package;

import flixel.util.FlxTimer;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import funkin.data.KeyBinds;
import funkin.menus.TitleState;
import funkin.gameplay.objects.hud.Highscore;
import data.PlayerSettings;
import funkin.states.LoadingState;
import funkin.graphics.shaders.ShaderManager;
import funkin.scripting.ScriptHandler;
import openfl.utils.Assets as OpenFlAssets;

using StringTools;

import Paths;

class CacheState extends funkin.states.MusicBeatState
{
    var loadingBar:FlxSprite;
    var loadingText:FlxText;
    var loadingPercentage:FlxText;

    var assetsToCache:Array<AssetInfo> = [];
    var currentAssetIndex:Int = 0;
    var totalAssets:Int = 0;

    var loadingComplete:Bool = false;
    var barMaxWidth:Float = 0;

    // Bloquea el procesamiento del siguiente asset hasta que el async actual termine.
    // Sin esto, update() podría lanzar varios loadBitmapData/loadSound en paralelo,
    // saturando la RAM y bloqueando el hilo GL igualmente.
    var _asyncPending:Bool = false;

    // En Android procesar 1 asset por frame para no bloquear el hilo principal.
    // Cargar 8 a la vez (comportamiento desktop) congela el render loop en móvil
    // porque cada getGraphic/getSound es síncrono y los assets pesados (UI/alphabet)
    // pueden tardar >100ms, disparando el watchdog ANR del sistema.
    #if (android || mobileC)
    static inline final ASSETS_PER_FRAME:Int = 1;
    #else
    static inline final ASSETS_PER_FRAME:Int = 8;
    #end

    override function create()
    {
        // NOTA: PathsCache.beginSession() es llamado automáticamente por la señal
        // preStateSwitch en FunkinCache.init(). No llamarlo aquí para evitar doble
        // beginSession() que causaría que los assets del state anterior queden huérfanos.

        funkin.system.CursorManager.hide();

        // ── UI ─────────────────────────────────────────────────────────────
        var barBG:FlxSprite = new FlxSprite(0, 500).makeGraphic(FlxG.width - 100, 40, 0xFF333333);
        barBG.screenCenter(X);
        add(barBG);

        barMaxWidth = FlxG.width - 110;

        loadingBar = new FlxSprite(barBG.x + 5, barBG.y + 5).makeGraphic(10, 30, FlxColor.LIME);
        add(loadingBar);

        loadingText = new FlxText(0, 450, FlxG.width, "Loading...");
        loadingText.setFormat(Paths.font("Funkin.otf"), 28, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
        add(loadingText);

        loadingPercentage = new FlxText(0, 550, FlxG.width, "0%");
        loadingPercentage.setFormat(Paths.font("Funkin.otf"), 24, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
        add(loadingPercentage);

        // ── Lista mínima de assets esenciales ──────────────────────────────
        buildEssentialList();

        // ── Scripts globales ────────────────────────────────────────────────
        // FIX (Android): ScriptHandler.loadGlobalScripts() usaba Sys.programPath()
        // + FileSystem.readDirectory() síncrono, lo que en Android puede tardar
        // varios segundos bloqueando el hilo GL y congelando la barra en ~7%.
        // Solución: se registra como un paso más de la cadena de carga (tipo SCRIPTS),
        // de modo que el render loop tiene garantizado al menos 1 frame renderizado
        // antes de ejecutarlo. El comportamiento lógico es idéntico al anterior:
        // los scripts quedan listos antes de entrar a TitleState.
        assetsToCache.push({ type: SCRIPTS, path: '', permanent: false });

        totalAssets = assetsToCache.length;
        super.create();
    }

    /**
     * Solo cargamos lo que el juego necesita ANTES de llegar al TitleState.
     * Todo lo demás (stages, personajes, canciones) se carga on-demand.
     */
    function buildEssentialList():Void
    {
        #if (!android && !mobileC && !ios)
        final sounds:Array<String> = [
            "menus/confirmMenu", "menus/cancelMenu", "menus/scrollMenu",
            "intro3", "intro2", "intro1", "introGo",
            "soundtray/Volup", "soundtray/Voldown", "soundtray/VolMAX"
        ];
        for (s in sounds)
            assetsToCache.push({ type: SOUND, path: s, permanent: true });
        #end

        #if (!android && !mobileC && !ios)
        // permanent:true → estos assets de UI se usan en TODOS los states
        // (alphabet en FreeplayState, cursor siempre, soundtray siempre).
        final images:Array<String> = [
            "UI/alphabet",
            "soundtray/volumebox",
            "menu/cursor/cursor-default"
        ];
        for (i in images)
            assetsToCache.push({ type: IMAGE, path: i, permanent: true });
        #end

        #if (android || mobileC || ios)
        final titleImages:Array<String> = [
            "menu/menuBGtitle",       // FlxSprite.loadGraphic en TitleState.create()
            "titlestate/logoBumpin",  // FunkinSprite.loadAsset → loadSparrow → getGraphic
            "titlestate/gfDanceTitle",
            "titlestate/titleEnter"
        ];
        for (i in titleImages)
            assetsToCache.push({ type: IMAGE, path: i, permanent: false });

        // freakyMenu: el mayor responsable del spike de RAM (PCM buffer ~50MB).
        // Se carga aquí 1 frame a la vez. Cuando TitleState.create() llama
        // MusicManager.playWithFade('freakyMenu'), obtiene un cache hit → sin
        // decodificación OGG en el hilo principal → sin spike.
        // permanent:false no importa aquí porque Main.hx ya llama
        // Paths.addExclusion(Paths.music('freakyMenu')) directamente.
        assetsToCache.push({ type: MUSIC, path: 'freakyMenu', permanent: false });
        #end
    }

    override function update(elapsed:Float)
    {
        super.update(elapsed);

        if (loadingComplete) return;

        // En mobile, esperar a que el async del frame anterior termine
        // antes de lanzar el siguiente. Sin este guard, un frame con
        // loadBitmapData en vuelo lanzaría otro idéntico el frame siguiente.
        if (_asyncPending) return;

        // Procesar hasta ASSETS_PER_FRAME assets por frame
        var processed = 0;
        while (processed < ASSETS_PER_FRAME && currentAssetIndex < totalAssets)
        {
            #if (android || mobileC || ios)
            // En móvil, IMAGE y MUSIC se cargan de forma ASÍNCRONA para no
            // bloquear el hilo GL. La función lanza el Future y sale; el callback
            // incrementa currentAssetIndex y limpia _asyncPending cuando termina.
            var asset = assetsToCache[currentAssetIndex];
            if (asset.type == IMAGE || asset.type == MUSIC)
            {
                _asyncPending = true;
                _cacheAssetAsync(asset, function()
                {
                    currentAssetIndex++;
                    _asyncPending = false;
                });
                break; // salir del while; update() volverá el próximo frame
            }
            #end

            cacheAsset(assetsToCache[currentAssetIndex]);
            currentAssetIndex++;
            processed++;
        }

        // Actualizar UI con scaleX en lugar de makeGraphic() (0 alloc)
        final pct:Float = totalAssets > 0 ? currentAssetIndex / totalAssets : 1.0;
        final targetW = barMaxWidth * pct;
        loadingBar.scale.x = targetW / 10; // 10 es el ancho base del makeGraphic inicial
        loadingBar.updateHitbox();
        loadingPercentage.text = Math.floor(pct * 100) + "%";

        if (currentAssetIndex >= totalAssets && !_asyncPending)
            completeLoading();
    }

    function cacheAsset(asset:AssetInfo):Void
    {
        try
        {
            switch (asset.type)
            {
                case SOUND:
                    final path = Paths.sound(asset.path);
                    final snd = Paths.getSound(path);
                    // Solo marcar permanente si el asset realmente debe sobrevivir
                    // a todos los cambios de state. Para assets específicos de un
                    // state (e.g., sonidos de intro que solo usa TitleState),
                    // permanent:false evita la retención indefinida en _permanentSounds.
                    if (snd != null && asset.permanent)
                        Paths.cache.addExclusion(path);

                case IMAGE:
                    final path = Paths.image(asset.path);
                    final g = Paths.getGraphic(asset.path);
                    // FIX memory leak: solo llamar addExclusion para assets
                    // genuinamente globales (UI/alphabet, cursor, soundtray).
                    // Los assets de TitleState (logoBumpin, gfDanceTitle, etc.)
                    // con permanent:false se pre-calientan aquí para evitar el
                    // freeze, pero NO se marcan permanentes: se liberan
                    // normalmente en postStateSwitch cuando el jugador deja TitleState.
                    if (g != null && asset.permanent)
                        Paths.cache.addExclusion(path);

                case MUSIC:
                    // Igual que SOUND pero usando Paths.music() para la ruta.
                    // Necesario para freakyMenu: su path es assets/music/freakyMenu.ogg,
                    // no assets/sounds/. Paths.getSound() acepta el path completo.
                    final path = Paths.music(asset.path);
                    final snd = Paths.getSound(path);
                    if (snd != null && asset.permanent)
                        Paths.cache.addExclusion(path);

                case SCRIPTS:
                    // FIX (Android): ejecutado aquí, después de que el render loop
                    // ya pintó al menos un frame, evitando el freeze en ~7%.
                    // Rescannear global scripts garantiza que los menús del mod activo
                    // (TitleState, MainMenu, FreeplayState…) ya tengan sus hooks.
                    ScriptHandler.loadGlobalScripts();
            }
        }
        catch (_:Dynamic) {}
    }

    #if (android || mobileC || ios)
    /**
     * Versión asíncrona de cacheAsset() para IMAGE y MUSIC en móvil.
     *
     * openfl.utils.Assets.loadBitmapData() / loadSound() usan el sistema
     * de Futures de Lime, que resuelve la carga en un hilo de fondo (nativo)
     * y despacha el resultado al hilo principal cuando termina. De este modo
     * el hilo GL nunca se bloquea más de 1 frame, independientemente del
     * tamaño del asset.
     *
     * El callback `onDone` debe ser llamado SIEMPRE (incluso en error) para
     * que la barra de progreso avance y el juego no se quede bloqueado para
     * siempre esperando un Future que nunca resolvió.
     */
    function _cacheAssetAsync(asset:AssetInfo, onDone:Void->Void):Void
    {
        switch (asset.type)
        {
            case IMAGE:
                final path = Paths.image(asset.path);
                if (Paths.cache.hasValidGraphic(path))
                {
                    // Ya en caché (e.g. segundo intento): saltar sin I/O
                    if (asset.permanent) Paths.cache.addExclusion(path);
                    onDone();
                    return;
                }
                OpenFlAssets.loadBitmapData(path)
                    .onComplete(function(bmp:openfl.display.BitmapData)
                    {
                        if (bmp != null)
                        {
                            var optimized = funkin.assets.AssetOptimizer.optimizeBitmapData(bmp);
                            if (optimized != bmp)
                                try { funkin.cache.FunkinCache.instance.setBitmapData(path, optimized); } catch (_:Dynamic) {}
                            Paths.cache.getGraphic(path, optimized, true);
                            if (asset.permanent) Paths.cache.addExclusion(path);
                        }
                        onDone();
                    })
                    .onError(function(_) { onDone(); });

            case MUSIC:
                final path = Paths.music(asset.path);
                if (Paths.cache.hasSound(path))
                {
                    if (asset.permanent) Paths.cache.addExclusion(path);
                    onDone();
                    return;
                }
                OpenFlAssets.loadSound(path)
                    .onComplete(function(snd:openfl.media.Sound)
                    {
                        if (snd != null)
                        {
                            Paths.cache.getSound(path, snd);
                            if (asset.permanent) Paths.cache.addExclusion(path);
                        }
                        onDone();
                    })
                    .onError(function(_) { onDone(); });

            default:
                // SOUND y SCRIPTS: síncrono (son rápidos o ya tienen su propio fix)
                cacheAsset(asset);
                onDone();
        }
    }
    #end

    function completeLoading():Void
    {
        loadingComplete = true;
        loadingText.text = "Ready!";
        loadingPercentage.text = "100%";

        #if (android || mobileC || ios)
        FlxG.signals.postStateSwitch.addOnce(function()
        {
            // postStateSwitch dispara justo después de create() del nuevo state.
            // Usamos ENTER_FRAME para garantizar que al menos UN render real
            // ocurrió antes de tocar el GL context con ShaderFilter.
            var stage = openfl.Lib.current.stage;
            var listener:openfl.events.Event->Void = null;
            listener = function(_:openfl.events.Event):Void
            {
                stage.removeEventListener(openfl.events.Event.ENTER_FRAME, listener);
                ShaderManager.init();
            };
            stage.addEventListener(openfl.events.Event.ENTER_FRAME, listener);
        });

        funkin.transitions.StateTransition.setNext('none');

        var framesLeft:Int = 6;
        var stage = openfl.Lib.current.stage;
        var frameListener:openfl.events.Event->Void = null;
        frameListener = function(_:openfl.events.Event):Void
        {
            framesLeft--;
            if (framesLeft > 0) return;
            stage.removeEventListener(openfl.events.Event.ENTER_FRAME, frameListener);
            haxe.Timer.delay(goToTitle, 400);
        };
        stage.addEventListener(openfl.events.Event.ENTER_FRAME, frameListener);

        #else
        // Desktop: wait 1 frame + 0.3s, play the loaded sound, then switch.
        new FlxTimer().start(0.016, function(_)
        {
            new FlxTimer().start(0.3, function(_)
            {
                try { FlxG.sound.play(Paths.sound('menus/cacheLoaded'), 0.7); }
                catch (_:Dynamic) {}
                new FlxTimer().start(0.3, function(_) { goToTitle(); });
            });
        });
        #end
    }

    function goToTitle():Void
    {
        #if (!mobileC && !android && !ios)
        FlxG.autoPause = false;
        #else
        FlxG.autoPause = true;
        #end

        funkin.data.EngineSettings.applyFPS();

        #if (!mobileC && !android && !ios)
        funkin.data.EngineSettings.ensureWindowSize();
        // Desktop: init ShaderManager here (safe — no state switch pending yet).
        ShaderManager.init();
        #end
        // Mobile: ShaderManager.init() is called via postStateSwitch listener
        // registered in completeLoading(). Do NOT call it here — the listener
        // handles it after TitleState.create() is done and GL context is stable.

        // NOTE: FlxG.camera.fade removed — it conflicts with StateTransition.
        // The FADE/NONE transition handled by StateTransition is enough.
        // TitleState applies its own intro fade if needed.
        // If an intro.json exists (engine or mod), play IntroState first.
        // IntroState automatically switches to TitleState when it finishes.

        if (!funkin.menus.IntroState.finished && funkin.menus.IntroState.introExists())
            LoadingState.loadAndSwitchState(new funkin.menus.IntroState(), true);
        else
            LoadingState.loadAndSwitchState(new TitleState(), true);
    }
}

typedef AssetInfo = { var type:AssetType; var path:String; var permanent:Bool; }

enum AssetType { SOUND; IMAGE; MUSIC; SCRIPTS; }