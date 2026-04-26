package mods.compat;

using StringTools;

import haxe.Json;
import funkin.data.Song;
import funkin.data.Section;

/**
 * VSliceConverter
 * ─────────────────────────────────────────────────────────────────────────────
 * Converts the Friday Night Funkin' v0.5+ chart format (V-Slice / "2.0.0")
 * into the native Cool Engine SwagSong format.
 *
 * ── V-Slice Chart Structure ──────────────────────────────────────────────────
 *
 *  {
 *    "version": "2.0.0",
 *    "generatedBy": "Friday Night Funkin' - v0.8.1",
 *    "scrollSpeed": { "erect": 2.2, "nightmare": 2.8 },
 *    "events": [
 *      { "t": 0,     "e": "FocusCamera",  "v": { "char": 1, "x": 0, "y": 0 } },
 *      { "t": 1234,  "e": "ZoomCamera",   "v": { "zoom": 1.2, "ease": "expoOut", "duration": 32, "mode": "stage" } },
 *      { "t": 5678,  "e": "SetCameraBop", "v": { "rate": 2, "intensity": 1 } }
 *    ],
 *    "notes": {
 *      "erect": [
 *        { "t": 759.49, "d": 7 },
 *        { "t": 806.96, "d": 6, "l": 237.34 },
 *        { "t": 1518.99, "d": 3, "l": 427.22, "k": "hurt" }
 *      ],
 *      "nightmare": [ ... ]
 *    }
 *  }
 *
 * ── Direction/Lane Encoding (field "d") ──────────────────────────────────────
 *
 *  d = direction + (strumlineIndex * 4)
 *
 *    d 0-3  → strumline 0 (player / BF)    → lane 0-3  in Cool Engine
 *    d 4-7  → strumline 1 (opponent / Dad) → lane 4-7  in Cool Engine
 *    d 8-11 → strumline 2 (extra)          → lane 8-11 in Cool Engine
 *
 *  Inside each strumline:
 *    %4 == 0 → Left  (0)
 *    %4 == 1 → Down  (1)
 *    %4 == 2 → Up    (2)
 *    %4 == 3 → Right (3)
 *
 *  The V-Slice "d" value directly matches the rawNoteData expected by
 *  Cool Engine in sectionNotes[1], so NO transformation is required.
 *
 * ── Metadata File (separate) ─────────────────────────────────────────────────
 *
 *  V-Slice separates the chart from the metadata. If the chart path
 *  is known (passed as `chartFilePath`), the converter automatically searches:
 *
 *    songs/{folder}/{folder}-metadata.json
 *    songs/{folder}/metadata.json
 *    songs/{folder}/{folder}-metadata-{variation}.json  (e.g. erect)
 *
 *  Metadata contains: BPM (timeChanges), characters, stage, etc.
 *
 *  Metadata example:
 *  {
 *    "version": "2.2.0",
 *    "songName": "Senpai",
 *    "artist": "Kawai Sprite",
 *    "timeChanges": [ { "t": 0, "bpm": 115 }, { "t": 4500, "bpm": 120 } ],
 *    "playData": {
 *      "stage": "school",
 *      "characters": { "player": "bf-pixel", "girlfriend": "gf-pixel", "opponent": "senpai" },
 *      "difficulties": ["easy", "normal", "hard", "erect", "nightmare"]
 *    }
 *  }
 *
 * ── Supported V-Slice Events ─────────────────────────────────────────────────
 *
 *  FocusCamera  → Camera Follow   (char 0=bf, 1=dad, 2=gf)
 *  ZoomCamera   → Camera Zoom     (zoom|duration)
 *  SetCameraBop → Camera Bop Rate (rate)
 *  PlayAnimation → Play Anim      (target:anim)
 *  SetCharacter  → Change Character
 *  (others)      → pass-through
 */
class VSliceConverter
{
	// ── Entry point ───────────────────────────────────────────────────────────

	/**
	 * Convierte un chart V-Slice al formato SwagSong de Cool Engine.
	 *
	 * @param rawJson       Contenido JSON del archivo de chart.
	 * @param difficulty    Dificultad a extraer (ej: "erect", "hard").
	 * @param chartFilePath Path físico al archivo .json (para buscar metadata).
	 */
	public static function convertChart(rawJson:String, difficulty:String = 'hard', ?chartFilePath:String):SwagSong
	{
		trace('[VSliceConverter] Converting chart (diff=$difficulty)...');

		final root:Dynamic = Json.parse(rawJson);

		// Normalizar dificultad: si viene como "ugh-erect" (nombre de archivo completo),
		// extraer solo la parte de dificultad real ("erect") quitando el prefijo de canción.
		// Esto ocurre porque Song.loadFromJson pasa el filename como diff ("ugh-erect").
		if (chartFilePath != null && chartFilePath != '')
		{
			final folderName = _songFolderFromPath(chartFilePath).name;
			final prefix = folderName + '-';
			if (difficulty.toLowerCase().startsWith(prefix))
				difficulty = difficulty.substr(prefix.length);
		}

		trace('[VSliceConverter] difficulty normalizada: $difficulty');

		// ── 1. Cargar metadata (BPM, personajes, stage) ──────────────────────
		final meta = _loadMetadata(root, chartFilePath, difficulty);

		final bpm:Float = meta.bpm;
		final stage:String = meta.stage;
		final player:String = meta.player;
		final gf:String = meta.gf;
		final opponent:String = meta.opponent;
		final timeChanges:Array<{t:Float, bpm:Float}> = meta.timeChanges;

		// ── 2. Determinar scroll speed ────────────────────────────────────────
		final scrollSpeedObj:Dynamic = root.scrollSpeed;
		var speed:Float = 1.0;
		if (scrollSpeedObj != null)
		{
			// Buscar la dificultad exacta, luego sin case, luego usar primera disponible
			var found:Null<Float> = null;
			for (d in _diffVariants(difficulty))
			{
				final v = Reflect.field(scrollSpeedObj, d);
				if (v != null)
				{
					found = _float(v, 1.0);
					break;
				}
			}
			if (found == null)
			{
				// Primera key del objeto
				for (k in Reflect.fields(scrollSpeedObj))
				{
					found = _float(Reflect.field(scrollSpeedObj, k), 1.0);
					break;
				}
			}
			if (found != null)
				speed = found;
		}

		// ── 3. Construir SwagSong base ────────────────────────────────────────
		// IMPORTANTE: song.song debe ser el nombre de CARPETA (ej: "senpai", "high")
		// y NO el display name del metadata (ej: "Senpai Erect", "High Erect").
		// Se usa en _resolveSongFolder() para buscar Inst.ogg, Voices.ogg, etc.
		// Si tenemos el path del chart, derivamos el folder name desde ahí.
		// Si no, usamos el songName en lowercase como fallback.
		final songFolder:String = (chartFilePath != null && chartFilePath != '')
			? _songFolderFromPath(chartFilePath).name
			: meta.songName.toLowerCase();

		final song:SwagSong = {
			song: songFolder,
			bpm: bpm,
			speed: speed,
			needsVoices: true,
			stage: stage,
			validScore: true,
			notes: [],
			// Legacy fields (para que Song.parseJSONshit migre a nuevo sistema)
			player1: player,
			player2: opponent,
			gfVersion: gf,
			characters: null,
			strumsGroups: null,
			events: [],
			// V-Slice audio variation override
			instSuffix: (meta.instrumental != null && meta.instrumental != '') ? meta.instrumental : null,
			artist: (meta.artist != null && meta.artist != '') ? meta.artist : null
		};

		// ── 4. Obtener las notas para esta dificultad ─────────────────────────
		final allNotes:Dynamic = root.notes;
		var diffNotes:Array<Dynamic> = [];
		if (allNotes != null)
		{
			for (d in _diffVariants(difficulty))
			{
				final n = Reflect.field(allNotes, d);
				if (n != null && Std.isOfType(n, Array))
				{
					diffNotes = cast n;
					break;
				}
			}
			// ── Fallback progresivo para sufijos compuestos (ej: "easy-bf") ──────
			// Si la dificultad normalizada tiene la forma "{diff}-{variation}" y no
			// matchea ninguna clave del objeto notes, quitamos el último segmento
			// iterativamente hasta encontrar una clave válida.
			// Ejemplo: "easy-bf" → intenta "easy" → MATCH en notes.easy ✓
			// Esto cubre los charts de variación V-Slice (lit_up-bf.json) donde las
			// claves del objeto notes son las dificultades reales (easy/normal/hard),
			// no el nombre de la variación.
			if (diffNotes.length == 0)
			{
				var stripped = difficulty;
				while (diffNotes.length == 0)
				{
					final lastDash = stripped.lastIndexOf('-');
					if (lastDash <= 0) break;
					stripped = stripped.substr(0, lastDash);
					for (d in _diffVariants(stripped))
					{
						final n = Reflect.field(allNotes, d);
						if (n != null && Std.isOfType(n, Array))
						{
							diffNotes = cast n;
							trace('[VSliceConverter] Notas encontradas por fallback progresivo: "$d" (de "$difficulty")');
							break;
						}
					}
				}
			}
			// Último recurso: usar la primera dificultad disponible
			if (diffNotes.length == 0)
			{
				for (k in Reflect.fields(allNotes))
				{
					final n = Reflect.field(allNotes, k);
					if (n != null && Std.isOfType(n, Array))
					{
						diffNotes = cast n;
						trace('[VSliceConverter] Notas: usando primera disponible ("$k") como último recurso');
						break;
					}
				}
			}
		}

		// ── 5. Convertir notas a secciones ────────────────────────────────────
		_buildSections(song, diffNotes, timeChanges);

		// ── 6. Convertir eventos ──────────────────────────────────────────────
		final rawEvents:Dynamic = root.events;
		if (rawEvents != null && Std.isOfType(rawEvents, Array))
		{
			final evArr:Array<Dynamic> = cast rawEvents;
			for (ev in evArr)
			{
				final timeMs:Float = _float(ev.t, 0);
				final stepTime:Float = _msToStep(timeMs, bpm);
				final kind:String = _str(ev.e, '');
				final value:Dynamic = ev.v;

				final mapped = _mapEvent(kind, value);
				if (mapped != null)
					song.events.push({stepTime: stepTime, type: mapped.type, value: mapped.value});
			}
		}

		// ── 7. Eventos de BPM change desde timeChanges ───────────────────────
		// Solo añadir los cambios secundarios (el primero es el BPM base)
		for (i in 1...timeChanges.length)
		{
			final tc = timeChanges[i];
			final stepTime = _msToStep(tc.t, bpm);
			song.events.push({stepTime: stepTime, type: 'BPM Change', value: Std.string(tc.bpm)});
		}

		trace('[VSliceConverter] Done. Sections=${song.notes.length}, Events=${song.events.length}, BPM=$bpm, Stage=$stage');
		return song;
	}

	// ── Secciones ─────────────────────────────────────────────────────────────

	/**
	 * Agrupa las notas V-Slice en secciones de 16 pasos.
	 *
	 * Cada sección tiene una duración determinada por el BPM vigente en ese punto.
	 * Con múltiples timeChanges se recalcula la duración de sección dinámicamente.
	 *
	 * mustHitSection se determina por la mayoría de notas en esa sección:
	 *   - Si la mayoría son del jugador (d < 4), mustHitSection = true
	 *   - Si la mayoría son del oponente (d >= 4), mustHitSection = false
	 */
	static function _buildSections(song:SwagSong, notes:Array<Dynamic>, timeChanges:Array<{t:Float, bpm:Float}>):Void
	{
		if (notes == null || notes.length == 0)
		{
			// Al menos una sección vacía para que el engine no crashee
			song.notes.push(_emptySection(song.bpm, true));
			return;
		}

		// Ordenar notas por tiempo
		notes.sort((a, b) -> (_float(a.t, 0) < _float(b.t, 0)) ? -1 : 1);

		// Duración de una sección = 16 pasos = 4 beats
		// stepDurationMs = (60000 / bpm) / 4
		// sectionDurationMs = 16 * stepDurationMs = (60000 / bpm) * 4

		// Construir mapa de tiempo→BPM desde timeChanges
		final tcList = timeChanges.copy();
		tcList.sort((a, b) -> a.t < b.t ? -1 : 1);

		// Calcular dónde cae cada sección (en ms) para asignar notas correctamente
		final lastNoteTime:Float = _float(notes[notes.length - 1].t, 0) + _float(notes[notes.length - 1].l, 0);

		// Generar posiciones de secciones hasta cubrir todas las notas + 1 extra
		final sectionStarts:Array<Float> = [];
		final sectionBpms:Array<Float> = [];
		final sectionMustHits:Array<Bool> = [];
		final sectionNoteArrays:Array<Array<Dynamic>> = [];

		var cursor:Float = 0; // ms desde el inicio
		var currentBpm:Float = (tcList.length > 0) ? tcList[0].bpm : song.bpm;
		var tcIdx:Int = 1; // índice al siguiente cambio de BPM pendiente

		while (cursor <= lastNoteTime + _sectionDurationMs(currentBpm))
		{
			// Actualizar BPM si hay un cambio antes del cursor actual
			while (tcIdx < tcList.length && tcList[tcIdx].t <= cursor)
			{
				currentBpm = tcList[tcIdx].bpm;
				tcIdx++;
			}

			sectionStarts.push(cursor);
			sectionBpms.push(currentBpm);
			sectionNoteArrays.push([]);

			cursor += _sectionDurationMs(currentBpm);
		}

		// Asignar cada nota a su sección
		// altAnim: se activa cuando las notas CPU de una sección tienen un kind que
		// indica un personaje alt (ej: "mom" en Eggnog, "dad-car" en algunas canciones).
		// En V-Slice el campo "k" (kind) de las notas del oponente (d >= 4) se usa
		// para distinguir qué personaje canta — si no es el oponente base, es altAnim.
		final sectionAltAnims:Array<Bool> = [for (_ in 0...sectionStarts.length) false];

		// Kinds que indican animación alt del oponente.
		// "mom" es el más común (Eggnog/Cocoa/Eggnoggin), pero admitimos cualquier
		// kind en notas CPU que NO sea un tipo de nota normal (hurt, mine, etc.).
		final _normalNoteKinds = ['', 'hurt', 'mine', 'bomb', 'hazard', 'default', 'normal'];

		for (n in notes)
		{
			final t:Float = _float(n.t, 0);
			// Buscar sección por tiempo
			var secIdx:Int = sectionStarts.length - 1;
			for (i in 0...sectionStarts.length - 1)
			{
				if (t < sectionStarts[i + 1])
				{
					secIdx = i;
					break;
				}
			}
			// El "d" de V-Slice = lane directamente en Cool Engine
			final lane:Int = Std.int(_float(n.d, 0));
			final hold:Float = _float(n.l, 0);
			final kind:String = (n.k != null) ? Std.string(n.k).toLowerCase() : '';

			// Detectar altAnim: nota CPU (lane >= 4) con un kind que no sea tipo
			// de nota estándar → el oponente usa personaje/animación alternativa
			if (lane >= 4 && kind != '' && !_normalNoteKinds.contains(kind))
				sectionAltAnims[secIdx] = true;

			if (kind != '')
				sectionNoteArrays[secIdx].push([t, lane, hold, kind]);
			else
				sectionNoteArrays[secIdx].push([t, lane, hold]);
		}

		// Determinar mustHitSection.
		// En V-Slice la asignación de notas a strumlines está FIJA:
		//   d 0-3 (groupIdx=0) → siempre jugador (BF)
		//   d 4-7 (groupIdx=1) → siempre oponente (Dad/CPU)
		// NoteManager deriva quién toca una nota así:
		//   groupIdx 0 → gottaHitNote = mustHitSection
		//   groupIdx 1 → gottaHitNote = !mustHitSection
		// Para que esto funcione correctamente con el encoding absoluto de V-Slice,
		// mustHitSection DEBE ser true en TODAS las secciones.
		// Si fuera false, las notas d 0-3 irían al CPU y d 4-7 al jugador — incorrecto.
		// La cámara se controla con eventos FocusCamera, no con mustHitSection.
		for (i in 0...sectionNoteArrays.length)
			sectionMustHits.push(true);

		// Añadir secciones al song (omitir las completamente vacías al final)
		var lastNonEmpty:Int = 0;
		for (i in 0...sectionNoteArrays.length)
			if (sectionNoteArrays[i].length > 0)
				lastNonEmpty = i;

		for (i in 0...(lastNonEmpty + 2)) // +2 = incluir última vacía de cierre
		{
			if (i >= sectionStarts.length)
				break;
			song.notes.push({
				sectionNotes: i < sectionNoteArrays.length ? sectionNoteArrays[i] : [],
				lengthInSteps: 16,
				typeOfSection: 0,
				mustHitSection: i < sectionMustHits.length ? sectionMustHits[i] : true,
				bpm: i < sectionBpms.length ? sectionBpms[i] : song.bpm,
				changeBPM: i > 0 && i < sectionBpms.length && sectionBpms[i] != sectionBpms[i - 1],
				altAnim: i < sectionAltAnims.length ? sectionAltAnims[i] : false
			});
		}
	}

	static inline function _sectionDurationMs(bpm:Float):Float
		return (60000.0 / bpm) * 4.0; // 16 steps = 4 beats

	static function _emptySection(bpm:Float, mustHit:Bool):SwagSection
	{
		return {
			sectionNotes: [],
			lengthInSteps: 16,
			typeOfSection: 0,
			mustHitSection: mustHit,
			bpm: bpm,
			changeBPM: false,
			altAnim: false
		};
	}

	// ── Eventos ───────────────────────────────────────────────────────────────

	/**
	 * Convierte un evento V-Slice a su equivalente en Cool Engine.
	 * Devuelve null si el evento debe ignorarse.
	 */
	static function _mapEvent(kind:String, value:Dynamic):Null<{type:String, value:String}>
	{
		return switch (kind.toLowerCase())
		{
			// ── Cámara ────────────────────────────────────────────────────────
			case 'focuscamera', 'focus camera':
				/*
				 * V-Slice char index:
				 *   0  = player (BF)
				 *   1  = opponent (Dad)
				 *   2  = girlfriend (GF)
				 *  -1  = posición absoluta (x,y)
				 *
				 * "value" puede ser:
				 *   • Un número puro  → { "v": 1 }  — es el charIdx directamente.
				 *   • Un objeto       → { "v": { "char": 1, "x": 0, "y": 0, … } }
				 *
				 * Formato de value en Cool Engine:
				 *   "target|offsetX|offsetY|duration|ease"
				 *   (campos opcionales; solo target es obligatorio)
				 */
				// BUG FIX: cuando value es un número puro (v: 0, v: 1, v: 2),
				// ese número ES el charIdx. Leer value.char en un número siempre
				// devuelve null → charIdx = 0 → siempre BF, ignorando al oponente/GF.
				final isPlainNumber:Bool = value != null && Std.isOfType(value, Float);
				final charIdx:Int = if (value == null)
					0;
				else if (isPlainNumber)
					Std.int(_float(value, 0));
				else
					Std.int(_float(value.char, 0));

				final target = switch (charIdx)
				{
					case -1: 'position';
					case 0:  'bf';
					case 1:  'dad';
					case 2:  'gf';
					default: 'bf';
				};
				final offX:Float   = (!isPlainNumber && value != null) ? _float(value.x, 0.0) : 0.0;
				final offY:Float   = (!isPlainNumber && value != null) ? _float(value.y, 0.0) : 0.0;
				final dur:Float    = (!isPlainNumber && value != null) ? _float(value.duration, 0.0) : 0.0;
				// Construir ease completo: "expo" + "Out" → "expoOut"
				var ease:String = (!isPlainNumber && value != null) ? _str(value.ease, '') : '';
				if (ease != '' && ease != 'CLASSIC' && ease != 'INSTANT' && ease != 'linear')
				{
					final easeDir:String = (!isPlainNumber && value != null) ? _str(value.easeDir, '') : '';
					if (easeDir != '') ease = ease + easeDir;
				}

				// HaxeFlixel no tiene variantes In/Out para smoothStep ni smootherStep —
				// solo existe la función base. Normalizar para evitar que Reflect.field()
				// devuelva null y el tween no se dispare.
				ease = switch (ease.toLowerCase())
				{
					case 'smoothstepinout' | 'smoothstepin' | 'smoothstepout': 'smoothStep';
					case 'smootherstepinout' | 'smootherstepin' | 'smootherstepout': 'smootherStep';
					default: ease;
				};

				// CLASSIC = snap del follow point sin tween (comportamiento por defecto).
				// INSTANT = snap instantáneo (duración 0).
				// Ambos se traducen a un Camera Follow simple sin duration/ease.
				final isSnap = (ease == 'CLASSIC' || ease == 'INSTANT');

				var composed = target;
				if (!isSnap && (offX != 0 || offY != 0 || dur > 0 || (ease != '' && ease != 'linear')))
				{
					composed += '|$offX|$offY';
					if (dur > 0 || ease != '')
					{
						composed += '|$dur';
						if (ease != '') composed += '|$ease';
					}
				}
				else if (!isSnap && (offX != 0 || offY != 0))
				{
					composed += '|$offX|$offY';
				}
				{type: 'Camera Follow', value: composed};

			case 'zoomcamera', 'zoom camera':
				/*
				 * V-Slice: { zoom, ease, duration, mode }
				 * Cool Engine: "Camera Zoom" with value "zoom|duration"
				 */
				final zoom = value != null ? _str(value.zoom, '1') : '1';
				final duration = value != null ? _str(value.duration, '4') : '4';
				final ease = value != null ? _str(value.ease, '') : '';
				final mode = value != null ? _str(value.mode, '') : '';
				var composed = '$zoom|$duration';
				if (ease != '')
					composed += '|$ease';
				if (mode != '')
					composed += '|$mode';
				{type: 'Camera Zoom', value: composed};

			case 'setcamerabop', 'set camera bop', 'camerabop':
				final rate = value != null ? _str(value.rate, '1') : '1';
				{type: 'Camera Bop Rate', value: rate};

			// ── Animaciones ───────────────────────────────────────────────────
			case 'playanimation', 'play animation', 'play anim':
				/*
				 * V-Slice: { targetCharacterId, animation, force }
				 * Cool Engine: "Play Anim" with value "target:anim"
				 */
				if (value == null) {
					type: 'Play Anim', 
					value: 'bf:idle'
				}
				else
				{
					final target = _str(value.targetCharacterId ?? value.target, 'bf');
					final anim = _str(value.animation ?? value.anim, 'idle');
					{type: 'Play Anim', value: '$target:$anim'};
				}

			// ── Personajes ────────────────────────────────────────────────────
			case 'setcharacter', 'set character', 'change character':
				if (value == null) null; else
				{
					final target = _str(value.targetCharacterId ?? value.target, 'bf');
					final character = _str(value.characterId ?? value.character, 'bf');
					{type: 'Change Character', value: '$target|$character'};
				}

			// ── Salud ─────────────────────────────────────────────────────────
			case 'sethealth', 'set health', 'health':
				if (value == null) null; else {type: 'Health Change', value: _str(value.value ?? value.health, '1')};

			// ── HUD ───────────────────────────────────────────────────────────
			case 'sethudvisible', 'set hud visible', 'togglehud', 'toggle hud':
				{type: 'HUD Visible', value: 'toggle'};

			// ── Stage ─────────────────────────────────────────────────────────
			case 'setstage', 'set stage', 'changestage', 'change stage':
				if (value == null) null; else {type: 'Change Stage', value: _str(value.stageId ?? value.stage, 'stage')};

			// ── Desconocidos: pasar tal cual ──────────────────────────────────
			default:
				final valStr = (value != null) ? Json.stringify(value) : '';
				{type: kind, value: valStr};
		};
	}

	// ── Carga de metadata ─────────────────────────────────────────────────────

	/**
	 * Estructura de metadata resuelta (para uso interno).
	 */
	static var _MetaResult = {
		bpm: 100.0,
		stage: 'stage',
		player: 'bf',
		gf: 'gf',
		opponent: 'dad',
		songName: 'Unknown',
		timeChanges: new Array<{t:Float, bpm:Float}>()
	};

	/**
	 * Intenta cargar la metadata del song V-Slice.
	 *
	 * Orden de búsqueda (usando chartFilePath para determinar la carpeta):
	 *   1. {folder}/{songName}-metadata.json
	 *   2. {folder}/metadata.json
	 *   3. {folder}/{songName}-metadata-{variation}.json  (ej: senpai-metadata-erect.json)
	 *
	 * Si no se encuentra nada, usa valores por defecto.
	 */
	static function _loadMetadata(chartRoot:Dynamic, chartFilePath:Null<String>, difficulty:String):Dynamic
	{
		// Objeto resultado con defaults
		final result = {
			bpm: 100.0,
			stage: 'stage_week1',
			player: 'bf',
			gf: 'gf',
			opponent: 'dad',
			songName: 'Unknown',
			artist: '',
			instrumental: '',   // V-Slice: playData.characters.instrumental
			timeChanges: new Array<{t:Float, bpm:Float}>()
		};

		#if sys
		// Determinar la carpeta del chart.
		// FIX: usar _songFolderFromPath() en lugar de _parentDir() crudo.
		// Cuando el chart está en un subdirectorio charts/ (estructura V-Slice estándar):
		//   songs/bopeebo/charts/bopeebo-erect.json
		//   → _parentDir() daba dir="songs/bopeebo/charts", folderName="charts"  ← INCORRECTO
		//   → _songFolderFromPath() da  dir="songs/bopeebo",        name="bopeebo" ← CORRECTO
		// Sin este fix, genericCandidates buscaba "charts/charts-metadata.json" y
		// specificCandidates buscaba "charts/charts-metadata-erect.json", ninguno existe.
		if (chartFilePath != null && chartFilePath != '')
		{
			final songInfo = _songFolderFromPath(chartFilePath);
			final dir = songInfo.dir;         // raíz real de la canción (ej: songs/bopeebo)
			final folderName = songInfo.name; // nombre real del folder  (ej: bopeebo)
			result.songName = _capitalize(folderName);

			// Si la dificultad viene como "ugh-erect" (nombre de archivo completo),
			// extraer solo la parte de dificultad quitando el prefijo "ugh-".
			// Esto cubre loadFromJson que pasa el filename completo como diff.
			var cleanDiff = difficulty.toLowerCase();
			final prefix = folderName.toLowerCase() + '-';
			if (cleanDiff.startsWith(prefix))
				cleanDiff = cleanDiff.substr(prefix.length);

			// Variantes de casing del difficulty limpio (erect/Erect/ERECT)
			final _diffVarsFile:Array<String> = [];
			{
				inline function _addDV(v:String) if (v != '' && !_diffVarsFile.contains(v)) _diffVarsFile.push(v);
				_addDV(cleanDiff.toLowerCase());
				_addDV(cleanDiff.toUpperCase());
				_addDV(cleanDiff.charAt(0).toUpperCase() + cleanDiff.substr(1).toLowerCase());
				_addDV(cleanDiff);
				// También añadir la variante original por si acaso
				_addDV(difficulty.toLowerCase());
				_addDV(difficulty);
			}

			// ── Carga en dos pasos ────────────────────────────────────────────────────
			// Paso 1: metadata genérica (valores base: stage, BPM, personajes, artist)
			// Paso 2: metadata específica de dificultad (override: instrumental, artist…)
			//
			// Así, si senpai-metadata-erect.json tiene un "artist" distinto o un
			// "instrumental" diferente, tiene prioridad sobre el metadata base.
			// Si el campo no aparece en el metadata específico, se conserva el del base.
			final genericCandidates:Array<String> = [
				'$dir/${folderName}-metadata-default.json',
				'$dir/$folderName-metadata.json',
				'$dir/metadata.json',
			];

			// specificCandidates: busca bopeebo-metadata-erect.json en la raíz de la
			// canción (dir). Antes se buscaba en _parentDir() que podía ser charts/,
			// por lo que este archivo nunca se encontraba.
			final specificCandidates:Array<String> = [];
			for (_dv in _diffVarsFile)
				specificCandidates.push('$dir/${folderName}-metadata-${_dv}.json');

			// ── Fallback progresivo para sufijos compuestos (ej: cleanDiff = "easy-bf") ──
			// Si cleanDiff tiene forma "{diff}-{variation}", también buscamos el metadata
			// usando solo la variación como clave ("bf" → lit_up-metadata-bf.json).
			// Esto cubre charts de variación V-Slice donde el metadata de variación NO lleva
			// el nombre de la dificultad en el nombre del archivo.
			{
				var _stripped = cleanDiff;
				while (true)
				{
					final _ld = _stripped.lastIndexOf('-');
					if (_ld <= 0) break;
					_stripped = _stripped.substr(_ld + 1); // queda solo "bf"
					final _strippedVars = _diffVariants(_stripped);
					for (_sv in _strippedVars)
					{
						final _cand = '$dir/${folderName}-metadata-${_sv}.json';
						if (!specificCandidates.contains(_cand))
							specificCandidates.push(_cand);
					}
					break; // solo un nivel de stripping es suficiente
				}
			}

			// Paso 1 — base
			for (path in genericCandidates)
			{
				if (!sys.FileSystem.exists(path)) continue;
				try
				{
					final meta:Dynamic = Json.parse(sys.io.File.getContent(path));
					_applyMetadata(meta, result);
					trace('[VSliceConverter] Metadata base desde: $path');
					break;
				}
				catch (e:Dynamic) { trace('[VSliceConverter] Error leyendo metadata "$path": $e'); }
			}

			// Paso 2 — específica de dificultad (override, artist incluido)
			for (path in specificCandidates)
			{
				if (!sys.FileSystem.exists(path)) continue;
				try
				{
					final meta:Dynamic = Json.parse(sys.io.File.getContent(path));
					_applyMetadata(meta, result);
					trace('[VSliceConverter] Metadata específica (diff=$cleanDiff) desde: $path');
					break;
				}
				catch (e:Dynamic) { trace('[VSliceConverter] Error leyendo metadata "$path": $e'); }
			}

			// BUGFIX: Si los charts están en assets/ pero la metadata está en un mod
			// (ej: base_game), buscar en todos los mods habilitados con el mismo esquema
			// de dos pasos para respetar la prioridad del artist por dificultad.
			if (result.stage == 'stage_week1' && result.player == 'bf' && result.opponent == 'dad')
			{
				for (mod in mods.ModManager.installedMods)
				{
					if (!mods.ModManager.isEnabled(mod.id)) continue;
					final modSongDir = '${mods.ModManager.MODS_FOLDER}/${mod.id}/songs/$folderName';
					if (!sys.FileSystem.exists(modSongDir)) continue;

					final modGeneric:Array<String> = [
						'$modSongDir/${folderName}-metadata-default.json',
						'$modSongDir/$folderName-metadata.json',
						'$modSongDir/metadata.json',
					];
					final modSpecific:Array<String> = [];
					for (_dv in _diffVarsFile)
						modSpecific.push('$modSongDir/${folderName}-metadata-${_dv}.json');

					var foundInMod = false;
					// Paso 1 mod — base
					for (mpath in modGeneric)
					{
						if (!sys.FileSystem.exists(mpath)) continue;
						try
						{
							final meta:Dynamic = Json.parse(sys.io.File.getContent(mpath));
							_applyMetadata(meta, result);
							trace('[VSliceConverter] Metadata base mod "${mod.id}": $mpath');
							foundInMod = true;
							break;
						}
						catch (e:Dynamic) { trace('[VSliceConverter] Error metadata mod "$mpath": $e'); }
					}
					// Paso 2 mod — específica (artist override)
					for (mpath in modSpecific)
					{
						if (!sys.FileSystem.exists(mpath)) continue;
						try
						{
							final meta:Dynamic = Json.parse(sys.io.File.getContent(mpath));
							_applyMetadata(meta, result);
							trace('[VSliceConverter] Metadata específica mod "${mod.id}": $mpath');
							foundInMod = true;
							break;
						}
						catch (e:Dynamic) { trace('[VSliceConverter] Error metadata mod "$mpath": $e'); }
					}
					if (foundInMod) break;
				}
			}
		}
		#end

		// Si no encontramos metadata, intentar extraer BPM de los eventos del chart
		// (algunos charts V-Slice tienen "timeChanges" en el propio chart - V-Slice 2.1+)
		if (result.timeChanges.length == 0)
		{
			final chartTc:Dynamic = chartRoot.timeChanges;
			if (chartTc != null && Std.isOfType(chartTc, Array))
				_parseTimeChanges(cast chartTc, result);
		}

		// BPM fallback: usar el primero de timeChanges
		if (result.timeChanges.length > 0)
			result.bpm = result.timeChanges[0].bpm;
		else
			result.timeChanges.push({t: 0.0, bpm: result.bpm});

		return result;
	}

	/** Aplica los campos de un JSON de metadata al objeto resultado. */
	static function _applyMetadata(meta:Dynamic, result:Dynamic):Void
	{
		// ── Nombre ───────────────────────────────────────────────────────────
		if (meta.songName != null)
			result.songName = _str(meta.songName, result.songName);

		// ── Artista ───────────────────────────────────────────────────────────
		if (meta.artist != null)
			result.artist = _str(meta.artist, result.artist);

		// ── BPM / timeChanges ─────────────────────────────────────────────────
		final tcRaw:Dynamic = meta.timeChanges;
		if (tcRaw != null && Std.isOfType(tcRaw, Array))
			_parseTimeChanges(cast tcRaw, result);

		// ── playData ─────────────────────────────────────────────────────────
		final pd:Dynamic = meta.playData;
		if (pd != null)
		{
			if (pd.stage != null)
				result.stage = _str(pd.stage, result.stage);

			final chars:Dynamic = pd.characters;
			if (chars != null)
			{
				if (chars.player != null)
					result.player = _str(chars.player, result.player);
				if (chars.girlfriend != null)
					result.gf = _str(chars.girlfriend, result.gf);
				if (chars.opponent != null)
					result.opponent = _str(chars.opponent, result.opponent);
				// V-Slice: campo "instrumental" → variante de audio a usar
				// (puede diferir de la dificultad; ej: nightmare usa audio "erect")
				if (chars.instrumental != null)
					result.instrumental = _str(chars.instrumental, result.instrumental);
			}
		}
	}

	/** Parsea un array de timeChanges V-Slice → array de {t, bpm}. */
	static function _parseTimeChanges(arr:Array<Dynamic>, result:Dynamic):Void
	{
		result.timeChanges = [];
		for (tc in arr)
		{
			final t = _float(tc.t ?? tc.time ?? tc.timeStamp, 0.0);
			final bpm = _float(tc.bpm ?? tc.BPM, 100.0);
			if (bpm > 0)
				result.timeChanges.push({t: t, bpm: bpm});
		}
		if (result.timeChanges.length > 0)
			result.bpm = result.timeChanges[0].bpm;
	}

	// ── Helpers de rutas ──────────────────────────────────────────────────────

	static function _parentDir(path:String):String
	{
		final sep1 = path.lastIndexOf('/');
		final sep2 = path.lastIndexOf('\\');
		final sep = Std.int(Math.max(sep1, sep2));
		return sep >= 0 ? path.substr(0, sep) : '';
	}

	static function _folderName(dir:String):String
	{
		final sep1 = dir.lastIndexOf('/');
		final sep2 = dir.lastIndexOf('\\');
		final sep = Std.int(Math.max(sep1, sep2));
		return sep >= 0 ? dir.substr(sep + 1) : dir;
	}

	/**
	 * Devuelve el nombre real de la carpeta de la canción a partir del path del chart,
	 * resolviendo correctamente el caso en que el archivo esté dentro de charts/:
	 *
	 *   songs/bopeebo/bopeebo-chart.json  → "bopeebo"
	 *   songs/bopeebo/charts/bopeebo-chart.json → "bopeebo"  ← FIX: antes devolvía "charts"
	 *
	 * También devuelve el directorio raíz de la canción (parent de charts/ o del propio archivo).
	 */
	static function _songFolderFromPath(chartFilePath:String):{name:String, dir:String}
	{
		final immediateDir = _parentDir(chartFilePath);
		final immediateName = _folderName(immediateDir).toLowerCase();

		// Si el archivo vive dentro de charts/, el nombre real es el de su carpeta padre
		if (immediateName == 'charts')
		{
			final songDir = _parentDir(immediateDir);
			return { name: _folderName(songDir).toLowerCase(), dir: songDir };
		}

		return { name: immediateName, dir: immediateDir };
	}

	static function _capitalize(s:String):String
		return s.length > 0 ? s.charAt(0).toUpperCase() + s.substr(1) : s;

	// ── Helpers de conversión ─────────────────────────────────────────────────

	/**
	 * Genera variantes de nombre de dificultad para búsqueda tolerante.
	 * "Erect" → ["Erect", "erect", "ERECT"]
	 */
	static function _diffVariants(diff:String):Array<String>
	{
		final variants:Array<String> = [];
		function add(v:String)
			if (v != '' && !variants.contains(v))
				variants.push(v);
		add(diff);
		add(diff.toLowerCase());
		add(diff.toUpperCase());
		add(diff.charAt(0).toUpperCase() + diff.substr(1).toLowerCase());
		return variants;
	}

	/** Convierte milisegundos a pasos dados un BPM. */
	static inline function _msToStep(ms:Float, bpm:Float):Float
		return (ms / 1000.0) * (bpm / 60.0) * 4.0;

	// ── Extractores de campos con tipo seguro ─────────────────────────────────

	static inline function _str(v:Dynamic, def:String):String
		return (v != null) ? Std.string(v) : def;

	static inline function _float(v:Dynamic, def:Float):Float
	{
		if (v == null)
			return def;
		final f = Std.parseFloat(Std.string(v));
		return Math.isNaN(f) ? def : f;
	}

	// ── Conversión de personajes V-Slice ──────────────────────────────────────

	/**
	 * Convierte un JSON de personaje en formato V-Slice al formato Cool Engine.
	 *
	 * Formato V-Slice:
	 * {
	 *   "version": "1.0.0",
	 *   "name": "Boyfriend",
	 *   "renderType": "sparrow",          // "sparrow" | "animateatlas" | "multisparrow"
	 *   "assetPath": "shared:characters/BF_Assets",
	 *   "scale": 1.0,
	 *   "flipX": false,
	 *   "healthIcon": { "id": "bf", "isPixel": false },
	 *   "healthBar": { "leftColor": "...", "rightColor": "..." },
	 *   "animations": [
	 *     { "name": "idle", "prefix": "BF idle dance", "fps": 24, "looped": true,
	 *       "frameIndices": [], "offsets": { "x": 0, "y": 0 } }
	 *   ],
	 *   "offsets": { "x": 0, "y": 0 },
	 *   "cameraOffsets": { "x": 0, "y": 0 },
	 *   "startingAnimation": "idle",
	 *   "antialiasing": true
	 * }
	 *
	 * Formato Cool Engine resultante (compatible con CharacterData):
	 * {
	 *   "image": "characters/BF_Assets",
	 *   "scale": 1.0,
	 *   "flip_x": false,
	 *   "healthicon": "bf",
	 *   "antialiasing": true,
	 *   "animations": [
	 *     { "anim": "idle", "name": "BF idle dance", "fps": 24, "loop": true,
	 *       "indices": [], "offsets": [0, 0] }
	 *   ],
	 *   "position": [0, 0],
	 *   "camera_position": [0, 0]
	 * }
	 */
	public static function convertCharacter(rawJson:String, charName:String):Dynamic
	{
		trace('[VSliceConverter] Converting V-Slice character: $charName');
		final src:Dynamic = Json.parse(rawJson);

		// ── Asset path → imagen ───────────────────────────────────────────────
		// V-Slice usa "shared:characters/BF_Assets" o solo "characters/BF_Assets".
		// Cool Engine usa solo la parte de path relativa a images/ sin extensión.
		var rawAsset:String = _str(src.assetPath, 'characters/' + charName);
		// Quitar prefijo de biblioteca (e.g. "shared:")
		final colonIdx = rawAsset.indexOf(':');
		if (colonIdx >= 0) rawAsset = rawAsset.substr(colonIdx + 1);
		// Quitar leading slash
		if (rawAsset.startsWith('/')) rawAsset = rawAsset.substr(1);

		// ── Posición global ───────────────────────────────────────────────────
		var posX:Float = 0.0;
		var posY:Float = 0.0;
		if (src.offsets != null)
		{
			posX = _float(src.offsets.x, 0.0);
			posY = _float(src.offsets.y, 0.0);
		}

		// ── Camera offsets ────────────────────────────────────────────────────
		var camX:Float = 0.0;
		var camY:Float = 0.0;
		if (src.cameraOffsets != null)
		{
			camX = _float(src.cameraOffsets.x, 0.0);
			camY = _float(src.cameraOffsets.y, 0.0);
		}

		// ── Health icon ───────────────────────────────────────────────────────
		var iconId:String = charName;
		if (src.healthIcon != null && src.healthIcon.id != null)
			iconId = _str(src.healthIcon.id, charName);

		// ── Animaciones ───────────────────────────────────────────────────────
		final coolAnims:Array<Dynamic> = [];
		if (src.animations != null && Std.isOfType(src.animations, Array))
		{
			final vsAnims:Array<Dynamic> = cast src.animations;
			for (anim in vsAnims)
			{
				// V-Slice "name" = cool "anim" (ID interno), "prefix" = cool "name" (atlas prefix)
				final animId:String     = _str(anim.name, '');
				final atlasPrefix:String = _str(anim.prefix, animId);
				final fps:Int           = Std.int(_float(anim.fps, 24.0));
				final looped:Bool       = (anim.looped == true);

				// Frame indices: [] o vacío = sin restricción
				var indices:Array<Int> = [];
				if (anim.frameIndices != null && Std.isOfType(anim.frameIndices, Array))
				{
					final raw:Array<Dynamic> = cast anim.frameIndices;
					indices = [for (i in raw) Std.int(_float(i, 0))];
				}

				// Offsets por animación (sobreescriben el offset global en Cool)
				var offX:Float = 0.0;
				var offY:Float = 0.0;
				if (anim.offsets != null)
				{
					offX = _float(anim.offsets.x, 0.0);
					offY = _float(anim.offsets.y, 0.0);
				}

				coolAnims.push({
					anim:    animId,
					name:    atlasPrefix,
					fps:     fps,
					loop:    looped,
					indices: indices,
					offsets: [offX, offY]
				});
			}
		}

		// ── Resultado Cool Engine ─────────────────────────────────────────────
		return {
			image:           rawAsset,
			scale:           _float(src.scale, 1.0),
			flip_x:          src.flipX == true,
			healthicon:      iconId,
			antialiasing:    src.antialiasing != false, // default true
			animations:      coolAnims,
			position:        [posX, posY],
			camera_position: [camX, camY],
			// Animación inicial si se especifica
			startAnim:       src.startingAnimation != null ? _str(src.startingAnimation, 'idle') : 'idle'
		};
	}
}
