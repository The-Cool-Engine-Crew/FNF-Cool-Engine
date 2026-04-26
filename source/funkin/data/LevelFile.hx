package funkin.data;

import haxe.Json;
import funkin.data.Song.SwagSong;
import funkin.data.MetaData.SongMetaData;
import mods.ModManager;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/**
 * LevelFile — Formato de nivel único (.level) estilo osu!
 * =========================================================
 *
 * OBJETIVO
 * --------
 * Un único archivo `mysong.level` reemplaza todos estos archivos:
 *
 *   mysong/
 *     mysong.json        ← chart normal
 *     mysong-easy.json   ← chart easy
 *     mysong-hard.json   ← chart hard
 *     meta.json          ← metadata (UI, noteSkin, artist…)
 *
 * …por:
 *
 *   mysong/
 *     mysong.level       ← TODO en un archivo
 *
 * ESTRUCTURA
 * ----------
 * {
 *   "version": 3,
 *   "title":   "Bopeebo",
 *   "artist":  "Kawai Sprite",
 *   "charter": "ninjamuffin99",
 *   "bpm":     180,
 *   "previewStart": 0,
 *   "previewEnd":   30000,
 *   "tags": ["week1"],
 *
 *   "meta": { ...SongMetaData... },
 *
 *   "difficulties": {
 *     "":       { ...SwagSong normal...  },
 *     "-easy":  { ...SwagSong easy...    },
 *     "-hard":  { ...SwagSong hard...    },
 *     "-erect": { ...SwagSong erect...   }
 *   }
 * }
 *
 * La clave de dificultad es el SUFIJO CON guion incluido ('' = normal).
 * Los scripts .hx siguen siendo archivos independientes.
 *
 * COMPATIBILIDAD HACIA ATRÁS
 * --------------------------
 * Si NO existe un .level pero SÍ los .json viejos, `loadDiff` los carga
 * automáticamente. `Song.findChart` y `Song.getAvailableDifficulties`
 * NO necesitan cambios — siguen funcionando con los .json legacy.
 *
 * INTEGRACIÓN CON EL CHARTING EDITOR
 * ------------------------------------
 * ChartingState debe llamar:
 *   LevelFile.saveDiff(songName, curDiffSuffix, _song, metaData);
 *
 * Esto actualiza solo la dificultad indicada en el .level existente
 * (o crea uno nuevo). El autosave usa el mismo método.
 *
 * @version 3.0.0
 */
typedef LevelData =
{
	var version:Null<Int>;
	var title:String;
	@:optional var charter:String;
	@:optional var bpm:Float;
	@:optional var previewStart:Int;
	@:optional var previewEnd:Int;
	@:optional var tags:Array<String>;
	var meta:SongMetaData;

	/** Objeto cuyas claves son sufijos de dificultad ('' = normal). */
	var difficulties:Dynamic;

	/**
	 * Datos del PlayState Editor (eventos PSE + scripts inline).
	 * Reemplaza el viejo archivo `*-playstate.json` separado.
	 */
	@:optional var pse:Null<Dynamic>;
}

class LevelFile
{
	public static inline var FORMAT_VERSION = 3;
	public static inline var EXTENSION = 'level';

	// ──────────────────────────────────────────────────────────────────────────
	//  SAVE
	// ──────────────────────────────────────────────────────────────────────────

	/**
	 * Guarda UNA dificultad dentro del .level de la canción.
	 *
	 * ── Comportamiento en el PRIMER guardado ─────────────────────────────────
	 * Si el .level no existe todavía, antes de escribir la dificultad nueva se
	 * importan automáticamente todos los archivos legacy que existan:
	 *   • mysong.json, mysong-hard.json, mysong-easy.json, … → bloque difficulties
	 *   • meta.json                                          → bloque meta
	 *   • mysong-playstate.json                              → bloque pse
	 *
	 * Después se sobreescribe la dificultad indicada con los datos recién
	 * guardados (para que el guardado actual tenga prioridad sobre el legacy).
	 *
	 * ── Guardados posteriores ─────────────────────────────────────────────────
	 * El .level ya existe: solo se actualiza el campo indicado (merge).
	 *
	 * Los archivos .json legacy NO se modifican ni se borran.
	 *
	 * @param songName   Nombre de carpeta (ej: 'bopeebo')
	 * @param diff       Sufijo de dificultad ('' = normal, '-hard', '-easy'…)
	 * @param song       SwagSong de esta dificultad
	 * @param meta       SongMetaData (null = no cambiar el bloque meta existente)
	 */
	public static function saveDiff(songName:String, diff:String, song:SwagSong, ?meta:SongMetaData):Bool
	{
		#if sys
		try
		{
			final key = songName.toLowerCase();
			final path = _targetPath(key);
			_ensureDir(path);

			// Si el .level ya existe, leerlo (para sumar la nueva dificultad a las
			// que ya están guardadas). Si no existe, migrar los archivos legacy para
			// que el .level arranque con TODAS las dificultades disponibles y no solo
			// la que se está guardando en este momento.
			var level:LevelData;
			if (FileSystem.exists(path))
			{
				level = _read(path);
			}
			else
			{
				trace('[LevelFile] saveDiff: no .level found, auto-migrating legacy files for "$key"…');
				level = _buildLevelFromLegacy(key) ?? _emptyLevel(key, song);
			}

			// Aplicar el guardado actual (tiene prioridad sobre el legacy)
			Reflect.setField(level.difficulties, diff ?? '', song);
			if (meta != null)
				level.meta = meta;
			if (song.bpm > 0)
				level.bpm = song.bpm;

			File.saveContent(path, Json.stringify(level, null, '\t'));
			trace('[LevelFile] saveDiff "$diff" → $path');
			return true;
		}
		catch (e:Dynamic)
		{
			trace('[LevelFile] saveDiff error: $e');
			return false;
		}
		#else
		return false;
		#end
	}

	/**
	 * Guarda TODAS las dificultades a la vez (ideal para importar mods).
	 *
	 * @param diffs   Map de sufijo → SwagSong
	 */
	public static function saveAll(songName:String, diffs:Map<String, SwagSong>, ?meta:SongMetaData, ?title:String, ?charter:String):Bool
	{
		#if sys
		try
		{
			final key = songName.toLowerCase();
			final path = _targetPath(key);
			_ensureDir(path);

			final normal = diffs.exists('') ? diffs.get('') : diffs.iterator().next();
			var level = _emptyLevel(key, normal);
			level.difficulties = {};

			if (title != null)
				level.title = title;
			if (charter != null)
				level.charter = charter;
			if (meta != null)
				level.meta = meta;

			for (suffix => song in diffs)
				Reflect.setField(level.difficulties, suffix ?? '', song);

			File.saveContent(path, Json.stringify(level, null, '\t'));
			trace('[LevelFile] saveAll (${Lambda.count(diffs)} diffs) → $path');
			return true;
		}
		catch (e:Dynamic)
		{
			trace('[LevelFile] saveAll error: $e');
			return false;
		}
		#else
		return false;
		#end
	}

	// ──────────────────────────────────────────────────────────────────────────
	//  PSE (PlayState Editor data)
	// ──────────────────────────────────────────────────────────────────────────

	/**
	 * Guarda los datos del PlayState Editor (eventos PSE + scripts) dentro
	 * del bloque `pse` del archivo .level.
	 *
	 * Si el .level no existe aún, primero migra todos los archivos legacy
	 * (charts .json, meta.json) antes de escribir el bloque pse.
	 */
	public static function savePSE(songName:String, pseData:Dynamic):Bool
	{
		#if sys
		try
		{
			final key = songName.toLowerCase();
			final path = _targetPath(key);
			_ensureDir(path);

			var level:LevelData;
			if (FileSystem.exists(path))
			{
				level = _read(path);
			}
			else
			{
				trace('[LevelFile] savePSE: no .level found, auto-migrating legacy files for "$key"…');
				level = _buildLevelFromLegacy(key) ?? _emptyLevel(key, null);
			}

			level.pse = pseData;
			File.saveContent(path, Json.stringify(level, null, '\t'));
			trace('[LevelFile] savePSE → $path');
			return true;
		}
		catch (e:Dynamic)
		{
			trace('[LevelFile] savePSE error: $e');
			return false;
		}
		#else
		return false;
		#end
	}

	/**
	 * Carga el bloque PSE del .level.
	 *
	 * Fallback: si no hay .level, intenta leer el archivo legacy
	 * `songname-playstate.json`.
	 *
	 * @return  Objeto `{events, scripts}` o null si no hay datos PSE.
	 */
	public static function loadPSE(songName:String):Null<Dynamic>
	{
		#if sys
		final key = songName.toLowerCase();
		final path = resolvePath(key);

		// ── 1. Bloque pse del .level ──────────────────────────────────────
		if (path != null)
		{
			try
			{
				final level = _read(path);
				if (level.pse != null)
				{
					trace('[LevelFile] loadPSE ← .level $path');
					return level.pse;
				}
			}
			catch (e:Dynamic)
			{
				trace('[LevelFile] loadPSE read error: $e');
			}
		}

		// ── 2. Fallback: archivo -playstate.json legacy ───────────────────
		for (root in _searchRoots())
		{
			for (sub in ['songs/$key', 'assets/songs/$key'])
			{
				final legacyPath = '$root/$sub/$key-playstate.json';
				if (FileSystem.exists(legacyPath))
				{
					try
					{
						final parsed:Dynamic = Json.parse(File.getContent(legacyPath));
						trace('[LevelFile] loadPSE fallback legacy: $legacyPath');
						return parsed;
					}
					catch (_)
					{
					}
				}
			}
		}
		// Assets base
		final baseLegacy = 'assets/songs/$key/$key-playstate.json';
		if (FileSystem.exists(baseLegacy))
		{
			try
			{
				return cast Json.parse(File.getContent(baseLegacy));
			}
			catch (_)
			{
			}
		}
		#end
		return null;
	}

	// ──────────────────────────────────────────────────────────────────────────
	//  LOAD
	// ──────────────────────────────────────────────────────────────────────────

	/**
	 * Carga UN chart (dificultad) intentando:
	 *   1. Archivo .level  (nuevo formato)
	 *   2. Archivo .json   (formato legacy)
	 *
	 * @param songName   Nombre de carpeta
	 * @param diff       Sufijo ('' = normal, '-hard', '-erect'…)
	 */
	public static function loadDiff(songName:String, ?diff:String = ''):Null<SwagSong>
	{
		#if sys
		final key = songName.toLowerCase();
		final path = resolvePath(key);

		// ── 1. Archivo .level ─────────────────────────────────────────────
		if (path != null)
		{
			try
			{
				final level = _read(path);
				var song:SwagSong = cast Reflect.field(level.difficulties, diff ?? '');

				// Fallback a normal si la diff pedida no existe en el .level
				if (song == null && diff != '' && diff != null)
				{
					trace('[LevelFile] "$diff" not found in .level, using normal');
					song = cast Reflect.field(level.difficulties, '');
				}

				if (song != null)
				{
					if (song.notes != null)
					{
						for (rawSec in song.notes)
						{
							var sec:Dynamic = rawSec;
							if (sec.lengthInSteps == null || sec.lengthInSteps <= 0)
							{
								var beats:Float = (sec.sectionBeats != null) ? cast sec.sectionBeats : 4.0;
								sec.lengthInSteps = Std.int(beats * 4);
							}
						}
					}
					trace('[LevelFile] loadDiff "$diff" ← $path');
					return song;
				}
			}
			catch (e:Dynamic)
			{
				trace('[LevelFile] .level read error: $e');
			}
		}

		// ── 2. Fallback a .json legacy ────────────────────────────────────
		final legacyName = _legacyDiffName(key, diff ?? '');
		final legacyPath = Song.findChart(key, legacyName);
		if (legacyPath != null)
		{
			trace('[LevelFile] loadDiff fallback legacy: $legacyPath');
			try
			{
				final raw = File.getContent(legacyPath).trim();
				// BUGFIX: pasar legacyName (sin guion: 'hard') en vez de diff ('-hard').
				// VSliceConverter normaliza por prefijo de canción, no por guion inicial.
				// '-hard' no empieza por 'darnell-' → se queda como '-hard' → miss en
				// notes['-hard'] → fallback a first key = easy. Con 'hard' matchea directo.
				return Song.parseJSONshit(raw, legacyPath, legacyName);
			}
			catch (e)
			{
				trace('[LevelFile] legacy load error: $e');
			}
		}
		#end
		return null;
	}

	/** Carga el .level completo (todas las diffs + meta). */
	public static function loadFull(songName:String):Null<LevelData>
	{
		#if sys
		final path = resolvePath(songName.toLowerCase());
		if (path == null)
			return null;
		try
		{
			return _read(path);
		}
		catch (e:Dynamic)
		{
			trace('[LevelFile] loadFull error: $e');
		}
		#end
		return null;
	}

	/**
	 * Carga el bloque meta del .level.
	 * Devuelve null si no hay .level (MetaData.load usará meta.json legacy).
	 */
	public static function loadMeta(songName:String):Null<SongMetaData>
	{
		#if sys
		final path = resolvePath(songName.toLowerCase());
		if (path != null)
		{
			try
			{
				final level = _read(path);
				if (level.meta != null)
					return level.meta;
			}
			catch (_)
			{
			}
		}
		#end
		return null;
	}

	// ──────────────────────────────────────────────────────────────────────────
	//  DIFICULTADES DISPONIBLES
	// ──────────────────────────────────────────────────────────────────────────

	/**
	 * Combina las dificultades del .level con las de los .json legacy.
	 * Devuelve Array de pares [label, suffix] como Song.getAvailableDifficulties.
	 */
	public static function getAvailableDifficulties(songName:String):Array<Array<String>>
	{
		final found:Map<String, Bool> = new Map();

		// Dificultades del .level
		#if sys
		final path = resolvePath(songName.toLowerCase());
		if (path != null)
		{
			try
			{
				final level = _read(path);
				for (dk in Reflect.fields(level.difficulties))
					found.set(dk, true);
			}
			catch (_)
			{
			}
		}
		#end

		// Dificultades legacy .json (Song ya sabe buscarlas)
		for (pair in Song.getAvailableDifficulties(songName))
			found.set(pair[1], true);

		if (!found.keys().hasNext())
			return [['Easy', '-easy'], ['Normal', ''], ['Hard', '-hard']];

		final ordered:Array<Array<String>> = [];
		final priority = [['-easy', 'Easy'], ['', 'Normal'], ['-normal', 'Normal'], ['-hard', 'Hard']];
		for (p in priority)
		{
			if (found.exists(p[0]))
			{
				ordered.push([p[1], p[0]]);
				found.remove(p[0]);
			}
		}
		final rest = [for (k in found.keys()) k];
		rest.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		for (s in rest)
		{
			final lbl = s.length > 1 ? s.substr(1, 1).toUpperCase() + s.substr(2) : s;
			ordered.push([lbl, s]);
		}
		return ordered;
	}

	// ──────────────────────────────────────────────────────────────────────────
	//  MIGRACIÓN: JSON viejos → .level
	// ──────────────────────────────────────────────────────────────────────────

	/**
	 * Convierte los .json de dificultades + meta.json en un único .level.
	 * Los archivos originales NO se borran (compatibilidad garantizada).
	 *
	 * @return true si se generó el .level correctamente
	 */
	public static function migrateFromJson(songName:String):Bool
	{
		#if sys
		final key = songName.toLowerCase();
		final diffs:Map<String, SwagSong> = new Map();
		var metaRaw:SongMetaData = null;

		// Cargar cada dificultad desde sus .json
		for (pair in Song.getAvailableDifficulties(key))
		{
			final suffix = pair[1];
			final diffName = _legacyDiffName(key, suffix);
			final chartPath = Song.findChart(key, diffName);
			if (chartPath == null)
				continue;
			try
			{
				final raw = File.getContent(chartPath).trim();
				final song = Song.parseJSONshit(raw, chartPath, suffix);
				diffs.set(suffix, song);
				trace('[LevelFile] migrate: loaded "$suffix" from $chartPath');
			}
			catch (e)
			{
				trace('[LevelFile] migrate skip "$suffix": $e');
			}
		}

		if (Lambda.count(diffs) == 0)
		{
			trace('[LevelFile] migrate: no charts found for "$key"');
			return false;
		}

		// Cargar meta.json si existe
		for (mp in [ModManager.resolveInMod('songs/$key/meta.json'), 'assets/songs/$key/meta.json'])
		{
			if (mp != null && FileSystem.exists(mp))
			{
				try
				{
					metaRaw = cast Json.parse(File.getContent(mp));
					break;
				}
				catch (_)
				{
				}
			}
		}

		final base = diffs.exists('') ? diffs.get('') : diffs.iterator().next();
		return saveAll(key, diffs, metaRaw, base?.song ?? key);
		#else
		return false;
		#end
	}

	// ──────────────────────────────────────────────────────────────────────────
	//  QUERY HELPERS
	// ──────────────────────────────────────────────────────────────────────────

	/** ¿Existe un .level para esta canción? */
	public static function exists(songName:String):Bool
		return resolvePath(songName.toLowerCase()) != null;

	/**
	 * Resuelve la ruta del .level buscando en:
	 *   1. Mod activo
	 *   2. Todos los mods habilitados
	 *   3. assets/
	 */
	public static function resolvePath(songName:String):Null<String>
	{
		#if sys
		final key = songName.toLowerCase();

		final searchRoots:Array<String> = [];

		if (ModManager.isActive())
			searchRoots.push(ModManager.modRoot());

		for (mod in ModManager.installedMods)
		{
			if (!ModManager.isEnabled(mod.id))
				continue;
			final root = '${ModManager.MODS_FOLDER}/${mod.id}';
			if (!searchRoots.contains(root))
				searchRoots.push(root);
		}

		for (root in searchRoots)
		{
			for (sub in ['songs/$key', 'assets/songs/$key'])
			{
				// charts/ subfolder (nueva estructura, prioridad sobre raíz)
				final pc = '$root/$sub/charts/$key.$EXTENSION';
				if (FileSystem.exists(pc))
					return pc;
				// raíz (compatibilidad con .level legacy)
				final p = '$root/$sub/$key.$EXTENSION';
				if (FileSystem.exists(p))
					return p;
			}
		}

		// assets base — charts/ primero, luego raíz
		final baseCharts = 'assets/songs/$key/charts/$key.$EXTENSION';
		if (FileSystem.exists(baseCharts))
			return baseCharts;
		final base = 'assets/songs/$key/$key.$EXTENSION';
		if (FileSystem.exists(base))
			return base;
		#end
		return null;
	}

	// ──────────────────────────────────────────────────────────────────────────
	//  PRIVATE
	// ──────────────────────────────────────────────────────────────────────────

	/**
	 * Determina dónde guardar el .level de una canción.
	 *
	 * Política:
	 *   • Si ya existe un .level en la raíz de la carpeta de la canción
	 *     (ubicación legacy), se usa esa ruta para no mover el archivo sin querer.
	 *   • Si no existe ninguno aún, el archivo nuevo se crea en la subcarpeta
	 *     charts/ (nueva estructura organizada).
	 *
	 * Esto garantiza compatibilidad total con mods ya publicados y que los
	 * proyectos nuevos usen la organización correcta desde el principio.
	 */
	static function _targetPath(key:String):String
	{
		#if sys
		if (ModManager.isActive())
		{
			// ¿Existe ya en la raíz (legacy)? → respetar esa ubicación
			final legacyPath = '${ModManager.modRoot()}/songs/$key/$key.$EXTENSION';
			if (FileSystem.exists(legacyPath))
				return legacyPath;
			// Nueva canción → guardar en charts/
			return '${ModManager.modRoot()}/songs/$key/charts/$key.$EXTENSION';
		}
		#end
		// Assets base: mismo criterio
		final legacyBase = 'assets/songs/$key/$key.$EXTENSION';
		if (FileSystem.exists(legacyBase))
			return legacyBase;
		return 'assets/songs/$key/charts/$key.$EXTENSION';
	}

	/** Returns all roots to search (active mod first, then all enabled mods). */
	static function _searchRoots():Array<String>
	{
		final roots:Array<String> = [];
		#if sys
		if (ModManager.isActive())
			roots.push(ModManager.modRoot());
		for (mod in ModManager.installedMods)
		{
			if (!ModManager.isEnabled(mod.id))
				continue;
			final root = '${ModManager.MODS_FOLDER}/${mod.id}';
			if (!roots.contains(root))
				roots.push(root);
		}
		#end
		return roots;
	}

	/**
	 * Construye un LevelData completo leyendo los archivos legacy existentes:
	 *   • mysong.json, mysong-hard.json, … → difficulties
	 *   • meta.json                        → meta
	 *   • mysong-playstate.json            → pse
	 *
	 * Devuelve null si no se encuentra ningún archivo legacy (canción nueva).
	 * NO escribe nada a disco — el caller decide cuándo guardar.
	 */
	static function _buildLevelFromLegacy(key:String):Null<LevelData>
	{
		#if sys
		final diffs:Map<String, SwagSong> = new Map();

		// ── Charts .json ──────────────────────────────────────────────────
		for (pair in Song.getAvailableDifficulties(key))
		{
			final suffix = pair[1];
			final diffName = _legacyDiffName(key, suffix);
			final path = Song.findChart(key, diffName);
			if (path == null)
				continue;
			try
			{
				final raw = File.getContent(path).trim();
				final song = Song.parseJSONshit(raw, path, suffix);
				diffs.set(suffix, song);
				trace('[LevelFile] _buildLevelFromLegacy: loaded diff "$suffix" from $path');
			}
			catch (e)
			{
				trace('[LevelFile] _buildLevelFromLegacy skip "$suffix": $e');
			}
		}

		if (Lambda.count(diffs) == 0)
			return null;

		// ── meta.json ─────────────────────────────────────────────────────
		var metaRaw:SongMetaData = null;
		for (mp in [
			ModManager.resolveInMod('songs/$key/meta.json'),
			ModManager.resolveInMod('assets/songs/$key/meta.json'),
			'assets/songs/$key/meta.json'
		])
		{
			if (mp != null && FileSystem.exists(mp))
			{
				try
				{
					metaRaw = cast Json.parse(File.getContent(mp));
					break;
				}
				catch (_)
				{
				}
			}
		}

		// ── -playstate.json ───────────────────────────────────────────────
		var pseRaw:Dynamic = null;
		for (root in _searchRoots().concat(['assets']))
		{
			for (sub in ['songs/$key', 'assets/songs/$key'])
			{
				final p = '$root/$sub/$key-playstate.json';
				if (FileSystem.exists(p))
				{
					try
					{
						pseRaw = Json.parse(File.getContent(p));
						break;
					}
					catch (_)
					{
					}
				}
			}
			if (pseRaw != null)
				break;
		}

		// ── Construir LevelData ───────────────────────────────────────────
		final base = diffs.exists('') ? diffs.get('') : diffs.iterator().next();
		var level = _emptyLevel(key, base);

		if (metaRaw != null)
		{
			level.meta = metaRaw;
		}

		level.difficulties = {};
		for (suffix => song in diffs)
			Reflect.setField(level.difficulties, suffix ?? '', song);

		if (pseRaw != null)
			level.pse = pseRaw;

		trace('[LevelFile] _buildLevelFromLegacy: assembled ${Lambda.count(diffs)} diffs'
			+ (metaRaw != null ? ' + meta' : '')
			+ (pseRaw != null ? ' + pse' : '')
			+ ' for "$key"');

		return level;
		#else
		return null;
		#end
	}

	static function _ensureDir(path:String):Void
	{
		#if sys
		final dir = haxe.io.Path.directory(path);
		if (!FileSystem.exists(dir))
			FileSystem.createDirectory(dir);
		#end
	}

	static function _read(path:String):LevelData
	{
		final raw:LevelData = cast Json.parse(File.getContent(path));
		_migrate(raw);
		return raw;
	}

	static function _emptyLevel(key:String, ?base:SwagSong):LevelData
	{
		return {
			version: FORMAT_VERSION,
			title: base?.song ?? key,
			charter: null,
			bpm: base?.bpm ?? 120,
			previewStart: 0,
			previewEnd: 30000,
			tags: [],
			meta: {},
			difficulties: {}
		};
	}

	/**
	 * Transforma el sufijo de dificultad en el nombre que espera Song.findChart.
	 * Ej: '' → 'bopeebo' | '-hard' → 'hard'
	 */
	static function _legacyDiffName(key:String, suffix:String):String
	{
		if (suffix == null || suffix == '')
			return key;
		return suffix.startsWith('-') ? suffix.substr(1) : suffix;
	}

	/** Migración in-place de versiones anteriores del formato. */
	static function _migrate(data:LevelData):Void
	{
		if (data.version != null && data.version >= FORMAT_VERSION)
			return;

		// v1 / v2: tenía un campo "song" directo en lugar de "difficulties"
		if (Reflect.hasField(data, 'song') && data.difficulties == null)
		{
			data.difficulties = {};
			Reflect.setField(data.difficulties, '', Reflect.field(data, 'song'));
			Reflect.deleteField(data, 'song');
			trace('[LevelFile] migrated v${data.version ?? 1} → v$FORMAT_VERSION');
		}

		if (data.meta == null)
			data.meta = {};
		data.version = FORMAT_VERSION;
	}
}
