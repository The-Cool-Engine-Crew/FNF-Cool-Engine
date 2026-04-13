package funkin.states;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.util.FlxTimer;
import lime.app.Application;
import funkin.menus.MainMenuState;
import funkin.transitions.StateTransition;

/**
 * OutdatedSubState — Pantalla que se muestra cuando la versión local
 * del engine está desactualizada.
 *
 * ─── Integración con el Launcher ────────────────────────────────────────────
 *  Si el usuario llegó al juego a través del launcher de Electron y hay una
 *  actualización, lo más cómodo es reabrirlo para que gestione la descarga.
 *  Esta clase busca el ejecutable del launcher en rutas relativas comunes:
 *
 *    ../launcher/CoolEngineLauncher.exe   (Windows — estructura recomendada)
 *    ../launcher/CoolEngineLauncher       (Linux / Mac)
 *    ./launcher/CoolEngineLauncher.exe    (launcher al lado del binario)
 *
 *  Si no lo encuentra, cae a la URL de GitHub/GameBanana como antes.
 *
 * ─── Controles ───────────────────────────────────────────────────────────────
 *  SPACE / ACCEPT  → Abre el launcher (o la URL de descarga)
 *  ESCAPE / BACK   → Ignorar y continuar al MainMenu
 */
class OutdatedSubState extends funkin.states.MusicBeatState
{
    /** true si el usuario ya eligió "ignorar esta actualización". */
    public static var leftState:Bool = false;

    /** Versión más reciente disponible (rellenada por TitleState). */
    public static var daVersionNeeded:String = '???';

    /** Changelog de la nueva versión (rellenado por TitleState). */
    public static var daChangelogNeeded:String = '';

    /** URL a la que ir si no se puede abrir el launcher. */
    public static var downloadUrl:String = 'https://github.com/The-Cool-Engine-Crew/FNF-Cool-Engine/releases/latest';

    // ── Layout ────────────────────────────────────────────────────────────────

    static final MARGIN:Float = 40;

    override function create():Void
    {
        super.create();

        // Fondo negro sólido
        var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
        add(bg);

        var currentVer:String = Application.current.meta.get('version') ?? '???';

        // ── Header ──────────────────────────────────────────────────────────
        var header:FlxText = new FlxText(MARGIN, 60, FlxG.width - MARGIN * 2,
            '⚠  UPDATE AVAILABLE', 40);
        header.setFormat('VCR OSD Mono', 40, 0xFFFFAA00, CENTER, OUTLINE, FlxColor.BLACK);
        header.alpha = 0;
        add(header);

        // ── Info de versión ──────────────────────────────────────────────────
        var versionInfo:FlxText = new FlxText(MARGIN, 130, FlxG.width - MARGIN * 2,
            'Your version:  $currentVer\nLatest version:  $daVersionNeeded', 26);
        versionInfo.setFormat('VCR OSD Mono', 26, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
        versionInfo.alpha = 0;
        add(versionInfo);

        // ── Separador ────────────────────────────────────────────────────────
        var sep:FlxSprite = new FlxSprite(MARGIN, 220).makeGraphic(
            Std.int(FlxG.width - MARGIN * 2), 2, 0x44FFFFFF);
        sep.alpha = 0;
        add(sep);

        // ── Changelog ────────────────────────────────────────────────────────
        var changelogLabel:FlxText = new FlxText(MARGIN, 235, FlxG.width - MARGIN * 2,
            "What's new:", 22);
        changelogLabel.setFormat('VCR OSD Mono', 22, 0xFF88CCFF, LEFT, OUTLINE, FlxColor.BLACK);
        changelogLabel.alpha = 0;
        add(changelogLabel);

        // Recortar changelog si es muy largo para que no se salga de la pantalla
        var changelogTxt:String = daChangelogNeeded.length > 480
            ? daChangelogNeeded.substr(0, 480) + '...'
            : daChangelogNeeded;

        var changelog:FlxText = new FlxText(MARGIN, 268, FlxG.width - MARGIN * 2,
            changelogTxt.length > 0 ? changelogTxt : '(no changelog provided)', 20);
        changelog.setFormat('VCR OSD Mono', 20, FlxColor.WHITE, LEFT, OUTLINE, FlxColor.BLACK);
        changelog.alpha = 0;
        add(changelog);

        // ── Controles ────────────────────────────────────────────────────────
        var hasLauncher:Bool = _launcherExists();
        var acceptLabel:String = hasLauncher
            ? 'SPACE / ACCEPT  →  Open Launcher to update'
            : 'SPACE / ACCEPT  →  Go to download page';

        var controls:FlxText = new FlxText(MARGIN, FlxG.height - 70,
            FlxG.width - MARGIN * 2,
            '$acceptLabel\n ESCAPE / BACK   →  Ignore and continue', 22);
        controls.setFormat('VCR OSD Mono', 22, 0xFFCCCCCC, CENTER, OUTLINE, FlxColor.BLACK);
        controls.alpha = 0;
        add(controls);

        // ── Fade in de todos los elementos ────────────────────────────────────
        for (obj in [header, versionInfo, sep, changelogLabel, changelog, controls])
            FlxTween.tween(obj, {alpha: 1}, 0.5, {ease: FlxEase.quadOut, startDelay: 0.15});

        #if mobileC
		addTouchMenuControls(true, false);
		#end
    }

    override function update(elapsed:Float):Void
    {
        super.update(elapsed);

        if (controls.ACCEPT)
        {
            // Intentar abrir el launcher; si no existe, abrir la URL
            if (!_openLauncher())
                FlxG.openURL(downloadUrl);
        }

        if (controls.BACK)
        {
            leftState = true;
            StateTransition.switchState(new MainMenuState());
        }
    }

    // ── Launcher helpers ──────────────────────────────────────────────────────

    /**
     * Rutas candidatas donde puede estar el ejecutable del launcher,
     * relativas al directorio de trabajo del juego.
     */
    static final LAUNCHER_PATHS_WIN:Array<String> = [
        '../launcher/CoolEngineLauncher.exe',
        './launcher/CoolEngineLauncher.exe',
        '../CoolEngineLauncher.exe',
    ];
    static final LAUNCHER_PATHS_UNIX:Array<String> = [
        '../launcher/CoolEngineLauncher',
        './launcher/CoolEngineLauncher',
        '../CoolEngineLauncher',
    ];

    /** Devuelve true si se encuentra el ejecutable del launcher en el disco. */
    static function _launcherExists():Bool
    {
        #if sys
        var paths = #if windows LAUNCHER_PATHS_WIN #else LAUNCHER_PATHS_UNIX #end;
        for (p in paths)
            if (sys.FileSystem.exists(p)) return true;
        #end
        return false;
    }

    /**
     * Intenta abrir el launcher.
     * @return true si se encontró y se lanzó correctamente.
     */
    static function _openLauncher():Bool
    {
        #if sys
        var paths = #if windows LAUNCHER_PATHS_WIN #else LAUNCHER_PATHS_UNIX #end;
        for (p in paths)
        {
            if (!sys.FileSystem.exists(p)) continue;

            try
            {
                var abs = sys.FileSystem.absolutePath(p);
                #if windows
                // En Windows usamos cmd /c start "" para lanzar sin bloquear
                Sys.command('cmd', ['/c', 'start', '', abs]);
                #elseif mac
                Sys.command('open', [abs]);
                #elseif linux
                // nohup para no bloquear el proceso del juego
                Sys.command('bash', ['-c', 'nohup "$0" &', abs]);
                #end
                return true;
            }
            catch (e:Dynamic)
            {
                trace('[OutdatedSubState] No se pudo abrir el launcher ($p): $e');
            }
        }
        #end
        return false;
    }
}
