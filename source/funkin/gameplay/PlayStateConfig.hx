package funkin.gameplay;

using StringTools;
/**
 * PlayStateConfig - Configuración y constantes
 * Centraliza todas las configuraciones del gameplay
 */
class PlayStateConfig
{
	// === GAMEPLAY CONSTANTS ===
	public static inline var DEFAULT_ZOOM:Float = 1.05;
	public static inline var PIXEL_ZOOM:Float = 6.0;
	public static inline var STRUM_LINE_Y:Float = 50.0;
	public static inline var NOTE_SPAWN_TIME:Float = 3000.0; // ms antes de aparecer
	
	// === TIMING WINDOWS (ms) ===
	public static inline var SICK_WINDOW:Float = 45.0;
	public static inline var GOOD_WINDOW:Float = 90.0;
	public static inline var BAD_WINDOW:Float = 135.0;
	public static inline var SHIT_WINDOW:Float = 166.0;
	
	// === SCORE VALUES ===
	public static inline var SICK_SCORE:Int = 350;
	public static inline var GOOD_SCORE:Int = 200;
	public static inline var BAD_SCORE:Int = 100;
	public static inline var SHIT_SCORE:Int = 50;
	
	// === HEALTH VALUES ===
	public static inline var SICK_HEALTH:Float = 0.1;
	public static inline var GOOD_HEALTH:Float = 0.05;
	public static inline var BAD_HEALTH:Float = -0.03;
	public static inline var SHIT_HEALTH:Float = -0.03;
	public static inline var MISS_HEALTH:Float = -0.04;
	
	// === CAMERA ===
	public static inline var CAM_LERP_SPEED:Float = 2.4;
	public static inline var CAM_ZOOM_AMOUNT:Float = 0.015;
	public static inline var CAM_HUD_ZOOM_AMOUNT:Float = 0.03;
	public static inline var CAM_NOTE_OFFSET:Float = 30.0;
	
	// === OPTIMIZATION ===
	public static inline var NOTE_CULL_DISTANCE:Float = 500.0;
	public static inline var MAX_NOTE_POOL_SIZE:Int = 200;
	public static inline var MAX_SPLASH_POOL_SIZE:Int = 50;
	
	// === INPUT ===
	public static inline var GHOST_TAP_ENABLED:Bool = true;
	public static inline var ANTI_MASH_ENABLED:Bool = true;
	public static inline var MAX_MASH_VIOLATIONS:Int = 8;
	/*
	// === PERFORMANCE ===
	public static inline var FPS_CAP_ENABLED:Bool = true;
	public static inline var FPS_CAP_VALUE:Int = 120;
	public static inline var FPS_UNCAPPED_VALUE:Int = 240;*/
	
	// === VISUAL EFFECTS ===
	public static inline var NOTESPLASH_ENABLED:Bool = true;
	public static inline var DOWNSCROLL_ENABLED:Bool = false;
	public static inline var MIDDLESCROLL_ENABLED:Bool = false;

	/**
	 * MINIMAL MODE (modo osu-like)
	 *
	 * Cuando es `true`, el PlayState omite completamente el stage y los personajes
	 * y sólo inicializa lo mínimo necesario para jugar: strums, notas, HUD y audio.
	 * Útil para un modo rhythm-game puro sin escenario ni animaciones.
	 *
	 * Cómo activarlo antes de entrar al PlayState:
	 *   PlayStateConfig.minimalMode = true;
	 *   // ... asignar SONG, dificultad, etc. como de costumbre ...
	 *   StateTransition.switchState(new PlayState());
	 *
	 * Se reinicia automáticamente a `false` cuando el PlayState hace destroy(),
	 * así que no hace falta limpiarlo manualmente.
	 */
	public static var minimalMode:Bool = false;
	
	// === ANIMATION ===
	public static inline var SING_DURATION:Float = 0.6;
	public static inline var IDLE_THRESHOLD:Float = 0.001;
	public static inline var HOLD_THRESHOLD:Float = 0.001;
	
	// === PATHS ===
	public static inline var UI_PATH:String = 'UI/';
	public static inline var NORMAL_UI_PATH:String = 'UI/normal/';
	public static inline var PIXEL_UI_PATH:String = 'UI/pixelUI/';

	/**
	 * ELIMINADO: MILF_ZOOM_START_BEAT / MILF_ZOOM_END_BEAT / MILF_ZOOM_AMOUNT
	 *
	 * Esas constantes hardcodeaban el comportamiento de zoom mid-song solo para
	 * la canción "milf" y nunca se usaban en ningún otro lugar.
	 * El zoom de cámara ya es 100% softcodeable via el evento "Camera Zoom"
	 * del EventManager → assets/data/events/{canción}.json
	 * Ninguna canción necesita modificar código Haxe para tener zoom custom.
	 */

	/**
	 * ELIMINADO: isPixelStage(stage) / getUIPath / getUISuffix / getPixelScale
	 *
	 * Estas funciones chequeaban stage.startsWith('school'), lo que rompía
	 * cualquier stage pixel de mod que no se llamara "school*".
	 *
	 * CÓMO HACERLO AHORA — leer el campo del JSON del stage:
	 *
	 *   var sd = funkin.gameplay.objects.stages.Stage.getStageData(curStage);
	 *   var isPixel = (sd != null && sd.isPixelStage == true);
	 *
	 * En el JSON del stage añade:  "isPixelStage": true
	 * Eso es todo — ningún código Haxe necesita saber el nombre del stage.
	 */
}
