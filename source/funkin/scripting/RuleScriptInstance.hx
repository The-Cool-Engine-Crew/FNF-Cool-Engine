package funkin.scripting;

import funkin.scripting.IScript;
import funkin.scripting.ScriptEvent;

using StringTools;

// ── RuleScript ────────────────────────────────────────────────────────────────
//
//  Full-power Lua scripting system built on linc_luajit.
//
//  WHAT IS RULESCRIPT?
//  ===================
//  RuleScript is the new scripting paradigm for Cool Engine.  Scripts are plain
//  .lua files, but with a transparent bridge to ALL Haxe classes and instances.
//  No sandboxing, no wrapper functions you have to memorise — just real Lua.
//
//  OOP ACCESS
//  ----------
//    local spr = import("flixel.FlxSprite").new(100, 200)
//    spr.alpha  = 0.5         -- set any field
//    spr.x      = 300         -- works like Haxe
//    spr:update(elapsed)      -- call any method
//    FlxG.state:add(spr)      -- chain any call
//
//  CLASS IMPORT
//  ------------
//    -- All four syntaxes are equivalent:
//    import "flixel.util.FlxColor"        -- clean, no parens (recommended)
//    import 'flixel.util.FlxColor'
//    import("flixel.util.FlxColor")       -- function-call style
//    local C = import("flixel.util.FlxColor")  -- assign to local
//
//    -- After any of the above, FlxColor is available as a global:
//    local red = FlxColor.RED
//    local col = FlxColor.fromRGB(255, 0, 0)
//
//    -- Works with any Haxe class or enum:
//    import "flixel.tweens.FlxTween"
//    import "flixel.tweens.FlxEase"
//    import "funkin.gameplay.PlayState"
//    FlxTween.tween(bf, {x = 500}, 0.5, {ease = FlxEase.quadOut})
//
//  METHOD HOOKS
//  ------------
//    -- Run code BEFORE the original (return false to cancel it)
//    before(game, "onBeatHit", function(beat)
//        shakeCamera(0.02, 0.1)
//    end)
//
//    -- Run code AFTER the original
//    after(dad, "dance", function()
//        dad:playAnim("myExtra", false)
//    end)
//
//    -- Fully replace a method (original never runs)
//    replace(bf, "dance", function()
//        bf:playAnim("myIdle", true)
//    end)
//
//    -- Cancel original based on a condition
//    before(game, "onNoteHit", function(note)
//        if note.noteType == "ghost" then
//            return false   -- skip original hit logic
//        end
//    end)
//
//  CUSTOM CLASSES
//  --------------
//    MyBoss = Class {
//        init = function(self, x, y)
//            self.sprite = import("animationdata.FunkinSprite").new(x, y)
//            self.hp     = 100
//        end,
//        takeDamage = function(self, amount)
//            self.hp = self.hp - amount
//            if self.hp <= 0 then self:die() end
//        end,
//        die = function(self)
//            tweenAlpha(self.sprite, 0, 0.5, "quadOut")
//        end
//    }
//    myBoss = MyBoss.new(640, 360)
//
//  REQUIRE (script modules)
//  -----------------------
//    local utils = require("songs/mymod/utils")   -- loads utils.lua
//    utils.doSomething()
//
//  ALL HOOKS
//  ---------
//    onCreate, onUpdate, onUpdatePost, onBeatHit, onStepHit,
//    onNoteHit, onNoteHitPre, onMiss, onHold, onHoldEnd,
//    onSongStart, onSongEnd, onCountdownTick, onCountdownEnd,
//    onPause, onResume, onGameOver, onGameOverRestart,
//    onSectionHit, onChartEvent,
//    onKeyPressed, onKeyJustPressed, onKeyJustReleased,
//    onFocusLost, onFocusGained,
//    onDestroy
//
//  ─── Requirements ────────────────────────────────────────────────────────────
//    Project.xml:  <haxedef name="LUA_ALLOWED"/>
//                  <haxelib name="linc_luajit"/>
//
#if (LUA_ALLOWED && linc_luajit)
import llua.Lua;
import llua.LuaL;
import llua.State;
#end
#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
 * RuleScriptInstance — full-power LuaJIT scripting with complete Haxe bridge.
 *
 * Replaces LuaScriptInstance.  All legacy function bindings (newObject,
 * setProp, getProp, callMethod, triggerAnim, etc.) are preserved so existing
 * mods continue working without changes.
 *
 * NEW in RuleScript:
 *   • import(className)          → class proxy with static + constructor access
 *   • overrideMethod(obj, name)  → patch any method at runtime
 *   • require(path)              → load a .lua script as a module
 *   • All Haxe objects returned as OOP proxies (dot-access + method calls)
 *   • game / bf / dad / gf / stage exposed as live proxies
 *
 * @author  Cool Engine Team
 * @since   0.7.0
 */
class RuleScriptInstance implements IScript
{
	public var id:String;
	public var filePath(default, null):Null<String>;
	public var active:Bool = false;
	public var errored:Bool = false;
	public var lastError:Null<String> = null;

	#if (LUA_ALLOWED && linc_luajit)
	// ── Lua state ─────────────────────────────────────────────────────────────
	var _lua:Dynamic;

	/** Cached source for hotReload(). */
	var _source:String = '';

	// ── Object Registry ───────────────────────────────────────────────────────

	/** Global registry: handle → Haxe object.  Shared across all script instances. */
	static var _reg:Map<Int, Dynamic> = new Map();

	/** Per-tag registry for Psych-compat tag references. */
	static var _tags:Map<String, Int> = new Map();

	/** Auto-incrementing handle counter. */
	static var _regCtr:Int = 1;

	/** Class handle registry (keeps class objects alive). */
	static var _clsReg:Map<String, Int> = new Map();

	/** Factories for newObject() — extended by registerClass(). */
	static var _factories:Map<String, Array<Dynamic>->Dynamic> = _defaultFactories();

	/** Map from script handle → script instance, for timer callbacks. */
	static var _timerScripts:Map<Int, RuleScriptInstance> = new Map();

	/** Current active Lua state (set on every call() so C functions can reach it). */
	static var _sCurrentLua:Dynamic = null;

	/** Current active script id (set on every call() so static C functions can log it). */
	static var _sCurrentId:String = '';

	/** Current active script instance (set on every public entry so _pushOOP can track ownership). */
	static var _sCurrentInstance:RuleScriptInstance = null;

	/**
	 * Reverse registry: Haxe object → handle.
	 * Prevents the same object from accumulating multiple handles across calls.
	 * ObjectMap uses reference-equality (identity), not value equality.
	 */
	static var _revReg:haxe.ds.ObjectMap<{}, Int> = new haxe.ds.ObjectMap();

	/** Reusable empty-args array to avoid allocation on every no-arg call(). */
	static final _emptyArgs:Array<Dynamic> = [];

	// ── Required scripts cache (module system) ────────────────────────────────

	/** path → module table (avoids re-executing the same file). */
	var _required:Map<String, Dynamic> = new Map();

	/**
	 * Handles created by _pushOOP while this script is the active instance.
	 * Freed in destroy() to prevent the shared _reg from growing unboundedly.
	 */
	var _ownedHandles:Array<Int> = [];

	/** Handle registered for this script itself in _timerScripts. Cleaned up on destroy(). */
	var _selfHandle:Int = -1;
	#end

	// ── Constructor ───────────────────────────────────────────────────────────

	public function new(id:String, ?filePath:String)
	{
		this.id = id;
		this.filePath = filePath;
		#if (LUA_ALLOWED && linc_luajit)
		_lua = LuaL.newstate();
		LuaL.openlibs(_lua);
		_registerBridge();
		_registerLegacy();
		LuaL.dostring(_lua, _oopStdlib());
		LuaL.dostring(_lua, _legacyStdlib());
		#end
	}

	// ── Load ──────────────────────────────────────────────────────────────────

	public function loadFile(?path:String):RuleScriptInstance
	{
		#if (LUA_ALLOWED && sys)
		final p = path ?? filePath;
		if (p == null)
		{
			_error('loadFile(): no path provided');
			return this;
		}
		filePath = p;
		if (!FileSystem.exists(p))
		{
			_error('File not found: $p');
			return this;
		}
		try
		{
			return loadString(File.getContent(p));
		}
		catch (e:Dynamic)
		{
			_error('Error reading $p: $e');
		}
		#end
		return this;
	}

	public function loadString(src:String):RuleScriptInstance
	{
		#if (LUA_ALLOWED && linc_luajit)
		active = false;
		errored = false;
		if (src != null)
			_source = src;

		// ── Import pre-processor ─────────────────────────────────────────────
		// Scan for top-level import statements BEFORE the Lua VM runs.
		// This lets you write clean imports at the top of any script:
		//
		//   import "flixel.util.FlxColor"
		//   import "flixel.tweens.FlxTween"
		//   import("funkin.gameplay.PlayState")
		//
		// Classes are resolved in Haxe and pushed as Lua globals immediately,
		// so they are available everywhere — including inside other imports.
		// The matched lines are replaced with comments so Lua never sees them.
		final processed = _preprocessImports(_source);

		if (LuaL.dostring(_lua, processed) != 0)
		{
			final e = Lua.tostring(_lua, -1);
			Lua.pop(_lua, 1);
			_error('[$id] $e');
			return this;
		}
		active = true;

		// Store a back-reference to this instance so bridge C functions can
		// access it (e.g. the require() implementation needs _required).
		final selfHandle = register(this);
		_selfHandle = selfHandle;
		_timerScripts.set(selfHandle, this);
		Lua.pushnumber(_lua, selfHandle);
		Lua.setglobal(_lua, '__scriptHandle');

		// Push live proxy globals
		_pushGlobals();
		#end
		return this;
	}

	// ── IScript ───────────────────────────────────────────────────────────────

	public function call(fn:String, ?args:Array<Dynamic>):Dynamic
	{
		#if (LUA_ALLOWED && linc_luajit)
		if (!active)
			return null;
		if (args == null)
			args = _emptyArgs;
		_sCurrentLua = _lua;
		_sCurrentId = id;
		_sCurrentInstance = this;

		Lua.getglobal(_lua, fn);
		if (Lua.type(_lua, -1) != 6)
		{
			Lua.pop(_lua, 1);
			return null;
		} // LUA_TFUNCTION = 6

		for (a in args)
			_pushOOP(_lua, a);

		if (Lua.pcall(_lua, args.length, 1, 0) != 0)
		{
			final e = Lua.tostring(_lua, -1);
			Lua.pop(_lua, 1);
			trace('[RuleScript:$id] $fn — $e');
			return null;
		}
		final ret = _readOOP(_lua, -1);
		Lua.pop(_lua, 1);
		return ret;
		#else
		return null;
		#end
	}

	public function set(name:String, v:Dynamic):Void
	{
		#if (LUA_ALLOWED && linc_luajit)
		if (_lua == null)
			return;
		_sCurrentInstance = this;
		_pushOOP(_lua, v);
		Lua.setglobal(_lua, name);
		#end
	}

	public function get(name:String):Dynamic
	{
		#if (LUA_ALLOWED && linc_luajit)
		if (_lua == null)
			return null;
		_sCurrentInstance = this;
		Lua.getglobal(_lua, name);
		final v = _readOOP(_lua, -1);
		Lua.pop(_lua, 1);
		return v;
		#else
		return null;
		#end
	}

	public function hasFunction(name:String):Bool
	{
		#if (LUA_ALLOWED && linc_luajit)
		if (!active || _lua == null)
			return false;
		Lua.getglobal(_lua, name);
		final is = Lua.type(_lua, -1) == 6;
		Lua.pop(_lua, 1);
		return is;
		#else
		return false;
		#end
	}

	public function destroy():Void
	{
		#if (LUA_ALLOWED && linc_luajit)
		if (_lua != null)
		{
			try
				Lua.close(_lua)
			catch (_)
			{
			};
			_lua = null;
		}
		_source = '';
		_required.clear();

		// Release all Haxe objects this script registered in the shared registry.
		// This prevents the static _reg from growing unboundedly across songs / reloads.
		for (h in _ownedHandles)
		{
			final obj = _reg.get(h);
			if (obj != null)
				try
					_revReg.remove(cast obj)
				catch (_)
				{
				};
			_reg.remove(h);
		}
		_ownedHandles = [];

		// Remove this script's back-reference from the timer map.
		if (_selfHandle >= 0)
		{
			_timerScripts.remove(_selfHandle);
			_selfHandle = -1;
		}

		if (_sCurrentInstance == this)
			_sCurrentInstance = null;
		#end
		active = false;
		errored = false;
	}

	// ── Hot-reload ────────────────────────────────────────────────────────────

	public function hotReload():Bool
	{
		#if (LUA_ALLOWED && sys)
		if (_lua == null || filePath == null)
			return false;
		if (!FileSystem.exists(filePath))
		{
			trace('[RuleScript] hotReload: not found "$filePath"');
			return false;
		}
		try
		{
			_source = File.getContent(filePath);
			if (LuaL.dostring(_lua, _source) != 0)
			{
				final e = Lua.tostring(_lua, -1);
				Lua.pop(_lua, 1);
				trace('[RuleScript] hotReload failed "$id": $e');
				return false;
			}
			_pushGlobals();
			call('onCreate');
			trace('[RuleScript] Hot-reloaded: $id');
			return true;
		}
		catch (e:Dynamic)
		{
			trace('[RuleScript] hotReload error "$id": $e');
			return false;
		}
		#else
		return false;
		#end
	}

	// ── Static registry helpers ───────────────────────────────────────────────

	/** Register a Haxe object and return its integer handle. */
	public static function register(obj:Dynamic):Int
	{
		final h = _regCtr++;
		_reg.set(h, obj);
		return h;
	}

	/** Retrieve object by handle (null if not registered). */
	public static inline function resolve(h:Int):Dynamic
		return _reg.get(h);

	/** Unregister an object handle (frees the registry slot). */
	public static inline function release(h:Int):Void
	{
		final obj = _reg.get(h);
		if (obj != null)
			try
				_revReg.remove(cast obj)
			catch (_)
			{
			};
		_reg.remove(h);
	}

	/** Register a named factory for newObject(). */
	public static function registerClass(name:String, factory:Array<Dynamic>->Dynamic):Void
		_factories.set(name, factory);

	// ── Private: bridge C functions (OOP) ────────────────────────────────────
	#if (LUA_ALLOWED && linc_luajit)
	// ── Import pre-processor ─────────────────────────────────────────────────

	/**
	 * Scans Lua source for top-level import statements and resolves them
	 * in Haxe BEFORE the Lua VM runs, pushing each class as a global.
	 *
	 * Recognised syntaxes (all equivalent):
	 *   import "flixel.util.FlxColor"
	 *   import 'flixel.util.FlxColor'
	 *   import("flixel.util.FlxColor")
	 *   import('flixel.util.FlxColor')
	 *
	 * The short class name (last segment after the dot) is registered
	 * as a Lua global, exactly like typing `local FlxColor = import(...)`.
	 * Matched lines are replaced with comments so Lua never sees them.
	 *
	 * Mirror of ScriptHandler.processImports() for HScript.
	 */
	function _preprocessImports(src:String):String
	{
		// Matches:
		//   import "com.foo.Bar"          (no parens, double or single quotes)
		//   import("com.foo.Bar")         (function-call style)
		//   import('com.foo.Bar')
		// Optional trailing semicolon allowed. Whitespace before/after class name.
		final importReg = ~/^[ \t]*import[ \t]*\(?[ \t]*['"]([^'"]+)['"][ \t]*\)?[ \t]*;?/gm;
		return importReg.map(src, function(r:EReg):String
		{
			final fullName = r.matched(1).trim();
			final shortName = fullName.split('.').pop();

			var resolved:Dynamic = Type.resolveClass(fullName);
			if (resolved == null)
				resolved = Type.resolveEnum(fullName);

			// Also try common package prefixes if bare name was given
			if (resolved == null && !fullName.contains('.'))
			{
				for (pkg in [
					'flixel',     'flixel.util', 'flixel.tweens', 'flixel.text',
					'funkin', 'funkin.gameplay',   'funkin.data', 'funkin.menus'
				])
				{
					resolved = Type.resolveClass('$pkg.$fullName');
					if (resolved == null)
						resolved = Type.resolveEnum('$pkg.$fullName');
					if (resolved != null)
						break;
				}
			}

			if (resolved != null)
			{
				// Push the resolved class into the Lua state as a global right now,
				// before the rest of the source runs.
				Lua.getglobal(_lua, '__hcls');
				if (Lua.type(_lua, -1) == 6)
				{
					// __hcls(handle) → proxy table; we need the handle first
					final h = register(resolved);
					Lua.pushnumber(_lua, h);
					if (Lua.pcall(_lua, 1, 1, 0) == 0)
					{
						Lua.setglobal(_lua, shortName);
					}
					else
					{
						Lua.pop(_lua, 1);
					}
				}
				else
				{
					// __hcls not ready yet (shouldn't happen, but fallback)
					Lua.pop(_lua, 1);
					_pushOOP(_lua, resolved);
					Lua.setglobal(_lua, shortName);
				}
				trace('[RuleScript:$id] import $fullName → $shortName');
			}
			else
			{
				trace('[RuleScript:$id] import not found: $fullName');
			}

			// Comment out the line so Lua never tries to parse it
			return '-- [import] $fullName';
		});
	}

	/** Push live proxy globals so scripts can use  game / bf / dad / gf / stage  directly. */
	function _pushGlobals():Void
	{
		final ps = funkin.gameplay.PlayState.instance;

		// ── Instancia de PlayState y shortcuts ─────────────────────────────────
		_pushOOP(_lua, ps);
		Lua.setglobal(_lua, 'game');
		_pushOOP(_lua, ps);
		Lua.setglobal(_lua, 'playState');

		if (ps != null)
		{
			_pushOOP(_lua, try ps.boyfriend catch (_) null);
			Lua.setglobal(_lua, 'bf');
			_pushOOP(_lua, try ps.dad catch (_) null);
			Lua.setglobal(_lua, 'dad');
			_pushOOP(_lua, try ps.gf catch (_) null);
			Lua.setglobal(_lua, 'gf');
			_pushOOP(_lua, try ps.currentStage catch (_) null);
			Lua.setglobal(_lua, 'stage');

			// Cámaras
			_pushOOP(_lua, try ps.camGame catch (_) null);
			Lua.setglobal(_lua, 'camGame');
			_pushOOP(_lua, try ps.camHUD catch (_) null);
			Lua.setglobal(_lua, 'camHUD');
			_pushOOP(_lua, try ps.camCountdown catch (_) null);
			Lua.setglobal(_lua, 'camCountdown');

			// Notas y grupos
			_pushOOP(_lua, try ps.notes catch (_) null);
			Lua.setglobal(_lua, 'notes');
			_pushOOP(_lua, try ps.sustainNotes catch (_) null);
			Lua.setglobal(_lua, 'sustainNotes');
			_pushOOP(_lua, try ps.strumLineNotes catch (_) null);
			Lua.setglobal(_lua, 'strumLineNotes');
			_pushOOP(_lua, try ps.grpNoteSplashes catch (_) null);
			Lua.setglobal(_lua, 'grpNoteSplashes');
			_pushOOP(_lua, try ps.grpHoldCovers catch (_) null);
			Lua.setglobal(_lua, 'grpHoldCovers');
			_pushOOP(_lua, try ps.playerStrumsGroup catch (_) null);
			Lua.setglobal(_lua, 'playerStrumsGroup');
			_pushOOP(_lua, try ps.cpuStrumsGroup catch (_) null);
			Lua.setglobal(_lua, 'cpuStrumsGroup');
			_pushOOP(_lua, try ps.strumsGroups catch (_) null);
			Lua.setglobal(_lua, 'strumsGroups');

			// Managers y controllers
			_pushOOP(_lua, try ps.scoreManager catch (_) null);
			Lua.setglobal(_lua, 'scoreManager');
			_pushOOP(_lua, try ps.noteManager catch (_) null);
			Lua.setglobal(_lua, 'noteManager');
			_pushOOP(_lua, try ps.gameState catch (_) null);
			Lua.setglobal(_lua, 'gameState');
			_pushOOP(_lua, try ps.metaData catch (_) null);
			Lua.setglobal(_lua, 'metaData');
			_pushOOP(_lua, try ps.countdown catch (_) null);
			Lua.setglobal(_lua, 'countdown');
			_pushOOP(_lua, try ps.vocals catch (_) null);
			Lua.setglobal(_lua, 'vocals');

			// Primitivos de PlayState (pushed como Lua booleans/numbers)
			Lua.pushboolean(_lua, try ps.paused catch (_) false);
			Lua.setglobal(_lua, 'paused');
			Lua.pushboolean(_lua, try ps.inCutscene catch (_) false);
			Lua.setglobal(_lua, 'inCutscene');
			Lua.pushboolean(_lua, try ps.canPause catch (_) true);
			Lua.setglobal(_lua, 'canPause');
			Lua.pushnumber(_lua, try ps.health catch (_) 1.0);
			Lua.setglobal(_lua, 'health');
			Lua.pushboolean(_lua, try ps.enableBatching catch (_) false);
			Lua.setglobal(_lua, 'enableBatching');

			// Estáticos
			_pushOOP(_lua, funkin.gameplay.PlayState.SONG);
			Lua.setglobal(_lua, 'SONG');
			Lua.pushboolean(_lua, funkin.gameplay.PlayState.isStoryMode);
			Lua.setglobal(_lua, 'isStoryMode');
			Lua.pushboolean(_lua, funkin.gameplay.PlayState.isBotPlay);
			Lua.setglobal(_lua, 'isBotPlay');
			Lua.pushboolean(_lua, funkin.gameplay.PlayState.startingSong);
			Lua.setglobal(_lua, 'startingSong');
			Lua.pushstring(_lua, funkin.gameplay.PlayState.curStage ?? '');
			Lua.setglobal(_lua, 'curStage');
			Lua.pushnumber(_lua, funkin.gameplay.PlayState.storyDifficulty ?? 0);
			Lua.setglobal(_lua, 'storyDifficulty');
			Lua.pushnumber(_lua, funkin.gameplay.PlayState.storyWeek ?? 0);
			Lua.setglobal(_lua, 'storyWeek');
			Lua.pushnumber(_lua, funkin.gameplay.PlayState.campaignScore);
			Lua.setglobal(_lua, 'campaignScore');
			Lua.pushboolean(_lua, funkin.gameplay.PlayState.cinematicMode);
			Lua.setglobal(_lua, 'cinematicMode');
			Lua.pushboolean(_lua, funkin.gameplay.PlayState.isPlaying);
			Lua.setglobal(_lua, 'isPlaying');
		}
		else
		{
			// Fuera de gameplay — pushear nil para bf/dad/gf/etc.
			for (_ in [
				'bf',
				'dad',
				'gf',
				'stage',
				'camGame',
				'camHUD',
				'camCountdown',
				'notes',
				'sustainNotes',
				'strumLineNotes',
				'SONG'
			])
			{
				Lua.pushnil(_lua);
				Lua.setglobal(_lua, _);
			}
		}

		// ── Siempre disponibles ─────────────────────────────────────────────────
		_pushOOP(_lua, flixel.FlxG);
		Lua.setglobal(_lua, 'FlxG');
		_pushOOP(_lua, funkin.data.Conductor);
		Lua.setglobal(_lua, 'Conductor');
		_pushOOP(_lua, Paths);
		Lua.setglobal(_lua, 'Paths');
		_pushOOP(_lua, funkin.gameplay.notes.NoteSkinSystem);
		Lua.setglobal(_lua, 'NoteSkinSystem');
		_pushOOP(_lua, funkin.shaders.NoteColorSwapShader);
		Lua.setglobal(_lua, 'NoteColorSwapShader');
		_pushOOP(_lua, funkin.data.GlobalConfig);
		Lua.setglobal(_lua, 'GlobalConfig');
		_pushOOP(_lua, ScriptHandler);
		Lua.setglobal(_lua, 'ScriptHandler');
	}

	/** Register all OOP bridge C functions. */
	function _registerBridge():Void
	{
		inline function r(n, f)
			Lua.register(_lua, n, f);

		// ── Core OOP bridge ───────────────────────────────────────────────────

		// __haxe_index(handle, key) → value (or method proxy)
		r('__haxe_index', function(l)
		{
			final h = _handle(l, 1);
			final k = Lua.tostring(l, 2);
			Lua.settop(l, 0);
			final obj = _reg.get(h);
			if (obj == null)
			{
				Lua.pushnil(l);
				return 1;
			}

			var val:Dynamic = null;
			try
			{
				val = Reflect.getProperty(obj, k);
			}
			catch (_)
			{
			}
			if (val == null)
				try
				{
					val = Reflect.field(obj, k);
				}
				catch (_)
				{
				}

			if (val != null && Reflect.isFunction(val))
			{
				// Return a method proxy: {__hid=h, __mname=k}
				// We call the Lua helper __hmth(h, k) already defined in stdlib.
				Lua.getglobal(l, '__hmth');
				Lua.pushnumber(l, h);
				Lua.pushstring(l, k);
				if (Lua.pcall(l, 2, 1, 0) != 0)
				{
					Lua.pop(l, 1);
					Lua.pushnil(l);
				}
				return 1;
			}

			_pushOOP(l, val);
			return 1;
		});

		// __haxe_newindex(handle, key, value)
		r('__haxe_newindex', function(l)
		{
			final h = _handle(l, 1);
			final k = Lua.tostring(l, 2);
			final v = _readOOP(l, 3);
			Lua.settop(l, 0);
			final obj = _reg.get(h);
			if (obj == null)
				return 0;
			try
			{
				Reflect.setProperty(obj, k, v);
			}
			catch (e)
			{
				try
					Reflect.setField(obj, k, v)
				catch (e2)
					trace('[RuleScript] set $k: $e2');
			}
			return 0;
		});

		// __haxe_call_method(selfHandle, methodName, args...) → result
		r('__haxe_call_method', function(l)
		{
			final h = _handle(l, 1);
			final name = Lua.tostring(l, 2);
			final nArg = Lua.gettop(l) - 2;
			final args = [for (i in 0...nArg) _readOOP(l, i + 3)];
			Lua.settop(l, 0);
			final obj = _reg.get(h);
			if (obj == null)
			{
				Lua.pushnil(l);
				return 1;
			}
			try
			{
				var m:Dynamic = null;
				try
				{
					m = Reflect.getProperty(obj, name);
				}
				catch (_)
				{
				}
				if (m == null)
					try
					{
						m = Reflect.field(obj, name);
					}
					catch (_)
					{
					}
				if (m == null || !Reflect.isFunction(m))
				{
					Lua.pushnil(l);
					return 1;
				}
				_pushOOP(l, Reflect.callMethod(obj, m, args));
			}
			catch (e:Dynamic)
			{
				trace('[RuleScript] call $name: $e');
				Lua.pushnil(l);
			}
			return 1;
		});

		// __haxe_tostring(handle) → string
		r('__haxe_tostring', function(l)
		{
			final obj = _reg.get(_handle(l, 1));
			Lua.settop(l, 0);
			Lua.pushstring(l, obj != null ? Std.string(obj) : 'null');
			return 1;
		});

		// ── Class bridge ──────────────────────────────────────────────────────

		// __haxe_import(className) → class proxy handle
		r('__haxe_import', function(l)
		{
			final name = Lua.tostring(l, 1);
			Lua.settop(l, 0);

			// Check class cache first
			if (_clsReg.exists(name))
			{
				Lua.pushnumber(l, _clsReg.get(name));
				return 1;
			}

			var resolved:Dynamic = Type.resolveClass(name);
			if (resolved == null)
				resolved = Type.resolveEnum(name);
			if (resolved == null)
			{
				// Try common short names
				for (pkg in [
					'flixel',
					'flixel.util',
					'flixel.tweens',
					'flixel.text',
					'flixel.group',
					'flixel.sound',
					'flixel.math',
					'funkin.gameplay',
					'funkin.menus',
					'funkin.states',
					'funkin.data',
					'funkin.scripting',
					'funkin.gameplay.notes',
					'funkin.gameplay.objects',
					'funkin.gameplay.objects.characters',
					'funkin.gameplay.objects.stages',
					'animationdata',
					'openfl.display',
					'openfl.media'
				])
				{
					resolved = Type.resolveClass('$pkg.$name');
					if (resolved != null)
						break;
					resolved = Type.resolveEnum('$pkg.$name');
					if (resolved != null)
						break;
				}
			}

			if (resolved == null)
			{
				trace('[RuleScript] import: class not found — $name');
				Lua.pushnil(l);
				return 1;
			}

			final h = _regCtr++;
			_reg.set(h, resolved);
			_clsReg.set(name, h);
			trace('[RuleScript] import: $name → handle $h');
			Lua.pushnumber(l, h);
			return 1;
		});

		// __haxe_new_instance(classHandle, args...) → object proxy
		r('__haxe_new_instance', function(l)
		{
			final h = _handle(l, 1);
			final nArg = Lua.gettop(l) - 1;
			final args = [for (i in 0...nArg) _readOOP(l, i + 2)];
			Lua.settop(l, 0);
			final cls = _reg.get(h);
			if (cls == null)
			{
				Lua.pushnil(l);
				return 1;
			}
			try
			{
				final inst = Type.createInstance(cls, args);
				_pushOOP(l, inst);
			}
			catch (e:Dynamic)
			{
				trace('[RuleScript] new: $e');
				Lua.pushnil(l);
			}
			return 1;
		});

		// __haxe_static_get(classHandle, key) → value
		r('__haxe_static_get', function(l)
		{
			final h = _handle(l, 1);
			final k = Lua.tostring(l, 2);
			Lua.settop(l, 0);
			final cls = _reg.get(h);
			if (cls == null)
			{
				Lua.pushnil(l);
				return 1;
			}
			var val:Dynamic = null;
			try
			{
				val = Reflect.field(cls, k);
			}
			catch (_)
			{
			}
			if (val == null)
				try
				{
					val = Reflect.getProperty(cls, k);
				}
				catch (_)
				{
				}
			// Wrap enum constructors and static functions as callables
			if (val != null && Reflect.isFunction(val))
			{
				Lua.getglobal(l, '__hmth');
				Lua.pushnumber(l, h);
				Lua.pushstring(l, k);
				if (Lua.pcall(l, 2, 1, 0) != 0)
				{
					Lua.pop(l, 1);
					Lua.pushnil(l);
				}
				return 1;
			}
			_pushOOP(l, val);
			return 1;
		});

		// __haxe_static_set(classHandle, key, value)
		r('__haxe_static_set', function(l)
		{
			final h = _handle(l, 1);
			final k = Lua.tostring(l, 2);
			final v = _readOOP(l, 3);
			Lua.settop(l, 0);
			final cls = _reg.get(h);
			if (cls == null)
				return 0;
			try
				Reflect.setField(cls, k, v)
			catch (_)
			{
			};
			return 0;
		});

		// __haxe_class_name(classHandle) → string
		r('__haxe_class_name', function(l)
		{
			final cls = _reg.get(_handle(l, 1));
			Lua.settop(l, 0);
			Lua.pushstring(l, cls != null ? Type.getClassName(cls) ?? 'unknown' : 'null');
			return 1;
		});

		// ── import / require (public API functions) ────────────────────────────

		// import(className) → class proxy table
		r('import', function(l)
		{
			final name = Lua.tostring(l, 1);
			Lua.settop(l, 0);

			// Call __haxe_import to get the handle
			Lua.getglobal(l, '__haxe_import');
			Lua.pushstring(l, name);
			if (Lua.pcall(l, 1, 1, 0) != 0)
			{
				Lua.pop(l, 1);
				Lua.pushnil(l);
				return 1;
			}
			final h = Std.int(Lua.tonumber(l, -1));
			Lua.pop(l, 1);

			if (h == 0)
			{
				Lua.pushnil(l);
				return 1;
			}

			// Also register as global short name
			final shortName = name.split('.').pop();
			Lua.getglobal(l, '__hcls');
			Lua.pushnumber(l, h);
			if (Lua.pcall(l, 1, 1, 0) != 0)
			{
				Lua.pop(l, 1);
				Lua.pushnil(l);
				return 1;
			}
			Lua.pushvalue(l, -1);
			Lua.setglobal(l, shortName);
			return 1; // return the class proxy
		});

		// require(scriptPath) → module table
		r('require', function(l)
		{
			final path = Lua.tostring(l, 1);
			Lua.settop(l, 0);
			final selfH = Std.int(0); // retrieve from __scriptHandle
			Lua.getglobal(l, '__scriptHandle');
			final sh = Std.int(Lua.tonumber(l, -1));
			Lua.pop(l, 1);

			final script:RuleScriptInstance = cast _timerScripts.get(sh);
			if (script == null)
			{
				Lua.pushnil(l);
				return 1;
			}

			// Check cache
			if (script._required.exists(path))
			{
				_pushLuaTable(l, script._required.get(path));
				return 1;
			}

			// Resolve path
			final resolved = _resolveModulePath(path, script.filePath);
			#if sys
			if (resolved == null || !FileSystem.exists(resolved))
			{
				trace('[RuleScript] require: not found — $path');
				Lua.pushnil(l);
				return 1;
			}

			// Create a sub-instance and load it
			final mod = new RuleScriptInstance('$id:$path', resolved);
			mod.loadFile(resolved);
			if (!mod.active)
			{
				Lua.pushnil(l);
				return 1;
			}

			// Collect all non-internal globals into a module table
			final modTable:Dynamic = {};
			Lua.getglobal(mod._lua, '_G');
			if (Lua.type(mod._lua, -1) == 5)
			{
				Lua.pushnil(mod._lua);
				while (Lua.next(mod._lua, -2) != 0)
				{
					if (Lua.type(mod._lua, -2) == 4) // string key
					{
						final k = Lua.tostring(mod._lua, -2);
						if (!k.startsWith('_') && !k.startsWith('__'))
						{
							final v = _readOOP(mod._lua, -1);
							if (v != null)
								Reflect.setField(modTable, k, v);
						}
					}
					Lua.pop(mod._lua, 1);
				}
			}
			Lua.pop(mod._lua, 1);

			script._required.set(path, modTable);
			_pushLuaAnon(l, modTable);
			#else
			Lua.pushnil(l);
			#end
			return 1;
		});

		// ── before / after / replace ──────────────────────────────────────────
		//
		// Three simple ways to hook into any method on any object.
		// No `original` parameter, no `self` — just the real arguments.
		//
		//   before(obj, "method", fn)   → fn(args) runs BEFORE original.
		//                                 Return false from fn to cancel original.
		//
		//   after(obj, "method", fn)    → fn(args) runs AFTER original.
		//
		//   replace(obj, "method", fn)  → fn(args) replaces the method entirely.
		//                                 Original never runs.
		//
		// Example:
		//   before(game, "onBeatHit", function(beat)
		//       shakeCamera(0.02, 0.1)
		//   end)
		//
		//   after(dad, "dance", function()
		//       dad:playAnim("myExtra", false)
		//   end)
		//
		//   replace(bf, "dance", function()
		//       bf:playAnim("myIdle", true)
		//   end)
		//
		// Note: overrideMethod() is kept as an alias for backward compat.
		//

		// _patchMethod is the shared implementation used by before/after/replace.
		// mode: 0 = before, 1 = after, 2 = replace
		final _patchMethod = function(l:Dynamic, mode:Int):Int
		{
			final h = _handle(l, 1);
			final name = Lua.tostring(l, 2);
			if (Lua.type(l, 3) != 6)
			{
				Lua.settop(l, 0);
				return 0;
			}

			final obj = _reg.get(h);
			if (obj == null)
			{
				Lua.settop(l, 0);
				return 0;
			}

			// Capture original (may be null for replace — that's fine)
			var original:Dynamic = null;
			try
			{
				original = Reflect.getProperty(obj, name);
			}
			catch (_)
			{
			}
			if (original == null)
				try
				{
					original = Reflect.field(obj, name);
				}
				catch (_)
				{
				}

			// Store the Lua fn as a named global
			final luaFnName = '__patch_${mode}_${h}_${name}_${_regCtr++}';
			Lua.pushvalue(l, 3);
			Lua.setglobal(l, luaFnName);
			Lua.settop(l, 0);

			final luaRef = _lua;
			final capturedOriginal = original;
			final capturedObj = obj;

			// Helper: call the Lua patch fn with args, return its result
			final callLua = function(args:Array<Dynamic>):Dynamic
			{
				Lua.getglobal(luaRef, luaFnName);
				if (Lua.type(luaRef, -1) != 6)
				{
					Lua.pop(luaRef, 1);
					return null;
				}
				for (a in args)
					_pushOOP(luaRef, a);
				if (Lua.pcall(luaRef, args.length, 1, 0) != 0)
				{
					final e = Lua.tostring(luaRef, -1);
					Lua.pop(luaRef, 1);
					trace('[RuleScript] $luaFnName: $e');
					return null;
				}
				final ret = _readOOP(luaRef, -1);
				Lua.pop(luaRef, 1);
				return ret;
			};

			// Helper: call the original Haxe method
			final callOriginal = function(args:Array<Dynamic>):Dynamic
			{
				if (capturedOriginal == null)
					return null;
				try
					return Reflect.callMethod(capturedObj, capturedOriginal, args)
				catch (_)
					return null;
			};

			final wrapper:Dynamic = switch (mode)
			{
				case 0: // before — lua first, then original (unless lua returns false)
					function(args:haxe.Rest<Dynamic>):Dynamic
					{
						final a = args.toArray();
						final r = callLua(a);
						if (r == false)
							return null; // Lua returned false → cancel original
						return callOriginal(a);
					};
				case 1: // after — original first, then lua
					function(args:haxe.Rest<Dynamic>):Dynamic
					{
						final a = args.toArray();
						final ret = callOriginal(a);
						callLua(a);
						return ret;
					};
				default: // replace — lua only
					function(args:haxe.Rest<Dynamic>):Dynamic
					{
						return callLua(args.toArray());
					};
			};

			try
			{
				Reflect.setField(obj, name, wrapper);
			}
			catch (e)
			{
				trace('[RuleScript] patch($name): $e');
			}

			return 0;
		};

		r('before', function(l) return _patchMethod(l, 0));
		r('after', function(l) return _patchMethod(l, 1));
		r('replace', function(l) return _patchMethod(l, 2));

		// overrideMethod(obj, name, fn(original, self, args...)) — backward compat
		r('overrideMethod', function(l)
		{
			final h = _handle(l, 1);
			final name = Lua.tostring(l, 2);
			if (Lua.type(l, 3) != 6)
			{
				Lua.settop(l, 0);
				return 0;
			}

			final obj = _reg.get(h);
			if (obj == null)
			{
				Lua.settop(l, 0);
				return 0;
			}

			var original:Dynamic = null;
			try
			{
				original = Reflect.getProperty(obj, name);
			}
			catch (_)
			{
			}
			if (original == null)
				try
				{
					original = Reflect.field(obj, name);
				}
				catch (_)
				{
				}

			final replaceName = '__override_${h}_${name}_${_regCtr++}';
			Lua.pushvalue(l, 3);
			Lua.setglobal(l, replaceName);
			Lua.settop(l, 0);

			final luaRef = _lua;
			final capturedObj = obj;
			final capturedOrig = original;

			final wrapper:Dynamic = function(args:haxe.Rest<Dynamic>):Dynamic
			{
				Lua.getglobal(luaRef, replaceName);
				if (Lua.type(luaRef, -1) != 6)
				{
					Lua.pop(luaRef, 1);
					return null;
				}
				_pushCallable(luaRef, capturedOrig);
				_pushOOP(luaRef, capturedObj);
				final a = args.toArray();
				for (arg in a)
					_pushOOP(luaRef, arg);
				final nArgs = 2 + a.length;
				if (Lua.pcall(luaRef, nArgs, 1, 0) != 0)
				{
					final e = Lua.tostring(luaRef, -1);
					Lua.pop(luaRef, 1);
					trace('[RuleScript] overrideMethod $name: $e');
					return null;
				}
				final ret = _readOOP(luaRef, -1);
				Lua.pop(luaRef, 1);
				return ret;
			};

			try
			{
				Reflect.setField(capturedObj, name, wrapper);
			}
			catch (e)
			{
				trace('[RuleScript] overrideMethod: could not patch $name — $e');
			}

			return 0;
		});

		// ── switchState (engine-level state transitions) ──────────────────────
		r('switchState', function(l)
		{
			final name = Lua.tostring(l, 1);
			Lua.settop(l, 0);
			final cls = Type.resolveClass(name) ?? Type.resolveClass('funkin.menus.$name') ?? Type.resolveClass('funkin.states.$name') ?? Type.resolveClass('funkin.gameplay.$name');
			if (cls == null)
			{
				trace('[RuleScript] switchState: not found — $name');
				return 0;
			}
			flixel.FlxG.switchState(Type.createInstance(cls, []));
			return 0;
		});
	}

	// ── Private: legacy C functions ───────────────────────────────────────────

	/** Register all v1/v2 function bindings for full backward compatibility. */
	function _registerLegacy():Void
	{
		inline function r(n, f)
			Lua.register(_lua, n, f);

		// Object Registry (legacy handle pattern)
		r('newObject', _fnNew);
		r('getProp', _fnGetProp);
		r('setProp', _fnSetProp);
		r('callMethod', _fnCallMethod);
		r('destroyObject', _fnDestroy);

		// Scene
		r('addToState', _fnAddState);
		r('removeFromState', _fnRemState);
		r('addToGroup', _fnAddGroup);
		r('removeFromGroup', _fnRemGroup);

		// Path-style property access (Psych compat)
		r('getProperty', _fnGetPath);
		r('setProperty', _fnSetPath);
		r('getPropertyOf', _fnGetOf);
		r('setPropertyOf', _fnSetOf);

		// Characters
		r('triggerAnim', _fnTriggerAnim);
		r('characterDance', _fnDance);
		r('getCharHandle', _fnCharHandle);
		r('setCharPos', _fnCharPos);
		r('setCharX', _fnCharX);
		r('setCharY', _fnCharY);
		r('getCharX', _fnCharGetX);
		r('getCharY', _fnCharGetY);
		r('setCharScale', _fnCharScale);
		r('setCharVisible', _fnCharVisible);
		r('setCharAlpha', _fnCharAlpha);
		r('setCharColor', _fnCharColor);
		r('setCharAngle', _fnCharAngle);
		r('setCharFlip', _fnCharFlip);
		r('setCharScrollFactor', _fnCharScroll);
		r('getCharAnim', _fnCharGetAnim);
		r('isAnimFinished', _fnCharAnimDone);
		r('lockCharacter', _fnCharLock);
		r('setCharPlaybackRate', _fnCharRate);
		r('setBF', _fnSetBF);
		r('setDAD', _fnSetDAD);
		r('setGF', _fnSetGF);

		// Health icons
		r('setHealthIcon', _fnSetHIcon);
		r('setHealthIconScale', _fnSetHIconScale);
		r('setHealthIconOffset', _fnSetHIconOffset);
		r('getHealthIconHandle', _fnGetHIconHandle);

		// Strumlines
		r('setStrumAlpha', _fnStrumAlpha);
		r('setStrumScale', _fnStrumScale);
		r('setStrumPosition', _fnStrumPos);
		r('hideStrumNotes', _fnStrumHide);
		r('getStrumHandle', _fnStrumHandle);

		// Sprites
		r('makeSprite', _fnMakeSprite);
		r('makeFunkinSprite', _fnMakeFunkin);
		r('loadImage', _fnLoadImg);
		r('loadGraphic', _fnLoadImg);
		r('loadSparrow', _fnLoadSparrow);
		r('loadAtlas', _fnLoadAtlas);
		r('addAnim', _fnAddAnim);
		r('addAnimOffset', _fnAddAnimOff);
		r('playAnim', _fnPlayAnim);
		r('stopAnim', _fnStopAnim);
		r('addSprite', _fnAddSpr);
		r('removeSprite', _fnRemSpr);
		r('setSpriteScale', _fnSprScale);
		r('setSpriteFlip', _fnSprFlip);
		r('setSpriteAlpha', _fnSprAlpha);
		r('setSpriteColor', _fnSprColor);
		r('setSpritePosition', _fnSprPos);
		r('setSpriteScrollFactor', _fnSprScroll);
		r('setAntialiasing', _fnSprAA);
		r('screenCenter', _fnSprCenter);
		r('setSpriteAngle', _fnSprAngle);
		r('setSpriteVisible', _fnSprVisible);
		r('getSpriteX', _fnSprGetX);
		r('getSpriteY', _fnSprGetY);
		r('getSpriteWidth', _fnSprGetW);
		r('getSpriteHeight', _fnSprGetH);
		r('updateHitbox', _fnUpdateHitbox);
		r('addAnimByIndices', _fnAddAnimIdx);
		r('getCurAnim', _fnGetCurAnim);
		r('isAnimPlaying', _fnIsAnimPlay);
		r('setAnimFPS', _fnSetAnimFPS);
		r('addSpriteToCamera', _fnSprCam);

		// Text
		r('makeText', _fnMakeText);
		r('setText', _fnSetText);
		r('setTextSize', _fnTextSize);
		r('setTextFont', _fnTextFont);
		r('setTextBold', _fnTextBold);
		r('setTextAlign', _fnTextAlign);
		r('setTextBorder', _fnTextBorder);
		r('setTextColor', _fnTextColor);
		r('setTextItalic', _fnTextItalic);
		r('setTextShadow', _fnTextShadow);
		r('getText', _fnGetText);

		// Camera
		r('setCamZoom', _fnCamZoom);
		r('setCamZoomTween', _fnCamZoomTween);
		r('cameraFlash', _fnCamFlash);
		r('cameraShake', _fnCamShake);
		r('cameraFade', _fnCamFade);
		r('cameraPan', _fnCamPan);
		r('cameraSnapTo', _fnCamSnap);
		r('getCamHandle', _fnCamHandle);
		r('makeCam', _fnMakeCam);
		r('setCamTarget', _fnCamTarget);
		r('setCamFollowStyle', _fnCamFollow);
		r('setCamLerp', _fnCamLerp);
		r('getCamZoom', _fnGetCamZoom);
		r('setCamScrollX', _fnCamScrollX);
		r('setCamScrollY', _fnCamScrollY);
		r('removeCam', _fnRemoveCam);

		// Tweens
		r('tweenProp', _fnTweenProp);
		r('tween', _fnTweenProp);
		r('tweenColor', _fnTweenColor);
		r('tweenCancel', _fnTweenCancel);
		r('tweenAngle', _fnTweenAngle);
		r('tweenPosition', _fnTweenPos);
		r('tweenAlpha', _fnTweenAlpha);
		r('tweenScale', _fnTweenScale);
		r('tweenNumTween', _fnNumTween);

		// Timers
		r('timer', _fnTimer);
		r('timerCancel', _fnTimerCancel);

		// Cutscenes
		r('newCutscene', _fnCutNew);
		r('cutsceneSkippable', _fnCutSkip);
		r('cutsceneDefineRect', _fnCutRect);
		r('cutsceneDefineSprite', _fnCutSpr);
		r('cutsceneAdd', _fnCutAdd);
		r('cutsceneRemove', _fnCutRem);
		r('cutsceneWait', _fnCutWait);
		r('cutsceneStageAnim', _fnCutAnim);
		r('cutscenePlaySound', _fnCutSound);
		r('cutsceneCameraZoom', _fnCutCamZ);
		r('cutsceneCameraFlash', _fnCutCamF);
		r('cutscenePlay', _fnCutPlay);

		// Gameplay
		r('addScore', _fnAddScore);
		r('setScore', _fnSetScore);
		r('getScore', _fnGetScore);
		r('addHealth', _fnAddHealth);
		r('setHealth', _fnSetHealth);
		r('getHealth', _fnGetHealth);
		r('setMisses', _fnSetMisses);
		r('getMisses', _fnGetMisses);
		r('setCombo', _fnSetCombo);
		r('getCombo', _fnGetCombo);
		r('endSong', _fnEndSong);
		r('gameOver', _fnGameOver);
		r('pauseGame', _fnPause);
		r('resumeGame', _fnResume);

		// Notes
		r('spawnNote', _fnSpawnNote);
		r('getNoteDir', _fnNoteDir);
		r('getNoteTime', _fnNoteTime);
		r('forEachNote', _fnForNote);
		r('setNoteAlpha', _fnNoteAlpha);
		r('setNoteColor', _fnNoteColor);
		r('skipNote', _fnSkipNote);
		r('setNoteSkin', _fnNoteSkin);
		r('showNoteSplash', _fnNoteSplash);
		r('holdNoteActive', _fnHoldActive);

		// Note skins / types (full access)
		r('getNoteSkinHandle', _fnNoteSkinHandle);
		r('reloadNoteSkin', _fnReloadNoteSkin);

		// ── Shader RGB y tweens de color ──────────────────────────────────
		r('applyRGBShader', _fnApplyRGB);
		r('applyRGBColor', _fnApplyRGBColor);
		r('setRGBIntensity', _fnSetRGBIntensity);
		r('removeRGBShader', _fnRemoveRGB);
		r('tweenRGBToDirection', _fnTweenRGBDir);
		r('tweenRGBToColor', _fnTweenRGBColor);
		r('tweenRGBIntensity', _fnTweenRGBIntensity);

		// Notetype overrides from script
		r('registerNoteType', _fnRegNoteType);

		// Audio
		r('playMusic', _fnPlayMusic);
		r('stopMusic', _fnStopMusic);
		r('pauseMusic', _fnPauseMusic);
		r('resumeMusic', _fnResumeMusic);
		r('playSound', _fnPlaySound);
		r('getMusicPos', _fnMusicPos);
		r('setMusicPos', _fnSetMusicPos);
		r('setMusicPitch', _fnMusicPitch);
		r('setVocalsVolume', _fnVocVol);
		r('setPlayerVocals', _fnVocP);
		r('setOpponentVocals', _fnVocOp);
		r('muteVocals', _fnMuteVoc);

		// Config
		r('setConfig', _fnSetConfig);
		r('getConfig', _fnGetConfig);

		// Input
		r('keyPressed', _fnKeyP);
		r('keyJustPressed', _fnKeyJP);
		r('keyJustReleased', _fnKeyJR);
		r('mouseX', _fnMouseX);
		r('mouseY', _fnMouseY);
		r('mousePressed', _fnMouseP);
		r('mouseJustPressed', _fnMouseJP);
		r('gamepadPressed', _fnPadP);
		r('gamepadJustPressed', _fnPadJP);
		r('mouseRightPressed', _fnMouseRP);
		r('mouseRightJustPressed', _fnMouseRJP);

		// Utils
		r('trace', _fnTrace);
		r('log', _fnTrace);
		r('getBeat', _fnBeat);
		r('getStep', _fnStep);
		r('getBPM', _fnBPM);
		r('getSongPos', _fnSongPos);
		r('randomInt', _fnRndInt);
		r('randomFloat', _fnRndFlt);
		r('colorRGB', _fnRGB);
		r('colorRGBA', _fnRGBA);
		r('colorHex', _fnHex);
		r('lerp', _fnLerp);
		r('clamp', _fnClamp);
		r('fileExists', _fnFileEx);
		r('fileRead', _fnFileR);
		r('fileWrite', _fnFileW);
		r('getSongName', _fnSongName);
		r('getSongArtist', _fnSongArtist);
		r('isStoryMode', _fnIsStory);
		r('getDifficulty', _fnGetDiff);
		r('getAccuracy', _fnGetAcc);
		r('getSicks', _fnGetSicks);
		r('getGoods', _fnGetGoods);
		r('getBads', _fnGetBads);
		r('getShits', _fnGetShits);
		r('setSicks', _fnSetSicks);
		r('setScrollSpeed', _fnSetScroll);
		r('getScrollSpeed', _fnGetScroll);

		// Shared data between scripts
		r('setShared', _fnSetShared);
		r('getShared', _fnGetShared);
		r('deleteShared', _fnDelShared);

		// Script communication
		r('broadcast', _fnBroadcast);
		r('callOnScripts', _fnCallScripts);
		r('setScriptVar', _fnSetScriptVar);
		r('getScriptVar', _fnGetScriptVar);

		// Modifiers (modchart)
		r('setModifier',       _fnSetMod);      // 'all' - todos los grupos (legacy)
		r('setPlayerModifier', _fnSetPlayerMod); // solo grupo del jugador
		r('setCpuModifier',    _fnSetCpuMod);    // solo grupo CPU/oponente
		r('setGroupModifier',  _fnSetGroupMod);  // grupo por ID (e.g. 'bf', 'dad')
		r('getModifier',       _fnGetMod);
		r('clearModifiers',    _fnClearMods);
		r('noteModifier',      _fnNoteMod);

		// Events
		r('triggerEvent', _fnTriggerEv);
		r('registerEvent', _fnRegisterEv);
		r('getEventDef', _fnGetEventDef);
		r('listEvents', _fnListEvents);
		r('registerEventDef', _fnRegisterEventDef);

		// Shaders
		r('addShader', _fnAddShader);
		r('removeShader', _fnRemoveShader);
		r('setShaderProp', _fnShaderProp);

		// UI / Dialogs
		r('showNotification', _fnNotif);
		r('newDialog', _fnNewDialog);
		r('dialogAddLine', _fnDialogAddLine);
		r('dialogSetPortrait', _fnDialogPortrait);
		r('dialogSetTypeSpeed', _fnDialogTypeSpeed);
		r('dialogSetAutoAdvance', _fnDialogAutoAdv);
		r('dialogSetSpeakerColor', _fnDialogSpColor);
		r('dialogSetBgColor', _fnDialogBgColor);
		r('dialogSetAllowSkip', _fnDialogAllowSkip);
		r('dialogOnFinish', _fnDialogOnFinish);
		r('dialogOnLine', _fnDialogOnLine);
		r('dialogShow', _fnDialogShow);
		r('dialogClose', _fnDialogClose);
		r('dialogSkipAll', _fnDialogSkipAll);
		r('showDialog', _fnDialogQuick);
		r('dialogSequence', _fnDialogSequence);
		r('closeDialog', _fnCloseAllDialogs);

		// Persistent data
		r('dataSave', _fnDataSave);
		r('dataLoad', _fnDataLoad);
		r('dataExists', _fnDataExists);
		r('dataDelete', _fnDataDelete);

		// JSON
		r('jsonEncode', _fnJsonEnc);
		r('jsonDecode', _fnJsonDec);

		// Strings / Tables
		r('stringSplit', _fnStrSplit);
		r('stringContains', _fnStrContains);
		r('stringTrim', _fnStrTrim);
		r('stringReplace', _fnStrReplace);
		r('tableLength', _fnTableLen);

		// Subtitles
		r('showSubtitle', _fnSubShow);
		r('hideSubtitle', _fnSubHide);
		r('clearSubtitles', _fnSubClear);
		r('queueSubtitle', _fnSubQueue);
		r('setSubtitleStyle', _fnSubStyle);
		r('resetSubtitleStyle', _fnSubReset);

		// Transitions
		r('fadeIn', _fnFadeIn);
		r('fadeOut', _fnFadeOut);

		// Menu / Options / PauseMenu / GameOver hooks (direct object access)
		r('getMenuHandle', _fnGetMenuHandle);
		r('getPauseHandle', _fnGetPauseHandle);
		r('getGameOverHandle', _fnGetGameOverHandle);
		r('getOptionsHandle', _fnGetOptionsHandle);
		r('getResultsHandle', _fnGetResultsHandle);
		r('getFreeplayHandle', _fnGetFreeplayHandle);
		r('getMainMenuHandle', _fnGetMainMenuHandle);
	}

	// ── OOP stdlib (metatables + helpers) ─────────────────────────────────────

	static function _oopStdlib():String
		return '
-- ════════════════════════════════════════════════════════════════════════════
-- RuleScript OOP Bridge v1
-- Metatables that make every Haxe object behave like a native Lua object.
-- ════════════════════════════════════════════════════════════════════════════

-- ── Haxe object proxy metatable ──────────────────────────────────────────────
__HOBJ = {}
__HOBJ.__index = function(t, k)
    local h = rawget(t, "__hid")
    if not h then return nil end
    return __haxe_index(h, k)
end
__HOBJ.__newindex = function(t, k, v)
    local h = rawget(t, "__hid")
    if not h then return end
    __haxe_newindex(h, k, v)
end
__HOBJ.__tostring = function(t)
    local h = rawget(t, "__hid")
    return h and __haxe_tostring(h) or "HaxeObject(nil)"
end
__HOBJ.__eq = function(a, b)
    local ha = rawget(a, "__hid")
    local hb = rawget(b, "__hid")
    return ha ~= nil and ha == hb
end

-- ── Haxe class proxy metatable ────────────────────────────────────────────────
__HCLS = {}
__HCLS.__index = function(t, k)
    local h = rawget(t, "__hid")
    if not h then return nil end
    if k == "new" then
        return function(...)
            return __haxe_new_instance(h, ...)
        end
    end
    return __haxe_static_get(h, k)
end
__HCLS.__call = function(t, ...)
    local h = rawget(t, "__hid")
    return __haxe_new_instance(h, ...)
end
__HCLS.__newindex = function(t, k, v)
    local h = rawget(t, "__hid")
    __haxe_static_set(h, k, v)
end
__HCLS.__tostring = function(t)
    local h = rawget(t, "__hid")
    return "HaxeClass(" .. (h and __haxe_class_name(h) or "nil") .. ")"
end

-- ── Haxe method proxy metatable ───────────────────────────────────────────────
__HMTH = {}
__HMTH.__call = function(t, ...)
    return __haxe_call_method(rawget(t, "__hid"), rawget(t, "__mname"), ...)
end
__HMTH.__tostring = function(t)
    return "HaxeMethod(" .. (rawget(t, "__mname") or "?") .. ")"
end

-- ── Proxy constructors ────────────────────────────────────────────────────────

-- Wrap an integer handle as a Haxe instance proxy
function __hobj(h)
    if h == nil then return nil end
    local t = {__hid = h}
    setmetatable(t, __HOBJ)
    return t
end

-- Wrap an integer handle as a Haxe class proxy
function __hcls(h)
    if h == nil then return nil end
    local t = {__hid = h}
    setmetatable(t, __HCLS)
    return t
end

-- Build a method proxy (used by __haxe_index when a field is a function)
function __hmth(h, name)
    local t = {__hid = h, __mname = name}
    setmetatable(t, __HMTH)
    return t
end

-- Extract the raw handle from any proxy (or return the number itself)
function __raw(v)
    if type(v) == "number" then return v end
    if type(v) == "table"  then return rawget(v, "__hid") end
    return nil
end

-- ── Custom Class system (unchanged from legacy) ───────────────────────────────
function Class(def)
    local cls = {}
    cls.__index = cls
    if def.extends then setmetatable(cls, {__index = def.extends}) end
    for k, v in pairs(def) do if k ~= "extends" then cls[k] = v end end
    cls.new = function(...)
        local inst = setmetatable({}, cls)
        if inst.init then inst:init(...) end
        return inst
    end
    return cls
end

-- ── Lightweight state machine ─────────────────────────────────────────────────
StateMachine = Class {
    init = function(self, states)
        self.states  = states or {}
        self.current = nil
    end,
    go = function(self, name, ...)
        local cur = self.states[self.current]
        if cur and cur.exit then cur:exit() end
        self.current = name
        local next = self.states[name]
        if next and next.enter then next:enter(...) end
    end,
    update = function(self, elapsed)
        local cur = self.states[self.current]
        if cur and cur.update then cur:update(elapsed) end
    end
}
';

	// ── Legacy stdlib (shortcuts, compat, helpers) ────────────────────────────

	static function _legacyStdlib():String
		return '
-- ════════════════════════════════════════════════════════════════════════════
-- RuleScript Helpers & Compatibility Layer
-- ════════════════════════════════════════════════════════════════════════════

-- Pre-defined colors
Color = {
    WHITE = colorHex("FFFFFFFF"), BLACK = colorHex("FF000000"),
    RED   = colorHex("FFFF0000"), GREEN = colorHex("FF00FF00"),
    BLUE  = colorHex("FF0000FF"), YELLOW= colorHex("FFFFFF00"),
    CYAN  = colorHex("FF00FFFF"), MAGENTA=colorHex("FFFF00FF"),
    ORANGE= colorHex("FFFF8800"), PINK  = colorHex("FFFF69B4"),
    PURPLE= colorHex("FF800080"), GRAY  = colorHex("FF888888"),
    TRANSPARENT = 0
}

-- Ease name constants
Ease = {
    linear    = "linear",
    quadIn    = "quadIn",   quadOut   = "quadOut",   quadInOut   = "quadInOut",
    cubeIn    = "cubeIn",   cubeOut   = "cubeOut",   cubeInOut   = "cubeInOut",
    sineIn    = "sineIn",   sineOut   = "sineOut",   sineInOut   = "sineInOut",
    bounceIn  = "bounceIn", bounceOut = "bounceOut",
    elasticIn = "elasticIn",elasticOut= "elasticOut",
    backIn    = "backIn",   backOut   = "backOut"
}

-- Direction key aliases
Key = {
    LEFT="LEFT", DOWN="DOWN", UP="UP", RIGHT="RIGHT",
    ENTER="ENTER", ESCAPE="ESCAPE", SPACE="SPACE",
    A="A",B="B",C="C",D="D",E="E",F="F",G="G",H="H",I="I",J="J",
    K="K",L="L",M="M",N="N",O="O",P="P",Q="Q",R="R",S="S",T="T",
    U="U",V="V",W="W",X="X",Y="Y",Z="Z",
    ONE="ONE",TWO="TWO",THREE="THREE",FOUR="FOUR",
    F1="F1",F2="F2",F3="F3",F4="F4",F5="F5"
}

-- Camera shortcuts
camGame = "game"
camHUD  = "hud"
camUI   = "ui"

-- Character aliases
BF       = "bf"
DAD      = "dad"
GF       = "gf"
OPPONENT = "dad"
PLAYER   = "bf"

-- ── Math helpers ──────────────────────────────────────────────────────────────
function sign(n)   return n > 0 and 1 or (n < 0 and -1 or 0) end
function round(n)  return math.floor(n + 0.5) end
function map(v, mn, mx, tmn, tmx) return tmn + (v - mn) / (mx - mn) * (tmx - tmn) end

-- ── Table helpers ─────────────────────────────────────────────────────────────
function tableContains(t, v)
    for _, x in ipairs(t) do if x == v then return true end end
    return false
end
function tableRemove(t, v)
    for i, x in ipairs(t) do if x == v then table.remove(t, i) return end end
end
function tableMap(t, fn)
    local r = {}
    for i, v in ipairs(t) do r[i] = fn(v) end
    return r
end
function tableFilter(t, fn)
    local r = {}
    for _, v in ipairs(t) do if fn(v) then r[#r+1] = v end end
    return r
end

-- ── String helpers ────────────────────────────────────────────────────────────
function startsWith(s, p) return s:sub(1, #p) == p end
function endsWith(s, p)   return s:sub(-#p) == p end
function capitalize(s)    return s:sub(1,1):upper() .. s:sub(2):lower() end

-- ── Layout helpers ────────────────────────────────────────────────────────────
function centerX(h)  setProp(h,"x",(1280-getProp(h,"width"))/2) end
function centerY(h)  setProp(h,"y",(720 -getProp(h,"height"))/2) end
function center(h)   centerX(h); centerY(h) end

-- ── Psych compat aliases ──────────────────────────────────────────────────────
makeLuaSprite   = makeSprite
addLuaSprite    = addSprite
removeLuaSprite = removeSprite
makeGraphic     = makeSprite
luaTrace        = trace

-- ── Tween shortcuts ───────────────────────────────────────────────────────────
function tweenX(spr, to, dur, ease)      return tweenProp(spr,"x", to, dur, ease or "linear") end
function tweenY(spr, to, dur, ease)      return tweenProp(spr,"y", to, dur, ease or "linear") end
function tweenXY(spr, tx, ty, dur, ease) return tweenPosition(spr, tx, ty, dur, ease or "linear") end
function fadeInSprite(spr, dur, ease)    return tweenAlpha(spr, 1, dur or 0.5, ease or "linear") end
function fadeOutSprite(spr, dur, ease)   return tweenAlpha(spr, 0, dur or 0.5, ease or "linear") end

-- ── Character shortcuts ───────────────────────────────────────────────────────
function bfAnim(anim, force)   triggerAnim("bf",  anim, force or false) end
function dadAnim(anim, force)  triggerAnim("dad", anim, force or false) end
function gfAnim(anim, force)   triggerAnim("gf",  anim, force or false) end
function bfDance()    characterDance("bf")  end
function dadDance()   characterDance("dad") end
function gfDance()    characterDance("gf")  end

-- ── Camera shortcuts ──────────────────────────────────────────────────────────
function zoomCamera(z, dur, ease) if dur then setCamZoomTween(z, dur, ease or "linear") else setCamZoom(z) end end
function flashCamera(col, dur)    cameraFlash(col or "WHITE", dur or 0.5) end
function shakeCamera(i, dur)      cameraShake(i or 0.03, dur or 0.2) end
function snapCameraTo(x, y)       cameraSnapTo(x, y) end

-- ── Data helpers ──────────────────────────────────────────────────────────────
function saveData(key, value) dataSave(key, value) end
function loadData(key, default)
    local v = dataLoad(key)
    return v ~= nil and v or default
end

-- ── Notification shortcut ─────────────────────────────────────────────────────
function notify(msg, dur) showNotification(msg, dur or 2.5) end

-- ── Dialog fluent API ─────────────────────────────────────────────────────────
Dialog = {}
Dialog.__index = Dialog

function Dialog.new()
    return setmetatable({_handle = newDialog()}, Dialog)
end
function Dialog:line(speaker, text, color, autoAdv)
    dialogAddLine(self._handle, speaker, text, color or 0, autoAdv or 0)
    return self
end
function Dialog:portrait(key, path) dialogSetPortrait(self._handle, key, path); return self end
function Dialog:typeSpeed(s)        dialogSetTypeSpeed(self._handle, s); return self end
function Dialog:autoAdvance(s)      dialogSetAutoAdvance(self._handle, s); return self end
function Dialog:speakerColor(c)     dialogSetSpeakerColor(self._handle, c); return self end
function Dialog:bgColor(c)          dialogSetBgColor(self._handle, c); return self end
function Dialog:allowSkip(v)        dialogSetAllowSkip(self._handle, v ~= false); return self end
function Dialog:onFinish(fn)        dialogOnFinish(self._handle, fn); return self end
function Dialog:onLine(fn)          dialogOnLine(self._handle, fn); return self end
function Dialog:show()              dialogShow(self._handle); return self end
function Dialog:close()             dialogClose(self._handle); return self end
function Dialog:skip()              dialogSkipAll(self._handle); return self end

-- ── Boss bar widget ───────────────────────────────────────────────────────────
BossBar = Class {
    init = function(self, label, color)
        self.bg  = makeText(0, 0, 1280, "", 18)
        self.bar = newObject("FlxSprite", 0, 0)
        self.txt = makeText(0, 0, 1280, label or "BOSS", 20)
        self.max = 100
        self.val = 100
        self.col = color or Color.RED
        callMethod(self.bar, "makeGraphic", 1280, 20, self.col)
        setProp(self.bg, "y", 695); setProp(self.bar, "y", 695); setProp(self.txt, "y", 692)
        setTextAlign(self.txt, "center"); setTextBold(self.txt, true)
        setSpriteScrollFactor(self.bar, 0, 0)
        setProp(self.bg,  "scrollFactor.x", 0); setProp(self.bg,  "scrollFactor.y", 0)
        setProp(self.txt, "scrollFactor.x", 0); setProp(self.txt, "scrollFactor.y", 0)
        addToState(self.bg); addToState(self.bar); addToState(self.txt)
    end,
    set = function(self, value)
        self.val = math.max(0, math.min(self.max, value))
        local ratio = self.val / self.max
        callMethod(self.bar, "setGraphicSize", math.floor(1280 * ratio), 20)
        callMethod(self.bar, "updateHitbox")
    end,
    damage = function(self, amount) self:set(self.val - amount) end,
    heal   = function(self, amount) self:set(self.val + amount) end,
    isDead = function(self) return self.val <= 0 end
}
';

	// ── _push / _read (OOP-aware) ─────────────────────────────────────────────

	/**
	 * Push a Haxe value onto the Lua stack.
	 * Haxe objects (non-primitives) are wrapped as proxy tables via __hobj().
	 *
	 * Optimisation: the same Haxe object always gets the same handle (deduplicated
	 * via _revReg), so repeatedly pushing globals like FlxG or PlayState.instance
	 * does not spam the shared registry with new entries each frame.
	 */
	static function _pushOOP(l:Dynamic, v:Dynamic):Void
	{
		if (v == null)
			Lua.pushnil(l);
		else if (Std.isOfType(v, Bool))
			Lua.pushboolean(l, v);
		else if (Std.isOfType(v, Int))
			Lua.pushnumber(l, v);
		else if (Std.isOfType(v, Float))
			Lua.pushnumber(l, v);
		else if (Std.isOfType(v, String))
			Lua.pushstring(l, v);
		else
		{
			// Check if this object is already in the registry.
			var h:Int;
			final existing = try _revReg.get(cast v) catch (_) null;
			if (existing != null)
			{
				h = existing;
			}
			else
			{
				h = _regCtr++;
				_reg.set(h, v);
				try
					_revReg.set(cast v, h)
				catch (_)
				{
				};
				// Track ownership for cleanup in destroy()
				if (_sCurrentInstance != null)
					_sCurrentInstance._ownedHandles.push(h);
			}

			Lua.getglobal(l, '__hobj');
			Lua.pushnumber(l, h);
			if (Lua.pcall(l, 1, 1, 0) != 0)
			{
				Lua.pop(l, 1);
				Lua.pushnumber(l, h); // fallback: push raw handle
			}
		}
	}

	/**
	 * Push a callable Haxe function as a Lua-callable proxy.
	 * Used by overrideMethod (legacy) to pass the original function to Lua.
	 */
	static function _pushCallable(l:Dynamic, fn:Dynamic):Void
	{
		if (fn == null)
		{
			Lua.pushnil(l);
			return;
		}
		final h = _regCtr++;
		_reg.set(h, fn);
		// Create a special callable proxy: {__hid=h, __mname="__call__"}
		Lua.getglobal(l, '__hmth');
		Lua.pushnumber(l, h);
		Lua.pushstring(l, '__call__');
		if (Lua.pcall(l, 2, 1, 0) != 0)
		{
			Lua.pop(l, 1);
			Lua.pushnil(l);
		}
	}

	/**
	 * Read a value from the Lua stack at position idx.
	 * Proxy tables are unwrapped back to their Haxe objects.
	 */
	static function _readOOP(l:Dynamic, idx:Int):Dynamic
	{
		final t = Lua.type(l, idx);
		if (t == 0)
			return null; // LUA_TNIL
		if (t == 1)
			return (Lua.toboolean(l, idx) : Dynamic);
		if (t == 3)
			return (Lua.tonumber(l, idx) : Dynamic);
		if (t == 4)
			return (Lua.tostring(l, idx) : Dynamic);
		if (t == 5) // LUA_TTABLE — check for __hid
		{
			Lua.getfield(l, idx, '__hid');
			if (Lua.type(l, -1) == 3)
			{
				final h = Std.int(Lua.tonumber(l, -1));
				Lua.pop(l, 1);
				final obj = _reg.get(h);
				return obj;
			}
			Lua.pop(l, 1);
			// Plain Lua table — convert to anonymous Dynamic object
			return _luaTableToDynamic(l, idx);
		}
		return null;
	}

	/** Extract a numeric handle from arg at idx (handles both raw number and proxy table). */
	static function _handle(l:Dynamic, idx:Int):Int
	{
		final t = Lua.type(l, idx);
		if (t == 3)
			return Std.int(Lua.tonumber(l, idx));
		if (t == 5)
		{
			Lua.getfield(l, idx, '__hid');
			final h = Std.int(Lua.tonumber(l, -1));
			Lua.pop(l, 1);
			return h;
		}
		return 0;
	}

	/** Convert a plain Lua table (at idx) to an anonymous Dynamic object. */
	static function _luaTableToDynamic(l:Dynamic, idx:Int):Dynamic
	{
		final obj:Dynamic = {};
		Lua.pushnil(l);
		while (Lua.next(l, idx) != 0)
		{
			if (Lua.type(l, -2) == 4)
			{
				final k = Lua.tostring(l, -2);
				final v = _readOOP(l, -1);
				if (v != null)
					Reflect.setField(obj, k, v);
			}
			Lua.pop(l, 1);
		}
		return obj;
	}

	/** Push an anon Dynamic as a Lua table. */
	static function _pushLuaAnon(l:Dynamic, obj:Dynamic):Void
	{
		Lua.newtable(l);
		if (obj == null)
			return;
		for (k in Reflect.fields(obj))
		{
			Lua.pushstring(l, k);
			_pushOOP(l, Reflect.field(obj, k));
			Lua.settable(l, -3);
		}
	}

	/** Push a Dynamic Map as a Lua table. */
	static function _pushLuaTable(l:Dynamic, obj:Dynamic):Void
		_pushLuaAnon(l, obj);

	// ── Helpers ───────────────────────────────────────────────────────────────

	static inline function _ps():Dynamic
		return funkin.gameplay.PlayState.instance;

	static function _spr(l:Dynamic, idx:Int = 1):Dynamic
	{
		final h = _handle(l, idx);
		if (h != 0)
			return _reg.get(h);
		final tag = Lua.tostring(l, idx);
		if (tag == null)
			return null;
		final th = _tags.get(tag);
		return th != null ? _reg.get(th) : null;
	}

	static function _char(who:String):Dynamic
	{
		final p = _ps();
		if (p == null)
			return null;
		return switch who.toLowerCase()
		{
			case 'bf' | 'boyfriend' | 'player': try p.boyfriend catch (_) null;
			case 'dad' | 'opponent': try p.dad catch (_) null;
			case 'gf' | 'girlfriend': try p.gf catch (_) null;
			default: null;
		};
	}

	static function _resolvePath(path:String, root:Dynamic):Dynamic
	{
		if (root == null)
			return null;
		var o = root;
		for (p in path.split('.'))
		{
			try
				o = Reflect.getProperty(o, p)
			catch (_)
				return null;
		}
		return o;
	}

	static function _applyPath(path:String, v:Dynamic, root:Dynamic):Void
	{
		if (root == null)
			return;
		final parts = path.split('.');
		var o = root;
		for (i in 0...parts.length - 1)
			try
				o = Reflect.getProperty(o, parts[i])
			catch (_)
				return;
		try
		{
			Reflect.setProperty(o, parts[parts.length - 1], v);
		}
		catch (_)
		{
			try
				Reflect.setField(o, parts[parts.length - 1], v)
			catch (_)
			{
			};
		}
	}

	static function _key(n:String):Null<flixel.input.keyboard.FlxKey>
	{
		try
			return flixel.input.keyboard.FlxKey.fromString(n.toUpperCase())
		catch (_)
			return null;
	}

	/**
	 * Devuelve el FlxTweenManager de gameplay si estamos en PlayState,
	 * o el globalManager si no. Así los tweens de scripts se congelan
	 * automáticamente cuando el jugador pausa la partida.
	 */
	static inline function _tweenMgr():flixel.tweens.FlxTween.FlxTweenManager
		return funkin.gameplay.PlayState.gameplayTweens ?? flixel.tweens.FlxTween.globalManager;

	/**
	 * Devuelve el FlxTimerManager de gameplay si estamos en PlayState,
	 * o el globalManager si no.
	 */
	static inline function _timerMgr():flixel.util.FlxTimer.FlxTimerManager
		return funkin.gameplay.PlayState.gameplayTimers ?? flixel.util.FlxTimer.globalManager;

	static function _ease(n:String):Float->Float
		return switch n
		{
			case 'quadIn': flixel.tweens.FlxEase.quadIn;
			case 'quadOut': flixel.tweens.FlxEase.quadOut;
			case 'quadInOut': flixel.tweens.FlxEase.quadInOut;
			case 'cubeIn': flixel.tweens.FlxEase.cubeIn;
			case 'cubeOut': flixel.tweens.FlxEase.cubeOut;
			case 'cubeInOut': flixel.tweens.FlxEase.cubeInOut;
			case 'sineIn': flixel.tweens.FlxEase.sineIn;
			case 'sineOut': flixel.tweens.FlxEase.sineOut;
			case 'sineInOut': flixel.tweens.FlxEase.sineInOut;
			case 'bounceOut': flixel.tweens.FlxEase.bounceOut;
			case 'bounceIn': flixel.tweens.FlxEase.bounceIn;
			case 'elasticOut': flixel.tweens.FlxEase.elasticOut;
			case 'backIn': flixel.tweens.FlxEase.backIn;
			case 'backOut': flixel.tweens.FlxEase.backOut;
			default: flixel.tweens.FlxEase.linear;
		};

	static function _strum(idx:Int):Dynamic
	{
		final ps = _ps();
		if (ps == null)
			return null;
		return try idx == 0 ? ps.playerStrumline : ps.opponentStrumline catch (_) null;
	}

	static function _luaTableToOpts(l:Dynamic, idx:Int):Dynamic
	{
		final opts:Dynamic = {};
		Lua.pushnil(l);
		while (Lua.next(l, idx) != 0)
		{
			if (Lua.type(l, -2) == 4)
			{
				final key = Lua.tostring(l, -2);
				final vt = Lua.type(l, -1);
				if (vt == 1)
					Reflect.setField(opts, key, Lua.toboolean(l, -1));
				else if (vt == 3)
					Reflect.setField(opts, key, Lua.tonumber(l, -1));
				else if (vt == 4)
					Reflect.setField(opts, key, Lua.tostring(l, -1));
			}
			Lua.pop(l, 1);
		}
		return opts;
	}

	static function _resolveModulePath(path:String, scriptPath:Null<String>):Null<String>
	{
		#if sys
		if (FileSystem.exists(path))
			return path;
		if (FileSystem.exists(path + '.lua'))
			return path + '.lua';
		if (scriptPath != null)
		{
			final sep = scriptPath.indexOf('/') >= 0 ? '/' : '\\';
			final dir = scriptPath.substring(0, scriptPath.lastIndexOf(sep) + 1);
			if (FileSystem.exists(dir + path))
				return dir + path;
			if (FileSystem.exists(dir + path + '.lua'))
				return dir + path + '.lua';
		}
		if (mods.ModManager.isActive())
		{
			final mod = '${mods.ModManager.modRoot()}/$path';
			if (FileSystem.exists(mod))
				return mod;
			if (FileSystem.exists(mod + '.lua'))
				return mod + '.lua';
		}
		#end
		return null;
	}

	// ─────────────────────────────────────────────────────────────────────────
	// FACTORIES
	// ─────────────────────────────────────────────────────────────────────────

	static function _defaultFactories():Map<String, Array<Dynamic>->Dynamic>
	{
		return [
			'FlxSprite' => a -> new flixel.FlxSprite(a.length > 0 ? (a[0] : Float) : 0, a.length > 1 ? (a[1] : Float) : 0),
			'FlxText' => a -> new flixel.text.FlxText(a.length > 0 ? (a[0] : Float) : 0, a.length > 1 ? (a[1] : Float) : 0, a.length > 2 ? Std.int(a[2]) : 0,
				a.length > 3 ? Std.string(a[3]) : '', a.length > 4 ? Std.int(a[4]) : 16),
			'FlxSpriteGroup' => _ -> new flixel.group.FlxSpriteGroup(),
			'FlxGroup' => _ -> new flixel.group.FlxGroup(),
			'FlxCamera' => a -> new flixel.FlxCamera(a.length > 0 ? Std.int(a[0]) : 0, a.length > 1 ? Std.int(a[1]) : 0,
				a.length > 2 ? Std.int(a[2]) : flixel.FlxG.width, a.length > 3 ? Std.int(a[3]) : flixel.FlxG.height),
			'FlxTimer' => _ -> new flixel.util.FlxTimer(),
			'FunkinSprite' => a -> new animationdata.FunkinSprite(a.length > 0 ? (a[0] : Float) : 0, a.length > 1 ? (a[1] : Float) : 0),
		];
	}

	// ─────────────────────────────────────────────────────────────────────────
	// LEGACY FUNCTION IMPLEMENTATIONS (all preserved for backward compat)
	// ─────────────────────────────────────────────────────────────────────────
	// Object Registry
	static function _fnNew(l:Dynamic):Int
	{
		final cls = Lua.tostring(l, 1);
		final nArg = Lua.gettop(l) - 1;
		final args = [for (i in 0...nArg) _readOOP(l, i + 2)];
		Lua.settop(l, 0);
		final factory = _factories.get(cls);
		try
		{
			final obj = factory != null ? factory(args) : Type.createInstance(Type.resolveClass(cls) ?? Type.resolveClass('funkin.gameplay.$cls') ?? Type.resolveClass('funkin.menus.$cls') ?? Type.resolveClass('funkin.states.$cls') ?? Type.resolveClass('funkin.gameplay.notes.$cls'),
				args);
			if (obj == null)
			{
				Lua.pushnil(l);
				return 1;
			}
			_pushOOP(l, obj);
		}
		catch (e:Dynamic)
		{
			trace('[RuleScript] newObject($cls): $e');
			Lua.pushnil(l);
		}
		return 1;
	}

	static function _fnGetProp(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final f = Lua.tostring(l, 2);
		Lua.settop(l, 0);
		_pushOOP(l, _resolvePath(f, _reg.get(h)));
		return 1;
	}

	static function _fnSetProp(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final f = Lua.tostring(l, 2);
		final v = _readOOP(l, 3);
		Lua.settop(l, 0);
		_applyPath(f, v, _reg.get(h));
		return 0;
	}

	static function _fnCallMethod(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final m = Lua.tostring(l, 2);
		final na = Lua.gettop(l) - 2;
		final ar = [for (i in 0...na) _readOOP(l, i + 3)];
		Lua.settop(l, 0);
		final ob = _reg.get(h);
		if (ob == null)
		{
			Lua.pushnil(l);
			return 1;
		}
		try
		{
			var fn:Dynamic = null;
			try
				fn = Reflect.getProperty(ob, m)
			catch (_)
			{
			};
			if (fn == null)
				fn = Reflect.field(ob, m);
			_pushOOP(l, Reflect.callMethod(ob, fn, ar));
		}
		catch (e:Dynamic)
		{
			trace('[RuleScript] callMethod($m): $e');
			Lua.pushnil(l);
		}
		return 1;
	}

	static function _fnDestroy(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		Lua.settop(l, 0);
		final o = _reg.get(h);
		if (o != null)
		{
			try
				(o : Dynamic).destroy()
			catch (_)
			{
			};
			release(h);
		}
		return 0;
	}

	// Scene
	static function _fnAddState(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final front = Lua.gettop(l) > 1 && Lua.toboolean(l, 2);
		Lua.settop(l, 0);
		final o = _reg.get(h);
		if (o == null)
			return 0;
		if (front)
			flixel.FlxG.state.add(o)
		else
			flixel.FlxG.state.insert(0, o);
		return 0;
	}

	static function _fnRemState(l:Dynamic):Int
	{
		final o = _reg.get(_handle(l, 1));
		Lua.settop(l, 0);
		if (o != null)
			flixel.FlxG.state.remove(o, true);
		return 0;
	}

	static function _fnAddGroup(l:Dynamic):Int
	{
		final g = _reg.get(_handle(l, 1));
		final o = _reg.get(_handle(l, 2));
		Lua.settop(l, 0);
		if (g != null && o != null)
			try
				(g : Dynamic).add(o)
			catch (_)
			{
			};
		return 0;
	}

	static function _fnRemGroup(l:Dynamic):Int
	{
		final g = _reg.get(_handle(l, 1));
		final o = _reg.get(_handle(l, 2));
		Lua.settop(l, 0);
		if (g != null && o != null)
			try
				(g : Dynamic).remove(o, true)
			catch (_)
			{
			};
		return 0;
	}

	// Path-style
	static function _fnGetPath(l:Dynamic):Int
	{
		final p = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		_pushOOP(l, _resolvePath(p, _ps()));
		return 1;
	}

	static function _fnSetPath(l:Dynamic):Int
	{
		final p = Lua.tostring(l, 1);
		final v = _readOOP(l, 2);
		Lua.settop(l, 0);
		_applyPath(p, v, _ps());
		return 0;
	}

	static function _fnGetOf(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final p = Lua.tostring(l, 2);
		Lua.settop(l, 0);
		_pushOOP(l, _resolvePath(p, _reg.get(h)));
		return 1;
	}

	static function _fnSetOf(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final p = Lua.tostring(l, 2);
		final v = _readOOP(l, 3);
		Lua.settop(l, 0);
		_applyPath(p, v, _reg.get(h));
		return 0;
	}

	// Characters
	static function _fnTriggerAnim(l:Dynamic):Int
	{
		final w = Lua.tostring(l, 1);
		final a = Lua.tostring(l, 2);
		final f = Lua.gettop(l) > 2 && Lua.toboolean(l, 3);
		Lua.settop(l, 0);
		final c = _char(w);
		if (c != null)
			c.playAnim(a, f);
		return 0;
	}

	static function _fnDance(l:Dynamic):Int
	{
		final c = _char(Lua.tostring(l, 1));
		Lua.settop(l, 0);
		if (c != null)
			try
				c.dance()
			catch (_)
				c.playAnim('idle', false);
		return 0;
	}

	static function _fnCharHandle(l:Dynamic):Int
	{
		final c = _char(Lua.tostring(l, 1));
		Lua.settop(l, 0);
		if (c == null)
		{
			Lua.pushnil(l);
			return 1;
		}
		_pushOOP(l, c);
		return 1;
	}

	static function _fnCharPos(l:Dynamic):Int
	{
		final c = _char(Lua.tostring(l, 1));
		final x = Lua.tonumber(l, 2);
		final y = Lua.tonumber(l, 3);
		Lua.settop(l, 0);
		if (c != null)
		{
			c.x = x;
			c.y = y;
		}
		return 0;
	}

	static function _fnCharX(l:Dynamic):Int
	{
		final c = _char(Lua.tostring(l, 1));
		final x = Lua.tonumber(l, 2);
		Lua.settop(l, 0);
		if (c != null)
			c.x = x;
		return 0;
	}

	static function _fnCharY(l:Dynamic):Int
	{
		final c = _char(Lua.tostring(l, 1));
		final y = Lua.tonumber(l, 2);
		Lua.settop(l, 0);
		if (c != null)
			c.y = y;
		return 0;
	}

	static function _fnCharGetX(l:Dynamic):Int
	{
		final c = _char(Lua.tostring(l, 1));
		Lua.settop(l, 0);
		Lua.pushnumber(l, c != null ? c.x : 0);
		return 1;
	}

	static function _fnCharGetY(l:Dynamic):Int
	{
		final c = _char(Lua.tostring(l, 1));
		Lua.settop(l, 0);
		Lua.pushnumber(l, c != null ? c.y : 0);
		return 1;
	}

	static function _fnCharScale(l:Dynamic):Int
	{
		final c = _char(Lua.tostring(l, 1));
		final s = Lua.tonumber(l, 2);
		Lua.settop(l, 0);
		if (c != null)
		{
			c.scale.x = s;
			c.scale.y = s;
		}
		return 0;
	}

	static function _fnCharVisible(l:Dynamic):Int
	{
		final c = _char(Lua.tostring(l, 1));
		final v = Lua.toboolean(l, 2);
		Lua.settop(l, 0);
		if (c != null)
			c.visible = v;
		return 0;
	}

	static function _fnCharAlpha(l:Dynamic):Int
	{
		final c = _char(Lua.tostring(l, 1));
		final a = Lua.tonumber(l, 2);
		Lua.settop(l, 0);
		if (c != null)
			c.alpha = a;
		return 0;
	}

	static function _fnCharColor(l:Dynamic):Int
	{
		final c = _char(Lua.tostring(l, 1));
		final col = Std.int(Lua.tonumber(l, 2));
		Lua.settop(l, 0);
		if (c != null)
			c.color = col;
		return 0;
	}

	static function _fnCharAngle(l:Dynamic):Int
	{
		final c = _char(Lua.tostring(l, 1));
		final a = Lua.tonumber(l, 2);
		Lua.settop(l, 0);
		if (c != null)
			c.angle = a;
		return 0;
	}

	static function _fnCharFlip(l:Dynamic):Int
	{
		final c = _char(Lua.tostring(l, 1));
		final fx = Lua.toboolean(l, 2);
		Lua.settop(l, 0);
		if (c != null)
			c.flipX = fx;
		return 0;
	}

	static function _fnCharScroll(l:Dynamic):Int
	{
		final c = _char(Lua.tostring(l, 1));
		final sx = Lua.tonumber(l, 2);
		final sy = Lua.tonumber(l, 3);
		Lua.settop(l, 0);
		if (c != null)
		{
			c.scrollFactor.x = sx;
			c.scrollFactor.y = sy;
		}
		return 0;
	}

	static function _fnCharGetAnim(l:Dynamic):Int
	{
		final c = _char(Lua.tostring(l, 1));
		Lua.settop(l, 0);
		Lua.pushstring(l, c != null ?try c.animation.curAnim.name catch (_) '':'');
		return 1;
	}

	static function _fnCharAnimDone(l:Dynamic):Int
	{
		final c = _char(Lua.tostring(l, 1));
		Lua.settop(l, 0);
		Lua.pushboolean(l, c != null ? try c.animation.finished catch (_) false : false);
		return 1;
	}

	static function _fnCharLock(l:Dynamic):Int
	{
		final c = _char(Lua.tostring(l, 1));
		final v = Lua.toboolean(l, 2);
		Lua.settop(l, 0);
		if (c != null)
			try
				Reflect.setField(c, 'specialAnim', v)
			catch (_)
			{
			};
		return 0;
	}

	static function _fnCharRate(l:Dynamic):Int
	{
		final c = _char(Lua.tostring(l, 1));
		final r = Lua.tonumber(l, 2);
		Lua.settop(l, 0);
		if (c != null)
			try
				c.animation.timeScale = r
			catch (_)
			{
			};
		return 0;
	}

	static function _fnSetBF(l:Dynamic):Int
	{
		final name = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		final p = _ps();
		if (p != null)
			try
				p.changeBF(name)
			catch (_)
			{
			};
		return 0;
	}

	static function _fnSetDAD(l:Dynamic):Int
	{
		final name = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		final p = _ps();
		if (p != null)
			try
				p.changeDAD(name)
			catch (_)
			{
			};
		return 0;
	}

	static function _fnSetGF(l:Dynamic):Int
	{
		final name = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		final p = _ps();
		if (p != null)
			try
				p.changeGF(name)
			catch (_)
			{
			};
		return 0;
	}

	// Health icons
	static function _fnSetHIcon(l:Dynamic):Int
	{
		final who = Lua.tostring(l, 1);
		final key = Lua.tostring(l, 2);
		Lua.settop(l, 0);
		final ps = _ps();
		if (ps == null)
			return 0;
		try
		{
			final ic = who == 'player' ? ps.healthIconP1 : ps.healthIconP2;
			if (ic != null)
				ic.loadHealthIcon(key);
		}
		catch (_)
		{
		};
		return 0;
	}

	static function _fnSetHIconScale(l:Dynamic):Int
	{
		final who = Lua.tostring(l, 1);
		final sc = Lua.tonumber(l, 2);
		Lua.settop(l, 0);
		final ps = _ps();
		if (ps == null)
			return 0;
		try
		{
			final ic = who == 'player' ? ps.healthIconP1 : ps.healthIconP2;
			if (ic != null)
				ic.setGraphicSize(Std.int(ic.width * sc));
		}
		catch (_)
		{
		};
		return 0;
	}

	static function _fnSetHIconOffset(l:Dynamic):Int
	{
		final who = Lua.tostring(l, 1);
		final dx = Lua.tonumber(l, 2);
		final dy = Lua.tonumber(l, 3);
		Lua.settop(l, 0);
		final ps = _ps();
		if (ps == null)
			return 0;
		try
		{
			final ic = who == 'player' ? ps.healthIconP1 : ps.healthIconP2;
			if (ic != null)
			{
				ic.offset.x = dx;
				ic.offset.y = dy;
			}
		}
		catch (_)
		{
		};
		return 0;
	}

	static function _fnGetHIconHandle(l:Dynamic):Int
	{
		final who = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		final ps = _ps();
		if (ps == null)
		{
			Lua.pushnil(l);
			return 1;
		}
		final ic = try who == 'player' ? ps.healthIconP1 : ps.healthIconP2 catch (_) null;
		if (ic == null)
		{
			Lua.pushnil(l);
			return 1;
		}
		_pushOOP(l, ic);
		return 1;
	}

	// Strumlines
	static function _fnStrumAlpha(l:Dynamic):Int
	{
		final s = _strum(Std.int(Lua.tonumber(l, 1)));
		final a = Lua.tonumber(l, 2);
		Lua.settop(l, 0);
		if (s != null)
			s.alpha = a;
		return 0;
	}

	static function _fnStrumScale(l:Dynamic):Int
	{
		final s = _strum(Std.int(Lua.tonumber(l, 1)));
		final sc = Lua.tonumber(l, 2);
		Lua.settop(l, 0);
		if (s != null)
		{
			s.scale.x = sc;
			s.scale.y = sc;
		}
		return 0;
	}

	static function _fnStrumPos(l:Dynamic):Int
	{
		final s = _strum(Std.int(Lua.tonumber(l, 1)));
		final x = Lua.tonumber(l, 2);
		final y = Lua.tonumber(l, 3);
		Lua.settop(l, 0);
		if (s != null)
		{
			s.x = x;
			s.y = y;
		}
		return 0;
	}

	static function _fnStrumHide(l:Dynamic):Int
	{
		final s = _strum(Std.int(Lua.tonumber(l, 1)));
		final h = Lua.toboolean(l, 2);
		Lua.settop(l, 0);
		if (s != null)
			s.visible = !h;
		return 0;
	}

	static function _fnStrumHandle(l:Dynamic):Int
	{
		final s = _strum(Std.int(Lua.tonumber(l, 1)));
		Lua.settop(l, 0);
		if (s == null)
		{
			Lua.pushnil(l);
			return 1;
		}
		_pushOOP(l, s);
		return 1;
	}

	// Sprites (core)
	static function _fnMakeSprite(l:Dynamic):Int
	{
		final tag = Lua.tostring(l, 1);
		final x = Lua.gettop(l) > 1 ? Lua.tonumber(l, 2) : 0.0;
		final y = Lua.gettop(l) > 2 ? Lua.tonumber(l, 3) : 0.0;
		Lua.settop(l, 0);
		final spr = new flixel.FlxSprite(x, y);
		final h = register(spr);
		if (tag != null)
			_tags.set(tag, h);
		_pushOOP(l, spr);
		return 1;
	}

	static function _fnMakeFunkin(l:Dynamic):Int
	{
		final tag = Lua.tostring(l, 1);
		final x = Lua.gettop(l) > 1 ? Lua.tonumber(l, 2) : 0.0;
		final y = Lua.gettop(l) > 2 ? Lua.tonumber(l, 3) : 0.0;
		Lua.settop(l, 0);
		final spr = new animationdata.FunkinSprite(x, y);
		final h = register(spr);
		if (tag != null)
			_tags.set(tag, h);
		_pushOOP(l, spr);
		return 1;
	}

	static function _fnLoadImg(l:Dynamic):Int
	{
		final s = _spr(l);
		final p = Lua.tostring(l, 2);
		Lua.settop(l, 0);
		if (s != null)
			try
				s.loadGraphic(Paths.image(p))
			catch (_)
			{
			};
		return 0;
	}

	static function _fnLoadSparrow(l:Dynamic):Int
	{
		final s = _spr(l);
		final p = Lua.tostring(l, 2);
		Lua.settop(l, 0);
		if (s != null)
			try
				s.frames = Paths.getSparrowAtlas(p)
			catch (_)
			{
			};
		return 0;
	}

	static function _fnLoadAtlas(l:Dynamic):Int
	{
		final s = _spr(l);
		final p = Lua.tostring(l, 2);
		Lua.settop(l, 0);
		if (s != null)
			try
				s.frames = Paths.getPackerAtlas(p)
			catch (_)
			{
			};
		return 0;
	}

	static function _fnAddAnim(l:Dynamic):Int
	{
		final s = _spr(l);
		final n = Lua.tostring(l, 2);
		final prefix = Lua.tostring(l, 3);
		final fps = Lua.gettop(l) > 3 ? Std.int(Lua.tonumber(l, 4)) : 24;
		final loop = Lua.gettop(l) > 4 && Lua.toboolean(l, 5);
		Lua.settop(l, 0);
		if (s != null)
			try
				s.animation.addByPrefix(n, prefix, fps, loop)
			catch (_)
			{
			};
		return 0;
	}

	static function _fnAddAnimOff(l:Dynamic):Int
	{
		final s = _spr(l);
		final n = Lua.tostring(l, 2);
		final x = Lua.tonumber(l, 3);
		final y = Lua.tonumber(l, 4);
		Lua.settop(l, 0);
		if (s != null)
			try
				(s : animationdata.FunkinSprite).applyAnimOffset(x, y)
			catch (_)
			{
			};
		return 0;
	}

	static function _fnPlayAnim(l:Dynamic):Int
	{
		final s = _spr(l);
		final n = Lua.tostring(l, 2);
		final f = Lua.gettop(l) > 2 && Lua.toboolean(l, 3);
		Lua.settop(l, 0);
		if (s != null)
			try
				s.animation.play(n, f)
			catch (_)
			{
			};
		return 0;
	}

	static function _fnStopAnim(l:Dynamic):Int
	{
		final s = _spr(l);
		Lua.settop(l, 0);
		if (s != null)
			try
				s.animation.stop()
			catch (_)
			{
			};
		return 0;
	}

	static function _fnAddSpr(l:Dynamic):Int
	{
		final s = _spr(l);
		final front = Lua.gettop(l) < 2 || Lua.toboolean(l, 2);
		Lua.settop(l, 0);
		if (s != null)
		{
			if (front)
				flixel.FlxG.state.add(s)
			else
				flixel.FlxG.state.insert(0, s);
		}
		return 0;
	}

	static function _fnRemSpr(l:Dynamic):Int
	{
		final s = _spr(l);
		Lua.settop(l, 0);
		if (s != null)
			flixel.FlxG.state.remove(s, true);
		return 0;
	}

	static function _fnSprScale(l:Dynamic):Int
	{
		final s = _spr(l);
		final sx = Lua.tonumber(l, 2);
		final sy = Lua.gettop(l) > 2 ? Lua.tonumber(l, 3) : sx;
		Lua.settop(l, 0);
		if (s != null)
		{
			s.scale.x = sx;
			s.scale.y = sy;
		}
		return 0;
	}

	static function _fnSprFlip(l:Dynamic):Int
	{
		final s = _spr(l);
		final fx = Lua.toboolean(l, 2);
		final fy = Lua.gettop(l) > 2 && Lua.toboolean(l, 3);
		Lua.settop(l, 0);
		if (s != null)
		{
			s.flipX = fx;
			s.flipY = fy;
		}
		return 0;
	}

	static function _fnSprAlpha(l:Dynamic):Int
	{
		final s = _spr(l);
		final a = Lua.tonumber(l, 2);
		Lua.settop(l, 0);
		if (s != null)
			s.alpha = a;
		return 0;
	}

	static function _fnSprColor(l:Dynamic):Int
	{
		final s = _spr(l);
		final c = Std.int(Lua.tonumber(l, 2));
		Lua.settop(l, 0);
		if (s != null)
			s.color = c;
		return 0;
	}

	static function _fnSprPos(l:Dynamic):Int
	{
		final s = _spr(l);
		final x = Lua.tonumber(l, 2);
		final y = Lua.tonumber(l, 3);
		Lua.settop(l, 0);
		if (s != null)
		{
			s.x = x;
			s.y = y;
		}
		return 0;
	}

	static function _fnSprScroll(l:Dynamic):Int
	{
		final s = _spr(l);
		final sx = Lua.tonumber(l, 2);
		final sy = Lua.tonumber(l, 3);
		Lua.settop(l, 0);
		if (s != null)
		{
			s.scrollFactor.x = sx;
			s.scrollFactor.y = sy;
		}
		return 0;
	}

	static function _fnSprAA(l:Dynamic):Int
	{
		final s = _spr(l);
		final v = Lua.toboolean(l, 2);
		Lua.settop(l, 0);
		if (s != null)
			s.antialiasing = v;
		return 0;
	}

	static function _fnSprCenter(l:Dynamic):Int
	{
		final s = _spr(l);
		Lua.settop(l, 0);
		if (s != null)
			s.screenCenter();
		return 0;
	}

	static function _fnSprAngle(l:Dynamic):Int
	{
		final s = _spr(l);
		final a = Lua.tonumber(l, 2);
		Lua.settop(l, 0);
		if (s != null)
			s.angle = a;
		return 0;
	}

	static function _fnSprVisible(l:Dynamic):Int
	{
		final s = _spr(l);
		final v = Lua.toboolean(l, 2);
		Lua.settop(l, 0);
		if (s != null)
			s.visible = v;
		return 0;
	}

	static function _fnSprGetX(l:Dynamic):Int
	{
		final s = _spr(l);
		Lua.settop(l, 0);
		Lua.pushnumber(l, s != null ? s.x : 0);
		return 1;
	}

	static function _fnSprGetY(l:Dynamic):Int
	{
		final s = _spr(l);
		Lua.settop(l, 0);
		Lua.pushnumber(l, s != null ? s.y : 0);
		return 1;
	}

	static function _fnSprGetW(l:Dynamic):Int
	{
		final s = _spr(l);
		Lua.settop(l, 0);
		Lua.pushnumber(l, s != null ? s.width : 0);
		return 1;
	}

	static function _fnSprGetH(l:Dynamic):Int
	{
		final s = _spr(l);
		Lua.settop(l, 0);
		Lua.pushnumber(l, s != null ? s.height : 0);
		return 1;
	}

	static function _fnUpdateHitbox(l:Dynamic):Int
	{
		final s = _spr(l);
		Lua.settop(l, 0);
		if (s != null)
			try
				s.updateHitbox()
			catch (_)
			{
			};
		return 0;
	}

	static function _fnAddAnimIdx(l:Dynamic):Int
	{
		final s = _spr(l);
		final n = Lua.tostring(l, 2);
		final prefix = Lua.tostring(l, 3);
		final nIdx = Lua.gettop(l) - 3;
		final indices = [for (i in 0...nIdx) Std.int(Lua.tonumber(l, i + 4))];
		Lua.settop(l, 0);
		if (s != null)
			try
				s.animation.addByIndices(n, prefix, indices, '', 24, false)
			catch (_)
			{
			};
		return 0;
	}

	static function _fnGetCurAnim(l:Dynamic):Int
	{
		final s = _spr(l);
		Lua.settop(l, 0);
		Lua.pushstring(l, s != null ?try s.animation.curAnim.name catch (_) '':'');
		return 1;
	}

	static function _fnIsAnimPlay(l:Dynamic):Int
	{
		final s = _spr(l);
		final n = Lua.tostring(l, 2);
		Lua.settop(l, 0);
		Lua.pushboolean(l, s != null ? try s.animation.curAnim.name == n catch (_) false : false);
		return 1;
	}

	static function _fnSetAnimFPS(l:Dynamic):Int
	{
		final s = _spr(l);
		final fps = Std.int(Lua.tonumber(l, 2));
		Lua.settop(l, 0);
		if (s != null)
			try
				s.animation.curAnim.frameRate = fps
			catch (_)
			{
			};
		return 0;
	}

	static function _fnSprCam(l:Dynamic):Int
	{
		final s = _spr(l);
		final camName = Lua.tostring(l, 2);
		Lua.settop(l, 0);
		if (s != null)
			try
			{
				final cam:Dynamic = switch (camName ?? 'game')
				{
					case 'hud': flixel.FlxG.state.members[1];
					case 'ui': flixel.FlxG.state.members[2];
					default: flixel.FlxG.camera;
				};
				s.cameras = [cam];
			}
			catch (_)
			{
			};
		return 0;
	}

	static function _fnFrameSize(l:Dynamic):Int
	{
		final s = _spr(l);
		final w = Std.int(Lua.tonumber(l, 2));
		final h2 = Std.int(Lua.tonumber(l, 3));
		Lua.settop(l, 0);
		if (s != null)
			try
				s.setGraphicSize(w, h2)
			catch (_)
			{
			};
		return 0;
	}

	// Text
	static function _fnMakeText(l:Dynamic):Int
	{
		final x = Lua.tonumber(l, 1);
		final y = Lua.tonumber(l, 2);
		final w = Std.int(Lua.tonumber(l, 3));
		final txt = Lua.tostring(l, 4);
		final size = Lua.gettop(l) > 4 ? Std.int(Lua.tonumber(l, 5)) : 16;
		Lua.settop(l, 0);
		final t = new flixel.text.FlxText(x, y, w, txt, size);
		_pushOOP(l, t);
		return 1;
	}

	static function _fnSetText(l:Dynamic):Int
	{
		final s = _spr(l);
		final t = Lua.tostring(l, 2);
		Lua.settop(l, 0);
		if (s != null)
			try
				(s : flixel.text.FlxText).text = t
			catch (_)
			{
			};
		return 0;
	}

	static function _fnTextSize(l:Dynamic):Int
	{
		final s = _spr(l);
		final sz = Std.int(Lua.tonumber(l, 2));
		Lua.settop(l, 0);
		if (s != null)
			try
				(s : flixel.text.FlxText).size = sz
			catch (_)
			{
			};
		return 0;
	}

	static function _fnTextFont(l:Dynamic):Int
	{
		final s = _spr(l);
		final f = Lua.tostring(l, 2);
		Lua.settop(l, 0);
		if (s != null)
			try
				(s : flixel.text.FlxText).font = f
			catch (_)
			{
			};
		return 0;
	}

	static function _fnTextBold(l:Dynamic):Int
	{
		final s = _spr(l);
		final b = Lua.toboolean(l, 2);
		Lua.settop(l, 0);
		if (s != null)
			try
				(s : flixel.text.FlxText).bold = b
			catch (_)
			{
			};
		return 0;
	}

	static function _fnTextAlign(l:Dynamic):Int
	{
		final s = _spr(l);
		final a = Lua.tostring(l, 2);
		Lua.settop(l, 0);
		if (s != null)
			try
				(s : flixel.text.FlxText).alignment = cast a
			catch (_)
			{
			};
		return 0;
	}

	static function _fnTextBorder(l:Dynamic):Int
	{
		final s = _spr(l);
		final sz = Lua.tonumber(l, 2);
		final c = Std.int(Lua.tonumber(l, 3));
		Lua.settop(l, 0);
		if (s != null)
			try
			{
				final t:flixel.text.FlxText = cast s;
				t.setBorderStyle(flixel.text.FlxText.FlxTextBorderStyle.OUTLINE, c, sz);
			}
			catch (_)
			{
			};
		return 0;
	}

	static function _fnTextColor(l:Dynamic):Int
	{
		final s = _spr(l);
		final c = Std.int(Lua.tonumber(l, 2));
		Lua.settop(l, 0);
		if (s != null)
			try
				(s : flixel.text.FlxText).color = c
			catch (_)
			{
			};
		return 0;
	}

	static function _fnTextItalic(l:Dynamic):Int
	{
		final s = _spr(l);
		final v = Lua.toboolean(l, 2);
		Lua.settop(l, 0);
		if (s != null)
			try
				(s : flixel.text.FlxText).italic = v
			catch (_)
			{
			};
		return 0;
	}

	static function _fnTextShadow(l:Dynamic):Int
	{
		final s = _spr(l);
		final c = Std.int(Lua.tonumber(l, 2));
		final sz = Lua.tonumber(l, 3);
		Lua.settop(l, 0);
		if (s != null)
			try
			{
				final t:flixel.text.FlxText = cast s;
				t.setBorderStyle(flixel.text.FlxText.FlxTextBorderStyle.SHADOW, c, sz);
			}
			catch (_)
			{
			};
		return 0;
	}

	static function _fnGetText(l:Dynamic):Int
	{
		final s = _spr(l);
		Lua.settop(l, 0);
		Lua.pushstring(l, s != null ?try (s : flixel.text.FlxText).text catch (_) '':'');
		return 1;
	}

	// Camera
	static function _fnCamZoom(l:Dynamic):Int
	{
		final z = Lua.tonumber(l, 1);
		Lua.settop(l, 0);
		flixel.FlxG.camera.zoom = z;
		return 0;
	}

	static function _fnCamZoomTween(l:Dynamic):Int
	{
		final z = Lua.tonumber(l, 1);
		final dur = Lua.tonumber(l, 2);
		final ease = Lua.gettop(l) > 2 ? Lua.tostring(l, 3) : 'linear';
		Lua.settop(l, 0);
		_tweenMgr().tween(flixel.FlxG.camera, {zoom: z}, dur, {ease: _ease(ease)});
		return 0;
	}

	static function _fnCamFlash(l:Dynamic):Int
	{
		final c = Lua.tostring(l, 1);
		final dur = Lua.gettop(l) > 1 ? Lua.tonumber(l, 2) : 0.5;
		Lua.settop(l, 0);
		flixel.FlxG.camera.flash(flixel.util.FlxColor.fromString(c ?? 'white'), dur);
		return 0;
	}

	static function _fnCamShake(l:Dynamic):Int
	{
		final i = Lua.tonumber(l, 1);
		final dur = Lua.tonumber(l, 2);
		Lua.settop(l, 0);
		flixel.FlxG.camera.shake(i, dur);
		return 0;
	}

	static function _fnCamFade(l:Dynamic):Int
	{
		final c = Lua.tostring(l, 1);
		final dur = Lua.gettop(l) > 1 ? Lua.tonumber(l, 2) : 1.0;
		Lua.settop(l, 0);
		flixel.FlxG.camera.fade(flixel.util.FlxColor.fromString(c ?? 'black'), dur);
		return 0;
	}

	static function _fnCamPan(l:Dynamic):Int
	{
		final x = Lua.tonumber(l, 1);
		final y = Lua.tonumber(l, 2);
		final dur = Lua.tonumber(l, 3);
		Lua.settop(l, 0);
		_tweenMgr().tween(flixel.FlxG.camera.scroll, {x: x, y: y}, dur);
		return 0;
	}

	static function _fnCamSnap(l:Dynamic):Int
	{
		final x = Lua.tonumber(l, 1);
		final y = Lua.tonumber(l, 2);
		Lua.settop(l, 0);
		flixel.FlxG.camera.scroll.set(x, y);
		return 0;
	}

	static function _fnCamHandle(l:Dynamic):Int
	{
		final name = Lua.gettop(l) > 0 ? Lua.tostring(l, 1) : 'game';
		Lua.settop(l, 0);
		final cam:Dynamic = switch (name ?? 'game')
		{
			case 'hud': try flixel.FlxG.state.members[1] catch (_) flixel.FlxG.camera;
			case 'ui': try flixel.FlxG.state.members[2] catch (_) flixel.FlxG.camera;
			default: flixel.FlxG.camera;
		};
		_pushOOP(l, cam);
		return 1;
	}

	static function _fnMakeCam(l:Dynamic):Int
	{
		final x = Lua.gettop(l) > 0 ? Std.int(Lua.tonumber(l, 1)) : 0;
		final y = Lua.gettop(l) > 1 ? Std.int(Lua.tonumber(l, 2)) : 0;
		final w = Lua.gettop(l) > 2 ? Std.int(Lua.tonumber(l, 3)) : flixel.FlxG.width;
		final h = Lua.gettop(l) > 3 ? Std.int(Lua.tonumber(l, 4)) : flixel.FlxG.height;
		Lua.settop(l, 0);
		final cam = new flixel.FlxCamera(x, y, w, h);
		flixel.FlxG.cameras.add(cam, false);
		_pushOOP(l, cam);
		return 1;
	}

	static function _fnCamTarget(l:Dynamic):Int
	{
		final o = _reg.get(_handle(l, 1));
		Lua.settop(l, 0);
		if (o != null)
			flixel.FlxG.camera.follow(o);
		return 0;
	}

	static function _fnCamFollow(l:Dynamic):Int
	{
		final style = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		final s:Dynamic = switch (style ?? 'lockon')
		{
			case 'lockon': flixel.FlxCamera.FlxCameraFollowStyle.LOCKON;
			case 'platformer': flixel.FlxCamera.FlxCameraFollowStyle.PLATFORMER;
			case 'topdown': flixel.FlxCamera.FlxCameraFollowStyle.TOPDOWN;
			case 'screen_by_screen': flixel.FlxCamera.FlxCameraFollowStyle.SCREEN_BY_SCREEN;
			default: flixel.FlxCamera.FlxCameraFollowStyle.LOCKON;
		};
		flixel.FlxG.camera.follow(flixel.FlxG.camera.target, s);
		return 0;
	}

	static function _fnCamLerp(l:Dynamic):Int
	{
		final v = Lua.tonumber(l, 1);
		Lua.settop(l, 0);
		flixel.FlxG.camera.followLerp = v;
		return 0;
	}

	static function _fnGetCamZoom(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		Lua.pushnumber(l, flixel.FlxG.camera.zoom);
		return 1;
	}

	static function _fnCamScrollX(l:Dynamic):Int
	{
		final v = Lua.tonumber(l, 1);
		Lua.settop(l, 0);
		flixel.FlxG.camera.scroll.x = v;
		return 0;
	}

	static function _fnCamScrollY(l:Dynamic):Int
	{
		final v = Lua.tonumber(l, 1);
		Lua.settop(l, 0);
		flixel.FlxG.camera.scroll.y = v;
		return 0;
	}

	static function _fnRemoveCam(l:Dynamic):Int
	{
		final c = _reg.get(_handle(l, 1));
		Lua.settop(l, 0);
		if (c != null)
			try
				flixel.FlxG.cameras.remove(c)
			catch (_)
			{
			};
		return 0;
	}

	// Tweens
	static function _fnTweenProp(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final field = Lua.tostring(l, 2);
		final to = Lua.tonumber(l, 3);
		final dur = Lua.tonumber(l, 4);
		final ease = Lua.gettop(l) > 4 ? Lua.tostring(l, 5) : 'linear';
		Lua.settop(l, 0);
		final obj = _reg.get(h);
		if (obj == null)
			return 0;
		final props:Dynamic = {};
		Reflect.setField(props, field, to);
		final tw = _tweenMgr().tween(obj, props, dur, {ease: _ease(ease)});
		_pushOOP(l, tw);
		return 1;
	}

	static function _fnTweenColor(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final dur = Lua.tonumber(l, 2);
		final from = Std.int(Lua.tonumber(l, 3));
		final to = Std.int(Lua.tonumber(l, 4));
		Lua.settop(l, 0);
		final obj = _reg.get(h);
		if (obj == null)
			return 0;
		final tw = _tweenMgr().color(obj, dur, from, to);
		_pushOOP(l, tw);
		return 1;
	}

	static function _fnTweenCancel(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		Lua.settop(l, 0);
		final tw = _reg.get(h);
		if (tw != null)
			try
				tw.cancel()
			catch (_)
			{
			};
		return 0;
	}

	static function _fnTweenAngle(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final to = Lua.tonumber(l, 2);
		final dur = Lua.tonumber(l, 3);
		final ease = Lua.gettop(l) > 3 ? Lua.tostring(l, 4) : 'linear';
		Lua.settop(l, 0);
		final obj = _reg.get(h);
		if (obj == null)
			return 0;
		final tw = _tweenMgr().tween(obj, {angle: to}, dur, {ease: _ease(ease)});
		_pushOOP(l, tw);
		return 1;
	}

	static function _fnTweenPos(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final tx = Lua.tonumber(l, 2);
		final ty = Lua.tonumber(l, 3);
		final dur = Lua.tonumber(l, 4);
		final ease = Lua.gettop(l) > 4 ? Lua.tostring(l, 5) : 'linear';
		Lua.settop(l, 0);
		final obj = _reg.get(h);
		if (obj == null)
			return 0;
		final tw = _tweenMgr().tween(obj, {x: tx, y: ty}, dur, {ease: _ease(ease)});
		_pushOOP(l, tw);
		return 1;
	}

	static function _fnTweenAlpha(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final to = Lua.tonumber(l, 2);
		final dur = Lua.tonumber(l, 3);
		final ease = Lua.gettop(l) > 3 ? Lua.tostring(l, 4) : 'linear';
		Lua.settop(l, 0);
		final obj = _reg.get(h);
		if (obj == null)
			return 0;
		final tw = _tweenMgr().tween(obj, {alpha: to}, dur, {ease: _ease(ease)});
		_pushOOP(l, tw);
		return 1;
	}

	static function _fnTweenScale(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final to = Lua.tonumber(l, 2);
		final dur = Lua.tonumber(l, 3);
		final ease = Lua.gettop(l) > 3 ? Lua.tostring(l, 4) : 'linear';
		Lua.settop(l, 0);
		final obj = _reg.get(h);
		if (obj == null)
			return 0;
		final tw = _tweenMgr().tween(obj, {'scale.x': to, 'scale.y': to}, dur, {ease: _ease(ease)});
		_pushOOP(l, tw);
		return 1;
	}

	static function _fnNumTween(l:Dynamic):Int
	{
		final from = Lua.tonumber(l, 1);
		final to = Lua.tonumber(l, 2);
		final dur = Lua.tonumber(l, 3);
		final cbName = Lua.tostring(l, 4);
		final ease = Lua.gettop(l) > 4 ? Lua.tostring(l, 5) : 'linear';
		Lua.settop(l, 0);
		final luaRef = _sCurrentLua;
		final tw = _tweenMgr().num(from, to, dur, {ease: _ease(ease)}, function(v:Float)
		{
			Lua.getglobal(luaRef, cbName);
			if (Lua.type(luaRef, -1) == 6)
			{
				Lua.pushnumber(luaRef, v);
				Lua.pcall(luaRef, 1, 0, 0);
			}
			else
				Lua.pop(luaRef, 1);
		});
		_pushOOP(l, tw);
		return 1;
	}

	// Timers
	static function _fnTimer(l:Dynamic):Int
	{
		final dur = Lua.tonumber(l, 1);
		final cbName = Lua.tostring(l, 2);
		final loops = Lua.gettop(l) > 2 ? Std.int(Lua.tonumber(l, 3)) : 1;
		Lua.settop(l, 0);
		final luaRef = _sCurrentLua;
		final t = new flixel.util.FlxTimer(_timerMgr());
		t.start(dur, function(_)
		{
			Lua.getglobal(luaRef, cbName);
			if (Lua.type(luaRef, -1) == 6)
				Lua.pcall(luaRef, 0, 0, 0)
			else
				Lua.pop(luaRef, 1);
		}, loops);
		_pushOOP(l, t);
		return 1;
	}

	static function _fnTimerCancel(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		Lua.settop(l, 0);
		final t = _reg.get(h);
		if (t != null)
			try
				t.cancel()
			catch (_)
			{
			};
		return 0;
	}

	// Cutscenes
	static function _fnCutNew(l:Dynamic):Int
	{
		final key = Lua.gettop(l) > 0 ? Lua.tostring(l, 1) : '';
		final song = Lua.gettop(l) > 1 ? Lua.tostring(l, 2) : null;
		Lua.settop(l, 0);
		try
		{
			final b = new funkin.cutscenes.SpriteCutscene(flixel.FlxG.state, key ?? '', song);
			_pushOOP(l, b);
		}
		catch (_)
		{
			Lua.pushnil(l);
		}
		return 1;
	}

	static function _fnCutSkip(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final v = Lua.toboolean(l, 2);
		Lua.settop(l, 0);
		final b = _reg.get(h);
		if (b != null)
			try
				b.skippable = v
			catch (_)
			{
			};
		return 0;
	}

	static function _fnCutRect(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final name = Lua.tostring(l, 2);
		final col = Lua.tostring(l, 3);
		Lua.settop(l, 0);
		final b = _reg.get(h);
		if (b != null)
			try
				b.defineRect(name, flixel.util.FlxColor.fromString(col ?? 'black'))
			catch (_)
			{
			};
		return 0;
	}

	static function _fnCutSpr(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final name = Lua.tostring(l, 2);
		final path = Lua.tostring(l, 3);
		Lua.settop(l, 0);
		final b = _reg.get(h);
		if (b != null)
			try
				b.defineSprite(name, path)
			catch (_)
			{
			};
		return 0;
	}

	static function _fnCutAdd(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final name = Lua.tostring(l, 2);
		Lua.settop(l, 0);
		final b = _reg.get(h);
		if (b != null)
			try
				b.add(name)
			catch (_)
			{
			};
		return 0;
	}

	static function _fnCutRem(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final name = Lua.tostring(l, 2);
		Lua.settop(l, 0);
		final b = _reg.get(h);
		if (b != null)
			try
				b.remove(name)
			catch (_)
			{
			};
		return 0;
	}

	static function _fnCutWait(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final dur = Lua.tonumber(l, 2);
		Lua.settop(l, 0);
		final b = _reg.get(h);
		if (b != null)
			try
				b.wait(dur)
			catch (_)
			{
			};
		return 0;
	}

	static function _fnCutAnim(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final who = Lua.tostring(l, 2);
		final anim = Lua.tostring(l, 3);
		Lua.settop(l, 0);
		final b = _reg.get(h);
		if (b != null)
			try
				b.playCharAnim(who, anim)
			catch (_)
			{
			};
		return 0;
	}

	static function _fnCutSound(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final path = Lua.tostring(l, 2);
		Lua.settop(l, 0);
		final b = _reg.get(h);
		if (b != null)
			try
				b.playSound(path)
			catch (_)
			{
			};
		return 0;
	}

	static function _fnCutCamZ(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final z = Lua.tonumber(l, 2);
		final dur = Lua.tonumber(l, 3);
		Lua.settop(l, 0);
		final b = _reg.get(h);
		if (b != null)
			try
				b.cameraZoom(z, dur)
			catch (_)
			{
			};
		return 0;
	}

	static function _fnCutCamF(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final col = Lua.tostring(l, 2);
		final dur = Lua.tonumber(l, 3);
		Lua.settop(l, 0);
		final b = _reg.get(h);
		if (b != null)
			try
				b.cameraFlash(flixel.util.FlxColor.fromString(col ?? 'white'), dur)
			catch (_)
			{
			};
		return 0;
	}

	static function _fnCutPlay(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		Lua.settop(l, 0);
		final b = _reg.get(h);
		if (b != null)
			try
				b.play()
			catch (_)
			{
			};
		return 0;
	}

	// Gameplay
	static function _fnAddScore(l:Dynamic):Int
	{
		final p = _ps();
		if (p != null)
			p.score += Std.int(Lua.tonumber(l, 1));
		Lua.settop(l, 0);
		return 0;
	}

	static function _fnSetScore(l:Dynamic):Int
	{
		final p = _ps();
		if (p != null)
			p.score = Std.int(Lua.tonumber(l, 1));
		Lua.settop(l, 0);
		return 0;
	}

	static function _fnGetScore(l:Dynamic):Int
	{
		final p = _ps();
		Lua.pushnumber(l, p != null ? p.score : 0);
		return 1;
	}

	static function _fnAddHealth(l:Dynamic):Int
	{
		final p = _ps();
		if (p != null)
			p.health = Math.min(2, p.health + Lua.tonumber(l, 1));
		Lua.settop(l, 0);
		return 0;
	}

	static function _fnSetHealth(l:Dynamic):Int
	{
		final p = _ps();
		if (p != null)
			p.health = Math.max(0, Math.min(2, Lua.tonumber(l, 1)));
		Lua.settop(l, 0);
		return 0;
	}

	static function _fnGetHealth(l:Dynamic):Int
	{
		final p = _ps();
		Lua.pushnumber(l, p != null ? p.health : 1.0);
		return 1;
	}

	static function _fnSetMisses(l:Dynamic):Int
	{
		final p = _ps();
		if (p != null)
			try
				p.misses = Std.int(Lua.tonumber(l, 1))
			catch (_)
			{
			};
		Lua.settop(l, 0);
		return 0;
	}

	static function _fnGetMisses(l:Dynamic):Int
	{
		final p = _ps();
		Lua.pushnumber(l, p != null ?try p.misses catch (_) 0:0);
		return 1;
	}

	static function _fnSetCombo(l:Dynamic):Int
	{
		final p = _ps();
		if (p != null)
			try
				p.combo = Std.int(Lua.tonumber(l, 1))
			catch (_)
			{
			};
		Lua.settop(l, 0);
		return 0;
	}

	static function _fnGetCombo(l:Dynamic):Int
	{
		final p = _ps();
		Lua.pushnumber(l, p != null ?try p.combo catch (_) 0:0);
		return 1;
	}

	static function _fnEndSong(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		final p = _ps();
		if (p != null)
			p.endSong();
		return 0;
	}

	static function _fnGameOver(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		final p = _ps();
		if (p != null)
			p.health = 0;
		return 0;
	}

	static function _fnPause(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		final p = _ps();
		if (p != null)
			try
				p.pauseSong()
			catch (_)
				flixel.FlxG.timeScale = 0;
		return 0;
	}

	static function _fnResume(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		final p = _ps();
		if (p != null)
			try
				p.resumeSong()
			catch (_)
				flixel.FlxG.timeScale = 1;
		return 0;
	}

	// Notes
	static function _fnSpawnNote(l:Dynamic):Int
	{
		final t = Lua.tonumber(l, 1);
		final d = Std.int(Lua.tonumber(l, 2));
		final len = Lua.gettop(l) > 2 ? Lua.tonumber(l, 3) : 0.0;
		Lua.settop(l, 0);
		final p = _ps();
		if (p != null)
			try
				p.spawnNote(t, d, len)
			catch (_)
			{
			};
		return 0;
	}

	static function _fnNoteDir(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		Lua.settop(l, 0);
		final n = _reg.get(h);
		Lua.pushnumber(l, n != null ?try n.noteData catch (_) 0:0);
		return 1;
	}

	static function _fnNoteTime(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		Lua.settop(l, 0);
		final n = _reg.get(h);
		Lua.pushnumber(l, n != null ?try n.strumTime catch (_) 0:0);
		return 1;
	}

	static function _fnNoteAlpha(l:Dynamic):Int
	{
		final a = Lua.tonumber(l, 1);
		Lua.settop(l, 0);
		final p = _ps();
		if (p != null)
			try
				p.noteAlphaOverride = a
			catch (_)
			{
			};
		return 0;
	}

	static function _fnNoteColor(l:Dynamic):Int
	{
		final c = Std.int(Lua.tonumber(l, 1));
		Lua.settop(l, 0);
		final p = _ps();
		if (p != null)
			try
				p.noteColorOverride = c
			catch (_)
			{
			};
		return 0;
	}

	static function _fnSkipNote(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		Lua.settop(l, 0);
		final n = _reg.get(h);
		if (n != null)
			try
				n.ignoreNote = true
			catch (_)
			{
			};
		return 0;
	}

	static function _fnNoteSkin(l:Dynamic):Int
	{
		final skin = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		final p = _ps();
		if (p != null)
			try
				p.noteSkinOverride = skin
			catch (_)
			{
			};
		return 0;
	}

	static function _fnNoteSplash(l:Dynamic):Int
	{
		final d = Std.int(Lua.tonumber(l, 1));
		Lua.settop(l, 0);
		final p = _ps();
		if (p != null)
			try
				p.spawnSplash(d)
			catch (_)
			{
			};
		return 0;
	}

	static function _fnHoldActive(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		Lua.settop(l, 0);
		final n = _reg.get(h);
		Lua.pushboolean(l, n != null ? try n.held catch (_) false : false);
		return 1;
	}

	static function _fnForNote(l:Dynamic):Int
	{
		final cbName = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		final p = _ps();
		if (p == null)
			return 0;
		final luaRef = _sCurrentLua;
		try
		{
			final noteGroup = (p.notes : flixel.group.FlxGroup.FlxTypedGroup<funkin.gameplay.notes.Note>);
			for (n in noteGroup.members)
			{
				Lua.getglobal(luaRef, cbName);
				if (Lua.type(luaRef, -1) == 6)
				{
					_pushOOP(luaRef, n);
					Lua.pcall(luaRef, 1, 0, 0);
				}
				else
					Lua.pop(luaRef, 1);
			}
		}
		catch (_)
		{
		};
		return 0;
	}

	static function _fnNoteSkinHandle(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		_pushOOP(l, funkin.gameplay.notes.NoteSkinSystem);
		return 1;
	}

	static function _fnReloadNoteSkin(l:Dynamic):Int
	{
		final skin = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		try
		{
			if (skin != null && skin != '')
				funkin.gameplay.notes.NoteSkinSystem.setSkin(skin);
			else
				funkin.gameplay.notes.NoteSkinSystem.forceReinit();
		}
		catch (_)
		{
		};
		return 0;
	}

	// ── RGB shader helpers ────────────────────────────────────────────────────
	// applyRGBShader(sprHandle, direction [, mult=1.0])
	static function _fnApplyRGB(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final dir = Std.int(Lua.tonumber(l, 2));
		final mul = Lua.gettop(l) > 2 ? Lua.tonumber(l, 3) : 1.0;
		Lua.settop(l, 0);
		final spr = _reg.get(h);
		if (spr != null)
			try
				funkin.gameplay.notes.NoteSkinSystem.applyRGBShader(spr, dir, mul)
			catch (_)
			{
			};
		return 0;
	}

	// applyRGBColor(sprHandle, hexColor [, mult=1.0])
	static function _fnApplyRGBColor(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final col = Std.int(Lua.tonumber(l, 2));
		final mul = Lua.gettop(l) > 2 ? Lua.tonumber(l, 3) : 1.0;
		Lua.settop(l, 0);
		final spr = _reg.get(h);
		if (spr != null)
			try
				funkin.gameplay.notes.NoteSkinSystem.applyRGBColor(spr, col, mul)
			catch (_)
			{
			};
		return 0;
	}

	// setRGBIntensity(sprHandle, mult)
	static function _fnSetRGBIntensity(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final mul = Lua.tonumber(l, 2);
		Lua.settop(l, 0);
		final spr = _reg.get(h);
		if (spr != null)
			try
				funkin.gameplay.notes.NoteSkinSystem.setRGBIntensity(spr, mul)
			catch (_)
			{
			};
		return 0;
	}

	// removeRGBShader(sprHandle)
	static function _fnRemoveRGB(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		Lua.settop(l, 0);
		final spr = _reg.get(h);
		if (spr != null)
			try
				funkin.gameplay.notes.NoteSkinSystem.removeRGBShader(spr)
			catch (_)
			{
			};
		return 0;
	}

	// tweenRGBToDirection(sprHandle, direction [, duration=0.25 [, ease='linear']])
	static function _fnTweenRGBDir(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final dir = Std.int(Lua.tonumber(l, 2));
		final dur = Lua.gettop(l) > 2 ? Lua.tonumber(l, 3) : 0.25;
		final eas = Lua.gettop(l) > 3 ? Lua.tostring(l, 4) : 'linear';
		Lua.settop(l, 0);
		final spr = _reg.get(h);
		if (spr != null)
			try
			{
				final tw = funkin.gameplay.notes.NoteSkinSystem.tweenRGBToDirection(spr, dir, dur, eas);
				if (tw != null)
					_pushOOP(l, tw)
				else
					Lua.pushnil(l);
			}
			catch (_)
			{
				Lua.pushnil(l);
			}
		return 1;
	}

	// tweenRGBToColor(sprHandle, hexColor [, duration=0.25 [, ease='linear']])
	static function _fnTweenRGBColor(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final col = Std.int(Lua.tonumber(l, 2));
		final dur = Lua.gettop(l) > 2 ? Lua.tonumber(l, 3) : 0.25;
		final eas = Lua.gettop(l) > 3 ? Lua.tostring(l, 4) : 'linear';
		Lua.settop(l, 0);
		final spr = _reg.get(h);
		if (spr != null)
			try
			{
				final tw = funkin.gameplay.notes.NoteSkinSystem.tweenRGBToColor(spr, col, dur, eas);
				if (tw != null)
					_pushOOP(l, tw)
				else
					Lua.pushnil(l);
			}
			catch (_)
			{
				Lua.pushnil(l);
			}
		return 1;
	}

	// tweenRGBIntensity(sprHandle, fromMult, toMult [, duration=0.2 [, ease='linear']])
	static function _fnTweenRGBIntensity(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final from = Lua.tonumber(l, 2);
		final to = Lua.tonumber(l, 3);
		final dur = Lua.gettop(l) > 3 ? Lua.tonumber(l, 4) : 0.2;
		final eas = Lua.gettop(l) > 4 ? Lua.tostring(l, 5) : 'linear';
		Lua.settop(l, 0);
		final spr = _reg.get(h);
		if (spr != null)
			try
			{
				final tw = funkin.gameplay.notes.NoteSkinSystem.tweenRGBIntensity(spr, from, to, dur, eas);
				if (tw != null)
					_pushOOP(l, tw)
				else
					Lua.pushnil(l);
			}
			catch (_)
			{
				Lua.pushnil(l);
			}
		return 1;
	}

	static function _fnRegNoteType(l:Dynamic):Int
	{
		final name = Lua.tostring(l, 1);
		final cbHit = Lua.gettop(l) > 1 ? Lua.tostring(l, 2) : null;
		Lua.settop(l, 0);
		final luaRef = _sCurrentLua;
		final onHit:Dynamic = cbHit != null ? function(note:Dynamic)
		{
			Lua.getglobal(luaRef, cbHit);
			if (Lua.type(luaRef, -1) == 6)
			{
				_pushOOP(luaRef, note);
				Lua.pcall(luaRef, 1, 0, 0);
			}
			else
				Lua.pop(luaRef, 1);
		} : null;
		try
			funkin.gameplay.notes.NoteTypeManager.register(name, {onHit: onHit})
		catch (_)
		{
		};
		return 0;
	}

	// Audio
	static function _fnPlayMusic(l:Dynamic):Int
	{
		final p = Lua.tostring(l, 1);
		final v = Lua.gettop(l) > 1 ? Lua.tonumber(l, 2) : 1.0;
		final loop = Lua.gettop(l) < 3 || Lua.toboolean(l, 3);
		Lua.settop(l, 0);
		try
			flixel.FlxG.sound.playMusic(Paths.music(p), v, loop)
		catch (_)
		{
		};
		return 0;
	}

	static function _fnStopMusic(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		try
			flixel.FlxG.sound.music.stop()
		catch (_)
		{
		};
		return 0;
	}

	static function _fnPauseMusic(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		try
			flixel.FlxG.sound.music.pause()
		catch (_)
		{
		};
		return 0;
	}

	static function _fnResumeMusic(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		try
			flixel.FlxG.sound.music.resume()
		catch (_)
		{
		};
		return 0;
	}

	static function _fnPlaySound(l:Dynamic):Int
	{
		final p = Lua.tostring(l, 1);
		final v = Lua.gettop(l) > 1 ? Lua.tonumber(l, 2) : 1.0;
		Lua.settop(l, 0);
		try
			flixel.FlxG.sound.play(Paths.sound(p), v)
		catch (_)
		{
		};
		return 0;
	}

	static function _fnMusicPos(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		Lua.pushnumber(l, try flixel.FlxG.sound.music.time catch (_) 0);
		return 1;
	}

	static function _fnSetMusicPos(l:Dynamic):Int
	{
		final t = Lua.tonumber(l, 1);
		Lua.settop(l, 0);
		try
			flixel.FlxG.sound.music.time = t
		catch (_)
		{
		};
		return 0;
	}

	static function _fnMusicPitch(l:Dynamic):Int
	{
		final p = Lua.tonumber(l, 1);
		Lua.settop(l, 0);
		try
			flixel.FlxG.sound.music.pitch = p
		catch (_)
		{
		};
		return 0;
	}

	static function _fnVocVol(l:Dynamic):Int
	{
		final v = Lua.tonumber(l, 1);
		Lua.settop(l, 0);
		final p = _ps();
		if (p != null)
			try
			{
				p.vocals.volume = v;
			}
			catch (_)
			{
			};
		return 0;
	}

	static function _fnVocP(l:Dynamic):Int
	{
		final s = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		final p = _ps();
		if (p != null)
			try
				p.loadVocals(s, 'player')
			catch (_)
			{
			};
		return 0;
	}

	static function _fnVocOp(l:Dynamic):Int
	{
		final s = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		final p = _ps();
		if (p != null)
			try
				p.loadVocals(s, 'opponent')
			catch (_)
			{
			};
		return 0;
	}

	static function _fnMuteVoc(l:Dynamic):Int
	{
		final v = Lua.toboolean(l, 1);
		Lua.settop(l, 0);
		final p = _ps();
		if (p != null)
			try
				p.vocals.volume = v ? 0 : 1
			catch (_)
			{
			};
		return 0;
	}

	// Config
	static function _fnSetConfig(l:Dynamic):Int
	{
		final k = Lua.tostring(l, 1);
		final v = _readOOP(l, 2);
		Lua.settop(l, 0);
		try
			Reflect.setField(funkin.data.GlobalConfig, k, v)
		catch (_)
		{
		};
		return 0;
	}

	static function _fnGetConfig(l:Dynamic):Int
	{
		final k = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		_pushOOP(l, try Reflect.field(funkin.data.GlobalConfig, k) catch (_) null);
		return 1;
	}

	// Input
	static function _fnKeyP(l:Dynamic):Int
	{
		final k = _key(Lua.tostring(l, 1));
		Lua.settop(l, 0);
		Lua.pushboolean(l, k != null && flixel.FlxG.keys.checkStatus(k, flixel.input.FlxInput.FlxInputState.PRESSED));
		return 1;
	}

	static function _fnKeyJP(l:Dynamic):Int
	{
		final k = _key(Lua.tostring(l, 1));
		Lua.settop(l, 0);
		Lua.pushboolean(l, k != null && flixel.FlxG.keys.checkStatus(k, flixel.input.FlxInput.FlxInputState.JUST_PRESSED));
		return 1;
	}

	static function _fnKeyJR(l:Dynamic):Int
	{
		final k = _key(Lua.tostring(l, 1));
		Lua.settop(l, 0);
		Lua.pushboolean(l, k != null && flixel.FlxG.keys.checkStatus(k, flixel.input.FlxInput.FlxInputState.JUST_RELEASED));
		return 1;
	}

	static function _fnMouseX(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		Lua.pushnumber(l, flixel.FlxG.mouse.x);
		return 1;
	}

	static function _fnMouseY(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		Lua.pushnumber(l, flixel.FlxG.mouse.y);
		return 1;
	}

	static function _fnMouseP(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		Lua.pushboolean(l, flixel.FlxG.mouse.pressed);
		return 1;
	}

	static function _fnMouseJP(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		Lua.pushboolean(l, flixel.FlxG.mouse.justPressed);
		return 1;
	}

	static function _fnMouseRP(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		Lua.pushboolean(l, flixel.FlxG.mouse.pressedRight);
		return 1;
	}

	static function _fnMouseRJP(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		Lua.pushboolean(l, flixel.FlxG.mouse.justPressedRight);
		return 1;
	}

	static function _fnPadP(l:Dynamic):Int
	{
		final b = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		try
		{
			final gb = flixel.input.gamepad.FlxGamepadInputID.fromString(b);
			Lua.pushboolean(l, flixel.FlxG.gamepads.anyPressed(gb));
		}
		catch (_)
		{
			Lua.pushboolean(l, false);
		}
		return 1;
	}

	static function _fnPadJP(l:Dynamic):Int
	{
		final b = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		try
		{
			final gb = flixel.input.gamepad.FlxGamepadInputID.fromString(b);
			Lua.pushboolean(l, flixel.FlxG.gamepads.anyJustPressed(gb));
		}
		catch (_)
		{
			Lua.pushboolean(l, false);
		}
		return 1;
	}

	// Utils
	static function _fnTrace(l:Dynamic):Int
	{
		final n = Lua.gettop(l);
		final parts = [for (i in 0...n) Lua.tostring(l, i + 1) ?? 'nil'];
		Lua.settop(l, 0);
		trace('[Lua:$_sCurrentId] ' + parts.join('\t'));
		return 0;
	}

	static function _fnBeat(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		Lua.pushnumber(l, try Math.floor(funkin.data.Conductor.songPosition / funkin.data.Conductor.crochet) catch (_) 0);
		return 1;
	}

	static function _fnStep(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		Lua.pushnumber(l, try Math.floor(funkin.data.Conductor.songPosition / funkin.data.Conductor.stepCrochet) catch (_) 0);
		return 1;
	}

	static function _fnBPM(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		Lua.pushnumber(l, try funkin.data.Conductor.bpm catch (_) 100);
		return 1;
	}

	static function _fnSongPos(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		Lua.pushnumber(l, try funkin.data.Conductor.songPosition catch (_) 0);
		return 1;
	}

	static function _fnRndInt(l:Dynamic):Int
	{
		final a = Std.int(Lua.tonumber(l, 1));
		final b = Std.int(Lua.tonumber(l, 2));
		Lua.settop(l, 0);
		Lua.pushnumber(l, a + Std.int(Math.random() * (b - a + 1)));
		return 1;
	}

	static function _fnRndFlt(l:Dynamic):Int
	{
		final a = Lua.tonumber(l, 1);
		final b = Lua.tonumber(l, 2);
		Lua.settop(l, 0);
		Lua.pushnumber(l, a + Math.random() * (b - a));
		return 1;
	}

	static function _fnRGB(l:Dynamic):Int
	{
		final r = Std.int(Lua.tonumber(l, 1));
		final g = Std.int(Lua.tonumber(l, 2));
		final b = Std.int(Lua.tonumber(l, 3));
		Lua.settop(l, 0);
		Lua.pushnumber(l, flixel.util.FlxColor.fromRGB(r, g, b));
		return 1;
	}

	static function _fnRGBA(l:Dynamic):Int
	{
		final r = Std.int(Lua.tonumber(l, 1));
		final g = Std.int(Lua.tonumber(l, 2));
		final b = Std.int(Lua.tonumber(l, 3));
		final a = Std.int(Lua.tonumber(l, 4));
		Lua.settop(l, 0);
		Lua.pushnumber(l, flixel.util.FlxColor.fromRGBFloat(r / 255, g / 255, b / 255, a / 255));
		return 1;
	}

	static function _fnHex(l:Dynamic):Int
	{
		final h = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		try
			Lua.pushnumber(l, flixel.util.FlxColor.fromString('#$h'))
		catch (_)
			Lua.pushnumber(l, 0);
		return 1;
	}

	static function _fnLerp(l:Dynamic):Int
	{
		final a = Lua.tonumber(l, 1);
		final b = Lua.tonumber(l, 2);
		final r = Lua.tonumber(l, 3);
		Lua.settop(l, 0);
		Lua.pushnumber(l, a + (b - a) * r);
		return 1;
	}

	static function _fnClamp(l:Dynamic):Int
	{
		final v = Lua.tonumber(l, 1);
		final mn = Lua.tonumber(l, 2);
		final mx = Lua.tonumber(l, 3);
		Lua.settop(l, 0);
		Lua.pushnumber(l, Math.min(mx, Math.max(mn, v)));
		return 1;
	}

	static function _fnFileEx(l:Dynamic):Int
	{
		final p = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		Lua.pushboolean(l, #if sys FileSystem.exists(p) #else false #end);
		return 1;
	}

	static function _fnFileR(l:Dynamic):Int
	{
		final p = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		try
			Lua.pushstring(l, #if sys File.getContent(p) #else '' #end)
		catch (_)
			Lua.pushnil(l);
		return 1;
	}

	static function _fnFileW(l:Dynamic):Int
	{
		final p = Lua.tostring(l, 1);
		final c = Lua.tostring(l, 2);
		Lua.settop(l, 0); #if sys try
			File.saveContent(p, c)
		catch (_)
		{
		} #end return 0;
	}

	static function _fnSongName(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		Lua.pushstring(l, try funkin.gameplay.PlayState.SONG.song catch (_) '');
		return 1;
	}

	static function _fnSongArtist(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		Lua.pushstring(l, try funkin.gameplay.PlayState.SONG.artist catch (_) '');
		return 1;
	}

	static function _fnIsStory(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		Lua.pushboolean(l, try funkin.gameplay.PlayState.isStoryMode catch (_) false);
		return 1;
	}

	static function _fnGetDiff(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		Lua.pushstring(l, try Std.string(funkin.gameplay.PlayState.storyDifficulty) catch (_) 'normal');
		return 1;
	}

	static function _fnGetAcc(l:Dynamic):Int
	{
		final p = _ps();
		Lua.settop(l, 0);
		Lua.pushnumber(l, p != null ?try p.scoreManager.accuracy catch (_) 0:0);
		return 1;
	}

	static function _fnGetSicks(l:Dynamic):Int
	{
		final p = _ps();
		Lua.settop(l, 0);
		Lua.pushnumber(l, p != null ?try p.scoreManager.sicks catch (_) 0:0);
		return 1;
	}

	static function _fnGetGoods(l:Dynamic):Int
	{
		final p = _ps();
		Lua.settop(l, 0);
		Lua.pushnumber(l, p != null ?try p.scoreManager.goods catch (_) 0:0);
		return 1;
	}

	static function _fnGetBads(l:Dynamic):Int
	{
		final p = _ps();
		Lua.settop(l, 0);
		Lua.pushnumber(l, p != null ?try p.scoreManager.bads catch (_) 0:0);
		return 1;
	}

	static function _fnGetShits(l:Dynamic):Int
	{
		final p = _ps();
		Lua.settop(l, 0);
		Lua.pushnumber(l, p != null ?try p.scoreManager.shits catch (_) 0:0);
		return 1;
	}

	static function _fnSetSicks(l:Dynamic):Int
	{
		final v = Std.int(Lua.tonumber(l, 1));
		Lua.settop(l, 0);
		final p = _ps();
		if (p != null)
			try
				p.scoreManager.sicks = v
			catch (_)
			{
			};
		return 0;
	}

	static function _fnSetScroll(l:Dynamic):Int
	{
		final v = Lua.tonumber(l, 1);
		Lua.settop(l, 0);
		final p = _ps();
		if (p != null)
			try
				p.scrollSpeed = v
			catch (_)
			{
			};
		return 0;
	}

	static function _fnGetScroll(l:Dynamic):Int
	{
		final p = _ps();
		Lua.settop(l, 0);
		Lua.pushnumber(l, p != null ?try p.scrollSpeed catch (_) 1:1);
		return 1;
	}

	// Shared / script communication
	static var _sharedData:Map<String, Dynamic> = new Map();

	static function _fnSetShared(l:Dynamic):Int
	{
		final k = Lua.tostring(l, 1);
		final v = _readOOP(l, 2);
		Lua.settop(l, 0);
		_sharedData.set(k, v);
		return 0;
	}

	static function _fnGetShared(l:Dynamic):Int
	{
		final k = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		_pushOOP(l, _sharedData.get(k));
		return 1;
	}

	static function _fnDelShared(l:Dynamic):Int
	{
		final k = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		_sharedData.remove(k);
		return 0;
	}

	static function _fnBroadcast(l:Dynamic):Int
	{
		final ev = Lua.tostring(l, 1);
		final nArg = Lua.gettop(l) - 1;
		final args = [for (i in 0...nArg) _readOOP(l, i + 2)];
		Lua.settop(l, 0);
		try
			funkin.scripting.ScriptHandler.callOnScripts(ev, args)
		catch (_)
		{
		};
		return 0;
	}

	static function _fnCallScripts(l:Dynamic):Int
	{
		return _fnBroadcast(l);
	}

	static function _fnSetScriptVar(l:Dynamic):Int
	{
		final id2 = Lua.tostring(l, 1);
		final k = Lua.tostring(l, 2);
		final v = _readOOP(l, 3);
		Lua.settop(l, 0);
		try
			funkin.scripting.ScriptHandler.setOnScripts(k, v)
		catch (_)
		{
		};
		return 0;
	}

	static function _fnGetScriptVar(l:Dynamic):Int
	{
		final id2 = Lua.tostring(l, 1);
		final k = Lua.tostring(l, 2);
		Lua.settop(l, 0);
		_pushOOP(l, try funkin.scripting.ScriptHandler.getFromScripts(k, null) catch (_) null);
		return 1;
	}

	// Modchart
	static function _fnSetMod(l:Dynamic):Int
	{
		final name = Lua.tostring(l, 1);
		final v = Lua.tonumber(l, 2);
		Lua.settop(l, 0);
		// setModifier does not exist; forward as an immediate beat-0 event for current beat
		try
		{
			final beat = Math.floor(funkin.data.Conductor.songPosition / funkin.data.Conductor.crochet);
			funkin.gameplay.modchart.ModChartManager.instance.addEventSimple(beat, 'all', -1, name, v, 0.0, 'linear');
		}
		catch (_)
		{
		};
		return 0;
	}

	// setPlayerModifier(name, value) -- solo grupo del jugador
	static function _fnSetPlayerMod(l:Dynamic):Int
	{
		final name = Lua.tostring(l, 1);
		final v = Lua.tonumber(l, 2);
		Lua.settop(l, 0);
		try {
			final beat = Math.floor(funkin.data.Conductor.songPosition / funkin.data.Conductor.crochet);
			funkin.gameplay.modchart.ModChartManager.instance.addEventSimple(beat, 'player', -1, name, v, 0.0, 'linear');
		} catch (_) {};
		return 0;
	}

	// setCpuModifier(name, value) -- solo grupo CPU/oponente
	static function _fnSetCpuMod(l:Dynamic):Int
	{
		final name = Lua.tostring(l, 1);
		final v = Lua.tonumber(l, 2);
		Lua.settop(l, 0);
		try {
			final beat = Math.floor(funkin.data.Conductor.songPosition / funkin.data.Conductor.crochet);
			funkin.gameplay.modchart.ModChartManager.instance.addEventSimple(beat, 'cpu', -1, name, v, 0.0, 'linear');
		} catch (_) {};
		return 0;
	}

	// setGroupModifier(groupId, name, value) -- grupo especifico por ID
	// Ej: setGroupModifier('bf','invert',1)  -> solo BF
	//     setGroupModifier('dad','drunk',80) -> solo el papa
	static function _fnSetGroupMod(l:Dynamic):Int
	{
		final target = Lua.tostring(l, 1);
		final name   = Lua.tostring(l, 2);
		final v      = Lua.tonumber(l, 3);
		Lua.settop(l, 0);
		try {
			final beat = Math.floor(funkin.data.Conductor.songPosition / funkin.data.Conductor.crochet);
			funkin.gameplay.modchart.ModChartManager.instance.addEventSimple(beat, target, -1, name, v, 0.0, 'linear');
		} catch (_) {};
		return 0;
	}

	static function _fnGetMod(l:Dynamic):Int
	{
		final name = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		try
		{
			final st = funkin.gameplay.modchart.ModChartManager.instance.getState('all', 0);
			Lua.pushnumber(l, st != null ? Reflect.field(st, name) ?? 0.0 : 0.0);
		}
		catch (_)
		{
			Lua.pushnumber(l, 0);
		}
		return 1;
	}

	static function _fnClearMods(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		try
			funkin.gameplay.modchart.ModChartManager.instance.clearEvents()
		catch (_)
		{
		};
		return 0;
	}

	static function _fnNoteMod(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final mod = Lua.tostring(l, 2);
		final v = Lua.tonumber(l, 3);
		Lua.settop(l, 0);
		final n = _reg.get(h);
		if (n != null)
			try
				Reflect.setField(n, 'modifier_' + mod, v)
			catch (_)
			{
			};
		return 0;
	}

	// Events
	static function _fnTriggerEv(l:Dynamic):Int
	{
		final name = Lua.tostring(l, 1);
		final v1 = Lua.gettop(l) > 1 ? Lua.tostring(l, 2) : '';
		final v2 = Lua.gettop(l) > 2 ? Lua.tostring(l, 3) : '';
		Lua.settop(l, 0);
		try
			funkin.scripting.events.EventManager.fireEvent(name, v1 ?? '', v2 ?? '')
		catch (_)
		{
		};
		return 0;
	}

	static function _fnRegisterEv(l:Dynamic):Int
	{
		final name = Lua.tostring(l, 1);
		final cb = Lua.tostring(l, 2);
		Lua.settop(l, 0);
		final luaRef = _sCurrentLua;
		try
			funkin.scripting.events.EventManager.registerCustomEvent(name, function(evts)
			{
				Lua.getglobal(luaRef, cb);
				final v1 = evts.length > 0 ? (evts[0].value1 ?? '') : '';
				final v2 = evts.length > 0 ? (evts[0].value2 ?? '') : '';
				if (Lua.type(luaRef, -1) == 6)
				{
					Lua.pushstring(luaRef, v1);
					Lua.pushstring(luaRef, v2);
					Lua.pcall(luaRef, 2, 0, 0);
				}
				else
					Lua.pop(luaRef, 1);
				return false;
			})
		catch (_)
		{
		};
		return 0;
	}

	static function _fnGetEventDef(l:Dynamic):Int
	{
		final name = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		_pushOOP(l, try funkin.scripting.events.EventRegistry.get(name) catch (_) null);
		return 1;
	}

	static function _fnListEvents(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		_pushOOP(l, try funkin.scripting.events.EventRegistry.eventList catch (_) null);
		return 1;
	}

	static function _fnRegisterEventDef(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		return 0;
	}

	// Shaders
	static function _fnAddShader(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final key = Lua.tostring(l, 2);
		Lua.settop(l, 0);
		final obj = _reg.get(h);
		if (obj == null)
			return 0;
		try
			funkin.graphics.shaders.ShaderManager.applyToNote(obj, 0)
		catch (_)
		{
		};
		return 0;
	}

	static function _fnRemoveShader(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final key = Lua.tostring(l, 2);
		Lua.settop(l, 0);
		final obj = _reg.get(h);
		if (obj == null)
			return 0;
		try
			funkin.graphics.shaders.ShaderManager.removeFromNote(obj)
		catch (_)
		{
		};
		return 0;
	}

	static function _fnShaderProp(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final key = Lua.tostring(l, 2);
		final prop = Lua.tostring(l, 3);
		final v = _readOOP(l, 4);
		Lua.settop(l, 0);
		try
		{
			final sm = funkin.graphics.shaders.ShaderManager;
			final shader:Dynamic = sm.shaders.exists(key) ? sm.shaders.get(key) : (sm.scriptShaders.exists(key) ? sm.scriptShaders.get(key) : null);
			if (shader != null)
				Reflect.setField(shader, prop, v);
		}
		catch (_)
		{
		};
		return 0;
	}

	// UI / Dialogs
	static function _fnNotif(l:Dynamic):Int
	{
		final msg = Lua.tostring(l, 1);
		final dur = Lua.gettop(l) > 1 ? Lua.tonumber(l, 2) : 2.0;
		Lua.settop(l, 0);
		try
		{
			final d = new funkin.scripting.ScriptDialog();
			d.addLine('', msg, dur);
			d.close();
		}
		catch (_)
		{
		};
		return 0;
	}

	static function _fnNewDialog(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		final d = try new funkin.scripting.ScriptDialog() catch (_) null;
		if (d != null)
			_pushOOP(l, d)
		else
			Lua.pushnil(l);
		return 1;
	}

	static function _fnDialogAddLine(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		final spk = Lua.tostring(l, 2);
		final txt = Lua.tostring(l, 3);
		final col = Lua.gettop(l) > 3 ? Std.int(Lua.tonumber(l, 4)) : 0;
		Lua.settop(l, 0);
		final d = _reg.get(h);
		if (d != null)
			try
				d.addLine(spk, txt, col)
			catch (_)
			{
			};
		return 0;
	}

	static function _fnDialogPortrait(l:Dynamic):Int
	{
		final d = _reg.get(_handle(l, 1));
		if (d != null)
			try
				d.setPortrait(Lua.tostring(l, 2), Lua.tostring(l, 3))
			catch (_)
			{
			};
		Lua.settop(l, 0);
		return 0;
	}

	static function _fnDialogTypeSpeed(l:Dynamic):Int
	{
		final d = _reg.get(_handle(l, 1));
		if (d != null)
			try
				d.typeSpeed = Lua.tonumber(l, 2)
			catch (_)
			{
			};
		Lua.settop(l, 0);
		return 0;
	}

	static function _fnDialogAutoAdv(l:Dynamic):Int
	{
		final d = _reg.get(_handle(l, 1));
		if (d != null)
			try
				d.autoAdvance = Lua.tonumber(l, 2)
			catch (_)
			{
			};
		Lua.settop(l, 0);
		return 0;
	}

	static function _fnDialogSpColor(l:Dynamic):Int
	{
		final d = _reg.get(_handle(l, 1));
		if (d != null)
			try
				d.speakerColor = Std.int(Lua.tonumber(l, 2))
			catch (_)
			{
			};
		Lua.settop(l, 0);
		return 0;
	}

	static function _fnDialogBgColor(l:Dynamic):Int
	{
		final d = _reg.get(_handle(l, 1));
		if (d != null)
			try
				d.bgColor = Std.int(Lua.tonumber(l, 2))
			catch (_)
			{
			};
		Lua.settop(l, 0);
		return 0;
	}

	static function _fnDialogAllowSkip(l:Dynamic):Int
	{
		final d = _reg.get(_handle(l, 1));
		if (d != null)
			try
				d.allowSkip = Lua.toboolean(l, 2)
			catch (_)
			{
			};
		Lua.settop(l, 0);
		return 0;
	}

	static function _fnDialogOnFinish(l:Dynamic):Int
	{
		final d = _reg.get(_handle(l, 1));
		final cb = Lua.tostring(l, 2);
		Lua.settop(l, 0);
		final luaRef = _sCurrentLua;
		if (d != null)
			try
				d.onFinish = function()
				{
					Lua.getglobal(luaRef, cb);
					if (Lua.type(luaRef, -1) == 6)
						Lua.pcall(luaRef, 0, 0, 0)
					else
						Lua.pop(luaRef, 1);
				}
			catch (_)
			{
			};
		return 0;
	}

	static function _fnDialogOnLine(l:Dynamic):Int
	{
		// ScriptDialog has no onLine callback — no-op (lines advance automatically)
		Lua.settop(l, 0);
		return 0;
	}

	static function _fnDialogShow(l:Dynamic):Int
	{
		final d = _reg.get(_handle(l, 1));
		Lua.settop(l, 0);
		if (d != null)
			try
				d.show()
			catch (_)
			{
			};
		return 0;
	}

	static function _fnDialogClose(l:Dynamic):Int
	{
		final d = _reg.get(_handle(l, 1));
		Lua.settop(l, 0);
		if (d != null)
			try
				d.close()
			catch (_)
			{
			};
		return 0;
	}

	static function _fnDialogSkipAll(l:Dynamic):Int
	{
		final d = _reg.get(_handle(l, 1));
		Lua.settop(l, 0);
		if (d != null)
			try
				d.skipAll()
			catch (_)
			{
			};
		return 0;
	}

	static function _fnDialogQuick(l:Dynamic):Int
	{
		final spk = Lua.tostring(l, 1);
		final txt = Lua.tostring(l, 2);
		final cb = Lua.gettop(l) > 2 ? Lua.tostring(l, 3) : null;
		Lua.settop(l, 0);
		try
		{
			final luaRef = _sCurrentLua;
			final d = funkin.scripting.ScriptDialog.quick(spk ?? '', txt ?? '', 0.0, cb != null ? function()
			{
				Lua.getglobal(luaRef, cb);
				if (Lua.type(luaRef, -1) == 6)
					Lua.pcall(luaRef, 0, 0, 0)
				else
					Lua.pop(luaRef, 1);
			} : null);
			_pushOOP(l, d);
		}
		catch (_)
		{
			Lua.pushnil(l);
		};
		return 1;
	}

	static function _fnDialogSequence(l:Dynamic):Int
	{
		final h = _handle(l, 1);
		Lua.settop(l, 0);
		final d = _reg.get(h);
		if (d != null)
			try
				d.show()
			catch (_)
			{
			};
		return 0;
	}

	static function _fnCloseAllDialogs(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		return 0; /* no global closeAll in this engine */}

	// Persistent data
	static function _fnDataSave(l:Dynamic):Int
	{
		final k = Lua.tostring(l, 1);
		final v = _readOOP(l, 2);
		Lua.settop(l, 0);
		try
		{
			flixel.FlxG.save.data.ruleScriptData ??= {};
			Reflect.setField(flixel.FlxG.save.data.ruleScriptData, k, v);
			flixel.FlxG.save.flush();
		}
		catch (_)
		{
		};
		return 0;
	}

	static function _fnDataLoad(l:Dynamic):Int
	{
		final k = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		try
			_pushOOP(l, Reflect.field(flixel.FlxG.save.data.ruleScriptData, k))
		catch (_)
			Lua.pushnil(l);
		return 1;
	}

	static function _fnDataExists(l:Dynamic):Int
	{
		final k = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		try
			Lua.pushboolean(l, Reflect.hasField(flixel.FlxG.save.data.ruleScriptData, k))
		catch (_)
			Lua.pushboolean(l, false);
		return 1;
	}

	static function _fnDataDelete(l:Dynamic):Int
	{
		final k = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		try
		{
			Reflect.deleteField(flixel.FlxG.save.data.ruleScriptData, k);
			flixel.FlxG.save.flush();
		}
		catch (_)
		{
		};
		return 0;
	}

	// JSON
	static function _fnJsonEnc(l:Dynamic):Int
	{
		final v = _readOOP(l, 1);
		Lua.settop(l, 0);
		try
			Lua.pushstring(l, haxe.Json.stringify(v))
		catch (_)
			Lua.pushnil(l);
		return 1;
	}

	static function _fnJsonDec(l:Dynamic):Int
	{
		final s = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		try
			_pushOOP(l, haxe.Json.parse(s))
		catch (_)
			Lua.pushnil(l);
		return 1;
	}

	// String / Table
	static function _fnStrSplit(l:Dynamic):Int
	{
		final s = Lua.tostring(l, 1);
		final sep = Lua.tostring(l, 2);
		Lua.settop(l, 0);
		final parts = s.split(sep);
		Lua.newtable(l);
		for (i in 0...parts.length)
		{
			Lua.pushnumber(l, i + 1);
			Lua.pushstring(l, parts[i]);
			Lua.settable(l, -3);
		}
		return 1;
	}

	static function _fnStrContains(l:Dynamic):Int
	{
		final s = Lua.tostring(l, 1);
		final sub = Lua.tostring(l, 2);
		Lua.settop(l, 0);
		Lua.pushboolean(l, s.indexOf(sub) >= 0);
		return 1;
	}

	static function _fnStrTrim(l:Dynamic):Int
	{
		final s = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		Lua.pushstring(l, StringTools.trim(s));
		return 1;
	}

	static function _fnStrReplace(l:Dynamic):Int
	{
		final s = Lua.tostring(l, 1);
		final f = Lua.tostring(l, 2);
		final r = Lua.tostring(l, 3);
		Lua.settop(l, 0);
		Lua.pushstring(l, StringTools.replace(s, f, r));
		return 1;
	}

	static function _fnTableLen(l:Dynamic):Int
	{
		if (Lua.type(l, 1) == 5)
		{
			var n = 0;
			Lua.pushnil(l);
			while (Lua.next(l, -2) != 0)
			{
				n++;
				Lua.pop(l, 1);
			}
			Lua.settop(l, 0);
			Lua.pushnumber(l, n);
		}
		else
		{
			Lua.settop(l, 0);
			Lua.pushnumber(l, 0);
		}
		return 1;
	}

	// Subtitles
	static function _fnSubShow(l:Dynamic):Int
	{
		final txt = Lua.tostring(l, 1);
		final dur = Lua.tonumber(l, 2);
		var opts:Dynamic = null;
		if (Lua.gettop(l) > 2 && Lua.type(l, 3) == 5)
			opts = _luaTableToOpts(l, 3);
		Lua.settop(l, 0);
		try
			funkin.ui.SubtitleManager.instance.show(txt, dur, opts)
		catch (_)
		{
		};
		return 0;
	}

	static function _fnSubHide(l:Dynamic):Int
	{
		final v = Lua.gettop(l) > 0 && Lua.toboolean(l, 1);
		Lua.settop(l, 0);
		try
			funkin.ui.SubtitleManager.instance.hide(v)
		catch (_)
		{
		};
		return 0;
	}

	static function _fnSubClear(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		try
			funkin.ui.SubtitleManager.instance.clear()
		catch (_)
		{
		};
		return 0;
	}

	static function _fnSubQueue(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		return 0;
	}

	static function _fnSubStyle(l:Dynamic):Int
	{
		var opts:Dynamic = null;
		if (Lua.gettop(l) > 0 && Lua.type(l, 1) == 5)
			opts = _luaTableToOpts(l, 1);
		Lua.settop(l, 0);
		try
			funkin.ui.SubtitleManager.instance.setStyle(opts)
		catch (_)
		{
		};
		return 0;
	}

	static function _fnSubReset(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		try
			funkin.ui.SubtitleManager.instance.resetStyle()
		catch (_)
		{
		};
		return 0;
	}

	// Transitions
	static function _fnFadeIn(l:Dynamic):Int
	{
		final dur = Lua.gettop(l) > 0 ? Lua.tonumber(l, 1) : 1.0;
		Lua.settop(l, 0);
		try
			flixel.FlxG.camera.fade(flixel.util.FlxColor.BLACK, dur, true)
		catch (_)
		{
		};
		return 0;
	}

	static function _fnFadeOut(l:Dynamic):Int
	{
		final dur = Lua.gettop(l) > 0 ? Lua.tonumber(l, 1) : 1.0;
		Lua.settop(l, 0);
		try
			flixel.FlxG.camera.fade(flixel.util.FlxColor.BLACK, dur, false)
		catch (_)
		{
		};
		return 0;
	}

	// State handles — direct OOP access to ALL engine states
	static function _fnGetMenuHandle(l:Dynamic):Int
	{
		final name = Lua.tostring(l, 1);
		Lua.settop(l, 0);
		_pushOOP(l, flixel.FlxG.state);
		return 1;
	}

	static function _fnGetPauseHandle(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		_pushOOP(l, try flixel.FlxG.state.subState catch (_) null);
		return 1;
	}

	static function _fnGetGameOverHandle(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		_pushOOP(l, flixel.FlxG.state);
		return 1;
	}

	static function _fnGetOptionsHandle(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		_pushOOP(l, flixel.FlxG.state);
		return 1;
	}

	static function _fnGetResultsHandle(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		_pushOOP(l, flixel.FlxG.state);
		return 1;
	}

	static function _fnGetFreeplayHandle(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		_pushOOP(l, flixel.FlxG.state);
		return 1;
	}

	static function _fnGetMainMenuHandle(l:Dynamic):Int
	{
		Lua.settop(l, 0);
		_pushOOP(l, flixel.FlxG.state);
		return 1;
	}
	#end

	// ── Error helper ──────────────────────────────────────────────────────────

	function _error(msg:String):Void
	{
		errored = true;
		active = false;
		lastError = msg;
		trace('[RuleScript] ❌ $msg');
	}
}
