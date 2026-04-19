package funkin.debug.editors;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.text.FlxText;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.util.FlxColor;
import flixel.math.FlxPoint;
import flixel.math.FlxMath;
import openfl.display.Sprite;
import openfl.display.Shape;
import openfl.display.Graphics;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.events.MouseEvent;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import funkin.states.MusicBeatState;
import funkin.transitions.StateTransition;
import funkin.audio.MusicManager;
import haxe.Json;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

// ─────────────────────────────────────────────────────────────────────────
// TYPEDEF DATA
// ─────────────────────────────────────────────────────────────────────────
private typedef NodeData = {
	var id:String;
	var label:String;
	var className:String;
	var x:Float;
	var y:Float;
};

private typedef ConnData = {
	var id:String;
	var fromId:String;
	var toId:String;
	var label:String;
};

/**
 * NodeMenuEditor — Editor visual de nodos para conectar menús entre sí.
 *
 * ══════════════════════════════════════════════════════════════════════
 *  CONCEPTO
 * ══════════════════════════════════════════════════════════════════════
 *  Cada nodo representa un FlxState (menú/state del engine).
 *  Las flechas conectan un nodo-origen (output port ▶) a un
 *  nodo-destino (input port ◀).  El grafo resultante describe cómo
 *  fluye la navegación del juego.
 *
 *  El editor no modifica los states — es una herramienta visual de
 *  planificación / documentación que puede exportar el grafo a JSON
 *  para que scripts externos lo consuman.
 *
 * ══════════════════════════════════════════════════════════════════════
 *  CONTROLES
 * ══════════════════════════════════════════════════════════════════════
 *  Ratón
 *    LMB drag en canvas vacío   Pan de la vista
 *    LMB drag en nodo           Mover nodo
 *    LMB click en output (▶)    Empezar conexión (arrastrar al input)
 *    LMB click en input  (◀)    Terminar conexión
 *    LMB click en nodo           Seleccionar
 *    RMB click en nodo           Menú contextual (borrar)
 *    RMB click en flecha         Borrar conexión
 *    Rueda                       Zoom in/out
 *
 *  Teclado
 *    Delete / Backspace          Borrar nodo / conexión seleccionada
 *    Ctrl+S                      Guardar JSON
 *    Ctrl+Z                      Undo (deshacer última acción)
 *    Ctrl+A                      Seleccionar todos
 *    F                           Fit all nodes in view
 *    ESC                         Deseleccionar / cancelar / salir
 *    ~  (tilde)                  Abrir ScriptConsoleState
 *
 * ══════════════════════════════════════════════════════════════════════
 *  PANELES
 * ══════════════════════════════════════════════════════════════════════
 *  Izquierda — Biblioteca de nodos (click para añadir al canvas)
 *  Centro    — Canvas infinito pan+zoom
 *  Derecha   — Propiedades del nodo seleccionado
 *  Abajo     — Status bar
 */
class NodeMenuEditor extends MusicBeatState {
	// ── Layout constants ────────────────────────────────────────────────────
	static inline var SW:Int = 1280;
	static inline var SH:Int = 720;
	static inline var LIB_W:Int = 190; // left library panel width
	static inline var PROP_W:Int = 220; // right properties panel width
	static inline var STAT_H:Int = 22; // bottom status bar height
	static inline var HDR_H:Int = 36; // top header height
	static inline var CANVAS_X:Int = LIB_W;
	static inline var CANVAS_Y:Int = HDR_H;
	static inline var CANVAS_W:Int = SW - LIB_W - PROP_W;
	static inline var CANVAS_H:Int = SH - HDR_H - STAT_H;

	// ── Node dimensions ──────────────────────────────────────────────────────
	static inline var NODE_W:Int = 160;
	static inline var NODE_H:Int = 54;
	static inline var PORT_R:Int = 7; // port circle radius
	static inline var PORT_OX:Int = 8; // port X offset from node edge

	// ── Colours ──────────────────────────────────────────────────────────────
	static inline var C_BG:Int = 0xFF0A0A12;
	static inline var C_GRID:Int = 0xFF141428;
	static inline var C_PANEL:Int = 0xFF0D0D1E;
	static inline var C_PANEL_BORDER:Int = 0xFF1A1A3A;
	static inline var C_HEADER:Int = 0xFF00D9FF;
	static inline var C_ACCENT:Int = 0xFF00D9FF;
	static inline var C_TEXT:Int = 0xFFDDEEFF;
	static inline var C_DIM:Int = 0xFF556677;
	static inline var C_SEL:Int = 0xFFFFFF00;
	static inline var C_CONN:Int = 0xFF00FFAA;
	static inline var C_CONN_DRAG:Int = 0xFFFFAA00;
	static inline var C_PORT_OUT:Int = 0xFF00D9FF;
	static inline var C_PORT_IN:Int = 0xFFAA44FF;
	static inline var C_STATUS_OK:Int = 0xFF00FF88;
	static inline var C_STATUS_WARN:Int = 0xFFFFCC00;
	static inline var C_STATUS_ERR:Int = 0xFFFF4466;

	// Node type colours
	static var NODE_TYPE_COLORS:Map<String, Int> = [
		'MainMenuState' => 0xFF1A2A5A,
		'FreeplayState' => 0xFF1A3A2A,
		'StoryMenuState' => 0xFF3A1A3A,
		'OptionsMenuState' => 0xFF3A2A1A,
		'CharacterSelectorState' => 0xFF1A3A3A,
		'CreditsState' => 0xFF2A1A3A,
		'EditorHubState' => 0xFF3A1A1A,
		'ModSelectorState' => 0xFF1A2A3A,
		'IntroState' => 0xFF2A3A1A,
		'ScriptConsoleState' => 0xFF0A1A3A,
		'custom' => 0xFF1E1E30,
	];

	// ── Data ─────────────────────────────────────────────────────────────────
	var _nodes:Array<NodeData> = [];
	var _conns:Array<ConnData> = [];
	var _nextId:Int = 0;

	var _selectedNode:Null<NodeData> = null;
	var _selectedConn:Null<ConnData> = null;

	// ── Canvas transform ─────────────────────────────────────────────────────
	var _panX:Float = 60;
	var _panY:Float = 60;
	var _zoom:Float = 1.0;

	static inline var ZOOM_MIN:Float = 0.25;
	static inline var ZOOM_MAX:Float = 2.5;

	// ── Drag state ───────────────────────────────────────────────────────────
	var _draggingNode:Null<NodeData> = null;
	var _dragOffX:Float = 0;
	var _dragOffY:Float = 0;

	var _panning:Bool = false;
	var _panStartX:Float = 0;
	var _panStartY:Float = 0;
	var _panStartPX:Float = 0;
	var _panStartPY:Float = 0;

	var _connectingFrom:Null<NodeData> = null; // node being connected from
	var _connectDragX:Float = 0;
	var _connectDragY:Float = 0;

	// ── OpenFL canvas ────────────────────────────────────────────────────────
	var _canvasSprite:Sprite;
	var _gridShape:Shape;
	var _connShape:Shape; // permanent connections
	var _dragConnShape:Shape; // connection being dragged
	var _nodeSprites:Map<String, Sprite> = [];

	// ── UI sprites (FlxSprite overlays) ──────────────────────────────────────
	var _camHUD:FlxCamera;
	var _statusTxt:FlxText;
	var _propNameTxt:FlxText;
	var _propClassTxt:FlxText;
	var _headerTxt:FlxText;

	// ── Undo stack ──────────────────────────────────────────────────────────
	var _undo:Array<String> = []; // serialised snapshots
	var _unsaved:Bool = false;

	// ─────────────────────────────────────────────────────────────────────────
	// CREATE
	// ─────────────────────────────────────────────────────────────────────────
	override function create():Void {
		super.create();

		MusicManager.play('chartEditorLoop/chartEditorLoop', 0.5);

		funkin.system.CursorManager.show();

		// ── HUD camera ──────────────────────────────────────────────────────
		_camHUD = new FlxCamera();
		_camHUD.bgColor = FlxColor.TRANSPARENT;
		FlxG.cameras.add(_camHUD, false);

		// ── Background ──────────────────────────────────────────────────────
		var bg = new FlxSprite().makeGraphic(SW, SH, FlxColor.fromInt(C_BG));
		bg.scrollFactor.set();
		add(bg);

		// ── OpenFL canvas root ───────────────────────────────────────────────
		_canvasSprite = new Sprite();
		_canvasSprite.x = CANVAS_X;
		_canvasSprite.y = CANVAS_Y;
		_canvasSprite.scrollRect = new openfl.geom.Rectangle(0, 0, CANVAS_W, CANVAS_H);
		FlxG.stage.addChild(_canvasSprite);

		_gridShape = new Shape();
		_connShape = new Shape();
		_dragConnShape = new Shape();
		_canvasSprite.addChild(_gridShape);
		_canvasSprite.addChild(_connShape);
		_canvasSprite.addChild(_dragConnShape);

		// ── Build UI (FlxSprite panels) ──────────────────────────────────────
		_buildPanels();
		_buildLibraryPanel();
		_buildPropertiesPanel();
		_buildHeader();
		_buildStatusBar();

		// ── Events ──────────────────────────────────────────────────────────
		_canvasSprite.addEventListener(MouseEvent.MOUSE_DOWN, _onCanvasMouseDown);
		_canvasSprite.addEventListener(MouseEvent.MOUSE_MOVE, _onCanvasMouseMove);
		FlxG.stage.addEventListener(MouseEvent.MOUSE_UP, _onMouseUp);
		FlxG.stage.addEventListener(MouseEvent.MOUSE_WHEEL, _onMouseWheel);
		FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, _onKeyDown);

		// ── Default graph — starter nodes ────────────────────────────────────
		_addNode('MainMenuState', 'Main Menu', 80, 80);
		_addNode('FreeplayState', 'Freeplay', 360, 60);
		_addNode('StoryMenuState', 'Story Mode', 360, 150);
		_addNode('OptionsMenuState', 'Options', 360, 240);
		_addConnection(_nodes[0].id, _nodes[1].id, 'Freeplay');
		_addConnection(_nodes[0].id, _nodes[2].id, 'Story');
		_addConnection(_nodes[0].id, _nodes[3].id, 'Options');

		_redrawAll();
		_saveUndo();
		_status('Node Menu Editor ready — LMB drag node  •  drag ▶ to connect  •  Ctrl+S save', C_STATUS_OK);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// UI BUILD
	// ─────────────────────────────────────────────────────────────────────────
	function _buildPanels():Void {
		// Left panel bg
		var lp = new FlxSprite(0, HDR_H).makeGraphic(LIB_W, SH - HDR_H - STAT_H, FlxColor.fromInt(C_PANEL));
		lp.scrollFactor.set();
		lp.cameras = [_camHUD];
		add(lp);
		var lb = new FlxSprite(LIB_W - 1, HDR_H).makeGraphic(1, SH - HDR_H - STAT_H, FlxColor.fromInt(C_PANEL_BORDER));
		lb.scrollFactor.set();
		lb.cameras = [_camHUD];
		add(lb);

		// Right panel bg
		var rp = new FlxSprite(SW - PROP_W, HDR_H).makeGraphic(PROP_W, SH - HDR_H - STAT_H, FlxColor.fromInt(C_PANEL));
		rp.scrollFactor.set();
		rp.cameras = [_camHUD];
		add(rp);
		var rb = new FlxSprite(SW - PROP_W, HDR_H).makeGraphic(1, SH - HDR_H - STAT_H, FlxColor.fromInt(C_PANEL_BORDER));
		rb.scrollFactor.set();
		rb.cameras = [_camHUD];
		add(rb);
	}

	function _buildHeader():Void {
		var hdrBg = new FlxSprite(0, 0).makeGraphic(SW, HDR_H, FlxColor.fromInt(0xFF070714));
		hdrBg.scrollFactor.set();
		hdrBg.cameras = [_camHUD];
		add(hdrBg);
		var hdrLine = new FlxSprite(0, HDR_H - 1).makeGraphic(SW, 1, FlxColor.fromInt(C_ACCENT));
		hdrLine.scrollFactor.set();
		hdrLine.cameras = [_camHUD];
		add(hdrLine);

		_headerTxt = new FlxText(0, 6, SW, '♪  NODE MENU EDITOR  ♪', 16);
		_headerTxt.setFormat(null, 16, FlxColor.fromInt(C_ACCENT), CENTER, OUTLINE);
		_headerTxt.borderColor = FlxColor.fromInt(0xFF003344);
		_headerTxt.borderSize = 2;
		_headerTxt.scrollFactor.set();
		_headerTxt.cameras = [_camHUD];
		add(_headerTxt);

		// Ctrl+S / ESC hint (right side)
		var hint = new FlxText(SW - PROP_W - 10, 10, PROP_W, 'Ctrl+S Save  ESC Exit', 9);
		hint.setFormat(null, 9, FlxColor.fromInt(C_DIM), RIGHT);
		hint.scrollFactor.set();
		hint.cameras = [_camHUD];
		add(hint);
	}

	function _buildStatusBar():Void {
		var sb = new FlxSprite(0, SH - STAT_H).makeGraphic(SW, STAT_H, FlxColor.fromInt(0xFF07070F));
		sb.scrollFactor.set();
		sb.cameras = [_camHUD];
		add(sb);
		var sbl = new FlxSprite(0, SH - STAT_H).makeGraphic(SW, 1, FlxColor.fromInt(C_PANEL_BORDER));
		sbl.scrollFactor.set();
		sbl.cameras = [_camHUD];
		add(sbl);

		_statusTxt = new FlxText(8, SH - STAT_H + 4, SW - 16, '', 10);
		_statusTxt.setFormat(null, 10, FlxColor.fromInt(C_STATUS_OK));
		_statusTxt.scrollFactor.set();
		_statusTxt.cameras = [_camHUD];
		add(_statusTxt);
	}

	function _buildLibraryPanel():Void {
		var title = new FlxText(6, HDR_H + 6, LIB_W - 12, 'NODE LIBRARY', 11);
		title.setFormat(null, 11, FlxColor.fromInt(C_ACCENT), LEFT, OUTLINE);
		title.borderColor = FlxColor.fromInt(0xFF001122);
		title.scrollFactor.set();
		title.cameras = [_camHUD];
		add(title);

		var sep = new FlxSprite(6, HDR_H + 22).makeGraphic(LIB_W - 12, 1, FlxColor.fromInt(C_ACCENT));
		sep.alpha = 0.3;
		sep.scrollFactor.set();
		sep.cameras = [_camHUD];
		add(sep);

		var libItems:Array<{cls:String, label:String}> = [
			{cls: 'MainMenuState', label: 'Main Menu'},
			{cls: 'FreeplayState', label: 'Freeplay'},
			{cls: 'StoryMenuState', label: 'Story Mode'},
			{cls: 'OptionsMenuState', label: 'Options'},
			{cls: 'CharacterSelectorState', label: 'Char Selector'},
			{cls: 'CreditsState', label: 'Credits'},
			{cls: 'EditorHubState', label: 'Editor Hub'},
			{cls: 'ModSelectorState', label: 'Mod Selector'},
			{cls: 'IntroState', label: 'Intro'},
			{cls: 'ScriptConsoleState', label: 'Script Console'},
			{cls: 'custom', label: '+ Custom…'},
		];

		var iy = HDR_H + 28;
		for (item in libItems) {
			var capturedCls = item.cls;
			var capturedLabel = item.label;
			var col = NODE_TYPE_COLORS.exists(capturedCls) ? NODE_TYPE_COLORS.get(capturedCls) : NODE_TYPE_COLORS.get('custom');

			// Coloured strip left
			var strip = new FlxSprite(6, iy).makeGraphic(4, 22, FlxColor.fromInt(C_ACCENT));
			var baseCol:FlxColor = col | 0xFF000000;
			strip.color = baseCol.getLightened(0.4);
			strip.scrollFactor.set();
			strip.cameras = [_camHUD];
			add(strip);

			// Label (clickable via FlxSprite hitbox — we'll detect via mouse in update)
			var lbl = new FlxText(14, iy + 3, LIB_W - 20, capturedLabel, 10);
			lbl.setFormat(null, 10, FlxColor.fromInt(C_TEXT));
			lbl.scrollFactor.set();
			lbl.cameras = [_camHUD];
			add(lbl);

			// Store for mouse detection (simple approach: store Y ranges)
			var capturedY = iy;
			// We'll handle click detection in update() via the library bounds
			_libItems.push({
				y: capturedY,
				h: 22,
				cls: capturedCls,
				label: capturedLabel
			});

			iy += 26;
		}

		// Instructions
		var ins = new FlxText(6, iy + 6, LIB_W - 12, 'Click item to\nadd to canvas', 9);
		ins.setFormat(null, 9, FlxColor.fromInt(C_DIM));
		ins.scrollFactor.set();
		ins.cameras = [_camHUD];
		add(ins);
	}

	var _libItems:Array<{
		y:Int,
		h:Int,
		cls:String,
		label:String
	}> = [];

	function _buildPropertiesPanel():Void {
		var px = SW - PROP_W + 8;

		var title = new FlxText(px, HDR_H + 6, PROP_W - 16, 'PROPERTIES', 11);
		title.setFormat(null, 11, FlxColor.fromInt(C_ACCENT), LEFT, OUTLINE);
		title.borderColor = FlxColor.fromInt(0xFF001122);
		title.scrollFactor.set();
		title.cameras = [_camHUD];
		add(title);

		var sep = new FlxSprite(px, HDR_H + 22).makeGraphic(PROP_W - 16, 1, FlxColor.fromInt(C_ACCENT));
		sep.alpha = 0.3;
		sep.scrollFactor.set();
		sep.cameras = [_camHUD];
		add(sep);

		var noSel = new FlxText(px, HDR_H + 30, PROP_W - 16, 'No node selected.\nClick a node to\nview properties.', 10);
		noSel.setFormat(null, 10, FlxColor.fromInt(C_DIM));
		noSel.scrollFactor.set();
		noSel.cameras = [_camHUD];
		add(noSel);

		_propNameTxt = new FlxText(px, HDR_H + 32, PROP_W - 16, '', 11);
		_propNameTxt.setFormat(null, 11, FlxColor.fromInt(C_TEXT), LEFT, OUTLINE);
		_propNameTxt.borderColor = FlxColor.fromInt(0xFF001122);
		_propNameTxt.scrollFactor.set();
		_propNameTxt.cameras = [_camHUD];
		add(_propNameTxt);
		_propNameTxt.visible = false;

		_propClassTxt = new FlxText(px, HDR_H + 52, PROP_W - 16, '', 9);
		_propClassTxt.setFormat(null, 9, FlxColor.fromInt(C_DIM));
		_propClassTxt.scrollFactor.set();
		_propClassTxt.cameras = [_camHUD];
		add(_propClassTxt);
		_propClassTxt.visible = false;

		// Delete node button area (drawn via FlxSprite — click detection in update)
		_propDeleteBg = new FlxSprite(px, HDR_H + 80).makeGraphic(PROP_W - 16, 22, FlxColor.fromInt(0xFF3A0A0A));
		_propDeleteBg.scrollFactor.set();
		_propDeleteBg.cameras = [_camHUD];
		add(_propDeleteBg);
		_propDeleteBg.visible = false;

		var delTxt = new FlxText(px, HDR_H + 84, PROP_W - 16, 'Delete Node', 10);
		delTxt.setFormat(null, 10, FlxColor.fromInt(0xFFFF4466), CENTER);
		delTxt.scrollFactor.set();
		delTxt.cameras = [_camHUD];
		add(delTxt);
		_propDeleteTxt = delTxt;
		_propDeleteTxt.visible = false;

		// Go to state button
		_propGoBtn = new FlxSprite(px, HDR_H + 108).makeGraphic(PROP_W - 16, 22, FlxColor.fromInt(0xFF0A2A1A));
		_propGoBtn.scrollFactor.set();
		_propGoBtn.cameras = [_camHUD];
		add(_propGoBtn);
		_propGoBtn.visible = false;

		_propGoTxt = new FlxText(px, HDR_H + 112, PROP_W - 16, 'Open State ▶', 10);
		_propGoTxt.setFormat(null, 10, FlxColor.fromInt(C_STATUS_OK), CENTER);
		_propGoTxt.scrollFactor.set();
		_propGoTxt.cameras = [_camHUD];
		add(_propGoTxt);
		_propGoTxt.visible = false;

		// Connections list (updated on select)
		_propConnTxt = new FlxText(px, HDR_H + 140, PROP_W - 16, '', 9);
		_propConnTxt.setFormat(null, 9, FlxColor.fromInt(C_DIM));
		_propConnTxt.scrollFactor.set();
		_propConnTxt.cameras = [_camHUD];
		add(_propConnTxt);
	}

	var _propDeleteBg:FlxSprite;
	var _propDeleteTxt:FlxText;
	var _propGoBtn:FlxSprite;
	var _propGoTxt:FlxText;
	var _propConnTxt:FlxText;

	// ─────────────────────────────────────────────────────────────────────────
	// UPDATE
	// ─────────────────────────────────────────────────────────────────────────
	override function update(elapsed:Float):Void {
		super.update(elapsed);

		_checkLibraryClick();
		_checkPropertiesClick();

		// Header pulse
		_headerTxt.alpha = 0.85 + Math.sin(FlxG.game.ticks / 400) * 0.15;

		// Keyboard shortcuts
		if (FlxG.keys.pressed.CONTROL) {
			if (FlxG.keys.justPressed.S)
				_save();
			if (FlxG.keys.justPressed.Z)
				_undoStep();
			if (FlxG.keys.justPressed.A) {
				_selectedNode = null;
				_redrawAll();
			}
		}

		if (FlxG.keys.justPressed.F)
			_fitView();

		if (FlxG.keys.justPressed.ESCAPE) {
			if (_connectingFrom != null) {
				_connectingFrom = null;
				_dragConnShape.graphics.clear();
				_status('Connection cancelled.', C_STATUS_WARN);
			} else {
				_cleanup();
				StateTransition.switchState(new funkin.debug.EditorHubState());
			}
		}

		if ((FlxG.keys.justPressed.DELETE || FlxG.keys.justPressed.BACKSPACE) && _selectedNode != null)
			_deleteNode(_selectedNode);

		if (FlxG.keys.justPressed.GRAVEACCENT) {
			_cleanup();
			funkin.debug.ScriptConsoleState.openFrom(() -> new NodeMenuEditor());
		}
	}

	function _checkLibraryClick():Void {
		if (!FlxG.mouse.justPressed)
			return;
		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;
		if (mx >= LIB_W)
			return; // not in library panel

		for (item in _libItems) {
			if (my >= item.y && my < item.y + item.h) {
				// Place node in center of canvas view
				var cx = (_panX == 0 ? 100 : -_panX) + CANVAS_W * 0.5 / _zoom;
				var cy = (_panY == 0 ? 100 : -_panY) + CANVAS_H * 0.5 / _zoom;
				// Jitter so overlapping nodes are visible
				cx += FlxG.random.float(-40, 40);
				cy += FlxG.random.float(-20, 20);
				var label = item.cls == 'custom' ? 'Custom' : item.label;
				_addNode(item.cls, label, cx, cy);
				_redrawAll();
				_saveUndo();
				_status('Added node: ${item.label}', C_STATUS_OK);
				break;
			}
		}
	}

	function _checkPropertiesClick():Void {
		if (!FlxG.mouse.justPressed || _selectedNode == null)
			return;
		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;

		// Delete button
		var dx = SW - PROP_W + 8;
		var dy = HDR_H + 80;
		if (mx >= dx && mx <= dx + PROP_W - 16 && my >= dy && my <= dy + 22) {
			_deleteNode(_selectedNode);
			return;
		}

		// Go button
		var gy = HDR_H + 108;
		if (mx >= dx && mx <= dx + PROP_W - 16 && my >= gy && my <= gy + 22) {
			_openSelectedState();
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	// MOUSE EVENTS (OpenFL)
	// ─────────────────────────────────────────────────────────────────────────
	function _onCanvasMouseDown(e:MouseEvent):Void {
		var cx = (e.stageX - CANVAS_X - _panX) / _zoom;
		var cy = (e.stageY - CANVAS_Y - _panY) / _zoom;

		// Check if clicking a node
		var hit = _nodeAt(cx, cy);
		if (hit != null) {
			// Check output port (right side)
			var outPX = hit.x + NODE_W + PORT_OX;
			var outPY = hit.y + NODE_H * 0.5;
			if (Math.abs(cx - outPX) < PORT_R + 4 && Math.abs(cy - outPY) < PORT_R + 4) {
				// Start connection drag
				_connectingFrom = hit;
				_connectDragX = e.stageX - CANVAS_X;
				_connectDragY = e.stageY - CANVAS_Y;
				return;
			}

			// Start dragging node
			_selectedNode = hit;
			_draggingNode = hit;
			_dragOffX = cx - hit.x;
			_dragOffY = cy - hit.y;
			_updatePropertiesPanel();
			_redrawAll();
			return;
		}

		// Check if clicking an existing connection (rough midpoint test)
		var hitConn = _connAt(cx, cy);
		if (hitConn != null) {
			_selectedConn = hitConn;
			_selectedNode = null;
			_updatePropertiesPanel();
			_redrawAll();
			return;
		}

		// Start pan
		_selectedNode = null;
		_selectedConn = null;
		_panning = true;
		_panStartX = e.stageX;
		_panStartY = e.stageY;
		_panStartPX = _panX;
		_panStartPY = _panY;
		_updatePropertiesPanel();
		_redrawAll();
	}

	function _onCanvasMouseMove(e:MouseEvent):Void {
		if (_draggingNode != null) {
			var cx = (e.stageX - CANVAS_X - _panX) / _zoom;
			var cy = (e.stageY - CANVAS_Y - _panY) / _zoom;
			_draggingNode.x = cx - _dragOffX;
			_draggingNode.y = cy - _dragOffY;
			_redrawAll();
		} else if (_panning) {
			_panX = _panStartPX + (e.stageX - _panStartX);
			_panY = _panStartPY + (e.stageY - _panStartY);
			_redrawAll();
		} else if (_connectingFrom != null) {
			_connectDragX = e.stageX - CANVAS_X;
			_connectDragY = e.stageY - CANVAS_Y;
			_redrawDragConnection();
		}
	}

	function _onMouseUp(e:MouseEvent):Void {
		if (_connectingFrom != null) {
			var cx = (e.stageX - CANVAS_X - _panX) / _zoom;
			var cy = (e.stageY - CANVAS_Y - _panY) / _zoom;
			var hit = _nodeAt(cx, cy);

			if (hit != null && hit != _connectingFrom) {
				// Check input port (left side)
				var inPX = hit.x - PORT_OX;
				var inPY = hit.y + NODE_H * 0.5;
				if (Math.abs(cx - inPX) < PORT_R + 10 && Math.abs(cy - inPY) < PORT_R + 10 || true /* be generous with drop target */) {
					_addConnection(_connectingFrom.id, hit.id, '');
					_saveUndo();
					_status('Connected: ${_connectingFrom.label} → ${hit.label}', C_STATUS_OK);
				}
			}
			_connectingFrom = null;
			_dragConnShape.graphics.clear();
			_redrawAll();
		}

		if (_draggingNode != null) {
			_saveUndo();
			_draggingNode = null;
		}

		_panning = false;
	}

	function _onMouseWheel(e:MouseEvent):Void {
		// Zoom around the mouse position
		var mxS = e.stageX - CANVAS_X;
		var myS = e.stageY - CANVAS_Y;

		if (mxS < 0 || mxS > CANVAS_W || myS < 0 || myS > CANVAS_H)
			return;

		var oldZoom = _zoom;
		_zoom = FlxMath.bound(_zoom + e.delta * 0.1, ZOOM_MIN, ZOOM_MAX);

		// Adjust pan so zoom is centred on cursor
		_panX = mxS - (_zoom / oldZoom) * (mxS - _panX);
		_panY = myS - (_zoom / oldZoom) * (myS - _panY);

		_redrawAll();
	}

	function _onKeyDown(e:KeyboardEvent):Void {
		if (e.keyCode == Keyboard.DELETE || e.keyCode == Keyboard.BACKSPACE) {
			if (_selectedConn != null) {
				_deleteConn(_selectedConn);
			}
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	// DRAW
	// ─────────────────────────────────────────────────────────────────────────
	function _redrawAll():Void {
		_drawGrid();
		_drawConnections();
		_drawNodes();
	}

	function _drawGrid():Void {
		var g = _gridShape.graphics;
		g.clear();
		g.lineStyle(1, C_GRID, 1);

		var gridSize = 32 * _zoom;
		var ox = _panX % gridSize;
		var oy = _panY % gridSize;

		var x = ox;
		while (x < CANVAS_W) {
			g.moveTo(x, 0);
			g.lineTo(x, CANVAS_H);
			x += gridSize;
		}
		var y = oy;
		while (y < CANVAS_H) {
			g.moveTo(0, y);
			g.lineTo(CANVAS_W, y);
			y += gridSize;
		}

		// Axes
		g.lineStyle(1, C_ACCENT, 0.15);
		g.moveTo(_panX, 0);
		g.lineTo(_panX, CANVAS_H);
		g.moveTo(0, _panY);
		g.lineTo(CANVAS_W, _panY);
	}

	function _drawConnections():Void {
		var g = _connShape.graphics;
		g.clear();

		for (conn in _conns) {
			var from = _nodeById(conn.fromId);
			var to = _nodeById(conn.toId);
			if (from == null || to == null)
				continue;

			var x0 = (from.x + NODE_W + PORT_OX) * _zoom + _panX;
			var y0 = (from.y + NODE_H * 0.5) * _zoom + _panY;
			var x1 = (to.x - PORT_OX) * _zoom + _panX;
			var y1 = (to.y + NODE_H * 0.5) * _zoom + _panY;

			var isSelected = (conn == _selectedConn);
			var col = isSelected ? C_SEL : C_CONN;
			var lw = isSelected ? 2.5 : 1.5;

			_drawBezier(g, x0, y0, x1, y1, col, lw);

			// Arrow head at x1,y1
			_drawArrow(g, x1, y1, x0, y0, col);

			// Connection label at midpoint
			if (conn.label != null && conn.label.trim() != '') {
				// (label drawn as OpenFL text would be ideal; skip for now — use Shape text hack)
			}
		}
	}

	function _redrawDragConnection():Void {
		var g = _dragConnShape.graphics;
		g.clear();
		if (_connectingFrom == null)
			return;

		var x0 = (_connectingFrom.x + NODE_W + PORT_OX) * _zoom + _panX;
		var y0 = (_connectingFrom.y + NODE_H * 0.5) * _zoom + _panY;
		var x1 = _connectDragX;
		var y1 = _connectDragY;

		_drawBezier(g, x0, y0, x1, y1, C_CONN_DRAG, 2.0);
		_drawArrow(g, x1, y1, x0, y0, C_CONN_DRAG);
	}

	function _drawBezier(g:Graphics, x0:Float, y0:Float, x1:Float, y1:Float, col:Int, lw:Float):Void {
		g.lineStyle(lw, col, 0.9);
		var dx = Math.abs(x1 - x0) * 0.5;
		g.moveTo(x0, y0);
		g.cubicCurveTo(x0 + dx, y0, x1 - dx, y1, x1, y1);
	}

	function _drawArrow(g:Graphics, tipX:Float, tipY:Float, fromX:Float, fromY:Float, col:Int):Void {
		var angle = Math.atan2(tipY - fromY, tipX - fromX);
		var len = 9 * _zoom;
		var spread = 0.45;
		g.lineStyle(0);
		g.beginFill(col, 0.9);
		g.moveTo(tipX, tipY);
		g.lineTo(tipX - len * Math.cos(angle - spread), tipY - len * Math.sin(angle - spread));
		g.lineTo(tipX - len * Math.cos(angle + spread), tipY - len * Math.sin(angle + spread));
		g.endFill();
	}

	function _drawNodes():Void {
		// Remove old node sprites
		for (id => spr in _nodeSprites)
			_canvasSprite.removeChild(spr);
		_nodeSprites = [];

		for (node in _nodes) {
			var spr = new Sprite();
			var nx = node.x * _zoom + _panX;
			var ny = node.y * _zoom + _panY;
			var nw = NODE_W * _zoom;
			var nh = NODE_H * _zoom;
			spr.x = nx;
			spr.y = ny;

			var isSelected = (node == _selectedNode);

			// Shadow
			var g = spr.graphics;
			if (isSelected) {
				g.lineStyle(2, C_SEL, 0.8);
				g.beginFill(C_SEL, 0.08);
				g.drawRoundRect(-3, -3, nw + 6, nh + 6, 10, 10);
				g.endFill();
			}

			// Body
			var col = NODE_TYPE_COLORS.exists(node.className) ? NODE_TYPE_COLORS.get(node.className) : NODE_TYPE_COLORS.get('custom');
			g.lineStyle(isSelected ? 2 : 1, isSelected ? C_SEL : C_ACCENT, isSelected ? 1.0 : 0.5);
			g.beginFill(col ?? 0xFF1E1E30, 1.0);
			g.drawRoundRect(0, 0, nw, nh, 8 * _zoom, 8 * _zoom);
			g.endFill();

			// Colour stripe at top
			g.lineStyle(0);
			g.beginFill(C_ACCENT, 0.2);
			g.drawRoundRect(0, 0, nw, 5 * _zoom, 4 * _zoom, 4 * _zoom);
			g.endFill();

			// Label
			var tf = new TextField();
			tf.x = 10 * _zoom;
			tf.y = 8 * _zoom;
			tf.width = (NODE_W - 20) * _zoom;
			tf.height = 18 * _zoom;
			tf.selectable = false;
			tf.mouseEnabled = false;
			tf.defaultTextFormat = new TextFormat('_typewriter', Std.int(11 * _zoom), C_TEXT, true);
			tf.text = node.label;
			spr.addChild(tf);

			// Class name (smaller)
			var tf2 = new TextField();
			tf2.x = 10 * _zoom;
			tf2.y = 28 * _zoom;
			tf2.width = (NODE_W - 20) * _zoom;
			tf2.height = 16 * _zoom;
			tf2.selectable = false;
			tf2.mouseEnabled = false;
			tf2.defaultTextFormat = new TextFormat('_typewriter', Std.int(9 * _zoom), 0xFF6688AA);
			tf2.text = node.className;
			spr.addChild(tf2);

			// Output port (right ▶)
			var gp = spr.graphics;
			gp.lineStyle(1, C_PORT_OUT, 1);
			gp.beginFill(C_PORT_OUT, 0.8);
			gp.drawCircle((NODE_W + PORT_OX) * _zoom, (NODE_H * 0.5) * _zoom, PORT_R * _zoom);
			gp.endFill();

			// Input port (left ◀)
			gp.lineStyle(1, C_PORT_IN, 1);
			gp.beginFill(C_PORT_IN, 0.8);
			gp.drawCircle(-PORT_OX * _zoom, (NODE_H * 0.5) * _zoom, PORT_R * _zoom);
			gp.endFill();

			_canvasSprite.addChild(spr);
			_nodeSprites.set(node.id, spr);
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	// DATA HELPERS
	// ─────────────────────────────────────────────────────────────────────────
	function _addNode(cls:String, label:String, x:Float, y:Float):NodeData {
		var n:NodeData = {
			id: 'node_' + (_nextId++),
			label: label,
			className: cls,
			x: x,
			y: y,
		};
		_nodes.push(n);
		_unsaved = true;
		return n;
	}

	function _addConnection(fromId:String, toId:String, label:String):Void {
		// Avoid duplicates
		for (c in _conns)
			if (c.fromId == fromId && c.toId == toId)
				return;

		_conns.push({
			id: 'conn_' + (_nextId++),
			fromId: fromId,
			toId: toId,
			label: label,
		});
		_unsaved = true;
		_redrawAll();
	}

	function _deleteNode(node:NodeData):Void {
		_nodes.remove(node);
		// Remove connections involving this node
		_conns = _conns.filter(c -> c.fromId != node.id && c.toId != node.id);
		if (_selectedNode == node)
			_selectedNode = null;
		_updatePropertiesPanel();
		_redrawAll();
		_saveUndo();
		_unsaved = true;
		_status('Deleted: ${node.label}', C_STATUS_WARN);
	}

	function _deleteConn(conn:ConnData):Void {
		_conns.remove(conn);
		if (_selectedConn == conn)
			_selectedConn = null;
		_redrawAll();
		_saveUndo();
		_unsaved = true;
		_status('Connection removed.', C_STATUS_WARN);
	}

	function _nodeAt(cx:Float, cy:Float):Null<NodeData> {
		// Iterate in reverse so topmost node (last drawn) wins
		var i = _nodes.length - 1;
		while (i >= 0) {
			var n = _nodes[i];
			if (cx >= n.x - PORT_OX - 4 && cx <= n.x + NODE_W + PORT_OX + 4 && cy >= n.y && cy <= n.y + NODE_H)
				return n;
			i--;
		}
		return null;
	}

	function _connAt(cx:Float, cy:Float):Null<ConnData> {
		for (conn in _conns) {
			var from = _nodeById(conn.fromId);
			var to = _nodeById(conn.toId);
			if (from == null || to == null)
				continue;
			// Check midpoint proximity
			var mx = (from.x + NODE_W + to.x) * 0.5;
			var my = (from.y + to.y + NODE_H) * 0.5;
			if (Math.abs(cx - mx) < 24 && Math.abs(cy - my) < 20)
				return conn;
		}
		return null;
	}

	function _nodeById(id:String):Null<NodeData> {
		for (n in _nodes)
			if (n.id == id)
				return n;
		return null;
	}

	// ─────────────────────────────────────────────────────────────────────────
	// PROPERTIES PANEL UPDATE
	// ─────────────────────────────────────────────────────────────────────────
	function _updatePropertiesPanel():Void {
		var has = (_selectedNode != null);
		_propNameTxt.visible = has;
		_propClassTxt.visible = has;
		_propDeleteBg.visible = has;
		_propDeleteTxt.visible = has;
		_propGoBtn.visible = has;
		_propGoTxt.visible = has;

		if (!has) {
			_propConnTxt.text = '';
			return;
		}

		var n = _selectedNode;
		_propNameTxt.text = n.label;
		_propClassTxt.text = n.className;

		var outs = _conns.filter(c -> c.fromId == n.id);
		var ins = _conns.filter(c -> c.toId == n.id);
		var sb = new StringBuf();
		sb.add('Connections:\n');
		for (c in outs) {
			var to = _nodeById(c.toId);
			sb.add('  ▶ ${to?.label ?? c.toId}\n');
		}
		for (c in ins) {
			var fr = _nodeById(c.fromId);
			sb.add('  ◀ ${fr?.label ?? c.fromId}\n');
		}
		if (outs.length == 0 && ins.length == 0)
			sb.add('  (none)');
		_propConnTxt.text = sb.toString();
	}

	function _openSelectedState():Void {
		if (_selectedNode == null)
			return;
		_cleanup();
		var cls = _selectedNode.className;
		var state = funkin.debug.ScriptConsoleState.openFrom.bind(() -> new NodeMenuEditor());
		// Try to open the actual state via the same resolver
		var console = new funkin.debug.ScriptConsoleState();
		_cleanupAndGo(console);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// FIT VIEW
	// ─────────────────────────────────────────────────────────────────────────
	function _fitView():Void {
		if (_nodes.length == 0)
			return;
		var minX = 1e9;
		var minY = 1e9;
		var maxX = -1e9;
		var maxY = -1e9;
		for (n in _nodes) {
			if (n.x < minX)
				minX = n.x;
			if (n.y < minY)
				minY = n.y;
			if (n.x + NODE_W > maxX)
				maxX = n.x + NODE_W;
			if (n.y + NODE_H > maxY)
				maxY = n.y + NODE_H;
		}
		var pw = maxX - minX + 60;
		var ph = maxY - minY + 60;
		_zoom = FlxMath.bound(Math.min(CANVAS_W / pw, CANVAS_H / ph), ZOOM_MIN, ZOOM_MAX);
		_panX = (CANVAS_W - pw * _zoom) * 0.5 - (minX - 30) * _zoom;
		_panY = (CANVAS_H - ph * _zoom) * 0.5 - (minY - 30) * _zoom;
		_redrawAll();
		_status('Fit to view.', C_STATUS_OK);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// SAVE / LOAD
	// ─────────────────────────────────────────────────────────────────────────
	function _save():Void {
		#if sys
		var path = 'assets/data/nodeMenuGraph.json';
		var data = {nodes: _nodes, connections: _conns};
		File.saveContent(path, Json.stringify(data, null, '  '));
		_unsaved = false;
		_status('Saved → $path', C_STATUS_OK);
		#else
		_status('Save not supported on this platform.', C_STATUS_WARN);
		#end
	}

	// ─────────────────────────────────────────────────────────────────────────
	// UNDO
	// ─────────────────────────────────────────────────────────────────────────
	function _saveUndo():Void {
		var snap = Json.stringify({nodes: _nodes, connections: _conns});
		_undo.push(snap);
		if (_undo.length > 40)
			_undo.shift();
	}

	function _undoStep():Void {
		if (_undo.length < 2) {
			_status('Nothing to undo.', C_STATUS_WARN);
			return;
		}
		_undo.pop();
		var snap = Json.parse(_undo[_undo.length - 1]);
		_nodes = snap.nodes;
		_conns = snap.connections;
		_selectedNode = null;
		_selectedConn = null;
		_updatePropertiesPanel();
		_redrawAll();
		_status('Undo ←', C_STATUS_WARN);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// BEAT HIT
	// ─────────────────────────────────────────────────────────────────────────
	override function beatHit():Void {
		super.beatHit();
		FlxTween.tween(_headerTxt, {alpha: 0.5}, 0.1, {
			ease: FlxEase.quadOut,
			onComplete: _ -> FlxTween.tween(_headerTxt, {alpha: 1.0}, 0.3, {ease: FlxEase.quadIn})
		});
	}

	// ─────────────────────────────────────────────────────────────────────────
	// STATUS BAR
	// ─────────────────────────────────────────────────────────────────────────
	function _status(msg:String, col:Int = C_STATUS_OK):Void {
		_statusTxt.text = msg;
		_statusTxt.color = FlxColor.fromInt(col);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// CLEANUP
	// ─────────────────────────────────────────────────────────────────────────
	function _cleanup():Void {
		FlxG.stage.removeEventListener(MouseEvent.MOUSE_UP, _onMouseUp);
		FlxG.stage.removeEventListener(MouseEvent.MOUSE_WHEEL, _onMouseWheel);
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, _onKeyDown);
		if (_canvasSprite != null && FlxG.stage.contains(_canvasSprite))
			FlxG.stage.removeChild(_canvasSprite);
		if (_camHUD != null)
			FlxG.cameras.remove(_camHUD, true);
	}

	function _cleanupAndGo(target:MusicBeatState):Void {
		_cleanup();
		StateTransition.switchState(target);
	}

	override function destroy():Void {
		_cleanup();
		super.destroy();
	}
}
