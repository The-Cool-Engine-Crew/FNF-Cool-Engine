package funkin.debug.editors;

import coolui.CoolInputText;
import coolui.CoolNumericStepper;
import coolui.CoolCheckBox;
import coolui.CoolDropDown;
import coolui.CoolTabMenu;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import coolui.CoolButton;
import flixel.util.FlxColor;
import funkin.data.WeekFile;
import funkin.data.WeekFile.WeekData;
import funkin.gameplay.objects.character.CharacterList;
import funkin.menus.substate.MenuCharacter;
import funkin.states.MusicBeatState;
import funkin.transitions.StateTransition;
import haxe.Json;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import openfl.net.FileReference;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/**
 * StoryMenuEditor v2 — Editor visual que replica 1:1 el layout del StoryMenuState.
 *
 * ── Layout general ────────────────────────────────────────────────────────────
 *
 *  ┌─ camHUD ─────────────────────────────────────────────────────────────────┐
 *  │ [topBar 36px]                                                            │
 *  ├──────────────────────────────────────────────────────────────────────────┤
 *  │ [Lista  │    camGame: preview EXACTO del StoryMenu        │ Panel tabs   │
 *  │ 220px   │    yellowBG + 3×MenuCharacter + tracksMenu      │ 340px        │
 *  │         │    viewport recortado = sólo esa franja         │              │
 *  ├─────────┴──────────────────────────────────────────────────┴─────────────┤
 *  │ [statusBar 26px]                                                         │
 *  └──────────────────────────────────────────────────────────────────────────┘
 *
 *  El preview usa los mismos elementos que StoryMenuState:
 *    • blackBarThingie  (negro, h=56, y=0)
 *    • yellowBG         (color de la week, y=56, h=404)
 *    • grpWeekCharacters (3× MenuCharacter en posiciones reales)
 *    • tracksMenu + txtTracklist
 *    • scoreText + txtWeekTitle
 *
 *  Los personajes usan MenuCharacter (no Character), que carga:
 *    atlas  → assets/images/menu/storymenu/props/<nombre>.png/.xml
 *    datos  → assets/data/storymenu/chars/<nombre>.json  (offsetX/Y, scale, flipX, anims)
 *
 *  Los offsets EDITABLES en el tab CHARS se suman encima de los del JSON,
 *  permitiendo ajustar la posición sin tocar el JSON del personaje.
 *  Se guardan en campos extendidos del WeekData (wceOffX, wceOffY, wceScale, wceFlip).
 *
 * ── Atajos ────────────────────────────────────────────────────────────────────
 *  CTRL+S   → Guardar JSON al disco
 *  CTRL+E   → Exportar JSON (FileReference)
 *  ESC      → Volver al EditorHubState
 *
 * @author  Cool Engine Team
 * @version 2.0.0
 */
class StoryMenuEditor extends MusicBeatState {
	// ── Dimensiones de los paneles laterales ─────────────────────────────────
	static inline var LIST_W:Int = 220;
	static inline var PANEL_W:Int = 340;
	static inline var TOP_H:Int = 36;
	static inline var BOT_H:Int = 26;

	// ── Paleta UI ────────────────────────────────────────────────────────────
	static inline var C_BG:Int = 0xFF080810;
	static inline var C_PANEL:Int = 0xFF0F0F1E;
	static inline var C_PALT:Int = 0xFF131325;
	static inline var C_ACCENT:Int = 0xFF00D9FF;
	static inline var C_GREEN:Int = 0xFF00FF88;
	static inline var C_RED:Int = 0xFFFF3355;
	static inline var C_YELLOW:Int = 0xFFFFCC00;
	static inline var C_GRAY:Int = 0xFFAAAAAA;
	static inline var C_WHITE:Int = 0xFFFFFFFF;

	// ── Posiciones exactas del StoryMenuState ────────────────────────────────
	// blackBarThingie: y=0, h=56
	// yellowBG:        y=56, h=404
	// MenuCharacter x: (FlxG.width * 0.25) * (1 + slot) - 150   →  170 / 490 / 810  (para 1280)
	// MenuCharacter y: yellowBG.y + 70 = 126
	// tracksMenu:      x=FlxG.width*0.07,  y=yellowBG.y+435 = 491
	static inline var YELLOW_Y:Int = 56;
	static inline var YELLOW_H:Int = 404;
	static inline var CHAR_Y:Int = 126; // 56 + 70
	static inline var TRACKS_Y:Int = 491; // 56 + 435

	// ── Cámaras ──────────────────────────────────────────────────────────────

	/** Única cámara — todo se renderiza aquí (no hay camGame separada). */
	var camHUD:FlxCamera;

	/** X donde empieza el área de preview. */
	var _pvX:Int = 0;

	/** Escala para mapear coordenadas 1280→pvW. */
	var _pvScale:Float = 1.0;

	// ── Datos ────────────────────────────────────────────────────────────────
	var _weeks:Array<WeekData> = [];
	var _curWeek:Int = 0;
	var _dirty:Bool = false;

	// ── Elementos del preview (idénticos al StoryMenuState) ──────────────────
	var _blackBar:FlxSprite;
	var _yellowBG:FlxSprite;
	var _grpChars:FlxTypedGroup<MenuCharacter>;
	var _tracksMenu:FlxSprite;
	var _txtTracks:FlxText;
	var _txtTitle:FlxText;
	var _scoreText:FlxText;
	var _colorTween:FlxTween = null;

	// ── Offsets editables (se suman sobre los del JSON del MenuCharacter) ─────
	var _editOffX:Array<Float> = [0.0, 0.0, 0.0];
	var _editOffY:Array<Float> = [0.0, 0.0, 0.0];
	var _editScale:Array<Float> = [1.0, 1.0, 1.0];
	var _editFlip:Array<Bool> = [false, false, false];

	// ── Panel izquierdo ───────────────────────────────────────────────────────
	var _listItems:FlxTypedGroup<WeekListItem>;

	static inline var ITEM_H:Int = 44;

	// ── Panel derecho ─────────────────────────────────────────────────────────
	var _tabMenu:CoolTabMenu;

	// Controles tab WEEK
	var _wId:CoolInputText;
	var _wName:CoolInputText;
	var _wPath:CoolInputText;
	var _wColor:CoolInputText;
	var _wLocked:CoolCheckBox;
	var _wOrder:CoolNumericStepper;
	var _wSongIn:CoolInputText;
	var _wSongs:Array<SongRow> = [];

	/** Tab WEEK para poder añadir/quitar filas dinámicamente. */
	var _weekTab:coolui.CoolUIGroup = null;

	var _colPrev:FlxSprite;

	// Controles tab CHARS
	var _cDrop:Array<CoolDropDown> = [];
	var _cOffX:Array<CoolNumericStepper> = [];
	var _cOffY:Array<CoolNumericStepper> = [];
	var _cScale:Array<CoolNumericStepper> = [];
	var _cFlip:Array<CoolCheckBox> = [];

	static var SLOT_LABELS:Array<String> = ["Opponent", "BF", "GF"];

	// ── Status ────────────────────────────────────────────────────────────────
	var _statusTxt:FlxText;
	var _statusTimer:Float = 0;
	var _file:FileReference;

	// ============================================================
	// CREATE
	// ============================================================

	override public function create():Void {
		super.create();

		funkin.system.CursorManager.show();

		// ── Una sola cámara para todo ────────────────────────────────────────────
		// Usar una única camHUD evita los problemas de coolui.CoolUIGroup con múltiples cámaras.
		// Los elementos del preview se posicionan y escalan manualmente.
		var pvX = LIST_W + 1;
		var pvW = FlxG.width - LIST_W - PANEL_W - 2;
		var pvH = FlxG.height - TOP_H - BOT_H;

		_pvX = pvX;
		_pvScale = pvW / FlxG.width; // factor de escala 1280→pvW

		camHUD = new FlxCamera();
		camHUD.bgColor = 0xFF080810;

		FlxG.cameras.reset(camHUD);

		// ── Datos
		_weeks = WeekFile.loadAll();
		if (_weeks.length == 0)
			_weeks.push(_newWeek('week1'));

		// ── Construir
		_buildHUD();
		_buildPreview();
		_buildListPanel();
		_buildRightPanel();

		_loadWeek(0, true);

		FlxG.camera.fade(FlxColor.BLACK, 0.25, true);
	}

	// ============================================================
	// HUD — barras + fondos de paneles
	// ============================================================

	function _buildHUD():Void {
		// Fondo global
		_addHUD(new FlxSprite(0, 0)).makeGraphic(FlxG.width, FlxG.height, C_BG);

		// Fondo panel izquierdo
		_addHUD(new FlxSprite(0, TOP_H)).makeGraphic(LIST_W, FlxG.height - TOP_H - BOT_H, C_PANEL);

		// Separadores de paneles
		for (sx in [LIST_W, FlxG.width - PANEL_W]) {
			var s = _addHUD(new FlxSprite(sx, TOP_H));
			s.makeGraphic(1, FlxG.height - TOP_H - BOT_H, C_ACCENT);
			s.alpha = 0.15;
		}

		// ── Barra superior
		_addHUD(new FlxSprite(0, 0)).makeGraphic(FlxG.width, TOP_H, C_PALT);

		var topLine = _addHUD(new FlxSprite(0, TOP_H - 1));
		topLine.makeGraphic(FlxG.width, 1, C_ACCENT);
		topLine.alpha = 0.3;

		var lbl = new FlxText(10, 0, 0, "STORY MENU EDITOR", 14);
		lbl.color = C_ACCENT;
		lbl.font = Paths.font("vcr.ttf");
		lbl.y = Std.int((TOP_H - lbl.height) / 2);
		_addHUDTxt(lbl);

		var hints = new FlxText(0, 0, FlxG.width - 10, "CTRL+S SAVE  •  CTRL+E EXPORT  •  ESC BACK", 11);
		hints.alignment = RIGHT;
		hints.color = C_GRAY;
		hints.font = Paths.font("vcr.ttf");
		hints.y = Std.int((TOP_H - hints.height) / 2);
		_addHUDTxt(hints);

		// ── Barra de estado
		_addHUD(new FlxSprite(0, FlxG.height - BOT_H)).makeGraphic(FlxG.width, BOT_H, C_PALT);

		var botLine = _addHUD(new FlxSprite(0, FlxG.height - BOT_H));
		botLine.makeGraphic(FlxG.width, 1, C_ACCENT);
		botLine.alpha = 0.15;

		_statusTxt = new FlxText(10, FlxG.height - BOT_H + 6, FlxG.width - 20, "Done.", 10);
		_statusTxt.color = C_GRAY;
		_statusTxt.font = Paths.font("vcr.ttf");
		_addHUDTxt(_statusTxt);
	}

	// camHUD is now the only camera — no need to assign cameras explicitly.
	// These helpers kept for compatibility but cameras= lines removed.
	inline function _addHUD(s:FlxSprite):FlxSprite {
		s.scrollFactor.set();
		add(s);
		return s;
	}

	inline function _addHUDTxt(t:FlxText):FlxText {
		t.scrollFactor.set();
		add(t);
		return t;
	}

	// ============================================================
	// PREVIEW — idéntico al StoryMenuState
	// ============================================================

	function _buildPreview():Void {
		// Preview background (área oscura detrás del StoryMenu simulado)
		var pvBg = new FlxSprite(_pvX, TOP_H);
		pvBg.makeGraphic(FlxG.width - LIST_W - PANEL_W - 2, FlxG.height - TOP_H - BOT_H, 0xFF0A0A0A);
		pvBg.scrollFactor.set();
		add(pvBg);

		// Todos los elementos del preview se posicionan con _pvX offset
		// y se escalan con _pvScale para simular el StoryMenu dentro del área central.
		var sc = _pvScale;
		var ox = _pvX;

		// blackBarThingie: y=TOP_H, height=56*sc
		_blackBar = new FlxSprite(ox, TOP_H);
		_blackBar.makeGraphic(Std.int((FlxG.width - LIST_W - PANEL_W - 2)), Std.int(56 * sc), FlxColor.BLACK);
		_blackBar.scrollFactor.set();
		add(_blackBar);

		// Score text
		_scoreText = new FlxText(ox + Std.int(10 * sc), TOP_H + Std.int(10 * sc), 0, "LEVEL SCORE: 0", Std.int(32 * sc));
		_scoreText.setFormat(Paths.font("vcr.ttf"), Std.int(Math.max(8, 32 * sc)));
		_scoreText.scrollFactor.set();
		add(_scoreText);

		// txtWeekTitle (top-right)
		var pvW2 = FlxG.width - LIST_W - PANEL_W - 2;
		_txtTitle = new FlxText(ox, TOP_H + Std.int(10 * sc), pvW2, "", Std.int(Math.max(8, 32 * sc)));
		_txtTitle.setFormat(Paths.font("vcr.ttf"), Std.int(Math.max(8, 32 * sc)), FlxColor.WHITE, RIGHT);
		_txtTitle.alpha = 0.7;
		_txtTitle.scrollFactor.set();
		add(_txtTitle);

		// yellowBG (franja de color, escalada)
		var yyY = TOP_H + Std.int(YELLOW_Y * sc);
		_yellowBG = new FlxSprite(ox, yyY);
		_yellowBG.makeGraphic(pvW2, Std.int(YELLOW_H * sc), 0xFFFFD900);
		_yellowBG.scrollFactor.set();
		add(_yellowBG);

		// 3× MenuCharacter — posicionadas con offset _pvX y escaladas
		_grpChars = new FlxTypedGroup<MenuCharacter>();
		add(_grpChars);

		for (i in 0...3) {
			// x original: (1280 * 0.25) * (1+i) - 150 → escalar y desplazar
			var cx = ox + Std.int(((FlxG.width * 0.25) * (1 + i) - 150) * sc);
			var mc = new MenuCharacter(cx, '');
			mc.y = TOP_H + Std.int(CHAR_Y * sc);
			mc.antialiasing = true;
			mc.scrollFactor.set();
			_grpChars.add(mc);
		}

		// tracksMenu image
		_tracksMenu = new FlxSprite(ox + Std.int(FlxG.width * 0.07 * sc), TOP_H + Std.int(TRACKS_Y * sc));
		var tmPath = Paths.image('menu/storymenu/tracksMenu');
		var loaded = false;
		#if sys
		if (FileSystem.exists(tmPath)) {
			try {
				_tracksMenu.loadGraphic(tmPath);
				if (_tracksMenu.graphic != null && _tracksMenu.graphic.bitmap != null) {
					_tracksMenu.antialiasing = true;
					loaded = true;
				}
			} catch (_) {}
		}
		#end
		if (!loaded)
			_tracksMenu.makeGraphic(Std.int(pvW2 * 0.5), Std.int(120 * sc), 0xDD000000);
		_tracksMenu.scrollFactor.set();
		add(_tracksMenu);

		// txtTracklist (canciones, rosa como StoryMenuState)
		_txtTracks = new FlxText(ox + Std.int(FlxG.width * 0.05 * sc), _tracksMenu.y + Std.int(60 * sc), pvW2, "", Std.int(Math.max(8, 32 * sc)));
		_txtTracks.alignment = CENTER;
		_txtTracks.font = Paths.font("vcr.ttf");
		_txtTracks.color = 0xFFe55777;
		_txtTracks.scrollFactor.set();
		add(_txtTracks);

		// Indicador sutil de modo editor
		var ovl = new FlxText(ox + pvW2 - Std.int(110 * sc), TOP_H + Std.int((YELLOW_Y + 4) * sc), Std.int(100 * sc), "[ EDITOR ]", 9);
		ovl.color = FlxColor.WHITE;
		ovl.alpha = 0.15;
		ovl.font = Paths.font("vcr.ttf");
		ovl.scrollFactor.set();
		add(ovl);
	}

	// ============================================================
	// PANEL IZQUIERDO — lista de weeks
	// ============================================================

	function _buildListPanel():Void {
		// Header
		var hdr = _addHUD(new FlxSprite(0, TOP_H));
		hdr.makeGraphic(LIST_W, 28, C_PALT);

		var hLbl = new FlxText(8, TOP_H + 6, LIST_W - 56, "WEEKS", 11);
		hLbl.color = C_ACCENT;
		hLbl.font = Paths.font("vcr.ttf");
		_addHUDTxt(hLbl);

		add(_mkBtn(LIST_W - 52, TOP_H + 3, 22, 22, "+", CoolButton.STYLE_ACCENT, _onNewWeek));
		add(_mkBtn(LIST_W - 26, TOP_H + 3, 22, 22, "−", CoolButton.STYLE_DANGER, _onDelWeek));

		var hSep = _addHUD(new FlxSprite(0, TOP_H + 28));
		hSep.makeGraphic(LIST_W, 1, C_ACCENT);
		hSep.alpha = 0.1;

		_listItems = new FlxTypedGroup<WeekListItem>();
		add(_listItems);

		_rebuildList();
	}

	function _rebuildList():Void {
		while (_listItems.length > 0)
			_listItems.remove(_listItems.members[0], true);
		for (i in 0..._weeks.length) {
			var item = new WeekListItem(0, TOP_H + 29 + i * ITEM_H, LIST_W, ITEM_H, i, _weeks[i], i == _curWeek);
			item.onSelect = function(idx) {
				_loadWeek(idx);
			};
			_listItems.add(item);
		}
	}

	// ============================================================
	// PANEL DERECHO — CoolTabMenu
	// ============================================================

	function _buildRightPanel():Void {
		_tabMenu = new CoolTabMenu(null, [{name: 'week', label: 'WEEK'}, {name: 'chars', label: 'CHARS'}], true);
		_tabMenu.x = FlxG.width - PANEL_W;
		_tabMenu.y = TOP_H;
		_tabMenu.resize(PANEL_W, FlxG.height - TOP_H - BOT_H);
		_tabMenu.scrollFactor.set();

		_buildTabWeek();
		_buildTabChars();

		// camHUD es la cámara por defecto (FlxG.cameras.reset), no asignar explícitamente
		add(_tabMenu);
		_tabMenu.selected_tab_id = 'week'; // mostrar la primera pestaña
	}

	// ── Tab WEEK ─────────────────────────────────────────────────────────────

	function _buildTabWeek():Void {
		var tab = new coolui.CoolUIGroup();
		tab.name = 'week';
		var y0 = CoolTabMenu.TAB_BAR_H + 10;
		var xL = 10;
		var lW = PANEL_W - 20;
		var sH = 34;

		function lbl(y:Float, t:String):FlxText {
			var x = new FlxText(xL, y, lW, t, 10);
			x.color = C_GRAY;
			x.font = Paths.font("vcr.ttf");
			tab.add(x);
			return x;
		}

		lbl(y0, "ID (nombre del archivo)");
		_wId = new CoolInputText(xL, y0 + 13, lW, '', 11);
		tab.add(_wId);

		lbl(y0 + sH, "Nombre de la semana");
		_wName = new CoolInputText(xL, y0 + sH + 13, lW, '', 11);
		tab.add(_wName);

		lbl(y0 + sH * 2, "Ruta del título (weekPath)");
		_wPath = new CoolInputText(xL, y0 + sH * 2 + 13, lW, '', 11);
		tab.add(_wPath);

		lbl(y0 + sH * 3, "Color (hex)");
		_wColor = new CoolInputText(xL, y0 + sH * 3 + 13, lW - 36, '', 11);
		_wColor.callback = function(_, _) {
			_onColorChange();
		};
		tab.add(_wColor);

		_colPrev = new FlxSprite(xL + lW - 30, y0 + sH * 3 + 13);
		_colPrev.makeGraphic(28, 20, 0xFFFFD900);
		tab.add(_colPrev);

		_wLocked = new CoolCheckBox(xL, y0 + sH * 4 + 8, null, null, "Bloqueada", 90);
		cast(_wLocked.getLabel(), flixel.text.FlxText).color = C_WHITE;
		tab.add(_wLocked);

		lbl(y0 + sH * 4 + 6, "               Orden:");
		_wOrder = new CoolNumericStepper(xL + 165, y0 + sH * 4 + 6, 1, 0, 0, 99, 0);
		tab.add(_wOrder);

		// ── Sección canciones
		var sepY = y0 + sH * 5 + 4;
		var div = new FlxSprite(xL, sepY);
		div.makeGraphic(lW, 1, C_ACCENT);
		div.alpha = 0.2;
		tab.add(div);

		var sLbl = new FlxText(xL, sepY + 5, lW, "SONGS", 10);
		sLbl.color = C_ACCENT;
		sLbl.font = Paths.font("vcr.ttf");
		tab.add(sLbl);

		var addY = sepY + 22;
		_wSongIn = new CoolInputText(xL, addY, lW - 32, '', 11);
		tab.add(_wSongIn);

		var btnAdd = _mkBtn(xL + lW - 28, addY, 26, 20, "+", CoolButton.STYLE_ACCENT, function() {
			var n = _wSongIn.text.trim();
			if (n.length == 0)
				return;
			_curW().weekSongs.push(n);
			_wSongIn.text = '';
			_rebuildSongRows();
			_refreshTracks();
			_dirty = true;
		});
		tab.add(btnAdd);

		_wSongs = [];
		_weekTab = tab;
		_rebuildSongRows();

		// Botones al fondo
		var btnH = FlxG.height - TOP_H - BOT_H;
		var btnSave = new CoolButton(xL, btnH - 58, "SAVE (CTRL+S)", _onSave, 80, 20, CoolButton.STYLE_ACCENT);
		tab.add(btnSave);

		var btnExp = new CoolButton(xL, btnH - 30, "EXPORT JSON", _onExport, 80, 20, CoolButton.STYLE_ACCENT);
		tab.add(btnExp);

		_tabMenu.addGroup(tab);
	}

	function _rebuildSongRows():Void {
		// Quitar filas anteriores del tab directamente
		for (row in _wSongs)
			if (_weekTab != null)
				_weekTab.remove(row, true);
		_wSongs = [];

		var w = _curW();
		if (w == null)
			return;
		var sy = CoolTabMenu.TAB_BAR_H + 10 + 34 * 5 + 4 + 50;
		for (i in 0...Std.int(Math.min(w.weekSongs.length, 5))) {
			var row = new SongRow(10, sy + i * 24, PANEL_W - 20, w.weekSongs[i], i, function(idx) {
				_curW().weekSongs.splice(idx, 1);
				_rebuildSongRows();
				_refreshTracks();
				_dirty = true;
			});
			_wSongs.push(row);
			if (_weekTab != null)
				_weekTab.add(row);
		}
	}

	// ── Tab CHARS ────────────────────────────────────────────────────────────

	function _buildTabChars():Void {
		var tab = new coolui.CoolUIGroup();
		tab.name = 'chars';
		var allCh = CharacterList.getAllCharacters();
		if (allCh == null || allCh.length == 0)
			allCh = ['bf', 'dad', 'gf'];
		var opts = allCh.copy();
		opts.unshift('(ninguno)');

		var y0 = CoolTabMenu.TAB_BAR_H + 8;
		var xL = 10;
		var lW = PANEL_W - 20;

		for (s in 0...3) {
			var sy = y0 + s * 128;
			var sc = [C_ACCENT, C_GREEN, C_YELLOW][s];
			var sn = s; // captura para closures

			var sLbl = new FlxText(xL, sy, lW, SLOT_LABELS[s].toUpperCase(), 11);
			sLbl.color = sc;
			sLbl.font = Paths.font("vcr.ttf");
			tab.add(sLbl);

			var sDiv = new FlxSprite(xL, sy + 14);
			sDiv.makeGraphic(lW, 1, sc);
			sDiv.alpha = 0.25;
			tab.add(sDiv);

			// Dropdown
			var drop = new CoolDropDown(xL, sy + 18, CoolDropDown.makeStrIdLabelArray(opts), function(sel:String) {
				_onCharSel(sn, sel);
			});
			_cDrop[s] = drop;
			tab.add(drop);

			// Offset X / Y
			var oxt = new FlxText(xL, sy + 48, 55, "Offset X:", 10);
			oxt.color = C_GRAY;
			oxt.font = Paths.font("vcr.ttf");
			tab.add(oxt);
			var oxs = new CoolNumericStepper(xL + 58, sy + 46, 2, 0, -500, 500, 1);
			_cOffX[s] = oxs;
			tab.add(oxs);

			var oyt = new FlxText(xL + 160, sy + 48, 55, "Offset Y:", 10);
			oyt.color = C_GRAY;
			oyt.font = Paths.font("vcr.ttf");
			tab.add(oyt);
			var oys = new CoolNumericStepper(xL + 218, sy + 46, 2, 0, -500, 500, 1);
			_cOffY[s] = oys;
			tab.add(oys);

			// Escala / Flip
			var sct = new FlxText(xL, sy + 72, 55, "Scale:", 10);
			sct.color = C_GRAY;
			sct.font = Paths.font("vcr.ttf");
			tab.add(sct);
			var scs = new CoolNumericStepper(xL + 58, sy + 70, 0.05, 1.0, 0.1, 5.0, 2);
			_cScale[s] = scs;
			tab.add(scs);

			var fbox = new CoolCheckBox(xL + 180, sy + 72, null, null, "Flip X", 60);
			cast(fbox.getLabel(), flixel.text.FlxText).color = C_WHITE;
			fbox.callback = function(_:Bool) {
				_applyCharEdit(sn);
			};
			_cFlip[s] = fbox;
			tab.add(fbox);
		}

		// Botones
		var sepY = y0 + 3 * 128 + 6;
		var sep = new FlxSprite(xL, sepY);
		sep.makeGraphic(lW, 1, C_ACCENT);
		sep.alpha = 0.15;
		tab.add(sep);

		var btnAp = new CoolButton(xL, sepY + 8, "APPLY AND SAVE", function() {
			_applyAllCharEdits();
			_onSave();
		}, 80, 20, CoolButton.STYLE_ACCENT);
		tab.add(btnAp);

		var btnRs = new CoolButton(xL, sepY + 36, "RESET OFFSETS", function() {
			for (i in 0...3) {
				_cOffX[i].value = 0;
				_cOffY[i].value = 0;
				_cScale[i].value = 1.0;
				_cFlip[i].checked = false;
				_editOffX[i] = 0;
				_editOffY[i] = 0;
				_editScale[i] = 1.0;
				_editFlip[i] = false;
			}
			_rebuildChars();
		}, 80, 20, CoolButton.STYLE_DANGER);
		tab.add(btnRs);

		_tabMenu.addGroup(tab);
	}

	// ============================================================
	// LÓGICA — cargar / actualizar week
	// ============================================================

	function _loadWeek(idx:Int, instant:Bool = false):Void {
		if (idx < 0 || idx >= _weeks.length)
			return;
		_curWeek = idx;
		var w = _weeks[idx];

		_wId.text = w.id ?? '';
		_wName.text = w.weekName ?? '';
		_wPath.text = w.weekPath ?? '';
		_wColor.text = w.color ?? '0xFFFFD900';
		_wLocked.checked = w.locked == true;
		_wOrder.value = w.order ?? idx;

		// Leer offsets extendidos guardados
		_editOffX = _readDyn(w, 'wceOffX', [0.0, 0.0, 0.0]);
		_editOffY = _readDyn(w, 'wceOffY', [0.0, 0.0, 0.0]);
		_editScale = _readDyn(w, 'wceScale', [1.0, 1.0, 1.0]);
		_editFlip = _readDyn(w, 'wceFlip', [false, false, false]);

		for (i in 0...3) {
			if (_cOffX[i] != null)
				_cOffX[i].value = _editOffX[i];
			if (_cOffY[i] != null)
				_cOffY[i].value = _editOffY[i];
			if (_cScale[i] != null)
				_cScale[i].value = _editScale[i];
			if (_cFlip[i] != null)
				_cFlip[i].checked = _editFlip[i];
		}

		// Aplicar color inmediatamente si es la primera carga
		var col = _parseColor(w.color ?? '0xFFFFD900');
		if (instant)
			_yellowBG.color = col;
		else {
			if (_colorTween != null) {
				_colorTween.cancel();
				_colorTween = null;
			}
			_colorTween = FlxTween.color(_yellowBG, 0.35, _yellowBG.color, col, {ease: FlxEase.quartOut, onComplete: function(_) _colorTween = null});
		}
		_colPrev.makeGraphic(28, 20, col);

		_refreshTitle();
		_refreshTracks();
		_rebuildSongRows();
		_rebuildChars();
		_rebuildList();

		_dirty = false;
		_setStatus('Week "${w.weekName ?? w.id}" loaded.');
	}

	function _refreshTitle():Void {
		var w = _curW();
		if (w == null)
			return;
		_txtTitle.text = (w.weekName ?? '').toUpperCase();
		var _pvW2 = FlxG.width - LIST_W - PANEL_W - 2;
		_txtTitle.x = _pvX + _pvW2 - _txtTitle.width - Std.int(10 * _pvScale);
	}

	function _refreshTracks():Void {
		var w = _curW();
		if (w == null)
			return;
		_txtTracks.text = '';
		for (s in (w.weekSongs ?? []))
			_txtTracks.text += s.replace('-', ' ').toUpperCase() + '\n';
		var _pvW3 = FlxG.width - LIST_W - PANEL_W - 2;
		_txtTracks.x = _pvX + Std.int((_pvW3 - _txtTracks.width) * 0.5);
	}

	function _onColorChange():Void {
		var w = _curW();
		if (w == null)
			return;
		w.color = _wColor.text.trim();
		var col = _parseColor(w.color);
		_colPrev.makeGraphic(28, 20, col);
		if (_colorTween != null) {
			_colorTween.cancel();
			_colorTween = null;
		}
		_colorTween = FlxTween.color(_yellowBG, 0.35, _yellowBG.color, col, {ease: FlxEase.quartOut, onComplete: function(_) _colorTween = null});
		_dirty = true;
	}

	// ── Personajes ────────────────────────────────────────────────────────────

	function _rebuildChars():Void {
		var w = _curW();
		var chars = (w != null && w.weekCharacters != null) ? w.weekCharacters : ['', 'bf', 'gf'];
		while (chars.length < 3)
			chars.push('');

		for (i in 0...3) {
			var mc = _grpChars.members[i];
			if (mc == null)
				continue;

			// Posición escalada al área de preview
			var bx = (FlxG.width * 0.25) * (1 + i) - 150;
			mc.x = _pvX + Std.int((bx + _editOffX[i]) * _pvScale);
			mc.y = TOP_H + Std.int((CHAR_Y + _editOffY[i]) * _pvScale);

			// Cambiar personaje — MenuCharacter aplica sus propios offsets del JSON
			mc.changeCharacter(chars[i] ?? '');

			// Los offsets editables (escala, flip) se suman por encima del JSON
			if (mc.graphic != null && mc.visible) {
				// Escala combinada: _pvScale (preview) + _editScale (ajuste del usuario)
				var s = _editScale[i] * _pvScale;
				mc.scale.set(s, s);
				mc.updateHitbox();
				if (_editFlip[i])
					mc.flipX = !mc.flipX;
			}
		}
	}

	function _onCharSel(slot:Int, charName:String):Void {
		var w = _curW();
		if (w == null)
			return;
		while (w.weekCharacters.length < 3)
			w.weekCharacters.push('');
		w.weekCharacters[slot] = (charName == '(ninguno)') ? '' : charName;
		_dirty = true;
		_rebuildChars();
	}

	function _applyCharEdit(slot:Int):Void {
		if (_cOffX[slot] == null)
			return;
		_editOffX[slot] = _cOffX[slot].value;
		_editOffY[slot] = _cOffY[slot].value;
		_editScale[slot] = _cScale[slot].value;
		_editFlip[slot] = _cFlip[slot].checked;
		_rebuildChars();
		_dirty = true;
	}

	function _applyAllCharEdits():Void {
		for (i in 0...3)
			_applyCharEdit(i);
		var w = _curW();
		if (w == null)
			return;
		Reflect.setField(w, 'wceOffX', _editOffX.copy());
		Reflect.setField(w, 'wceOffY', _editOffY.copy());
		Reflect.setField(w, 'wceScale', _editScale.copy());
		Reflect.setField(w, 'wceFlip', _editFlip.copy());
	}

	// ── Gestión de weeks ─────────────────────────────────────────────────────

	function _onNewWeek():Void {
		_weeks.push(_newWeek('week${_weeks.length + 1}'));
		_loadWeek(_weeks.length - 1);
	}

	function _onDelWeek():Void {
		if (_weeks.length <= 1) {
			_setStatus('The one week cannot be deleted.');
			return;
		}
		_weeks.splice(_curWeek, 1);
		if (_curWeek >= _weeks.length)
			_curWeek = _weeks.length - 1;
		_loadWeek(_curWeek);
	}

	// ── Guardar / Exportar ────────────────────────────────────────────────────

	function _onSave():Void {
		_commitFields();
		_applyAllCharEdits();
		var w = _curW();
		var ok = (w != null) ? WeekFile.save(w) : false;
		_dirty = !ok;
		_setStatus(ok ? '✓ Saved: ${w.id}.json' : '✗ Error save.');
		_rebuildList();
	}

	function _onExport():Void {
		_commitFields();
		_applyAllCharEdits();
		var w = _curW();
		if (w == null)
			return;
		_file = new FileReference();
		_file.addEventListener(Event.COMPLETE, function(_) _setStatus('Exported.'));
		_file.addEventListener(IOErrorEvent.IO_ERROR, function(_) _setStatus('Error export.'));
		_file.save(Json.stringify(w, null, '\t'), '${w.id}.json');
	}

	function _commitFields():Void {
		var w = _curW();
		if (w == null)
			return;
		w.id = _wId.text.trim();
		w.weekName = _wName.text;
		w.weekPath = _wPath.text.trim();
		w.color = _wColor.text.trim();
		w.locked = _wLocked.checked;
		w.order = Std.int(_wOrder.value);
		_refreshTitle();
	}

	// ============================================================
	// UPDATE
	// ============================================================

	override public function update(elapsed:Float):Void {
		super.update(elapsed);

		// Reflejar steppers de chars en tiempo real
		if (_tabMenu != null && _tabMenu.selected_tab_id == 'chars') {
			var chg = false;
			for (i in 0...3) {
				if (_cOffX[i] == null)
					continue;
				var nx = _cOffX[i].value;
				var ny = _cOffY[i].value;
				var ns = _cScale[i].value;
				var nf = _cFlip[i].checked;
				if (nx != _editOffX[i] || ny != _editOffY[i] || ns != _editScale[i] || nf != _editFlip[i]) {
					_editOffX[i] = nx;
					_editOffY[i] = ny;
					_editScale[i] = ns;
					_editFlip[i] = nf;
					chg = true;
				}
			}
			if (chg)
				_rebuildChars();
		}

		if (FlxG.keys.pressed.CONTROL) {
			if (FlxG.keys.justPressed.S)
				_onSave();
			if (FlxG.keys.justPressed.E)
				_onExport();
		}

		if (controls.BACK && !_anyFocused()) {
			funkin.system.CursorManager.hide();
			FlxG.sound.play(Paths.sound('menus/cancelMenu'));
			StateTransition.switchState(new EditorHubState());
		}

		if (_statusTimer > 0) {
			_statusTimer -= elapsed;
			if (_statusTimer <= 0)
				_statusTxt.text = _dirty ? '(Changes Unsaved)' : 'Done.';
		}
	}

	// ============================================================
	// HELPERS
	// ============================================================

	inline function _curW():Null<WeekData>
		return (_curWeek >= 0 && _curWeek < _weeks.length) ? _weeks[_curWeek] : null;

	function _newWeek(id:String):WeekData
		return {
			id: id,
			weekName: 'New Week',
			weekPath: '',
			weekCharacters: ['dad', 'bf', 'gf'],
			weekSongs: ['NewSong'],
			color: '0xFFFFD900',
			locked: false,
			order: _weeks.length
		};

	function _parseColor(hex:String):FlxColor {
		try {
			var v = Std.parseInt(hex);
			return (v != null) ? FlxColor.fromInt(v) : 0xFFFFD900;
		} catch (_) {
			return 0xFFFFD900;
		}
	}

	function _readDyn<T>(obj:Dynamic, field:String, def:T):T {
		var v = Reflect.field(obj, field);
		return (v != null) ? cast v : def;
	}

	function _setStatus(msg:String, dur:Float = 3.0):Void {
		_statusTxt.text = msg;
		_statusTimer = dur;
	}

	function _anyFocused():Bool {
		for (f in [_wId, _wName, _wPath, _wColor, _wSongIn])
			if (f != null && f.hasFocus)
				return true;
		return false;
	}

	function _mkBtn(bx:Float, by:Float, bw:Int, bh:Int, lbl:String, style:Int, cb:Void->Void):CoolButton {
		var b = new CoolButton(bx, by, lbl, cb, bw, bh, style);
		b.scrollFactor.set();
		return b;
	}

	override public function destroy():Void {
		super.destroy();
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// WeekListItem
// ─────────────────────────────────────────────────────────────────────────────

class WeekListItem extends flixel.group.FlxSpriteGroup {
	public var onSelect:Int->Void;

	var _idx:Int;
	var _iW:Int;
	var _iH:Int;
	var _sel:Bool;
	var _bg:FlxSprite;

	public function new(ix:Float, iy:Float, iw:Int, ih:Int, idx:Int, w:WeekData, sel:Bool) {
		super(ix, iy);
		_idx = idx;
		_iW = iw;
		_iH = ih;
		_sel = sel;
		_bg = new FlxSprite(0, 0);
		_bg.makeGraphic(iw, ih - 1, sel ? 0xFF1A2A3A : 0xFF0F0F1E);
		add(_bg);
		if (sel) {
			var ac = new FlxSprite(0, 0);
			ac.makeGraphic(3, ih - 1, 0xFF00D9FF);
			add(ac);
		}
		var nm = new FlxText(10, 5, iw - 14, w.weekName ?? w.id ?? 'Week ${idx + 1}', 12);
		nm.color = sel ? FlxColor.WHITE : 0xFFCCCCDD;
		nm.font = Paths.font("vcr.ttf");
		add(nm);
		var sg = new FlxText(10, nm.y + nm.height + 2, iw - 14, (w.weekSongs != null && w.weekSongs.length > 0) ? w.weekSongs.join(' • ') : '(No Songs)', 9);
		sg.color = 0xFF555577;
		sg.font = Paths.font("vcr.ttf");
		add(sg);
		var sep = new FlxSprite(0, ih - 1);
		sep.makeGraphic(iw, 1, 0x0EFFFFFF);
		add(sep);
	}

	override public function update(elapsed:Float):Void {
		super.update(elapsed);
		var hov = FlxG.mouse.x >= x && FlxG.mouse.x <= x + _iW && FlxG.mouse.y >= y && FlxG.mouse.y <= y + _iH;
		_bg.color = (hov && !_sel) ? 0xFF131328 : (_sel ? 0xFF1A2A3A : 0xFF0F0F1E);
		if (hov && FlxG.mouse.justPressed && onSelect != null)
			onSelect(_idx);
	}

	override public function destroy():Void {
		onSelect = null;
		super.destroy();
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// SongRow
// ─────────────────────────────────────────────────────────────────────────────

class SongRow extends flixel.group.FlxSpriteGroup {
	public var onDelete:Int->Void;

	var _idx:Int;

	public function new(rx:Float, ry:Float, rw:Int, name:String, idx:Int, onDel:Int->Void) {
		super(rx, ry);
		_idx = idx;
		onDelete = onDel;
		var bg = new FlxSprite(0, 0);
		bg.makeGraphic(rw, 22, 0xFF0A0A1A);
		add(bg);
		var num = new FlxText(4, 3, 22, '${idx + 1}.', 10);
		num.color = 0xFF555577;
		num.font = Paths.font("vcr.ttf");
		add(num);
		var lbl = new FlxText(24, 3, rw - 46, name, 10);
		lbl.color = 0xFFCCCCDD;
		lbl.font = Paths.font("vcr.ttf");
		add(lbl);
		var del = new CoolButton(rw - 20, 1, "×", function() {
			if (onDelete != null)
				onDelete(_idx);
		}, 18, 18, CoolButton.STYLE_DANGER);
		add(del);
		var sep = new FlxSprite(0, 21);
		sep.makeGraphic(rw, 1, 0x08FFFFFF);
		add(sep);
	}

	override public function destroy():Void {
		onDelete = null;
		super.destroy();
	}
}
