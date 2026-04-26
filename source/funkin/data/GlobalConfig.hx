package funkin.data;

import haxe.Json;
import sys.FileSystem;
import sys.io.File;
import mods.ModManager;

using StringTools;

/**
 * GlobalConfig — Configuración global de UI, noteskin y hold cover.
 *
 * Archivo: assets/data/config/global.json  (base)
 *          mods/{activeMod}/data/config/global.json  (override por mod)
 *
 * Ejemplo de global.json:
 * {
 *   "ui":               "default",
 *   "noteSkin":         "arrows",
 *   "noteSplash":       "Default",
 *   "holdCoverEnabled": true,
 *   "holdCoverSkin":    "noteHoldCover"
 * }
 *
 * Jerarquía de prioridad:
 *   meta.json  >  global.json del mod activo  >  global.json base  >  hardcoded
 */
class GlobalConfig
{
	// ─── Singleton ──────────────────────────────────────────────────────────────
	public static var instance(get, null):GlobalConfig;
	private static var _instance:GlobalConfig;
	private static var _loadedForMod:String = null;
	private static var _hooked:Bool = false;

	// ─── Runtime overrides (seteados desde script, no desde global.json) ────────
	// Permiten que un script de mod cambie configuración sin tocar el JSON en disco.
	// Se limpian en reload() para que el JSON tenga prioridad al recargar.
	private static var _runtimeOverrides:Map<String, Dynamic> = new Map();

	static function get_instance():GlobalConfig
	{
		_ensureHooked();
		final curMod:String = ModManager.activeMod != null ? ModManager.activeMod : '__NONE__';
		if (_instance == null || _loadedForMod != curMod)
		{
			if (_instance != null)
				trace('[GlobalConfig] Mod cambió ("$_loadedForMod" → "$curMod"), recargando...');
			_instance     = _load(curMod);
			_loadedForMod = curMod;
		}
		return _instance;
	}

	public static function applyToSkinSystem():Void
	{
		if (_instance != null) _applyToSkinSystem(_instance);
		else _applyToSkinSystem(instance);
	}

	public static function reload():Void
	{
		final curMod:String = ModManager.activeMod != null ? ModManager.activeMod : '__NONE__';
		_instance     = _load(curMod);
		_loadedForMod = curMod;
		_applyToSkinSystem(_instance);
		applyDiscord();
	}

	// ─── Propiedades ────────────────────────────────────────────────────────────

	/** Nombre del script de UI en assets/ui/{ui}/script.hx */
	public var ui:String = 'default';

	/** Nombre del noteskin en assets/skins/{noteSkin}/skin.json */
	public var noteSkin:String = 'default';

	/** Nombre del splash en assets/splashes/{noteSplash}/splash.json */
	public var noteSplash:String = 'Default';

	/**
	 * Activa/desactiva el hold cover globalmente.
	 * Las canciones con holdCoverEnabled en su meta.json tienen prioridad.
	 */
	public var holdCoverEnabled:Bool = true;

	public var splashesEnabled:Bool = true;

	/**
	 * Skin global del hold cover (nombre de atlas sin extensión).
	 * Se busca en assets/images/holdCovers/{holdCoverSkin}.
	 * Las canciones pueden sobreescribirlo con su propio holdCoverSkin.
	 */
	public var holdCoverSkin:Null<String> = null;

	// ─── Ventana ────────────────────────────────────────────────────────────────

	/**
	 * Título personalizado de la ventana del OS.
	 * null = usa el título por defecto del engine o de mod.json.
	 * Tiene prioridad sobre mod.json appTitle cuando se setea desde script.
	 */
	public var windowTitle:Null<String> = null;

	// ─── Discord Rich Presence ───────────────────────────────────────────────────

	/**
	 * Client ID de la aplicación Discord del mod.
	 * null = usa el clientId de mod.json > default del engine.
	 */
	public var discordClientId:Null<String> = null;

	/** Key de imagen grande en el portal Discord Developer. null = default del engine. */
	public var discordLargeImageKey:Null<String> = null;

	/** Tooltip de la imagen grande. null = default del engine. */
	public var discordLargeImageText:Null<String> = null;

	/** Texto de "details" en el menú principal. null = default del engine. */
	public var discordMenuDetails:Null<String> = null;

	// ─── Gameplay ────────────────────────────────────────────────────────────────

	/**
	 * Velocidad de scroll global de las notas (multiplier).
	 * 0 o negativo = usa la velocidad del chart.
	 * Los scripts de song pueden sobreescribirlo per-canción.
	 */
	public var scrollSpeed:Float = 0.0;

	/** Zoom de cámara por defecto en gameplay. 0 = usa el del stage. */
	public var defaultZoom:Float = 0.0;

	/** Activa ghost tap globalmente. true = no penaliza al presionar sin nota. */
	public var ghostTap:Bool = true;

	/** Activa anti-mash globalmente. */
	public var antiMash:Bool = true;

	/** Downscroll global. false = notas caen hacia abajo (normal). */
	public var downscroll:Bool = false;

	/** Middlescroll global. */
	public var middlescroll:Bool = false;

	/** Activa/desactiva los note splashes globalmente. */
	public var noteSplashEnabled:Bool = true;

	// ─── Audio ───────────────────────────────────────────────────────────────────

	/** Volumen de la música del menú de freeplay (0.0-1.0). -1 = usar default. */
	public var freeplayMusicVolume:Float = -1.0;

	// ─── State Overrides ─────────────────────────────────────────────────────────

	/**
	 * Reemplaza un state del engine por un ScriptableState personalizado.
	 *
	 * Ejemplo en global.json:
	 * {
	 *   "stateOverrides": {
	 *     "TitleState":    "TitleMenu",
	 *     "MainMenuState": "MainMenu",
	 *     "FreeplayState": "MyFreeplay"
	 *   }
	 * }
	 *
	 * Cuando el engine intente navegar a "TitleState", en su lugar cargará
	 * un ScriptableState('TitleMenu') cuyo script está en:
	 *   assets/states/titlemenu/    o    mods/{mod}/states/titlemenu/
	 *
	 * Keys aceptadas (case-insensitive):
	 *   TitleState, MainMenuState, FreeplayState, StoryMenuState,
	 *   OptionsMenuState, CreditsState, CharacterSelectorState
	 *
	 * El valor es el nombre del ScriptableState a cargar (sin distinción de case).
	 */
	public var stateOverrides:Map<String, String> = new Map();

	/**
	 * Resuelve un nombre de state aplicando overrides del global.json.
	 * Si hay un override definido devuelve el nombre del ScriptableState de destino,
	 * si no existe override devuelve null (el engine usa el state nativo).
	 *
	 * Ejemplo:
	 *   var override = GlobalConfig.resolveStateOverride('TitleState');
	 *   if (override != null)
	 *       StateTransition.switchState(new ScriptableState(override));
	 *   else
	 *       StateTransition.switchState(new TitleState());
	 */
	public static function resolveStateOverride(stateName:String):Null<String>
	{
		final cfg = instance;
		if (cfg.stateOverrides == null || cfg.stateOverrides.iterator() == null) return null;

		// Buscar primero case-sensitive, luego case-insensitive
		if (cfg.stateOverrides.exists(stateName))
			return cfg.stateOverrides.get(stateName);

		final lower = stateName.toLowerCase();
		for (key => value in cfg.stateOverrides)
			if (key.toLowerCase() == lower)
				return value;

		return null;
	}

	// ─── Carga interna ───────────────────────────────────────────────────────────

	function new() {}

	static function _load(curMod:String):GlobalConfig
	{
		var cfg      = new GlobalConfig();
		var path:String  = null;
		var fromMod:Bool = false;

		#if sys
		final modPath = ModManager.resolveInMod('data/config/global.json');
		if (modPath != null) { path = modPath; fromMod = true; }
		if (path == null)
		{
			final basePath = 'assets/data/config/global.json';
			if (FileSystem.exists(basePath)) path = basePath;
		}
		#else
		path = 'assets/data/config/global.json';
		#end

		if (path == null)
		{
			trace('[GlobalConfig] No existe global.json (mod=$curMod), usando defaults');
			return cfg;
		}

		try
		{
			var raw:Dynamic = Json.parse(File.getContent(path));

			if (raw.ui              != null) cfg.ui              = Std.string(raw.ui);
			if (raw.noteSkin        != null) cfg.noteSkin        = Std.string(raw.noteSkin);
			if (raw.noteSplash      != null) cfg.noteSplash      = Std.string(raw.noteSplash);
			if (raw.holdCoverEnabled != null) cfg.holdCoverEnabled = (raw.holdCoverEnabled == true);
			if (raw.splashesEnabled != null) cfg.splashesEnabled = (raw.splashesEnabled == true);
			
			if (raw.holdCoverSkin   != null && Std.string(raw.holdCoverSkin) != '')
				cfg.holdCoverSkin = Std.string(raw.holdCoverSkin);

			// ── Ventana ────────────────────────────────────────────────────────
			if (raw.windowTitle != null && Std.string(raw.windowTitle).trim() != '')
				cfg.windowTitle = Std.string(raw.windowTitle);

			// ── Discord ───────────────────────────────────────────────────────
			if (raw.discordClientId      != null) cfg.discordClientId      = Std.string(raw.discordClientId);
			if (raw.discordLargeImageKey  != null) cfg.discordLargeImageKey  = Std.string(raw.discordLargeImageKey);
			if (raw.discordLargeImageText != null) cfg.discordLargeImageText = Std.string(raw.discordLargeImageText);
			if (raw.discordMenuDetails    != null) cfg.discordMenuDetails    = Std.string(raw.discordMenuDetails);

			// ── Gameplay ──────────────────────────────────────────────────────
			if (raw.scrollSpeed       != null) cfg.scrollSpeed       = (raw.scrollSpeed   : Float);
			if (raw.defaultZoom       != null) cfg.defaultZoom       = (raw.defaultZoom   : Float);
			if (raw.ghostTap          != null) cfg.ghostTap          = (raw.ghostTap       == true);
			if (raw.antiMash          != null) cfg.antiMash          = (raw.antiMash       == true);
			if (raw.downscroll        != null) cfg.downscroll        = (raw.downscroll     == true);
			if (raw.middlescroll      != null) cfg.middlescroll      = (raw.middlescroll   == true);
			if (raw.noteSplashEnabled != null) cfg.noteSplashEnabled = (raw.noteSplashEnabled == true);

			// ── Audio ─────────────────────────────────────────────────────────
			if (raw.freeplayMusicVolume != null) cfg.freeplayMusicVolume = (raw.freeplayMusicVolume : Float);

			// ── State Overrides ───────────────────────────────────────────────
			// "stateOverrides": { "TitleState": "TitleMenu", "MainMenuState": "MainMenu" }
			if (raw.stateOverrides != null)
			{
				cfg.stateOverrides = new Map();
				for (key in Reflect.fields(raw.stateOverrides))
				{
					final value = Reflect.field(raw.stateOverrides, key);
					if (value != null && Std.string(value).trim() != '')
						cfg.stateOverrides.set(key, Std.string(value));
				}
				if (cfg.stateOverrides.iterator() != null)
				{
					final overrideList = [for (k => v in cfg.stateOverrides) '$k → $v'].join(', ');
					trace('[GlobalConfig] State overrides: $overrideList');
				}
			}

			final src = fromMod ? 'mod:${ModManager.activeMod}' : 'base';
			trace('[GlobalConfig] Cargado ($src) — ui="${cfg.ui}" skin="${cfg.noteSkin}" splash="${cfg.noteSplash}" holdCover=${cfg.holdCoverEnabled}');
		}
		catch (e)
		{
			trace('[GlobalConfig] Error al parsear $path: $e');
		}

		_applyToSkinSystem(cfg);
		return cfg;
	}

	// ─── Aplicar a NoteSkinSystem ────────────────────────────────────────────────

	private static function _applyToSkinSystem(cfg:GlobalConfig):Void
	{
		try
		{
			final skinSystem = funkin.gameplay.notes.NoteSkinSystem;

			if (cfg.noteSkin != null && cfg.noteSkin.toLowerCase() != 'default')
			{
				skinSystem.setModDefaultSkin(cfg.noteSkin);
				trace('[GlobalConfig → NoteSkinSystem] skin mod-default: "${cfg.noteSkin}"');
			}
			else
				skinSystem.setModDefaultSkin(null);

			if (cfg.noteSplash != null && cfg.noteSplash.toLowerCase() != 'default')
			{
				skinSystem.setModDefaultSplash(cfg.noteSplash);
				trace('[GlobalConfig → NoteSkinSystem] splash mod-default: "${cfg.noteSplash}"');
			}
			else
				skinSystem.setModDefaultSplash(null);
		}
		catch (e)
		{
			trace('[GlobalConfig] _applyToSkinSystem falló (posiblemente demasiado temprano): $e');
		}
	}

	// ─── Hook a ModManager ───────────────────────────────────────────────────────

	private static function _ensureHooked():Void
	{
		if (_hooked) return;
		_hooked = true;

		final prevCallback = ModManager.onModChanged;
		ModManager.onModChanged = function(newMod:Null<String>):Void
		{
			if (prevCallback != null) prevCallback(newMod);

			final label = newMod != null ? '"$newMod"' : '(ninguno)';
			trace('[GlobalConfig] Mod cambió a $label — invalidando singleton...');

			final curMod  = newMod != null ? newMod : '__NONE__';
			_instance     = null;
			_loadedForMod = null;
			_instance     = _load(curMod);
			_loadedForMod = curMod;

			funkin.gameplay.notes.NoteSkinSystem.forceReinit();
			funkin.gameplay.notes.NoteSkinSystem.init();
		};
	}

	// ─── Save ────────────────────────────────────────────────────────────────────

	public function save():Void
	{
		#if sys
		var savePath:String;
		final modRoot = ModManager.modRoot();

		if (modRoot != null)
		{
			final dir = '$modRoot/data/config';
			if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
			savePath = '$dir/global.json';
		}
		else
		{
			final dir = 'assets/data/config';
			if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
			savePath = '$dir/global.json';
		}

		try
		{
			var data:Dynamic = {
				ui:               ui,
				noteSkin:         noteSkin,
				noteSplash:       noteSplash,
				holdCoverEnabled: holdCoverEnabled,
				splashesEnabled: splashesEnabled,
				holdCoverSkin:    holdCoverSkin
			};
			// Solo serializar campos no-default para mantener el JSON limpio
			if (windowTitle        != null) data.windowTitle        = windowTitle;
			if (discordClientId    != null) data.discordClientId    = discordClientId;
			if (discordLargeImageKey  != null) data.discordLargeImageKey  = discordLargeImageKey;
			if (discordLargeImageText != null) data.discordLargeImageText = discordLargeImageText;
			if (discordMenuDetails != null) data.discordMenuDetails = discordMenuDetails;
			if (scrollSpeed  > 0)  data.scrollSpeed  = scrollSpeed;
			if (defaultZoom  > 0)  data.defaultZoom  = defaultZoom;
			if (!ghostTap)         data.ghostTap      = false;
			if (!antiMash)         data.antiMash      = false;
			if (downscroll)        data.downscroll    = true;
			if (middlescroll)      data.middlescroll  = true;
			if (!noteSplashEnabled) data.noteSplashEnabled = false;
			if (freeplayMusicVolume >= 0) data.freeplayMusicVolume = freeplayMusicVolume;

			// stateOverrides — solo serializar si tiene entradas
			if (stateOverrides != null)
			{
				var hasOverrides = false;
				for (_ in stateOverrides) { hasOverrides = true; break; }
				if (hasOverrides)
				{
					var overridesObj:Dynamic = {};
					for (k => v in stateOverrides)
						Reflect.setField(overridesObj, k, v);
					data.stateOverrides = overridesObj;
				}
			}

			File.saveContent(savePath, Json.stringify(data, null, '\t'));
			trace('[GlobalConfig] Guardado en $savePath');
		}
		catch (e)
		{
			trace('[GlobalConfig] Error al guardar en $savePath: $e');
		}
		#else
		trace('[GlobalConfig] save() no disponible en esta plataforma');
		#end
	}

	// ─── Runtime setters (usados desde scripts) ──────────────────────────────────
	// Modifican la instancia en memoria sin tocar el JSON en disco.
	// Se aplican automáticamente a los subsistemas correspondientes.

	/**
	 * Setea cualquier campo del GlobalConfig en runtime desde un script.
	 * El cambio es inmediato y se aplica a los subsistemas relevantes.
	 *
	 * Campos soportados: ui, noteSkin, noteSplash, holdCoverEnabled, holdCoverSkin,
	 *   windowTitle, discordClientId, discordLargeImageKey, discordLargeImageText,
	 *   discordMenuDetails, scrollSpeed, defaultZoom, ghostTap, antiMash,
	 *   downscroll, middlescroll, noteSplashEnabled, freeplayMusicVolume.
	 */
	public static function set(field:String, value:Dynamic):Void
	{
		final cfg = instance;
		Reflect.setField(cfg, field, value);
		_runtimeOverrides.set(field, value);

		// Aplicar side-effects según el campo
		switch (field)
		{
			case 'noteSkin', 'noteSplash':
				_applyToSkinSystem(cfg);
			case 'windowTitle':
				applyWindowTitle();
			case 'discordClientId', 'discordLargeImageKey', 'discordLargeImageText', 'discordMenuDetails':
				applyDiscord();
			default:
		}
		trace('[GlobalConfig] Runtime set: $field = $value');
	}

	/** Aplica el windowTitle actual a la ventana del OS. */
	public static function applyWindowTitle():Void
	{
		final cfg = instance;
		if (cfg.windowTitle == null || cfg.windowTitle.trim() == '') return;
		#if !html5
		final win = lime.app.Application.current?.window;
		if (win != null) win.title = cfg.windowTitle;
		#end
	}

	/**
	 * Aplica la configuración Discord del GlobalConfig al DiscordClient activo.
	 * Solo sobreescribe los campos que están definidos (non-null).
	 */
	public static function applyDiscord():Void
	{
		#if cpp
		final cfg = instance;
		final dc  = data.Discord.DiscordClient;
		if (cfg.discordClientId      != null) dc.activeClientId       = cfg.discordClientId;
		if (cfg.discordLargeImageKey  != null) dc.activeLargeImageKey  = cfg.discordLargeImageKey;
		if (cfg.discordLargeImageText != null) dc.activeLargeImageText = cfg.discordLargeImageText;
		if (cfg.discordMenuDetails    != null) dc.activeMenuDetails    = cfg.discordMenuDetails;
		trace('[GlobalConfig] Discord applied');
		#end
	}
}
