package funkin.data;

import flixel.FlxG;

/**
 * SaveData — A typed layer on top of FlxG.save.data.
 *
 * ─── Why it exists ────────────────────────────────────────────────────────────
 *
 * FlxG.save.data is a dynamic object: any field can be written to without
 * the compiler notifying you. These types of problems:
 *
 * 1. Silent typos: `FlxG.save.data.antialiasing = true` compiles and saves
 *    to a field that is never read, while `antialiasing` remains null.
 *
 * 2. Scattered migrations: each refactor renames a field and leaves migration
 *    code scattered throughout the project (see FPSCap → fpsTarget).
 *
 * This class solves both:
 *   • `SaveData.data` returns FlxG.save.data cast to `SaveDataFields`,
 *     giving autocompletion and compile-time type errors for core fields.
 *   • `SaveData.migrate()` centralises ALL migrations in one place.
 *   • `SaveData.register*(key, default)` lets scripts and sub-systems declare
 *     their own persistent fields without touching the typedef.
 *     Auto-initialisation happens at `init()` time — one call, zero boilerplate.
 *
 * ─── Usage (core fields) ──────────────────────────────────────────────────────
 *
 *   Read:  var fps = SaveData.data.fpsTarget ?? 60;
 *   Write: SaveData.data.antialiasing = true;  SaveData.flush();
 *
 * ─── Usage (dynamic / script fields) ─────────────────────────────────────────
 *
 *   // Declare once — anywhere in the codebase, before init() is called.
 *   SaveData.registerBool("myMod_coolFeature", false);
 *   SaveData.registerInt("myMod_highStreak", 0);
 *   SaveData.registerFloat("myMod_speed", 1.0);
 *   SaveData.registerString("myMod_skin", "default");
 *
 *   // Read (returns the registered default if never saved before):
 *   var on = SaveData.getBool("myMod_coolFeature");
 *
 *   // Write:
 *   SaveData.setBool("myMod_coolFeature", true);
 *   SaveData.flush();
 *
 * ─── Startup order ────────────────────────────────────────────────────────────
 *
 *   FlxG.save.bind(...);        // 1 — bind the save slot
 *   SaveData.migrate();         // 2 — rename / clean obsolete fields
 *   SaveData.init();            // 3 — auto-create any missing registered fields
 *
 * ─── Adding a new core field ──────────────────────────────────────────────────
 *
 *   1. Declare it in `SaveDataFields` with `@:optional` and the correct type.
 *   2. If renaming an existing field, add a rule in `migrate()`.
 *   3. Never write directly to FlxG.save.data — always use SaveData.data.
 *
 * @author  Cool Engine Team
 * @since   0.6.1
 */

// ─── Typedef ─────────────────────────────────────────────────────────────────

/**
 * All fields that the engine saves in FlxG.save.data.
 * Each field is optional (Null<T>) because it may not exist in older saves.
 *
 * Naming convention:
 *   • Strict camelCase.
 *   • Deprecated fields carry a "@deprecated" comment with the new name.
 */
typedef SaveDataFields =
{
	// ── Video / performance ──────────────────────────────────────────────────

	/** FPS limit. 0 = no limit. Replaces the obsolete FPSCap field. */
	@:optional var fpsTarget:Null<Int>;

	/** @deprecated — Use fpsTarget. Retained for migration purposes only. */
	@:optional var FPSCap:Null<Int>;

	/** Sync vertical. */
	@:optional var vsync:Null<Bool>;

	/** Antialiasing global. */
	@:optional var antialiasing:Null<Bool>;

	/** Screen scaling mode (e.g. "letterbox", "stretch"). */
	@:optional var scaleMode:Null<String>;

	/** Internal render resolution (e.g. "720p", "1080p"). */
	@:optional var renderResolution:Null<String>;

	/** Shader effects enabled. */
	@:optional var shadersEnabled:Null<Bool>;

	/** @deprecated — use shadersEnabled. */
	@:optional var shaders:Null<Bool>;

	/** Special visual effects (particles, etc.). */
	@:optional var specialVisualEffects:Null<Bool>;

	/** GPU texture cache. */
	@:optional var gpuCaching:Null<Bool>;

	/** Low memory power mode. */
	@:optional var lowMemoryMode:Null<Bool>;

	/** Streaming music instead of full upload. */
	@:optional var streamedMusic:Null<Bool>;

	// ── Gameplay ─────────────────────────────────────────────────────────────

	/** Downscroll enabled. */
	@:optional var downscroll:Null<Bool>;

	/**
	 * Sustain Penalty enabled.
	 */
	@:optional var sustainMiss:Null<Bool>;

	/** Middlescroll enabled. */
	@:optional var middlescroll:Null<Bool>;

	/** Ghost tap (does not penalize taps without a note). */
	@:optional var ghosttap:Null<Bool>;

	/** Sick Mode (Strict FC). */
	@:optional var sickmode:Null<Bool>;

	/** Global audio/input offset in ms. */
	@:optional var offset:Null<Float>;

	/** Hide HUD toggle. */
	@:optional var HUD:Null<Bool>;

	/** Hitsounds activated. */
	@:optional var hitsounds:Null<Bool>;

	/** Accuracy display enabled. */
	@:optional var accuracyDisplay:Null<Bool>;

	/** Notesplashes activated. */
	@:optional var notesplashes:Null<Bool>;

	// ── Appearance ───────────────────────────────────────────────────────────

	/** Selected Noteskin. */
	@:optional var noteSkin:Null<String>;

	/** Selected Splash. */
	@:optional var noteSplash:Null<String>;

	/** Note lane alpha (0.0–1.0). */
	@:optional var laneAlpha:Null<Float>;

	/** Cursor Skin. */
	@:optional var cursorSkin:Null<String>;

	/** Offset X of the rating text. */
	@:optional var ratingOffsetX:Null<Float>;

	/** Offset Y of the rating text. */
	@:optional var ratingOffsetY:Null<Float>;

	/** Song ratings per key (serialized Map<String,Float>). */
	@:optional var songRating:Null<Dynamic>;

	/** Flash effects in transitions. */
	@:optional var flashing:Null<Bool>;

	// ── Audio ────────────────────────────────────────────────────────────────

	/** Master volume (0.0–1.0). */
	@:optional var volume:Null<Float>;

	/** Silenced master. */
	@:optional var muted:Null<Bool>;

	/** Core audio volume. */
	@:optional var coreVolume:Null<Float>;

	/** Core audio muted. */
	@:optional var coreMuted:Null<Bool>;

	// ── Subtitles ────────────────────────────────────────────────────────────

	@:optional var subtitlesEnabled:Null<Bool>;
	@:optional var subtitleFont:Null<String>;
	@:optional var subtitleSize:Null<Int>;
	@:optional var subtitleColor:Null<Int>;
	@:optional var subtitleBold:Null<Bool>;
	@:optional var subtitleFadeIn:Null<Float>;
	@:optional var subtitlePosition:Null<String>;
	@:optional var subtitleBgAlpha:Null<Float>;
	@:optional var subtitleTranslateLang:Null<String>;

	// ── Controls ────────────────────────────────────────────────────────────

	@:optional var upBind:Null<String>;
	@:optional var downBind:Null<String>;
	@:optional var leftBind:Null<String>;
	@:optional var rightBind:Null<String>;
	@:optional var killBind:Null<String>;
	@:optional var acceptBind:Null<String>;
	@:optional var backBind:Null<String>;
	@:optional var pauseBind:Null<String>;
	@:optional var screenshotBind:Null<String>;
	@:optional var cheatBind:Null<String>;

	// ── Mobile ───────────────────────────────────────────────────────────────

	@:optional var mobileAlpha:Null<Float>;
	@:optional var mobilePadLayout:Null<String>;
	@:optional var touchIndicator:Null<Bool>;

	/**
	 * Strum Tap mode (mobile only).
	 * If true, the player taps directly on the strum arrows
	 * to hit the notes instead of using the Hitbox or VirtualPad.
	 * This only takes effect when the active control scheme is Hitbox (mode 4).
	 * Default: false.
	 */
	@:optional var strumTap:Null<Bool>;

	/** Haptic vibration feedback enabled (mobile only). Default: true. */
	@:optional var vibration:Null<Bool>;

	/** Vibration intensity preset: "light" | "medium" | "strong". Default: "medium". */
	@:optional var vibrationIntensity:Null<String>;

	/** Gamepad rumble / force-feedback enabled. Default: true. */
	@:optional var gamepadRumble:Null<Bool>;

	// ── Game progress ────────────────────────────────────────────────────────

	/** Unlocked Weeks (Serialized Array<Bool>). */
	@:optional var weekUnlocked:Null<Dynamic>;

	/** Scores per song (Serialized Map). */
	@:optional var songScores:Null<Dynamic>;

	// ── Modchart / scripting ─────────────────────────────────────────────────

	@:optional var modchart_last:Null<String>;
	@:optional var modchart_script:Null<String>;
	@:optional var ruleScriptData:Null<Dynamic>;
}

// ─── Manager ─────────────────────────────────────────────────────────────────

class SaveData
{
	// ── Typed access ─────────────────────────────────────────────────────────

	/**
	 * Typed access to FlxG.save.data cast as SaveDataFields.
	 *
	 * The cast is compiler-only — no data is copied.
	 * Always call `flush()` after writing.
	 */
	public static var data(get, never):SaveDataFields;

	static inline function get_data():SaveDataFields
		return (cast FlxG.save.data : SaveDataFields);

	// ── Default registry ─────────────────────────────────────────────────────

	/**
	 * Default values for every registered dynamic field.
	 * Key   → save-data field name (String).
	 * Value → the default (Bool / Int / Float / String / Dynamic).
	 *
	 * Populated by registerBool / registerInt / registerFloat / registerString.
	 * Applied to FlxG.save.data during init().
	 */
	static var _defaults:Map<String, Dynamic> = [];

	// ── Registration ─────────────────────────────────────────────────────────

	/**
	 * Register a Bool field with a default value.
	 *
	 * Call this before `SaveData.init()` — typically at class static-init time
	 * or inside a script's `onCreate` / module init hook.
	 *
	 * ```haxe
	 * SaveData.registerBool("myMod_enabled", true);
	 * ```
	 *
	 * If the field already exists in the save file its stored value is kept;
	 * the default is only written when the field is missing (null).
	 */
	public static inline function registerBool(key:String, defaultValue:Bool):Void
		_defaults.set(key, defaultValue);

	/**
	 * Register an Int field with a default value.
	 *
	 * ```haxe
	 * SaveData.registerInt("myMod_streak", 0);
	 * ```
	 */
	public static inline function registerInt(key:String, defaultValue:Int):Void
		_defaults.set(key, defaultValue);

	/**
	 * Register a Float field with a default value.
	 *
	 * ```haxe
	 * SaveData.registerFloat("myMod_speed", 1.5);
	 * ```
	 */
	public static inline function registerFloat(key:String, defaultValue:Float):Void
		_defaults.set(key, defaultValue);

	/**
	 * Register a String field with a default value.
	 *
	 * ```haxe
	 * SaveData.registerString("myMod_skin", "default");
	 * ```
	 */
	public static inline function registerString(key:String, defaultValue:String):Void
		_defaults.set(key, defaultValue);

	/**
	 * Register any Dynamic field with a default value.
	 *
	 * Use this for Arrays, Maps, or anonymous objects that scripts need to persist.
	 *
	 * ```haxe
	 * SaveData.registerDynamic("myMod_config", { volume: 1.0, skin: "cool" });
	 * ```
	 */
	public static inline function registerDynamic(key:String, defaultValue:Dynamic):Void
		_defaults.set(key, defaultValue);

	// ── Dynamic accessors ────────────────────────────────────────────────────

	/**
	 * Read a Bool field by key.
	 * Returns the registered default (or `false`) if the field is null.
	 *
	 * ```haxe
	 * var on = SaveData.getBool("myMod_enabled");
	 * ```
	 */
	public static function getBool(key:String):Bool
	{
		var raw:Dynamic = Reflect.field(FlxG.save.data, key);
		if (raw != null)
			return (raw : Bool);
		var def:Dynamic = _defaults.get(key);
		return (def != null) ? (def : Bool) : false;
	}

	/**
	 * Write a Bool field by key and persist to disk.
	 *
	 * ```haxe
	 * SaveData.setBool("myMod_enabled", true);
	 * ```
	 */
	public static function setBool(key:String, value:Bool):Void
	{
		Reflect.setField(FlxG.save.data, key, value);
		flush();
	}

	/**
	 * Read an Int field by key.
	 * Returns the registered default (or `0`) if the field is null.
	 */
	public static function getInt(key:String):Int
	{
		var raw:Dynamic = Reflect.field(FlxG.save.data, key);
		if (raw != null)
			return (raw : Int);
		var def:Dynamic = _defaults.get(key);
		return (def != null) ? (def : Int) : 0;
	}

	/**
	 * Write an Int field by key and persist to disk.
	 */
	public static function setInt(key:String, value:Int):Void
	{
		Reflect.setField(FlxG.save.data, key, value);
		flush();
	}

	/**
	 * Read a Float field by key.
	 * Returns the registered default (or `0.0`) if the field is null.
	 */
	public static function getFloat(key:String):Float
	{
		var raw:Dynamic = Reflect.field(FlxG.save.data, key);
		if (raw != null)
			return (raw : Float);
		var def:Dynamic = _defaults.get(key);
		return (def != null) ? (def : Float) : 0.0;
	}

	/**
	 * Write a Float field by key and persist to disk.
	 */
	public static function setFloat(key:String, value:Float):Void
	{
		Reflect.setField(FlxG.save.data, key, value);
		flush();
	}

	/**
	 * Read a String field by key.
	 * Returns the registered default (or `""`) if the field is null.
	 */
	public static function getString(key:String):String
	{
		var raw:Dynamic = Reflect.field(FlxG.save.data, key);
		if (raw != null)
			return (raw : String);
		var def:Dynamic = _defaults.get(key);
		return (def != null) ? (def : String) : "";
	}

	/**
	 * Write a String field by key and persist to disk.
	 */
	public static function setString(key:String, value:String):Void
	{
		Reflect.setField(FlxG.save.data, key, value);
		flush();
	}

	/**
	 * Read any Dynamic field by key.
	 * Returns the registered default (or `null`) if the field is null.
	 */
	public static function getDynamic(key:String):Dynamic
	{
		var raw:Dynamic = Reflect.field(FlxG.save.data, key);
		if (raw != null)
			return raw;
		return _defaults.get(key);
	}

	/**
	 * Write any Dynamic field by key and persist to disk.
	 */
	public static function setDynamic(key:String, value:Dynamic):Void
	{
		Reflect.setField(FlxG.save.data, key, value);
		flush();
	}

	// ── Persistence ──────────────────────────────────────────────────────────

	/** Persist the save to disk. Equivalent to FlxG.save.flush(). */
	public static inline function flush():Void
		FlxG.save.flush();

	// ── Init (auto-create registered fields) ─────────────────────────────────

	/**
	 * Auto-initialise every registered field that is currently null in the save.
	 *
	 * Call this ONCE at startup, after `migrate()`:
	 *
	 * ```haxe
	 * FlxG.save.bind(...);
	 * SaveData.migrate();
	 * SaveData.init();
	 * ```
	 *
	 * Scripts that call `register*()` before this point will have their fields
	 * initialised here automatically — no manual boilerplate required.
	 */
	public static function init():Void
	{
		var dirty = false;

		for (key => defaultValue in _defaults)
		{
			if (Reflect.field(FlxG.save.data, key) == null)
			{
				trace('[SaveData] init: auto-creating "$key" = $defaultValue');
				Reflect.setField(FlxG.save.data, key, defaultValue);
				dirty = true;
			}
		}

		if (dirty)
		{
			flush();
			trace('[SaveData] init: ${_defaults.keys().hasNext() ? "campos inicializados y persistidos." : ""}');
		}
		else
		{
			trace('[SaveData] init: todos los campos ya estaban inicializados.');
		}
	}

	// ── Centralized migration ─────────────────────────────────────────────────

	/**
	 * Migrate obsolete fields to their current name and clean up leftover data.
	 *
	 * Call ONCE at startup, after `FlxG.save.bind(...)` and before `init()`.
	 *
	 * ─── Migration History ────────────────────────────────────────────────────
	 *   0.6.1  FPSCap        → fpsTarget        (field renamed)
	 *   0.6.1  shaders       → shadersEnabled    (field renamed)
	 * ─────────────────────────────────────────────────────────────────────────
	 *
	 * To add a future migration follow this pattern:
	 *
	 * ```haxe
	 * if (data.oldField != null && data.newField == null)
	 * {
	 *     trace('[SaveData] migrate: oldField → newField');
	 *     data.newField = data.oldField;
	 *     data.oldField = null;
	 *     dirty = true;
	 * }
	 * ```
	 */
	public static function migrate():Void
	{
		var dirty = false;

		// ── v0.6.1: FPSCap → fpsTarget ──────────────────────────────────────
		if (data.FPSCap != null && data.fpsTarget == null)
		{
			trace('[SaveData] migrate: FPSCap(${data.FPSCap}) → fpsTarget');
			data.fpsTarget = data.FPSCap;
			data.FPSCap    = null;
			dirty = true;
		}

		// ── v0.6.1: shaders → shadersEnabled ────────────────────────────────
		if (data.shaders != null && data.shadersEnabled == null)
		{
			trace('[SaveData] migrate: shaders(${data.shaders}) → shadersEnabled');
			data.shadersEnabled = data.shaders;
			data.shaders        = null;
			dirty = true;
		}

		// ── Add future migrations here ────────────────────────────────────────

		if (dirty)
		{
			flush();
			trace('[SaveData] migrate: save actualizado y persistido.');
		}
		else
		{
			trace('[SaveData] migrate: sin cambios necesarios.');
		}
	}
}
