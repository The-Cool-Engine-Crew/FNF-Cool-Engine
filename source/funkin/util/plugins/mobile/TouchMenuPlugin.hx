package funkin.util.plugins.mobile;

#if mobileC
import flixel.FlxBasic;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.input.IFlxInput;
import flixel.input.touch.FlxTouch;
import flixel.input.actions.FlxActionInput;
import flixel.input.actions.FlxActionInputDigital;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.FlxCamera;
import funkin.gameplay.controls.Controls;
import funkin.gameplay.controls.Control;
import data.PlayerSettings;

/**
 * TouchMenuPlugin — navegación 100% táctil en menús sin VirtualPad.
 *
 * ── GESTOS SOPORTADOS ───────────────────────────────────────────────
 *
 *  ↑  Deslizar hacia arriba    → UP     (subir en el menú)
 *  ↓  Deslizar hacia abajo     → DOWN   (bajar en el menú)
 *  ←  Deslizar hacia izquierda → LEFT   (ajustar valor / tab anterior)
 *  →  Deslizar hacia derecha   → RIGHT  (ajustar valor / tab siguiente)
 *  ☞  Toque rápido (tap)       → ACCEPT (confirmar / seleccionar)
 *  ←  Deslizar desde borde derecho → BACK  (volver)
 *  ⏱  Mantener ~0.7 s quieto   → BACK  (volver)
 *
 * ── USO ────────────────────────────────────────────────────────────
 *
 *  Desde MusicBeatState (sustituto directo de addVirtualPad):
 *
 *    addTouchMenuControls();           // UP/DOWN/LEFT/RIGHT + ACCEPT + BACK
 *    addTouchMenuControls(false);      // sin BACK (p.ej. PlayState)
 *
 *  El sistema de controles (controls.UP_P / controls.LEFT_P / controls.ACCEPT …)
 *  funciona exactamente igual que con VirtualPad — no hay que cambiar nada
 *  en el código de cada menú.
 *
 * ── PERSONALIZACIÓN ─────────────────────────────────────────────────
 *
 *  TouchMenuPlugin.swipeMinDist   → px mínimos para considerar swipe  (def: 55)
 *  TouchMenuPlugin.swipeMaxTime   → s máximos del swipe               (def: 0.45)
 *  TouchMenuPlugin.tapMaxDist     → px máximos de movimiento para tap (def: 22)
 *  TouchMenuPlugin.tapMaxTime     → s máximos de un tap               (def: 0.32)
 *  TouchMenuPlugin.holdBackTime   → s para BACK por mantener          (def: 0.70)
 *  TouchMenuPlugin.backEdgeZone   → anchura del borde derecho p/BACK  (def: 55)
 *  TouchMenuPlugin.vertBias       → ratio para resolver swipes diagonales (def: 1.2)
 *  TouchMenuPlugin.showHint       → mostrar texto de ayuda             (def: true)
 */
class TouchMenuPlugin extends FlxBasic
{
	// ── Configuración pública ───────────────────────────────────────────
	public static var swipeMinDist:Float  = 55.0;
	public static var swipeMaxTime:Float  = 0.45;
	public static var tapMaxDist:Float    = 22.0;
	public static var tapMaxTime:Float    = 0.32;
	public static var holdBackTime:Float  = 0.70;
	public static var backEdgeZone:Float  = 55.0;
	/** Ratio mínimo para que un eje domine. |dy|/|dx| >= vertBias → vertical.
	 *  |dx|/|dy| >= vertBias → horizontal. Diagonales ambiguas se ignoran. */
	public static var vertBias:Float      = 1.2;
	public static var showHint:Bool       = true;

	// ── Inputs de gesto (uno por acción) ────────────────────────────────
	var _upInput:GestureInput     = new GestureInput();
	var _downInput:GestureInput   = new GestureInput();
	var _leftInput:GestureInput   = new GestureInput();
	var _rightInput:GestureInput  = new GestureInput();
	var _acceptInput:GestureInput = new GestureInput();
	var _backInput:GestureInput   = new GestureInput();

	// ── Seguimiento de cada dedo ─────────────────────────────────────────
	var _touchData:Map<Int, TouchData> = new Map();

	// ── Hint visual ──────────────────────────────────────────────────────
	var _hint:FlxText       = null;
	var _hintTween:FlxTween = null;
	var _hintCam:FlxCamera  = null;

	static var _hintShown:Bool = false;

	// ── Flags de qué acciones incluir ───────────────────────────────────
	var _includeBack:Bool      = true;
	var _includeLeftRight:Bool = true;

	// ────────────────────────────────────────────────────────────────────

	/**
	 * @param includeBack       Si true, swipe desde borde / hold largo = BACK.
	 * @param includeLeftRight  Si true, swipes horizontales generan LEFT/RIGHT.
	 *                          Necesario para OptionsMenu (sliders, tabs).
	 */
	public function new(includeBack:Bool = true, includeLeftRight:Bool = true)
	{
		super();
		_includeBack      = includeBack;
		_includeLeftRight = includeLeftRight;
	}

	// ── Inyección en Controls ────────────────────────────────────────────

	/**
	 * Registra los GestureInputs en el sistema de controles del jugador.
	 * Llamar después de new() y antes de add().
	 */
	public function bindToControls(?controls:Controls):Void
	{
		if (controls == null)
			controls = PlayerSettings.player1.controls;

		controls.bindGestureInput(Control.UP,     _upInput);
		controls.bindGestureInput(Control.DOWN,   _downInput);
		if (_includeLeftRight)
		{
			controls.bindGestureInput(Control.LEFT,  _leftInput);
			controls.bindGestureInput(Control.RIGHT, _rightInput);
		}
		controls.bindGestureInput(Control.ACCEPT, _acceptInput);
		if (_includeBack)
			controls.bindGestureInput(Control.BACK, _backInput);
	}

	// ── Update ───────────────────────────────────────────────────────────

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// Avanzar estado de cada input (limpia justPressed del frame anterior)
		_upInput.tick();
		_downInput.tick();
		_leftInput.tick();
		_rightInput.tick();
		_acceptInput.tick();
		_backInput.tick();

		// Procesar todos los toques activos
		for (touch in FlxG.touches.list)
		{
			if (touch == null) continue;
			_processTouch(touch, elapsed);
		}

		// Eliminar datos de toques que ya terminaron
		for (id => _ in _touchData)
			if (!_isTouchActive(id))
				_touchData.remove(id);

		// Hint: mostrar la primera vez
		if (showHint && !_hintShown)
		{
			_hintShown = true;
			_spawnHint();
		}
	}

	// ── Procesado de cada dedo ───────────────────────────────────────────

	function _processTouch(touch:FlxTouch, elapsed:Float):Void
	{
		var id = touch.touchPointID;

		// ── Inicio de toque ────────────────────────────────────────────
		if (touch.justPressed)
		{
			_touchData.set(id, {
				startX:    touch.screenX,
				startY:    touch.screenY,
				duration:  0.0,
				maxDist:   0.0,
				backFired: false
			});
			return;
		}

		var data = _touchData.get(id);
		if (data == null) return;

		// ── Actualizar métricas del toque ──────────────────────────────
		data.duration += elapsed;

		var dx   = touch.screenX - data.startX;
		var dy   = touch.screenY - data.startY;
		var dist = Math.sqrt(dx * dx + dy * dy);
		if (dist > data.maxDist)
			data.maxDist = dist;

		// ── BACK por mantener quieto ───────────────────────────────────
		if (_includeBack && !data.backFired
		 && data.duration >= holdBackTime
		 && data.maxDist  <  tapMaxDist)
		{
			data.backFired = true;
			_backInput.fire();
			_pulseHint("BACK ←");
		}

		// ── Al soltar el dedo ──────────────────────────────────────────
		if (touch.justReleased)
		{
			if (!data.backFired)
				_classifyGesture(data, dx, dy, dist);
			_touchData.remove(id);
		}
	}

	function _classifyGesture(data:TouchData, dx:Float, dy:Float, dist:Float):Void
	{
		// ── BACK desde borde derecho ───────────────────────────────────
		if (_includeBack
		 && data.startX > FlxG.width - backEdgeZone
		 && dx < -45)
		{
			_backInput.fire();
			_pulseHint("BACK ←");
			return;
		}

		// ── Swipe (cualquier dirección) ────────────────────────────────
		if (dist >= swipeMinDist && data.duration <= swipeMaxTime)
		{
			var absDx = Math.abs(dx);
			var absDy = Math.abs(dy);

			// Eje vertical domina → UP / DOWN
			if (absDy >= absDx * vertBias)
			{
				if (dy < 0) { _upInput.fire();   _pulseHint("↑"); }
				else        { _downInput.fire();  _pulseHint("↓"); }
				return;
			}

			// Eje horizontal domina → LEFT / RIGHT
			if (_includeLeftRight && absDx >= absDy * vertBias)
			{
				if (dx < 0) { _leftInput.fire();  _pulseHint("←"); }
				else        { _rightInput.fire(); _pulseHint("→"); }
				return;
			}

			// Diagonal ambigua — ignorar para no confundir UP con LEFT, etc.
			return;
		}

		// ── Tap → ACCEPT ───────────────────────────────────────────────
		if (data.maxDist <= tapMaxDist && data.duration <= tapMaxTime)
		{
			_acceptInput.fire();
			_pulseHint("✓");
		}
	}

	// ── Helpers ──────────────────────────────────────────────────────────

	inline function _isTouchActive(id:Int):Bool
	{
		for (t in FlxG.touches.list)
			if (t != null && t.touchPointID == id)
				return true;
		return false;
	}

	// ── Hint visual ──────────────────────────────────────────────────────

	function _spawnHint():Void
	{
		_hintCam = new FlxCamera();
		_hintCam.bgColor.alpha = 0;
		FlxG.cameras.add(_hintCam, false);

		var hintStr = _includeLeftRight
			? "UP/DOWN Scroll - LEFT/RIGHT Adjust - Touch (check) - Hold ← Back"
			: "UP/DOWN Slide - Touch (check) - Hold ←  Back";

		_hint = new FlxText(0, FlxG.height - 80, FlxG.width, hintStr, 13);
		_hint.setFormat("VCR OSD Mono", 13, FlxColor.WHITE,
			CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		_hint.scrollFactor.set(0, 0);
		_hint.cameras = [_hintCam];
		_hint.alpha = 0;

		FlxG.state.add(_hint);

		FlxTween.tween(_hint, {alpha: 0.85}, 0.4, {
			ease: FlxEase.quadOut,
			onComplete: function(_) {
				FlxTween.tween(_hint, {alpha: 0}, 0.6, {
					startDelay: 2.5,
					ease: FlxEase.quadIn,
					onComplete: function(_) { _hint.kill(); }
				});
			}
		});
	}

	function _pulseHint(label:String):Void
	{
		if (!showHint) return;

		if (_hint == null || !_hint.alive)
		{
			if (_hintCam == null)
			{
				_hintCam = new FlxCamera();
				_hintCam.bgColor.alpha = 0;
				FlxG.cameras.add(_hintCam, false);
			}

			_hint = new FlxText(0, FlxG.height / 2 - 30, FlxG.width, label, 36);
			_hint.setFormat("VCR OSD Mono", 36, FlxColor.WHITE,
				CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			_hint.scrollFactor.set(0, 0);
			_hint.cameras = [_hintCam];
			_hint.alpha = 0.0;
			FlxG.state.add(_hint);
		}
		else
		{
			_hint.text  = label;
			_hint.alpha = 0.0;
			if (_hintTween != null) { _hintTween.cancel(); _hintTween = null; }
		}

		_hintTween = FlxTween.tween(_hint, {alpha: 0.75}, 0.12, {
			ease: FlxEase.quadOut,
			onComplete: function(_) {
				_hintTween = FlxTween.tween(_hint, {alpha: 0.0}, 0.35, {
					startDelay: 0.3,
					ease: FlxEase.quadIn,
					onComplete: function(_) { _hintTween = null; }
				});
			}
		});
	}

	// ── Destroy ──────────────────────────────────────────────────────────

	override public function destroy():Void
	{
		_touchData.clear();
		if (_hintTween != null) { _hintTween.cancel(); _hintTween = null; }
		if (_hint != null)      { _hint.kill(); _hint = null; }
		if (_hintCam != null)
		{
			FlxG.cameras.remove(_hintCam);
			_hintCam = null;
		}
		super.destroy();
	}
}

// ═══════════════════════════════════════════════════════════════════════════
//  GestureInput — IFlxInput accionado manualmente por el detector de gestos
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Input sintético compatible con IFlxInput / FlxActionInputDigitalIFlxInput.
 *
 * Ciclo de vida en frames:
 *
 *  Frame 0 (fire() llamado en update):
 *    justPressed = true   pressed = true   justReleased = false   released = false
 *
 *  Frame 1 (tick() al inicio del update):
 *    justPressed = false  pressed = false  justReleased = true    released = true
 *
 *  Frame 2+:
 *    todo = false
 */
class GestureInput implements IFlxInput
{
	// ── Estado interno (máquina de 3 estados) ────────────────────────────
	// 0 = idle, 1 = triggered-this-frame, 2 = releasing

	var _state:Int = 0;

	public var ID(default, null):Int = 0;

	// ── IFlxInput API ────────────────────────────────────────────────────

	public var justPressed  (get, never):Bool;
	public var pressed      (get, never):Bool;
	public var justReleased (get, never):Bool;
	public var released     (get, never):Bool;

	inline function get_justPressed():Bool  return _state == 1;
	inline function get_pressed():Bool      return _state == 1;
	inline function get_justReleased():Bool return _state == 2;
	inline function get_released():Bool     return _state == 2 || _state == 0;

	public function new() {}

	// ── API para el plugin ───────────────────────────────────────────────

	/** Dispara el gesto — llámalo una vez cuando el gesto se detecta. */
	public inline function fire():Void
		_state = 1;

	/**
	 * Avanza el estado en un frame.
	 * Llama esto al inicio de cada update() del plugin,
	 * ANTES de procesar nuevos toques.
	 */
	public inline function tick():Void
	{
		switch (_state)
		{
			case 1: _state = 2;  // triggered → releasing
			case 2: _state = 0;  // releasing → idle
			default:             // idle → idle
		}
	}
}

// ═══════════════════════════════════════════════════════════════════════════
//  TouchData — datos internos de cada toque en vuelo
// ═══════════════════════════════════════════════════════════════════════════

private typedef TouchData =
{
	startX:    Float,
	startY:    Float,
	duration:  Float,
	maxDist:   Float,
	backFired: Bool,
}
#end
