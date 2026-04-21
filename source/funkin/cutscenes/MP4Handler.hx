package funkin.cutscenes;

import funkin.states.LoadingState;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.util.FlxTimer;
import openfl.display.Shape;
import openfl.events.Event;

using StringTools;

// =============================================================================
//  NATIVE CPP — hxvlc.flixel.FlxVideo  (desktop + Android + iOS)
//
//  API real de hxvlc 2.x:
//    • hxvlc.flixel.FlxVideo   — Bitmap-based, se añade al stage con addChildBelowMouse
//    • Callbacks son signals:  onEndReached.add() / onEncounteredError.add()
//    • onFormatSetup.add()     — resolución lista, aquí se dimensiona y se quita el cover
//    • load(path) + play()     — en dos pasos, con pequeño timer entre ellos
//    • volume                  — Int 0-200 (100 = normal, 200 = boost)
//    • width/height            — read-only en Bitmap, se ajustan via scaleX/scaleY
// =============================================================================
#if cpp
import hxvlc.flixel.FlxVideo;
import openfl.filters.BitmapFilter;

class MP4Handler
{
	public var finishCallback:Null<Void->Void>;
	public var stateCallback:Null<FlxState>;

	public var bitmap:Dynamic         = null; // compatibilidad legacy
	public var sprite:Null<FlxSprite> = null;

	/**
	 * Tiempo actual de reproducción del video en milisegundos.
	 * Devuelve -1 si no hay video activo.
	 */
	public var currentTimeMs(get, never):Int;
	function get_currentTimeMs():Int
	{
		if (_video == null || _killed) return -1;
		try return haxe.Int64.toInt(_video.time) catch (_:Dynamic) return -1;
	}

	/**
	 * Callback llamado cada ENTER_FRAME con el tiempo actual en ms.
	 * Úsalo para sincronizar subtítulos SRT sin necesitar subclasificar.
	 *
	 *   handler.onTick = function(ms:Int) { trace(ms); };
	 */
	public var onTick:Null<Int->Void> = null;

	var _video:Null<FlxVideo>;
	var _cover:Null<Shape>;
	var _killed:Bool = false;
	var _filters:Array<BitmapFilter> = [];

	// Deferred fps restore.
	var _bootFrames:Int = 0;
	var _bootSavedFps:Int = 0;

	// Volume throttle: solo sincronizamos con libvlc cuando el valor cambia.
	var _lastVolume:Int = -1;

	public function new() {}

	// ── Playback ──────────────────────────────────────────────────────────────

	public function playMP4(path:String, ?midSong:Bool = false, ?repeat:Bool = false,
	                        ?outputTo:Null<FlxSprite> = null, ?isWindow:Bool = false,
	                        ?isFullscreen:Bool = false):Void
	{
		_killed     = false;
		_filters    = [];
		_lastVolume = -1;

		if (!midSong && FlxG.sound.music != null)
			FlxG.sound.music.stop();

		// FIX SampleDataEvent crash (OpenFL 9.3.0): lower fps briefly so the audio
		// backend initialises its buffer with ≥ 2048 samples.
		// SOLO necesario cuando se detiene la música (midSong=false) en modo
		// pantalla completa, porque es cuando OpenFL reinicializa su backend de
		// audio. En modo sprite (outputTo != null) no se toca el backend de OpenFL
		// así que saltamos el throttle entero → la carga es ~300 ms más rápida.
		final needsFpsThrottle = (outputTo == null && !midSong);
		if (needsFpsThrottle)
		{
			_bootSavedFps = FlxG.save.data.fpsTarget != null ? Std.int(FlxG.save.data.fpsTarget) : 60;
			final safeFps:Int = Std.int(Math.floor(funkin.audio.AudioConfig.frequency / 2048));
			final main = cast(openfl.Lib.current.getChildAt(0), Main);
			if (main != null) main.setMaxFps(safeFps);
			#if lime
			final _limeWin = lime.app.Application.current?.window;
			if (_limeWin != null) _limeWin.frameRate = safeFps;
			#end
			_bootFrames = 4;
		}

		// Cover negro mientras el decoder arranca — solo en modo pantalla completa.
		// En modo sprite (outputTo != null) el cover no tiene sentido y es lo que
		// causaba el cuadrado negro tapando el menú entero.
		if (outputTo == null)
		{
			_cover = new Shape();
			_cover.graphics.beginFill(0x000000);
			_cover.graphics.drawRect(0, 0, FlxG.stage.stageWidth, FlxG.stage.stageHeight);
			_cover.graphics.endFill();
			try FlxG.addChildBelowMouse(_cover) catch (_:Dynamic) {}
		}

		// ── FlxVideo ──────────────────────────────────────────────────────────
		_video = new FlxVideo();

		sprite = outputTo;

		// onFormatSetup — resolución lista, dimensionar el video
		_video.onFormatSetup.add(function()
		{
			if (_video == null || _killed) return;

			final sw:Float    = FlxG.stage.stageWidth;
			final sh:Float    = FlxG.stage.stageHeight;
			final ratio:Float = 16.0 / 9.0;
			final vw:Float    = (sw / sh > ratio) ? sh * ratio : sw;
			final vh:Float    = (sw / sh > ratio) ? sh          : sw / ratio;

			// FlxVideo extiende Bitmap — width/height son read-only.
			// Usar scaleX/scaleY para dimensionar.
			if (_video.bitmapData != null && _video.bitmapData.width > 0)
			{
				_video.scaleX = vw / _video.bitmapData.width;
				_video.scaleY = vh / _video.bitmapData.height;
			}
			_video.x = (sw - vw) / 2;
			_video.y = (sh - vh) / 2;

			// Si se usa como outputTo, hacer el loadGraphic inicial una sola vez.
			// Usamos fromBitmapData con unique=false para compartir la referencia
			// in-place que hxvlc actualiza cada frame (el dirty en _update hará el resto).
			if (sprite != null && _video.bitmapData != null)
				try sprite.loadGraphic(flixel.graphics.FlxGraphic.fromBitmapData(_video.bitmapData, false, null, false)) catch (_:Dynamic) {}

			// Quitar cover — en hxvlc el primer frame ya está renderizado en onFormatSetup
			_removeCover();

			// Aplicar filtros pendientes
			if (_filters.length > 0)
				try _video.filters = _filters.copy() catch (_:Dynamic) {}

			_syncVolume();
		});

		// onEndReached — fin del video
		_video.onEndReached.add(function()
		{
			if (!_killed) _finish();
		});

		// onEncounteredError — tratar como fin, el juego nunca se queda colgado
		_video.onEncounteredError.add(function(msg:String)
		{
			trace('[MP4Handler] hxvlc error — ' + msg);
			if (!_killed) _finish();
		});

		// Sincronizar volumen cada frame
		FlxG.stage.addEventListener(Event.ENTER_FRAME, _update);

		// Si es outputTo, no añadir al stage (renderizar en el sprite)
		if (outputTo == null)
			try FlxG.addChildBelowMouse(_video) catch (_:Dynamic) {}

		// Cargar y reproducir.
		// En modo pantalla completa esperamos un tick para que el cambio de FPS
		// esté activo antes de que hxvlc registre su SampleDataEvent listener.
		// En modo sprite no hubo cambio de FPS, así que cargamos directo.
		if (outputTo != null)
		{
			// Modo sprite: sin throttle, sin espera — carga inmediata.
			if (_video != null && !_killed && _video.load(path))
				new FlxTimer().start(0.001, function(_) { if (_video != null && !_killed) _video.play(); });
			else if (_video != null)
			{
				trace('[MP4Handler] hxvlc: no se pudo cargar "$path"');
				_finish();
			}
		}
		else
		{
			// Modo pantalla completa: esperamos a que el FPS bajo esté activo.
			new FlxTimer().start(0.1, function(_)
			{
				if (_video == null || _killed) return;
				if (_video.load(path))
					new FlxTimer().start(0.001, function(_) { if (_video != null && !_killed) _video.play(); });
				else
				{
					trace('[MP4Handler] hxvlc: no se pudo cargar "$path"');
					_finish();
				}
			});
		}
	}

	// ── Shader / Filter API ───────────────────────────────────────────────────

	public function applyFilter(filter:BitmapFilter):Void
	{
		if (filter == null) return;
		_filters.push(filter);
		if (_video != null) try _video.filters = _filters.copy() catch (_:Dynamic) {}
	}

	public function removeFilter(filter:BitmapFilter):Void
	{
		_filters.remove(filter);
		if (_video != null) try _video.filters = _filters.copy() catch (_:Dynamic) {}
	}

	public function clearFilters():Void
	{
		_filters = [];
		if (_video != null) try _video.filters = [] catch (_:Dynamic) {}
	}

	// ── Controls ──────────────────────────────────────────────────────────────

	public function kill():Void
	{
		if (_killed) return;
		_killed = true;

		FlxG.stage.removeEventListener(Event.ENTER_FRAME, _update);
		_removeCover();
		_stopAndDispose();
		_restoreFrameRate();

		if (finishCallback != null)
		{
			final cb = finishCallback;
			finishCallback = null;
			cb();
		}
	}

	public function pause():Void
	{
		if (_video == null) return;
		// Just pause playback. The video bitmap stays in its current position in
		// the display list so it remains visible behind the pause-menu overlay.
		try _video.pause() catch (_:Dynamic) {}
	}

	public function resume():Void
	{
		if (_video == null) return;
		// Video never moved, nothing to reorder. Just resume playback.
		try _video.resume() catch (_:Dynamic) {}
		_syncVolume();
	}

	// ── Internals ─────────────────────────────────────────────────────────────

	function _update(_:Event):Void
	{
		// Deferred fps restore: once the audio backend has fired its first
		// SampleDataEvent (after a few frames), we can go back to the target fps.
		if (_bootFrames > 0)
		{
			_bootFrames--;
			if (_bootFrames == 0)
				_restoreFrameRate();
		}

		_syncVolume();

		// Refrescar el sprite si se usa como outputTo.
		// hxvlc actualiza el bitmapData in-place cada frame, así que NO hay que
		// llamar loadGraphic() cada tick (crea FlxGraphic nuevos innecesariamente).
		// Solo marcamos dirty para que Flixel reenvíe la textura a la GPU.
		if (sprite != null && _video != null && _video.bitmapData != null)
			sprite.dirty = true;

		// Notificar tiempo actual a listeners externos (p.ej. SRT player)
		if (onTick != null && _video != null)
			try onTick(haxe.Int64.toInt(_video.time)) catch (_:Dynamic) {}
	}

	function _syncVolume():Void
	{
		if (_video == null) return;
		// hxvlc volume: 0-200 (100 = nivel normal).
		// Solo llamamos al setter nativo cuando el valor realmente cambió
		// (evita un call nativo innecesario a libvlc 60 veces por segundo).
		final vol:Int = Std.int((FlxG.sound.muted ? 0.0 : FlxG.sound.volume) * 100);
		if (vol == _lastVolume) return;
		_lastVolume = vol;
		try _video.volume = vol catch (_:Dynamic) {}
	}

	function _finish():Void
	{
		if (_killed) return;
		_killed = true;

		FlxG.stage.removeEventListener(Event.ENTER_FRAME, _update);

		new FlxTimer().start(0.1, function(_)
		{
			_removeCover();
			_stopAndDispose();
			_restoreFrameRate();

			if (finishCallback != null)
			{
				final cb = finishCallback;
				finishCallback = null;
				cb();
			}
			else if (stateCallback != null)
				LoadingState.loadAndSwitchState(stateCallback);
		});
	}

	function _removeCover():Void
	{
		if (_cover == null) return;
		try FlxG.removeChild(_cover) catch (_:Dynamic) {}
		_cover = null;
	}

	function _stopAndDispose():Void
	{
		if (_video == null) return;
		try FlxG.removeChild(_video) catch (_:Dynamic) {}
		try _video.stop()    catch (_:Dynamic) {}
		try _video.dispose() catch (_:Dynamic) {}
		_video  = null;
		sprite  = null;
		bitmap  = null;
	}

	/** Restaura el FPS al valor previo al video via Main.setMaxFps(). */
	function _restoreFrameRate():Void
	{
		// Only restore if there's a saved value (avoids double-restore).
		if (_bootSavedFps <= 0) return;
		var main = cast(openfl.Lib.current.getChildAt(0), Main);
		if (main != null) main.setMaxFps(_bootSavedFps);
		#if lime
		final _limeWin = lime.app.Application.current?.window;
		if (_limeWin != null) _limeWin.frameRate = _bootSavedFps;
		#end
		_bootSavedFps = 0;
		_bootFrames   = 0;
	}
}

// =============================================================================
//  STUB — HTML5 y plataformas sin hxvlc.
// =============================================================================
#else

class MP4Handler
{
	public var finishCallback:Null<Void->Void>;
	public var stateCallback:Null<FlxState>;
	public var bitmap:Dynamic = null;
	public var sprite:Dynamic = null;

	public var currentTimeMs(get, never):Int;
	function get_currentTimeMs():Int return -1;
	public var onTick:Null<Int->Void> = null;

	public function new() {}

	public function playMP4(path:String, ?midSong:Bool = false, ?repeat:Bool = false,
	                        ?outputTo:Dynamic = null, ?isWindow:Bool = false,
	                        ?isFullscreen:Bool = false):Void
	{
		trace("MP4Handler: hxvlc no disponible en esta plataforma.");
		_skip();
	}

	public function applyFilter(_:Dynamic):Void  {}
	public function removeFilter(_:Dynamic):Void {}
	public function clearFilters():Void          {}
	public function kill():Void                  { _skip(); }
	public function pause():Void                 {}
	public function resume():Void                {}

	inline function _skip():Void
	{
		if (finishCallback != null) { final cb = finishCallback; finishCallback = null; cb(); }
		else if (stateCallback != null) funkin.states.LoadingState.loadAndSwitchState(stateCallback);
	}
}

#end
