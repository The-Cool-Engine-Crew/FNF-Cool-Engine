package funkin.cutscenes.dialogue;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.text.FlxText;
import flixel.addons.text.FlxTypeText;
import flixel.util.FlxColor;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.util.FlxTimer;
import funkin.cutscenes.dialogue.DialogueData;

/**
 * DialogueScriptContext — API completa expuesta a los scripts HScript de diálogo.
 *
 * ─── Flujo de ejecución ───────────────────────────────────────────────────────
 *
 *  1. `DialogueBoxImproved` crea las 6 capas y este objeto.
 *  2. Carga el script HScript (skin.scriptFile) y establece `ctx = this`.
 *  3. Llama a `onCreate()` del script — aquí puedes asignar callbacks y crear objetos.
 *  4. A continuación construye los elementos por defecto, pero comprueba cada
 *     callback (`onCreateBackground`, `onCreateBox`, `onCreatePortrait`) antes:
 *     si el script los asignó, los llama en lugar del comportamiento por defecto.
 *  5. Durante el juego llama a `onUpdate`, `onInput`, `onMessageStart`, etc.
 *
 * ─── Ejemplo mínimo (scripts/myFormat.hx) ───────────────────────────────────
 *
 *    // Formato completamente nuevo desde cero
 *    function onCreate() {
 *        // Ocultar todo lo que el motor crearía por defecto
 *        ctx.setDefaultsVisible(false);
 *
 *        // Fondo negro con imagen propia
 *        ctx.loadImage('dialogue/myBg', 0, 0, ctx.bgLayer);
 *
 *        // Reemplazar la caja de diálogo
 *        ctx.onCreateBox = function(boxName) {
 *            var s = ctx.makeSprite(0, 500, ctx.boxLayer);
 *            s.loadGraphic(Paths.image('dialogue/myBox'));
 *            return s;   // devolver el sprite lo usa como ctx.box
 *        };
 *
 *        // Portrait personalizado
 *        ctx.onCreatePortrait = function(charName) {
 *            return ctx.loadCutsceneImage('portraits/' + charName, 50, 100, ctx.portraitLayer);
 *        };
 *
 *        // Campo de texto propio (reemplaza el FlxTypeText por defecto)
 *        var tt = ctx.makeTypeText(90, 515, 820, 30, ctx.textLayer);
 *        tt.font = Paths.font('MyFont.ttf');
 *        ctx.textField = tt;   // registrar como campo principal
 *    }
 *
 *    function onUpdate(elapsed) {
 *        // lógica frame a frame, e.g. parallax, partículas…
 *    }
 *
 *    function onInput(action) {
 *        // action == 'accept' | 'skip'
 *        // Devolver true consume el input (el motor no hace nada más)
 *        if (action == 'accept') {
 *            ctx.advance();
 *            return true;
 *        }
 *        return false;
 *    }
 *
 *    function onMessageStart(msg) {
 *        trace('Habla ' + msg.character + ': ' + msg.text);
 *    }
 *
 *    function onMessageEnd(msg) { }
 *    function onEnd() { }
 *
 * ─── Capas disponibles (orden de render, de atrás a delante) ─────────────────
 *
 *   bgLayer       → fondo (detrás de todo)
 *   portraitLayer → portraits de personajes
 *   boxLayer      → caja de diálogo
 *   textLayer     → texto (FlxTypeText + sombra)
 *   uiLayer       → controles, iconos encima del texto
 *   overlayLayer  → encima de absolutamente todo
 *
 * @author Cool Engine Team
 */
@:keep
class DialogueScriptContext {

    // ── CAPAS ─────────────────────────────────────────────────────────────────

    /** Capa de fondo — detrás de todo. */
    public var bgLayer:FlxSpriteGroup;

    /** Capa de portraits de personajes. */
    public var portraitLayer:FlxSpriteGroup;

    /** Capa de la caja de diálogo. */
    public var boxLayer:FlxSpriteGroup;

    /** Capa del texto (FlxTypeText y drop shadow). */
    public var textLayer:FlxSpriteGroup;

    /** Capa de UI (texto de controles, iconos). */
    public var uiLayer:FlxSpriteGroup;

    /** Capa de overlay — encima de absolutamente todo. */
    public var overlayLayer:FlxSpriteGroup;

    // ── DATOS (read-only para scripts) ────────────────────────────────────────

    /** Skin cargada para este diálogo. */
    public var skin(default, null):DialogueSkin;

    /** Conversación completa (mensajes + referencia a skin). */
    public var conversation(default, null):DialogueConversation;

    /** Índice del mensaje actual (0-based). Actualizado antes de cada hook. */
    public var messageIndex(default, null):Int = 0;

    /** Total de mensajes en la conversación. */
    public var totalMessages(get, never):Int;

    /** Mensaje actual — shortcut a conversation.messages[messageIndex]. */
    public var currentMessage(get, never):DialogueMessage;

    // ── WIDGETS (el script puede leerlos y modificarlos) ─────────────────────

    /**
     * El FlxTypeText que escribe el texto letra a letra.
     * Puedes reemplazarlo por el tuyo propio en onCreate():
     *   ctx.textField = ctx.makeTypeText(..., ctx.textLayer);
     */
    public var textField:FlxTypeText;

    /** Sombra del texto (pixel art). Puede ser null si el estilo no la usa. */
    public var dropShadow:FlxText;

    /**
     * Sprite de la caja de diálogo activa.
     * Se actualiza cada vez que cambia la caja.
     */
    public var box:FlxSprite;

    /** Sprite del fade de fondo semitransparente. */
    public var bgFade:FlxSprite;

    /** Portrait activo en este momento. */
    public var activePortrait:FlxSprite;

    /** Texto de controles (ENTER / SHIFT). */
    public var controlsText:FlxText;

    // ── ESTADO ────────────────────────────────────────────────────────────────

    /** true cuando el texto actual ha terminado de escribirse. */
    public var textFinished:Bool = false;

    /** true cuando la animación de apertura de la caja terminó. */
    public var dialogueOpened:Bool = false;

    /** true cuando se ha llamado a startDialogue() al menos una vez. */
    public var dialogueStarted:Bool = false;

    /** true mientras se está ejecutando la secuencia de cierre. */
    public var isEnding:Bool = false;

    // ── CALLBACKS DE OVERRIDE ─────────────────────────────────────────────────
    //  Asígnalos en onCreate() para reemplazar el comportamiento por defecto.

    /**
     * Si se asigna, se llama EN LUGAR de la creación de fondo por defecto.
     * El script es responsable de todo lo visual del fondo.
     *
     *   ctx.onCreateBackground = function() {
     *       ctx.loadImage('myBg', 0, 0, ctx.bgLayer);
     *   };
     */
    public var onCreateBackground:Void->Void = null;

    /**
     * Si se asigna, se llama al cargar una caja por nombre.
     * Devolver un FlxSprite lo registra como `ctx.box`.
     * Devolver null delega al cargador por defecto.
     *
     *   ctx.onCreateBox = function(boxName) {
     *       var s = ctx.makeSprite(0, 400, ctx.boxLayer);
     *       s.loadGraphic(Paths.image('myBox_' + boxName));
     *       return s;
     *   };
     */
    public var onCreateBox:String->FlxSprite = null;

    /**
     * Si se asigna, se llama al cargar un portrait por nombre.
     * Devolver un FlxSprite lo registra como portrait.
     * Devolver null delega al cargador por defecto.
     *
     *   ctx.onCreatePortrait = function(charName) {
     *       return ctx.loadCutsceneImage('portraits/' + charName, 50, 100, ctx.portraitLayer);
     *   };
     */
    public var onCreatePortrait:String->FlxSprite = null;

    // ── CALLBACKS DE EVENTOS ──────────────────────────────────────────────────

    /**
     * Llamado cuando comienza a mostrarse un nuevo mensaje.
     *
     *   ctx.onMessageStart = function(msg) {
     *       trace('Habla: ' + msg.character + ' — ' + msg.text);
     *   };
     */
    public var onMessageStart:DialogueMessage->Void = null;

    /**
     * Llamado cuando el texto de un mensaje termina de escribirse.
     */
    public var onMessageEnd:DialogueMessage->Void = null;

    /**
     * Llamado cada frame.
     *
     *   ctx.onUpdate = function(elapsed) { mySprite.x += 100 * elapsed; };
     */
    public var onUpdate:Float->Void = null;

    /**
     * Llamado cuando el jugador pulsa una acción.
     * @param action  'accept' (ENTER/SPACE) o 'skip' (SHIFT).
     * @return true para consumir el input (evita el comportamiento por defecto).
     */
    public var onInput:String->Bool = null;

    /**
     * Llamado justo antes de que el diálogo se cierre (antes del fade-out).
     */
    public var onEnd:Void->Void = null;

    // ── REFERENCIA INTERNA ────────────────────────────────────────────────────
    var _owner:DialogueBoxImproved;

    // ── CONSTRUCTOR ───────────────────────────────────────────────────────────

    public function new(owner:DialogueBoxImproved, skin:DialogueSkin, conversation:DialogueConversation) {
        this._owner = owner;
        this.skin   = skin;
        this.conversation = conversation;
    }

    // ── SINCRONIZACIÓN DE ESTADO ──────────────────────────────────────────────
    // Llamado por DialogueBoxImproved antes de cada hook para que el script
    // vea siempre los valores actualizados.

    @:allow(funkin.cutscenes.dialogue.DialogueBoxImproved)
    function _syncState(msgIdx:Int, txtFinished:Bool, opened:Bool, started:Bool, ending:Bool):Void {
        messageIndex    = msgIdx;
        textFinished    = txtFinished;
        dialogueOpened  = opened;
        dialogueStarted = started;
        isEnding        = ending;
    }

    // ── API DE CONTROL ────────────────────────────────────────────────────────

    /**
     * Avanza al siguiente mensaje o cierra el diálogo si era el último.
     * Equivalente a que el jugador pulse ENTER.
     */
    public function advance():Void
        _owner.scriptAdvance();

    /**
     * Cierra el diálogo inmediatamente, independientemente del mensaje actual.
     */
    public function skip():Void
        _owner.scriptSkip();

    /**
     * Muestra todas las letras del mensaje actual instantáneamente.
     */
    public function finishText():Void {
        if (textField != null)
            textField.skip();
        textFinished = true;
    }

    /**
     * Cambia el texto del campo principal y empieza a escribirlo.
     * @param text   Texto a mostrar.
     * @param speed  Segundos entre letra y letra (default 0.04).
     */
    public function showText(text:String, speed:Float = 0.04):Void {
        textFinished = false;
        if (textField == null)
            return;
        textField.resetText(text);
        textField.start(speed, true, false, null, () -> {
            textFinished = true;
            if (onMessageEnd != null)
                onMessageEnd(currentMessage);
        });
        if (dropShadow != null)
            dropShadow.text = '';
    }

    /**
     * Oculta o muestra todo el contenido generado por defecto
     * (bgFade, box, text, controls, shadow).
     * Útil para crear un formato completamente nuevo desde cero.
     *
     *   function onCreate() {
     *       ctx.setDefaultsVisible(false);
     *       // ... construir UI propia ...
     *   }
     */
    public function setDefaultsVisible(visible:Bool):Void {
        if (bgFade      != null) bgFade.visible      = visible;
        if (box         != null) box.visible          = visible;
        if (textField   != null) textField.visible    = visible;
        if (dropShadow  != null) dropShadow.visible   = visible;
        if (controlsText!= null) controlsText.visible = visible;
    }

    // ── FÁBRICA DE OBJETOS VISUALES ───────────────────────────────────────────
    //  Helpers para que los scripts no necesiten importar clases de Flixel.

    /**
     * Crea un FlxSprite vacío y opcionalmente lo añade a una capa.
     *
     *   var s = ctx.makeSprite(100, 200, ctx.bgLayer);
     *   s.makeGraphic(640, 360, 0xFF001122);
     */
    public function makeSprite(x:Float = 0, y:Float = 0, ?layer:FlxSpriteGroup):FlxSprite {
        var s = new FlxSprite(x, y);
        if (layer != null) layer.add(s);
        return s;
    }

    /**
     * Crea un sprite con gráfico de color sólido.
     *
     *   var panel = ctx.makeRect(0, 400, 1280, 320, 0xCC000000, ctx.bgLayer);
     */
    public function makeRect(x:Float, y:Float, w:Int, h:Int, color:FlxColor, ?layer:FlxSpriteGroup):FlxSprite {
        var s = new FlxSprite(x, y);
        s.makeGraphic(w, h, color);
        if (layer != null) layer.add(s);
        return s;
    }

    /**
     * Carga una imagen por path y opcionalmente la añade a una capa.
     * `path` es relativo (igual que Paths.image()).
     *
     *   var bg = ctx.loadImage('dialogue/mybg', 0, 0, ctx.bgLayer);
     */
    public function loadImage(path:String, x:Float = 0, y:Float = 0, ?layer:FlxSpriteGroup):FlxSprite {
        var s = new FlxSprite(x, y);
        s.loadGraphic(Paths.image(path));
        if (layer != null) layer.add(s);
        return s;
    }

    /**
     * Carga una imagen de cutscene por path.
     * Busca en la carpeta de cutscenes del mod activo.
     */
    public function loadCutsceneImage(path:String, x:Float = 0, y:Float = 0, ?layer:FlxSpriteGroup):FlxSprite {
        var s = new FlxSprite(x, y);
        s.loadGraphic(Paths.imageCutscene(path));
        if (layer != null) layer.add(s);
        return s;
    }

    /**
     * Crea un FlxText simple.
     *
     *   var label = ctx.makeText(50, 50, 'Hola mundo', 32, ctx.uiLayer);
     *   label.color = FlxColor.WHITE;
     */
    public function makeText(x:Float = 0, y:Float = 0, text:String = '', size:Int = 24, ?layer:FlxSpriteGroup):FlxText {
        var t = new FlxText(x, y, 0, text, size);
        if (layer != null) layer.add(t);
        return t;
    }

    /**
     * Crea un FlxTypeText (typewriter) con configuración básica.
     * Para usarlo como campo principal del diálogo, asígna ctx.textField:
     *
     *   var tt = ctx.makeTypeText(80, 480, 900, 32, ctx.textLayer);
     *   ctx.textField = tt;
     */
    public function makeTypeText(x:Float, y:Float, fieldWidth:Int, size:Int = 32, ?layer:FlxSpriteGroup):FlxTypeText {
        var t = new FlxTypeText(x, y, fieldWidth, '', size);
        if (layer != null) layer.add(t);
        return t;
    }

    /**
     * Reproduce un tween en cualquier objeto.
     * Eases disponibles: 'linear', 'quadIn', 'quadOut', 'quadInOut',
     *   'cubeIn', 'cubeOut', 'cubeInOut', 'sineIn', 'sineOut', 'sineInOut',
     *   'backIn', 'backOut', 'bounceOut', 'elasticOut', 'expoIn', 'expoOut'.
     *
     *   ctx.tween(mySprite, {alpha: 0}, 0.5, {ease: 'quadOut', onComplete: function(t) { ... }});
     */
    public function tween(target:Dynamic, values:Dynamic, duration:Float, ?options:Dynamic):FlxTween {
        var opts:flixel.tweens.FlxTween.TweenOptions = {};
        if (options != null) {
            if (Reflect.hasField(options, 'ease')) {
                var easeName:String = Reflect.field(options, 'ease');
                opts.ease = switch (easeName) {
                    case 'quadIn':    FlxEase.quadIn;
                    case 'quadOut':   FlxEase.quadOut;
                    case 'quadInOut': FlxEase.quadInOut;
                    case 'cubeIn':    FlxEase.cubeIn;
                    case 'cubeOut':   FlxEase.cubeOut;
                    case 'cubeInOut': FlxEase.cubeInOut;
                    case 'sineIn':    FlxEase.sineIn;
                    case 'sineOut':   FlxEase.sineOut;
                    case 'sineInOut': FlxEase.sineInOut;
                    case 'backIn':    FlxEase.backIn;
                    case 'backOut':   FlxEase.backOut;
                    case 'bounceOut': FlxEase.bounceOut;
                    case 'elasticOut':FlxEase.elasticOut;
                    case 'expoIn':    FlxEase.expoIn;
                    case 'expoOut':   FlxEase.expoOut;
                    default:          FlxEase.linear;
                };
            }
            if (Reflect.hasField(options, 'onComplete'))
                opts.onComplete = Reflect.field(options, 'onComplete');
            if (Reflect.hasField(options, 'loopType'))
                opts.type = Reflect.field(options, 'loopType');
            if (Reflect.hasField(options, 'startDelay'))
                opts.startDelay = Reflect.field(options, 'startDelay');
        }
        return FlxTween.tween(target, values, duration, opts);
    }

    /**
     * Ejecuta una función después de `seconds` segundos.
     *
     *   ctx.delay(1.5, function() { ctx.advance(); });
     */
    public function delay(seconds:Float, callback:Void->Void):FlxTimer {
        return new FlxTimer().start(seconds, function(_) callback());
    }

    /**
     * Ejecuta `callback` repetidamente `loops` veces con intervalo `interval`.
     * loops = 0 → infinito.
     *
     *   ctx.repeat(0.1, 10, function(n) { trace(n); });
     */
    public function repeat(interval:Float, loops:Int, callback:Int->Void):FlxTimer {
        var count = 0;
        return new FlxTimer().start(interval, function(t:FlxTimer) {
            callback(count++);
        }, loops);
    }

    /**
     * Cambia el color del texto de forma instantánea.
     */
    public function setTextColor(color:FlxColor):Void {
        if (textField != null) textField.color = color;
    }

    /**
     * Cambia el tamaño del texto de forma instantánea.
     */
    public function setTextSize(size:Int):Void {
        if (textField != null) textField.size = size;
    }

    /**
     * Reproduce un sonido por nombre.
     *   ctx.playSound('clickText');
     */
    public function playSound(name:String, volume:Float = 1.0):Void {
        try FlxG.sound.play(Paths.sound(name), volume)
        catch (_:Dynamic) {}
    }

    /**
     * Reproduce música.
     *   ctx.playMusic('myDialogueMusic');
     */
    public function playMusic(name:String, volume:Float = 0.7):Void {
        try FlxG.sound.playMusic(Paths.music(name), volume)
        catch (_:Dynamic) {}
    }

    /**
     * Fade rápido de un sprite.
     * direction: 'in' | 'out'
     */
    public function fadeSprite(sprite:FlxSprite, direction:String, duration:Float = 0.3, ?onComplete:Void->Void):Void {
        if (sprite == null) return;
        var target = direction == 'in' ? 1.0 : 0.0;
        if (direction == 'in') sprite.alpha = 0;
        FlxTween.tween(sprite, {alpha: target}, duration, {
            ease: FlxEase.quadOut,
            onComplete: onComplete != null ? function(_) onComplete() : null
        });
    }

    /**
     * Sacudida (shake) de un sprite sobre su posición original.
     *
     *   ctx.shake(ctx.box, 8, 0.5);
     */
    public function shake(sprite:FlxSprite, intensity:Float = 6, duration:Float = 0.4):Void {
        if (sprite == null) return;
        var origX = sprite.x;
        var origY = sprite.y;
        var elapsed = 0.0;
        // Usamos un timer de alta frecuencia para simular shake
        var interval = 0.03;
        var loops = Std.int(duration / interval);
        new FlxTimer().start(interval, function(t:FlxTimer) {
            elapsed += interval;
            if (elapsed >= duration) {
                sprite.x = origX;
                sprite.y = origY;
            } else {
                sprite.x = origX + (Math.random() * 2 - 1) * intensity;
                sprite.y = origY + (Math.random() * 2 - 1) * intensity;
            }
        }, loops);
    }

    // ── GETTERS INTERNOS ──────────────────────────────────────────────────────

    function get_totalMessages():Int
        return conversation?.messages?.length ?? 0;

    function get_currentMessage():DialogueMessage {
        var msgs = conversation?.messages;
        if (msgs == null || messageIndex < 0 || messageIndex >= msgs.length)
            return null;
        return msgs[messageIndex];
    }
}
