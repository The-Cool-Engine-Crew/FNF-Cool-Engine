package funkin.transitions;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.group.FlxGroup;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.util.FlxTimer;
import flixel.math.FlxMath;
import flixel.graphics.FlxGraphic;
import haxe.Json;
import sys.FileSystem;

/**
 * Sistema de transición con stickers — animación idéntica al V-Slice (FNF base).
 *
 * APARICIÓN (regenStickers):
 *   • Grid que cubre toda la pantalla usando frameWidth * 0.5 de avance horizontal
 *     y 70-120 px de avance vertical (igual que v-slice).
 *   • Se mezcla el orden aleatoriamente.
 *   • Se añade un sticker CENTRAL al final (ángulo 0, escala pop grande).
 *   • timing = remapToRange(ind, 0, N, 0, 0.9).
 *   • Al aparecer: visible=true → delay 0-2 frames → snap de escala (0.97-1.02).
 *   • El último sticker siempre usa 2 frames de delay y escala 1.08 → dispara callback.
 *
 * DESAPARICIÓN (degenStickers):
 *   • Cada sticker se oculta con visible=false usando su mismo timing de aparición.
 *   • Sin tweens de posición ni escala (igual que v-slice).
 *
 * SKIN POR WEEK / SONG:
 *   Llama StickerTransition.setCurrentContext(weekIdx, songName) antes de start().
 *   El campo stickerMode del config decide cómo elegir el set:
 *     "week"   → weekStickerSets[weekIdx]  (default)
 *     "song"   → songStickerSets[songName]
 *     "random" → set aleatorio
 */
class StickerTransition
{
	// ── Config ────────────────────────────────────────────────────────────────

	public static var enabled:Bool = true;

	public static var configPath(get, set):String;
	static var _configPath:Null<String> = null;
	static function get_configPath():String
	{
		if (_configPath == null)
			_configPath = Paths.resolveWrite('data/stickers/sticker-config.json');
		return _configPath;
	}
	static function set_configPath(v:String):String return _configPath = v;

	private static var config:StickerConfig;

	// ── Contexto para elegir skin ─────────────────────────────────────────────

	/** Índice de la semana actual (StoryMenu o Freeplay). */
	public static var currentWeek:Int = -1;
	/** Nombre de canción actual en lowercase. */
	public static var currentSong:String = "";

	/**
	 * Establece el contexto de week/song ANTES de llamar start().
	 * El motor elegirá el set correcto según stickerMode del config.
	 *
	 * @param weekIdx  Índice de week. -1 = no especificado.
	 * @param songName Nombre de la canción (lowercase). Opcional.
	 */
	public static function setCurrentContext(weekIdx:Int, ?songName:String):Void
	{
		currentWeek = weekIdx;
		currentSong = songName != null ? songName.toLowerCase() : "";
	}

	// ── Estado interno ────────────────────────────────────────────────────────

	private static var onComplete:Void->Void;
	private static var isPlaying:Bool = false;

	private static var transitionSprite:Null<StickerTransitionContainer> = null;

	private static var graphicsCache:Map<String, FlxGraphic> = new Map();
	private static var cacheLoaded:Bool = false;

	/**
	 * timing de aparición por sticker — reutilizado en disipación.
	 * Público para que StickerTransitionContainer pueda leerlo.
	 */
	public static var stickerTimings:Map<FlxSprite, Float> = new Map();

	private static var activeTimers:Array<FlxTimer> = [];

	// ═════════════════════════════════════════════════════════════════════════
	//  API PÚBLICA
	// ═════════════════════════════════════════════════════════════════════════

	public static function init():Void
	{
		loadConfig();
		preloadGraphics();
		if (transitionSprite == null)
			transitionSprite = new StickerTransitionContainer();
		trace('[StickerTransition] System initialized (mode: ${config?.stickerMode ?? "random"})');
	}

	/**
	 * Inicia la transición — llena la pantalla de stickers.
	 * El callback se dispara cuando el último sticker aparece.
	 *
	 * @param callback  Función a llamar cuando los stickers cubren la pantalla.
	 * @param customSet Override manual del nombre del set.
	 */
	public static function start(?callback:Void->Void, ?customSet:String):Void
	{
		if (!enabled) return;

		if (isPlaying)
		{
			trace('[StickerTransition] Already playing — cancelling first');
			cancel();
		}

		if (config == null) loadConfig();
		if (!cacheLoaded) preloadGraphics();
		if (transitionSprite == null)
			transitionSprite = new StickerTransitionContainer();

		isPlaying   = true;
		onComplete  = callback;

		trace('[StickerTransition] ===== START =====');
		transitionSprite.insert();

		var selectedSet = _pickSet(customSet);
		trace('[StickerTransition] Set: ${selectedSet.name}');
		_regenStickers(selectedSet);
	}

	/**
	 * Oculta los stickers una vez que el nuevo state fue creado.
	 * Los stickers desaparecen con visible=false en el mismo timing con que
	 * aparecieron (comportamiento idéntico al v-slice degenStickers).
	 *
	 * @param onFinished Callback cuando todos los stickers desaparecieron.
	 */
	public static function clearStickers(?onFinished:Void->Void):Void
	{
		if (!isPlaying)
		{
			if (onFinished != null) onFinished();
			return;
		}

		trace('[StickerTransition] ===== CLEAR (degen) =====');
		cancelAllTimers();

		if (transitionSprite != null)
		{
			transitionSprite.degenStickers(function()
			{
				finish();
				if (onFinished != null) onFinished();
			});
		}
		else
		{
			finish();
			if (onFinished != null) onFinished();
		}
	}

	public static function isActive():Bool return isPlaying;

	public static function cancel():Void
	{
		if (!isPlaying) return;
		trace('[StickerTransition] Cancelled');
		finish();
	}

	/**
	 * Marks the sticker cache as dirty so it is rebuilt on the next transition.
	 * Only destroys the cached FlxGraphics when no transition is currently active;
	 * if a transition is in progress its sprites are still using those bitmaps —
	 * destroying them now would cause blank textures mid-animation.
	 */
	public static function invalidateCache():Void
	{
		if (transitionSprite == null)
		{
			// Safe to destroy — no sprite is currently rendering these graphics.
			for (g in graphicsCache)
			{
				if (g == null) continue;
				try { FlxG.bitmap.removeByKey(g.key); g.destroy(); } catch (_:Dynamic) {}
			}
		}
		// If a transition IS active we deliberately skip the destroy: the sprites
		// hold strong useCount references and will release them when the transition
		// finishes. clearUnused() will then collect the orphaned graphics naturally
		// on the next preStateSwitch, because we restore destroyOnNoUse=true below
		// via preloadGraphics() on next load (or they become eligible immediately
		// since useCount will drop to 0 once the transition completes).
		graphicsCache.clear();
		cacheLoaded = false;
		trace('[StickerTransition] Cache invalidated');
	}

	public static function reloadConfig():Void
	{
		loadConfig();
		preloadGraphics();
	}

	public static function playRandomSound():Void
	{
		if (config == null || config.sounds == null || config.sounds.length == 0) return;
		var name = FlxG.random.getObject(config.sounds);
		try { FlxG.sound.play(Paths.sound('${config.soundPath}/$name'), FlxG.random.float(0.9, 1.3)); }
		catch (_:Dynamic) {}
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  INTERNOS — generación y disipación
	// ═════════════════════════════════════════════════════════════════════════

	/**
	 * Genera el grid de stickers al estilo v-slice y programa su aparición.
	 */
	private static function _regenStickers(stickerSet:StickerSet):Void
	{
		transitionSprite.clearStickers();
		stickerTimings.clear();
		cancelAllTimers();

		var regularStickers:Array<FlxSprite> = [];

		// ── Paso 1: grid que cubre la pantalla ────────────────────────────────
		var xPos:Float = -100;
		var yPos:Float = -100;

		while (yPos <= FlxG.height)
		{
			var sticker = _makeSprite(stickerSet);
			if (sticker == null) break;

			sticker.x = xPos;
			sticker.y = yPos;
			sticker.angle = FlxG.random.int(-60, 70);

			xPos += sticker.frameWidth * 0.65;
			regularStickers.push(sticker);
			transitionSprite.addSticker(sticker);

			if (xPos >= FlxG.width)
			{
				if (yPos > FlxG.height) break;
				xPos = -100;
				yPos += FlxG.random.float(90, 140);
			}
		}

		// ── Paso 2: mezclar orden ─────────────────────────────────────────────
		FlxG.random.shuffle(regularStickers);

		// ── Paso 3: sticker central (siempre el último en aparecer) ──────────
		var centerSticker = _makeSprite(stickerSet);
		if (centerSticker != null)
		{
			centerSticker.angle = 0;
			centerSticker.updateHitbox();
			centerSticker.x = (FlxG.width  - centerSticker.frameWidth)  * 0.5;
			centerSticker.y = (FlxG.height - centerSticker.frameHeight) * 0.5;
			transitionSprite.addSticker(centerSticker);
		}

		var allStickers = regularStickers.slice(0);
		if (centerSticker != null) allStickers.push(centerSticker);

		var totalN = allStickers.length;
		trace('[StickerTransition] $totalN stickers generated');

		// ── Paso 4: programar aparición con timing escalonado ─────────────────
		for (ind in 0...totalN)
		{
			var sticker = allStickers[ind];
			var timing  = FlxMath.remapToRange(ind, 0, totalN, 0, 0.9);
			var isLast  = (ind == totalN - 1);

			stickerTimings.set(sticker, timing); // guardado para degen

			var t = new FlxTimer(FlxTimer.globalManager);
			activeTimers.push(t);

			t.start(timing, function(_:FlxTimer)
			{
				if (sticker == null || !sticker.exists) return;

				sticker.visible = true;
				playRandomSound();

				// v-slice: 0-2 frames extra antes del snap de escala
				var frameDelay = isLast ? 2 : FlxG.random.int(0, 2);
				var frameTime  = (1.0 / 24.0) * frameDelay;

				var snapAndCallback = function()
				{
					if (sticker != null && sticker.exists)
					{
						var snap:Float = isLast ? 1.08 : FlxG.random.float(0.97, 1.02);
						sticker.scale.set(snap, snap);
						sticker.updateHitbox();
					}
					if (isLast && onComplete != null)
						onComplete();
				};

				if (frameTime > 0)
				{
					var ft = new FlxTimer(FlxTimer.globalManager);
					activeTimers.push(ft);
					ft.start(frameTime, function(_:FlxTimer) snapAndCallback());
				}
				else
				{
					snapAndCallback();
				}
			});
		}
	}

	/**
	 * Crea un FlxSprite para el sticker (sin posición ni ángulo — los asigna _regenStickers).
	 * Empieza invisible con escala 1×1.
	 */
	private static function _makeSprite(set:StickerSet):Null<FlxSprite>
	{
		var name     = FlxG.random.getObject(set.stickers);
		var cacheKey = '${set.path}/$name';

		var graphic = graphicsCache.get(cacheKey);
		if (graphic == null || graphic.bitmap == null)
		{
			trace('[StickerTransition] ⚠ Not cached: $cacheKey');
			return null;
		}

		var sticker = new FlxSprite();
		try { sticker.loadGraphic(graphic); }
		catch (e:Dynamic)
		{
			trace('[StickerTransition] ⚠ loadGraphic failed ($cacheKey): $e');
			graphicsCache.remove(cacheKey);
			cacheLoaded = false;
			sticker.destroy();
			return null;
		}

		sticker.visible  = false;
		sticker.scale.set(1, 1);
		sticker.updateHitbox();
		sticker.scrollFactor.set(0, 0);
		return sticker;
	}

	// ── Selección de set ──────────────────────────────────────────────────────

	private static function _pickSet(?customSet:String):StickerSet
	{
		// 1. Override manual
		if (customSet != null)
			for (set in config.stickerSets)
				if (set.name == customSet) return set;

		// 2. Por contexto
		var mode = config.stickerMode ?? "week";

		if (mode == "week" && currentWeek >= 0 && config.weekStickerSets != null)
		{
			var setName:String = Reflect.field(config.weekStickerSets, Std.string(currentWeek));
			if (setName != null)
				for (set in config.stickerSets)
					if (set.name == setName) return set;
		}
		else if (mode == "song" && currentSong != "" && config.songStickerSets != null)
		{
			var setName:String = Reflect.field(config.songStickerSets, currentSong);
			if (setName != null)
				for (set in config.stickerSets)
					if (set.name == setName) return set;
		}

		// 3. Aleatorio
		return FlxG.random.getObject(config.stickerSets);
	}

	// ── Finish / cancel / timers ──────────────────────────────────────────────

	private static function finish():Void
	{
		isPlaying = false;
		activeTimers = [];
		if (transitionSprite != null) transitionSprite.clear();
		stickerTimings.clear();
		onComplete = null;
		trace('[StickerTransition] ===== FINISHED =====');
	}

	private static function cancelAllTimers():Void
	{
		for (t in activeTimers) if (t != null && t.active) t.cancel();
		activeTimers = [];
	}

	// ── Config ────────────────────────────────────────────────────────────────

	private static function loadConfig():Void
	{
		try
		{
			var jsonPath = configPath;
			#if sys
			if (!FileSystem.exists(jsonPath)) { config = _defaultConfig(); return; }
			#end
			config = Json.parse(sys.io.File.getContent(jsonPath));
			trace('[StickerTransition] Config loaded (mode: ${config.stickerMode ?? "week"})');
		}
		catch (e:Dynamic)
		{
			trace('[StickerTransition] Config error: $e');
			config = _defaultConfig();
		}
	}

	private static function preloadGraphics():Void
	{
		if (cacheLoaded || config == null) return;
		var loaded = 0; var failed = 0;
		for (set in config.stickerSets)
		{
			for (sn in set.stickers)
			{
				var key = '${set.path}/$sn';
				if (graphicsCache.exists(key)) continue;
				try
				{
					var resolved = Paths.image(key);
					var bmp:openfl.display.BitmapData = null;
					#if sys
					if (sys.FileSystem.exists(resolved))
						bmp = openfl.display.BitmapData.fromFile(resolved);
					#else
					bmp = openfl.Assets.getBitmapData(resolved);
					#end
					if (bmp == null) { failed++; continue; }
					var g = FlxGraphic.fromBitmapData(bmp);
					g.persist          = true;
					// FIX: clearUnused() destroys FlxGraphics with useCount==0 AND
					// destroyOnNoUse==true. Between transitions sticker sprites are
					// gone (useCount drops to 0) but cacheLoaded remains true, so
					// preloadGraphics() is never re-run — the next transition calls
					// _makeSprite() with a dead FlxGraphic (bitmap==null) and gets
					// null back, producing blank/missing stickers. Setting this to
					// false keeps the graphics alive across the gap between transitions;
					// they are only truly destroyed in invalidateCache().
					g.destroyOnNoUse   = false;
					graphicsCache.set(key, g);
					loaded++;
				}
				catch (e:Dynamic) { failed++; }
			}
		}
		cacheLoaded = true;
		trace('[StickerTransition] Cache: $loaded ok / $failed failed');
	}

	private static function _defaultConfig():StickerConfig
	{
		return {
			enabled: true,
			stickerMode: "week",
			stickerSets: [
				{name:"stickers-set-1", path:"transitionSwag/stickers-set-1",
				 stickers:["bfSticker3","picoSticker1","dadSticker1","gfSticker1","momSticker1","monsterSticker1"]},
				{name:"stickers-set-2", path:"transitionSwag/stickers-set-2",
				 stickers:["bfSticker3","picoSticker1","dadSticker1"]}
			],
			weekStickerSets: {"0":"stickers-set-1","1":"stickers-set-1","2":"stickers-set-2",
			                  "3":"stickers-set-2","4":"stickers-set-1","5":"stickers-set-2",
			                  "6":"stickers-set-1","7":"stickers-set-2"},
			songStickerSets: {},
			soundPath: "stickersounds/keys",
			sounds: ["keyClick1","keyClick2","keyClick3","keyClick4"],
			stickersPerWave: 4, totalWaves: 4, delayBetweenStickers: 0.0,
			delayBetweenWaves: 0.1, minScale: 0.85, maxScale: 1.0,
			animationDuration: 0.25, stickerLifetime: 999
		};
	}
}

// ═════════════════════════════════════════════════════════════════════════════
//  StickerTransitionContainer — capa OpenFL que renderiza los stickers
// ═════════════════════════════════════════════════════════════════════════════

@:access(flixel.FlxCamera)
class StickerTransitionContainer extends openfl.display.Sprite
{
	public var stickersCamera:FlxCamera;
	public var grpStickers:FlxTypedGroup<FlxSprite>;

	private var dissipationTimers:Array<FlxTimer> = [];

	// FIX Bug 3: store the gameResized handler so it can be removed in clear().
	// The anonymous lambda `(_, _) -> onResize()` was added but never removed,
	// retaining a strong reference to `this` in FlxG.signals.gameResized for
	// the lifetime of the game — preventing GC of every StickerTransitionContainer
	// instance ever created.
	private var _onResizeHandler:(Int, Int) -> Void;

	public function new():Void
	{
		super();
		visible = false;

		stickersCamera = new FlxCamera();
		stickersCamera.bgColor = 0x00000000;
		addChild(stickersCamera.flashSprite);

		grpStickers = new FlxTypedGroup<FlxSprite>();
		grpStickers.camera = stickersCamera;

		_onResizeHandler = (_, _) -> onResize();
		FlxG.signals.gameResized.add(_onResizeHandler);
		scrollRect = new openfl.geom.Rectangle();
		onResize();
	}

	public function update(elapsed:Float):Void
	{
		stickersCamera.visible = visible;
		if (!visible) return;
		grpStickers?.update(elapsed);
		stickersCamera.update(elapsed);
		stickersCamera?.clearDrawStack();
		stickersCamera?.canvas?.graphics.clear();
		grpStickers?.draw();
		stickersCamera.render();
	}

	public function insert():Void
	{
		FlxG.addChildBelowMouse(this, 9999);
		visible = true;
		onResize();
		FlxG.signals.preUpdate.add(_tick);
	}

	private function _tick():Void update(FlxG.elapsed);

	public function clear():Void
	{
		FlxG.signals.preUpdate.remove(_tick);
		// FIX Bug 3: remove the gameResized handler registered in new().
		// Without this, each StickerTransitionContainer instance stayed rooted
		// in FlxG.signals forever — one retained reference per transition played.
		if (_onResizeHandler != null)
		{
			FlxG.signals.gameResized.remove(_onResizeHandler);
			_onResizeHandler = null;
		}
		FlxG.removeChild(this);
		visible = false;
		clearStickers();
		stickersCamera?.clearDrawStack();
		stickersCamera?.canvas?.graphics.clear();
	}

	public function onResize():Void
	{
		x = y = 0; scaleX = scaleY = 1;
		if (FlxG.camera != null && FlxG.camera._scrollRect != null
			&& FlxG.camera._scrollRect.scrollRect != null)
		{
			__scrollRect.setTo(0, 0,
				FlxG.camera._scrollRect.scrollRect.width,
				FlxG.camera._scrollRect.scrollRect.height);
		}
		else if (FlxG.width > 0)
		{
			__scrollRect.setTo(0, 0, FlxG.width, FlxG.height);
		}
		stickersCamera.onResize();
		stickersCamera._scrollRect.scrollRect = scrollRect;
	}

	public function addSticker(s:FlxSprite):Void grpStickers.add(s);

	public function clearStickers():Void
	{
		_cancelDissipation();
		if (grpStickers != null)
		{
			for (s in grpStickers.members)
			{
				if (s == null) continue;
				FlxTween.cancelTweensOf(s);
				FlxTween.cancelTweensOf(s.scale);
				s.destroy();
			}
			grpStickers.clear();
		}
	}

	/**
	 * Disipación v-slice: cada sticker se hace invisible con visible=false
	 * usando el mismo timing con que apareció (0 → 0.9 s).
	 */
	public function degenStickers(onComplete:Void->Void):Void
	{
		_cancelDissipation();

		if (grpStickers == null || grpStickers.members.length == 0)
		{
			if (onComplete != null) onComplete();
			return;
		}

		var total = 0;
		for (s in grpStickers.members) if (s != null && s.exists) total++;
		if (total == 0) { if (onComplete != null) onComplete(); return; }

		var done = 0;

		for (sticker in grpStickers.members)
		{
			if (sticker == null || !sticker.exists) continue;

			var timing:Float = StickerTransition.stickerTimings.exists(sticker)
				? StickerTransition.stickerTimings.get(sticker)
				: 0.0;

			var t = new FlxTimer(FlxTimer.globalManager);
			dissipationTimers.push(t);

			var captured = sticker;
			var capturedTotal = total;

			t.start(timing, function(_:FlxTimer)
			{
				if (captured != null && captured.exists)
					captured.visible = false;
				StickerTransition.playRandomSound();
				done++;
				if (done >= capturedTotal && onComplete != null)
					onComplete();
			});
		}
	}

	private function _cancelDissipation():Void
	{
		for (t in dissipationTimers) if (t != null && t.active) t.cancel();
		dissipationTimers = [];
	}
}

// ═════════════════════════════════════════════════════════════════════════════
//  Typedefs
// ═════════════════════════════════════════════════════════════════════════════

typedef StickerConfig =
{
	var enabled:Bool;
	var stickerSets:Array<StickerSet>;
	var soundPath:String;
	var sounds:Array<String>;
	// Legacy (compatible con configs anteriores)
	var stickersPerWave:Int;
	var totalWaves:Int;
	var delayBetweenStickers:Float;
	var delayBetweenWaves:Float;
	var minScale:Float;
	var maxScale:Float;
	var animationDuration:Float;
	var stickerLifetime:Float;
	// Nuevos campos para selección de skin por contexto
	@:optional var stickerMode:String;        // "week" | "song" | "random"
	@:optional var weekStickerSets:Dynamic;   // { "0": "stickers-set-1", ... }
	@:optional var songStickerSets:Dynamic;   // { "bopeebo": "stickers-set-2", ... }
}

typedef StickerSet =
{
	var name:String;
	var path:String;
	var stickers:Array<String>;
}
