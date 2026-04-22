package funkin.debug;
import coolui.CoolDropDown;


import flixel.*;

import flixel.group.FlxGroup;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.tweens.*;
import flixel.ui.*;
import flixel.util.*;
import funkin.data.Song.SwagSong;
import openfl.events.TextEvent;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import funkin.audio.SoundTray;

using StringTools;

/**
 * ScriptEditorSubState v2 — Ventana de edición de scripts en HScript/Haxe.
 *
 * ARREGLOS:
 *  • Escritura de texto completamente funcional (OpenFL TextEvent.TEXT_INPUT)
 *  • Cursor | parpadeante en la posición exacta del caret
 *  • Resaltado de línea activa
 *  • Navegación con flechas, Home/End, Backspace, Delete, Enter (con auto-indent), Tab
 *  • SoundTray.blockInput = true mientras el editor está abierto
 *    → 0 / + / - NO cambian el volumen al escribir código
 *  • Ctrl+Z undo, Ctrl+W cerrar, Ctrl+S guardar, Ctrl+N nuevo
 *  • Arrastre de ventana funcional (todos los sprites se reposicionan)
 */
class ScriptEditorSubState extends FlxSubState
{
	// ── Paleta ────────────────────────────────────────────────────────────────
	static inline var C_BG          : Int = 0xF0101018;
	static inline var C_EDITOR      : Int = 0xFF0D0D1A;
	static inline var C_PANEL       : Int = 0xFF1A1A2A;
	static inline var C_ACCENT      : Int = 0xFF00D9FF;
	static inline var C_GREEN       : Int = 0xFF00FF88;
	static inline var C_RED         : Int = 0xFFFF3355;
	static inline var C_WHITE       : Int = 0xFFFFFFFF;
	static inline var C_GRAY        : Int = 0xFFAAAAAA;
	static inline var C_CURLINE     : Int = 0xFF1A1A35;  // Highlight línea activa

	// ── Layout ────────────────────────────────────────────────────────────────
	static inline var WIN_W         : Int = 820;
	static inline var WIN_H         : Int = 580;
	static inline var LIST_W        : Int = 180;
	static inline var TITLEBAR_H    : Int = 36;
	static inline var TOOLBAR_H     : Int = 34;
	static inline var LINENUM_W     : Int = 44;
	static inline var STATUS_H      : Int = 22;
	static inline var FONT_SIZE     : Int = 12;
	static inline var LINE_H        : Int = 15;
	static inline var CHAR_W        : Float = 7.2;  // Ancho aprox. de carácter monospace
	static inline var BLINK_RATE    : Float = 0.53;

	// ── State ─────────────────────────────────────────────────────────────────
	var _song          : SwagSong;
	var _camHUD        : FlxCamera;
	var _camSub        : FlxCamera;

	var _currentName   : String = "new_script";
	var _currentCode   : String = "";
	var _isDirty       : Bool   = false;
	var _scripts       : Map<String, String> = new Map();

	/** Callback invocado al guardar — recibe el código actual del script activo. */
	var _onSave        : Null<String->Void> = null;

	// ── Caret (posición absoluta en _currentCode) ─────────────────────────────
	var _caretPos      : Int    = 0;
	var _cursorLine    : Int    = 0;
	var _cursorCol     : Int    = 0;

	// ── Blink ────────────────────────────────────────────────────────────────
	var _blinkTimer    : Float  = 0;
	var _blinkVisible  : Bool   = true;

	// ── Scroll ────────────────────────────────────────────────────────────────
	var _scrollY       : Float  = 0;
	var _maxScrollY    : Float  = 0;

	// ── Window position ───────────────────────────────────────────────────────
	var _winX          : Float;
	var _winY          : Float;

	// Tracking de elementos para reposicionamiento al arrastrar
	var _movableSprites : Array<{s:FlxSprite, ox:Float, oy:Float}> = [];
	var _movableTexts   : Array<{t:FlxText,   ox:Float, oy:Float}> = [];

	// ── UI refs ───────────────────────────────────────────────────────────────
	var _codeText      : FlxText;
	var _lineNumText   : FlxText;
	var _cursorLineBg  : FlxSprite;
	var _statusText    : FlxText;
	var _lineColText   : FlxText;

	// Script list groups
	var _listItems     : FlxTypedGroup<FlxSprite>;
	var _listLabels    : FlxTypedGroup<FlxText>;

	// ── Drag ─────────────────────────────────────────────────────────────────
	var _isDragging    : Bool  = false;
	var _dragOffX      : Float = 0;
	var _dragOffY      : Float = 0;

	// ── Button rects (RELATIVAS a _winX/_winY) ────────────────────────────────
	var _btnRects : Array<{id:String, x:Float, y:Float, w:Float, h:Float}> = [];

	// ── Undo stack ───────────────────────────────────────────────────────────
	var _undoStack : Array<{code:String, caret:Int}> = [];
	static inline var MAX_UNDO = 60;

	// ── OpenFL listener refs ─────────────────────────────────────────────────
	var _textInputFn   : TextEvent->Void;
	var _keyDownFn     : KeyboardEvent->Void;

	// ── Templates ────────────────────────────────────────────────────────────
	static var TEMPLATES : Map<String, String> = [
		"Empty"         => "// New script\n// API: game, chars.bf(), chars.gf(), camera, stage\n\n",
		"Camera Zoom"   => "function onBeatHit(beat) {\n  if (beat % 4 == 0) {\n    camera.bumpZoom();\n  }\n}\n",
		"Char Anim"     => "function onPlayerNoteHit(note, rating) {\n  if (rating == 'sick') {\n    chars.bf().playAnim('hey', true);\n  }\n}\n",
		"Lightning"     => "var _nextBolt = 8;\nfunction onBeatHit(beat) {\n  if (FlxG.random.bool(10) && beat > _nextBolt) {\n    camera.flash(FlxColor.WHITE, 0.15);\n    _nextBolt = beat + FlxG.random.int(8, 24);\n  }\n}\n",
		"Custom Event"  => "function onEvent(name, v1, v2, time) {\n  switch(name.toLowerCase()) {\n    case 'my event':\n      trace('fired: ' + v1);\n  }\n  return false;\n}\n",
	];

	// ─────────────────────────────────────────────────────────────────────────
	/**
	 * @param song        Datos de la canción (para acceder a SONG.events).
	 * @param scriptName  Nombre del script a abrir por defecto.
	 * @param camHUD      Cámara HUD del estado padre.
	 * @param initialCode Código inicial a inyectar (usado por PSEScript inline/file).
	 *                    Si es null se busca en SONG.events como siempre.
	 * @param onSave      Callback(code) invocado cada vez que el usuario guarda.
	 *                    Permite al PSEEditor actualizar `scr.code` y escribir archivos.
	 */
	public function new(song:SwagSong, ?scriptName:String, ?camHUD:FlxCamera,
	                    ?initialCode:String, ?onSave:String->Void)
	{
		super(0x88000000);
		_song   = song;
		_camHUD = camHUD;
		_onSave = onSave;
		if (scriptName != null) _currentName = scriptName;

		if (_song?.events != null) {
			for (evt in _song.events) {
				if (Std.string(evt.type) == "Script") {
					var n = Std.string(evt.value);
					if (!_scripts.exists(n)) _scripts.set(n, "// Script: " + n + "\n\n");
				}
			}
		}

		// Si se pasó código inicial (PSEScript), inyectarlo en el mapa
		if (initialCode != null && initialCode != '')
			_scripts.set(_currentName, initialCode);

		_currentCode = _scripts.exists(_currentName)
			? _scripts.get(_currentName)
			: (TEMPLATES.get("Empty") ?? "// New script\n\n");
	}

	// ─── create ───────────────────────────────────────────────────────────────
	override function create() : Void
	{
		super.create();
		funkin.system.CursorManager.show();

		// Bloquear SoundTray para que +/-/0 no cambien el volumen
		SoundTray.blockInput = true;

		_camSub = new FlxCamera();
		_camSub.bgColor = 0x00000000;
		FlxG.cameras.add(_camSub);

		_winX = (FlxG.width  - WIN_W) / 2;
		_winY = (FlxG.height - WIN_H) / 2;

		_buildWindow();
		_refreshScriptList();
		_renderCode();

		// ── Listeners OpenFL para captura de texto real ───────────────────────
		_textInputFn = _onTextInput;
		_keyDownFn   = _onKeyDown;
		FlxG.stage.addEventListener(TextEvent.TEXT_INPUT,   _textInputFn);
		FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, _keyDownFn);
	}

	// ─── Build window ─────────────────────────────────────────────────────────
	function _buildWindow() : Void
	{
		var wx = _winX;
		var wy = _winY;

		// Overlay (no se mueve)
		var ov = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, 0xBB000000);
		ov.scrollFactor.set(); ov.cameras = [_camSub]; add(ov);

		// ── Fondo ventana + borde ─────────────────────────────────────────────
		_ws(new FlxSprite().makeGraphic(WIN_W, WIN_H, C_PANEL), 0, 0);
		var bd = new FlxSprite().makeGraphic(WIN_W, WIN_H, 0x00000000, true);
		_drawBorder(bd, WIN_W, WIN_H, 2, C_ACCENT);
		_ws(bd, 0, 0);

		// ── Titlebar ──────────────────────────────────────────────────────────
		_ws(new FlxSprite().makeGraphic(WIN_W, TITLEBAR_H, 0xFF080812), 0, 0);
		var ta = new FlxSprite().makeGraphic(WIN_W, 2, C_ACCENT); ta.alpha = 0.4;
		_ws(ta, 0, TITLEBAR_H - 2);

		_wt("📜 SCRIPT EDITOR", 12, 10, WIN_W - 100, 14, C_ACCENT, LEFT);
		_wt('— $_currentName',  200, 10, 300, 13, C_GRAY, LEFT);

		// Close btn
		_ws(new FlxSprite().makeGraphic(26, 26, 0xFF2A0808), WIN_W - 32, 4);
		_wt("✕", WIN_W - 32, 8, 26, 13, C_RED, CENTER);
		_regBtn("close", WIN_W - 32, 4, 26, 26);

		// ── Toolbar ───────────────────────────────────────────────────────────
		var tbY = TITLEBAR_H;
		_ws(new FlxSprite().makeGraphic(WIN_W, TOOLBAR_H, 0xFF0F0F1C), 0, tbY);

		var btns = [
			{id:"new",   lbl:"＋ New",   bg:0xFF1A2A1A, tc:C_GREEN},
			{id:"save",  lbl:"💾 Save",  bg:0xFF1A2A2A, tc:C_ACCENT},
			{id:"delete",lbl:"🗑 Delete", bg:0xFF2A1A1A, tc:C_RED},
		];
		var bx = 8;
		for (b in btns) {
			_ws(new FlxSprite().makeGraphic(76, 26, b.bg), bx, tbY + 4);
			_wt(b.lbl, bx, tbY + 10, 76, 10, b.tc, CENTER);
			_regBtn(b.id, bx, tbY + 4, 76, 26);
			bx += 82;
		}

		_wt("Template:", bx + 4, tbY + 8, 0, 10, C_GRAY, LEFT);

		var tNames = [for (k in TEMPLATES.keys()) k];
		var dd = new CoolDropDown(wx + bx + 68, wy + tbY + 4,
			CoolDropDown.makeStrIdLabelArray(tNames, true),
			function(id:String) {
				var i = Std.parseInt(id);
				if (i != null && i >= 0 && i < tNames.length) _applyTemplate(tNames[i]);
			});
		dd.scrollFactor.set(); dd.cameras = [_camSub]; add(dd);

		// ── Script list ───────────────────────────────────────────────────────
		var edY  = tbY + TOOLBAR_H;
		var edH  = WIN_H - TITLEBAR_H - TOOLBAR_H - STATUS_H;

		_ws(new FlxSprite().makeGraphic(LIST_W, edH, 0xFF0A0A14), 0, edY);
		_ws(new FlxSprite().makeGraphic(LIST_W, 18, 0xFF060610),  0, edY);
		_wt("Scripts", 6, edY + 3, LIST_W - 12, 10, C_ACCENT, LEFT);

		_listItems  = new FlxTypedGroup<FlxSprite>();
		_listLabels = new FlxTypedGroup<FlxText>();
		_listItems.cameras  = [_camSub];
		_listLabels.cameras = [_camSub];
		add(_listItems); add(_listLabels);

		// ── Editor área ───────────────────────────────────────────────────────
		var edX = LIST_W + 2;
		var edW = WIN_W - LIST_W - 2;

		// Highlight línea activa (posicionado en _renderCode)
		_cursorLineBg = _ws(new FlxSprite().makeGraphic(edW - LINENUM_W, LINE_H, C_CURLINE),
			edX + LINENUM_W, edY);
		_cursorLineBg.alpha = 0.85;

		// Gutter números de línea
		_ws(new FlxSprite().makeGraphic(LINENUM_W, edH, 0xFF080810),  edX, edY);
		_ws(new FlxSprite().makeGraphic(1, edH, 0xFF222233), edX + LINENUM_W - 1, edY);
		_lineNumText = _wt("", edX + 4, edY + 4, LINENUM_W - 8, FONT_SIZE, 0xFF555577, RIGHT);

		// Área de código
		_ws(new FlxSprite().makeGraphic(edW - LINENUM_W, edH, C_EDITOR), edX + LINENUM_W, edY);
		_codeText = _wt("", edX + LINENUM_W + 6, edY + 4, edW - LINENUM_W - 12, FONT_SIZE, C_WHITE, LEFT);

		// ── Status bar ────────────────────────────────────────────────────────
		var stY = WIN_H - STATUS_H;
		_ws(new FlxSprite().makeGraphic(WIN_W, STATUS_H, 0xFF060610), 0, stY);
		_statusText  = _wt("Ready",       8,          stY + 5, WIN_W - 200, 10, C_GRAY, LEFT);
		_lineColText = _wt("Ln 1, Col 1", WIN_W - 140, stY + 5, 130, 10, C_GRAY, RIGHT);
	}

	// ─── _ws: window sprite helper ────────────────────────────────────────────
	/** Añade un sprite con posición RELATIVA a (_winX, _winY) y lo registra para reposicionamiento. */
	function _ws(spr:FlxSprite, ox:Float, oy:Float) : FlxSprite
	{
		spr.x = _winX + ox; spr.y = _winY + oy;
		spr.scrollFactor.set(); spr.cameras = [_camSub]; add(spr);
		_movableSprites.push({s:spr, ox:ox, oy:oy});
		return spr;
	}

	// ─── _wt: window text helper ──────────────────────────────────────────────
	function _wt(text:String, ox:Float, oy:Float, ?width:Int, ?size:Int,
	             ?col:Int, ?align:FlxTextAlign) : FlxText
	{
		var t = new FlxText(_winX + ox, _winY + oy, width ?? 0, text, size ?? FONT_SIZE);
		t.font = Paths.font("vcr.ttf");
		if (col   != null) t.color = col;
		if (align != null) t.alignment = align;
		t.scrollFactor.set(); t.cameras = [_camSub]; add(t);
		_movableTexts.push({t:t, ox:ox, oy:oy});
		return t;
	}

	// ─── Script list ──────────────────────────────────────────────────────────
	function _refreshScriptList() : Void
	{
		if (_listItems == null) return;
		_listItems.clear(); _listLabels.clear();

		var listBaseY = _winY + TITLEBAR_H + TOOLBAR_H + 20;
		var scripts = [for (k in _scripts.keys()) k];
		if (scripts.length == 0) scripts = [_currentName];

		for (i in 0...scripts.length) {
			var name     = scripts[i];
			var isActive = (name == _currentName);
			var iy       = listBaseY + i * 22;

			var ibg = new FlxSprite(_winX, iy).makeGraphic(LIST_W, 20,
				isActive ? 0xFF1A2A3A : 0xFF0C0C18);
			ibg.scrollFactor.set(); ibg.cameras = [_camSub]; _listItems.add(ibg);

			var ilbl = new FlxText(_winX + 8, iy + 4, LIST_W - 16, name, 9);
			ilbl.setFormat(Paths.font("vcr.ttf"), 9, isActive ? C_ACCENT : C_GRAY, LEFT);
			ilbl.scrollFactor.set(); ilbl.cameras = [_camSub]; _listLabels.add(ilbl);

			// btn en coords relativas a ventana
			_regBtn('list_$i', 0, TITLEBAR_H + TOOLBAR_H + 20 + i * 22, LIST_W, 20);
		}
	}

	// ─── Render ───────────────────────────────────────────────────────────────
	function _renderCode() : Void
	{
		if (_codeText == null) return;

		_updateLineCol();

		var lines     = _currentCode.split("\n");
		var totalL    = lines.length;
		var edH       = WIN_H - TITLEBAR_H - TOOLBAR_H - STATUS_H;
		var visLines  = Std.int(edH / LINE_H) + 2;

		// Auto-scroll para mantener el cursor visible
		var cpxY = _cursorLine * LINE_H;
		if (cpxY < _scrollY)
			_scrollY = cpxY;
		else if (cpxY + LINE_H > _scrollY + edH - LINE_H)
			_scrollY = cpxY - edH + LINE_H * 2;
		_maxScrollY = Math.max(0, (totalL - visLines + 2) * LINE_H);
		_scrollY    = FlxMath.bound(_scrollY, 0, _maxScrollY);

		var startL = Std.int(_scrollY / LINE_H);
		var endL   = Std.int(Math.min(startL + visLines, totalL));

		// Números de línea
		var nums = "";
		for (i in startL...endL) nums += '${i + 1}\n';
		_lineNumText.text = nums;

		// Código con cursor | parpadeante inline
		var code = "";
		for (i in startL...endL) {
			var line = lines[i];
			if (i == _cursorLine && _blinkVisible) {
				var col = Std.int(FlxMath.bound(_cursorCol, 0, line.length));
				line = line.substr(0, col) + "|" + line.substr(col);
			}
			code += line + "\n";
		}
		_codeText.text = code;

		// Posición del highlight de línea activa
		if (_cursorLineBg != null) {
			var editorTopY = _winY + TITLEBAR_H + TOOLBAR_H + 4;
			var lineY      = editorTopY + (_cursorLine - startL) * LINE_H;
			if (_cursorLine >= startL && _cursorLine < endL) {
				_cursorLineBg.visible = true;
				_cursorLineBg.y = lineY;
			} else {
				_cursorLineBg.visible = false;
			}
		}

		// Indicador de posición
		if (_lineColText != null)
			_lineColText.text = 'Ln ${_cursorLine + 1}, Col ${_cursorCol + 1}  •  $totalL lines';
	}

	// ─── Calcular cursorLine/Col desde _caretPos ──────────────────────────────
	function _updateLineCol() : Void
	{
		_caretPos = Std.int(FlxMath.bound(_caretPos, 0, _currentCode.length));
		var before = _currentCode.substr(0, _caretPos);
		var lines  = before.split("\n");
		_cursorLine = lines.length - 1;
		_cursorCol  = lines[lines.length - 1].length;
	}

	// ─── update ───────────────────────────────────────────────────────────────
	override function update(elapsed:Float) : Void
	{
		super.update(elapsed);
		_handleDrag();
		_handleScroll();
		_handleClick();
		_handleFlixelKeys();

		_blinkTimer += elapsed;
		if (_blinkTimer >= BLINK_RATE) {
			_blinkTimer   = 0;
			_blinkVisible = !_blinkVisible;
			_renderCode();
		}
	}

	// ─── Drag ────────────────────────────────────────────────────────────────
	function _handleDrag() : Void
	{
		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;
		var inTitle = mx >= _winX && mx <= _winX + WIN_W
		           && my >= _winY && my <= _winY + TITLEBAR_H;

		if (FlxG.mouse.justPressed && inTitle && !_isBtnAt(mx, my)) {
			_isDragging = true;
			_dragOffX   = mx - _winX;
			_dragOffY   = my - _winY;
		}
		if (_isDragging) {
			_winX = FlxMath.bound(mx - _dragOffX, 0, FlxG.width  - WIN_W);
			_winY = FlxMath.bound(my - _dragOffY, 0, FlxG.height - WIN_H);
			_repositionAll();
		}
		if (FlxG.mouse.justReleased) _isDragging = false;
	}

	function _repositionAll() : Void
	{
		for (e in _movableSprites) { e.s.x = _winX + e.ox; e.s.y = _winY + e.oy; }
		for (e in _movableTexts)   { e.t.x = _winX + e.ox; e.t.y = _winY + e.oy; }
		_refreshScriptList();
		_renderCode();
	}

	// ─── Scroll ──────────────────────────────────────────────────────────────
	function _handleScroll() : Void
	{
		if (FlxG.mouse.wheel == 0) return;
		var mx = FlxG.mouse.x; var my = FlxG.mouse.y;
		if (mx > _winX + LIST_W && mx < _winX + WIN_W
		 && my > _winY + TITLEBAR_H + TOOLBAR_H && my < _winY + WIN_H - STATUS_H) {
			_scrollY -= FlxG.mouse.wheel * LINE_H * 3;
			_scrollY = FlxMath.bound(_scrollY, 0, _maxScrollY);
			_renderCode();
		}
	}

	// ─── Click ───────────────────────────────────────────────────────────────
	function _handleClick() : Void
	{
		if (!FlxG.mouse.justPressed) return;
		var mx = FlxG.mouse.x; var my = FlxG.mouse.y;

		// Botones (coordenadas relativas a ventana)
		if (_isBtnAt(mx, my)) {
			var rx = mx - _winX; var ry = my - _winY;
			for (b in _btnRects) {
				if (rx >= b.x && rx <= b.x + b.w && ry >= b.y && ry <= b.y + b.h) {
					_onBtnClick(b.id); return;
				}
			}
		}

		// Click en código → posicionar caret
		var codeAreaX = _winX + LIST_W + 2 + LINENUM_W + 6;
		var codeAreaY = _winY + TITLEBAR_H + TOOLBAR_H + 4;
		if (mx >= codeAreaX && mx <= _winX + WIN_W
		 && my >= codeAreaY && my <= _winY + WIN_H - STATUS_H) {
			var relY = my - codeAreaY + _scrollY;
			var relX = mx - codeAreaX;
			_moveCaretToLineCol(Std.int(relY / LINE_H), Std.int(relX / CHAR_W));
			_blinkVisible = true; _blinkTimer = 0;
			_renderCode();
		}
	}

	// ─── Mover caret a línea/col ──────────────────────────────────────────────
	function _moveCaretToLineCol(line:Int, col:Int) : Void
	{
		var lines = _currentCode.split("\n");
		line = Std.int(FlxMath.bound(line, 0, lines.length - 1));
		col  = Std.int(FlxMath.bound(col,  0, lines[line].length));
		var pos = 0;
		for (i in 0...line) pos += lines[i].length + 1;
		pos += col;
		_caretPos = Std.int(FlxMath.bound(pos, 0, _currentCode.length));
	}

	// ─── Botones ─────────────────────────────────────────────────────────────
	function _onBtnClick(id:String) : Void
	{
		switch (id) {
			case "close":  _close();
			case "new":    _newScript();
			case "save":   _save();
			case "delete": _deleteScript();
			case _ if (id.startsWith("list_")):
				var idx  = Std.parseInt(id.substr(5));
				var list = [for (k in _scripts.keys()) k];
				if (idx != null && idx >= 0 && idx < list.length) _switchScript(list[idx]);
		}
	}

	// ─── OpenFL TEXT_INPUT → caracteres imprimibles ───────────────────────────
	function _onTextInput(e:TextEvent) : Void
	{
		if (!_isOverWindow()) return;
		var ch = e.text;
		if (ch == null || ch.length == 0) return;
		var code = ch.charCodeAt(0);
		// Filtrar caracteres de control (Enter, Backspace, etc. ya en KEY_DOWN)
		if (code < 32 || code == 127) return;
		_insertText(ch);
	}

	// ─── OpenFL KEY_DOWN → control keys ──────────────────────────────────────
	function _onKeyDown(e:KeyboardEvent) : Void
	{
		if (!_isOverWindow()) return;
		var kc = e.keyCode;

		if (e.ctrlKey) {
			switch (kc) {
				case Keyboard.S: _save();  e.stopImmediatePropagation(); return;
				case Keyboard.Z: _undo();  e.stopImmediatePropagation(); return;
				case Keyboard.A: _caretPos = _currentCode.length; _renderCode();
				                 e.stopImmediatePropagation(); return;
			}
		}

		switch (kc) {
			case Keyboard.BACKSPACE:
				_backspace(); e.stopImmediatePropagation();
			case Keyboard.DELETE:
				_deleteForward(); e.stopImmediatePropagation();
			case Keyboard.ENTER:
				_insertNewline(); e.stopImmediatePropagation();
			case Keyboard.TAB:
				_insertText("  "); e.stopImmediatePropagation();
			case Keyboard.LEFT:
				if (_caretPos > 0) { _caretPos--; _renderCode(); }
				e.stopImmediatePropagation();
			case Keyboard.RIGHT:
				if (_caretPos < _currentCode.length) { _caretPos++; _renderCode(); }
				e.stopImmediatePropagation();
			case Keyboard.UP:
				_updateLineCol(); _moveCaretToLineCol(_cursorLine - 1, _cursorCol); _renderCode();
				e.stopImmediatePropagation();
			case Keyboard.DOWN:
				_updateLineCol(); _moveCaretToLineCol(_cursorLine + 1, _cursorCol); _renderCode();
				e.stopImmediatePropagation();
			case Keyboard.HOME:
				_updateLineCol(); _moveCaretToLineCol(_cursorLine, 0); _renderCode();
				e.stopImmediatePropagation();
			case Keyboard.END:
				_updateLineCol();
				var ll = _currentCode.split("\n");
				var len = _cursorLine < ll.length ? ll[_cursorLine].length : 0;
				_moveCaretToLineCol(_cursorLine, len); _renderCode();
				e.stopImmediatePropagation();
		}

		_blinkVisible = true; _blinkTimer = 0;
	}

	// ─── Flixel keys (solo Ctrl+W, Ctrl+N, ESC — no conflictan con texto) ─────
	function _handleFlixelKeys() : Void
	{
		if (FlxG.keys.pressed.CONTROL) {
			if (FlxG.keys.justPressed.W) { _close(); return; }
			if (FlxG.keys.justPressed.N) { _newScript(); return; }
		}
		if (FlxG.keys.justPressed.ESCAPE) _close();
	}

	// ─── Insertar texto ───────────────────────────────────────────────────────
	function _insertText(text:String) : Void
	{
		_pushUndo();
		var a = _currentCode.substr(0, _caretPos);
		var b = _currentCode.substr(_caretPos);
		_currentCode = a + text + b;
		_caretPos   += text.length;
		_isDirty     = true;
		_renderCode();
	}

	// ─── Enter con auto-indent ────────────────────────────────────────────────
	function _insertNewline() : Void
	{
		_pushUndo();
		_updateLineCol();
		var lines   = _currentCode.split("\n");
		var curLine = _cursorLine < lines.length ? lines[_cursorLine] : "";
		var indent  = ""; var i = 0;
		while (i < curLine.length && (curLine.charAt(i) == " " || curLine.charAt(i) == "\t"))
			indent += curLine.charAt(i++);
		if (StringTools.rtrim(curLine).endsWith("{")) indent += "  ";

		var a = _currentCode.substr(0, _caretPos);
		var b = _currentCode.substr(_caretPos);
		_currentCode = a + "\n" + indent + b;
		_caretPos   = _caretPos + 1 + indent.length;
		_isDirty     = true;
		_renderCode();
	}

	// ─── Backspace / Delete ───────────────────────────────────────────────────
	function _backspace() : Void
	{
		if (_caretPos <= 0) return;
		_pushUndo();
		_currentCode = _currentCode.substr(0, _caretPos - 1) + _currentCode.substr(_caretPos);
		_caretPos--; _isDirty = true; _renderCode();
	}
	function _deleteForward() : Void
	{
		if (_caretPos >= _currentCode.length) return;
		_pushUndo();
		_currentCode = _currentCode.substr(0, _caretPos) + _currentCode.substr(_caretPos + 1);
		_isDirty = true; _renderCode();
	}

	// ─── Undo ─────────────────────────────────────────────────────────────────
	function _pushUndo() : Void
	{
		_undoStack.push({code: _currentCode, caret: _caretPos});
		if (_undoStack.length > MAX_UNDO) _undoStack.shift();
	}
	function _undo() : Void
	{
		if (_undoStack.length == 0) return;
		var st = _undoStack.pop();
		_currentCode = st.code; _caretPos = st.caret;
		_isDirty = true; _renderCode();
		_showStatus("↩ Undo");
	}

	// ─── ¿El mouse está sobre la ventana? ────────────────────────────────────
	function _isOverWindow() : Bool
	{
		var mx = FlxG.mouse.x; var my = FlxG.mouse.y;
		return mx >= _winX && mx <= _winX + WIN_W && my >= _winY && my <= _winY + WIN_H;
	}

	// ─── Actions ─────────────────────────────────────────────────────────────
	function _newScript() : Void
	{
		var name = 'script_${Lambda.count(_scripts) + 1}';
		_scripts.set(name, TEMPLATES.get("Empty") ?? "// New script\n\n");
		_currentName = name;
		_currentCode = _scripts.get(name);
		_caretPos    = _currentCode.length;
		_isDirty     = false; _undoStack = [];
		_refreshScriptList(); _renderCode();
		_addScriptEventToSong(name);
		_showStatus('✅ Created "$name"');
	}

	function _save() : Void
	{
		_scripts.set(_currentName, _currentCode);
		_isDirty = false;
		_updateScriptEventInSong(_currentName, _currentCode);
		// Notificar al editor padre (PSEEditor) para que actualice scr.code
		// y escriba en disco si tiene savePath configurado
		if (_onSave != null) _onSave(_currentCode);
		_showStatus('💾 Saved "$_currentName"');
		FlxG.sound.play(Paths.sound('menus/confirmMenu'), 0.4);
	}

	function _deleteScript() : Void
	{
		if (!_scripts.exists(_currentName)) { _close(); return; }
		_scripts.remove(_currentName);
		_removeScriptEventFromSong(_currentName);
		var keys = [for (k in _scripts.keys()) k];
		_currentName = keys.length > 0 ? keys[0] : "new_script";
		_currentCode = _scripts.exists(_currentName) ? _scripts.get(_currentName) : "";
		_caretPos    = 0; _undoStack = [];
		_refreshScriptList(); _renderCode();
		_showStatus("🗑 Deleted script");
	}

	function _switchScript(name:String) : Void
	{
		if (_isDirty) _scripts.set(_currentName, _currentCode);
		_currentName = name;
		_currentCode = _scripts.exists(name) ? _scripts.get(name) : "";
		_scrollY = 0; _caretPos = 0; _isDirty = false; _undoStack = [];
		_refreshScriptList(); _renderCode();
		_showStatus('📂 Loaded "$name"');
	}

	function _applyTemplate(name:String) : Void
	{
		var code = TEMPLATES.get(name);
		if (code == null) return;
		_pushUndo();
		_currentCode = code; _caretPos = code.length;
		_isDirty = true; _renderCode();
		_showStatus('📋 Applied "$name"');
	}

	// ─── Song events ─────────────────────────────────────────────────────────
	function _addScriptEventToSong(name:String) : Void
	{
		if (_song?.events == null) return;
		for (e in _song.events) if (Std.string(e.type) == "Script" && Std.string(e.value) == name) return;
		_song.events.push({stepTime: 0, type: "Script", value: name});
	}
	function _updateScriptEventInSong(name:String, _code:String) : Void
	{
		if (_song?.events == null) return;
		for (e in _song.events) if (Std.string(e.type) == "Script" && Std.string(e.value) == name) return;
		_addScriptEventToSong(name);
	}
	function _removeScriptEventFromSong(name:String) : Void
	{
		if (_song?.events == null) return;
		_song.events = _song.events.filter(
			e -> !(Std.string(e.type) == "Script" && Std.string(e.value) == name));
	}

	// ─── Close ───────────────────────────────────────────────────────────────
	function _close() : Void
	{
		if (_isDirty) _scripts.set(_currentName, _currentCode);
		SoundTray.blockInput = false;
		FlxG.cameras.remove(_camSub);
		close();
	}

	// ─── Util ────────────────────────────────────────────────────────────────
	function _isBtnAt(mx:Float, my:Float) : Bool
	{
		var rx = mx - _winX; var ry = my - _winY;
		for (b in _btnRects) if (rx >= b.x && rx <= b.x + b.w && ry >= b.y && ry <= b.y + b.h) return true;
		return false;
	}

	function _regBtn(id:String, x:Float, y:Float, w:Float, h:Float) : Void
	{
		_btnRects = _btnRects.filter(b -> b.id != id);
		_btnRects.push({id:id, x:x, y:y, w:w, h:h});
	}

	function _showStatus(msg:String) : Void
	{
		if (_statusText == null) return;
		FlxTween.cancelTweensOf(_statusText);
		_statusText.text = msg; _statusText.alpha = 1;
		FlxTween.tween(_statusText, {alpha: 0.5}, 0.3, {startDelay: 2.0});
	}

	function _drawBorder(spr:FlxSprite, w:Int, h:Int, t:Int, col:Int) : Void
	{
		var gu = flixel.util.FlxSpriteUtil;
		gu.drawRect(spr, 0, 0, w, t, col);
		gu.drawRect(spr, 0, h-t, w, t, col);
		gu.drawRect(spr, 0, 0, t, h, col);
		gu.drawRect(spr, w-t, 0, t, h, col);
		spr.dirty = true;
	}

	// ─── destroy ─────────────────────────────────────────────────────────────
	override function destroy() : Void
	{
		SoundTray.blockInput = false;
		if (_textInputFn != null) FlxG.stage.removeEventListener(TextEvent.TEXT_INPUT, _textInputFn);
		if (_keyDownFn   != null) FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, _keyDownFn);
		if (_camSub != null) FlxG.cameras.remove(_camSub, false);
		super.destroy();
	}
}
