package funkin.debug.editors;

import funkin.debug.EditorDialogs.UnsavedChangesDialog;
import coolui.CoolInputText;
import coolui.CoolNumericStepper;
import coolui.CoolCheckBox;
import coolui.CoolDropDown;
import coolui.CoolTabMenu;
import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.text.FlxText;
import coolui.CoolButton;
import flixel.util.FlxColor;
import funkin.gameplay.objects.character.Character;
import funkin.gameplay.objects.stages.Stage;
import funkin.gameplay.objects.stages.Stage.StageAnimation;
import funkin.gameplay.objects.stages.Stage.StageData;
import funkin.gameplay.objects.stages.Stage.StageElement;
import funkin.gameplay.PlayState;
import funkin.transitions.StateTransition;
import haxe.Json;
import mods.ModManager;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import openfl.net.FileReference;
#if sys
import sys.FileSystem;
import sys.io.File;
#end
import funkin.debug.themes.EditorTheme;
import funkin.debug.themes.ThemePickerSubState;
import funkin.graphics.shaders.ShaderManager;

using StringTools;

// ── Private helpers ───────────────────────────────────────────────────────────

/** Data stored per visible layer row for click detection. */
private typedef LayerHit =
{
	x:Float, // left edge of clickable zone (screen coords)
	w:Int, // width of clickable zone
	y:Float,
	h:Int, // height of clickable zone
	idx:Int, // element index in stageData.elements (-1 = char row)
	charId:String, // "bf" | "gf" | "dad" | null
	zone:String // "row" | "eye" | "up" | "down" | "del" | "lock" | "char" | "charup" | "chardown" | "add_element"
}

/** Simple fixed-size button for the toolbar / layer panel. */
private class MiniBtn extends FlxSprite
{
	public var label:FlxText;
	public var onClick:Void->Void;

	public function new(x:Float, y:Float, w:Int, h:Int, txt:String, color:Int, txtColor:Int, ?cb:Void->Void)
	{
		super(x, y);
		makeGraphic(w, h, color);
		onClick = cb;
		label = new FlxText(x, y, w, txt, 11);
		label.setFormat(Paths.font('vcr.ttf'), 11, txtColor, CENTER);
		label.scrollFactor.set();
	}
}

// ─────────────────────────────────────────────────────────────────────────────
//  StageEditor
// ─────────────────────────────────────────────────────────────────────────────

class StageEditor extends funkin.states.MusicBeatState
{
	// ── Layout constants ──────────────────────────────────────────────────────
	static inline final TITLE_H:Int = 34;
	static inline final TOOLBAR_H:Int = 40;
	static inline final TOP_H:Int = TITLE_H + TOOLBAR_H;
	static inline final STATUS_H:Int = 24;
	static inline final LEFT_W:Int = 252;
	static inline final RIGHT_W:Int = 282;
	static inline final ROW_H:Int = 26;
	static inline final ANIM_ROW_H:Int = 22;
	static inline final MAX_VISIBLE_LAYERS:Int = 18;

	// ── Cameras ───────────────────────────────────────────────────────────────
	var camGame:FlxCamera;
	var camHUD:FlxCamera;
	var camUI:FlxCamera; // cámara invisible en cameras[0]: zoom siempre 1 → coolui.CoolUIGroup calcula bien los clicks
	var camZoom:Float = 0.75;
	var camTargetX:Float = 0;
	var camTargetY:Float = 0;

	// ── Editor state ──────────────────────────────────────────────────────────
	var stageData:StageData;
	var currentFilePath:String = '';
	var hasUnsavedChanges:Bool = false;
	var _unsavedDlg:UnsavedChangesDialog = null;
	var _windowCloseFn:Void->Void = null;
	/** True once stageData has been populated from disk or from loadJSON.
	 *  When true, reloadStageView uses __fromData__ (in-memory) instead of disk. */
	var _stageDataReady:Bool = false;

	var selectedIdx:Int = -1;
	var selectedCharId:String = null;
	/** All currently selected element indices (multi-select via Shift / Ctrl). */
	var selectedIndices:Array<Int> = [];
	var history:Array<String> = [];
	var historyIndex:Int = -1;
	var clipboard:Dynamic = null;
	var layerScrollStart:Int = 0;
	var animSelIdx:Int = 0;

	// ── Canvas objects (camGame) ──────────────────────────────────────────────
	var stage:Stage;
	var elementSprites:Map<String, FlxSprite> = new Map();

	/** Group containing aboveChars:true sprites — rendered ABOVE characters. */
	var stageAboveGroup:FlxTypedGroup<FlxBasic>;

	var charGroup:FlxTypedGroup<Character>;
	var characters:Map<String, Character> = new Map();
	var gridSprite:FlxSprite;
	var selBox:FlxSprite;
	/** Malla (checkerboard) superpuesta al sprite seleccionado para diferenciarlo mejor */
	var selMesh:FlxSprite;
	var charLabels:FlxTypedGroup<FlxText>;

	/** Cached selection-box pixel dimensions – avoids rebuilding BitmapData every frame. */
	var _selBoxW:Int = 0;
	var _selMeshW:Int = 0;

	var _selBoxH:Int = 0;
	var _selMeshH:Int = 0;

	/** Tooltip que aparece sobre el mouse al hacer hover en elementos/personajes */
	var hoverTooltipBg:FlxSprite;
	var hoverTooltipTxt:FlxText;
	var _hoverName:String = '';
	/** Cached tooltip dimensions — avoids makeGraphic every frame. */
	var _tooltipW:Int = 0;
	var _tooltipH:Int = 0;

	// ── HUD: title + toolbar + status ────────────────────────────────────────
	var titleText:FlxText;
	var unsavedDot:FlxText;
	var statusText:FlxText;
	var coordText:FlxText;
	var zoomText:FlxText;
	var modBadge:FlxText;

	// ── HUD: left panel (layer list) ─────────────────────────────────────────
	var layerPanelBg:FlxSprite;
	var layerRowsGroup:FlxTypedGroup<FlxSprite>;
	var layerTextsGroup:FlxTypedGroup<FlxText>;
	var layerHitData:Array<LayerHit> = [];
	var layerHoverIdx:Int = -1;
	/** Maps element index → its row-background FlxSprite so hover can recolor without full rebuild. */
	var _layerRowBgMap:Map<Int, FlxSprite> = new Map();
	/** Maps element index → all FlxText labels on that row, so they can be hidden during drag. */
	var _layerRowTextsMap:Map<Int, Array<FlxText>> = new Map();

	// ── HUD: right panel (CoolTabMenu) ──────────────────────────────────────
	var rightPanel:CoolTabMenu;

	// ── HUD: context panel (shown when an element / char is selected) ─────────
	/** Replaces rightPanel when something is selected — shows only type-specific props. */
	var _contextPanel:CoolTabMenu;
	var _contextPanelBg:FlxSprite;

	/** Background and border of the right panel area — hidden in VIEW mode. */
	var _rightPanelBg:FlxSprite;
	var _rightPanelBorder:FlxSprite;

	/** X position of right panels when visible (EDIT mode). */
	var _rightPanelEditX:Float = 0;
	/** X position of right panels when hidden (VIEW mode) — off-screen to the right. */
	static inline final RIGHT_PANEL_HIDE_X:Float = 99999;

	// Element tab widgets
	var elemNameInput:CoolInputText;
	var elemAssetInput:CoolInputText;
	var elemTypeDropdown:CoolDropDown;
	var elemXStepper:CoolNumericStepper;
	var elemYStepper:CoolNumericStepper;
	var elemScaleXStepper:CoolNumericStepper;
	var elemScaleYStepper:CoolNumericStepper;
	var elemScrollXStepper:CoolNumericStepper;
	var elemScrollYStepper:CoolNumericStepper;
	var elemAlphaStepper:CoolNumericStepper;
	var elemZIndexStepper:CoolNumericStepper;
	var elemAngleStepper:CoolNumericStepper;
	var elemFlipXCheck:CoolCheckBox;
	var elemFlipYCheck:CoolCheckBox;
	var elemAntialiasingCheck:CoolCheckBox;
	var elemVisibleCheck:CoolCheckBox;
	var elemAboveCharsCheck:CoolCheckBox;
	var elemColorInput:CoolInputText;

	// Animations tab widgets
	var animNameInput:CoolInputText;
	var animPrefixInput:CoolInputText;
	var animFPSStepper:CoolNumericStepper;
	var animLoopCheck:CoolCheckBox;
	var animIndicesInput:CoolInputText;
	var animFirstInput:CoolInputText;
	var animTypeDropdown:CoolDropDown;
	var animListBg:FlxTypedGroup<FlxSprite>;
	var animListText:FlxTypedGroup<FlxText>;
	var animHitData:Array<{y:Float, idx:Int}> = [];

	// Stage tab widgets
	var stageNameInput:CoolInputText;
	var stageZoomStepper:CoolNumericStepper;
	var stagePixelCheck:CoolCheckBox;
	var stageHideGFCheck:CoolCheckBox;

	// Chars tab widgets
	var bfXStepper:CoolNumericStepper;
	var bfYStepper:CoolNumericStepper;
	var gfXStepper:CoolNumericStepper;
	var gfYStepper:CoolNumericStepper;
	var dadXStepper:CoolNumericStepper;
	var dadYStepper:CoolNumericStepper;
	var camBFXStepper:CoolNumericStepper;
	var camBFYStepper:CoolNumericStepper;
	var camDadXStepper:CoolNumericStepper;
	var camDadYStepper:CoolNumericStepper;
	var gfVersionInput:CoolInputText;

	// Shaders tab widgets
	var stageShaderDropdown:CoolDropDown;
	var elemShaderDropdown:CoolDropDown;
	var _shaderList:Array<String> = []; // cache de nombres escaneados

	// Backdrop panel widgets (shown only when type == 'backdrop')
	var backdropRepeatXCheck:CoolCheckBox;
	var backdropRepeatYCheck:CoolCheckBox;
	var backdropVelXStepper:CoolNumericStepper;
	var backdropVelYStepper:CoolNumericStepper;
	/** All backdrop-specific tab widgets; toggled as a group. */
	var _backdropWidgets:Array<flixel.FlxBasic> = [];

	// Graphic panel widgets (shown only when type == 'graphic')
	var graphicWidthStepper:CoolNumericStepper;
	var graphicHeightStepper:CoolNumericStepper;
	var graphicFillColorInput:CoolInputText;
	/** All graphic-specific tab widgets; toggled as a group. */
	var _graphicWidgets:Array<flixel.FlxBasic> = [];

	/** Asset path widgets (label + input + browse btn); hidden for types that have no external asset (graphic, group). */
	var _assetWidgets:Array<flixel.FlxBasic> = [];

	// ── Drag ─────────────────────────────────────────────────────────────────
	var isDraggingEl:Bool = false;
	var isDraggingChar:Bool = false;
	var dragCharId:String = null;
	var dragStart:FlxPoint;
	var dragObjStart:FlxPoint;
	var isDraggingCam:Bool = false;
	var dragCamStart:FlxPoint;
	var dragCamScrollStart:FlxPoint;

	// ── Layer panel drag-to-reorder ───────────────────────────────────────────
	var isDraggingLayer:Bool = false;
	var dragLayerFromIdx:Int = -1;    // element index being dragged
	var dragLayerGhostY:Float = 0;    // current Y of the ghost row
	var dragLayerDropIdx:Int = -1;    // insertion index under the cursor
	/** Ghost row sprite that follows the cursor when dragging a layer */
	var layerDragGhost:FlxSprite;
	var layerDragGhostTxt:FlxText;
	/** Drop indicator line */
	var layerDropLine:FlxSprite;

	// ── Pending drag (press-and-hold to drag, click to select) ───────────────
	/** Mouse pressed in drag zone but hasn't moved enough to start a drag. */
	var dragLayerPending:Bool = false;
	var dragLayerPendingIdx:Int = -1;
	var dragLayerPendingX:Float = 0;
	var dragLayerPendingY:Float = 0;
	/** Pixels of movement required before a press becomes a drag (vs a click). */
	static inline final DRAG_THRESHOLD:Float = 6.0;

	// ── File reference ────────────────────────────────────────────────────────
	var _fileRef:FileReference;
	var _shaderFileRef:FileReference; // separado para no mezclar con _fileRef del asset browser

	// ── Animation list visibility (managed at state level, not inside coolui.CoolUIGroup tab) ──
	var _animTabVisible:Bool = false;
	/** All widgets inside the Anims tab — hidden for non-animated element types. */
	var _animTabWidgets:Array<flixel.FlxBasic> = [];
	/** Sprite that covers the "Anims" tab header when the selected element doesn't support animations. */
	var _animTabMask:FlxSprite = null;

	// ── Editor Mode (VIEW / EDIT) ─────────────────────────────────────────────
	/** Current editor mode: 'edit' = full editing, 'view' = camera preview only */
	var editorMode:String = 'edit';
	/** Which camera position to preview in VIEW mode */
	var viewCamSlot:String = 'general'; // 'general' | 'bf' | 'dad' | 'gf'
	/** Mode toggle button sprites (kept to allow recoloring on toggle) */
	var _modeBtnBg:FlxSprite = null;
	var _modeBtnTxt:FlxText = null;
	/** Per-slot button backgrounds for VIEW cam bar (active highlight) */
	var _viewCamBtnBgs:Map<String, FlxSprite> = new Map();
	var _viewCamBtnTxts:Map<String, FlxText> = new Map();
	/** All sprites/texts in the view-cam bar — toggled as a unit */
	var _viewCamBarSprites:Array<FlxSprite> = [];
	var _viewCamBarTexts:Array<FlxText> = [];
	/** Click hit areas for the view cam bar */
	var _viewCamHits:Array<{slot:String, x:Float, y:Float, w:Float, h:Float}> = [];

	// ── Selection info bar (top of right panel) ───────────────────────────────
	/** Background strip shown when an element is selected */
	var _selInfoBg:FlxSprite = null;
	var _selInfoNameTxt:FlxText = null;
	var _selInfoTypeBg:FlxSprite = null;
	var _selInfoTypeTxt:FlxText = null;
	var _selInfoHintTxt:FlxText = null;
	static inline final SEL_INFO_H:Int = 38;

	// ─────────────────────────────────────────────────────────────────────────
	// LIFECYCLE
	// ─────────────────────────────────────────────────────────────────────────

	override public function create():Void
	{
		super.create();

		// Load theme
		EditorTheme.load();
		var T = EditorTheme.current;

		funkin.system.CursorManager.show();

		// Window-close guard — auto-guarda si hay cambios sin guardar
		#if sys
		_windowCloseFn = function()
		{
			if (hasUnsavedChanges)
				try { saveJSON(); } catch (_) {}
		};
		lime.app.Application.current.window.onClose.add(_windowCloseFn);
		#end
		funkin.audio.MusicManager.play('chartEditorLoop/chartEditorLoop', 0.6);

		// ── Cameras ───────────────────────────────────────────────────────────
		camGame = new FlxCamera();
		camGame.bgColor = T.bgDark;
		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;

		// Igual que AnimationDebug: camUI es una cámara transparente y vacía
		// que ocupa cameras[0] (= FlxG.camera). coolui.CoolUIGroup usa cameras[0] para
		// calcular las posiciones de click. Al tener zoom=1 fijo, los inputs,
		// steppers y checkboxes responden correctamente sin importar el zoom
		// del canvas. camGame y camHUD renderizan encima de ella.
		camUI = new FlxCamera();
		camUI.bgColor.alpha = 0;

		FlxG.cameras.reset(camUI); // cameras[0] → FlxG.camera = camUI (zoom 1 fijo)
		FlxG.cameras.add(camGame, false); // canvas, encima de camUI
		FlxG.cameras.add(camHUD, false); // HUD, encima de todo

		camGame.zoom = camZoom;

		dragStart = FlxPoint.get();
		dragObjStart = FlxPoint.get();
		dragCamStart = FlxPoint.get();
		dragCamScrollStart = FlxPoint.get();

		// ── Default stage data ────────────────────────────────────────────────
		var songData = PlayState.SONG;
		stageData = {
			name: songData != null ? (songData.stage ?? 'stage') : 'stage',
			defaultZoom: 0.9,
			isPixelStage: false,
			elements: [],
			gfVersion: songData != null ? (songData.gfVersion ?? 'gf') : 'gf',
			boyfriendPosition: [770.0, 450.0],
			dadPosition: [100.0, 100.0],
			gfPosition: [400.0, 130.0],
			cameraBoyfriend: [0.0, 0.0],
			cameraDad: [0.0, 0.0],
			hideGirlfriend: false,
			scripts: []
		};

		// ── Build everything ──────────────────────────────────────────────────
		buildCanvas();
		buildGrid();
		loadStageIntoCanvas();
		buildUI();
		buildLayerPanel();
		buildRightPanel();
		buildSelectionBox();
		buildSelectionInfoBar();
		buildViewCamBar();

		// ── Layer drag ghost & drop indicator (camHUD, on top of everything) ──
		var T2 = EditorTheme.current;
		layerDragGhost = new FlxSprite(0, 0).makeGraphic(LEFT_W, ROW_H, 0xCC1155AA);
		layerDragGhost.cameras = [camHUD];
		layerDragGhost.scrollFactor.set();
		layerDragGhost.visible = false;
		add(layerDragGhost);
		layerDragGhostTxt = new FlxText(8, 0, LEFT_W - 16, '', 9);
		layerDragGhostTxt.setFormat(Paths.font('vcr.ttf'), 9, 0xFFFFFFFF, LEFT);
		layerDragGhostTxt.cameras = [camHUD];
		layerDragGhostTxt.scrollFactor.set();
		layerDragGhostTxt.visible = false;
		add(layerDragGhostTxt);
		layerDropLine = new FlxSprite(0, 0).makeGraphic(LEFT_W, 2, 0xFF44AAFF);
		layerDropLine.cameras = [camHUD];
		layerDropLine.scrollFactor.set();
		layerDropLine.visible = false;
		add(layerDropLine);

		saveHistory();

		// Camera start position
		camTargetX = FlxG.width * 0.5;
		camTargetY = FlxG.height * 0.5;
		camGame.scroll.x = camTargetX - FlxG.width * 0.5;
		camGame.scroll.y = camTargetY - FlxG.height * 0.5;
	}

	// ─────────────────────────────────────────────────────────────────────────
	// CANVAS SETUP
	// ─────────────────────────────────────────────────────────────────────────

	function buildCanvas():Void
	{
		var canvasBg = new FlxSprite().makeGraphic(FlxG.width * 4, FlxG.height * 4, EditorTheme.current.bgDark);
		canvasBg.x = -FlxG.width * 1.5;
		canvasBg.y = -FlxG.height * 1.5;
		canvasBg.cameras = [camGame];
		add(canvasBg);
	}

	function buildGrid():Void
	{
		var gs = 64;
		var gw = 2560;
		var gh = 1440;

		gridSprite = new FlxSprite(-320, -180);
		gridSprite.makeGraphic(gw, gh, FlxColor.TRANSPARENT, true);

		var pix = gridSprite.pixels;
		var gridLineColor = 0x22FFFFFF;

		// Vertical lines
		var x = 0;
		while (x < gw)
		{
			for (py in 0...gh)
				pix.setPixel32(x, py, gridLineColor);
			x += gs;
		}
		// Horizontal lines
		var y = 0;
		while (y < gh)
		{
			for (px in 0...gw)
				pix.setPixel32(px, y, gridLineColor);
			y += gs;
		}
		// Center axes (brighter)
		var cx = gw >> 1;
		var cy = gh >> 1;
		for (py in 0...gh)
			pix.setPixel32(cx, py, 0x55FFFFFF);
		for (px in 0...gw)
			pix.setPixel32(px, cy, 0x55FFFFFF);

		gridSprite.cameras = [camGame];
		gridSprite.scrollFactor.set(1, 1);
		add(gridSprite);
	}

	function loadStageIntoCanvas():Void
	{
		// ── Remove previous canvas objects ────────────────────────────────────
		if (stage != null)
		{
			// En el char-anchor system los sprites se añadieron directo al FlxState
			// con add(entry.sprite). Hay que quitarlos ANTES de destroy() o quedan
			// huérfanos renderizando indefinidamente sobre los nuevos.
			if (stage._useCharAnchorSystem)
			{
				for (entry in stage.spriteList)
					if (entry.sprite != null)
						remove(entry.sprite, true);
			}

			// stageAboveGroup is stage.aboveCharsGroup — stage.destroy() cleans it up.
			// We only need to remove it from the FlxState render list first.
			if (stageAboveGroup != null)
			{
				remove(stageAboveGroup, true);
				stageAboveGroup = null;
			}
			remove(stage);
			stage.destroy();
			stage = null;
		}
		else if (stageAboveGroup != null)
		{
			remove(stageAboveGroup, true);
			stageAboveGroup = null;
		}
		if (charGroup != null)
		{
			// Characters are added directly to state (not via charGroup) — remove individually
			for (c in charGroup.members)
				if (c != null) remove(c, true);
			charGroup.destroy();
			charGroup = null;
		}
		if (charLabels != null)
		{
			remove(charLabels);
			charLabels.destroy();
			charLabels = null;
		}

		elementSprites.clear();
		characters.clear();

		// ── Build stage: from disk on first load, from memory on subsequent reloads ──
		//
		// • _stageDataReady == false  →  first launch or fresh open: load from disk so
		//   the user sees the actual stage assets immediately.
		//   We capture stageData from the loaded Stage and mark the flag true.
		//
		// • _stageDataReady == true   →  the user has already loaded/edited data;
		//   use __fromData__ so in-memory changes (aboveChars, positions, etc.)
		//   are reflected instantly without needing to save first.
		try
		{
			if (!_stageDataReady)
			{
				// FIX: Verificar si el archivo del stage existe en disco ANTES de crear Stage().
				// Si no existe, Stage.loadStage() caía a loadDefaultStage() → cargaba los assets
				// de stage_week1 aunque el usuario no los pidiera, ensuciando el canvas vacío.
				final stageFileExists = mods.compat.ModCompatLayer.readStageFile(stageData.name) != null;

				if (stageFileExists)
				{
					// ── First load: read from disk ──────────────────────────────
					stage = new Stage(stageData.name);
					stage.isEditorPreview = true;
					if (stage.stageData != null)
					{
						stageData = stage.stageData; // safe: nothing in memory yet
						_stageDataReady = true;
					}
				}
				else
				{
					// ── Stage nuevo sin archivo: canvas vacío ───────────────────
					// Usar __fromData__ con stageData vacío (elements:[]) en lugar de
					// new Stage(nombre) para evitar completamente el fallback a stage_week1.
					trace('[StageEditor] Stage "${stageData.name}" no encontrado en disco — canvas vacío.');
					_stageDataReady = true;
					stage = new Stage('__fromData__');
					stage.isEditorPreview = true;
					stage.curStage = stageData.name ?? 'stage';
					stage.stageData = stageData;
					stage.buildStage();
				}
			}
			else
			{
				// ── Subsequent reloads: build from in-memory stageData ───────────
				// __fromData__ sentinel skips loadStage() / disk I/O entirely.
				stage = new Stage('__fromData__');
				stage.isEditorPreview = true;
				stage.curStage = stageData.name ?? 'stage';
				stage.stageData = stageData;
				stage.buildStage(); // routes aboveChars:true → stage.aboveCharsGroup
			}

			stage.cameras = [camGame];
			// FlxTypedGroup.cameras no hace cascade automático a los miembros
			// existentes, ni tampoco a sub-grupos. Propagamos recursivamente.
			_assignCamerasRecursive(stage, [camGame]);
			add(stage);

			// In the char-anchor system, sprites are in spriteList (stage.members is empty).
			// We only set cameras here; the actual add() calls happen inside
			// _addCharsInOrder() so that stage sprites and character sprites are
			// interleaved in the correct draw order defined by stageData.elements.
			if (stage._useCharAnchorSystem)
			{
				for (entry in stage.spriteList)
					if (entry.sprite != null)
						entry.sprite.cameras = [camGame];
			}

			// Map all element sprites so the editor can select/drag/highlight them
			for (name => spr in stage.elements)
				elementSprites.set(name, spr);
			for (name => grp in stage.groups)
				if (grp.length > 0 && grp.members[0] != null)
					elementSprites.set(name, grp.members[0]);
			for (name => spr in stage.customClasses)
				elementSprites.set(name, spr);

			// ── Re-aplicar shaders guardados en customProperties ──────────────
			for (elem in stageData.elements)
			{
				if (elem.customProperties == null) continue;
				var sh = Reflect.field(elem.customProperties, 'shader');
				if (sh == null || sh == '') continue;
				var shName = Std.string(sh);
				if (elem.name != null && elementSprites.exists(elem.name))
				{
					var spr = elementSprites.get(elem.name);
					ShaderManager.applyShader(spr, shName, camGame);

					// Restaurar params guardados
					var sp = Reflect.field(elem.customProperties, 'shaderParams');
					if (sp != null)
					{
						for (field in Reflect.fields(sp))
							ShaderManager.setShaderParam(shName, field, Reflect.field(sp, field));
					}
				}
			}
		}
		catch (e:Dynamic)
		{
			trace('[StageEditor] Stage build error: $e');
			stage = null;
		}

		// ── Characters ────────────────────────────────────────────────────────
		charGroup = new FlxTypedGroup<Character>();
		charLabels = new FlxTypedGroup<FlxText>();
		charGroup.cameras = [camGame];
		charLabels.cameras = [camGame];
		// NOTE: charGroup is NOT added directly to state so we can control
		// the z-order of individual characters relative to stage elements.
		// Characters are added in _addCharsInOrder() below.

		// ── Above-chars group / char-anchor system ────────────────────────────
		// In the new char-anchor system, all sprites are in stage.spriteList
		// and have already been added individually above. The aboveCharsGroup
		// is empty (old-system only). Skip it to avoid double-add.
		if (stage != null && !stage._useCharAnchorSystem
			&& stage.aboveCharsGroup != null && stage.aboveCharsGroup.length > 0)
		{
			stageAboveGroup = stage.aboveCharsGroup;
			stageAboveGroup.cameras = [camGame];
			for (obj in stageAboveGroup.members)
				if (obj != null)
					obj.cameras = [camGame];
			// stageAboveGroup is added AFTER characters inside _addCharsInOrder
		}
		else
		{
			stageAboveGroup = null;
		}

		// Auto-populate character layer entries if absent, then load and place chars
		_ensureCharacterEntries();
		loadCharacters();
		_addCharsInOrder();
		add(charLabels);
		if (stageAboveGroup != null)
			add(stageAboveGroup);
	}

	function loadCharacters():Void
	{
		// Clear existing
		for (spr in charGroup.members)
			if (spr != null)
				spr.destroy();
		charGroup.clear();
		for (t in charLabels.members)
			if (t != null)
				t.destroy();
		charLabels.clear();
		characters.clear();

		var songData = PlayState.SONG;
		var p1 = songData != null ? (songData.player1 ?? 'bf') : 'bf';
		var p2 = songData != null ? (songData.player2 ?? 'dad') : 'dad';
		var gfVer = stageData.gfVersion ?? (songData != null ? (songData.gfVersion ?? 'gf') : 'gf');

		var bfPos = stageData.boyfriendPosition ?? [770.0, 450.0];
		var dadPos = stageData.dadPosition ?? [100.0, 100.0];
		var gfPos = stageData.gfPosition ?? [400.0, 130.0];

		function addChar(id:String, name:String, x:Float, y:Float, isPlayer:Bool, label:String):Void
		{
			try
			{
				var c = new Character(x, y, name, isPlayer);
				c.alpha = 0.85;
				charGroup.add(c);
				characters.set(id, c);

				var lbl = new FlxText(x, y - 22, 200, label, 10);
				lbl.setFormat(Paths.font('vcr.ttf'), 10, id == 'bf' ? 0xFF00D9FF : (id == 'gf' ? 0xFFFF88FF : 0xFFFFAA00), LEFT);
				charLabels.add(lbl);
			}
			catch (e:Dynamic)
			{
				trace('[StageEditor] Char load error ($id: $name): $e');
			}
		}

		addChar('dad', p2, dadPos[0], dadPos[1], false, 'DAD (' + p2 + ')');
		if (!(stageData.hideGirlfriend == true))
			addChar('gf', gfVer, gfPos[0], gfPos[1], false, 'GF (' + gfVer + ')');
		addChar('bf', p1, bfPos[0], bfPos[1], true, 'BF (' + p1 + ')');
	}

	function buildSelectionBox():Void
	{
		selBox = new FlxSprite();
		selBox.makeGraphic(1, 1, FlxColor.TRANSPARENT);
		selBox.visible = false;
		selBox.cameras = [camGame];
		add(selBox);

		// Malla semitransparente sobre el sprite seleccionado (patrón checkerboard)
		selMesh = new FlxSprite();
		selMesh.makeGraphic(1, 1, FlxColor.TRANSPARENT);
		selMesh.visible = false;
		selMesh.alpha = 0.35;
		selMesh.cameras = [camGame];
		add(selMesh);

		// Tooltip de hover — vive en camHUD para que siempre esté encima de todo
		hoverTooltipBg = new FlxSprite();
		hoverTooltipBg.makeGraphic(4, 18, 0xCC000000);
		hoverTooltipBg.visible = false;
		hoverTooltipBg.scrollFactor.set();
		hoverTooltipBg.cameras = [camHUD];
		add(hoverTooltipBg);

		hoverTooltipTxt = new FlxText(0, 0, 0, '', 11);
		hoverTooltipTxt.setFormat(Paths.font('vcr.ttf'), 11, FlxColor.WHITE, LEFT);
		hoverTooltipTxt.borderStyle = OUTLINE;
		hoverTooltipTxt.borderColor = FlxColor.BLACK;
		hoverTooltipTxt.visible = false;
		hoverTooltipTxt.scrollFactor.set();
		hoverTooltipTxt.cameras = [camHUD];
		add(hoverTooltipTxt);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// HUD SETUP — TITLE / TOOLBAR / STATUS
	// ─────────────────────────────────────────────────────────────────────────

	function buildUI():Void
	{
		var T = EditorTheme.current;

		// Title bar
		var titleBg = new FlxSprite().makeGraphic(FlxG.width, TITLE_H, T.bgPanelAlt);
		titleBg.cameras = [camHUD];
		titleBg.scrollFactor.set();
		add(titleBg);

		var titleBorder = new FlxSprite(0, TITLE_H - 2).makeGraphic(FlxG.width, 2, T.borderColor);
		titleBorder.cameras = [camHUD];
		titleBorder.scrollFactor.set();
		titleBorder.alpha = 0.6;
		add(titleBorder);

		titleText = new FlxText(10, 6, 0, '\u26AA  STAGE EDITOR  \u2022  ' + stageData.name, 15);
		titleText.setFormat(Paths.font('vcr.ttf'), 15, T.accent, LEFT, OUTLINE, FlxColor.BLACK);
		titleText.cameras = [camHUD];
		titleText.scrollFactor.set();
		add(titleText);

		unsavedDot = new FlxText(0, 8, 0, '  [UNSAVED]', 11);
		unsavedDot.setFormat(Paths.font('vcr.ttf'), 11, T.warning, LEFT);
		unsavedDot.visible = false;
		unsavedDot.cameras = [camHUD];
		unsavedDot.scrollFactor.set();
		add(unsavedDot);

		// Toolbar
		var toolbarBg = new FlxSprite(0, TITLE_H).makeGraphic(FlxG.width, TOOLBAR_H, T.bgPanel);
		toolbarBg.cameras = [camHUD];
		toolbarBg.scrollFactor.set();
		add(toolbarBg);

		var toolbarBorder = new FlxSprite(0, TOP_H - 1).makeGraphic(FlxG.width, 1, T.borderColor);
		toolbarBorder.cameras = [camHUD];
		toolbarBorder.scrollFactor.set();
		toolbarBorder.alpha = 0.4;
		add(toolbarBorder);

		buildToolbarButtons();

		// Status bar
		var statusBg = new FlxSprite(0, FlxG.height - STATUS_H).makeGraphic(FlxG.width, STATUS_H, T.bgPanelAlt);
		statusBg.cameras = [camHUD];
		statusBg.scrollFactor.set();
		add(statusBg);

		var statusBorder = new FlxSprite(0, FlxG.height - STATUS_H).makeGraphic(FlxG.width, 1, T.borderColor);
		statusBorder.alpha = 0.4;
		statusBorder.cameras = [camHUD];
		statusBorder.scrollFactor.set();
		add(statusBorder);

		statusText = new FlxText(8, FlxG.height - STATUS_H + 5, 400, 'Stage Editor ready', 10);
		statusText.setFormat(Paths.font('vcr.ttf'), 10, T.textSecondary, LEFT);
		statusText.cameras = [camHUD];
		statusText.scrollFactor.set();
		add(statusText);

		modBadge = new FlxText(FlxG.width - 320, FlxG.height - STATUS_H + 5, 150, _modLabel(), 10);
		modBadge.setFormat(Paths.font('vcr.ttf'), 10, ModManager.isActive() ? T.success : T.textDim, RIGHT);
		modBadge.cameras = [camHUD];
		modBadge.scrollFactor.set();
		add(modBadge);

		coordText = new FlxText(FlxG.width - 160, FlxG.height - STATUS_H + 5, 80, 'x:0 y:0', 10);
		coordText.setFormat(Paths.font('vcr.ttf'), 10, T.textSecondary, RIGHT);
		coordText.cameras = [camHUD];
		coordText.scrollFactor.set();
		add(coordText);

		zoomText = new FlxText(FlxG.width - 75, FlxG.height - STATUS_H + 5, 65, 'Zoom: 75%', 10);
		zoomText.setFormat(Paths.font('vcr.ttf'), 10, T.textSecondary, RIGHT);
		zoomText.cameras = [camHUD];
		zoomText.scrollFactor.set();
		add(zoomText);
	}

	function buildToolbarButtons():Void
	{
		var T = EditorTheme.current;
		var by = TITLE_H + 6;

		function toolBtn(x:Float, w:Int, label:String, col:Int, cb:Void->Void):FlxSprite
		{
			var bg = new FlxSprite(x, by).makeGraphic(w, 28, col);
			bg.cameras = [camHUD];
			bg.scrollFactor.set();
			add(bg);
			var txt = new FlxText(x, by + 7, w, label, 10);
			txt.setFormat(Paths.font('vcr.ttf'), 10, T.textPrimary, CENTER);
			txt.cameras = [camHUD];
			txt.scrollFactor.set();
			add(txt);
			_toolBtns.set(bg, cb);
			return bg;
		}

		// ── Left action buttons (EDIT mode only) ─────────────────────────────────
		toolBtn(LEFT_W + 4,   58, '\u2606 NEW',      0xFF1A002A, openNewStageDialog);
		toolBtn(LEFT_W + 66,  72, '\u25A4 STAGES',  0xFF001A2A, openStageListDialog);
		toolBtn(LEFT_W + 142, 80, '+ ADD ELEMENT', T.bgHover,  openAddElementDialog);
		toolBtn(LEFT_W + 226, 52, 'LOAD',           T.bgPanelAlt, loadJSON);
		toolBtn(LEFT_W + 282, 52, 'SAVE',           0xFF003A20, saveJSON);
		toolBtn(LEFT_W + 338, 72, 'SAVE MOD',       0xFF2A1A00, saveToMod);

		// ── Right utility buttons (always visible) ────────────────────────────────
		toolBtn(FlxG.width - RIGHT_W - 4 - 166, 40, 'UNDO', T.bgPanelAlt, undo);
		toolBtn(FlxG.width - RIGHT_W - 4 - 122, 40, 'REDO', T.bgPanelAlt, redo);
		toolBtn(FlxG.width - RIGHT_W - 4 - 78, 38, 'COPY', T.bgPanelAlt, copyElement);
		toolBtn(FlxG.width - RIGHT_W - 4 - 36, 36, 'PASTE', T.bgPanelAlt, pasteElement);
		toolBtn(FlxG.width - RIGHT_W - 4, 32, '\u2728', T.bgPanelAlt, () -> openSubState(new ThemePickerSubState()));

		// ── MODE TOGGLE BUTTON (centre of toolbar) ────────────────────────────────
		// Placed between the left action group and the right utility group.
		var modeX:Float = LEFT_W + 430;
		var modeW:Int = 100;
		_modeBtnBg = new FlxSprite(modeX, by).makeGraphic(modeW, 28, 0xFF003A10);
		_modeBtnBg.cameras = [camHUD];
		_modeBtnBg.scrollFactor.set();
		add(_modeBtnBg);
		_toolBtns.set(_modeBtnBg, _toggleEditorMode);

		_modeBtnTxt = new FlxText(modeX, by + 7, modeW, '\u25CF EDIT MODE', 10);
		_modeBtnTxt.setFormat(Paths.font('vcr.ttf'), 10, 0xFF44FF88, CENTER);
		_modeBtnTxt.cameras = [camHUD];
		_modeBtnTxt.scrollFactor.set();
		add(_modeBtnTxt);
	}

	var _toolBtns:Map<FlxSprite, Void->Void> = new Map();

	// ─────────────────────────────────────────────────────────────────────────
	// VIEW CAM BAR  (visible only in VIEW mode, sits in the toolbar area)
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Builds a row of 4 camera-selector tabs that appears in VIEW mode.
	 * Tabs: GENERAL | BF CAM | DAD CAM | GF CAM
	 * Hidden by default (edit mode).
	 */
	function buildViewCamBar():Void
	{
		var T = EditorTheme.current;
		_viewCamHits = [];
		_viewCamBtnBgs = new Map();
		_viewCamBtnTxts = new Map();
		_viewCamBarSprites = [];
		_viewCamBarTexts = [];

		// Bar background (replaces the left action buttons in VIEW mode)
		var barBg = new FlxSprite(LEFT_W + 2, TITLE_H + 2).makeGraphic(
			Std.int(FlxG.width - LEFT_W - RIGHT_W - 4 - 200), TOOLBAR_H - 4, 0xFF000E1A);
		barBg.cameras = [camHUD];
		barBg.scrollFactor.set();
		barBg.visible = false;
		add(barBg);
		_viewCamBarSprites.push(barBg);

		// Label
		var lbl = new FlxText(LEFT_W + 8, TITLE_H + 10, 0, 'CAMERA VIEW:', 9);
		lbl.setFormat(Paths.font('vcr.ttf'), 9, T.textSecondary, LEFT);
		lbl.cameras = [camHUD];
		lbl.scrollFactor.set();
		lbl.visible = false;
		add(lbl);
		_viewCamBarTexts.push(lbl);

		// Camera tab definitions
		var slots:Array<{id:String, label:String, col:Int, labelCol:Int}> = [
			{id: 'general', label: '\u25CB  GENERAL',  col: 0xFF0A1A2A, labelCol: 0xFF88BBFF},
			{id: 'bf',      label: '\u25CF  BF CAM',   col: 0xFF001A2A, labelCol: 0xFF00D9FF},
			{id: 'dad',     label: '\u25CF  DAD CAM',  col: 0xFF1A1000, labelCol: 0xFFFFAA00},
			{id: 'gf',      label: '\u25CF  GF CAM',   col: 0xFF1A001A, labelCol: 0xFFFF88FF},
		];

		var bx:Float = LEFT_W + 100;
		var bw:Int = 100;
		var by2 = TITLE_H + 6;
		var bh = 28;

		for (slot in slots)
		{
			var col = slot.id == viewCamSlot ? 0xFF004466 : slot.col;
			var bg = new FlxSprite(bx, by2).makeGraphic(bw, bh, col);
			bg.cameras = [camHUD];
			bg.scrollFactor.set();
			bg.visible = false;
			add(bg);
			_viewCamBarSprites.push(bg);
			_viewCamBtnBgs.set(slot.id, bg);

			var txt = new FlxText(bx, by2 + 8, bw, slot.label, 9);
			txt.setFormat(Paths.font('vcr.ttf'), 9, slot.labelCol, CENTER);
			txt.cameras = [camHUD];
			txt.scrollFactor.set();
			txt.visible = false;
			add(txt);
			_viewCamBarTexts.push(txt);
			_viewCamBtnTxts.set(slot.id, txt);

			_viewCamHits.push({slot: slot.id, x: bx, y: by2, w: bw, h: bh});
			bx += bw + 4;
		}

		// Info text (shows current cam target coords)
		var infoTxt = new FlxText(bx + 4, TITLE_H + 10, 140, 'Zoom: stage default', 9);
		infoTxt.setFormat(Paths.font('vcr.ttf'), 9, T.textDim, LEFT);
		infoTxt.cameras = [camHUD];
		infoTxt.scrollFactor.set();
		infoTxt.visible = false;
		add(infoTxt);
		_viewCamBarTexts.push(infoTxt);

		// The view cam bar background covers the mode-toggle button because it is
		// added to the state after the button. Re-insert the button at the END of
		// the draw list so it is always rendered on top of the bar background.
		if (_modeBtnBg  != null) { remove(_modeBtnBg,  true); add(_modeBtnBg); }
		if (_modeBtnTxt != null) { remove(_modeBtnTxt, true); add(_modeBtnTxt); }
	}

	/** Toggles between EDIT and VIEW mode. */
	function _toggleEditorMode():Void
	{
		editorMode = (editorMode == 'edit') ? 'view' : 'edit';
		var isView = (editorMode == 'view');

		// Update mode button appearance
		if (_modeBtnBg != null)
			_modeBtnBg.makeGraphic(100, 28, isView ? 0xFF00204A : 0xFF003A10);
		if (_modeBtnTxt != null)
		{
			_modeBtnTxt.text = isView ? '\u25CE VIEW MODE' : '\u25CF EDIT MODE';
			_modeBtnTxt.color = isView ? 0xFF44AAFF : 0xFF44FF88;
		}

		// Show/hide view cam bar
		for (s in _viewCamBarSprites) if (s != null) s.visible = isView;
		for (t in _viewCamBarTexts)  if (t != null) t.visible = isView;

		// Show/hide selection box (not needed in view mode)
		if (selBox  != null) selBox.visible  = false;
		if (selMesh != null) selMesh.visible = false;

		// ── Right panel: use X-offset to truly hide native text fields (CoolInputText /
		//   CoolNumericStepper use OpenFL native TextFields that ignore Flixel visible=false).
		//   Moving the entire CoolTabMenu off-screen is the only reliable way to hide them.
		_setRightPanelsOffscreen(isView);

		// Deselect everything when entering view mode
		if (isView)
		{
			selectedIdx = -1;
			selectedIndices = [];
			selectedCharId = null;
			_updateSelectionInfoBar();
			refreshLayerPanel();
			_setViewCamera(viewCamSlot);
			setStatus('VIEW MODE — Select a camera tab to preview it');
		}
		else
		{
			// Return to free-roam on re-entering edit mode
			camZoom = 0.75;
			_updatePanelVisibility(); // restore correct panel based on selection state
			setStatus('EDIT MODE — Click and drag elements to position them');
		}
	}

	/**
	 * Moves both right CoolTabMenu panels on/off screen in VIEW mode.
	 *
	 * WHY X-OFFSET instead of visible=false:
	 * CoolInputText and CoolNumericStepper wrap native OpenFL TextFields.
	 * Native TextFields live in OpenFL's display list and are NOT hidden
	 * by Flixel's visible flag — they must physically leave the visible
	 * screen area to disappear.  Setting the parent CoolTabMenu's x to a
	 * large value moves every child TextField off-screen reliably.
	 */
	function _setRightPanelsOffscreen(offscreen:Bool):Void
	{
		// Panel backgrounds — plain FlxSprites, visible=false works fine
		if (_rightPanelBg     != null) _rightPanelBg.visible     = !offscreen;
		if (_rightPanelBorder != null) _rightPanelBorder.visible = !offscreen;

		// Selection info bar — plain FlxSprite/FlxText, visible=false works fine
		// (They are already hidden when nothing is selected; this is the safety blanket.)
		if (offscreen)
		{
			if (_selInfoBg       != null) _selInfoBg.visible       = false;
			if (_selInfoNameTxt  != null) _selInfoNameTxt.visible  = false;
			if (_selInfoTypeBg   != null) _selInfoTypeBg.visible   = false;
			if (_selInfoTypeTxt  != null) _selInfoTypeTxt.visible  = false;
			if (_selInfoHintTxt  != null) _selInfoHintTxt.visible  = false;
		}
		// (Restoring selInfo visibility is handled by _updateSelectionInfoBar on re-entry.)

		// CoolTabMenu panels — MUST use X-offset because they contain native TextFields
		if (rightPanel    != null) rightPanel.x    = offscreen ? RIGHT_PANEL_HIDE_X : _rightPanelEditX;
		if (_contextPanel != null) _contextPanel.x = offscreen ? RIGHT_PANEL_HIDE_X : _rightPanelEditX;

		// Anims tab header mask — follows context panel
		if (_animTabMask != null) _animTabMask.x = offscreen ? RIGHT_PANEL_HIDE_X : _rightPanelEditX;

		// Animation list overlay — plain FlxGroups, visible works fine
		if (offscreen)
		{
			if (animListBg   != null) animListBg.visible   = false;
			if (animListText != null) animListText.visible = false;
			_animTabVisible = false;
		}
	}

	/**
	 * Switches between rightPanel (Stage/Chars/Shaders — no selection)
	 * and _contextPanel (Element/Anims — has selection).
	 * Uses X-offset so native OpenFL text fields are truly hidden.
	 * No-ops in VIEW mode (panels are already off-screen via _setRightPanelsOffscreen).
	 */
	function _updatePanelVisibility():Void
	{
		if (editorMode == 'view') return;

		var hasSelection = (selectedIdx >= 0 && selectedIdx < stageData.elements.length)
			|| selectedCharId != null;

		// Ensure backgrounds are visible (they might have been hidden in view mode)
		if (_rightPanelBg     != null) _rightPanelBg.visible     = true;
		if (_rightPanelBorder != null) _rightPanelBorder.visible = true;

		// Move the correct panel on-screen, push the other off-screen.
		if (rightPanel    != null) rightPanel.x    = hasSelection ? RIGHT_PANEL_HIDE_X : _rightPanelEditX;
		if (_contextPanel != null)
		{
			_contextPanel.x       = hasSelection ? _rightPanelEditX : RIGHT_PANEL_HIDE_X;
			_contextPanel.visible = true; // was set false at build-time; restore it here
		}

		// Keep the Anims-tab mask aligned with the context panel
		if (_animTabMask != null)
			_animTabMask.x = hasSelection ? _rightPanelEditX : RIGHT_PANEL_HIDE_X;
	}

	/**
	 * Moves camGame to show the stage from the perspective of the given camera slot.
	 *   'general' → free-roam (no lock, reset to center)
	 *   'bf'      → boyfriend position + cameraBoyfriend offset
	 *   'dad'     → dad position + cameraDad offset
	 *   'gf'      → girlfriend position (no game-cam offset for GF)
	 */
	function _setViewCamera(slot:String):Void
	{
		viewCamSlot = slot;
		_refreshViewCamBar();

		var zoom = stageData.defaultZoom > 0 ? stageData.defaultZoom : 0.9;

		switch (slot)
		{
			case 'bf':
				var pos  = stageData.boyfriendPosition  ?? [770.0, 450.0];
				var off  = stageData.cameraBoyfriend     ?? [0.0, 0.0];
				var cx = pos[0] + off[0];
				var cy = pos[1] + off[1];
				camTargetX = cx + FlxG.width  * 0.5 / zoom;
				camTargetY = cy + FlxG.height * 0.5 / zoom;
				camZoom    = zoom;
				setStatus('BF CAM  →  target x:${Std.int(cx)} y:${Std.int(cy)}  zoom:${zoom}');

			case 'dad':
				var pos  = stageData.dadPosition   ?? [100.0, 100.0];
				var off  = stageData.cameraDad      ?? [0.0, 0.0];
				var cx = pos[0] + off[0];
				var cy = pos[1] + off[1];
				camTargetX = cx + FlxG.width  * 0.5 / zoom;
				camTargetY = cy + FlxG.height * 0.5 / zoom;
				camZoom    = zoom;
				setStatus('DAD CAM  →  target x:${Std.int(cx)} y:${Std.int(cy)}  zoom:${zoom}');

			case 'gf':
				var pos = stageData.gfPosition ?? [400.0, 130.0];
				var cx = pos[0];
				var cy = pos[1];
				camTargetX = cx + FlxG.width  * 0.5 / zoom;
				camTargetY = cy + FlxG.height * 0.5 / zoom;
				camZoom    = zoom;
				setStatus('GF CAM  →  target x:${Std.int(cx)} y:${Std.int(cy)}  zoom:${zoom}');

			default: // 'general'
				camTargetX = FlxG.width  * 0.5;
				camTargetY = FlxG.height * 0.5;
				camZoom    = 0.75;
				setStatus('GENERAL VIEW — Free roam (middle-mouse drag / scroll to zoom)');
		}
	}

	/** Repaints camera tab buttons to show which one is active. */
	function _refreshViewCamBar():Void
	{
		var slots:Array<{id:String, base:Int}> = [
			{id: 'general', base: 0xFF0A1A2A},
			{id: 'bf',      base: 0xFF001A2A},
			{id: 'dad',     base: 0xFF1A1000},
			{id: 'gf',      base: 0xFF1A001A},
		];
		for (s in slots)
		{
			var bg = _viewCamBtnBgs.get(s.id);
			if (bg == null) continue;
			var active = (s.id == viewCamSlot);
			bg.makeGraphic(100, 28, active ? 0xFF004466 : s.base);
			var txt = _viewCamBtnTxts.get(s.id);
			if (txt != null)
				txt.alpha = active ? 1.0 : 0.65;
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	// SELECTION INFO BAR  (top strip of right panel — shows selected element)
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Builds the selection info bar displayed at the very top of the right panel.
	 * It shows the name and type of the currently selected element so you can see
	 * at a glance what you're editing without scrolling the tab.
	 */
	function buildSelectionInfoBar():Void
	{
		var T = EditorTheme.current;
		var panelX:Float = FlxG.width - RIGHT_W + 2;
		var panelY:Float = TOP_H;

		// Background strip (sits ABOVE the CoolTabMenu header)
		_selInfoBg = new FlxSprite(panelX, panelY).makeGraphic(RIGHT_W - 2, SEL_INFO_H, T.bgPanelAlt);
		_selInfoBg.cameras = [camHUD];
		_selInfoBg.scrollFactor.set();
		_selInfoBg.visible = false;
		add(_selInfoBg);

		// Bottom border
		var border = new FlxSprite(panelX, panelY + SEL_INFO_H - 2).makeGraphic(RIGHT_W - 2, 2, T.borderColor);
		border.alpha = 0.4;
		border.cameras = [camHUD];
		border.scrollFactor.set();
		add(border);
		// Store in _selInfoBg so it toggles with the same logic (hidden via alpha trick)
		// — actually just always show it; it's drawn behind the tab header anyway.

		// Element name
		_selInfoNameTxt = new FlxText(panelX + 8, panelY + 6, RIGHT_W - 80, 'No selection', 11);
		_selInfoNameTxt.setFormat(Paths.font('vcr.ttf'), 11, T.textPrimary, LEFT);
		_selInfoNameTxt.cameras = [camHUD];
		_selInfoNameTxt.scrollFactor.set();
		_selInfoNameTxt.visible = false;
		add(_selInfoNameTxt);

		// Type badge background
		_selInfoTypeBg = new FlxSprite(panelX + RIGHT_W - 68, panelY + 6).makeGraphic(60, 16, T.bgHover);
		_selInfoTypeBg.cameras = [camHUD];
		_selInfoTypeBg.scrollFactor.set();
		_selInfoTypeBg.visible = false;
		add(_selInfoTypeBg);

		// Type badge text
		_selInfoTypeTxt = new FlxText(panelX + RIGHT_W - 68, panelY + 7, 60, '', 9);
		_selInfoTypeTxt.setFormat(Paths.font('vcr.ttf'), 9, 0xFF000000, CENTER);
		_selInfoTypeTxt.cameras = [camHUD];
		_selInfoTypeTxt.scrollFactor.set();
		_selInfoTypeTxt.visible = false;
		add(_selInfoTypeTxt);

		// Hint text
		_selInfoHintTxt = new FlxText(panelX + 8, panelY + 22, RIGHT_W - 80, '', 9);
		_selInfoHintTxt.setFormat(Paths.font('vcr.ttf'), 9, T.textDim, LEFT);
		_selInfoHintTxt.cameras = [camHUD];
		_selInfoHintTxt.scrollFactor.set();
		_selInfoHintTxt.visible = false;
		add(_selInfoHintTxt);
	}

	/**
	 * Updates the selection info bar text and type badge to reflect the current selection.
	 * Call whenever selectedIdx / selectedCharId changes.
	 */
	function _updateSelectionInfoBar():Void
	{
		if (_selInfoBg == null) return;

		var T = EditorTheme.current;
		var hasElem = (selectedIdx >= 0 && selectedIdx < stageData.elements.length);
		var hasChar = (!hasElem && selectedCharId != null);
		var hasAny  = hasElem || hasChar;

		_selInfoBg.visible       = hasAny;
		_selInfoNameTxt.visible  = hasAny;
		_selInfoTypeBg.visible   = hasAny;
		_selInfoTypeTxt.visible  = hasAny;
		_selInfoHintTxt.visible  = hasAny;

		if (!hasAny) return;

		if (hasElem)
		{
			var elem = stageData.elements[selectedIdx];
			var nameStr = elem.name ?? ('element_' + selectedIdx);
			_selInfoNameTxt.text = nameStr.length > 24 ? nameStr.substr(0, 22) + '..' : nameStr;

			var typeStr = elem.type ?? 'sprite';
			var badgeLabel = typeStr.toUpperCase().substr(0, 7);
			_selInfoTypeTxt.text = badgeLabel;

			// Color badge by type
			var badgeColor = switch (typeStr.toLowerCase())
			{
				case 'animated':                  T.accentAlt;
				case 'atlas', 'animate_atlas', 'texture_atlas': 0xFF9900AA; // violeta brillante
				case 'graphic':                   0xFFCC8800;
				case 'backdrop':                  0xFF007799;
				case 'group', 'custom_class_group': T.warning;
				case 'sound':                     T.success;
				case 'character':                 0xFF0077CC;
				default:                          T.bgHover;
			};
			var panelX:Float = FlxG.width - RIGHT_W + 2;
			_selInfoTypeBg.x = panelX + RIGHT_W - 68;
			_selInfoTypeBg.makeGraphic(60, 16, badgeColor);
			_selInfoTypeTxt.x = panelX + RIGHT_W - 68;

			var hint = 'idx:$selectedIdx  |  ';
			hint += (elem.locked == true) ? '\u{1F512} LOCKED' : 'drag or arrow-nudge to move';
			_selInfoHintTxt.text = hint;
			_selInfoHintTxt.color = (elem.locked == true) ? T.warning : T.textDim;
		}
		else // hasChar
		{
			var cLabel = switch (selectedCharId)
			{
				case 'bf':  'Boyfriend';
				case 'gf':  'Girlfriend';
				case 'dad': 'Dad (Opponent)';
				default:    selectedCharId;
			};
			_selInfoNameTxt.text = cLabel;
			_selInfoTypeTxt.text = 'CHAR';
			var panelX:Float = FlxG.width - RIGHT_W + 2;
			_selInfoTypeBg.x = panelX + RIGHT_W - 68;
			_selInfoTypeBg.makeGraphic(60, 16, 0xFF0077CC);
			_selInfoTypeTxt.x = panelX + RIGHT_W - 68;
			_selInfoHintTxt.text = 'drag on canvas to move';
			_selInfoHintTxt.color = EditorTheme.current.textDim;
		}

		// Toggle right-side panels based on whether anything is selected
		_updatePanelVisibility();
	}



	function buildLayerPanel():Void
	{
		var T = EditorTheme.current;
		var panelH = FlxG.height - TOP_H - STATUS_H;

		layerPanelBg = new FlxSprite(0, TOP_H).makeGraphic(LEFT_W, panelH, T.bgPanel);
		layerPanelBg.cameras = [camHUD];
		layerPanelBg.scrollFactor.set();
		add(layerPanelBg);

		// Right border
		var border = new FlxSprite(LEFT_W, TOP_H).makeGraphic(2, panelH, T.borderColor);
		border.alpha = 0.5;
		border.cameras = [camHUD];
		border.scrollFactor.set();
		add(border);

		layerRowsGroup = new FlxTypedGroup<FlxSprite>();
		layerTextsGroup = new FlxTypedGroup<FlxText>();
		layerRowsGroup.cameras = [camHUD];
		layerTextsGroup.cameras = [camHUD];
		add(layerRowsGroup);
		add(layerTextsGroup);

		refreshLayerPanel();
	}

	function refreshLayerPanel():Void
	{
		var T = EditorTheme.current;

		// ── Clear existing rows ───────────────────────────────────────────────
		for (s in layerRowsGroup.members)
			if (s != null) { remove(s, true); s.destroy(); }
		for (t in layerTextsGroup.members)
			if (t != null) { remove(t, true); t.destroy(); }
		layerRowsGroup.clear();
		layerTextsGroup.clear();
		layerHitData = [];
		_layerRowBgMap.clear();
		_layerRowTextsMap.clear();

		var rowY = TOP_H + 0.0;

		// ── LAYERS header ─────────────────────────────────────────────────────
		var headerBg = new FlxSprite(0, rowY).makeGraphic(LEFT_W, 28, T.bgPanelAlt);
		headerBg.cameras = [camHUD];
		headerBg.scrollFactor.set();
		add(headerBg);
		layerRowsGroup.add(headerBg);
		var headerTxt = new FlxText(10, rowY + 6, 0, '\u25A3 LAYERS', 12);
		headerTxt.setFormat(Paths.font('vcr.ttf'), 12, T.accent, LEFT);
		headerTxt.cameras = [camHUD];
		headerTxt.scrollFactor.set();
		add(headerTxt);
		layerTextsGroup.add(headerTxt);

		// [+] button in header
		var addBg = new FlxSprite(LEFT_W - 26, rowY + 4).makeGraphic(22, 20, T.bgHover);
		addBg.cameras = [camHUD];
		addBg.scrollFactor.set();
		add(addBg);
		layerRowsGroup.add(addBg);
		var addTxt = new FlxText(LEFT_W - 26, rowY + 5, 22, '+', 12);
		addTxt.setFormat(Paths.font('vcr.ttf'), 12, T.success, CENTER);
		addTxt.cameras = [camHUD];
		addTxt.scrollFactor.set();
		add(addTxt);
		layerTextsGroup.add(addTxt);
		layerHitData.push({
			x: LEFT_W - 26,
			w: 22,
			y: rowY + 4,
			h: 20,
			idx: -2,
			charId: null,
			zone: 'add_element'
		});
		rowY += 28;

		// ── Layer rows (top of list = topmost on screen = last in array) ──────
		var elements = stageData.elements;
		var totalRows = elements != null ? elements.length : 0;
		var drawnCount = 0;
		var i = totalRows - 1;
		while (i >= 0)
		{
			if (drawnCount < layerScrollStart)
			{
				drawnCount++;
				i--;
				continue;
			}
			if (drawnCount >= layerScrollStart + MAX_VISIBLE_LAYERS)
			{
				i--;
				continue;
			}
			drawnCount++;

			var elemIdx = i;
			var elem = elements[elemIdx];

			// ── Character anchor row ────────────────────────────────────────
			if (elem.type != null && elem.type.toLowerCase() == 'character')
			{
				_drawCharAnchorRow(elemIdx, rowY);
				rowY += ROW_H;
				i--;
				continue;
			}

			var isSelected = (elemIdx == selectedIdx || selectedIndices.contains(elemIdx));
			var isVisible = !(elem.visible == false);
			var isAbove = (elem.aboveChars == true);

			// Row background — tinted amber if aboveChars
			var isHovered = (elemIdx == layerHoverIdx && !isSelected);
			var rowBgColor = isSelected ? T.rowSelected
				: isHovered  ? (T.rowSelected & 0x00FFFFFF | 0x55000000) // hover = 33% selection tint
				: isAbove ? 0xFF2A1A00 // warm amber tint = above-chars layer
				: (drawnCount % 2 == 0 ? T.rowEven : T.rowOdd);
			var rowBg = new FlxSprite(0, rowY).makeGraphic(LEFT_W, ROW_H, rowBgColor);
			rowBg.cameras = [camHUD];
			rowBg.scrollFactor.set();
			add(rowBg);
			layerRowsGroup.add(rowBg);
			_layerRowBgMap.set(elemIdx, rowBg); // store for hover-recolor (avoids full rebuild)
			layerHitData.push({
				x: 0,
				w: LEFT_W,
				y: rowY,
				h: ROW_H,
				idx: elemIdx,
				charId: null,
				zone: 'row'
			});

			// Eye toggle
			var eyeColor = isVisible ? T.success : T.textDim;
			var eyeTxt = new FlxText(4, rowY + 5, 16, isVisible ? '\u25CF' : '\u2013', 10);
			eyeTxt.setFormat(Paths.font('vcr.ttf'), 10, eyeColor, CENTER);
			eyeTxt.cameras = [camHUD];
			eyeTxt.scrollFactor.set();
			add(eyeTxt);
			layerTextsGroup.add(eyeTxt);
			layerHitData.push({
				x: 0,
				w: 22,
				y: rowY,
				h: ROW_H,
				idx: elemIdx,
				charId: null,
				zone: 'eye'
			});

			// Layer name
			var nameStr = elem.name ?? ('elem_' + elemIdx);
			if (nameStr.length > 14)
				nameStr = nameStr.substr(0, 12) + '..';
			var nameColor = isSelected ? T.accent : (isAbove ? 0xFFFFAA00 : T.textPrimary);
			var nameTxt = new FlxText(22, rowY + 6, 90, nameStr, 10);
			nameTxt.setFormat(Paths.font('vcr.ttf'), 10, nameColor, LEFT);
			nameTxt.cameras = [camHUD];
			nameTxt.scrollFactor.set();
			add(nameTxt);
			layerTextsGroup.add(nameTxt);

			// Type badge
			var typeStr = switch ((elem.type ?? 'sprite').toLowerCase())
			{
				case 'sprite': 'SPR';
				case 'animated': 'ANI';
				case 'atlas', 'animate_atlas', 'texture_atlas': 'ATL';
				case 'graphic': 'GFX';
				case 'backdrop': 'BKD';
				case 'group': 'GRP';
				case 'custom_class': 'CLS';
				case 'custom_class_group': 'CGP';
				case 'sound': 'SND';
				case 'character': 'CHR';
				default: (elem.type ?? 'SPR').toUpperCase().substr(0, 3);
			}
			var typeBgColor = switch ((elem.type ?? 'sprite').toLowerCase())
			{
				case 'animated': T.accentAlt;
				case 'atlas', 'animate_atlas', 'texture_atlas': 0xFF6A006A; // violeta — Texture Atlas
				case 'graphic': 0xFF5A3A00; // dark amber — solid colour rect
				case 'backdrop': 0xFF003A5A; // dark teal — tiling layer
				case 'group', 'custom_class_group': T.warning;
				case 'sound': T.success;
				case 'character': 0xFF0055AA;
				default: T.bgHover;
			}
			var typeBg = new FlxSprite(116, rowY + 5).makeGraphic(28, 16, typeBgColor);
			typeBg.cameras = [camHUD];
			typeBg.scrollFactor.set();
			add(typeBg);
			layerRowsGroup.add(typeBg);
			var typeTxt = new FlxText(116, rowY + 5, 28, typeStr, 8);
			typeTxt.setFormat(Paths.font('vcr.ttf'), 8, 0xFF000000, CENTER);
			typeTxt.cameras = [camHUD];
			typeTxt.scrollFactor.set();
			add(typeTxt);
			layerTextsGroup.add(typeTxt);

			// ▲ Above-Chars toggle — the KEY button for foreground layers
			// Shows "AB" (amber) when enabled, "ab" (dim) when disabled.
			var abBgColor = isAbove ? 0xFFFF8800 : T.bgHover;
			var abBg = new FlxSprite(148, rowY + 4).makeGraphic(20, 18, abBgColor);
			abBg.cameras = [camHUD];
			abBg.scrollFactor.set();
			add(abBg);
			layerRowsGroup.add(abBg);
			var abTxt = new FlxText(148, rowY + 5, 20, isAbove ? 'AB' : 'ab', 8);
			abTxt.setFormat(Paths.font('vcr.ttf'), 8, isAbove ? 0xFF000000 : T.textDim, CENTER);
			abTxt.cameras = [camHUD];
			abTxt.scrollFactor.set();
			add(abTxt);
			layerTextsGroup.add(abTxt);
			layerHitData.push({
				x: 145,
				w: 26,
				y: rowY,
				h: ROW_H,
				idx: elemIdx,
				charId: null,
				zone: 'above'
			});

			// ▲ Up
			var upBg = new FlxSprite(172, rowY + 4).makeGraphic(16, 18, T.bgHover);
			upBg.cameras = [camHUD];
			upBg.scrollFactor.set();
			add(upBg);
			layerRowsGroup.add(upBg);
			var upTxt = new FlxText(172, rowY + 4, 16, '\u25B2', 9);
			upTxt.setFormat(Paths.font('vcr.ttf'), 9, T.textSecondary, CENTER);
			upTxt.cameras = [camHUD];
			upTxt.scrollFactor.set();
			add(upTxt);
			layerTextsGroup.add(upTxt);
			layerHitData.push({
				x: 169,
				w: 22,
				y: rowY,
				h: ROW_H,
				idx: elemIdx,
				charId: null,
				zone: 'up'
			});

			// ▼ Down
			var downBg = new FlxSprite(191, rowY + 4).makeGraphic(16, 18, T.bgHover);
			downBg.cameras = [camHUD];
			downBg.scrollFactor.set();
			add(downBg);
			layerRowsGroup.add(downBg);
			var downTxt = new FlxText(191, rowY + 4, 16, '\u25BC', 9);
			downTxt.setFormat(Paths.font('vcr.ttf'), 9, T.textSecondary, CENTER);
			downTxt.cameras = [camHUD];
			downTxt.scrollFactor.set();
			add(downTxt);
			layerTextsGroup.add(downTxt);
			layerHitData.push({
				x: 188,
				w: 22,
				y: rowY,
				h: ROW_H,
				idx: elemIdx,
				charId: null,
				zone: 'down'
			});

			// ✕ Delete
			var delBg = new FlxSprite(211, rowY + 4).makeGraphic(22, 18, T.bgHover);
			delBg.cameras = [camHUD];
			delBg.scrollFactor.set();
			add(delBg);
			layerRowsGroup.add(delBg);
			var delTxt = new FlxText(211, rowY + 5, 22, '\u2715', 9);
			delTxt.setFormat(Paths.font('vcr.ttf'), 9, T.error, CENTER);
			delTxt.cameras = [camHUD];
			delTxt.scrollFactor.set();
			add(delTxt);
			layerTextsGroup.add(delTxt);
			layerHitData.push({
				x: 208,
				w: 26,
				y: rowY,
				h: ROW_H,
				idx: elemIdx,
				charId: null,
				zone: 'del'
			});

			// 🔒 Lock toggle — locked elements can't be selected/moved/deleted
			var isLocked = (elem.locked == true);
			var lockBgCol = isLocked ? 0xFFCC4400 : T.bgHover;
			var lockBg = new FlxSprite(237, rowY + 4).makeGraphic(16, 18, lockBgCol);
			lockBg.cameras = [camHUD];
			lockBg.scrollFactor.set();
			add(lockBg);
			layerRowsGroup.add(lockBg);
			var lockLabel = isLocked ? '\u{1F512}' : '\u{1F513}'; // 🔒 / 🔓 — fallback: L / -
			// Unicode emoji may not render in VCR font; use ASCII substitute
			var lockLabelAscii = isLocked ? 'LK' : '--';
			var lockTxt = new FlxText(237, rowY + 5, 16, lockLabelAscii, 8);
			lockTxt.setFormat(Paths.font('vcr.ttf'), 8, isLocked ? 0xFFFFDD88 : T.textDim, CENTER);
			lockTxt.cameras = [camHUD];
			lockTxt.scrollFactor.set();
			add(lockTxt);
			layerTextsGroup.add(lockTxt);
			layerHitData.push({
				x: 234,
				w: 20,
				y: rowY,
				h: ROW_H,
				idx: elemIdx,
				charId: null,
				zone: 'lock'
			});

			// Sprite-loaded indicator dot
			if (elem.name != null && elementSprites.exists(elem.name))
			{
				var dotColor = isLocked ? 0xFFCC4400 : T.success;
				var dot = new FlxSprite(LEFT_W - 10, rowY + 9).makeGraphic(6, 6, dotColor);
				dot.cameras = [camHUD];
				dot.scrollFactor.set();
				add(dot);
				layerRowsGroup.add(dot);
			}

			// Register all texts for this row so the drag system can hide them
			_layerRowTextsMap.set(elemIdx, [eyeTxt, nameTxt, typeTxt, abTxt, upTxt, downTxt, delTxt, lockTxt]);

			rowY += ROW_H;
			i--;
		}
	}

	// ── Row helpers used by refreshLayerPanel ─────────────────────────────────

	/** Draw a single character-anchor row (type:"character") in the layer panel. */
	function _drawCharAnchorRow(elemIdx:Int, rowY:Float):Void
	{
		var T = EditorTheme.current;
		var elem = stageData.elements[elemIdx];
		var slot = elem.charSlot ?? 'bf';
		var isSelected = (elemIdx == selectedIdx);
		var isHovered = (elemIdx == layerHoverIdx && !isSelected);

		// Color-code by character slot
		var slotColor = switch (slot.toLowerCase())
		{
			case 'gf', 'girlfriend', 'spectator': 0xFFFF88FF;
			case 'dad', 'opponent', 'player2':   0xFFFFAA00;
			default: 0xFF00D9FF; // bf / player
		};
		var rowBgBase = switch (slot.toLowerCase())
		{
			case 'gf', 'girlfriend', 'spectator': 0xFF2A002A;
			case 'dad', 'opponent', 'player2':   0xFF2A1A00;
			default: 0xFF002A3A; // bf
		};
		var rowBgColor = isSelected ? T.rowSelected
			: isHovered ? (rowBgBase | 0xAA000000)
			: rowBgBase;

		var rowBg = new FlxSprite(0, rowY).makeGraphic(LEFT_W, ROW_H, rowBgColor);
		rowBg.cameras = [camHUD];
		rowBg.scrollFactor.set();
		add(rowBg);
		layerRowsGroup.add(rowBg);
		layerHitData.push({x: 0, w: LEFT_W, y: rowY, h: ROW_H, idx: elemIdx, charId: slot, zone: 'row'});

		// Drag handle indicator
		var gripTxt = new FlxText(3, rowY + 6, 12, '\u2630', 9);
		gripTxt.setFormat(Paths.font('vcr.ttf'), 9, slotColor, CENTER);
		gripTxt.cameras = [camHUD];
		gripTxt.scrollFactor.set();
		add(gripTxt);
		layerTextsGroup.add(gripTxt);

		// Char slot label (e.g. "⬤ BF")
		var slotLabel = '\u25CF ' + switch (slot.toLowerCase())
		{
			case 'gf', 'girlfriend', 'spectator': 'GF';
			case 'dad', 'opponent', 'player2':   'DAD';
			default: 'BF';
		};
		var labelTxt = new FlxText(16, rowY + 6, 70, slotLabel, 10);
		labelTxt.setFormat(Paths.font('vcr.ttf'), 10, slotColor, LEFT);
		labelTxt.cameras = [camHUD];
		labelTxt.scrollFactor.set();
		add(labelTxt);
		layerTextsGroup.add(labelTxt);

		// "CHAR" type badge
		var badgeBg = new FlxSprite(88, rowY + 5).makeGraphic(34, 16, slotColor);
		badgeBg.cameras = [camHUD];
		badgeBg.scrollFactor.set();
		add(badgeBg);
		layerRowsGroup.add(badgeBg);
		var badgeTxt = new FlxText(88, rowY + 5, 34, 'CHAR', 8);
		badgeTxt.setFormat(Paths.font('vcr.ttf'), 8, 0xFF000000, CENTER);
		badgeTxt.cameras = [camHUD];
		badgeTxt.scrollFactor.set();
		add(badgeTxt);
		layerTextsGroup.add(badgeTxt);

		// Position of the live character (if loaded)
		var c = characters.get(switch (slot.toLowerCase())
		{
			case 'gf', 'girlfriend', 'spectator': 'gf';
			case 'dad', 'opponent', 'player2':   'dad';
			default: 'bf';
		});
		var posStr = c != null ? 'x:${Std.int(c.x)} y:${Std.int(c.y)}' : '';
		var posTxt = new FlxText(126, rowY + 7, 90, posStr, 8);
		posTxt.setFormat(Paths.font('vcr.ttf'), 8, T.textDim, LEFT);
		posTxt.cameras = [camHUD];
		posTxt.scrollFactor.set();
		add(posTxt);
		layerTextsGroup.add(posTxt);

		// ✕ Delete anchor
		var delBg = new FlxSprite(LEFT_W - 24, rowY + 4).makeGraphic(20, 18, T.bgHover);
		delBg.cameras = [camHUD];
		delBg.scrollFactor.set();
		add(delBg);
		layerRowsGroup.add(delBg);
		var delTxt = new FlxText(LEFT_W - 24, rowY + 5, 20, '\u2715', 9);
		delTxt.setFormat(Paths.font('vcr.ttf'), 9, T.error, CENTER);
		delTxt.cameras = [camHUD];
		delTxt.scrollFactor.set();
		add(delTxt);
		layerTextsGroup.add(delTxt);
		layerHitData.push({x: LEFT_W - 26, w: 26, y: rowY, h: ROW_H, idx: elemIdx, charId: slot, zone: 'del'});
	}

	// ─────────────────────────────────────────────────────────────────────────
	// RIGHT PANEL (CoolTabMenu)
	// ─────────────────────────────────────────────────────────────────────────

	function buildRightPanel():Void
	{
		var T = EditorTheme.current;
		var panelH = FlxG.height - TOP_H - STATUS_H;
		var panelX = FlxG.width - RIGHT_W;

		// ── Shared background + border (reused by both panels) ─────────────────
		_rightPanelBg = new FlxSprite(panelX, TOP_H).makeGraphic(RIGHT_W, panelH, T.bgPanel);
		_rightPanelBg.cameras = [camHUD];
		_rightPanelBg.scrollFactor.set();
		add(_rightPanelBg);

		_rightPanelBorder = new FlxSprite(panelX, TOP_H).makeGraphic(2, panelH, T.borderColor);
		_rightPanelBorder.alpha = 0.5;
		_rightPanelBorder.cameras = [camHUD];
		_rightPanelBorder.scrollFactor.set();
		add(_rightPanelBorder);

		// Store the in-edit X for panels so _toggleEditorMode can restore it.
		_rightPanelEditX = panelX + 2;

		// ── rightPanel: Stage / Shaders (no selection) ───────────────────────
		// No SEL_INFO_H gap: visible only when nothing is selected.
		var tabsMain = [
			{name: 'Stage',   label: 'Stage'},
			{name: 'Shaders', label: 'Shaders'}
		];
		rightPanel = new CoolTabMenu(null, tabsMain, true);
		rightPanel.resize(RIGHT_W - 2, panelH);
		rightPanel.x = panelX + 2;
		rightPanel.y = TOP_H;
		rightPanel.scrollFactor.set();
		rightPanel.cameras = [camHUD];
		add(rightPanel);

		buildStageTab();
		buildShadersTab();

		// ── _contextPanel: Element / Anims (has selection) ────────────────────
		// Starts SEL_INFO_H below TOP_H to leave room for the info bar.
		var tabsCtx = [
			{name: 'Element', label: 'Element'},
			{name: 'Anims',   label: 'Anims'}
		];
		_contextPanel = new CoolTabMenu(null, tabsCtx, true);
		_contextPanel.resize(RIGHT_W - 2, panelH - SEL_INFO_H);
		_contextPanel.x = panelX + 2;
		_contextPanel.y = TOP_H + SEL_INFO_H;
		_contextPanel.scrollFactor.set();
		_contextPanel.cameras = [camHUD];
		add(_contextPanel);

		buildElementTab();
		buildAnimsTab();

		// IMPORTANT: build tabs with the panel on-screen so CoolTabMenu computes
		// widget positions correctly.  Then push it off-screen via x-offset (same
		// mechanism used by _updatePanelVisibility).  Do NOT use visible=false —
		// that corrupts CoolTabMenu's internal tab-selection state and causes all
		// tab contents to render simultaneously when the panel is later shown.
		_contextPanel.x = RIGHT_PANEL_HIDE_X;

		// ── Anims tab header mask ────────────────────────────────────────────────
		// CoolTabMenu sorts tabs alphabetically: Anims=left half, Element=right half.
		// This sprite covers the "Anims" tab header with the panel background colour
		// so it appears absent for types that don't support animations.
		var tabHeaderH = 22;
		var tabW = Std.int((RIGHT_W - 2) / 2);
		_animTabMask = new FlxSprite(panelX + 2, TOP_H + SEL_INFO_H)
			.makeGraphic(tabW, tabHeaderH, T.bgPanel);
		_animTabMask.cameras = [camHUD];
		_animTabMask.scrollFactor.set();
		_animTabMask.visible = false; // hidden by default; shown for non-anim types
		add(_animTabMask);

		// The animation list groups must be added to the state (not to coolui.CoolUIGroup tab,
		// which only accepts FlxSprite). Sprites inside use absolute screen coords + camHUD.
		if (animListBg != null)
		{
			animListBg.cameras = [camHUD];
			add(animListBg);
		}
		if (animListText != null)
		{
			animListText.cameras = [camHUD];
			add(animListText);
		}
	}

	// ── Element Tab ───────────────────────────────────────────────────────────
	//
	//  Reorganised layout (2025 UX pass):
	//
	//  ┌─ ◈ IDENTITY ──────────────────────────────────────────────────────┐
	//  │  Name input          │  Type dropdown                             │
	//  ├─ ◈ ASSET / GRAPHIC ──────────────────────────────────────────────┤  (type-dependent)
	//  │  path input + Browse  OR  Width / Height / FillColor              │
	//  ├─ ◈ TRANSFORM ────────────────────────────────────────────────────┤
	//  │  X / Y  │  ScaleX / ScaleY  │  Angle  │  ScrollX / ScrollY       │
	//  ├─ ◈ DISPLAY ──────────────────────────────────────────────────────┤
	//  │  Alpha  │  Z-Index  │  Color  │  FlipX/Y  │  AA  │  Visible      │
	//  ├─ ◈ LAYER ────────────────────────────────────────────────────────┤
	//  │  Above Characters checkbox                                        │
	//  ├─ ◈ BACKDROP (only for backdrop type) ────────────────────────────┤
	//  │  RepeatX/Y  │  VelX/Y                                            │
	//  └───────────────────────────────────────────────────────────────────┘
	//  [ Apply Changes ]

	function buildElementTab():Void
	{
		var tab = new coolui.CoolUIGroup();
		tab.name = 'Element';

		var T = EditorTheme.current;
		var y = 6.0;
		var W = RIGHT_W - 16; // usable inner width

		// ── Local helpers ──────────────────────────────────────────────────────
		function lbl(text:String, lx:Float, ly:Float, ?w:Int):FlxText
		{
			var t = new FlxText(lx, ly, w ?? 0, text, 9);
			t.color = FlxColor.fromInt(T.textSecondary);
			tab.add(t);
			return t;
		}

		/** Full-width section header with accent colour stripe. */
		function sectionHeader(title:String, headerY:Float, col:Int):Void
		{
			var bg = new FlxSprite(4, headerY).makeGraphic(W + 8, 18, T.bgPanelAlt);
			tab.add(bg);
			var stripe = new FlxSprite(4, headerY).makeGraphic(3, 18, col);
			tab.add(stripe);
			var t = new FlxText(10, headerY + 3, W, title, 9);
			t.setFormat(Paths.font('vcr.ttf'), 9, col, LEFT);
			tab.add(t);
		}

		function thinSep(sy:Float):Void
		{
			var s = new FlxSprite(4, sy).makeGraphic(W + 8, 1, T.borderColor);
			s.alpha = 0.18;
			tab.add(s);
		}

		// ══════════════════════════════════════════════════════════════════
		// ◈ IDENTITY
		// ══════════════════════════════════════════════════════════════════
		sectionHeader('\u25C8 IDENTITY', y, T.accent);
		y += 22;

		lbl('Name', 8, y);
		elemNameInput = new CoolInputText(8, y + 12, W - 2, '', 10);
		tab.add(elemNameInput);
		y += 30;

		lbl('Type', 8, y);
		var types = ['sprite', 'animated', 'atlas', 'graphic', 'backdrop', 'group', 'custom_class', 'sound'];
		elemTypeDropdown = new CoolDropDown(8, y + 12, CoolDropDown.makeStrIdLabelArray(types, true), function(sel:String)
		{
			var t = types[Std.parseInt(sel)];
			if (selectedIdx >= 0 && selectedIdx < stageData.elements.length)
			{
				stageData.elements[selectedIdx].type = t;
				_updateSelectionInfoBar(); // refresh type badge in info bar
			}
			_updateTypeWidgets(t);
		});
		tab.add(elemTypeDropdown);
		y += 36;

		// ══════════════════════════════════════════════════════════════════
		// ◈ ASSET  (mutually exclusive with GRAPHIC PROPERTIES)
		// ══════════════════════════════════════════════════════════════════
		thinSep(y); y += 4;
		sectionHeader('\u25C8 ASSET', y, 0xFF88BBFF);
		y += 22;

		_assetWidgets = [];
		_graphicWidgets = [];

		// -- Asset path row
		var assetPathLbl = lbl('Path', 8, y);
		_assetWidgets.push(assetPathLbl);

		elemAssetInput = new CoolInputText(8, y + 12, W - 50, '', 10);
		tab.add(elemAssetInput);
		_assetWidgets.push(elemAssetInput);

		var browseBtn = new CoolButton(W - 36, y + 11, 'Browse', browseAsset);
		tab.add(browseBtn);
		_assetWidgets.push(browseBtn);
		y += 32;

		// -- Graphic-specific: Width / Height / Fill colour
		// (placed at the same vertical slot as the asset row — only one is visible)
		// rewind y so they overlap with the asset block
		y -= 32;

		var gfxHdr = new FlxText(8, y, 0, '\u25A0 FILL SIZE & COLOR', 9);
		gfxHdr.color = FlxColor.fromInt(0xFFFFAA33);
		tab.add(gfxHdr);
		_graphicWidgets.push(gfxHdr);
		y += 14;

		lbl('W', 8, y);
		lbl('H', 130, y);
		graphicWidthStepper  = new CoolNumericStepper(8,   y + 10, 1, 100, 1, 8192, 0);
		graphicHeightStepper = new CoolNumericStepper(130, y + 10, 1, 100, 1, 8192, 0);
		tab.add(graphicWidthStepper);
		tab.add(graphicHeightStepper);
		_graphicWidgets.push(graphicWidthStepper);
		_graphicWidgets.push(graphicHeightStepper);
		y += 26;

		var gfxColLbl = lbl('Fill colour (hex)', 8, y);
		_graphicWidgets.push(gfxColLbl);
		graphicFillColorInput = new CoolInputText(8, y + 10, 120, '#FFFFFF', 10);
		tab.add(graphicFillColorInput);
		_graphicWidgets.push(graphicFillColorInput);
		y += 26;

		// advance past the taller block
		y += 4; // small gap before next section

		// ══════════════════════════════════════════════════════════════════
		// ◈ TRANSFORM
		// ══════════════════════════════════════════════════════════════════
		thinSep(y); y += 4;
		sectionHeader('\u25C8 TRANSFORM', y, 0xFF88FFBB);
		y += 22;

		// Position row
		lbl('X', 8, y);
		lbl('Y', 130, y);
		elemXStepper = new CoolNumericStepper(8,   y + 10, 10, 0, -4000, 4000, 0);
		elemYStepper = new CoolNumericStepper(130, y + 10, 10, 0, -4000, 4000, 0);
		tab.add(elemXStepper);
		tab.add(elemYStepper);
		y += 26;

		// Scale row
		lbl('Scale X', 8, y);
		lbl('Scale Y', 130, y);
		elemScaleXStepper = new CoolNumericStepper(8,   y + 10, 0.1, 1, 0.01, 20, 2);
		elemScaleYStepper = new CoolNumericStepper(130, y + 10, 0.1, 1, 0.01, 20, 2);
		tab.add(elemScaleXStepper);
		tab.add(elemScaleYStepper);
		y += 26;

		// Angle + Z-Index on same row
		lbl('Angle', 8, y);
		lbl('Z-Index', 130, y);
		elemAngleStepper  = new CoolNumericStepper(8,   y + 10, 1,  0, -360, 360, 1);
		elemZIndexStepper = new CoolNumericStepper(130, y + 10, 1,  0, -100, 100, 0);
		tab.add(elemAngleStepper);
		tab.add(elemZIndexStepper);
		y += 26;

		// Scroll factor row
		lbl('Scroll X', 8, y);
		lbl('Scroll Y', 130, y);
		elemScrollXStepper = new CoolNumericStepper(8,   y + 10, 0.1, 1, 0, 5, 2);
		elemScrollYStepper = new CoolNumericStepper(130, y + 10, 0.1, 1, 0, 5, 2);
		tab.add(elemScrollXStepper);
		tab.add(elemScrollYStepper);
		y += 28;

		// ══════════════════════════════════════════════════════════════════
		// ◈ DISPLAY
		// ══════════════════════════════════════════════════════════════════
		thinSep(y); y += 4;
		sectionHeader('\u25C8 DISPLAY', y, 0xFFFFCC44);
		y += 22;

		// Alpha + Color on same row
		lbl('Alpha', 8, y);
		lbl('Color (hex)', 130, y);
		elemAlphaStepper = new CoolNumericStepper(8,   y + 10, 0.05, 1, 0, 1, 2);
		elemColorInput   = new CoolInputText(130, y + 10, 110, '#FFFFFF', 10);
		tab.add(elemAlphaStepper);
		tab.add(elemColorInput);
		y += 26;

		// Bool checkboxes — two per row
		elemFlipXCheck        = new CoolCheckBox(8,   y, null, null, 'Flip X', 70);
		elemFlipYCheck        = new CoolCheckBox(90,  y, null, null, 'Flip Y', 70);
		elemAntialiasingCheck = new CoolCheckBox(8,   y + 20, null, null, 'Antialiasing', 110);
		elemVisibleCheck      = new CoolCheckBox(130, y + 20, null, null, 'Visible', 80);
		tab.add(elemFlipXCheck);
		tab.add(elemFlipYCheck);
		tab.add(elemAntialiasingCheck);
		tab.add(elemVisibleCheck);
		y += 42;

		// ══════════════════════════════════════════════════════════════════
		// ◈ LAYER
		// ══════════════════════════════════════════════════════════════════
		thinSep(y); y += 4;
		sectionHeader('\u25C8 LAYER', y, 0xFFFFAA00);
		y += 22;

		elemAboveCharsCheck = new CoolCheckBox(8, y, null, null, '\u25B2 Above Characters (foreground)', W);
		elemAboveCharsCheck.color = 0xFFFFAA00;
		tab.add(elemAboveCharsCheck);
		y += 24;

		// Apply button
		thinSep(y); y += 6;
		var applyBtn = new CoolButton(8, y, 'Apply Changes  \u21B5', applyElementProps);
		tab.add(applyBtn);
		y += 30;

		// ══════════════════════════════════════════════════════════════════
		// ◈ BACKDROP PROPERTIES  (type-conditional)
		// ══════════════════════════════════════════════════════════════════
		_backdropWidgets = [];

		var bdSep = new FlxSprite(4, y).makeGraphic(W + 8, 1, T.borderColor);
		bdSep.alpha = 0.18;
		tab.add(bdSep);
		_backdropWidgets.push(bdSep);
		y += 4;

		var bdHdrBg = new FlxSprite(4, y).makeGraphic(W + 8, 18, T.bgPanelAlt);
		tab.add(bdHdrBg);
		_backdropWidgets.push(bdHdrBg);
		var bdStripe = new FlxSprite(4, y).makeGraphic(3, 18, T.accentAlt);
		tab.add(bdStripe);
		_backdropWidgets.push(bdStripe);
		var bdHeader = new FlxText(10, y + 3, W, '\u25C8 BACKDROP PROPERTIES', 9);
		bdHeader.setFormat(Paths.font('vcr.ttf'), 9, T.accentAlt, LEFT);
		tab.add(bdHeader);
		_backdropWidgets.push(bdHeader);
		y += 22;

		backdropRepeatXCheck = new CoolCheckBox(8,   y, null, null, 'Repeat X', 80);
		backdropRepeatYCheck = new CoolCheckBox(110, y, null, null, 'Repeat Y', 80);
		backdropRepeatXCheck.checked = true;
		backdropRepeatYCheck.checked = true;
		tab.add(backdropRepeatXCheck);
		tab.add(backdropRepeatYCheck);
		_backdropWidgets.push(backdropRepeatXCheck);
		_backdropWidgets.push(backdropRepeatYCheck);
		y += 22;

		var bdVLblX = lbl('Vel X', 8, y);
		var bdVLblY = lbl('Vel Y', 130, y);
		_backdropWidgets.push(bdVLblX);
		_backdropWidgets.push(bdVLblY);
		backdropVelXStepper = new CoolNumericStepper(8,   y + 10, 5, 0, -500, 500, 1);
		backdropVelYStepper = new CoolNumericStepper(130, y + 10, 5, 0, -500, 500, 1);
		tab.add(backdropVelXStepper);
		tab.add(backdropVelYStepper);
		_backdropWidgets.push(backdropVelXStepper);
		_backdropWidgets.push(backdropVelYStepper);

		// Default visibility states
		_setBackdropPanelVisible(false);
		_setGraphicPanelVisible(false);
		for (w in _assetWidgets) if (w != null) w.visible = true;

		_contextPanel.addGroup(tab);
	}

	// ── Animations Tab ────────────────────────────────────────────────────────

	function buildAnimsTab():Void
	{
		var tab = new coolui.CoolUIGroup();
		tab.name = 'Anims';

		var T = EditorTheme.current;
		var y = 8.0;

		// Helper: add to tab AND track in _animTabWidgets so visibility can be toggled per type.
		function track(w:flixel.FlxBasic):flixel.FlxBasic
		{
			tab.add(cast w);
			_animTabWidgets.push(w);
			return w;
		}

		// Animation list placeholder background (the actual rows live in animListBg / animListText
		// which are state-level groups; they are gated separately via _animTabVisible).
		track(new FlxSprite(4, y).makeGraphic(RIGHT_W - 16, 140, T.bgPanelAlt));

		animListBg   = new FlxTypedGroup<FlxSprite>();
		animListText = new FlxTypedGroup<FlxText>();
		// Groups are added to the state directly in buildRightPanel (coolui.CoolUIGroup only accepts FlxSprite)

		track(new CoolButton(4,            y + 144, '+ Add Anim', addAnimation));
		track(new CoolButton(RIGHT_W - 86, y + 144, 'Remove',     removeAnimation));

		y += 172;
		var sep = new FlxSprite(4, y).makeGraphic(RIGHT_W - 16, 1, T.borderColor);
		sep.alpha = 0.25;
		track(sep);
		y += 8;

		function lbl(t:String, ly:Float):Void
		{
			var tx = new FlxText(8, ly, 0, t, 10);
			tx.color = T.textSecondary;
			track(tx);
		}

		lbl('Animation Name:', y);
		animNameInput = cast track(new CoolInputText(8, y + 12, 180, 'idle', 10));

		y += 32;
		lbl('XML Prefix:', y);
		animPrefixInput = cast track(new CoolInputText(8, y + 12, 180, 'idle0', 10));

		y += 32;
		lbl('FPS:', y);
		animFPSStepper = cast track(new CoolNumericStepper(8, y + 12, 1, 24, 1, 120, 0));
		animLoopCheck  = cast track(new CoolCheckBox(90, y + 12, null, null, 'Looped', 80));

		y += 34;
		lbl('Indices (e.g. 0,1,2):', y);
		animIndicesInput = cast track(new CoolInputText(8, y + 12, 180, '', 10));

		y += 32;
		lbl('Anim Type:', y);
		var animTypes = ['default', 'each_beat'];
		animTypeDropdown = cast track(new CoolDropDown(8, y + 12, CoolDropDown.makeStrIdLabelArray(animTypes, true), null));
		animTypeDropdown.selectedLabel = 'default';

		y += 36;
		lbl('First Animation:', y);
		animFirstInput = cast track(new CoolInputText(8, y + 12, 180, 'idle', 10));

		y += 32;
		track(new CoolButton(8, y, 'Save Anim Data', saveAnimData));

		_contextPanel.addGroup(tab);
	}

	// ── Stage Tab ─────────────────────────────────────────────────────────────

	function buildStageTab():Void
	{
		var tab = new coolui.CoolUIGroup();
		tab.name = 'Stage';

		var T = EditorTheme.current;
		var y = 8.0;
		function lbl(t:String, ly:Float)
		{
			var tx = new FlxText(8, ly, 0, t, 10);
			tx.color = T.textSecondary;
			tab.add(tx);
		}

		lbl('Stage Name:', y);
		stageNameInput = new CoolInputText(8, y + 12, 180, stageData.name, 10);
		tab.add(stageNameInput);

		y += 32;
		lbl('Default Zoom:', y);
		stageZoomStepper = new CoolNumericStepper(8, y + 12, 0.05, stageData.defaultZoom, 0.1, 5.0, 2);
		tab.add(stageZoomStepper);

		y += 32;
		stagePixelCheck = new CoolCheckBox(8, y, null, null, 'Pixel Stage', 120);
		stageHideGFCheck = new CoolCheckBox(8, y + 22, null, null, 'Hide Girlfriend', 130);
		stagePixelCheck.checked = stageData.isPixelStage;
		stageHideGFCheck.checked = stageData.hideGirlfriend ?? false;
		tab.add(stagePixelCheck);
		tab.add(stageHideGFCheck);

		y += 52;
		var applyStageBtn = new CoolButton(8, y, 'Apply Stage Props', applyStageProps);
		tab.add(applyStageBtn);

		y += 30;
		var sep = new FlxSprite(4, y).makeGraphic(RIGHT_W - 16, 1, T.borderColor);
		sep.alpha = 0.25;
		tab.add(sep);
		y += 8;

		lbl('Scripts (one per line):', y);
		y += 14;
		var scriptsInfo = new FlxText(8, y, RIGHT_W - 24,
			(stageData.scripts != null && stageData.scripts.length > 0) ? stageData.scripts.join('\n') : '(none)', 9);
		scriptsInfo.color = T.textDim;
		tab.add(scriptsInfo);

		y += Std.int(scriptsInfo.textField.textHeight) + 8;
		var addScriptBtn = new CoolButton(8, y, '+ Add Script Path', addScript);
		tab.add(addScriptBtn);

		y += 30;
		var reloadBtn = new CoolButton(8, y, 'Reload Stage View', reloadStageView);
		tab.add(reloadBtn);

		rightPanel.addGroup(tab);
	}

	// ── Characters Tab ────────────────────────────────────────────────────────

	function buildCharsTab():Void
	{
		var tab = new coolui.CoolUIGroup();
		tab.name = 'Chars';

		var T = EditorTheme.current;
		var y = 8.0;

		function sectionHeader(text:String, ly:Float, col:Int):Void
		{
			var bg = new FlxSprite(4, ly).makeGraphic(RIGHT_W - 16, 18, T.bgPanelAlt);
			tab.add(bg);
			var tx = new FlxText(8, ly + 2, 0, text, 10);
			tx.setFormat(Paths.font('vcr.ttf'), 10, col, LEFT);
			tab.add(tx);
		}
		function lbl(t:String, ly:Float)
		{
			var tx = new FlxText(8, ly, 0, t, 9);
			tx.color = T.textSecondary;
			tab.add(tx);
		}

		var bfPos = stageData.boyfriendPosition ?? [770.0, 450.0];
		var gfPos = stageData.gfPosition ?? [400.0, 130.0];
		var dadPos = stageData.dadPosition ?? [100.0, 100.0];
		var camBF = stageData.cameraBoyfriend ?? [0.0, 0.0];
		var camDad = stageData.cameraDad ?? [0.0, 0.0];

		sectionHeader('BOYFRIEND', y, 0xFF00D9FF);
		y += 22;
		lbl('X:', y);
		lbl('Y:', y + 20);
		bfXStepper = new CoolNumericStepper(16, y + 12, 10, bfPos[0], -2000, 4000, 0);
		bfYStepper = new CoolNumericStepper(130, y + 12, 10, bfPos[1], -2000, 4000, 0);
		tab.add(bfXStepper);
		tab.add(bfYStepper);
		y += 26;
		lbl('Cam Offset X:', y);
		lbl('Y:', y + 20);
		camBFXStepper = new CoolNumericStepper(80, y + 12, 10, camBF[0], -500, 500, 0);
		camBFYStepper = new CoolNumericStepper(165, y + 12, 10, camBF[1], -500, 500, 0);
		tab.add(camBFXStepper);
		tab.add(camBFYStepper);

		y += 34;
		sectionHeader('GIRLFRIEND', y, 0xFFFF88FF);
		y += 22;
		lbl('X:', y);
		lbl('Y:', y + 20);
		gfXStepper = new CoolNumericStepper(16, y + 12, 10, gfPos[0], -2000, 4000, 0);
		gfYStepper = new CoolNumericStepper(130, y + 12, 10, gfPos[1], -2000, 4000, 0);
		tab.add(gfXStepper);
		tab.add(gfYStepper);

		lbl('GF Version:', y + 24);
		gfVersionInput = new CoolInputText(8, y + 36, 120, stageData.gfVersion ?? 'gf', 10);
		tab.add(gfVersionInput);

		y += 60;
		sectionHeader('DAD / OPPONENT', y, 0xFFFFAA00);
		y += 22;
		lbl('X:', y);
		lbl('Y:', y + 20);
		dadXStepper = new CoolNumericStepper(16, y + 12, 10, dadPos[0], -2000, 4000, 0);
		dadYStepper = new CoolNumericStepper(130, y + 12, 10, dadPos[1], -2000, 4000, 0);
		tab.add(dadXStepper);
		tab.add(dadYStepper);
		y += 26;
		lbl('Cam Offset X:', y);
		lbl('Y:', y + 20);
		camDadXStepper = new CoolNumericStepper(80, y + 12, 10, camDad[0], -500, 500, 0);
		camDadYStepper = new CoolNumericStepper(165, y + 12, 10, camDad[1], -500, 500, 0);
		tab.add(camDadXStepper);
		tab.add(camDadYStepper);

		y += 36;
		var applyBtn = new CoolButton(8, y, 'Apply + Reload Chars', applyCharProps);
		tab.add(applyBtn);

		rightPanel.addGroup(tab);
	}

	// ── Shaders Tab ───────────────────────────────────────────────────────────

	function buildShadersTab():Void
	{
		var tab = new coolui.CoolUIGroup();
		tab.name = 'Shaders';

		var T = EditorTheme.current;
		var y = 8.0;

		// ── Header ────────────────────────────────────────────────────────────
		var info = new FlxText(8, y, RIGHT_W - 20,
			'Assign, create and tune shaders per element. All changes preview live.', 10);
		info.color = T.textSecondary;
		tab.add(info);
		y += 26;

		// Row 1: Refresh + Import
		var refreshBtn = new CoolButton(8, y, 'Refresh', function()
		{
			ShaderManager.scanShaders();
			_shaderList = ['(none)'].concat(ShaderManager.getAvailableShaders());
			var labels = CoolDropDown.makeStrIdLabelArray(_shaderList, true);
			if (stageShaderDropdown != null) stageShaderDropdown.setData(labels);
			if (elemShaderDropdown   != null) elemShaderDropdown.setData(labels);
			setStatus('Shaders rescanned: ${_shaderList.length - 1} found');
		});
		tab.add(refreshBtn);

		var importBtn = new CoolButton(RIGHT_W - 136, y, '+ Import .frag', _importShader);
		tab.add(importBtn);
		y += 28;

		// Row 2: New shader + Edit current
		var newBtn = new CoolButton(8, y, 'New Shader', function() _openShaderEditor(null));
		tab.add(newBtn);

		var editBtn = new CoolButton(RIGHT_W - 136, y, 'Edit Selected .frag', function()
		{
			// Find which shader is currently shown in the element dropdown
			var shName:String = null;
			if (selectedIdx >= 0 && selectedIdx < stageData.elements.length)
			{
				var elem = stageData.elements[selectedIdx];
				if (elem.customProperties != null)
				{
					var sh = Reflect.field(elem.customProperties, 'shader');
					if (sh != null && Std.string(sh) != '' && Std.string(sh) != '(none)')
						shName = Std.string(sh);
				}
			}
			_openShaderEditor(shName);
		});
		tab.add(editBtn);
		y += 28;

		function sep(sy:Float):Void
		{
			var s = new FlxSprite(4, sy).makeGraphic(RIGHT_W - 16, 1, T.borderColor);
			s.alpha = 0.3;
			tab.add(s);
		}

		sep(y); y += 8;

		// ── Stage-level shader ────────────────────────────────────────────────
		var lbl1 = new FlxText(8, y, 0, 'Stage Shader:', 10);
		lbl1.color = T.accent;
		tab.add(lbl1);
		y += 14;

		_shaderList = ['(none)'].concat(ShaderManager.getAvailableShaders());
		var labels = CoolDropDown.makeStrIdLabelArray(_shaderList, true);

		stageShaderDropdown = new CoolDropDown(8, y, labels, function(id:String)
		{
			var idx = Std.parseInt(id);
			if (idx == null) return;
			var name = _shaderList[idx];
			if (stageData.customProperties == null) stageData.customProperties = {};
			Reflect.setField(stageData.customProperties, 'shader', name == '(none)' ? '' : name);
			markUnsaved();
			saveHistory();
			setStatus(name == '(none)' ? 'Stage shader removed' : 'Stage shader: $name');
		});
		stageShaderDropdown.selectedLabel = _shaderList[0];
		y += 36;

		sep(y); y += 8;

		// ── Element shader ────────────────────────────────────────────────────
		var lbl2 = new FlxText(8, y, 0, 'Selected Element Shader:', 10);
		lbl2.color = T.accentAlt;
		tab.add(lbl2);
		y += 14;

		elemShaderDropdown = new CoolDropDown(8, y, labels, function(id:String)
		{
			if (selectedIdx < 0 || selectedIdx >= stageData.elements.length) return;
			var idx = Std.parseInt(id);
			if (idx == null) return;
			var name = _shaderList[idx];

			var elem = stageData.elements[selectedIdx];
			if (elem.customProperties == null) elem.customProperties = {};
			Reflect.setField(elem.customProperties, 'shader', name == '(none)' ? '' : name);

			// Live preview
			if (elem.name != null && elementSprites.exists(elem.name))
			{
				var spr = elementSprites.get(elem.name);
				if (spr.cameras == null || spr.cameras.length == 0) spr.cameras = [camGame];
				try
				{
					if (name == '(none)' || name == '')
						ShaderManager.removeShader(spr);
					else
						ShaderManager.applyShader(spr, name, camGame);
				}
				catch (e:Dynamic) { setStatus('Shader error: $e'); return; }
			}
			markUnsaved();
			saveHistory();
			setStatus(name == '(none)' ? 'Shader removed from element' : 'Shader "$name" applied live');
		});
		elemShaderDropdown.selectedLabel = _shaderList[0];
		y += 36;

		// Remove shader + Params substate buttons
		var removeBtn = new CoolButton(8, y, 'x Remove', function()
		{
			if (selectedIdx < 0 || selectedIdx >= stageData.elements.length) return;
			var elem = stageData.elements[selectedIdx];
			if (elem.customProperties != null) Reflect.setField(elem.customProperties, 'shader', '');
			if (elem.name != null && elementSprites.exists(elem.name))
				ShaderManager.removeShader(elementSprites.get(elem.name));
			elemShaderDropdown.selectedLabel = '(none)';
			markUnsaved();
			saveHistory();
			setStatus('Shader removed');
		});
		tab.add(removeBtn);

		var paramsBtn = new CoolButton(RIGHT_W - 132, y, '* Shader Params', _openShaderParams);
		tab.add(paramsBtn);
		y += 28;

		var note = new FlxText(8, y, RIGHT_W - 20,
			'Shaders live in assets/shaders/*.frag\nor mods/<id>/shaders/*.frag', 9);
		note.color = T.textDim;
		tab.add(note);

		tab.add(elemShaderDropdown);
		tab.add(stageShaderDropdown);

		rightPanel.addGroup(tab);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// UPDATE
	// ─────────────────────────────────────────────────────────────────────────

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		handleKeyboard();
		handleCameraMovement(elapsed);
		handleLayerPanelClick();
		handleLayerDrag();
		handleCanvasDrag();
		handleToolbarClick();
		updateSelectionBox();
		updateCharLabels();
		updateStatusBar();

		// Track which context-panel tab is selected to show/hide the animation list overlay.
		// _contextPanel has 2 tabs (Element, Anims) sorted alphabetically → Anims=0, Element=1.
		// Tab header sits at y ≈ TOP_H + SEL_INFO_H, height ≈ 20px. 2 tabs share RIGHT_W-2 px.
		if (FlxG.mouse.justPressed && _contextPanel != null && _contextPanel.visible)
		{
			var mx = FlxG.mouse.gameX;
			var my = FlxG.mouse.gameY;
			var tabY = TOP_H + SEL_INFO_H;
			if (my >= tabY && my <= tabY + 22 && mx >= FlxG.width - RIGHT_W)
			{
				var tabW:Float = (RIGHT_W - 2) / 2;
				var ti = Std.int((mx - (FlxG.width - RIGHT_W + 2)) / tabW);
				// CoolTabMenu sorts tabs alphabetically: [Anims=0, Element=1]
				_animTabVisible = (ti == 0);
			}
		}
		// CoolTabMenu restores visible=true on all widgets of the active tab every time
		// a tab is switched. Re-enforce type-specific visibility every frame so backdrop/
		// graphic/asset sections never bleed through for types that shouldn't show them.
		if (_contextPanel != null && _contextPanel.x == _rightPanelEditX
			&& selectedIdx >= 0 && selectedIdx < stageData.elements.length)
			_updateTypeWidgets(stageData.elements[selectedIdx].type ?? 'sprite');
		// Hide anim list when context panel is not visible
		if (_contextPanel != null && !_contextPanel.visible)
			_animTabVisible = false;
		// Hide anim list when the current element type doesn't support animations
		if (_animTabVisible && selectedIdx >= 0 && selectedIdx < stageData.elements.length)
		{
			var _curType = stageData.elements[selectedIdx].type ?? '';
			if (_curType != 'animated' && _curType != 'sprite')
				_animTabVisible = false;
		}
		if (animListBg != null)
			animListBg.visible = _animTabVisible;
		if (animListText != null)
			animListText.visible = _animTabVisible;
	}

	function handleKeyboard():Void
	{
		// Si el usuario está escribiendo en un input, no disparar shortcuts ni nudge
		if (isTyping())
			return;

		// Tab key toggles edit/view mode
		if (FlxG.keys.justPressed.TAB)
		{
			_toggleEditorMode();
			return;
		}

		if (FlxG.keys.pressed.CONTROL)
		{
			if (FlxG.keys.justPressed.Z)
			{
				undo();
				return;
			}
			if (FlxG.keys.justPressed.Y)
			{
				redo();
				return;
			}
			if (FlxG.keys.justPressed.C)
			{
				copyElement();
				return;
			}
			if (FlxG.keys.justPressed.V)
			{
				pasteElement();
				return;
			}
			if (FlxG.keys.justPressed.S)
			{
				saveJSON();
				return;
			}
		}

		if (FlxG.keys.justPressed.ESCAPE)
		{
			if (_unsavedDlg != null) return;
			if (hasUnsavedChanges)
			{
				_unsavedDlg = new UnsavedChangesDialog([camHUD]);
				_unsavedDlg.onSaveAndExit = () -> { saveJSON(); _stageEditorExit(); };
				_unsavedDlg.onSave        = () -> { saveJSON(); remove(_unsavedDlg); _unsavedDlg = null; };
				_unsavedDlg.onExit        = () -> { _stageEditorExit(); };
				add(_unsavedDlg);
			}
			else
			{
				_stageEditorExit();
			}
			return;
		}

		// ── EDIT-only shortcuts below this point ─────────────────────────────
		if (editorMode == 'view')
		{
			// In VIEW mode: number keys switch camera
			if (FlxG.keys.justPressed.ONE)   _setViewCamera('general');
			if (FlxG.keys.justPressed.TWO)   _setViewCamera('bf');
			if (FlxG.keys.justPressed.THREE) _setViewCamera('dad');
			if (FlxG.keys.justPressed.FOUR)  _setViewCamera('gf');
			return;
		}

		if (FlxG.keys.justPressed.DELETE && !isMouseOverUI())
			deleteSelectedElement();

		// Nudge selected element with arrow keys (skip if locked)
		if (selectedIdx >= 0 && selectedIdx < stageData.elements.length
			&& !(stageData.elements[selectedIdx].locked == true))
		{
			var step = FlxG.keys.pressed.SHIFT ? 10.0 : 1.0;
			var elem = stageData.elements[selectedIdx];
			var moved = false;

			// Guardia: position puede ser null si el elemento se cargó de un JSON incompleto
			if (elem.position == null)
				elem.position = [0.0, 0.0];

			if (FlxG.keys.justPressed.LEFT)
			{
				elem.position[0] -= step;
				moved = true;
			}
			if (FlxG.keys.justPressed.RIGHT)
			{
				elem.position[0] += step;
				moved = true;
			}
			if (FlxG.keys.justPressed.UP)
			{
				elem.position[1] -= step;
				moved = true;
			}
			if (FlxG.keys.justPressed.DOWN)
			{
				elem.position[1] += step;
				moved = true;
			}

			if (moved)
			{
				if (elem.name != null && elementSprites.exists(elem.name))
					elementSprites.get(elem.name).setPosition(elem.position[0], elem.position[1]);
				syncElementFieldsToUI();
				markUnsaved();
			}
		}
	}

	function handleCameraMovement(elapsed:Float):Void
	{
		var speed = 400 * elapsed;
		var overUI = isMouseOverUI();

		if (!overUI && !FlxG.keys.pressed.SHIFT)
		{
			if (FlxG.keys.pressed.A || FlxG.keys.pressed.LEFT)
				camTargetX -= speed;
			if (FlxG.keys.pressed.D || FlxG.keys.pressed.RIGHT)
				camTargetX += speed;
			if (FlxG.keys.pressed.W || FlxG.keys.pressed.UP)
				camTargetY -= speed;
			if (FlxG.keys.pressed.S || FlxG.keys.pressed.DOWN)
				camTargetY += speed;
		}

		// Middle mouse drag
		if (!overUI && FlxG.mouse.pressedMiddle)
		{
			if (FlxG.mouse.justPressedMiddle)
			{
				isDraggingCam = true;
				dragCamStart.set(FlxG.mouse.gameX, FlxG.mouse.gameY);
				dragCamScrollStart.set(camTargetX, camTargetY);
			}
		}
		if (isDraggingCam)
		{
			if (FlxG.mouse.pressedMiddle)
			{
				camTargetX = dragCamScrollStart.x - (FlxG.mouse.gameX - dragCamStart.x) / camZoom;
				camTargetY = dragCamScrollStart.y - (FlxG.mouse.gameY - dragCamStart.y) / camZoom;
			}
			else
			{
				isDraggingCam = false;
			}
		}

		// Zoom with scroll wheel
		if (!overUI && FlxG.mouse.wheel != 0)
		{
			camZoom += FlxG.mouse.wheel * 0.05;
			camZoom = Math.max(0.15, Math.min(2.5, camZoom));
		}

		if (FlxG.keys.justPressed.R && !isMouseOverUI())
		{
			camTargetX = FlxG.width * 0.5;
			camTargetY = FlxG.height * 0.5;
			camZoom = 0.75;
		}

		camGame.scroll.x = FlxMath.lerp(camGame.scroll.x, camTargetX - FlxG.width * 0.5, 0.12);
		camGame.scroll.y = FlxMath.lerp(camGame.scroll.y, camTargetY - FlxG.height * 0.5, 0.12);
		camGame.zoom = FlxMath.lerp(camGame.zoom, camZoom, 0.12);
	}

	function handleLayerPanelClick():Void
	{
		// In VIEW mode the layer panel is read-only (no selection, no reorder)
		if (editorMode == 'view')
			return;

		var mx = FlxG.mouse.gameX;
		var my = FlxG.mouse.gameY;

		// Mouse wheel scrolling over layer panel
		if (FlxG.mouse.wheel != 0 && mx < LEFT_W && my > TOP_H && my < FlxG.height - STATUS_H)
		{
			layerScrollStart = Std.int(Math.max(0, Math.min(stageData.elements.length - 1, layerScrollStart - Std.int(FlxG.mouse.wheel))));
			refreshLayerPanel();
			return;
		}

		// ── Hover highlight — actualiza layerHoverIdx y refresca filas si cambia ──
		if (mx >= 0 && mx < LEFT_W && my >= TOP_H && my < FlxG.height - STATUS_H)
		{
			var newHover = -1;
			for (hit in layerHitData)
			{
				if (hit.zone == 'row' && hit.idx >= 0 && my >= hit.y && my <= hit.y + hit.h
					&& mx >= hit.x && mx <= hit.x + hit.w)
				{
					newHover = hit.idx;
					break;
				}
			}
			if (newHover != layerHoverIdx && !isDraggingLayer && !dragLayerPending)
			{
				var oldHover = layerHoverIdx;
				layerHoverIdx = newHover;
				// Recolor only the two affected row-background sprites instead of
				// rebuilding the entire panel (180+ makeGraphic calls per hover event).
				_recolorLayerRow(oldHover);
				_recolorLayerRow(newHover);
			}
		}
		else if (layerHoverIdx != -1)
		{
			var old = layerHoverIdx;
			layerHoverIdx = -1;
			_recolorLayerRow(old);
		}

		if (!FlxG.mouse.justPressed || mx > LEFT_W || my < TOP_H || my > FlxG.height - STATUS_H)
			return;

		// ── Begin layer drag on mousedown in a 'row' zone ────────────────────
		// Only start drag from the left part of the row (not over buttons).
		// We detect this before pass-1 button detection so we can cancel later.
		if (mx < 125) // drag handle zone = left 125 px
		{
			for (hit in layerHitData)
			{
				if (hit.zone == 'row' && hit.idx >= 0 && my >= hit.y && my <= hit.y + hit.h)
				{
					// Record the press — actual drag only activates once the mouse
					// moves beyond DRAG_THRESHOLD. A release without movement = click.
					dragLayerPending = true;
					dragLayerPendingIdx = hit.idx;
					dragLayerPendingX = mx;
					dragLayerPendingY = my;
					return; // don't fire click actions while press is pending
				}
			}
		}

		// ── Two-pass hit detection ────────────────────────────────────────────
		// Pass 1: look for specific small-button zones (eye, up, down, del, add_element)
		//         These must be checked first; they share the same Y band as 'row'
		//         but have a narrower X range.
		// Pass 2: fallback to 'row' and 'char' (full-width zones).
		var rowFallback:LayerHit = null;

		for (hit in layerHitData)
		{
			var hitX = hit.x;
			var hitW = hit.w;
			var hitY = hit.y;
			var hitH = hit.h;

			if (my < hitY || my > hitY + hitH)
				continue;
			if (mx < hitX || mx > hitX + hitW)
				continue;

			// Exact match on a specific zone → fire immediately
			if (hit.zone != 'row' && hit.zone != 'char')
			{
				switch (hit.zone)
				{
					case 'lock':
						// Toggle the lock flag on this element
						if (hit.idx >= 0 && hit.idx < stageData.elements.length)
						{
							var elem = stageData.elements[hit.idx];
							elem.locked = !(elem.locked == true);
							refreshLayerPanel();
							markUnsaved();
							saveHistory();
							// If we just locked the currently selected element, deselect it
							if (elem.locked == true && selectedIdx == hit.idx)
							{
								selectedIdx = -1;
								selectedCharId = null;
								_updateSelectionInfoBar();
								refreshLayerPanel();
							}
							setStatus('"${elem.name ?? "element"}" ${elem.locked ? "locked (LK)" : "unlocked"}');
						}

					case 'charup', 'chardown':
						// Character depth is now controlled by dragging the
						// character anchor row in the layer list. No-op here.

					case 'above':
						// Toggle aboveChars on this element (renders above characters).
						// Character anchors don't use aboveChars — skip them.
						if (hit.idx >= 0 && hit.idx < stageData.elements.length)
						{
							var elem = stageData.elements[hit.idx];
							if (elem.type != null && elem.type.toLowerCase() == 'character')
							{
								setStatus('Character anchors use drag-reorder, not the AB toggle');
							}
							else
							{
								elem.aboveChars = !(elem.aboveChars == true);
								saveHistory();
								reloadStageView();
								refreshLayerPanel();
								markUnsaved();
								var onOff = elem.aboveChars ? 'ON' : 'OFF';
								setStatus('"${elem.name ?? "element"}" above-chars: $onOff');
							}
						}

					case 'add_element':
						openAddElementDialog();

					case 'eye':
						if (hit.idx >= 0 && hit.idx < stageData.elements.length)
						{
							var elem = stageData.elements[hit.idx];
							elem.visible = !(elem.visible != false);
							if (elem.name != null && elementSprites.exists(elem.name))
								elementSprites.get(elem.name).visible = elem.visible;
							refreshLayerPanel();
							markUnsaved();
						}

					case 'up':
						moveLayer(hit.idx, 1);

					case 'down':
						moveLayer(hit.idx, -1);

					case 'del':
						if (hit.idx == selectedIdx)
						{
							selectedIdx = -1;
							selectedCharId = null;
						}
						stageData.elements.splice(hit.idx, 1);
						saveHistory();
						reloadStageView();
						_updateSelectionInfoBar();
						refreshLayerPanel();
						markUnsaved();
				}
				return;
			}

			// Save row/char as fallback (will be used if no specific zone matched)
			if (rowFallback == null)
				rowFallback = hit;
		}

		// Pass 2: fire the row/char fallback if we found one and no specific zone matched
		if (rowFallback != null)
		{
			switch (rowFallback.zone)
			{
				case 'row':
					if (rowFallback.idx >= 0 && rowFallback.idx < stageData.elements.length)
					{
						var clickedIdx = rowFallback.idx;
						var shiftHeld = FlxG.keys.pressed.SHIFT;
						var ctrlHeld  = FlxG.keys.pressed.CONTROL;

						if (shiftHeld && selectedIdx >= 0)
						{
							// ── Shift+click: rango entre anchor (selectedIdx) y clickedIdx ──
							var lo = Std.int(Math.min(selectedIdx, clickedIdx));
							var hi = Std.int(Math.max(selectedIdx, clickedIdx));
							// Añadir todo el rango; duplicados no importan (se filtran al usar)
							for (ri in lo...hi + 1)
								if (!selectedIndices.contains(ri))
									selectedIndices.push(ri);
							// selectedIdx (anchor) no cambia con Shift
						}
						else if (ctrlHeld)
						{
							// ── Ctrl+click: toggle individual ──
							if (selectedIndices.contains(clickedIdx))
							{
								selectedIndices.remove(clickedIdx);
								// Si quitamos el anchor, el nuevo anchor es el último de la lista
								if (selectedIdx == clickedIdx)
									selectedIdx = selectedIndices.length > 0 ? selectedIndices[selectedIndices.length - 1] : -1;
							}
							else
							{
								selectedIndices.push(clickedIdx);
								selectedIdx = clickedIdx; // Ctrl+click también actualiza el anchor
							}
						}
						else
						{
							// ── Click normal: selección única ──
							selectedIdx = clickedIdx;
							selectedIndices = [clickedIdx];
						}

						selectedCharId = null;
						syncElementFieldsToUI();
						refreshLayerPanel();
					}

				case 'char':
					selectedCharId = rowFallback.charId;
					var charElemIdx = _charEntryIndex(rowFallback.charId ?? '');
					selectedIdx = charElemIdx;
					selectedIndices = charElemIdx >= 0 ? [charElemIdx] : [];
					if (charElemIdx >= 0)
						syncElementFieldsToUI();
					else
						_updateSelectionInfoBar();
					refreshLayerPanel();
			}
		}
	}

	function handleLayerDrag():Void
	{
		// ── Resolve pending drag (press without enough movement = click) ────
		if (dragLayerPending)
		{
			var mx = FlxG.mouse.gameX;
			var my = FlxG.mouse.gameY;
			var dx = mx - dragLayerPendingX;
			var dy = my - dragLayerPendingY;

			if (FlxG.mouse.justReleased)
			{
				// Released without moving enough → treat as a click: select the row
				dragLayerPending = false;
				var idx = dragLayerPendingIdx;
				if (idx >= 0 && idx < stageData.elements.length)
				{
					var shiftHeld = FlxG.keys.pressed.SHIFT;
					var ctrlHeld  = FlxG.keys.pressed.CONTROL;

					if (shiftHeld && selectedIdx >= 0)
					{
						var lo = Std.int(Math.min(selectedIdx, idx));
						var hi = Std.int(Math.max(selectedIdx, idx));
						for (ri in lo...hi + 1)
							if (!selectedIndices.contains(ri))
								selectedIndices.push(ri);
					}
					else if (ctrlHeld)
					{
						if (selectedIndices.contains(idx))
						{
							selectedIndices.remove(idx);
							if (selectedIdx == idx)
								selectedIdx = selectedIndices.length > 0 ? selectedIndices[selectedIndices.length - 1] : -1;
						}
						else
						{
							selectedIndices.push(idx);
							selectedIdx = idx;
						}
					}
					else
					{
						selectedIdx = idx;
						selectedIndices = [idx];
					}

					selectedCharId = null;
					syncElementFieldsToUI();
					refreshLayerPanel();
				}
				return;
			}

			if (Math.sqrt(dx * dx + dy * dy) >= DRAG_THRESHOLD)
			{
				// Moved far enough → activate the real drag
				dragLayerPending = false;
				isDraggingLayer = true;
				dragLayerFromIdx = dragLayerPendingIdx;
				dragLayerDropIdx = dragLayerPendingIdx;

				// Si el elemento que se arrastra NO está en la selección actual,
				// descartamos la selección previa y arrastramos sólo ese elemento.
				var isMultiDrag = selectedIndices.length > 1 && selectedIndices.contains(dragLayerPendingIdx);
				if (!isMultiDrag)
				{
					selectedIdx = dragLayerPendingIdx;
					selectedIndices = [dragLayerPendingIdx];
				}

				// Texto del ghost: nombre individual o "N layers"
				var ghostLabel:String;
				if (selectedIndices.length > 1)
				{
					ghostLabel = '${selectedIndices.length} layers';
				}
				else
				{
					var elem = stageData.elements[dragLayerPendingIdx];
					ghostLabel = (elem.type != null && elem.type.toLowerCase() == 'character')
						? '\u25CF ' + (elem.charSlot ?? 'char')
						: (elem.name ?? 'element');
				}

				if (layerDragGhost != null)
				{
					layerDragGhost.y = my - ROW_H * 0.5;
					layerDragGhost.visible = true;
				}
				if (layerDragGhostTxt != null)
				{
					layerDragGhostTxt.text = '\u2630  ' + ghostLabel;
					layerDragGhostTxt.y = my - ROW_H * 0.5 + 6;
					layerDragGhostTxt.visible = true;
				}

				// Atenuar TODAS las filas seleccionadas
				for (sidx in selectedIndices)
				{
					var origBg = _layerRowBgMap.get(sidx);
					if (origBg != null) origBg.alpha = 0.2;
					var origTxts = _layerRowTextsMap.get(sidx);
					if (origTxts != null) for (t in origTxts) if (t != null) t.alpha = 0.15;
				}
				// fall through to the main drag logic below
			}
			else
				return; // still waiting for enough movement
		}

		if (!isDraggingLayer)
		{
			// Si había filas atenuadas por un drag previo que se canceló, restaurarlas
			if (dragLayerFromIdx >= 0)
			{
				for (sidx in selectedIndices)
				{
					var origBg = _layerRowBgMap.get(sidx);
					if (origBg != null) origBg.alpha = 1.0;
					var origTxts = _layerRowTextsMap.get(sidx);
					if (origTxts != null) for (t in origTxts) if (t != null) t.alpha = 1.0;
				}
				dragLayerFromIdx = -1;
			}
			if (layerDragGhost != null) layerDragGhost.visible = false;
			if (layerDragGhostTxt != null) layerDragGhostTxt.visible = false;
			if (layerDropLine != null) layerDropLine.visible = false;
			return;
		}

		var mx = FlxG.mouse.gameX;
		var my = FlxG.mouse.gameY;

		// Move ghost row with cursor
		if (layerDragGhost != null)
		{
			layerDragGhost.y = my - ROW_H * 0.5;
			layerDragGhost.visible = true;
		}
		if (layerDragGhostTxt != null)
		{
			layerDragGhostTxt.y = my - ROW_H * 0.5 + 6;
			layerDragGhostTxt.visible = true;
		}

		// Find the drop target position: which row are we hovering over?
		dragLayerDropIdx = dragLayerFromIdx; // default: no move
		var bestY:Float = 9999;
		for (hit in layerHitData)
		{
			if (hit.zone != 'row' || hit.idx < 0)
				continue;
			var rowMid = hit.y + ROW_H * 0.5;
			var dist = Math.abs(my - rowMid);
			if (dist < bestY)
			{
				bestY = dist;
				// Drop above or below this row depending on cursor position
				dragLayerDropIdx = (my < rowMid) ? hit.idx + 1 : hit.idx;
			}
		}
		// Clamp
		var total = stageData.elements != null ? stageData.elements.length : 0;
		dragLayerDropIdx = Std.int(Math.max(0, Math.min(total, dragLayerDropIdx)));

		// Draw the drop indicator line at the insertion point
		var lineY:Float = -100;
		for (hit in layerHitData)
		{
			if (hit.zone != 'row' || hit.idx < 0) continue;
			if (hit.idx == dragLayerDropIdx - 1)
				lineY = hit.y;
			else if (hit.idx == dragLayerDropIdx)
				lineY = hit.y;
		}
		if (layerDropLine != null)
		{
			layerDropLine.visible = (lineY > 0);
			if (lineY > 0) layerDropLine.y = lineY;
		}

		if (FlxG.mouse.justReleased)
		{
			isDraggingLayer = false;
			dragLayerPending = false;
			if (layerDragGhost != null) layerDragGhost.visible = false;
			if (layerDragGhostTxt != null) layerDragGhostTxt.visible = false;
			if (layerDropLine != null) layerDropLine.visible = false;

			// Restaurar alpha de todas las filas atenuadas
			for (sidx in selectedIndices)
			{
				var origBg = _layerRowBgMap.get(sidx);
				if (origBg != null) origBg.alpha = 1.0;
				var origTxts = _layerRowTextsMap.get(sidx);
				if (origTxts != null) for (t in origTxts) if (t != null) t.alpha = 1.0;
			}

			var toIdx = dragLayerDropIdx;

			if (selectedIndices.length > 1)
			{
				// ── Multi-layer move ──────────────────────────────────────────────
				_moveMultipleLayers(toIdx);
			}
			else
			{
				// ── Single layer move ─────────────────────────────────────────────
				var fromIdx = dragLayerFromIdx;
				if (toIdx != fromIdx && toIdx != fromIdx + 1 && stageData.elements != null)
				{
					var elem = stageData.elements.splice(fromIdx, 1)[0];
					var insertAt = toIdx > fromIdx ? toIdx - 1 : toIdx;
					stageData.elements.insert(insertAt, elem);
					selectedIdx = insertAt;
					selectedIndices = [insertAt];
					saveHistory();
					reloadStageView();
					syncElementFieldsToUI();
					refreshLayerPanel();
					markUnsaved();
					setStatus('Layer moved to position ${insertAt + 1}');
				}
				else
				{
					refreshLayerPanel();
				}
			}
		}
	}

	/**
	 * Mueve todas las capas de selectedIndices a la posición toIdx del array,
	 * preservando su orden relativo entre sí.
	 *
	 * Algoritmo:
	 *  1. Ordena los índices seleccionados (ascendente).
	 *  2. Cuenta cuántos están ANTES del punto de inserción → ajusta insertAt.
	 *  3. Extrae los elementos en orden.
	 *  4. Los borra del array de mayor a menor índice (para no desplazar los demás).
	 *  5. Los inserta como bloque en insertAt.
	 *  6. Actualiza selectedIndices y selectedIdx al nuevo rango.
	 */
	function _moveMultipleLayers(toIdx:Int):Void
	{
		if (stageData.elements == null || selectedIndices.length <= 1) return;

		// 1. Ordenar y filtrar índices válidos
		var sorted = selectedIndices.filter(i -> i >= 0 && i < stageData.elements.length);
		sorted.sort((a, b) -> a - b);
		if (sorted.length == 0) return;

		// Clampar destino
		toIdx = Std.int(Math.max(0, Math.min(stageData.elements.length, toIdx)));

		// 2. Número de seleccionados estrictamente antes del punto de inserción
		var numBefore = 0;
		for (s in sorted) if (s < toIdx) numBefore++;
		var insertAt = toIdx - numBefore;

		// 3. Extraer elementos en orden
		var extracted:Array<StageElement> = [for (s in sorted) stageData.elements[s]];

		// 4. Borrar de mayor a menor
		var sortedDesc = sorted.copy();
		sortedDesc.sort((a, b) -> b - a);
		for (s in sortedDesc)
			stageData.elements.splice(s, 1);

		// 5. Insertar como bloque
		for (i in 0...extracted.length)
			stageData.elements.insert(insertAt + i, extracted[i]);

		// 6. Actualizar selección al nuevo rango
		var newIndices = [for (i in 0...extracted.length) insertAt + i];
		selectedIndices = newIndices;

		// El anchor (selectedIdx) se mapea a su posición dentro del bloque
		var newAnchor = insertAt;
		for (i in 0...sorted.length)
		{
			if (sorted[i] == selectedIdx)
			{
				newAnchor = insertAt + i;
				break;
			}
		}
		selectedIdx = newAnchor;

		saveHistory();
		reloadStageView();
		syncElementFieldsToUI();
		refreshLayerPanel();
		markUnsaved();
		setStatus('${extracted.length} layers moved to position ${insertAt + 1}');
	}

	function handleCanvasDrag():Void
	{
		// In VIEW mode the canvas is read-only — no element/char dragging
		if (editorMode == 'view')
			return;

		var worldPos = FlxG.mouse.getWorldPosition(camGame);
		var worldX = worldPos.x;
		var worldY = worldPos.y;
		worldPos.put();

		if (FlxG.mouse.justPressed)
		{
			// Try to select element under cursor
			var clickedIdx = -1;
			var clickedChar = '';

			// Check characters first (they're on top)
			for (cid => c in characters)
			{
				if (worldX >= c.x && worldX <= c.x + c.width && worldY >= c.y && worldY <= c.y + c.height)
				{
					clickedChar = cid;
					break;
				}
			}

			if (clickedChar != '')
			{
				selectedCharId = clickedChar;
				// Also select the corresponding character-type element in the layer panel
				var charEntryIdx = _charEntryIndex(clickedChar);
				selectedIdx = charEntryIdx; // -1 if no entry (backward compat)
				// Sync element fields (runs _updateTypeWidgets so backdrop/graphic
				// panels are hidden for character-type elements).
				if (charEntryIdx >= 0)
					syncElementFieldsToUI();
				else
					_updateSelectionInfoBar();
				refreshLayerPanel();
				isDraggingChar = true;
				dragCharId = clickedChar;
				dragStart.set(worldX, worldY);
				var c = characters.get(clickedChar);
				dragObjStart.set(c.x, c.y);
			}
			else
			{
				// Check elements (reverse order = topmost first), skip locked
				var i = stageData.elements.length - 1;
				while (i >= 0)
				{
					var elem = stageData.elements[i];
					// Sound elements have no visual bounds — skip them in canvas hit-testing.
					var elemType = elem.type != null ? elem.type.toLowerCase() : '';
					if (elemType != 'sound' && elem.locked != true
						&& elem.name != null && elementSprites.exists(elem.name))
					{
						var spr = elementSprites.get(elem.name);
						if (spr.width > 0 && spr.height > 0
							&& worldX >= spr.x && worldX <= spr.x + spr.width
							&& worldY >= spr.y && worldY <= spr.y + spr.height)
						{
							clickedIdx = i;
							break;
						}
					}
					i--;
				}

				if (clickedIdx >= 0)
				{
					selectedIdx = clickedIdx;
					selectedCharId = null;
					syncElementFieldsToUI();
					refreshLayerPanel();
					var clickedElem = stageData.elements[clickedIdx];
					// Guard: position may be null for sound/group elements from older JSON files
					var startPos = clickedElem.position ?? [0.0, 0.0];
					isDraggingEl = true;
					dragStart.set(worldX, worldY);
					dragObjStart.set(startPos[0], startPos[1]);
				}
				else
				{
					// Check if user clicked a LOCKED element — select it (read-only) but don't drag
					var foundLocked = false;
					var li = stageData.elements.length - 1;
					while (li >= 0)
					{
						var elem = stageData.elements[li];
						var liType = elem.type != null ? elem.type.toLowerCase() : '';
						if (liType != 'sound' && elem.locked == true
							&& elem.name != null && elementSprites.exists(elem.name))
						{
							var spr = elementSprites.get(elem.name);
							if (spr.width > 0 && spr.height > 0
								&& worldX >= spr.x && worldX <= spr.x + spr.width
								&& worldY >= spr.y && worldY <= spr.y + spr.height)
							{
								selectedIdx = li;
								selectedCharId = null;
								syncElementFieldsToUI();
								refreshLayerPanel();
								setStatus('"${elem.name ?? "element"}" is locked — unlock (LK button) to move');
								foundLocked = true;
								break;
							}
						}
						li--;
					}
					// Clicked empty space — deselect everything
					if (!foundLocked)
					{
						selectedIdx = -1;
						selectedCharId = null;
						selectedIndices = [];
						_updateSelectionInfoBar();
						refreshLayerPanel();
					}
				}
			}
		}

		// Drag element
		if (isDraggingEl && selectedIdx >= 0 && selectedIdx < stageData.elements.length)
		{
			if (FlxG.mouse.pressed)
			{
				var dx = worldX - dragStart.x;
				var dy = worldY - dragStart.y;
				var dragElem = stageData.elements[selectedIdx];
				// Guard: position may be null for sound/group from older JSON files
				if (dragElem.position == null) dragElem.position = [0.0, 0.0];
				dragElem.position[0] = dragObjStart.x + dx;
				dragElem.position[1] = dragObjStart.y + dy;
				var elem = stageData.elements[selectedIdx];
				if (elem.name != null && elementSprites.exists(elem.name))
					elementSprites.get(elem.name).setPosition(elem.position[0], elem.position[1]);
				syncElementFieldsToUI();
			}
			else
			{
				isDraggingEl = false;
				saveHistory();
				markUnsaved();
			}
		}

		// Drag character
		if (isDraggingChar && dragCharId != null)
		{
			if (FlxG.mouse.pressed)
			{
				var dx = worldX - dragStart.x;
				var dy = worldY - dragStart.y;
				var c = characters.get(dragCharId);
				if (c != null)
					c.setPosition(dragObjStart.x + dx, dragObjStart.y + dy);
			}
			else
			{
				isDraggingChar = false;
				// Save new position into stageData
				var c = characters.get(dragCharId);
				if (c != null)
				{
					switch (dragCharId)
					{
						case 'bf':
							stageData.boyfriendPosition = [c.x, c.y];
							if (bfXStepper != null)
								bfXStepper.value = c.x;
							if (bfYStepper != null)
								bfYStepper.value = c.y;
						case 'gf':
							stageData.gfPosition = [c.x, c.y];
							if (gfXStepper != null)
								gfXStepper.value = c.x;
							if (gfYStepper != null)
								gfYStepper.value = c.y;
						case 'dad':
							stageData.dadPosition = [c.x, c.y];
							if (dadXStepper != null)
								dadXStepper.value = c.x;
							if (dadYStepper != null)
								dadYStepper.value = c.y;
					}
				}
				saveHistory();
				markUnsaved();
				refreshLayerPanel(); // Update position display
			}
		}
	}

	function handleToolbarClick():Void
	{
		if (!FlxG.mouse.justPressed)
			return;
		var mx = FlxG.mouse.gameX;
		var my = FlxG.mouse.gameY;
		// Toolbar occupies TITLE_H → TOP_H (i.e. y=34 to y=74)
		// Use a slightly generous top bound to avoid missing the top row
		if (my < 0 || my > TOP_H)
			return;

		// ── View camera bar click detection (VIEW mode only) ──────────────────
		if (editorMode == 'view')
		{
			for (hit in _viewCamHits)
			{
				if (mx >= hit.x && mx <= hit.x + hit.w && my >= hit.y && my <= hit.y + hit.h)
				{
					_setViewCamera(hit.slot);
					return;
				}
			}
		}

		for (bg => cb in _toolBtns)
		{
			if (mx >= bg.x && mx <= bg.x + bg.width && my >= bg.y && my <= bg.y + bg.height)
			{
				cb();
				return;
			}
		}
	}

	function updateSelectionBox():Void
	{
		if (selBox == null)
			return;

		// ── Determinar sprite seleccionado (elemento O personaje) ─────────────
		var spr:FlxSprite = null;
		var selName:String = null;

		if (selectedIdx >= 0 && selectedIdx < stageData.elements.length)
		{
			var elem = stageData.elements[selectedIdx];
			if (elem.name != null && elementSprites.exists(elem.name))
			{
				spr = elementSprites.get(elem.name);
				selName = elem.name;
			}
			// Character-type element: look up the actual character sprite
			else if (elem.type != null && elem.type.toLowerCase() == 'character')
			{
				var cid = _normalizeSlot(elem.charSlot ?? 'bf');
				if (characters.exists(cid))
				{
					spr = characters.get(cid);
					selName = cid;
				}
			}
		}
		else if (selectedCharId != null && characters.exists(selectedCharId))
		{
			spr = characters.get(selectedCharId);
			selName = selectedCharId;
		}

		if (spr == null)
		{
			selBox.visible = false;
			selMesh.visible = false;
			return;
		}

		var pad = 3;
		var needW = Std.int(spr.width  + pad * 2);
		var needH = Std.int(spr.height + pad * 2);

		// Guard: makeGraphic crashes with 0, negative, or absurdly large values.
		// Sound / group placeholder sprites can have degenerate dimensions.
		if (needW < 6) needW = 6;
		if (needH < 6) needH = 6;
		if (needW > 4096) needW = 4096;
		if (needH > 4096) needH = 4096;

		// ── Borde de selección (solo rebuildear si cambió tamaño) ─────────────
		if (needW != _selBoxW || needH != _selBoxH)
		{
			_selBoxW = needW;
			_selBoxH = needH;

			selBox.makeGraphic(needW, needH, FlxColor.TRANSPARENT, true);

			var pix = selBox.pixels;
			var c = EditorTheme.current.selection;

			for (xi in 0...needW)
			{
				pix.setPixel32(xi, 0, c);
				pix.setPixel32(xi, 1, c);
				pix.setPixel32(xi, needH - 1, c);
				pix.setPixel32(xi, needH - 2, c);
			}
			for (yi in 0...needH)
			{
				pix.setPixel32(0, yi, c);
				pix.setPixel32(1, yi, c);
				pix.setPixel32(needW - 1, yi, c);
				pix.setPixel32(needW - 2, yi, c);
			}

			selBox.dirty = true;
		}

		// ── Malla checkerboard (diferencia visualmente el sprite activo) ──────
		var mw = Std.int(spr.width);
		var mh = Std.int(spr.height);
		if (mw < 1) mw = 1;
		if (mh < 1) mh = 1;

		if (mw != _selMeshW || mh != _selMeshH)
		{
			_selMeshW = mw;
			_selMeshH = mh;

			selMesh.makeGraphic(mw, mh, FlxColor.TRANSPARENT, true);
			var mp = selMesh.pixels;
			var cA = EditorTheme.current.selection | 0xFF000000;  // color sólido
			var tile = 8; // tamaño de cada cuadro del damero

			for (yi in 0...mh)
			{
				for (xi in 0...mw)
				{
					var tx = Std.int(xi / tile);
					var ty = Std.int(yi / tile);
					if ((tx + ty) % 2 == 0)
						mp.setPixel32(xi, yi, (cA & 0x00FFFFFF) | 0x55000000); // 33% alpha
				}
			}
			selMesh.dirty = true;
		}

		selBox.setPosition(spr.x - pad, spr.y - pad);
		selBox.visible = true;
		selMesh.setPosition(spr.x, spr.y);
		selMesh.visible = true;

		// ── Hover tooltip — detectar elemento/personaje bajo el mouse ─────────
		_updateHoverTooltip();
	}

	/** Muestra el nombre del elemento/personaje que está bajo el cursor del mouse. */
	function _updateHoverTooltip():Void
	{
		var worldPos = FlxG.mouse.getWorldPosition(camGame);
		var wx = worldPos.x;
		var wy = worldPos.y;
		worldPos.put();

		var foundName:String = null;

		// Chequear personajes primero (están encima)
		for (cid => c in characters)
		{
			if (wx >= c.x && wx <= c.x + c.width && wy >= c.y && wy <= c.y + c.height)
			{
				foundName = cid;
				break;
			}
		}

		// Chequear elementos si no cayó en personaje
		if (foundName == null)
		{
			var i = stageData.elements.length - 1;
			while (i >= 0)
			{
				var elem = stageData.elements[i];
				if (elem.name != null && elementSprites.exists(elem.name))
				{
					var espr = elementSprites.get(elem.name);
					if (wx >= espr.x && wx <= espr.x + espr.width && wy >= espr.y && wy <= espr.y + espr.height)
					{
						foundName = elem.name;
						break;
					}
				}
				i--;
			}
		}

		var sx = FlxG.mouse.gameX;
		var sy = FlxG.mouse.gameY;

		if (foundName == null || sx < LEFT_W || sx > FlxG.width - RIGHT_W)
		{
			hoverTooltipBg.visible  = false;
			hoverTooltipTxt.visible = false;
			return;
		}

		// Solo rebuild texto si cambió el nombre
		if (foundName != _hoverName)
		{
			_hoverName = foundName;
			hoverTooltipTxt.text = foundName;
		}

		// Posición: ligeramente por encima y a la derecha del cursor (HUD space)
		var tx = sx + 12;
		var ty = sy - 20;
		var tw = Std.int(hoverTooltipTxt.width) + 8;
		var th = 18;

		// Evitar salirse por la derecha
		if (tx + tw > FlxG.width - RIGHT_W - 2)
			tx = sx - tw - 4;

		hoverTooltipBg.setPosition(tx, ty);
		// Only call makeGraphic when size changes — avoids BitmapData alloc every frame.
		if (tw != _tooltipW || th != _tooltipH)
		{
			_tooltipW = tw;
			_tooltipH = th;
			hoverTooltipBg.makeGraphic(tw, th, 0xCC000000);
		}
		hoverTooltipTxt.setPosition(tx + 4, ty + 3);

		hoverTooltipBg.visible  = true;
		hoverTooltipTxt.visible = true;
	}

	function updateCharLabels():Void
	{
		var lArr = charLabels.members;
		var cIds = ['dad', 'gf', 'bf'];
		var ci = 0;
		for (cid in cIds)
		{
			if (!characters.exists(cid))
				continue;
			var c = characters.get(cid);
			if (ci < lArr.length && lArr[ci] != null)
			{
				lArr[ci].setPosition(c.x, c.y - 22);
			}
			ci++;
		}
	}

	function updateStatusBar():Void
	{
		var worldPos = FlxG.mouse.getWorldPosition(camGame);
		var worldX = Std.int(worldPos.x);
		var worldY = Std.int(worldPos.y);
		worldPos.put();
		coordText.text = 'x:$worldX y:$worldY';
		zoomText.text = 'Zoom: ${Std.int(camZoom * 100)}%';
		unsavedDot.x = titleText.x + titleText.textField.textWidth + 10;
		// Show current mode in title bar hint
		if (titleText != null && editorMode == 'view')
			titleText.alpha = 0.7;
		else if (titleText != null)
			titleText.alpha = 1.0;
	}

	// ─────────────────────────────────────────────────────────────────────────
	// ELEMENT OPERATIONS
	// ─────────────────────────────────────────────────────────────────────────

	function openAddElementDialog():Void
	{
		openSubState(new AddElementSubState(function(elem:StageElement)
		{
			stageData.elements.push(elem);
			saveHistory();
			reloadStageView();
			selectedIdx = stageData.elements.length - 1;
			selectedCharId = null;
			selectedIndices = [selectedIdx];
			syncElementFieldsToUI();   // → calls _updateSelectionInfoBar → _updatePanelVisibility
			refreshLayerPanel();
			markUnsaved();
			setStatus('Element "${elem.name}" added');
		}, stageData.name ?? 'stage', ModManager.isActive()));
	}

	function deleteSelectedElement():Void
	{
		if (stageData.elements == null) return;

		// ── Multi-delete cuando hay más de una capa seleccionada ──────────────────
		if (selectedIndices.length > 1)
		{
			var toDelete = selectedIndices.filter(i -> i >= 0 && i < stageData.elements.length
				&& stageData.elements[i].locked != true);
			if (toDelete.length == 0)
			{
				setStatus('All selected layers are locked — unlock (LK) to delete');
				return;
			}
			// Borrar de mayor a menor para no invalidar los índices restantes
			toDelete.sort((a, b) -> b - a);
			for (i in toDelete)
				stageData.elements.splice(i, 1);

			selectedIdx = -1;
			selectedIndices = [];
			saveHistory();
			reloadStageView();
			_updateSelectionInfoBar();
			refreshLayerPanel();
			markUnsaved();
			setStatus('${toDelete.length} layers deleted');
			return;
		}

		// ── Single delete (comportamiento original) ───────────────────────────────
		if (selectedIdx < 0 || selectedIdx >= stageData.elements.length)
			return;
		var elem = stageData.elements[selectedIdx];
		if (elem.locked == true)
		{
			setStatus('"${elem.name ?? "element"}" is locked — unlock (LK button) to delete');
			return;
		}
		var name = elem.name ?? 'element';
		stageData.elements.splice(selectedIdx, 1);
		selectedIdx = -1;
		selectedIndices = [];
		saveHistory();
		reloadStageView();
		_updateSelectionInfoBar();
		refreshLayerPanel();
		markUnsaved();
		setStatus('Element "$name" deleted');
	}

	function copyElement():Void
	{
		if (selectedIdx < 0 || selectedIdx >= stageData.elements.length)
			return;
		clipboard = Json.parse(Json.stringify(stageData.elements[selectedIdx]));
		setStatus('Element copied to clipboard');
	}

	function pasteElement():Void
	{
		if (clipboard == null)
			return;
		var newElem:StageElement = Json.parse(Json.stringify(clipboard));
		newElem.name = (clipboard.name ?? 'elem') + '_copy';
		var cpPos = clipboard.position ?? [0.0, 0.0];
		newElem.position = [cpPos[0] + 30, cpPos[1] + 30];
		stageData.elements.push(newElem);
		saveHistory();
		reloadStageView();
		selectedIdx = stageData.elements.length - 1;
		syncElementFieldsToUI();
		refreshLayerPanel();
		markUnsaved();
		setStatus('Element pasted: "${newElem.name}"');
	}

	function moveLayer(idx:Int, delta:Int):Void
	{
		// In the array, higher index = drawn on top.
		// delta = 1 means move element up visually = increase index
		var newIdx = idx + delta;
		if (newIdx < 0 || newIdx >= stageData.elements.length)
			return;

		var temp = stageData.elements[idx];
		stageData.elements[idx] = stageData.elements[newIdx];
		stageData.elements[newIdx] = temp;

		if (selectedIdx == idx)
			selectedIdx = newIdx;
		else if (selectedIdx == newIdx)
			selectedIdx = idx;

		saveHistory();
		reloadStageView();
		refreshLayerPanel();
		markUnsaved();
	}

	function applyElementProps():Void
	{
		if (selectedIdx < 0 || selectedIdx >= stageData.elements.length)
			return;
		var elem = stageData.elements[selectedIdx];

		elem.name = elemNameInput.text.trim();
		elem.asset = elemAssetInput.text.trim();
		// Always ensure position is a valid array (sound/group elements from old
		// JSON files may have omitted the field entirely).
		if (elem.position == null) elem.position = [0.0, 0.0];
		elem.position = [elemXStepper.value, elemYStepper.value];
		elem.scale = [elemScaleXStepper.value, elemScaleYStepper.value];
		elem.scrollFactor = [elemScrollXStepper.value, elemScrollYStepper.value];
		elem.alpha = elemAlphaStepper.value;
		elem.zIndex = Std.int(elemZIndexStepper.value);
		elem.angle = elemAngleStepper.value != 0 ? elemAngleStepper.value : null;
		elem.flipX = elemFlipXCheck.checked;
		elem.flipY = elemFlipYCheck.checked;
		elem.antialiasing = elemAntialiasingCheck.checked;
		elem.visible = elemVisibleCheck.checked;
		elem.aboveChars = elemAboveCharsCheck.checked;

		var colorStr = elemColorInput.text.trim();
		elem.color = (colorStr != '' && colorStr != '#FFFFFF') ? colorStr : null;

		// ── Backdrop properties ───────────────────────────────────────────────
		if (elem.type == 'backdrop')
		{
			if (elem.customProperties == null) elem.customProperties = {};
			Reflect.setField(elem.customProperties, 'repeatX', backdropRepeatXCheck.checked);
			Reflect.setField(elem.customProperties, 'repeatY', backdropRepeatYCheck.checked);
			Reflect.setField(elem.customProperties, 'velocityX', backdropVelXStepper.value);
			Reflect.setField(elem.customProperties, 'velocityY', backdropVelYStepper.value);
		}

		// ── Graphic properties ────────────────────────────────────────────────
		if (elem.type == 'graphic')
		{
			elem.graphicSize  = [graphicWidthStepper.value, graphicHeightStepper.value];
			var gcStr = graphicFillColorInput.text.trim();
			elem.graphicColor = (gcStr != '') ? gcStr : '#FFFFFF';
		}

		saveHistory();
		reloadStageView();
		selectedIdx = stageData.elements.length > 0 ? Std.int(Math.min(selectedIdx, stageData.elements.length - 1)) : -1;
		refreshLayerPanel();
		markUnsaved();
		setStatus('Properties applied: "${elem.name}"');
	}

	function syncElementFieldsToUI():Void
	{
		if (selectedIdx < 0 || selectedIdx >= stageData.elements.length)
			return;
		var elem = stageData.elements[selectedIdx];

		// Update selection info bar (top of right panel)
		_updateSelectionInfoBar();

		if (elemNameInput != null)
			elemNameInput.text = elem.name ?? '';
		if (elemAssetInput != null)
			elemAssetInput.text = elem.asset ?? '';
		if (elemTypeDropdown != null)
			elemTypeDropdown.selectedLabel = elem.type ?? 'sprite';

		var pos = elem.position ?? [0.0, 0.0];
		if (elemXStepper != null)
			elemXStepper.value = pos.length > 0 ? pos[0] : 0.0;
		if (elemYStepper != null)
			elemYStepper.value = pos.length > 1 ? pos[1] : 0.0;

		var sc = elem.scale ?? [1.0, 1.0];
		if (elemScaleXStepper != null)
			elemScaleXStepper.value = sc[0];
		if (elemScaleYStepper != null)
			elemScaleYStepper.value = sc[1];

		var sf = elem.scrollFactor ?? [1.0, 1.0];
		if (elemScrollXStepper != null)
			elemScrollXStepper.value = sf[0];
		if (elemScrollYStepper != null)
			elemScrollYStepper.value = sf[1];

		if (elemAlphaStepper != null)
			elemAlphaStepper.value = elem.alpha ?? 1.0;
		if (elemZIndexStepper != null)
			elemZIndexStepper.value = elem.zIndex ?? 0;
		if (elemAngleStepper != null)
			elemAngleStepper.value = elem.angle ?? 0;

		if (elemFlipXCheck != null)
			elemFlipXCheck.checked = elem.flipX ?? false;
		if (elemFlipYCheck != null)
			elemFlipYCheck.checked = elem.flipY ?? false;
		if (elemAntialiasingCheck != null)
			elemAntialiasingCheck.checked = elem.antialiasing ?? true;
		if (elemVisibleCheck != null)
			elemVisibleCheck.checked = elem.visible ?? true;
		if (elemAboveCharsCheck != null)
			elemAboveCharsCheck.checked = elem.aboveChars == true;
		if (elemColorInput != null)
			elemColorInput.text = elem.color ?? '#FFFFFF';

		// Shader — sincronizar dropdown con el shader del elemento seleccionado
		if (elemShaderDropdown != null)
		{
			var sh = (elem.customProperties != null) ? Reflect.field(elem.customProperties, 'shader') : null;
			var shName = (sh != null && sh != '') ? Std.string(sh) : '(none)';
			// Buscar en la lista; si no existe, mostrar (none)
			elemShaderDropdown.selectedLabel = (_shaderList.contains(shName)) ? shName : '(none)';
		}

		// ── Type-specific panel visibility ────────────────────────────────────────
		_updateTypeWidgets(elem.type ?? 'sprite');

		// ── Backdrop panel values ─────────────────────────────────────────────────
		if (elem.type == 'backdrop')
		{
			var cp = elem.customProperties;
			if (backdropRepeatXCheck != null)
			{
				var rx = (cp != null) ? Reflect.field(cp, 'repeatX') : null;
				backdropRepeatXCheck.checked = (rx == null) ? true : (rx == true);
			}
			if (backdropRepeatYCheck != null)
			{
				var ry = (cp != null) ? Reflect.field(cp, 'repeatY') : null;
				backdropRepeatYCheck.checked = (ry == null) ? true : (ry == true);
			}
			if (backdropVelXStepper != null)
			{
				var vx = (cp != null) ? Reflect.field(cp, 'velocityX') : null;
				backdropVelXStepper.value = (vx == null) ? 0 : Std.parseFloat(Std.string(vx));
			}
			if (backdropVelYStepper != null)
			{
				var vy = (cp != null) ? Reflect.field(cp, 'velocityY') : null;
				backdropVelYStepper.value = (vy == null) ? 0 : Std.parseFloat(Std.string(vy));
			}
		}

		// ── Graphic panel values ──────────────────────────────────────────────────
		if (elem.type == 'graphic')
		{
			var gs = elem.graphicSize ?? [100.0, 100.0];
			if (graphicWidthStepper  != null) graphicWidthStepper.value  = gs.length > 0 ? gs[0] : 100.0;
			if (graphicHeightStepper != null) graphicHeightStepper.value = gs.length > 1 ? gs[1] : 100.0;
			if (graphicFillColorInput != null) graphicFillColorInput.text = elem.graphicColor ?? '#FFFFFF';
		}

		// Sync animation tab
		syncAnimListUI();
	}

	// ─────────────────────────────────────────────────────────────────────────
	// ANIMATION OPERATIONS
	// ─────────────────────────────────────────────────────────────────────────

	function syncAnimListUI():Void
	{
		if (animListBg == null || animListText == null)
			return;

		// Destroy existing sprites — clear() alone only empties the array without
		// freeing the BitmapData, causing sprites to accumulate across selections.
		while (animListBg.members.length > 0)
		{
			var s = animListBg.members[0];
			animListBg.remove(s, true);
			if (s != null) s.destroy();
		}
		while (animListText.members.length > 0)
		{
			var t = animListText.members[0];
			animListText.remove(t, true);
			if (t != null) t.destroy();
		}
		animHitData = [];

		if (selectedIdx < 0 || selectedIdx >= stageData.elements.length)
			return;
		var elem = stageData.elements[selectedIdx];
		if (elem.animations == null || elem.animations.length == 0)
			return;

		var T = EditorTheme.current;
		var ay = 10.0;

		// Absolute offset: right panel starts at (FlxG.width - RIGHT_W + 2), tab header ≈ 20px
		// SEL_INFO_H is added because the tab menu itself is offset by that amount.
		var ox:Float = FlxG.width - RIGHT_W + 2;
		var oy:Float = TOP_H + SEL_INFO_H + 20;

		for (i in 0...elem.animations.length)
		{
			var anim = elem.animations[i];
			var isSelAnim = (i == animSelIdx);
			var rowColor = isSelAnim ? T.rowSelected : (i % 2 == 0 ? T.rowEven : T.rowOdd);

			var bg = new FlxSprite(ox + 4, oy + ay).makeGraphic(RIGHT_W - 16, ANIM_ROW_H, rowColor);
			bg.cameras = [camHUD];
			bg.scrollFactor.set();
			animListBg.add(bg);

			var nameT = new FlxText(ox + 8, oy + ay + 4, 100, anim.name, 9);
			nameT.setFormat(Paths.font('vcr.ttf'), 9, isSelAnim ? T.accent : T.textPrimary, LEFT);
			nameT.cameras = [camHUD];
			nameT.scrollFactor.set();
			animListText.add(nameT);

			var prefT = new FlxText(ox + 110, oy + ay + 4, 80, anim.prefix, 9);
			prefT.setFormat(Paths.font('vcr.ttf'), 9, T.textSecondary, LEFT);
			prefT.cameras = [camHUD];
			prefT.scrollFactor.set();
			animListText.add(prefT);

			var fpsT = new FlxText(ox + RIGHT_W - 50, oy + ay + 4, 40, '${anim.framerate ?? 24}fps', 8);
			fpsT.color = T.textDim;
			fpsT.cameras = [camHUD];
			fpsT.scrollFactor.set();
			animListText.add(fpsT);

			animHitData.push({y: oy + ay, idx: i});
			ay += ANIM_ROW_H;

			if (i == animSelIdx)
			{
				// Populate edit fields with selected anim
				if (animNameInput != null)
					animNameInput.text = anim.name;
				if (animPrefixInput != null)
					animPrefixInput.text = anim.prefix;
				if (animFPSStepper != null)
					animFPSStepper.value = anim.framerate ?? 24;
				if (animLoopCheck != null)
					animLoopCheck.checked = anim.looped ?? false;
				if (animIndicesInput != null)
					animIndicesInput.text = (anim.indices != null ? anim.indices.join(',') : '');
				if (animTypeDropdown != null)
					animTypeDropdown.selectedLabel = (anim.animType != null && anim.animType == 'each_beat') ? 'each_beat' : 'default';
			}
		}

		if (elem.firstAnimation != null && animFirstInput != null)
			animFirstInput.text = elem.firstAnimation;
	}

	function addAnimation():Void
	{
		if (selectedIdx < 0 || selectedIdx >= stageData.elements.length)
			return;
		var elem = stageData.elements[selectedIdx];
		if (elem.animations == null)
			elem.animations = [];
		elem.animations.push({
			name: 'new_anim',
			prefix: 'new0',
			framerate: 24,
			looped: false
		});
		animSelIdx = elem.animations.length - 1;
		syncAnimListUI();
		markUnsaved();
	}

	function removeAnimation():Void
	{
		if (selectedIdx < 0 || selectedIdx >= stageData.elements.length)
			return;
		var elem = stageData.elements[selectedIdx];
		if (elem.animations == null || animSelIdx < 0 || animSelIdx >= elem.animations.length)
			return;
		elem.animations.splice(animSelIdx, 1);
		animSelIdx = Std.int(Math.max(0, animSelIdx - 1));
		syncAnimListUI();
		markUnsaved();
	}

	function saveAnimData():Void
	{
		if (selectedIdx < 0 || selectedIdx >= stageData.elements.length)
			return;
		var elem = stageData.elements[selectedIdx];
		if (elem.animations == null || elem.animations.length == 0)
			return;

		var anim = elem.animations[animSelIdx];
		anim.name = animNameInput.text.trim();
		anim.prefix = animPrefixInput.text.trim();
		anim.framerate = Std.int(animFPSStepper.value);
		anim.looped = animLoopCheck.checked;

		// Persist animType — omit the field entirely when "default" to keep JSON clean.
		var selectedType = animTypeDropdown != null ? animTypeDropdown.selectedLabel : 'default';
		anim.animType = (selectedType == 'each_beat') ? 'each_beat' : null;

		var indStr = animIndicesInput.text.trim();
		if (indStr != '')
		{
			anim.indices = indStr.split(',').map(s -> Std.parseInt(s.trim())).filter(v -> v != null);
		}
		else
		{
			anim.indices = null;
		}

		elem.firstAnimation = animFirstInput.text.trim();

		syncAnimListUI();
		saveHistory();
		markUnsaved();
		setStatus('Animation "${anim.name}" saved');
	}

	// ─────────────────────────────────────────────────────────────────────────
	// STAGE / CHARS PROPS
	// ─────────────────────────────────────────────────────────────────────────

	function applyStageProps():Void
	{
		stageData.name = stageNameInput.text.trim();
		stageData.defaultZoom = stageZoomStepper.value;
		stageData.isPixelStage = stagePixelCheck.checked;
		stageData.hideGirlfriend = stageHideGFCheck.checked;
		titleText.text = '\u26AA  STAGE EDITOR  \u2022  ' + stageData.name;
		saveHistory();
		markUnsaved();
		setStatus('Stage properties updated');
	}

	function applyCharProps():Void
	{
		stageData.boyfriendPosition = [bfXStepper.value, bfYStepper.value];
		stageData.gfPosition = [gfXStepper.value, gfYStepper.value];
		stageData.dadPosition = [dadXStepper.value, dadYStepper.value];
		stageData.cameraBoyfriend = [camBFXStepper.value, camBFYStepper.value];
		stageData.cameraDad = [camDadXStepper.value, camDadYStepper.value];
		stageData.gfVersion = gfVersionInput.text.trim();
		loadCharacters();
		saveHistory();
		markUnsaved();
		refreshLayerPanel();
		setStatus('Character positions updated');
	}

	function addScript():Void
	{
		if (stageData.scripts == null)
			stageData.scripts = [];
		stageData.scripts.push('scripts/newScript.hx');
		saveHistory();
		markUnsaved();
		setStatus('Script placeholder added — edit the JSON to set the real path');
	}

	// ─────────────────────────────────────────────────────────────────────────
	// NEW STAGE / STAGE LIST
	// ─────────────────────────────────────────────────────────────────────────

	function openNewStageDialog():Void
	{
		openSubState(new NewStageSubState([camHUD], function(name:String)
		{
			// Build a blank stageData with the given name
			stageData = {
				name: name,
				defaultZoom: 0.9,
				isPixelStage: false,
				elements: [],
				gfVersion: 'gf',
				boyfriendPosition: [770.0, 450.0],
				dadPosition:        [100.0, 100.0],
				gfPosition:         [400.0, 130.0],
				cameraBoyfriend: [0.0, 0.0],
				cameraDad:       [0.0, 0.0],
				hideGirlfriend: false,
				scripts: []
			};
			_stageDataReady = true;
			history = [];
			historyIndex = -1;
			selectedIdx = -1;
			selectedIndices = [];
			selectedCharId = null;
			saveHistory();
			reloadStageView();
			refreshLayerPanel();
			hasUnsavedChanges = true;
			unsavedDot.visible = true;
			if (titleText != null)
				titleText.text = '\u26AA  STAGE EDITOR  \u2022  $name';
			setStatus('New stage "$name" created — save it when ready');
		}));
	}

	function openStageListDialog():Void
	{
		openSubState(new StageListSubState([camHUD], function(stageName:String, stagePath:String)
		{
			// Load stage from disk by path
			#if sys
			try
			{
				var raw = sys.io.File.getContent(stagePath);
				stageData = haxe.Json.parse(raw);
				_stageDataReady = true;
				history = [];
				historyIndex = -1;
				selectedIdx = -1;
				selectedIndices = [];
				selectedCharId = null;
				saveHistory();
				reloadStageView();
				refreshLayerPanel();
				currentFilePath = stagePath;
				hasUnsavedChanges = false;
				unsavedDot.visible = false;
				if (titleText != null)
					titleText.text = '\u26AA  STAGE EDITOR  \u2022  $stageName';
				setStatus('Stage loaded: $stagePath');
			}
			catch (e:Dynamic)
			{
				setStatus('Error loading stage "$stageName": $e');
			}
			#end
		}));
	}

	// ─────────────────────────────────────────────────────────────────────────
	// SAVE / LOAD
	// ─────────────────────────────────────────────────────────────────────────

	function _getSavePath(toMod:Bool):String
	{
		#if sys
		var stageName = stageData.name;
		if (toMod && ModManager.isActive())
			return '${ModManager.modRoot()}/stages/$stageName.json';
		else
			return 'assets/stages/$stageName.json';
		#else
		return '';
		#end
	}

	function _ensureDir(path:String):Void
	{
		#if sys
		var dir = haxe.io.Path.directory(path);
		if (dir != '' && !FileSystem.exists(dir))
			FileSystem.createDirectory(dir);
		#end
	}

	/** Exits the Stage Editor cleanly. */
	function _stageEditorExit():Void
	{
		funkin.system.CursorManager.hide();
		StateTransition.switchState(new funkin.menus.FreeplayState());
	}

	function saveJSON():Void
	{
		#if sys
		var path = _getSavePath(false);
		try
		{
			_ensureDir(path);
			File.saveContent(path, Json.stringify(stageData, null, '\t'));
			currentFilePath = path;
			hasUnsavedChanges = false;
			unsavedDot.visible = false;
			modBadge.text = _modLabel();
			setStatus('Saved: $path');
		}
		catch (e:Dynamic)
		{
			setStatus('ERROR saving: $e');
		}
		#end
	}

	function saveToMod():Void
	{
		#if sys
		if (!ModManager.isActive())
		{
			setStatus('No active mod — using base path');
			saveJSON();
			return;
		}
		var path = _getSavePath(true);
		try
		{
			_ensureDir(path);
			File.saveContent(path, Json.stringify(stageData, null, '\t'));
			currentFilePath = path;
			hasUnsavedChanges = false;
			unsavedDot.visible = false;
			setStatus('Saved in mod: $path');
		}
		catch (e:Dynamic)
		{
			setStatus('ERROR saving in mod: $e');
		}
		#end
	}

	function loadJSON():Void
	{
		#if sys
		_fileRef = new FileReference();
		_fileRef.addEventListener(Event.SELECT, function(e:Event)
		{
			_fileRef.addEventListener(Event.COMPLETE, function(e2:Event)
			{
				try
				{
					var raw = _fileRef.data.toString();
					stageData = Json.parse(raw);
					history = [];
					historyIndex = -1;
					_stageDataReady = true; // data is now in memory — use __fromData__ for rebuilds
					saveHistory();
					reloadStageView();
					refreshLayerPanel();
					currentFilePath = _fileRef.name;
					hasUnsavedChanges = false;
					unsavedDot.visible = false;
					setStatus('Stage loaded: ' + _fileRef.name);
				}
				catch (e:Dynamic)
				{
					setStatus('Error parsing JSON: $e');
				}
			});
			_fileRef.load();
		});
		_fileRef.browse([new openfl.net.FileFilter('Stage JSON', '*.json')]);
		#end
	}

	function browseAsset():Void
	{
		#if sys
		_fileRef = new FileReference();
		_fileRef.addEventListener(Event.SELECT, function(e:Event)
		{
			_fileRef.addEventListener(Event.COMPLETE, function(e2:Event)
			{
				var filename = _fileRef.name;

				// Determine destination folder based on active mod
				var stageName = stageData.name ?? 'stage';
				var destDir:String;
				if (ModManager.isActive())
					destDir = '${ModManager.modRoot()}/stages/$stageName/images';
				else
					destDir = 'assets/stages/$stageName/images';

				// ── ¿Es un Texture Atlas root? (Animation.json / spritemap*.json) ──
				var isAnimateRoot = (filename == 'Animation.json'
					|| (filename.startsWith('spritemap') && filename.endsWith('.json')));

				// Strip extension to get asset key
				var assetKey = filename;
				if      (assetKey.endsWith('.png'))  assetKey = assetKey.substr(0, assetKey.length - 4);
				else if (assetKey.endsWith('.jpg'))  assetKey = assetKey.substr(0, assetKey.length - 4);
				else if (assetKey.endsWith('.jpeg')) assetKey = assetKey.substr(0, assetKey.length - 5);
				else if (assetKey.endsWith('.xml'))  assetKey = assetKey.substr(0, assetKey.length - 4);
				else if (assetKey.endsWith('.txt'))  assetKey = assetKey.substr(0, assetKey.length - 4);
				else if (assetKey.endsWith('.json')) assetKey = assetKey.substr(0, assetKey.length - 5);

				try
				{
					if (!FileSystem.exists(destDir))
						FileSystem.createDirectory(destDir);

					var bytes = _fileRef.data;
					if (bytes != null)
						sys.io.File.saveBytes('$destDir/$filename', bytes);

					// ── Copiar compañeros (XML/TXT para PNG, o carpeta entera para atlas) ──
					_copyCompanionFilesMain(filename, assetKey, destDir, isAnimateRoot);
				}
				catch (ex:Dynamic)
				{
					setStatus('Error copying asset: $ex');
				}

				// Para atlas: la clave es el nombre de la carpeta
				if (isAnimateRoot && _lastBrowseFolderName != '')
					assetKey = _lastBrowseFolderName;

				if (elemAssetInput != null)
					elemAssetInput.text = assetKey;

				setStatus('Asset copiado → $destDir/$assetKey');
			});
			_fileRef.load();
		});
		_fileRef.addEventListener(Event.CANCEL, function(_)
		{
			setStatus('Browse cancelled.');
		});
		_fileRef.addEventListener(IOErrorEvent.IO_ERROR, function(_)
		{
			setStatus('Error opening file browser.');
		});
		_fileRef.browse([new openfl.net.FileFilter(
			'Sprite assets (PNG, XML, TXT, Animation.json, spritemap.json)',
			'*.png;*.jpg;*.jpeg;*.xml;*.txt;*.json'
		)]);
		#end
	}

	/** Último nombre de carpeta de atlas importado desde browseAsset() del panel principal. */
	var _lastBrowseFolderName:String = '';

	/**
	 * Versión de _copyCompanionFiles usada desde el panel de propiedades principal.
	 * Misma lógica que AddElementSubState._copyCompanionFiles pero usa _lastBrowseFolderName.
	 */
	function _copyCompanionFilesMain(filename:String, assetKey:String,
		destDir:String, isAnimateRoot:Bool):Void
	{
		#if sys
		// Recuperar directorio origen
		var srcDir:String = '';
		try
		{
			@:privateAccess
			{
				var rawPath:Dynamic = null;
				if (Reflect.hasField(_fileRef, '__path'))
					rawPath = Reflect.field(_fileRef, '__path');
				else if (Reflect.hasField(_fileRef, '_path'))
					rawPath = Reflect.field(_fileRef, '_path');

				if (rawPath != null)
				{
					var fullPath:String = Std.string(rawPath).replace('\\\\', '/');
					var slash = fullPath.lastIndexOf('/');
					if (slash >= 0) srcDir = fullPath.substr(0, slash + 1);
				}
			}
		}
		catch (_:Dynamic) {}

		if (srcDir == '')
		{
			trace('[StageEditor] browseAsset: no se pudo leer el path origen — copia manual necesaria.');
			return;
		}

		if (!isAnimateRoot)
		{
			// Caso PNG/XML/TXT: copiar hermanos
			for (comp in ['$assetKey.png', '$assetKey.xml', '$assetKey.txt'])
			{
				var src = '$srcDir$comp';
				var dst = '$destDir/$comp';
				if (comp != filename && FileSystem.exists(src) && !FileSystem.exists(dst))
				{
					sys.io.File.copy(src, dst);
					trace('[StageEditor] browseAsset companion: $comp');
				}
			}
			return;
		}

		// Caso Texture Atlas: copiar carpeta entera
		var trimmed    = srcDir.endsWith('/') ? srcDir.substr(0, srcDir.length - 1) : srcDir;
		var lastSlash  = trimmed.lastIndexOf('/');
		var folderName = lastSlash >= 0 ? trimmed.substr(lastSlash + 1) : assetKey;
		_lastBrowseFolderName = folderName;

		var bundleDest = '$destDir/$folderName';
		if (!FileSystem.exists(bundleDest))
			FileSystem.createDirectory(bundleDest);

		for (entry in FileSystem.readDirectory(srcDir))
		{
			var entryPath = '$srcDir$entry';
			if (FileSystem.isDirectory(entryPath))
			{
				var subDest = '$bundleDest/$entry';
				if (!FileSystem.exists(subDest)) FileSystem.createDirectory(subDest);
				for (sub in FileSystem.readDirectory(entryPath))
				{
					var subSrc = '$entryPath/$sub';
					var subDst = '$subDest/$sub';
					if (!FileSystem.isDirectory(subSrc) && !FileSystem.exists(subDst))
						sys.io.File.copy(subSrc, subDst);
				}
			}
			else
			{
				var dst = '$bundleDest/$entry';
				if (!FileSystem.exists(dst))
					sys.io.File.copy(entryPath, dst);
			}
		}
		trace('[StageEditor] browseAsset atlas bundle copiado: $folderName → $bundleDest');
		#end
	}

	// ─────────────────────────────────────────────────────────────────────────
	// HISTORY (UNDO / REDO)
	// ─────────────────────────────────────────────────────────────────────────

	function saveHistory():Void
	{
		if (historyIndex < history.length - 1)
			history.splice(historyIndex + 1, history.length - historyIndex - 1);

		history.push(Json.stringify(stageData));
		historyIndex = history.length - 1;

		if (history.length > 60)
		{
			history.shift();
			historyIndex--;
		}
	}

	function undo():Void
	{
		if (historyIndex <= 0)
			return;
		historyIndex--;
		stageData = Json.parse(history[historyIndex]);
		_stageDataReady = true;
		selectedIdx = -1;
		selectedIndices = [];
		selectedCharId = null;
		reloadStageView();
		_updateSelectionInfoBar();
		refreshLayerPanel();
		markUnsaved();
		setStatus('Undo \u2190  (${historyIndex + 1}/${history.length})');
	}

	function redo():Void
	{
		if (historyIndex >= history.length - 1)
			return;
		historyIndex++;
		stageData = Json.parse(history[historyIndex]);
		_stageDataReady = true;
		selectedIdx = -1;
		selectedIndices = [];
		selectedCharId = null;
		reloadStageView();
		_updateSelectionInfoBar();
		refreshLayerPanel();
		markUnsaved();
		setStatus('Redo \u2192  (${historyIndex + 1}/${history.length})');
	}

	// ─────────────────────────────────────────────────────────────────────────
	// HELPERS
	// ─────────────────────────────────────────────────────────────────────────

	function reloadStageView():Void
	{
		loadStageIntoCanvas();
		_selBoxW = 0;
		_selBoxH = 0;
		_selMeshW = 0;
		_selMeshH = 0;
		if (selBox != null)
			selBox.visible = false;
		if (selMesh != null)
			selMesh.visible = false;
		syncCharsTabUI();
	}

	/** Sincroniza los steppers del tab Chars con los valores actuales de stageData.
	 *  Llamar después de cualquier operación que pueda haber modificado posiciones de personajes
	 *  o después de reloadStageView() para mantener la UI consistente. */
	function syncCharsTabUI():Void
	{
		var bfPos  = stageData.boyfriendPosition  ?? [770.0, 450.0];
		var gfPos  = stageData.gfPosition          ?? [400.0, 130.0];
		var dadPos = stageData.dadPosition          ?? [100.0, 100.0];
		var camBF  = stageData.cameraBoyfriend      ?? [0.0, 0.0];
		var camDad = stageData.cameraDad            ?? [0.0, 0.0];

		if (bfXStepper  != null) bfXStepper.value  = bfPos[0];
		if (bfYStepper  != null) bfYStepper.value  = bfPos[1];
		if (gfXStepper  != null) gfXStepper.value  = gfPos[0];
		if (gfYStepper  != null) gfYStepper.value  = gfPos[1];
		if (dadXStepper != null) dadXStepper.value = dadPos[0];
		if (dadYStepper != null) dadYStepper.value = dadPos[1];
		if (camBFXStepper  != null) camBFXStepper.value  = camBF[0];
		if (camBFYStepper  != null) camBFYStepper.value  = camBF[1];
		if (camDadXStepper != null) camDadXStepper.value = camDad[0];
		if (camDadYStepper != null) camDadYStepper.value = camDad[1];
		if (gfVersionInput != null) gfVersionInput.text  = stageData.gfVersion ?? 'gf';
	}

	function markUnsaved():Void
	{
		hasUnsavedChanges = true;
		unsavedDot.visible = true;
	}

	function setStatus(msg:String):Void
	{
		if (statusText != null)
			statusText.text = msg;
		trace('[StageEditor] $msg');
	}

	/** True si algún input de texto tiene el foco.
	 *  Mientras el usuario escribe, las flechas/delete NO deben mover el elemento. */
	function isTyping():Bool
	{
		if (elemNameInput != null && elemNameInput.hasFocus)
			return true;
		if (elemAssetInput != null && elemAssetInput.hasFocus)
			return true;
		if (elemColorInput != null && elemColorInput.hasFocus)
			return true;
		if (animNameInput != null && animNameInput.hasFocus)
			return true;
		if (animPrefixInput != null && animPrefixInput.hasFocus)
			return true;
		if (animIndicesInput != null && animIndicesInput.hasFocus)
			return true;
		if (animFirstInput != null && animFirstInput.hasFocus)
			return true;
		if (stageNameInput != null && stageNameInput.hasFocus)
			return true;
		if (gfVersionInput != null && gfVersionInput.hasFocus)
			return true;
		return false;
	}

	function isMouseOverUI():Bool
	{
		var mx = FlxG.mouse.gameX;
		var my = FlxG.mouse.gameY;
		return my < TOP_H || my > FlxG.height - STATUS_H || mx < LEFT_W || mx > FlxG.width - RIGHT_W;
	}

	// ── Lock helpers ──────────────────────────────────────────────────────────

	/** Shows or hides the backdrop properties section in the Element tab. */
	/**
	 * Central function that shows / hides type-specific widgets in the Element tab
	 * based on the current element type.  Call this whenever the type changes
	 * (type dropdown callback, syncElementFieldsToUI).
	 *
	 * Rules:
	 *  – 'graphic'  → show GRAPHIC PROPERTIES, hide Asset path
	 *  – 'group'    → hide Asset path (groups have no external asset)
	 *  – 'backdrop' → show BACKDROP PROPERTIES, hide GRAPHIC PROPERTIES
	 *  – others     → show Asset path, hide both type-specific panels
	 */
	function _updateTypeWidgets(type:String):Void
	{
		var isGraphic  = (type == 'graphic');
		var isBackdrop = (type == 'backdrop');
		var isGroup    = (type == 'group');
		// Anims tab is relevant for: 'animated' (Sparrow atlas), 'sprite' (may have XML companion)
		// and 'atlas' (Texture Atlas / FunkinSprite.loadAnimateAtlas — misma API addAnim/playAnim)
		var isAnimCompatible = (type == 'animated' || type == 'sprite' || type == 'atlas'
			|| type == 'animate_atlas' || type == 'texture_atlas');

		// Asset path: visible for all types that load an external file
		var showAsset = !isGraphic && !isGroup;
		for (w in _assetWidgets)
			if (w != null) w.visible = showAsset;

		// Graphic properties panel (width/height/fill colour)
		for (w in _graphicWidgets)
			if (w != null) w.visible = isGraphic;

		// Backdrop properties panel (repeat axes / scroll velocity)
		for (w in _backdropWidgets)
			if (w != null) w.visible = isBackdrop;

		// Do NOT touch _animTabWidgets visibility here — CoolTabMenu owns that flag
		// internally to show/hide the active tab. Overriding it causes the content
		// of the inactive tab to bleed into the active one.
		// Visibility of the Anims tab is controlled exclusively via the mask below.

		// Show/hide the mask that covers the "Anims" tab header
		if (_animTabMask != null)
			_animTabMask.visible = !isAnimCompatible;

		// Hide the anim-list state-level overlay when switching to a non-compatible type
		if (!isAnimCompatible)
		{
			_animTabVisible = false;
			if (animListBg   != null) animListBg.visible   = false;
			if (animListText != null) animListText.visible = false;
		}
	}

	function _setBackdropPanelVisible(visible:Bool):Void
	{
		for (w in _backdropWidgets)
			if (w != null)
				w.visible = visible;
	}

	function _setGraphicPanelVisible(visible:Bool):Void
	{
		for (w in _graphicWidgets)
			if (w != null)
				w.visible = visible;
	}

	/** Returns true when the element at idx has locked:true. */
	inline function _elemIsLocked(idx:Int):Bool
	{
		return idx >= 0 && idx < stageData.elements.length && stageData.elements[idx].locked == true;
	}

	/**
	 * Recolors the row-background sprite for element [idx] in-place.
	 * Called on hover-in / hover-out instead of a full panel rebuild.
	 * Only paints over the BitmapData that already exists — zero alloc.
	 */
	function _recolorLayerRow(idx:Int):Void
	{
		if (idx < 0 || idx >= stageData.elements.length) return;
		var spr = _layerRowBgMap.get(idx);
		if (spr == null) return;

		var T = EditorTheme.current;
		var elem = stageData.elements[idx];
		var isSelected = (idx == selectedIdx || selectedIndices.contains(idx));
		var isHovered  = (idx == layerHoverIdx && !isSelected);
		var isAbove    = (elem.aboveChars == true);
		var isCharType = (elem.type != null && elem.type.toLowerCase() == 'character');

		var color:Int;
		if (isSelected)
		{
			color = T.rowSelected;
		}
		else if (isHovered)
		{
			color = T.rowSelected & 0x00FFFFFF | 0x55000000;
		}
		else if (isCharType)
		{
			color = switch ((elem.charSlot ?? 'bf').toLowerCase())
			{
				case 'gf', 'girlfriend', 'spectator': 0xFF2A002A;
				case 'dad', 'opponent', 'player2':   0xFF2A1A00;
				default: 0xFF002A3A;
			};
		}
		else if (isAbove)
		{
			color = 0xFF2A1A00;
		}
		else
		{
			// Even/odd — we don't track the draw-order parity here so use rowEven as neutral
			color = T.rowEven;
		}

		spr.makeGraphic(LEFT_W, ROW_H, color);
	}

	// ── Shader helpers ────────────────────────────────────────────────────────

	/** Opens a native file picker to import a .frag shader into the engine's shader folder. */
	function _importShader():Void
	{
		#if sys
		_shaderFileRef = new FileReference();
		_shaderFileRef.addEventListener(Event.SELECT, function(_)
		{
			_shaderFileRef.addEventListener(Event.COMPLETE, function(_)
			{
				var filename = _shaderFileRef.name;
				if (!filename.endsWith('.frag'))
				{
					setStatus('Import error: only .frag files supported');
					return;
				}
				var destDir = (ModManager.isActive())
					? '${ModManager.modRoot()}/shaders'
					: 'assets/shaders';
				try
				{
					if (!FileSystem.exists(destDir)) FileSystem.createDirectory(destDir);
					File.saveBytes('$destDir/$filename', _shaderFileRef.data);
				}
				catch (ex:Dynamic) { setStatus('Import error: $ex'); return; }

				ShaderManager.scanShaders();
				_shaderList = ['(none)'].concat(ShaderManager.getAvailableShaders());
				var labels = CoolDropDown.makeStrIdLabelArray(_shaderList, true);
				if (stageShaderDropdown != null) stageShaderDropdown.setData(labels);
				if (elemShaderDropdown   != null) elemShaderDropdown.setData(labels);
				setStatus('Shader imported: $filename');
			});
			_shaderFileRef.load();
		});
		_shaderFileRef.addEventListener(Event.CANCEL, function(_) {});
		_shaderFileRef.browse([new openfl.net.FileFilter('GLSL Fragment Shader', '*.frag')]);
		#end
	}

	/**
	 * Opens ShaderEditorSubState — a text editor for writing/editing .frag code.
	 * If shaderName is non-null and the file exists on disk, its code is pre-loaded.
	 * On save the file is written to disk and the shader is hot-reloaded & applied live.
	 */
	function _openShaderEditor(?shaderName:String):Void
	{
		var initialCode = '// My shader\nvoid main()\n{\n\tgl_FragColor = flixel_texture2D(bitmap, openfl_TextureCoordv);\n}\n';
		var editingName  = shaderName ?? 'new_shader';

		#if sys
		if (shaderName != null && shaderName != '' && ShaderManager.shaderPaths.exists(shaderName))
		{
			try { initialCode = File.getContent(ShaderManager.shaderPaths.get(shaderName)); }
			catch (_:Dynamic) {}
		}
		#end

		var editorSpr:FlxSprite = (selectedIdx >= 0 && selectedIdx < stageData.elements.length)
			? (stageData.elements[selectedIdx].name != null
				? elementSprites.get(stageData.elements[selectedIdx].name)
				: null)
			: null;

		openSubState(new ShaderEditorSubState(editingName, initialCode, editorSpr, camGame,
			function(savedName:String, savedCode:String)
			{
				// Refresh lists and re-apply to selected element if any
				ShaderManager.scanShaders();
				_shaderList = ['(none)'].concat(ShaderManager.getAvailableShaders());
				var lbs = CoolDropDown.makeStrIdLabelArray(_shaderList, true);
				if (stageShaderDropdown != null) stageShaderDropdown.setData(lbs);
				if (elemShaderDropdown   != null) elemShaderDropdown.setData(lbs);

				if (editorSpr != null && selectedIdx >= 0 && selectedIdx < stageData.elements.length)
				{
					var elem = stageData.elements[selectedIdx];
					if (elem.customProperties == null) elem.customProperties = {};
					Reflect.setField(elem.customProperties, 'shader', savedName);
					try { ShaderManager.applyShader(editorSpr, savedName, camGame); } catch (_:Dynamic) {}
					if (elemShaderDropdown != null && _shaderList.contains(savedName))
						elemShaderDropdown.selectedLabel = savedName;
					markUnsaved();
				}
				setStatus('Shader "$savedName" saved');
			}
		));
	}

	/**
	 * Opens ShaderParamsSubState — parses the .frag uniforms of the currently
	 * assigned shader and shows sliders / inputs for each one.
	 * Values are saved to customProperties.shaderParams in the JSON and applied live.
	 */
	function _openShaderParams():Void
	{
		if (selectedIdx < 0 || selectedIdx >= stageData.elements.length)
		{
			setStatus('Select an element first');
			return;
		}
		var elem = stageData.elements[selectedIdx];
		var shaderName:String = '';
		if (elem.customProperties != null)
		{
			var sh = Reflect.field(elem.customProperties, 'shader');
			if (sh != null) shaderName = Std.string(sh);
		}
		if (shaderName == '' || shaderName == '(none)')
		{
			setStatus('Assign a shader to this element first');
			return;
		}

		// Read .frag source from disk for uniform parsing
		var fragSrc = '';
		#if sys
		if (ShaderManager.shaderPaths.exists(shaderName))
		{
			try { fragSrc = File.getContent(ShaderManager.shaderPaths.get(shaderName)); }
			catch (_:Dynamic) {}
		}
		#end

		// Gather existing params from JSON
		var existingParams:Dynamic = {};
		if (elem.customProperties != null)
		{
			var sp = Reflect.field(elem.customProperties, 'shaderParams');
			if (sp != null) existingParams = sp;
		}

		var spr = (elem.name != null && elementSprites.exists(elem.name))
			? elementSprites.get(elem.name)
			: null;

		openSubState(new ShaderParamsSubState(shaderName, fragSrc, existingParams, spr, camGame,
			function(params:Dynamic)
			{
				if (elem.customProperties == null) elem.customProperties = {};
				Reflect.setField(elem.customProperties, 'shaderParams', params);
				markUnsaved();
				saveHistory();
				setStatus('Shader params saved for "${elem.name}"');
			}
		));
	}

	function _modLabel():String
	{
		return ModManager.isActive() ? 'Mod: ${ModManager.activeMod}' : 'Base Game';
	}

	// ── Character layer helpers ───────────────────────────────────────────────

	/**
	 * Normalises a charSlot string to one of the three canonical ids used in
	 * the `characters` Map: "bf", "gf" or "dad".
	 */
	inline function _normalizeSlot(slot:String):String
	{
		return switch (slot.toLowerCase())
		{
			case 'bf', 'player', 'player1': 'bf';
			case 'gf', 'girlfriend', 'spectator': 'gf';
			case 'dad', 'opponent', 'player2': 'dad';
			default: slot.toLowerCase();
		};
	}

	/**
	 * Returns the index of the first character-type element with the given
	 * normalised slot name, or -1 if not found.
	 */
	function _charEntryIndex(slot:String):Int
	{
		for (i in 0...stageData.elements.length)
		{
			var e = stageData.elements[i];
			if (e.type != null && e.type.toLowerCase() == 'character'
				&& _normalizeSlot(e.charSlot ?? '') == slot)
				return i;
		}
		return -1;
	}

	/**
	 * Ensures BF, GF and DAD always appear as type:"character" entries in
	 * stageData.elements so they show up in the layer panel.
	 *
	 * Missing entries are inserted just before the first aboveChars:true element
	 * (or at the end of the array when none exists), in the order:
	 *   dad (bottom) → gf → bf (top)
	 *
	 * Existing entries are never moved or duplicated.
	 */
	function _ensureCharacterEntries():Void
	{
		if (stageData == null || stageData.elements == null)
			return;

		var hasBf  = _charEntryIndex('bf')  >= 0;
		var hasGf  = _charEntryIndex('gf')  >= 0;
		var hasDad = _charEntryIndex('dad') >= 0;

		if (hasBf && hasGf && hasDad)
			return; // nothing to do

		// Find insertion point: just before the first aboveChars element, or at end
		var insertAt = stageData.elements.length;
		for (i in 0...stageData.elements.length)
		{
			if (stageData.elements[i].aboveChars == true)
			{
				insertAt = i;
				break;
			}
		}

		// Helper to build a minimal character element entry
		function makeCharElem(slot:String):StageElement
		{
			return {
				type: 'character',
				name: 'char_$slot',
				charSlot: slot,
				asset: '',
				position: [0.0, 0.0],
				scrollFactor: [1.0, 1.0],
				scale: [1.0, 1.0],
				alpha: 1.0,
				visible: true,
				antialiasing: true,
				zIndex: 0
			};
		}

		// Insert in reverse desired order so the final array reads dad → gf → bf
		// (lower index = rendered first = further behind).

		// bf on top (insert first at insertAt, then gf and dad push it down)
		if (!hasBf)
			stageData.elements.insert(insertAt, makeCharElem('bf'));

		// gf below bf
		if (!hasGf && !(stageData.hideGirlfriend == true))
		{
			var bfIdx = _charEntryIndex('bf');
			stageData.elements.insert(bfIdx >= 0 ? bfIdx : insertAt, makeCharElem('gf'));
		}

		// dad below gf (and bf)
		if (!hasDad)
		{
			var gfIdx = _charEntryIndex('gf');
			var bfIdx = _charEntryIndex('bf');
			var dadAt = gfIdx >= 0 ? gfIdx : (bfIdx >= 0 ? bfIdx : insertAt);
			stageData.elements.insert(dadAt, makeCharElem('dad'));
		}
	}

	/**
	 * Adds individual character sprites to the FlxState at the z-positions
	 * dictated by the order of type:"character" entries in stageData.elements.
	 *
	 * Called after loadCharacters() so the `characters` Map is populated.
	 * Any characters without a matching entry are appended at the end as fallback.
	 * After all characters are placed, stageAboveGroup is added (if present).
	 */
	function _addCharsInOrder():Void
	{
		// ── Char-anchor system: interleave stage sprites AND characters ────────
		// In this mode sprites were NOT added in loadStageIntoCanvas() so we own
		// all add() calls here. Walk stageData.elements in order → the FlxState
		// draw order matches the layer panel 1-to-1, including characters placed
		// between (or around) individual stage sprites.
		if (stage != null && stage._useCharAnchorSystem)
		{
			var placedChars:Array<String>  = [];
			var addedSprites:Array<flixel.FlxBasic> = [];

			for (elem in stageData.elements)
			{
				if (elem.type != null && elem.type.toLowerCase() == 'character')
				{
					// ── character slot ───────────────────────────────────────
					var cid = _normalizeSlot(elem.charSlot ?? 'bf');
					if (!placedChars.contains(cid))
					{
						var c = characters.get(cid);
						if (c != null)
						{
							c.cameras = [camGame];
							add(c);
							placedChars.push(cid);
						}
					}
				}
				else if (elem.name != null && elementSprites.exists(elem.name))
				{
					// ── regular stage element ────────────────────────────────
					var spr:flixel.FlxBasic = elementSprites.get(elem.name);
					if (spr != null && !addedSprites.contains(spr))
					{
						add(spr);
						addedSprites.push(spr);
					}
				}
			}

			// Fallback A: any spriteList entry not yet added (e.g. sprites not in
			// elementSprites because they come from custom classes or sub-groups)
			for (entry in stage.spriteList)
			{
				if (entry.sprite != null && !addedSprites.contains(entry.sprite))
				{
					add(entry.sprite);
					addedSprites.push(entry.sprite);
				}
			}

			// Fallback B: any character not covered by a character entry
			for (cid in ['dad', 'gf', 'bf'])
			{
				if (!placedChars.contains(cid) && characters.exists(cid))
				{
					var c = characters.get(cid);
					c.cameras = [camGame];
					add(c);
				}
			}

			return;
		}

		// ── Non-char-anchor system: only add character sprites ─────────────────
		// Stage sprites are already inside the `stage` FlxTypedGroup (added in
		// loadStageIntoCanvas). We just need to add individual characters in the
		// order dictated by stageData.elements so their relative draw order is
		// correct (dad behind gf behind bf, or whatever the user configured).
		var placed:Array<String> = [];

		for (elem in stageData.elements)
		{
			if (elem.type == null || elem.type.toLowerCase() != 'character')
				continue;
			var cid = _normalizeSlot(elem.charSlot ?? 'bf');
			if (placed.contains(cid))
				continue;
			var c = characters.get(cid);
			if (c != null)
			{
				c.cameras = [camGame];
				add(c);
				placed.push(cid);
			}
		}

		// Fallback: add any character not covered by an entry (backward compat)
		for (cid in ['dad', 'gf', 'bf'])
		{
			if (!placed.contains(cid) && characters.exists(cid))
			{
				var c = characters.get(cid);
				c.cameras = [camGame];
				add(c);
			}
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	// DESTROY
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Propaga una lista de cámaras a TODOS los FlxBasic dentro de un grupo,
	 * bajando recursivamente a sub-grupos (FlxTypedGroup dentro de FlxTypedGroup).
	 *
	 * FlxGroup.cameras solo actualiza el campo del grupo en sí y los NUEVOS
	 * miembros que se añadan DESPUÉS de la asignación. Los miembros ya existentes
	 * en el momento de la asignación NO reciben la cámara — hay que hacerlo manual.
	 * Sin este fix, los sprites dentro de stage.groups tienen cameras=[] y
	 * Flixel no puede compilar el programa GL del shader ("no camera detected").
	 */
	function _assignCamerasRecursive(group:flixel.group.FlxGroup, cams:Array<FlxCamera>):Void
	{
		for (member in group.members)
		{
			if (member == null)
				continue;
			member.cameras = cams;
			// Si el miembro es a su vez un grupo, bajar recursivamente
			if (Std.isOfType(member, flixel.group.FlxGroup))
				_assignCamerasRecursive(cast member, cams);
		}
	}

	override public function destroy():Void
	{
		dragStart.put();
		dragObjStart.put();
		dragCamStart.put();
		dragCamScrollStart.put();
		if (stage != null)
		{
			stage.destroy();
			stage = null;
		}
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

// ─────────────────────────────────────────────────────────────────────────────
//  NewStageSubState
// ─────────────────────────────────────────────────────────────────────────────

/**
 * A small dialog box that asks for the name of the new stage and triggers the callback.
 */
class NewStageSubState extends flixel.FlxSubState
{
	var _onConfirm:String->Void;
	var _camSub:flixel.FlxCamera;
	var _nameInput:CoolInputText;

	static inline final W:Int = 380;
	static inline final H:Int = 170;

	public function new(cameras:Array<FlxCamera>, onConfirm:String->Void)
	{
		super();
		_onConfirm = onConfirm;
		this.cameras = cameras;
	}

	override function create():Void
	{
		super.create();

		_camSub = new flixel.FlxCamera();
		_camSub.bgColor.alpha = 0;
		FlxG.cameras.add(_camSub, false);
		cameras = [_camSub];

		var T = EditorTheme.current;
		var panX = (FlxG.width  - W) * 0.5;
		var panY = (FlxG.height - H) * 0.5;

		// Overlay
		var ov = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xCC000000);
		ov.scrollFactor.set(); ov.cameras = [_camSub]; add(ov);

		// Panel
		var pan = new FlxSprite(panX, panY).makeGraphic(W, H, T.bgPanel);
		pan.scrollFactor.set(); pan.cameras = [_camSub]; add(pan);

		var border = new FlxSprite(panX, panY).makeGraphic(W, 3, T.accent);
		border.scrollFactor.set(); border.cameras = [_camSub]; add(border);

		var title = new FlxText(panX + 14, panY + 10, W - 28, '\u2606  NEW STAGE', 16);
		title.setFormat(Paths.font('vcr.ttf'), 16, T.accent, LEFT);
		title.scrollFactor.set(); title.cameras = [_camSub]; add(title);

		var lbl = new FlxText(panX + 14, panY + 46, W - 28, 'Stage name  (used as file name and stage ID):', 10);
		lbl.color = T.textSecondary;
		lbl.scrollFactor.set(); lbl.cameras = [_camSub]; add(lbl);

		_nameInput = new CoolInputText(panX + 14, panY + 62, W - 28, 'my_stage', 11);
		_nameInput.scrollFactor.set(); _nameInput.cameras = [_camSub]; add(_nameInput);

		var note = new FlxText(panX + 14, panY + 86, W - 28,
			'Tip: use lowercase letters, numbers and underscores only.\nFile will be saved to  assets/stages/<name>.json', 9);
		note.color = T.textDim;
		note.scrollFactor.set(); note.cameras = [_camSub]; add(note);

		var confirmBtn = new CoolButton(panX + 14, panY + H - 34, 'Create Stage', function()
		{
			var n = _nameInput.text.trim();
			if (n == '') n = 'my_stage';
			// Sanitise: keep only safe characters
			n = ~/[^a-zA-Z0-9_\-]/.replace(n, '_');
			_onConfirm(n);
			close();
		});
		confirmBtn.cameras = [_camSub]; add(confirmBtn);

		var cancelBtn = new CoolButton(panX + W - 100, panY + H - 34, 'Cancel', close);
		cancelBtn.cameras = [_camSub]; add(cancelBtn);

		var hint = new FlxText(panX + 14, panY + H - 16, W - 28, 'ESC to cancel', 9);
		hint.color = T.textDim;
		hint.scrollFactor.set(); hint.cameras = [_camSub]; add(hint);
	}

	override function close():Void
	{
		if (_camSub != null) { FlxG.cameras.remove(_camSub, true); _camSub = null; }
		super.close();
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);
		if (FlxG.keys.justPressed.ESCAPE) close();
	}
}

// ─────────────────────────────────────────────────────────────────────────────
//  StageListSubState
// ─────────────────────────────────────────────────────────────────────────────

/** Entry shown in the stage list. */
private typedef StageEntry =
{
	name:String,   // stage ID (file name without .json)
	path:String,   // full path to the JSON on disk
	source:String  // "base" | "mod" | mod-id string
}

/**
 * Dialog flotante que muestra todos los stages encontrados en disco con un
 * buscador y carga el seleccionado al editor.
 */
class StageListSubState extends flixel.FlxSubState
{
	var _onSelect:String->String->Void; // (stageName, stagePath)
	var _camSub:flixel.FlxCamera;

	// Layout
	static inline final W:Int     = 520;
	static inline final H:Int     = 440;
	static inline final ROW_H:Int = 30;
	static inline final VISIBLE:Int = 10;

	// Data
	var _allEntries:Array<StageEntry> = [];
	var _filtered:Array<StageEntry>   = [];
	var _scrollIdx:Int = 0;

	// UI objects (re-created on filter/scroll)
	var _rowGroup:FlxTypedGroup<FlxSprite>;
	var _textGroup:FlxTypedGroup<FlxText>;
	var _hitData:Array<{y:Float, h:Int, idx:Int}> = [];

	// Filter
	var _filterInput:CoolInputText;
	var _lastFilter:String = '';

	// Scroll buttons
	var _btnUp:FlxSprite;
	var _btnDown:FlxSprite;
	var _btnUpTxt:FlxText;
	var _btnDownTxt:FlxText;
	var _countTxt:FlxText;

	// Panel origin (stored for row rebuild)
	var _panX:Float;
	var _panY:Float;

	public function new(cameras:Array<FlxCamera>, onSelect:String->String->Void)
	{
		super();
		_onSelect = onSelect;
		this.cameras = cameras;
	}

	override function create():Void
	{
		super.create();

		_camSub = new flixel.FlxCamera();
		_camSub.bgColor.alpha = 0;
		FlxG.cameras.add(_camSub, false);
		cameras = [_camSub];

		var T = EditorTheme.current;
		_panX = (FlxG.width  - W) * 0.5;
		_panY = (FlxG.height - H) * 0.5;

		// ── Overlay + panel ───────────────────────────────────────────────────
		var ov = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xCC000000);
		ov.scrollFactor.set(); ov.cameras = [_camSub]; add(ov);

		var pan = new FlxSprite(_panX, _panY).makeGraphic(W, H, T.bgPanel);
		pan.scrollFactor.set(); pan.cameras = [_camSub]; add(pan);

		var topBorder = new FlxSprite(_panX, _panY).makeGraphic(W, 3, T.accent);
		topBorder.scrollFactor.set(); topBorder.cameras = [_camSub]; add(topBorder);

		// ── Title ─────────────────────────────────────────────────────────────
		var title = new FlxText(_panX + 14, _panY + 10, W - 28, '\u25A4  STAGES', 16);
		title.setFormat(Paths.font('vcr.ttf'), 16, T.accent, LEFT);
		title.scrollFactor.set(); title.cameras = [_camSub]; add(title);

		// ── Search bar ────────────────────────────────────────────────────────
		var searchLbl = new FlxText(_panX + 14, _panY + 38, 60, 'Filter:', 10);
		searchLbl.color = T.textSecondary;
		searchLbl.scrollFactor.set(); searchLbl.cameras = [_camSub]; add(searchLbl);

		_filterInput = new CoolInputText(_panX + 70, _panY + 35, W - 84, '', 11);
		_filterInput.scrollFactor.set(); _filterInput.cameras = [_camSub]; add(_filterInput);

		// ── Column headers ────────────────────────────────────────────────────
		var hdrBg = new FlxSprite(_panX, _panY + 60).makeGraphic(W, 22, T.bgPanelAlt);
		hdrBg.scrollFactor.set(); hdrBg.cameras = [_camSub]; add(hdrBg);

		function hdrTxt(tx:Float, w:Int, t:String):Void
		{
			var h = new FlxText(_panX + tx, _panY + 63, w, t, 9);
			h.setFormat(Paths.font('vcr.ttf'), 9, T.textSecondary, LEFT);
			h.scrollFactor.set(); h.cameras = [_camSub]; add(h);
		}
		hdrTxt(10,  200, 'STAGE NAME');
		hdrTxt(218, 80,  'SOURCE');
		hdrTxt(308, W - 320, 'PATH');

		// ── Row groups (rebuilt on scroll/filter) ─────────────────────────────
		_rowGroup  = new FlxTypedGroup<FlxSprite>();
		_textGroup = new FlxTypedGroup<FlxText>();
		_rowGroup.cameras  = [_camSub];
		_textGroup.cameras = [_camSub];
		add(_rowGroup);
		add(_textGroup);

		// ── Scroll controls ───────────────────────────────────────────────────
		var ctrlY = _panY + H - 42;

		_btnUp = new FlxSprite(_panX + 14, ctrlY).makeGraphic(32, 26, T.bgPanelAlt);
		_btnUp.scrollFactor.set(); _btnUp.cameras = [_camSub]; add(_btnUp);
		_btnUpTxt = new FlxText(_panX + 14, ctrlY + 5, 32, '\u25B2', 11);
		_btnUpTxt.setFormat(Paths.font('vcr.ttf'), 11, T.textPrimary, CENTER);
		_btnUpTxt.scrollFactor.set(); _btnUpTxt.cameras = [_camSub]; add(_btnUpTxt);

		_btnDown = new FlxSprite(_panX + 50, ctrlY).makeGraphic(32, 26, T.bgPanelAlt);
		_btnDown.scrollFactor.set(); _btnDown.cameras = [_camSub]; add(_btnDown);
		_btnDownTxt = new FlxText(_panX + 50, ctrlY + 5, 32, '\u25BC', 11);
		_btnDownTxt.setFormat(Paths.font('vcr.ttf'), 11, T.textPrimary, CENTER);
		_btnDownTxt.scrollFactor.set(); _btnDownTxt.cameras = [_camSub]; add(_btnDownTxt);

		_countTxt = new FlxText(_panX + 90, ctrlY + 6, W - 200, '', 10);
		_countTxt.setFormat(Paths.font('vcr.ttf'), 10, T.textSecondary, LEFT);
		_countTxt.scrollFactor.set(); _countTxt.cameras = [_camSub]; add(_countTxt);

		var cancelBtn = new CoolButton(_panX + W - 100, ctrlY, 'Cancel', close);
		cancelBtn.cameras = [_camSub]; add(cancelBtn);

		var hint = new FlxText(_panX + 14, _panY + H - 16, W - 28, 'Click a row to load  •  ESC to cancel  •  ↑↓ to scroll', 9);
		hint.color = T.textDim;
		hint.scrollFactor.set(); hint.cameras = [_camSub]; add(hint);

		// ── Scan stages ───────────────────────────────────────────────────────
		_scanStages();
		_applyFilter('');
		_rebuildRows();
	}

	// ── Stage discovery ───────────────────────────────────────────────────────

	function _scanStages():Void
	{
		_allEntries = [];
		#if sys
		// Base game
		var basePath = 'assets/stages';
		if (sys.FileSystem.exists(basePath) && sys.FileSystem.isDirectory(basePath))
		{
			for (f in sys.FileSystem.readDirectory(basePath))
			{
				if (!f.endsWith('.json')) continue;
				var name = f.substr(0, f.length - 5);
				_allEntries.push({ name: name, path: '$basePath/$f', source: 'base' });
			}
		}

		// Active mod
		if (ModManager.isActive())
		{
			var modPath = '${ModManager.modRoot()}/stages';
			if (sys.FileSystem.exists(modPath) && sys.FileSystem.isDirectory(modPath))
			{
				for (f in sys.FileSystem.readDirectory(modPath))
				{
					if (!f.endsWith('.json')) continue;
					var name = f.substr(0, f.length - 5);
					// If base already has this name, mark it as mod override
					var existsInBase = Lambda.exists(_allEntries, function(e) return e.name == name && e.source == 'base');
					if (existsInBase)
						_allEntries = _allEntries.filter(e -> !(e.name == name && e.source == 'base'));
					_allEntries.push({ name: name, path: '$modPath/$f', source: ModManager.activeMod });
				}
			}
		}

		// Sort alphabetically
		_allEntries.sort((a, b) -> a.name < b.name ? -1 : (a.name > b.name ? 1 : 0));
		#end
	}

	// ── Filtering + row rebuild ───────────────────────────────────────────────

	function _applyFilter(q:String):Void
	{
		q = q.toLowerCase().trim();
		_filtered = (q == '') ? _allEntries.copy()
			: _allEntries.filter(e -> e.name.toLowerCase().contains(q) || e.source.toLowerCase().contains(q));
		_scrollIdx = 0;
	}

	function _rebuildRows():Void
	{
		var T = EditorTheme.current;

		// Clear old rows
		for (s in _rowGroup.members)  { if (s != null) { remove(s,  true); s.destroy(); } }
		for (t in _textGroup.members) { if (t != null) { remove(t,  true); t.destroy(); } }
		_rowGroup.clear();
		_textGroup.clear();
		_hitData = [];

		var listY = _panY + 82.0;
		var maxRow = Std.int(Math.min(VISIBLE, _filtered.length - _scrollIdx));

		for (ri in 0...maxRow)
		{
			var entry = _filtered[_scrollIdx + ri];
			var ry = listY + ri * ROW_H;
			var isEven = ri % 2 == 0;

			// Row background
			var rowBg = new FlxSprite(_panX, ry).makeGraphic(W, ROW_H - 1, isEven ? T.rowEven : T.rowOdd);
			rowBg.scrollFactor.set(); rowBg.cameras = [_camSub];
			add(rowBg); _rowGroup.add(rowBg);

			_hitData.push({ y: ry, h: ROW_H - 1, idx: _scrollIdx + ri });

			// Stage name
			var nameStr = entry.name.length > 26 ? entry.name.substr(0, 24) + '..' : entry.name;
			var nameTxt = new FlxText(_panX + 10, ry + 8, 200, nameStr, 10);
			nameTxt.setFormat(Paths.font('vcr.ttf'), 10, T.textPrimary, LEFT);
			nameTxt.scrollFactor.set(); nameTxt.cameras = [_camSub];
			add(nameTxt); _textGroup.add(nameTxt);

			// Source badge
			var srcColor = (entry.source == 'base') ? T.textDim : T.accent;
			var srcTxt = new FlxText(_panX + 218, ry + 8, 80, entry.source, 9);
			srcTxt.setFormat(Paths.font('vcr.ttf'), 9, srcColor, LEFT);
			srcTxt.scrollFactor.set(); srcTxt.cameras = [_camSub];
			add(srcTxt); _textGroup.add(srcTxt);

			// Path (dim, truncated)
			var shortPath = entry.path.length > 38 ? '..' + entry.path.substr(entry.path.length - 36) : entry.path;
			var pathTxt = new FlxText(_panX + 308, ry + 8, W - 320, shortPath, 8);
			pathTxt.setFormat(Paths.font('vcr.ttf'), 8, T.textDim, LEFT);
			pathTxt.scrollFactor.set(); pathTxt.cameras = [_camSub];
			add(pathTxt); _textGroup.add(pathTxt);

			// LOAD button on the right
			var btn = new CoolButton(_panX + W - 60, ry + 4, 'LOAD', function()
			{
				_onSelect(entry.name, entry.path);
				close();
			});
			btn.resize(56, ROW_H - 8);
			btn.cameras = [_camSub]; add(btn); _rowGroup.add(cast btn);
		}

		// Empty state
		if (_filtered.length == 0)
		{
			var emptyTxt = new FlxText(_panX + 14, listY + 10, W - 28,
				'No stages found.\nCreate a new one with \u2606 NEW, or check that stage JSON files exist in\nassets/stages/ or your mod\'s stages/ folder.', 11);
			emptyTxt.color = EditorTheme.current.textDim;
			emptyTxt.scrollFactor.set(); emptyTxt.cameras = [_camSub];
			add(emptyTxt); _textGroup.add(emptyTxt);
		}

		// Count label
		if (_countTxt != null)
			_countTxt.text = '${_filtered.length} stage${_filtered.length == 1 ? "" : "s"}  '
				+ '(${_scrollIdx + 1}–${Std.int(Math.min(_scrollIdx + VISIBLE, _filtered.length))} shown)';
	}

	// ── Update loop ───────────────────────────────────────────────────────────

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// close() removes _camSub synchronously. If it was called this frame
		// (e.g. via Cancel button or ESC), bail out before touching any camera-
		// dependent objects to avoid a null-pointer crash.
		if (_camSub == null) return;

		if (FlxG.keys.justPressed.ESCAPE) { close(); return; }

		// Re-filter when the input changes
		if (_filterInput != null && _filterInput.text != _lastFilter)
		{
			_lastFilter = _filterInput.text;
			_applyFilter(_lastFilter);
			_rebuildRows();
		}

		// Mouse-wheel scroll
		if (FlxG.mouse.wheel != 0)
		{
			_scrollIdx = Std.int(Math.max(0,
				Math.min(_filtered.length - VISIBLE, _scrollIdx - FlxG.mouse.wheel)));
			_rebuildRows();
		}

		// Keyboard scroll
		if (FlxG.keys.justPressed.UP   && !(_filterInput != null && _filterInput.hasFocus))
		{
			if (_scrollIdx > 0) { _scrollIdx--; _rebuildRows(); }
		}
		if (FlxG.keys.justPressed.DOWN && !(_filterInput != null && _filterInput.hasFocus))
		{
			if (_scrollIdx + VISIBLE < _filtered.length) { _scrollIdx++; _rebuildRows(); }
		}

		// Scroll button clicks
		if (FlxG.mouse.justPressed)
		{
			var mx = FlxG.mouse.gameX;
			var my = FlxG.mouse.gameY;

			// Up button
			if (_btnUp != null && mx >= _btnUp.x && mx <= _btnUp.x + _btnUp.width
				&& my >= _btnUp.y && my <= _btnUp.y + _btnUp.height)
			{
				if (_scrollIdx > 0) { _scrollIdx--; _rebuildRows(); }
				return;
			}
			// Down button
			if (_btnDown != null && mx >= _btnDown.x && mx <= _btnDown.x + _btnDown.width
				&& my >= _btnDown.y && my <= _btnDown.y + _btnDown.height)
			{
				if (_scrollIdx + VISIBLE < _filtered.length) { _scrollIdx++; _rebuildRows(); }
				return;
			}

			// Row click → select and load
			for (hit in _hitData)
			{
				if (my >= hit.y && my <= hit.y + hit.h
					&& mx >= _panX && mx <= _panX + W - 70) // avoid the LOAD btn area
				{
					if (hit.idx >= 0 && hit.idx < _filtered.length)
					{
						var e = _filtered[hit.idx];
						_onSelect(e.name, e.path);
						close();
						return;
					}
				}
			}
		}
	}

	override function close():Void
	{
		if (_camSub != null) { FlxG.cameras.remove(_camSub, true); _camSub = null; }
		super.close();
	}
}

// ─────────────────────────────────────────────────────────────────────────────
//  AddElementSubState
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Substate flotante para añadir un nuevo elemento al stage.
 * Muestra un formulario con tipo, nombre y asset, y llama al callback al confirmar.
 */
class AddElementSubState extends flixel.FlxSubState
{
	var onConfirm:StageElement->Void;

	var nameInput:CoolInputText;
	var assetInput:CoolInputText;
	var typeDropdown:CoolDropDown;

	static inline final W:Int = 420;
	static inline final H:Int = 320;

	var _camSub:flixel.FlxCamera;
	var _fileRef:FileReference;

	/** The stage name (passed from the editor) so we know where to copy assets. */
	var _stageName:String;

	/** Whether to copy to the active mod folder (true) or base assets (false). */
	var _toMod:Bool;

	public function new(cb:StageElement->Void, stageName:String = 'stage', toMod:Bool = false)
	{
		super();
		onConfirm = cb;
		_stageName = stageName;
		_toMod = toMod;
	}

	override function create():Void
	{
		super.create();

		_camSub = new flixel.FlxCamera();
		_camSub.bgColor.alpha = 0;
		FlxG.cameras.add(_camSub, false);
		cameras = [_camSub];

		var T = EditorTheme.current;
		var panX = (FlxG.width - W) * 0.5;
		var panY = (FlxG.height - H) * 0.5;

		var overlay = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xBB000000);
		overlay.scrollFactor.set();
		overlay.cameras = [_camSub];
		add(overlay);

		var panel = new FlxSprite(panX, panY).makeGraphic(W, H, T.bgPanel);
		panel.scrollFactor.set();
		panel.cameras = [_camSub];
		add(panel);

		var topBorder = new FlxSprite(panX, panY).makeGraphic(W, 3, T.borderColor);
		topBorder.scrollFactor.set();
		topBorder.cameras = [_camSub];
		add(topBorder);

		var title = new FlxText(panX + 12, panY + 10, W - 24, '\u2795  ADD ELEMENT', 16);
		title.setFormat(Paths.font('vcr.ttf'), 16, T.accent, LEFT);
		title.scrollFactor.set();
		title.cameras = [_camSub];
		add(title);

		var y = panY + 44.0;

		function lbl(t:String, ly:Float):Void
		{
			var tx = new FlxText(panX + 12, ly, 0, t, 10);
			tx.color = T.textSecondary;
			tx.scrollFactor.set();
			tx.cameras = [_camSub];
			add(tx);
		}

		lbl('Element Name:', y);
		nameInput = new CoolInputText(panX + 12, y + 14, W - 28, 'new_element', 11);
		nameInput.scrollFactor.set();
		nameInput.cameras = [_camSub];
		add(nameInput);

		y += 40;
		lbl('Type:', y);
		var types = ['sprite', 'animated', 'atlas', 'graphic', 'backdrop', 'group', 'custom_class', 'sound', 'character'];
		typeDropdown = new CoolDropDown(panX + 12, y + 14, CoolDropDown.makeStrIdLabelArray(types, true), null);
		typeDropdown.scrollFactor.set();
		typeDropdown.cameras = [_camSub];
		add(typeDropdown);

		y += 52;
		lbl('Asset path  (images/stages/… or browse to copy):', y);

		// Asset path input
		assetInput = new CoolInputText(panX + 12, y + 14, W - 110, 'myAsset', 11);
		assetInput.scrollFactor.set();
		assetInput.cameras = [_camSub];
		add(assetInput);

		// ── Browse button ──────────────────────────────────────────────────────
		// Opens a native file picker. The selected PNG/JPG/XML is copied to the
		// engine's asset folder (mod or base) and the asset path is filled in.
		var browseBtn = new CoolButton(panX + W - 96, y + 13, 'Browse...', _browseAsset);
		browseBtn.cameras = [_camSub];
		add(browseBtn);

		// Copy-destination info
		var destRoot = _toMod
			&& ModManager.isActive() ? '${ModManager.modRoot()}/stages/$_stageName/images' : 'assets/stages/$_stageName/images';
		var destInfo = new FlxText(panX + 12, y + 30, W - 28, '\u2192 copies to: $destRoot', 9);
		destInfo.color = T.textDim;
		destInfo.scrollFactor.set();
		destInfo.cameras = [_camSub];
		add(destInfo);

		y += 56;

		// Confirm / Cancel
		var confirmBtn = new CoolButton(panX + 12, y, 'Add Element', function()
		{
			var types2 = ['sprite', 'animated', 'atlas', 'graphic', 'backdrop', 'group', 'custom_class', 'sound', 'character'];
			var typeIdx = Std.parseInt(typeDropdown.selectedId);
			var typeName = (typeIdx != null && typeIdx >= 0 && typeIdx < types2.length) ? types2[typeIdx] : 'sprite';
			var newElem:StageElement = {
				type: typeName,
				name: nameInput.text.trim(),
				asset: '',
				position: [100.0, 100.0],
				scrollFactor: [1.0, 1.0],
				scale: [1.0, 1.0],
				alpha: 1.0,
				visible: true,
				antialiasing: true,
				zIndex: 0
			};
			if (typeName != 'character')
				newElem.asset = assetInput.text.trim();
			if (typeName == 'animated')
				newElem.animations = [
					{
						name: 'idle',
						prefix: 'idle0',
						framerate: 24,
						looped: true
					}
				];
			if (typeName == 'atlas')
				// Atlas Animate CC: las animaciones usan el nombre del símbolo/clip tal cual.
				// Dejamos una entrada de ejemplo que el usuario puede editar o borrar.
				newElem.animations = [
					{
						name: 'idle',
						prefix: 'idle',
						framerate: 24,
						looped: true
					}
				];
			if (typeName == 'graphic')
			{
				// Default graphic: white 100×100 solid rect
				newElem.graphicSize  = [100.0, 100.0];
				newElem.graphicColor = '#FFFFFF';
			}
			if (typeName == 'backdrop')
			{
				// Default backdrop settings: tile both axes, no auto-scroll
				newElem.customProperties = {repeatX: true, repeatY: true, velocityX: 0.0, velocityY: 0.0};
			}
			if (typeName == 'character')
			{
				// Character anchors use charSlot to specify which character.
				// The name field doubles as charSlot (bf / gf / dad).
				var slotName = nameInput.text.trim().toLowerCase();
				if (slotName == '' || (slotName != 'bf' && slotName != 'gf' && slotName != 'dad'
					&& slotName != 'girlfriend' && slotName != 'opponent'))
					slotName = 'bf';
				newElem.name = 'char_$slotName';
				newElem.charSlot = slotName;
				newElem.asset = '';
			}
			onConfirm(newElem);
			close();
		});
		confirmBtn.cameras = [_camSub];
		add(confirmBtn);

		var cancelBtn = new CoolButton(panX + W - 102, y, 'Cancel', close);
		cancelBtn.cameras = [_camSub];
		add(cancelBtn);

		var hint = new FlxText(panX + 12, panY + H - 20, W - 24, 'ESC to cancel', 9);
		hint.color = T.textDim;
		hint.scrollFactor.set();
		hint.cameras = [_camSub];
		add(hint);
	}

	/**
	 * Opens a native file browser. The selected PNG/XML/JSON/TXT is copied to
	 * the engine asset folder (mod or base) and the asset path field is filled in.
	 *
	 * ── Companion files ─────────────────────────────────────────────────────────
	 * When a PNG is selected the editor also copies, from the same source folder:
	 *   • <name>.xml          → Sparrow atlas descriptor
	 *   • <name>.txt          → Packer atlas descriptor
	 *
	 * When Animation.json or spritemap1.json is selected the editor treats the
	 * entire parent folder as a Texture Atlas bundle and copies it wholesale:
	 *   <folder>/
	 *     Animation.json  (or spritemap1.json, spritemap2.json …)
	 *     images/
	 *       *.png          ← Animate CC texture sheets
	 *
	 * When an XML/TXT descriptor is selected the matching PNG is also copied.
	 */
	function _browseAsset():Void
	{
		#if sys
		_fileRef = new FileReference();
		_fileRef.addEventListener(Event.SELECT, function(_)
		{
			_fileRef.addEventListener(Event.COMPLETE, function(_)
			{
				var filename:String = _fileRef.name;

				// Determine destination
				var destDir:String = _toMod && ModManager.isActive()
					? '${ModManager.modRoot()}/stages/$_stageName/images'
					: 'assets/stages/$_stageName/images';

				// ── Strip extension to get asset key ────────────────────────────
				var assetKey:String = filename;
				var isAnimateRoot = (filename == 'Animation.json'
					|| filename.startsWith('spritemap') && filename.endsWith('.json'));
				if      (assetKey.endsWith('.png'))  assetKey = assetKey.substr(0, assetKey.length - 4);
				else if (assetKey.endsWith('.jpg'))  assetKey = assetKey.substr(0, assetKey.length - 4);
				else if (assetKey.endsWith('.jpeg')) assetKey = assetKey.substr(0, assetKey.length - 5);
				else if (assetKey.endsWith('.xml'))  assetKey = assetKey.substr(0, assetKey.length - 4);
				else if (assetKey.endsWith('.txt'))  assetKey = assetKey.substr(0, assetKey.length - 4);
				else if (assetKey.endsWith('.json')) assetKey = assetKey.substr(0, assetKey.length - 5);

				try
				{
					if (!FileSystem.exists(destDir))
						FileSystem.createDirectory(destDir);

					// Save the selected file first
					var bytes = _fileRef.data;
					if (bytes != null)
						sys.io.File.saveBytes('$destDir/$filename', bytes);

					// Copy companion files from the same source directory
					_copyCompanionFiles(filename, assetKey, destDir, isAnimateRoot);
				}
				catch (ex:Dynamic)
				{
					trace('[AddElementSubState] Error copying asset: $ex');
				}

				// For Animate atlas the key is the folder name, not Animation/spritemap
				if (isAnimateRoot && _lastAnimateFolderName != '')
					assetKey = _lastAnimateFolderName;

				// ── Auto-seleccionar tipo según el archivo elegido ─────────────
				// Si se importó un atlas (Animation.json / spritemap*.json) cambiar
				// el dropdown a 'atlas' automáticamente para que el elemento quede
				// correctamente configurado sin que el usuario tenga que hacerlo a mano.
				if (isAnimateRoot)
				{
					// Localizar 'atlas' en el array de tipos del dropdown
					var _atlasTypes = ['sprite', 'animated', 'atlas', 'graphic', 'backdrop', 'group', 'custom_class', 'sound', 'character'];
					var _atlasIdx   = _atlasTypes.indexOf('atlas');
					if (_atlasIdx >= 0)
						typeDropdown.selectedId = Std.string(_atlasIdx);
				}

				// Auto-fill name input
				if (nameInput.text == 'new_element' || nameInput.text == '')
					nameInput.text = assetKey;

				assetInput.text = assetKey;
			});
			_fileRef.load();
		});
		_fileRef.addEventListener(Event.CANCEL, function(_) {});
		_fileRef.addEventListener(IOErrorEvent.IO_ERROR, function(_)
		{
			trace('[AddElementSubState] File browse IO error');
		});
		// Accept PNGs, XMLs, TXTs and Animate JSON files
		_fileRef.browse([new openfl.net.FileFilter(
			'Sprite assets (PNG, XML, TXT, Animation.json, spritemap.json)',
			'*.png;*.jpg;*.jpeg;*.xml;*.txt;*.json'
		)]);
		#end
	}

	/** Tracks the sub-folder name created for the last Animate atlas import. */
	var _lastAnimateFolderName:String = '';

	/**
	 * Copies companion files that belong to the same atlas as the selected file.
	 *
	 * Uses @:privateAccess on FileReference to recover the full source path on
	 * desktop cpp targets.  Falls back gracefully on other targets.
	 *
	 * ── Case 1 (PNG / XML / TXT selected) ───────────────────────────────────
	 *   Copies the sibling PNG, XML and TXT from the source directory.
	 *
	 * ── Case 2 (Animation.json / spritemap1.json selected) ──────────────────
	 *   Copies the entire parent folder (including sub-folders like images/)
	 *   into destDir/<folderName>/ so FunkinSprite.loadAnimateAtlas() can
	 *   find it at stages/<stage>/images/<folderName>/Animation.json.
	 */
	function _copyCompanionFiles(filename:String, assetKey:String,
		destDir:String, isAnimateRoot:Bool):Void
	{
		#if sys
		// ── Recover source directory ─────────────────────────────────────────────
		var srcDir:String = '';
		try
		{
			@:privateAccess
			{
				var rawPath:Dynamic = null;
				if (Reflect.hasField(_fileRef, '__path'))
					rawPath = Reflect.field(_fileRef, '__path');
				else if (Reflect.hasField(_fileRef, '_path'))
					rawPath = Reflect.field(_fileRef, '_path');

				if (rawPath != null)
				{
					var fullPath:String = Std.string(rawPath).replace('\\\\', '/');
					var slash = fullPath.lastIndexOf('/');
					if (slash >= 0) srcDir = fullPath.substr(0, slash + 1);
				}
			}
		}
		catch (_:Dynamic) {}

		if (srcDir == '')
		{
			trace('[AddElementSubState] HINT: no se pudo leer el path origen — '
				+ 'copia manual el XML / Animation.json del mismo directorio.');
			return;
		}

		// ── Case 1: PNG / XML / TXT — copy sibling atlas files ───────────────────
		if (!isAnimateRoot)
		{
			var companions = ['$assetKey.png', '$assetKey.xml', '$assetKey.txt'];
			for (comp in companions)
			{
				var src = '$srcDir$comp';
				var dst = '$destDir/$comp';
				if (comp != filename && FileSystem.exists(src) && !FileSystem.exists(dst))
				{
					sys.io.File.copy(src, dst);
					trace('[AddElementSubState] Companion copiado: $comp');
				}
			}
			return;
		}

		// ── Case 2: Animation.json / spritemap — copy entire atlas bundle ─────────
		// Derive the atlas folder name from the source path
		var trimmed = srcDir.endsWith('/') ? srcDir.substr(0, srcDir.length - 1) : srcDir;
		var lastSlash = trimmed.lastIndexOf('/');
		var folderName = lastSlash >= 0 ? trimmed.substr(lastSlash + 1) : assetKey;
		_lastAnimateFolderName = folderName;

		var bundleDest = '$destDir/$folderName';
		if (!FileSystem.exists(bundleDest))
			FileSystem.createDirectory(bundleDest);

		// Copy all files and one level of sub-folders
		for (entry in FileSystem.readDirectory(srcDir))
		{
			var entryPath = '$srcDir$entry';
			if (FileSystem.isDirectory(entryPath))
			{
				var subDest = '$bundleDest/$entry';
				if (!FileSystem.exists(subDest)) FileSystem.createDirectory(subDest);
				for (sub in FileSystem.readDirectory(entryPath))
				{
					var subSrc = '$entryPath/$sub';
					var subDst = '$subDest/$sub';
					if (!FileSystem.isDirectory(subSrc) && !FileSystem.exists(subDst))
						sys.io.File.copy(subSrc, subDst);
				}
			}
			else
			{
				var dst = '$bundleDest/$entry';
				if (!FileSystem.exists(dst))
					sys.io.File.copy(entryPath, dst);
			}
		}
		trace('[AddElementSubState] Texture Atlas bundle copiado: $folderName → $bundleDest');
		#end
	}
	override function close():Void
	{
		if (_camSub != null)
		{
			FlxG.cameras.remove(_camSub, true);
			_camSub = null;
		}
		super.close();
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);
		if (FlxG.keys.justPressed.ESCAPE)
			close();
	}
}
