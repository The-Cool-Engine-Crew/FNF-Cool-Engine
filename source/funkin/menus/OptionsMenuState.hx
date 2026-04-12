package funkin.menus;

#if desktop
import data.Discord.DiscordClient;
#end
import funkin.scripting.StateScriptHandler;
import funkin.gameplay.controls.CustomControlsState;
import funkin.gameplay.notes.NoteSkinOptions;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.FlxG;
import flixel.input.gamepad.FlxGamepadInputID;
import funkin.transitions.StateTransition;
import flixel.FlxSprite;
import flixel.FlxSubState;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import funkin.data.CoolUtil;
import funkin.gameplay.PlayState;
import funkin.states.MusicBeatState;
import funkin.states.MusicBeatSubstate;
import funkin.menus.MainMenuState;
import funkin.audio.MusicManager;
import data.PlayerSettings;
import openfl.Lib;
import funkin.data.SaveData;
import funkin.shaders.MenuBGShader;
import funkin.shaders.ScrollingGridShader;

using StringTools;

/**
 * Options Menu - Sistema de tabs integrado con keybinds
 * EXTENSIBLE: Usa StateScriptHandler para opciones dinámicas
 */
class OptionsMenuState extends MusicBeatSubstate
{
	// Categorías principales (se pueden agregar más desde scripts)
	#if mobileC
	var categories:Array<String> = ['General', 'Graphics', 'Gameplay', 'Subtitles', 'Note Skin', 'Offset', 'Mobile'];
	#else
	var categories:Array<String> = [
		'General',
		'Graphics',
		'Gameplay',
		'Subtitles',
		'Controls',
		'Note Skin',
		'Offset'
	];
	#end

	// ── FPS Cap — rango 30–240 en pasos de 5, luego Unlimited (0) ──────────────
	static inline final FPS_MIN:Int = 30;
	static inline final FPS_MAX:Int = 240;
	static inline final FPS_STEP:Int = 5;

	/** Devuelve el valor actual guardado (0 = Unlimited, default 60). */
	static function _getCurrentFPS():Int
	{
		return SaveData.data.fpsTarget != null ? Std.int(SaveData.data.fpsTarget) : 60;
	}

	/** Siguiente valor al pulsar → (Right/Toggle): sube 5, al llegar a 240 pasa a Unlimited,
		desde Unlimited vuelve a 30. */
	static function _nextFPS(current:Int):Int
	{
		if (current <= 0)
			return FPS_MIN; // Unlimited → 30
		if (current >= FPS_MAX)
			return 0; // 240 → Unlimited
		// Redondear al múltiplo de 5 más cercano por encima
		final snapped = Math.ceil(current / FPS_STEP) * FPS_STEP;
		final next = (snapped == current) ? current + FPS_STEP : snapped;
		return next > FPS_MAX ? 0 : next;
	}

	/** Anterior valor al pulsar ←: baja 5, desde 30 pasa a Unlimited. */
	static function _prevFPS(current:Int):Int
	{
		if (current <= 0)
			return FPS_MAX; // Unlimited → 240
		if (current <= FPS_MIN)
			return 0; // 30 → Unlimited
		final snapped = Math.floor(current / FPS_STEP) * FPS_STEP;
		final prev = (snapped == current) ? current - FPS_STEP : snapped;
		return prev < FPS_MIN ? 0 : prev;
	}

	var curCategory:Int = 0;

	// UI Elements
	var menuBG:FlxSprite;
	var categoryTexts:FlxTypedGroup<FlxText>;
	var contentPanel:FlxTypedGroup<FlxSprite>;

	// Current tab content
	var optionNames:FlxTypedGroup<FlxText>;
	var optionValues:FlxTypedGroup<FlxText>;
	var curSelected:Int = 0;
	var currentOptions:Array<Dynamic> = [];

	// ── Scroll de opciones ────────────────────────────────────────────────
	// Desplazamiento vertical en píxeles para cuando hay más opciones que espacio
	var _optScrollY:Float = 0.0;

	// Área visible de opciones: desde startY hasta el footer
	static inline var OPT_START_Y:Int = 180;
	static inline var OPT_SPACING:Int = 55;
	static inline var OPT_VISIBLE_H:Int = 370; // FlxG.height(720) - footer(100) - startY(180) - margen(70)

	// ── Scrollbar ─────────────────────────────────────────────────────────
	var _scrollbarTrack:FlxSprite = null; // barra gris de fondo
	var _scrollbarThumb:FlxSprite = null; // barra blanca indicadora

	static inline var SCROLLBAR_W:Int = 6;
	static var SCROLLBAR_X:Int = FlxG.width - 58; // pegado al borde derecho del panel

	// Keybind state
	var bindingState:String = "select"; // "select", "binding", "editing"
	var tempKey:String = "";
	var keyBindNames:Array<String> = [
		"LEFT",
		"DOWN",
		"UP",
		"RIGHT",
		"RESET",
		"ACCEPT",
		"BACK",
		"PAUSE",
		"SCREENSHOT",
		"CHEAT"
	];
	var defaultKeys:Array<String> = ["A", "S", "W", "D", "R", "ENTER", "ESCAPE", "ENTER", "F12", "SEVEN"];
	var blacklistKeys:Array<String> = ["SPACE"];
	// Teclas que solo pueden usarse en ciertos controles:
	var reservedKeys:Array<String> = ["ESCAPE", "ENTER", "BACKSPACE"]; // solo para ACCEPT/BACK/PAUSE
	var keys:Array<String> = [];

	// ── Edit mode (opciones multi-valor: ENTER entra, A/D cambia, ENTER/ESC sale) ──
	var _editMode:Bool = false;
	var _editModeIndicator:flixel.text.FlxText;

	// ── Flechas de scroll ─────────────────────────────────────────────────────
	var _scrollArrowUp:flixel.text.FlxText;
	var _scrollArrowDown:flixel.text.FlxText;

	// ── Touch input (only mobileC) ────────────────────────────────────────────
	#if mobileC
	var _touchStartX:Float  = 0;
	var _touchStartY:Float  = 0;
	var _touchPrevY:Float   = 0;
	var _touchIsDrag:Bool   = false;
	var _touchIsScroll:Bool = false;
	#end

	var warningText:FlxText;
	var bindingIndicator:FlxText;

	public static var fromPause:Bool = false;

	/**
	 * Guard de input: permanece true hasta que todas las teclas de ACCEPT
	 * se hayan soltado al menos un frame. Evita que el ENTER/SPACE usado
	 * para abrir el menú dispare una acción en el primer frame.
	 */
	var _inputGuard:Bool = true;

	/** Si se cambia una opción que requiere restart mientras en pausa, este flag
	 *  le indica a PauseSubState que dispare el rewind al volver. */
	public static var pendingRewind:Bool = false;

	public static var isOpenOptions:Bool = false;

	/**
	 * BUG FIX #7: caché estático del bitmap del fondo del menú.
	 * La primera apertura llamaba BitmapData.fromFile() síncronamente
	 * (lectura de disco + decodificación de PNG en el main thread) causando
	 * un freeze visible de ~300-500ms. Con el caché, las aperturas siguientes
	 * son instantáneas y la primera solo paga el costo una vez por sesión.
	 */
	/** Nulleado por ModSelectorState al cambiar de mod para forzar recarga del BG. */
	public static var _cachedMenuBG:openfl.display.BitmapData = null;

	// ── Controller icon atlas ─────────────────────────────────────────────────

	/** Currently detected gamepad style: "ps" | "xbox" | "switch" | null (keyboard) */
	var _gamepadStyle:Null<String> = null;

	// ── Fondo del menú (no-pause) con shader de colorización ─────────────────

	/** Sprite que muestra el menuBG con el shader aplicado (solo si !fromPause). */
	var bgSprite:FlxSprite = null;

	/** Shader de colorización del fondo. */
	var _bgMenuShader:MenuBGShader = null;

	/** Paleta de colores: misma que MainMenuState para coherencia visual. */
	static final OPT_PALETTE:Array<Array<Float>> = [
		[1.00, 0.41, 0.71], // Rosa  #FF69B4
		[0.61, 0.19, 1.00], // Morado #9B30FF
		[0.20, 0.80, 1.00], // Cian  #33CCFF
		[0.20, 1.00, 0.60], // Verde neón #33FF99
		[1.00, 0.55, 0.10], // Naranja #FF8C19
	];

	var _optPaletteIdx:Int = 0;
	var _optColorTimer:Float = 0;
	var _optColorTween:FlxTween = null;

	static inline final OPT_COLOR_HOLD:Float = 4.0;
	static inline final OPT_COLOR_TRANS:Float = 1.2;

	// ── Grid de pausa ─────────────────────────────────────────────────────────

	/** Sprite pantalla-completa con el shader de grid (solo si fromPause). */
	var _pauseGrid:FlxSprite = null;

	/** Shader de grid scrolling. */
	var _gridShader:ScrollingGridShader = null;

	/** Frames atlas for the detected gamepad. Loaded once, reused. */
	var _gamepadAtlas:Null<flixel.graphics.frames.FlxAtlasFrames> = null;

	/** Sprite pool for controller button icons (reused across rebuilds). */
	var _buttonIcons:FlxTypedGroup<FlxSprite> = null;

	// ── Checkbox atlas ────────────────────────────────────────────────────────

	/** Sprite pool for boolean checkboxes (reused across rebuilds). */
	var _checkboxSprites:FlxTypedGroup<FlxSprite> = null;

	/** Sparrow atlas frames for the checks sprite. */
	var _checksAtlas:Null<flixel.graphics.frames.FlxAtlasFrames> = null;

	var isCheck = false;

	override function create()
	{
		#if HSCRIPT_ALLOWED
		StateScriptHandler.init();
		StateScriptHandler.loadStateScripts('OptionsMenuState', this);

		if (fromPause)
			isOpenOptions = true;

		// Cargar categorías custom desde scripts
		loadCustomCategoriesFromScripts();
		StateScriptHandler.callOnScripts('onCreate', []);
		#end

		#if desktop
		DiscordClient.changePresence("Options Menu", null);
		#end

		if (!OptionsMenuState.fromPause)
			MusicManager.play('configurator', 0.7);

		// Inicializar keybinds
		loadKeyBinds();

		// ── Background según modo ─────────────────────────────────────────────
		if (fromPause)
		{
			// PAUSA: grid scrolling que se mueve de izquierda a derecha
			_gridShader = new ScrollingGridShader();
			_pauseGrid = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0x00000000);
			_pauseGrid.shader = _gridShader;
			_pauseGrid.scrollFactor.set();
			_pauseGrid.alpha = 0;
			add(_pauseGrid);
			FlxTween.tween(_pauseGrid, {alpha: 1.0}, 0.5, {ease: FlxEase.quartInOut});
		}
		else
		{
			// MENÚ NORMAL: menuBG con shader de colorización
			_bgMenuShader = new MenuBGShader();
			// BUG FIX #7: usar caché estático — evita leer el PNG del disco
			// cada vez que se abre el menú (primera apertura era ~300-500ms).
			if (_cachedMenuBG == null)
				_cachedMenuBG = openfl.display.BitmapData.fromFile(Paths.image('menu/menuBG'));
			bgSprite = new FlxSprite().loadGraphic(_cachedMenuBG);
			var bgScale:Float = Math.max(FlxG.width / bgSprite.width, FlxG.height / bgSprite.height) * 1.05;
			bgSprite.scale.set(bgScale, bgScale);
			bgSprite.updateHitbox();
			bgSprite.screenCenter();
			bgSprite.scrollFactor.set();
			bgSprite.antialiasing = SaveData.data.antialiasing;

			// Arrancar con primer color
			_bgMenuShader.setColorA(OPT_PALETTE[0][0], OPT_PALETTE[0][1], OPT_PALETTE[0][2]);
			_bgMenuShader.setColorB(OPT_PALETTE[1][0], OPT_PALETTE[1][1], OPT_PALETTE[1][2]);
			_bgMenuShader.setBlend(0.0);
			bgSprite.shader = _bgMenuShader;
			add(bgSprite);

			// Overlay oscuro encima para que el panel sea legible
			var bgOverlay:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
			bgOverlay.alpha = 0.55;
			bgOverlay.scrollFactor.set();
			add(bgOverlay);
		}

		// Borde del panel (agregar primero para que esté detrás)
		var borderThickness = 3;
		var panelBorder = new FlxSprite(50 - borderThickness,
			80 - borderThickness).makeGraphic(Std.int(FlxG.width - 100 + borderThickness * 2), Std.int(FlxG.height - 160 + borderThickness * 2), 0xFF2a2a2a);
		panelBorder.scrollFactor.set();
		add(panelBorder);

		// Panel principal con borde
		menuBG = new FlxSprite(50, 80).makeGraphic(FlxG.width - 100, FlxG.height - 160, 0xFF0a0a0a);
		menuBG.scrollFactor.set();
		add(menuBG);

		// Título del menú
		var titleText = new FlxText(0, 20, FlxG.width, "OPTIONS MENU", 48);
		titleText.setFormat(Paths.font("Funkin.otf"), 48, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		titleText.borderSize = 3;
		titleText.scrollFactor.set();
		titleText.antialiasing = SaveData.data.antialiasing;
		add(titleText);

		// Crear contentPanel ANTES de usarlo
		contentPanel = new FlxTypedGroup<FlxSprite>();
		add(contentPanel);

		// Categorías en la parte superior con backgrounds individuales
		categoryTexts = new FlxTypedGroup<FlxText>();
		add(categoryTexts);

		var categoryWidth = (FlxG.width - 120) / categories.length;
		var tabHeight = 40;
		var tabY = 85;

		for (i in 0...categories.length)
		{
			// Background de la pestaña (inicialmente inactiva)
			var tabBG = new FlxSprite(60 + (i * categoryWidth), tabY).makeGraphic(Std.int(categoryWidth - 4), tabHeight, 0xFF1a1a1a);
			tabBG.scrollFactor.set();
			tabBG.ID = i;
			contentPanel.add(tabBG);

			// Borde superior de la pestaña
			var tabBorder = new FlxSprite(tabBG.x, tabBG.y - 2).makeGraphic(Std.int(tabBG.width), 2, 0xFF444444);
			tabBorder.scrollFactor.set();
			tabBorder.ID = i;
			contentPanel.add(tabBorder);

			var categoryText:FlxText = new FlxText(60 + (i * categoryWidth), tabY + 8, categoryWidth, categories[i], 24);
			categoryText.setFormat(Paths.font("Funkin.otf"), 22, 0xFF888888, CENTER, OUTLINE, FlxColor.BLACK);
			categoryText.borderSize = 2;
			categoryText.antialiasing = SaveData.data.antialiasing;
			categoryText.ID = i;
			categoryText.scrollFactor.set();
			categoryTexts.add(categoryText);
		}

		// Separador horizontal entre pestañas y contenido
		var separator = new FlxSprite(menuBG.x, tabY + tabHeight).makeGraphic(Std.int(menuBG.width), 3, 0xFF444444);
		separator.scrollFactor.set();
		add(separator);

		// Indicador de pestaña activa (barra inferior)
		var activeIndicator = new FlxSprite(0, tabY + tabHeight - 3).makeGraphic(Std.int(categoryWidth - 4), 3, FlxColor.CYAN);
		activeIndicator.scrollFactor.set();
		activeIndicator.ID = -1; // ID especial para el indicador
		contentPanel.add(activeIndicator);

		optionNames = new FlxTypedGroup<FlxText>();
		add(optionNames);

		optionValues = new FlxTypedGroup<FlxText>();
		add(optionValues);

		// Button-icon and checkbox sprite pools (drawn on top of value texts)
		_buttonIcons = new FlxTypedGroup<FlxSprite>();
		_checkboxSprites = new FlxTypedGroup<FlxSprite>();
		add(_buttonIcons);
		add(_checkboxSprites);

		// Detect connected gamepad style once
		_gamepadStyle = _detectGamepadStyle();
		_gamepadAtlas = _loadGamepadAtlas(_gamepadStyle);

		// BUGFIX: refrescar iconos/estilo cuando el jugador conecta un mando
		// en caliente mientras el menú ya está abierto.
		FlxG.gamepads.deviceConnected.add(_onGamepadConnectedInMenu);
		FlxG.gamepads.deviceDisconnected.add(_onGamepadDisconnectedInMenu);

		// Load checks Sparrow atlas (PNG + XML required)
		try
		{
			#if sys
			if (sys.FileSystem.exists('assets/images/menu/options/checks.png')
				&& sys.FileSystem.exists('assets/images/menu/options/checks.xml'))
			#end
			_checksAtlas = Paths.getSparrowAtlas('menu/options/checks');
		}
		catch (_)
		{
			_checksAtlas = null;
		}

		// Warning text para keybinds
		warningText = new FlxText(0, 140, FlxG.width, "", 20);
		warningText.setFormat(Paths.font("Funkin.otf"), 20, FlxColor.RED, CENTER, OUTLINE, FlxColor.BLACK);
		warningText.borderSize = 2;
		warningText.antialiasing = SaveData.data.antialiasing;
		warningText.alpha = 0;
		warningText.scrollFactor.set();
		add(warningText);

		// Binding indicator
		bindingIndicator = new FlxText(0, FlxG.height - 120, FlxG.width, "", 22);
		bindingIndicator.setFormat(Paths.font("Funkin.otf"), 22, FlxColor.YELLOW, CENTER, OUTLINE, FlxColor.BLACK);
		bindingIndicator.borderSize = 2;
		bindingIndicator.visible = false;
		bindingIndicator.antialiasing = SaveData.data.antialiasing;
		bindingIndicator.scrollFactor.set();
		add(bindingIndicator);

		// Footer con ayuda de controles
		var footerBG = new FlxSprite(menuBG.x, FlxG.height - 100).makeGraphic(Std.int(menuBG.width), 50, 0xFF1a1a1a);
		footerBG.scrollFactor.set();
		add(footerBG);

		var footerBorder = new FlxSprite(footerBG.x, footerBG.y).makeGraphic(Std.int(footerBG.width), 2, 0xFF444444);
		footerBorder.scrollFactor.set();
		add(footerBorder);

		var helpText = new FlxText(footerBG.x + 20, footerBG.y + 12, footerBG.width - 40,
			#if mobileC
			"TAP Section: Change Section  |  TAP: Select  |  TAP 2x: Activate  |  SLIDE UP/DOWN: scroll  |  SLIDE L/R: Section  |  TAP Title/Footage: return",
			#else
			"LEFT/RIGHT : Tab  |  UP/DOWN : Navigate  |  ENTER : Toggle/Edit  |  A/D : Adjust  |  ESC : Back",
			#end
			18);
		helpText.setFormat(Paths.font("Funkin.otf"), 18, 0xFFAAAAAA, CENTER, OUTLINE, FlxColor.BLACK);
		helpText.borderSize = 1.5;
		helpText.antialiasing = SaveData.data.antialiasing;
		helpText.scrollFactor.set();
		add(helpText);

		// ── Edit mode indicator ────────────────────────────────────────────────
		_editModeIndicator = new FlxText(0, footerBG.y - 32, FlxG.width, "", 20);
		_editModeIndicator.setFormat(Paths.font("Funkin.otf"), 20, FlxColor.LIME, CENTER, OUTLINE, FlxColor.BLACK);
		_editModeIndicator.borderSize = 2;
		_editModeIndicator.visible = false;
		_editModeIndicator.antialiasing = SaveData.data.antialiasing;
		_editModeIndicator.scrollFactor.set();
		add(_editModeIndicator);

		// ── Flechas de scroll ──────────────────────────────────────────────────
		_scrollArrowUp = new FlxText(0, OPT_START_Y - 28, FlxG.width, "▲  More Options Up", 18);
		_scrollArrowUp.setFormat(Paths.font("Funkin.otf"), 18, 0xFF888888, CENTER, NONE);
		_scrollArrowUp.visible = false;
		_scrollArrowUp.antialiasing = SaveData.data.antialiasing;
		_scrollArrowUp.scrollFactor.set();
		add(_scrollArrowUp);

		_scrollArrowDown = new FlxText(0, OPT_START_Y + OPT_VISIBLE_H + 4, FlxG.width, "▼  More Options Down", 18);
		_scrollArrowDown.setFormat(Paths.font("Funkin.otf"), 18, 0xFF888888, CENTER, NONE);
		_scrollArrowDown.visible = false;
		_scrollArrowDown.antialiasing = SaveData.data.antialiasing;
		_scrollArrowDown.scrollFactor.set();
		add(_scrollArrowDown);

		// ── Scrollbar ─────────────────────────────────────────────────────────
		_scrollbarTrack = new FlxSprite(SCROLLBAR_X, OPT_START_Y).makeGraphic(SCROLLBAR_W, OPT_VISIBLE_H, 0xFF222222);
		_scrollbarTrack.scrollFactor.set();
		_scrollbarTrack.visible = false;
		add(_scrollbarTrack);

		_scrollbarThumb = new FlxSprite(SCROLLBAR_X, OPT_START_Y).makeGraphic(SCROLLBAR_W, 40, 0xFFFFFFFF);
		_scrollbarThumb.scrollFactor.set();
		_scrollbarThumb.visible = false;
		add(_scrollbarThumb);

		loadCategory(curCategory);

		// Configurar cámaras si se abre desde pause menu
		if (fromPause)
		{
			cameras = [FlxG.cameras.list[FlxG.cameras.list.length - 1]];
		}

		super.create();

		#if HSCRIPT_ALLOWED
		StateScriptHandler.refreshStateFields(this);
		StateScriptHandler.callOnScripts('postCreate', []);
		#end
	}

	#if mobileC
	/**
	 * Manage touch input according to the help prompts:
	 * TAP section: Change tab | TAP: Select | TAP 2x: Activate
	 * SWIPE UP/DOWN: Scroll | SWIPE L/R: Change tab | TAP Title/Footage: Back
	 */
	function handleTouchInput():Void
	{
		for (touch in FlxG.touches.list)
		{
			if (touch.justPressed)
			{
				_touchStartX = touch.screenX;
				_touchStartY = touch.screenY;
				_touchPrevY = touch.screenY;
				_touchIsScroll = false;
			}

			if (touch.pressed)
			{
				var deltaY = touch.screenY - _touchPrevY;
				var totalDeltaY = Math.abs(touch.screenY - _touchStartY);
				var totalDeltaX = Math.abs(touch.screenX - _touchStartX);

				// Detectar inicio de scroll vertical (SLIDE UP/DOWN)
				if (!_touchIsScroll && totalDeltaY > 20 && totalDeltaY > totalDeltaX)
					_touchIsScroll = true;

				if (_touchIsScroll)
				{
					_optScrollY -= deltaY;
					// Limitar el scroll para no salirse de la lista
					var maxScroll = Math.max(0, (currentOptions.length * OPT_SPACING) - OPT_VISIBLE_H);
					if (_optScrollY < 0) _optScrollY = 0;
					if (_optScrollY > maxScroll) _optScrollY = maxScroll;

					_updateScroll();
				}
				_touchPrevY = touch.screenY;
			}

			if (touch.justReleased)
			{
				var totalDeltaX = touch.screenX - _touchStartX;
				var totalDeltaY = touch.screenY - _touchStartY;

				if (!_touchIsScroll)
				{
					if (Math.abs(totalDeltaX) < 25 && Math.abs(totalDeltaY) < 25)
					{
						// 1. TAP Title o Footage (Volver)
						if (touch.screenY < 80 || touch.screenY > FlxG.height - 100)
						{
							if (_editMode) {
								_editMode = false;
								_editModeIndicator.visible = false;
								FlxG.sound.play(Paths.sound('menus/cancelMenu'), 0.7);
							} else {
								_exitOptionsMenu();
							}
							return;
						}

						if (touch.screenY > 80 && touch.screenY < 135)
						{
							var categoryWidth = (FlxG.width - 120) / categories.length;
							var tabIdx = Std.int((touch.screenX - 60) / categoryWidth);
							if (tabIdx >= 0 && tabIdx < categories.length && tabIdx != curCategory)
							{
								curCategory = tabIdx;
								loadCategory(curCategory);
								FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.7);
								return;
							}
						}

						if (touch.screenY >= OPT_START_Y && touch.screenY <= OPT_START_Y + OPT_VISIBLE_H)
						{
							var relativeY = touch.screenY - OPT_START_Y + _optScrollY;
							var clickedIdx = Std.int(relativeY / OPT_SPACING);

							if (clickedIdx >= 0 && clickedIdx < currentOptions.length)
							{
								if (curSelected == clickedIdx)
								{
									_triggerSelectedOption();
								}
								else
								{
									curSelected = clickedIdx;
									updateOptionDisplay();
									FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.7);
								}
							}
						}
					}
					else if (Math.abs(totalDeltaX) > 60 && Math.abs(totalDeltaY) < 50)
					{
						if (totalDeltaX > 0)
							curCategory--;
						else
							curCategory++;

						if (curCategory < 0) curCategory = categories.length - 1;
						if (curCategory >= categories.length) curCategory = 0;

						loadCategory(curCategory);
						FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.7);
					}
				}
			}
		}
	}

	function _triggerSelectedOption():Void
	{
		if (currentOptions.length == 0) return;
		
		final opt = currentOptions[curSelected];
		if (opt.left != null || opt.right != null)
		{
			_editMode = true;
			_editModeIndicator.text = "⟵ A / D ⟶ Adjusting: " + opt.name + "   (TAP Title/Footer to confirm)";
			_editModeIndicator.visible = true;
			FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.7);
		}
		else if (opt.toggle != null)
		{
			opt.toggle();
			updateOptionDisplay();
			FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.7);
		}
	}

	function _exitOptionsMenu():Void
	{
		if (bindingState != "select") return;

		FlxG.sound.play(Paths.sound('menus/cancelMenu'), 0.7);
		if (fromPause) {
			isOpenOptions = false;
			close();
		} else {
			MusicBeatState.switchState(new MainMenuState());
		}
	}
	#end

	#if HSCRIPT_ALLOWED
	/**
	 * Carga categorías custom registradas desde scripts
	 */
	function loadCustomCategoriesFromScripts():Void
	{
		var customCategories = StateScriptHandler.getCustomCategories();
		for (categoryName in customCategories)
		{
			if (!categories.contains(categoryName))
			{
				categories.push(categoryName);
			}
		}
	}
	#end

	function loadKeyBinds()
	{
		// Verificar que existan los keybinds
		if (SaveData.data.leftBind == null)
			SaveData.data.leftBind = "A";
		if (SaveData.data.downBind == null)
			SaveData.data.downBind = "S";
		if (SaveData.data.upBind == null)
			SaveData.data.upBind = "W";
		if (SaveData.data.rightBind == null)
			SaveData.data.rightBind = "D";
		if (SaveData.data.killBind == null)
			SaveData.data.killBind = "R";
		if (SaveData.data.acceptBind == null)
			SaveData.data.acceptBind = "ENTER";
		if (SaveData.data.backBind == null)
			SaveData.data.backBind = "ESCAPE";
		if (SaveData.data.pauseBind == null)
			SaveData.data.pauseBind = "ENTER";
		if (SaveData.data.screenshotBind == null)
			SaveData.data.screenshotBind = "F12";
		if (SaveData.data.cheatBind == null)
			SaveData.data.cheatBind = "SEVEN";

		keys = [
			SaveData.data.leftBind,
			SaveData.data.downBind,
			SaveData.data.upBind,
			SaveData.data.rightBind,
			SaveData.data.killBind,
			SaveData.data.acceptBind,
			SaveData.data.backBind,
			SaveData.data.pauseBind,
			SaveData.data.screenshotBind,
			SaveData.data.cheatBind
		];
	}

	function saveKeyBinds()
	{
		SaveData.data.leftBind = keys[0];
		SaveData.data.downBind = keys[1];
		SaveData.data.upBind = keys[2];
		SaveData.data.rightBind = keys[3];
		SaveData.data.killBind = keys[4];
		SaveData.data.acceptBind = keys[5];
		SaveData.data.backBind = keys[6];
		SaveData.data.pauseBind = keys[7];
		SaveData.data.screenshotBind = keys[8];
		SaveData.data.cheatBind = keys[9];

		SaveData.flush();
		PlayerSettings.player1.controls.loadKeyBinds();
	}

	function loadCategory(index:Int)
	{
		// Limpiar contenido anterior
		optionNames.clear();
		optionValues.clear();
		currentOptions = [];
		curSelected = 0;
		_optScrollY = 0.0;
		if (_scrollbarTrack != null)
			_scrollbarTrack.visible = false;
		if (_scrollbarThumb != null)
			_scrollbarThumb.visible = false;
		bindingState = "select";
		bindingIndicator.visible = false;
		_editMode = false;
		if (_editModeIndicator != null)
			_editModeIndicator.visible = false;

		var categoryName = categories[index];

		switch (categoryName)
		{
			case 'General':
				loadGeneralOptions();
			case 'Graphics':
				loadGraphicsOptions();
			case 'Gameplay':
				loadGameplayOptions();
			case 'Subtitles':
				loadSubtitlesOptions();
			case 'Controls':
				loadControlsOptions();
			case 'Note Skin':
				loadNoteSkinOptions();
			case 'Offset':
				loadOffsetOptions();
			case 'Mobile':
				#if mobileC
				loadMobileControlsOptions();
				#end
			default:
				// Categoría custom desde script
				#if HSCRIPT_ALLOWED
				loadCustomCategory(categoryName);
				#end
		}

		// Agregar opciones custom a categorías existentes desde scripts
		#if HSCRIPT_ALLOWED
		loadCustomOptionsForCategory(categoryName);
		#end

		updateCategoryDisplay();
		updateOptionDisplay();
		_updateScroll(); // ← CRITICAL: clip items beyond visible area from the start
	}

	#if HSCRIPT_ALLOWED
	/**
	 * Carga una categoría custom completa desde scripts
	 */
	function loadCustomCategory(categoryName:String):Void
	{
		// Llamar a los scripts para obtener opciones de esta categoría
		var customOptions = StateScriptHandler.callOnScriptsReturn('getOptionsForCategory', [categoryName]);

		if (customOptions != null && Std.isOfType(customOptions, Array))
		{
			var optionsArray:Array<Dynamic> = cast customOptions;
			for (opt in optionsArray)
			{
				currentOptions.push(opt);
			}
		}

		createOptionTexts();
	}

	/**
	 * Carga opciones custom que se agregan a categorías existentes
	 */
	function loadCustomOptionsForCategory(categoryName:String):Void
	{
		// Llamar a los scripts para obtener opciones adicionales para esta categoría
		var additionalOptions = StateScriptHandler.callOnScriptsReturn('getAdditionalOptionsForCategory', [categoryName]);

		if (additionalOptions != null && Std.isOfType(additionalOptions, Array))
		{
			var optionsArray:Array<Dynamic> = cast additionalOptions;
			for (opt in optionsArray)
			{
				currentOptions.push(opt);
			}

			// Recrear los textos con las opciones adicionales
			optionNames.clear();
			optionValues.clear();
			createOptionTexts();
		}
	}
	#end

	function loadGeneralOptions()
	{
		currentOptions = [
			{
				name: "Flashing Lights",
				get: function() return SaveData.data.flashing ? "ON" : "OFF",
				toggle: function()
				{
					SaveData.data.flashing = !SaveData.data.flashing;
				}
			},
			{
				name: "Show HUD",
				get: function() return SaveData.data.HUD ? "OFF" : "ON",
				toggle: function()
				{
					SaveData.data.HUD = !SaveData.data.HUD;
				}
			},
			{
				name: "FPS Counter",
				get: function()
				{
					var mainInstance = cast(openfl.Lib.current.getChildAt(0), Main);
					return mainInstance.data.visible ? "ON" : "OFF";
				},
				toggle: function()
				{
					var mainInstance = cast(openfl.Lib.current.getChildAt(0), Main);
					mainInstance.data.visible = !mainInstance.data.visible;
				}
			},
			#if !mobileC
			{
				// ── FPS Cap ─────────────────────────────────────────────────────
				// ← / → suben/bajan de 5 en 5 entre 30 y 240, luego Unlimited (0).
				// Se guarda en SaveData.data.fpsTarget y se aplica de inmediato.
				name: "FPS Cap",
				get: function()
				{
					var t:Int = _getCurrentFPS();
					return t == 0 ? "Unlimited" : t + " FPS";
				},
				toggle: function()
				{
					applyFPSCap(_nextFPS(_getCurrentFPS()));
				},
				left: function()
				{
					applyFPSCap(_prevFPS(_getCurrentFPS()));
				},
				right: function()
				{
					applyFPSCap(_nextFPS(_getCurrentFPS()));
				}
			}, {
				// ── VSync ────────────────────────────────────────────────────────
				name: "VSync",
				get: function()
				{
					return (SaveData.data.vsync == true) ? "ON" : "OFF";
				},
				toggle: function()
				{
					applyVSync(!(SaveData.data.vsync == true));
				}
			},
			// ── Gamepad Rumble ───────────────────────────────────────────────────
			// Visible solo en desktop (donde suelen conectarse mandos).
			// La intensidad es compartida con la vibración móvil.
			{
				name: "Gamepad Rumble",
				get: function()
				{
					var on = SaveData.data.gamepadRumble != null ? SaveData.data.gamepadRumble : true;
					return on ? "ON" : "OFF";
				},
				toggle: function()
				{
					var cur = SaveData.data.gamepadRumble != null ? SaveData.data.gamepadRumble : true;
					SaveData.data.gamepadRumble = !cur;
					SaveData.flush();
					// Preview inmediato al activar
					if (SaveData.data.gamepadRumble)
						funkin.util.VibrationManager.vibrateConfirm();
				}
			},
			{
				name: "Rumble Intensity",
				get: function()
				{
					var intensity = SaveData.data.vibrationIntensity != null ? SaveData.data.vibrationIntensity : "medium";
					return switch (intensity)
					{
						case "light":  "Light";
						case "strong": "Strong";
						default:       "Medium";
					};
				},
				left: function()
				{
					var intensity = SaveData.data.vibrationIntensity != null ? SaveData.data.vibrationIntensity : "medium";
					SaveData.data.vibrationIntensity = switch (intensity)
					{
						case "light":  "strong";
						case "medium": "light";
						case "strong": "medium";
						default:       "medium";
					};
					SaveData.flush();
					funkin.util.VibrationManager.vibrateConfirm();
				},
				right: function()
				{
					var intensity = SaveData.data.vibrationIntensity != null ? SaveData.data.vibrationIntensity : "medium";
					SaveData.data.vibrationIntensity = switch (intensity)
					{
						case "light":  "medium";
						case "medium": "strong";
						case "strong": "light";
						default:       "medium";
					};
					SaveData.flush();
					funkin.util.VibrationManager.vibrateConfirm();
				},
				toggle: function() { funkin.util.VibrationManager.vibrateConfirm(); }
			}
			#end
		];

		createOptionTexts();
	}

	/** Aplica el FPS cap y lo persiste en el save */
	function applyFPSCap(fps:Int):Void
	{
		SaveData.data.fpsTarget = fps;
		SaveData.flush();

		// Delegar SIEMPRE en Main.setMaxFps() — es el único punto que sabe
		// si usar FrameLimiterAPI (desktop/cpp) o stage.frameRate (mobile/html5).
		// NO tocar stage.frameRate directamente aquí:
		//   • stage.frameRate = 0 → OpenFL deja de disparar ENTER_FRAME → juego congelado.
		//   • En desktop el throttle real ya lo hace FrameLimiterAPI, no Lime.
		var main = cast(openfl.Lib.current.getChildAt(0), Main);
		if (main != null)
			main.setMaxFps(fps);

		trace('[Options] FPS cap -> ' + (fps <= 0 ? 'Unlimited' : fps + ' FPS'));
	}

	/** Aplica/quita VSync via extensión nativa y lo persiste en el save */
	function applyVSync(value:Bool):Void
	{
		SaveData.data.vsync = value;
		SaveData.flush();
		#if cpp
		extensions.VSyncAPI.setVSync(value);
		#end
		trace('[Options] VSync -> ' + (value ? 'ON' : 'OFF'));
	}

	function loadGraphicsOptions()
	{
		currentOptions = [
			#if !mobileC
			{
				name: "GPU Texture Caching",
				get: function() return SaveData.data.gpuCaching ? "ON" : "OFF",
				toggle: function()
				{
					SaveData.data.gpuCaching = !SaveData.data.gpuCaching;
					funkin.cache.PathsCache.gpuCaching = SaveData.data.gpuCaching;
					SaveData.flush();
				}
			},
			#end
			{
				name: "Low Memory Mode",
				get: function() return SaveData.data.lowMemoryMode ? "ON" : "OFF",
				toggle: function()
				{
					SaveData.data.lowMemoryMode = !SaveData.data.lowMemoryMode;
					funkin.cache.PathsCache.lowMemoryMode = SaveData.data.lowMemoryMode;
					SaveData.flush();
				}
			},
			{
				name: "Shaders",
				get: function() return SaveData.data.shaders ? "ON" : "OFF",
				toggle: function()
				{
					SaveData.data.shaders = !SaveData.data.shaders;
					if (funkin.graphics.shaders.ShaderManager.initialized)
						funkin.graphics.shaders.ShaderManager.setEnabled(SaveData.data.shaders);
					SaveData.flush();
				}
			},
			#if !mobileC
			{
				name: "Streamed Music",
				get: function() return SaveData.data.streamedMusic ? "ON" : "OFF",
				toggle: function()
				{
					SaveData.data.streamedMusic = !SaveData.data.streamedMusic;
					funkin.cache.PathsCache.streamedMusic = SaveData.data.streamedMusic;
					SaveData.flush();
				}
			},
			#end
			{
				name: "Anti-Aliasing",
				get: function() return SaveData.data.antialiasing ? "ON" : "OFF",
				toggle: function()
				{
					SaveData.data.antialiasing = !SaveData.data.antialiasing;
				}
			},
			{
				name: "Note Splashes",
				get: function() return SaveData.data.notesplashes ? "ON" : "OFF",
				toggle: function()
				{
					SaveData.data.notesplashes = !SaveData.data.notesplashes;
				}
			},
			{
				name: "Visual Effects",
				get: function() return SaveData.data.specialVisualEffects ? "ON" : "OFF",
				toggle: function()
				{
					SaveData.data.specialVisualEffects = !SaveData.data.specialVisualEffects;
				}
			}
		];

		createOptionTexts();
	}

	function loadGameplayOptions()
	{
		currentOptions = [
			{
				name: "Downscroll",
				get: function() return SaveData.data.downscroll ? "ON" : "OFF",
				toggle: function()
				{
					SaveData.data.downscroll = !SaveData.data.downscroll;
				}
			},
			{
				name: "Middlescroll",
				get: function() return SaveData.data.middlescroll ? "ON" : "OFF",
				toggle: function()
				{
					SaveData.data.middlescroll = !SaveData.data.middlescroll;
				}
			},
			{
				name: "Sustain Penalty",
				get: function() return SaveData.data.sustainMiss ? "ON" : "OFF",
				toggle: function()
				{
					SaveData.data.sustainMiss = !SaveData.data.sustainMiss;
				}
			},
			{
				name: "Ghost Tapping",
				get: function() return SaveData.data.ghosttap ? "ON" : "OFF",
				toggle: function()
				{
					SaveData.data.ghosttap = !SaveData.data.ghosttap;
				}
			},
			{
				name: "Accuracy Display",
				get: function() return SaveData.data.accuracyDisplay ? "ON" : "OFF",
				toggle: function()
				{
					SaveData.data.accuracyDisplay = !SaveData.data.accuracyDisplay;
				}
			},
			{
				name: "Sick Mode",
				get: function() return SaveData.data.sickmode ? "ON" : "OFF",
				toggle: function()
				{
					SaveData.data.sickmode = !SaveData.data.sickmode;
				}
			},
			{
				name: "Hit Sounds",
				get: function() return SaveData.data.hitsounds ? "ON" : "OFF",
				toggle: function()
				{
					SaveData.data.hitsounds = !SaveData.data.hitsounds;
				}
			},
			{
				name: "Lane Backdrop",
				get: function()
				{
					var a:Float = (SaveData.data.laneAlpha != null) ? SaveData.data.laneAlpha : 0.0;
					return Std.int(a * 100) + "%";
				},
				left: function()
				{
					var a:Float = (SaveData.data.laneAlpha != null) ? SaveData.data.laneAlpha : 0.0;
					a = Math.max(0.0, Math.round((a - 0.05) * 100) / 100);
					SaveData.data.laneAlpha = a;
					_applyLaneBackdropAlpha(a);
				},
				right: function()
				{
					var a:Float = (SaveData.data.laneAlpha != null) ? SaveData.data.laneAlpha : 0.0;
					a = Math.min(1.0, Math.round((a + 0.05) * 100) / 100);
					SaveData.data.laneAlpha = a;
					_applyLaneBackdropAlpha(a);
				}
			},
			// ── Rating Position ────────────────────────────────────────────────
			// Abre un substate visual donde se puede mover la posición del popup
			// de rating (Sick, Good, Bad, etc.) en pantalla.
			{
				name: "Rating Position",
				get: function()
				{
					var ox:Float = SaveData.data.ratingOffsetX != null ? SaveData.data.ratingOffsetX : 0;
					var oy:Float = SaveData.data.ratingOffsetY != null ? SaveData.data.ratingOffsetY : 0;
					return 'X:$ox  Y:$oy';
				},
				toggle: function()
				{
					openSubState(new RatingPositionSubState());
				}
			}
		];

		createOptionTexts();
	}

	function loadControlsOptions()
	{
		currentOptions = [];

		// Cargar keybinds actuales (todos los 9 controles)
		for (i in 0...keyBindNames.length)
		{
			var keyIndex = i;
			currentOptions.push({
				name: keyBindNames[i],
				get: function() return _displayKey(keys[keyIndex]),
				toggle: function()
				{
					startBinding(keyIndex);
				},
				isKeybind: true
			});
		}

		// Opción de resetear
		currentOptions.push({
			name: "Reset to Default",
			get: function() return "BACKSPACE",
			toggle: function()
			{
				resetKeybinds();
			},
			isKeybind: false
		});

		createOptionTexts();
	}

	function loadNoteSkinOptions()
	{
		currentOptions = [
			{
				name: "Note Skin Settings",
				get: function() return "PRESS ENTER",
				toggle: function()
				{
					StateTransition.switchState(new NoteSkinOptions());
				}
			}
		];

		createOptionTexts();
	}

	#if mobileC
	/** Nombres de esquemas de control en el mismo orden que Config.getcontrolmode() devuelve */
	static final MOBILE_SCHEME_NAMES:Array<String> = [
		"VirtualPad Right", // 0
		"VirtualPad Left", // 1
		"Keyboard Only", // 2
		"VirtualPad Custom", // 3
		"Hitbox" // 4
	];

	function loadMobileControlsOptions()
	{
		var config = new data.Config();
		currentOptions = [
			{
				name: "Control Scheme",
				get: function()
				{
					var mode = config.getcontrolmode();
					return MOBILE_SCHEME_NAMES[mode < MOBILE_SCHEME_NAMES.length ? mode : 0];
				},
				toggle: function()
				{
					// Cicla al siguiente esquema
					var mode = config.getcontrolmode();
					config.setcontrolmode((mode + 1) % MOBILE_SCHEME_NAMES.length);
				},
				left: function()
				{
					var mode = config.getcontrolmode();
					config.setcontrolmode((mode - 1 + MOBILE_SCHEME_NAMES.length) % MOBILE_SCHEME_NAMES.length);
				},
				right: function()
				{
					var mode = config.getcontrolmode();
					config.setcontrolmode((mode + 1) % MOBILE_SCHEME_NAMES.length);
				}
			},
			{
				name: "Pad Opacity",
				get: function()
				{
					var v = SaveData.data.mobileAlpha != null ? Std.int(SaveData.data.mobileAlpha * 100) : 75;
					return v + "%";
				},
				left: function()
				{
					var v:Float = SaveData.data.mobileAlpha != null ? SaveData.data.mobileAlpha : 0.75;
					v = Math.max(0.1, v - 0.05);
					SaveData.data.mobileAlpha = v;
					SaveData.flush();
				},
				right: function()
				{
					var v:Float = SaveData.data.mobileAlpha != null ? SaveData.data.mobileAlpha : 0.75;
					v = Math.min(1.0, v + 0.05);
					SaveData.data.mobileAlpha = v;
					SaveData.flush();
				},
				toggle: function()
				{
				}
			},
			{
				name: "Edit Custom Layout",
				get: function() return "PRESS ENTER",
				toggle: function()
				{
					// Solo disponible en modo VirtualPad Custom
					var mode = config.getcontrolmode();
					if (mode == 3)
						openSubState(new ui.MobileControlsEditor());
					else
						showWarning("Switch to 'VirtualPad Custom' first!");
				}
			},
			{
				name: "Reset Custom Layout",
				get: function() return "BACKSPACE",
				toggle: function()
				{
					SaveData.data.mobilePadLayout = null;
					SaveData.flush();
					showWarning("Custom layout reset!");
					FlxG.sound.play(Paths.sound('menus/cancelMenu'));
				}
			},
			{
				name: "Touch Indicator",
				get: function()
				{
					var on = SaveData.data.touchIndicator != null ? SaveData.data.touchIndicator : true;
					return on ? "ON" : "OFF";
				},
				toggle: function()
				{
					var cur = SaveData.data.touchIndicator != null ? SaveData.data.touchIndicator : true;
					SaveData.data.touchIndicator = !cur;
					SaveData.flush();
					funkin.util.plugins.TouchPointerPlugin.enabled = SaveData.data.touchIndicator;
				}
			},
			// ── Vibración háptica ────────────────────────────────────────────────
			{
				name: "Vibration",
				get: function()
				{
					var on = SaveData.data.vibration != null ? SaveData.data.vibration : true;
					return on ? "ON" : "OFF";
				},
				toggle: function()
				{
					var cur = SaveData.data.vibration != null ? SaveData.data.vibration : true;
					SaveData.data.vibration = !cur;
					SaveData.flush();
					// Feedback inmediato al activar
					if (SaveData.data.vibration)
						funkin.util.VibrationManager.vibrateConfirm();
				}
			},
			{
				name: "Vibration Intensity",
				get: function()
				{
					var intensity = SaveData.data.vibrationIntensity != null ? SaveData.data.vibrationIntensity : "medium";
					return switch (intensity)
					{
						case "light":  "Light";
						case "strong": "Strong";
						default:       "Medium";
					};
				},
				left: function()
				{
					var intensity = SaveData.data.vibrationIntensity != null ? SaveData.data.vibrationIntensity : "medium";
					SaveData.data.vibrationIntensity = switch (intensity)
					{
						case "light":  "strong";
						case "medium": "light";
						case "strong": "medium";
						default:       "medium";
					};
					SaveData.flush();
					_previewVibration();
				},
				right: function()
				{
					var intensity = SaveData.data.vibrationIntensity != null ? SaveData.data.vibrationIntensity : "medium";
					SaveData.data.vibrationIntensity = switch (intensity)
					{
						case "light":  "medium";
						case "medium": "strong";
						case "strong": "light";
						default:       "medium";
					};
					SaveData.flush();
					_previewVibration();
				},
				toggle: function() { _previewVibration(); }
			}
		];

		createOptionTexts();
	}

	/**
	 * Hace una vibración de prueba con la intensidad seleccionada actualmente.
	 * Solo se llama desde las opciones de Vibration Intensity.
	 */
	function _previewVibration():Void
	{
		var intensity = SaveData.data.vibrationIntensity != null ? SaveData.data.vibrationIntensity : "medium";
		switch (intensity)
		{
			case "light":  funkin.util.VibrationManager.vibrateTap();
			case "strong": funkin.util.VibrationManager.vibrateMiss();
			default:       funkin.util.VibrationManager.vibrateBeat();
		}
	}
	#end

	// ── Tamaños de fuente disponibles para subtítulos ─────────────────────────
	static final SUBTITLE_SIZES:Array<Int> = [16, 18, 20, 22, 24, 26, 28, 30, 32, 36, 40, 48];

	// ── Fuentes disponibles para subtítulos ───────────────────────────────────
	// Nombre visible | nombre real del archivo en assets/fonts/
	static final SUBTITLE_FONT_NAMES:Array<String> = ['VCR OSD', 'Funkin', 'Arial', 'Pixel', 'Bold'];
	static final SUBTITLE_FONT_FILES:Array<String> = ['vcr.ttf', 'Funkin.otf', 'arial.ttf', 'pixel.ttf', 'bold.ttf'];

	// ── Colores de texto predefinidos ─────────────────────────────────────────
	static final SUBTITLE_COLOR_NAMES:Array<String> = ['White', 'Yellow', 'Cyan', 'Lime', 'Pink', 'Orange'];
	static final SUBTITLE_COLOR_VALUES:Array<Int> = [0xFFFFFFFF, 0xFFFFFF00, 0xFF00FFFF, 0xFF00FF00, 0xFFFF69B4, 0xFFFF8C00];

	// ── Idiomas de traducción ─────────────────────────────────────────────────
	static final SUBTITLE_LANG_NAMES:Array<String> = [
		      'None',  'Spanish', 'English',  'French',  'German', 'Italian',
		'Portuguese', 'Japanese',  'Korean', 'Chinese', 'Russian',  'Arabic'
	];
	static final SUBTITLE_LANG_CODES:Array<String> = [
		  '', 'es', 'en', 'fr', 'de', 'it',
		'pt', 'ja', 'ko', 'zh', 'ru', 'ar'
	];

	function loadSubtitlesOptions()
	{
		currentOptions = [
			// ── Activar / desactivar subtítulos ───────────────────────────────
			{
				name: "Subtitles",
				get: function()
				{
					return (SaveData.data.subtitlesEnabled != false) ? "ON" : "OFF";
				},
				toggle: function()
				{
					SaveData.data.subtitlesEnabled = !(SaveData.data.subtitlesEnabled != false);
					SaveData.flush();
				}
			},
			// ── Fuente del texto ──────────────────────────────────────────────
			{
				name: "Font",
				get: function()
				{
					var f:String = SaveData.data.subtitleFont != null ? SaveData.data.subtitleFont : 'vcr.ttf';
					var idx = SUBTITLE_FONT_FILES.indexOf(f);
					return idx >= 0 ? SUBTITLE_FONT_NAMES[idx] : f;
				},
				left: function()
				{
					var f:String = SaveData.data.subtitleFont != null ? SaveData.data.subtitleFont : 'vcr.ttf';
					var idx = _resolveSubtitleFontIndex(f);
					idx = (idx - 1 + _availableSubtitleFonts().length) % _availableSubtitleFonts().length;
					SaveData.data.subtitleFont = _availableSubtitleFonts()[idx];
					_applySubtitleSettings();
				},
				right: function()
				{
					var f:String = SaveData.data.subtitleFont != null ? SaveData.data.subtitleFont : 'vcr.ttf';
					var idx = _resolveSubtitleFontIndex(f);
					idx = (idx + 1) % _availableSubtitleFonts().length;
					SaveData.data.subtitleFont = _availableSubtitleFonts()[idx];
					_applySubtitleSettings();
				}
			},
			// ── Tamaño de fuente ──────────────────────────────────────────────
			{
				name: "Font Size",
				get: function()
				{
					var sz:Int = SaveData.data.subtitleSize != null ? SaveData.data.subtitleSize : 26;
					return sz + " px";
				},
				left: function()
				{
					var sz:Int = SaveData.data.subtitleSize != null ? SaveData.data.subtitleSize : 26;
					var idx = SUBTITLE_SIZES.indexOf(sz);
					if (idx < 0)
						idx = SUBTITLE_SIZES.indexOf(26);
					idx = (idx - 1 + SUBTITLE_SIZES.length) % SUBTITLE_SIZES.length;
					SaveData.data.subtitleSize = SUBTITLE_SIZES[idx];
					_applySubtitleSettings();
				},
				right: function()
				{
					var sz:Int = SaveData.data.subtitleSize != null ? SaveData.data.subtitleSize : 26;
					var idx = SUBTITLE_SIZES.indexOf(sz);
					if (idx < 0)
						idx = SUBTITLE_SIZES.indexOf(26);
					idx = (idx + 1) % SUBTITLE_SIZES.length;
					SaveData.data.subtitleSize = SUBTITLE_SIZES[idx];
					_applySubtitleSettings();
				}
			},
			// ── Color del texto ───────────────────────────────────────────────
			{
				name: "Text Color",
				get: function()
				{
					var c:Int = SaveData.data.subtitleColor != null ? SaveData.data.subtitleColor : 0xFFFFFFFF;
					var idx = SUBTITLE_COLOR_VALUES.indexOf(c);
					return idx >= 0 ? SUBTITLE_COLOR_NAMES[idx] : "Custom";
				},
				left: function()
				{
					var c:Int = SaveData.data.subtitleColor != null ? SaveData.data.subtitleColor : 0xFFFFFFFF;
					var idx = SUBTITLE_COLOR_VALUES.indexOf(c);
					if (idx < 0)
						idx = 0;
					idx = (idx - 1 + SUBTITLE_COLOR_VALUES.length) % SUBTITLE_COLOR_VALUES.length;
					SaveData.data.subtitleColor = SUBTITLE_COLOR_VALUES[idx];
					_applySubtitleSettings();
				},
				right: function()
				{
					var c:Int = SaveData.data.subtitleColor != null ? SaveData.data.subtitleColor : 0xFFFFFFFF;
					var idx = SUBTITLE_COLOR_VALUES.indexOf(c);
					if (idx < 0)
						idx = 0;
					idx = (idx + 1) % SUBTITLE_COLOR_VALUES.length;
					SaveData.data.subtitleColor = SUBTITLE_COLOR_VALUES[idx];
					_applySubtitleSettings();
				}
			},
			// ── Opacidad del fondo ────────────────────────────────────────────
			{
				name: "Background Opacity",
				get: function()
				{
					var a:Float = SaveData.data.subtitleBgAlpha != null ? SaveData.data.subtitleBgAlpha : 0.6;
					return Std.int(a * 100) + "%";
				},
				left: function()
				{
					var a:Float = SaveData.data.subtitleBgAlpha != null ? SaveData.data.subtitleBgAlpha : 0.6;
					a = Math.max(0.0, Math.round((a - 0.1) * 10) / 10);
					SaveData.data.subtitleBgAlpha = a;
					_applySubtitleSettings();
				},
				right: function()
				{
					var a:Float = SaveData.data.subtitleBgAlpha != null ? SaveData.data.subtitleBgAlpha : 0.6;
					a = Math.min(1.0, Math.round((a + 0.1) * 10) / 10);
					SaveData.data.subtitleBgAlpha = a;
					_applySubtitleSettings();
				}
			},
			// ── Posición vertical ─────────────────────────────────────────────
			{
				name: "Position",
				get: function()
				{
					var p:String = SaveData.data.subtitlePosition != null ? SaveData.data.subtitlePosition : 'bottom';
					return switch (p)
					{
						case 'top': "Top";
						case 'center': "Center";
						default: "Bottom";
					};
				},
				toggle: function()
				{
					var p:String = SaveData.data.subtitlePosition != null ? SaveData.data.subtitlePosition : 'bottom';
					SaveData.data.subtitlePosition = switch (p)
					{
						case 'bottom': 'top';
						case 'top': 'center';
						default: 'bottom';
					};
					_applySubtitleSettings();
				}
			},
			// ── Negrita ───────────────────────────────────────────────────────
			{
				name: "Bold Text",
				get: function()
				{
					return (SaveData.data.subtitleBold != false) ? "ON" : "OFF";
				},
				toggle: function()
				{
					SaveData.data.subtitleBold = !(SaveData.data.subtitleBold != false);
					_applySubtitleSettings();
				}
			},
			// ── Velocidad de fade ─────────────────────────────────────────────
			{
				name: "Fade Speed",
				get: function()
				{
					var f:Float = SaveData.data.subtitleFadeIn != null ? SaveData.data.subtitleFadeIn : 0.2;
					return f == 0 ? "Instant" : (Std.int(f * 10) / 10) + "s";
				},
				left: function()
				{
					var steps:Array<Float> = [0.0, 0.1, 0.2, 0.3, 0.5, 0.8, 1.0];
					var f:Float = SaveData.data.subtitleFadeIn != null ? SaveData.data.subtitleFadeIn : 0.2;
					var idx = 0;
					var best = 999.0;
					for (i in 0...steps.length)
					{
						var d = Math.abs(steps[i] - f);
						if (d < best)
						{
							best = d;
							idx = i;
						}
					}
					idx = (idx - 1 + steps.length) % steps.length;
					SaveData.data.subtitleFadeIn = steps[idx];
					_applySubtitleSettings();
				},
				right: function()
				{
					var steps:Array<Float> = [0.0, 0.1, 0.2, 0.3, 0.5, 0.8, 1.0];
					var f:Float = SaveData.data.subtitleFadeIn != null ? SaveData.data.subtitleFadeIn : 0.2;
					var idx = 0;
					var best = 999.0;
					for (i in 0...steps.length)
					{
						var d = Math.abs(steps[i] - f);
						if (d < best)
						{
							best = d;
							idx = i;
						}
					}
					idx = (idx + 1) % steps.length;
					SaveData.data.subtitleFadeIn = steps[idx];
					_applySubtitleSettings();
				}
			},
			// ── Idioma de traducción ──────────────────────────────────────────
			{
				name: "Translate To",
				get: function()
				{
					var code:String = SaveData.data.subtitleTranslateLang != null ? SaveData.data.subtitleTranslateLang : '';
					var idx = SUBTITLE_LANG_CODES.indexOf(code);
					return idx >= 0 ? SUBTITLE_LANG_NAMES[idx] : "None";
				},
				left: function()
				{
					var code:String = SaveData.data.subtitleTranslateLang != null ? SaveData.data.subtitleTranslateLang : '';
					var idx = SUBTITLE_LANG_CODES.indexOf(code);
					if (idx < 0)
						idx = 0;
					idx = (idx - 1 + SUBTITLE_LANG_CODES.length) % SUBTITLE_LANG_CODES.length;
					SaveData.data.subtitleTranslateLang = SUBTITLE_LANG_CODES[idx];
					SaveData.flush();
				},
				right: function()
				{
					var code:String = SaveData.data.subtitleTranslateLang != null ? SaveData.data.subtitleTranslateLang : '';
					var idx = SUBTITLE_LANG_CODES.indexOf(code);
					if (idx < 0)
						idx = 0;
					idx = (idx + 1) % SUBTITLE_LANG_CODES.length;
					SaveData.data.subtitleTranslateLang = SUBTITLE_LANG_CODES[idx];
					SaveData.flush();
				}
			}
		];

		createOptionTexts();
	}

	/**
	 * Devuelve solo las fuentes que existen en assets/fonts/ en el sistema.
	 * Siempre incluye vcr.ttf y Funkin.otf como fallback garantizado.
	 */
	function _availableSubtitleFonts():Array<String>
	{
		var available:Array<String> = [];
		for (i in 0...SUBTITLE_FONT_FILES.length)
		{
			var file = SUBTITLE_FONT_FILES[i];
			var path = 'assets/fonts/$file';
			var exists = false;
			#if sys
			exists = sys.FileSystem.exists(path);
			#else
			exists = openfl.utils.Assets.exists(path);
			#end
			// vcr.ttf y Funkin.otf siempre incluidos (vienen con el engine)
			if (exists || file == 'vcr.ttf' || file == 'Funkin.otf')
				available.push(file);
		}
		if (available.length == 0)
			available.push('vcr.ttf');
		return available;
	}

	/** Devuelve el índice de la fuente en _availableSubtitleFonts(), o 0 si no se encuentra. */
	function _resolveSubtitleFontIndex(fontFile:String):Int
	{
		var avail = _availableSubtitleFonts();
		var idx = avail.indexOf(fontFile);
		return idx >= 0 ? idx : 0;
	}

	/** Aplica la configuración de subtítulos guardada al SubtitleManager singleton. */
	function _applySubtitleSettings():Void
	{
		SaveData.flush();
		var sm = funkin.ui.SubtitleManager.instance;

		// Fuente
		if (SaveData.data.subtitleFont != null)
			sm.defaultFont = SaveData.data.subtitleFont;

		// Tamaño
		if (SaveData.data.subtitleSize != null)
			sm.defaultSize = SaveData.data.subtitleSize;

		// Color
		if (SaveData.data.subtitleColor != null)
			sm.defaultColor = SaveData.data.subtitleColor;

		// Opacidad de fondo
		if (SaveData.data.subtitleBgAlpha != null)
			sm.defaultBgAlpha = SaveData.data.subtitleBgAlpha;

		// Negrita
		if (SaveData.data.subtitleBold != null)
			sm.defaultBold = (SaveData.data.subtitleBold != false);

		// Fade in/out
		if (SaveData.data.subtitleFadeIn != null)
		{
			sm.defaultFadeIn = SaveData.data.subtitleFadeIn;
			sm.defaultFadeOut = SaveData.data.subtitleFadeIn;
		}

		// Posición Y
		var pos:String = SaveData.data.subtitlePosition != null ? SaveData.data.subtitlePosition : 'bottom';
		sm.defaultY = switch (pos)
		{
			case 'top': 60.0;
			case 'center': -2.0; // valor especial: centrado vertical
			default: -1.0; // -1 = automático (cerca del fondo)
		};
	}

	function loadOffsetOptions()
	{
		currentOptions = [
			{
				name: "Audio Offset",
				get: function() return SaveData.data.offset + " ms",
				toggle: function()
				{
					openSubState(new OffsetCalibrationState());
				}
			}
		];

		createOptionTexts();
	}

	function createOptionTexts()
	{
		// Clear icon pools
		if (_buttonIcons != null)
			_buttonIcons.clear();
		if (_checkboxSprites != null)
			_checkboxSprites.clear();

		var isControlsTab = (categories[curCategory] == 'Controls');

		for (i in 0...currentOptions.length)
		{
			var opt = currentOptions[i];

			var nameText:FlxText = new FlxText(90, OPT_START_Y + (i * OPT_SPACING), 600, opt.name, 26);
			nameText.setFormat(Paths.font("Funkin.otf"), 26, FlxColor.WHITE, LEFT, OUTLINE, FlxColor.BLACK);
			nameText.borderSize = 2;
			nameText.ID = i;
			nameText.scrollFactor.set();
			nameText.antialiasing = SaveData.data.antialiasing;
			optionNames.add(nameText);

			var rawVal:String = opt.get();
			var isBool = (rawVal == 'ON' || rawVal == 'OFF');

			// ── Controls tab: try to show a controller button icon ────────────
			if (isControlsTab && opt.isKeybind == true)
			{
				var iconPlaced = false;
				if (_gamepadAtlas != null)
				{
					var frameName = _buttonNameToFrame(rawVal, _gamepadStyle);
					if (frameName != null)
					{
						var icon = new FlxSprite(FlxG.width - 120, OPT_START_Y + (i * OPT_SPACING) - 4);
						icon.frames = _gamepadAtlas;
						icon.animation.addByPrefix('idle', frameName, 1, false);
						icon.animation.play('idle');
						icon.setGraphicSize(40, 40);
						icon.updateHitbox();
						icon.scrollFactor.set();
						icon.antialiasing = SaveData.data.antialiasing;
						icon.ID = i;
						_buttonIcons.add(icon);
						iconPlaced = true;
					}
				}
				// Fallback to text if no icon available
				var valueText:FlxText = new FlxText(FlxG.width - 400, OPT_START_Y + (i * OPT_SPACING), iconPlaced ? 260 : 320, iconPlaced ? '' : rawVal, 26);
				valueText.setFormat(Paths.font("Funkin.otf"), 26, FlxColor.CYAN, RIGHT, OUTLINE, FlxColor.BLACK);
				valueText.antialiasing = SaveData.data.antialiasing;
				valueText.borderSize = 2;
				valueText.ID = i;
				valueText.scrollFactor.set();
				optionValues.add(valueText);

				isCheck = false;
			}
			// ── Boolean option: show animated checkbox sprite ────────────────
			else if (isBool && _checksAtlas != null)
			{
				// Invisible placeholder so optionValues index stays in sync
				var valueText:FlxText = new FlxText(0, 0, 0, '', 1);
				valueText.ID = i;
				valueText.visible = false;
				valueText.scrollFactor.set();
				optionValues.add(valueText);

				isCheck = true;

				var isOn = (rawVal == 'ON');

				// Build the animated checkbox using the Sparrow atlas
				var cb = new FlxSprite(FlxG.width - 120, OPT_START_Y + (i * OPT_SPACING) - 16);
				cb.frames = _checksAtlas;

				// Static end-states
				cb.animation.addByPrefix('checked', 'checked', 1, false);
				cb.animation.addByPrefix('unchecked', 'unchecked', 1, false);
				// Intro transitions (24 fps feels snappy but not jarring)
				cb.animation.addByPrefix('introchecked', 'introchecked', 24, false);
				cb.animation.addByPrefix('introunchecked', 'introunchecked', 24, false);

				// Settle to the matching static frame once the intro finishes
				cb.animation.finishCallback = function(name:String)
				{
					if (name == 'introchecked')
					{
						cb.animation.play('checked', true);
						FlxG.sound.play(Paths.sound('menus/options/check' + FlxG.random.int(1, 2)), 0.8);
					}
					if (name == 'introunchecked')
					{
						cb.animation.play('unchecked', true);
						FlxG.sound.play(Paths.sound('menus/options/check' + FlxG.random.int(1, 2)), 0.8);
					}
				};

				// Start directly on the correct stable state (no intro on first load)
				cb.animation.play(isOn ? 'checked' : 'unchecked');

				cb.scale.set(0.95, 0.95);
				cb.updateHitbox();
				cb.scrollFactor.set();
				cb.antialiasing = SaveData.data.antialiasing;
				cb.ID = i;
				_checkboxSprites.add(cb);
			}
			// ── Normal text value ─────────────────────────────────────────────
			else
			{
				var valueText:FlxText = new FlxText(FlxG.width - 400, OPT_START_Y + (i * OPT_SPACING), 320, rawVal, 26);
				valueText.setFormat(Paths.font("Funkin.otf"), 26, FlxColor.CYAN, RIGHT, OUTLINE, FlxColor.BLACK);
				valueText.antialiasing = SaveData.data.antialiasing;
				valueText.borderSize = 2;
				valueText.ID = i;
				valueText.scrollFactor.set();
				optionValues.add(valueText);

				isCheck = false;
			}
		}
	}

	// Recalcula _optScrollY para que curSelected siempre sea visible
	function _updateScroll()
	{
		if (currentOptions.length == 0)
			return;

		// Posición Y del item seleccionado (relativa al area, sin scroll)
		var itemY:Float = curSelected * OPT_SPACING;

		// Asegurar que el item seleccionado esté dentro del área visible
		if (itemY < _optScrollY)
			_optScrollY = itemY;
		if (itemY + OPT_SPACING > _optScrollY + OPT_VISIBLE_H)
			_optScrollY = itemY + OPT_SPACING - OPT_VISIBLE_H;

		// Clamp: no desplazar más allá del contenido
		var maxScroll:Float = Math.max(0, currentOptions.length * OPT_SPACING - OPT_VISIBLE_H);
		if (_optScrollY < 0)
			_optScrollY = 0;
		if (_optScrollY > maxScroll)
			_optScrollY = maxScroll;

		// Aplicar scroll a los textos
		var clip = new flixel.math.FlxRect(0, OPT_START_Y, FlxG.width, OPT_VISIBLE_H);

		optionNames.forEach(function(txt:FlxText)
		{
			txt.y = OPT_START_Y + (txt.ID * OPT_SPACING) - _optScrollY;
			txt.visible = (txt.y >= OPT_START_Y - OPT_SPACING) && (txt.y < OPT_START_Y + OPT_VISIBLE_H);
		});

		optionValues.forEach(function(txt:FlxText)
		{
			txt.y = OPT_START_Y + (txt.ID * OPT_SPACING) - _optScrollY;
			txt.visible = (txt.y >= OPT_START_Y - OPT_SPACING) && (txt.y < OPT_START_Y + OPT_VISIBLE_H);
		});

		// ── Actualizar flechas de scroll ─────────────────────────────────────
		if (_scrollArrowUp != null)
			_scrollArrowUp.visible = (_optScrollY > 0);
		if (_scrollArrowDown != null)
		{
			var maxScroll2:Float = Math.max(0, currentOptions.length * OPT_SPACING - OPT_VISIBLE_H);
			_scrollArrowDown.visible = (_optScrollY < maxScroll2 - 1);
		}
		{
			var totalH = currentOptions.length * OPT_SPACING;
			var needsBar = totalH > OPT_VISIBLE_H;
			_scrollbarTrack.visible = needsBar;
			_scrollbarThumb.visible = needsBar;
			if (needsBar)
			{
				// Altura del thumb proporcional al contenido visible
				var thumbH = Std.int(Math.max(20, OPT_VISIBLE_H * OPT_VISIBLE_H / totalH));
				var thumbTravel = OPT_VISIBLE_H - thumbH;
				var thumbY = OPT_START_Y + Std.int(thumbTravel * (_optScrollY / maxScroll));
				_scrollbarThumb.makeGraphic(SCROLLBAR_W, thumbH, 0xFFFFFFFF);
				_scrollbarThumb.y = thumbY;
			}
		}
		// Sync icon/checkbox sprite positions with scroll
		_syncIconScroll();
	}

	function updateCategoryDisplay()
	{
		var categoryWidth = (FlxG.width - 120) / categories.length;

		// Actualizar textos de categorías
		categoryTexts.forEach(function(txt:FlxText)
		{
			if (txt.ID == curCategory)
			{
				txt.color = FlxColor.WHITE;
				txt.setFormat(Paths.font("Funkin.otf"), 24, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);

				// Animar el texto
				FlxTween.cancelTweensOf(txt.scale);
				FlxTween.tween(txt.scale, {x: 1.05, y: 1.05}, 0.2, {ease: FlxEase.quadOut});
			}
			else
			{
				txt.color = 0xFF888888;
				txt.setFormat(Paths.font("Funkin.otf"), 22, 0xFF888888, CENTER, OUTLINE, FlxColor.BLACK);

				FlxTween.cancelTweensOf(txt.scale);
				FlxTween.tween(txt.scale, {x: 1, y: 1}, 0.2, {ease: FlxEase.quadOut});
			}
		});

		// Actualizar backgrounds de pestañas
		contentPanel.forEach(function(sprite:FlxSprite)
		{
			if (sprite.ID >= 0 && sprite.ID < categories.length)
			{
				if (sprite.ID == curCategory)
				{
					// Pestaña activa - más clara y brillante
					sprite.color = 0xFF2a2a2a;
					sprite.alpha = 1;
				}
				else
				{
					// Pestaña inactiva - más oscura
					sprite.color = 0xFF1a1a1a;
					sprite.alpha = 0.7;
				}
			}

			// Mover el indicador de pestaña activa
			if (sprite.ID == -1) // El indicador tiene ID -1
			{
				var targetX = 60 + (curCategory * categoryWidth);
				FlxTween.cancelTweensOf(sprite);
				FlxTween.tween(sprite, {x: targetX}, 0.3, {ease: FlxEase.quadOut});
			}
		});
	}

	function updateOptionDisplay()
	{
		optionNames.forEach(function(txt:FlxText)
		{
			if (txt.ID == curSelected)
			{
				txt.color = FlxColor.CYAN;
				txt.alpha = 1;

				// Animar el texto seleccionado
				FlxTween.cancelTweensOf(txt.scale);
				FlxTween.tween(txt.scale, {x: 1.08, y: 1.08}, 0.15, {ease: FlxEase.quadOut});
			}
			else
			{
				txt.color = FlxColor.WHITE;
				txt.alpha = 0.6;

				FlxTween.cancelTweensOf(txt.scale);
				FlxTween.tween(txt.scale, {x: 1, y: 1}, 0.15, {ease: FlxEase.quadOut});
			}
		});

		optionValues.forEach(function(txt:FlxText)
		{
			if (txt.ID == curSelected)
			{
				txt.alpha = 1;
				txt.color = FlxColor.YELLOW;

				// Animar el valor seleccionado
				FlxTween.cancelTweensOf(txt.scale);
				FlxTween.tween(txt.scale, {x: 1.08, y: 1.08}, 0.15, {ease: FlxEase.quadOut});
			}
			else
			{
				txt.alpha = 0.6;
				txt.color = FlxColor.CYAN;

				FlxTween.cancelTweensOf(txt.scale);
				FlxTween.tween(txt.scale, {x: 1, y: 1}, 0.15, {ease: FlxEase.quadOut});
			}

			// Only update text for non-checkbox, non-hidden value texts
			var rawVal = currentOptions[txt.ID].get();
			if (txt.visible)
				txt.text = rawVal;
		});

		// Sync checkbox sprites state and selection highlight
		syncCheckboxes();

		// Sync controller button icons (no-op if no gamepad atlas loaded)
		syncButtonIcons();

		// Sync button icon selection highlight
		if (_buttonIcons != null)
		{
			_buttonIcons.forEach(function(spr:FlxSprite)
			{
				spr.alpha = (spr.ID == curSelected) ? 1.0 : 0.7;
				FlxTween.cancelTweensOf(spr.scale);
				if (spr.ID == curSelected)
					FlxTween.tween(spr.scale, {x: 1.15, y: 1.15}, 0.15, {ease: FlxEase.quadOut});
				else
					FlxTween.tween(spr.scale, {x: 1.0, y: 1.0}, 0.15, {ease: FlxEase.quadOut});
			});
		}
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onUpdate', [elapsed]);
		#end

		// ── Guard de input: esperar a que se suelten todas las teclas de ACCEPT ──
		// Previene que el ENTER/SPACE usado para abrir el menú dispare
		// una acción en el primer frame.

		if (_inputGuard)
		{
			// BUG FIX #4: antes solo se bloqueaban ENTER/SPACE/Z hardcodeados.
			// Si el jugador tiene ACCEPT mapeado a otra tecla (X, gamepad A, etc.)
			// el guard no la detectaba y la primera opción se activaba sola.
			// Agregamos controls.ACCEPT para cubrir cualquier binding configurado.
			var acceptReleased = !FlxG.keys.pressed.ENTER
				&& !FlxG.keys.pressed.SPACE
				&& !FlxG.keys.pressed.Z
				&& !controls.ACCEPT;
			if (acceptReleased)
				_inputGuard = false;
			else
				return;
		}

		#if mobileC
		handleTouchInput();
		#end

		// ── Actualizar shaders de fondo ───────────────────────────────────────
		if (fromPause && _gridShader != null)
		{
			// Scroll horizontal: acumular tiempo * velocidad
			_gridShader.uTime.value[0] += elapsed * 0.12;
		}
		else if (!fromPause && _bgMenuShader != null)
		{
			_optColorTimer += elapsed;
			if (_optColorTimer >= OPT_COLOR_HOLD)
			{
				_optColorTimer = 0;
				_startOptColorTransition();
			}
		}

		// Si estamos esperando un keybind
		if (bindingState == "binding")
		{
			handleKeyBinding();
			return;
		}

		// ── Modo edición: A/D cambia el valor, ENTER o ESC confirma y sale ────
		if (_editMode)
		{
			final opt = currentOptions[curSelected];
			var changed = false;
			if (FlxG.keys.justPressed.A || FlxG.keys.justPressed.LEFT || controls.LEFT_P)
			{
				if (opt.left != null)
				{
					opt.left();
					changed = true;
				}
			}
			if (FlxG.keys.justPressed.D || FlxG.keys.justPressed.RIGHT || controls.RIGHT_P)
			{
				if (opt.right != null)
				{
					opt.right();
					changed = true;
				}
			}
			if (changed)
			{
				FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.7);
				updateOptionDisplay();
				SaveData.flush();
			}
			// Salir del modo edición con ENTER o ESC
			if (controls.ACCEPT || controls.BACK)
			{
				_editMode = false;
				_editModeIndicator.visible = false;
				var _exitVal = (currentOptions != null && curSelected < currentOptions.length) ? currentOptions[curSelected].get() : '';
				var _exitIsBool = (_exitVal == 'ON' || _exitVal == 'OFF');
				if (!_exitIsBool)
					FlxG.sound.play(Paths.sound('menus/confirmMenu'), 0.7);
				else
					FlxG.sound.play(Paths.sound('menus/options/press' + FlxG.random.int(1, 2)), 0.7);
			}
			return;
		}

		// Navegación de categorías con ← →
		if (controls.LEFT_P && currentOptions.length > 0)
		{
			changeCategory(-1);
		}
		if (controls.RIGHT_P && currentOptions.length > 0)
		{
			changeCategory(1);
		}

		// Navegación de opciones ↑ ↓
		if (controls.UP_P)
		{
			changeSelection(-1);
		}
		if (controls.DOWN_P)
		{
			changeSelection(1);
		}

		// Ajuste izquierda/derecha para opciones con slider (p.ej. FPS Cap)
		// Cuando NO estamos en modo edición y la opción tiene funciones left/right.
		if (categories[curCategory] != 'Controls' && currentOptions.length > 0)
		{
			final opt = currentOptions[curSelected];
			if (FlxG.keys.justPressed.A || FlxG.keys.justPressed.LEFT || controls.LEFT_P)
			{
				if (opt.left != null)
				{
					FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.7);
					opt.left();
					updateOptionDisplay();
				}
			}
			if (FlxG.keys.justPressed.D || FlxG.keys.justPressed.RIGHT || controls.RIGHT_P)
			{
				if (opt.right != null)
				{
					FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.7);
					opt.right();
					updateOptionDisplay();
				}
			}
		}

		// Aceptar/Toggle opción
		if (controls.ACCEPT && currentOptions.length > 0)
		{
			final opt = currentOptions[curSelected];

			// Si la opción tiene left/right (multi-valor), entrar en edit mode al pulsar ENTER
			if (opt.left != null || opt.right != null)
			{
				_editMode = true;
				_editModeIndicator.text = "⟵ A / D ⟶   Adjusting: " + opt.name + "   ENTER / ESC to confirm";
				_editModeIndicator.visible = true;
				FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.7);
				return;
			}

			var _acceptVal = opt.get();
			var _acceptBool = (_acceptVal == 'ON' || _acceptVal == 'OFF');
			if (!_acceptBool)
				FlxG.sound.play(Paths.sound('menus/confirmMenu'), 0.7);
			else
				FlxG.sound.play(Paths.sound('menus/options/press' + FlxG.random.int(1, 2)), 0.7);
			var optionName = opt.name;
			opt.toggle();
			updateOptionDisplay();
			SaveData.flush();

			// Si estamos en pause menu
			if (fromPause)
			{
				// Verificar si es una configuración SEGURA para aplicar en tiempo real
				if (isGameplaySetting(optionName))
				{
					applyGameplaySettingsRealtime();
				}
				// Si requiere reinicio y estamos en pausa dentro del PlayState → señalar rewind
				else if (requiresRestart(optionName))
				{
					if (fromPause && PlayState.instance != null)
					{
						SaveData.flush();
						pendingRewind = true;
						close(); // vuelve a PauseSubState que detectará pendingRewind
						isOpenOptions = false;
					}
					else
					{
						showWarning("Restart song to apply changes");
					}
				}
			}
		}

		// Reset keybinds con BACKSPACE (solo en Controls)
		if (FlxG.keys.justPressed.BACKSPACE && categories[curCategory] == 'Controls')
		{
			resetKeybinds();
		}

		// Volver
		if (controls.BACK)
		{
			FlxG.sound.play(Paths.sound('menus/cancelMenu'));

			if (fromPause)
			{
				fromPause = false;
				close();
				isOpenOptions = false;
			}
			else
			{
				StateTransition.switchState(funkin.scripting.ScriptBridge.resolveState('MainMenuState') ?? new MainMenuState());
			}
		}

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onUpdatePost', [elapsed]);
		#end
	}

	function changeCategory(change:Int)
	{
		FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.7);
		curCategory += change;

		if (curCategory < 0)
			curCategory = categories.length - 1;
		if (curCategory >= categories.length)
			curCategory = 0;

		loadCategory(curCategory);
	}

	function changeSelection(change:Int)
	{
		if (currentOptions.length == 0)
			return;

		FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.7);
		curSelected += change;

		if (curSelected < 0)
			curSelected = currentOptions.length - 1;
		if (curSelected >= currentOptions.length)
			curSelected = 0;

		updateOptionDisplay();
		_updateScroll();
	}

	// === KEYBIND FUNCTIONS ===

	function startBinding(keyIndex:Int)
	{
		bindingState = "binding";
		tempKey = keys[keyIndex];

		bindingIndicator.text = "Press any key or gamepad button for " + keyBindNames[keyIndex] + "...\nESC to cancel";
		bindingIndicator.visible = true;

		// Cambiar el valor mostrado a "?"
		optionValues.members[curSelected].text = "?";
	}

	function handleKeyBinding()
	{
		// Cancelar con ESC
		if (FlxG.keys.justPressed.ESCAPE)
		{
			keys[curSelected] = tempKey;
			bindingState = "select";
			bindingIndicator.visible = false;
			updateOptionDisplay();
			FlxG.sound.play(Paths.sound('menus/cancelMenu'));
			return;
		}

		// Detectar botón de gamepad
		var gamepad = FlxG.gamepads.lastActive;
		if (gamepad != null)
		{
			var gpButton = gamepad.firstJustPressedID();
			if (gpButton != FlxGamepadInputID.NONE)
			{
				// No permitir usar START como bind de dirección/reset (se usa para pausar)
				var gpName = gpButton.toString();
				var blocked = (gpName == 'START' && curSelected <= 4);
				if (!blocked)
				{
					// Guardar el gamepad binding: usamos prefijo "GP:" para diferenciarlo
					keys[curSelected] = 'GP:' + gpName;
					saveKeyBinds();
					bindingState = "select";
					bindingIndicator.visible = false;
					_rebuildControlsIconAt(curSelected, keys[curSelected]);
					updateOptionDisplay();
					FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.7);
					if (hasDuplicateKeys())
						showWarning("Warning: Duplicate keys detected");
				}
				else
				{
					keys[curSelected] = tempKey;
					showWarning("Invalid button! Button is blocked.");
					bindingState = "select";
					bindingIndicator.visible = false;
					updateOptionDisplay();
					FlxG.sound.play(Paths.sound('menus/cancelMenu'));
				}
				return;
			}
		}

		// Esperar cualquier tecla de teclado
		if (FlxG.keys.justPressed.ANY)
		{
			var pressedKey = FlxG.keys.getIsDown()[0].ID.toString();

			if (isKeyValid(pressedKey, curSelected))
			{
				keys[curSelected] = pressedKey;
				saveKeyBinds();
				bindingState = "select";
				bindingIndicator.visible = false;
				// Rebuild full icon list so new key shows correct icon (or text fallback)
				_rebuildControlsIconAt(curSelected, pressedKey);
				updateOptionDisplay();
				FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.7);

				// Advertir si hay duplicados (pero permitirlos)
				if (hasDuplicateKeys())
				{
					showWarning("Warning: Duplicate keys detected");
				}
			}
			else
			{
				// Mostrar warning
				keys[curSelected] = tempKey;
				showWarning("Invalid key! Key is blocked.");
				bindingState = "select";
				bindingIndicator.visible = false;
				updateOptionDisplay();
				FlxG.sound.play(Paths.sound('menus/cancelMenu'));
			}
		}
	}

	function isKeyValid(key:String, keyIndex:Int):Bool
	{
		// Gamepad bindings (GP: prefix) always valid — no keyboard-reserved restrictions apply
		if (key != null && key.startsWith('GP:'))
			return true;

		// SPACE nunca se permite (se usa para UI)
		if (key == "SPACE")
			return false;

		// Para controles de dirección (0-3) y RESET (4): no permitir teclas reservadas de sistema
		if (keyIndex <= 4)
		{
			if (key == "ESCAPE" || key == "ENTER" || key == "BACKSPACE")
				return false;
		}

		// Para RESET (4): no puede coincidir con direcciones
		if (keyIndex == 4)
		{
			for (i in 0...4)
				if (keys[i] == key)
					return false;
		}

		return true;
	}

	/**
	 * Verifica si hay teclas duplicadas en las direcciones
	 */
	function hasDuplicateKeys():Bool
	{
		for (i in 0...4)
		{
			for (j in i + 1...4)
			{
				if (keys[i] == keys[j])
					return true;
			}
		}
		return false;
	}

	function resetKeybinds()
	{
		FlxG.sound.play(Paths.sound('menus/confirmMenu'));

		for (i in 0...keyBindNames.length)
		{
			keys[i] = defaultKeys[i];
		}

		saveKeyBinds();
		loadCategory(curCategory); // Recargar para actualizar valores

		showWarning("Keybinds reset to default!");
	}

	function showWarning(text:String)
	{
		warningText.text = text;
		warningText.alpha = 1;

		FlxTween.tween(warningText, {alpha: 0}, 0.5, {
			ease: FlxEase.circOut,
			startDelay: 2
		});
	}

	/**
	 * Determina si una configuración es SEGURA para aplicar en tiempo real
	 * Solo configuraciones visuales/UI que no afectan la lógica del juego
	 */
	function isGameplaySetting(optionName:String):Bool
	{
		var safeGameplaySettings = [
			"Ghost Tapping", // Seguro: solo afecta siguiente input
			"Show HUD", // Seguro: solo visual
			// "Note Splashes" — REQUIERE RESTART: grpNoteSplashes se inicializa en create(),
			// simplemente cambiar .visible no basta cuando el warmup ya ocurrió.
			// Queda en requiresRestart() para forzar el rewind.
			"Accuracy Display", // Seguro: solo visual
			"Anti-Aliasing" // Seguro: solo visual
		];

		// Configuraciones que REQUIEREN REINICIO (NO en tiempo real):
		// - Downscroll: requiere reposicionar strums y notas en vuelo
		// - Middlescroll: requiere reorganizar layout completo
		// - Perfect Mode/Sick Mode: cambian lógica de scoring
		// - Static Stage: puede causar memory leaks

		return safeGameplaySettings.contains(optionName);
	}

	/**
	 * Verifica si una configuración requiere reiniciar la canción
	 */
	function requiresRestart(optionName:String):Bool
	{
		var restartRequired = [
			"Downscroll",
			"Middlescroll",
			"Note Splashes",
			"Perfect Mode",
			"Sick Mode",
			"Static Stage",
			"Special Visual Effects",
			"GF Bye",
			"Background Bye",
			"Render Resolution"
		];

		return restartRequired.contains(optionName);
	}

	/**
	 * Aplica el alpha del lane backdrop al PlayState activo si existe.
	 * Si no hay PlayState activo (options desde menú), el cambio solo se
	 * persiste en SaveData.data y se aplicará al siguiente gameplay.
	 */
	private function _applyLaneBackdropAlpha(alpha:Float):Void
	{
		if (funkin.gameplay.PlayState.instance != null && funkin.gameplay.PlayState.instance.laneBackdrop != null)
		{
			funkin.gameplay.PlayState.instance.laneBackdrop.alpha = alpha;
		}
	}

	/**
	 * Aplica las configuraciones de gameplay en tiempo real al PlayState
	 */
	function applyGameplaySettingsRealtime():Void
	{
		if (PlayState.instance != null)
		{
			trace('[OptionsMenuState] Applying gameplay settings in real-time');
			PlayState.instance.updateGameplaySettings();
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  HELPERS: Checkbox sync, controller detection, scroll of icons
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Syncs checkbox sprites state and selection highlight.
	 * Plays the intro transition animation when the value has changed,
	 * then the finishCallback (set in createOptionTexts) settles to the static frame.
	 */
	function syncCheckboxes():Void
	{
		if (_checkboxSprites == null)
			return;
		_checkboxSprites.forEach(function(cb:FlxSprite)
		{
			if (cb.ID >= currentOptions.length)
				return;

			final isOn = (currentOptions[cb.ID].get() == 'ON');
			final curName = (cb.animation.curAnim != null) ? cb.animation.curAnim.name : '';
			final stableAnim = isOn ? 'checked' : 'unchecked';
			final introAnim = isOn ? 'introchecked' : 'introunchecked';
			final wrongStable = isOn ? 'unchecked' : 'checked';
			final wrongIntro = isOn ? 'introunchecked' : 'introchecked';

			if (curName == stableAnim || curName == introAnim)
			{
				// Already in the correct state or mid-transition — don't interrupt
			}
			else if (curName == wrongStable || curName == wrongIntro)
			{
				// Value just flipped → play the intro transition
				cb.animation.play(introAnim, true);
			}
			else
			{
				// Unknown / uninitialised state — snap straight to stable
				cb.animation.play(stableAnim, true);
			}

			cb.alpha = (cb.ID == curSelected) ? 1.0 : 0.7;
		});
	}

	/**
	 * Syncs button icons (controller tab) after a keybind changes.
	 */
	function syncButtonIcons():Void
	{
		if (_buttonIcons == null || _gamepadAtlas == null)
			return;
		_buttonIcons.forEach(function(icon:FlxSprite)
		{
			if (icon.ID >= currentOptions.length)
				return;
			var rawVal:String = currentOptions[icon.ID].get();
			var frameName = _buttonNameToFrame(rawVal, _gamepadStyle);
			if (frameName != null && icon.animation.getByName(frameName) == null)
			{
				icon.animation.addByPrefix(frameName, frameName, 1, false);
				icon.animation.play(frameName);
			}
			else if (frameName != null)
			{
				icon.animation.play(frameName);
			}
			icon.alpha = (icon.ID == curSelected) ? 1.0 : 0.7;
		});
	}

	/**
	 * Applies scroll offset to icon/checkbox sprite pools, mirroring _updateScroll.
	 * Call after _updateScroll().
	 */
	function _syncIconScroll():Void
	{
		if (_buttonIcons != null)
		{
			_buttonIcons.forEach(function(spr:FlxSprite)
			{
				spr.y = OPT_START_Y + (spr.ID * OPT_SPACING) - _optScrollY - 4;
				spr.visible = (spr.y >= OPT_START_Y - OPT_SPACING) && (spr.y < OPT_START_Y + OPT_VISIBLE_H);
			});
		}
		if (_checkboxSprites != null)
		{
			_checkboxSprites.forEach(function(spr:FlxSprite)
			{
				spr.y = OPT_START_Y + (spr.ID * OPT_SPACING) - _optScrollY - 16;
				spr.visible = (spr.y >= OPT_START_Y - OPT_SPACING) && (spr.y < OPT_START_Y + OPT_VISIBLE_H);
			});
		}
	}

	/**
	 * Rebuilds the button icon for a single slot after a keybind changes.
	 * Much cheaper than rebuilding the entire list — just swaps the animation
	 * on the existing FlxSprite, or shows/hides it if the key type changes.
	 *
	 * Call this right after keys[idx] is updated, before updateOptionDisplay().
	 */
	function _rebuildControlsIconAt(idx:Int, newKey:String):Void
	{
		if (_buttonIcons == null)
			return;

		var frameName:Null<String> = (_gamepadAtlas != null) ? _buttonNameToFrame(newKey, _gamepadStyle) : null;

		// Find existing icon sprite for this slot
		var existingIcon:FlxSprite = null;
		_buttonIcons.forEach(function(spr:FlxSprite)
		{
			if (spr.ID == idx)
				existingIcon = spr;
		});

		if (frameName != null)
		{
			if (existingIcon != null)
			{
				// Reuse existing sprite — just play the new animation
				if (existingIcon.animation.getByName(frameName) == null)
					existingIcon.animation.addByPrefix(frameName, frameName, 1, false);
				existingIcon.animation.play(frameName);
				existingIcon.visible = true;
			}
			else
			{
				// No icon existed for this slot yet — create one
				var icon = new FlxSprite(FlxG.width - 120, OPT_START_Y + (idx * OPT_SPACING) - 4);
				icon.frames = _gamepadAtlas;
				icon.animation.addByPrefix(frameName, frameName, 1, false);
				icon.animation.play(frameName);
				icon.setGraphicSize(40, 40);
				icon.updateHitbox();
				icon.scrollFactor.set();
				icon.antialiasing = SaveData.data.antialiasing;
				icon.ID = idx;
				_buttonIcons.add(icon);
				// Hide the text value for this slot
				optionValues.forEach(function(txt:FlxText)
				{
					if (txt.ID == idx)
					{
						txt.text = '';
						txt.visible = false;
					}
				});
			}
		}
		else
		{
			// No icon for this key — hide icon sprite, show text fallback
			if (existingIcon != null)
				existingIcon.visible = false;
			optionValues.forEach(function(txt:FlxText)
			{
				if (txt.ID == idx)
				{
					txt.text = _displayKey(newKey);
					txt.visible = true;
				}
			});
		}
	}

	// ── Gamepad detection ─────────────────────────────────────────────────────

	/**
	 * Converts an internal key/binding string to a human-readable label.
	 * "GP:A"        → "🎮 A"
	 * "GP:DPAD_UP"  → "🎮 D-Up"
	 * "W"           → "W"
	 */
	static function _displayKey(raw:String):String
	{
		if (raw == null) return '?';
		if (!raw.startsWith('GP:')) return raw;
		var btn = raw.substr(3);
		// Friendlier names for common buttons
		btn = switch (btn.toUpperCase())
		{
			case 'DPAD_UP':    'D-Up';
			case 'DPAD_DOWN':  'D-Down';
			case 'DPAD_LEFT':  'D-Left';
			case 'DPAD_RIGHT': 'D-Right';
			case 'LEFT_STICK_DIGITAL_UP':    'LS-Up';
			case 'LEFT_STICK_DIGITAL_DOWN':  'LS-Down';
			case 'LEFT_STICK_DIGITAL_LEFT':  'LS-Left';
			case 'LEFT_STICK_DIGITAL_RIGHT': 'LS-Right';
			case 'LEFT_STICK_CLICK':  'LS-Click';
			case 'RIGHT_STICK_CLICK': 'RS-Click';
			case 'LEFT_SHOULDER':  'LB';
			case 'RIGHT_SHOULDER': 'RB';
			case 'LEFT_TRIGGER':   'LT';
			case 'RIGHT_TRIGGER':  'RT';
			default: btn;
		}
		return '🎮 $btn';
	}

	/**
	 * Returns "ps" | "xbox" | "switch" | null based on connected gamepads.
	 * Priority: first detected gamepad wins.
	 */
	static function _detectGamepadStyle():Null<String>
	{
		#if FLX_GAMEPADS
		var pads = FlxG.gamepads.getActiveGamepads();
		if (pads != null && pads.length > 0)
		{
			var name = (pads[0].name ?? '').toLowerCase();
			if (name.contains('xbox') || name.contains('xinput') || name.contains('microsoft'))
				return 'xbox';
			if (name.contains('dualshock') || name.contains('dualsense') || name.contains('playstation') || name.contains('ps4') || name.contains('ps5'))
				return 'ps';
			if (name.contains('nintendo') || name.contains('joy-con') || name.contains('pro controller') || name.contains('switch'))
				return 'switch';
			// Generic/unknown gamepad → default to xbox layout
			return 'xbox';
		}
		#end
		return null;
	}

	/**
	 * Loads the Sparrow atlas for the given gamepad style from
	 * assets/images/menu/options/controls/<style>.png+xml.
	 * Returns null if the files don't exist or no style given.
	 */
	static function _loadGamepadAtlas(style:Null<String>):Null<flixel.graphics.frames.FlxAtlasFrames>
	{
		if (style == null)
			return null;
		#if sys
		var pngPath = 'assets/images/menu/options/controls/$style.png';
		var xmlPath = 'assets/images/menu/options/controls/$style.xml';
		if (!sys.FileSystem.exists(pngPath) || !sys.FileSystem.exists(xmlPath))
		{
			trace('[OptionsMenu] No gamepad atlas for style "$style" at $pngPath');
			return null;
		}
		#end
		try
		{
			return Paths.getSparrowAtlas('menu/options/controls/$style');
		}
		catch (_)
		{
			return null;
		}
	}

	/**
	 * Maps a key/button name string to the frame prefix in the gamepad atlas.
	 * Returns null if there is no matching frame (caller falls back to text).
	 *
	 * Frame names in the atlases (from the XMLs):
	 *   PS:     X, circle, square, triangle, up, down, left, right, options, share, play
	 *   Xbox:   A, B, X, Y, up, down, left, right, options, share
	 *   Switch: A, B, X, Y, up, down, left, right, home, minus, plus, screen
	 */
	static function _buttonNameToFrame(keyName:String, style:Null<String>):Null<String>
	{
		if (style == null || keyName == null)
			return null;
		// Strip GP: prefix if present (gamepad binding saved by handleKeyBinding)
		var raw = keyName.startsWith('GP:') ? keyName.substr(3) : keyName;
		var k = raw.toUpperCase();

		// D-pad directions — same across all controllers
		// FlxGamepadInputID.toString() returns "DPAD_UP" etc.
		if (k == 'UP' || k == 'DPAD_UP')
			return 'up';
		if (k == 'DOWN' || k == 'DPAD_DOWN')
			return 'down';
		if (k == 'LEFT' || k == 'DPAD_LEFT')
			return 'left';
		if (k == 'RIGHT' || k == 'DPAD_RIGHT')
			return 'right';

		switch (style)
		{
			case 'ps':
				return switch (k)
				{
					case 'CROSS' | 'X': 'X';
					case 'CIRCLE' | 'B': 'circle';
					case 'SQUARE' | 'Q': 'square';
					case 'TRIANGLE' | 'T': 'triangle';
					case 'OPTIONS' | 'START': 'options';
					case 'SHARE' | 'SELECT' | 'BACK': 'share';
					case 'PLAY' | 'TOUCHPAD': 'play';
					default: null;
				};
			case 'xbox':
				return switch (k)
				{
					case 'A' | 'CROSS': 'A';
					case 'B' | 'CIRCLE': 'B';
					case 'X' | 'SQUARE': 'X';
					case 'Y' | 'TRIANGLE': 'Y';
					case 'START' | 'OPTIONS' | 'MENU': 'options';
					case 'SELECT' | 'BACK' | 'SHARE': 'share';
					default: null;
				};
			case 'switch':
				return switch (k)
				{
					case 'A' | 'CROSS': 'A';
					case 'B' | 'CIRCLE': 'B';
					case 'X' | 'SQUARE': 'X';
					case 'Y' | 'TRIANGLE': 'Y';
					case 'HOME': 'home';
					case 'MINUS' | 'SELECT' | 'BACK': 'minus';
					case 'PLUS' | 'START' | 'OPTIONS': 'plus';
					case 'SCREEN' | 'CAPTURE': 'screen';
					default: null;
				};
			default:
				return null;
		}
	}

	// === CLASE DE COMPATIBILIDAD PARA Main.hx ===

	/**
	 * Inicia la transición al siguiente color de paleta para el fondo del menú de opciones.
	 */
	function _startOptColorTransition():Void
	{
		if (_bgMenuShader == null)
			return;

		if (_optColorTween != null)
		{
			_optColorTween.cancel();
			_optColorTween = null;
		}

		_optPaletteIdx = (_optPaletteIdx + 1) % OPT_PALETTE.length;
		var nextIdx:Int = (_optPaletteIdx + 1) % OPT_PALETTE.length;

		var cA = OPT_PALETTE[_optPaletteIdx];
		var cB = OPT_PALETTE[nextIdx];
		_bgMenuShader.setColorA(cA[0], cA[1], cA[2]);
		_bgMenuShader.setColorB(cB[0], cB[1], cB[2]);
		_bgMenuShader.setBlend(0.0);

		var blendProxy = {v: 0.0};
		_optColorTween = FlxTween.tween(blendProxy, {v: 1.0}, OPT_COLOR_TRANS, {
			ease: FlxEase.sineInOut,
			onUpdate: function(_)
			{
				if (_bgMenuShader != null)
					_bgMenuShader.setBlend(blendProxy.v);
			},
			onComplete: function(_)
			{
				if (_bgMenuShader != null)
				{
					_bgMenuShader.setColorA(cB[0], cB[1], cB[2]);
					_bgMenuShader.setBlend(0.0);
				}
				_optColorTween = null;
			}
		});
	}

	/**
	 * Inicializa los valores por defecto de las opciones
	 * Llamado desde Main.hx
	 */
	public static function initSave():Void
	{
		OptionsData.initSave();
	}

	override function destroy()
	{
		// Cancelar tweens de color para evitar referencias colgantes
		if (_optColorTween != null)
		{
			_optColorTween.cancel();
			_optColorTween = null;
		}
		_bgMenuShader = null;
		_gridShader = null;

		// BUGFIX: limpiar listeners de hot-plug
		FlxG.gamepads.deviceConnected.remove(_onGamepadConnectedInMenu);
		FlxG.gamepads.deviceDisconnected.remove(_onGamepadDisconnectedInMenu);

		super.destroy();
	}

	// ── Gamepad hot-plug handlers ─────────────────────────────────────────────

	/**
	 * Llamado cuando se conecta un mando mientras el menú está abierto.
	 * Re-detecta el estilo (PS / Xbox / Switch) y recarga el atlas de iconos
	 * para que los botones mostrados correspondan al mando recién conectado.
	 */
	function _onGamepadConnectedInMenu(gamepad:flixel.input.gamepad.FlxGamepad):Void
	{
		_gamepadStyle = _detectGamepadStyle();
		_gamepadAtlas = _loadGamepadAtlas(_gamepadStyle);
		createOptionTexts(); // reconstruye la lista con los nuevos iconos
		trace('[OptionsMenu] Gamepad conectado (id=${gamepad.id}), estilo=$_gamepadStyle');
	}

	/**
	 * Llamado cuando se desconecta un mando mientras el menú está abierto.
	 * Si ya no quedan mandos, limpia el estilo y los iconos para volver
	 * a mostrar las teclas de teclado.
	 */
	function _onGamepadDisconnectedInMenu(gamepad:flixel.input.gamepad.FlxGamepad):Void
	{
		_gamepadStyle = _detectGamepadStyle(); // null si no queda ninguno
		_gamepadAtlas = _loadGamepadAtlas(_gamepadStyle);
		createOptionTexts();
		trace('[OptionsMenu] Gamepad desconectado (id=${gamepad.id})');
	}
}

/**
 * Clase de compatibilidad con el sistema antiguo
 */
class OptionsData
{
	public static function initSave():Void
	{
		if (SaveData.data.downscroll == null)
			SaveData.data.downscroll = false;

		if (SaveData.data.sustainMiss == null)
			SaveData.data.sustainMiss = true;

		// ── Display / Resolution ──────────────────────────────────────────────
		if (SaveData.data.renderResolution == null)
			SaveData.data.renderResolution = '1080p'; // '720p' o '1080p'

		if (SaveData.data.scaleMode == null)
			SaveData.data.scaleMode = 'letterbox'; // 'letterbox', 'widescreen', 'stretch', 'pixel'

		if (SaveData.data.shaders == null)
			SaveData.data.shaders = true;

		if (SaveData.data.vsync == null)
			// En móvil el VSync evita el tearing sin coste apreciable porque
			// el framerate ya está fijado a 60 fps. En desktop se deja OFF
			// para no forzar la sincronía a quien usa un monitor de alta frecuencia.
			SaveData.data.vsync = #if (android || ios || mobileC) true #else false #end;

		if (SaveData.data.accuracyDisplay == null)
			SaveData.data.accuracyDisplay = true;

		if (SaveData.data.notesplashes == null)
			SaveData.data.notesplashes = true;

		if (SaveData.data.middlescroll == null)
			SaveData.data.middlescroll = false;

		if (SaveData.data.HUD == null)
			SaveData.data.HUD = false;

		if (SaveData.data.flashing == null)
			SaveData.data.flashing = true;

		if (SaveData.data.offset == null)
			SaveData.data.offset = 0;

		if (SaveData.data.sickmode == null)
			SaveData.data.sickmode = false;

		if (SaveData.data.specialVisualEffects == null)
			SaveData.data.specialVisualEffects = true;

		if (SaveData.data.ghosttap == null)
			SaveData.data.ghosttap = true;

		if (SaveData.data.hitsounds == null)
			SaveData.data.hitsounds = false;

		if (SaveData.data.antialiasing == null)
			SaveData.data.antialiasing = true;

		// ── Keybinds ──────────────────────────────────────────────────────────
		// Inicializar defaults aquí para que loadKeyBinds() nunca lea null
		// (FlxKey.fromString(null) devuelve NONE=0, lo que puede disparar
		// capturas accidentales si el ScreenshotPlugin se inicializa antes).
		if (SaveData.data.leftBind == null)
			SaveData.data.leftBind = "A";
		if (SaveData.data.downBind == null)
			SaveData.data.downBind = "S";
		if (SaveData.data.upBind == null)
			SaveData.data.upBind = "W";
		if (SaveData.data.rightBind == null)
			SaveData.data.rightBind = "D";
		if (SaveData.data.killBind == null)
			SaveData.data.killBind = "R";
		if (SaveData.data.acceptBind == null)
			SaveData.data.acceptBind = "ENTER";
		if (SaveData.data.backBind == null)
			SaveData.data.backBind = "ESCAPE";
		if (SaveData.data.pauseBind == null)
			SaveData.data.pauseBind = "ENTER";
		if (SaveData.data.screenshotBind == null)
			SaveData.data.screenshotBind = "F12";
		if (SaveData.data.cheatBind == null)
			SaveData.data.cheatBind = "SEVEN";

		// ── PathsCache: GPU texture caching ──────────────────────────────────
		// Por defecto activo en desktop (false en web/mobile sin context3D fiable).
		// Cuando está activo, los bitmaps se suben a VRAM y la copia en RAM se
		// libera → ahorro de ~4 MB por textura 1024×1024.
		if (SaveData.data.gpuCaching == null)
			SaveData.data.gpuCaching = #if (desktop && !hl) true #else false #end;

		// Sincronizar con PathsCache al arrancar
		funkin.cache.PathsCache.gpuCaching = SaveData.data.gpuCaching;

		// ── Low Memory Mode (inspirado en Codename Engine) ───────────────────
		if (SaveData.data.lowMemoryMode == null)
			SaveData.data.lowMemoryMode = false;
		funkin.cache.PathsCache.lowMemoryMode = SaveData.data.lowMemoryMode;

		// ── Streamed Music (no cachear audio de canciones) ───────────────────
		if (SaveData.data.streamedMusic == null)
			SaveData.data.streamedMusic = false;
		funkin.cache.PathsCache.streamedMusic = SaveData.data.streamedMusic;

		// ── Mobile controls ───────────────────────────────────────────────────
		#if mobileC
		if (SaveData.data.mobileAlpha == null)
			SaveData.data.mobileAlpha = 0.75;
		// mobilePadLayout se inicializa como null → Mobilecontrols usará posiciones default
		if (SaveData.data.vibration == null)
			SaveData.data.vibration = true;
		if (SaveData.data.vibrationIntensity == null)
			SaveData.data.vibrationIntensity = "medium";
		#end

		// ── Gamepad rumble (todas las plataformas con FLX_GAMEPADS) ──────────
		if (SaveData.data.gamepadRumble == null)
			SaveData.data.gamepadRumble = true;
		// vibrationIntensity es compartida entre móvil y gamepad
		if (SaveData.data.vibrationIntensity == null)
			SaveData.data.vibrationIntensity = "medium";
	}
}

/**
 * OffsetCalibrationState — Calibración de offset de audio al estilo pro.
 *
 * Reproduce un click track generado por código a exactamente 120 BPM.
 * El usuario presiona SPACE en cada beat; tras 8 taps se calcula el offset
 * como promedio de (tiempo_tap - tiempo_beat_más_cercano).
 *
 * Teclas:
 *   SPACE   → Tap en el beat
 *   ← / →   → Ajustar offset ±1 ms manualmente
 *   R       → Resetear taps
 *   ESC     → Guardar y salir
 */
class OffsetCalibrationState extends MusicBeatSubstate
{
	// ── Constantes de ritmo ───────────────────────────────────────────────────
	static final BPM:Float = 120.0;
	static final BEAT_SEC:Float = 60.0 / BPM; // 0.5 s
	static final MAX_TAPS:Int = 8;
	static final CLICK_MUSIC:String = "offsetMusic";
	static final CLICK_SOUND:String = "menus/chartingSounds/metronome";

	// ── Estado del metrónomo ──────────────────────────────────────────────────
	var _beatTimer:Float = 0.0;
	var _beatCount:Int = 0;

	/** Timestamps de cada click (segundos absolutos desde apertura). */
	var _clickTimes:Array<Float> = [];

	/** Timestamps de cada tap del usuario. */
	var _tapTimes:Array<Float> = [];

	/** Tiempo transcurrido desde que se abrió el substate. */
	var _elapsed:Float = 0.0;

	/** Countdown inicial de 2 s antes de empezar. */
	var _countdown:Float = 2.0;

	var _counting:Bool = true;

	// ── UI ────────────────────────────────────────────────────────────────────
	var _panel:FlxSprite;
	var _pulseDot:FlxSprite;
	var _tapBar:FlxSprite; // Barra de progreso de taps
	var _tapBarFill:FlxSprite;
	var _offsetTxt:FlxText;
	var _tapsTxt:FlxText;
	var _feedbackTxt:FlxText;
	var _countdownTxt:FlxText;
	var _resultsTxt:FlxText;

	// Línea de tiempo visual — último tap vs último beat
	var _timelineBg:FlxSprite;
	var _timelineBeat:FlxSprite;
	var _timelineTap:FlxSprite;

	var _cam:flixel.FlxCamera;

	override function create()
	{
		super.create();
		funkin.audio.SoundTray.blockInput = true; // No cambiar volumen con +/-

		MusicManager.playWithFade(CLICK_MUSIC, 0.7, 4.0);

		_cam = OptionsMenuState.fromPause ? FlxG.cameras.list[FlxG.cameras.list.length - 1] : FlxG.camera;

		// ── Fondo oscuro ──────────────────────────────────────────────────────
		var bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xFF000000);
		bg.alpha = 0.88;
		bg.cameras = [_cam];
		add(bg);

		// ── Panel central ─────────────────────────────────────────────────────
		_panel = new FlxSprite(0, 0).makeGraphic(820, 580, 0xFF141428);
		_panel.screenCenter();
		_panel.cameras = [_cam];
		add(_panel);

		// Borde del panel
		var border = new FlxSprite(_panel.x - 2, _panel.y - 2).makeGraphic(824, 584, 0xFF5555FF);
		border.alpha = 0.4;
		border.cameras = [_cam];
		add(border);

		// ── Título ────────────────────────────────────────────────────────────
		var title = new FlxText(0, _panel.y + 24, FlxG.width, "OFFSET CALIBRATION", 38);
		title.setFormat(Paths.font("vcr.ttf"), 38, FlxColor.WHITE, CENTER, OUTLINE, 0xFF5555FF);
		title.borderSize = 2;
		title.cameras = [_cam];
		add(title);

		var bpmLabel = new FlxText(0, _panel.y + 68, FlxG.width, "♩ = " + Std.int(BPM) + " BPM", 18);
		bpmLabel.setFormat(Paths.font("vcr.ttf"), 18, 0xFF8888FF, CENTER);
		bpmLabel.cameras = [_cam];
		add(bpmLabel);

		// ── Instrucciones ─────────────────────────────────────────────────────
		var instr = new FlxText(0, _panel.y
			+ 100, FlxG.width,
			"Press SPACE in sync with the metronome beat.\nRepeat "
			+ MAX_TAPS
			+ " times to calculate offset.", 20);
		instr.setFormat(Paths.font("vcr.ttf"), 20, 0xFFCCCCCC, CENTER);
		instr.cameras = [_cam];
		add(instr);

		// ── Punto pulsante central ────────────────────────────────────────────
		_pulseDot = new FlxSprite(0, _panel.y + 200).makeGraphic(80, 80, 0xFF5555FF);
		_pulseDot.screenCenter(X);
		_pulseDot.alpha = 0.15;
		_pulseDot.cameras = [_cam];
		add(_pulseDot);

		// ── Línea de tiempo (diff visual entre tap y beat) ────────────────────
		_timelineBg = new FlxSprite(0, _panel.y + 305).makeGraphic(500, 6, 0xFF333355);
		_timelineBg.screenCenter(X);
		_timelineBg.cameras = [_cam];
		add(_timelineBg);

		// Marcador central (= beat perfecto)
		var centerMark = new FlxSprite(_timelineBg.x + 247, _panel.y + 296).makeGraphic(6, 24, 0xFF5555FF);
		centerMark.cameras = [_cam];
		add(centerMark);

		// Indicador de beat (azul, siempre en el centro)
		_timelineBeat = new FlxSprite(_timelineBg.x + 247, _panel.y + 299).makeGraphic(6, 18, 0xFF4488FF);
		_timelineBeat.cameras = [_cam];
		add(_timelineBeat);

		// Indicador de tap (amarillo, se mueve según el error)
		_timelineTap = new FlxSprite(_timelineBg.x + 247, _panel.y + 299).makeGraphic(6, 18, FlxColor.YELLOW);
		_timelineTap.cameras = [_cam];
		_timelineTap.alpha = 0;
		add(_timelineTap);

		var earlyLabel = new FlxText(_timelineBg.x - 2, _panel.y + 315, 50, "EARLY", 11);
		earlyLabel.cameras = [_cam];
		earlyLabel.setFormat(Paths.font("vcr.ttf"), 11, 0xFF8888CC, LEFT);
		add(earlyLabel);
		var lateLabel = new FlxText(_timelineBg.x + 460, _panel.y + 315, 50, "LATE", 11);
		lateLabel.cameras = [_cam];
		lateLabel.setFormat(Paths.font("vcr.ttf"), 11, 0xFF8888CC, RIGHT);
		add(lateLabel);

		// ── Barra de progreso de taps ─────────────────────────────────────────
		_tapBar = new FlxSprite(0, _panel.y + 345).makeGraphic(500, 16, 0xFF222244);
		_tapBar.screenCenter(X);
		_tapBar.cameras = [_cam];
		add(_tapBar);
		_tapBarFill = new FlxSprite(_tapBar.x, _tapBar.y).makeGraphic(4, 16, 0xFF5555FF);
		_tapBarFill.cameras = [_cam];
		add(_tapBarFill);

		// ── Textos de estado ─────────────────────────────────────────────────
		_tapsTxt = new FlxText(0, _panel.y + 368, FlxG.width, "Taps: 0 / " + MAX_TAPS, 20);
		_tapsTxt.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.WHITE, CENTER);
		_tapsTxt.cameras = [_cam];
		add(_tapsTxt);

		_feedbackTxt = new FlxText(0, _panel.y + 396, FlxG.width, "", 18);
		_feedbackTxt.setFormat(Paths.font("vcr.ttf"), 18, FlxColor.YELLOW, CENTER, OUTLINE, FlxColor.BLACK);
		_feedbackTxt.borderSize = 1;
		_feedbackTxt.cameras = [_cam];
		add(_feedbackTxt);

		_resultsTxt = new FlxText(0, _panel.y + 422, FlxG.width, "", 22);
		_resultsTxt.setFormat(Paths.font("vcr.ttf"), 22, FlxColor.LIME, CENTER, OUTLINE, FlxColor.BLACK);
		_resultsTxt.borderSize = 2;
		_resultsTxt.cameras = [_cam];
		add(_resultsTxt);

		// ── Offset actual ─────────────────────────────────────────────────────
		_offsetTxt = new FlxText(0, _panel.y + 462, FlxG.width, "Current Offset: " + (SaveData.data.offset ?? 0) + " ms", 26);
		_offsetTxt.setFormat(Paths.font("vcr.ttf"), 26, FlxColor.YELLOW, CENTER, OUTLINE, FlxColor.BLACK);
		_offsetTxt.borderSize = 2;
		_offsetTxt.cameras = [_cam];
		add(_offsetTxt);

		// ── Controles ─────────────────────────────────────────────────────────
		var ctrl = new FlxText(0, _panel.y + 510, FlxG.width, "SPACE: Tap  |  ← →: ±1 ms  |  R: Reset  |  ESC: Save & Back", 15);
		ctrl.setFormat(Paths.font("vcr.ttf"), 15, 0xFF888888, CENTER);
		ctrl.cameras = [_cam];
		add(ctrl);

		// ── Countdown overlay ─────────────────────────────────────────────────
		_countdownTxt = new FlxText(0, 0, FlxG.width, "2", 90);
		_countdownTxt.setFormat(Paths.font("vcr.ttf"), 90, FlxColor.WHITE, CENTER, OUTLINE, 0xFF5555FF);
		_countdownTxt.borderSize = 4;
		_countdownTxt.screenCenter(Y);
		_countdownTxt.cameras = [_cam];
		add(_countdownTxt);

		if (SaveData.data.offset == null)
			SaveData.data.offset = 0;
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		_elapsed += elapsed;

		// ── Countdown ─────────────────────────────────────────────────────────
		if (_counting)
		{
			_countdown -= elapsed;
			var display = Math.ceil(_countdown);
			_countdownTxt.text = display > 0 ? Std.string(display) : "GO!";
			_countdownTxt.alpha = FlxMath.lerp(_countdownTxt.alpha, _countdown > 0 ? 1.0 : 0.0, elapsed * 8);

			if (_countdown <= -0.3)
			{
				_counting = false;
				_countdownTxt.visible = false;
				_beatTimer = 0;
				_elapsed = 0;
			}
			return; // no input durante countdown
		}

		// ── Metrónomo ─────────────────────────────────────────────────────────
		_beatTimer += elapsed;
		if (_beatTimer >= BEAT_SEC)
		{
			_beatTimer -= BEAT_SEC;
			_beatCount++;
			FlxG.sound.play(Paths.soundRandom(CLICK_SOUND, 1, 2), 0.3);
			_clickTimes.push(_elapsed - _beatTimer); // tiempo exacto del beat
			_pulseDot.alpha = 1.0;
			_pulseDot.scale.set(1.35, 1.35);
		}

		// Animar punto pulsante
		_pulseDot.alpha = FlxMath.lerp(_pulseDot.alpha, 0.12, elapsed * 9);
		_pulseDot.scale.x = FlxMath.lerp(_pulseDot.scale.x, 1.0, elapsed * 9);
		_pulseDot.scale.y = FlxMath.lerp(_pulseDot.scale.y, 1.0, elapsed * 9);
		_pulseDot.updateHitbox();
		_pulseDot.screenCenter(X);

		// Fade del indicador de tap en la timeline
		if (_timelineTap.alpha > 0)
			_timelineTap.alpha = FlxMath.lerp(_timelineTap.alpha, 0.0, elapsed * 3);

		// ── Input ─────────────────────────────────────────────────────────────
		if (FlxG.keys.justPressed.SPACE)
			_doTap();

		if (FlxG.keys.justPressed.LEFT || FlxG.keys.justPressed.A)
		{
			SaveData.data.offset -= 1;
			_updateOffsetTxt();
			FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.7);
		}
		if (FlxG.keys.justPressed.RIGHT || FlxG.keys.justPressed.D)
		{
			SaveData.data.offset += 1;
			_updateOffsetTxt();
			FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.7);
		}

		if (FlxG.keys.justPressed.R)
			_reset();

		if (FlxG.keys.justPressed.ESCAPE || controls.BACK)
		{
			funkin.audio.SoundTray.blockInput = false;
			SaveData.flush();
			FlxG.sound.play(Paths.sound('menus/cancelMenu'));
			funkin.system.CursorManager.hide();
			if (!OptionsMenuState.fromPause)
				MusicManager.playWithFade('configurator', 0.7, 4.0);
			close();
		}
	}

	function _doTap():Void
	{
		if (_beatCount == 0)
			return; // Esperar al menos un beat

		// Calcular diferencia con el beat más cercano
		var tapTime = _elapsed - _beatTimer; // tiempo absoluto del tap en la escala del metrónomo
		var beatPhase = _beatTimer; // fracción de beat actual (0 = justo en el beat)
		// Normalizar al rango [-BEAT_SEC/2, BEAT_SEC/2]
		var diff = beatPhase;
		if (diff > BEAT_SEC / 2)
			diff -= BEAT_SEC;
		var diffMs = Std.int(diff * 1000);

		_tapTimes.push(diffMs);
		_tapsTxt.text = "Taps: " + _tapTimes.length + " / " + MAX_TAPS;

		// Barra de progreso
		var pct = Math.min(1.0, _tapTimes.length / MAX_TAPS);
		_tapBarFill.makeGraphic(Std.int(Math.max(4, Std.int(500 * pct))), 16, 0xFF5555FF);

		// Timeline visual: posición del tap relativa al beat
		var lineW:Float = 500;
		var halfBeat = BEAT_SEC / 2;
		var normDiff = (diff / halfBeat) * 0.5; // -0.5 .. +0.5
		_timelineTap.x = _timelineBg.x + 247 + normDiff * lineW * 0.5;
		_timelineTap.alpha = 1.0;
		_timelineTap.color = diffMs < -20 ? 0xFF4488FF : diffMs > 20 ? FlxColor.RED : FlxColor.LIME;

		// Feedback inmediato
		if (Math.abs(diffMs) < 15)
			_feedbackTxt.text = "Perfect!";
		else if (diffMs < 0)
			_feedbackTxt.text = "Early (" + diffMs + " ms)";
		else
			_feedbackTxt.text = "Late (+" + diffMs + " ms)";

		FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.7);

		if (_tapTimes.length >= MAX_TAPS)
			_calculateOffset();
	}

	function _calculateOffset():Void
	{
		var sum:Float = 0;
		for (t in _tapTimes)
			sum += t;
		var avg = Std.int(sum / _tapTimes.length);

		SaveData.data.offset = avg;
		_updateOffsetTxt();
		_resultsTxt.text = "Calculated: " + avg + " ms — Saved!";
		FlxG.sound.play(Paths.sound('menus/confirmMenu'));

		// Flash del panel
		_pulseDot.alpha = 1.0;
		_pulseDot.color = FlxColor.LIME;
		_tapTimes = [];
		_tapsTxt.text = "Taps: 0 / " + MAX_TAPS;
		_tapBarFill.makeGraphic(4, 16, 0xFF5555FF);
	}

	function _reset():Void
	{
		_tapTimes = [];
		_tapsTxt.text = "Taps: 0 / " + MAX_TAPS;
		_feedbackTxt.text = "";
		_resultsTxt.text = "";
		_tapBarFill.makeGraphic(4, 16, 0xFF5555FF);
		SaveData.data.offset = 0;
		_updateOffsetTxt();
		FlxG.sound.play(Paths.sound('menus/cancelMenu'), 0.6);
	}

	function _updateOffsetTxt():Void
	{
		_offsetTxt.text = "Current Offset: " + (SaveData.data.offset ?? 0) + " ms";
	}
}

// ─────────────────────────────────────────────────────────────────────────────

/**
 * RatingPositionSubState — Editor visual de posición del popup de rating.
 *
 * Muestra una recreación simplificada del HUD de gameplay y un popup de
 * rating de ejemplo que el usuario puede mover con WASD / flechas o arrastrando
 * con el ratón. Guarda los offsets en SaveData.data.ratingOffsetX / ratingOffsetY.
 */
class RatingPositionSubState extends FlxSubState
{
	// Offset acumulado (píxeles desde la posición base del juego)
	var _offsetX:Null<Float> = 0;
	var _offsetY:Null<Float> = 0;

	// Sprites de la preview
	var _ratingPreview:FlxSprite;
	var _previewBorder:FlxSprite; // BUGFIX: guardado como member para actualizarlo en _applyPosition
	var _sickLabel:FlxText;
	var _comboPreview:Array<FlxSprite> = [];

	// HUD simulado
	var _healthBarFill:FlxSprite;
	var _scoreTxt:FlxText;

	// UI del editor
	var _crosshairH:FlxSprite;
	var _crosshairV:FlxSprite;
	var _positionTxt:FlxText;

	// Velocidad de movimiento (px/frame)
	static final MOVE_SPEED:Float = 2.0;
	static final FAST_SPEED:Float = 10.0;

	// Posición base del rating (igual que en script.hx por defecto)
	var _baseX:Float;
	var _baseY:Float;

	// Demo bounce
	var _demoTimer:Float = 0.0;

	// ── Mouse drag ────────────────────────────────────────────────────────────
	var _dragging:Bool = false;
	var _dragStartMouseX:Float = 0;
	var _dragStartMouseY:Float = 0;
	var _dragStartOffX:Null<Float> = 0;
	var _dragStartOffY:Null<Float> = 0;

	var _cam:flixel.FlxCamera;

	var posX:Float = 0;
	var posY:Float = 0;

	function onInit()
	{
		// Leer los offsets guardados (default: posición base original = -50, 0)
		posX = (SaveData.data.ratingOffsetX != null) ? SaveData.data.ratingOffsetX : -100;
		posY = (SaveData.data.ratingOffsetY != null) ? SaveData.data.ratingOffsetY : 0;
	}

	override function create()
	{
		super.create();

		_cam = OptionsMenuState.fromPause ? FlxG.cameras.list[FlxG.cameras.list.length - 1] : FlxG.camera;

		_offsetX = SaveData.data.ratingOffsetX != null ? SaveData.data.ratingOffsetX : 0;
		_offsetY = SaveData.data.ratingOffsetY != null ? SaveData.data.ratingOffsetY : 0;

		// ── Fondo oscuro ──────────────────────────────────────────────────────
		var bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		bg.alpha = 0.82;
		bg.scrollFactor.set();
		bg.cameras = [_cam];
		add(bg);

		// ── HUD simulado ──────────────────────────────────────────────────────
		_buildSimulatedHUD();

		// ── Posición base ─────────────────────────────────────────────────────
		_baseX = FlxG.width * 0.55 - 40;
		_baseY = FlxG.height * 0.5 - 90;

		// Línea de referencia Y base
		var refLine = new FlxSprite(0, _baseY).makeGraphic(FlxG.width, 1, 0xFF5555FF);
		refLine.alpha = 0.30;
		refLine.scrollFactor.set();
		refLine.cameras = [_cam];
		add(refLine);

		var baseRef = new FlxText(_baseX, _baseY - 14, 0, "▼ BASE", 11);
		baseRef.setFormat(Paths.font("vcr.ttf"), 11, 0xFF5555FF, LEFT);
		baseRef.scrollFactor.set();
		baseRef.cameras = [_cam];
		add(baseRef);

		// ── Crosshairs ────────────────────────────────────────────────────────
		_crosshairH = new FlxSprite(0, 0).makeGraphic(FlxG.width, 1, 0xFFFFFF00);
		_crosshairH.alpha = 0.30;
		_crosshairH.scrollFactor.set();
		_crosshairH.cameras = [_cam];
		add(_crosshairH);

		_crosshairV = new FlxSprite(0, 0).makeGraphic(1, FlxG.height, 0xFFFFFF00);
		_crosshairV.alpha = 0.30;
		_crosshairV.scrollFactor.set();
		_crosshairV.cameras = [_cam];
		add(_crosshairV);

		onInit();

		// BUGFIX: el borde se añade ANTES del rating preview para que quede detrás.
		// Antes se añadía después (encima) y sin posición (quedaba en x=0, y=0).
		// Ahora es un member var para poder actualizarlo en _applyPosition().
		_previewBorder = new FlxSprite();
		_previewBorder.makeGraphic(204, 94, 0xFF5555FF);
		_previewBorder.alpha = 0.6;
		_previewBorder.scrollFactor.set();
		_previewBorder.cameras = [_cam];
		add(_previewBorder);

		// ── Rating preview ────────────────────────────────────────────────────
		_ratingPreview = new FlxSprite(FlxG.width * 0.55 - 40 + posX, FlxG.height * 0.5 - 90 + posY);
		_ratingPreview.loadGraphic(Paths.image('UI/normal/score/sick'));
		_ratingPreview.setGraphicSize(Std.int(_ratingPreview.width * 0.7));
		_ratingPreview.antialiasing = SaveData.data.antialiasing;
		_ratingPreview.updateHitbox();
		_ratingPreview.scrollFactor.set();
		_ratingPreview.cameras = [_cam];
		add(_ratingPreview);

		_sickLabel = new FlxText(0, 0, 200, "SICK!", 32);
		_sickLabel.setFormat(Paths.font("vcr.ttf"), 32, 0xFFCCCCFF, CENTER, OUTLINE, FlxColor.BLACK);
		_sickLabel.borderSize = 2;
		_sickLabel.visible = false;
		_sickLabel.scrollFactor.set();
		_sickLabel.cameras = [_cam];
		add(_sickLabel);

		// Números del combo de demo
		for (i in 0...3)
		{
			var num = new FlxSprite();
			num.makeGraphic(40, 40, 0xFF1A2244);
			num.scrollFactor.set();
			num.cameras = [_cam];
			add(num);
			_comboPreview.push(num);
		}

		// Etiqueta "drag me"
		var dragLabel = new FlxText(0, 0, 200, "drag me ↕↔", 11);
		dragLabel.setFormat(Paths.font("vcr.ttf"), 11, 0xFF888888, CENTER);
		dragLabel.scrollFactor.set();
		dragLabel.cameras = [_cam];
		add(dragLabel);

		// ── Panel inferior ────────────────────────────────────────────────────
		var infoBg = new FlxSprite(0, FlxG.height - 64).makeGraphic(FlxG.width, 64, 0xFF0A0A1A);
		infoBg.alpha = 0.95;
		infoBg.scrollFactor.set();
		infoBg.cameras = [_cam];
		add(infoBg);

		_positionTxt = new FlxText(0, FlxG.height - 58, FlxG.width, "", 18);
		_positionTxt.setFormat(Paths.font("vcr.ttf"), 18, FlxColor.WHITE, CENTER);
		_positionTxt.scrollFactor.set();
		_positionTxt.cameras = [_cam];
		add(_positionTxt);

		var hint = new FlxText(0, FlxG.height - 36, FlxG.width, "WASD/Arrows: Move  |  SHIFT: Fast  |  Mouse Drag  |  R: Reset  |  ENTER/ESC: Save", 14);
		hint.setFormat(Paths.font("vcr.ttf"), 14, 0xFF888888, CENTER);
		hint.scrollFactor.set();
		hint.cameras = [_cam];
		add(hint);

		// ── Título superior ───────────────────────────────────────────────────
		var titleBg = new FlxSprite(0, 0).makeGraphic(FlxG.width, 36, 0xFF0A0A1A);
		titleBg.alpha = 0.92;
		titleBg.scrollFactor.set();
		titleBg.cameras = [_cam];
		add(titleBg);

		var title = new FlxText(0, 6, FlxG.width, "RATING POSITION EDITOR", 20);
		title.setFormat(Paths.font("vcr.ttf"), 20, 0xFF8888FF, CENTER);
		title.scrollFactor.set();
		title.cameras = [_cam];
		add(title);

		funkin.system.CursorManager.show();
		_applyPosition();
		_updateUI();
	}

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		// ── Mouse drag ────────────────────────────────────────────────────────
		if (FlxG.mouse.justPressed)
		{
			// Solo iniciar drag si el clic está sobre el rating preview
			var mx = FlxG.mouse.x;
			var my = FlxG.mouse.y;
			if (mx >= _ratingPreview.x
				&& mx <= _ratingPreview.x + _ratingPreview.width
				&& my >= _ratingPreview.y
				&& my <= _ratingPreview.y + _ratingPreview.height + 50)
			{
				_dragging = true;
				_dragStartMouseX = mx;
				_dragStartMouseY = my;
				_dragStartOffX = _offsetX;
				_dragStartOffY = _offsetY;
			}
		}

		if (FlxG.mouse.justReleased)
			_dragging = false;

		if (_dragging)
		{
			_offsetX = _dragStartOffX + Std.int(FlxG.mouse.x - _dragStartMouseX);
			_offsetY = _dragStartOffY + Std.int(FlxG.mouse.y - _dragStartMouseY);
			_applyPosition();
			_updateUI();
		}

		// ── Teclado ───────────────────────────────────────────────────────────
		if (!_dragging)
		{
			var fast = FlxG.keys.pressed.SHIFT;
			var speed = fast ? FAST_SPEED : MOVE_SPEED;
			var moved = false;

			if (FlxG.keys.pressed.LEFT || FlxG.keys.pressed.A)
			{
				_offsetX -= Std.int(speed);
				moved = true;
			}
			if (FlxG.keys.pressed.RIGHT || FlxG.keys.pressed.D)
			{
				_offsetX += Std.int(speed);
				moved = true;
			}
			if (FlxG.keys.pressed.UP || FlxG.keys.pressed.W)
			{
				_offsetY -= Std.int(speed);
				moved = true;
			}
			if (FlxG.keys.pressed.DOWN || FlxG.keys.pressed.S)
			{
				_offsetY += Std.int(speed);
				moved = true;
			}

			if (FlxG.keys.justPressed.R)
			{
				_offsetX = 0;
				_offsetY = 0;
				moved = true;
				FlxG.sound.play(Paths.sound('menus/cancelMenu'), 0.6);
			}

			if (moved)
			{
				_applyPosition();
				_updateUI();
			}
		}

		// Demo bounce
		_demoTimer += elapsed;
		var bounce = Math.sin(_demoTimer * 3.5) * 3;
		if (!_dragging)
			_ratingPreview.y = _baseY + _offsetY + bounce;

		// Cursor de mano cuando está sobre el rating
		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;
		var overPreview = (mx >= _ratingPreview.x
			&& mx <= _ratingPreview.x + _ratingPreview.width
			&& my >= _ratingPreview.y
			&& my <= _ratingPreview.y + _ratingPreview.height + 50);
		FlxG.mouse.useSystemCursor = !overPreview;

		// Sincronizar sickLabel y combo con ratingPreview.y (que puede estar en bounce)
		_sickLabel.x = _ratingPreview.x;
		_sickLabel.y = _ratingPreview.y + 20;
		for (i in 0..._comboPreview.length)
			_comboPreview[i].setPosition(_ratingPreview.x + (44 * i) - 10 + 140, _ratingPreview.y + _ratingPreview.height + 4);

		if (FlxG.keys.justPressed.ENTER || FlxG.keys.justPressed.ESCAPE)
		{
			FlxG.mouse.useSystemCursor = false;
			_save();
			close();
		}
	}

	function _buildSimulatedHUD():Void
	{
		var hbY = FlxG.height * 0.88;

		var hbBg = new FlxSprite(0, hbY).makeGraphic(600, 22, 0xFF333333);
		hbBg.screenCenter(X);
		hbBg.scrollFactor.set();
		hbBg.cameras = [_cam];
		add(hbBg);

		_healthBarFill = new FlxSprite(hbBg.x + 2, hbY + 2).makeGraphic(296, 18, 0xFF66FF33);
		_healthBarFill.scrollFactor.set();
		_healthBarFill.cameras = [_cam];
		add(_healthBarFill);

		// Iconos de salud simulados
		var iconP1 = new FlxSprite(hbBg.x + 296 - 20, hbY - 10).makeGraphic(30, 30, 0xFF44AAFF);
		iconP1.scrollFactor.set();
		iconP1.cameras = [_cam];
		add(iconP1);
		var iconP2 = new FlxSprite(hbBg.x + 296 - 48, hbY - 10).makeGraphic(30, 30, 0xFFFF4444);
		iconP2.scrollFactor.set();
		iconP2.cameras = [_cam];
		add(iconP2);

		_scoreTxt = new FlxText(0, hbY - 28, FlxG.width, "Score: 123,456   Misses: 0   Acc: 100.00%", 18);
		_scoreTxt.setFormat(Paths.font("vcr.ttf"), 18, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		_scoreTxt.borderSize = 1;
		_scoreTxt.scrollFactor.set();
		_scoreTxt.cameras = [_cam];
		add(_scoreTxt);
	}

	function _applyPosition():Void
	{
		var rx:Float = _baseX + _offsetX;
		var ry:Float = _baseY + _offsetY;

		_ratingPreview.x = rx;
		_ratingPreview.y = ry;

		// BUGFIX: actualizar el borde para que siga al rating preview
		if (_previewBorder != null)
		{
			_previewBorder.x = rx - 2;
			_previewBorder.y = ry - 2;
		}

		_crosshairH.y = ry + _ratingPreview.height / 2;
		_crosshairV.x = rx + _ratingPreview.width / 2;
	}

	function _updateUI():Void
	{
		var label = (_offsetX == 0 && _offsetY == 0) ? "  (default)" : "";
		_positionTxt.text = 'Offset   X: $_offsetX px    Y: $_offsetY px$label';
	}

	function _save():Void
	{
		SaveData.data.ratingOffsetX = _offsetX;
		SaveData.data.ratingOffsetY = _offsetY;
		SaveData.flush();
		FlxG.sound.play(Paths.sound('menus/confirmMenu'));
	}
}
