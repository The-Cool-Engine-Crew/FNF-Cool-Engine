package funkin.util.plugins.mobile;

import flixel.FlxG;
import funkin.data.SaveData;
#if FEATURE_HAPTICS
import extension.haptics.Haptic;
#end

/**
 * VibrationManager — Haptic feedback unificado para móviles y mandos.
 *
 * ─── Mobile Implementation ────────────────────────────────────────────────────
 *
 *   Use `extension-haptics` (same as V-Slice), NOT lime.system.System.vibrate().
 * 	 Requires the FEATURE_HAPTICS build flag and the haxelib installed.
 *
 *   Extension API:
 * 	 Haptic.vibrateOneShot(duration, amplitude, sharpness)
 * 	 duration — duration in seconds
 * 	 amplitude — intensity 0.0 … 1.0
 * 	 sharpness — haptic texture 0.0 (soft) … 1.0 (sharp)
 * 	 Haptic.vibratePattern(durations[], amplitudes[], sharpnesses[])
 * 	 parallel arrays for complex patterns (available if needed).
 *
 * ─── Supported platforms ────────────────────────────────────────────────
 *
 *   GAMEPAD (DualShock 4/5, Xbox One/Series, Switch Pro, etc.)
 *     Uses `FlxGamepad.setMotion(leftStr, rightStr, duration)`.
 *     Respects `SaveData.data.gamepadRumble`.
 *     Motor strength is scaled by `SaveData.data.vibrationIntensity`.
 *
 * ─── Basic usage ─────────────────────────────────────────────────────────────
 *
 *   VibrationManager.vibrateTap();      // note hit (light)
 *   VibrationManager.vibrateBeat();     // section change (medium)
 *   VibrationManager.vibrateMiss();     // missed note (strong)
 *   VibrationManager.vibrateConfirm();  // menu confirm action
 *   VibrationManager.vibrate(80);       // custom duration in ms

 * @author  Cool Engine Team
 * @since   0.6.1
 */
class VibrationManager {
	// ── Predefined durations (ms) ─────────────────────────────────────────

	/** Short tap: note hit. */
	public static inline var TAP_MS:Int = 18;

	/** Medium pulse: beat / new section. */
	public static inline var BEAT_MS:Int = 35;

	/** Long rumble: missed note. */
	public static inline var MISS_MS:Int = 80;

	/** Confirmation pulse: important menu action. */
	public static inline var CONFIRM_MS:Int = 50;

	// ── Haptic presets (in seconds, same as V-Slice) ──────────────────────

	/** Default Sharpness — sharp (V-Slice DEFAULT_VIBRATION_SHARPNESS = 1.0). */
	static inline var HAPTIC_SHARPNESS:Float = 1.0;

	/** Maximum amplitude (V-Slice MAX_VIBRATION_AMPLITUDE = 1.0). */
	static inline var HAPTIC_AMP_MAX:Float = 1.0;

	// ── Base motor strengths ───────────────────────────────────────

	/** Left motor (low frequency, body of the controller) strength at 100%. */
	static inline var LEFT_MOTOR_MAX:Float = 0.70;

	/** Right motor (high frequency, triggers) strength at 100%. */
	static inline var RIGHT_MOTOR_MAX:Float = 0.50;

	// ── Global Guard ─────────────────────────────────────────────────────────

	/**
	 * When false, all calls are no-ops regardless of SaveData.
	 * Useful for suppressing haptics during cutscenes or pause screens.
	 */
	public static var globalEnabled:Bool = true;

	// ── Public API ──────────────────────────────────────────────────────────

	/** Very short vibration for hitting a note. */
	public static inline function vibrateTap():Void
		vibrate(TAP_MS);

	/** Medium vibration for a beat pulse / new section. */
	public static inline function vibrateBeat():Void
		vibrate(BEAT_MS);

	/** Long vibration for a missed note. */
	public static inline function vibrateMiss():Void
		vibrate(MISS_MS);

	/** Confirmation vibration for menu actions. */
	public static inline function vibrateConfirm():Void
		vibrate(CONFIRM_MS);

	/**
	 * Triggers haptic feedback for `ms` milliseconds.
	 *
	 * Fires in parallel:
	 *   1. Mobile device vibration  (if `SaveData.data.vibration` = true)
	 *   2. Rumble on all active gamepads  (if `SaveData.data.gamepadRumble` = true)
	 *
	 * @param ms  Duration in milliseconds. Values <= 0 are ignored.
	 */
	public static function vibrate(ms:Int):Void {
		if (!globalEnabled || ms <= 0)
			return;

		_vibrateMobile(ms);
		_vibrateGamepads(ms);
	}

	/**
	 * Asymmetric rumble with independent control over each motor.
	 * Useful for directional feedback or different durations per motor.
	 *
	 * @param leftMs    Left motor (low-freq) duration in ms.
	 * @param rightMs   Right motor (high-freq) duration in ms.
	 * @param leftStr   Left strength 0..1 (scaled by the user's intensity setting).
	 * @param rightStr  Right strength 0..1 (scaled by the user's intensity setting).
	 */
	public static function vibrateAsymmetric(leftMs:Int, rightMs:Int, leftStr:Float = 0.6, rightStr:Float = 0.4):Void {
		if (!globalEnabled)
			return;

		_vibrateMobile(Std.int(Math.max(leftMs, rightMs)));

		#if FLX_GAMEPADS
		var enabled = SaveData.data.gamepadRumble;
		if (enabled == null || enabled == false)
			return;
		var scale = _intensityScale();
		_applyRumbleToAllPads(leftStr * scale, rightStr * scale, Math.max(leftMs, rightMs) / 1000.0);
		#end
	}

	// ── Internos ─────────────────────────────────────────────────────────────

	/**
	 * Vibrates the mobile device if the option is enabled.
	 * No-op on non-mobile builds.
	 *
	 *   Haptic.vibrateOneShot(durationSec, amplitude, sharpness)
	 *
	 * `amplitude` It scales according to user preference (0.0–1.0).
	 * `sharpness` is fixed at 1.0 for crisp feedback (same as V-Slice).
	 */
	static function _vibrateMobile(ms:Int):Void {
		#if FEATURE_HAPTICS
		var enabled = SaveData.data.vibration;
		if (enabled == null || enabled == false)
			return;

		try {
			var durationSec:Float = ms / 1000.0;
			var amplitude:Float = _intensityScale() * HAPTIC_AMP_MAX;
			if (amplitude < 0.0)
				amplitude = 0.0;
			if (amplitude > 1.0)
				amplitude = 1.0;

			Haptic.vibrateOneShot(durationSec, amplitude, HAPTIC_SHARPNESS);
		} catch (e:Dynamic)
			trace('[VibrationManager] mobile vibrate($ms ms) error: $e');
		#end
	}

	/**
	 * Rumbles ALL active gamepads if the option is enabled.
	 * Motor strength is scaled by `vibrationIntensity`.
	 *
	 * Compatible with:
	 *   - DualShock 4 / DualSense (PS4 / PS5)
	 *   - Xbox One / Series S/X
	 *   - Nintendo Switch Pro Controller
	 *   - Generic gamepads with rumble support
	 */
	static function _vibrateGamepads(ms:Int):Void {
		#if FLX_GAMEPADS
		var enabled = SaveData.data.gamepadRumble;
		if (enabled == null || enabled == false)
			return;

		var scale = _intensityScale();
		var left = LEFT_MOTOR_MAX * scale;
		var right = RIGHT_MOTOR_MAX * scale;
		var durSec = ms / 1000.0;

		_applyRumbleToAllPads(left, right, durSec);
		#end
	}

	/**
	 * Iterates all active gamepads and calls `setMotion(left, right, dur)`.
	 *
	 *   left  — left motor  (low frequency, body of the controller)  0..1
	 *   right — right motor (high frequency, triggers)               0..1
	 *   dur   — duration in SECONDS (Flixel API, not ms)
	 *
	 * On controllers without two separate motors (Joy-Cons in some modes,
	 * basic USB gamepads) Flixel will still send the signal — the OS decides
	 * what to do with it. There is no crash risk.
	 *
	 *   left  — motor izquierdo (baja frecuencia)  0..1
	 *   right — motor derecho  (alta frecuencia)   0..1
	 *   dur   — duración en SEGUNDOS (API de Flixel, no ms)
	 */
	static function _applyRumbleToAllPads(left:Float, right:Float, dur:Float):Void {
		#if FLX_GAMEPADS
		var pads = FlxG.gamepads.getActiveGamepads();
		if (pads == null)
			return;

		for (pad in pads) {
			if (pad == null)
				continue;
			try {
				pad.setMotion(left, right, dur);
			} catch (e:Dynamic)
				trace('[VibrationManager] rumble error (${pad.name}): $e');
		}
		#end
	}

	/**
	 * Returns the motor strength multiplier based on the user's preference.
	 *   "light"  -> 0.35
	 *   "medium" -> 0.65  (default)
	 *   "strong" -> 1.00
	 */
	static function _intensityScale():Float {
		var intensity = SaveData.data.vibrationIntensity ?? "medium";
		return switch (intensity) {
			case "light": 0.35;
			case "strong": 1.00;
			default: 0.65;
		};
	}
}
