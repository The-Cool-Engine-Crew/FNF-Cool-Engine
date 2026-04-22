package funkin.gameplay.objects.character;

import flixel.FlxG;
import animationdata.FunkinSprite;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import funkin.scripting.HScriptInstance;
import funkin.scripting.ScriptHandler;
import mods.ModManager;
#if sys
import sys.FileSystem;
import sys.io.File;
import haxe.Json;
#end

using StringTools;

/**
 * HealthIcon v2 — icono de salud con soporte de scripts y animaciones custom.
 *
 * ─── Formato del icono ──────────────────────────────────────────────────────
 *
 *  LEGACY (spritesheet horizontal, 150×150 por frame):
 *    icons/icon-bf.png        →  [normal][losing]          (2 frames)
 *    icons/icon-bf.png        →  [normal][losing][winning] (3 frames)
 *
 *  ANIMADO (atlas Sparrow):
 *    icons/icon-bf.png  +  icons/icon-bf.xml
 *    Las animaciones deben llamarse exactamente: "normal", "losing", "winning"
 *    Si faltan "losing" o "winning", se hace fallback a "normal".
 *
 *  JSON DE CONFIGURACIÓN (opcional, máxima flexibilidad):
 *    icons/icon-bf.json
 *    {
 *      "image"      : "icons/icon-bf",   // ruta al atlas/imagen (sin extensión)
 *      "scale"      : 1.0,               // escala base del icono
 *      "flipX"      : false,             // voltear por defecto (ignorado si isPlayer)
 *      "antialias"  : true,
 *      "animations" : {
 *        "normal"  : { "prefix": "icon normal",  "fps": 24, "loop": true  },
 *        "losing"  : { "prefix": "icon losing",  "fps": 24, "loop": true  },
 *        "winning" : { "prefix": "icon winning", "fps": 24, "loop": false }
 *      },
 *      "offsets" : {
 *        "normal"  : [0, 0],
 *        "losing"  : [0, 0],
 *        "winning" : [0, 0]
 *      }
 *    }
 *
 * ─── Scripts de mod ─────────────────────────────────────────────────────────
 *
 *  Rutas buscadas (primera que exista):
 *    mods/{mod}/scripts/healthicons/{char}.hx
 *    mods/{mod}/characters/{char}/healthicon.hx
 *    assets/scripts/healthicons/{char}.hx
 *    assets/characters/{char}/healthicon.hx
 *
 *  Variables disponibles en el script:
 *    `icon`     → esta instancia de HealthIcon
 *    `char`     → nombre del personaje cargado
 *    `isPlayer` → bool
 *
 *  Callbacks llamados:
 *    onCreate()
 *    onUpdate(elapsed)
 *    onStateChange(newState, oldState)   → "normal" | "losing" | "winning"
 *    onBeatHit(beat)
 *    onDestroy()
 */
@:keep
class HealthIcon extends FunkinSprite
{
	// ── pública ──────────────────────────────────────────────────────────────

	/** Sprite al que seguir (p.ej. la barra de salud). */
	public var sprTracker:flixel.FlxSprite;

	/** Nombre del personaje actualmente cargado. */
	public var characterName(default, null):String = '';

	/** Estado actual: "normal" | "losing" | "winning". */
	public var currentState(default, null):String = 'normal';

	/** Permite que scripts anulen el flip automático isPlayer. */
	public var flipOverride:Null<Bool> = null;

	/** Offset de posición relativo a sprTracker (por defecto 10, -30). */
	public var trackerOffsetX:Float = 10;

	public var trackerOffsetY:Float = -30;

	/** Offset adicional por animación (leído del JSON si existe). */
	public var animOffsets:Map<String, Array<Float>> = [];

	// ── privada ───────────────────────────────────────────────────────────────
	var _isPlayer:Bool = false;
	var _isAnimated:Bool = false; // true → atlas sparrow
	var _script:Null<HScriptInstance> = null;
	var _iconConfig:Null<Dynamic> = null;
	/** Script Lua opcional (assets/characters/scripts/{char}/healthicon/). */
	#if (LUA_ALLOWED && linc_luajit)
	var _luaScript:Null<funkin.scripting.RuleScriptInstance> = null;
	#end

	// ── constructor ──────────────────────────────────────────────────────────

	public function new(char:String = 'bf', isPlayer:Bool = false)
	{
		super();
		updateIcon(char, isPlayer);
	}

	// ── API pública ───────────────────────────────────────────────────────────

	/**
	 * Carga o recarga el icono para un personaje.
	 * Puede llamarse en runtime sin recrear el objeto.
	 */
	public function updateIcon(char:String, isPlayer:Bool = false):Void
	{
		final _framesAlive = frames != null
			&& frames.parent != null
			&& frames.parent.bitmap != null;
		if (char == characterName && isPlayer == _isPlayer && _framesAlive)
		{
			flipX = flipOverride ?? isPlayer;
			return;
		}

		// Limpiar estado anterior
		_destroyScript();
		animation.destroyAnimations();
		animOffsets.clear();
		_iconConfig = null;
		_isAnimated = false;
		currentState = 'normal';

		characterName = char;
		_isPlayer = isPlayer;

		_loadIcon(char);
		_loadScript(char);

		flipX = flipOverride ?? isPlayer;
		scrollFactor.set();

		animation.play('normal');
	}

	/**
	 * Cambia el estado visual del icono.
	 * @param state  "normal" | "losing" | "winning"
	 */
	public function setState(state:String):Void
	{
		if (state == currentState)
			return;

		var oldState = currentState;
		currentState = state;

		// Notificar script HScript del icono
		if (_script != null)
		{
			var cancelled = _script.callBool('onStateChange', [state, oldState]);
			if (cancelled)
				return;
		}

		// Notificar script Lua del icono
		#if (LUA_ALLOWED && linc_luajit)
		if (_luaScript != null)
			_luaScript.call('onStateChange', [state, oldState]);
		#end

		// Notificar char scripts del personaje en gameplay
		ScriptHandler.callOnCharacterScripts(characterName, 'onHealthIconStateChange', [state, oldState]);

		_playAnim(state);

		// Aplicar offset si existe
		if (animOffsets.exists(state))
		{
			var off = animOffsets.get(state);
			offset.set(off[0], off[1]);
		}
		else
		{
			offset.set(0, 0);
		}
	}

	/** Llamado por el gameplay en cada beat. */
	public function beatHit(beat:Int):Void
	{
		if (_script != null)
			_script.call('onBeatHit', [beat]);
		#if (LUA_ALLOWED && linc_luajit)
		if (_luaScript != null)
			_luaScript.call('onBeatHit', [beat]);
		#end
		ScriptHandler.callOnCharacterScripts(characterName, 'onHealthIconBeatHit', [beat]);
	}

	// ── update ────────────────────────────────────────────────────────────────

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (sprTracker != null)
			setPosition(sprTracker.x + sprTracker.width + trackerOffsetX, sprTracker.y + trackerOffsetY);

		if (_script != null)
			_script.call('onUpdate', [elapsed]);
		#if (LUA_ALLOWED && linc_luajit)
		if (_luaScript != null)
			_luaScript.call('onUpdate', [elapsed]);
		#end
	}

	// ── destroy ───────────────────────────────────────────────────────────────

	override function destroy()
	{
		_destroyScript();
		super.destroy();
	}

	// ══════════════════════════════════════════════════════════════════════════
	//  Carga del icono
	// ══════════════════════════════════════════════════════════════════════════

	function _loadIcon(char:String):Void
	{
		// 1 · Buscar JSON de config
		var jsonPath = _resolveAsset('icons/icon-$char.json');
		if (jsonPath == null)
			jsonPath = _resolveAsset('icons/$char.json');

		if (jsonPath != null)
		{
			_loadFromJson(jsonPath);
			return;
		}

		// 2 · Atlas animado (XML sparrow)
		var atlasXml = _resolveAsset('icons/icon-$char.xml');
		if (atlasXml == null)
			atlasXml = _resolveAsset('icons/$char.xml');

		if (atlasXml != null)
		{
			var imgKey = atlasXml.endsWith('.xml') ? atlasXml.substr(0, atlasXml.length - 4) : atlasXml;
			// Strip full path to get logical key for Paths
			var logicalKey = _pathToLogicalKey(imgKey);
			_loadAnimatedAtlas(logicalKey);
			return;
		}

		// 3 · Spritesheet legacy 150×150
		_loadLegacySheet(char);
	}

	// ── JSON config ───────────────────────────────────────────────────────────

	function _loadFromJson(jsonPath:String):Void
	{
		#if sys
		var raw:String;
		try
		{
			raw = File.getContent(jsonPath);
		}
		catch (e)
		{
			_loadLegacySheet(characterName);
			return;
		}

		var cfg:Dynamic;
		try
		{
			cfg = Json.parse(raw);
		}
		catch (e)
		{
			FlxG.log.warn('[HealthIcon] JSON inválido ($jsonPath): $e');
			_loadLegacySheet(characterName);
			return;
		}

		_iconConfig = cfg;

		var imgKey:String = cfg.image != null ? cfg.image : 'icons/icon-$characterName';
		var isAtlas = (cfg.animations != null);

		if (isAtlas)
		{
			_loadAnimatedAtlas(imgKey, cfg.animations);
		}
		else
		{
			var graphic = _getGraphicForKey(imgKey);
			if (graphic == null)
			{
				_loadLegacySheet(characterName);
				return;
			}
			antialiasing = cfg.antialias != false;
			loadGraphic(graphic, true, 150, 150);
			_addLegacyAnims(Math.floor(graphic.width / 150));
		}

		if (cfg.scale != null)
		{
			scale.set(cfg.scale, cfg.scale);
			updateHitbox();
		}
		if (cfg.offsets != null)
		{
			for (state in ['normal', 'losing', 'winning'])
			{
				var o:Dynamic = Reflect.field(cfg.offsets, state);
				if (o != null)
					animOffsets.set(state, [o[0], o[1]]);
			}
		}
		#else
		_loadLegacySheet(characterName);
		#end
	}

	// ── Atlas animado ─────────────────────────────────────────────────────────

	function _loadAnimatedAtlas(imgKey:String, ?animDefs:Dynamic):Void
	{
		var atlas:FlxAtlasFrames = null;
		try
		{
			atlas = Paths.getSparrowAtlas(imgKey);
		}
		catch (e)
		{
		}

		if (atlas == null)
		{
			_loadLegacySheet(characterName);
			return;
		}

		antialiasing = true;
		frames = atlas;
		_isAnimated = true;

		if (animDefs != null)
		{
			// JSON con definiciones explícitas
			for (state in ['normal', 'losing', 'winning'])
			{
				var def:Dynamic = Reflect.field(animDefs, state);
				if (def == null)
					continue;
				var fps:Int = def.fps != null ? Std.int(def.fps) : 24;
				var loop:Bool = def.loop != null ? def.loop : false;
				var prefix:String = def.prefix != null ? def.prefix : state;
				animation.addByPrefix(state, prefix, fps, loop);
			}
		}
		else
		{
			// Sin JSON: usar prefijos por nombre de estado directamente
			for (state in ['normal', 'losing', 'winning'])
				animation.addByPrefix(state, state, 24, false);
		}

		// Fallbacks: si falta "losing" o "winning", usar "normal"
		for (state in ['losing', 'winning'])
			if (animation.getByName(state) == null && animation.getByName('normal') != null)
				animation.addByPrefix(state, 'normal', 24, false);
	}

	// ── Spritesheet legacy ────────────────────────────────────────────────────

	function _loadLegacySheet(char:String):Void
	{
		var iconKey = 'icons/icon-$char';
		var graphic = _getGraphicForKey(iconKey);

		// Psych: icono sin prefijo "icon-"
		if (graphic == null)
			graphic = _getGraphicForKey('icons/$char');

		// Fallback al icono genérico
		if (graphic == null)
			graphic = _getGraphicForKey('icons/icon-face');

		if (graphic == null)
		{
			FlxG.log.warn('[HealthIcon] No se encontró ningún icono para "$char" — usando gráfico vacío.');
			makeGraphic(150, 150, 0x00000000);
			return;
		}

		antialiasing = true;
		loadGraphic(graphic, true, 150, 150);
		_addLegacyAnims(Math.floor(graphic.width / 150));
	}

	function _addLegacyAnims(frameCount:Int):Void
	{
		if (frameCount >= 3)
		{
			animation.add('normal', [0], 0, false);
			animation.add('losing', [1], 0, false);
			animation.add('winning', [2], 0, false);
		}
		else if (frameCount == 2)
		{
			animation.add('normal', [0], 0, false);
			animation.add('losing', [1], 0, false);
			animation.add('winning', [0], 0, false);
		}
		else
		{
			animation.add('normal', [0], 0, false);
			animation.add('losing', [0], 0, false);
			animation.add('winning', [0], 0, false);
		}
	}

	// ── helpers ───────────────────────────────────────────────────────────────

	function _playAnim(state:String):Void
	{
		var target = animation.getByName(state) != null ? state : 'normal';
		animation.play(target);
	}

	function _getGraphicForKey(key:String):Null<FlxGraphic>
	{
		var path = Paths.image(key);

		#if sys
		if (!FileSystem.exists(path))
			return null;
		var g = Paths.getGraphic(key);
		if (g == null)
		{
			try
			{
				var bmp = openfl.display.BitmapData.fromFile(path);
				if (bmp != null)
				{
					g = funkin.cache.PathsCache.instance.getGraphic(path, bmp);
					if (g != null)
						g.persist = true;
				}
			}
			catch (e)
			{
			}
		}
		return g;
		#else
		return FlxG.bitmap.add(path);
		#end
	}

	/** Convierte una ruta de archivo en clave lógica de Paths (sin extensión). */
	function _pathToLogicalKey(path:String):String
	{
		// Si empieza por "assets/", quitar ese prefijo
		if (path.startsWith('assets/'))
			path = path.substr(7);
		// Quitar prefijo "images/" para evitar el doble images/images/ que
		// ocurre cuando Paths.image() vuelve a anteponer "images/" a la clave
		if (path.startsWith('images/'))
			path = path.substr(7);
		// Si empieza por "mods/{mod}/", quitar ese prefijo también
		var modRoot = ModManager.modRoot();
		if (modRoot != null && path.startsWith(modRoot + '/'))
			path = path.substr(modRoot.length + 1);
		// Quitar prefijo "images/" que pueda quedar tras stripping del mod root
		if (path.startsWith('images/'))
			path = path.substr(7);
		return path;
	}

	/**
	 * Resuelve una ruta de asset buscando primero en el mod activo,
	 * luego en assets/.  Devuelve null si no existe.
	 */
	function _resolveAsset(relPath:String):Null<String>
	{
		#if sys
		// mod override — buscar primero sin prefijo images/, luego con él
		var modPath = ModManager.resolveInMod(relPath);
		if (modPath != null)
			return modPath;
		modPath = ModManager.resolveInMod('images/$relPath');
		if (modPath != null)
			return modPath;

		// base assets — sin prefijo images/
		var basePath = 'assets/$relPath';
		if (FileSystem.exists(basePath))
			return basePath;

		// base assets — con prefijo images/ (ubicación estándar de FNF)
		var imagesPath = 'assets/images/$relPath';
		return FileSystem.exists(imagesPath) ? imagesPath : null;
		#else
		return null;
		#end
	}

	// ══════════════════════════════════════════════════════════════════════════
	//  Scripts
	// ══════════════════════════════════════════════════════════════════════════

	function _loadScript(char:String):Void
	{
		#if sys
		// ── HScript ──────────────────────────────────────────────────────────────
		#if HSCRIPT_ALLOWED
		var hxPath = _findHxPath(char);
		if (hxPath != null)
		{
			_script = ScriptHandler.loadScriptNoInit(hxPath, 'healthicon', ['icon' => this, 'char' => char, 'isPlayer' => _isPlayer,]);
			if (_script != null)
			{
				_script.call('onCreate');
				_script.call('postCreate');
				trace('[HealthIcon] HScript cargado para "$char": $hxPath');
			}
		}
		#end

		// ── Lua ───────────────────────────────────────────────────────────────────
		#if (LUA_ALLOWED && linc_luajit)
		var luaPath = _findLuaPath(char);
		if (luaPath != null)
		{
			_luaScript = new funkin.scripting.RuleScriptInstance('healthicon_$char', luaPath);
			_luaScript.set('char', char);
			_luaScript.set('isPlayer', _isPlayer);
			_luaScript.call('onCreate', []);
			trace('[HealthIcon] Lua cargado para "$char": $luaPath');
		}
		#end
		#end
	}

	function _findHxPath(char:String):Null<String>
	{
		#if sys
		final candidates:Array<String> = [];
		final modRoot = ModManager.modRoot();

		// Mod override — varias ubicaciones de mayor a menor prioridad
		if (modRoot != null)
		{
			candidates.push('$modRoot/characters/scripts/$char/healthicon/$char.hx');
			candidates.push('$modRoot/characters/scripts/$char/healthicon/healthicon.hx');
			candidates.push('$modRoot/scripts/healthicons/$char.hx');
			candidates.push('$modRoot/characters/$char/healthicon.hx');
		}

		// Base game
		candidates.push('assets/characters/scripts/$char/healthicon/$char.hx');
		candidates.push('assets/characters/scripts/$char/healthicon/healthicon.hx');
		candidates.push('assets/scripts/healthicons/$char.hx');
		candidates.push('assets/characters/$char/healthicon.hx');

		for (p in candidates)
			if (sys.FileSystem.exists(p))
				return p;
		#end
		return null;
	}

	function _findLuaPath(char:String):Null<String>
	{
		#if sys
		final candidates:Array<String> = [];
		final modRoot = ModManager.modRoot();

		if (modRoot != null)
		{
			candidates.push('$modRoot/characters/scripts/$char/healthicon/$char.lua');
			candidates.push('$modRoot/characters/scripts/$char/healthicon/healthicon.lua');
			candidates.push('$modRoot/scripts/healthicons/$char.lua');
			candidates.push('$modRoot/characters/$char/healthicon.lua');
		}

		candidates.push('assets/characters/scripts/$char/healthicon/$char.lua');
		candidates.push('assets/characters/scripts/$char/healthicon/healthicon.lua');
		candidates.push('assets/scripts/healthicons/$char.lua');
		candidates.push('assets/characters/$char/healthicon.lua');

		for (p in candidates)
			if (sys.FileSystem.exists(p))
				return p;
		#end
		return null;
	}

	function _destroyScript():Void
	{
		if (_script != null)
		{
			_script.call('onDestroy');
			_script.dispose();
			_script = null;
		}
		#if (LUA_ALLOWED && linc_luajit)
		if (_luaScript != null)
		{
			_luaScript.call('onDestroy', []);
			_luaScript.destroy();
			_luaScript = null;
		}
		#end
	}
}
