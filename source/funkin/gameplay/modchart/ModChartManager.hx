package funkin.gameplay.modchart;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import funkin.gameplay.objects.StrumsGroup;
import funkin.gameplay.notes.StrumNote;
import funkin.gameplay.modchart.ModChartEvent;
import haxe.Json;
import lime.app.Application;

using StringTools;

#if (LUA_ALLOWED && linc_luajit)
import llua.Lua;
import llua.LuaL;
import llua.State;
#end

// ─── Estado interno por strum ─────────────────────────────────────────────────

typedef StrumState =
{
	var baseX:Float;
	var baseY:Float;
	var offsetX:Float;
	var offsetY:Float;
	var absX:Null<Float>;
	var absY:Null<Float>;
	var angle:Float;
	var spinRate:Float;
	var alpha:Float;
	var scaleX:Float;
	var scaleY:Float;
	var visible:Bool;
	var baseVisible:Bool;
	var drunkX:Float;
	var drunkY:Float;
	var drunkFreq:Float;
	var tornado:Float;
	var confusion:Float;
	var scrollMult:Float;
	var flipX:Float;
	var noteOffsetX:Float;
	var noteOffsetY:Float;
	var bumpy:Float;
	var bumpySpeed:Float;
	var tipsy:Float;
	var tipsySpeed:Float;
	var invert:Float;
	var zigzag:Float;
	var zigzagFreq:Float;
	var wave:Float;
	var waveSpeed:Float;
	var beatScale:Float;
	var _beatPulse:Float;
	var stealth:Float;
	var noteAlpha:Float;
}

// ─── Contexto de posición de nota (hook onNotePosition) ──────────────────────

/**
 * Objeto pasado a onNotePosition() en cada frame por nota.
 * El script modifica x/y/angle/alpha/scaleY; el engine los aplica después.
 *
 * ⚠️  El objeto SE REUTILIZA entre frames. No guardar referencias a él.
 *
 * Uso en HScript:
 *   function onNotePosition(ctx) {
 *       ctx.x += Math.sin(ctx.strumTime * 0.01) * 80;
 *       ctx.y += Math.cos(ctx.songPosition * 0.002) * 30;
 *   }
 *
 * Uso en Lua:
 *   function onNotePosition(ctx)
 *       ctx.x = ctx.x + math.sin(ctx.strumTime * 0.01) * 80
 *       ctx.angle = ctx.angle + math.sin(ctx.beat * math.pi) * 15
 *   end
 */
typedef NotePositionContext =
{
	/** Dirección 0-3 (izq/abajo/arriba/der) */
	var noteData:Int;
	/** Tiempo de la nota en ms desde el inicio de la canción */
	var strumTime:Float;
	/** Posición actual de la canción en ms */
	var songPosition:Float;
	/** Beat actual (songPosition / crochet) */
	var beat:Float;
	/** true = nota del jugador, false = CPU */
	var isPlayer:Bool;
	/** true = pieza de hold/sustain, false = nota normal */
	var isSustain:Bool;
	/** ID del grupo de strums al que pertenece la nota (ej. "bf", "dad") */
	var groupId:String;
	/** Multiplicador de velocidad de scroll efectivo */
	var scrollMult:Float;
	// ── Valores modificables ──────────────────────────────────────────────────
	/** Posición X en píxeles — MODIFICAR para mover la nota horizontalmente */
	var x:Float;
	/** Posición Y en píxeles — MODIFICAR para mover la nota verticalmente */
	var y:Float;
	/** Rotación en grados — MODIFICAR para rotar la nota */
	var angle:Float;
	/** Transparencia 0.0-1.0 — MODIFICAR para cambiar alpha */
	var alpha:Float;
	/** Escala Y del sustain (solo sustains) — MODIFICAR para cambiar longitud */
	var scaleY:Float;
	/**
	 * Flip horizontal — MODIFICAR para cambiar el espejo X de la nota.
	 * ⚠️  Sustains: ignorado en body pieces; solo afecta al tail cap.
	 *     El flipX del body siempre es false (la dirección visual la gestiona el ángulo).
	 */
	var flipX:Bool;
	/**
	 * Flip vertical — MODIFICAR para cambiar el espejo Y de la nota.
	 * ⚠️  Sustains: solo el tail cap usa flipY (para apuntar hacia el strum en downscroll/invert).
	 *     El body piece nunca necesita flipY (textura repetitiva simétrica).
	 */
	var flipY:Bool;
}

// ─── Estado de cámara ─────────────────────────────────────────────────────────

typedef CameraModState =
{
	var zoom:Float;
	var offsetX:Float;
	var offsetY:Float;
	var angle:Float;
}

// ─── Estado de ventana OS ─────────────────────────────────────────────────────

/**
 * Todos los parámetros que controlan la ventana del OS.
 * El motor calcula la posición/escala/opacidad final cada frame
 * combinando todos los modificadores activos.
 */
typedef WindowModState =
{
	// Base — offset directo desde la posición inicial de la ventana
	var offsetX:Float;
	var offsetY:Float;
	// Escala de la ventana (multiplicadores, 1.0 = normal)
	var scaleX:Float;
	var scaleY:Float;
	// Opacidad (0-1)
	var alpha:Float;

	// Órbita circular/elíptica
	var orbit:Float; // radio
	var orbitSpeed:Float; // beats/rev
	var orbitPhase:Float; // offset turns
	var orbitEX:Float; // stretch X
	var orbitEY:Float; // stretch Y

	// Vibración aleatoria determinista
	var shake:Float; // amplitud px
	var shakeSpeed:Float; // velocidad

	// Rebote de resorte
	var bounce:Float; // amplitud px
	var bounceFreq:Float;
	var bouncePeriod:Float; // beats

	// Espiral arquimediana
	var spiral:Float; // radio max
	var spiralSpeed:Float;
	var spiralTight:Float; // curvas

	// Lemniscata (figura-8)
	var figure8:Float; // amplitud
	var figure8Speed:Float;

	// Glitch (teletransporte rápido)
	var glitch:Float; // amplitud
	var glitchRate:Float;

	// Warp (snap aleatorio)
	var warp:Float; // distancia
	var warpPeriod:Float; // beats
	var _warpX:Float; // estado interno
	var _warpY:Float;
	var _warpCycle:Int;

	// Péndulo
	var swing:Float;
	var swingSpeed:Float;

	// Onda triangular
	var winZigzag:Float;
	var zigzagSpeed:Float;

	// Pinball
	var pinball:Float; // velocidad px/beat
	var pinballAngle:Float; // grados

	// Roll
	var roll:Float;
	var rollSpeed:Float;

	// Pulso de escala en beat
	var beatScale:Float;
	var _beatPulse:Float;

	// Pulso cardíaco
	var heartbeat:Float;

	// Strobe
	var strobe:Float;
	var strobeRate:Float;
	var strobeDuty:Float;

	// Anclaje a esquina de pantalla
	var anchor:Float; // blend 0-1
	var anchorX:Float; // -1/0/1
	var anchorY:Float;
	var anchorMX:Float; // margen px
	var anchorMY:Float;
}

// ─── Tween activo ────────────────────────────────────────────────────────────

typedef ActiveTween =
{
	var event:ModChartEvent;
	var startBeat:Float;
	var startVal:Float;
	var groupId:String;
	var strumIdx:Int;
}

// ─────────────────────────────────────────────────────────────────────────────

class ModChartManager
{
	public var data:ModChartData;

	private var strumsGroups:Array<StrumsGroup>;
	private var states:Map<String, Array<StrumState>> = new Map();

	/** Caché de resolución de alias → groupId real.
	 *  getState() hace un scan O(n) de strumsGroups cuando el groupId literal
	 *  ("player"/"cpu"/…) no existe como clave en `states`. Este Map guarda el
	 *  resultado para convertir ese scan en O(1) en todos los frames siguientes.
	 *  Se invalida en captureBasePositions() y replaceStrumsGroups(). */
	private var _aliasCache:Map<String, String> = new Map();

	public var camState:CameraModState = {
		zoom: 0,
		offsetX: 0,
		offsetY: 0,
		angle: 0
	};

	// ── Window state ──────────────────────────────────────────────────────────

	/**
	 * Estado completo de la ventana OS.  PlayState no necesita leer esto —
	 * el manager lo aplica directamente en applyWindowState() cada frame.
	 */
	public var winState:WindowModState;

	/** Posición base de la ventana (capturada en init, restaurada en destroy). */
	private var _winBaseX:Int = 0;

	private var _winBaseY:Int = 0;
	private var _winBaseW:Int = 0;
	private var _winBaseH:Int = 0;
	private var _winBaseAlpha:Float = 1.0;
	private var _winInitialized:Bool = false;

	/** Caché de screen size para no leer display.bounds cada frame. */
	private var _screenW:Float = 1920;

	private var _screenH:Float = 1080;

	/** Valores anteriores para evitar llamadas innecesarias a la API de Lime. */
	private var _lastWinX:Int = -9999;

	private var _lastWinY:Int = -9999;
	private var _lastWinW:Int = -9999;
	private var _lastWinH:Int = -9999;
	private var _lastWinAlpha:Float = -1;

	// ── Eventos / tweens ──────────────────────────────────────────────────────
	private var pending:Array<ModChartEvent> = [];
	private var _pendingIdx:Int = 0;
	private var activeTweens:Array<ActiveTween> = [];
	private var _finishedTweens:Array<ActiveTween> = [];

	/** Beat actual — público para que NoteManager pueda leerlo en el hook de posición. */
	public var currentBeat:Float = 0;
	private var songPosition:Float = 0;

	private var _winWasModifiedByModchart:Bool = false;

	public var enabled:Bool = true;

	// ── Hook de posición de notas ─────────────────────────────────────────────

	/**
	 * Contexto preallocado para onNotePosition.
	 * Reutilizado cada frame por nota → cero allocations en el path caliente.
	 */
	public var noteCtx:NotePositionContext = {
		noteData: 0, strumTime: 0.0, songPosition: 0.0, beat: 0.0,
		isPlayer: true, isSustain: false, groupId: '',
		scrollMult: 1.0, x: 0.0, y: 0.0, angle: 0.0, alpha: 1.0, scaleY: 1.0,
		flipX: false, flipY: false
	};

	/**
	 * true si algún script cargado define onNotePosition.
	 * NoteManager lo comprueba antes de llamar al hook para evitar overhead
	 * cuando ningún script usa esta característica.
	 */
	public var hasNotePositionHook:Bool = false;

	/**
	 * Llama a onNotePosition() en todos los scripts cargados.
	 * Solo llamar si hasNotePositionHook == true.
	 */
	public inline function callNotePositionHook(ctx:NotePositionContext):Void
	{
		#if HSCRIPT_ALLOWED
		_callHScript('onNotePosition', [ctx]);
		#end
		#if (LUA_ALLOWED && linc_luajit)
		_callLua('onNotePosition', [ctx]);
		#end
	}

	public static var instance:ModChartManager = null;

	// ─────────────────────────────────────────────────────────────────────────

	public function new(strumsGroups:Array<StrumsGroup>)
	{
		instance = this;
		this.strumsGroups = strumsGroups;

		data = {
			name: "New ModChart",
			song: "",
			version: "1.0",
			events: []
		};

		winState = _makeDefaultWinState();
		_initWindow();

		captureBasePositions();
		trace('[ModChartManager] Init con ${strumsGroups.length} grupos de strums');
	}

	// ── Window init / destroy ─────────────────────────────────────────────────

	private function _initWindow():Void
	{
		#if (!html5 && !mobile)
		try
		{
			final win = Application.current?.window;
			if (win == null)
				return;
			_winBaseX = win.x;
			_winBaseY = win.y;
			_winBaseW = win.width;
			_winBaseH = win.height;
			_winBaseAlpha = win.opacity;

			// Capturar tamaño de pantalla
			final b = win.display?.bounds;
			if (b != null)
			{
				_screenW = b.width;
				_screenH = b.height;
			}

			_winInitialized = true;
			trace('[ModChartManager] Ventana capturada: ${_winBaseW}×${_winBaseH} @ (${_winBaseX},${_winBaseY}) pantalla ${_screenW}×${_screenH}');
		}
		catch (e:Dynamic)
		{
			trace('[ModChartManager] No se pudo capturar ventana: $e');
		}
		#end
	}

	private function _restoreWindow():Void
	{
		#if (!html5 && !mobile)
		if (!_winInitialized || !_winWasModifiedByModchart)
			return;
		try
		{
			final win = Application.current?.window;
			if (win == null)
				return;
			win.move(_winBaseX, _winBaseY);
			win.resize(_winBaseW, _winBaseH);
			win.opacity = _winBaseAlpha;
		}
		catch (_:Dynamic)
		{
		}
		#end
	}

	private function _makeDefaultWinState():WindowModState
	{
		return {
			offsetX: 0,
			offsetY: 0,
			scaleX: 1,
			scaleY: 1,
			alpha: 1,
			orbit: 0,
			orbitSpeed: 4,
			orbitPhase: 0,
			orbitEX: 1,
			orbitEY: 1,
			shake: 0,
			shakeSpeed: 8,
			bounce: 0,
			bounceFreq: 6,
			bouncePeriod: 1,
			spiral: 0,
			spiralSpeed: 4,
			spiralTight: 2,
			figure8: 0,
			figure8Speed: 8,
			glitch: 0,
			glitchRate: 4,
			warp: 0,
			warpPeriod: 1,
			_warpX: 0,
			_warpY: 0,
			_warpCycle: -1,
			swing: 0,
			swingSpeed: 2,
			winZigzag: 0,
			zigzagSpeed: 2,
			pinball: 0,
			pinballAngle: 45,
			roll: 0,
			rollSpeed: 4,
			beatScale: 0,
			_beatPulse: 0,
			heartbeat: 0,
			strobe: 0,
			strobeRate: 4,
			strobeDuty: 0.5,
			anchor: 0,
			anchorX: 1,
			anchorY: -1,
			anchorMX: 20,
			anchorMY: 20
		};
	}

	// ── Aplicar estado de ventana al OS ───────────────────────────────────────

	private function applyWindowState(beat:Float):Void
	{
		#if (html5 || mobile)
		return;
		#end

		if (!_winInitialized || !_winWasModifiedByModchart)
			return;

		final ws = winState;

		// ── Calcular offsets acumulados ───────────────────────────────────────
		var dx:Float = ws.offsetX;
		var dy:Float = ws.offsetY;
		var sx:Float = ws.scaleX;
		var sy:Float = ws.scaleY;
		var al:Float = ws.alpha;

		// Órbita
		if (ws.orbit != 0)
		{
			final spd = ws.orbitSpeed == 0 ? 0.001 : ws.orbitSpeed;
			final angle = ((beat / spd) + ws.orbitPhase) * Math.PI * 2;
			dx += Math.cos(angle) * ws.orbit * ws.orbitEX;
			dy += Math.sin(angle) * ws.orbit * ws.orbitEY;
		}

		// Shake
		if (ws.shake != 0)
		{
			final t = beat * ws.shakeSpeed;
			dx += _hash(t, 42) * ws.shake;
			dy += _hash(t + 100, 77) * ws.shake;
		}

		// Bounce
		if (ws.bounce != 0)
		{
			final period = ws.bouncePeriod == 0 ? 1 : ws.bouncePeriod;
			final tY = beat % period;
			dy += ws.bounce * Math.exp(-ws.bounceFreq * 0.5 * tY) * Math.sin(ws.bounceFreq * tY * Math.PI * 2);
		}

		// Espiral
		if (ws.spiral != 0)
		{
			final spd = ws.spiralSpeed == 0 ? 0.001 : ws.spiralSpeed;
			final tight = ws.spiralTight == 0 ? 1 : ws.spiralTight;
			final angle = (beat / spd) * Math.PI * 2;
			final t = (angle / (Math.PI * 2 * tight)) % 1.0;
			final r = ws.spiral * t;
			dx += Math.cos(angle) * r;
			dy += Math.sin(angle) * r;
		}

		// Figura-8
		if (ws.figure8 != 0)
		{
			final spd = ws.figure8Speed == 0 ? 0.001 : ws.figure8Speed;
			final t = (beat / spd) * Math.PI * 2;
			final denom = 1 + Math.sin(t) * Math.sin(t);
			dx += ws.figure8 * Math.cos(t) / denom;
			dy += ws.figure8 * Math.sin(t) * Math.cos(t) / denom * 0.5;
		}

		// Glitch
		if (ws.glitch != 0)
		{
			final rate = ws.glitchRate == 0 ? 0.001 : ws.glitchRate;
			final tc = beat * rate;
			final cycle = Math.floor(tc);
			final frac = tc - cycle;
			if (frac < 0.3)
			{
				dx += _hash(cycle, 13) * ws.glitch;
				dy += _hash(cycle, 99) * ws.glitch;
			}
		}

		// Warp
		if (ws.warp != 0)
		{
			final period = ws.warpPeriod == 0 ? 1 : ws.warpPeriod;
			final cycle = Std.int(beat / period);
			if (cycle != ws._warpCycle)
			{
				ws._warpCycle = cycle;
				ws._warpX = _hash01(cycle, 7) * ws.warp;
				ws._warpY = _hash01(cycle, 31) * ws.warp;
			}
			dx += ws._warpX;
			dy += ws._warpY;
		}

		// Swing (péndulo)
		if (ws.swing != 0)
		{
			final spd = ws.swingSpeed == 0 ? 0.001 : ws.swingSpeed;
			final t = (beat / spd) * Math.PI * 2;
			dx += Math.sin(t) * ws.swing + Math.sin(3 * t) * ws.swing * 0.25 * 0.3;
		}

		// Zigzag (onda triangular)
		if (ws.winZigzag != 0)
		{
			final spd = ws.zigzagSpeed == 0 ? 0.001 : ws.zigzagSpeed;
			final t = (beat / spd) % 1.0;
			final w = t < 0.5 ? t * 4 - 1 : 3 - t * 4; // triángulo [-1,1]
			dx += w * ws.winZigzag;
		}

		// Pinball (rebota en bordes del monitor)
		if (ws.pinball != 0)
		{
			final maxX = _screenW - _winBaseW;
			final maxY = _screenH - _winBaseH;
			if (maxX > 0 && maxY > 0)
			{
				final ang = ws.pinballAngle * Math.PI / 180;
				final px = Math.cos(ang) * ws.pinball * beat;
				final py = Math.sin(ang) * ws.pinball * beat;
				// Convertir a offset relativo al origen base
				dx = _bouncePinball(px, maxX) - _winBaseX;
				dy = _bouncePinball(py, maxY) - _winBaseY;
			}
		}

		// Roll (rueda rodando)
		if (ws.roll != 0)
		{
			final spd = ws.rollSpeed == 0 ? 0.001 : ws.rollSpeed;
			final norm = ((beat / spd) % 1.0);
			dx += (norm * 2 - 1) * ws.roll * 0.5;
		}

		// Beat scale
		if (ws._beatPulse > 0)
		{
			sx *= 1 + ws._beatPulse;
			sy *= 1 + ws._beatPulse;
		}

		// Heartbeat
		if (ws.heartbeat != 0)
		{
			final t = beat % 1.0;
			final p1 = Math.exp(-10 * t) * ws.heartbeat;
			final t2 = (t < 0.3) ? t + 0.7 : t - 0.3;
			final p2 = Math.exp(-10 * t2) * ws.heartbeat * 0.5;
			sx *= 1 + p1 + p2;
			sy *= 1 + p1 + p2;
		}

		// Strobe
		if (ws.strobe != 0)
		{
			final rate = ws.strobeRate == 0 ? 0.001 : ws.strobeRate;
			final t = (beat * rate) % 1.0;
			if (t > ws.strobeDuty)
				al *= 1.0 - ws.strobe;
		}

		// Anclaje a esquina de pantalla
		if (ws.anchor > 0)
		{
			final winW = Std.int(_winBaseW * sx);
			final winH = Std.int(_winBaseH * sy);
			final absX:Float = ws.anchorX <= -0.5 ? ws.anchorMX : ws.anchorX >= 0.5 ? _screenW - winW - ws.anchorMX : (_screenW - winW) * 0.5;
			final absY:Float = ws.anchorY <= -0.5 ? ws.anchorMY : ws.anchorY >= 0.5 ? _screenH - winH - ws.anchorMY : (_screenH - winH) * 0.5;
			final offX = absX - _winBaseX;
			final offY = absY - _winBaseY;
			dx = dx * (1 - ws.anchor) + offX * ws.anchor;
			dy = dy * (1 - ws.anchor) + offY * ws.anchor;
		}

		// ── Calcular posición y tamaño finales ────────────────────────────────
		sx = Math.max(0.1, sx);
		sy = Math.max(0.1, sy);
		al = Math.max(0.0, Math.min(1.0, al));

		final finalX = _winBaseX + Std.int(dx);
		final finalY = _winBaseY + Std.int(dy);
		final finalW = Std.int(_winBaseW * sx);
		final finalH = Std.int(_winBaseH * sy);

		// ── Aplicar solo si cambió ─────────────────────────────────────────────
		try
		{
			final win = Application.current?.window;
			if (win == null)
				return;

			if (finalX != _lastWinX || finalY != _lastWinY)
			{
				win.move(finalX, finalY);
				_lastWinX = finalX;
				_lastWinY = finalY;
			}
			if (finalW != _lastWinW || finalH != _lastWinH)
			{
				win.resize(finalW, finalH);
				_lastWinW = finalW;
				_lastWinH = finalH;
			}
			if (Math.abs(al - _lastWinAlpha) > 0.004)
			{
				win.opacity = al;
				_lastWinAlpha = al;
			}
		}
		catch (e:Dynamic)
		{
		}
	}

	// ── Helpers matemáticos ──────────────────────────────────────────────────

	private inline function _hash(t:Float, seed:Float):Float
	{
		final v = Math.sin(t * 127.1 + seed * 311.7) * 43758.5453;
		return (v - Math.floor(v)) * 2.0 - 1.0;
	}

	private inline function _hash01(t:Float, seed:Float):Float
	{
		final v = Math.sin(t * 127.1 + seed * 311.7) * 43758.5453;
		return (v - Math.floor(v)) * 2.0 - 1.0;
	}

	private inline function _bouncePinball(p:Float, max:Float):Float
	{
		final period = max * 2;
		final t = ((p % period) + period) % period;
		return (t > max) ? period - t : t;
	}

	// ── Leer/escribir valores del estado de ventana ───────────────────────────

	private function getWindowValue(type:ModEventType):Float
	{
		final ws = winState;
		return switch (type)
		{
			case WIN_X: ws.offsetX;
			case WIN_Y: ws.offsetY;
			case WIN_SCALE: ws.scaleX; // scaleX == scaleY en uniform
			case WIN_SCALE_X: ws.scaleX;
			case WIN_SCALE_Y: ws.scaleY;
			case WIN_ALPHA: ws.alpha;
			case WIN_ORBIT: ws.orbit;
			case WIN_ORBIT_SPEED: ws.orbitSpeed;
			case WIN_ORBIT_PHASE: ws.orbitPhase;
			case WIN_ORBIT_EX: ws.orbitEX;
			case WIN_ORBIT_EY: ws.orbitEY;
			case WIN_SHAKE: ws.shake;
			case WIN_SHAKE_SPEED: ws.shakeSpeed;
			case WIN_BOUNCE: ws.bounce;
			case WIN_BOUNCE_FREQ: ws.bounceFreq;
			case WIN_BOUNCE_PERIOD: ws.bouncePeriod;
			case WIN_SPIRAL: ws.spiral;
			case WIN_SPIRAL_SPEED: ws.spiralSpeed;
			case WIN_SPIRAL_TIGHT: ws.spiralTight;
			case WIN_FIGURE8: ws.figure8;
			case WIN_FIGURE8_SPEED: ws.figure8Speed;
			case WIN_GLITCH: ws.glitch;
			case WIN_GLITCH_RATE: ws.glitchRate;
			case WIN_WARP: ws.warp;
			case WIN_WARP_PERIOD: ws.warpPeriod;
			case WIN_SWING: ws.swing;
			case WIN_SWING_SPEED: ws.swingSpeed;
			case WIN_ZIGZAG: ws.winZigzag;
			case WIN_ZIGZAG_SPEED: ws.zigzagSpeed;
			case WIN_PINBALL: ws.pinball;
			case WIN_PINBALL_ANGLE: ws.pinballAngle;
			case WIN_ROLL: ws.roll;
			case WIN_ROLL_SPEED: ws.rollSpeed;
			case WIN_BEAT_SCALE: ws.beatScale;
			case WIN_HEARTBEAT: ws.heartbeat;
			case WIN_STROBE: ws.strobe;
			case WIN_STROBE_RATE: ws.strobeRate;
			case WIN_STROBE_DUTY: ws.strobeDuty;
			case WIN_ANCHOR: ws.anchor;
			case WIN_ANCHOR_X: ws.anchorX;
			case WIN_ANCHOR_Y: ws.anchorY;
			case WIN_ANCHOR_MX: ws.anchorMX;
			case WIN_ANCHOR_MY: ws.anchorMY;
			default: 0;
		};
	}

	private function setWindowValue(type:ModEventType, value:Float):Void
	{
		final ws = winState;
		_winWasModifiedByModchart = true;
		switch (type)
		{
			case WIN_X:
				ws.offsetX = value;
			case WIN_Y:
				ws.offsetY = value;
			case WIN_SCALE:
				ws.scaleX = value;
				ws.scaleY = value;
			case WIN_SCALE_X:
				ws.scaleX = value;
			case WIN_SCALE_Y:
				ws.scaleY = value;
			case WIN_ALPHA:
				ws.alpha = value;
			case WIN_ORBIT:
				ws.orbit = value;
			case WIN_ORBIT_SPEED:
				ws.orbitSpeed = value;
			case WIN_ORBIT_PHASE:
				ws.orbitPhase = value;
			case WIN_ORBIT_EX:
				ws.orbitEX = value;
			case WIN_ORBIT_EY:
				ws.orbitEY = value;
			case WIN_SHAKE:
				ws.shake = value;
			case WIN_SHAKE_SPEED:
				ws.shakeSpeed = value;
			case WIN_BOUNCE:
				ws.bounce = value;
			case WIN_BOUNCE_FREQ:
				ws.bounceFreq = value;
			case WIN_BOUNCE_PERIOD:
				ws.bouncePeriod = value;
			case WIN_SPIRAL:
				ws.spiral = value;
			case WIN_SPIRAL_SPEED:
				ws.spiralSpeed = value;
			case WIN_SPIRAL_TIGHT:
				ws.spiralTight = value;
			case WIN_FIGURE8:
				ws.figure8 = value;
			case WIN_FIGURE8_SPEED:
				ws.figure8Speed = value;
			case WIN_GLITCH:
				ws.glitch = value;
			case WIN_GLITCH_RATE:
				ws.glitchRate = value;
			case WIN_WARP:
				ws.warp = value;
			case WIN_WARP_PERIOD:
				ws.warpPeriod = value;
			case WIN_SWING:
				ws.swing = value;
			case WIN_SWING_SPEED:
				ws.swingSpeed = value;
			case WIN_ZIGZAG:
				ws.winZigzag = value;
			case WIN_ZIGZAG_SPEED:
				ws.zigzagSpeed = value;
			case WIN_PINBALL:
				ws.pinball = value;
			case WIN_PINBALL_ANGLE:
				ws.pinballAngle = value;
			case WIN_ROLL:
				ws.roll = value;
			case WIN_ROLL_SPEED:
				ws.rollSpeed = value;
			case WIN_BEAT_SCALE:
				ws.beatScale = value;
			case WIN_HEARTBEAT:
				ws.heartbeat = value;
			case WIN_STROBE:
				ws.strobe = value;
			case WIN_STROBE_RATE:
				ws.strobeRate = value;
			case WIN_STROBE_DUTY:
				ws.strobeDuty = value;
			case WIN_ANCHOR:
				ws.anchor = value;
			case WIN_ANCHOR_X:
				ws.anchorX = value;
			case WIN_ANCHOR_Y:
				ws.anchorY = value;
			case WIN_ANCHOR_MX:
				ws.anchorMX = value;
			case WIN_ANCHOR_MY:
				ws.anchorMY = value;
			case WIN_RESET:
				winState = _makeDefaultWinState();
				_restoreWindow();
			default:
		}
	}

	// ── Captura de posiciones base ────────────────────────────────────────────

	public function replaceStrumsGroups(newGroups:Array<StrumsGroup>):Void
	{
		this.strumsGroups = newGroups;
		_aliasCache.clear(); // los grupos cambiaron → invalidar resolución de alias
		captureBasePositions();
	}

	public function captureBasePositions():Void
	{
		states.clear();
		_aliasCache.clear(); // strumsGroups cambió → alias anteriores son inválidos
		for (group in strumsGroups)
		{
			var arr:Array<StrumState> = [];
			for (i in 0...4)
			{
				var spr = group.getStrum(i);
				if (spr == null)
				{
					arr.push(makeDefaultState(0, 0));
					continue;
				}
				arr.push({
					baseX: spr.x,
					baseY: spr.y,
					offsetX: 0,
					offsetY: 0,
					absX: null,
					absY: null,
					angle: 0,
					spinRate: 0,
					alpha: 1,
					scaleX: spr.scale.x,
					scaleY: spr.scale.y,
					visible: spr.visible,
					baseVisible: spr.visible,
					drunkX: 0,
					drunkY: 0,
					drunkFreq: 1.0,
					tornado: 0,
					confusion: 0,
					scrollMult: 1.0,
					flipX: 0,
					noteOffsetX: 0,
					noteOffsetY: 0,
					bumpy: 0,
					bumpySpeed: 2.0,
					tipsy: 0,
					tipsySpeed: 1.0,
					invert: 0,
					zigzag: 0,
					zigzagFreq: 1.0,
					wave: 0,
					waveSpeed: 1.5,
					beatScale: 0,
					_beatPulse: 0,
					stealth: 0,
					noteAlpha: 1.0
				});
			}
			states.set(group.id, arr);
		}
	}

	private function makeDefaultState(bx:Float, by:Float):StrumState
	{
		return {
			baseX: bx,
			baseY: by,
			offsetX: 0,
			offsetY: 0,
			absX: null,
			absY: null,
			angle: 0,
			spinRate: 0,
			alpha: 1,
			scaleX: 0.7,
			scaleY: 0.7,
			visible: true,
			baseVisible: true,
			drunkX: 0,
			drunkY: 0,
			drunkFreq: 1.0,
			tornado: 0,
			confusion: 0,
			scrollMult: 1.0,
			flipX: 0,
			noteOffsetX: 0,
			noteOffsetY: 0,
			bumpy: 0,
			bumpySpeed: 2.0,
			tipsy: 0,
			tipsySpeed: 1.0,
			invert: 0,
			zigzag: 0,
			zigzagFreq: 1.0,
			wave: 0,
			waveSpeed: 1.5,
			beatScale: 0,
			_beatPulse: 0,
			stealth: 0,
			noteAlpha: 1.0
		};
	}

	// ─── Carga de archivos ────────────────────────────────────────────────────

	public function loadFromFile(songName:String):Bool
	{
		var song = songName.toLowerCase();
		var searchPaths:Array<String> = [];

		#if sys
		var activeMod = mods.ModManager.activeMod;
		if (activeMod != null)
		{
			searchPaths.push('${mods.ModManager.MODS_FOLDER}/$activeMod/songs/${song}/modchart.lua');
			searchPaths.push('${mods.ModManager.MODS_FOLDER}/$activeMod/songs/${song}/modchart.hx');
			searchPaths.push('${mods.ModManager.MODS_FOLDER}/$activeMod/songs/${song}/modchart.json');
		}
		for (mod in mods.ModManager.installedMods)
		{
			if (!mod.enabled || mod.id == activeMod)
				continue;
			searchPaths.push('${mods.ModManager.MODS_FOLDER}/${mod.id}/songs/${song}/modchart.lua');
			searchPaths.push('${mods.ModManager.MODS_FOLDER}/${mod.id}/songs/${song}/modchart.hx');
			searchPaths.push('${mods.ModManager.MODS_FOLDER}/${mod.id}/songs/${song}/modchart.json');
		}
		#end

		searchPaths.push('assets/songs/${song}/modchart.lua');
		searchPaths.push('assets/songs/${song}/modchart.hx');
		searchPaths.push('assets/data/modcharts/${song}.lua');
		searchPaths.push('assets/data/modcharts/${song}.hx');
		searchPaths.push('assets/songs/${song}/modchart.json');
		searchPaths.push('assets/data/modcharts/${song}.json');

		for (p in searchPaths)
		{
			#if sys
			var exists = sys.FileSystem.exists(p);
			#else
			var exists = openfl.Assets.exists(p);
			#end
			if (!exists)
				continue;

			if (p.endsWith('.lua'))
			{
				if (loadFromLua(p, songName))
					return true;
			}
			else if (p.endsWith('.hx'))
			{
				if (loadFromHScript(p, songName))
					return true;
			}
			else if (p.endsWith('.json'))
			{
				try
				{
					var txt = #if sys sys.io.File.getContent(p) #else openfl.Assets.getText(p) #end;
					var loaded:ModChartData = Json.parse(txt);
					data = loaded;
					data.events.sort((a, b) -> a.beat < b.beat ? -1 : (a.beat > b.beat ? 1 : 0));
					pending = data.events.copy();
					trace('[ModChartManager] JSON cargado desde "$p"');
					return true;
				}
				catch (e:Dynamic)
				{
					trace('[ModChartManager] ERROR JSON "$p": $e');
				}
			}
		}
		trace('[ModChartManager] No hay modchart para "$songName"');
		return false;
	}

	public function loadFromHScript(path:String, songName:String = ''):Bool
	{
		#if HSCRIPT_ALLOWED
		try
		{
			var src = #if sys sys.io.File.getContent(path) #else openfl.Assets.getText(path) #end;
			if (src == null || src.length == 0)
				return false;

			var parser = new hscript.Parser();
			parser.allowTypes = true;
			#if (hscript >= "2.5.0")
			try
			{
				parser.allowMetadata = true;
			}
			catch (_:Dynamic)
			{
			}
			#end
			var prog = parser.parseString(src);
			var interp = new hscript.Interp();

			_exposeConstantsHScript(interp);
			interp.variables.set('modChart', this);
			interp.variables.set('song', songName);
			interp.variables.set('Math', Math);
			interp.variables.set('FlxG', flixel.FlxG);
			interp.variables.set('Conductor', funkin.data.Conductor);
			interp.variables.set('noteManager', funkin.gameplay.PlayState.instance != null ? funkin.gameplay.PlayState.instance.noteManager : null);
			interp.variables.set('playState', funkin.gameplay.PlayState.instance);
			interp.variables.set('camState', camState);
			interp.variables.set('winState', winState);

			interp.execute(prog);
			_hscriptInterp = interp;

			if (interp.variables.exists('onCreate'))
				try
				{
					Reflect.callMethod(null, interp.variables.get('onCreate'), []);
				}
				catch (e:Dynamic)
				{
					trace('[ModChartManager] Error onCreate(): $e');
				}

			data.events.sort((a, b) -> a.beat < b.beat ? -1 : (a.beat > b.beat ? 1 : 0));
			pending = data.events.copy();

			// Detectar hooks opcionales
			if (interp.variables.exists('onNotePosition'))
				hasNotePositionHook = true;

			// ── Aplicar eventos en beat 0 y estado actual inmediatamente ──────
			// Esto garantiza que cualquier llamada a set() o addEventSimple(0,…)
			// dentro de onCreate() se vea YA en el primer frame de PlayState,
			// sin esperar al primer update().
			fireReadyEvents(0.0);
			applyAllStates();
			trace('[ModChartManager] HScript cargado: "$path"');
			return true;
		}
		catch (e:Dynamic)
		{
			trace('[ModChartManager] ERROR HScript: $e');
			return false;
		}
		#else
		return false;
		#end
	}

	public function loadFromLua(path:String, songName:String = ''):Bool
	{
		#if (LUA_ALLOWED && linc_luajit)
		try
		{
			#if sys
			if (!sys.FileSystem.exists(path))
				return false;
			#end

			var lua = new funkin.scripting.RuleScriptInstance('modchart_${songName}', path);
			_exposeConstantsLua(lua, songName);

			#if sys
			var src = sys.io.File.getContent(path);
			#else
			var src = openfl.Assets.getText(path);
			#end
			lua.loadString(src);

			if (!lua.active)
			{
				lua.destroy();
				return false;
			}

			_luaScript = lua;
			data.events.sort((a, b) -> a.beat < b.beat ? -1 : (a.beat > b.beat ? 1 : 0));
			pending = data.events.copy();
			// Con Lua activo habilitamos el hook: _callLua falla silenciosamente
			// si onNotePosition no está definida, así que el overhead es mínimo.
			hasNotePositionHook = true;

			// ── Aplicar beat-0 inmediatamente (igual que en HScript) ──────────
			fireReadyEvents(0.0);
			applyAllStates();
			trace('[ModChartManager] Lua cargado: "$path"');
			return true;
		}
		catch (e:Dynamic)
		{
			trace('[ModChartManager] ERROR Lua: $e');
			return false;
		}
		#else
		return false;
		#end
	}

	// ── Exposición de constantes a scripts ────────────────────────────────────
	#if HSCRIPT_ALLOWED
	private var _hscriptInterp:Null<hscript.Interp> = null;

	private function _exposeConstantsHScript(interp:hscript.Interp):Void
	{
		inline function s(k:String, v:Dynamic)
			interp.variables.set(k, v);
		// Strum
		s('MOVE_X', ModEventType.MOVE_X);
		s('MOVE_Y', ModEventType.MOVE_Y);
		s('SET_ABS_X', ModEventType.SET_ABS_X);
		s('SET_ABS_Y', ModEventType.SET_ABS_Y);
		s('ANGLE', ModEventType.ANGLE);
		s('SPIN', ModEventType.SPIN);
		s('ALPHA', ModEventType.ALPHA);
		s('SCALE', ModEventType.SCALE);
		s('SCALE_X', ModEventType.SCALE_X);
		s('SCALE_Y', ModEventType.SCALE_Y);
		s('VISIBLE', ModEventType.VISIBLE);
		s('RESET', ModEventType.RESET);
		s('DRUNK_X', ModEventType.DRUNK_X);
		s('DRUNK_Y', ModEventType.DRUNK_Y);
		s('DRUNK_FREQ', ModEventType.DRUNK_FREQ);
		s('TORNADO', ModEventType.TORNADO);
		s('CONFUSION', ModEventType.CONFUSION);
		s('SCROLL_MULT', ModEventType.SCROLL_MULT);
		s('FLIP_X', ModEventType.FLIP_X);
		s('NOTE_OFFSET_X', ModEventType.NOTE_OFFSET_X);
		s('NOTE_OFFSET_Y', ModEventType.NOTE_OFFSET_Y);
		s('BUMPY', ModEventType.BUMPY);
		s('BUMPY_SPEED', ModEventType.BUMPY_SPEED);
		s('TIPSY', ModEventType.TIPSY);
		s('TIPSY_SPEED', ModEventType.TIPSY_SPEED);
		s('INVERT', ModEventType.INVERT);
		s('ZIGZAG', ModEventType.ZIGZAG);
		s('ZIGZAG_FREQ', ModEventType.ZIGZAG_FREQ);
		s('WAVE', ModEventType.WAVE);
		s('WAVE_SPEED', ModEventType.WAVE_SPEED);
		s('BEAT_SCALE', ModEventType.BEAT_SCALE);
		s('STEALTH', ModEventType.STEALTH);
		s('NOTE_ALPHA', ModEventType.NOTE_ALPHA);
		// Camera
		s('CAM_ZOOM', ModEventType.CAM_ZOOM);
		s('CAM_MOVE_X', ModEventType.CAM_MOVE_X);
		s('CAM_MOVE_Y', ModEventType.CAM_MOVE_Y);
		s('CAM_ANGLE', ModEventType.CAM_ANGLE);
		// Window
		s('WIN_X', ModEventType.WIN_X);
		s('WIN_Y', ModEventType.WIN_Y);
		s('WIN_SCALE', ModEventType.WIN_SCALE);
		s('WIN_SCALE_X', ModEventType.WIN_SCALE_X);
		s('WIN_SCALE_Y', ModEventType.WIN_SCALE_Y);
		s('WIN_ALPHA', ModEventType.WIN_ALPHA);
		s('WIN_RESET', ModEventType.WIN_RESET);
		s('WIN_ORBIT', ModEventType.WIN_ORBIT);
		s('WIN_ORBIT_SPEED', ModEventType.WIN_ORBIT_SPEED);
		s('WIN_ORBIT_PHASE', ModEventType.WIN_ORBIT_PHASE);
		s('WIN_ORBIT_EX', ModEventType.WIN_ORBIT_EX);
		s('WIN_ORBIT_EY', ModEventType.WIN_ORBIT_EY);
		s('WIN_SHAKE', ModEventType.WIN_SHAKE);
		s('WIN_SHAKE_SPEED', ModEventType.WIN_SHAKE_SPEED);
		s('WIN_BOUNCE', ModEventType.WIN_BOUNCE);
		s('WIN_BOUNCE_FREQ', ModEventType.WIN_BOUNCE_FREQ);
		s('WIN_BOUNCE_PERIOD', ModEventType.WIN_BOUNCE_PERIOD);
		s('WIN_SPIRAL', ModEventType.WIN_SPIRAL);
		s('WIN_SPIRAL_SPEED', ModEventType.WIN_SPIRAL_SPEED);
		s('WIN_SPIRAL_TIGHT', ModEventType.WIN_SPIRAL_TIGHT);
		s('WIN_FIGURE8', ModEventType.WIN_FIGURE8);
		s('WIN_FIGURE8_SPEED', ModEventType.WIN_FIGURE8_SPEED);
		s('WIN_GLITCH', ModEventType.WIN_GLITCH);
		s('WIN_GLITCH_RATE', ModEventType.WIN_GLITCH_RATE);
		s('WIN_WARP', ModEventType.WIN_WARP);
		s('WIN_WARP_PERIOD', ModEventType.WIN_WARP_PERIOD);
		s('WIN_SWING', ModEventType.WIN_SWING);
		s('WIN_SWING_SPEED', ModEventType.WIN_SWING_SPEED);
		s('WIN_ZIGZAG', ModEventType.WIN_ZIGZAG);
		s('WIN_ZIGZAG_SPEED', ModEventType.WIN_ZIGZAG_SPEED);
		s('WIN_PINBALL', ModEventType.WIN_PINBALL);
		s('WIN_PINBALL_ANGLE', ModEventType.WIN_PINBALL_ANGLE);
		s('WIN_ROLL', ModEventType.WIN_ROLL);
		s('WIN_ROLL_SPEED', ModEventType.WIN_ROLL_SPEED);
		s('WIN_BEAT_SCALE', ModEventType.WIN_BEAT_SCALE);
		s('WIN_HEARTBEAT', ModEventType.WIN_HEARTBEAT);
		s('WIN_STROBE', ModEventType.WIN_STROBE);
		s('WIN_STROBE_RATE', ModEventType.WIN_STROBE_RATE);
		s('WIN_STROBE_DUTY', ModEventType.WIN_STROBE_DUTY);
		s('WIN_ANCHOR', ModEventType.WIN_ANCHOR);
		s('WIN_ANCHOR_X', ModEventType.WIN_ANCHOR_X);
		s('WIN_ANCHOR_Y', ModEventType.WIN_ANCHOR_Y);
		s('WIN_ANCHOR_MX', ModEventType.WIN_ANCHOR_MX);
		s('WIN_ANCHOR_MY', ModEventType.WIN_ANCHOR_MY);
		// Funciones de acceso directo (sin cola de eventos, sin beats)
		var _self = this;
		s('set', function(groupId:String, strumIdx:Int, type:String, value:Float):Void _self.setVal(groupId, strumIdx, type, value));
		s('get', function(groupId:String, strumIdx:Int, type:String):Float return _self.getVal(groupId, strumIdx, type));
		s('applyNow', function():Void _self.applyNow());
		// Eases
		s('LINEAR', ModEase.LINEAR);
		s('QUAD_IN', ModEase.QUAD_IN);
		s('QUAD_OUT', ModEase.QUAD_OUT);
		s('QUAD_IN_OUT', ModEase.QUAD_IN_OUT);
		s('CUBE_IN', ModEase.CUBE_IN);
		s('CUBE_OUT', ModEase.CUBE_OUT);
		s('CUBE_IN_OUT', ModEase.CUBE_IN_OUT);
		s('SINE_IN', ModEase.SINE_IN);
		s('SINE_OUT', ModEase.SINE_OUT);
		s('SINE_IN_OUT', ModEase.SINE_IN_OUT);
		s('ELASTIC_IN', ModEase.ELASTIC_IN);
		s('ELASTIC_OUT', ModEase.ELASTIC_OUT);
		s('BOUNCE_OUT', ModEase.BOUNCE_OUT);
		s('BACK_IN', ModEase.BACK_IN);
		s('BACK_OUT', ModEase.BACK_OUT);
		s('INSTANT', ModEase.INSTANT);
	}

	private inline function _callHScript(func:String, args:Array<Dynamic>):Void
	{
		if (_hscriptInterp == null || !_hscriptInterp.variables.exists(func))
			return;
		try
		{
			Reflect.callMethod(null, _hscriptInterp.variables.get(func), args);
		}
		catch (e:Dynamic)
		{
			trace('[ModChartManager] Error $func(): $e');
		}
	}
	#end

	#if (LUA_ALLOWED && linc_luajit)
	private var _luaScript:Null<funkin.scripting.RuleScriptInstance> = null;

	private function _exposeConstantsLua(lua:funkin.scripting.RuleScriptInstance, songName:String):Void
	{
		inline function s(k:String, v:Dynamic)
			lua.set(k, v);
		s('song', songName);
		s('songPosition', 0.0);
		s('currentBeat', 0.0);
		// Strum types
		s('MOVE_X', ModEventType.MOVE_X);
		s('MOVE_Y', ModEventType.MOVE_Y);
		s('SET_ABS_X', ModEventType.SET_ABS_X);
		s('SET_ABS_Y', ModEventType.SET_ABS_Y);
		s('ANGLE', ModEventType.ANGLE);
		s('SPIN', ModEventType.SPIN);
		s('ALPHA', ModEventType.ALPHA);
		s('SCALE', ModEventType.SCALE);
		s('SCALE_X', ModEventType.SCALE_X);
		s('SCALE_Y', ModEventType.SCALE_Y);
		s('VISIBLE', ModEventType.VISIBLE);
		s('RESET', ModEventType.RESET);
		s('DRUNK_X', ModEventType.DRUNK_X);
		s('DRUNK_Y', ModEventType.DRUNK_Y);
		s('DRUNK_FREQ', ModEventType.DRUNK_FREQ);
		s('TORNADO', ModEventType.TORNADO);
		s('CONFUSION', ModEventType.CONFUSION);
		s('SCROLL_MULT', ModEventType.SCROLL_MULT);
		s('FLIP_X', ModEventType.FLIP_X);
		s('NOTE_OFFSET_X', ModEventType.NOTE_OFFSET_X);
		s('NOTE_OFFSET_Y', ModEventType.NOTE_OFFSET_Y);
		s('BUMPY', ModEventType.BUMPY);
		s('BUMPY_SPEED', ModEventType.BUMPY_SPEED);
		s('TIPSY', ModEventType.TIPSY);
		s('TIPSY_SPEED', ModEventType.TIPSY_SPEED);
		s('INVERT', ModEventType.INVERT);
		s('ZIGZAG', ModEventType.ZIGZAG);
		s('ZIGZAG_FREQ', ModEventType.ZIGZAG_FREQ);
		s('WAVE', ModEventType.WAVE);
		s('WAVE_SPEED', ModEventType.WAVE_SPEED);
		s('BEAT_SCALE', ModEventType.BEAT_SCALE);
		s('STEALTH', ModEventType.STEALTH);
		s('NOTE_ALPHA', ModEventType.NOTE_ALPHA);
		// Camera
		s('CAM_ZOOM', ModEventType.CAM_ZOOM);
		s('CAM_MOVE_X', ModEventType.CAM_MOVE_X);
		s('CAM_MOVE_Y', ModEventType.CAM_MOVE_Y);
		s('CAM_ANGLE', ModEventType.CAM_ANGLE);
		// Window
		s('WIN_X', ModEventType.WIN_X);
		s('WIN_Y', ModEventType.WIN_Y);
		s('WIN_SCALE', ModEventType.WIN_SCALE);
		s('WIN_SCALE_X', ModEventType.WIN_SCALE_X);
		s('WIN_SCALE_Y', ModEventType.WIN_SCALE_Y);
		s('WIN_ALPHA', ModEventType.WIN_ALPHA);
		s('WIN_RESET', ModEventType.WIN_RESET);
		s('WIN_ORBIT', ModEventType.WIN_ORBIT);
		s('WIN_ORBIT_SPEED', ModEventType.WIN_ORBIT_SPEED);
		s('WIN_ORBIT_PHASE', ModEventType.WIN_ORBIT_PHASE);
		s('WIN_ORBIT_EX', ModEventType.WIN_ORBIT_EX);
		s('WIN_ORBIT_EY', ModEventType.WIN_ORBIT_EY);
		s('WIN_SHAKE', ModEventType.WIN_SHAKE);
		s('WIN_SHAKE_SPEED', ModEventType.WIN_SHAKE_SPEED);
		s('WIN_BOUNCE', ModEventType.WIN_BOUNCE);
		s('WIN_BOUNCE_FREQ', ModEventType.WIN_BOUNCE_FREQ);
		s('WIN_BOUNCE_PERIOD', ModEventType.WIN_BOUNCE_PERIOD);
		s('WIN_SPIRAL', ModEventType.WIN_SPIRAL);
		s('WIN_SPIRAL_SPEED', ModEventType.WIN_SPIRAL_SPEED);
		s('WIN_SPIRAL_TIGHT', ModEventType.WIN_SPIRAL_TIGHT);
		s('WIN_FIGURE8', ModEventType.WIN_FIGURE8);
		s('WIN_FIGURE8_SPEED', ModEventType.WIN_FIGURE8_SPEED);
		s('WIN_GLITCH', ModEventType.WIN_GLITCH);
		s('WIN_GLITCH_RATE', ModEventType.WIN_GLITCH_RATE);
		s('WIN_WARP', ModEventType.WIN_WARP);
		s('WIN_WARP_PERIOD', ModEventType.WIN_WARP_PERIOD);
		s('WIN_SWING', ModEventType.WIN_SWING);
		s('WIN_SWING_SPEED', ModEventType.WIN_SWING_SPEED);
		s('WIN_ZIGZAG', ModEventType.WIN_ZIGZAG);
		s('WIN_ZIGZAG_SPEED', ModEventType.WIN_ZIGZAG_SPEED);
		s('WIN_PINBALL', ModEventType.WIN_PINBALL);
		s('WIN_PINBALL_ANGLE', ModEventType.WIN_PINBALL_ANGLE);
		s('WIN_ROLL', ModEventType.WIN_ROLL);
		s('WIN_ROLL_SPEED', ModEventType.WIN_ROLL_SPEED);
		s('WIN_BEAT_SCALE', ModEventType.WIN_BEAT_SCALE);
		s('WIN_HEARTBEAT', ModEventType.WIN_HEARTBEAT);
		s('WIN_STROBE', ModEventType.WIN_STROBE);
		s('WIN_STROBE_RATE', ModEventType.WIN_STROBE_RATE);
		s('WIN_STROBE_DUTY', ModEventType.WIN_STROBE_DUTY);
		s('WIN_ANCHOR', ModEventType.WIN_ANCHOR);
		s('WIN_ANCHOR_X', ModEventType.WIN_ANCHOR_X);
		s('WIN_ANCHOR_Y', ModEventType.WIN_ANCHOR_Y);
		s('WIN_ANCHOR_MX', ModEventType.WIN_ANCHOR_MX);
		s('WIN_ANCHOR_MY', ModEventType.WIN_ANCHOR_MY);
		// Eases
		s('LINEAR', ModEase.LINEAR);
		s('QUAD_IN', ModEase.QUAD_IN);
		s('QUAD_OUT', ModEase.QUAD_OUT);
		s('QUAD_IN_OUT', ModEase.QUAD_IN_OUT);
		s('CUBE_IN', ModEase.CUBE_IN);
		s('CUBE_OUT', ModEase.CUBE_OUT);
		s('CUBE_IN_OUT', ModEase.CUBE_IN_OUT);
		s('SINE_IN', ModEase.SINE_IN);
		s('SINE_OUT', ModEase.SINE_OUT);
		s('SINE_IN_OUT', ModEase.SINE_IN_OUT);
		s('ELASTIC_IN', ModEase.ELASTIC_IN);
		s('ELASTIC_OUT', ModEase.ELASTIC_OUT);
		s('BOUNCE_OUT', ModEase.BOUNCE_OUT);
		s('BACK_IN', ModEase.BACK_IN);
		s('BACK_OUT', ModEase.BACK_OUT);
		s('INSTANT', ModEase.INSTANT);

		var self = this;
		s('addEvent', function(beat:Float, target:String, strumIdx:Int, type:String, value:Float, ?duration:Float, ?ease:String):Void
		{
			self.addEventSimple(beat, target, strumIdx, type, value, duration ?? 0.0, ease ?? ModEase.LINEAR);
		});
		s('clearEvents', function():Void self.clearEvents());
		s('getState', function(groupId:String, strumIdx:Int):Dynamic
		{
			var st = self.getState(groupId, strumIdx);
			if (st == null)
				return null;
			return {
				x: st.baseX + st.offsetX,
				y: st.baseY + st.offsetY,
				angle: st.angle,
				alpha: st.alpha,
				scaleX: st.scaleX,
				scaleY: st.scaleY,
				visible: st.visible,
				scrollMult: st.scrollMult
			};
		});
		s('camState', camState);
		s('winState', winState);
		s('Conductor', funkin.data.Conductor);
		s('FlxG', flixel.FlxG);
		s('Math', Math);
		// Funciones de acceso directo (sin cola de eventos, sin beats)
		s('set', function(groupId:String, strumIdx:Int, type:String, value:Float):Void self.setVal(groupId, strumIdx, type, value));
		s('get', function(groupId:String, strumIdx:Int, type:String):Float return self.getVal(groupId, strumIdx, type));
		s('applyNow', function():Void self.applyNow());
	}

	private inline function _callLua(func:String, args:Array<Dynamic>):Void
	{
		if (_luaScript == null || !_luaScript.active)
			return;
		_luaScript.call(func, args);
	}
	#end

	// ─── Playback ─────────────────────────────────────────────────────────────

	public function loadFromJson(json:String):Void
	{
		try
		{
			var loaded:ModChartData = Json.parse(json);
			data = loaded;
			data.events.sort((a, b) -> a.beat < b.beat ? -1 : 1);
			resetToStart();
		}
		catch (e:Dynamic)
		{
			trace('[ModChartManager] ERROR parse JSON: $e');
		}
	}

	public function loadData(d:ModChartData):Void
	{
		data = d;
		data.events.sort((a, b) -> a.beat < b.beat ? -1 : 1);
		resetToStart();
	}

	public function toJson():String
		return Json.stringify(data, null, "  ");

	public function resetToStart():Void
	{
		// FIX 3 RAM: resize(0) reutiliza el array existente en lugar de allocar uno nuevo.
		activeTweens.resize(0);
		winState = _makeDefaultWinState();
		_lastWinX = _lastWinY = _lastWinW = _lastWinH = -9999;
		_lastWinAlpha = -1;

		for (group in strumsGroups)
		{
			var arr = states.get(group.id);
			if (arr == null)
				continue;
			for (i in 0...arr.length)
			{
				var st = arr[i];
				var spr = group.getStrum(i);
				st.offsetX = 0;
				st.offsetY = 0;
				st.absX = null;
				st.absY = null;
				st.angle = 0;
				st.spinRate = 0;
				st.alpha = 1;
				st.scaleX = (spr != null) ? spr.scale.x : 0.7;
				st.scaleY = (spr != null) ? spr.scale.y : 0.7;
				st.visible = st.baseVisible;
				st.drunkX = 0;
				st.drunkY = 0;
				st.drunkFreq = 1.0;
				st.tornado = 0;
				st.confusion = 0;
				st.scrollMult = 1.0;
				st.flipX = 0;
				st.noteOffsetX = 0;
				st.noteOffsetY = 0;
				st.bumpy = 0;
				st.bumpySpeed = 2.0;
				st.tipsy = 0;
				st.tipsySpeed = 1.0;
				st.invert = 0;
				st.zigzag = 0;
				st.zigzagFreq = 1.0;
				st.wave = 0;
				st.waveSpeed = 1.5;
				st.beatScale = 0;
				st._beatPulse = 0;
				st.stealth = 0;
				st.noteAlpha = 1.0;
			}
		}

		_pendingIdx = 0;
		pending.resize(0); // FIX 3 RAM: resize(0) reutiliza el array sin allocar
		for (ev in data.events)
			if (ev.beat >= currentBeat - 0.01)
				pending.push(ev);

		applyAllStates();
	}

	public function seekToBeat(beat:Float):Void
	{
		for (group in strumsGroups)
		{
			var arr = states.get(group.id);
			if (arr == null)
				continue;
			for (i in 0...arr.length)
			{
				var st = arr[i];
				var spr = group.getStrum(i);
				st.offsetX = 0;
				st.offsetY = 0;
				st.absX = null;
				st.absY = null;
				st.angle = 0;
				st.spinRate = 0;
				st.alpha = 1;
				st.scaleX = (spr != null) ? spr.scale.x : 0.7;
				st.scaleY = (spr != null) ? spr.scale.y : 0.7;
				st.visible = st.baseVisible;
				st.drunkX = 0;
				st.drunkY = 0;
				st.drunkFreq = 1.0;
				st.tornado = 0;
				st.confusion = 0;
				st.scrollMult = 1.0;
				st.flipX = 0;
				st.noteOffsetX = 0;
				st.noteOffsetY = 0;
				st.bumpy = 0;
				st.bumpySpeed = 2.0;
				st.tipsy = 0;
				st.tipsySpeed = 1.0;
				st.invert = 0;
				st.zigzag = 0;
				st.zigzagFreq = 1.0;
				st.wave = 0;
				st.waveSpeed = 1.5;
				st.beatScale = 0;
				st._beatPulse = 0;
				st.stealth = 0;
				st.noteAlpha = 1.0;
			}
		}
		winState = _makeDefaultWinState();

		for (ev in data.events)
		{
			if (ev.beat > beat)
				break;
			if (ModChartHelpers.isWindowType(ev.type))
				setWindowValue(ev.type, ev.value);
			else
				applyEventInstant(ev);
		}

		currentBeat = beat;
		activeTweens.resize(0); // FIX 3 RAM: resize(0) reutiliza el array sin allocar
		_pendingIdx = 0;
		pending.resize(0); // FIX 3 RAM
		for (ev in data.events)
			if (ev.beat >= beat - 0.01)
				pending.push(ev);

		applyAllStates();
	}

	// ─── Update ───────────────────────────────────────────────────────────────

	public function update(songPos:Float):Void
	{
		if (!enabled)
			return;

		this.songPosition = songPos;
		var beatFloat:Float = (funkin.data.Conductor.crochet > 0) ? songPos / funkin.data.Conductor.crochet : 0.0;
		this.currentBeat = beatFloat;

		fireReadyEvents(beatFloat);
		updateTweens(beatFloat);
		applySpins(FlxG.elapsed);
		applyAllStates();
		applyWindowState(beatFloat); // ← WINDOW MODS APLICADOS AQUÍ

		#if HSCRIPT_ALLOWED
		_callHScript('onUpdate', [songPos]);
		#end
		#if (LUA_ALLOWED && linc_luajit)
		if (_luaScript != null)
		{
			_luaScript.set('songPosition', songPos);
			_luaScript.set('currentBeat', currentBeat);
			_callLua('onUpdate', [songPos]);
		}
		#end
	}

	// ── Disparar eventos ─────────────────────────────────────────────────────

	private function fireReadyEvents(curBeat:Float):Void
	{
		while (_pendingIdx < pending.length)
		{
			final ev = pending[_pendingIdx];
			if (ev.beat > curBeat)
				break;
			_pendingIdx++;

			if (ev.type == RESET)
			{
				applyReset(ev);
				continue;
			}
			if (ev.type == WIN_RESET)
			{
				winState = _makeDefaultWinState();
				_restoreWindow();
				continue;
			}

			if (ev.duration <= 0 || ev.ease == INSTANT)
			{
				if (ModChartHelpers.isWindowType(ev.type))
					setWindowValue(ev.type, ev.value);
				else
					applyEventInstant(ev);
			}
			else
			{
				if (ModChartHelpers.isCameraType(ev.type))
				{
					activeTweens.push({
						event: ev,
						startBeat: ev.beat,
						startVal: getStateValue("", -1, ev.type),
						groupId: "__camera__",
						strumIdx: 0
					});
				}
				else if (ModChartHelpers.isWindowType(ev.type))
				{
					activeTweens.push({
						event: ev,
						startBeat: ev.beat,
						startVal: getWindowValue(ev.type),
						groupId: "__window__",
						strumIdx: 0
					});
				}
				else
				{
					final targets = resolveTargets(ev.target, ev.strumIdx);
					for (t in targets)
						activeTweens.push({
							event: ev,
							startBeat: ev.beat,
							startVal: getStateValue(t.groupId, t.strumIdx, ev.type),
							groupId: t.groupId,
							strumIdx: t.strumIdx
						});
				}
			}
		}
	}

	// ── Tweens ───────────────────────────────────────────────────────────────

	private function updateTweens(curBeat:Float):Void
	{
		_finishedTweens.resize(0);
		for (tw in activeTweens)
		{
			final elapsed = curBeat - tw.startBeat;
			final t = tw.event.duration > 0 ? elapsed / tw.event.duration : 1.0;
			final eased = ModChartHelpers.applyEase(tw.event.ease, t);
			final val = tw.startVal + (tw.event.value - tw.startVal) * eased;

			if (tw.groupId == "__window__")
				setWindowValue(tw.event.type, val);
			else
				setStateValue(tw.groupId, tw.strumIdx, tw.event.type, val);

			if (t >= 1.0)
				_finishedTweens.push(tw);
		}

		var i = _finishedTweens.length - 1;
		while (i >= 0)
		{
			final target = _finishedTweens[i];
			final len = activeTweens.length;
			var j = len - 1;
			while (j >= 0)
			{
				if (activeTweens[j] == target)
				{
					// Swap con el último y reducir longitud — O(1), sin mover memoria
					activeTweens[j] = activeTweens[len - 1];
					activeTweens.resize(len - 1);
					break;
				}
				j--;
			}
			i--;
		}
	}

	// ── Spin / Beat pulse ─────────────────────────────────────────────────────

	private function applySpins(elapsed:Float):Void
	{
		var bps:Float = funkin.data.Conductor.bpm / 60.0;
		for (group in strumsGroups)
		{
			var arr = states.get(group.id);
			if (arr == null)
				continue;
			for (st in arr)
			{
				if (st.spinRate != 0)
					st.angle += st.spinRate * elapsed * bps;
				if (st._beatPulse > 0)
				{
					st._beatPulse -= elapsed * 8.0;
					if (st._beatPulse < 0)
						st._beatPulse = 0;
				}
			}
		}

		// Window beat pulse decay
		if (winState._beatPulse > 0)
		{
			winState._beatPulse -= elapsed * 8.0;
			if (winState._beatPulse < 0)
				winState._beatPulse = 0;
		}
	}

	// ─── API de escritura/lectura directa (sin cola de eventos) ──────────────

	/**
	 * Establece un valor de estado INMEDIATAMENTE, sin pasar por la cola de
	 * eventos ni esperar ningún beat/step.  Ideal para usar en `onCreate`
	 * cuando quieres que la flecha esté ya en cierta posición desde el primer
	 * frame de PlayState.
	 *
	 * Uso HScript:
	 *   function onCreate() {
	 *       set("player", 0, SET_ABS_X, 640);   // flecha 0 centrada en X
	 *       set("player", -1, SET_ABS_Y, 400);  // todos los strums, Y=400
	 *   }
	 *
	 * Uso Lua:
	 *   function onCreate()
	 *       set("player", 0, SET_ABS_X, 640)
	 *   end
	 */
	public function setVal(groupId:String, strumIdx:Int, type:ModEventType, value:Float):Void
	{
		if (ModChartHelpers.isWindowType(type))
		{
			setWindowValue(type, value);
			return;
		}
		if (strumIdx == -1)
		{
			// -1 = todos los strums del grupo
			for (i in 0...4)
				setStateValue(groupId, i, type, value);
		}
		else
		{
			setStateValue(groupId, strumIdx, type, value);
		}
	}

	/** Devuelve el valor actual de un parámetro de estado, sin depender de beats. */
	public function getVal(groupId:String, strumIdx:Int, type:ModEventType):Float
	{
		if (ModChartHelpers.isWindowType(type))
			return getWindowValue(type);
		return getStateValue(groupId, strumIdx, type);
	}

	/** Fuerza la aplicación inmediata de todos los estados a los sprites.
	 *  Útil al final de `onCreate` si has usado `set()` directamente. */
	public function applyNow():Void
		applyAllStates();

	// ── Apply sprites ─────────────────────────────────────────────────────────

	private function applyAllStates():Void
	{
		for (group in strumsGroups)
		{
			var arr = states.get(group.id);
			if (arr == null)
				continue;
			for (i in 0...4)
			{
				var spr = group.getStrum(i);
				if (spr == null || i >= arr.length)
					continue;
				var st = arr[i];

				// ── Posición / ángulo / escala base ───────────────────────────
				final logX:Float = (st.absX != null) ? st.absX : st.baseX + st.offsetX;
				final logY:Float = (st.absY != null) ? st.absY : st.baseY + st.offsetY;

				// Guardar posición lógica en StrumNote para que NoteManager
				// la use como referencia de posicionamiento de notas, sin que
				// los modificadores visuales de abajo contaminen el cálculo.
				var sn:StrumNote = Std.downcast(spr, StrumNote);
				if (sn != null)
				{
					sn.logicalX = logX;
					sn.logicalY = logY;
				}

				spr.x = logX;
				spr.y = logY;
				// BUG A FIX: los receptores (strums) NO rotan con INVERT.
				// Solo las NOTAS se rotan 180° (en NoteManager.updateNotePosition).
				// Los strums son indicadores estáticos de qué tecla pulsar;
				// rotar 180° los hacía aparecer con flipX visual (LEFT→RIGHT, etc.),
				// confundiendo al jugador. El comportamiento correcto es mantener
				// el ángulo del strum independiente del estado de invert.
				spr.angle = st.angle;
				spr.alpha = Math.max(0, Math.min(1, st.alpha));
				spr.scale.set(st.scaleX, st.scaleY);
				spr.visible = st.visible;

				// ── Modificadores visuales del carril ─────────────────────────
				// Se aplican DESPUÉS de guardar logicalX/Y.  Replica la misma
				// fórmula que NoteManager.updateNotePosition() evaluada en
				// t = songPosition (la nota que estaría "en" el strum ahora mismo).
				// Esto hace que el strum receptor se mueva sincronizado con las
				// notas al llegar, sin desplazar la referencia de posicionamiento.
				final sp:Float = this.songPosition;

				// Flat offsets (siempre activos aunque sean 0)
				if (st.noteOffsetX != 0) spr.x += st.noteOffsetX;
				if (st.noteOffsetY != 0) spr.y += st.noteOffsetY;

				// DrunkX/Y — onda senoidal (misma fase que NoteManager: t=sp)
				if (st.drunkX != 0)
					spr.x += st.drunkX * Math.sin(sp * 0.001 * st.drunkFreq + sp * 0.0008);
				if (st.drunkY != 0)
					spr.y += st.drunkY * Math.sin(sp * 0.001 * st.drunkFreq + sp * 0.0008);

				// Tipsy — ola X global por songPosition
				if (st.tipsy != 0)
					spr.x += st.tipsy * Math.sin(sp * 0.001 * st.tipsySpeed);

				// Zigzag — escalonado en X por songPosition
				if (st.zigzag != 0)
				{
					final zz:Float = Math.sin(sp * 0.001 * st.zigzagFreq * Math.PI);
					spr.x += st.zigzag * (zz >= 0 ? 1.0 : -1.0);
				}

				// Bumpy — ola Y global por songPosition
				if (st.bumpy != 0)
					spr.y += st.bumpy * Math.sin(sp * 0.001 * st.bumpySpeed);

				// Wave — ola Y mixta (misma evaluación que NoteManager en t=sp)
				if (st.wave != 0)
					spr.y += st.wave * Math.sin(sp * 0.001 * st.waveSpeed - sp * 0.001);

				// Confusion — offset de ángulo plano (idéntico al de cada nota)
				if (st.confusion != 0)
					spr.angle += st.confusion;

				// Tornado — ángulo senoidal evaluado en t=sp
				if (st.tornado != 0)
					spr.angle += st.tornado * Math.sin(sp * 0.001 * st.drunkFreq);
			}
		}
	}

	// ── Target resolution ─────────────────────────────────────────────────────

	private function resolveTargets(target:String, strumIdx:Int):Array<{groupId:String, strumIdx:Int}>
	{
		var result:Array<{groupId:String, strumIdx:Int}> = [];
		var groupIds:Array<String> = [];

		if (target == "all")
			for (g in strumsGroups)
				groupIds.push(g.id);
		else if (target == "player")
			for (g in strumsGroups)
			{
				if (!g.isCPU)
					groupIds.push(g.id);
			}
		else if (target == "cpu")
			for (g in strumsGroups)
			{
				if (g.isCPU)
					groupIds.push(g.id);
			}
		else
			groupIds.push(target);

		for (gid in groupIds)
		{
			if (strumIdx == -1)
				for (s in 0...4)
					result.push({groupId: gid, strumIdx: s});
			else
				result.push({groupId: gid, strumIdx: strumIdx});
		}
		return result;
	}

	// ── get/set state value ───────────────────────────────────────────────────

	private function getStateValue(groupId:String, strumIdx:Int, type:ModEventType):Float
	{
		if (ModChartHelpers.isCameraType(type))
			return switch (type)
			{
				case CAM_ZOOM: camState.zoom;
				case CAM_MOVE_X: camState.offsetX;
				case CAM_MOVE_Y: camState.offsetY;
				case CAM_ANGLE: camState.angle;
				default: 0;
			};

		var arr = states.get(groupId);
		if (arr == null || strumIdx < 0 || strumIdx >= arr.length)
			return 0;
		var st = arr[strumIdx];
		return switch (type)
		{
			case MOVE_X: st.offsetX;
			case MOVE_Y: st.offsetY;
			case SET_ABS_X: st.absX != null ? st.absX : st.baseX;
			case SET_ABS_Y: st.absY != null ? st.absY : st.baseY;
			case ANGLE: st.angle;
			case ALPHA: st.alpha;
			case SCALE | SCALE_X: st.scaleX;
			case SCALE_Y: st.scaleY;
			case SPIN: st.spinRate;
			case VISIBLE: st.visible ? 1 : 0;
			case DRUNK_X: st.drunkX;
			case DRUNK_Y: st.drunkY;
			case DRUNK_FREQ: st.drunkFreq;
			case TORNADO: st.tornado;
			case CONFUSION: st.confusion;
			case SCROLL_MULT: st.scrollMult;
			case FLIP_X: st.flipX;
			case NOTE_OFFSET_X: st.noteOffsetX;
			case NOTE_OFFSET_Y: st.noteOffsetY;
			case BUMPY: st.bumpy;
			case BUMPY_SPEED: st.bumpySpeed;
			case TIPSY: st.tipsy;
			case TIPSY_SPEED: st.tipsySpeed;
			case INVERT: st.invert;
			case ZIGZAG: st.zigzag;
			case ZIGZAG_FREQ: st.zigzagFreq;
			case WAVE: st.wave;
			case WAVE_SPEED: st.waveSpeed;
			case BEAT_SCALE: st.beatScale;
			case STEALTH: st.stealth;
			case NOTE_ALPHA: st.noteAlpha;
			default: 0;
		};
	}

	private function setStateValue(groupId:String, strumIdx:Int, type:ModEventType, value:Float):Void
	{
		if (ModChartHelpers.isCameraType(type))
		{
			switch (type)
			{
				case CAM_ZOOM:
					camState.zoom = value;
				case CAM_MOVE_X:
					camState.offsetX = value;
				case CAM_MOVE_Y:
					camState.offsetY = value;
				case CAM_ANGLE:
					camState.angle = value;
				default:
			}
			return;
		}

		var arr = states.get(groupId);
		if (arr == null || strumIdx < 0 || strumIdx >= arr.length)
			return;
		var st = arr[strumIdx];
		switch (type)
		{
			case MOVE_X:
				st.offsetX = value;
				st.absX = null;
			case MOVE_Y:
				st.offsetY = value;
				st.absY = null;
			case SET_ABS_X:
				st.absX = value;
			case SET_ABS_Y:
				st.absY = value;
			case ANGLE:
				st.angle = value;
			case ALPHA:
				st.alpha = value;
			case SCALE:
				st.scaleX = value;
				st.scaleY = value;
			case SCALE_X:
				st.scaleX = value;
			case SCALE_Y:
				st.scaleY = value;
			case SPIN:
				st.spinRate = value;
			case VISIBLE:
				st.visible = value >= 0.5;
			case DRUNK_X:
				st.drunkX = value;
			case DRUNK_Y:
				st.drunkY = value;
			case DRUNK_FREQ:
				st.drunkFreq = value;
			case TORNADO:
				st.tornado = value;
			case CONFUSION:
				st.confusion = value;
			case SCROLL_MULT:
				st.scrollMult = value;
			case FLIP_X:
				st.flipX = value;
			case NOTE_OFFSET_X:
				st.noteOffsetX = value;
			case NOTE_OFFSET_Y:
				st.noteOffsetY = value;
			case BUMPY:
				st.bumpy = value;
			case BUMPY_SPEED:
				st.bumpySpeed = value;
			case TIPSY:
				st.tipsy = value;
			case TIPSY_SPEED:
				st.tipsySpeed = value;
			case INVERT:
				st.invert = value;
			case ZIGZAG:
				st.zigzag = value;
			case ZIGZAG_FREQ:
				st.zigzagFreq = value;
			case WAVE:
				st.wave = value;
			case WAVE_SPEED:
				st.waveSpeed = value;
			case BEAT_SCALE:
				st.beatScale = value;
			case STEALTH:
				st.stealth = value;
			case NOTE_ALPHA:
				st.noteAlpha = value;
			case RESET:
			case CAM_ZOOM | CAM_MOVE_X | CAM_MOVE_Y | CAM_ANGLE:
			default:
		}
	}

	private function applyEventInstant(ev:ModChartEvent):Void
	{
		for (t in resolveTargets(ev.target, ev.strumIdx))
			setStateValue(t.groupId, t.strumIdx, ev.type, ev.value);
	}

	private function applyReset(ev:ModChartEvent):Void
	{
		if (ev.target == "camera" || ev.target == "cam")
		{
			camState.zoom = 0;
			camState.offsetX = 0;
			camState.offsetY = 0;
			camState.angle = 0;
			return;
		}
		for (t in resolveTargets(ev.target, ev.strumIdx))
		{
			var arr = states.get(t.groupId);
			if (arr == null || t.strumIdx < 0 || t.strumIdx >= arr.length)
				continue;
			var st = arr[t.strumIdx];
			var spr:Dynamic = null;
			for (g in strumsGroups)
				if (g.id == t.groupId)
				{
					spr = g.getStrum(t.strumIdx);
					break;
				}
			st.offsetX = 0;
			st.offsetY = 0;
			st.absX = null;
			st.absY = null;
			st.angle = 0;
			st.spinRate = 0;
			st.alpha = 1;
			st.scaleX = (spr != null) ? spr.scale.x : 0.7;
			st.scaleY = (spr != null) ? spr.scale.y : 0.7;
			st.visible = st.baseVisible;
			st.drunkX = 0;
			st.drunkY = 0;
			st.drunkFreq = 1.0;
			st.tornado = 0;
			st.confusion = 0;
			st.scrollMult = 1.0;
			st.flipX = 0;
			st.noteOffsetX = 0;
			st.noteOffsetY = 0;
			st.bumpy = 0;
			st.bumpySpeed = 2.0;
			st.tipsy = 0;
			st.tipsySpeed = 1.0;
			st.invert = 0;
			st.zigzag = 0;
			st.zigzagFreq = 1.0;
			st.wave = 0;
			st.waveSpeed = 1.5;
			st.beatScale = 0;
			st._beatPulse = 0;
			st.stealth = 0;
			st.noteAlpha = 1.0;
		}
	}

	// ─── API pública ──────────────────────────────────────────────────────────

	public function addEvent(ev:ModChartEvent):Void
	{
		data.events.push(ev);
		data.events.sort((a, b) -> a.beat < b.beat ? -1 : 1);
		if (ev.beat >= currentBeat - 0.01)
			pending.push(ev);
		pending.sort((a, b) -> a.beat < b.beat ? -1 : 1);
	}

	public function addEventSimple(beat:Float, target:String, strumIdx:Int, type:ModEventType, value:Float, duration:Float = 0, ease:ModEase = LINEAR):Void
	{
		addEvent(ModChartHelpers.makeEvent(beat, target, strumIdx, type, value, duration, ease));
	}

	public function clearEvents():Void
	{
		// FIX 3 RAM: resize(0) en todos los arrays — reutiliza la backing array sin allocar
		if (data.events != null) data.events.resize(0);
		_pendingIdx = 0;
		pending.resize(0);
		activeTweens.resize(0);
	}

	public function getState(groupId:String, strumIdx:Int):Null<StrumState>
	{
		// BUG FIX #5: NoteManager uses "player"/"cpu" as fallback when
		// allStrumsGroups is null. But states are keyed by the actual
		// group.id (e.g. "bf", "dad", "player1"…).  Resolve aliases first.
		var resolvedId = groupId;
		if (!states.exists(groupId))
		{
			// OPTIMIZACIÓN: consultar caché antes de hacer el scan O(n).
			// En el caso común (groupId = "player"/"cpu") el scan solo ocurre
			// la primera vez; todas las llamadas siguientes son O(1).
			var cached = _aliasCache.get(groupId);
			if (cached != null)
			{
				resolvedId = cached;
			}
			else
			{
				// Try to match by isCPU flag when the literal key isn't found
				var wantCPU = (groupId == "cpu" || groupId == "opponent" || groupId == "dad" || groupId == "enemy");
				for (g in strumsGroups)
				{
					if (g.isCPU == wantCPU)
					{
						resolvedId = g.id;
						break;
					}
				}
				_aliasCache.set(groupId, resolvedId);
			}
		}
		var arr = states.get(resolvedId);
		if (arr == null || strumIdx < 0 || strumIdx >= arr.length)
			return null;
		return arr[strumIdx];
	}

	public function getStrumDisplayPos(groupId:String, strumIdx:Int):{x:Float, y:Float}
	{
		var st = getState(groupId, strumIdx);
		if (st == null)
			return {x: 0, y: 0};
		return {
			x: st.absX != null ? st.absX : st.baseX + st.offsetX,
			y: st.absY != null ? st.absY : st.baseY + st.offsetY
		};
	}

	// ─── Beat / Step hooks ────────────────────────────────────────────────────

	public function onBeatHit(beat:Int):Void
	{
		for (group in strumsGroups)
		{
			var arr = states.get(group.id);
			if (arr == null)
				continue;
			for (st in arr)
				if (st.beatScale > 0)
					st._beatPulse = st.beatScale;
		}

		// Window beat scale pulse
		if (winState.beatScale > 0)
			winState._beatPulse = winState.beatScale;

		#if HSCRIPT_ALLOWED _callHScript('onBeatHit', [beat]); #end
		#if (LUA_ALLOWED && linc_luajit) _callLua('onBeatHit', [beat]); #end
	}

	public function onNoteHit(note:Dynamic):Void
	{
		#if HSCRIPT_ALLOWED _callHScript('onNoteHit', [note]); #end
		#if (LUA_ALLOWED && linc_luajit) _callLua('onNoteHit', [note]); #end
	}

	public function onStepHit(step:Int):Void
	{
		#if HSCRIPT_ALLOWED _callHScript('onStepHit', [step]); #end
		#if (LUA_ALLOWED && linc_luajit) _callLua('onStepHit', [step]); #end
	}

	// ── Hooks adicionales del ciclo de vida ───────────────────────────────────

	/**
	 * Se llama cuando empieza el countdown (antes de que aparezcan los números).
	 * Ideal para posicionar cosas ANTES de que el jugador vea la pantalla.
	 *
	 * Uso HScript:
	 *   function onCountdownStart() {
	 *       set("player", -1, SET_ABS_X, 640);
	 *   }
	 */
	public function onCountdownStart():Void
	{
		#if HSCRIPT_ALLOWED _callHScript('onCountdownStart', []); #end
		#if (LUA_ALLOWED && linc_luajit) _callLua('onCountdownStart', []); #end
	}

	/**
	 * Se llama en cada tick del countdown (step = 0, 1, 2, 3 → 4 = "GO!").
	 * Útil para efectos que reaccionen a "3-2-1-GO".
	 */
	public function onCountdownTick(step:Int):Void
	{
		#if HSCRIPT_ALLOWED _callHScript('onCountdownTick', [step]); #end
		#if (LUA_ALLOWED && linc_luajit) _callLua('onCountdownTick', [step]); #end
	}

	/**
	 * Se llama justo cuando la música arranca (después del countdown).
	 */
	public function onSongStart():Void
	{
		#if HSCRIPT_ALLOWED _callHScript('onSongStart', []); #end
		#if (LUA_ALLOWED && linc_luajit) _callLua('onSongStart', []); #end
	}

	/**
	 * Se llama cuando el jugador falla una nota.
	 */
	public function onNoteMiss(note:Dynamic):Void
	{
		#if HSCRIPT_ALLOWED _callHScript('onNoteMiss', [note]); #end
		#if (LUA_ALLOWED && linc_luajit) _callLua('onNoteMiss', [note]); #end
	}

	/**
	 * Se llama cuando el jugador pausa el juego.
	 */
	public function onPause():Void
	{
		#if HSCRIPT_ALLOWED _callHScript('onPause', []); #end
		#if (LUA_ALLOWED && linc_luajit) _callLua('onPause', []); #end
	}

	/**
	 * Se llama cuando el jugador reanuda el juego tras una pausa.
	 */
	public function onResume():Void
	{
		#if HSCRIPT_ALLOWED _callHScript('onResume', []); #end
		#if (LUA_ALLOWED && linc_luajit) _callLua('onResume', []); #end
	}

	// ─── Destructor ───────────────────────────────────────────────────────────

	public function destroy():Void
	{
		// FIX 3 RAM: resize(0) — libera elementos pero reutiliza backing array
		activeTweens.resize(0);
		_pendingIdx = 0;
		pending.resize(0);
		states.clear();
		strumsGroups = null;

		_restoreWindow(); // ← Restaurar ventana al estado original al destruir

		#if HSCRIPT_ALLOWED _hscriptInterp = null; #end
		#if (LUA_ALLOWED && linc_luajit)
		if (_luaScript != null)
		{
			_callLua('onDestroy', []);
			_luaScript.destroy();
			_luaScript = null;
		}
		#end
		instance = null;
	}
}
