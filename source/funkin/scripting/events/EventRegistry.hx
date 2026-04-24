package funkin.scripting.events;

#if sys
import sys.FileSystem;
import sys.io.File;
#end
import haxe.Json;
import mods.ModManager;

import funkin.scripting.events.EventDefinition;
import funkin.scripting.events.EventInfoSystem;
import funkin.scripting.events.EventInfoSystem.EventParamDef;
import funkin.scripting.events.EventInfoSystem.EventParamType;

using StringTools;

/**
 * EventRegistry — Registro unificado de eventos del engine.
 *
 * Reemplaza y extiende EventInfoSystem con:
 *  • Estructura de carpetas por contexto (chart, cutscene, playstate, modchart, global)
 *  • Soporte de carpeta-por-evento y archivos planos
 *  • Descripción y aliases por evento
 *  • Descubrimiento automático de handlers .hx y .lua
 *  • Acceso filtrado por contexto para cada editor
 *
 * ─── Estructura de carpetas soportada ────────────────────────────────────────
 *
 *  [modRoot|assets]/data/events/
 *    chart/
 *      Camera Follow.json     ← config UI (nombre del archivo = nombre del evento)
 *      Camera Follow.hx       ← handler HScript (mismo nombre base)
 *      Camera Follow.lua      ← handler Lua (mismo nombre base)
 *      My Event/              ← formato carpeta-por-evento
 *        event.json           ← config (o config.json)
 *        handler.hx           ← handler HScript (o My Event.hx)
 *        handler.lua          ← handler Lua (o My Event.lua)
 *    cutscene/
 *      ...
 *    playstate/
 *      ...
 *    modchart/
 *      ...
 *    global/
 *      ...
 *    (raíz)                   ← backward compat: tratados como contexto "chart"
 *      OldEvent.json
 *      OldEvent.hx
 *
 * ─── Prioridad de carga ───────────────────────────────────────────────────────
 *
 *  1. Built-ins del engine (hardcodeados en EventInfoSystem._builtins)
 *  2. assets/data/events/  (engine base)
 *  3. mods/shared/data/events/  (si existe, shared entre mods)
 *  4. mods/{activeMod}/data/events/  (mod activo, máxima prioridad)
 *
 * ─── Contextos ────────────────────────────────────────────────────────────────
 *
 *   "chart"     → Chart Editor + gameplay dispatch
 *   "cutscene"  → SpriteCutscene editor + cutscene dispatch
 *   "playstate" → PlayState Editor
 *   "modchart"  → Modchart Editor
 *   "global"    → visible y activo en todos los contextos
 */
class EventRegistry
{
	// ── Storage ───────────────────────────────────────────────────────────────

	/** Todas las definiciones indexadas por nombre canónico. */
	static var _defs:Map<String, EventDefinition> = new Map();

	/** Mapa alias → nombre canónico. */
	static var _aliasMap:Map<String, String> = new Map();

	/** Nombres ordenados para UI. */
	static var _ordered:Array<String> = [];

	// ── Contextos válidos ────────────────────────────────────────────────────

	public static final CONTEXTS = ['chart', 'cutscene', 'playstate', 'modchart', 'global'];

	// ── API principal ─────────────────────────────────────────────────────────

	/**
	 * Recarga todas las definiciones desde los JSONs + built-ins.
	 * Llamar al inicio o al cambiar de mod.
	 * También sincroniza EventInfoSystem para compatibilidad con el ChartEditor.
	 */
	public static function reload():Void
	{
		_defs.clear();
		_aliasMap.clear();
		_ordered = [];

		// 1. Built-ins de EventInfoSystem (hardcodeados)
		EventInfoSystem.reload();
		for (name in EventInfoSystem.eventList)
		{
			final params = EventInfoSystem.eventParams.get(name) ?? [];
			final color  = EventInfoSystem.eventColors.get(name)  ?? 0xFFAAAAAA;
			_register({
				name:        name,
				description: null,
				color:       color,
				contexts:    ['chart'],
				aliases:     [],
				params:      params,
				hscriptPath: null,
				luaPath:     null,
				sourceDir:   null
			});
		}

		// 2. Carpetas de eventos del engine
		_loadRoot('assets/data/events');
		// Ruta alternativa sin prefijo assets/ (permite poner eventos en data/events/chart/)
		_loadRoot('data/events');

		// 3. Carpetas de eventos del mod activo
		#if sys
		if (ModManager.isActive())
		{
			final r = ModManager.modRoot();
			if (r != null)
			{
				_loadRoot('$r/data/events');
				_loadRoot('$r/assets/data/events');
			}
		}
		// También buscar en todos los mods instalados habilitados
		for (mod in ModManager.installedMods)
		{
			if (!ModManager.isEnabled(mod.id)) continue;
			final r = '${ModManager.MODS_FOLDER}/${mod.id}';
			_loadRoot('$r/data/events');
			_loadRoot('$r/assets/data/events');
		}
		#end

		// 4. Sincronizar de vuelta a EventInfoSystem para que el ChartEditor lo vea
		_syncToEventInfoSystem();

		trace('[EventRegistry] ${_ordered.length} events registered (${_defs.keys().hasNext() ? Lambda.count(_defs) : 0} unique).');
	}

	/**
	 * Devuelve todas las definiciones de un contexto dado.
	 * Los eventos de contexto "global" se incluyen siempre.
	 */
	public static function getByContext(context:String):Array<EventDefinition>
	{
		final out:Array<EventDefinition> = [];
		for (name in _ordered)
		{
			final def = _defs.get(name);
			if (def == null) continue;
			if (def.contexts.contains(context) || def.contexts.contains('global'))
				out.push(def);
		}
		return out;
	}

	/** Devuelve todos los nombres de eventos de un contexto (para dropdowns de editor). */
	public static function getNamesForContext(context:String):Array<String>
		return getByContext(context).map(d -> d.name);

	/** Devuelve la definición de un evento por nombre o alias. */
	public static function get(name:String):Null<EventDefinition>
	{
		if (_defs.exists(name)) return _defs.get(name);
		final canonical = _aliasMap.get(name.toLowerCase());
		return canonical != null ? _defs.get(canonical) : null;
	}

	/** Resuelve un alias/nombre al nombre canónico. Null si no existe. */
	public static function resolveAlias(name:String):Null<String>
	{
		if (_defs.exists(name)) return name;
		return _aliasMap.get(name.toLowerCase());
	}

	/** Registra un evento manualmente (útil desde scripts). */
	public static function register(def:EventDefinition):Void
	{
		_register(def);
		_syncToEventInfoSystem();
	}

	/** Lista ordenada de todos los nombres de eventos (para UI). */
	public static var eventList(get, never):Array<String>;
	static inline function get_eventList() return _ordered.copy();

	// ── Carga de carpetas ─────────────────────────────────────────────────────

	/**
	 * Carga el árbol completo de una raíz de eventos:
	 *   root/chart/, root/cutscene/, root/playstate/, root/modchart/, root/global/
	 *   root/ (raíz, backward-compat → contexto "chart")
	 */
	static function _loadRoot(root:String):Void
	{
		#if sys
		if (!FileSystem.exists(root) || !FileSystem.isDirectory(root)) return;

		// Subcarpetas de contexto
		for (ctx in CONTEXTS)
		{
			final dir = '$root/$ctx';
			if (FileSystem.exists(dir) && FileSystem.isDirectory(dir))
				_loadContextDir(dir, ctx);
		}

		// Raíz directa (backward compat → "chart")
		_loadContextDir(root, 'chart', true);
		#end
	}

	/**
	 * Carga todos los eventos de una carpeta de contexto.
	 * Soporta archivos planos Y subcarpetas por evento.
	 *
	 * @param dir          Carpeta a escanear.
	 * @param context      Contexto de los eventos encontrados.
	 * @param skipSubdirs  Si true, ignorar subdirectorios (para evitar recursión).
	 */
	static function _loadContextDir(dir:String, context:String, skipSubdirs:Bool = false):Void
	{
		#if sys
		if (!FileSystem.exists(dir) || !FileSystem.isDirectory(dir)) return;

		final entries = FileSystem.readDirectory(dir);

		// ── Primero: carpetas por evento (Formato B) ──────────────────────────
		if (!skipSubdirs)
		{
			for (entry in entries)
			{
				final fullPath = '$dir/$entry';
				if (!FileSystem.isDirectory(fullPath)) continue;
				// Ignorar subcarpetas de contexto (ya procesadas en _loadRoot)
				if (CONTEXTS.contains(entry.toLowerCase())) continue;
				_loadEventFolder(fullPath, entry, context);
			}
		}

		// ── Segundo: archivos planos (Formato A) ──────────────────────────────
		// Agrupar por nombre base (sin extensión)
		final byBase:Map<String, { json:Null<String>, hx:Null<String>, lua:Null<String> }> = new Map();

		for (entry in entries)
		{
			final fullPath = '$dir/$entry';
			if (FileSystem.isDirectory(fullPath)) continue;

			final entryLow = entry.toLowerCase();
			// Ignorar archivos que no sean relevantes
			if (!entryLow.endsWith('.json') && !entryLow.endsWith('.hx')
				&& !entryLow.endsWith('.hscript') && !entryLow.endsWith('.lua'))
				continue;

			// Nombre base sin extensión
			final base = _stripExt(entry);

			// Ignorar archivos con nombre reservado (no son eventos)
			if (base.toLowerCase() == 'event' || base.toLowerCase() == 'config'
				|| base.toLowerCase() == 'handler') continue;

			if (!byBase.exists(base))
				byBase.set(base, { json: null, hx: null, lua: null });
			final group = byBase.get(base);

			if (entryLow.endsWith('.json'))
				group.json = fullPath;
			else if (entryLow.endsWith('.hx') || entryLow.endsWith('.hscript'))
				group.hx = fullPath;
			else if (entryLow.endsWith('.lua'))
				group.lua = fullPath;
		}

		// Crear definición para cada grupo de archivos encontrado
		for (eventName => group in byBase)
		{
			// Al menos debe haber un JSON o un script para registrar el evento
			if (group.json == null && group.hx == null && group.lua == null) continue;

			var def = _parseJsonDef(group.json, eventName, context, dir);
			def.hscriptPath = group.hx;
			def.luaPath     = group.lua;
			def.sourceDir   = dir;

			// Añadir el contexto de la carpeta si el JSON no especificó ninguno
			if (def.contexts.length == 0) def.contexts = [context];

			_register(def);
		}
		#end
	}

	/**
	 * Carga un evento desde una carpeta dedicada (Formato B).
	 * Busca event.json / config.json y handler.hx / EventName.hx, etc.
	 */
	static function _loadEventFolder(folderPath:String, eventName:String, context:String):Void
	{
		#if sys
		final entries = FileSystem.readDirectory(folderPath);

		// Localizar archivos dentro de la carpeta
		var jsonPath:Null<String>  = null;
		var hxPath:Null<String>    = null;
		var luaPath:Null<String>   = null;

		for (entry in entries)
		{
			final full    = '$folderPath/$entry';
			final entryLow = entry.toLowerCase();

			if (entryLow == 'event.json' || entryLow == 'config.json')
				jsonPath = full;
			else if (entryLow == 'handler.hx' || entryLow == 'handler.hscript'
				|| entryLow == (eventName.toLowerCase() + '.hx')
				|| entryLow == (eventName.toLowerCase() + '.hscript'))
				hxPath = full;
			else if (entryLow == 'handler.lua'
				|| entryLow == (eventName.toLowerCase() + '.lua'))
				luaPath = full;
		}

		// Si no encontramos nada, saltamos
		if (jsonPath == null && hxPath == null && luaPath == null) return;

		var def     = _parseJsonDef(jsonPath, eventName, context, folderPath);
		def.hscriptPath = hxPath;
		def.luaPath     = luaPath;
		def.sourceDir   = folderPath;
		if (def.contexts.length == 0) def.contexts = [context];

		_register(def);
		#end
	}

	// ── Parseo de JSON ────────────────────────────────────────────────────────

	static function _parseJsonDef(jsonPath:Null<String>, fallbackName:String,
		fallbackContext:String, sourceDir:String):EventDefinition
	{
		var name        = fallbackName;
		var description:Null<String> = null;
		var color       = 0xFFAAAAAA;
		var contexts    = [fallbackContext];
		var aliases     = [];
		var params:Array<EventParamDef> = [];

		#if sys
		if (jsonPath != null && FileSystem.exists(jsonPath))
		{
			try
			{
				final raw:Dynamic = Json.parse(File.getContent(jsonPath));

				if (raw.name        != null) name        = Std.string(raw.name);
				if (raw.description != null) description = Std.string(raw.description);
				if (raw.color       != null) color       = _parseColor(Std.string(raw.color));

				// context: string o array
				if (raw.context != null)
				{
					if (Std.isOfType(raw.context, String))
						contexts = [Std.string(raw.context)];
					else if (Std.isOfType(raw.context, Array))
						contexts = [for (c in (cast raw.context:Array<Dynamic>)) Std.string(c)];
				}
				else if (raw.contexts != null)
				{
					if (Std.isOfType(raw.contexts, Array))
						contexts = [for (c in (cast raw.contexts:Array<Dynamic>)) Std.string(c)];
				}

				// aliases
				if (raw.aliases != null && Std.isOfType(raw.aliases, Array))
					aliases = [for (a in (cast raw.aliases:Array<Dynamic>)) Std.string(a)];

				// params — reutilizar el parser de EventInfoSystem
				if (raw.params != null && Std.isOfType(raw.params, Array))
				{
					final rawParams:Array<Dynamic> = cast raw.params;
					for (p in rawParams)
					{
						if (p == null || p.name == null) continue;
						final paramDesc:Null<String> = p.description != null ? Std.string(p.description) : null;
						params.push({
							name:        Std.string(p.name),
							type:        EventInfoSystem.parseParamType(Std.string(p.type ?? 'String')),
							defValue:    p.defaultValue != null ? Std.string(p.defaultValue) : '',
							description: paramDesc
						});
					}
				}
			}
			catch (e:Dynamic) trace('[EventRegistry] Error parseando JSON "$jsonPath": $e');
		}
		#end

		return {
			name:        name,
			description: description,
			color:       color,
			contexts:    contexts,
			aliases:     aliases,
			params:      params,
			hscriptPath: null,
			luaPath:     null,
			sourceDir:   sourceDir
		};
	}

	// ── Registro ──────────────────────────────────────────────────────────────

	static function _register(def:EventDefinition):Void
	{
		final name = def.name;

		// Si ya existe, fusionar: la nueva tiene prioridad en params/color/desc
		// pero conservar las rutas de scripts si la nueva no las especifica
		if (_defs.exists(name))
		{
			final existing = _defs.get(name);
			def.hscriptPath = def.hscriptPath ?? existing.hscriptPath;
			def.luaPath     = def.luaPath     ?? existing.luaPath;
			// Añadir contextos sin duplicar
			for (ctx in existing.contexts)
				if (!def.contexts.contains(ctx)) def.contexts.push(ctx);
		}
		else
		{
			_ordered.push(name);
		}

		_defs.set(name, def);

		// Registrar aliases (en lowercase para búsqueda case-insensitive)
		_aliasMap.set(name.toLowerCase(), name);
		for (alias in def.aliases)
			_aliasMap.set(alias.toLowerCase(), name);
	}

	/**
	 * Sincroniza las definiciones de contexto "chart" a EventInfoSystem
	 * para que el ChartEditor (EventsSidebar) y el ChartEditor legacy puedan
	 * seguir leyendo `EventInfoSystem.eventList` y `eventParams`.
	 */
	static function _syncToEventInfoSystem():Void
	{
		// Reconstruir las listas del EventInfoSystem solo con eventos de chart/global
		EventInfoSystem.eventList   = [];
		EventInfoSystem.eventParams = new Map();
		EventInfoSystem.eventColors = new Map();

		for (name in _ordered)
		{
			final def = _defs.get(name);
			if (def == null) continue;
			if (!def.contexts.contains('chart') && !def.contexts.contains('global')) continue;

			EventInfoSystem.eventList.push(name);
			EventInfoSystem.eventParams.set(name, def.params);
			EventInfoSystem.eventColors.set(name, def.color);
		}
	}

	// ── Helpers ───────────────────────────────────────────────────────────────

	static function _stripExt(filename:String):String
	{
		final dot = filename.lastIndexOf('.');
		return dot >= 0 ? filename.substr(0, dot) : filename;
	}

	static function _parseColor(s:String):Int
	{
		s = s.replace('#', '').replace('0x', '').replace('0X', '');
		// Asegurar alpha
		if (s.length == 6) s = 'FF$s';
		try return Std.parseInt('0x$s') catch(_) return 0xFFAAAAAA;
	}
}
