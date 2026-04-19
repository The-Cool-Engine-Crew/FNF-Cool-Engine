package funkin.debug;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import openfl.display.Sprite;
import openfl.display.Shape;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFieldType;
import openfl.events.KeyboardEvent;
import openfl.ui.Keyboard;
import flixel.FlxState;
import funkin.states.MusicBeatState;
import funkin.transitions.StateTransition;
import funkin.audio.MusicManager;

using StringTools;

/**
 * ScriptConsoleState — State de consola estilo terminal para el engine.
 *
 * ══════════════════════════════════════════════════════════════════
 *  VISUAL
 * ══════════════════════════════════════════════════════════════════
 *  • Fondo negro total.
 *  • Rain de notas musicales (♩♪♫♬) y números cayendo tipo Matrix.
 *    Colores cyan / violeta / verde néon que cambian al beat.
 *  • Header "FUNKIN CONSOLE" con glow pulsante sincronizado al BPM.
 *  • Panel de consola centrado en la mitad-inferior con:
 *      – Área de log con scroll.
 *      – Campo de entrada con prompt "> ".
 *      – Cursor parpadeante.
 *  • Borde del panel que flashea cyan en cada beat.
 *
 * ══════════════════════════════════════════════════════════════════
 *  COMANDOS
 * ══════════════════════════════════════════════════════════════════
 *  open  <State>   Ir a ese state (ej: open FreeplayState)
 *  back / exit     Volver al estado anterior
 *  help            Listar comandos disponibles
 *  clear           Limpiar log
 *  echo  <texto>   Imprimir texto
 *  state           Mostrar state actual
 *  fps             FPS actual
 *  reload          Recargar este mismo state
 *  volume <0-1>    Volumen de música
 *  zoom   <n>      Camera zoom
 *  bpm    <n>      Cambiar BPM del Conductor
 *
 * ══════════════════════════════════════════════════════════════════
 *  TECLADO
 * ══════════════════════════════════════════════════════════════════
 *  Enter           Ejecutar comando
 *  ↑ / ↓          Historial de comandos
 *  Tab             Autocompletar
 *  ESC             Salir
 */
class ScriptConsoleState extends MusicBeatState {
	// ── Layout ───────────────────────────────────────────────────────────────
	static inline var SW:Int = 1280;
	static inline var SH:Int = 720;
	static inline var PAN_W:Int = 860;
	static inline var PAN_H:Int = 290;
	static inline var PAN_X:Int = Std.int((SW - PAN_W) / 2);
	static inline var PAN_Y:Int = 390;
	static inline var LOG_H:Int = 228;
	static inline var INPUT_H:Int = 28;
	static inline var PADDING:Int = 10;

	// ── Colours ──────────────────────────────────────────────────────────────
	static inline var C_BG:Int = 0xFF000000;
	static inline var C_PANEL:Int = 0xE5050510;
	static inline var C_BORDER:Int = 0xFF00F0FF;
	static inline var C_HEADER:Int = 0xFF00F0FF;
	static inline var C_INPUT_BG:Int = 0xFF020215;
	static inline var C_PROMPT:Int = 0xFF00F0FF;
	static inline var C_TEXT:Int = 0xFFCCEEFF;
	static inline var C_SUCCESS:Int = 0xFF00FF88;
	static inline var C_ERROR:Int = 0xFFFF4466;
	static inline var C_WARN:Int = 0xFFFFCC00;
	static inline var C_CMD:Int = 0xFF88FFFF;
	static inline var C_DIM:Int = 0xFF334455;

	// ── Matrix rain ──────────────────────────────────────────────────────────
	static inline var RAIN_COLS:Int = 38;
	static inline var RAIN_CHARS:String = '0123456789ABCDEF><()[]{}|/\\';
	static inline var RAIN_SPEED_MIN:Float = 80;
	static inline var RAIN_SPEED_MAX:Float = 260;

	var _rainTexts:Array<FlxText> = [];
	var _rainY:Array<Float> = [];
	var _rainSpeed:Array<Float> = [];
	var _rainChar:Array<FlxText> = []; // single leading character (brighter)
	var _rainTrails:Array<Array<FlxText>> = [];

	static inline var TRAIL_LEN:Int = 12;

	// ── Header ───────────────────────────────────────────────────────────────
	var _headerTxt:FlxText;
	var _subHeaderTxt:FlxText;
	var _headerGlow:FlxSprite;

	// ── Panel (OpenFL overlay) ────────────────────────────────────────────────
	var _panelSprite:Sprite;
	var _logField:TextField;
	var _inputField:TextField;
	var _cursorSprite:Shape;

	// ── Camera HUD ───────────────────────────────────────────────────────────
	var _camHUD:FlxCamera;

	// ── Panel FlxSprite border (beat flash) ─────────────────────────────────
	var _panelBorder:FlxSprite;

	// ── Console state ────────────────────────────────────────────────────────
	var _logLines:Array<{text:String, col:Int}> = [];
	var _cmdHistory:Array<String> = [];
	var _historyIdx:Int = -1;
	var _cursorBlink:Float = 0.0;
	var _cursorVis:Bool = true;
	var _inputActive:Bool = true;
	var _beatFlash:Float = 0.0;

	// ── Previous state (for 'back') ──────────────────────────────────────────
	static var _prevStateFactory:Null<Void->FlxState> = null;

	/** Call this before switching to ScriptConsoleState to remember where to go back. */
	public static function openFrom(factory:Void->FlxState):Void {
		_prevStateFactory = factory;
		StateTransition.switchState(new ScriptConsoleState());
	}

	// ─────────────────────────────────────────────────────────────────────────
	// CREATE
	// ─────────────────────────────────────────────────────────────────────────
	override function create():Void {
		super.create();

		MusicManager.play('chartEditorLoop/chartEditorLoop', 0.4);

		// ── Background ──────────────────────────────────────────────────────
		var bg = new FlxSprite().makeGraphic(SW, SH, FlxColor.BLACK);
		bg.scrollFactor.set();
		add(bg);

		// ── HUD camera ──────────────────────────────────────────────────────
		_camHUD = new FlxCamera();
		_camHUD.bgColor = FlxColor.TRANSPARENT;
		FlxG.cameras.add(_camHUD, false);

		// ── Matrix rain ─────────────────────────────────────────────────────
		_buildRain();

		// ── Header glow ─────────────────────────────────────────────────────
		_headerGlow = new FlxSprite(0, 0).makeGraphic(SW, 90, 0x00000000);
		_headerGlow.scrollFactor.set();
		_headerGlow.cameras = [_camHUD];
		add(_headerGlow);
		_tintGlow(C_BORDER);

		// ── Header text ─────────────────────────────────────────────────────
		_headerTxt = new FlxText(0, 16, SW, 'FUNKIN CONSOLE', 40);
		_headerTxt.setFormat(null, 40, FlxColor.fromInt(C_HEADER), CENTER, OUTLINE);
		_headerTxt.borderColor = FlxColor.fromInt(0xFF004466);
		_headerTxt.borderSize = 3;
		_headerTxt.scrollFactor.set();
		_headerTxt.cameras = [_camHUD];
		add(_headerTxt);

		_subHeaderTxt = new FlxText(0, 60, SW, 'type  help  for command list  •  ESC to exit', 12);
		_subHeaderTxt.setFormat(null, 12, FlxColor.fromInt(C_DIM), CENTER);
		_subHeaderTxt.scrollFactor.set();
		_subHeaderTxt.cameras = [_camHUD];
		add(_subHeaderTxt);

		// ── Panel border (FlxSprite, for beat flash) ─────────────────────────
		_panelBorder = new FlxSprite(PAN_X - 2, PAN_Y - 2).makeGraphic(PAN_W + 4, PAN_H + 4, FlxColor.fromInt(C_BORDER));
		_panelBorder.scrollFactor.set();
		_panelBorder.cameras = [_camHUD];
		add(_panelBorder);

		var panelFill = new FlxSprite(PAN_X, PAN_Y).makeGraphic(PAN_W, PAN_H, FlxColor.fromInt(C_PANEL));
		panelFill.scrollFactor.set();
		panelFill.cameras = [_camHUD];
		add(panelFill);

		// ── OpenFL panel overlay ─────────────────────────────────────────────
		_buildOpenFLPanel();

		// ── Footer hint ──────────────────────────────────────────────────────
		var footerTxt = new FlxText(0, SH - 20, SW, 'Enter  Execute    ↑↓  History    Tab  Autocomplete    ESC  Exit', 10);
		footerTxt.setFormat(null, 10, FlxColor.fromInt(C_DIM), CENTER);
		footerTxt.scrollFactor.set();
		footerTxt.cameras = [_camHUD];
		add(footerTxt);

		// ── Keyboard listener ────────────────────────────────────────────────
		FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, _onKeyDown);

		// ── Initial messages ─────────────────────────────────────────────────
		_log('╔═══════════════════════════════════════════════╗', C_BORDER);
		_log('║       FUNKIN CONSOLE  v1.0  — ready           ║', C_HEADER);
		_log('╚═══════════════════════════════════════════════╝', C_BORDER);
		_log('type  help  to see available commands.', C_DIM);
		_log('');
	}

	// ─────────────────────────────────────────────────────────────────────────
	// BUILD HELPERS
	// ─────────────────────────────────────────────────────────────────────────
	function _buildRain():Void {
		var colW = Std.int(SW / RAIN_COLS);
		for (c in 0...RAIN_COLS) {
			var startY = -FlxG.random.float(0, SH);
			var speed = FlxG.random.float(RAIN_SPEED_MIN, RAIN_SPEED_MAX);
			_rainY.push(startY);
			_rainSpeed.push(speed);

			// Trail texts
			var trail:Array<FlxText> = [];
			for (t in 0...TRAIL_LEN) {
				var tt = new FlxText(c * colW, startY - t * 18, colW, _rndChar(), 14);
				var alpha = 1.0 - (t / TRAIL_LEN);
				tt.color = FlxColor.fromRGBFloat(0, alpha * 0.9, alpha, alpha);
				tt.scrollFactor.set();
				add(tt);
				trail.push(tt);
			}
			_rainTrails.push(trail);

			// Bright leader
			var lead = new FlxText(c * colW, startY, colW, _rndChar(), 15);
			lead.color = FlxColor.WHITE;
			lead.scrollFactor.set();
			add(lead);
			_rainChar.push(lead);
		}
	}

	function _buildOpenFLPanel():Void {
		// Scale from game coords to screen pixels
		var scaleX = FlxG.stage.stageWidth / SW;
		var scaleY = FlxG.stage.stageHeight / SH;

		_panelSprite = new Sprite();
		_panelSprite.x = PAN_X * scaleX;
		_panelSprite.y = PAN_Y * scaleY;

		// Log text field
		_logField = new TextField();
		_logField.x = PADDING;
		_logField.y = PADDING;
		_logField.width = (PAN_W - PADDING * 2) * scaleX;
		_logField.height = LOG_H * scaleY;
		_logField.multiline = true;
		_logField.wordWrap = true;
		_logField.selectable = false;
		_logField.mouseEnabled = false;
		_logField.defaultTextFormat = new TextFormat('_typewriter', Std.int(11 * scaleY), C_TEXT);
		_panelSprite.addChild(_logField);

		// Separator line
		var sep = new Shape();
		sep.graphics.lineStyle(1, C_BORDER, 0.5);
		sep.graphics.moveTo(PADDING * scaleX, (LOG_H + PADDING + 2) * scaleY);
		sep.graphics.lineTo((PAN_W - PADDING) * scaleX, (LOG_H + PADDING + 2) * scaleY);
		_panelSprite.addChild(sep);

		// Prompt label
		var promptTf = new TextField();
		promptTf.x = PADDING * scaleX;
		promptTf.y = (LOG_H + PADDING + 6) * scaleY;
		promptTf.width = 22 * scaleX;
		promptTf.height = INPUT_H * scaleY;
		promptTf.selectable = false;
		promptTf.mouseEnabled = false;
		promptTf.defaultTextFormat = new TextFormat('_typewriter', Std.int(12 * scaleY), C_PROMPT, true);
		promptTf.text = '>';
		_panelSprite.addChild(promptTf);

		// Input field
		_inputField = new TextField();
		_inputField.type = TextFieldType.INPUT;
		_inputField.x = (PADDING + 22) * scaleX;
		_inputField.y = (LOG_H + PADDING + 6) * scaleY;
		_inputField.width = (PAN_W - PADDING * 2 - 26) * scaleX;
		_inputField.height = INPUT_H * scaleY;
		_inputField.multiline = false;
		_inputField.wordWrap = false;
		_inputField.defaultTextFormat = new TextFormat('_typewriter', Std.int(12 * scaleY), C_TEXT);
		_panelSprite.addChild(_inputField);

		// Cursor blink shape
		_cursorSprite = new Shape();
		_panelSprite.addChild(_cursorSprite);

		FlxG.stage.addChild(_panelSprite);

		// Focus input
		FlxG.stage.focus = _inputField;
	}

	// ─────────────────────────────────────────────────────────────────────────
	// UPDATE
	// ─────────────────────────────────────────────────────────────────────────
	override function update(elapsed:Float):Void {
		super.update(elapsed);

		_updateRain(elapsed);
		_updateCursor(elapsed);
		_updateBeatFlash(elapsed);
		_updateHeaderPulse(elapsed);

		if (FlxG.keys.justPressed.ESCAPE)
			_cmdBack([]);
	}

	function _updateRain(elapsed:Float):Void {
		var colW = SW / RAIN_COLS;
		for (c in 0...RAIN_COLS) {
			_rainY[c] += _rainSpeed[c] * elapsed;

			if (_rainY[c] > SH + 30) {
				_rainY[c] = -FlxG.random.float(20, 180);
				_rainSpeed[c] = FlxG.random.float(RAIN_SPEED_MIN, RAIN_SPEED_MAX);
			}

			var ry = _rainY[c];

			// Leader
			_rainChar[c].x = c * colW;
			_rainChar[c].y = ry;
			if (FlxG.random.bool(8))
				_rainChar[c].text = _rndChar();

			// Trail
			var trail = _rainTrails[c];
			for (t in 0...TRAIL_LEN) {
				var tt = trail[t];
				tt.x = c * colW;
				tt.y = ry - (t + 1) * 18;
				if (FlxG.random.bool(5))
					tt.text = _rndChar();
				var fade = (1.0 - (t / TRAIL_LEN));
				// Alternate between cyan and violet per column
				if (c % 3 == 0)
					tt.color = FlxColor.fromRGBFloat(0.05, fade * 0.85, fade, fade * 0.9);
				else if (c % 3 == 1)
					tt.color = FlxColor.fromRGBFloat(fade * 0.6, 0.05, fade, fade * 0.8);
				else
					tt.color = FlxColor.fromRGBFloat(0.05, fade, fade * 0.4, fade * 0.9);
			}
		}
	}

	function _updateCursor(elapsed:Float):Void {
		_cursorBlink += elapsed;
		if (_cursorBlink > 0.5) {
			_cursorBlink = 0;
			_cursorVis = !_cursorVis;
			_drawCursor();
		}
	}

	function _drawCursor():Void {
		if (_cursorSprite == null)
			return;
		_cursorSprite.graphics.clear();
		if (!_cursorVis)
			return;

		var scaleX = FlxG.stage.stageWidth / SW;
		var scaleY = FlxG.stage.stageHeight / SH;

		// Position after the last character in the input field
		var tf = _inputField;
		var cx = tf.x + tf.textWidth + 2;
		var cy = tf.y + 2;
		_cursorSprite.graphics.beginFill(C_PROMPT, 0.9);
		_cursorSprite.graphics.drawRect(cx, cy, 2 * scaleX, 14 * scaleY);
		_cursorSprite.graphics.endFill();
	}

	function _updateBeatFlash(elapsed:Float):Void {
		if (_beatFlash > 0) {
			_beatFlash -= elapsed * 6;
			if (_beatFlash < 0)
				_beatFlash = 0;
			var t = FlxEase.cubeOut(_beatFlash);
			var col = FlxColor.interpolate(FlxColor.fromInt(C_BORDER), FlxColor.WHITE, t);
			_panelBorder.color = col;
		}
	}

	function _updateHeaderPulse(elapsed:Float):Void {
		var t = (Math.sin(FlxG.game.ticks / 300) * 0.5 + 0.5);
		_headerTxt.alpha = 0.75 + t * 0.25;
	}

	override function beatHit():Void {
		super.beatHit();
		_beatFlash = 1.0;

		// Randomise a few rain column speeds on beat for visual rhythm
		for (_ in 0...4) {
			var c = FlxG.random.int(0, RAIN_COLS - 1);
			_rainSpeed[c] = FlxG.random.float(RAIN_SPEED_MIN, RAIN_SPEED_MAX);
		}

		// Tint glow with random accent
		var glowCols = [C_BORDER, 0xFFFF00FF, 0xFF00FF88, 0xFFFF4488];
		_tintGlow(glowCols[curBeat % glowCols.length]);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// KEYBOARD INPUT
	// ─────────────────────────────────────────────────────────────────────────
	function _onKeyDown(e:KeyboardEvent):Void {
		switch (e.keyCode) {
			case Keyboard.ENTER:
				var cmd = _inputField.text.trim();
				_inputField.text = '';
				_cursorBlink = 0;
				if (cmd.length > 0) {
					if (_cmdHistory.length == 0 || _cmdHistory[_cmdHistory.length - 1] != cmd)
						_cmdHistory.push(cmd);
					_historyIdx = -1;
					_executeCommand(cmd);
				}

			case Keyboard.UP:
				if (_cmdHistory.length > 0) {
					if (_historyIdx == -1)
						_historyIdx = _cmdHistory.length - 1;
					else if (_historyIdx > 0)
						_historyIdx--;
					_inputField.text = _cmdHistory[_historyIdx];
				}

			case Keyboard.DOWN:
				if (_historyIdx >= 0) {
					_historyIdx++;
					if (_historyIdx >= _cmdHistory.length) {
						_historyIdx = -1;
						_inputField.text = '';
					} else {
						_inputField.text = _cmdHistory[_historyIdx];
					}
				}

			case Keyboard.TAB:
				_autocomplete();
				e.preventDefault();

			case Keyboard.ESCAPE:
				_cmdBack([]);
		}

		// Re-focus input if it lost focus
		if (FlxG.stage.focus != _inputField)
			FlxG.stage.focus = _inputField;
	}

	function _autocomplete():Void {
		var partial = _inputField.text.trim().toLowerCase();
		if (partial == '')
			return;

		var all = [
			'open ',
			'help',
			'clear',
			'echo ',
			'state',
			'fps',
			'reload',
			'back',
			'exit',
			'volume ',
			'zoom ',
			'bpm '
		];

		var matches = all.filter(c -> c.toLowerCase().startsWith(partial));
		if (matches.length == 1) {
			_inputField.text = matches[0];
			_log('[tab] → ${matches[0]}', C_DIM);
			_scrollLogToBottom();
		} else if (matches.length > 1) {
			_log('[tab] ' + matches.join('  '), C_DIM);
			_scrollLogToBottom();
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	// COMMAND EXECUTION
	// ─────────────────────────────────────────────────────────────────────────
	function _executeCommand(raw:String):Void {
		_log('> ' + raw, C_CMD);

		var parts = raw.trim().split(' ');
		var cmd = parts[0].toLowerCase();
		var args = parts.slice(1);

		switch (cmd) {
			case 'open':
				_cmdOpen(args);
			case 'back', 'exit':
				_cmdBack(args);
			case 'help':
				_cmdHelp(args);
			case 'clear':
				_cmdClear(args);
			case 'echo':
				_log(args.join(' '), C_TEXT);
			case 'state':
				_log('Current: ' + Type.getClassName(Type.getClass(FlxG.state)), C_SUCCESS);
			case 'fps':
				_log('FPS: ' + Std.string(Math.round(1 / FlxG.elapsed)), C_SUCCESS);
			case 'reload':
				_cmdReload(args);
			case 'volume':
				_cmdVolume(args);
			case 'zoom':
				_cmdZoom(args);
			case 'bpm':
				_cmdBpm(args);
			default:
				_log('Unknown command: "$cmd"  —  type  help', C_ERROR);
		}

		_log('');
		_scrollLogToBottom();
	}

	// ── open ─────────────────────────────────────────────────────────────────
	function _cmdOpen(args:Array<String>):Void {
		if (args.length == 0) {
			_log('Usage: open <StateName>', C_WARN);
			_log('Examples: open FreeplayState  /  open MainMenuState', C_DIM);
			return;
		}

		var name = args[0];
		var state = _resolveState(name);

		if (state == null) {
			_log('Cannot resolve state: "$name"', C_ERROR);
			_log('Known: MainMenuState, FreeplayState, StoryMenuState,', C_DIM);
			_log('       CharacterSelectorState, OptionsMenuState,', C_DIM);
			_log('       EditorHubState, ScriptConsoleState', C_DIM);
			return;
		}

		_log('Switching → $name  ...', C_SUCCESS);
		_cleanupAndSwitch(state);
	}

	function _resolveState(name:String):FlxState {
		// Friendly name map (without full package)
		var nameL = name.toLowerCase().replace('state', '');
		return switch (nameL) {
			case 'mainmenu', 'main', 'menu':
				new funkin.menus.MainMenuState();
			case 'freeplay':
				new funkin.menus.FreeplayState();
			case 'storymenu', 'story', 'storymode':
				new funkin.menus.StoryMenuState();
			case 'options', 'optionsmenu', 'settings':
				new funkin.menus.OptionsMenuState();
			case 'credits':
				new funkin.menus.credits.CreditsState();
			case 'editorhub', 'editors', 'hub', 'editor':
				new funkin.debug.EditorHubState();
			case 'console', 'scriptconsole':
				new funkin.debug.ScriptConsoleState();
			case 'modselector', 'mods', 'modselectormenu':
				new funkin.menus.ModSelectorState();
			case 'intro', 'introstate':
				new funkin.menus.IntroState();
			default:
				// Try full qualified class via reflection
				var cls = Type.resolveClass('funkin.menus.' + name) ?? Type.resolveClass('funkin.debug.' + name) ?? Type.resolveClass('funkin.debug.editors.'
					+ name) ?? Type.resolveClass('funkin.states.' + name) ?? Type.resolveClass('funkin.' + name) ?? Type.resolveClass(name);
				if (cls != null) {
					try {
						return cast Type.createInstance(cls, []);
					} catch (ex:Dynamic) {
						_log('Error instantiating: $ex', C_ERROR);
					}
				}
				null;
		};
	}

	// ── back ─────────────────────────────────────────────────────────────────
	function _cmdBack(args:Array<String>):Void {
		if (_prevStateFactory != null) {
			var s = _prevStateFactory();
			_prevStateFactory = null;
			_cleanupAndSwitch(s);
		} else {
			_cleanupAndSwitch(new funkin.menus.MainMenuState());
		}
	}

	// ── help ─────────────────────────────────────────────────────────────────
	function _cmdHelp(args:Array<String>):Void {
		var cmds:Array<Array<String>> = [
			['open  <State>', 'Switch to a state (ex: open FreeplayState)'],
			['back  /  exit', 'Return to previous state'],
			['help', 'Show this list'],
			['clear', 'Clear console log'],
			['echo  <text>', 'Print text to log'],
			['state', 'Print current state class name'],
			['fps', 'Print current FPS'],
			['reload', 'Reload ScriptConsoleState'],
			['volume  <0-1>', 'Set menu music volume'],
			['zoom  <n>', 'Set camera zoom (default 1.0)'],
			['bpm  <n>', 'Set Conductor BPM'],
		];
		_log('═══ Commands ════════════════════════════════════', C_BORDER);
		for (row in cmds)
			_log('  ' + _padR(row[0], 22) + row[1], C_TEXT);
		_log('════════════════════════════════════════════════', C_BORDER);
	}

	// ── reload ───────────────────────────────────────────────────────────────
	function _cmdReload(args:Array<String>):Void {
		_log('Reloading console...', C_SUCCESS);
		_cleanupAndSwitch(new ScriptConsoleState());
	}

	// ── volume ───────────────────────────────────────────────────────────────
	function _cmdVolume(args:Array<String>):Void {
		if (args.length == 0) {
			_log('Usage: volume <0-1>', C_WARN);
			return;
		}
		var v = Std.parseFloat(args[0]);
		if (Math.isNaN(v)) {
			_log('Invalid number: ${args[0]}', C_ERROR);
			return;
		}
		v = FlxMath.bound(v, 0, 1);
		FlxG.sound.volume = v;
		_log('Volume set to ${v}', C_SUCCESS);
	}

	// ── zoom ─────────────────────────────────────────────────────────────────
	function _cmdZoom(args:Array<String>):Void {
		if (args.length == 0) {
			_log('Usage: zoom <factor>', C_WARN);
			return;
		}
		var z = Std.parseFloat(args[0]);
		if (Math.isNaN(z) || z <= 0) {
			_log('Invalid zoom: ${args[0]}', C_ERROR);
			return;
		}
		FlxG.camera.zoom = z;
		_log('Camera zoom → $z', C_SUCCESS);
	}

	// ── bpm ──────────────────────────────────────────────────────────────────
	function _cmdBpm(args:Array<String>):Void {
		if (args.length == 0) {
			_log('Usage: bpm <value>', C_WARN);
			return;
		}
		var b = Std.parseFloat(args[0]);
		if (Math.isNaN(b) || b <= 0) {
			_log('Invalid BPM: ${args[0]}', C_ERROR);
			return;
		}
		funkin.data.Conductor.changeBPM(b);
		_log('BPM → $b', C_SUCCESS);
	}

	// ── clear ────────────────────────────────────────────────────────────────
	function _cmdClear(args:Array<String>):Void {
		_logLines = [];
		_rebuildLogField();
	}

	// ─────────────────────────────────────────────────────────────────────────
	// LOG HELPERS
	// ─────────────────────────────────────────────────────────────────────────
	function _log(text:String, col:Int = C_TEXT):Void {
		_logLines.push({text: text, col: col});
		if (_logLines.length > 200)
			_logLines.shift();
		_rebuildLogField();
	}

	function _rebuildLogField():Void {
		if (_logField == null)
			return;
		var sb = new StringBuf();
		for (line in _logLines)
			sb.add(line.text + '\n');
		_logField.text = sb.toString();

		// Apply colour to last added line
		// (TextField doesn't support per-line colour easily — use a simple workaround:
		//  last line gets the right colour via setTextFormat on that range)
		var full = _logField.text;
		if (_logLines.length > 0) {
			var last = _logLines[_logLines.length - 1];
			var start = full.length - last.text.length - 1;
			if (start < 0)
				start = 0;
			var fmt = new TextFormat('_typewriter', null, last.col);
			_logField.setTextFormat(fmt, start, full.length);
		}

		_scrollLogToBottom();
	}

	function _scrollLogToBottom():Void {
		if (_logField != null)
			_logField.scrollV = _logField.maxScrollV;
	}

	// ─────────────────────────────────────────────────────────────────────────
	// VISUAL HELPERS
	// ─────────────────────────────────────────────────────────────────────────
	inline function _rndChar():String {
		return RAIN_CHARS.charAt(FlxG.random.int(0, RAIN_CHARS.length - 1));
	}

	function _tintGlow(col:Int):Void {
		if (_headerGlow == null)
			return;
		var c = FlxColor.fromInt(col);
		_headerGlow.makeGraphic(SW, 90, FlxColor.fromRGBFloat(c.redFloat, c.greenFloat, c.blueFloat, 0.08));
	}

	inline function _padR(s:String, n:Int):String {
		while (s.length < n)
			s += ' ';
		return s;
	}

	// ─────────────────────────────────────────────────────────────────────────
	// CLEANUP
	// ─────────────────────────────────────────────────────────────────────────
	function _cleanupAndSwitch(target:FlxState):Void {
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, _onKeyDown);
		if (_panelSprite != null && FlxG.stage.contains(_panelSprite))
			FlxG.stage.removeChild(_panelSprite);
		StateTransition.switchState(target);
	}

	override function destroy():Void {
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, _onKeyDown);
		if (_panelSprite != null && FlxG.stage.contains(_panelSprite))
			FlxG.stage.removeChild(_panelSprite);
		if (_camHUD != null)
			FlxG.cameras.remove(_camHUD, true);
		super.destroy();
	}
}
