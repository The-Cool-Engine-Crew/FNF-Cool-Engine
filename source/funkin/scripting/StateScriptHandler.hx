package funkin.scripting;

import flixel.FlxG;
import flixel.FlxState;
import haxe.Exception;
import sys.FileSystem;
import sys.io.File;

#if HSCRIPT_ALLOWED
import funkin.scripting.interp.FunkinInterp;
#end

using StringTools;

/**
 * StateScriptHandler v2 — sistema de scripts para FlxStates y menus.
 *
 * Novedades respecto a v1:
 *   ┌─────────────────────────────────────────────────────────────────────┐
 *   │ ELEMENTOS                                                           │
 *   │  exposeElement(name, obj)  → expone cualquier objeto al script      │
 *   │  getElement(name)          → lee desde fuera                        │
 *   │  exposeAll(map)            → bulk                                   │
 *   ├─────────────────────────────────────────────────────────────────────┤
 *   │ HOOKS CUSTOM                                                        │
 *   │  registerHook(name, fn)    → engancha lógica Haxe nativa           │
 *   │  callHook(name, args)      → llama hook + scripts                  │
 *   │  fireRaw(name, args)       → solo scripts, sin hooks Haxe          │
 *   ├─────────────────────────────────────────────────────────────────────┤
 *   │ DATOS COMPARTIDOS entre scripts del mismo state                    │
 *   │  setShared(key, value)                                              │
 *   │  getShared(key)                                                     │
 *   ├─────────────────────────────────────────────────────────────────────┤
 *   │ BROADCAST (entre TODOS los scripts del engine)                     │
 *   │  broadcast(event, args)    → llama a todos (state + gameplay)      │
 *   ├─────────────────────────────────────────────────────────────────────┤
 *   │ OTROS                                                               │
 *   │  hotReloadAll()            → recarga todos los scripts del state   │
 *   │  getByTag(tag)             → obtiene scripts por tag               │
 *   │  callOnBool(fn, args)      → versión cancelable                    │
 *   └─────────────────────────────────────────────────────────────────────┘
 *
 * ─── Uso básico ──────────────────────────────────────────────────────────────
 *   StateScriptHandler.init();
 *   StateScriptHandler.loadStateScripts('MainMenuState', this);
 *   StateScriptHandler.exposeElement('menuItems', menuItemGroup);
 *   var cancelled = StateScriptHandler.callOnScripts('onBack', []);
 *   StateScriptHandler.clearStateScripts();
 *
 * ─── Estructura de carpetas ──────────────────────────────────────────────────
 *   assets/states/{statename}/       → scripts .hx / .hscript
 *   mods/{mod}/states/{statename}/   → sobrescribe / complementa
 */
class StateScriptHandler
{
	public static var scripts   : Map<String, HScriptInstance> = [];
	public static var overrides : Map<String, FunctionOverride> = [];

	#if (LUA_ALLOWED && linc_luajit)
	/** RuleScript (Lua) scripts for this state. */
	public static var luaScripts : Array<RuleScriptInstance> = [];
	#end

	/** Datos compartidos entre scripts del mismo state. */
	public static var sharedData : Map<String, Dynamic> = [];

	/** Hooks Haxe nativos registrados por el state. */
	static var _hooks    : Map<String, Array<Dynamic->Void>> = [];

	static var _sortedCache : Array<HScriptInstance> = [];
	static var _cacheDirty  : Bool = true;

	// ─── Init ─────────────────────────────────────────────────────────────────

	public static function init():Void
	{
		sharedData.clear();
		_hooks.clear();
		trace('[StateScriptHandler] Done.');
	}

	// ─── Carga ────────────────────────────────────────────────────────────────

	public static function loadStateScripts(stateName:String, state:FlxState,
		?extraVars:Map<String, Dynamic>):Array<HScriptInstance>
	{
		clearStateScripts();

		var loaded:Array<HScriptInstance> = [];

		#if sys
		if (mods.ModManager.isActive())
		{
			final modRoot = mods.ModManager.modRoot();
			final sn = stateName.toLowerCase();
			for (folder in ['$modRoot/states/$sn', '$modRoot/assets/states/$sn'])
				for (s in _loadFolder(folder, state, extraVars))
					loaded.push(s);
		}
		#end

		for (s in _loadFolder('assets/states/${stateName.toLowerCase()}', state, extraVars))
			loaded.push(s);

		trace('[StateScriptHandler] ${loaded.length} scripts for $stateName.');
		return loaded;
	}

	public static function loadScript(scriptPath:String, state:FlxState,
		priority:Int = 0, ?extraVars:Map<String, Dynamic>):HScriptInstance
	{
		#if HSCRIPT_ALLOWED
		if (!FileSystem.exists(scriptPath))
		{
			trace('[StateScriptHandler] not found: $scriptPath');
			return null;
		}

		final name    = ScriptHandler.extractName(scriptPath);
		final content = File.getContent(scriptPath);
		final script  = new HScriptInstance(name, scriptPath, priority);

		// Asignar callback de error global
		script.onError = (sn, ctx, err) ->
			trace('[STATE SCRIPT ERROR] $sn::$ctx → ${Std.string(err)}');

		try
		{
			// FIX: crear el interp y exponer ScriptAPI ANTES de parsear,
			// para que processImports() pueda detectar proxies ya registrados
			// (FlxColor, FlxEase, etc.) y no sobreescribirlos con la clase cruda.
			// Antes el orden era: parse → create interp → expose → execute,
			// lo que impedía que processImports() funcionara correctamente.
			script.interp = new FunkinInterp();

			ScriptAPI.expose(script.interp);
			_exposeStateAPI(script.interp, state, script);

			// Variables extra opcionales
			if (extraVars != null)
				script.setAll(extraVars);

			// FIX: procesar imports ANTES de parsear, igual que ScriptHandler._createScript().
			// Sin este paso, cualquier línea `import a.b.C;` en el script hacía que
			// el parser de hscript lanzara un error (no soporta import), que antes
			// se perdía porque el catch solo atrapaba haxe.Exception.
			final processedContent = ScriptHandler.processImports(content, script.interp);
			@:privateAccess script._source = processedContent;
			script.program = ScriptHandler.parser.parseString(processedContent, scriptPath);

			script.interp.execute(script.program);
			script.call('onCreate');

			scripts.set(name, script);
			_cacheDirty = true;

			trace('[StateScriptHandler] Loaded: $name (prio $priority)');
			return script;
		}
		// FIX: capturar Dynamic en vez de haxe.Exception.
		// Los errores de hscript en versiones anteriores a 2.5 son Dynamic,
		// no subclases de haxe.Exception. Con catch (e:Exception) escapaban
		// el catch sin loguearse, haciendo invisible la causa del fallo.
		catch (e:Dynamic)
		{
			trace('[StateScriptHandler] Error "$name": ${Std.string(e)}');
			return null;
		}
		#else
		return null;
		#end
	}

	// FIX: añadir recursión a subdirectorios, igual que ScriptHandler._loadFolder().
	// Sin este fix, scripts en subcarpetas de assets/states/{state}/ se ignoraban.
	static function _loadFolder(folderPath:String, state:FlxState,
		?extraVars:Map<String, Dynamic>):Array<HScriptInstance>
	{
		final loaded:Array<HScriptInstance> = [];

		if (!FileSystem.exists(folderPath) || !FileSystem.isDirectory(folderPath))
			return loaded;

		for (file in FileSystem.readDirectory(folderPath))
		{
			final fullPath = '$folderPath/$file';
			if (FileSystem.isDirectory(fullPath))
			{
				for (s in _loadFolder(fullPath, state, extraVars))
					loaded.push(s);
				continue;
			}
			#if (LUA_ALLOWED && linc_luajit)
			if (file.endsWith('.lua'))
			{
				loadLuaScript(fullPath, state, extraVars);
				continue;
			}
			#end
			if (!file.endsWith('.hx') && !file.endsWith('.hscript')) continue;
			final s = loadScript(fullPath, state, 0, extraVars);
			if (s != null) loaded.push(s);
		}

		return loaded;
	}

	// ─── Elementos expuestos ──────────────────────────────────────────────────

	/**
	 * Expone un elemento del state a TODOS los scripts activos.
	 *
	 *   StateScriptHandler.exposeElement('rankSprite', rankSprite);
	 *
	 * En el script:
	 *   rankSprite.alpha = 0.5;
	 */
	public static function exposeElement(name:String, value:Dynamic):Void
		setOnScripts(name, value);

	/** Expone varios elementos de una vez. */
	public static function exposeAll(map:Map<String, Dynamic>):Void
	{
		for (k => v in map)
			setOnScripts(k, v);
	}

	// ─── Hooks nativos ────────────────────────────────────────────────────────

	/**
	 * Registra un hook Haxe para `hookName`.
	 * Cuando `callHook(hookName, args)` se llame, primero ejecuta el callback
	 * nativo y luego propaga a los scripts.
	 *
	 *   StateScriptHandler.registerHook('onExit', function(args) {
	 *       // lógica Haxe nativa antes de que los scripts lo vean
	 *   });
	 */
	public static function registerHook(hookName:String, callback:Dynamic->Void):Void
	{
		if (!_hooks.exists(hookName))
			_hooks.set(hookName, []);
		_hooks.get(hookName).push(callback);
		trace('[StateScriptHandler] Hook "$hookName" registred.');
	}

	/** Elimina todos los hooks nativos para `hookName`. */
	public static function removeHook(hookName:String):Void
	{
		_hooks.remove(hookName);
	}

	/**
	 * Llama hooks nativos + scripts.
	 * @return true si algún script canceló el evento.
	 */
	public static function callHook(hookName:String, args:Array<Dynamic> = null):Bool
	{
		if (args == null) args = [];

		// 1) Hooks Haxe nativos
		final hooks = _hooks.get(hookName);
		if (hooks != null)
			for (h in hooks)
				try { h(args); } catch (e:Dynamic) { trace('[Hook Error] $hookName: $e'); }

		// 2) Scripts
		return callOnScripts(hookName, args);
	}

	/**
	 * Llama solo en scripts (sin hooks nativos), y NO cancela.
	 * Para eventos de "notificación pura".
	 */
	public static function fireRaw(hookName:String, args:Array<Dynamic> = null):Void
	{
		if (args == null) args = [];
		for (script in getSorted())
			script.call(hookName, args);
	}

	// ─── Datos compartidos ────────────────────────────────────────────────────

	public static function setShared(key:String, value:Dynamic):Void
		sharedData.set(key, value);

	public static function getShared(key:String, ?defaultVal:Dynamic):Dynamic
	{
		if (sharedData.exists(key)) return sharedData.get(key);
		return defaultVal;
	}

	public static function deleteShared(key:String):Void
		sharedData.remove(key);

	// ─── Broadcast global ─────────────────────────────────────────────────────

	/**
	 * Lanza un evento a TODOS los sistemas de scripts (state + gameplay).
	 * Útil para comunicación inter-sistema (ej. un menú le dice al gameplay algo).
	 */
	public static function broadcast(eventName:String, args:Array<Dynamic> = null):Void
	{
		if (args == null) args = [];
		callOnScripts(eventName, args);
		ScriptHandler.callOnScripts(eventName, args);
	}

	// ─── Hot-Reload ───────────────────────────────────────────────────────────

	/** Recarga todos los scripts del state sin perder sus variables. */
	public static function hotReloadAll():Void
	{
		for (s in scripts)
			s.hotReload();
	
		#if (LUA_ALLOWED && linc_luajit)
		for (lua in luaScripts)
			lua.hotReload();
		#end
	}

	/** Recarga un script concreto por nombre. */
	public static function hotReload(scriptName:String):Bool
	{
		final s = scripts.get(scriptName);
		return s != null && s.hotReload();
	}

	/**
	 * Re-sincroniza TODOS los campos del state hacia los scripts activos.
	 * Útil cuando el state crea objetos DESPUÉS de cargar los scripts
	 * (ej: TitleState crea logoBl en startIntro(), no en create()).
	 * Llamar justo antes de 'postCreate' en esos casos.
	 *
	 * IMPORTANTE: a diferencia de _reflectStateFields (que respeta variables ya
	 * existentes para no sobreescribir el API del engine), esta función SÍ
	 * actualiza todos los campos del state — excepto las variables fijas del API.
	 */
	public static function refreshStateFields(state:FlxState):Void
	{
		#if HSCRIPT_ALLOWED
		for (script in scripts)
			if (script.interp != null)
				_reflectStateFields(script.interp, state, true); // true = modo refresh
		#end
		#if (LUA_ALLOWED && linc_luajit)
		for (lua in luaScripts)
			if (lua.active)
				_reflectLuaStateFields(lua, state, true); // true = modo refresh
		#end
	}

	// ─── Llamadas ─────────────────────────────────────────────────────────────

	/**
	 * Llama `funcName` en orden de prioridad.
	 * Si algún script devuelve `true` → cancela (devuelve true).
	 */
	public static function callOnScripts(funcName:String, args:Array<Dynamic> = null):Bool
	{
		if (args == null) args = [];

		final ovr = overrides.get(funcName);
		if (ovr != null && ovr.enabled)
		{
			ovr.call(args);
			// Lua scripts still receive the call even when overridden
			#if (LUA_ALLOWED && linc_luajit)
			for (lua in luaScripts)
				if (lua.active) lua.call(funcName, args);
			#end
			return true;
		}

		for (script in getSorted())
			if (script.callBool(funcName, args))
			{
				trace('[StateScriptHandler] "$funcName" canceled por ${script.name}');
				#if (LUA_ALLOWED && linc_luajit)
				for (lua in luaScripts)
					if (lua.active) lua.call(funcName, args);
				#end
				return true;
			}

		#if (LUA_ALLOWED && linc_luajit)
		for (lua in luaScripts)
			if (lua.active) lua.call(funcName, args);
		#end
		return false;
	}

	/** Devuelve el primer resultado no-null. */
	public static function callOnScriptsReturn(funcName:String, args:Array<Dynamic> = null,
		defaultValue:Dynamic = null):Dynamic
	{
		if (args == null) args = [];

		final ovr = overrides.get(funcName);
		if (ovr != null && ovr.enabled) return ovr.call(args);

		for (script in getSorted())
		{
			final r = script.call(funcName, args);
			if (r != null) return r;
		}

		return defaultValue;
	}

	/** Llama en todos SIN cancelación (siempre continúa). */
	public static function callOnAll(funcName:String, args:Array<Dynamic> = null):Void
	{
		if (args == null) args = [];
		for (s in getSorted()) s.call(funcName, args);
	}

	// ─── Variables ────────────────────────────────────────────────────────────

	public static function setOnScripts(varName:String, value:Dynamic):Void
	{
		for (s in scripts) s.set(varName, value);
		#if (LUA_ALLOWED && linc_luajit)
		for (lua in luaScripts)
			if (lua.active) lua.set(varName, value);
		#end
	}

	public static function getFromScripts(varName:String):Dynamic
	{
		for (s in getSorted())
			if (s.exists(varName)) return s.get(varName);
		return null;
	}

	// ─── Por tag ──────────────────────────────────────────────────────────────

	/** Obtiene un script por su nombre. */
	public static function getByName(name:String):HScriptInstance
		return scripts.get(name);

	/** Obtiene todos los scripts con un tag dado. */
	public static function getByTag(tag:String):Array<HScriptInstance>
		return [for (s in scripts) if (s.tag == tag) s];

	// ─── Overrides ────────────────────────────────────────────────────────────

	public static function registerOverride(funcName:String, script:HScriptInstance, func:Dynamic):Void
	{
		overrides.set(funcName, new FunctionOverride(funcName, script, func));
		trace('[StateScriptHandler] Override "$funcName" by ${script.name}');
	}

	public static function unregisterOverride(funcName:String):Void
		overrides.remove(funcName);

	public static function toggleOverride(funcName:String, enabled:Bool):Void
	{
		final ovr = overrides.get(funcName);
		if (ovr != null) ovr.enabled = enabled;
	}

	public static function hasOverride(funcName:String):Bool
	{
		final ovr = overrides.get(funcName);
		return ovr != null && ovr.enabled;
	}

	// ─── Colecciones ──────────────────────────────────────────────────────────

	public static function collectArrays(funcName:String):Array<Dynamic>
	{
		final all:Array<Dynamic> = [];
		for (s in scripts)
		{
			final r = s.call(funcName);
			if (r != null && Std.isOfType(r, Array))
				for (item in (cast r:Array<Dynamic>)) all.push(item);
		}
		return all;
	}

	public static function collectUniqueStrings(funcName:String):Array<String>
	{
		final all:Array<String> = [];
		for (s in scripts)
		{
			final r = s.call(funcName);
			if (r == null || !Std.isOfType(r, Array)) continue;
			for (item in (cast r:Array<String>))
				if (!all.contains(item)) all.push(item);
		}
		return all;
	}

	// ─── Compatibilidad OptionsMenuState ─────────────────────────────────────

	public static function getCustomOptions():Array<Dynamic>     return collectArrays('getCustomOptions');
	public static function getCustomCategories():Array<String>   return collectUniqueStrings('getCustomCategories');

	// ─── Limpiar ──────────────────────────────────────────────────────────────

	public static function clearStateScripts():Void
	{
		for (s in scripts) s.destroy();
		scripts.clear();
		overrides.clear();
		sharedData.clear();
		_hooks.clear();
		_sortedCache = [];
		_cacheDirty  = false;
		#if (LUA_ALLOWED && linc_luajit)
		for (lua in luaScripts)
		{
			try lua.call('onDestroy') catch(_) {};
			try lua.destroy()        catch(_) {};
		}
		luaScripts = [];
		#end
	}

	// ─── Lua scripts for states ───────────────────────────────────────────────

	/**
	 * Loads a .lua file as a RuleScriptInstance for a state/menu.
	 * Supports the same hooks and full top-level API as HScript state scripts.
	 *
	 * Hooks:  onCreate, postCreate, onUpdate, onUpdatePost,
	 *         onBeatHit, onStepHit, onDestroy, onKeyJustPressed
	 * API:    add, remove, insert, switchState, timer, interval,
	 *         shake, flash, fade, zoomCamera, center, playSound, …
	 *         Plus the full RuleScript OOP bridge (import, FlxTween.tween, etc.)
	 */
	#if (LUA_ALLOWED && linc_luajit)
	public static function loadLuaScript(scriptPath:String, state:Dynamic,
		?extraVars:Map<String, Dynamic>):Null<RuleScriptInstance>
	{
		if (!FileSystem.exists(scriptPath)) return null;

		final name   = ScriptHandler.extractName(scriptPath);
		final script = new RuleScriptInstance(name, scriptPath);

		// Inject state-bound top-level API
		_exposeLuaStateAPI(script, state);

		// Extra caller-provided vars
		if (extraVars != null)
			for (k => v in extraVars) script.set(k, v);

		script.loadFile(scriptPath);

		if (!script.active)
		{
			trace('[StateScriptHandler] RuleScript error in: $scriptPath');
			script.destroy();
			return null;
		}

		luaScripts.push(script);
		script.call('onCreate');
		script.call('postCreate');
		trace('[StateScriptHandler] RuleScript loaded: $name');
		return script;
	}

	/**
	 * Exposes the standard state API to a RuleScript (Lua) script.
	 * State-bound functions (add, remove, insert, switchState, timer…) are
	 * injected as top-level globals — identical to _exposeStateAPI for HScript.
	 * Everything else (FlxTween, FlxG, FlxSprite…) is already accessible via
	 * the RuleScript OOP bridge, so no duplication needed.
	 */
	static function _exposeLuaStateAPI(script:RuleScriptInstance, state:Dynamic):Void
	{
		script.set('FlxG',  flixel.FlxG);
		script.set('Math',  Math);
		script.set('Std',   Std);
		script.set('self',  state);

		// ── AUTO-REFLECT: exponer TODOS los campos públicos del state ─────────
		// Igual que _reflectStateFields para HScript — los scripts Lua pueden
		// acceder a curSelected, menuItems, logoBl, etc. sin getField().
		_reflectLuaStateFields(script, state);

		// ── Leer/escribir campos del state por nombre ─────────────────────────
		// Para primitivos (Bool/Int/Float/String) que no son referencias.
		script.set('getField', function(name:String):Dynamic {
			try   { return Reflect.getProperty(state, name); }
			catch (e:Dynamic) { trace('[LuaStateScript] getField("$name") failed: $e'); return null; }
		});
		script.set('setField', function(name:String, value:Dynamic):Void {
			try   { Reflect.setProperty(state, name, value); }
			catch (e:Dynamic) { trace('[LuaStateScript] setField("$name") failed: $e'); }
		});

		// ── Llamar métodos del state por nombre ───────────────────────────────
		script.set('callMethod', function(name:String, ?args:Array<Dynamic>):Dynamic {
			try {
				final fn = Reflect.getProperty(state, name);
				if (fn != null && Reflect.isFunction(fn))
					return Reflect.callMethod(state, fn, args ?? []);
			} catch (e:Dynamic) { trace('[LuaStateScript] callMethod("$name") failed: $e'); }
			return null;
		});

		// ── Re-sincronizar campos del state hacia el script ───────────────────
		// Llamar desde Lua cuando el state crea objetos después del onCreate:
		//   refreshFields()
		script.set('refreshFields', function():Void {
			_reflectLuaStateFields(script, state, true);
		});

		// ── save data ─────────────────────────────────────────────────────────
		script.set('save', flixel.FlxG.save.data);

		// ui object — backward compat
		final uiHelper:Dynamic =
			(state != null && Std.isOfType(state, flixel.FlxState))
			? funkin.scripting.ScriptBridge.buildUIHelper(cast state)
			: funkin.scripting.ScriptBridge.buildUIHelper(flixel.FlxG.state);
		script.set('ui', uiHelper);

		final st:flixel.FlxState = Std.isOfType(state, flixel.FlxState)
			? cast state : flixel.FlxG.state;

		// Display list
		script.set('add',    function(obj:Dynamic) { st.add(obj); return obj; });
		script.set('remove', function(obj:Dynamic) return st.remove(obj));
		script.set('insert', function(pos:Int, obj:Dynamic) { st.insert(pos, obj); return obj; });

		// Navigation — respeta stateOverrides de GlobalConfig
		script.set('switchState',         function(name:String) funkin.scripting.ScriptBridge.switchStateByName(name));
		script.set('switchStateInstance', function(inst:flixel.FlxState) funkin.transitions.StateTransition.switchState(inst));
		script.set('stickerSwitch',       function(inst:flixel.FlxState)
			funkin.transitions.StickerTransition.start(function() funkin.transitions.StateTransition.switchState(inst)));
		script.set('loadState',           function(inst:flixel.FlxState)
			funkin.states.LoadingState.loadAndSwitchState(inst));

		// Timers
		script.set('timer',    function(delay:Float, cb:Dynamic) return new flixel.util.FlxTimer().start(delay, cb));
		script.set('interval', function(delay:Float, cb:Dynamic, loops:Int = 0) return new flixel.util.FlxTimer().start(delay, cb, loops));
		script.set('cancelTweens', function(obj:Dynamic) flixel.tweens.FlxTween.cancelTweensOf(obj));

		// Camera
		script.set('shake',      function(i:Float = 0.005, d:Float = 0.25) flixel.FlxG.camera.shake(i, d));
		script.set('flash',      function(c:Int = 0xFFFFFFFF, d:Float = 0.5) flixel.FlxG.camera.flash(c, d));
		script.set('fade',       function(c:Int = 0xFF000000, d:Float = 0.5, fadeIn:Bool = false) flixel.FlxG.camera.fade(c, d, fadeIn));
		script.set('zoomCamera', function(target:Float = 1.0, d:Float = 0.3)
			flixel.tweens.FlxTween.tween(flixel.FlxG.camera, {zoom: target}, d, {ease: flixel.tweens.FlxEase.quadOut}));

		// Centering
		script.set('center',  function(spr:flixel.FlxSprite) { spr.screenCenter(); return spr; });
		script.set('centerX', function(spr:flixel.FlxSprite) { spr.screenCenter(flixel.util.FlxAxes.X); return spr; });
		script.set('centerY', function(spr:flixel.FlxSprite) { spr.screenCenter(flixel.util.FlxAxes.Y); return spr; });

		// Sound
		script.set('playSound', function(path:String, vol:Float = 1.0) {
			final resolved = Paths.sound(path);
			final snd = Paths.getSound(resolved);
			if (snd != null) flixel.FlxG.sound.play(snd, vol); else flixel.FlxG.sound.play(resolved, vol);
		});
		script.set('playMusic', function(path:String, vol:Float = 1.0) {
			final resolved = Paths.music(path);
			final snd = Paths.getSound(resolved);
			if (snd != null) flixel.FlxG.sound.playMusic(snd, vol); else flixel.FlxG.sound.playMusic(resolved, vol);
		});
		script.set('stopMusic', function() { if (flixel.FlxG.sound.music != null) flixel.FlxG.sound.music.stop(); });

		// Shared data (mismo API que HScript para scripts mixtos en el mismo estado)
		script.set('setShared',    function(k:String, v:Dynamic)    setShared(k, v));
		script.set('getShared',    function(k:String, ?def:Dynamic) return getShared(k, def));
		script.set('deleteShared', function(k:String)               deleteShared(k));

		// Broadcast
		script.set('broadcast', function(ev:String, ?args:Array<Dynamic>) broadcast(ev, args ?? []));

		// PlayState reference if available
		final ps = funkin.gameplay.PlayState.instance;
		if (ps != null) script.set('game', ps);
	}

	/**
	 * Expone AUTOMÁTICAMENTE todos los campos de instancia del state al script Lua,
	 * igual que _reflectStateFields hace para HScript.
	 *
	 * @param refresh  Si true, actualiza campos del state EXCEPTO vars fijas del API.
	 *                 Si false (init), no sobreescribe nada que ya exista.
	 */
	static final _LUA_API_VARS:Array<String> = [
		'FlxG', 'Math', 'Std', 'self', 'save',
		'getField', 'setField', 'callMethod', 'refreshFields',
		'ui', 'add', 'remove', 'insert',
		'switchState', 'switchStateInstance', 'stickerSwitch', 'loadState',
		'timer', 'interval', 'cancelTweens',
		'shake', 'flash', 'fade', 'zoomCamera',
		'center', 'centerX', 'centerY',
		'playSound', 'playMusic', 'stopMusic',
		'setShared', 'getShared', 'deleteShared', 'broadcast', 'game'
	];

	static function _reflectLuaStateFields(script:RuleScriptInstance, state:Dynamic, refresh:Bool = false):Void
	{
		if (state == null || !Std.isOfType(state, flixel.FlxState)) return;

		var fields:Array<String> = [];
		var cls:Dynamic = Type.getClass(state);
		while (cls != null)
		{
			for (f in Type.getInstanceFields(cls))
				if (!fields.contains(f))
					fields.push(f);
			cls = Type.getSuperClass(cls);
			// Parar en FlxState para no exponer internos de Flixel/OpenFL
			if (cls != null && Type.getClassName(cls) == 'flixel.FlxState')
				break;
		}

		for (fieldName in fields)
		{
			// En modo init: no sobreescribir las vars fijas del API Lua.
			// En modo refresh: actualizar campos del state SALVO las vars fijas.
			if (!refresh && _LUA_API_VARS.contains(fieldName)) continue;
			if (refresh  && _LUA_API_VARS.contains(fieldName)) continue;

			try
			{
				final value = Reflect.getProperty(state, fieldName);
				script.set(fieldName, value);
			}
			catch (e:Dynamic)
			{
				// Campo write-only o inaccesible — ignorar silenciosamente
			}
		}
	}
	#end


	// ─── Helpers internos ─────────────────────────────────────────────────────

	static function getSorted():Array<HScriptInstance>
	{
		if (_cacheDirty)
		{
			_sortedCache = [for (s in scripts) s];
			_sortedCache.sort((a, b) -> b.priority - a.priority);
			_cacheDirty = false;
		}
		return _sortedCache;
	}

	#if HSCRIPT_ALLOWED
	/**
	 * Expone AUTOMÁTICAMENTE todos los campos de instancia del state al script,
	 * igual que hace Codename Engine — sin necesidad de llamar exposeElement()
	 * manualmente para cada sprite/variable.
	 *
	 * Funcionamiento:
	 *  • Type.getInstanceFields() recorre toda la jerarquía de clases del state
	 *    y devuelve los nombres de todos los campos de instancia.
	 *  • Reflect.getProperty() lee el valor actual de cada campo.
	 *  • Los objetos (FlxSprite, FlxGroup…) se pasan por referencia — el script
	 *    puede modificarlos directamente (logoBl.visible = false; etc.).
	 *  • Los primitivos (Bool, Int, Float, String) se pasan por valor.
	 *    Para escribirlos de vuelta desde el script usa setField(nombre, valor).
	 *
	 * Ejemplo en script:
	 *   logoBl.visible = false;          // funciona — es referencia al sprite
	 *   setField('transitioning', true); // escribe un Bool del state
	 *   var v = getField('curBeat');     // lee cualquier campo
	 */
	static function _exposeStateAPI(interp:FunkinInterp, state:FlxState, script:HScriptInstance):Void
	{
		// ── 1. AUTO-REFLECT: exponer TODOS los campos de instancia del state ──
		_reflectStateFields(interp, state);

		// ── 2. Referencia principal al state ──────────────────────────────────
		interp.variables.set('state', state);
		interp.variables.set('save',  FlxG.save.data);

		// ── 3. Leer/escribir campos primitivos del state desde el script ──────
		//    Para objetos no hace falta porque son referencias, pero para
		//    Bool/Int/Float/String la asignación directa no escribe de vuelta.
		interp.variables.set('getField', (name:String) -> {
			try   { return Reflect.getProperty(state, name); }
			catch (e:Dynamic) { trace('[StateScript] getField("$name") failed: $e'); return null; }
		});
		interp.variables.set('setField', (name:String, value:Dynamic) -> {
			try   { Reflect.setProperty(state, name, value); }
			catch (e:Dynamic) { trace('[StateScript] setField("$name") failed: $e'); }
		});

		// ── 4. Llamar métodos del state por nombre ────────────────────────────
		//    callMethod('skipIntro')  →  state.skipIntro()
		interp.variables.set('callMethod', (name:String, ?args:Array<Dynamic>) -> {
			try
			{
				final fn = Reflect.getProperty(state, name);
				if (fn != null && Reflect.isFunction(fn))
					return Reflect.callMethod(state, fn, args ?? []);
			}
			catch (e:Dynamic) { trace('[StateScript] callMethod("$name") failed: $e'); }
			return null;
		});

		// ── 5. Re-sincronizar campos del state HACIA el script ─────────────────
		//    Útil para refrescar valores primitivos que cambiaron desde Haxe.
		//    Llamar desde el script cuando sea necesario: refreshFields()
		interp.variables.set('refreshFields', () -> _reflectStateFields(interp, state, true));

		// ── 6. Control de cancelación ─────────────────────────────────────────
		interp.variables.set('cancelEvent',   () -> true);
		interp.variables.set('continueEvent', () -> false);

		// ── 7. Prioridad dinámica ─────────────────────────────────────────────
		interp.variables.set('setPriority', (p:Int) -> {
			script.priority = p;
			_cacheDirty = true;
		});

		// ── 8. Tag del script ─────────────────────────────────────────────────
		interp.variables.set('setTag', (t:String) -> { script.tag = t; });
		interp.variables.set('getTag', () -> script.tag);

		// ── 9. Overrides de funciones ─────────────────────────────────────────
		interp.variables.set('overrideFunction', (name:String, fn:Dynamic) ->
			registerOverride(name, script, fn));
		interp.variables.set('removeOverride',   (name:String) -> unregisterOverride(name));
		interp.variables.set('toggleOverride',   (name:String, en:Bool) -> toggleOverride(name, en));
		interp.variables.set('hasOverride',       (name:String) -> hasOverride(name));

		// ── 10. Datos compartidos ─────────────────────────────────────────────
		interp.variables.set('setShared',    (k:String, v:Dynamic)    -> setShared(k, v));
		interp.variables.set('getShared',    (k:String, ?def:Dynamic) -> getShared(k, def));
		interp.variables.set('deleteShared', (k:String)               -> deleteShared(k));

		// ── 11. Hooks, broadcast, hot-reload, require ─────────────────────────
		interp.variables.set('registerHook', (name:String, fn:Dynamic->Void) ->
			registerHook(name, fn));
		interp.variables.set('broadcast', (ev:String, ?args:Array<Dynamic>) ->
			broadcast(ev, args ?? []));
		interp.variables.set('hotReload', () -> script.hotReload());
		interp.variables.set('require',   (path:String) -> script.require(path));

		// ── 12. Acceso a otros scripts del mismo state ────────────────────────
		interp.variables.set('getScript',    (name:String) -> getByName(name));
		interp.variables.set('getScriptTag', (tag:String)  -> getByTag(tag));

		// ── 13. Helper crear opciones de menú ─────────────────────────────────
		interp.variables.set('createOption',
			(name:String, getValue:Void->String, onPress:Void->Bool) -> ({
				name:     name,
				getValue: getValue,
				onPress:  onPress
			})
		);

		// ── 14. ui helper object (backward compat — scripts using ui.X still work) ──
		interp.variables.set('ui', ScriptBridge.buildUIHelper(state));

		// ── 15. Top-level equivalents — accurate to how a real FlxState works ────
		//
		// In Haxe you call add(), remove(), FlxTween.tween(), etc. directly.
		// Everything that used to require ui.X is now also available bare.
		// ui.X still works for old scripts — this is purely additive.

		// Display list (state-bound — need the state reference)
		if (!interp.variables.exists('add'))
			interp.variables.set('add',    function(obj:Dynamic) { state.add(obj); return obj; });
		if (!interp.variables.exists('remove'))
			interp.variables.set('remove', function(obj:Dynamic, splice:Bool = false) return state.remove(obj, splice));
		if (!interp.variables.exists('insert'))
			interp.variables.set('insert', function(pos:Int, obj:Dynamic) { state.insert(pos, obj); return obj; });

		// State navigation
		interp.variables.set('switchState',         function(name:String) funkin.scripting.ScriptBridge.switchStateByName(name));
		interp.variables.set('switchStateInstance', function(inst:flixel.FlxState) funkin.transitions.StateTransition.switchState(inst));
		interp.variables.set('stickerSwitch',       function(inst:flixel.FlxState)
			funkin.transitions.StickerTransition.start(function() funkin.transitions.StateTransition.switchState(inst)));
		interp.variables.set('loadState',           function(inst:flixel.FlxState)
			funkin.states.LoadingState.loadAndSwitchState(inst));

		// Timers (mirrors new FlxTimer().start(...))
		interp.variables.set('timer',    function(delay:Float, cb:flixel.util.FlxTimer->Void):flixel.util.FlxTimer
			return new flixel.util.FlxTimer().start(delay, cb));
		interp.variables.set('interval', function(delay:Float, cb:flixel.util.FlxTimer->Void, loops:Int = 0):flixel.util.FlxTimer
			return new flixel.util.FlxTimer().start(delay, cb, loops));

		// Tweens — FlxTween is already exposed by ScriptAPI, but these shorthands
		// mirror what you'd call directly on the state in Haxe:
		//   FlxTween.tween(spr, {alpha:0}, 0.5)  ← that already works
		//   cancelTweens(spr)                     ← shorthand for FlxTween.cancelTweensOf
		interp.variables.set('cancelTweens', function(obj:Dynamic) flixel.tweens.FlxTween.cancelTweensOf(obj));

		// Camera helpers (equivalent to FlxG.camera.X — those also work directly)
		interp.variables.set('shake', function(intensity:Float = 0.005, duration:Float = 0.25)
			flixel.FlxG.camera.shake(intensity, duration));
		interp.variables.set('flash', function(color:Int = 0xFFFFFFFF, duration:Float = 0.5)
			flixel.FlxG.camera.flash(color, duration));
		interp.variables.set('fade',  function(color:Int = 0xFF000000, duration:Float = 0.5, fadeIn:Bool = false)
			flixel.FlxG.camera.fade(color, duration, fadeIn));
		interp.variables.set('zoomCamera', function(target:Float = 1.0, duration:Float = 0.3)
			flixel.tweens.FlxTween.tween(flixel.FlxG.camera, {zoom: target}, duration,
				{ease: flixel.tweens.FlxEase.quadOut}));

		// Centering helpers (mirrors spr.screenCenter())
		interp.variables.set('center',  function(spr:flixel.FlxSprite) { spr.screenCenter(); return spr; });
		interp.variables.set('centerX', function(spr:flixel.FlxSprite) { spr.screenCenter(flixel.util.FlxAxes.X); return spr; });
		interp.variables.set('centerY', function(spr:flixel.FlxSprite) { spr.screenCenter(flixel.util.FlxAxes.Y); return spr; });

		// Sound (mirrors FlxG.sound.X — those also work directly)
		interp.variables.set('playSound', function(path:String, vol:Float = 1.0) {
			final resolved = Paths.sound(path);
			final snd = Paths.getSound(resolved);
			if (snd != null) flixel.FlxG.sound.play(snd, vol);
			else flixel.FlxG.sound.play(resolved, vol);
		});
		interp.variables.set('playMusic', function(path:String, vol:Float = 1.0) {
			final resolved = Paths.music(path);
			final snd = Paths.getSound(resolved);
			if (snd != null) flixel.FlxG.sound.playMusic(snd, vol);
			else flixel.FlxG.sound.playMusic(resolved, vol);
		});
		interp.variables.set('stopMusic', function() {
			if (flixel.FlxG.sound.music != null) flixel.FlxG.sound.music.stop();
		});

		// ── 16. Reference to the script itself ────────────────────────────────
		interp.variables.set('self', script);
	}

	/**
	 * Itera TODOS los campos de instancia del state (y sus superclases)
	 * y los inyecta en el intérprete del script por reflexión.
	 *
	 * @param refresh  Si true (modo refresh), sobreescribe campos existentes del
	 *                 state EXCEPTO las variables fijas del API del engine.
	 *                 Si false (modo init, default), no sobreescribe nada que ya
	 *                 exista — el API tiene prioridad.
	 *
	 * Uso:
	 *   • Modo init   → llamado desde _exposeStateAPI al cargar el script por primera vez.
	 *   • Modo refresh → llamado desde refreshStateFields() / refreshFields()
	 *                    cuando el state crea objetos DESPUÉS de cargar los scripts.
	 */
	static final _API_VARS:Array<String> = [
		'state','save','getField','setField','callMethod','refreshFields',
		'cancelEvent','continueEvent','setPriority','setTag','getTag',
		'overrideFunction','removeOverride','toggleOverride','hasOverride',
		'setShared','getShared','deleteShared','registerHook','broadcast',
		'hotReload','require','getScript','getScriptTag','createOption','ui','self',
		'add','remove','insert',
		'switchState','switchStateInstance','stickerSwitch','loadState',
		'timer','interval','cancelTweens',
		'shake','flash','fade','zoomCamera',
		'center','centerX','centerY',
		'playSound','playMusic','stopMusic'
	];

	static function _reflectStateFields(interp:FunkinInterp, state:FlxState, refresh:Bool = false):Void
	{
		// Obtener todos los campos de instancia recorriendo la jerarquía completa.
		// Type.getSuperClass() devuelve Class<Dynamic>, no Class<FlxState>, así que
		// usamos Dynamic para la variable de iteración y evitamos el error de tipos.
		var fields:Array<String> = [];
		var cls:Dynamic = Type.getClass(state);
		while (cls != null)
		{
			for (f in Type.getInstanceFields(cls))
				if (!fields.contains(f))
					fields.push(f);
			cls = Type.getSuperClass(cls);
			// Parar en FlxState para no exponer internos de Flixel/OpenFL
			if (cls != null && Type.getClassName(cls) == 'flixel.FlxState')
				break;
		}

		for (fieldName in fields)
		{
			// En modo init: no sobreescribir NADA que ya exista (API tiene prioridad).
			// En modo refresh: actualizar campos del state SALVO las vars fijas del API.
			if (!refresh && interp.variables.exists(fieldName)) continue;
			if (refresh && _API_VARS.contains(fieldName)) continue;

			try
			{
				final value = Reflect.getProperty(state, fieldName);
				interp.variables.set(fieldName, value);
			}
			catch (e:Dynamic)
			{
				// Campo write-only o inaccesible — ignorar silenciosamente
			}
		}
	}
	#end
}

// ─────────────────────────────────────────────────────────────────────────────

class FunctionOverride
{
	public var funcName : String;
	public var script   : HScriptInstance;
	public var func     : Dynamic;
	public var enabled  : Bool = true;

	public function new(funcName, script, func)
	{
		this.funcName = funcName;
		this.script   = script;
		this.func     = func;
	}

	public function call(args:Array<Dynamic>):Dynamic
	{
		if (!enabled || !script.active) return null;

		try
		{
			if (Reflect.isFunction(func))
				return Reflect.callMethod(null, func, args);
		}
		catch (e:Dynamic)
		{
			trace('[FunctionOverride] Error "$funcName": ${Std.string(e)}');
		}

		return null;
	}
}
