package funkin.gameplay;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import flixel.tweens.FlxEase;
import funkin.gameplay.notes.Note;
import funkin.gameplay.notes.NoteRenderer;
import funkin.gameplay.notes.NoteSplash;
import funkin.gameplay.notes.NoteHoldCover;
import funkin.gameplay.notes.StrumNote;
import funkin.gameplay.objects.StrumsGroup;
import funkin.data.Song.SwagSong;
import funkin.data.Conductor;
import funkin.gameplay.notes.NoteSkinSystem;
import funkin.gameplay.modchart.ModChartManager;
import funkin.gameplay.modchart.ModChartEvent;
import funkin.gameplay.notes.NoteTypeManager;
import funkin.data.SaveData;

using StringTools;

// NoteRawData typedef ELIMINADO — reemplazado por Struct-of-Arrays en NoteManager.
// Ver campos _raw* y helpers _packNote/_pXxx en la clase para el nuevo layout.

class NoteManager
{
	// === GROUPS ===
	public var notes:FlxTypedGroup<Note>;

	/** Grupo separado para notas sustain — se dibuja DEBAJO de notes para que
	 *  las notas normales siempre aparezcan por encima de los holds. */
	public var sustainNotes:FlxTypedGroup<Note>;

	public var splashes:FlxTypedGroup<NoteSplash>;
	public var holdCovers:FlxTypedGroup<NoteHoldCover>;

	// ── Struct-of-Arrays de notas crudas ────────────────────────────────────────
	//
	// ANTES: Array<NoteRawData> — cada NoteRawData es un objeto anónimo en el heap de Haxe.
	// En C++ cada objeto anónimo carga: puntero de clase vtable (8 B) + metadatos GC (8-16 B)
	// + campos (40 B) + padding → ~64-80 bytes por nota. Con millones de notas: gigabytes.
	//
	// AHORA: 4 arrays paralelos de primitivas puras — cero metadatos de objeto por nota:
	//   _rawStrumTime[i]  Float  8 B  — ms del strum time raw
	//   _rawPacked[i]     Int    4 B  — bits 0-1: noteData, bit2: isSustain,
	//                                   bit3: mustHit, bits 4-11: strumsGroupIndex
	//   _rawSustainLen[i] Float  8 B  — sustainLength (0 si no es head note)
	//   _rawNoteTypeId[i] Int    4 B  — ID interned de noteType (0 = "" / normal)
	//
	// Total: 24 bytes/nota vs ~72 bytes anteriores = reducción de ~67 % de RAM raw.
	// Para 1 M notas: 72 MB → 24 MB. Para 10 M notas: 720 MB → 240 MB.
	//
	// COMPACTACIÓN DESLIZANTE: cada RAW_TRIM_CHUNK spawns, el tramo ya procesado
	// se elimina de los arrays → la memoria liberada queda disponible para el GC.
	// Sin esto las entradas procesadas permanecen en RAM toda la canción.
	private static inline final RAW_TRIM_CHUNK:Int = 1024;
	private var _rawStrumTime:  Array<Float> = [];
	private var _rawPacked:     Array<Int>   = [];
	private var _rawSustainLen: Array<Float> = [];
	private var _rawNoteTypeId: Array<Int>   = [];
	private var _rawTotal:      Int = 0;  // = _rawStrumTime.length tras el sort
	private var _unspawnIdx:    Int = 0;
	/** FIX: referencia al SONG usado en generateNotes(). rewindTo() la necesita para
	 *  regenerar los arrays crudos desde cero cuando _trimRawArrays() ya compactó datos. */
	private var _song:Null<funkin.data.Song.SwagSong> = null;
	/** Tabla de intern de noteType: String → Int ID. 0 = "" / "normal". */
	private var _noteTypeIndex: Map<String, Int>  = [];
	private var _noteTypeTable: Array<String>     = [''];  // id 0 = ""
	// BUGFIX: trackeado por dirección para evitar cross-chain en holds simultáneos
	private var _prevSpawnedNote:Map<Int, Note> = new Map();

	/** Calcula la clave del mapa _prevSpawnedNote combinando dirección, grupo de strums y lado.
	 *
	 *  BUG FIX (Bug 1): la versión anterior solo usaba `noteData + strumsGroupIndex * 4`,
	 *  lo que hacía que una nota del jugador y una del CPU con la misma dirección y el
	 *  mismo grupo compartieran la misma clave. Cuando `mustHitSection` cambiaba de
	 *  sección, un sustain del CPU apuntaba al sustain del jugador como `prevNote`,
	 *  corrompiendo la cadena y rompiendo las animaciones hold/holdend.
	 *
	 *  El bit 3 del campo `_rawPacked` ya codifica mustHit, pero _prevNoteKey lo ignoraba.
	 *  Ahora se incluye como offset de 16 (4 dirs × 4 groups = 16 slots por lado):
	 *    mustHit=false → slots  0-15
	 *    mustHit=true  → slots 16-31
	 *
	 *  noteData 0-3, strumsGroupIndex 0-N, mustHit bool → clave única por grupo+lado. */
	private inline function _prevNoteKey(noteData:Int, strumsGroupIndex:Int, mustHit:Bool):Int
		return noteData + strumsGroupIndex * 4 + (mustHit ? 16 : 0);

	// ── SOA pack/unpack helpers ───────────────────────────────────────────────
	// Un solo Int por nota empaqueta 4 campos booleanos/pequeños sin alloc extra.
	private static inline function _packNote(nd:Int, sus:Bool, mh:Bool, gi:Int):Int
		return (nd & 3) | (sus ? 4 : 0) | (mh ? 8 : 0) | ((gi & 0xFF) << 4);
	private static inline function _pNoteData(p:Int):Int  return p & 3;
	private static inline function _pIsSustain(p:Int):Bool return (p & 4) != 0;
	private static inline function _pMustHit(p:Int):Bool   return (p & 8) != 0;
	private static inline function _pGroupIdx(p:Int):Int   return (p >> 4) & 0xFF;

	/** Interna una String de noteType y devuelve su ID (0 = ""). Sin alloc si ya existe. */
	private inline function _internNoteType(s:String):Int
	{
		if (s == null || s == '' || s == 'normal') return 0;
		var id = _noteTypeIndex.get(s);
		if (id == null)
		{
			id = _noteTypeTable.length;
			_noteTypeTable.push(s);
			_noteTypeIndex.set(s, id);
		}
		return id;
	}

	/**
	 * Compacta los arrays crudos eliminando las entradas ya procesadas ([0.._unspawnIdx)).
	 * Llamado automáticamente cada RAW_TRIM_CHUNK avances de _unspawnIdx.
	 * Libera la RAM de notas ya spawneadas sin tocar la ventana futura.
	 */
	private function _trimRawArrays():Void
	{
		if (_unspawnIdx <= 0) return;
		final remaining = _rawTotal - _unspawnIdx;
		if (remaining <= 0)
		{
			// Todo procesado — reset completo
			_rawStrumTime.resize(0);
			_rawPacked.resize(0);
			_rawSustainLen.resize(0);
			_rawNoteTypeId.resize(0);
			_rawTotal = 0;
			_unspawnIdx = 0;
			return;
		}
		// Copiar el bloque futuro al inicio (mover en-lugar)
		for (i in 0...remaining)
		{
			_rawStrumTime[i]  = _rawStrumTime[_unspawnIdx + i];
			_rawPacked[i]     = _rawPacked[_unspawnIdx + i];
			_rawSustainLen[i] = _rawSustainLen[_unspawnIdx + i];
			_rawNoteTypeId[i] = _rawNoteTypeId[_unspawnIdx + i];
		}
		_rawStrumTime.resize(remaining);
		_rawPacked.resize(remaining);
		_rawSustainLen.resize(remaining);
		_rawNoteTypeId.resize(remaining);
		_rawTotal    = remaining;
		_unspawnIdx  = 0;
	}

	// === STRUMS ===
	private var playerStrums:FlxTypedGroup<FlxSprite>;
	private var cpuStrums:FlxTypedGroup<FlxSprite>;
	private var playerStrumsGroup:StrumsGroup;
	private var cpuStrumsGroup:StrumsGroup;
	private var allStrumsGroups:Array<StrumsGroup>;

	// ── Exposición pública mínima para ModchartHoldMesh ──────────────────────

	/**
	 * Grupos de strums disponibles (read-only).
	 * Usado por ModchartHoldMesh para resolver el groupId por strumsGroupIndex.
	 */
	public var strumsGroups(get, never):Array<StrumsGroup>;
	inline function get_strumsGroups():Array<StrumsGroup> return allStrumsGroups;

	// OPTIMIZACIÓN: Caché de strums por dirección — evita forEach O(n) por nota por frame.
	// Antes: 20 notas × 1 forEach × 4 iteraciones = 80 iteraciones+closures/frame.
	// Ahora: lookup O(1) directo en el Map.
	private var _playerStrumCache:Map<Int, FlxSprite> = [];
	private var _cpuStrumCache:Map<Int, FlxSprite> = [];
	private var _strumGroupCache:Map<Int, Map<Int, FlxSprite>> = [];

	// === RENDERER ===
	public var renderer:NoteRenderer;

	// === CONFIG ===
	public var strumLineY:Float = 50;
	public var downscroll:Bool = false;
	public var middlescroll:Bool = false;

	private var songSpeed:Float = 1.0;

	/**
	 * Referencia al ModChartManager activo (si hay modchart cargado).
	 * PlayState la asigna en create() después de crear el ModChartManager.
	 * NoteManager la usa en updateNotePosition() para aplicar modificadores per-nota.
	 */
	public var modManager:Null<ModChartManager> = null;

	/** Píxeles de margen más allá del borde de la pantalla que se usan como
	 *  ventana de spawn y como base del cull distance. */
	private static inline final SPAWN_PAD_PX:Float  = 300.0;

	/** Ms pasados el strumTime tras los que una nota tooLate/wasGoodHit se elimina
	 *  aunque no haya salido de la zona de cull (necesario a velocidades muy bajas
	 *  donde las notas se mueven apenas unos píxeles por segundo). */
	private static inline final EXPIRE_AFTER_MS:Float = 3500.0;

	/** Ventana de spawn en ms — recalculada cada frame en update().
	 *  Determina cuántos ms por adelantado se spawean notas. */
	private var _dynSpawnTime:Float  = 1800.0;

	/** Margen de cull en px — recalculado cada frame en update().
	 *  Una nota con |note.y| > FlxG.height + _dynCullDist se oculta/elimina. */
	private var _dynCullDist:Float   = 2000.0;

	private var _scrollSpeed:Float = 0.45;

	/**
	 * Velocidad de scroll actual (read-only, incluye songSpeed × targetScrollRate).
	 * Usado por ModchartHoldMesh para evaluar posiciones del path.
	 */
	public var scrollSpeed(get, never):Float;
	inline function get_scrollSpeed():Float return _scrollSpeed;

	/** Último valor de _scrollSpeed con el que se calcularon los sustainBaseScaleY.
	 *  Si cambia (modchart o evento de velocidad), recalculamos todos los sustains activos. */
	private var _lastSustainSpeed:Float = -1.0;

	// ── Playback-rate lerp (suaviza la transición cuando el jugador cambia velocidad) ─

	/**
	 * Multiplicador de velocidad de reproducción pedido desde PlayState (teclas 4/5).
	 * NoteManager interpola _scrollSpeed hacia (0.45 × songSpeed × targetScrollRate)
	 * cada frame para hacer la transición suave.
	 * Valor inicial 1.0 = velocidad normal.
	 */
	public var targetScrollRate:Float = 1.0;

	/** true mientras _scrollSpeed está siendo interpolado hacia targetScrollRate. */
	private var _scrollTransitioning:Bool = false;

	/** _scrollSpeed al inicio de la transición activa (para calcular el from de cada nota). */
	private var _scrollSpeedAtTransStart:Float = 0.45;

	// FIX: transición suave al cambiar INVERT en modchart (análoga a _scrollTransitioning).
	// _invertTransitioning se activa cuando invert cambia de valor en cualquier grupo.
	// _invertTransTimer cuenta el tiempo restante de la animación en segundos.
	// _prevGroupInvert guarda el último valor de invert por groupId para detectar cambios.
	private var _invertTransitioning:Bool = false;
	private var _invertTransTimer:Float = 0.0;
	private static inline final INVERT_LERP_DURATION:Float = 0.18; // segundos (~0.18 s a pantalla)
	private var _prevGroupInvert:Map<String, Float> = new Map();

	// === SAVE.DATA CACHE (evita acceso Dynamic en hot loop) ===
	// Se actualizan en generateNotes() y cuando cambia la configuración.
	private var _cachedNoteSplashes:Bool = false;

	private var _cachedHoldCoverEnabled:Bool = true;

	private var _cachedMiddlescroll:Bool = false;

	private var _noteSplashesEnabled:Bool = true;

	/**
	 * Caché de SaveData.data.sustainMiss.
	 * true  → al fallar una cadena de hold se dispara UN solo miss y todas las
	 *         piezas restantes se marcan tooLate (no se pueden volver a presionar).
	 * false → comportamiento normal: un miss por pieza fallida por frame.
	 */
	private var _cachedSustainMiss:Bool = false;

	/**
	 * Por dirección (0-3): true mientras la cadena de hold de esa dirección
	 * ya fue penalizada con sustainMiss activo.
	 * Se resetea cuando el jugador golpea la siguiente head note de esa dirección.
	 */
	private var _sustainChainMissed:Array<Bool> = [false, false, false, false];

	/**
	 * sustainMiss: strumTime máximo de la cadena penalizada por dirección.
	 * -1.0 = sin cadena activa.
	 * Se usa en spawnNotes() para NO marcar como born-dead los sustains que
	 * pertenecen a una cadena DIFERENTE (futura) en la misma dirección, y en
	 * _markSustainChainMissed() para limitar el marcado solo a la cadena actual.
	 */
	private var _sustainChainMissedEndTime:Array<Float> = [-1.0, -1.0, -1.0, -1.0];

	/** Actualiza el caché de opciones del jugador. Llamar si el jugador cambia config. */
	public function refreshSaveDataCache():Void
	{
		_cachedNoteSplashes = SaveData.data.notesplashes == true;
		_cachedMiddlescroll = SaveData.data.middlescroll == true;
		_cachedSustainMiss = SaveData.data.sustainMiss == true;
		final metaHoldCover = PlayState.instance.metaData.holdCoverEnabled;
		_cachedHoldCoverEnabled = metaHoldCover != null ? metaHoldCover : funkin.data.GlobalConfig.instance.holdCoverEnabled;

		final metaNoteSplashes = PlayState.instance.metaData.splashesEnabled;
		_noteSplashesEnabled = metaNoteSplashes != null ? metaNoteSplashes : funkin.data.GlobalConfig.instance.splashesEnabled;
	}

	// === CALLBACKS ===
	public var onNoteMiss:Note->Void = null;
	public var onCPUNoteHit:Note->Void = null;
	public var onNoteHit:Note->Void = null;

	// Hold note tracking
	private var heldNotes:Map<Int, Note> = new Map();
	private var holdStartTimes:Map<Int, Float> = new Map();

	/**
	 * Tiempo exacto en que termina cada hold por dirección.
	 * Calculado al golpear el head note: headNote.strumTime + headNote.sustainLength.
	 * Comparar con songPosition cada frame para disparar playEnd() puntualmente.
	 */
	private var holdEndTimes:Map<Int, Float> = new Map();

	/** Mismo para CPU (por dirección 0-3). */
	private var cpuHoldEndTimes:Array<Float> = [-1, -1, -1, -1];

	/** strumsGroupIndex del hold cover activo del CPU por dirección. */
	private var _cpuHoldGroupIdx:Array<Int> = [0, 0, 0, 0];

	/**
	 * strumsGroupIndex del hold cover activo del JUGADOR por dirección.
	 * BUG FIX: releaseHoldNote() necesita la misma clave que startHoldCover() usó.
	 * Sin este array, stopHoldCover() recibe strumsGroupIndex=0 por defecto y la
	 * clave del Map<Int,NoteHoldCover> no coincide → el cover nunca recibe playEnd()
	 * y se queda en STATE_LOOP eternamente cuando strumsGroupIndex > 0.
	 */
	private var _playerHoldGroupIdx:Array<Int> = [0, 0, 0, 0];

	/**
	 * Estado de teclas presionadas — actualizado desde PlayState cada frame
	 * (inputHandler.held[0..3]).  Usado para distinguir si un sustain está
	 * siendo mantenido o fue soltado antes de tiempo.
	 */
	public var playerHeld:Array<Bool> = [false, false, false, false];

	/**
	 * Direcciones (0-3) cuyos sustains ya contaron un miss este ciclo.
	 * OPTIMIZADO: Bool[4] en lugar de Map<Int,Bool> — elimina allocs de Map.clear()
	 * que ocurrían 60 veces/seg. Map.clear() en Haxe/C++ resetea el hashmap interno
	 * y puede hacer pequeñas allocations. Array fijo es O(1) set y O(1) clear.
	 */
	private var _missedHoldDir:Array<Bool> = [false, false, false, false];

	/** Buffer preallocado para autoReleaseFinishedHolds — cero allocs por frame */
	private var _autoReleaseBuffer:Array<Int> = [];

	/**
	 * Tracking de qué direcciones está "manteniendo" el CPU (para hold covers).
	 * OPTIMIZADO: Bool[4] en lugar de Map<Int,Bool> — mismo razonamiento que _missedHoldDir.
	 */
	private var _cpuHeldDirs:Array<Bool> = [false, false, false, false];

	/**
	 * Set de NoteHoldCovers ya añadidos al grupo holdCovers.
	 * OPTIMIZADO: reemplaza holdCovers.members.indexOf(cover) O(n) con lookup O(1).
	 * indexOf se llamaba en cada nota de hold activa (cada frame CPU hit) — con
	 * canciones densas esto se suma rápidamente.
	 */
	private var _holdCoverSet:haxe.ds.ObjectMap<NoteHoldCover, Bool> = new haxe.ds.ObjectMap();

	/** ClipRect reutilizable para sustains en downscroll — elimina `new FlxRect()` por frame */
	private var _sustainClipRect:flixel.math.FlxRect = new flixel.math.FlxRect();

	/**
	 * Cache de strumCenterY y visualCenter indexado por (noteData + strumsGroupIndex*4 + mustPress*16).
	 * OPTIMIZACIÓN v2: reemplaza Map<Int,Float> por arrays fijos con sentinel NaN.
	 *   • Map.clear() 60×/s hacía rehash interno → pequeñas allocations cada frame.
	 *   • Array fijo: clear = 128 float assignments (~128 B de memoria contigua) = un memset.
	 *   • Lookup: array[key] vs Map.get(key) → sin hash, sin branch de colisión.
	 * Key space: noteData(0-3) + strumsGroupIndex(0-15)*4 + mustPress(0|16) ≤ 79. Array de 128 es seguro.
	 * Sentinel Math.NaN: Math.isNaN(x) es una comparación de bit exacta en C++, coste cero.
	 */
	private static inline final _FRAME_CACHE_SIZE:Int = 128;
	private var _frameCenterYCache:Array<Float>      = [for (_ in 0..._FRAME_CACHE_SIZE) Math.NaN];
	private var _frameVisualCenterCache:Array<Float> = [for (_ in 0..._FRAME_CACHE_SIZE) Math.NaN];

	/**
	 * Caché de frame: `modManager != null && modManager.enabled`.
	 * updateNotePosition() evalúa esta condición varias veces por nota (escalado,
	 * alpha, offsets X/Y, hook de posición). Con 20+ notas activas eso son 80-120
	 * dereferences de puntero + comparaciones por frame — eliminadas con un bool plano.
	 * Se recalcula UNA VEZ al inicio de updateActiveNotes() y updatePositionsForRewind().
	 */
	private var _frameModEnabled:Bool = false;

	/**
	 * Caché de frame: `allStrumsGroups != null ? allStrumsGroups.length : 0`.
	 * updateNotePosition() comprueba `allStrumsGroups != null && note.strumsGroupIndex < allStrumsGroups.length`
	 * para resolver el groupId del modchart. Con el count en un Int local se elimina
	 * el null-check y el .length por nota.
	 * Se recalcula UNA VEZ al inicio de updateActiveNotes() y updatePositionsForRewind().
	 */
	private var _frameGroupCount:Int = 0;

	public function new(notes:FlxTypedGroup<Note>, playerStrums:FlxTypedGroup<FlxSprite>, cpuStrums:FlxTypedGroup<FlxSprite>,
			splashes:FlxTypedGroup<NoteSplash>, holdCovers:FlxTypedGroup<NoteHoldCover>, ?playerStrumsGroup:StrumsGroup, ?cpuStrumsGroup:StrumsGroup,
			?allStrumsGroups:Array<StrumsGroup>, ?sustainNotes:FlxTypedGroup<Note>)
	{
		this.notes = notes;
		this.sustainNotes = sustainNotes != null ? sustainNotes : notes; // fallback: usar mismo grupo si no se pasa
		this.playerStrums = playerStrums;
		this.cpuStrums = cpuStrums;
		this.splashes = splashes;
		this.holdCovers = holdCovers;
		this.playerStrumsGroup = playerStrumsGroup;
		this.cpuStrumsGroup = cpuStrumsGroup;
		this.allStrumsGroups = allStrumsGroups;
		renderer = new NoteRenderer(notes, playerStrums, cpuStrums);

		_rebuildStrumCache();
	}

	/**
	 * Reconstruye el caché de strums por dirección.
	 * Llamar después de cualquier cambio en los grupos de strums.
	 */
	public function _rebuildStrumCache():Void
	{
		_playerStrumCache.clear();
		_cpuStrumCache.clear();
		_strumGroupCache.clear();

		if (playerStrums != null)
			playerStrums.forEach(function(s:FlxSprite)
			{
				_playerStrumCache.set(s.ID, s);
			});
		if (cpuStrums != null)
			cpuStrums.forEach(function(s:FlxSprite)
			{
				_cpuStrumCache.set(s.ID, s);
			});

		if (allStrumsGroups != null)
		{
			for (i in 0...allStrumsGroups.length)
			{
				var grp = allStrumsGroups[i];
				if (grp == null)
					continue;
				var map:Map<Int, FlxSprite> = [];
				// StrumsGroup tiene getStrum(dir) — iteramos las 4 direcciones estándar
				for (dir in 0...4)
				{
					var s = grp.getStrum(dir);
					if (s != null)
						map.set(dir, s);
				}
				_strumGroupCache.set(i, map);
			}
		}
	}

	/**
	 * Genera SOLO datos crudos desde SONG data — cero FlxSprites instanciados.
	 *
	 * MEMORIA: usa Struct-of-Arrays en lugar de Array<NoteRawData>.
	 * Cada nota ocupa 24 bytes (4 arrays × Float/Int) vs ~72 bytes (objeto anónimo heap).
	 * Reducción de ~67% en RAM de datos crudos antes de cualquier spawn.
	 */
	public function generateNotes(SONG:SwagSong):Void
	{
		_song = SONG; // FIX: cache for rewindTo() regeneration
		_unspawnIdx = 0;
		_prevSpawnedNote.clear();
		songSpeed = SONG.speed;
		_scrollSpeed = 0.45 * FlxMath.roundDecimal(songSpeed, 2);
		_lastSustainSpeed = _scrollSpeed;

		// Reset intern table (nueva canción puede tener tipos distintos)
		_noteTypeIndex.clear();
		_noteTypeTable.resize(1); // id 0 siempre = ""
		_noteTypeTable[0] = '';

		// Cachear opciones del jugador ahora — se usan en el hot loop de notas
		refreshSaveDataCache();

		// ── Pre-calcular capacidad total para evitar resizes ──────────────────
		var noteCount:Int = 0;
		for (section in SONG.notes)
			for (songNotes in section.sectionNotes)
			{
				noteCount++;
				var susLength:Float = songNotes[2];
				if (susLength > 0)
					noteCount += Math.floor(susLength / Conductor.stepCrochet);
			}

		// Pre-reservar los 4 arrays paralelos de una sola vez
		_rawStrumTime  = [for (_ in 0...noteCount) 0.0];
		_rawPacked     = [for (_ in 0...noteCount) 0];
		_rawSustainLen = [for (_ in 0...noteCount) 0.0];
		_rawNoteTypeId = [for (_ in 0...noteCount) 0];
		var _wi:Int = 0; // write index

		for (section in SONG.notes)
		{
			for (songNotes in section.sectionNotes)
			{
				var daStrumTime:Float = songNotes[0];
				var rawNoteData:Int = Std.int(songNotes[1]);
				var daNoteData:Int = rawNoteData % 4;
				var groupIdx:Int = Math.floor(rawNoteData / 4);

				var gottaHitNote:Bool;
				if (allStrumsGroups != null && groupIdx < allStrumsGroups.length && groupIdx >= 2)
					gottaHitNote = !allStrumsGroups[groupIdx].isCPU;
				else
				{
					gottaHitNote = section.mustHitSection;
					if (groupIdx == 1)
						gottaHitNote = !section.mustHitSection;
				}

				var noteTypeRaw:String = (songNotes.length > 3 && songNotes[3] != null) ? Std.string(songNotes[3]) : '';
				var susLength:Float = songNotes[2];
				final ntId:Int = _internNoteType(noteTypeRaw);
				final packed:Int = _packNote(daNoteData, false, gottaHitNote, groupIdx);

				_rawStrumTime[_wi]  = daStrumTime;
				_rawPacked[_wi]     = packed;
				_rawSustainLen[_wi] = susLength;
				_rawNoteTypeId[_wi] = ntId;
				_wi++;

				if (susLength > 0)
				{
					var floorSus:Int = Math.floor(susLength / Conductor.stepCrochet);
					final packedSus:Int = _packNote(daNoteData, true, gottaHitNote, groupIdx);
					for (susNote in 0...floorSus)
					{
						_rawStrumTime[_wi]  = daStrumTime + (Conductor.stepCrochet * susNote) + Conductor.stepCrochet * 0.5;
						_rawPacked[_wi]     = packedSus;
						_rawSustainLen[_wi] = 0.0;
						_rawNoteTypeId[_wi] = ntId;
						_wi++;
					}
				}
			}
		}

		var _idx:Array<Int> = [for (i in 0..._wi) i];
		_idx.sort((a, b) -> {
			var d = _rawStrumTime[a] - _rawStrumTime[b];
			d < 0 ? -1 : d > 0 ? 1 : 0;
		});

		var _st2:Array<Float> = []; _st2.resize(_wi);
		var _pk2:Array<Int>   = []; _pk2.resize(_wi);
		var _sl2:Array<Float> = []; _sl2.resize(_wi);
		var _nt2:Array<Int>   = []; _nt2.resize(_wi);

		for (i in 0..._wi)
		{
			final si = _idx[i];
			_st2[i] = _rawStrumTime[si];
			_pk2[i] = _rawPacked[si];
			_sl2[i] = _rawSustainLen[si];
			_nt2[i] = _rawNoteTypeId[si];
		}
		_rawStrumTime  = _st2;
		_rawPacked     = _pk2;
		_rawSustainLen = _sl2;
		_rawNoteTypeId = _nt2;
		_rawTotal      = _wi;

		trace('[NoteManager] $_rawTotal notas en cola (SOA, ${_noteTypeTable.length} tipos internados)');
	}

	public function update(songPosition:Float):Void
	{
		final targetSpeed:Float = 0.45 * FlxMath.roundDecimal(songSpeed * targetScrollRate, 2);
		final speedDiff:Float = targetSpeed - _scrollSpeed;

		if (Math.abs(speedDiff) > 0.0005)
		{
			// Usar elapsed real (sin escala de timeScale) para que el lerp siempre
			// tarde ~0.15 s en tiempo de pantalla independientemente del rate.
			final rawElapsed:Float = FlxG.elapsed / (FlxG.timeScale > 0 ? FlxG.timeScale : 1.0);
			final alpha:Float = Math.min(1.0, rawElapsed * 12.0); // ~0.08 s a 60 fps
			_scrollSpeed = _scrollSpeed + speedDiff * alpha;

			if (!_scrollTransitioning)
			{
				// Primera vez que entramos en transición: guardar el Y y scale.y
				// actuales de TODAS las notas vivas como punto de partida del lerp.
				_scrollTransitioning = true;
				_scrollSpeedAtTransStart = _scrollSpeed;

				for (note in sustainNotes.members)
				{
					if (note == null || !note.alive)
						continue;
					note._lerpFromY = note.y;
					note._lerpFromScaleY = note.scale.y;
					note._lerpT = 0.0;
				}
				for (note in notes.members)
				{
					if (note == null || !note.alive)
						continue;
					note._lerpFromY = note.y;
					note._lerpFromScaleY = note.scale.y;
					note._lerpT = 0.0;
				}
			}
		}
		else
		{
			_scrollSpeed = targetSpeed;
			_scrollTransitioning = false;
		}

		final _safeSpeed:Float = Math.max(_scrollSpeed, 0.005);
		_dynSpawnTime = Math.max(600.0, (FlxG.height + SPAWN_PAD_PX) / _safeSpeed);

		// FIX: avanzar el timer de transición por INVERT y apagarlo cuando expire.
		if (_invertTransTimer > 0.0)
		{
			final rawElapsedInv:Float = FlxG.elapsed / (FlxG.timeScale > 0 ? FlxG.timeScale : 1.0);
			_invertTransTimer -= rawElapsedInv;
			if (_invertTransTimer <= 0.0)
			{
				_invertTransTimer = 0.0;
				_invertTransitioning = false;
			}
		}

		// _dynCullDist: margen en px más allá del borde de pantalla antes de ocultar/eliminar.
		//   Base: pantalla + SPAWN_PAD_PX → garantiza que notas recién spawneadas no se cull inmediatamente.
		//   Extra modchart: cuando hay mods activos, drunkY/wave/bumpy pueden desplazar notas
		//   ±pantalla fuera del área visible. Añadimos FlxG.height extra de margen.
		//   INVERT FIX: con MOVE_Y grande (ej. 500 px) los strums se desplazan lejos de strumLineY.
		//   Las notas se posicionan relativas al strum real, así que el margen de cull debe incluir
		//   la desviación máxima de cualquier strum respecto a strumLineY.
		final _modCullExtra:Float = (modManager != null && modManager.enabled) ? FlxG.height : 0.0;
		var _maxStrumYDev:Float = 0.0;
		if (modManager != null && modManager.enabled && allStrumsGroups != null)
		{
			for (_cg in allStrumsGroups)
			{
				for (_ci2 in 0...4)
				{
					final _cs = _cg.getStrum(_ci2);
					if (_cs != null)
					{
						final _dev = Math.abs(_cs.y - strumLineY);
						if (_dev > _maxStrumYDev) _maxStrumYDev = _dev;
					}
				}
			}
		}
		_dynCullDist = FlxG.height + SPAWN_PAD_PX + _modCullExtra + _maxStrumYDev;

		spawnNotes(songPosition);
		updateActiveNotes(songPosition);
		updateStrumAnimations();
		autoReleaseFinishedHolds();

		// ── Hold splash live tracking ────────────────────────────────────────
		// Re-center every active NoteHoldCover on the strum's CURRENT position.
		// This is the fix for covers drifting away during modchart movements.
		if (renderer != null)
			_updateHoldCoverPositions();

		if (renderer != null)
		{
			renderer.updateBatcher();
			renderer.updateHoldCovers();
		}
	}

	private function autoReleaseFinishedHolds():Void
	{
		final songPos = Conductor.songPosition;

		// ── Jugador ──────────────────────────────────────────────────────────
		if (heldNotes.keys().hasNext())
		{
			_autoReleaseBuffer.resize(0);
			for (dir in heldNotes.keys())
			{
				// Usar holdEndTime si está disponible; fallback a _hasPendingSustain
				var shouldRelease:Bool;
				if (holdEndTimes.exists(dir))
					shouldRelease = songPos >= holdEndTimes.get(dir);
				else
					shouldRelease = !_hasPendingSustain(dir, true, sustainNotes.members, sustainNotes.members.length);
				if (shouldRelease)
					_autoReleaseBuffer.push(dir);
			}
			for (dir in _autoReleaseBuffer)
				releaseHoldNote(dir);
		}

		// ── CPU ──────────────────────────────────────────────────────────────
		var _anyCpuHeld = false;
		for (d in 0...4)
			if (_cpuHeldDirs[d])
			{
				_anyCpuHeld = true;
				break;
			}
		if (_anyCpuHeld)
		{
			_autoReleaseBuffer.resize(0);
			for (dir in 0...4)
			{
				if (!_cpuHeldDirs[dir])
					continue;
				var shouldRelease:Bool;
				if (cpuHoldEndTimes[dir] >= 0)
					shouldRelease = songPos >= cpuHoldEndTimes[dir];
				else
					shouldRelease = !_hasPendingSustain(dir, false, sustainNotes.members, sustainNotes.members.length);
				if (shouldRelease)
					_autoReleaseBuffer.push(dir);
			}
			for (dir in _autoReleaseBuffer)
			{
				if (renderer != null)
					renderer.stopHoldCover(dir, false, _cpuHoldGroupIdx[dir]);
				_cpuHeldDirs[dir] = false;
				cpuHoldEndTimes[dir] = -1;
				_cpuHoldGroupIdx[dir] = 0;
			}
		}
	}

	/**
	 * Devuelve true si quedan piezas de sustain AÚN NO COMPLETADAS para esta dirección.
	 *
	 * FIX: antes comprobaba `n.alive` y esperaba a que los sustains se salieran de pantalla.
	 * Ahora comprueba `!n.wasGoodHit && !n.tooLate` — la hold termina en cuanto la última
	 * pieza de sustain cruza la ventana de hit (wasGoodHit=true), no cuando sale de pantalla.
	 * Esto dispara la animación de fin del hold cover en el momento correcto.
	 *
	 * OPTIMIZACIÓN — salida anticipada en el scan de datos futuros:
	 * Los arrays SOA están ordenados por strumTime. Dentro de un hold, todas las piezas
	 * de sustain para una dirección son consecutivas en el tiempo. Si durante el scan
	 * encontramos una HEAD NOTE (isSustain=false) para la misma dirección y lado, significa
	 * que ya pasamos todas las piezas del hold actual — el siguiente hold empieza después.
	 * Condición: las piezas no spawneadas del hold actual tienen strumTime ANTERIOR al de
	 * la siguiente head note, así que siempre se encuentran primero en el scan.
	 * → break seguro: el hold activo no tiene piezas pendientes en el array crudo.
	 */
	private function _hasPendingSustain(dir:Int, isPlayer:Bool, members:Array<Note>, len:Int):Bool
	{
		// 1. Notas spawneadas: pendientes = vivas, aún no golpeadas y no perdidas
		for (i in 0...len)
		{
			final n = members[i];
			if (n != null && n.alive && n.isSustainNote && n.noteData == dir && n.mustPress == isPlayer && !n.wasGoodHit && !n.tooLate)
				return true;
		}
		// 2. Notas futuras aún no spawneadas — CRÍTICO para holds largos.
		//    Salida anticipada: al topar con una head note de la misma dirección/lado
		//    sabemos que el hold actual ya terminó y que el siguiente aún no empieza.
		for (i in _unspawnIdx..._rawTotal)
		{
			final pk = _rawPacked[i];
			if (_pNoteData(pk) == dir && _pMustHit(pk) == isPlayer)
			{
				if (_pIsSustain(pk)) return true;
				// Head note encontrada para este dir — las piezas del hold activo
				// habrían aparecido antes (tiempo menor) en el array ordenado.
				// No hay más piezas pendientes del hold actual: salida anticipada.
				break;
			}
		}
		return false;
	}

	private function spawnNotes(songPosition:Float):Void
	{
		// _dynSpawnTime calculado en update() — leer directamente.
		while (_unspawnIdx < _rawTotal && _rawStrumTime[_unspawnIdx] - songPosition < _dynSpawnTime)
		{
			final i = _unspawnIdx++;
			final rawST:Float  = _rawStrumTime[i];
			final rawPK:Int    = _rawPacked[i];
			final rawSL:Float  = _rawSustainLen[i];
			final rawND:Int    = _pNoteData(rawPK);
			final rawIS:Bool   = _pIsSustain(rawPK);
			final rawMH:Bool   = _pMustHit(rawPK);
			final rawGI:Int    = _pGroupIdx(rawPK);
			final rawNT:String = _noteTypeTable[_rawNoteTypeId[i]];

			var _groupSkin:String = null;
			if (allStrumsGroups != null && rawGI < allStrumsGroups.length)
				_groupSkin = allStrumsGroups[rawGI].data.noteSkin;

			// BUG 1 FIX: pass rawMH so player/CPU notes on the same dir/group don't share a chain.
			final _pnKey = _prevNoteKey(rawND, rawGI, rawMH);
			// POOL FIX: pass rawGI so notes pool per-group (same skin name can differ in texture).
			final note = renderer.getNote(rawST, rawND, _prevSpawnedNote.get(_pnKey), rawIS, rawMH, _groupSkin, rawGI);
			note.strumsGroupIndex = rawGI;
			note.noteType         = rawNT;
			note.sustainLength    = rawSL;
			note.visible = true;
			note.active  = true;
			note.alpha   = rawIS ? 0.6 : 1.0;

			// sustainMiss: born-dead SOLO si es un sustain de la cadena actualmente penalizada.
			if (_cachedSustainMiss && rawIS && rawMH && _sustainChainMissed[rawND]
				&& (_sustainChainMissedEndTime[rawND] < 0
					|| rawST <= _sustainChainMissedEndTime[rawND] + Conductor.stepCrochet))
			{
				note.tooLate = true;
				note.alpha = 0.3;
			}

			_prevSpawnedNote.set(_pnKey, note);

			// ── Look-ahead: ¿es esta pieza de sustain body o tail? ───────────
			// Escanear hacia adelante en los SOA (sin crear objetos).
			if (rawIS)
			{
				final _stepTol:Float = Conductor.stepCrochet * 1.5;
				var _isBodyPiece = false;
				var _scanIdx = _unspawnIdx;
				while (_scanIdx < _rawTotal)
				{
					final _scanST = _rawStrumTime[_scanIdx];
					if (_scanST - rawST > _stepTol)
						break;
					final _scanPK = _rawPacked[_scanIdx];
					if (_pIsSustain(_scanPK) && _pNoteData(_scanPK) == rawND && _pGroupIdx(_scanPK) == rawGI)
					{
						_isBodyPiece = true;
						break;
					}
					_scanIdx++;
				}
				if (_isBodyPiece)
					note.confirmHoldPiece();
			}

			if (rawIS)
				sustainNotes.add(note);
			else
				notes.add(note);
		}

		// ── Compactación deslizante ───────────────────────────────────────────
		// Cada RAW_TRIM_CHUNK notas spawneadas, eliminar las entradas ya procesadas
		// del inicio de los arrays para liberar su RAM al GC.
		if (_unspawnIdx > 0 && (_unspawnIdx % RAW_TRIM_CHUNK) == 0)
			_trimRawArrays();
	}

	private function updateActiveNotes(songPosition:Float):Void
	{
		final hitWindow:Float = Conductor.safeZoneOffset;

		// V-Slice: si el scroll speed cambió (evento de velocidad o modchart),
		// recalcular sustainBaseScaleY de todos los sustains activos para que
		// no queden gaps ni solapamientos a velocidades muy altas/bajas.
		if (_scrollSpeed != _lastSustainSpeed)
		{
			_lastSustainSpeed = _scrollSpeed;
			_recalcAllSustainScales();
		}

		// Cachés de frame: recalcular UNA vez antes de iterar las notas.
		// updateNotePosition() los consulta varias veces por nota — sin alloc, sin null-check repetido.
		_frameModEnabled = modManager != null && modManager.enabled;
		_frameGroupCount = (allStrumsGroups != null) ? allStrumsGroups.length : 0;

		// Limpiar caches de posición de strums — se rellenan lazily nota a nota este frame.
		// OPTIMIZACIÓN: array fill con NaN vs Map.clear() → sin rehash, sin alloc.
		for (_ci in 0..._FRAME_CACHE_SIZE)
		{
			_frameCenterYCache[_ci]      = Math.NaN;
			_frameVisualCenterCache[_ci] = Math.NaN;
		}

		_missedHoldDir[0] = false;
		_missedHoldDir[1] = false;
		_missedHoldDir[2] = false;
		_missedHoldDir[3] = false;

		// FIX: detectar cambio de INVERT por grupo y guardar posición actual de las notas
		// afectadas como punto de partida del lerp, igual que hace _scrollTransitioning.
		if (_frameModEnabled && allStrumsGroups != null)
		{
			for (group in allStrumsGroups)
			{
				final st0 = modManager.getState(group.id, 0);
				final curInv:Float = (st0 != null) ? st0.invert : 0.0;
				final prevInv:Float = _prevGroupInvert.exists(group.id) ? _prevGroupInvert.get(group.id) : 0.0;

				if ((curInv > 0.5) != (prevInv > 0.5))
				{
					// El estado de invert cambió para este grupo → iniciar transición
					_invertTransitioning = true;
					_invertTransTimer = INVERT_LERP_DURATION;
					final gid:String = group.id;

					for (note in sustainNotes.members)
					{
						if (note == null || !note.alive) continue;
						// Misma lógica que updateNotePosition: grupos 0/1 usan mustPress,
						// grupos >= 2 usan strumsGroupIndex directo.
						final nGid:String = (note.strumsGroupIndex >= 2 && note.strumsGroupIndex < _frameGroupCount)
							? allStrumsGroups[note.strumsGroupIndex].id
							: (note.mustPress ? "player" : "cpu");
						if (nGid != gid) continue;
						note._lerpFromY      = note.y;
						note._lerpFromScaleY = note.scale.y;
						note._lerpT          = 0.0;
					}
					if (sustainNotes != notes)
					{
						for (note in notes.members)
						{
							if (note == null || !note.alive) continue;
							final nGid:String = (note.strumsGroupIndex >= 2 && note.strumsGroupIndex < _frameGroupCount)
								? allStrumsGroups[note.strumsGroupIndex].id
								: (note.mustPress ? "player" : "cpu");
							if (nGid != gid) continue;
							note._lerpFromY      = note.y;
							note._lerpFromScaleY = note.scale.y;
							note._lerpT          = 0.0;
						}
					}
				}
				_prevGroupInvert.set(group.id, curInv);
			}
		}

		// Iterar ambos grupos: primero sustains, luego notas normales
		_updateNoteGroup(sustainNotes.members, sustainNotes.members.length, songPosition, hitWindow);
		// Evitar doble-iteración si sustainNotes apunta al mismo objeto que notes (fallback)
		if (sustainNotes != notes)
			_updateNoteGroup(notes.members, notes.members.length, songPosition, hitWindow);
	}

	private inline function _updateNoteGroup(members:Array<Note>, len:Int, songPosition:Float, hitWindow:Float):Void
	{
		var i:Int = len;
		while (i > 0)
		{
			i--;
			final note = members[i];
			if (note == null || !note.alive)
				continue;

			updateNotePosition(note, songPosition);

			// ── canBeHit — calculado aquí con el songPosition correcto ─────
			// FIX: antes se calculaba en Note.update() con el songPosition del
			// frame ANTERIOR (el Conductor se actualiza después de super.update).
			// Eso desplazaba la ventana de hit ~1 frame hacia atrás, haciendo
			// que el área de "sick" apareciera visualmente mucho antes de donde
			// la nota llega al strum. Ahora se usa el songPosition actual.
			if (note.mustPress)
			{
				final _hw:Float = note.isSustainNote ? hitWindow * 1.05 : hitWindow;
				note.canBeHit = (note.strumTime > songPosition - _hw && note.strumTime < songPosition + _hw);
			}

			// ── CPU notes ──────────────────────────────────────────────────
			if (!note.mustPress && note.strumTime <= songPosition)
			{
				if (!(note.isSustainNote && note.wasGoodHit))
				{
					handleCPUNote(note);
					if (!note.isSustainNote)
						continue;
				}
			}

			// ── Notas del jugador ──────────────────────────────────────────
			if (note.mustPress && !note.wasGoodHit)
			{
				if (note.isSustainNote)
				{
					// Sustain ya fallida — no se puede volver a presionar; solo sigue de largo
					if (note.tooLate)
					{
						continue;
					}

					if (songPosition > note.strumTime + hitWindow)
					{
						var dir = note.noteData;
						if (playerHeld[dir])
						{
							note.wasGoodHit = true;
							handleSustainNoteHit(note);
						}
						else
						{
							note.tooLate = true;
							note.alpha = _cachedSustainMiss ? 0.3 : 0.2;

							if (heldNotes.exists(dir))
								releaseHoldNote(dir);

							if (_cachedSustainMiss)
							{
								// ── sustainMiss activo: UN solo miss por toda la cadena ──────
								if (!_sustainChainMissed[dir])
								{
									_sustainChainMissed[dir] = true;
									// Marcar en un pase todas las piezas vivas de esta dirección
									_markSustainChainMissed(dir);
									if (onNoteMiss != null)
										onNoteMiss(note);
								}
							}
							else
							{
								// ── Comportamiento normal: un miss por pieza fallida por frame ─
								if (!_missedHoldDir[dir])
								{
									_missedHoldDir[dir] = true;
									if (onNoteMiss != null)
										onNoteMiss(note);
								}
							}
							// No llamar removeNote — la pieza sigue de largo con alpha reducido
							// hasta que el culling la elimine al salir de pantalla.
						}
					}
					// Si strumTime todavía no pasó, no hacer nada — processSustains() lo maneja
					continue;
				}

				// ── NOTAS NORMALES: miss si pasan la ventana ───────────────
				if (note.tooLate || songPosition > note.strumTime + hitWindow)
				{
					// Solo disparar el miss la primera vez; después sigue de largo
					// con alpha reducido hasta que el culling la elimine al salir de pantalla.
					if (!note.tooLate)
						missNote(note);
					continue;
				}
			}

			// ── Visibilidad y culling ──────────────────────────────────────
			// _dynCullDist ya tiene en cuenta si hay modchart activo (margen extra).
			final _isOffscreen:Bool  = note.y < -_dynCullDist || note.y > FlxG.height + _dynCullDist;
			final _isDone:Bool       = (note.isSustainNote && note.wasGoodHit) || note.tooLate;
			final _timeExpired:Bool  = (Conductor.songPosition - note.strumTime) > EXPIRE_AFTER_MS;

			// FIX (modchart sustain disappearing):
			// Mods como drunk/wave/tipsy pueden mover sustains temporalmente fuera del
			// rango _dynCullDist. Usar _isOffscreen como condicion de eliminacion para
			// sustains con wasGoodHit=true causaba eliminacion prematura y desaparicion
			// permanente al volver al rango (visible=false nunca se restauraba).
			// FIX: para sustains wasGoodHit con modchart activo, solo eliminar por TIEMPO.
			// tooLate sigue usando posicion (esas notas estan visualmente terminadas).
			final _isModWasGoodHit:Bool = _frameModEnabled && note.isSustainNote && note.wasGoodHit;

			if (_isDone && ((!_isModWasGoodHit && _isOffscreen) || _timeExpired))
			{
				removeNote(note);
				continue; // nota muerta -- saltar actualizacion de visibilidad
			}

			// FIX: NO ocultar sustains wasGoodHit con modchart por posicion. El clipRect
			// de updateNotePosition() gestiona su visibilidad real (clipH=0 => sin pixels
			// renderizados aunque visible=true). Sin este fix, el sustain quedaba
			// visible=false al salir del rango y nunca se restauraba al volver.
			if (_isOffscreen && !_isModWasGoodHit)
				note.visible = false;
			else if (!_isOffscreen)
			{
				// Restaurar visibilidad para todos los casos en rango visual.
				// wasGoodHit sustains: clipRect limita pixeles renderizados => visible=true es seguro.
				note.visible = true;
				if (!note.mustPress && middlescroll)
					note.alpha = 0;
			}
		}
	}

	private function handleCPUNote(note:Note):Void
	{
		note.wasGoodHit = true;
		if (onCPUNoteHit != null)
			onCPUNoteHit(note);
		// Solo animar el strum en la nota cabeza, NO en las piezas de sustain.
		handleStrumAnimation(note.noteData, note.strumsGroupIndex, false);

		if (!note.isSustainNote && note.sustainLength > 0)
		{
			var newEnd = note.strumTime + note.sustainLength - SaveData.data.offset;
			if (cpuHoldEndTimes[note.noteData] < 0)
				cpuHoldEndTimes[note.noteData] = newEnd;
			else
				cpuHoldEndTimes[note.noteData] = Math.max(cpuHoldEndTimes[note.noteData], newEnd);
		}
		/*
			if (!note.isSustainNote && !_cachedMiddlescroll && _cachedNoteSplashes && renderer != null)
				createNormalSplash(note, false); */
		// Hold covers para CPU: solo en la primera pieza de sustain
		if (note.isSustainNote && !_cachedMiddlescroll && _cachedNoteSplashes && renderer != null)
		{
			var dir = note.noteData;
			if (!_cpuHeldDirs[dir])
			{
				_cpuHeldDirs[dir] = true;
				_cpuHoldGroupIdx[dir] = note.strumsGroupIndex;
				var strum = getStrumForDirection(dir, note.strumsGroupIndex, false);
				if (strum != null)
				{
					var holdSplashCPU = NoteTypeManager.getHoldSplashName(note.noteType);
					if (_cachedHoldCoverEnabled)
					{
						// FIX: strum.width/height incluyen scale; frameWidth/Height son px sin escalar.
						// Usar dims escaladas para coincidir con _updateHoldCoverPositions().
						// FIX (v-slice parity): centro gráfico = frameWidth/Height * scale, no hitbox width/height.
					var cover = renderer.startHoldCover(dir, strum.x - strum.offset.x + strum.frameWidth * strum.scale.x * 0.5, strum.y - strum.offset.y + strum.frameHeight * strum.scale.y * 0.5,
							false, note.strumsGroupIndex, holdSplashCPU);
						if (cover != null && !_holdCoverSet.exists(cover) && holdCovers.members.indexOf(cover) < 0)
						{
							_holdCoverSet.set(cover, true);
							holdCovers.add(cover);
						}
					}
				}
			}
		}
		if (!note.isSustainNote)
			removeNote(note);
	}

	private function updateStrumAnimations():Void
	{
		_resetStrumsGroup(cpuStrums);
		_resetStrumsGroup(playerStrums);
	}

	private static inline function _resetStrumsGroup(group:FlxTypedGroup<FlxSprite>):Void
	{
		if (group == null)
			return;
		final members = group.members;
		final len = members.length;
		for (i in 0...len)
		{
			final strum = members[i];
			if (strum == null || !strum.alive)
				continue;
			final strumNote = cast(strum, funkin.gameplay.notes.StrumNote);
			if (strumNote == null)
				continue;
			final anim = strumNote.animation.curAnim;
			// OPT: comparar primer char 'c' antes de llamar startsWith (evita scan completo)
			// En la mayoria de frames el anim es 'static', que falla en el primer char.
			if (anim != null
				&& anim.finished
				&& anim.name.length >= 7
				&& anim.name.charCodeAt(0) == 99 // 'c' de 'confirm'
				&& anim.name.startsWith('confirm'))
				strumNote.playAnim('static');
		}
	}

	/**
	 * V-Slice style: recalcula sustainBaseScaleY de todos los sustains activos
	 * cuando el scroll speed cambia en mitad de una canción (eventos de velocidad,
	 * modcharts, etc.). Sin esto, al cambiar la velocidad quedan gaps o solapamientos
	 * permanentes en los holds que ya estaban spawneados con el speed anterior.
	 */
	private function _recalcAllSustainScales():Void
	{
		final conductor = funkin.data.Conductor;
		if (conductor.stepCrochet <= 0)
			return;

		// Calcular el scale.y correcto para el speed efectivo actual.
		// FIX: antes usaba songSpeed (base fija) en lugar de _scrollSpeed
		// (_scrollSpeed = 0.45 * songSpeed * targetScrollRate), así que el tail cap
		// nunca se adaptaba cuando el jugador cambiaba el scroll rate o un evento
		// de chart alteraba la velocidad. Ahora usamos _scrollSpeed directamente:
		//   targetH = stepCrochet * _scrollSpeed  ≡  stepCrochet * 0.45 * effectiveSpeed
		inline function calcScaleY(note:funkin.gameplay.notes.Note):Float
		{
			if (note.frameHeight <= 0)
				return note.sustainBaseScaleY; // sin datos de frame
			final _stretch:Float = note._skinHoldStretch;
			// Derivar el multiplicador de velocidad efectivo para el _extra de alta velocidad.
			final _effectiveSpeed:Float = _scrollSpeed / 0.45;
			final _extra:Float = (_effectiveSpeed > 3.0) ? ((_effectiveSpeed - 3.0) * 0.02) : 0.0;
			// _scrollSpeed ya incluye 0.45, así que: stepCrochet * _scrollSpeed = stepCrochet * 0.45 * effectiveSpeed
			final targetH:Float = conductor.stepCrochet * _scrollSpeed;
			return (targetH * (_stretch + _extra)) / note.frameHeight;
		}

		// Iterar sobre todos los sustains activos (body Y tail caps).
		//
		// FIX tail cap: antes se excluía isTailCap con un `continue`, dejando el
		// extremo del hold con el scale calculado al spawnear la nota (velocidad
		// inicial). Cuando un evento de chart o el jugador cambiaban el scroll rate,
		// los body-pieces se ajustaban pero el tail cap se quedaba con el scale
		// antiguo → el extremo final sobresalía o quedaba corto respecto al body.
		//
		// IMPORTANTE: tail caps tienen frameHeight distinto a los body-pieces, pero
		// calcScaleY() ya usa note.frameHeight individualmente, así que produce el
		// scale correcto para cada pieza independientemente de su tipo.
		// updateNotePosition() respeta note.sustainBaseScaleY para tail caps (no les
		// aplica la escala Euclídea), así que actualizar sustainBaseScaleY aquí es
		// la única vía para que el tail cap refleje el cambio de velocidad.
		for (note in sustainNotes.members)
		{
			if (note == null || !note.alive || !note.isSustainNote)
				continue;
			var newSY = calcScaleY(note);
			if (newSY > 0 && newSY != note.sustainBaseScaleY)
			{
				if (_scrollTransitioning)
				{
					if (note._lerpFromScaleY < 0.0) // aún no tiene from: usar el actual
						note._lerpFromScaleY = note.scale.y;
					// No tocamos note.scale.y — el lerp de updateNotePosition lo actualiza gradualmente
				}
				else
				{
					// Cambio instantáneo (evento de chart, modchart): saltar directo
					note.scale.y = newSY;
					note.updateHitbox();
					note.offset.x += note.noteOffsetX;
					note.offset.y += note.noteOffsetY;
				}
				note.sustainBaseScaleY = newSY; // siempre actualizar el target
			}
		}
	}

	private function handleStrumAnimation(noteData:Int, groupIndex:Int, isPlayer:Bool):Void
	{
		var strum = getStrumForDirection(noteData, groupIndex, isPlayer);
		if (strum != null)
		{
			var strumNote = cast(strum, funkin.gameplay.notes.StrumNote);
			if (strumNote != null)
				strumNote.playAnim('confirm', true);
		}
	}

	private function updateNotePosition(note:Note, songPosition:Float):Void
	{
		// ── Middlescroll: notas CPU completamente invisibles — no calcular nada ─
		// Hacerlo aquí (antes de cualquier cálculo) evita el flash de 1 frame
		// que ocurría cuando updateNotePosition asignaba alpha=0.05 (floor del
		// FlxMath.bound) y el override a 0 llegaba un tick después.
		if (_cachedMiddlescroll && !note.mustPress)
		{
			note.visible = false;
			note.clipRect = null;
			return;
		}

		var strum = getStrumForDirection(note.noteData, note.strumsGroupIndex, note.mustPress);

		// BUG FIX: centro visual del strum — siempre descuenta strum.offset.y para que
		// sea consistente entre skins. Sin esto, skins con sprites más grandes/offset
		// distinto desplazan _refY y visualCenter, desalineando notas y clipRect.
		//
		// OPTIMIZACIÓN: clave = noteData + strumsGroupIndex*4 + mustPress*16 → 32 slots máx.
		// strumCenterY y visualCenter se calculan una vez por strum por frame y se reutilizan
		// para todas las notas que apuntan al mismo strum. El Map se vacía en updateActiveNotes().
		final _strumCacheKey:Int = note.noteData + note.strumsGroupIndex * 4 + (note.mustPress ? 0 : 16);

		var strumCenterY:Float;
		{
			final _cached = _frameCenterYCache[_strumCacheKey];
			if (Math.isNaN(_cached))
			{
				// Usar logicalY en lugar de strum.y cuando hay modchart activo:
				// strum.y puede incluir desplazamientos visuales (drunk, tipsy…)
				// que NO deben contaminar la referencia de posicionamiento de notas.
				// logicalY = baseY + offsetY, sin modificadores visuales.
				final _sn:StrumNote = (strum != null) ? Std.downcast(strum, StrumNote) : null;
				strumCenterY = (_sn != null) ? _sn.logicalY : ((strum != null) ? strum.y : strumLineY);
				_frameCenterYCache[_strumCacheKey] = strumCenterY;
			}
			else
				strumCenterY = _cached;
		}

		final _refY:Float = strumCenterY;

		var visualCenter:Float;
		{
			final _cachedVC = _frameVisualCenterCache[_strumCacheKey];
			if (Math.isNaN(_cachedVC))
			{
				// BUG FIX: restar strum.offset.y para que el punto de clip sea estable
				// independientemente del scale del strum (beat bumps, modchart scale, etc.).
				// Sin esto: strum.height = frameHeight * scale.y, así que visualCenter se
				// desplazaba hacia abajo durante beat bumps cuando scale.y > 1.
				// Correcto: strum.y - offset.y + height/2 = strum.y + frameHeight/2 (constante).
				visualCenter = strumCenterY - strum.offset.y + (strum.height / 2);
				_frameVisualCenterCache[_strumCacheKey] = visualCenter;
			}
			else
				visualCenter = _cachedVC;
		}

		// ── Leer modificadores per-nota del ModChartManager (si existe) ────────
		var _modState:funkin.gameplay.modchart.StrumState = null;

		var _noteGroupId:String = note.mustPress ? "player" : "cpu";
		if (_frameModEnabled)
		{
			// Grupos 0 y 1 (estándar): usar alias "player"/"cpu" basado en mustPress,
			// igual que getStrumForDirection. strumsGroupIndex 0/1 NO tiene una
			// correspondencia fija con allStrumsGroups[0/1] porque mustHitSection
			// puede hacer que un groupIdx=0 sea CPU o player según la sección.
			// Grupos >= 2 sí tienen groupId propio asignado explícitamente en el JSON.
			if (note.strumsGroupIndex >= 2 && note.strumsGroupIndex < _frameGroupCount)
				_noteGroupId = allStrumsGroups[note.strumsGroupIndex].id;
			_modState = modManager.getState(_noteGroupId, note.noteData);
		}

		// ── Scroll speed con multiplicador per-strum ────────────────────────────
		final _scrollMult:Float = (_modState != null) ? _modState.scrollMult : 1.0;

		final _isInvert:Bool = (_modState != null && _modState.invert > 0.5);
		final _effectiveDownscroll:Bool = downscroll != _isInvert;
		final _effectiveSpeed:Float = _scrollSpeed * _scrollMult;

		// ── Posición Y base (referenciada al strum) ─────────────────────────────
		var noteY:Float;
		if (_effectiveDownscroll)
			noteY = _refY + (songPosition - note.strumTime) * _effectiveSpeed;
		else
			noteY = _refY - (songPosition - note.strumTime) * _effectiveSpeed;

		// ── Y modifiers (BUG FIX v3: drunkY, noteOffsetY, bumpy, wave nunca se aplicaban) ─
		var _noteYOffset:Float = 0;
		if (_modState != null)
		{
			// NOTE_OFFSET_Y: offset plano en Y para todas las notas
			_noteYOffset += _modState.noteOffsetY;

			// DRUNK_Y: onda senoidal en Y según strumTime (espejo de drunkX en el eje Y)
			if (_modState.drunkY != 0)
				_noteYOffset += _modState.drunkY * Math.sin(note.strumTime * 0.001 * _modState.drunkFreq + songPosition * 0.0008);

			if (_modState.bumpy != 0)
				_noteYOffset += _modState.bumpy * Math.sin(songPosition * 0.001 * _modState.bumpySpeed);

			// WAVE: ola Y viajante — cada nota tiene desfase según su strumTime.
			// Produce ondas que "viajan" de abajo hacia arriba por la columna de notas.
			if (_modState.wave != 0)
				_noteYOffset += _modState.wave * Math.sin(songPosition * 0.001 * _modState.waveSpeed - note.strumTime * 0.001);
		}
		noteY += _noteYOffset;

		if ((_scrollTransitioning || _invertTransitioning) && note._lerpFromY >= 0.0 && note._lerpT < 1.0)
		{
			// Avanzar el progreso del lerp usando tiempo real (sin escalar por timeScale)
			// para que la animación dure ~0.15 s de pantalla sin importar el rate.
			// También cubre la transición de INVERT (_invertTransitioning).
			final rawElapsed:Float = FlxG.elapsed / (FlxG.timeScale > 0 ? FlxG.timeScale : 1.0);
			note._lerpT = Math.min(1.0, note._lerpT + rawElapsed * 12.0);
			final easedT:Float = FlxEase.quartOut(note._lerpT);
			noteY = note._lerpFromY + (noteY - note._lerpFromY) * easedT;
		}

		if (!note.isSustainNote)
			note.y = noteY;

		if (strum != null)
		{
			// ── Ángulo base del strum ─────────────────────────────────────────
			// _baseAngle acumula: rotación del strum + confusion + tornado.
			// INVERT NO entra aquí: se aplica distinto según el tipo de nota.
			//   • Notas normales → +180° al ángulo final (rota el sprite).
			//   • Sustains       → flipX/flipY (preserva el vector del snake).
			var _baseAngle:Float = strum.angle;

			if (_modState != null)
			{
				// CONFUSION: rotación plana extra en cada nota
				_baseAngle += _modState.confusion;

				// TORNADO: cada nota rota según su strumTime (efecto carrusel).
				if (_modState.tornado != 0)
					_baseAngle += _modState.tornado * Math.sin(note.strumTime * 0.001 * _modState.drunkFreq);
			}

			// INVERT para notas normales: rotar la flecha 180° cuando la dirección
			// efectiva es downscroll (notas vienen de arriba).
			// Usa _effectiveDownscroll (XOR) para ser consistente con la posición Y.
			//
			// INVERT FIX: en downscroll real, Note.hx inicializa flipX=true/flipY=true.
			// Con INVERT activo en upscroll, la nota nació con flipX=false/flipY=false
			// pero recibe +180° de ángulo → apariencia diferente al downscroll real.
			// Solución: forzar flipX/flipY al valor que tendría en downscroll efectivo,
			// sobreescribiendo el estado de inicialización en cada frame.
			if (!note.isSustainNote)
			{
				note.angle = _baseAngle + (_effectiveDownscroll ? 180.0 : 0.0);
				note.flipX = _effectiveDownscroll;
				note.flipY = _effectiveDownscroll;
			}

			// ── Escala / alpha ────────────────────────────────────────────────
			var newSX = strum.scale.x;
			final newSY = note.isSustainNote ? note.sustainBaseScaleY : strum.scale.y;

			// BEAT_SCALE: pulso de escala lanzado en cada beat desde onBeatHit
			if (_modState != null && _modState._beatPulse > 0)
				newSX = newSX * (1.0 + _modState._beatPulse);

			// Epsilon threshold: evita updateHitbox() + dos sumas de offset cuando el cambio de escala
			// es puro ruido de punto flotante (<0.001 px). _beatPulse y strum.scale pueden acumular
			// épsilon tras varias operaciones; sin el umbral, updateHitbox() se dispararía cada frame
			// aunque el sprite visualmente no cambie de tamaño.
			final scaleChanged = Math.abs(note.scale.x - newSX) > 0.001 || Math.abs(note.scale.y - newSY) > 0.001;
			note.scale.x = newSX;
			note.scale.y = newSY;
			if (scaleChanged)
			{
				note.updateHitbox();
				note.offset.x += note.noteOffsetX;
				note.offset.y += note.noteOffsetY;
			}

			// ── Alpha: strum + NOTE_ALPHA override + STEALTH ─────────────────
			var _baseAlpha:Float = FlxMath.bound(strum.alpha, 0.05, 1.0);
			if (_modState != null)
			{
				// NOTE_ALPHA: multiplicador de alpha per-nota (independent del strum)
				_baseAlpha *= FlxMath.bound(_modState.noteAlpha, 0.0, 1.0);

				// STEALTH: notas completamente invisibles pero todavía hiteables
				if (_modState.stealth > 0.5)
					_baseAlpha = 0.0;
			}

			if (note.tooLate)
				note.alpha = note.isSustainNote ? (_cachedSustainMiss ? 0.3 : 0.2) : 0.3;
			else
				note.alpha = _baseAlpha;

			// ── Posición X base ───────────────────────────────────────────────
			// Usar logicalX en lugar de strum.x: después del fix de strum visual,
			// strum.x puede incluir desplazamientos visuales (drunk, tipsy…).
			// logicalX = baseX + offsetX, es la referencia limpia de posicionamiento.
			final _sn:StrumNote = Std.downcast(strum, StrumNote);
			final _logStrumX:Float = (_sn != null) ? _sn.logicalX : strum.x;
			var _noteX:Float = _logStrumX + (strum.width - note.width) / 2;

			if (_modState != null)
			{
				// NOTE_OFFSET_X: offset plano en X
				_noteX += _modState.noteOffsetX;

				// DRUNK_X: onda senoidal en X usando strumTime de la nota.
				if (_modState.drunkX != 0)
					_noteX += _modState.drunkX * Math.sin(note.strumTime * 0.001 * _modState.drunkFreq + songPosition * 0.0008);

				// TIPSY: ola X global por songPosition (todas las notas oscilan juntas en X)
				if (_modState.tipsy != 0)
					_noteX += _modState.tipsy * Math.sin(songPosition * 0.001 * _modState.tipsySpeed);

				// ZIGZAG: patrón escalonado en X alternando +amp / -amp
				if (_modState.zigzag != 0)
				{
					// sign(sin(x)) da exactamente +1 o -1, produciendo el escalón
					var _zz = Math.sin(note.strumTime * 0.001 * _modState.zigzagFreq * Math.PI);
					_noteX += _modState.zigzag * (_zz >= 0 ? 1.0 : -1.0);
				}

				// FLIP_X: espejo horizontal alrededor del centro lógico del strum
				if (_modState.flipX > 0.5)
				{
					final _strumCenter = _logStrumX + strum.width / 2;
					_noteX = _strumCenter - (_noteX - _strumCenter + note.width / 2) - note.width / 2;
				}
			}

			note.x = _noteX;

			if (note.isSustainNote)
			{
				note.flipX = false;
				note.flipY = note.isTailCap && _effectiveDownscroll;

				// ── Position of the NEXT step (end-of-piece / start-of-next) ──
				final _nextStrumTime:Float = note.strumTime + Conductor.stepCrochet;

				// Next Y: misma fórmula que noteY pero en _nextStrumTime
				var _nextY:Float = _effectiveDownscroll ? _refY + (songPosition - _nextStrumTime) * _effectiveSpeed : _refY
					- (songPosition - _nextStrumTime) * _effectiveSpeed;

				// Apply same Y modifiers evaluated at _nextStrumTime
				if (_modState != null)
				{
					_nextY += _modState.noteOffsetY;

					if (_modState.drunkY != 0)
						_nextY += _modState.drunkY * Math.sin(_nextStrumTime * 0.001 * _modState.drunkFreq + songPosition * 0.0008);

					if (_modState.bumpy != 0)
						_nextY += _modState.bumpy * Math.sin(songPosition * 0.001 * _modState.bumpySpeed);

					if (_modState.wave != 0)
						_nextY += _modState.wave * Math.sin(songPosition * 0.001 * _modState.waveSpeed - _nextStrumTime * 0.001);
				}

				// Next X: misma fórmula que _noteX pero en _nextStrumTime
				var _nextX:Float = _logStrumX + (strum.width - note.width) / 2;
				if (_modState != null)
				{
					_nextX += _modState.noteOffsetX;

					if (_modState.drunkX != 0)
						_nextX += _modState.drunkX * Math.sin(_nextStrumTime * 0.001 * _modState.drunkFreq + songPosition * 0.0008);

					if (_modState.tipsy != 0)
						_nextX += _modState.tipsy * Math.sin(songPosition * 0.001 * _modState.tipsySpeed);

					if (_modState.zigzag != 0)
					{
						var _zzN = Math.sin(_nextStrumTime * 0.001 * _modState.zigzagFreq * Math.PI);
						_nextX += _modState.zigzag * (_zzN >= 0 ? 1.0 : -1.0);
					}

					if (_modState.flipX > 0.5)
					{
						final _sc:Float = _logStrumX + strum.width / 2;
						_nextX = _sc - (_nextX - _sc + note.width / 2) - note.width / 2;
					}
				}

				final _dX:Float = _nextX - note.x;
				final _dY:Float = _nextY - noteY; // noteY, no note.y

				final _rad:Float = Math.atan2(_dY, _dX);
				final _deg:Float = _rad * (180.0 / Math.PI);

				// _baseAngle: sin INVERT 180° — el flip ya está en flipX/flipY.
				note.angle = _baseAngle + (_deg - 90.0);

				// ── Scale.y: actual Euclidean distance (NV style) ─────────────
				// Body pieces stretch to exactly fill the gap between this piece
				// and the next. Tail caps keep their base scale (they're the end
				// graphic and shouldn't stretch).
				final _isTailCap:Bool = note.isTailCap;

				if (!_isTailCap)
				{
					// Fast-path: sin desplazamiento lateral real (columna recta, sin drunk/tipsy/zigzag activos),
					// dist == |dy| — evitar Math.sqrt completamente.
					// Con 20+ piezas de sustain en pantalla × 60 fps = 1200+ sqrt/s ahorrados en gameplay normal.
					final _absX:Float = _dX < 0 ? -_dX : _dX;
					final _dist:Float = _absX < 0.5
						? (_dY < 0 ? -_dY : _dY)
						: Math.sqrt(_dX * _dX + _dY * _dY);
					final _fh:Float = note.frameHeight > 0 ? note.frameHeight : 1.0;
					// Small seam overlap (2px in frame-space) prevents hairline
					// gaps at high scroll speeds or extreme angles.
					note.scale.y = (_dist + 2.0) / _fh;
				}
				// else: tail cap — leave scale.y as sustainBaseScaleY
			}
		}

		// ── V-Slice style fade: desvanecer notas que pasan el strum ─────────
		// Solo aplica a notas del jugador que no fueron golpeadas
		if (note.mustPress && !note.wasGoodHit && !note.isSustainNote)
		{
			var distPast:Float;
			if (downscroll)
				distPast = note.y - strumLineY;
			else
				distPast = strumLineY - note.y;
		}

		// NOTE: Y modifiers (noteOffsetY, drunkY, bumpy, wave) are already accumulated
		// in _noteYOffset above (lines ~1011-1031) and added to noteY before note.y is
		// set at line 1044. The duplicate application block that previously appeared here
		// has been removed — it caused every modifier to fire twice for normal notes,
		// doubling displacement and wasting 3+ trig calls per note per frame.

		if (note.isSustainNote)
		{
			if ((_scrollTransitioning || _invertTransitioning) && note._lerpFromY >= 0.0 && note._lerpT < 1.0)
			{
				final easedT:Float = FlxEase.quartOut(note._lerpT);
				noteY = note._lerpFromY + (noteY - note._lerpFromY) * easedT;

				if (note._lerpFromScaleY > 0.0)
				{
					final targetSY:Float = note.sustainBaseScaleY; // target ya recalculado
					note.scale.y = note._lerpFromScaleY + (targetSY - note._lerpFromScaleY) * easedT;
				}
			}

			final visualHeight:Float = (note.frameHeight > 0 ? note.frameHeight : 1.0) * note.scale.y;

			if (_effectiveDownscroll) {
				note.y = noteY - visualHeight;
			} else {
				note.y = noteY;
			}
		}

		if (_frameModEnabled && modManager.hasNotePositionHook)
		{
			final ctx = modManager.noteCtx;
			ctx.noteData = note.noteData;
			ctx.strumTime = note.strumTime;
			ctx.songPosition = songPosition;
			ctx.beat = modManager.currentBeat;
			ctx.isPlayer = note.mustPress;
			ctx.isSustain = note.isSustainNote;
			ctx.groupId = _noteGroupId;
			ctx.scrollMult = _modState != null ? _modState.scrollMult : 1.0;
			ctx.x = note.x;
			ctx.y = note.y;
			ctx.angle = note.angle;
			ctx.alpha = note.alpha;
			ctx.scaleY = note.scale.y;
			// INVERT FIX: exponer el estado actual de flipX/flipY al script para que
			// onNotePosition pueda leer (y opcionalmente modificar) el flip efectivo.
			// Sustains: flipX siempre false (dirección gestionada por ángulo).
			ctx.flipX = note.isSustainNote ? false : note.flipX;
			ctx.flipY = note.flipY;
			modManager.callNotePositionHook(ctx);
			note.x = ctx.x;
			note.y = ctx.y;
			note.angle = ctx.angle;
			note.alpha = ctx.alpha;
			// scaleY solo si cambió (evita updateHitbox innecesario)
			if (note.isSustainNote && ctx.scaleY != note.scale.y)
				note.scale.y = ctx.scaleY;
			// Aplicar flipX/flipY del script con las restricciones de cada tipo:
			//   • Notas normales: el script puede cambiar flipX y flipY libremente.
			//   • Sustains body:  flipX siempre false (la dirección la gestiona el ángulo snake).
			//   • Sustains tail:  el script puede cambiar flipY; flipX sigue siendo false.
			if (!note.isSustainNote)
			{
				note.flipX = ctx.flipX;
				note.flipY = ctx.flipY;
			}
			else if (note.isTailCap)
			{
				note.flipY = ctx.flipY;
				// note.flipX queda en false (ya fijado arriba, no se toca)
			}
		}

		final _noteWidth2:Float = note.width * 2;

		if (note.isSustainNote)
		{
			if (note.tooLate)
			{
				// Nota fallida: sin clipRect — se ve completa mientras sale de pantalla.
				// Sin este bypass, el bloque de clip la cortaría en el strum,
				// la volvería invisible y al cruzarlo aparecería de nuevo scrolleando.
				note.clipRect = null;
			}
			else
			{
				// Enfoque NoteManager2: threshold unificado en la MITAD del strum,
				// usando Note.swagWidth * 0.5 como offset fijo respecto al strum de la nota.
				// Se aplica igual a wasGoodHit y !wasGoodHit — lógica uniforme para
				// player y CPU, upscroll y downscroll.
				//
				// INVERT FIX (bug principal): usar _refY (la Y real del strum de ESTA nota)
				// en lugar de strumLineY (la Y global del strum del jugador).
				// Con MOVE_Y=500 en CPU, el strum CPU está a _refY≈550 pero strumLineY≈50.
				// El clip en strumLineY recortaba todos los sustains CPU desde el primer frame,
				// haciéndolos invisibles. Ahora cada nota se recorta en su propio strum.
				//
				// BUG FIX: usar _effectiveDownscroll (= downscroll XOR modchart invert)
				// para que el clip sea correcto cuando el mod INVERT está activo.
				final halfStrum:Float = funkin.gameplay.notes.Note.swagWidth * 0.5;
				final strumLineThreshold:Float = _effectiveDownscroll
					? _refY - halfStrum   // downscroll/invert: threshold desplazado hacia arriba del strum
					: _refY + halfStrum;  // upscroll: threshold desplazado hacia dentro del strum

				if (_effectiveDownscroll)
				{
					// Downscroll: la nota baja de arriba → strum. Cortamos el fondo
					// cuando cruza strumLineThreshold.
					final noteBottom:Float = note.y + note.height;
					if (noteBottom >= strumLineThreshold)
					{
						var clipH:Float = (strumLineThreshold - note.y) / note.scale.y;
						if (clipH <= 0)
						{
							note.clipRect = null;
							if (note.wasGoodHit)
							{
								note.visible = false;
								removeNote(note);
							}
						}
						else
						{
							_sustainClipRect.x      = 0;
							_sustainClipRect.width  = _noteWidth2;
							_sustainClipRect.height = clipH;
							_sustainClipRect.y      = note.frameHeight - clipH;
							if (note.clipRect == null)
								note.clipRect = new flixel.math.FlxRect();
							note.clipRect.copyFrom(_sustainClipRect);
							note.clipRect = note.clipRect;
						}
					}
					else
					{
						note.clipRect = null;
					}
				}
				else
				{
					// Upscroll: la nota sube hacia el strum (Y decrece).
					// Cortamos la parte superior que ya cruzó strumLineThreshold.
					if (note.y < strumLineThreshold)
					{
						var clipY:Float = (strumLineThreshold - note.y) / note.scale.y;
						var clipH:Float = note.frameHeight - clipY;
						if (clipH > 0 && clipY >= 0)
						{
							_sustainClipRect.x      = 0;
							_sustainClipRect.width  = _noteWidth2;
							_sustainClipRect.y      = clipY;
							_sustainClipRect.height = clipH;
							if (note.clipRect == null)
								note.clipRect = new flixel.math.FlxRect();
							note.clipRect.copyFrom(_sustainClipRect);
							note.clipRect = note.clipRect;
						}
						else
						{
							// Nota completamente por encima del strum: ocultar si ya fue consumida.
							if (note.wasGoodHit)
							{
								note.visible = false;
								removeNote(note);
							}
							note.clipRect = null;
						}
					}
					else
					{
						note.clipRect = null;
					}
				}
			}
		}
	}

	private function removeNote(note:Note):Void
	{
		note.kill();
		// Remover del grupo correcto según tipo de nota
		if (note.isSustainNote && sustainNotes != notes)
			sustainNotes.remove(note, true);
		else
			notes.remove(note, true);
		if (renderer != null)
			renderer.recycleNote(note);
	}

	public function hitNote(note:Note, rating:String):Void
	{
		if (note.wasGoodHit)
			return;
		note.wasGoodHit = true;
		handleStrumAnimation(note.noteData, note.strumsGroupIndex, true);

		// sustainMiss: el jugador acertó la siguiente head note → la cadena puede
		// volver a penalizar si se suelta antes de tiempo.
		if (!note.isSustainNote)
		{
			_sustainChainMissed[note.noteData] = false;
			_sustainChainMissedEndTime[note.noteData] = -1.0; // limpiar límite de cadena penalizada
		}

		if (!note.isSustainNote && note.sustainLength > 0)
		{
			var newEnd = note.strumTime + note.sustainLength - SaveData.data.offset;
			if (!holdEndTimes.exists(note.noteData))
				holdEndTimes.set(note.noteData, newEnd);
			else
				holdEndTimes.set(note.noteData, Math.max(holdEndTimes.get(note.noteData), newEnd));
		}
		if (rating == "sick")
		{
			if (note.isSustainNote)
				handleSustainNoteHit(note);
			else if (_cachedNoteSplashes && _noteSplashesEnabled && renderer != null)
				createNormalSplash(note, true);
		}
		if (!note.isSustainNote)
			removeNote(note);
		if (onNoteHit != null)
			onNoteHit(note);
	}

	private function handleSustainNoteHit(note:Note):Void
	{
		var direction = note.noteData;
		if (!heldNotes.exists(direction))
		{
			heldNotes.set(direction, note);
			holdStartTimes.set(direction, Conductor.songPosition);

			if (!holdEndTimes.exists(direction))
			{
				// Paso 1: encontrar el strumTime raw más tardío entre piezas spawneadas
				var chainEnd:Float = note.strumTime - SaveData.data.offset;
				final smembers = sustainNotes.members;
				final slen = smembers.length;
				for (si in 0...slen)
				{
					final sn = smembers[si];
					if (sn == null || !sn.alive || !sn.isSustainNote || sn.noteData != direction || sn.mustPress != note.mustPress)
						continue;
					final rawT = sn.strumTime - SaveData.data.offset;
					if (rawT > chainEnd)
						chainEnd = rawT;
				}
				final gapThresh:Float = Conductor.stepCrochet * 2.0;
				for (ui in _unspawnIdx..._rawTotal)
				{
					final rawST = _rawStrumTime[ui];
					if (rawST > chainEnd + gapThresh)
						break;
					final pk = _rawPacked[ui];
					if (_pIsSustain(pk) && _pNoteData(pk) == direction && _pMustHit(pk) == note.mustPress)
						chainEnd = rawST;
				}
				holdEndTimes.set(direction, chainEnd + Conductor.stepCrochet);
				trace('[NoteManager] holdEndTime calculado (HEAD perdida) dir=$direction → ${holdEndTimes.get(direction)}ms');
			}

			if (_cachedNoteSplashes && _cachedHoldCoverEnabled && renderer != null)
			{
				var strum = getStrumForDirection(direction, note.strumsGroupIndex, true);
				if (strum != null)
				{
					_playerHoldGroupIdx[direction] = note.strumsGroupIndex;
					var holdSplashPlayer = NoteTypeManager.getHoldSplashName(note.noteType);
					// FIX: strum.width/height incluyen scale; frameWidth/Height son px sin escalar.
					// Usar dims escaladas y descontar strum.offset para coincidir con el centro
					// visual real (igual que la llamada equivalente en handleCPUNote, linea ~876).
					// FIX (v-slice parity): centro gráfico = frameWidth/Height * scale.
					var cover = renderer.startHoldCover(direction, strum.x - strum.offset.x + strum.frameWidth * strum.scale.x * 0.5, strum.y - strum.offset.y + strum.frameHeight * strum.scale.y * 0.5, true, note.strumsGroupIndex,
						holdSplashPlayer);
					if (cover != null && !_holdCoverSet.exists(cover) && holdCovers.members.indexOf(cover) < 0)
					{
						_holdCoverSet.set(cover, true);
						holdCovers.add(cover);
					}
				}
			}
		}
		// No llamar removeNote aquí — hitNote() ya lo hace después
	}

	public function releaseHoldNote(direction:Int):Void
	{
		if (!heldNotes.exists(direction))
			return;
		if (renderer != null)
			// BUG FIX: pasar strumsGroupIndex guardado para que la clave del Map
			// coincida con la que startHoldCover() registró. Sin esto, el cover
			// nunca recibe playEnd() y queda en STATE_LOOP eternamente si
			// strumsGroupIndex > 0.
			renderer.stopHoldCover(direction, true, _playerHoldGroupIdx[direction]);
		heldNotes.remove(direction);
		holdStartTimes.remove(direction);
		holdEndTimes.remove(direction);
	}

	private function createNormalSplash(note:Note, isPlayer:Bool):Void
	{
		if (renderer == null)
			return;
		var strum = getStrumForDirection(note.noteData, note.strumsGroupIndex, isPlayer);
		if (strum != null)
		{
			var splashName = NoteTypeManager.getSplashName(note.noteType);
			// FIX (v-slice parity): pasar la esquina del GRÁFICO (strum.x - offset.x, strum.y - offset.y),
			// no la del hitbox (strum.x, strum.y). V-Slice posiciona el splash en la misma X
			// que el strum receptor (posición gráfica), no en la esquina del hitbox de Flixel.
			var splash = renderer.spawnSplash(strum.x - strum.offset.x, strum.y - strum.offset.y, note.noteData, splashName);
			if (splash != null)
				splashes.add(splash);
		}
	}

	/**
	 * Obtiene el strum para una dirección dada.
	 * OPTIMIZADO: usa caché Map<Int, FlxSprite> para O(1) en vez de forEach O(n).
	 * El forEach anterior creaba una closure nueva cada llamada — ahora es solo
	 * un Map lookup. Con 20 notas en pantalla esto elimina ~80 closures por frame.
	 */
	/**
	 * Alias público de getStrumForDirection para ModchartHoldMesh.
	 * Inline → sin coste en runtime vs. llamar directamente al privado.
	 */
	public inline function getStrumForDir(direction:Int, strumsGroupIndex:Int, isPlayer:Bool):FlxSprite
		return getStrumForDirection(direction, strumsGroupIndex, isPlayer);

	private function getStrumForDirection(direction:Int, strumsGroupIndex:Int, isPlayer:Bool):FlxSprite
	{
		// Grupos adicionales (strumsGroupIndex >= 2) — caché por grupo
		if (allStrumsGroups != null && allStrumsGroups.length > 0 && strumsGroupIndex >= 2)
		{
			var groupMap = _strumGroupCache.get(strumsGroupIndex);
			if (groupMap != null)
				return groupMap.get(direction);
		}

		// Grupos 0 y 1 — caché por dirección
		return isPlayer ? _playerStrumCache.get(direction) : _cpuStrumCache.get(direction);
	}

	/**
	 * sustainMiss: marca como tooLate UNICAMENTE las piezas de sustain de la
	 * cadena ACTUAL en la direccion `dir`. Las cadenas futuras (separadas por un
	 * gap > stepCrochet * 2) NO se tocan, corrigiendo el bug donde al fallar
	 * un sustain la siguiente cadena separada tambien bajaba su alpha.
	 *
	 * Algoritmo:
	 *   1. Buscar el strumTime minimo entre piezas elegibles → inicio de cadena.
	 *   2. Extender hacia adelante mientras el siguiente sustain este dentro del
	 *      umbral de gap → fin de cadena.
	 *   3. Guardar el fin en _sustainChainMissedEndTime[dir] para que spawnNotes()
	 *      no marque born-dead piezas que pertenezcan a cadenas posteriores.
	 *   4. Marcar solo las piezas cuyo strumTime <= chainEnd.
	 */
	private function _markSustainChainMissed(dir:Int):Void
	{
		final smembers = sustainNotes.members;
		final slen = smembers.length;
		final gapThresh:Float = Conductor.stepCrochet * 2.0;

		// Recopilar los strumTimes de las piezas elegibles — O(n).
		// ANTES: paso 2 era un while/found que reescaneaba n veces → O(n²).
		// AHORA: ordenar una vez O(k log k) y extender en un único paso lineal O(k),
		// con k = piezas elegibles de esta dirección (típicamente ≪ n total).
		var eligible:Array<Float> = [];
		for (i in 0...slen)
		{
			final n = smembers[i];
			if (n == null || !n.alive || !n.isSustainNote || n.noteData != dir || n.wasGoodHit || n.tooLate)
				continue;
			eligible.push(n.strumTime);
		}

		if (eligible.length == 0)
		{
			_sustainChainMissedEndTime[dir] = -1.0;
			return; // nada que marcar
		}

		// Ordenar una sola vez — necesario para que el break del paso siguiente sea correcto.
		eligible.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);

		var chainStart:Float = eligible[0];
		var chainEnd:Float   = chainStart;

		// Paso único: recorrer en orden ascendente.
		// La lista está ordenada → en cuanto hay un hueco podemos cortar.
		for (i in 1...eligible.length)
		{
			final t = eligible[i];
			if (t <= chainEnd + gapThresh)
				chainEnd = t;
			else
				break; // hueco detectado — imposible extender más sin backtrack
		}

		// Guardar el limite para spawnNotes() y para el reset en hitNote()
		_sustainChainMissedEndTime[dir] = chainEnd;

		// Paso 3: marcar SOLO las piezas de esta cadena
		for (i in 0...slen)
		{
			final n = smembers[i];
			if (n == null || !n.alive || !n.isSustainNote || n.noteData != dir || n.wasGoodHit || n.tooLate)
				continue;
			if (n.strumTime > chainEnd + gapThresh)
				continue; // cadena futura — no tocar
			n.tooLate = true;
			n.alpha = 0.3;
		}
	}

	public function missNote(note:Note):Void
	{
		if (note == null || note.wasGoodHit)
			return;
		// Para sustains: ya se contó el miss en updateActiveNotes, no volver a contar
		if (heldNotes.exists(note.noteData))
			releaseHoldNote(note.noteData);
		if (onNoteMiss != null && !note.isSustainNote)
			onNoteMiss(note);
		// Marcar como fallida y bajar el alpha — sigue de largo hasta salir de pantalla
		note.tooLate = true;
		note.alpha = 0.3;
	}

	// ─── Rewind Restart (V-Slice style) ──────────────────────────────────────

	/**
	 * Actualiza SOLO la posición visual de las notas activas — sin spawn ni kill.
	 * Llamar durante la animación de rewind para que las notas deslicen hacia atrás.
	 */
	public function updatePositionsForRewind(songPosition:Float):Void
	{
		// Sincronizar cachés de frame: updateNotePosition() los necesita aunque no pasemos por updateActiveNotes().
		_frameModEnabled = modManager != null && modManager.enabled;
		_frameGroupCount = (allStrumsGroups != null) ? allStrumsGroups.length : 0;
		_rewindUpdateGroup(sustainNotes.members, sustainNotes.members.length, songPosition);
		if (sustainNotes != notes)
			_rewindUpdateGroup(notes.members, notes.members.length, songPosition);
		if (renderer != null)
			renderer.updateBatcher();
	}

	private inline function _rewindUpdateGroup(members:Array<Note>, len:Int, songPosition:Float):Void
	{
		for (i in 0...len)
		{
			final note = members[i];
			if (note == null || !note.alive)
				continue;
			updateNotePosition(note, songPosition);
			if (note.y < -_dynCullDist || note.y > FlxG.height + _dynCullDist)
				note.visible = false;
			else
				note.visible = true;
		}
	}

	/**
	 * Mata todas las notas activas y retrocede el índice de spawn
	 * al punto correcto para `targetTime` (generalmente inicio del countdown).
	 * Llamar al finalizar la animación de rewind.
	 */
	public function rewindTo(targetTime:Float):Void
	{
		// FIX: _trimRawArrays() may have compacted the SOA, discarding early notes.
		// Regenerating from the cached SONG reference restores the full dataset so
		// every note (including sustains) is available for re-spawn after rewind.
		// generateNotes() resets _unspawnIdx, _prevSpawnedNote, and intern tables,
		// so the state cleanup below remains valid on top of the fresh arrays.
		if (_song != null)
			generateNotes(_song);

		// Matar todas las notas vivas en ambos grupos
		if (sustainNotes != notes)
		{
			var i = sustainNotes.members.length - 1;
			while (i >= 0)
			{
				var n = sustainNotes.members[i];
				if (n != null && n.alive)
					removeNote(n);
				i--;
			}
		}
		var i = notes.members.length - 1;
		while (i >= 0)
		{
			var n = notes.members[i];
			if (n != null && n.alive)
				removeNote(n);
			i--;
		}

		_prevSpawnedNote.clear();
		heldNotes.clear();
		_cpuHeldDirs[0] = _cpuHeldDirs[1] = _cpuHeldDirs[2] = _cpuHeldDirs[3] = false;
		_cpuHoldGroupIdx[0] = _cpuHoldGroupIdx[1] = _cpuHoldGroupIdx[2] = _cpuHoldGroupIdx[3] = 0;
		_playerHoldGroupIdx[0] = _playerHoldGroupIdx[1] = _playerHoldGroupIdx[2] = _playerHoldGroupIdx[3] = 0;
		holdStartTimes.clear();
		holdEndTimes.clear();
		cpuHoldEndTimes[0] = cpuHoldEndTimes[1] = cpuHoldEndTimes[2] = cpuHoldEndTimes[3] = -1;
		_missedHoldDir[0] = _missedHoldDir[1] = _missedHoldDir[2] = _missedHoldDir[3] = false;
		_sustainChainMissed[0] = _sustainChainMissed[1] = _sustainChainMissed[2] = _sustainChainMissed[3] = false;
		_sustainChainMissedEndTime[0] = _sustainChainMissedEndTime[1] = _sustainChainMissedEndTime[2] = _sustainChainMissedEndTime[3] = -1.0;
		playerHeld = [false, false, false, false];
		_holdCoverSet.clear();

		// BUGFIX escala pixel: limpiar el pool de notas para que las nuevas se creen
		// desde cero con la skin activa correcta. Sin esto, notas recicladas del pool
		// pueden tener _noteScale = 0.7 (Default) si la skin se corrompió durante el juego,
		// causando que las notas pixel (scale 6.0) aparezcan en tamaño de notas normales.
		if (renderer != null)
			renderer.clearPools();

		// Retroceder el índice de spawn:
		// queremos empezar a spawnear desde notas cuyo strumTime ≥ targetTime - spawnWindow.
		// Usar la misma fórmula que _dynSpawnTime pero con velocidad base (targetScrollRate=1)
		// ya que el rewind siempre vuelve al inicio de la canción donde el scroll es normal.
		final _baseSpeed:Float = Math.max(0.45 * songSpeed, 0.005);
		final spawnWindow:Float = Math.max(600.0, (FlxG.height + SPAWN_PAD_PX) / _baseSpeed);
		var cutoff:Float = targetTime - spawnWindow;

		_unspawnIdx = 0;
		// Si targetTime es negativo (countdown), cutoff también es negativo → _unspawnIdx = 0 (correcto)
		if (cutoff > 0)
		{
			while (_unspawnIdx < _rawTotal && _rawStrumTime[_unspawnIdx] < cutoff)
				_unspawnIdx++;
		}

		trace('[NoteManager] rewindTo($targetTime) → _unspawnIdx=$_unspawnIdx / $_rawTotal');
	}

	// ─── Hold splash live tracking ────────────────────────────────────────────

	/**
	 * Re-center every active NoteHoldCover on its strum's CURRENT position.
	 *
	 * FIX EXPLAINED:
	 *   startHoldCover() in NoteRenderer captures the strum center once at
	 *   the moment the hold begins.  When strums move (modchart events, stage
	 *   scripts, beat-bump animations, etc.) the hold splash is left at the
	 *   old position and visually drifts away from the strum arrow.
	 *
	 *   This function is called every frame (via update()) and pushes the strum's
	 *   LIVE position into each active cover via NoteRenderer.updateActiveCoverPosition().
	 *
	 * COST:
	 *   - Iterates heldNotes.keys() (≤ 4 player holds) + 4 CPU directions.
	 *   - Each iteration does one Map lookup + one getStrumForDirection (O(1) cached).
	 *   - NoteHoldCover._applyPosition() is two float additions. Negligible.
	 */
	private function _updateHoldCoverPositions():Void
	{
		if (renderer == null)
			return;

		// ── Player holds ────────────────────────────────────────────────────
		for (dir in heldNotes.keys())
		{
			final note = heldNotes.get(dir);
			if (note == null)
				continue;

			final strum = getStrumForDirection(dir, note.strumsGroupIndex, true);
			if (strum == null)
				continue;

			final cx:Float = strum.x - strum.offset.x + strum.frameWidth  * strum.scale.x * 0.5;
			final cy:Float = strum.y - strum.offset.y + strum.frameHeight * strum.scale.y * 0.5;

			// Key formula mirrors NoteRenderer.startHoldCover / stopHoldCover
			final key:Int = dir + note.strumsGroupIndex * 8;
			renderer.updateActiveCoverPosition(key, cx, cy);
		}

		// ── CPU holds ───────────────────────────────────────────────────────
		for (dir in 0...4)
		{
			if (!_cpuHeldDirs[dir])
				continue;

			final strum = getStrumForDirection(dir, _cpuHoldGroupIdx[dir], false);
			if (strum == null)
				continue;

			final cx:Float = strum.x - strum.offset.x + strum.frameWidth  * strum.scale.x * 0.5;
			final cy:Float = strum.y - strum.offset.y + strum.frameHeight * strum.scale.y * 0.5;

			// Key formula: CPU side = +4 offset in NoteRenderer
			final key:Int = dir + 4 + _cpuHoldGroupIdx[dir] * 8;
			renderer.updateActiveCoverPosition(key, cx, cy);
		}
	}

	public function destroy():Void
	{
		_rawStrumTime.resize(0);
		_rawPacked.resize(0);
		_rawSustainLen.resize(0);
		_rawNoteTypeId.resize(0);
		_rawTotal   = 0;
		_unspawnIdx = 0;
		_noteTypeIndex.clear();
		_noteTypeTable.resize(1);
		_noteTypeTable[0] = '';
		_prevSpawnedNote.clear();
		heldNotes.clear();
		_cpuHeldDirs[0] = _cpuHeldDirs[1] = _cpuHeldDirs[2] = _cpuHeldDirs[3] = false;
		_cpuHoldGroupIdx[0] = _cpuHoldGroupIdx[1] = _cpuHoldGroupIdx[2] = _cpuHoldGroupIdx[3] = 0;
		_playerHoldGroupIdx[0] = _playerHoldGroupIdx[1] = _playerHoldGroupIdx[2] = _playerHoldGroupIdx[3] = 0;
		holdStartTimes.clear();
		holdEndTimes.clear();
		cpuHoldEndTimes[0] = cpuHoldEndTimes[1] = cpuHoldEndTimes[2] = cpuHoldEndTimes[3] = -1;
		_missedHoldDir[0] = _missedHoldDir[1] = _missedHoldDir[2] = _missedHoldDir[3] = false;
		_sustainChainMissed[0] = _sustainChainMissed[1] = _sustainChainMissed[2] = _sustainChainMissed[3] = false;
		_sustainChainMissedEndTime[0] = _sustainChainMissedEndTime[1] = _sustainChainMissedEndTime[2] = _sustainChainMissedEndTime[3] = -1.0;
		_holdCoverSet.clear();
		_playerStrumCache = [];
		_cpuStrumCache = [];
		_strumGroupCache = [];
		sustainNotes = null;
		if (renderer != null)
		{
			renderer.clearPools();
			renderer.destroy();
		}
	}

	public function getPoolStats():String
		return renderer != null ? renderer.getPoolStats() : "No renderer";

	public function toggleBatching():Void
		if (renderer != null)
			renderer.toggleBatching();

	public function toggleHoldSplashes():Void
		if (renderer != null)
			renderer.toggleHoldSplashes();
}
