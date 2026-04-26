package ui;

import openfl.display.Sprite;
import openfl.display.Shape;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.events.Event;
import openfl.events.KeyboardEvent;
import openfl.system.System;
import flixel.FlxG;
import funkin.system.SystemInfo;
import funkin.system.WindowManager;
import funkin.audio.AudioConfig;

using StringTools;

/**
 * DataInfoUI — overlay de debug/stats superpuesto sobre el juego.
 *
 * ─── Capas de información ────────────────────────────────────────────────────
 *  • FPSCount    — FPS + RAM usada + RAM pico + GC Mem  (siempre visible)
 *  • _devLabel   — Watermark "Developer Mode" (solo si developerMode=true)
 *  • SystemPanel — OS, CPU, GPU, VRAM, RAM total  (toggle con F3)
 *  • StatsPanel  — GPU renderer, draw calls, cache, audio config  (toggle con F3)
 *  • GameplayDebugOverlay — overlay completo de gameplay (toggle con F1)
 *
 * ─── Controles ───────────────────────────────────────────────────────────────
 *  F1         — alterna GameplayDebugOverlay (gráfica FPS + info de gameplay)
 *  F3         — alterna visibilidad de SystemPanel + StatsPanel
 *  Shift+F3   — alterna visibilidad de todo el overlay
 *
 * @author  Cool Engine Team
 * @since   0.6.0
 */
class DataInfoUI extends Sprite
{
	public var fps:FPSCount;
	public var systemPanel:SystemPanel;
	public var statsPanel:StatsPanel;

	/** @deprecated Mantener compatibilidad con código que lee .gpuEnabled */
	public static var gpuEnabled:Bool = true;

	public static var saveData:Dynamic = null;

	private var _bg:Shape;
	private var _devLabel:TextField;
	private var _expanded:Bool = false;

	/** Overlay de debug de gameplay (F1). */
	public var gameplayOverlay:GameplayDebugOverlay;

	// Padding interior del fondo
	private static inline var PAD_X:Float = 6;
	private static inline var PAD_Y:Float = 4;

	public function new(x:Float = 10, y:Float = 10)
	{
		super();

		saveData = _getSaveData();
		gpuEnabled = (saveData?.gpuRendering ?? true);

		// Fondo semitransparente — se redimensiona cada frame con el contenido
		_bg = new Shape();
		_updateBG(200, 36);
		addChild(_bg);

		// FPS counter (2 líneas: FPS+Mem / GC Mem)
		fps = new FPSCount(PAD_X, PAD_Y, 0xFFFFFF);
		addChild(fps);

		// Watermark "Developer Mode"
		_devLabel = new TextField();
		_devLabel.selectable = false;
		_devLabel.mouseEnabled = false;
		_devLabel.defaultTextFormat = new TextFormat(openfl.utils.Assets.getFont(Paths.font("Funkin.otf")).fontName, 16, 0xFFFFFF);
		_devLabel.autoSize = openfl.text.TextFieldAutoSize.LEFT;
		_devLabel.text = "Developer Mode";
		_devLabel.x = PAD_X;
		_devLabel.visible = false;
		addChild(_devLabel);

		// Panel de info del sistema (oculto por defecto)
		systemPanel = new SystemPanel(x, 0);
		systemPanel.visible = false;
		addChild(systemPanel);

		// Panel de stats de rendimiento (oculto por defecto)
		statsPanel = new StatsPanel(x, SystemPanel.HEIGHT + 4);
		statsPanel.visible = false;
		addChild(statsPanel);

		// Restaurar estado previo
		var showExpanded = saveData?.showDebugStats ?? false;
		if (showExpanded)
			_setExpanded(true);

		this.x = x;
		this.y = y;

		// ── Overlay de gameplay F1 ────────────────────────────────────────────
		// Se añade directamente al stage para que pueda posicionarse en la
		// esquina derecha de forma independiente a DataInfoUI.
		gameplayOverlay = new GameplayDebugOverlay(fps);

		// Keyboard listener a nivel de stage para F1 y F3
		openfl.Lib.current.stage.addEventListener(KeyboardEvent.KEY_DOWN, _onKeyDown);

		addEventListener(Event.ENTER_FRAME, _onFrame);
	}

	// ── Frame loop — reposicionar y redimensionar el fondo ────────────────────

	private function _onFrame(_:Event):Void
	{
		var devMode = mods.ModManager.developerMode;

		_devLabel.visible = devMode;
		_devLabel.y = fps.y + fps.textHeight + 1;

		var contentW:Float = fps.textWidth + PAD_X * 2;
		if (devMode && _devLabel.textWidth + PAD_X * 2 > contentW)
			contentW = _devLabel.textWidth + PAD_X * 2;

		var fpsH:Float = fps.textHeight;
		var labelH:Float = devMode ? (_devLabel.textHeight + 1) : 0;
		var collapsedH:Float = PAD_Y + fpsH + labelH + PAD_Y;

		var totalH:Float;
		if (_expanded)
		{
			var panelsTop:Float = collapsedH;
			systemPanel.y = panelsTop;
			statsPanel.y = panelsTop + SystemPanel.HEIGHT + 4;
			totalH = panelsTop + SystemPanel.HEIGHT + StatsPanel.HEIGHT + 8;
			if (contentW < 230)
				contentW = 230;
		}
		else
		{
			totalH = collapsedH;
		}

		_updateBG(contentW, totalH);
	}

	// ── Keyboard ──────────────────────────────────────────────────────────────

	private function _onKeyDown(e:KeyboardEvent):Void
	{
		switch (e.keyCode)
		{
			case 112: // F1 — toggle overlay de gameplay
				gameplayOverlay.toggle();

			case 114: // F3 — toggle system/stats panels
				if (e.shiftKey)
					visible = !visible;
				else
					toggleExpanded();
		}
	}

	// ── Toggles ───────────────────────────────────────────────────────────────

	public function toggleExpanded():Void
	{
		_setExpanded(!_expanded);
		if (saveData != null)
			saveData.showDebugStats = _expanded;
	}

	private function _setExpanded(v:Bool):Void
	{
		_expanded = v;
		systemPanel.visible = v;
		statsPanel.visible = v;
	}

	/** Toggle legacy para compatibilidad (antes se llamaba toggleGPUStats). */
	public inline function toggleGPUStats():Void
		toggleExpanded();

	// ── Helpers ───────────────────────────────────────────────────────────────

	private function _updateBG(w:Float, h:Float):Void
	{
		_bg.graphics.clear();
		_bg.graphics.beginFill(0x000000, 0.55);
		_bg.graphics.drawRoundRect(0, 0, w, h, 4);
		_bg.graphics.endFill();
	}

	private static function _getSaveData():Dynamic
	{
		if (FlxG.save != null && FlxG.save.data != null)
			return FlxG.save.data;
		return null;
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// GameplayDebugOverlay  (F1)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Overlay de debug completo activado con F1.
 *
 * ─── Panel izquierdo (debajo del FPS counter) ────────────────────────────────
 *  • Gráfica de FPS (sparkline de barras, últimos 120 frames)
 *  • Estado actual  (nombre de clase del FlxState)
 *  • Song pos / curStep / curBeat / BPM
 *  • Posición de camFollow + target + locked
 *
 * ─── Panel derecho (esquina superior derecha) ────────────────────────────────
 *  • VRAM  (SystemInfo)
 *  • Texturas en caché  (FunkinCache.getStats)
 *  • Nº de cámaras Flixel
 *  • Nº de miembros en el state actual
 *  • Zoom de camGame / camHUD
 *  • Scroll de camGame (x, y)
 *  • Scripts cargados (HScript × / Lua ×)
 *  • Mod activo  /  Script API version
 */
class GameplayDebugOverlay extends Sprite
{
	private var _fpsRef:FPSCount;

	// Paneles
	private var _leftPanel:DebugPanel;
	private var _rightPanel:DebugPanel;

	// Ring buffer para la gráfica de FPS
	private static inline var GRAPH_SAMPLES:Int = 120;

	private var _fpsRing:Array<Int>;
	private var _fpsRingHead:Int = 0;

	// Canvas de la gráfica
	private var _graph:Shape;

	private static inline var GRAPH_W:Int = 210;
	private static inline var GRAPH_H:Int = 36;

	// Throttle de actualización del texto
	private static inline var TEXT_INTERVAL:Float = 0.12;

	private var _textElapsed:Float = 0;

	public var shown(default, null):Bool = false;

	public function new(fpsRef:FPSCount)
	{
		super();
		_fpsRef = fpsRef;

		_fpsRing = [for (_ in 0...GRAPH_SAMPLES) 0];

		// Panel izquierdo: gráfica + info de gameplay
		_leftPanel = new DebugPanel(GRAPH_W + 10, 10, 0x000000, 0.72);
		_graph = new Shape();
		_leftPanel.addChild(_graph);
		addChild(_leftPanel);

		// Panel derecho: info de sistema / cámara / scripts
		_rightPanel = new DebugPanel(224, 10, 0x000000, 0.72);
		addChild(_rightPanel);

		visible = false;

		// Añadir directamente al stage (no a DataInfoUI) para posicionamiento libre
		openfl.Lib.current.stage.addChild(this);

		addEventListener(Event.ENTER_FRAME, _onFrame);
	}

	// ── Toggle ────────────────────────────────────────────────────────────────

	public function toggle():Void
	{
		shown = !shown;
		visible = shown;
	}

	// ── Frame loop ────────────────────────────────────────────────────────────

	private function _onFrame(_:Event):Void
	{
		if (!shown)
			return;

		var stageW:Float = openfl.Lib.current.stage.stageWidth;

		var fpsBottom:Float = 10;

		if (_fpsRef != null)
		{
			if (_fpsRef.parent != null)
			{
				// Casteamos el padre para acceder a sus variables (systemPanel, statsPanel)
				var parentUI:DataInfoUI = cast(_fpsRef.parent, DataInfoUI);

				// Partimos de la Y base de DataInfoUI
				fpsBottom = parentUI.y;

				if (parentUI.systemPanel.visible)
				{
					// Si F3 (System/Stats) está expandido, bajamos hasta debajo de las stats
					fpsBottom += parentUI.statsPanel.y + StatsPanel.HEIGHT + 4;
				}
				else
				{
					// Si F3 está cerrado, solo contamos FPS y Developer Mode
					fpsBottom += _fpsRef.y + _fpsRef.height;

					if (mods.ModManager.developerMode)
					{
						fpsBottom += 18; // Altura del _devLabel
					}

					fpsBottom += 4; // Padding final del fondo negro
				}
			}
			else
			{
				fpsBottom = 50;
			}
		}

		// Panel izquierdo — debajo del FPS counter
		_leftPanel.x = 10;
		_leftPanel.y = fpsBottom;

		// Panel derecho — esquina superior derecha, alineado a la misma Y
		_rightPanel.x = stageW - _rightPanel.panelW - 10;
		_rightPanel.y = fpsBottom;

		// Añadir sample de FPS al ring (cada frame)
		var curFps:Int = _fpsRef != null ? _fpsRef.currentFPS : 0;
		_fpsRing[_fpsRingHead] = curFps;
		_fpsRingHead = (_fpsRingHead + 1) % GRAPH_SAMPLES;

		// Redibujar gráfica cada frame
		_drawGraph();

		// Actualizar textos con throttle
		_textElapsed += FlxG.elapsed;
		if (_textElapsed >= TEXT_INTERVAL)
		{
			_textElapsed = 0;
			_refreshLeft();
			_refreshRight();
		}

		// Redimensionar paneles al contenido real
		var leftH:Float = GRAPH_H + 8 + _leftPanel.label.textHeight + 10;
		var rightH:Float = _rightPanel.label.textHeight + 12;
		_leftPanel.resize(_leftPanel.panelW, leftH);
		_rightPanel.resize(_rightPanel.panelW, rightH);
	}

	// ── Gráfica de FPS ────────────────────────────────────────────────────────

	private function _drawGraph():Void
	{
		var g = _graph.graphics;
		var targetFps:Int = FlxG.drawFramerate > 0 ? FlxG.drawFramerate : 60;
		var barW:Float = GRAPH_W / GRAPH_SAMPLES;
		var maxH:Float = GRAPH_H - 2;

		g.clear();

		// Fondo
		g.beginFill(0x111111, 0.85);
		g.drawRect(0, 0, GRAPH_W, GRAPH_H);
		g.endFill();

		// Línea de referencia: target FPS (100%)
		g.lineStyle(0.5, 0x335533, 0.9);
		g.moveTo(0, 1);
		g.lineTo(GRAPH_W, 1);
		g.lineStyle();

		// Línea de 30fps (50%)
		var halfY:Float = GRAPH_H - (30.0 / targetFps) * maxH;
		g.lineStyle(0.5, 0x553300, 0.7);
		g.moveTo(0, halfY);
		g.lineTo(GRAPH_W, halfY);
		g.lineStyle();

		// Barras
		for (i in 0...GRAPH_SAMPLES)
		{
			var idx:Int = (_fpsRingHead + i) % GRAPH_SAMPLES;
			var fps:Int = _fpsRing[idx];
			if (fps <= 0)
				continue;

			var ratio:Float = Math.min(fps / targetFps, 1.5);
			var bh:Float = Math.max(1.0, ratio * maxH);
			var bx:Float = i * barW;
			var by:Float = GRAPH_H - bh;

			var col:Int;
			if (ratio >= 0.95)
				col = 0x00EE55;
			else if (ratio >= 0.65)
				col = 0xFFCC00;
			else if (ratio >= 0.40)
				col = 0xFF7700;
			else
				col = 0xFF2222;

			g.beginFill(col, 0.90);
			g.drawRect(bx, by, Math.max(1.0, barW - 0.5), bh);
			g.endFill();
		}

		_graph.x = 5;
		_graph.y = 4;
	}

	// ── Texto panel izquierdo ─────────────────────────────────────────────────

	private function _refreshLeft():Void
	{
		var lines:Array<String> = [];

		// Estado actual
		var stateName = 'Unknown';
		try
		{
			stateName = Type.getClassName(Type.getClass(FlxG.state));
		}
		catch (_:Dynamic)
		{
		}
		var dot = stateName.lastIndexOf('.');
		if (dot >= 0)
			stateName = stateName.substr(dot + 1);
		lines.push('State: $stateName');

		// Info de gameplay (solo en PlayState)
		var ps:funkin.gameplay.PlayState = null;
		try
		{
			ps = cast(FlxG.state, funkin.gameplay.PlayState);
		}
		catch (_:Dynamic)
		{
		}

		if (ps != null)
		{
			var pos:Float = funkin.data.Conductor.songPosition;
			var step:Int = Reflect.field(ps, 'curStep') ?? 0;
			var beat:Int = Reflect.field(ps, 'curBeat') ?? 0;
			var bpm:Float = funkin.data.Conductor.bpm;
			var crochet:Float = funkin.data.Conductor.crochet;

			var posStr = (pos < 0 ? '-' : '') + Std.int(Math.abs(pos)) + 'ms';
			lines.push('Song pos: $posStr   Step: $step   Beat: $beat');
			lines.push('BPM: ${Std.int(bpm)}   Crochet: ${Std.int(crochet)}ms');

			if (ps.cameraController != null)
			{
				var cc = ps.cameraController;
				var cf = cc.camFollow;
				var lck = cc.locked ? ' [LOCKED]' : '';
				lines.push('CamFollow: (${Std.int(cf.x)}, ${Std.int(cf.y)})');
				lines.push('Target: ${cc.currentTarget}$lck');
			}
		}
		else
		{
			lines.push('(no gameplay active)');
		}

		_leftPanel.label.x = 5;
		_leftPanel.label.y = GRAPH_H + 10;
		_leftPanel.setLines(lines);
	}

	// ── Texto panel derecho ───────────────────────────────────────────────────

	private function _refreshRight():Void
	{
		var lines:Array<String> = [];

		// VRAM — usada / total + barra ASCII de progreso
		var vramLine:String;
		if (SystemInfo.initialized && SystemInfo.vRAMTotalKB > 0)
		{
			var totalKB  = SystemInfo.vRAMTotalKB;
			var usedKB   = SystemInfo.getVRAMUsedKB();
			var totalMB  = Math.round(totalKB  / 1024);
			if (usedKB >= 0)
			{
				var usedMB  = Math.round(usedKB  / 1024);
				var pct     = Math.min(1.0, usedKB / totalKB);
				var pctInt  = Math.round(pct * 100);
				var filled  = Math.round(pct * 10);
				var bar     = '[' + StringTools.rpad('', '█', filled)
				            + StringTools.rpad('', '░', 10 - filled) + ']';
				var warn    = pct >= 0.90 ? ' !!' : (pct >= 0.75 ? ' !' : '');
				vramLine = 'VRAM: ${usedMB} / ${totalMB} MB  (${pctInt}%) $bar$warn';
			}
			else
			{
				vramLine = 'VRAM: ${totalMB} MB total  (live use N/A)';
			}
		}
		else
		{
			var fallback = (SystemInfo.initialized && SystemInfo.vRAM != 'Unknown')
				? SystemInfo.vRAM : 'N/A';
			vramLine = 'VRAM: $fallback';
		}
		lines.push(vramLine);

		// Texturas en caché
		if (funkin.cache.FunkinCache.instance != null)
		{
			var st = funkin.cache.FunkinCache.instance.getStats();
			// Extraer fragmento legible: "N bmp / N snd / N fnt"
			var r = ~/CURRENT: (\d+ bmp \/ \d+ snd \/ \d+ fnt)/;
			lines.push('Cache: ' + (r.match(st) ? r.matched(1) : 'see trace'));
		}
		else
		{
			lines.push('Cache: N/A');
		}

		// Cámaras y objetos
		var camCount = FlxG.cameras.list != null ? FlxG.cameras.list.length : 0;
		lines.push('Cameras: $camCount');

		var objCount = 0;
		try
		{
			if (FlxG.state != null && FlxG.state.members != null)
				objCount = FlxG.state.members.length;
		}
		catch (_:Dynamic)
		{
		}
		lines.push('State members: $objCount');

		// Info de cámara del PlayState
		var ps:funkin.gameplay.PlayState = null;
		try
		{
			ps = cast(FlxG.state, funkin.gameplay.PlayState);
		}
		catch (_:Dynamic)
		{
		}

		if (ps != null && ps.cameraController != null)
		{
			var cc = ps.cameraController;
			var cg = cc.camGame;
			var ch = cc.camHUD;
			if (cg != null)
			{
				lines.push('CamGame zoom: ${_fmt(cg.zoom)} / ${_fmt(cc.defaultZoom)}');
				lines.push('CamGame scroll: (${Std.int(cg.scroll.x)}, ${Std.int(cg.scroll.y)})');
			}
			if (ch != null)
				lines.push('CamHUD zoom: ${_fmt(ch.zoom)}');
		}

		// Scripts activos
		var hxCount = 0;
		var luaCount = 0;
		try
		{
			var sh = funkin.scripting.ScriptHandler;
			for (_ in sh.globalScripts)
				hxCount++;
			for (_ in sh.stageScripts)
				hxCount++;
			for (_ in sh.songScripts)
				hxCount++;
			for (_ in sh.uiScripts)
				hxCount++;
			for (_ in sh.charScripts)
				hxCount++;
			luaCount = 0;
			#if (LUA_ALLOWED && linc_luajit)
			luaCount = sh.globalLuaScripts.length
				+ sh.stageLuaScripts.length
				+ sh.songLuaScripts.length
				+ sh.uiLuaScripts.length
				+ sh.charLuaScripts.length;
			#end
		}
		catch (_:Dynamic)
		{
		}
		lines.push('Scripts: HScript×$hxCount   Lua×$luaCount');

		// Mod activo, versión de Script API y estado de Developer Mode
		var modId = mods.ModManager.activeMod ?? '(none)';
		var devStr = mods.ModManager.developerMode ? ' [DEV MODE]' : '';
		lines.push('Mod: $modId$devStr');
		lines.push('Script API: v6.0.0');

		_rightPanel.label.x = 6;
		_rightPanel.label.y = 6;
		_rightPanel.setLines(lines);
	}

	// ── Util ──────────────────────────────────────────────────────────────────

	private static function _fmt(v:Float):String
		return Std.string(Math.round(v * 1000) / 1000);
}

// ─────────────────────────────────────────────────────────────────────────────
// DebugPanel — sprite con fondo + TextField reusable
// ─────────────────────────────────────────────────────────────────────────────

class DebugPanel extends Sprite
{
	public var panelW(default, null):Float;

	private var _panelH:Float;
	private var _bg:Shape;

	public var label:TextField;

	private var _bgAlpha:Float;
	private var _bgColor:Int;

	public function new(w:Float, h:Float, bgColor:Int = 0x000000, bgAlpha:Float = 0.72)
	{
		super();

		panelW = w;
		_panelH = h;
		_bgColor = bgColor;
		_bgAlpha = bgAlpha;

		_bg = new Shape();
		_drawBG(w, h);
		addChild(_bg);

		label = new TextField();
		label.selectable = false;
		label.mouseEnabled = false;
		label.defaultTextFormat = new TextFormat('_sans', 10, 0xEEEEEE);
		label.multiline = true;
		label.wordWrap = false;
		label.autoSize = openfl.text.TextFieldAutoSize.LEFT;
		label.x = 6;
		label.y = 5;
		addChild(label);
	}

	public function setLines(lines:Array<String>):Void
		label.text = lines.join('\n');

	public function resize(w:Float, h:Float):Void
	{
		if (Math.abs(w - panelW) < 1 && Math.abs(h - _panelH) < 1)
			return;
		panelW = w;
		_panelH = h;
		_drawBG(w, h);
	}

	private function _drawBG(w:Float, h:Float):Void
	{
		_bg.graphics.clear();
		_bg.graphics.beginFill(_bgColor, _bgAlpha);
		_bg.graphics.drawRoundRect(0, 0, w, h, 5);
		_bg.graphics.endFill();
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// SystemPanel — info estática del hardware
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Muestra OS / CPU / GPU / VRAM / RAM total.
 * El contenido se carga una sola vez (los datos no cambian en runtime).
 */
class SystemPanel extends TextField
{
	public static inline var HEIGHT:Int = 76;

	public function new(x:Float, y:Float)
	{
		super();

		this.x = x + 4;
		this.y = y;
		this.width = 210;
		this.height = HEIGHT;
		this.selectable = false;
		this.mouseEnabled = false;
		this.defaultTextFormat = new TextFormat("_sans", 9, 0xAADDFF);
		this.multiline = true;
		this.wordWrap = false;

		if (SystemInfo.initialized)
			_fill();
		else
			this.text = "System Info loading...";

		addEventListener(Event.ENTER_FRAME, _onEnter);
	}

	private var _filled:Bool = false;

	private function _onEnter(_):Void
	{
		if (!_filled && SystemInfo.initialized)
		{
			_fill();
			_filled = true;
			removeEventListener(Event.ENTER_FRAME, _onEnter);
		}
	}

	private function _fill():Void
	{
		var lines:Array<String> = [];

		if (SystemInfo.osName != "Unknown")
			lines.push('OS:  ${SystemInfo.osName}');
		if (SystemInfo.cpuName != "Unknown")
			lines.push('CPU: ${SystemInfo.cpuName}');

		var gpuLine = '';
		if (SystemInfo.gpuName != "Unknown")
			gpuLine += 'GPU: ${SystemInfo.gpuName}';
		if (gpuLine.length > 0)
			lines.push(gpuLine);
		// VRAM total (estático, detectado al inicio)
		if (SystemInfo.vRAMTotalKB > 0)
		{
			var totalMB = Math.round(SystemInfo.vRAMTotalKB / 1024);
			lines.push('    VRAM: ${totalMB} MB total  (F1 for live use)');
		}
		else if (SystemInfo.vRAM != "Unknown")
		{
			lines.push('    VRAM: ${SystemInfo.vRAM}');
		}

		if (SystemInfo.gpuMaxTextureSize != "Unknown")
			lines.push('    Max tex: ${SystemInfo.gpuMaxTextureSize}');

		var ramLine = '';
		if (SystemInfo.totalRAM != "Unknown")
			ramLine = 'RAM: ${SystemInfo.totalRAM}';
		if (SystemInfo.ramType.length > 0)
			ramLine += '  ${SystemInfo.ramType}';
		if (ramLine.length > 0)
			lines.push(ramLine);

		if (lines.length == 0)
			lines.push("(System info not available)");
		this.text = lines.join("\n");
		_filled = true;
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// StatsPanel — stats de rendimiento dinámicas (actualizadas cada 0.5s)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Muestra: resolución de ventana, modo de escala, draw calls, cache, audio config.
 */
class StatsPanel extends TextField
{
	public static inline var HEIGHT:Int = 72;
	private static inline var UPDATE_INTERVAL:Float = 0.5;

	private var _elapsed:Float = 0;

	public function new(x:Float, y:Float)
	{
		super();

		this.x = x + 4;
		this.y = y;
		this.width = 210;
		this.height = HEIGHT;
		this.selectable = false;
		this.mouseEnabled = false;
		this.defaultTextFormat = new TextFormat(openfl.utils.Assets.getFont(Paths.font("Funkin.otf")).fontName, 16, 0xFFFFFF);
		this.multiline = true;
		this.wordWrap = false;
		this.text = "Stats loading...";

		addEventListener(Event.ENTER_FRAME, _onEnter);
	}

	private function _onEnter(e:Event):Void
	{
		_elapsed += FlxG.elapsed;
		if (_elapsed < UPDATE_INTERVAL)
			return;
		_elapsed = 0;
		_refresh();
	}

	private function _refresh():Void
	{
		var lines:Array<String> = [];

		var ww = WindowManager.windowWidth;
		var wh = WindowManager.windowHeight;
		var mode = WindowManager.scaleMode;
		lines.push('Win: ${ww}×${wh}  Scale: $mode${WindowManager.isFullscreen ? " [FS]" : ""}');

		lines.push('Game: ${FlxG.width}×${FlxG.height} | FPS target: ${FlxG.updateFramerate}');

		var drawCalls = 0;
		var sprites = 0;
		var culled = 0;
		try
		{
			var ps = cast(FlxG.state, funkin.gameplay.PlayState);
			if (ps?.optimizationManager?.gpuRenderer != null)
			{
				drawCalls = ps.optimizationManager.gpuRenderer.drawCalls;
				sprites = ps.optimizationManager.gpuRenderer.spritesRendered;
				culled = ps.optimizationManager.gpuRenderer.spritesCulled;
			}
		}
		catch (_:Dynamic)
		{
		}

		lines.push('GPU: DC=$drawCalls  Spr=$sprites  Cull=$culled');

		#if cpp
		var usedMB = Math.round(cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE) / (1024 * 1024));
		var peakMB = Math.round(cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_RESERVED) / (1024 * 1024));
		#else
		var usedMB = Math.round(openfl.system.System.totalMemory / (1024 * 1024));
		var peakMB = usedMB;
		#end
		var gcPaused = funkin.system.MemoryUtil.disableCount > 0;
		lines.push('Mem: ${usedMB}/${peakMB} MB | GC: ${gcPaused ? "paused" : "active"}');

		if (AudioConfig.loaded)
			lines.push('Audio: ${AudioConfig.debugString()}');
		else
			lines.push('Audio: default config');

		lines.push('Cache: ${Paths.cacheDebugString()}');

		this.text = lines.join("\n");
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// GPUStatsText — alias legacy
// ─────────────────────────────────────────────────────────────────────────────

@:deprecated("Use StatsPanel. GPUStatsText will remain as an empty alias.")
class GPUStatsText extends TextField
{
	public static function getSaveData():Dynamic
	{
		if (FlxG.save != null && FlxG.save.data != null)
			return FlxG.save.data;
		return null;
	}

	public function new(x:Float, y:Float)
	{
		super();
		this.x = x;
		this.y = y;
		this.selectable = false;
		this.mouseEnabled = false;
		this.width = 10;
		this.height = 10;
		this.visible = false;
	}

	/** @deprecated No-op. */
	public function updateStats():Void
	{
	}
}
