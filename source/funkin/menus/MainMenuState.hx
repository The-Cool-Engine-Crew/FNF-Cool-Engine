package funkin.menus;

#if desktop
import data.Discord.DiscordClient;
#end
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxObject;
import flixel.FlxSprite;
import funkin.transitions.StateTransition;
import flixel.effects.FlxFlicker;
import flixel.group.FlxGroup.FlxTypedGroup;
import funkin.transitions.StickerTransition;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import lime.app.Application;
import animationdata.FunkinSprite;
import funkin.menus.OptionsMenuState;
import openfl.display.BitmapData as Bitmap;
import data.PlayerSettings;
import funkin.scripting.StateScriptHandler;
import funkin.audio.MusicManager;
import funkin.data.SaveData;
import funkin.shaders.MenuBGShader;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;

using StringTools;

class MainMenuState extends funkin.states.MusicBeatState
{
	var curSelected:Int = 0;

	var menuItems:FlxTypedGroup<FunkinSprite>;

	var optionShit:Array<String> = ['storymode', 'freeplay', 'options', 'credits'];

	var canSnap:Array<Float> = [];

	var camFollow:FlxObject;
	var newInput:Bool = true;
	var menuItem:FlxSprite;

	var bg:FlxSprite;
	var versionShit2:FlxText;
	var modShit:FlxText;

	var versionAPI:String = "0.4.4B";

	public static var firstStart:Bool = true;

	public static var finishedFunnyMove:Bool = false;

	// ── MenuBG Shader — ciclo de colores ─────────────────────────────────────
	var _bgShader:MenuBGShader;

	/**
	 * Paleta de colores en formato [R, G, B] (valores 0-1).
	 * Se puede ampliar fácilmente con más entradas.
	 */
	static final BG_PALETTE:Array<Array<Float>> = [
		[1.00, 0.41, 0.71],   // Rosa  #FF69B4
		[0.61, 0.19, 1.00],   // Morado #9B30FF
		[0.20, 0.80, 1.00],   // Cian  #33CCFF
		[0.20, 1.00, 0.60],   // Verde neón #33FF99
		[1.00, 0.55, 0.10],   // Naranja #FF8C19
	];

	/** Índice del color actualmente visible. */
	var _paletteIdx:Int = 0;

	/** Tween activo de transición de color (para cancelar si es necesario). */
	var _colorTween:FlxTween = null;

	/** Segundos que cada color permanece antes de transicionar. */
	static inline final COLOR_HOLD:Float    = 4.0;
	/** Duración de la transición de un color al siguiente. */
	static inline final COLOR_TRANS:Float   = 1.2;

	/** Timer acumulado para el ciclo de color. */
	var _colorTimer:Float = 0;

	override function create()
	{
		funkin.system.CursorManager.hide();
		// LOAD CUZ THIS SHIT DONT DO IT SOME IN THE CACHESTATE.HX FUCK
		PlayerSettings.player1.controls.loadKeyBinds();

		if (StickerTransition.enabled)
		{
			transIn = null;
			transOut = null;
		}

		#if desktop
		// Updating Discord Rich Presence
		DiscordClient.changePresence("In the Menu", null);
		#end

		#if !MAINMENU
		// MusicManager solo llama playMusic si freakyMenu no está ya sonando
		MusicManager.play('freakyMenu', 0.7);
		#end

		#if HSCRIPT_ALLOWED
		StateScriptHandler.init();
		StateScriptHandler.loadStateScripts('MainMenuState', this);
		StateScriptHandler.callOnScripts('onCreate', []);
		#end

		persistentUpdate = persistentDraw = true;

		bg = new FlxSprite().loadGraphic(Bitmap.fromFile(Paths.image('menu/menuBG')));
		var bgScale:Float = Math.max(FlxG.width / bg.width, FlxG.height / bg.height) * 1.1;
		bg.scale.set(bgScale, bgScale);
		bg.updateHitbox();
		bg.screenCenter();
		bg.antialiasing = SaveData.data.antialiasing;

		// ── Aplicar shader de colorización ───────────────────────────────────
		_bgShader = new MenuBGShader();
		// Arrancar con el primer color de paleta ya asignado como A y B (sin blend)
		_bgShader.setColorA(BG_PALETTE[0][0], BG_PALETTE[0][1], BG_PALETTE[0][2]);
		_bgShader.setColorB(BG_PALETTE[1][0], BG_PALETTE[1][1], BG_PALETTE[1][2]);
		_bgShader.setBlend(0.0);
		bg.shader = _bgShader;

		add(bg);

		camFollow = new FlxObject(0, 0, 1, 1);
		add(camFollow);
		FlxG.camera.follow(camFollow, LOCKON, 0.06);
		FlxG.camera.snapToTarget();

		menuItems = new FlxTypedGroup<FunkinSprite>();
		add(menuItems);

		#if HSCRIPT_ALLOWED
		// Obtener items custom
		var customItems = StateScriptHandler.callOnScriptsReturn('getCustomMenuItems', [], null);
		if (customItems != null && Std.isOfType(customItems, Array))
		{
			var itemsArray:Array<String> = cast customItems;
			for (item in itemsArray)
				optionShit.push(item);
		}
		#end

		for (i in 0...optionShit.length)
		{
			var offset:Float = 108 - (Math.max(optionShit.length, 4) - 4) * 80;
			var menuItem:FunkinSprite = new FunkinSprite(70, (i * 140) + offset);
			menuItem.loadAsset('menu/mainmenu/' + optionShit[i]);
			menuItem.addAnim('idle', optionShit[i] + " idle", 24);
			menuItem.addAnim('selected', optionShit[i] + " selected", 24);
			menuItem.playAnim('idle');
			menuItem.ID = i;
			// menuItem.screenCenter(X);
			menuItems.add(menuItem);
			var scr:Float = (optionShit.length - 4) * 0.135;
			if (optionShit.length < 6)
				scr = 0;
			menuItem.scrollFactor.set(0, scr);
			menuItem.antialiasing = SaveData.data.antialiasing;
			menuItem.setGraphicSize(Std.int(menuItem.width * 0.8));
			menuItem.updateHitbox();
		}

		versionShit2 = new FlxText(5, FlxG.height - 19, 0, 'Cool Engine - v${Application.current.meta.get('version')}', 12);
		versionShit2.scrollFactor.set();
		versionShit2.setFormat("VCR OSD Mono", 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		versionShit2.antialiasing = SaveData.data.antialiasing;
		add(versionShit2);
		
		#if mobileC
		// En móvil: texto "[ MODS ]" tappable en lugar de "Press Shift"
		modShit = new FlxText(5, FlxG.height - 19, 0, '[ MODS ]', 12);
		#else
		modShit = new FlxText(5, FlxG.height - 19, 0, 'Press Shift - Menu Mods - API v'+versionAPI, 12);
		#end
		modShit.scrollFactor.set();
		modShit.setFormat("VCR OSD Mono", 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		modShit.antialiasing = SaveData.data.antialiasing;
		modShit.y -= 20;
		add(modShit);

		// Etiqueta del mod activo — solo visible si hay uno cargado
		final _activeMod = mods.ModManager.activeMod;
		if (_activeMod != null)
		{
			final _modInfo = mods.ModManager.getInfo(_activeMod);
			final _modLabel = _modInfo != null ? _modInfo.name : _activeMod;
			final _modVer = _modInfo != null ? ' v${_modInfo.version}' : '';
			final _modColor:flixel.util.FlxColor = _modInfo != null ? new flixel.util.FlxColor(_modInfo.color | 0xFF000000) : FlxColor.fromRGB(255, 170, 0);

			var modActiveText:FlxText = new FlxText(FlxG.width - 270, FlxG.height - 19, 0, '\u25B6 MOD: $_modLabel$_modVer', 16);
			modActiveText.scrollFactor.set();
			modActiveText.setFormat("VCR OSD Mono", 16, _modColor, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			modActiveText.antialiasing = SaveData.data.antialiasing;
			add(modActiveText);
		}

		changeItem();

		#if mobileC
		addVirtualPad(UP_DOWN, A_B);
		#end

		#if HSCRIPT_ALLOWED
		StateScriptHandler.refreshStateFields(this);
		StateScriptHandler.callOnScripts('postCreate', []);
		#end
		
		StickerTransition.clearStickers();

		super.create();
	}

	var selectedSomethin:Bool = false;

	override function update(elapsed:Float)
	{
		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onUpdate', [elapsed]);
		#end

		// ── Ciclo de color del fondo ──────────────────────────────────────────
		if (_bgShader != null)
		{
			_colorTimer += elapsed;
			if (_colorTimer >= COLOR_HOLD)
			{
				_colorTimer = 0;
				_startColorTransition();
			}
		}

		// El volumen de la música de menú lo gestiona CoreAudio._applyAll() cada frame.
		// No manipular FlxG.sound.music.volume aquí — pelea con el sistema de volumen.

		// ── Teclas de editor (solo en developer mode) ──────────────────────────
		if (mods.ModManager.developerMode)
		{
			if (FlxG.keys.justPressed.ONE)
				StateTransition.switchState(new funkin.debug.EditorHubState());
		}

		// ── Mod Selector ────────────────────────────────────────────────────────
		if (FlxG.keys.justPressed.SHIFT)
			StateTransition.switchState(funkin.scripting.ScriptBridge.resolveState('ModSelectorState') ?? new ModSelectorState());
		#if mobileC
		// Tap en la zona del texto "[ MODS ]" (esquina inferior izquierda)
		for (touch in FlxG.touches.justStarted())
			if (touch.screenX < 130 && touch.screenY > FlxG.height - 60)
				StateTransition.switchState(funkin.scripting.ScriptBridge.resolveState('ModSelectorState') ?? new ModSelectorState());
		#end

		if (!selectedSomethin)
		{
			if (controls.UP_P)
			{
				FlxG.sound.play(Paths.sound('menus/scrollMenu'));
				changeItem(-1);
			}

			if (controls.DOWN_P)
			{
				FlxG.sound.play(Paths.sound('menus/scrollMenu'));
				changeItem(1);
			}

			if (controls.BACK)
			{
				StateTransition.switchState(funkin.scripting.ScriptBridge.resolveState('TitleState') ?? new TitleState());
			}

			if (controls.ACCEPT)
			{
				#if HSCRIPT_ALLOWED
				var cancelled = StateScriptHandler.callOnScriptsReturn('onAccept', [], false);
				if (cancelled)
				{
					super.update(elapsed);
					return;
				}
				StateScriptHandler.callOnScripts('onMenuItemSelected', [optionShit[curSelected], curSelected]);
				#end

				selectedSomethin = true;
				FlxG.sound.play(Paths.sound('menus/confirmMenu'));
				if (SaveData.data.flashing)
					FlxG.camera.flash(FlxColor.WHITE);

				menuItems.forEach(function(spr:FunkinSprite)
				{
					if (curSelected != spr.ID)
					{
						FlxTween.tween(spr, {alpha: 0}, 0.4, {
							ease: FlxEase.quadOut,
							onComplete: function(twn:FlxTween)
							{
								spr.kill();
							}
						});
					}
					else
					{
						menuItems.forEach(function(spr:FunkinSprite)
						{
							FlxFlicker.flicker(spr, 1, 0.06, false, false, function(flick:FlxFlicker)
							{
								var daChoice:String = optionShit[curSelected];

								switch (daChoice)
								{
									case 'storymode':
										StateTransition.switchState(funkin.scripting.ScriptBridge.resolveState('StoryMenuState') ?? new StoryMenuState());
									case 'freeplay':
										StateTransition.switchState(funkin.scripting.ScriptBridge.resolveState('FreeplayState') ?? new FreeplayState());
									case 'options':
										StateTransition.switchState(funkin.scripting.ScriptBridge.resolveState('OptionsMenuState') ?? new OptionsMenuState());
									case 'credits':
										StateTransition.switchState(funkin.scripting.ScriptBridge.resolveState('CreditsState') ?? new funkin.menus.credits.CreditsState());
								}
							});
						});
					}
				});
			}
		}

		super.update(elapsed);

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onUpdatePost', [elapsed]);
		#end
	}

	function changeItem(huh:Int = 0)
	{
		curSelected += huh;

		if (curSelected >= menuItems.length)
			curSelected = 0;
		if (curSelected < 0)
			curSelected = menuItems.length - 1;

		menuItems.forEach(function(spr:FunkinSprite)
		{
			spr.playAnim('idle');
			spr.offset.y = 0;
			spr.updateHitbox();

			if (spr.ID == curSelected)
			{
				spr.playAnim('selected');
				camFollow.setPosition(spr.getGraphicMidpoint().x, spr.getGraphicMidpoint().y);
				spr.offset.x = 0.15 * (spr.frameWidth / 2 + 180);
				spr.offset.y = 0.15 * spr.frameHeight;
			}
		});

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onSelectionChanged', [curSelected]);
		#end
	}

	/**
	 * Inicia la transición al siguiente color de paleta.
	 * Cancela cualquier tween previo, avanza el índice y hace blend 0→1.
	 * Al completarse, fija colorA = colorB y prepara el siguiente B.
	 */
	function _startColorTransition():Void
	{
		if (_bgShader == null) return;

		// Cancelar tween anterior si sigue activo
		if (_colorTween != null)
		{
			_colorTween.cancel();
			_colorTween = null;
		}

		// Avanzar índice
		_paletteIdx = (_paletteIdx + 1) % BG_PALETTE.length;
		var nextIdx:Int = (_paletteIdx + 1) % BG_PALETTE.length;

		// Asignar: A = color actual, B = siguiente
		var cA = BG_PALETTE[_paletteIdx];
		var cB = BG_PALETTE[nextIdx];
		_bgShader.setColorA(cA[0], cA[1], cA[2]);
		_bgShader.setColorB(cB[0], cB[1], cB[2]);
		_bgShader.setBlend(0.0);

		// Animar blend de 0 a 1 durante COLOR_TRANS segundos
		// Se usa un objeto auxiliar para que FlxTween pueda interpolarlo
		var blendProxy = {v: 0.0};
		_colorTween = FlxTween.tween(blendProxy, {v: 1.0}, COLOR_TRANS, {
			ease: FlxEase.sineInOut,
			onUpdate: function(_)
			{
				if (_bgShader != null)
					_bgShader.setBlend(blendProxy.v);
			},
			onComplete: function(_)
			{
				// Una vez terminado: A ya es el color llegado, preparar el siguiente B
				if (_bgShader != null)
				{
					_bgShader.setColorA(cB[0], cB[1], cB[2]);
					_bgShader.setBlend(0.0);
				}
				_colorTween = null;
			}
		});
	}

	override function destroy()
	{
		if (_colorTween != null)
		{
			_colorTween.cancel();
			_colorTween = null;
		}
		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onDestroy', []);
		StateScriptHandler.clearStateScripts();
		#end

		super.destroy();
	}
}