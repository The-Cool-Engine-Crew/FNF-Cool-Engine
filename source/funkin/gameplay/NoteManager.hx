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

class NoteManager {
	// ── Groups ───────────────────────────────────────────────────────────────
	public var notes:FlxTypedGroup<Note>;

	/** Drawn below `notes` so head notes always render on top of hold bodies. */
	public var sustainNotes:FlxTypedGroup<Note>;

	public var splashes:FlxTypedGroup<NoteSplash>;
	public var holdCovers:FlxTypedGroup<NoteHoldCover>;

	// ── Struct-of-Arrays raw note data (~24 B/note vs ~72 B for anon objects) ─
	// _rawPacked bits: 0-1=noteData, 2=isSustain, 3=mustHit, 4-11=groupIdx
	private static inline final RAW_TRIM_CHUNK:Int = 1024;

	private var _rawStrumTime:Array<Float> = [];
	private var _rawPacked:Array<Int> = [];
	private var _rawSustainLen:Array<Float> = [];
	private var _rawNoteTypeId:Array<Int> = [];
	private var _rawTotal:Int = 0;
	private var _unspawnIdx:Int = 0;
	private var _song:Null<SwagSong> = null;

	// Note-type intern table (id 0 = "")
	private var _noteTypeIndex:Map<String, Int> = [];
	private var _noteTypeTable:Array<String> = [''];

	// _prevSpawnedNote key encodes dir+group+side to avoid cross-chain corruption
	private var _prevSpawnedNote:Map<Int, Note> = new Map();

	private inline function _prevNoteKey(nd:Int, gi:Int, mh:Bool):Int
		return nd + gi * 4 + (mh ? 16 : 0);

	// SOA pack / unpack
	private static inline function _packNote(nd:Int, sus:Bool, mh:Bool, gi:Int):Int
		return (nd & 3) | (sus ? 4 : 0) | (mh ? 8 : 0) | ((gi & 0xFF) << 4);

	private static inline function _pNoteData(p:Int):Int
		return p & 3;

	private static inline function _pIsSustain(p:Int):Bool
		return (p & 4) != 0;

	private static inline function _pMustHit(p:Int):Bool
		return (p & 8) != 0;

	private static inline function _pGroupIdx(p:Int):Int
		return (p >> 4) & 0xFF;

	private inline function _internNoteType(s:String):Int {
		if (s == null || s == '' || s == 'normal')
			return 0;
		var id = _noteTypeIndex.get(s);
		if (id == null) {
			id = _noteTypeTable.length;
			_noteTypeTable.push(s);
			_noteTypeIndex.set(s, id);
		}
		return id;
	}

	/** Slide the compacted window forward, freeing already-spawned entries. */
	private function _trimRawArrays():Void {
		if (_unspawnIdx <= 0)
			return;
		final rem = _rawTotal - _unspawnIdx;
		if (rem <= 0) {
			_rawStrumTime.resize(0);
			_rawPacked.resize(0);
			_rawSustainLen.resize(0);
			_rawNoteTypeId.resize(0);
			_rawTotal = 0;
			_unspawnIdx = 0;
			return;
		}
		for (i in 0...rem) {
			_rawStrumTime[i] = _rawStrumTime[_unspawnIdx + i];
			_rawPacked[i] = _rawPacked[_unspawnIdx + i];
			_rawSustainLen[i] = _rawSustainLen[_unspawnIdx + i];
			_rawNoteTypeId[i] = _rawNoteTypeId[_unspawnIdx + i];
		}
		_rawStrumTime.resize(rem);
		_rawPacked.resize(rem);
		_rawSustainLen.resize(rem);
		_rawNoteTypeId.resize(rem);
		_rawTotal = rem;
		_unspawnIdx = 0;
	}

	// ── Strums ───────────────────────────────────────────────────────────────
	private var playerStrums:FlxTypedGroup<FlxSprite>;
	private var cpuStrums:FlxTypedGroup<FlxSprite>;
	private var playerStrumsGroup:StrumsGroup;
	private var cpuStrumsGroup:StrumsGroup;
	private var allStrumsGroups:Array<StrumsGroup>;

	public var strumsGroups(get, never):Array<StrumsGroup>;

	inline function get_strumsGroups():Array<StrumsGroup>
		return allStrumsGroups;

	// O(1) strum lookup cache — rebuilt on _rebuildStrumCache()
	private var _playerStrumCache:Map<Int, FlxSprite> = [];
	private var _cpuStrumCache:Map<Int, FlxSprite> = [];
	private var _strumGroupCache:Map<Int, Map<Int, FlxSprite>> = [];

	// ── Renderer ─────────────────────────────────────────────────────────────
	public var renderer:NoteRenderer;

	// ── Config ───────────────────────────────────────────────────────────────
	public var strumLineY:Float = 50;
	public var downscroll:Bool = false;
	public var middlescroll:Bool = false;

	private var songSpeed:Float = 1.0;

	public var modManager:Null<ModChartManager> = null;

	/** Called at end of update(), after note visibility is resolved. Used by ModchartHoldMesh. */
	public var onAfterUpdate:Null<Void->Void> = null;

	private static inline final SPAWN_PAD_PX:Float = 300.0;
	private static inline final EXPIRE_AFTER_MS:Float = 3500.0;

	private var _dynSpawnTime:Float = 1800.0;
	private var _dynCullDist:Float = 2000.0;
	private var _scrollSpeed:Float = 0.45;

	public var scrollSpeed(get, never):Float;

	inline function get_scrollSpeed():Float
		return _scrollSpeed;

	private var _lastSustainSpeed:Float = -1.0;

	public var targetScrollRate:Float = 1.0;

	private var _scrollTransitioning:Bool = false;
	private var _scrollSpeedAtTransStart:Float = 0.45;

	private var _invertTransitioning:Bool = false;
	private var _invertTransTimer:Float = 0.0;

	private static inline final INVERT_LERP_DURATION:Float = 0.18;

	private var _prevGroupInvert:Map<String, Float> = new Map();

	// SaveData cache (refreshed on generateNotes / refreshSaveDataCache)
	private var _cachedNoteSplashes:Bool = false;
	private var _cachedHoldCoverEnabled:Bool = true;
	private var _cachedMiddlescroll:Bool = false;
	private var _noteSplashesEnabled:Bool = true;
	private var _cachedSustainMiss:Bool = false;
	private var _sustainChainMissed:Array<Bool> = [false, false, false, false];
	private var _sustainChainMissedEndTime:Array<Float> = [-1.0, -1.0, -1.0, -1.0];

	public function refreshSaveDataCache():Void {
		_cachedNoteSplashes = SaveData.data.notesplashes == true;
		_cachedMiddlescroll = SaveData.data.middlescroll == true;
		_cachedSustainMiss = SaveData.data.sustainMiss == true;
		final metaHoldCover = PlayState.instance.metaData.holdCoverEnabled;
		_cachedHoldCoverEnabled = metaHoldCover != null ? metaHoldCover : funkin.data.GlobalConfig.instance.holdCoverEnabled;
		final metaSplashes = PlayState.instance.metaData.splashesEnabled;
		_noteSplashesEnabled = metaSplashes != null ? metaSplashes : funkin.data.GlobalConfig.instance.splashesEnabled;
	}

	// ── Callbacks ────────────────────────────────────────────────────────────
	public var onNoteMiss:Note->Void = null;
	public var onCPUNoteHit:Note->Void = null;
	public var onNoteHit:Note->Void = null;
	public var onBotNoteHit:Note->Void = null;

	// ── Hold tracking ─────────────────────────────────────────────────────────
	private var heldNotes:Map<Int, Note> = new Map();
	private var holdStartTimes:Map<Int, Float> = new Map();
	private var holdEndTimes:Map<Int, Float> = new Map();
	private var cpuHoldEndTimes:Array<Float> = [-1, -1, -1, -1];
	private var _cpuHoldGroupIdx:Array<Int> = [0, 0, 0, 0];
	private var _playerHoldGroupIdx:Array<Int> = [0, 0, 0, 0];

	public var playerHeld:Array<Bool> = [false, false, false, false];

	private var _missedHoldDir:Array<Bool> = [false, false, false, false];
	private var _autoReleaseBuffer:Array<Int> = [];
	private var _cpuHeldDirs:Array<Bool> = [false, false, false, false];
	private var _holdCoverSet:haxe.ds.ObjectMap<NoteHoldCover, Bool> = new haxe.ds.ObjectMap();
	private var _sustainClipRect:flixel.math.FlxRect = new flixel.math.FlxRect();

	// Per-frame strum-center cache: key = noteData + groupIdx*4 + mustPress*16, sentinel = NaN
	private static inline final _FRAME_CACHE_SIZE:Int = 128;

	private var _frameCenterYCache:Array<Float> = [for (_ in 0..._FRAME_CACHE_SIZE) Math.NaN];
	private var _frameVisualCenterCache:Array<Float> = [for (_ in 0..._FRAME_CACHE_SIZE) Math.NaN];
	private var _frameModEnabled:Bool = false;
	private var _frameGroupCount:Int = 0;

	// ─────────────────────────────────────────────────────────────────────────

	public function new(notes:FlxTypedGroup<Note>, playerStrums:FlxTypedGroup<FlxSprite>, cpuStrums:FlxTypedGroup<FlxSprite>,
			splashes:FlxTypedGroup<NoteSplash>, holdCovers:FlxTypedGroup<NoteHoldCover>, ?playerStrumsGroup:StrumsGroup, ?cpuStrumsGroup:StrumsGroup,
			?allStrumsGroups:Array<StrumsGroup>, ?sustainNotes:FlxTypedGroup<Note>) {
		this.notes = notes;
		this.sustainNotes = sustainNotes != null ? sustainNotes : notes;
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

	public function _rebuildStrumCache():Void {
		_playerStrumCache.clear();
		_cpuStrumCache.clear();
		_strumGroupCache.clear();

		if (playerStrums != null)
			playerStrums.forEach(s -> _playerStrumCache.set(s.ID, s));
		if (cpuStrums != null)
			cpuStrums.forEach(s -> _cpuStrumCache.set(s.ID, s));

		if (allStrumsGroups != null) {
			for (i in 0...allStrumsGroups.length) {
				final grp = allStrumsGroups[i];
				if (grp == null)
					continue;
				final map:Map<Int, FlxSprite> = [];
				for (dir in 0...4) {
					final s = grp.getStrum(dir);
					if (s != null)
						map.set(dir, s);
				}
				_strumGroupCache.set(i, map);
			}
		}
	}

	/** Build the SOA from SONG data. Zero FlxSprites allocated here. */
	public function generateNotes(SONG:SwagSong):Void {
		_song = SONG;
		_unspawnIdx = 0;
		_prevSpawnedNote.clear();
		songSpeed = SONG.speed;
		_scrollSpeed = 0.45 * FlxMath.roundDecimal(songSpeed, 2);
		_lastSustainSpeed = _scrollSpeed;

		_noteTypeIndex.clear();
		_noteTypeTable.resize(1);
		_noteTypeTable[0] = '';

		refreshSaveDataCache();

		// Pre-count to reserve all four arrays in one shot
		var noteCount:Int = 0;
		for (sec in SONG.notes)
			for (sn in sec.sectionNotes) {
				noteCount++;
				if ((sn[2] : Float) > 0)
					noteCount += Math.floor((sn[2] : Float) / Conductor.stepCrochet);
			}

		_rawStrumTime = [for (_ in 0...noteCount) 0.0];
		_rawPacked = [for (_ in 0...noteCount) 0];
		_rawSustainLen = [for (_ in 0...noteCount) 0.0];
		_rawNoteTypeId = [for (_ in 0...noteCount) 0];
		var wi:Int = 0;

		for (sec in SONG.notes) {
			for (sn in sec.sectionNotes) {
				final daStrumTime:Float = sn[0];
				final rawND:Int = Std.int(sn[1]);
				final daNoteData:Int = rawND % 4;
				final groupIdx:Int = Math.floor(rawND / 4);

				var gottaHit:Bool;
				if (allStrumsGroups != null && groupIdx < allStrumsGroups.length && groupIdx >= 2)
					gottaHit = !allStrumsGroups[groupIdx].isCPU;
				else {
					gottaHit = sec.mustHitSection;
					if (groupIdx == 1)
						gottaHit = !sec.mustHitSection;
				}

				final ntStr:String = (sn.length > 3 && sn[3] != null) ? Std.string(sn[3]) : '';
				final susLen:Float = sn[2];
				final ntId:Int = _internNoteType(ntStr);

				_rawStrumTime[wi] = daStrumTime;
				_rawPacked[wi] = _packNote(daNoteData, false, gottaHit, groupIdx);
				_rawSustainLen[wi] = susLen;
				_rawNoteTypeId[wi] = ntId;
				wi++;

				if (susLen > 0) {
					final floorSus:Int = Math.floor(susLen / Conductor.stepCrochet);
					final packedSus:Int = _packNote(daNoteData, true, gottaHit, groupIdx);
					for (s in 0...floorSus) {
						_rawStrumTime[wi] = daStrumTime + Conductor.stepCrochet * s + Conductor.stepCrochet * 0.5;
						_rawPacked[wi] = packedSus;
						_rawSustainLen[wi] = 0.0;
						_rawNoteTypeId[wi] = ntId;
						wi++;
					}
				}
			}
		}

		// Sort via index permutation, then scatter into fresh arrays
		final idx:Array<Int> = [for (i in 0...wi) i];
		idx.sort((a, b) -> {
			final d = _rawStrumTime[a] - _rawStrumTime[b];
			d < 0 ? -1 : d > 0 ? 1 : 0;
		});
		final st2:Array<Float> = [];
		st2.resize(wi);
		final pk2:Array<Int> = [];
		pk2.resize(wi);
		final sl2:Array<Float> = [];
		sl2.resize(wi);
		final nt2:Array<Int> = [];
		nt2.resize(wi);
		for (i in 0...wi) {
			final si = idx[i];
			st2[i] = _rawStrumTime[si];
			pk2[i] = _rawPacked[si];
			sl2[i] = _rawSustainLen[si];
			nt2[i] = _rawNoteTypeId[si];
		}
		_rawStrumTime = st2;
		_rawPacked = pk2;
		_rawSustainLen = sl2;
		_rawNoteTypeId = nt2;
		_rawTotal = wi;

		trace('[NoteManager] $_rawTotal notes queued (SOA, ${_noteTypeTable.length} types)');
	}

	public function update(songPosition:Float):Void {
		// ── Scroll speed lerp ─────────────────────────────────────────────────
		final targetSpeed:Float = 0.45 * FlxMath.roundDecimal(songSpeed * targetScrollRate, 2);
		final speedDiff:Float = targetSpeed - _scrollSpeed;
		if (Math.abs(speedDiff) > 0.0005) {
			final rawEl = FlxG.elapsed / (FlxG.timeScale > 0 ? FlxG.timeScale : 1.0);
			_scrollSpeed += speedDiff * Math.min(1.0, rawEl * 12.0);
			if (!_scrollTransitioning) {
				_scrollTransitioning = true;
				_scrollSpeedAtTransStart = _scrollSpeed;
				for (n in sustainNotes.members)
					if (n != null && n.alive) {
						n._lerpFromY = n.y;
						n._lerpFromScaleY = n.scale.y;
						n._lerpT = 0.0;
					}
				if (sustainNotes != notes)
					for (n in notes.members)
						if (n != null && n.alive) {
							n._lerpFromY = n.y;
							n._lerpFromScaleY = n.scale.y;
							n._lerpT = 0.0;
						}
			}
		} else {
			_scrollSpeed = targetSpeed;
			_scrollTransitioning = false;
		}

		_dynSpawnTime = Math.max(600.0, (FlxG.height + SPAWN_PAD_PX) / Math.max(_scrollSpeed, 0.005));

		// ── Invert transition timer ───────────────────────────────────────────
		if (_invertTransTimer > 0.0) {
			_invertTransTimer -= FlxG.elapsed / (FlxG.timeScale > 0 ? FlxG.timeScale : 1.0);
			if (_invertTransTimer <= 0.0) {
				_invertTransTimer = 0.0;
				_invertTransitioning = false;
			}
		}

		// ── Dynamic cull distance ─────────────────────────────────────────────
		final modExtra:Float = (modManager != null && modManager.enabled) ? FlxG.height : 0.0;
		var maxStrumDev:Float = 0.0;
		if (modManager != null && modManager.enabled && allStrumsGroups != null) {
			for (cg in allStrumsGroups)
				for (ci in 0...4) {
					final cs = cg.getStrum(ci);
					if (cs != null) {
						final d = Math.abs(cs.y - strumLineY);
						if (d > maxStrumDev)
							maxStrumDev = d;
					}
				}
		}
		_dynCullDist = FlxG.height + SPAWN_PAD_PX + modExtra + maxStrumDev;

		spawnNotes(songPosition);
		updateActiveNotes(songPosition);
		updateStrumAnimations();
		autoReleaseFinishedHolds();

		if (renderer != null)
			_updateHoldCoverPositions();
		if (onAfterUpdate != null)
			onAfterUpdate();
		if (renderer != null) {
			renderer.updateBatcher();
			renderer.updateHoldCovers();
		}
	}

	private function autoReleaseFinishedHolds():Void {
		final songPos = Conductor.songPosition;

		// Player
		if (heldNotes.keys().hasNext()) {
			_autoReleaseBuffer.resize(0);
			for (dir in heldNotes.keys()) {
				final release = holdEndTimes.exists(dir) ? songPos >= holdEndTimes.get(dir) : !_hasPendingSustain(dir, true, sustainNotes.members,
					sustainNotes.members.length);
				if (release)
					_autoReleaseBuffer.push(dir);
			}
			for (dir in _autoReleaseBuffer)
				releaseHoldNote(dir);
		}

		// CPU
		for (dir in 0...4) {
			if (!_cpuHeldDirs[dir])
				continue;
			final release = cpuHoldEndTimes[dir] >= 0 ? songPos >= cpuHoldEndTimes[dir] : !_hasPendingSustain(dir, false, sustainNotes.members,
				sustainNotes.members.length);
			if (release) {
				if (renderer != null)
					renderer.stopHoldCover(dir, false, _cpuHoldGroupIdx[dir]);
				_cpuHeldDirs[dir] = false;
				cpuHoldEndTimes[dir] = -1;
				_cpuHoldGroupIdx[dir] = 0;
			}
		}
	}

	private function _hasPendingSustain(dir:Int, isPlayer:Bool, members:Array<Note>, len:Int):Bool {
		for (i in 0...len) {
			final n = members[i];
			if (n != null && n.alive && n.isSustainNote && n.noteData == dir && n.mustPress == isPlayer && !n.wasGoodHit && !n.tooLate)
				return true;
		}
		for (i in _unspawnIdx..._rawTotal) {
			final pk = _rawPacked[i];
			if (_pNoteData(pk) == dir && _pMustHit(pk) == isPlayer) {
				if (_pIsSustain(pk))
					return true;
				break; // head note — this hold chain is done
			}
		}
		return false;
	}

	private function spawnNotes(songPosition:Float):Void {
		while (_unspawnIdx < _rawTotal && _rawStrumTime[_unspawnIdx] - songPosition < _dynSpawnTime) {
			final i = _unspawnIdx++;
			final rawST = _rawStrumTime[i];
			final rawPK = _rawPacked[i];
			final rawSL = _rawSustainLen[i];
			final rawND = _pNoteData(rawPK);
			final rawIS = _pIsSustain(rawPK);
			final rawMH = _pMustHit(rawPK);
			final rawGI = _pGroupIdx(rawPK);
			final rawNT = _noteTypeTable[_rawNoteTypeId[i]];

			var groupSkin:String = null;
			if (allStrumsGroups != null && rawGI < allStrumsGroups.length)
				groupSkin = allStrumsGroups[rawGI].data.noteSkin;

			final pnKey = _prevNoteKey(rawND, rawGI, rawMH);
			final note = renderer.getNote(rawST, rawND, _prevSpawnedNote.get(pnKey), rawIS, rawMH, groupSkin, rawGI);
			note.strumsGroupIndex = rawGI;
			note.noteType = rawNT;
			note.sustainLength = rawSL;
			note.visible = true;
			note.active = true;
			note.alpha = rawIS ? 0.6 : 1.0;

			// sustainMiss: mark born-dead only for the currently-penalised chain
			if (_cachedSustainMiss
				&& rawIS
				&& rawMH
				&& _sustainChainMissed[rawND]
				&& (_sustainChainMissedEndTime[rawND] < 0 || rawST <= _sustainChainMissedEndTime[rawND] + Conductor.stepCrochet)) {
				note.tooLate = true;
				note.alpha = 0.3;
			}

			_prevSpawnedNote.set(pnKey, note);

			// Look ahead to decide body vs tail cap
			if (rawIS) {
				final stepTol:Float = Conductor.stepCrochet * 1.5;
				var isBody = false;
				var si = _unspawnIdx;
				while (si < _rawTotal) {
					if (_rawStrumTime[si] - rawST > stepTol)
						break;
					final spk = _rawPacked[si];
					if (_pIsSustain(spk) && _pNoteData(spk) == rawND && _pGroupIdx(spk) == rawGI) {
						isBody = true;
						break;
					}
					si++;
				}
				if (isBody)
					note.confirmHoldPiece();
			}

			if (rawIS)
				sustainNotes.add(note);
			else
				notes.add(note);
		}

		if (_unspawnIdx > 0 && (_unspawnIdx % RAW_TRIM_CHUNK) == 0)
			_trimRawArrays();
	}

	private function updateActiveNotes(songPosition:Float):Void {
		final hitWindow:Float = Conductor.safeZoneOffset;

		if (_scrollSpeed != _lastSustainSpeed) {
			_lastSustainSpeed = _scrollSpeed;
			_recalcAllSustainScales();
		}

		_frameModEnabled = modManager != null && modManager.enabled;
		_frameGroupCount = allStrumsGroups != null ? allStrumsGroups.length : 0;

		for (ci in 0..._FRAME_CACHE_SIZE) {
			_frameCenterYCache[ci] = Math.NaN;
			_frameVisualCenterCache[ci] = Math.NaN;
		}
		_missedHoldDir[0] = _missedHoldDir[1] = _missedHoldDir[2] = _missedHoldDir[3] = false;

		// Detect INVERT state flip per group and seed note lerp start positions
		if (_frameModEnabled && allStrumsGroups != null) {
			for (group in allStrumsGroups) {
				final st0 = modManager.getState(group.id, 0);
				final curInv:Float = st0 != null ? st0.invert : 0.0;
				final prevInv:Float = _prevGroupInvert.exists(group.id) ? _prevGroupInvert.get(group.id) : 0.0;
				if ((curInv > 0.5) != (prevInv > 0.5)) {
					_invertTransitioning = true;
					_invertTransTimer = INVERT_LERP_DURATION;
					_seedLerpForGroup(sustainNotes.members, group.id);
					if (sustainNotes != notes)
						_seedLerpForGroup(notes.members, group.id);
				}
				_prevGroupInvert.set(group.id, curInv);
			}
		}

		_updateNoteGroup(sustainNotes.members, sustainNotes.members.length, songPosition, hitWindow);
		if (sustainNotes != notes)
			_updateNoteGroup(notes.members, notes.members.length, songPosition, hitWindow);
	}

	private inline function _seedLerpForGroup(members:Array<Note>, gid:String):Void {
		for (note in members) {
			if (note == null || !note.alive)
				continue;
			final nGid = (note.strumsGroupIndex >= 2
				&& note.strumsGroupIndex < _frameGroupCount) ? allStrumsGroups[note.strumsGroupIndex].id : (note.mustPress ? "player" : "cpu");
			if (nGid != gid)
				continue;
			note._lerpFromY = note.y;
			note._lerpFromScaleY = note.scale.y;
			note._lerpT = 0.0;
		}
	}

	private inline function _updateNoteGroup(members:Array<Note>, len:Int, songPosition:Float, hitWindow:Float):Void {
		var i:Int = len;
		while (i > 0) {
			i--;
			final note = members[i];
			if (note == null || !note.alive)
				continue;

			// FIX: CPU hit BEFORE updateNotePosition so wasGoodHit=true when clipRect is evaluated,
			// preventing sustains from flashing 1 frame above the strum line on their hit frame.
			if (!note.mustPress && note.strumTime <= songPosition && !(note.isSustainNote && note.wasGoodHit)) {
				handleCPUNote(note);
				if (!note.isSustainNote)
					continue;
			}

			updateNotePosition(note, songPosition);

			if (note.mustPress) {
				final hw = note.isSustainNote ? hitWindow * 1.05 : hitWindow;
				note.canBeHit = note.strumTime > songPosition - hw && note.strumTime < songPosition + hw;
			}

			// Bot play
			if (note.mustPress && funkin.gameplay.PlayState.isBotPlay && note.strumTime <= songPosition && !note.wasGoodHit) {
				handleBotNote(note);
				if (!note.isSustainNote)
					continue;
			}

			// Human player misses
			if (note.mustPress && !note.wasGoodHit && !funkin.gameplay.PlayState.isBotPlay) {
				if (note.isSustainNote) {
					if (note.tooLate) {
						continue;
					}
					if (songPosition > note.strumTime + hitWindow) {
						final dir = note.noteData;
						if (playerHeld[dir]) {
							note.wasGoodHit = true;
							handleSustainNoteHit(note);
						} else {
							note.tooLate = true;
							note.alpha = _cachedSustainMiss ? 0.3 : 0.2;
							if (heldNotes.exists(dir))
								releaseHoldNote(dir);
							if (_cachedSustainMiss) {
								if (!_sustainChainMissed[dir]) {
									_sustainChainMissed[dir] = true;
									_markSustainChainMissed(dir, note.strumsGroupIndex, note.mustPress);
									if (onNoteMiss != null)
										onNoteMiss(note);
								}
							} else if (!_missedHoldDir[dir]) {
								_missedHoldDir[dir] = true;
								if (onNoteMiss != null)
									onNoteMiss(note);
							}
						}
					}
					continue;
				}

				if (note.tooLate || songPosition > note.strumTime + hitWindow) {
					if (!note.tooLate)
						missNote(note);
					continue;
				}
			}

			// Culling
			final offscreen = note.y < -_dynCullDist || note.y > FlxG.height + _dynCullDist;
			final done = (note.isSustainNote && note.wasGoodHit) || note.tooLate;
			final expired = (Conductor.songPosition - note.strumTime) > EXPIRE_AFTER_MS;
			final modWasHit = _frameModEnabled && note.isSustainNote && note.wasGoodHit;

			if (done && ((!modWasHit && offscreen) || expired)) {
				removeNote(note);
				continue;
			}

			if (offscreen && !modWasHit)
				note.visible = false;
			else if (!offscreen) {
				note.visible = true;
				if (!note.mustPress && middlescroll)
					note.alpha = 0;
			}
		}
	}

	private function handleCPUNote(note:Note):Void {
		note.wasGoodHit = true;
		if (onCPUNoteHit != null)
			onCPUNoteHit(note);
		handleStrumAnimation(note.noteData, note.strumsGroupIndex, false);

		if (!note.isSustainNote && note.sustainLength > 0) {
			final newEnd = note.strumTime + note.sustainLength - SaveData.data.offset;
			cpuHoldEndTimes[note.noteData] = cpuHoldEndTimes[note.noteData] < 0 ? newEnd : Math.max(cpuHoldEndTimes[note.noteData], newEnd);
		}

		if (note.isSustainNote && !_cachedMiddlescroll && _cachedNoteSplashes && renderer != null) {
			final dir = note.noteData;
			if (!_cpuHeldDirs[dir]) {
				_cpuHeldDirs[dir] = true;
				_cpuHoldGroupIdx[dir] = note.strumsGroupIndex;
				final strum = getStrumForDirection(dir, note.strumsGroupIndex, false);
				if (strum != null && _cachedHoldCoverEnabled) {
					final cx = strum.x - strum.offset.x + strum.frameWidth * strum.scale.x * 0.5;
					final cy = strum.y - strum.offset.y + strum.frameHeight * strum.scale.y * 0.5;
					final cover = renderer.startHoldCover(dir, cx, cy, false, note.strumsGroupIndex, NoteTypeManager.getHoldSplashName(note.noteType));
					if (cover != null && !_holdCoverSet.exists(cover) && holdCovers.members.indexOf(cover) < 0) {
						_holdCoverSet.set(cover, true);
						holdCovers.add(cover);
					}
				}
			}
		}
		if (!note.isSustainNote)
			removeNote(note);
	}

	private function handleBotNote(note:Note):Void {
		if (onBotNoteHit != null)
			onBotNoteHit(note);
	}

	private function updateStrumAnimations():Void {
		_resetStrumsGroup(cpuStrums);
		_resetStrumsGroup(playerStrums);
	}

	private static inline function _resetStrumsGroup(group:FlxTypedGroup<FlxSprite>):Void {
		if (group == null)
			return;
		final members = group.members;
		for (i in 0...members.length) {
			final strum = members[i];
			if (strum == null || !strum.alive)
				continue;
			final sn = cast(strum, StrumNote);
			if (sn == null)
				continue;
			final anim = sn.animation.curAnim;
			if (anim != null
				&& anim.finished
				&& anim.name.length >= 7
				&& anim.name.charCodeAt(0) == 99
				&& anim.name.startsWith('confirm'))
				sn.playAnim('static');
		}
	}

	private function _recalcAllSustainScales():Void {
		final conductor = funkin.data.Conductor;
		if (conductor.stepCrochet <= 0)
			return;

		inline function calcScaleY(note:Note):Float {
			if (note.frameHeight <= 0)
				return note.sustainBaseScaleY;
			final effSpeed = _scrollSpeed / 0.45;
			final extra = effSpeed > 3.0 ? (effSpeed - 3.0) * 0.02 : 0.0;
			return (conductor.stepCrochet * _scrollSpeed * (note._skinHoldStretch + extra)) / note.frameHeight;
		}

		for (note in sustainNotes.members) {
			if (note == null || !note.alive || !note.isSustainNote)
				continue;
			final newSY = calcScaleY(note);
			if (newSY <= 0 || newSY == note.sustainBaseScaleY)
				continue;
			if (_scrollTransitioning) {
				if (note._lerpFromScaleY < 0.0)
					note._lerpFromScaleY = note.scale.y;
			} else {
				note.scale.y = newSY;
				note.updateHitbox();
				note.offset.x += note.noteOffsetX;
				note.offset.y += note.noteOffsetY;
			}
			note.sustainBaseScaleY = newSY;
		}
	}

	private function handleStrumAnimation(noteData:Int, groupIndex:Int, isPlayer:Bool):Void {
		final strum = getStrumForDirection(noteData, groupIndex, isPlayer);
		if (strum != null) {
			final sn = cast(strum, StrumNote);
			if (sn != null)
				sn.playAnim('confirm', true);
		}
	}

	private function updateNotePosition(note:Note, songPosition:Float):Void {
		// Middlescroll: CPU notes are always invisible — skip all calculations
		if (_cachedMiddlescroll && !note.mustPress) {
			note.visible = false;
			note.clipRect = null;
			return;
		}

		final strum = getStrumForDirection(note.noteData, note.strumsGroupIndex, note.mustPress);

		// Strum center cache (per frame, per strum): key = noteData + groupIdx*4 + mustPress*16
		final cKey:Int = note.noteData + note.strumsGroupIndex * 4 + (note.mustPress ? 0 : 16);

		var strumCY:Float = _frameCenterYCache[cKey];
		if (Math.isNaN(strumCY)) {
			final sn = strum != null ? Std.downcast(strum, StrumNote) : null;
			strumCY = sn != null ? sn.logicalY : (strum != null ? strum.y : strumLineY);
			_frameCenterYCache[cKey] = strumCY;
		}

		var visualCenter:Float = _frameVisualCenterCache[cKey];
		if (Math.isNaN(visualCenter)) {
			visualCenter = strumCY - strum.offset.y + strum.height / 2;
			_frameVisualCenterCache[cKey] = visualCenter;
		}

		// Mod state
		var ms:funkin.gameplay.modchart.StrumState = null;
		var ngid:String = note.mustPress ? "player" : "cpu";
		if (_frameModEnabled) {
			if (note.strumsGroupIndex >= 2 && note.strumsGroupIndex < _frameGroupCount)
				ngid = allStrumsGroups[note.strumsGroupIndex].id;
			ms = modManager.getState(ngid, note.noteData);
		}

		final scrollMult:Float = ms != null ? ms.scrollMult : 1.0;
		final effDown:Bool = downscroll != (ms != null && ms.invert > 0.5);
		final effSpeed:Float = _scrollSpeed * scrollMult;

		// Base Y
		var noteY:Float = effDown ? strumCY + (songPosition - note.strumTime) * effSpeed : strumCY - (songPosition - note.strumTime) * effSpeed;

		// Y modifiers
		if (ms != null) {
			noteY += ms.noteOffsetY;
			if (ms.drunkY != 0)
				noteY += ms.drunkY * Math.sin(note.strumTime * 0.001 * ms.drunkFreq + songPosition * 0.0008);
			if (ms.bumpy != 0)
				noteY += ms.bumpy * Math.sin(songPosition * 0.001 * ms.bumpySpeed);
			if (ms.wave != 0)
				noteY += ms.wave * Math.sin(songPosition * 0.001 * ms.waveSpeed - note.strumTime * 0.001);
		}

		// Speed/invert transition lerp
		if ((_scrollTransitioning || _invertTransitioning) && note._lerpFromY >= 0.0 && note._lerpT < 1.0) {
			final rawEl = FlxG.elapsed / (FlxG.timeScale > 0 ? FlxG.timeScale : 1.0);
			note._lerpT = Math.min(1.0, note._lerpT + rawEl * 12.0);
			noteY = note._lerpFromY + (noteY - note._lerpFromY) * FlxEase.quartOut(note._lerpT);
		}

		if (!note.isSustainNote)
			note.y = noteY;

		if (strum != null) {
			var baseAngle:Float = strum.angle;
			if (ms != null) {
				baseAngle += ms.confusion;
				if (ms.tornado != 0)
					baseAngle += ms.tornado * Math.sin(note.strumTime * 0.001 * ms.drunkFreq);
			}

			if (!note.isSustainNote) {
				note.angle = baseAngle + (effDown ? 180.0 : 0.0);
				note.flipX = effDown;
				note.flipY = effDown;
			}

			// Scale X (beat pulse + 3D rotY)
			var newSX = strum.scale.x;
			final newSY = note.isSustainNote ? note.sustainBaseScaleY : strum.scale.y;
			if (ms != null && ms._beatPulse > 0)
				newSX *= 1.0 + ms._beatPulse;

			if (ms != null && (ms.rotX != 0 || ms.rotY != 0)) {
				final cosX = Math.cos(ms.rotX * Math.PI / 180.0);
				final cosY = Math.cos(ms.rotY * Math.PI / 180.0);
				newSX = newSX * Math.abs(cosY);
				if (!note.isSustainNote) {
					note.scale.y = newSY * Math.abs(cosX);
					if (cosY < 0)
						note.flipX = !note.flipX;
					if (cosX < 0)
						note.flipY = !note.flipY;
				} else if (cosY < 0)
					note.flipX = !note.flipX;
			}

			final scaleChanged = Math.abs(note.scale.x - newSX) > 0.001 || Math.abs(note.scale.y - newSY) > 0.001;
			note.scale.x = newSX;
			note.scale.y = newSY;
			if (scaleChanged) {
				note.updateHitbox();
				note.offset.x += note.noteOffsetX;
				note.offset.y += note.noteOffsetY;
			}

			// Alpha
			var baseAlpha:Float = FlxMath.bound(strum.alpha, 0.05, 1.0);
			if (ms != null) {
				baseAlpha *= FlxMath.bound(ms.noteAlpha, 0.0, 1.0);
				if (ms.stealth > 0.5)
					baseAlpha = 0.0;
			}
			note.alpha = note.tooLate ? (note.isSustainNote ? (_cachedSustainMiss ? 0.3 : 0.2) : 0.3) : baseAlpha;

			// X position
			final snCast = Std.downcast(strum, StrumNote);
			final logStrX = snCast != null ? snCast.logicalX : strum.x;
			var noteX:Float = logStrX + (strum.width - note.width) / 2;
			if (ms != null) {
				noteX += ms.noteOffsetX;
				if (ms.drunkX != 0)
					noteX += ms.drunkX * Math.sin(note.strumTime * 0.001 * ms.drunkFreq + songPosition * 0.0008);
				if (ms.tipsy != 0)
					noteX += ms.tipsy * Math.sin(songPosition * 0.001 * ms.tipsySpeed);
				if (ms.zigzag != 0) {
					final zz = Math.sin(note.strumTime * 0.001 * ms.zigzagFreq * Math.PI);
					noteX += ms.zigzag * (zz >= 0 ? 1.0 : -1.0);
				}
				if (ms.flipX > 0.5) {
					final sc = logStrX + strum.width / 2;
					noteX = sc - (noteX - sc + note.width / 2) - note.width / 2;
				}
			}
			note.x = noteX;

			if (note.isSustainNote) {
				note.flipX = false;
				note.flipY = note.isTailCap && effDown;

				// Snake angle + Euclidean scale: evaluate next-piece position
				final nextST:Float = note.strumTime + Conductor.stepCrochet;
				var nextY:Float = effDown ? strumCY + (songPosition - nextST) * effSpeed : strumCY - (songPosition - nextST) * effSpeed;
				if (ms != null) {
					nextY += ms.noteOffsetY;
					if (ms.drunkY != 0)
						nextY += ms.drunkY * Math.sin(nextST * 0.001 * ms.drunkFreq + songPosition * 0.0008);
					if (ms.bumpy != 0)
						nextY += ms.bumpy * Math.sin(songPosition * 0.001 * ms.bumpySpeed);
					if (ms.wave != 0)
						nextY += ms.wave * Math.sin(songPosition * 0.001 * ms.waveSpeed - nextST * 0.001);
				}
				var nextX:Float = logStrX + (strum.width - note.width) / 2;
				if (ms != null) {
					nextX += ms.noteOffsetX;
					if (ms.drunkX != 0)
						nextX += ms.drunkX * Math.sin(nextST * 0.001 * ms.drunkFreq + songPosition * 0.0008);
					if (ms.tipsy != 0)
						nextX += ms.tipsy * Math.sin(songPosition * 0.001 * ms.tipsySpeed);
					if (ms.zigzag != 0) {
						final zzN = Math.sin(nextST * 0.001 * ms.zigzagFreq * Math.PI);
						nextX += ms.zigzag * (zzN >= 0 ? 1.0 : -1.0);
					}
					if (ms.flipX > 0.5) {
						final sc = logStrX + strum.width / 2;
						nextX = sc - (nextX - sc + note.width / 2) - note.width / 2;
					}
				}

				final dX = nextX - note.x;
				final dY = nextY - noteY;
				note.angle = baseAngle + (Math.atan2(dY, dX) * (180.0 / Math.PI) - 90.0);

				if (!note.isTailCap) {
					final absX = dX < 0 ? -dX : dX;
					final dist = absX < 0.5 ? (dY < 0 ? -dY : dY) : Math.sqrt(dX * dX + dY * dY);
					note.scale.y = (dist + 2.0) / (note.frameHeight > 0 ? note.frameHeight : 1.0);
				}
			}
		}

		// Sustain Y + lerp
		if (note.isSustainNote) {
			if ((_scrollTransitioning || _invertTransitioning) && note._lerpFromY >= 0.0 && note._lerpT < 1.0) {
				final easedT = FlxEase.quartOut(note._lerpT);
				noteY = note._lerpFromY + (noteY - note._lerpFromY) * easedT;
				if (note._lerpFromScaleY > 0.0)
					note.scale.y = note._lerpFromScaleY + (note.sustainBaseScaleY - note._lerpFromScaleY) * easedT;
			}
			final vh:Float = (note.frameHeight > 0 ? note.frameHeight : 1.0) * note.scale.y;
			note.y = effDown ? noteY - vh : noteY;
		}

		// Modchart note position hook
		if (_frameModEnabled && modManager.hasNotePositionHook) {
			final ctx = modManager.noteCtx;
			ctx.noteData = note.noteData;
			ctx.strumTime = note.strumTime;
			ctx.songPosition = songPosition;
			ctx.beat = modManager.currentBeat;
			ctx.isPlayer = note.mustPress;
			ctx.isSustain = note.isSustainNote;
			ctx.groupId = ngid;
			ctx.scrollMult = ms != null ? ms.scrollMult : 1.0;
			ctx.x = note.x;
			ctx.y = note.y;
			ctx.angle = note.angle;
			ctx.alpha = note.alpha;
			ctx.scaleY = note.scale.y;
			ctx.scaleX = note.scale.x;
			ctx.rotX = ms != null ? ms.rotX : 0.0;
			ctx.rotY = ms != null ? ms.rotY : 0.0;
			ctx.flipX = note.isSustainNote ? false : note.flipX;
			ctx.flipY = note.flipY;
			modManager.callNotePositionHook(ctx);
			note.x = ctx.x;
			note.y = ctx.y;
			note.angle = ctx.angle;
			note.alpha = ctx.alpha;
			if (note.isSustainNote && ctx.scaleY != note.scale.y)
				note.scale.y = ctx.scaleY;
			if (Math.abs(note.scale.x - ctx.scaleX) > 0.001) {
				note.scale.x = ctx.scaleX;
				note.updateHitbox();
				note.offset.x += note.noteOffsetX;
				note.offset.y += note.noteOffsetY;
			}
			if (!note.isSustainNote) {
				note.flipX = ctx.flipX;
				note.flipY = ctx.flipY;
			} else if (note.isTailCap)
				note.flipY = ctx.flipY;
		}

		// ClipRect for hit sustains
		if (note.isSustainNote) {
			if (note.tooLate) {
				note.clipRect = null;
			} else if (note.wasGoodHit) {
				final halfStrum = funkin.gameplay.notes.Note.swagWidth * 0.5;
				final thresh = effDown ? strumCY - halfStrum : strumCY + halfStrum;

				if (effDown) {
					if (note.y + note.height >= thresh) {
						final clipH = (thresh - note.y) / note.scale.y;
						if (clipH <= 0) {
							note.clipRect = null;
							note.visible = false;
							removeNote(note);
						} else {
							_sustainClipRect.set(0, note.frameHeight - clipH, note.width * 2, clipH);
							if (note.clipRect == null)
								note.clipRect = new flixel.math.FlxRect();
							note.clipRect.copyFrom(_sustainClipRect);
							note.clipRect = note.clipRect;
						}
					} else
						note.clipRect = null;
				} else {
					if (note.y < thresh) {
						final clipY = (thresh - note.y) / note.scale.y;
						final clipH = note.frameHeight - clipY;
						if (clipH > 0 && clipY >= 0) {
							_sustainClipRect.set(0, clipY, note.width * 2, clipH);
							if (note.clipRect == null)
								note.clipRect = new flixel.math.FlxRect();
							note.clipRect.copyFrom(_sustainClipRect);
							note.clipRect = note.clipRect;
						} else {
							if (note.wasGoodHit) {
								note.visible = false;
								removeNote(note);
							}
							note.clipRect = null;
						}
					} else
						note.clipRect = null;
				}
			} else
				note.clipRect = null;
		}
	}

	private function removeNote(note:Note):Void {
		note.kill();
		if (note.isSustainNote && sustainNotes != notes)
			sustainNotes.remove(note, true);
		else
			notes.remove(note, true);
		if (renderer != null)
			renderer.recycleNote(note);
	}

	public function hitNote(note:Note, rating:String):Void {
		if (note.wasGoodHit)
			return;
		note.wasGoodHit = true;
		handleStrumAnimation(note.noteData, note.strumsGroupIndex, true);

		if (!note.isSustainNote) {
			_sustainChainMissed[note.noteData] = false;
			_sustainChainMissedEndTime[note.noteData] = -1.0;
		}

		if (!note.isSustainNote && note.sustainLength > 0) {
			final newEnd = note.strumTime + note.sustainLength - SaveData.data.offset;
			holdEndTimes.set(note.noteData, holdEndTimes.exists(note.noteData) ? Math.max(holdEndTimes.get(note.noteData), newEnd) : newEnd);
		}

		if (rating == "sick") {
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

	private function handleSustainNoteHit(note:Note):Void {
		final dir = note.noteData;
		if (!heldNotes.exists(dir)) {
			heldNotes.set(dir, note);
			holdStartTimes.set(dir, Conductor.songPosition);

			if (!holdEndTimes.exists(dir)) {
				// Find chain end across spawned and unspawned notes
				var chainEnd:Float = note.strumTime - SaveData.data.offset;
				final sm = sustainNotes.members;
				for (si in 0...sm.length) {
					final sn = sm[si];
					if (sn == null || !sn.alive || !sn.isSustainNote || sn.noteData != dir || sn.mustPress != note.mustPress)
						continue;
					final rawT = sn.strumTime - SaveData.data.offset;
					if (rawT > chainEnd)
						chainEnd = rawT;
				}
				final gapThresh:Float = Conductor.stepCrochet * 2.0;
				for (ui in _unspawnIdx..._rawTotal) {
					if (_rawStrumTime[ui] > chainEnd + gapThresh)
						break;
					final pk = _rawPacked[ui];
					if (_pIsSustain(pk) && _pNoteData(pk) == dir && _pMustHit(pk) == note.mustPress)
						chainEnd = _rawStrumTime[ui];
				}
				holdEndTimes.set(dir, chainEnd + Conductor.stepCrochet);
				trace('[NoteManager] holdEndTime dir=$dir → ${holdEndTimes.get(dir)}ms');
			}

			if (_cachedNoteSplashes && _cachedHoldCoverEnabled && renderer != null) {
				final strum = getStrumForDirection(dir, note.strumsGroupIndex, true);
				if (strum != null) {
					_playerHoldGroupIdx[dir] = note.strumsGroupIndex;
					final cx = strum.x - strum.offset.x + strum.frameWidth * strum.scale.x * 0.5;
					final cy = strum.y - strum.offset.y + strum.frameHeight * strum.scale.y * 0.5;
					final cover = renderer.startHoldCover(dir, cx, cy, true, note.strumsGroupIndex, NoteTypeManager.getHoldSplashName(note.noteType));
					if (cover != null && !_holdCoverSet.exists(cover) && holdCovers.members.indexOf(cover) < 0) {
						_holdCoverSet.set(cover, true);
						holdCovers.add(cover);
					}
				}
			}
		}
	}

	public function releaseHoldNote(direction:Int):Void {
		if (!heldNotes.exists(direction))
			return;
		if (renderer != null)
			renderer.stopHoldCover(direction, true, _playerHoldGroupIdx[direction]);
		heldNotes.remove(direction);
		holdStartTimes.remove(direction);
		holdEndTimes.remove(direction);
	}

	private function createNormalSplash(note:Note, isPlayer:Bool):Void {
		if (renderer == null)
			return;
		final strum = getStrumForDirection(note.noteData, note.strumsGroupIndex, isPlayer);
		if (strum != null) {
			final splash = renderer.spawnSplash(strum.x - strum.offset.x, strum.y - strum.offset.y, note.noteData,
				NoteTypeManager.getSplashName(note.noteType));
			if (splash != null)
				splashes.add(splash);
		}
	}

	public inline function getStrumForDir(direction:Int, strumsGroupIndex:Int, isPlayer:Bool):FlxSprite
		return getStrumForDirection(direction, strumsGroupIndex, isPlayer);

	private function getStrumForDirection(direction:Int, strumsGroupIndex:Int, isPlayer:Bool):FlxSprite {
		if (allStrumsGroups != null && allStrumsGroups.length > 0 && strumsGroupIndex >= 2) {
			final gm = _strumGroupCache.get(strumsGroupIndex);
			if (gm != null)
				return gm.get(direction);
		}
		return isPlayer ? _playerStrumCache.get(direction) : _cpuStrumCache.get(direction);
	}

	/** Mark all sustain pieces of the current chain as tooLate (sustainMiss mode).
	 *  Two-pass over the live group — no intermediate Array allocation. */
	private function _markSustainChainMissed(dir:Int, strumsGroupIndex:Int, mustPress:Bool):Void {
		final sm = sustainNotes.members;
		final slen = sm.length;
		final gap = Conductor.stepCrochet * 2.0;

		// Pass 1: find chainEnd using a fixpoint-extension scan.
		// Notes are stored in approximately ascending strumTime (spawn order),
		// so the while loop typically only iterates twice.
		var chainEnd:Float = -1.0;
		var extended = true;
		while (extended) {
			extended = false;
			for (i in 0...slen) {
				final n = sm[i];
				if (n == null || !n.alive || !n.isSustainNote || n.noteData != dir || n.wasGoodHit || n.tooLate)
					continue;
				if (n.mustPress != mustPress || n.strumsGroupIndex != strumsGroupIndex)
					continue;
				if (chainEnd < 0 || (n.strumTime > chainEnd && n.strumTime <= chainEnd + gap)) {
					chainEnd = n.strumTime;
					extended = true;
				}
			}
		}

		if (chainEnd < 0) {
			_sustainChainMissedEndTime[dir] = -1.0;
			return;
		}
		_sustainChainMissedEndTime[dir] = chainEnd;

		// Pass 2: mark
		for (i in 0...slen) {
			final n = sm[i];
			if (n == null || !n.alive || !n.isSustainNote || n.noteData != dir || n.wasGoodHit || n.tooLate)
				continue;
			if (n.mustPress != mustPress || n.strumsGroupIndex != strumsGroupIndex)
				continue;
			if (n.strumTime > chainEnd + gap)
				continue;
			n.tooLate = true;
			n.alpha = 0.3;
		}
	}

	public function missNote(note:Note):Void {
		if (note == null || note.wasGoodHit)
			return;
		if (heldNotes.exists(note.noteData))
			releaseHoldNote(note.noteData);
		if (onNoteMiss != null && !note.isSustainNote)
			onNoteMiss(note);
		note.tooLate = true;
		note.alpha = 0.3;
	}

	// ── Rewind ───────────────────────────────────────────────────────────────

	public function updatePositionsForRewind(songPosition:Float):Void {
		_frameModEnabled = modManager != null && modManager.enabled;
		_frameGroupCount = allStrumsGroups != null ? allStrumsGroups.length : 0;
		_rewindUpdateGroup(sustainNotes.members, sustainNotes.members.length, songPosition);
		if (sustainNotes != notes)
			_rewindUpdateGroup(notes.members, notes.members.length, songPosition);
		if (renderer != null)
			renderer.updateBatcher();
	}

	private inline function _rewindUpdateGroup(members:Array<Note>, len:Int, songPosition:Float):Void {
		for (i in 0...len) {
			final note = members[i];
			if (note == null || !note.alive)
				continue;
			updateNotePosition(note, songPosition);
			note.visible = !(note.y < -_dynCullDist || note.y > FlxG.height + _dynCullDist);
		}
	}

	public function rewindTo(targetTime:Float):Void {
		if (_song != null)
			generateNotes(_song);

		if (sustainNotes != notes) {
			var i = sustainNotes.members.length - 1;
			while (i >= 0) {
				final n = sustainNotes.members[i];
				if (n != null && n.alive)
					removeNote(n);
				i--;
			}
		}
		var i = notes.members.length - 1;
		while (i >= 0) {
			final n = notes.members[i];
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
		if (renderer != null)
			renderer.clearPools();

		final baseSpeed = Math.max(0.45 * songSpeed, 0.005);
		final spawnWin = Math.max(600.0, (FlxG.height + SPAWN_PAD_PX) / baseSpeed);
		_unspawnIdx = 0;
		final cutoff = targetTime - spawnWin;
		if (cutoff > 0)
			while (_unspawnIdx < _rawTotal && _rawStrumTime[_unspawnIdx] < cutoff)
				_unspawnIdx++;

		trace('[NoteManager] rewindTo($targetTime) → idx=$_unspawnIdx / $_rawTotal');
	}

	// ── Hold cover live position tracking ────────────────────────────────────

	private function _updateHoldCoverPositions():Void {
		if (renderer == null)
			return;

		for (dir in heldNotes.keys()) {
			final note = heldNotes.get(dir);
			if (note == null)
				continue;
			final strum = getStrumForDirection(dir, note.strumsGroupIndex, true);
			if (strum == null)
				continue;
			renderer.updateActiveCoverPosition(dir
				+ note.strumsGroupIndex * 8, strum.x
				- strum.offset.x
				+ strum.frameWidth * strum.scale.x * 0.5,
				strum.y
				- strum.offset.y
				+ strum.frameHeight * strum.scale.y * 0.5);
		}

		for (dir in 0...4) {
			if (!_cpuHeldDirs[dir])
				continue;
			final strum = getStrumForDirection(dir, _cpuHoldGroupIdx[dir], false);
			if (strum == null)
				continue;
			renderer.updateActiveCoverPosition(dir
				+ 4
				+ _cpuHoldGroupIdx[dir] * 8, strum.x
				- strum.offset.x
				+ strum.frameWidth * strum.scale.x * 0.5,
				strum.y
				- strum.offset.y
				+ strum.frameHeight * strum.scale.y * 0.5);
		}
	}

	// ── Lifecycle ─────────────────────────────────────────────────────────────

	public function destroy():Void {
		_rawStrumTime.resize(0);
		_rawPacked.resize(0);
		_rawSustainLen.resize(0);
		_rawNoteTypeId.resize(0);
		_rawTotal = 0;
		_unspawnIdx = 0;
		_song = null;
		_noteTypeIndex.clear();
		_noteTypeTable.resize(1);
		_noteTypeTable[0] = '';
		_prevSpawnedNote.clear();

		heldNotes.clear();
		holdStartTimes.clear();
		holdEndTimes.clear();
		_cpuHeldDirs[0] = _cpuHeldDirs[1] = _cpuHeldDirs[2] = _cpuHeldDirs[3] = false;
		cpuHoldEndTimes[0] = cpuHoldEndTimes[1] = cpuHoldEndTimes[2] = cpuHoldEndTimes[3] = -1;
		_cpuHoldGroupIdx[0] = _cpuHoldGroupIdx[1] = _cpuHoldGroupIdx[2] = _cpuHoldGroupIdx[3] = 0;
		_playerHoldGroupIdx[0] = _playerHoldGroupIdx[1] = _playerHoldGroupIdx[2] = _playerHoldGroupIdx[3] = 0;
		_missedHoldDir[0] = _missedHoldDir[1] = _missedHoldDir[2] = _missedHoldDir[3] = false;
		_sustainChainMissed[0] = _sustainChainMissed[1] = _sustainChainMissed[2] = _sustainChainMissed[3] = false;
		_sustainChainMissedEndTime[0] = _sustainChainMissedEndTime[1] = _sustainChainMissedEndTime[2] = _sustainChainMissedEndTime[3] = -1.0;
		_autoReleaseBuffer.resize(0);

		_holdCoverSet.clear();
		_prevGroupInvert.clear();
		_invertTransTimer = 0.0;
		_invertTransitioning = false;
		modManager = null;
		_playerStrumCache.clear();
		_cpuStrumCache.clear();
		_strumGroupCache.clear();

		onAfterUpdate = null;
		onNoteMiss = null;
		onCPUNoteHit = null;
		onNoteHit = null;
		onBotNoteHit = null;
		sustainNotes = null;
		notes = null;
		splashes = null;
		holdCovers = null;
		playerStrums = null;
		cpuStrums = null;
		playerStrumsGroup = null;
		cpuStrumsGroup = null;
		allStrumsGroups = null;

		if (renderer != null) {
			renderer.clearPools();
			renderer.destroy();
			renderer = null;
		}
		if (_sustainClipRect != null) {
			_sustainClipRect.put();
			_sustainClipRect = null;
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
