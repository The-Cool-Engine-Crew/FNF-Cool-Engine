package funkin.debug.editors;

import coolui.CoolCheckBox;
import coolui.CoolDropDown;
import coolui.CoolInputText;
import coolui.CoolNumericStepper;
import coolui.CoolTabMenu;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.input.keyboard.FlxKey;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import coolui.CoolButton;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import funkin.gameplay.notes.NoteSkinSystem;
import funkin.gameplay.notes.NoteSkinSystem.NoteHoldCoverData;
import funkin.gameplay.notes.NoteSkinSystem.NoteSkinData;
import funkin.gameplay.notes.NoteSkinSystem.NoteSkinTexture;
import funkin.gameplay.notes.NoteSkinSystem.NoteSplashData;
import funkin.gameplay.notes.NoteSkinSystem.SkinAnimEntry;
import funkin.states.MusicBeatState;
import haxe.Json;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import openfl.net.FileReference;
#if sys
import lime.ui.FileDialog;
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/**
 * NoteSkinEditorState — Visual editor for Note Skins, Splashes and Hold Covers.
 *
 * ─── Modes ───────────────────────────────────────────────────────────────────
 *   NOTE SKIN  — edits skin.json    (NoteSkinData)
 *   SPLASH     — edits splash.json  (NoteSplashData)
 *   HOLD COVER — edits the holdCover block inside splash.json (NoteHoldCoverData)
 *
 * ─── Tabs ────────────────────────────────────────────────────────────────────
 *   Info       — name, author, description, texture path & type
 *   Textures   — extra textures (hold, notes-only, strums-only)
 *   Animations — animList editor (new format: name/prefix/fps/offsets/loop/flipX)
 *   Preview    — live sprite preview, offset drag
 *   Export     — JSON generation & file save / clipboard copy
 *
 * ─── Controls ────────────────────────────────────────────────────────────────
 *   W / S            — switch selected animation in list
 *   ARROWS           — nudge offset (SHIFT = ×10)
 *   RIGHT-DRAG       — drag offset on preview sprite
 *   SCROLL / I J K L — camera zoom & pan
 *   SPACE            — replay animation
 *   ESC              — back to Editor Hub
 */
class NoteSkinEditorState extends MusicBeatState {
	// ── Cameras ───────────────────────────────────────────────────────────────
	var camGame:FlxCamera;
	var camHUD:FlxCamera;
	var camUI:FlxCamera;

	// ── UI ────────────────────────────────────────────────────────────────────
	var UI_box:CoolTabMenu;
	var uiPanelBg:FlxSprite;
	var leftPanel:FlxSprite;
	var headerBg:FlxSprite;
	var headerText:FlxText;
	var statusBar:FlxSprite;
	var statusAccentBar:FlxSprite;
	var statusText:FlxText;
	var animRowHighlight:FlxSprite;
	var dumbTexts:FlxTypedGroup<FlxText>;

	static inline var PANEL_HIDDEN_X:Float = 1600;

	// ── Mode ─────────────────────────────────────────────────────────────────

	/** 0 = Note Skin, 1 = Splash, 2 = Hold Cover */
	var editorMode:Int = 0;

	static inline var MODE_SKIN:Int = 0;
	static inline var MODE_SPLASH:Int = 1;
	static inline var MODE_HOLDCOVER:Int = 2;

	// ── Preview sprite ────────────────────────────────────────────────────────
	var previewSprite:FlxSprite;
	var gridBG:FlxSprite;
	var camFollow:FlxObject;

	// ── Animation list (left panel) ───────────────────────────────────────────
	var animEntries:Array<SkinAnimEntry> = [];
	var curAnimIdx:Int = 0;

	// ── Drag offset ───────────────────────────────────────────────────────────
	var isDragging:Bool = false;
	var dragLastX:Float = 0;
	var dragLastY:Float = 0;

	// ── Data being edited ─────────────────────────────────────────────────────
	// Note Skin
	var skinData:NoteSkinData;
	// Splash (wraps both splash + holdCover)
	var splashData:NoteSplashData;

	// ── File reference ────────────────────────────────────────────────────────
	var _file:FileReference;

	// ── Unsaved changes ───────────────────────────────────────────────────────
	var _hasUnsaved:Bool = false;

	// ── Info tab ──────────────────────────────────────────────────────────────
	var nameInput:CoolInputText;
	var authorInput:CoolInputText;
	var descInput:CoolInputText;

	// ── Textures tab ─────────────────────────────────────────────────────────
	// Main texture
	var texPathInput:CoolInputText;
	var texTypeDropdown:CoolDropDown;
	var _texType:String = "sparrow";

	/** Absolute path of the browsed main texture PNG (sys only). */
	var _texAbsPath:String = null;

	var _texAtlasAbsPath:String = null;
	var texScaleStepper:CoolNumericStepper;
	var texAntialiasingCheckbox:CoolCheckBox;
	// Hold texture (skin only)
	var holdTexPathInput:CoolInputText;
	var holdTexTypeDropdown:CoolDropDown;
	var _holdTexType:String = "sparrow";

	/** Absolute path of the browsed hold texture PNG (sys only). */
	var _holdTexAbsPath:String = null;

	var _holdTexAtlasAbsPath:String = null;
	var holdTexScaleStepper:CoolNumericStepper;
	// Notes-only texture
	var notesTexPathInput:CoolInputText;
	// Strums-only texture
	var strumsTexPathInput:CoolInputText;

	// ── Skin flags tab ────────────────────────────────────────────────────────
	var isPixelCheckbox:CoolCheckBox;
	var confirmOffsetCheckbox:CoolCheckBox;
	var colorAutoCheckbox:CoolCheckBox;
	var colorMultStepper:CoolNumericStepper;
	var sustainOffsetStepper:CoolNumericStepper;
	var holdStretchStepper:CoolNumericStepper;

	// ── Splash tab fields ─────────────────────────────────────────────────────
	var splashOffsetXStepper:CoolNumericStepper;
	var splashOffsetYStepper:CoolNumericStepper;
	var splashScaleStepper:CoolNumericStepper;
	var splashAntialiasingCheckbox:CoolCheckBox;

	// ── Hold Cover tab fields ─────────────────────────────────────────────────
	var hcTexturePrefix:CoolInputText;
	var hcPerColorCheckbox:CoolCheckBox;
	var hcTextureTypeDropdown:CoolDropDown;
	var _hcTextureType:String = "sparrow";
	var hcScaleStepper:CoolNumericStepper;
	var hcFramerateStepper:CoolNumericStepper;
	var hcLoopFramerateStepper:CoolNumericStepper;
	var hcOffsetXStepper:CoolNumericStepper;
	var hcOffsetYStepper:CoolNumericStepper;
	var hcStartPrefixInput:CoolInputText;
	var hcLoopPrefixInput:CoolInputText;
	var hcEndPrefixInput:CoolInputText;

	// ── Animation tab fields ──────────────────────────────────────────────────
	var animNameInput:CoolInputText;
	var animPrefixInput:CoolInputText;
	var animFpsStepper:CoolNumericStepper;
	var animLoopCheckbox:CoolCheckBox;
	var animFlipXCheckbox:CoolCheckBox;
	var animFlipYCheckbox:CoolCheckBox;
	var animOffsetXStepper:CoolNumericStepper;
	var animOffsetYStepper:CoolNumericStepper;
	var animNoteIDDropdown:CoolDropDown;
	var addAnimBtn:CoolButton;

	/** Currently selected noteID from the dropdown (0-based dir, or -1 = all). */
	var _selectedNoteID:Int = -1;

	/** null = Add mode, String = Edit mode */
	var editingAnimIdx:Int = -1;

	// ── Play Preview ──────────────────────────────────────────────────────────
	var _playPreviewActive:Bool = false;
	var _playStrums:Array<FlxSprite> = [];
	var _activeNotes:Array<{spr:FlxSprite, dir:Int, hit:Bool}> = [];
	var _noteScrollSpeed:Float = 450.0;
	var _downscroll:Bool = false;
	var _previewPlayBtn:CoolButton;
	var _previewHintText:FlxText;
	var _noteSpeedStepper:CoolNumericStepper;
	var _downscrollCheckbox:CoolCheckBox;

	// Candidate animation names per direction (tried in order)
	static final _NOTE_ANIMS = [
		["left", "left0", "purpleScroll", "noteLeft", "note0"],
		["down", "down0", "blueScroll", "noteDown", "note1"],
		["up", "up0", "greenScroll", "noteUp", "note2"],
		["right", "right0", "redScroll", "noteRight", "note3"]
	];
	static final _STRUM_STATIC_ANIMS = [
		["strumLeft", "leftStatic", "static0", "static"],
		["strumDown", "downStatic", "static1", "static"],
		["strumUp", "upStatic", "static2", "static"],
		["strumRight", "rightStatic", "static3", "static"]
	];
	static final _STRUM_CONFIRM_ANIMS = [
		["strumLeftConfirm", "leftConfirm", "confirm0", "confirm"],
		["strumDownConfirm", "downConfirm", "confirm1", "confirm"],
		["strumUpConfirm", "upConfirm", "confirm2", "confirm"],
		["strumRightConfirm", "rightConfirm", "confirm3", "confirm"]
	];
	static final _STRUM_PRESS_ANIMS = [
		["strumLeftPress", "leftPress", "pressed0", "pressed"],
		["strumDownPress", "downPress", "pressed1", "pressed"],
		["strumUpPress", "upPress", "pressed2", "pressed"],
		["strumRightPress", "rightPress", "pressed3", "pressed"]
	];
	static final _HOLD_ANIMS = [
		["leftHold", "lefthold", "purplehold", "holdLeft", "hold0"],
		["downHold", "downhold", "bluehold", "holdDown", "hold1"],
		["upHold", "uphold", "greenhold", "holdUp", "hold2"],
		["rightHold", "righthold", "redhold", "holdRight", "hold3"]
	];
	static final _TAIL_ANIMS = [
		["leftHoldEnd", "leftTail", "purpleholdend", "tailLeft", "tail0"],
		["downHoldEnd", "downTail", "blueholdend", "tailDown", "tail1"],
		["upHoldEnd", "upTail", "greenholdend", "tailUp", "tail2"],
		["rightHoldEnd", "rightTail", "redholdend", "tailRight", "tail3"]
	];
	static final _DIR_COLORS:Array<Int> = [0xFFCC44FF, 0xFF44CCFF, 0xFF44FF88, 0xFFFF5555];

	// ── Static showcase sprites (always visible in the playfield) ─────────────
	var _showcaseStrums:Array<FlxSprite> = [];
	var _showcaseNotes:Array<FlxSprite> = [];
	var _showcaseHolds:Array<FlxSprite> = [];
	var _showcaseTails:Array<FlxSprite> = [];
	var _showcaseSplash:FlxSprite = null;
	var _showcaseHoldCover:FlxSprite = null;

	// ── Showcase visibility toggles ─────────────────────────────────────────
	var _showStrums:Bool = true;
	var _showNotes:Bool = true;
	var _showHolds:Bool = true;
	var _showSplash:Bool = true;
	var _showHoldCover:Bool = true;

	// ─────────────────────────────────────────────────────────────────────────

	public function new() {
		super();
	}

	override function create() {
		funkin.debug.themes.EditorTheme.load();
		funkin.system.CursorManager.show();
		funkin.audio.MusicManager.play('configurator', 0.7);

		// ── Cameras ───────────────────────────────────────────────────────────
		camUI = new FlxCamera();
		camUI.bgColor = funkin.debug.themes.EditorTheme.current.bgDark;
		camGame = new FlxCamera();
		camGame.bgColor = funkin.debug.themes.EditorTheme.current.bgDark;
		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;

		FlxG.cameras.reset(camUI);
		FlxG.cameras.add(camGame, false);
		FlxG.cameras.add(camHUD, false);

		// ── Grid background ───────────────────────────────────────────────────
		gridBG = flixel.addons.display.FlxGridOverlay.create(32, 32, 640, 480);
		gridBG.scrollFactor.set(0.5, 0.5);
		gridBG.cameras = [camGame];
		gridBG.alpha = 0.08;
		add(gridBG);

		// ── Preview sprite ────────────────────────────────────────────────────
		previewSprite = new FlxSprite(0, 0);
		previewSprite.cameras = [camGame];
		previewSprite.visible = false;
		add(previewSprite);

		// ── Camera follow ─────────────────────────────────────────────────────
		camFollow = new FlxObject(0, 0, 2, 2);
		camFollow.screenCenter();
		add(camFollow);
		camGame.follow(camFollow, LOCKON, 0.08);

		// ── Build data stubs ──────────────────────────────────────────────────
		_buildDefaultSkinData();
		_buildDefaultSplashData();

		// ── UI ────────────────────────────────────────────────────────────────
		_setupUI();

		// ── Left panel + animation list ───────────────────────────────────────
		_setupLeftPanel();

		// ── Status bar ────────────────────────────────────────────────────────
		statusBar = new FlxSprite(0, FlxG.height - 30);
		statusBar.makeGraphic(FlxG.width, 30, (funkin.debug.themes.EditorTheme.current.bgDark & 0x00FFFFFF) | 0xDD000000);
		statusBar.cameras = [camHUD];
		statusBar.scrollFactor.set();
		add(statusBar);

		statusAccentBar = new FlxSprite(0, FlxG.height - 30);
		statusAccentBar.makeGraphic(4, 30, funkin.debug.themes.EditorTheme.current.accent);
		statusAccentBar.cameras = [camHUD];
		statusAccentBar.scrollFactor.set();
		add(statusAccentBar);

		statusText = new FlxText(12, FlxG.height - 24, FlxG.width - 300, '', 11);
		statusText.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		statusText.color = funkin.debug.themes.EditorTheme.current.accent;
		statusText.cameras = [camHUD];
		statusText.scrollFactor.set();
		add(statusText);

		// Theme button
		var themeBtn = new CoolButton(FlxG.width - 75, FlxG.height - 28, '\u2728 Theme', function() {
			openSubState(new funkin.debug.themes.ThemePickerSubState());
		});
		themeBtn.cameras = [camHUD];
		themeBtn.scrollFactor.set();
		add(themeBtn);

		// ── Slide-in animation ────────────────────────────────────────────────
		UI_box.x = PANEL_HIDDEN_X;
		uiPanelBg.x = PANEL_HIDDEN_X - 4;
		FlxTween.tween(UI_box, {x: FlxG.width - UI_box.width - 10}, 0.4, {ease: FlxEase.quartOut});
		FlxTween.tween(uiPanelBg, {x: FlxG.width - UI_box.width - 14}, 0.4, {ease: FlxEase.quartOut});

		leftPanel.alpha = 0;
		FlxTween.tween(leftPanel, {alpha: 1}, 0.4, {ease: FlxEase.quartOut, startDelay: 0.1});

		// ── Load Default skin/splash from game data on startup ────────────
		// Do this after the full UI is built so _populateUIFromSkinData() can
		// write into the input fields. Falls back to the hardcoded stubs if
		// the Default skin is not registered yet (e.g. assets not loaded).
		if (NoteSkinSystem.availableSkins.exists("Default")) {
			_loadSkinFromGame("Default");
			_setStatus("Loaded Default skin. Ready to edit!", 0xFF44FF88);
		} else {
			_setStatus("Welcome to the Note Skin Editor! Select a mode and start editing.", 0xFF00D9FF);
			_refreshAnimList();
		}

		if (NoteSkinSystem.availableSplashes.exists("Default"))
			_loadSplashFromGame("Default");

		// Restore skin mode after the splash preload — _loadSplashFromGame sets
		// editorMode=MODE_SPLASH which would break _applyLegacyAnimsToSpr in the showcase.
		if (NoteSkinSystem.availableSkins.exists("Default"))
			editorMode = MODE_SKIN;

		// ── Auto-build the showcase with the default skin texture ──────────
		new FlxTimer().start(0.05, function(_) {
			_buildShowcase();
		});

		funkin.transitions.StateTransition.onStateCreated();
	}

	// ─────────────────────────────────────────────────────────────── DEFAULT DATA

	function _buildDefaultSkinData() {
		skinData = {
			name: "Default",
			author: "",
			description: "",
			texture: {
				path: "NOTE_assets",
				type: "sparrow",
				scale: 1.0,
				antialiasing: true
			},
			isPixel: false,
			confirmOffset: true,
			sustainOffset: 0.0,
			holdStretch: 1.0,
			animations: {},
			animList: []
		};
	}

	function _buildDefaultSplashData() {
		splashData = {
			name: "My Splash",
			author: "",
			assets: {
				path: "noteSplashes",
				scale: 1.0,
				antialiasing: true,
				offset: [0, 0]
			},
			animations: {all: ["note impact 1", "note impact 2"]},
			animList: [],
			holdCover: {
				perColorTextures: true,
				texturePrefix: "holdCover",
				textureType: "sparrow",
				scale: 1.0,
				antialiasing: true,
				framerate: 24,
				loopFramerate: 48,
				offset: null,
				startPrefix: "holdCoverStart",
				loopPrefix: "holdCover",
				endPrefix: "holdCoverEnd",
				animList: []
			}
		};
	}

	// ─────────────────────────────────────────────────────────────── UI SETUP

	function _setupUI() {
		var tabs = [
			{name: "Mode", label: "Mode & Info"},
			{name: "Tex", label: "Textures"},
			{name: "Flags", label: "Flags"},
			{name: "Anims", label: "Animations"},
			{name: "Export", label: "Export"}
		];

		UI_box = new CoolTabMenu(null, tabs, true);
		UI_box.cameras = [camHUD];
		UI_box.resize(340, 490);
		UI_box.x = FlxG.width - UI_box.width - 10;
		UI_box.y = 10;

		uiPanelBg = new FlxSprite(UI_box.x - 4, UI_box.y - 4);
		uiPanelBg.makeGraphic(Std.int(UI_box.width) + 8, Std.int(UI_box.height) + 8,
			(funkin.debug.themes.EditorTheme.current.bgDark & 0x00FFFFFF) | 0xDD000000);
		uiPanelBg.cameras = [camHUD];
		add(uiPanelBg);
		add(UI_box);

		_addModeInfoTab();
		_addTexturesTab();
		_addFlagsTab();
		_addAnimationsTab();
		_addExportTab();
	}

	// ── Left panel & animation list ───────────────────────────────────────────

	function _setupLeftPanel() {
		leftPanel = new FlxSprite(0, 0);
		leftPanel.makeGraphic(350, FlxG.height, (funkin.debug.themes.EditorTheme.current.bgPanel & 0x00FFFFFF) | 0xCC000000);
		leftPanel.cameras = [camHUD];
		leftPanel.scrollFactor.set();
		add(leftPanel);

		var border = new FlxSprite(350, 0);
		border.makeGraphic(2, FlxG.height, funkin.debug.themes.EditorTheme.current.accent);
		border.cameras = [camHUD];
		border.scrollFactor.set();
		add(border);

		// Header
		headerBg = new FlxSprite(0, 0);
		headerBg.makeGraphic(350, 38, funkin.debug.themes.EditorTheme.current.accent);
		headerBg.cameras = [camHUD];
		headerBg.scrollFactor.set();
		add(headerBg);

		headerText = new FlxText(8, 7, 336, 'NOTE SKIN EDITOR', 16);
		headerText.font = "VCR OSD Mono";
		headerText.color = funkin.debug.themes.EditorTheme.current.bgDark;
		headerText.cameras = [camHUD];
		headerText.scrollFactor.set();
		add(headerText);

		// Controls hint
		var hint = new FlxText(8, 42, 336,
			"W/S = Anim  ARROWS = Offset (SHIFT x10)\nSPACE = Play  SCROLL = Zoom  ESC = Exit\nRIGHT-DRAG = Move Offset  I/J/K/L = Camera", 9);
		hint.color = funkin.debug.themes.EditorTheme.current.textSecondary;
		hint.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		hint.cameras = [camHUD];
		hint.scrollFactor.set();
		add(hint);

		// ── Play Preview strip ────────────────────────────────────────────────
		var ppSep = new FlxSprite(0, 88);
		ppSep.makeGraphic(352, 1, 0x33FFFFFF);
		ppSep.cameras = [camHUD];
		ppSep.scrollFactor.set();
		add(ppSep);

		_previewPlayBtn = new CoolButton(6, 93, "\u25B6 Play Preview", _togglePlayPreview);
		_previewPlayBtn.cameras = [camHUD];
		_previewPlayBtn.scrollFactor.set();
		add(_previewPlayBtn);

		var speedLbl = new FlxText(175, 97, 45, "Speed:", 9);
		speedLbl.color = funkin.debug.themes.EditorTheme.current.textSecondary;
		speedLbl.cameras = [camHUD];
		speedLbl.scrollFactor.set();
		add(speedLbl);

		_noteSpeedStepper = new CoolNumericStepper(222, 93, 50, 450, 100, 2000, 0);
		_noteSpeedStepper.cameras = [camHUD];
		_noteSpeedStepper.scrollFactor.set();
		add(_noteSpeedStepper);

		_downscrollCheckbox = new CoolCheckBox(6, 116, null, null, "Downscroll", 110);
		_downscrollCheckbox.cameras = [camHUD];
		_downscrollCheckbox.scrollFactor.set();
		_downscrollCheckbox.checked = false;
		add(_downscrollCheckbox);

		_previewHintText = new FlxText(120, 119, 228, "\u2190\u2193\u2191\u2192 = spawn notes  |  active", 9);
		_previewHintText.color = funkin.debug.themes.EditorTheme.current.accent;
		_previewHintText.cameras = [camHUD];
		_previewHintText.scrollFactor.set();
		_previewHintText.visible = false;
		add(_previewHintText);

		var ppSep2 = new FlxSprite(0, 138);
		ppSep2.makeGraphic(352, 1, 0x33FFFFFF);
		ppSep2.cameras = [camHUD];
		ppSep2.scrollFactor.set();
		add(ppSep2);

		// ── Showcase visibility checkboxes ──────────────────────────────────────
		var showLbl = new FlxText(6, 143, 40, "Show:", 9);
		showLbl.color = funkin.debug.themes.EditorTheme.current.textSecondary;
		showLbl.cameras = [camHUD];
		showLbl.scrollFactor.set();
		add(showLbl);

		var cbStrums = new CoolCheckBox(46, 141, null, function(v:Bool) {
			_showStrums = v;
			for (s in _showcaseStrums)
				s.visible = v;
		}, "Strums", 70);
		cbStrums.checked = true;
		cbStrums.cameras = [camHUD];
		cbStrums.scrollFactor.set();
		add(cbStrums);

		var cbNotes = new CoolCheckBox(120, 141, null, function(v:Bool) {
			_showNotes = v;
			for (s in _showcaseNotes)
				s.visible = v;
		}, "Notes", 65);
		cbNotes.checked = true;
		cbNotes.cameras = [camHUD];
		cbNotes.scrollFactor.set();
		add(cbNotes);

		var cbHolds = new CoolCheckBox(190, 141, null, function(v:Bool) {
			_showHolds = v;
			for (s in _showcaseHolds)
				s.visible = v;
			for (s in _showcaseTails)
				s.visible = v;
		}, "Holds", 65);
		cbHolds.checked = true;
		cbHolds.cameras = [camHUD];
		cbHolds.scrollFactor.set();
		add(cbHolds);

		var cbSplash = new CoolCheckBox(258, 141, null, function(v:Bool) {
			_showSplash = v;
			if (_showcaseSplash != null)
				_showcaseSplash.visible = v;
		}, "Splash", 70);
		cbSplash.checked = true;
		cbSplash.cameras = [camHUD];
		cbSplash.scrollFactor.set();
		add(cbSplash);

		var cbHC = new CoolCheckBox(46, 159, null, function(v:Bool) {
			_showHoldCover = v;
			if (_showcaseHoldCover != null)
				_showcaseHoldCover.visible = v;
		}, "Hold Cover", 100);
		cbHC.checked = true;
		cbHC.cameras = [camHUD];
		cbHC.scrollFactor.set();
		add(cbHC);

		var ppSep3 = new FlxSprite(0, 178);
		ppSep3.makeGraphic(352, 1, 0x33FFFFFF);
		ppSep3.cameras = [camHUD];
		ppSep3.scrollFactor.set();
		add(ppSep3);

		// Animation list highlight bar
		animRowHighlight = new FlxSprite(4, 0);
		animRowHighlight.makeGraphic(342, 18, (funkin.debug.themes.EditorTheme.current.accent & 0x00FFFFFF) | 0x44000000);
		animRowHighlight.cameras = [camHUD];
		animRowHighlight.scrollFactor.set();
		animRowHighlight.visible = false;
		add(animRowHighlight);

		// Animation list text group
		dumbTexts = new FlxTypedGroup<FlxText>();
		dumbTexts.cameras = [camHUD];
		add(dumbTexts);
	}

	// ─────────────────────────────────────────────── TAB: Mode & Info

	function _addModeInfoTab() {
		var tab = new coolui.CoolUIGroup();
		tab.name = "Mode";
		var y = 10;

		// ── Editor Mode selector ──────────────────────────────────────────────
		tab.add(_label(10, y, "Editor Mode:"));
		y += 14;

		var modeOptions = CoolDropDown.makeStrIdLabelArray(["Note Skin (skin.json)", "Splash (splash.json)", "Hold Cover (in splash.json)"], true);
		var modeDD = new CoolDropDown(10, y, modeOptions, function(id:String) {
			editorMode = Std.parseInt(id);
			_onModeChanged();
		});
		modeDD.selectedLabel = "Note Skin (skin.json)";
		tab.add(modeDD);
		y += 35;

		// Divider
		tab.add(_divider(10, y, "─── Info"));
		y += 16;

		// Name
		tab.add(_label(10, y, "Name:"));
		y += 14;
		nameInput = new CoolInputText(10, y, 300, 'Default', 9);
		tab.add(nameInput);
		y += 26;

		// Author
		tab.add(_label(10, y, "Author:"));
		y += 14;
		authorInput = new CoolInputText(10, y, 300, '', 9);
		tab.add(authorInput);
		y += 26;

		// Description
		tab.add(_label(10, y, "Description:"));
		y += 14;
		descInput = new CoolInputText(10, y, 300, '', 9);
		tab.add(descInput);
		y += 30;

		// ── Quick Load ────────────────────────────────────────────────────────
		tab.add(_divider(10, y, "─── Load Existing"));
		y += 16;

		var availableSkins:Array<String> = [for (k in NoteSkinSystem.availableSkins.keys()) k];
		if (availableSkins.length > 0) {
			tab.add(_label(10, y, "Load skin from game:"));
			y += 14;
			var skinDD = new CoolDropDown(10, y, CoolDropDown.makeStrIdLabelArray(availableSkins, true), function(id:String) {
				var idx = Std.parseInt(id);
				_loadSkinFromGame(availableSkins[idx]);
			});
			skinDD.selectedLabel = availableSkins[0];
			tab.add(skinDD);
			y += 35;
		}

		var availableSplashes:Array<String> = [for (k in NoteSkinSystem.availableSplashes.keys()) k];
		if (availableSplashes.length > 0) {
			tab.add(_label(10, y, "Load splash from game:"));
			y += 14;
			var splashDD = new CoolDropDown(10, y, CoolDropDown.makeStrIdLabelArray(availableSplashes, true), function(id:String) {
				var idx = Std.parseInt(id);
				_loadSplashFromGame(availableSplashes[idx]);
			});
			splashDD.selectedLabel = availableSplashes[0];
			tab.add(splashDD);
			y += 35;
		}

		// Load JSON from file
		tab.add(new CoolButton(10, y, "Load JSON from File", function() {
			_loadJSONFromFile();
		}));
		y += 28;

		UI_box.addGroup(tab);
	}

	// ─────────────────────────────────────────────── TAB: Textures

	function _addTexturesTab() {
		var tab = new coolui.CoolUIGroup();
		tab.name = "Tex";
		var y = 10;
		var texTypes = CoolDropDown.makeStrIdLabelArray(["sparrow", "packer", "image", "funkinsprite"], true);

		// ── Main Texture ──────────────────────────────────────────────────────
		tab.add(_divider(10, y, "─── Main Texture"));
		y += 16;

		tab.add(_label(10, y, "Path (no extension):"));
		y += 14;
		texPathInput = new CoolInputText(10, y, 218, 'NOTE_assets', 8);
		tab.add(texPathInput);
		tab.add(new CoolButton(232, y - 2, "Browse…", function() {
			_browseTexturePNG(function(png, atlas) {
				_texAbsPath = png;
				_texAtlasAbsPath = atlas;
				// Suggest relative path (filename without extension)
				var base = png.replace("\\", "/");
				var slash = base.lastIndexOf("/");
				var name = slash >= 0 ? base.substr(slash + 1) : base;
				if (name.endsWith(".png"))
					name = name.substr(0, name.length - 4);
				texPathInput.text = name;
				_setStatus('Texture selected: $name  (atlas: ${atlas != null ? "found" : "none"})', 0xFF44FF88);
			}, true);
		}));
		y += 22;

		tab.add(_label(10, y, "Type:"));
		y += 14;
		texTypeDropdown = new CoolDropDown(10, y, texTypes, function(_) {
			_texType = texTypeDropdown.selectedLabel;
		});
		texTypeDropdown.selectedLabel = "sparrow";
		tab.add(texTypeDropdown);
		y += 30;

		tab.add(_label(10, y, "Scale:"));
		texScaleStepper = new CoolNumericStepper(80, y, 0.1, 1.0, 0.1, 10.0, 1);
		tab.add(texScaleStepper);
		texAntialiasingCheckbox = new CoolCheckBox(170, y, null, null, "Antialiasing", 140);
		texAntialiasingCheckbox.checked = true;
		tab.add(texAntialiasingCheckbox);
		y += 28;

		// ── Hold Texture (Note Skin only) ─────────────────────────────────────
		tab.add(_divider(10, y, "─── Hold Texture (skin only)"));
		y += 16;
		tab.add(_hint(10, y, "Leave empty to inherit from main texture"));
		y += 14;

		tab.add(_label(10, y, "Hold Path:"));
		y += 14;
		holdTexPathInput = new CoolInputText(10, y, 218, '', 8);
		tab.add(holdTexPathInput);
		tab.add(new CoolButton(232, y - 2, "Browse…", function() {
			_browseTexturePNG(function(png, atlas) {
				_holdTexAbsPath = png;
				_holdTexAtlasAbsPath = atlas;
				var base = png.replace("\\", "/");
				var slash = base.lastIndexOf("/");
				var name = slash >= 0 ? base.substr(slash + 1) : base;
				if (name.endsWith(".png"))
					name = name.substr(0, name.length - 4);
				holdTexPathInput.text = name;
				_setStatus('Hold texture selected: $name', 0xFF44FF88);
			}, false);
		}));
		y += 22;

		tab.add(_label(10, y, "Type:"));
		y += 14;
		holdTexTypeDropdown = new CoolDropDown(10, y, texTypes, function(_) {
			_holdTexType = holdTexTypeDropdown.selectedLabel;
		});
		holdTexTypeDropdown.selectedLabel = "sparrow";
		tab.add(holdTexTypeDropdown);
		y += 30;

		tab.add(_label(10, y, "Scale:"));
		holdTexScaleStepper = new CoolNumericStepper(80, y, 0.1, 1.0, 0.1, 10.0, 1);
		tab.add(holdTexScaleStepper);
		y += 28;

		// ── Notes-only / Strums-only ──────────────────────────────────────────
		tab.add(_divider(10, y, "─── Notes / Strums Separate (skin only)"));
		y += 16;

		tab.add(_label(10, y, "Notes-only path:"));
		y += 14;
		notesTexPathInput = new CoolInputText(10, y, 300, '', 8);
		tab.add(notesTexPathInput);
		y += 22;

		tab.add(_label(10, y, "Strums-only path:"));
		y += 14;
		strumsTexPathInput = new CoolInputText(10, y, 300, '', 8);
		tab.add(strumsTexPathInput);
		y += 22;

		// ── Splash Assets ─────────────────────────────────────────────────────
		tab.add(_divider(10, y, "─── Splash Assets"));
		y += 16;
		tab.add(_label(10, y, "Splash Path:"));
		y += 14;
		// (reuses texPathInput from main — populated on mode switch)

		tab.add(_label(10, y, "Splash Scale:"));
		splashScaleStepper = new CoolNumericStepper(80, y, 0.1, 1.0, 0.1, 10.0, 1);
		tab.add(splashScaleStepper);
		splashAntialiasingCheckbox = new CoolCheckBox(170, y, null, null, "Antialiasing", 140);
		splashAntialiasingCheckbox.checked = true;
		tab.add(splashAntialiasingCheckbox);
		y += 26;

		tab.add(_label(10, y, "Splash Offset X:"));
		splashOffsetXStepper = new CoolNumericStepper(120, y, 1, 0, -500, 500, 0);
		tab.add(splashOffsetXStepper);
		y += 22;
		tab.add(_label(10, y, "Splash Offset Y:"));
		splashOffsetYStepper = new CoolNumericStepper(120, y, 1, 0, -500, 500, 0);
		tab.add(splashOffsetYStepper);

		UI_box.addGroup(tab);
	}

	// ─────────────────────────────────────────────── TAB: Flags

	function _addFlagsTab() {
		var tab = new coolui.CoolUIGroup();
		tab.name = "Flags";
		var y = 10;

		// ── Note Skin Flags ───────────────────────────────────────────────────
		tab.add(_divider(10, y, "─── Note Skin Flags"));
		y += 16;

		isPixelCheckbox = new CoolCheckBox(10, y, null, null, "isPixel (disable antialiasing)", 290);
		isPixelCheckbox.checked = false;
		tab.add(isPixelCheckbox);
		y += 22;

		confirmOffsetCheckbox = new CoolCheckBox(10, y, null, null, "confirmOffset (apply -13,-13 on confirms)", 290);
		confirmOffsetCheckbox.checked = true;
		tab.add(confirmOffsetCheckbox);
		y += 26;

		tab.add(_label(10, y, "sustainOffset (X shift on holds):"));
		sustainOffsetStepper = new CoolNumericStepper(200, y, 1, 0, -100, 200, 0);
		tab.add(sustainOffsetStepper);
		y += 24;

		tab.add(_label(10, y, "holdStretch (scale.y multiplier):"));
		holdStretchStepper = new CoolNumericStepper(200, y, 0.01, 1.0, 0.1, 5.0, 2);
		tab.add(holdStretchStepper);
		y += 30;

		// ── Color / RGB ───────────────────────────────────────────────────────
		tab.add(_divider(10, y, "─── Auto Color (RGB Shader)"));
		y += 16;

		colorAutoCheckbox = new CoolCheckBox(10, y, null, null, "colorAuto (apply RGB color preset)", 290);
		colorAutoCheckbox.checked = false;
		tab.add(colorAutoCheckbox);
		y += 22;

		tab.add(_label(10, y, "colorMult (0.0 – 1.0):"));
		colorMultStepper = new CoolNumericStepper(160, y, 0.05, 1.0, 0.0, 1.0, 2);
		tab.add(colorMultStepper);
		y += 30;

		tab.add(_hint(10, y,
			"colorAuto: tints notes with standard FNF colors\n" + "(L=purple D=cyan U=green R=red) using a shader.\n" +
			"Useful for grayscale NOTE_assets sprites."));
		y += 44;

		// ── Hold Cover Settings ───────────────────────────────────────────────
		tab.add(_divider(10, y, "─── Hold Cover (in splash.json)"));
		y += 16;

		hcPerColorCheckbox = new CoolCheckBox(10, y, null, null, "perColorTextures (one texture per direction)", 290);
		hcPerColorCheckbox.checked = true;
		tab.add(hcPerColorCheckbox);
		y += 22;

		tab.add(_label(10, y, "texturePrefix:"));
		hcTexturePrefix = new CoolInputText(100, y, 190, 'holdCover', 8);
		tab.add(hcTexturePrefix);
		y += 22;

		var hcTexTypes = CoolDropDown.makeStrIdLabelArray(["sparrow", "packer"], true);
		tab.add(_label(10, y, "textureType:"));
		hcTextureTypeDropdown = new CoolDropDown(100, y, hcTexTypes, function(_) {
			_hcTextureType = hcTextureTypeDropdown.selectedLabel;
		});
		hcTextureTypeDropdown.selectedLabel = "sparrow";
		tab.add(hcTextureTypeDropdown);
		y += 30;

		tab.add(_label(10, y, "scale:"));
		hcScaleStepper = new CoolNumericStepper(60, y, 0.1, 1.0, 0.1, 10.0, 1);
		tab.add(hcScaleStepper);
		y += 22;

		tab.add(_label(10, y, "framerate (start/end):"));
		hcFramerateStepper = new CoolNumericStepper(150, y, 1, 24, 1, 120, 0);
		tab.add(hcFramerateStepper);
		y += 22;

		tab.add(_label(10, y, "loopFramerate:"));
		hcLoopFramerateStepper = new CoolNumericStepper(110, y, 1, 48, 1, 120, 0);
		tab.add(hcLoopFramerateStepper);
		y += 22;

		tab.add(_label(10, y, "offset X:"));
		hcOffsetXStepper = new CoolNumericStepper(75, y, 1, 0, -999, 999, 0);
		tab.add(hcOffsetXStepper);
		y += 20;
		tab.add(_label(10, y, "offset Y:"));
		hcOffsetYStepper = new CoolNumericStepper(75, y, 1, 0, -999, 999, 0);
		tab.add(hcOffsetYStepper);
		y += 22;

		tab.add(_label(10, y, "startPrefix:"));
		hcStartPrefixInput = new CoolInputText(90, y, 210, 'holdCoverStart', 8);
		tab.add(hcStartPrefixInput);
		y += 20;

		tab.add(_label(10, y, "loopPrefix:"));
		hcLoopPrefixInput = new CoolInputText(90, y, 210, 'holdCover', 8);
		tab.add(hcLoopPrefixInput);
		y += 20;

		tab.add(_label(10, y, "endPrefix:"));
		hcEndPrefixInput = new CoolInputText(90, y, 210, 'holdCoverEnd', 8);
		tab.add(hcEndPrefixInput);

		UI_box.addGroup(tab);
	}

	// ─────────────────────────────────────────────── TAB: Animations

	function _addAnimationsTab() {
		var tab = new coolui.CoolUIGroup();
		tab.name = "Anims";
		var y = 10;

		tab.add(_divider(10, y, "─── animList Entry (new format)"));
		y += 16;
		tab.add(_hint(10, y,
			"animList entries override the old animations:{} field.\n" + "Use name patterns like: left, down, up, right,\n" +
			"leftHold, purpleScroll, left_0, all_0 etc."));
		y += 46;

		// Name
		tab.add(_label(10, y, "name (internal ID):"));
		y += 14;
		animNameInput = new CoolInputText(10, y, 300, '', 8);
		tab.add(animNameInput);
		y += 24;

		// Prefix
		tab.add(_label(10, y, "prefix (atlas prefix):"));
		y += 14;
		animPrefixInput = new CoolInputText(10, y, 300, '', 8);
		tab.add(animPrefixInput);
		y += 24;

		// FPS
		tab.add(_label(10, y, "fps:"));
		animFpsStepper = new CoolNumericStepper(50, y, 1, 24, 1, 120, 0);
		tab.add(animFpsStepper);
		y += 24;

		// Flags row
		animLoopCheckbox = new CoolCheckBox(10, y, null, null, "loop", 90);
		animLoopCheckbox.checked = false;
		tab.add(animLoopCheckbox);

		animFlipXCheckbox = new CoolCheckBox(110, y, null, null, "flipX", 80);
		animFlipXCheckbox.checked = false;
		tab.add(animFlipXCheckbox);

		animFlipYCheckbox = new CoolCheckBox(200, y, null, null, "flipY", 80);
		animFlipYCheckbox.checked = false;
		tab.add(animFlipYCheckbox);
		y += 24;

		// Offsets
		tab.add(_label(10, y, "offset X:"));
		animOffsetXStepper = new CoolNumericStepper(75, y, 1, 0, -500, 500, 0);
		tab.add(animOffsetXStepper);
		tab.add(_label(160, y, "offset Y:"));
		animOffsetYStepper = new CoolNumericStepper(225, y, 1, 0, -500, 500, 0);
		tab.add(animOffsetYStepper);
		y += 24;

		// noteID (for strum animations)
		tab.add(_label(10, y, "noteID (strums only):"));
		y += 14;
		var noteIDOpts = CoolDropDown.makeStrIdLabelArray(["none (all dirs)", "0 - Left", "1 - Down", "2 - Up", "3 - Right"], true);
		animNoteIDDropdown = new CoolDropDown(10, y, noteIDOpts, function(id:String) {
			var idx = Std.parseInt(id);
			_selectedNoteID = (idx != null && idx > 0) ? idx - 1 : -1;
		});
		animNoteIDDropdown.selectedLabel = "none (all dirs)";
		tab.add(animNoteIDDropdown);
		y += 32;

		// Buttons row
		addAnimBtn = new CoolButton(10, y, "Add Animation", function() {
			_addOrUpdateAnimation();
		});
		tab.add(addAnimBtn);

		tab.add(new CoolButton(120, y, "New / Clear", function() {
			_clearAnimFields();
		}));
		y += 28;

		tab.add(new CoolButton(10, y, "Delete Selected", function() {
			_deleteSelectedAnimation();
		}));

		tab.add(new CoolButton(120, y, "← Load Selected", function() {
			_loadAnimIntoUI();
		}));
		y += 28;

		tab.add(new CoolButton(10, y, "▲ Move Up", function() {
			_moveAnimation(-1);
		}));

		tab.add(new CoolButton(120, y, "▼ Move Down", function() {
			_moveAnimation(1);
		}));
		y += 28;

		// Play current anim on preview
		tab.add(new CoolButton(10, y, "▶ Play on Preview", function() {
			_playSelectedAnimOnPreview();
		}));

		UI_box.addGroup(tab);
	}

	// ─────────────────────────────────────────────── TAB: Export

	function _addExportTab() {
		var tab = new coolui.CoolUIGroup();
		tab.name = "Export";
		var y = 10;

		tab.add(_divider(10, y, "─── Generate & Save JSON"));
		y += 16;

		tab.add(_hint(10, y,
			"Saves the current data as a skin.json or splash.json.\n"
			+ "Place it in:\n"
			+ "  assets/notes/skins/<skinName>/skin.json\n"
			+ "  assets/notes/splashes/<splashName>/splash.json"));
		y += 58;

		tab.add(new CoolButton(10, y, "Save skin.json", function() {
			_exportJSON("skin");
		}));
		y += 28;

		tab.add(new CoolButton(10, y, "Save splash.json", function() {
			_exportJSON("splash");
		}));
		y += 28;

		#if sys
		tab.add(new CoolButton(10, y, "📁 Save skin to folder…", function() {
			_saveSkinToFolder();
		}));
		tab.add(_hint(10, y + 20, "Writes skin.json + copies texture files\nto a folder of your choice."));
		y += 54;
		#else
		y += 4;
		#end

		tab.add(new CoolButton(10, y, "Copy skin.json to Clipboard", function() {
			_copyToClipboard("skin");
		}));
		y += 28;

		tab.add(new CoolButton(10, y, "Copy splash.json to Clipboard", function() {
			_copyToClipboard("splash");
		}));
		y += 36;

		// ── Preview controls ──────────────────────────────────────────────────
		tab.add(_divider(10, y, "─── Preview Controls"));
		y += 16;

		tab.add(new CoolButton(10, y, "Reload Preview Sprite", function() {
			_reloadPreviewSprite();
		}));
		y += 28;

		tab.add(new CoolButton(10, y, "Reset Camera", function() {
			camFollow.setPosition(FlxG.width * 0.5, FlxG.height * 0.5);
			camGame.zoom = 1.0;
		}));
		y += 28;

		tab.add(new CoolButton(10, y, "Center Sprite", function() {
			if (previewSprite.visible)
				camFollow.setPosition(previewSprite.getMidpoint().x, previewSprite.getMidpoint().y);
		}));
		y += 36;

		// ── JSON Preview (read-only text) ─────────────────────────────────────
		tab.add(_divider(10, y, "─── JSON Preview (first 300 chars)"));
		y += 14;
		var jsonPreviewText = new FlxText(10, y, 310, '', 7);
		jsonPreviewText.color = funkin.debug.themes.EditorTheme.current.textSecondary;
		jsonPreviewText.wordWrap = true;

		tab.add(new CoolButton(10, y + 140, "Refresh Preview", function() {
			var j = (editorMode == MODE_SKIN) ? _buildSkinJSON() : _buildSplashJSON();
			var str = Json.stringify(j, null, '  ');
			jsonPreviewText.text = str.length > 300 ? str.substr(0, 300) + '...' : str;
		}));
		tab.add(jsonPreviewText);

		UI_box.addGroup(tab);
	}

	// ─────────────────────────────────────────────────────────────────── UPDATE

	override function update(elapsed:Float) {
		super.update(elapsed);

		// ── Keyboard navigation ───────────────────────────────────────────────
		if (!_isAnyInputFocused()) {
			// Camera pan (always available)
			var camSpd = 200 * elapsed;
			if (FlxG.keys.pressed.I)
				camFollow.y -= camSpd;
			if (FlxG.keys.pressed.K)
				camFollow.y += camSpd;
			if (FlxG.keys.pressed.J)
				camFollow.x -= camSpd;
			if (FlxG.keys.pressed.L)
				camFollow.x += camSpd;

			// Camera zoom (always available)
			if (FlxG.mouse.wheel != 0)
				camGame.zoom = Math.max(0.1, Math.min(10.0, camGame.zoom + FlxG.mouse.wheel * 0.1));

			if (_playPreviewActive) {
				// ── Play preview: arrow keys spawn notes ──────────────────────
				_updatePlayPreview(elapsed);
			} else {
				// ── Normal mode ───────────────────────────────────────────────
				// Cycle animations
				if (FlxG.keys.justPressed.W) {
					curAnimIdx = Std.int(Math.max(0, curAnimIdx - 1));
					_refreshAnimList();
					_playSelectedAnimOnPreview();
				}
				if (FlxG.keys.justPressed.S) {
					curAnimIdx = Std.int(Math.min(animEntries.length - 1, curAnimIdx + 1));
					_refreshAnimList();
					_playSelectedAnimOnPreview();
				}

				// Offset nudge
				if (previewSprite.visible && curAnimIdx >= 0 && curAnimIdx < animEntries.length) {
					var step = FlxG.keys.pressed.SHIFT ? 10.0 : 1.0;
					var changed = false;
					// Guard: offsets array may be null on legacy-format entries
					if (FlxG.keys.justPressed.LEFT || FlxG.keys.justPressed.RIGHT || FlxG.keys.justPressed.UP || FlxG.keys.justPressed.DOWN)
						if (animEntries[curAnimIdx].offsets == null)
							animEntries[curAnimIdx].offsets = [0.0, 0.0];
					if (FlxG.keys.justPressed.LEFT) {
						animEntries[curAnimIdx].offsets[0] -= step;
						changed = true;
					}
					if (FlxG.keys.justPressed.RIGHT) {
						animEntries[curAnimIdx].offsets[0] += step;
						changed = true;
					}
					if (FlxG.keys.justPressed.UP) {
						animEntries[curAnimIdx].offsets[1] -= step;
						changed = true;
					}
					if (FlxG.keys.justPressed.DOWN) {
						animEntries[curAnimIdx].offsets[1] += step;
						changed = true;
					}
					if (changed) {
						_applyPreviewOffset();
						_refreshAnimList();
						_markUnsaved();
					}
				}

				// Replay
				if (FlxG.keys.justPressed.SPACE)
					_playSelectedAnimOnPreview();
			}
		}

		// ── Right-click drag for offset ───────────────────────────────────────
		if (FlxG.mouse.justPressedRight) {
			isDragging = true;
			dragLastX = FlxG.mouse.x;
			dragLastY = FlxG.mouse.y;
		}
		if (FlxG.mouse.justReleasedRight)
			isDragging = false;

		if (isDragging && curAnimIdx >= 0 && curAnimIdx < animEntries.length) {
			var dx = FlxG.mouse.x - dragLastX;
			var dy = FlxG.mouse.y - dragLastY;
			dragLastX = FlxG.mouse.x;
			dragLastY = FlxG.mouse.y;
			if (animEntries[curAnimIdx].offsets == null)
				animEntries[curAnimIdx].offsets = [0.0, 0.0];
			animEntries[curAnimIdx].offsets[0] -= dx;
			animEntries[curAnimIdx].offsets[1] -= dy;
			_applyPreviewOffset();
			_refreshAnimList();
			_markUnsaved();
		}

		// ── ESC ───────────────────────────────────────────────────────────────
		if (FlxG.keys.justPressed.ESCAPE) {
			funkin.transitions.StateTransition.switchState(new funkin.debug.EditorHubState());
		}
	}

	// ─────────────────────────────────────────────────────────── ANIMATION LIST

	function _refreshAnimList() {
		dumbTexts.clear();

		// Current animation name header
		var curName = (animEntries.length > 0 && curAnimIdx < animEntries.length) ? animEntries[curAnimIdx].name : "—";

		var nameText = new FlxText(8, 220, 334, '► $curName', 16);
		nameText.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 2);
		nameText.color = funkin.debug.themes.EditorTheme.current.accent;
		nameText.cameras = [camHUD];
		nameText.scrollFactor.set();
		dumbTexts.add(nameText);

		// Offset of current anim
		if (curAnimIdx < animEntries.length) {
			var e = animEntries[curAnimIdx];
			var ox = e.offsets != null && e.offsets.length > 0 ? e.offsets[0] : 0.0;
			var oy = e.offsets != null && e.offsets.length > 1 ? e.offsets[1] : 0.0;
			var offsetInfo = new FlxText(8, 240, 334, 'Offset: $ox , $oy  |  fps: ${e.fps ?? 24}', 11);
			offsetInfo.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
			offsetInfo.color = funkin.debug.themes.EditorTheme.current.warning;
			offsetInfo.cameras = [camHUD];
			offsetInfo.scrollFactor.set();
			dumbTexts.add(offsetInfo);
		}

		// List of animations
		var listY = 262;
		var rowH = 18;
		for (i in 0...animEntries.length) {
			var e = animEntries[i];
			var ox = e.offsets != null && e.offsets.length > 0 ? e.offsets[0] : 0.0;
			var oy = e.offsets != null && e.offsets.length > 1 ? e.offsets[1] : 0.0;
			var txt = new FlxText(8, listY + i * rowH, 334, '${i == curAnimIdx ? "▶" : " "} ${e.name}  [$ox, $oy]  fps:${e.fps ?? 24}', 9);
			txt.color = i == curAnimIdx ? funkin.debug.themes.EditorTheme.current.accent : funkin.debug.themes.EditorTheme.current.textSecondary;
			txt.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
			txt.cameras = [camHUD];
			txt.scrollFactor.set();
			dumbTexts.add(txt);

			if (i == curAnimIdx) {
				animRowHighlight.y = listY + i * rowH - 1;
				animRowHighlight.visible = true;
			}
		}

		if (animEntries.length == 0)
			animRowHighlight.visible = false;
	}

	// ───────────────────────────────────────────────────────── ANIMATION FIELDS

	function _addOrUpdateAnimation() {
		var name = animNameInput.text.trim();
		var prefix = animPrefixInput.text.trim();

		if (name.length == 0 || prefix.length == 0) {
			_setStatus("Error: name and prefix are required.", FlxColor.RED);
			return;
		}

		var noteID:Null<Int> = _selectedNoteID >= 0 ? _selectedNoteID : null;

		var entry:SkinAnimEntry = {
			name: name,
			prefix: prefix,
			fps: Std.int(animFpsStepper.value),
			loop: animLoopCheckbox.checked,
			flipX: animFlipXCheckbox.checked,
			flipY: animFlipYCheckbox.checked,
			offsets: [animOffsetXStepper.value, animOffsetYStepper.value],
			noteID: noteID
		};

		if (editingAnimIdx >= 0 && editingAnimIdx < animEntries.length) {
			animEntries[editingAnimIdx] = entry;
			_setStatus('Updated animation: $name', 0xFF44FF88);
		} else {
			// Avoid duplicate names
			for (i in 0...animEntries.length)
				if (animEntries[i].name == name) {
					animEntries[i] = entry;
					_setStatus('Replaced: $name', 0xFFFFCC00);
					_refreshAnimList();
					_markUnsaved();
					return;
				}
			animEntries.push(entry);
			curAnimIdx = animEntries.length - 1;
			_setStatus('Added animation: $name', 0xFF44FF88);
		}

		editingAnimIdx = -1;
		addAnimBtn.label = "Add Animation";
		_refreshAnimList();
		_markUnsaved();
	}

	function _clearAnimFields() {
		editingAnimIdx = -1;
		addAnimBtn.label = "Add Animation";
		animNameInput.text = "";
		animPrefixInput.text = "";
		animFpsStepper.value = 24;
		animLoopCheckbox.checked = false;
		animFlipXCheckbox.checked = false;
		animFlipYCheckbox.checked = false;
		animOffsetXStepper.value = 0;
		animOffsetYStepper.value = 0;
		animNoteIDDropdown.selectedLabel = "none (all dirs)";
		_selectedNoteID = -1;
		_setStatus("Cleared — Add mode", FlxColor.CYAN);
	}

	function _loadAnimIntoUI() {
		if (animEntries.length == 0 || curAnimIdx >= animEntries.length)
			return;
		var e = animEntries[curAnimIdx];
		editingAnimIdx = curAnimIdx;
		animNameInput.text = e.name ?? "";
		animPrefixInput.text = e.prefix ?? "";
		animFpsStepper.value = e.fps ?? 24;
		animLoopCheckbox.checked = e.loop ?? false;
		animFlipXCheckbox.checked = e.flipX ?? false;
		animFlipYCheckbox.checked = e.flipY ?? false;
		animOffsetXStepper.value = (e.offsets != null && e.offsets.length > 0) ? e.offsets[0] : 0;
		animOffsetYStepper.value = (e.offsets != null && e.offsets.length > 1) ? e.offsets[1] : 0;
		var nid = e.noteID;
		_selectedNoteID = nid != null ? nid : -1;
		animNoteIDDropdown.selectedLabel = nid == null ? "none (all dirs)" : '${nid} - ${["Left", "Down", "Up", "Right"][nid % 4]}';
		addAnimBtn.label = "Update Animation";
		_setStatus('Editing: ${e.name}', FlxColor.CYAN);
	}

	function _deleteSelectedAnimation() {
		if (animEntries.length == 0 || curAnimIdx >= animEntries.length)
			return;
		var removed = animEntries[curAnimIdx].name;
		animEntries.splice(curAnimIdx, 1);
		curAnimIdx = Std.int(Math.max(0, curAnimIdx - 1));
		_refreshAnimList();
		_markUnsaved();
		_setStatus('Deleted: $removed', FlxColor.ORANGE);
	}

	function _moveAnimation(dir:Int) {
		var to = curAnimIdx + dir;
		if (to < 0 || to >= animEntries.length)
			return;
		var tmp = animEntries[curAnimIdx];
		animEntries[curAnimIdx] = animEntries[to];
		animEntries[to] = tmp;
		curAnimIdx = to;
		_refreshAnimList();
		_markUnsaved();
	}

	// ──────────────────────────────────────────────────────────── PREVIEW

	/**
	 * Returns the skin/splash folder name to use when resolving texture paths.
	 * Matches what NoteSkinSystem uses: the skin/splash name (from nameInput).
	 * Falls back to "Default" if the name field is empty.
	 */
	function _editorFolder():String {
		var n = nameInput?.text?.trim() ?? "";
		return n.length > 0 ? n : "Default";
	}

	/**
	 * Loads atlas frames for a given path+type, resolving relative to the
	 * correct asset directory:
	 *   - Skin mode  → assets/notes/skins/<folder>/<path>
	 *   - Splash mode → assets/notes/splashes/<folder>/<path>
	 * This mirrors NoteSkinSystem.loadAtlas / loadAtlasSplash exactly so the
	 * editor preview always matches what the engine will load at runtime.
	 */
	function _loadFramesForPath(path:String, type:String):Null<flixel.graphics.frames.FlxAtlasFrames> {
		if (path == null || path.trim().length == 0)
			return null;
		path = path.trim();
		var folder = _editorFolder();
		try {
			if (editorMode == MODE_SPLASH) {
				// Splashes live in assets/notes/splashes/<folder>/
				return switch (type) {
					case "packer": flixel.graphics.frames.FlxAtlasFrames.fromSpriteSheetPacker(flixel.FlxG.bitmap.add('assets/notes/splashes/$folder/$path.png'),
							'assets/notes/splashes/$folder/$path.txt');
					default: Paths.splashSprite('$folder/$path');
				};
			} else {
				// Skins (notes, strums, holds) live in assets/notes/skins/<folder>/
				return switch (type) {
					case "packer": Paths.skinSpriteTxt('$folder/$path');
					default: Paths.skinSprite('$folder/$path');
				};
			}
		} catch (e:Dynamic) {
			trace('[NoteSkinEditor] _loadFramesForPath failed for "$folder/$path": $e');
			return null;
		}
	}

	/**
	 * Applies frames + all animEntries to a sprite.
	 * Silently skips prefixes not found in the atlas.
	 */
	function _applyFramesToSpr(spr:FlxSprite, frames:flixel.graphics.frames.FlxAtlasFrames, scale:Float, aa:Bool):Void {
		if (frames == null)
			return;
		spr.frames = frames;
		spr.scale.set(scale, scale);
		spr.antialiasing = aa;
		for (e in animEntries)
			if (e.prefix != null && e.prefix.length > 0)
				spr.animation.addByPrefix(e.name, e.prefix, e.fps ?? 24, e.loop ?? false);
	}

	/**
	 * Builds the always-visible static showcase.
	 * Always renders ALL elements simultaneously regardless of editor mode:
	 *   - 4 strum sprites  (from skin texture / UI inputs)
	 *   - 4 note heads     (from notes texture)
	 *   - 4 hold pieces + tails (from hold texture)
	 *   - 1 splash sprite  (from splashData)
	 *   - 1 hold-cover sprite (from splashData.holdCover)
	 * Each group can be toggled with the "Show:" checkboxes in the left panel.
	 */
	function _buildShowcase() {
		_clearShowcase();

		var folder = _editorFolder();
		var scale = texScaleStepper?.value ?? 1.0;
		var aa = texAntialiasingCheckbox?.checked ?? true;

		// ── Resolve skin frames (always from skins/ folder) ───────────────────
		// Use texPathInput when editing skin; otherwise fall back to skinData fields.
		var skinFolder = (editorMode == MODE_SKIN) ? folder : (skinData?.folder ?? "Default");
		var mainPath = (editorMode == MODE_SKIN) ? (texPathInput?.text?.trim() ?? "") : (skinData?.texture?.path ?? "");
		var mainType = (editorMode == MODE_SKIN) ? (_texType ?? "sparrow") : (skinData?.texture?.type ?? "sparrow");
		var mainScale = (editorMode == MODE_SKIN) ? scale : (skinData?.texture?.scale ?? 1.0);
		var mainAA = (editorMode == MODE_SKIN) ? aa : (skinData?.texture?.antialiasing ?? true);

		if (mainType == "funkinsprite")
			return;

		var mainFrames:Null<flixel.graphics.frames.FlxAtlasFrames> = null;
		if (mainPath.length > 0 && mainType != "image") {
			try {
				mainFrames = Paths.skinSprite('$skinFolder/$mainPath');
			} catch (e:Dynamic) {
				trace('[NoteSkinEditor] main skin frames failed: $e');
			}
		}

		// Per-role overrides — only used when editing skin mode (UI has the inputs)
		var strumsPath = (editorMode == MODE_SKIN) ? (strumsTexPathInput?.text?.trim() ?? "") : "";
		var strumsFrames = (strumsPath.length > 0) ? (try Paths.skinSprite('$skinFolder/$strumsPath') catch (_:Dynamic) mainFrames) ?? mainFrames : mainFrames;

		var notesPath = (editorMode == MODE_SKIN) ? (notesTexPathInput?.text?.trim() ?? "") : "";
		var notesFrames = (notesPath.length > 0) ? (try Paths.skinSprite('$skinFolder/$notesPath') catch (_:Dynamic) mainFrames) ?? mainFrames : mainFrames;

		var holdFrames = (editorMode == MODE_SKIN) ? (_loadHoldFrames() ?? mainFrames) : mainFrames;
		var holdScale = (editorMode == MODE_SKIN) ? (holdTexScaleStepper?.value ?? mainScale) : mainScale;

		// Keep previewSprite in sync
		if (mainFrames != null) {
			previewSprite.frames = mainFrames;
			previewSprite.scale.set(mainScale, mainScale);
			previewSprite.antialiasing = mainAA;
			previewSprite.visible = true;
		}

		// ── Layout constants ──────────────────────────────────────────────────
		var pfCenter = (360.0 + (FlxG.width - 370.0)) * 0.5;
		var gap = 110.0;
		var x0 = pfCenter - gap * 1.5;
		var strumY = FlxG.height * 0.72;
		var noteY = strumY - 200.0;

		// ── Strums / Notes / Holds / Tails ────────────────────────────────────
		for (i in 0...4) {
			var sx = x0 + i * gap;

			var strum = _makeShowcaseSpr(strumsFrames, mainScale, mainAA);
			_applyLegacyAnimsToSpr(strum, strumsFrames);
			if (!_tryPlayDirAnim(strum, i, "static"))
				strum.makeGraphic(54, 54, _DIR_COLORS[i]);
			strum.updateHitbox();
			strum.setPosition(sx - strum.width * 0.5, strumY - strum.height * 0.5);
			strum.visible = _showStrums;
			add(strum);
			_showcaseStrums.push(strum);

			var note = _makeShowcaseSpr(notesFrames, mainScale, mainAA);
			_applyLegacyAnimsToSpr(note, notesFrames);
			if (!_tryPlayDirAnim(note, i, "note"))
				note.makeGraphic(54, 54, _DIR_COLORS[i]);
			note.updateHitbox();
			note.setPosition(sx - note.width * 0.5, noteY - note.height * 0.5);
			note.visible = _showNotes;
			add(note);
			_showcaseNotes.push(note);

			var hold = _makeShowcaseSpr(holdFrames, holdScale, mainAA);
			_applyLegacyAnimsToSpr(hold, holdFrames);
			if (!_tryPlayDirAnim(hold, i, "hold"))
				hold.makeGraphic(Std.int(24 * holdScale), Std.int(80 * holdScale), (_DIR_COLORS[i] & 0x00FFFFFF) | 0xBB000000);
			hold.updateHitbox();
			hold.setPosition(sx - hold.width * 0.5, noteY + 50.0);
			hold.visible = _showHolds;
			add(hold);
			_showcaseHolds.push(hold);

			var tail = _makeShowcaseSpr(holdFrames, holdScale, mainAA);
			_applyLegacyAnimsToSpr(tail, holdFrames);
			if (!_tryPlayDirAnim(tail, i, "tail"))
				tail.makeGraphic(Std.int(24 * holdScale), Std.int(24 * holdScale), (_DIR_COLORS[i] & 0x00FFFFFF) | 0x88000000);
			tail.updateHitbox();
			tail.setPosition(sx - tail.width * 0.5, strumY - tail.height - 8.0);
			tail.visible = _showHolds;
			add(tail);
			_showcaseTails.push(tail);
		}

		// ── Splash preview (always, from splashData) ──────────────────────────
		var splashFolder = (editorMode == MODE_SPLASH) ? folder : (splashData?.folder ?? "Default");
		var splashPath = (editorMode == MODE_SPLASH) ? (texPathInput?.text?.trim() ?? "") : (splashData?.assets?.path ?? "");
		var splashScale = (editorMode == MODE_SPLASH) ? (splashScaleStepper?.value ?? 1.0) : (splashData?.assets?.scale ?? 1.0);
		var splashAA = (editorMode == MODE_SPLASH) ? (splashAntialiasingCheckbox?.checked ?? true) : (splashData?.assets?.antialiasing ?? true);

		if (splashPath.length > 0) {
			try {
				var splashFrames = Paths.splashSprite('$splashFolder/$splashPath');
				if (splashFrames != null) {
					var spr = new FlxSprite();
					spr.cameras = [camHUD];
					spr.scrollFactor.set();
					spr.frames = splashFrames;
					spr.scale.set(splashScale, splashScale);
					spr.antialiasing = splashAA;
					// Register splash animations
					var splashAnims = (editorMode == MODE_SPLASH) ? animEntries : (splashData?.animList ?? []);
					for (e in splashAnims)
						if (e.prefix != null && e.prefix.length > 0)
							spr.animation.addByPrefix(e.name, e.prefix, e.fps ?? 24, e.loop ?? false);
					var al = spr.animation.getAnimationList();
					if (al.length > 0) {
						spr.animation.play(al[0].name, true);
						spr.animation.pause();
					}
					spr.updateHitbox();
					// Position: overlap strum 1 (down), slightly above
					var sx = x0 + 1 * gap;
					spr.setPosition(sx - spr.width * 0.5, strumY - spr.height * 0.5 - 55.0);
					spr.visible = _showSplash;
					add(spr);
					_showcaseSplash = spr;
				}
			} catch (e:Dynamic) {
				trace('[NoteSkinEditor] splash showcase failed: $e');
			}
		}

		// ── Hold Cover preview (always, from splashData.holdCover) ────────────
		var hc = splashData?.holdCover;
		if (hc != null && hc.texturePrefix != null && (hc.texturePrefix : String).length > 0) {
			try {
				var hcFile = (hc.perColorTextures == true) ? (hc.texturePrefix : String) + "Purple" : (hc.texturePrefix : String);
				var hcFrames = Paths.splashSprite('$splashFolder/$hcFile');
				if (hcFrames != null) {
					var spr = new FlxSprite();
					spr.cameras = [camHUD];
					spr.scrollFactor.set();
					spr.frames = hcFrames;
					spr.scale.set(hc.scale ?? 1.0, hc.scale ?? 1.0);
					spr.antialiasing = hc.antialiasing ?? true;
					if (hc.startPrefix != null && (hc.startPrefix : String).length > 0)
						spr.animation.addByPrefix("start", cast hc.startPrefix, hc.framerate ?? 24, false);
					if (hc.loopPrefix != null && (hc.loopPrefix : String).length > 0)
						spr.animation.addByPrefix("loop", cast hc.loopPrefix, hc.loopFramerate ?? 48, true);
					if (hc.endPrefix != null && (hc.endPrefix : String).length > 0)
						spr.animation.addByPrefix("end", cast hc.endPrefix, hc.framerate ?? 24, false);
					var al = spr.animation.getAnimationList();
					if (al.length > 0) {
						spr.animation.play(al[0].name, true);
						spr.animation.pause();
					}
					spr.updateHitbox();
					// Position: overlap strum 2 (up), slightly above
					var sx = x0 + 2 * gap;
					spr.setPosition(sx - spr.width * 0.5, strumY - spr.height * 0.5 - 55.0);
					spr.visible = _showHoldCover;
					add(spr);
					_showcaseHoldCover = spr;
				}
			} catch (e:Dynamic) {
				trace('[NoteSkinEditor] hold cover showcase failed: $e');
			}
		}
	}

	/** Creates a fresh HUD-space showcase sprite and applies animEntries to it. */
	function _makeShowcaseSpr(frames:flixel.graphics.frames.FlxAtlasFrames, scale:Float, aa:Bool):FlxSprite {
		var spr = new FlxSprite();
		spr.cameras = [camHUD];
		spr.scrollFactor.set();
		_applyFramesToSpr(spr, frames, scale, aa);
		return spr;
	}

	/**
	 * Registers all animations from the legacy `animations:{}` field of the current
	 * skinData onto `spr`. Works alongside animEntries (both formats coexist).
	 * For sparrow-type atlases: uses `prefix`. For image/grid atlases: uses `indices`.
	 */
	function _applyLegacyAnimsToSpr(spr:FlxSprite, frames:flixel.graphics.frames.FlxAtlasFrames):Void {
		// Apply skin legacy animations regardless of current editorMode —
		// the showcase always displays skin sprites even when editing a splash.
		var anims:Dynamic = (skinData != null) ? skinData.animations : null;
		if (anims == null || frames == null)
			return;
		for (name in Reflect.fields(anims)) {
			var def:Dynamic = Reflect.field(anims, name);
			if (def == null)
				continue;
			var fps:Int = def.framerate != null ? Std.int(def.framerate) : 24;
			var loop:Bool = def.loop != null ? (def.loop : Bool) : false;
			if (def.prefix != null && (def.prefix : String).length > 0) {
				if (!spr.animation.exists(name))
					spr.animation.addByPrefix(name, cast def.prefix, fps, loop);
			} else if (def.indices != null) {
				var idx:Array<Int> = cast def.indices;
				if (!spr.animation.exists(name))
					spr.animation.add(name, idx, fps, loop);
			}
		}
	}

	/**
	 * Loads hold/tail frames, handling both atlas types and the special
	 * image-grid type (frameWidth × frameHeight sliced spritesheet).
	 */
	function _loadHoldFrames():Null<flixel.graphics.frames.FlxAtlasFrames> {
		var path = holdTexPathInput?.text?.trim() ?? "";
		if (path.length == 0)
			return null;
		var type = _holdTexType ?? "sparrow";
		if (type == "image") {
			try {
				var fw = (skinData?.holdTexture?.frameWidth != null) ? Std.int(skinData.holdTexture.frameWidth) : 17;
				var fh = (skinData?.holdTexture?.frameHeight != null) ? Std.int(skinData.holdTexture.frameHeight) : 17;
				var folder = _editorFolder();
				var g = FlxG.bitmap.add('assets/notes/skins/$folder/$path.png');
				if (g == null)
					return null;
				g.persist = true;
				return extensions.FlxAtlasFramesExt.fromGraphic(g, fw, fh);
			} catch (e:Dynamic) {
				trace('[Showcase] image hold load failed: $e');
				return null;
			}
		}
		return _loadFramesForPath(path, type);
	}

	/** Destroys all showcase sprites. */
	function _clearShowcase() {
		for (s in _showcaseStrums) {
			remove(s, true);
			s.destroy();
		}
		_showcaseStrums = [];
		for (s in _showcaseNotes) {
			remove(s, true);
			s.destroy();
		}
		_showcaseNotes = [];
		for (s in _showcaseHolds) {
			remove(s, true);
			s.destroy();
		}
		_showcaseHolds = [];
		for (s in _showcaseTails) {
			remove(s, true);
			s.destroy();
		}
		_showcaseTails = [];
		if (_showcaseSplash != null) {
			remove(_showcaseSplash, true);
			_showcaseSplash.destroy();
			_showcaseSplash = null;
		}
		if (_showcaseHoldCover != null) {
			remove(_showcaseHoldCover, true);
			_showcaseHoldCover.destroy();
			_showcaseHoldCover = null;
		}
		previewSprite.visible = false;
	}

	function _reloadPreviewSprite() {
		// Build a temporary sprite from the current texture settings
		var path = texPathInput.text.trim();
		if (path.length == 0) {
			_setStatus("No texture path set.", FlxColor.ORANGE);
			return;
		}

		try {
			var texType = _texType;
			var frames:Null<flixel.graphics.frames.FlxAtlasFrames> = null;
			var folder = _editorFolder();
			var isSplash = (editorMode == MODE_SPLASH);
			switch (texType) {
				case "packer":
					frames = isSplash ? flixel.graphics.frames.FlxAtlasFrames.fromSpriteSheetPacker(flixel.FlxG.bitmap.add('assets/notes/splashes/$folder/$path.png'),
						'assets/notes/splashes/$folder/$path.txt') : Paths.skinSpriteTxt('$folder/$path');
				case "image" | "funkinsprite":
					// Plain image — no atlas; load directly as a graphic
					var imgPath = isSplash ? 'assets/notes/splashes/$folder/$path.png' : 'assets/notes/skins/$folder/$path.png';
					previewSprite.loadGraphic(imgPath);
				default: // sparrow
					frames = isSplash ? Paths.splashSprite('$folder/$path') : Paths.skinSprite('$folder/$path');
			}
			if (frames != null)
				previewSprite.frames = frames;
			previewSprite.scale.set(texScaleStepper.value, texScaleStepper.value);
			previewSprite.antialiasing = texAntialiasingCheckbox.checked;
			previewSprite.updateHitbox();

			// Register animations — only meaningful for atlas-backed sprites
			if (frames != null) {
				if (previewSprite.animation != null)
					previewSprite.animation.destroyAnimations();

				for (e in animEntries) {
					if (e.prefix != null && e.prefix.length > 0)
						previewSprite.animation.addByPrefix(e.name, e.prefix, e.fps ?? 24, e.loop ?? false);
				}

				if (animEntries.length > 0) {
					curAnimIdx = Std.int(Math.max(0, Math.min(curAnimIdx, animEntries.length - 1)));
					_playSelectedAnimOnPreview();
				}
			}

			previewSprite.setPosition(camFollow.x - previewSprite.width * 0.5, camFollow.y - previewSprite.height * 0.5);
			previewSprite.visible = true;
			_setStatus('Preview loaded: $path', 0xFF44FF88);
			// Rebuild static showcase with the new texture
			_buildShowcase();
		} catch (e:Dynamic) {
			_setStatus('Error loading preview: $e', FlxColor.RED);
		}
	}

	function _playSelectedAnimOnPreview() {
		if (!previewSprite.visible || animEntries.length == 0)
			return;
		curAnimIdx = Std.int(Math.max(0, Math.min(curAnimIdx, animEntries.length - 1)));
		var e = animEntries[curAnimIdx];
		if (previewSprite.animation.exists(e.name)) {
			previewSprite.animation.play(e.name, true);
			_applyPreviewOffset();
		}
	}

	function _applyPreviewOffset() {
		if (!previewSprite.visible || curAnimIdx >= animEntries.length)
			return;
		var e = animEntries[curAnimIdx];
		if (e.offsets != null && e.offsets.length >= 2) {
			previewSprite.updateHitbox();
			previewSprite.offset.set(e.offsets[0], e.offsets[1]);
		}
	}

	// ──────────────────────────────────────────────────────────── MODE CHANGE

	function _onModeChanged() {
		var modeName = switch (editorMode) {
			case MODE_SPLASH: "Splash";
			case MODE_HOLDCOVER: "Hold Cover";
			default: "Note Skin";
		};
		headerText.text = 'NOTE SKIN EDITOR — $modeName';

		// Switch animEntries to the correct source
		_syncAnimEntriesFromMode();
		_refreshAnimList();
		_setStatus('Mode: $modeName', FlxColor.CYAN);
	}

	function _syncAnimEntriesFromMode() {
		switch (editorMode) {
			case MODE_SKIN:
				animEntries = skinData.animList ?? [];
				skinData.animList = animEntries;
			case MODE_SPLASH:
				animEntries = splashData.animList ?? [];
				splashData.animList = animEntries;
			case MODE_HOLDCOVER:
				if (splashData.holdCover == null)
					splashData.holdCover = {animList: []};
				animEntries = splashData.holdCover.animList ?? [];
				splashData.holdCover.animList = animEntries;
		}
	}

	// ──────────────────────────────────────────────────────────── LOAD GAME

	function _loadSkinFromGame(name:String) {
		var data = NoteSkinSystem.availableSkins.get(name);
		if (data == null) {
			_setStatus('Skin not found: $name', FlxColor.RED);
			return;
		}
		skinData = data;
		animEntries = skinData.animList ?? [];
		if (skinData.animList == null)
			skinData.animList = animEntries;
		_populateUIFromSkinData();
		editorMode = MODE_SKIN;
		_refreshAnimList();
		_setStatus('Loaded skin: $name', 0xFF44FF88);
	}

	function _loadSplashFromGame(name:String) {
		var data = NoteSkinSystem.availableSplashes.get(name);
		if (data == null) {
			_setStatus('Splash not found: $name', FlxColor.RED);
			return;
		}
		splashData = data;
		animEntries = splashData.animList ?? [];
		if (splashData.animList == null)
			splashData.animList = animEntries;
		_populateUIFromSplashData();
		editorMode = MODE_SPLASH;
		_refreshAnimList();
		_setStatus('Loaded splash: $name', 0xFF44FF88);
	}

	function _populateUIFromSkinData() {
		nameInput.text = skinData.name ?? "";
		authorInput.text = skinData.author ?? "";
		descInput.text = skinData.description ?? "";
		texPathInput.text = skinData.texture?.path ?? "";
		_texType = skinData.texture?.type ?? "sparrow";
		texTypeDropdown.selectedLabel = _texType;
		texScaleStepper.value = skinData.texture?.scale ?? 1.0;
		texAntialiasingCheckbox.checked = skinData.texture?.antialiasing ?? true;
		var holdType = skinData.holdTexture?.type ?? "sparrow";
		_holdTexType = holdType;
		holdTexTypeDropdown.selectedLabel = holdType;
		holdTexPathInput.text = skinData.holdTexture?.path ?? "";
		holdTexScaleStepper.value = skinData.holdTexture?.scale ?? 1.0;
		notesTexPathInput.text = skinData.notesTexture?.path ?? "";
		strumsTexPathInput.text = skinData.strumsTexture?.path ?? "";
		isPixelCheckbox.checked = skinData.isPixel ?? false;
		confirmOffsetCheckbox.checked = skinData.confirmOffset ?? true;
		sustainOffsetStepper.value = skinData.sustainOffset ?? 0.0;
		holdStretchStepper.value = skinData.holdStretch ?? 1.0;
		colorAutoCheckbox.checked = skinData.colorAuto ?? false;
		colorMultStepper.value = skinData.colorMult ?? 1.0;
		_buildShowcase();
	}

	function _populateUIFromSplashData() {
		nameInput.text = splashData.name ?? "";
		authorInput.text = splashData.author ?? "";
		descInput.text = splashData.description ?? "";
		texPathInput.text = splashData.assets?.path ?? "";
		splashScaleStepper.value = splashData.assets?.scale ?? 1.0;
		splashAntialiasingCheckbox.checked = splashData.assets?.antialiasing ?? true;
		if (splashData.assets?.offset != null && splashData.assets.offset.length >= 2) {
			splashOffsetXStepper.value = splashData.assets.offset[0];
			splashOffsetYStepper.value = splashData.assets.offset[1];
		}
		var hc = splashData.holdCover;
		if (hc != null) {
			hcPerColorCheckbox.checked = hc.perColorTextures ?? true;
			hcTexturePrefix.text = hc.texturePrefix ?? "holdCover";
			_hcTextureType = hc.textureType ?? "sparrow";
			hcTextureTypeDropdown.selectedLabel = _hcTextureType;
			hcScaleStepper.value = hc.scale ?? 1.0;
			hcFramerateStepper.value = hc.framerate ?? 24;
			hcLoopFramerateStepper.value = hc.loopFramerate ?? 48;
			hcStartPrefixInput.text = hc.startPrefix ?? "holdCoverStart";
			hcLoopPrefixInput.text = hc.loopPrefix ?? "holdCover";
			hcEndPrefixInput.text = hc.endPrefix ?? "holdCoverEnd";
			if (hc.offset != null && hc.offset.length >= 2) {
				hcOffsetXStepper.value = hc.offset[0];
				hcOffsetYStepper.value = hc.offset[1];
			}
		}
		_buildShowcase();
	}

	// ──────────────────────────────────────────────────────────── LOAD FILE

	function _loadJSONFromFile() {
		#if sys
		var fd = new FileDialog();
		fd.onSelect.add(function(path:String) {
			try {
				var raw = File.getContent(path);
				var obj = Json.parse(raw);
				// Detect by presence of "assets" field → splash; else → skin
				if (Reflect.hasField(obj, "assets")) {
					splashData = (cast obj : funkin.gameplay.notes.NoteSplashData);
					animEntries = splashData.animList ?? [];
					splashData.animList = animEntries;
					_populateUIFromSplashData();
					editorMode = MODE_SPLASH;
					_refreshAnimList();
					_setStatus('Loaded: $path', 0xFF44FF88);
				} else {
					skinData = (cast obj : funkin.gameplay.notes.NoteSkinData);
					animEntries = skinData.animList ?? [];
					skinData.animList = animEntries;
					_populateUIFromSkinData();
					editorMode = MODE_SKIN;
					_refreshAnimList();
					_setStatus('Loaded: $path', 0xFF44FF88);
				}
			} catch (e:Dynamic) {
				_setStatus('Error parsing JSON: $e', FlxColor.RED);
			}
		});
		fd.browse(lime.ui.FileDialogType.OPEN, "json", null, "Open skin.json or splash.json");
		#else
		_setStatus("File dialog not available on this platform.", FlxColor.ORANGE);
		#end
	}

	// ──────────────────────────────────────────────────────────── BUILD JSON

	function _buildSkinJSON():Dynamic {
		// Collect from UI into skinData
		skinData.name = nameInput.text.trim();
		skinData.author = authorInput.text.trim();
		skinData.description = descInput.text.trim();
		skinData.texture = {
			path: texPathInput.text.trim(),
			type: _texType,
			scale: texScaleStepper.value,
			antialiasing: texAntialiasingCheckbox.checked
		};

		// Optional hold texture
		if (holdTexPathInput.text.trim().length > 0)
			skinData.holdTexture = {
				path: holdTexPathInput.text.trim(),
				type: _holdTexType,
				scale: holdTexScaleStepper.value
			};
		else
			skinData.holdTexture = null;

		// Optional notes/strums textures
		skinData.notesTexture = notesTexPathInput.text.trim().length > 0 ? {path: notesTexPathInput.text.trim()} : null;
		skinData.strumsTexture = strumsTexPathInput.text.trim().length > 0 ? {path: strumsTexPathInput.text.trim()} : null;

		skinData.isPixel = isPixelCheckbox.checked;
		skinData.confirmOffset = confirmOffsetCheckbox.checked;
		skinData.sustainOffset = sustainOffsetStepper.value;
		skinData.holdStretch = holdStretchStepper.value;
		skinData.colorAuto = colorAutoCheckbox.checked;
		skinData.colorMult = colorMultStepper.value;
		skinData.animList = animEntries;

		// Strip nulls for cleaner output
		var out:Dynamic = {};
		if (skinData.name != null && skinData.name.length > 0)
			Reflect.setField(out, "name", skinData.name);
		if (skinData.author != null && skinData.author.length > 0)
			Reflect.setField(out, "author", skinData.author);
		if (skinData.description != null && skinData.description.length > 0)
			Reflect.setField(out, "description", skinData.description);
		Reflect.setField(out, "texture", skinData.texture);
		if (skinData.holdTexture != null)
			Reflect.setField(out, "holdTexture", skinData.holdTexture);
		if (skinData.notesTexture != null)
			Reflect.setField(out, "notesTexture", skinData.notesTexture);
		if (skinData.strumsTexture != null)
			Reflect.setField(out, "strumsTexture", skinData.strumsTexture);
		if (skinData.isPixel)
			Reflect.setField(out, "isPixel", true);
		if (!skinData.confirmOffset)
			Reflect.setField(out, "confirmOffset", false);
		if (skinData.sustainOffset != 0)
			Reflect.setField(out, "sustainOffset", skinData.sustainOffset);
		if (skinData.holdStretch != 1.0)
			Reflect.setField(out, "holdStretch", skinData.holdStretch);
		if (skinData.colorAuto)
			Reflect.setField(out, "colorAuto", true);
		if (skinData.colorMult != 1.0)
			Reflect.setField(out, "colorMult", skinData.colorMult);
		if (animEntries.length > 0)
			Reflect.setField(out, "animList", animEntries);
		Reflect.setField(out, "animations", {}); // kept for engine compatibility
		return out;
	}

	function _buildSplashJSON():Dynamic {
		splashData.name = nameInput.text.trim();
		splashData.author = authorInput.text.trim();
		splashData.description = descInput.text.trim();
		splashData.assets = {
			path: texPathInput.text.trim(),
			scale: splashScaleStepper.value,
			antialiasing: splashAntialiasingCheckbox.checked,
			offset: [splashOffsetXStepper.value, splashOffsetYStepper.value]
		};

		// Hold cover
		splashData.holdCover = {
			perColorTextures: hcPerColorCheckbox.checked,
			texturePrefix: hcTexturePrefix.text.trim(),
			textureType: _hcTextureType,
			scale: hcScaleStepper.value,
			framerate: Std.int(hcFramerateStepper.value),
			loopFramerate: Std.int(hcLoopFramerateStepper.value),
			offset: (hcOffsetXStepper.value != 0 || hcOffsetYStepper.value != 0) ? [hcOffsetXStepper.value, hcOffsetYStepper.value] : null,
			startPrefix: hcStartPrefixInput.text.trim(),
			loopPrefix: hcLoopPrefixInput.text.trim(),
			endPrefix: hcEndPrefixInput.text.trim(),
			animList: (editorMode == MODE_HOLDCOVER) ? animEntries : (splashData.holdCover?.animList ?? [])
		};

		splashData.animList = (editorMode == MODE_SPLASH) ? animEntries : (splashData.animList ?? []);
		splashData.animations = {all: ["note impact 1", "note impact 2"]}; // compat fallback

		return splashData;
	}

	// ──────────────────────────────────────────────────────────── EXPORT

	function _exportJSON(type:String) {
		var data:Dynamic = (type == "skin") ? _buildSkinJSON() : _buildSplashJSON();
		var jsonString = Json.stringify(data, null, '\t');
		var filename = (type == "skin") ? (skinData.name ?? "skin").replace(" ", "_") + ".json" : (splashData.name ?? "splash").replace(" ", "_") + ".json";

		_file = new FileReference();
		_file.addEventListener(Event.COMPLETE, _onSaveComplete);
		_file.addEventListener(Event.CANCEL, _onSaveCancel);
		_file.addEventListener(IOErrorEvent.IO_ERROR, _onSaveError);
		_file.save(jsonString, filename);
	}

	function _copyToClipboard(type:String) {
		var data:Dynamic = (type == "skin") ? _buildSkinJSON() : _buildSplashJSON();
		var jsonString = Json.stringify(data, null, '\t');
		#if desktop
		lime.system.Clipboard.text = jsonString;
		_setStatus('✓ JSON copied to clipboard!', FlxColor.LIME);
		#else
		_setStatus("Clipboard not supported on this platform.", FlxColor.ORANGE);
		#end
	}

	// ─────────────────────────────────────────────────────── PLAY PREVIEW

	/**
	 * Toggles the play-preview mode on/off.
	 * In this mode the four arrow keys spawn notes that travel toward the strums.
	 */
	function _togglePlayPreview() {
		_playPreviewActive = !_playPreviewActive;
		_previewPlayBtn.label = _playPreviewActive ? "■ Stop Preview" : "▶ Play Preview";
		_previewHintText.visible = _playPreviewActive;

		if (_playPreviewActive) {
			_noteScrollSpeed = _noteSpeedStepper.value;
			_downscroll = _downscrollCheckbox.checked;
			_initPlayPreviewStrums();
			_setStatus("Play Preview ON  ←↓↑→ = spawn notes", FlxColor.LIME);
		} else {
			_tearDownPlayPreview();
			_setStatus("Play Preview OFF", FlxColor.CYAN);
		}
	}

	/** Activates play preview: reuses the showcase strum sprites and hides static note/hold/tail. */
	function _initPlayPreviewStrums() {
		// Make sure showcase exists
		if (_showcaseStrums.length == 0)
			_buildShowcase();

		// Re-use showcase strum sprites directly
		_playStrums = _showcaseStrums.copy();

		// Reposition strums for current downscroll setting
		var strumY = _downscroll ? FlxG.height - 100.0 : FlxG.height * 0.72;
		for (i in 0...4)
			_playStrums[i].setPosition(_playStrums[i].x, strumY - _playStrums[i].height * 0.5);

		// Hide static note / hold / tail rows during play mode
		for (s in _showcaseNotes)
			s.visible = false;
		for (s in _showcaseHolds)
			s.visible = false;
		for (s in _showcaseTails)
			s.visible = false;
		if (_showcaseSplash != null)
			_showcaseSplash.visible = false;
		if (_showcaseHoldCover != null)
			_showcaseHoldCover.visible = false;
	}

	/**
	 * Copies the skin frames + all animList animations to a fresh FlxSprite.
	 * @return true if at least one animation was registered.
	 */
	function _setupSpriteWithSkinAnims(spr:FlxSprite):Bool {
		if (_texType == "image" || _texType == "funkinsprite")
			return false;
		if (!previewSprite.visible)
			return false;

		spr.frames = previewSprite.frames;
		spr.scale.set(texScaleStepper.value, texScaleStepper.value);
		spr.antialiasing = texAntialiasingCheckbox.checked;

		for (e in animEntries)
			if (e.prefix != null && e.prefix.length > 0)
				spr.animation.addByPrefix(e.name, e.prefix, e.fps ?? 24, e.loop ?? false);

		spr.updateHitbox();
		return spr.animation.getAnimationList().length > 0;
	}

	/**
	 * Tries each candidate animation name in order and plays the first that exists.
	 * @param mode  "note" | "static" | "confirm"
	 * @return true if an animation was played.
	 */
	function _tryPlayDirAnim(spr:FlxSprite, dir:Int, mode:String):Bool {
		var list = switch (mode) {
			case "static": _STRUM_STATIC_ANIMS[dir];
			case "confirm": _STRUM_CONFIRM_ANIMS[dir];
			case "press": _STRUM_PRESS_ANIMS[dir];
			case "hold": _HOLD_ANIMS[dir];
			case "tail": _TAIL_ANIMS[dir];
			default: _NOTE_ANIMS[dir];
		};
		for (c in list) {
			if (spr.animation.exists(c)) {
				spr.animation.play(c, true);
				return true;
			}
		}
		return false;
	}

	/** Spawns a scrolling note sprite for the given direction (0-3). */
	function _spawnPlayNote(dir:Int) {
		if (dir < 0 || dir >= _playStrums.length)
			return;
		var strum = _playStrums[dir];

		var spr = new FlxSprite();
		spr.cameras = [camHUD];
		spr.scrollFactor.set();

		// Reuse showcase note sprite's frames if available
		if (dir < _showcaseNotes.length && _showcaseNotes[dir].frames != null) {
			_applyFramesToSpr(spr, cast(_showcaseNotes[dir].frames, flixel.graphics.frames.FlxAtlasFrames), texScaleStepper.value,
				texAntialiasingCheckbox.checked);
			if (!_tryPlayDirAnim(spr, dir, "note") && animEntries.length > 0)
				spr.animation.play(animEntries[0].name);
		} else {
			spr.makeGraphic(54, 54, _DIR_COLORS[dir]);
		}

		spr.updateHitbox();

		// Upscroll: notes come from the TOP   Downscroll: notes come from the BOTTOM
		var spawnY = _downscroll ? FlxG.height + 10.0 : -spr.height - 10.0;

		spr.setPosition(strum.x + strum.width * 0.5 - spr.width * 0.5, spawnY);

		add(spr);
		_activeNotes.push({spr: spr, dir: dir, hit: false});
	}

	/** Flashes the strum confirm animation, then reverts to static after 180 ms. */
	function _flashStrum(dir:Int) {
		if (dir >= _playStrums.length)
			return;
		var strum = _playStrums[dir];

		var played = _tryPlayDirAnim(strum, dir, "confirm");
		if (!played) {
			// No confirm anim: just brighten briefly
			strum.color = 0xFFFFFFFF;
			strum.alpha = 0.6;
		}

		new FlxTimer().start(0.18, function(_) {
			if (dir >= _playStrums.length)
				return;
			_playStrums[dir].color = 0xFFFFFFFF;
			_playStrums[dir].alpha = 1.0;
			_tryPlayDirAnim(_playStrums[dir], dir, "static");
		});
	}

	/** Removes active note sprites and restores the showcase to its static state. */
	function _tearDownPlayPreview() {
		for (nd in _activeNotes) {
			remove(nd.spr, true);
			nd.spr.destroy();
		}
		_activeNotes = [];

		// Do NOT destroy showcase strum sprites — just drop the reference
		_playStrums = [];

		// Restore static note / hold / tail rows
		for (s in _showcaseNotes)
			s.visible = _showNotes;
		for (s in _showcaseHolds)
			s.visible = _showHolds;
		for (s in _showcaseTails)
			s.visible = _showHolds;
		if (_showcaseSplash != null)
			_showcaseSplash.visible = _showSplash;
		if (_showcaseHoldCover != null)
			_showcaseHoldCover.visible = _showHoldCover;

		// Return strums to idle animation
		for (i in 0..._showcaseStrums.length) {
			_showcaseStrums[i].color = 0xFFFFFFFF;
			_showcaseStrums[i].alpha = 1.0;
			_tryPlayDirAnim(_showcaseStrums[i], i, "static");
		}
	}

	/** Called every frame while play preview is active. */
	function _updatePlayPreview(elapsed:Float) {
		// Read speed + downscroll live so the stepper/checkbox work during playback
		_noteScrollSpeed = _noteSpeedStepper.value;
		_downscroll = _downscrollCheckbox.checked;

		// ── Spawn notes on key press ──────────────────────────────────────────
		var keys = [FlxKey.LEFT, FlxKey.DOWN, FlxKey.UP, FlxKey.RIGHT];
		for (i in 0...4)
			if (FlxG.keys.checkStatus(keys[i], JUST_PRESSED))
				_spawnPlayNote(i);

		// ── Move notes ────────────────────────────────────────────────────────
		var vel = _noteScrollSpeed * (_downscroll ? 1.0 : -1.0);
		var toKill:Array<{spr:FlxSprite, dir:Int, hit:Bool}> = [];

		for (nd in _activeNotes) {
			nd.spr.y += vel * elapsed;

			if (!nd.hit && nd.dir < _playStrums.length) {
				var strumMidY = _playStrums[nd.dir].y + _playStrums[nd.dir].height * 0.5;
				var noteMidY = nd.spr.y + nd.spr.height * 0.5;

				// Auto-hit when the note centre crosses the strum centre
				var crossed = _downscroll ? noteMidY >= strumMidY : noteMidY <= strumMidY;

				if (crossed) {
					nd.hit = true;
					_flashStrum(nd.dir);
				}
			}

			// Despawn after passing 60px beyond the far edge
			var despawn = _downscroll ? nd.spr.y + nd.spr.height < -60 : nd.spr.y > FlxG.height + 60;
			if (despawn)
				toKill.push(nd);
		}

		for (nd in toKill) {
			remove(nd.spr, true);
			nd.spr.destroy();
			_activeNotes.remove(nd);
		}
	}

	// ──────────────────────────────────────────────────────── TEXTURE BROWSER

	/**
	 * Opens a PNG file picker.  Auto-detects a sidecar atlas (.xml for Sparrow,
	 * .txt for Packer) and updates the matching type-dropdown automatically.
	 *
	 * @param onPick      Callback(pngAbsPath, atlasAbsPathOrNull).
	 * @param isMain      true = updates texTypeDropdown/_texType,
	 *                    false = updates holdTexTypeDropdown/_holdTexType.
	 */
	function _browseTexturePNG(onPick:String->String->Void, isMain:Bool) {
		#if sys
		var fd = new FileDialog();
		fd.onSelect.add(function(pngPath:String) {
			var norm = pngPath.replace("\\", "/");
			var base = norm.endsWith(".png") ? norm.substr(0, norm.length - 4) : norm;

			// Auto-detect atlas sidecar
			var xmlPath = base + ".xml";
			var txtPath = base + ".txt";
			var atlasPath:String = null;
			var detectedType = "image";

			if (FileSystem.exists(xmlPath)) {
				atlasPath = xmlPath;
				detectedType = "sparrow";
			} else if (FileSystem.exists(txtPath)) {
				atlasPath = txtPath;
				detectedType = "packer";
			}

			// Update the correct dropdown
			if (isMain) {
				_texType = detectedType;
				texTypeDropdown.selectedLabel = detectedType;
			} else {
				_holdTexType = detectedType;
				holdTexTypeDropdown.selectedLabel = detectedType;
			}

			onPick(pngPath, atlasPath);
		});
		fd.browse(lime.ui.FileDialogType.OPEN, "png", null, "Select texture PNG");
		#else
		_setStatus("File dialog not available on this platform.", FlxColor.ORANGE);
		#end
	}

	// ──────────────────────────────────────────────────────── SAVE TO FOLDER

	/**
	 * Asks the user where to save, then writes:
	 *   <folder>/skin.json   (or splash.json)
	 *   <folder>/<tex>.png
	 *   <folder>/<tex>.xml   (if Sparrow atlas was imported)
	 *   <folder>/<tex>.txt   (if Packer atlas was imported)
	 *   <folder>/<holdTex>.png + atlas  (if a hold texture was browsed)
	 */
	function _saveSkinToFolder() {
		#if sys
		var isSkin = (editorMode == MODE_SKIN);
		var jsonName = isSkin ? (skinData.name ?? "skin").replace(" ", "_") + ".json" : (splashData.name ?? "splash").replace(" ", "_") + ".json";

		var fd = new FileDialog();
		fd.onSelect.add(function(savePath:String) {
			try {
				// Resolve output folder from the chosen save path
				var norm = savePath.replace("\\", "/");
				var folder = norm.contains("/") ? norm.substr(0, norm.lastIndexOf("/")) : ".";

				if (!FileSystem.exists(folder))
					FileSystem.createDirectory(folder);

				// ── Write JSON ────────────────────────────────────────────────
				var data:Dynamic = isSkin ? _buildSkinJSON() : _buildSplashJSON();
				File.saveContent(folder + "/" + jsonName, Json.stringify(data, null, "\t"));

				var copied:Array<String> = [jsonName];

				// ── Copy main texture files ───────────────────────────────────
				if (_texAbsPath != null && FileSystem.exists(_texAbsPath)) {
					var dest = folder + "/" + _fileName(_texAbsPath);
					if (_texAbsPath != dest)
						File.copy(_texAbsPath, dest);
					copied.push(_fileName(_texAbsPath));
				}
				if (_texAtlasAbsPath != null && FileSystem.exists(_texAtlasAbsPath)) {
					var dest = folder + "/" + _fileName(_texAtlasAbsPath);
					if (_texAtlasAbsPath != dest)
						File.copy(_texAtlasAbsPath, dest);
					copied.push(_fileName(_texAtlasAbsPath));
				}

				// ── Copy hold texture files ───────────────────────────────────
				if (_holdTexAbsPath != null && FileSystem.exists(_holdTexAbsPath)) {
					var dest = folder + "/" + _fileName(_holdTexAbsPath);
					if (_holdTexAbsPath != dest)
						File.copy(_holdTexAbsPath, dest);
					copied.push(_fileName(_holdTexAbsPath));
				}
				if (_holdTexAtlasAbsPath != null && FileSystem.exists(_holdTexAtlasAbsPath)) {
					var dest = folder + "/" + _fileName(_holdTexAtlasAbsPath);
					if (_holdTexAtlasAbsPath != dest)
						File.copy(_holdTexAtlasAbsPath, dest);
					copied.push(_fileName(_holdTexAtlasAbsPath));
				}

				_hasUnsaved = false;
				_setStatus('✓ Saved ${copied.length} file(s) to: $folder', FlxColor.LIME);
			} catch (e:Dynamic) {
				_setStatus('Error saving to folder: $e', FlxColor.RED);
			}
		});
		fd.browse(lime.ui.FileDialogType.SAVE, "json", jsonName, "Save skin to folder");
		#else
		_setStatus("Save to folder not available on this platform.", FlxColor.ORANGE);
		#end
	}

	/** Returns just the filename portion of an absolute path. */
	inline function _fileName(absPath:String):String {
		var norm = absPath.replace("\\", "/");
		var slash = norm.lastIndexOf("/");
		return slash >= 0 ? norm.substr(slash + 1) : norm;
	}

	function _onSaveComplete(_) {
		_setStatus('✓ File saved successfully!', FlxColor.LIME);
		_hasUnsaved = false;
	}

	function _onSaveCancel(_) {
		_setStatus('Save cancelled.', FlxColor.YELLOW);
	}

	function _onSaveError(_) {
		_setStatus('Error saving file!', FlxColor.RED);
	}

	// ──────────────────────────────────────────────────────────── HELPERS

	function _label(x:Float, y:Float, text:String, ?size:Int = 10):FlxText {
		var t = new FlxText(x, y, 0, text, size);
		t.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		return t;
	}

	function _hint(x:Float, y:Float, text:String):FlxText {
		var t = new FlxText(x, y, 300, text, 8);
		t.color = funkin.debug.themes.EditorTheme.current.textSecondary;
		t.wordWrap = true;
		return t;
	}

	function _divider(x:Float, y:Float, label:String):FlxText {
		var t = new FlxText(x, y, 300, label, 9);
		t.color = funkin.debug.themes.EditorTheme.current.accent;
		t.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		return t;
	}

	function _setStatus(msg:String, ?color:FlxColor) {
		statusText.text = msg;
		statusText.color = color ?? funkin.debug.themes.EditorTheme.current.accent;
		statusAccentBar.color = color ?? funkin.debug.themes.EditorTheme.current.accent;
	}

	function _markUnsaved() {
		_hasUnsaved = true;
		if (!statusText.text.startsWith("● "))
			statusText.text = "● " + statusText.text;
	}

	function _isAnyInputFocused():Bool {
		// CoolInputText sets hasFocus when clicked
		for (obj in [
			nameInput,
			authorInput,
			descInput,
			texPathInput,
			holdTexPathInput,
			notesTexPathInput,
			strumsTexPathInput,
			hcTexturePrefix,
			hcStartPrefixInput,
			hcLoopPrefixInput,
			hcEndPrefixInput,
			animNameInput,
			animPrefixInput
		]) {
			if (obj != null && obj.hasFocus)
				return true;
		}
		return false;
	}
}
