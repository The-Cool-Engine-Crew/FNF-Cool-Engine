package funkin.states;

import coolui.CoolUIState;
import funkin.data.Conductor.BPMChangeEvent;
import funkin.data.Conductor;
import flixel.FlxG;
import flixel.util.FlxTimer;
import data.PlayerSettings;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.util.FlxColor;
import flixel.FlxCamera;
#if mobileC
import ui.FlxVirtualPad;
import flixel.input.actions.FlxActionInput;
#end
import funkin.gameplay.controls.Controls;
import funkin.audio.SoundTray;
import funkin.transitions.StateTransition;
import funkin.scripting.StateScriptHandler;
import funkin.debug.GameDevConsole;
#if (sys)
import funkin.debug.JsonWatcher;
import funkin.debug.ScriptWatcher;
import sys.FileSystem;
#end

/**
 * MusicBeatState v2 — base de todos los estados del juego.
 *
 * Novedades:
 *   • Auto-scripting: si hay scripts en assets/states/{ClassName}/, los carga
 *     automáticamente sin que cada state tenga que hacerlo manualmente.
 *   • Propagación de beatHit/stepHit a scripts.
 *   • Hook onStateCreate/onStateDestroy para scripts globales.
 *   • autoScriptLoad: bool para deshabilitar si el state lo gestiona manualmente.
 */
class MusicBeatState extends CoolUIState
{
	private var lastBeat : Float = 0;
	private var lastStep : Float = 0;

	private var curStep : Int = 0;
	private var curBeat : Int = 0;
	private var controls(get, never):Controls;

	/** Si true, carga automáticamente scripts de assets/states/{ClassName}/. */
	public var autoScriptLoad:Bool = true;

	// Cache BPM incremental
	private var _bpmIdx:Int = 0;

	// ─── Dev-mode pitch/speed control (teclas 4 / 5) ─────────────────────────
	private var _devPitch:Float        = 1.0;
	private var _devToastText:flixel.text.FlxText  = null;
	private var _devToastTween:flixel.tweens.FlxTween = null;
	private var _devToastCam:flixel.FlxCamera      = null;

	inline function get_controls():Controls
		return PlayerSettings.player1.controls;

	#if mobileC
	var _virtualpad:FlxVirtualPad;
	var trackedinputs:Array<FlxActionInput> = [];

	public function addVirtualPad(?DPad:FlxDPadMode, ?Action:FlxActionMode)
	{
		_virtualpad = new FlxVirtualPad(DPad, Action);
		_virtualpad.alpha = 0.75;
		add(_virtualpad);
		controls.setVirtualPad(_virtualpad, DPad, Action);
		trackedinputs = controls.trackedinputs;
		controls.trackedinputs = [];

		var padscam = new FlxCamera();
		FlxG.cameras.add(padscam);
		padscam.bgColor.alpha = 0;
		_virtualpad.cameras = [padscam];

		#if android
		controls.addAndroidBack();
		#end
	}

	override function destroy()
	{
		_onDestroy();
		controls.removeFlxInput(trackedinputs);
		// NOTE: Paths.clearCache() removed — it was called while the NEW state's
		// assets were already loaded, destroying graphics that belong to the
		// incoming state. FunkinCache's postStateSwitch signal handles cleanup.
		super.destroy();
	}
	#else
	public function addVirtualPad(?DPad, ?Action) {}

	override function destroy():Void
	{
		_onDestroy();
		// NOTE: Paths.clearCache() removed — it was called while the NEW state's
		// assets were already loaded, destroying graphics that belong to the
		// incoming state. FunkinCache's postStateSwitch signal handles cleanup.
		super.destroy();
	}
	#end

	override function create():Void
	{
		_bpmIdx = 0;

		super.create();
		StateTransition.onStateCreated();

		if (mods.ModManager.developerMode)
		{
			GameDevConsole.init();
			_setupDevToast();
		}

		// ── Limpiar watcher del state anterior y configurar el nuevo ──────────
		JsonWatcher.clear();

		if (mods.ModManager.developerMode)
		{
			// Callback: reiniciar el state automáticamente cuando un JSON vigilado cambia.
			JsonWatcher.onChange = function(type:String, name:String, path:String):Void
			{
				final msg = '[HotReload] ${type.toUpperCase()} "$name" modificado — caché invalidado.';
				GameDevConsole.log(msg, 0xFF69F0AE);
				trace(msg);

				GameDevConsole.log('[HotReload] Reiniciando state...', 0xFFFFCC00);
				new flixel.util.FlxTimer(flixel.util.FlxTimer.globalManager).start(0.05, function(_) {
					_hotReloadRestart();
				});
			};
		}

		// Auto-cargar scripts si el state lo permite y no los cargó manualmente
		if (autoScriptLoad)
			_autoLoadScripts();

		// GPU caching: liberar RAM de todas las texturas cargadas en este state
		// que ya fueron subidas a VRAM. Esto reduce RAM en menús (240 MB → mucho menos).
		// En desktop se hace a los 5 frames; en móvil a los 10 frames (más margen
		// porque el pipeline de upload de OpenGL ES puede ser más lento en GPUs
		// Adreno/Mali, y preferimos estar seguros antes de llamar disposeImage()).
		// PlayState tiene su propio mecanismo más granular — no se doble-flush.
		//
		// POR QUÉ TAMBIÉN EN MÓVIL:
		//   En Android/iOS la GPU comparte la misma RAM física (unified memory).
		//   Un BitmapData de 2048×2048 RGBA = 16MB en RAM. Después de que OpenGL
		//   sube la textura (GL.texImage2D en el primer draw), los pixels CPU son
		//   redundantes — la GPU ya los tiene. disposeImage() libera esos 16MB
		//   dejando solo el handle de textura GPU. Sin esto, la RAM no baja del
		//   pico inicial y el sistema mata la app por OOM en dispositivos de 2-3GB.
		//
		// POR QUÉ NO context3D EN MÓVIL:
		//   flushGPUCache() usa FlxG.stage.context3D (Stage3D API) para verificar
		//   que la textura está en GPU antes de disposeImage(). En Android con
		//   OpenGL ES, context3D NO es el mismo objeto que en desktop (Stage3D es
		//   una abstracción de Flash sobre D3D/OpenGL). flushGPUCache() devuelve
		//   early en móvil. Usamos flushGPUCacheMobile() que llama disposeImage()
		//   directamente después de N frames — seguro porque tras 10 frames todos
		//   los sprites visibles ya tuvieron al menos un draw call.
		#if (cpp && !hl)
		if (!Std.isOfType(this, funkin.gameplay.PlayState))
		{
			#if (desktop)
			final _flushTarget:Int = 5;
			#else
			final _flushTarget:Int = 10;
			#end
			var _menuFlushFrames:Int = 0;
			function _onMenuFlush(_:openfl.events.Event):Void {
				if (++_menuFlushFrames < _flushTarget) return;
				FlxG.stage.removeEventListener(openfl.events.Event.ENTER_FRAME, _onMenuFlush);
				#if desktop
				// Desktop: usa context3D para verificar upload antes de disposeImage().
				funkin.cache.PathsCache.instance.flushGPUCache();
				#else
				// Móvil: context3D no disponible — disposeImage() directo tras N frames.
				funkin.cache.PathsCache.instance.flushGPUCacheMobile();
				#end
				funkin.system.MemoryUtil.collectMinor();
			}
			FlxG.stage.addEventListener(openfl.events.Event.ENTER_FRAME, _onMenuFlush);
		}
		#end
	}

	override function update(elapsed:Float):Void
	{
		var oldStep:Int = curStep;
		if (mods.ModManager.developerMode){
			GameDevConsole.update();

			// ── F6: Hot-reload de cachés JSON ────────────────────────────────────
			// Limpia los datos parseados de personajes y stages para que el próximo
			// acceso los lea de nuevo desde disco. No recarga la partida actual —
			// solo invalida el caché estático. Útil mientras se editan JSONs sin
			// tener que reiniciar el juego.
			if (FlxG.keys.justPressed.F6)
			{
				funkin.gameplay.objects.character.Character.clearCharCaches();
				funkin.gameplay.objects.stages.Stage.clearStageCache();
				GameDevConsole.log('[HotReload] F6 → JSON caches (chars + stages) limpiados.', 0xFF69F0AE);
				trace('[MusicBeatState] F6 → JSON caches (chars + stages) limpiados.');
			}

			// ── 4 / 5: Bajar / subir pitch+velocidad ─────────────────────────────
			if (FlxG.keys.justPressed.FOUR)
			{
				_devPitch = flixel.math.FlxMath.roundDecimal(Math.max(0.1, _devPitch - 0.1), 1);
				_applyDevPitch();
			}
			if (FlxG.keys.justPressed.FIVE)
			{
				_devPitch = flixel.math.FlxMath.roundDecimal(Math.min(3.0, _devPitch + 0.1), 1);
				_applyDevPitch();
			}

			// ── F5: Reiniciar state (developer mode) ─────────────────────────────
			// En PlayState recarga el chart desde disco antes de reiniciar,
			// para que los cambios al JSON de la canción surtan efecto al instante.
			// En cualquier otro state hace un FlxG.resetState() limpio.
			if (FlxG.keys.justPressed.F5 && mods.ModManager.developerMode)
			{
				GameDevConsole.log('[DevMode] F5 → Reiniciando state...', 0xFFFFCC00);
				_hotReloadRestart();
			}

			#if (sys)
			// ── Poll del JsonWatcher (auto hot-reload de JSONs) ────────────────────
			JsonWatcher.poll(elapsed);

			// ── Poll del ScriptWatcher (live reload de .hx / .lua) ─────────────────
			// Detecta cambios en disco cada 0.5 s y recarga el script en caliente
			// sin reiniciar el state. Los objetos actuales (bf, dad, stage…)
			// se re-inyectan automáticamente en el script recargado.
			ScriptWatcher.poll(elapsed);

			// ── F7: Forzar reload de TODOS los scripts ahora mismo ─────────────────
			if (FlxG.keys.justPressed.F7 && mods.ModManager.developerMode)
			{
				GameDevConsole.log('[ScriptWatcher] F7 → Live reload de todos los scripts...', 0xFFFFCC00);
				ScriptWatcher.forceReloadAll();
			}
			#end
		}

		updateCurStep();
		updateBeat();

		if (oldStep != curStep && curStep > 0)
			stepHit();

		#if HSCRIPT_ALLOWED
		if (Lambda.count(StateScriptHandler.scripts) > 0)
		{
			StateScriptHandler.callOnScripts('onUpdate', [elapsed]);
			super.update(elapsed);
			StateScriptHandler.callOnScripts('onUpdatePost', [elapsed]);
			return;
		}
		#end

		super.update(elapsed);
	}

	// ─── Auto-scripting ───────────────────────────────────────────────────────

	/**
	 * Carga scripts para el state actual desde todas las rutas posibles
	 * (assets/, mod activo, etc.). StateScriptHandler.loadStateScripts()
	 * ya maneja todas las rutas — la comprobación FileSystem previa era
	 * incorrecta porque solo miraba assets/ y perdía los scripts de mods.
	 *
	 * Llamado automáticamente al final de create(). Los states que gestionan
	 * sus scripts manualmente deben poner `autoScriptLoad = false` en su
	 * create() ANTES de llamar a super.create().
	 */
	function _autoLoadScripts():Void
	{
		#if HSCRIPT_ALLOWED
		// Si el state ya cargó scripts manualmente antes de super.create(),
		// no volver a cargar — evita duplicados en TitleState, MainMenuState, etc.
		if (Lambda.count(StateScriptHandler.scripts) > 0)
		{
			// Scripts ya cargados externamente — iniciar watcher si aplica
			#if (sys)
			if (mods.ModManager.developerMode) _initScriptWatcher();
			#end
			return;
		}

		final className = Type.getClassName(Type.getClass(this)).split('.').pop();

		StateScriptHandler.init();
		StateScriptHandler.loadStateScripts(className, this);

		if (Lambda.count(StateScriptHandler.scripts) > 0)
		{
			// Re-sincronizar campos DESPUÉS de crear todos los objetos del state
			// para que los scripts vean los sprites/grupos reales, no null.
			StateScriptHandler.refreshStateFields(this);
			StateScriptHandler.callOnScripts('onCreate', []);
			StateScriptHandler.callOnScripts('postCreate', []);
			trace('[MusicBeatState] Scripts cargados para $className.');
		}
		#end

		// Iniciar ScriptWatcher solo en developer mode
		#if (sys)
		if (mods.ModManager.developerMode) _initScriptWatcher();
		#end
	}

	#if (sys)
	/**
	 * Inicializa ScriptWatcher con el state actual.
	 * Registra todos los scripts ya cargados y vigila las carpetas del mod
	 * activo para detectar archivos nuevos mientras el juego corre.
	 */
	function _initScriptWatcher():Void
	{
		ScriptWatcher.init(this);

		final cn = Type.getClassName(Type.getClass(this)).split('.').pop().toLowerCase();

		if (mods.ModManager.isActive())
		{
			final r = mods.ModManager.modRoot();

			// Carpetas globales + state
			ScriptWatcher.watchFolder('$r/scripts/global',   'global');
			ScriptWatcher.watchFolder('$r/data/scripts',     'global');
			ScriptWatcher.watchFolder('$r/states/$cn',       'menu');

			// Si estamos en PlayState: vigilar carpetas de canción, stage y personajes
			final ps = funkin.gameplay.PlayState.instance;
			if (ps != null && funkin.gameplay.PlayState.SONG != null)
			{
				final songName = funkin.gameplay.PlayState.SONG.song.toLowerCase();
				ScriptWatcher.watchSongScripts(songName);
				if (ps.currentStage != null) ScriptWatcher.watchStageScripts(ps.currentStage.curStage ?? '');
				if (ps.boyfriend != null) ScriptWatcher.watchCharacterScripts(ps.boyfriend.curCharacter);
				if (ps.dad       != null) ScriptWatcher.watchCharacterScripts(ps.dad.curCharacter);
				if (ps.gf        != null) ScriptWatcher.watchCharacterScripts(ps.gf.curCharacter);
			}
		}

		// Carpetas base del juego
		ScriptWatcher.watchFolder('assets/data/scripts/global', 'global');
		ScriptWatcher.watchFolder('assets/states/$cn',          'menu');

		trace('[MusicBeatState] ScriptWatcher listo.');
	}
	#end

	// ─── Dev-mode toast helpers ───────────────────────────────────────────────

	/**
	 * Crea la cámara overlay y el texto de toast para el control de pitch/velocidad.
	 * Solo se llama si developerMode = true.
	 */
	private function _setupDevToast():Void
	{
		// Cámara dedicada para el toast (siempre encima de todo, sin fondo)
		_devToastCam = new flixel.FlxCamera();
		_devToastCam.bgColor.alpha = 0;
		FlxG.cameras.add(_devToastCam, false);

		// Texto pegado al borde superior derecho
		_devToastText = new flixel.text.FlxText(0, 12, FlxG.width - 14, '', 22);
		_devToastText.setFormat(null, 22, FlxColor.WHITE, RIGHT);
		_devToastText.setBorderStyle(flixel.text.FlxText.FlxTextBorderStyle.OUTLINE, FlxColor.BLACK, 2);
		_devToastText.alpha = 0;
		_devToastText.scrollFactor.set(0, 0);
		_devToastText.cameras = [_devToastCam];
		add(_devToastText);
	}

	/**
	 * Aplica _devPitch al audio activo y muestra el toast de velocidad.
	 */
	private function _applyDevPitch():Void
	{
		// ── Aplicar pitch al instrumental ────────────────────────────────────
		if (FlxG.sound.music != null)
			FlxG.sound.music.pitch = _devPitch;

		// ── Aplicar pitch a las vocales si estamos en PlayState ──────────────
		var ps = Std.downcast(this, funkin.gameplay.PlayState);
		if (ps != null)
		{
			if (ps.vocals != null)
				ps.vocals.pitch = _devPitch;
			for (v in ps.vocalsPerChar)
				if (v != null) v.pitch = _devPitch;
		}

		// ── Toast arriba a la derecha ─────────────────────────────────────────
		if (_devToastText != null)
		{
			_devToastText.text = '⚡ Speed: ${_devPitch}x';
			_devToastText.alpha = 1.0;
			if (_devToastTween != null) _devToastTween.cancel();
			_devToastTween = FlxTween.tween(
				_devToastText,
				{ alpha: 0 },
				0.4,
				{ startDelay: 1.2, ease: FlxEase.quadIn }
			);
		}

		GameDevConsole.log('[DevMode] 4/5 → Pitch/Speed = ${_devPitch}x', 0xFFFFCC00);
		trace('[MusicBeatState] Dev pitch → ${_devPitch}x');
	}

	function _onDestroy():Void
	{
		// Limpiar cámara overlay del dev toast
		if (_devToastCam != null)
		{
			FlxG.cameras.remove(_devToastCam, true);
			_devToastCam = null;
		}
		_devToastText  = null;
		_devToastTween = null;
		// Garantía de seguridad: limpiar blockInput al salir de cualquier state.
		// Si OptionsMenuState (u otro state con inputs de texto) lo dejó en true
		// por salir de forma inesperada, la tecla 0 quedaría bloqueada para siempre.
		funkin.audio.SoundTray.blockInput = false;

		var soundTray = FlxG.plugins.get(SoundTray);
		if (soundTray != null)
			cast(soundTray, SoundTray).forceHide();

		#if (sys)
		// Limpiar watchers del state anterior.
		JsonWatcher.clear();
		JsonWatcher.onChange = null;
		ScriptWatcher.clear();
		#end

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onDestroy', []);
		StateScriptHandler.clearStateScripts();

		// ── Limpiar capas de scripts de gameplay ──────────────────────────────
		// FunkinCache.preStateSwitch ya hace esto como red de seguridad, pero
		// llamarlo aquí también (en el destroy del state) garantiza que los
		// callbacks de scripts (onDestroy, etc.) no se disparen en el nuevo state.
		// En PlayState.destroy() estas ya fueron limpiadas antes → no-ops.
		// En cualquier otro state que haya cargado scripts de song/stage/char
		// (poco usual), esto cierra el hueco.
		funkin.scripting.ScriptHandler.clearSongScripts();
		funkin.scripting.ScriptHandler.clearStageScripts();
		funkin.scripting.ScriptHandler.clearCharScripts();
		funkin.scripting.ScriptHandler.clearMenuScripts();
		#end
	}

	/**
	 * Hot-reload restart — reinicia el state actual releyendo assets desde disco.
	 *
	 * En PlayState:
	 *   1. Limpia los cachés de chars y stages.
	 *   2. Recarga el SONG desde el .json en disco (recoge cambios al chart).
	 *   3. Hace FlxG.resetState() — el PlayState se re-crea con el SONG fresco.
	 *
	 * En cualquier otro state:
	 *   Limpia cachés y hace FlxG.resetState() directamente.
	 *
	 * Solo activo en `#if debug` — no se compila en builds de release.
	 */
	private function _hotReloadRestart():Void
	{
		if (mods.ModManager.developerMode){
			funkin.gameplay.objects.character.Character.clearCharCaches();
			funkin.gameplay.objects.stages.Stage.clearStageCache();

			// ── Reload de skins/splashes de notas ──────────────────────────────
			// Recarga los JSONs activos desde disco y fuerza re-descubrimiento
			// de todas las skins en el próximo init, para que los cambios a
			// skin.json / splash.json surtan efecto al reiniciar con F5.
			#if sys
			final skinReloaded = funkin.gameplay.notes.NoteSkinSystem.reloadCurrentJsonsFromDisk();
			if (skinReloaded)
				GameDevConsole.log('[HotReload] Note skin / splash JSONs reloaded from disk.', 0xFF69F0AE);
			#end
			funkin.gameplay.notes.NoteSkinSystem.forceReinit();

			// Si estamos en PlayState, recargar el SONG desde disco antes de resetear.
			// Esto permite editar el .json del chart y ver los cambios al reiniciar.
			#if sys
			var ps = Std.downcast(this, funkin.gameplay.PlayState);
			if (ps != null && funkin.gameplay.PlayState.SONG != null)
			{
				final songName = funkin.gameplay.PlayState.SONG.song;
				final diffSuffix = funkin.data.CoolUtil.difficultySuffix();
				try
				{
					final reloaded = funkin.data.Song.loadFromJson(
						songName.toLowerCase() + diffSuffix,
						songName
					);
					if (reloaded != null)
					{
						funkin.gameplay.PlayState.SONG = reloaded;
						GameDevConsole.log('[HotReload] Chart "$songName$diffSuffix" reloaded from disk.', 0xFF69F0AE);
					}
				}
				catch (e:Dynamic)
				{
					GameDevConsole.log('[HotReload] Error reloaded chart: $e', 0xFFFF5252);
				}
			}
			#end

			#if HSCRIPT_ALLOWED
			try
			{
				StateScriptHandler.callOnScripts('onDestroy', []);
				StateScriptHandler.clearStateScripts();
				funkin.scripting.ScriptHandler.clearSongScripts();
				funkin.scripting.ScriptHandler.clearStageScripts();
				funkin.scripting.ScriptHandler.clearCharScripts();
				funkin.scripting.ScriptHandler.clearMenuScripts();
			}
			catch (_:Dynamic) {}
			#end

			FlxG.resetState();
		}
	}

	// ─── BPM / Beat ───────────────────────────────────────────────────────────

	public function updateBeat():Void
	{
		curBeat = Math.floor(curStep / 4);
	}

	/**
	 * Calcula el step actual con búsqueda incremental O(1) amortizado.
	 */
	public function updateCurStep():Void
	{
		final map = Conductor.bpmChangeMap;
		final pos = Conductor.songPosition;
		final len = map.length;

		if (len == 0)
		{
			curStep = Math.floor(pos / Conductor.stepCrochet);
			return;
		}

		if (_bpmIdx > 0 && pos < map[_bpmIdx].songTime)
			_bpmIdx = 0;

		while (_bpmIdx + 1 < len && pos >= map[_bpmIdx + 1].songTime)
			_bpmIdx++;

		final ev = map[_bpmIdx];
		curStep = ev.stepTime + Math.floor((pos - ev.songTime) / Conductor.stepCrochet);
	}

	public function stepHit():Void
	{
		// Propagar a scripts (StateScriptHandler si hay activos)
		#if HSCRIPT_ALLOWED
		if (Lambda.count(StateScriptHandler.scripts) > 0)
			StateScriptHandler.fireRaw('onStepHit', [curStep]);
		#end

		if (curStep % 4 == 0)
			beatHit();
	}

	public function beatHit():Void
	{
		// Propagar a scripts
		#if HSCRIPT_ALLOWED
		if (Lambda.count(StateScriptHandler.scripts) > 0)
			StateScriptHandler.fireRaw('onBeatHit', [curBeat]);
		#end
		// override en subclases
	}
}
