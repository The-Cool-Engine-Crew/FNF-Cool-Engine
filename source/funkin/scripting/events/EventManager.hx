package funkin.scripting.events;

import flixel.FlxG;
import funkin.gameplay.PlayState;
import funkin.gameplay.objects.character.Character;
import funkin.data.Song.SwagSong;
import funkin.data.Section.SwagSection;
import Paths;
import funkin.scripting.events.EventRegistry;
import funkin.scripting.events.EventHandlerLoader;

using StringTools;

/**
 * Sistema de eventos de gameplay.
 *
 * Infraestructura pura: carga, disparo y registro de handlers.
 * Los handlers concretos viven en `assets/data/scripts/events/`
 * y se registran con `registerEvent()` desde HScript.
 *
 * ─── Optimizaciones respecto a la versión anterior ───────────────────────────
 *   • Puntero de índice en `update()` — sin array `toRemove` por frame.
 *   • `events` ya no se modifica durante `update()`, sólo se avanza el índice.
 *   • `stepTimeToMs` es `inline` — el compilador la inlinea en hot paths.
 *   • `triggerEvent` sin creación de closures en el path normal.
 *
 * ─── Uso desde HScript ───────────────────────────────────────────────────────
 *   registerEvent('Flash', function(v1, v2, time) {
 *     FlxG.cameras.flash(FlxColor.WHITE, 0.5);
 *   });
 *   fireEvent('Flash');
 */
class EventManager
{
	/** Todos los eventos de la canción actual, ordenados por tiempo. */
	public static var events : Array<EventData> = [];

	/** Handlers custom registrados por scripts. */
	public static var customHandlers : Map<String, Array<EventData>->Bool> = [];

	/**
	 * Índice del siguiente evento a comprobar en `update()`.
	 * Al ser un puntero, update() nunca necesita crear arrays temporales.
	 */
	static var _nextIndex : Int = 0;

	// ─── Carga ────────────────────────────────────────────────────────────────

	/**
	 * Carga y ordena eventos desde `PlayState.SONG`.
	 * Llamar DESPUÉS de que `Conductor` esté configurado.
	 */
	public static function loadEventsFromSong():Void
	{
		// Limpiar pool de precacheo del run anterior (restart o cambio de canción)
		// antes de construir el nuevo, para no acumular dummies de runs previos.
		Character.releasePrecachePool();

		events     = [];
		_nextIndex = 0;

		final songData:SwagSong = PlayState.SONG;
		if (songData == null) return;

		if (songData.events != null && songData.events.length > 0)
			loadNewFormat(songData);
		else if (songData.notes != null)
			loadLegacyFormat(songData);

		// Compatibilidad hacia atrás: generar Camera Follow desde mustHitSection
		// si el chart (old .json o nuevo .level) no contiene ningún evento de cámara.
		if (songData.notes != null)
		{
			var hasCam = false;
			for (e in events) if (e.name == 'Camera Follow') { hasCam = true; break; }
			if (!hasCam) generateCameraFollow(songData);
		}

		events.sort((a, b) -> Std.int(a.time - b.time));

		// Refrescar `game` en los scripts ahora que PlayState.instance existe.
		ScriptHandler.setOnScripts('game', PlayState.instance);

		// ── Cargar handlers de eventos del contexto "chart" ───────────────────
		// EventRegistry descubre los .hx / .lua de data/events/chart/
		// EventHandlerLoader los carga y los mantiene listos para dispatch.
		EventRegistry.reload();
		EventHandlerLoader.loadContext('chart');
		EventHandlerLoader.loadContext('global');

		// ── Precacheo proactivo de Change Character ───────────────────────────
		_precacheChangeCharacters();

		// ── onEventPushed: cubre restart y entrada directa sin LoadingState ──
		// LoadingState ya lo llamó antes de entrar a PlayState; aquí es el
		// respaldo para accesos directos (debug, restart rápido, etc.).
		// precacheCharacter() tiene guard interno → segunda llamada gratuita.
		_dispatchEventPushed();

		trace('[EventManager] ${events.length} eventos cargados.');
	}

	static function loadNewFormat(songData:SwagSong):Void
	{
		for (evt in songData.events)
		{
			var v1 = evt.value != null ? evt.value : '';
			var v2 = '';

			if (v1.contains('|'))
			{
				final firstPipe = v1.indexOf('|');
				final rest = v1.substring(firstPipe + 1);
				if (rest.contains('|'))
				{
					// Valor multi-pipe (Camera Follow con offsets/duration/ease, Camera Zoom con ease, etc.)
					// Dejar v1 intacto — el handler built-in lo parsea él mismo con split('|').
					// Si se pre-partiera aquí, los campos extra (offsetY, duration, ease) se perderían
					// silenciosamente y v2 recibiría el offsetX, que el handler interpreta como lerp speed.
				}
				else
				{
					// Formato clásico dos-campos: "v1|v2" (Change Character, Camera Shake, etc.)
					v1 = v1.substring(0, firstPipe).trim();
					v2 = rest.trim();
				}
			}

			final e    = new EventData();
			e.name     = evt.type;
			e.time     = stepToMs(evt.stepTime, songData.bpm);
			e.value1   = v1;
			e.value2   = v2;
			events.push(e);
		}
		trace('[EventManager] Formato nuevo: ${events.length} eventos.');
	}

	static function loadLegacyFormat(songData:SwagSong):Void
	{
		final sections:Array<SwagSection> = cast songData.notes;
		for (section in sections)
		{
			if (section.sectionNotes == null) continue;
			for (note in section.sectionNotes)
			{
				if (note.length < 5 || note[4] == null || Std.string(note[4]) == '') continue;
				final e  = new EventData();
				e.name   = Std.string(note[4]);
				e.time   = note[0];
				e.value1 = note.length >= 6 ? Std.string(note[5]) : '';
				e.value2 = note.length >= 7 ? Std.string(note[6]) : '';
				events.push(e);
			}
		}
		trace('[EventManager] Formato legacy: ${events.length} eventos.');
	}

	static function generateCameraFollow(songData:SwagSong):Void
	{
		var lastTarget = '';
		var step:Float = 0;
		var bpm:Float  = songData.bpm;
		var count = 0;

		final sections:Array<SwagSection> = cast songData.notes;
		for (section in sections)
		{
			final stepsInSection:Float = section.lengthInSteps > 0 ? section.lengthInSteps : 16;
			// gfSing (gfSection en Psych) tiene prioridad sobre mustHitSection
			final target = (section.gfSing == true) ? 'gf' : (section.mustHitSection ? 'player' : 'opponent');

			if (target != lastTarget)
			{
				final e  = new EventData();
				e.name   = 'Camera Follow';
				e.time   = stepToMs(step, bpm);
				e.value1 = target;
				events.push(e);
				lastTarget = target;
				count++;
			}

			if (section.changeBPM && section.bpm > 0) bpm = section.bpm;
			step += stepsInSection;
		}
		trace('[EventManager] Auto-generados $count Camera Follow desde mustHitSection/gfSection.');
	}

	// ─── Update ───────────────────────────────────────────────────────────────

	/**
	 * Dispara los eventos cuyo tiempo ha llegado.
	 * Usa un puntero de índice — sin allocaciones por frame.
	 */
	public static function update(songPosition:Float):Void
	{
		while (_nextIndex < events.length)
		{
			final event = events[_nextIndex];
			if (songPosition < event.time) break;

			if (!event.triggered)
			{
				event.triggered = true;
				triggerEvent(event);
			}
			_nextIndex++;
		}
	}

	// ─── Disparo ──────────────────────────────────────────────────────────────

	public static function triggerEvent(event:EventData):Void
	{
		trace('[EventManager] -> "${event.name}" | v1="${event.value1}" v2="${event.value2}" t=${event.time}ms');

		final v1 = event.value1 ?? '';
		final v2 = event.value2 ?? '';

		// 1. Los scripts globales pueden cancelar el evento devolviendo true en `onEvent`.
		if (ScriptHandler.callOnScriptsReturn('onEvent',
			([event.name, v1, v2, event.time] : Array<Dynamic>), false) == true)
		{
			trace('[EventManager] Cancelado por script global.');
			return;
		}

		// 2. Handler custom registrado vía registerCustomEvent() / registerEvent()
		final customHandler = customHandlers.get(event.name);
		if (customHandler != null)
		{
			if (customHandler([event]))
			{
				trace('[EventManager] Manejado por handler custom.');
				return;
			}
		}

		// 3. Script handler por-evento (data/events/chart/EventName.hx|.lua)
		//    Si devuelve true, cancela el built-in pero no el paso 1 ni 2.
		if (EventHandlerLoader.dispatch(event.name, v1, v2, event.time))
		{
			trace('[EventManager] Manejado por EventHandlerLoader (built-in cancelado).');
			return;
		}

		// 4. Built-in handlers del engine
		_handleBuiltin(event);
	}
	/**
	 * Handlers built-in para todos los eventos nativos.
	 * Los scripts pueden cancelarlos con `onEvent` devolviendo true.
	 *
	 * ── Eventos soportados ──────────────────────────────────────────────────
	 *   Camera Follow / Camera : v1=target(bf/dad/gf), v2=lerp
	 *   Camera Zoom            : v1=zoom, v2=speed
	 *   Camera Shake           : v1=intensity, v2=duration
	 *   Camera Flash / Flash   : v1=color(hex), v2=duration
	 *   Camera Fade / Fade     : v1=color(hex), v2=duration
	 *   BPM Change             : v1=newBPM
	 *   Play Anim              : v1=target ou "target:anim", v2=anim
	 *   Alt Anim               : v1=target, v2=true/false
	 *   Change Character       : v1=slot, v2=newCharName
	 *   HUD Visible            : v1=true/false
	 *   Health Change          : v1=amount
	 *   Add Health             : v1=amount
	 *   Play Sound             : v1=key, v2=volume
	 *   Music Change           : v1=key
	 *   Play Video             : v1=videoKey, v2=midSong(true/false)
	 *   Stop Video
	 *   Run Script             : v1=functionName, v2=arg
	 *   Set Var                : v1=varPath, v2=value
	 *   End Song
	 */
	static function _handleBuiltin(e:EventData):Void
	{
		final game = PlayState.instance;
		final v1   = e.value1 != null ? e.value1 : '';
		final v2   = e.value2 != null ? e.value2 : '';

		switch (e.name.toLowerCase())
		{
			// -- Camera ---------------------------------------------------
			case 'camera follow', 'camera':
				if (game != null && game.cameraController != null)
				{
					// Formato: "target|offsetX|offsetY|duration|ease"
					// Todos los campos salvo target son opcionales.
					// NOTA: loadNewFormat preserva el string completo en v1 para este evento
					// (no lo parte en v1/v2), de modo que parts contiene todos los segmentos.
					final parts = v1.split('|');
					final target  = parts[0].trim();
					final offX    = parts.length > 1 ? Std.parseFloat(parts[1]) : Math.NaN;
					final offY    = parts.length > 2 ? Std.parseFloat(parts[2]) : Math.NaN;
					final dur     = parts.length > 3 ? Std.parseFloat(parts[3]) : Math.NaN;
					final ease    = parts.length > 4 ? parts[4].trim() : '';

					final extraOffX = Math.isNaN(offX) ? 0.0 : offX;
					final extraOffY = Math.isNaN(offY) ? 0.0 : offY;
					final hasDur    = !Math.isNaN(dur) && dur > 0;

					if (hasDur)
					{
						// Evento con tween: cambiar target y animar hacia él.
						// setTarget() snapeará camFollow si no está bloqueado;
						// tweenToTarget() iniciará el pan (cancelando cualquier tween previo).
						game.cameraController.setTarget(target, extraOffX, extraOffY);
						var easeFunc:Null<Float->Float> = null;
						if (ease != '')
							easeFunc = Reflect.field(flixel.tweens.FlxEase, ease);
						// Solo tweenear si la función de ease es válida.
						// Si el nombre no existe en FlxEase, usar lerp normal (no tween).
						if (easeFunc != null)
							game.cameraController.tweenToTarget(dur, easeFunc);
					}
					else
					{
						// Evento snap (sin duration): cancelar cualquier pan tween activo
						// para que la cámara salte inmediatamente al nuevo target, incluso
						// si había un pan largo en curso (e.g. FocusCamera CLASSIC en V-Slice).
						game.cameraController.cancelPan();
						game.cameraController.setTarget(target, extraOffX, extraOffY);
					}

					// v2 legacy: lerp speed (solo para eventos del formato antiguo sin pipes en v1)
					// Con el nuevo formato multi-pipe, v2 siempre es '' para Camera Follow,
					// así que este bloque solo actúa en eventos legacy explícitos.
					if (v2 != '')
					{
						final lerp = Std.parseFloat(v2);
						if (!Math.isNaN(lerp)) game.cameraController.setFollowLerp(lerp);
					}
				}

			// Camera Focus: centra la camara entre los dos personajes.
			// v1 = target ('both' para centrar, o 'bf'/'dad'/'gf' igual que Camera Follow)
			// v2 = lerp speed opcional
			case 'camera focus', 'focus camera', 'focus':
				if (game != null && game.cameraController != null)
				{
					final focusTarget = (v1 != '') ? v1 : 'both';
					game.cameraController.setTarget(focusTarget);
					if (v2 != '')
					{
						final lerp = Std.parseFloat(v2);
						if (!Math.isNaN(lerp)) game.cameraController.setFollowLerp(lerp);
					}
				}

			case 'camera zoom', 'zoom camera':
				if (game != null && game.cameraController != null)
				{
					// v1 puede ser "zoom" (simple) o "zoom|duration|ease|mode" (multi-pipe desde V-Slice).
					// Parsear solo el primer segmento para obtener el valor de zoom.
					final zoom = Std.parseFloat(v1.split('|')[0]);
					if (!Math.isNaN(zoom)) game.cameraController.defaultZoom = zoom;
					game.cameraController.zoomEnabled = true;
				}

			case 'camera shake', 'shake camera':
				final intensity = v1 != '' ? (Std.parseFloat(v1)) : 0.005;
				final dur       = v2 != '' ? (Std.parseFloat(v2)) : 0.25;
				flixel.FlxG.cameras.shake(
					Math.isNaN(intensity) ? 0.005 : intensity,
					Math.isNaN(dur) ? 0.25 : dur);

			case 'camera flash', 'flash camera', 'flash':
				final col = _parseColor(v1 != '' ? v1 : 'FFFFFF');
				final dur = v2 != '' ? Std.parseFloat(v2) : 0.5;
				flixel.FlxG.camera.flash(col, Math.isNaN(dur) ? 0.5 : dur);

			case 'camera fade', 'fade camera', 'fade':
				final col = _parseColor(v1 != '' ? v1 : '000000');
				final dur = v2 != '' ? Std.parseFloat(v2) : 0.5;
				flixel.FlxG.camera.fade(col, Math.isNaN(dur) ? 0.5 : dur);

			// -- BPM ------------------------------------------------------
			case 'bpm change', 'change bpm':
				final bpm = Std.parseFloat(v1);
				if (!Math.isNaN(bpm) && bpm > 0)
				{
					funkin.data.Conductor.changeBPM(bpm);
					trace('[EventManager] BPM -> $bpm');
				}

			// -- Characters -----------------------------------------------
			case 'play anim', 'play animation':
				var tgt  = v1;
				var anim = v2;
				if (v1.contains(':')) { final p = v1.split(':'); tgt = p[0].trim(); anim = p[1].trim(); }
				if (game != null)
				{
					final ch = _resolveChar(game, tgt);
					if (ch != null && anim != '') ch.playAnim(anim, true);
				}

			case 'alt anim', 'alt idle animation':
				// isPlayingSpecialAnim() is a read-only method that reflects current anim state.
				// Toggling alt-anim mode requires script-side handling via onEvent.
				if (game != null)
					ScriptHandler.callOnScripts('onAltAnim', [v1, v2]);

			case 'change character', 'swap character':
				// FIX: el built-in ahora realiza el swap real con reloadCharacter().
				// Antes solo llamaba a scripts (que quizás no estaban cargados en
				// ScriptHandler), por lo que el evento no hacía nada visible.
				if (game != null && v1 != '' && v2 != '')
				{
					final target = _resolveChar(game, v1);
					if (target != null)
					{
						target.reloadCharacter(v2);
						// Actualizar iconos del HUD si existe uiManager
						if (game.uiManager != null && game.boyfriend != null && game.dad != null)
							game.uiManager.setIcons(game.boyfriend.healthIcon, game.dad.healthIcon);
					}
					else
						trace('[EventManager] Change Character: slot "${v1}" no reconocido.');
					// Notificar a scripts por si necesitan reaccionar al cambio
					ScriptHandler.callOnScripts('onCharacterChange', [v1, v2]);
				}

			// -- HUD / Score ----------------------------------------------
			case 'hud visible', 'toggle hud':
				if (game != null && game.uiManager != null)
					game.uiManager.visible = (v1.toLowerCase() != 'false' && v1 != '0');

			case 'health change', 'set health':
				if (game?.gameState != null)
				{
					final amt = Std.parseFloat(v1);
					if (!Math.isNaN(amt)) game.gameState.health = Math.max(0.0, Math.min(2.0, amt));
				}

			case 'add health', 'heal':
				if (game?.gameState != null)
				{
					final amt = Std.parseFloat(v1);
					if (!Math.isNaN(amt)) game.gameState.modifyHealth(amt);
				}

			// -- Audio ----------------------------------------------------
			case 'play sound', 'sound':
				if (v1 != '')
				{
					final vol = v2 != '' ? Std.parseFloat(v2) : 1.0;
					flixel.FlxG.sound.play(Paths.sound(v1), Math.isNaN(vol) ? 1.0 : vol);
				}

			case 'music change', 'change music':
				if (v1 != '') flixel.FlxG.sound.playMusic(Paths.music(v1), 1, true);

			// -- Video ----------------------------------------------------
			case 'play video', 'video':
				// v1=videoKey, v2="true" para mid-song (pausa la cancion)
				if (v1 != '')
				{
					final midSong = (v2.toLowerCase() == 'true' || v2 == '1')
					             || (game?.metaData?.midSongVideo == true);
					if (midSong && game != null)
					{
						funkin.cutscenes.VideoManager.playMidSong(v1, game, function()
						{
							if (flixel.FlxG.sound.music != null) flixel.FlxG.sound.music.resume();
							if (game != null) game.paused = false;
						});
					}
					else
					{
						funkin.cutscenes.VideoManager.playCutscene(v1);
					}
				}

			case 'stop video', 'kill video':
				funkin.cutscenes.VideoManager.stop();

			// -- Flow -----------------------------------------------------
			case 'end song':
				if (game != null) game.endSong();

			case 'run script', 'call script':
				if (v1 != '') ScriptHandler.callOnScripts(v1, v2 != '' ? [v2] : []);

			case 'set var', 'set variable':
				_setScriptVar(v1, v2);

			// -- Subtítulos ---------------------------------------------------
			// value1 = texto (soporta formato extendido "texto|size|color|bgAlpha")
			// value2 = duración en segundos (default: 3.0)
			case 'subtitle', 'show subtitle':
				if (v1 != '')
				{
					final parsed = funkin.ui.SubtitleManager.parseEventValue(v1, v2);
					funkin.ui.SubtitleManager.instance.show(
						parsed.text, parsed.duration, parsed.options);
				}

			case 'subtitle hide', 'hide subtitle':
				funkin.ui.SubtitleManager.instance.hide();

			case 'subtitle clear', 'clear subtitles', 'clear subtitle':
				funkin.ui.SubtitleManager.instance.clear();

			default:
				trace('[EventManager] Sin handler para "${e.name}" -- registra uno con registerCustomEvent() o en scripts.');
		}
	}

	// -- Helpers ---------------------------------------------------------------

	/**
	 * Escanea todos los eventos ya cargados buscando "Change Character".
	 * Por cada personaje nuevo único, llama a Character.precacheCharacter()
	 * para que su JSON y spritesheet queden en los caches estáticos antes
	 * de que empiece el gameplay → cambio de personaje sin hitch.
	 */
	static function _precacheChangeCharacters():Void
	{
		final seen:Map<String, Bool> = [];
		var count = 0;

		for (e in events)
		{
			if (e.name.toLowerCase() != 'change character' && e.name.toLowerCase() != 'swap character')
				continue;

			final charName = e.value2 != null ? e.value2.trim() : '';
			if (charName == '' || seen.exists(charName)) continue;

			seen.set(charName, true);
			Character.precacheCharacter(charName);
			count++;
		}

		if (count > 0)
			trace('[EventManager] Precacheados $count personajes de Change Character.');
	}

	/**
	 * Despacha `onEventPushed(name, v1, v2, time)` en todos los scripts cargados
	 * por cada evento del chart ya parseado en `events`.
	 *
	 * Esto permite que scripts como `ChangeCharacter.hx` precacheen assets
	 * (atlas, iconos) en cuanto se conoce el chart, antes de que arranque la música.
	 *
	 * Llamado desde:
	 *   • `loadEventsFromSong()`     — cubre restart y entrada directa a PlayState
	 *   • `LoadingState._precacheChartEvents()` — cubre la pantalla de carga visual
	 */
	public static function _dispatchEventPushed():Void
	{
		for (e in events)
			ScriptHandler.callOnScripts('onEventPushed', [e.name, e.value1, e.value2, e.time]);
	}

	static function _resolveChar(game:PlayState,
	                             slot:String):Null<funkin.gameplay.objects.character.Character>
	{
		// Delegar en PlayState.getCharacterByName que soporta aliases, índices y nombres exactos
		return game.getCharacterByName(slot);
	}

	static function _parseColor(s:String):flixel.util.FlxColor
	{
		final c = s.startsWith('#') ? s.substr(1) : s;
		try
		{
			final v = Std.parseInt('0x$c');
			return c.length <= 6
				? flixel.util.FlxColor.fromRGB((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
				: new flixel.util.FlxColor(v);
		}
		catch (_:Dynamic) { return flixel.util.FlxColor.WHITE; }
	}

	static function _setScriptVar(path:String, value:String):Void
	{
		if (!path.contains('.')) { ScriptHandler.setOnScripts(path, value); return; }
		final parts = path.split('.');
		final obj   = ScriptHandler.getFromScripts(parts[0]);
		if (obj != null && parts.length > 1)
			Reflect.setField(obj, parts[1], value);
	}

	// ─── API pública ──────────────────────────────────────────────────────────

	/** Registra un handler custom para eventos con `name`. */
	public static function registerCustomEvent(name:String, handler:Array<EventData>->Bool):Void
		customHandlers.set(name, handler);

	/**
	 * Dispara un evento manualmente (fuera del timeline).
	 * El tiempo se lee de la posición actual de la música.
	 */
	public static function fireEvent(name:String, value1:String = '', value2:String = ''):Void
	{
		final e  = new EventData();
		e.name   = name;
		e.time   = FlxG.sound.music != null ? FlxG.sound.music.time : 0;
		e.value1 = value1;
		e.value2 = value2;
		triggerEvent(e);
	}

	public static function clear():Void
	{
		events = [];
		customHandlers.clear();
		_nextIndex = 0;
		// Liberar dummies del pool que no llegaron a usarse (personajes opcionales
		// que el jugador nunca alcanzó en la canción).
		Character.releasePrecachePool();
	}

	/**
	 * Rebobina todos los eventos al estado "no disparado" y reinicia el puntero
	 * al inicio del timeline. Llamar al hacer rewind restart.
	 * Los eventos se re-dispararán naturalmente conforme la canción avance de nuevo.
	 */
	public static function rewindToStart():Void
	{
		_nextIndex = 0;
		for (e in events)
			e.triggered = false;
		trace('[EventManager] Rewind: ${events.length} eventos marcados como no disparados.');
	}

	/**
	 * Avanza el puntero hasta `posMs` SIN disparar eventos.
	 * Los eventos anteriores a `posMs` quedan marcados como disparados
	 * para que no se re-ejecuten cuando la música llegue a ellos.
	 * Útil para seek en el editor (no queremos re-ejecutar efectos al scrubear).
	 */
	public static function seekTo(posMs:Float):Void
	{
		_nextIndex = 0;
		for (e in events) e.triggered = false;
		while (_nextIndex < events.length && events[_nextIndex].time < posMs)
		{
			events[_nextIndex].triggered = true;
			_nextIndex++;
		}
	}

	// ─── Util ─────────────────────────────────────────────────────────────────

	/** 1 beat = 60 000 / bpm ms  |  1 step = 1 beat / 4 */
	public static inline function stepToMs(step:Float, bpm:Float):Float
		return step * (60000.0 / bpm / 4.0);
}

// ─────────────────────────────────────────────────────────────────────────────

/** Datos de un evento de gameplay. Puede crearse como objeto anónimo. */
class EventData
{
	public var name      : String = '';
	public var time      : Float  = 0;
	public var value1    : String = '';
	public var value2    : String = '';
	public var triggered : Bool   = false;

	public function new() {}

	public function toString():String
		return 'Event["$name" @ ${time}ms | "$value1" "$value2"]';
}
