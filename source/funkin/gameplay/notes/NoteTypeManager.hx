package funkin.gameplay.notes;

#if sys
import sys.FileSystem;
import sys.io.File;
#end
import flixel.graphics.frames.FlxAtlasFrames;
import funkin.scripting.HScriptInstance;
import funkin.scripting.ScriptHandler;
#if (LUA_ALLOWED && linc_luajit)
import funkin.scripting.RuleScriptInstance;
#end

/**
 * NoteTypeManager — Sistema de tipos de nota personalizados.
 *
 * ─── Estructura de carpetas ────────────────────────────────────────────────
 *
 *   assets/notes/custom/{typeName}/
 *     {typeName}.json      ← configuración (opcional)
 *     {typeName}.hx        ← script HScript (opcional)
 *     {typeName}.lua       ← script Lua (opcional, si LUA_ALLOWED)
 *     {typeName}.png       ← textura de nota cabeza (opcional, con .xml)
 *     {typeName}.xml
 *     {typeName}.png       ← splashes and hold splashes (opcional, con .xml)
 *     {typeName}.xml
 *     {typeName}_hold.png  ← textura de sustain (opcional, con .xml)
 *     {typeName}_hold.xml
 *
 *   mods/{mod}/notes/custom/{typeName}/   ← misma estructura, prioridad sobre base
 *
 * ─── noteType.json ────────────────────────────────────────────────────────
 *
 *   {
 *     "ignoreMiss":      false,
 *     "ignoreScore":     false,
 *     "noCPUHit":        false,
 *     "splash":          "MySplash",
 *     "holdSplash":      "MySplash",
 *     "sustainTexture":  "holdPurple",
 *     "color":           "0xFFFF0000"
 *   }
 *
 * ─── API del script (.hx o .lua) ──────────────────────────────────────────
 *
 *   function onSpawn(note)               { }
 *   function onPlayerHit(note, game)     { return false; }
 *   function onPlayerHitPost(note, game) { }
 *   function onCPUHit(note, game)        { }
 *   function onMiss(note, game)          { return false; }
 */

using StringTools;

class NoteTypeManager
{
	// ─── Cache ────────────────────────────────────────────────────────────────
	static var _types:Null<Array<String>> = null;

	static var _scripts:Map<String, Null<HScriptInstance>> = [];

	#if (LUA_ALLOWED && linc_luajit)
	static var _luaScripts:Map<String, Null<RuleScriptInstance>> = [];
	#end

	static var _frames:Map<String, Null<FlxAtlasFrames>> = [];
	static var _holdFrames:Map<String, Null<FlxAtlasFrames>> = [];
	static var _configs:Map<String, Null<NoteTypeConfig>> = [];

	/** Runtime registry (ScriptAPI compat). */
	static var _runtimeTypes:Map<String, Dynamic> = [];

	// ─── REGISTRO RUNTIME ────────────────────────────────────────────────────

	public static function register(name:String, cfg:Dynamic):Void
	{
		_runtimeTypes.set(name, cfg);
		_types = null;
		trace('[NoteTypeManager] Tipo "$name" registrado en runtime.');
	}

	public static function unregister(name:String):Void
	{
		_runtimeTypes.remove(name);
		_types = null;
	}

	public static function exists(name:String):Bool
	{
		if (_runtimeTypes.exists(name)) return true;
		return getTypes().indexOf(name) >= 0;
	}

	public static function getAll():Array<String>
	{
		final base = getTypes().copy();
		for (k in _runtimeTypes.keys())
			if (base.indexOf(k) < 0) base.push(k);
		return base;
	}

	// ─── DISCOVERY ───────────────────────────────────────────────────────────

	public static function getTypes():Array<String>
	{
		if (_types != null) return _types;
		_types = [];
		#if sys
		if (mods.ModManager.isActive())
		{
			final dir = '${mods.ModManager.modRoot()}/noteTypes';
			if (FileSystem.exists(dir) && FileSystem.isDirectory(dir))
				for (e in FileSystem.readDirectory(dir))
					if (FileSystem.isDirectory('$dir/$e') && _types.indexOf(e) == -1)
						_types.push(e);
		}
		final base = 'assets/notes/noteCustom';
		if (FileSystem.exists(base) && FileSystem.isDirectory(base))
			for (e in FileSystem.readDirectory(base))
				if (FileSystem.isDirectory('$base/$e') && _types.indexOf(e) == -1)
					_types.push(e);
		#end
		_types.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		return _types;
	}

	public static function clearCache():Void
	{
		_types = null;

		// FIX Bug 6: _scripts and _luaScripts were cleared with map.clear()
		// without calling destroy() on each instance first.
		// HScriptInstance.destroy() releases the hscript Interp and all its
		// variable bindings (closures over Note, PlayState, etc.).
		// RuleScriptInstance.destroy() closes the Lua VM.
		// Without these calls, every note-type script loaded during a song
		// kept its interpreter alive, holding strong references to gameplay
		// objects (NoteManager, PlayState, StrumNote…) that the GC could
		// never reclaim after the song ended.
		for (_ => s in _scripts)
			if (s != null) try s.destroy() catch (_:Dynamic) {}
		_scripts.clear();

		_frames.clear();
		_holdFrames.clear();
		_configs.clear();

		#if (LUA_ALLOWED && linc_luajit)
		for (_ => s in _luaScripts)
			if (s != null) try s.destroy() catch (_:Dynamic) {}
		_luaScripts.clear();
		#end
	}

	// ─── CONFIG JSON ─────────────────────────────────────────────────────────

	public static function getConfig(typeName:String):Null<NoteTypeConfig>
	{
		if (!isCustomType(typeName)) return null;
		if (_configs.exists(typeName)) return _configs.get(typeName);
		final cfg = _loadConfig(typeName);
		_configs.set(typeName, cfg);
		return cfg;
	}

	static function _loadConfig(typeName:String):Null<NoteTypeConfig>
	{
		#if sys
		final candidates = ['$typeName.json', 'config.json', 'noteType.json'];
		final dirs:Array<String> = [];
		if (mods.ModManager.isActive())
			dirs.push('${mods.ModManager.modRoot()}/notes/custom/$typeName');
		dirs.push('assets/notes/custom/$typeName');

		for (d in dirs)
			for (fname in candidates)
			{
				final p = '$d/$fname';
				if (!FileSystem.exists(p)) continue;
				try
				{
					final raw:Dynamic = haxe.Json.parse(File.getContent(p));
					var colorVal:Null<Int> = null;
					if (raw.color != null)
					{
						if (Std.isOfType(raw.color, Int))
							colorVal = cast raw.color;
						else
						{
							var hex:String = Std.string(raw.color);
							if (hex.startsWith('0x') || hex.startsWith('0X'))
								colorVal = Std.parseInt(hex);
							else if (hex.startsWith('#'))
								colorVal = Std.parseInt('0xFF' + hex.substr(1));
						}
					}
					return {
						ignoreMiss:     raw.ignoreMiss    == true,
						ignoreScore:    raw.ignoreScore   == true,
						noCPUHit:       raw.noCPUHit      == true,
						splash:         raw.splash        != null ? Std.string(raw.splash)         : null,
						holdSplash:     raw.holdSplash    != null ? Std.string(raw.holdSplash)     : null,
						sustainTexture: raw.sustainTexture != null ? Std.string(raw.sustainTexture) : null,
						color:          colorVal
					};
				}
				catch (e:Dynamic) { trace('[NoteTypeManager] Error config $p: $e'); }
			}
		#end
		return null;
	}

	// ─── SCRIPTS HSCRIPT ─────────────────────────────────────────────────────

	public static function getScript(typeName:String):Null<HScriptInstance>
	{
		if (!isCustomType(typeName)) return null;
		if (_scripts.exists(typeName)) return _scripts.get(typeName);

		final path = _findScriptPath(typeName, false);
		var inst:Null<HScriptInstance> = null;
		if (path != null)
		{
			inst = cast ScriptHandler.loadScript(path, 'song');
			if (inst != null)
			{
				inst.set('NoteTypeManager', NoteTypeManager);
				inst.set('typeName', typeName);
				inst.set('typeConfig', getConfig(typeName));
			}
		}
		_scripts.set(typeName, inst);
		return inst;
	}

	// ─── SCRIPTS LUA ─────────────────────────────────────────────────────────

	#if (LUA_ALLOWED && linc_luajit)
	public static function getLuaScript(typeName:String):Null<RuleScriptInstance>
	{
		if (!isCustomType(typeName)) return null;
		if (_luaScripts.exists(typeName)) return _luaScripts.get(typeName);

		final path = _findScriptPath(typeName, true);
		var inst:Null<RuleScriptInstance> = null;
		if (path != null)
		{
			inst = new RuleScriptInstance(typeName, path);
			inst.loadFile(path);
			inst.set('typeName', typeName);
			inst.set('typeConfig', getConfig(typeName));
		}
		_luaScripts.set(typeName, inst);
		return inst;
	}
	#end

	static function _findScriptPath(typeName:String, lua:Bool):Null<String>
	{
		#if sys
		final exts  = lua ? ['.lua'] : ['.hx', '.hscript'];
		final names = [typeName, 'script', 'noteType'];

		if (mods.ModManager.isActive())
		{
			final d = '${mods.ModManager.modRoot()}/notes/custom/$typeName';
			for (ext in exts)
				for (name in names)
					if (FileSystem.exists('$d/$name$ext')) return '$d/$name$ext';
		}
		final d = 'assets/notes/custom/$typeName';
		for (ext in exts)
			for (name in names)
				if (FileSystem.exists('$d/$name$ext')) return '$d/$name$ext';
		#end
		return null;
	}

	// ─── FRAMES / TEXTURAS ───────────────────────────────────────────────────

	/** Atlas de nota (cabeza) para este noteType. null = usar skin activa. */
	public static function getFrames(typeName:String):Null<FlxAtlasFrames>
	{
		if (!isCustomType(typeName)) return null;
		if (_frames.exists(typeName)) return _frames.get(typeName);
		final f = _loadAtlas(typeName, false);
		_frames.set(typeName, f);
		return f;
	}

	/**
	 * Atlas de sustain (hold pieces + tail) para este noteType.
	 * null = usar textura de sustain de la noteskin activa.
	 */
	public static function getHoldFrames(typeName:String):Null<FlxAtlasFrames>
	{
		if (!isCustomType(typeName)) return null;
		if (_holdFrames.exists(typeName)) return _holdFrames.get(typeName);
		final f = _loadAtlas(typeName, true);
		_holdFrames.set(typeName, f);
		return f;
	}

	/**
	 * Nombre del splash skin para los hit splashes de este noteType.
	 * null = usar el splash activo del jugador.
	 */
	public static function getSplashName(typeName:String):Null<String>
	{
		final cfg = getConfig(typeName);
		return cfg != null ? cfg.splash : null;
	}

	/**
	 * Nombre del hold cover (hold splash) para este noteType.
	 * Prioridad: config.holdSplash → config.splash → null.
	 * Si el splash elegido no tiene holdCover, NoteSkinSystem.getHoldCoverTexture
	 * cae automáticamente al Default — no hace falta ninguna lógica extra aquí.
	 */
	public static function getHoldSplashName(typeName:String):Null<String>
	{
		final cfg = getConfig(typeName);
		if (cfg == null) return null;
		if (cfg.holdSplash != null) return cfg.holdSplash;
		return cfg.splash; // reutilizar splash como holdSplash
	}

	static function _loadAtlas(typeName:String, hold:Bool):Null<FlxAtlasFrames>
	{
		#if sys
		// 1. Intentar con sustainTexture del config (solo para hold)
		if (hold)
		{
			final cfg = _loadConfig(typeName);
			if (cfg != null && cfg.sustainTexture != null)
			{
				final dirs:Array<String> = [];
				if (mods.ModManager.isActive())
					dirs.push('${mods.ModManager.modRoot()}/notes/custom/$typeName');
				dirs.push('assets/notes/custom/$typeName');

				for (d in dirs)
				{
					final relPng = '$d/${cfg.sustainTexture}.png';
					final relXml = '$d/${cfg.sustainTexture}.xml';
					if (FileSystem.exists(relPng) && FileSystem.exists(relXml))
					{
						try
						{
							final bmp = openfl.display.BitmapData.fromImage(
								lime.graphics.Image.fromBytes(File.getBytes(relPng)));
							return FlxAtlasFrames.fromSparrow(bmp, File.getContent(relXml));
						}
						catch (e:Dynamic) { trace('[NoteTypeManager] sustainTexture error ($typeName): $e'); }
					}
				}
				// Path absoluto
				final absPng = cfg.sustainTexture + '.png';
				final absXml = cfg.sustainTexture + '.xml';
				if (FileSystem.exists(absPng) && FileSystem.exists(absXml))
				{
					try
					{
						final bmp = openfl.display.BitmapData.fromImage(
							lime.graphics.Image.fromBytes(File.getBytes(absPng)));
						return FlxAtlasFrames.fromSparrow(bmp, File.getContent(absXml));
					}
					catch (e:Dynamic) {}
				}
			}
		}

		// 2. Convención de nombre
		final suffixes = hold
			? ['${typeName}_hold', '${typeName}Hold', 'hold']
			: [typeName, 'note'];

		final dirs:Array<String> = [];
		if (mods.ModManager.isActive())
			dirs.push('${mods.ModManager.modRoot()}/notes/custom/$typeName');
		dirs.push('assets/notes/custom/$typeName');

		for (d in dirs)
			for (s in suffixes)
			{
				final png = '$d/$s.png';
				final xml = '$d/$s.xml';
				if (!FileSystem.exists(png) || !FileSystem.exists(xml)) continue;
				try
				{
					final bmp = openfl.display.BitmapData.fromImage(
						lime.graphics.Image.fromBytes(File.getBytes(png)));
					return FlxAtlasFrames.fromSparrow(bmp, File.getContent(xml));
				}
				catch (e:Dynamic) { trace('[NoteTypeManager] Atlas error ($typeName, hold=$hold): $e'); }
			}
		#end
		return null;
	}

	// ─── HELPERS ─────────────────────────────────────────────────────────────

	public static inline function isCustomType(t:String):Bool
		return t != null && t != '' && t != 'normal';

	/** Llama una función en el script HScript y/o Lua del tipo. */
	static function _call(typeName:String, fn:String, args:Array<Dynamic>):Dynamic
	{
		var result:Dynamic = null;

		#if HSCRIPT_ALLOWED
		final s = getScript(typeName);
		if (s != null) result = s.call(fn, args);
		#end

		#if (LUA_ALLOWED && linc_luajit)
		final lua = getLuaScript(typeName);
		if (lua != null)
		{
			final r = lua.call(fn, args);
			if (r != null) result = r;
		}
		#end

		return result;
	}

	// ─── CALLBACKS ───────────────────────────────────────────────────────────

	public static function onNoteSpawn(note:Note):Void
	{
		if (!isCustomType(note.noteType)) return;

		// Textura de nota cabeza custom
		final f = getFrames(note.noteType);
		if (f != null)
		{
			note.frames = f;
			note.setupTypeAnimations();
		}

		// Color tint desde config
		final cfg = getConfig(note.noteType);
		if (cfg != null && cfg.color != null)
			note.color = cfg.color;

		_call(note.noteType, 'onSpawn', [note]);
	}

	public static function onPlayerHit(note:Note, game:Dynamic):Bool
	{
		if (!isCustomType(note.noteType)) return false;
		final cfg = getConfig(note.noteType);
		if (cfg != null && cfg.ignoreScore) return true;
		return _call(note.noteType, 'onPlayerHit', [note, game]) == true;
	}

	public static function onPlayerHitPost(note:Note, game:Dynamic):Void
	{
		if (!isCustomType(note.noteType)) return;
		_call(note.noteType, 'onPlayerHitPost', [note, game]);
	}

	public static function onCPUHit(note:Note, game:Dynamic):Void
	{
		if (!isCustomType(note.noteType)) return;
		final cfg = getConfig(note.noteType);
		if (cfg != null && cfg.noCPUHit) return;
		_call(note.noteType, 'onCPUHit', [note, game]);
	}

	public static function onMiss(note:Note, game:Dynamic):Bool
	{
		if (!isCustomType(note.noteType)) return false;
		final cfg = getConfig(note.noteType);
		if (cfg != null && cfg.ignoreMiss) return true;
		return _call(note.noteType, 'onMiss', [note, game]) == true;
	}
}

// ─── Typedef ─────────────────────────────────────────────────────────────────

typedef NoteTypeConfig =
{
	var ignoreMiss:Bool;
	var ignoreScore:Bool;
	var noCPUHit:Bool;
	/** Splash skin para hit splashes. null = usar el del jugador. */
	var ?splash:Null<String>;
	/**
	 * Hold cover skin. null = usar splash (o Default si splash no tiene holdCover).
	 * El fallback a Default ocurre en NoteSkinSystem.getHoldCoverTexture — sin código extra aquí.
	 */
	var ?holdSplash:Null<String>;
	/** Path a textura de sustain (sin ext). Relativo a la carpeta del type o absoluto. */
	var ?sustainTexture:Null<String>;
	/** Color tint ARGB. null = sin tint. */
	var ?color:Null<Int>;
}
