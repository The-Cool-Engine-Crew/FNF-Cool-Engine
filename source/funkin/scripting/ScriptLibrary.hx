package funkin.scripting;

#if HSCRIPT_ALLOWED
import hscript.Parser;
import funkin.scripting.interp.FunkinInterp;
#end
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/**
 * ScriptLibrary — sistema de librerías HScript puras para addons y mods.
 *
 * Permite escribir código Haxe interpretado reutilizable sin compilar nada.
 * Una librería es un archivo .hx normal cuyas variables/funciones del scope
 * raíz quedan disponibles como "exports" al llamar require().
 *
 * ─── Estructura de carpetas ───────────────────────────────────────────────────
 *
 *   addons/<id>/libs/MiLib.hx          → librería exclusiva de ese addon
 *   mods/<id>/libs/MiLib.hx            → librería exclusiva de ese mod
 *   assets/data/libs/MiLib.hx          → librería base del engine
 *
 * ─── Uso desde cualquier script .hx ──────────────────────────────────────────
 *
 *   // Carga la librería y obtiene sus exports:
 *   var MiLib = require('MiLib');
 *   MiLib.saludar('Mundo');
 *
 *   // Subcarpetas:
 *   var Utils = require('utils/StringUtils');
 *
 * ─── Escribir una librería ────────────────────────────────────────────────────
 *
 *   // En addons/my-addon/libs/MiLib.hx
 *   // ── Toda variable/función de nivel raíz es un "export" ──
 *
 *   var VERSION = '1.0.0';
 *
 *   function saludar(nombre) {
 *       trace('Hola, ' + nombre + '!');
 *   }
 *
 *   var miConfig = { velocidad: 1.5, color: 0xFF0000 };
 *
 *   // Las libs tienen acceso al ScriptAPI completo (FlxG, FlxSprite, etc.)
 *   function crearSprite(x, y) {
 *       var sp = new FlxSprite(x, y);
 *       return sp;
 *   }
 *
 *   // También puedes hacer require() de otras libs dentro de una lib:
 *   var Otra = require('OtraLib');
 *   function usarOtra() Otra.algo();
 *
 * ─── En addon.json ────────────────────────────────────────────────────────────
 *
 *   {
 *     "id": "my-addon",
 *     "libs": ["MiLib", "utils/StringUtils"]   // opcional: lista explícita
 *     // Si "libs" se omite, se auto-escanea la carpeta libs/ del addon
 *   }
 *
 * ─── Caché ────────────────────────────────────────────────────────────────────
 *
 *   Las librerías se ejecutan UNA SOLA VEZ y quedan en caché por ruta absoluta.
 *   Al cambiar de mod (AddonManager.onModSwitch / ScriptAPI) se limpia la caché.
 *   Usar clearCache() o clearCacheForDir() para invalidar manualmente.
 */
class ScriptLibrary
{
	// ── Caché: ruta absoluta → exports Dynamic ────────────────────────────────
	static var _cache:Map<String, Dynamic> = new Map();

	// ── Extensiones buscadas en orden ─────────────────────────────────────────
	static final EXTS = ['.hx', '.hscript', ''];

	// ── Directorios base del engine ───────────────────────────────────────────
	/** Directorio de librerías base (engine). Buscado siempre como fallback. */
	public static final BASE_LIBS = 'assets/data/libs';

	// ─────────────────────────────────────────────────────────────────────────
	// API pública
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Carga `name` como librería desde `searchDirs` (en orden).
	 * Retorna un objeto anónimo con todos los símbolos exportados por la lib,
	 * o `null` si no se encontró o hubo un error.
	 *
	 * @param name        Nombre de la lib, con o sin extensión.
	 *                    Puede incluir subcarpeta: 'utils/Math2'.
	 * @param searchDirs  Directorios donde buscar (en orden de prioridad).
	 *                    BASE_LIBS se añade automáticamente al final.
	 * @param context     Interp del script llamante — hereda las variables del
	 *                    ScriptAPI para que la lib pueda usar FlxG, etc.
	 *                    Si null, se expone el ScriptAPI en un interp fresco.
	 * @param forceReload Si true, ignora caché y re-ejecuta el archivo.
	 */
	#if HSCRIPT_ALLOWED
	public static function require(
		name:String,
		searchDirs:Array<String>,
		?context:FunkinInterp,
		forceReload:Bool = false
	):Dynamic
	{
		#if sys
		var resolvedPath = _resolve(name, searchDirs);
		if (resolvedPath == null)
		{
			trace('[ScriptLibrary] require("$name") — no encontrado en: ${searchDirs.join(", ")}');
			return null;
		}
		return _load(resolvedPath, context, forceReload);
		#else
		return null;
		#end
	}
	#end

	/**
	 * Carga directamente desde una ruta absoluta conocida.
	 * Útil para que AddonEntry pre-cargue todas sus libs de una vez.
	 */
	#if HSCRIPT_ALLOWED
	public static function loadAbsolute(
		absPath:String,
		?context:FunkinInterp,
		forceReload:Bool = false
	):Dynamic
	{
		#if sys
		if (!FileSystem.exists(absPath))
		{
			trace('[ScriptLibrary] loadAbsolute: no existe "$absPath"');
			return null;
		}
		return _load(absPath, context, forceReload);
		#else
		return null;
		#end
	}
	#end

	// ── Gestión de caché ──────────────────────────────────────────────────────

	/** Limpia TODO el caché. Llamar al cambiar de mod. */
	public static function clearCache():Void
		_cache.clear();

	/**
	 * Limpia sólo las entradas cuya ruta empieza por `dir`.
	 * Útil para invalidar sólo las libs de un mod concreto al desactivarlo.
	 */
	public static function clearCacheForDir(dir:String):Void
	{
		var toRemove = [for (k in _cache.keys()) if (k.startsWith(dir)) k];
		for (k in toRemove)
			_cache.remove(k);
	}

	/** Devuelve true si la lib en `absPath` ya está en caché. */
	public static inline function isCached(absPath:String):Bool
		return _cache.exists(absPath);

	// ─────────────────────────────────────────────────────────────────────────
	// Internos
	// ─────────────────────────────────────────────────────────────────────────

	#if (HSCRIPT_ALLOWED && sys)
	/**
	 * Carga, ejecuta y cachea una librería desde `absPath`.
	 * Devuelve las variables NUEVAS que el archivo definió (= exports).
	 */
	static function _load(
		absPath:String,
		?context:FunkinInterp,
		forceReload:Bool
	):Dynamic
	{
		if (!forceReload && _cache.exists(absPath))
			return _cache.get(absPath);

		try
		{
			final src = File.getContent(absPath);

			// ── Crear intérprete fresco ────────────────────────────────────
			var libInterp = new FunkinInterp();
			try { Reflect.setField(libInterp, 'allowMetadata', true); } catch(_) {}

			// ── Snapshot ANTES de exponer el API ──────────────────────────
			// (el FunkinInterp puede tener vars internas ya — las excluimos)
			final preKeys = _keySet(libInterp.variables);

			// ── Exponer ScriptAPI (o copiar del contexto) ──────────────────
			if (context != null)
			{
				// Copiar TODAS las variables del contexto padre para que la
				// lib tenga acceso al mismo ScriptAPI que el script llamante.
				for (k in context.variables.keys())
					libInterp.variables.set(k, context.variables.get(k));
			}
			else
			{
				ScriptAPI.expose(libInterp);
			}

			// ── Snapshot DESPUÉS de exponer el API (= vars del framework) ─
			final apiKeys = _keySet(libInterp.variables);

			// ── Inyectar require() anidado en el mismo directorio ─────────
			final libDir = haxe.io.Path.directory(absPath);
			_injectRequire(libInterp, [libDir, BASE_LIBS], context);

			// ── Parsear y ejecutar ─────────────────────────────────────────
			final parser = ScriptHandler.parser; // parser compartido del engine
			final src2    = ScriptHandler.processImports(src, libInterp);
			final ast     = parser.parseString(src2, haxe.io.Path.withoutDirectory(absPath));
			libInterp.execute(ast);

			// ── Recoger exports: sólo lo que el archivo AÑADIÓ ────────────
			final exports:Dynamic = {};
			for (key in libInterp.variables.keys())
			{
				if (!apiKeys.exists(key) && !preKeys.exists(key))
					Reflect.setField(exports, key, libInterp.variables.get(key));
			}

			_cache.set(absPath, exports);
			trace('[ScriptLibrary] Cargada: ${haxe.io.Path.withoutDirectory(absPath)} → ${Reflect.fields(exports).join(", ")}');
			return exports;
		}
		catch (e:Dynamic)
		{
			trace('[ScriptLibrary] Error en "$absPath": $e');
			return null;
		}
	}

	/**
	 * Busca `name` en los directorios dados probando varias extensiones.
	 * BASE_LIBS se añade siempre como último directorio de búsqueda.
	 * Devuelve la primera ruta absoluta que exista, o null.
	 */
	static function _resolve(name:String, searchDirs:Array<String>):Null<String>
	{
		final dirs = searchDirs.copy();
		if (dirs.indexOf(BASE_LIBS) == -1)
			dirs.push(BASE_LIBS);

		for (dir in dirs)
		{
			if (dir == null || dir == '') continue;
			for (ext in EXTS)
			{
				final candidate = '$dir/$name$ext';
				if (FileSystem.exists(candidate) && !FileSystem.isDirectory(candidate))
					return candidate;
			}
		}
		return null;
	}

	/**
	 * Inyecta `require(name)` en `targetInterp` con los `dirs` dados.
	 * El contexto padre se pasa opcionalmente para que libs anidadas
	 * también hereden el mismo ScriptAPI.
	 */
	static function _injectRequire(
		targetInterp:FunkinInterp,
		dirs:Array<String>,
		?parentCtx:FunkinInterp
	):Void
	{
		targetInterp.variables.set('require', function(name:String, ?forceReload:Bool):Dynamic {
			return require(name, dirs, parentCtx ?? targetInterp, forceReload ?? false);
		});
	}

	/** Copia las claves de un StringMap a un Map<String,Bool>. */
	static inline function _keySet(vars:haxe.ds.StringMap<Dynamic>):Map<String, Bool>
	{
		final s:Map<String, Bool> = new Map();
		for (k in vars.keys()) s.set(k, true);
		return s;
	}
	#end
}
