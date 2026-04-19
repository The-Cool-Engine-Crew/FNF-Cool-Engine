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
import funkin.gameplay.controls.Controls.Control;
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
	public static var swipeMinDist:Float  = 32.0;  // px mínimos para considerar swipe (bajado de 48 — más sensible)
	public static var swipeMaxTime:Float  = 0.75;  // s máximos del swipe (subido de 0.5 — más margen para swipes lentos)
	public static var tapMaxDist:Float    = 10.0;  // px máximos para un tap (bajado de 28 — evita confundir swipes con ACCEPT)
	public static var tapMaxTime:Float    = 0.36;  // s máximos de un tap
	public static var holdBackTime:Float  = 1.20;  // s para BACK por mantener (subido de 1.0)
	/** Si el dedo se movió más de este umbral en cualquier momento, hold-back no se lanza. */
	public static var holdBackMoveGuard:Float = 14.0;
	public static var backEdgeZone:Float  = 55.0;
	/** Ratio mínimo para que un eje domine. |dy|/|dx| >= vertBias → vertical. */
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
				backFired: false,
				gestFired: false
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
		// holdBackMoveGuard impide que el hold-back se lance si el dedo
		// se movió aunque sea un poco — evita BACK accidental al inicio de un swipe lento.
		if (_includeBack && !data.backFired
		 && data.duration >= holdBackTime
		 && data.maxDist  <  holdBackMoveGuard)
		{
			data.backFired = true;
			data.gestFired = true;
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
		var screenW:Float = FlxG.stage != null ? FlxG.stage.stageWidth : FlxG.width;
		if (_includeBack
		 && data.startX > screenW - backEdgeZone
		 && dx < -45
		 && Math.abs(dx) > Math.abs(dy))
		{
			_backInput.fire();
			_pulseHint("BACK ←");
			return;
		}

		var absDx = Math.abs(dx);
		var absDy = Math.abs(dy);

		// ── Swipe ──────────────────────────────────────────────────────
		// Se considera swipe si el dedo alcanzó la distancia mínima en el tiempo permitido.
		// Si el tiempo se excedió pero el movimiento es grande y claro, también se acepta
		// como swipe lento (evita que swipes deliberados caigan a ACCEPT o BACK).
		var isSwipe    = data.maxDist >= swipeMinDist && data.duration <= swipeMaxTime;
		var isSlowSwipe = data.maxDist >= swipeMinDist * 1.8 && !isSwipe; // swipe lento pero grande y claro

		if (isSwipe || isSlowSwipe)
		{
			// Si el dedo volvió atrás más del 60%, el vector final es poco fiable.
			// Solo descartamos si el gesto no es lo suficientemente claro.
			if (dist < swipeMinDist * 0.35 && !isSlowSwipe)
				return;

			// Para swipes lentos, usamos la posición del máximo desplazamiento implícito
			// (el vector dx/dy sigue siendo la mejor aproximación de la dirección).
			// Si el pullback es extremo en swipe lento, también descartamos.
			if (isSlowSwipe && dist < swipeMinDist * 0.25)
				return;

			// Eje vertical domina → UP / DOWN
			if (absDy >= absDx * vertBias)
			{
				if (dy < 0) { _upInput.fire();  _pulseHint("↑"); }
				else        { _downInput.fire(); _pulseHint("↓"); }
				return;
			}

			// Eje horizontal domina → LEFT / RIGHT
			if (_includeLeftRight && absDx >= absDy * vertBias)
			{
				if (dx < 0) { _leftInput.fire();  _pulseHint("←"); }
				else        { _rightInput.fire(); _pulseHint("→"); }
				return;
			}

			// Diagonal: resolver al eje dominante (nunca silenciar el gesto)
			if (absDy >= absDx)
			{
				if (dy < 0) { _upInput.fire();  _pulseHint("↑"); }
				else        { _downInput.fire(); _pulseHint("↓"); }
			}
			else if (_includeLeftRight)
			{
				if (dx < 0) { _leftInput.fire();  _pulseHint("←"); }
				else        { _rightInput.fire(); _pulseHint("→"); }
			}
			return; // fue un swipe — nunca convertir a tap
		}

		// ── Tap → ACCEPT ───────────────────────────────────────────────
		// tapMaxDist es pequeño (10px) para que solo los taps deliberados
		// disparen ACCEPT — cualquier intento de swipe queda fuera de este umbral.
		if (data.maxDist <= tapMaxDist && data.duration <= tapMaxTime)
		{
			_acceptInput.fire();
			_pulseHint("✓");
		}
		// Si maxDist está entre tapMaxDist y swipeMinDist: gesto ambiguo → ignorar.
		// Mejor no hacer nada que disparar la acción equivocada.
	}

	// ── Helpers ──────────────────────────────────────────────────────────

	function _isTouchActive(id:Int):Bool
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

	function get_justPressed():Bool  return _state == 1;
	function get_pressed():Bool      return _state == 1;
	function get_justReleased():Bool return _state == 2;
	function get_released():Bool     return _state == 2 || _state == 0;

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
	/** true si ya se clasificó un gesto (swipe o hold-back) — impide que el
	 *  mismo toque también dispare ACCEPT al soltarse. */
	gestFired: Bool,
}
#end
