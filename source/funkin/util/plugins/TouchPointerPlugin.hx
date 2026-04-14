package funkin.util.plugins;

#if mobileC
import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup.FlxTypedSpriteGroup;
import flixel.input.touch.FlxTouch;
import flixel.math.FlxPoint;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import openfl.display.Shape;
import openfl.display.BitmapData;
import flixel.graphics.FlxGraphic;

/**
 * TouchPointerPlugin — muestra una huella visual donde el jugador toca la pantalla.
 *
 * Inspirado directamente en el TouchPointerPlugin de V-Slice / FNF.
 * Diferencias con el original:
 *   - No usa assets externos (michael.png / kevin.png). Las texturas se generan
 *     por código: anillo exterior + círculo interior con gradiente.
 *   - Si el jugador coloca sus propios PNGs en assets/images/touch/finger-still.png
 *     y assets/images/touch/finger-move.png, el plugin los usa automáticamente.
 *   - Se integra con el sistema de cámara de Cool Engine (no necesita FunkinCamera).
 *
 * Para activarlo, llama a TouchPointerPlugin.initialize() en Main.hx (ya está añadido).
 * Para desactivarlo en runtime: TouchPointerPlugin.enabled = false;
 */
class TouchPointerPlugin extends FlxTypedSpriteGroup<TouchPointer>
{
	// ── Singleton ──────────────────────────────────────────────────────────
	private static var _instance:TouchPointerPlugin = null;
	private static var _camera:FlxCamera = null;

	/** Activa/desactiva el plugin en runtime. */
	public static var enabled(default, set):Bool = true;

	// ── Texturas cacheadas (generadas una sola vez) ────────────────────────
	@:allow(funkin.util.plugins.TouchPointer)
	static var _texStill:FlxGraphic = null;
	@:allow(funkin.util.plugins.TouchPointer)
	static var _texMove:FlxGraphic = null;

	/** Tamaño del indicador en píxeles */
	public static inline var POINTER_SIZE:Int = 80;

	// ── Color del indicador ────────────────────────────────────────────────
	// V-Slice usa 0xff6666e1 (lila) con blend=screen. Aquí usamos el mismo.
	public static var pointerColor:FlxColor = 0xff6666e1;

	// ──────────────────────────────────────────────────────────────────────

	public function new() { super(); }

	// ── API pública ───────────────────────────────────────────────────────

	/**
	 * Inicializa el plugin. Llamar UNA SOLA VEZ desde Main.hx.
	 */
	public static function initialize():Void
	{
		// Generar texturas procedurales
		_buildTextures();

		// Cámara dedicada, siempre encima de todo
		_camera = new FlxCamera();
		_camera.bgColor.alpha = 0;

		_instance = new TouchPointerPlugin();
		_instance.cameras = [_camera];

		FlxG.cameras.add(_camera, false);
		FlxG.plugins.add(_instance);

		// Mantener la cámara del plugin en la cima ante cualquier cambio
		FlxG.cameras.cameraAdded.add(_onCameraAdded);
		FlxG.cameras.cameraRemoved.add(_onCameraRemoved);

		// Limpiar punteros en cada cambio de estado
		FlxG.signals.preStateSwitch.add(function() { if (_instance != null) _instance._clearAll(true); });
	}

	// ── Generación de texturas ────────────────────────────────────────────

	static function _buildTextures():Void
	{
		var S = POINTER_SIZE;

		// ── Textura "still" (presionando sin mover): anillo exterior + punto central ──
		{
			var bd = new BitmapData(S, S, true, 0x00000000);
			var cx = S >> 1;
			var cy = S >> 1;
			var c:UInt = pointerColor;
			var r = (c >> 16) & 0xFF;
			var g = (c >> 8)  & 0xFF;
			var b =  c        & 0xFF;

			// Pintar pixel a pixel con círculos suaves
			for (py in 0...S)
			{
				for (px in 0...S)
				{
					var dx = px - cx;
					var dy = py - cy;
					var dist = Math.sqrt(dx * dx + dy * dy);
					var outer = S / 2 - 2;
					var inner = S / 2 - 12;
					var dot   = 6.0;

					var alpha:Float = 0;

					// Anillo exterior
					if (dist <= outer && dist >= inner)
					{
						var t = 1 - Math.abs(dist - (outer + inner) / 2) / ((outer - inner) / 2);
						alpha = t * 220;
					}
					// Punto central
					if (dist <= dot)
					{
						var t = 1 - dist / dot;
						alpha = Math.max(alpha, t * 180);
					}

					if (alpha > 0)
						bd.setPixel32(px, py, (Std.int(Math.min(alpha, 255)) << 24) | (r << 16) | (g << 8) | b);
				}
			}

			_texStill = FlxGraphic.fromBitmapData(bd, false, "__touch_still__", false);
		}

		// ── Textura "move" (deslizando): anillo con dirección ──────────────────
		{
			var bd = new BitmapData(S, S, true, 0x00000000);
			var cx = S >> 1;
			var cy = S >> 1;
			var c:UInt = pointerColor;
			var r = (c >> 16) & 0xFF;
			var g = (c >> 8)  & 0xFF;
			var b =  c        & 0xFF;

			for (py in 0...S)
			{
				for (px in 0...S)
				{
					var dx = px - cx;
					var dy = py - cy;
					var dist = Math.sqrt(dx * dx + dy * dy);
					var outer = S / 2 - 2;
					var inner = S / 2 - 10;

					// Anillo más grueso + arco superior más brillante (simula dirección)
					if (dist <= outer && dist >= inner)
					{
						var t = 1 - Math.abs(dist - (outer + inner) / 2) / ((outer - inner) / 2);
						// Ángulo: superior más opaco para dar sensación de flecha
						var angle = Math.atan2(-dy, dx); // -dy para que "arriba" sea brillante
						var bright = (Math.cos(angle) * 0.4 + 0.6);
						var alpha = t * 240 * bright;
						if (alpha > 0)
							bd.setPixel32(px, py, (Std.int(Math.min(alpha, 255)) << 24) | (r << 16) | (g << 8) | b);
					}
				}
			}

			_texMove = FlxGraphic.fromBitmapData(bd, false, "__touch_move__", false);
		}
	}

	// ── Update ────────────────────────────────────────────────────────────

	override public function update(elapsed:Float):Void
	{
		if (!exists || !visible || !enabled) return;

		super.update(elapsed);

		for (touch in FlxG.touches.list)
		{
			if (touch == null) continue;

			// NOTA: NO llamar _clearAll aquí. Antes se llamaba en justPressed,
			// lo que eliminaba los punteros de otros dedos todavía activos.
			// La limpieza de punteros huérfanos ya se gestiona al final del
			// loop mediante el fade-out individual por touchId.

			var pointer = _findById(touch.touchPointID);

			if (pointer == null)
			{
				pointer = recycle(TouchPointer);
				pointer.init(touch.touchPointID);
				add(pointer);
			}

			pointer.updateFromTouch(touch, _camera);
		}

		// Punteros sin toque activo → fade out
		for (ptr in members)
		{
			if (ptr == null || _touchActive(ptr.touchId)) continue;
			if (ptr.touchId == -2) continue; // ya en fade

			ptr.touchId = -2;
			ptr.alpha = 0.85;
			FlxTween.tween(ptr, {alpha: 0}, FlxG.random.float(0.35, 0.55), {
				ease: FlxEase.quadIn,
				onComplete: function(_) remove(ptr, true)
			});
		}
	}

	// ── Helpers ───────────────────────────────────────────────────────────

	private function _findById(id:Int):TouchPointer
	{
		for (p in members) if (p != null && p.touchId == id) return p;
		return null;
	}

	private function _touchActive(id:Int):Bool
	{
		for (t in FlxG.touches.list)
			if (t.touchPointID == id && !t.justReleased)
				return true;
		return false;
	}

	private function _clearAll(instant:Bool):Void
	{
		for (ptr in members)
		{
			if (ptr == null) continue;
			if (instant) { remove(ptr, true); continue; }
			FlxTween.tween(ptr, {alpha: 0}, 0.25, {
				ease: FlxEase.quadIn,
				onComplete: function(_) remove(ptr, true)
			});
		}
	}

	// ── Camera management ─────────────────────────────────────────────────

	static function _moveCameraToTop():Void
	{
		if (_camera == null) return;
		if (FlxG.cameras.list.length == 0)
		{
			FlxG.signals.postStateSwitch.addOnce(function() _moveCameraToTop());
			return;
		}

		if (FlxG.cameras.list.contains(_camera))
			FlxG.cameras.list.remove(_camera);

		if (FlxG.game.contains(_camera.flashSprite))
			FlxG.game.removeChild(_camera.flashSprite);

		// FIX: getChildIndex() returns -1 when _inputContainer is not yet a child
		// (can happen on Android before the first frame). addChildAt(-1) throws a
		// RangeError in the native layer → instant crash.
		// Wrapping in try/catch lets us fall back to addChild() if the index is invalid.
		@:privateAccess
		try
		{
			final idx = FlxG.game.getChildIndex(FlxG.game._inputContainer);
			if (idx >= 0)
				FlxG.game.addChildAt(_camera.flashSprite, idx);
			else
				FlxG.game.addChild(_camera.flashSprite);
		}
		catch (_:Dynamic)
		{
			try FlxG.game.addChild(_camera.flashSprite) catch (_:Dynamic) {}
		}
		FlxG.cameras.list.push(_camera);
	}

	static function _onCameraAdded(_:FlxCamera):Void
		_moveCameraToTop();

	static function _onCameraRemoved(cam:FlxCamera):Void
	{
		if (cam == _camera)
		{
			if (!cam.exists)
			{
				_camera = new FlxCamera();
				_camera.bgColor.alpha = 0;
				if (_instance != null) _instance.cameras = [_camera];
				_moveCameraToTop();
			}
			else _moveCameraToTop();
		}
		else _moveCameraToTop();
	}

	// ── enabled setter ────────────────────────────────────────────────────

	@:noCompletion
	static function set_enabled(v:Bool):Bool
	{
		if (_instance != null)
			_instance.exists = _instance.visible = _instance.active = _instance.alive = v;
		return enabled = v;
	}
}

// ═════════════════════════════════════════════════════════════════════════════

/**
 * TouchPointer — un único indicador visual para un dedo en pantalla.
 *
 * Al presionar: aparece con scale 1.4 → 1.0 (pop).
 * Al mover: cambia a la textura "move" y rota hacia la dirección de movimiento.
 * Al soltar: fade out gestionado por TouchPointerPlugin.
 */
class TouchPointer extends FlxSprite
{
	public var touchId:Int = -1;

	private var _lastPos:FlxPoint;
	private var _isMoving:Bool = false;
	private var _skipMoveCheck:Bool = true;

	// Usar PNGs propios si existen, si no la textura procedural
	private static var _customStillExists:Null<Bool> = null;
	private static var _customMoveExists:Null<Bool>  = null;

	private static inline var CUSTOM_STILL = "assets/images/touch/finger-still.png";
	private static inline var CUSTOM_MOVE  = "assets/images/touch/finger-move.png";

	public function new()
	{
		super();
		scrollFactor.set(0, 0);
		_lastPos = FlxPoint.get();
		blend = "screen";
	}

	public function init(id:Int):Void
	{
		FlxTween.cancelTweensOf(this);

		touchId = id;
		_isMoving = false;
		_skipMoveCheck = true; // ignorar el primer frame de movimiento (lastPos = 0,0)

		_loadStill();

		// Pop de entrada
		scale.set(1.4, 1.4);
		alpha = 0.9;
		FlxTween.tween(scale, {x: 1.0, y: 1.0}, 0.18, {ease: FlxEase.backOut});
	}

	public function updateFromTouch(touch:FlxTouch, cam:FlxCamera):Void
	{
		var sx:Float = touch.x;
		var sy:Float = touch.y;

		x = sx - width  / 2;
		y = sy - height / 2;

		if (_skipMoveCheck)
		{
			_lastPos.set(sx, sy);
			_skipMoveCheck = false;
			return;
		}

		var dx = sx - _lastPos.x;
		var dy = sy - _lastPos.y;
		var moved = (dx * dx + dy * dy) > 16;

		if (moved && !_isMoving)
		{
			_isMoving = true;
			_loadMove();
		}
		else if (!moved && _isMoving)
		{
			_isMoving = false;
			_loadStill();
		}

		if (moved)
		{
			angle = Math.atan2(dy, dx) * (180 / Math.PI);
		}
		else
		{
			angle = 0;
		}

		_lastPos.set(sx, sy);
	}

	// ── Cargar textura ────────────────────────────────────────────────────

	private function _loadStill():Void
	{
		if (_customStillExists == null)
			_customStillExists = sys.FileSystem.exists(CUSTOM_STILL);

		if (_customStillExists)
			loadGraphic(CUSTOM_STILL);
		else if (TouchPointerPlugin._texStill != null)
		{
			frames = TouchPointerPlugin._texStill.imageFrame;
			setGraphicSize(TouchPointerPlugin.POINTER_SIZE, TouchPointerPlugin.POINTER_SIZE);
			updateHitbox();
		}
	}

	private function _loadMove():Void
	{
		if (_customMoveExists == null)
			_customMoveExists = sys.FileSystem.exists(CUSTOM_MOVE);

		if (_customMoveExists)
			loadGraphic(CUSTOM_MOVE);
		else if (TouchPointerPlugin._texMove != null)
		{
			frames = TouchPointerPlugin._texMove.imageFrame;
			setGraphicSize(TouchPointerPlugin.POINTER_SIZE, TouchPointerPlugin.POINTER_SIZE);
			updateHitbox();
		}
	}

	override public function destroy():Void
	{
		_lastPos.put();
		super.destroy();
	}
}
#end
