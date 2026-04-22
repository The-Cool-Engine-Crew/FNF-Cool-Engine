package funkin.debug;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxSubState;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import funkin.gameplay.PlayState;
import funkin.gameplay.modchart.ModChartEditorState;
import funkin.gameplay.modchart.ModChartManager;
import funkin.data.Song.SwagSong;
import funkin.menus.FreeplayState.SongMetadata;
import funkin.transitions.StateTransition;
import funkin.debug.editors.FreeplayEditorState;
import funkin.debug.charting.ChartingState;
import funkin.debug.editors.StageEditor;
import funkin.debug.editors.DialogueEditor;
import funkin.debug.editors.CutsceneEditorState;
import funkin.debug.editors.GameplayEditorState;
import funkin.data.Song;
import funkin.data.CoolUtil;
import haxe.Json;
import sys.io.File;
import sys.FileSystem;

/**
 * Submenú que aparece al presionar Enter sobre una canción en FreeplayEditorState.
 * Permite elegir qué editor de debug abrir sin pasar por PlayState.
 *
 * Opciones:
 *  0 — Edit Song Data       (comportamiento original)
 *  1 — Chart Editor
 *  2 — Stage Editor
 *  3 — Dialogue Editor
 *  4 — Cutscene Editor      ← NUEVO
 *  5 — ModChart Editor
 *  6 — PlayState Editor
 */
class DebugMenuSubState extends FlxSubState
{
	static var OPTIONS:Array<String> = [
		"✎  EDIT SONG DATA",
		"♪  CHART EDITOR",
		"⬡  STAGE EDITOR",
		"✦  DIALOGUE EDITOR",
		"✂  CUTSCENE EDITOR",
		"◈  MODCHART EDITOR",
		"▶  PLAYSTATE EDITOR"
	];

	static var DESCRIPTIONS:Array<String> = [
		"Edit song metadata, BPM, characters and stages",
		"Create and edit the note chart for this song",
		"Build and arrange stage elements and backgrounds",
		"Write branching dialogue cutscenes",
		"Create sprite cutscenes (atlas / animate / rect) with timeline",
		"Script note modifiers and visual effects (ModCharts)",
		"Preview stage, HUD, characters — add events & scripts in real-time"
	];

	static var ACCENT_COLORS:Array<Int> = [
		0xFFFFCC00,
		0xFF00D9FF,
		0xFFFF8844,
		0xFFCC44FF,
		0xFF00E5FF,   // ← Cutscene Editor (cyan)
		0xFF44FF88,
		0xFFFF4488,
	];

	var songData:SongMetadata;
	var songName:String;

	var bg          :FlxSprite;
	var panel       :FlxSprite;
	var accentBar   :FlxSprite;
	var titleText   :FlxText;
	var optionTexts :Array<FlxText> = [];
	var cursor      :FlxSprite;
	var descBg      :FlxSprite;
	var descText    :FlxText;

	var curSelected:Int = 0;

	static inline var COLOR_BG      :Int = 0xAA000000;
	static inline var COLOR_PANEL   :Int = 0xFF14142A;
	static inline var COLOR_NORMAL  :Int = 0xFFBBBBCC;
	static inline var COLOR_TITLE   :Int = 0xFFFFFFFF;
	static inline var PANEL_W       :Int = 560;
	static inline var OPTION_H      :Int = 46;
	static inline var PADDING_TOP   :Int = 62;
	static inline var PADDING_SIDE  :Int = 28;

	public function new(song:SongMetadata)
	{
		super(0x00000000);
		songData = song;
		songName = song.songName;
	}

	override function create():Void
	{
		var panelH = PADDING_TOP + OPTIONS.length * OPTION_H + 86;
		var panelX = (FlxG.width  - PANEL_W) / 2;
		var panelY = (FlxG.height - panelH)  / 2;

		bg = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, COLOR_BG);
		bg.scrollFactor.set(); bg.alpha = 0; add(bg);

		panel = new FlxSprite(panelX, panelY).makeGraphic(PANEL_W, panelH, COLOR_PANEL);
		panel.scrollFactor.set(); add(panel);

		accentBar = new FlxSprite(panelX, panelY).makeGraphic(PANEL_W, 4, ACCENT_COLORS[0]);
		accentBar.scrollFactor.set(); add(accentBar);

		var borderL = new FlxSprite(panelX, panelY).makeGraphic(1, panelH, 0xFF00D9FF);
		borderL.scrollFactor.set(); borderL.alpha = 0.12; add(borderL);
		var borderR = new FlxSprite(panelX + PANEL_W - 1, panelY).makeGraphic(1, panelH, 0xFF00D9FF);
		borderR.scrollFactor.set(); borderR.alpha = 0.12; add(borderR);

		titleText = new FlxText(panelX, panelY + 14, PANEL_W,
			'OPEN EDITOR  —  ${songName.toUpperCase()}', 18);
		titleText.setFormat(Paths.font('vcr.ttf'), 18, COLOR_TITLE, CENTER,
			FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		titleText.scrollFactor.set(); add(titleText);

		var sep = new FlxSprite(panelX + 20, panelY + 52).makeGraphic(PANEL_W - 40, 1, 0xFF333355);
		sep.scrollFactor.set(); add(sep);

		cursor = new FlxSprite(panelX + 10, panelY + PADDING_TOP + 6);
		cursor.makeGraphic(5, OPTION_H - 12, 0xFF00D9FF);
		cursor.scrollFactor.set(); add(cursor);

		for (i in 0...OPTIONS.length)
		{
			var optY = panelY + PADDING_TOP + i * OPTION_H;

			var txt = new FlxText(panelX + PADDING_SIDE, optY + 9, PANEL_W - PADDING_SIDE * 2 - 40, OPTIONS[i], 18);
			txt.setFormat(Paths.font('vcr.ttf'), 18, COLOR_NORMAL, LEFT,
				FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			txt.scrollFactor.set(); add(txt);
			optionTexts.push(txt);

			var numTxt = new FlxText(panelX + PANEL_W - PADDING_SIDE - 28, optY + 11, 28, Std.string(i + 1), 13);
			numTxt.setFormat(Paths.font('vcr.ttf'), 13, 0xFF333355, RIGHT);
			numTxt.scrollFactor.set(); add(numTxt);

			if (i < OPTIONS.length - 1)
			{
				var rowSep = new FlxSprite(panelX + PADDING_SIDE, optY + OPTION_H - 1).makeGraphic(PANEL_W - PADDING_SIDE * 2, 1, 0xFF1E1E3A);
				rowSep.scrollFactor.set(); add(rowSep);
			}
		}

		var descY = panelY + PADDING_TOP + OPTIONS.length * OPTION_H + 8;
		descBg = new FlxSprite(panelX, descY).makeGraphic(PANEL_W, 44, 0xFF0D0D1E);
		descBg.scrollFactor.set(); add(descBg);

		descText = new FlxText(panelX + PADDING_SIDE, descY + 8, PANEL_W - PADDING_SIDE * 2, DESCRIPTIONS[0], 11);
		descText.setFormat(Paths.font('vcr.ttf'), 11, 0xFF8888AA, LEFT);
		descText.scrollFactor.set(); add(descText);

		var hint = new FlxText(panelX, descY + 52, PANEL_W,
			'↑↓ Navigate    ENTER Open    1-7 Quick Select    ESC Close', 11);
		hint.setFormat(Paths.font('vcr.ttf'), 11, 0xFF444466, CENTER);
		hint.scrollFactor.set(); add(hint);

		panel.alpha  = 0;
		cursor.alpha = 0;
		for (t in optionTexts) t.alpha = 0;

		FlxTween.tween(bg,     {alpha: 1}, 0.18, {ease: FlxEase.quadOut});
		FlxTween.tween(panel,  {alpha: 1}, 0.22, {ease: FlxEase.quadOut});
		FlxTween.tween(cursor, {alpha: 1}, 0.28, {ease: FlxEase.quadOut, startDelay: 0.05});
		for (i in 0...optionTexts.length)
			FlxTween.tween(optionTexts[i], {alpha: 1}, 0.2,
				{ease: FlxEase.quadOut, startDelay: 0.03 * (i + 1)});

		updateSelection();
		super.create();
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (FlxG.keys.justPressed.UP   || FlxG.keys.justPressed.W) changeSelection(-1);
		if (FlxG.keys.justPressed.DOWN || FlxG.keys.justPressed.S) changeSelection(1);

		var numKeys = [
			FlxG.keys.justPressed.ONE,   FlxG.keys.justPressed.TWO,
			FlxG.keys.justPressed.THREE, FlxG.keys.justPressed.FOUR,
			FlxG.keys.justPressed.FIVE,  FlxG.keys.justPressed.SIX,
			FlxG.keys.justPressed.SEVEN,
		];
		for (i in 0...numKeys.length)
		{
			if (numKeys[i] && i < OPTIONS.length)
			{
				curSelected = i;
				updateSelection();
				confirmSelection();
				return;
			}
		}

		if (FlxG.keys.justPressed.ENTER) confirmSelection();

		if (FlxG.keys.justPressed.ESCAPE)
		{
			FlxG.sound.play(Paths.sound('menus/cancelMenu'));
			close();
		}
	}

	function changeSelection(dir:Int):Void
	{
		curSelected = (curSelected + dir + OPTIONS.length) % OPTIONS.length;
		FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.4);
		updateSelection();
	}

	function updateSelection():Void
	{
		for (i in 0...optionTexts.length)
		{
			var sel = (i == curSelected);
			optionTexts[i].color = sel ? FlxColor.fromInt(ACCENT_COLORS[i]) : FlxColor.fromInt(COLOR_NORMAL);
			optionTexts[i].scale.set(sel ? 1.04 : 1.0, sel ? 1.04 : 1.0);
		}

		var targetY = optionTexts[curSelected].y + (optionTexts[curSelected].height - cursor.height) / 2;
		FlxTween.cancelTweensOf(cursor);
		FlxTween.tween(cursor, {y: targetY}, 0.10, {ease: FlxEase.expoOut});

		if (accentBar != null)
			accentBar.makeGraphic(PANEL_W, 4, ACCENT_COLORS[curSelected]);

		if (descText != null)
		{
			descText.text  = DESCRIPTIONS[curSelected];
			descText.color = _blendColor(ACCENT_COLORS[curSelected], 0xFFFFFFFF, 0.35);
		}
	}

	function confirmSelection():Void
	{
		FlxG.sound.play(Paths.sound('menus/confirmMenu'), 0.7);
		switch (curSelected)
		{
			case 0: FreeplayEditorState.pendingAction = 1; close();
			case 1: _openEditor(CHART_EDITOR);
			case 2: _openEditor(STAGE_EDITOR);
			case 3: _openEditor(DIALOGUE_EDITOR);
			case 4: _openEditor(CUTSCENE_EDITOR);
			case 5: _openEditor(MODCHART_EDITOR);
			case 6: _openEditor(PLAYSTATE_EDITOR);
		}
	}

	function _openEditor(type:DebugEditorType):Void
	{
		PlayState.SONG = _loadSongFromDisk(songData.songName.toLowerCase());
		switch (type)
		{
			case CHART_EDITOR:      StateTransition.switchState(new ChartingState());
			case STAGE_EDITOR:      StateTransition.switchState(new StageEditor());
			case DIALOGUE_EDITOR:   StateTransition.switchState(new DialogueEditor());
			case CUTSCENE_EDITOR:   StateTransition.switchState(new CutsceneEditorState());
			case MODCHART_EDITOR:   StateTransition.switchState(new ModChartEditorState());
			case PLAYSTATE_EDITOR:  StateTransition.switchState(new GameplayEditorState(songData));
		}
	}

	function _loadSongFromDisk(songName:String):SwagSong
	{
		final diffSuffix = CoolUtil.difficultySuffix();
		final diffInput  = (diffSuffix == '' || diffSuffix == null)
		                   ? songName
		                   : songName + diffSuffix;
		try
		{
			final song = Song.loadFromJson(diffInput, songName);
			if (song != null)
			{
				trace('[DebugMenuSubState] Chart cargado: $songName diff=$diffSuffix');
				return song;
			}
		}
		catch (e:Dynamic)
		{
			trace('[DebugMenuSubState] loadFromJson error for "$songName": $e');
		}

		trace('[DebugMenuSubState] Fallback vacío para "$songName"');
		return cast {
			song: songName, notes: [], events: [], characters: [], strumsGroups: [],
			bpm: 120, speed: 2, needsVoices: true, stage: 'stage_week1',
			player1: 'bf', player2: 'dad', gfVersion: 'gf', validScore: false
		};
	}

	/** Linear blend from color `a` toward color `b` by `t` (0=a, 1=b). */
	static function _blendColor(a:Int, b:Int, t:Float):Int
	{
		final ar = (a >> 16) & 0xFF; final ag = (a >> 8) & 0xFF; final ab = a & 0xFF;
		final br = (b >> 16) & 0xFF; final bg = (b >> 8) & 0xFF; final bb = b & 0xFF;
		final r = Std.int(ar + (br - ar) * t);
		final g = Std.int(ag + (bg - ag) * t);
		final bl= Std.int(ab + (bb - ab) * t);
		return 0xFF000000 | (r << 16) | (g << 8) | bl;
	}
}

enum DebugEditorType
{
	CHART_EDITOR;
	STAGE_EDITOR;
	DIALOGUE_EDITOR;
	CUTSCENE_EDITOR;
	MODCHART_EDITOR;
	PLAYSTATE_EDITOR;
}
