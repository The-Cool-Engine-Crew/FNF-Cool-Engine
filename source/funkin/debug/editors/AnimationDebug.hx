package funkin.debug.editors;
import coolui.CoolInputText;
import coolui.CoolNumericStepper;
import coolui.CoolCheckBox;
import coolui.CoolDropDown;
import coolui.CoolTabMenu;
import flixel.math.FlxMath;
import funkin.gameplay.objects.character.Character.AnimData;
import funkin.gameplay.objects.character.Character.CharacterData;
import funkin.gameplay.objects.stages.Stage;
import funkin.states.MusicBeatState;
import flixel.FlxG;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.FlxCamera;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.util.FlxTimer;
import flixel.addons.display.FlxGridOverlay;
import flixel.group.FlxGroup.FlxTypedGroup;
import coolui.Cool9Slice;
import openfl.net.FileReference;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import coolui.CoolButton;
import flixel.ui.FlxSpriteButton;
import funkin.gameplay.objects.character.Character;
import funkin.menus.FreeplayState;
import funkin.data.CoolUtil;
import funkin.states.LoadingState;
import haxe.Json;
import funkin.menus.MainMenuState;
import funkin.gameplay.objects.character.HealthIcon;
import funkin.debug.ColorPickerWheel;
#if sys
import sys.FileSystem;
import sys.io.File;
import lime.ui.FileDialog;
#end

using StringTools;

class AnimationDebug extends MusicBeatState
{
	var UI_box:CoolTabMenu;

	var char:Character;
	var textAnim:FlxText;
	var textInfo:FlxText;
	var textControls:FlxText;
	var textHelp:FlxText;
	var dumbTexts:FlxTypedGroup<FlxText>;
	var layeringbullshit:FlxTypedGroup<FlxSprite>;
	var animList:Array<String> = [];
	var curAnim:Int = 0;
	var ghostAnimIdx:Int = 0;
	public var daAnim:String = 'bf';
	var camFollow:FlxObject;
	var camHUD:FlxCamera;
	var camGame:FlxCamera;
	var camUI:FlxCamera; // cámara invisible cameras[0]: da coordenadas estables al mouse (zoom siempre 1)
	var _file:FileReference;
	var ghostChar:Character;

	// UI Elements — Character tab
	var playerCheckbox:CoolCheckBox;
	var charFlipXCheckbox:CoolCheckBox;

	// UI Elements — Properties tab
	var antialiasingCheckbox:CoolCheckBox;
	var scaleStepper:CoolNumericStepper;
	var pathInput:CoolInputText;
	var spritemapNameInput:CoolInputText; // antes: animFileInput
	var isTxtCheckbox:CoolCheckBox;
	var isSpritesheetCheckbox:CoolCheckBox;
	var isFlxAnimateCheckbox:CoolCheckBox; // antes: isAdobeAnimateCheckbox
	var healthIconInput:CoolInputText;
	var healthBarColorInput:CoolInputText;

	// UI Elements — Animation tab
	var animNameInput:CoolInputText;
	var animPrefixInput:CoolInputText;
	var animFramerateStepper:CoolNumericStepper;
	var animLoopedCheckbox:CoolCheckBox;
	var animFlipXCheckbox:CoolCheckBox;
	// Multi-atlas: campos de sub-atlas por animación
	var animAssetPathInput:CoolInputText;
	var animRenderTypeInput:CoolInputText;
	var offsetXStepper:CoolNumericStepper;
	var offsetYStepper:CoolNumericStepper;

	var velocityPlus:Float = 1;
	var gridBG:FlxSprite;
	var showGrid:Bool = true;

	// ── Cache para actualizar labels en-lugar (evita recrear objetos cada frame) ─
	// generateOffsetTexts() los llena; updateOffsetTexts() los reutiliza.
	var _offsetLabels:Array<FlxText>  = [];
	var _ghostBadgeBgs:Array<FlxSprite> = [];
	var _ghostBadgeLabels:Array<FlxText> = [];
	var _rowBgs:Array<FlxSprite> = [];

	// Timer reutilizable para el flash amarillo de textInfo (un solo objeto)
	var _flashTimer:FlxTimer = null;

	// Mouse drag para offsets (click derecho)
	var isDraggingOffset:Bool = false;
	var dragLastX:Float = 0;
	var dragLastY:Float = 0;

	// Nombre original de la animación que se está editando.
	// null = modo "Add" (nueva animación). String = modo "Edit" (modificar existente).
	var editingAnimName:String = null;

	// Botón "Add Animation" — necesitamos referencia para cambiar su label
	var addAnimBtn:CoolButton;

	// Character data para exportar
	var characterData:CharacterData;
	var currentAnimData:Array<AnimData> = [];

	public var currentStage:Stage;

	// Icon preview
	var iconPreview:HealthIcon;
	var iconBG:FlxSprite;

	// Ruta de la carpeta FlxAnimate importada (assets/images/<char>/)
	var flxAnimateFolderPath:String = "";

	// ── Variables visuales ────────────────────────────────────────────────────
	// Panel oscuro detrás de la lista de offsets / controles (lado izquierdo)
	var leftPanel:FlxSprite;
	// Barra de header con nombre del personaje actual
	var charHeaderBg:FlxSprite;
	var charHeaderText:FlxText;
	// Barra de estado inferior (reemplaza textHelp flotante)
	var statusBar:FlxSprite;
	// Borde decorativo del panel UI derecho
	var uiPanelBg:FlxSprite;

	// Posición X de inicio fuera de pantalla para el slide-in del panel
	static inline var PANEL_HIDDEN_X:Float = 1500;

	// Fila de highlight para la animación seleccionada en la lista
	var animRowHighlight:FlxSprite;
	// Acento de color actual del estado (verde=ok, rojo=error, cyan=info)
	var statusAccentBar:FlxSprite;
	// Preview de healthBar en el HUD (esquina inferior, debajo del ícono)
	var hudHealthBar:FlxSprite;
	var hudHealthBarLabel:FlxText;
	var charDeathInput:coolui.CoolInputText;
	// ── Game Over fields ──────────────────────────────────────────────────────
	var gameOverSoundInput:CoolInputText;
	var gameOverMusicInput:CoolInputText;
	var gameOverEndInput:CoolInputText;
	var gameOverBpmStepper:CoolNumericStepper;
	var gameOverCamFrameStepper:CoolNumericStepper;
	// Position offset steppers (campo "positionOffset" del CharacterData)
	var posOffsetXStepper:CoolNumericStepper;
	var posOffsetYStepper:CoolNumericStepper;
	// Camera offset steppers (campo "cameraOffset" del CharacterData)
	var camOffsetXStepper:CoolNumericStepper;
	var camOffsetYStepper:CoolNumericStepper;
	// Color actual seleccionado para la healthBar
	var currentHealthBarColor:FlxColor = FlxColor.fromString("#31B0D1");

	// ── Unsaved-changes tracking ──────────────────────────────────────────────
	var _hasUnsaved:Bool = false;
	var _unsavedDlg:funkin.debug.EditorDialogs.UnsavedChangesDialog = null;
	var _windowCloseFn:Void->Void = null;

	// ── Undo stack ────────────────────────────────────────────────────────────
	// Cada entrada es un JSON snapshot de currentAnimData en ese momento.
	// _pushUndo() se llama ANTES de cualquier operación destructiva.
	// _doUndo() restaura el último snapshot y recarga el personaje.
	var _undoStack:Array<String> = [];
	static inline var MAX_UNDO:Int = 30;
	// Evita empujar un snapshot idéntico al que ya está en el tope de la pila
	// (p.ej. al mantener pulsada una flecha varias veces seguidas y luego hacer
	// Ctrl+Z: cada pulsación ya era distinta, pero si por algún bug se llama dos
	// veces sin cambio intermedio, no duplicamos entradas inútiles).
	var _lastUndoJson:String = "";

	public function new(daAnim:String = 'bf')
	{
		super();
		this.daAnim = daAnim;
	}

	// ── create ───────────────────────────────────────────────────────────────

	override function create()
	{
		funkin.debug.themes.EditorTheme.load();
		funkin.system.CursorManager.show();
		funkin.audio.MusicManager.play('configurator', 0.7);

		camGame = new FlxCamera();
		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;

		// camUI es una cámara completamente transparente y vacía que se pone
		// en cameras[0] para que FlxG.mouse.x/y use siempre zoom=1.
		// Sin esto, cuando camGame tiene zoom != 1, flixel-ui calcula mal
		// las posiciones de click en CoolInputText y el HUD deja de responder.
		camUI = new FlxCamera();
		camUI.bgColor.alpha = 0;

		FlxG.cameras.reset(camUI); // cameras[0] → FlxG.camera = camUI (zoom 1 fijo)
		FlxG.cameras.add(camGame, false); // renders encima de camUI
		FlxG.cameras.add(camHUD, false); // renders encima de todo

		currentStage = new Stage('stage_week1');
		currentStage.cameras = [camGame];
		add(currentStage);

		layeringbullshit = new FlxTypedGroup<FlxSprite>();
		layeringbullshit.cameras = [camGame];
		add(layeringbullshit);

		setupUI();

		dumbTexts = new FlxTypedGroup<FlxText>();
		dumbTexts.cameras = [camHUD];

		// ── Panel oscuro izquierdo ────────────────────────────────────────────
		// Cubre el área de controles + lista de offsets
		leftPanel = new FlxSprite(0, 0);
		leftPanel.makeGraphic(340, FlxG.height, (funkin.debug.themes.EditorTheme.current.bgPanel & 0x00FFFFFF) | 0xCC000000);
		leftPanel.cameras = [camHUD];
		leftPanel.scrollFactor.set();
		add(leftPanel);

		// Borde derecho del panel izquierdo (línea accent cyan)
		var leftPanelBorder = new FlxSprite(340, 0);
		leftPanelBorder.makeGraphic(2, FlxG.height, funkin.debug.themes.EditorTheme.current.accent);
		leftPanelBorder.cameras = [camHUD];
		leftPanelBorder.scrollFactor.set();
		add(leftPanelBorder);

		// ── Header del personaje (arriba del panel izquierdo) ─────────────────
		charHeaderBg = new FlxSprite(0, 0);
		charHeaderBg.makeGraphic(340, 36, funkin.debug.themes.EditorTheme.current.accent);
		charHeaderBg.cameras = [camHUD];
		charHeaderBg.scrollFactor.set();
		add(charHeaderBg);

		charHeaderText = new FlxText(8, 6, 330, '', 16);
		charHeaderText.color = funkin.debug.themes.EditorTheme.current.bgDark;
		charHeaderText.cameras = [camHUD];
		charHeaderText.scrollFactor.set();
		charHeaderText.font = "VCR OSD Mono";
		add(charHeaderText);

		// ── Fila de highlight de la animación seleccionada ────────────────────
		animRowHighlight = new FlxSprite(4, 0);
		animRowHighlight.makeGraphic(332, 20, (funkin.debug.themes.EditorTheme.current.accent & 0x00FFFFFF) | 0x44000000);
		animRowHighlight.cameras = [camHUD];
		animRowHighlight.scrollFactor.set();
		animRowHighlight.visible = false;
		add(animRowHighlight);

		add(dumbTexts);

		// ── Textos de controles ───────────────────────────────────────────────
		var controlsBg = new FlxSprite(4, 40);
		controlsBg.makeGraphic(332, 85, 0x22FFFFFF);
		controlsBg.cameras = [camHUD];
		controlsBg.scrollFactor.set();
		add(controlsBg);

		textControls = new FlxText(8, 42, 328, '', 10);
		textControls.text = "W/S · Switch Anim   ARROWS · Offset (SHIFT=x10)\n" + "I/K · Cam Up/Down   J/L · Cam Left/Right\n"
			+ "SCROLL · Zoom   SPACE · Play   R · Reset   T · Ghost\n" + "RIGHT DRAG · Move Offset (SHIFT=x3)   Ctrl+Z · Undo   ESC · Exit";
		textControls.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		textControls.color = funkin.debug.themes.EditorTheme.current.textSecondary;
		textControls.cameras = [camHUD];
		textControls.scrollFactor.set();
		add(textControls);

		// ── Texto de animación actual ─────────────────────────────────────────
		textAnim = new FlxText(8, 132, 330, '', 18);
		textAnim.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 2);
		textAnim.color = funkin.debug.themes.EditorTheme.current.accent;
		textAnim.cameras = [camHUD];
		textAnim.scrollFactor.set();
		add(textAnim);

		// ── Texto de offset / zoom ────────────────────────────────────────────
		textInfo = new FlxText(8, 154, 330, '', 12);
		textInfo.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		textInfo.color = funkin.debug.themes.EditorTheme.current.warning;
		textInfo.cameras = [camHUD];
		textInfo.scrollFactor.set();
		add(textInfo);

		// ── Barra de estado inferior ──────────────────────────────────────────
		statusBar = new FlxSprite(0, FlxG.height - 30);
		statusBar.makeGraphic(FlxG.width, 30, (funkin.debug.themes.EditorTheme.current.bgDark & 0x00FFFFFF) | 0xDD000000);
		statusBar.cameras = [camHUD];
		statusBar.scrollFactor.set();
		add(statusBar);

		// Acento de color en la barra de estado (izquierda, 4px)
		statusAccentBar = new FlxSprite(0, FlxG.height - 30);
		statusAccentBar.makeGraphic(4, 30, funkin.debug.themes.EditorTheme.current.accent);
		statusAccentBar.cameras = [camHUD];
		statusAccentBar.scrollFactor.set();
		add(statusAccentBar);

		textHelp = new FlxText(12, FlxG.height - 24, FlxG.width - 200, '', 12);
		textHelp.text = "TIP · Use the UI tabs to edit properties and animations";
		textHelp.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		textHelp.color = funkin.debug.themes.EditorTheme.current.accent;
		textHelp.cameras = [camHUD];
		textHelp.scrollFactor.set();
		add(textHelp);

		// ✨ Botón de tema en barra de estado (esquina inferior derecha)
		var _themeBtn = new coolui.CoolButton(FlxG.width - 75, FlxG.height - 28, "\u2728 Theme", function()
		{
			openSubState(new funkin.debug.themes.ThemePickerSubState());
		});
		_themeBtn.cameras = [camHUD];
		_themeBtn.scrollFactor.set();
		add(_themeBtn);

		// ── Icon preview ──────────────────────────────────────────────────────
		var iconAreaX = FlxG.width - 340 + 5; // dentro del panel derecho no existe aún, lo ponemos en la barra inferior
		// Lo dejamos en la esquina inferior izquierda del status bar a la derecha
		var iconX = FlxG.width - 185;
		var iconY = FlxG.height - 185;

		iconBG = new FlxSprite(iconX - 10, iconY - 28);
		iconBG.makeGraphic(170, 162, (funkin.debug.themes.EditorTheme.current.bgDark & 0x00FFFFFF) | 0xEE000000);
		iconBG.cameras = [camHUD];
		add(iconBG);

		// Borde superior del recuadro del ícono (línea cyan)
		var iconTopBorder = new FlxSprite(iconX - 10, iconY - 28);
		iconTopBorder.makeGraphic(170, 2, funkin.debug.themes.EditorTheme.current.accent);
		iconTopBorder.cameras = [camHUD];
		add(iconTopBorder);

		var iconLabel = new FlxText(iconX - 10, iconY - 22, 170, "ICON PREVIEW", 10);
		iconLabel.alignment = CENTER;
		iconLabel.color = funkin.debug.themes.EditorTheme.current.accent;
		iconLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		iconLabel.cameras = [camHUD];
		add(iconLabel);

		iconPreview = new HealthIcon('bf', false);
		iconPreview.setPosition(iconX, iconY - 8);
		iconPreview.cameras = [camHUD];
		iconPreview.scale.set(0.8, 0.8);
		add(iconPreview);

		// ── Preview de la healthBar en el HUD ─────────────────────────────────
		// Se muestra debajo del ícono, siempre visible con el color del personaje
		hudHealthBarLabel = new FlxText(iconX - 10, iconY + 150, 170, "HEALTH BAR", 10);
		hudHealthBarLabel.alignment = CENTER;
		hudHealthBarLabel.color = funkin.debug.themes.EditorTheme.current.accent;
		hudHealthBarLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		hudHealthBarLabel.cameras = [camHUD];
		add(hudHealthBarLabel);

		hudHealthBar = new FlxSprite(iconX - 10, iconY + 164);
		hudHealthBar.loadGraphic(Paths.image("UI/healthBar"));
		hudHealthBar.setGraphicSize(168, 20);
		hudHealthBar.updateHitbox();
		hudHealthBar.cameras = [camHUD];
		hudHealthBar.color = currentHealthBarColor;
		add(hudHealthBar);

		// ── Slide-in del panel derecho al abrir ───────────────────────────────
		UI_box.x = PANEL_HIDDEN_X + 30;
		uiPanelBg.x = PANEL_HIDDEN_X - 4 + 30;
		FlxTween.tween(UI_box, {x: FlxG.width - UI_box.width - 2}, 0.45, {ease: FlxEase.quartOut});
		FlxTween.tween(uiPanelBg, {x: FlxG.width - UI_box.width - 6}, 0.45, {ease: FlxEase.quartOut});

		// Fade-in del panel izquierdo
		leftPanel.alpha = 0;
		leftPanelBorder.alpha = 0;
		charHeaderBg.alpha = 0;
		charHeaderText.alpha = 0;
		FlxTween.tween(leftPanel, {alpha: 1}, 0.5, {ease: FlxEase.quartOut, startDelay: 0.1});
		FlxTween.tween(leftPanelBorder, {alpha: 1}, 0.5, {ease: FlxEase.quartOut, startDelay: 0.15});
		FlxTween.tween(charHeaderBg, {alpha: 1}, 0.4, {ease: FlxEase.quartOut, startDelay: 0.2});
		FlxTween.tween(charHeaderText, {alpha: 1}, 0.4, {ease: FlxEase.quartOut, startDelay: 0.25});

		camFollow = new FlxObject(0, 0, 2, 2);
		camFollow.screenCenter();
		add(camFollow);
		camGame.follow(camFollow);

		displayCharacter(daAnim);
		loadCharacterData();

		// ── Window-close guard ────────────────────────────────────────────
		#if sys
		_windowCloseFn = function()
		{
			if (_hasUnsaved)
			{
				// Auto-guardar al cerrar para no perder trabajo
				try { reloadCharacterWithNewAnims(); } catch (_) {}
			}
		};
		lime.app.Application.current.window.onClose.add(_windowCloseFn);
		#end

		funkin.transitions.StateTransition.onStateCreated();

		super.create();
	}

	// ── UI Setup ──────────────────────────────────────────────────────────────

	function setupUI():Void
	{
		var tabs = [
			{name: "Character", label: "Character"},
			{name: "Animation", label: "Animation"},
			{name: "Properties", label: "Properties"},
			{name: "Import", label: "Import Assets"},
			{name: "Export", label: "Export"}
		];

		UI_box = new CoolTabMenu(null, tabs, true);
		UI_box.cameras = [camHUD];
		UI_box.resize(320, 450);
		UI_box.x = FlxG.width - UI_box.width - 2;
		UI_box.y = 10;

		// Panel oscuro detrás del tab menu (se crea aquí para poder referenciar el tamaño)
		uiPanelBg = new FlxSprite(UI_box.x - 4, UI_box.y - 4);
		uiPanelBg.makeGraphic(Std.int(UI_box.width) + 8, Std.int(UI_box.height) + 8, (funkin.debug.themes.EditorTheme.current.bgDark & 0x00FFFFFF) | 0xDD000000);
		uiPanelBg.cameras = [camHUD];
		add(uiPanelBg);

		add(UI_box);

		addCharacterTab();
		addAnimationTab();
		addPropertiesTab();
		addImportTab();
		addExportTab();
	}

	// ── Tab: Character ────────────────────────────────────────────────────────

	function addCharacterTab():Void
	{
		var tab = new coolui.CoolUIGroup();
		tab.name = "Character";

		playerCheckbox = new CoolCheckBox(10, 10, null, null, "Player Character", 150);
		playerCheckbox.checked = false;
		tab.add(playerCheckbox);

		charFlipXCheckbox = new CoolCheckBox(165, 10, null, null, "FlipX", 80);
		charFlipXCheckbox.checked = false;
		charFlipXCheckbox.callback = function(_:Bool)
		{
			if (char != null)      char.flipX      = charFlipXCheckbox.checked;
			if (ghostChar != null) ghostChar.flipX = charFlipXCheckbox.checked;
		};
		tab.add(charFlipXCheckbox);

		tab.add(new FlxText(10, 47, 0, "Death Character:", 10));
		charDeathInput = new CoolInputText(10, 58, 200, '', 8);
		tab.add(charDeathInput);
		var charDeathHint = new FlxText(10, 72, 280, "Ej: bf-dead  (empty = default)", 8);
		charDeathHint.color = FlxColor.WHITE;
		tab.add(charDeathHint);

		// ── Game Over ──────────────────────────────────────────────────────────
		var goLabel = new FlxText(10, 90, 0, "── Game Over ──", 10);
		goLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		tab.add(goLabel);

		var yGO = 107;

		tab.add(new FlxText(10, yGO, 0, "Death SFX  (Paths.sound):", 8));
		gameOverSoundInput = new CoolInputText(10, yGO + 12, 200, '', 8);
		var goSndHint = new FlxText(10, yGO + 26, 280, "Default: fnf_loss_sfx", 7);
		goSndHint.color = FlxColor.WHITE;
		tab.add(gameOverSoundInput);
		tab.add(goSndHint);
		yGO += 42;

		tab.add(new FlxText(10, yGO, 0, "Loop Music  (Paths.music):", 8));
		gameOverMusicInput = new CoolInputText(10, yGO + 12, 200, '', 8);
		var goMusHint = new FlxText(10, yGO + 36, 280, "Default: gameplay/gameOver", 7);
		goMusHint.color = FlxColor.WHITE;
		tab.add(gameOverMusicInput);
		tab.add(goMusHint);
		yGO += 42;

		tab.add(new FlxText(10, yGO + 10, 0, "End/Retry SFX  (Paths.music):", 8));
		gameOverEndInput = new CoolInputText(10, yGO + 22, 200, '', 8);
		var goEndHint = new FlxText(10, yGO + 36, 280, "Default: gameplay/gameOverEnd", 7);
		goEndHint.color = FlxColor.WHITE;
		tab.add(gameOverEndInput);
		tab.add(goEndHint);
		yGO += 42;

		tab.add(new FlxText(10, yGO + 12, 0, "BPM:", 8));
		gameOverBpmStepper = new CoolNumericStepper(60, yGO + 11, 1, 100, 1, 999, 1);
		tab.add(gameOverBpmStepper);

		tab.add(new FlxText(150, yGO + 12, 0, "Cam Frame:", 8));
		gameOverCamFrameStepper = new CoolNumericStepper(200, yGO + 31, 1, 12, 0, 60, 0);
		tab.add(gameOverCamFrameStepper);

		yGO += 24;

		var refreshBtn = new CoolButton(10, yGO, "Refresh Character", function()
		{
			displayCharacter(daAnim);
			loadCharacterData();
		});
		tab.add(refreshBtn);

		tab.add(new CoolButton(170, yGO, "Reset Camera", function()
		{
			camFollow.setPosition(FlxG.width / 2, FlxG.height / 2);
			camGame.zoom = 1;
		}));
		UI_box.addGroup(tab);
	}

	// ── Tab: Animation ────────────────────────────────────────────────────────

	function addAnimationTab():Void
	{
		var tab = new coolui.CoolUIGroup();
		tab.name = "Animation";

		var yPos = 10;

		var titleLabel = new FlxText(10, yPos, 0, "Add/Edit Animation", 14);
		titleLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		tab.add(titleLabel);
		yPos += 25;

		tab.add(new FlxText(10, yPos, 0, "Name:", 10));
		yPos += 15;
		animNameInput = new CoolInputText(10, yPos, 200, '', 8);
		tab.add(animNameInput);
		yPos += 25;

		// Para FlxAnimate: este campo es el SN del símbolo
		// Para sprites normales: es el prefix del atlas XML
		tab.add(new FlxText(10, yPos, 0, "Prefix / Symbol SN:", 10));
		yPos += 15;
		animPrefixInput = new CoolInputText(10, yPos, 200, '', 8);
		tab.add(animPrefixInput);

		var prefixHint = new FlxText(10, yPos + 14, 280, "FlxAnimate: name exact of símbol (SN)", 8);
		prefixHint.color = FlxColor.WHITE;
		tab.add(prefixHint);
		yPos += 35;

		// Separador visual para la sección multi-atlas
		var atlasSection = new FlxSprite(10, yPos);
		atlasSection.makeGraphic(290, 1, 0x55FF90D0);
		tab.add(atlasSection);
		var atlasSectionLabel = new FlxText(14, yPos - 1, 0, "─ Multi-Atlas", 8);
		atlasSectionLabel.color = 0xFFFF90D0;
		atlasSectionLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		tab.add(atlasSectionLabel);
		yPos += 12;

		tab.add(new FlxText(10, yPos, 0, "Framerate:", 10));
		yPos += 15;
		animFramerateStepper = new CoolNumericStepper(10, yPos, 1, 24, 1, 60, 0);
		tab.add(animFramerateStepper);
		yPos += 25;

		animLoopedCheckbox = new CoolCheckBox(10, yPos, null, null, "Looped", 100);
		animLoopedCheckbox.checked = false;
		tab.add(animLoopedCheckbox);

		animFlipXCheckbox = new CoolCheckBox(160, yPos, null, null, "FlipX (anim)", 120);
		animFlipXCheckbox.checked = false;
		tab.add(animFlipXCheckbox);
		yPos += 24;

		// ── Multi-Atlas: Asset Path (opcional) ───────────────────────────────
		// Si se deja vacío, la animación pertenece al atlas principal del personaje.
		// Si se rellena, esta animación se cargará del sub-atlas indicado.
		// Ejemplo: "tankman/bloody" → assets/characters/images/tankman/bloody/
		var atlasLabel = new FlxText(10, yPos, 0, "Sub-Atlas Path:", 10);
		atlasLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		tab.add(atlasLabel);
		yPos += 14;
		animAssetPathInput = new CoolInputText(10, yPos, 290, '', 8);
		tab.add(animAssetPathInput);
		yPos += 14;
		var atlasHint = new FlxText(10, yPos, 290, "empty = main atlas  |  e.g: tankman/bloody", 8);
		atlasHint.color = FlxColor.fromRGB(100, 180, 255);
		tab.add(atlasHint);
		yPos += 20;

		// ── Render Type (opcional) ────────────────────────────────────────────
		// "animateatlas" para Adobe Animate, "sparrow" para XML atlas.
		// Dejar vacío para que el engine lo detecte automáticamente.
		var rtLabel = new FlxText(10, yPos, 0, "Render Type:", 10);
		rtLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		tab.add(rtLabel);
		yPos += 14;
		animRenderTypeInput = new CoolInputText(10, yPos, 200, '', 8);
		tab.add(animRenderTypeInput);
		yPos += 14;
		var rtHint = new FlxText(10, yPos, 290, "animateatlas | sparrow | empty=auto", 8);
		rtHint.color = FlxColor.fromRGB(200, 200, 100);
		tab.add(rtHint);
		yPos += 20;

		tab.add(new FlxText(10, yPos, 0, "Offset X:", 10));
		yPos += 15;
		offsetXStepper = new CoolNumericStepper(10, yPos, 1, 0, -500, 500, 0);
		tab.add(offsetXStepper);
		yPos += 25;

		tab.add(new FlxText(10, yPos, 0, "Offset Y:", 10));
		yPos += 15;
		offsetYStepper = new CoolNumericStepper(10, yPos, 1, 0, -500, 500, 0);
		tab.add(offsetYStepper);
		yPos += 30;

		// Botón Add/Update — su label cambia según si estás editando o agregando
		addAnimBtn = new CoolButton(10, yPos, "Add Animation", function()
		{
			addNewAnimation();
		});
		tab.add(addAnimBtn);

		// Botón "New" — limpia los campos y vuelve a modo Add
		tab.add(new CoolButton(130, yPos, "New / Clear", function()
		{
			editingAnimName = null;
			animNameInput.text = "";
			animPrefixInput.text = "";
			animFramerateStepper.value = 24;
			animLoopedCheckbox.checked = false;
			offsetXStepper.value = 0;
			offsetYStepper.value = 0;
			if (animAssetPathInput != null) animAssetPathInput.text = "";
			if (animRenderTypeInput != null) animRenderTypeInput.text = "";
			if (animFlipXCheckbox != null) animFlipXCheckbox.checked = false;
			if (addAnimBtn != null)
				addAnimBtn.label = "Add Animation";
			setHelp("Cleared fields — Add mode", FlxColor.CYAN);
		}));
		yPos += 30;

		tab.add(new CoolButton(10, yPos, "Delete Current", function()
		{
			deleteCurrentAnimation();
		}));
		yPos += 30;

		tab.add(new CoolButton(10, yPos, "← Load Selected", function()
		{
			loadAnimIntoUI();
		}));

		var loadHint = new FlxText(10, yPos + 22, 280, "Load the selected animation (W/S) for editing", 8);
		loadHint.color = FlxColor.WHITE;
		tab.add(loadHint);

		UI_box.addGroup(tab);
	}

	// ── Tab: Properties ───────────────────────────────────────────────────────

	function addPropertiesTab():Void
	{
		var tab = new coolui.CoolUIGroup();
		tab.name = "Properties";

		var yPos = 10;

		var titleLabel = new FlxText(10, yPos, 0, "Character Properties", 14);
		titleLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		tab.add(titleLabel);
		yPos += 25;

		// Path — para FlxAnimate es la carpeta completa, para sprites el nombre del atlas
		tab.add(new FlxText(10, yPos, 0, "Sprite Path / Folder:", 10));
		yPos += 15;
		pathInput = new CoolInputText(10, yPos, 200, 'BOYFRIEND', 8);
		tab.add(pathInput);

		var pathHint = new FlxText(10, yPos + 14, 280, "FlxAnimate: path to the character's folder", 8);
		pathHint.color = FlxColor.WHITE;
		tab.add(pathHint);
		yPos += 35;

		// Spritemap Name — solo relevante para FlxAnimate (por defecto "spritemap1")
		tab.add(new FlxText(10, yPos, 0, "Spritemap Name:", 10));
		yPos += 15;
		spritemapNameInput = new CoolInputText(10, yPos, 200, 'spritemap1', 8);
		tab.add(spritemapNameInput);

		var smHint = new FlxText(10, yPos + 14, 280, "FlxAnimate only · Default: spritemap1", 8);
		smHint.color = FlxColor.WHITE;
		tab.add(smHint);
		yPos += 35;

		// Health Icon
		tab.add(new FlxText(10, yPos, 0, "Health Icon:", 10));
		yPos += 15;
		healthIconInput = new CoolInputText(10, yPos, 200, 'bf', 8);
		healthIconInput.callback = function(text:String, action:String)
		{
			updateIconPreview(text);
		};
		tab.add(healthIconInput);
		yPos += 25;

		// Health Bar Color — campo de texto + swatch clickeable que abre el picker
		tab.add(new FlxText(10, yPos, 0, "Health Bar Color:", 10));
		yPos += 15;
		healthBarColorInput = new CoolInputText(10, yPos, 155, '#31B0D1', 8);
		healthBarColorInput.callback = function(text:String, action:String)
		{
			try
			{
				var parsed = FlxColor.fromString(text);
				currentHealthBarColor = parsed;
				if (hudHealthBar != null)
					hudHealthBar.color = parsed;
			}
			catch (_)
			{
			}
		};
		tab.add(healthBarColorInput);

		// Swatch de color (cuadrado que muestra el color actual)
		// Es un CoolButton sin texto que abre el ColorPickerWheel
		var colorSwatchBtn = new CoolButton(170, yPos - 1, "", function()
		{
			// Parsear el color actual del input para pasárselo al picker
			var startColor = currentHealthBarColor;
			try
			{
				startColor = FlxColor.fromString(healthBarColorInput.text);
			}
			catch (_)
			{
			}

			var picker = new ColorPickerWheel(startColor);
			picker.onColorSelected = function(selectedColor:FlxColor)
			{
				currentHealthBarColor = selectedColor;
				var hex = "#" + selectedColor.toHexString(false, false).toUpperCase();
				healthBarColorInput.text = hex;
				if (hudHealthBar != null)
				{
					hudHealthBar.color = selectedColor;
					// Pequeño bounce en la healthBar del HUD como feedback
					FlxTween.cancelTweensOf(hudHealthBar.scale);
					hudHealthBar.scale.set(1, 1.3);
					FlxTween.tween(hudHealthBar.scale, {x: 1, y: 1}, 0.25, {ease: FlxEase.backOut});
				}
			};
			picker.cameras = [camHUD];
			openSubState(picker);
		});

		// Pintar el botón con el color actual y darle tamaño de swatch
		colorSwatchBtn.resize(28, 20);
		tab.add(colorSwatchBtn);

		var pickBtn = new CoolButton(202, yPos - 1, "Pick", function()
		{
			var startColor = currentHealthBarColor;
			try
			{
				startColor = FlxColor.fromString(healthBarColorInput.text);
			}
			catch (_)
			{
			}

			var picker = new ColorPickerWheel(startColor);
			picker.onColorSelected = function(selectedColor:FlxColor)
			{
				currentHealthBarColor = selectedColor;
				var hex = "#" + selectedColor.toHexString(false, false).toUpperCase();
				healthBarColorInput.text = hex;
				if (hudHealthBar != null)
				{
					hudHealthBar.color = selectedColor;
					FlxTween.cancelTweensOf(hudHealthBar.scale);
					hudHealthBar.scale.set(1, 1.3);
					FlxTween.tween(hudHealthBar.scale, {x: 1, y: 1}, 0.25, {ease: FlxEase.backOut});
				}
				// Actualizar el swatch del botón
				colorSwatchBtn.resize(28, 20);
			};
			picker.cameras = [camHUD];
			openSubState(picker);
		});
		tab.add(pickBtn);
		yPos += 30;

		// Scale
		tab.add(new FlxText(10, yPos, 0, "Scale:", 10));
		yPos += 15;
		scaleStepper = new CoolNumericStepper(10, yPos, 0.1, 1.0, 0.1, 10.0, 1);
		scaleStepper.value = 1.0;
		tab.add(scaleStepper);
		yPos += 30;

		antialiasingCheckbox = new CoolCheckBox(10, yPos, null, null, "Antialiasing", 100);
		antialiasingCheckbox.checked = true;
		tab.add(antialiasingCheckbox);
		yPos += 25;

		// Formato — los tres son mutuamente exclusivos
		isTxtCheckbox = new CoolCheckBox(10, yPos, null, null, "TXT Spritesheet", 150);
		isTxtCheckbox.checked = false;
		isTxtCheckbox.callback = function(_:Bool)
		{
			if (isTxtCheckbox.checked)
			{
				isSpritesheetCheckbox.checked = false;
				isFlxAnimateCheckbox.checked = false;
			}
		};
		tab.add(isTxtCheckbox);
		yPos += 20;

		isSpritesheetCheckbox = new CoolCheckBox(10, yPos, null, null, "Spritesheet JSON", 150);
		isSpritesheetCheckbox.checked = false;
		isSpritesheetCheckbox.callback = function(_:Bool)
		{
			if (isSpritesheetCheckbox.checked)
			{
				isTxtCheckbox.checked = false;
				isFlxAnimateCheckbox.checked = false;
			}
		};
		tab.add(isSpritesheetCheckbox);
		yPos += 20;

		isFlxAnimateCheckbox = new CoolCheckBox(10, yPos, null, null, "FlxAnimate (Adobe Animate)", 200);
		isFlxAnimateCheckbox.checked = false;
		isFlxAnimateCheckbox.callback = function(_:Bool)
		{
			if (isFlxAnimateCheckbox.checked)
			{
				isTxtCheckbox.checked = false;
				isSpritesheetCheckbox.checked = false;
			}
			// Recordatorio visual
			spritemapNameInput.color = isFlxAnimateCheckbox.checked ? FlxColor.ORANGE : FlxColor.WHITE;
		};
		tab.add(isFlxAnimateCheckbox);
		yPos += 30;

		// ── Position Offset ───────────────────────────────────────────────────
		// El offset global del sprite que se SUMA a la posición del stage.
		// Equivalente al campo "position" de Psych Engine y al field nativo de Cool.
		var posOffsetTitle = new FlxText(10, yPos, 0, "Position Offset:", 10);
		tab.add(posOffsetTitle);
		yPos += 15;
		tab.add(new FlxText(10, yPos + 4, 0, "X:", 9));
		posOffsetXStepper = new CoolNumericStepper(22, yPos, 1, 0, -2000, 2000, 0);
		tab.add(posOffsetXStepper);
		tab.add(new FlxText(130, yPos + 4, 0, "Y:", 9));
		posOffsetYStepper = new CoolNumericStepper(142, yPos, 1, 0, -2000, 2000, 0);
		tab.add(posOffsetYStepper);
		yPos += 28;

		// ── Camera Offset ─────────────────────────────────────────────────────
		// Offset de la cámara relativo al personaje (cameraOffset en CharacterData).
		var camOffsetTitle = new FlxText(10, yPos, 0, "Camera Offset:", 10);
		tab.add(camOffsetTitle);
		yPos += 15;
		tab.add(new FlxText(10, yPos + 4, 0, "X:", 9));
		camOffsetXStepper = new CoolNumericStepper(22, yPos, 1, 0, -2000, 2000, 0);
		tab.add(camOffsetXStepper);
		tab.add(new FlxText(130, yPos + 4, 0, "Y:", 9));
		camOffsetYStepper = new CoolNumericStepper(142, yPos, 1, 0, -2000, 2000, 0);
		tab.add(camOffsetYStepper);
		yPos += 28;

		tab.add(new CoolButton(10, yPos, "Apply Properties", function()
		{
			if (char != null)
			{
				char.antialiasing = antialiasingCheckbox.checked;
				char.scale.set(scaleStepper.value, scaleStepper.value);
				char.updateHitbox();
				updateIconPreview(healthIconInput.text);

				// Aplicar positionOffset en vivo: recentrar y sumar el offset
				char.screenCenter();
				if (ghostChar != null) ghostChar.screenCenter();
				if (posOffsetXStepper != null && posOffsetYStepper != null)
				{
					char.x += posOffsetXStepper.value;
					char.y += posOffsetYStepper.value;
					if (ghostChar != null)
					{
						ghostChar.x += posOffsetXStepper.value;
						ghostChar.y += posOffsetYStepper.value;
					}
				}
				// Actualizar cameraOffset en el characterData en memoria
				if (char.characterData != null)
				{
					if (posOffsetXStepper != null && posOffsetYStepper != null)
						char.characterData.positionOffset = [posOffsetXStepper.value, posOffsetYStepper.value];
					if (camOffsetXStepper != null && camOffsetYStepper != null)
						char.characterData.cameraOffset = [camOffsetXStepper.value, camOffsetYStepper.value];
				}
			}
		}));

		UI_box.addGroup(tab);
	}

	// ── Tab: Import ───────────────────────────────────────────────────────────

	function addImportTab():Void
	{
		var tab = new coolui.CoolUIGroup();
		tab.name = "Import";

		var yPos = 10;

		var titleLabel = new FlxText(10, yPos, 0, "Import Assets", 14);
		titleLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		tab.add(titleLabel);
		yPos += 25;

		// ── Standard sprite ──
		var stdLabel = new FlxText(10, yPos, 0, "Standard Sprite:", 12);
		stdLabel.color = FlxColor.CYAN;
		stdLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		tab.add(stdLabel);
		yPos += 20;

		tab.add(new CoolButton(10, yPos, "Import Sprite PNG", function()
		{
			browseForFile("sprite");
		}));

		tab.add(new FlxText(10, yPos + 22, 280, "Automatically detects XML/TXT", 8));
		yPos += 50;

		// ── FlxAnimate ──
		var flxLabel = new FlxText(10, yPos, 0, "FlxAnimate (Adobe Animate):", 12);
		flxLabel.color = FlxColor.ORANGE;
		flxLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		tab.add(flxLabel);
		yPos += 20;

		tab.add(new FlxText(10, yPos, 0, "Select the PNG spritemap.\nAutomatically detects spritemap.json and Animation.json\nfrom the same folder.", 9));
		yPos += 40;

		tab.add(new CoolButton(10, yPos, "Import FlxAnimate", function()
		{
			browseForFlxAnimate();
		}));
		yPos += 30;

		// Listar símbolos disponibles en Animation.json
		tab.add(new CoolButton(10, yPos, "List Symbols (Console)", function()
		{
			listAvailableSymbols();
		}));

		var symHint = new FlxText(10, yPos + 22, 280, "Shows the available SNs to use as a 'prefix''", 8);
		symHint.color = FlxColor.WHITE;
		tab.add(symHint);
		yPos += 50;

		// ── Health Icon ──
		var iconTitle = new FlxText(10, yPos, 0, "Health Icon:", 12);
		iconTitle.color = FlxColor.LIME;
		iconTitle.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		tab.add(iconTitle);
		yPos += 20;

		tab.add(new CoolButton(10, yPos, "Import Icon PNG", function()
		{
			browseForFile("icon");
		}));
		tab.add(new FlxText(10, yPos + 22, 280, "300x150px (2 frames de 150x150)", 9));

		UI_box.addGroup(tab);
	}

	// ── Tab: Export ───────────────────────────────────────────────────────────

	function addExportTab():Void
	{
		var tab = new coolui.CoolUIGroup();
		tab.name = "Export";

		var yPos = 10;

		var titleLabel = new FlxText(10, yPos, 0, "Export Character", 14);
		titleLabel.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
		tab.add(titleLabel);
		yPos += 30;

		tab.add(new CoolButton(10, yPos, "Export JSON", function()
		{
			exportCharacterJSON();
		}));
		yPos += 35;
		tab.add(new CoolButton(10, yPos, "Export Offsets TXT", function()
		{
			exportOffsetsTXT();
		}));
		yPos += 35;
		tab.add(new CoolButton(10, yPos, "Copy JSON", function()
		{
			copyJSONToClipboard();
		}));
		yPos += 40;

		tab.add(new FlxText(10, yPos, 280,
			"Export JSON: Saves all character data\n" + "Offsets TXT: Only animation offsets\n" + "Copy JSON: Copies to clipboard", 10));

		UI_box.addGroup(tab);
	}

	// ── Lógica de animaciones ─────────────────────────────────────────────────

	function addNewAnimation():Void
	{
		var newName = animNameInput.text.trim();
		var newPrefix = animPrefixInput.text.trim();

		if (newName == "" || newPrefix == "")
		{
			setHelp("✗ Name and prefix are required!", FlxColor.RED);
			return;
		}

		// Guardar estado anterior antes de modificar
		_pushUndo();

		var newAnim:AnimData = {
			name: newName,
			prefix: newPrefix,
			framerate: animFramerateStepper.value,
			looped: animLoopedCheckbox.checked,
			offsets: [offsetXStepper.value, offsetYStepper.value]
		};

		// Sub-atlas path (opcional): solo se guarda si se especificó algo
		var rawAssetPath = animAssetPathInput != null ? animAssetPathInput.text.trim() : "";
		if (rawAssetPath != "")
			newAnim.assetPath = rawAssetPath;

		// Render type (opcional): solo se guarda si no está vacío
		var rawRenderType = animRenderTypeInput != null ? animRenderTypeInput.text.trim().toLowerCase() : "";
		if (rawRenderType == "animateatlas" || rawRenderType == "sparrow")
			newAnim.renderType = rawRenderType;

		// flipX por animacion
		if (animFlipXCheckbox != null)
			newAnim.flipX = animFlipXCheckbox.checked;

		if (editingAnimName != null)
		{
			// ── Modo EDIT: actualizar la animación cuyo nombre original es editingAnimName ──
			var found = false;
			for (i in 0...currentAnimData.length)
			{
				if (currentAnimData[i].name == editingAnimName)
				{
					currentAnimData[i] = newAnim;
					found = true;
					break;
				}
			}

			if (!found)
			{
				// Por si acaso no existía, agregarla
				currentAnimData.push(newAnim);
			}

			reloadCharacterWithNewAnims();
			setHelp("✓ Animation updated: " + newName, FlxColor.LIME);

			// Mantener la selección apuntando a la anim recién editada
			var newIdx = animList.indexOf(newName);
			if (newIdx >= 0)
				curAnim = newIdx;

			// Volver a modo Add
			editingAnimName = null;
			if (addAnimBtn != null)
				addAnimBtn.label = "Add Animation";
		}
		else
		{
			// ── Modo ADD: nunca sobreescribir, error si el nombre ya existe ──
			var alreadyExists = false;
			for (anim in currentAnimData)
			{
				if (anim.name == newName)
				{
					alreadyExists = true;
					break;
				}
			}

			if (alreadyExists)
			{
				setHelp('✗ "' + newName + '" it already exists — use "← Load Selected" to edit it', FlxColor.RED);
				return;
			}

			currentAnimData.push(newAnim);
			reloadCharacterWithNewAnims();
			setHelp("✓ Animation add: " + newName, FlxColor.LIME);
		}

		_hasUnsaved = true;

		// Limpiar campos tras Add (no tras Edit, para comodidad)
		if (editingAnimName == null)
		{
			animNameInput.text = "";
			animPrefixInput.text = "";
		}
	}

	/**
	 * Rellena los campos del tab Animation con los datos de la animación
	 * seleccionada actualmente (curAnim). Así puedes editar cualquier anim
	 * sin tener que escribir todo desde cero.
	 */
	function loadAnimIntoUI():Void
	{
		if (animList.length == 0 || curAnim < 0 || curAnim >= animList.length)
		{
			setHelp("⚠ No animation selected", FlxColor.WHITE);
			return;
		}

		var animName = animList[curAnim];

		for (anim in currentAnimData)
		{
			if (anim.name == animName)
			{
				animNameInput.text = anim.name;
				animPrefixInput.text = anim.prefix != null ? anim.prefix : "";
				animFramerateStepper.value = anim.framerate != 0 ? anim.framerate : 24;
				animLoopedCheckbox.checked = anim.looped;
				offsetXStepper.value = anim.offsets[0];
				offsetYStepper.value = anim.offsets[1];

				// Cargar sub-atlas path y render type (nuevos campos opcionales)
				if (animAssetPathInput != null)
					animAssetPathInput.text = anim.assetPath != null ? anim.assetPath : "";
				if (animRenderTypeInput != null)
					animRenderTypeInput.text = anim.renderType != null ? anim.renderType : "";
				if (animFlipXCheckbox != null)
					animFlipXCheckbox.checked = anim.flipX == true;

				// Entrar en modo EDIT — guardar qué anim estamos modificando
				editingAnimName = animName;
				if (addAnimBtn != null)
					addAnimBtn.label = "Update Anim";

				setHelp('← Editing: $animName  |  "New / Clear" for cancel', FlxColor.CYAN);
				UI_box.selected_tab_id = "Animation";
				return;
			}
		}

		setHelp("⚠ Animation not found in dates", FlxColor.WHITE);
	}

	function deleteCurrentAnimation():Void
	{
		if (animList.length == 0 || curAnim < 0 || curAnim >= animList.length)
			return;

		// Guardar estado anterior antes de borrar
		_pushUndo();

		var animName = animList[curAnim];

		for (i in 0...currentAnimData.length)
		{
			if (currentAnimData[i].name == animName)
			{
				currentAnimData.splice(i, 1);
				break;
			}
		}

		reloadCharacterWithNewAnims();
		setHelp("✓ Animation erased: " + animName, FlxColor.LIME);
		_hasUnsaved = true;

		if (curAnim >= animList.length)
			curAnim = animList.length - 1;
		if (curAnim < 0)
			curAnim = 0;
	}

	// ── Import: Standard sprite ───────────────────────────────────────────────

	function browseForFile(fileType:String):Void
	{
		#if sys
		switch (fileType)
		{
			case "sprite":
				var _fdSpr = new FileDialog();
				_fdSpr.onSelect.add(function(path:String) { onSpriteSelected(path); });
				_fdSpr.browse(OPEN, "png", null, "Select Sprite PNG");
			case "icon":
				var _fdIco = new FileDialog();
				_fdIco.onSelect.add(function(path:String) { onFileSelected(path, "icon"); });
				_fdIco.browse(OPEN, "png", null, "Select Icon PNG");
		}
		#else
		FlxG.log.warn("File import solo disponible en desktop");
		#end
	}

	function onSpriteSelected(sourcePath:String):Void
	{
		#if sys
		try
		{
			var fileName = haxe.io.Path.withoutDirectory(sourcePath);
			var sourceDir = haxe.io.Path.directory(sourcePath) + "/";
			var baseName = haxe.io.Path.withoutExtension(fileName);

			var destDir = Paths.resolveWrite("characters/images/");
			Paths.ensureDir(destDir + "x");  // ensure dir exists

			File.copy(sourcePath, destDir + fileName);

			var xmlPath = sourceDir + baseName + ".xml";
			var txtPath = sourceDir + baseName + ".txt";

			if (FileSystem.exists(xmlPath))
			{
				File.copy(xmlPath, destDir + baseName + ".xml");
				setHelp("✓ PNG + XML importados — abriendo mapper…", FlxColor.LIME);

				// Parse unique prefixes from the XML and open the name mapper
				var rawAnims = _parseXmlPrefixes(destDir + baseName + ".xml");
				if (rawAnims.length > 0)
				{
					openSubState(new AnimMapperSubState(rawAnims, function(mapped:Array<funkin.gameplay.objects.character.Character.AnimData>)
					{
						// Guard: mapper returned empty (all rows deleted by user) — do not wipe existing anims
						if (mapped.length == 0)
						{
							setHelp("⚠ No animations confirmed — keeping existing list", FlxColor.YELLOW);
							return;
						}
						currentAnimData = mapped;
						reloadCharacterWithNewAnims();
						setHelp("✓ PNG + XML importados — " + mapped.length + " animaciones mapeadas", FlxColor.LIME);
					}));
				}
				else
				{
					// XML found but no parseable prefixes (e.g. non-Sparrow format)
					setHelp("⚠ PNG + XML importados — no se detectaron prefijos en el XML", FlxColor.YELLOW);
				}
			}
			else if (FileSystem.exists(txtPath))
			{
				File.copy(txtPath, destDir + baseName + ".txt");
				isTxtCheckbox.checked = true;
				setHelp("✓ PNG + TXT importados", FlxColor.LIME);
			}
			else
			{
				setHelp("⚠ PNG importado (sin XML/TXT)", FlxColor.WHITE);
			}

			pathInput.text = baseName;
		}
		catch (err:Dynamic)
		{
			setHelp("✗ Error: " + err, FlxColor.RED);
		}
		#end
	}

	function onFileSelected(sourcePath:String, fileType:String):Void
	{
		#if sys
		try
		{
			var fileName = haxe.io.Path.withoutDirectory(sourcePath);
			var destDir = (fileType == "icon") ? Paths.resolveWrite("images/icons/") : Paths.resolveWrite("characters/images/");
			var newFileName = fileName;

			Paths.ensureDir(destDir + "x");  // ensure dir exists

			if (fileType == "icon" && healthIconInput != null && healthIconInput.text != "")
			{
				var ext = haxe.io.Path.extension(fileName);
				newFileName = "icon-" + healthIconInput.text + "." + ext;
			}

			File.copy(sourcePath, destDir + newFileName);

			if (fileType == "icon" && healthIconInput != null)
				updateIconPreview(healthIconInput.text);

			setHelp("✓ " + newFileName + " imported!", FlxColor.LIME);
		}
		catch (err:Dynamic)
		{
			setHelp("✗ Error importing: " + err, FlxColor.RED);
		}
		#end
	}

	// ── Import: FlxAnimate ────────────────────────────────────────────────────

	/**
	 * Abre un FileDialog para seleccionar el PNG del spritemap.
	 * Detecta automáticamente el JSON del atlas y el Animation.json
	 * de la misma carpeta, y los copia todos a assets/images/<daAnim>/
	 */
	function browseForFlxAnimate():Void
	{
		#if sys
		var _fdAnim = new FileDialog();
		_fdAnim.onSelect.add(function(path:String) { onFlxAnimateSelected(path); });
		_fdAnim.browse(OPEN, "png", null, "Select Spritemap PNG (FlxAnimate)");
		#else
		FlxG.log.warn("File import only available on desktop");
		#end
	}

	function onFlxAnimateSelected(sourcePngPath:String):Void
	{
		#if sys
		try
		{
			var fileName = haxe.io.Path.withoutDirectory(sourcePngPath);
			var sourceDir = haxe.io.Path.directory(sourcePngPath) + "/";
			var baseName = haxe.io.Path.withoutExtension(fileName); // ej: "spritemap1"

			// Rutas que esperamos encontrar junto al PNG
			var atlasJsonSrc = sourceDir + baseName + ".json"; // spritemap1.json
			var animJsonSrc = sourceDir + "Animation.json";

			if (!FileSystem.exists(atlasJsonSrc))
			{
				setHelp("✗ Not found " + baseName + ".json next to PNG", FlxColor.RED);
				return;
			}

			// Destino: {root}/characters/images/<daAnim>/
			var destFolder = Paths.resolveWrite('characters/images/$daAnim/');
			Paths.ensureDir(destFolder + "x");  // ensure dir exists

			// Copiar los tres archivos
			File.copy(sourcePngPath, destFolder + fileName);
			FlxG.log.notice("Copied: " + destFolder + fileName);

			File.copy(atlasJsonSrc, destFolder + baseName + ".json");
			FlxG.log.notice("Copied: " + destFolder + baseName + ".json");

			var hasAnimJson = FileSystem.exists(animJsonSrc);
			if (hasAnimJson)
			{
				File.copy(animJsonSrc, destFolder + "Animation.json");
				FlxG.log.notice("Copied: " + destFolder + "Animation.json");
			}

			// Actualizar UI:
			// - path = nombre del personaje (ej: "myChar"), NO la ruta completa
			//   Character.hx lo convierte con Paths.characterFolder(path)
			// - spritemapName = nombre del PNG sin extensión (ej: "spritemap1")
			flxAnimateFolderPath = destFolder;
			pathInput.text = daAnim; // ← solo el nombre del personaje
			spritemapNameInput.text = baseName;
			isFlxAnimateCheckbox.checked = true;
			isTxtCheckbox.checked = false;
			isSpritesheetCheckbox.checked = false;

			// Si hay Animation.json, parsear símbolos y abrir el mapper de nombres
			if (hasAnimJson)
			{
				var rawAnims = _parseAnimJsonSymbols(destFolder + "Animation.json");
				if (rawAnims.length > 0)
				{
					setHelp("✓ FlxAnimate importado — abriendo mapper de símbolos…", FlxColor.LIME);
					openSubState(new AnimMapperSubState(rawAnims, function(mapped:Array<funkin.gameplay.objects.character.Character.AnimData>)
					{
						// Guard: mapper returned empty (all rows deleted by user) — do not wipe existing anims
						if (mapped.length == 0)
						{
							setHelp("⚠ No symbols confirmed — keeping existing animation list", FlxColor.YELLOW);
							return;
						}
						currentAnimData = mapped;
						reloadCharacterWithNewAnims();
						setHelp("✓ FlxAnimate importado — " + mapped.length + " símbolos mapeados", FlxColor.LIME);
					}));
				}
				else
				{
					loadAnimationsFromAnimationJson(destFolder + "Animation.json");
					setHelp("✓ FlxAnimate importado en " + destFolder, FlxColor.LIME);
				}
			}
			else
			{
				setHelp("✓ FlxAnimate importado\n⚠ Sin Animation.json — añade animaciones manualmente", FlxColor.WHITE);
			}
		}
		catch (err:Dynamic)
		{
			setHelp("✗ Error: " + err, FlxColor.RED);
		}
		#end
	}

	/**
	 * Lee el Animation.json y auto-genera currentAnimData con todos los
	 * símbolos del Symbol Dictionary (SD.S) como animaciones.
	 * El 'prefix' de cada animación = SN del símbolo.
	 */
	function loadAnimationsFromAnimationJson(animJsonPath:String):Void
	{
		#if sys
		try
		{
			var content = File.getContent(animJsonPath);
			var parsed:Dynamic = Json.parse(content);

			currentAnimData = [];

			// Registrar la animación principal (AN)
			if (parsed.AN != null)
			{
				currentAnimData.push({
					name: parsed.AN.SN,
					prefix: parsed.AN.SN,
					framerate: parsed.MD != null ? Std.int(parsed.MD.FRT) : 24,
					looped: true,
					offsets: [0, 0]
				});
			}

			// Registrar todos los símbolos del diccionario
			if (parsed.SD != null && parsed.SD.S != null)
			{
				for (sym in (cast parsed.SD.S : Array<Dynamic>))
				{
					currentAnimData.push({
						name: sym.SN,
						prefix: sym.SN,
						framerate: parsed.MD != null ? Std.int(parsed.MD.FRT) : 24,
						looped: false,
						offsets: [0, 0]
					});
				}
			}

			FlxG.log.notice('[AnimDebug] Loaded ' + currentAnimData.length + ' simbols of Animation.json');
			reloadCharacterWithNewAnims();
		}
		catch (e:Dynamic)
		{
			FlxG.log.error('[AnimDebug] Error reading Animation.json: ' + e);
			setHelp("✗ Error reading Animation.json: " + e, FlxColor.RED);
		}
		#end
	}

	/**
	 * Lista en consola todos los símbolos (SN) disponibles en el Animation.json
	 * del personaje actual. Útil para saber qué poner como "prefix" en cada animación.
	 */
	function listAvailableSymbols():Void
	{
		// Fallback: parsear Animation.json directamente
		#if sys
		var animJsonPath = flxAnimateFolderPath != "" ? flxAnimateFolderPath + "Animation.json" : Paths.characterFolder(pathInput.text) + "Animation.json";

		if (!FileSystem.exists(animJsonPath))
		{
			setHelp("⚠ Not found Animation.json in: " + animJsonPath, FlxColor.WHITE);
			return;
		}

		try
		{
			var content = File.getContent(animJsonPath);
			var parsed:Dynamic = Json.parse(content);

			trace("═══════════════════════════════════════════");
			trace("  SÍMBOLOS DISPONIBLES EN Animation.json");
			trace("  (usa el SN como 'prefix' en tus anims)");
			trace("═══════════════════════════════════════════");
			if (parsed.AN != null)
				trace("  [AN] " + parsed.AN.SN + "  ← Animación principal");

			if (parsed.SD != null && parsed.SD.S != null)
			{
				trace("  [SD] Símbols of diccionary:");
				for (sym in (cast parsed.SD.S : Array<Dynamic>))
					trace("    - " + sym.SN);
			}
			else
				trace("  (No Symbol Dictionary)");

			trace("═══════════════════════════════════════════");
			setHelp("✓ Símbols listed in console", FlxColor.LIME);
		}
		catch (e:Dynamic)
		{
			setHelp("✗ Error reading Animation.json: " + e, FlxColor.RED);
		}
		#else
		setHelp("⚠ Only available in desktop", FlxColor.RED);
		#end
	}

	// ── Character display ─────────────────────────────────────────────────────

	function displayCharacter(character:String):Void
	{
		// Al cambiar de personaje, cancelar cualquier edición pendiente
		editingAnimName = null;
		ghostAnimIdx = 0;
		if (addAnimBtn != null)
			addAnimBtn.label = "Add Animation";

		// FIX: cancelar tweens y destruir antes de limpiar para evitar tween-leaks.
		// Iterar en reversa para no alterar índices al hacer remove.
		var i = dumbTexts.members.length - 1;
		while (i >= 0)
		{
			var m = dumbTexts.members[i];
			if (m != null) { FlxTween.cancelTweensOf(m); m.destroy(); }
			i--;
		}
		dumbTexts.clear();
		// Limpiar caches de referencias — ya fueron destruidos arriba
		_offsetLabels.resize(0);
		_ghostBadgeBgs.resize(0);
		_ghostBadgeLabels.resize(0);
		_rowBgs.resize(0);
		animList = [];

		// FIX: destroy() libera la textura de VRAM; remove() solo quita del grupo.
		if (char != null)
		{
			layeringbullshit.remove(char, true);
			char.destroy();
			char = null;
		}
		if (ghostChar != null)
		{
			layeringbullshit.remove(ghostChar, true);
			ghostChar.destroy();
			ghostChar = null;
		}

		ghostChar = new Character(0, 0, character);
		ghostChar.alpha = 0.5;
		ghostChar.screenCenter();
		ghostChar.debugMode = true;
		layeringbullshit.add(ghostChar);

		char = new Character(0, 0, character);
		char.screenCenter();
		char.debugMode = true;
		layeringbullshit.add(char);
		// NO sobreescribir flipX aquí — Character.hx ya lo aplica desde el JSON.
		// loadCharacterData() actualizará el checkbox y sincronizará tras esto.

		// Aplicar positionOffset al preview (igual que en PlayState)
		if (char.characterData != null)
		{
			final posOff = char.characterData.positionOffset;
			if (posOff != null && posOff.length >= 2)
			{
				char.x += posOff[0];
				char.y += posOff[1];
				if (ghostChar != null)
				{
					ghostChar.x += posOff[0];
					ghostChar.y += posOff[1];
				}
			}
		}

		// Actualizar header con el nombre del personaje
		if (charHeaderText != null)
		{
			charHeaderText.text = "  ▶  " + daAnim.toUpperCase();
			// Pequeño bounce en el header
			FlxTween.cancelTweensOf(charHeaderText);
			charHeaderText.alpha = 0;
			FlxTween.tween(charHeaderText, {alpha: 1}, 0.3, {ease: FlxEase.quartOut});
		}

		generateOffsetTexts();
	}

	function generateOffsetTexts(pushList:Bool = true):Void
	{
		var daLoop = 0;
		var startY = 174;
		var rowH = 20;

		for (anim => offsets in char.animOffsets)
		{
			var rowY = startY + (rowH * daLoop);
			var isCur = (daLoop == curAnim);

			// Fondo de fila alternado
			var rowBg = new FlxSprite(4, rowY);
			rowBg.makeGraphic(332, rowH - 1, isCur ? 0x5500E5FF : (daLoop % 2 == 0 ? 0x22FFFFFF : 0x11FFFFFF));
			rowBg.scrollFactor.set();
			rowBg.cameras = [camHUD];
			rowBg.alpha = 0;
			dumbTexts.add(cast rowBg);
			_rowBgs.push(rowBg);
			FlxTween.tween(rowBg, {alpha: 1}, 0.2, {startDelay: daLoop * 0.03, ease: FlxEase.quartOut});

			// Punto de color a la izquierda para la fila activa
			if (isCur)
			{
				var dot = new FlxSprite(4, rowY);
				dot.makeGraphic(4, rowH - 1, 0xFF00E5FF);
				dot.scrollFactor.set();
				dot.cameras = [camHUD];
				dumbTexts.add(cast dot);
			}

			// Buscar si esta animación tiene sub-atlas propio para mostrar indicador ◈
			var animAssetTag = "";
			for (ad in currentAnimData)
			{
				if (ad.name == anim && ad.assetPath != null && ad.assetPath != "")
				{
					var parts = ad.assetPath.split("/");
					animAssetTag = " ◈" + parts[parts.length - 1];
					break;
				}
			}
			var label = anim + animAssetTag + "  [" + offsets[0] + ", " + offsets[1] + "]";
			var text = new FlxText(10, rowY + 3, 295, label, 11);
			text.scrollFactor.set();
			text.setBorderStyle(FlxTextBorderStyle.OUTLINE, 0xFF0A0A0F, 1);
			var hasCustomAtlas = animAssetTag != "";
			if (isCur)
				text.color = 0xFF00E5FF;
			else if (hasCustomAtlas)
				text.color = 0xFFFF90D0;
			else
				text.color = 0xFFCCCCCC;
			text.cameras = [camHUD];
			text.alpha = 0;
			dumbTexts.add(text);
			_offsetLabels.push(text); // guardar referencia para updates in-place
			FlxTween.tween(text, {alpha: 1}, 0.2, {startDelay: daLoop * 0.03 + 0.05, ease: FlxEase.quartOut});

			var isGhostRow = (daLoop == ghostAnimIdx);
			var ghostBadgeBg = new FlxSprite(308, rowY);
			ghostBadgeBg.makeGraphic(28, rowH - 1, isGhostRow ? 0xCC7744CC : 0x33FFFFFF);
			ghostBadgeBg.scrollFactor.set();
			ghostBadgeBg.cameras = [camHUD];
			ghostBadgeBg.alpha = 0;
			dumbTexts.add(cast ghostBadgeBg);
			_ghostBadgeBgs.push(ghostBadgeBg);
			FlxTween.tween(ghostBadgeBg, {alpha: 1}, 0.2, {startDelay: daLoop * 0.03, ease: FlxEase.quartOut});

			var ghostLabel = new FlxText(308, rowY + 3, 28, "[G]", 10);
			ghostLabel.scrollFactor.set();
			ghostLabel.alignment = CENTER;
			ghostLabel.color = isGhostRow ? 0xFFFFFFFF : 0x88FFFFFF;
			ghostLabel.cameras = [camHUD];
			ghostLabel.alpha = 0;
			dumbTexts.add(ghostLabel);
			_ghostBadgeLabels.push(ghostLabel);
			FlxTween.tween(ghostLabel, {alpha: 1}, 0.2, {startDelay: daLoop * 0.03 + 0.05, ease: FlxEase.quartOut});

			if (pushList)
				animList.push(anim);

			daLoop++;
		}

		// Mover el highlight a la posición correcta
		if (animRowHighlight != null)
		{
			animRowHighlight.y = startY + (rowH * curAnim);
			animRowHighlight.visible = animList.length > 0;
		}
	}

	function updateOffsetTexts():Void
	{
		// FIX: En lugar de destruir y recrear todos los objetos cada vez que
		// cambia un offset (incluyendo cada frame del drag), actualizamos solo
		// el texto de los labels ya existentes. Esto elimina la principal fuente
		// de memory leak (antes: ~75 objetos + tweens nuevos por frame durante drag).
		var daLoop = 0;
		for (anim => offsets in char.animOffsets)
		{
			// Actualizar label de offset
			if (daLoop < _offsetLabels.length)
			{
				var animAssetTag = "";
				for (ad in currentAnimData)
				{
					if (ad.name == anim && ad.assetPath != null && ad.assetPath != "")
					{
						var parts = ad.assetPath.split("/");
						animAssetTag = " ◈" + parts[parts.length - 1];
						break;
					}
				}
				var isCur = (daLoop == curAnim);
				var hasCustomAtlas = animAssetTag != "";
				_offsetLabels[daLoop].text = anim + animAssetTag + "  [" + offsets[0] + ", " + offsets[1] + "]";
				if (isCur)
					_offsetLabels[daLoop].color = 0xFF00E5FF;
				else if (hasCustomAtlas)
					_offsetLabels[daLoop].color = 0xFFFF90D0;
				else
					_offsetLabels[daLoop].color = 0xFFCCCCCC;
			}

			// Actualizar badge [G] del ghost
			if (daLoop < _ghostBadgeLabels.length)
				_ghostBadgeLabels[daLoop].color = (daLoop == ghostAnimIdx) ? 0xFFFFFFFF : 0x88FFFFFF;

			daLoop++;
		}

		// Mover el highlight a la nueva posición
		if (animRowHighlight != null && animList.length > 0)
			animRowHighlight.y = 174.0 + (20.0 * curAnim);
	}

	// ── loadCharacterData — carga el JSON del personaje en la UI ──────────────

	function loadCharacterData():Void
	{
		try
		{
			var jsonPath = Paths.characterJSON(daAnim);
			var content:String;

			#if sys
			if (FileSystem.exists(jsonPath))
				content = File.getContent(jsonPath);
			else
				content = lime.utils.Assets.getText(jsonPath);
			#else
			content = lime.utils.Assets.getText(jsonPath);
			#end

			characterData = cast Json.parse(content);

			if (pathInput != null)
				pathInput.text = characterData.path;

			if (scaleStepper != null)
				scaleStepper.value = characterData.scale;

			if (antialiasingCheckbox != null)
				antialiasingCheckbox.checked = characterData.antialiasing;

			if (playerCheckbox != null)
				playerCheckbox.checked = characterData.isPlayer;

			if (charFlipXCheckbox != null)
			{
				var fx = characterData.flipX != null ? characterData.flipX : false;
				charFlipXCheckbox.checked = fx;
				if (char != null)      char.flipX      = fx;
				if (ghostChar != null) ghostChar.flipX = fx;
			}

			if (charDeathInput != null)
				charDeathInput.text = characterData.charDeath != null ? characterData.charDeath : "";

			if (isTxtCheckbox != null)
				isTxtCheckbox.checked = characterData.isTxt != null ? characterData.isTxt : false;

			if (isSpritesheetCheckbox != null)
				isSpritesheetCheckbox.checked = characterData.isSpritemap != null ? characterData.isSpritemap : false;

			var usingFlxAnimate = characterData.isFlxAnimate != null ? characterData.isFlxAnimate : false;
			if (isFlxAnimateCheckbox != null)
				isFlxAnimateCheckbox.checked = usingFlxAnimate;

			if (spritemapNameInput != null)
			{
				spritemapNameInput.text = (characterData.spritemapName != null && characterData.spritemapName != "") ? characterData.spritemapName : "spritemap1";
				spritemapNameInput.color = usingFlxAnimate ? FlxColor.YELLOW : FlxColor.WHITE;
			}

			if (healthIconInput != null)
			{
				healthIconInput.text = characterData.healthIcon != null ? characterData.healthIcon : daAnim;
				updateIconPreview(healthIconInput.text);
			}

			if (healthBarColorInput != null)
			{
				var colorStr = characterData.healthBarColor != null ? characterData.healthBarColor : "#31B0D1";
				healthBarColorInput.text = colorStr;
				try
				{
					currentHealthBarColor = FlxColor.fromString(colorStr);
					if (hudHealthBar != null)
						hudHealthBar.color = currentHealthBarColor;
				}
				catch (_)
				{
				}
			}

			// ── Game Over fields ────────────────────────────────────────────────
			if (gameOverSoundInput != null)
				gameOverSoundInput.text = characterData.gameOverSound ?? '';
			if (gameOverMusicInput != null)
				gameOverMusicInput.text = characterData.gameOverMusic ?? '';
			if (gameOverEndInput != null)
				gameOverEndInput.text = characterData.gameOverEnd ?? '';
			if (gameOverBpmStepper != null)
				gameOverBpmStepper.value = characterData.gameOverBpm ?? 100;
			if (gameOverCamFrameStepper != null)
				gameOverCamFrameStepper.value = characterData.gameOverCamFrame ?? 12;

			// ── Position Offset ──────────────────────────────────────────────
			if (posOffsetXStepper != null && posOffsetYStepper != null)
			{
				var posOff = characterData.positionOffset;
				posOffsetXStepper.value = (posOff != null && posOff.length > 0) ? posOff[0] : 0;
				posOffsetYStepper.value = (posOff != null && posOff.length > 1) ? posOff[1] : 0;
			}

			// ── Camera Offset ────────────────────────────────────────────────
			if (camOffsetXStepper != null && camOffsetYStepper != null)
			{
				var camOff = characterData.cameraOffset;
				camOffsetXStepper.value = (camOff != null && camOff.length > 0) ? camOff[0] : 0;
				camOffsetYStepper.value = (camOff != null && camOff.length > 1) ? camOff[1] : 0;
			}

			currentAnimData = characterData.animations;

			if (usingFlxAnimate)
				flxAnimateFolderPath = Paths.characterFolder(characterData.path);
		}
		catch (e:Dynamic)
		{
			trace('[AnimDebug] No se encontraron datos para: ' + daAnim);
			currentAnimData = [];
		}
	}

	// ── reloadCharacterWithNewAnims ───────────────────────────────────────────

	function reloadCharacterWithNewAnims():Void
	{
		var tempData:CharacterData = {
			path: pathInput.text,
			animations: currentAnimData,
			isPlayer: playerCheckbox.checked,
			antialiasing: antialiasingCheckbox.checked,
			scale: scaleStepper.value
		};
		if (charFlipXCheckbox != null && charFlipXCheckbox.checked)
			tempData.flipX = true;

		if (isTxtCheckbox.checked)
			tempData.isTxt = true;

		if (isSpritesheetCheckbox.checked)
			tempData.isSpritemap = true;

		if (isFlxAnimateCheckbox.checked)
		{
			tempData.isFlxAnimate = true;
			var sm = spritemapNameInput.text.trim();
			if (sm != "" && sm != "spritemap1")
				tempData.spritemapName = sm;
		}

		if (charDeathInput != null && charDeathInput.text.trim() != "")
			tempData.charDeath = charDeathInput.text.trim();

		// ── Game Over ──────────────────────────────────────────────────────────
		if (gameOverSoundInput != null && gameOverSoundInput.text.trim() != "")
			tempData.gameOverSound = gameOverSoundInput.text.trim();
		if (gameOverMusicInput != null && gameOverMusicInput.text.trim() != "")
			tempData.gameOverMusic = gameOverMusicInput.text.trim();
		if (gameOverEndInput != null && gameOverEndInput.text.trim() != "")
			tempData.gameOverEnd = gameOverEndInput.text.trim();
		if (gameOverBpmStepper != null && gameOverBpmStepper.value != 100)
			tempData.gameOverBpm = gameOverBpmStepper.value;
		if (gameOverCamFrameStepper != null && Std.int(gameOverCamFrameStepper.value) != 12)
			tempData.gameOverCamFrame = Std.int(gameOverCamFrameStepper.value);

		// ── Position Offset ────────────────────────────────────────────────────
		if (posOffsetXStepper != null && posOffsetYStepper != null)
		{
			final px = posOffsetXStepper.value;
			final py = posOffsetYStepper.value;
			if (px != 0 || py != 0)
				tempData.positionOffset = [px, py];
		}

		// ── Camera Offset ──────────────────────────────────────────────────────
		if (camOffsetXStepper != null && camOffsetYStepper != null)
		{
			final cx = camOffsetXStepper.value;
			final cy = camOffsetYStepper.value;
			if (cx != 0 || cy != 0)
				tempData.cameraOffset = [cx, cy];
		}

		var jsonString = Json.stringify(tempData, null, '\t');

		#if sys
		try
		{
			final charPath = Paths.ensureDir(Paths.resolveWrite('characters/$daAnim.json'));
			File.saveContent(charPath, jsonString);
			_hasUnsaved = false;
			displayCharacter(daAnim);
			loadCharacterData();
		}
		catch (e:Dynamic)
		{
			FlxG.log.error('[AnimDebug] Error guardando datos temporales: ' + e);
		}
		#end
	}

	// ── Export ────────────────────────────────────────────────────────────────

	function buildExportData():CharacterData
	{
		var exportData:CharacterData = {
			path: pathInput.text,
			animations: currentAnimData,
			isPlayer: playerCheckbox.checked,
			antialiasing: antialiasingCheckbox.checked,
			scale: scaleStepper.value
		};
		if (charFlipXCheckbox != null && charFlipXCheckbox.checked)
			exportData.flipX = true;

		if (isTxtCheckbox.checked)
			exportData.isTxt = true;

		if (isSpritesheetCheckbox.checked)
			exportData.isSpritemap = true;

		if (isFlxAnimateCheckbox.checked)
		{
			exportData.isFlxAnimate = true;
			var sm = spritemapNameInput.text.trim();
			if (sm != "" && sm != "spritemap1")
				exportData.spritemapName = sm;
		}

		if (healthIconInput.text != "" && healthIconInput.text != daAnim)
			exportData.healthIcon = healthIconInput.text;

		if (healthBarColorInput.text != "" && healthBarColorInput.text != "#31B0D1")
			exportData.healthBarColor = healthBarColorInput.text;

		if (charDeathInput != null && charDeathInput.text.trim() != "")
			exportData.charDeath = charDeathInput.text.trim();

		// ── Game Over ──────────────────────────────────────────────────────────
		if (gameOverSoundInput != null && gameOverSoundInput.text.trim() != "")
			exportData.gameOverSound = gameOverSoundInput.text.trim();
		if (gameOverMusicInput != null && gameOverMusicInput.text.trim() != "")
			exportData.gameOverMusic = gameOverMusicInput.text.trim();
		if (gameOverEndInput != null && gameOverEndInput.text.trim() != "")
			exportData.gameOverEnd = gameOverEndInput.text.trim();
		if (gameOverBpmStepper != null && gameOverBpmStepper.value != 100)
			exportData.gameOverBpm = gameOverBpmStepper.value;
		if (gameOverCamFrameStepper != null && Std.int(gameOverCamFrameStepper.value) != 12)
			exportData.gameOverCamFrame = Std.int(gameOverCamFrameStepper.value);

		// ── Position Offset ────────────────────────────────────────────────────
		if (posOffsetXStepper != null && posOffsetYStepper != null)
		{
			final px = posOffsetXStepper.value;
			final py = posOffsetYStepper.value;
			if (px != 0 || py != 0)
				exportData.positionOffset = [px, py];
		}

		// ── Camera Offset ──────────────────────────────────────────────────────
		if (camOffsetXStepper != null && camOffsetYStepper != null)
		{
			final cx = camOffsetXStepper.value;
			final cy = camOffsetYStepper.value;
			if (cx != 0 || cy != 0)
				exportData.cameraOffset = [cx, cy];
		}

		return exportData;
	}

	function exportCharacterJSON():Void
	{
		var jsonString = Json.stringify(buildExportData(), null, '\t');

		_file = new FileReference();
		_file.addEventListener(Event.COMPLETE, onSaveComplete);
		_file.addEventListener(Event.CANCEL, onSaveCancel);
		_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file.save(jsonString, daAnim + ".json");
	}

	function exportOffsetsTXT():Void
	{
		var data = '';
		for (anim in animList)
		{
			if (char.animOffsets.exists(anim))
			{
				var offsets = char.animOffsets.get(anim);
				data += anim + " " + offsets[0] + " " + offsets[1] + "\n";
			}
		}

		if (data.length > 0)
		{
			_file = new FileReference();
			_file.addEventListener(Event.COMPLETE, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data.trim(), daAnim + "Offsets.txt");
		}
	}

	function copyJSONToClipboard():Void
	{
		var jsonString = Json.stringify(buildExportData(), null, '\t');
		#if desktop
		lime.system.Clipboard.text = jsonString;
		setHelp("✓ JSON copied to clipboard!", FlxColor.LIME);
		#else
		FlxG.log.warn("Clipboard not supported on this platform");
		#end
	}

	// ── File save events ──────────────────────────────────────────────────────

	function onSaveComplete(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		_hasUnsaved = false;
		setHelp("✓ File saved!", FlxColor.LIME);
	}

	function onSaveCancel(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
	}

	function onSaveError(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		setHelp("✗ Error saving file!", FlxColor.RED);
	}

	// ── Icon preview ──────────────────────────────────────────────────────────

	function updateIconPreview(iconName:String):Void
	{
		if (iconPreview != null && iconName != null && iconName != "")
			iconPreview.updateIcon(iconName, false);
	}

	// ── Update ────────────────────────────────────────────────────────────────

	override function update(elapsed:Float)
	{
		super.update(elapsed);
/*
		// Usar char.hasCurAnim() para ser compatible con FlxAnimate y sprites normales
		if (char == null || !char.hasCurAnim())
			return;*/

		var curAnimName = char.getCurAnimName();

		// Display
		textAnim.text = "▶  " + curAnimName + "  [" + (curAnim + 1) + "/" + animList.length + "]";

		if (animList.length > 0 && curAnim >= 0 && curAnim < animList.length)
		{
			var offsets = char.animOffsets.get(animList[curAnim]);
			if (offsets != null)
				textInfo.text = "Offset: [" + offsets[0] + ", " + offsets[1] + "]   Zoom: " + FlxMath.roundDecimal(camGame.zoom, 2);
		}

		// Mover el highlight a la fila activa (lerp suave)
		if (animRowHighlight != null && animList.length > 0)
		{
			var targetY = 174.0 + (20.0 * curAnim);
			animRowHighlight.y += (targetY - animRowHighlight.y) * 0.25;
			animRowHighlight.visible = true;
		}

		if (ghostChar != null)
			ghostChar.flipX = char.flipX;

		// Exit — ESC siempre funciona aunque estés escribiendo
		if (FlxG.keys.justPressed.ESCAPE)
		{
			if (_unsavedDlg != null)
			{
				// Ya hay diálogo abierto — ignorar ESC para evitar doble-close
			}
			else if (_hasUnsaved)
			{
				_unsavedDlg = new funkin.debug.EditorDialogs.UnsavedChangesDialog([camHUD]);
				_unsavedDlg.onSaveAndExit = () ->
				{
					reloadCharacterWithNewAnims();
					_hasUnsaved = false;
					remove(_unsavedDlg, true);
					_unsavedDlg = null;
					funkin.system.CursorManager.hide();
					LoadingState.loadAndSwitchState(new MainMenuState());
				};
				_unsavedDlg.onSave = () ->
				{
					reloadCharacterWithNewAnims();
					_hasUnsaved = false;
					remove(_unsavedDlg, true);
					_unsavedDlg = null;
				};
				_unsavedDlg.onExit = () ->
				{
					remove(_unsavedDlg, true);
					_unsavedDlg = null;
					funkin.system.CursorManager.hide();
					LoadingState.loadAndSwitchState(new MainMenuState());
				};
				add(_unsavedDlg);
			}
			else
			{
				funkin.system.CursorManager.hide();
				LoadingState.loadAndSwitchState(new MainMenuState());
			}
		}

		// ── Zoom con rueda del mouse (siempre activo, no requiere teclado) ────
		if (FlxG.mouse.wheel != 0 && !isMouseOverHUD())
		{
			camGame.zoom = Math.max(0.1, camGame.zoom + FlxG.mouse.wheel * 0.1);
		}

		// ── Undo — Ctrl+Z (siempre activo, incluso si hay texto enfocado) ──────
		// Se permite fuera de isTyping() para que funcione aunque un campo esté
		// activo; no modifica el texto del campo.
		if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.Z)
		{
			_doUndo();
		}

		// ── Todo lo demás se bloquea si el usuario está escribiendo en un campo ─
		if (isTyping())
			return;

		// ── Click en el badge [G] de cada fila para cambiar la anim del ghost ─
		// La columna del badge está en x=308–335, filas desde y=174 cada 20px.
		if (FlxG.mouse.justPressed && ghostChar != null && animList.length > 0)
		{
			var mx = FlxG.mouse.gameX;
			var my = FlxG.mouse.gameY;
			var listStartY = 174;
			var rowH2 = 20;
			if (mx >= 308 && mx <= 336 && my >= listStartY && my < listStartY + animList.length * rowH2)
			{
				var clickedIdx = Std.int((my - listStartY) / rowH2);
				if (clickedIdx >= 0 && clickedIdx < animList.length)
				{
					ghostAnimIdx = clickedIdx;
					if (ghostChar.visible)
						ghostChar.playAnim(animList[ghostAnimIdx]);
					updateOffsetTexts();
					setHelp("[G] Ghost → " + animList[ghostAnimIdx], 0xFFAA88FF);
				}
			}
		}

		// Reset camera
		if (FlxG.keys.justPressed.R)
		{
			camFollow.setPosition(FlxG.width / 2, FlxG.height / 2);
			camGame.zoom = 1;
		}

		// Ghost
		if (FlxG.keys.justPressed.T && ghostChar != null)
			ghostChar.visible = !ghostChar.visible;

		// Camera movement
		var camSpeed = 90 * (FlxG.keys.pressed.SHIFT ? 2 : 1);
		var moveH = FlxG.keys.pressed.J ? -1 : FlxG.keys.pressed.L ? 1 : 0;
		var moveV = FlxG.keys.pressed.I ? -1 : FlxG.keys.pressed.K ? 1 : 0;
		camFollow.velocity.set(moveH * camSpeed, moveV * camSpeed);

		// Animation switching
		if (FlxG.keys.justPressed.W)
		{
			curAnim--;
			if (curAnim < 0)
				curAnim = animList.length - 1;
		}
		if (FlxG.keys.justPressed.S)
		{
			curAnim++;
			if (curAnim >= animList.length)
				curAnim = 0;
		}

		if (FlxG.keys.justPressed.S || FlxG.keys.justPressed.W || FlxG.keys.justPressed.SPACE)
		{
			if (animList.length > 0 && curAnim >= 0 && curAnim < animList.length)
			{
				char.playAnim(animList[curAnim]);
				if (ghostChar != null)
					ghostChar.playAnim(animList[ghostAnimIdx]);
				updateOffsetTexts();

				// Bounce visual en el texto de animación
				FlxTween.cancelTweensOf(textAnim);
				textAnim.scale.set(1.15, 1.15);
				FlxTween.tween(textAnim.scale, {x: 1, y: 1}, 0.25, {ease: FlxEase.backOut});

				// Solo auto-cargar en la UI si YA estábamos en modo Edit,
				// para no pisar lo que el usuario estaba escribiendo
				if (editingAnimName != null)
					loadAnimIntoUI();
			}
		}

		// ── Offset adjustment por teclado ─────────────────────────────────────
		var upP = FlxG.keys.anyJustPressed([UP]);
		var rightP = FlxG.keys.anyJustPressed([RIGHT]);
		var downP = FlxG.keys.anyJustPressed([DOWN]);
		var leftP = FlxG.keys.anyJustPressed([LEFT]);
		var mult = FlxG.keys.pressed.SHIFT ? 10 : 1;

		if ((upP || rightP || downP || leftP) && animList.length > 0 && curAnim >= 0 && curAnim < animList.length)
		{
			var selAnim = animList[curAnim];
			var offsets = char.animOffsets.get(selAnim);

			if (offsets != null)
			{
				// Guardar estado anterior una vez por pulsación de tecla
				_pushUndo();

				if (upP)
					offsets[1] += 1 * mult;
				if (downP)
					offsets[1] -= 1 * mult;
				if (leftP)
					offsets[0] += 1 * mult;
				if (rightP)
					offsets[0] -= 1 * mult;

				for (anim in currentAnimData)
				{
					if (anim.name == selAnim)
					{
						anim.offsets = [offsets[0], offsets[1]];
						break;
					}
				}

				char.playAnim(selAnim);
				if (ghostChar != null)
					ghostChar.playAnim(animList[ghostAnimIdx]);
				updateOffsetTexts();
				_hasUnsaved = true;

				// Flash amarillo → normal en textInfo como feedback
				// FIX: reusar _flashTimer en vez de crear new FlxTimer() cada keypress.
				// Antes: mantener flecha pulsada = 60 timers/segundo acumulados.
				FlxTween.cancelTweensOf(textInfo);
				textInfo.color = 0xFFFFFFFF;
				if (_flashTimer != null)
					_flashTimer.reset(0.3);
				else
					_flashTimer = new FlxTimer().start(0.3, function(_)
					{
						if (textInfo != null)
							textInfo.color = 0xFFFFE566;
					});
			}
		}

		// ── Offset adjustment por mouse (click derecho + arrastrar) ───────────
		// Click DERECHO: arrastrar para mover el offset de la animación actual.
		// BUGFIX: antes usaba justPressed (click izquierdo) en lugar de justPressedRight,
		// causando que cualquier click izquierdo en el área de juego moviese los offsets.
		// La sensibilidad es 1px de mouse = 1px de offset (SHIFT = x3).
		if (!isMouseOverHUD())
		{
			var mouseMult = FlxG.keys.pressed.SHIFT ? 3 : 1;

			if (FlxG.mouse.justPressedRight)
			{
				isDraggingOffset = true;
				dragLastX = FlxG.mouse.gameX;
				dragLastY = FlxG.mouse.gameY;
				// Guardar estado antes de comenzar el arrastre (un solo push por drag)
				_pushUndo();
			}

			if (isDraggingOffset && FlxG.mouse.pressedRight)
			{
				var dx = (FlxG.mouse.gameX - dragLastX) * mouseMult;
				var dy = (FlxG.mouse.gameY - dragLastY) * mouseMult;
				dragLastX = FlxG.mouse.gameX;
				dragLastY = FlxG.mouse.gameY;

				if ((Math.abs(dx) > 0 || Math.abs(dy) > 0) && animList.length > 0 && curAnim >= 0 && curAnim < animList.length)
				{
					var selAnim = animList[curAnim];
					var offsets = char.animOffsets.get(selAnim);

					if (offsets != null)
					{
						// Arrastrar derecha = offset X decrece (igual que flecha derecha)
						offsets[0] -= dx;
						offsets[1] -= dy;

						for (anim in currentAnimData)
						{
							if (anim.name == selAnim)
							{
								anim.offsets = [offsets[0], offsets[1]];
								break;
							}
						}

						char.playAnim(selAnim);
						if (ghostChar != null)
							ghostChar.playAnim(animList[ghostAnimIdx]);
						updateOffsetTexts();
						_hasUnsaved = true;
					}
				}
			}

			if (FlxG.mouse.justReleasedRight)
				isDraggingOffset = false;
		}
		else
		{
			// Si el mouse está sobre la UI, cancelar drag para no interferir
			if (FlxG.mouse.justReleasedRight)
				isDraggingOffset = false;
		}
	} // end update

	// ── Undo helpers ──────────────────────────────────────────────────────────

	/**
	 * Guarda un snapshot de currentAnimData en el stack de undo.
	 * Llama esto ANTES de cualquier operación que modifique datos.
	 *
	 * No duplica el snapshot si currentAnimData no cambió respecto al
	 * último push (evita entradas inútiles al mantener teclas pulsadas).
	 */
	function _pushUndo():Void
	{
		var snap = Json.stringify(currentAnimData);
		if (snap == _lastUndoJson)
			return; // sin cambios desde el último push → no apilar duplicado
		_undoStack.push(snap);
		_lastUndoJson = snap;
		if (_undoStack.length > MAX_UNDO)
			_undoStack.shift();
	}

	/**
	 * Restaura el último snapshot del stack, recarga el personaje y
	 * sincroniza los offsets en memoria (char.animOffsets).
	 *
	 * Usa reloadCharacterWithNewAnims() para garantizar consistencia
	 * tanto si se deshace un cambio de offset como si se deshace
	 * un add/delete de animación.
	 */
	function _doUndo():Void
	{
		if (_undoStack.length == 0)
		{
			setHelp("↩ Nothing to undo", FlxColor.WHITE);
			return;
		}
		var snap = _undoStack.pop();
		_lastUndoJson = snap; // actualizar marca para evitar re-push inmediato
		currentAnimData = cast Json.parse(snap);
		reloadCharacterWithNewAnims();
		setHelp("↩ Undo  (" + _undoStack.length + " left)", FlxColor.CYAN);
	}

	// ── Helpers ───────────────────────────────────────────────────────────────

	/**
	 * Devuelve true si el cursor está sobre cualquier elemento del HUD
	 * (panel izquierdo, panel UI derecho, barra inferior, área de ícono).
	 * Se usa para bloquear el drag de offsets cuando el usuario hace click
	 * sobre la interfaz en lugar del área de juego.
	 */
	function isMouseOverHUD():Bool
	{
		// Usamos gameX/Y (flixel-git: screenX/Y están deprecated y siempre valen 0).
		// (sus coordenadas de mundo == coordenadas de pantalla).
		// FlxG.mouse.overlaps() en flixel-git no maneja bien cámaras no-default.
		var mx = FlxG.mouse.gameX;
		var my = FlxG.mouse.gameY;

		// Panel derecho (UI_box)
		if (mx >= UI_box.x && mx <= UI_box.x + UI_box.width
			&& my >= UI_box.y && my <= UI_box.y + UI_box.height)
			return true;

		// Panel izquierdo (leftPanel)
		if (mx >= leftPanel.x && mx <= leftPanel.x + leftPanel.width
			&& my >= leftPanel.y && my <= leftPanel.y + leftPanel.height)
			return true;

		// Barra de estado (statusBar)
		if (mx >= statusBar.x && mx <= statusBar.x + statusBar.width
			&& my >= statusBar.y && my <= statusBar.y + statusBar.height)
			return true;

		// Preview del ícono (iconBG)
		if (mx >= iconBG.x && mx <= iconBG.x + iconBG.width
			&& my >= iconBG.y && my <= iconBG.y + iconBG.height)
			return true;

		return false;
	}

	function setHelp(msg:String, color:FlxColor):Void
	{
		if (textHelp != null)
		{
			textHelp.text = msg;
			textHelp.color = color;
		}

		// Pulsar el acento de la barra de estado con el color del mensaje
		if (statusAccentBar != null)
		{
			statusAccentBar.color = color;
			FlxTween.cancelTweensOf(statusAccentBar);
			statusAccentBar.alpha = 1;
			FlxTween.tween(statusAccentBar, {alpha: 0.4}, 1.2, {ease: FlxEase.quartOut, onComplete: function(_)
			{
				statusAccentBar.alpha = 0.4;
			}});
		}
	}

	/**
	 * Devuelve true si cualquier campo de texto tiene el foco actualmente.
	 * Se usa para bloquear los atajos de teclado mientras el usuario escribe.
	 */
	function isTyping():Bool
	{
		// CoolInputText tiene hasFocus cuando está activo
		if (animNameInput != null && animNameInput.hasFocus)
			return true;
		if (animPrefixInput != null && animPrefixInput.hasFocus)
			return true;
		if (pathInput != null && pathInput.hasFocus)
			return true;
		if (spritemapNameInput != null && spritemapNameInput.hasFocus)
			return true;
		if (healthIconInput != null && healthIconInput.hasFocus)
			return true;
		if (healthBarColorInput != null && healthBarColorInput.hasFocus)
			return true;
		if (animAssetPathInput != null && animAssetPathInput.hasFocus)
			return true;
		if (animRenderTypeInput != null && animRenderTypeInput.hasFocus)
			return true;
		return false;
	}

	// ── _parseXmlPrefixes ────────────────────────────────────────────────────
	/**
	 * Lee un XML de Sparrow atlas y extrae los prefijos únicos de SubTexture
	 * (quitando los dígitos finales del nombre).
	 * Devuelve un Array<AnimData> listo para pasar a AnimMapperSubState.
	 */
	function _parseXmlPrefixes(xmlPath:String, framerate:Int = 24):Array<AnimData>
	{
		var result:Array<AnimData> = [];
		#if sys
		var seen = new Map<String, Bool>();
		try
		{
			var root = Xml.parse(sys.io.File.getContent(xmlPath)).firstElement();
			for (node in root.elements())
			{
				if (node.nodeName != "SubTexture") continue;
				var raw    = node.get("name") != null ? node.get("name") : "";
				var prefix = ~/\d+$/.replace(raw, ""); // strip trailing digits
				prefix = StringTools.trim(prefix);
				if (prefix != "" && !seen.exists(prefix))
				{
					seen.set(prefix, true);
					result.push({
						name:      prefix,
						prefix:    prefix,
						framerate: framerate,
						looped:    false,
						offsets:   [0, 0]
					});
				}
			}
		}
		catch (e:Dynamic) { FlxG.log.error("[AnimDebug] _parseXmlPrefixes error: " + e); }
		#end
		return result;
	}

	// ── _parseAnimJsonSymbols ─────────────────────────────────────────────────
	/**
	 * Lee un Animation.json de FlxAnimate y devuelve todos los símbolos (SN)
	 * como Array<AnimData> listo para AnimMapperSubState.
	 * A diferencia de loadAnimationsFromAnimationJson, NO modifica currentAnimData.
	 */
	function _parseAnimJsonSymbols(animJsonPath:String, framerate:Int = 24):Array<AnimData>
	{
		var result:Array<AnimData> = [];
		#if sys
		try
		{
			var parsed:Dynamic = haxe.Json.parse(sys.io.File.getContent(animJsonPath));
			var fps:Int = (parsed.MD != null) ? Std.int(parsed.MD.FRT) : framerate;
			// Deduplicate by SN so AN.SN never creates a duplicate of an SD.S entry
			var seen = new Map<String, Bool>();

			// Main animation (AN)
			if (parsed.AN != null && parsed.AN.SN != null && !seen.exists(parsed.AN.SN))
			{
				seen.set(parsed.AN.SN, true);
				result.push({ name: parsed.AN.SN, prefix: parsed.AN.SN,
					framerate: fps, looped: true, offsets: [0, 0] });
			}

			// Symbol dictionary (SD.S)
			if (parsed.SD != null && parsed.SD.S != null)
				for (sym in (cast parsed.SD.S : Array<Dynamic>))
					if (sym.SN != null && !seen.exists(sym.SN))
					{
						seen.set(sym.SN, true);
						result.push({ name: sym.SN, prefix: sym.SN,
							framerate: fps, looped: false, offsets: [0, 0] });
					}
		}
		catch (e:Dynamic) { FlxG.log.error("[AnimDebug] _parseAnimJsonSymbols error: " + e); }
		#end
		return result;
	}

	override function destroy():Void
	{
		// ── Quitar listener de cierre de ventana ───────────────────────────
		#if sys
		if (_windowCloseFn != null)
		{
			try { lime.app.Application.current.window.onClose.remove(_windowCloseFn); }
			catch (_) {}
			_windowCloseFn = null;
		}
		#end

		// Limpiar timer reutilizable
		if (_flashTimer != null)
		{
			_flashTimer.cancel();
			_flashTimer.destroy();
			_flashTimer = null;
		}

		// Vaciar caches de referencias (los objetos se destruyen con el grupo)
		_offsetLabels.resize(0);
		_ghostBadgeBgs.resize(0);
		_ghostBadgeLabels.resize(0);
		_rowBgs.resize(0);

		_unsavedDlg = null;
		super.destroy();
	}

}