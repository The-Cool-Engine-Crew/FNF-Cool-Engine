package funkin.debug.editors;

import funkin.debug.EditorDialogs.UnsavedChangesDialog;
import coolui.CoolInputText;
import coolui.CoolNumericStepper;
import coolui.CoolCheckBox;
import coolui.CoolDropDown;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.group.FlxGroup;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import coolui.CoolButton;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import funkin.cutscenes.dialogue.DialogueData;
import funkin.cutscenes.dialogue.DialogueData.*;
import funkin.cutscenes.dialogue.DialogueBoxImproved;
import funkin.gameplay.PlayState;
import funkin.transitions.StateTransition;
import haxe.Json;
import openfl.events.Event;
import openfl.net.FileReference;
#if sys
import lime.ui.FileDialog;
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

// ═══════════════════════════════════════════════════════════════════════════════
//  Data Typedefs
// ═══════════════════════════════════════════════════════════════════════════════

/** A track layer in the dialogue timeline. Same shape as PSETrack. */
typedef DLGTrack = {
	var id:String;
	var name:String;
	var type:String;   // 'dialogue' | 'portrait' | 'background' | 'music'
	var color:Int;
	var visible:Bool;
	var locked:Bool;
	var height:Int;
}

/** A clip placed on a timeline track. */
typedef DLGClipData = {
	var id:String;
	var trackId:String;
	var startSlot:Float;   // message-slot index where clip starts
	var duration:Float;    // how many slots the clip spans
	// Dialogue track
	@:optional var msgIndex:Int;
	@:optional var character:String;
	@:optional var text:String;
	@:optional var bubbleType:String;
	@:optional var speed:Float;
	@:optional var portrait:String;
	@:optional var boxSprite:String;
	@:optional var music:String;
	@:optional var sound:String;
	// Portrait track
	@:optional var portraitName:String;
	@:optional var portraitFlipX:Bool;
	// Background track
	@:optional var bgColor:String;
	// Music / Sound FX track
	@:optional var musicName:String;  // display name / label
	@:optional var soundFile:String;  // audio file name (relative to skin sounds/ or music/)
	@:optional var volume:Float;      // 0.0 – 1.0 (default 1.0)
	@:optional var loop:Bool;         // loop this clip's audio?
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DialogueEditor  — dual-mode: SCENE BUILDER + DIALOGUE EDITOR
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Dialogue Editor — full rework.
 *
 *  MODE A — SCENE BUILDER
 *   Visual canvas for building a skin (portraits, boxes, background).
 *   Drag elements, set positions/scales/flips. Save → config.json.
 *
 *  MODE B — DIALOGUE EDITOR
 *   FL-Studio-style timeline editor for dialogue conversations.
 *   Tracks: DIALOGUE | PORTRAIT | BACKGROUND | MUSIC.
 *   Each DIALOGUE clip = one message. Other tracks overlay changes.
 *
 *  Layout (both modes):
 *   ┌─────────────────── MENU BAR ──────────────────────────────┐
 *   │ File  Skin  Dialogue  View  Help   [SCENE | TIMELINE]     │
 *   ├────────────────────────────────────────────────────────────┤
 *   │ TOP BAR  (mode-sensitive controls)                        │
 *   ├─────────────────────────────────────────┬─────────────────┤
 *   │  MAIN AREA  (canvas | preview)          │  INSPECTOR      │
 *   ├─────────────────────────────────────────┤  (right panel)  │
 *   │  TIMELINE  (dialogue mode only)         │                 │
 *   ├─────────────────────────────────────────┴─────────────────┤
 *   │  STATUS BAR                                               │
 *   └────────────────────────────────────────────────────────────┘
 */
class DialogueEditor extends funkin.states.MusicBeatState {

	// ── Layout constants ──────────────────────────────────────────────────────
	static inline final SW:Int        = 1280;
	static inline final SH:Int        = 720;
	static inline final MENU_H:Int    = 22;
	static inline final TOPBAR_H:Int  = 38;
	static inline final STATUS_H:Int  = 20;
	static inline final INSP_W:Int    = 264;
	static inline final ASSET_W:Int   = 180;  // scene builder asset panel
	static inline final TL_LABEL_W:Int = 108;
	static inline final TL_RULER_H:Int = 22;
	static inline final TL_SCRUB_H:Int = 20;
	static inline final TL_TRACK_H:Int = 28;
	static inline final TL_SLOT_W:Int  = 90;  // px per message slot at zoom=1.0
	static inline final TL_ASSET_W:Int = 136; // asset panel width in timeline mode
	static inline final SPLITTER_H:Int = 6;
	static inline final MIN_VP_H:Int   = 80;
	static inline final MIN_TL_H:Int   = 60;
	static inline final HEADER_H:Int   = MENU_H + TOPBAR_H;

	// ── Colors ────────────────────────────────────────────────────────────────
	static inline final C_BG:Int         = 0xFF14141F;
	static inline final C_MENU:Int        = 0xFF0F0F1A;
	static inline final C_TOPBAR:Int      = 0xFF161622;
	static inline final C_PANEL:Int       = 0xFF1C1C2C;
	static inline final C_INSP:Int        = 0xFF181828;
	static inline final C_CANVAS:Int      = 0xFF111120;
	static inline final C_BORDER:Int      = 0xFF2E2E46;
	static inline final C_ACCENT:Int      = 0xFF00C8F0;
	static inline final C_ACCENT2:Int     = 0xFFFF6CA8;  // pink — dialogue accent
	static inline final C_ACCENT3:Int     = 0xFF00E894;  // mint
	static inline final C_TEXT:Int        = 0xFFE0E0F0;
	static inline final C_SUBTEXT:Int     = 0xFF626280;
	static inline final C_TL_BG:Int       = 0xFF0D0D1A;
	static inline final C_TL_RULER:Int    = 0xFF141420;
	static inline final C_UNSAVED:Int     = 0xFFFFAA00;
	static inline final C_SELECT:Int      = 0xFFFFFFFF;
	static inline final C_MENU_HOVER:Int  = 0xFF252538;
	static inline final C_PLAYHEAD:Int    = 0xFFFF3355;

	// ── Default tracks ────────────────────────────────────────────────────────
	static final DEFAULT_TRACKS:Array<DLGTrack> = [
		{ id: 'dialogue',   name: 'DIALOGUE',   type: 'dialogue',   color: 0xFFFF6CA8, visible: true, locked: false, height: TL_TRACK_H },
		{ id: 'portrait',   name: 'PORTRAIT',   type: 'portrait',   color: 0xFF00C8F0, visible: true, locked: false, height: TL_TRACK_H },
		{ id: 'background', name: 'BACKGROUND', type: 'background', color: 0xFF9944FF, visible: true, locked: false, height: TL_TRACK_H },
		{ id: 'music',      name: 'MUSIC',      type: 'music',      color: 0xFF00E894, visible: true, locked: false, height: TL_TRACK_H },
		{ id: 'sound',      name: 'SOUND FX',   type: 'sound',      color: 0xFFFFCC44, visible: true, locked: false, height: TL_TRACK_H },
	];

	// ── Editor mode ───────────────────────────────────────────────────────────
	var _mode:String = 'scene';   // 'scene' | 'timeline'

	// ── Cameras ───────────────────────────────────────────────────────────────
	var camHUD:FlxCamera;
	var camUI:FlxCamera;

	// ── Shared data ───────────────────────────────────────────────────────────
	var currentSkin:DialogueSkin;
	var currentSkinName:String = 'default';
	var conversation:DialogueConversation;
	var songName:String = 'Test';
	var hasUnsaved:Bool = false;

	// ── Undo stack ────────────────────────────────────────────────────────────
	var _undoStack:Array<String> = [];
	var _redoStack:Array<String> = [];
	static inline final MAX_UNDO:Int = 30;

	// ── Timeline data ─────────────────────────────────────────────────────────
	var tracks:Array<DLGTrack> = [];
	var clips:Array<DLGClipData> = [];
	var selectedClipId:String = '';
	var tlScrollSlot:Float = 0;   // scroll offset in slots
	var tlZoom:Float = 1.0;       // zoom multiplier (1.0 = TL_SLOT_W px/slot)
	var _trackScrollY:Int = 0;

	// ── Timeline drag state ───────────────────────────────────────────────────
	var _dragClip:DLGClipBlock = null;
	var _dragClipOffSlot:Float = 0;
	var _resizeClip:DLGClipBlock = null;
	var _resizeOrigDur:Float = 0;
	var _resizeStartX:Float = 0;
	var _hScrollDrag:Bool = false;
	var _hScrollDragOff:Float = 0;
	var _lastClickTime:Float = 0;
	var _lastClickX:Float = 0;
	var _lastClickY:Float = 0;
	var _previewMsgIdx:Int = 0;

	// ── Viewport / splitter ───────────────────────────────────────────────────
	var _vpHeight:Int = 300;
	var _splitterDrag:Bool = false;

	// ── Scene builder data ────────────────────────────────────────────────────
	// Canvas elements: index → {type:'portrait'|'box', key:String, sprite:FlxSprite}
	var _canvasElements:Array<{type:String, key:String, sprite:FlxSprite}> = [];
	var _selectedElementIdx:Int = -1;
	var _dragElementIdx:Int = -1;
	var _dragElemOffX:Float = 0;
	var _dragElemOffY:Float = 0;
	var _canvasBg:FlxSprite;
	var _canvasFrame:FlxSprite;
	static inline final CANVAS_X:Int  = ASSET_W;
	static inline final CANVAS_W:Int  = SW - ASSET_W - INSP_W;

	// ── UI — Menu bar ─────────────────────────────────────────────────────────
	var _menuBg:FlxSprite;
	var _menuItems:Array<DLGMenuBtn> = [];
	var _activeMenu:Int = -1;
	var _menuDropdowns:Array<DLGDropdownPanel> = [];
	var _modeSwitchBtns:Array<DLGBtn> = [];

	// ── UI — Top bar ──────────────────────────────────────────────────────────
	var _topBg:FlxSprite;
	var _topBarSprites:Array<flixel.FlxBasic> = [];
	// Scene builder top bar
	var _btnNewSkin:DLGBtn;
	var _btnLoadSkin:DLGBtn;
	var _btnSaveSkin:DLGBtn;
	var _skinNameTxt:FlxText;
	// Dialogue editor top bar
	var _btnNewConv:DLGBtn;
	var _btnLoadConv:DLGBtn;
	var _btnSaveConv:DLGBtn;
	var _btnTestConv:DLGBtn;
	var _convInfoTxt:FlxText;
	var _btnAddMsg:DLGBtn;
	var _btnRemoveMsg:DLGBtn;
	var _unsavedDot:FlxSprite;

	// ── UI — Scene builder ────────────────────────────────────────────────────
	var _assetPanelBg:FlxSprite;
	var _assetPanelTitle:FlxText;
	var _assetPortraitTitle:FlxText;
	var _assetBoxTitle:FlxText;
	var _assetItems:Array<{bg:FlxSprite, lbl:FlxText, key:String, type:String}> = [];
	var _btnAddPortrait:DLGBtn;
	var _btnAddBox:DLGBtn;
	var _btnAddBackground:DLGBtn;
	var _btnAddOverlay:DLGBtn;
	var _btnRemoveElement:DLGBtn;
	var _sceneGroup:FlxGroup;

	// ── UI — Timeline ─────────────────────────────────────────────────────────
	var _tlBg:FlxSprite;
	var _tlRulerBg:FlxSprite;
	var _tlRulerLabels:Array<FlxText> = [];
	var _tlRulerTicks:Array<FlxSprite> = [];
	var _tlPlayhead:FlxSprite;
	var _tlLabelColBg:FlxSprite;
	var _trackBgs:Array<FlxSprite> = [];
	var _trackLabels:Array<FlxText> = [];
	var _trackLockBtns:Array<DLGBtn> = [];
	var _trackVisBtns:Array<DLGBtn> = [];
	var _trackColorStrips:Array<FlxSprite> = [];
	var _clipBlocks:Array<DLGClipBlock> = [];
	var _tlGridLines:Array<FlxSprite> = [];
	var _tlHScrollBg:FlxSprite;
	var _tlHScrollThumb:FlxSprite;
	var _tlScrollUp:DLGBtn;
	var _tlScrollDown:DLGBtn;
	var _tlGroup:FlxGroup;
	var _splitterSprite:FlxSprite;

	// ── UI — Timeline asset panel (timeline mode, left of preview) ────────────
	var _tlAssetPanelBg:FlxSprite;
	var _tlAssetPanelTitle:FlxText;
	var _tlAssetItemsList:Array<{bg:FlxSprite, lbl:FlxText, key:String, type:String}> = [];
	// Asset-to-timeline drag state
	var _tlDragAssetKey:String  = '';
	var _tlDragAssetType:String = '';
	var _tlGhostClip:FlxSprite  = null;
	var _tlGhostLabel:FlxText   = null;

	// ── UI — Preview (dialogue editor) ────────────────────────────────────────
	var _previewBg:FlxSprite;
	var _previewLabel:FlxText;
	var _previewBox:DialogueBoxImproved;
	var _previewGroup:FlxGroup;

	// ── UI — Inspector ────────────────────────────────────────────────────────
	var _inspBg:FlxSprite;
	var _inspTitle:FlxText;
	var _inspSep:FlxSprite;
	var _inspFields:Array<{lbl:FlxText, input:CoolInputText}> = [];
	var _inspGroup:FlxGroup;
	// Specific inspector inputs
	var _inspCharInput:CoolInputText;
	var _inspTextInput:CoolInputText;
	var _inspBubbleInput:CoolInputText;
	var _inspSpeedInput:CoolInputText;
	var _inspPortraitInput:CoolInputText;
	var _inspBoxInput:CoolInputText;
	var _inspMusicInput:CoolInputText;
	var _inspDurationInput:CoolInputText;
	var _inspStartSlotLbl:FlxText;
	// Dialogue field labels (for show/hide toggling)
	var _inspDlgLbls:Array<FlxText> = [];
	// Audio inspector fields (shown instead of dialogue fields for music/sound clips)
	var _inspAudioFileInput:CoolInputText;
	var _inspVolumeInput:CoolInputText;
	var _inspLoopInput:CoolInputText;
	var _btnBrowseAudio:DLGBtn;
	var _inspAudioItems:Array<flixel.FlxBasic> = [];  // all audio-section sprites for show/hide
	// Scene builder element inspector
	var _inspElemXInput:CoolInputText;
	var _inspElemYInput:CoolInputText;
	var _inspElemScaleXInput:CoolInputText;
	var _inspElemScaleYInput:CoolInputText;
	var _inspElemAnimInput:CoolInputText;
	var _inspElemFlipBtn:DLGBtn;
	var _inspApplyBtn:DLGBtn;
	// Skin inspector
	var _inspSkinStyleInput:CoolInputText;
	var _inspSkinBgInput:CoolInputText;
	var _inspSkinFadeInput:CoolInputText;
	// Scene builder import audio buttons
	var _btnImportMusic:DLGBtn;
	var _btnImportSound:DLGBtn;

	// ── UI — Status bar ───────────────────────────────────────────────────────
	var _statusBg:FlxSprite;
	var _statusTxt:FlxText;

	// ── Internal ──────────────────────────────────────────────────────────────
	static var _uid:Int = 0;
	var _windowCloseFn:Void->Void = null;
	var _unsavedDlg:UnsavedChangesDialog = null;

	// ── OS drag-and-drop state ────────────────────────────────────────────────
	var _pendingDropPath:String  = '';
	var _dropOverlay:FlxGroup    = null;
	var _dropHintTxt:FlxText     = null;  // persistent tip on status bar

	// ── Helpers ───────────────────────────────────────────────────────────────
	inline function _tlY():Int
		return HEADER_H + _vpHeight + SPLITTER_H;

	inline function _tlH():Int {
		var n = Std.int(Math.min(tracks.length - _trackScrollY, 6));
		return TL_RULER_H + n * TL_TRACK_H + TL_SCRUB_H + 12;
	}

	inline function _tlAreaW():Int
		return SW - TL_LABEL_W - INSP_W;

	inline function _slotToX(slot:Float):Float
		return TL_LABEL_W + (slot - tlScrollSlot) * TL_SLOT_W * tlZoom;

	inline function _xToSlot(px:Float):Float
		return (px - TL_LABEL_W) / (TL_SLOT_W * tlZoom) + tlScrollSlot;

	inline function _getTrackY(trackIdx:Int):Int
		return _tlY() + TL_RULER_H + (trackIdx - _trackScrollY) * TL_TRACK_H;

	inline function _mainAreaH():Int
		return SH - HEADER_H - STATUS_H - _tlH() - SPLITTER_H;

	inline function _mainAreaY():Int
		return HEADER_H;

	// ═════════════════════════════════════════════════════════════════════════
	//  CREATE
	// ═════════════════════════════════════════════════════════════════════════

	override public function create():Void {
		funkin.debug.themes.EditorTheme.load();
		funkin.audio.MusicManager.play('chartEditorLoop/chartEditorLoop', 0.7);

		if (PlayState.SONG != null && PlayState.SONG.song != null)
			songName = PlayState.SONG.song;

		// Default viewport height
		var minTlH = TL_RULER_H + TL_TRACK_H * 4 + TL_SCRUB_H + 12;
		_vpHeight = Std.int(Math.max(MIN_VP_H, SH - HEADER_H - SPLITTER_H - minTlH - STATUS_H - 20));

		_setupCameras();
		_initData();
		_buildBackground();
		_buildMenuBar();
		_buildTopBar();
		_buildMainArea();
		_buildSplitter();
		_buildTimeline();
		_buildInspector();
		_buildStatusBar();

		// Apply initial mode
		_switchMode('scene', true);

		_showStatus('Dialogue Editor  |  Ctrl+S = save  |  Ctrl+Z = undo  |  F1 = help');

		#if sys
		_windowCloseFn = function() {
			if (hasUnsaved) try { _doSave(); } catch (_) {}
		};
		lime.app.Application.current.window.onClose.add(_windowCloseFn);
		lime.app.Application.current.window.onDropFile.add(_onDropFile);
		#end

		super.create();
	}

	// ─────────────────────────────────────────────────────────────────────────
	function _setupCameras():Void {
		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		FlxG.cameras.reset(camHUD);

		camUI = new FlxCamera();
		camUI.bgColor.alpha = 0;
		FlxG.cameras.add(camUI, false);

		@:privateAccess FlxCamera._defaultCameras = [camHUD];
	}

	// ─────────────────────────────────────────────────────────────────────────
	function _initData():Void {
		// Default tracks for timeline
		tracks = [];
		for (t in DEFAULT_TRACKS)
			tracks.push({id: t.id, name: t.name, type: t.type, color: t.color, visible: t.visible, locked: t.locked, height: t.height});

		clips = [];

		// Default empty skin
		currentSkin = DialogueData.createEmptySkin(currentSkinName, 'normal');
		conversation = DialogueData.createEmptyConversation('intro', currentSkinName);
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  UI BUILD — BACKGROUND
	// ═════════════════════════════════════════════════════════════════════════

	function _buildBackground():Void {
		var bg = new FlxSprite(0, 0).makeGraphic(SW, SH, C_BG);
		bg.scrollFactor.set();
		bg.cameras = [camHUD];
		add(bg);
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  UI BUILD — MENU BAR
	// ═════════════════════════════════════════════════════════════════════════

	function _buildMenuBar():Void {
		_menuBg = new FlxSprite(0, 0).makeGraphic(SW, MENU_H, C_MENU);
		_menuBg.scrollFactor.set();
		_menuBg.cameras = [camHUD];
		add(_menuBg);

		// Bottom border
		var line = new FlxSprite(0, MENU_H - 1).makeGraphic(SW, 1, C_BORDER);
		line.scrollFactor.set();
		line.cameras = [camHUD];
		add(line);

		var menuDefs:Array<{label:String, items:Array<{label:String, cb:Void->Void, sep:Bool}>}> = [
			{
				label: 'File',
				items: [
					{ label: 'New Skin',           cb: _doNewSkin,          sep: false },
					{ label: 'Load Skin…',          cb: _doLoadSkin,         sep: false },
					{ label: 'Save Skin',           cb: _doSaveSkin,         sep: true  },
					{ label: 'New Conversation',    cb: _doNewConv,          sep: false },
					{ label: 'Load Conversation…',  cb: _doLoadConv,         sep: false },
					{ label: 'Save Conversation',   cb: _doSaveConv,         sep: true  },
					{ label: 'Back to Editor Hub',  cb: _doBack,             sep: false },
				]
			},
			{
				label: 'Skin',
				items: [
					{ label: 'Add Portrait…',    cb: _doAddPortrait,  sep: false },
					{ label: 'Add Box…',         cb: _doAddBox,       sep: false },
					{ label: 'Remove Selected',  cb: _doRemoveSelected, sep: false },
				]
			},
			{
				label: 'Dialogue',
				items: [
					{ label: 'Add Message',      cb: _doAddMessage,    sep: false },
					{ label: 'Remove Message',   cb: _doRemoveMessage, sep: false },
					{ label: 'Duplicate Message',cb: _doDuplicateMessage, sep: true },
					{ label: 'Import Skin…',     cb: _doImportSkin,    sep: false },
					{ label: 'Test Dialogue',    cb: _doTestDialogue,  sep: false },
				]
			},
			{
				label: 'Edit',
				items: [
					{ label: 'Undo  Ctrl+Z', cb: _doUndo, sep: false },
					{ label: 'Redo  Ctrl+Y', cb: _doRedo, sep: true  },
					{ label: 'Move Up',      cb: _doMoveUp,   sep: false },
					{ label: 'Move Down',    cb: _doMoveDown, sep: false },
				]
			},
			{
				label: 'View',
				items: [
					{ label: 'Zoom In',      cb: () -> { tlZoom = FlxMath.bound(tlZoom * 1.25, 0.3, 4.0); _rebuildTimeline(); }, sep: false },
					{ label: 'Zoom Out',     cb: () -> { tlZoom = FlxMath.bound(tlZoom * 0.8, 0.3, 4.0); _rebuildTimeline(); }, sep: false },
					{ label: 'Reset Zoom',   cb: () -> { tlZoom = 1.0; _rebuildTimeline(); }, sep: false },
				]
			},
			{
				label: 'Help',
				items: [
					{ label: 'Controls', cb: _showHelp, sep: false },
				]
			},
		];

		var xCursor = 4;
		for (i in 0...menuDefs.length) {
			var def = menuDefs[i];
			var btn = new DLGMenuBtn(xCursor, 0, def.label, C_MENU, C_MENU_HOVER, C_TEXT, i, (idx, bx) -> {
				if (_activeMenu == idx) {
					_closeMenus();
				} else {
					_closeMenus();
					_activeMenu = idx;
					var w = 180;
					var dd = new DLGDropdownPanel(bx, MENU_H, w, menuDefs[idx].items);
					dd.cameras = [camUI];
					add(dd);
					_menuDropdowns = [dd];
				}
			});
			btn.scrollFactor.set();
			btn.cameras = [camHUD];
			add(btn);
			btn.label.cameras = [camHUD];
			_menuItems.push(btn);
			xCursor += Std.int(btn.width) + 2;
		}

		// Mode switch buttons (right side)
		var modeLabels    = ['SCENE', 'TIMELINE'];
		var modeTooltips  = [
			'SCENE BUILDER — arrastra retratos, cajas de texto y ajusta colores/posiciones de la skin',
			'DIALOGUE EDITOR — crea mensajes y organiza clips en el timeline'
		];
		var modeW = 72;
		var modeX = SW - (modeW + 4) * 2 - 4;
		for (i in 0...2) {
			var col = i == 0 ? C_ACCENT2 : 0xFF252540;
			var btn = new DLGBtn(modeX + i * (modeW + 4), 2, modeW, MENU_H - 4, modeLabels[i], col, C_BG, null);
			btn.tooltip = modeTooltips[i];
			btn.scrollFactor.set();
			btn.cameras = [camHUD];
			btn.label.cameras = [camHUD];
			var captI = i;
			btn.onClick = () -> _switchMode(captI == 0 ? 'scene' : 'timeline');
			add(btn);
			_modeSwitchBtns.push(btn);
		}
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  UI BUILD — TOP BAR
	// ═════════════════════════════════════════════════════════════════════════

	function _buildTopBar():Void {
		_topBg = new FlxSprite(0, MENU_H).makeGraphic(SW, TOPBAR_H, C_TOPBAR);
		_topBg.scrollFactor.set();
		_topBg.cameras = [camHUD];
		add(_topBg);

		var line = new FlxSprite(0, MENU_H + TOPBAR_H - 1).makeGraphic(SW, 1, C_BORDER);
		line.scrollFactor.set();
		line.cameras = [camHUD];
		add(line);

		var ty = MENU_H + (TOPBAR_H - 14) / 2;
		var x = 8;

		// ── Scene builder buttons ──────────────────────────────────────────
		_btnNewSkin = new DLGBtn(x, MENU_H + 4, 70, 28, 'NEW SKIN', C_PANEL, C_ACCENT, _doNewSkin);
		_btnNewSkin.scrollFactor.set(); _btnNewSkin.cameras = [camHUD]; _btnNewSkin.label.cameras = [camHUD]; add(_btnNewSkin); _topBarSprites.push(_btnNewSkin); _topBarSprites.push(_btnNewSkin.label);
		x += 74;

		_btnLoadSkin = new DLGBtn(x, MENU_H + 4, 80, 28, 'LOAD SKIN', C_PANEL, C_TEXT, _doLoadSkin);
		_btnLoadSkin.tooltip = 'Cargar skin de diálogo (config.json)';
		_btnLoadSkin.scrollFactor.set(); _btnLoadSkin.cameras = [camHUD]; _btnLoadSkin.label.cameras = [camHUD]; add(_btnLoadSkin); _topBarSprites.push(_btnLoadSkin); _topBarSprites.push(_btnLoadSkin.label);
		x += 84;

		_btnSaveSkin = new DLGBtn(x, MENU_H + 4, 80, 28, 'SAVE SKIN', C_ACCENT, C_BG, _doSaveSkin);
		_btnSaveSkin.tooltip = 'Guardar skin → assets/cutscenes/dialogue/<nombre>/config.json';
		_btnSaveSkin.scrollFactor.set(); _btnSaveSkin.cameras = [camHUD]; _btnSaveSkin.label.cameras = [camHUD]; add(_btnSaveSkin); _topBarSprites.push(_btnSaveSkin); _topBarSprites.push(_btnSaveSkin.label);
		x += 80;

		_skinNameTxt = new FlxText(x, ty, 200, 'skin: $currentSkinName', 10);
		_skinNameTxt.setFormat(Paths.font('vcr.ttf'), 10, C_SUBTEXT, LEFT);
		_skinNameTxt.scrollFactor.set(); _skinNameTxt.cameras = [camHUD]; add(_skinNameTxt); _topBarSprites.push(_skinNameTxt);

		// ── Dialogue editor buttons ────────────────────────────────────────
		x = 8;
		_btnNewConv = new DLGBtn(x, MENU_H + 4, 60, 28, 'NEW', C_PANEL, C_ACCENT2, _doNewConv);
		_btnNewConv.tooltip = 'Nueva conversación vacía';
		_btnNewConv.scrollFactor.set(); _btnNewConv.cameras = [camHUD]; _btnNewConv.label.cameras = [camHUD]; add(_btnNewConv); _topBarSprites.push(_btnNewConv); _topBarSprites.push(_btnNewConv.label);
		x += 64;

		_btnLoadConv = new DLGBtn(x, MENU_H + 4, 76, 28, 'LOAD CONV', C_PANEL, C_TEXT, _doLoadConv);
		_btnLoadConv.tooltip = 'Cargar conversación desde archivo JSON (intro.json / outro.json)';
		_btnLoadConv.scrollFactor.set(); _btnLoadConv.cameras = [camHUD]; _btnLoadConv.label.cameras = [camHUD]; add(_btnLoadConv); _topBarSprites.push(_btnLoadConv); _topBarSprites.push(_btnLoadConv.label);
		x += 80;

		_btnSaveConv = new DLGBtn(x, MENU_H + 4, 76, 28, 'SAVE CONV', C_ACCENT2, C_BG, _doSaveConv);
		_btnSaveConv.tooltip = 'Guardar conversación → assets/songs/<cancion>/<nombre>.json';
		_btnSaveConv.scrollFactor.set(); _btnSaveConv.cameras = [camHUD]; _btnSaveConv.label.cameras = [camHUD]; add(_btnSaveConv); _topBarSprites.push(_btnSaveConv); _topBarSprites.push(_btnSaveConv.label);
		x += 80;

		_btnTestConv = new DLGBtn(x, MENU_H + 4, 60, 28, '▶ TEST', C_ACCENT3, C_BG, _doTestDialogue);
		_btnTestConv.scrollFactor.set(); _btnTestConv.cameras = [camHUD]; _btnTestConv.label.cameras = [camHUD]; add(_btnTestConv); _topBarSprites.push(_btnTestConv); _topBarSprites.push(_btnTestConv.label);
		x += 68;

		_btnAddMsg = new DLGBtn(x, MENU_H + 4, 28, 28, '+', C_PANEL, C_ACCENT2, _doAddMessage);
		_btnAddMsg.scrollFactor.set(); _btnAddMsg.cameras = [camHUD]; _btnAddMsg.label.cameras = [camHUD]; add(_btnAddMsg); _topBarSprites.push(_btnAddMsg); _topBarSprites.push(_btnAddMsg.label);
		x += 32;

		_btnRemoveMsg = new DLGBtn(x, MENU_H + 4, 28, 28, '–', C_PANEL, 0xFFFF4444, _doRemoveMessage);
		_btnRemoveMsg.scrollFactor.set(); _btnRemoveMsg.cameras = [camHUD]; _btnRemoveMsg.label.cameras = [camHUD]; add(_btnRemoveMsg); _topBarSprites.push(_btnRemoveMsg); _topBarSprites.push(_btnRemoveMsg.label);
		x += 36;

		_convInfoTxt = new FlxText(x, ty, 300, 'song: $songName  |  conv: ${conversation.name}', 10);
		_convInfoTxt.setFormat(Paths.font('vcr.ttf'), 10, C_SUBTEXT, LEFT);
		_convInfoTxt.scrollFactor.set(); _convInfoTxt.cameras = [camHUD]; add(_convInfoTxt); _topBarSprites.push(_convInfoTxt);

		// Unsaved dot
		_unsavedDot = new FlxSprite(SW - INSP_W - 14, MENU_H + 14).makeGraphic(6, 6, C_UNSAVED);
		_unsavedDot.scrollFactor.set(); _unsavedDot.cameras = [camHUD]; _unsavedDot.visible = false; add(_unsavedDot);
		_topBarSprites.push(_unsavedDot);
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  UI BUILD — MAIN AREA (Scene Builder / Preview)
	// ═════════════════════════════════════════════════════════════════════════

	function _buildMainArea():Void {
		_buildSceneBuilder();
		_buildPreview();
	}

	function _buildSceneBuilder():Void {
		_sceneGroup = new FlxGroup();

		var mainH = _mainAreaH();

		// Asset panel background
		_assetPanelBg = new FlxSprite(0, _mainAreaY()).makeGraphic(ASSET_W, mainH, C_PANEL);
		_assetPanelBg.scrollFactor.set(); _assetPanelBg.cameras = [camHUD];
		_sceneGroup.add(_assetPanelBg);

		// Asset panel right border
		var assetBorder = new FlxSprite(ASSET_W - 1, _mainAreaY()).makeGraphic(1, mainH, C_BORDER);
		assetBorder.scrollFactor.set(); assetBorder.cameras = [camHUD];
		_sceneGroup.add(assetBorder);

		// Asset panel title
		_assetPanelTitle = new FlxText(8, _mainAreaY() + 8, ASSET_W - 16, 'ASSETS', 10);
		_assetPanelTitle.setFormat(Paths.font('vcr.ttf'), 10, C_ACCENT, LEFT);
		_assetPanelTitle.scrollFactor.set(); _assetPanelTitle.cameras = [camHUD];
		_sceneGroup.add(_assetPanelTitle);

		// Section labels
		_assetPortraitTitle = new FlxText(8, _mainAreaY() + 26, ASSET_W - 16, 'PORTRAITS', 9);
		_assetPortraitTitle.setFormat(Paths.font('vcr.ttf'), 9, C_SUBTEXT, LEFT);
		_assetPortraitTitle.scrollFactor.set(); _assetPortraitTitle.cameras = [camHUD];
		_sceneGroup.add(_assetPortraitTitle);

		_assetBoxTitle = new FlxText(8, _mainAreaY() + 100, ASSET_W - 16, 'BOXES', 9);
		_assetBoxTitle.setFormat(Paths.font('vcr.ttf'), 9, C_SUBTEXT, LEFT);
		_assetBoxTitle.scrollFactor.set(); _assetBoxTitle.cameras = [camHUD];
		_sceneGroup.add(_assetBoxTitle);

		// Hint text below title
		var assetHint = new FlxText(8, _mainAreaY() + 16, ASSET_W - 16, 'click=select  drag=move', 8);
		assetHint.setFormat(Paths.font('vcr.ttf'), 8, C_SUBTEXT, LEFT);
		assetHint.scrollFactor.set(); assetHint.cameras = [camHUD];
		_sceneGroup.add(assetHint);

		// Add portrait / box / background / overlay buttons
		_btnAddPortrait = new DLGBtn(8, _mainAreaY() + 152, ASSET_W - 16, 22, '+ PORTRAIT', 0xFF0E2840, C_ACCENT, _doAddPortrait);
		_btnAddPortrait.scrollFactor.set(); _btnAddPortrait.cameras = [camHUD]; _btnAddPortrait.label.cameras = [camHUD];
		_sceneGroup.add(_btnAddPortrait); _sceneGroup.add(_btnAddPortrait.label);

		_btnAddBox = new DLGBtn(8, _mainAreaY() + 178, ASSET_W - 16, 22, '+ BOX', 0xFF0E2820, C_ACCENT3, _doAddBox);
		_btnAddBox.scrollFactor.set(); _btnAddBox.cameras = [camHUD]; _btnAddBox.label.cameras = [camHUD];
		_sceneGroup.add(_btnAddBox); _sceneGroup.add(_btnAddBox.label);

		_btnAddBackground = new DLGBtn(8, _mainAreaY() + 204, ASSET_W - 16, 22, '+ BACKGROUND', 0xFF2A1505, 0xFFFF9933, _doAddBackground);
		_btnAddBackground.scrollFactor.set(); _btnAddBackground.cameras = [camHUD]; _btnAddBackground.label.cameras = [camHUD];
		_sceneGroup.add(_btnAddBackground); _sceneGroup.add(_btnAddBackground.label);

		_btnAddOverlay = new DLGBtn(8, _mainAreaY() + 230, ASSET_W - 16, 22, '+ OVERLAY', 0xFF152205, 0xFF88CC55, _doAddOverlay);
		_btnAddOverlay.scrollFactor.set(); _btnAddOverlay.cameras = [camHUD]; _btnAddOverlay.label.cameras = [camHUD];
		_sceneGroup.add(_btnAddOverlay); _sceneGroup.add(_btnAddOverlay.label);

		// Audio import section
		var audioSep = new FlxSprite(4, _mainAreaY() + 256).makeGraphic(ASSET_W - 8, 1, C_BORDER);
		audioSep.alpha = 0.5; audioSep.scrollFactor.set(); audioSep.cameras = [camHUD];
		_sceneGroup.add(audioSep);
		var audioTitleLbl = new FlxText(8, _mainAreaY() + 260, ASSET_W - 16, 'AUDIO ASSETS', 8);
		audioTitleLbl.setFormat(Paths.font('vcr.ttf'), 8, C_SUBTEXT, LEFT);
		audioTitleLbl.scrollFactor.set(); audioTitleLbl.cameras = [camHUD];
		_sceneGroup.add(audioTitleLbl);

		_btnImportMusic = new DLGBtn(8, _mainAreaY() + 272, ASSET_W - 16, 22, '+ MUSIC', 0xFF05200D, 0xFF00E894, _doImportMusic);
		_btnImportMusic.scrollFactor.set(); _btnImportMusic.cameras = [camHUD]; _btnImportMusic.label.cameras = [camHUD];
		_sceneGroup.add(_btnImportMusic); _sceneGroup.add(_btnImportMusic.label);

		_btnImportSound = new DLGBtn(8, _mainAreaY() + 298, ASSET_W - 16, 22, '+ SOUND FX', 0xFF201E04, 0xFFFFCC44, _doImportSound);
		_btnImportSound.scrollFactor.set(); _btnImportSound.cameras = [camHUD]; _btnImportSound.label.cameras = [camHUD];
		_sceneGroup.add(_btnImportSound); _sceneGroup.add(_btnImportSound.label);

		_btnRemoveElement = new DLGBtn(8, _mainAreaY() + 326, ASSET_W - 16, 22, 'REMOVE', 0xFF2A0E0E, 0xFFFF4444, _doRemoveSelected);
		_btnRemoveElement.scrollFactor.set(); _btnRemoveElement.cameras = [camHUD]; _btnRemoveElement.label.cameras = [camHUD];
		_sceneGroup.add(_btnRemoveElement); _sceneGroup.add(_btnRemoveElement.label);

		// Canvas area
		var canvasH = mainH;
		_canvasBg = new FlxSprite(CANVAS_X, _mainAreaY()).makeGraphic(CANVAS_W, canvasH, C_CANVAS);
		_canvasBg.scrollFactor.set(); _canvasBg.cameras = [camHUD];
		_sceneGroup.add(_canvasBg);

		// Canvas frame (1280x720 at scale)
		var frameW = Std.int(CANVAS_W * 0.85);
		var frameH = Std.int(frameW * 720 / 1280);
		var frameX = CANVAS_X + (CANVAS_W - frameW) / 2;
		var frameY = _mainAreaY() + (canvasH - frameH) / 2;
		_canvasFrame = new FlxSprite(frameX, frameY).makeGraphic(frameW, frameH, 0xFF080818);
		_canvasFrame.scrollFactor.set(); _canvasFrame.cameras = [camHUD];
		_sceneGroup.add(_canvasFrame);

		// Canvas border
		var frameBorder = new FlxSprite(frameX - 1, frameY - 1).makeGraphic(frameW + 2, frameH + 2, C_BORDER);
		frameBorder.scrollFactor.set(); frameBorder.cameras = [camHUD];
		_sceneGroup.add(frameBorder);
		_sceneGroup.add(_canvasFrame);

		// Canvas label
		var canvasLbl = new FlxText(frameX + 4, frameY + 4, 200, '1280 × 720', 9);
		canvasLbl.setFormat(Paths.font('vcr.ttf'), 9, C_SUBTEXT, LEFT);
		canvasLbl.scrollFactor.set(); canvasLbl.cameras = [camHUD];
		_sceneGroup.add(canvasLbl);

		add(_sceneGroup);
	}

	function _buildPreview():Void {
		_previewGroup = new FlxGroup();

		var mainH    = _mainAreaH();
		var previewX = TL_ASSET_W;
		var previewW = SW - INSP_W - TL_ASSET_W;

		// ── Left asset panel ──────────────────────────────────────────────────
		_tlAssetPanelBg = new FlxSprite(0, _mainAreaY()).makeGraphic(TL_ASSET_W, mainH, C_PANEL);
		_tlAssetPanelBg.scrollFactor.set(); _tlAssetPanelBg.cameras = [camHUD];
		_previewGroup.add(_tlAssetPanelBg);

		// Right border of asset panel
		var apBorder = new FlxSprite(TL_ASSET_W - 1, _mainAreaY()).makeGraphic(1, mainH, C_BORDER);
		apBorder.scrollFactor.set(); apBorder.cameras = [camHUD];
		_previewGroup.add(apBorder);

		// Asset panel title
		_tlAssetPanelTitle = new FlxText(4, _mainAreaY() + 5, TL_ASSET_W - 8, 'SKIN ASSETS', 9);
		_tlAssetPanelTitle.setFormat(Paths.font('vcr.ttf'), 9, C_ACCENT, LEFT);
		_tlAssetPanelTitle.scrollFactor.set(); _tlAssetPanelTitle.cameras = [camHUD];
		_previewGroup.add(_tlAssetPanelTitle);

		// Hint
		var apHint = new FlxText(4, _mainAreaY() + 17, TL_ASSET_W - 8, 'drag → track', 8);
		apHint.setFormat(Paths.font('vcr.ttf'), 8, C_SUBTEXT, LEFT);
		apHint.scrollFactor.set(); apHint.cameras = [camHUD];
		_previewGroup.add(apHint);

		// Separator under hint
		var apSep = new FlxSprite(2, _mainAreaY() + 28).makeGraphic(TL_ASSET_W - 4, 1, C_BORDER);
		apSep.scrollFactor.set(); apSep.cameras = [camHUD];
		_previewGroup.add(apSep);

		// ── Preview area ─────────────────────────────────────────────────────
		_previewBg = new FlxSprite(previewX, _mainAreaY()).makeGraphic(previewW, mainH, C_CANVAS);
		_previewBg.scrollFactor.set(); _previewBg.cameras = [camHUD];
		_previewGroup.add(_previewBg);

		_previewLabel = new FlxText(previewX + 8, _mainAreaY() + 6, 200, 'PREVIEW', 10);
		_previewLabel.setFormat(Paths.font('vcr.ttf'), 10, C_ACCENT2, LEFT);
		_previewLabel.scrollFactor.set(); _previewLabel.cameras = [camHUD];
		_previewGroup.add(_previewLabel);

		var hintTxt = new FlxText(previewX, _mainAreaY() + mainH / 2 - 20, previewW,
			'Select a message clip in the timeline\nto preview it here', 11);
		hintTxt.setFormat(Paths.font('vcr.ttf'), 11, C_SUBTEXT, CENTER);
		hintTxt.scrollFactor.set(); hintTxt.cameras = [camHUD];
		_previewGroup.add(hintTxt);

		add(_previewGroup);
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  UI BUILD — SPLITTER
	// ═════════════════════════════════════════════════════════════════════════

	function _buildSplitter():Void {
		_splitterSprite = new FlxSprite(0, HEADER_H + _vpHeight).makeGraphic(SW, SPLITTER_H, C_BORDER);
		_splitterSprite.scrollFactor.set();
		_splitterSprite.cameras = [camHUD];
		add(_splitterSprite);
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  UI BUILD — TIMELINE
	// ═════════════════════════════════════════════════════════════════════════

	function _buildTimeline():Void {
		_tlGroup = new FlxGroup();

		var tlY = _tlY();
		var tlH = _tlH();
		var tlW = SW - INSP_W;

		// Timeline background
		_tlBg = new FlxSprite(0, tlY).makeGraphic(tlW, tlH, C_TL_BG);
		_tlBg.scrollFactor.set(); _tlBg.cameras = [camHUD];
		_tlGroup.add(_tlBg);

		// Ruler background
		_tlRulerBg = new FlxSprite(TL_LABEL_W, tlY).makeGraphic(tlW - TL_LABEL_W, TL_RULER_H, C_TL_RULER);
		_tlRulerBg.scrollFactor.set(); _tlRulerBg.cameras = [camHUD];
		_tlGroup.add(_tlRulerBg);

		// Label column background
		_tlLabelColBg = new FlxSprite(0, tlY).makeGraphic(TL_LABEL_W, tlH - TL_SCRUB_H - 12, C_PANEL);
		_tlLabelColBg.scrollFactor.set(); _tlLabelColBg.cameras = [camHUD];
		_tlGroup.add(_tlLabelColBg);

		// Label column right border
		var lcBorder = new FlxSprite(TL_LABEL_W - 1, tlY).makeGraphic(1, tlH, C_BORDER);
		lcBorder.scrollFactor.set(); lcBorder.cameras = [camHUD];
		_tlGroup.add(lcBorder);

		// Top ruler border
		var rulerTop = new FlxSprite(0, tlY).makeGraphic(tlW, 1, C_BORDER);
		rulerTop.scrollFactor.set(); rulerTop.cameras = [camHUD];
		_tlGroup.add(rulerTop);

		// Playhead
		_tlPlayhead = new FlxSprite(_slotToX(0), tlY).makeGraphic(2, TL_RULER_H + tracks.length * TL_TRACK_H, C_PLAYHEAD);
		_tlPlayhead.scrollFactor.set(); _tlPlayhead.cameras = [camHUD];
		_tlGroup.add(_tlPlayhead);

		// Track rows + labels
		_rebuildTrackRows();

		// Ruler labels
		_rebuildRuler();

		// Clips
		_rebuildClips();

		// Horizontal scrollbar
		var scrubY = tlY + tlH - TL_SCRUB_H - 12;
		_tlHScrollBg = new FlxSprite(TL_LABEL_W, scrubY + 2).makeGraphic(tlW - TL_LABEL_W - 12, 8, C_PANEL);
		_tlHScrollBg.scrollFactor.set(); _tlHScrollBg.cameras = [camHUD];
		_tlGroup.add(_tlHScrollBg);

		_tlHScrollThumb = new FlxSprite(TL_LABEL_W, scrubY + 2).makeGraphic(40, 8, C_ACCENT);
		_tlHScrollThumb.scrollFactor.set(); _tlHScrollThumb.cameras = [camHUD];
		_tlGroup.add(_tlHScrollThumb);

		// Track scroll buttons
		_tlScrollUp = new DLGBtn(SW - INSP_W - 16, tlY + TL_RULER_H, 14, 14, '▲', C_PANEL, C_TEXT, () -> { if (_trackScrollY > 0) { _trackScrollY--; _rebuildTrackRows(); _rebuildClips(); } });
		_tlScrollUp.scrollFactor.set(); _tlScrollUp.cameras = [camHUD]; _tlScrollUp.label.cameras = [camHUD];
		_tlGroup.add(_tlScrollUp); _tlGroup.add(_tlScrollUp.label);

		_tlScrollDown = new DLGBtn(SW - INSP_W - 16, tlY + TL_RULER_H + 16, 14, 14, '▼', C_PANEL, C_TEXT, () -> { if (_trackScrollY < tracks.length - 1) { _trackScrollY++; _rebuildTrackRows(); _rebuildClips(); } });
		_tlScrollDown.scrollFactor.set(); _tlScrollDown.cameras = [camHUD]; _tlScrollDown.label.cameras = [camHUD];
		_tlGroup.add(_tlScrollDown); _tlGroup.add(_tlScrollDown.label);

		// + TRACK button in ruler area (like GameplayEditorState)
		var addTrackBtn = new DLGBtn(TL_LABEL_W - 22, tlY + 3, 20, TL_RULER_H - 6, '+', 0xFF0D2E0D, C_ACCENT3, _doAddTrack);
		addTrackBtn.scrollFactor.set(); addTrackBtn.cameras = [camHUD]; addTrackBtn.label.cameras = [camHUD];
		_tlGroup.add(addTrackBtn); _tlGroup.add(addTrackBtn.label);

		// Ruler hint text
		var rulerHint = new FlxText(4, tlY + 6, TL_LABEL_W - 26, 'TRACKS', 8);
		rulerHint.setFormat(Paths.font('vcr.ttf'), 8, C_SUBTEXT, LEFT);
		rulerHint.scrollFactor.set(); rulerHint.cameras = [camHUD];
		_tlGroup.add(rulerHint);

		add(_tlGroup);
	}

	function _rebuildTrackRows():Void {
		// Remove old track UI
		for (s in _trackBgs) { _tlGroup.remove(s, true); s.destroy(); }
		for (s in _trackLabels) { _tlGroup.remove(s, true); s.destroy(); }
		for (b in _trackLockBtns) { _tlGroup.remove(b, true); _tlGroup.remove(b.label, true); b.label.destroy(); b.destroy(); }
		for (b in _trackVisBtns) { _tlGroup.remove(b, true); _tlGroup.remove(b.label, true); b.label.destroy(); b.destroy(); }
		for (s in _trackColorStrips) { _tlGroup.remove(s, true); s.destroy(); }
		for (s in _tlGridLines) { _tlGroup.remove(s, true); s.destroy(); }
		_trackBgs = []; _trackLabels = []; _trackLockBtns = []; _trackVisBtns = []; _trackColorStrips = []; _tlGridLines = [];

		var tlY = _tlY();
		var tlW = SW - INSP_W;
		var numVisible = Std.int(Math.min(tracks.length - _trackScrollY, 6));

		for (vi in 0...numVisible) {
			var ti = vi + _trackScrollY;
			var track = tracks[ti];
			var ty = tlY + TL_RULER_H + vi * TL_TRACK_H;

			// Track background
			var even = vi % 2 == 0;
			var bg = new FlxSprite(0, ty).makeGraphic(tlW, TL_TRACK_H, even ? 0xFF0E0E1C : 0xFF111120);
			bg.scrollFactor.set(); bg.cameras = [camHUD];
			_trackBgs.push(bg); _tlGroup.add(bg);

			// Track bottom separator
			var sep = new FlxSprite(0, ty + TL_TRACK_H - 1).makeGraphic(tlW, 1, C_BORDER);
			sep.alpha = 0.4; sep.scrollFactor.set(); sep.cameras = [camHUD];
			_tlGridLines.push(sep); _tlGroup.add(sep);

			// Color strip
			var cs = new FlxSprite(0, ty).makeGraphic(3, TL_TRACK_H, track.color);
			cs.scrollFactor.set(); cs.cameras = [camHUD];
			_trackColorStrips.push(cs); _tlGroup.add(cs);

			// Lock button
			var captI = ti;
			var coreIds = ['dialogue', 'portrait', 'background', 'music'];
			var isCustom = coreIds.indexOf(track.id) < 0;

			// Label (left side, truncated to leave room for buttons)
			var lbl = new FlxText(4, ty + (TL_TRACK_H - 10) / 2, 50, track.name, 9);
			lbl.setFormat(Paths.font('vcr.ttf'), 9, track.visible ? C_TEXT : C_SUBTEXT, LEFT);
			lbl.scrollFactor.set(); lbl.cameras = [camHUD];
			_trackLabels.push(lbl); _tlGroup.add(lbl);

			// ▲/▼ move up-down buttons (x=56)
			var moveUpBtn = new DLGBtn(56, ty, 10, Std.int(TL_TRACK_H / 2) - 1, '▲', C_PANEL, C_SUBTEXT, () -> {
				if (captI > 0) {
					_pushUndo();
					var tmp = tracks[captI]; tracks[captI] = tracks[captI - 1]; tracks[captI - 1] = tmp;
					_rebuildTrackRows(); _rebuildClips(); hasUnsaved = true;
				}
			});
			moveUpBtn.scrollFactor.set(); moveUpBtn.cameras = [camHUD]; moveUpBtn.label.cameras = [camHUD];
			_tlGroup.add(moveUpBtn); _tlGroup.add(moveUpBtn.label);

			var moveDnBtn = new DLGBtn(56, ty + Std.int(TL_TRACK_H / 2), 10, Std.int(TL_TRACK_H / 2) - 1, '▼', C_PANEL, C_SUBTEXT, () -> {
				if (captI < tracks.length - 1) {
					_pushUndo();
					var tmp = tracks[captI]; tracks[captI] = tracks[captI + 1]; tracks[captI + 1] = tmp;
					_rebuildTrackRows(); _rebuildClips(); hasUnsaved = true;
				}
			});
			moveDnBtn.scrollFactor.set(); moveDnBtn.cameras = [camHUD]; moveDnBtn.label.cameras = [camHUD];
			_tlGroup.add(moveDnBtn); _tlGroup.add(moveDnBtn.label);

			// ● visibility toggle (x=68)
			var visBtn = new DLGBtn(68, ty + 4, 14, TL_TRACK_H - 8, track.visible ? '●' : '○', C_PANEL, track.visible ? track.color : C_SUBTEXT, () -> {
				tracks[captI].visible = !tracks[captI].visible;
				_rebuildTrackRows(); _rebuildClips();
			});
			visBtn.scrollFactor.set(); visBtn.cameras = [camHUD]; visBtn.label.cameras = [camHUD];
			_trackVisBtns.push(visBtn); _tlGroup.add(visBtn); _tlGroup.add(visBtn.label);

			// 🔒 lock (x=84)
			var lockBtn = new DLGBtn(84, ty + 4, 14, TL_TRACK_H - 8, track.locked ? '🔒' : '🔓', C_PANEL, C_TEXT, () -> {
				tracks[captI].locked = !tracks[captI].locked;
				_rebuildTrackRows();
			});
			lockBtn.scrollFactor.set(); lockBtn.cameras = [camHUD]; lockBtn.label.cameras = [camHUD];
			_trackLockBtns.push(lockBtn); _tlGroup.add(lockBtn); _tlGroup.add(lockBtn.label);

			// × remove (x=100, only for custom tracks)
			if (isCustom) {
				var removeBtn = new DLGBtn(100, ty + 4, 6, TL_TRACK_H - 8, '×', 0xFF2A0808, 0xFFFF4444, () -> {
					_doRemoveTrack(captI);
				});
				removeBtn.scrollFactor.set(); removeBtn.cameras = [camHUD]; removeBtn.label.cameras = [camHUD];
				_tlGroup.add(removeBtn); _tlGroup.add(removeBtn.label);
			}
		}

		// Update splitter and playhead position
		if (_splitterSprite != null) _splitterSprite.y = HEADER_H + _vpHeight;
		_updatePlayheadPos();
	}

	function _rebuildRuler():Void {
		for (l in _tlRulerLabels) { _tlGroup.remove(l, true); l.destroy(); }
		for (t in _tlRulerTicks) { _tlGroup.remove(t, true); t.destroy(); }
		_tlRulerLabels = []; _tlRulerTicks = [];

		var tlY = _tlY();
		var tlW = SW - INSP_W - TL_LABEL_W;
		var slotPx = TL_SLOT_W * tlZoom;
		var totalSlots = conversation != null ? conversation.messages.length + 2 : 8;
		var maxSlots = Std.int(tlW / slotPx) + 2;

		for (si in 0...Std.int(Math.max(totalSlots, maxSlots))) {
			var slotX = _slotToX(si + tlScrollSlot);
			if (slotX < TL_LABEL_W || slotX > SW - INSP_W) continue;

			var tick = new FlxSprite(slotX, tlY + TL_RULER_H - 6).makeGraphic(1, 6, C_SUBTEXT);
			tick.scrollFactor.set(); tick.cameras = [camHUD];
			_tlRulerTicks.push(tick); _tlGroup.add(tick);

			var lbl = new FlxText(slotX + 3, tlY + 4, 60, 'MSG ${si + 1}', 8);
			lbl.setFormat(Paths.font('vcr.ttf'), 8, C_SUBTEXT, LEFT);
			lbl.scrollFactor.set(); lbl.cameras = [camHUD];
			_tlRulerLabels.push(lbl); _tlGroup.add(lbl);
		}
	}

	function _rebuildClips():Void {
		for (b in _clipBlocks) { _tlGroup.remove(b, true); _tlGroup.remove(b.lblTxt, true); b.lblTxt.destroy(); b.destroy(); }
		_clipBlocks = [];

		if (conversation == null) return;

		for (clip in clips) {
			var trackIdx = _getTrackIndex(clip.trackId);
			if (trackIdx < 0) continue;
			var visIdx = trackIdx - _trackScrollY;
			if (visIdx < 0 || visIdx >= 6) continue;
			var track = tracks[trackIdx];
			if (!track.visible) continue;

			var cx = _slotToX(clip.startSlot);
			var cw = Std.int(clip.duration * TL_SLOT_W * tlZoom);
			var cy = _getTrackY(trackIdx);
			var col = track.color;

			var selected = clip.id == selectedClipId;
			var block = new DLGClipBlock(cx, cy + 2, Std.int(Math.max(6, cw)), TL_TRACK_H - 4, col, clip.id, selected);
			block.scrollFactor.set(); block.cameras = [camHUD];
			block.lblTxt.cameras = [camHUD];

			// Clip label
			var labelStr = switch (clip.trackId) {
				case 'dialogue':   clip.character != null ? '${clip.character}: ${clip.text ?? ""}' : 'MSG';
				case 'portrait':   clip.portraitName ?? 'portrait';
				case 'background': clip.bgColor ?? 'bg';
				case 'music':      '♪ ${clip.soundFile ?? clip.musicName ?? "music"}';
				case 'sound':      '▶ ${clip.soundFile ?? "sfx"}';
				default:           clip.id;
			}
			if (labelStr.length > 20) labelStr = labelStr.substr(0, 20) + '…';
			block.lblTxt.text = labelStr;
			block.lblTxt.x = cx + 4;
			block.lblTxt.y = cy + 2 + (TL_TRACK_H - 4 - 10) / 2;
			block.lblTxt.fieldWidth = Std.int(Math.max(10, cw - 8));

			_clipBlocks.push(block);
			_tlGroup.add(block);
			_tlGroup.add(block.lblTxt);
		}
		_updatePlayheadPos();
	}

	function _updatePlayheadPos():Void {
		if (_tlPlayhead == null) return;
		var px = _slotToX(_previewMsgIdx);
		_tlPlayhead.x = px;
		_tlPlayhead.y = _tlY();
		var numVis = Std.int(Math.min(tracks.length - _trackScrollY, 6));
		_tlPlayhead.makeGraphic(2, TL_RULER_H + numVis * TL_TRACK_H, C_PLAYHEAD);
	}

	function _rebuildTimeline():Void {
		_rebuildRuler();
		_rebuildClips();
		_updateScrollThumb();
	}

	function _updateScrollThumb():Void {
		if (_tlHScrollThumb == null || _tlHScrollBg == null) return;
		var totalSlots = conversation != null ? conversation.messages.length + 2 : 8;
		var visSlots = _tlAreaW() / (TL_SLOT_W * tlZoom);
		var ratio = FlxMath.bound(visSlots / totalSlots, 0.05, 1.0);
		var thumbW = Std.int((_tlHScrollBg.width) * ratio);
		var offsetRatio = totalSlots > 0 ? tlScrollSlot / totalSlots : 0;
		var thumbX = TL_LABEL_W + Std.int((_tlHScrollBg.width - thumbW) * offsetRatio);
		_tlHScrollThumb.x = thumbX;
		_tlHScrollThumb.makeGraphic(Std.int(Math.max(12, thumbW)), 8, C_ACCENT);
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  UI BUILD — INSPECTOR
	// ═════════════════════════════════════════════════════════════════════════

	function _buildInspector():Void {
		_inspGroup = new FlxGroup();

		var ix = SW - INSP_W;
		_inspBg = new FlxSprite(ix, HEADER_H).makeGraphic(INSP_W, SH - HEADER_H - STATUS_H, C_INSP);
		_inspBg.scrollFactor.set(); _inspBg.cameras = [camHUD];
		_inspGroup.add(_inspBg);

		_inspSep = new FlxSprite(ix, HEADER_H).makeGraphic(1, SH - HEADER_H - STATUS_H, C_BORDER);
		_inspSep.scrollFactor.set(); _inspSep.cameras = [camHUD];
		_inspGroup.add(_inspSep);

		_inspTitle = new FlxText(ix + 8, HEADER_H + 8, INSP_W - 16, 'INSPECTOR', 10);
		_inspTitle.setFormat(Paths.font('vcr.ttf'), 10, C_ACCENT, LEFT);
		_inspTitle.scrollFactor.set(); _inspTitle.cameras = [camHUD];
		_inspGroup.add(_inspTitle);

		// Separator line under title
		var titleSep = new FlxSprite(ix, HEADER_H + 24).makeGraphic(INSP_W, 1, C_BORDER);
		titleSep.scrollFactor.set(); titleSep.cameras = [camHUD];
		_inspGroup.add(titleSep);

		var fieldY = HEADER_H + 32;
		var fieldX = ix + 8;
		var fieldW = INSP_W - 16;
		var fieldH = 22;
		var gap = 28;

		// Helper to add a label+input pair (tracks label for show/hide)
		_inspDlgLbls = [];
		var mkField = (label:String, yOff:Int) -> {
			var lbl = new FlxText(fieldX, fieldY + yOff, fieldW, label, 9);
			lbl.setFormat(Paths.font('vcr.ttf'), 9, C_SUBTEXT, LEFT);
			lbl.scrollFactor.set(); lbl.cameras = [camHUD];
			_inspDlgLbls.push(lbl);
			_inspGroup.add(lbl);

			var inp = new CoolInputText(fieldX, fieldY + yOff + 12, fieldW, '', 9);
			inp.cameras = [camHUD];
			_inspGroup.add(inp);
			return inp;
		};

		// Dialogue clip fields
		_inspCharInput    = mkField('Character:',                   0);
		_inspTextInput    = mkField('Text:',                        gap);
		_inspBubbleInput  = mkField('Bubble Type:',                 gap * 2);
		_inspSpeedInput   = mkField('Speed:',                       gap * 3);
		_inspPortraitInput = mkField('Portrait:',                   gap * 4);
		_inspBoxInput     = mkField('Box Sprite:',                  gap * 5);
		_inspMusicInput   = mkField('Music (bg):',                  gap * 6);
		_inspDurationInput = mkField('Duration (slots):',           gap * 7);

		// Read-only start-slot info line (shown under duration)
		_inspStartSlotLbl = new FlxText(fieldX, fieldY + gap * 8 + 4, fieldW, 'Slot: —', 9);
		_inspStartSlotLbl.setFormat(Paths.font('vcr.ttf'), 9, C_SUBTEXT, LEFT);
		_inspStartSlotLbl.scrollFactor.set(); _inspStartSlotLbl.cameras = [camHUD];
		_inspGroup.add(_inspStartSlotLbl);

		// ── Audio clip fields (shown instead of dialogue fields for music/sound tracks) ──
		_inspAudioItems = [];
		var mkAudioLbl = (txt:String, yOff:Int) -> {
			var l = new FlxText(fieldX, fieldY + yOff, fieldW, txt, 9);
			l.setFormat(Paths.font('vcr.ttf'), 9, C_SUBTEXT, LEFT);
			l.scrollFactor.set(); l.cameras = [camHUD]; l.visible = false;
			_inspGroup.add(l); _inspAudioItems.push(l); return l;
		};
		var mkAudioInp = (yOff:Int, ?w:Int) -> {
			var iw = w ?? fieldW;
			var inp = new CoolInputText(fieldX, fieldY + yOff + 12, iw, '', 9);
			inp.cameras = [camHUD]; inp.visible = false;
			_inspGroup.add(inp); _inspAudioItems.push(inp); return inp;
		};

		mkAudioLbl('Audio File:', 0);
		_inspAudioFileInput = mkAudioInp(0, fieldW - 32);

		// BROWSE button next to file input
		_btnBrowseAudio = new DLGBtn(fieldX + fieldW - 28, fieldY + 12, 28, 18, '…', C_PANEL, C_ACCENT, _doBrowseAudioFile);
		_btnBrowseAudio.scrollFactor.set(); _btnBrowseAudio.cameras = [camHUD]; _btnBrowseAudio.label.cameras = [camHUD];
		_btnBrowseAudio.visible = false;
		_inspGroup.add(_btnBrowseAudio); _inspGroup.add(_btnBrowseAudio.label);
		_inspAudioItems.push(_btnBrowseAudio); _inspAudioItems.push(_btnBrowseAudio.label);

		mkAudioLbl('Volume (0.0 – 1.0):', gap);
		_inspVolumeInput = mkAudioInp(gap);

		mkAudioLbl('Loop (yes / no):', gap * 2);
		_inspLoopInput = mkAudioInp(gap * 2);

		// Re-use duration and slot label for audio too (always shown)
		mkAudioLbl('Duration (slots):', gap * 3);
		// (we reuse _inspDurationInput visually via _refreshClipInspector)

		// hint
		var audioHint = new FlxText(fieldX, fieldY + gap * 4 + 8, fieldW,
			'Drag right edge of clip\nto stretch/shrink duration', 8);
		audioHint.setFormat(Paths.font('vcr.ttf'), 8, C_SUBTEXT, LEFT);
		audioHint.scrollFactor.set(); audioHint.cameras = [camHUD]; audioHint.visible = false;
		_inspGroup.add(audioHint); _inspAudioItems.push(audioHint);

		// Apply button
		_inspApplyBtn = new DLGBtn(fieldX, fieldY + gap * 8 + 18, fieldW, 26, 'APPLY CHANGES', C_ACCENT2, C_BG, _doApplyInspector);
		_inspApplyBtn.scrollFactor.set(); _inspApplyBtn.cameras = [camHUD]; _inspApplyBtn.label.cameras = [camHUD];
		_inspGroup.add(_inspApplyBtn); _inspGroup.add(_inspApplyBtn.label);

		// Separator
		var midSep = new FlxSprite(ix, fieldY + gap * 8 + 50).makeGraphic(INSP_W, 1, C_BORDER);
		midSep.scrollFactor.set(); midSep.cameras = [camHUD];
		_inspGroup.add(midSep);

		// Canvas element fields (scene builder)
		var eFieldY = fieldY + gap * 8 + 58;
		var mkEField = (label:String, yOff:Int) -> {
			var lbl = new FlxText(fieldX, eFieldY + yOff, fieldW, label, 9);
			lbl.setFormat(Paths.font('vcr.ttf'), 9, C_SUBTEXT, LEFT);
			lbl.scrollFactor.set(); lbl.cameras = [camHUD];
			_inspGroup.add(lbl);

			var inp = new CoolInputText(fieldX, eFieldY + yOff + 12, fieldW, '', 9);
			inp.cameras = [camHUD];
			_inspGroup.add(inp);
			return inp;
		};

		_inspElemXInput      = mkEField('X:', 0);
		_inspElemYInput      = mkEField('Y:', gap);
		_inspElemScaleXInput = mkEField('Scale X:', gap * 2);
		_inspElemScaleYInput = mkEField('Scale Y:', gap * 3);
		_inspElemAnimInput   = mkEField('Animation:', gap * 4);

		_inspElemFlipBtn = new DLGBtn(fieldX, eFieldY + gap * 5 + 8, fieldW, 22, 'TOGGLE FLIP X', 0xFF1E1E3E, C_TEXT, () -> {
			if (_selectedElementIdx >= 0 && _selectedElementIdx < _canvasElements.length) {
				var el = _canvasElements[_selectedElementIdx];
				// Toggle flipX in the skin
				if (el.type == 'portrait' && currentSkin != null) {
					var pc = currentSkin.portraits.get(el.key);
					if (pc != null) pc.flipX = !(pc.flipX ?? false);
					_rebuildCanvasSprites();
				}
			}
		});
		_inspElemFlipBtn.scrollFactor.set(); _inspElemFlipBtn.cameras = [camHUD]; _inspElemFlipBtn.label.cameras = [camHUD];
		_inspGroup.add(_inspElemFlipBtn); _inspGroup.add(_inspElemFlipBtn.label);

		// Skin config fields
		var sFieldY = eFieldY + gap * 6 + 4;
		var skinSep = new FlxSprite(ix, sFieldY).makeGraphic(INSP_W, 1, C_BORDER);
		skinSep.scrollFactor.set(); skinSep.cameras = [camHUD];
		_inspGroup.add(skinSep);

		var skinTitleLbl = new FlxText(fieldX, sFieldY + 4, fieldW, 'SKIN CONFIG', 9);
		skinTitleLbl.setFormat(Paths.font('vcr.ttf'), 9, C_ACCENT, LEFT);
		skinTitleLbl.scrollFactor.set(); skinTitleLbl.cameras = [camHUD];
		_inspGroup.add(skinTitleLbl);

		_inspSkinStyleInput = mkEField('Style (normal/pixel):', gap);
		_inspSkinBgInput    = mkEField('Background Color:', gap * 2);
		_inspSkinFadeInput  = mkEField('Fade Time:', gap * 3);

		// Init skin fields
		_refreshSkinInspectorFields();

		add(_inspGroup);
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  UI BUILD — STATUS BAR
	// ═════════════════════════════════════════════════════════════════════════

	function _buildStatusBar():Void {
		_statusBg = new FlxSprite(0, SH - STATUS_H).makeGraphic(SW, STATUS_H, C_MENU);
		_statusBg.scrollFactor.set(); _statusBg.cameras = [camHUD];
		add(_statusBg);

		var sTop = new FlxSprite(0, SH - STATUS_H).makeGraphic(SW, 1, C_BORDER);
		sTop.scrollFactor.set(); sTop.cameras = [camHUD];
		add(sTop);

		_statusTxt = new FlxText(6, SH - STATUS_H + 4, SW - 200, '', 9);
		_statusTxt.setFormat(Paths.font('vcr.ttf'), 9, C_SUBTEXT, LEFT);
		_statusTxt.scrollFactor.set(); _statusTxt.cameras = [camHUD];
		add(_statusTxt);

		// Tooltip de botón: se muestra a la derecha del status (izquierda del drop-hint)
		// y se reemplaza con el último mensaje de estado al quitarse el hover.
		var _tooltipTxt = new FlxText(SW - 500, SH - STATUS_H + 4, 290, '', 9);
		_tooltipTxt.setFormat(Paths.font('vcr.ttf'), 9, 0xFF8888CC, RIGHT);
		_tooltipTxt.scrollFactor.set(); _tooltipTxt.cameras = [camHUD];
		add(_tooltipTxt);
		// Conectar el callback: muestra tooltip mientras hay hover, lo limpia al salir
		DLGBtn.onTooltip = (tip:String) -> _tooltipTxt.text = tip;

		// Persistent drop hint on the right side of status bar
		_dropHintTxt = new FlxText(SW - 194, SH - STATUS_H + 4, 190, '⬇ drop files to import', 9);
		_dropHintTxt.setFormat(Paths.font('vcr.ttf'), 9, 0xFF3A3A5A, RIGHT);
		_dropHintTxt.scrollFactor.set(); _dropHintTxt.cameras = [camHUD];
		add(_dropHintTxt);
	}

	function _showStatus(msg:String):Void {
		if (_statusTxt != null) _statusTxt.text = msg;
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  MODE SWITCHING
	// ═════════════════════════════════════════════════════════════════════════

	function _switchMode(mode:String, force:Bool = false):Void {
		if (!force && mode == _mode) return;
		_mode = mode;
		_closeMenus();

		var isScene = mode == 'scene';

		// Toggle group visibility
		_sceneGroup.visible = isScene;
		_previewGroup.visible = !isScene;
		_tlGroup.visible = !isScene;
		if (_splitterSprite != null) _splitterSprite.visible = !isScene;

		// Scene mode: make vpHeight cover the full main area (no timeline)
		if (isScene) {
			_vpHeight = SH - HEADER_H - STATUS_H;
			if (_canvasBg != null) _canvasBg.makeGraphic(CANVAS_W, _vpHeight, C_CANVAS);
		} else {
			var minTlH = TL_RULER_H + TL_TRACK_H * 4 + TL_SCRUB_H + 12;
			_vpHeight = Std.int(Math.max(MIN_VP_H, SH - HEADER_H - SPLITTER_H - minTlH - STATUS_H - 20));
			_rebuildTimeline();
			_rebuildTimelineAssets();
		}

		// Top bar visibility
		for (sp in _topBarSprites) sp.visible = false;
		if (isScene) {
			_btnNewSkin.visible  = true; _btnNewSkin.label.visible  = true;
			_btnLoadSkin.visible = true; _btnLoadSkin.label.visible = true;
			_btnSaveSkin.visible = true; _btnSaveSkin.label.visible = true;
			_skinNameTxt.visible = true;
		} else {
			_btnNewConv.visible   = true; _btnNewConv.label.visible   = true;
			_btnLoadConv.visible  = true; _btnLoadConv.label.visible  = true;
			_btnSaveConv.visible  = true; _btnSaveConv.label.visible  = true;
			_btnTestConv.visible  = true; _btnTestConv.label.visible  = true;
			_btnAddMsg.visible    = true; _btnAddMsg.label.visible    = true;
			_btnRemoveMsg.visible = true; _btnRemoveMsg.label.visible = true;
			_convInfoTxt.visible  = true;
			_unsavedDot.visible   = hasUnsaved;
		}

		// Mode button highlights
		for (i in 0...2) {
			var active = (i == 0 && isScene) || (i == 1 && !isScene);
			var sp = _modeSwitchBtns[i];
			sp._base = active ? C_ACCENT2 : 0xFF252540;
			sp._drawBtn(sp._base);
			sp.label.color = active ? C_BG : C_TEXT;
		}

		// Inspector context
		_refreshInspector();
		_showStatus('Mode: ${isScene ? "SCENE BUILDER" : "DIALOGUE EDITOR"}');
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  INSPECTOR REFRESH
	// ═════════════════════════════════════════════════════════════════════════

	function _refreshInspector():Void {
		if (_mode == 'scene') {
			_inspTitle.text = 'SCENE BUILDER';
			_refreshElementInspector();
		} else {
			_inspTitle.text = 'INSPECTOR';
			_refreshClipInspector();
		}
		_refreshSkinInspectorFields();
	}

	function _refreshClipInspector():Void {
		var clip = _findClip(selectedClipId);
		if (clip == null) {
			_clearClipFields();
			return;
		}

		var isAudio = clip.trackId == 'music' || clip.trackId == 'sound';

		// Toggle dialogue vs audio field visibility
		var dlgVisible = !isAudio;
		for (lbl in _inspDlgLbls) lbl.visible = dlgVisible;
		for (f in [_inspCharInput, _inspTextInput, _inspBubbleInput, _inspSpeedInput,
		           _inspPortraitInput, _inspBoxInput, _inspMusicInput]) {
			if (f != null) f.visible = dlgVisible;
		}
		for (item in _inspAudioItems) if (item != null) item.visible = isAudio;

		if (isAudio) {
			// ── Audio inspector ───────────────────────────────────────────
			var trackLabel = clip.trackId == 'music' ? 'MUSIC' : 'SOUND FX';
			_inspTitle.text = '$trackLabel CLIP';
			if (_inspAudioFileInput != null) _inspAudioFileInput.text = clip.soundFile ?? '';
			if (_inspVolumeInput   != null) _inspVolumeInput.text   = clip.volume != null ? Std.string(clip.volume) : '1.0';
			if (_inspLoopInput     != null) _inspLoopInput.text     = (clip.loop ?? (clip.trackId == 'music')) ? 'yes' : 'no';
			if (_inspDurationInput != null) { _inspDurationInput.visible = true; _inspDurationInput.text = Std.string(clip.duration); }
			if (_inspStartSlotLbl != null)  _inspStartSlotLbl.text  = 'Slot: ${Std.int(clip.startSlot) + 1}  |  track: ${clip.trackId}  |  drag right edge to resize';
		} else {
			// ── Dialogue inspector ────────────────────────────────────────
			_inspTitle.text = 'INSPECTOR';
			if (_inspCharInput     != null) _inspCharInput.text     = clip.character    ?? '';
			if (_inspTextInput     != null) _inspTextInput.text     = clip.text         ?? '';
			if (_inspBubbleInput   != null) _inspBubbleInput.text   = clip.bubbleType   ?? 'normal';
			if (_inspSpeedInput    != null) _inspSpeedInput.text    = clip.speed != null ? Std.string(clip.speed) : '0.04';
			if (_inspPortraitInput != null) _inspPortraitInput.text = clip.portrait     ?? '';
			if (_inspBoxInput      != null) _inspBoxInput.text      = clip.boxSprite    ?? '';
			if (_inspMusicInput    != null) _inspMusicInput.text    = clip.music        ?? '';
			if (_inspDurationInput != null) { _inspDurationInput.visible = true; _inspDurationInput.text = Std.string(clip.duration); }
			if (_inspStartSlotLbl != null)  _inspStartSlotLbl.text  = 'Slot: ${Std.int(clip.startSlot) + 1}  |  track: ${clip.trackId}';
		}
	}

	function _clearClipFields():Void {
		_inspTitle.text = 'INSPECTOR';
		for (lbl in _inspDlgLbls) lbl.visible = true;
		for (f in [_inspCharInput, _inspTextInput, _inspBubbleInput, _inspSpeedInput,
		           _inspPortraitInput, _inspBoxInput, _inspMusicInput, _inspDurationInput])
			if (f != null) { f.text = ''; f.visible = true; }
		if (_inspStartSlotLbl != null) _inspStartSlotLbl.text = 'Slot: —';
		// Hide audio section
		for (item in _inspAudioItems) if (item != null) item.visible = false;
		if (_inspAudioFileInput != null) _inspAudioFileInput.text = '';
		if (_inspVolumeInput    != null) _inspVolumeInput.text    = '';
		if (_inspLoopInput      != null) _inspLoopInput.text      = '';
	}

	function _refreshElementInspector():Void {
		if (_selectedElementIdx < 0 || _selectedElementIdx >= _canvasElements.length) {
			_clearElementFields();
			return;
		}
		var el = _canvasElements[_selectedElementIdx];
		if (el.type == 'portrait' && currentSkin != null) {
			var pc = currentSkin.portraits.get(el.key);
			if (pc == null) return;
			if (_inspElemXInput != null)      _inspElemXInput.text      = Std.string(pc.x ?? 0.0);
			if (_inspElemYInput != null)      _inspElemYInput.text      = Std.string(pc.y ?? 0.0);
			if (_inspElemScaleXInput != null) _inspElemScaleXInput.text = Std.string(pc.scaleX ?? 1.0);
			if (_inspElemScaleYInput != null) _inspElemScaleYInput.text = Std.string(pc.scaleY ?? 1.0);
			if (_inspElemAnimInput != null)   _inspElemAnimInput.text   = pc.animation ?? 'idle';
		} else if (el.type == 'box' && currentSkin != null) {
			var bc = currentSkin.boxes.get(el.key);
			if (bc == null) return;
			if (_inspElemXInput != null)      _inspElemXInput.text      = Std.string(bc.x ?? 0.0);
			if (_inspElemYInput != null)      _inspElemYInput.text      = Std.string(bc.y ?? 0.0);
			if (_inspElemScaleXInput != null) _inspElemScaleXInput.text = Std.string(bc.scaleX ?? 1.0);
			if (_inspElemScaleYInput != null) _inspElemScaleYInput.text = Std.string(bc.scaleY ?? 1.0);
			if (_inspElemAnimInput != null)   _inspElemAnimInput.text   = bc.animation ?? 'normal';
		} else if (el.type == 'background' && currentSkin?.backgrounds != null) {
			var bg = currentSkin.backgrounds.get(el.key);
			if (bg == null) return;
			if (_inspElemXInput != null)      _inspElemXInput.text      = Std.string(bg.x ?? 0.0);
			if (_inspElemYInput != null)      _inspElemYInput.text      = Std.string(bg.y ?? 0.0);
			if (_inspElemScaleXInput != null) _inspElemScaleXInput.text = Std.string(bg.scaleX ?? 1.0);
			if (_inspElemScaleYInput != null) _inspElemScaleYInput.text = Std.string(bg.scaleY ?? 1.0);
			if (_inspElemAnimInput != null)   _inspElemAnimInput.text   = Std.string(bg.alpha ?? 1.0);
		} else if (el.type == 'overlay' && currentSkin?.overlays != null) {
			var ov = currentSkin.overlays.get(el.key);
			if (ov == null) return;
			if (_inspElemXInput != null)      _inspElemXInput.text      = Std.string(ov.x ?? 0.0);
			if (_inspElemYInput != null)      _inspElemYInput.text      = Std.string(ov.y ?? 0.0);
			if (_inspElemScaleXInput != null) _inspElemScaleXInput.text = Std.string(ov.scaleX ?? 1.0);
			if (_inspElemScaleYInput != null) _inspElemScaleYInput.text = Std.string(ov.scaleY ?? 1.0);
			if (_inspElemAnimInput != null)   _inspElemAnimInput.text   = Std.string(ov.alpha ?? 0.8);
		}
	}

	function _clearElementFields():Void {
		for (f in [_inspElemXInput, _inspElemYInput, _inspElemScaleXInput, _inspElemScaleYInput, _inspElemAnimInput])
			if (f != null) f.text = '';
	}

	function _refreshSkinInspectorFields():Void {
		if (currentSkin == null) return;
		if (_inspSkinStyleInput != null) _inspSkinStyleInput.text = currentSkin.style ?? 'normal';
		if (_inspSkinBgInput != null)    _inspSkinBgInput.text    = currentSkin.backgroundColor ?? '#000000';
		if (_inspSkinFadeInput != null)  _inspSkinFadeInput.text  = currentSkin.fadeTime != null ? Std.string(currentSkin.fadeTime) : '0.83';
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  SCENE BUILDER — Canvas
	// ═════════════════════════════════════════════════════════════════════════

	function _rebuildCanvasSprites():Void {
		// Remove old sprites
		for (el in _canvasElements) {
			_sceneGroup.remove(el.sprite, true);
			el.sprite.destroy();
		}
		_canvasElements = [];

		if (currentSkin == null) return;

		var frameW = CANVAS_W * 0.85;
		var frameH = frameW * 720 / 1280;
		var frameX = CANVAS_X + (CANVAS_W - frameW) / 2;
		var frameY = _mainAreaY() + (_vpHeight - frameH) / 2;
		var scaleF = frameW / 1280;

		// Add portraits as draggable sprites
		for (key => pc in currentSkin.portraits) {
			var imgPath = DialogueData.getPortraitAssetPath(currentSkinName, pc.fileName);
			var sp:FlxSprite;
			#if sys
			var absPath = Paths.resolve(imgPath);
			if (FileSystem.exists(absPath)) {
				sp = new FlxSprite();
				sp.loadGraphic(absPath);   // FIX: use absolute fs path, not Paths.image()
			} else {
				sp = new FlxSprite().makeGraphic(60, 80, DLGColorFor('portrait'));
			}
			#else
			sp = new FlxSprite().makeGraphic(60, 80, DLGColorFor('portrait'));
			#end

			// Position relative to canvas frame
			var worldX = frameX + (pc.x ?? 0) * scaleF;
			var worldY = frameY + (pc.y ?? 0) * scaleF;
			sp.setPosition(worldX, worldY);
			sp.scale.set((pc.scaleX ?? 1.0) * scaleF, (pc.scaleY ?? 1.0) * scaleF);
			sp.updateHitbox();
			sp.flipX = pc.flipX ?? false;
			sp.scrollFactor.set();
			sp.cameras = [camHUD];

			_sceneGroup.add(sp);
			_canvasElements.push({ type: 'portrait', key: key, sprite: sp });
		}

		// Add boxes
		for (key => bc in currentSkin.boxes) {
			var imgPath = DialogueData.getBoxAssetPath(currentSkinName, bc.fileName);
			var sp:FlxSprite;
			#if sys
			var absPath = Paths.resolve(imgPath);
			if (FileSystem.exists(absPath)) {
				sp = new FlxSprite();
				sp.loadGraphic(absPath);   // FIX: use absolute fs path
			} else {
				sp = new FlxSprite().makeGraphic(400, 80, DLGColorFor('box'));
			}
			#else
			sp = new FlxSprite().makeGraphic(400, 80, DLGColorFor('box'));
			#end

			var worldX = frameX + (bc.x ?? 0) * scaleF;
			var worldY = frameY + (bc.y ?? 0) * scaleF;
			sp.setPosition(worldX, worldY);
			sp.scale.set((bc.scaleX ?? 1.0) * scaleF, (bc.scaleY ?? 1.0) * scaleF);
			sp.updateHitbox();
			sp.scrollFactor.set();
			sp.cameras = [camHUD];

			_sceneGroup.add(sp);
			_canvasElements.push({ type: 'box', key: key, sprite: sp });
		}

		// Add backgrounds (rendered behind everything, full-frame)
		if (currentSkin.backgrounds != null) {
			for (key => bg in currentSkin.backgrounds) {
				var imgPath = DialogueData.getBackgroundAssetPath(currentSkinName, bg.fileName);
				var sp:FlxSprite;
				#if sys
				var absPath = Paths.resolve(imgPath);
				if (FileSystem.exists(absPath)) {
					sp = new FlxSprite();
					sp.loadGraphic(absPath);
				} else {
					sp = new FlxSprite().makeGraphic(Std.int(frameW), Std.int(frameH), DLGColorFor('background'));
				}
				#else
				sp = new FlxSprite().makeGraphic(Std.int(frameW), Std.int(frameH), DLGColorFor('background'));
				#end
				sp.setPosition(frameX + (bg.x ?? 0) * scaleF, frameY + (bg.y ?? 0) * scaleF);
				sp.scale.set((bg.scaleX ?? 1.0) * scaleF, (bg.scaleY ?? 1.0) * scaleF);
				sp.alpha = bg.alpha ?? 1.0;
				sp.updateHitbox();
				sp.scrollFactor.set();
				sp.cameras = [camHUD];
				_sceneGroup.add(sp);
				_canvasElements.push({ type: 'background', key: key, sprite: sp });
			}
		}

		// Add overlays (rendered on top, semi-transparent images)
		if (currentSkin.overlays != null) {
			for (key => ov in currentSkin.overlays) {
				var imgPath = DialogueData.getOverlayAssetPath(currentSkinName, ov.fileName);
				var sp:FlxSprite;
				#if sys
				var absPath = Paths.resolve(imgPath);
				if (FileSystem.exists(absPath)) {
					sp = new FlxSprite();
					sp.loadGraphic(absPath);
				} else {
					sp = new FlxSprite().makeGraphic(Std.int(frameW), Std.int(frameH), DLGColorFor('overlay'));
				}
				#else
				sp = new FlxSprite().makeGraphic(Std.int(frameW), Std.int(frameH), DLGColorFor('overlay'));
				#end
				sp.setPosition(frameX + (ov.x ?? 0) * scaleF, frameY + (ov.y ?? 0) * scaleF);
				sp.scale.set((ov.scaleX ?? 1.0) * scaleF, (ov.scaleY ?? 1.0) * scaleF);
				sp.alpha = ov.alpha ?? 0.8;
				sp.updateHitbox();
				sp.scrollFactor.set();
				sp.cameras = [camHUD];
				_sceneGroup.add(sp);
				_canvasElements.push({ type: 'overlay', key: key, sprite: sp });
			}
		}

		_rebuildAssetList();
		if (_mode == 'timeline') _rebuildTimelineAssets();
	}

	function _rebuildAssetList():Void {
		for (item in _assetItems) {
			_sceneGroup.remove(item.bg, true); item.bg.destroy();
			_sceneGroup.remove(item.lbl, true); item.lbl.destroy();
		}
		_assetItems = [];

		if (currentSkin == null) return;

		var yOff = _mainAreaY() + 38;

		// Portraits
		for (key => _ in currentSkin.portraits) {
			var isSelected = _selectedElementIdx >= 0 && _canvasElements[_selectedElementIdx].key == key;
			var bg = new FlxSprite(4, yOff).makeGraphic(ASSET_W - 8, 20, isSelected ? C_ACCENT2 : C_PANEL);
			bg.alpha = 0.7; bg.scrollFactor.set(); bg.cameras = [camHUD];
			_sceneGroup.add(bg);

			var lbl = new FlxText(8, yOff + 4, ASSET_W - 16, '◆ $key', 9);
			lbl.setFormat(Paths.font('vcr.ttf'), 9, C_ACCENT, LEFT);
			lbl.scrollFactor.set(); lbl.cameras = [camHUD];
			_sceneGroup.add(lbl);

			var captKey = key;
			_assetItems.push({ bg: bg, lbl: lbl, key: key, type: 'portrait' });
			yOff += 22;
		}

		yOff = _mainAreaY() + 110;
		for (key => _ in currentSkin.boxes) {
			var isSelected = _selectedElementIdx >= 0 && _canvasElements[_selectedElementIdx].key == key;
			var bg = new FlxSprite(4, yOff).makeGraphic(ASSET_W - 8, 20, isSelected ? C_ACCENT3 : C_PANEL);
			bg.alpha = 0.7; bg.scrollFactor.set(); bg.cameras = [camHUD];
			_sceneGroup.add(bg);

			var lbl = new FlxText(8, yOff + 4, ASSET_W - 16, '■ $key', 9);
			lbl.setFormat(Paths.font('vcr.ttf'), 9, C_ACCENT3, LEFT);
			lbl.scrollFactor.set(); lbl.cameras = [camHUD];
			_sceneGroup.add(lbl);

			_assetItems.push({ bg: bg, lbl: lbl, key: key, type: 'box' });
			yOff += 22;
		}

		// Backgrounds section
		if (currentSkin.backgrounds != null) {
			for (key => _ in currentSkin.backgrounds) {
				var isSelected = _selectedElementIdx >= 0 && _canvasElements[_selectedElementIdx].key == key;
				var bgSp = new FlxSprite(4, yOff).makeGraphic(ASSET_W - 8, 20, isSelected ? 0xFFFF9933 : C_PANEL);
				bgSp.alpha = 0.7; bgSp.scrollFactor.set(); bgSp.cameras = [camHUD];
				_sceneGroup.add(bgSp);
				var lbl = new FlxText(8, yOff + 4, ASSET_W - 16, '▣ $key (bg)', 9);
				lbl.setFormat(Paths.font('vcr.ttf'), 9, 0xFFFF9933, LEFT);
				lbl.scrollFactor.set(); lbl.cameras = [camHUD];
				_sceneGroup.add(lbl);
				_assetItems.push({ bg: bgSp, lbl: lbl, key: key, type: 'background' });
				yOff += 22;
			}
		}

		// Overlays section
		if (currentSkin.overlays != null) {
			for (key => _ in currentSkin.overlays) {
				var isSelected = _selectedElementIdx >= 0 && _canvasElements[_selectedElementIdx].key == key;
				var ovSp = new FlxSprite(4, yOff).makeGraphic(ASSET_W - 8, 20, isSelected ? 0xFF88CC55 : C_PANEL);
				ovSp.alpha = 0.7; ovSp.scrollFactor.set(); ovSp.cameras = [camHUD];
				_sceneGroup.add(ovSp);
				var lbl = new FlxText(8, yOff + 4, ASSET_W - 16, '◈ $key (ov)', 9);
				lbl.setFormat(Paths.font('vcr.ttf'), 9, 0xFF88CC55, LEFT);
				lbl.scrollFactor.set(); lbl.cameras = [camHUD];
				_sceneGroup.add(lbl);
				_assetItems.push({ bg: ovSp, lbl: lbl, key: key, type: 'overlay' });
				yOff += 22;
			}
		}
	}


	// ═════════════════════════════════════════════════════════════════════════
	//  TIMELINE ASSET PANEL
	// ═════════════════════════════════════════════════════════════════════════

	/** Returns the track/ghost colour associated with a given asset type. */
	function _colorForAssetType(t:String):Int {
		return switch (t) {
			case 'portrait':                        C_ACCENT;          // cyan
			case 'box':                             C_ACCENT3;         // mint
			case 'background':                      0xFFFF9933;        // orange
			case 'music' | 'music_import':          0xFF00E894;        // green
			case 'sound' | 'sound_import':          0xFFFFCC44;        // yellow
			default:                                C_ACCENT2;         // pink
		};
	}

	/**
	 * Repopulate the left-side asset panel shown in TIMELINE mode.
	 * Lists portraits, boxes, backgrounds from the current skin, plus
	 * audio entries found in existing clips and import shortcuts.
	 */
	function _rebuildTimelineAssets():Void {
		// Remove previous items
		for (item in _tlAssetItemsList) {
			_previewGroup.remove(item.bg,  true); item.bg.destroy();
			_previewGroup.remove(item.lbl, true); item.lbl.destroy();
		}
		_tlAssetItemsList = [];

		if (currentSkin == null) return;

		var yOff = _mainAreaY() + 32;
		var maxY = _mainAreaY() + _mainAreaH() - 4;
		var pw   = TL_ASSET_W - 4;

		// Non-interactive section header
		var mkSection = (title:String, col:Int) -> {
			if (yOff + 13 > maxY) return;
			var sep = new FlxSprite(2, yOff).makeGraphic(pw, 1, C_BORDER);
			sep.alpha = 0.5; sep.scrollFactor.set(); sep.cameras = [camHUD];
			var slbl = new FlxText(4, yOff + 2, pw, title, 8);
			slbl.setFormat(Paths.font('vcr.ttf'), 8, col, LEFT);
			slbl.scrollFactor.set(); slbl.cameras = [camHUD];
			_previewGroup.add(sep); _previewGroup.add(slbl);
			// blank key → drag-detection skips headers
			_tlAssetItemsList.push({ bg: sep,  lbl: slbl, key: '', type: '' });
			yOff += 13;
		};

		// Draggable/clickable entry
		var mkEntry = (key:String, type:String, icon:String, col:Int) -> {
			if (yOff + 20 > maxY) return;
			var isActive = (_tlDragAssetKey == key && _tlDragAssetType == type);
			var bgSp = new FlxSprite(2, yOff).makeGraphic(pw, 18, isActive ? col : C_PANEL);
			bgSp.alpha = isActive ? 0.95 : 0.75;
			bgSp.scrollFactor.set(); bgSp.cameras = [camHUD];
			var lbl = new FlxText(5, yOff + 4, pw - 6, '$icon $key', 8);
			lbl.setFormat(Paths.font('vcr.ttf'), 8, col, LEFT);
			lbl.scrollFactor.set(); lbl.cameras = [camHUD];
			_previewGroup.add(bgSp); _previewGroup.add(lbl);
			_tlAssetItemsList.push({ bg: bgSp, lbl: lbl, key: key, type: type });
			yOff += 20;
		};

		// Portraits
		var hasPortraits = false;
		for (_ in currentSkin.portraits) { hasPortraits = true; break; }
		if (hasPortraits) {
			mkSection('PORTRAITS', C_ACCENT);
			for (key => _ in currentSkin.portraits)
				mkEntry(key, 'portrait', '◆', C_ACCENT);
		}

		// Boxes
		var hasBoxes = false;
		for (_ in currentSkin.boxes) { hasBoxes = true; break; }
		if (hasBoxes) {
			mkSection('BOXES', C_ACCENT3);
			for (key => _ in currentSkin.boxes)
				mkEntry(key, 'box', '■', C_ACCENT3);
		}

		// Backgrounds
		if (currentSkin.backgrounds != null) {
			var hasBg = false;
			for (_ in currentSkin.backgrounds) { hasBg = true; break; }
			if (hasBg) {
				mkSection('BG', 0xFFFF9933);
				for (key => _ in currentSkin.backgrounds)
					mkEntry(key, 'background', '▣', 0xFFFF9933);
			}
		}

		// Music: unique soundFile values from existing clips + import shortcut
		mkSection('MUSIC', 0xFF00E894);
		var addedM = new Map<String, Bool>();
		for (c in clips)
			if (c.trackId == 'music' && c.soundFile != null && c.soundFile != '' && !addedM.exists(c.soundFile)) {
				mkEntry(c.soundFile, 'music', '♪', 0xFF00E894);
				addedM.set(c.soundFile, true);
			}
		mkEntry('+ import…', 'music_import', '♪', 0xFF006633);

		// Sound FX: same pattern
		mkSection('SOUND FX', 0xFFFFCC44);
		var addedS = new Map<String, Bool>();
		for (c in clips)
			if (c.trackId == 'sound' && c.soundFile != null && c.soundFile != '' && !addedS.exists(c.soundFile)) {
				mkEntry(c.soundFile, 'sound', '▶', 0xFFFFCC44);
				addedS.set(c.soundFile, true);
			}
		mkEntry('+ import…', 'sound_import', '▶', 0xFF664400);
	}

	static function DLGColorFor(t:String):Int {
		return switch (t) {
			case 'portrait':   0xFF3344AA;
			case 'box':        0xFF2A6644;
			case 'background': 0xFF553322;
			case 'overlay':    0xFF445533;
			default:           0xFF333344;
		}
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  CLIP MANAGEMENT
	// ═════════════════════════════════════════════════════════════════════════

	function _syncClipsFromConversation():Void {
		// Rebuild DIALOGUE track clips from conversation.messages
		clips = clips.filter(c -> c.trackId != 'dialogue');

		for (i in 0...conversation.messages.length) {
			var msg = conversation.messages[i];
			clips.push({
				id: 'dlg_$i',
				trackId: 'dialogue',
				startSlot: i,
				duration: 1.0,
				msgIndex: i,
				character: msg.character,
				text: msg.text,
				bubbleType: msg.bubbleType,
				speed: msg.speed,
				portrait: msg.portrait,
				boxSprite: msg.boxSprite,
				music: msg.music,
				sound: msg.sound,
			});
		}
		_rebuildClips();
	}

	function _syncConversationFromClips():Void {
		// Rebuild messages from DIALOGUE track clips (sorted by startSlot)
		var dialogueClips = clips.filter(c -> c.trackId == 'dialogue');
		dialogueClips.sort((a, b) -> Std.int(a.startSlot - b.startSlot));

		conversation.messages = [];
		for (clip in dialogueClips) {
			conversation.messages.push({
				character: clip.character ?? 'bf',
				text: clip.text ?? '',
				bubbleType: clip.bubbleType,
				speed: clip.speed,
				portrait: clip.portrait,
				boxSprite: clip.boxSprite,
				music: clip.music,
				sound: clip.sound,
			});
		}
	}

	function _findClip(id:String):DLGClipData {
		for (c in clips)
			if (c.id == id) return c;
		return null;
	}

	function _getTrackIndex(trackId:String):Int {
		for (i in 0...tracks.length)
			if (tracks[i].id == trackId) return i;
		return -1;
	}

	function _selectClip(id:String):Void {
		selectedClipId = id;
		var clip = _findClip(id);
		if (clip != null && clip.trackId == 'dialogue')
			_previewMsgIdx = Std.int(clip.startSlot);
		_rebuildClips();
		_refreshClipInspector();
		_updateConvInfoText();
	}

	function _updateConvInfoText():Void {
		if (_convInfoTxt != null) {
			var msgCount = conversation != null ? conversation.messages.length : 0;
			_convInfoTxt.text = 'song: $songName  |  conv: ${conversation?.name ?? "none"}  |  msgs: $msgCount';
		}
		if (_skinNameTxt != null)
			_skinNameTxt.text = 'skin: $currentSkinName  |  style: ${currentSkin?.style ?? "normal"}';
	}

	function _pushUndo():Void {
		var snap = Json.stringify({ conv: conversation, clips: clips, skin: _skinSnap(), skinName: currentSkinName });
		_undoStack.push(snap);
		if (_undoStack.length > MAX_UNDO) _undoStack.shift();
		_redoStack = [];
		hasUnsaved = true;
		if (_unsavedDot != null && _mode != 'scene') _unsavedDot.visible = true;
	}

	// ── Skin serialization helpers (for undo snapshots) ───────────────────────

	/** Serialize current skin to a plain Dynamic (Maps → plain objects). */
	function _skinSnap():Dynamic {
		if (currentSkin == null) return null;
		var pObj:Dynamic = {};
		for (k => v in currentSkin.portraits) Reflect.setField(pObj, k, v);
		var bObj:Dynamic = {};
		for (k => v in currentSkin.boxes) Reflect.setField(bObj, k, v);
		var bgObj:Dynamic = {};
		if (currentSkin.backgrounds != null)
			for (k => v in currentSkin.backgrounds) Reflect.setField(bgObj, k, v);
		var ovObj:Dynamic = {};
		if (currentSkin.overlays != null)
			for (k => v in currentSkin.overlays) Reflect.setField(ovObj, k, v);
		return {
			name: currentSkin.name,
			style: currentSkin.style,
			backgroundColor: currentSkin.backgroundColor,
			fadeTime: currentSkin.fadeTime,
			scriptFile: currentSkin.scriptFile,
			portraits: pObj,
			boxes: bObj,
			backgrounds: bgObj,
			overlays: ovObj,
			textConfig: currentSkin.textConfig
		};
	}

	/** Restore skin from a plain Dynamic snapshot produced by _skinSnap(). */
	function _applySkinSnap(snap:Dynamic):Void {
		if (snap == null) return;
		var pMap = new Map<String, PortraitConfig>();
		if (snap.portraits != null)
			for (k in Reflect.fields(snap.portraits))
				pMap.set(k, cast Reflect.field(snap.portraits, k));
		var bMap = new Map<String, BoxConfig>();
		if (snap.boxes != null)
			for (k in Reflect.fields(snap.boxes))
				bMap.set(k, cast Reflect.field(snap.boxes, k));
		var bgMap = new Map<String, funkin.cutscenes.dialogue.DialogueData.BackgroundConfig>();
		if (snap.backgrounds != null)
			for (k in Reflect.fields(snap.backgrounds))
				bgMap.set(k, cast Reflect.field(snap.backgrounds, k));
		var ovMap = new Map<String, funkin.cutscenes.dialogue.DialogueData.BackgroundConfig>();
		if (snap.overlays != null)
			for (k in Reflect.fields(snap.overlays))
				ovMap.set(k, cast Reflect.field(snap.overlays, k));
		currentSkin = {
			name: snap.name,
			style: snap.style ?? 'normal',
			backgroundColor: snap.backgroundColor,
			fadeTime: snap.fadeTime,
			scriptFile: snap.scriptFile,
			portraits: pMap,
			boxes: bMap,
			backgrounds: bgMap,
			overlays: ovMap,
			textConfig: snap.textConfig
		};
	}

	// ── Auto-name helper ──────────────────────────────────────────────────────

	/**
	 * Ensures currentSkinName is non-empty and the folder exists.
	 * If the name is blank / "default" / "new_skin", auto-assigns "unnamed0",
	 * "unnamed1" … picking the lowest free index.
	 */
	function _ensureSkinName():Void {
		var needsName = (currentSkinName == null || currentSkinName == ''
			|| currentSkinName == 'default' || currentSkinName == 'new_skin');
		if (!needsName) {
			// Just make sure directories exist
			DialogueData.createSkinDirectories(currentSkinName);
			return;
		}
		#if sys
		var existing = DialogueData.getAvailableSkins();
		var idx = 0;
		while (existing.indexOf('unnamed$idx') >= 0) idx++;
		currentSkinName = 'unnamed$idx';
		#else
		currentSkinName = 'unnamed0';
		#end
		if (currentSkin == null)
			currentSkin = DialogueData.createEmptySkin(currentSkinName, 'normal');
		else
			currentSkin.name = currentSkinName;
		DialogueData.createSkinDirectories(currentSkinName);
		_updateConvInfoText();
		_refreshSkinInspectorFields();
		_showStatus('Auto-created skin folder: $currentSkinName');
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  UPDATE
	// ═════════════════════════════════════════════════════════════════════════

	override public function update(elapsed:Float):Void {
		super.update(elapsed);

		// Close menus on click elsewhere
		if (FlxG.mouse.justPressed && _activeMenu >= 0) {
			var onMenu = false;
			for (m in _menuItems)
				if (FlxG.mouse.overlaps(m, camHUD)) { onMenu = true; break; }
			var onDd = false;
			for (dd in _menuDropdowns)
				for (m in dd.members)
					if (m != null && FlxG.mouse.overlaps(m, camHUD)) { onDd = true; break; }
			if (!onMenu && !onDd) _closeMenus();
		}

		// Keyboard shortcuts
		_updateKeyboard();

		if (_mode == 'scene')
			_updateSceneBuilder();
		else
			_updateTimelineInput();
	}

	function _updateKeyboard():Void {
		var ctrl = FlxG.keys.pressed.CONTROL;

		if (ctrl && FlxG.keys.justPressed.S) _doSave();
		if (ctrl && FlxG.keys.justPressed.Z) _doUndo();
		if (ctrl && FlxG.keys.justPressed.Y) _doRedo();

		if (FlxG.keys.justPressed.ESCAPE)
			_doBack();

		if (FlxG.keys.justPressed.F1)
			_showHelp();

		// Timeline scroll
		if (_mode == 'timeline') {
			if (FlxG.keys.justPressed.LEFT && tlScrollSlot > 0) { tlScrollSlot--; _rebuildTimeline(); }
			if (FlxG.keys.justPressed.RIGHT) { tlScrollSlot++; _rebuildTimeline(); }
			// Zoom with ctrl+scroll
			if (ctrl && FlxG.mouse.wheel != 0) {
				tlZoom = FlxMath.bound(tlZoom + FlxG.mouse.wheel * 0.1, 0.25, 4.0);
				_rebuildTimeline();
			} else if (!ctrl && FlxG.mouse.wheel != 0) {
				tlScrollSlot = FlxMath.bound(tlScrollSlot - FlxG.mouse.wheel, 0, conversation != null ? conversation.messages.length + 1 : 0);
				_rebuildTimeline();
			}
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Scene builder interaction
	// ─────────────────────────────────────────────────────────────────────────
	function _updateSceneBuilder():Void {
		if (!_sceneGroup.visible) return;

		// Check asset list clicks
		if (FlxG.mouse.justPressed) {
			for (i in 0..._assetItems.length) {
				if (FlxG.mouse.overlaps(_assetItems[i].bg, camHUD)) {
					// Select corresponding canvas element
					for (j in 0..._canvasElements.length) {
						if (_canvasElements[j].key == _assetItems[i].key) {
							_selectedElementIdx = j;
							_refreshElementInspector();
							_rebuildAssetList();
							break;
						}
					}
					break;
				}
			}
		}

		// Canvas element drag
		if (FlxG.mouse.justPressed && _dragElementIdx < 0) {
			for (i in _canvasElements.length - 1...(-1)) {
				if (i < 0) break;
				var el = _canvasElements[i];
				if (FlxG.mouse.overlaps(el.sprite, camHUD)) {
					_dragElementIdx = i;
					_dragElemOffX = FlxG.mouse.x - el.sprite.x;
					_dragElemOffY = FlxG.mouse.y - el.sprite.y;
					_selectedElementIdx = i;
					_refreshElementInspector();
					_rebuildAssetList();
					break;
				}
			}
		}

		if (_dragElementIdx >= 0) {
			if (FlxG.mouse.pressed) {
				var el = _canvasElements[_dragElementIdx];
				el.sprite.x = FlxG.mouse.x - _dragElemOffX;
				el.sprite.y = FlxG.mouse.y - _dragElemOffY;

				// Convert back to skin coordinates
				var frameW = CANVAS_W * 0.85;
				var frameH = frameW * 720 / 1280;
				var frameX = CANVAS_X + (CANVAS_W - frameW) / 2;
				var frameY = _mainAreaY() + (_vpHeight - frameH) / 2;
				var scaleF = frameW / 1280;

				var skinX = (el.sprite.x - frameX) / scaleF;
				var skinY = (el.sprite.y - frameY) / scaleF;

				if (el.type == 'portrait' && currentSkin != null) {
					var pc = currentSkin.portraits.get(el.key);
					if (pc != null) { pc.x = skinX; pc.y = skinY; }
				} else if (el.type == 'box' && currentSkin != null) {
					var bc = currentSkin.boxes.get(el.key);
					if (bc != null) { bc.x = skinX; bc.y = skinY; }
				}
				_refreshElementInspector();
			}
			if (FlxG.mouse.justReleased) _dragElementIdx = -1;
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Timeline interaction
	// ─────────────────────────────────────────────────────────────────────────
	function _updateTimelineInput():Void {
		if (!_tlGroup.visible) return;

		var tlY = _tlY();
		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;

		// ── Asset panel: pick up an item ──────────────────────────────────────
		if (FlxG.mouse.justPressed && _tlDragAssetKey == '' && _dragClip == null && _resizeClip == null) {
			for (item in _tlAssetItemsList) {
				if (item.key == '' || item.type == '') continue;
				if (FlxG.mouse.overlaps(item.bg, camHUD)) {
					// Import shortcuts fire immediately
					if (item.type == 'music_import') { _doImportMusic(); break; }
					if (item.type == 'sound_import') { _doImportSound(); break; }

					// Begin drag
					_tlDragAssetKey  = item.key;
					_tlDragAssetType = item.type;

					// Ghost clip sprite (follows cursor)
					var ghostCol = _colorForAssetType(item.type);
					_tlGhostClip = new FlxSprite(mx, my).makeGraphic(80, TL_TRACK_H - 4, ghostCol);
					_tlGhostClip.alpha = 0.55;
					_tlGhostClip.scrollFactor.set();
					_tlGhostClip.cameras = [camHUD];
					add(_tlGhostClip);

					_tlGhostLabel = new FlxText(mx + 4, my + 4, 80, item.key, 8);
					_tlGhostLabel.setFormat(Paths.font('vcr.ttf'), 8, FlxColor.WHITE, LEFT);
					_tlGhostLabel.scrollFactor.set();
					_tlGhostLabel.cameras = [camHUD];
					add(_tlGhostLabel);

					_rebuildTimelineAssets();   // highlight selected item
					_showStatus('Dragging "${item.key}" — drop on any track to create a clip');
					break;
				}
			}
		}

		// ── Asset drag: move ghost + drop ─────────────────────────────────────
		if (_tlDragAssetKey != '') {
			if (FlxG.mouse.pressed && _tlGhostClip != null) {
				// Default: ghost follows cursor loosely
				_tlGhostClip.x   = mx - 4;
				_tlGhostClip.y   = my - Std.int((TL_TRACK_H - 4) / 2);
				_tlGhostLabel.x  = _tlGhostClip.x + 4;
				_tlGhostLabel.y  = _tlGhostClip.y + Std.int((TL_TRACK_H - 4 - 8) / 2);

				// Snap to track grid when hovering over the timeline content area
				if (my > tlY + TL_RULER_H && mx > TL_LABEL_W && mx < SW - INSP_W) {
					var snapSlot = Math.round(_xToSlot(mx));
					var snapX    = _slotToX(snapSlot);
					var vi       = Std.int((my - tlY - TL_RULER_H) / TL_TRACK_H);
					var trackY   = tlY + TL_RULER_H + vi * TL_TRACK_H;
					_tlGhostClip.x   = snapX;
					_tlGhostClip.y   = trackY + 2;
					_tlGhostLabel.x  = snapX + 4;
					_tlGhostLabel.y  = trackY + 2 + Std.int((TL_TRACK_H - 4 - 8) / 2);
				}
			}

			if (FlxG.mouse.justReleased) {
				// Destroy ghost visuals
				if (_tlGhostClip  != null) { remove(_tlGhostClip);  _tlGhostClip.destroy();  _tlGhostClip  = null; }
				if (_tlGhostLabel != null) { remove(_tlGhostLabel); _tlGhostLabel.destroy(); _tlGhostLabel = null; }

				// Check if dropped on a valid track
				if (my > tlY + TL_RULER_H && mx > TL_LABEL_W && mx < SW - INSP_W) {
					var vi = Std.int((my - tlY - TL_RULER_H) / TL_TRACK_H);
					var ti = vi + _trackScrollY;
					if (ti >= 0 && ti < tracks.length && !tracks[ti].locked)
						_addClipFromAsset(tracks[ti].id, _xToSlot(mx), _tlDragAssetKey, _tlDragAssetType);
					else
						_showStatus('Cannot drop here — track is locked or out of range');
				}

				var savedKey  = _tlDragAssetKey;
				_tlDragAssetKey  = '';
				_tlDragAssetType = '';
				_rebuildTimelineAssets();
			}

			// If a drag is in progress, skip all other timeline input this frame
			return;
		}

		// Ruler click → seek playhead
		if (FlxG.mouse.justPressed && my >= tlY && my < tlY + TL_RULER_H && mx > TL_LABEL_W && mx < SW - INSP_W) {
			var slot = Std.int(_xToSlot(mx));
			_previewMsgIdx = Std.int(FlxMath.bound(slot, 0, conversation != null ? conversation.messages.length - 1 : 0));
			_updatePlayheadPos();
		}

		// Double-click on track area → add clip
		if (FlxG.mouse.justPressed) {
			var now = haxe.Timer.stamp();
			var doubleClick = (now - _lastClickTime < 0.35) && Math.abs(mx - _lastClickX) < 6 && Math.abs(my - _lastClickY) < 6;
			_lastClickTime = now; _lastClickX = mx; _lastClickY = my;

			if (doubleClick && my > tlY + TL_RULER_H && mx > TL_LABEL_W && mx < SW - INSP_W) {
				var vi = Std.int((my - tlY - TL_RULER_H) / TL_TRACK_H);
				var ti = vi + _trackScrollY;
				if (ti >= 0 && ti < tracks.length && !tracks[ti].locked) {
					var slot = _xToSlot(mx);
					_addClipAt(tracks[ti].id, slot);
				}
			}
		}

		// Clip selection + drag
		if (FlxG.mouse.justPressed && _dragClip == null) {
			for (i in _clipBlocks.length - 1...(-1)) {
				if (i < 0) break;
				var block = _clipBlocks[i];
				if (FlxG.mouse.overlaps(block, camHUD)) {
					var clip = _findClip(block.clipId);
					if (clip != null) {
						var ti = _getTrackIndex(clip.trackId);
						if (ti >= 0 && !tracks[ti].locked) {
							// Check resize handle (right edge)
							var resizeZone = block.x + block.width - 8;
							if (mx >= resizeZone) {
								_resizeClip = block;
								_resizeOrigDur = clip.duration;
								_resizeStartX = mx;
							} else {
								_dragClip = block;
								_dragClipOffSlot = _xToSlot(mx) - clip.startSlot;
							}
						}
					}
					_selectClip(block.clipId);
					break;
				}
			}
		}

		if (_dragClip != null) {
			if (FlxG.mouse.pressed) {
				var clip = _findClip(_dragClip.clipId);
				if (clip != null) {
					var newSlot = FlxMath.bound(_xToSlot(mx) - _dragClipOffSlot, 0, 99);
					// Snap to integer if dialogue track
					if (clip.trackId == 'dialogue')
						newSlot = Math.round(newSlot);
					clip.startSlot = newSlot;
					_rebuildClips();
				}
			}
			if (FlxG.mouse.justReleased) {
				_syncConversationFromClips();
				_syncClipsFromConversation();
				_dragClip = null;
				hasUnsaved = true;
			}
		}

		if (_resizeClip != null) {
			if (FlxG.mouse.pressed) {
				var clip = _findClip(_resizeClip.clipId);
				if (clip != null) {
					var deltaSlots = (_xToSlot(mx) - _xToSlot(_resizeStartX));
					clip.duration = FlxMath.bound(_resizeOrigDur + deltaSlots, 0.25, 32);
					_rebuildClips();
				}
			}
			if (FlxG.mouse.justReleased) _resizeClip = null;
		}

		// Horizontal scrollbar drag
		if (_tlHScrollBg != null && FlxG.mouse.justPressed && FlxG.mouse.overlaps(_tlHScrollBg, camHUD))
			_hScrollDrag = true;
		if (!FlxG.mouse.pressed) _hScrollDrag = false;
		if (_hScrollDrag) {
			var ratio = (mx - TL_LABEL_W) / (_tlHScrollBg.width);
			var totalSlots = conversation != null ? conversation.messages.length + 2 : 8;
			tlScrollSlot = FlxMath.bound(ratio * totalSlots, 0, totalSlots - 1);
			_rebuildTimeline();
		}
	}

	function _addClipAt(trackId:String, slot:Float):Void {
		if (conversation == null) return;
		var id = '${trackId}_${++_uid}';
		var clip:DLGClipData = { id: id, trackId: trackId, startSlot: Math.round(slot), duration: 1.0 };
		switch (trackId) {
			case 'dialogue':
				clip.character = 'bf';
				clip.text = 'New message';
				clip.bubbleType = 'normal';
				clip.speed = 0.04;
			case 'portrait':
				clip.portraitName = 'bf';
			case 'background':
				clip.bgColor = '#000000';
			case 'music':
				clip.soundFile = '';
				clip.volume = 1.0;
				clip.loop = true;
				clip.duration = 4.0;   // music usually spans several messages
			case 'sound':
				clip.soundFile = '';
				clip.volume = 1.0;
				clip.loop = false;
				clip.duration = 1.0;
		}
		_pushUndo();
		clips.push(clip);
		if (trackId == 'dialogue') _syncConversationFromClips();
		_rebuildClips();
		_selectClip(id);
		_showStatus('Added clip on $trackId track at slot ${Math.round(slot) + 1}');
	}

	/**
	 * Create a new clip on `trackId` at `slot`, pre-filling fields from the
	 * dragged asset (key + type come from the timeline asset panel).
	 */
	function _addClipFromAsset(trackId:String, slot:Float, assetKey:String, assetType:String):Void {
		if (conversation == null) return;
		var id   = '${trackId}_${++_uid}';
		var clip:DLGClipData = { id: id, trackId: trackId, startSlot: Math.round(slot), duration: 1.0 };

		switch (assetType) {
			case 'portrait':
				if (trackId == 'dialogue') {
					clip.character  = assetKey;
					clip.text       = 'New message';
					clip.bubbleType = 'normal';
					clip.speed      = 0.04;
					clip.portrait   = assetKey;
				} else {
					clip.portraitName = assetKey;
				}
			case 'box':
				if (trackId == 'dialogue') {
					clip.character  = 'bf';
					clip.text       = 'New message';
					clip.bubbleType = 'normal';
					clip.speed      = 0.04;
					clip.boxSprite  = assetKey;
				} else {
					clip.portraitName = assetKey;
				}
			case 'background':
				clip.bgColor = assetKey;
			case 'music':
				clip.soundFile = assetKey;
				clip.volume    = 1.0;
				clip.loop      = true;
				clip.duration  = 4.0;
			case 'sound':
				clip.soundFile = assetKey;
				clip.volume    = 1.0;
				clip.loop      = false;
			default:
				// Fallback: use track-type defaults
				switch (trackId) {
					case 'dialogue':   clip.character = 'bf'; clip.text = 'New message'; clip.bubbleType = 'normal'; clip.speed = 0.04;
					case 'portrait':   clip.portraitName = assetKey;
					case 'background': clip.bgColor = '#000000';
					case 'music':      clip.soundFile = ''; clip.volume = 1.0; clip.loop = true;  clip.duration = 4.0;
					case 'sound':      clip.soundFile = ''; clip.volume = 1.0; clip.loop = false;
				}
		}

		_pushUndo();
		clips.push(clip);
		if (trackId == 'dialogue') _syncConversationFromClips();
		_rebuildClips();
		_selectClip(id);
		_rebuildTimelineAssets();   // refresh panel (highlight new audio entries)
		_showStatus('Dropped "$assetKey" → $trackId at slot ${Math.round(slot) + 1}  |  use inspector to edit');
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  ACTIONS
	// ═════════════════════════════════════════════════════════════════════════

	function _doApplyInspector():Void {
		if (_mode == 'scene') {
			_doApplyElementInspector();
		} else {
			_doApplyClipInspector();
		}
	}

	function _doApplyClipInspector():Void {
		var clip = _findClip(selectedClipId);
		if (clip == null) return;
		_pushUndo();

		var isAudio = clip.trackId == 'music' || clip.trackId == 'sound';

		if (isAudio) {
			// ── Apply audio fields ────────────────────────────────────────
			if (_inspAudioFileInput?.text != null && _inspAudioFileInput.text != '')
				clip.soundFile = _inspAudioFileInput.text;
			if (_inspVolumeInput?.text != null && _inspVolumeInput.text != '') {
				var vol = Std.parseFloat(_inspVolumeInput.text);
				if (!Math.isNaN(vol)) clip.volume = FlxMath.bound(vol, 0.0, 1.0);
			}
			if (_inspLoopInput?.text != null) {
				var loopStr = _inspLoopInput.text.toLowerCase().trim();
				clip.loop = (loopStr == 'yes' || loopStr == 'true' || loopStr == '1' || loopStr == 'y');
			}
		} else {
			// ── Apply dialogue fields ─────────────────────────────────────
			clip.character  = _inspCharInput?.text ?? clip.character;
			clip.text       = _inspTextInput?.text ?? clip.text;
			clip.bubbleType = _inspBubbleInput?.text ?? clip.bubbleType;
			clip.speed      = _inspSpeedInput?.text != null && _inspSpeedInput.text != '' ? Std.parseFloat(_inspSpeedInput.text) : clip.speed;
			clip.portrait   = _inspPortraitInput?.text ?? clip.portrait;
			clip.boxSprite  = _inspBoxInput?.text ?? clip.boxSprite;
			clip.music      = _inspMusicInput?.text ?? clip.music;
			if (clip.trackId == 'dialogue') _syncConversationFromClips();
		}

		// Duration applies to every clip type
		if (_inspDurationInput?.text != null && _inspDurationInput.text != '') {
			var dur = Std.parseFloat(_inspDurationInput.text);
			if (!Math.isNaN(dur)) clip.duration = FlxMath.bound(dur, 0.25, 64);
		}

		_rebuildClips();
		_showStatus('Applied  |  track: ${clip.trackId}  dur: ${clip.duration}  slot: ${Std.int(clip.startSlot) + 1}');
	}

	function _doApplyElementInspector():Void {
		if (_selectedElementIdx < 0 || _selectedElementIdx >= _canvasElements.length) return;
		_pushUndo();   // snapshot before modifying element positions / skin config
		var el = _canvasElements[_selectedElementIdx];

		var x      = _inspElemXInput?.text != null      ? Std.parseFloat(_inspElemXInput.text) : 0.0;
		var y      = _inspElemYInput?.text != null      ? Std.parseFloat(_inspElemYInput.text) : 0.0;
		var scaleX = _inspElemScaleXInput?.text != null ? Std.parseFloat(_inspElemScaleXInput.text) : 1.0;
		var scaleY = _inspElemScaleYInput?.text != null ? Std.parseFloat(_inspElemScaleYInput.text) : 1.0;
		var anim   = _inspElemAnimInput?.text ?? '';

		if (el.type == 'portrait' && currentSkin != null) {
			var pc = currentSkin.portraits.get(el.key);
			if (pc != null) { pc.x = x; pc.y = y; pc.scaleX = scaleX; pc.scaleY = scaleY; pc.animation = anim; }
		} else if (el.type == 'box' && currentSkin != null) {
			var bc = currentSkin.boxes.get(el.key);
			if (bc != null) { bc.x = x; bc.y = y; bc.scaleX = scaleX; bc.scaleY = scaleY; bc.animation = anim; }
		} else if (el.type == 'background' && currentSkin?.backgrounds != null) {
			var bg = currentSkin.backgrounds.get(el.key);
			if (bg != null) { bg.x = x; bg.y = y; bg.scaleX = scaleX; bg.scaleY = scaleY; }
		} else if (el.type == 'overlay' && currentSkin?.overlays != null) {
			var ov = currentSkin.overlays.get(el.key);
			if (ov != null) { ov.x = x; ov.y = y; ov.scaleX = scaleX; ov.scaleY = scaleY; }
		}

		// Apply skin config fields
		if (currentSkin != null) {
			currentSkin.style = _inspSkinStyleInput?.text ?? currentSkin.style;
			currentSkin.backgroundColor = _inspSkinBgInput?.text ?? currentSkin.backgroundColor;
			if (_inspSkinFadeInput?.text != null && _inspSkinFadeInput.text != '')
				currentSkin.fadeTime = Std.parseFloat(_inspSkinFadeInput.text);
		}

		_rebuildCanvasSprites();
		hasUnsaved = true;
		_showStatus('Applied element changes');
	}

	function _doNewSkin():Void {
		_closeMenus();
		// Don't keep stale name — let _ensureSkinName generate a fresh one next import
		currentSkinName = 'new_skin';
		currentSkin = DialogueData.createEmptySkin(currentSkinName, 'normal');
		_selectedElementIdx = -1;
		_rebuildCanvasSprites();
		_refreshSkinInspectorFields();
		_updateConvInfoText();
		_showStatus('New skin ready — add a portrait or box to auto-create its folder');
	}

	function _doLoadSkin():Void {
		_closeMenus();
		#if sys
		// Let user pick the skin's config.json directly
		var fd = new FileDialog();
		fd.onSelect.add(function(path:String) {
			// path → .../cutscenes/dialogue/<skinName>/config.json
			var skinDir  = haxe.io.Path.directory(path);
			var skinName = haxe.io.Path.withoutDirectory(skinDir);
			var skin = DialogueData.loadSkin(skinName);
			if (skin != null) {
				currentSkinName = skinName;
				currentSkin = skin;
				_selectedElementIdx = -1;
				_rebuildCanvasSprites();
				_refreshSkinInspectorFields();
				_updateConvInfoText();
				_showStatus('Loaded skin: $skinName');
			} else {
				// Fallback: try by available list
				var skins = DialogueData.getAvailableSkins();
				if (skins.length > 0) {
					currentSkinName = skins[0];
					currentSkin = DialogueData.loadSkin(currentSkinName);
					_rebuildCanvasSprites();
					_refreshSkinInspectorFields();
					_updateConvInfoText();
					_showStatus('Loaded skin: $currentSkinName');
				} else {
					_showStatus('Could not load skin from: $path');
				}
			}
		});
		fd.browse(lime.ui.FileDialogType.OPEN, 'json', null, 'Select skin config.json');
		#else
		// Web: just pick from available list
		var skins = DialogueData.getAvailableSkins();
		if (skins.length == 0) { _showStatus('No skins found'); return; }
		currentSkinName = skins[0];
		currentSkin = DialogueData.loadSkin(currentSkinName);
		if (currentSkin != null) {
			_rebuildCanvasSprites(); _refreshSkinInspectorFields(); _updateConvInfoText();
			_showStatus('Loaded skin: $currentSkinName');
		}
		#end
	}

	function _doSaveSkin():Void {
		_closeMenus();
		if (currentSkin == null) return;
		// Apply skin config fields before saving
		if (currentSkin != null) {
			currentSkin.style = _inspSkinStyleInput?.text ?? currentSkin.style;
			currentSkin.backgroundColor = _inspSkinBgInput?.text ?? currentSkin.backgroundColor;
			if (_inspSkinFadeInput?.text != null && _inspSkinFadeInput.text != '')
				currentSkin.fadeTime = Std.parseFloat(_inspSkinFadeInput.text);
		}
		if (DialogueData.saveSkin(currentSkinName, currentSkin)) {
			hasUnsaved = false;
			_showStatus('Skin saved: $currentSkinName → assets/cutscenes/dialogue/$currentSkinName/config.json');
		} else {
			_showStatus('Error saving skin. Check file permissions.');
		}
	}

	function _doNewConv():Void {
		_closeMenus();
		conversation = DialogueData.createEmptyConversation('intro', currentSkinName);
		_syncClipsFromConversation();
		_updateConvInfoText();
		_showStatus('New conversation created');
	}

	function _doLoadConv():Void {
		_closeMenus();
		#if sys
		// FIX: usar FileDialog en vez de songName (que por defecto es 'Test' y nunca
		// encontraba el archivo). Ahora el usuario elige directamente el intro.json / outro.json.
		var fd = new FileDialog();
		fd.onSelect.add(function(path:String) {
			try {
				var content = sys.io.File.getContent(path);
				var data:Dynamic = haxe.Json.parse(content);
				if (data.messages == null) {
					_showStatus('El archivo seleccionado no parece una conversación (falta "messages")');
					return;
				}
				_pushUndo();
				conversation = cast data;
				// FIX: auto-cargar la skin referenciada en la conversación
				if (conversation.skinName != null && conversation.skinName != '') {
					var skin = DialogueData.loadSkin(conversation.skinName);
					if (skin != null) {
						currentSkinName = conversation.skinName;
						currentSkin = skin;
						_rebuildCanvasSprites();
						_refreshSkinInspectorFields();
					} else {
						_showStatus('Conversación cargada pero no se encontró la skin "${conversation.skinName}"');
					}
				}
				_syncClipsFromConversation();
				_updateConvInfoText();
				// FIX: cambiar al modo timeline donde se ven los clips
				if (_mode != 'timeline') _switchMode('timeline');
				else { _rebuildTimeline(); _rebuildTimelineAssets(); }
				_showStatus('Conversación cargada: ${conversation.name}  (${conversation.messages.length} mensajes)  |  skin: ${conversation.skinName ?? "ninguna"}');
			} catch (e:Dynamic) {
				_showStatus('Error al leer la conversación: $e');
			}
		});
		fd.browse(lime.ui.FileDialogType.OPEN, 'json', null, 'Seleccionar archivo de conversación (intro.json / outro.json)');
		#else
		// Web: intentar carga por songName como fallback
		var conv = DialogueData.loadConversation(songName, 'intro');
		if (conv != null) {
			conversation = conv;
			if (conversation.skinName != null && conversation.skinName != '') {
				var skin = DialogueData.loadSkin(conversation.skinName);
				if (skin != null) { currentSkinName = conversation.skinName; currentSkin = skin; _rebuildCanvasSprites(); _refreshSkinInspectorFields(); }
			}
			_syncClipsFromConversation();
			_updateConvInfoText();
			if (_mode != 'timeline') _switchMode('timeline');
			_showStatus('Conversación cargada: ${conv.name}');
		} else {
			_showStatus('No se encontró conversación para la canción: $songName');
		}
		#end
	}

	function _doSaveConv():Void {
		_closeMenus();
		_syncConversationFromClips();
		if (DialogueData.saveConversation(songName, conversation)) {
			hasUnsaved = false;
			if (_unsavedDot != null) _unsavedDot.visible = false;
			_showStatus('Conversation saved: $songName/${conversation.name}.json');
		} else {
			_showStatus('Error saving conversation.');
		}
	}

	function _doSave():Void {
		if (_mode == 'scene') _doSaveSkin() else _doSaveConv();
	}

	function _doTestDialogue():Void {
		_closeMenus();
		_showStatus('Test: opening dialogue preview…');
		// TODO: launch DialogueBoxImproved in a sub-state
	}

	function _doAddMessage():Void {
		if (conversation == null) return;
		_pushUndo();
		var msg:DialogueMessage = {
			character: 'bf',
			text: 'New message ' + (conversation.messages.length + 1),
			bubbleType: 'normal',
			speed: 0.04,
		};
		conversation.messages.push(msg);
		_syncClipsFromConversation();
		_updateConvInfoText();
		_showStatus('Added message ${conversation.messages.length}');
	}

	function _doRemoveMessage():Void {
		if (conversation == null || conversation.messages.length == 0) return;
		var clip = _findClip(selectedClipId);
		var idx = clip != null && clip.trackId == 'dialogue' ? clip.msgIndex ?? (conversation.messages.length - 1) : conversation.messages.length - 1;
		if (idx < 0 || idx >= conversation.messages.length) return;
		_pushUndo();
		conversation.messages.splice(idx, 1);
		selectedClipId = '';
		_syncClipsFromConversation();
		_updateConvInfoText();
		_showStatus('Removed message ${idx + 1}');
	}

	function _doDuplicateMessage():Void {
		var clip = _findClip(selectedClipId);
		if (clip == null || clip.trackId != 'dialogue') return;
		var idx = clip.msgIndex ?? 0;
		if (idx < 0 || idx >= conversation.messages.length) return;
		_pushUndo();
		var orig = conversation.messages[idx];
		var dupe:DialogueMessage = {
			character: orig.character,
			text: orig.text + ' (copy)',
			bubbleType: orig.bubbleType,
			speed: orig.speed,
			portrait: orig.portrait,
			boxSprite: orig.boxSprite,
			music: orig.music,
		};
		conversation.messages.insert(idx + 1, dupe);
		_syncClipsFromConversation();
		_showStatus('Duplicated message ${idx + 1}');
	}

	function _doMoveUp():Void {
		var clip = _findClip(selectedClipId);
		if (clip == null || clip.trackId != 'dialogue') return;
		var idx = clip.msgIndex ?? 0;
		if (idx <= 0) return;
		_pushUndo();
		var tmp = conversation.messages[idx];
		conversation.messages[idx] = conversation.messages[idx - 1];
		conversation.messages[idx - 1] = tmp;
		_syncClipsFromConversation();
		_showStatus('Moved message up');
	}

	function _doMoveDown():Void {
		var clip = _findClip(selectedClipId);
		if (clip == null || clip.trackId != 'dialogue') return;
		var idx = clip.msgIndex ?? 0;
		if (idx >= conversation.messages.length - 1) return;
		_pushUndo();
		var tmp = conversation.messages[idx];
		conversation.messages[idx] = conversation.messages[idx + 1];
		conversation.messages[idx + 1] = tmp;
		_syncClipsFromConversation();
		_showStatus('Moved message down');
	}

	function _doAddPortrait():Void {
		_closeMenus();
		#if sys
		var fd = new FileDialog();
		fd.onSelect.add(function(path:String) {
			// Auto-create skin folder if needed
			_ensureSkinName();

			var fileName = haxe.io.Path.withoutDirectory(path);
			var baseKey  = haxe.io.Path.withoutExtension(fileName);

			// Resolve key collisions (portrait_1, portrait_2 …)
			var finalKey = baseKey;
			var n = 1;
			while (currentSkin.portraits.exists(finalKey))
				finalKey = '${baseKey}_$n' ; n++;

			// Snapshot for undo BEFORE making any changes
			_pushUndo();

			if (DialogueData.copyPortraitToSkin(path, currentSkinName, fileName)) {
				var pc = DialogueData.createPortraitConfig(finalKey, fileName);
				currentSkin.portraits.set(finalKey, pc);
				hasUnsaved = true;
				_rebuildCanvasSprites();
				_showStatus('Portrait "$finalKey" added → cutscenes/dialogue/$currentSkinName/portraits/$fileName');
			} else {
				// Roll back the undo we just pushed (copy failed)
				_undoStack.pop();
				_showStatus('Error: could not copy file — check permissions or skin path');
			}
		});
		fd.browse(lime.ui.FileDialogType.OPEN, 'png,jpg,jpeg,gif,webp', null, 'Select Portrait Image');
		#else
		_showStatus('File dialog not supported on this platform');
		#end
	}

	function _doAddBox():Void {
		_closeMenus();
		#if sys
		var fd = new FileDialog();
		fd.onSelect.add(function(path:String) {
			_ensureSkinName();

			var fileName = haxe.io.Path.withoutDirectory(path);
			var baseKey  = haxe.io.Path.withoutExtension(fileName);

			var finalKey = baseKey;
			var n = 1;
			while (currentSkin.boxes.exists(finalKey))
				finalKey = '${baseKey}_$n'; n++;

			_pushUndo();

			if (DialogueData.copyBoxToSkin(path, currentSkinName, fileName)) {
				var bc = DialogueData.createBoxConfig(finalKey, fileName);
				currentSkin.boxes.set(finalKey, bc);
				hasUnsaved = true;
				_rebuildCanvasSprites();
				_showStatus('Box "$finalKey" added → cutscenes/dialogue/$currentSkinName/boxes/$fileName');
			} else {
				_undoStack.pop();
				_showStatus('Error: could not copy file — check permissions or skin path');
			}
		});
		fd.browse(lime.ui.FileDialogType.OPEN, 'png,jpg,jpeg,gif,webp', null, 'Select Dialogue Box Image');
		#else
		_showStatus('File dialog not supported on this platform');
		#end
	}

	function _doAddBackground():Void {
		_closeMenus();
		#if sys
		var fd = new FileDialog();
		fd.onSelect.add(function(path:String) {
			_ensureSkinName();
			var fileName = haxe.io.Path.withoutDirectory(path);
			var baseKey  = haxe.io.Path.withoutExtension(fileName);
			var finalKey = baseKey;
			var n = 1;
			while (currentSkin.backgrounds != null && currentSkin.backgrounds.exists(finalKey))
				finalKey = '${baseKey}_$n'; n++;
			_pushUndo();
			if (DialogueData.copyBackgroundToSkin(path, currentSkinName, fileName)) {
				if (currentSkin.backgrounds == null)
					currentSkin.backgrounds = new Map();
				var bc = DialogueData.createBackgroundConfig(finalKey, fileName);
				currentSkin.backgrounds.set(finalKey, bc);
				hasUnsaved = true;
				_rebuildCanvasSprites();
				_showStatus('Background "$finalKey" added → cutscenes/dialogue/$currentSkinName/backgrounds/$fileName');
			} else {
				_undoStack.pop();
				_showStatus('Error: could not copy background image — check permissions');
			}
		});
		fd.browse(lime.ui.FileDialogType.OPEN, 'png,jpg,jpeg,gif,webp', null, 'Select Background Image');
		#else
		_showStatus('File dialog not supported on this platform');
		#end
	}

	function _doAddOverlay():Void {
		_closeMenus();
		#if sys
		var fd = new FileDialog();
		fd.onSelect.add(function(path:String) {
			_ensureSkinName();
			var fileName = haxe.io.Path.withoutDirectory(path);
			var baseKey  = haxe.io.Path.withoutExtension(fileName);
			var finalKey = baseKey;
			var n = 1;
			while (currentSkin.overlays != null && currentSkin.overlays.exists(finalKey))
				finalKey = '${baseKey}_$n'; n++;
			_pushUndo();
			if (DialogueData.copyOverlayToSkin(path, currentSkinName, fileName)) {
				if (currentSkin.overlays == null)
					currentSkin.overlays = new Map();
				var oc = DialogueData.createBackgroundConfig(finalKey, fileName);
				oc.alpha = 0.8;
				currentSkin.overlays.set(finalKey, oc);
				hasUnsaved = true;
				_rebuildCanvasSprites();
				_showStatus('Overlay "$finalKey" added → cutscenes/dialogue/$currentSkinName/overlays/$fileName');
			} else {
				_undoStack.pop();
				_showStatus('Error: could not copy overlay image — check permissions');
			}
		});
		fd.browse(lime.ui.FileDialogType.OPEN, 'png,jpg,jpeg,gif,webp', null, 'Select Overlay Image');
		#else
		_showStatus('File dialog not supported on this platform');
		#end
	}

	// ── Audio import / browse ─────────────────────────────────────────────────

	/**
	 * Browse for an audio file from the inspector BROWSE button.
	 * Copies it to the skin's music/ or sounds/ folder depending on
	 * which track type the currently selected clip belongs to.
	 */
	function _doBrowseAudioFile():Void {
		#if sys
		var clip = _findClip(selectedClipId);
		if (clip == null) { _showStatus('Select a music or sound clip first'); return; }
		_ensureSkinName();
		var isMusic = clip.trackId == 'music';
		var fd = new FileDialog();
		fd.onSelect.add(function(path:String) {
			var fileName = haxe.io.Path.withoutDirectory(path);
			var ok = isMusic
				? DialogueData.copyMusicToSkin(path, currentSkinName, fileName)
				: DialogueData.copySoundToSkin(path, currentSkinName, fileName);
			if (ok) {
				if (_inspAudioFileInput != null) _inspAudioFileInput.text = fileName;
				clip.soundFile = fileName;
				_rebuildClips();
				_showStatus('Imported "${fileName}" → ${isMusic ? "music" : "sounds"}/ folder  (click APPLY to confirm)');
			} else {
				_showStatus('Error copying audio file — check permissions');
			}
		});
		fd.browse(lime.ui.FileDialogType.OPEN, 'mp3,ogg,wav,flac', null, 'Select Audio File');
		#else
		_showStatus('File dialog not available on this platform');
		#end
	}

	/**
	 * Import a music file into the skin's music/ folder (from asset panel button).
	 * Adds it as a new clip on the MUSIC track at the current playhead.
	 */
	function _doImportMusic():Void {
		_closeMenus();
		#if sys
		_ensureSkinName();
		var fd = new FileDialog();
		fd.onSelect.add(function(path:String) {
			var fileName = haxe.io.Path.withoutDirectory(path);
			if (!DialogueData.copyMusicToSkin(path, currentSkinName, fileName)) {
				_showStatus('Error copying music file — check permissions'); return;
			}
			// Add a clip on the music track at the playhead position
			var id = 'music_${++_uid}';
			var clip:DLGClipData = {
				id: id, trackId: 'music',
				startSlot: _previewMsgIdx, duration: 4.0,
				soundFile: fileName, volume: 1.0, loop: true
			};
			_pushUndo();
			clips.push(clip);
			_rebuildClips();
			_selectClip(id);
			_switchMode('timeline');
			_showStatus('Music "${fileName}" imported + added to MUSIC track at slot ${_previewMsgIdx + 1}');
		});
		fd.browse(lime.ui.FileDialogType.OPEN, 'mp3,ogg,wav,flac', null, 'Select Music File');
		#else
		_showStatus('File dialog not available on this platform');
		#end
	}

	/**
	 * Import a sound effect into the skin's sounds/ folder (from asset panel button).
	 * Adds it as a new clip on the SOUND FX track at the current playhead.
	 */
	function _doImportSound():Void {
		_closeMenus();
		#if sys
		_ensureSkinName();
		var fd = new FileDialog();
		fd.onSelect.add(function(path:String) {
			var fileName = haxe.io.Path.withoutDirectory(path);
			if (!DialogueData.copySoundToSkin(path, currentSkinName, fileName)) {
				_showStatus('Error copying sound file — check permissions'); return;
			}
			var id = 'sound_${++_uid}';
			var clip:DLGClipData = {
				id: id, trackId: 'sound',
				startSlot: _previewMsgIdx, duration: 1.0,
				soundFile: fileName, volume: 1.0, loop: false
			};
			_pushUndo();
			clips.push(clip);
			_rebuildClips();
			_selectClip(id);
			_switchMode('timeline');
			_showStatus('Sound FX "${fileName}" imported + added to SOUND FX track at slot ${_previewMsgIdx + 1}');
		});
		fd.browse(lime.ui.FileDialogType.OPEN, 'mp3,ogg,wav,flac', null, 'Select Sound Effect');
		#else
		_showStatus('File dialog not available on this platform');
		#end
	}

	function _doRemoveSelected():Void {
		_closeMenus();
		if (_selectedElementIdx < 0 || _selectedElementIdx >= _canvasElements.length) return;
		_pushUndo();
		var el = _canvasElements[_selectedElementIdx];
		if (el.type == 'portrait') currentSkin?.portraits.remove(el.key);
		else if (el.type == 'box') currentSkin?.boxes.remove(el.key);
		else if (el.type == 'background') currentSkin?.backgrounds?.remove(el.key);
		else if (el.type == 'overlay') currentSkin?.overlays?.remove(el.key);
		_selectedElementIdx = -1;
		hasUnsaved = true;
		_rebuildCanvasSprites();
		_showStatus('Removed element: ${el.key}  (Ctrl+Z to undo)');
	}

	function _doAddTrack():Void {
		_pushUndo();
		var idx = tracks.length;
		var customCount = 0;
		for (t in tracks) if (t.id.startsWith('custom')) customCount++;
		var typeChoices  = ['sprite', 'sfx', 'background', 'custom'];
		var colorChoices:Array<Int> = [0xFF66AAFF, 0xFFAA66FF, 0xFFFF9933, 0xFF55EEAA, 0xFFFFCC44];
		var newType = typeChoices[customCount % typeChoices.length];
		tracks.push({
			id:      'custom$idx',
			name:    '${newType.toUpperCase()} ${customCount + 1}',
			type:    newType,
			color:   colorChoices[customCount % colorChoices.length],
			visible: true,
			locked:  false,
			height:  TL_TRACK_H
		});
		if (idx >= _trackScrollY + 6) _trackScrollY = idx - 5;
		var availH  = SH - HEADER_H - SPLITTER_H - STATUS_H;
		var visN    = Std.int(Math.min(tracks.length, 6));
		var neededH = TL_RULER_H + visN * TL_TRACK_H + TL_SCRUB_H + 12;
		if (_vpHeight > availH - neededH)
			_vpHeight = Std.int(Math.max(MIN_VP_H, availH - neededH));
		_rebuildTimeline();
		hasUnsaved = true;
		_showStatus('Track "${tracks[idx].name}" added — dblClick to add clips  (${tracks.length} tracks total)');
	}

	function _doRemoveTrack(trackIdx:Int):Void {
		if (trackIdx < 0 || trackIdx >= tracks.length) return;
		var coreIds = ['dialogue', 'portrait', 'background', 'music'];
		if (coreIds.indexOf(tracks[trackIdx].id) >= 0) {
			_showStatus('Cannot remove core track "${tracks[trackIdx].name}" — only custom tracks removable');
			return;
		}
		_pushUndo();
		var removedId = tracks[trackIdx].id;
		tracks.splice(trackIdx, 1);
		clips = clips.filter(c -> c.trackId != removedId);
		if (_trackScrollY > 0 && _trackScrollY >= tracks.length) _trackScrollY--;
		_rebuildTimeline();
		hasUnsaved = true;
		_showStatus('Track removed  (Ctrl+Z to undo)');
	}

	function _doImportSkin():Void {
		_closeMenus();
		var skins = DialogueData.getAvailableSkins();
		if (skins.length == 0) { _showStatus('No skins available to import'); return; }
		var skinName = skins[0];
		var skin = DialogueData.loadSkin(skinName);
		if (skin != null) {
			currentSkin = skin;
			currentSkinName = skinName;
			if (conversation != null) conversation.skinName = skinName;
			_rebuildCanvasSprites();
			_refreshSkinInspectorFields();
			_updateConvInfoText();
			_showStatus('Imported skin: $skinName');
		}
	}

	function _doUndo():Void {
		if (_undoStack.length == 0) { _showStatus('Nothing to undo'); return; }
		var snap = _undoStack.pop();
		var cur = Json.stringify({ conv: conversation, clips: clips, skin: _skinSnap(), skinName: currentSkinName });
		_redoStack.push(cur);
		var state = Json.parse(snap);
		conversation = state.conv;
		clips = state.clips ?? [];
		if (state.skinName != null) currentSkinName = state.skinName;
		if (state.skin != null) { _applySkinSnap(state.skin); _rebuildCanvasSprites(); }
		_syncClipsFromConversation();
		_refreshInspector();
		_updateConvInfoText();
		_showStatus('Undo');
	}

	function _doRedo():Void {
		if (_redoStack.length == 0) { _showStatus('Nothing to redo'); return; }
		var snap = _redoStack.pop();
		var cur = Json.stringify({ conv: conversation, clips: clips, skin: _skinSnap(), skinName: currentSkinName });
		_undoStack.push(cur);
		var state = Json.parse(snap);
		conversation = state.conv;
		clips = state.clips ?? [];
		if (state.skinName != null) currentSkinName = state.skinName;
		if (state.skin != null) { _applySkinSnap(state.skin); _rebuildCanvasSprites(); }
		_syncClipsFromConversation();
		_refreshInspector();
		_updateConvInfoText();
		_showStatus('Redo');
	}

	function _doBack():Void {
		_closeMenus();
		if (hasUnsaved && _unsavedDlg == null) {
			_unsavedDlg = new UnsavedChangesDialog([camHUD]);
			_unsavedDlg.onSaveAndExit = () -> {
				_doSave();
				StateTransition.switchState(new funkin.debug.EditorHubState());
			};
			_unsavedDlg.onSave = () -> {
				_doSave();
				remove(_unsavedDlg);
				_unsavedDlg = null;
			};
			_unsavedDlg.onExit = () -> {
				StateTransition.switchState(new funkin.debug.EditorHubState());
			};
			add(_unsavedDlg);
		} else {
			StateTransition.switchState(new funkin.debug.EditorHubState());
		}
	}

	function _showHelp():Void {
		_closeMenus();
		_showStatus('Controls: SCENE/TIMELINE toggle | Ctrl+S save | Ctrl+Z undo | Ctrl+Y redo | Scroll=zoom | DblClick=add clip | ESC=back');
	}

	function _closeMenus():Void {
		for (dd in _menuDropdowns) { remove(dd); dd.destroy(); }
		_menuDropdowns = [];
		_activeMenu = -1;
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  OS DRAG-AND-DROP  (files dragged from file manager onto the window)
	// ═════════════════════════════════════════════════════════════════════════

	/**
	 * Called by Lime when the user drops one or more files onto the window.
	 * Determines the file type and either acts immediately (JSON / unique type)
	 * or shows a chooser overlay so the user picks how to import it.
	 */
	function _onDropFile(path:String):Void {
		_closeMenus();
		_pendingDropPath = path;
		var ext = haxe.io.Path.extension(path).toLowerCase();
		var name = haxe.io.Path.withoutDirectory(path);

		if (['png', 'jpg', 'jpeg', 'gif', 'webp'].indexOf(ext) >= 0) {
			_showDropChooser(
				['PORTRAIT', 'BOX', 'BACKGROUND', 'OVERLAY'],
				['portrait', 'box', 'background', 'overlay'],
				['◆', '■', '▣', '◈'],
				[C_ACCENT, C_ACCENT3, 0xFFFF9933, 0xFF88CC55],
				name
			);
		} else if (['mp3', 'ogg', 'wav', 'flac'].indexOf(ext) >= 0) {
			_showDropChooser(
				['MUSIC', 'SOUND FX'],
				['music', 'sound'],
				['♪', '▶'],
				[0xFF00E894, 0xFFFFCC44],
				name
			);
		} else if (ext == 'json') {
			_tryDropJson(path);
		} else {
			_showStatus('Cannot import .$ext — supported: png/jpg/gif/webp, mp3/ogg/wav/flac, json');
		}
	}

	/**
	 * Show a centred modal overlay letting the user pick how to import the
	 * dropped file.  Each button calls _doDropImport() with its type string.
	 */
	function _showDropChooser(
		labels:Array<String>, types:Array<String>,
		icons:Array<String>,  colors:Array<Int>,
		fileName:String
	):Void {
		_closeDropOverlay();

		var ov = new FlxGroup();
		_dropOverlay = ov;

		// Semi-transparent full-screen dim
		var dim = new FlxSprite(0, 0).makeGraphic(SW, SH, 0xCC050510);
		dim.scrollFactor.set(); dim.cameras = [camUI];
		ov.add(dim);

		// Panel geometry
		var panW = 340;
		var btnH = 32;
		var panH = 56 + labels.length * (btnH + 6) + btnH + 16;
		var panX = Std.int((SW - panW) / 2);
		var panY = Std.int((SH - panH) / 2);

		// Panel background
		var pan = new FlxSprite(panX, panY).makeGraphic(panW, panH, C_PANEL);
		flixel.util.FlxSpriteUtil.drawRect(pan, 0, 0,      panW, 1,     C_ACCENT);
		flixel.util.FlxSpriteUtil.drawRect(pan, 0, panH-1, panW, 1,     C_ACCENT);
		flixel.util.FlxSpriteUtil.drawRect(pan, 0, 0,      1,    panH,  C_ACCENT);
		flixel.util.FlxSpriteUtil.drawRect(pan, panW-1, 0, 1,    panH,  C_ACCENT);
		pan.scrollFactor.set(); pan.cameras = [camUI];
		ov.add(pan);

		// Header row
		var headerBg = new FlxSprite(panX, panY).makeGraphic(panW, 32, 0xFF0A0A18);
		headerBg.scrollFactor.set(); headerBg.cameras = [camUI];
		ov.add(headerBg);

		var hdrLbl = new FlxText(panX + 10, panY + 9, panW - 20, 'Import  "$fileName"  as:', 10);
		hdrLbl.setFormat(Paths.font('vcr.ttf'), 10, C_ACCENT, LEFT);
		hdrLbl.scrollFactor.set(); hdrLbl.cameras = [camUI];
		ov.add(hdrLbl);

		// Type buttons
		for (i in 0...labels.length) {
			var bx = panX + 16;
			var by = panY + 40 + i * (btnH + 6);
			var bw = panW - 32;
			var col = colors[i];

			var btn = new DLGBtn(bx, by, bw, btnH, '${icons[i]}  ${labels[i]}', col, C_BG, null);
			btn.scrollFactor.set(); btn.cameras = [camUI]; btn.label.cameras = [camUI];
			var captType = types[i];
			btn.onClick = () -> { _closeDropOverlay(); _doDropImport(_pendingDropPath, captType); };
			ov.add(btn); ov.add(btn.label);
		}

		// Cancel button
		var cy = panY + 40 + labels.length * (btnH + 6) + 4;
		var cancelBtn = new DLGBtn(panX + 16, cy, panW - 32, btnH, '✕  CANCEL', 0xFF1A1A2E, 0xFFFF4444, _closeDropOverlay);
		cancelBtn.scrollFactor.set(); cancelBtn.cameras = [camUI]; cancelBtn.label.cameras = [camUI];
		ov.add(cancelBtn); ov.add(cancelBtn.label);

		add(ov);
		_showStatus('Dropped "${haxe.io.Path.withoutDirectory(_pendingDropPath)}" — pick type to import');
	}

	function _closeDropOverlay():Void {
		if (_dropOverlay == null) return;
		remove(_dropOverlay);
		_dropOverlay.destroy();
		_dropOverlay = null;
	}

	/**
	 * Execute the actual file copy + skin update once the user has chosen the
	 * asset type in the drop chooser.
	 */
	function _doDropImport(path:String, type:String):Void {
		_ensureSkinName();
		var fileName = haxe.io.Path.withoutDirectory(path);
		var baseKey  = haxe.io.Path.withoutExtension(fileName);

		// Unique-key helper
		var makeKey = (base:String, exists:String->Bool) -> {
			var k = base; var n = 1;
			while (exists(k)) k = '${base}_$n'; n++;
			return k;
		};

		switch (type) {
			// ── Image types ──────────────────────────────────────────────────
			case 'portrait':
				var key = makeKey(baseKey, k -> currentSkin.portraits.exists(k));
				_pushUndo();
				if (DialogueData.copyPortraitToSkin(path, currentSkinName, fileName)) {
					currentSkin.portraits.set(key, DialogueData.createPortraitConfig(key, fileName));
					hasUnsaved = true; _rebuildCanvasSprites();
					_showStatus('Portrait "$key" imported — visible in Scene Builder & Timeline panel');
				} else { _undoStack.pop(); _showStatus('Error copying portrait — check permissions'); }

			case 'box':
				var key = makeKey(baseKey, k -> currentSkin.boxes.exists(k));
				_pushUndo();
				if (DialogueData.copyBoxToSkin(path, currentSkinName, fileName)) {
					currentSkin.boxes.set(key, DialogueData.createBoxConfig(key, fileName));
					hasUnsaved = true; _rebuildCanvasSprites();
					_showStatus('Box "$key" imported — drag it from the asset panel onto the timeline');
				} else { _undoStack.pop(); _showStatus('Error copying box — check permissions'); }

			case 'background':
				if (currentSkin.backgrounds == null) currentSkin.backgrounds = new Map();
				var key = makeKey(baseKey, k -> currentSkin.backgrounds.exists(k));
				_pushUndo();
				if (DialogueData.copyBackgroundToSkin(path, currentSkinName, fileName)) {
					currentSkin.backgrounds.set(key, DialogueData.createBackgroundConfig(key, fileName));
					hasUnsaved = true; _rebuildCanvasSprites();
					_showStatus('Background "$key" imported');
				} else { _undoStack.pop(); _showStatus('Error copying background'); }

			case 'overlay':
				if (currentSkin.overlays == null) currentSkin.overlays = new Map();
				var key = makeKey(baseKey, k -> currentSkin.overlays.exists(k));
				_pushUndo();
				if (DialogueData.copyOverlayToSkin(path, currentSkinName, fileName)) {
					var oc = DialogueData.createBackgroundConfig(key, fileName);
					oc.alpha = 0.8;
					currentSkin.overlays.set(key, oc);
					hasUnsaved = true; _rebuildCanvasSprites();
					_showStatus('Overlay "$key" imported');
				} else { _undoStack.pop(); _showStatus('Error copying overlay'); }

			// ── Audio types ───────────────────────────────────────────────────
			case 'music':
				if (DialogueData.copyMusicToSkin(path, currentSkinName, fileName)) {
					var id = 'music_${++_uid}';
					var clip:DLGClipData = {
						id: id, trackId: 'music',
						startSlot: _previewMsgIdx, duration: 4.0,
						soundFile: fileName, volume: 1.0, loop: true
					};
					_pushUndo();
					clips.push(clip);
					_rebuildClips();
					_selectClip(id);
					if (_mode != 'timeline') _switchMode('timeline') else _rebuildTimelineAssets();
					_showStatus('Music "$fileName" imported + placed on MUSIC track at slot ${_previewMsgIdx + 1}');
				} else { _showStatus('Error copying music — check permissions'); }

			case 'sound':
				if (DialogueData.copySoundToSkin(path, currentSkinName, fileName)) {
					var id = 'sound_${++_uid}';
					var clip:DLGClipData = {
						id: id, trackId: 'sound',
						startSlot: _previewMsgIdx, duration: 1.0,
						soundFile: fileName, volume: 1.0, loop: false
					};
					_pushUndo();
					clips.push(clip);
					_rebuildClips();
					_selectClip(id);
					if (_mode != 'timeline') _switchMode('timeline') else _rebuildTimelineAssets();
					_showStatus('Sound "$fileName" imported + placed on SOUND FX track at slot ${_previewMsgIdx + 1}');
				} else { _showStatus('Error copying sound — check permissions'); }
		}
	}

	/**
	 * Handle a dropped JSON file — auto-detect whether it's a skin config
	 * or a conversation file and import accordingly.
	 */
	function _tryDropJson(path:String):Void {
		#if sys
		try {
			var content = sys.io.File.getContent(path);
			var data    = haxe.Json.parse(content);

			if (data.portraits != null) {
				// Es un config.json de skin — cargarlo directamente
				// FIX: antes solo mostraba un mensaje de error; ahora carga la skin real.
				var skinDir  = haxe.io.Path.directory(path);
				var skinName = haxe.io.Path.withoutDirectory(skinDir);
				var skin = DialogueData.loadSkin(skinName);
				if (skin != null) {
					_pushUndo();
					currentSkinName = skinName;
					currentSkin = skin;
					_selectedElementIdx = -1;
					_rebuildCanvasSprites();
					_refreshSkinInspectorFields();
					_updateConvInfoText();
					if (_mode != 'scene') _switchMode('scene');
					_showStatus('Skin cargada: $skinName');
				} else {
					_showStatus('No se pudo cargar la skin. Asegúrate de que config.json esté en assets/cutscenes/dialogue/<nombre>/config.json');
				}
			} else if (data.messages != null) {
				// Es una conversación
				// FIX: antes no cargaba la skin ni cambiaba de modo → no se veía nada.
				_pushUndo();
				conversation = cast data;
				// Auto-cargar la skin referenciada en la conversación
				if (conversation.skinName != null && conversation.skinName != '') {
					var skin = DialogueData.loadSkin(conversation.skinName);
					if (skin != null) {
						currentSkinName = conversation.skinName;
						currentSkin = skin;
						_rebuildCanvasSprites();
						_refreshSkinInspectorFields();
					}
				}
				_syncClipsFromConversation();
				_updateConvInfoText();
				// Cambiar al modo timeline donde se ven los clips de diálogo
				if (_mode != 'timeline') _switchMode('timeline');
				else { _rebuildTimeline(); _rebuildTimelineAssets(); }
				_showStatus('Conversación importada (${conversation.messages.length} mensajes)  |  skin: ${conversation.skinName ?? "ninguna"}');
			} else {
				_showStatus('JSON no reconocido — se esperaba un config de skin o un archivo de conversación');
			}
		} catch (e:Dynamic) {
			_showStatus('Error reading JSON: $e');
		}
		#end
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  DESTROY
	// ═════════════════════════════════════════════════════════════════════════

	override public function destroy():Void {
		#if sys
		if (_windowCloseFn != null)
			lime.app.Application.current.window.onClose.remove(_windowCloseFn);
		lime.app.Application.current.window.onDropFile.remove(_onDropFile);
		#end
		_closeDropOverlay();
		DLGBtn.onTooltip = null;
		super.destroy();
	}
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DLGBtn  — simple icon/text button (mirrors PSEBtn)
// ═══════════════════════════════════════════════════════════════════════════════
private class DLGBtn extends FlxSprite {
	public var label:FlxText;
	public var onClick:Void->Void;
	/** Texto de tooltip que se muestra en la barra de estado al hacer hover. */
	public var tooltip:String = '';
	/** Callback global que el editor registra para mostrar tooltips. */
	public static var onTooltip:Null<String->Void> = null;

	public var _base:Int;
	var _hover:Int;
	var _over:Bool = false;
	var _btnW:Int;
	var _btnH:Int;

	public function new(x:Float, y:Float, w:Int, h:Int, lbl:String, col:Int, txtCol:Int, ?cb:Void->Void) {
		super(x, y);
		_base  = col;
		_hover = _lighten(col, 22);
		_btnW  = w;
		_btnH  = h;
		onClick = cb;
		_drawBtn(col);
		label = new FlxText(x, y + (h - 10) / 2, w, lbl, 9);
		label.setFormat(Paths.font('vcr.ttf'), 9, txtCol, CENTER);
		label.scrollFactor.set();
	}

	/** Draws the button body with a 1-px bevel border so it's always visible. */
	public function _drawBtn(col:Int):Void {
		makeGraphic(_btnW, _btnH, col, true);
		// Top + left highlight edge
		var hi = _lighten(col, 22);
		flixel.util.FlxSpriteUtil.drawRect(this, 0, 0,          _btnW, 1,     hi);
		flixel.util.FlxSpriteUtil.drawRect(this, 0, 0,          1,     _btnH, hi);
		// Bottom + right shadow edge
		var sh = _darken(col, 28);
		flixel.util.FlxSpriteUtil.drawRect(this, 0,        _btnH - 1, _btnW, 1,     sh);
		flixel.util.FlxSpriteUtil.drawRect(this, _btnW - 1, 0,        1,     _btnH, sh);
	}

	override private function set_cameras(c:Array<flixel.FlxCamera>):Array<flixel.FlxCamera> {
		if (label != null) label.cameras = c;
		return super.set_cameras(c);
	}

	override public function update(elapsed:Float):Void {
		super.update(elapsed);
		if (alive && exists && visible) _updateInput();
	}

	function _updateInput():Void {
		var cam = (cameras != null && cameras.length > 0) ? cameras[0] : FlxG.camera;
		var ov = FlxG.mouse.overlaps(this, cam);
		if (ov != _over) {
			_drawBtn(ov ? _hover : _base);
			_over = ov;
			// Mostrar / limpiar tooltip en la barra de estado
			if (onTooltip != null)
				onTooltip(ov && tooltip != '' ? tooltip : '');
		}
		label.x = x; label.y = y + (height - label.height) / 2;
		if (ov && FlxG.mouse.justPressed && onClick != null) onClick();
	}

	static function _lighten(c:Int, a:Int):Int {
		var r = (c >> 16) & 0xFF;
		var g = (c >> 8) & 0xFF;
		var b = c & 0xFF;
		var f = a / 100.0;
		return ((c >> 24) & 0xFF) << 24
			| Std.int(Math.min(255, r + (255 - r) * f)) << 16
			| Std.int(Math.min(255, g + (255 - g) * f)) << 8
			| Std.int(Math.min(255, b + (255 - b) * f));
	}

	static function _darken(c:Int, a:Int):Int {
		var r = (c >> 16) & 0xFF;
		var g = (c >> 8) & 0xFF;
		var b = c & 0xFF;
		var f = (100 - a) / 100.0;
		return ((c >> 24) & 0xFF) << 24
			| Std.int(r * f) << 16
			| Std.int(g * f) << 8
			| Std.int(b * f);
	}
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DLGMenuBtn  — menu bar item
// ═══════════════════════════════════════════════════════════════════════════════
private class DLGMenuBtn extends FlxSprite {
	public var label:FlxText;

	var _base:Int;
	var _hover:Int;
	var _over:Bool = false;
	var _idx:Int;
	var _cb:Int->Float->Void;

	public function new(x:Float, y:Float, text:String, base:Int, hover:Int, txtCol:Int, idx:Int, cb:Int->Float->Void) {
		super(x, y);
		var w = text.length * 7 + 14;
		makeGraphic(w, 22, base);
		_base = base; _hover = hover; _idx = idx; _cb = cb;
		label = new FlxText(x + 6, y + 5, w - 12, text, 9);
		label.setFormat(Paths.font('vcr.ttf'), 9, txtCol, LEFT);
		label.scrollFactor.set();
	}

	override private function set_cameras(c:Array<flixel.FlxCamera>):Array<flixel.FlxCamera> {
		if (label != null) label.cameras = c;
		return super.set_cameras(c);
	}

	override public function update(e:Float):Void {
		super.update(e);
		if (!alive || !exists || !visible) return;
		var cam = (cameras != null && cameras.length > 0) ? cameras[0] : FlxG.camera;
		var ov = FlxG.mouse.overlaps(this, cam);
		if (ov != _over) { makeGraphic(Std.int(width), Std.int(height), ov ? _hover : _base); _over = ov; }
		label.x = x + 6; label.y = y + 5;
		if (ov && FlxG.mouse.justPressed && _cb != null) _cb(_idx, x);
	}
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DLGDropdownPanel  — menu dropdown (mirrors PSEDropdownPanel)
// ═══════════════════════════════════════════════════════════════════════════════
private class DLGDropdownPanel extends FlxGroup {
	var _bg:FlxSprite;
	var _btns:Array<FlxSprite> = [];
	var _txts:Array<FlxText>   = [];
	var _cbs:Array<Void->Void>  = [];

	static inline final ITEM_H:Int    = 22;
	static inline final C_PANEL:Int   = 0xFF1A1A2E;
	static inline final C_HOVER:Int   = 0xFF282842;
	static inline final C_BORDER:Int  = 0xFF343454;
	static inline final C_TEXT:Int    = 0xFFCCCCEE;
	static inline final C_SEP:Int     = 0xFF2E2E4E;

	public function new(x:Float, y:Float, w:Int, items:Array<{label:String, cb:Void->Void, sep:Bool}>) {
		super();
		var h = items.length * ITEM_H + 2;
		_bg = new FlxSprite(x, y).makeGraphic(w, h, C_PANEL);
		flixel.util.FlxSpriteUtil.drawRect(_bg, 0, 0, w, 1, C_BORDER);
		flixel.util.FlxSpriteUtil.drawRect(_bg, 0, h - 1, w, 1, C_BORDER);
		flixel.util.FlxSpriteUtil.drawRect(_bg, 0, 0, 1, h, C_BORDER);
		flixel.util.FlxSpriteUtil.drawRect(_bg, w - 1, 0, 1, h, C_BORDER);
		add(_bg);

		for (i in 0...items.length) {
			var item = items[i];
			var iy = y + i * ITEM_H + 1;
			if (item.sep) {
				var sep = new FlxSprite(x + 4, iy + ITEM_H / 2).makeGraphic(w - 8, 1, C_SEP);
				sep.alpha = 0.5; add(sep);
				_btns.push(null); _txts.push(null); _cbs.push(null);
				continue;
			}
			var btn = new FlxSprite(x, iy).makeGraphic(w, ITEM_H, C_PANEL);
			add(btn); _btns.push(btn);
			var txt = new FlxText(x + 10, iy + 5, w - 20, item.label, 9);
			txt.setFormat(Paths.font('vcr.ttf'), 9, C_TEXT, LEFT);
			add(txt); _txts.push(txt);
			_cbs.push(item.cb);
		}
	}

	override private function set_cameras(c:Array<flixel.FlxCamera>):Array<flixel.FlxCamera> {
		for (m in members) if (m != null) m.cameras = c;
		return super.set_cameras(c);
	}

	override public function update(e:Float):Void {
		super.update(e);
		for (i in 0...Std.int(Math.min(_btns.length, _cbs.length))) {
			var btn = _btns[i]; if (btn == null) continue;
			var cam = (cameras != null && cameras.length > 0) ? cameras[0] : FlxG.camera;
			var ov = FlxG.mouse.overlaps(btn, cam);
			btn.makeGraphic(Std.int(btn.width), Std.int(btn.height), ov ? C_HOVER : C_PANEL);
			if (ov && FlxG.mouse.justPressed && _cbs[i] != null) _cbs[i]();
		}
	}
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DLGClipBlock  — colored rectangular clip on the timeline (mirrors PSEEventBlock)
// ═══════════════════════════════════════════════════════════════════════════════
private class DLGClipBlock extends FlxSprite {
	public var clipId:String;
	public var lblTxt:FlxText;

	public function new(x:Float, y:Float, w:Int, h:Int, col:Int, id:String, selected:Bool) {
		super(x, y);
		clipId = id;
		makeGraphic(Std.int(Math.max(6, w)), h, col, true);
		// Top highlight edge
		flixel.util.FlxSpriteUtil.drawRect(this, 0, 0, Std.int(Math.max(6, w)), 2, _lighten(col, 25));
		// Bottom dark edge
		flixel.util.FlxSpriteUtil.drawRect(this, 0, h - 1, Std.int(Math.max(6, w)), 1, _darken(col, 30));
		// Resize handle on right edge
		flixel.util.FlxSpriteUtil.drawRect(this, Std.int(Math.max(6, w)) - 4, 1, 3, h - 2, _lighten(col, 35));

		if (selected) {
			flixel.util.FlxSpriteUtil.drawRect(this, 0, 0, 1, h, FlxColor.WHITE);
			flixel.util.FlxSpriteUtil.drawRect(this, Std.int(Math.max(6, w)) - 1, 0, 1, h, FlxColor.WHITE);
			flixel.util.FlxSpriteUtil.drawRect(this, 0, 0, Std.int(Math.max(6, w)), 2, FlxColor.WHITE);
		}
		alpha = selected ? 1.0 : 0.85;

		lblTxt = new FlxText(x + 4, y + 3, Std.int(Math.max(10, w - 8)), '', 8);
		lblTxt.setFormat(Paths.font('vcr.ttf'), 8, 0xFFE0E0F0, LEFT);
		lblTxt.scrollFactor.set();
	}

	override private function set_cameras(c:Array<flixel.FlxCamera>):Array<flixel.FlxCamera> {
		if (lblTxt != null) lblTxt.cameras = c;
		return super.set_cameras(c);
	}

	static function _lighten(c:Int, a:Int):Int {
		var r = (c >> 16) & 0xFF; var g = (c >> 8) & 0xFF; var b = c & 0xFF;
		var f = a / 100.0;
		return 0xFF000000 | Std.int(Math.min(255, r + (255 - r) * f)) << 16
			| Std.int(Math.min(255, g + (255 - g) * f)) << 8
			| Std.int(Math.min(255, b + (255 - b) * f));
	}

	static function _darken(c:Int, a:Int):Int {
		var r = (c >> 16) & 0xFF; var g = (c >> 8) & 0xFF; var b = c & 0xFF;
		var f = (100 - a) / 100.0;
		return 0xFF000000 | Std.int(r * f) << 16 | Std.int(g * f) << 8 | Std.int(b * f);
	}
}
