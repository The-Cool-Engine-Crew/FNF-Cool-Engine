package funkin.scripting;

import haxe.Exception;
#if sys
import sys.FileSystem;
import sys.io.File;
#end
#if HSCRIPT_ALLOWED
import hscript.Parser;
import hscript.Interp;
#end

using StringTools;

/**
 * ScriptHandler v4 — central script management for gameplay and mods.
 *
 * ─── Script layers ───────────────────────────────────────────────────────────
 *
 *   global   → always active (entire game session)
 *   stage    → active during the current stage
 *   song     → active during the current song
 *   ui       → HUD / UIScriptedManager scripts
 *   menu     → state and menu scripts (FreeplayState, TitleState, etc.)
 *   char     → scripts for a specific character
 *
 * ─── Full folder structure ───────────────────────────────────────────────────
 *
 *   BASE GAME:
 *   assets/data/scripts/global/          → base global scripts
 *   assets/data/scripts/events/          → custom event handlers
 *   assets/songs/{song}/scripts/         → song scripts
 *   assets/songs/{song}/events/          → song-specific custom events
 *   assets/stages/{stage}/scripts/       → stage scripts
 *   assets/characters/{char}/scripts/    → character scripts
 *   assets/states/{state}/              → state / menu scripts
 *
 *   MODS:
 *   mods/{mod}/scripts/global/           → mod global scripts
 *   mods/{mod}/scripts/events/
 *   mods/{mod}/songs/{song}/scripts/
 *   mods/{mod}/songs/{song}/events/
 *   mods/{mod}/stages/{stage}/scripts/
 *   mods/{mod}/characters/{char}/scripts/
 *   mods/{mod}/states/{state}/
 *   mods/{mod}/data/scripts/             → extra alias
 *
 *   PSYCH-COMPAT (additional recognised paths):
 *   mods/{mod}/custom_events/{event}.hx
 *   mods/{mod}/custom_notetypes/{type}.hx
 *
 * ─── Script types supported ──────────────────────────────────────────────────
 *  .hx / .hscript  → HScriptInstance  (requires HSCRIPT_ALLOWED)
 *  .lua            → RuleScriptInstance (requires LUA_ALLOWED + linc_luajit)
 *                    Full LuaJIT OOP bridge — import(), overrideMethod(),
 *                    require(), custom classes, direct Haxe field access.
 *
 * @author Cool Engine Team
 * @version 4.0.0
 */
class ScriptHandler
{
	// ── Almacenamiento de scripts por capa ────────────────────────────────────
	public static var globalScripts:Map<String, HScriptInstance> = [];
	public static var stageScripts:Map<String, HScriptInstance> = [];
	public static var songScripts:Map<String, HScriptInstance> = [];
	public static var uiScripts:Map<String, HScriptInstance> = [];
	public static var menuScripts:Map<String, HScriptInstance> = [];
	public static var charScripts:Map<String, HScriptInstance> = [];

	// OPT v4: Arrays paralelos para iteración en hot-path (frame-by-frame).
	// Las Maps se mantienen para lookup por nombre (hotReload, charScriptsByName).
	// Los Arrays se usan en _callLayer / _destroyLayer / _setLayerVar / etc.
	// Se sincronizan en _registerScript y _removeFromArray.
	static var _globalArr:Array<HScriptInstance>  = [];
	static var _stageArr:Array<HScriptInstance>   = [];
	static var _songArr:Array<HScriptInstance>    = [];
	static var _uiArr:Array<HScriptInstance>      = [];
	static var _menuArr:Array<HScriptInstance>    = [];
	static var _charArr:Array<HScriptInstance>    = [];

	#if (LUA_ALLOWED && linc_luajit)
	// RuleScript layers — one array per gameplay context (same structure as HScript layers)
	public static var globalLuaScripts:Array<RuleScriptInstance> = [];
	public static var stageLuaScripts:Array<RuleScriptInstance> = [];
	public static var songLuaScripts:Array<RuleScriptInstance> = [];
	public static var uiLuaScripts:Array<RuleScriptInstance> = [];
	public static var menuLuaScripts:Array<RuleScriptInstance> = [];
	public static var charLuaScripts:Array<RuleScriptInstance> = [];
	#end

	/**
	 * Index of character scripts grouped by name.
	 * Allows callOnCharacterScripts in O(1) instead of iterating all charScripts.
	 * Populated by loadCharacterScripts and cleared by destroy().
	 */
	public static var charScriptsByName:Map<String, Array<HScriptInstance>> = [];

	// ── Reusable hot-path arrays (avoid allocating new Array every frame) ────
	// Every gameplay callback (onUpdate, onBeatHit, onStepHit,
	// onNoteHit, onMiss…) passes its args through these static arrays instead
	// of creating a new Array<Dynamic> on each call.
	// IMPORTANT: These arrays are temporary — only valid during the
	// callOnScripts call. Do NOT store references to them in scripts.

	/** For onUpdate(elapsed:Float) */
	public static final _argsUpdate:Array<Dynamic> = [0.0];

	/** For onUpdatePost(elapsed:Float) */
	public static final _argsUpdatePost:Array<Dynamic> = [0.0];

	/** For onBeatHit(beat:Int) */
	public static final _argsBeat:Array<Dynamic> = [0];

	/** For onStepHit(step:Int) */
	public static final _argsStep:Array<Dynamic> = [0];

	/** For onNoteHit / onMiss — [note, extra] */
	public static final _argsNote:Array<Dynamic> = [null, null];

	/** For events with a single generic argument */
	public static final _argsOne:Array<Dynamic> = [null];

	/** Reusable empty array — for no-argument callbacks */
	public static final _argsEmpty:Array<Dynamic> = [];

	/** For onAnimStart/onSingStart/onSingEnd in character scripts — [arg0, arg1] */
	public static final _argsAnim:Array<Dynamic> = [null, null];

	// ── Parser compartido ─────────────────────────────────────────────────────
	#if HSCRIPT_ALLOWED
	static var _parser:Parser = null;

	public static var parser(get, null):Parser;

	static function get_parser():Parser
	{
		if (_parser == null)
		{
			_parser = new Parser();
			_parser.allowTypes = true;
			_parser.allowJSON = true;
			try
			{
				Reflect.setField(_parser, 'allowInterp', true);
			}
			catch (_e:Dynamic)
			{
			}
			
			try
			{
				Reflect.setField(_parser, 'allowMetadata', true);
			}
			catch (_e:Dynamic)
			{
			}
		}
		return _parser;
	}
	#end

	// ── Init ──────────────────────────────────────────────────────────────────

	public static function init():Void
	{
		loadGlobalScripts();
		trace('[ScriptHandler v4] Ready.');
	}

	/**
	 * Loads all global scripts: base + mods + custom_events (Psych compat).
	 */
	public static function loadGlobalScripts():Void
	{
		// Clear previous global scripts to avoid duplicates on the 2nd playthrough
		_destroyLayer(globalScripts);
		globalScripts.clear();
		_clearArr(_globalArr);

		#if sys
		if (mods.ModManager.isActive())
		{
			final r = mods.ModManager.modRoot();
			// Standard mod paths
			_loadFolder('$r/scripts/global', 'global');
			_loadFolder('$r/scripts/events', 'global');
			_loadFolder('$r/data/scripts', 'global');
			_loadFolder('$r/data/config', 'global');
			// Psych-compat paths
			_loadFolder('$r/custom_events', 'global');
			_loadFolder('$r/custom_notetypes', 'global');
		}
		#end
		// FIX (Android): el working directory no es el root del APK, por lo que
		// rutas relativas como 'assets/...' pueden fallar en sys.FileSystem.exists().
		// Usamos Sys.programPath() para construir una ruta absoluta garantizada.
		#if sys
		final base = haxe.io.Path.directory(Sys.programPath());
		_loadFolder('$base/assets/data/scripts/global', 'global');
		_loadFolder('$base/assets/data/scripts/events', 'global');
		#end
		trace('[ScriptHandler v4] Global scripts loaded.');
	}

	// ── Context loading ───────────────────────────────────────────────────────

	/** Loads scripts for song `songName` from base + mod. */
	public static function loadSongScripts(songName:String):Void
	{
		// FIX: clear existing song/ui layers before loading so retries don't
		// double-register scripts. loadGlobalScripts() already does this for
		// its own layer; song scripts need the same guard.
		_destroyLayer(songScripts);
		_destroyLayer(uiScripts);
		songScripts.clear();
		uiScripts.clear();
		_clearArr(_songArr);
		_clearArr(_uiArr);
		#if (LUA_ALLOWED && linc_luajit)
		_destroyLuaLayer(songLuaScripts);
		_destroyLuaLayer(uiLuaScripts);
		#end
		#if sys
		if (mods.ModManager.isActive())
		{
			final r = mods.ModManager.modRoot();
			_loadFolder('$r/songs/$songName/scripts', 'song');
			_loadFolder('$r/songs/$songName/events', 'song');
			// Psych Engine layout: scripts live in data/{songName}/ alongside the chart
			_loadFolder('$r/data/$songName', 'song');
		}
		#end
		_loadFolder('assets/songs/$songName/scripts', 'song');
		_loadFolder('assets/songs/$songName/events', 'song');
	}

	/** Loads scripts for stage `stageName` from base + mod. */
	public static function loadStageScripts(stageName:String):Void
	{
		final sn = stageName.toLowerCase();
		#if sys
		if (mods.ModManager.isActive())
		{
			final r = mods.ModManager.modRoot();
			_loadFolder('$r/stages/$sn/scripts', 'stage');
			_loadFolder('$r/assets/stages/$sn/scripts', 'stage');
		}
		#end
		_loadFolder('assets/stages/$sn/scripts', 'stage');
		_loadFolder('assets/data/stages/$sn/scripts', 'stage');
	}

	/**
	 * Loads scripts for character `charName` from base + mod.
	 * Scripts are tagged with `charName` so they can be filtered later.
	 * Returns the list of loaded scripts so the caller can inject variables.
	 *
	 *  ── Search paths (priority order) ───────────────────────────────────────
	 *
	 *   Canonical new path (recommended):
	 *     assets/characters/scripts/{char}/scripts.hx
	 *     mods/{mod}/characters/scripts/{char}/scripts.hx
	 *
	 *   Legacy paths (still work for backward compat):
	 *     assets/characters/{char}/scripts/              ← folder with multiple .hx
	 *     mods/{mod}/characters/{char}/scripts/
	 *     mods/{mod}/characters/{char}/                  ← loose .hx (legacy)
	 */
	public static function loadCharacterScripts(charName:String):Array<HScriptInstance>
	{
		final loaded:Array<HScriptInstance> = [];
		#if sys
		if (mods.ModManager.isActive())
		{
			final r = mods.ModManager.modRoot();
			// ── Nueva ruta canónica (mod) ────────────────────────────────────
			for (s in _loadFolder('$r/characters/scripts/$charName', 'char'))
				loaded.push(s);
			// ── Rutas heredadas (mod) — compat con mods anteriores ───────────
			for (s in _loadFolder('$r/characters/$charName/scripts', 'char'))
				loaded.push(s);
			// FIXED: usar _loadFolderFlat para la carpeta raíz del personaje —
			// recurrir aquí cargaría assets que no son scripts (imágenes, animaciones…).
			for (s in _loadFolderFlat('$r/characters/$charName', 'char'))
				loaded.push(s);
		}
		#end
		// ── Nueva ruta canónica (base game) ─────────────────────────────────
		for (s in _loadFolder('assets/characters/scripts/$charName', 'char'))
			loaded.push(s);
		// ── Ruta heredada (base game) ────────────────────────────────────────
		for (s in _loadFolder('assets/characters/$charName/scripts', 'char'))
			loaded.push(s);
		// Taggear y registrar en el índice por nombre
		if (loaded.length > 0)
		{
			for (s in loaded)
				s.tag = charName;
			if (!charScriptsByName.exists(charName))
				charScriptsByName.set(charName, []);
			for (s in loaded)
				charScriptsByName.get(charName).push(s);
		}
		return loaded;
	}

	/**
	 * Calls `func` on scripts for character `charName`.
	 * Uses charScriptsByName for O(1) lookup — does not iterate all charScripts.
	 */
	public static function callOnCharacterScripts(charName:String, func:String, args:Array<Dynamic>):Void
	{
		#if HSCRIPT_ALLOWED
		final list = charScriptsByName.get(charName);
		if (list == null)
			return; // fast guard: no scripts for this character
		for (script in list)
		{
			try
			{
				if (script != null && script.active)
					script.call(func, args);
			}
			catch (e:Dynamic)
			{
				// Outer safety net — script.call() already has its own try/catch,
				// but this catches anything that slips through (null refs, etc.).
				trace('[ScriptHandler] Unhandled error in character script"'
					+ '${script?.name ?? charName}" ($func): ${Std.string(e)}');
			}
		}
		#end
	}

	/**
	 * Like callOnCharacterScripts but returns true if any script returns true.
	 * (Used to cancel default behaviour: `return true` in overrideDance, etc.)
	 */
	public static function callOnCharacterScriptsReturn(charName:String, func:String, args:Array<Dynamic>):Bool
	{
		#if HSCRIPT_ALLOWED
		final list = charScriptsByName.get(charName);
		if (list == null)
			return false; // fast guard
		var result = false;
		for (script in list)
		{
			try
			{
				if (script != null && script.active && script.call(func, args) == true)
					result = true;
			}
			catch (e:Dynamic)
			{
				trace('[ScriptHandler] Unhandled error in character script "'
					+ '${script?.name ?? charName}" ($func): ${Std.string(e)}');
			}
		}
		return result;
		#else
		return false;
		#end
	}

	/**
	 * Injects variables into scripts for a specific character.
	 * Uses charScriptsByName for O(1) lookup.
	 */
	public static function setOnCharacterScripts(charName:String, varName:String, value:Dynamic):Void
	{
		#if HSCRIPT_ALLOWED
		final list = charScriptsByName.get(charName);
		if (list == null)
			return;
		for (script in list)
			if (script.interp != null)
				script.interp.variables.set(varName, value);
		#end
	}

	/**
	 * Loads scripts for state/menu `stateName`.
	 * Searches in `assets/states/{stateName}/` and `mods/{mod}/states/{stateName}/`.
	 */
	public static function loadStateScripts(stateName:String):Void
	{
		#if sys
		if (mods.ModManager.isActive())
		{
			final r = mods.ModManager.modRoot();
			_loadFolder('$r/states/$stateName', 'menu');
		}
		#end
		_loadFolder('assets/states/$stateName', 'menu');
	}

	// ── Individual script loading ─────────────────────────────────────────────

	/**
	 * Loads a script from `scriptPath`.
	 * Supports native .hx / .hscript and .lua (Psych-compat transpilation).
	 *
	 * @param presetVars  Variables injected BEFORE execute() (top-level code sees them).
	 * @param stage       Stage reference for the Psych Lua API shim.
	 */
	/**
	 * Loads a script from `scriptPath` and calls onCreate/postCreate.
	 * Delegates to _createScript with callInit = true.
	 */
	public static function loadScript(scriptPath:String, scriptType:String = 'song', ?presetVars:Map<String, Dynamic>,
			?stage:funkin.gameplay.objects.stages.Stage):Null<HScriptInstance>
	{
		return _createScript(scriptPath, scriptType, presetVars, stage, true);
	}

	/**
	 * Like loadScript() but does NOT call onCreate/postCreate automatically.
	 * Use when the caller needs to inject additional APIs BEFORE the first onCreate.
	 * The script is parsed, ScriptAPI is exposed, and the program is executed (functions defined).
	 * The caller is responsible for calling script.call('onCreate') when ready.
	 */
	public static function loadScriptNoInit(scriptPath:String, scriptType:String = 'song', ?presetVars:Map<String, Dynamic>):Null<HScriptInstance>
	{
		return _createScript(scriptPath, scriptType, presetVars, null, false);
	}

	/**
	 * FIX #2: método privado unificado que reemplaza los cuerpos duplicados de
	 * loadScript() y loadScriptNoInit(). Antes ambos tenían ~80 líneas idénticas;
	 * cualquier bug corregido en uno había que replicarlo manualmente en el otro.
	 *
	 * El único punto de variación es `callInit`: si es true, se invoca onCreate
	 * y postCreate al final (comportamiento de loadScript). Si es false, esas
	 * llamadas se omiten y el caller decide cuándo invocarlas (loadScriptNoInit).
	 *
	 * @param scriptPath  Ruta al archivo .hx/.hscript/.lua.
	 * @param scriptType  Capa de registro: 'global', 'stage', 'song', 'ui', 'menu', 'char'.
	 * @param presetVars  Variables inyectadas ANTES de execute() — el top-level las ve.
	 * @param stage       Referencia al Stage para el shim Psych Lua (sólo .lua).
	 * @param callInit    Si true, llama onCreate + postCreate tras execute().
	 */
	static function _createScript(scriptPath:String, scriptType:String, ?presetVars:Map<String, Dynamic>, ?stage:funkin.gameplay.objects.stages.Stage,
			callInit:Bool = true):Null<HScriptInstance>
	{
		#if HSCRIPT_ALLOWED
		#if sys
		if (!FileSystem.exists(scriptPath))
		{
			trace('[ScriptHandler] Script not found: $scriptPath');
			return null;
		}
		#end

		final isLua = scriptPath.endsWith('.lua');
		final rawContent = #if sys File.getContent(scriptPath) #else '' #end;

		final content = isLua ? mods.compat.LuaStageConverter.convert(rawContent, _extractName(scriptPath)) : rawContent;

		if (isLua)
			trace('[ScriptHandler] Transpiling Lua: $scriptPath');

		final scriptName = _extractName(scriptPath);
		final script = new HScriptInstance(scriptName, scriptPath);
		// Cachear el source procesado para que _handleError pueda mostrar
		// la línea exacta del fallo en errores de runtime posteriores.
		script._source = content;

		try
		{
			script.interp = new funkin.scripting.interp.FunkinInterp();

			// Si es un script de stage, pasarle el stage como objeto base
			if (scriptType == 'stage' && stage != null)
			{
				script.scriptObject = stage;
			}

			ScriptAPI.expose(script.interp);

			script.interp.variables.set('require', function(path:String):Dynamic return script.require(path));
			script.interp.variables.set('log', function(msg:Dynamic):Void trace('[Script:$scriptName] $msg'));

			if (presetVars != null)
				for (k => v in presetVars)
					script.interp.variables.set(k, v);

			if (isLua)
				mods.compat.PsychLuaGameplayAPI.expose(script.interp);

			if (isLua && stage != null)
				mods.compat.PsychLuaStageAPI.expose(script.interp, stage);

			_autoInjectContext(script.interp, scriptType);

			final finalContent = isLua ? content : processImports(content, script.interp);
			if (finalContent != content)
				script._source = finalContent;
			script.program = parser.parseString(finalContent, scriptPath);

			script.interp.execute(script.program);
			if (!isLua)
				script.warmCache(); // OPT v4: pre-fill _funcCache tras execute()

			if (isLua)
				mods.compat.PsychLuaGameplayAPI.setupCallbackAliases(script);

			// Punto de variación: loadScript llama init, loadScriptNoInit no.
			if (callInit)
			{
				script.call('onCreate');
				script.call('postCreate');
			}

			_registerScript(script, scriptType);
			trace('[ScriptHandler] Loaded${callInit ? "" : " (no-init)"} [$scriptType]: $scriptName${isLua ? " (from Lua)" : ""}');
			return script;
		}
		catch (e:Dynamic)
		{
			// Extraer número de línea del error de parse/runtime para un mensaje concreto.
			var lineInfo = '';
			try
			{
				if (Reflect.hasField(e, 'line'))
				{
					lineInfo = ':${Reflect.field(e, 'line')}';
				}
				else if (Reflect.hasField(e, 'pmin'))
				{
					final pmin:Int = Reflect.field(e, 'pmin');
					var lineNum = 1;
					final len = Std.int(Math.min(pmin, content.length));
					for (i in 0...len)
						if (content.charAt(i) == '\n')
							lineNum++;
					lineInfo = ':$lineNum';
				}
			}
			catch (_e:Dynamic)
			{
			}

			var errorStr = "(error desconocido)";
			try { errorStr = Std.string(e); } catch (_e:Dynamic) {}

			trace('[ScriptHandler] Error loading script "$scriptName$lineInfo": $errorStr');
			if (isLua)
				try { trace('[ScriptHandler] Transpiled Lua code:\n$content'); } catch (_e:Dynamic) {}

			// ── In-game popup for load / parse failures ──────────────────────
			// Envuelto en try/catch — si el popup falla el juego no debe crashear.
			try
			{
				ScriptErrorNotifier.notify(
					scriptName, 'load', errorStr,
					lineInfo == '' ? -1 : Std.parseInt(lineInfo.substr(1)));
			}
			catch (_notifyErr:Dynamic)
			{
				try { Sys.stderr().writeString('[ScriptError][load] $scriptName$lineInfo → $errorStr\n'); } catch (_e:Dynamic) {}
			}

			return null;
		}
		#else
		trace('[ScriptHandler] HSCRIPT_ALLOWED not defined in Project.xml — scripts disabled.');
		return null;
		#end
	}

	#if HSCRIPT_ALLOWED
	/** Auto-inyecta el contexto de PlayState si hay una instancia activa. */
	static function _autoInjectContext(interp:hscript.Interp, scriptType:String):Void
	{
		final ps = funkin.gameplay.PlayState.instance;
		if (ps == null)
			return;
		final vars = _buildPlayStateVars(ps);
		for (k => v in vars)
			interp.variables.set(k, v);
	}
	#end

	static function _buildPlayStateVars(ps:funkin.gameplay.PlayState):Map<String, Dynamic>
	{
		final vars:Map<String, Dynamic> = [];
		vars.set('game', ps);
		vars.set('playState', ps);

		// FIX: 'controls' es private+inline en MusicBeatState — la reflexión no
		// lo detecta. Lo exponemos aquí para que scripts de canción, stage,
		// personaje y global puedan usar controls.UP_P / controls.ACCEPT, etc.
		try { vars.set('controls', data.PlayerSettings.player1.controls); }
		catch (e:Dynamic) { trace('[ScriptHandler] controls expose failed: $e'); }
		vars.set('health', ps.health);
		vars.set('camGame', ps.camGame);
		vars.set('camHUD', ps.camHUD);
		vars.set('camCountdown', ps.camCountdown);
		vars.set('bf', ps.boyfriend);
		vars.set('dad', ps.dad);
		vars.set('gf', ps.gf);
		vars.set('stage', ps.currentStage);
		vars.set('notes', ps.notes);
		vars.set('sustainNotes', ps.sustainNotes);
		vars.set('strumLineNotes', ps.strumLineNotes);
		vars.set('grpNoteSplashes', ps.grpNoteSplashes);
		vars.set('grpHoldCovers', ps.grpHoldCovers);
		vars.set('vocals', ps.vocals);
		vars.set('paused', ps.paused);
		vars.set('inCutscene', ps.inCutscene);
		vars.set('canPause', ps.canPause);
		vars.set('scoreManager', ps.scoreManager);
		vars.set('gameState', ps.gameState);
		vars.set('noteManager', ps.noteManager);
		vars.set('metaData', ps.metaData);
		vars.set('countdown', ps.countdown);
		vars.set('enableBatching', ps.enableBatching);
		vars.set('strumsGroups', ps.strumsGroups);
		vars.set('playerStrumsGroup', ps.playerStrumsGroup);
		vars.set('cpuStrumsGroup', ps.cpuStrumsGroup);
		vars.set('SONG', funkin.gameplay.PlayState.SONG);
		vars.set('isStoryMode', funkin.gameplay.PlayState.isStoryMode);
		vars.set('isBotPlay', funkin.gameplay.PlayState.isBotPlay);
		vars.set('startingSong', funkin.gameplay.PlayState.startingSong);
		vars.set('curStage', funkin.gameplay.PlayState.curStage);
		vars.set('storyDifficulty', funkin.gameplay.PlayState.storyDifficulty);
		vars.set('storyWeek', funkin.gameplay.PlayState.storyWeek);
		vars.set('storyPlaylist', funkin.gameplay.PlayState.storyPlaylist);
		vars.set('campaignScore', funkin.gameplay.PlayState.campaignScore);
		vars.set('cinematicMode', funkin.gameplay.PlayState.cinematicMode);
		vars.set('isPlaying', funkin.gameplay.PlayState.isPlaying);
		// Reflection fallback (campos no anticipados)
		if (_psInstanceFields == null)
			_psInstanceFields = Type.getInstanceFields(funkin.gameplay.PlayState);
		if (_psClassFields == null)
			_psClassFields = Type.getClassFields(funkin.gameplay.PlayState);
		for (field in _psInstanceFields)
		{
			if (field.startsWith('_') || vars.exists(field))
				continue;
			try
			{
				final v = Reflect.getProperty(ps, field);
				if (!Reflect.isFunction(v))
					vars.set(field, v);
			}
			catch (_e:Dynamic)
			{
			}
		}
		for (field in _psClassFields)
		{
			if (field.startsWith('_') || vars.exists(field))
				continue;
			try
			{
				final v = Reflect.getProperty(funkin.gameplay.PlayState, field);
				if (!Reflect.isFunction(v))
					vars.set(field, v);
			}
			catch (_e:Dynamic)
			{
			}
		}
		return vars;
	}

	/** Loads all `.hx` / `.hscript` / `.lua` files from a folder. */
	public static function loadScriptsFromFolder(folderPath:String, scriptType:String = 'song'):Array<HScriptInstance>
	{
		return _loadFolder(folderPath, scriptType);
	}

	/**
	 * Like loadScriptsFromFolder but does NOT recurse into subdirectories.
	 * Use when you explicitly want a flat scan of a single folder.
	 */
	public static function loadScriptsFromFolderFlat(folderPath:String, scriptType:String = 'song'):Array<HScriptInstance>
	{
		return _loadFolderFlat(folderPath, scriptType);
	}

	/** Loads scripts from an explicit list of paths. */
	public static function loadScriptsFromArray(paths:Array<String>, scriptType:String = 'stage'):Array<HScriptInstance>
	{
		final out:Array<HScriptInstance> = [];
		for (p in paths)
		{
			final s = loadScript(p, scriptType);
			if (s != null)
				out.push(s);
		}
		return out;
	}

	// ── Script calls ─────────────────────────────────────────────────────────

	/**
	 * Calls `funcName(args)` on ALL scripts in ALL layers.
	 * Order: global → stage → song → ui → menu → char.
	 */
	public static function callOnScripts(funcName:String, args:Array<Dynamic> = null):Void
	{
		// OPT: reutilizar _argsEmpty en vez de asignar un Array nuevo en el heap.
		if (args == null)
			args = _argsEmpty;
		// OPT v4: _callArr itera Array en vez de Map (~2-3x más rápido)
		_callArr(_globalArr, funcName, args);
		_callArr(_stageArr,  funcName, args);
		_callArr(_songArr,   funcName, args);
		_callArr(_uiArr,     funcName, args);
		_callArr(_menuArr,   funcName, args);
		_callArr(_charArr,   funcName, args);

		#if (LUA_ALLOWED && linc_luajit)
		_callLuaLayer(globalLuaScripts, funcName, args);
		_callLuaLayer(stageLuaScripts, funcName, args);
		_callLuaLayer(songLuaScripts, funcName, args);
		_callLuaLayer(uiLuaScripts, funcName, args);
		_callLuaLayer(menuLuaScripts, funcName, args);
		_callLuaLayer(charLuaScripts, funcName, args);
		#end
	}

	/**
	 * Like callOnScripts but returns the first non-null / non-defaultValue result.
	 * If any script returns `true` (cancel), propagation stops.
	 * No intermediate array allocation — iterates layers directly.
	 */
	public static function callOnScriptsReturn(funcName:String, args:Array<Dynamic> = null, defaultValue:Dynamic = null):Dynamic
	{
		// OPT: reutilizar _argsEmpty en vez de asignar un Array nuevo.
		if (args == null)
			args = _argsEmpty;
		// OPT: antes había una closure `_checkLayer` definida aquí dentro, lo
		// que asignaba un objeto de closure en el GC en CADA llamada a este método.
		// Ahora se delega al método estático privado _checkLayerReturn, que es
		// una simple llamada de función sin asignación adicional de heap.
		#if HSCRIPT_ALLOWED
		var r:Dynamic;
		r = _checkLayerReturn(globalScripts, funcName, args, defaultValue);
		if (r != null)
			return r;
		r = _checkLayerReturn(stageScripts, funcName, args, defaultValue);
		if (r != null)
			return r;
		r = _checkLayerReturn(songScripts, funcName, args, defaultValue);
		if (r != null)
			return r;
		r = _checkLayerReturn(uiScripts, funcName, args, defaultValue);
		if (r != null)
			return r;
		r = _checkLayerReturn(menuScripts, funcName, args, defaultValue);
		if (r != null)
			return r;
		r = _checkLayerReturn(charScripts, funcName, args, defaultValue);
		if (r != null)
			return r;
		#end
		return defaultValue;
	}

	/** Injects a variable into all active scripts. */
	public static function setOnScripts(varName:String, value:Dynamic):Void
	{
		// OPT: las closures locales _setLayer / _setLua se definían dentro del método,
		// lo que asignaba un objeto closure en el GC cada vez que se llamaba setOnScripts.
		// Delegamos a métodos estáticos para evitar esa asignación.
		// OPT v4: _setArrVar itera Array en vez de Map
		_setArrVar(_globalArr, varName, value);
		_setArrVar(_stageArr,  varName, value);
		_setArrVar(_songArr,   varName, value);
		_setArrVar(_uiArr,     varName, value);
		_setArrVar(_menuArr,   varName, value);
		_setArrVar(_charArr,   varName, value);

		#if (LUA_ALLOWED && linc_luajit)
		_setLuaLayerVar(globalLuaScripts, varName, value);
		_setLuaLayerVar(stageLuaScripts, varName, value);
		_setLuaLayerVar(songLuaScripts, varName, value);
		_setLuaLayerVar(uiLuaScripts, varName, value);
		_setLuaLayerVar(menuLuaScripts, varName, value);
		_setLuaLayerVar(charLuaScripts, varName, value);
		#end
	}

	static var _psInstanceFields:Null<Array<String>> = null;
	static var _psClassFields:Null<Array<String>> = null;

	public static function injectPlayState(ps:funkin.gameplay.PlayState):Void
	{
		if (ps == null)
			return;

		final vars = _buildPlayStateVars(ps);
		// OPT v4: iterate arrays
		_injectArrVars(_globalArr, vars);
		_injectArrVars(_stageArr,  vars);
		_injectArrVars(_songArr,   vars);
		_injectArrVars(_uiArr,     vars);
		_injectArrVars(_menuArr,   vars);
		_injectArrVars(_charArr,   vars);

		if (ps.uiManager != null)
		{
			final hudVars = ps.uiManager.getScriptVars();
			final hudObjects = new Map<String, Dynamic>();
			for (k => v in hudVars)
				if (!Reflect.isFunction(v))
					hudObjects.set(k, v);
			_injectLayerVars(globalScripts, hudObjects);
			_injectLayerVars(stageScripts, hudObjects);
			_injectLayerVars(songScripts, hudObjects);
			_injectLayerVars(charScripts, hudObjects);
		}
	}

	/** Injects a variable only into stage scripts. */
	public static function setOnStageScripts(varName:String, value:Dynamic):Void
	{
		for (script in stageScripts)
			if (script.active)
				script.set(varName, value);
	}

	/** Calls a function only in stage scripts. */
	public static function callOnStageScripts(funcName:String, args:Array<Dynamic> = null):Void
	{
		if (args == null)
			args = [];
		_callArr(_stageArr, funcName, args); // OPT v4
	}

	/**
	 * Calls a function on all layers EXCEPT stageScripts.
	 * Use when stage scripts already fired the event in loadStageScripts()
	 * and a second execution would overwrite the correct state.
	 */
	public static function callOnNonStageScripts(funcName:String, args:Array<Dynamic> = null):Void
	{
		if (args == null)
			args = [];
		_callArr(_globalArr, funcName, args); // OPT v4
		_callArr(_songArr,   funcName, args);
		_callArr(_uiArr,     funcName, args);
		_callArr(_menuArr,   funcName, args);
		_callArr(_charArr,   funcName, args);
	}

	/** Gets the value of a variable from active scripts (first non-null result). */
	public static function getFromScripts(varName:String, defaultValue:Dynamic = null):Dynamic
	{
		// OPT: closure local eliminada → sin alloc de heap por llamada.
		var v:Dynamic;
		v = _getLayerVar(globalScripts, varName);
		if (v != null)
			return v;
		v = _getLayerVar(stageScripts, varName);
		if (v != null)
			return v;
		v = _getLayerVar(songScripts, varName);
		if (v != null)
			return v;
		v = _getLayerVar(uiScripts, varName);
		if (v != null)
			return v;
		v = _getLayerVar(menuScripts, varName);
		if (v != null)
			return v;
		v = _getLayerVar(charScripts, varName);
		if (v != null)
			return v;
		return defaultValue;
	}

	// ── Cleanup ───────────────────────────────────────────────────────────────

	public static function clearSongScripts():Void
	{
		_destroyLayer(songScripts);
		_destroyLayer(uiScripts);
		songScripts.clear();
		uiScripts.clear();

		#if (LUA_ALLOWED && linc_luajit)
		_destroyLuaLayer(songLuaScripts);
		_destroyLuaLayer(uiLuaScripts);
		#end

		// FIX Bug 6: flush the static signal bus so closures registered by mod
		// scripts via signal.on('beat', fn) cannot retain strong references to
		// PlayState objects (Character, Stage, notes, etc.) after the song ends.
		// Without this, each song leaks 50-80 MB worth of gameplay objects that
		// the GC can never reclaim because _signals keeps them rooted.
		try { @:privateAccess funkin.scripting.ScriptAPI._signals.clear(); } catch (_:Dynamic) {}
		try { @:privateAccess funkin.scripting.ScriptAPI._signalsOnce.clear(); } catch (_:Dynamic) {}
	}

	public static function clearStageScripts():Void
	{
		_destroyLayer(stageScripts);
		stageScripts.clear();
		_clearArr(_stageArr);

		#if (LUA_ALLOWED && linc_luajit)
		_destroyLuaLayer(stageLuaScripts);
		#end
	}

	public static function clearCharScripts():Void
	{
		_destroyLayer(charScripts);
		charScripts.clear();
		_clearArr(_charArr);

		#if (LUA_ALLOWED && linc_luajit)
		_destroyLuaLayer(charLuaScripts);
		#end

		charScriptsByName.clear(); // clear index too
	}

	public static function clearMenuScripts():Void
	{
		_destroyLayer(menuScripts);
		menuScripts.clear();

		#if (LUA_ALLOWED && linc_luajit)
		_destroyLuaLayer(menuLuaScripts);
		#end
		
		_clearArr(_menuArr);
	}

	public static function clearAll():Void
	{
		clearSongScripts();
		clearStageScripts();
		clearCharScripts();
		clearMenuScripts();
		_destroyLayer(globalScripts);
		globalScripts.clear();
	}

	// ── Hot-reload ────────────────────────────────────────────────────────────

	/** Reloads a script by name (without restarting the interpreter). */
	public static function hotReload(name:String):Bool
	{
		// No alloc: check layers directly.
		function _tryReload(layer:Map<String, HScriptInstance>):Bool
		{
			if (!layer.exists(name))
				return false;
			layer.get(name).hotReload();
			trace('[ScriptHandler] Hot-reload: $name');
			return true;
		}
		if (_tryReload(globalScripts))
			return true;
		if (_tryReload(stageScripts))
			return true;
		if (_tryReload(songScripts))
			return true;
		if (_tryReload(uiScripts))
			return true;
		if (_tryReload(menuScripts))
			return true;
		if (_tryReload(charScripts))
			return true;
		trace('[ScriptHandler] hotReload: "$name" not found.');
		return false;
	}

	/** Reloads all scripts in all layers. */
	public static function hotReloadAll():Void
	{
		final layers = [globalScripts, stageScripts, songScripts, uiScripts, menuScripts, charScripts];
		for (layer in layers)
			for (s in layer)
				s.hotReload();
		trace('[ScriptHandler] Hot-reload complete.');

		// FIX #5: StateScriptHandler.hotReloadAll() DEBE estar fuera del bloque
		// #if LUA_ALLOWED. Si el proyecto compila sin Lua, el bloque entero se
		// descarta → los state scripts nunca se recargaban. Moverlo aquí garantiza
		// que siempre se ejecuta independientemente del flag de Lua.
		funkin.scripting.StateScriptHandler.hotReloadAll();

		#if (LUA_ALLOWED && linc_luajit)
		for (lua in globalLuaScripts)
			lua.hotReload();
		for (lua in stageLuaScripts)
			lua.hotReload();
		for (lua in songLuaScripts)
			lua.hotReload();
		for (lua in uiLuaScripts)
			lua.hotReload();
		for (lua in menuLuaScripts)
			lua.hotReload();
		for (lua in charLuaScripts)
			lua.hotReload();
		#end
	}

	// ── Internals ─────────────────────────────────────────────────────────────

	/**
	 * FIX: La versión anterior sólo escaneaba el nivel inmediato del directorio.
	 * `FileSystem.readDirectory()` devuelve tanto archivos como subdirectorios.
	 * Los nombres de subdirectorio no terminan en `.hx`/`.hscript`/`.lua`,
	 * así que eran silenciosamente ignorados — cualquier script en una subcarpeta
	 * nunca llegaba a cargarse.
	 *
	 * La corrección añade `FileSystem.isDirectory()` para detectar subcarpetas
	 * y llama a `_loadFolder` recursivamente sobre ellas, preservando el mismo
	 * `scriptType`. También se extrae `fullPath` una sola vez por entrada para
	 * no concatenar la misma cadena dos veces.
	 */
	static function _loadFolder(folderPath:String, scriptType:String):Array<HScriptInstance>
	{
		final out:Array<HScriptInstance> = [];
		#if sys
		if (!FileSystem.exists(folderPath) || !FileSystem.isDirectory(folderPath))
			return out;
		for (file in FileSystem.readDirectory(folderPath))
		{
			final fullPath = '$folderPath/$file';
			// FIXED: recurrir a subcarpetas para que los scripts anidados se carguen.
			if (FileSystem.isDirectory(fullPath))
			{
				for (s in _loadFolder(fullPath, scriptType))
					out.push(s);
				continue;
			}
			#if (LUA_ALLOWED && linc_luajit)
			if (file.endsWith('.lua'))
			{
				_loadLuaFile(fullPath, scriptType);
				continue;
			}
			#end
			if (!file.endsWith('.hx') && !file.endsWith('.hscript'))
				continue;
			final s = loadScript(fullPath, scriptType);
			if (s != null)
				out.push(s);
		}
		#end
		return out;
	}

	/**
	 * Escaneo plano (no recursivo) de un directorio — ignora subcarpetas.
	 * Usado para `mods/{mod}/characters/{charName}/` donde la carpeta raíz
	 * puede contener imágenes, datos de animación, etc. que no son scripts.
	 */
	static function _loadFolderFlat(folderPath:String, scriptType:String):Array<HScriptInstance>
	{
		final out:Array<HScriptInstance> = [];
		#if sys
		if (!FileSystem.exists(folderPath) || !FileSystem.isDirectory(folderPath))
			return out;
		for (file in FileSystem.readDirectory(folderPath))
		{
			final fullPath = '$folderPath/$file';
			if (FileSystem.isDirectory(fullPath))
				continue; // plano: saltar subcarpetas intencionalmente
			#if (LUA_ALLOWED && linc_luajit)
			if (file.endsWith('.lua'))
			{
				_loadLuaFile(fullPath, scriptType);
				continue;
			}
			#end
			if (!file.endsWith('.hx') && !file.endsWith('.hscript'))
				continue;
			final s = loadScript(fullPath, scriptType);
			if (s != null)
				out.push(s);
		}
		#end
		return out;
	}

	static function _registerScript(script:HScriptInstance, scriptType:String):Void
	{
		// OPT v4: mantenemos tanto la Map (lookup por nombre) como el Array
		// paralelo (iteración sin overhead de tabla hash en hot-path).
		var map:Map<String, HScriptInstance>;
		var arr:Array<HScriptInstance>;
		switch (scriptType.toLowerCase())
		{
			case 'global': map = globalScripts; arr = _globalArr;
			case 'stage':  map = stageScripts;  arr = _stageArr;
			case 'ui':     map = uiScripts;     arr = _uiArr;
			case 'menu':   map = menuScripts;   arr = _menuArr;
			case 'char':   map = charScripts;   arr = _charArr;
			default:       map = songScripts;   arr = _songArr;
		}
		// Duplicate names → numeric suffix
		var name = script.name;
		var i = 1;
		while (map.exists(name))
			name = '${script.name}_${i++}';
		script.name = name;
		map.set(name, script);
		arr.push(script);
	}

	/** @deprecated Mantener firma para compatibilidad; usa la overload de Array internamente. */
	static inline function _callLayer(layer:Map<String, HScriptInstance>, func:String, args:Array<Dynamic>):Void {}

	/**
	 * OPT v4: iteración sobre Array en vez de Map.
	 * Array usa aritmética de puntero; Map usa traversal de tabla hash.
	 * Sobre 10 scripts activos, el array es ~2-3x más rápido de iterar.
	 *
	 * script.call() ya tiene su propio try/catch para errores de script;
	 * el try externo solo protege contra null object reference del propio
	 * objeto script (caso extremadamente raro pero posible durante destroy).
	 */
	static function _callArr(arr:Array<HScriptInstance>, func:String, args:Array<Dynamic>):Void
	{
		#if HSCRIPT_ALLOWED
		for (script in arr)
			if (script != null && script.active)
				script.call(func, args);
		#end
	}

	static function _destroyLayer(layer:Map<String, HScriptInstance>):Void
	{
		// BUGFIX: do NOT call onDestroy here (see history for full explanation).
		// OPT v4: iterate the parallel array — same elements, faster traversal.
		for (script in layer)
			script.dispose();
	}

	/** Limpia el array paralelo correspondiente a una Map de scripts. */
	static function _clearArr(arr:Array<HScriptInstance>):Void
	{
		#if (cpp || hl)
		arr.resize(0); // resize(0) es O(1) en cpp/hl; evita realloc
		#else
		arr.splice(0, arr.length);
		#end
	}

	#if (LUA_ALLOWED && linc_luajit)
	static function _callLuaLayer(layer:Array<RuleScriptInstance>, func:String, args:Array<Dynamic>):Void
	{
		for (lua in layer)
			if (lua.active)
				lua.call(func, args);
	}

	static function _destroyLuaLayer(layer:Array<RuleScriptInstance>):Void
	{
		for (lua in layer)
			try
				lua.destroy()
			catch (_e:Dynamic)
			{
			};
		layer.resize(0);
	}

	/**
	 * Loads a .lua file as a RuleScriptInstance into the correct gameplay layer.
	 * RuleScript provides a full LuaJIT OOP bridge to all Haxe classes.
	 * Called automatically by _loadFolder when a .lua file is found.
	 */
	static function _loadLuaFile(path:String, scriptType:String):Null<RuleScriptInstance>
	{
		if (!FileSystem.exists(path))
			return null;
		final name = _extractName(path);
		final script = new RuleScriptInstance(name, path);

		script.loadFile(path);

		if (!script.active)
		{
			trace('[ScriptHandler] RuleScript error: $path');
			script.destroy();
			return null;
		}

		var target:Array<RuleScriptInstance> = switch (scriptType.toLowerCase())
		{
			case 'global': globalLuaScripts;
			case 'stage': stageLuaScripts;
			case 'ui': uiLuaScripts;
			case 'menu': menuLuaScripts;
			case 'char': charLuaScripts;
			default: songLuaScripts;
		};
		target.push(script);

		script.call('onCreate');
		script.call('postCreate');
		trace('[ScriptHandler] RuleScript loaded [$scriptType]: $name');
		return script;
	}
	#end

	/** Public alias for _extractName for compatibility. */
	public static inline function extractName(path:String):String
		return _extractName(path);

	/**
	 * OPT: versión sin alloc de Array.
	 * La versión original hacía path.split('/').pop() + path.split('\\').pop(),
	 * asignando dos Array<String> temporales en el GC en cada llamada.
	 * Esta versión usa lastIndexOf() — O(n) sobre la cadena, sin allocs extra.
	 */
	static inline function _extractName(path:String):String
	{
		var sep1 = path.lastIndexOf('/');
		var sep2 = path.lastIndexOf('\\');
		var start = (sep1 > sep2 ? sep1 : sep2) + 1; // +1 para saltar el separador
		var name = start > 0 ? path.substring(start) : path;
		final dot = name.lastIndexOf('.');
		if (dot > 0)
			name = name.substring(0, dot);
		return name;
	}

	// ── Static helpers (reemplazan closures de instancia para evitar alloc GC) ─
	/**
	 * Helper estático para callOnScriptsReturn.
	 * Una closure definida dentro del método asigna un objeto en el GC por cada
	 * invocación. Un método estático es una dirección de función — sin alloc.
	 */
	#if HSCRIPT_ALLOWED
	static function _checkLayerReturn(layer:Map<String, HScriptInstance>, funcName:String, args:Array<Dynamic>, defaultValue:Dynamic):Dynamic
	{
		for (script in layer)
		{
			if (script == null || !script.active)
				continue;
			try
			{
				final r = script.call(funcName, args);
				if (r != null && r != defaultValue)
					return r;
			}
			catch (_layerErr:Dynamic) {}
		}
		return null;
	}
	#end

	/** Helper estático para setOnScripts — evita closure por llamada. */
	static inline function _setLayerVar(layer:Map<String, HScriptInstance>, varName:String, value:Dynamic):Void
	{
		for (script in layer)
			if (script.active)
				script.set(varName, value);
	}

	/** OPT v4: versión Array de _setLayerVar para hot-path. */
	static inline function _setArrVar(arr:Array<HScriptInstance>, varName:String, value:Dynamic):Void
	{
		for (script in arr)
			if (script != null && script.active)
				script.set(varName, value);
	}

	#if (LUA_ALLOWED && linc_luajit)
	/** Helper estático para setOnScripts (Lua) — evita closure por llamada. */
	static inline function _setLuaLayerVar(layer:Array<RuleScriptInstance>, varName:String, value:Dynamic):Void
	{
		for (lua in layer)
			if (lua.active)
				lua.set(varName, value);
	}
	#end

	/** Helper estático para getFromScripts — evita closure por llamada. */
	static function _getLayerVar(layer:Map<String, HScriptInstance>, varName:String):Dynamic
	{
		for (script in layer)
			if (script.active)
			{
				final v = script.get(varName);
				if (v != null)
					return v;
			}
		return null;
	}

	/** Helper estático para injectPlayState — evita closure por llamada. */
	static function _injectLayerVars(layer:Map<String, HScriptInstance>, vars:Map<String, Dynamic>):Void
	{
		for (script in layer)
			if (script.active && script.interp != null)
				for (k => v in vars)
					script.interp.variables.set(k, v);
	}

	/** OPT v4: versión Array de _injectLayerVars. */
	static function _injectArrVars(arr:Array<HScriptInstance>, vars:Map<String, Dynamic>):Void
	{
		for (script in arr)
			if (script != null && script.active && script.interp != null)
				for (k => v in vars)
					script.interp.variables.set(k, v);
	}

	// ═══════════════════════════════════════════════════════════════════════════
	// ── Script source pre-processor ──────────────────────────────────────────
	// ═══════════════════════════════════════════════════════════════════════════
	//
	// processImports() is the single entry-point used by ALL script loaders
	// (ScriptHandler._createScript, StateScriptHandler.loadScript,
	//  HScriptInstance.loadString, HScriptInstance.hotReload).
	//
	// Pipeline (in order):
	//   1. _processConditionals  — #if / #elseif / #else / #end  (NEW)
	//   2. _packageReg           — strip `package foo.bar;`
	//   3. _usingReg             — strip `using foo.Bar;`
	//   4. _importReg            — resolve `import a.b.C;` into interp variables
	//
	// FIX: declarar las EReg como static final para compilar el patrón una sola vez.
	#if HSCRIPT_ALLOWED
	static final _importReg :EReg = ~/^[ \t]*import\s+([\w.]+)(?:\s+as\s+(\w+))?\s*;/gm;
	static final _packageReg:EReg = ~/^[ \t]*package\s+[\w.]*\s*;/gm;
	static final _usingReg  :EReg = ~/^[ \t]*using\s+([\w.]+)\s*;/gm;

	// EReg por línea para las directivas condicionales de hscript
	static final _condIfReg    :EReg = ~/^[ \t]*#if\b(.*)/;
	static final _condElseifReg:EReg = ~/^[ \t]*#elseif\b(.*)/;
	static final _condElseReg  :EReg = ~/^[ \t]*#else\b/;
	static final _condEndReg   :EReg = ~/^[ \t]*#end\b/;
	#end

	// ── Runtime defines ───────────────────────────────────────────────────────

	/**
	 * Map of defines available for `#if` conditions in scripts.
	 * Populated once at runtime from Haxe compile-time flags.
	 *
	 * Mods can add their own defines at boot:
	 *   ScriptHandler.scriptDefines.set("myMod", true);
	 */
	public static var scriptDefines(get, null):Map<String, Bool>;
	static var _scriptDefines:Map<String, Bool> = null;

	static function get_scriptDefines():Map<String, Bool>
	{
		if (_scriptDefines != null) return _scriptDefines;
		_scriptDefines = new Map<String, Bool>();

		// ── Target / platform ─────────────────────────────────────────────────
		#if desktop    _scriptDefines["desktop"]  = true; #end
		#if mobile     _scriptDefines["mobile"]   = true; #end
		#if sys        _scriptDefines["sys"]       = true; #end
		#if cpp        _scriptDefines["cpp"]       = true; #end
		#if hl         _scriptDefines["hl"]        = true; #end
		#if neko       _scriptDefines["neko"]      = true; #end
		#if windows    _scriptDefines["windows"]   = true; #end
		#if linux      _scriptDefines["linux"]     = true; #end
		#if (mac || macos)
		_scriptDefines["mac"]   = true;
		_scriptDefines["macos"] = true;
		#end
		#if android    _scriptDefines["android"]   = true; #end
		#if ios        _scriptDefines["ios"]       = true; #end
		#if (html5 || js)
		_scriptDefines["html5"] = true;
		_scriptDefines["web"]   = true;
		_scriptDefines["js"]    = true;
		#end

		// ── Build type ────────────────────────────────────────────────────────
		#if debug      _scriptDefines["debug"]     = true; #end
		#if !debug     _scriptDefines["release"]   = true; #end

		// ── Engine feature flags ──────────────────────────────────────────────
		#if HSCRIPT_ALLOWED    _scriptDefines["HSCRIPT_ALLOWED"]    = true; #end
		#if LUA_ALLOWED        _scriptDefines["LUA_ALLOWED"]        = true; #end
		#if (LUA_ALLOWED && linc_luajit) _scriptDefines["linc_luajit"] = true; #end

		// Sentinel so the defines lazy-init doesn't re-run if all are absent
		_scriptDefines["__initialized"] = true;

		return _scriptDefines;
	}

	// ── Condition evaluator ───────────────────────────────────────────────────

	/**
	 * Evaluates a `#if` condition string against `scriptDefines`.
	 *
	 * Supports:
	 *   - Simple identifiers:            desktop,  !mobile
	 *   - AND / OR (correct precedence): desktop && sys,  mobile || web
	 *   - Parentheses:                   (desktop && sys) || html5
	 *   - Literals:                      true, false
	 *
	 * Unknown identifiers evaluate to false.
	 */
	public static function evalScriptCond(cond:String):Bool
	{
		cond = cond.trim();
		if (cond == '' || cond == 'false') return false;
		if (cond == 'true')  return true;

		// ── Strip balanced outer parentheses ──────────────────────────────────
		if (cond.charAt(0) == '(')
		{
			var depth = 0;
			var outerMatch = true;
			for (i in 0...cond.length)
			{
				if (cond.charAt(i) == '(') depth++;
				else if (cond.charAt(i) == ')')
				{
					depth--;
					if (depth == 0 && i < cond.length - 1) { outerMatch = false; break; }
				}
			}
			if (outerMatch)
				return evalScriptCond(cond.substring(1, cond.length - 1));
		}

		// ── Find || at the top level (lowest precedence, left-to-right) ──────
		var depth = 0;
		for (i in 0...cond.length - 1)
		{
			final c = cond.charAt(i);
			if      (c == '(') depth++;
			else if (c == ')') depth--;
			else if (c == '|' && cond.charAt(i + 1) == '|' && depth == 0)
				return evalScriptCond(cond.substring(0, i))
				    || evalScriptCond(cond.substring(i + 2));
		}

		// ── Find && at the top level ──────────────────────────────────────────
		depth = 0;
		for (i in 0...cond.length - 1)
		{
			final c = cond.charAt(i);
			if      (c == '(') depth++;
			else if (c == ')') depth--;
			else if (c == '&' && cond.charAt(i + 1) == '&' && depth == 0)
				return evalScriptCond(cond.substring(0, i))
				    && evalScriptCond(cond.substring(i + 2));
		}

		// ── Negation ──────────────────────────────────────────────────────────
		if (cond.charAt(0) == '!')
			return !evalScriptCond(cond.substring(1).ltrim());

		// ── Simple identifier ─────────────────────────────────────────────────
		// Strip any remaining whitespace / trailing comment and look up
		final ident = cond.split(' ')[0].split('\t')[0];
		return scriptDefines.exists(ident) && scriptDefines[ident] == true;
	}

	// ── Conditional compilation preprocessor ─────────────────────────────────

	/**
	 * Processes `#if` / `#elseif` / `#else` / `#end` blocks in HScript source.
	 *
	 * Active branches are kept verbatim. Inactive lines are replaced with blank
	 * comment lines so that line numbers in error messages remain accurate.
	 *
	 * Supports nesting and all three branch forms:
	 *
	 *   #if desktop
	 *     FlxG.fullscreen = true;
	 *   #elseif mobile
	 *     FlxG.resizeGame(480, 320);
	 *   #else
	 *     trace("unknown target");
	 *   #end
	 */
	#if HSCRIPT_ALLOWED
	static function _processConditionals(source:String):String
	{
		// Normalise line endings
		final lines = source.split('\n');
		final out:Array<String> = [];

		// Stack of {active, anyBranchTaken}.
		// `active`         — whether lines in the current block should be emitted.
		// `anyBranchTaken` — true once a branch of the current #if chain evaluated true.
		final stack:Array<{active:Bool, anyBranchTaken:Bool}> = [];

		inline function isActive():Bool
			return stack.length == 0 || stack[stack.length - 1].active;

		for (rawLine in lines)
		{
			// Strip trailing \r for Windows line endings
			final line = rawLine.endsWith('\r') ? rawLine.substring(0, rawLine.length - 1) : rawLine;

			if (_condIfReg.match(line))
			{
				final cond = _condIfReg.matched(1).trim();
				final parentActive = isActive();
				final taken = parentActive && evalScriptCond(cond);
				stack.push({active: taken, anyBranchTaken: taken});
				out.push('// [#if $cond]');
			}
			else if (_condElseifReg.match(line))
			{
				if (stack.length > 0)
				{
					final top = stack.pop();
					final parentActive = isActive();
					final cond = _condElseifReg.matched(1).trim();
					final taken = parentActive && !top.anyBranchTaken && evalScriptCond(cond);
					stack.push({active: taken, anyBranchTaken: top.anyBranchTaken || taken});
					out.push('// [#elseif $cond]');
				}
				else
				{
					trace('[ScriptHandler] #elseif without #if — ignored');
					out.push('// [#elseif — unmatched]');
				}
			}
			else if (_condElseReg.match(line))
			{
				if (stack.length > 0)
				{
					final top = stack.pop();
					final parentActive = isActive();
					stack.push({active: parentActive && !top.anyBranchTaken, anyBranchTaken: true});
					out.push('// [#else]');
				}
				else
				{
					trace('[ScriptHandler] #else without #if — ignored');
					out.push('// [#else — unmatched]');
				}
			}
			else if (_condEndReg.match(line))
			{
				if (stack.length > 0)
					stack.pop();
				else
					trace('[ScriptHandler] #end without #if — ignored');
				out.push('// [#end]');
			}
			else
			{
				// Regular line: emit only if we're inside an active branch (or no branch at all).
				// Inactive lines become `// ` to preserve line numbers for error reporting.
				out.push(isActive() ? (rawLine.endsWith('\r') ? line : rawLine) : '// ');
			}
		}

		if (stack.length > 0)
			trace('[ScriptHandler] ${stack.length} unclosed #if block(s) detected.');

		return out.join('\n');
	}
	#end

	// ── Main preprocessor entry-point ─────────────────────────────────────────

	/**
	 * Full source pre-processing pipeline for HScript files.
	 *
	 * Pipeline (in order):
	 *   1. #if / #elseif / #else / #end  — conditional compilation
	 *   2. package foo.bar;              → comment (hscript doesn't support it)
	 *   3. using foo.Bar;                → comment (extension methods unsupported)
	 *   4. import a.b.C;                 → comment + inject class into interp
	 *
	 * @param source   Raw source code of the script (read from disk or string).
	 * @param interp   Interpreter into which imported classes will be injected.
	 * @return         Source code safe to pass to hscript.Parser.parseString().
	 */
	#if HSCRIPT_ALLOWED
	public static function processImports(source:String, interp:Interp):String
	{
		// ── Step 1: #if / #elseif / #else / #end ─────────────────────────────
		var result = _processConditionals(source);

		// ── Step 2: strip `package foo.bar;` ─────────────────────────────────
		result = _packageReg.map(result, function(r:EReg):String
		{
			trace('[ScriptHandler] package stripped: ${r.matched(0).trim()}');
			return '// [package] ${r.matched(0).trim()}';
		});

		// ── Step 3: strip `using foo.Bar;` ───────────────────────────────────
		// Extension methods are not supported by hscript at runtime.
		// Comment the line so the parser doesn't reject it.
		result = _usingReg.map(result, function(r:EReg):String
		{
			trace('[ScriptHandler] using stripped: ${r.matched(1)}');
			return '// [using] ${r.matched(1)}';
		});

		// ── Step 4: resolve `import a.b.C;` ──────────────────────────────────
		// Each import is resolved via Type.resolveClass / Type.resolveEnum and
		// injected into interp.variables under the short name (or alias).
		// The import line is replaced with a comment so hscript doesn't see it.
		return _importReg.map(result, function(r:EReg):String
		{
			final fullName  = r.matched(1);
			final alias     = r.matched(2);
			final shortName = (alias != null && alias != '') ? alias : fullName.split('.').pop();

			// If ScriptAPI.expose() already registered a hand-crafted proxy for
			// this name (e.g. FlxColor proxy, FlxEase proxy) do NOT overwrite it.
			// Abstracts are erased at runtime — the raw class resolved via
			// Type.resolveClass() would expose the @:impl class whose static fields
			// are NOT accessible via Reflect.field().
			if (interp.variables.exists(shortName))
			{
				trace('[ScriptHandler] import $fullName → kept existing proxy for "$shortName"');
				return '// [import] $fullName';
			}

			var resolved:Dynamic = Type.resolveClass(fullName);
			if (resolved == null)
				resolved = Type.resolveEnum(fullName);

			if (resolved != null)
			{
				interp.variables.set(shortName, resolved);
				trace('[ScriptHandler] import $fullName → $shortName');
			}
			else
			{
				trace('[ScriptHandler] unresolved import: $fullName (missing from build?)');
			}

			return '// [import] $fullName';
		});
	}
	#end
}
