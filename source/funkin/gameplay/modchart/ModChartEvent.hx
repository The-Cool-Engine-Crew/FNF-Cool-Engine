package funkin.gameplay.modchart;

using StringTools;
/**
 * ============================================================
 *  ModChartEvent.hx  –  v4  (Window Modcharting integrado)
 * ============================================================
 */
enum abstract ModEventType(String) from String to String
{
	// ── Strum – Posición
	var MOVE_X = "moveX";
	var MOVE_Y = "moveY";
	var SET_ABS_X = "setAbsX";
	var SET_ABS_Y = "setAbsY";

	// ── Strum – Rotación / apariencia
	var ANGLE = "angle";
	var SPIN = "spin";
	var ALPHA = "alpha";
	var SCALE = "scale";
	var SCALE_X = "scaleX";
	var SCALE_Y = "scaleY";
	var VISIBLE = "visible";
	var RESET = "reset";

	// ── Per-nota – Drunk
	var DRUNK_X = "drunkX";
	var DRUNK_Y = "drunkY";
	var DRUNK_FREQ = "drunkFreq";

	// ── Per-nota – Rotación
	var TORNADO = "tornado";
	var CONFUSION = "confusion";

	// ── Rotación 3D simulada (perspectiva por eje) ────────────────────────────
	// rotX → gira alrededor del eje X (comprime scaleY con cos); efecto "página que se voltea"
	// rotY → gira alrededor del eje Y (comprime scaleX con cos); efecto "moneda girando de lado"
	// Rango: 0-360°. Cara trasera automática cuando cos < 0 (flipX/flipY).
	var ROT_X = "rotX";
	var ROT_Y = "rotY";

	// ── Per-nota – Scroll / Posición
	var SCROLL_MULT = "scrollMult";
	var FLIP_X = "flipX";
	var NOTE_OFFSET_X = "noteOffsetX";
	var NOTE_OFFSET_Y = "noteOffsetY";

	// ── Per-nota – Bumpy
	var BUMPY = "bumpy";
	var BUMPY_SPEED = "bumpySpeed";

	// ── Per-nota – v3
	var TIPSY = "tipsy";
	var TIPSY_SPEED = "tipsySpeed";
	var INVERT = "invert";
	var ZIGZAG = "zigzag";
	var ZIGZAG_FREQ = "zigzagFreq";
	var WAVE = "wave";
	var WAVE_SPEED = "waveSpeed";
	var BEAT_SCALE = "beatScale";
	var STEALTH = "stealth";
	var NOTE_ALPHA = "noteAlpha";

	// ── Deformación / baile de strums ──────────────────────────────────────
	/** Inclina el strum en X (lean horizontal en grados). */
	var SKEW_X = "skewX";
	/** Inclina el strum en Y (lean vertical en grados). */
	var SKEW_Y = "skewY";
	/** Amplitud del salto parabólico Y por beat (px). */
	var JUMP_Y = "jumpY";
	/** Período del salto en beats (default 1 = un salto por beat). */
	var JUMP_PERIOD = "jumpPeriod";
	/** Amplitud del temblor aleatorio en X (px). */
	var SHAKE_X = "shakeX";
	/** Amplitud del temblor aleatorio en Y (px). */
	var SHAKE_Y = "shakeY";
	/** Velocidad del temblor (oscilaciones/seg, default 20). */
	var SHAKE_SPEED = "shakeSpeed";
	/** Pulso de escala en X por beat (aplastado/estirado horizontal). */
	var BEAT_SCALE_X = "beatScaleX";
	/** Pulso de escala en Y por beat (aplastado/estirado vertical). */
	var BEAT_SCALE_Y = "beatScaleY";

	// ── Cámara
	var CAM_ZOOM = "camZoom";
	var CAM_MOVE_X = "camMoveX";
	var CAM_MOVE_Y = "camMoveY";
	var CAM_ANGLE = "camAngle";

	// ══════════════════════════════════════
	//  VENTANA OS  (todos empiezan con "win")
	// ══════════════════════════════════════
	// Controles base
	var WIN_X = "winX";
	var WIN_Y = "winY";
	var WIN_SCALE = "winScale";
	var WIN_SCALE_X = "winScaleX";
	var WIN_SCALE_Y = "winScaleY";
	var WIN_ALPHA = "winAlpha";
	var WIN_RESET = "winReset";

	// Órbita circular / elíptica
	var WIN_ORBIT = "winOrbit";
	var WIN_ORBIT_SPEED = "winOrbitSpeed";
	var WIN_ORBIT_PHASE = "winOrbitPhase";
	var WIN_ORBIT_EX = "winOrbitEX";
	var WIN_ORBIT_EY = "winOrbitEY";

	// Vibración
	var WIN_SHAKE = "winShake";
	var WIN_SHAKE_SPEED = "winShakeSpeed";

	// Rebote de resorte
	var WIN_BOUNCE = "winBounce";
	var WIN_BOUNCE_FREQ = "winBounceFreq";
	var WIN_BOUNCE_PERIOD = "winBouncePeriod";

	// Espiral
	var WIN_SPIRAL = "winSpiral";
	var WIN_SPIRAL_SPEED = "winSpiralSpeed";
	var WIN_SPIRAL_TIGHT = "winSpiralTight";

	// Figura-8
	var WIN_FIGURE8 = "winFigure8";
	var WIN_FIGURE8_SPEED = "winFigure8Speed";

	// Glitch
	var WIN_GLITCH = "winGlitch";
	var WIN_GLITCH_RATE = "winGlitchRate";

	// Warp
	var WIN_WARP = "winWarp";
	var WIN_WARP_PERIOD = "winWarpPeriod";

	// Péndulo
	var WIN_SWING = "winSwing";
	var WIN_SWING_SPEED = "winSwingSpeed";

	// Zigzag
	var WIN_ZIGZAG = "winZigzag";
	var WIN_ZIGZAG_SPEED = "winZigzagSpeed";

	// Pinball
	var WIN_PINBALL = "winPinball";
	var WIN_PINBALL_ANGLE = "winPinballAngle";

	// Roll
	var WIN_ROLL = "winRoll";
	var WIN_ROLL_SPEED = "winRollSpeed";

	// Beat Scale / Heartbeat
	var WIN_BEAT_SCALE = "winBeatScale";
	var WIN_HEARTBEAT = "winHeartbeat";

	// Strobe
	var WIN_STROBE = "winStrobe";
	var WIN_STROBE_RATE = "winStrobeRate";
	var WIN_STROBE_DUTY = "winStrobeDuty";

	// Anclaje a esquina
	var WIN_ANCHOR = "winAnchor";
	var WIN_ANCHOR_X = "winAnchorX";
	var WIN_ANCHOR_Y = "winAnchorY";
	var WIN_ANCHOR_MX = "winAnchorMX";
	var WIN_ANCHOR_MY = "winAnchorMY";
}

// ─── Easings ─────────────────────────────────────────────────────────────────

enum abstract ModEase(String) from String to String
{
	var LINEAR = "linear";
	var QUAD_IN = "quadIn";
	var QUAD_OUT = "quadOut";
	var QUAD_IN_OUT = "quadInOut";
	var CUBE_IN = "cubeIn";
	var CUBE_OUT = "cubeOut";
	var CUBE_IN_OUT = "cubeInOut";
	var SINE_IN = "sineIn";
	var SINE_OUT = "sineOut";
	var SINE_IN_OUT = "sineInOut";
	var ELASTIC_IN = "elasticIn";
	var ELASTIC_OUT = "elasticOut";
	var BOUNCE_OUT = "bounceOut";
	var BACK_IN = "backIn";
	var BACK_OUT = "backOut";
	var INSTANT = "instant";
}

// ─── Evento ──────────────────────────────────────────────────────────────────

typedef ModChartEvent =
{
	var id:String;
	var beat:Float;
	var target:String;
	var strumIdx:Int;
	var type:ModEventType;
	var value:Float;
	var duration:Float;
	var ease:ModEase;
	var label:String;
	var color:Int;
}

typedef ModChartData =
{
	var name:String;
	var song:String;
	var version:String;
	var events:Array<ModChartEvent>;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class ModChartHelpers
{
	static var _uid:Int = 0;

	public static function newId():String
		return "ev_" + (++_uid) + "_" + Std.string(Std.random(9999));

	public static function makeEvent(beat:Float, target:String, strumIdx:Int, type:ModEventType, value:Float, duration:Float = 0.0,
			ease:ModEase = LINEAR):ModChartEvent
	{
		return {
			id: newId(),
			beat: beat,
			target: target,
			strumIdx: strumIdx,
			type: type,
			value: value,
			duration: duration,
			ease: ease,
			label: type,
			color: defaultColor(type)
		};
	}

	public static function defaultColor(type:ModEventType):Int
	{
		return switch (type)
		{
			case MOVE_X | SET_ABS_X | NOTE_OFFSET_X | FLIP_X | TIPSY | ZIGZAG | SKEW_X | SHAKE_X: 0xFF4FC3F7;
			case MOVE_Y | SET_ABS_Y | NOTE_OFFSET_Y | BUMPY | WAVE | SKEW_Y | SHAKE_Y | JUMP_Y: 0xFF81C784;
			case ANGLE | SPIN | TORNADO | CONFUSION | ROT_X | ROT_Y: 0xFFFFB74D;
			case ALPHA | NOTE_ALPHA | STEALTH: 0xFFBA68C8;
			case SCALE | SCALE_X | SCALE_Y | BEAT_SCALE | BEAT_SCALE_X | BEAT_SCALE_Y: 0xFFFF8A65;
			case DRUNK_X | DRUNK_Y | DRUNK_FREQ: 0xFF26C6DA;
			case SCROLL_MULT | INVERT: 0xFFFFD54F;
			case BUMPY_SPEED | TIPSY_SPEED | ZIGZAG_FREQ | WAVE_SPEED: 0xFF66BB6A;
			case CAM_ZOOM | CAM_MOVE_X | CAM_MOVE_Y | CAM_ANGLE: 0xFFEF9A9A;
			case VISIBLE: 0xFFE0E0E0;
			case RESET: 0xFFEF5350;
			default:
				var s:String = type;
				s.startsWith("win") ? 0xFFCE93D8 : 0xFF90CAF9;
		};
	}

	public static function applyEase(ease:ModEase, t:Float):Float
	{
		t = Math.max(0, Math.min(1, t));
		return switch (ease)
		{
			case LINEAR: t;
			case QUAD_IN: t * t;
			case QUAD_OUT: t * (2 - t);
			case QUAD_IN_OUT: t < .5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
			case CUBE_IN: t * t * t;
			case CUBE_OUT:
				var t1 = t - 1;
				t1 * t1 * t1 + 1;
			case CUBE_IN_OUT: t < .5 ? 4 * t * t * t : (t - 1) * (2 * t - 2) * (2 * t - 2) + 1;
			case SINE_IN: 1 - Math.cos(t * Math.PI / 2);
			case SINE_OUT: Math.sin(t * Math.PI / 2);
			case SINE_IN_OUT: -(Math.cos(Math.PI * t) - 1) / 2;
			case ELASTIC_IN:
				if (t == 0 || t == 1) t else
				{
					var p = 0.3;
					- (Math.pow(2, 10 * (t - 1)) * Math.sin(((t - 1) - p / 4) * (2 * Math.PI) / p));
				}
			case ELASTIC_OUT:
				if (t == 0 || t == 1) t else
				{
					var p = 0.3;
					Math.pow(2, -10 * t) * Math.sin((t - p / 4) * (2 * Math.PI) / p) + 1;
				}
			case BOUNCE_OUT: bounceOut(t);
			case BACK_IN: t * t * ((1.70158 + 1) * t - 1.70158);
			case BACK_OUT:
				var t1 = t - 1;
				t1 * t1 * ((1.70158 + 1) * t1 + 1.70158) + 1;
			case INSTANT: 1.0;
			default: t;
		};
	}

	static function bounceOut(t:Float):Float
	{
		if (t < 1 / 2.75)
			return 7.5625 * t * t;
		else if (t < 2 / 2.75)
		{
			t -= 1.5 / 2.75;
			return 7.5625 * t * t + 0.75;
		}
		else if (t < 2.5 / 2.75)
		{
			t -= 2.25 / 2.75;
			return 7.5625 * t * t + 0.9375;
		}
		else
		{
			t -= 2.625 / 2.75;
			return 7.5625 * t * t + 0.984375;
		}
	}

	public static final ALL_TYPES:Array<ModEventType> = [
		MOVE_X, MOVE_Y, SET_ABS_X, SET_ABS_Y,
		ANGLE, SPIN, ALPHA, SCALE, SCALE_X, SCALE_Y, VISIBLE, RESET,
		DRUNK_X, DRUNK_Y, DRUNK_FREQ,
		TORNADO, CONFUSION,
		ROT_X, ROT_Y,
		SCROLL_MULT, FLIP_X, NOTE_OFFSET_X, NOTE_OFFSET_Y,
		BUMPY, BUMPY_SPEED,
		TIPSY, TIPSY_SPEED, INVERT, ZIGZAG, ZIGZAG_FREQ, WAVE, WAVE_SPEED,
		BEAT_SCALE, STEALTH, NOTE_ALPHA,
		SKEW_X, SKEW_Y, JUMP_Y, JUMP_PERIOD,
		SHAKE_X, SHAKE_Y, SHAKE_SPEED,
		BEAT_SCALE_X, BEAT_SCALE_Y,
		CAM_ZOOM, CAM_MOVE_X, CAM_MOVE_Y, CAM_ANGLE,
		WIN_X, WIN_Y, WIN_SCALE, WIN_SCALE_X, WIN_SCALE_Y, WIN_ALPHA, WIN_RESET,
		WIN_ORBIT, WIN_ORBIT_SPEED, WIN_ORBIT_PHASE, WIN_ORBIT_EX, WIN_ORBIT_EY,
		WIN_SHAKE, WIN_SHAKE_SPEED,
		WIN_BOUNCE, WIN_BOUNCE_FREQ, WIN_BOUNCE_PERIOD,
		WIN_SPIRAL, WIN_SPIRAL_SPEED, WIN_SPIRAL_TIGHT,
		WIN_FIGURE8, WIN_FIGURE8_SPEED,
		WIN_GLITCH, WIN_GLITCH_RATE,
		WIN_WARP, WIN_WARP_PERIOD,
		WIN_SWING, WIN_SWING_SPEED,
		WIN_ZIGZAG, WIN_ZIGZAG_SPEED,
		WIN_PINBALL, WIN_PINBALL_ANGLE,
		WIN_ROLL, WIN_ROLL_SPEED,
		WIN_BEAT_SCALE, WIN_HEARTBEAT,
		WIN_STROBE, WIN_STROBE_RATE, WIN_STROBE_DUTY,
		WIN_ANCHOR, WIN_ANCHOR_X, WIN_ANCHOR_Y, WIN_ANCHOR_MX, WIN_ANCHOR_MY
	];

	public static final ALL_EASES:Array<ModEase> = [
		LINEAR,
		QUAD_IN,
		QUAD_OUT,
		QUAD_IN_OUT,
		CUBE_IN,
		CUBE_OUT,
		CUBE_IN_OUT,
		SINE_IN,
		SINE_OUT,
		SINE_IN_OUT,
		ELASTIC_IN,
		ELASTIC_OUT,
		BOUNCE_OUT,
		BACK_IN,
		BACK_OUT,
		INSTANT
	];

	public static inline function isCameraType(type:ModEventType):Bool
	{
		return switch (type)
		{
			case CAM_ZOOM | CAM_MOVE_X | CAM_MOVE_Y | CAM_ANGLE: true;
			default: false;
		};
	}

	/** Returns true for any WIN_* event type. */
	public static inline function isWindowType(type:ModEventType):Bool
		return (type : String).startsWith("win");

	public static function beatsToSteps(beats:Float, stepsPerBeat:Int = 4):Float
		return beats * stepsPerBeat;

	public static function stepsToBeat(steps:Float, stepsPerBeat:Int = 4):Float
		return steps / stepsPerBeat;

	public static function typeLabel(type:ModEventType):String
	{
		return switch (type)
		{
			case WIN_X: "Window Offset X (px)";
			case WIN_Y: "Window Offset Y (px)";
			case WIN_SCALE: "Window Scale (1=normal)";
			case WIN_SCALE_X: "Window Scale X";
			case WIN_SCALE_Y: "Window Scale Y";
			case WIN_ALPHA: "Window Opacity (0-1)";
			case WIN_RESET: "Window Reset";
			case WIN_ORBIT: "Window Orbit Radius (px)";
			case WIN_ORBIT_SPEED: "Window Orbit Speed (beats/rev)";
			case WIN_ORBIT_PHASE: "Window Orbit Phase";
			case WIN_ORBIT_EX: "Window Orbit Ellipse X";
			case WIN_ORBIT_EY: "Window Orbit Ellipse Y";
			case WIN_SHAKE: "Window Shake Amp (px)";
			case WIN_SHAKE_SPEED: "Window Shake Speed";
			case WIN_BOUNCE: "Window Bounce Amp (px)";
			case WIN_BOUNCE_FREQ: "Window Bounce Freq";
			case WIN_BOUNCE_PERIOD: "Window Bounce Period (beats)";
			case WIN_SPIRAL: "Window Spiral Radius (px)";
			case WIN_SPIRAL_SPEED: "Window Spiral Speed";
			case WIN_SPIRAL_TIGHT: "Window Spiral Tightness";
			case WIN_FIGURE8: "Window Figure-8 Amp (px)";
			case WIN_FIGURE8_SPEED: "Window Figure-8 Speed";
			case WIN_GLITCH: "Window Glitch Amp (px)";
			case WIN_GLITCH_RATE: "Window Glitch Rate";
			case WIN_WARP: "Window Warp Distance (px)";
			case WIN_WARP_PERIOD: "Window Warp Period (beats)";
			case WIN_SWING: "Window Swing Amp (px)";
			case WIN_SWING_SPEED: "Window Swing Speed";
			case WIN_ZIGZAG: "Window Zigzag Amp (px)";
			case WIN_ZIGZAG_SPEED: "Window Zigzag Speed";
			case WIN_PINBALL: "Window Pinball Speed (px/beat)";
			case WIN_PINBALL_ANGLE: "Window Pinball Angle (deg)";
			case WIN_ROLL: "Window Roll Travel (px)";
			case WIN_ROLL_SPEED: "Window Roll Speed";
			case WIN_BEAT_SCALE: "Window Beat Scale Amp";
			case WIN_HEARTBEAT: "Window Heartbeat Amp";
			case WIN_STROBE: "Window Strobe Intensity";
			case WIN_STROBE_RATE: "Window Strobe Rate";
			case WIN_STROBE_DUTY: "Window Strobe Duty";
			case WIN_ANCHOR: "Window Anchor Blend (0-1)";
			case WIN_ANCHOR_X: "Window Anchor X (-1/0/1)";
			case WIN_ANCHOR_Y: "Window Anchor Y (-1/0/1)";
			case WIN_ANCHOR_MX: "Window Anchor Margin X";
			case WIN_ANCHOR_MY: "Window Anchor Margin Y";
			// strum / camera labels (unchanged from before)
			case MOVE_X: "Move X (offset)";
			case MOVE_Y: "Move Y (offset)";
			case SET_ABS_X: "Set X (absolute)";
			case SET_ABS_Y: "Set Y (absolute)";
			case ANGLE: "Angle";
			case ALPHA: "Alpha (0-1)";
			case SCALE: "Scale";
			case SCALE_X: "Scale X";
			case SCALE_Y: "Scale Y";
			case SPIN: "Spin (deg/beat)";
			case RESET: "Reset All";
			case VISIBLE: "Visible (0/1)";
			case DRUNK_X: "Drunk X";
			case DRUNK_Y: "Drunk Y";
			case DRUNK_FREQ: "Drunk Frequency";
			case TORNADO: "Tornado";
			case CONFUSION: "Confusion";
			case ROT_X: "Rotate 3D X (deg)";
			case ROT_Y: "Rotate 3D Y (deg)";
			case SCROLL_MULT: "Scroll Multiplier";
			case FLIP_X: "Flip X";
			case NOTE_OFFSET_X: "Note Offset X";
			case NOTE_OFFSET_Y: "Note Offset Y";
			case BUMPY: "Bumpy Y";
			case BUMPY_SPEED: "Bumpy Speed";
			case TIPSY: "Tipsy X";
			case TIPSY_SPEED: "Tipsy Speed";
			case INVERT: "Invert Scroll";
			case ZIGZAG: "Zigzag X";
			case ZIGZAG_FREQ: "Zigzag Frequency";
			case WAVE: "Wave Y";
			case WAVE_SPEED: "Wave Speed";
			case BEAT_SCALE: "Beat Scale";
			case SKEW_X: "Skew X (lean horizontal, deg)";
			case SKEW_Y: "Skew Y (lean vertical, deg)";
			case JUMP_Y: "Jump Y (hop amplitude, px)";
			case JUMP_PERIOD: "Jump Period (beats per hop)";
			case SHAKE_X: "Shake X (vibración horizontal, px)";
			case SHAKE_Y: "Shake Y (vibración vertical, px)";
			case SHAKE_SPEED: "Shake Speed (oscilaciones/seg)";
			case BEAT_SCALE_X: "Beat Scale X (pulso X por beat)";
			case BEAT_SCALE_Y: "Beat Scale Y (pulso Y por beat)";
			case STEALTH: "Stealth";
			case NOTE_ALPHA: "Note Alpha";
			case CAM_ZOOM: "Camera Zoom";
			case CAM_MOVE_X: "Camera Move X";
			case CAM_MOVE_Y: "Camera Move Y";
			case CAM_ANGLE: "Camera Angle";
			default: type;
		};
	}
}
