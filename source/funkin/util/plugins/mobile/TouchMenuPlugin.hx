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
 * TouchMenuPlugin — 100% touch navigation for menus without VirtualPad.
 *
 * ── GESTURES ────────────────────────────────────────────────────────
 *
 *  ↕  Drag finger up/down   → UP / DOWN  (wheel-style, fires every scrollPixels)
 *  ←→  Swipe left/right      → LEFT / RIGHT  (sliders / tabs)
 *  ☞  Quick tap              → ACCEPT
 *  🔙  Back button (bottom-left) → BACK  (alpha 0.3 at rest → 1.0 when pressed)
 *
 * ── USAGE ───────────────────────────────────────────────────────────
 *
 *  addTouchMenuControls();           // UP/DOWN/LEFT/RIGHT + ACCEPT + BACK
 *  addTouchMenuControls(false);      // no BACK (e.g. PlayState)
 *
 * ── TUNING ──────────────────────────────────────────────────────────
 *
 *  TouchMenuPlugin.scrollPixels   → px per UP/DOWN tick      (def: 28)
 *  TouchMenuPlugin.swipeMinDist   → px min for L/R swipe     (def: 55)
 *  TouchMenuPlugin.swipeMaxTime   → s max for L/R swipe      (def: 0.75)
 *  TouchMenuPlugin.tapMaxDist     → px max for tap/ACCEPT    (def: 10)
 *  TouchMenuPlugin.tapMaxTime     → s max for tap            (def: 0.36)
 *  TouchMenuPlugin.backBtnSize    → back button size in px   (def: 90)
 *  TouchMenuPlugin.backBtnAlpha   → idle alpha               (def: 0.3)
 *  TouchMenuPlugin.showHint       → show hint text on start  (def: true)
 */
class TouchMenuPlugin extends FlxBasic
{
	// ── Public tuning ──────────────────────────────────────────────────

	/** Pixels of vertical drag needed to fire one UP or DOWN (like a mouse-wheel notch). */
	public static var scrollPixels:Float  = 28.0;

	/** Minimum horizontal px for a LEFT/RIGHT swipe. */
	public static var swipeMinDist:Float  = 55.0;

	/** Maximum seconds for a LEFT/RIGHT swipe. */
	public static var swipeMaxTime:Float  = 0.75;

	/** Maximum finger movement in px to count as a tap (ACCEPT). */
	public static var tapMaxDist:Float    = 10.0;

	/** Maximum seconds for a tap. */
	public static var tapMaxTime:Float    = 0.36;

	/** Back button rendered size in screen pixels (square). */
	public static var backBtnSize:Float   = 90.0;

	/** Idle (non-pressed) alpha of the back button. */
	public static var backBtnAlpha:Float  = 0.3;

	public static var showHint:Bool       = true;

	// ── Gesture inputs ─────────────────────────────────────────────────
	var _upInput:GestureInput     = new GestureInput();
	var _downInput:GestureInput   = new GestureInput();
	var _leftInput:GestureInput   = new GestureInput();
	var _rightInput:GestureInput  = new GestureInput();
	var _acceptInput:GestureInput = new GestureInput();
	var _backInput:GestureInput   = new GestureInput();

	// ── Per-finger state ───────────────────────────────────────────────
	var _touchData:Map<Int, TouchData> = new Map();

	// ── Back button ────────────────────────────────────────────────────
	var _backBtn:FlxSprite     = null;
	var _backBtnCam:FlxCamera  = null;
	var _backBtnTween:FlxTween = null;
	/** Touch ID currently pressing the back button (-1 = none). */
	var _backBtnTouchId:Int    = -1;

	// ── Hint text ─────────────────────────────────────────────────────
	var _hint:FlxText       = null;
	var _hintTween:FlxTween = null;
	var _hintCam:FlxCamera  = null;

	static var _hintShown:Bool = false;

	// ── Flags ─────────────────────────────────────────────────────────
	var _includeBack:Bool      = true;
	var _includeLeftRight:Bool = true;

	// ─────────────────────────────────────────────────────────────────

	/**
	 * @param includeBack       Show back button + fire BACK action.
	 * @param includeLeftRight  Enable horizontal swipe for LEFT/RIGHT.
	 */
	public function new(includeBack:Bool = true, includeLeftRight:Bool = true)
	{
		super();
		_includeBack      = includeBack;
		_includeLeftRight = includeLeftRight;
	}

	// ── Controls binding ──────────────────────────────────────────────

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

	// ── Back button (lazy init — stage is ready on first update) ──────

	function _ensureBackButton():Void
	{
		if (_backBtn != null || !_includeBack) return;

		// Dedicated camera so the button stays fixed regardless of game camera
		_backBtnCam = new FlxCamera();
		_backBtnCam.bgColor.alpha = 0;
		FlxG.cameras.add(_backBtnCam, false);

		_backBtn = new FlxSprite();

		try
		{
			var frames = Paths.getSparrowAtlas("mobile/backButton");
			if (frames != null)
			{
				_backBtn.frames = frames;
				// The atlas uses "back0000" … "back0022" — addByPrefix picks them all
				_backBtn.animation.addByPrefix("idle",  "back", 18, true);
				_backBtn.animation.play("idle");
			}
			else
				_makeBackButtonFallback();
		}
		catch (_e:Dynamic)
		{
			_makeBackButtonFallback();
		}

		// Scale to configured size
		_backBtn.setGraphicSize(Std.int(backBtnSize), Std.int(backBtnSize));
		_backBtn.updateHitbox();

		// Position: bottom-left corner, small margin
		var margin:Float  = 16;
		var screenH:Float = FlxG.stage != null ? FlxG.stage.stageHeight : FlxG.height;
		_backBtn.x = margin;
		_backBtn.y = screenH - backBtnSize - margin;

		_backBtn.scrollFactor.set(0, 0);
		_backBtn.alpha   = backBtnAlpha;
		_backBtn.cameras = [_backBtnCam];

		FlxG.state.add(_backBtn);
	}

	inline function _makeBackButtonFallback():Void
	{
		// Simple white rounded square if the atlas is unavailable
		_backBtn.makeGraphic(Std.int(backBtnSize), Std.int(backBtnSize), 0xFFFFFFFF);
	}

	// ── Main update ───────────────────────────────────────────────────

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// Advance each input one frame (clears justPressed set last frame)
		_upInput.tick();
		_downInput.tick();
		_leftInput.tick();
		_rightInput.tick();
		_acceptInput.tick();
		_backInput.tick();

		// Lazy-init the back button on the first update
		_ensureBackButton();

		// Process every active touch
		for (touch in FlxG.touches.list)
		{
			if (touch == null) continue;
			_processTouch(touch, elapsed);
		}

		// Clean up data for touches that have fully ended
		for (id => _ in _touchData)
			if (!_isTouchActive(id))
				_touchData.remove(id);

		// Show the one-shot hint
		if (showHint && !_hintShown)
		{
			_hintShown = true;
			_spawnHint();
		}
	}

	// ── Per-touch logic ───────────────────────────────────────────────

	function _processTouch(touch:FlxTouch, elapsed:Float):Void
	{
		var id = touch.touchPointID;

		// ── Finger down ────────────────────────────────────────────────
		if (touch.justPressed)
		{
			// Check whether the finger lands on the back button hit-zone
			if (_includeBack && _backBtn != null && _isOnBackButton(touch))
			{
				_backBtnTouchId = id;
				_setBackBtnPressed(true);
				return; // do NOT register as a menu-scroll touch
			}

			_touchData.set(id, {
				startX:       touch.screenX,
				startY:       touch.screenY,
				lastY:        touch.screenY,
				lastX:        touch.screenX,
				duration:     0.0,
				maxDist:      0.0,
				scrollAccumY: 0.0,
				gestFired:    false
			});
			return;
		}

		// ── Back button release ────────────────────────────────────────
		if (id == _backBtnTouchId)
		{
			if (touch.justReleased)
			{
				var wasOnBtn = _isOnBackButton(touch);
				_setBackBtnPressed(false);
				_backBtnTouchId = -1;

				if (wasOnBtn)
				{
					_backInput.fire();
					_pulseHint("BACK");
				}
			}
			return;
		}

		// ── Regular menu touch ─────────────────────────────────────────
		var data = _touchData.get(id);
		if (data == null) return;

		data.duration += elapsed;

		var dx   = touch.screenX - data.startX;
		var dy   = touch.screenY - data.startY;
		var dist = Math.sqrt(dx * dx + dy * dy);
		if (dist > data.maxDist)
			data.maxDist = dist;

		// ── Wheel-style vertical scroll ────────────────────────────────
		// Accumulate the raw per-frame pixel delta.
		// Every `scrollPixels` of movement fires one UP or DOWN —
		// exactly like turning a mouse wheel one notch at a time.
		var frameDY  = touch.screenY - data.lastY;
		data.scrollAccumY += frameDY;
		data.lastY = touch.screenY;

		while (data.scrollAccumY <= -scrollPixels)
		{
			data.scrollAccumY += scrollPixels;
			data.gestFired     = true;
			_upInput.fire();
			_pulseHint("↑");
		}
		while (data.scrollAccumY >= scrollPixels)
		{
			data.scrollAccumY -= scrollPixels;
			data.gestFired     = true;
			_downInput.fire();
			_pulseHint("↓");
		}

		// ── On release: tap or horizontal swipe ────────────────────────
		if (touch.justReleased)
		{
			if (!data.gestFired)
				_classifyRelease(data, dx, dy, dist);
			_touchData.remove(id);
		}
	}

	/**
	 * Called on finger release when no wheel-scroll event was fired.
	 * Classifies the gesture as a tap (ACCEPT) or horizontal swipe (LEFT/RIGHT).
	 */
	function _classifyRelease(data:TouchData, dx:Float, dy:Float, dist:Float):Void
	{
		// ── Tap → ACCEPT ───────────────────────────────────────────────
		if (data.maxDist <= tapMaxDist && data.duration <= tapMaxTime)
		{
			_acceptInput.fire();
			_pulseHint("✓");
			return;
		}

		// ── Horizontal swipe → LEFT / RIGHT ───────────────────────────
		if (!_includeLeftRight) return;

		var absDx = Math.abs(dx);
		var absDy = Math.abs(dy);

		// X must clearly dominate Y (ratio 1.4×) and reach the minimum distance
		if (absDx >= swipeMinDist && absDx >= absDy * 1.4 && data.duration <= swipeMaxTime)
		{
			if (dx < 0) { _leftInput.fire();  _pulseHint("←"); }
			else        { _rightInput.fire(); _pulseHint("→"); }
		}
		// Anything else (ambiguous gesture) → silently ignored
	}

	// ── Back button helpers ────────────────────────────────────────────

	/** Returns true if the touch is within the back button hit area. */
	function _isOnBackButton(touch:FlxTouch):Bool
	{
		if (_backBtn == null) return false;
		// Use a slightly larger hit zone than the visual size for comfort
		var hitPad:Float = 20;
		var bx = _backBtn.x - hitPad;
		var by = _backBtn.y - hitPad;
		var bw = backBtnSize + hitPad * 2;
		var bh = backBtnSize + hitPad * 2;
		return touch.screenX >= bx && touch.screenX <= bx + bw
		    && touch.screenY >= by && touch.screenY <= by + bh;
	}

	/** Tweens the back button alpha and switches animation on press/release. */
	function _setBackBtnPressed(pressed:Bool):Void
	{
		if (_backBtn == null) return;

		if (_backBtnTween != null)
		{
			_backBtnTween.cancel();
			_backBtnTween = null;
		}

		var targetAlpha = pressed ? 1.0 : backBtnAlpha;
		_backBtnTween = FlxTween.tween(_backBtn, {alpha: targetAlpha}, 0.10, {
			ease: FlxEase.quadOut,
			onComplete: function(_) { _backBtnTween = null; }
		});
	}

	// ── Generic helpers ───────────────────────────────────────────────

	function _isTouchActive(id:Int):Bool
	{
		for (t in FlxG.touches.list)
			if (t != null && t.touchPointID == id)
				return true;
		return false;
	}

	// ── Hint ─────────────────────────────────────────────────────────

	function _spawnHint():Void
	{
		_hintCam = new FlxCamera();
		_hintCam.bgColor.alpha = 0;
		FlxG.cameras.add(_hintCam, false);

		var hintStr = _includeLeftRight
			? "Drag up/down to scroll  •  Swipe left/right to adjust  •  Tap to confirm"
			: "Drag up/down to scroll  •  Tap to confirm";

		_hint = new FlxText(0, FlxG.height - 80, FlxG.width, hintStr, 13);
		_hint.setFormat("VCR OSD Mono", 13, FlxColor.WHITE,
			CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		_hint.scrollFactor.set(0, 0);
		_hint.cameras = [_hintCam];
		_hint.alpha   = 0;

		FlxG.state.add(_hint);

		FlxTween.tween(_hint, {alpha: 0.85}, 0.4, {
			ease: FlxEase.quadOut,
			onComplete: function(_) {
				FlxTween.tween(_hint, {alpha: 0}, 0.6, {
					startDelay: 3.0,
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
			_hint.alpha   = 0.0;
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
					startDelay: 0.25,
					ease: FlxEase.quadIn,
					onComplete: function(_) { _hintTween = null; }
				});
			}
		});
	}

	// ── Destroy ──────────────────────────────────────────────────────

	override public function destroy():Void
	{
		_touchData.clear();

		if (_backBtnTween != null) { _backBtnTween.cancel(); _backBtnTween = null; }
		if (_hintTween    != null) { _hintTween.cancel();    _hintTween    = null; }
		if (_backBtn      != null) { _backBtn.kill();        _backBtn      = null; }
		if (_hint         != null) { _hint.kill();           _hint         = null; }

		if (_backBtnCam != null)
		{
			FlxG.cameras.remove(_backBtnCam);
			_backBtnCam = null;
		}
		if (_hintCam != null)
		{
			FlxG.cameras.remove(_hintCam);
			_hintCam = null;
		}

		super.destroy();
	}
}

// ═══════════════════════════════════════════════════════════════════════════
//  GestureInput — synthetic IFlxInput fired manually by the gesture detector
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Frame lifecycle:
 *
 *  Frame 0  (fire() called during update):
 *    justPressed = true,  pressed = true
 *
 *  Frame 1  (tick() at start of update):
 *    justReleased = true, released = true
 *
 *  Frame 2+: all false / idle
 */
class GestureInput implements IFlxInput
{
	var _state:Int = 0;  // 0 = idle | 1 = triggered | 2 = releasing

	public var ID(default, null):Int = 0;

	public var justPressed  (get, never):Bool;
	public var pressed      (get, never):Bool;
	public var justReleased (get, never):Bool;
	public var released     (get, never):Bool;

	function get_justPressed():Bool  return _state == 1;
	function get_pressed():Bool      return _state == 1;
	function get_justReleased():Bool return _state == 2;
	function get_released():Bool     return _state == 2 || _state == 0;

	public function new() {}

	/** Trigger the gesture. Call once when the gesture is detected. */
	public inline function fire():Void
		_state = 1;

	/**
	 * Advance one frame.
	 * Call at the very start of each update(), before processing new touches.
	 */
	public inline function tick():Void
	{
		switch (_state)
		{
			case 1: _state = 2;
			case 2: _state = 0;
			default:
		}
	}
}

// ═══════════════════════════════════════════════════════════════════════════
//  TouchData — per-finger state for the duration of a touch
// ═══════════════════════════════════════════════════════════════════════════

private typedef TouchData =
{
	/** Screen X/Y where the finger first landed. */
	startX:       Float,
	startY:       Float,
	/** Position from the previous frame — used for wheel-delta. */
	lastY:        Float,
	lastX:        Float,
	/** Seconds since touch start. */
	duration:     Float,
	/** Maximum distance ever reached from start (used for tap detection). */
	maxDist:      Float,
	/** Sub-tick vertical accumulator for the wheel simulation. */
	scrollAccumY: Float,
	/** True if any directional event was already fired for this touch. */
	gestFired:    Bool,
}
#end
