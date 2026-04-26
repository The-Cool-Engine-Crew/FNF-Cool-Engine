package funkin.gameplay;

import flixel.FlxG;

/**
 * GameState - Gestión centralizada del estado del juego.
 * Ahora usa RatingManager para soportar ratings softcodeados.
 */
class GameState
{
	// === SINGLETON ===
	private static var _instance:GameState;

	public static function get():GameState
	{
		if (_instance == null)
			_instance = new GameState();
		return _instance;
	}

	// === STATS ===
	public var score:Int = 0;
	public var combo:Int = 0;
	public var maxCombo:Int = 0;
	public var health:Float = 1.0;
	public var accuracy:Float = 0.00;

	/**
	 * True if the score of this game exceeds the previously saved high score.
     * Set in PlayState just before calling Highscore.saveScore().
	 */
	public var isNewHighscore:Bool = false;

	// === COUNTERS LEGACY (compatibilidad con scripts/HUD existentes) ===
	public var sicks:Int = 0;
	public var goods:Int = 0;
	public var bads:Int = 0;
	public var shits:Int = 0;
	public var misses:Int = 0;

	/**
	 * Contador genérico por nombre de rating.
	 * Incluye los 4 legacy + cualquier rating custom del mod.
	 * Example: ratingCounts['perfect'], ratingCounts['sick'], etc.
	 */
	public var ratingCounts:Map<String, Int> = new Map();

	// === INTERNAL ===
	private var totalNotesHit:Float = 0;
	// public(default,null): los sistemas externos (ScoreManager.getHUDText, HUD)
	// necesitan saber si hay notas jugadas para mostrar "N/A" o un porcentaje real.
	// Solo GameState escribe este valor — de ahí el null setter.
	public var totalNotesPlayed(default, null):Int = 0;

	// === CONSTANTS ===
	private static inline var MAX_HEALTH:Float = 2.0;
	private static inline var MIN_HEALTH:Float = 0.0;

	public static var listArtist:String = 'unknown';
	public static var deathCounter:Int = 0;

	public function new()
	{
		reset();
	}

	// ─── Reset ───────────────────────────────────────────────────────────────

	public function reset():Void
	{
		score     = 0;
		combo     = 0;
		maxCombo  = 0;
		health    = 1.0;
		accuracy  = 0.0;
		sicks     = 0;
		goods     = 0;
		bads      = 0;
		shits     = 0;
		misses    = 0;
		isNewHighscore   = false;
		totalNotesHit    = 0;
		totalNotesPlayed = 0;
		ratingCounts.clear();
		// Sembrar contadores para ratings conocidos (evita null-check en HUD)
		for (r in RatingManager.ratings)
			ratingCounts.set(r.name, 0);
	}

	// ─── Note hit ────────────────────────────────────────────────────────────

	/**
	 * Procesar hit de nota.
	 * Retorna el nombre del rating obtenido (ej. "sick", "perfect", "good"…).
	 */
	public function processNoteHit(noteDiff:Float, isSustain:Bool):String
	{
		if (isSustain)
		{
			// Los sustains no afectan al combo ni al rating visual.
			// Se puntúan como el rating más bajo que no rompe combo.
			totalNotesHit += 1.0;
			totalNotesPlayed++;
			updateAccuracy();
			score += 50; // puntuación fija para sustains (ajustable)
			return RatingManager.topRatingName; // devolver 'sick' / top rating para compatibilidad
		}

		var ratingData = RatingManager.getRating(noteDiff);
		if (ratingData == null)
		{
			// noteDiff > missWindow — debería haberlo capturado NoteManager,
			// pero si llega aquí lo tratamos como el peor rating.
			ratingData = RatingManager.ratings[RatingManager.ratings.length - 1];
		}

		var name = ratingData.name;

		// ── Counters ──────────────────────────────────────────────────────────
		ratingCounts.set(name, (ratingCounts.get(name) ?? 0) + 1);

		// Legacy compat (solo los 4 estándar de FNF)
		switch (name)
		{
			case 'sick':  sicks++;
			case 'good':  goods++;
			case 'bad':   bads++;
			case 'shit':  shits++;
			// ratings custom no tienen variable propia, solo ratingCounts
		}

		// ── Combo ─────────────────────────────────────────────────────────────
		if (ratingData.breakCombo)
			combo = 0;
		else
		{
			combo++;
			if (combo > maxCombo) maxCombo = combo;
		}

		// ── Accuracy ─────────────────────────────────────────────────────────
		totalNotesHit += ratingData.accuracyWeight;
		totalNotesPlayed++;
		updateAccuracy();

		// ── Score ─────────────────────────────────────────────────────────────
		score += ratingData.score;

		return name;
	}

	// ─── Miss ────────────────────────────────────────────────────────────────

	public function processMiss():Void
	{
		misses++;
		combo = 0;
		totalNotesPlayed++;
		updateAccuracy();
	}

	// ─── Health ──────────────────────────────────────────────────────────────

	public function modifyHealth(amount:Float):Void
	{
		health = Math.max(MIN_HEALTH, Math.min(MAX_HEALTH, health + amount));
	}

	public function isDead():Bool
		return health <= MIN_HEALTH;

	// ─── Accuracy ────────────────────────────────────────────────────────────

	private function updateAccuracy():Void
	{
		accuracy = totalNotesPlayed > 0
			? Math.fround((totalNotesHit / totalNotesPlayed) * 10000) / 100
			: 0.0;
	}

	public function getAccuracyString():String
		return totalNotesPlayed > 0 ? Std.string(accuracy) + '%' : 'N/A';

	// ─── FC / Sick detection ─────────────────────────────────────────────────

	/**
	 * Full Combo: sin misses y sin ningún rating que rompa combo.
	 * Funciona con ratings custom que tengan breakCombo:true.
	 */
	public function isFullCombo():Bool
	{
		if (misses > 0) return false;
		for (r in RatingManager.ratings)
			if (r.breakCombo && (ratingCounts.get(r.name) ?? 0) > 0)
				return false;
		return true;
	}

	/**
	 * Sick/Perfect: solo hits del rating más estricto (menor window).
	 * Con un ratings.json custom que tenga "perfect" antes de "sick",
	 * isSickMode() devuelve true solo si TODOS son "perfect".
	 */
	public function isSickMode():Bool
	{
		if (!isFullCombo()) return false;
		for (r in RatingManager.ratings)
		{
			// El primer rating (menor window) es el "top" — se permite
			if (r.name == RatingManager.topRatingName) continue;
			if ((ratingCounts.get(r.name) ?? 0) > 0) return false;
		}
		return true;
	}

	// ─── Singleton destroy ────────────────────────────────────────────────────

	public static function destroy():Void
		_instance = null;
}