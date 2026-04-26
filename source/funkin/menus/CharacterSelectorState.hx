package funkin.menus;
import coolui.CoolInputText;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import funkin.gameplay.objects.character.Character.CharacterData;
import funkin.gameplay.objects.character.Character.AnimData;
import funkin.gameplay.objects.character.CharacterList;
import funkin.gameplay.objects.character.HealthIcon;
import funkin.debug.editors.AnimationDebug;
import funkin.debug.themes.EditorTheme;
import funkin.states.MusicBeatState;
import funkin.transitions.StateTransition;
import funkin.menus.MainMenuState;
import ui.Alphabet;
import haxe.Json;
#if sys
import sys.FileSystem;
import sys.io.File;
import lime.ui.FileDialog;
import funkin.audio.MusicManager;
#end

using StringTools;

/**
 * CharacterSelectorState
 *
 * Lista de personajes al estilo FreeplayEditor.
 * "+ NEW CHARACTER" arriba abre un wizard de 2 pasos:
 *   Paso 1 – Nombre del personaje
 *   Paso 2 – Importar assets (sprite, FlxAnimate, ícono)
 * Al terminar → AnimationDebug con el nuevo personaje.
 *
 * ENTER en personaje existente → AnimationDebug directo.
 * DELETE → confirmar borrado.
 */
class CharacterSelectorState extends MusicBeatState
{
	// ── Lista ─────────────────────────────────────────────────────────────────
	private var grpChars:FlxTypedGroup<Alphabet>;
	private var iconArray:Array<HealthIcon> = [];
	private var charNames:Array<String>     = [];
	private static var curSelected:Int = 0;

	// ── BG / colores ──────────────────────────────────────────────────────────
	private var bg:FlxSprite;
	private var colorTween:FlxTween;
	private var intendedColor:Int;

	// ── Visual bars ───────────────────────────────────────────────────────────
	private var visualBars:FlxTypedGroup<FlxSprite>;
	private var beatTimer:Float  = 0;
	private var glowOverlay:FlxSprite;

	// ── UI ────────────────────────────────────────────────────────────────────
	private var charInfoText:FlxText;
	private var helpText:FlxText;

	// ── Wizard "New Character" ────────────────────────────────────────────────
	// 0 = cerrado, 1 = paso nombre, 2 = paso importar
	private var wizardStep:Int = 0;

	// Panel visual compartido
	private var wizardPanel:FlxSprite;
	private var wizardBorder:FlxSprite;

	// Paso 1 – nombre
	private var step1Group:FlxTypedGroup<FlxSprite>;  // sprites del paso 1
	private var step1Texts:Array<FlxText> = [];
	private var nameInput:CoolInputText;
	private var nameHint:FlxText;

	// Paso 2 – import
	private var step2Texts:Array<FlxText> = [];
	private var step2Btns:Array<flixel.ui.FlxButton> = [];

	// Estado del wizard
	private var wizardCharName:String  = "";  // nombre confirmado en paso 1
	private var importedSpritePath:String = ""; // ruta base importada (para path del JSON)
	private var importedIsFlxAnimate:Bool = false;
	private var importedIsTxt:Bool        = false;
	private var importedSpritemapName:String = "spritemap1";
	private var importedAnimData:Array<AnimData> = [];
	private var statusLine:FlxText;           // línea de estado en paso 2

	// ── Confirm delete ────────────────────────────────────────────────────────
	private var delPanel:FlxSprite;
	private var delPanelBorder:FlxSprite;
	private var delText:FlxText;
	private var delHint:FlxText;
	private var pendingDelete:String = null;

	// ── Deferred wizard transitions ───────────────────────────────────────────
	//
	// CoolInputText fires onEnterPressed / onEscapePressed via a native OpenFL
	// KeyboardEvent listener.  That event runs synchronously inside (or just
	// before) the Flixel update loop, which means FlxG.keys.justPressed can
	// ALSO be true for the same key on the same frame — even after
	// FlxG.keys.reset() — because FlxKeyboard.update() re-detects a key that
	// is still physically held.
	//
	// Consequence without this fix:
	//   • Enter in step 1 → confirmName() sets wizardStep=2, then the step-2
	//     code sees justPressed.ENTER and calls finishWizard() immediately.
	//   • Escape in step 1 → closeWizard() sets wizardStep=0, then
	//     controls.BACK sees the Escape key and switches to MainMenuState.
	//
	// Fix: callbacks set a one-frame flag instead of calling the transition
	// directly.  The flags are consumed at the very top of update(), before
	// any key checks, and a `return` prevents the rest of update() from
	// running that frame.
	private var _step2Pending:Bool    = false;  // step 1 → 2 (Enter confirmed)
	private var _wizClosePending:Bool = false;  // wizard close (Escape pressed)

	// ── Constantes ────────────────────────────────────────────────────────────
	static inline var PW:Int = 520;       // panel width
	static inline var DAD_PATH:String = "DADDY_DEAREST";

	// ─────────────────────────────────────────────────────────────────────────

	override function create():Void
	{
		EditorTheme.load();
		funkin.system.CursorManager.show();
		// MusicManager solo cambia si 'configurator' no está sonando ya.
		// Resetear la flag solo cuando realmente se cambia la pista.
		if (!MusicManager.isPlaying('configurator'))
			MusicManager.play('configurator', 0.7);

		#if (HSCRIPT_ALLOWED || (LUA_ALLOWED && linc_luajit))
		funkin.scripting.StateScriptHandler.init();
		funkin.scripting.StateScriptHandler.loadStateScripts('CharacterSelectorState', this);
		funkin.scripting.StateScriptHandler.callOnScripts('onCreate', []);
		#end
		
		loadCharList();

		// ── BG ────────────────────────────────────────────────────────────────
		bg = new FlxSprite();
		try   { bg.loadGraphic(Paths.image('menu/menuBG')); }
		catch (_) { bg.makeGraphic(FlxG.width, FlxG.height, 0xFF0A0A14); }
		bg.color = EditorTheme.current.bgDark;
		bg.scrollFactor.set(0.1, 0.1);
		add(bg);

		var grad = new FlxSprite();
		grad.makeGraphic(FlxG.width, FlxG.height, FlxColor.TRANSPARENT, true);
		for (i in 0...FlxG.height)
		{
			var a = Std.int((i / FlxG.height) * 0xAA);
			grad.pixels.fillRect(new flash.geom.Rectangle(0, i, FlxG.width, 1), a << 24);
		}
		grad.pixels.unlock();
		add(grad);

		intendedColor = EditorTheme.current.bgDark;

		// ── Visual bars ───────────────────────────────────────────────────────
		visualBars = new FlxTypedGroup<FlxSprite>();
		add(visualBars);
		for (i in 0...10)
		{
			var bar = new FlxSprite(i * 140, FlxG.height - 50);
			bar.makeGraphic(120, 220, FlxColor.fromRGB(80 + i * 15, 120, 220 - i * 10));
			bar.alpha = 0.22;
			bar.scrollFactor.set();
			visualBars.add(bar);
		}

		// ── Lista ─────────────────────────────────────────────────────────────
		grpChars = new FlxTypedGroup<Alphabet>();
		add(grpChars);
		buildList();

		// ── Glow ──────────────────────────────────────────────────────────────
		glowOverlay = new FlxSprite();
		glowOverlay.makeGraphic(FlxG.width, FlxG.height, FlxColor.WHITE);
		glowOverlay.alpha = 0;
		glowOverlay.blend = ADD;
		add(glowOverlay);

		// ── Info top-right ────────────────────────────────────────────────────
		var infoBg = new FlxSprite(FlxG.width - 270, 15);
		infoBg.makeGraphic(260, 50, 0xCC000000);
		add(infoBg);

		charInfoText = new FlxText(FlxG.width - 260, 20, 250, "", 16);
		charInfoText.setFormat(Paths.font("vcr.ttf"), 16, FlxColor.WHITE, RIGHT);
		charInfoText.setBorderStyle(OUTLINE, FlxColor.BLACK, 2);
		add(charInfoText);

		// ── Barra inferior ────────────────────────────────────────────────────
		var bar = new FlxSprite(0, FlxG.height - 30);
		bar.makeGraphic(FlxG.width, 30, 0xFF000000);
		bar.alpha = 0.85;
		add(bar);

		helpText = new FlxText(0, FlxG.height - 26, FlxG.width,
			"ENTER: Edit  |  N: New Character  |  DELETE: Remove  |  ESC: Back", 14);
		helpText.setFormat("VCR OSD Mono", 14, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(helpText);

		var label = new FlxText(12, FlxG.height - 26, 0, "CHARACTER EDITOR", 14);
		label.setFormat("VCR OSD Mono", 14, EditorTheme.current.accent, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		add(label);

		// ── Botón tema ────────────────────────────────────────────────────────
		var themeBtn = new flixel.ui.FlxButton(FlxG.width - 88, 4, "✨ Theme", function()
		{
			openSubState(new funkin.debug.themes.ThemePickerSubState());
		});
		add(themeBtn);

		// ── Wizard panel (oculto) ─────────────────────────────────────────────
		buildWizardPanel();

		// ── Delete confirm panel ──────────────────────────────────────────────
		buildDeletePanel();

		changeSelection();

		#if mobileC
		addTouchMenuControls(true, false); // ↑↓ swipe + tap=ACCEPT + hold/edge=BACK
		#end

		super.create();

		#if (HSCRIPT_ALLOWED || (LUA_ALLOWED && linc_luajit))
		funkin.scripting.StateScriptHandler.refreshStateFields(this);
		funkin.scripting.StateScriptHandler.callOnScripts('postCreate', []);
		#end
	}

	// ── Lista ─────────────────────────────────────────────────────────────────

	function loadCharList():Void
	{
		CharacterList.reload();
		charNames = CharacterList.getAllCharacters();
	}

	function buildList():Void
	{
		grpChars.clear();
		for (ic in iconArray) { remove(ic); ic.destroy(); }
		iconArray = [];

		var addEntry = new Alphabet(0, 30, "+ NEW CHARACTER", true, false);
		addEntry.isMenuItem = true;
		addEntry.targetY = 0;
		grpChars.add(addEntry);

		var addIcon = new HealthIcon("face");
		addIcon.sprTracker = addEntry;
		iconArray.push(addIcon);
		add(addIcon);

		for (i in 0...charNames.length)
		{
			var lbl = new Alphabet(0, (70 * (i + 1)) + 30, charNames[i], true, false);
			lbl.isMenuItem = true;
			lbl.targetY = i + 1;
			grpChars.add(lbl);

			var ic = new HealthIcon(charNames[i]);
			ic.sprTracker = lbl;
			iconArray.push(ic);
			add(ic);
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	// WIZARD PANEL
	// ─────────────────────────────────────────────────────────────────────────

	function buildWizardPanel():Void
	{
		var ph = 260;
		var px = (FlxG.width - PW) / 2;
		var py = (FlxG.height - ph) / 2;

		wizardPanel = new FlxSprite(px, py);
		wizardPanel.makeGraphic(PW, ph, 0xF00A0A18);
		wizardPanel.scrollFactor.set();
		wizardPanel.visible = false;
		add(wizardPanel);

		wizardBorder = new FlxSprite(px, py);
		wizardBorder.makeGraphic(PW, 3, EditorTheme.current.accent);
		wizardBorder.scrollFactor.set();
		wizardBorder.visible = false;
		add(wizardBorder);

		// ── Paso 1 – nombre ───────────────────────────────────────────────────
		var t1 = makeWizTxt(px + 14, py + 12, PW - 28, "STEP 1 / 2  —  Character Name", 14, EditorTheme.current.accent);
		step1Texts.push(t1); add(t1);

		var t2 = makeWizTxt(px + 14, py + 38, PW - 28, "Enter a unique ID for the character (no spaces or special chars):", 11, FlxColor.WHITE);
		step1Texts.push(t2); add(t2);

		nameInput = new CoolInputText(Std.int(px) + 14, Std.int(py) + 62, PW - 28, "my-character", 14);
		nameInput.scrollFactor.set();
		nameInput.visible = false;
		add(nameInput);

		nameHint = makeWizTxt(px + 14, py + 96, PW - 28, "", 11, FlxColor.YELLOW);
		step1Texts.push(nameHint); add(nameHint);

		var t3 = makeWizTxt(px + 14, py + 226, PW - 28, "ENTER: Continue  |  ESC: Cancel", 11, 0xFFAAAAAA);
		step1Texts.push(t3); add(t3);

		// ── Paso 2 – import ───────────────────────────────────────────────────
		var h1 = makeWizTxt(px + 14, py + 12, PW - 28, "STEP 2 / 2  —  Import Assets", 14, EditorTheme.current.accent);
		step2Texts.push(h1); add(h1);

		var sub = makeWizTxt(px + 14, py + 34, PW - 28,
			"Import your sprite files. You can skip any section and add them later in the editor.", 10, 0xFFBBBBBB);
		step2Texts.push(sub); add(sub);

		// --- Sección Sprite normal
		var secA = makeWizTxt(px + 14, py + 60, 0, "▸ STANDARD SPRITE", 11, FlxColor.CYAN);
		step2Texts.push(secA); add(secA);

		var btnSprite = makeWizBtn(Std.int(px) + 14, Std.int(py) + 76, "Import PNG + XML/TXT", function()
		{
			importStandardSprite();
		});
		step2Btns.push(btnSprite); add(btnSprite);

		// --- Sección FlxAnimate
		var secB = makeWizTxt(px + 14, py + 114, 0, "▸ FLXANIMATE (Adobe Animate)", 11, FlxColor.ORANGE);
		step2Texts.push(secB); add(secB);

		var btnFA = makeWizBtn(Std.int(px) + 14, Std.int(py) + 130, "Import Spritemap PNG", function()
		{
			importFlxAnimate();
		});
		step2Btns.push(btnFA); add(btnFA);

		// --- Sección Ícono
		var secC = makeWizTxt(px + 14, py + 168, 0, "▸ HEALTH ICON  (300×150px, 2 frames)", 11, FlxColor.LIME);
		step2Texts.push(secC); add(secC);

		var btnIcon = makeWizBtn(Std.int(px) + 14, Std.int(py) + 184, "Import Icon PNG", function()
		{
			importIcon();
		});
		step2Btns.push(btnIcon); add(btnIcon);

		// --- Línea de estado
		statusLine = makeWizTxt(px + 14, py + 218, PW - 28, "No assets imported yet  (you can import later in the editor)", 10, 0xFF888888);
		step2Texts.push(statusLine); add(statusLine);

		var footer = makeWizTxt(px + 14, py + 238, PW - 28,
			"ENTER: Open in Editor  |  BACKSPACE: Back  |  ESC: Cancel", 11, 0xFFAAAAAA);
		step2Texts.push(footer); add(footer);

		// Ocultar todo
		setWizVisible(false);
	}

	// ── Helpers de construcción ───────────────────────────────────────────────

	function makeWizTxt(x:Float, y:Float, w:Float, s:String, size:Int, col:FlxColor):FlxText
	{
		var t = new FlxText(x, y, w, s, size);
		t.setFormat("VCR OSD Mono", size, col, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		t.scrollFactor.set();
		t.visible = false;
		return t;
	}

	function makeWizBtn(x:Int, y:Int, label:String, cb:Void->Void):flixel.ui.FlxButton
	{
		var btn = new flixel.ui.FlxButton(x, y, label, cb);
		btn.scrollFactor.set();
		btn.visible = false;
		return btn;
	}

	// ── Show / hide ───────────────────────────────────────────────────────────

	function setWizVisible(v:Bool):Void
	{
		wizardPanel.visible  = v;
		wizardBorder.visible = v;
		nameInput.visible    = v && (wizardStep == 1);
		for (t in step1Texts) t.visible = v && (wizardStep == 1);
		for (t in step2Texts) t.visible = v && (wizardStep == 2);
		for (b in step2Btns)  b.visible = v && (wizardStep == 2);
	}

	function openWizard():Void
	{
		wizardStep = 1;
		wizardCharName = "";
		importedSpritePath   = "";
		importedIsFlxAnimate = false;
		importedIsTxt        = false;
		importedSpritemapName = "spritemap1";
		importedAnimData     = [];

		nameHint.text  = "";
		nameInput.text = "my-character";

		// Handle ENTER/ESC via native callbacks (FlxG.keys is disabled while the
		// native TextField has focus; _onFocusIn sets keys.enabled = false).
		nameInput.onEnterPressed  = function() { confirmName(); };
		// FIX: set flag instead of calling closeWizard() directly.  The native
		// KeyboardEvent fires before (or during) FlxG.keys.update(), so calling
		// closeWizard() here sets wizardStep=0 and re-enables FlxG.keys, which
		// lets controls.BACK fire on the same frame and switch to MainMenuState.
		nameInput.onEscapePressed = function() { _wizClosePending = true; };
		// Auto re-focus if the user clicks outside the input while still on step 1.
		nameInput.onFocusLost = function() { if (wizardStep == 1) nameInput.hasFocus = true; };

		// setWizVisible BEFORE hasFocus so FlxSpriteGroup.set_visible() doesn't
		// un-hide the Flixel sprites after _onFocusIn already hid them.
		setWizVisible(true);
		nameInput.hasFocus = true;

		wizardPanel.alpha = 0;
		wizardBorder.alpha = 0;
		FlxTween.cancelTweensOf(wizardPanel);
		FlxTween.tween(wizardPanel,  {alpha: 1}, 0.18, {ease: FlxEase.quartOut});
		FlxTween.tween(wizardBorder, {alpha: 1}, 0.18, {ease: FlxEase.quartOut});

		helpText.text = "ENTER: Continue  |  ESC: Cancel";
	}

	function goToStep2():Void
	{
		wizardStep = 2;
		// Clear callbacks BEFORE hasFocus=false so onFocusLost doesn't re-focus.
		nameInput.onFocusLost     = null;
		nameInput.onEnterPressed  = null;
		nameInput.onEscapePressed = null;
		nameInput.hasFocus = false;
		statusLine.text  = "No assets imported yet  (you can import later in the editor)";
		statusLine.color = 0xFF888888;
		setWizVisible(true);
		helpText.text = "ENTER: Open in Editor  |  BACKSPACE: Back  |  ESC: Cancel";
	}

	function closeWizard():Void
	{
		// Clear callbacks BEFORE hasFocus=false so onFocusLost doesn't re-focus.
		nameInput.onFocusLost     = null;
		nameInput.onEnterPressed  = null;
		nameInput.onEscapePressed = null;
		nameInput.hasFocus = false;
		wizardStep = 0;
		FlxTween.cancelTweensOf(wizardPanel);
		FlxTween.tween(wizardPanel, {alpha: 0}, 0.14, {ease: FlxEase.quartIn, onComplete: function(_)
		{
			setWizVisible(false);
		}});
		FlxTween.tween(wizardBorder, {alpha: 0}, 0.14, {ease: FlxEase.quartIn});
		helpText.text = "ENTER: Edit  |  N: New Character  |  DELETE: Remove  |  ESC: Back";
	}

	// ── Lógica paso 1 ─────────────────────────────────────────────────────────

	function confirmName():Void
	{
		var name = nameInput.text.trim();

		if (name == "" || name == "my-character")
		{
			nameHint.text  = "⚠ Enter a valid name";
			nameHint.color = FlxColor.YELLOW;
			return;
		}

		var invalid = ~/[\/\\:*?"<>|. ]/;
		if (invalid.match(name))
		{
			nameHint.text  = "✗ No spaces or special chars allowed";
			nameHint.color = FlxColor.RED;
			return;
		}

		#if sys
		var destPath = Paths.resolveWrite('characters/$name.json');
		if (FileSystem.exists(destPath))
		{
			nameHint.text  = "✗ \"" + name + "\" already exists";
			nameHint.color = FlxColor.RED;
			return;
		}
		#end

		wizardCharName = name;
		FlxG.sound.play(Paths.sound('menus/confirmMenu'), 0.6);
		// FIX: set flag instead of calling goToStep2() directly.  Calling it
		// here (inside the onEnterPressed native callback) sets wizardStep=2
		// before FlxG.keys.justPressed is cleared, so the step-2 block would
		// see justPressed.ENTER=true on the same frame and call finishWizard()
		// immediately.  The flag is consumed at the top of the next update().
		_step2Pending = true;
	}

	// ── Lógica paso 2 – importar ──────────────────────────────────────────────

	function importStandardSprite():Void
	{
		#if sys
		var _fd_Select_Spr = new FileDialog();
		_fd_Select_Spr.onSelect.add(function(path:String)
		{
			try
			{
				var fileName = haxe.io.Path.withoutDirectory(path);
				var sourceDir = haxe.io.Path.directory(path) + "/";
				var baseName  = haxe.io.Path.withoutExtension(fileName);

				var destDir = Paths.resolveWrite("characters/images/");
				Paths.ensureDir(destDir + "x");
				File.copy(path, destDir + fileName);

				var xmlPath = sourceDir + baseName + ".xml";
				var txtPath = sourceDir + baseName + ".txt";

				importedIsFlxAnimate   = false;
				importedSpritePath     = baseName;

				if (FileSystem.exists(xmlPath))
				{
					File.copy(xmlPath, destDir + baseName + ".xml");
					importedIsTxt = false;
					setStatus("✓ PNG + XML importados — abriendo mapper…", FlxColor.LIME);
					// Parsear prefijos únicos del XML y abrir el mapper de nombres
					var rawAnims = parseXmlPrefixes(destDir + baseName + ".xml");
					if (rawAnims.length > 0)
					{
						openSubState(new funkin.debug.editors.AnimMapperSubState(rawAnims,
							function(mapped:Array<funkin.gameplay.objects.character.Character.AnimData>)
							{
								importedAnimData = mapped;
								setStatus("✓ " + mapped.length + " animaciones mapeadas para " + baseName, FlxColor.LIME);
							}));
					}
				}
				else if (FileSystem.exists(txtPath))
				{
					File.copy(txtPath, destDir + baseName + ".txt");
					importedIsTxt = true;
					setStatus("✓ PNG + TXT imported → " + baseName, FlxColor.LIME);
				}
				else
				{
					setStatus("⚠ PNG imported — no XML/TXT found in same folder", FlxColor.YELLOW);
				}
			}
			catch (e:Dynamic) { setStatus("✗ Error: " + e, FlxColor.RED); }
		});
		_fd_Select_Spr.browse(OPEN, "png", null, "Select Sprite PNG");
		#end
	}

	function importFlxAnimate():Void
	{
		#if sys
		var _fd_Select_Spr = new FileDialog();
		_fd_Select_Spr.onSelect.add(function(pngPath:String)
		{
			try
			{
				var fileName  = haxe.io.Path.withoutDirectory(pngPath);
				var sourceDir = haxe.io.Path.directory(pngPath) + "/";
				var baseName  = haxe.io.Path.withoutExtension(fileName);

				var atlasJson = sourceDir + baseName + ".json";
				var animJson  = sourceDir + "Animation.json";

				if (!FileSystem.exists(atlasJson))
				{
					setStatus("✗ " + baseName + ".json not found next to PNG", FlxColor.RED);
					return;
				}

				var destFolder = Paths.resolveWrite('characters/images/$wizardCharName/');
				Paths.ensureDir(destFolder + "x");

				File.copy(pngPath,    destFolder + fileName);
				File.copy(atlasJson,  destFolder + baseName + ".json");

				var hasAnim = FileSystem.exists(animJson);
				if (hasAnim)
					File.copy(animJson, destFolder + "Animation.json");

				importedIsFlxAnimate   = true;
				importedIsTxt          = false;
				importedSpritePath     = wizardCharName;
				importedSpritemapName  = baseName;

				if (hasAnim)
				{
					// Parsear símbolos y abrir el mapper de nombres
					var rawAnims = parseAnimJson(destFolder + "Animation.json");
					if (rawAnims.length > 0)
					{
						setStatus("✓ FlxAnimate importado — abriendo mapper de símbolos…", FlxColor.LIME);
						openSubState(new funkin.debug.editors.AnimMapperSubState(rawAnims,
							function(mapped:Array<funkin.gameplay.objects.character.Character.AnimData>)
							{
								importedAnimData = mapped;
								setStatus("✓ " + mapped.length + " símbolos mapeados", FlxColor.LIME);
							}));
					}
					else
					{
						importedAnimData = rawAnims;
						setStatus("✓ FlxAnimate importado (sin símbolos en Animation.json)", FlxColor.YELLOW);
					}
				}
				else
				{
					setStatus("✓ FlxAnimate importado — sin Animation.json (añade anims manualmente)", FlxColor.YELLOW);
				}
			}
			catch (e:Dynamic) { setStatus("✗ Error: " + e, FlxColor.RED); }
		});
		_fd_Select_Spr.browse(OPEN, "png", null, "Select Spritemap PNG (FlxAnimate)");
		#end
	}

	function importIcon():Void
	{
		#if sys
		var _fd_Select_Ico = new FileDialog();
		_fd_Select_Ico.onSelect.add(function(path:String)
		{
			try
			{
				var ext     = haxe.io.Path.extension(path);
				var destDir = Paths.resolveWrite("images/icons/");
				Paths.ensureDir(destDir + "x");
				var dest = destDir + "icon-" + wizardCharName + "." + ext;
				File.copy(path, dest);
				setStatus("✓ Icon imported → icon-" + wizardCharName, FlxColor.LIME);
			}
			catch (e:Dynamic) { setStatus("✗ Error: " + e, FlxColor.RED); }
		});
		_fd_Select_Ico.browse(OPEN, "png", null, "Select Icon PNG (300x150)");
		#end
	}

	function setStatus(msg:String, col:FlxColor):Void
	{
		if (statusLine != null)
		{
			statusLine.text  = msg;
			statusLine.color = col;
		}
	}

	/** Parsea un XML de Sparrow y extrae los prefijos únicos de SubTexture
	 *  (quitando los dígitos finales). Devuelve Array<AnimData> para AnimMapperSubState. */
	/** Parses a Sparrow XML and returns unique SubTexture prefixes
	 *  (trailing digits stripped) as an Array<AnimData> for AnimMapperSubState. */
	function parseXmlPrefixes(xmlPath:String, framerate:Int = 24):Array<AnimData>
	{
		var result:Array<AnimData> = [];
		#if sys
		var seen = new Map<String, Bool>();
		try
		{
			var root = Xml.parse(File.getContent(xmlPath)).firstElement();
			for (node in root.elements())
			{
				if (node.nodeName != "SubTexture") continue;
				var raw    = node.get("name") != null ? node.get("name") : "";
				var prefix = ~/\d+$/.replace(raw, "");
				prefix = StringTools.trim(prefix);
				if (prefix != "" && !seen.exists(prefix))
				{
					seen.set(prefix, true);
					result.push({ name: prefix, prefix: prefix,
						framerate: framerate, looped: false, offsets: [0,0] });
				}
			}
		}
		catch (e:Dynamic) {}
		#end
		return result;
	}

	/** Parsea Animation.json y devuelve AnimData[] — igual que AnimationDebug */
	function parseAnimJson(path:String):Array<AnimData>
	{
		var result:Array<AnimData> = [];
		#if sys
		try
		{
			var parsed:Dynamic = Json.parse(File.getContent(path));
			if (parsed.AN != null)
				result.push({ name: parsed.AN.SN, prefix: parsed.AN.SN,
					framerate: parsed.MD != null ? Std.int(parsed.MD.FRT) : 24,
					looped: true, offsets: [0,0] });
			if (parsed.SD != null && parsed.SD.S != null)
				for (sym in (cast parsed.SD.S : Array<Dynamic>))
					result.push({ name: sym.SN, prefix: sym.SN,
						framerate: parsed.MD != null ? Std.int(parsed.MD.FRT) : 24,
						looped: false, offsets: [0,0] });
		}
		catch (_:Dynamic) {}
		#end
		return result;
	}

	// ── Finalizar wizard → crear JSON + abrir editor ──────────────────────────

	function finishWizard():Void
	{
		// Decidir animaciones: las importadas, o las de Dad como fallback
		var anims:Array<AnimData> = (importedAnimData.length > 0) ? importedAnimData : [
			{ name: "idle",      prefix: "Dad idle dance",     framerate: 24, looped: false, offsets: [0,0] },
			{ name: "singLEFT",  prefix: "Dad Sing Note LEFT", framerate: 24, looped: false, offsets: [-10,10] },
			{ name: "singDOWN",  prefix: "Dad Sing Note DOWN", framerate: 24, looped: false, offsets: [0,-30] },
			{ name: "singUP",    prefix: "Dad Sing Note UP",   framerate: 24, looped: false, offsets: [-6,50] },
			{ name: "singRIGHT", prefix: "Dad Sing Note RIGHT",framerate: 24, looped: false, offsets: [0,27] }
	  	];

		// Decidir path: lo importado, o Dad como fallback
		var spritePath = (importedSpritePath != "") ? importedSpritePath : DAD_PATH;

		var data:CharacterData = {
			path:         spritePath,
			animations:   anims,
			isPlayer:     false,
			scale:        1.0,
			antialiasing: true,
			healthIcon:   wizardCharName,
			healthBarColor: "#31B0D1"
		};

		if (importedIsFlxAnimate)
		{
			data.isFlxAnimate = true;
			if (importedSpritemapName != "" && importedSpritemapName != "spritemap1")
				data.spritemapName = importedSpritemapName;
		}
		if (importedIsTxt) data.isTxt = true;

		#if sys
		try
		{
			var writePath = Paths.ensureDir(Paths.resolveWrite('characters/$wizardCharName.json'));
			File.saveContent(writePath, Json.stringify(data, null, '\t'));

			CharacterList.reload();
			FlxG.sound.play(Paths.sound('menus/confirmMenu'), 0.8);
			StateTransition.switchState(new AnimationDebug(wizardCharName));
		}
		catch (e:Dynamic)
		{
			setStatus("✗ Could not save JSON: " + e, FlxColor.RED);
		}
		#end
	}

	// ── Delete confirm ────────────────────────────────────────────────────────

	function buildDeletePanel():Void
	{
		var pw = 420;
		var ph = 90;
		var px = (FlxG.width - pw) / 2;
		var py = (FlxG.height - ph) / 2;

		delPanel = new FlxSprite(px, py);
		delPanel.makeGraphic(pw, ph, 0xF01A0808);
		delPanel.scrollFactor.set();
		delPanel.visible = false;
		add(delPanel);

		delPanelBorder = new FlxSprite(px, py);
		delPanelBorder.makeGraphic(pw, 3, FlxColor.RED);
		delPanelBorder.scrollFactor.set();
		delPanelBorder.visible = false;
		add(delPanelBorder);

		delText = new FlxText(px + 10, py + 10, pw - 20, "", 13);
		delText.setFormat("VCR OSD Mono", 13, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		delText.scrollFactor.set();
		delText.visible = false;
		add(delText);

		delHint = new FlxText(px + 10, py + 58, pw - 20, "ENTER: Confirm  |  ESC: Cancel", 11);
		delHint.setFormat("VCR OSD Mono", 11, 0xFFAAAAAA, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		delHint.scrollFactor.set();
		delHint.visible = false;
		add(delHint);
	}

	function openDeleteConfirm(name:String):Void
	{
		pendingDelete = name;
		delText.text  = "Delete \"" + name + "\"?\nThis cannot be undone.";
		delPanel.visible = delPanelBorder.visible = delText.visible = delHint.visible = true;
		delPanel.alpha = 0;
		FlxTween.tween(delPanel, {alpha: 1}, 0.16, {ease: FlxEase.quartOut});
	}

	function closeDeleteConfirm():Void
	{
		pendingDelete = null;
		FlxTween.tween(delPanel, {alpha: 0}, 0.12, {ease: FlxEase.quartIn, onComplete: function(_)
		{
			delPanel.visible = delPanelBorder.visible = delText.visible = delHint.visible = false;
		}});
	}

	function confirmDelete():Void
	{
		if (pendingDelete == null) return;
		#if sys
		try
		{
			var path = Paths.resolveWrite('characters/$pendingDelete.json');
			if (FileSystem.exists(path)) FileSystem.deleteFile(path);
		}
		catch (_:Dynamic) {}
		#end

		closeDeleteConfirm();
		loadCharList();
		if (curSelected > charNames.length) curSelected = charNames.length;
		buildList();
		changeSelection();
		FlxG.sound.play(Paths.sound('menus/cancelMenu'), 0.8);
	}

	// ── changeSelection ───────────────────────────────────────────────────────

	function changeSelection(change:Int = 0):Void
	{
		if (change != 0) FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.4);

		curSelected += change;
		var maxSel = charNames.length;
		if (curSelected < 0)      curSelected = maxSel;
		if (curSelected > maxSel) curSelected = 0;

		// Color bg
		var target = (curSelected == 0) ? EditorTheme.current.accent : EditorTheme.current.bgDark;
		if (target != intendedColor)
		{
			if (colorTween != null) colorTween.cancel();
			intendedColor = target;
			colorTween = FlxTween.color(bg, 0.5, bg.color, intendedColor,
				{ onComplete: function(_) { colorTween = null; } });
		}

		charInfoText.text = (curSelected == 0) ? "Create new character"
			: charNames[curSelected - 1].toUpperCase();

		for (i in 0...iconArray.length)
			if (iconArray[i] != null) iconArray[i].alpha = 0.5;
		if (iconArray[curSelected] != null) iconArray[curSelected].alpha = 1.0;

		var n = 0;
		for (item in grpChars.members)
		{
			if (item == null) continue;
			item.targetY = n - curSelected;
			item.alpha   = (item.targetY == 0) ? 1.0 : 0.5;
			if (item.targetY == 0)
			{
				FlxTween.cancelTweensOf(item.scale);
				item.scale.set(1.06, 1.06);
				FlxTween.tween(item.scale, {x: 1, y: 1}, 0.28, {ease: FlxEase.expoOut});
			}
			n++;
		}

		FlxG.camera.zoom = 1.02;
	}

	// ── Update ────────────────────────────────────────────────────────────────

	override function update(elapsed:Float):Void
	{
		#if (HSCRIPT_ALLOWED || (LUA_ALLOWED && linc_luajit))
		funkin.scripting.StateScriptHandler.callOnScripts('onUpdate', [elapsed]);
		#end
		super.update(elapsed);

		if (FlxG.sound.music != null && FlxG.sound.music.volume < 0.7)
			FlxG.sound.music.volume += 0.5 * elapsed;

		updateVisualBars(elapsed);
		FlxG.camera.zoom = FlxMath.lerp(FlxG.camera.zoom, 1, elapsed * 3);

		// ── Consume deferred wizard transitions ───────────────────────────────
		// These flags are set by CoolInputText native-event callbacks (onEnterPressed
		// / onEscapePressed) instead of calling the transitions directly, so that
		// FlxG.keys.justPressed does not fire the state's own handlers on the same
		// frame.  Process them before any key check and return immediately to keep
		// the navigation code from running on the transition frame.
		if (_wizClosePending) { _wizClosePending = false; closeWizard(); return; }
		if (_step2Pending)    { _step2Pending    = false; goToStep2();   return; }

		// ── Delete confirm abierto ────────────────────────────────────────────
		if (pendingDelete != null)
		{
			if (FlxG.keys.justPressed.ENTER)  confirmDelete();
			if (FlxG.keys.justPressed.ESCAPE) closeDeleteConfirm();
			return;
		}

		// ── Wizard abierto ────────────────────────────────────────────────────
		if (wizardStep > 0)
		{
			if (wizardStep == 1)
			{
				// ENTER → confirmName()  handled via nameInput.onEnterPressed → _step2Pending
				// ESC   → closeWizard()  handled via nameInput.onEscapePressed → _wizClosePending
				// Both callbacks are deferred so they don't double-fire here.
				// FlxG.keys.enabled is false while nameInput has focus anyway,
				// so these keys cannot be read from FlxG.keys during normal input.
			}
			else // paso 2
			{
				if (FlxG.keys.justPressed.ENTER)     finishWizard();
				if (FlxG.keys.justPressed.BACKSPACE) {
					wizardStep = 1;
					nameInput.onEnterPressed  = function() { confirmName(); };
					nameInput.onEscapePressed = function() { _wizClosePending = true; };
					nameInput.onFocusLost     = function() { if (wizardStep == 1) nameInput.hasFocus = true; };
					setWizVisible(true);
					nameInput.hasFocus = true;
					helpText.text = "ENTER: Continue  |  ESC: Cancel";
				}
				if (FlxG.keys.justPressed.ESCAPE)    closeWizard();
			}
			return; // bloquear navegación
		}

		// ── Navegación lista ──────────────────────────────────────────────────
		if (controls.UP_P)   changeSelection(-1);
		if (controls.DOWN_P) changeSelection(1);

		if (FlxG.keys.justPressed.N)
		{
			FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.5);
			openWizard();
			return;
		}

		if (FlxG.keys.justPressed.DELETE && curSelected > 0)
		{
			FlxG.sound.play(Paths.sound('menus/cancelMenu'), 0.6);
			openDeleteConfirm(charNames[curSelected - 1]);
			return;
		}

		if (controls.ACCEPT)
		{
			if (curSelected == 0)
			{
				FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.5);
				openWizard();
			}
			else
			{
				FlxG.sound.play(Paths.sound('menus/confirmMenu'), 0.7);
				StateTransition.switchState(new AnimationDebug(charNames[curSelected - 1]));
			}
		}

		if (controls.BACK)
		{
			FlxG.sound.play(Paths.sound('menus/cancelMenu'));
			StateTransition.switchState(funkin.scripting.ScriptBridge.resolveState('MainMenuState') ?? new MainMenuState());
		}

		#if (HSCRIPT_ALLOWED || (LUA_ALLOWED && linc_luajit))
		funkin.scripting.StateScriptHandler.callOnScripts('onUpdatePost', [elapsed]);
		#end
	}

	override function destroy():Void
	{
		#if (HSCRIPT_ALLOWED || (LUA_ALLOWED && linc_luajit))
		funkin.scripting.StateScriptHandler.callOnScripts('onDestroy', []);
		funkin.scripting.StateScriptHandler.clearStateScripts();
		#end
		super.destroy();
	}

	// ── Visual bars ───────────────────────────────────────────────────────────

	function updateVisualBars(elapsed:Float):Void
	{
		beatTimer += elapsed;
		var i = 0;
		for (bar in visualBars)
		{
			if (bar == null) continue;
			var t:Float = 0.28 + Math.sin(beatTimer * 2.5 + i * 0.7) * 0.22;
			bar.scale.y = FlxMath.lerp(bar.scale.y, t, elapsed * 6);
			bar.y = FlxG.height - bar.scale.y * 220;
			i++;
		}
	}
}
