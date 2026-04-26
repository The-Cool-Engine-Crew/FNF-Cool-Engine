package mods;

#if sys
import sys.FileSystem;
import sys.io.File;
#end
import haxe.Json;
import mods.ModEngineOverride;
import ui.Alphabet.AlphabetConfig;

using StringTools;

/**
 * ModManager — Gestiona mods instalados, activación y previews.
 *
 * ─── Estructura esperada de un mod ─────────────────────────────────────────
 *
 *   mods/
 *   └── my-mod/
 *       ├── mod.json          ← metadatos (name, author, version, priority…)
 *       ├── preview.mp4       ← preview video en el selector  (opcional)
 *       ├── preview.png       ← preview imagen si no hay video (opcional)
 *       ├── icon.png          ← icono cuadrado del mod         (opcional)
 *       ├── songs/
 *       ├── characters/
 *       ├── stages/
 *       ├── images/
 *       ├── sounds/
 *       ├── music/
 *       ├── data/
 *       ├── scripts/
 *       └── videos/
 *
 * ─── Campos de mod.json ──────────────────────────────────────────────────────
 *   {
 *     "name":           "My Mod",
 *     "description":    "Descripción del mod",
 *     "author":         "NombreAutor",
 *     "version":        "1.0.0",
 *     "priority":       0,
 *     "color":          "FF5599",
 *     "website":        "https://…",
 *     "enabled":        true,
 *     "startupDefault": false,   ← true = arranca siempre con este mod
 *     "appTitle":       "Mi Mod — FNF",  ← título de ventana (opcional)
 *     "appIcon":        "icon",           ← PNG en raíz del mod, sin extensión (opcional)
 *     "discord": {                        ← config de Discord Rich Presence (opcional)
 *       "clientId":      "123456789",       ← app ID propio del mod
 *       "largeImageKey": "mymod_icon",      ← key de imagen en Discord Dev Portal
 *       "largeImageText": "Mi Mod",         ← tooltip de imagen grande
 *       "menuDetails":   "Jugando Mi Mod"   ← texto en el menú
 *     }
 *   }
 */
class ModManager
{
	/** Mod actualmente cargado. null = modo base. */
	public static var activeMod(default, null):String = null;

	/**
	 * Mod que arranca por defecto aunque no haya sesión guardada.
	 * Se detecta desde mod.json startupDefault:true (mayor priority gana).
	 */
	public static var startupMod(default, null):Null<String> = null;

	/** Lista de mods instalados, ordenada por priority desc. */
	public static var installedMods(default, null):Array<ModInfo> = [];

	/** Callback que se llama cuando cambia el mod activo. */
	public static var onModChanged:Null<String->Void> = null;

	/** Carpeta raíz donde viven los mods.
	 *  En Android usa el almacenamiento externo para que el usuario
	 *  pueda añadir mods sin necesidad de root ni recompilar el APK.
	 *  Ruta: /sdcard/Android/data/com.coolTeam.coolEngine/files/mods/
	 *  (o lime.system.System.documentsDirectory + "/mods" en Lime) */
	public static var MODS_FOLDER(get, never):String;
	static var _modsFolder:String = null;
	static function get_MODS_FOLDER():String
	{
		if (_modsFolder != null) return _modsFolder;
		#if android
		// lime.system.System.documentsDirectory en Android apunta a
		// /sdcard/Android/data/<package>/files/ — carpeta accesible sin root.
		var base = lime.system.System.documentsDirectory;
		if (base == null || base == '') base = '/sdcard/Android/data/com.coolTeam.coolEngine/files';
		// Quitar trailing slash si lo hay
		if (base.endsWith('/')) base = base.substr(0, base.length - 1);
		_modsFolder = base + '/mods';
		#else
		_modsFolder = 'mods';
		#end
		return _modsFolder;
	}

	/** Sub-carpetas estándar que se crean al crear un mod nuevo. */
	static var STD_FOLDERS = [
		'characters', 'cutscenes', 'data', 'fonts', 'images',
		'music', 'notes', 'shaders', 'songs',
		'sounds', 'stages', 'states', 'scripts'
	];

	private static var _enabledMap:Map<String, Bool> = new Map();

	// ─── Init ─────────────────────────────────────────────────────────────────

	public static function init():Void
	{
		installedMods = [];
		startupMod    = null;

		#if android
		// En Android los mods base viajan dentro del APK como assets (assets/mods/).
		// Los copiamos al storage externo la primera vez.
		_copyBaseModsIfNeeded();
		#end

		#if sys
		if (!FileSystem.exists(MODS_FOLDER) || !FileSystem.isDirectory(MODS_FOLDER))
		{
			trace('[ModManager] Carpeta "mods/" no encontrada — modo base activo.');
			return;
		}

		final extracted = ModExtractor.extractAll();
		if (extracted.length > 0)
			trace('[ModManager] Mods extraídos de archivo: ' + extracted.join(', '));

		_loadEnabledState();

		for (entry in FileSystem.readDirectory(MODS_FOLDER))
		{
			final modPath = '$MODS_FOLDER/$entry';
			if (!FileSystem.isDirectory(modPath)) continue;

			final info = _loadModInfo(entry, modPath);
			if (info != null)
			{
				installedMods.push(info);
				trace('[ModManager] Mod: ${info.id} (${info.name}) prio=${info.priority} enabled=${info.enabled} startup=${info.startupDefault}');
			}
		}

		installedMods.sort((a, b) ->
		{
			if (b.priority != a.priority) return b.priority - a.priority;
			return a.name < b.name ? -1 : 1;
		});

		// Detectar startup mod (primer habilitado con startupDefault=true por priority)
		for (m in installedMods)
			if (m.startupDefault && m.enabled) { startupMod = m.id; break; }

		if (startupMod != null)
			trace('[ModManager] Startup mod: "$startupMod"');
		#end

		trace('[ModManager] ${installedMods.length} mods instalados.');
		#if sys
		loadActiveState();
		#end
	}

	// ─── Activación ───────────────────────────────────────────────────────────

	public static function setActive(modId:Null<String>):Void
	{
		if (modId == null)
		{
			activeMod = null;
			trace('[ModManager] Mod desactivado — modo base.');
			ModEngineOverride.clear();
			AlphabetConfig.reload();
			_saveActiveState();
			if (onModChanged != null) onModChanged(null);
			return;
		}
		#if sys
		if (!isInstalled(modId)) { trace('[ModManager] Mod "$modId" not found.'); return; }
		#end
		activeMod = modId;
		trace('[ModManager] Mod activo: "$activeMod"');

		// Cargar engine overrides declarados en mod.json (si los tiene)
		#if sys
		ModEngineOverride.loadFromModJson('$MODS_FOLDER/$modId/mod.json', modId);
		#end

		AlphabetConfig.reload();
		_saveActiveState();
		if (onModChanged != null) onModChanged(activeMod);
	}

	public static inline function deactivate():Void setActive(null);
	public static inline function isActive():Bool return activeMod != null;

	public static function isInstalled(modId:String):Bool
	{
		#if sys
		return FileSystem.exists('$MODS_FOLDER/$modId') && FileSystem.isDirectory('$MODS_FOLDER/$modId');
		#else
		for (m in installedMods) if (m.id == modId) return true;
		return false;
		#end
	}

	// ─── Enable / Disable ─────────────────────────────────────────────────────

	public static function setEnabled(modId:String, enabled:Bool):Void
	{
		_enabledMap.set(modId, enabled);
		for (m in installedMods) if (m.id == modId) { m.enabled = enabled; break; }
		if (!enabled && activeMod == modId) deactivate();
		_saveEnabledState();
	}

	public static function toggleEnabled(modId:String):Bool
	{
		final cur = isEnabled(modId); setEnabled(modId, !cur); return !cur;
	}

	public static function isEnabled(modId:String):Bool
	{
		if (_enabledMap.exists(modId)) return _enabledMap.get(modId);
		for (m in installedMods) if (m.id == modId) return m.enabled;
		return true;
	}

	// ─── Startup Mod ──────────────────────────────────────────────────────────

	/**
	 * Establece `modId` como startup mod (arranca siempre con él).
	 * Pasa null para limpiar el startup mod actual.
	 * Persiste el cambio en el mod.json correspondiente.
	 */
	public static function setStartupMod(modId:Null<String>):Void
	{
		#if sys
		// Quitar flag del anterior startup mod
		if (startupMod != null && startupMod != modId)
		{
			final prev = getInfo(startupMod);
			if (prev != null) { prev.startupDefault = false; _writeModJson(prev); }
		}
		startupMod = modId;
		if (modId != null)
		{
			final info = getInfo(modId);
			if (info != null)
			{
				info.startupDefault = true;
				_writeModJson(info);
				trace('[ModManager] Startup mod = "$modId"');
			}
		}
		else trace('[ModManager] Startup mod limpiado.');
		#end
	}

	/**
	 * Aplica el startup mod si no hay sesión guardada.
	 * Llamar tras init() en el arranque del juego.
	 */
	public static function applyStartupMod():Void
	{
		if (activeMod != null) return;
		if (startupMod != null)
		{
			trace('[ModManager] Aplicando startup mod: "$startupMod"');
			activeMod = startupMod;
			#if sys
			ModEngineOverride.loadFromModJson('$MODS_FOLDER/$activeMod/mod.json', activeMod);
			#end
			if (onModChanged != null) onModChanged(activeMod);
		}
	}

	// ─── Creación / Edición de mods ───────────────────────────────────────────

	/**
	 * Crea un nuevo mod con la estructura de carpetas estándar.
	 * @param id    Identificador/carpeta (ej: "my-cool-mod")
	 * @param info  Campos del mod.json
	 * @return El ModInfo creado o null si hubo error
	 */
	public static function createMod(id:String, info:ModInfo):Null<ModInfo>
	{
		#if sys
		final modPath = '$MODS_FOLDER/$id';
		if (FileSystem.exists(modPath))
		{
			trace('[ModManager] createMod: la carpeta "$modPath" ya existe.');
			return null;
		}
		try
		{
			FileSystem.createDirectory(modPath);
			for (sub in STD_FOLDERS) FileSystem.createDirectory('$modPath/$sub');
			info.id     = id;
			info.folder = modPath;
			_writeModJson(info);
			installedMods.push(info);
			installedMods.sort((a, b) ->
			{
				if (b.priority != a.priority) return b.priority - a.priority;
				return a.name < b.name ? -1 : 1;
			});
			trace('[ModManager] Mod creado: "$id"');
			return info;
		}
		catch (e:Dynamic) { trace('[ModManager] Error creando mod "$id": $e'); return null; }
		#else
		return null;
		#end
	}

	/**
	 * Guarda los cambios de un ModInfo existente en disco.
	 */
	public static function saveModInfo(info:ModInfo):Void
	{
		#if sys
		for (i in 0...installedMods.length)
			if (installedMods[i].id == info.id) { installedMods[i] = info; break; }
		_writeModJson(info);
		trace('[ModManager] mod.json actualizado: ${info.id}');
		#end
	}

	// ─── Resolución de paths ──────────────────────────────────────────────────

	public static function resolveInMod(file:String):Null<String>
	{
		if (activeMod == null) return null;
		final path = '$MODS_FOLDER/$activeMod/$file';
		#if sys return FileSystem.exists(path) ? path : null;
		#else return openfl.utils.Assets.exists(path) ? path : null; #end
	}

	public static function resolveInSpecific(modId:Null<String>, file:String):Null<String>
	{
		if (modId == null) return null;
		final path = '$MODS_FOLDER/$modId/$file';
		#if sys return FileSystem.exists(path) ? path : null;
		#else return openfl.utils.Assets.exists(path) ? path : null; #end
	}

	public static inline function modRoot():Null<String>
		return activeMod != null ? '$MODS_FOLDER/$activeMod' : null;

	// ─── Preview ──────────────────────────────────────────────────────────────

	public static function previewVideo(modId:String):Null<String>
	{
		final p = '$MODS_FOLDER/$modId/preview.mp4';
		#if sys return FileSystem.exists(p) ? p : null; #else return null; #end
	}

	public static function previewImage(modId:String):Null<String>
	{
		#if sys
		for (ext in ['png', 'jpg', 'jpeg'])
		{
			final p = '$MODS_FOLDER/$modId/preview.$ext';
			if (FileSystem.exists(p)) return p;
		}
		return null;
		#else return null; #end
	}

	public static function iconPath(modId:String):Null<String>
	{
		final p = '$MODS_FOLDER/$modId/icon.png';
		#if sys return FileSystem.exists(p) ? p : null; #else return null; #end
	}

	public static function previewType(modId:String):ModPreviewType
	{
		if (previewVideo(modId) != null) return VIDEO;
		if (previewImage(modId) != null) return IMAGE;
		return NONE;
	}

	// ─── Info del mod ─────────────────────────────────────────────────────────

	public static function activeInfo():Null<ModInfo>
	{
		if (activeMod == null) return null;
		for (m in installedMods) if (m.id == activeMod) return m;
		return null;
	}

	public static function getInfo(modId:String):Null<ModInfo>
	{
		for (m in installedMods) if (m.id == modId) return m;
		return null;
	}

	/** Developer Mode — controla el acceso a editores (Chart, Stage, Dialogue, AnimDebug, etc.).
	 *  Se lee y escribe en mod.json del mod activo ("developerMode": true).
	 *  Si no hay mod activo o el campo no está presente devuelve FALSE.
	 *  Por defecto es FALSE; debe activarse explícitamente en mod.json. */
	public static var developerMode(get, set):Bool;

	static function get_developerMode():Bool
	{
		final info = activeInfo();
		if (info != null)
			return info.developerMode != false; // null/true → true, false → false
		return true; // sin mod activo → true por defecto
	}

	static function set_developerMode(v:Bool):Bool
	{
		final info = activeInfo();
		if (info != null)
		{
			info.developerMode = v;
			saveModInfo(info);
		}
		return v;
	}

	// ─── Helpers internos ─────────────────────────────────────────────────────
	#if sys
	static function _loadModInfo(id:String, path:String):Null<ModInfo>
	{
		final jsonPath = '$path/mod.json';
		var name           = id;
		var desc           = '';
		var author         = '';
		var version        = '1.0.0';
		var priority       = 0;
		var color          = 0xFF9900;
		var website        = '';
		var enabledDef     = true;
		var startupDef       = false;
		var developerModeDef:Null<Bool> = null; // null = no definido → default true
		var gamebananaid:Null<Int> = null;
		var appTitle:Null<String> = null;
		var appIcon:Null<String>  = null;
		var discord:Null<ModDiscordConfig> = null;

		if (FileSystem.exists(jsonPath))
		{
			try
			{
				final d:Dynamic = Json.parse(File.getContent(jsonPath));
				name       = d.name           ?? id;
				desc       = d.description    ?? '';
				author     = d.author         ?? '';
				version    = d.version        ?? '1.0.0';
				priority   = Std.int(d.priority ?? 0);
				website    = d.website        ?? '';
				enabledDef = d.enabled        ?? true;
				startupDef   = d.startupDefault ?? false;
				if (d.developerMode != null) developerModeDef = (d.developerMode == true);
				if (d.gamebananaid != null) gamebananaid = Std.int(d.gamebananaid);
				if (d.appTitle != null) appTitle = Std.string(d.appTitle);
				if (d.appIcon  != null) appIcon  = Std.string(d.appIcon);
				if (d.discord != null)
				{
					final dc:Dynamic = d.discord;
					discord = {
						clientId:     dc.clientId     != null ? Std.string(dc.clientId)     : null,
						largeImageKey: dc.largeImageKey != null ? Std.string(dc.largeImageKey) : null,
						largeImageText: dc.largeImageText != null ? Std.string(dc.largeImageText) : null,
						menuDetails:  dc.menuDetails  != null ? Std.string(dc.menuDetails)  : null
					};
				}
				if (d.color != null)
				{
					try
					{
						var hex:String = Std.string(d.color);
						if (StringTools.startsWith(hex, '#')) hex = hex.substr(1);
						color = 0xFF000000 | Std.parseInt('0x$hex');
					}
					catch (_) {}
				}
				// Aplicar engineOverrides al vuelo si el mod está siendo activado ahora
				if (d.engineOverrides != null && activeMod == id)
					ModEngineOverride.applyFromRaw(d.engineOverrides, id);
			}
			catch (e:Dynamic) { trace('[ModManager] Error mod.json "$id": $e'); }
		}
		else
		{
			// ── V-Slice mod: usa _polymod_meta.json en lugar de mod.json ──────────
			// Formato: { "title":"Name", "description":"...", "contributors":[{"name":"Author"}],
			//            "api_version":"0.8.0", "mod_version":"1.0.0" }
			final polymodPath = '$path/_polymod_meta.json';
			if (FileSystem.exists(polymodPath))
			{
				try
				{
					final d:Dynamic = Json.parse(File.getContent(polymodPath));
					// "title" es el nombre del mod en V-Slice
					if (d.title != null)   name    = Std.string(d.title);
					if (d.description != null) desc = Std.string(d.description);
					// Primer contribuidor = autor
					if (d.contributors != null && Std.isOfType(d.contributors, Array))
					{
						final contribs:Array<Dynamic> = cast d.contributors;
						if (contribs.length > 0 && contribs[0].name != null)
							author = Std.string(contribs[0].name);
					}
					// mod_version es la versión
					if (d.mod_version != null) version = Std.string(d.mod_version);
					// V-Slice mods no tienen enabled/priority en _polymod_meta → defaults
					// Nota: no hay mod.json → no hay engineOverrides para V-Slice
					trace('[ModManager] Mod V-Slice detectado via _polymod_meta.json: "$id" ("$name")');
				}
				catch (e:Dynamic) { trace('[ModManager] Error _polymod_meta.json "$id": $e'); }
			}
		}

		final enabled = _enabledMap.exists(id) ? _enabledMap.get(id) : enabledDef;
		return {
			id: id, name: name, description: desc, author: author,
			version: version, priority: priority, color: color,
			website: website, enabled: enabled, startupDefault: startupDef, folder: path,
			developerMode: developerModeDef,
			appTitle: appTitle, appIcon: appIcon, discord: discord,
			gamebananaid: gamebananaid
		};
	}

	static function _writeModJson(info:ModInfo):Void
	{
		try
		{
			final obj:Dynamic = {
				name:           info.name,
				description:    info.description,
				author:         info.author,
				version:        info.version,
				priority:       info.priority,
				color:          StringTools.hex(info.color & 0xFFFFFF, 6),
				website:        info.website,
				enabled:        info.enabled,
				startupDefault: info.startupDefault,
				developerMode:  info.developerMode != false // null/true → true, false → false
			};
			// Solo serializar si están definidos, para no ensuciar mod.json sin esos campos
			if (info.appTitle     != null) Reflect.setField(obj, 'appTitle',     info.appTitle);
			if (info.appIcon      != null) Reflect.setField(obj, 'appIcon',      info.appIcon);
			if (info.gamebananaid != null) Reflect.setField(obj, 'gamebananaid', info.gamebananaid);
			if (info.discord  != null)
			{
				final dc:Dynamic = {};
				if (info.discord.clientId      != null) Reflect.setField(dc, 'clientId',      info.discord.clientId);
				if (info.discord.largeImageKey  != null) Reflect.setField(dc, 'largeImageKey',  info.discord.largeImageKey);
				if (info.discord.largeImageText != null) Reflect.setField(dc, 'largeImageText', info.discord.largeImageText);
				if (info.discord.menuDetails   != null) Reflect.setField(dc, 'menuDetails',   info.discord.menuDetails);
				Reflect.setField(obj, 'discord', dc);
			}
			File.saveContent('${info.folder}/mod.json', Json.stringify(obj, null, '\t'));
		}
		catch (e:Dynamic) { trace('[ModManager] Error escribiendo mod.json "${info.id}": $e'); }
	}

	static function _saveActiveState():Void
	{
		try { File.saveContent('$MODS_FOLDER/.active_mod.json', Json.stringify({active: activeMod})); }
		catch (e:Dynamic) { trace('[ModManager] No se pudo guardar active mod: $e'); }
	}

	public static function loadActiveState():Void
	{
		final path = '$MODS_FOLDER/.active_mod.json';
		if (!FileSystem.exists(path)) return;
		try
		{
			final data:Dynamic = Json.parse(File.getContent(path));
			final savedId:String = Reflect.field(data, 'active');
			if (savedId != null && isInstalled(savedId))
			{
				activeMod = savedId;
				// Aplicar engine overrides del mod restaurado (mismo camino que setActive)
				ModEngineOverride.loadFromModJson('$MODS_FOLDER/$activeMod/mod.json', activeMod);
				trace('[ModManager] Mod activo restaurado: "$activeMod"');
			}
		}
		catch (e:Dynamic) { trace('[ModManager] Error restaurando active mod: $e'); }
	}

	static function _saveEnabledState():Void
	{
		try
		{
			final obj:Dynamic = {};
			for (id => val in _enabledMap) Reflect.setField(obj, id, val);
			File.saveContent('$MODS_FOLDER/.enabled_state.json', Json.stringify(obj));
		}
		catch (e:Dynamic) { trace('[ModManager] No se pudo guardar enabled state: $e'); }
	}

	static function _loadEnabledState():Void
	{
		final path = '$MODS_FOLDER/.enabled_state.json';
		if (!FileSystem.exists(path)) return;
		try
		{
			final data:Dynamic = Json.parse(File.getContent(path));
			for (f in Reflect.fields(data)) _enabledMap.set(f, Reflect.field(data, f) == true);
		}
		catch (e:Dynamic) { trace('[ModManager] Error cargando enabled state: $e'); }
	}
	#end

	// ─── Android: copia mods base del APK al storage externo ─────────────────
	#if (android && sys)
	static function _copyBaseModsIfNeeded():Void
	{
		final dest   = MODS_FOLDER;
		final marker = dest + '/.base_copied';

		if (FileSystem.exists(marker)) return;

		// FIX Bug #2: On the very first launch the APK contains the base mods as
		// embedded assets. Copying them synchronously inside the game-loop blocks
		// for several seconds (images, music…) → Android's ANR watchdog kills
		// the process before the first frame is ever drawn.
		// We run the copy on a background thread so the game loop stays alive.
		// The mods folder won't be available on this first launch, but that's
		// acceptable — they will be there from the second launch onward.
		trace('[ModManager] Primera ejecución — copiando mods base a $dest (background thread)');

		sys.thread.Thread.create(function()
		{
			try
			{
				if (!FileSystem.exists(dest))
					FileSystem.createDirectory(dest);

				final assetList = openfl.utils.Assets.list();
				var copied = 0;

				for (assetPath in assetList)
				{
					if (!assetPath.startsWith('assets/mods/')) continue;
					final relative = assetPath.substr('assets/mods/'.length);
					final destPath = dest + '/' + relative;
					final destDir  = haxe.io.Path.directory(destPath);
					if (FileSystem.exists(destPath)) continue;
					if (!FileSystem.exists(destDir))
					{
						try FileSystem.createDirectory(destDir)
						catch (_:Dynamic) {}
					}
					try
					{
						final bytes = openfl.utils.Assets.getBytes(assetPath);
						if (bytes != null) { sys.io.File.saveBytes(destPath, bytes); copied++; }
					}
					catch (e:Dynamic) { trace('[ModManager] No se pudo copiar $assetPath: $e'); }
				}

				sys.io.File.saveContent(marker, '1');
				trace('[ModManager] Mods base copiados: $copied archivos → $dest');
			}
			catch (e:Dynamic) { trace('[ModManager] Error copiando mods base en background: $e'); }
		});
	}
	#end
}

// ─────────────────────────────────────────────────────────────────────────────

/**
 * Configuración de Discord Rich Presence por mod.
 * Todos los campos son opcionales — si no se definen, el engine usa sus valores por defecto.
 */
typedef ModDiscordConfig =
{
	/** ID de aplicación Discord del mod. Si se define, reinicia RPC con este clientId. */
	var ?clientId:Null<String>;
	/** Key de imagen grande en el portal de Discord Developer. Default: "icon". */
	var ?largeImageKey:Null<String>;
	/** Texto tooltip de la imagen grande. Default: "FNF\' Cool Engine". */
	var ?largeImageText:Null<String>;
	/** Texto de "details" que aparece en el menú. Default: "In the Menu". */
	var ?menuDetails:Null<String>;
}

typedef ModInfo =
{
	var id:String;
	var name:String;
	var description:String;
	var author:String;
	var version:String;
	var priority:Int;
	var color:Int;
	var website:String;
	var enabled:Bool;
	var startupDefault:Bool;
	var folder:String;
	/**
	 * Activa/desactiva el modo desarrollador para este mod.
	 * null/true (default) = acceso a editores (Chart, Stage, Dialogue, AnimDebug).
	 * false = modo jugador normal sin herramientas de desarrollo.
	 * Para desactivarlo en un mod de distribución: "developerMode": false en mod.json.
	 */
	var ?developerMode:Null<Bool>;
	/** Título de ventana personalizado. null = usar el default del engine. */
	var ?appTitle:Null<String>;
	/** Nombre del archivo PNG de icono en la raíz del mod, sin extensión. null = icono default. */
	var ?appIcon:Null<String>;
	/** Configuración de Discord Rich Presence. null = usar valores por defecto del engine. */
	var ?discord:Null<ModDiscordConfig>;
	/**
	 * ID del mod en GameBanana (el número de la URL: gamebanana.com/mods/XXXXX).
	 * El launcher usa esto para comprobar si hay actualización disponible.
	 * null = no se comprueba actualización en GameBanana para este mod.
	 */
	var ?gamebananaid:Null<Int>;
}

enum ModPreviewType { VIDEO; IMAGE; NONE; }
