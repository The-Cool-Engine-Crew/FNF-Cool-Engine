package funkin.cutscenes.dialogue;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.addons.text.FlxTypeText;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import funkin.cutscenes.dialogue.DialogueData;
import funkin.cutscenes.dialogue.DialogueData.*;
import funkin.cutscenes.dialogue.DialogueScriptContext;
#if HSCRIPT_ALLOWED
import funkin.scripting.HScriptInstance;
#end

using StringTools;

/**
 * DialogueBoxImproved — sistema de diálogos con scripting HScript nativo.
 *
 * ─── Arquitectura de capas (orden de render, atrás → delante) ────────────────
 *
 *   bgLayer       → fondos, imágenes de fondo
 *   portraitLayer → portraits de personajes
 *   boxLayer      → caja de diálogo
 *   textLayer     → FlxTypeText + sombra
 *   uiLayer       → controles ENTER/SHIFT, iconos
 *   overlayLayer  → efectos sobre todo lo demás
 *
 * ─── Flujo de construcción ───────────────────────────────────────────────────
 *
 *   new()
 *     ├── Cargar conversación + skin
 *     ├── Crear 6 capas (FlxSpriteGroup)
 *     ├── Crear DialogueScriptContext con las capas
 *     ├── Cargar HScript (skin.scriptFile) → script.call('onCreate')
 *     │     El script puede asignar ctx.onCreateBackground, onCreateBox,
 *     │     onCreatePortrait antes de que los defaults se construyan.
 *     ├── buildBackground()   — si ctx.onCreateBackground != null lo llama,
 *     │                         si no usa el fade semitransparente por defecto
 *     ├── buildDialogueBox()  — idem con ctx.onCreateBox
 *     ├── buildTextArea()     — crea swagDialogue y dropText
 *     └── buildControlsText()
 *
 * @author Cool Engine Team
 */
class DialogueBoxImproved extends FlxSpriteGroup
{
    // ── CAPAS ────────────────────────────────────────────────────────────────
    var _bgLayer:FlxSpriteGroup;
    var _portraitLayer:FlxSpriteGroup;
    var _boxLayer:FlxSpriteGroup;
    var _textLayer:FlxSpriteGroup;
    var _uiLayer:FlxSpriteGroup;
    var _overlayLayer:FlxSpriteGroup;

    // ── SPRITES PRINCIPALES ──────────────────────────────────────────────────
    var box:FlxSprite;
    var bgFade:FlxSprite;

    // ── TEXTO ────────────────────────────────────────────────────────────────
    var swagDialogue:FlxTypeText;
    var dropText:FlxText;
    var controlsText:FlxText;

    // ── DATOS ────────────────────────────────────────────────────────────────
    var conversation:DialogueConversation;
    var skin:DialogueSkin;
    var currentMessageIndex:Int = 0;
    var currentStyle:DialogueStyle;

    // ── CALLBACKS ────────────────────────────────────────────────────────────
    public var finishThing:Void->Void;

    // ── ESTADO ───────────────────────────────────────────────────────────────
    var textFinished:Bool   = false;
    var dialogueOpened:Bool = false;
    var dialogueStarted:Bool= false;
    var isEnding:Bool       = false;

    // ── PORTRAITS + BOXES CACHE ──────────────────────────────────────────────
    var portraitCache:Map<String, FlxSprite> = new Map();
    var boxCache:Map<String, FlxSprite>      = new Map();
    var activePortrait:FlxSprite             = null;

    // ── SCRIPT ───────────────────────────────────────────────────────────────
    var ctx:DialogueScriptContext;
    #if HSCRIPT_ALLOWED
    var _script:HScriptInstance;
    #end

    // ─────────────────────────────────────────────────────────────────────────
    // CONSTRUCTOR
    // ─────────────────────────────────────────────────────────────────────────

    public function new(songName:String, conversationName:String = 'intro')
    {
        super();

        // ── 1. Cargar datos ──────────────────────────────────────────────────
        conversation = DialogueData.loadConversation(songName, conversationName);
        if (conversation == null)
        {
            trace('[DialogueBox] ERROR: no se encontró conversación para "$songName"');
            conversation = _dummyConversation();
        }

        skin = DialogueData.loadSkin(conversation.skinName);
        if (skin == null)
        {
            trace('[DialogueBox] ERROR: no se encontró skin "${conversation.skinName}"');
            skin = DialogueData.createEmptySkin(conversation.skinName, 'pixel');
        }

        if (conversation.messages == null || conversation.messages.length == 0)
            conversation.messages = _dummyMessages();

        currentStyle = switch (skin.style.toLowerCase())
        {
            case 'pixel':  DialogueStyle.PIXEL;
            case 'normal': DialogueStyle.NORMAL;
            default:       DialogueStyle.CUSTOM;
        };

        // ── 2. Crear capas ───────────────────────────────────────────────────
        _bgLayer       = _makeLayer();
        _portraitLayer = _makeLayer();
        _boxLayer      = _makeLayer();
        _textLayer     = _makeLayer();
        _uiLayer       = _makeLayer();
        _overlayLayer  = _makeLayer();

        // ── 3. Crear contexto y asignarle las capas ──────────────────────────
        ctx = new DialogueScriptContext(this, skin, conversation);
        ctx.bgLayer       = _bgLayer;
        ctx.portraitLayer = _portraitLayer;
        ctx.boxLayer      = _boxLayer;
        ctx.textLayer     = _textLayer;
        ctx.uiLayer       = _uiLayer;
        ctx.overlayLayer  = _overlayLayer;

        // ── 4. Cargar HScript (si la skin lo define) ─────────────────────────
        _loadScript();

        // ── 5. Construir elementos visuales (respetando overrides del script) ─
        _buildBackground();
        _buildDialogueBox();
        _buildTextArea();
        _buildControlsText();

        // ── 6. Sincronizar ctx con los widgets creados ───────────────────────
        _syncCtxWidgets();

        trace('[DialogueBox] OK — conversación: ${conversation.name} | skin: ${skin.name} | mensajes: ${conversation.messages.length}');
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SCRIPT
    // ─────────────────────────────────────────────────────────────────────────

    function _loadScript():Void
    {
        #if HSCRIPT_ALLOWED
        var scriptPath = DialogueData.getScriptPath(skin);
        if (scriptPath == null)
            return;

        _script = new HScriptInstance('dialogue_${skin.name}', scriptPath);

        // Exponer variables al script ANTES de ejecutarlo
        _script.set('ctx', ctx);
        // Aliases cómodos
        //_script.set('FlxColor',  FlxColor);
        _script.set('FlxG',      FlxG);

        // Cargar y ejecutar el archivo → define las funciones globales
        #if sys
        if (!sys.FileSystem.exists(scriptPath))
        {
            trace('[DialogueBox] WARNING: scriptFile no encontrado en "$scriptPath"');
            _script = null;
            return;
        }
        var code = sys.io.File.getContent(scriptPath);
        _script.loadString(code);
        #end

        // Llamar a onCreate() — aquí el script configura los callbacks
        _callScript('onCreate');
        #end
    }

    /**
     * Llama a una función del script si existe.
     * @return El valor devuelto por el script, o null.
     */
    function _callScript(funcName:String, ?args:Array<Dynamic>):Dynamic
    {
        #if HSCRIPT_ALLOWED
        if (_script == null || !_script.active)
            return null;
        _syncCtxState();
        return _script.call(funcName, args ?? []);
        #else
        return null;
        #end
    }

    /**
     * Sincroniza el estado actual con ctx para que el script vea valores frescos.
     */
    inline function _syncCtxState():Void
    {
        ctx._syncState(currentMessageIndex, textFinished, dialogueOpened, dialogueStarted, isEnding);
    }

    /**
     * Sincroniza los widgets con ctx (llamar tras crearlos o cambiarlos).
     */
    function _syncCtxWidgets():Void
    {
        ctx.bgFade       = bgFade;
        ctx.box          = box;
        ctx.textField    = swagDialogue;
        ctx.dropShadow   = dropText;
        ctx.controlsText = controlsText;
        ctx.activePortrait = activePortrait;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CONSTRUCCIÓN DE ELEMENTOS VISUALES
    // ─────────────────────────────────────────────────────────────────────────

    function _buildBackground():Void
    {
        // ── Override por script ──────────────────────────────────────────────
        if (ctx.onCreateBackground != null)
        {
            ctx.onCreateBackground();
            return;
        }

        // ── Default: fade semitransparente ───────────────────────────────────
        var bgColor = FlxColor.fromString(skin.backgroundColor ?? '#000000');

        bgFade = new FlxSprite(-200, -200);
        bgFade.makeGraphic(Std.int(FlxG.width * 1.3), Std.int(FlxG.height * 1.3), bgColor);
        bgFade.scrollFactor.set();
        bgFade.alpha = 0;
        _bgLayer.add(bgFade);

        var fadeTime = skin.fadeTime ?? 0.83;
        new FlxTimer().start(fadeTime / 5, function(tmr:FlxTimer)
        {
            bgFade.alpha += (1 / 5) * 0.7;
            if (bgFade.alpha > 0.7) bgFade.alpha = 0.7;
        }, 5);
    }

    function _buildDialogueBox():Void
    {
        // Determinar nombre de la caja
        var firstMsg  = conversation.messages[0];
        var boxName   = firstMsg.boxSprite;

        if (boxName == null || boxName == '')
        {
            for (k in skin.boxes.keys()) { boxName = k; break; }
        }

        if (boxName == null)
        {
            // Sin cajas en la skin — crear placeholder
            box = new FlxSprite(0, FlxG.height - 200);
            box.makeGraphic(Std.int(FlxG.width * 0.8), 200, FlxColor.WHITE);
            box.screenCenter(X);
            _boxLayer.add(box);
            return;
        }

        box = _loadBox(boxName);

        if (box != null)
        {
            // Animación de apertura
            if (box.animation != null)
            {
                if (box.animation.exists('normalOpen'))
                    box.animation.play('normalOpen');
                else if (box.animation.exists('open'))
                    box.animation.play('open');
            }
        }
    }

    function _buildTextArea():Void
    {
        var textConfig = skin.textConfig;

        if (textConfig == null)
        {
            textConfig = switch (currentStyle)
            {
                case PIXEL:  { x: 240,  y: 500,              width: 800,                     size: 32, font: "Pixel Arial 11 Bold", color: "#3F2021" };
                case NORMAL: { x: 180,  y: FlxG.height - 250, width: Std.int(FlxG.width * 0.7), size: 42, font: "VCR OSD Mono",        color: "#000000" };
                default:     { x: 100,  y: FlxG.height - 250, width: Std.int(FlxG.width * 0.8), size: 32, font: "Arial",               color: "#FFFFFF" };
            };
        }

        // Sombra (solo pixel)
        if (currentStyle == PIXEL)
        {
            dropText = new FlxText(textConfig.x + 2, textConfig.y + 2, textConfig.width, '', textConfig.size);
            dropText.font  = textConfig.font;
            dropText.color = 0xFFD89494;
            _textLayer.add(dropText);
        }

        // Texto principal
        swagDialogue = new FlxTypeText(textConfig.x, textConfig.y, textConfig.width, '', textConfig.size);
        swagDialogue.font  = textConfig.font;
        swagDialogue.color = FlxColor.fromString(textConfig.color);

        // Sonido de tipeo
        var soundPath = conversation.messages[0].sound;
        if (soundPath == null)
        {
            soundPath = switch (currentStyle)
            {
                case PIXEL:  'pixelText';
                case NORMAL: 'dialogueText';
                default:     'pixelText';
            };
        }

        try   { swagDialogue.sounds = [FlxG.sound.load(Paths.sound(soundPath), 0.6)]; }
        catch (_:Dynamic) { trace('[DialogueBox] WARNING: no se pudo cargar el sonido "$soundPath"'); }

        _textLayer.add(swagDialogue);
    }

    function _buildControlsText():Void
    {
        controlsText = new FlxText(0, 0, 'Press ENTER to continue | SHIFT to skip');
        controlsText.size = 20;
        controlsText.x    = FlxG.width - controlsText.width - 60;
        controlsText.y    = FlxG.height - 100;
        controlsText.font = Paths.font('Funkin.otf');
        controlsText.setBorderStyle(FlxTextBorderStyle.OUTLINE, FlxColor.BLACK, 2, 1);
        controlsText.color = FlxColor.WHITE;
        controlsText.scrollFactor.set();
        _uiLayer.add(controlsText);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CARGA DE ASSETS (CAJAS Y PORTRAITS)
    // ─────────────────────────────────────────────────────────────────────────

    function _loadBox(boxName:String):FlxSprite
    {
        if (boxCache.exists(boxName))
            return boxCache.get(boxName);

        // ── Override por script ──────────────────────────────────────────────
        if (ctx.onCreateBox != null)
        {
            var custom = ctx.onCreateBox(boxName);
            if (custom != null)
            {
                boxCache.set(boxName, custom);
                // Añadir a la capa si no lo está ya
                if (!_boxLayer.members.contains(custom))
                    _boxLayer.add(custom);
                return custom;
            }
        }

        // ── Default ──────────────────────────────────────────────────────────
        var config = skin.boxes.get(boxName);
        if (config == null)
        {
            trace('[DialogueBox] WARNING: BoxConfig no encontrada: $boxName');
            return null;
        }

        var fileBase   = haxe.io.Path.withoutExtension(config.fileName);
        var assetKey   = DialogueData.getBoxAssetPath(skin.name, fileBase);
        var staticPath = Paths.resolve(DialogueData.getBoxAssetPath(skin.name, config.fileName));

        var boxSprite = new FlxSprite(config.x ?? 0, config.y ?? 0);

        try
        {
            boxSprite.frames = Paths.getSparrowAtlasCutscene(assetKey);

            if (boxSprite.frames != null)
            {
                if (currentStyle == PIXEL)
                {
                    boxSprite.animation.addByPrefix('normalOpen', config.animation ?? 'Text Box Appear', 24, false);
                    boxSprite.animation.addByIndices('normal',    config.animation ?? 'Text Box Appear', [4], '', 24);
                    boxSprite.animation.addByPrefix('open',       config.animation ?? 'Text Box Appear', 24, false);
                    var pixelZoom = 6.0;
                    boxSprite.setGraphicSize(Std.int(boxSprite.width * pixelZoom * 0.9));
                }
                else
                {
                    boxSprite.animation.addByPrefix('normalOpen', 'Speech Bubble Normal Open', 24, false);
                    boxSprite.animation.addByPrefix('normal',     'speech bubble normal',       24, true);
                    boxSprite.animation.addByPrefix('loud',       'speech bubble loud open',    24, false);
                    boxSprite.animation.addByPrefix('open',       'Speech Bubble Normal Open',  24, false);
                }
            }
        }
        catch (_:Dynamic)
        {
            trace('[DialogueBox] Cargando caja como imagen estática: $staticPath');
            boxSprite.loadGraphic(staticPath);
        }

        boxSprite.scale.set(config.scaleX ?? 1.0, config.scaleY ?? 1.0);
        boxSprite.updateHitbox();
        boxSprite.screenCenter(X);

        _boxLayer.add(boxSprite);
        boxCache.set(boxName, boxSprite);

        return boxSprite;
    }

    function _loadPortrait(portraitName:String):FlxSprite
    {
        // ── Override por script ──────────────────────────────────────────────
        if (ctx.onCreatePortrait != null)
        {
            var custom = ctx.onCreatePortrait(portraitName);
            if (custom != null)
            {
                if (!_portraitLayer.members.contains(custom))
                    _portraitLayer.add(custom);
                return custom;
            }
        }

        // ── Default ──────────────────────────────────────────────────────────
        var config = skin.portraits.get(portraitName);
        if (config == null)
        {
            trace('[DialogueBox] WARNING: PortraitConfig no encontrada: $portraitName');
            return null;
        }

        // getSparrowAtlasCutscene añade .png / .xml por su cuenta → necesitamos
        // la clave SIN extensión aunque config.fileName la lleve (ej: "bf.png" → "bf").
        var fileBase   = haxe.io.Path.withoutExtension(config.fileName);
        var assetKey   = DialogueData.getPortraitAssetPath(skin.name, fileBase);
        // Para la carga estática usamos el path completo ya resuelto por el mod.
        var staticPath = Paths.resolve(DialogueData.getPortraitAssetPath(skin.name, config.fileName));

        var portrait = new FlxSprite(config.x ?? 0, config.y ?? 0);

        try
        {
            portrait.frames = Paths.getSparrowAtlasCutscene(assetKey);
            if (portrait.frames != null)
            {
                portrait.animation.addByPrefix('idle',  config.animation ?? 'idle',  24, true);
                portrait.animation.addByPrefix('enter', config.animation ?? 'enter', 24, false);
                portrait.animation.addByPrefix('talk',  config.animation ?? 'talk',  24, true);

                if (currentStyle == PIXEL)
                {
                    var pixelZoom = 6.0;
                    portrait.setGraphicSize(Std.int(portrait.width * pixelZoom * 0.9));
                }
            }
        }
        catch (_:Dynamic)
        {
            trace('[DialogueBox] Cargando portrait como imagen estática: $staticPath');
            portrait.loadGraphic(staticPath);
        }

        portrait.scale.set(config.scaleX ?? 1.0, config.scaleY ?? 1.0);
        portrait.flipX = config.flipX ?? false;
        portrait.updateHitbox();
        portrait.scrollFactor.set();
        portrait.visible = false;

        _portraitLayer.add(portrait);
        return portrait;
    }

    function _getOrCreatePortrait(portraitName:String):FlxSprite
    {
        if (portraitCache.exists(portraitName))
            return portraitCache.get(portraitName);

        var portrait = _loadPortrait(portraitName);
        if (portrait != null)
            portraitCache.set(portraitName, portrait);

        return portrait;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // UPDATE
    // ─────────────────────────────────────────────────────────────────────────

    override function update(elapsed:Float):Void
    {
        super.update(elapsed);

        // Actualizar sombra
        if (dropText != null && swagDialogue != null)
            dropText.text = swagDialogue.text;

        // Hook onUpdate del script
        if (ctx.onUpdate != null)
        {
            _syncCtxState();
            ctx.onUpdate(elapsed);
        }
        else
        {
            _callScript('onUpdate', [elapsed]);
        }

        // Detectar fin de animación de apertura de la caja
        if (!dialogueOpened)
        {
            if (box != null && box.animation != null && box.animation.curAnim != null)
            {
                var aName = box.animation.curAnim.name;
                if ((aName == 'normalOpen' || aName == 'open') && box.animation.curAnim.finished)
                {
                    if (box.animation.exists('normal'))
                        box.animation.play('normal');
                    dialogueOpened = true;
                }
            }
            else
            {
                // Sin animación de apertura → abrir de inmediato
                dialogueOpened = true;
            }
        }

        // Iniciar primer mensaje
        if (dialogueOpened && !dialogueStarted)
        {
            _startDialogue();
            dialogueStarted = true;
        }

        _handleInput();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INPUT
    // ─────────────────────────────────────────────────────────────────────────

    function _handleInput():Void
    {
        if (!dialogueStarted || isEnding)
            return;

        // Skip con SHIFT
        if (FlxG.keys.justPressed.SHIFT)
        {
            var consumed = _dispatchInput('skip');
            if (!consumed)
            {
                FlxG.sound.play(Paths.sound('clickText'), 0.8);
                _endDialogue();
            }
            return;
        }

        // Avanzar con ENTER / SPACE
        if (FlxG.keys.justPressed.ENTER || FlxG.keys.justPressed.SPACE)
        {
            var consumed = _dispatchInput('accept');
            if (!consumed)
                _defaultAccept();
        }
    }

    /**
     * Llama ctx.onInput o al script, devuelve true si el input fue consumido.
     */
    function _dispatchInput(action:String):Bool
    {
        _syncCtxState();

        // Prioridad: callback en ctx (asignado en onCreate())
        if (ctx.onInput != null)
            return ctx.onInput(action) == true;

        // Fallback: función onInput() definida en el script
        #if HSCRIPT_ALLOWED
        if (_script != null && _script.active && _script.hasFunction('onInput'))
        {
            _syncCtxState();
            var result = _script.call('onInput', [action]);
            return result == true;
        }
        #end

        return false;
    }

    function _defaultAccept():Void
    {
        if (!textFinished)
        {
            swagDialogue.skip();
            textFinished = true;
            return;
        }

        FlxG.sound.play(Paths.sound('clickText'), 0.8);
        currentMessageIndex++;

        if (currentMessageIndex >= conversation.messages.length)
            _endDialogue();
        else
            _startDialogue();
    }

    // ─────────────────────────────────────────────────────────────────────────
    // INICIO DE MENSAJE
    // ─────────────────────────────────────────────────────────────────────────

    function _startDialogue():Void
    {
        if (conversation == null || conversation.messages == null)
        {
            _endDialogue();
            return;
        }

        if (currentMessageIndex >= conversation.messages.length)
        {
            _endDialogue();
            return;
        }

        var msg = conversation.messages[currentMessageIndex];
        if (msg == null)
        {
            _endDialogue();
            return;
        }

        textFinished = false;
        _syncCtxWidgets();

        // ── Llamar hook onMessageStart ───────────────────────────────────────
        _syncCtxState();

        if (ctx.onMessageStart != null)
            ctx.onMessageStart(msg);

        _callScript('onMessageStart', [msg]);

        // ── Actualizar texto ─────────────────────────────────────────────────
        if (swagDialogue != null)
        {
            swagDialogue.resetText(msg.text ?? '');
            swagDialogue.start(msg.speed ?? 0.04, true, false, null, function()
            {
                textFinished = true;
                _syncCtxState();

                // Hook onMessageEnd
                if (ctx.onMessageEnd != null)
                    ctx.onMessageEnd(msg);

                _callScript('onMessageEnd', [msg]);
            });
        }

        // ── Portrait ─────────────────────────────────────────────────────────
        if (msg.portrait != null && msg.portrait != '')
            _updatePortrait(msg.portrait);
        else if (activePortrait != null)
        {
            activePortrait.visible = false;
            activePortrait = null;
            ctx.activePortrait = null;
        }

        // ── Caja ─────────────────────────────────────────────────────────────
        if (msg.boxSprite != null && msg.boxSprite != '')
            _updateBox(msg.boxSprite);

        // ── Animación de burbuja ─────────────────────────────────────────────
        if (box != null && box.animation != null && msg.bubbleType != null)
        {
            switch (msg.bubbleType)
            {
                case 'loud':
                    if (box.animation.exists('loud'))  box.animation.play('loud');
                case 'angry':
                    if (box.animation.exists('angry')) box.animation.play('angry');
                case 'evil':
                    if (box.animation.exists('evil'))  box.animation.play('evil');
                case 'normal' | _:
                    if (box.animation.exists('normal')) box.animation.play('normal');
            }
        }

        // ── Música ───────────────────────────────────────────────────────────
        if (msg.music != null && msg.music != '')
            FlxG.sound.playMusic(Paths.music(msg.music), 0.7);
    }

    function _updatePortrait(portraitName:String):Void
    {
        if (activePortrait != null)
            activePortrait.visible = false;

        var newPortrait = _getOrCreatePortrait(portraitName);
        if (newPortrait != null)
        {
            newPortrait.visible = true;

            if (newPortrait.animation != null)
            {
                if (newPortrait.animation.exists('enter'))
                    newPortrait.animation.play('enter');
                else if (newPortrait.animation.exists('idle'))
                    newPortrait.animation.play('idle');
            }

            activePortrait     = newPortrait;
            ctx.activePortrait = newPortrait;
        }
    }

    function _updateBox(boxName:String):Void
    {
        // Comprobar si ya usamos esa caja
        for (name => sprite in boxCache)
            if (sprite == box && name == boxName)
                return;

        var newBox = _loadBox(boxName);
        if (newBox == null)
            return;

        // Ocultar la caja anterior (sigue en caché, no se destruye)
        if (box != null)
            box.visible = false;

        box = newBox;
        box.visible = true;
        ctx.box = box;

        if (box.animation != null)
        {
            if (box.animation.exists('normalOpen'))
                box.animation.play('normalOpen');
            else if (box.animation.exists('open'))
                box.animation.play('open');
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // CIERRE
    // ─────────────────────────────────────────────────────────────────────────

    function _endDialogue():Void
    {
        if (isEnding) return;
        isEnding = true;

        // Hook onEnd
        _syncCtxState();
        if (ctx.onEnd != null)
            ctx.onEnd();
        _callScript('onEnd');

        // Fade-out de música
        if (FlxG.sound.music != null)
        {
            FlxG.sound.music.fadeOut(1.2, 0, function(_)
            {
                FlxG.sound.music.stop();
                FlxG.sound.music.kill();
                if (finishThing != null) finishThing();
            });
        }
        else if (finishThing != null)
        {
            finishThing();
        }

        // Fade-out visual
        new FlxTimer().start(0.2, function(tmr:FlxTimer)
        {
            if (box         != null) box.alpha         -= 1 / 5;
            if (bgFade      != null) bgFade.alpha       -= 1 / 5 * 0.7;
            if (swagDialogue!= null) swagDialogue.alpha -= 1 / 5;
            if (dropText    != null) dropText.alpha      = swagDialogue?.alpha ?? 0;
            if (controlsText!= null) controlsText.alpha -= 1 / 5;

            for (portrait in portraitCache)
                portrait.visible = false;

        }, 5);

        new FlxTimer().start(1.2, function(_) { kill(); });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // API PÚBLICA PARA DialogueScriptContext
    // ─────────────────────────────────────────────────────────────────────────

    /** Llamado por ctx.advance() — avanza al siguiente mensaje o cierra. */
    public function scriptAdvance():Void
    {
        if (!dialogueStarted || isEnding) return;

        if (!textFinished)
        {
            if (swagDialogue != null) swagDialogue.skip();
            textFinished = true;
            return;
        }

        FlxG.sound.play(Paths.sound('clickText'), 0.8);
        currentMessageIndex++;

        if (currentMessageIndex >= conversation.messages.length)
            _endDialogue();
        else
            _startDialogue();
    }

    /** Llamado por ctx.skip() — cierra el diálogo inmediatamente. */
    public function scriptSkip():Void
    {
        if (!isEnding)
        {
            FlxG.sound.play(Paths.sound('clickText'), 0.8);
            _endDialogue();
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // HELPERS PRIVADOS
    // ─────────────────────────────────────────────────────────────────────────

    inline function _makeLayer():FlxSpriteGroup
    {
        var g = new FlxSpriteGroup();
        add(g);
        return g;
    }

    function _dummyConversation():DialogueConversation
    {
        return {
            name: 'error',
            skinName: 'default',
            messages: _dummyMessages()
        };
    }

    function _dummyMessages():Array<DialogueMessage>
    {
        return [{
            character: 'error',
            text: 'Failed to load dialogue!',
            bubbleType: 'normal',
            speed: 0.04
        }];
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DESTROY
    // ─────────────────────────────────────────────────────────────────────────

    override public function destroy():Void
    {
        // Liberar el intérprete HScript
        #if HSCRIPT_ALLOWED
        if (_script != null)
        {
            try _script.dispose() catch (_:Dynamic) {}
            _script = null;
        }
        #end

        // Destruir portraits en caché
        for (_ => portrait in portraitCache)
            if (portrait != null) try portrait.destroy() catch (_:Dynamic) {}
        portraitCache.clear();

        // Destruir cajas en caché
        for (_ => boxSpr in boxCache)
            if (boxSpr != null) try boxSpr.destroy() catch (_:Dynamic) {}
        boxCache.clear();

        ctx = null;
        super.destroy();
    }
}
