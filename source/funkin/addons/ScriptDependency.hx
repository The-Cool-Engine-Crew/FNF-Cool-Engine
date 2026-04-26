package funkin.addons;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/**
 * ScriptDependency — Downloads and caches external HScript libraries from GitHub or other URLs.
 *
 * Dependencies are declared in `addon.json` under the `dependencies` key.
 * Downloaded files are stored in `addons/<id>/.deps/` and are treated
 * exactly like local libraries in the `libs/` folder.
 *
 * ─── Supported formats in addon.json ────────────────────────────────────────
 *
 *  // Direct URL to a raw .hx file (raw.githubusercontent.com, etc.)
 *  {
 *    "name":    "TweenLib",
 *    "url":     "https://raw.githubusercontent.com/user/repo/main/src/TweenLib.hx"
 *  }
 *
 *  // GitHub shorthand (user/repo) + path inside the repo
 *  {
 *    "name":    "EaseUtil",
 *    "github":  "user/repo",
 *    "branch":  "main",          // optional, default "main"
 *    "path":    "src/EaseUtil.hx"
 *  }
 *
 *  // Multiple files from the same repo (stored as separate deps)
 *  {
 *    "github":  "user/repo",
 *    "branch":  "dev",
 *    "paths": [
 *      { "name": "StringUtils", "path": "src/utils/StringUtils.hx" },
 *      { "name": "ArrayUtils",  "path": "src/utils/ArrayUtils.hx"  }
 *    ]
 *  }
 *
 * ─── Cache ─────────────────────────────────────────────────────────────────
 *
 *  Downloaded files are stored in `addons/<id>/.deps/<name>.hx`.
 *  If the file already exists, it will NOT be downloaded again (permanent disk cache).
 *  To force re-download, delete the `.deps/` folder of the addon
 *  or use `forceRedownload: true` in the JSON entry.
 *
 * ─── HScript Limitations ───────────────────────────────────────────────────
 *
 *  HScript is a pure Haxe interpreter. External libraries must be:
 *    ✓ Pure Haxe without macros
 *    ✓ No externs or native bindings (C++/Java/etc.)
 *    ✓ No complex conditional compilation (#if)
 *    ✓ No abstract types with complex custom operators
 *    ✓ Only standard types: String, Array, Map, Dynamic, Int, Float, Bool…
 *
 * ─── Full addon.json example ───────────────────────────────────────────────
 *
 *  {
 *    "id": "my-addon",
 *    "name": "My Addon",
 *    "version": "1.0.0",
 *    "dependencies": [
 *      {
 *        "name":   "Ease",
 *        "url":    "https://raw.githubusercontent.com/nicoptere/FlxEase/main/Ease.hx"
 *      },
 *      {
 *        "name":   "ArrayUtils",
 *        "github": "FunkinMods/hscript-utils",
 *        "branch": "main",
 *        "path":   "src/ArrayUtils.hx"
 *      }
 *    ],
 *    "hooks": { ... }
 *  }
 */
class ScriptDependency
{
	/** Subcarpeta dentro de un addon donde se cachean las deps descargadas. */
	public static inline final DEPS_FOLDER = '.deps';

	/** Timeout en segundos para las peticiones HTTP. */
	public static inline final HTTP_TIMEOUT = 15;

	// ─────────────────────────────────────────────────────────────────────────
	// API pública
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Resuelve y descarga todas las dependencias de `addon`.
	 * Los archivos se guardan en `<addonPath>/.deps/`.
	 * Devuelve la ruta al directorio .deps/ (para añadirla al searchPath).
	 *
	 * @param addonId    ID del addon (para trazas)
	 * @param addonPath  Carpeta raíz del addon (donde existe addon.json)
	 * @param deps       Array de ScriptDepInfo del addon.json
	 * @return           Ruta de la carpeta .deps/ que contiene los archivos descargados
	 */
	public static function resolveAll(addonId:String, addonPath:String, deps:Array<ScriptDepInfo>):String
	{
		final depsDir = '$addonPath/$DEPS_FOLDER';

		#if sys
		if (deps == null || deps.length == 0)
			return depsDir;

		// Asegurar que la carpeta .deps/ existe
		if (!FileSystem.exists(depsDir))
			FileSystem.createDirectory(depsDir);

		for (dep in deps)
		{
			try
			{
				_resolveDep(addonId, depsDir, dep);
			}
			catch (e:Dynamic)
			{
				trace('[ScriptDependency] [$addonId] Error resolving dep "${dep?.name ?? "?"}": $e');
			}
		}
		#end

		return depsDir;
	}

	/**
	 * Elimina la caché en disco de todas las dependencias de un addon.
	 * Al hacer esto, la próxima llamada a resolveAll() re-descargará todo.
	 */
	public static function clearCache(addonPath:String):Void
	{
		#if sys
		final depsDir = '$addonPath/$DEPS_FOLDER';
		if (!FileSystem.exists(depsDir)) return;
		for (f in FileSystem.readDirectory(depsDir))
		{
			final fp = '$depsDir/$f';
			if (!FileSystem.isDirectory(fp))
				FileSystem.deleteFile(fp);
		}
		trace('[ScriptDependency] Cache cleared: $depsDir');
		#end
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Internos
	// ─────────────────────────────────────────────────────────────────────────

	#if sys
	/**
	 * Procesa una única entrada de dep.
	 * Soporta `url`, `github`+`path`, y `github`+`paths`.
	 */
	static function _resolveDep(addonId:String, depsDir:String, dep:ScriptDepInfo):Void
	{
		// ── Caso 1: url directa ──────────────────────────────────────────
		if (dep.url != null && dep.url != '')
		{
			if (dep.name == null || dep.name == '')
			{
				trace('[ScriptDependency] [$addonId] Dep with "url" you need "name". Skipping.');
				return;
			}
			_downloadIfNeeded(addonId, depsDir, dep.name, dep.url, dep.forceRedownload == true);
			return;
		}

		// ── Caso 2: github shorthand ─────────────────────────────────────
		if (dep.github != null && dep.github != '')
		{
			final branch = (dep.branch != null && dep.branch != '') ? dep.branch : 'main';

			// Sub-caso 2a: múltiples paths []
			if (dep.paths != null && dep.paths.length > 0)
			{
				for (entry in dep.paths)
				{
					if (entry.name == null || entry.path == null) continue;
					final url = _githubRawUrl(dep.github, branch, entry.path);
					_downloadIfNeeded(addonId, depsDir, entry.name, url, dep.forceRedownload == true);
				}
				return;
			}

			// Sub-caso 2b: un único path
			if (dep.path != null && dep.path != '')
			{
				if (dep.name == null || dep.name == '')
				{
					trace('[ScriptDependency] [$addonId] Dep with "github"+"path" you need "name". Skipping.');
					return;
				}
				final url = _githubRawUrl(dep.github, branch, dep.path);
				_downloadIfNeeded(addonId, depsDir, dep.name, url, dep.forceRedownload == true);
				return;
			}

			trace('[ScriptDependency] [$addonId] Dep with "github" you need "path" or "paths". Skipping.');
			return;
		}

		trace('[ScriptDependency] [$addonId] Dep invalid (without "url" or "github"): ${haxe.Json.stringify(dep)}');
	}

	/**
	 * Descarga `url` y lo guarda como `depsDir/<name>.hx` si no existe ya
	 * (o si forceRedownload == true).
	 */
	static function _downloadIfNeeded(
		addonId:String,
		depsDir:String,
		name:String,
		url:String,
		forceRedownload:Bool
	):Void
	{
		final destPath = '$depsDir/$name.hx';

		if (!forceRedownload && FileSystem.exists(destPath))
		{
			trace('[ScriptDependency] [$addonId] "$name" already cached on disk → $destPath');
			return;
		}

		trace('[ScriptDependency] [$addonId] Downloading "$name" from: $url');

		var content:String = null;
		var error:String   = null;

		final http = new haxe.Http(url);
		http.onData  = function(data:String)  { content = data; };
		http.onError = function(err:String)   { error   = err;  };

		#if sys
		http.request(false); // GET síncrono
		#end

		if (error != null || content == null)
		{
			trace('[ScriptDependency] [$addonId] Error downloading "$name": ${error ?? "no data"}');
			return;
		}

		if (content.trim() == '' || content.startsWith('404'))
		{
			trace('[ScriptDependency] [$addonId] "$name" → empty response or 404. URL: $url');
			return;
		}

		File.saveContent(destPath, content);
		trace('[ScriptDependency] [$addonId] "$name" downloaded and saved → $destPath');
	}

	/** Construye la URL raw de GitHub para un archivo. */
	static inline function _githubRawUrl(repo:String, branch:String, filePath:String):String
	{
		// Normalizar: quitar leading slash del path si lo hay
		final path = filePath.startsWith('/') ? filePath.substr(1) : filePath;
		return 'https://raw.githubusercontent.com/$repo/$branch/$path';
	}
	#end
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Typedefs
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Descriptor of an external dependency in addon.json.
 *
 * Valid forms:
 *   { name, url }
 *   { name, github, branch?, path }
 *   { github, branch?, paths: [ {name, path}, … ] }
 */
typedef ScriptDepInfo = {
	/**
	 * Name used to import the library via require().
	 * Required unless `paths` is used (each entry in paths has its own name).
	 */
	var ?name: String;

	/**
	 * Direct URL to the raw .hx file (raw.githubusercontent.com, etc.).
	 * Alternative to `github`.
	 */
	var ?url: String;

	/**
	 * GitHub shorthand: "user/repo".
	 * Alternative to `url`. Requires `path` or `paths`.
	 */
	var ?github: String;

	/**
	 * GitHub repository branch. Defaults to "main".
	 * Only applies when using `github`.
	 */
	var ?branch: String;

	/**
	 * Path to the .hx file inside the GitHub repo.
	 * Used with `github` to import a single file.
	 */
	var ?path: String;

	/**
	 * List of files to import from the same repo.
	 * Each entry has { name, path }.
	 * Used with `github` to import multiple files.
	 */
	var ?paths: Array<ScriptDepPathEntry>;

	/**
	 * If true, re-downloads the file even if it's already cached on disk.
	 * Useful during development. Default: false.
	 */
	var ?forceRedownload: Bool;
}

/** Entry for an individual file inside `paths`. */
typedef ScriptDepPathEntry = {
	/** Name used for require(). */
	var name: String;
	/** Relative path inside the repo. */
	var path: String;
}
