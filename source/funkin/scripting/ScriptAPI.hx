package funkin.scripting;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.FlxObject;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.sound.FlxSound;
import funkin.transitions.StateTransition;
import funkin.transitions.StickerTransition;
import funkin.scripting.ScriptableState.ScriptableSubState;
import funkin.addons.AddonManager;
import funkin.graphics.scene3d.Flx3DScene;
import funkin.graphics.scene3d.Flx3DSprite;
import funkin.graphics.scene3d.Flx3DObject;
import funkin.graphics.scene3d.Flx3DPrimitives;
import funkin.graphics.scene3d.Flx3DMesh;
import funkin.graphics.scene3d.Flx3DCamera;
import funkin.graphics.scene3d.Vec3;
import funkin.graphics.scene3d.Mat4;

#if HSCRIPT_ALLOWED
import hscript.Interp;
#end

using StringTools;

/**
 * ScriptAPI v6 — API COMPLETA expuesta a los scripts HScript.
 *
 * ─── Nuevas categorías en v6 ─────────────────────────────────────────────────
 *  `Mathf`         — proxy de funkin.data.Mathf (todas las funciones matemáticas)
 *  `CoolUtil`      — utilidades generales (texto, arrays, dificultad)
 *  `CameraUtil`    — control avanzado de cámaras y filtros/shaders en cámara
 *  `add` / `remove`— añadir/quitar sprites del juego directamente
 *  `stage`         — acceso completo al stage actual (elementos, grupos, sonidos)
 *  `noteManager`   — acceso al NoteManager del PlayState
 *  `input`         — acceso al InputHandler (teclas presionadas, held, etc.)
 *  `VideoManager`  — reproducción de vídeos/cutscenes desde script
 *  `Highscore`     — guardar y leer scores desde script
 *  `Ranking`       — letra de ranking del run actual
 *  `CharacterList` — listas de personajes y stages disponibles
 *  `PlayStateConfig` — constantes de timing, zoom, health, etc.
 *  `FlxAnimate`    — soporte de Texture Atlas animados
 *  `FlxSound`      — clase de sonido de Flixel
 *  `FlxCamera`     — clase de cámara de Flixel
 *  `FlxObject`     — objeto base de Flixel
 *  `FlxBackdrop`   — fondo de scroll infinito
 *  `transition`    — control de transiciones de pantalla
 *  `MetaData`      — metadatos de la canción actual
 *  `GlobalConfig`  — configuración global del engine
 *  `ScriptHandler` — acceso a scripts desde scripts (callOnScripts, etc.)
 *  `EventManager`  — sistema de eventos del chart
 *  `CharacterController` — controller de personajes del PlayState
 *  `CameraController`    — controller de cámara del PlayState
 *
 * ─── Compatibilidad total con v4/v5 ──────────────────────────────────────────
 *  Todos los objetos y funciones previos siguen disponibles sin cambios.
 *
 * @author Cool Engine Team
 * @version 6.0.0
 */
class ScriptAPI
{
	#if HSCRIPT_ALLOWED

	public static function expose(interp:Interp):Void
	{
		// ── v1-v5 (sin cambios de interfaz) ───────────────────────────────────
		exposeFlixel(interp);
		exposeGameplay(interp);
		exposeScoring(interp);
		exposeNoteTypes(interp);
		exposeStates(interp);
		exposeSignals(interp);
		exposeStorage(interp);
		exposeImport(interp);
		exposeMath(interp);
		exposeArray(interp);
		exposeShaders(interp);
		exposeWindow(interp);
		exposeVisibility(interp);
		exposeUtils(interp);
		exposeEvents(interp);
		exposeDebug(interp);
		exposeMod(interp);
		exposeCharacters(interp);
		exposeCamera(interp);
		exposeHUD(interp);
		exposeStrums(interp);
		exposeModChart(interp);
		// ── NUEVO v6 ──────────────────────────────────────────────────────────
		exposeMathf(interp);          // proxy completo de funkin.data.Mathf
		exposeCoolUtil(interp);       // utilidades generales
		exposeCameraUtil(interp);     // control avanzado de cámaras
		exposeAddRemove(interp);      // add() / remove() directos
		exposeStageAccess(interp);    // stage.getElement(), stage.getGroup(), etc.
		exposeNoteManagerAccess(interp); // noteManager completo
		exposeInputAccess(interp);    // input.held[], input.pressed[], etc.
		exposeVideoManager(interp);   // VideoManager cutscenes
		exposeHighscore(interp);      // Highscore.saveScore(), etc.
		exposeRanking(interp);        // Ranking.generateLetterRank()
		exposeCharacterList(interp);  // CharacterList.boyfriends, etc.
		exposePlayStateConfig(interp); // constantes de timing/zoom/health
		exposeTransition(interp);     // control de transiciones
		exposeControllers(interp);    // CharacterController y CameraController
		exposeMetaData(interp);       // MetaData de la canción
		exposeGlobalConfig(interp);   // GlobalConfig del engine
		exposeScriptHandler(interp);  // ScriptHandler (callOnScripts, etc.)
		exposeCountdown(interp);      // Countdown del PlayState
		exposeModPaths(interp);       // ModPaths completo
		// ── v7: Nuevas clases base de script ──────────────────────────────────
		exposeScriptTemplates(interp); // PlayStateScript, CharacterScript, StateScript
		// ── v8: Acceso directo a todos los states (igual que Haxe normal) ───
		exposeStatesAndCasting(interp);
		// ── v9: Sistema 3D y AddonManager ─────────────────────────────────────
		expose3D(interp);             // Flx3DSprite, Flx3DScene, primitivas GPU, etc.
		exposeAddonManager(interp);   // AddonManager + sistemas registrados por addons
		// ── v10: Subtítulos ────────────────────────────────────────────────────
		exposeSubtitles(interp);      // subtitle.show(), subtitle.hide(), etc.

		// ── Wildcard import registry ──────────────────────────────────────────
		// Index all class references now in interp so that scripts can use
		// `import flixel.*;` or `import funkin.gameplay.*;` etc.
		ScriptHandler.buildRegistryFromInterp(interp);
	}

	// ─── Flixel core ──────────────────────────────────────────────────────────

	static function exposeFlixel(interp:Interp):Void
	{
		interp.variables.set('FlxG',           FlxG);
		interp.variables.set('FlxSprite',      FlxSprite);
		interp.variables.set('FlxTween',       FlxTween);
		interp.variables.set('FlxEase',        _flxEaseProxy());
		interp.variables.set('FlxColor',       _flxColorProxy());
		interp.variables.set('FlxTimer',       FlxTimer);
		interp.variables.set('FlxSound',       FlxSound);
		interp.variables.set('FlxCamera',      FlxCamera);
		interp.variables.set('FlxObject',      FlxObject);
		interp.variables.set('FunkinSprite',   animationdata.FunkinSprite);

		// Tipos adicionales
		interp.variables.set('FlxText',          flixel.text.FlxText);
		interp.variables.set('FlxGroup',         flixel.group.FlxGroup);
		interp.variables.set('FlxSpriteGroup',   flixel.group.FlxSpriteGroup);
		interp.variables.set('FlxTypedGroup',    flixel.group.FlxGroup.FlxTypedGroup);

		// FlxAnimate (Texture Atlas)
		try {
			final flxAnimate = Type.resolveClass('flxanimate.FlxAnimate');
			if (flxAnimate != null) interp.variables.set('FlxAnimate', flxAnimate);
		} catch(_) {}

		// FlxBackdrop (fondo de scroll infinito) — en flixel-addons si existe
		try {
			final backdrop = Type.resolveClass('flixel.addons.display.FlxBackdrop');
			if (backdrop != null) interp.variables.set('FlxBackdrop', backdrop);
		} catch(_) {}

		// FlxTrail — en flixel-addons si el proyecto lo incluye
		try {
			final trail = Type.resolveClass('flixel.addons.effects.FlxTrail');
			if (trail != null) interp.variables.set('FlxTrail', trail);
		} catch(_) {}

		// BUGFIX inline: proxy de FlxMath para evitar "Null Function Pointer"
		interp.variables.set('FlxMath', {
			lerp          : function(a:Float, b:Float, ratio:Float):Float return a + (b - a) * ratio,
			fastSin       : function(angle:Float):Float return Math.sin(angle),
			fastCos       : function(angle:Float):Float return Math.cos(angle),
			remapToRange  : flixel.math.FlxMath.remapToRange,
			bound         : flixel.math.FlxMath.bound,
			roundDecimal  : flixel.math.FlxMath.roundDecimal,
			isOdd         : flixel.math.FlxMath.isOdd,
			isEven        : flixel.math.FlxMath.isEven,
			dotProduct    : flixel.math.FlxMath.dotProduct,
			vectorLength  : flixel.math.FlxMath.vectorLength,
			MIN_VALUE_INT  : flixel.math.FlxMath.MIN_VALUE_INT,
			MAX_VALUE_INT  : flixel.math.FlxMath.MAX_VALUE_INT,
			MIN_VALUE_FLOAT: flixel.math.FlxMath.MIN_VALUE_FLOAT,
			MAX_VALUE_FLOAT: flixel.math.FlxMath.MAX_VALUE_FLOAT
		});

		interp.variables.set('FlxPoint',   _flxPointProxy());
		interp.variables.set('FlxRect',    _flxRectProxy());
		interp.variables.set('FlxAngle',   flixel.math.FlxAngle);

		// OpenFL
		interp.variables.set('BitmapData', openfl.display.BitmapData);
		interp.variables.set('Sound',      openfl.media.Sound);

		interp.variables.set('RuntimeRainShader', funkin.graphics.shaders.RuntimeRainShader);
		interp.variables.set('ShaderFilter', openfl.filters.ShaderFilter);

		// BlendMode — expuesto como proxy con las constantes más usadas.
		// En HScript la conversión abstracta `from String` de BlendMode no se
		// aplica automáticamente al asignar sp.blend = "add", por lo que los
		// scripts deben usar BlendMode.ADD, BlendMode.MULTIPLY, etc.
		interp.variables.set('BlendMode', {
			NORMAL   : (openfl.display.BlendMode.NORMAL   : openfl.display.BlendMode),
			ADD      : (openfl.display.BlendMode.ADD      : openfl.display.BlendMode),
			MULTIPLY : (openfl.display.BlendMode.MULTIPLY : openfl.display.BlendMode),
			SCREEN   : (openfl.display.BlendMode.SCREEN   : openfl.display.BlendMode),
			OVERLAY  : (openfl.display.BlendMode.OVERLAY  : openfl.display.BlendMode),
			SUBTRACT : (openfl.display.BlendMode.SUBTRACT : openfl.display.BlendMode),
			DARKEN   : (openfl.display.BlendMode.DARKEN   : openfl.display.BlendMode),
			LIGHTEN  : (openfl.display.BlendMode.LIGHTEN  : openfl.display.BlendMode),
			HARDLIGHT: (openfl.display.BlendMode.HARDLIGHT: openfl.display.BlendMode),
			INVERT   : (openfl.display.BlendMode.INVERT   : openfl.display.BlendMode),
			ALPHA    : (openfl.display.BlendMode.ALPHA    : openfl.display.BlendMode),
			ERASE    : (openfl.display.BlendMode.ERASE    : openfl.display.BlendMode),
			// Helper para convertir string → BlendMode (retrocompatibilidad)
			fromString: function(name:String):openfl.display.BlendMode {
				return switch (name.toLowerCase()) {
					case 'add'       : openfl.display.BlendMode.ADD;
					case 'multiply'  : openfl.display.BlendMode.MULTIPLY;
					case 'screen'    : openfl.display.BlendMode.SCREEN;
					case 'overlay'   : openfl.display.BlendMode.OVERLAY;
					case 'subtract'  : openfl.display.BlendMode.SUBTRACT;
					case 'darken'    : openfl.display.BlendMode.DARKEN;
					case 'lighten'   : openfl.display.BlendMode.LIGHTEN;
					case 'hardlight' : openfl.display.BlendMode.HARDLIGHT;
					case 'invert'    : openfl.display.BlendMode.INVERT;
					case 'alpha'     : openfl.display.BlendMode.ALPHA;
					case 'erase'     : openfl.display.BlendMode.ERASE;
					default          : openfl.display.BlendMode.NORMAL;
				};
			}
		});
	}

	// ─── Gameplay ─────────────────────────────────────────────────────────────

	static function exposeGameplay(interp:Interp):Void
	{
		interp.variables.set('PlayState',       funkin.gameplay.PlayState);
		interp.variables.set('game',            funkin.gameplay.PlayState.instance);
		interp.variables.set('Conductor',       funkin.data.Conductor);
		interp.variables.set('Paths',           Paths);
		interp.variables.set('MetaData',        funkin.data.MetaData);
		interp.variables.set('GlobalConfig',    funkin.data.GlobalConfig);
		interp.variables.set('Song',            funkin.data.Song);
		interp.variables.set('Note',            funkin.gameplay.notes.Note);
		interp.variables.set('NoteSkinSystem',  funkin.gameplay.notes.NoteSkinSystem);
		interp.variables.set('NotePool',        funkin.gameplay.notes.NotePool);
		interp.variables.set('NoteTypeManager', funkin.gameplay.notes.NoteTypeManager);
		interp.variables.set('ModManager',      mods.ModManager);
		interp.variables.set('ModPaths',        mods.ModPaths);
		interp.variables.set('ShaderManager',   _shaderManagerProxy());
		interp.variables.set('ModChartManager', funkin.gameplay.modchart.ModChartManager);
		interp.variables.set('ModChartHelpers', funkin.gameplay.modchart.ModChartEvent.ModChartHelpers);

		interp.variables.set('ModEventType', {
			MOVE_X   : "moveX",   MOVE_Y   : "moveY",
			ANGLE    : "angle",   ALPHA    : "alpha",
			SCALE    : "scale",   SCALE_X  : "scaleX",    SCALE_Y  : "scaleY",
			SPIN     : "spin",    RESET    : "reset",
			SET_ABS_X: "setAbsX", SET_ABS_Y: "setAbsY",
			VISIBLE  : "visible"
		});
		interp.variables.set('ModEase', {
			LINEAR    : "linear",
			QUAD_IN   : "quadIn",    QUAD_OUT   : "quadOut",    QUAD_IN_OUT  : "quadInOut",
			CUBE_IN   : "cubeIn",    CUBE_OUT   : "cubeOut",    CUBE_IN_OUT  : "cubeInOut",
			SINE_IN   : "sineIn",    SINE_OUT   : "sineOut",    SINE_IN_OUT  : "sineInOut",
			ELASTIC_IN: "elasticIn", ELASTIC_OUT: "elasticOut",
			BOUNCE_OUT: "bounceOut",
			BACK_IN   : "backIn",    BACK_OUT   : "backOut",
			INSTANT   : "instant"
		});
	}

	// ─── Scoring custom ───────────────────────────────────────────────────────

	static function exposeScoring(interp:Interp):Void
	{
		interp.variables.set('score', {
			setWindow: function(rating:String, ms:Float) {
				final sm = funkin.gameplay.objects.hud.ScoreManager;
				switch (rating.toLowerCase()) {
					case 'sick':  Reflect.setField(sm, 'SICK_WINDOW',  ms);
					case 'good':  Reflect.setField(sm, 'GOOD_WINDOW',  ms);
					case 'bad':   Reflect.setField(sm, 'BAD_WINDOW',   ms);
					case 'shit':  Reflect.setField(sm, 'SHIT_WINDOW',  ms);
				}
			},
			setPoints: function(rating:String, pts:Int) {
				final sm = funkin.gameplay.objects.hud.ScoreManager;
				switch (rating.toLowerCase()) {
					case 'sick':  Reflect.setField(sm, 'SICK_SCORE',  pts);
					case 'good':  Reflect.setField(sm, 'GOOD_SCORE',  pts);
					case 'bad':   Reflect.setField(sm, 'BAD_SCORE',   pts);
					case 'shit':  Reflect.setField(sm, 'SHIT_SCORE',  pts);
				}
			},
			setMissPenalty: function(penalty:Int) {
				Reflect.setField(funkin.gameplay.objects.hud.ScoreManager, 'MISS_PENALTY', penalty);
			},
			getAccuracy:  function():Float {
				final i = funkin.gameplay.PlayState.instance;
				return i != null ? i.scoreManager.accuracy : 0.0;
			},
			getCombo: function():Int {
				final i = funkin.gameplay.PlayState.instance;
				return i != null ? i.scoreManager.combo : 0;
			},
			getScore: function():Int {
				final i = funkin.gameplay.PlayState.instance;
				return i != null ? i.scoreManager.score : 0;
			},
			getMisses: function():Int {
				final i = funkin.gameplay.PlayState.instance;
				return i != null ? i.scoreManager.misses : 0;
			},
			getSicks: function():Int {
				final i = funkin.gameplay.PlayState.instance;
				return i != null ? i.scoreManager.sicks : 0;
			},
			addScore: function(n:Int) {
				final i = funkin.gameplay.PlayState.instance;
				if (i != null) i.scoreManager.score += n;
			},
			resetCombo: function() {
				final i = funkin.gameplay.PlayState.instance;
				if (i != null) { i.scoreManager.combo = 0; i.scoreManager.fullCombo = false; }
			},
			isFullCombo: function():Bool {
				final i = funkin.gameplay.PlayState.instance;
				return i != null ? i.scoreManager.fullCombo : false;
			},
			isSickCombo: function():Bool {
				final i = funkin.gameplay.PlayState.instance;
				return i != null ? i.scoreManager.sickCombo : false;
			},
			onNoteHit: null,
			onMiss:    null
		});
	}

	// ─── NoteTypes ────────────────────────────────────────────────────────────

	static function exposeNoteTypes(interp:Interp):Void
	{
		interp.variables.set('noteTypes', {
			register:   function(name:String, cfg:Dynamic) {
				funkin.gameplay.notes.NoteTypeManager.register(name, cfg);
			},
			unregister: function(name:String) {
				funkin.gameplay.notes.NoteTypeManager.unregister(name);
			},
			exists: function(name:String):Bool {
				return funkin.gameplay.notes.NoteTypeManager.exists(name);
			},
			list: function():Array<String> {
				return funkin.gameplay.notes.NoteTypeManager.getAll();
			}
		});
	}

	// ─── States ───────────────────────────────────────────────────────────────

	static function exposeStates(interp:Interp):Void
	{
		interp.variables.set('states', {
			goto:               function(name:String) { ScriptBridge.switchStateByName(name); },
			open:               function(state:flixel.FlxState) { StateTransition.switchState(state); },
			sticker:            function(state:flixel.FlxState) {
				StickerTransition.start(function() StateTransition.switchState(state));
			},
			load:               function(state:flixel.FlxState) {
				funkin.states.LoadingState.loadAndSwitchState(state);
			},
			openSubState: function(name:String) {
				final ss = new ScriptableSubState(name);
				if (FlxG.state != null) FlxG.state.openSubState(ss);
			},
			openSubStateInstance: function(ss:flixel.FlxSubState) {
				if (FlxG.state != null) FlxG.state.openSubState(ss);
			},
			close: function() { if (FlxG.state != null) FlxG.state.closeSubState(); },
			scripted: function(name:String) {
				final ss = new ScriptableSubState(name);
				if (FlxG.state != null) FlxG.state.openSubState(ss);
			},
			current: function():flixel.FlxState { return FlxG.state; }
		});
	}

	// ─── Signal bus ───────────────────────────────────────────────────────────

	static var _signals    : Map<String, Array<Dynamic>> = [];
	static var _signalsOnce: Map<String, Array<Dynamic>> = [];

	static function exposeSignals(interp:Interp):Void
	{
		interp.variables.set('signal', {
			on:   function(event:String, cb:Dynamic) {
				if (!_signals.exists(event)) _signals.set(event, []);
				_signals.get(event).push(cb);
			},
			once: function(event:String, cb:Dynamic) {
				if (!_signalsOnce.exists(event)) _signalsOnce.set(event, []);
				_signalsOnce.get(event).push(cb);
			},
			off: function(event:String, cb:Dynamic) {
				final arr = _signals.get(event);
				if (arr != null) arr.remove(cb);
			},
			emit: function(event:String, ?data:Dynamic) {
				final arr = _signals.get(event);
				if (arr != null)
					for (cb in arr.copy()) try { Reflect.callMethod(null, cb, [data]); } catch(_) {}
				final once = _signalsOnce.get(event);
				if (once != null) {
					for (cb in once.copy()) try { Reflect.callMethod(null, cb, [data]); } catch(_) {}
					once.resize(0);
				}
			},
			clear:    function(event:String) { _signals.remove(event); _signalsOnce.remove(event); },
			clearAll: function() { _signals.clear(); _signalsOnce.clear(); }
		});
	}

	// ─── Storage ──────────────────────────────────────────────────────────────

	static function exposeStorage(interp:Interp):Void
	{
		interp.variables.set('SaveData',funkin.data.SaveData);
		interp.variables.set('data', {
			set:    function(key:String, value:Dynamic) { Reflect.setField(FlxG.save.data, key, value); },
			get:    function(key:String, ?fallback:Dynamic):Dynamic {
				final v = Reflect.field(FlxG.save.data, key);
				return v != null ? v : fallback;
			},
			delete: function(key:String) { Reflect.deleteField(FlxG.save.data, key); },
			has:    function(key:String):Bool { return Reflect.hasField(FlxG.save.data, key); },
			save:   function() { FlxG.save.flush(); },
			dump:   function():Dynamic { return FlxG.save.data; }
		});
	}

	// ─── Import dinámico ──────────────────────────────────────────────────────

	static function exposeImport(interp:Interp):Void
	{
		final _flxMathProxy:Dynamic = interp.variables.get('FlxMath');

		final _classRegistry:Map<String, Dynamic> = [
			// Flixel core
			'FlxSprite'         => FlxSprite,
			'FlxText'           => flixel.text.FlxText,
			'FlxG'              => FlxG,
			'FlxTween'          => FlxTween,
			'FlxEase'           => _flxEaseProxy(),
			'FlxColor'          => _flxColorProxy(),
			'FlxTimer'          => FlxTimer,
			'FlxSound'          => FlxSound,
			'FlxCamera'         => FlxCamera,
			'FlxObject'         => FlxObject,
			'FlxMath'           => _flxMathProxy,
			'FlxPoint'          => _flxPointProxy(),
			'FlxRect'           => _flxRectProxy(),
			'FlxSpriteGroup'    => flixel.group.FlxSpriteGroup,
			'FlxGroup'          => flixel.group.FlxGroup,
			'FlxAngle'          => flixel.math.FlxAngle,
			// Extensions del engine
			'FlxAtlasFramesExt' => extensions.FlxAtlasFramesExt,
			'CppAPI'            => extensions.CppAPI,
			// Shaders
			'ShaderManager'     => _shaderManagerProxy(),
			'ShaderHandle'      => funkin.graphics.shaders.ShaderHandle,
			'WaveEffect'        => funkin.graphics.shaders.custom.WaveEffect,
			'WiggleEffect'      => funkin.graphics.shaders.custom.WiggleEffect,
			'BlendModeEffect'   => funkin.graphics.shaders.custom.BlendModeEffect,
			'OverlayShader'     => funkin.graphics.shaders.custom.OverlayShader,
			'DropShadowShader'  => funkin.graphics.shaders.custom.DropShadowShader,
			// Funkin gameplay
			'PlayState'         => funkin.gameplay.PlayState,
			'Countdown'         => funkin.gameplay.Countdown,
			'GameState'         => funkin.gameplay.GameState,
			'CharacterController' => funkin.gameplay.CharacterController,
			'CameraController'    => funkin.gameplay.CameraController,
			'Conductor'         => funkin.data.Conductor,
			'Note'              => funkin.gameplay.notes.Note,
			'NotePool'          => funkin.gameplay.notes.NotePool,
			'NoteSkinSystem'    => funkin.gameplay.notes.NoteSkinSystem,
			'NoteTypeManager'   => funkin.gameplay.notes.NoteTypeManager,
			'Song'              => funkin.data.Song,
			'MetaData'          => funkin.data.MetaData,
			'GlobalConfig'      => funkin.data.GlobalConfig,
			'CoolUtil'          => funkin.data.CoolUtil,
			'CameraUtil'        => funkin.data.CameraUtil,
			'PlayStateConfig'   => funkin.gameplay.PlayStateConfig,
			'CharacterList'     => funkin.gameplay.objects.character.CharacterList,
			'Highscore'         => funkin.gameplay.objects.hud.Highscore,
			'ModManager'        => mods.ModManager,
			'ModPaths'          => mods.ModPaths,
			'ModChartManager'   => funkin.gameplay.modchart.ModChartManager,
			'FunkinSprite'      => animationdata.FunkinSprite,
			// Transitions
			'StateTransition'   => funkin.transitions.StateTransition,
			'StickerTransition' => funkin.transitions.StickerTransition,
			// Video
			'VideoManager'      => funkin.cutscenes.VideoManager,
			// Scripting
			'ScriptHandler'     => funkin.scripting.ScriptHandler,
			'EventManager'      => funkin.scripting.events.EventManager,
			// OpenFL
			'BitmapData'        => openfl.display.BitmapData,
			'Sound'             => openfl.media.Sound,
			'BlendMode'         => interp.variables.get('BlendMode'),
		];

		// Registrar clases opcionales (solo si están en el build)
		try {
			final flxAnimate = Type.resolveClass('flxanimate.FlxAnimate');
			if (flxAnimate != null) _classRegistry.set('FlxAnimate', flxAnimate);
		} catch(_) {}
		try {
			final backdrop = Type.resolveClass('flixel.addons.display.FlxBackdrop');
			if (backdrop != null) _classRegistry.set('FlxBackdrop', backdrop);
		} catch(_) {}
		try {
			final trail = Type.resolveClass('flixel.addons.effects.FlxTrail');
			if (trail != null) _classRegistry.set('FlxTrail', trail);
		} catch(_) {}

		interp.variables.set('importClass', function(className:String):Dynamic {
			if (_classRegistry.exists(className)) return _classRegistry.get(className);
			final resolved = Type.resolveClass(className);
			if (resolved != null) return resolved;
			trace('[ScriptAPI] importClass: "$className" no encontrada.');
			return null;
		});

		interp.variables.set('createInstance', function(className:String, args:Array<Dynamic>):Dynamic {
			final cls = Type.resolveClass(className);
			if (cls == null) { trace('[ScriptAPI] createInstance: "$className" no encontrada.'); return null; }
			return Type.createInstance(cls, args ?? []);
		});

		// ─── defineClass / newClass ─────────────────────────────────────────
		// Registro local de clases definidas en este script.
		// Permite crear clases con prototype pattern desde HScript.
		//
		// ESTILO A — objeto prototipo (siempre disponible):
		//
		//   defineClass('MiEfecto', {
		//     'new': function(x:Float, y:Float) {
		//       var self = { x:x, y:y, alpha:1.0 };
		//       self.update = function(dt:Float) { self.x += 100 * dt; };
		//       self.setAlpha = function(a:Float) { self.alpha = a; };
		//       return self;
		//     }
		//   });
		//   var obj = newClass('MiEfecto', 100, 200);
		//   obj.update(0.016);
		//
		// ESTILO B — clase Haxe nativa (si el parser soporta 'class'):
		//
		//   class MiEfecto extends FlxSprite {
		//     public function new(x:Float, y:Float) {
		//       super(x, y);
		//       makeGraphic(16, 16, FlxColor.RED);
		//     }
		//   }
		//   defineClass('MiEfecto', MiEfecto);
		//   var obj = newClass('MiEfecto', 100, 200);
		//
		final _scriptClasses:Map<String, Dynamic> = new Map();

		interp.variables.set('defineClass', function(name:String, proto:Dynamic):Void {
			if (name == null || proto == null) return;
			_scriptClasses.set(name, proto);
			interp.variables.set(name, proto);
			trace('[Script] Clase definida: "$name"');
		});

		interp.variables.set('newClass', function(name:String, ?args:Array<Dynamic>):Dynamic {
			var proto:Dynamic = _scriptClasses.get(name);
			if (proto == null) proto = interp.variables.get(name);
			if (proto == null) {
				trace('[Script] newClass: "$name" no encontrada.');
				return null;
			}
			// 1. método 'new'
			var ctor:Dynamic = Reflect.field(proto, 'new');
			if (ctor != null && Reflect.isFunction(ctor))
				return Reflect.callMethod(proto, ctor, args ?? []);
			// 2. método 'create'
			ctor = Reflect.field(proto, 'create');
			if (ctor != null && Reflect.isFunction(ctor))
				return Reflect.callMethod(proto, ctor, args ?? []);
			// 3. la clase misma es una función constructora
			if (Reflect.isFunction(proto))
				return Reflect.callMethod(null, proto, args ?? []);
			trace('[Script] newClass: "$name" no tiene constructor.');
			return null;
		});

		interp.variables.set('getClass', function(name:String):Dynamic {
			var proto:Dynamic = _scriptClasses.get(name);
			return proto ?? interp.variables.get(name);
		});

		interp.variables.set('hasClass', function(name:String):Bool
			return _scriptClasses.exists(name) || interp.variables.exists(name));

		// ─── Sistema de librerías HScript ────────────────────────────────────────
		// require(name) carga y devuelve los exports de una librería .hx sin compilar.
		//
		// Orden de búsqueda:
		//   1. mods/<activeMod>/libs/   ← librería del mod activo
		//   2. libs/ de cada addon cargado  ← librerías de addons
		//   3. assets/data/libs/         ← librerías base del engine
		//
		// Ejemplo de uso desde cualquier script de mod:
		//   var Utils = require('Utils');
		//   Utils.miFuncion(arg1, arg2);
		//
		// Ejemplo con subcarpeta:
		//   var MathExtra = require('math/Lerp');
		//
		// forceReload: si true, re-ejecuta el archivo ignorando caché.
		#if sys
		interp.variables.set('require', function(name:String, ?forceReload:Bool):Dynamic {
			final searchDirs:Array<String> = [];

			// 1. Libs del mod activo
			final modRoot = mods.ModManager.modRoot();
			if (modRoot != null)
				searchDirs.push('$modRoot/libs');

			// 2. Libs de todos los addons cargados
			for (dir in funkin.addons.AddonManager.getLibSearchDirs())
				searchDirs.push(dir);

			// BASE_LIBS se añade automáticamente dentro de ScriptLibrary.require()
			return funkin.scripting.ScriptLibrary.require(
				name, searchDirs,
				#if HSCRIPT_ALLOWED cast interp #else null #end,
				forceReload ?? false
			);
		});

		// hasLib(name) — comprueba si una librería existe sin cargarla.
		interp.variables.set('hasLib', function(name:String):Bool {
			final dirs:Array<String> = [];
			final modRoot = mods.ModManager.modRoot();
			if (modRoot != null) dirs.push('$modRoot/libs');
			for (dir in funkin.addons.AddonManager.getLibSearchDirs())
				dirs.push(dir);
			dirs.push(funkin.scripting.ScriptLibrary.BASE_LIBS);

			for (dir in dirs)
				for (ext in ['.hx', '.hscript', ''])
				{
					final p = '$dir/$name$ext';
					if (sys.FileSystem.exists(p) && !sys.FileSystem.isDirectory(p))
						return true;
				}
			return false;
		});
		#end
	}

	// ─── Math extendido ───────────────────────────────────────────────────────

	static function exposeMath(interp:Interp):Void
	{
		interp.variables.set('math', {
			// Interpolación
			lerp:       function(a:Float, b:Float, t:Float):Float return a + (b - a) * t,
			lerpSnap:   function(a:Float, b:Float, t:Float, snap:Float):Float {
				final r = a + (b - a) * t;
				return Math.abs(r - b) < snap ? b : r;
			},
			// Rango
			clamp:   function(v:Float, min:Float, max:Float):Float return Math.min(Math.max(v, min), max),
			clampInt: function(v:Int, min:Int, max:Int):Int {
				if (v < min) return min;
				if (v > max) return max;
				return v;
			},
			map:     function(v:Float, i0:Float, i1:Float, o0:Float, o1:Float):Float {
				return o0 + (v - i0) / (i1 - i0) * (o1 - o0);
			},
			norm:    function(v:Float, min:Float, max:Float):Float return (v - min) / (max - min),
			snap:    function(v:Float, step:Float):Float return Math.round(v / step) * step,
			pingpong: function(v:Float, len:Float):Float {
				final t = v % (len * 2);
				return t < len ? t : len * 2 - t;
			},
			sign:    function(v:Float):Int return v > 0 ? 1 : (v < 0 ? -1 : 0),
			// Seno/coseno con acumulador (sin estado global compartido)
			sine:    function(acc:Float, speed:Float = 1.0):Float return Math.sin(acc * speed),
			cosine:  function(acc:Float, speed:Float = 1.0):Float return Math.cos(acc * speed),
			// Random
			rnd:     function(min:Int, max:Int):Int return FlxG.random.int(min, max),
			rndf:    function(min:Float, max:Float):Float return FlxG.random.float(min, max),
			chance:  function(pct:Float):Bool return FlxG.random.float() < pct,
			// Geometría
			dist:    function(x1:Float, y1:Float, x2:Float, y2:Float):Float {
				final dx = x2 - x1; final dy = y2 - y1;
				return Math.sqrt(dx * dx + dy * dy);
			},
			angle:   function(x1:Float, y1:Float, x2:Float, y2:Float):Float {
				return Math.atan2(y2 - y1, x2 - x1) * (180 / Math.PI);
			},
			// Bézier
			bezier:     function(t:Float, p0:Float, p1:Float, p2:Float, p3:Float):Float {
				final u = 1 - t;
				return u*u*u*p0 + 3*u*u*t*p1 + 3*u*t*t*p2 + t*t*t*p3;
			},
			quadBezier: function(t:Float, p0:Float, p1:Float, p2:Float):Float {
				final u = 1 - t;
				return u*u*p0 + 2*u*t*p1 + t*t*p2;
			},
			// Trig en grados
			sin:     function(d:Float):Float return Math.sin(d * Math.PI / 180),
			cos:     function(d:Float):Float return Math.cos(d * Math.PI / 180),
			tan:     function(d:Float):Float return Math.tan(d * Math.PI / 180),
			// Constantes
			PI: Math.PI, TAU: Math.PI * 2,
			E: Math.exp(1.0), SQRT2: Math.sqrt(2.0),
			INF: Math.POSITIVE_INFINITY
		});
	}

	// ─── Array helpers ────────────────────────────────────────────────────────

	static function exposeArray(interp:Interp):Void
	{
		interp.variables.set('arr', {
			find:    function(a:Array<Dynamic>, fn:Dynamic):Dynamic {
				for (x in a) if (Reflect.callMethod(null, fn, [x])) return x;
				return null;
			},
			filter:  function(a:Array<Dynamic>, fn:Dynamic):Array<Dynamic> {
				return a.filter(function(x) return Reflect.callMethod(null, fn, [x]));
			},
			map:     function(a:Array<Dynamic>, fn:Dynamic):Array<Dynamic> {
				return a.map(function(x) return Reflect.callMethod(null, fn, [x]));
			},
			some:    function(a:Array<Dynamic>, fn:Dynamic):Bool {
				for (x in a) if (Reflect.callMethod(null, fn, [x])) return true;
				return false;
			},
			every:   function(a:Array<Dynamic>, fn:Dynamic):Bool {
				for (x in a) if (!Reflect.callMethod(null, fn, [x])) return false;
				return true;
			},
			shuffle: function(a:Array<Dynamic>):Array<Dynamic> {
				final r = a.copy();
				for (i in 0...r.length) {
					final j = FlxG.random.int(0, r.length - 1);
					final tmp = r[i]; r[i] = r[j]; r[j] = tmp;
				}
				return r;
			},
			pick:    function(a:Array<Dynamic>):Dynamic {
				return a.length > 0 ? a[FlxG.random.int(0, a.length - 1)] : null;
			},
			unique:  function(a:Array<Dynamic>):Array<Dynamic> {
				final r:Array<Dynamic> = [];
				for (x in a) if (!r.contains(x)) r.push(x);
				return r;
			},
			flatten: function(a:Array<Array<Dynamic>>):Array<Dynamic> {
				final r:Array<Dynamic> = [];
				for (sub in a) for (x in sub) r.push(x);
				return r;
			},
			sum:     function(a:Array<Float>):Float { var s = 0.0; for (x in a) s += x; return s; },
			max:     function(a:Array<Float>):Float { var m = Math.NEGATIVE_INFINITY; for (x in a) if (x > m) m = x; return m; },
			min:     function(a:Array<Float>):Float { var m = Math.POSITIVE_INFINITY; for (x in a) if (x < m) m = x; return m; },
			sortBy:  function(a:Array<Dynamic>, key:String):Array<Dynamic> {
				final r = a.copy();
				r.sort(function(x, y) {
					final vx = Reflect.field(x, key); final vy = Reflect.field(y, key);
					if (vx < vy) return -1; if (vx > vy) return 1; return 0;
				});
				return r;
			},
			range:   function(from:Int, to:Int, ?step:Int):Array<Int> {
				if (step == null) step = 1;
				final r:Array<Int> = [];
				var i = from;
				while (step > 0 ? i < to : i > to) { r.push(i); i += step; }
				return r;
			},
			zip:     function(a:Array<Dynamic>, b:Array<Dynamic>):Array<Array<Dynamic>> {
				final len = Std.int(Math.min(a.length, b.length));
				return [for (i in 0...len) [a[i], b[i]]];
			}
		});
	}

	// ─── Mod info ─────────────────────────────────────────────────────────────

	static function exposeMod(interp:Interp):Void
	{
		interp.variables.set('mod', {
			isActive: function():Bool   return mods.ModManager.isActive(),
			name:     function():String return mods.ModManager.activeMod ?? 'base',
			root:     function():String return mods.ModManager.isActive() ? mods.ModManager.modRoot() : 'assets',
			path:     function(rel:String):String {
				if (mods.ModManager.isActive()) return '${mods.ModManager.modRoot()}/$rel';
				return 'assets/$rel';
			},
			exists:   function(rel:String):Bool {
				#if sys
				if (mods.ModManager.isActive()) {
					if (sys.FileSystem.exists('${mods.ModManager.modRoot()}/$rel')) return true;
				}
				return sys.FileSystem.exists('assets/$rel');
				#else
				return false;
				#end
			},
			list:     function():Array<String> { return [for (m in mods.ModManager.installedMods) m.id]; },
			info:     function():Dynamic {
				final id = mods.ModManager.activeMod;
				if (id == null) return null;
				for (m in mods.ModManager.installedMods) if (m.id == id) return m;
				return null;
			},
			getImage:  function(name:String):Dynamic { return Paths.image(name); },
			getSound:  function(name:String):Dynamic { return Paths.sound(name); },
			getMusic:  function(name:String):Dynamic { return Paths.music(name); },
			setActive: function(id:String) { mods.ModManager.setActive(id); },
			deactivate: function() { mods.ModManager.deactivate(); }
		});
	}

	// ─── Characters ───────────────────────────────────────────────────────────

	static function exposeCharacters(interp:Interp):Void
	{
		interp.variables.set('chars', {
			bf:  function():Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				return ps != null ? ps.boyfriend : null;
			},
			dad: function():Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				return ps != null ? ps.dad : null;
			},
			gf:  function():Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				return ps != null ? ps.gf : null;
			},
			get: function(idx:Int):Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return null;
				final cc = Reflect.field(ps, 'characterController');
				return (cc != null) ? cc.getCharacter(idx) : null;
			},
			getSlot: function(idx:Int):Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return null;
				final cc = Reflect.field(ps, 'characterController');
				return (cc != null) ? cc.getSlot(idx) : null;
			},
			count: function():Int {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return 0;
				final cc = Reflect.field(ps, 'characterController');
				return (cc != null) ? cc.getCharacterCount() : 0;
			},
			playAnim:    function(char:Dynamic, anim:String, ?force:Bool) {
				if (char != null) char.playAnim(anim, force != null ? force : true);
			},
			dance:       function(char:Dynamic) { if (char != null) char.dance(); },
			setVisible:  function(char:Dynamic, v:Bool) { if (char != null) char.visible = v; },
			setPosition: function(char:Dynamic, x:Float, y:Float) {
				if (char != null) { char.x = x; char.y = y; }
			},
			getAnim: function(char:Dynamic):String {
				if (char == null || char.animation == null) return '';
				final cur = char.animation.curAnim;
				return cur != null ? cur.name : '';
			},
			hasAnim: function(char:Dynamic, name:String):Bool {
				if (char == null) return false;
				return char.hasAnimation(name);
			},
			getAnimList: function(char:Dynamic):Array<String> {
				if (char == null) return [];
				return char.getAnimationList();
			},
			setActive: function(idx:Int, active:Bool) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return;
				final cc = Reflect.field(ps, 'characterController');
				if (cc != null) cc.setCharacterActive(idx, active);
			},
			singByIndex: function(charIdx:Int, noteData:Int, ?altAnim:String) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return;
				final cc = Reflect.field(ps, 'characterController');
				if (cc != null) cc.singByIndex(charIdx, noteData, altAnim);
			}
		});
	}

	// ─── Camera ───────────────────────────────────────────────────────────────

	static function exposeCamera(interp:Interp):Void
	{
		interp.variables.set('camera', {
			game:    function():Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				return ps != null ? Reflect.field(ps, 'camGame') : FlxG.camera;
			},
			hud:     function():Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				return ps != null ? Reflect.field(ps, 'camHUD') : null;
			},
			other:   function():Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				return ps != null ? Reflect.field(ps, 'camOther') : null;
			},
			setZoom: function(v:Float) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null) { final cg = Reflect.field(ps, 'camGame'); if (cg != null) cg.zoom = v; }
			},
			getZoom: function():Float {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return 1.0;
				final cg = Reflect.field(ps, 'camGame');
				return cg != null ? cg.zoom : 1.0;
			},
			tweenZoom: function(targetZoom:Float, duration:Float, ?ease:Dynamic) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return;
				final cg = Reflect.field(ps, 'camGame');
				if (cg != null) FlxTween.tween(cg, {zoom: targetZoom}, duration,
					ease != null ? {ease: ease} : null);
			},
			shake:   function(?intensity:Float, ?duration:Float, ?target:Dynamic) {
				final cam = target ?? FlxG.camera;
				cam.shake(intensity ?? 0.03, duration ?? 0.2);
			},
			flash:   function(?color:Int, ?duration:Float, ?target:Dynamic) {
				final cam = target ?? FlxG.camera;
				cam.flash(color ?? FlxColor.WHITE, duration ?? 0.3);
			},
			fade:    function(?color:Int, ?duration:Float, ?inward:Bool, ?target:Dynamic) {
				final cam = target ?? FlxG.camera;
				if (inward ?? false) cam.fade(color ?? FlxColor.BLACK, duration ?? 0.5, true);
				else                 cam.fade(color ?? FlxColor.BLACK, duration ?? 0.5);
			},
			focusBf:  function() {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.cameraController != null) ps.cameraController.setTarget('bf');
			},
			focusDad: function() {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.cameraController != null) ps.cameraController.setTarget('opponent');
			},
			setFollowLerp: function(lerp:Float) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.cameraController != null) ps.cameraController.setFollowLerp(lerp);
			},
			bumpZoom: function() {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.cameraController != null) ps.cameraController.bumpZoom();
			},
			// Añadir shader a una cámara específica.
			// FIX: usar ShaderManager.applyShaderToCamera() en lugar del camino manual
			// que bypaseaba _liveInstances → setShaderParam no podía actualizar uniforms
			// (uTime, etc.) porque la instancia no estaba registrada → sin efecto visual.
			addShader: function(shaderName:String, ?camTarget:Dynamic) {
				final ps = funkin.gameplay.PlayState.instance;
				final cam:FlxCamera = camTarget ?? (ps != null ? Reflect.field(ps, 'camGame') : FlxG.camera);
				if (cam == null) return;
				funkin.graphics.shaders.ShaderManager.applyShaderToCamera(shaderName, cam);
			},
			clearShaders: function(?camTarget:Dynamic) {
				final ps = funkin.gameplay.PlayState.instance;
				final cam:FlxCamera = camTarget ?? (ps != null ? Reflect.field(ps, 'camGame') : FlxG.camera);
				if (cam != null) funkin.data.CameraUtil.clearFilters(cam);
			}
		});
	}

	// ─── HUD ──────────────────────────────────────────────────────────────────

	static function exposeHUD(interp:Interp):Void
	{
		interp.variables.set('hud', {
			get: function():Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				return (ps != null) ? ps.uiManager : null;
			},
			camera: function():Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				return (ps != null) ? ps.camHUD : null;
			},
			setVisible: function(v:Bool) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.uiManager != null) ps.uiManager.visible = v;
			},
			setHealth: function(v:Float) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.gameState != null) ps.gameState.health = v;
			},
			getHealth: function():Float {
				final ps = funkin.gameplay.PlayState.instance;
				return (ps != null && ps.gameState != null) ? ps.gameState.health : 1.0;
			},
			addHealth: function(v:Float) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.gameState != null) ps.gameState.modifyHealth(v);
			},
			iconP1: function():Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				return (ps != null && ps.uiManager != null) ? ps.uiManager.iconP1 : null;
			},
			iconP2: function():Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				return (ps != null && ps.uiManager != null) ? ps.uiManager.iconP2 : null;
			},
			setScoreVisible: function(v:Bool) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.uiManager != null) {
					final txt = Reflect.field(ps.uiManager, 'scoreText');
					if (txt != null) txt.visible = v;
				}
			},
			showRating: function(rating:String, ?combo:Int) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.uiManager != null)
					ps.uiManager.showRatingPopup(rating, combo ?? ps.scoreManager.combo);
			},
			tweenTo: function(obj:Dynamic, props:Dynamic, dur:Float, ?ease:Dynamic) {
				if (obj == null) return null;
				return FlxTween.tween(obj, props, dur, ease != null ? {ease: ease} : null);
			}
		});
	}

	// ─── Shaders ──────────────────────────────────────────────────────────────

	static function exposeShaders(interp:Interp):Void
	{
		interp.variables.set('ShaderManager',    _shaderManagerProxy());
		interp.variables.set('WaveEffect',       funkin.graphics.shaders.custom.WaveEffect);
		interp.variables.set('WiggleEffect',     funkin.graphics.shaders.custom.WiggleEffect);
		interp.variables.set('BlendModeEffect',  funkin.graphics.shaders.custom.BlendModeEffect);
		interp.variables.set('OverlayShader',    funkin.graphics.shaders.custom.OverlayShader);
		interp.variables.set('DropShadowShader', funkin.graphics.shaders.custom.DropShadowShader);
		interp.variables.set('ShaderHandle', {
			// Constructor: new ShaderHandle('wave') — instanciable desde HScript
			create: function(shaderName:String):funkin.graphics.shaders.ShaderHandle
				return new funkin.graphics.shaders.ShaderHandle(shaderName)
		});
		// Expose ShaderHandle class directly so HScript "new ShaderHandle(...)" works
		interp.variables.set('ShaderHandleClass', funkin.graphics.shaders.ShaderHandle);

		// WiggleEffect — object wrapper para usar en scripts fácilmente
		interp.variables.set('wiggleEffect', {
			create: function():funkin.graphics.shaders.custom.WiggleEffect { return new funkin.graphics.shaders.custom.WiggleEffect(); },
			DREAMY:     'DREAMY',
			WAVY:       'WAVY',
			HEAT_WAVE:  'HEAT_WAVE',
			FLAG:       'FLAG',
			CUSTOM:     'CUSTOM'
		});

		// ── FlxRuntimeShader directo ──────────────────────────────────────────
		// Permite crear shaders inline desde scripts sin pasar por ShaderManager.
		// El constructor acepta el código GLSL del fragment shader directamente.
		//
		// Uso en HScript:
		//   var s = new FlxRuntimeShader(fragCode);
		//   setFilters(camGame, [makeShaderFilter(s)]);
		//   s.setFloat('uIntensity', 0.5);
		//   s.setFloat('uTime', elapsed);
		//
		// Para quitar el shader:
		//   clearFilters(camGame);
		//
		// IMPORTANTE: llama a setFloat() DESPUÉS de haber añadido el shader
		// como filtro y de que se haya renderizado al menos 1 frame, porque
		// FlxRuntimeShader compila el GLSL la primera vez que se renderiza.
		// Si el uniform aún no está bound, setFloat() falla silenciosamente
		// pero puede reintentarse el frame siguiente.
		interp.variables.set('FlxRuntimeShader', {
			function(fragCode:String, ?vertCode:String):flixel.addons.display.FlxRuntimeShader
			{
				try
				{
					return vertCode != null
						? new flixel.addons.display.FlxRuntimeShader(fragCode, vertCode)
						: new flixel.addons.display.FlxRuntimeShader(fragCode);
				}
				catch (e:Dynamic)
				{
					trace('[ScriptAPI] FlxRuntimeShader error: $e');
					return null;
				}
			}
		});
		// Crea un shader desde código GLSL inline y devuelve un objeto con métodos
		// para aplicarlo fácilmente a sprites, cámaras o al video activo.
		//
		// MODO 1 — desde archivo .frag (ya existe con ShaderManager.applyShader):
		//   ShaderManager.applyShader(sprite, 'chromaKey');
		//
		// MODO 2 — inline en el script:
		//   var s = createShader('miEfecto', '
		//     uniform float uTime;
		//     void main() {
		//       vec2 uv = openfl_TextureCoordv;
		//       gl_FragColor = flixel_texture2D(bitmap, uv) * vec4(abs(sin(uTime)), 1.0, 1.0, 1.0);
		//     }
		//   ');
		//   s.applyTo(mySprite);
		//
		//   function update(elapsed) {
		//     s.set('uTime', elapsed);
		//   }
		//
		// Métodos del objeto devuelto:
		//   s.applyTo(sprite)          — aplica el shader a un sprite
		//   s.applyToCamera(?cam)      — aplica el shader como filtro de cámara
		//   s.applyToVideo()           — aplica el shader al video activo
		//   s.set(param, value)        — setea un uniform float/bool/array
		//   s.setInt(param, value)     — setea un uniform int
		//   s.remove(?sprite)          — quita el shader (de sprite o limpia instancias)
		//   s.name                     — nombre del shader
		interp.variables.set('createShader', function(name:String, fragCode:String):Dynamic
		{
			if (name == null || name.trim() == '')
			{
				trace('[ScriptAPI] createShader: nombre vacío.');
				return null;
			}

			// Registrar (o reemplazar) el shader inline en ShaderManager.
			final cs = funkin.graphics.shaders.ShaderManager.registerInline(name, fragCode);
			if (cs == null)
			{
				trace('[ScriptAPI] createShader: error al registrar "$name".');
				return null;
			}

			// Devolver objeto con API amigable.
			return {
				name: name,

				/** Aplica el shader a un FlxSprite. */
				applyTo: function(sprite:Dynamic, ?cam:Dynamic):Bool
					return funkin.graphics.shaders.ShaderManager.applyShader(sprite, name, cam),

				/** Aplica el shader como filtro de cámara (default: FlxG.camera). */
				applyToCamera: function(?cam:Dynamic):Dynamic
					return funkin.graphics.shaders.ShaderManager.applyShaderToCamera(name, cam),

				/** Aplica el shader al video activo (si hay uno). */
				applyToVideo: function():Bool
					return funkin.cutscenes.VideoManager.applyShader(name) != null,

				/** Actualiza un uniform float/bool/array. */
				set: function(param:String, value:Dynamic):Bool
					return funkin.graphics.shaders.ShaderManager.setShaderParam(name, param, value),

				/** Actualiza un uniform int (para samplers, etc.). */
				setInt: function(param:String, value:Int):Bool
					return funkin.graphics.shaders.ShaderManager.setShaderParamInt(name, param, value),

				/** Quita el shader de un sprite, o limpia todas las instancias si sprite es null. */
				remove: function(?sprite:Dynamic):Void
				{
					if (sprite != null)
						funkin.graphics.shaders.ShaderManager.removeShader(sprite);
					else
					{
						funkin.graphics.shaders.ShaderManager.clearSpriteShaders();
						funkin.cutscenes.VideoManager.removeShader(name);
					}
				},

				/** Recarga el shader con nuevo código GLSL (útil para hot-reload en debug). */
				reload: function(newFragCode:String):Void
					funkin.graphics.shaders.ShaderManager.registerInline(name, newFragCode)
			};
		});
	}

	// ─── Window + CppAPI (Windows DWM / dark mode) ────────────────────────────

	static function exposeWindow(interp:Interp):Void
	{
		interp.variables.set('Window', {
			setTitle:  function(t:String) { try { openfl.Lib.application.window.title = t; } catch(_) {} },
			getTitle:  function():String  { try { return openfl.Lib.application.window.title; } catch(_) { return ''; } },
			setFPS:    function(fps:Int)  { FlxG.updateFramerate = fps; FlxG.drawFramerate = fps; },
			getFPS:    function():Int     { return FlxG.updateFramerate; },
			getWidth:  function():Int     { return FlxG.width; },
			getHeight: function():Int     { return FlxG.height; }
		});

		// CppAPI — control de la ventana a nivel OS (Windows only, no-op en otros)
		interp.variables.set('CppAPI', extensions.CppAPI);
		interp.variables.set('nativeWindow', {
			// Colores de la barra de título (Windows 11 DWM)
			setBorderColor:  function(r:Int, g:Int, b:Int) { extensions.CppAPI.changeColor(r, g, b); },
			setCaptionColor: function(r:Int, g:Int, b:Int) { extensions.CppAPI.changeCaptionColor(r, g, b); },
			// Dark mode (Windows 10 1809+)
			enableDarkMode:  function() { extensions.CppAPI.enableDarkMode(); },
			disableDarkMode: function() { extensions.CppAPI.disableDarkMode(); },
			// DPI awareness
			setDPIAware:     function() { extensions.CppAPI.registerDPIAware(); },
			// Opacidad de la ventana
			setOpacity:      function(alpha:Float) { extensions.CppAPI.setWindowOpacity(alpha); },
			// Título (alias de Window.setTitle)
			setTitle:        function(t:String) { extensions.CppAPI.setWindowTitle(t); },
			getTitle:        function():String  { return extensions.CppAPI.windowTitle; }
		});
	}

	// ─── Visibility ───────────────────────────────────────────────────────────

	static function exposeVisibility(interp:Interp):Void
	{
		interp.variables.set('show', function(spr:Dynamic) {
			if (spr != null) { spr.visible = true; spr.active = true; }
		});
		interp.variables.set('hide', function(spr:Dynamic) {
			if (spr != null) { spr.visible = false; spr.active = false; }
		});

		// ── Velocity helpers ──────────────────────────────────────────────────
		// hscript no soporta bien la asignación encadenada obj.velocity.x = v
		// (puede lanzar "Null Function Pointer" según la versión del intérprete).
		// Usar estas funciones desde los scripts de stage es la forma segura.

		/** Establece la velocidad (vx, vy) de cualquier FlxObject. */
		interp.variables.set('setVelocity', function(spr:Dynamic, vx:Float, vy:Float):Void {
			if (spr == null) return;
			try {
				final vel = Reflect.field(spr, 'velocity');
				if (vel != null) {
					Reflect.setField(vel, 'x', vx);
					Reflect.setField(vel, 'y', vy);
				}
			} catch(_) {}
		});

		/** Establece sólo la velocidad horizontal. */
		interp.variables.set('setVelocityX', function(spr:Dynamic, vx:Float):Void {
			if (spr == null) return;
			try {
				final vel = Reflect.field(spr, 'velocity');
				if (vel != null) Reflect.setField(vel, 'x', vx);
			} catch(_) {}
		});

		/** Establece sólo la velocidad vertical. */
		interp.variables.set('setVelocityY', function(spr:Dynamic, vy:Float):Void {
			if (spr == null) return;
			try {
				final vel = Reflect.field(spr, 'velocity');
				if (vel != null) Reflect.setField(vel, 'y', vy);
			} catch(_) {}
		});

		/** Devuelve la velocidad X del sprite (0 si no tiene). */
		interp.variables.set('getVelocityX', function(spr:Dynamic):Float {
			if (spr == null) return 0.0;
			try {
				final vel = Reflect.field(spr, 'velocity');
				if (vel != null) return Reflect.field(vel, 'x');
			} catch(_) {}
			return 0.0;
		});

		/** Devuelve la velocidad Y del sprite (0 si no tiene). */
		interp.variables.set('getVelocityY', function(spr:Dynamic):Float {
			if (spr == null) return 0.0;
			try {
				final vel = Reflect.field(spr, 'velocity');
				if (vel != null) return Reflect.field(vel, 'y');
			} catch(_) {}
			return 0.0;
		});

		// ── SpriteUtil: objeto que agrupa helpers de sprites ─────────────────
		interp.variables.set('SpriteUtil', {
			setVelocity: function(spr:Dynamic, vx:Float, vy:Float):Void {
				if (spr == null) return;
				try {
					final vel = Reflect.field(spr, 'velocity');
					if (vel != null) { Reflect.setField(vel, 'x', vx); Reflect.setField(vel, 'y', vy); }
				} catch(_) {}
			},
			setVelocityX: function(spr:Dynamic, vx:Float):Void {
				if (spr == null) return;
				try { final v = Reflect.field(spr, 'velocity'); if (v != null) Reflect.setField(v, 'x', vx); } catch(_) {}
			},
			setVelocityY: function(spr:Dynamic, vy:Float):Void {
				if (spr == null) return;
				try { final v = Reflect.field(spr, 'velocity'); if (v != null) Reflect.setField(v, 'y', vy); } catch(_) {}
			},
			getVelocityX: function(spr:Dynamic):Float {
				if (spr == null) return 0.0;
				try { final v = Reflect.field(spr, 'velocity'); if (v != null) return Reflect.field(v, 'x'); } catch(_) {}
				return 0.0;
			},
			getVelocityY: function(spr:Dynamic):Float {
				if (spr == null) return 0.0;
				try { final v = Reflect.field(spr, 'velocity'); if (v != null) return Reflect.field(v, 'y'); } catch(_) {}
				return 0.0;
			},
			// Iterar sobre miembros de un FlxGroup de forma segura (sin forEach tipado)
			forEachMember: function(group:Dynamic, callback:Dynamic->Void):Void {
				if (group == null || callback == null) return;
				try {
					final members = Reflect.field(group, 'members');
					if (members == null) return;
					for (i in 0...group.length)
					{
						final m = members[i];
						if (m != null) callback(m);
					}
				} catch(_) {}
			}
		});
	}

	// ─── Utils ────────────────────────────────────────────────────────────────

	static function exposeUtils(interp:Interp):Void
	{
		// FIX: StringTools.endsWith / startsWith / trim son funciones `inline`
		// en Haxe → Reflect.field las devuelve null → Null Function Pointer en HScript.
		// Se expone 'Str' como wrapper con lambdas non-inline para cada utilidad.
		interp.variables.set('StringTools', StringTools);
		interp.variables.set('Str', {
			endsWith:   function(s:String, end:String):Bool {
				if (s == null || end == null) return false;
				final eLen = end.length;
				return eLen == 0 || (s.length >= eLen && s.substr(s.length - eLen) == end);
			},
			startsWith: function(s:String, start:String):Bool {
				if (s == null || start == null) return false;
				return s.length >= start.length && s.substr(0, start.length) == start;
			},
			trim:       function(s:String):String {
				if (s == null) return '';
				return StringTools.ltrim(StringTools.rtrim(s));
			},
			ltrim:      function(s:String):String  return s == null ? '' : StringTools.ltrim(s),
			rtrim:      function(s:String):String  return s == null ? '' : StringTools.rtrim(s),
			contains:   function(s:String, sub:String):Bool {
				return s != null && sub != null && s.indexOf(sub) != -1;
			},
			replace:    function(s:String, sub:String, by:String):String {
				if (s == null) return '';
				return StringTools.replace(s, sub, by);
			},
			hex:        function(n:Int, ?digits:Int):String  return StringTools.hex(n, digits),
			padLeft:    function(s:String, c:String, l:Int):String return StringTools.lpad(s, c, l),
			padRight:   function(s:String, c:String, l:Int):String return StringTools.rpad(s, c, l),
		});
		interp.variables.set('Std',         Std);
		interp.variables.set('Math',        Math);
		interp.variables.set('Json',        haxe.Json);
		interp.variables.set('Reflect',     Reflect);
		interp.variables.set('Type',        Type);
		interp.variables.set('trace', function(v:Dynamic) trace('[Script] $v'));
		interp.variables.set('print', function(v:Dynamic) trace('[Script] $v'));

		// FlxAtlasFramesExt — crear atlas desde grid (sin XML/JSON)
		interp.variables.set('FlxAtlasFramesExt', extensions.FlxAtlasFramesExt);
		interp.variables.set('atlasFrames', {
			// Crea frames de un tileset por grid: fromGraphic(graphic, 64, 64)
			fromGraphic: function(graphic:Dynamic, frameWidth:Int, frameHeight:Int, ?name:String):Dynamic {
				return extensions.FlxAtlasFramesExt.fromGraphic(graphic, frameWidth, frameHeight, name);
			},
			// Sparrow Atlas desde XML (wrapper de FlxAtlasFrames)
			fromSparrow: function(source:Dynamic, desc:Dynamic):Dynamic {
				return flixel.graphics.frames.FlxAtlasFrames.fromSparrow(source, desc);
			},
			// Packer Atlas desde TXT
			fromPacker: function(source:Dynamic, desc:Dynamic):Dynamic {
				return flixel.graphics.frames.FlxAtlasFrames.fromTexturePackerJson(source, desc);
			}
		});

		// Acceso al sistema de archivos (solo en targets sys como Windows/Linux/Mac)
		#if sys
		interp.variables.set('FileSystem', sys.FileSystem);
		interp.variables.set('File', {
			read:         function(path:String):String {
				try { return sys.io.File.getContent(path); } catch(_) { return null; }
			},
			readBytes:    function(path:String):Dynamic {
				try { return sys.io.File.getBytes(path); } catch(_) { return null; }
			},
			write:        function(path:String, content:String) {
				try { sys.io.File.saveContent(path, content); } catch(_) {}
			},
			exists:       function(path:String):Bool { return sys.FileSystem.exists(path); },
			isDirectory:  function(path:String):Bool {
				return sys.FileSystem.exists(path) && sys.FileSystem.isDirectory(path);
			},
			listDir:      function(path:String):Array<String> {
				try { return sys.FileSystem.readDirectory(path); } catch(_) { return []; }
			},
			createDir:    function(path:String) {
				try { sys.FileSystem.createDirectory(path); } catch(_) {}
			},
			deleteFile:   function(path:String) {
				try { sys.FileSystem.deleteFile(path); } catch(_) {}
			}
		});
		#end

		// Haxe utils útiles
		interp.variables.set('Xml',  Xml);
		interp.variables.set('EReg', EReg);
	}

	// ─── Events ───────────────────────────────────────────────────────────────

	static function exposeEvents(interp:Interp):Void
	{
		interp.variables.set('EventManager',      funkin.scripting.events.EventManager);
		interp.variables.set('EventRegistry',     funkin.scripting.events.EventRegistry);
		interp.variables.set('EventHandlerLoader',funkin.scripting.events.EventHandlerLoader);

		// Objeto 'events' con API de alto nivel para scripts de mods
		interp.variables.set('events', {
			/**
			 * Dispara un evento inmediatamente (fuera del timeline del chart).
			 *   events.fire("Camera Shake", "0.01", "0.5")
			 */
			fire: function(name:String, ?v1:String, ?v2:String) {
				funkin.scripting.events.EventManager.fireEvent(name, v1 ?? '', v2 ?? '');
			},
			/**
			 * Registra un handler para un evento concreto.
			 * El handler recibe (v1, v2, time) y puede retornar true para
			 * cancelar el built-in.
			 *   events.on("My Event", function(v1, v2, time) { ... })
			 */
			on: function(name:String, handler:Dynamic) {
				funkin.scripting.events.EventManager.registerCustomEvent(name, function(evArr) {
					final e = evArr != null && evArr.length > 0 ? evArr[0] : null;
					if (e == null) return false;
					try { return handler(e.value1, e.value2, e.time) == true; }
					catch(_) return false;
				});
			},
			/**
			 * Lista de todos los nombres de eventos registrados en un contexto.
			 *   events.list("chart")   → ["Camera Follow", "BPM Change", ...]
			 *   events.list()          → todos
			 */
			list: function(?context:String):Array<String> {
				if (context != null)
					return funkin.scripting.events.EventRegistry.getNamesForContext(context);
				return funkin.scripting.events.EventRegistry.eventList;
			},
			/**
			 * Definición completa de un evento (params, color, descripción, etc.)
			 *   var def = events.get("Camera Follow")
			 *   trace(def.description)
			 *   trace(def.params.length)
			 */
			get: function(name:String):Dynamic {
				return funkin.scripting.events.EventRegistry.get(name);
			},
			/**
			 * Registra un nuevo evento con su definición completa.
			 * Si tiene scriptPath, lo carga como handler.
			 *   events.register({
			 *     name: "My Event",
			 *     description: "Does something cool",
			 *     color: 0xFF88FF88,
			 *     contexts: ["chart"],
			 *     aliases: ["ME"],
			 *     params: [{ name: "Value", type: "String", defaultValue: "" }]
			 *   })
			 */
			register: function(def:Dynamic) {
				final paramDefs:Array<funkin.scripting.events.EventInfoSystem.EventParamDef> = [];
				if (def.params != null && Std.isOfType(def.params, Array))
				{
					for (p in (def.params : Array<Dynamic>))
					{
						if (p == null || p.name == null) continue;
						paramDefs.push({
							name:     Std.string(p.name),
							type:     funkin.scripting.events.EventInfoSystem.parseParamType(
							              Std.string(p.type ?? 'String')),
							defValue: p.defaultValue != null ? Std.string(p.defaultValue) : '',
							description: p.description != null ? Std.string(p.description) : null
						});
					}
				}
				funkin.scripting.events.EventRegistry.register({
					name:        Std.string(def.name ?? ''),
					description: def.description != null ? Std.string(def.description) : null,
					color:       def.color  != null ? Std.int(def.color) : 0xFFAAAAAA,
					contexts:    def.contexts != null && Std.isOfType(def.contexts, Array)
					             ? [for (c in (def.contexts:Array<Dynamic>)) Std.string(c)]
					             : ['chart'],
					aliases:     def.aliases != null && Std.isOfType(def.aliases, Array)
					             ? [for (a in (def.aliases:Array<Dynamic>)) Std.string(a)]
					             : [],
					params:      paramDefs,
					hscriptPath: def.hscriptPath != null ? Std.string(def.hscriptPath) : null,
					luaPath:     def.luaPath     != null ? Std.string(def.luaPath)     : null,
					sourceDir:   null
				});
			}
		});
	}

	// ─── Debug ────────────────────────────────────────────────────────────────

	static function exposeDebug(interp:Interp):Void
	{
		interp.variables.set('debug', {
			log:    function(msg:Dynamic) trace('[ScriptDebug] $msg'),
			warn:   function(msg:Dynamic) trace('[ScriptWARN] $msg'),
			error:  function(msg:Dynamic) trace('[ScriptERROR] $msg'),
			assert: function(cond:Bool, msg:String) { if (!cond) trace('[ScriptASSERT FAIL] $msg'); },
			drawBox: function(x:Float, y:Float, w:Float, h:Float, ?color:Int) {
				#if FLX_DEBUG
				var gfx = FlxG.camera.debugLayer.graphics;
				gfx.lineStyle(1, color ?? 0xFFFF0000, 1.0);
				gfx.drawRect(x, y, w, h);
				#end
			}
		});
	}

	// ─── Strums ───────────────────────────────────────────────────────────────

	static function exposeStrums(interp:Interp):Void
	{
		interp.variables.set('strum', {
			getGroup: function(id:String):Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				return ps != null ? ps.strumsGroupMap.get(id) : null;
			},
			getPlayer: function():Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				return (ps != null) ? ps.playerStrumsGroup : null;
			},
			getCpu: function():Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				return (ps != null) ? ps.cpuStrumsGroup : null;
			},
			getAll: function():Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				return (ps != null) ? ps.strumsGroups : [];
			},
			getStrum: function(groupId:String, idx:Int):Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return null;
				final g = ps.strumsGroupMap.get(groupId);
				return (g != null) ? g.getStrum(idx) : null;
			},
			getPlayerStrum: function(idx:Int):Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null || ps.playerStrumsGroup == null) return null;
				return ps.playerStrumsGroup.getStrum(idx);
			},
			getCpuStrum: function(idx:Int):Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null || ps.cpuStrumsGroup == null) return null;
				return ps.cpuStrumsGroup.getStrum(idx);
			},
			setX: function(groupId:String, idx:Int, v:Float) {
				final ps = funkin.gameplay.PlayState.instance; if (ps == null) return;
				final s = ps.strumsGroupMap.get(groupId)?.getStrum(idx);
				if (s != null) s.x = v;
			},
			setY: function(groupId:String, idx:Int, v:Float) {
				final ps = funkin.gameplay.PlayState.instance; if (ps == null) return;
				final s = ps.strumsGroupMap.get(groupId)?.getStrum(idx);
				if (s != null) s.y = v;
			},
			setAlpha: function(groupId:String, idx:Int, v:Float) {
				final ps = funkin.gameplay.PlayState.instance; if (ps == null) return;
				final s = ps.strumsGroupMap.get(groupId)?.getStrum(idx);
				if (s != null) s.alpha = v;
			},
			setAngle: function(groupId:String, idx:Int, v:Float) {
				final ps = funkin.gameplay.PlayState.instance; if (ps == null) return;
				final s = ps.strumsGroupMap.get(groupId)?.getStrum(idx);
				if (s != null) s.angle = v;
			},
			setVisible: function(groupId:String, idx:Int, v:Bool) {
				final ps = funkin.gameplay.PlayState.instance; if (ps == null) return;
				final s = ps.strumsGroupMap.get(groupId)?.getStrum(idx);
				if (s != null) s.visible = v;
			},
			setScale: function(groupId:String, idx:Int, sx:Float, ?sy:Float) {
				final ps = funkin.gameplay.PlayState.instance; if (ps == null) return;
				final s = ps.strumsGroupMap.get(groupId)?.getStrum(idx);
				if (s != null) s.scale.set(sx, sy ?? sx);
			},
			setGroupVisible: function(groupId:String, v:Bool) {
				final ps = funkin.gameplay.PlayState.instance; if (ps == null) return;
				final g = ps.strumsGroupMap.get(groupId);
				if (g != null) g.setVisible(v);
			},
			setGroupPosition: function(groupId:String, x:Float, y:Float) {
				final ps = funkin.gameplay.PlayState.instance; if (ps == null) return;
				final g = ps.strumsGroupMap.get(groupId);
				if (g != null) g.setPosition(x, y);
			},
			setGroupSpacing: function(groupId:String, spacing:Float) {
				final ps = funkin.gameplay.PlayState.instance; if (ps == null) return;
				final g = ps.strumsGroupMap.get(groupId);
				if (g != null) g.setSpacing(spacing);
			}
		});
	}

	// ─── ModChart ─────────────────────────────────────────────────────────────

	static function exposeModChart(interp:Interp):Void
	{
		interp.variables.set('modchart', {
			add: function(beat:Float, target:String, strumIdx:Int, type:String, value:Float,
			              ?duration:Float, ?ease:String) {
				final mc = funkin.gameplay.modchart.ModChartManager.instance;
				if (mc == null) return;
				mc.addEventSimple(beat, target, strumIdx, type, value, duration ?? 0.0, ease ?? "linear");
			},
			addNow: function(target:String, strumIdx:Int, type:String, value:Float,
			                 ?duration:Float, ?ease:String) {
				final mc = funkin.gameplay.modchart.ModChartManager.instance;
				if (mc == null) return;
				final beat = funkin.data.Conductor.crochet > 0
					? funkin.data.Conductor.songPosition / funkin.data.Conductor.crochet : 0.0;
				mc.addEventSimple(beat, target, strumIdx, type, value, duration ?? 0.0, ease ?? "linear");
			},
			clear:     function() { final mc = funkin.gameplay.modchart.ModChartManager.instance; if (mc != null) mc.clearEvents(); },
			reset:     function() { final mc = funkin.gameplay.modchart.ModChartManager.instance; if (mc != null) mc.resetToStart(); },
			enable:    function() { final mc = funkin.gameplay.modchart.ModChartManager.instance; if (mc != null) mc.enabled = true; },
			disable:   function() { final mc = funkin.gameplay.modchart.ModChartManager.instance; if (mc != null) mc.enabled = false; },
			isEnabled: function():Bool { final mc = funkin.gameplay.modchart.ModChartManager.instance; return mc != null ? mc.enabled : false; },
			manager:   function():Dynamic { return funkin.gameplay.modchart.ModChartManager.instance; },
			seek:      function(beat:Float) { final mc = funkin.gameplay.modchart.ModChartManager.instance; if (mc != null) mc.seekToBeat(beat); }
		});
	}

	// ═══════════════════════════════════════════════════════════════════════════
	//  NUEVO v6
	// ═══════════════════════════════════════════════════════════════════════════

	// ─── Mathf proxy completo ─────────────────────────────────────────────────
	// Todas las funciones de funkin.data.Mathf + las de extensions.Mathf,
	// expuestas como lambdas porque la mayoría son static inline (invisibles
	// por reflexión en targets compilados).
	static function exposeMathf(interp:Interp):Void
	{
		interp.variables.set('Mathf', {
			// ── funkin.data.Mathf ──────────────────────────────────────────────
			roundTo:      function(n:Float, dec:Float):Float {
				final f = Math.pow(10, dec);
				return Math.round(n * f) / f;
			},
			percent:      function(value:Float, total:Float):Float {
				return total == 0 ? 0 : Math.round(value / total * 100);
			},
			clamp:        function(v:Float, min:Float, max:Float):Float {
				if (v < min) return min; if (v > max) return max; return v;
			},
			clampInt:     function(v:Int, min:Int, max:Int):Int {
				if (v < min) return min; if (v > max) return max; return v;
			},
			remap:        function(v:Float, i0:Float, i1:Float, o0:Float, o1:Float):Float {
				return o0 + (v - i0) * (o1 - o0) / (i1 - i0);
			},
			toRadians:    function(deg:Float):Float return deg * (Math.PI / 180.0),
			toDegrees:    function(rad:Float):Float return rad * (180.0 / Math.PI),
			floorInt:     function(v:Float):Int return Std.int(Math.floor(v)),
			ceilInt:      function(v:Float):Int  return Std.int(Math.ceil(v)),
			absInt:       function(v:Int):Int    return v < 0 ? -v : v,
			lerp:         function(a:Float, b:Float, t:Float):Float return a + (b - a) * t,
			// sine() con acumulador externo — SIN estado global compartido.
			// Uso: sineAcc += elapsed; sprite.y += Mathf.sine(sineAcc, 2.0) * 5;
			sine:         function(acc:Float, speed:Float = 1.0):Float return Math.sin(acc * speed),
			// ── extensions.Mathf ──────────────────────────────────────────────
			// Equivalente a sineByTime pero sin la static var compartida.
			// Mantén tu propio acumulador en el script:
			//   var t = 0.0; // en onUpdate: t += elapsed; sprite.y += Mathf.sineAcc(t);
			sineAcc:      function(acc:Float, ?multi:Float):Float {
				return Math.sin(Math.abs(acc * (multi != null ? multi : 1.0)));
			},
			radiants2degrees: function(v:Float):Float return v * (180 / Math.PI),
			degrees2radiants: function(v:Float):Float return v * (Math.PI / 180),
			getPercentage:    function(number:Float, toGet:Float):Float {
				var num = number;
				num = num * Math.pow(10, toGet);
				num = Math.round(num) / Math.pow(10, toGet);
				return num;
			},
			floor2int: function(v:Float):Int return Std.int(Math.floor(Math.abs(v))),
			// ── Constantes ────────────────────────────────────────────────────
			DEG_TO_RAD: Math.PI / 180.0,
			RAD_TO_DEG: 180.0 / Math.PI
		});
	}

	// ─── CoolUtil proxy ───────────────────────────────────────────────────────

	static function exposeCoolUtil(interp:Interp):Void
	{
		interp.variables.set('CoolUtil', {
			// Nombre de la dificultad actual
			difficultyString: function():String return funkin.data.CoolUtil.difficultyString(),
			// Leer un archivo de texto y dividir en líneas
			coolTextFile:     function(path:String):Array<String> {
				return funkin.data.CoolUtil.coolTextFile(path);
			},
			// Dividir un string en líneas
			coolStringFile:   function(content:String):Array<String> {
				return funkin.data.CoolUtil.coolStringFile(content);
			},
			// Array de enteros [min..max)
			numberArray:      function(max:Int, ?min:Int):Array<Int> {
				return funkin.data.CoolUtil.numberArray(max, min != null ? min : 0);
			},
			capitalize:       function(s:String):String return funkin.data.CoolUtil.capitalize(s),
			truncate:         function(s:String, maxLen:Int):String return funkin.data.CoolUtil.truncate(s, maxLen),
			// Arrays de dificultad
			difficultyArray:  funkin.data.CoolUtil.difficultyArray,
			difficultyPath:   funkin.data.CoolUtil.difficultyPath
		});
	}

	// ─── CameraUtil proxy ─────────────────────────────────────────────────────

	static function exposeCameraUtil(interp:Interp):Void
	{
		interp.variables.set('CameraUtil', {
			create:        function(?addToStack:Bool):FlxCamera {
				return funkin.data.CameraUtil.create(addToStack != null ? addToStack : true);
			},
			addShader:     function(shader:Dynamic, ?cam:FlxCamera):Dynamic {
				return funkin.data.CameraUtil.addShader(shader, cam);
			},
			removeFilter:  function(filter:Dynamic, ?cam:FlxCamera):Bool {
				return funkin.data.CameraUtil.removeFilter(filter, cam);
			},
			clearFilters:  function(?cam:FlxCamera) { funkin.data.CameraUtil.clearFilters(cam); },
			getFilters:    function(?cam:FlxCamera):Array<Dynamic> {
				return funkin.data.CameraUtil.getFilters(cam ?? FlxG.camera);
			},
			optimizeForGameplay: function(cam:FlxCamera) {
				funkin.data.CameraUtil.optimizeForGameplay(cam);
			},
			lastCamera:    function():FlxCamera { return funkin.data.CameraUtil.lastCamera; }
		});
	}

	// ─── add / remove directos ────────────────────────────────────────────────

	static function exposeAddRemove(interp:Interp):Void
	{
		// add(sprite) → game.add(sprite) si estamos en PlayState, si no FlxG.state.add()
		interp.variables.set('add', function(obj:Dynamic):Dynamic {
			final ps = funkin.gameplay.PlayState.instance;
			if (ps != null) return ps.add(obj);
			if (FlxG.state != null) return FlxG.state.add(obj);
			return null;
		});
		interp.variables.set('remove', function(obj:Dynamic, ?splice:Bool):Dynamic {
			final ps = funkin.gameplay.PlayState.instance;
			if (ps != null) return ps.remove(obj, splice ?? false);
			if (FlxG.state != null) return FlxG.state.remove(obj, splice ?? false);
			return null;
		});

		// ── Helpers de z-orden para scripts de personaje ──────────────────────
		// addBehindChar(sprite, character) → inserta ANTES del personaje (queda detrás)
		interp.variables.set('addBehindChar', function(obj:Dynamic, charObj:Dynamic):Dynamic {
			final ps = funkin.gameplay.PlayState.instance;
			if (ps == null || obj == null) return null;
			if (charObj == null) return ps.add(obj);
			final idx = ps.members.indexOf(cast charObj);
			if (idx < 0) return ps.add(obj);
			return ps.insert(idx, cast obj);
		});
		// addInFrontOfChar(sprite, character) → inserta DESPUÉS del personaje (queda encima)
		interp.variables.set('addInFrontOfChar', function(obj:Dynamic, charObj:Dynamic):Dynamic {
			final ps = funkin.gameplay.PlayState.instance;
			if (ps == null || obj == null) return null;
			if (charObj == null) return ps.add(obj);
			final idx = ps.members.indexOf(cast charObj);
			if (idx < 0) return ps.add(obj);
			return ps.insert(idx + 1, cast obj);
		});
		// insertAt(sprite, index) → inserta en un índice concreto
		interp.variables.set('insertAt', function(obj:Dynamic, index:Int):Dynamic {
			final ps = funkin.gameplay.PlayState.instance;
			if (ps == null || obj == null) return null;
			return ps.insert(Std.int(Math.max(0, index)), cast obj);
		});
		// setFilters / clearFilters / makeShaderFilter
		// HScript no puede acceder a .filters en cpp (propiedad nativa OpenFL).
		// Estos helpers lo hacen desde Haxe compilado donde sí funciona.
		//
		// BUGFIX: FlxCamera en Flixel 5 extiende FlxBasic, NO DisplayObject.
		// El cast inseguro a DisplayObject + .filters = null crasheaba en C++/HL.
		// Si el objeto es FlxCamera usamos CameraUtil que accede a cam._filters
		// con @:access. Para cualquier otro DisplayObject usamos el cast normal.
		interp.variables.set('setFilters', function(obj:Dynamic, filters:Array<Dynamic>):Void {
			if (obj == null) return;
			if (Std.isOfType(obj, FlxCamera))
				funkin.data.CameraUtil.setFilters(cast obj, cast filters);
			else
			{
				var disp:openfl.display.DisplayObject = cast obj;
				disp.filters = filters != null ? cast filters : null;
			}
		});
		interp.variables.set('clearFilters', function(obj:Dynamic):Void {
			if (obj == null) return;
			if (Std.isOfType(obj, FlxCamera))
				funkin.data.CameraUtil.clearFilters(cast obj);
			else
			{
				var disp:openfl.display.DisplayObject = cast obj;
				disp.filters = null;
			}
		});
		interp.variables.set('makeShaderFilter', function(shader:Dynamic):Dynamic {
			if (shader == null) return null;
			return new openfl.filters.ShaderFilter(cast shader);
		});

		// addToHUD(sprite) → añade a camHUD
		interp.variables.set('addToHUD', function(obj:Dynamic) {
			final ps = funkin.gameplay.PlayState.instance;
			if (ps == null || obj == null) return;
			if (Reflect.hasField(obj, 'cameras')) {
				final camHUD = Reflect.field(ps, 'camHUD');
				if (camHUD != null) obj.cameras = [camHUD];
			}
			ps.add(obj);
		});
	}

	// ─── Stage access ─────────────────────────────────────────────────────────

	static function exposeStageAccess(interp:Interp):Void
	{
		interp.variables.set('stage', {
			// Referencia directa al Stage actual
			get:          function():Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				return ps != null ? Reflect.field(ps, 'currentStage') : null;
			},
			// Obtener un elemento del stage por nombre
			getElement:   function(name:String):Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return null;
				final st = Reflect.field(ps, 'currentStage');
				return st != null ? st.getElement(name) : null;
			},
			// Obtener un grupo del stage por nombre
			getGroup:     function(name:String):Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return null;
				final st = Reflect.field(ps, 'currentStage');
				return st != null ? st.getGroup(name) : null;
			},
			// Obtener un sonido del stage por nombre
			getSound:     function(name:String):Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return null;
				final st = Reflect.field(ps, 'currentStage');
				return st != null ? st.getSound(name) : null;
			},
			// Obtener una custom class del stage por nombre
			getCustomClass: function(name:String):Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return null;
				final st = Reflect.field(ps, 'currentStage');
				return st != null ? st.getCustomClass(name) : null;
			},
			// Nombre del stage actual
			name:         function():String {
				final ps = funkin.gameplay.PlayState.instance;
				return ps != null ? Reflect.field(ps, 'curStage') : '';
			},
			// Posiciones de referencia del stage
			bfPos:        function():Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return null;
				final st = Reflect.field(ps, 'currentStage');
				return st != null ? st.boyfriendPosition : null;
			},
			dadPos:       function():Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return null;
				final st = Reflect.field(ps, 'currentStage');
				return st != null ? st.dadPosition : null;
			},
			gfPos:        function():Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return null;
				final st = Reflect.field(ps, 'currentStage');
				return st != null ? st.gfPosition : null;
			},
			// Default camera zoom del stage
			defaultZoom:  function():Float {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return 1.05;
				final st = Reflect.field(ps, 'currentStage');
				return st != null ? st.defaultCamZoom : 1.05;
			},
			isPixel:      function():Bool {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return false;
				final st = Reflect.field(ps, 'currentStage');
				return st != null ? st.isPixelStage : false;
			}
		});
	}

	// ─── NoteManager access ───────────────────────────────────────────────────

	static function exposeNoteManagerAccess(interp:Interp):Void
	{
		interp.variables.set('noteManager', {
			get:             function():Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				return ps != null ? ps.noteManager : null;
			},
			setDownscroll:   function(v:Bool) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.noteManager != null) ps.noteManager.downscroll = v;
			},
			setMiddlescroll: function(v:Bool) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.noteManager != null) ps.noteManager.middlescroll = v;
			},
			setStrumLineY:   function(v:Float) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.noteManager != null) ps.noteManager.strumLineY = v;
			},
			getStats:        function():String {
				final ps = funkin.gameplay.PlayState.instance;
				return (ps != null && ps.noteManager != null) ? ps.noteManager.getPoolStats() : '';
			},
			toggleBatching:  function() {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.noteManager != null) ps.noteManager.toggleBatching();
			}
		});
	}

	// ─── Input access ─────────────────────────────────────────────────────────

	static function exposeInputAccess(interp:Interp):Void
	{
		interp.variables.set('input', {
			// Arrays de estado de teclas — acceso directo
			held:     function():Array<Bool> {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return [false,false,false,false];
				final ih = Reflect.field(ps, 'inputHandler');
				return ih != null ? ih.held : [false,false,false,false];
			},
			pressed:  function():Array<Bool> {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return [false,false,false,false];
				final ih = Reflect.field(ps, 'inputHandler');
				return ih != null ? ih.pressed : [false,false,false,false];
			},
			released: function():Array<Bool> {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return [false,false,false,false];
				final ih = Reflect.field(ps, 'inputHandler');
				return ih != null ? ih.released : [false,false,false,false];
			},
			isHeld:    function(dir:Int):Bool {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return false;
				final ih = Reflect.field(ps, 'inputHandler');
				return ih != null ? ih.held[dir] : false;
			},
			isPressed: function(dir:Int):Bool {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return false;
				final ih = Reflect.field(ps, 'inputHandler');
				return ih != null ? ih.pressed[dir] : false;
			},
			setGhostTapping: function(v:Bool) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return;
				final ih = Reflect.field(ps, 'inputHandler');
				if (ih != null) ih.ghostTapping = v;
			},
			// Acceso al FlxKey — útil para binds personalizados
			isKeyDown:  function(keyName:String):Bool {
				try {
					final key = flixel.input.keyboard.FlxKey.fromString(keyName);
					return FlxG.keys.checkStatus(key, flixel.input.FlxInput.FlxInputState.PRESSED);
				} catch(_) { return false; }
			},
			isKeyJustPressed: function(keyName:String):Bool {
				try {
					final key = flixel.input.keyboard.FlxKey.fromString(keyName);
					return FlxG.keys.checkStatus(key, flixel.input.FlxInput.FlxInputState.JUST_PRESSED);
				} catch(_) { return false; }
			}
		});
	}

	// ─── VideoManager ─────────────────────────────────────────────────────────

	static function exposeVideoManager(interp:Interp):Void
	{
		interp.variables.set('VideoManager', funkin.cutscenes.VideoManager);
		interp.variables.set('video', {
			play:       function(key:String, ?onComplete:Dynamic) {
				funkin.cutscenes.VideoManager.playCutscene(key, onComplete);
			},
			playMidSong: function(key:String, ?onComplete:Dynamic) {
				funkin.cutscenes.VideoManager.playMidSong(key, onComplete);
			},
			stop:       function() { funkin.cutscenes.VideoManager.stop(); },
			pause:      function() { funkin.cutscenes.VideoManager.pause(); },
			resume:     function() { funkin.cutscenes.VideoManager.resume(); },
			isPlaying:  function():Bool { return funkin.cutscenes.VideoManager.isPlaying; },
			onSprite:   function(key:String, sprite:Dynamic, ?onComplete:Dynamic) {
				funkin.cutscenes.VideoManager.playOnSprite(key, sprite, onComplete);
			},

			// ── Shaders en video ──────────────────────────────────────────────
			// Permite aplicar shaders al video en reproducción desde scripts HScript.
			//
			// Ejemplo de uso en un script:
			//   video.applyShader('chromaKey');
			//   video.setShaderParam('chromaKey', 'threshold', 0.25);
			//   video.removeShader('chromaKey');
			//   video.clearShaders();

			/**
			 * Aplica un shader del ShaderManager al video activo.
			 * Devuelve true si se aplicó correctamente.
			 */
			applyShader: function(shaderName:String):Bool {
				return funkin.cutscenes.VideoManager.applyShader(shaderName) != null;
			},

			/**
			 * Actualiza un parámetro/uniform del shader del video.
			 *   video.setShaderParam('wave', 'amplitude', 0.05);
			 */
			setShaderParam: function(shaderName:String, paramName:String, value:Dynamic):Bool {
				return funkin.cutscenes.VideoManager.setVideoShaderParam(shaderName, paramName, value);
			},

			/**
			 * Quita un shader específico del video.
			 */
			removeShader: function(shaderName:String):Void {
				funkin.cutscenes.VideoManager.removeShader(shaderName);
			},

			/**
			 * Quita todos los shaders del video activo.
			 */
			clearShaders: function():Void {
				funkin.cutscenes.VideoManager.clearVideoShaders();
			},

			/**
			 * Aplica un BitmapFilter/ShaderFilter OpenFL directamente al video.
			 * Útil para shaders creados en el script sin pasar por ShaderManager:
			 *
			 *   var shader = new flixel.addons.display.FlxRuntimeShader(fragCode);
			 *   var filter = new openfl.filters.ShaderFilter(shader);
			 *   video.applyFilter(filter);
			 */
			applyFilter: function(filter:Dynamic):Void {
				funkin.cutscenes.VideoManager.applyRawFilter(filter);
			},

			/**
			 * Quita un BitmapFilter aplicado con applyFilter().
			 */
			removeFilter: function(filter:Dynamic):Void {
				funkin.cutscenes.VideoManager.removeRawFilter(filter);
			}
		});
	}

	// ─── Highscore ────────────────────────────────────────────────────────────

	static function exposeHighscore(interp:Interp):Void
	{
		interp.variables.set('Highscore', funkin.gameplay.objects.hud.Highscore);
		interp.variables.set('highscore', {
			// suffix = sufijo de dificultad como string: "-hard", "-erect", "" (normal)
			// Si no se pasa suffix, usa la dificultad actual automáticamente.
			saveScore:  function(song:String, score:Int, ?suffix:String) {
				funkin.gameplay.objects.hud.Highscore.saveScore(song, score, suffix ?? funkin.data.CoolUtil.difficultySuffix());
			},
			saveRating: function(song:String, rating:Float, ?suffix:String) {
				funkin.gameplay.objects.hud.Highscore.saveRating(song, rating, suffix ?? funkin.data.CoolUtil.difficultySuffix());
			},
			getScore:   function(song:String, ?suffix:String):Int {
				return funkin.gameplay.objects.hud.Highscore.getScore(song, suffix ?? funkin.data.CoolUtil.difficultySuffix());
			},
			getRating:  function(song:String, ?suffix:String):Float {
				return funkin.gameplay.objects.hud.Highscore.getRating(song, suffix ?? funkin.data.CoolUtil.difficultySuffix());
			},
			saveWeek:   function(week:Int, score:Int, ?suffix:String) {
				funkin.gameplay.objects.hud.Highscore.saveWeekScore(week, score, suffix ?? funkin.data.CoolUtil.difficultySuffix());
			},
			getWeek:    function(week:Int, ?suffix:String):Int {
				return funkin.gameplay.objects.hud.Highscore.getWeekScore(week, suffix ?? funkin.data.CoolUtil.difficultySuffix());
			},
			format:     function(song:String, suffix:String):String {
				return funkin.gameplay.objects.hud.Highscore.formatSongBySuffix(song, suffix);
			},
			currentSuffix: function():String {
				return funkin.data.CoolUtil.difficultySuffix();
			},
			load: function() { funkin.gameplay.objects.hud.Highscore.load(); }
		});
	}

	// ─── Ranking ──────────────────────────────────────────────────────────────

	static function exposeRanking(interp:Interp):Void
	{
		interp.variables.set('Ranking', funkin.data.Ranking);
		interp.variables.set('ranking', {
			getLetterRank: function():String { return funkin.data.Ranking.generateLetterRank(); }
		});
	}

	// ─── CharacterList ────────────────────────────────────────────────────────────────────────────

	static function exposeCharacterList(interp:Interp):Void
	{
		// FIX: HScript no puede acceder a campos/métodos estáticos de una clase
		// Haxe expuesta directamente (Reflect.getProperty falla en static fields).
		//
		// Problema con un objeto anónimo simple:
		//   CharacterList.reload() reemplaza los arrays con nuevas instancias
		//   (boyfriends = []), así que un campo capturado al inicio quedaría obsoleto.
		//
		// Solución: crear el wrapper primero, luego asignar 'reload' e 'init' como
		// lambdas que llaman a CL.reload/init Y actualizan los campos del propio
		// wrapper via Reflect.setField. Así CharacterList.boyfriends siempre
		// refleja el estado actual después de cada reload.
		final CL = funkin.gameplay.objects.character.CharacterList;
		final w:Dynamic = {
			boyfriends:  CL.boyfriends,
			opponents:   CL.opponents,
			girlfriends: CL.girlfriends,
			stages:      CL.stages,
			getCharacterName:       function(c:String)    return CL.getCharacterName(c),
			getStageName:           function(s:String)    return CL.getStageName(s),
			getDefaultStageForSong: function(song:String) return CL.getDefaultStageForSong(song),
			getDefaultGFForStage:   function(stg:String)  return CL.getDefaultGFForStage(stg),
			getAllCharacters:       function()            return CL.getAllCharacters()
		};
		w.init   = function():Void {
			CL.init();
			Reflect.setField(w, 'boyfriends',  CL.boyfriends);
			Reflect.setField(w, 'opponents',   CL.opponents);
			Reflect.setField(w, 'girlfriends', CL.girlfriends);
			Reflect.setField(w, 'stages',      CL.stages);
		};
		w.reload = function():Void {
			CL.reload();
			Reflect.setField(w, 'boyfriends',  CL.boyfriends);
			Reflect.setField(w, 'opponents',   CL.opponents);
			Reflect.setField(w, 'girlfriends', CL.girlfriends);
			Reflect.setField(w, 'stages',      CL.stages);
		};
		interp.variables.set('CharacterList', w);

		// charList se mantiene por compatibilidad con scripts que ya lo usen
		interp.variables.set('charList', {
			boyfriends:      function():Array<String>  { return CL.boyfriends; },
			opponents:       function():Array<String>  { return CL.opponents; },
			girlfriends:     function():Array<String>  { return CL.girlfriends; },
			stages:          function():Array<String>  { return CL.stages; },
			getName:         function(c:String):String { return CL.getCharacterName(c); },
			getStageName:    function(s:String):String { return CL.getStageName(s); },
			getDefaultStage: function(song:String):String { return CL.getDefaultStageForSong(song); }
		});
	}

	// ─── PlayStateConfig ──────────────────────────────────────────────────────

	static function exposePlayStateConfig(interp:Interp):Void
	{
		interp.variables.set('PlayStateConfig', funkin.gameplay.PlayStateConfig);
		// Constantes inline — hay que leerlas en tiempo de compilación
		interp.variables.set('PSC', {
			DEFAULT_ZOOM     : 1.05,
			PIXEL_ZOOM       : 6.0,
			STRUM_LINE_Y     : 50.0,
			NOTE_SPAWN_TIME  : 3000.0,
			SICK_WINDOW      : 45.0,
			GOOD_WINDOW      : 90.0,
			BAD_WINDOW       : 135.0,
			SHIT_WINDOW      : 166.0,
			SICK_SCORE       : 350,
			GOOD_SCORE       : 200,
			BAD_SCORE        : 100,
			SHIT_SCORE       : 50,
			SICK_HEALTH      : 0.1,
			GOOD_HEALTH      : 0.05,
			BAD_HEALTH       : -0.03,
			SHIT_HEALTH      : -0.03,
			MISS_HEALTH      : -0.04,
			CAM_LERP_SPEED   : 2.4,
			CAM_ZOOM_AMOUNT  : 0.015,
			CAM_HUD_ZOOM_AMOUNT: 0.03
		});
	}

	// ─── Transition ───────────────────────────────────────────────────────────

	static function exposeTransition(interp:Interp):Void
	{
		interp.variables.set('StateTransition', funkin.transitions.StateTransition);
		interp.variables.set('StickerTransition', funkin.transitions.StickerTransition);
		interp.variables.set('transition', {
			setNext:    function(?type:Dynamic, ?duration:Float, ?color:Int) {
				funkin.transitions.StateTransition.setNext(type, duration, color);
			},
			setGlobal:  function(?type:Dynamic, ?duration:Float, ?color:Int) {
				funkin.transitions.StateTransition.setGlobal(type, duration, color);
			},
			enable:     function() { funkin.transitions.StateTransition.enabled = true; },
			disable:    function() { funkin.transitions.StateTransition.enabled = false; },
			sticker:    function(?callback:Dynamic) {
				funkin.transitions.StickerTransition.start(callback);
			},
			clearStickers: function(?onDone:Dynamic) {
				funkin.transitions.StickerTransition.clearStickers(onDone);
			},
			stickerActive: function():Bool { return funkin.transitions.StickerTransition.isActive(); }
		});

		// ── Auto-resize: mantener la transición cubriendo toda la ventana ─────────
		// FlxG.width/height son las dimensiones VIRTUALES del juego (p.ej. 1280x720).
		// Cuando el usuario redimensiona la ventana, el stage de OpenFL escala el
		// contenido, pero cualquier overlay que haya creado StateTransition con
		// makeGraphic(FlxG.width, FlxG.height) queda más pequeño que la pantalla real.
		// Solución: escuchar el evento RESIZE del stage y pedir a StateTransition
		// que actualice su tamaño usando las dimensiones reales de la ventana.
		try {
			var stage = openfl.Lib.current.stage;
			if (stage != null) {
				stage.addEventListener(openfl.events.Event.RESIZE, function(_) {
					_fitTransitionToStage();
				});
			}
		} catch(_) {}
	}

	/**
	 * Escala el overlay de StateTransition para que tape toda la ventana real,
	 * independientemente del zoom/resolución virtual del juego.
	 *
	 * StateTransition suele tener un FlxSprite u overlay como campo estático.
	 * Usamos Reflect para accederlo sin depender de la API interna.
	 */
	static function _fitTransitionToStage():Void
	{
		try {
			var stage    = openfl.Lib.current.stage;
			var stageW   = stage.stageWidth;
			var stageH   = stage.stageHeight;

			// Ratio entre la ventana real y el espacio virtual del juego
			var ratioX   = stageW / FlxG.width;
			var ratioY   = stageH / FlxG.height;

			// Intentar con el nombre de campo más común: 'overlay', 'bg', 'transition'
			for (fieldName in ['overlay', 'bg', 'background', 'transitionSprite', 'blackOverlay']) {
				var overlay:Dynamic = Reflect.field(funkin.transitions.StateTransition, fieldName);
				if (overlay == null) continue;

				// Si el sprite fue creado con makeGraphic, la manera más limpia de
				// cubrirlo todo es a través de scale, no recreando el bitmap.
				overlay.scale.x = ratioX;
				overlay.scale.y = ratioY;
				overlay.updateHitbox();
				overlay.screenCenter();
			}

			// También llamar a un posible método resize() si existe
			var resizeFn:Dynamic = Reflect.field(funkin.transitions.StateTransition, 'resize');
			if (resizeFn != null)
				Reflect.callMethod(null, resizeFn, [stageW, stageH]);

		} catch(_) {}
	}

	// ─── CharacterController y CameraController ───────────────────────────────

	static function exposeControllers(interp:Interp):Void
	{
		interp.variables.set('charController', {
			get: function():Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				return ps != null ? Reflect.field(ps, 'characterController') : null;
			},
			sing: function(charIdx:Int, noteData:Int, ?altAnim:String) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return;
				final cc = Reflect.field(ps, 'characterController');
				if (cc != null) cc.singByIndex(charIdx, noteData, altAnim);
			},
			miss: function(charIdx:Int, noteData:Int) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return;
				final cc = Reflect.field(ps, 'characterController');
				if (cc != null) cc.missByIndex(charIdx, noteData);
			},
			playSpecialAnim: function(charIdx:Int, animName:String) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return;
				final cc = Reflect.field(ps, 'characterController');
				if (cc != null) cc.playSpecialAnimByIndex(charIdx, animName);
			},
			forceIdle: function() {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return;
				final cc = Reflect.field(ps, 'characterController');
				if (cc != null) cc.forceIdleAll();
			},
			setActive: function(idx:Int, active:Bool) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return;
				final cc = Reflect.field(ps, 'characterController');
				if (cc != null) cc.setCharacterActive(idx, active);
			},
			count: function():Int {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return 0;
				final cc = Reflect.field(ps, 'characterController');
				return cc != null ? cc.getCharacterCount() : 0;
			}
		});

		interp.variables.set('camController', {
			get: function():Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				return ps != null ? ps.cameraController : null;
			},
			setTarget:      function(target:String, ?extraOffX:Float, ?extraOffY:Float, ?snap:Bool) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.cameraController != null)
					ps.cameraController.setTarget(target, extraOffX ?? 0.0, extraOffY ?? 0.0, snap ?? true);
			},
			setFollowLerp:  function(lerp:Float) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.cameraController != null)
					ps.cameraController.setFollowLerp(lerp);
			},
			bumpZoom:       function() {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.cameraController != null) ps.cameraController.bumpZoom();
			},
			tweenZoomIn:    function() {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.cameraController != null) ps.cameraController.tweenZoomIn();
			},
			shake:          function(?intensity:Float, ?duration:Float) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.cameraController != null)
					ps.cameraController.shake(intensity ?? 0.05, duration ?? 0.1);
			},
			flash:          function(?duration:Float, ?color:Int) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.cameraController != null)
					ps.cameraController.flash(duration ?? 0.5, color ?? 0xFFFFFFFF);
			},
			setZoomEnabled: function(v:Bool) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.cameraController != null) ps.cameraController.zoomEnabled = v;
			},
			getTarget:      function():String {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null || ps.cameraController == null) return '';
				return ps.cameraController.currentTarget;
			},
			// FIX: lock/unlock/moveTo/panTo faltaban en el proxy.
			// "locked" es un Bool (property), NO una función. Desde HScript
			// llamar cameraController.locked() crashea porque intenta invocar un Bool.
			// Usar estos helpers en su lugar:
			//   camController.lock()          → bloquea en posición actual
			//   camController.lock(x, y)      → bloquea en coordenadas de mundo
			//   camController.unlock()        → reanuda follow
			//   camController.isLocked()      → lee el Bool sin intentar llamarlo
			lock:           function(?x:Float, ?y:Float) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.cameraController != null)
					ps.cameraController.lock(x, y);
			},
			unlock:         function() {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.cameraController != null)
					ps.cameraController.unlock();
			},
			isLocked:       function():Bool {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null || ps.cameraController == null) return false;
				return ps.cameraController.locked;
			},
			moveTo:         function(x:Float, y:Float) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.cameraController != null)
					ps.cameraController.moveTo(x, y);
			},
			panTo:          function(x:Float, y:Float, ?duration:Float, ?ease:Dynamic, ?keepLocked:Bool, ?onComplete:Dynamic) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.cameraController != null)
					ps.cameraController.panTo(x, y, duration, ease, keepLocked, onComplete);
			},
			tweenToTarget:  function(duration:Float, ?ease:Dynamic) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.cameraController != null)
					ps.cameraController.tweenToTarget(duration, ease);
			},
			centerBetweenChars: function(?snap:Bool) {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null && ps.cameraController != null)
					ps.cameraController.centerBetweenChars(snap);
			}
		});
	}

	// ─── MetaData ─────────────────────────────────────────────────────────────

	static function exposeMetaData(interp:Interp):Void
	{
		interp.variables.set('songMeta', {
			get:           function():Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				return ps != null ? Reflect.field(ps, 'metaData') : null;
			},
			noteSkin:      function():String {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return 'default';
				final md = Reflect.field(ps, 'metaData');
				return md != null ? md.noteSkin : 'default';
			},
			hudVisible:    function():Bool {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return true;
				final md = Reflect.field(ps, 'metaData');
				return md != null ? md.hudVisible : true;
			},
			hideCombo:     function():Bool {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return false;
				final md = Reflect.field(ps, 'metaData');
				return md != null ? md.hideCombo : false;
			},
			hideRatings:   function():Bool {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return false;
				final md = Reflect.field(ps, 'metaData');
				return md != null ? md.hideRatings : false;
			},
			load:          function(songName:String):Dynamic {
				return funkin.data.MetaData.load(songName);
			}
		});
	}

	// ─── GlobalConfig ─────────────────────────────────────────────────────────

	static function exposeGlobalConfig(interp:Interp):Void
	{
		interp.variables.set('GlobalConfig', funkin.data.GlobalConfig);

		/**
		 * `config` — proxy de lectura/escritura sobre GlobalConfig.
		 *
		 * Equivalente a Codename Engine's `PlayState.instance.xxx` pero para
		 * configuración global del mod. Cambia surten efecto inmediatamente.
		 *
		 * LECTURA:   config.noteSkin()          → String
		 * ESCRITURA: config.set('noteSkin', 'Pixel')
		 * BULK:      config.apply({ noteSkin:'Pixel', downscroll:true })
		 *
		 * Campos disponibles:
		 *   ui, noteSkin, noteSplash, holdCoverEnabled, holdCoverSkin,
		 *   windowTitle, discordClientId, discordLargeImageKey,
		 *   discordLargeImageText, discordMenuDetails,
		 *   scrollSpeed, defaultZoom, ghostTap, antiMash,
		 *   downscroll, middlescroll, noteSplashEnabled, freeplayMusicVolume
		 */
		interp.variables.set('config', {
			// ── Lectura directa ───────────────────────────────────────────────
			get:                  function():Dynamic            { return funkin.data.GlobalConfig.instance; },
			ui:                   function():String             { return funkin.data.GlobalConfig.instance.ui; },
			noteSkin:             function():String             { return funkin.data.GlobalConfig.instance.noteSkin; },
			noteSplash:           function():String             { return funkin.data.GlobalConfig.instance.noteSplash; },
			holdCoverEnabled:     function():Bool               { return funkin.data.GlobalConfig.instance.holdCoverEnabled; },
			holdCoverSkin:        function():Null<String>       { return funkin.data.GlobalConfig.instance.holdCoverSkin; },
			windowTitle:          function():Null<String>       { return funkin.data.GlobalConfig.instance.windowTitle; },
			discordClientId:      function():Null<String>       { return funkin.data.GlobalConfig.instance.discordClientId; },
			discordLargeImageKey: function():Null<String>       { return funkin.data.GlobalConfig.instance.discordLargeImageKey; },
			discordLargeImageText:function():Null<String>       { return funkin.data.GlobalConfig.instance.discordLargeImageText; },
			discordMenuDetails:   function():Null<String>       { return funkin.data.GlobalConfig.instance.discordMenuDetails; },
			scrollSpeed:          function():Float              { return funkin.data.GlobalConfig.instance.scrollSpeed; },
			defaultZoom:          function():Float              { return funkin.data.GlobalConfig.instance.defaultZoom; },
			ghostTap:             function():Bool               { return funkin.data.GlobalConfig.instance.ghostTap; },
			antiMash:             function():Bool               { return funkin.data.GlobalConfig.instance.antiMash; },
			downscroll:           function():Bool               { return funkin.data.GlobalConfig.instance.downscroll; },
			middlescroll:         function():Bool               { return funkin.data.GlobalConfig.instance.middlescroll; },
			noteSplashEnabled:    function():Bool               { return funkin.data.GlobalConfig.instance.noteSplashEnabled; },
			freeplayMusicVolume:  function():Float              { return funkin.data.GlobalConfig.instance.freeplayMusicVolume; },

			// ── Escritura individual ──────────────────────────────────────────
			// Cambia un campo y aplica los side-effects correspondientes.
			set: function(field:String, value:Dynamic) {
				funkin.data.GlobalConfig.set(field, value);
			},

			// ── Escritura bulk ────────────────────────────────────────────────
			// Acepta un objeto anónimo con varios campos a la vez.
			// Ejemplo: config.apply({ noteSkin:'Pixel', downscroll:true })
			apply: function(obj:Dynamic) {
				if (obj == null) return;
				for (field in Reflect.fields(obj))
					funkin.data.GlobalConfig.set(field, Reflect.field(obj, field));
			},

			// ── Persistencia ──────────────────────────────────────────────────
			save:   function() { funkin.data.GlobalConfig.instance.save(); },
			reload: function() { funkin.data.GlobalConfig.reload(); }
		});

		/**
		 * `window` — control de la ventana del OS desde script.
		 *
		 * Ejemplo:
		 *   window.setTitle('Mi Mod — Semana 5');
		 *   window.setOpacity(0.9);
		 *   window.center();
		 */
		interp.variables.set('window', {
			setTitle: function(title:String) {
				funkin.data.GlobalConfig.set('windowTitle', title);
				funkin.data.GlobalConfig.applyWindowTitle();
			},
			getTitle: function():String {
				#if !html5
				final win = lime.app.Application.current?.window;
				return win != null ? win.title : '';
				#else
				return '';
				#end
			},
			setOpacity:  function(v:Float) { funkin.system.WindowManager.setWindowOpacity(v); },
			setGameAlpha:function(v:Float) { funkin.system.WindowManager.setGameAlpha(v); },
			center:      function()        { funkin.system.WindowManager.centerOnScreen(); },
			minimize:    function()        { funkin.system.WindowManager.minimize(); },
			restore:     function()        { funkin.system.WindowManager.restore(); },
			hide:        function()        { funkin.system.WindowManager.hide(); },
			show:        function()        { funkin.system.WindowManager.show(); },
			setFullscreen:function(v:Bool) { flixel.FlxG.fullscreen = v; },
			isFullscreen: function():Bool  { return flixel.FlxG.fullscreen; },
			width:        function():Int   { return funkin.system.WindowManager.windowWidth; },
			height:       function():Int   { return funkin.system.WindowManager.windowHeight; },
			setScaleMode: function(mode:String) {
				funkin.system.WindowManager.applyScaleModeByName(mode);
			},
			applyModBranding: function() {
				funkin.system.WindowManager.applyModBranding(mods.ModManager.activeInfo());
			},

			// ── Cursor del ratón ──────────────────────────────────────────────
			/**
			 * Cambia la imagen del cursor del ratón por un asset del mod.
			 *
			 * @param key     Clave del asset de imagen (igual que Paths.image),
			 *                sin extensión. Ej: 'ui/cursors/cursor-pixel'
			 * @param hotX    Offset X del punto activo del cursor (default 0)
			 * @param hotY    Offset Y del punto activo del cursor (default 0)
			 *
			 * Ejemplo:
			 *   window.setCursor('ui/cursors/cursor-pixel');
			 *   window.setCursor('ui/cursors/cursor-hand', 8, 2);
			 */
			setCursor: function(key:String, ?hotX:Int = 0, ?hotY:Int = 0) {
				final bmp = Paths.getBitmap(key, false); // false = sin GPU, cursor necesita CPU-side
				if (bmp != null)
				{
					flixel.FlxG.mouse.useSystemCursor = false;
					flixel.FlxG.mouse.load(bmp, 1, hotX, hotY);
					trace('[window.setCursor] Cursor cargado: "$key"');
				}
				else
					trace('[window.setCursor] Imagen no encontrada: "$key"');
			},

			/** Restaura el cursor del engine por defecto (cursor-default del base). */
			resetCursor: function() {
				final bmp = Paths.getBitmap('menu/cursor/cursor-default', false);
				if (bmp != null) {
					flixel.FlxG.mouse.useSystemCursor = false;
					flixel.FlxG.mouse.load(bmp);
				}
			},

			/** Usa el cursor del sistema operativo en lugar de uno custom. */
			useSystemCursor: function(v:Bool) {
				flixel.FlxG.mouse.useSystemCursor = v;
			},

			/** Muestra u oculta el cursor. */
			setCursorVisible: function(v:Bool) {
				flixel.FlxG.mouse.visible = v;
			},

			isCursorVisible: function():Bool {
				return flixel.FlxG.mouse.visible;
			}
		});

		/**
		 * `discord` — control del Discord Rich Presence desde script.
		 *
		 * Ejemplo:
		 *   discord.setClientId('123456789012345678');
		 *   discord.setLargeImage('myicon', 'Mi Mod — FNF Cool Engine');
		 *   discord.setMenuDetails('Explorando el menú principal');
		 */
		interp.variables.set('discord', {
			setClientId: function(id:String) {
				funkin.data.GlobalConfig.set('discordClientId', id);
				funkin.data.GlobalConfig.applyDiscord();
			},
			setLargeImage: function(key:String, ?text:String) {
				funkin.data.GlobalConfig.set('discordLargeImageKey', key);
				if (text != null) funkin.data.GlobalConfig.set('discordLargeImageText', text);
				funkin.data.GlobalConfig.applyDiscord();
			},
			setMenuDetails: function(details:String) {
				funkin.data.GlobalConfig.set('discordMenuDetails', details);
				funkin.data.GlobalConfig.applyDiscord();
			},
			// Aplica todo lo que haya en GlobalConfig.instance al DiscordClient activo
			apply: function() { funkin.data.GlobalConfig.applyDiscord(); },
			// Acceso directo al DiscordClient para llamadas avanzadas (ej: changePresence)
			#if cpp
			client: data.Discord.DiscordClient
			#else
			client: null
			#end
		});
	}

	// ─── ScriptHandler ────────────────────────────────────────────────────────

	static function exposeScriptHandler(interp:Interp):Void
	{
		interp.variables.set('ScriptHandler', funkin.scripting.ScriptHandler);
		interp.variables.set('scripts', {
			// Llamar a una función en TODOS los scripts activos
			call:     function(funcName:String, ?args:Array<Dynamic>) {
				funkin.scripting.ScriptHandler.callOnScripts(funcName, args ?? []);
			},
			// Setear una variable en todos los scripts
			setVar:   function(name:String, value:Dynamic) {
				funkin.scripting.ScriptHandler.setOnScripts(name, value);
			},
			// Obtener un script específico por nombre
			getStage: function(name:String):Dynamic {
				return funkin.scripting.ScriptHandler.stageScripts.get(name);
			},
			getSong:  function(name:String):Dynamic {
				return funkin.scripting.ScriptHandler.songScripts.get(name);
			},
			getGlobal: function(name:String):Dynamic {
				return funkin.scripting.ScriptHandler.globalScripts.get(name);
			}
		});
	}

	// ─── Countdown ────────────────────────────────────────────────────────────

	static function exposeCountdown(interp:Interp):Void
	{
		interp.variables.set('Countdown', funkin.gameplay.Countdown);
		interp.variables.set('countdown', {
			// Referencia al countdown activo del PlayState
			get:     function():Dynamic {
				final ps = funkin.gameplay.PlayState.instance;
				return ps != null ? Reflect.field(ps, 'countdown') : null;
			},
			// Cancelar el countdown actual
			cancel:  function() {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return;
				final cd = Reflect.field(ps, 'countdown');
				if (cd != null) cd.cancel();
			},
			// Si el countdown terminó
			finished: function():Bool {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return false;
				final cd = Reflect.field(ps, 'countdown');
				return cd != null ? cd.finished : false;
			},
			running:  function():Bool {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps == null) return false;
				final cd = Reflect.field(ps, 'countdown');
				return cd != null ? cd.running : false;
			},
			// Skins predefinidas
			SKIN_NORMAL: funkin.gameplay.Countdown.SKIN_NORMAL,
			SKIN_PIXEL:  funkin.gameplay.Countdown.SKIN_PIXEL
		});
	}

	// ─── ModPaths completo ────────────────────────────────────────────────────

	static function exposeModPaths(interp:Interp):Void
	{
		interp.variables.set('ModPaths', mods.ModPaths);
		// Alias conveniente — todas las funciones de ModPaths como lambdas
		// (ModPaths tiene funciones static inline que no son accesibles por reflexión)
		interp.variables.set('modpaths', {
			resolve:        function(file:String, ?mod:String):String {
				return mods.ModPaths.resolve(file, mod);
			},
			txt:            function(key:String, ?mod:String):String { return mods.ModPaths.txt(key, mod); },
			xml:            function(key:String, ?mod:String):String { return mods.ModPaths.xml(key, mod); },
			json:           function(key:String, ?mod:String):String { return mods.ModPaths.json(key, mod); },
			songJson:       function(song:String, ?diff:String, ?mod:String):String {
				return mods.ModPaths.songJson(song, diff != null ? diff : 'Hard', mod);
			},
			inst:           function(song:String, ?mod:String):String { return mods.ModPaths.inst(song, mod); },
			voices:         function(song:String, ?mod:String):String { return mods.ModPaths.voices(song, mod); },
			characterJSON:  function(key:String, ?mod:String):String { return mods.ModPaths.characterJSON(key, mod); },
			characterImage: function(key:String, ?mod:String):String { return mods.ModPaths.characterImage(key, mod); },
			stageJSON:      function(key:String, ?mod:String):String { return mods.ModPaths.stageJSON(key, mod); },
			image:          function(key:String, ?mod:String):String { return mods.ModPaths.image(key, mod); },
			bgImage:        function(key:String, ?mod:String):String { return mods.ModPaths.bgImage(key, mod); },
			iconImage:      function(key:String, ?mod:String):String { return mods.ModPaths.iconImage(key, mod); },
			shader:         function(key:String, ?mod:String):String { return mods.ModPaths.shader(key, mod); }
		});
	}

	// ─── Script template classes ──────────────────────────────────────────────

	/**
	 * Expone las clases base de script (PlayStateScript, CharacterScript, StateScript)
	 * y sus constructores, para que los scripts HScript puedan instanciarlas
	 * o extenderlas por referencia.
	 *
	 * También inyecta helpers de contexto para que los scripts de canción/stage
	 * tengan acceso directo a todas las variables del PlayState.
	 */
	static function exposeScriptTemplates(interp:Interp):Void
	{
		interp.variables.set('PlayStateScript',  funkin.scripting.PlayStateScript);
		interp.variables.set('CharacterScript',  funkin.scripting.CharacterScript);
		interp.variables.set('StateScript',      funkin.scripting.StateScript);

		// ── Inyección directa de variables del PlayState ─────────────────────
		// Scripts pueden usar `bf`, `dad`, `gf`, `stage`, `camGame`, `camHUD`
		// directamente sin necesitar `game.boyfriend`, etc.
		final ps = funkin.gameplay.PlayState.instance;
		if (ps != null)
		{
			interp.variables.set('bf',      ps.boyfriend);
			interp.variables.set('dad',     ps.dad);
			interp.variables.set('gf',      ps.gf);
			interp.variables.set('stage',   ps.currentStage);
			interp.variables.set('camGame', Reflect.field(ps, 'camGame'));
			interp.variables.set('camHUD',  Reflect.field(ps, 'camHUD'));
			interp.variables.set('vocals',  Reflect.field(ps, 'vocals'));
			interp.variables.set('notes',   ps.notes);
			interp.variables.set('strumsGroups', ps.strumsGroups);
			interp.variables.set('gameState', ps.gameState);
			interp.variables.set('modChartManager', ps.modChartManager);
			interp.variables.set('countdown', Reflect.field(ps, 'countdown'));

			// Atajos de stats
			interp.variables.set('health', {
				get: function():Float return ps.health,
				set: function(v:Float) ps.health = v,
				add: function(v:Float) ps.health = ps.health + v,
				sub: function(v:Float) ps.health = ps.health - v,
			});
		}

		// ── Helper para scripts de personaje: injectCharContext(char, script) ─
		// Inyecta la instancia de Character y PlayState en las variables del script.
		interp.variables.set('injectCharContext', function(char:Dynamic, scriptInterp:Dynamic) {
			if (char == null || scriptInterp == null) return;
			try
			{
				final vars = Reflect.field(scriptInterp, 'variables');

				if (vars == null) return;
				Reflect.callMethod(vars, Reflect.field(vars, 'set'), ['character', char]);
				Reflect.callMethod(vars, Reflect.field(vars, 'set'), ['game', funkin.gameplay.PlayState.instance]);
				Reflect.callMethod(vars, Reflect.field(vars, 'set'), ['bf', funkin.gameplay.PlayState.instance?.boyfriend]);
				Reflect.callMethod(vars, Reflect.field(vars, 'set'), ['dad', funkin.gameplay.PlayState.instance?.dad]);
				Reflect.callMethod(vars, Reflect.field(vars, 'set'), ['gf', funkin.gameplay.PlayState.instance?.gf]);
			}
			catch (e:Dynamic) trace('[ScriptAPI] injectCharContext error: $e');
		});

		// ── Helper para abrir el ShaderEditor desde un script ─────────────────
		interp.variables.set('openShaderEditor', function(?name:String, ?fragCode:String, ?sprite:Dynamic) {
			final subState = flixel.FlxG.state.subState;
			if (subState != null) return; // Ya hay un substate abierto

			var targetSprite:flixel.FlxSprite = null;
			if (sprite != null && Std.isOfType(sprite, flixel.FlxSprite))
				targetSprite = cast sprite;

			var editor = new funkin.debug.editors.ShaderEditorSubState(
				name ?? 'script_shader',
				fragCode ?? '',
				null,
				targetSprite,
				null,
				function(n, code) {
					trace('[Script] Shader guardado: $n');
				}
			);
			flixel.FlxG.state.openSubState(editor);
		});
	}

	// ─── States + casting directo ────────────────────────────────────────────
	//
	// Permite escribir en scripts exactamente igual que en Haxe normal:
	//
	//   FreeplayState.songInfo          → campo estático directo
	//   MainMenuState.firstStart = true → escritura estática
	//   PlayState.instance.health       → instancia del gameplay
	//
	//   var fs = getState()             → estado actual ya casteado al tipo correcto
	//   fs.curSong                      → campo de instancia sin Reflect
	//
	//   var ps = getState('PlayState')  → igual pero pides el tipo explícito
	//   var ms = getState('FreeplayState')
	//
	// Si el state actual no es del tipo pedido, devuelve null en lugar de crashear.
	//
	static function exposeStatesAndCasting(interp:Interp):Void
	{
		// ── Clases de state expuestas directamente ────────────────────────────
		// Scripts pueden acceder a campos estáticos igual que en Haxe:
		//   FreeplayState.songInfo
		//   FreeplayState.difficultyStuff[0]
		//   MainMenuState.firstStart
		interp.variables.set('PlayState',            funkin.gameplay.PlayState);
		interp.variables.set('GameState',            funkin.gameplay.GameState);
		interp.variables.set('MainMenuState',        funkin.menus.MainMenuState);
		interp.variables.set('FreeplayState',        funkin.menus.FreeplayState);
		interp.variables.set('StoryMenuState',       funkin.menus.StoryMenuState);
		interp.variables.set('TitleState',           funkin.menus.TitleState);
		interp.variables.set('OptionsMenuState',     funkin.menus.OptionsMenuState);
		interp.variables.set('CreditsState',         funkin.menus.credits.CreditsState);
		interp.variables.set('PauseSubState',        funkin.menus.substate.PauseSubState);
		interp.variables.set('GameOverSubstate',     funkin.states.GameOverSubstate);
		interp.variables.set('LoadingState',         funkin.states.LoadingState);
		interp.variables.set('MusicBeatState',       funkin.states.MusicBeatState);
		interp.variables.set('MusicBeatSubstate',    funkin.states.MusicBeatSubstate);
		interp.variables.set('CharacterSelectorState', funkin.menus.CharacterSelectorState);
		interp.variables.set('ModSelectorState',     funkin.menus.ModSelectorState);
		interp.variables.set('ChartingState',        funkin.debug.charting.ChartingState);
		interp.variables.set('ScriptableState',      funkin.scripting.ScriptableState);

		// ── currentState: el state activo ya listo para usar ─────────────────
		// Igual que FlxG.state pero sin necesitar cast.
		// En gameplay devuelve PlayState.instance directamente.
		interp.variables.set('currentState', function():Dynamic {
			final ps = funkin.gameplay.PlayState.instance;
			if (ps != null) return ps;
			return FlxG.state;
		});

		// ── getState(nombre?): cast automático al tipo correcto ───────────────
		//
		// Sin argumento → devuelve el state actual, sea lo que sea.
		// Con nombre    → devuelve el state si es de ese tipo, null si no.
		//
		// Ejemplos:
		//   var ps  = getState();                   // Dynamic, sin cast
		//   var fs  = getState('FreeplayState');     // FreeplayState o null
		//   var ms  = getState('MainMenuState');
		//   var pau = getState('PauseSubState');     // substate activo
		//
		interp.variables.set('getState', function(?typeName:String):Dynamic {
			// Sin argumento: state/substate actual
			if (typeName == null || typeName == '') {
				final ps = funkin.gameplay.PlayState.instance;
				if (ps != null) return ps;
				// Substate activo tiene prioridad sobre el state padre
				if (FlxG.state != null && FlxG.state.subState != null)
					return FlxG.state.subState;
				return FlxG.state;
			}

			// Resolver la clase por nombre
			final cls = _resolveStateClass(typeName);
			if (cls == null) {
				trace('[ScriptAPI] getState: tipo "$typeName" no encontrado.');
				return null;
			}

			// Comprobar substate primero (PauseSubState, GameOver, etc.)
			if (FlxG.state != null && FlxG.state.subState != null
				&& Std.isOfType(FlxG.state.subState, cls))
				return FlxG.state.subState;

			// Luego el state principal
			if (FlxG.state != null && Std.isOfType(FlxG.state, cls))
				return FlxG.state;

			// PlayState por singleton (evitar cast inútil si ya es el mismo)
			final ps = funkin.gameplay.PlayState.instance;
			if (ps != null && Std.isOfType(ps, cls)) return ps;

			return null;
		});

		// ── isState(nombre): saber en qué state estás ────────────────────────
		//
		//   if (isState('FreeplayState')) { ... }
		//   if (isState('PauseSubState')) { ... }
		//
		interp.variables.set('isState', function(typeName:String):Bool {
			final cls = _resolveStateClass(typeName);
			if (cls == null) return false;
			if (FlxG.state != null && FlxG.state.subState != null
				&& Std.isOfType(FlxG.state.subState, cls)) return true;
			if (FlxG.state != null && Std.isOfType(FlxG.state, cls)) return true;
			return false;
		});

		// ── switchState: ir a un state directamente por clase o nombre ────────
		//
		//   switchState(new FreeplayState());     // instancia directa
		//   switchState('MainMenuState');          // por nombre de clase
		//
		interp.variables.set('switchState', function(stateOrName:Dynamic):Void {
			if (stateOrName == null) return;
			if (Std.isOfType(stateOrName, String)) {
				funkin.scripting.ScriptBridge.switchStateByName(stateOrName);
			} else {
				funkin.transitions.StateTransition.switchState(stateOrName);
			}
		});

		// ── Variables directas de state ─────────────────────────────────────
		// Instancias reales, no funciones. En el script se usan igual que Haxe:
		//
		//   freeplay.curSong = "x";
		//   mainmenu.firstStart = false;
		//   pause.resume();
		//
		// Son null si el state activo no es ese tipo.
		interp.variables.set('freeplay',    _castState(funkin.menus.FreeplayState));
		interp.variables.set('mainmenu',    _castState(funkin.menus.MainMenuState));
		interp.variables.set('storymenu',   _castState(funkin.menus.StoryMenuState));
		interp.variables.set('titlescreen', _castState(funkin.menus.TitleState));
		interp.variables.set('options',     _castState(funkin.menus.OptionsMenuState));
		interp.variables.set('pause',    (FlxG.state != null && FlxG.state.subState != null
			&& Std.isOfType(FlxG.state.subState, funkin.menus.substate.PauseSubState))
			? FlxG.state.subState : null);
		interp.variables.set('gameover', (FlxG.state != null && FlxG.state.subState != null
			&& Std.isOfType(FlxG.state.subState, funkin.states.GameOverSubstate))
			? FlxG.state.subState : null);
	}

	/** Devuelve el state actual si es del tipo dado, null si no. */
	static function _castState(cls:Class<Dynamic>):Dynamic {
		if (FlxG.state != null && Std.isOfType(FlxG.state, cls)) return FlxG.state;
		final ps = funkin.gameplay.PlayState.instance;
		if (ps != null && Std.isOfType(ps, cls)) return ps;
		return null;
	}

	/** Resuelve el nombre de clase de state al tipo real. */
	static function _resolveStateClass(name:String):Null<Class<Dynamic>> {
		return switch (name) {
			case 'PlayState':             funkin.gameplay.PlayState;
			case 'GameState':             funkin.gameplay.GameState;
			case 'MainMenuState':         funkin.menus.MainMenuState;
			case 'FreeplayState':         funkin.menus.FreeplayState;
			case 'StoryMenuState':        funkin.menus.StoryMenuState;
			case 'TitleState':            funkin.menus.TitleState;
			case 'OptionsMenuState':      funkin.menus.OptionsMenuState;
			case 'CreditsState':          funkin.menus.credits.CreditsState;
			case 'PauseSubState':         funkin.menus.substate.PauseSubState;
			case 'GameOverSubstate':      funkin.states.GameOverSubstate;
			case 'LoadingState':          funkin.states.LoadingState;
			case 'MusicBeatState':        funkin.states.MusicBeatState;
			case 'MusicBeatSubstate':     funkin.states.MusicBeatSubstate;
			case 'CharacterSelectorState': funkin.menus.CharacterSelectorState;
			case 'ModSelectorState':      funkin.menus.ModSelectorState;
			case 'ChartingState':         funkin.debug.charting.ChartingState;
			case 'ScriptableState':       funkin.scripting.ScriptableState;
			default: Type.resolveClass('funkin.menus.$name')
				?? Type.resolveClass('funkin.gameplay.$name')
				?? Type.resolveClass('funkin.states.$name')
				?? Type.resolveClass('funkin.menus.substate.$name')
				?? Type.resolveClass(name);
		};
	}

	// ─── Sistema 3D ───────────────────────────────────────────────────────────
	//
	// Expone las clases del sistema de escena 3D GPU-acelerada a HScript.
	// Permite a mods y addons crear sprites con geometría 3D renderizada
	// sobre Stage3D/Context3D directamente desde scripts.
	//
	// Uso básico en HScript:
	//   var sp = new Flx3DSprite(0, 0, 640, 480);
	//   add(sp);
	//   var cube = Flx3DPrimitives.cube();
	//   var obj = new Flx3DObject();
	//   obj.mesh = cube;
	//   sp.scene.add(obj);
	//
	//   // Controlar la cámara
	//   sp.scene.camera.z = -5;
	//
	//   // En onUpdate:
	//   obj.rotY += elapsed;
	//   sp.scene.render();
	//
	static function expose3D(interp:Interp):Void
	{
		// ── Clases principales ────────────────────────────────────────────────
		interp.variables.set('Flx3DSprite',     Flx3DSprite);
		interp.variables.set('Flx3DScene',      Flx3DScene);
		interp.variables.set('Flx3DObject',     Flx3DObject);
		interp.variables.set('Flx3DMesh',       Flx3DMesh);
		interp.variables.set('Flx3DCamera',     Flx3DCamera);
		interp.variables.set('Flx3DPrimitives', Flx3DPrimitives);
		interp.variables.set('Vec3',            Vec3);
		interp.variables.set('Mat4',            Mat4);

		// ── Proxy de fábrica para uso ergonómico desde scripts ───────────────
		// Los métodos estáticos de Flx3DPrimitives no son reflectables en C++.
		// Este proxy los envuelve en lambdas exactamente igual que _shaderManagerProxy().
		interp.variables.set('scene3d', {
			// Crear un sprite 3D listo para usar
			createSprite: function(x:Float, y:Float, w:Int, h:Int):Flx3DSprite
				return new Flx3DSprite(x, y, w, h),

			// Crear un objeto 3D vacío (sin malla)
			createObject: function():Flx3DObject
				return new Flx3DObject(),

			// ── Primitivas ────────────────────────────────────────────────────
			// Devuelven un Flx3DMesh listo para asignar a obj.mesh
			cube:         function():Flx3DMesh     return Flx3DPrimitives.cube(),
			plane:        function(?w:Float, ?h:Float):Flx3DMesh
				return Flx3DPrimitives.plane(w ?? 1.0, h ?? 1.0),
			sphere:       function(?r:Float, ?segs:Int):Flx3DMesh
				return Flx3DPrimitives.sphere(r ?? 0.5, segs ?? 16),
			cylinder:     function(?r:Float, ?height:Float, ?segs:Int):Flx3DMesh
				return Flx3DPrimitives.cylinder(r ?? 0.5, height ?? 1.0, segs ?? 16),

			// ── Helpers de cámara ─────────────────────────────────────────────
			// Obtiene la cámara 3D de un Flx3DSprite
			getCamera:    function(sprite:Flx3DSprite):Flx3DCamera {
				return sprite?.scene?.camera;
			},

			// ── Vec3 factory ─────────────────────────────────────────────────
			vec3:         function(x:Float, y:Float, z:Float):Vec3
				return new Vec3(x, y, z),

			// ── Mat4 identity ─────────────────────────────────────────────────
			mat4:         function():Mat4
				return new Mat4()
		});
	}

	// ─── AddonManager ─────────────────────────────────────────────────────────
	//
	// Expone AddonManager al intérprete HScript y llama al hook 'exposeAPI'
	// de cada addon cargado para que registren sus propias variables.
	//
	// Variables inyectadas:
	//   AddonManager          → clase estática completa
	//   addon_<id>            → API de cada sistema registrado (por registerSystem)
	//   addons                → objeto proxy con helpers de alto nivel
	//
	// Uso en HScript:
	//   // Comprobar si un sistema está disponible
	//   if (AddonManager.hasSystem('myParticles')) {
	//     var api = AddonManager.getSystem('myParticles');
	//     api.burst(x, y, 20);
	//   }
	//
	//   // Alias corto via proxy
	//   var sys = addons.getSystem('myParticles');
	//   addons.callHook('onSongStart', []);
	//
	static function exposeAddonManager(interp:Interp):Void
	{
		#if HSCRIPT_ALLOWED
		// Delegar a AddonManager.exposeToScript() que:
		//  1. Inyecta la clase AddonManager
		//  2. Expone cada sistema registrado como "addon_<id>"
		//  3. Llama el hook 'exposeAPI' en todos los addons cargados
		AddonManager.exposeToScript(interp);

		// Proxy de alto nivel para uso ergonómico en scripts
		interp.variables.set('addons', {
			// ── Query de sistemas ─────────────────────────────────────────────
			getSystem:   function(id:String):Dynamic
				return AddonManager.getSystem(id),
			hasSystem:   function(id:String):Bool
				return AddonManager.hasSystem(id),
			allSystems:  function():Array<String>
				return [for (k in AddonManager.registeredSystems.keys()) k],

			// ── Dispatch de hooks ─────────────────────────────────────────────
			// callHook: primer addon que retorna non-null gana
			callHook:    function(hookName:String, ?args:Array<Dynamic>):Dynamic
				return AddonManager.callHook(hookName, args ?? []),
			// broadcastHook: todos los addons reciben el hook (sin early-exit)
			broadcastHook: function(hookName:String, ?args:Array<Dynamic>):Void
				AddonManager.broadcastHook(hookName, args ?? []),

			// ── Info de addons cargados ───────────────────────────────────────
			count:       function():Int
				return AddonManager.loadedAddons.length,
			ids:         function():Array<String>
				return [for (ae in AddonManager.loadedAddons) ae.id],
			isLoaded:    function():Bool
				return AddonManager.initialized
		});
		#end
	}

	#end // HSCRIPT_ALLOWED

	// ═══════════════════════════════════════════════════════════════════════════
	//  PROXIES (disponibles incluso sin HSCRIPT_ALLOWED, usados por exposeImport)
	// ═══════════════════════════════════════════════════════════════════════════

	/**
	 * Proxy para ShaderManager como objeto anonimo.
	 * En targets C++ los metodos estaticos no son reflectables directamente,
	 * por lo que pasar la clase raw hace que HScript devuelva null al llamarlos.
	 * Este wrapper funciona igual que los proxies de FlxEase y FlxColor.
	 */
	static function _shaderManagerProxy():Dynamic
	{
		return {
			applyShader             : funkin.graphics.shaders.ShaderManager.applyShader,
			applyShaderToCamera     : funkin.graphics.shaders.ShaderManager.applyShaderToCamera,
			applyPostProcessToCamera: funkin.graphics.shaders.ShaderManager.applyPostProcessToCamera,
			removeShaderFromCamera  : funkin.graphics.shaders.ShaderManager.removeShaderFromCamera,
			registerInstance        : funkin.graphics.shaders.ShaderManager.registerInstance,
			unregisterInstance      : funkin.graphics.shaders.ShaderManager.unregisterInstance,
			removeShader            : funkin.graphics.shaders.ShaderManager.removeShader,
			setShaderParam          : funkin.graphics.shaders.ShaderManager.setShaderParam,
			setShaderParamInt       : funkin.graphics.shaders.ShaderManager.setShaderParamInt,
			flushPending            : funkin.graphics.shaders.ShaderManager.flushPending,
			clearSpriteShaders      : funkin.graphics.shaders.ShaderManager.clearSpriteShaders,
			loadShader              : funkin.graphics.shaders.ShaderManager.loadShader,
			getShader               : funkin.graphics.shaders.ShaderManager.getShader,
			registerInline          : funkin.graphics.shaders.ShaderManager.registerInline,
			getAvailableShaders     : funkin.graphics.shaders.ShaderManager.getAvailableShaders,
			scanShaders             : funkin.graphics.shaders.ShaderManager.scanShaders,
			reloadShader            : funkin.graphics.shaders.ShaderManager.reloadShader,
			reloadAllShaders        : funkin.graphics.shaders.ShaderManager.reloadAllShaders,
			clear                   : funkin.graphics.shaders.ShaderManager.clear,
			// Factory — crea un ShaderHandle instanciable desde scripts
			createHandle: function(shaderName:String):funkin.graphics.shaders.ShaderHandle
				return new funkin.graphics.shaders.ShaderHandle(shaderName),
		};
	}

	static function _flxColorProxy():Dynamic
	{
		return {
			TRANSPARENT : (flixel.util.FlxColor.TRANSPARENT : Int),
			WHITE       : (flixel.util.FlxColor.WHITE        : Int),
			BLACK       : (flixel.util.FlxColor.BLACK        : Int),
			RED         : (flixel.util.FlxColor.RED          : Int),
			GREEN       : (flixel.util.FlxColor.GREEN        : Int),
			BLUE        : (flixel.util.FlxColor.BLUE         : Int),
			YELLOW      : (flixel.util.FlxColor.YELLOW       : Int),
			ORANGE      : (flixel.util.FlxColor.ORANGE       : Int),
			CYAN        : (flixel.util.FlxColor.CYAN         : Int),
			MAGENTA     : (flixel.util.FlxColor.MAGENTA      : Int),
			PURPLE      : (flixel.util.FlxColor.PURPLE       : Int),
			PINK        : (flixel.util.FlxColor.PINK         : Int),
			BROWN       : (flixel.util.FlxColor.BROWN        : Int),
			GRAY        : (flixel.util.FlxColor.GRAY         : Int),
			LIME        : (flixel.util.FlxColor.LIME         : Int),
			fromRGB     : function(r:Int, g:Int, b:Int, ?a:Int):Int {
				return (flixel.util.FlxColor.fromRGB(r, g, b, a == null ? 255 : a) : Int);
			},
			fromHSB     : function(h:Float, s:Float, b:Float, ?a:Float):Int {
				return (flixel.util.FlxColor.fromHSB(h, s, b, a == null ? 1.0 : a) : Int);
			},
			fromHSL     : function(h:Float, s:Float, l:Float, ?a:Float):Int {
				return (flixel.util.FlxColor.fromHSL(h, s, l, a == null ? 1.0 : a) : Int);
			},
			fromString  : function(s:String):Int { return (flixel.util.FlxColor.fromString(s) : Int); },
			fromInt     : function(v:Int):Int return v,
			toString    : function(c:Int):String { return (c : flixel.util.FlxColor).toHexString(true); },
			interpolate : function(a:Int, b:Int, t:Float):Int {
				return (flixel.util.FlxColor.interpolate(
					(a : flixel.util.FlxColor), (b : flixel.util.FlxColor), t) : Int);
			}
		};
	}

	static function _flxEaseProxy():Dynamic
	{
		return {
			linear      : FlxEase.linear,
			quadIn      : FlxEase.quadIn,      quadOut     : FlxEase.quadOut,      quadInOut   : FlxEase.quadInOut,
			cubeIn      : FlxEase.cubeIn,      cubeOut     : FlxEase.cubeOut,      cubeInOut   : FlxEase.cubeInOut,
			quartIn     : FlxEase.quartIn,     quartOut    : FlxEase.quartOut,     quartInOut  : FlxEase.quartInOut,
			quintIn     : FlxEase.quintIn,     quintOut    : FlxEase.quintOut,     quintInOut  : FlxEase.quintInOut,
			sineIn      : FlxEase.sineIn,      sineOut     : FlxEase.sineOut,      sineInOut   : FlxEase.sineInOut,
			bounceIn    : FlxEase.bounceIn,    bounceOut   : FlxEase.bounceOut,    bounceInOut : FlxEase.bounceInOut,
			circIn      : FlxEase.circIn,      circOut     : FlxEase.circOut,      circInOut   : FlxEase.circInOut,
			expoIn      : FlxEase.expoIn,      expoOut     : FlxEase.expoOut,      expoInOut   : FlxEase.expoInOut,
			backIn      : FlxEase.backIn,      backOut     : FlxEase.backOut,      backInOut   : FlxEase.backInOut,
			elasticIn   : FlxEase.elasticIn,   elasticOut  : FlxEase.elasticOut,   elasticInOut: FlxEase.elasticInOut,
			smoothStepIn: FlxEase.smoothStepIn, smoothStepOut: FlxEase.smoothStepOut,
			smootherStepIn: FlxEase.smootherStepIn, smootherStepOut: FlxEase.smootherStepOut
		};
	}

	static function _flxPointProxy():Dynamic
	{
		return {
			get   : function(x:Float = 0, y:Float = 0):flixel.math.FlxPoint return flixel.math.FlxPoint.get(x, y),
			weak  : function(x:Float = 0, y:Float = 0):flixel.math.FlxPoint return flixel.math.FlxPoint.weak(x, y),
			floor : function(p:flixel.math.FlxPoint):flixel.math.FlxPoint return p.floor(),
			ceil  : function(p:flixel.math.FlxPoint):flixel.math.FlxPoint return p.ceil(),
			round : function(p:flixel.math.FlxPoint):flixel.math.FlxPoint return p.round()
		};
	}

	static function _flxRectProxy():Dynamic
	{
		return {
			get : function(x:Float = 0, y:Float = 0, w:Float = 0, h:Float = 0):flixel.math.FlxRect
				return flixel.math.FlxRect.get(x, y, w, h),
			weak: function(x:Float = 0, y:Float = 0, w:Float = 0, h:Float = 0):flixel.math.FlxRect
				return flixel.math.FlxRect.weak(x, y, w, h)
		};
	}

	// ── Subtítulos ────────────────────────────────────────────────────────────

	static function exposeSubtitles(interp:Interp):Void
	{
		final sm = funkin.ui.SubtitleManager.instance;
		interp.variables.set('subtitle', {
			/**
			 * Muestra un subtítulo.
			 *   subtitle.show("Hola", 3.0)
			 *   subtitle.show("Hola", 2.0, { size: 28, color: 0xFFFF00 })
			 */
			show: function(text:String, ?duration:Float, ?options:Dynamic) {
				sm.show(text, duration ?? 3.0, options);
			},
			/**
			 * Oculta el subtítulo activo con fade-out.
			 *   subtitle.hide()       -- suave
			 *   subtitle.hide(true)   -- instantáneo
			 */
			hide: function(?instant:Bool) {
				sm.hide(instant == true);
			},
			/**
			 * Vacía la cola y oculta el subtítulo actual.
			 */
			clear: function() {
				sm.clear();
			},
			/**
			 * Encola una lista de subtítulos. Se muestran secuencialmente.
			 *   subtitle.queue([
			 *     { text: "Línea 1", duration: 2.0 },
			 *     { text: "Línea 2", duration: 1.5, options: { color: 0xFFFF00 } }
			 *   ])
			 */
			queue: function(entries:Array<Dynamic>) {
				sm.queue(entries);
			},
			/**
			 * Establece el estilo global para futuros show().
			 *   subtitle.setStyle({ size: 28, color: 0xFFFFFF, bgAlpha: 0.6 })
			 */
			setStyle: function(opts:Dynamic) {
				sm.setStyle(opts);
			},
			/**
			 * Restaura el estilo global a los valores por defecto.
			 */
			resetStyle: function() {
				sm.resetStyle();
			},
			/** Referencia directa a la instancia (para acceso a propiedades). */
			manager: sm
		});
		// También exponer la clase completa para acceso avanzado
		interp.variables.set('SubtitleManager', funkin.ui.SubtitleManager);
	}
}
