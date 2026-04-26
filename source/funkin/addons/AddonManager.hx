package funkin.addons;

#if sys
import sys.FileSystem;
import sys.io.File;
#end
import haxe.Json;
import funkin.scripting.HScriptInstance;
import funkin.scripting.ScriptLibrary;
import mods.ModManager;

using StringTools;

/**
 * AddonManager — Gestor de addons del engine.
 *
 * ─── Qué es un addon vs un mod ───────────────────────────────────────────────
 *
 *  MOD:    añade contenido (canciones, personajes, stages, skins, scripts).
 *          Vive en mods/<id>/. No puede cambiar el comportamiento del engine.
 *
 *  ADDON:  extiende el engine mismo. Puede:
 *          • Registrar nuevos sistemas accesibles desde scripts de mods.
 *          • Interceptar hooks del gameplay (onNoteHit, onBeat, onUpdate…).
 *          • Exponer nuevas APIs al ScriptAPI de HScript.
 *          • Cambiar mecánicas de juego globales.
 *          • Ser activados/desactivados independientemente de los mods.
 *
 *  Vive en addons/<id>/addon.json.
 *
 * ─── Carpeta esperada ────────────────────────────────────────────────────────
 *
 *   addons/
 *   └── my-addon/
 *       ├── addon.json        ← metadatos y declaración de hooks/sistemas
 *       ├── scripts/
 *       │   ├── onNoteHit.hx  ← script llamado en cada nota acertada
 *       │   ├── onMissNote.hx
 *       │   ├── onSongStart.hx
 *       │   ├── exposeAPI.hx  ← expone variables nuevas al ScriptAPI
 *       │   └── onUpdate.hx
 *       └── assets/           ← recursos propios del addon (opcional)
 *           ├── images/
 *           └── data/
 *
 * ─── Flujo de carga ──────────────────────────────────────────────────────────
 *
 *  Main.setupGame()
 *    → AddonManager.init()          ← carga todos los addons habilitados
 *    → AddonManager.callHook('exposeAPI', interp) ← expone APIs a HScript
 *
 *  PlayState.create()
 *    → AddonManager.callHook('onStateCreate', args)
 *  PlayState.update(elapsed)
 *    → AddonManager.callHook('onUpdate', args)
 *  PlayState.onNoteHit(note)
 *    → AddonManager.callHook('onNoteHit', args)
 */
class AddonManager
{
	// ── Constante de carpeta ────────────────────────────────────────────────

	public static inline final ADDONS_FOLDER = 'addons';

	// ── Estado ─────────────────────────────────────────────────────────────

	/** Todos los addons cargados y habilitados, ordenados por priority desc. */
	public static var loadedAddons(default, null):Array<AddonEntry> = [];

	/** Sistemas registrados por los addons. Clave = id de sistema. */
	public static var registeredSystems(default, null):Map<String, Dynamic> = new Map();

	/** Si init() ya se ejecutó. */
	public static var initialized(default, null):Bool = false;

	// ── Init ───────────────────────────────────────────────────────────────

	/**
	 * Escanea la carpeta addons/, carga addon.json de cada uno,
	 * compila sus scripts y los ordena por priority.
	 * Llamar una vez al arrancar desde Main.setupGame().
	 */
	public static function init():Void
	{
		// FIX Bug 8: destroy existing AddonEntry instances before discarding them
		// so their HScriptInstance interpreters are properly freed.
		for (ae in loadedAddons)
			try ae.destroy() catch (_:Dynamic) {}
		loadedAddons    = [];
		registeredSystems = new Map();
		initialized     = true;

		#if sys
		if (!FileSystem.exists(ADDONS_FOLDER) || !FileSystem.isDirectory(ADDONS_FOLDER))
		{
			trace('[AddonManager] Carpeta "addons/" no encontrada — sin addons.');
			return;
		}

		for (entry in FileSystem.readDirectory(ADDONS_FOLDER))
		{
			final path = '$ADDONS_FOLDER/$entry';
			if (!FileSystem.isDirectory(path)) continue;

			final infoPath = '$path/addon.json';
			if (!FileSystem.exists(infoPath)) continue;

			try
			{
				final raw:AddonInfo = cast Json.parse(File.getContent(infoPath));
				if (raw == null) continue;
				if (raw.enabled == false) continue;

				final ae = new AddonEntry(entry, path, raw);
				ae.loadScripts();
				loadedAddons.push(ae);

				trace('[AddonManager] Addon cargado: ${ae.info.id} v${ae.info.version ?? "?"}');
			}
			catch (e:Dynamic)
			{
				trace('[AddonManager] Error cargando addon "$entry": $e');
			}
		}

		// Ordenar por priority desc
		loadedAddons.sort((a, b) -> (b.info.priority ?? 0) - (a.info.priority ?? 0));
		trace('[AddonManager] ${loadedAddons.length} addons cargados.');
		#end

		// ── Fix 5: notificar cambios de mod a los addons ──────────────────────
		// ModManager.onModChanged es un slot único. Lo encadenamos de forma
		// segura: si ya había un listener previo, lo preservamos y lo llamamos
		// después del nuestro (no lo sobreescribimos silenciosamente).
		final _prev = ModManager.onModChanged;
		ModManager.onModChanged = function(newMod:String)
		{
			// 1. Propagar al listener previo si existía
			if (_prev != null)
				try { _prev(newMod); } catch (e:Dynamic) { trace('[AddonManager] onModChanged prev error: $e'); }

			// 2. Notificar a todos los addons cargados.
			//    Los addons pueden usar este hook para limpiar estado propio,
			//    re-registrar sistemas o simplemente ignorarlo si no les afecta.
			broadcastHook('onModSwitch', [newMod]);
			trace('[AddonManager] onModSwitch broadcast → ${loadedAddons.length} addons (mod="${newMod ?? "base"}")');

			// 3. Limpiar caché de librerías del mod anterior.
			//    Las libs del mod nuevo se cargarán frescos al primer require().
			funkin.scripting.ScriptLibrary.clearCacheForDir(mods.ModManager.MODS_FOLDER);
		};
	}

	// ── Hook dispatch ──────────────────────────────────────────────────────

	/**
	 * Llama el hook `hookName` en todos los addons cargados.
	 * Los addons pueden retornar un valor; si alguno retorna != null
	 * ese valor se propaga (el primer non-null "gana").
	 *
	 * @param hookName   nombre del hook ("onNoteHit", "onBeat", etc.)
	 * @param args       argumentos a pasar al script
	 * @return           primer valor no-null retornado por algún addon, o null
	 */
	public static function callHook(hookName:String, args:Array<Dynamic> = null):Dynamic
	{
		if (args == null) args = [];
		for (ae in loadedAddons)
		{
			final result = ae.callHook(hookName, args);
			if (result != null) return result;
		}
		return null;
	}

	/**
	 * Versión "broadcast": llama el hook en todos los addons sin early-exit.
	 * Útil para hooks donde múltiples addons deben responder (onUpdate, onBeat).
	 */
	public static function broadcastHook(hookName:String, args:Array<Dynamic> = null):Void
	{
		if (args == null) args = [];
		for (ae in loadedAddons)
			ae.callHook(hookName, args);
	}

	// ── Sistema API ────────────────────────────────────────────────────────

	/**
	 * Registra un sistema bajo un ID.
	 * Los addons llaman esto desde su script exposeAPI.hx para
	 * poner a disposición de mods nuevas clases/funciones/estados.
	 *
	 *   // En exposeAPI.hx de un addon:
	 *   AddonManager.registerSystem('my3dSystem', {
	 *     createScene: function(w, h) return new Flx3DSprite(0, 0, w, h),
	 *     getCube:     function()     return Flx3DPrimitives.cube()
	 *   });
	 */
	public static function registerSystem(id:String, api:Dynamic):Void
	{
		if (registeredSystems.exists(id))
			trace('[AddonManager] Sobreescribiendo sistema "$id"');
		registeredSystems.set(id, api);
		trace('[AddonManager] Sistema registrado: "$id"');
	}

	/** Devuelve el API de un sistema, o null si no existe. */
	public static inline function getSystem(id:String):Dynamic
		return registeredSystems.get(id);

	/** ¿Está disponible el sistema `id`? */
	public static inline function hasSystem(id:String):Bool
		return registeredSystems.exists(id);

	// ── Exponer API a HScript ──────────────────────────────────────────────

	/**
	 * Expone AddonManager y todos los sistemas registrados al intérprete
	 * HScript. Llamar desde ScriptAPI.expose(interp).
	 */
	#if HSCRIPT_ALLOWED
	public static function exposeToScript(interp:hscript.Interp):Void
	{
		interp.variables.set('AddonManager', AddonManager);
		// Exponer cada sistema registrado directamente
		for (id in registeredSystems.keys())
			interp.variables.set('addon_$id', registeredSystems.get(id));
		// Llamar hook exposeAPI en todos los addons para que registren sus vars
		for (ae in loadedAddons)
			ae.callHook('exposeAPI', [interp]);
	}
	#end

// ── Gestión de librerías de addons (API estática) ─────────────────────────

	/**
	 * Devuelve todos los directorios `libs/` de los addons cargados.
	 * Usado por ScriptAPI para construir el search path global de require().
	 */
	public static function getLibSearchDirs():Array<String>
	{
		// Incluye tanto libs/ locales como .deps/ descargadas de cada addon
		final dirs:Array<String> = [];
		for (ae in loadedAddons) { dirs.push(ae.libsPath); dirs.push(ae.depsPath); }
		return dirs;
	}
}

// ═══════════════════════════════════════════════════════════════════════════════
//  AddonEntry — instancia de addon en memoria
// ═══════════════════════════════════════════════════════════════════════════════

class AddonEntry
{
	public var id    (default, null):String;
	public var path  (default, null):String;
	public var info  (default, null):AddonInfo;

	/** Ruta a la carpeta libs/ de este addon. */
	public var libsPath(default, null):String;

	/** Ruta a la carpeta .deps/ donde se cachean las dependencias descargadas. */
	public var depsPath(default, null):String;

	// Scripts compilados por hook name
	var _scripts:Map<String, HScriptInstance> = new Map();

	// Librerías pre-cargadas: nombre (sin extensión) → exports Dynamic
	var _libs:Map<String, Dynamic> = new Map();

	// Nombres de lib → ruta absoluta (para require() por nombre)
	var _libPaths:Map<String, String> = new Map();

	public function new(id:String, path:String, info:AddonInfo)
	{
		this.id      = id;
		this.path    = path;
		this.info    = info;
		this.libsPath = '$path/libs';
		this.depsPath  = '$path/${funkin.addons.ScriptDependency.DEPS_FOLDER}';
	}

	// ── Carga de librerías ─────────────────────────────────────────────────

	/**
	 * Escanea la carpeta `libs/` del addon y registra todas las librerías.
	 * Si `info.libs` está definido, usa esa lista explícita en su lugar.
	 * Las libs NO se ejecutan aquí — se cargan bajo demanda al primer require().
	 */
	public function discoverLibs():Void
	{
		#if (sys && HSCRIPT_ALLOWED)
		if (info.libs != null)
		{
			// Lista explícita en addon.json → ["MiLib", "utils/Math2"]
			for (libName in info.libs)
			{
				for (ext in ['.hx', '.hscript', ''])
				{
					final candidate = '$libsPath/$libName$ext';
					if (FileSystem.exists(candidate) && !FileSystem.isDirectory(candidate))
					{
						_libPaths.set(libName, candidate);
						trace('[AddonManager] Lib registrada: ${id}::$libName');
						break;
					}
				}
			}
		}
		else if (FileSystem.exists(libsPath) && FileSystem.isDirectory(libsPath))
		{
			// Auto-scan: registra todos los .hx/.hscript de libs/ (recursivo)
			_scanLibDir(libsPath, '');
		}
		#end
	}

	#if (sys && HSCRIPT_ALLOWED)
	/** Recorre `dir` recursivamente registrando archivos .hx/.hscript. */
	function _scanLibDir(dir:String, prefix:String):Void
	{
		for (entry in FileSystem.readDirectory(dir))
		{
			final fullPath = '$dir/$entry';
			final nameWithPrefix = prefix == '' ? entry : '$prefix/$entry';

			if (FileSystem.isDirectory(fullPath))
			{
				_scanLibDir(fullPath, nameWithPrefix);
			}
			else if (entry.endsWith('.hx') || entry.endsWith('.hscript'))
			{
				// Nombre sin extensión: "MiLib", "utils/Math2"
				final libName = nameWithPrefix.substr(0,
					nameWithPrefix.lastIndexOf('.'));
				_libPaths.set(libName, fullPath);
				trace('[AddonManager] Lib descubierta: ${id}::$libName → $fullPath');
			}
		}
	}
	#end

	// ── Carga de scripts ───────────────────────────────────────────────────

	public function loadScripts():Void
	{
		// ── Paso 0: descargar dependencias externas (GitHub / URL) ──────────────
		// Se hace ANTES de discoverLibs() para que los .hx descargados en
		// .deps/ queden disponibles junto con las libs locales.
		if (info.dependencies != null && info.dependencies.length > 0)
			funkin.addons.ScriptDependency.resolveAll(id, path, info.dependencies);

		// Primero descubrir las libs para que estén disponibles
		// en el require() que inyectamos a los scripts.
		discoverLibs();

		#if (sys && HSCRIPT_ALLOWED)
		if (info.hooks == null) return;

		final hooks:Dynamic = info.hooks;
		for (hookName in Reflect.fields(hooks))
		{
			final scriptPath = '$path/${Reflect.field(hooks, hookName)}';
			if (!FileSystem.exists(scriptPath)) continue;

			try
			{
				final inst = new HScriptInstance('${id}::$hookName', scriptPath);
				inst.loadString(File.getContent(scriptPath));
				_exposeDefaults(inst);
				_scripts.set(hookName, inst);
			}
			catch (e:Dynamic)
			{
				trace('[AddonManager] Error compilando ${id}::$hookName: $e');
			}
		}
		#end
	}

	// ── Llamada de hook ────────────────────────────────────────────────────

	public function callHook(hookName:String, args:Array<Dynamic>):Dynamic
	{
		final script = _scripts.get(hookName);
		if (script == null || !script.active) return null;

		try
		{
			return script.call(hookName, args);
		}
		catch (e:Dynamic)
		{
			trace('[AddonManager] Error en hook ${id}::$hookName — $e');
			return null;
		}
	}

	// ── Defaults expuestos a todos los scripts del addon ───────────────────

	function _exposeDefaults(inst:HScriptInstance):Void
	{
		#if HSCRIPT_ALLOWED
		funkin.scripting.ScriptAPI.expose(inst.interp);
		inst.set('AddonManager', AddonManager);
		inst.set('addonId',   id);
		inst.set('addonPath', path);
		inst.set('registerSystem', AddonManager.registerSystem);

		// ── require() para scripts del addon ──────────────────────────────
		// Busca en orden: libs/ del addon → libs/ de otros addons → base.
		_injectRequire(inst);
		#end
	}

	#if HSCRIPT_ALLOWED
	/**
	 * Inyecta la función require(name) en el intérprete del script.
	 * Orden de búsqueda:
	 *   1. Libs registradas de ESTE addon (ya en _libPaths)
	 *   2. ScriptLibrary con search path: [libsPath del addon, libs de otros addons, base]
	 */
	function _injectRequire(inst:HScriptInstance):Void
	{
		// Construir search path dinámico al momento de la llamada:
		//   propio addon primero, luego el resto de addons, luego base.
		inst.set('require', function(name:String, ?forceReload:Bool):Dynamic {
			// 1. Lib propia registrada (ruta exacta conocida)
			if (_libPaths.exists(name))
			{
				final absPath = _libPaths.get(name);
				return funkin.scripting.ScriptLibrary.loadAbsolute(
					absPath, inst.interp, forceReload ?? false);
			}

			// 2. Búsqueda en todos los search dirs
			final dirs = _buildSearchDirs();
			return funkin.scripting.ScriptLibrary.require(
				name, dirs, inst.interp, forceReload ?? false);
		});

		// requireLib(name) — alias que devuelve null en vez de trazar error
		// si la lib no existe, útil para comprobaciones opcionales.
		inst.set('hasLib', function(name:String):Bool {
			if (_libPaths.exists(name)) return true;
			#if sys
			final dirs = _buildSearchDirs();
			for (dir in dirs)
				for (ext in ['.hx', '.hscript', ''])
					if (sys.FileSystem.exists('$dir/$name$ext')
						&& !sys.FileSystem.isDirectory('$dir/$name$ext'))
						return true;
			#end
			return false;
		});
	}

	function _buildSearchDirs():Array<String>
	{
		// Propio addon: libs/ primero, luego .deps/ (dependencias descargadas)
		final dirs:Array<String> = [libsPath, depsPath];
		// Libs y deps de todos los addons cargados (excepto el propio)
		for (ae in AddonManager.loadedAddons)
			if (ae.id != id) { dirs.push(ae.libsPath); dirs.push(ae.depsPath); }
		// Base engine
		dirs.push(funkin.scripting.ScriptLibrary.BASE_LIBS);
		return dirs;
	}
	#end

	// ── Destroy ────────────────────────────────────────────────────────────

	// FIX Bug 8: AddonEntry had no destroy() method.
	public function destroy():Void
	{
		#if HSCRIPT_ALLOWED
		for (_ => inst in _scripts)
			if (inst != null) try inst.destroy() catch (_:Dynamic) {}
		#end
		_scripts.clear();
		_libs.clear();
		_libPaths.clear();
		// Limpiar caché de ScriptLibrary para la carpeta libs/ de este addon
		funkin.scripting.ScriptLibrary.clearCacheForDir(libsPath);
		funkin.scripting.ScriptLibrary.clearCacheForDir(depsPath);
	}
}
