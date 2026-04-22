package funkin.debug.editors;
import funkin.debug.EditorDialogs.UnsavedChangesDialog;
import coolui.CoolInputText;
import coolui.CoolDropDown;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.util.FlxTimer;
import funkin.data.Conductor;
import funkin.debug.MediaTransportBar;
import funkin.gameplay.PlayState;
import funkin.gameplay.PlayStateSubState;
import funkin.transitions.StateTransition;
import haxe.Json;
import openfl.events.Event;
import openfl.net.FileReference;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

// ═══════════════════════════════════════════════════════════════════════════════
//  CutsceneEditorState  v3.0
//
//  Editor visual de cutscenes (intro + outro) con:
//   • PlayState cinematicMode de fondo  (stage + chars, sin HUD, sin notas)
//   • MediaTransportBar controlando el TIEMPO DE LA CUTSCENE (no el audio)
//   • Toggle INTRO / OUTRO  (TAB para cambiar)
//   • Seek visual: resalta en qué step estarías en el tiempo T
//   • Preview: avanza el tiempo de cutscene en tiempo real
//
//  Controles:
//   SPACE / K   → Play / Pause preview
//   R           → Reiniciar a t=0
//   TAB         → Cambiar Intro ↔ Outro
//   F5/Ctrl+S   → Guardar
//   ESC         → Volver al EditorHubState
// ═══════════════════════════════════════════════════════════════════════════════
class CutsceneEditorState extends funkin.states.MusicBeatState
{
	// ── Layout ────────────────────────────────────────────────────────────────
	static inline final SW:Int = 1280;
	static inline final SH:Int = 720;
	static inline final TOP_H:Int = 36;
	static inline final PANEL_H:Int = 210;
	static inline final STATUS_H:Int = 20;
	static inline final BAR_H:Int = MediaTransportBar.BAR_H;
	static inline final LEFT_W:Int = 260;
	static inline final INSP_W:Int = 280;
	static inline final ROW_H:Int = 22;
	static inline final MAX_ROWS:Int = 8;

	inline function panelY():Int
		return SH - BAR_H - STATUS_H - PANEL_H;

	inline function statusY():Int
		return SH - BAR_H - STATUS_H;

	inline function stepX():Int
		return LEFT_W + 2;

	inline function stepW():Int
		return SW - LEFT_W - 2 - INSP_W - 2;

	inline function inspX():Int
		return SW - INSP_W;

	// ── Paleta ────────────────────────────────────────────────────────────────
	static inline final C_BG:Int = 0xFF0D0D1A;
	static inline final C_TOP:Int = 0xFF0A0A16;
	static inline final C_PANEL:Int = 0xFF141428;
	static inline final C_PANEL2:Int = 0xFF111124;
	static inline final C_BORDER:Int = 0xFF252540;
	static inline final C_ACCENT:Int = 0xFF00D9FF;
	static inline final C_ACCENT2:Int = 0xFFFF4081;
	static inline final C_TEXT:Int = 0xFFDDDDFF;
	static inline final C_DIM:Int = 0xFF6666AA;
	static inline final C_SEL:Int = 0xFF1A3A5A;
	static inline final C_UNSAVED:Int = 0xFFFFAA00;
	static inline final C_SAVED:Int = 0xFF00FF88;
	static inline final C_INTRO:Int = 0xFF003344;
	static inline final C_OUTRO:Int = 0xFF330044;
	static inline final C_PLAY:Int = 0xFF003A00;

	// step row colors por categoría
	static inline final CR_WAIT:Int = 0xFF1A2A1A;
	static inline final CR_CAM:Int = 0xFF1A2A44;
	static inline final CR_ANIM:Int = 0xFF2A1A44;
	static inline final CR_SND:Int = 0xFF2A2A1A;
	static inline final CR_ADD:Int = 0xFF1A3A2A;
	static inline final CR_END:Int = 0xFF3A1A1A;
	static inline final CR_DEF:Int = 0xFF1A1A2A;

	// ── Cameras ───────────────────────────────────────────────────────────────
	var camHUD:FlxCamera;

	// ── Modo (intro / outro) ──────────────────────────────────────────────────
	var isIntro:Bool = true;

	// Docs separados por tipo
	var docIntro:CutsceneDoc = {sprites: {}, steps: []};
	var docOutro:CutsceneDoc = {sprites: {}, steps: []};
	var doc(get, never):CutsceneDoc;

	inline function get_doc()
		return isIntro ? docIntro : docOutro;

	var hasUnsaved:Bool = false;
	var _unsavedDlg:UnsavedChangesDialog = null;
	var _windowCloseFn:Void->Void = null;
	var pathIntro:String = '';
	var pathOutro:String = '';

	// ── Selección ─────────────────────────────────────────────────────────────
	var selSpr:String = null;
	var selStep:Int = -1;

	// ── Tiempo de cutscene ────────────────────────────────────────────────────

	/** Posición actual en segundos dentro de la cutscene */
	var cutTime:Float = 0.0;

	/** Duración total calculada sumando steps bloqueantes */
	var cutDuration:Float = 1.0;

	var playing:Bool = false;

	// ── Transport ─────────────────────────────────────────────────────────────
	var _bar:MediaTransportBar;

	// ── UI ────────────────────────────────────────────────────────────────────
	var _statusTxt:FlxText;
	var _infotxt:FlxText;
	var _unsavedDot:FlxSprite;

	var _btnBack:_Btn;
	var _btnNew:_Btn;
	var _btnLoad:_Btn;
	var _btnSave:_Btn;
	var _btnPlay:_Btn;
	var _btnStop:_Btn;
	var _btnIntro:_Btn;
	var _btnOutro:_Btn;

	// Listas
	var _sprRows:FlxTypedGroup<FlxSprite>;
	var _sprLabels:FlxTypedGroup<FlxText>;
	var _sprHits:Array<{y:Float, key:String}> = [];
	var _sprScroll:Int = 0;

	var _stpRows:FlxTypedGroup<FlxSprite>;
	var _stpLabels:FlxTypedGroup<FlxText>;
	var _stpHits:Array<{y:Float, idx:Int}> = [];
	var _stpScroll:Int = 0;

	// Playhead row (resalta step activo durante preview)
	var _playhead:FlxSprite;

	// Inspector
	var _actionDD:CoolDropDown;
	var _spriteDD:CoolDropDown;
	var _pInputs:Array<CoolInputText> = [];
	var _pLabels:Array<FlxText> = [];

	var _fileRef:FileReference;

	// ── Acciones ──────────────────────────────────────────────────────────────
	static final ACTIONS:Array<String> = [
		"add",
		"remove",
		"setAlpha",
		"setColor",
		"setVisible",
		"setPosition",
		"screenCenter",
		"wait",
		"fadeTimer",
		"tween",
		"playAnim",
		"playSound",
		"waitSound",
		"cameraFade",
		"cameraFlash",
		"cameraShake",
		"cameraZoom",
		"cameraMove",
		"cameraPan",
		"cameraTarget",
		"cameraReset",
		"setCamVisible",
		"waitBeat",
		"waitStep",
		"call",
		"callAsync",
		"script",
		"end"
	];

	static final PARAMS:Map<String, Array<{l:String, k:String}>> = [
		"add" => [{l: "alpha", k: "alpha"}],
		"remove" => [],
		"setAlpha" => [{l: "alpha", k: "alpha"}],
		"setColor" => [{l: "color", k: "color"}],
		"setVisible" => [{l: "visible", k: "visible"}],
		"setPosition" => [{l: "x", k: "x"}, {l: "y", k: "y"}],
		"screenCenter" => [{l: "axis", k: "axis"}],
		"wait" => [{l: "time (s)", k: "time"}],
		"fadeTimer" => [
			{l: "target α", k: "target"},
			{l: "step", k: "step"},
			{l: "interval", k: "interval"}
		],
		"tween" => [
			{l: "props (JSON)", k: "props"},
			{l: "dur", k: "duration"},
			{l: "ease", k: "ease"},
			{l: "async", k: "async"}
		],
		"playAnim" => [{l: "anim", k: "anim"}, {l: "force", k: "force"}],
		"playSound" => [{l: "key", k: "key"}, {l: "id", k: "id"}],
		"waitSound" => [{l: "id", k: "id"}],
		"cameraFade" => [{l: "color", k: "color"}, {l: "dur", k: "duration"}, {l: "fadeIn", k: "fadeIn"}],
		"cameraFlash" => [
			{l: "color", k: "color"},
			{l: "dur", k: "duration"},
			{l: "persist", k: "persist"}
		],
		"cameraShake" => [{l: "intensity", k: "intensity"}, {l: "dur", k: "duration"}],
		"cameraZoom" => [
			{l: "zoom", k: "zoom"},
			{l: "dur", k: "duration"},
			{l: "ease", k: "ease"},
			{l: "async", k: "async"}
		],
		"cameraMove" => [{l: "camX", k: "camX"}, {l: "camY", k: "camY"}],
		"cameraPan" => [
			{l: "camX", k: "camX"},
			{l: "camY", k: "camY"},
			{l: "dur", k: "duration"},
			{l: "ease", k: "ease"},
			{l: "async", k: "async"}
		],
		"cameraTarget" => [{l: "target", k: "camTarget"}],
		"cameraReset" => [{l: "dur", k: "duration"}, {l: "ease", k: "ease"}, {l: "async", k: "async"}],
		"setCamVisible" => [{l: "cam", k: "cam"}, {l: "visible", k: "visible"}],
		"waitBeat" => [{l: "beat", k: "beat"}],
		"waitStep" => [{l: "step", k: "step"}],
		"call" => [{l: "id", k: "id"}],
		"callAsync" => [{l: "id", k: "id"}],
		"script" => [{l: "fn", k: "fn"}, {l: "args", k: "args"}],
		"end" => []
	];

	// ═════════════════════════════════════════════════════════════════════════
	//  create
	// ═════════════════════════════════════════════════════════════════════════
	override public function create():Void
	{
		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		FlxG.cameras.add(camHUD, false);

		_launchPlayState();

		_buildOverlay();
		_buildTopBar();
		_buildSpritePanel();
		_buildStepPanel();
		_buildInspector();
		_buildStatusBar();

		// Transport bar
		_bar = new MediaTransportBar(0, SH - BAR_H, SW, camHUD);
		_bar.songLength = cutDuration;
		_bar.isPlaying = false;
		_bar.onSeek = _onSeek;
		_bar.onPlayToggle = _onPlayToggle;
		_bar.onStop = _onStopBar;
		_bar.onSpeedChange = r -> {}; // solo afecta velocidad interna del preview
		add(_bar);

		// Playhead row
		_playhead = new FlxSprite(stepX(), 0).makeGraphic(stepW() - 2, ROW_H - 1, 0x44FFFFFF);
		_reg(_playhead);
		_playhead.visible = false;
		add(_playhead);

		_autoLoad();
		_recalcDuration();

		// Window-close guard
		#if sys
		_windowCloseFn = function()
		{
			if (hasUnsaved)
				try { _onSave(); } catch (_) {}
		};
		lime.app.Application.current.window.onClose.add(_windowCloseFn);
		#end

		super.create();
	}

	function _launchPlayState():Void
	{
		if (PlayState.SONG == null)
			return;
		PlayState.isBotPlay     = true;
		PlayState.cinematicMode = true;
		PlayState.isStoryMode   = false;
		PlayState.startFromTime = null;
		persistentUpdate = true;
		persistentDraw   = true;
		openSubState(new PlayStateSubState());
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  Build
	// ═════════════════════════════════════════════════════════════════════════
	function _buildOverlay():Void
	{
		var ov = new FlxSprite(0, panelY()).makeGraphic(SW, PANEL_H + STATUS_H, 0xE00A0A18);
		_reg(ov);
		add(ov);
		var ln = new FlxSprite(0, panelY()).makeGraphic(SW, 1, C_ACCENT);
		_reg(ln);
		ln.alpha = 0.3;
		add(ln);
	}

	function _buildTopBar():Void
	{
		var tb = new FlxSprite(0, 0).makeGraphic(SW, TOP_H, C_TOP);
		_reg(tb);
		add(tb);
		var sep = new FlxSprite(0, TOP_H - 1).makeGraphic(SW, 1, C_BORDER);
		_reg(sep);
		add(sep);

		_mkTxt(10, 11, 180, 'CUTSCENE EDITOR', 11, C_ACCENT);

		_unsavedDot = new FlxSprite(192, 14).makeGraphic(8, 8, C_UNSAVED);
		_reg(_unsavedDot);
		_unsavedDot.visible = false;
		add(_unsavedDot);

		var bx:Float = 212;
		_btnBack = _btn(bx, 4, 52, 28, '← BACK', C_PANEL, _onBack);
		bx += 56;
		_btnNew = _btn(bx, 4, 40, 28, 'NEW', C_PANEL, _onNew);
		bx += 44;
		_btnLoad = _btn(bx, 4, 50, 28, 'LOAD', C_PANEL, _onLoad);
		bx += 54;
		_btnSave = _btn(bx, 4, 50, 28, 'SAVE', 0xFF1A3A2A, _onSave);

		// Botones Intro / Outro — centrados
		_btnIntro = _btn(SW / 2 - 64, 4, 60, 28, 'INTRO', C_INTRO, _onSelectIntro);
		_btnOutro = _btn(SW / 2 + 4, 4, 60, 28, 'OUTRO', C_OUTRO, _onSelectOutro);
		_refreshModeBtns();

		// Derecha
		var rx:Float = SW - 10;
		_btnStop = _btnR(rx, 4, 50, 28, '⏹ STOP', C_PANEL, _onStopBar);
		rx -= 54;
		_btnPlay = _btnR(rx, 4, 56, 28, '▶ PLAY', C_PLAY, _onQuickPlay);
	}

	function _buildSpritePanel():Void
	{
		final py = panelY();
		var bg = new FlxSprite(0, py).makeGraphic(LEFT_W, PANEL_H, C_PANEL);
		_reg(bg);
		add(bg);
		_mkTxt(8, py + 5, LEFT_W - 16, 'SPRITES', 9, C_DIM);
		_btn(LEFT_W - 50, py + 2, 22, 18, '+', 0xFF1A3A1A, _onAddSprite);
		_btn(LEFT_W - 26, py + 2, 22, 18, '−', 0xFF3A1A1A, _onDelSprite);
		var brd = new FlxSprite(LEFT_W - 1, py).makeGraphic(1, PANEL_H, C_BORDER);
		_reg(brd);
		add(brd);
		_sprRows = new FlxTypedGroup();
		_sprRows.cameras = [camHUD];
		_sprLabels = new FlxTypedGroup();
		_sprLabels.cameras = [camHUD];
		add(_sprRows);
		add(_sprLabels);
		_refreshSprList();
	}

	function _buildStepPanel():Void
	{
		final py = panelY();
		final px = stepX();
		final pw = stepW();
		var bg = new FlxSprite(px, py).makeGraphic(pw, PANEL_H, C_PANEL);
		_reg(bg);
		add(bg);
		_mkTxt(px + 8, py + 5, pw - 16, 'STEPS', 9, C_DIM);
		var brd = new FlxSprite(px + pw - 1, py).makeGraphic(1, PANEL_H, C_BORDER);
		_reg(brd);
		add(brd);
		_stpRows = new FlxTypedGroup();
		_stpRows.cameras = [camHUD];
		_stpLabels = new FlxTypedGroup();
		_stpLabels.cameras = [camHUD];
		add(_stpRows);
		add(_stpLabels);
		_refreshStpList();
	}

	function _buildInspector():Void
	{
		final py = panelY();
		final px = inspX();
		var bg = new FlxSprite(px, py).makeGraphic(INSP_W, PANEL_H, C_PANEL2);
		_reg(bg);
		add(bg);
		_mkTxt(px + 8, py + 5, INSP_W - 16, 'INSPECTOR', 9, C_DIM);

		_actionDD = new CoolDropDown(px + 6, py + 18, CoolDropDown.makeStrIdLabelArray(ACTIONS));
		_actionDD.cameras = [camHUD];
		_actionDD.scrollFactor.set();
		_actionDD.selectedLabel = ACTIONS[0];
		_actionDD.callback = _onActionChanged;
		add(_actionDD);

		_spriteDD = new CoolDropDown(px + 6, py + 44, CoolDropDown.makeStrIdLabelArray(['(ninguno)']));
		_spriteDD.cameras = [camHUD];
		_spriteDD.scrollFactor.set();
		add(_spriteDD);

		_refreshSprDD();
		_rebuildParams();

		final by = py + PANEL_H - 28;
		_btn(px + 6, by, 50, 22, '+ ADD', 0xFF1A3A1A, _onAddStep);
		_btn(px + 60, by, 50, 22, '− DEL', 0xFF3A1A1A, _onDelStep);
		_btn(px + 114, by, 30, 22, '↑', C_PANEL, _onStepUp);
		_btn(px + 148, by, 30, 22, '↓', C_PANEL, _onStepDown);
	}

	function _buildStatusBar():Void
	{
		final sy = statusY();
		var sb = new FlxSprite(0, sy).makeGraphic(SW, STATUS_H, C_TOP);
		_reg(sb);
		add(sb);
		var sep = new FlxSprite(0, sy).makeGraphic(SW, 1, C_BORDER);
		_reg(sep);
		add(sep);
		_statusTxt = _mkTxt(10, sy + 4, SW - 200, '', 9, C_DIM);
		_infotxt = _mkTxt(SW - 195, sy + 4, 185, '', 9, C_DIM);
		_infotxt.alignment = RIGHT;
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  Update
	// ═════════════════════════════════════════════════════════════════════════
	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// Avanzar tiempo de cutscene
		if (playing)
		{
			cutTime += elapsed * _bar.playbackRate;
			if (cutTime >= cutDuration)
			{
				cutTime = cutDuration;
				playing = false;
				_bar.isPlaying = false;
				_btnPlay.setLabel('▶ PLAY');
				_showStatus('Preview terminado.');
			}
		}

		_bar.songPosition = cutTime;
		_updatePlayhead();
		_updateInfoTxt();

		// Teclado
		if (FlxG.keys.anyJustPressed([SPACE, K]))
			_onQuickPlay();
		if (FlxG.keys.justPressed.R)
			_onStopBar();
		if (FlxG.keys.justPressed.TAB)
			isIntro ? _onSelectOutro() : _onSelectIntro();
		if (FlxG.keys.justPressed.ESCAPE)
			_onBack();
		if (FlxG.keys.justPressed.F5 || (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.S))
			_onSave();

		// Scroll
		final mx = FlxG.mouse.x;
		final my = FlxG.mouse.y;
		final py = panelY();
		if (my >= py && my <= py + PANEL_H && FlxG.mouse.wheel != 0)
		{
			if (mx < LEFT_W)
			{
				_sprScroll = Std.int(FlxMath.bound(_sprScroll - FlxG.mouse.wheel, 0, Math.max(0, _sprKeys().length - MAX_ROWS)));
				_refreshSprList();
			}
			else if (mx < inspX())
			{
				_stpScroll = Std.int(FlxMath.bound(_stpScroll - FlxG.mouse.wheel, 0, Math.max(0, doc.steps.length - MAX_ROWS)));
				_refreshStpList();
			}
		}

		// Clicks
		if (FlxG.mouse.justPressed)
		{
			for (h in _sprHits)
				if (my >= h.y && my < h.y + ROW_H && mx < LEFT_W)
				{
					selSpr = h.key;
					_refreshSprList();
					_refreshSprDD();
					break;
				}

			for (h in _stpHits)
				if (my >= h.y && my < h.y + ROW_H && mx >= stepX() && mx < inspX())
				{
					selStep = h.idx;
					_refreshStpList();
					_loadStepToInspector(h.idx);
					break;
				}
		}
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  Transport callbacks
	// ═════════════════════════════════════════════════════════════════════════

	/** Seek: usuario arrastró la barra → saltar al tiempo T de la cutscene */
	function _onSeek(t:Float):Void
	{
		cutTime = FlxMath.bound(t, 0, cutDuration);
		_updatePlayhead();
	}

	function _onPlayToggle(p:Bool):Void
	{
		playing = p;
		_btnPlay.setLabel(p ? '⏸ PAUSE' : '▶ PLAY');
		if (p && cutTime >= cutDuration)
			cutTime = 0;
	}

	function _onStopBar():Void
	{
		playing = false;
		cutTime = 0;
		_bar.isPlaying = false;
		_btnPlay.setLabel('▶ PLAY');
		_updatePlayhead();
		_showStatus('Reiniciado.');
	}

	function _onQuickPlay():Void
	{
		playing = !playing;
		_bar.isPlaying = playing;
		_btnPlay.setLabel(playing ? '⏸ PAUSE' : '▶ PLAY');
		if (playing && cutTime >= cutDuration)
			cutTime = 0;
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  Playhead visual
	// ═════════════════════════════════════════════════════════════════════════
	function _updatePlayhead():Void
	{
		final si = _stepAtTime(cutTime);
		_playhead.visible = false;
		for (h in _stpHits)
			if (h.idx == si)
			{
				_playhead.y = h.y;
				_playhead.visible = true;
				break;
			}
	}

	function _updateInfoTxt():Void
	{
		if (_infotxt != null)
			_infotxt.text = '${isIntro ? "INTRO" : "OUTRO"}  ${_fmt(cutTime)} / ${_fmt(cutDuration)}';
	}

	/** Índice del step activo en el tiempo t */
	function _stepAtTime(t:Float):Int
	{
		var acc:Float = 0;
		for (i in 0...doc.steps.length)
		{
			final d = _stepDur(doc.steps[i]);
			if (acc + d > t)
				return i;
			acc += d;
		}
		return Std.int(Math.max(0, doc.steps.length - 1));
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  Botones top
	// ═════════════════════════════════════════════════════════════════════════
	function _onBack():Void
	{
		if (_unsavedDlg != null) return;
		if (hasUnsaved)
		{
			_unsavedDlg = new UnsavedChangesDialog([camHUD]);
			_unsavedDlg.onSaveAndExit = () -> { _onSave(); _cutsceneEditorExit(); };
			_unsavedDlg.onSave        = () -> { _onSave(); remove(_unsavedDlg); _unsavedDlg = null; };
			_unsavedDlg.onExit        = () -> { _cutsceneEditorExit(); };
			add(_unsavedDlg);
		}
		else
		{
			_cutsceneEditorExit();
		}
	}

	function _cutsceneEditorExit():Void
	{
		PlayState.cinematicMode = false;
		PlayState.isBotPlay = false;
		StateTransition.switchState(new funkin.debug.EditorHubState());
	}

	function _onNew():Void
	{
		if (isIntro)
			docIntro = empty()
		else
			docOutro = empty();
		selStep = -1;
		selSpr = null;
		_markUnsaved();
		_recalcDuration();
		_refreshAll();
		_showStatus('Nuevo doc ${isIntro ? "intro" : "outro"}.');
	}

	function _onLoad():Void
	{
		#if sys
		final p = _path();
		if (p != '' && FileSystem.exists(p))
		{
			try
			{
				_applyDoc(File.getContent(p));
				if (isIntro)
					pathIntro = p
				else
					pathOutro = p;
				_markSaved();
				_recalcDuration();
				_refreshAll();
				_showStatus('Cargado: $p');
				return;
			}
			catch (e:Dynamic)
			{
			}
		}
		#end
		_fileRef = new FileReference();
		_fileRef.addEventListener(Event.SELECT, function(_)
		{
			_fileRef.addEventListener(Event.COMPLETE, function(_:Event)
			{
				try
				{
					_applyDoc(_fileRef.data.toString());
					_markSaved();
					_recalcDuration();
					_refreshAll();
					_showStatus('Cargado.');
				}
				catch (e:Dynamic)
					_showStatus('Error JSON: $e');
			});
			_fileRef.load();
		});
		_fileRef.browse();
	}

	function _onSave():Void
	{
		final json = Json.stringify(doc, null, '\t');
		#if sys
		final p = _path();
		if (p != '')
		{
			try
			{
				final dir = p.substr(0, p.lastIndexOf('/'));
				if (!FileSystem.exists(dir))
					FileSystem.createDirectory(dir);
				File.saveContent(p, json);
				if (isIntro)
					pathIntro = p
				else
					pathOutro = p;
				_markSaved();
				_showStatus('Guardado: $p');
				return;
			}
			catch (e:Dynamic)
			{
			}
		}
		#end
		_fileRef = new FileReference();
		_fileRef.save(json, '${_songName()}-cutscene-${isIntro ? "intro" : "outro"}.json');
		_markSaved();
		_showStatus('Exportado.');
	}

	function _onSelectIntro():Void
	{
		if (isIntro)
			return;
		isIntro = true;
		selStep = -1;
		selSpr = null;
		_refreshModeBtns();
		_refreshAll();
		_recalcDuration();
		cutTime = 0;
		_showStatus('Editando INTRO.');
	}

	function _onSelectOutro():Void
	{
		if (!isIntro)
			return;
		isIntro = false;
		selStep = -1;
		selSpr = null;
		_refreshModeBtns();
		_refreshAll();
		_recalcDuration();
		cutTime = 0;
		_showStatus('Editando OUTRO.');
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  Sprites
	// ═════════════════════════════════════════════════════════════════════════
	function _onAddSprite():Void
	{
		final k = 'sprite${_sprKeys().length + 1}';
		Reflect.setField(doc.sprites, k, {
			type: 'atlas',
			image: '',
			x: 0,
			y: 0
		});
		selSpr = k;
		_markUnsaved();
		_refreshSprList();
		_refreshSprDD();
		_showStatus('Sprite: $k');
	}

	function _onDelSprite():Void
	{
		if (selSpr == null)
			return;
		Reflect.deleteField(doc.sprites, selSpr);
		selSpr = null;
		_markUnsaved();
		_refreshSprList();
		_refreshSprDD();
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  Steps
	// ═════════════════════════════════════════════════════════════════════════
	function _onAddStep():Void
	{
		final action = _actionDD.selectedLabel;
		var st:Dynamic = {action: action};
		if (_spriteDD.selectedLabel != '(ninguno)')
			st.sprite = _spriteDD.selectedLabel;
		final params = PARAMS.get(action) ?? [];
		for (i in 0...Std.int(Math.min(params.length, _pInputs.length)))
		{
			final v = _pInputs[i].text.trim();
			if (v != '')
				Reflect.setField(st, params[i].k, v);
		}
		final at = (selStep >= 0) ? selStep + 1 : doc.steps.length;
		doc.steps.insert(at, st);
		selStep = at;
		_markUnsaved();
		_recalcDuration();
		_refreshStpList();
		_showStatus('Step $at: $action');
	}

	function _onDelStep():Void
	{
		if (selStep < 0 || selStep >= doc.steps.length)
			return;
		doc.steps.splice(selStep, 1);
		selStep = Std.int(FlxMath.bound(selStep, 0, doc.steps.length - 1));
		if (doc.steps.length == 0)
			selStep = -1;
		_markUnsaved();
		_recalcDuration();
		_refreshStpList();
	}

	function _onStepUp():Void
	{
		if (selStep <= 0)
			return;
		final t = doc.steps[selStep - 1];
		doc.steps[selStep - 1] = doc.steps[selStep];
		doc.steps[selStep] = t;
		selStep--;
		_markUnsaved();
		_refreshStpList();
	}

	function _onStepDown():Void
	{
		if (selStep < 0 || selStep >= doc.steps.length - 1)
			return;
		final t = doc.steps[selStep + 1];
		doc.steps[selStep + 1] = doc.steps[selStep];
		doc.steps[selStep] = t;
		selStep++;
		_markUnsaved();
		_refreshStpList();
	}

	function _onActionChanged(a:String):Void
	{
		_rebuildParams();
		if (selStep >= 0 && selStep < doc.steps.length)
		{
			doc.steps[selStep].action = a;
			_markUnsaved();
			_recalcDuration();
			_refreshStpList();
		}
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  Refresh
	// ═════════════════════════════════════════════════════════════════════════
	function _refreshAll():Void
	{
		_refreshSprList();
		_refreshStpList();
		_refreshSprDD();
	}

	function _refreshModeBtns():Void
	{
		if (_btnIntro == null)
			return;
		_btnIntro.makeGraphic(60, 28, isIntro ? C_ACCENT : C_INTRO);
		_btnOutro.makeGraphic(60, 28, !isIntro ? C_ACCENT2 : C_OUTRO);
		_btnIntro.label.color = isIntro ? C_BG : C_TEXT;
		_btnOutro.label.color = !isIntro ? C_BG : C_TEXT;
	}

	function _refreshSprList():Void
	{
		_sprRows.clear();
		_sprLabels.clear();
		_sprHits = [];
		final keys = _sprKeys();
		final py = panelY() + 20;
		final n = Std.int(Math.min(MAX_ROWS, keys.length - _sprScroll));
		for (i in 0...n)
		{
			final k = keys[i + _sprScroll];
			final ry = py + i * ROW_H;
			final sel = (k == selSpr);
			var row = new FlxSprite(0, ry).makeGraphic(LEFT_W - 2, ROW_H - 1, sel ? C_SEL : (i % 2 == 0 ? C_PANEL : C_BG));
			_reg(row);
			_sprRows.add(row);
			var lbl = _rawTxt(8, ry + 4, LEFT_W - 16, k, 10, sel ? C_ACCENT : C_TEXT);
			_sprLabels.add(lbl);
			_sprHits.push({y: ry, key: k});
		}
	}

	function _refreshStpList():Void
	{
		_stpRows.clear();
		_stpLabels.clear();
		_stpHits = [];
		final px = stepX();
		final pw = stepW();
		final py = panelY() + 20;
		final n = Std.int(Math.min(MAX_ROWS, doc.steps.length - _stpScroll));
		for (i in 0...n)
		{
			final idx = i + _stpScroll;
			final st = doc.steps[idx];
			final ry = py + i * ROW_H;
			final sel = (idx == selStep);
			var row = new FlxSprite(px, ry).makeGraphic(pw - 2, ROW_H - 1, sel ? C_SEL : _rowCol(st.action));
			_reg(row);
			_stpRows.add(row);
			final spr = (Reflect.hasField(st, 'sprite') && st.sprite != null) ? ' [${st.sprite}]' : '';
			final extra = _stepSummary(st);
			var lbl = _rawTxt(px + 8, ry + 4, pw - 24, '$idx. ${st.action}$spr$extra', 10, sel ? C_ACCENT : C_TEXT);
			_stpLabels.add(lbl);
			_stpHits.push({y: ry, idx: idx});
		}
	}

	function _refreshSprDD():Void
	{
		if (_spriteDD == null)
			return;
		// CoolDropDown has no setList() in the current flixel-ui version.
		// Recreate the widget in-place to update its item list.
		final sx = _spriteDD.x;
		final sy = _spriteDD.y;
		final prev = _spriteDD.selectedLabel;
		remove(_spriteDD);
		_spriteDD = new CoolDropDown(sx, sy, CoolDropDown.makeStrIdLabelArray(['(ninguno)'].concat(_sprKeys())));
		_spriteDD.cameras = [camHUD];
		_spriteDD.scrollFactor.set();
		add(_spriteDD);
		_spriteDD.selectedLabel = prev;
	}

	function _loadStepToInspector(idx:Int):Void
	{
		if (idx < 0 || idx >= doc.steps.length)
			return;
		final st = doc.steps[idx];
		if (_actionDD != null)
			_actionDD.selectedLabel = st.action;
		_rebuildParams();
		final params = PARAMS.get(st.action) ?? [];
		for (i in 0...Std.int(Math.min(params.length, _pInputs.length)))
		{
			final v = Reflect.field(st, params[i].k);
			_pInputs[i].text = (v != null) ? Std.string(v) : '';
		}
		if (_spriteDD != null)
		{
			final s = Reflect.field(st, 'sprite');
			_spriteDD.selectedLabel = (s != null) ? s : '(ninguno)';
		}
	}

	function _rebuildParams():Void
	{
		for (i in _pInputs)
		{
			i.visible = false;
			i.active = false;
		}
		for (l in _pLabels)
			l.visible = false;
		_pInputs = [];
		_pLabels = [];
		final action = _actionDD?.selectedLabel ?? ACTIONS[0];
		final params = PARAMS.get(action) ?? [];
		final px = inspX() + 6;
		var iy = panelY() + 70;
		for (p in params)
		{
			if (iy + 22 > statusY() - 32)
				break;
			var lbl = _mkTxt(px, iy, INSP_W - 12, '${p.l}:', 9, C_DIM);
			_pLabels.push(lbl);
			var inp = new CoolInputText(px, iy + 10, INSP_W - 14, '', 10);
			inp.scrollFactor.set();
			inp.cameras = [camHUD];
			add(inp);
			_pInputs.push(inp);
			iy += 30;
		}
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  Duración
	// ═════════════════════════════════════════════════════════════════════════
	function _recalcDuration():Void
	{
		cutDuration = 0;
		for (st in doc.steps)
			cutDuration += _stepDur(st);
		if (cutDuration < 1)
			cutDuration = 1;
		_bar.songLength = cutDuration;
	}

	function _stepDur(st:Dynamic):Float
	{
		final async = Reflect.field(st, 'async');
		if (async == true || Std.string(async) == 'true')
			return 0;
		return switch (Std.string(st.action))
		{
			case 'wait': _ff(st, 'time', 0);
			case 'tween' | 'cameraFade' | 'cameraFlash' | 'cameraShake' | 'cameraZoom' | 'cameraPan' | 'cameraReset': _ff(st, 'duration', 0);
			case 'fadeTimer': _ff(st, 'step', 0.15) * _ff(st, 'interval', 0.3);
			case 'waitBeat': (_ff(st, 'beat', 0) * Conductor.crochet) / 1000.0;
			case 'waitStep': (_ff(st, 'step', 0) * Conductor.stepCrochet) / 1000.0;
			case 'waitSound': 0.5;
			default: 0;
		};
	}

	inline function _ff(o:Dynamic, f:String, def:Float):Float
	{
		final v = Reflect.field(o, f);
		if (v == null)
			return def;
		final n = Std.parseFloat(Std.string(v));
		return Math.isNaN(n) ? def : n;
	}

	// ═════════════════════════════════════════════════════════════════════════
	//  IO
	// ═════════════════════════════════════════════════════════════════════════
	function _autoLoad():Void
	{
		#if sys
		for (t in ['intro', 'outro'])
		{
			final p = _pathFor(t);
			if (p != '' && FileSystem.exists(p))
			{
				try
				{
					final d = _parseRaw(File.getContent(p));
					if (t == 'intro')
					{
						docIntro = d;
						pathIntro = p;
					}
					else
					{
						docOutro = d;
						pathOutro = p;
					}
				}
				catch (e:Dynamic)
				{
				}
			}
		}
		#end
	}

	function _path():String
		return _pathFor(isIntro ? 'intro' : 'outro');

	function _pathFor(t:String):String
	{
		final s = _songName();
		#if sys
		return mods.ModManager.isActive() ? '${mods.ModManager.modRoot()}/songs/$s/$s-cutscene-$t.json' : 'assets/data/songs/$s/$s-cutscene-$t.json';
		#else
		return '';
		#end
	}

	function _applyDoc(raw:String):Void
	{
		final d = _parseRaw(raw);
		if (isIntro)
			docIntro = d
		else
			docOutro = d;
		selStep = -1;
		selSpr = null;
	}

	function _parseRaw(raw:String):CutsceneDoc
	{
		final d:CutsceneDoc = Json.parse(raw);
		if (d.sprites == null)
			d.sprites = {};
		if (d.steps == null)
			d.steps = [];
		return d;
	}

	inline function _songName():String
		return (PlayState.SONG?.song ?? 'cutscene').toLowerCase();

	inline function _sprKeys():Array<String>
		return Reflect.fields(doc.sprites);

	inline function empty():CutsceneDoc
		return {sprites: {}, steps: []};

	// ═════════════════════════════════════════════════════════════════════════
	//  Misc
	// ═════════════════════════════════════════════════════════════════════════
	function _rowCol(a:String):Int
		return switch (a)
		{
			case 'wait' | 'waitSound' | 'waitBeat' | 'waitStep': CR_WAIT;
			case 'cameraFade' | 'cameraFlash' | 'cameraShake' | 'cameraZoom' | 'cameraMove' | 'cameraPan' | 'cameraTarget' | 'cameraReset' | 'setCamVisible': CR_CAM;
			case 'playAnim' | 'tween' | 'fadeTimer' | 'setAlpha' | 'setColor' | 'setVisible' | 'setPosition' | 'screenCenter': CR_ANIM;
			case 'add': CR_ADD;
			case 'playSound': CR_SND;
			case 'end': CR_END;
			default: CR_DEF;
		};

	function _stepSummary(st:Dynamic):String
		return switch (Std.string(st.action))
		{
			case 'wait': ' ${_ff(st, "time", 0)}s';
			case 'playAnim': ' "${Reflect.field(st, "anim") ?? ""}"';
			case 'playSound': ' "${Reflect.field(st, "key") ?? ""}"';
			case 'tween': ' ${_ff(st, "duration", 0)}s';
			case 'cameraZoom': ' z=${_ff(st, "zoom", 1)} ${_ff(st, "duration", 0)}s';
			case 'waitBeat': ' beat=${Reflect.field(st, "beat") ?? ""}';
			case 'waitStep': ' step=${Reflect.field(st, "step") ?? ""}';
			case 'end': ' ← FIN';
			default: '';
		};

	function _markUnsaved():Void
	{
		hasUnsaved = true;
		if (_unsavedDot != null)
		{
			_unsavedDot.makeGraphic(8, 8, C_UNSAVED);
			_unsavedDot.visible = true;
		}
	}

	function _markSaved():Void
	{
		hasUnsaved = false;
		if (_unsavedDot != null)
		{
			_unsavedDot.makeGraphic(8, 8, C_SAVED);
			_unsavedDot.visible = true;
			new FlxTimer().start(2.0, _ ->
			{
				if (_unsavedDot != null)
					_unsavedDot.visible = hasUnsaved;
			});
		}
	}

	function _showStatus(msg:String):Void
		if (_statusTxt != null)
			_statusTxt.text = msg;

	static function _fmt(s:Float):String
	{
		final t = Std.int(s);
		final m = Std.int(t / 60);
		final ss = t % 60;
		final ms = Std.int((s - t) * 10);
		return '${m}:${ss < 10 ? "0" : ""}$ss.$ms';
	}

	// ─── Factory de UI ────────────────────────────────────────────────────────
	inline function _reg(s:flixel.FlxBasic):Void
	{
		if (Std.isOfType(s, FlxSprite))
			(cast s : FlxSprite).scrollFactor.set();
		s.cameras = [camHUD];
	}

	function _mkTxt(x:Float, y:Float, w:Float, t:String, sz:Int, col:Int):FlxText
	{
		var lbl = new FlxText(x, y, Std.int(w), t, sz);
		lbl.setFormat(Paths.font('vcr.ttf'), sz, col, LEFT);
		lbl.scrollFactor.set();
		lbl.cameras = [camHUD];
		add(lbl);
		return lbl;
	}

	function _rawTxt(x:Float, y:Float, w:Float, t:String, sz:Int, col:Int):FlxText
	{
		var lbl = new FlxText(x, y, Std.int(w), t, sz);
		lbl.setFormat(Paths.font('vcr.ttf'), sz, col, LEFT);
		lbl.scrollFactor.set();
		lbl.cameras = [camHUD];
		return lbl;
	}

	function _btn(x:Float, y:Float, w:Int, h:Int, lbl:String, col:Int, cb:Void->Void):_Btn
	{
		var b = new _Btn(x, y, w, h, lbl, col, C_TEXT, cb);
		b.scrollFactor.set();
		b.cameras = [camHUD];
		add(b);
		add(b.label);
		return b;
	}

	function _btnR(xr:Float, y:Float, w:Int, h:Int, lbl:String, col:Int, cb:Void->Void):_Btn
		return _btn(xr - w, y, w, h, lbl, col, cb);

	override function destroy():Void
	{
		#if sys
		if (_windowCloseFn != null)
		{
			try { lime.app.Application.current.window.onClose.remove(_windowCloseFn); } catch (_) {}
			_windowCloseFn = null;
		}
		#end
		super.destroy();
	}
}

// ═══════════════════════════════════════════════════════════════════════════════
typedef CutsceneDoc =
{
	var sprites:Dynamic;
	var steps:Array<Dynamic>;
}

// ═══════════════════════════════════════════════════════════════════════════════
private class _Btn extends FlxSprite
{
	public var label:FlxText;
	public var onClick:Void->Void;

	var _base:Int;
	var _hov:Int;
	var _isHov:Bool = false;

	public function new(x:Float, y:Float, w:Int, h:Int, lbl:String, col:Int, txtCol:Int, ?cb:Void->Void)
	{
		super(x, y);
		makeGraphic(w, h, col);
		_base = col;
		_hov = _lgt(col, 22);
		onClick = cb;
		label = new FlxText(x, y, w, lbl, 10);
		label.setFormat(Paths.font('vcr.ttf'), 10, txtCol, CENTER);
		label.scrollFactor.set();
	}

	override private function set_cameras(v:Array<flixel.FlxCamera>):Array<flixel.FlxCamera>
	{
		if (label != null)
			label.cameras = v;
		return super.set_cameras(v);
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);
		if (!alive || !visible)
			return;
		final cam = (cameras != null && cameras.length > 0) ? cameras[0] : FlxG.camera;
		final ov = FlxG.mouse.overlaps(this, cam);
		if (ov != _isHov)
		{
			_isHov = ov;
			makeGraphic(Std.int(width), Std.int(height), ov ? _hov : _base);
		}
		label.x = x;
		label.y = y + (height - label.height) * 0.5;
		if (ov && FlxG.mouse.justPressed && onClick != null)
			onClick();
	}

	public function setLabel(t:String):Void
		if (label != null)
			label.text = t;

	static function _lgt(c:Int, a:Int):Int
		return ((c >> 24) & 0xFF) << 24 | Std.int(Math.min(255,
			((c >> 16) & 0xFF) + a)) << 16 | Std.int(Math.min(255, ((c >> 8) & 0xFF) + a)) << 8 | Std.int(Math.min(255, (c & 0xFF) + a));
}
