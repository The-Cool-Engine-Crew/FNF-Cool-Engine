package funkin.gameplay.objects.hud;

import flixel.FlxG;

/**
 * ScoreManager v2 — gestión de puntuación y estadísticas.
 *
 * ─── Fix crítico vs v1 ────────────────────────────────────────────────────────
 *
 *  v1: Las constantes de scoring estaban marcadas como `static inline`.
 *  Problema: `inline` hace que el compilador REEMPLACE cada referencia con el
 *  valor literal en tiempo de compilación — `Reflect.setField()` nunca las toca
 *  porque no existen como campo en el binario.
 *
 *  v2: Se eliminó `inline` de las variables de configuración (SICK_WINDOW, etc.)
 *  para que `score.setWindow()` y `score.setPoints()` del ScriptAPI funcionen.
 *
 * @author Cool Engine Team
 * @version 2.0.0
 */
@:keep // Evitar que DCE elimine campos no referenciados directamente
class ScoreManager
{
	// ── Estadísticas de jugabilidad ────────────────────────────────────────────

	public var score      : Int   = 0;
	public var combo      : Int   = 0;
	public var maxCombo   : Int   = 0;
	public var misses     : Int   = 0;

	public var sicks  : Int = 0;
	public var goods  : Int = 0;
	public var bads   : Int = 0;
	public var shits  : Int = 0;

	public var accuracy        : Float = 0;
	public var totalNotesHit   : Float = 0;
	public var totalNotesPlayed: Int   = 0;

	public var fullCombo : Bool = true;
	public var sickCombo : Bool = true;

	// ── Configuración de scoring ──────────────────────────────────────────────
	// ¡IMPORTANTE! NO usar `inline` aquí — los scripts los modifican via Reflect.
	// `inline` = el compilador incrusta el valor en cada callsite → Reflect no ve el campo.

	public static var SICK_SCORE  : Int = 350;
	public static var GOOD_SCORE  : Int = 200;
	public static var BAD_SCORE   : Int = 100;
	public static var SHIT_SCORE  : Int = 50;
	public static var MISS_PENALTY: Int = -10;

	// Timing windows (ms) — también sin inline para permitir override desde scripts
	public static var SICK_WINDOW  : Float = 45;
	public static var GOOD_WINDOW  : Float = 90;
	public static var BAD_WINDOW   : Float = 135;
	public static var SHIT_WINDOW  : Float = 166;

	// ── Multiplicadores de combo ──────────────────────────────────────────────
	// Sí pueden ser inline porque los scripts no los modifican directamente
	static inline var COMBO_1 : Float = 1.0;
	static inline var COMBO_2 : Float = 1.1; // 10 combo
	static inline var COMBO_3 : Float = 1.2; // 25 combo
	static inline var COMBO_4 : Float = 1.3; // 50 combo

	// ── Constructor ───────────────────────────────────────────────────────────

	public function new()
	{
		reset();
	}

	// ── Gestión ───────────────────────────────────────────────────────────────

	/** Reinicia todas las estadísticas para una nueva partida. */
	public function reset():Void
	{
		score           = 0;
		combo           = 0;
		maxCombo        = 0;
		misses          = 0;
		sicks = goods = bads = shits = 0;
		accuracy        = 0;
		totalNotesHit   = 0;
		totalNotesPlayed = 0;
		fullCombo       = true;
		sickCombo       = true;
	}

	/**
	 * Procesa un hit y devuelve el rating correspondiente.
	 * El `diff` es la diferencia absoluta en ms entre el hit y el strumTime.
	 * Para sustains, usar `isSustain=true` (no suma al combo ni accuracy).
	 */
	public function processNoteHit(diff:Float, isSustain:Bool = false):String
	{
		final rating = getRating(diff);

		if (!isSustain)
		{
			combo++;
			if (combo > maxCombo) maxCombo = combo;

			totalNotesPlayed++;
			totalNotesHit += getNoteHitValue(rating);

			switch (rating)
			{
				case 'sick':  sicks++;
				case 'good':  goods++;
				case 'bad':   bads++;
				case 'shit':  shits++;
			}

			score += getScore(rating, combo);
			recalcAccuracy();
		}

		return rating;
	}

	/** Procesa un miss. */
	public function processMiss():Void
	{
		fullCombo = false;
		sickCombo = false;
		combo     = 0;
		misses++;
		totalNotesPlayed++;
		totalNotesHit += 0.0; // miss = 0 en accuracy
		score += MISS_PENALTY;
		if (score < 0) score = 0;
		recalcAccuracy();
	}

	/** Modifica la salud del personaje. Rango: 0.0 – 2.0. */
	public function modifyHealth(delta:Float):Void
	{
		// Delegado al PlayState via getInstance()
		final ps = funkin.gameplay.PlayState.instance;
		if (ps != null)
		{
			ps.health = flixel.math.FlxMath.bound(ps.health + delta, 0, 2);
		}
	}

	// ── Helpers ───────────────────────────────────────────────────────────────

	/** Clasifica `diff` (ms absolutos) en un rating. */
	public static function getRating(diff:Float):String
	{
		if (diff <= SICK_WINDOW)  return 'sick';
		if (diff <= GOOD_WINDOW)  return 'good';
		if (diff <= BAD_WINDOW)   return 'bad';
		return 'shit';
	}

	/**
	 * Calcula los puntos para un hit con el rating y combo dados.
	 * Aplica multiplicador de combo para combos largos.
	 */
	public static function getScore(rating:String, combo:Int):Int
	{
		final base = switch (rating)
		{
			case 'sick': SICK_SCORE;
			case 'good': GOOD_SCORE;
			case 'bad':  BAD_SCORE;
			default:     SHIT_SCORE;
		};
		return Math.round(base * getComboMultiplier(combo));
	}

	/** Multiplicador de combo: 1.0 base, hasta 1.3 en 50+ combo. */
	static function getComboMultiplier(combo:Int):Float
	{
		if (combo >= 50) return COMBO_4;
		if (combo >= 25) return COMBO_3;
		if (combo >= 10) return COMBO_2;
		return COMBO_1;
	}

	/**
	 * Valor de accuracy por rating:
	 * sick=1.0, good=0.75, bad=0.5, shit=0.25, miss=0.0
	 */
	static function getNoteHitValue(rating:String):Float
	{
		return switch (rating)
		{
			case 'sick': 1.00;
			case 'good': 0.75;
			case 'bad':  0.50;
			case 'shit': 0.25;
			default:     0.00;
		};
	}

	function recalcAccuracy():Void
	{
		accuracy = totalNotesPlayed > 0
			? Math.round((totalNotesHit / totalNotesPlayed) * 10000) / 100
			: 0;
	}

	public function getHUDText(gameState:funkin.gameplay.GameState):String
	{
		// Fix: leer FC/SC desde GameState, no desde los campos locales del ScoreManager.
		// El ScoreManager del script nunca recibe processNoteHit/processMiss,
		// así que this.fullCombo / this.sickCombo siempre serían `true`.
		var fcText = gameState.isFullCombo() ? ' [FC]' : '';
		var scText = gameState.isSickMode()  ? ' [SC]' : '';

		// Fix accuracy N/A: comparar gameState.totalNotesPlayed, NO this.totalNotesPlayed.
		// this.totalNotesPlayed es siempre 0 en el ScoreManager de display porque
		// los hits los registra GameState.processNoteHit(), no ScoreManager.processNoteHit().
		final accText = gameState.totalNotesPlayed > 0 ? '${gameState.accuracy}%' : 'N/A';
		return 'Score: ${gameState.score} - Misses: ${gameState.misses}$fcText$scText - Accuracy: $accText';
	}

	/** Resumen de estadísticas para debug. */
	public function getSummary():String
	{
		final accText = totalNotesPlayed > 0 ? '${accuracy}%' : 'N/A';
		return 'Score=$score  Combo=$combo  MaxCombo=$maxCombo  '
		     + 'Misses=$misses  Acc=$accText  '
		     + 'Sicks=$sicks  Goods=$goods  Bads=$bads  Shits=$shits';
	}
}
