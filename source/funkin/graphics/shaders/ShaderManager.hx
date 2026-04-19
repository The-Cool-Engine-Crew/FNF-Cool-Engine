package funkin.graphics.shaders;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.addons.display.FlxRuntimeShader;
import flixel.system.FlxAssets.FlxShader;
import funkin.data.CameraUtil;
import funkin.graphics.shaders.FunkinRuntimeShader;
import funkin.shaders.BloomShader;
import funkin.shaders.NoteGlowShader;
import mods.ModManager;
import openfl.filters.BitmapFilter;
import openfl.filters.ShaderFilter;
import funkin.graphics.shaders.compat.ShaderCompat;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/**
 * ShaderManager — Sistema unificado de shaders para Cool Engine.
 *
 * ─── DOS RESPONSABILIDADES EN UNA CLASE ──────────────────────────────────────
 *
 *  1. EFECTOS DE CÁMARA (bloom, filmGrain)
 *     Llamar init() UNA VEZ desde CacheState.goToTitle().
 *     Se engancha a postStateSwitch y re-aplica automáticamente en cada estado.
 *
 *       ShaderManager.init();
 *       ShaderManager.applyMenuPreset();
 *
 *  2. SHADERS RUNTIME (archivo .frag / inline GLSL) para sprites y cámaras
 *     Carga shaders desde assets/shaders/ o mods, los aplica a sprites
 *     y permite controlar uniforms en tiempo real.
 *
 *       ShaderManager.applyShader(mySprite, 'wave');
 *       ShaderManager.setShaderParam('wave', 'uTime', elapsed);
 *       ShaderManager.applyShaderToCamera('chromaShift');
 *
 *  3. FLECHAS (NoteGlowShader)
 *       ShaderManager.applyToNote(arrowSprite, noteData % 4);
 *
 * @author  Cool Engine Team
 * @since   0.7.0
 */
class ShaderManager
{
	// ═══════════════════════════════════════════════════════════════════════════
	// PARTE 1 — EFECTOS DE CÁMARA
	// ═══════════════════════════════════════════════════════════════════════════

	public static var bloom     (default, null):BloomShader;

	/** Efectos de cámara activos. Se persiste en FlxG.save.data.shadersEnabled */
	public static var enabled(default, null):Bool = true;

	public static var initialized(default, null):Bool = false;

	static var _time:Float  = 0.0;
	static var _hooked:Bool = false;

	// ─── Init ─────────────────────────────────────────────────────────────────

	/**
	 * Inicializar UNA VEZ en CacheState.goToTitle().
	 * Combina la inicializacion de efectos de camara + escaneo de shaders runtime.
	 *
	 * En movil (Android / iOS), new BloomShader() lanza la compilacion GLSL
	 * en el driver de la GPU. En GPUs Mali y Adreno lentas esto bloquea el hilo
	 * principal 2-3 s. Para evitar el freeze visible, la creacion de shaders de
	 * camara se difiere al primer frame siguiente via FlxTimer.wait(0): en ese
	 * momento el usuario ya esta en la pantalla de carga de TitleState y el
	 * bloqueo es imperceptible. applyToCamera() es null-safe mientras bloom==null.
	 */
	public static function init():Void
	{
		// ── Efectos de camara ──────────────────────────────────────────────────
		if (FlxG.save.data.shadersEnabled != null)
			enabled = (FlxG.save.data.shadersEnabled == true);
		else
			enabled = true;

		#if (mobileC || android || ios)
		flixel.util.FlxTimer.wait(0, function()
		{
			_createCameraShaders();
			applyToCamera();
			scanShaders(); // FIX: diferido para evitar freeze en "100% Ready!"
		});
		#else
		_createCameraShaders();
		scanShaders();
		#end

		if (!_hooked)
		{
			_hooked = true;
			FlxG.signals.postStateSwitch.add(_onStateSwitch);
		}

		initialized = true;

		final prevCallback = ModManager.onModChanged;
		ModManager.onModChanged = function(modId:String)
		{
			if (prevCallback != null) prevCallback(modId);
			reloadAllShaders();
		};

		trace('[ShaderManager] Inicializado. enabled=$enabled, ${Lambda.count(shaderPaths)} shaders runtime disponibles');
		applyToCamera(); // no-op seguro si bloom todavia es null (movil deferred)
	}

	// ─── Toggle ───────────────────────────────────────────────────────────────

	/** Activa/desactiva los efectos de cámara y guarda la preferencia. */
	public static function setEnabled(value:Bool):Void
	{
		enabled = value;
		FlxG.save.data.shadersEnabled = value;
		FlxG.save.flush();
		applyToCamera();
		trace('[ShaderManager] Efectos de cámara ${enabled ? "ON" : "OFF"}');
	}

	// ─── Cámara ───────────────────────────────────────────────────────────────

	/**
	 * Aplica (o elimina) los efectos de cámara (bloom, filmGrain).
	 * Null-safe: si bloom es null (móvil deferred todavía no compilado), limpia
	 * los filtros y sale sin crashear.
	 * @param cam  null = FlxG.camera
	 */
	public static function applyToCamera(?cam:FlxCamera):Void
	{
		if (!initialized) init();
		if (cam == null) cam = FlxG.camera;

		if (!enabled || bloom == null)
		{
			CameraUtil.clearFilters(cam);
			return;
		}

		final filters:Array<BitmapFilter> = [
			new ShaderFilter(bloom)
		];
		CameraUtil.setFilters(cam, filters);
	}

	// ─── Update ───────────────────────────────────────────────────────────────

	/** Call from MusicBeatState.update(elapsed). Animates camera effects and script shaders. */
	public static function update(elapsed:Float):Void
	{
		if (!initialized || !enabled) return;
		_time += elapsed;

		// Update all active script shaders
		for (ss in scriptShaders) ss.update(elapsed);
	}

	// ─── Presets ──────────────────────────────────────────────────────────────

	public static function applyMenuPreset():Void
	{
		if (!initialized) return;
		if (bloom != null)     { bloom.threshold  = 0.60; bloom.intensity = 0.50; }
	}

	public static function applyGameplayPreset():Void
	{
		if (!initialized) return;
		if (bloom != null)     { bloom.threshold  = 0.50; bloom.intensity = 0.80; }
	}

	public static function onResize(w:Float, h:Float):Void
	{
		if (bloom != null) bloom.setResolution(w, h);
	}

	// ─── Flechas ──────────────────────────────────────────────────────────────

	/**
	 * Aplica NoteGlowShader a una flecha. Si los efectos están OFF, pone null.
	 * @param sprite     FlxSprite de la flecha
	 * @param direction  0=LEFT  1=DOWN  2=UP  3=RIGHT
	 */
	public static function applyToNote(sprite:FlxSprite, direction:Int):Void
	{
		sprite.shader = enabled ? NoteGlowShader.forDirection(direction % 4) : null;
	}

	/** Quita el shader de una flecha. */
	public static inline function removeFromNote(sprite:FlxSprite):Void
		sprite.shader = null;

	// ─── Internos cámara ──────────────────────────────────────────────────────

	static function _createCameraShaders():Void
	{
		bloom     = new BloomShader(0.55, 0.65, 1.8);
	}

	static function _onStateSwitch():Void
	{
		// FIX Bug 11: _spriteToInstance, _liveInstances, _cameraOverlayMap and
		// _pendingParams were never cleared between states. Any FlxSprite from
		// PlayState that had a runtime shader applied (via script) remained rooted
		// here, preventing the GC from reclaiming the sprite, the Character that
		// owns it, and the BitmapData of its texture. Clear all four maps first,
		// then re-apply bloom/menu settings on the next frame via the deferred timer.
		_spriteToInstance.clear();
		_liveInstances.clear();
		_cameraOverlayMap.clear();
		_pendingParams.clear();

		// FIX: apply applyMenuPreset() (which includes applyToCamera()) rather than
		// only applyToCamera(). This ensures bloom parameters for menu states
		// (threshold=0.60, intensity=0.50) are restored after every state switch,
		// including the first transition from CacheState.
		flixel.util.FlxTimer.wait(0, function() {
			applyMenuPreset();
			applyToCamera();
		});
	}


	// ═══════════════════════════════════════════════════════════════════════════
	// PARTE 2 — SHADERS RUNTIME (sprites / cámaras / mods)
	// ═══════════════════════════════════════════════════════════════════════════

	public static var shaders:Map<String, CustomShader>    = new Map();
	public static var shaderPaths:Map<String, String>      = new Map();

	/** Vertex shader paths (.vert siblings). */
	public static var vertPaths:Map<String, String>        = new Map();

	/** Script shaders — .lua / .hx files in the shaders folder. */
	public static var scriptShaders:Map<String, funkin.scripting.ScriptShader> = new Map();

	static var _liveInstances:Map<String, Array<FunkinRuntimeShader>>                         = new Map();
	static var _spriteToInstance:Map<FlxSprite, {name:String, instance:FunkinRuntimeShader}> = new Map();
	static var _pendingParams:Map<String, Map<String, Dynamic>>                               = new Map();
	static var _lastAppliedParams:Map<String, Map<String, Dynamic>>                           = new Map();

	/**
	 * Overlays de cámara gestionados internamente por applyShaderToCamera().
	 * Clave: "$shaderName@camId" → FlxSprite overlay.
	 * Permite que removeShaderFromCamera() limpie sin que el stage script
	 * tenga que gestionar el sprite manualmente.
	 */
	static var _cameraOverlayMap:Map<String, FlxSprite> = new Map();

	// ─── Escaneo ──────────────────────────────────────────────────────────────

	public static function scanShaders():Void
	{
		shaderPaths.clear();
		_scanFolder('assets/shaders', null);
		#if sys
		final mods = ModManager.installedMods.copy();
		mods.reverse();
		for (mod in mods)
		{
			if (!ModManager.isEnabled(mod.id)) continue;
			_scanFolder('${ModManager.MODS_FOLDER}/${mod.id}/shaders', mod.id);
		}
		#end
	}

	private static function _scanFolder(folderPath:String, modId:Null<String>):Void
	{
		#if sys
		if (!FileSystem.exists(folderPath) || !FileSystem.isDirectory(folderPath))
		{
			if (modId == null)
				try { FileSystem.createDirectory(folderPath); } catch (e:Dynamic) {}
			return;
		}
		final prefix = modId != null ? '[$modId] ' : '[base] ';
		for (file in FileSystem.readDirectory(folderPath))
		{
			// ── .frag — standard GLSL file ───────────────────────────────────
			if (file.endsWith('.frag'))
			{
				final shaderName = file.substr(0, file.length - 5);
				shaderPaths.set(shaderName, '$folderPath/$file');
				final vertFile = shaderName + '.vert';
				if (FileSystem.exists('$folderPath/$vertFile'))
					vertPaths.set(shaderName, '$folderPath/$vertFile');
				trace('[ShaderManager] Registered ${prefix}$shaderName (GLSL)');
				continue;
			}

			// ── .lua / .hx — script shader ───────────────────────────────────
			final isLua     = file.endsWith('.lua');
			final isHScript = file.endsWith('.hx') || file.endsWith('.hscript');
			if (!isLua && !isHScript) continue;

			final dotIdx     = file.lastIndexOf('.');
			final shaderName = dotIdx >= 0 ? file.substr(0, dotIdx) : file;
			final fullPath   = '$folderPath/$file';

			// Don't overwrite a .frag with the same name — .frag takes priority
			if (shaderPaths.exists(shaderName)) continue;

			final ss = new funkin.scripting.ScriptShader(shaderName, fullPath);
			if (ss.load())
			{
				scriptShaders.set(shaderName, ss);
				// Also register the compiled FunkinRuntimeShader as a CustomShader
				// so the existing applyShader/applyShaderToCamera API works unchanged.
				if (ss.shader != null)
				{
					final cs = new CustomShader(shaderName, ss.shader.fragmentSource, ss.shader.vertexSource);
					shaders.set(shaderName, cs);
					registerInstance(shaderName, ss.shader);
				}
				trace('[ShaderManager] Registered ${prefix}$shaderName (script)');
			}
		}
		#end
	}

	// ─── Carga ────────────────────────────────────────────────────────────────

	public static function loadShader(shaderName:String):CustomShader
	{
		if (shaders.exists(shaderName)) return shaders.get(shaderName);
		if (!shaderPaths.exists(shaderName))
		{
			scanShaders();
			if (!shaderPaths.exists(shaderName))
			{
				trace('[ShaderManager] Shader "$shaderName" no existe');
				return null;
			}
		}
		try
		{
			#if sys
			final fragCode = File.getContent(shaderPaths.get(shaderName));
			final vertCode = vertPaths.exists(shaderName) ? File.getContent(vertPaths.get(shaderName)) : null;
			#else
			final fragCode = openfl.utils.Assets.getText(shaderPaths.get(shaderName));
			final vertCode:Null<String> = null;
			#end
			final shader = new CustomShader(shaderName, fragCode, vertCode);
			shaders.set(shaderName, shader);
			trace('[ShaderManager] Shader "$shaderName" cargado' + (vertCode != null ? ' (con vertex shader)' : ''));
			return shader;
		}
		catch (e:Dynamic)
		{
			trace('[ShaderManager] Error al cargar shader "$shaderName": $e');
			return null;
		}
	}

	public static function getShader(shaderName:String):CustomShader
		return shaders.exists(shaderName) ? shaders.get(shaderName) : loadShader(shaderName);

	/**
	 * Registra un shader desde código GLSL inline (sin archivo .frag).
	 * Si ya existe un shader con ese nombre, lo sobreescribe.
	 */
	public static function registerInline(shaderName:String, fragCode:String):CustomShader
	{
		if (fragCode == null || fragCode.trim() == '')
		{
			trace('[ShaderManager] registerInline: código vacío para "$shaderName"');
			return null;
		}
		if (shaders.exists(shaderName)) shaders.remove(shaderName);
		_liveInstances.remove(shaderName);

		final shader = new CustomShader(shaderName, fragCode, null);
		shaders.set(shaderName, shader);
		trace('[ShaderManager] Shader inline "$shaderName" registrado.');
		return shader;
	}

	// ─── Aplicar / Quitar ─────────────────────────────────────────────────────

	public static function applyShader(sprite:FlxSprite, shaderName:String, ?camera:FlxCamera):Bool
	{
		if (sprite == null) { trace('[ShaderManager] applyShader: sprite es null'); return false; }

		final cs = getShader(shaderName);
		if (cs == null || cs.fragmentCode == null) return false;

		removeShader(sprite);

		var instance:FunkinRuntimeShader;
		try
		{
			instance = new FunkinRuntimeShader(cs.fragmentCode, cs.vertexCode);
		}
		catch (e:Dynamic)
		{
			trace('[ShaderManager] Error al crear FunkinRuntimeShader "$shaderName": $e');
			return false;
		}

		sprite.shader = instance;

		if (!_liveInstances.exists(shaderName)) _liveInstances.set(shaderName, []);
		_liveInstances.get(shaderName).push(instance);
		_spriteToInstance.set(sprite, {name: shaderName, instance: instance});

		_restoreLastParams(shaderName, instance);
		_flushPendingForShader(shaderName);
		trace('[ShaderManager] Shader "$shaderName" aplicado a sprite');
		return true;
	}

	/**
	 * Aplica un shader a una cámara mediante un sprite overlay de pantalla completa.
	 *
	 * ── POR QUÉ OVERLAY Y NO ShaderFilter ────────────────────────────────────
	 * `FlxRuntimeShader` como `ShaderFilter` en una `FlxCamera` **no** hace el
	 * binding automático de `bitmap` a la textura renderizada de esa cámara.
	 * Ese binding solo ocurre en shaders **compilados** (subclases de `FlxShader`
	 * con `@:glFragmentSource`, como `BloomShader`), donde la macro de Haxe genera
	 * el campo `__bitmap : ShaderInput<BitmapData>` en compile-time.
	 * En `FlxRuntimeShader` el campo se crea dinámicamente y OpenFL no lo localiza
	 * vía `Reflect.field`, por lo que la textura de la cámara nunca llega al shader
	 * → pantalla negra.
	 *
	 * SOLUCIÓN FIABLE: sprite overlay 100% blanco, scrollFactor(0,0), mismo tamaño
	 * que la pantalla. `FlxSprite.shader` sí bindea el bitmap del sprite propio.
	 * El shader recibe ese bitmap blanco y produce un overlay semi-transparente que
	 * OpenFL composta sobre la escena con blending NORMAL.
	 *
	 * El sprite se gestiona internamente; usa `removeShaderFromCamera()` para quitarlo.
	 * Para post-proceso real (leer la textura de la cámara), usa `applyPostProcessToCamera()`.
	 *
	 * @param shaderName  Nombre del shader (sin extensión .frag)
	 * @param cam         Cámara destino (default: FlxG.camera)
	 * @return            Siempre null — el efecto lo gestiona el sprite interno.
	 */
	public static function applyShaderToCamera(shaderName:String, ?cam:FlxCamera):ShaderFilter
	{
		if (cam == null) cam = FlxG.camera;

		final cs = getShader(shaderName);
		if (cs == null || cs.fragmentCode == null)
		{
			trace('[ShaderManager] applyShaderToCamera: shader "$shaderName" no encontrado');
			return null;
		}

		// Quitar overlay anterior del mismo shader en esta cámara (si existe)
		removeShaderFromCamera(shaderName, cam);

		var instance:FunkinRuntimeShader;
		try
		{
			instance = new FunkinRuntimeShader(cs.fragmentCode, cs.vertexCode);
		}
		catch (e:Dynamic)
		{
			trace('[ShaderManager] Error compilando shader "$shaderName" para cámara: $e');
			return null;
		}

		if (!_liveInstances.exists(shaderName)) _liveInstances.set(shaderName, []);
		_liveInstances.get(shaderName).push(instance);
		_restoreLastParams(shaderName, instance);
		_flushPendingForShader(shaderName);

		// Sprite overlay de pantalla completa — fijo en pantalla, encima del stage.
		var overlay = new FlxSprite(0, 0);
		overlay.makeGraphic(FlxG.width, FlxG.height, 0xFFFFFFFF);
		overlay.scrollFactor.set(0, 0);
		overlay.cameras = [cam];
		overlay.shader  = instance;

		// Añadir al estado actual en la capa más alta (insert al final del grupo)
		FlxG.state.add(overlay);

		// Registrar para poder quitarlo con removeShaderFromCamera()
		final key = '$shaderName@${Std.string(cam)}';
		_cameraOverlayMap.set(key, overlay);

		trace('[ShaderManager] Shader "$shaderName" aplicado a cámara (overlay)');
		return null; // el overlay gestiona el efecto; no se devuelve ShaderFilter
	}

	/**
	 * Quita el shader overlay aplicado a una cámara con `applyShaderToCamera()`.
	 * Si `cam` es null, quita todos los overlays de ese shader en cualquier cámara.
	 *
	 * @param shaderName  Nombre del shader
	 * @param cam         Cámara de la que quitar el overlay (null = todas)
	 */
	public static function removeShaderFromCamera(shaderName:String, ?cam:FlxCamera):Void
	{
		var toDelete:Array<String> = [];

		for (key in _cameraOverlayMap.keys())
		{
			// La clave es "$shaderName@camRef" — filtramos por nombre de shader
			if (!StringTools.startsWith(key, shaderName + '@')) continue;
			// Si se especificó cámara, filtramos también por referencia
			if (cam != null && key != '$shaderName@${Std.string(cam)}') continue;

			var overlay = _cameraOverlayMap.get(key);
			if (overlay != null)
			{
				// Quitar la instancia del shader del registro de lives
				var arr = _liveInstances.get(shaderName);
				if (arr != null && overlay.shader != null)
					arr.remove(cast overlay.shader);

				// Quitar del estado y destruir el sprite
				try { FlxG.state.remove(overlay, true); } catch (_:Dynamic) {}
				overlay.destroy();
			}
			toDelete.push(key);
		}

		for (k in toDelete) _cameraOverlayMap.remove(k);
	}

	/**
	 * Aplica un shader como `ShaderFilter` real en la cámara (post-proceso verdadero).
	 *
	 * ── CUÁNDO USAR ESTO en vez de applyShaderToCamera() ─────────────────────
	 * Úsalo SOLO cuando el shader necesite leer los píxeles reales de la cámara
	 * (ej: blur, chromatic aberration que desplaza coordenadas, distorsión de escena).
	 * En ese caso el shader DEBE tener `#pragma header` y usar
	 * `flixel_texture2D(bitmap, openfl_TextureCoordv)` para samplear.
	 *
	 * ── REQUISITOS ────────────────────────────────────────────────────────────
	 * • flixel-addons ≥ 2.11.0 con `FlxRuntimeShader` funcional como `ShaderFilter`
	 * • El .frag DEBE contener `#pragma header` en la primera línea útil
	 * • Usar `flixel_texture2D()` (no `texture2D()` directamente con openfl_TextureCoordv)
	 *
	 * El `ShaderFilter` devuelto es necesario para quitarlo después:
	 *   `CameraUtil.removeFilter(filter, cam)`
	 *
	 * @param shaderName  Nombre del shader (sin extensión .frag)
	 * @param cam         Cámara destino (default: FlxG.camera)
	 * @return            El ShaderFilter creado, o null si falló.
	 */
	public static function applyPostProcessToCamera(shaderName:String, ?cam:FlxCamera):ShaderFilter
	{
		if (cam == null) cam = FlxG.camera;

		final cs = getShader(shaderName);
		if (cs == null || cs.fragmentCode == null)
		{
			trace('[ShaderManager] applyPostProcessToCamera: shader "$shaderName" no encontrado');
			return null;
		}

		var instance:FunkinRuntimeShader;
		try
		{
			instance = new FunkinRuntimeShader(cs.fragmentCode, cs.vertexCode);
			// Fuerza la reinicialización del programa GL para asegurar que
			// el binding de __bitmap esté listo antes de pasarlo a ShaderFilter.
			instance.setupForPostProcess();
		}
		catch (e:Dynamic)
		{
			trace('[ShaderManager] Error compilando shader "$shaderName" para post-process: $e');
			return null;
		}

		if (!_liveInstances.exists(shaderName)) _liveInstances.set(shaderName, []);
		_liveInstances.get(shaderName).push(instance);
		_restoreLastParams(shaderName, instance);
		_flushPendingForShader(shaderName);

		final filter = CameraUtil.addShader(instance, cam);
		trace('[ShaderManager] Shader "$shaderName" aplicado como post-process a cámara');
		return filter;
	}

	/**
	 * Crea una instancia nueva de FunkinRuntimeShader para el shader indicado,
	 * la registra en _liveInstances y le aplica los params pendientes/cacheados.
	 *
	 * Es la pieza que necesita ShaderHandle.runtimeShader / toFilter() para
	 * poder usar el shader directamente con new ShaderFilter(instance) o setFilters().
	 *
	 * @param shaderName  Nombre del shader registrado (ej: 'wave')
	 * @return            La instancia creada, o null si el shader no existe.
	 */
	public static function createInstance(shaderName:String):FunkinRuntimeShader
	{
		final cs = getShader(shaderName);
		if (cs == null || cs.fragmentCode == null)
		{
			trace('[ShaderManager] createInstance: shader "$shaderName" no encontrado');
			return null;
		}
		var instance:FunkinRuntimeShader;
		try
		{
			instance = new FunkinRuntimeShader(cs.fragmentCode, cs.vertexCode);
		}
		catch (e:Dynamic)
		{
			trace('[ShaderManager] createInstance: error compilando "$shaderName": $e');
			return null;
		}
		if (!_liveInstances.exists(shaderName)) _liveInstances.set(shaderName, []);
		_liveInstances.get(shaderName).push(instance);
		_restoreLastParams(shaderName, instance);
		_flushPendingForShader(shaderName);
		return instance;
	}

	public static function registerInstance(shaderName:String, instance:FunkinRuntimeShader):Void
	{
		if (instance == null) return;
		if (!_liveInstances.exists(shaderName)) _liveInstances.set(shaderName, []);
		final arr = _liveInstances.get(shaderName);
		if (!arr.contains(instance)) arr.push(instance);
		_flushPendingForShader(shaderName);
	}

	public static function unregisterInstance(shaderName:String, instance:FunkinRuntimeShader):Void
	{
		final arr = _liveInstances.get(shaderName);
		if (arr != null) arr.remove(instance);
	}

	public static function removeShader(sprite:FlxSprite):Void
	{
		if (sprite == null) return;
		try
		{
			final entry = _spriteToInstance.get(sprite);
			if (entry == null) return;
			final arr = _liveInstances.get(entry.name);
			if (arr != null) arr.remove(entry.instance);
			sprite.shader = null;
			_spriteToInstance.remove(sprite);
		}
		catch (e:Dynamic) { _spriteToInstance.remove(sprite); }
	}

	// ─── Parámetros ───────────────────────────────────────────────────────────

	public static function setShaderParam(shaderName:String, paramName:String, value:Dynamic):Bool
	{
		_flushPendingForShader(shaderName);

		var updated     = false;
		var hadInstances = false;

		final arr = _liveInstances.get(shaderName);
		if (arr != null && arr.length > 0)
		{
			hadInstances = true;
			for (instance in arr)
			{
				if (instance == null) continue;
				if (_writeParam(instance, paramName, value)) updated = true;
				else _storePending(shaderName, paramName, value);
			}
		}
		if (!hadInstances) _storePending(shaderName, paramName, value);

		_cacheParam(shaderName, paramName, value);
		return updated;
	}

	public static function flushPending():Void
	{
		for (name in _pendingParams.keys()) _flushPendingForShader(name);
	}

	public static function setShaderParamInt(shaderName:String, paramName:String, value:Int):Bool
	{
		var updated = false;
		final arr = _liveInstances.get(shaderName);
		if (arr != null)
			for (instance in arr)
				if (instance != null)
					try { instance.setInt(paramName, value); updated = true; } catch (_:Dynamic) {}
		if (!updated) _storePending(shaderName, paramName, value);
		_cacheParam(shaderName, paramName, value);
		return updated;
	}

	static function _writeParam(instance:FunkinRuntimeShader, paramName:String, value:Dynamic):Bool
	{
		if (instance == null) return false;
		return instance.writeUniform(paramName, value);
	}

	static function _storePending(shaderName:String, paramName:String, value:Dynamic):Void
	{
		if (!_pendingParams.exists(shaderName)) _pendingParams.set(shaderName, new Map());
		_pendingParams.get(shaderName).set(paramName, value);
	}

	static function _cacheParam(shaderName:String, paramName:String, value:Dynamic):Void
	{
		if (!_lastAppliedParams.exists(shaderName)) _lastAppliedParams.set(shaderName, new Map());
		_lastAppliedParams.get(shaderName).set(paramName, value);
	}

	static function _restoreLastParams(shaderName:String, instance:FunkinRuntimeShader):Void
	{
		final cache = _lastAppliedParams.get(shaderName);
		if (cache == null || Lambda.count(cache) == 0) return;
		for (paramName => value in cache)
			_writeParam(instance, paramName, value);
	}

	static function _flushPendingForShader(shaderName:String):Void
	{
		final pending = _pendingParams.get(shaderName);
		if (pending == null || Lambda.count(pending) == 0) return;
		final arr = _liveInstances.get(shaderName);
		if (arr == null || arr.length == 0) return;
		final toRemove:Array<String> = [];
		for (paramName => value in pending)
		{
			var ok = false;
			for (instance in arr)
				if (instance != null && _writeParam(instance, paramName, value)) ok = true;
			if (ok) toRemove.push(paramName);
		}
		for (p in toRemove) pending.remove(p);
		if (Lambda.count(pending) == 0) _pendingParams.remove(shaderName);
	}

	// ─── Limpieza ─────────────────────────────────────────────────────────────

	public static function clearSpriteShaders():Void
	{
		// Destruir todos los overlays de cámara gestionados internamente
		for (key in _cameraOverlayMap.keys())
		{
			var overlay = _cameraOverlayMap.get(key);
			if (overlay != null)
			{
				try { FlxG.state.remove(overlay, true); } catch (_:Dynamic) {}
				overlay.destroy();
			}
		}
		_cameraOverlayMap.clear();

		_liveInstances.clear();
		_spriteToInstance.clear();
		_pendingParams.clear();
		_lastAppliedParams.clear();
	}

	public static function getAvailableShaders():Array<String>
	{
		final list = [for (n in shaderPaths.keys()) n];
		list.sort((a, b) -> a < b ? -1 : 1);
		return list;
	}

	public static function reloadShader(shaderName:String):Bool
	{
		// Script shader reload
		if (scriptShaders.exists(shaderName))
		{
			final ss = scriptShaders.get(shaderName);
			final ok = ss.hotReload();
			if (ok && ss.shader != null)
			{
				final cs = new CustomShader(shaderName, ss.shader.fragmentSource, ss.shader.vertexSource);
				shaders.set(shaderName, cs);
			}
			return ok;
		}
		// GLSL file reload
		if (shaders.exists(shaderName)) shaders.remove(shaderName);
		final cs = loadShader(shaderName);
		if (cs == null) return false;
		#if sys
		final arr = _liveInstances.get(shaderName);
		if (arr != null)
			for (inst in arr)
				if (inst != null) inst.recompile(cs.fragmentCode, cs.vertexCode);
		#end
		return true;
	}

	public static function reloadAllShaders():Void
	{
		// Reload script shaders
		for (name => ss in scriptShaders) ss.hotReload();
		// Reload GLSL shaders
		shaders.clear();
		scanShaders();
		trace('[ShaderManager] ${Lambda.count(shaderPaths) + Lambda.count(scriptShaders)} shaders available');
	}

	/** Clears everything: camera effects + runtime shaders + script shaders. */
	public static function clear():Void
	{
		// Destroy script shaders
		for (ss in scriptShaders) ss.destroy();
		scriptShaders.clear();

		shaders.clear();
		shaderPaths.clear();
		vertPaths.clear();
		_cameraOverlayMap.clear();
		_liveInstances.clear();
		_spriteToInstance.clear();
		_pendingParams.clear();
		_lastAppliedParams.clear();
		initialized = false;
		_hooked     = false;
	}

	@:deprecated("_ensureCameras ya no es necesario")
	public static function _ensureCameras(sprite:FlxSprite, ?fallback:FlxCamera):Void {}
}


// ─── CustomShader ─────────────────────────────────────────────────────────────

class CustomShader
{
	public var name:String;
	public var fragmentCode:String;

	/** Código GLSL del vertex shader (.vert hermano). null = usar default de Flixel. */
	public var vertexCode:Null<String>;

	var _shader:FunkinRuntimeShader;
	public var shader(get, never):FunkinRuntimeShader;

	function get_shader():FunkinRuntimeShader
	{
		if (_shader == null && fragmentCode != null)
		{
			try { _shader = new FunkinRuntimeShader(fragmentCode, vertexCode); }
			catch (e:Dynamic) { trace('[CustomShader] Error compilando "$name": $e'); }
		}
		return _shader;
	}

	public function new(name:String, fragmentCode:String, ?vertexCode:String)
	{
		this.name         = name;
		this.fragmentCode = fragmentCode;
		this.vertexCode   = vertexCode;
	}

	public function destroy():Void
	{
		_shader      = null;
		fragmentCode = null;
		vertexCode   = null;
	}
}
