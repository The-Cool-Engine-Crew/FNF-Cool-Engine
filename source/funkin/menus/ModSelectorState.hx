package funkin.menus;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.FlxSubState;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.math.FlxMath;
import openfl.display.BitmapData as Bitmap;
import openfl.events.KeyboardEvent as OflKeyboardEvent;
import lime.app.Application as LimeApp;
import mods.ModManager;
import mods.ModManager.ModInfo;
import funkin.cache.FunkinCache;
import funkin.gameplay.notes.NoteTypeManager;
import funkin.scripting.events.EventRegistry;
import funkin.transitions.StateTransition;
import funkin.states.MusicBeatState;
import funkin.data.GlobalConfig;
import funkin.debug.themes.EditorTheme;
import funkin.debug.themes.ThemePickerSubState;
import funkin.menus.MainMenuState;
import funkin.menus.ModImportSubState;
#if sys
import sys.FileSystem;
import sys.io.File;
import funkin.data.SaveData;
#end

using StringTools;

class ModSelectorState extends MusicBeatState {
	// ─── Layout ───────────────────────────────────────────────────────────────
	public static inline var LIST_W = 380;
	public static inline var LIST_ITEM_H = 68;
	static inline var PREVIEW_X = LIST_W + 20;
	static inline var PREVIEW_W = 860;
	static inline var PREVIEW_H = 480;
	static inline var CONTENT_Y = 32; // Y bajo el tab bar

	// ─── Tabs ─────────────────────────────────────────────────────────────────
	var _curTab:Int = 0;

	static final TAB_NAMES = ['MODS', 'CONFIGURATION', 'SYSTEM'];

	var _tabBtns:Array<FlxText> = [];
	var _tabUnderlines:Array<FlxSprite> = [];

	// ─── Cameras ──────────────────────────────────────────────────────────────
	var _camBG:FlxCamera;
	var _camUI:FlxCamera;

	// ─── Shared bg ────────────────────────────────────────────────────────────
	var _bg:FlxSprite;
	var _panelBg:FlxSprite;

	// ─── Tab MODS ─────────────────────────────────────────────────────────────
	var _mods:Array<ModInfo> = [];
	var _cur:Int = 0;
	var _prevCur:Int = -1;
	var _listScrollY:Float = 0;

	var _itemGroup:FlxTypedGroup<ModListItem>;
	var _newBtn:FlxSprite;
	var _newBtnTxt:FlxText;
	var _importBtn:FlxSprite;
	var _importBtnTxt:FlxText;
	var _previewBg:FlxSprite;
	var _previewImg:FlxSprite;
	var _previewNone:FlxSprite;
	var _previewTween:FlxTween = null;

	var _infoName:FlxText;
	var _infoAuthor:FlxText;
	var _infoVersion:FlxText;
	var _infoDesc:FlxText;
	var _infoActive:FlxText;
	var _infoWebsite:FlxText;
	var _infoStartup:FlxText;

	#if cpp
	var _videoHandler:Null<funkin.cutscenes.MP4Handler> = null;
	var _videoSprite:FlxSprite = null;
	#end

	// ─── Tab CONFIG ───────────────────────────────────────────────────────────
	var _cfgItems:Array<{label:FlxText, value:FlxText, key:String}> = [];
	var _cfgCursor:Int = 0;
	var _cfgBar:FlxSprite;
	var _cfgHint:FlxText;

	// ─── Tab SYSTEM ───────────────────────────────────────────────────────────
	var _sysItems:Array<{label:FlxText, value:FlxText, key:String}> = [];
	var _sysCursor:Int = 0;
	var _sysBar:FlxSprite;
	var _sysDescText:FlxText;
	var _sysHint:FlxText;

	static final SYS_DESCS:Array<String> = [
		'Activate editors and debugging tools in the main menu (Ctrl+D)',
		'Visual theme for all editors. [Enter] opens the preset selector'
	];

	// ─── Shared ───────────────────────────────────────────────────────────────
	var _infoKey:FlxText;
	var _statusMsg:FlxText;
	var _inputCooldown:Float = 0;

	static inline var INPUT_CD = 0.13;

	// ─────────────────────────────────────────────────────────────────────────
	// create
	// ─────────────────────────────────────────────────────────────────────────

	override function create() {
		EditorTheme.load();
		ModManager.init();
		_mods = ModManager.installedMods.copy();

		funkin.system.CursorManager.show();
		_setupCameras();
		_buildBG();
		_buildTabBar();
		_buildHelpBar();
		_buildStatusMsg();

		// Tab contents
		_buildModsTab();
		_buildConfigTab();
		_buildSystemTab();

		#if (HSCRIPT_ALLOWED || (LUA_ALLOWED && linc_luajit))
		funkin.scripting.StateScriptHandler.init();
		funkin.scripting.StateScriptHandler.loadStateScripts('ModSelectorState', this);
		funkin.scripting.StateScriptHandler.callOnScripts('onCreate', []);
		#end

		#if mobileC
		addTouchMenuControls(true, false);
		#end

		super.create();

		// Posicionar cursor de lista al mod activo
		if (ModManager.activeMod != null)
			for (i in 0..._mods.length)
				if (_mods[i].id == ModManager.activeMod) {
					_cur = i;
					break;
				}

		if (_mods.length == 0)
			_showEmptyMessage();

		_switchTab(0, true);

		#if (HSCRIPT_ALLOWED || (LUA_ALLOWED && linc_luajit))
		funkin.scripting.StateScriptHandler.refreshStateFields(this);
		funkin.scripting.StateScriptHandler.callOnScripts('postCreate', []);
		#end
	}

	inline function _sndScroll():Void
		FlxG.sound.play(Paths.sound('menus/scrollMenu'));

	inline function _sndConfirm():Void
		FlxG.sound.play(Paths.sound('menus/confirmMenu'));

	function _setupCameras():Void {
		_camBG = new FlxCamera();
		_camBG.bgColor = EditorTheme.current.bgDark;
		FlxG.cameras.add(_camBG, false);
		_camUI = new FlxCamera();
		_camUI.bgColor = FlxColor.TRANSPARENT;
		FlxG.cameras.add(_camUI, false);
	}

	function _buildBG():Void {
		final T = EditorTheme.current;

		_bg = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, T.bgDark);
		_bg.scrollFactor.set();
		_bg.cameras = [_camBG];
		add(_bg);

		_panelBg = new FlxSprite(0, 0).makeGraphic(LIST_W, FlxG.height, T.bgPanel);
		_panelBg.scrollFactor.set();
		_panelBg.cameras = [_camUI];
		add(_panelBg);

		final divider = new FlxSprite(LIST_W, 0).makeGraphic(2, FlxG.height, T.borderColor);
		divider.scrollFactor.set();
		divider.cameras = [_camUI];
		add(divider);
	}

	// ─── Tab Bar ──────────────────────────────────────────────────────────────

	function _buildTabBar():Void {
		final T = EditorTheme.current;
		final startX = LIST_W + 4;
		final tabW = (FlxG.width - startX) / TAB_NAMES.length;

		for (i in 0...TAB_NAMES.length) {
			final tx = startX + i * tabW;
			final lbl = new FlxText(tx, 4, tabW, TAB_NAMES[i]);
			lbl.setFormat(Paths.font('vcr.ttf'), 14, T.textSecondary, CENTER, OUTLINE, T.bgDark);
			lbl.scrollFactor.set();
			lbl.cameras = [_camUI];
			add(lbl);
			_tabBtns.push(lbl);

			final bar = new FlxSprite(tx + 8, 24).makeGraphic(Std.int(tabW - 16), 3, T.accent);
			bar.scrollFactor.set();
			bar.cameras = [_camUI];
			bar.alpha = 0;
			add(bar);
			_tabUnderlines.push(bar);
		}

		// Separador bajo tab bar
		final sep = new FlxSprite(LIST_W + 4, 28).makeGraphic(FlxG.width - LIST_W - 4, 2, T.borderColor);
		sep.scrollFactor.set();
		sep.cameras = [_camUI];
		add(sep);
	}

	// ─── Help bar ─────────────────────────────────────────────────────────────

	function _buildHelpBar():Void {
		final T = EditorTheme.current;

		// Izquierda: controles del panel de mods
		_infoKey = new FlxText(8, FlxG.height - 44, LIST_W - 16,
			'[1][2][3] Tabs   [↑↓] Browse   [Enter] Active\n[X] Enable   [E] Edit   [N] New   [I] Import   [F] Startup');
		_infoKey.setFormat(Paths.font('vcr.ttf'), 11, T.textDim, LEFT);
		_infoKey.scrollFactor.set();
		_infoKey.cameras = [_camUI];
		add(_infoKey);

		// Título arriba del panel izquierdo
		final title = new FlxText(0, 4, LIST_W, 'MODS');
		title.setFormat(Paths.font('vcr.ttf'), 20, T.accent, CENTER, OUTLINE, T.bgDark);
		title.scrollFactor.set();
		title.cameras = [_camUI];
		add(title);
	}

	function _buildStatusMsg():Void {
		_statusMsg = new FlxText(PREVIEW_X + 8, FlxG.height - 62, PREVIEW_W, '');
		_statusMsg.setFormat(Paths.font('vcr.ttf'), 13, EditorTheme.current.success, LEFT);
		_statusMsg.scrollFactor.set();
		_statusMsg.cameras = [_camUI];
		_statusMsg.alpha = 0;
		add(_statusMsg);
	}

	function _showEmptyMessage():Void {
		final msg = new FlxText(16, 80, LIST_W - 32, 'No mods installed.\n\nInstall your mods in\nthe folder mods/\n\n[N] to create a new one.');
		msg.setFormat(Paths.font('vcr.ttf'), 14, EditorTheme.current.textDim, CENTER);
		msg.scrollFactor.set();
		msg.cameras = [_camUI];
		add(msg);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Tab MODS
	// ─────────────────────────────────────────────────────────────────────────

	function _buildModsTab():Void {
		final T = EditorTheme.current;

		// Lista
		_itemGroup = new FlxTypedGroup<ModListItem>();
		_itemGroup.cameras = [_camUI];
		add(_itemGroup);
		for (i in 0..._mods.length) {
			final item = new ModListItem(_mods[i], i);
			item.y = CONTENT_Y + i * (LIST_ITEM_H + 4);
			_itemGroup.add(item);
		}

		// Preview area
		_previewBg = new FlxSprite(PREVIEW_X - 8, CONTENT_Y).makeGraphic(FlxG.width - PREVIEW_X + 8, PREVIEW_H + 10, T.bgPanelAlt);
		_previewBg.scrollFactor.set();
		_previewBg.cameras = [_camUI];
		add(_previewBg);

		_previewImg = new FlxSprite(PREVIEW_X, CONTENT_Y + 4);
		_previewImg.alpha = 0;
		_previewImg.scrollFactor.set();
		_previewImg.cameras = [_camUI];
		add(_previewImg);

		_previewNone = new FlxSprite(PREVIEW_X, CONTENT_Y + 4).makeGraphic(PREVIEW_W, PREVIEW_H, T.bgPanel);
		_previewNone.alpha = 0;
		_previewNone.scrollFactor.set();
		_previewNone.cameras = [_camUI];
		add(_previewNone);

		// Info panel bajo el preview
		final iy = PREVIEW_H + CONTENT_Y + 18;
		final ix = PREVIEW_X;

		_infoActive = new FlxText(ix, iy, PREVIEW_W, '');
		_infoActive.setFormat(Paths.font('vcr.ttf'), 13, T.success, LEFT);
		_infoActive.scrollFactor.set();
		_infoActive.cameras = [_camUI];
		add(_infoActive);

		_infoStartup = new FlxText(ix + 200, iy, PREVIEW_W - 200, '');
		_infoStartup.setFormat(Paths.font('vcr.ttf'), 13, T.warning, RIGHT);
		_infoStartup.scrollFactor.set();
		_infoStartup.cameras = [_camUI];
		add(_infoStartup);

		_infoName = new FlxText(ix, iy + 20, PREVIEW_W, '');
		_infoName.setFormat(Paths.font('vcr.ttf'), 26, T.textPrimary, LEFT, OUTLINE, T.bgDark);
		_infoName.scrollFactor.set();
		_infoName.cameras = [_camUI];
		add(_infoName);

		_infoAuthor = new FlxText(ix, iy + 52, PREVIEW_W - 120, '');
		_infoAuthor.setFormat(Paths.font('vcr.ttf'), 14, T.textSecondary, LEFT);
		_infoAuthor.scrollFactor.set();
		_infoAuthor.cameras = [_camUI];
		add(_infoAuthor);

		_infoVersion = new FlxText(ix + PREVIEW_W - 120, iy + 52, 120, '');
		_infoVersion.setFormat(Paths.font('vcr.ttf'), 13, T.textDim, RIGHT);
		_infoVersion.scrollFactor.set();
		_infoVersion.cameras = [_camUI];
		add(_infoVersion);

		_infoDesc = new FlxText(ix, iy + 74, PREVIEW_W, '');
		_infoDesc.setFormat(Paths.font('vcr.ttf'), 12, T.textSecondary, LEFT);
		_infoDesc.scrollFactor.set();
		_infoDesc.wordWrap = true;
		_infoDesc.cameras = [_camUI];
		add(_infoDesc);

		_infoWebsite = new FlxText(ix, iy + 118, PREVIEW_W, '');
		_infoWebsite.setFormat(Paths.font('vcr.ttf'), 12, T.accent, LEFT);
		_infoWebsite.scrollFactor.set();
		_infoWebsite.cameras = [_camUI];
		add(_infoWebsite);

		// ── Botón "⬆ IMPORT MOD" ──────────────────────────────────────────────
		final importBtnY = FlxG.height - 116;
		_importBtn = new FlxSprite(8, importBtnY).makeGraphic(LIST_W - 16, 28, T.warning);
		_importBtn.scrollFactor.set();
		_importBtn.cameras = [_camUI];
		add(_importBtn);
		_importBtnTxt = new FlxText(8, importBtnY + 6, LIST_W - 16, '⬆ IMPORT MOD');
		_importBtnTxt.setFormat(Paths.font('vcr.ttf'), 13, T.bgDark, CENTER, OUTLINE, T.bgDark);
		_importBtnTxt.bold = true;
		_importBtnTxt.scrollFactor.set();
		_importBtnTxt.cameras = [_camUI];
		add(_importBtnTxt);

		// ── Botón "+ NEW MOD" ─────────────────────────────────────────────────
		final btnY = FlxG.height - 80;
		_newBtn = new FlxSprite(8, btnY).makeGraphic(LIST_W - 16, 30, T.accent);
		_newBtn.scrollFactor.set();
		_newBtn.cameras = [_camUI];
		add(_newBtn);
		_newBtnTxt = new FlxText(8, btnY + 7, LIST_W - 16, '+ NEW MOD');
		_newBtnTxt.setFormat(Paths.font('vcr.ttf'), 13, T.bgDark, CENTER, OUTLINE, T.bgDark);
		_newBtnTxt.bold = true;
		_newBtnTxt.scrollFactor.set();
		_newBtnTxt.cameras = [_camUI];
		add(_newBtnTxt);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Tab CONFIG
	// ─────────────────────────────────────────────────────────────────────────

	function _buildConfigTab():Void {
		final T = EditorTheme.current;
		final gc = GlobalConfig.instance;
		final ix = PREVIEW_X + 12;
		final iy = CONTENT_Y + 8;

		_cfgBar = new FlxSprite(ix - 10, iy).makeGraphic(5, 34, T.accent);
		_cfgBar.scrollFactor.set();
		_cfgBar.cameras = [_camUI];
		add(_cfgBar);

		final defs = [
			{label: 'UI Script', key: 'ui', value: gc.ui},
			{label: 'Note Skin', key: 'noteSkin', value: gc.noteSkin},
			{label: 'Note Splash', key: 'noteSplash', value: gc.noteSplash}
		];

		for (i in 0...defs.length) {
			final d = defs[i];
			final fy = iy + i * 44;

			final lbl = new FlxText(ix, fy + 8, 185, d.label);
			lbl.setFormat(Paths.font('vcr.ttf'), 13, T.textDim, RIGHT);
			lbl.scrollFactor.set();
			lbl.cameras = [_camUI];
			add(lbl);

			final val = new FlxText(ix + 200, fy + 4, PREVIEW_W - 220, d.value);
			val.setFormat(Paths.font('vcr.ttf'), 16, T.textPrimary, LEFT);
			val.scrollFactor.set();
			val.cameras = [_camUI];
			add(val);

			_cfgItems.push({label: lbl, value: val, key: d.key});
		}

		_cfgHint = new FlxText(ix, iy + defs.length * 44 + 10, PREVIEW_W - 24, '[↑↓] Select field   [Enter] Edit value   [F5] Save to disk');
		_cfgHint.setFormat(Paths.font('vcr.ttf'), 12, T.textDim, LEFT);
		_cfgHint.scrollFactor.set();
		_cfgHint.cameras = [_camUI];
		add(_cfgHint);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Tab SISTEMA
	// ─────────────────────────────────────────────────────────────────────────

	function _buildSystemTab():Void {
		final T = EditorTheme.current;
		final ix = PREVIEW_X + 12;
		final iy = CONTENT_Y + 8;

		_sysBar = new FlxSprite(ix - 10, iy).makeGraphic(5, 34, T.accent);
		_sysBar.scrollFactor.set();
		_sysBar.cameras = [_camUI];
		add(_sysBar);

		final defs = [
			{label: 'Developer Mode', key: 'devMode', value: _devModeStr()},
			{label: 'Editor Theme', key: 'theme', value: EditorTheme.current.name.toUpperCase()}
		];

		for (i in 0...defs.length) {
			final d = defs[i];
			final fy = iy + i * 44;

			final lbl = new FlxText(ix, fy + 8, 210, d.label);
			lbl.setFormat(Paths.font('vcr.ttf'), 13, T.textDim, RIGHT);
			lbl.scrollFactor.set();
			lbl.cameras = [_camUI];
			add(lbl);

			final val = new FlxText(ix + 224, fy + 4, PREVIEW_W - 244, d.value);
			val.setFormat(Paths.font('vcr.ttf'), 16, T.textPrimary, LEFT);
			val.scrollFactor.set();
			val.cameras = [_camUI];
			add(val);

			_sysItems.push({label: lbl, value: val, key: d.key});
		}

		// Descripción dinámica
		_sysDescText = new FlxText(ix, iy + defs.length * 44 + 8, PREVIEW_W - 24, '');
		_sysDescText.setFormat(Paths.font('vcr.ttf'), 12, T.textDim, LEFT);
		_sysDescText.scrollFactor.set();
		_sysDescText.wordWrap = true;
		_sysDescText.cameras = [_camUI];
		add(_sysDescText);

		_sysHint = new FlxText(ix, iy + defs.length * 44 + 52, PREVIEW_W - 24, '[↑↓] Browse   [Enter] Change / Open   [F5] Save');
		_sysHint.setFormat(Paths.font('vcr.ttf'), 12, T.textDim, LEFT);
		_sysHint.scrollFactor.set();
		_sysHint.cameras = [_camUI];
		add(_sysHint);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Tab switching
	// ─────────────────────────────────────────────────────────────────────────

	function _switchTab(idx:Int, instant:Bool = false):Void {
		_curTab = idx;
		final T = EditorTheme.current;

		for (i in 0...TAB_NAMES.length) {
			final active = i == idx;
			_tabBtns[i].color = active ? T.accent : T.textSecondary;
			FlxTween.cancelTweensOf(_tabUnderlines[i]);
			if (instant)
				_tabUnderlines[i].alpha = active ? 1 : 0;
			else
				FlxTween.tween(_tabUnderlines[i], {alpha: active ? 1.0 : 0.0}, 0.15, {ease: FlxEase.quadOut});
		}

		final isMods = idx == 0;
		final isConfig = idx == 1;
		final isSys = idx == 2;

		// Tab MODS visibility
		_itemGroup.visible = isMods;
		_previewBg.visible = isMods;
		_previewImg.visible = isMods;
		_previewNone.visible = isMods;
		_infoName.visible = isMods;
		_infoAuthor.visible = isMods;
		_infoVersion.visible = isMods;
		_infoDesc.visible = isMods;
		_infoWebsite.visible = isMods;
		_infoActive.visible = isMods;
		_infoStartup.visible = isMods;
		if (_importBtn != null)
			_importBtn.visible = isMods;
		if (_importBtnTxt != null)
			_importBtnTxt.visible = isMods;

		// Tab CONFIG visibility
		if (_cfgBar != null)
			_cfgBar.visible = isConfig;
		if (_cfgHint != null)
			_cfgHint.visible = isConfig;
		for (it in _cfgItems) {
			it.label.visible = isConfig;
			it.value.visible = isConfig;
		}

		// Tab SISTEMA visibility
		if (_sysBar != null)
			_sysBar.visible = isSys;
		if (_sysDescText != null)
			_sysDescText.visible = isSys;
		if (_sysHint != null)
			_sysHint.visible = isSys;
		for (it in _sysItems) {
			it.label.visible = isSys;
			it.value.visible = isSys;
		}

		if (isMods && _mods.length > 0) {
			_camUI.scroll.y = _listScrollY;
			_selectItem(_cur, instant);
		}
		if (isConfig) {
			_camUI.scroll.y = 0;
			_updateCfgCursor();
			if (_mods.length > 0)
				_refreshConfigForMod(_mods[_cur]);
		}
		if (isSys) {
			_camUI.scroll.y = 0;
			_updateSysCursor();
			_updateSysDesc();
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Update
	// ─────────────────────────────────────────────────────────────────────────

	override function update(elapsed:Float) {
		#if (HSCRIPT_ALLOWED || (LUA_ALLOWED && linc_luajit))
		funkin.scripting.StateScriptHandler.callOnScripts('onUpdate', [elapsed]);
		#end
		super.update(elapsed);

		if (_inputCooldown > 0) {
			_inputCooldown -= elapsed;
			return;
		}

		// Tab keys
		if (FlxG.keys.justPressed.ONE) {
			_inputCooldown = INPUT_CD;
			_sndScroll();
			_switchTab(0);
			return;
		}
		if (FlxG.keys.justPressed.TWO) {
			_inputCooldown = INPUT_CD;
			_sndScroll();
			_switchTab(1);
			return;
		}
		if (FlxG.keys.justPressed.THREE) {
			_inputCooldown = INPUT_CD;
			_sndScroll();
			_switchTab(2);
			return;
		}
		if (controls.BACK) {
			_sndConfirm();
			_goBack();
			return;
		}

		// ── Mouse ────────────────────────────────────────────────────────────
		_handleMouse();

		switch (_curTab) {
			case 0:
				_updateMods(elapsed);
			case 1:
				_updateConfig();
			case 2:
				_updateSystem();
		}

		#if (HSCRIPT_ALLOWED || (LUA_ALLOWED && linc_luajit))
		funkin.scripting.StateScriptHandler.callOnScripts('onUpdatePost', [elapsed]);
		#end
	}

	function _handleMouse():Void {
		// ── Scroll de rueda en lista ─────────────────────────────────────────
		if (_curTab == 0 && FlxG.mouse.wheel != 0 && _mods.length > 0) {
			_cur = Std.int(Math.max(0, Math.min(_mods.length - 1, _cur - FlxG.mouse.wheel)));
			_sndScroll();
			_selectItem(_cur);
		}

		if (!FlxG.mouse.justPressed)
			return;

		// ── Click en tabs ────────────────────────────────────────────────────
		for (i in 0..._tabBtns.length) {
			if (FlxG.mouse.overlaps(_tabBtns[i], _camUI) && i != _curTab) {
				_sndScroll();
				_switchTab(i);
				return;
			}
		}

		// ── Tab MODS ─────────────────────────────────────────────────────────
		if (_curTab == 0) {
			// Botón "⬆ IMPORT MOD"
			if (_importBtn != null && FlxG.mouse.overlaps(_importBtn, _camUI)) {
				_sndConfirm();
				_openImportMod();
				return;
			}
			// Botón "+ NEW MOD"
			if (_newBtn != null && FlxG.mouse.overlaps(_newBtn, _camUI)) {
				_sndConfirm();
				_openCreateMod();
				return;
			}
			// Click en item de lista
			_itemGroup.forEachAlive(function(item:ModListItem) {
				if (FlxG.mouse.overlaps(item, _camUI)) {
					if (item.modIndex == _cur) {
						_sndConfirm();
						_activateMod();
					} else {
						_sndScroll();
						_cur = item.modIndex;
						_selectItem(_cur);
					}
				}
			});
		}

		// ── Tab CONFIG ────────────────────────────────────────────────────────
		if (_curTab == 1) {
			for (i in 0..._cfgItems.length) {
				if (FlxG.mouse.overlaps(_cfgItems[i].value, _camUI)) {
					if (i == _cfgCursor) {
						_sndScroll();
						_editCfgField();
					} else {
						_sndScroll();
						_cfgCursor = i;
						_updateCfgCursor();
					}
					return;
				}
			}
		}

		// ── Tab SYSTEM ────────────────────────────────────────────────────────
		if (_curTab == 2) {
			for (i in 0..._sysItems.length) {
				if (FlxG.mouse.overlaps(_sysItems[i].value, _camUI)) {
					if (i == _sysCursor) {
						_sndConfirm();
						_activateSysItem();
					} else {
						_sndScroll();
						_sysCursor = i;
						_updateSysCursor();
						_updateSysDesc();
					}
					return;
				}
			}
		}
	}

	// ─── Mods update ─────────────────────────────────────────────────────────

	function _updateMods(elapsed:Float):Void {
		if (FlxG.keys.justPressed.N) {
			_openCreateMod();
			return;
		}
		if (FlxG.keys.justPressed.I) {
			_openImportMod();
			return;
		}
		if (_mods.length == 0)
			return;

		if (FlxG.keys.justPressed.UP || FlxG.keys.justPressed.W) {
			_inputCooldown = INPUT_CD;
			_sndScroll();
			_cur = (_cur - 1 + _mods.length) % _mods.length;
			_selectItem(_cur);
		} else if (FlxG.keys.justPressed.DOWN || FlxG.keys.justPressed.S) {
			_inputCooldown = INPUT_CD;
			_sndScroll();
			_cur = (_cur + 1) % _mods.length;
			_selectItem(_cur);
		} else if (controls.ACCEPT) {
			_inputCooldown = 0.25;
			_sndConfirm();
			_activateMod();
		} else if (FlxG.keys.justPressed.X || FlxG.keys.justPressed.BACKSPACE) {
			_inputCooldown = INPUT_CD;
			_sndScroll();
			_toggleEnable();
		} else if (FlxG.keys.justPressed.E) {
			_inputCooldown = 0.2;
			_sndScroll();
			_openEditMod(_mods[_cur]);
		} else if (FlxG.keys.justPressed.F) {
			_inputCooldown = INPUT_CD;
			_sndScroll();
			_toggleStartup();
		}

		// Scroll suave
		final vis = Math.floor((FlxG.height - CONTENT_Y - 60) / (LIST_ITEM_H + 4)) - 1;
		if (_mods.length > vis) {
			final target = Math.max(0, (_cur - Math.floor(vis * 0.5)) * (LIST_ITEM_H + 4));
			_listScrollY = FlxMath.lerp(_listScrollY, target, Math.min(elapsed * 10, 1.0));
			_camUI.scroll.y = _listScrollY;
		}
	}

	// ─── Config update ────────────────────────────────────────────────────────

	function _updateConfig():Void {
		if (FlxG.keys.justPressed.UP || FlxG.keys.justPressed.W) {
			_inputCooldown = INPUT_CD;
			_sndScroll();
			_cfgCursor = (_cfgCursor - 1 + _cfgItems.length) % _cfgItems.length;
			_updateCfgCursor();
		} else if (FlxG.keys.justPressed.DOWN || FlxG.keys.justPressed.S) {
			_inputCooldown = INPUT_CD;
			_sndScroll();
			_cfgCursor = (_cfgCursor + 1) % _cfgItems.length;
			_updateCfgCursor();
		} else if (controls.ACCEPT) {
			_inputCooldown = 0.2;
			_sndScroll();
			_editCfgField();
		} else if (FlxG.keys.justPressed.F5) {
			_sndConfirm();
			_saveCfg();
		}
	}

	function _updateCfgCursor():Void {
		final T = EditorTheme.current;
		final iy = CONTENT_Y + 8;
		FlxTween.cancelTweensOf(_cfgBar);
		FlxTween.tween(_cfgBar, {y: iy + _cfgCursor * 44 + 6}, 0.12, {ease: FlxEase.expoOut});
		for (i in 0..._cfgItems.length)
			_cfgItems[i].value.color = i == _cfgCursor ? T.accent : T.textPrimary;
	}

	/**
	 * Lee el global.json del mod indicado (por su carpeta) y actualiza
	 * los campos del tab CONFIG con esos valores.
	 * Si el mod no tiene global.json, carga el de assets/ base.
	 * Así el CONFIG tab siempre muestra la config del mod seleccionado,
	 * no la del mod activo.
	 */
	function _refreshConfigForMod(mod:ModInfo):Void {
		#if sys
		var ui = 'default';
		var noteSkin = 'default';
		var noteSplash = 'Default';

		// Intentar cargar desde la carpeta del mod seleccionado
		final modCfgPath = '${mod.folder}/data/config/global.json';
		final baseCfgPath = 'assets/data/config/global.json';
		final path = sys.FileSystem.exists(modCfgPath) ? modCfgPath : sys.FileSystem.exists(baseCfgPath) ? baseCfgPath : null;

		if (path != null) {
			try {
				final d:Dynamic = haxe.Json.parse(sys.io.File.getContent(path));
				if (d.ui != null)
					ui = Std.string(d.ui);
				if (d.noteSkin != null)
					noteSkin = Std.string(d.noteSkin);
				if (d.noteSplash != null)
					noteSplash = Std.string(d.noteSplash);
			} catch (_) {}
		}

		for (it in _cfgItems)
			switch (it.key) {
				case 'ui':
					it.value.text = ui;
				case 'noteSkin':
					it.value.text = noteSkin;
				case 'noteSplash':
					it.value.text = noteSplash;
			}
		#end
	}

	function _editCfgField():Void {
		final item = _cfgItems[_cfgCursor];
		openSubState(new SimpleTextInputSubState('Editing "${item.label.text}"', item.value.text, v -> item.value.text = v, v -> item.value.text = v));
	}

	function _saveCfg():Void {
		final gc = GlobalConfig.instance;
		for (it in _cfgItems) {
			switch (it.key) {
				case 'ui':
					gc.ui = it.value.text;
				case 'noteSkin':
					gc.noteSkin = it.value.text;
				case 'noteSplash':
					gc.noteSplash = it.value.text;
			}
		}
		gc.save();
		GlobalConfig.reload();
		_showStatus('✓ GlobalConfig saved.', true);
	}

	// ─── System update ────────────────────────────────────────────────────────

	function _updateSystem():Void {
		if (FlxG.keys.justPressed.UP || FlxG.keys.justPressed.W) {
			_inputCooldown = INPUT_CD;
			_sndScroll();
			_sysCursor = (_sysCursor - 1 + _sysItems.length) % _sysItems.length;
			_updateSysCursor();
			_updateSysDesc();
		} else if (FlxG.keys.justPressed.DOWN || FlxG.keys.justPressed.S) {
			_inputCooldown = INPUT_CD;
			_sndScroll();
			_sysCursor = (_sysCursor + 1) % _sysItems.length;
			_updateSysCursor();
			_updateSysDesc();
		} else if (controls.ACCEPT) {
			_inputCooldown = 0.25;
			_sndConfirm();
			_activateSysItem();
		} else if (FlxG.keys.justPressed.F5) {
			_sndConfirm();
			SaveData.flush();
			_showStatus('✓ Saved.', true);
		}
	}

	function _updateSysCursor():Void {
		final T = EditorTheme.current;
		final iy = CONTENT_Y + 8;
		FlxTween.cancelTweensOf(_sysBar);
		FlxTween.tween(_sysBar, {y: iy + _sysCursor * 44 + 6}, 0.12, {ease: FlxEase.expoOut});
		for (i in 0..._sysItems.length)
			_sysItems[i].value.color = i == _sysCursor ? T.accent : T.textPrimary;
	}

	function _updateSysDesc():Void {
		if (_sysDescText == null)
			return;
		_sysDescText.text = SYS_DESCS[_sysCursor] ?? '';
	}

	function _activateSysItem():Void {
		final item = _sysItems[_sysCursor];
		switch (item.key) {
			case 'devMode':
				mods.ModManager.developerMode = !mods.ModManager.developerMode;
				item.value.text = _devModeStr();
				_showStatus(mods.ModManager.developerMode ? '⚙ Developer Mode ACTIVATED' : '⚙ Developer Mode desactivated', true);
			case 'theme':
				final sub = new ThemePickerSubState(function() {
					item.value.text = EditorTheme.current.name.toUpperCase();
					_showStatus('✓ Theme "${EditorTheme.current.name}" applied.', true);
				});
				funkin.system.CursorManager.show();
				openSubState(sub);
		}
	}

	// ─── Mods actions ─────────────────────────────────────────────────────────

	function _selectItem(idx:Int, instant:Bool = false):Void {
		if (idx == _prevCur && !instant)
			return;
		_prevCur = idx;
		_itemGroup.forEachAlive(function(it:ModListItem) it.setSelected(it.modIndex == idx));
		final mod = _mods[idx];
		_updateInfo(mod);
		_loadPreview(mod, instant);
		// Refrescar CONFIG tab si está visible para mostrar la config de este mod
		if (_curTab == 1)
			_refreshConfigForMod(mod);
	}

	function _updateInfo(mod:ModInfo):Void {
		final T = EditorTheme.current;
		_infoName.text = mod.name;
		_infoAuthor.text = mod.author.length > 0 ? 'by ' + mod.author : '';
		_infoVersion.text = 'v' + mod.version;
		_infoDesc.text = mod.description;
		_infoWebsite.text = mod.website.length > 0 ? '🌐 ' + mod.website : '';
		final isActive = ModManager.activeMod == mod.id;
		_infoActive.text = isActive ? '✓ ACTIVE' : (!mod.enabled ? '✗ DISABLED' : '');
		_infoActive.color = isActive ? T.success : T.error;
		_infoStartup.text = ModManager.startupMod == mod.id ? '⚑ STARTUP MOD' : '';
		_infoStartup.color = T.warning;
	}

	function _loadPreview(mod:ModInfo, instant:Bool = false):Void {
		if (_previewTween != null) {
			_previewTween.cancel();
			_previewTween = null;
		}
		#if cpp _stopVideo(); #end

		switch (ModManager.previewType(mod.id)) {
			case VIDEO:
				_previewImg.alpha = 0;
				_previewNone.makeGraphic(PREVIEW_W, PREVIEW_H, mod.color | 0xFF000000);
				_previewNone.alpha = 1;
				#if cpp _playVideo(ModManager.previewVideo(mod.id)); #end
			case IMAGE:
				_previewNone.alpha = 0;
				#if cpp _stopVideo(); #end
				_loadPreviewImage(mod, instant);
			case NONE:
				_previewImg.alpha = 0;
				#if cpp _stopVideo(); #end
				_previewNone.makeGraphic(PREVIEW_W, PREVIEW_H, mod.color | 0xFF000000);
				if (instant)
					_previewNone.alpha = 1;
				else {
					_previewNone.alpha = 0;
					_previewTween = FlxTween.tween(_previewNone, {alpha: 1}, 0.3, {ease: FlxEase.quadOut});
				}
		}
	}

	function _loadPreviewImage(mod:ModInfo, instant:Bool):Void {
		final imgPath = ModManager.previewImage(mod.id);
		if (imgPath == null) {
			_previewImg.alpha = 0;
			return;
		}
		try {
			final bmp = Bitmap.fromFile(imgPath);
			if (bmp == null) {
				_previewImg.alpha = 0;
				return;
			}
			final scale = Math.min(PREVIEW_W / bmp.width, PREVIEW_H / bmp.height);
			_previewImg.loadGraphic(bmp);
			_previewImg.setGraphicSize(Std.int(bmp.width * scale), Std.int(bmp.height * scale));
			_previewImg.updateHitbox();
			_previewImg.x = PREVIEW_X + (PREVIEW_W - _previewImg.width) * 0.5;
			_previewImg.y = CONTENT_Y + 4 + (PREVIEW_H - _previewImg.height) * 0.5;
			_previewImg.antialiasing = true;
			if (instant)
				_previewImg.alpha = 1;
			else {
				_previewImg.alpha = 0;
				_previewTween = FlxTween.tween(_previewImg, {alpha: 1}, 0.35, {ease: FlxEase.quadOut});
			}
		} catch (e:Dynamic) {
			trace('[ModSelectorState] Preview error: $e');
			_previewImg.alpha = 0;
		}
	}

	#if cpp
	function _playVideo(path:Null<String>):Void {
		if (path == null)
			return;
		_stopVideo();
		try {
			if (_videoSprite == null) {
				_videoSprite = new FlxSprite(PREVIEW_X, CONTENT_Y + 4);
				_videoSprite.cameras = [_camUI];
				_videoSprite.scrollFactor.set();
				_videoSprite.alpha = 0;
				add(_videoSprite);
			}

			_videoHandler = new funkin.cutscenes.MP4Handler();
			_videoHandler.playMP4(path, true, true, _videoSprite, false, false);

			// Fade in once we have a frame.
			new flixel.util.FlxTimer().start(0.4, function(_) {
				if (_videoSprite != null) {
					_videoSprite.setGraphicSize(PREVIEW_W, PREVIEW_H);
					_videoSprite.updateHitbox();
					flixel.tweens.FlxTween.tween(_videoSprite, {alpha: 1}, 0.3, {ease: flixel.tweens.FlxEase.quadOut});
				}
			});
		} catch (e:Dynamic) {
			trace('[ModSelectorState] Video error: $e');
		}
	}

	function _stopVideo():Void {
		if (_videoHandler != null) {
			_videoHandler.finishCallback = null;
			try
				_videoHandler.kill()
			catch (_:Dynamic) {}
			_videoHandler = null;
		}
		if (_videoSprite != null)
			_videoSprite.alpha = 0;
	}
	#end

	function _activateMod():Void {
		if (_mods.length == 0)
			return;
		final mod = _mods[_cur];
		if (ModManager.activeMod == mod.id)
			ModManager.deactivate();
		else
			ModManager.setActive(mod.id);

		#if cpp _stopVideo(); #end

		// ── Limpieza completa de estado antes del cambio de mod ──────────────
		// El orden importa: audio primero (libera FlxSounds activos), luego
		// assets (texturas/atlas/bitmaps), luego caches de datos (note types,
		// events). Por último reset de estado estático residual.

		// 1. Audio: para y libera todos los FlxSounds de la sesión anterior.
		funkin.audio.CoreAudio.flushForModSwitch();

		// 2. Assets visuales: atlasCache + PathsCache + FlxG.bitmap + OpenFL cache.
		Paths.forceClearCache();
		// ── FIX: limpiar explícitamente el cache de paths de mod ─────────────
		// forceClearCache() → PathsCache.destroy() ya limpia _modPathCache (fix),
		// pero esta llamada doble garantiza que si se llama desde otro lugar que
		// no pase por destroy(), el cache tampoco quede sucio con rutas del mod
		// anterior. getSparrowAtlas y similares resolverán correctamente al nuevo
		// mod sin necesitar reiniciar el juego.
		funkin.cache.PathsCache.instance.clearModPathCache();

		// 3. Permanentes de OpenFL (fonts, texturas UI marcadas como permanentes
		//    del mod anterior). FunkinCache.clearAll() va más allá de forceClearCache()
		//    que solo llama PathsCache.destroy() — también limpia _permanentBitmaps
		//    y _permanentSounds del lado AssetCache.
		if (FunkinCache.instance != null)
			FunkinCache.instance.clearAll();

		// 4. Cache de tipos de nota: _types, _scripts, _frames, _configs.
		//    Sin esto, un note type con el mismo nombre en el mod anterior
		//    podría colarse porque _configs lo tiene en memoria.
		NoteTypeManager.clearCache();

		// 5. Definiciones de eventos personalizados del mod anterior.
		//    EventRegistry.reload() re-escanea la carpeta del nuevo mod activo.
		EventRegistry.reload();

		// 6. Reset del stage estático: PlayState.create() lo sobreescribe, pero
		//    el valor anterior puede afectar resoluciones de Paths intermedias
		//    durante CacheState (ej: Paths.stageSprite busca en currentStage).
		Paths.currentStage = 'stage_week1';

		// 7. Reset del estado estático de FreeplayState.
		//    freeplayData contiene la songlist del mod anterior (puede ser grande).
		//    coolColors guarda los colores parseados de esas canciones.
		//    curSelected/curDifficulty pueden quedar fuera de rango en el nuevo mod.
		//    Sin este reset, al entrar al FreeplayState del nuevo mod se mostraría
		//    la lista anterior hasta que loadSongsData() la sobreescriba, y la RAM
		//    del mod anterior no se liberaría hasta el primer GC tras el create().
		funkin.menus.FreeplayState.resetStaticState();

		// 8. JSONs y paths de personajes del mod anterior.
		//    _dataCache/_pathCache guardan el JSON parseado y la ruta resuelta por
		//    ModCompatLayer para cada personaje. Sin limpiarlos, un personaje con el
		//    mismo nombre en el nuevo mod usaría el JSON del anterior.
		//    releasePrecachePool() destruye dummies de precacheo que pueden retener
		//    atlas de VRAM del mod viejo.
		funkin.gameplay.objects.character.Character.clearCharCaches();

		// 9. JSONs de stages del mod anterior.
		//    Stage._dataCache guarda el JSON parseado por nombre de stage.
		//    Sin esto, stages con el mismo nombre en mods distintos colisionan.
		funkin.gameplay.objects.stages.Stage.clearStageCache();

		// 10. Lista de personajes y stages disponibles.
		//     CharacterList escanea el sistema de archivos una sola vez y cachea el
		//     resultado. Al cambiar de mod, la lista es obsoleta (nuevo mod puede
		//     tener personajes distintos). reload() forza el re-escaneo.
		funkin.gameplay.objects.character.CharacterList.reload();

		// 11. Sistema de noteskins.
		//     NoteSkinSystem cachea skins/splashes y los scripts asociados.
		//     forceReinit() resetea `initialized` + `_lastInitMod` para que el
		//     siguiente acceso haga un escaneo limpio del nuevo mod.
		funkin.gameplay.notes.NoteSkinSystem.forceReinit();

		// 12. Configuración de ratings (ventanas de timing, nombres, display).
		//     RatingManager la carga desde ratings.json del mod activo.
		//     Sin reload(), el nuevo mod heredaría la config del anterior.
		funkin.gameplay.RatingManager.reload();

		// 13. Datos de créditos.
		//     CreditsDataHandler los cachea hasta la primera llamada a reload().
		//     Sin esto, los créditos del mod anterior aparecen en el nuevo mod.
		funkin.menus.credits.CreditsDataHandler.reload();

		// 15. Animaciones de intro de menús.
		//     TitleState.initialized evita reproducir el intro dos veces en la
		//     misma sesión. Al cambiar de mod queremos que el nuevo mod muestre
		//     su propio intro (puede tener TitleState scriptado distinto).
		//     MainMenuState.firstStart / finishedFunnyMove controlan la animación
		//     de entrada del menú principal — igual, debe resetearse para el nuevo mod.
		funkin.menus.TitleState.initialized = false;
		funkin.menus.MainMenuState.firstStart = true;
		funkin.menus.MainMenuState.finishedFunnyMove = false;

		// 16. songInfo estático del FreeplayEditorState.
		//     Sin reset apunta a la lista del mod anterior; la próxima apertura
		//     del editor mostraría canciones del mod viejo.
		funkin.debug.editors.FreeplayEditorState.songInfo = null;

		// 17. weekUnlocked del StoryMenuState.
		//     Array estático con el estado de bloqueo de cada semana.
		//     buildWeeksFromJSON() lo reconstruye en cada create(), pero si por
		//     algún motivo falla antes, un array stale del mod anterior podría
		//     dejar weeks bloqueadas/desbloqueadas incorrectamente.
		funkin.menus.StoryMenuState.weekUnlocked = [];

		// FIX Bug #2 — eliminada la segunda llamada a Paths.clearAllCaches() que
		// existía aquí. Paths.forceClearCache() (línea ~1077) ya ejecuta
		// clearAllCaches() → PathsCache.destroy() con toda la limpieza necesaria.
		// La segunda llamada iteraba mapas ya vacíos (trabajo redundante) y
		// oscurecía qué cleanup realmente ocurrió durante el cambio de mod.

		#if cpp cpp.vm.Gc.run(true); #end
		#if hl hl.Gc.major(); #end

		// Fade en la cámara visible (_camBG cubre toda la pantalla)
		// y luego switchState a CacheState — NO resetGame(), que deja
		// el estado de plugins en un estado potencialmente inconsistente.
		funkin.system.CursorManager.hide();
		_camBG.fade(flixel.util.FlxColor.BLACK, 0.4, false, function() {
			funkin.transitions.StateTransition.switchState(new CacheState());
		});
	}

	function _toggleEnable():Void {
		if (_mods.length == 0)
			return;
		ModManager.toggleEnabled(_mods[_cur].id);
		_updateInfo(_mods[_cur]);
		_itemGroup.forEachAlive(function(it:ModListItem) it.refresh());
	}

	function _toggleStartup():Void {
		if (_mods.length == 0)
			return;
		final mod = _mods[_cur];
		if (ModManager.startupMod == mod.id)
			ModManager.setStartupMod(null);
		else
			ModManager.setStartupMod(mod.id);
		_updateInfo(mod);
		_itemGroup.forEachAlive(function(it:ModListItem) it.refresh());
	}

	function _openEditMod(mod:ModInfo):Void {
		openSubState(new ModEditSubState(mod, false, function(saved:ModInfo) {
			for (i in 0..._mods.length)
				if (_mods[i].id == saved.id) {
					_mods[i] = saved;
					break;
				}
			_prevCur = -1;
			_selectItem(_cur, true);
			_itemGroup.forEachAlive(function(it:ModListItem) it.refresh());
		}));
	}

	function _openImportMod():Void {
		funkin.system.CursorManager.show();
		openSubState(new ModImportSubState(function() {
			// Refresh mod list after successful import
			ModManager.init();
			_mods = ModManager.installedMods.copy();
			_itemGroup.forEachAlive(function(it:ModListItem) it.kill());
			_itemGroup.clear();
			for (i in 0..._mods.length) {
				final item = new ModListItem(_mods[i], i);
				item.y = CONTENT_Y + i * (LIST_ITEM_H + 4);
				_itemGroup.add(item);
			}
			_prevCur = -1;
			if (_mods.length > 0)
				_selectItem(_cur = 0, true);
			_showStatus('✓ Mod imported successfully.', true);
		}));
	}

	function _openCreateMod():Void {
		funkin.system.CursorManager.show();
		final empty:ModInfo = {
			id: '',
			name: 'New Mod',
			description: '',
			author: '',
			version: '1.0.0',
			priority: 0,
			color: 0xFF6633CC,
			website: '',
			enabled: true,
			startupDefault: false,
			folder: '',
			gamebananaid: null
		};
		openSubState(new ModEditSubState(empty, true, function(created:ModInfo) {
			ModManager.init();
			_mods = ModManager.installedMods.copy();
			_itemGroup.forEachAlive(function(it:ModListItem) it.kill());
			_itemGroup.clear();
			for (i in 0..._mods.length) {
				final item = new ModListItem(_mods[i], i);
				item.y = CONTENT_Y + i * (LIST_ITEM_H + 4);
				_itemGroup.add(item);
			}
			for (i in 0..._mods.length)
				if (_mods[i].id == created.id) {
					_cur = i;
					break;
				}
			_prevCur = -1;
			if (_mods.length > 0)
				_selectItem(_cur, true);
		}));
	}

	// ─── Helpers ──────────────────────────────────────────────────────────────

	inline function _boolStr(v:Dynamic):String
		return (v == true) ? 'ON' : 'OFF';

	inline function _devModeStr():String
		return mods.ModManager.developerMode ? 'ACTIVATED  ⚙' : 'OFF';

	function _showStatus(msg:String, ok:Bool):Void {
		final T = EditorTheme.current;
		_statusMsg.text = msg;
		_statusMsg.color = ok ? T.success : T.error;
		FlxTween.cancelTweensOf(_statusMsg);
		_statusMsg.alpha = 1;
		FlxTween.tween(_statusMsg, {alpha: 0}, 0.5, {startDelay: 2.0, ease: FlxEase.quadIn});
	}

	function _goBack():Void {
		#if cpp _stopVideo(); #end
		final target = funkin.scripting.ScriptBridge.resolveState('MainMenuState') ?? new MainMenuState();
		StateTransition.switchState(target);
	}

	override function destroy() {
		#if (HSCRIPT_ALLOWED || (LUA_ALLOWED && linc_luajit))
		funkin.scripting.StateScriptHandler.callOnScripts('onDestroy', []);
		funkin.scripting.StateScriptHandler.clearStateScripts();
		#end
		#if cpp _stopVideo(); #end
		super.destroy();
	}
}

// ═══════════════════════════════════════════════════════════════════════════
//  ModListItem
// ═══════════════════════════════════════════════════════════════════════════

class ModListItem extends FlxSprite {
	public var modIndex:Int;

	var _mod:ModInfo;
	var _bg:FlxSprite;
	var _icon:FlxSprite;
	var _nameTxt:FlxText;
	var _authorTxt:FlxText;
	var _enableDot:FlxSprite;
	var _startupDot:FlxSprite;

	static inline var W = ModSelectorState.LIST_W - 16;
	static inline var H = ModSelectorState.LIST_ITEM_H;

	public function new(mod:ModInfo, index:Int) {
		super(8, 0);
		_mod = mod;
		modIndex = index;
		final T = EditorTheme.current;

		_bg = new FlxSprite(0, 0);
		_bg.scrollFactor.set();

		// Icono
		_icon = new FlxSprite(6, (H - 40) * 0.5);
		_icon.scrollFactor.set();
		#if sys
		final iconP = ModManager.iconPath(mod.id);
		if (iconP != null) {
			final bmp = openfl.display.BitmapData.fromFile(iconP);
			if (bmp != null) {
				_icon.loadGraphic(flixel.graphics.FlxGraphic.fromBitmapData(bmp));
				_icon.setGraphicSize(40, 40);
				_icon.updateHitbox();
			} else
				_icon = null;
		} else
			_icon = null;
		#else
		_icon = null;
		#end

		final offX:Int = _icon != null ? 52 : 10;

		_nameTxt = new FlxText(offX, 10, W - offX - 30, mod.name);
		_nameTxt.setFormat(Paths.font('vcr.ttf'), 16, T.textPrimary, LEFT, OUTLINE, T.bgDark);
		_nameTxt.scrollFactor.set();

		_authorTxt = new FlxText(offX, 32, W - offX - 30, mod.author.length > 0 ? 'By ' + mod.author : '');
		_authorTxt.setFormat(Paths.font('vcr.ttf'), 11, T.textSecondary, LEFT);
		_authorTxt.scrollFactor.set();

		_enableDot = new FlxSprite(W - 26, H * 0.5 - 6).makeGraphic(12, 12, FlxColor.TRANSPARENT);
		_enableDot.scrollFactor.set();
		_startupDot = new FlxSprite(W - 14, H * 0.5 - 6).makeGraphic(8, 8, FlxColor.TRANSPARENT);
		_startupDot.scrollFactor.set();

		_refresh();
	}

	override public function draw():Void {
		_dc(_bg);
		if (_icon != null)
			_dc(_icon);
		_dc(_nameTxt);
		_dc(_authorTxt);
		_dc(_enableDot);
		_dc(_startupDot);
	}

	inline function _dc(s:flixel.FlxBasic):Void {
		if (s == null || !s.alive || !s.visible)
			return;
		final spr = cast(s, flixel.FlxObject);
		final ox = spr.x;
		final oy = spr.y;
		spr.x += x;
		spr.y += y;
		spr.cameras = cameras;
		s.draw();
		spr.x = ox;
		spr.y = oy;
	}

	public function setSelected(sel:Bool):Void {
		final T = EditorTheme.current;
		FlxTween.cancelTweensOf(this);
		FlxTween.tween(this, {alpha: sel ? 1.0 : (ModManager.activeMod == _mod.id ? 0.85 : 0.55)}, 0.15, {ease: FlxEase.quadOut});
		_bg.makeGraphic(W, H, sel ? (_mod.color | 0xCC000000) : T.bgPanel);
	}

	public function refresh():Void
		_refresh();

	function _refresh():Void {
		final T = EditorTheme.current;
		final en = ModManager.isEnabled(_mod.id);
		final st = ModManager.startupMod == _mod.id;
		_nameTxt.color = en ? T.textPrimary : T.textDim;
		_authorTxt.color = en ? T.textSecondary : T.textDim;
		_enableDot.makeGraphic(12, 12, en ? T.success : T.error);
		_startupDot.makeGraphic(8, 8, st ? T.warning : FlxColor.TRANSPARENT);
	}
}

// ═══════════════════════════════════════════════════════════════════════════
//  SimpleTextInputSubState
// ═══════════════════════════════════════════════════════════════════════════

class SimpleTextInputSubState extends funkin.states.MusicBeatSubstate {
	var _title:String;
	var _text:String;
	var _onDone:String->Void;
	var _onChange:String->Void;
	var _inputTxt:FlxText;

	public function new(title:String, initial:String, onDone:String->Void, ?onChange:String->Void) {
		super();
		_title = title;
		_text = initial;
		_onDone = onDone;
		_onChange = onChange;
	}

	override function create() {
		// Cámara propia para renderizarse sobre camUI del estado padre
		final camSub = new flixel.FlxCamera();
		camSub.bgColor = flixel.util.FlxColor.TRANSPARENT;
		FlxG.cameras.add(camSub, false);
		cameras = [camSub];

		final T = EditorTheme.current;
		final pw = 640;
		final ph = 160;
		final px = (FlxG.width - pw) / 2;
		final py = (FlxG.height - ph) / 2;

		final bg = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, 0xBB000000);
		bg.scrollFactor.set();
		bg.alpha = 0;
		add(bg);
		FlxTween.tween(bg, {alpha: 1}, 0.15, {ease: FlxEase.quadOut});

		final panel = new FlxSprite(px, py).makeGraphic(pw, ph, T.bgPanel);
		panel.scrollFactor.set();
		add(panel);

		final bord = new FlxSprite(px, py).makeGraphic(pw, 3, T.accent);
		bord.scrollFactor.set();
		add(bord);

		final lbl = new FlxText(px, py + 8, pw, _title);
		lbl.setFormat(Paths.font('vcr.ttf'), 14, T.textSecondary, CENTER);
		lbl.scrollFactor.set();
		add(lbl);

		final iBg = new FlxSprite(px + 20, py + 44).makeGraphic(pw - 40, 42, T.bgPanelAlt);
		iBg.scrollFactor.set();
		add(iBg);

		_inputTxt = new FlxText(px + 28, py + 50, pw - 56, _text + '|');
		_inputTxt.setFormat(Paths.font('vcr.ttf'), 18, T.textPrimary, LEFT);
		_inputTxt.scrollFactor.set();
		add(_inputTxt);

		final hint = new FlxText(px, py + ph - 28, pw, '[Enter] Confirm   [Esc] Cancel');
		hint.setFormat(Paths.font('vcr.ttf'), 12, T.textDim, CENTER);
		hint.scrollFactor.set();
		add(hint);

		// Escucha nativa via Lime — independiente de foco.
		// CRÍTICO: textInputEnabled = true activa SDL_StartTextInput() en desktop,
		// sin esto onTextInput nunca dispara y no se puede escribir nada.
		LimeApp.current.window.textInputEnabled = true;
		LimeApp.current.window.onTextInput.add(_onLimeTextInput);
		FlxG.stage.addEventListener(OflKeyboardEvent.KEY_DOWN, _onKeyDown);

		super.create();
	}

	function _onLimeTextInput(text:String):Void {
		_text += text;
		_inputTxt.text = _text + '|';
		if (_onChange != null)
			_onChange(_text);
	}

	function _onKeyDown(e:OflKeyboardEvent):Void {
		if (e.keyCode == 8 && _text.length > 0) {
			_text = _text.substr(0, _text.length - 1);
			_inputTxt.text = _text + '|';
			if (_onChange != null)
				_onChange(_text);
		}
	}

	override function destroy() {
		if (cameras != null && cameras.length > 0) {
			final cam = cameras[0];
			if (cam != null)
				FlxG.cameras.remove(cam, true);
		}
		LimeApp.current.window.textInputEnabled = false;
		LimeApp.current.window.onTextInput.remove(_onLimeTextInput);
		FlxG.stage.removeEventListener(OflKeyboardEvent.KEY_DOWN, _onKeyDown);
		super.destroy();
	}

	override function update(elapsed:Float) {
		super.update(elapsed);
		if (controls.BACK) {
			FlxG.sound.play(Paths.sound('menus/scrollMenu'));
			close();
			return;
		}
		if (controls.ACCEPT) {
			FlxG.sound.play(Paths.sound('menus/confirmMenu'));
			_onDone(_text);
			close();
			return;
		}
	}

	// _kc ya no se necesita — se mantiene por compatibilidad si algo lo llama
	function _kc(key:flixel.input.keyboard.FlxKey, sh:Bool):String {
		final n = key.toString();
		if (n.length == 1)
			return sh ? n.toUpperCase() : n.toLowerCase();
		return switch (key) {
			case SPACE: ' ';
			case MINUS: sh ? '_' : '-';
			case PERIOD: sh ? '>' : '.';
			case SLASH: sh ? '?' : '/';
			case SEMICOLON: sh ? ':' : ';';
			case NUMPADZERO | ZERO: '0';
			case NUMPADONE | ONE: '1';
			case NUMPADTWO | TWO: '2';
			case NUMPADTHREE | THREE: '3';
			case NUMPADFOUR | FOUR: '4';
			case NUMPADFIVE | FIVE: '5';
			case NUMPADSIX | SIX: '6';
			case NUMPADSEVEN | SEVEN: '7';
			case NUMPADEIGHT | EIGHT: '8';
			case NUMPADNINE | NINE: '9';
			default: '';
		};
	}
}

// ═══════════════════════════════════════════════════════════════════════════
//  ModEditSubState — con colores de EditorTheme
// ═══════════════════════════════════════════════════════════════════════════

class ModEditSubState extends funkin.states.MusicBeatSubstate {
	var _mod:ModInfo;
	var _isCreate:Bool;
	var _onDone:ModInfo->Void;

	var _fields:Array<{label:String, key:String, value:String}> = [];
	var _fieldValues:Array<FlxText> = [];
	var _cursor:FlxSprite;
	var _curField:Int = 0;
	var _editMode:Bool = false;
	var _editingText:String = '';
	var _editBg:FlxSprite;
	var _editText:FlxText;
	var _hint:FlxText;

	var _panelW:Int = 700;
	var _panelH:Int = 580;
	var _panelX:Float;
	var _panelY:Float;
	var _saveBtn:FlxSprite;
	var _closeBtn:FlxSprite;

	public function new(mod:ModInfo, isCreate:Bool, onDone:ModInfo->Void) {
		super();
		_mod = Reflect.copy(mod);
		_isCreate = isCreate;
		_onDone = onDone;
	}

	override function create() {
		// Cámara propia para renderizarse sobre camUI del estado padre
		final camSub = new flixel.FlxCamera();
		camSub.bgColor = flixel.util.FlxColor.TRANSPARENT;
		FlxG.cameras.add(camSub, false);
		cameras = [camSub];

		final T = EditorTheme.current;
		_panelX = (FlxG.width - _panelW) / 2;
		_panelY = (FlxG.height - _panelH) / 2;

		final bg = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, 0xCC000000);
		bg.scrollFactor.set();
		bg.alpha = 0;
		add(bg);
		FlxTween.tween(bg, {alpha: 1}, 0.18, {ease: FlxEase.quadOut});

		final panel = new FlxSprite(_panelX, _panelY).makeGraphic(_panelW, _panelH, T.bgPanel);
		panel.scrollFactor.set();
		panel.alpha = 0;
		add(panel);
		FlxTween.tween(panel, {alpha: 1}, 0.22, {ease: FlxEase.quadOut});

		final bord = new FlxSprite(_panelX, _panelY).makeGraphic(_panelW, 4, T.accent);
		bord.scrollFactor.set();
		add(bord);

		final title = new FlxText(_panelX, _panelY + 14, _panelW, _isCreate ? '✦  CREATE NEW MOD' : '✎  EDIT MOD  —  ' + _mod.name.toUpperCase());
		title.setFormat(Paths.font('vcr.ttf'), 18, T.textPrimary, CENTER, OUTLINE, T.bgDark);
		title.scrollFactor.set();
		add(title);

		final sep = new FlxSprite(_panelX + 20, _panelY + 44).makeGraphic(_panelW - 40, 1, T.borderColor);
		sep.scrollFactor.set();
		add(sep);

		_cursor = new FlxSprite(_panelX + 12, _panelY + 60).makeGraphic(5, 28, T.accent);
		_cursor.scrollFactor.set();
		add(_cursor);

		_fields = _isCreate ? [
			{label: 'ID (folder)', key: 'id', value: _mod.id},
			{label: 'Name', key: 'name', value: _mod.name},
			{label: 'Description', key: 'description', value: _mod.description},
			{label: 'Author', key: 'author', value: _mod.author},
			{label: 'Version', key: 'version', value: _mod.version},
			{label: 'Priority', key: 'priority', value: Std.string(_mod.priority)},
			{label: 'Color (HEX)', key: 'color', value: StringTools.hex(_mod.color & 0xFFFFFF, 6)},
			{label: 'Website', key: 'website', value: _mod.website},
			{label: 'GameBanana ID', key: 'gamebananaid', value: _mod.gamebananaid != null ? Std.string(_mod.gamebananaid) : ''},
		] : [
			{label: 'Name', key: 'name', value: _mod.name},
			{label: 'Description', key: 'description', value: _mod.description},
			{label: 'Author', key: 'author', value: _mod.author},
			{label: 'Version', key: 'version', value: _mod.version},
			{label: 'Priority', key: 'priority', value: Std.string(_mod.priority)},
			{label: 'Color (HEX)', key: 'color', value: StringTools.hex(_mod.color & 0xFFFFFF, 6)},
			{label: 'Website', key: 'website', value: _mod.website},
			{label: 'GameBanana ID', key: 'gamebananaid', value: _mod.gamebananaid != null ? Std.string(_mod.gamebananaid) : ''},
			];

		for (i in 0..._fields.length) {
			final fy = _panelY + 58 + i * 48;
			final lbl = new FlxText(_panelX + 24, fy + 6, 180, _fields[i].label);
			lbl.setFormat(Paths.font('vcr.ttf'), 13, T.textDim, RIGHT);
			lbl.scrollFactor.set();
			add(lbl);
			final val = new FlxText(_panelX + 220, fy + 2, _panelW - 240, _fields[i].value);
			val.setFormat(Paths.font('vcr.ttf'), 15, T.textPrimary, LEFT);
			val.scrollFactor.set();
			_fieldValues.push(val);
			add(val);
		}

		_editBg = new FlxSprite(_panelX + 20, _panelY + _panelH - 80).makeGraphic(_panelW - 40, 36, T.bgPanelAlt);
		_editBg.scrollFactor.set();
		_editBg.visible = false;
		add(_editBg);

		_editText = new FlxText(_panelX + 28, _panelY + _panelH - 74, _panelW - 56, '');
		_editText.setFormat(Paths.font('vcr.ttf'), 16, T.textPrimary, LEFT);
		_editText.scrollFactor.set();
		_editText.visible = false;
		add(_editText);

		// ── Botones Save / Close ─────────────────────────────────────────────
		final btnW = 140;
		final btnH = 28;
		final btnY = _panelY + _panelH - 40;

		_saveBtn = new FlxSprite(_panelX + _panelW - btnW * 2 - 20, btnY).makeGraphic(btnW, btnH, T.success);
		_saveBtn.scrollFactor.set();
		add(_saveBtn);
		final saveTxt = new FlxText(_saveBtn.x, btnY + 7, btnW, '[F5] SAVE');
		saveTxt.setFormat(Paths.font('vcr.ttf'), 13, T.bgDark, CENTER);
		saveTxt.bold = true;
		saveTxt.scrollFactor.set();
		add(saveTxt);

		_closeBtn = new FlxSprite(_panelX + _panelW - btnW - 10, btnY).makeGraphic(btnW, btnH, T.error);
		_closeBtn.scrollFactor.set();
		add(_closeBtn);
		final closeTxt = new FlxText(_closeBtn.x, btnY + 7, btnW, '[Esc] CLOSE');
		closeTxt.setFormat(Paths.font('vcr.ttf'), 13, T.bgDark, CENTER);
		closeTxt.bold = true;
		closeTxt.scrollFactor.set();
		add(closeTxt);

		_hint = new FlxText(_panelX + 10, btnY + 6, _panelW - btnW * 2 - 40, '[↑↓ / Click] Field   [Enter / Click] Edit');
		_hint.setFormat(Paths.font('vcr.ttf'), 11, T.textDim, LEFT);
		_hint.scrollFactor.set();
		add(_hint);

		_updateCursor();

		// Captura nativa de texto via Lime — independiente de foco.
		// CRÍTICO: textInputEnabled = true activa SDL_StartTextInput() en desktop,
		// sin esto onTextInput nunca dispara y no se puede escribir nada.
		LimeApp.current.window.textInputEnabled = true;
		LimeApp.current.window.onTextInput.add(_onLimeTextInput);
		FlxG.stage.addEventListener(OflKeyboardEvent.KEY_DOWN, _onKeyDown);
		funkin.system.CursorManager.show();

		super.create();
	}

	override function update(elapsed:Float) {
		super.update(elapsed);
		if (_editMode) {
			_handleTextInput();
			return;
		}

		// ── Mouse ─────────────────────────────────────────────────────────────
		if (FlxG.mouse.justPressed) {
			// Botón SAVE
			if (_saveBtn != null && FlxG.mouse.overlaps(_saveBtn, cameras[0])) {
				FlxG.sound.play(Paths.sound('menus/confirmMenu'));
				_save();
			}
			// Botón CLOSE
			else if (_closeBtn != null && FlxG.mouse.overlaps(_closeBtn, cameras[0])) {
				funkin.system.CursorManager.show();
				FlxG.sound.play(Paths.sound('menus/scrollMenu'));
				close();
			}
			// Click en campo — usar value FlxText como hitbox de cada fila
			else {
				for (i in 0..._fieldValues.length) {
					if (FlxG.mouse.overlaps(_fieldValues[i], cameras[0])) {
						if (i == _curField) {
							FlxG.sound.play(Paths.sound('menus/scrollMenu'));
							_startEdit();
						} else {
							FlxG.sound.play(Paths.sound('menus/scrollMenu'));
							_curField = i;
							_updateCursor();
						}
						break;
					}
				}
			}
		}

		var upP = controls.UP_P;
		var downP = controls.DOWN_P;

		if (_fields.length < 1)
		{
			upP = false;
			downP = false;
		}

		if (upP) {
			FlxG.sound.play(Paths.sound('menus/scrollMenu'));
			_changeField(-1);
		}
		if (downP) {
			FlxG.sound.play(Paths.sound('menus/scrollMenu'));
			_changeField(1);
		}
		if (controls.ACCEPT) {
			FlxG.sound.play(Paths.sound('menus/scrollMenu'));
			_startEdit();
		}
		if (FlxG.keys.justPressed.F5) {
			FlxG.sound.play(Paths.sound('menus/confirmMenu'));
			_save();
		}
		if (controls.BACK) {
			funkin.system.CursorManager.show();
			FlxG.sound.play(Paths.sound('menus/scrollMenu'));
			close();
		}
	}

	function _handleTextInput():Void {
		if (FlxG.keys.justPressed.ESCAPE) {
			_endEdit(false);
			return;
		}
		if (FlxG.keys.justPressed.ENTER) {
			_endEdit(true);
			return;
		}
		// La actualización real la hacen _onLimeTextInput / _onKeyDown
	}

	function _onLimeTextInput(text:String):Void {
		if (!_editMode)
			return;
		_editingText += text;
		_editText.text = _editingText + '|';
	}

	function _onKeyDown(e:OflKeyboardEvent):Void {
		if (!_editMode)
			return;
		if (e.keyCode == 8 && _editingText.length > 0) {
			_editingText = _editingText.substr(0, _editingText.length - 1);
			_editText.text = _editingText + '|';
		}
	}

	function _kc(key:flixel.input.keyboard.FlxKey, sh:Bool):String {
		final n = key.toString();
		if (n.length == 1)
			return sh ? n.toUpperCase() : n.toLowerCase();
		return switch (key) {
			case SPACE: ' ';
			case MINUS: sh ? '_' : '-';
			case PERIOD: sh ? '>' : '.';
			case SLASH: sh ? '?' : '/';
			case SEMICOLON: sh ? ':' : ';';
			case NUMPADZERO | ZERO: '0';
			case NUMPADONE | ONE: '1';
			case NUMPADTWO | TWO: '2';
			case NUMPADTHREE | THREE: '3';
			case NUMPADFOUR | FOUR: '4';
			case NUMPADFIVE | FIVE: '5';
			case NUMPADSIX | SIX: '6';
			case NUMPADSEVEN | SEVEN: '7';
			case NUMPADEIGHT | EIGHT: '8';
			case NUMPADNINE | NINE: '9';
			default: '';
		};
	}

	function _changeField(d:Int):Void {
		_curField = (_curField + d + _fields.length) % _fields.length;
		_updateCursor();
	}

	function _updateCursor():Void {
		final T = EditorTheme.current;
		FlxTween.cancelTweensOf(_cursor);
		FlxTween.tween(_cursor, {y: _panelY + 58 + _curField * 48 + 8}, 0.12, {ease: FlxEase.expoOut});
		for (i in 0..._fieldValues.length)
			_fieldValues[i].color = i == _curField ? T.accent : T.textPrimary;
	}

	function _startEdit():Void {
		_editingText = _fields[_curField].value;
		_editMode = true;
		_editBg.visible = true;
		_editText.visible = true;
		_editText.text = _editingText + '|';
		_hint.text = '  Writing "${_fields[_curField].label}" — [Enter] Apply   [Esc] Cancel';
	}

	function _endEdit(apply:Bool):Void {
		_editMode = false;
		_editBg.visible = false;
		_editText.visible = false;
		if (apply) {
			_fields[_curField].value = _editingText;
			_fieldValues[_curField].text = _editingText;
		}
		_hint.text = '[↑↓] Field   [Enter] Edit/Confirm   [Esc] Cancel/Close   [F5] Save';
	}

	function _save():Void {
		final T = EditorTheme.current;
		for (f in _fields)
			switch (f.key) {
				case 'id':
					_mod.id = f.value.trim().toLowerCase().replace(' ', '-');
				case 'name':
					_mod.name = f.value;
				case 'description':
					_mod.description = f.value;
				case 'author':
					_mod.author = f.value;
				case 'version':
					_mod.version = f.value;
				case 'website':
					_mod.website = f.value;
				case 'gamebananaid':
					final gbid = Std.parseInt(f.value.trim());
					_mod.gamebananaid = (gbid != null && gbid > 0) ? gbid : null;
				case 'priority':
					final p = Std.parseInt(f.value);
					_mod.priority = p ?? 0;
				case 'color':
					try {
						var h = f.value.trim();
						if (h.startsWith('#'))
							h = h.substr(1);
						_mod.color = 0xFF000000 | Std.parseInt('0x$h');
					} catch (_) {}
			}

		if (_isCreate) {
			if (_mod.id == '' || _mod.id == null) {
				_hint.text = '⚠  The ID field cannot be empty.';
				_hint.color = T.error;
				return;
			}
			final c = ModManager.createMod(_mod.id, _mod);
			if (c == null) {
				_hint.text = '⚠  Error: A mod with that ID already exists.';
				_hint.color = T.error;
				return;
			}
			_onDone(c);
		} else {
			ModManager.saveModInfo(_mod);
			_onDone(_mod);
		}
		close();
	}

	override function destroy() {
		if (cameras != null && cameras.length > 0) {
			final cam = cameras[0];
			if (cam != null)
				FlxG.cameras.remove(cam, true);
		}
		LimeApp.current.window.textInputEnabled = false;
		LimeApp.current.window.onTextInput.remove(_onLimeTextInput);
		FlxG.stage.removeEventListener(OflKeyboardEvent.KEY_DOWN, _onKeyDown);
		super.destroy();
	}
}
