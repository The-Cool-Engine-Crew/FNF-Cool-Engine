package;

import flixel.FlxG;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import openfl.display.BitmapData as Bitmap;
import openfl.media.Sound;
import openfl.utils.AssetType;
import openfl.utils.Assets as OpenFlAssets;
import animationdata.FunkinSprite;
import mods.ModManager;
import funkin.cache.PathsCache;
import haxe.Json;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/**
 * Paths — sistema centralizado de resolución de rutas con caché avanzado.
 *
 * ─── Arquitectura del caché ───────────────────────────────────────────────────
 *
 *  ANTES (Paths viejo):
 *    bitmapCache:Map<String, BitmapData>   — cacheaba el bitmap en RAM
 *    atlasCache: Map<String, FlxAtlasFrames> — cacheaba los frames
 *    ¡La textura estaba SIEMPRE en RAM aunque ya estuviese subida a GPU!
 *
 *  AHORA (Paths + PathsCache):
 *    PathsCache.currentTrackedGraphics    — FlxGraphic con GPU caching opcional
 *    PathsCache.currentTrackedSounds      — Sound cacheados
 *    atlasCache: Map<String, FlxAtlasFrames> — sólo los frames (ligeros)
 *
 *  El FlxGraphic que construye PathsCache integra con FlxG.bitmap nativo de
 *  Flixel (FlxSprite.loadGraphic() lo encuentra automáticamente). Cuando
 *  gpuCaching=true el BitmapData en RAM se libera después del upload → ahorra
 *  ~4 MB por textura 1024×1024.
 *
 * ─── Ciclo de vida del caché ──────────────────────────────────────────────────
 *
 *   // Al inicio de un estado que carga assets pesados (p.ej. PlayState):
 *   Paths.beginSession();
 *
 *   // Durante la carga — se llama automáticamente por getGraphic / getSound
 *
 *   // Al destruir el estado:
 *   Paths.clearStoredMemory();   // sonidos fuera de uso + marcar gráficos
 *   Paths.clearUnusedMemory();   // destruir gráficos marcados + GC
 *
 * @author Cool Engine Team
 * @version 0.6.0
 */
class Paths
{
	public static inline var SOUND_EXT = #if web "mp3" #else "ogg" #end;

	// ── Acceso al caché principal ─────────────────────────────────────────────

	/** Instancia global de PathsCache. Nunca null. */
	public static var cache(get, never):PathsCache;

	static inline function get_cache():PathsCache
		return PathsCache.instance;

	// ── Caché de atlas (sólo frames, los bitmaps están en PathsCache) ─────────
	//
	// FlxAtlasFrames es ligero: sólo contiene un array de FlxRect + referencia
	// al FlxGraphic. No tiene datos de píxeles propios.
	// El bitmap real vive en PathsCache (GPU o RAM según gpuCaching).
	// LRU eliminado: FNF nunca necesita evictar atlases durante gameplay.
	// Los frames se liberan con clearPreviousSession(), no por eviction.
	static var atlasCache:Map<String, FlxAtlasFrames> = [];
	static var atlasCount:Int = 0;

	/**
	 * Límite de atlases en caché.
	 * 50 cubre todo lo necesario para gameplay: 3 personajes + stage + notas + UI.
	 * El valor anterior (200) acumulaba atlas de assets ya sin usar entre canciones
	 * manteniendo sus BitmapData en RAM — contribución directa a los ~1 GB observados.
	 * Con LRU (eviction al superar el límite) es seguro bajar este valor.
	 */
	public static var maxAtlasCache:Int = 50;

	/** Si false todos los accesos van a disco (útil para depuración). */
	public static var cacheEnabled:Bool = true;

	// ── Stage actual ──────────────────────────────────────────────────────────

	/** Actualizado por PlayState al cambiar de stage. */
	public static var currentStage:String = 'stage_week1';

	// ── Opciones de GPU ───────────────────────────────────────────────────────

	/**
	 * Alias de PathsCache.gpuCaching para compatibilidad con opciones guardadas.
	 * Cambiar aquí también cambia el comportamiento de PathsCache.
	 */
	public static var gpuCaching(get, set):Bool;

	static inline function get_gpuCaching():Bool
		return PathsCache.gpuCaching;

	static inline function set_gpuCaching(v:Bool):Bool
	{
		PathsCache.gpuCaching = v;
		return v;
	}

	// ── Gestión de sesión (delegados a PathsCache) ────────────────────────────

	/**
	 * Inicia una nueva sesión de caché.
	 * Resetea localTrackedAssets sin borrar nada.
	 * Llamar al inicio de create() en cada estado pesado.
	 */
	public static inline function beginSession():Void
		cache.beginSession();

	/**
	 * Destruye los assets de la sesión anterior que no fueron rescatados.
	 * Llamar al FINAL de create() de un estado pesado, después de cargar
	 * todos los assets — esto da tiempo a que los assets compartidos sean
	 * rescatados de _previousGraphics a _currentGraphics durante la carga.
	 */
	public static inline function clearPreviousSession():Void
	{
		cache.clearPreviousSession();
		_pruneInvalidAtlases();
	}

	/**
	 * Añade una clave a las exclusiones permanentes (nunca se evicta).
	 * Ejemplo: Paths.addExclusion(Paths.music('freakyMenu'));
	 */
	public static inline function addExclusion(key:String):Void
		cache.addExclusion(key);

	/**
	 * Libera assets de sonido + gráficos no marcados (fuera de localTrackedAssets).
	 * Llamar al salir de un estado pesado ANTES de clearUnusedMemory().
	 */
	public static inline function clearStoredMemory():Void
	{
		cache.clearStoredMemory();
		// Limpiar también atlases cuya graphic ya no está en PathsCache
		_pruneInvalidAtlases();
	}

	/**
	 * Destruye los gráficos marcados por clearStoredMemory() + fuerza GC.
	 * Llamar DESPUÉS de clearStoredMemory().
	 */
	public static inline function clearUnusedMemory():Void
		cache.clearUnusedMemory();

	// ── Core: resolve ─────────────────────────────────────────────────────────

	/**
	 * Resuelve un archivo al path físico correcto.
	 * Orden: mods/{activeMod}/{file} → assets/{file}
	 */
	public static function resolve(file:String, ?type:AssetType):String
	{
		final modPath = ModManager.resolveInMod(file);
		if (modPath != null)
			return modPath;
		return 'assets/$file';
	}

	/**
	 * Resolve a path for WRITING (saving files).
	 * Unlike resolve(), this does NOT check if the file exists —
	 * it always returns the mod path if a mod is active.
	 * Use this whenever you need to save/create a file.
	 *
	 * Examples:
	 *   resolveWrite('characters/bf.json') → 'mods/myMod/characters/bf.json'  (mod active)
	 *   resolveWrite('characters/bf.json') → 'assets/characters/bf.json'      (no mod)
	 */
	public static function resolveWrite(file:String):String
	{
		#if sys
		if (ModManager.isActive())
			return '${ModManager.modRoot()}/$file';
		#end
		return 'assets/$file';
	}

	/**
	 * Ensure the directory for a file path exists, then return the path.
	 * Convenience wrapper for write operations.
	 */
	public static function ensureDir(filePath:String):String
	{
		#if sys
		final dir = haxe.io.Path.directory(filePath);
		if (dir != '' && !sys.FileSystem.exists(dir))
			sys.FileSystem.createDirectory(dir);
		#end
		return filePath;
	}

	public static function resolveAny(candidates:Array<String>):String
	{
		for (c in candidates)
		{
			if (c == null || c == '')
				continue;
			#if sys
			if (FileSystem.exists(c))
				return c;
			#else
			if (OpenFlAssets.exists(c))
				return c;
			#end
		}
		return candidates.filter(s -> s != null && s != '')[0] ?? '';
	}

	/** ¿Existe el archivo (en mod o en assets)? */
	public static function exists(file:String, ?type:AssetType):Bool
	{
		final path = resolve(file, type);
		#if sys
		return FileSystem.exists(path);
		#else
		return OpenFlAssets.exists(path, type);
		#end
	}

	/** Lee texto desde file (en mod o en assets). */
	public static function getText(file:String):String
	{
		final path = resolve(file, TEXT);
		#if sys
		if (FileSystem.exists(path))
			return File.getContent(path);
		#end
		return OpenFlAssets.getText(path);
	}

	// ── Paths tipados ─────────────────────────────────────────────────────────

	public static inline function file(file:String, type:AssetType = TEXT):String
		return resolve(file, type);

	public static inline function txt(key:String):String
		return resolve('data/$key.txt', TEXT);

	public static inline function xml(key:String):String
		return resolve('data/$key.xml', TEXT);

	public static inline function json(key:String):String
		return resolve('data/$key.json', TEXT);

	public static function jsonSong(key:String):String
		return resolveAny([ModManager.resolveInMod('songs/$key.json') ?? '', 'assets/songs/$key.json']);

	public static function songsTxt(key:String):String
		return resolve('songs/$key.txt', TEXT);

	public static function characterJSON(key:String):String
		return resolveAny([
			ModManager.resolveInMod('characters/$key.json') ?? '',
			'assets/characters/$key.json'
		]);

	public static function stageJSON(key:String):String
		return resolveAny([ModManager.resolveInMod('stages/$key.json') ?? '', 'stages/$key.json']);

	public static function image(key:String):String
	{
		return resolve('images/$key.png', IMAGE);
	}

	public static inline function imageCutscene(key:String):String
		return resolve('$key.png', IMAGE);

	public static inline function characterimage(key:String):String
		return resolve('characters/images/$key.png', IMAGE);

	public static function characterFolder(key:String):String
		return resolve('characters/images/$key/');

	public static function sound(key:String):String
	{
		#if sys
		final modPath = ModManager.resolveInMod('sounds/$key.$SOUND_EXT');
		if (modPath != null && FileSystem.exists(modPath))
			return modPath;
		final assetsPath = 'assets/sounds/$key.$SOUND_EXT';
		if (FileSystem.exists(assetsPath))
			return assetsPath;
		#end
		return resolve('sounds/$key.$SOUND_EXT', SOUND);
	}

	/**
	 * Resuelve el path de un sonido de stage buscando en:
	 *   1. Mod activo   → mods/{active}/stages/{key}.ogg
	 *   2. Mods habilitados → mods/{mod}/stages/{key}.ogg  (por orden de instalación)
	 *   3. Assets base  → assets/stages/{key}.ogg
	 *
	 * BUGFIX: usaba resolveWrite() que devuelve SIEMPRE la ruta del mod activo sin
	 * comprobar si el archivo existe, por lo que el fallback a assets/ nunca ocurría.
	 * Esto causaba que soundRandomStage() devolviera una ruta inexistente cuando el
	 * sonido estaba en assets/ y no en el mod activo → silencio sin error.
	 */
	public static function soundStage(key:String):String
	{
		#if sys
		// 1. Mod activo primero
		if (ModManager.isActive())
		{
			final p = '${ModManager.modRoot()}/stages/$key.$SOUND_EXT';
			if (FileSystem.exists(p))
				return p;
		}
		// 2. Todos los mods habilitados
		for (mod in ModManager.installedMods)
		{
			if (!ModManager.isEnabled(mod.id))
				continue;
			final p = '${ModManager.MODS_FOLDER}/${mod.id}/stages/$key.$SOUND_EXT';
			if (FileSystem.exists(p))
				return p;
		}
		// 3. Assets base
		final assetsPath = 'assets/stages/$key.$SOUND_EXT';
		if (FileSystem.exists(assetsPath))
			return assetsPath;
		#end
		return 'assets/stages/$key.$SOUND_EXT';
	}

	public static inline function soundRandom(key:String, min:Int, max:Int):Null<Sound>
		return getSound(key + FlxG.random.int(min, max));

	/**
	 * Devuelve el path de un sonido aleatorio del stage actual.
	 *
	 * BUGFIX: ahora soundStage() resuelve correctamente con fallback a assets/,
	 * por lo que este método funciona aunque el sonido esté en assets/ y no en el
	 * mod activo — sin necesidad de recompilar.
	 *
	 * Uso: Paths.getSound(Paths.soundRandomStage("key", 1, 5))
	 */
	public static inline function soundRandomStage(key:String, min:Int, max:Int):String
		return soundStage('${funkin.gameplay.PlayState.curStage}/sounds/' + key + FlxG.random.int(min, max));

	public static function music(key:String):String
	{
		// Igual que sound(): solo resuelve el path fisico sin registrar en Lime.
		// getSound() / loadMusic() cargan con Sound.fromFile() que bypasea OpenFL.
		#if sys
		final modPath = ModManager.resolveInMod('music/$key.$SOUND_EXT');
		if (modPath != null && FileSystem.exists(modPath))
			return modPath;
		final assetsPath = 'assets/music/$key.$SOUND_EXT';
		if (FileSystem.exists(assetsPath))
			return assetsPath;
		#end
		return resolve('music/$key.$SOUND_EXT', MUSIC);
	}

	public static inline function font(key:String):String
		return resolve('fonts/$key');

	public static function video(key:String):String
	{
		final k = key.endsWith('.mp4') ? key.substr(0, key.length - 4) : key;
		return resolveAny([
			ModManager.resolveInMod('videos/$k.mp4') ?? '',
			ModManager.resolveInMod('cutscenes/videos/$k.mp4') ?? '',
			'assets/videos/$k.mp4',
			'assets/cutscenes/videos/$k.mp4'
		]);
	}

	public static function stageScripts(stageName:String):String
		return resolveAny([
			ModManager.resolveInMod('stages/$stageName/scripts') ?? '',
			'assets/stages/$stageName/scripts'
		]);

	// ── Carga de gráficos ─────────────────────────────────────────────────────

	/**
	 * Carga un BitmapData desde disco o assets embebidos.
	 * Internamente pasa por PathsCache → si gpuCaching=true, la imagen en RAM
	 * se libera después del upload y se devuelve FlxGraphic.bitmap (que puede
	 * estar en modo "GPU only"; los píxeles no son accesibles desde CPU).
	 *
	 * Para efectos que necesiten leer píxeles desde CPU (tintado dinámico, etc.)
	 * usar getGraphic() con allowGPU=false.
	 *
	 * @deprecated Preferir getGraphic() para integración completa con Flixel.
	 */
	public static function getBitmap(key:String, allowGPU:Bool = true):Null<Bitmap>
	{
		final g = getGraphic(key, allowGPU);
		return g?.bitmap;
	}

	/**
	 * Loads and caches an FlxGraphic for the given key.
	 *
	 * • First searches PathsCache (cache hit → O(1), no I/O).
	 * • The resulting FlxGraphic has persist=true + destroyOnNoUse=false.
	 *
	 * @param key       Logical key of the asset (without the "images/" prefix, without ".png").
	 * @param allowGPU  If false, disable GPU caching for this asset.
	 */
	public static function getGraphic(key:String, allowGPU:Bool = true):Null<FlxGraphic>
	{
		// Resolver path físico
		final path = image(key);
		// Clave de PathsCache = path físico (único y estable entre llamadas)
		final cacheKey = path;

		// Cache hit en PathsCache
		if (cacheEnabled && cache.hasValidGraphic(cacheKey))
			return cache.peekGraphic(cacheKey);

		// Cache miss → cargar desde disco
		final bmp = _loadBitmapFromDisk(path);
		if (bmp == null)
		{
			trace('[Paths] getGraphic: not found "$key" (path="$path")');
			return null;
		}

		return cacheEnabled ? cache.getGraphic(cacheKey, bmp, allowGPU) : FlxGraphic.fromBitmapData(bmp, false, cacheKey, false);
	}

	// ── Imagen del stage (path especial) ──────────────────────────────────────

	/**
	 * Carga la imagen de un asset de stage.
	 * @param fromStage  Si se especifica, busca en la carpeta de OTRO stage en
	 *                   lugar de currentStage.  Permite compartir assets entre stages.
	 */
	public static function imageStage(key:String, ?fromStage:String):Null<Bitmap>
	{
		final path = _resolveStageImagePath(key, fromStage);
		if (path == null)
			return null;

		// Intentar desde PathsCache primero
		if (cacheEnabled && cache.hasValidGraphic(path))
			return cache.peekGraphic(path)?.bitmap;

		final bmp = _loadBitmapFromDisk(path);
		if (bmp == null)
			return null;

		// BUGFIX: purgar entrada muerta de FlxG.bitmap antes de crear el gráfico nuevo.
		@:privateAccess
		{
			final deadEntry = FlxG.bitmap.get(path);
			if (deadEntry != null && deadEntry.bitmap == null)
			{
				FlxG.bitmap.removeKey(path);
				trace('[Paths] imageStage: purgada entrada muerta de FlxG.bitmap para "$path"');
			}
		}

		if (cacheEnabled)
			cache.getGraphic(path, bmp);
		return bmp;
	}

	// ── Carga de sonidos ─────────────────────────────────────────────────────

	/**
	 * Carga un sonido desde disco y lo cachea en PathsCache.
	 * Reutiliza la instancia Sound si ya estaba cacheada (sin I/O).
	 *
	 * @param path    Path físico del sonido (resultado de Paths.sound(), .music(), etc.)
	 * @param safety  Si true y no se encuentra, devuelve un beep de fallback.
	 */
	public static function getSound(path:String, safety:Bool = false):Null<Sound>
	{
		// Cache hit
		if (cacheEnabled && cache.hasSound(path))
			return cache.getSound(path, null, safety);

		// Cache miss → cargar
		var snd:Sound = null;
		try
		{
			#if sys
			if (FileSystem.exists(path))
			{
				snd = Sound.fromFile(path);
			}
			#end
			// Bug 1 fix: on Android/iOS, FileSystem.exists() returns true for APK-embedded
			// assets, but Sound.fromFile() can't open them as real OS paths and returns null.
			// The old `else` meant the OpenFlAssets fallback was never reached in that case.
			// Using `if (snd == null)` ensures the fallback always runs when fromFile failed.
			if (snd == null)
			{
				if (OpenFlAssets.exists(path, SOUND))
					snd = OpenFlAssets.getSound(path);
				else if (OpenFlAssets.exists(path, MUSIC))
					snd = OpenFlAssets.getSound(path);
			}
		}
		catch (e:Dynamic)
		{
			trace('[Paths] getSound "$path": $e');
		}

		return cacheEnabled ? cache.getSound(path, snd, safety) : snd;
	}

	/**
	 * Carga música de forma segura desde el filesystem o assets embebidos.
	 * Úsalo en lugar de FlxG.sound.playMusic(Paths.music(...)) cuando el path
	 * puede venir de una carpeta de mods (no está en el manifest de OpenFL).
	 */
	public static function loadMusic(key:String):Null<Sound>
	{
		final path = music(key);
		return getSound(path);
	}

	// ── Carga de audio de canción (streaming) ─────────────────────────────────

	/** Carga el Inst de una canción usando streaming. */
	public static function loadInst(song:String, ?diffSuffix:String):flixel.sound.FlxSound
		return _loadStreamingSound(inst(song, diffSuffix));

	/** Carga las Voices de una canción usando streaming. */
	public static function loadVoices(song:String, ?diffSuffix:String):flixel.sound.FlxSound
		return _loadStreamingSound(voices(song, diffSuffix));

	/**
	 * Carga un FlxSound en modo streaming.
	 * Las canciones NUNCA se meten en PathsCache (son demasiado grandes y
	 * se usan una sola vez). Se cargan directamente como stream desde disco.
	 *
	 * POR QUÉ STREAMING:
	 *   loadEmbedded() decodifica el OGG completo a PCM en RAM al cargar.
	 *   3 min × 44.1 kHz × 16-bit × 2 canales = ~32 MB por pista.
	 *   Inst + Voices = 64–120 MB. Con streaming → sólo un buffer de segundos.
	 */
	/**
	 * Carga un FlxSound en modo streaming.
	 *
	 * IMPORTANTE: loadStream() registra un SampleDataEvent listener en el
	 * openfl.media.Sound subyacente, lo que DEBE ocurrir en el main thread.
	 * Si se llama desde un thread secundario OpenFL lanza:
	 *   "SampleDataEvent listener has to provide between 2048 and 8192 samples"
	 * Por eso esta función siempre es síncrona en el main thread.
	 * El threading de la precarga lo gestiona el llamador (FreeplayState).
	 */
	static function _loadStreamingSound(path:String):flixel.sound.FlxSound
	{
		final snd = new flixel.sound.FlxSound();
		try
		{
			#if sys
			if (FileSystem.exists(path))
			{
				snd.loadStream(path);
				FlxG.sound.list.add(snd);
				return snd;
			}
			#end
			snd.loadEmbedded(path, false, false);
			FlxG.sound.list.add(snd);
		}
		catch (e:Dynamic)
		{
			trace('[Paths] _loadStreamingSound "$path": $e');
		}
		return snd;
	}

	// ── Song paths ────────────────────────────────────────────────────────────

	public static function inst(song:String, ?diffSuffix:String):String
	{
		final folder = _resolveSongFolder(song);
		#if sys
		// Primero intentar con sufijo de dificultad (ej: "Inst-nightmare.ogg")
		if (diffSuffix != null && diffSuffix != '')
		{
			// El sufijo viene como "-nightmare", quitamos el guión inicial
			final diffName = diffSuffix.startsWith('-') ? diffSuffix.substr(1) : diffSuffix;
			for (subdir in ['song/', ''])
			{
				final p = '$folder/${subdir}Inst-$diffName.$SOUND_EXT';
				if (FileSystem.exists(p))
					return p;
			}
		}
		final withSub = '$folder/song/Inst.$SOUND_EXT';
		if (FileSystem.exists(withSub))
			return withSub;
		final flat = '$folder/Inst.$SOUND_EXT';
		if (FileSystem.exists(flat))
			return flat;
		#end
		return '$folder/song/Inst.$SOUND_EXT';
	}

	public static function voices(song:String, ?diffSuffix:String):String
	{
		final folder = _resolveSongFolder(song);
		#if sys
		// Primero intentar con sufijo de dificultad (ej: "Voices-nightmare.ogg")
		if (diffSuffix != null && diffSuffix != '')
		{
			final diffName = diffSuffix.startsWith('-') ? diffSuffix.substr(1) : diffSuffix;
			for (subdir in ['song/', ''])
			{
				final p = '$folder/${subdir}Voices-$diffName.$SOUND_EXT';
				if (FileSystem.exists(p))
					return p;
			}
		}
		final withSub = '$folder/song/Voices.$SOUND_EXT';
		if (FileSystem.exists(withSub))
			return withSub;
		final flat = '$folder/Voices.$SOUND_EXT';
		if (FileSystem.exists(flat))
			return flat;
		#end
		return '$folder/song/Voices.$SOUND_EXT';
	}

	/**
	 * Resuelve la ruta de vocals para un personaje específico.
	 * Prioridad: Voices-charName-diff → Voices-charName → Voices-diff → Voices
	 * Devuelve null si no existe ningún archivo de vocals para ese personaje.
	 */
	public static function voicesForChar(song:String, charName:String, ?diffSuffix:String):Null<String>
	{
		if (charName == null || charName == '')
			return null;
		final folder = _resolveSongFolder(song);
		#if sys
		final diffName = (diffSuffix != null && diffSuffix != '') ? (diffSuffix.startsWith('-') ? diffSuffix.substr(1) : diffSuffix) : null;

		// 1. Voices-charName-diff.ogg
		if (diffName != null)
		{
			for (subdir in ['song/', ''])
			{
				final p = '$folder/${subdir}Voices-$charName-$diffName.$SOUND_EXT';
				if (FileSystem.exists(p))
					return p;
			}
		}
		// 2. Voices-charName.ogg
		for (subdir in ['song/', ''])
		{
			final p = '$folder/${subdir}Voices-$charName.$SOUND_EXT';
			if (FileSystem.exists(p))
				return p;
		}
		#end
		return null; // no existe archivo específico para este personaje
	}

	/** Carga vocals específicas de un personaje como FlxSound en streaming. */
	public static function loadVoicesForChar(song:String, charName:String, ?diffSuffix:String):Null<flixel.sound.FlxSound>
	{
		final path = voicesForChar(song, charName, diffSuffix);
		if (path == null)
			return null;
		return _loadStreamingSound(path);
	}

	/** true si existen vocals específicas para este personaje (con o sin diff). */
	public static function hasVoicesForChar(song:String, charName:String, ?diffSuffix:String):Bool
		return voicesForChar(song, charName, diffSuffix) != null;

	// ── FunkinSprite helpers ─────────────────────────────────────────────────

	public static function animateAtlas(key:String):String
		return resolve(key);

	public static function characterAnimateAtlas(key:String):String
		return resolve('characters/images/$key');

	public static function hasAnimateAtlas(key:String):Bool
		return FunkinSprite.folderHasAnimateAtlas(resolve(key));

	public static function characterHasAnimateAtlas(key:String):Bool
		return FunkinSprite.folderHasAnimateAtlas(resolve('characters/images/$key'));

	public static inline function getFunkinSprite(x:Float, y:Float, key:String):FunkinSprite
		return FunkinSprite.create(x, y, key);

	public static inline function getCharacterSprite(x:Float, y:Float, key:String):FunkinSprite
		return FunkinSprite.createCharacter(x, y, key);

	// ── Atlas Sparrow con caché ───────────────────────────────────────────────

	/**
	 * Carga un atlas Sparrow (PNG + XML).
	 *
	 * El FlxGraphic del PNG pasa por PathsCache (GPU caching).
	 * El FlxAtlasFrames se cachea separadamente (es sólo metadata de frames).
	 */
	public static function getSparrowAtlas(key:String):FlxAtlasFrames
	{
		final path:String = image(key);
		return _cachedAtlas(path, () -> _sparrow(path, resolve('images/$key.xml')));
	}

	public static function characterSprite(key:String):FlxAtlasFrames
		return _cachedAtlas('char_$key', () -> _loadCharacterSpriteAtlas(key));

	/**
	 * Carga el atlas de un personaje soportando múltiples hojas de sprites.
	 *
	 * Si existe `characters/images/charName.sheets` (JSON array de strings),
	 * cada entrada puede ser:
	 *
	 *   • Una KEY Sparrow (PNG+XML):
	 *       ["tankman_basic", "tankman_bloody"]
	 *
	 *   • Una CARPETA de Adobe Animate (con Animation.json):
	 *       ["tankman/basic", "tankman/bloody", "tankman/extra-animations"]
	 *
	 *   • O subcarpetas directas del personaje:
	 *       ["basic", "bloody", "extra-animations"]
	 *       → se resuelven como characters/images/charName/basic, etc.
	 *
	 * Las entradas Animate se fusionan vía FunkinSprite.loadMultiAnimateAtlas()
	 * (que escribe un directorio temporal con el atlas unificado).
	 * Las entradas Sparrow se fusionan con FlxAtlasFramesExt.mergeAtlases().
	 *
	 * Si el .sheets mezcla tipos, las entradas Animate tienen prioridad y las
	 * Sparrow se ignoran (imprime un warning).
	 *
	 * Sin .sheets: hoja única estándar (Sparrow o Animate).
	 */
	static function _loadCharacterSpriteAtlas(key:String):FlxAtlasFrames
	{
		// 1. Buscar archivo .sheets para multi-sheet
		final sheetsPath = _resolveCharacterSheets(key);
		#if sys
		if (sheetsPath != null && sys.FileSystem.exists(sheetsPath))
		{
			try
			{
				final sheetKeys:Array<String> = haxe.Json.parse(sys.io.File.getContent(sheetsPath));
				if (sheetKeys != null && sheetKeys.length > 0)
				{
					// ── Detectar si las entradas son carpetas Animate ────────
					final animateFolders:Array<String> = [];
					final sparrowKeys:Array<String> = [];

					for (sheetKey in sheetKeys)
					{
						if (sheetKey == null || sheetKey.trim() == '')
							continue;
						final folder = _resolveCharacterAnimateFolder(key, sheetKey);
						if (folder != null)
							animateFolders.push(folder);
						else
							sparrowKeys.push(sheetKey);
					}

					// ── Rama Animate ─────────────────────────────────────────
					if (animateFolders.length > 0)
					{
						if (sparrowKeys.length > 0)
							trace('[Paths] characterSprite "$key": .sheets mezcla Animate y Sparrow — se usan sólo las carpetas Animate.');

						// La fusión real ocurre en FunkinSprite.loadMultiAnimateAtlas.
						// Paths no puede devolver un FlxAtlasFrames para Animate —
						// devolvemos null para que el caller (loadCharacterSparrow)
						// use la vía Animate directamente.
						//
						// NOTA: este caso ya es interceptado en FunkinSprite.loadCharacterSparrow()
						// mediante resolveMultiAnimateFolders(). Si llegamos aquí es porque alguien
						// llama Paths.characterSprite() directamente (raro). En ese caso no podemos
						// hacer nada útil, así que logueamos y devolvemos null.
						trace('[Paths] characterSprite "$key": multi-Animate detectado — usar FunkinSprite.loadCharacterSparrow() en su lugar.');
						return null;
					}

					// ── Rama Sparrow ──────────────────────────────────────────
					if (sparrowKeys.length > 0)
					{
						final atlases:Array<FlxAtlasFrames> = [];
						for (sheetKey in sparrowKeys)
						{
							final png = _resolveCharacterPng(sheetKey);
							final xml = _resolveCharacterXml(sheetKey);
							final atlas = _sparrow(png, xml);
							if (atlas != null)
								atlases.push(atlas);
						}
						if (atlases.length > 0)
						{
							final merged = extensions.FlxAtlasFramesExt.mergeAtlases(atlases);
							if (merged != null)
							{
								trace('[Paths] characterSprite "$key": multi-sheet Sparrow (${atlases.length} hojas fusionadas)');
								return merged;
							}
						}
					}
				}
			}
			catch (e:Dynamic)
			{
				trace('[Paths] characterSprite "$key": error leyendo .sheets — $e');
			}
		}
		#end
		// 2. Fallback: hoja única estándar
		return _sparrow(_resolveCharacterPng(key), _resolveCharacterXml(key));
	}

	/**
	 * Dado un key de .sheets, intenta resolverlo como carpeta Adobe Animate.
	 * Busca en: subcarpeta del char, characters/images/, images/characters/, assets/.
	 * Devuelve el path si tiene Animation.json, null si no es Animate.
	 */
	static function _resolveCharacterAnimateFolder(charKey:String, sheetKey:String):Null<String>
	{
		#if sys
		final isSubKey = !sheetKey.contains('/');
		final candidates:Array<String> = [];

		// Como subcarpeta directa del personaje
		if (isSubKey)
		{
			if (ModManager.activeMod != null)
			{
				final base = '${ModManager.MODS_FOLDER}/${ModManager.activeMod}';
				candidates.push('$base/characters/images/$charKey/$sheetKey');
				candidates.push('$base/images/characters/$charKey/$sheetKey');
			}
			candidates.push('assets/characters/images/$charKey/$sheetKey');
		}

		// Como ruta relativa a characters/images/
		if (ModManager.activeMod != null)
		{
			final base = '${ModManager.MODS_FOLDER}/${ModManager.activeMod}';
			candidates.push('$base/characters/images/$sheetKey');
			candidates.push('$base/images/characters/$sheetKey');
		}
		candidates.push('assets/characters/images/$sheetKey');

		for (p in candidates)
			if (p != null && animationdata.FunkinSprite.folderHasAnimateAtlas(p))
				return p;
		#end
		return null;
	}

	static function _resolveCharacterSheets(key:String):Null<String>
	{
		#if sys
		return resolveAny([
			ModManager.resolveInMod('characters/images/$key.sheets') ?? '',
			ModManager.resolveInMod('images/characters/$key.sheets') ?? '',
			'assets/characters/images/$key.sheets'
		]);
		#else
		return null;
		#end
	}

	/**
	 * Carga un atlas Sparrow de un stage.
	 * @param fromStage  Si se especifica, busca los assets en ese stage en lugar
	 *                   de currentStage — permite reutilizar assets entre stages.
	 */
	public static function stageSprite(key:String, ?fromStage:String):FlxAtlasFrames
	{
		final lib = fromStage ?? currentStage;
		return _cachedAtlas('stage_${lib}_$key', () ->
		{
			final pngPath = resolveAny([
				ModManager.resolveInMod('stages/$lib/images/$key.png') ?? '',
				ModManager.resolveInMod('images/stages/$key.png') ?? '',
				ModManager.resolveInMod('images/$key.png') ?? '',
				'assets/stages/$lib/images/$key.png'
			]);
			final xmlPath = resolveAny([
				ModManager.resolveInMod('stages/$lib/images/$key.xml') ?? '',
				ModManager.resolveInMod('images/stages/$key.xml') ?? '',
				ModManager.resolveInMod('images/$key.xml') ?? '',
				'assets/stages/$lib/images/$key.xml'
			]);
			final stageBmp = _resolveStageImagePath(key, lib);
			if (stageBmp == null)
				return null;
			return _sparrowFromPath(stageBmp, xmlPath);
		});
	}

	public static function skinSprite(key:String):FlxAtlasFrames
		return _cachedAtlas('skin_$key', () -> _sparrow(resolve('notes/skins/$key.png', IMAGE), resolve('notes/skins/$key.xml', TEXT)));

	public static function splashSprite(key:String):FlxAtlasFrames
		return _cachedAtlas('splash_$key', () -> _sparrow(resolve('notes/splashes/$key.png', IMAGE), resolve('notes/splashes/$key.xml', TEXT)));

	public static function getSparrowAtlasCutscene(key:String):FlxAtlasFrames
		return _cachedAtlas('cutscene_$key', () -> FlxAtlasFrames.fromSparrow('$key.png', '$key.xml'));

	// ── Atlas Packer con caché ────────────────────────────────────────────────

	public static function getPackerAtlas(key:String):FlxAtlasFrames
		return _cachedAtlas('packer_$key', () -> _packer(image(key), resolve('images/$key.txt')));

	public static function characterSpriteTxt(key:String):FlxAtlasFrames
		return _cachedAtlas('char_txt_$key', () -> _packer(_resolveCharacterPng(key), _resolveCharacterTxt(key)));

	/** Packer (TXT) atlas from a stage. Accepts optional @fromStage override. */
	public static function stageSpriteTxt(key:String, ?fromStage:String):FlxAtlasFrames
	{
		final lib = fromStage ?? currentStage;
		return _cachedAtlas('stage_txt_${lib}_$key', () ->
		{
			final pngPath = resolveAny([
				ModManager.resolveInMod('stages/$lib/images/$key.png') ?? '',
				ModManager.resolveInMod('images/stages/$key.png') ?? '',
				'assets/stages/$lib/images/$key.png'
			]);
			final txtPath = resolveAny([
				ModManager.resolveInMod('stages/$lib/images/$key.txt') ?? '',
				ModManager.resolveInMod('images/stages/$key.txt') ?? '',
				'assets/stages/$lib/images/$key.txt'
			]);
			return _packer(pngPath, txtPath);
		});
	}

	public static function skinSpriteTxt(key:String):FlxAtlasFrames
		return _cachedAtlas('skin_txt_$key', () -> _packer(resolve('notes/skins/$key.png', IMAGE), resolve('notes/skins/$key.txt', TEXT)));

	// ── Gestión del caché de atlas ────────────────────────────────────────────

	/**
	 * Limpia el caché de atlas + delega a PathsCache.
	 * Los FlxGraphics del PNG se liberan via PathsCache.
	 */
	public static function clearCache():Void
	{
		for (atlas in atlasCache)
		{
			if (atlas?.parent != null)
			{
				atlas.parent.destroyOnNoUse = true;
				if (atlas.parent.useCount <= 0)
					atlas.parent.destroy();
			}
		}
		atlasCache.clear();
		atlasCount = 0;
		trace('[Paths] Atlas cache limpiado.');
	}

	/**
	 * Limpia entradas del atlasCache cuyo FlxGraphic ya fue dispuesto.
	 * Llamar después de GC/compact para que atlas invalidados sean detectados.
	 * Así el siguiente acceso fuerza una recarga limpia desde disco.
	 */
	public static inline function pruneAtlasCache():Void
	{
		_pruneInvalidAtlases();
	}

	public static function clearFlxBitmapCache():Void
	{
		FlxG.bitmap.clearCache();
		try
		{
			openfl.utils.Assets.cache.clear();
		}
		catch (_:Dynamic)
		{
		}
		#if cpp cpp.vm.Gc.run(true); #end
		#if hl hl.Gc.major(); #end
		trace('[Paths] FlxG.bitmap + OpenFL cache limpiados.');
	}

	/**
	 * Clears EVERYTHING: atlas + PathsCache.forceFullClear() + Flixel + Lime cache.
	 * Always call this when changing mods or restarting.
	 */
	public static function clearAllCaches():Void
	{
		clearCache();
		cache.forceFullClear();

		try
		{
			final oflCache:openfl.utils.AssetCache = cast openfl.utils.Assets.cache;
			@:privateAccess
			{
				if (oflCache.bitmapData != null)
					for (k in oflCache.bitmapData.keys())
						oflCache.removeBitmapData(k);
				if (oflCache.sound != null)
					for (k in oflCache.sound.keys())
						oflCache.removeSound(k);
			}
			oflCache.clear();
		}
		catch (_:Dynamic) {}

		clearFlxBitmapCache();
		cache.clearModPathCache();
	}

	/**
	 * @deprecated Alias de clearAllCaches() para compatibilidad.
	 */
	public static inline function forceClearCache():Void
		clearAllCaches();

	/** Limpia SÓLO assets de gameplay sin tocar UI/menús. */
	public static function clearGameplayCache():Void
	{
		// Limpiar atlases con prefijos de gameplay
		final prefixes = ["char_", "stage_", "skin_"];
		final toRemove:Array<String> = [];
		for (key in atlasCache.keys())
			for (p in prefixes)
				if (key.startsWith(p))
				{
					toRemove.push(key);
					break;
				}

		for (key in toRemove)
		{
			final atlas = atlasCache.get(key);
			atlasCache.remove(key);
			atlasCount--;
			if (atlas?.parent != null)
			{
				atlas.parent.destroyOnNoUse = true;
				if (atlas.parent.useCount <= 0)
					atlas.parent.destroy();
			}
		}

		// Delegar los gráficos a PathsCache
		cache.clearGameplayAssets();

		if (toRemove.length > 0)
			trace('[Paths] clearGameplayCache: ${toRemove.length} atlas(es) + gráficos de gameplay liberados.');
	}

	public static function setCacheEnabled(enabled:Bool):Void
	{
		cacheEnabled = enabled;
		if (!enabled)
			clearCache();
	}

	// ── Stats ─────────────────────────────────────────────────────────────────

	/** String compacto para el debug overlay. */
	public static function cacheDebugString():String
		return 'Atlas: $atlasCount/$maxAtlasCache  ' + cache.debugString();

	/** Stats completos. */
	public static function getCacheStats():String
		return '[Paths] Atlas=$atlasCount/$maxAtlasCache\n' + cache.fullStats();

	// ── Internos: carga de bitmaps ────────────────────────────────────────────

	/**
	 * Carga un BitmapData desde disco (via Lime) o desde assets embebidos.
	 * NO cachea nada — es el nivel más bajo de carga.
	 */
	static function _loadBitmapFromDisk(path:String):Null<Bitmap>
	{
		try
		{
			#if sys
			if (FileSystem.exists(path))
			{
				try
				{
					final bmp = Bitmap.fromFile(path);
					if (bmp != null)
						return bmp;
				}
				catch (innerE:Dynamic)
				{
					trace('[Paths] _loadBitmapFromDisk fromFile failed "$path": $innerE — trying OpenFlAssets fallback');
				}
			}
			#end
			if (!path.startsWith('/') && OpenFlAssets.exists(path, IMAGE))
				return OpenFlAssets.getBitmapData(path);
		}
		catch (e:Dynamic)
		{
			trace('[Paths] _loadBitmapFromDisk "$path": $e');
		}
		return null;
	}

	// ── Internos: atlas ───────────────────────────────────────────────────────

	/**
	 * Patrón de caché unificado para FlxAtlasFrames.
	 * Valida el atlas antes de devolverlo: si el bitmap fue dispuesto,
	 * elimina la entrada y recarga.
	 */
	static function _cachedAtlas(key:String, loader:() -> FlxAtlasFrames):FlxAtlasFrames
	{
		if (cacheEnabled && atlasCache.exists(key))
		{
			final cached = atlasCache.get(key);
			final parentOwned = cached?.parent == null || cache.hasValidGraphic(cached.parent.key);
			if (_atlasValid(cached) && parentOwned)
			{
				// Rescue: si el FlxGraphic del atlas está en _previousGraphics,
				// moverlo a _currentGraphics para que sobreviva esta sesión.
				if (cached.parent != null)
					cache.rescueFromPrevious(cached.parent.key, cached.parent);
				return cached;
			}
			// Inválido o pertenece a sesión anterior → limpiar y recargar
			atlasCache.remove(key);
			atlasCount--;
		}

		final atlas = loader();
		if (cacheEnabled && atlas != null)
			_storeAtlas(key, atlas);
		return atlas;
	}

	/**
	 * Carga Sparrow: obtiene el FlxGraphic de PathsCache (con GPU upload) y
	 * construye el FlxAtlasFrames desde el FlxGraphic + contenido del XML.
	 *
	 * Pasar FlxGraphic en vez de BitmapData a fromSparrow() garantiza que
	 * Flixel use el MISMO objeto de textura que PathsCache, sin duplicarlo.
	 */
	static function _sparrow(pngPath:String, xmlPath:String):FlxAtlasFrames
	{
		try
		{
			// Obtener o crear el FlxGraphic via PathsCache
			final graphic = _getGraphicForPath(pngPath);
			if (graphic == null)
			{
				trace('[Paths] _sparrow: PNG not found "$pngPath"');
				return null;
			}

			// Leer el XML
			final xmlContent = _readXml(xmlPath);
			if (xmlContent == null)
			{
				trace('[Paths] _sparrow: XML not found "$xmlPath"');
				return null;
			}

			// fromSparrow acepta FlxGraphic directamente — sin duplicar textura
			return FlxAtlasFrames.fromSparrow(graphic, xmlContent);
		}
		catch (e:Dynamic)
		{
			trace('[Paths] _sparrow "$pngPath": $e');
			return null;
		}
	}

	/** Variante de _sparrow que recibe el path físico directamente (no image()). */
	static function _sparrowFromPath(pngPath:String, xmlPath:String):FlxAtlasFrames
	{
		try
		{
			final graphic = _getGraphicForPath(pngPath);
			if (graphic == null)
				return null;
			final xmlContent = _readXml(xmlPath);
			if (xmlContent == null)
				return null;
			return FlxAtlasFrames.fromSparrow(graphic, xmlContent);
		}
		catch (e:Dynamic)
		{
			trace('[Paths] _sparrowFromPath "$pngPath": $e');
			return null;
		}
	}

	/** Carga Packer: igual que _sparrow pero para txt. */
	static function _packer(pngPath:String, txtPath:String):FlxAtlasFrames
	{
		try
		{
			final graphic = _getGraphicForPath(pngPath);
			if (graphic == null)
				return null;

			final txtContent = _readXml(txtPath); // reutilizar el mismo helper
			if (txtContent == null)
				return null;

			return FlxAtlasFrames.fromSpriteSheetPacker(graphic, txtContent);
		}
		catch (e:Dynamic)
		{
			trace('[Paths] _packer "$pngPath": $e');
			return null;
		}
	}

	/**
	 * Obtiene o crea un FlxGraphic para un path físico.
	 * Usa PathsCache con el path físico como clave.
	 */
	static function _getGraphicForPath(pngPath:String):Null<FlxGraphic>
	{
		// Hit rápido en PathsCache
		if (cacheEnabled && cache.hasValidGraphic(pngPath))
			return cache.peekGraphic(pngPath);

		// Cargar bitmap y registrar en PathsCache
		final bmp = _loadBitmapFromDisk(pngPath);
		if (bmp == null)
			return null;

		return cacheEnabled ? cache.getGraphic(pngPath, bmp) : FlxGraphic.fromBitmapData(bmp, false, pngPath, false);
	}

	/** Lee contenido XML/TXT desde disco o assets embebidos. */
	static function _readXml(xmlPath:String):Null<String>
	{
		try
		{
			#if sys
			if (FileSystem.exists(xmlPath))
				return File.getContent(xmlPath);
			#end
			if (OpenFlAssets.exists(xmlPath, TEXT))
				return OpenFlAssets.getText(xmlPath);
		}
		catch (e:Dynamic)
		{
			trace('[Paths] _readXml "$xmlPath": $e');
		}
		return null;
	}

	static function _storeAtlas(key:String, atlas:FlxAtlasFrames):Void
	{
		// Sin eviction durante gameplay — clearPreviousSession() libera en bloque.
		if (atlas?.parent != null)
			atlas.parent.destroyOnNoUse = false; // PathsCache gestiona el ciclo de vida
		atlasCache.set(key, atlas);
		atlasCount++;
	}

	static inline function _atlasValid(atlas:FlxAtlasFrames):Bool
	{
		try
		{
			return atlas != null && atlas.parent != null && atlas.parent.bitmap != null;
		}
		catch (_:Dynamic)
		{
			return false;
		}
	}

	/** Elimina del caché de atlas cualquier entrada cuyo FlxGraphic ya no esté en PathsCache. */
	static function _pruneInvalidAtlases():Void
	{
		final toRemove:Array<String> = [];
		for (key in atlasCache.keys())
			if (!_atlasValid(atlasCache.get(key)))
				toRemove.push(key);
		for (key in toRemove)
		{
			atlasCache.remove(key);
			atlasCount--;
		}
	}

	// ── Resolve helpers privados ──────────────────────────────────────────────

	/**
	 * Resuelve el path físico de la imagen de un stage asset.
	 * @param fromStage  Si se especifica, usa ESA carpeta de stage en lugar de currentStage.
	 */
	static function _resolveStageImagePath(key:String, ?fromStage:String):Null<String>
	{
		final lib = fromStage ?? currentStage;
		final candidates = [
			ModManager.resolveInMod('stages/$lib/images/$key.png'),
			ModManager.resolveInMod('images/stages/$key.png'),
			ModManager.resolveInMod('images/$key.png'),
		].filter(p -> p != null);

		#if sys
		for (p in candidates)
			if (FileSystem.exists(p))
				return p;
		final base = 'assets/stages/$lib/images/$key.png';
		if (FileSystem.exists(base))
			return base;
		#end
		final base = 'assets/stages/$lib/images/$key.png';
		if (OpenFlAssets.exists(base, IMAGE))
			return base;
		return null;
	}

	static function _resolveCharacterPng(key:String):String
		return resolveAny([
			ModManager.resolveInMod('characters/images/$key.png') ?? '',
			ModManager.resolveInMod('images/characters/$key.png') ?? '',
			'assets/characters/images/$key.png'
		]);

	static function _resolveCharacterXml(key:String):String
		return resolveAny([
			ModManager.resolveInMod('characters/images/$key.xml') ?? '',
			ModManager.resolveInMod('images/characters/$key.xml') ?? '',
			'assets/characters/images/$key.xml'
		]);

	static function _resolveCharacterTxt(key:String):String
		return resolveAny([
			ModManager.resolveInMod('characters/images/$key.txt') ?? '',
			ModManager.resolveInMod('images/characters/$key.txt') ?? '',
			'assets/characters/images/$key.txt'
		]);

	static function _songFolderVariants(name:String):Array<String>
	{
		final s = name.toLowerCase();
		final v:Array<String> = [];
		function add(x:String)
		{
			x = x.trim();
			if (x != '' && !v.contains(x))
				v.push(x);
		}
		add(s);
		add(s.replace(' ', '-'));
		add(s.replace('-', ' '));
		add(s.replace('!', ''));
		add(s.replace(' ', '-').replace('!', ''));
		return v;
	}

	static function _resolveSongFolder(song:String):String
	{
		#if sys
		// BUGFIX: igual que findChart(), buscar en TODOS los mods habilitados y no
		// solo en el mod activo. Sin este fix, si los archivos de audio (Inst.ogg,
		// Voices.ogg) estaban en un mod habilitado pero no activo (ej: base_game),
		// Lime tiraba error "file not found" al hacer loadStream().
		// Mod activo primero (mayor prioridad)
		if (ModManager.isActive())
		{
			final modRoot = ModManager.modRoot();
			for (v in _songFolderVariants(song))
				for (base in ['$modRoot/songs', '$modRoot/assets/songs'])
					if (sys.FileSystem.isDirectory('$base/$v'))
						return '$base/$v';
		}
		// Todos los mods instalados y habilitados
		for (mod in ModManager.installedMods)
		{
			if (!ModManager.isEnabled(mod.id))
				continue;
			final modRoot = '${ModManager.MODS_FOLDER}/${mod.id}';
			for (v in _songFolderVariants(song))
				for (base in ['$modRoot/songs', '$modRoot/assets/songs'])
					if (sys.FileSystem.isDirectory('$base/$v'))
						return '$base/$v';
		}
		for (v in _songFolderVariants(song))
			if (sys.FileSystem.isDirectory('assets/songs/$v'))
				return 'assets/songs/$v';
		#end
		return 'assets/songs/${song.toLowerCase()}';
	}
}
