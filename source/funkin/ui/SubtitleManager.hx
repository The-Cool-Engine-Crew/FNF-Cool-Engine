package funkin.ui;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;

/**
 * SubtitleManager — Sistema de subtítulos en pantalla.
 *
 * Singleton global que muestra texto con fondo semitransparente sobre el HUD.
 * Funciona en gameplay, cutscenes y cualquier estado del engine.
 * Lee automáticamente la configuración guardada (tamaño, color, posición,
 * opacidad, negrita, fade) y puede traducir el texto vía MyMemory / Lingva.
 *
 * ─── Uso desde HScript ─────────────────────────────────────────────────────
 *
 *   // Mostrar subtítulo durante 3 segundos
 *   subtitle.show("Hello World", 3.0);
 *
 *   // Con opciones de estilo (sobreescriben los globales guardados)
 *   subtitle.show("Hello", 2.0, { size: 28, color: 0xFFFF00, bgAlpha: 0.7 });
 *
 *   // Sin auto-hide (se queda hasta hide() o clear())
 *   subtitle.show("Permanent text", 0);
 *
 *   // Ocultar manualmente
 *   subtitle.hide();
 *
 *   // Cola de subtítulos (uno tras otro)
 *   subtitle.queue([
 *     { text: "Line 1", duration: 2.0 },
 *     { text: "Line 2", duration: 1.5, options: { color: 0xFFFF00 } }
 *   ]);
 *
 *   // Configurar estilo global
 *   subtitle.setStyle({ size: 28, color: 0xFFFFFF, bgAlpha: 0.6 });
 *   subtitle.resetStyle();
 *
 *   // Limpiar todo (hide + vaciar cola)
 *   subtitle.clear();
 *
 * ─── Uso desde Lua ──────────────────────────────────────────────────────────
 *
 *   showSubtitle("Hello World", 3.0)
 *   showSubtitle("Hello", 2.0, { size=28, color=0xFFFF00, bgAlpha=0.7 })
 *   hideSubtitle()                   -- fade-out suave
 *   hideSubtitle(true)               -- instantáneo
 *   clearSubtitles()                 -- hide + vacía la cola
 *   queueSubtitle({                  -- cola secuencial
 *     { text="Line 1", duration=2 },
 *     { text="Line 2", duration=1.5 }
 *   })
 *   setSubtitleStyle({ size=28, color=0xFFFFFF })
 *   resetSubtitleStyle()
 *
 * ─── Desde eventos del chart ────────────────────────────────────────────────
 *
 *   Nombre del evento: "Subtitle"
 *   value1 = texto a mostrar
 *   value2 = duración en segundos (vacío = 3.0)
 *
 *   Nombre del evento: "Subtitle Hide" o "Hide Subtitle"
 *   (sin value)
 *
 *   Nombre del evento: "Subtitle Clear" o "Clear Subtitles"
 *   (sin value)
 *
 *   Formato extendido con | en value1: "text|size|color|bgAlpha"
 *   Ejemplo: "Hello World|28|0xFFFF00|0.7"
 *
 * ─── Desde cutscene JSON ───────────────────────────────────────────────────
 *
 *   { "action": "subtitle", "text": "Hello World", "duration": 3.0 }
 *   { "action": "subtitle", "text": "Hello", "duration": 2.0,
 *     "size": 28, "color": "0xFFFF00", "bgAlpha": 0.7, "align": "center",
 *     "y": 620, "bold": true, "font": "vcr.ttf",
 *     "fadeIn": 0.2, "fadeOut": 0.3 }
 *   { "action": "subtitleHide" }
 *   { "action": "subtitleHide", "instant": true }
 *   { "action": "subtitleClear" }
 *   { "action": "subtitleStyle", "size": 28, "color": "0xFFFFFF" }
 *
 * ─── Parámetros de opciones ─────────────────────────────────────────────────
 *
 *   text      → texto del subtítulo (soporta \n)
 *   duration  → segundos de visibilidad; 0 = manual (default: 3.0)
 *   size      → tamaño de fuente (default: 26)
 *   color     → color del texto como Int (default: 0xFFFFFFFF)
 *   bgColor   → color del fondo (default: 0xFF000000)
 *   bgAlpha   → opacidad del fondo 0.0-1.0 (default: 0.6)
 *   align     → "center" | "left" | "right" (default: "center")
 *   y         → posición Y en px; -1 = auto abajo (default: -1)
 *   bold      → negrita (default: true)
 *   font      → nombre del font en assets/fonts/ (default: "vcr.ttf")
 *   fadeIn    → duración fade-in en segundos (default: 0.2)
 *   fadeOut   → duración fade-out en segundos (default: 0.3)
 *   padX      → padding horizontal del fondo (default: 16)
 *   padY      → padding vertical del fondo (default: 10)
 *   instant   → si true, no aplica fade (solo en hide)
 */
class SubtitleManager
{
	// ── Singleton ─────────────────────────────────────────────────────────────

	static var _inst:SubtitleManager = null;

	/** Instancia global. Se crea automáticamente al primer acceso. */
	public static var instance(get, never):SubtitleManager;
	static inline function get_instance():SubtitleManager
	{
		if (_inst == null) _inst = new SubtitleManager();
		return _inst;
	}

	// ── Sprites ───────────────────────────────────────────────────────────────

	var _bg:FlxSprite;
	var _text:FlxText;
	/** Estado al que están añadidos los sprites actualmente. */
	var _attachedState:flixel.FlxState = null;

	// ── Tweens / Timers ───────────────────────────────────────────────────────

	var _autoTimer:FlxTimer = null;
	var _fadeActive:Bool    = false;

	// ── Cola de subtítulos ────────────────────────────────────────────────────

	var _queue:Array<_QueueEntry> = [];
	var _playing:Bool = false;

	// ── Estilo global (modifiable desde scripts o desde opciones) ─────────────

	public var defaultSize:Int      = 26;
	public var defaultColor:Int     = 0xFFFFFFFF;
	public var defaultBgColor:Int   = 0xFF000000;
	public var defaultBgAlpha:Float = 0.6;
	public var defaultAlign:String  = 'center';
	public var defaultFadeIn:Float  = 0.2;
	public var defaultFadeOut:Float = 0.3;
	public var defaultFont:String   = 'vcr.ttf';
	public var defaultBold:Bool     = true;
	/** Posición Y; -1 = automático (cerca del fondo), -2 = centrado vertical. */
	public var defaultY:Float       = -1;
	public var defaultPadX:Float    = 16;
	public var defaultPadY:Float    = 10;

	// ── Traducción ────────────────────────────────────────────────────────────

	/**
	 * Backend primario: MyMemory (GET, sin clave, 5000 chars/dia gratis).
	 * Sobrescribible desde HScript/Lua si se prefiere otro servidor.
	 */
	public static var translatePrimaryUrl:String =
		"https://api.mymemory.translated.net/get";

	/**
	 * Backend de fallback: Lingva Translate (GET, sin clave, sin limite).
	 * Dejar vacio para deshabilitar el fallback.
	 */
	public static var translateFallbackUrl:String =
		"https://lingva.ml/api/v1/auto";

	/** Si true, hay una petición de traducción en curso. */
	var _translating:Bool = false;

	// ── Constructor ───────────────────────────────────────────────────────────

	function new()
	{
		_bg   = new FlxSprite();
		_text = new FlxText(0, 0, 0, '', 26);
		_bg.scrollFactor.set(0, 0);
		_text.scrollFactor.set(0, 0);
		_bg.alpha   = 0;
		_text.alpha = 0;
		// z-order alto para que quede sobre todos los sprites del estado
		_bg.cameras   = [];
		_text.cameras = [];
	}

	// ══════════════════════════════════════════════════════════════════════════
	//  API pública
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Muestra un subtítulo. Cancela cualquier subtítulo o cola activa.
	 * Aplica automáticamente la configuración guardada en FlxG.save.data
	 * y traduce el texto si el usuario lo ha configurado.
	 *
	 * @param text      Texto a mostrar (soporta \n para varias líneas).
	 * @param duration  Segundos de visibilidad. 0 = sin auto-hide.
	 * @param options   Objeto con opciones de estilo (sobreescriben los globales).
	 */
	public function show(text:String, duration:Float = 3.0, ?options:Dynamic):Void
	{
		// Si subtítulos desactivados en opciones, ignorar
		if (FlxG.save.data.subtitlesEnabled == false) return;

		_cancelTimer();
		_cancelFade();
		_queue = [];

		// Aplicar preferencias guardadas al estilo global antes de mostrar
		_loadSavedSettings();

		// Traducir si está configurado
		var targetLang:String = FlxG.save.data.subtitleTranslateLang != null
			? FlxG.save.data.subtitleTranslateLang : '';

		if (targetLang != '' && !_translating)
		{
			_translating = true;
			// Mostrar el original mientras se traduce (indicador visual sutil)
			_doShow(text + " …", duration, options);

			_translateAsync(text, targetLang, function(translated:String) {
				_translating = false;
				// Reemplazar el texto con la traducción
				_cancelTimer();
				_cancelFade();
				_doShow(translated, duration, options);
			}, function() {
				// En caso de error, mantener el texto original sin el indicador
				_translating = false;
				_cancelTimer();
				_cancelFade();
				_doShow(text, duration, options);
			});
		}
		else
		{
			_doShow(text, duration, options);
		}
	}

	/**
	 * Oculta el subtítulo con fade-out (por defecto suave).
	 * @param instant  Si true, oculta sin animación.
	 */
	public function hide(instant:Bool = false):Void
	{
		_cancelTimer();
		if (_bg.alpha <= 0 && _text.alpha <= 0) return;

		if (instant)
		{
			_cancelFade();
			_bg.alpha   = 0;
			_text.alpha = 0;
			_removeSprites();
			_playing = false;
		}
		else
		{
			_startFadeOut(defaultFadeOut, function() {
				_removeSprites();
				_playing = false;
				_playNext();
			});
		}
	}

	/**
	 * Añade subtítulos a la cola. Se muestran uno tras otro cuando
	 * el subtítulo actual termina.
	 *
	 * @param entries  Array de objetos { text, duration, ?options }.
	 */
	public function queue(entries:Array<Dynamic>):Void
	{
		for (e in entries)
		{
			_queue.push({
				text:     e.text    != null ? Std.string(e.text)  : '',
				duration: e.duration != null ? _f(e.duration, 3.0) : 3.0,
				options:  e.options  != null ? e.options           : null
			});
		}
		if (!_playing) _playNext();
	}

	/**
	 * Cancela todo: oculta el subtítulo actual y vacía la cola.
	 */
	public function clear():Void
	{
		_cancelTimer();
		_cancelFade();
		_queue   = [];
		_playing = false;
		_bg.alpha   = 0;
		_text.alpha = 0;
		_removeSprites();
	}

	/**
	 * Configura el estilo global que se aplica a los siguientes show().
	 * Solo sobreescribe los campos presentes en opts.
	 */
	public function setStyle(opts:Dynamic):Void
	{
		if (opts == null) return;
		if (opts.size     != null) defaultSize     = Std.int(_f(opts.size,     defaultSize));
		if (opts.color    != null) defaultColor    = Std.int(_f(opts.color,    defaultColor));
		if (opts.bgColor  != null) defaultBgColor  = Std.int(_f(opts.bgColor,  defaultBgColor));
		if (opts.bgAlpha  != null) defaultBgAlpha  = _f(opts.bgAlpha,  defaultBgAlpha);
		if (opts.align    != null) defaultAlign    = Std.string(opts.align);
		if (opts.fadeIn   != null) defaultFadeIn   = _f(opts.fadeIn,   defaultFadeIn);
		if (opts.fadeOut  != null) defaultFadeOut  = _f(opts.fadeOut,  defaultFadeOut);
		if (opts.font     != null) defaultFont     = Std.string(opts.font);
		if (opts.bold     != null) defaultBold     = (opts.bold == true);
		if (opts.y        != null) defaultY        = _f(opts.y, -1);
		if (opts.padX     != null) defaultPadX     = _f(opts.padX, defaultPadX);
		if (opts.padY     != null) defaultPadY     = _f(opts.padY, defaultPadY);
	}

	/** Restablece el estilo global a los valores por defecto. */
	public function resetStyle():Void
	{
		defaultSize     = 26;
		defaultColor    = 0xFFFFFFFF;
		defaultBgColor  = 0xFF000000;
		defaultBgAlpha  = 0.6;
		defaultAlign    = 'center';
		defaultFadeIn   = 0.2;
		defaultFadeOut  = 0.3;
		defaultFont     = 'vcr.ttf';
		defaultBold     = true;
		defaultY        = -1;
		defaultPadX     = 16;
		defaultPadY     = 10;
	}

	// ══════════════════════════════════════════════════════════════════════════
	//  Carga de ajustes guardados
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Lee las preferencias de subtítulos del save y las aplica al estilo global.
	 * Se llama automáticamente en show() para respetar siempre los ajustes
	 * más recientes del usuario.
	 */
	function _loadSavedSettings():Void
	{
		var sd = FlxG.save.data;

		if (sd.subtitleFont    != null)  defaultFont     = sd.subtitleFont;
		if (sd.subtitleSize    != null)  defaultSize     = sd.subtitleSize;
		if (sd.subtitleColor   != null)  defaultColor    = sd.subtitleColor;
		if (sd.subtitleBgAlpha != null)  defaultBgAlpha  = sd.subtitleBgAlpha;
		if (sd.subtitleBold    != null)  defaultBold     = (sd.subtitleBold != false);
		if (sd.subtitleFadeIn  != null)
		{
			defaultFadeIn  = sd.subtitleFadeIn;
			defaultFadeOut = sd.subtitleFadeIn; // usar mismo valor para simetría
		}

		// Posición vertical
		var pos:String = sd.subtitlePosition != null ? sd.subtitlePosition : 'bottom';
		defaultY = switch (pos) {
			case 'top':    60.0;
			case 'center': -2.0;  // -2 = centrado vertical (tratado en _doShow)
			default:       -1.0;  // -1 = automático (cerca del fondo)
		};
	}

	// ══════════════════════════════════════════════════════════════════════════
	//  Traducción asíncrona — MyMemory (primario) + Lingva (fallback)
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Intenta traducir `text` al idioma `targetLang` usando MyMemory (GET).
	 * Si falla, reintenta con Lingva. Si ambos fallan, llama a onError().
	 * Nunca bloquea el hilo principal.
	 *
	 * MyMemory: GET https://api.mymemory.translated.net/get?q=...&langpair=auto|es
	 * Respuesta: { "responseData": { "translatedText": "..." }, "responseStatus": 200 }
	 *
	 * Lingva:   GET https://lingva.ml/api/v1/auto/{lang}/{encodedText}
	 * Respuesta: { "translation": "..." }
	 */
	function _translateAsync(text:String, targetLang:String,
		onSuccess:String->Void, onError:Void->Void):Void
	{
		_tryMyMemory(text, targetLang, onSuccess, function()
		{
			// MyMemory falló → intentar Lingva como fallback
			_tryLingva(text, targetLang, onSuccess, onError);
		});
	}

	/** Intenta traducir con MyMemory (GET, sin clave, ~5000 chars/día gratis). */
	function _tryMyMemory(text:String, targetLang:String,
		onSuccess:String->Void, onError:Void->Void):Void
	{
		if (translatePrimaryUrl == null || translatePrimaryUrl == '')
		{
			onError();
			return;
		}
		try
		{
			// MyMemory espera: langpair=auto|es  (source|target)
			var encoded = StringTools.urlEncode(text);
			var url = translatePrimaryUrl
				+ '?q=' + encoded
				+ '&langpair=auto%7C' + targetLang;

			var http = new haxe.Http(url);
			http.addHeader('Accept', 'application/json');

			http.onData = function(response:String)
			{
				try
				{
					var parsed:Dynamic = haxe.Json.parse(response);
					// MyMemory devuelve responseStatus 200/206 cuando tiene resultado
					var status:Int = parsed.responseStatus != null
						? Std.int(parsed.responseStatus) : 0;
					var translated:String = parsed?.responseData?.translatedText;
					if (translated != null && translated.length > 0
						&& status >= 200 && status < 300
						// MyMemory a veces devuelve "PLEASE SELECT TWO DISTINCT LANGUAGES" como error
						&& translated.substr(0, 6).toUpperCase() != 'PLEASE')
						onSuccess(translated);
					else
						onError();
				}
				catch (_) { onError(); }
			};

			http.onError = function(_) { onError(); };
			http.request(false); // GET
		}
		catch (_) { onError(); }
	}

	/** Intenta traducir con Lingva Translate (GET, sin clave). */
	function _tryLingva(text:String, targetLang:String,
		onSuccess:String->Void, onError:Void->Void):Void
	{
		if (translateFallbackUrl == null || translateFallbackUrl == '')
		{
			onError();
			return;
		}
		try
		{
			// Lingva: /api/v1/{source}/{target}/{encodedText}
			var encoded = StringTools.urlEncode(text);
			var url = translateFallbackUrl + '/' + targetLang + '/' + encoded;

			var http = new haxe.Http(url);
			http.addHeader('Accept', 'application/json');

			http.onData = function(response:String)
			{
				try
				{
					var parsed:Dynamic = haxe.Json.parse(response);
					var translated:String = parsed.translation;
					if (translated != null && translated.length > 0)
						onSuccess(translated);
					else
						onError();
				}
				catch (_) { onError(); }
			};

			http.onError = function(_) { onError(); };
			http.request(false); // GET
		}
		catch (_) { onError(); }
	}

	// ══════════════════════════════════════════════════════════════════════════
	//  Internos
	// ══════════════════════════════════════════════════════════════════════════

	function _doShow(text:String, duration:Float, ?opts:Dynamic):Void
	{
		// ── Leer opciones (con fallback al estilo global) ─────────────────────
		final size    = opts?.size    != null ? Std.int(_f(opts.size,    defaultSize))    : defaultSize;
		final color   = opts?.color   != null ? Std.int(_f(opts.color,   defaultColor))   : defaultColor;
		final bgColor = opts?.bgColor != null ? Std.int(_f(opts.bgColor, defaultBgColor)) : defaultBgColor;
		final bgAlpha = opts?.bgAlpha != null ? _f(opts.bgAlpha, defaultBgAlpha)          : defaultBgAlpha;
		final align   = opts?.align   != null ? Std.string(opts.align)                    : defaultAlign;
		final fadeIn  = opts?.fadeIn  != null ? _f(opts.fadeIn,  defaultFadeIn)            : defaultFadeIn;
		final fadeOut = opts?.fadeOut != null ? _f(opts.fadeOut, defaultFadeOut)           : defaultFadeOut;
		final bold    = opts?.bold    != null ? (opts.bold == true)                        : defaultBold;
		final font    = opts?.font    != null ? Std.string(opts.font)                      : defaultFont;
		final userY   = opts?.y       != null ? _f(opts.y, defaultY)                       : defaultY;
		final padX    = opts?.padX    != null ? _f(opts.padX, defaultPadX)                 : defaultPadX;
		final padY    = opts?.padY    != null ? _f(opts.padY, defaultPadY)                 : defaultPadY;

		// ── Configurar FlxText ────────────────────────────────────────────────
		final fontPath = Paths.font(font);
		_text.setFormat(fontPath, size, FlxColor.fromInt(color), _textAlign(align));
		_text.bold       = bold;
		_text.fieldWidth = FlxG.width - Std.int(padX * 4);
		_text.text       = text;
		_text.setBorderStyle(
			flixel.text.FlxText.FlxTextBorderStyle.OUTLINE,
			FlxColor.BLACK, 2);

		// ── Posición ──────────────────────────────────────────────────────────
		// Forzar recálculo de height tras cambiar el texto
		_text.updateHitbox();

		final bgW  = Std.int(_text.width  + padX * 2);
		final bgH  = Std.int(_text.height + padY * 2);

		// userY == -2 → centrado vertical
		final bgY:Float = if (userY == -2)
			(FlxG.height - bgH) * 0.5;
		else if (userY >= 0)
			userY;
		else
			FlxG.height - bgH - 20;

		final bgX  = switch (align)
		{
			case 'left':  Std.int(padX);
			case 'right': Std.int(FlxG.width - bgW - padX);
			default:      Std.int((FlxG.width - bgW) * 0.5);
		};

		_bg.makeGraphic(bgW, bgH, FlxColor.fromInt(bgColor));
		_bg.setPosition(bgX, bgY);
		_text.setPosition(bgX + padX, bgY + padY);

		// ── Alpha inicial a 0 ─────────────────────────────────────────────────
		_bg.alpha   = 0;
		_text.alpha = 0;

		// ── Añadir al estado / cámara ─────────────────────────────────────────
		_mountSprites();

		// ── Fade in ───────────────────────────────────────────────────────────
		_playing = true;
		_fadeActive = true;
		if (fadeIn > 0)
		{
			FlxTween.tween(_bg,   {alpha: bgAlpha}, fadeIn, {ease: FlxEase.quadOut});
			FlxTween.tween(_text, {alpha: 1},        fadeIn, {ease: FlxEase.quadOut,
				onComplete: function(_) { _fadeActive = false; }});
		}
		else
		{
			_bg.alpha   = bgAlpha;
			_text.alpha = 1;
			_fadeActive = false;
		}

		// ── Auto-hide ─────────────────────────────────────────────────────────
		if (duration > 0)
		{
			_autoTimer = new FlxTimer().start(duration, function(_) {
				_autoTimer = null;
				_startFadeOut(fadeOut, function() {
					_removeSprites();
					_playing = false;
					_playNext();
				});
			});
		}
	}

	function _playNext():Void
	{
		if (_queue.length == 0) { _playing = false; return; }
		final e = _queue.shift();
		_doShow(e.text, e.duration, e.options);
	}

	// ── Fade out helper ────────────────────────────────────────────────────────

	function _startFadeOut(duration:Float, onDone:Void->Void):Void
	{
		_fadeActive = true;
		if (duration > 0)
		{
			FlxTween.cancelTweensOf(_bg);
			FlxTween.cancelTweensOf(_text);
			FlxTween.tween(_bg,   {alpha: 0}, duration, {ease: FlxEase.quadIn});
			FlxTween.tween(_text, {alpha: 0}, duration, {ease: FlxEase.quadIn,
				onComplete: function(_) {
					_fadeActive = false;
					onDone();
				}});
		}
		else
		{
			_bg.alpha   = 0;
			_text.alpha = 0;
			_fadeActive = false;
			onDone();
		}
	}

	// ── Montaje de sprites en el estado / cámara ──────────────────────────────

	function _mountSprites():Void
	{
		final state = FlxG.state;

		if (_attachedState != null)
		{
			try { _attachedState.remove(_bg,   false); } catch(_) {}  // false = no destruir
			try { _attachedState.remove(_text, false); } catch(_) {}
			_attachedState = null;
		}

		_attachedState = state;
		state.add(_bg);
		state.add(_text);

		// Asignar cámara: preferir camHUD del PlayState
		final cam = _resolveCamera();
		_bg.cameras   = [cam];
		_text.cameras = [cam];
	}

	/**
	 * Refreshes the camera assigned to the active subtitle sprites.
	 * Called by PlayState.postCreate() once camHUD already exists,
	 * correcting the case where show() was called from onCreate()
	 * before setupCameras() had created camHUD.
	 */
	public function refreshCamera():Void
	{
		if (_bg == null || (_bg.alpha <= 0 && _text.alpha <= 0)) return;
		final cam = _resolveCamera();
		_bg.cameras   = [cam];
		_text.cameras = [cam];
		if (_attachedState != null && _attachedState != FlxG.state)
			_mountSprites();
	}

	function _removeSprites():Void
	{
		if (_attachedState != null)
		{
			try { _attachedState.remove(_bg,   true); } catch(_) {}
			try { _attachedState.remove(_text, true); } catch(_) {}
		}
		_attachedState = null;
	}

	function _resolveCamera():flixel.FlxCamera
	{
		final ps = funkin.gameplay.PlayState.instance;
		if (ps != null)
		{
			final subtitleCam:Dynamic = Reflect.field(ps, 'camSubtitles');
			if (subtitleCam != null) return cast subtitleCam;
			final hudCam:Dynamic = Reflect.field(ps, 'camHUD');
			if (hudCam != null) return cast hudCam;
		}
		// 2. Múltiples cámaras → última (habitualmente la de UI)
		final cams = FlxG.cameras.list;
		if (cams.length > 1) return cams[cams.length - 1];
		// 3. Cámara por defecto
		return FlxG.camera;
	}

	// ── Cancelaciones ─────────────────────────────────────────────────────────

	function _cancelTimer():Void
	{
		if (_autoTimer != null) { _autoTimer.cancel(); _autoTimer = null; }
	}

	function _cancelFade():Void
	{
		FlxTween.cancelTweensOf(_bg);
		FlxTween.cancelTweensOf(_text);
		_fadeActive = false;
	}

	// ── Helpers estáticos ─────────────────────────────────────────────────────

	static inline function _f(v:Dynamic, def:Float):Float
	{
		if (v == null) return def;
		final f = Std.parseFloat(Std.string(v));
		return Math.isNaN(f) ? def : f;
	}

	static function _textAlign(s:String):FlxTextAlign
	{
		return switch (s?.toLowerCase() ?? 'center')
		{
			case 'left':    LEFT;
			case 'right':   RIGHT;
			case 'justify': JUSTIFY;
			default:        CENTER;
		};
	}

	/**
	 * Parsea el formato extendido de value1 para eventos:
	 * "texto|size|color|bgAlpha"  →  devuelve { text, options }
	 */
	public static function parseEventValue(value1:String, value2:String):{ text:String, duration:Float, options:Dynamic }
	{
		final parts   = value1.split('|');
		final text    = parts[0];
		final dur     = value2 != '' ? (_f(value2, 3.0)) : 3.0;
		var   options:Dynamic = null;

		if (parts.length > 1)
		{
			options = {};
			if (parts.length >= 2 && parts[1] != '') options.size    = Std.parseInt(parts[1]);
			if (parts.length >= 3 && parts[2] != '') options.color   = Std.parseInt(parts[2]);
			if (parts.length >= 4 && parts[3] != '') options.bgAlpha = _f(parts[3], 0.6);
		}

		return { text: text, duration: dur, options: options };
	}
}

// ── Tipo interno de entrada de cola ──────────────────────────────────────────

private typedef _QueueEntry =
{
	var text:String;
	var duration:Float;
	var ?options:Dynamic;
}


