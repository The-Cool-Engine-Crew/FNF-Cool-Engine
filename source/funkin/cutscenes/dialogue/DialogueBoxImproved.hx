package funkin.cutscenes.dialogue;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.addons.text.FlxTypeText;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import funkin.cutscenes.dialogue.DialogueData;
import funkin.gameplay.PlayState;
import funkin.cutscenes.dialogue.DialogueData.*;

using StringTools;

/**
 * Sistema de diálogos 100% softcoding con skins
 */
class DialogueBoxImproved extends FlxSpriteGroup
{
	// === SPRITES ===
	var box:FlxSprite;
	var bgFade:FlxSprite;

	// === TEXTO ===
	var swagDialogue:FlxTypeText;
	var dropText:FlxText;
	var controlsText:FlxText;

	// === DATOS ===
	var conversation:DialogueConversation;
	var skin:DialogueSkin;
	var currentMessageIndex:Int = 0;
	var currentStyle:DialogueStyle;

	// === CALLBACKS ===
	public var finishThing:Void->Void;

	// === ESTADO ===
	var textFinished:Bool = false;
	var dialogueOpened:Bool = false;
	var dialogueStarted:Bool = false;
	var isEnding:Bool = false;

	// === PORTRAITS CACHE ===
	var portraitCache:Map<String, FlxSprite> = new Map<String, FlxSprite>();
	var portraitGroup:FlxSpriteGroup;
	var activePortrait:FlxSprite = null;

	// === BOXES CACHE ===
	var boxCache:Map<String, FlxSprite> = new Map<String, FlxSprite>();

	/**
	 * Constructor - 100% softcoding
	 */
	public function new(songName:String)
	{
		super();

		// 1. Cargar conversación (solo mensajes + referencia a skin)
		conversation = DialogueData.loadConversation(songName);
		if (conversation == null)
		{
			trace('ERROR: Failed to load conversation for: $songName');
			trace('Make sure the file exists at: assets/songs/${songName.toLowerCase()}/dialogue.json');
			// Crear conversación dummy para evitar crashes
			conversation = {
				name: "error",
				skinName: "default",
				messages: [{
					character: "error",
					text: "Failed to load dialogue!",
					bubbleType: "normal",
					speed: 0.04
				}]
			};
		}

		// 2. Cargar skin asociada (toda la configuración visual)
		skin = DialogueData.loadSkin(conversation.skinName);
		if (skin == null)
		{
			trace('ERROR: Failed to load skin: ${conversation.skinName}');
			trace('Make sure the skin exists at: assets/cutscenes/dialogue/${conversation.skinName}/config.json');
			// Crear skin dummy
			skin = DialogueData.createEmptySkin(conversation.skinName, "pixel");
		}

		// Verificar que hay mensajes
		if (conversation.messages == null || conversation.messages.length == 0)
		{
			trace('ERROR: No messages in conversation!');
			conversation.messages = [{
				character: "error",
				text: "No messages!",
				bubbleType: "normal",
				speed: 0.04
			}];
		}

		// 3. Determinar estilo desde la skin
		currentStyle = switch (skin.style.toLowerCase())
		{
			case 'pixel': DialogueStyle.PIXEL;
			case 'normal': DialogueStyle.NORMAL;
			default: DialogueStyle.CUSTOM;
		}

		createBackground();

		portraitGroup = new FlxSpriteGroup();
		add(portraitGroup);

		createDialogueBox();
		createTextArea();
		createControlsText();

		trace('Dialogue loaded successfully!');
		trace('  Conversation: ${conversation.name}');
		trace('  Skin: ${skin.name}');
		trace('  Style: ${skin.style}');
		trace('  Messages: ${conversation.messages.length}');
	}

	/**
	 * Crear fondo con fade
	 */
	function createBackground():Void
	{
		// Color desde la skin
		var bgColor = FlxColor.fromString(skin.backgroundColor ?? '#000000');

		bgFade = new FlxSprite(-200, -200);
		bgFade.makeGraphic(Std.int(FlxG.width * 1.3), Std.int(FlxG.height * 1.3), bgColor);
		bgFade.scrollFactor.set();
		bgFade.alpha = 0;
		add(bgFade);

		// Fade in time desde la skin
		var fadeTime = skin.fadeTime ?? 0.83;
		new FlxTimer().start(fadeTime / 5, function(tmr:FlxTimer)
		{
			bgFade.alpha += (1 / 5) * 0.7;
			if (bgFade.alpha > 0.7)
				bgFade.alpha = 0.7;
		}, 5);
	}

	/**
	 * Crear caja de diálogo inicial
	 */
	function createDialogueBox():Void
	{
		// Obtener box del primer mensaje
		var firstMessage = conversation.messages[0];
		var boxName = firstMessage.boxSprite;

		if (boxName != null && boxName != "")
		{
			box = loadBox(boxName);
		}
		else
		{
			// Si no hay box específica, usar la primera disponible
			var firstBoxName:String = null;
			for (name in skin.boxes.keys())
			{
				firstBoxName = name;
				break;
			}
			
			if (firstBoxName != null)
			{
				box = loadBox(firstBoxName);
			}
			else
			{
				trace('WARNING: No boxes found in skin, creating placeholder');
				box = new FlxSprite(0, FlxG.height - 200);
				box.makeGraphic(Std.int(FlxG.width * 0.8), 200, FlxColor.WHITE);
				box.screenCenter(X);
			}
		}

		if (box != null)
		{
			add(box);

			// Iniciar animación de apertura si existe
			if (box.animation != null && box.animation.exists('normalOpen'))
			{
				box.animation.play('normalOpen');
			}
			else if (box.animation != null && box.animation.exists('open'))
			{
				box.animation.play('open');
			}
		}
	}

	/**
	 * Cargar caja desde configuración de skin
	 */
	function loadBox(boxName:String):FlxSprite
	{
		// Verificar caché
		if (boxCache.exists(boxName))
		{
			return boxCache.get(boxName);
		}

		var config = skin.boxes.get(boxName);
		if (config == null)
		{
			trace('WARNING: Box config not found: $boxName');
			return null;
		}

		// Construir ruta completa desde la skin
		var fullPath = DialogueData.getBoxAssetPath(skin.name, config.fileName);
		
		var boxSprite = new FlxSprite(config.x ?? 0, config.y ?? 0);

		try
		{
			// Intentar cargar como spritesheet con animaciones
			boxSprite.frames = Paths.getSparrowAtlasCutscene(fullPath);
			
			// Agregar animaciones comunes
			if (boxSprite.frames != null)
			{
				// Animaciones según estilo
				if (currentStyle == DialogueStyle.PIXEL)
				{
					boxSprite.animation.addByPrefix('normalOpen', config.animation ?? 'Text Box Appear', 24, false);
					boxSprite.animation.addByIndices('normal', config.animation ?? 'Text Box Appear', [4], "", 24);
					boxSprite.animation.addByPrefix('open', config.animation ?? 'Text Box Appear', 24, false);
					
					// Escalar para pixel art
					var pixelZoom = 6.0;
					boxSprite.setGraphicSize(Std.int(boxSprite.width * pixelZoom * 0.9));
				}
				else
				{
					boxSprite.animation.addByPrefix('normalOpen', 'Speech Bubble Normal Open', 24, false);
					boxSprite.animation.addByPrefix('normal', 'speech bubble normal', 24, true);
					boxSprite.animation.addByPrefix('loud', 'speech bubble loud open', 24, false);
					boxSprite.animation.addByPrefix('open', 'Speech Bubble Normal Open', 24, false);
				}
			}
		}
		catch (e:Dynamic)
		{
			// Si falla, cargar como imagen estática
			trace('Loading box as static image: $fullPath');
			boxSprite.loadGraphic(Paths.imageCutscene(fullPath));
		}

		// Aplicar escala desde configuración
		boxSprite.scale.set(config.scaleX ?? 1.0, config.scaleY ?? 1.0);
		boxSprite.updateHitbox();
		boxSprite.screenCenter(X);

		// Guardar en caché
		boxCache.set(boxName, boxSprite);

		return boxSprite;
	}

	/**
	 * Crear área de texto desde configuración de skin
	 */
	function createTextArea():Void
	{
		var textConfig = skin.textConfig;

		// Si no hay configuración, usar valores por defecto según estilo
		if (textConfig == null)
		{
			textConfig = switch (currentStyle)
			{
				case DialogueStyle.PIXEL:
					{
						x: 240,
						y: 500,
						width: 800,
						size: 32,
						font: "Pixel Arial 11 Bold",
						color: "#3F2021"
					};
				case DialogueStyle.NORMAL:
					{
						x: 180,
						y: FlxG.height - 250,
						width: Std.int(FlxG.width * 0.7),
						size: 42,
						font: "VCR OSD Mono",
						color: "#000000"
					};
				default:
					{
						x: 100,
						y: FlxG.height - 250,
						width: Std.int(FlxG.width * 0.8),
						size: 32,
						font: "Arial",
						color: "#FFFFFF"
					};
			}
		}

		// Sombra del texto (opcional, solo si el estilo es pixel)
		if (currentStyle == DialogueStyle.PIXEL)
		{
			dropText = new FlxText(textConfig.x + 2, textConfig.y + 2, textConfig.width, "", textConfig.size);
			dropText.font = textConfig.font;
			dropText.color = 0xFFD89494;
			add(dropText);
		}

		// Texto principal
		swagDialogue = new FlxTypeText(textConfig.x, textConfig.y, textConfig.width, "", textConfig.size);
		swagDialogue.font = textConfig.font;
		swagDialogue.color = FlxColor.fromString(textConfig.color);

		// Sonido del texto (desde el primer mensaje o por defecto)
		var soundPath = conversation.messages[0].sound;
		if (soundPath == null)
		{
			// Sonido por defecto según estilo
			soundPath = switch (currentStyle)
			{
				case DialogueStyle.PIXEL: 'pixelText';
				case DialogueStyle.NORMAL: 'dialogueText';
				default: 'pixelText';
			}
		}

		try
		{
			swagDialogue.sounds = [FlxG.sound.load(Paths.sound(soundPath), 0.6)];
		}
		catch (e:Dynamic)
		{
			trace('WARNING: Failed to load dialogue sound: $soundPath');
		}

		add(swagDialogue);
	}

	/**
	 * Crear texto de controles
	 */
	function createControlsText():Void
	{
		controlsText = new FlxText(0, 0, 'Press ENTER to continue | SHIFT to skip');
		controlsText.size = 20;
		controlsText.x = FlxG.width - controlsText.width - 60;
		controlsText.y = FlxG.height - 100;
		controlsText.font = Paths.font('Funkin.otf');
		controlsText.setBorderStyle(FlxTextBorderStyle.OUTLINE, FlxColor.BLACK, 2, 1);
		controlsText.color = FlxColor.WHITE;
		controlsText.scrollFactor.set();
		add(controlsText);
	}

	/**
	 * Cargar portrait desde configuración de skin
	 */
	function loadPortrait(portraitName:String):FlxSprite
	{
		var config = skin.portraits.get(portraitName);
		if (config == null)
		{
			trace('WARNING: Portrait config not found: $portraitName');
			return null;
		}

		// Construir ruta completa desde la skin
		var fullPath = DialogueData.getPortraitAssetPath(skin.name, config.fileName);

		var portrait = new FlxSprite(config.x ?? 0, config.y ?? 0);

		try
		{
			// Intentar cargar como spritesheet con animaciones
			portrait.frames = Paths.getSparrowAtlasCutscene(fullPath);
			
			if (portrait.frames != null)
			{
				// Agregar animaciones
				portrait.animation.addByPrefix('idle', config.animation ?? 'idle', 24, true);
				portrait.animation.addByPrefix('enter', config.animation ?? 'enter', 24, false);
				portrait.animation.addByPrefix('talk', config.animation ?? 'talk', 24, true);
				
				// Escalar para pixel art si es necesario
				if (currentStyle == DialogueStyle.PIXEL)
				{
					var pixelZoom = 6.0;
					portrait.setGraphicSize(Std.int(portrait.width * pixelZoom * 0.9));
				}
			}
		}
		catch (e:Dynamic)
		{
			// Si falla, cargar como imagen estática
			trace('Loading portrait as static image: $fullPath');
			portrait.loadGraphic(Paths.imageCutscene(fullPath));
		}

		// Aplicar configuración
		portrait.scale.set(config.scaleX ?? 1.0, config.scaleY ?? 1.0);
		portrait.flipX = config.flipX ?? false;
		portrait.updateHitbox();
		portrait.scrollFactor.set();
		portrait.visible = false;

		return portrait;
	}

	/**
	 * Obtener o crear portrait (con caché)
	 */
	function getOrCreatePortrait(portraitName:String):FlxSprite
	{
		// Verificar caché
		if (portraitCache.exists(portraitName))
		{
			return portraitCache.get(portraitName);
		}

		// Crear portrait
		var portrait = loadPortrait(portraitName);
		if (portrait != null)
		{
			portraitGroup.add(portrait);
			portraitCache.set(portraitName, portrait);
		}

		return portrait;
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// Actualizar sombra del texto (solo pixel)
		if (dropText != null)
		{
			dropText.text = swagDialogue.text;
		}

		// Esperar a que la caja termine de abrir
		if (box != null && box.animation != null && box.animation.curAnim != null)
		{
			if (box.animation.curAnim.name == 'normalOpen' || box.animation.curAnim.name == 'open')
			{
				if (box.animation.curAnim.finished)
				{
					if (box.animation.exists('normal'))
					{
						box.animation.play('normal');
					}
					dialogueOpened = true;
				}
			}
		}
		else
		{
			// Si no hay animación de apertura, abrir inmediatamente
			dialogueOpened = true;
		}

		// Iniciar diálogo
		if (dialogueOpened && !dialogueStarted)
		{
			startDialogue();
			dialogueStarted = true;
		}

		// Input para avanzar
		handleInput();
	}

	/**
	 * Manejar input del jugador
	 */
	function handleInput():Void
	{
		if (!dialogueStarted || isEnding)
			return;

		// Skip completo con SHIFT
		if (FlxG.keys.justPressed.SHIFT)
		{
			FlxG.sound.play(Paths.sound('clickText'), 0.8);
			endDialogue();
			return;
		}

		// Avanzar o completar texto
		var acceptInput = FlxG.keys.justPressed.ENTER || FlxG.keys.justPressed.SPACE;

		if (acceptInput)
		{
			if (!textFinished)
			{
				// Completar texto instantáneamente
				swagDialogue.skip();
				textFinished = true;
				return;
			}

			// Si ya terminó el texto, avanzar al siguiente mensaje
			FlxG.sound.play(Paths.sound('clickText'), 0.8);
			currentMessageIndex++;

			if (currentMessageIndex >= conversation.messages.length)
			{
				endDialogue();
			}
			else
			{
				startDialogue();
			}
		}
	}

	/**
	 * Iniciar el mensaje actual
	 */
	function startDialogue():Void
	{
		// Verificar que conversation y messages existen
		if (conversation == null || conversation.messages == null)
		{
			trace('ERROR: Conversation or messages is null!');
			endDialogue();
			return;
		}

		if (currentMessageIndex >= conversation.messages.length)
		{
			endDialogue();
			return;
		}

		var msg = conversation.messages[currentMessageIndex];
		if (msg == null)
		{
			trace('ERROR: Message is null at index $currentMessageIndex');
			endDialogue();
			return;
		}

		textFinished = false;

		// Actualizar texto
		if (swagDialogue != null)
		{
			swagDialogue.resetText(msg.text ?? "");
			swagDialogue.start(msg.speed ?? 0.04, true, false, null, function()
			{
				textFinished = true;
			});
		}

		// Actualizar portrait si está especificado
		if (msg.portrait != null && msg.portrait != "")
		{
			updatePortrait(msg.portrait);
		}
		else if (activePortrait != null)
		{
			// Si no hay portrait especificado, ocultar el activo
			activePortrait.visible = false;
			activePortrait = null;
		}

		// Cambiar caja si está especificada
		if (msg.boxSprite != null && msg.boxSprite != "")
		{
			updateBox(msg.boxSprite);
		}

		// Actualizar animación de la caja según el tipo de burbuja
		if (box != null && box.animation != null && msg.bubbleType != null)
		{
			switch (msg.bubbleType)
			{
				case 'loud':
					if (box.animation.exists('loud'))
						box.animation.play('loud');
				case 'angry':
					if (box.animation.exists('angry'))
						box.animation.play('angry');
				case 'evil':
					if (box.animation.exists('evil'))
						box.animation.play('evil');
				case 'normal' | _:
					if (box.animation.exists('normal'))
						box.animation.play('normal');
			}
		}

		// Cambiar música si está especificada
		if (msg.music != null && msg.music != "")
		{
			FlxG.sound.playMusic(Paths.music(msg.music), 0.7);
		}
	}

	/**
	 * Actualizar portrait activo
	 */
	function updatePortrait(portraitName:String):Void
	{
		// Ocultar portrait anterior
		if (activePortrait != null)
		{
			activePortrait.visible = false;
		}

		// Obtener o crear nuevo portrait
		var newPortrait = getOrCreatePortrait(portraitName);

		if (newPortrait != null)
		{
			newPortrait.visible = true;

			// Reproducir animación
			if (newPortrait.animation != null)
			{
				if (newPortrait.animation.exists('enter'))
				{
					newPortrait.animation.play('enter');
				}
				else if (newPortrait.animation.exists('idle'))
				{
					newPortrait.animation.play('idle');
				}
			}

			activePortrait = newPortrait;
		}
	}

	/**
	 * Actualizar caja de diálogo
	 */
	function updateBox(boxName:String):Void
	{
		// Solo cambiar si es diferente a la actual
		var currentBoxConfig = null;
		for (name => sprite in boxCache)
		{
			if (sprite == box)
			{
				currentBoxConfig = name;
				break;
			}
		}

		if (currentBoxConfig == boxName)
			return; // Ya estamos usando esta caja

		// Cargar nueva caja
		var newBox = loadBox(boxName);
		if (newBox != null)
		{
			// Remover caja anterior
			if (box != null)
			{
				remove(box);
			}

			// Agregar nueva caja
			box = newBox;
			add(box);

			// Iniciar animación
			if (box.animation != null)
			{
				if (box.animation.exists('normalOpen'))
				{
					box.animation.play('normalOpen');
				}
				else if (box.animation.exists('open'))
				{
					box.animation.play('open');
				}
			}
		}
	}

	function endDialogue():Void
	{
		if (isEnding)
			return;
		isEnding = true;

		// Detener la música del diálogo con fade out
		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.fadeOut(1.2, 0, function(twn:flixel.tweens.FlxTween)
			{
				FlxG.sound.music.stop();
				FlxG.sound.music.kill();
				if (finishThing != null)
					finishThing();
			});
		}
		else if (finishThing != null) {
			finishThing();
		}

		// Fade out
		new FlxTimer().start(0.2, function(tmr:FlxTimer)
		{
			if (box != null)
				box.alpha -= 1 / 5;
			
			bgFade.alpha -= 1 / 5 * 0.7;

			// Ocultar todos los portraits
			for (portrait in portraitCache)
			{
				portrait.visible = false;
			}

			swagDialogue.alpha -= 1 / 5;

			if (dropText != null)
				dropText.alpha = swagDialogue.alpha;

			controlsText.alpha -= 1 / 5;
		}, 5);

		new FlxTimer().start(1.2, function(tmr:FlxTimer)
		{
			kill();
		});
	}

	// FIX Bug 7: portraitCache and boxCache held strong FlxSprite references
	// (and thus their BitmapData textures) forever — DialogueBoxImproved had
	// no destroy() override at all.  Each time a cutscene was replayed the old
	// portrait and box sprites accumulated in RAM because nothing ever called
	// sprite.destroy() on them.
	override public function destroy():Void
	{
		if (portraitGroup != null)
		{
			portraitGroup.destroy();
			portraitGroup = null;
		}

		// Destroy every cached portrait sprite so its BitmapData is freed.
		for (_ => portrait in portraitCache)
			if (portrait != null) try portrait.destroy() catch (_:Dynamic) {}
		portraitCache.clear();

		// Destroy every cached dialogue-box sprite.
		for (_ => boxSpr in boxCache)
			if (boxSpr != null) try boxSpr.destroy() catch (_:Dynamic) {}
		boxCache.clear();

		super.destroy();
	}
}
