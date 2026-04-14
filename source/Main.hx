package;

import flixel.FlxG;
import flixel.FlxGame;
import flixel.FlxState;
import flixel.FlxSprite;
import openfl.Assets;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.display.StageScaleMode;
import openfl.display.StageAlign;
import CacheState;
import ui.DataInfoUI;
import funkin.audio.SoundTray;
import funkin.menus.TitleState;
import data.PlayerSettings;
import CrashHandler;
import funkin.transitions.StickerTransition;
import openfl.system.System;
import funkin.audio.AudioConfig;
import funkin.data.CameraUtil;
import funkin.system.MemoryUtil;
import funkin.system.SystemInfo;
import funkin.system.WindowManager;
import funkin.system.WindowManager.ScaleMode;
import funkin.cache.PathsCache;
import funkin.cache.FunkinCache;
import extensions.FrameLimiterAPI;
import extensions.InitAPI;
import extensions.VSyncAPI;
#if (desktop && cpp)
import data.Discord.DiscordClient;
import sys.thread.Thread;
#end
import funkin.data.KeyBinds;
import funkin.gameplay.notes.NoteSkinSystem;
import funkin.addons.AddonManager;
import funkin.data.SaveData;
#if mobileC
import funkin.util.plugins.TouchPointerPlugin;
#end

using StringTools;

/**
 * Main — punto de entrada de Cool Engine.
 *
 * ─── Orden de inicialización ─────────────────────────────────────────────────
 *  1. DPI-awareness + dark mode (antes de cualquier ventana)
 *  2. GC tuning (antes de cargar nada)
 *  3. Stage config
 *  4. AudioConfig.load() (antes de createGame → antes de que OpenAL se init)
 *  5. CrashHandler, DebugConsole
 *  6. createGame() → FlxG disponible
 *  7. AudioConfig.applyToFlixel()
 *  8. WindowManager.init() → suscripción a resize, scale mode
 *  9. Sistemas que dependen de FlxG (save, keybinds, nota skins…)
 * 10. UI overlays
 * 11. SystemInfo.init() (necesita context3D → después del primer frame)
 *
 * @author Cool Engine Team
 * @version 0.6.0
 */
class Main extends Sprite
{
	// ── Configuración del juego ────────────────────────────────────────────────
	private static inline var GAME_WIDTH:Int = 1280;
	private static inline var GAME_HEIGHT:Int = 720;
	private static inline var BASE_FPS:Int = 2000; // FlxGame construye con este valor para no bloquear FPS reales

	private var gameWidth:Int = GAME_WIDTH;
	private var gameHeight:Int = GAME_HEIGHT;
	private var zoom:Float = -1;
	private var framerate:Int = BASE_FPS;
	private var skipSplash:Bool = true;
	private var startFullscreen:Bool = false;

	private var initialState:Class<FlxState> = CacheState;

	// ── UI ────────────────────────────────────────────────────────────────────
	public final data:DataInfoUI = new DataInfoUI(10, 3);

	// ── Versiones ─────────────────────────────────────────────────────────────
	public static inline var ENGINE_VERSION:String = "0.6.0B";

	/** Factor de escala para compensar resoluciones mayores a 720p.
	 *  En 720p  → 1.0   (sin cambio)
	 *  En 1080p → 1.5   (1920/1280)
	 *  Úsalo para escalar defaultZoom y posiciones absolutas en HUD. */
	public static inline var BASE_WIDTH:Int = 1280;
	public static function resolutionScale():Float
		return (FlxG.width > 0) ? FlxG.width / BASE_WIDTH : 1.0;

	// ── Entry point ───────────────────────────────────────────────────────────

	@:keep
	static function __init__():Void
	{
		#if (windows && cpp)
		// DPI-awareness: debe llamarse antes de cualquier ventana para que
		// Windows no escale el framebuffer en monitores HiDPI.
		InitAPI.setDPIAware();
		#end

		#if (linux && cpp)
		// GTK_THEME debe establecerse antes de que SDL/Lime inicialice GTK.
		// Una vez creada la ventana el putenv ya no tiene efecto sobre la
		// sesion actual, por eso se hace aqui y no en setupStage.
		InitAPI.setDarkMode(true);
		#end
	}

	public static function main():Void
	{
		Lib.current.addChild(new Main());
	}

	// ── Constructor ───────────────────────────────────────────────────────────

	public function new()
	{
		super();

		if (stage != null)
			init();
		else
			addEventListener(Event.ADDED_TO_STAGE, init);
	}

	// ── Init ─────────────────────────────────────────────────────────────────

	private function init(?e:Event):Void
	{
		if (hasEventListener(Event.ADDED_TO_STAGE))
			removeEventListener(Event.ADDED_TO_STAGE, init);

		setupStage();
		setupGame();
	}

	private function setupStage():Void
	{
		stage.scaleMode = StageScaleMode.NO_SCALE;
		stage.align = StageAlign.TOP_LEFT;
		stage.quality = openfl.display.StageQuality.LOW;

		#if cpp
		// 32 MB de headroom: el GC espera a tener menos de 32 MB libres antes
		// de barrer. Con 8 MB el heap fragmentaba en muchas páginas pequeñas
		// causando que MEM_INFO_RESERVED subiera a ~200 MB innecesariamente.
		// Con 32 MB el heap crece en bloques más grandes y compact() devuelve
		// mucha más RAM al OS después de la carga inicial.
		cpp.vm.Gc.setMinimumFreeSpace(32 * 1024 * 1024);
		cpp.vm.Gc.enable(true);
		#end

		#if (windows && cpp)
		// FIX (PC): GetActiveWindow() devuelve NULL si la ventana del juego todavia
		// no tiene el foco del teclado en el momento de setupStage().  Esto ocurre
		// de forma intermitente (ventanas multiples, alt-tab durante el inicio, etc.)
		// y hace que DwmSetWindowAttribute() no aplique el color ni el dark mode.
		// Diferir al primer ENTER_FRAME garantiza que la ventana ya existe y tiene
		// foco antes de llamar a la API de DWM.  Si en el primer frame todavia no
		// hay HWND valido, _applyWindowStylingDeferred reintenta hasta 5 veces.
		stage.addEventListener(openfl.events.Event.ENTER_FRAME, _applyWindowStylingDeferred);
		#elseif (mac && cpp)
		// macOS: NSApp esta disponible desde el arranque, pero diferimos igualmente
		// al primer frame para que la ventana ya este visible al aplicar la apariencia.
		stage.addEventListener(openfl.events.Event.ENTER_FRAME, _applyWindowStylingDeferred);
		#end
	}

	private function setupGame():Void
	{
		calculateZoom();

		// FIX (mobile): el valor por defecto de `framerate` es BASE_FPS=2000.
		// FlxGame se construye con ese valor → stage.frameRate=2000 → el GPU de
		// Android/iOS intenta renderizar 2000 veces/segundo → 1 FPS real y el
		// despachador de eventos de Lime no procesa los callbacks async de
		// OpenFlAssets.loadBitmapData / loadSound → la barra se queda en 0% para
		// siempre.  initializeFramerate() llama setMaxFps(60) DESPUÉS de
		// createGame(), pero eso llega tarde.  Limitamos a 60 fps ANTES de
		// construir FlxGame para evitar el burst inicial.
		#if mobileC
		framerate = 60;
		#end

		// ── Audio (ANTES de createGame) ────────────────────────────────────────
		AudioConfig.load();

		// ── CrashHandler ──────────────────────────────────────────────────────
		CrashHandler.init();

		// ── Juego ─────────────────────────────────────────────────────────────
		createGame();
		FunkinCache.init();
		AudioConfig.applyToFlixel();
		// FIX: StickerTransition.init() creates a new FlxCamera internally.
		// On Android the OpenGL context (context3D) is not ready until after the
		// first rendered frame — creating GPU-backed objects here crashes the
		// Mali/Adreno driver. We defer to the first ENTER_FRAME on mobile,
		// exactly as we already do for FunkinCameraFrontEnd and SystemInfo.
		#if !mobileC
		StickerTransition.init();
		#else
		stage.addEventListener(openfl.events.Event.ENTER_FRAME, _initStickersDeferred);
		#end

		// ── WindowManager ──────────────────────────────────────────────────────
		WindowManager.init(/* mode    */ LETTERBOX, /* minW    */ 960, /* minH    */ 540, /* baseW   */ GAME_WIDTH, /* baseH   */ GAME_HEIGHT);

		// ── FIX: Tamaño inicial de ventana más grande (solo desktop) ──────────
		// En Android window.resize() interfiere con la superficie SDL y puede
		// provocar que el contexto EGL quede en estado inválido.
		#if (desktop && !html5)
		if (lime.app.Application.current?.window != null)
		{
			lime.app.Application.current.window.resize(1280, 720);
			WindowManager.centerOnScreen();
		}
		#end

		// ── Sistemas que dependen de FlxG ─────────────────────────────────────
		initializeSaveSystem();
		initializeGameSystems();
		// Capturas de pantalla — DEBE ir después de initializeGameSystems() para
		// que el save y los keybinds ya estén cargados antes de que el plugin
		// empiece a leer controles (evita capturas en el frame 0 por null key).
		funkin.util.plugins.ScreenshotPlugin.initialize();
		initializeFramerate();
		Main.applyVSync();
		initializeCameras();

		// ── UI overlays ───────────────────────────────────────────────────────
		addChild(data);
		// CoreAudio PRIMERO: carga el save (masterVolume/muted) para que
		// SoundTray.loadVolume() lea valores correctos al construirse.
		funkin.audio.CoreAudio.initialize();
		FlxG.plugins.add(new SoundTray());
		disableDefaultSoundTray();
		// V-Slice style: plugin de volumen rebindable.
		funkin.audio.VolumePlugin.initialize();

		// save volume
		final _saveVolumeOnExit = function(_:openfl.events.Event) {
			funkin.audio.CoreAudio.saveVolume();
		};
		stage.addEventListener(openfl.events.Event.DEACTIVATE, _saveVolumeOnExit);
		#if (desktop || cpp)
		stage.addEventListener(openfl.events.Event.CLOSE, _saveVolumeOnExit);
		#end

		// ── BUGFIX (Flixel git): forzar curva de volumen lineal ───────────────
		// CoreAudio gestiona su propio volumen directamente sobre FlxSound.volume,
		// pero dejamos la curva lineal por si algún SFX usa FlxG.sound.play().
		FlxG.sound.applySoundCurve  = function(v:Float) return v;
		FlxG.sound.reverseSoundCurve = function(v:Float) return v;

		// ── FIX (mobile): pantalla negra al volver a la app ──────────────────
		// En Android/iOS, cuando el OS manda la app a segundo plano y el usuario
		// vuelve, la superficie EGL puede quedar invalidada.  OpenFL debería
		// restaurarla automáticamente en el evento ACTIVATE, pero si el juego
		// estaba congelado (p.ej. por la race condition del framerate de 2000fps)
		// el handler interno de Lime nunca se ejecutó correctamente.
		// Forzar stage.invalidate() + re-aplicar framerate en ACTIVATE asegura
		// que el render pipeline se reanuda con parámetros correctos.
		#if mobileC
		stage.addEventListener(openfl.events.Event.ACTIVATE, _onMobileActivate);
		#end

		// ── Mods ──────────────────────────────────────────────────────────────
		#if android
		// En Android 6+ hay que pedir permisos de almacenamiento en runtime.
		// Sin esto el FileSystem no puede leer /sdcard/Android/data/.../files/mods/
		_requestAndroidStoragePermission(function() {
			mods.ModManager.init();
			mods.ModManager.applyStartupMod();
			// ── Addons (después de mods para que puedan leer la carpeta activa) ──
			AddonManager.init();
		});
		#else
		mods.ModManager.init();
		mods.ModManager.applyStartupMod();
		// ── Addons (después de mods para que puedan leer la carpeta activa) ────
		AddonManager.init();
		#end
		WindowManager.applyModBranding(mods.ModManager.activeInfo());
		#if (desktop && cpp)
		DiscordClient.applyModConfig(mods.ModManager.activeInfo());
		#end
		mods.ModManager.onModChanged = function(newMod:Null<String>)
		{
			// Limpiar cache de assets del mod anterior
			Paths.forceClearCache();
			funkin.gameplay.objects.character.CharacterList.reload();
			MemoryUtil.collectMajor();
			trace('[Main] Cache cleaned. Mod active → ${newMod ?? "base"}');

			// BUG FIX: recargar scripts globales del nuevo mod.
			// Sin esto, los scripts del mod anterior siguen activos y los del nuevo
			// no se cargan → funciones de mod ausentes, variables incorrectas, crashes.
			funkin.scripting.ScriptHandler.clearAll();
			funkin.scripting.ScriptHandler.loadGlobalScripts();

			// BUG FIX: reiniciar el sistema de skins al cambiar de mod.
			// Sin esto ocurren 3 problemas:
			//   1. availableSkins sigue teniendo las skins del mod anterior.
			//   2. Las skins del nuevo mod no se descubren.
			//   3. Los scripts Lua de skin del mod anterior (skinScripts/splashScripts)
			//      siguen activos y pueden ejecutar código del mod equivocado.
			funkin.gameplay.notes.NoteSkinSystem.destroyScripts();
			funkin.gameplay.notes.NoteSkinSystem.forceReinit();

			WindowManager.applyModBranding(mods.ModManager.activeInfo());
			#if (desktop && cpp)
			DiscordClient.applyModConfig(mods.ModManager.activeInfo());
			#end
		};

		// ── Discord ───────────────────────────────────────────────────────────
		#if (desktop && cpp)
		DiscordClient.initialize();
		#end

		// ── FunkinCamera frontend ─────────────────────────────────────────────
		// DEBE hacerse aquí, DESPUÉS de createGame() pero ANTES del primer
		// ENTER_FRAME. Reemplazar FlxG.cameras dentro del ENTER_FRAME provoca
		// un null pointer en el pipeline nativo de Lime/SDL en Android porque
		// el renderer ya está iterando la lista de cámaras en ese momento.
		// FixedBitmapData ya tiene guarda contra context3D == null (usa
		// software bitmap como fallback), así que esto es seguro en Android.
		// FunkinCamera usa RenderTexture de flixel-animate que crea texturas GPU.
		// En Android ese contexto no está listo aquí y crashea el driver OpenGL.
		// Los blend modes avanzados tampoco son necesarios en mobile.
		#if (cpp && !mobileC)
		untyped FlxG.cameras = new funkin.graphics.FunkinCameraFrontEnd();
		#end

		// SystemInfo._detectGPU() llama ctx.gl.getParameter() — GL call directa.
		// En Android el render corre en un thread nativo separado; hacerlo desde
		// ENTER_FRAME (event thread de Lime) viola el contexto OpenGL → crash.
		// En desktop es seguro deferir al primer frame.
		// En mobile solo inicializamos la parte no-GL (OS, CPU, RAM).
		#if (cpp && !mobileC)
		stage.addEventListener(openfl.events.Event.ENTER_FRAME, _initSystemInfoDeferred);
		#else
		SystemInfo.initSafe();
		#end
	}

	// ── ENTER_FRAME deferred ──────────────────────────────────────────────────

	private function _initSystemInfoDeferred(_:openfl.events.Event):Void
	{
		stage.removeEventListener(openfl.events.Event.ENTER_FRAME, _initSystemInfoDeferred);

		// context3D.gl está disponible a partir del primer frame renderizado.
		// FunkinCameraFrontEnd ya se inicializó en setupGame() con la guarda
		// de FixedBitmapData — este método solo necesita SystemInfo.
		SystemInfo.init();
	}

	#if ((windows || mac) && cpp)
	private static inline var _WIN_STYLE_MAX_RETRIES:Int = 120;
	private var _winStyleRetries:Int = 0;
	private var _winStyleApplied:Bool = false;

	private function _applyWindowStylingDeferred(_:openfl.events.Event):Void
	{
		if (!InitAPI.hasValidWindow())
		{
			if (++_winStyleRetries < _WIN_STYLE_MAX_RETRIES)
				return; // reintentar el siguiente frame
			stage.removeEventListener(openfl.events.Event.ENTER_FRAME, _applyWindowStylingDeferred);
			return;
		}

		stage.removeEventListener(openfl.events.Event.ENTER_FRAME, _applyWindowStylingDeferred);

		_doApplyWindowStyling();

		if (!_winStyleApplied)
		{
			_winStyleApplied = true;
			new flixel.util.FlxTimer().start(0.5, function(_) _doApplyWindowStyling());
		}
	}

	private function _doApplyWindowStyling():Void
	{
		InitAPI.setDarkMode(true);
		InitAPI.setWindowCaptionColor(0, 0, 0);
		InitAPI.setWindowBorderColor(0, 0, 0);
	}
	#end

	#if mobileC
	/** Deferred init for StickerTransition on mobile — waits for the OpenGL context. */
	private function _initStickersDeferred(_:openfl.events.Event):Void
	{
		stage.removeEventListener(openfl.events.Event.ENTER_FRAME, _initStickersDeferred);
		StickerTransition.init();
	}
	#end

	#if mobileC
	/**
	 * Corrige la pantalla negra y el audio silenciado al volver a la app en Android/iOS.
	 *
	 * Cuando el OS destruye la superficie EGL (app en segundo plano) y la
	 * recrea al volver, OpenFL debe re-enlazar el framebuffer y re-subir
	 * todas las texturas. stage.invalidate() fuerza un redraw completo.
	 * Re-aplicar el framerate garantiza que stage.frameRate no quedó
	 * revirtido a 2000 por algún reset interno de Lime/SDL.
	 */
	private function _onMobileActivate(_:openfl.events.Event):Void
	{
		openfl.Lib.current.stage.invalidate();

		setMaxFps(60);

		Main.applyVSync();

		funkin.audio.CoreAudio.onMobileResume();

		haxe.Timer.delay(function() openfl.Lib.current.stage.invalidate(), 200);
	}
	#end

	// ── Helpers de inicialización ─────────────────────────────────────────────

	private function calculateZoom():Void
	{
		// ── Resolución guardada: 720p (default) o 1080p ───────────────────────
		var tempSave = new flixel.util.FlxSave();
		tempSave.bind('coolengine', 'CoolTeam');
		var use1080p = (tempSave.data != null && tempSave.data.renderResolution == '1080p');
		tempSave.destroy();

		// SIEMPRE mantenemos el espacio de juego en 1280x720.
		// Toda la geometria (stages, personajes, HUD) esta disenada para esas
		// coordenadas. En 1080p escalamos el renderer fisico a 1.5x para que
		// ocupe 1920x1080 en pantalla sin romper ninguna posicion.
		gameWidth  = GAME_WIDTH;   // 1280
		gameHeight = GAME_HEIGHT;  // 720

		if (use1080p)
		{
			zoom = 1.5;
		}
		else
		{
			zoom = 1.0;
		}

		// Nota: en Android/iOS se mantiene el auto-detect porque la "ventana" es siempre
		// pantalla completa y las dimensiones del stage son las físicas del dispositivo.
		#if android
		var rawW:Int = Lib.current.stage.stageWidth;
		var rawH:Int = Lib.current.stage.stageHeight;
		// Forzar landscape en Android (el stage puede reportar portrait antes de la orientación)
		var stageW:Int = Std.int(Math.max(rawW, rawH));
		var stageH:Int = Std.int(Math.min(rawW, rawH));

		if (stageW <= 0 || stageH <= 0)
		{
			zoom       = 1.0;
			gameWidth  = GAME_WIDTH;
			gameHeight = GAME_HEIGHT;
		}
		else
		{
			zoom = Math.min(stageW / gameWidth, stageH / gameHeight);
			if (zoom <= 0) zoom = 1.0;
			gameWidth  = Math.ceil(stageW / zoom);
			gameHeight = Math.ceil(stageH / zoom);
		}
		#elseif ios
		// iOS — misma lógica que Android: el stage siempre reporta dimensiones físicas
		// reales del dispositivo en landscape (UIInterfaceOrientationLandscape).
		var rawW:Int = Lib.current.stage.stageWidth;
		var rawH:Int = Lib.current.stage.stageHeight;
		var stageW:Int = Std.int(Math.max(rawW, rawH));
		var stageH:Int = Std.int(Math.min(rawW, rawH));

		if (stageW <= 0 || stageH <= 0)
		{
			zoom       = 1.0;
			gameWidth  = GAME_WIDTH;
			gameHeight = GAME_HEIGHT;
		}
		else
		{
			zoom = Math.min(stageW / gameWidth, stageH / gameHeight);
			if (zoom <= 0) zoom = 1.0;
			gameWidth  = Math.ceil(stageW / zoom);
			gameHeight = Math.ceil(stageH / zoom);
		}
		#end
	}

	private function createGame():Void
	{
		addChild(new FlxGame(gameWidth, gameHeight, initialState, #if (flixel < "5.0.0") zoom, #end framerate, framerate, skipSplash, startFullscreen));

		// Garantizar que el juego siempre arranca en modo ventana,
		// ignorando cualquier valor de fullscreen guardado en save data.
		FlxG.fullscreen = false;

		// FIX: drawFramerate y updateFramerate se asignan solo en initializeFramerate()
		// para evitar el error "Invalid field" al llamarlos antes de que FlxG esté listo.
		// NO se duplican aquí.

		FlxSprite.defaultAntialiasing = false;
	}

	private function initializeSaveSystem():Void
	{
		FlxG.save.bind('coolengine', 'CoolTeam');
		
		SaveData.migrate();

		funkin.menus.OptionsMenuState.OptionsData.initSave();
		funkin.gameplay.objects.hud.Highscore.load();

		// ── Aplicar modo de escala guardado ────────────────────────────────────
		if (SaveData.data.scaleMode != null)
			WindowManager.applyScaleModeByName(SaveData.data.scaleMode);
	}

	private function initializeGameSystems():Void
	{
		NoteSkinSystem.init();
		KeyBinds.keyCheck();
		PlayerSettings.init();
		PlayerSettings.player1.controls.loadKeyBinds();

		// ── CursorManager: sistema de cursor personalizable ──────────────────
		funkin.system.CursorManager.init();
		funkin.system.CursorManager.loadSkinPreference();

		// ── Touch pointer visual (mobile) ──────────────────────────────────────
		#if mobileC
		TouchPointerPlugin.initialize();
		// Restaurar preferencia guardada
		if (SaveData.data.touchIndicator != null)
			TouchPointerPlugin.enabled = SaveData.data.touchIndicator;
		#end

		if (SaveData.data.gpuCaching != null)
			PathsCache.gpuCaching = SaveData.data.gpuCaching;

		Paths.addExclusion(Paths.music('freakyMenu'));
		Paths.addExclusion(Paths.image('menu/cursor/cursor-default'));
	}

	private function initializeFramerate():Void
	{
		// Inicializar el limitador nativo UNA VEZ (timeBeginPeriod + waitable timer).
		// Esto también mejora la precisión del loop de Lime como efecto colateral.
		FrameLimiterAPI.init();

		// FIX: was `!androidC` — that define never existed; `mobileC` is the correct one.
		// On Android at 120fps the SDL render thread overruns and produces a null-ptr
		// crash in the native pipeline. Mobile targets run at 60fps max.
		#if (!html5 && !mobileC)
		framerate = 120;
		#else
		framerate = 60;
		#end

		#if !mobileC
		if (SaveData.data.fpsTarget != null)
		{
			setMaxFps(Std.int(SaveData.data.fpsTarget));
		}
		else if (SaveData.data.FPSCap != null && SaveData.data.FPSCap > 0)
		{
			SaveData.data.fpsTarget = 120;
			setMaxFps(120);
		}
		else
		{
			SaveData.data.fpsTarget = 60;
			setMaxFps(60);
		}
		#else
		// FIX (mobile): aunque framerate ya se fijó a 60 antes de createGame(),
		// FlxG.updateFramerate / FlxG.drawFramerate y stage.frameRate pueden
		// haber quedado en 2000 si Flixel los restauró internamente.
		// Llamar setMaxFps() aquí los sincroniza todos definitivamente.
		setMaxFps(60);
		#end
	}

	private function initializeCameras():Void
	{
		CameraUtil.pruneEmptyFilters(FlxG.camera);
	}

	private function disableDefaultSoundTray():Void
	{
		FlxG.sound.volumeUpKeys = null;
		FlxG.sound.volumeDownKeys = null;
		FlxG.sound.muteKeys = null;
		#if FLX_SOUND_SYSTEM
		@:privateAccess
		{
			if (FlxG.game.soundTray != null)
			{
				FlxG.game.soundTray.visible = false;
				FlxG.game.soundTray.active = false;
			}
		}
		#end
	}

	// ── Public API ────────────────────────────────────────────────────────────

	public function setMaxFps(fps:Int):Void
	{
		// fps = 0  → "Unlimited": render as fast as possible (1000 cap for safety),
		//            but logic updates capped at 240 so Flixel doesn't run 16+ steps/frame.
		// fps > 0  → exact cap for both render and logic.
		//
		// WHY separate updateFramerate cap:
		//   FlxGame.step() runs floor(elapsed / stepMS) update calls per rendered frame.
		//   updateFramerate=1000 → stepMS=1ms. At 60Hz display, elapsed≈16ms → 16 update
		//   calls per frame → 16x CPU cost → game feels slow/unresponsive at high FPS.
		//   Capping logic at 240 keeps 1-2 updates per frame at typical display rates.

		#if (!html5 && !mobileC)
		final renderFps:Int = fps <= 0 ? 1000 : fps;
		final updateFps:Int = fps <= 0 ? 240  : fps;
		// FIX: Flixel's updateFramerate setter warns when value < stage.frameRate.
		// Lower stage.frameRate to updateFps first so the check passes, then
		// raise it to renderFps via drawFramerate (which sets stage.frameRate internally).
		openfl.Lib.current.stage.frameRate = updateFps;
		FlxG.updateFramerate = updateFps;
		FlxG.drawFramerate   = renderFps;
		openfl.Lib.current.stage.frameRate = renderFps;
		#else
		final effective:Int = fps <= 0 ? 60 : fps;
		openfl.Lib.current.stage.frameRate = effective;
		FlxG.updateFramerate = effective;
		FlxG.drawFramerate   = effective;
		#end
	}

	/**
	 * Aplica el estado de VSync guardado en save via extension nativa.
	 *
	 * FIX: la expresion original `SaveData.data.vsync == true` evalua a false
	 * cuando vsync es null (usuario nuevo sin save previo), desactivando el
	 * VSync de forma silenciosa en el primer arranque.
	 * Con `!= false`, null se trata como true → VSync activado por defecto,
	 * que es el comportamiento correcto en todas las plataformas.
	 */
	public static function applyVSync():Void
	{
		#if cpp
		VSyncAPI.setVSync(SaveData.data.vsync != false);
		#end
	}

	#if android
	/** Solicita READ/WRITE_EXTERNAL_STORAGE en Android 6+ y llama onGranted() cuando esté listo. */
	static function _requestAndroidStoragePermission(onGranted:Void->Void):Void
	{
		#if (android && cpp)
		// Android 10+ (API 29+): /Android/data/<package>/files/ es accesible sin permisos
		// de almacenamiento externo. READ/WRITE_EXTERNAL_STORAGE están deprecados en
		// Android 13+ (API 33) y el sistema los deniega silenciosamente.
		// El JNI a HaxeObject::requestPermissions no existe en Lime y puede lanzar
		// una excepción nativa que crashea la app antes del primer frame.
		// Simplemente esperamos un tick para que el FileSystem esté listo y continuamos.
		new flixel.util.FlxTimer().start(0.1, function(_) onGranted());
		#else
		onGranted();
		#end
	}
	#end

	public static function getGame():FlxGame
		return cast(Lib.current.getChildAt(0), FlxGame);
}
