package funkin.cutscenes;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.sound.FlxSound;
import haxe.Json;
import mods.ModManager;
import animationdata.FunkinSprite;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/**
 * SpriteCutscene v2 — sistema de cutscenes con sprites basado en JSON.
 *
 * ─── Uso desde PlayState (automático vía meta.json) ──────────────────────────
 *
 *   meta.json:
 *   {
 *     "introCutscene": "thorns-intro",     → assets/data/cutscenes/thorns-intro.json
 *     "outroCutscene": "thorns-outro"      → assets/data/cutscenes/thorns-outro.json
 *   }
 *
 * ─── Uso desde script ────────────────────────────────────────────────────────
 *
 *   var cut = new SpriteCutscene(game, 'thorns-intro');
 *   cut.play(function() { log("cutscene terminada"); });
 *
 * ─── Resolución de archivos JSON ─────────────────────────────────────────────
 *
 *   mods/{mod}/data/cutscenes/{key}.json    ← mod override
 *   assets/data/cutscenes/{key}.json        ← base game
 *   mods/{mod}/data/cutscenes/{song}/{key}.json
 *   assets/data/cutscenes/{song}/{key}.json
 *
 * ─── Referencia del formato JSON ─────────────────────────────────────────────
 *   Ver SpriteCutsceneData.hx para la documentación completa del formato.
 */
class SpriteCutscene
{
	// ── config ────────────────────────────────────────────────────────────────
	public var skippable:Bool = true;

	// ── state ─────────────────────────────────────────────────────────────────
	public var playing(default, null):Bool  = false;
	public var finished(default, null):Bool = false;

	// ── privado ───────────────────────────────────────────────────────────────
	var _state:flixel.FlxState;
	var _doc:SpriteCutsceneData.CutsceneDocument;
	var _sprites:Map<String, FlxSprite> = [];
	var _sounds:Map<String, FlxSound>   = [];
	var _onComplete:Null<Void->Void>    = null;
	var _stepIdx:Int   = 0;
	var _blocked:Bool  = false;
	var _skipped:Bool  = false;

	// Seguimiento propio de timers y tweens para cancelarlos sin tocar
	// el globalManager (que mataría timers de audio y otros sistemas).
	var _timers:Array<FlxTimer>  = [];
	var _tweens:Array<FlxTween>  = [];

	// Seguimiento de cámara: sprite al que la cámara sigue opcionalmente.
	var _camTarget:Null<FlxSprite> = null;
	/** Zoom original de FlxG.camera antes de la cutscene, para restaurarlo en reset. */
	var _origCamZoom:Float = 1.0;
	/** Posición X original de FlxG.camera antes de la cutscene. */
	var _origCamX:Float    = 0.0;
	/** Posición Y original de FlxG.camera antes de la cutscene. */
	var _origCamY:Float    = 0.0;

	// Cámara dedicada para los sprites de cutscene — se sitúa ENCIMA
	// de camHUD para que los sprites tapen el gameplay completamente.
	var _camCutscene:FlxCamera;

	// Bandera que indica si deshabilitamos el follow de FlxG.camera al
	// empezar la cutscene (para que los tweens de scroll no luchen con él).
	var _camFollowDisabled:Bool = false;

	// Registro de cámaras que esta cutscene ocultó, para restaurarlas al terminar.
	// Map<"hud"|"game"|"countdown", Bool> — guarda la visibilidad ORIGINAL.
	var _hiddenCams:Map<String, Bool>  = [];
	// Guarda el alpha original de cada cámara tocada por setCamVisible.
	var _hiddenCamsAlpha:Map<String, Float> = [];

	// Mapa de callbacks registrados por CutsceneBuilder para los pasos 'call' y
	// 'callAsync'. La clave es el id del paso (campo step.id generado por el builder).
	// Permite ejecutar funciones Haxe/HScript arbitrarias dentro de la secuencia.
	var _callbackMap:Map<String, Dynamic> = [];

	// Lista de funciones a llamar cuando la cutscene termine o se salte.
	// Se registran vía el paso interno '_registerCleanup'.
	var _cleanupCallbacks:Array<Dynamic> = [];

	// ── Seguimiento del estado de pausa del juego ─────────────────────────────
	// FlxTimerManager y FlxTweenManager son PLUGINS globales de Flixel, no
	// miembros del estado. Siguen actualizándose aunque el estado esté pausado
	// por un substate (ej. PauseSubState). Hay que pausarlos/reanudarlos
	// manualmente detectando cuándo el juego entra/sale de pausa.
	var _wasGamePaused:Bool = false;

	// ── constructor ───────────────────────────────────────────────────────────

	/**
	 * @param state  Estado padre (normalmente PlayState.instance)
	 * @param key    Clave del JSON (sin extensión ni ruta)
	 * @param song   Canción actual (para resolver rutas de subcarpeta)
	 */
	public function new(state:flixel.FlxState, key:String, ?song:String)
	{
		_state = state;
		_doc   = _loadDocument(key, song);
		if (_doc != null && _doc.skippable == false) skippable = false;

		_initCamera();
	}

	/**
	 * Crea una SpriteCutscene a partir de un documento ya construido en memoria
	 * (sin necesidad de un JSON). Usado por CutsceneBuilder.
	 * @param callbacks  Map opcional de id→fn para pasos call/callAsync.
	 */
	public static function fromDoc(state:flixel.FlxState,
		doc:SpriteCutsceneData.CutsceneDocument,
		?callbacks:Map<String, Dynamic>):SpriteCutscene
	{
		var sc       = new SpriteCutscene(state, '__noop__');
		sc._doc      = doc;
		sc.skippable = doc.skippable ?? true;
		if (callbacks != null)
			for (k => v in callbacks) sc._callbackMap.set(k, v);
		return sc;
	}

	function _initCamera():Void
	{
		// Crear cámara dedicada que se añade AL FINAL de la lista de cámaras
		// → se renderiza encima de camGame y camHUD, tapando el gameplay.
		_camCutscene = new FlxCamera();
		_camCutscene.bgColor = 0x00000000; // transparente

		// FIX flash blanco: el canvas de OpenFL que subyace a cada FlxCamera
		// se inicializa como un bitmap blanco. Flixel lo limpia con bgColor
		// durante su primer draw(), pero solo si la cámara ya era visible en
		// ese momento — si la hacemos visible en preUpdate (antes del draw)
		// vemos un destello blanco exactamente 1 frame.
		//
		// Solución: conectarse a postDraw UNA SOLA VEZ para activar la cámara
		// DESPUÉS de que el frame actual haya terminado de renderizarse.
		// En el siguiente frame Flixel la limpia con bgColor antes de dibujar,
		// así nunca se ve el bitmap blanco inicial.
		_camCutscene.visible = false;
		FlxG.cameras.add(_camCutscene, false);

		FlxG.signals.postDraw.addOnce(_onFirstPostDraw);
	}

	/** Activa _camCutscene después del primer frame completo para evitar el flash blanco. */
	function _onFirstPostDraw():Void
	{
		if (_camCutscene != null)
			_camCutscene.visible = true;
	}

	/** Inicia la cutscene. `onComplete` se llama cuando termina o se salta. */
	public function play(?onComplete:Void->Void):Void
	{
		if (_doc == null || _doc.steps == null || _doc.steps.length == 0)
		{
			if (onComplete != null) onComplete();
			return;
		}
		_onComplete = onComplete;
		playing     = true;
		finished    = false;
		_stepIdx    = 0;
		// Guardar el estado actual de la cámara para que cameraReset sepa
		// a qué valores volver.
		_origCamZoom = FlxG.camera.zoom;
		_origCamX    = FlxG.camera.scroll.x;
		_origCamY    = FlxG.camera.scroll.y;
		// FIX cámara se bloquea al terminar: FlxCamera.follow() sigue activo
		// durante la cutscene y cada frame lerpa scroll hacia camFollow,
		// peleando con los tweens de cameraPan/cameraZoom. Lo deshabilitamos
		// aquí y lo restauramos en _cleanup() para que el CameraController
		// retome el control limpiamente al volver al gameplay.
		_camFollowDisabled = false;
		var _ps = funkin.gameplay.PlayState.instance;
		if (_ps != null && _ps.cameraController != null)
		{
			FlxG.camera.follow(null); // desconectar follow
			_camFollowDisabled = true;
		}
		// FIX animaciones: congelar los personajes del PlayState mientras
		// dura la cutscene para que no sigan bailando/animándose por su cuenta.
		_setCharactersFrozen(true);
		// Conectar el update de seguimiento de cámara
		FlxG.signals.preUpdate.add(_onPreUpdate);
		_nextStep();
	}

	/** Salta la cutscene inmediatamente (limpia todo y llama onComplete). */
	public function skip():Void
	{
		if (!playing || _skipped) return;
		if (!skippable) return;
		_skipped = true;
		_cleanup();
		_finish();
	}

	/**
	 * Registra una función de callback para los pasos 'call' o 'callAsync'.
	 * Llamar antes de play(). CutsceneBuilder lo hace automáticamente.
	 * param id  ID del paso (generado por CutsceneBuilder o puesto a mano en el JSON)
	 * param fn  Función a ejecutar.
	 *            Para 'call':      fn()  — sin parámetros
	 *            Para 'callAsync': fn(done:Void->Void)  — debe llamar done() para continuar
	 */
	public function registerCallback(id:String, fn:Dynamic):Void
	{
		_callbackMap.set(id, fn);
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  Ejecución de pasos
	// ═════════════════════════════════════════════════════════════════════════

	function _nextStep():Void
	{
		if (_skipped || _doc == null) return;

		if (_stepIdx >= _doc.steps.length)
		{
			_finish();
			return;
		}

		var step = _doc.steps[_stepIdx];
		_stepIdx++;
		_executeStep(step);
	}

	function _executeStep(step:SpriteCutsceneData.CutsceneStep):Void
	{
		switch (step.action)
		{
			case 'add':
				_doAdd(step);

			case 'remove':
				var spr = _sprites.get(step.sprite ?? '');
				if (spr != null) _state.remove(spr);
				_nextStep();

			case 'setAlpha':
				var spr = _sprites.get(step.sprite ?? '');
				if (spr != null) spr.alpha = step.alpha ?? 1.0;
				_nextStep();

			case 'setColor':
				var spr = _sprites.get(step.sprite ?? '');
				if (spr != null) spr.color = _parseColor(step.color ?? 'WHITE');
				_nextStep();

			case 'setVisible':
				var spr = _sprites.get(step.sprite ?? '');
				if (spr != null) spr.visible = step.visible ?? true;
				_nextStep();

			case 'setPosition':
				var spr = _sprites.get(step.sprite ?? '');
				if (spr != null) { spr.x = step.x ?? spr.x; spr.y = step.y ?? spr.y; }
				_nextStep();

			case 'screenCenter':
				var spr = _sprites.get(step.sprite ?? '');
				if (spr != null) _screenCenter(spr, step.axis ?? 'xy');
				_nextStep();

			case 'wait':
				_blocked = true;
				var _t = new FlxTimer();
				_timers.push(_t);
				_t.start(step.time ?? 0.1, function(_) {
					_timers.remove(_t);
					_blocked = false;
					_nextStep();
				});

			case 'fadeTimer':
				_doFadeTimer(step);

			case 'tween':
				_doTween(step);

			case 'playAnim':
				var spr = _sprites.get(step.sprite ?? '');
				if (spr != null && spr.animation != null)
					spr.animation.play(step.anim ?? '', step.force ?? false);
				_nextStep();

			// ── stageAnim ─────────────────────────────────────────────────────
			// Controla personajes YA EXISTENTES en el PlayState (bf, dad, gf, o
			// cualquier nombre del stage) sin necesidad de añadir sprites nuevos.
			// JSON: { "action": "stageAnim", "sprite": "bf", "anim": "hey", "force": true }
			// Nombres válidos para "sprite":
			//   "bf" / "boyfriend"  → PlayState.boyfriend
			//   "dad" / "opponent"  → PlayState.dad
			//   "gf" / "girlfriend" → PlayState.gf
			case 'stageAnim':
				_doStageAnim(step);

			case 'playSound':
				_doPlaySound(step);

			case 'waitSound':
				_doWaitSound(step);

			case 'cameraFade':
				_doCameraFade(step);

			case 'cameraFlash':
				var col = _parseColor(step.color ?? 'WHITE');
				var dur = step.duration ?? 0.5;
				if (step.async ?? false)
				{
					FlxG.camera.flash(col, dur);
					_nextStep();
				}
				else
				{
					_blocked = true;
					FlxG.camera.flash(col, dur, function() { _blocked = false; _nextStep(); });
				}

			case 'cameraShake':
				FlxG.camera.shake(step.intensity ?? 0.03, step.duration ?? 0.2);
				_nextStep();

			// ── cameraZoom ────────────────────────────────────────────────────────
			// Tweenea el zoom de la cámara del gameplay (FlxG.camera).
			// JSON: { "action":"cameraZoom", "zoom":1.3, "duration":0.5, "ease":"quadOut", "async":true }
			case 'cameraZoom':
				_doCameraZoom(step);

			// ── cameraMove ────────────────────────────────────────────────────────
			// Salta la cámara a (camX, camY) instantáneamente (sin tween).
			// JSON: { "action":"cameraMove", "camX":760, "camY":450 }
			case 'cameraMove':
				// FIX: mover el scroll, no la posición de pantalla
				if (step.camX != null) FlxG.camera.scroll.x = step.camX;
				if (step.camY != null) FlxG.camera.scroll.y = step.camY;
				_nextStep();

			// ── cameraPan ─────────────────────────────────────────────────────────
			// Tween de posición de la cámara hacia (camX, camY).
			// JSON: { "action":"cameraPan", "camX":760, "camY":450, "duration":1.0, "ease":"sineInOut", "async":true }
			case 'cameraPan':
				_doCameraPan(step);

			// ── cameraTween ───────────────────────────────────────────────────────
			// Tween libre sobre propiedades de FlxG.camera (zoom, x, y).
			// JSON: { "action":"cameraTween", "camProps":{"zoom":1.2,"x":400}, "duration":0.8, "ease":"quadOut" }
			case 'cameraTween':
				_doCameraTween(step);

			// ── cameraReset ───────────────────────────────────────────────────────
			// Restaura el zoom y la posición que tenía la cámara antes de la cutscene.
			// JSON: { "action":"cameraReset", "duration":0.5, "ease":"quadOut", "async":true }
			case 'cameraReset':
				_doCameraReset(step);

			// ── cameraTarget ──────────────────────────────────────────────────────
			// Centra la cámara en un sprite (de la cutscene o del stage) hasta que se
			// cancele. La cámara sigue al sprite en cada frame desde _camTarget.
			// JSON: { "action":"cameraTarget", "camTarget":"senpaiEvil" }
			// JSON: { "action":"cameraTarget", "camTarget":null }   ← dejar de seguir
			case 'cameraTarget':
				// FIX: renamed from "target" to "camTarget" in SpriteCutsceneData
				// to avoid collision with the fadeTimer "target:Float" field.
				var targetId:Null<String> = (step : Dynamic).camTarget;
				if (targetId == null || targetId == '' || targetId == 'null')
				{
					_camTarget = null;
				}
				else
				{
					var t = _sprites.get(targetId);
					if (t == null) t = _resolveStageChar(targetId);
					_camTarget = t;
					// Centrar inmediatamente
					if (_camTarget != null)
						FlxG.camera.focusOn(_camTarget.getMidpoint());
				}
				_nextStep();

			// ── setCamVisible ──────────────────────────────────────────────────────
			// Muestra u oculta una cámara del PlayState con fade suave de alpha.
			// JSON: { "action": "setCamVisible", "cam": "hud", "visible": false }
			//       { "action": "setCamVisible", "cam": "hud", "visible": false, "duration": 0.4, "async": true }
			// Valores para "cam": "hud" | "game" | "countdown"
			// duration (default 0.3s), ease, async igual que otros tweens.
			// Al terminar/saltar la cutscene se restauran alpha y visible automáticamente.
			case 'setCamVisible':
				_doSetCamVisible(step);

			// ── call ───────────────────────────────────────────────────────────────
			// Ejecuta una función registrada con registerCallback() sin bloquear.
			// JSON / builder: { action:'call', id:'myFn' }
			// La función se llama sin parámetros: fn()
			case 'call':
				var cbId:String = step.id ?? '';
				var cb = _callbackMap.get(cbId);
				if (cb != null) try { cb(); } catch (e:Dynamic) trace('[SpriteCutscene] call error: $e');
				_nextStep();

			// ── callAsync ──────────────────────────────────────────────────────────
			// Ejecuta una función que recibe un callback `done:Void->Void`.
			// La cutscene se bloquea hasta que el script llame a done().
			// JSON / builder: { action:'callAsync', id:'myFn' }
			// La función recibe done: fn(done) { ...; done(); }
			case 'callAsync':
				var asyncId:String = step.id ?? '';
				var asyncCb = _callbackMap.get(asyncId);
				if (asyncCb == null) { _nextStep(); return; }
				_blocked = true;
				try
				{
					asyncCb(function() {
						if (_skipped) return;
						_blocked = false;
						_nextStep();
					});
				}
				catch (e:Dynamic)
				{
					trace('[SpriteCutscene] callAsync error: $e');
					_blocked = false;
					_nextStep();
				}

			// ── waitBeat ───────────────────────────────────────────────────────────
			// Bloquea la cutscene hasta que Conductor llega al beat indicado.
			// Si el beat ya pasó, continúa inmediatamente.
			// JSON / builder: { action:'waitBeat', beat:8 }
			case 'waitBeat':
				var targetBeat:Int = Std.int((step : Dynamic).beat ?? 0);
				// Leer curBeat vía Conductor para no necesitar @:privateAccess en MusicBeatState.
				var getCurrentBeat = function():Int
					return Std.int(funkin.data.Conductor.getBeatAtTime(funkin.data.Conductor.songPosition));
				if (getCurrentBeat() >= targetBeat) { _nextStep(); return; }
				_blocked = true;
				var _bt = new FlxTimer();
				_timers.push(_bt);
				_bt.start(0.016, function(t:FlxTimer) {
					if (_skipped) return;
					if (getCurrentBeat() >= targetBeat) {
						_timers.remove(t); t.cancel();
						_blocked = false;
						_nextStep();
					} else {
						t.reset(0.016);
					}
				});

			// ── waitStep ───────────────────────────────────────────────────────────
			// Bloquea hasta que Conductor llega al step indicado.
			// JSON / builder: { action:'waitStep', step:32 }
			case 'waitStep':
				var targetStep:Int = Std.int((step : Dynamic).step ?? 0);
				var getCurrentStep = function():Int
					return Std.int(funkin.data.Conductor.getStepAtTime(funkin.data.Conductor.songPosition));
				if (getCurrentStep() >= targetStep) { _nextStep(); return; }
				_blocked = true;
				var _st = new FlxTimer();
				_timers.push(_st);
				_st.start(0.016, function(t:FlxTimer) {
					if (_skipped) return;
					if (getCurrentStep() >= targetStep) {
						_timers.remove(t); t.cancel();
						_blocked = false;
						_nextStep();
					} else {
						t.reset(0.016);
					}
				});

			// ── _registerCleanup (interno, generado por CutsceneBuilder.onCleanup) ──
			// Registra una función para llamarla cuando la cutscene termine o se salte.
			case '_registerCleanup':
				var cleanId:String = step.id ?? '';
				var cleanFn = _callbackMap.get(cleanId);
				if (cleanFn != null) _cleanupCallbacks.push(cleanFn);
				_nextStep();

			// ── subtitle ──────────────────────────────────────────────────────────
			// Muestra un subtítulo. NO bloquea la cutscene (async).
			// JSON: { "action": "subtitle", "text": "Hello", "duration": 3.0,
			//         "size": 28, "color": "0xFFFF00", "bgAlpha": 0.7,
			//         "align": "center", "bold": true, "font": "vcr.ttf",
			//         "y": 620, "fadeIn": 0.2, "fadeOut": 0.3 }
			case 'subtitle':
				final _sd:Dynamic = step;
				final _subText = _sd.text != null ? Std.string(_sd.text) : '';
				if (_subText != '')
				{
					final _subDur = _sd.duration != null ? _sd.duration : 3.0;
					// Construir opts solo con campos que existan en el paso
					var _subOpts:Dynamic = null;
					inline function _hasF(f:String) return Reflect.hasField(_sd, f) && Reflect.field(_sd, f) != null;
					if (_hasF('size') || _hasF('color') || _hasF('bgColor') || _hasF('bgAlpha')
					 || _hasF('align') || _hasF('bold')  || _hasF('font')    || _hasF('y')
					 || _hasF('padX')  || _hasF('padY')  || _hasF('fadeIn')  || _hasF('fadeOut'))
					{
						_subOpts = {};
						if (_hasF('size'))    _subOpts.size    = _sd.size;
						if (_hasF('bgAlpha')) _subOpts.bgAlpha = _sd.bgAlpha;
						if (_hasF('align'))   _subOpts.align   = _sd.align;
						if (_hasF('bold'))    _subOpts.bold    = _sd.bold;
						if (_hasF('font'))    _subOpts.font    = _sd.font;
						if (_hasF('padX'))    _subOpts.padX    = _sd.padX;
						if (_hasF('padY'))    _subOpts.padY    = _sd.padY;
						if (_hasF('fadeIn'))  _subOpts.fadeIn  = _sd.fadeIn;
						if (_hasF('fadeOut')) _subOpts.fadeOut = _sd.fadeOut;
						// color y bgColor como Int (pueden venir como "0xFFFF00" o int)
						if (_hasF('color'))
							_subOpts.color = Std.parseInt(Std.string(_sd.color)) ?? _sd.color;
						if (_hasF('bgColor'))
							_subOpts.bgColor = Std.parseInt(Std.string(_sd.bgColor)) ?? _sd.bgColor;
						// y puede reutilizar el campo y del step (Float)
						if (_hasF('y')) _subOpts.y = _sd.y;
					}
					funkin.ui.SubtitleManager.instance.show(_subText, _subDur, _subOpts);
				}
				_nextStep();

			// ── subtitleHide ──────────────────────────────────────────────────────
			// Oculta el subtítulo actual.
			// JSON: { "action": "subtitleHide" }
			//       { "action": "subtitleHide", "instant": true }
			case 'subtitleHide', 'subtitle hide':
				final _sdH:Dynamic = step;
				funkin.ui.SubtitleManager.instance.hide(_sdH.instant == true);
				_nextStep();

			// ── subtitleClear ─────────────────────────────────────────────────────
			// Oculta el subtítulo y vacía la cola.
			// JSON: { "action": "subtitleClear" }
			case 'subtitleClear', 'subtitle clear':
				funkin.ui.SubtitleManager.instance.clear();
				_nextStep();

			// ── subtitleStyle ─────────────────────────────────────────────────────
			// Cambia el estilo global para futuros subtítulos.
			// JSON: { "action": "subtitleStyle", "size": 28, "color": "0xFFFFFF",
			//         "bgAlpha": 0.6, "align": "center", "bold": true }
			case 'subtitleStyle', 'subtitle style':
				final _sdS:Dynamic = step;
				final _styleOpts:Dynamic = {};
				inline function _cpF(f:String) {
					if (Reflect.hasField(_sdS, f) && Reflect.field(_sdS, f) != null)
						Reflect.setField(_styleOpts, f, Reflect.field(_sdS, f));
				}
				_cpF('size'); _cpF('color'); _cpF('bgColor'); _cpF('bgAlpha');
				_cpF('align'); _cpF('bold'); _cpF('font'); _cpF('y');
				_cpF('padX'); _cpF('padY'); _cpF('fadeIn'); _cpF('fadeOut');
				funkin.ui.SubtitleManager.instance.setStyle(_styleOpts);
				_nextStep();

			// ── subtitleResetStyle ────────────────────────────────────────────────
			// Restaura el estilo global a los defaults.
			// JSON: { "action": "subtitleResetStyle" }
			case 'subtitleResetStyle', 'subtitle reset style':
				funkin.ui.SubtitleManager.instance.resetStyle();
				_nextStep();

			case 'end':
				_cleanup();
				_finish();

			default:
				trace('[SpriteCutscene] Acción desconocida: "${step.action}"');
				_nextStep();
		}
	}

	// ── add ───────────────────────────────────────────────────────────────────

	function _doAdd(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var id = step.sprite ?? '';
		var spr = _sprites.get(id);

		// Crear el sprite si no existe aún
		if (spr == null)
		{
			spr = _createSprite(id);
			if (spr == null) { _nextStep(); return; }
			_sprites.set(id, spr);
		}

		if (step.alpha != null) spr.alpha = step.alpha;
		// Asignar la cámara de cutscene para que el sprite se renderice
		// por encima del HUD y el gameplay.
		spr.cameras = [_camCutscene];
		_state.add(spr);
		_nextStep();
	}

	function _createSprite(id:String):Null<FlxSprite>
	{
		if (_doc.sprites == null) return null;
		var data:SpriteCutsceneData.CutsceneSpriteData = Reflect.field(_doc.sprites, id);
		if (data == null)
		{
			trace('[SpriteCutscene] Sprite "$id" no encontrado en "sprites".');
			return null;
		}

		var spr:FlxSprite;
		var sf = data.scrollFactor ?? 0.0;

		switch (data.type ?? 'rect')
		{
			// ── Rectángulo sólido ─────────────────────────────────────────────
			case 'rect':
				spr = new FlxSprite();
				var w = Std.int((data.width  ?? 1.0) * FlxG.width);
				var h = Std.int((data.height ?? 1.0) * FlxG.height);
				spr.makeGraphic(w, h, _parseColor(data.color ?? 'BLACK'));
				spr.scrollFactor.set(sf, sf);

			// ── Imagen estática (images/) ──────────────────────────────────────
			case 'image':
				var imgSpr = new FunkinSprite();
				var key = data.image ?? id;
				var g = Paths.getGraphic(key);
				if (g != null) imgSpr.loadGraphic(g);
				else imgSpr.makeGraphic(150, 150, 0x00000000);
				imgSpr.scrollFactor.set(sf, sf);
				spr = imgSpr;

			// ── Personaje (characters/images/) ────────────────────────────────
			//    FunkinSprite.loadCharacterSparrow detecta automáticamente:
			//    Multi-Animate (.sheets) → Animate folder → Sparrow → Packer
			case 'character':
				var charSpr = new FunkinSprite();
				charSpr.scrollFactor.set(sf, sf);
				charSpr.loadCharacterSparrow(data.image ?? id);
				_addAnims(charSpr, data);
				spr = charSpr;

			// ── Stage sprite (stages/) ────────────────────────────────────────
			case 'stage':
				var stageSpr = new FunkinSprite();
				stageSpr.scrollFactor.set(sf, sf);
				stageSpr.loadStageSparrow(data.image ?? id);
				_addAnims(stageSpr, data);
				spr = stageSpr;

			// ── Atlas genérico (images/) — auto-detecta Sparrow/Packer/Animate ─
			//    FunkinSprite.loadAsset detecta por extensión XML/TXT/Animation.json
			case 'atlas', 'sparrow', 'packer', 'animate', 'flxanimate', 'auto':
				var atlasSpr = new FunkinSprite();
				atlasSpr.scrollFactor.set(sf, sf);

				var pathList:Array<String> = data.paths;
				if (pathList != null && pathList.length > 1)
					// Multi-atlas explícito (varios PNG+XML o carpetas Animate)
					atlasSpr.loadMultiAnimateAtlas(pathList);
				else if (pathList != null && pathList.length == 1)
					atlasSpr.loadAsset(pathList[0]);
				else
					atlasSpr.loadAsset(data.image ?? id);

				_addAnims(atlasSpr, data);
				spr = atlasSpr;

			// ── Placeholder visible para tipos desconocidos ───────────────────
			default:
				trace('[SpriteCutscene] Tipo desconocido "${data.type}" para sprite "$id" — usando placeholder.');
				spr = new FlxSprite();
				spr.makeGraphic(150, 150, 0x44FF0000);
				spr.scrollFactor.set(sf, sf);
		}

		// Propiedades comunes
		if (data.x != null)      spr.x = data.x;
		if (data.y != null)      spr.y = data.y;
		if (data.alpha != null)  spr.alpha = data.alpha;
		if (data.angle != null)  spr.angle = data.angle;
		if (data.flipX != null)  spr.flipX = data.flipX;
		if (data.flipY != null)  spr.flipY = data.flipY;
		spr.antialiasing = data.antialiasing ?? true;

		if (data.scale != null)
		{
			spr.setGraphicSize(Std.int(spr.width * data.scale));
			spr.updateHitbox();
		}
		else if (data.scaleX != null || data.scaleY != null)
		{
			spr.scale.set(data.scaleX ?? 1.0, data.scaleY ?? 1.0);
			spr.updateHitbox();
		}

		if (data.center == true) _screenCenter(spr, 'xy');

		return spr;
	}

	// ── _addAnims: registra animaciones en un FunkinSprite ───────────────────
	// FunkinSprite.addAnim() detecta automáticamente si el sprite es Animate
	// (frame labels) o Sparrow (addByPrefix/addByIndices).

	function _addAnims(spr:FunkinSprite, data:SpriteCutsceneData.CutsceneSpriteData):Void
	{
		if (data.animations == null) return;
		var anims:Array<SpriteCutsceneData.CutsceneSpriteAnim> = cast data.animations;
		for (anim in anims)
			spr.addAnim(anim.name, anim.prefix, anim.fps ?? 24, anim.loop ?? false, anim.indices);
	}

	// ── fadeTimer ─────────────────────────────────────────────────────────────

	function _doFadeTimer(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var spr = _sprites.get(step.sprite ?? '');
		if (spr == null) { _nextStep(); return; }

		var target   = step.target   ?? 0.0;
		var stepAmt  = step.step     ?? 0.15;
		var interval = step.interval ?? 0.3;
		_blocked = true;

		var _ft = new FlxTimer();
		_timers.push(_ft);
		_ft.start(interval, function(tmr:FlxTimer)
		{
			if (_skipped) return;

			if (target < spr.alpha)
				spr.alpha = Math.max(target, spr.alpha - stepAmt);
			else
				spr.alpha = Math.min(target, spr.alpha + stepAmt);

			if (Math.abs(spr.alpha - target) < 0.001)
			{
				spr.alpha = target;
				_blocked  = false;
				_timers.remove(tmr);
				_nextStep();
			}
			else
			{
				tmr.reset(interval);
			}
		});
	}

	// ── tween ─────────────────────────────────────────────────────────────────

	function _doTween(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var spr = _sprites.get(step.sprite ?? '');
		if (spr == null) { _nextStep(); return; }

		var dur  = step.duration ?? 1.0;
		var ease = _parseEase(step.ease);

		if (step.async ?? false)
		{
			var tw = FlxTween.tween(spr, step.props ?? {}, dur, { ease: ease ?? FlxEase.linear });
			_tweens.push(tw);
			_nextStep();
		}
		else
		{
			_blocked = true;
			var tw = FlxTween.tween(spr, step.props ?? {}, dur, {
				ease:       ease ?? FlxEase.linear,
				onComplete: function(t) { _tweens.remove(t); _blocked = false; _nextStep(); }
			});
			_tweens.push(tw);
		}
	}

	// ── stageAnim ─────────────────────────────────────────────────────────────

	/**
	 * Busca un personaje existente en el PlayState por nombre y le lanza la
	 * animación indicada. Esto permite hacer cutscenes usando directamente
	 * los personajes del stage sin añadir sprites extra.
	 *
	 * Nombres reconocidos para el campo "sprite":
	 *   "bf" | "boyfriend"  → PlayState.boyfriend
	 *   "dad" | "opponent"  → PlayState.dad
	 *   "gf" | "girlfriend" → PlayState.gf
	 *
	 * Si "wait" es true, la cutscene se bloquea hasta que la animación termine.
	 * JSON: { "action": "stageAnim", "sprite": "bf", "anim": "hey",
	 *         "force": true, "wait": false }
	 */
	function _doStageAnim(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var char = _resolveStageChar(step.sprite ?? '');
		if (char == null)
		{
			trace('[SpriteCutscene] stageAnim: personaje "${step.sprite}" no encontrado.');
			_nextStep();
			return;
		}

		var animName = step.anim ?? '';
		var force    = step.force ?? true;

		// Usar playAnim si es un Character (FNF), animation.play si es genérico
		if (Std.isOfType(char, funkin.gameplay.objects.character.Character))
			cast(char, funkin.gameplay.objects.character.Character).playAnim(animName, force);
		else if (char.animation != null)
			char.animation.play(animName, force);

		// Si wait=true esperar a que la animación termine antes de continuar
		if ((step : Dynamic).wait == true && char.animation != null)
		{
			_blocked = true;
			var _wt = new FlxTimer();
			_timers.push(_wt);
			// Poll cada frame (0.016s) hasta que la anim acabe
			_wt.start(0.016, function(t:FlxTimer)
			{
				if (_skipped) return;
				var anim = char.animation;
				// La animación acabó si finished=true o ya no está la misma
				if (anim == null || anim.curAnim == null || anim.curAnim.finished)
				{
					_timers.remove(t);
					t.cancel();
					_blocked = false;
					_nextStep();
				}
				else
				{
					t.reset(0.016);
				}
			});
		}
		else
		{
			_nextStep();
		}
	}

	/**
	 * Resuelve el nombre de personaje a un FlxSprite del PlayState activo.
	 * Devuelve null si no hay PlayState activo o el nombre no coincide.
	 */
	function _resolveStageChar(name:String):Null<FlxSprite>
	{
		var ps = funkin.gameplay.PlayState.instance;
		if (ps == null) return null;

		return switch (name.toLowerCase())
		{
			case 'bf', 'boyfriend':           ps.boyfriend;
			case 'dad', 'opponent', 'enemy':  ps.dad;
			case 'gf', 'girlfriend':          ps.gf;
			// Fallback: buscar en sprites de cutscene por si alguien reutilizó el nombre
			default:
				var found = _sprites.get(name);
				if (found != null) found else null;
		};
	}

	// ── playSound ─────────────────────────────────────────────────────────────

	function _doPlaySound(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var key     = step.key ?? '';
		var vol     = step.volume ?? 1.0;
		var id      = step.id;
		var stepDyn = (step : Dynamic);

		// ── Resolución de ruta ────────────────────────────────────────────────
		// Por defecto usa Paths.sound().
		// "music": true  → Paths.music()       (carpeta music/ del mod)
		// "stage": true  → Paths.soundStage()  (carpeta stages/<curStage>/... del mod)
		//                  Perfecto para sonidos que viven en phillyStreets/sounds/
		//                  o phillyStreets/music/ sin copiarlos a la carpeta global.
		//
		// Ejemplos en JSON:
		//   { "action":"playSound", "key":"Darnell_Lighter", "stage":true }
		//      → stages/phillyStreets/sounds/Darnell_Lighter.ogg
		//   { "action":"playSound", "key":"darnellCanCutscene", "music":true, "stage":true }
		//      → stages/phillyStreets/music/darnellCanCutscene.ogg
		var isMusic:Bool = stepDyn.music == true;
		var isStage:Bool = stepDyn.stage == true;

		var path:String;
		if (isStage)
		{
			// soundStage espera "stageName/subpath/key" — anteponemos el stage actual
			// y la subcarpeta según si es música o sonido.
			var curStage = funkin.gameplay.PlayState.curStage ?? Paths.currentStage;
			var sub      = isMusic ? 'music' : 'sounds';
			path = Paths.soundStage('$curStage/$sub/$key');
		}
		else if (isMusic)
		{
			path = Paths.music(key);
		}
		else
		{
			path = Paths.sound(key);
		}

		var snd = FlxG.sound.play(path, vol);

		if (id != null && snd != null)
			_sounds.set(id, snd);

		_nextStep(); // playSound nunca bloquea por sí solo — usar waitSound
	}

	// ── waitSound ─────────────────────────────────────────────────────────────

	function _doWaitSound(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var id = step.id ?? '';
		var snd = _sounds.get(id);

		if (snd == null) { _nextStep(); return; }
		if (!snd.playing) { _nextStep(); return; }

		_blocked = true;
		var prevComplete = snd.onComplete;
		snd.onComplete = function()
		{
			if (prevComplete != null) prevComplete();
			_blocked = false;
			_nextStep();
		};
	}

	// ── cameraFade ────────────────────────────────────────────────────────────

	function _doCameraFade(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var col    = _parseColor(step.color ?? 'BLACK');
		var dur    = step.duration ?? 0.5;
		var fadeIn = step.fadeIn   ?? false;

		if (step.async ?? false)
		{
			FlxG.camera.fade(col, dur, fadeIn);
			_nextStep();
		}
		else
		{
			_blocked = true;
			FlxG.camera.fade(col, dur, fadeIn, function()
			{
				_blocked = false;
				_nextStep();
			});
		}
	}

	// ─── helpers ──────────────────────────────────────────────────────────────

	function _screenCenter(spr:FlxSprite, axis:String):Void
	{
		switch (axis.toLowerCase())
		{
			case 'x':  spr.x = (FlxG.width  - spr.width)  * 0.5;
			case 'y':  spr.y = (FlxG.height - spr.height) * 0.5;
			default:   spr.screenCenter();
		}
	}

	static function _parseColor(s:String):FlxColor
	{
		if (s == null) return FlxColor.BLACK;
		var upper = s.toUpperCase();
		return switch (upper)
		{
			case 'BLACK':       FlxColor.BLACK;
			case 'WHITE':       FlxColor.WHITE;
			case 'RED':         FlxColor.RED;
			case 'GREEN':       FlxColor.GREEN;
			case 'BLUE':        FlxColor.BLUE;
			case 'YELLOW':      FlxColor.YELLOW;
			case 'CYAN':        FlxColor.CYAN;
			case 'MAGENTA':     FlxColor.MAGENTA;
			case 'TRANSPARENT': FlxColor.TRANSPARENT;
			default:
				// FIX color negro → blanco: FlxColor.fromString() solo acepta el prefijo '#',
				// NO '0x'. Cuando recibe '0xFF000000' devuelve TRANSPARENT (sin lanzar
				// excepción), y makeGraphic con transparente muestra el bitmap blanco subyacente.
				// Solución: detectar el prefijo '0x'/'0X' y parsear con Std.parseInt, que sí
				// entiende el formato 0xRRGGBB / 0xAARRGGBB correctamente.
				if (upper.startsWith('0X'))
				{
					var val = Std.parseInt(s);
					if (val != null) return (val : FlxColor);
				}
				// Para strings con '#' dejamos fromString (acepta #RGB, #RRGGBB, #AARRGGBB)
				try   { return FlxColor.fromString(s); }
				catch (_) { return FlxColor.BLACK; }
		};
	}

	static function _parseEase(s:Null<String>):Null<Float->Float>
	{
		if (s == null) return null;
		return switch (s.toLowerCase())
		{
			case 'linear':       FlxEase.linear;
			case 'quadin':       FlxEase.quadIn;
			case 'quadout':      FlxEase.quadOut;
			case 'quadinout':    FlxEase.quadInOut;
			case 'sinein':       FlxEase.sineIn;
			case 'sineout':      FlxEase.sineOut;
			case 'sineinout':    FlxEase.sineInOut;
			case 'cubein':       FlxEase.cubeIn;
			case 'cubeout':      FlxEase.cubeOut;
			case 'cubeinout':    FlxEase.cubeInOut;
			case 'elasticin':    FlxEase.elasticIn;
			case 'elasticout':   FlxEase.elasticOut;
			case 'bouncein':     FlxEase.bounceIn;
			case 'bounceout':    FlxEase.bounceOut;
			case 'backin':       FlxEase.backIn;
			case 'backout':      FlxEase.backOut;
			default:             null;
		};
	}

	// ── camera helpers ──────────────────────────────────────────────────────────

	function _doCameraZoom(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var targetZoom = step.zoom ?? 1.0;
		var dur  = step.duration ?? 0.5;
		var ease = _parseEase(step.ease);

		if (step.async ?? false)
		{
			var tw = FlxTween.tween(FlxG.camera, {zoom: targetZoom}, dur,
				{ ease: ease ?? FlxEase.quadOut });
			_tweens.push(tw);
			_nextStep();
		}
		else
		{
			_blocked = true;
			var tw = FlxTween.tween(FlxG.camera, {zoom: targetZoom}, dur,
			{
				ease: ease ?? FlxEase.quadOut,
				onComplete: function(t) { _tweens.remove(t); _blocked = false; _nextStep(); }
			});
			_tweens.push(tw);
		}
	}

	function _doCameraPan(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var dur  = step.duration ?? 0.6;
		var ease = _parseEase(step.ease);

		// FIX: cameraPan mueve el SCROLL (qué parte del mundo se ve),
		// NO camera.x/y (que son posición en pantalla — siempre 0,0 en FNF).
		// FlxG.camera.scroll es un FlxPoint con x/y tweeneable directamente.
		var props:Dynamic = {};
		if (step.camX != null) Reflect.setField(props, 'x', step.camX);
		if (step.camY != null) Reflect.setField(props, 'y', step.camY);

		if (step.async ?? false)
		{
			var tw = FlxTween.tween(FlxG.camera.scroll, props, dur,
				{ ease: ease ?? FlxEase.sineInOut });
			_tweens.push(tw);
			_nextStep();
		}
		else
		{
			_blocked = true;
			var tw = FlxTween.tween(FlxG.camera.scroll, props, dur,
			{
				ease: ease ?? FlxEase.sineInOut,
				onComplete: function(t) { _tweens.remove(t); _blocked = false; _nextStep(); }
			});
			_tweens.push(tw);
		}
	}

	function _doCameraTween(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var props = step.camProps ?? {};
		var dur   = step.duration ?? 0.5;
		var ease  = _parseEase(step.ease);

		if (step.async ?? false)
		{
			var tw = FlxTween.tween(FlxG.camera, props, dur,
				{ ease: ease ?? FlxEase.quadOut });
			_tweens.push(tw);
			_nextStep();
		}
		else
		{
			_blocked = true;
			var tw = FlxTween.tween(FlxG.camera, props, dur,
			{
				ease: ease ?? FlxEase.quadOut,
				onComplete: function(t) { _tweens.remove(t); _blocked = false; _nextStep(); }
			});
			_tweens.push(tw);
		}
	}

	function _doCameraReset(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var dur  = step.duration ?? 0.0;
		var ease = _parseEase(step.ease);

		var scrollProps:Dynamic = { x: _origCamX, y: _origCamY };

		if (dur <= 0)
		{
			FlxG.camera.zoom     = _origCamZoom;
			FlxG.camera.scroll.x = _origCamX;
			FlxG.camera.scroll.y = _origCamY;
			_nextStep();
		}
		else if (step.async ?? false)
		{
			FlxTween.tween(FlxG.camera,        { zoom: _origCamZoom }, dur, { ease: ease ?? FlxEase.quadOut });
			var tw = FlxTween.tween(FlxG.camera.scroll, scrollProps,   dur, { ease: ease ?? FlxEase.quadOut });
			_tweens.push(tw);
			_nextStep();
		}
		else
		{
			_blocked = true;
			FlxTween.tween(FlxG.camera, { zoom: _origCamZoom }, dur, { ease: ease ?? FlxEase.quadOut });
			var tw = FlxTween.tween(FlxG.camera.scroll, scrollProps, dur,
			{
				ease: ease ?? FlxEase.quadOut,
				onComplete: function(t) { _tweens.remove(t); _blocked = false; _nextStep(); }
			});
			_tweens.push(tw);
		}
	}

	// ── setCamVisible ─────────────────────────────────────────────────────────

	/**
	 * Muestra u oculta una cámara del PlayState con un fade suave de alpha.
	 *
	 * JSON:
	 *   { "action": "setCamVisible", "cam": "hud", "visible": false }
	 *   { "action": "setCamVisible", "cam": "hud", "visible": false, "duration": 0.4, "ease": "quadOut" }
	 *   { "action": "setCamVisible", "cam": "hud", "visible": false, "duration": 0.4, "async": true }
	 *
	 * - "duration" controla cuánto dura el fade (default: 0.3s).
	 *   Con duration=0 el cambio es instantáneo (sin tween).
	 * - "async": true → no bloquea la cadena de pasos (el fade corre en paralelo).
	 * - La visibilidad y alpha originales se restauran automáticamente en cleanup.
	 *
	 * @param step  Paso completo (se leen cam, visible, duration, ease, async)
	 */
	function _doSetCamVisible(step:SpriteCutsceneData.CutsceneStep):Void
	{
		var ps = funkin.gameplay.PlayState.instance;
		if (ps == null) { _nextStep(); return; }

		var camName:String = (step : Dynamic).cam ?? 'hud';
		var key = camName.toLowerCase().replace('cam', '');

		var cam:FlxCamera = switch (key)
		{
			case 'hud':        ps.camHUD;
			case 'game':       ps.camGame;
			case 'countdown':  ps.camCountdown;
			default:           null;
		};

		if (cam == null) { _nextStep(); return; }

		// Guardar alpha y visible originales la primera vez que tocamos esta cámara.
		if (!_hiddenCamsAlpha.exists(key))
			_hiddenCamsAlpha.set(key, cam.alpha);
		if (!_hiddenCams.exists(key))
			_hiddenCams.set(key, cam.visible);

		var makeVisible:Bool = step.visible ?? true;
		var dur:Float        = step.duration ?? 0.3;
		var ease             = _parseEase(step.ease);
		var isAsync:Bool     = step.async ?? false;
		var targetAlpha:Float = makeVisible ? 1.0 : 0.0;

		// Si vamos a mostrar la cámara, activar visible ANTES del fade
		// para que el tween sea visible desde el primer frame.
		if (makeVisible) cam.visible = true;

		if (dur <= 0)
		{
			// Instantáneo: sin tween
			cam.alpha   = targetAlpha;
			if (!makeVisible) cam.visible = false;
			_nextStep();
		}
		else if (isAsync)
		{
			var tw = FlxTween.tween(cam, { alpha: targetAlpha }, dur,
			{
				ease: ease ?? FlxEase.quadOut,
				onComplete: function(_)
				{
					// Al terminar el fade-out, ocultar visible para
					// que la cámara no consuma fill-rect cada frame.
					if (!makeVisible) cam.visible = false;
				}
			});
			_tweens.push(tw);
			_nextStep();
		}
		else
		{
			_blocked = true;
			var tw = FlxTween.tween(cam, { alpha: targetAlpha }, dur,
			{
				ease: ease ?? FlxEase.quadOut,
				onComplete: function(t)
				{
					_tweens.remove(t);
					if (!makeVisible) cam.visible = false;
					_blocked = false;
					_nextStep();
				}
			});
			_tweens.push(tw);
		}
	}

	// ── cleanup / finish ──────────────────────────────────────────────────────

	/** Tick de seguimiento de cámara — se conecta a FlxG.signals.preUpdate. */
	function _onPreUpdate():Void
	{
		// ── Detección de pausa del juego ─────────────────────────────────────
		// Un substate abierto (PauseSubState, etc.) significa que el juego está
		// en pausa. FlxTimerManager y FlxTweenManager son plugins globales y NO
		// se detienen solos → hay que gestionarlos manualmente aquí.
		var isGamePaused:Bool = (FlxG.state != null && FlxG.state.subState != null);

		if (isGamePaused && !_wasGamePaused)
		{
			_pauseCutscene();
		}
		else if (!isGamePaused && _wasGamePaused)
		{
			_resumeCutscene();
		}
		_wasGamePaused = isGamePaused;

		// No actualizar lógica de cámara mientras el juego esté pausado
		if (isGamePaused) return;

		// Sincronizar _camCutscene con FlxG.camera en cada frame para que
		// los sprites con scrollFactor=1 aparezcan correctamente sobre el stage.
		if (_camCutscene != null)
		{
			_camCutscene.scroll.copyFrom(FlxG.camera.scroll);
			_camCutscene.zoom = FlxG.camera.zoom;
		}

		if (_camTarget != null && playing)
			FlxG.camera.focusOn(_camTarget.getMidpoint());
	}

	/**
	 * Pausa la cutscene cuando el juego entra en pausa (substate abierto).
	 * Pausa manualmente timers, tweens, sonidos y animaciones de sprites propios
	 * porque FlxTimerManager/FlxTweenManager son plugins globales que no respetan
	 * el active=false del estado padre.
	 */
	function _pauseCutscene():Void
	{
		// Pausar timers de la cutscene
		for (t in _timers)
			t.active = false;

		// Pausar tweens de la cutscene
		for (tw in _tweens)
			tw.active = false;

		// Pausar sonidos propios de la cutscene
		for (snd in _sounds)
			if (snd != null && snd.playing) snd.pause();

		// Pausar animaciones de los sprites propios de la cutscene
		for (spr in _sprites)
		{
			if (spr == null) continue;
			if (spr.animation != null && spr.animation.curAnim != null)
				spr.animation.curAnim.paused = true;
			// FlxAnimate
			if (Reflect.hasField(spr, 'anim') && (spr : Dynamic).anim != null)
				try { (spr : Dynamic).anim.pause(); } catch (_:Dynamic) {}
		}
	}

	/**
	 * Reanuda la cutscene cuando el juego sale de pausa (substate cerrado).
	 */
	function _resumeCutscene():Void
	{
		// Reanudar timers
		for (t in _timers)
			t.active = true;

		// Reanudar tweens
		for (tw in _tweens)
			tw.active = true;

		// Reanudar sonidos
		for (snd in _sounds)
			if (snd != null) snd.resume();

		// Reanudar animaciones de los sprites propios
		for (spr in _sprites)
		{
			if (spr == null) continue;
			if (spr.animation != null && spr.animation.curAnim != null)
				spr.animation.curAnim.paused = false;
			// FlxAnimate
			if (Reflect.hasField(spr, 'anim') && (spr : Dynamic).anim != null)
				try { (spr : Dynamic).anim.resume(); } catch (_:Dynamic) {}
		}
	}

	/**
	 * Congela/descongela los personajes del PlayState durante la cutscene.
	 * Pausa/reanuda sus animaciones para que no sigan bailando mientras
	 * la cutscene reproduce sus propias animaciones con stageAnim.
	 */
	function _setCharactersFrozen(freeze:Bool):Void
	{
		var ps = funkin.gameplay.PlayState.instance;
		if (ps == null) return;
		// GF no se congela: solo bopea al ritmo y no interfiere con la cutscene.
		// Congelarla haría que se quedase estática durante toda la cinemática.
		var chars:Array<Dynamic> = [];
		if (ps.boyfriend != null) chars.push(ps.boyfriend);
		if (ps.dad       != null) chars.push(ps.dad);
		for (c in chars)
		{
			if (c == null) continue;
			try
			{
				// FunkinSprite / FlxAnimate: pausar/reanudar la animación
				if (freeze)
				{
					if (c.animation != null && c.animation.curAnim != null)
						c.animation.curAnim.paused = true;
					// FlxAnimate usa anim.pause() / anim.resume()
					if (Reflect.hasField(c, 'anim') && c.anim != null)
						c.anim.pause();
				}
				else
				{
					if (c.animation != null && c.animation.curAnim != null)
						c.animation.curAnim.paused = false;
					if (Reflect.hasField(c, 'anim') && c.anim != null)
						c.anim.resume();
				}
			}
			catch (_:Dynamic) {}
		}
	}

	/**
	 * Fuerza a bf, dad y gf a volver a su animación idle/dance después de
	 * que la cutscene termine.
	 *
	 * ESTRATEGIA para evitar el "snap" brusco al idle:
	 *  • Animaciones NO looping (intro2, laughCutscene…):  avanzar al último
	 *    frame. Character.update() verá animFinished=true en el siguiente tick
	 *    y llamará a dance() por sí solo — la transición queda a cargo del
	 *    sistema de animación del personaje, exactamente igual a cuando la
	 *    animación termina durante el gameplay.
	 *  • Animaciones looping: forzar returnToIdle() directamente porque nunca
	 *    terminarían solas y el personaje se quedaría congelado en esa pose.
	 */
	function _returnCharactersToIdle():Void
	{
		var ps = funkin.gameplay.PlayState.instance;
		if (ps == null) return;
		// GF no se incluye: nunca fue congelada, su sistema de animación ya la gestiona.
		var chars:Array<Dynamic> = [ps.boyfriend, ps.dad];
		for (c in chars)
		{
			if (c == null) continue;
			try
			{
				var anim = c.animation;
				if (anim == null || anim.curAnim == null) continue;

				if (anim.curAnim.looped)
				{
					// Looping → nunca terminaría: forzar idle ahora
					if (Std.isOfType(c, funkin.gameplay.objects.character.Character))
						cast(c, funkin.gameplay.objects.character.Character).returnToIdle();
				}
				else
				{
					// No-looping → avanzar al último frame para que el update
					// loop del Character detecte animFinished y llame a dance().
					// Esto preserva la transición natural definida en el personaje.
					final last = anim.curAnim.numFrames - 1;
					if (anim.curAnim.curFrame < last)
						anim.curAnim.curFrame = last;
					// Despausar (por si _setCharactersFrozen la dejó pausada)
					anim.curAnim.paused = false;
				}
			}
			catch (_:Dynamic) {}
		}
	}

	function _cleanup():Void
	{
		// Resetear estado de pausa para que no queden timers/tweens desactivados
		// si la cutscene se reutiliza o se salta mientras el juego está pausado.
		_wasGamePaused = false;
		// FIX animaciones: reanudar los personajes al terminar la cutscene
		_setCharactersFrozen(false);
		// FIX animaciones persisten: forzar a cada personaje a su idle/dance
		// después de la cutscene. _setCharactersFrozen(false) solo despausa la
		// animación que quedó activa (ej. intro2, laughCutscene); con esto la
		// reseteamos limpiamente a la pose de espera sin esperar al update loop.
		_returnCharactersToIdle();
		// Desconectar el tick de seguimiento de cámara
		FlxG.signals.preUpdate.remove(_onPreUpdate);
		// Por si la cutscene terminó antes de que se disparara el postDraw inicial
		FlxG.signals.postDraw.remove(_onFirstPostDraw);
		_camTarget = null;

		// FIX cámara se bloquea al personaje: restaurar el follow que
		// desconectamos en play(). También hacemos snap inmediato a la
		// posición correcta del target para que la cámara no "vuele" desde
		// donde quedó la cutscene hasta el personaje con un lerp largo.
		if (_camFollowDisabled)
		{
			var ps = funkin.gameplay.PlayState.instance;
			if (ps != null && ps.cameraController != null)
			{
				var cc = ps.cameraController;
				// Snap del camFollow al target actual ANTES de re-activar follow,
				// así el primer frame post-cutscene la cámara ya está en el sitio correcto.
				cc.snapshotInitialState(); // refresca los valores internos tras cambios de zoom
				FlxG.camera.follow(cc.camFollow, flixel.FlxCamera.FlxCameraFollowStyle.LOCKON, cc.followLerp);
			}
			_camFollowDisabled = false;
		}

		// FIX setCamVisible: restaurar visibilidad y alpha originales de cada
		// cámara que la cutscene modificó con setCamVisible.
		var ps2 = funkin.gameplay.PlayState.instance;
		if (ps2 != null)
		{
			for (key => wasVisible in _hiddenCams)
			{
				var cam:FlxCamera = switch (key)
				{
					case 'hud':        ps2.camHUD;
					case 'game':       ps2.camGame;
					case 'countdown':  ps2.camCountdown;
					default:           null;
				};
				if (cam != null)
				{
					// Cancelar cualquier tween de alpha pendiente sobre esta cámara
					FlxTween.cancelTweensOf(cam);
					cam.alpha   = _hiddenCamsAlpha.exists(key) ? _hiddenCamsAlpha.get(key) : 1.0;
					cam.visible = wasVisible;
				}
			}
		}
		_hiddenCams.clear();
		_hiddenCamsAlpha.clear();

		for (spr in _sprites) _state.remove(spr);
		for (snd in _sounds)  if (snd.playing) snd.stop();
		_sprites.clear();
		_sounds.clear();
		_callbackMap.clear();

		// Llamar callbacks de limpieza registrados con onCleanup()
		for (fn in _cleanupCallbacks)
			try { fn(); } catch (e:Dynamic) trace('[SpriteCutscene] onCleanup error: $e');
		_cleanupCallbacks = [];

		// Cancelar solo los timers y tweens de ESTA cutscene,
		// sin tocar el globalManager (que mataría timers de audio/música).
		for (t in _timers)  { try t.cancel() catch (_) {}; }
		for (tw in _tweens) { try tw.cancel() catch (_) {}; }
		_timers  = [];
		_tweens  = [];

		// Eliminar la cámara dedicada de la lista de Flixel.
		if (_camCutscene != null)
		{
			FlxG.cameras.remove(_camCutscene, true);
			_camCutscene = null;
		}
	}

	function _finish():Void
	{
		playing  = false;
		finished = true;
		final cb = _onComplete;
		_onComplete = null;
		if (cb != null) cb();
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  Carga del JSON
	// ═════════════════════════════════════════════════════════════════════════

	static function _loadDocument(key:String, ?song:String):Null<SpriteCutsceneData.CutsceneDocument>
	{
		#if sys
		var path = _resolvePath(key, song);
		if (path == null)
		{
			trace('[SpriteCutscene] JSON no encontrado para key="$key" song="$song".');
			return null;
		}
		try
		{
			var raw = File.getContent(path);
			return Json.parse(raw);
		}
		catch (e)
		{
			trace('[SpriteCutscene] Error al parsear "$path": $e');
			return null;
		}
		#else
		return null;
		#end
	}

	static function _resolvePath(key:String, ?song:String):Null<String>
	{
		#if sys
		var candidates:Array<String> = [];
		var modRoot = ModManager.modRoot();

		// Con subcarpeta de canción
		if (song != null)
		{
			if (modRoot != null)
			{
				candidates.push('$modRoot/data/cutscenes/$song/$key.json');
				candidates.push('$modRoot/data/cutscenes/$key.json');
				candidates.push('$modRoot/songs/$song/$key.json');
			}
			candidates.push('assets/data/cutscenes/$song/$key.json');
			candidates.push('assets/songs/$song/$key.json');
		}

		// Sin subcarpeta
		if (modRoot != null)
			candidates.push('$modRoot/data/cutscenes/$key.json');
		candidates.push('assets/data/cutscenes/$key.json');

		for (p in candidates)
			if (FileSystem.exists(p)) return p;
		#end
		return null;
	}

	// ── API estática de conveniencia ──────────────────────────────────────────

	/**
	 * Crea y ejecuta una cutscene directamente.
	 * Equivalente a: new SpriteCutscene(state, key).play(onComplete)
	 */
	public static function create(state:flixel.FlxState, key:String,
		?song:String, ?onComplete:Void->Void):SpriteCutscene
	{
		var cut = new SpriteCutscene(state, key, song);
		cut.play(onComplete);
		return cut;
	}

	/** Comprueba si existe el JSON de una cutscene sin cargarla. */
	public static function exists(key:String, ?song:String):Bool
	{
		return _resolvePath(key, song) != null;
	}
}
