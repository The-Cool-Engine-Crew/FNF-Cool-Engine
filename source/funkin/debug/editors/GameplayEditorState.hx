package funkin.debug.editors;

import funkin.debug.EditorDialogs.UnsavedChangesDialog;
import coolui.CoolInputText;
import coolui.CoolNumericStepper;
import coolui.CoolCheckBox;
import coolui.CoolDropDown;
import coolui.CoolTabMenu;
import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.group.FlxGroup;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.sound.FlxSound;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import coolui.CoolButton;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import funkin.data.Conductor;
import funkin.data.CoolUtil;
import funkin.data.MetaData;
import funkin.data.Song;
import funkin.data.Song.SwagSong;
import funkin.data.Song.CharacterSlotData;
import funkin.gameplay.CameraController;
import funkin.gameplay.CharacterController;
import funkin.gameplay.Countdown;
import funkin.gameplay.GameState;
import funkin.gameplay.PlayState;
import funkin.gameplay.UIScriptedManager;
import funkin.gameplay.objects.character.Character;
import funkin.gameplay.objects.character.CharacterSlot;
import funkin.gameplay.objects.hud.ScoreManager;
import funkin.gameplay.objects.stages.Stage;
import funkin.scripting.events.EventManager;
import funkin.scripting.HScriptInstance;
import funkin.scripting.ScriptHandler;
import funkin.scripting.events.EventInfoSystem;
import funkin.transitions.StateTransition;
import funkin.menus.FreeplayState.SongMetadata;
import haxe.Json;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import openfl.net.FileReference;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

// ═══════════════════════════════════════════════════════════════════════════════
//  Data Typedefs
// ═══════════════════════════════════════════════════════════════════════════════

typedef PSEEvent = {
	var id:String;
	var stepTime:Float;
	var type:String;
	var value:String;
	var difficulties:Array<String>;
	var trackIndex:Int;
	@:optional var label:String;
	@:optional var duration:Float; // duration in steps (for block display)
	@:optional var params:Dynamic; // structured params per event type
}

typedef PSEScript = {
	var id:String;
	var name:String;
	var code:String; // código inline (siempre actualizado como caché)
	var triggerStep:Float;
	var difficulties:Array<String>;
	var enabled:Bool;
	var autoTrigger:Bool;

	/** Dónde guardar/leer el script:
	 *  null / 'inline'  → embebido en el PSE JSON (por defecto)
	 *  'song'           → assets/songs/<song>/scripts/<name>.hx
	 *  'events'         → assets/data/scripts/events/<name>.hx
	 *  'global'         → assets/data/scripts/global/<name>.hx
	 *  Cualquier otra cadena → ruta literal de archivo
	 */
	@:optional var savePath:String;
}

typedef PSETrack = {
	var id:String;
	var name:String;
	var color:Int;
	var visible:Bool;
	var locked:Bool;
	var height:Int;
}

typedef PSEData = {
	@:optional var events:Array<PSEEvent>;
	@:optional var scripts:Array<PSEScript>;
	@:optional var tracks:Array<PSETrack>;
}

// ═══════════════════════════════════════════════════════════════════════════════
//  GameplayEditorState  v0.1 — FL Studio–style block timeline
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * PlayState Editor — redesigned with a proper block-style event timeline.
 *
 * Layout:
 *   ┌─────────────────── MENU BAR ──────────────────────────────────────┐
 *   │ File  View  Playback  Generate  Edit  Help          [transport]   │
 *   ├──────────────────────────────────────────────────┬────────────────┤
 *   │                                                  │  INSPECTOR     │
 *   │            GAME VIEWPORT                         │  (event props) │
 *   │          (stage + characters)                    │                │
 *   │                                                  │                │
 *   ├──────────────────────────────────────────────────┤                │
 *   │  TIMELINE                                        │                │
 *   │  [Track labels col] [Event blocks on tracks]     │                │
 *   │  [Ruler — bars:beats]                            │                │
 *   │  [Scrubber / progress]                           │                │
 *   └──────────────────────────────────────────────────┴────────────────┘
 *
 * Controls:
 *   SPACE       — Play / Pause
 *   R           — Restart
 *   Ctrl+Z      — Undo
 *   Ctrl+S      — Save (F5 also works)
 *   ESC         — Back
 *   Scroll      — Horizontal scroll timeline (Ctrl+Scroll = zoom)
 *   Click ruler — Seek
 *   Double-click track — Create event at cursor
 *   Click event block — Select + show in Inspector
 */
class GameplayEditorState extends funkin.states.MusicBeatState {
	// ── Layout constants ──────────────────────────────────────────────────────
	static inline final SW:Int = 1280;
	static inline final SH:Int = 720;
	static inline final MENU_H:Int = 22; // menu bar
	static inline final TOPBAR_H:Int = 38; // transport bar
	static inline final STATUS_H:Int = 20;
	static inline final INSP_W:Int = 264; // right inspector width
	static inline final TL_LABEL_W:Int = 108; // track label column
	static inline final TL_RULER_H:Int = 22; // ruler height
	static inline final TL_SCRUB_H:Int = 20; // scrubber height
	static inline final TL_TRACK_H:Int = 28; // each track row height
	static inline final TL_MAX_TRACKS:Int = 8; // max track rows visible
	static inline final HEADER_H:Int = 60; // MENU_H + TOPBAR_H
	static inline final VP_PAD:Int = 6; // padding around centered game viewport

	// ── Colors ────────────────────────────────────────────────────────────────
	static inline final C_BG:Int = 0xFF14141F; // deepest background
	static inline final C_MENU:Int = 0xFF0F0F1A; // menu bar
	static inline final C_TOPBAR:Int = 0xFF161622; // transport bar
	static inline final C_PANEL:Int = 0xFF1C1C2C; // general panels
	static inline final C_INSP:Int = 0xFF181828; // inspector bg
	static inline final C_BORDER:Int = 0xFF2E2E46; // subtle borders
	static inline final C_ACCENT:Int = 0xFF00C8F0; // primary accent (cyan)
	static inline final C_ACCENT2:Int = 0xFF00E894; // secondary accent (mint)
	static inline final C_TEXT:Int = 0xFFE0E0F0; // primary text
	static inline final C_SUBTEXT:Int = 0xFF626280; // secondary text
	static inline final C_PLAYHEAD:Int = 0xFFFF3355; // playhead
	static inline final C_TL_BG:Int = 0xFF0D0D1A; // timeline bg
	static inline final C_TL_RULER:Int = 0xFF141420; // ruler bg
	static inline final C_UNSAVED:Int = 0xFFFFAA00; // unsaved dot
	static inline final C_SELECT:Int = 0xFFFFFFFF; // selection
	static inline final C_MENU_HOVER:Int = 0xFF252538; // menu hover
	static inline final C_VP_FRAME:Int = 0xFF0A0A15; // viewport surround

	// Only ONE track exists by default. The user adds more via Generate > Add Track.
	static final DEFAULT_TRACKS:Array<PSETrack> = [
		{
			id: 'camera',
			name: 'Camera',
			color: 0xFF4488FF,
			visible: true,
			locked: false,
			height: TL_TRACK_H
		},
	];

	// ── Cameras ───────────────────────────────────────────────────────────────
	var camGame:FlxCamera;
	var camHUD:FlxCamera;
	var camUI:FlxCamera;
	var _gameZoom:Float = 1.0;
	var _freeCam:Bool = false;
	var _freeCamX:Float = 0;
	var _freeCamY:Float = 0;

	// ── Camera Proxy (visible camera indicator in game world) ─────────────────

	/** Outline rectangle showing what PlayState's camera sees (visible when zoomed out) */
	var camProxy:FlxSprite = null;

	/** Small label shown on the proxy frame */
	var camProxyLabel:FlxText = null;

	/** Whether the camera proxy overlay is active */
	var _showCamProxy:Bool = true;

	// ── Playback speed ────────────────────────────────────────────────────────
	var _playbackSpeed:Float = 1.0;
	var speedLbl:FlxText = null;

	// ── Gameplay ──────────────────────────────────────────────────────────────
	var currentStage:Stage;
	var characterSlots:Array<CharacterSlot> = [];
	var boyfriend:Character;
	var dad:Character;
	var gf:Character;
	var cameraController:CameraController;
	var characterController:CharacterController;
	var uiManager:UIScriptedManager;
	var gameState:GameState;
	var metaData:MetaData;

	// ── Audio ─────────────────────────────────────────────────────────────────
	var vocals:FlxSound;
	var vocalsBf:FlxSound;
	var vocalsDad:FlxSound;
	var vocalsMap:Map<String, FlxSound> = new Map();
	var _perCharVocals:Bool = false;

	// ── Playback ──────────────────────────────────────────────────────────────
	var isPlaying:Bool = false;
	var songLength:Float = 0;
	var autoSeekTime:Float = -1;
	var _lastBeat:Int = -1;
	var _lastStep:Int = -1;
	var _nextEventIdx:Int = 0;
	var _nextScriptIdx:Int = 0;
	var _chartNotes:Array<{time:Float, direction:Int, isPlayer:Bool, isGF:Bool}> = [];
	var _nextNoteIdx:Int = 0;

	// ── Editor data ───────────────────────────────────────────────────────────
	var pseData:PSEData;
	var tracks:Array<PSETrack> = [];
	var sortedEvents:Array<PSEEvent> = [];
	var sortedScripts:Array<PSEScript> = [];
	var hasUnsaved:Bool = false;
	var currentSong:String = '';
	var currentDiff:String = 'normal';
	var allDiffs:Array<String> = [];
	var selectedEventId:String = '';
	var _hoveredEventId:String = '';
	var scriptInstances:Map<String, HScriptInstance> = new Map();

	// Undo stack
	var _undoStack:Array<String> = []; // JSON snapshots
	var _redoStack:Array<String> = [];

	static inline final MAX_UNDO:Int = 50;

	// ── UI — Menu bar ─────────────────────────────────────────────────────────
	var menuBg:FlxSprite;
	var menuItems:Array<PSEMenuBtn> = [];
	var _activeMenu:Int = -1;
	var _menuDropdowns:Array<PSEDropdownPanel> = [];

	// ── UI — Top transport bar ────────────────────────────────────────────────
	var topBg:FlxSprite;
	var songTitleTxt:FlxText;
	var playBtn:PSEBtn;
	var stopBtn:PSEBtn;
	var restartBtn:PSEBtn;
	var timeTxt:FlxText;
	var diffDropdown:CoolDropDown;
	var unsavedDot:FlxSprite;
	var freeCamBtn:PSEBtn;
	var snapCheck:CoolCheckBox;
	var zoomSlider:PSESlider;
	var _snapEnabled:Bool = true;

	// ── UI — Timeline ─────────────────────────────────────────────────────────
	var tlBg:FlxSprite;
	var tlRulerBg:FlxSprite;
	var rulerLabels:Array<FlxText> = [];
	var rulerTicks:Array<FlxSprite> = [];
	var tlPlayhead:FlxSprite;
	var tlPlayheadHead:FlxSprite; // triangle on top
	var tlScrubBg:FlxSprite;
	var tlScrubFill:FlxSprite;
	var tlScrubHandle:FlxSprite;
	var tlLabelColBg:FlxSprite;
	var trackBgs:Array<FlxSprite> = [];
	var trackLabels:Array<FlxText> = [];
	var trackLocks:Array<PSEBtn> = [];
	var trackColors:Array<FlxSprite> = [];
	var eventBlocks:Array<PSEEventBlock> = [];
	var gridLines:Array<FlxSprite> = [];
	var tlScrollX:Float = 0; // scroll offset in ms
	var tlZoom:Float = 0.08; // px/ms
	var _scrubDrag:Bool = false;
	var _hScrollDrag:Bool = false;
	var _hScrollDragOff:Float = 0;
	var tlHScrollBg:FlxSprite;
	var tlHScrollThumb:FlxSprite;
	var _dragEvent:PSEEventBlock = null;
	var _dragEvtOffMs:Float = 0;
	var _dragEvtOffY:Float = 0;
	var _resizeEvent:PSEEventBlock = null;
	var _resizeEvtOrigDur:Float = 0;
	var _resizeStartX:Float = 0;

	// ── Double-click detection ────────────────────────────────────────────────
	var _lastClickTime:Float = 0;
	var _lastClickX:Float = 0;
	var _lastClickY:Float = 0;

	// ── Resize handle hover visual ────────────────────────────────────────────
	var _hoverResizeId:String = '';
	var _resizeHandleViz:FlxSprite = null;

	// ── UI — Inspector (right panel) ──────────────────────────────────────────
	var inspBg:FlxSprite;
	var inspTitle:FlxText;
	var inspTabs:CoolTabMenu;
	var _inspElements:Array<flixel.FlxBasic> = [];

	// Inspector — Event properties
	var ipEventType:CoolDropDown;
	var ipEventLabel:CoolInputText;
	var ipEventStep:CoolNumericStepper;
	var ipEventDur:CoolNumericStepper;
	var ipEventTrack:CoolNumericStepper;
	var ipEventValue:CoolInputText;
	var ipEventDiffChecks:Array<CoolCheckBox> = [];

	// Camera event properties
	var ipCamZoom:CoolNumericStepper;
	var ipCamMode:CoolDropDown;
	var ipCamDuration:CoolNumericStepper;
	var ipCamEaseType:CoolDropDown;
	var ipCamEaseDir:CoolDropDown;
	var ipCamCurve:FlxSprite; // ease curve preview (64×64)

	// Script inspector
	var ipScrName:CoolInputText;
	var ipScrCode:CoolInputText;
	var ipScrStep:CoolNumericStepper;
	var ipScrAuto:CoolCheckBox;
	var ipScrEnabled:CoolCheckBox;

	// Song tab info
	var ipSongInfoTxt:FlxText;

	// ── Status bar ────────────────────────────────────────────────────────────
	var statusBg:FlxSprite;
	var statusTxt:FlxText;
	var _statusTimer:Float = 0;
	var cursorInfoTxt:FlxText; // right side: "Bar 2.3 | Step 12 | 0:03.26"

	// ── Context menu ──────────────────────────────────────────────────────────
	var _ctxMenu:PSEContextMenu = null;

	// ── Track management ──────────────────────────────────────────────────────
	var _trackScrollY:Int = 0; // first visible track index

	// ── Internal ──────────────────────────────────────────────────────────────
	var _songMeta:SongMetadata;
	var _unsavedDlg:UnsavedChangesDialog = null;

	static var _uid:Int = 0;

	var _windowCloseFn:Void->Void = null;

	// ── Computed layout helpers ───────────────────────────────────────────────
	inline function _tlY():Int
		return HEADER_H + _gameH();

	inline function _gameH():Int
		return SH - HEADER_H - STATUS_H - _tlH();

	inline function _tlH():Int {
		var n = Std.int(Math.min(tracks.length - _trackScrollY, TL_MAX_TRACKS));
		return TL_RULER_H + n * TL_TRACK_H + TL_SCRUB_H + 12; // 12 = scrollbar
	}

	inline function _tlAreaW():Int
		return SW - TL_LABEL_W - INSP_W;

	inline function _gameW():Int
		return SW - INSP_W;

	var versionEditor:String = '0.1';

	// ─────────────────────────────────────────────────────────────────────────
	//  Constructor
	// ─────────────────────────────────────────────────────────────────────────
	public function new(?meta:SongMetadata) {
		super();
		_songMeta = meta;
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Create
	// ─────────────────────────────────────────────────────────────────────────
	override public function create():Void {
		funkin.system.CursorManager.show();
		persistentDraw = true;
		persistentUpdate = true;

		if (PlayState.SONG == null) {
			StateTransition.switchState(new FreeplayEditorState());
			return;
		}
		currentSong = PlayState.SONG.song ?? 'unknown';

		if (FlxG.sound.music != null) {
			FlxG.sound.music.stop();
			FlxG.sound.music = null;
		}

		_setupCameras();
		gameState = GameState.get();
		gameState.reset();
		gameState.health = 1.0;
		_loadStageAndCharacters();
		metaData = MetaData.load(currentSong, CoolUtil.difficultySuffix());
		_setupHUD();
		_loadPSEData();
		_applyGameViewport(); // re-apply now that tracks.length is known
		_setupAudio();
		_buildChartNotes();

		ScriptHandler.init();
		ScriptHandler.loadSongScripts(currentSong);
		EventManager.loadEventsFromSong();

		// ── Exponer el entorno completo de PlayState a los song scripts ───────────
		// Sin esto, scripts como events_senpai.hx crashean al acceder a dad/boyfriend/
		// currentStage/cameraController porque son null desde su perspectiva.
		ScriptHandler.setOnScripts('SONG', PlayState.SONG);
		ScriptHandler.setOnScripts('camGame', camGame);
		ScriptHandler.setOnScripts('camHUD', camHUD);
		ScriptHandler.setOnScripts('game', this);
		ScriptHandler.setOnScripts('playStateEditor', this);
		ScriptHandler.setOnScripts('boyfriend', boyfriend);
		ScriptHandler.setOnScripts('dad', dad);
		ScriptHandler.setOnScripts('gf', gf);
		ScriptHandler.setOnScripts('currentStage', currentStage);
		ScriptHandler.setOnScripts('cameraController', cameraController);
		ScriptHandler.setOnScripts('characterController', characterController);
		ScriptHandler.setOnScripts('gameState', gameState);
		ScriptHandler.setOnScripts('uiManager', uiManager);
		ScriptHandler.setOnScripts('Conductor', Conductor);
		ScriptHandler.setOnScripts('FlxG', FlxG);
		ScriptHandler.setOnScripts('FlxTween', FlxTween);
		ScriptHandler.setOnScripts('FlxEase', FlxEase);
		ScriptHandler.setOnScripts('FlxTimer', FlxTimer);
		ScriptHandler.setOnScripts('EventManager', EventManager);

		ScriptHandler.callOnScripts('onCreate', ScriptHandler._argsEmpty);
		ScriptHandler.callOnScripts('postStageCreate', ScriptHandler._argsEmpty);
		ScriptHandler.callOnScripts('postCreate', ScriptHandler._argsEmpty);

		// Registrar handlers de eventos de cámara del chart para que usen el
		// cameraController del editor (PlayState.instance es null aquí).
		_registerEditorEventHandlers();

		// ── Build UI ──
		_buildBackground();
		_buildMenuBar();
		_buildTopBar();
		_buildTimeline();
		_buildInspector();
		_buildStatusBar();

		Conductor.songPosition = 0;
		if (FlxG.sound.music != null)
			FlxG.sound.music.time = 0;
		_doSeek(0);
		_rebuildRuler();
		_rebuildEventBlocks();
		_refreshInspector();

		isPlaying = false;
		_showStatus('PlayState Editor v2  —  Help menu for controls  |  Ctrl+S = save');

		#if sys
		_windowCloseFn = function() {
			if (hasUnsaved)
				try {
					_savePSEData();
				} catch (_) {}
		};
		lime.app.Application.current.window.onClose.add(_windowCloseFn);
		#end

		super.create();
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Cameras
	// ─────────────────────────────────────────────────────────────────────────
	function _setupCameras():Void {
		// Render order (back → front):
		//   camHUD  (full-screen, opaque editor bg — menus / timeline / inspector)
		//   camGame (sub-viewport — stage & characters, renders on top of editor bg in its region)
		//   camUI   (full-screen, transparent — dropdowns / context menus, always on top of everything)
		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		FlxG.cameras.reset(camHUD); // first = bottom layer (editor UI background)

		camGame = new FlxCamera();
		camGame.bgColor = FlxColor.fromRGB(10, 10, 18);
		FlxG.cameras.add(camGame, false); // second = game viewport, on top of editor bg

		camUI = new FlxCamera();
		camUI.bgColor.alpha = 0;
		FlxG.cameras.add(camUI, false); // third = top-most layer for dropdowns/context menus

		@:privateAccess FlxCamera._defaultCameras = [camGame];
		_applyGameViewport();
	}

	function _applyGameViewport():Void {
		if (camGame == null)
			return;
		var availW = SW - INSP_W;
		var availH = _gameH() - VP_PAD * 2;

		// Fit within available area maintaining 16:9 aspect ratio
		var targetW = availW - VP_PAD * 2;
		var targetH = Std.int(targetW * 9 / 16);
		if (targetH > availH) {
			targetH = availH;
			targetW = Std.int(targetH * 16 / 9);
		}
		if (targetW > availW - VP_PAD * 2)
			targetW = availW - VP_PAD * 2;
		if (targetH > availH)
			targetH = availH;

		// Center horizontally within the non-inspector area
		camGame.x = Std.int((availW - targetW) / 2);
		camGame.y = HEADER_H + VP_PAD;
		camGame.width = targetW;
		camGame.height = targetH;

		camGame.zoom = _gameZoom * (camGame.width / SW);
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Stage + Characters
	// ─────────────────────────────────────────────────────────────────────────
	function _loadStageAndCharacters():Void {
		var SONG = PlayState.SONG;
		if (SONG.stage == null)
			SONG.stage = 'stage_week1';
		PlayState.curStage = SONG.stage;
		Paths.currentStage = SONG.stage;

		// Capture member count BEFORE Stage construction.
		// Some Stage implementations add background sprites directly to FlxG.state
		// (instead of to themselves as a group). We'll reassign cameras on those too.
		var membersBefore = members.length;

		currentStage = new Stage(SONG.stage);

		// Reassign any sprites the Stage constructor added directly to this state
		// (covers Stage scripts/impls that call FlxG.state.add() for background layers)
		for (i in membersBefore...members.length) {
			if (members[i] != null)
				_assignCams(members[i], [camGame]);
		}

		currentStage.cameras = [camGame];
		_assignCams(currentStage, [camGame]);

		_loadCharacters();
		if (currentStage._useCharAnchorSystem) {
			add(currentStage);
			_addCharactersWithAnchors(); // Llamamos al sistema de anclas
		} else {
			add(currentStage);
			for (slot in characterSlots)
				if (slot.character != null)
					add(slot.character);
			if (currentStage.aboveCharsGroup != null && currentStage.aboveCharsGroup.length > 0)
				add(currentStage.aboveCharsGroup);
		}

		for (slot in characterSlots) {
			if (slot.isGFSlot && gf == null)
				gf = slot.character;
			else if (slot.isOpponentSlot && dad == null)
				dad = slot.character;
			else if (slot.isPlayerSlot && boyfriend == null)
				boyfriend = slot.character;
		}

		if (currentStage.hideGirlfriend)
			for (slot in characterSlots)
				if (slot.isGFSlot && slot.character != null)
					slot.character.visible = false;

		if (boyfriend != null && dad != null) {
			cameraController = new CameraController(camGame, camHUD, boyfriend, dad, gf);
			if (currentStage != null) {
				if (currentStage.defaultCamZoom > 0)
					cameraController.defaultZoom = currentStage.defaultCamZoom;
				cameraController.stageOffsetBf.set(currentStage.cameraBoyfriend.x, currentStage.cameraBoyfriend.y);
				cameraController.stageOffsetDad.set(currentStage.cameraDad.x, currentStage.cameraDad.y);
				cameraController.stageOffsetGf.set(currentStage.cameraGirlfriend.x, currentStage.cameraGirlfriend.y);
				cameraController.lerpSpeed = CameraController.BASE_LERP_SPEED * currentStage.cameraSpeed;
			}
			cameraController.snapshotInitialState();
		}

		characterController = new CharacterController();
		characterController.initFromSlots(characterSlots);
		characterController.forceIdleAll();

		// Build the camera proxy frame (visible when zoomed out)
		_buildCamProxy();

		for (m in members)
			if (m != null)
				_assignCams(m, [camGame]);

		// Snap the initial camera so the stage is visible right away.
		// Without this, camGame.scroll stays at (0,0) and off-center stage
		// backgrounds (at negative world coords) remain off-screen until the
		// first CameraController update tick.
		if (cameraController != null) {
			try {
				cameraController.resetToInitial();
			} catch (_) {}
			try {
				cameraController.update(0.016);
			} catch (_) {}
		}
	}

	private function _addCharactersWithAnchors():Void {
		var addedCharSlots:Map<String, Bool> = new Map();
		var addedCharObjects:Array<Character> = [];

		for (entry in currentStage.spriteList) {
			if (entry.sprite != null) {
				entry.sprite.cameras = [camGame];
				add(entry.sprite);
			} else if (entry.element.type != null && entry.element.type.toLowerCase() == 'character' && entry.element.charSlot != null) {
				var slotKey = entry.element.charSlot.toLowerCase();
				for (slot in characterSlots) {
					var matches = switch (slotKey) {
						case 'bf', 'boyfriend', 'player', 'player1': slot.isPlayerSlot;
						case 'gf', 'girlfriend', 'spectator': slot.isGFSlot;
						case 'dad', 'opponent', 'player2': slot.isOpponentSlot;
						default: false;
					};
					if (matches && !addedCharSlots.exists(slotKey)) {
						add(slot.character);
						addedCharSlots.set(slotKey, true);
						addedCharObjects.push(slot.character);
						break;
					}
				}
			}
		}

		for (slot in characterSlots)
			if (slot.character != null && !addedCharObjects.contains(slot.character))
				add(slot.character);
	}

	function _loadCharacters():Void {
		var SONG = PlayState.SONG;
		if (SONG.characters == null || SONG.characters.length == 0) {
			SONG.characters = [];
			SONG.characters.push({
				name: SONG.gfVersion ?? 'gf',
				x: 0,
				y: 0,
				visible: true,
				isGF: true,
				type: 'Girlfriend',
				strumsGroup: 'gf_strums_0'
			});
			SONG.characters.push({
				name: SONG.player2 ?? 'dad',
				x: 0,
				y: 0,
				visible: true,
				type: 'Opponent',
				strumsGroup: 'cpu_strums_0'
			});
			SONG.characters.push({
				name: SONG.player1 ?? 'bf',
				x: 0,
				y: 0,
				visible: true,
				type: 'Player',
				strumsGroup: 'player_strums_0'
			});
		}
		for (i in 0...SONG.characters.length) {
			var cd = SONG.characters[i];
			var slot = new CharacterSlot(cd, i);
			if (cd.x == 0 && cd.y == 0)
				switch (slot.charType) {
					case 'Girlfriend':
						slot.character.setPosition(currentStage.gfPosition.x, currentStage.gfPosition.y);
					case 'Opponent':
						slot.character.setPosition(currentStage.dadPosition.x, currentStage.dadPosition.y);
					case 'Player':
						slot.character.setPosition(currentStage.boyfriendPosition.x, currentStage.boyfriendPosition.y);
					default:
				}
			else
				slot.character.setPosition(cd.x, cd.y);

			if (slot.character.characterData != null) {
				var po = slot.character.characterData.positionOffset;
				if (po != null && po.length >= 2) {
					slot.character.x += po[0];
					slot.character.y += po[1];
				}
			}
			characterSlots.push(slot);
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Camera Proxy — visible frame in game world showing camera FOV
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Crea un sprite 320×180 (escalado en runtime al FOV real del juego)
	 * que muestra DÓNDE mira la cámara del juego.
	 * Se renderiza en camGame (vive en coordenadas mundo) y se escala con el
	 * editor. Al hacer zoom out muy lejos puedes ver todo el stage Y el recuadro
	 * de la cámara moviéndose a medida que los eventos se disparan.
	 *
	 * Atajo: tecla C para mostrar/ocultar.
	 */
	function _buildCamProxy():Void {
		final W = 320;
		final H = 180;
		camProxy = new FlxSprite(0, 0);
		camProxy.makeGraphic(W, H, FlxColor.TRANSPARENT, true);

		// Borde exterior — cyan
		final BC:Int = 0xBB00C8F0;
		flixel.util.FlxSpriteUtil.drawRect(camProxy, 0, 0, W, 3, BC);
		flixel.util.FlxSpriteUtil.drawRect(camProxy, 0, H - 3, W, 3, BC);
		flixel.util.FlxSpriteUtil.drawRect(camProxy, 0, 0, 3, H, BC);
		flixel.util.FlxSpriteUtil.drawRect(camProxy, W - 3, 0, 3, H, BC);

		// Marcas en esquinas (rojo/rosa)
		final CC:Int = 0xCCFF3355;
		final CS:Int = 24;
		flixel.util.FlxSpriteUtil.drawRect(camProxy, 0, 0, CS, 5, CC);
		flixel.util.FlxSpriteUtil.drawRect(camProxy, 0, 0, 5, CS, CC);
		flixel.util.FlxSpriteUtil.drawRect(camProxy, W - CS, 0, CS, 5, CC);
		flixel.util.FlxSpriteUtil.drawRect(camProxy, W - 5, 0, 5, CS, CC);
		flixel.util.FlxSpriteUtil.drawRect(camProxy, 0, H - 5, CS, 5, CC);
		flixel.util.FlxSpriteUtil.drawRect(camProxy, 0, H - CS, 5, CS, CC);
		flixel.util.FlxSpriteUtil.drawRect(camProxy, W - CS, H - 5, CS, 5, CC);
		flixel.util.FlxSpriteUtil.drawRect(camProxy, W - 5, H - CS, 5, CS, CC);

		// Cruz central
		flixel.util.FlxSpriteUtil.drawRect(camProxy, W / 2 - 1, H / 2 - 12, 2, 24, 0x88FF3355);
		flixel.util.FlxSpriteUtil.drawRect(camProxy, W / 2 - 12, H / 2 - 1, 24, 2, 0x88FF3355);

		camProxy.cameras = [camGame];
		camProxy.scrollFactor.set(1, 1);
		camProxy.alpha = 0.8;
		camProxy.active = false;
		camProxy.visible = false;
		add(camProxy);

		// Etiqueta "CAM"
		camProxyLabel = new FlxText(0, 0, 80, 'CAM', 8);
		camProxyLabel.setFormat(Paths.font('vcr.ttf'), 8, 0xFF00C8F0, LEFT);
		camProxyLabel.cameras = [camGame];
		camProxyLabel.scrollFactor.set(1, 1);
		camProxyLabel.active = false;
		camProxyLabel.visible = false;
		add(camProxyLabel);
	}

	/**
	 * Llama cada frame desde update().
	 * Posiciona y escala el recuadro proxy para que coincida con el FOV
	 * de PlayState en coordenadas mundo. Solo visible cuando zoom editor < 0.88.
	 */
	function _updateCamProxy():Void {
		if (camProxy == null || camGame == null)
			return;

		var dz:Float = (cameraController != null && cameraController.defaultZoom > 0) ? cameraController.defaultZoom : 1.0;

		// Tamaño del FOV de PlayState en unidades mundo
		var vw:Float = 1280.0 / dz;
		var vh:Float = 720.0 / dz;

		// Centro de lo que la cámara editor está viendo, en espacio mundo
		var cx:Float = camGame.scroll.x + camGame.width / (2.0 * camGame.zoom);
		var cy:Float = camGame.scroll.y + camGame.height / (2.0 * camGame.zoom);

		// Escalar el sprite 320×180 al tamaño FOV real
		camProxy.scale.set(vw / 320.0, vh / 180.0);
		camProxy.updateHitbox();
		camProxy.setPosition(cx - vw * 0.5, cy - vh * 0.5);

		var show = _showCamProxy && camGame.zoom < 0.88;
		camProxy.visible = show;

		if (camProxyLabel != null) {
			camProxyLabel.setPosition(cx - vw * 0.5 + 6, cy - vh * 0.5 + 4);
			camProxyLabel.visible = show;
		}
	}

	function _assignCams(obj:FlxBasic, cams:Array<FlxCamera>):Void {
		obj.cameras = cams;
		if (Std.isOfType(obj, FlxGroup))
			for (m in (cast obj : FlxGroup).members)
				if (m != null)
					_assignCams(m, cams);
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  HUD
	// ─────────────────────────────────────────────────────────────────────────
	function _setupHUD():Void {
		var icons = [PlayState.SONG.player1 ?? 'bf', PlayState.SONG.player2 ?? 'dad'];
		if (boyfriend != null && dad != null && boyfriend.healthIcon != null && dad.healthIcon != null)
			icons = [boyfriend.healthIcon, dad.healthIcon];

		uiManager = new UIScriptedManager(camHUD, gameState, metaData);
		uiManager.setIcons(icons[0], icons[1]);
		uiManager.setStage(PlayState.curStage);
		uiManager.cameras = [camHUD];
		add(uiManager);
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Audio
	// ─────────────────────────────────────────────────────────────────────────
	function _setupAudio():Void {
		var SONG = PlayState.SONG;
		Conductor.changeBPM(SONG.bpm);
		if (FlxG.sound.music != null) {
			FlxG.sound.music.stop();
			FlxG.sound.music = null;
		}

		var diffSuffix = (SONG.instSuffix != null && SONG.instSuffix != '') ? '-' + SONG.instSuffix : CoolUtil.difficultySuffix();

		FlxG.sound.music = Paths.loadInst(SONG.song, diffSuffix);
		if (FlxG.sound.music != null) {
			FlxG.sound.music.volume = 1;
			FlxG.sound.music.pause();
			FlxG.sound.music.onComplete = _onSongEnd;
			songLength = FlxG.sound.music.length;
		}

		if (!SONG.needsVoices)
			return;
		var loadedAny = false;
		if (SONG.characters != null) {
			for (cd in SONG.characters) {
				final cn = cd.name ?? '';
				if (cn == '')
					continue;
				for (alias in [cn, _vocalAlias(cn)]) {
					var snd = Paths.loadVoicesForChar(SONG.song, alias, diffSuffix);
					if (snd != null) {
						vocalsMap.set(alias, snd);
						FlxG.sound.list.add(snd);
						_perCharVocals = true;
						loadedAny = true;
						break;
					}
				}
			}
		}
		if (!loadedAny) {
			var bfS = Paths.loadVoicesForChar(SONG.song, 'bf', diffSuffix);
			if (bfS != null) {
				_perCharVocals = true;
				vocalsBf = bfS;
				vocalsDad = Paths.loadVoicesForChar(SONG.song, 'dad', diffSuffix) ?? Paths.loadVoices(SONG.song, diffSuffix);
				FlxG.sound.list.add(vocalsBf);
				if (vocalsDad != null)
					FlxG.sound.list.add(vocalsDad);
				loadedAny = true;
			}
		}
		if (!loadedAny) {
			vocals = Paths.loadVoices(SONG.song, diffSuffix);
			if (vocals != null)
				FlxG.sound.list.add(vocals);
		}
	}

	function _vocalAlias(n:String):String
		return switch (n.toLowerCase()) {
			case 'boyfriend' | 'bf-pixel' | 'bf-car': 'bf';
			case 'dad' | 'daddy-dearest': 'dad';
			case 'gf' | 'gf-christmas' | 'gf-pixel': 'gf';
			default: n;
		}

	function _onSongEnd():Void {
		isPlaying = false;
		_syncAudio(false);
		_showStatus('Song ended');
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  PSE Data
	// ─────────────────────────────────────────────────────────────────────────
	function _loadPSEData():Void {
		pseData = {events: [], scripts: [], tracks: []};
		#if sys
		final parsed:Dynamic = funkin.data.LevelFile.loadPSE(currentSong);
		if (parsed != null) {
			if (parsed.events != null)
				pseData.events = parsed.events;
			if (parsed.scripts != null)
				pseData.scripts = parsed.scripts;
			if (parsed.tracks != null)
				pseData.tracks = parsed.tracks;
		} else {
			var path = Paths.resolve('songs/${currentSong.toLowerCase()}/${currentSong.toLowerCase()}-playstate.json');
			if (FileSystem.exists(path))
				try {
					var ld:PSEData = cast Json.parse(File.getContent(path));
					if (ld.events != null)
						pseData.events = ld.events;
					if (ld.scripts != null)
						pseData.scripts = ld.scripts;
				} catch (_) {}
		}
		#end

		// Build track list: merge saved tracks with defaults
		tracks = [];
		if (pseData.tracks != null && pseData.tracks.length > 0)
			tracks = pseData.tracks;
		else {
			for (t in DEFAULT_TRACKS)
				tracks.push({
					id: t.id,
					name: t.name,
					color: t.color,
					visible: t.visible,
					locked: t.locked,
					height: t.height
				});
			pseData.tracks = tracks;
		}

		_rebuildSorted();
		_refreshDiffList();
		_importSectionCamEvents();
	}

	function _savePSEData():Void {
		pseData.tracks = tracks;
		#if sys
		final ok = funkin.data.LevelFile.savePSE(currentSong, pseData);
		if (ok) {
			hasUnsaved = false;
			_updateUnsavedDot();
			_showStatus('✓ Guardado en ${currentSong.toLowerCase()}.level');
		} else
			_showStatus('✗ Error al guardar — ver consola');
		#else
		_showStatus('✗ Guardado solo disponible en desktop');
		#end
	}

	function _rebuildSorted():Void {
		sortedEvents = (pseData.events ?? []).copy();
		sortedEvents.sort((a, b) -> Std.int(a.stepTime - b.stepTime));
		sortedScripts = (pseData.scripts ?? []).copy();
		sortedScripts.sort((a, b) -> Std.int(a.triggerStep - b.triggerStep));
		_nextEventIdx = 0;
		_nextScriptIdx = 0;
	}

	function _refreshDiffList():Void {
		final pairs = funkin.data.LevelFile.getAvailableDifficulties(currentSong);
		var set:Map<String, Bool> = new Map();
		for (p in pairs) {
			final s = p[1];
			set.set(s == '' ? 'normal' : s.substr(1), true);
		}
		for (e in (pseData.events ?? []))
			for (d in e.difficulties)
				if (d != '*')
					set.set(d, true);
		for (s in (pseData.scripts ?? []))
			for (d in s.difficulties)
				if (d != '*')
					set.set(d, true);
		allDiffs = [for (k in set.keys()) k];
		final prio = ['easy', 'normal', 'hard'];
		final ordered:Array<String> = [];
		for (p in prio)
			if (allDiffs.contains(p))
				ordered.push(p);
		final rest = allDiffs.filter(d -> !prio.contains(d));
		rest.sort((a, b) -> a < b ? -1 : 1);
		allDiffs = ordered.concat(rest);
		if (allDiffs.length == 0)
			allDiffs = ['easy', 'normal', 'hard'];
		if (!allDiffs.contains(currentDiff))
			currentDiff = allDiffs[0];
	}

	function _pushUndo():Void {
		_undoStack.push(Json.stringify(pseData));
		if (_undoStack.length > MAX_UNDO)
			_undoStack.shift();
		_redoStack = [];
	}

	function _doUndo():Void {
		if (_undoStack.length == 0) {
			_showStatus('Nothing to undo');
			return;
		}
		_redoStack.push(Json.stringify(pseData));
		pseData = cast Json.parse(_undoStack.pop());
		_rebuildSorted();
		_refreshDiffList();
		_rebuildEventBlocks();
		_refreshInspector();
		hasUnsaved = true;
		_updateUnsavedDot();
		_showStatus('Undo');
	}

	function _doRedo():Void {
		if (_redoStack.length == 0) {
			_showStatus('Nothing to redo');
			return;
		}
		_undoStack.push(Json.stringify(pseData));
		pseData = cast Json.parse(_redoStack.pop());
		_rebuildSorted();
		_refreshDiffList();
		_rebuildEventBlocks();
		_refreshInspector();
		hasUnsaved = true;
		_updateUnsavedDot();
		_showStatus('Redo');
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Background
	// ─────────────────────────────────────────────────────────────────────────
	function _buildBackground():Void {
		// ── Full editor background ────────────────────────────────────────────
		var bg = new FlxSprite(0, 0).makeGraphic(SW, SH, C_BG);
		bg.cameras = [camHUD];
		bg.scrollFactor.set();
		add(bg);

		// ── Game area: only draw the 4 border strips AROUND the viewport ─────
		// (the viewport itself is left uncovered so camGame content is visible)
		var areaW = SW - INSP_W;
		var areaH = _gameH();
		var vpX = camGame != null ? Std.int(camGame.x) : 0;
		var vpY = camGame != null ? Std.int(camGame.y) : HEADER_H;
		var vpW = camGame != null ? camGame.width : areaW;
		var vpH = camGame != null ? camGame.height : areaH;

		// Strip above viewport
		if (vpY > HEADER_H) {
			var top = new FlxSprite(0, HEADER_H).makeGraphic(areaW, vpY - HEADER_H, C_VP_FRAME);
			top.cameras = [camHUD];
			top.scrollFactor.set();
			add(top);
		}
		// Strip below viewport
		var belowY = vpY + vpH;
		if (belowY < HEADER_H + areaH) {
			var bot = new FlxSprite(0, belowY).makeGraphic(areaW, HEADER_H + areaH - belowY, C_VP_FRAME);
			bot.cameras = [camHUD];
			bot.scrollFactor.set();
			add(bot);
		}
		// Strip left of viewport
		if (vpX > 0) {
			var left = new FlxSprite(0, vpY).makeGraphic(vpX, vpH, C_VP_FRAME);
			left.cameras = [camHUD];
			left.scrollFactor.set();
			add(left);
		}
		// Strip right of viewport
		if (vpX + vpW < areaW) {
			var right = new FlxSprite(vpX + vpW, vpY).makeGraphic(areaW - (vpX + vpW), vpH, C_VP_FRAME);
			right.cameras = [camHUD];
			right.scrollFactor.set();
			add(right);
		}

		// ── Accent border (1px cyan glow around the viewport) ────────────────
		var fTop = new FlxSprite(vpX - 1, vpY - 1).makeGraphic(vpW + 2, 1, C_ACCENT);
		fTop.cameras = [camHUD];
		fTop.scrollFactor.set();
		fTop.alpha = 0.35;
		add(fTop);
		var fBot = new FlxSprite(vpX - 1, vpY + vpH).makeGraphic(vpW + 2, 1, C_ACCENT);
		fBot.cameras = [camHUD];
		fBot.scrollFactor.set();
		fBot.alpha = 0.35;
		add(fBot);
		var fL = new FlxSprite(vpX - 1, vpY).makeGraphic(1, vpH, C_ACCENT);
		fL.cameras = [camHUD];
		fL.scrollFactor.set();
		fL.alpha = 0.22;
		add(fL);
		var fR = new FlxSprite(vpX + vpW, vpY).makeGraphic(1, vpH, C_ACCENT);
		fR.cameras = [camHUD];
		fR.scrollFactor.set();
		fR.alpha = 0.22;
		add(fR);
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Menu Bar
	// ─────────────────────────────────────────────────────────────────────────
	function _buildMenuBar():Void {
		menuBg = new FlxSprite(0, 0).makeGraphic(SW, MENU_H, C_MENU);
		menuBg.cameras = [camHUD];
		menuBg.scrollFactor.set();
		add(menuBg);

		// Bottom separator
		var sep = new FlxSprite(0, MENU_H - 1).makeGraphic(SW, 1, C_BORDER);
		sep.cameras = [camHUD];
		sep.scrollFactor.set();
		add(sep);

		final entries = ['File', 'View', 'Playback', 'Generate', 'Edit', 'Help'];
		var mx = 6.0;
		for (i in 0...entries.length) {
			var btn = new PSEMenuBtn(mx, 0, entries[i], C_MENU, C_MENU_HOVER, C_TEXT, i, function(idx:Int, bx:Float) {
				_activeMenu = idx;
				_closeMenuDropdowns();
				_openMenuDropdown(idx, bx);
			});
			btn.cameras = [camHUD];
			btn.scrollFactor.set();
			btn.label.cameras = [camHUD];
			btn.label.scrollFactor.set();
			menuItems.push(btn);
			add(btn);
			add(btn.label);
			mx += btn.width + 2;
		}

		// Song name in center of menu bar
		var snTxt = new FlxText(0, 4, SW, currentSong.toUpperCase(), 10);
		snTxt.setFormat(Paths.font('vcr.ttf'), 10, C_SUBTEXT, CENTER);
		snTxt.scrollFactor.set();
		snTxt.cameras = [camHUD];
		add(snTxt);

		// Right-side: PSE version tag (subtle)
		var proto = new FlxText(SW - 80, 5, 74, 'GE v'+versionEditor, 8);
		proto.setFormat(Paths.font('vcr.ttf'), 8, 0xFF333350, RIGHT);
		proto.scrollFactor.set();
		proto.cameras = [camHUD];
		add(proto);
	}

	function _openMenuDropdown(idx:Int, bx:Float):Void {
		var items:Array<{label:String, cb:Void->Void, sep:Bool}> = switch (idx) {
			case 0: [
					// File
					{label: 'Save  Ctrl+S', sep: false, cb: _savePSEData},
					{
						label: 'Import Camera Sections',
						sep: false,
						cb: () -> {
							_importSectionCamEvents();
							_rebuildEventBlocks();
							_showStatus('Secciones importadas como eventos de cámara');
						}
					},
					{label: '---', sep: true, cb: null},
					{label: 'Exit  ESC', sep: false, cb: _goBack},
				];
			case 1: [
					// View
					{
						label: 'Toggle Inspector',
						sep: false,
						cb: () -> {
							inspBg.visible = !inspBg.visible;
							_rebuildRuler();
							_rebuildEventBlocks();
						}
					},
					{
						label: 'Toggle HUD',
						sep: false,
						cb: () -> {
							if (uiManager != null)
								uiManager.visible = !uiManager.visible;
						}
					},
					{label: 'Free Camera (F)', sep: false, cb: _toggleFreeCam},
					{
						label: 'Toggle Camera Proxy (C)',
						sep: false,
						cb: () -> {
							_showCamProxy = !_showCamProxy;
							_showStatus(_showCamProxy ? '[CAM] Camera proxy ON' : '[CAM] Camera proxy OFF');
						}
					},
					{
						label: 'Reset Game Zoom (0)',
						sep: false,
						cb: () -> {
							_gameZoom = 1.0;
							if (camGame != null)
								camGame.zoom = _gameZoom;

							if (cameraController != null) cameraController.zoomEnabled = true;
							_showStatus('Zoom reset → 100%');
						}
					},
				];
			case 2: [
					// Playback
					{label: 'Play / Pause  SPACE', sep: false, cb: _onPlayPause},
					{label: 'Stop  .', sep: false, cb: _onStop},
					{label: 'Restart  R', sep: false, cb: _onRestart},
					{label: '---', sep: true, cb: null},
					{label: 'Jump to Start  Home', sep: false, cb: () -> autoSeekTime = 0},
					{label: 'Jump to End  End', sep: false, cb: () -> autoSeekTime = songLength - 50},
					{label: '---', sep: true, cb: null},
					{
						label: 'Speed 0.25x',
						sep: false,
						cb: () -> {
							_playbackSpeed = 0.25;
							if (speedLbl != null)
								speedLbl.text = '0.25x';
							_applyPlaybackSpeed();
							_showStatus('Speed: 0.25x');
						}
					},
					{
						label: 'Speed 0.5x',
						sep: false,
						cb: () -> {
							_playbackSpeed = 0.5;
							if (speedLbl != null)
								speedLbl.text = '0.5x';
							_applyPlaybackSpeed();
							_showStatus('Speed: 0.5x');
						}
					},
					{
						label: 'Speed 1.0x  (Normal)',
						sep: false,
						cb: () -> {
							_playbackSpeed = 1.0;
							if (speedLbl != null)
								speedLbl.text = '1.0x';
							_applyPlaybackSpeed();
							_showStatus('Speed: 1.0x');
						}
					},
					{
						label: 'Speed 1.5x',
						sep: false,
						cb: () -> {
							_playbackSpeed = 1.5;
							if (speedLbl != null)
								speedLbl.text = '1.5x';
							_applyPlaybackSpeed();
							_showStatus('Speed: 1.5x');
						}
					},
					{
						label: 'Speed 2.0x',
						sep: false,
						cb: () -> {
							_playbackSpeed = 2.0;
							if (speedLbl != null)
								speedLbl.text = '2.0x';
							_applyPlaybackSpeed();
							_showStatus('Speed: 2.0x');
						}
					},
				];
			case 3: [
					// Generate
					{label: 'Add Camera Follow Event', sep: false, cb: () -> _createEventAtPlayhead('Camera Follow', 'bf', 0)},
					{label: 'Add Camera Zoom Event', sep: false, cb: () -> _createEventAtPlayhead('Zoom Camera', '1.0', 0)},
					{label: 'Add Script Event', sep: false, cb: () -> _createEventAtPlayhead('Script', '', 3)},
					{label: '---', sep: true, cb: null},
					{label: 'Add Track', sep: false, cb: _addTrack},
				];
			case 4: [
					// Edit
					{label: 'Undo  Ctrl+Z', sep: false, cb: _doUndo},
					{label: 'Redo  Ctrl+Y', sep: false, cb: _doRedo},
					{label: '---', sep: true, cb: null},
					{label: 'Delete Selected  Del', sep: false, cb: _deleteSelected},
					{label: 'Duplicate Selected', sep: false, cb: _duplicateSelected},
				];
			case 5: [
					// Help
					{label: 'SPACE  Play/Pause', sep: false, cb: null},
					{label: 'R  Restart', sep: false, cb: null},
					{label: 'F  Free Camera', sep: false, cb: null},
					{label: 'C  Toggle Cam Proxy', sep: false, cb: null},
					{label: '0  Reset game zoom', sep: false, cb: null},
					{label: '[ / ]  Speed down/up', sep: false, cb: null},
					{label: 'Ctrl+Z/Y  Undo/Redo', sep: false, cb: null},
					{label: 'Ctrl+S / F5  Save', sep: false, cb: null},
					{label: 'Scroll  Pan timeline', sep: false, cb: null},
					{label: 'Ctrl+Scroll  Zoom timeline', sep: false, cb: null},
					{label: 'Scroll (game area)  Zoom', sep: false, cb: null},
					{label: 'Dbl-click track  New event', sep: false, cb: null},
					{label: 'Drag event  Move event', sep: false, cb: null},
					{label: 'Drag event right edge  Resize', sep: false, cb: null},
				];
			default: [];
		}

		var dd = new PSEDropdownPanel(bx, MENU_H, 200, items);
		dd.cameras = [camUI]; // camUI renders last → always on top of camGame viewport
		_menuDropdowns.push(dd);
		add(dd);
	}

	function _closeMenuDropdowns():Void {
		for (dd in _menuDropdowns) {
			remove(dd);
			dd.destroy();
		}
		_menuDropdowns = [];
		_activeMenu = -1;
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Top Transport Bar
	// ─────────────────────────────────────────────────────────────────────────
	function _buildTopBar():Void {
		var ty = MENU_H;
		topBg = new FlxSprite(0, ty).makeGraphic(SW, TOPBAR_H, C_TOPBAR);
		topBg.cameras = [camHUD];
		topBg.scrollFactor.set();
		add(topBg);
		var sep = new FlxSprite(0, ty + TOPBAR_H - 1).makeGraphic(SW, 1, C_BORDER);
		sep.cameras = [camHUD];
		sep.scrollFactor.set();
		sep.alpha = 0.6;
		add(sep);

		var bx = 6.0;
		var by = ty + 4.0;

		// Transport buttons
		restartBtn = _mkBtn(bx, by, '|<', 28, 29, C_PANEL, function() _onRestart());
		bx += 32;
		stopBtn = _mkBtn(bx, by, '[]', 28, 29, C_PANEL, function() _onStop());
		bx += 32;
		playBtn = _mkBtn(bx, by, '>', 36, 29, 0xFF1A3A1A, function() _onPlayPause());
		bx += 42;

		// Separator
		var s1 = new FlxSprite(bx, by + 3).makeGraphic(1, 22, C_BORDER);
		s1.cameras = [camHUD];
		s1.scrollFactor.set();
		add(s1);
		bx += 8;

		// Time display
		timeTxt = new FlxText(bx, by + 7, 140, '0:00.00 / 0:00.00', 11);
		timeTxt.setFormat(Paths.font('vcr.ttf'), 11, C_ACCENT, LEFT);
		timeTxt.cameras = [camHUD];
		timeTxt.scrollFactor.set();
		add(timeTxt);
		bx += 148;

		// Separator
		var s2 = new FlxSprite(bx, by + 3).makeGraphic(1, 22, C_BORDER);
		s2.cameras = [camHUD];
		s2.scrollFactor.set();
		add(s2);
		bx += 8;

		// Difficulty
		var dlbl = new FlxText(bx, by + 8, 0, 'DIFF:', 9);
		dlbl.setFormat(Paths.font('vcr.ttf'), 9, C_SUBTEXT, LEFT);
		dlbl.cameras = [camHUD];
		dlbl.scrollFactor.set();
		add(dlbl);
		bx += 30;
		var ddItems = allDiffs.length > 0 ? allDiffs : ['normal'];
		diffDropdown = new CoolDropDown(bx, by + 4, CoolDropDown.makeStrIdLabelArray(ddItems, true), function(id:String) {
			currentDiff = id;
			_rebuildEventBlocks();
			_refreshInspector();
			_showStatus('Dificultad: $id');
		});
		diffDropdown.selectedLabel = currentDiff;
		diffDropdown.cameras = [camHUD];
		diffDropdown.scrollFactor.set();
		add(diffDropdown);
		bx += 88;

		// Separator
		var s3 = new FlxSprite(bx, by + 3).makeGraphic(1, 22, C_BORDER);
		s3.cameras = [camHUD];
		s3.scrollFactor.set();
		add(s3);
		bx += 18;

		// Snap checkbox
		snapCheck = new CoolCheckBox(bx + 20, by + 7, null, null, 'Snap', 56);
		snapCheck.checked = true;
		snapCheck.callback = function(v:Bool) {
			_snapEnabled = v;
		};
		snapCheck.cameras = [camHUD];
		snapCheck.scrollFactor.set();
		add(snapCheck);
		bx += 92;

		// Separator
		var s4 = new FlxSprite(bx, by + 3).makeGraphic(1, 22, C_BORDER);
		s4.cameras = [camHUD];
		s4.scrollFactor.set();
		add(s4);
		bx += 8;

		// ── Playback speed control ──────────────────────────────────────────────
		var splbl = new FlxText(bx, by + 8, 32, 'SPD:', 9);
		splbl.setFormat(Paths.font('vcr.ttf'), 9, C_SUBTEXT, LEFT);
		splbl.cameras = [camHUD];
		splbl.scrollFactor.set();
		add(splbl);
		bx += 34;

		_mkBtn(bx, by, '<<', 22, 29, C_PANEL, function() _changeSpeed(-0.25));
		bx += 25;

		speedLbl = new FlxText(bx, by + 8, 34, '1.0x', 9);
		speedLbl.setFormat(Paths.font('vcr.ttf'), 9, C_ACCENT, CENTER);
		speedLbl.cameras = [camHUD];
		speedLbl.scrollFactor.set();
		add(speedLbl);
		bx += 36;

		_mkBtn(bx, by, '>>', 22, 29, C_PANEL, function() _changeSpeed(0.25));
		bx += 26;

		// Right-side controls
		var rbx = SW - INSP_W - 6.0;

		// Unsaved dot
		unsavedDot = new FlxSprite(rbx - 14, by + 10).makeGraphic(10, 10, C_UNSAVED);
		unsavedDot.cameras = [camHUD];
		unsavedDot.scrollFactor.set();
		unsavedDot.visible = false;
		add(unsavedDot);

		freeCamBtn = _mkBtn(rbx + 30, by, 'CAM', 36, 29, 0xFF1A2A3A, function() _toggleFreeCam());
		rbx -= 42;
		var saveB = _mkBtn(rbx + 30, by, 'SAV', 36, 29, 0xFF1A2A1A, function() _savePSEData());
		rbx -= 42;

		// Zoom label + slider
		var zlbl = new FlxText(rbx - 86, by + 8, 50, 'Zoom:', 9);
		zlbl.setFormat(Paths.font('vcr.ttf'), 9, C_SUBTEXT, RIGHT);
		zlbl.cameras = [camHUD];
		zlbl.scrollFactor.set();
		add(zlbl);
		zoomSlider = new PSESlider(rbx - 82, by + 11, 78, 0.005, 2.0, tlZoom, function(v:Float) {
			tlZoom = v;
			_rebuildRuler();
			_rebuildEventBlocks();
		});
		zoomSlider.cameras = [camHUD];
		zoomSlider.scrollFactor.set();
		add(zoomSlider);
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Timeline
	// ─────────────────────────────────────────────────────────────────────────
	function _buildTimeline():Void {
		// We create static bg elements here; ruler / tracks rebuild dynamically
		var tlY = _tlY();

		// TL background
		tlBg = new FlxSprite(0, tlY).makeGraphic(SW, _tlH() + 100, C_TL_BG);
		tlBg.cameras = [camHUD];
		tlBg.scrollFactor.set();
		add(tlBg);

		// Top separator
		var topSep = new FlxSprite(0, tlY).makeGraphic(SW, 2, C_ACCENT);
		topSep.cameras = [camHUD];
		topSep.scrollFactor.set();
		topSep.alpha = 0.5;
		add(topSep);

		// Ruler background
		tlRulerBg = new FlxSprite(0, tlY).makeGraphic(SW, TL_RULER_H, C_TL_RULER);
		tlRulerBg.cameras = [camHUD];
		tlRulerBg.scrollFactor.set();
		add(tlRulerBg);

		// Ruler bottom separator
		var rulSep = new FlxSprite(0, tlY + TL_RULER_H - 1).makeGraphic(SW, 1, C_BORDER);
		rulSep.cameras = [camHUD];
		rulSep.scrollFactor.set();
		rulSep.alpha = 0.5;
		add(rulSep);

		// Label column background
		tlLabelColBg = new FlxSprite(0, tlY + TL_RULER_H).makeGraphic(TL_LABEL_W, TL_MAX_TRACKS * TL_TRACK_H + 100, 0xFF0E0E1C);
		tlLabelColBg.cameras = [camHUD];
		tlLabelColBg.scrollFactor.set();
		add(tlLabelColBg);

		// Label col right border
		var lbSep = new FlxSprite(TL_LABEL_W - 1, tlY + TL_RULER_H).makeGraphic(1, TL_MAX_TRACKS * TL_TRACK_H + 100, C_BORDER);
		lbSep.cameras = [camHUD];
		lbSep.scrollFactor.set();
		lbSep.alpha = 0.6;
		add(lbSep);

		// Dynamic ruler / track / event elements
		_allocRulerLabels(220);
		_allocGridLines(220);
		_allocTrackRows();

		// Scrubber
		var scrY = tlY + TL_RULER_H + Std.int(Math.min(tracks.length, TL_MAX_TRACKS)) * TL_TRACK_H + 12;
		tlScrubBg = new FlxSprite(0, scrY).makeGraphic(SW, TL_SCRUB_H, 0xFF09091A);
		tlScrubBg.cameras = [camHUD];
		tlScrubBg.scrollFactor.set();
		add(tlScrubBg);
		var scrSep = new FlxSprite(0, scrY).makeGraphic(SW, 1, C_BORDER);
		scrSep.cameras = [camHUD];
		scrSep.scrollFactor.set();
		scrSep.alpha = 0.5;
		add(scrSep);

		// Waveform ticks (aesthetic)
		for (i in 0...100) {
			var tw = Std.int(SW / 100);
			var th = 3 + Std.int(Math.random() * (TL_SCRUB_H - 8));
			var ty2 = scrY + (TL_SCRUB_H - th) / 2;
			var tick = new FlxSprite(i * tw, ty2).makeGraphic(tw - 1, th, 0xFF162540);
			tick.cameras = [camHUD];
			tick.scrollFactor.set();
			tick.alpha = 0.8;
			add(tick);
		}

		tlScrubFill = new FlxSprite(0, scrY + 1).makeGraphic(1, TL_SCRUB_H - 2, 0xFF1A3C5C);
		tlScrubFill.cameras = [camHUD];
		tlScrubFill.scrollFactor.set();
		add(tlScrubFill);

		tlScrubHandle = new FlxSprite(0, scrY + TL_SCRUB_H / 2 - 8).makeGraphic(4, 16, C_PLAYHEAD);
		tlScrubHandle.cameras = [camHUD];
		tlScrubHandle.scrollFactor.set();
		add(tlScrubHandle);

		// Horizontal scrollbar
		tlHScrollBg = new FlxSprite(TL_LABEL_W,
			tlY + TL_RULER_H + Std.int(Math.min(tracks.length, TL_MAX_TRACKS)) * TL_TRACK_H).makeGraphic(_tlAreaW(), 12, 0xFF07071A);
		tlHScrollBg.cameras = [camHUD];
		tlHScrollBg.scrollFactor.set();
		add(tlHScrollBg);
		tlHScrollThumb = new FlxSprite(TL_LABEL_W,
			tlY + TL_RULER_H + Std.int(Math.min(tracks.length, TL_MAX_TRACKS)) * TL_TRACK_H + 2).makeGraphic(60, 8, C_ACCENT);
		tlHScrollThumb.cameras = [camHUD];
		tlHScrollThumb.scrollFactor.set();
		tlHScrollThumb.alpha = 0.5;
		add(tlHScrollThumb);

		// Playhead (red vertical line through ruler + tracks)
		var phH = TL_RULER_H + Std.int(Math.min(tracks.length, TL_MAX_TRACKS)) * TL_TRACK_H;
		tlPlayhead = new FlxSprite(TL_LABEL_W, tlY).makeGraphic(2, phH, C_PLAYHEAD);
		tlPlayhead.cameras = [camHUD];
		tlPlayhead.scrollFactor.set();
		tlPlayhead.alpha = 0.9;
		add(tlPlayhead);

		// Playhead triangle head
		tlPlayheadHead = new FlxSprite(TL_LABEL_W - 5, tlY).makeGraphic(12, 12, C_PLAYHEAD);
		tlPlayheadHead.cameras = [camHUD];
		tlPlayheadHead.scrollFactor.set();
		add(tlPlayheadHead);

		// Resize handle visual — lit right edge shown when hovering the resize zone
		_resizeHandleViz = new FlxSprite(0, 0).makeGraphic(4, TL_TRACK_H - 4, FlxColor.WHITE);
		_resizeHandleViz.cameras = [camHUD];
		_resizeHandleViz.scrollFactor.set();
		_resizeHandleViz.alpha = 0.75;
		_resizeHandleViz.visible = false;
		add(_resizeHandleViz);

		_rebuildRuler();
		_rebuildEventBlocks();
	}

	function _allocRulerLabels(n:Int):Void {
		for (i in 0...n) {
			var t = new FlxText(0, _tlY() + 4, 50, '', 9);
			t.setFormat(Paths.font('vcr.ttf'), 9, C_SUBTEXT, CENTER);
			t.cameras = [camHUD];
			t.scrollFactor.set();
			t.visible = false;
			rulerLabels.push(t);
			add(t);
		}
	}

	function _allocGridLines(n:Int):Void {
		for (i in 0...n) {
			var gl = new FlxSprite(0, _tlY() + TL_RULER_H).makeGraphic(1, TL_MAX_TRACKS * TL_TRACK_H, 0xFF1E1E38);
			gl.cameras = [camHUD];
			gl.scrollFactor.set();
			gl.visible = false;
			gridLines.push(gl);
			add(gl);
		}
	}

	function _allocTrackRows():Void {
		var tlY = _tlY();
		for (i in 0...TL_MAX_TRACKS) {
			var ty = tlY + TL_RULER_H + i * TL_TRACK_H;

			// Track area background
			var tbg = new FlxSprite(TL_LABEL_W, ty).makeGraphic(_tlAreaW(), TL_TRACK_H, C_TL_BG);
			tbg.cameras = [camHUD];
			tbg.scrollFactor.set();
			tbg.alpha = 0.9;
			trackBgs.push(tbg);
			add(tbg);

			// Track separator
			var tsep = new FlxSprite(0, ty + TL_TRACK_H - 1).makeGraphic(SW, 1, C_BORDER);
			tsep.cameras = [camHUD];
			tsep.scrollFactor.set();
			tsep.alpha = 0.2;
			add(tsep);

			// Color accent bar
			var tacc = new FlxSprite(0, ty + 3).makeGraphic(3, TL_TRACK_H - 6, 0xFF444466);
			tacc.cameras = [camHUD];
			tacc.scrollFactor.set();
			trackColors.push(tacc);
			add(tacc);

			// Track label
			var tlbl = new FlxText(18, ty + 8, TL_LABEL_W - 40, '', 9);
			tlbl.setFormat(Paths.font('vcr.ttf'), 9, C_SUBTEXT, LEFT);
			tlbl.cameras = [camHUD];
			tlbl.scrollFactor.set();
			trackLabels.push(tlbl);
			add(tlbl);

			// Lock button
			var lkBtn = _mkBtn(TL_LABEL_W - 22, ty + 6, '🔓', 16, 16, 0xFF0A0A1A, function() {});
			trackLocks.push(lkBtn);
		}

		_refreshTrackRows();
	}

	function _refreshTrackRows():Void {
		var tlY = _tlY();
		var visibleTracks = tracks.slice(_trackScrollY, _trackScrollY + TL_MAX_TRACKS);
		for (i in 0...TL_MAX_TRACKS) {
			var hasTrack = i < visibleTracks.length;
			if (trackBgs.length > i && trackBgs[i] != null)
				trackBgs[i].visible = hasTrack;
			if (trackColors.length > i && trackColors[i] != null) {
				trackColors[i].visible = hasTrack;
				if (hasTrack)
					trackColors[i].makeGraphic(3, TL_TRACK_H - 6, visibleTracks[i].color);
			}
			if (trackLabels.length > i && trackLabels[i] != null) {
				trackLabels[i].visible = hasTrack;
				if (hasTrack) {
					trackLabels[i].text = visibleTracks[i].name;
					trackLabels[i].color = visibleTracks[i].color;
					var ty = tlY + TL_RULER_H + i * TL_TRACK_H;
					trackLabels[i].y = ty + 9;
					trackColors[i].y = ty + 3;
				}
			}
			if (trackLocks.length > i && trackLocks[i] != null) {
				trackLocks[i].visible = hasTrack;
				if (hasTrack) {
					var ty = tlY + TL_RULER_H + i * TL_TRACK_H;
					var t = visibleTracks[i];
					final idx2 = i + _trackScrollY;
					trackLocks[i].y = ty + 6;
					trackLocks[i].label.text = t.locked ? '🔒' : '🔓';
					trackLocks[i].label.color = t.locked ? 0xFFFF6644 : C_SUBTEXT;
					// Reassign callback
					final tIdx = idx2;
					trackLocks[i].onClick = function() {
						tracks[tIdx].locked = !tracks[tIdx].locked;
						_refreshTrackRows();
					};
				}
			}
		}
	}

	function _rebuildRuler():Void {
		for (l in rulerLabels)
			l.visible = false;
		for (gl in gridLines)
			gl.visible = false;

		var tlY = _tlY();
		var areaW = _tlAreaW();
		var beatMs = Conductor.crochet;
		var startMs = tlScrollX;
		var endMs = startMs + areaW / tlZoom;
		var tracksH = Std.int(Math.min(tracks.length - _trackScrollY, TL_MAX_TRACKS)) * TL_TRACK_H;

		// ── Adaptive beat step ─────────────────────────────────────────────────
		// Prevent the label pool from being exhausted by skipping beats that
		// would render closer than MIN_PX_PER_LABEL pixels apart.
		var pixPerBeat = beatMs * tlZoom;
		var beatStep = 1;
		if (pixPerBeat < 30)
			beatStep = 4; // show bar-level only
		if (pixPerBeat < 8)
			beatStep = 16; // every 4 bars
		if (pixPerBeat < 2)
			beatStep = 64; // every 16 bars

		// Align start beat to the step boundary so labels always land on bars
		var beat = Std.int(Math.floor(startMs / beatMs) / beatStep) * beatStep;

		var li = 0;
		var gi = 0;

		while (beat * beatMs <= endMs + beatMs * beatStep && li < rulerLabels.length && gi < gridLines.length) {
			var xp = TL_LABEL_W + (beat * beatMs - startMs) * tlZoom;
			if (xp >= TL_LABEL_W && xp <= TL_LABEL_W + areaW) {
				var bar = Math.floor(beat / 4) + 1;
				var b = beat % 4;
				// Treat as bar-line whenever we're stepping by bars or the beat falls on one
				var isBar = (b == 0) || beatStep >= 4;

				var lbl = rulerLabels[li];
				lbl.text = isBar ? '$bar' : '$bar.${b + 1}';
				lbl.x = xp - 25;
				lbl.y = tlY + 4;
				lbl.color = isBar ? 0xFFCCCCEE : C_SUBTEXT;
				lbl.size = isBar ? 10 : 8;
				lbl.visible = true;
				li++;

				var gl = gridLines[gi];
				gl.x = xp;
				gl.y = tlY + TL_RULER_H;
				var glH = isBar ? tracksH : Std.int(tracksH * 0.5);
				gl.makeGraphic(1, glH > 0 ? glH : 1, isBar ? 0xFF2A2A4A : 0xFF1A1A34);
				gl.alpha = isBar ? 0.6 : 0.25;
				gl.visible = true;
				gi++;
			}
			beat += beatStep;
		}

		// Update ruler bg to cover only visible area
		if (tlRulerBg != null)
			tlRulerBg.y = tlY;
		if (tlBg != null)
			tlBg.y = tlY;
	}

	function _rebuildEventBlocks():Void {
		for (b in eventBlocks) {
			FlxTween.cancelTweensOf(b);
			remove(b);
			if (b.lblTxt != null) {
				remove(b.lblTxt);
				b.lblTxt.destroy();
			}
			b.destroy();
		}
		eventBlocks = [];
		if (pseData == null)
			return;

		var tlY = _tlY();
		var tracksY = tlY + TL_RULER_H;
		var areaW = _tlAreaW();
		var startMs = tlScrollX;
		var endMs = startMs + areaW / tlZoom;
		var visN = Std.int(Math.min(tracks.length - _trackScrollY, TL_MAX_TRACKS));

		for (evt in (pseData.events ?? [])) {
			if (!_evtForDiff(evt, currentDiff))
				continue;
			var trackI = evt.trackIndex - _trackScrollY;
			if (trackI < 0 || trackI >= visN)
				continue;
			if (!tracks[evt.trackIndex].visible)
				continue;

			var evtMs = Conductor.stepCrochet * evt.stepTime;
			var dur = (evt.duration != null && evt.duration > 0) ? evt.duration : 4.0;
			var endEvt = Conductor.stepCrochet * (evt.stepTime + dur);
			if (endEvt < startMs - 10 || evtMs > endMs + 10)
				continue;

			var xPos = TL_LABEL_W + (evtMs - startMs) * tlZoom;
			var wPx = Std.int(Math.max(10, dur * Conductor.stepCrochet * tlZoom));
			var yPos = tracksY + trackI * TL_TRACK_H + 2;
			var col = tracks[evt.trackIndex].color;
			var isSel = (evt.id == selectedEventId);

			var block = new PSEEventBlock(xPos, yPos, wPx, TL_TRACK_H - 4, col, evt.id, isSel, evt.type);
			block.cameras = [camHUD];
			block.scrollFactor.set();
			eventBlocks.push(block);
			add(block);

			// Label text
			var lblStr = (evt.label != null && evt.label != '') ? evt.label : evt.type;
			var lbl = new FlxText(xPos + 5, yPos + 5, Std.int(Math.max(10, wPx - 8)), lblStr, 8);
			lbl.setFormat(Paths.font('vcr.ttf'), 8, isSel ? FlxColor.WHITE : 0xFFBBBBCC, LEFT);
			lbl.cameras = [camHUD];
			lbl.scrollFactor.set();
			lbl.clipRect = null;
			block.lblTxt = lbl;
			add(lbl);
		}

		// Script blocks on script track
		for (scr in (pseData.scripts ?? [])) {
			if (!_scrForDiff(scr, currentDiff) || !scr.enabled)
				continue;
			// Find script track index
			var trackI = _getScriptTrackVisualIdx();
			if (trackI < 0)
				continue;

			var scrMs = scr.triggerStep >= 0 ? Conductor.stepCrochet * scr.triggerStep : -1;
			if (scrMs < 0 || scrMs < startMs - 10 || scrMs > endMs + 10)
				continue;

			var xPos = TL_LABEL_W + (scrMs - startMs) * tlZoom;
			var yPos = _tlY() + TL_RULER_H + trackI * TL_TRACK_H + 2;
			var col = 0xFFCC44FF;

			var block = new PSEEventBlock(xPos, yPos, 36, TL_TRACK_H - 4, col, 'script_' + scr.id, false, '[S] ' + scr.name);
			block.cameras = [camHUD];
			block.scrollFactor.set();
			block.isScriptBlock = true;
			eventBlocks.push(block);
			add(block);

			var lbl = new FlxText(xPos + 5, yPos + 5, 80, scr.name, 8);
			lbl.setFormat(Paths.font('vcr.ttf'), 8, 0xFFCCBBFF, LEFT);
			lbl.cameras = [camHUD];
			lbl.scrollFactor.set();
			block.lblTxt = lbl;
			add(lbl);
		}
	}

	function _getScriptTrackVisualIdx():Int {
		for (i in 0...tracks.length)
			if (tracks[i].id == 'script')
				return i - _trackScrollY;
		return -1;
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Inspector (right panel)
	// ─────────────────────────────────────────────────────────────────────────
	function _buildInspector():Void {
		var ix = SW - INSP_W;
		// Background
		inspBg = new FlxSprite(ix, HEADER_H).makeGraphic(INSP_W, SH - HEADER_H - STATUS_H, C_INSP);
		inspBg.cameras = [camHUD];
		inspBg.scrollFactor.set();
		add(inspBg);
		var ibSep = new FlxSprite(ix, HEADER_H).makeGraphic(2, SH - HEADER_H - STATUS_H, C_ACCENT);
		ibSep.cameras = [camHUD];
		ibSep.scrollFactor.set();
		ibSep.alpha = 0.3;
		add(ibSep);

		// Inspector title
		inspTitle = new FlxText(ix + 8, HEADER_H + 6, INSP_W - 16, 'Inspector', 11);
		inspTitle.setFormat(Paths.font('vcr.ttf'), 11, C_ACCENT, LEFT);
		inspTitle.cameras = [camHUD];
		inspTitle.scrollFactor.set();
		add(inspTitle);

		var titleSep = new FlxSprite(ix, HEADER_H + 22).makeGraphic(INSP_W, 1, C_BORDER);
		titleSep.cameras = [camHUD];
		titleSep.scrollFactor.set();
		titleSep.alpha = 0.5;
		add(titleSep);

		_refreshInspector();
	}

	function _refreshInspector():Void {
		// Destroy old inspector elements
		for (el in _inspElements) {
			remove(el);
			el.destroy();
		}
		_inspElements = [];

		var ix = SW - INSP_W + 8;
		var iy = HEADER_H + 28.0;

		if (selectedEventId == '') {
			_iLabel('No event selected.', ix, iy, C_ACCENT, INSP_W - 16, 10);
			iy += 18;
			_iSep(ix, iy, INSP_W - 16);
			iy += 10;

			// ── Tips panel ────────────────────────────────────────────────────
			_iLabel('TIPS & SHORTCUTS', ix, iy, C_ACCENT2, INSP_W - 16, 9);
			iy += 16;

			final tips:Array<String> = [
				'SPACE  Play / Pause',
				'R      Restart from start',
				'F      Toggle Free Camera',
				'C      Toggle Camera Proxy',
				'0      Reset zoom to 100%',
				'[ / ]  Speed down / up',
				'Del    Delete selected event',
				'Ctrl+Z / Y   Undo / Redo',
				'Ctrl+S / F5  Save',
				'',
				'Scroll (game area)',
				'  -> Zoom in/out',
				'Ctrl+Scroll (timeline)',
				'  -> Zoom timeline',
				'',
				'Double-click a track',
				'  -> Create new event',
				'Right-click a track',
				'  -> Context menu',
				'Drag event block',
				'  -> Move in time/track',
				'Drag event right edge',
				'  -> Resize duration',
				'',
				'Camera proxy frame',
				'  shows where PlayState',
				'  camera is looking.',
				'  Zoom out to see it.',
			];

			for (tip in tips) {
				if (tip == '') {
					iy += 4;
					continue;
				}
				var col = tip.startsWith(' ') ? C_SUBTEXT : C_TEXT;
				var sz = 8;
				_iLabel(tip, ix, iy, col, INSP_W - 16, sz);
				iy += 13;
			}
			return;
		}

		// Find selected event
		var selEvt:PSEEvent = null;
		for (e in (pseData.events ?? []))
			if (e.id == selectedEventId) {
				selEvt = e;
				break;
			}

		if (selEvt == null) {
			// Check if it's a script block
			var scrId = selectedEventId.startsWith('script_') ? selectedEventId.substr(7) : '';
			var selScr:PSEScript = null;
			for (s in (pseData.scripts ?? []))
				if (s.id == scrId) {
					selScr = s;
					break;
				}
			if (selScr != null) {
				_buildScriptInspector(selScr, ix, iy);
				return;
			}
			_iLabel('Event not found', ix, iy, C_SUBTEXT, INSP_W - 16);
			return;
		}

		_buildEventInspector(selEvt, ix, iy);
	}

	function _buildEventInspector(evt:PSEEvent, ix:Float, iy:Float):Void {
		var iw = INSP_W - 16;
		var ty = iy;

		// Event type header
		var hdr = _iLabel(evt.type, ix, ty, C_ACCENT, iw, 12);
		ty += 20;
		var sep1 = _iSep(ix, ty, iw);
		ty += 8;

		// Event type dropdown
		_iLabel('Event Type:', ix, ty, C_SUBTEXT, iw);
		ty += 14;
		var etypes = _getEventTypes();
		ipEventType = _iDropdown(ix, ty, iw, etypes, evt.type, function(id:String) {
			var i = Std.parseInt(id);
			if (i != null && i >= 0 && i < etypes.length)
				evt.type = etypes[i];
			_pushUndo();
			_rebuildEventBlocks();
			_showStatus('Type → ${evt.type}');
		});
		ty += 28;

		// Label
		_iLabel('Label:', ix, ty, C_SUBTEXT, iw);
		ty += 13;
		ipEventLabel = _iInput(ix, ty, iw, evt.label ?? '', function(v:String) {
			evt.label = v;
			hasUnsaved = true;
			_updateUnsavedDot();
		});
		ty += 26;

		// Value
		_iLabel('Value (v1|v2):', ix, ty, C_SUBTEXT, iw);
		ty += 13;
		ipEventValue = _iInput(ix, ty, iw, evt.value ?? '', function(v:String) {
			evt.value = v;
			hasUnsaved = true;
			_updateUnsavedDot();
		});
		ty += 26;

		var sep2 = _iSep(ix, ty, iw);
		ty += 8;

		// Camera-specific section
		if (evt.type.toLowerCase().contains('camera') || evt.type.toLowerCase().contains('zoom')) {
			_buildCamEventSection(evt, ix, ty, iw);
			ty += 170;
			var sep3 = _iSep(ix, ty, iw);
			ty += 8;
		}

		// Step + Duration
		_iLabel('Step Time:', ix, ty, C_SUBTEXT, Std.int(iw / 2 - 4));
		ty += 13;
		ipEventStep = _iStepper(ix, ty, Std.int(iw / 2 - 4), evt.stepTime, 0, 99999, 1, function(v:Float) {
			evt.stepTime = v;
			_pushUndo();
			_rebuildEventBlocks();
		});
		_iLabel('Duration (steps):', ix + iw / 2, ty - 13, C_SUBTEXT, Std.int(iw / 2));
		ipEventDur = _iStepper(ix + iw / 2, ty, Std.int(iw / 2), evt.duration ?? 4.0, 1, 9999, 1, function(v:Float) {
			evt.duration = v;
			_pushUndo();
			_rebuildEventBlocks();
		});
		ty += 26;

		// At-playhead button
		var athBtn = _iBtn(ix, ty, 'Set to Playhead', 0xFF1A2A3A, function() {
			var step = Conductor.songPosition / Conductor.stepCrochet;
			evt.stepTime = _snapEnabled ? Math.round(step) : step;
			if (ipEventStep != null)
				ipEventStep.value = evt.stepTime;
			_pushUndo();
			_rebuildEventBlocks();
			_showStatus('Step → ${Std.int(evt.stepTime)}');
		}, iw);
		ty += 28;

		// Track
		_iLabel('Track (0-${tracks.length - 1}):', ix, ty, C_SUBTEXT, iw);
		ty += 13;
		ipEventTrack = _iStepper(ix, ty, iw, evt.trackIndex, 0, tracks.length - 1, 1, function(v:Float) {
			evt.trackIndex = Std.int(v);
			_pushUndo();
			_rebuildEventBlocks();
		});
		ty += 26;

		var sep4 = _iSep(ix, ty, iw);
		ty += 8;

		// Difficulty checkboxes
		_iLabel('Difficulties:', ix, ty, C_SUBTEXT, iw);
		ty += 14;
		var dx = ix;
		ipEventDiffChecks = [];
		for (diff in allDiffs.concat(['*'])) {
			var chk = new CoolCheckBox(dx, ty, null, null, diff == '*' ? 'all' : diff, 56);
			chk.checked = evt.difficulties.contains('*') ? (diff == '*') : evt.difficulties.contains(diff);
			chk.cameras = [camHUD];
			chk.scrollFactor.set();
			add(chk);
			_inspElements.push(chk);
			ipEventDiffChecks.push(chk);
			dx += 60;
			if (dx > SW - INSP_W + iw + 4) {
				dx = ix;
				ty += 22;
			}
		}
		ty += 26;

		var sep5 = _iSep(ix, ty, iw);
		ty += 8;

		// Action buttons
		var addBtn = _iBtn(ix, ty, 'UPDATE EVENT', 0xFF1A3A1A, function() {
			var diffs:Array<String> = [];
			for (i in 0...ipEventDiffChecks.length) {
				var d = (i < allDiffs.length) ? allDiffs[i] : '*';
				if (ipEventDiffChecks[i].checked) {
					if (d == '*') {
						diffs = ['*'];
						break;
					}
					diffs.push(d);
				}
			}
			evt.difficulties = diffs.length > 0 ? diffs : ['*'];
			_pushUndo();
			_rebuildSorted();
			_rebuildEventBlocks();
			hasUnsaved = true;
			_updateUnsavedDot();
			_showStatus('✓ Event updated: ${evt.type}');
		}, Std.int(iw / 2 - 4));
		var delBtn = _iBtn(ix + iw / 2 + 4, ty, 'DELETE', 0xFF3A1A1A, function() _deleteSelected(), Std.int(iw / 2 - 4));
		ty += 28;

		// Open script editor button for script events
		if (evt.type.toLowerCase() == 'script') {
			var scrEdBtn = _iBtn(ix, ty, 'Open Script Editor', 0xFF1A1A3A, function() {
				openSubState(new ScriptEditorSubState(PlayState.SONG, evt.value, camHUD));
			}, iw);
			ty += 28;
		}
	}

	function _buildCamEventSection(evt:PSEEvent, ix:Float, ty:Float, iw:Int):Void {
		_iLabel('── Camera Properties ──', ix, ty, C_ACCENT, iw, 9);
		ty += 14;

		// Zoom
		_iLabel('Zoom:', ix, ty, C_SUBTEXT, Std.int(iw / 2));
		ty += 13;
		var zoomVal = 1.0;
		if (evt.value != null && evt.value != '') {
			var pz = Std.parseFloat(evt.value.split('|')[0]);
			if (!Math.isNaN(pz))
				zoomVal = pz;
		}
		ipCamZoom = _iStepper(ix, ty, Std.int(iw - 30), zoomVal, 0.1, 5.0, 0.1, function(v:Float) {
			var parts = (evt.value ?? '1.0').split('|');
			parts[0] = Std.string(v);
			evt.value = parts.join('|');
			hasUnsaved = true;
			_updateUnsavedDot();
		});
		// Zoom slider (visual like the screenshot)
		var zsld = new PSESlider(ix, ty + 22, iw - 10, 0.1, 3.0, zoomVal, function(v:Float) {
			var sv = Math.round(v * 10) / 10.0;
			ipCamZoom.value = sv;
			var parts = (evt.value ?? '1.0').split('|');
			parts[0] = Std.string(sv);
			evt.value = parts.join('|');
			hasUnsaved = true;
			_updateUnsavedDot();
		});
		zsld.cameras = [camHUD];
		zsld.scrollFactor.set();
		add(zsld);
		_inspElements.push(zsld);
		ty += 44;

		// Mode dropdown
		_iLabel('Mode:', ix, ty, C_SUBTEXT, iw);
		ty += 13;
		final camModes = ['Stage Zoom', 'UI Zoom', 'Both'];
		ipCamMode = _iDropdown(ix, ty, iw, camModes, 'Stage Zoom', null);
		ty += 28;

		// Duration
		_iLabel('Duration:', ix, ty, C_SUBTEXT, iw);
		ty += 13;
		var durVal = evt.duration ?? 10.0;
		ipCamDuration = _iStepper(ix, ty, iw, durVal, 1, 999, 1, function(v:Float) {
			evt.duration = v;
			hasUnsaved = true;
			_updateUnsavedDot();
			_rebuildEventBlocks();
		});
		ty += 26;

		// Ease type + dir side by side
		_iLabel('Ease Type:', ix, ty, C_SUBTEXT, Std.int(iw / 2));
		ty += 13;
		final easeTypes = [
			'linear',
			'quad',
			'cube',
			'quart',
			'quint',
			'sine',
			'expo',
			'circ',
			'elastic',
			'bounce',
			'back'
		];
		final easeDirs = ['In', 'Out', 'InOut'];
		ipCamEaseType = _iDropdown(ix, ty, Std.int(iw / 2 - 2), easeTypes, 'expo', null);
		_iLabel('Direction:', ix + iw / 2, ty - 13, C_SUBTEXT, Std.int(iw / 2));
		ipCamEaseDir = _iDropdown(ix + iw / 2, ty, Std.int(iw / 2 - 2), easeDirs, 'Out', null);
		ty += 28;

		// Ease curve preview (64x64 canvas)
		_drawEaseCurve(ix, ty, iw);
	}

	function _drawEaseCurve(ix:Float, ty:Float, iw:Int):Void {
		var w = 64;
		var h = 64;
		var cs = new FlxSprite(ix + iw / 2 - w / 2, ty).makeGraphic(w, h, 0xFF0A0A18, true);
		// Draw a simple ease-out curve
		for (xi in 0...w) {
			var t = xi / w;
			var yt = 1 - (1 - t) * (1 - t); // ease-out quad
			var yi = Std.int((1 - yt) * (h - 4) + 2);
			flixel.util.FlxSpriteUtil.drawRect(cs, xi, yi, 1, h - yi - 2, C_ACCENT);
		}
		// Border
		flixel.util.FlxSpriteUtil.drawRect(cs, 0, 0, w, 1, C_BORDER);
		flixel.util.FlxSpriteUtil.drawRect(cs, 0, h - 1, w, 1, C_BORDER);
		flixel.util.FlxSpriteUtil.drawRect(cs, 0, 0, 1, h, C_BORDER);
		flixel.util.FlxSpriteUtil.drawRect(cs, w - 1, 0, 1, h, C_BORDER);
		cs.cameras = [camHUD];
		cs.scrollFactor.set();
		ipCamCurve = cs;
		add(cs);
		_inspElements.push(cs);
	}

	function _buildScriptInspector(scr:PSEScript, ix:Float, ty:Float):Void {
		var iw = INSP_W - 16;
		_iLabel('Script: ${scr.name}', ix, ty, C_ACCENT, iw, 11);
		ty += 20;
		_iSep(ix, ty, iw);
		ty += 8;

		_iLabel('Name:', ix, ty, C_SUBTEXT, iw);
		ty += 13;
		ipScrName = _iInput(ix, ty, iw, scr.name, function(v:String) {
			scr.name = v;
			hasUnsaved = true;
			_updateUnsavedDot();
		});
		ty += 26;

		_iLabel('Trigger Step (-1 = manual):', ix, ty, C_SUBTEXT, iw);
		ty += 13;
		ipScrStep = _iStepper(ix, ty, iw, scr.triggerStep, -1, 99999, 1, function(v:Float) {
			scr.triggerStep = v;
			hasUnsaved = true;
			_updateUnsavedDot();
			_rebuildEventBlocks();
		});
		ty += 26;

		ipScrAuto = _iCheckbox(ix, ty, 'Auto-trigger on step', scr.autoTrigger, function(v:Bool) {
			scr.autoTrigger = v;
		});
		ty += 22;
		ipScrEnabled = _iCheckbox(ix, ty, 'Enabled', scr.enabled, function(v:Bool) {
			scr.enabled = v;
			_rebuildEventBlocks();
		});
		ty += 26;

		_iSep(ix, ty, iw);
		ty += 8;

		// ── Save Location ────────────────────────────────────────────────────
		_iLabel('Save Location:', ix, ty, C_SUBTEXT, iw);
		ty += 13;
		var saveLocItems = [
			{id: 'inline', label: 'Inline (PSE JSON)'},
			{id: 'song', label: 'Song Scripts'},
			{id: 'events', label: 'Event Scripts'},
			{id: 'global', label: 'Global Scripts'},
			{id: 'custom', label: 'Custom Path...'},
		];
		var curLoc = scr.savePath ?? 'inline';
		// Si savePath es una ruta literal (no una clave conocida), mostramos 'custom'
		if (curLoc != 'inline' && curLoc != 'song' && curLoc != 'events' && curLoc != 'global')
			curLoc = 'custom';

		// Texto descriptivo de la ruta resuelta
		var resolvedPath = _resolveSavePath(scr);
		var pathHint = resolvedPath ?? '(embebido en PSE JSON)';

		var pathHintTxt = _iLabel(pathHint, ix, ty + 42, 0xFF777799, iw, 8);

		var locDD = new CoolDropDown(ix, ty, saveLocItems.map(function(it) return {name: it.id, label: it.label}), function(id:String) {
			if (id == 'custom') {
				// Si ya tiene una ruta literal, la mantenemos; si no, preset
				if (scr.savePath == null || scr.savePath == '' || scr.savePath == 'inline' || scr.savePath == 'song' || scr.savePath == 'events'
					|| scr.savePath == 'global')
					scr.savePath = 'assets/songs/$currentSong/scripts/${scr.name}.hx';
			} else {
				scr.savePath = id;
			}
			hasUnsaved = true;
			_updateUnsavedDot();
			var rp = _resolveSavePath(scr);
			pathHintTxt.text = rp ?? '(embebido en PSE JSON)';
			_refreshInspector();
		});
		locDD.selectedId = curLoc;
		locDD.cameras = [camHUD];
		locDD.scrollFactor.set();
		add(locDD);
		_inspElements.push(locDD);
		ty += 26;

		// Hint de ruta (ya añadido arriba con ty+42 adelantado)
		ty += 20;

		// Input de ruta custom (solo visible si savePath es ruta literal)
		var isCustom = (scr.savePath != null && scr.savePath != 'inline' && scr.savePath != 'song' && scr.savePath != 'events' && scr.savePath != 'global');
		if (isCustom) {
			_iLabel('Ruta custom:', ix, ty, C_SUBTEXT, iw);
			ty += 13;
			var pathInp = _iInput(ix, ty, iw, scr.savePath ?? '', function(v:String) {
				scr.savePath = v;
				var rp2 = _resolveSavePath(scr);
				pathHintTxt.text = rp2 ?? '(embebido en PSE JSON)';
				hasUnsaved = true;
				_updateUnsavedDot();
			});
			ty += 26;
		}

		_iSep(ix, ty, iw);
		ty += 8;

		// ── Previsualización del código ──────────────────────────────────────
		_iLabel('HScript Code (previsualización):', ix, ty, C_SUBTEXT, iw);
		ty += 13;
		// Si hay archivo, intentar leer las primeras líneas de él
		var codePreview = _loadScriptCode(scr);
		var preview = codePreview.length > 120 ? codePreview.substr(0, 120) + '...' : codePreview;
		_iLabel(preview, ix, ty, 0xFF9988CC, iw, 8);
		ty += 70;

		_iSep(ix, ty, iw);
		ty += 8;

		// ── Botones de acción ────────────────────────────────────────────────
		var savedLoc = scr.savePath ?? 'inline';

		// Abrir editor de código
		_iBtn(ix, ty, 'Open Full Script Editor', 0xFF1A1A3A, function() {
			var onSaveCb = function(code:String) {
				// Actualizar código inline como caché siempre
				scr.code = code;
				hasUnsaved = true;
				_updateUnsavedDot();
				// Si apunta a fichero, guardarlo en disco
				#if sys
				var rp = _resolveSavePath(scr);
				if (rp != null) {
					try {
						var dir = haxe.io.Path.directory(rp);
						if (dir != '' && !sys.FileSystem.exists(dir))
							sys.FileSystem.createDirectory(dir);
						sys.io.File.saveContent(rp, code);
						_showStatus('[SAVED] Script saved: $rp', 3.0);
					} catch (ex:Dynamic) {
						_showStatus('⚠ Error al guardar: $ex', 4.0);
					}
				}
				#end
				// Invalidar instancia en caché para que se recargue con el nuevo código
				var old = scriptInstances.get(scr.id);
				if (old != null) {
					old.active = false;
					scriptInstances.remove(scr.id);
				}
			};
			openSubState(new ScriptEditorSubState(PlayState.SONG, scr.name, camHUD, _loadScriptCode(scr), onSaveCb));
		}, iw);
		ty += 28;

		// Guardar al archivo ahora (solo si no es inline)
		if (savedLoc != 'inline' && savedLoc != '' && savedLoc != null) {
			_iBtn(ix, ty, 'Save to File Now', 0xFF1A2A1A, function() {
				#if sys
				var rp = _resolveSavePath(scr);
				if (rp != null) {
					try {
						var dir = haxe.io.Path.directory(rp);
						if (dir != '' && !sys.FileSystem.exists(dir))
							sys.FileSystem.createDirectory(dir);
						sys.io.File.saveContent(rp, scr.code ?? '');
						_showStatus('[OK] Saved: $rp', 3.0);
					} catch (ex:Dynamic) {
						_showStatus('⚠ Error: $ex', 4.0);
					}
				}
				#else
				_showStatus('[ERR] File IO not available en esta plataforma');
				#end
			}, iw);
			ty += 28;
		}

		_iBtn(ix, ty, '> Test Run Now', 0xFF1A2A1A, function() _runScript(scr), iw);
		ty += 28;
		_iBtn(ix, ty, 'DELETE Script', 0xFF3A1A1A, function() {
			_deleteSelected();
		}, iw);
	}

	// Inspector builder helpers
	function _iLabel(text:String, x:Float, y:Float, col:Int, w:Int, ?size:Int = 10):FlxText {
		var t = new FlxText(x, y, w, text, size);
		t.setFormat(Paths.font('vcr.ttf'), size, col, LEFT);
		t.cameras = [camHUD];
		t.scrollFactor.set();
		add(t);
		_inspElements.push(t);
		return t;
	}

	function _iSep(x:Float, y:Float, w:Int):FlxSprite {
		var s = new FlxSprite(x, y).makeGraphic(w, 1, C_BORDER);
		s.alpha = 0.35;
		s.cameras = [camHUD];
		s.scrollFactor.set();
		add(s);
		_inspElements.push(s);
		return s;
	}

	function _iInput(x:Float, y:Float, w:Int, val:String, ?onChange:String->Void):CoolInputText {
		var inp = new CoolInputText(x, y, w, val, 10);
		if (onChange != null)
			inp.callback = function(text:String, _:String) onChange(text);
		inp.cameras = [camHUD];
		inp.scrollFactor.set();
		add(inp);
		_inspElements.push(inp);
		return inp;
	}

	function _iStepper(x:Float, y:Float, w:Int, val:Float, min:Float, max:Float, step:Float, ?onChange:Float->Void):CoolNumericStepper {
		var sp = new CoolNumericStepper(x, y, step, val, min, max, 2);
		if (onChange != null)
			sp.value_change = onChange;
		sp.cameras = [camHUD];
		sp.scrollFactor.set();
		add(sp);
		_inspElements.push(sp);
		return sp;
	}

	function _iDropdown(x:Float, y:Float, w:Int, items:Array<String>, selected:String, ?onChange:String->Void):CoolDropDown {
		var dd = new CoolDropDown(x, y, CoolDropDown.makeStrIdLabelArray(items, true), onChange);
		dd.selectedLabel = selected;
		dd.cameras = [camHUD];
		dd.scrollFactor.set();
		add(dd);
		_inspElements.push(dd);
		return dd;
	}

	function _iCheckbox(x:Float, y:Float, label:String, checked:Bool, ?onChange:Bool->Void):CoolCheckBox {
		var chk = new CoolCheckBox(x, y, null, null, label, 200);
		chk.checked = checked;
		if (onChange != null)
			chk.callback = onChange;
		chk.cameras = [camHUD];
		chk.scrollFactor.set();
		add(chk);
		_inspElements.push(chk);
		return chk;
	}

	function _iBtn(x:Float, y:Float, label:String, col:Int, cb:Void->Void, ?w:Int = 120):PSEBtn {
		var btn = new PSEBtn(x, y, w, 22, label, col, C_TEXT, cb);
		btn.cameras = [camHUD];
		btn.scrollFactor.set();
		btn.label.cameras = [camHUD];
		btn.label.scrollFactor.set();
		add(btn);
		add(btn.label);
		_inspElements.push(btn);
		_inspElements.push(btn.label);
		return btn;
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Status Bar
	// ─────────────────────────────────────────────────────────────────────────
	function _buildStatusBar():Void {
		var sy = SH - STATUS_H;
		statusBg = new FlxSprite(0, sy).makeGraphic(SW, STATUS_H, C_MENU);
		statusBg.cameras = [camHUD];
		statusBg.scrollFactor.set();
		add(statusBg);
		var stSep = new FlxSprite(0, sy).makeGraphic(SW, 1, C_BORDER);
		stSep.cameras = [camHUD];
		stSep.scrollFactor.set();
		stSep.alpha = 0.5;
		add(stSep);

		statusTxt = new FlxText(8, sy + 4, SW / 2, '', 9);
		statusTxt.setFormat(Paths.font('vcr.ttf'), 9, C_SUBTEXT, LEFT);
		statusTxt.cameras = [camHUD];
		statusTxt.scrollFactor.set();
		add(statusTxt);

		cursorInfoTxt = new FlxText(SW / 2, sy + 4, SW / 2 - 8, '', 9);
		cursorInfoTxt.setFormat(Paths.font('vcr.ttf'), 9, C_SUBTEXT, RIGHT);
		cursorInfoTxt.cameras = [camHUD];
		cursorInfoTxt.scrollFactor.set();
		add(cursorInfoTxt);
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Update
	// ─────────────────────────────────────────────────────────────────────────
	override public function update(elapsed:Float):Void {
		super.update(elapsed);

		if (autoSeekTime >= 0) {
			_doSeek(autoSeekTime);
			autoSeekTime = -1;
		}

		// Sync conductor
		if (isPlaying && FlxG.sound.music != null && FlxG.sound.music.playing) {
			var mt = FlxG.sound.music.time;
			Conductor.songPosition = (mt < Conductor.songPosition - 120 && mt > 0) ? Conductor.songPosition + FlxG.elapsed * 1000 : mt;

			var curBeat = Math.floor(Conductor.songPosition / Conductor.crochet);
			var curStep = Math.floor(Conductor.songPosition / Conductor.stepCrochet);
			if (curStep != _lastStep) {
				_lastStep = curStep;
				_onStepHit(curStep);
			}
			if (curBeat != _lastBeat) {
				_lastBeat = curBeat;
				_onBeatHit(curBeat);
			}

			_fireEditorEvents();
		}

		if (cameraController != null)
			cameraController.update(elapsed);
		if (characterController != null)
			characterController.update(elapsed);

		_updatePlayhead();
		_handleTimelineInput();
		_handleEventInteraction();
		_handleFreeCam(elapsed);
		_updateCamProxy();
		_updateTimeDisplay();
		_updateCursorInfo();

		if (_statusTimer > 0) {
			_statusTimer -= elapsed;
			if (_statusTimer <= 0)
				statusTxt.text = '';
		}

		// Menu dropdowns close on click outside
		if (FlxG.mouse.justPressed && _menuDropdowns.length > 0) {
			var overAny = false;
			for (dd in _menuDropdowns)
				if (FlxG.mouse.overlaps(dd, camHUD)) {
					overAny = true;
					break;
				}
			for (mb in menuItems)
				if (FlxG.mouse.overlaps(mb, camHUD)) {
					overAny = true;
					break;
				}
			if (!overAny)
				_closeMenuDropdowns();
		}

		// Menu button hover update
		for (mb in menuItems)
			mb.updateInput();

		// Context menu
		if (_ctxMenu != null) {
			_ctxMenu.updateInput();
			if (_ctxMenu.closed) {
				remove(_ctxMenu);
				_ctxMenu.destroy();
				_ctxMenu = null;
			}
		}

		_handleKeys();
	}

	function _onBeatHit(beat:Int):Void {
		if (characterController != null)
			characterController.danceOnBeat(beat);
		if (uiManager != null)
			uiManager.onBeatHit(beat);
		if (currentStage != null)
			currentStage.beatHit(beat);
		// Scripts PSE inline
		for (k in scriptInstances.keys()) {
			var inst = scriptInstances.get(k);
			if (inst != null && inst.active)
				inst.call('onBeatHit', [beat]);
		}
		// Scripts de la canción y globales
		ScriptHandler._argsBeat[0] = beat;
		try {
			ScriptHandler.callOnScripts('onBeatHit', ScriptHandler._argsBeat);
		} catch (e:Dynamic) {
			_showStatus('[SCRIPT ERR] onBeatHit: $e', 4.0);
		}
	}

	function _onStepHit(step:Int):Void {
		if (uiManager != null)
			uiManager.onStepHit(step);
		// Scripts PSE inline
		for (k in scriptInstances.keys()) {
			var inst = scriptInstances.get(k);
			if (inst != null && inst.active)
				inst.call('onStepHit', [step]);
		}
		// Scripts de la canción y globales
		ScriptHandler._argsStep[0] = step;
		try {
			ScriptHandler.callOnScripts('onStepHit', ScriptHandler._argsStep);
		} catch (e:Dynamic) {
			_showStatus('[SCRIPT ERR] onStepHit @$step: $e', 4.0);
		}
	}

	function _fireEditorEvents():Void {
		var posMs = Conductor.songPosition;

		// ── Canto de personajes sincronizado con el chart ─────────────────────
		while (_nextNoteIdx < _chartNotes.length && _chartNotes[_nextNoteIdx].time <= posMs) {
			var n = _chartNotes[_nextNoteIdx++];
			if (characterController != null) {
				if (n.isGF)
					characterController.singGF(n.direction);
				else if (n.isPlayer)
					characterController.singByIndex(characterController.findPlayerIndex(), n.direction);
				else
					characterController.singByIndex(characterController.findOpponentIndex(), n.direction);
			}
		}

		// ── Eventos del chart (cargados de SONG por EventManager) ─────────────
		try {
			EventManager.update(posMs);
		} catch (e:Dynamic) {
			_showStatus('[SCRIPT ERR] EventManager: $e', 4.0);
		}

		// ── Notificar onUpdate a scripts de la canción ────────────────────────
		ScriptHandler._argsUpdate[0] = FlxG.elapsed;
		try {
			ScriptHandler.callOnNonStageScripts('onUpdate', ScriptHandler._argsUpdate);
		} catch (e:Dynamic) {
			_showStatus('[SCRIPT ERR] onUpdate: $e', 4.0);
		}

		// ── Eventos PSE (propios del editor) ──────────────────────────────────
		while (_nextEventIdx < sortedEvents.length) {
			var e = sortedEvents[_nextEventIdx];
			if (!_evtForDiff(e, currentDiff)) {
				_nextEventIdx++;
				continue;
			}
			if (Conductor.stepCrochet * e.stepTime > posMs)
				break;
			_triggerEvent(e);
			_nextEventIdx++;
		}
		while (_nextScriptIdx < sortedScripts.length) {
			var s = sortedScripts[_nextScriptIdx];
			if (!s.enabled || !s.autoTrigger || !_scrForDiff(s, currentDiff)) {
				_nextScriptIdx++;
				continue;
			}
			if (s.triggerStep < 0 || Conductor.stepCrochet * s.triggerStep > posMs)
				break;
			_runScript(s);
			_nextScriptIdx++;
		}
	}

	function _triggerEvent(evt:PSEEvent):Void {
		var v1 = evt.value ?? '';
		var v2 = '';
		if (v1.contains('|')) {
			var p = v1.split('|');
			v1 = p[0].trim();
			v2 = p.length > 1 ? p[1].trim() : '';
		}
		EventManager.fireEvent(evt.type, v1, v2);
		// Flash the block
		for (b in eventBlocks)
			if (b.eventId == evt.id) {
				FlxTween.cancelTweensOf(b);
				b.alpha = 1.0;
				FlxTween.tween(b, {alpha: 0.7}, 0.25, {
					ease: FlxEase.quadOut,
					onComplete: function(_) {
						if (b != null && b.alive && b.exists)
							b.alpha = 0.85;
					}
				});
				break;
			}
		_showStatus('> ${evt.type}  ${evt.value}', 1.5);
	}

	/**
	 * Registra handlers de eventos de cámara y otros eventos del chart que
	 * necesitan actuar sobre el cameraController del editor (no el de PlayState,
	 * que no existe aquí).
	 * Se llama una vez desde create() DESPUÉS de que EventManager cargue los eventos.
	 */
	function _registerEditorEventHandlers():Void {
		var self = this;

		// Camera Follow / Camera
		var camFollowHandler = function(evts:Array<funkin.scripting.events.EventData>) {
			var e = evts[0];
			if (e == null || self.cameraController == null)
				return true;
			var parts = (e.value1 ?? '').split('|');
			var target = parts[0].trim();
			var offX = parts.length > 1 ? Std.parseFloat(parts[1]) : Math.NaN;
			var offY = parts.length > 2 ? Std.parseFloat(parts[2]) : Math.NaN;
			self.cameraController.setTarget(target, Math.isNaN(offX) ? 0.0 : offX, Math.isNaN(offY) ? 0.0 : offY);
			return true;
		};
		EventManager.registerCustomEvent('Camera Follow', camFollowHandler);
		EventManager.registerCustomEvent('Camera', camFollowHandler);

		// Camera Focus
		EventManager.registerCustomEvent('Camera Focus', function(evts) {
			var e = evts[0];
			if (e == null || self.cameraController == null)
				return true;
			self.cameraController.setTarget((e.value1 != null && e.value1 != '') ? e.value1 : 'both');
			return true;
		});
		EventManager.registerCustomEvent('Focus Camera', function(evts) {
			var e = evts[0];
			if (e == null || self.cameraController == null)
				return true;
			self.cameraController.setTarget((e.value1 != null && e.value1 != '') ? e.value1 : 'both');
			return true;
		});

		// Camera Zoom
		var camZoomHandler = function(evts:Array<funkin.scripting.events.EventData>) {
			var e = evts[0];
			if (e == null || self.cameraController == null)
				return true;
			var zoom = Std.parseFloat((e.value1 ?? '1.0').split('|')[0]);
			if (!Math.isNaN(zoom)) {
				self.cameraController.defaultZoom = zoom;
				self.cameraController.zoomEnabled = true;
			}
			return true;
		};
		EventManager.registerCustomEvent('Camera Zoom', camZoomHandler);
		EventManager.registerCustomEvent('Zoom Camera', camZoomHandler);

		// Camera Shake
		EventManager.registerCustomEvent('Camera Shake', function(evts) {
			// Dejar que el built-in lo maneje (usa FlxG.cameras directamente, funciona aquí)
			return false;
		});

		// BPM Change — también funciona aquí vía built-in (no depende de PlayState)
		// Flash / Fade — lo mismo
		// Run Script — el built-in llama ScriptHandler.callOnScripts, funciona

		// ── Stub out handlers that require PlayState.instance or a video player ──
		// These chart-event HScripts (MidSongVideo, HudVisible, PlayAnim, AltAnim)
		// call PlayState.instance.xxx or access video/flash objects that don't exist
		// in the editor, producing the "object does not have the property 'alpha'" crash.
		for (unsafeEvt in ['MidSongVideo', 'HudVisible', 'PlayAnim', 'AltAnim'])
			EventManager.registerCustomEvent(unsafeEvt, function(_) return true);
	}

	function _runScript(scr:PSEScript):Void {
		#if HSCRIPT_ALLOWED
		var inst = scriptInstances.get(scr.id);
		if (inst == null || !inst.active) {
			inst = new HScriptInstance(scr.name, scr.id);
			inst.priority = 0;
			_exposeScriptVars(inst);
			// Cargar código desde archivo si savePath apunta a un fichero externo
			var code = _loadScriptCode(scr);
			inst.loadString(code);
			scriptInstances.set(scr.id, inst);
		}
		inst.call('onTrigger', [Conductor.songPosition]);
		_showStatus('> Script: ${scr.name}', 1.5);
		#else
		_showStatus('[WARN] HScript not available in this build');
		#end
	}

	/**
	 * Devuelve el código del script.
	 * Si `savePath` apunta a un archivo externo y existe, lo lee del disco.
	 * En cualquier otro caso devuelve el código inline (`scr.code`).
	 */
	function _loadScriptCode(scr:PSEScript):String {
		#if sys
		var resolved = _resolveSavePath(scr);
		if (resolved != null && resolved != '' && sys.FileSystem.exists(resolved)) {
			try {
				return sys.io.File.getContent(resolved);
			} catch (_) {}
		}
		#end
		return scr.code ?? '';
	}

	/**
	 * Convierte el `savePath` lógico ('song', 'events', 'global') a una ruta
	 * de archivo real, o devuelve la ruta literal si ya es absoluta/relativa.
	 * Devuelve null si savePath es null / 'inline' / vacío.
	 */
	function _resolveSavePath(scr:PSEScript):Null<String> {
		var sp = scr.savePath ?? 'inline';
		var nm = (scr.name != null && scr.name != '') ? scr.name : 'unnamed_script';
		// Normalizar nombre a nombre de archivo válido
		nm = nm.replace(' ', '_').replace('/', '_').replace('\\', '_');
		if (!nm.endsWith('.hx'))
			nm += '.hx';
		return switch (sp) {
			case null, '', 'inline': null;
			case 'song': 'assets/songs/$currentSong/scripts/$nm';
			case 'events': 'assets/data/scripts/events/$nm';
			case 'global': 'assets/data/scripts/global/$nm';
			default: sp; // ruta literal
		}
	}

	function _exposeScriptVars(inst:HScriptInstance):Void {
		#if HSCRIPT_ALLOWED
		inst.set('game', this);
		inst.set('playStateEditor', this);
		inst.set('boyfriend', boyfriend);
		inst.set('dad', dad);
		inst.set('gf', gf);
		inst.set('stage', currentStage);
		inst.set('camGame', camGame);
		inst.set('camHUD', camHUD);
		inst.set('cameraController', cameraController);
		inst.set('gameState', gameState);
		inst.set('FlxG', FlxG);
		inst.set('FlxTween', FlxTween);
		inst.set('FlxTimer', FlxTimer);
		inst.set('conductor', Conductor);
		inst.set('Paths', Paths);
		inst.set('uiManager', uiManager);
		inst.set('songName', currentSong);
		inst.set('trace', function(v:Dynamic) trace('[PSEScript] $v'));
		#end
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Timeline input + playhead
	// ─────────────────────────────────────────────────────────────────────────
	function _updatePlayhead():Void {
		var tlY = _tlY();
		var posMs = Conductor.songPosition;
		var areaW = _tlAreaW();
		var trackN = Std.int(Math.min(tracks.length - _trackScrollY, TL_MAX_TRACKS));
		var tracksH = trackN * TL_TRACK_H;

		// Auto-scroll
		if (isPlaying && !_scrubDrag && !_hScrollDrag) {
			var rel = (posMs - tlScrollX) * tlZoom;
			if (rel > areaW * 0.78)
				tlScrollX = posMs - areaW * 0.2 / tlZoom;
			if (rel < 0)
				tlScrollX = posMs;
			if (tlScrollX < 0)
				tlScrollX = 0;
		}

		var xp = TL_LABEL_W + (posMs - tlScrollX) * tlZoom;
		if (tlPlayhead != null) {
			tlPlayhead.x = xp;
			tlPlayhead.y = tlY;
			tlPlayhead.makeGraphic(2, TL_RULER_H + tracksH, C_PLAYHEAD);
		}
		if (tlPlayheadHead != null) {
			tlPlayheadHead.x = xp - 5;
			tlPlayheadHead.y = tlY;
			tlPlayheadHead.makeGraphic(12, 12, C_PLAYHEAD);
		}

		// Scrubber
		if (songLength > 0) {
			var scrY = tlY + TL_RULER_H + tracksH + 12;
			if (tlScrubFill != null) {
				var fw = Std.int(Math.max(1, (posMs / songLength) * SW));
				tlScrubFill.makeGraphic(fw, TL_SCRUB_H - 2, 0xFF1A3C5C);
				tlScrubFill.y = scrY + 1;
			}
			if (tlScrubHandle != null) {
				tlScrubHandle.x = (posMs / songLength) * SW - 2;
				tlScrubHandle.y = scrY + TL_SCRUB_H / 2 - 8;
			}
		}

		// HScroll thumb
		if (tlHScrollThumb != null && songLength > 0) {
			var hsY = _tlY() + TL_RULER_H + trackN * TL_TRACK_H;
			var hsW = _tlAreaW();
			var visMs = hsW / tlZoom;
			var thumbW = Std.int(Math.max(16, hsW * Math.min(1, visMs / songLength)));
			var ratio = tlScrollX / Math.max(1, songLength - visMs);
			tlHScrollThumb.x = TL_LABEL_W + Std.int((hsW - thumbW) * FlxMath.bound(ratio, 0, 1));
			tlHScrollThumb.y = hsY + 2;
			tlHScrollThumb.makeGraphic(thumbW, 8, C_ACCENT);
		}

		// Update zoomSlider to reflect current tlZoom
		if (zoomSlider != null)
			zoomSlider.value = tlZoom;
	}

	function _handleTimelineInput():Void {
		var tlY = _tlY();
		var trackN = Std.int(Math.min(tracks.length - _trackScrollY, TL_MAX_TRACKS));
		var hsY = tlY + TL_RULER_H + trackN * TL_TRACK_H;
		var scrY = hsY + 12;
		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;
		var areaW = _tlAreaW();

		// HScroll drag
		var inHS = my >= hsY && my <= hsY + 12 && mx >= TL_LABEL_W && mx <= TL_LABEL_W + areaW;
		if (FlxG.mouse.justPressed && inHS) {
			_hScrollDrag = true;
			_hScrollDragOff = mx;
		}
		if (FlxG.mouse.justReleased)
			_hScrollDrag = false;
		if (_hScrollDrag && songLength > 0) {
			var visMs = areaW / tlZoom;
			var maxSc = Math.max(0, songLength - visMs);
			tlScrollX = FlxMath.bound((mx - TL_LABEL_W) / areaW * songLength, 0, maxSc);
			_rebuildRuler();
			_rebuildEventBlocks();
		}

		// Scrubber drag
		var inScrub = my >= scrY && my <= scrY + TL_SCRUB_H && mx >= 0 && mx <= SW;
		if (FlxG.mouse.justPressed && inScrub)
			_scrubDrag = true;
		if (FlxG.mouse.justReleased)
			_scrubDrag = false;
		if (_scrubDrag && songLength > 0)
			autoSeekTime = FlxMath.bound(mx / SW, 0, 1) * songLength;

		// Ruler click/drag → seek
		var inRuler = my >= tlY && my <= tlY + TL_RULER_H && mx >= TL_LABEL_W && mx <= TL_LABEL_W + areaW;
		if (FlxG.mouse.pressed && inRuler) {
			var ms = (mx - TL_LABEL_W) / tlZoom + tlScrollX;
			autoSeekTime = Math.max(0, ms);
		}

		// Double-click on track area → create event
		var tracksAreaY = tlY + TL_RULER_H;
		var inTracks = my >= tracksAreaY && my <= tracksAreaY + trackN * TL_TRACK_H && mx >= TL_LABEL_W && mx <= TL_LABEL_W + areaW;
		if (FlxG.mouse.justPressedRight && inTracks) {
			// Right-click → context menu
			_openContextMenu(mx, my);
		}
		if (FlxG.mouse.justPressed && inTracks && _ctxMenu == null) {
			var overBlock = false;
			for (b in eventBlocks)
				if (FlxG.mouse.overlaps(b, camHUD)) {
					overBlock = true;
					break;
				}
			if (!overBlock) {
				var now = haxe.Timer.stamp();
				var dx = Math.abs(mx - _lastClickX);
				var dy = Math.abs(my - _lastClickY);
				if (now - _lastClickTime < 0.35 && dx < 8 && dy < 8) {
					// Double-click on empty area → create a new event here
					var evtMs = (mx - TL_LABEL_W) / tlZoom + tlScrollX;
					var evtStep = evtMs / Conductor.stepCrochet;
					if (_snapEnabled)
						evtStep = Math.round(evtStep);
					var trackI = Std.int((my - tracksAreaY) / TL_TRACK_H) + _trackScrollY;
					trackI = Std.int(FlxMath.bound(trackI, 0, tracks.length - 1));
					if (!tracks[trackI].locked)
						_createEvent('Camera Follow', 'bf', trackI, evtStep);
					_lastClickTime = 0; // reset so triple-click doesn't re-create
				} else {
					selectedEventId = '';
					_lastClickTime = now;
					_lastClickX = mx;
					_lastClickY = my;
				}
			}
		}

		// Wheel scroll
		if (my >= tlY && my <= scrY) {
			var w = FlxG.mouse.wheel;
			if (w != 0) {
				if (FlxG.keys.pressed.CONTROL) {
					tlZoom = FlxMath.bound(tlZoom * (w > 0 ? 1.2 : 0.83), 0.005, 3.0);
				} else {
					tlScrollX -= w * Conductor.crochet * 2;
					if (tlScrollX < 0)
						tlScrollX = 0;
				}
				_rebuildRuler();
				_rebuildEventBlocks();
			}
		}

		// Wheel on game area = camera zoom  (Ctrl NOT held, free cam NOT active)
		if (my >= HEADER_H && my < tlY && mx < SW - INSP_W && !FlxG.keys.pressed.CONTROL) {
			var w = FlxG.mouse.wheel;
			if (w != 0) {
				_gameZoom = FlxMath.bound(_gameZoom * (w > 0 ? 1.12 : 0.89), 0.05, 5.0);
				if (camGame != null)
					camGame.zoom = _gameZoom * (camGame.width / SW);

				if (cameraController != null)
					cameraController.zoomEnabled = false;
				_showStatus('Zoom ${Math.round(_gameZoom * 100)}%  (C = toggle cam proxy)', 0.8);
			}
		}
	}

	function _handleEventInteraction():Void {
		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;

		// Drag existing event block
		if (_dragEvent != null) {
			if (FlxG.mouse.pressed) {
				var newMs = (mx - TL_LABEL_W) / tlZoom + tlScrollX - _dragEvtOffMs;
				if (_snapEnabled)
					newMs = Math.round(newMs / Conductor.stepCrochet) * Conductor.stepCrochet;
				newMs = Math.max(0, newMs);
				// Find event
				for (e in (pseData.events ?? [])) {
					if (e.id == _dragEvent.eventId) {
						e.stepTime = newMs / Conductor.stepCrochet;
						// Also allow vertical track change
						var tlY = _tlY();
						var tracksY = tlY + TL_RULER_H;
						var newTrack = Std.int((my - tracksY) / TL_TRACK_H) + _trackScrollY;
						newTrack = Std.int(FlxMath.bound(newTrack, 0, tracks.length - 1));
						e.trackIndex = newTrack;
						break;
					}
				}
				_rebuildEventBlocks();
			} else {
				hasUnsaved = true;
				_updateUnsavedDot();
				_pushUndo();
				_rebuildSorted();
				_dragEvent = null;
			}
			// Hide resize visual while dragging
			if (_resizeHandleViz != null)
				_resizeHandleViz.visible = false;
			return;
		}

		// Resize event block
		if (_resizeEvent != null) {
			if (FlxG.mouse.pressed) {
				var dx = mx - _resizeStartX;
				var addDur = dx / (Conductor.stepCrochet * tlZoom);
				var newDur = Math.max(1, _resizeEvtOrigDur + addDur);
				if (_snapEnabled)
					newDur = Math.round(newDur);
				for (e in (pseData.events ?? [])) {
					if (e.id == _resizeEvent.eventId) {
						e.duration = newDur;
						break;
					}
				}
				_rebuildEventBlocks();
			} else {
				hasUnsaved = true;
				_updateUnsavedDot();
				_pushUndo();
				_rebuildSorted();
				_resizeEvent = null;
			}
			// Hide resize visual while actively resizing
			if (_resizeHandleViz != null)
				_resizeHandleViz.visible = false;
			return;
		}

		// ── Hover detection for resize handle visual ──────────────────────────
		var newHoverId = '';
		for (b in eventBlocks) {
			if (!FlxG.mouse.overlaps(b, camHUD))
				continue;
			if (Math.abs(mx - (b.x + b.width)) <= 12) {
				newHoverId = b.eventId;
				break;
			}
		}
		if (newHoverId != _hoverResizeId) {
			_hoverResizeId = newHoverId;
			if (_resizeHandleViz != null) {
				if (_hoverResizeId != '') {
					for (b in eventBlocks)
						if (b.eventId == _hoverResizeId) {
							_resizeHandleViz.makeGraphic(4, Std.int(b.height), FlxColor.WHITE);
							_resizeHandleViz.x = b.x + b.width - 4;
							_resizeHandleViz.y = b.y;
							_resizeHandleViz.visible = true;
							break;
						}
				} else
					_resizeHandleViz.visible = false;
			}
		} else if (_hoverResizeId != '' && _resizeHandleViz != null && _resizeHandleViz.visible) {
			// Keep visual tracking the block in case scroll/zoom changed
			for (b in eventBlocks)
				if (b.eventId == _hoverResizeId) {
					_resizeHandleViz.x = b.x + b.width - 4;
					_resizeHandleViz.y = b.y;
					break;
				}
		}

		if (!FlxG.mouse.justPressed)
			return;

		// Click on event block
		for (b in eventBlocks) {
			if (!FlxG.mouse.overlaps(b, camHUD))
				continue;

			if (b.isScriptBlock) {
				selectedEventId = b.eventId;
				_refreshInspector();
				return;
			}

			selectedEventId = b.eventId;
			_refreshInspector();
			_rebuildEventBlocks();

			// Is cursor near right edge? → resize (12px zone for easier grab)
			var rightEdge = b.x + b.width;
			if (Math.abs(mx - rightEdge) <= 12) {
				_resizeEvent = b;
				_resizeStartX = mx;
				for (e in (pseData.events ?? []))
					if (e.id == b.eventId) {
						_resizeEvtOrigDur = e.duration ?? 4.0;
						break;
					}
				return;
			}
			// Otherwise drag
			_dragEvent = b;
			var evtMs = 0.0;
			for (e in (pseData.events ?? []))
				if (e.id == b.eventId) {
					evtMs = e.stepTime * Conductor.stepCrochet;
					break;
				}
			_dragEvtOffMs = (mx - TL_LABEL_W) / tlZoom + tlScrollX - evtMs;
			return;
		}
		// Clicked empty → deselect
		selectedEventId = '';
		_refreshInspector();
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Context Menu
	// ─────────────────────────────────────────────────────────────────────────
	function _openContextMenu(mx:Float, my:Float):Void {
		if (_ctxMenu != null) {
			remove(_ctxMenu);
			_ctxMenu.destroy();
		}
		var tlY = _tlY();
		var trackN = Std.int(Math.min(tracks.length - _trackScrollY, TL_MAX_TRACKS));
		var tracksY = tlY + TL_RULER_H;
		var trackI = Std.int((my - tracksY) / TL_TRACK_H) + _trackScrollY;
		var evtMs = (mx - TL_LABEL_W) / tlZoom + tlScrollX;
		var evtStep = evtMs / Conductor.stepCrochet;
		if (_snapEnabled)
			evtStep = Math.round(evtStep);

		var items:Array<{label:String, cb:Void->Void}> = [
			{label: 'Add Camera Follow', cb: () -> _createEvent('Camera Follow', 'bf', Std.int(FlxMath.bound(trackI, 0, tracks.length - 1)), evtStep)},
			{label: 'Add Camera Zoom', cb: () -> _createEvent('Zoom Camera', '1.0', Std.int(FlxMath.bound(trackI, 0, tracks.length - 1)), evtStep)},
			{
				label: 'Add BPM Change',
				cb: () -> _createEvent('BPM Change', '${Std.int(Conductor.bpm)}', Std.int(FlxMath.bound(trackI, 0, tracks.length - 1)), evtStep)
			},
			{label: 'Add Script Trigger', cb: () -> _createEvent('Script', '', 3, evtStep)},
			{label: 'Add Custom Event', cb: () -> _createEvent('Custom', '', Std.int(FlxMath.bound(trackI, 0, tracks.length - 1)), evtStep)},
		];
		if (selectedEventId != '') {
			items.push({label: 'Delete Selected', cb: _deleteSelected});
			items.push({label: 'Duplicate Selected', cb: _duplicateSelected});
		}

		_ctxMenu = new PSEContextMenu(mx, my, items);
		_ctxMenu.cameras = [camUI]; // camUI renders last → always on top of camGame viewport
		add(_ctxMenu);
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Free Camera
	// ─────────────────────────────────────────────────────────────────────────
	function _toggleFreeCam():Void {
		_freeCam = !_freeCam;
		if (freeCamBtn != null) {
			freeCamBtn.makeGraphic(36, 29, _freeCam ? 0xFF1A4A3A : 0xFF1A2A3A);
			freeCamBtn.label.color = _freeCam ? C_ACCENT2 : C_TEXT;
		}
		_showStatus(_freeCam ? '[CAM] Free Camera ON' : '[CAM] Free Camera OFF', 2.5);
	}

	function _handleFreeCam(elapsed:Float):Void {
		if (!_freeCam || camGame == null)
			return;
		var speed = 400 * elapsed / camGame.zoom;

		if (controls.UP)
			_freeCamY -= speed;
		if (controls.DOWN)
			_freeCamY += speed;
		if (controls.LEFT)
			_freeCamX -= speed;
		if (controls.RIGHT)
			_freeCamX += speed;

		// Mouse drag in game area
		if (FlxG.mouse.pressed && FlxG.mouse.y > HEADER_H && FlxG.mouse.y < _tlY() && FlxG.mouse.x < SW - INSP_W) {
			_freeCamX -= FlxG.mouse.deltaX / camGame.zoom;
			_freeCamY -= FlxG.mouse.deltaY / camGame.zoom;
		}

		camGame.scroll.set(_freeCamX, _freeCamY);

		// Scroll = zoom in free mode
		var w = FlxG.mouse.wheel;
		if (w != 0 && FlxG.mouse.y > HEADER_H && FlxG.mouse.y < _tlY()) {
			_gameZoom = FlxMath.bound(_gameZoom * (w > 0 ? 1.12 : 0.89), 0.05, 8.0);
			camGame.zoom = _gameZoom;
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Keyboard Shortcuts
	// ─────────────────────────────────────────────────────────────────────────
	function _handleKeys():Void {
		var ctrl = FlxG.keys.pressed.CONTROL;

		if (FlxG.keys.justPressed.SPACE && !_anyInputFocused())
			_onPlayPause();
		if (FlxG.keys.justPressed.R && !ctrl && !_anyInputFocused())
			_onRestart();
		if (FlxG.keys.justPressed.F && !ctrl && !_anyInputFocused())
			_toggleFreeCam();
		if ((FlxG.keys.justPressed.F5 || (ctrl && FlxG.keys.justPressed.S)))
			_savePSEData();
		if (ctrl && FlxG.keys.justPressed.Z)
			_doUndo();
		if (ctrl && (FlxG.keys.justPressed.Y || (FlxG.keys.pressed.SHIFT && FlxG.keys.justPressed.Z)))
			_doRedo();
		if (FlxG.keys.justPressed.DELETE && !_anyInputFocused() && selectedEventId != '')
			_deleteSelected();
		if (FlxG.keys.justPressed.ESCAPE)
			_goBack();
		if (FlxG.keys.justPressed.HOME && !_anyInputFocused())
			autoSeekTime = 0;
		if (FlxG.keys.justPressed.END && !_anyInputFocused())
			autoSeekTime = songLength - 50;

		// Zoom timeline
		if (ctrl && FlxG.keys.pressed.PLUS) {
			tlZoom = FlxMath.bound(tlZoom * 1.1, 0.005, 3.0);
			_rebuildRuler();
			_rebuildEventBlocks();
		}
		if (ctrl && FlxG.keys.pressed.MINUS) {
			tlZoom = FlxMath.bound(tlZoom * 0.9, 0.005, 3.0);
			_rebuildRuler();
			_rebuildEventBlocks();
		}

		// Playback speed  [ = slower,  ] = faster
		if (FlxG.keys.justPressed.LBRACKET && !ctrl && !_anyInputFocused())
			_changeSpeed(-0.25);
		if (FlxG.keys.justPressed.RBRACKET && !ctrl && !_anyInputFocused())
			_changeSpeed(0.25);

		// Toggle camera proxy overlay  (C)
		if (FlxG.keys.justPressed.C && !ctrl && !_anyInputFocused()) {
			_showCamProxy = !_showCamProxy;
			_showStatus(_showCamProxy ? '[CAM] Camera proxy ON' : '[CAM] Camera proxy OFF', 2.5);
		}

		// Reset game zoom to 1  (0)
		if (FlxG.keys.justPressed.ZERO && !ctrl && !_anyInputFocused()) {
			_gameZoom = 1.0;
			if (camGame != null)
				camGame.zoom = _gameZoom * (camGame.width / SW);
			_showStatus('Zoom reset → 100%', 1.0);
		}
	}

	function _anyInputFocused():Bool {
		for (el in _inspElements)
			if (Std.isOfType(el, CoolInputText) && (cast el : CoolInputText).hasFocus)
				return true;
		return false;
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Transport
	// ─────────────────────────────────────────────────────────────────────────
	function _onPlayPause():Void {
		isPlaying = !isPlaying;
		_syncAudio(isPlaying);
		if (playBtn != null) {
			playBtn.label.text = isPlaying ? '||' : '>';
			playBtn.label.color = isPlaying ? 0xFFFFAA00 : C_ACCENT2;
		}
		_showStatus(isPlaying ? '> Playing' : '|| Paused');
	}

	function _onStop():Void {
		isPlaying = false;
		_syncAudio(false);
		_doSeek(0);
		if (playBtn != null) {
			playBtn.label.text = '>';
			playBtn.label.color = C_ACCENT2;
		}
		_showStatus('[] Stopped');
	}

	function _onRestart():Void {
		_doSeek(0);
		if (cameraController != null)
			cameraController.resetToInitial();
		if (characterController != null)
			characterController.forceIdleAll();
		isPlaying = true;
		_syncAudio(true);
		if (playBtn != null) {
			playBtn.label.text = '||';
			playBtn.label.color = 0xFFFFAA00;
		}
		_showStatus('|< Restart');
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Playback speed
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Sube o baja la velocidad de reproducción en `delta` pasos (0.25 = un step).
	 * Aplica `pitch` al audio si la versión de lime lo soporta.
	 */
	function _changeSpeed(delta:Float):Void {
		_playbackSpeed = FlxMath.bound(Math.round((_playbackSpeed + delta) * 4) / 4.0, // snap to 0.25 grid
			0.25, 3.0);
		if (speedLbl != null)
			speedLbl.text = '${_playbackSpeed}x';
		_applyPlaybackSpeed();
		_showStatus('Speed: ${_playbackSpeed}x', 1.8);
	}

	/** Aplica _playbackSpeed al pitch del audio. Requiere lime 7+ / OpenFL 9+. */
	function _applyPlaybackSpeed():Void {
		try {
			if (FlxG.sound.music != null)
				FlxG.sound.music.pitch = _playbackSpeed;
			for (s in vocalsMap)
				if (s != null)
					s.pitch = _playbackSpeed;
			if (vocalsBf != null)
				vocalsBf.pitch = _playbackSpeed;
			if (vocalsDad != null)
				vocalsDad.pitch = _playbackSpeed;
			if (vocals != null)
				vocals.pitch = _playbackSpeed;
		} catch (e:Dynamic) {
			// pitch no disponible en esta build (HaxeFlixel < 5 / lime < 7)
			_showStatus('[WARN] Pitch change not supported in this build', 2.5);
		}
	}

	function _buildChartNotes():Void {
		_chartNotes = [];
		var SONG = PlayState.SONG;
		if (SONG == null || SONG.notes == null) return;
		for (section in SONG.notes) {
			if (section == null || section.sectionNotes == null) continue;
			var mustHit:Bool = section.mustHitSection ?? true;
			var gfSing:Bool  = section.gfSing ?? false;
			for (rawNote in section.sectionNotes) {
				var strumTime:Float = rawNote[0];
				var rawData:Int     = Std.int(rawNote[1]);
				var direction:Int   = rawData % 4;
				var isPlayer:Bool = (mustHit && rawData < 4) || (!mustHit && rawData >= 4);
				var isGF:Bool     = !isPlayer && gfSing;
				_chartNotes.push({time: strumTime, direction: direction, isPlayer: isPlayer, isGF: isGF});
			}
		}
		_chartNotes.sort((a, b) -> a.time < b.time ? -1 : (a.time > b.time ? 1 : 0));
		_nextNoteIdx = 0;
	}

	function _doSeek(ms:Float):Void {
		Conductor.songPosition = ms;
		if (FlxG.sound.music != null)
			FlxG.sound.music.time = ms;
		_syncVocals(ms);
		_lastBeat = -1;
		_lastStep = -1;

		// Avanzar el puntero del EventManager sin re-disparar eventos de chart
		EventManager.seekTo(ms);

		// Avanzar punteros de eventos/scripts PSE
		_nextEventIdx = 0;
		_nextScriptIdx = 0;
		_nextNoteIdx = 0;
		while (_nextNoteIdx < _chartNotes.length && _chartNotes[_nextNoteIdx].time < ms)
			_nextNoteIdx++;
		while (_nextEventIdx < sortedEvents.length && Conductor.stepCrochet * sortedEvents[_nextEventIdx].stepTime < ms)
			_nextEventIdx++;
		while (_nextScriptIdx < sortedScripts.length
			&& sortedScripts[_nextScriptIdx].triggerStep >= 0
			&& Conductor.stepCrochet * sortedScripts[_nextScriptIdx].triggerStep < ms)
			_nextScriptIdx++;
	}

	function _syncAudio(play:Bool):Void {
		if (FlxG.sound.music == null)
			return;
		if (play) {
			// Explicitly re-set time before play — some OpenFL/lime backends
			// reset the position to 0 when play() is called on a paused sound
			// unless the seek is re-applied right here.
			FlxG.sound.music.time = Conductor.songPosition;
			FlxG.sound.music.volume = 1;
			FlxG.sound.music.play();
			_applyPlaybackSpeed();
		} else
			FlxG.sound.music.pause();
		// Pass Conductor.songPosition (not music.time which may have drifted)
		_syncVocals(Conductor.songPosition, play);
	}

	function _syncVocals(t:Float, play:Bool = false):Void {
		for (s in vocalsMap) {
			if (s == null)
				continue;
			s.time = t;
			if (play)
				s.play();
			else
				s.pause();
		}
		if (_perCharVocals && Lambda.count(vocalsMap) == 0) {
			if (vocalsBf != null) {
				vocalsBf.time = t;
				if (play)
					vocalsBf.play();
				else
					vocalsBf.pause();
			}
			if (vocalsDad != null) {
				vocalsDad.time = t;
				if (play)
					vocalsDad.play();
				else
					vocalsDad.pause();
			}
		} else if (vocals != null) {
			vocals.time = t;
			if (play)
				vocals.play();
			else
				vocals.pause();
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Event CRUD
	// ─────────────────────────────────────────────────────────────────────────
	function _createEventAtPlayhead(type:String, value:String, trackI:Int):Void {
		var step = Conductor.songPosition / Conductor.stepCrochet;
		if (_snapEnabled)
			step = Math.round(step);
		_createEvent(type, value, trackI, step);
	}

	function _createEvent(type:String, value:String, trackI:Int, stepTime:Float):Void {
		_pushUndo();
		var evt:PSEEvent = {
			id: _newUid(),
			stepTime: stepTime,
			type: type,
			value: value,
			difficulties: ['*'],
			trackIndex: Std.int(FlxMath.bound(trackI, 0, tracks.length - 1)),
			duration: 8.0,
		};
		if (pseData.events == null)
			pseData.events = [];
		pseData.events.push(evt);
		selectedEventId = evt.id;
		hasUnsaved = true;
		_updateUnsavedDot();
		_rebuildSorted();
		_rebuildEventBlocks();
		_refreshInspector();
		_showStatus('✓ Event created: $type @ step ${Std.int(stepTime)}');
	}

	function _deleteSelected():Void {
		if (selectedEventId == '')
			return;
		_pushUndo();
		if (selectedEventId.startsWith('script_')) {
			var sid = selectedEventId.substr(7);
			if (pseData.scripts != null)
				pseData.scripts = pseData.scripts.filter(s -> s.id != sid);
		} else {
			if (pseData.events != null)
				pseData.events = pseData.events.filter(e -> e.id != selectedEventId);
		}
		selectedEventId = '';
		hasUnsaved = true;
		_updateUnsavedDot();
		_rebuildSorted();
		_rebuildEventBlocks();
		_refreshInspector();
		_showStatus('✓ Deleted');
	}

	function _duplicateSelected():Void {
		if (selectedEventId == '')
			return;
		_pushUndo();
		for (e in (pseData.events ?? [])) {
			if (e.id != selectedEventId)
				continue;
			var ne:PSEEvent = {
				id: _newUid(),
				stepTime: e.stepTime + (e.duration ?? 4.0),
				type: e.type,
				value: e.value,
				difficulties: e.difficulties.copy(),
				trackIndex: e.trackIndex,
				duration: e.duration,
				label: e.label,
			};
			if (pseData.events == null)
				pseData.events = [];
			pseData.events.push(ne);
			selectedEventId = ne.id;
			hasUnsaved = true;
			_updateUnsavedDot();
			_rebuildSorted();
			_rebuildEventBlocks();
			_refreshInspector();
			_showStatus('✓ Duplicated: ${ne.type}');
			return;
		}
	}

	function _addTrack():Void {
		var idx = tracks.length;
		tracks.push({
			id: 'custom$idx',
			name: 'Track $idx',
			color: 0xFF66AAFF,
			visible: true,
			locked: false,
			height: TL_TRACK_H
		});
		pseData.tracks = tracks;
		_refreshTrackRows();
		hasUnsaved = true;
		_updateUnsavedDot();
		_showStatus('✓ Track added');
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Import mustHitSection as camera events
	// ─────────────────────────────────────────────────────────────────────────
	function _importSectionCamEvents():Void {
		var SONG = PlayState.SONG;
		if (SONG == null || SONG.notes == null || SONG.notes.length == 0)
			return;
		var acc:Float = 0;
		var prev = true;
		for (i in 0...SONG.notes.length) {
			var sec = SONG.notes[i];
			var mh = sec.mustHitSection ?? true;
			if (i == 0 || mh != prev) {
				var tgt = mh ? 'bf' : 'dad';
				var exists = false;
				for (e in (pseData.events ?? []))
					if (e.type == 'Camera Follow' && Math.abs(e.stepTime - acc) < 0.5) {
						exists = true;
						break;
					}
				if (!exists) {
					if (pseData.events == null)
						pseData.events = [];
					pseData.events.push({
						id: _newUid(),
						stepTime: acc,
						type: 'Camera Follow',
						value: tgt,
						difficulties: ['*'],
						trackIndex: 0,
						duration: sec.lengthInSteps ?? 16,
						label: 'Cam→$tgt'
					});
				}
				prev = mh;
			}
			acc += sec.lengthInSteps ?? 16;
		}
		_rebuildSorted();
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Helpers
	// ─────────────────────────────────────────────────────────────────────────
	function _getEventTypes():Array<String> {
		EventInfoSystem.reload();
		var list = EventInfoSystem.eventList.copy();
		if (list.length == 0)
			list = [
				'Camera Follow',
				'Camera Focus',
				'Zoom Camera',
				'BPM Change',
				'Play Animation',
				'Hey!',
				'Screen Shake',
				'Camera Flash',
				'Change Character',
				'Tween',
				'Script'
			];
		return list;
	}

	function _evtForDiff(e:PSEEvent, diff:String):Bool
		return e.difficulties == null || e.difficulties.length == 0 || e.difficulties.contains('*') || e.difficulties.contains(diff);

	function _scrForDiff(s:PSEScript, diff:String):Bool
		return s.difficulties == null || s.difficulties.length == 0 || s.difficulties.contains('*') || s.difficulties.contains(diff);

	function _updateTimeDisplay():Void {
		var pos = Conductor.songPosition;
		var len = songLength;
		if (timeTxt != null)
			timeTxt.text = '${_fmtMs(pos)} / ${_fmtMs(len)}';
		if (playBtn != null)
			playBtn.label.text = isPlaying ? '||' : '>';
		// Snap check sync
		if (snapCheck != null)
			_snapEnabled = snapCheck.checked;
	}

	function _updateCursorInfo():Void {
		if (cursorInfoTxt == null)
			return;
		var mx = FlxG.mouse.x;
		var tlY = _tlY();
		var areaW = _tlAreaW();
		if (mx >= TL_LABEL_W && mx <= TL_LABEL_W + areaW && FlxG.mouse.y >= tlY && FlxG.mouse.y <= tlY + _tlH()) {
			var ms = (mx - TL_LABEL_W) / tlZoom + tlScrollX;
			var step = ms / Conductor.stepCrochet;
			var bar = Math.floor(step / 16) + 1;
			var beat = Std.int(step % 16);
			cursorInfoTxt.text = 'Bar ${bar}.${beat}  |  Step ${Std.int(step)}  |  ${_fmtMs(ms)}';
		} else {
			var posMs = Conductor.songPosition;
			var step = posMs / Conductor.stepCrochet;
			var bar = Math.floor(step / 16) + 1;
			var beat = Std.int(step % 16);
			cursorInfoTxt.text = 'Bar ${bar}.${beat}  |  Step ${Std.int(step)}  |  BPM ${Std.int(Conductor.bpm)}';
		}
	}

	function _fmtMs(ms:Float):String {
		var s = Math.floor(ms / 1000);
		var m = Math.floor(s / 60);
		var ss = Std.string(s % 60);
		if (ss.length < 2)
			ss = '0' + ss;
		var cs = Std.string(Std.int((ms % 1000) / 10));
		if (cs.length < 2)
			cs = '0' + cs;
		return '$m:$ss.$cs';
	}

	function _showStatus(msg:String, dur:Float = 3.5):Void {
		_statusTimer = dur;
		if (statusTxt != null)
			statusTxt.text = msg;
	}

	function _updateUnsavedDot():Void {
		if (unsavedDot != null)
			unsavedDot.visible = hasUnsaved;
	}

	function _newUid():String
		return 'pse_' + Std.string(Std.int(haxe.Timer.stamp() * 1000)) + '_' + (++_uid);

	function _mkBtn(x:Float, y:Float, label:String, w:Int, h:Int, color:Int, cb:Void->Void):PSEBtn {
		var btn = new PSEBtn(x, y, w, h, label, color, C_TEXT, cb);
		btn.cameras = [camHUD];
		btn.scrollFactor.set();
		btn.label.cameras = [camHUD];
		btn.label.scrollFactor.set();
		add(btn);
		add(btn.label);
		return btn;
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Navigation
	// ─────────────────────────────────────────────────────────────────────────
	function _goBack():Void {
		if (_unsavedDlg != null)
			return;
		if (hasUnsaved) {
			_unsavedDlg = new UnsavedChangesDialog([camHUD]);
			_unsavedDlg.onSaveAndExit = () -> {
				_savePSEData();
				_exitNow();
			};
			_unsavedDlg.onSave = () -> {
				_savePSEData();
				remove(_unsavedDlg);
				_unsavedDlg = null;
			};
			_unsavedDlg.onExit = _exitNow;
			add(_unsavedDlg);
		} else
			_exitNow();
	}

	function _exitNow():Void {
		funkin.system.CursorManager.hide();
		_syncAudio(false);
		StateTransition.switchState(new FreeplayEditorState());
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Destroy
	// ─────────────────────────────────────────────────────────────────────────
	override public function destroy():Void {
		for (k in scriptInstances.keys()) {
			var i = scriptInstances.get(k);
			if (i != null)
				i.active = false;
		}
		scriptInstances.clear();

		// Llamar onDestroy en scripts de la canción y limpiar todo
		ScriptHandler.callOnScripts('onDestroy', ScriptHandler._argsEmpty);
		ScriptHandler.clearSongScripts();
		EventManager.clear();

		if (vocals != null) {
			vocals.stop();
			vocals.destroy();
		}
		if (vocalsBf != null) {
			vocalsBf.stop();
			vocalsBf.destroy();
		}
		if (vocalsDad != null) {
			vocalsDad.stop();
			vocalsDad.destroy();
		}
		for (s in vocalsMap)
			if (s != null) {
				s.stop();
				s.destroy();
			}
		vocalsMap.clear();

		for (b in eventBlocks) {
			if (b.lblTxt != null)
				b.lblTxt.destroy();
			b.destroy();
		}
		eventBlocks = [];

		#if sys
		if (_windowCloseFn != null)
			try {
				lime.app.Application.current.window.onClose.remove(_windowCloseFn);
			} catch (_) {}
		#end

		if (camGame != null) {
			camGame.x = 0;
			camGame.y = 0;
			camGame.width = SW;
			camGame.height = SH;
		}
		super.destroy();
	}
}

// ═══════════════════════════════════════════════════════════════════════════════
//  PSEBtn  — simple button with hover highlight
// ═══════════════════════════════════════════════════════════════════════════════
private class PSEBtn extends FlxSprite {
	public var label:FlxText;
	public var onClick:Void->Void;

	var _base:Int;
	var _hover:Int;
	var _over:Bool = false;

	public function new(x:Float, y:Float, w:Int, h:Int, lbl:String, col:Int, txtCol:Int, ?cb:Void->Void) {
		super(x, y);
		makeGraphic(w, h, col);
		_base = col;
		_hover = _lighten(col, 18);
		onClick = cb;
		label = new FlxText(x, y + (h - 12) / 2, w, lbl, 11);
		label.setFormat(Paths.font('vcr.ttf'), 11, txtCol, CENTER);
		label.scrollFactor.set();
	}

	override private function set_cameras(c:Array<flixel.FlxCamera>):Array<flixel.FlxCamera> {
		if (label != null)
			label.cameras = c;
		return super.set_cameras(c);
	}

	override public function update(elapsed:Float):Void {
		super.update(elapsed);
		if (alive && exists && visible)
			updateInput();
	}

	public function updateInput():Void {
		var cam = (cameras != null && cameras.length > 0) ? cameras[0] : FlxG.camera;
		var ov = FlxG.mouse.overlaps(this, cam);
		if (ov && !_over) {
			makeGraphic(Std.int(width), Std.int(height), _hover);
			_over = true;
		} else if (!ov && _over) {
			makeGraphic(Std.int(width), Std.int(height), _base);
			_over = false;
		}
		label.x = x;
		label.y = y + (height - label.height) / 2;
		if (ov && FlxG.mouse.justPressed && onClick != null)
			onClick();
	}

	static function _lighten(c:Int, a:Int):Int {
		var r = (c >> 16) & 0xFF;
		var g = (c >> 8) & 0xFF;
		var b = c & 0xFF;
		var f = a / 100.0;
		return ((c >> 24) & 0xFF) << 24 | Std.int(Math.min(255,
			r + (255 - r) * f)) << 16 | Std.int(Math.min(255, g + (255 - g) * f)) << 8 | Std.int(Math.min(255, b + (255 - b) * f));
	}
}

// ═══════════════════════════════════════════════════════════════════════════════
//  PSEMenuBtn  — menu bar item (passes its index + x to callback)
// ═══════════════════════════════════════════════════════════════════════════════
private class PSEMenuBtn extends FlxSprite {
	public var label:FlxText;

	var _base:Int;
	var _hover:Int;
	var _over:Bool = false;
	var _idx:Int;
	var _cb:Int->Float->Void;

	public function new(x:Float, y:Float, text:String, base:Int, hover:Int, txtCol:Int, idx:Int, cb:Int->Float->Void) {
		super(x, y);
		var w = text.length * 8 + 12;
		makeGraphic(w, 22, base);
		_base = base;
		_hover = hover;
		_idx = idx;
		_cb = cb;
		label = new FlxText(x + 4, y + 4, w - 8, text, 10);
		label.setFormat(Paths.font('vcr.ttf'), 10, txtCol, LEFT);
		label.scrollFactor.set();
	}

	override private function set_cameras(c:Array<flixel.FlxCamera>):Array<flixel.FlxCamera> {
		if (label != null)
			label.cameras = c;
		return super.set_cameras(c);
	}

	override public function update(e:Float):Void {
		super.update(e);
		if (alive && exists && visible)
			updateInput();
	}

	public function updateInput():Void {
		var cam = (cameras != null && cameras.length > 0) ? cameras[0] : FlxG.camera;
		var ov = FlxG.mouse.overlaps(this, cam);
		if (ov && !_over) {
			makeGraphic(Std.int(width), Std.int(height), _hover);
			_over = true;
		} else if (!ov && _over) {
			makeGraphic(Std.int(width), Std.int(height), _base);
			_over = false;
		}
		label.x = x + 4;
		label.y = y + 4;
		if (ov && FlxG.mouse.justPressed && _cb != null)
			_cb(_idx, x);
	}
}

// ═══════════════════════════════════════════════════════════════════════════════
//  PSEDropdownPanel  — menu dropdown
// ═══════════════════════════════════════════════════════════════════════════════
private class PSEDropdownPanel extends FlxGroup {
	var _bg:FlxSprite;
	var _btns:Array<FlxSprite> = [];
	var _txts:Array<FlxText> = [];
	var _cbs:Array<Void->Void> = [];

	static inline final ITEM_H:Int = 22;
	static inline final C_PANEL_DD:Int = 0xFF1E1E34;
	static inline final C_HOVER_DD:Int = 0xFF2A2A4A;
	static inline final C_BORDER_DD:Int = 0xFF383858;
	static inline final C_TEXT_DD:Int = 0xFFCCCCEE;
	static inline final C_SEP_DD:Int = 0xFF303050;

	public function new(x:Float, y:Float, w:Int, items:Array<{label:String, cb:Void->Void, sep:Bool}>) {
		super();
		var h = items.length * ITEM_H + 2;
		_bg = new FlxSprite(x, y).makeGraphic(w, h, C_PANEL_DD);
		// Border
		flixel.util.FlxSpriteUtil.drawRect(_bg, 0, 0, w, 1, C_BORDER_DD);
		flixel.util.FlxSpriteUtil.drawRect(_bg, 0, h - 1, w, 1, C_BORDER_DD);
		flixel.util.FlxSpriteUtil.drawRect(_bg, 0, 0, 1, h, C_BORDER_DD);
		flixel.util.FlxSpriteUtil.drawRect(_bg, w - 1, 0, 1, h, C_BORDER_DD);
		add(_bg);

		for (i in 0...items.length) {
			var item = items[i];
			var iy = y + i * ITEM_H + 1;
			if (item.sep) {
				var sep = new FlxSprite(x + 4, iy + ITEM_H / 2).makeGraphic(w - 8, 1, C_SEP_DD);
				sep.alpha = 0.5;
				add(sep);
				_btns.push(null);
				_txts.push(null);
				_cbs.push(null);
				continue;
			}
			var btn = new FlxSprite(x, iy).makeGraphic(w, ITEM_H, C_PANEL_DD);
			add(btn);
			_btns.push(btn);

			var txt = new FlxText(x + 10, iy + 5, w - 20, item.label, 9);
			txt.setFormat(Paths.font('vcr.ttf'), 9, C_TEXT_DD, LEFT);
			add(txt);
			_txts.push(txt);
			_cbs.push(item.cb);
		}
	}

	override private function set_cameras(c:Array<flixel.FlxCamera>):Array<flixel.FlxCamera> {
        if (_bg != null) _bg.cameras = c;
        for (btn in _btns) if (btn != null) btn.cameras = c;
        for (txt in _txts) if (txt != null) txt.cameras = c;
        for (sep in members) if (sep != null) sep.cameras = c;
        return super.set_cameras(c);
    }

	override public function update(e:Float):Void {
		super.update(e);
		for (i in 0...Std.int(Math.min(_btns.length, _cbs.length))) {
			var btn = _btns[i];
			if (btn == null)
				continue;
			var cam = (cameras != null && cameras.length > 0) ? cameras[0] : FlxG.camera;
			var ov = FlxG.mouse.overlaps(btn, cam);
			btn.makeGraphic(Std.int(btn.width), Std.int(btn.height), ov ? C_HOVER_DD : C_PANEL_DD);
			if (ov && FlxG.mouse.justPressed && _cbs[i] != null)
				_cbs[i]();
		}
	}
}

// Extension to get int from float literal
private class FloatExt {
	public static function int(f:Float):Int
		return Std.int(f);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  PSEEventBlock  — colored rectangular event clip on the timeline
// ═══════════════════════════════════════════════════════════════════════════════
private class PSEEventBlock extends FlxSprite {
	public var eventId:String;
	public var lblTxt:FlxText;
	public var isScriptBlock:Bool = false;

	var _isSel:Bool;

	public function new(x:Float, y:Float, w:Int, h:Int, col:Int, id:String, isSel:Bool, ?typeName:String = '') {
		super(x, y);
		eventId = id;
		_isSel = isSel;

		// Clip body
		makeGraphic(Std.int(Math.max(4, w)), h, col, true);
		// Slightly lighter top edge
		flixel.util.FlxSpriteUtil.drawRect(this, 0, 0, Std.int(Math.max(4, w)), 2, _lighten(col, 25));
		// Darker bottom
		flixel.util.FlxSpriteUtil.drawRect(this, 0, h - 1, Std.int(Math.max(4, w)), 1, _darken(col, 30));
		// Selection highlight
		if (isSel) {
			flixel.util.FlxSpriteUtil.drawRect(this, 0, 0, Std.int(Math.max(4, w)), h, 0x00000000);
			flixel.util.FlxSpriteUtil.drawRect(this, 0, 0, Std.int(Math.max(4, w)), 2, FlxColor.WHITE);
			flixel.util.FlxSpriteUtil.drawRect(this, 0, 0, 1, h, FlxColor.WHITE);
			flixel.util.FlxSpriteUtil.drawRect(this, Std.int(Math.max(4, w)) - 1, 0, 1, h, FlxColor.WHITE);
		}

		alpha = isSel ? 1.0 : 0.85;
	}

	static function _lighten(c:Int, a:Int):Int {
		var r = (c >> 16) & 0xFF;
		var g = (c >> 8) & 0xFF;
		var b = c & 0xFF;
		var f = a / 100.0;
		return 0xFF000000 | Std.int(Math.min(255,
			r + (255 - r) * f)) << 16 | Std.int(Math.min(255, g + (255 - g) * f)) << 8 | Std.int(Math.min(255, b + (255 - b) * f));
	}

	static function _darken(c:Int, a:Int):Int {
		var r = (c >> 16) & 0xFF;
		var g = (c >> 8) & 0xFF;
		var b = c & 0xFF;
		var f = (100 - a) / 100.0;
		return 0xFF000000 | Std.int(r * f) << 16 | Std.int(g * f) << 8 | Std.int(b * f);
	}
}

// ═══════════════════════════════════════════════════════════════════════════════
//  PSESlider  — simple horizontal drag slider
// ═══════════════════════════════════════════════════════════════════════════════
private class PSESlider extends FlxSprite {
	public var value:Float;

	var _min:Float;
	var _max:Float;
	var _onChange:Float->Void;
	var _dragging:Bool = false;
	var _bg:FlxSprite;
	var _thumb:FlxSprite;

	public function new(x:Float, y:Float, w:Int, min:Float, max:Float, init:Float, ?cb:Float->Void) {
		super(x, y);
		makeGraphic(w, 6, 0xFF1A1A2E);
		_min = min;
		_max = max;
		value = init;
		_onChange = cb;
		_thumb = new FlxSprite(x, y - 2).makeGraphic(6, 10, 0xFF00C8F0);
		_updateThumb();
	}

	override private function set_cameras(c:Array<flixel.FlxCamera>):Array<flixel.FlxCamera> {
		if (_thumb != null)
			_thumb.cameras = c;
		return super.set_cameras(c);
	}

	// thumb needs to be added separately by whoever creates this
	override public function draw():Void {
		super.draw();
		if (_thumb != null)
			_thumb.draw();
	}

	override public function update(elapsed:Float):Void {
		super.update(elapsed);
		var cam = (cameras != null && cameras.length > 0) ? cameras[0] : FlxG.camera;
		var over = FlxG.mouse.overlaps(this, cam) || (if (_thumb != null) FlxG.mouse.overlaps(_thumb, cam) else false);
		if (FlxG.mouse.justPressed && over)
			_dragging = true;
		if (FlxG.mouse.justReleased)
			_dragging = false;
		if (_dragging) {
			var ratio = FlxMath.bound((FlxG.mouse.x - x) / width, 0, 1);
			value = _min + ratio * (_max - _min);
			_updateThumb();
			if (_onChange != null)
				_onChange(value);
		}
	}

	function _updateThumb():Void {
		if (_thumb == null)
			return;
		var ratio = (value - _min) / (_max - _min);
		_thumb.x = x + ratio * (width - 6);
		_thumb.y = y - 2;
	}
}

// ═══════════════════════════════════════════════════════════════════════════════
//  PSEContextMenu  — right-click context menu
// ═══════════════════════════════════════════════════════════════════════════════
private class PSEContextMenu extends FlxGroup {
	public var closed:Bool = false;

	var _items:Array<{btn:FlxSprite, lbl:FlxText, cb:Void->Void}> = [];

	static inline final W:Int = 180;
	static inline final IH:Int = 22;
	static inline final C_BG:Int = 0xFF1C1C30;
	static inline final C_HV:Int = 0xFF2C2C4A;
	static inline final C_BD:Int = 0xFF3A3A58;
	static inline final C_TX:Int = 0xFFCCCCEE;

	public function new(x:Float, y:Float, items:Array<{label:String, cb:Void->Void}>) {
		super();
		var h = items.length * IH + 2;
		// Clamp to screen
		var cx = Math.min(x, 1280 - W - 2);
		var cy = Math.min(y, 720 - h - 22);

		var bg = new FlxSprite(cx, cy).makeGraphic(W, h, C_BG);
		flixel.util.FlxSpriteUtil.drawRect(bg, 0, 0, W, 1, C_BD);
		flixel.util.FlxSpriteUtil.drawRect(bg, 0, h - 1, W, 1, C_BD);
		flixel.util.FlxSpriteUtil.drawRect(bg, 0, 0, 1, h, C_BD);
		flixel.util.FlxSpriteUtil.drawRect(bg, W - 1, 0, 1, h, C_BD);
		add(bg);

		for (i in 0...items.length) {
			var it = items[i];
			var iy = cy + i * IH + 1;
			var btn = new FlxSprite(cx, iy).makeGraphic(W, IH, C_BG);
			var lbl = new FlxText(cx + 10, iy + 5, W - 20, it.label, 9);
			lbl.setFormat(Paths.font('vcr.ttf'), 9, C_TX, LEFT);
			add(btn);
			add(lbl);
			_items.push({btn: btn, lbl: lbl, cb: it.cb});
		}
	}

	public function updateInput():Void {
		var cam = (cameras != null && cameras.length > 0) ? cameras[0] : FlxG.camera;
		// Close on click outside
		var overSelf = false;
		for (it in _items)
			if (FlxG.mouse.overlaps(it.btn, cam)) {
				overSelf = true;
				break;
			}
		if (FlxG.mouse.justPressed && !overSelf) {
			closed = true;
			return;
		}

		for (it in _items) {
			var ov = FlxG.mouse.overlaps(it.btn, cam);
			it.btn.makeGraphic(W, IH, ov ? C_HV : C_BG);
			if (ov && FlxG.mouse.justPressed && it.cb != null) {
				it.cb();
				closed = true;
				return;
			}
		}
	}
}
