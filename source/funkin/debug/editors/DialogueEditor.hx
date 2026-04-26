package funkin.debug.editors;
import funkin.debug.EditorDialogs.UnsavedChangesDialog;
import coolui.CoolInputText;


import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.text.FlxText;
import coolui.CoolButton;
import flixel.util.FlxColor;
import funkin.cutscenes.dialogue.DialogueData;
import funkin.transitions.StateTransition;
import funkin.cutscenes.dialogue.DialogueData.*;
import funkin.cutscenes.dialogue.DialogueBoxImproved;
import flixel.group.FlxSpriteGroup;
import funkin.gameplay.PlayState;


#if sys
import lime.ui.FileDialog;
#end

using StringTools;

/**
 * Editor visual de diálogos con sistema de skins
 */
class DialogueEditor extends FlxState
{
	// === UI ELEMENTOS ===
	var bg:FlxSprite;
	var titleText:FlxText;
	var messageList:FlxTypedGroup<FlxText>;
	var messageButtons:FlxTypedGroup<CoolButton>;
	var skinList:FlxTypedGroup<FlxText>;
	var skinButtons:FlxTypedGroup<CoolButton>;
	var portraitList:FlxTypedGroup<FlxText>;
	var portraitButtons:FlxTypedGroup<CoolButton>;
	var boxList:FlxTypedGroup<FlxText>;
	var boxButtons:FlxTypedGroup<CoolButton>;

	// === LABELS Y TÍTULOS (para ocultar/mostrar) ===
	// Conversation tab
	var convPanelTitle:FlxText;
	var convFilesTitle:FlxText;
	var convFileList:FlxTypedGroup<FlxText>;
	var convFileButtons:FlxTypedGroup<CoolButton>;
	var convNameLabel:FlxText;
	var convSkinLabel:FlxText;
	var convMessagesPanelTitle:FlxText;
	var convEditPanelTitle:FlxText;
	var convCharLabel:FlxText;
	var convPortraitLabel:FlxText;
	var convBoxLabel:FlxText;
	var convTextLabel:FlxText;
	var convBubbleLabel:FlxText;
	var convSpeedLabel:FlxText;
	var convMusicLabel:FlxText;
	var convUpdateBtn:CoolButton;
	var convCycleBubbleBtn:CoolButton;

	// Skin tab
	var skinPanelTitle:FlxText;
	var skinConfigTitle:FlxText;
	var skinNameLabel:FlxText;
	var skinStyleLabel:FlxText;
	var skinToggleStyleBtn:CoolButton;
	var skinBgColorLabel:FlxText;
	var skinTextConfigTitle:FlxText;
	var skinTextPosLabel:FlxText;
	var skinTextSizeLabel:FlxText;
	var skinTextFontLabel:FlxText;
	var skinTextColorLabel:FlxText;

	// Portraits tab
	var portraitsPanelTitle:FlxText;
	var portraitsConfigTitle:FlxText;
	var portraitsNameLabel:FlxText;
	var portraitsPosLabel:FlxText;
	var portraitsScaleLabel:FlxText;
	var portraitsAnimLabel:FlxText;
	var portraitsUpdateBtn:CoolButton;

	// Boxes tab
	var boxesPanelTitle:FlxText;
	var boxesConfigTitle:FlxText;
	var boxesNameLabel:FlxText;
	var boxesPosLabel:FlxText;
	var boxesScaleLabel:FlxText;
	var boxesAnimLabel:FlxText;
	var boxesUpdateBtn:CoolButton;

	// === TAB SYSTEM ===
	var currentTab:EditorTab = CONVERSATION;
	var tabButtons:Map<EditorTab, CoolButton>;
	
	// === TAB GROUPS (para visibilidad) ===
	var conversationGroup:FlxSpriteGroup;
	var skinGroup:FlxSpriteGroup;
	var portraitsGroup:FlxSpriteGroup;
	var boxesGroup:FlxSpriteGroup;

	// === INPUTS (Conversación) ===
	var conversationNameInput:CoolInputText;
	var skinNameDisplay:FlxText;
	var characterText:CoolInputText;
	var messageText:CoolInputText;
	var bubbleTypeText:CoolInputText;
	var speedText:CoolInputText;
	var portraitNameInput:CoolInputText;
	var boxNameInput:CoolInputText;
	var musicInput:CoolInputText;

	// === INPUTS (Skin) ===
	var skinNameInput:CoolInputText;
	var styleText:CoolInputText;
	var bgColorText:CoolInputText;
	var textXInput:CoolInputText;
	var textYInput:CoolInputText;
	var textWidthInput:CoolInputText;
	var textSizeInput:CoolInputText;
	var textFontInput:CoolInputText;
	var textColorInput:CoolInputText;

	// === INPUTS (Portrait) ===
	var portraitConfigNameInput:CoolInputText;
	var portraitXInput:CoolInputText;
	var portraitYInput:CoolInputText;
	var portraitScaleXInput:CoolInputText;
	var portraitScaleYInput:CoolInputText;
	var portraitAnimInput:CoolInputText;

	// === INPUTS (Box) ===
	var boxConfigNameInput:CoolInputText;
	var boxXInput:CoolInputText;
	var boxYInput:CoolInputText;
	var boxScaleXInput:CoolInputText;
	var boxScaleYInput:CoolInputText;
	var boxAnimInput:CoolInputText;

	// === BOTONES ===
	var addMessageBtn:CoolButton;
	var removeMessageBtn:CoolButton;
	var saveConversationBtn:CoolButton;
	var loadConversationBtn:CoolButton;
	var saveSkinBtn:CoolButton;
	var loadSkinBtn:CoolButton;
	var createSkinBtn:CoolButton;
	var testBtn:CoolButton;
	var importPortraitBtn:CoolButton;
	var importBoxBtn:CoolButton;
	var addPortraitBtn:CoolButton;
	var addBoxBtn:CoolButton;
	var removePortraitBtn:CoolButton;
	var removeBoxBtn:CoolButton;

	var _isDirty    : Bool = false;
	var _unsavedDlg : UnsavedChangesDialog = null;
	var _windowCloseFn : Void->Void = null;

	// === DATOS ===
	var conversation:DialogueConversation;
	var currentSkin:DialogueSkin;
	var currentSkinName:String = "default";
	var selectedMessageIndex:Int = -1;
	var selectedPortraitName:String = null;
	var selectedBoxName:String = null;
	var availableSkins:Array<String> = [];

	// === PREVIEW ===
	var previewBox:DialogueBoxImproved;

	// === LAYOUT ===
	static final PADDING = 10;
	static final PANEL_WIDTH = 350;
	static final TAB_HEIGHT = 40;

	var song:String = 'Test';

	override public function create():Void
	{
		funkin.debug.themes.EditorTheme.load();
		funkin.audio.MusicManager.play('chartEditorLoop/chartEditorLoop', 0.7);

		if (PlayState.SONG.song == null)
			PlayState.SONG.song = 'Test';

		if (PlayState.SONG.song != null)
			song = PlayState.SONG.song;

		// Inicializar datos
		initializeData();

		// Crear UI
		createBackground();
		createTabs();
		createConversationTab();
		createSkinTab();
		createPortraitsTab();
		createBoxesTab();
		createInstructions();

		// Mostrar pestaña inicial
		switchTab(CONVERSATION);

		// ✨ Botón de tema (esquina superior derecha)
		var _themeBtn = new coolui.CoolButton(FlxG.width - 80, 4, "\u2728 Theme", function()
		{
			openSubState(new funkin.debug.themes.ThemePickerSubState());
		});
		add(_themeBtn);

		funkin.system.CursorManager.show();

		// Window-close guard
		#if sys
		_windowCloseFn = function()
		{
			if (_isDirty)
				try { saveConversation(); } catch (_) {}
		};
		lime.app.Application.current.window.onClose.add(_windowCloseFn);
		#end

		super.create();

		StateTransition.onStateCreated();
	}

	/**
	 * Inicializar datos
	 */
	function initializeData():Void
	{
		// Cargar lista de skins disponibles
		availableSkins = DialogueData.listSkins();

		// Si no hay skins, crear una por defecto
		if (availableSkins.length == 0)
		{
			currentSkinName = "default";
			currentSkin = DialogueData.createEmptySkin(currentSkinName, "pixel");
			DialogueData.saveSkin(currentSkinName, currentSkin);
			availableSkins.push(currentSkinName);
		}
		else
		{
			// Cargar primera skin disponible
			currentSkinName = availableSkins[0];
			currentSkin = DialogueData.loadSkin(currentSkinName);
		}

		// Inicializar conversación vacía
		conversation = DialogueData.createEmptyConversation("new_dialogue", currentSkinName);
	}

	/**
	 * Crear fondo
	 */
	function createBackground():Void
	{
		bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, funkin.debug.themes.EditorTheme.current.bgDark);
		add(bg);

		titleText = new FlxText(0, PADDING, FlxG.width, "DIALOGUE EDITOR - With Skins", 28);
		titleText.alignment = CENTER;
		titleText.setBorderStyle(OUTLINE, FlxColor.BLACK, 2);
		add(titleText);
	}

	/**
	 * Crear sistema de tabs
	 */
	function createTabs():Void
	{
		tabButtons = new Map<EditorTab, CoolButton>();
		var tabs = [CONVERSATION, SKIN, PORTRAITS, BOXES];
		var tabNames = ["Conversation", "Skin", "Portraits", "Boxes"];
		var tabWidth = (FlxG.width - PADDING * (tabs.length + 1)) / tabs.length;
		
		for (i in 0...tabs.length)
		{
			var x = PADDING + (tabWidth + PADDING) * i;
			var btn = new CoolButton(x, 50, tabNames[i], function()
			{
				switchTab(tabs[i]);
			});
			btn.resize(Std.int(tabWidth), TAB_HEIGHT);
			btn.setLabelFormat(null, 16, FlxColor.WHITE);
			add(btn);
			tabButtons.set(tabs[i], btn);
		}
	}

	/**
	 * Cambiar de tab
	 */
	function switchTab(tab:EditorTab):Void
	{
		currentTab = tab;

		// Actualizar colores de tabs
		for (t in tabButtons.keys())
		{
			var btn = tabButtons.get(t);
			btn.color = (t == tab) ? funkin.debug.themes.EditorTheme.current.accent : funkin.debug.themes.EditorTheme.current.bgHover;
		}

		// Ocultar todos los elementos
		hideAllTabElements();

		// Mostrar elementos del tab actual
		switch (tab)
		{
			case CONVERSATION:
				showConversationTab();
			case SKIN:
				showSkinTab();
			case PORTRAITS:
				showPortraitsTab();
			case BOXES:
				showBoxesTab();
		}
	}

	/**
	 * Ocultar todos los elementos de tabs
	 */
	function hideAllTabElements():Void
	{
		// === CONVERSATION TAB ===
		if (convPanelTitle != null) convPanelTitle.visible = false;
		if (convFilesTitle != null) convFilesTitle.visible = false;
		if (convFileList != null) convFileList.visible = false;
		if (convFileButtons != null) convFileButtons.visible = false;
		if (convNameLabel != null) convNameLabel.visible = false;
		if (conversationNameInput != null) conversationNameInput.visible = false;
		if (convSkinLabel != null) convSkinLabel.visible = false;
		if (skinNameDisplay != null) skinNameDisplay.visible = false;
		if (convMessagesPanelTitle != null) convMessagesPanelTitle.visible = false;
		if (messageList != null) messageList.visible = false;
		if (messageButtons != null) messageButtons.visible = false;
		if (convEditPanelTitle != null) convEditPanelTitle.visible = false;
		if (convCharLabel != null) convCharLabel.visible = false;
		if (characterText != null) characterText.visible = false;
		if (convPortraitLabel != null) convPortraitLabel.visible = false;
		if (portraitNameInput != null) portraitNameInput.visible = false;
		if (convBoxLabel != null) convBoxLabel.visible = false;
		if (boxNameInput != null) boxNameInput.visible = false;
		if (convTextLabel != null) convTextLabel.visible = false;
		if (messageText != null) messageText.visible = false;
		if (convBubbleLabel != null) convBubbleLabel.visible = false;
		if (bubbleTypeText != null) bubbleTypeText.visible = false;
		if (convCycleBubbleBtn != null) convCycleBubbleBtn.visible = false;
		if (convSpeedLabel != null) convSpeedLabel.visible = false;
		if (speedText != null) speedText.visible = false;
		if (convMusicLabel != null) convMusicLabel.visible = false;
		if (musicInput != null) musicInput.visible = false;
		if (convUpdateBtn != null) convUpdateBtn.visible = false;
		if (removeMessageBtn != null) removeMessageBtn.visible = false;
		if (addMessageBtn != null) addMessageBtn.visible = false;
		if (saveConversationBtn != null) saveConversationBtn.visible = false;
		if (loadConversationBtn != null) loadConversationBtn.visible = false;
		if (testBtn != null) testBtn.visible = false;

		// === SKIN TAB ===
		if (skinPanelTitle != null) skinPanelTitle.visible = false;
		if (skinList != null) skinList.visible = false;
		if (skinButtons != null) skinButtons.visible = false;
		if (createSkinBtn != null) createSkinBtn.visible = false;
		if (skinConfigTitle != null) skinConfigTitle.visible = false;
		if (skinNameLabel != null) skinNameLabel.visible = false;
		if (skinNameInput != null) skinNameInput.visible = false;
		if (skinStyleLabel != null) skinStyleLabel.visible = false;
		if (styleText != null) styleText.visible = false;
		if (skinToggleStyleBtn != null) skinToggleStyleBtn.visible = false;
		if (skinBgColorLabel != null) skinBgColorLabel.visible = false;
		if (bgColorText != null) bgColorText.visible = false;
		if (skinTextConfigTitle != null) skinTextConfigTitle.visible = false;
		if (skinTextPosLabel != null) skinTextPosLabel.visible = false;
		if (textXInput != null) textXInput.visible = false;
		if (textYInput != null) textYInput.visible = false;
		if (skinTextSizeLabel != null) skinTextSizeLabel.visible = false;
		if (textWidthInput != null) textWidthInput.visible = false;
		if (textSizeInput != null) textSizeInput.visible = false;
		if (skinTextFontLabel != null) skinTextFontLabel.visible = false;
		if (textFontInput != null) textFontInput.visible = false;
		if (skinTextColorLabel != null) skinTextColorLabel.visible = false;
		if (textColorInput != null) textColorInput.visible = false;
		if (saveSkinBtn != null) saveSkinBtn.visible = false;
		if (loadSkinBtn != null) loadSkinBtn.visible = false;

		// === PORTRAITS TAB ===
		if (portraitsPanelTitle != null) portraitsPanelTitle.visible = false;
		if (portraitList != null) portraitList.visible = false;
		if (portraitButtons != null) portraitButtons.visible = false;
		if (importPortraitBtn != null) importPortraitBtn.visible = false;
		if (addPortraitBtn != null) addPortraitBtn.visible = false;
		if (portraitsConfigTitle != null) portraitsConfigTitle.visible = false;
		if (portraitsNameLabel != null) portraitsNameLabel.visible = false;
		if (portraitConfigNameInput != null) portraitConfigNameInput.visible = false;
		if (portraitsPosLabel != null) portraitsPosLabel.visible = false;
		if (portraitXInput != null) portraitXInput.visible = false;
		if (portraitYInput != null) portraitYInput.visible = false;
		if (portraitsScaleLabel != null) portraitsScaleLabel.visible = false;
		if (portraitScaleXInput != null) portraitScaleXInput.visible = false;
		if (portraitScaleYInput != null) portraitScaleYInput.visible = false;
		if (portraitsAnimLabel != null) portraitsAnimLabel.visible = false;
		if (portraitAnimInput != null) portraitAnimInput.visible = false;
		if (portraitsUpdateBtn != null) portraitsUpdateBtn.visible = false;
		if (removePortraitBtn != null) removePortraitBtn.visible = false;

		// === BOXES TAB ===
		if (boxesPanelTitle != null) boxesPanelTitle.visible = false;
		if (boxList != null) boxList.visible = false;
		if (boxButtons != null) boxButtons.visible = false;
		if (importBoxBtn != null) importBoxBtn.visible = false;
		if (addBoxBtn != null) addBoxBtn.visible = false;
		if (boxesConfigTitle != null) boxesConfigTitle.visible = false;
		if (boxesNameLabel != null) boxesNameLabel.visible = false;
		if (boxConfigNameInput != null) boxConfigNameInput.visible = false;
		if (boxesPosLabel != null) boxesPosLabel.visible = false;
		if (boxXInput != null) boxXInput.visible = false;
		if (boxYInput != null) boxYInput.visible = false;
		if (boxesScaleLabel != null) boxesScaleLabel.visible = false;
		if (boxScaleXInput != null) boxScaleXInput.visible = false;
		if (boxScaleYInput != null) boxScaleYInput.visible = false;
		if (boxesAnimLabel != null) boxesAnimLabel.visible = false;
		if (boxAnimInput != null) boxAnimInput.visible = false;
		if (boxesUpdateBtn != null) boxesUpdateBtn.visible = false;
		if (removeBoxBtn != null) removeBoxBtn.visible = false;
	}

	/**
	 * Crear instrucciones
	 */
	function createInstructions():Void
	{
		var instructions = new FlxText(PADDING, FlxG.height - 80, FlxG.width - PADDING * 2,
			"CLICK en campos para editar | ENTER: confirmar | ESC: volver\n"
			+ "CTRL+S: Guardar | CTRL+T: Probar | CTRL+N: Nuevo mensaje", 12);
		instructions.alignment = CENTER;
		instructions.setBorderStyle(OUTLINE, FlxColor.BLACK, 1);
		add(instructions);
	}

	// ========================================
	// TAB: CONVERSATION
	// ========================================

	/**
	 * Crear tab de conversación
	 */
	function createConversationTab():Void
	{
		var startY = 100;
		var leftX = PADDING;
		var rightX = PANEL_WIDTH + PADDING * 2;

		// === PANEL IZQUIERDO: INFO GENERAL ===
		convPanelTitle = new FlxText(leftX, startY, PANEL_WIDTH, "GENERAL INFO", 20);
		convPanelTitle.setBorderStyle(OUTLINE, FlxColor.BLACK, 2);
		add(convPanelTitle);
		startY += 30;

		// Nombre conversación
		convNameLabel = new FlxText(leftX, startY, PANEL_WIDTH, "Conversation Name:", 14);
		add(convNameLabel);
		startY += 18;

		conversationNameInput = createEditableText(leftX, startY, PANEL_WIDTH - 20, conversation.name);
		add(conversationNameInput);
		startY += 35;

		// Skin actual
		convSkinLabel = new FlxText(leftX, startY, PANEL_WIDTH, "Current Skin:", 14);
		add(convSkinLabel);
		startY += 18;

		skinNameDisplay = new FlxText(leftX, startY, PANEL_WIDTH - 20, currentSkinName, 14);
		skinNameDisplay.setBorderStyle(OUTLINE, FlxColor.BLACK, 1);
		skinNameDisplay.color = funkin.debug.themes.EditorTheme.current.accent;
		add(skinNameDisplay);
		startY += 35;

		// Botones de archivo
		var btnWidth = (PANEL_WIDTH - 20) / 2;

		saveConversationBtn = new CoolButton(leftX, startY, "SAVE", saveConversation);
		saveConversationBtn.resize(Std.int(btnWidth), 30);
		saveConversationBtn.setLabelFormat(null, 8, FlxColor.BLACK);
		add(saveConversationBtn);

		loadConversationBtn = new CoolButton(leftX + btnWidth + 10, startY, "LOAD", loadConversation);
		loadConversationBtn.resize(Std.int(btnWidth), 30);
		loadConversationBtn.setLabelFormat(null, 8, FlxColor.BLACK);
		add(loadConversationBtn);
		startY += 40;

		testBtn = new CoolButton(leftX, startY, "TEST DIALOGUE", testDialogue);
		testBtn.resize(PANEL_WIDTH - 10, 30);
		testBtn.setLabelFormat(null, 8, FlxColor.BLACK);
		add(testBtn);
		startY += 40;

		// === LISTA DE DIÁLOGOS DISPONIBLES EN LA CANCIÓN ===
		convFilesTitle = new FlxText(leftX, startY, PANEL_WIDTH, "DIALOGUES IN SONG:", 14);
		convFilesTitle.setBorderStyle(OUTLINE, FlxColor.BLACK, 1);
		add(convFilesTitle);
		startY += 20;

		convFileList = new FlxTypedGroup<FlxText>();
		add(convFileList);

		convFileButtons = new FlxTypedGroup<CoolButton>();
		add(convFileButtons);

		// === PANEL MEDIO: LISTA DE MENSAJES ===
		startY = 100;
		var midX = PANEL_WIDTH + PADDING * 2;
		var midWidth = PANEL_WIDTH;

		convMessagesPanelTitle = new FlxText(midX, startY, midWidth, "MESSAGES", 20);
		convMessagesPanelTitle.setBorderStyle(OUTLINE, FlxColor.BLACK, 2);
		add(convMessagesPanelTitle);
		startY += 30;

		messageList = new FlxTypedGroup<FlxText>();
		add(messageList);

		messageButtons = new FlxTypedGroup<CoolButton>();
		add(messageButtons);

		addMessageBtn = new CoolButton(midX, FlxG.height - 120, "ADD MESSAGE", addMessage);
		addMessageBtn.resize(midWidth, 30);
		addMessageBtn.setLabelFormat(null, 8, FlxColor.BLACK);
		add(addMessageBtn);

		// === PANEL DERECHO: EDITAR MENSAJE ===
		startY = 100;
		rightX = PANEL_WIDTH * 2 + PADDING * 3;
		var rightWidth = FlxG.width - rightX - PADDING;

		convEditPanelTitle = new FlxText(rightX, startY, rightWidth, "EDIT MESSAGE", 20);
		convEditPanelTitle.setBorderStyle(OUTLINE, FlxColor.BLACK, 2);
		add(convEditPanelTitle);
		startY += 30;

		// Character
		convCharLabel = new FlxText(rightX, startY, rightWidth, "Character:", 14);
		add(convCharLabel);
		startY += 18;

		characterText = createEditableText(rightX, startY, rightWidth - 20, "dad");
		add(characterText);
		startY += 30;

		// Portrait name
		convPortraitLabel = new FlxText(rightX, startY, rightWidth, "Portrait Name:", 14);
		add(convPortraitLabel);
		startY += 18;

		portraitNameInput = createEditableText(rightX, startY, rightWidth - 20, "");
		add(portraitNameInput);
		startY += 30;

		// Box name
		convBoxLabel = new FlxText(rightX, startY, rightWidth, "Box Name:", 14);
		add(convBoxLabel);
		startY += 18;

		boxNameInput = createEditableText(rightX, startY, rightWidth - 20, "");
		add(boxNameInput);
		startY += 30;

		// Text
		convTextLabel = new FlxText(rightX, startY, rightWidth, "Text:", 14);
		add(convTextLabel);
		startY += 18;

		messageText = createEditableText(rightX, startY, rightWidth - 20, "Type message...", 12);
		add(messageText);
		startY += 60;

		// Bubble type
		convBubbleLabel = new FlxText(rightX, startY, rightWidth, "Bubble Type:", 14);
		add(convBubbleLabel);
		startY += 18;

		bubbleTypeText = createEditableText(rightX, startY, 150, "normal");
		add(bubbleTypeText);

		convCycleBubbleBtn = new CoolButton(rightX + 160, startY - 2, "CYCLE", function()
		{
			var types = ["normal", "loud", "angry", "evil"];
			var current = types.indexOf(bubbleTypeText.text);
			var next = (current + 1) % types.length;
			bubbleTypeText.text = types[next];
		});
		convCycleBubbleBtn.resize(120, 25);
		convCycleBubbleBtn.setLabelFormat(null, 12, FlxColor.BLACK);
		add(convCycleBubbleBtn);
		startY += 30;

		// Speed
		convSpeedLabel = new FlxText(rightX, startY, rightWidth, "Speed:", 14);
		add(convSpeedLabel);
		startY += 18;

		speedText = createEditableText(rightX, startY, rightWidth - 20, "0.04");
		add(speedText);
		startY += 35;

		// Music
		convMusicLabel = new FlxText(rightX, startY, rightWidth, "Music (optional):", 14);
		add(convMusicLabel);
		startY += 18;

		musicInput = createEditableText(rightX, startY, rightWidth - 20, "");
		add(musicInput);
		startY += 35;

		// Botones
		convUpdateBtn = new CoolButton(rightX, startY, "UPDATE", updateCurrentMessage);
		convUpdateBtn.resize(Std.int((rightWidth - 10) / 2), 30);
		convUpdateBtn.setLabelFormat(null, 8, FlxColor.BLACK);
		add(convUpdateBtn);

		removeMessageBtn = new CoolButton(rightX + (rightWidth - 10) / 2 + 10, startY, "REMOVE", removeMessage);
		removeMessageBtn.resize(Std.int((rightWidth - 10) / 2), 30);
		removeMessageBtn.setLabelFormat(null, 8, FlxColor.BLACK);
		add(removeMessageBtn);

		refreshMessageList();
	}

	/**
	 * Mostrar tab de conversación
	 */
	function showConversationTab():Void
	{
		if (convPanelTitle != null) convPanelTitle.visible = true;
		if (convFilesTitle != null) convFilesTitle.visible = true;
		if (convFileList != null) convFileList.visible = true;
		if (convFileButtons != null) convFileButtons.visible = true;
		if (convNameLabel != null) convNameLabel.visible = true;
		if (conversationNameInput != null) conversationNameInput.visible = true;
		if (convSkinLabel != null) convSkinLabel.visible = true;
		if (skinNameDisplay != null) skinNameDisplay.visible = true;
		if (saveConversationBtn != null) saveConversationBtn.visible = true;
		if (loadConversationBtn != null) loadConversationBtn.visible = true;
		if (testBtn != null) testBtn.visible = true;
		if (convMessagesPanelTitle != null) convMessagesPanelTitle.visible = true;
		if (messageList != null) messageList.visible = true;
		if (messageButtons != null) messageButtons.visible = true;
		if (addMessageBtn != null) addMessageBtn.visible = true;
		if (convEditPanelTitle != null) convEditPanelTitle.visible = true;
		if (convCharLabel != null) convCharLabel.visible = true;
		if (characterText != null) characterText.visible = true;
		if (convPortraitLabel != null) convPortraitLabel.visible = true;
		if (portraitNameInput != null) portraitNameInput.visible = true;
		if (convBoxLabel != null) convBoxLabel.visible = true;
		if (boxNameInput != null) boxNameInput.visible = true;
		if (convTextLabel != null) convTextLabel.visible = true;
		if (messageText != null) messageText.visible = true;
		if (convBubbleLabel != null) convBubbleLabel.visible = true;
		if (bubbleTypeText != null) bubbleTypeText.visible = true;
		if (convCycleBubbleBtn != null) convCycleBubbleBtn.visible = true;
		if (convSpeedLabel != null) convSpeedLabel.visible = true;
		if (speedText != null) speedText.visible = true;
		if (convMusicLabel != null) convMusicLabel.visible = true;
		if (musicInput != null) musicInput.visible = true;
		if (convUpdateBtn != null) convUpdateBtn.visible = true;
		if (removeMessageBtn != null) removeMessageBtn.visible = true;

		refreshConversationList();
	}

	// ========================================
	// TAB: SKIN
	// ========================================

	/**
	 * Crear tab de skin
	 */
	function createSkinTab():Void
	{
		var startY = 100;
		var leftX = PADDING;

		// === PANEL IZQUIERDO: LISTA DE SKINS ===
		skinPanelTitle = new FlxText(leftX, startY, PANEL_WIDTH, "AVAILABLE SKINS", 20);
		skinPanelTitle.setBorderStyle(OUTLINE, FlxColor.BLACK, 2);
		add(skinPanelTitle);
		startY += 30;

		skinList = new FlxTypedGroup<FlxText>();
		add(skinList);

		skinButtons = new FlxTypedGroup<CoolButton>();
		add(skinButtons);

		createSkinBtn = new CoolButton(leftX, FlxG.height - 120, "CREATE NEW SKIN", createNewSkin);
		createSkinBtn.resize(PANEL_WIDTH, 30);
		createSkinBtn.setLabelFormat(null, 8, FlxColor.BLACK);
		add(createSkinBtn);

		// === PANEL DERECHO: CONFIGURACIÓN DE SKIN ===
		startY = 100;
		var rightX = PANEL_WIDTH + PADDING * 2;
		var rightWidth = FlxG.width - rightX - PADDING;

		skinConfigTitle = new FlxText(rightX, startY, rightWidth, "SKIN CONFIGURATION", 20);
		skinConfigTitle.setBorderStyle(OUTLINE, FlxColor.BLACK, 2);
		add(skinConfigTitle);
		startY += 30;

		// Skin Name
		skinNameLabel = new FlxText(rightX, startY, rightWidth, "Skin Name:", 14);
		add(skinNameLabel);
		startY += 18;

		skinNameInput = createEditableText(rightX, startY, rightWidth - 20, currentSkinName, 14);
		add(skinNameInput);
		startY += 30;

		// Style
		skinStyleLabel = new FlxText(rightX, startY, rightWidth, "Style:", 14);
		add(skinStyleLabel);
		startY += 18;

		styleText = createEditableText(rightX, startY, 150, currentSkin.style);
		add(styleText);

		skinToggleStyleBtn = new CoolButton(rightX + 160, startY - 2, "TOGGLE", function()
		{
			currentSkin.style = (currentSkin.style == "pixel") ? "normal" : "pixel";
			styleText.text = currentSkin.style;
			// Actualizar color de fondo por defecto
			currentSkin.backgroundColor = DialogueData.getDefaultBackgroundColor(currentSkin.style);
			bgColorText.text = currentSkin.backgroundColor;
		});
		skinToggleStyleBtn.resize(120, 25);
		skinToggleStyleBtn.setLabelFormat(null, 12, FlxColor.BLACK);
		add(skinToggleStyleBtn);
		startY += 30;

		// Background Color
		skinBgColorLabel = new FlxText(rightX, startY, rightWidth, "Background Color:", 14);
		add(skinBgColorLabel);
		startY += 18;

		bgColorText = createEditableText(rightX, startY, rightWidth - 20, currentSkin.backgroundColor);
		add(bgColorText);
		startY += 35;

		// === TEXT CONFIGURATION ===
		skinTextConfigTitle = new FlxText(rightX, startY, rightWidth, "TEXT CONFIGURATION", 18);
		skinTextConfigTitle.setBorderStyle(OUTLINE, FlxColor.BLACK, 1);
		add(skinTextConfigTitle);
		startY += 25;

		// Position
		skinTextPosLabel = new FlxText(rightX, startY, rightWidth, "Position (X, Y):", 14);
		add(skinTextPosLabel);
		startY += 18;

		textXInput = createEditableText(rightX, startY, (rightWidth - 30) / 2, Std.string(currentSkin.textConfig.x ?? 240), 12);
		add(textXInput);

		textYInput = createEditableText(rightX + (rightWidth - 30) / 2 + 10, startY, (rightWidth - 30) / 2, Std.string(currentSkin.textConfig.y ?? 500), 12);
		add(textYInput);
		startY += 30;

		// Width & Size
		skinTextSizeLabel = new FlxText(rightX, startY, rightWidth, "Width, Size:", 14);
		add(skinTextSizeLabel);
		startY += 18;

		textWidthInput = createEditableText(rightX, startY, (rightWidth - 30) / 2, Std.string(currentSkin.textConfig.width ?? 800), 12);
		add(textWidthInput);

		textSizeInput = createEditableText(rightX + (rightWidth - 30) / 2 + 10, startY, (rightWidth - 30) / 2, Std.string(currentSkin.textConfig.size ?? 32), 12);
		add(textSizeInput);
		startY += 30;

		// Font
		skinTextFontLabel = new FlxText(rightX, startY, rightWidth, "Font:", 14);
		add(skinTextFontLabel);
		startY += 18;

		textFontInput = createEditableText(rightX, startY, rightWidth - 20, currentSkin.textConfig.font ?? "Pixel Arial 11 Bold", 12);
		add(textFontInput);
		startY += 30;

		// Color
		skinTextColorLabel = new FlxText(rightX, startY, rightWidth, "Color (hex):", 14);
		add(skinTextColorLabel);
		startY += 18;

		textColorInput = createEditableText(rightX, startY, rightWidth - 20, currentSkin.textConfig.color ?? "#3F2021", 12);
		add(textColorInput);
		startY += 35;

		// Botones
		var btnWidth = (rightWidth - 20) / 2;

		saveSkinBtn = new CoolButton(rightX, startY, "SAVE SKIN", saveSkin);
		saveSkinBtn.resize(Std.int(btnWidth), 30);
		saveSkinBtn.setLabelFormat(null, 8, FlxColor.BLACK);
		add(saveSkinBtn);

		loadSkinBtn = new CoolButton(rightX + btnWidth + 10, startY, "RELOAD SKIN", function()
		{
			loadSkin(currentSkinName);
		});
		loadSkinBtn.resize(Std.int(btnWidth), 30);
		loadSkinBtn.setLabelFormat(null, 8, FlxColor.BLACK);
		add(loadSkinBtn);

		refreshSkinList();
	}

	/**
	 * Mostrar tab de skin
	 */
	function showSkinTab():Void
	{
		if (skinPanelTitle != null) skinPanelTitle.visible = true;
		if (skinList != null) skinList.visible = true;
		if (skinButtons != null) skinButtons.visible = true;
		if (createSkinBtn != null) createSkinBtn.visible = true;
		if (skinConfigTitle != null) skinConfigTitle.visible = true;
		if (skinNameLabel != null) skinNameLabel.visible = true;
		if (skinNameInput != null) skinNameInput.visible = true;
		if (skinStyleLabel != null) skinStyleLabel.visible = true;
		if (styleText != null) styleText.visible = true;
		if (skinToggleStyleBtn != null) skinToggleStyleBtn.visible = true;
		if (skinBgColorLabel != null) skinBgColorLabel.visible = true;
		if (bgColorText != null) bgColorText.visible = true;
		if (skinTextConfigTitle != null) skinTextConfigTitle.visible = true;
		if (skinTextPosLabel != null) skinTextPosLabel.visible = true;
		if (textXInput != null) textXInput.visible = true;
		if (textYInput != null) textYInput.visible = true;
		if (skinTextSizeLabel != null) skinTextSizeLabel.visible = true;
		if (textWidthInput != null) textWidthInput.visible = true;
		if (textSizeInput != null) textSizeInput.visible = true;
		if (skinTextFontLabel != null) skinTextFontLabel.visible = true;
		if (textFontInput != null) textFontInput.visible = true;
		if (skinTextColorLabel != null) skinTextColorLabel.visible = true;
		if (textColorInput != null) textColorInput.visible = true;
		if (saveSkinBtn != null) saveSkinBtn.visible = true;
		if (loadSkinBtn != null) loadSkinBtn.visible = true;
	}

	// ========================================
	// TAB: PORTRAITS
	// ========================================

	/**
	 * Crear tab de portraits
	 */
	function createPortraitsTab():Void
	{
		var startY = 100;
		var leftX = PADDING;

		// === PANEL IZQUIERDO: LISTA DE PORTRAITS ===
		portraitsPanelTitle = new FlxText(leftX, startY, PANEL_WIDTH, "PORTRAITS", 20);
		portraitsPanelTitle.setBorderStyle(OUTLINE, FlxColor.BLACK, 2);
		add(portraitsPanelTitle);
		startY += 30;

		portraitList = new FlxTypedGroup<FlxText>();
		add(portraitList);

		portraitButtons = new FlxTypedGroup<CoolButton>();
		add(portraitButtons);

		importPortraitBtn = new CoolButton(leftX, FlxG.height - 160, "IMPORT FILE", importPortrait);
		importPortraitBtn.resize(PANEL_WIDTH, 30);
		importPortraitBtn.setLabelFormat(null, 8, FlxColor.BLACK);
		add(importPortraitBtn);

		addPortraitBtn = new CoolButton(leftX, FlxG.height - 120, "ADD CONFIG", addPortraitConfig);
		addPortraitBtn.resize(PANEL_WIDTH, 30);
		addPortraitBtn.setLabelFormat(null, 8, FlxColor.BLACK);
		add(addPortraitBtn);

		// === PANEL DERECHO: CONFIGURACIÓN DE PORTRAIT ===
		startY = 100;
		var rightX = PANEL_WIDTH + PADDING * 2;
		var rightWidth = FlxG.width - rightX - PADDING;

		portraitsConfigTitle = new FlxText(rightX, startY, rightWidth, "PORTRAIT CONFIG", 20);
		portraitsConfigTitle.setBorderStyle(OUTLINE, FlxColor.BLACK, 2);
		add(portraitsConfigTitle);
		startY += 30;

		// Name
		portraitsNameLabel = new FlxText(rightX, startY, rightWidth, "Config Name:", 14);
		add(portraitsNameLabel);
		startY += 18;

		portraitConfigNameInput = createEditableText(rightX, startY, rightWidth - 20, "", 14);
		add(portraitConfigNameInput);
		startY += 30;

		// Position
		portraitsPosLabel = new FlxText(rightX, startY, rightWidth, "Position (X, Y):", 14);
		add(portraitsPosLabel);
		startY += 18;

		portraitXInput = createEditableText(rightX, startY, (rightWidth - 30) / 2, "0", 12);
		add(portraitXInput);

		portraitYInput = createEditableText(rightX + (rightWidth - 30) / 2 + 10, startY, (rightWidth - 30) / 2, "0", 12);
		add(portraitYInput);
		startY += 30;

		// Scale
		portraitsScaleLabel = new FlxText(rightX, startY, rightWidth, "Scale (X, Y):", 14);
		add(portraitsScaleLabel);
		startY += 18;

		portraitScaleXInput = createEditableText(rightX, startY, (rightWidth - 30) / 2, "1.0", 12);
		add(portraitScaleXInput);

		portraitScaleYInput = createEditableText(rightX + (rightWidth - 30) / 2 + 10, startY, (rightWidth - 30) / 2, "1.0", 12);
		add(portraitScaleYInput);
		startY += 30;

		// Animation
		portraitsAnimLabel = new FlxText(rightX, startY, rightWidth, "Animation:", 14);
		add(portraitsAnimLabel);
		startY += 18;

		portraitAnimInput = createEditableText(rightX, startY, rightWidth - 20, "idle", 12);
		add(portraitAnimInput);
		startY += 35;

		// Botones
		var btnWidth = (rightWidth - 20) / 2;

		portraitsUpdateBtn = new CoolButton(rightX, startY, "UPDATE", updatePortraitConfig);
		portraitsUpdateBtn.resize(Std.int(btnWidth), 30);
		portraitsUpdateBtn.setLabelFormat(null, 8, FlxColor.BLACK);
		add(portraitsUpdateBtn);

		removePortraitBtn = new CoolButton(rightX + btnWidth + 10, startY, "REMOVE", removePortraitConfig);
		removePortraitBtn.resize(Std.int(btnWidth), 30);
		removePortraitBtn.setLabelFormat(null, 8, FlxColor.BLACK);
		add(removePortraitBtn);
	}

	/**
	 * Mostrar tab de portraits
	 */
	function showPortraitsTab():Void
	{
		if (portraitsPanelTitle != null) portraitsPanelTitle.visible = true;
		if (portraitList != null) portraitList.visible = true;
		if (portraitButtons != null) portraitButtons.visible = true;
		if (importPortraitBtn != null) importPortraitBtn.visible = true;
		if (addPortraitBtn != null) addPortraitBtn.visible = true;
		if (portraitsConfigTitle != null) portraitsConfigTitle.visible = true;
		if (portraitsNameLabel != null) portraitsNameLabel.visible = true;
		if (portraitConfigNameInput != null) portraitConfigNameInput.visible = true;
		if (portraitsPosLabel != null) portraitsPosLabel.visible = true;
		if (portraitXInput != null) portraitXInput.visible = true;
		if (portraitYInput != null) portraitYInput.visible = true;
		if (portraitsScaleLabel != null) portraitsScaleLabel.visible = true;
		if (portraitScaleXInput != null) portraitScaleXInput.visible = true;
		if (portraitScaleYInput != null) portraitScaleYInput.visible = true;
		if (portraitsAnimLabel != null) portraitsAnimLabel.visible = true;
		if (portraitAnimInput != null) portraitAnimInput.visible = true;
		if (portraitsUpdateBtn != null) portraitsUpdateBtn.visible = true;
		if (removePortraitBtn != null) removePortraitBtn.visible = true;

		refreshPortraitList();
	}

	// ========================================
	// TAB: BOXES
	// ========================================

	/**
	 * Crear tab de boxes
	 */
	function createBoxesTab():Void
	{
		var startY = 100;
		var leftX = PADDING;

		// === PANEL IZQUIERDO: LISTA DE BOXES ===
		boxesPanelTitle = new FlxText(leftX, startY, PANEL_WIDTH, "DIALOGUE BOXES", 20);
		boxesPanelTitle.setBorderStyle(OUTLINE, FlxColor.BLACK, 2);
		add(boxesPanelTitle);
		startY += 30;

		boxList = new FlxTypedGroup<FlxText>();
		add(boxList);

		boxButtons = new FlxTypedGroup<CoolButton>();
		add(boxButtons);

		importBoxBtn = new CoolButton(leftX, FlxG.height - 160, "IMPORT FILE", importBox);
		importBoxBtn.resize(PANEL_WIDTH, 30);
		importBoxBtn.setLabelFormat(null, 8, FlxColor.BLACK);
		add(importBoxBtn);

		addBoxBtn = new CoolButton(leftX, FlxG.height - 120, "ADD CONFIG", addBoxConfig);
		addBoxBtn.resize(PANEL_WIDTH, 30);
		addBoxBtn.setLabelFormat(null, 8, FlxColor.BLACK);
		add(addBoxBtn);

		// === PANEL DERECHO: CONFIGURACIÓN DE BOX ===
		startY = 100;
		var rightX = PANEL_WIDTH + PADDING * 2;
		var rightWidth = FlxG.width - rightX - PADDING;

		boxesConfigTitle = new FlxText(rightX, startY, rightWidth, "BOX CONFIG", 20);
		boxesConfigTitle.setBorderStyle(OUTLINE, FlxColor.BLACK, 2);
		add(boxesConfigTitle);
		startY += 30;

		// Name
		boxesNameLabel = new FlxText(rightX, startY, rightWidth, "Config Name:", 14);
		add(boxesNameLabel);
		startY += 18;

		boxConfigNameInput = createEditableText(rightX, startY, rightWidth - 20, "", 14);
		add(boxConfigNameInput);
		startY += 30;

		// Position
		boxesPosLabel = new FlxText(rightX, startY, rightWidth, "Position (X, Y):", 14);
		add(boxesPosLabel);
		startY += 18;

		boxXInput = createEditableText(rightX, startY, (rightWidth - 30) / 2, "0", 12);
		add(boxXInput);

		boxYInput = createEditableText(rightX + (rightWidth - 30) / 2 + 10, startY, (rightWidth - 30) / 2, "0", 12);
		add(boxYInput);
		startY += 30;

		// Scale
		boxesScaleLabel = new FlxText(rightX, startY, rightWidth, "Scale (X, Y):", 14);
		add(boxesScaleLabel);
		startY += 18;

		boxScaleXInput = createEditableText(rightX, startY, (rightWidth - 30) / 2, "1.0", 12);
		add(boxScaleXInput);

		boxScaleYInput = createEditableText(rightX + (rightWidth - 30) / 2 + 10, startY, (rightWidth - 30) / 2, "1.0", 12);
		add(boxScaleYInput);
		startY += 30;

		// Animation
		boxesAnimLabel = new FlxText(rightX, startY, rightWidth, "Animation:", 14);
		add(boxesAnimLabel);
		startY += 18;

		boxAnimInput = createEditableText(rightX, startY, rightWidth - 20, "normal", 12);
		add(boxAnimInput);
		startY += 35;

		// Botones
		var btnWidth = (rightWidth - 20) / 2;

		boxesUpdateBtn = new CoolButton(rightX, startY, "UPDATE", updateBoxConfig);
		boxesUpdateBtn.resize(Std.int(btnWidth), 30);
		boxesUpdateBtn.setLabelFormat(null, 8, FlxColor.BLACK);
		add(boxesUpdateBtn);

		removeBoxBtn = new CoolButton(rightX + btnWidth + 10, startY, "REMOVE", removeBoxConfig);
		removeBoxBtn.resize(Std.int(btnWidth), 30);
		removeBoxBtn.setLabelFormat(null, 8, FlxColor.BLACK);
		add(removeBoxBtn);
	}

	/**
	 * Mostrar tab de boxes
	 */
	function showBoxesTab():Void
	{
		if (boxesPanelTitle != null) boxesPanelTitle.visible = true;
		if (boxList != null) boxList.visible = true;
		if (boxButtons != null) boxButtons.visible = true;
		if (importBoxBtn != null) importBoxBtn.visible = true;
		if (addBoxBtn != null) addBoxBtn.visible = true;
		if (boxesConfigTitle != null) boxesConfigTitle.visible = true;
		if (boxesNameLabel != null) boxesNameLabel.visible = true;
		if (boxConfigNameInput != null) boxConfigNameInput.visible = true;
		if (boxesPosLabel != null) boxesPosLabel.visible = true;
		if (boxXInput != null) boxXInput.visible = true;
		if (boxYInput != null) boxYInput.visible = true;
		if (boxesScaleLabel != null) boxesScaleLabel.visible = true;
		if (boxScaleXInput != null) boxScaleXInput.visible = true;
		if (boxScaleYInput != null) boxScaleYInput.visible = true;
		if (boxesAnimLabel != null) boxesAnimLabel.visible = true;
		if (boxAnimInput != null) boxAnimInput.visible = true;
		if (boxesUpdateBtn != null) boxesUpdateBtn.visible = true;
		if (removeBoxBtn != null) removeBoxBtn.visible = true;

		refreshBoxList();
	}

	// ========================================
	// FUNCIONES DE CONVERSACIÓN
	// ========================================

	/**
	 * Crear texto editable
	 */
	function createEditableText(x:Float, y:Float, width:Float, initialText:String, ?size:Int = 14):CoolInputText
	{
		var inputText = new CoolInputText(x, y, Std.int(width), initialText, size, FlxColor.WHITE, 0x33FFFFFF);
		// inputText.setBorderStyle removed — CoolInputText uses FlxText display for styling
		inputText.focusGained = () -> inputText.color = FlxColor.YELLOW;
		inputText.focusLost = () -> inputText.color = FlxColor.WHITE;
		return inputText;
	}

	/**
	 * Refrescar lista de mensajes
	 */
	function refreshMessageList():Void
	{
		messageList.clear();
		messageButtons.clear();

		var startY = 140;
		var x = PANEL_WIDTH + PADDING * 2;

		for (i in 0...conversation.messages.length)
		{
			var msg = conversation.messages[i];
			var preview = msg.character + ": " + msg.text.substr(0, 25);
			if (msg.text.length > 25)
				preview += "...";

			var msgText = new FlxText(x, startY, PANEL_WIDTH - 60, preview, 12);
			msgText.color = (selectedMessageIndex == i) ? FlxColor.YELLOW : FlxColor.WHITE;
			messageList.add(msgText);

			var selectBtn = new CoolButton(x + PANEL_WIDTH - 50, startY - 2, "EDIT", function()
			{
				selectMessage(i);
			});
			selectBtn.resize(50, 20);
			selectBtn.setLabelFormat(null, 10, 0xFFFFFFFF);
			messageButtons.add(selectBtn);

			startY += 22;

			if (startY > FlxG.height - 150)
				break;
		}
	}

	/**
	 * Seleccionar mensaje para editar
	 */
	function selectMessage(index:Int):Void
	{
		selectedMessageIndex = index;
		var msg = conversation.messages[index];

		characterText.text = msg.character;
		messageText.text = msg.text;
		speedText.text = Std.string(msg.speed ?? 0.04);
		bubbleTypeText.text = msg.bubbleType ?? "normal";
		portraitNameInput.text = msg.portrait ?? "";
		boxNameInput.text = msg.boxSprite ?? "";
		musicInput.text = msg.music ?? "";

		refreshMessageList();
	}

	/**
	 * Agregar nuevo mensaje
	 */
	function addMessage():Void
	{
		_isDirty = true;
		conversation.messages.push({
			character: "dad",
			text: "New message",
			bubbleType: "normal",
			speed: 0.04,
			portrait: "",
			boxSprite: "",
			music: ""
		});

		selectedMessageIndex = conversation.messages.length - 1;
		selectMessage(selectedMessageIndex);
	}

	/**
	 * Actualizar mensaje actual
	 */
	function updateCurrentMessage():Void
	{
		if (selectedMessageIndex < 0 || selectedMessageIndex >= conversation.messages.length)
			return;

		_isDirty = true;
		var msg = conversation.messages[selectedMessageIndex];
		msg.character = characterText.text;
		msg.text = messageText.text;
		msg.bubbleType = bubbleTypeText.text;
		msg.speed = Std.parseFloat(speedText.text);
		msg.portrait = portraitNameInput.text != "" ? portraitNameInput.text : null;
		msg.boxSprite = boxNameInput.text != "" ? boxNameInput.text : null;
		msg.music = musicInput.text != "" ? musicInput.text : null;

		conversation.name = conversationNameInput.text;
		conversation.skinName = currentSkinName;

		refreshMessageList();
		showMessage("Message updated!", FlxColor.GREEN);
	}

	/**
	 * Eliminar mensaje
	 */
	function removeMessage():Void
	{
		if (selectedMessageIndex < 0 || selectedMessageIndex >= conversation.messages.length)
			return;

		_isDirty = true;
		conversation.messages.splice(selectedMessageIndex, 1);
		selectedMessageIndex = -1;

		characterText.text = "";
		messageText.text = "";
		speedText.text = "0.04";
		bubbleTypeText.text = "normal";
		portraitNameInput.text = "";
		boxNameInput.text = "";

		refreshMessageList();
		showMessage("Message removed!", FlxColor.ORANGE);
	}

	/**
	 * Guardar conversación
	 */
	function saveConversation():Void
	{
		conversation.name = conversationNameInput.text;
		conversation.skinName = currentSkinName;

		if (DialogueData.saveConversation(PlayState.SONG.song, conversation))
		{
			_isDirty = false;
			refreshConversationList();
			showMessage("Conversation saved!", FlxColor.GREEN);
		}
		else
		{
			showMessage("Save failed!", FlxColor.RED);
		}
	}

	/**
	 * Cargar conversación — usa el nombre del input como nombre de archivo.
	 * Ej: input "intro" → carga songs/<canción>/intro.json
	 */
	function loadConversation():Void
	{
		var convName = conversationNameInput.text.trim();
		if (convName == '')
		{
			showMessage("Enter a conversation name first!", FlxColor.ORANGE);
			return;
		}

		var loaded = DialogueData.loadConversation(PlayState.SONG.song, convName);

		if (loaded != null)
		{
			conversation = loaded;
			conversationNameInput.text = conversation.name;

			// Cargar la skin asociada
			if (conversation.skinName != null)
			{
				loadSkin(conversation.skinName);
			}

			selectedMessageIndex = -1;
			refreshMessageList();
			showMessage("Loaded: " + convName + ".json", FlxColor.GREEN);
		}
		else
		{
			showMessage("Not found: " + convName + ".json", FlxColor.RED);
		}
	}

	/**
	 * Refrescar la lista de archivos de diálogo disponibles para la canción actual.
	 */
	function refreshConversationList():Void
	{
		if (convFileList == null || convFileButtons == null)
			return;

		convFileList.clear();
		convFileButtons.clear();

		var files = DialogueData.listConversations(song);
		var startY = 290; // debajo del botón TEST + título
		var x = PADDING;

		for (convName in files)
		{
			var nameText = new FlxText(x, startY, PANEL_WIDTH - 80, convName + ".json", 12);
			nameText.color = (convName == conversation.name) ? FlxColor.YELLOW : FlxColor.WHITE;
			convFileList.add(nameText);

			var loadBtn = new CoolButton(x + PANEL_WIDTH - 70, startY - 2, "LOAD", function()
			{
				conversationNameInput.text = convName;
				loadConversation();
			});
			loadBtn.resize(70, 20);
			loadBtn.setLabelFormat(null, 10, 0xFFFFFFFF);
			convFileButtons.add(loadBtn);

			startY += 20;
			if (startY > FlxG.height - 100)
				break;
		}
	}

	/**
	 * Probar diálogo
	 */
	function testDialogue():Void
	{
		// Actualizar y guardar temporalmente
		conversation.name = conversationNameInput.text;
		conversation.skinName = currentSkinName;

		// Guardar skin y conversación
		DialogueData.saveSkin(currentSkinName, currentSkin);
		DialogueData.saveConversation(PlayState.SONG.song, conversation);

		// Crear preview
		if (previewBox != null)
		{
			remove(previewBox);
			previewBox.destroy();
		}

		previewBox = new DialogueBoxImproved(PlayState.SONG.song, conversation.name);
		previewBox.finishThing = function()
		{
			remove(previewBox);
			previewBox = null;
		};
		add(previewBox);
	}

	// ========================================
	// FUNCIONES DE SKIN
	// ========================================

	/**
	 * Refrescar lista de skins
	 */
	function refreshSkinList():Void
	{
		skinList.clear();
		skinButtons.clear();

		availableSkins = DialogueData.listSkins();

		var startY = 140;
		var x = PADDING;

		for (skinName in availableSkins)
		{
			var skinText = new FlxText(x, startY, PANEL_WIDTH - 80, skinName, 14);
			skinText.color = (skinName == currentSkinName) ? FlxColor.YELLOW : FlxColor.WHITE;
			skinList.add(skinText);

			var selectBtn = new CoolButton(x + PANEL_WIDTH - 70, startY - 2, "LOAD", function()
			{
				loadSkin(skinName);
			});
			selectBtn.resize(70, 20);
			selectBtn.setLabelFormat(null, 10, 0xFFFFFFFF);
			skinButtons.add(selectBtn);

			startY += 22;

			if (startY > FlxG.height - 180)
				break;
		}
	}

	/**
	 * Cargar skin
	 */
	function loadSkin(skinName:String):Void
	{
		var loaded = DialogueData.loadSkin(skinName);

		if (loaded != null)
		{
			currentSkinName = skinName;
			currentSkin = loaded;

			// Actualizar UI
			skinNameInput.text = currentSkin.name;
			styleText.text = currentSkin.style;
			bgColorText.text = currentSkin.backgroundColor ?? "#B3DFD8";

			if (currentSkin.textConfig != null)
			{
				textXInput.text = Std.string(currentSkin.textConfig.x ?? 240);
				textYInput.text = Std.string(currentSkin.textConfig.y ?? 500);
				textWidthInput.text = Std.string(currentSkin.textConfig.width ?? 800);
				textSizeInput.text = Std.string(currentSkin.textConfig.size ?? 32);
				textFontInput.text = currentSkin.textConfig.font ?? "Pixel Arial 11 Bold";
				textColorInput.text = currentSkin.textConfig.color ?? "#3F2021";
			}

			skinNameDisplay.text = currentSkinName;
			conversation.skinName = currentSkinName;

			refreshSkinList();
			refreshPortraitList();
			refreshBoxList();
			showMessage("Skin loaded: " + skinName, FlxColor.GREEN);
		}
		else
		{
			showMessage("Failed to load skin!", FlxColor.RED);
		}
	}

	/**
	 * Guardar skin
	 */
	function saveSkin():Void
	{
		if (currentSkin == null)
			return;

		// Actualizar configuración desde inputs
		currentSkin.name = skinNameInput.text;
		currentSkin.style = styleText.text;
		currentSkin.backgroundColor = bgColorText.text;

		if (currentSkin.textConfig == null)
			currentSkin.textConfig = {};

		currentSkin.textConfig.x = Std.parseFloat(textXInput.text);
		currentSkin.textConfig.y = Std.parseFloat(textYInput.text);
		currentSkin.textConfig.width = Std.parseInt(textWidthInput.text);
		currentSkin.textConfig.size = Std.parseInt(textSizeInput.text);
		currentSkin.textConfig.font = textFontInput.text;
		currentSkin.textConfig.color = textColorInput.text;

		// Guardar
		if (DialogueData.saveSkin(currentSkinName, currentSkin))
		{
			_isDirty = false;
			showMessage("Skin saved!", FlxColor.GREEN);
			refreshSkinList();
		}
		else
		{
			showMessage("Save failed!", FlxColor.RED);
		}
	}

	/**
	 * Crear nueva skin
	 */
	function createNewSkin():Void
	{
		var newName = "new_skin_" + Date.now().getTime();
		currentSkinName = newName;
		currentSkin = DialogueData.createEmptySkin(newName, "pixel");

		if (DialogueData.saveSkin(currentSkinName, currentSkin))
		{
			availableSkins.push(currentSkinName);
			loadSkin(currentSkinName);
			showMessage("New skin created!", FlxColor.GREEN);
		}
		else
		{
			showMessage("Failed to create skin!", FlxColor.RED);
		}
	}

	// ========================================
	// FUNCIONES DE PORTRAITS
	// ========================================

	/**
	 * Refrescar lista de portraits
	 */
	function refreshPortraitList():Void
	{
		if (portraitList == null || portraitButtons == null)
			return;

		portraitList.clear();
		portraitButtons.clear();

		if (currentSkin == null || currentSkin.portraits == null)
			return;

		var startY = 140;
		var x = PADDING;

		for (name in currentSkin.portraits.keys())
		{
			var config = currentSkin.portraits.get(name);

			var portraitText = new FlxText(x, startY, PANEL_WIDTH - 80, name, 12);
			portraitText.color = (name == selectedPortraitName) ? FlxColor.YELLOW : FlxColor.WHITE;
			portraitList.add(portraitText);

			var selectBtn = new CoolButton(x + PANEL_WIDTH - 70, startY - 2, "EDIT", function()
			{
				selectPortrait(name);
			});
			selectBtn.resize(70, 20);
			selectBtn.setLabelFormat(null, 10, 0xFFFFFFFF);
			portraitButtons.add(selectBtn);

			startY += 20;

			if (startY > FlxG.height - 200)
				break;
		}
	}

	/**
	 * Seleccionar portrait
	 */
	function selectPortrait(name:String):Void
	{
		selectedPortraitName = name;
		var config = currentSkin.portraits.get(name);

		if (config != null)
		{
			portraitConfigNameInput.text = config.name;
			portraitXInput.text = Std.string(config.x ?? 0);
			portraitYInput.text = Std.string(config.y ?? 0);
			portraitScaleXInput.text = Std.string(config.scaleX ?? 1.0);
			portraitScaleYInput.text = Std.string(config.scaleY ?? 1.0);
			portraitAnimInput.text = config.animation ?? "idle";
		}

		refreshPortraitList();
	}

	/**
	 * Importar portrait
	 */
	function importPortrait():Void
	{
		#if sys
		var _fdDlg1 = new FileDialog();
		_fdDlg1.onSelect.add(function(path:String)
		{
			var fileName = haxe.io.Path.withoutDirectory(path);

			if (DialogueData.copyPortraitToSkin(path, currentSkinName, fileName))
			{
				var configName = "portrait_" + haxe.io.Path.withoutExtension(fileName);
				var config = DialogueData.createPortraitConfig(configName, fileName);
				currentSkin.portraits.set(configName, config);

				saveSkin();
				refreshPortraitList();
				showMessage("Portrait imported!", FlxColor.GREEN);
			}
			else
			{
				showMessage("Import failed!", FlxColor.RED);
			}
		});
		_fdDlg1.browse(OPEN, "png;jpg;jpeg", null, "Images");
		#else
		showMessage("File import not supported on this platform", FlxColor.ORANGE);
		#end
	}

	/**
	 * Agregar configuración de portrait
	 */
	function addPortraitConfig():Void
	{
		var newName = "portrait_" + (Lambda.count(currentSkin.portraits) + 1);
		var config = DialogueData.createPortraitConfig(newName, "placeholder.png");
		currentSkin.portraits.set(newName, config);

		refreshPortraitList();
		selectPortrait(newName);
		showMessage("Portrait config added!", FlxColor.GREEN);
	}

	/**
	 * Actualizar configuración de portrait
	 */
	function updatePortraitConfig():Void
	{
		if (selectedPortraitName == null)
			return;

		var config = currentSkin.portraits.get(selectedPortraitName);
		if (config == null)
			return;

		config.x = Std.parseFloat(portraitXInput.text);
		config.y = Std.parseFloat(portraitYInput.text);
		config.scaleX = Std.parseFloat(portraitScaleXInput.text);
		config.scaleY = Std.parseFloat(portraitScaleYInput.text);
		config.animation = portraitAnimInput.text;

		// Si cambió el nombre, actualizar key en el Map
		var newName = portraitConfigNameInput.text;
		if (newName != selectedPortraitName)
		{
			currentSkin.portraits.remove(selectedPortraitName);
			config.name = newName;
			currentSkin.portraits.set(newName, config);
			selectedPortraitName = newName;
		}

		refreshPortraitList();
		showMessage("Portrait updated!", FlxColor.GREEN);
	}

	/**
	 * Eliminar configuración de portrait
	 */
	function removePortraitConfig():Void
	{
		if (selectedPortraitName == null)
			return;

		currentSkin.portraits.remove(selectedPortraitName);
		selectedPortraitName = null;

		portraitConfigNameInput.text = "";
		portraitXInput.text = "0";
		portraitYInput.text = "0";
		portraitScaleXInput.text = "1.0";
		portraitScaleYInput.text = "1.0";
		portraitAnimInput.text = "idle";

		refreshPortraitList();
		showMessage("Portrait removed!", FlxColor.ORANGE);
	}

	// ========================================
	// FUNCIONES DE BOXES
	// ========================================

	/**
	 * Refrescar lista de boxes
	 */
	function refreshBoxList():Void
	{
		if (boxList == null || boxButtons == null)
			return;

		boxList.clear();
		boxButtons.clear();

		if (currentSkin == null || currentSkin.boxes == null)
			return;

		var startY = 140;
		var x = PADDING;

		for (name in currentSkin.boxes.keys())
		{
			var config = currentSkin.boxes.get(name);

			var boxText = new FlxText(x, startY, PANEL_WIDTH - 80, name, 12);
			boxText.color = (name == selectedBoxName) ? FlxColor.YELLOW : FlxColor.WHITE;
			boxList.add(boxText);

			var selectBtn = new CoolButton(x + PANEL_WIDTH - 70, startY - 2, "EDIT", function()
			{
				selectBox(name);
			});
			selectBtn.resize(70, 20);
			selectBtn.setLabelFormat(null, 10, 0xFFFFFFFF);
			boxButtons.add(selectBtn);

			startY += 20;

			if (startY > FlxG.height - 200)
				break;
		}
	}

	/**
	 * Seleccionar box
	 */
	function selectBox(name:String):Void
	{
		selectedBoxName = name;
		var config = currentSkin.boxes.get(name);

		if (config != null)
		{
			boxConfigNameInput.text = config.name;
			boxXInput.text = Std.string(config.x ?? 0);
			boxYInput.text = Std.string(config.y ?? 0);
			boxScaleXInput.text = Std.string(config.scaleX ?? 1.0);
			boxScaleYInput.text = Std.string(config.scaleY ?? 1.0);
			boxAnimInput.text = config.animation ?? "normal";
		}

		refreshBoxList();
	}

	/**
	 * Importar box
	 */
	function importBox():Void
	{
		#if sys
		var _fdDlg2 = new FileDialog();
		_fdDlg2.onSelect.add(function(path:String)
		{
			var fileName = haxe.io.Path.withoutDirectory(path);

			if (DialogueData.copyBoxToSkin(path, currentSkinName, fileName))
			{
				var configName = "box_" + haxe.io.Path.withoutExtension(fileName);
				var config = DialogueData.createBoxConfig(configName, fileName);
				currentSkin.boxes.set(configName, config);

				saveSkin();
				refreshBoxList();
				showMessage("Box imported!", FlxColor.GREEN);
			}
			else
			{
				showMessage("Import failed!", FlxColor.RED);
			}
		});
		_fdDlg2.browse(OPEN, "png;jpg;jpeg", null, "Images");
		#else
		showMessage("File import not supported on this platform", FlxColor.ORANGE);
		#end
	}

	/**
	 * Agregar configuración de box
	 */
	function addBoxConfig():Void
	{
		var newName = "box_" + (Lambda.count(currentSkin.boxes) + 1);
		var config = DialogueData.createBoxConfig(newName, "placeholder.png");
		currentSkin.boxes.set(newName, config);

		refreshBoxList();
		selectBox(newName);
		showMessage("Box config added!", FlxColor.GREEN);
	}

	/**
	 * Actualizar configuración de box
	 */
	function updateBoxConfig():Void
	{
		if (selectedBoxName == null)
			return;

		var config = currentSkin.boxes.get(selectedBoxName);
		if (config == null)
			return;

		config.x = Std.parseFloat(boxXInput.text);
		config.y = Std.parseFloat(boxYInput.text);
		config.scaleX = Std.parseFloat(boxScaleXInput.text);
		config.scaleY = Std.parseFloat(boxScaleYInput.text);
		config.animation = boxAnimInput.text;

		// Si cambió el nombre, actualizar key en el Map
		var newName = boxConfigNameInput.text;
		if (newName != selectedBoxName)
		{
			currentSkin.boxes.remove(selectedBoxName);
			config.name = newName;
			currentSkin.boxes.set(newName, config);
			selectedBoxName = newName;
		}

		refreshBoxList();
		showMessage("Box updated!", FlxColor.GREEN);
	}

	/**
	 * Eliminar configuración de box
	 */
	function removeBoxConfig():Void
	{
		if (selectedBoxName == null)
			return;

		currentSkin.boxes.remove(selectedBoxName);
		selectedBoxName = null;

		boxConfigNameInput.text = "";
		boxXInput.text = "0";
		boxYInput.text = "0";
		boxScaleXInput.text = "1.0";
		boxScaleYInput.text = "1.0";
		boxAnimInput.text = "normal";

		refreshBoxList();
		showMessage("Box removed!", FlxColor.ORANGE);
	}

	// ========================================
	// UTILIDADES
	// ========================================

	/**
	 * Mostrar mensaje temporal
	 */
	function showMessage(msg:String, color:FlxColor):Void
	{
		var messageText = new FlxText(0, FlxG.height / 2, FlxG.width, msg, 32);
		messageText.alignment = CENTER;
		messageText.color = color;
		messageText.setBorderStyle(OUTLINE, FlxColor.BLACK, 3);
		add(messageText);

		new flixel.util.FlxTimer().start(1.5, function(tmr)
		{
			remove(messageText);
		});
	}

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// Atajos de teclado
		if (FlxG.keys.justPressed.ESCAPE)
		{
			if (_unsavedDlg == null)
			{
				if (_isDirty)
				{
					_unsavedDlg = new UnsavedChangesDialog();
					// No dedicated HUD cam — use default cameras
					_unsavedDlg.onSaveAndExit = () -> {
						if (currentTab == CONVERSATION) saveConversation(); else saveSkin();
						funkin.system.CursorManager.hide();
						StateTransition.switchState(new funkin.menus.FreeplayState());
					};
					_unsavedDlg.onSave = () -> {
						if (currentTab == CONVERSATION) saveConversation(); else saveSkin();
						remove(_unsavedDlg); _unsavedDlg = null;
					};
					_unsavedDlg.onExit = () -> {
						funkin.system.CursorManager.hide();
						StateTransition.switchState(new funkin.menus.FreeplayState());
					};
					add(_unsavedDlg);
				}
				else
				{
					funkin.system.CursorManager.hide();
					StateTransition.switchState(new funkin.menus.FreeplayState());
				}
			}
		}

		// Evitar shortcuts si hay focus en inputs
		if (conversationNameInput != null && conversationNameInput.hasFocus)
			return;
		if (messageText != null && messageText.hasFocus)
			return;

		if (FlxG.keys.pressed.CONTROL)
		{
			if (FlxG.keys.justPressed.S)
			{
				if (currentTab == CONVERSATION)
					saveConversation();
				else if (currentTab == SKIN)
					saveSkin();
			}

			if (FlxG.keys.justPressed.T)
			{
				testDialogue();
			}

			if (FlxG.keys.justPressed.N && currentTab == CONVERSATION)
			{
				addMessage();
			}
		}
	}

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

/**
 * Tabs del editor
 */
enum EditorTab
{
	CONVERSATION;
	SKIN;
	PORTRAITS;
	BOXES;
}
