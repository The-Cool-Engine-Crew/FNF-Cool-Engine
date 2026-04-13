package funkin.gameplay.objects.character;

import animationdata.FunkinSprite;
import flixel.util.FlxColor;
import funkin.data.Conductor;
import haxe.Json;
import sys.io.File;
import sys.FileSystem;

using StringTools;

typedef CharacterData = {
	var path:String;
	var animations:Array<AnimData>;
	var isPlayer:Bool;
	var antialiasing:Bool;
	var scale:Float;
	@:optional var charDeath:String;
	@:optional var flipX:Bool;
	@:optional var isTxt:Bool;
	@:optional var isSpritemap:Bool;
	@:optional var isFlxAnimate:Bool;
	@:optional var spritemapName:String;
	@:optional var healthIcon:String;

	/**
	 * Clave del asset en el portal Discord Developer.
	 * Si es null, se usa `healthIcon` como fallback.
	 * Útil cuando el nombre del personaje no coincide con la clave Discord
	 * (ej: charName 'monster-christmas' → discordIcon 'monster').
	 */
	@:optional var discordIcon:String;

	@:optional var healthBarColor:String;
	@:optional var cameraOffset:Array<Float>;

	/** Offset de posición global del personaje (campo "position" de Psych). Se suma a la posición del stage. */
	@:optional var positionOffset:Array<Float>;

	@:optional var gameOverSound:String;
	@:optional var gameOverMusic:String;
	@:optional var gameOverEnd:String;
	@:optional var gameOverBpm:Float;
	@:optional var gameOverCamFrame:Int;
	@:optional var deathAnimSuffix:String;

	// ── Renderizado 3D ────────────────────────────────────────────────────────

	/**
	 * Tipo de renderizado alternativo.
	 * Si se omite o es null, usa el renderizado 2D estándar (Sparrow/Atlas).
	 *
	 *   "model3d"  → carga un archivo .obj como companion Flx3DSprite
	 *                visible en la posición del personaje; el sprite 2D
	 *                se oculta. Los scripts controlan la animación del modelo.
	 */
	@:optional var renderType:String;

	/**
	 * Nombre del archivo .obj a cargar (sin extensión) cuando renderType = "model3d".
	 * Rutas buscadas:
	 *   mods/{mod}/characters/models/{modelFile}.obj
	 *   assets/characters/models/{modelFile}.obj
	 * Si es null, se usa el nombre del personaje.
	 */
	@:optional var modelFile:String;

	/** Escala del modelo 3D (unidades del mundo 3D → píxeles). Default: 1.0. */
	@:optional var modelScale:Float;

	/** Ancho del render 3D en píxeles. Default: 320. */
	@:optional var modelWidth:Int;

	/** Alto del render 3D en píxeles. Default: 400. */
	@:optional var modelHeight:Int;

	/** Posición Z de la cámara 3D (alejamiento). Default: 5.0. */
	@:optional var modelCamZ:Float;

	/** Offset 2D del sprite 3D respecto a la posición base del personaje [x, y]. */
	@:optional var modelOffset:Array<Float>;
}

// También modificar AnimData para incluir la hoja a la que pertenece:

typedef AnimData = {
	var offsets:Array<Float>;
	var name:String;
	var looped:Bool;
	var framerate:Float;
	var prefix:String;
	@:optional var indices:Array<Int>;
	@:optional var assetPath:String;
	@:optional var renderType:String;

	/**
	 * Voltear horizontalmente SOLO para esta animación, independiente del flipX global.
	 * Útil cuando un sub-atlas tiene el sprite dibujado en la dirección contraria.
	 *
	 * El flipX resultante es: (flipX_global) XOR (flipX_anim).
	 * Ejemplos:
	 *   personaje sin flipX global + anim.flipX=true  → sprite volteado
	 *   personaje con flipX global + anim.flipX=true  → sprite sin voltear (se cancelan)
	 *   personaje con flipX global + anim.flipX=false → sprite volteado (normal)
	 */
	@:optional var flipX:Bool;
}

/**
	* Character — Playable character / NPC with advanced data cache.
	*
	* ─── Cache Improvements (v2) ───────────────────────────────────────────────────

	* • _dataCache — Caches CharacterData (result of JSON.parse) by character name. Eliminates the cost of File.getContent() +

	* JSON.parse() on repeated loads (e.g., same song is played

	repeated, or same character in multiple stages). Parsing

	a ~2 KB JSON file takes ~0.3-1 ms; negligible once,

	but if repeated 20 times in a session, it adds ~15 ms of I/O.

	* • _pathCache — Caches the path resolved by ModCompatLayer for each character.

	* Avoids traversing the compat layer paths on each load.

	* • invalidateCharCache(name) — Invalidates specific entries (mod reload).

	* • clearCharCaches() — Complete clearing.
	*
	* FunkinSprite already caches FlxAtlasFrames → texture assets are not

	duplicated even if the same character is instantiated multiple times.
 */
class Character extends FunkinSprite {
	public var animOffsets:Map<String, Array<Dynamic>>;
	public var debugMode:Bool = false;

	public var stunned:Bool = false;
	public var isPlayer:Bool = false;
	public var curCharacter:String = 'bf';
	public var holdTimer:Float = 0;

	public var healthIcon:String = 'bf';
	public var healthBarColor:FlxColor = FlxColor.fromString("#31B0D1");
	public var cameraOffset:Array<Float> = [0, 0];

	public var characterData:CharacterData;

	/**
	 * Companion Flx3DSprite activo cuando renderType = "model3d".
	 * Null para personajes 2D estándar.
	 * Los scripts pueden acceder a él para animar el modelo:
	 *   character.model3D.scene.objects[0].rotY += elapsed * 2;
	 */
	public var model3D:Null<funkin.graphics.scene3d.Flx3DSprite> = null;

	var danced:Bool = false;

	/** Nombre de la animación del frame anterior — para detectar fin de anim. */
	var _prevAnimName:String = '';

	/** Si la animación estaba terminada en el frame anterior. */
	var _prevAnimDone:Bool = false;

	var _singAnimPrefix:String = "sing";
	var _idleAnim:String = "idle";

	/** flipX base del personaje (sin per-anim flipX). Guardado en characterLoad(). */
	public var _baseFlipX:Bool = false;

	/**
	 * Tabla de reemplazos de animación.
	 * Si se registra "idle" → "idle-alt", cada vez que se intente reproducir
	 * "idle" se reproducirá "idle-alt" en su lugar (si existe).
	 *
	 * Uso desde script:
	 *   character.setAnimReplace("idle", "idle-alt");
	 *   character.setAnimReplace("singLEFT", "singLEFT-alt");
	 *   character.removeAnimReplace("idle");
	 *   character.clearAnimReplacements();
	 */
	public var _animReplacements:Map<String, String> = [];

	// ══════════════════════════════════════════════════════════════════════════
	//  CACHÉS ESTÁTICOS
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Caché de CharacterData parseados.
	 * key → nombre del personaje (p.ej. "bf", "dad", "gf")
	 *
	 * Almacena el Dynamic ya casteado para que clone() sea O(1) mediante
	 * haxe.Json.parse(haxe.Json.stringify(data)) — deep-copy barato.
	 * Esto garantiza que modificar el CharacterData de una instancia no
	 * corrompa el dato cacheado (inmutabilidad lógica).
	 */
	static var _dataCache:Map<String, String> = []; // key → JSON string del data

	/**
	 * Caché de rutas resueltas por ModCompatLayer.
	 * key → nombre del personaje, value → path absoluto al JSON
	 */
	static var _pathCache:Map<String, String> = [];

	/**
	 * Pool de personajes precacheados.
	 *
	 * Cada entrada es un Character "dummy" creado durante la fase de carga
	 * de la canción. Mantenerlos vivos (en lugar de destruirlos) es esencial:
	 * mientras el dummy existe, sus atlases tienen destroyOnNoUse = false,
	 * lo que garantiza que el BitmapData permanezca en VRAM hasta el momento
	 * en que el swap real ocurre.
	 *
	 * Sin este pool, releaseTrackedAtlases() en destroy() pondría
	 * destroyOnNoUse = true y el GC de Flixel podría liberar la textura
	 * entre el precacheo y el evento Change Character → re-upload a GPU → lag.
	 *
	 * Ciclo de vida:
	 *   1. precacheCharacter(name) → crea dummy y lo guarda aquí.
	 *   2. reloadCharacter(name)   → carga usando el caché caliente,
	 *                                luego destruye el dummy del pool.
	 *   3. releasePrecachePool()   → limpia todo al terminar la canción.
	 */
	static var _precachePool:Map<String, Character> = [];

	/** Invalida las entradas de un personaje específico (recarga de mod). */
	public static function invalidateCharCache(charName:String):Void {
		_dataCache.remove(charName);
		_pathCache.remove(charName);
		FunkinSprite.invalidateCache('char_sparrow:$charName');
		FunkinSprite.invalidateCache('char_packer:$charName');
		// Si había un dummy en el pool, destruirlo también
		final pooled = _precachePool.get(charName);
		if (pooled != null) {
			_precachePool.remove(charName);
			pooled.destroy();
		}
		trace('[Character] Cache invalidado para: $charName');
	}

	/** Limpia todos los cachés de Character, incluyendo el pool de precacheo. */
	public static function clearCharCaches():Void {
		releasePrecachePool();
		_dataCache.clear();
		_pathCache.clear();
		trace('[Character] Todos los cachés de Character limpiados.');
	}

	/**
	 * Destruye todos los dummies del pool y limpia la tabla.
	 * Llamar al terminar la canción (EventManager.clear) para liberar
	 * la VRAM reservada por personajes que no llegaron a usarse.
	 */
	public static function releasePrecachePool():Void {
		var count = 0;
		for (_ => dummy in _precachePool) {
			dummy.destroy();
			count++;
		}
		_precachePool.clear();
		if (count > 0)
			trace('[Character] Pool liberado: $count dummies destruidos.');
	}

	/**
	 * Precachea un personaje SIN añadirlo al stage ni a ninguna cámara,
	 * manteniendo sus assets PINNED en VRAM hasta que el swap real ocurra.
	 *
	 * A diferencia de la versión anterior (que destruía el dummy al instante),
	 * esta implementación guarda el dummy en `_precachePool`. Mientras el dummy
	 * esté vivo, sus atlases tienen `destroyOnNoUse = false`, lo que impide que
	 * el GC de Flixel libere el BitmapData entre el precacheo y el evento.
	 *
	 * Sin este pin, `_frameCache` puede tener la entrada pero
	 * `atlas.parent.bitmap == null` → re-upload a GPU al hacer el swap → lag.
	 *
	 * El dummy se destruye automáticamente en `reloadCharacter()` (una vez que
	 * el personaje real ha tomado la referencia a los frames) o en
	 * `releasePrecachePool()` al finalizar la canción.
	 *
	 * @param name  Nombre del personaje a precachear
	 */
	public static function precacheCharacter(name:String):Void {
		// BUGFIX: se eliminó `|| _dataCache.exists(name)` de la guarda.
		// Antes, si el JSON del personaje ya estaba en _dataCache (cargado en otra
		// canción o como personaje activo), no se creaba el dummy → las texturas
		// NO quedaban pinned en VRAM y podían ser liberadas por el GC de Flixel
		// entre el precacheo y el evento Change Character → GPU re-upload → lag.
		// Ahora siempre se crea el dummy salvo que ya exista uno en el pool.
		if (name == null || name == '' || _precachePool.exists(name))
			return;

		try {
			final dummy = new Character(-99999, -99999, name, false);
			dummy.visible = false;
			dummy.active = false;
			_precachePool.set(name, dummy);
			trace('[Character] Precacheado (pool pinned): "$name"');
		} catch (e:Dynamic) {
			trace('[Character] Precacheo fallido para "$name": $e');
		}
	}

	// ── Constructor ───────────────────────────────────────────────────────────

	public function new(x:Float, y:Float, ?character:String = "bf", ?isPlayer:Bool = false) {
		super(x, y);

		animOffsets = new Map<String, Array<Dynamic>>();
		curCharacter = character;
		this.isPlayer = isPlayer;
		antialiasing = true;

		loadCharacterData(character);

		if (characterData != null) {
			characterLoad(curCharacter);
			trace('[Character] Cargado: $character');
		} else {
			trace('[Character] No se encontraron datos para "$character", usando bf');
			loadCharacterData("bf");
			characterLoad("bf");
		}

		dance();

		// El isPlayer del constructor (pasado por CharacterSlot segun el tipo de slot)
		// es la fuente de verdad en runtime. characterData.isPlayer solo puede promover
		// de false -> true, nunca de true -> false.
		// Necesario para mods Psych: PsychConverter siempre pone isPlayer:false
		// porque no conoce el rol en runtime, y no debe sobreescribir al isPlayer real.
		if (characterData.isPlayer)
			isPlayer = true;

		// flipX del JSON es la única fuente de verdad — isPlayer ya NO voltea el personaje.
		// Para que un personaje mire a la derecha, pon flipX: true en su JSON.
		if (characterData.flipX != null)
			flipX = characterData.flipX;

		// Guardar el flipX base AQUÍ, cuando ya está aplicado el flipX del JSON.
		// playAnim() usará este valor como base para el XOR con AnimData.flipX.
		_baseFlipX = this.flipX;

		// Re-danzar con el _baseFlipX ya correcto para que la pose inicial sea la adecuada.
		dance();
	}

	// ── Carga de datos con caché ──────────────────────────────────────────────

	function loadCharacterData(character:String):Void {
		// ── Caché hit ─────────────────────────────────────────────────────────
		if (_dataCache.exists(character)) {
			try {
				// Deep-copy del JSON cacheado para aislar la instancia
				characterData = cast haxe.Json.parse(_dataCache.get(character));
				applyCharacterDataDefaults(characterData, character);
				return;
			} catch (e:Dynamic) {
				// Si el JSON cacheado está corrupto, invalidar y recargar
				trace('[Character] Cache corrupto para "$character", recargando...');
				_dataCache.remove(character);
			}
		}

		// ── Caché miss: cargar desde disco ────────────────────────────────────
		var jsonPath = _pathCache.get(character);
		if (jsonPath == null) {
			jsonPath = mods.compat.ModCompatLayer.resolveCharacterPath(character);
			_pathCache.set(character, jsonPath);
		}

		try {
			var content:String;
			if (FileSystem.exists(jsonPath))
				content = File.getContent(jsonPath);
			else
				content = lime.utils.Assets.getText(jsonPath);

			characterData = cast mods.compat.ModCompatLayer.loadCharacter(content, character);

			// Guardar en caché como JSON string (deep-copy)
			_dataCache.set(character, haxe.Json.stringify(characterData));

			applyCharacterDataDefaults(characterData, character);

			// ── Hot-reload: registrar path en JsonWatcher ──
			#if sys
			if (mods.ModManager.developerMode)
				funkin.debug.JsonWatcher.watch(jsonPath, 'character', character);
			#end
		} catch (e:Dynamic) {
			trace('[Character] Error cargando datos de "$character": $e');
			characterData = null;
		}
	}

	/** Aplica valores derivados del CharacterData (healthIcon, barColor, etc.) */
	function applyCharacterDataDefaults(data:CharacterData, character:String):Void {
		healthIcon = data.healthIcon != null ? data.healthIcon : character;
		healthBarColor = data.healthBarColor != null ? FlxColor.fromString(data.healthBarColor) : healthBarColor;
		cameraOffset = data.cameraOffset != null ? data.cameraOffset : cameraOffset;
	}

	function characterLoad(character:String):Void {
		// ── Multi-atlas al estilo V-Slice ────────────────────────────────────
		// Recolectamos todos los assetPath únicos por animación.
		// Si alguna animación tiene su propio assetPath, construimos el atlas
		// combinado igual que MultiSparrowCharacter / MultiAnimateAtlasCharacter.
		//
		// El primer path siempre es el path principal (characterData.path).
		// Los sub-paths se añaden en orden de aparición (sin duplicados).
		// Esto permite que BF-holding-GF, Tankman, etc. funcionen
		// sin necesidad de un archivo .sheets externo.

		final mainPath:String = characterData.path;
		final subPaths:Array<String> = [];
		var needsMultiAtlas:Bool = false;

		for (animData in characterData.animations) {
			if (animData.assetPath == null || animData.assetPath == mainPath)
				continue;
			if (subPaths.contains(animData.assetPath))
				continue;
			subPaths.push(animData.assetPath);
			needsMultiAtlas = true;
		}

		if (needsMultiAtlas) {
			// V-Slice style: main primero, subs después.
			// IMPORTANTE: usamos resolveAtlasFolder() que ya sabe buscar en mods/ primero
			// y luego en assets/. Así "tankman/basic" → "mods/base_game/characters/images/tankman/basic"
			// si existe ahí, o "assets/characters/images/tankman/basic" si no.
			// NO construimos el path a mano para evitar ignorar el mod activo.
			final resolveCharAtlas = (p:String) -> {
				// Si ya es un path absoluto resuelto (mods/ o assets/) lo usamos directo
				if (p.startsWith('assets/') || p.startsWith('mods/') || p.startsWith('/'))
					return p;
				// Normalizar a clave relativa a characters/images/
				final charKey = p.startsWith('characters/images/') ? p : 'characters/images/$p';
				// resolveAtlasFolder busca en mods → assets y devuelve el path real con Animation.json
				final resolved = animationdata.FunkinSprite.resolveAtlasFolder(charKey);
				if (resolved != null)
					return resolved;
				// Fallback: devolver como estaba (loadMultiAnimateAtlas lo intentará con assets/)
				return charKey;
			};

			final allPaths:Array<String> = [resolveCharAtlas(mainPath)].concat(subPaths.map(resolveCharAtlas));
			trace('[Character] Multi-atlas para "$curCharacter": ${allPaths.length} atlases → ${allPaths.join(", ")}');
			loadMultiAnimateAtlas(allPaths);
		} else {
			// FunkinSprite auto-detecta Atlas → Sparrow → Packer
			loadCharacterSparrow(mainPath);
		}

		if (isAnimateAtlas)
			trace('[Character] Modo Texture Atlas para "$curCharacter"');
		else
			trace('[Character] Modo Sparrow/Packer para "$curCharacter"');

		for (animData in characterData.animations) {
			var loop:Null<Bool> = animData.looped;
			if (loop == null)
				animData.looped = false;
			var fr:Null<Float> = animData.framerate;
			if (fr == null)
				animData.framerate = 24;
			addAnim(animData.name, animData.prefix, Std.int(animData.framerate), animData.looped,
				(animData.indices != null && animData.indices.length > 0) ? animData.indices : null);

			var fa = isAnimateAtlas ? null : animation.getByName(animData.name);
			if (!isAnimateAtlas && (fa == null || fa.numFrames == 0))
				trace('[Character] WARN: "${animData.name}" 0 frames (prefix="${animData.prefix}")');

			var offX:Null<Float> = animData.offsets[0];
			var offY:Null<Float> = animData.offsets[1];
			if (offX == null)
				animData.offsets[0] = 0;
			if (offY == null)
				animData.offsets[1] = 0;
			addOffset(animData.name, animData.offsets[0], animData.offsets[1]);
		}

		antialiasing = characterData.antialiasing;
		scale.set(characterData.scale, characterData.scale);
		updateHitbox();

		applyCharacterSpecificAdjustments();

		// NOTA: _baseFlipX NO se guarda aquí porque isPlayer y flipX del JSON
		// se aplican DESPUÉS en el constructor. Se guarda allí, tras esas modificaciones.

		if (animOffsets.exists('danceRight'))
			playAnim('danceRight');
		else if (animOffsets.exists('danceLeft'))
			playAnim('danceLeft');
		else if (animOffsets.exists(_idleAnim))
			playAnim(_idleAnim);

		// ── Modelo 3D companion ───────────────────────────────────────────────────
		// renderType: "model3d" → crea un Flx3DSprite que reemplaza visualmente
		// al sprite 2D. El sprite 2D sigue activo para hitbox y posición.
		if (characterData.renderType == 'model3d')
			_initModel3D();
	}

	/** Inicializa el companion Flx3DSprite para personajes con renderType = "model3d". */
	function _initModel3D():Void {
		final modelName = characterData.modelFile ?? curCharacter;
		final mw = characterData.modelWidth != null ? characterData.modelWidth : 320;
		final mh = characterData.modelHeight != null ? characterData.modelHeight : 400;
		final mscale = characterData.modelScale != null ? characterData.modelScale : 1.0;
		final mCamZ = characterData.modelCamZ != null ? characterData.modelCamZ : 5.0;
		final offX = characterData.modelOffset != null && characterData.modelOffset.length > 0 ? characterData.modelOffset[0] : 0.0;
		final offY = characterData.modelOffset != null && characterData.modelOffset.length > 1 ? characterData.modelOffset[1] : 0.0;

		final spr = new funkin.graphics.scene3d.Flx3DSprite(x + offX - mw * 0.5, y + offY - mh * 0.5, mw, mh);
		spr.scrollFactor.set(scrollFactor.x, scrollFactor.y);
		spr.scene.camera.position.set(0, 1, mCamZ);
		spr.scene.camera.target.set(0, 0, 0);
		spr.scene.clearA = 0.0;

		spr.onReady = function() {
			final mesh = funkin.graphics.scene3d.Model3DLoader.loadForCharacter(modelName);
			if (mesh == null) {
				trace('[Character] Modelo 3D "$modelName" no encontrado — usa un script para cargar el mesh manualmente.');
				return;
			}
			final obj3d = new funkin.graphics.scene3d.Flx3DObject();
			obj3d.mesh = mesh;
			obj3d.scaleX = mscale;
			obj3d.scaleY = mscale;
			obj3d.scaleZ = mscale;
			spr.scene.add(obj3d);
			trace('[Character] Modelo 3D "$modelName" listo para "$curCharacter" (${mesh.triangleCount} tri).');
		};

		model3D = spr;
		// Ocultar sprite 2D — el modelo 3D lo reemplaza visualmente
		alpha = 0.0;
		trace('[Character] renderType=model3d inicializado para "$curCharacter".');
	}

	// ── playAnim ──────────────────────────────────────────────────────────────

	override public function playAnim(AnimName:String, Force:Bool = false, Reversed:Bool = false, Frame:Int = 0):Void {
		// ── Reemplazos de animación ────────────────────────────────────────────
		// Si hay un reemplazo registrado Y la animación destino existe, redirigir.
		var _resolved = _animReplacements.get(AnimName);
		if (_resolved != null && animOffsets.exists(_resolved))
			AnimName = _resolved;
		super.playAnim(AnimName, Force, Reversed, Frame);

		// la animación en la lista.
		if (characterData != null) {
			var _animFlipX:Bool = false; // sin override → usar _baseFlipX
			for (anim in characterData.animations) {
				if (anim.name == AnimName) {
					_animFlipX = (anim.flipX == true);
					break;
				}
			}
			this.flipX = _baseFlipX != _animFlipX;
		}

		// ── Aplicar offset con compensación de flipX ──────────────────────────
		// Los offsets se autorean con el sprite en su orientación base (_baseFlipX).
		// Si el flipX actual difiere del base, invertimos offsetX para que el
		// desplazamiento visual resultante sea siempre el que el autor pretendía.
		var daOffset = animOffsets.get(AnimName);

		if (daOffset != null) {
			var ox:Float = daOffset[0];
			var oy:Float = daOffset[1];
			if (this.flipX != _baseFlipX)
				ox = -ox;
			offset.set(ox, oy);
		} else
			offset.set(0, 0);

		#if HSCRIPT_ALLOWED
		funkin.scripting.ScriptHandler._argsAnim[0] = AnimName;
		funkin.scripting.ScriptHandler.callOnCharacterScripts(curCharacter, 'onAnimStart', funkin.scripting.ScriptHandler._argsAnim);
		#end
	}

	// ── Estado de animación ───────────────────────────────────────────────────

	public function getCurAnimName():String
		return animName;

	public function isCurAnimFinished():Bool
		return animFinished;

	public function hasCurAnim():Bool
		return animName != "";

	public function isPlayingSpecialAnim():Bool {
		var name = getCurAnimName();
		if (name == '' || isCurAnimFinished())
			return false;
		if (name.startsWith(_singAnimPrefix))
			return false;
		if (name == _idleAnim)
			return false;
		if (name.startsWith('dance'))
			return false;
		if (name.endsWith('miss'))
			return false;
		if (name == 'firstDeath')
			return false;
		if (name == 'deathLoop')
			return false;
		return true;
	}

	// ── Update ────────────────────────────────────────────────────────────────

	override function update(elapsed:Float) {
		super.update(elapsed);

		if (!hasCurAnim())
			return;

		// En modo debug no se hace nada automático con las animaciones
		// (ni idle, ni sing timeout, ni dance) — el usuario controla todo.
		if (debugMode)
			return;

		var curAnimName = getCurAnimName();
		var curAnimDone = isCurAnimFinished();

		// ── Detectar fin de animación y disparar onAnimEnd ────────────────────
		// Condición: la animación acaba de terminar (esta frame está done, la anterior no)
		// O: la animación cambió mientras estaba terminada (animación no-looped completada)
		#if HSCRIPT_ALLOWED
		if (curAnimDone && (!_prevAnimDone || curAnimName != _prevAnimName)) {
			funkin.scripting.ScriptHandler._argsAnim[0] = curAnimName;
			funkin.scripting.ScriptHandler._argsAnim[1] = null;
			funkin.scripting.ScriptHandler.callOnCharacterScripts(curCharacter, 'onAnimEnd', funkin.scripting.ScriptHandler._argsAnim);
		}
		#end
		_prevAnimName = curAnimName;
		_prevAnimDone = curAnimDone;

		if (!isPlayer) {
			if (curAnimName.startsWith(_singAnimPrefix)) {
				holdTimer += elapsed;
				var dadVar:Float = (curCharacter == 'dad') ? 6.1 : 4.0;
				if (holdTimer >= Conductor.stepCrochet * dadVar * 0.001) {
					holdTimer = 0;
					#if HSCRIPT_ALLOWED
					if (!funkin.scripting.ScriptHandler.callOnCharacterScriptsReturn(curCharacter, 'overrideSingTimeout',
						funkin.scripting.ScriptHandler._argsEmpty))
						returnToIdle();
					#else
					returnToIdle();
					#end
					#if HSCRIPT_ALLOWED
					funkin.scripting.ScriptHandler._argsAnim[0] = curAnimName;
					funkin.scripting.ScriptHandler._argsAnim[1] = null;
					funkin.scripting.ScriptHandler.callOnCharacterScripts(curCharacter, 'onSingEnd', funkin.scripting.ScriptHandler._argsAnim);
					#end
				}
			} else {
				holdTimer = 0;
				if (curAnimDone) {
					// FIX: No llamar dance() cada frame cuando termina danceLeft/danceRight.
					// danceOnBeat() avanza el ciclo en cada beat. Si llamamos dance() aquí,
					// el personaje cicla danceLeft↔danceRight a 60 fps ignorando la música.
					// Solo relanzar dance() si la animación que terminó NO es ya una dance.
					if (!curAnimName.startsWith('dance'))
						dance();
				}
			}
		} else if (!debugMode) {
			if (curAnimName.startsWith(_singAnimPrefix)) {
				holdTimer += elapsed;
				if (holdTimer >= Conductor.stepCrochet * 4 * 0.001) {
					#if HSCRIPT_ALLOWED
					if (!funkin.scripting.ScriptHandler.callOnCharacterScriptsReturn(curCharacter, 'overrideSingTimeout',
						funkin.scripting.ScriptHandler._argsEmpty))
						returnToIdle();
					#else
					returnToIdle();
					#end
					holdTimer = 0;
					#if HSCRIPT_ALLOWED
					funkin.scripting.ScriptHandler._argsAnim[0] = curAnimName;
					funkin.scripting.ScriptHandler._argsAnim[1] = null;
					funkin.scripting.ScriptHandler.callOnCharacterScripts(curCharacter, 'onSingEnd', funkin.scripting.ScriptHandler._argsAnim);
					#end
				}
			} else {
				holdTimer = 0;
				if (curAnimDone) {
					if (curAnimName == 'firstDeath')
						playAnim('deathLoop');
						// FIX: igual que el branch opponent — no ciclar danceLeft↔danceRight
					// a 60fps. Solo llamar returnToIdle() si la anim terminada no es dance.
					else if (!curAnimName.startsWith('dance'))
						returnToIdle();
				}
			}
		}
	}

	// ── Dance ─────────────────────────────────────────────────────────────────

	public function returnToIdle():Void {
		#if HSCRIPT_ALLOWED
		if (funkin.scripting.ScriptHandler.callOnCharacterScriptsReturn(curCharacter, 'overrideDance', funkin.scripting.ScriptHandler._argsEmpty))
			return;
		#end
		var hasDanceAnims = animOffsets.exists('danceLeft') && animOffsets.exists('danceRight');
		if (hasDanceAnims) {
			danced = !danced;
			playAnim(danced ? 'danceRight' : 'danceLeft');
		} else {
			playAnim(_idleAnim);
		}
		#if HSCRIPT_ALLOWED
		funkin.scripting.ScriptHandler.callOnCharacterScripts(curCharacter, 'onReturnToIdle', funkin.scripting.ScriptHandler._argsEmpty);
		#end
	}

	/**
	 * Recarga completamente los datos y visuales de este personaje con un nuevo nombre.
	 * Útil para event scripts (ChangeCharacter.hx) sin necesidad de acceder a métodos privados.
	 * Preserva la posición actual y el flag isPlayer.
	 *
	 * @param newName  Nombre del personaje a cargar (debe existir en assets/characters/)
	 */
	public function reloadCharacter(newName:String):Void {
		if (newName == null || newName == '')
			return;

		// ── GUARD: skip si ya es el personaje activo ──────────────────────────
		// Evita destruir y reconstruir animaciones + recargar assets sin motivo.
		if (newName == curCharacter)
			return;

		final savedX = x;
		final savedY = y;
		final savedPlayer = isPlayer;

		// ── Liberar atlases del personaje anterior ANTES de cargar el nuevo ───
		releaseTrackedAtlases();

		// Borrar animaciones y offsets del personaje anterior
		animOffsets.clear();
		animation.destroyAnimations();

		curCharacter = newName;
		loadCharacterData(newName); // hit de _dataCache (O(1))
		characterLoad(newName); // hit de _frameCache con bitmap pinned → sin GPU stall

		// ── Liberar el dummy del pool DESPUÉS de que 'this' ya tomó los frames ─
		// El dummy referenciaba los atlases con destroyOnNoUse=false para mantener
		// el BitmapData en VRAM. Ahora 'this' los referencia a través de
		// _usedAtlases, así que es seguro destruir el dummy sin perder la textura.
		final pooled = Character._precachePool.get(newName);
		if (pooled != null) {
			Character._precachePool.remove(newName);
			pooled.destroy();
		}

		isPlayer = savedPlayer;
		setPosition(savedX, savedY);
	}

	public function dance():Void {
		if (!debugMode && !isPlayingSpecialAnim()) {
			#if HSCRIPT_ALLOWED
			if (funkin.scripting.ScriptHandler.callOnCharacterScriptsReturn(curCharacter, 'overrideDance', funkin.scripting.ScriptHandler._argsEmpty))
				return;
			#end

			var hasDanceAnims = animOffsets.exists('danceLeft') && animOffsets.exists('danceRight');

			switch (curCharacter) {
				default:
					if (hasDanceAnims) {
						if (!hasCurAnim() || !getCurAnimName().startsWith(_singAnimPrefix)) {
							danced = !danced;
							playAnim(danced ? 'danceRight' : 'danceLeft');
						}
					} else {
						if (!hasCurAnim() || !getCurAnimName().startsWith(_singAnimPrefix))
							playAnim(_idleAnim);
					}
			}

			#if HSCRIPT_ALLOWED
			funkin.scripting.ScriptHandler.callOnCharacterScripts(curCharacter, 'onDance', funkin.scripting.ScriptHandler._argsEmpty);
			#end
		}
	}

	// ── Ajustes específicos ───────────────────────────────────────────────────

	function applyCharacterSpecificAdjustments():Void {
		switch (curCharacter) {
			case 'bf-pixel-enemy':
				width -= 100;
				height -= 100;
		}
	}

	function flipAnimations():Void {
		if (isAnimateAtlas)
			return;

		if (animation.getByName('singRIGHT') != null && animation.getByName('singLEFT') != null) {
			var oldRight = animation.getByName('singRIGHT').frames;
			animation.getByName('singRIGHT').frames = animation.getByName('singLEFT').frames;
			animation.getByName('singLEFT').frames = oldRight;
		}
		if (animation.getByName('singRIGHTmiss') != null && animation.getByName('singLEFTmiss') != null) {
			var oldMiss = animation.getByName('singRIGHTmiss').frames;
			animation.getByName('singRIGHTmiss').frames = animation.getByName('singLEFTmiss').frames;
			animation.getByName('singLEFTmiss').frames = oldMiss;
		}
	}

	// ── API pública ───────────────────────────────────────────────────────────

	public function addOffset(name:String, x:Float = 0, y:Float = 0):Void
		animOffsets[name] = [x, y];

	public function getAnimationList():Array<String> {
		var list:Array<String> = [];
		for (a in animOffsets.keys())
			list.push(a);
		return list;
	}

	public function hasAnimation(name:String):Bool
		return animOffsets.exists(name);

	public function getOffset(name:String):Array<Dynamic>
		return animOffsets.get(name);

	public function updateOffset(name:String, x:Float, y:Float):Void {
		if (animOffsets.exists(name))
			animOffsets.set(name, [x, y]);
	}

	// ── Reemplazos de animación ───────────────────────────────────────────────

	/**
	 * Registra un reemplazo de animación.
	 * Cada vez que se intente reproducir `from`, se reproducirá `to` en su lugar
	 * (siempre que `to` exista; si no existe, se reproduce `from` normalmente).
	 *
	 * Ejemplos:
	 *   character.setAnimReplace("idle", "idle-alt");
	 *   character.setAnimReplace("singLEFT", "singLEFT-alt");
	 *
	 * @param from  Nombre de la animación original a interceptar
	 * @param to    Nombre de la animación destino
	 */
	public function setAnimReplace(from:String, to:String):Void
		_animReplacements.set(from, to);

	/**
	 * Elimina el reemplazo de una animación específica.
	 * @param from  Animación cuyo reemplazo se quiere quitar
	 */
	public function removeAnimReplace(from:String):Void
		_animReplacements.remove(from);

	/**
	 * Elimina todos los reemplazos de animación registrados.
	 */
	public function clearAnimReplacements():Void
		_animReplacements.clear();

	/**
	 * Devuelve el nombre real que se reproducirá al pedir `animName`,
	 * teniendo en cuenta los reemplazos activos.
	 * Útil para scripts que quieren saber qué animación va a salir.
	 */
	public function resolveAnimName(animName:String):String {
		var _r = _animReplacements.get(animName);
		return (_r != null && animOffsets.exists(_r)) ? _r : animName;
	}

	// ── Destruir ──────────────────────────────────────────────────────────────

	override function destroy():Void {
		// Liberar los atlases cargados con destroyOnNoUse=false (al estilo V-Slice destroy())
		releaseTrackedAtlases();

		if (animOffsets != null) {
			animOffsets.clear();
			animOffsets = null;
		}
		characterData = null;

		// Destruir el companion 3D si existe
		if (model3D != null) {
			model3D.destroy();
			model3D = null;
		}

		super.destroy();
	}
}
