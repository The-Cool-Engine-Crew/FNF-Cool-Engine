package funkin.gameplay.notes;

import extensions.FlxAtlasFramesExt;
import lime.utils.Assets;
import funkin.gameplay.PlayState;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import openfl.display.BitmapData;
import haxe.Json;
#if sys
import sys.FileSystem;
import sys.io.File;
import funkin.data.SaveData;
#end

using StringTools;

// ==================== TYPEDEFS ====================

/**
 * Definición de textura de skin.
 *
 * Para type "sparrow": usa path.xml (Sparrow Atlas).
 * Para type "packer":  usa path.txt (TexturePacker).
 * Para type "image":   usa path.png dividido en frames de frameWidth×frameHeight píxeles.
 *                      El número de filas/columnas se calcula automáticamente.
 */
typedef NoteSkinTexture =
{
	var path:String;
	/**
	 * Tipo de carga de textura:
	 *   "sparrow"      — Sparrow Atlas (.xml)                  [default]
	 *   "packer"       — TexturePacker (.txt)
	 *   "image"        — PNG dividido en frames (frameWidth×frameHeight)
	 *   "funkinsprite" — Adobe Animate Texture Atlas (FunkinSprite / flxanimate)
	 *                    path apunta a la CARPETA que contiene Animation.json
	 */
	var ?type:String;
	var ?frameWidth:Int;  // solo para type "image"
	var ?frameHeight:Int; // solo para type "image"
	var ?scale:Float;         // escala del sprite (default: 1.0)
	var ?antialiasing:Bool;   // default: true (false para pixel)
}

/**
 * Definición de una animación individual.
 *
 * Formatos aceptados en el JSON:
 *   String shorthand:   "purple0"
 *   Objeto prefix:      {"prefix": "purple0"}
 *   Objeto prefix+fps:  {"prefix": "purple0", "framerate": 12}
 *   Objeto indices:     {"indices": [4]}
 *   Objeto multi-frame: {"indices": [12, 16], "framerate": 24}
 *   Objeto con loop:    {"indices": [0, 1, 2], "framerate": 12, "loop": true}
 */
typedef NoteAnimDef =
{
	var ?prefix:String;
	var ?indices:Array<Int>;
	var ?framerate:Int;
	var ?loop:Bool;
	/**
	 * Offset [x, y] aplicado al strum cuando esta animación está activa.
	 * Solo relevante para animaciones de strum (pressed / confirm).
	 * Opcional — si está ausente, se usan los defaults del engine.
	 *
	 * Ejemplo en skin.json:
	 *   "strumLeftConfirm": { "prefix": "left confirm", "offset": [-13, -13] }
	 *   "strumLeftPress":   { "prefix": "left press",   "offset": [0, -5] }
	 */
	var ?offset:Array<Float>;
}

/**
 * Todas las animaciones de una skin de notas.
 *
 * El campo `animations` del JSON es COMPLETAMENTE LIBRE — puedes poner
 * cualquier clave que quieras. El sistema las resuelve en este orden:
 *
 *  ┌─────────────────────────┬──────────────────────────────────────────────────────────┐
 *  │ Slot interno            │ Cadena de búsqueda (de mayor a menor prioridad)          │
 *  ├─────────────────────────┼──────────────────────────────────────────────────────────┤
 *  │ nota scroll izq         │ "left"    → "note"  → "allNotes"                        │
 *  │ nota scroll abajo       │ "down"    → "note"  → "allNotes"                        │
 *  │ nota scroll arriba      │ "up"      → "note"  → "allNotes"                        │
 *  │ nota scroll der         │ "right"   → "note"  → "allNotes"                        │
 *  │ hold piece (dir N)      │ "{dir}Hold"  → "hold"    → "allHold"                    │
 *  │ hold end   (dir N)      │ "{dir}HoldEnd"→"holdEnd" → "allHoldEnd"                 │
 *  │ strum static (dir N)    │ "strum{Dir}" → "strum"   → "allStrum"                   │
 *  │ strum press  (dir N)    │ "strum{Dir}Press"  → "strumPress"  → "allStrumPress"    │
 *  │ strum confirm(dir N)    │ "strum{Dir}Confirm"→ "strumConfirm"→ "allStrumConfirm"  │
 *  └─────────────────────────┴──────────────────────────────────────────────────────────┘
 *
 * Ejemplos de JSONs válidos:
 *
 *   // ① Animación única para todas las notas y strums:
 *   "animations": {
 *     "note":          "myNoteAnim",
 *     "hold":          "myHoldPiece",
 *     "holdEnd":       "myHoldEnd",
 *     "strum":         "myStrumStatic",
 *     "strumPress":    "myStrumPress",
 *     "strumConfirm":  "myStrumConfirm"
 *   }
 *
 *   // ② Por dirección (estilo clásico, sigue funcionando):
 *   "animations": {
 *     "left": "purple0", "down": "blue0", "up": "green0", "right": "red0",
 *     "leftHold": "purple hold piece", ...
 *   }
 *
 *   // ③ Mix — genérico + override para una dirección concreta:
 *   "animations": {
 *     "note":  "genericNote",
 *     "left":  "specialLeftNote",
 *     "hold":  "genericHold"
 *   }
 *
 *   // ④ Campos con nombre completamente libre (se acceden con resolveAnimDef):
 *   "animations": {
 *     "myCustomAnim": { "prefix": "whatever", "framerate": 12 }
 *   }
 *
 * NoteSkinSystem.resolveAnimDef(anims, keys) resuelve cualquier cadena
 * de claves sobre el objeto libre — úsalo para acceder a animaciones extra.
 */
typedef NoteSkinAnims =
{
	// ── Por dirección (nombres clásicos — siguen funcionando) ────────
	var ?left:Dynamic;
	var ?down:Dynamic;
	var ?up:Dynamic;
	var ?right:Dynamic;
	var ?leftHold:Dynamic;
	var ?downHold:Dynamic;
	var ?upHold:Dynamic;
	var ?rightHold:Dynamic;
	var ?leftHoldEnd:Dynamic;
	var ?downHoldEnd:Dynamic;
	var ?upHoldEnd:Dynamic;
	var ?rightHoldEnd:Dynamic;
	var ?strumLeft:Dynamic;
	var ?strumDown:Dynamic;
	var ?strumUp:Dynamic;
	var ?strumRight:Dynamic;
	var ?strumLeftPress:Dynamic;
	var ?strumDownPress:Dynamic;
	var ?strumUpPress:Dynamic;
	var ?strumRightPress:Dynamic;
	var ?strumLeftConfirm:Dynamic;
	var ?strumDownConfirm:Dynamic;
	var ?strumUpConfirm:Dynamic;
	var ?strumRightConfirm:Dynamic;
	// ── Genéricos cortos (nuevos) — se aplican a TODAS las direcciones ─
	/** Una sola animación para todas las notas scroll. */
	var ?note:Dynamic;
	/** Una sola animación para todos los hold pieces. */
	var ?hold:Dynamic;
	/** Una sola animación para todos los hold ends/tails. */
	var ?holdEnd:Dynamic;
	/** Una sola animación static para todos los strums. */
	var ?strum:Dynamic;
	/** Una sola animación press para todos los strums. */
	var ?strumPress:Dynamic;
	/** Una sola animación confirm para todos los strums. */
	var ?strumConfirm:Dynamic;
	// ── Alias "all*" (compatibilidad con el cambio anterior) ─────────
	var ?allNotes:Dynamic;
	var ?allHold:Dynamic;
	var ?allHoldEnd:Dynamic;
	var ?allStrum:Dynamic;
	var ?allStrumPress:Dynamic;
	var ?allStrumConfirm:Dynamic;
}

// Alias de compatibilidad — código que usaba NoteAnimations sigue compilando
typedef NoteAnimations = NoteSkinAnims;

/**
 * Datos completos de una skin de notas.
 *
 * La skin pixel y la skin normal son ENTIDADES COMPLETAMENTE INDEPENDIENTES.
 * No hay ninguna lógica hardcodeada de "school → pixel". En su lugar:
 *   - Crea una skin con isPixel:true y sus texturas/animaciones propias
 *   - Registra qué stage la usa con NoteSkinSystem.registerStageSkin(stage, skinName)
 *   - O llama NoteSkinSystem.setTemporarySkin(skinName) desde tu PlayState/Stage
 *
 * Campos clave:
 *   texture:      textura de notas (cabeza) y strums
 *   holdTexture:  textura de sustain pieces + tails (null → usa texture)
 *   isPixel:      activa modo pixel (antialiasing false por defecto)
 *   confirmOffset: aplica offset -13,-13 al strum confirm (default: true)
 *   sustainOffset: offset X extra para notas sustain (default: 0; pixel usa 30)
 *   holdStretch:  multiplicador de scale.y en hold chain (default: 1.0; pixel usa 1.19)
 *   animations:   todas las anims de notas + strums, usando NoteAnimDef
 */
typedef NoteSkinData =
{
	var name:String;
	var ?author:String;
	var ?description:String;
	var ?folder:String;
	// ── Texturas ────────────────────────────────────────────────────────
	/**
	 * texture      — textura principal (notas normales + strums).
	 *               Usada para notas normales cuando notesTexture es null,
	 *               y para strums cuando strumsTexture es null.
	 * strumsTexture  — textura SOLO para los strums (opcional).
	 *               Si es null, se usa texture.
	 * notesTexture   — textura SOLO para las notas que bajan (cabezas, scroll) (opcional).
	 *               Si es null, se usa texture.
	 * holdTexture    — textura para sustain pieces + tails (opcional).
	 *               Si es null, se usa texture (o notesTexture si se define).
	 *
	 * Soporta type:"funkinsprite" en cualquiera de ellas para usar Adobe Animate Atlas.
	 */
	var texture:NoteSkinTexture;
	var ?strumsTexture:NoteSkinTexture;  // solo strums  (null → usa texture)
	var ?notesTexture:NoteSkinTexture;   // solo notas scroll (null → usa texture)
	var ?holdTexture:NoteSkinTexture;    // sustain pieces + tails (null → usa texture)
	// ── Flags y ajustes ───────────────────────────────────────────────
	var ?isPixel:Bool;
	var ?confirmOffset:Bool; // default: true — aplica offset -13,-13 a todos los confirms si no tienen offset propio
	var ?offsetDefault:Bool; // alias legacy de confirmOffset
	var ?sustainOffset:Float; // default: 0.0
	var ?holdStretch:Float; // default: 1.0
	// ── Animaciones ───────────────────────────────────────────────────
	var animations:NoteSkinAnims;
	// ── Script (opcional) ─────────────────────────────────────────────
	/** Nombre del archivo Lua/HScript en la carpeta de la skin. Si es null, no se ejecuta. */
	var ?script:String;
	// ── Colorización automática (shader RGB) ──────────────────────────
	/**
	 * Si es true, aplica NoteColorSwapShader a cada nota usando los presets de color
	 * estándar de FNF (Left=púrpura, Down=cian, Up=verde, Right=rojo).
	 * Útil para sprites en escala de grises / neutros como NOTE_assets.png.
	 */
	var ?colorAuto:Bool;

	var ?noteGlow:Bool;
	
	/** Intensidad del shader RGB (0.0–1.0). Default: 1.0. */
	var ?colorMult:Float;
	/**
	 * Paleta de colores custom por dirección.
	 * Array de 4 entradas (Left, Down, Up, Right), cada una con campos r/g/b
	 * que son vectores [x,y,z] (columnas de la matriz de transformación de color).
	 * Si es null, se usan los presets de NoteColorSwapShader.PRESETS.
	 *
	 * Ejemplo en skin.json:
	 *   "colorDirections": [
	 *     { "r":[0.76,0.11,0.67], "g":[0,0,0], "b":[0.09,0.03,0.94] },
	 *     { "r":[0,1,1],          "g":[0,0,0], "b":[0,1,0]           },
	 *     { "r":[0.07,0.98,0.02], "g":[0,0,0], "b":[0,0.96,0]        },
	 *     { "r":[0.98,0.22,0.25], "g":[0,0,0], "b":[0.96,0.09,0.12]  }
	 *   ]
	 */
	var ?colorDirections:Array<{ r:Array<Float>, g:Array<Float>, b:Array<Float> }>;
	/**
	 * Desplazamientos HSV por dirección (Left, Down, Up, Right).
	 * Cada entrada: { h: rotación de tono 0–1, s: desplazamiento saturación, b: factor brillo }.
	 * Cuando colorAuto es true y colorHSV está definido, el NoteColorSwapShader aplica
	 * el preset correspondiente a la dirección de la nota en lugar del preset neutro.
	 */
	var ?colorHSV:Array<{ h:Float, s:Float, b:Float }>;
	/**
	 * Sistema de animaciones al estilo personaje — PRIORIDAD sobre el campo `animations`.
	 * Permite definir animaciones con nombre, prefix, offsets, flipX y framerate custom,
	 * igual que los personajes. Ver SkinAnimEntry para el formato completo.
	 */
	var ?animList:Array<SkinAnimEntry>;
}

// ── Splash (sistema independiente, no cambia) ─────────────────────────────────

/**
 * Definición de animación al estilo personaje (Character.hx AnimData).
 *
 * Permite definir animaciones con nombre, prefix, offsets, flipX y framerate
 * custom — igual que los personajes del juego.
 *
 * ─── Uso en skin.json (notas / strums) ──────────────────────────────────────
 *   "animList": [
 *     { "name": "purpleScroll", "prefix": "purple0",         "fps": 24, "offsets": [0, 0] },
 *     { "name": "blueScroll",   "prefix": "blue0",           "fps": 24 },
 *     { "name": "purplehold",   "prefix": "purple hold piece","fps": 24 },
 *     { "name": "purpleholdend","prefix": "purple hold end",  "fps": 24 },
 *     // Strums — noteID filtra por dirección (0=left, 1=down, 2=up, 3=right)
 *     { "name": "static",  "prefix": "arrowLEFT",    "noteID": 0 },
 *     { "name": "pressed", "prefix": "left press",   "noteID": 0, "looped": false },
 *     { "name": "confirm", "prefix": "left confirm", "noteID": 0, "offsets": [-13, -13] }
 *   ]
 *
 * ─── Uso en splash.json (splash normal) ─────────────────────────────────────
 *   "animList": [
 *     { "name": "left_0",  "prefix": "noteSplash left 1",  "fps": 24, "offsets": [0, 0] },
 *     { "name": "left_1",  "prefix": "noteSplash left 2",  "fps": 24 },
 *     { "name": "down_0",  "prefix": "noteSplash down 1",  "fps": 24 },
 *     { "name": "all_0",   "prefix": "noteSplash generic", "fps": 24 }   // fallback shared
 *   ]
 *   // Una sola splash para todas las dirs:
 *   "animList": [
 *     { "name": "all_0", "prefix": "noteSplash", "fps": 24 }
 *   ]
 *
 * ─── Uso en holdCover (dentro de splash.json) ────────────────────────────────
 *   "holdCover": {
 *     "animList": [
 *       { "name": "holdCoverStartPurple", "prefix": "holdCoverStart Purple", "fps": 24 },
 *       { "name": "holdCoverPurple",      "prefix": "holdCover Purple",      "fps": 48, "looped": true },
 *       { "name": "holdCoverEndPurple",   "prefix": "holdCoverEnd Purple",   "fps": 24 }
 *     ]
 *   }
 *   // Un solo hold cover sin distinción de color (perColorTextures: false):
 *   "holdCover": {
 *     "perColorTextures": false,
 *     "animList": [
 *       { "name": "holdCoverStart", "prefix": "holdCoverStart", "fps": 24 },
 *       { "name": "holdCover",      "prefix": "holdCover",      "fps": 48, "looped": true },
 *       { "name": "holdCoverEnd",   "prefix": "holdCoverEnd",   "fps": 24 }
 *     ]
 *   }
 */
typedef SkinAnimEntry =
{
	/** Nombre INTERNO de la animación en el sprite (e.g. "purpleScroll", "static", "left_0"). */
	var name:String;
	/** Prefijo en el atlas sparrow / nombre del frame en el atlas. */
	var prefix:String;
	/** FPS. Default: 24. También acepta "framerate" (compatibilidad con AnimData). */
	var ?fps:Int;
	/** Alias de fps (compatible con el formato AnimData de personajes). */
	var ?framerate:Float;
	/** Si la animación hace loop. Default: false. También acepta "looped". */
	var ?loop:Bool;
	/** Alias de loop (compatible con el formato AnimData de personajes). */
	var ?looped:Bool;
	/** Offset [x, y] aplicado al reproducir esta animación. */
	var ?offsets:Array<Float>;
	/** Voltear horizontalmente. Default: false. */
	var ?flipX:Bool;
	/** Voltear verticalmente. Default: false. */
	var ?flipY:Bool;
	/** Índices específicos de frames (alternativo a prefix). */
	var ?indices:Array<Int>;
	/**
	 * Solo para strums: noteID de la dirección (0=left,1=down,2=up,3=right).
	 * null / ausente → aplica a TODAS las direcciones.
	 * Se usa para filtrar entradas al cargar strums en StrumNote.hx.
	 */
	var ?noteID:Int;
}

typedef NoteSplashData =
{
	var name:String;
	var author:String;
	var ?description:String;
	var ?folder:String;
	var assets:NoteSplashAssets;
	/** Sistema de animaciones legacy (prefijos por dirección). */
	var animations:SplashAnimations;
	/**
	 * Sistema de animaciones al estilo personaje — PRIORIDAD sobre `animations`.
	 * Nombres de variante: "{dir}_{N}" (ej. "left_0", "right_1") o "all_{N}" (fallback).
	 * Una sola splash: usar "all_0" como nombre.
	 */
	var ?animList:Array<SkinAnimEntry>;
	/** Configuración de los hold covers. Null = usar defaults hardcodeados. */
	var ?holdCover:NoteHoldCoverData;
	/** Nombre del archivo Lua/HScript en la carpeta del splash. Si es null, no se ejecuta. */
	var ?script:String;
	/** Si true, aplica NoteColorSwapShader al splash usando los presets de color estándar. */
	var ?colorAuto:Bool;
	/** Intensidad del shader RGB (0.0–1.0). Default: 1.0. */
	var ?colorMult:Float;
	/** Paleta custom por dirección (igual que en NoteSkinData). */
	var ?colorDirections:Array<{ r:Array<Float>, g:Array<Float>, b:Array<Float> }>;

	/** Desplazamientos HSV por dirección (hereda del note skin si null). */
	var ?colorHSV:Array<{ h:Float, s:Float, b:Float }>;
}

typedef NoteSplashAssets =
{
	var path:String;
	var ?type:String;
	var ?scale:Float;
	var ?antialiasing:Bool;
	var ?offset:Array<Float>;
}

/**
 * Animaciones de un splash skin.
 *
 * Cada campo directional es un Array de prefijos (se elige uno al azar).
 * Todos son opcionales: si una dirección es null, se usa el campo "all".
 *
 * Ejemplos:
 *   Compartida: { "all": ["note impact 1", "note impact 2"] }
 *   Mixta:      { "all": ["genericImpact"], "left": ["specialLeft1", "specialLeft2"] }
 */
typedef SplashAnimations =
{
	var ?left:Array<String>;
	var ?down:Array<String>;
	var ?up:Array<String>;
	var ?right:Array<String>;
	/** Fallback: se usa cuando la dirección específica no está definida. */
	var ?all:Array<String>;
	var ?framerate:Int;
	var ?randomFramerateRange:Int;
}

/**
 * Datos de configuración para los hold covers (animaciones de splash largo).
 *
 * Viven dentro del splash.json en el campo "holdCover".
 * Todos los campos son opcionales — los valores por defecto reproducen
 * el comportamiento original hardcodeado, manteniendo compatibilidad total.
 *
 * Ejemplo en splash.json:
 * {
 *   "holdCover": {
 *     "texturePrefix": "holdCover",
 *     "perColorTextures": true,
 *     "textureType": "sparrow",
 *     "scale": 1.0,
 *     "antialiasing": true,
 *     "framerate": 24,
 *     "loopFramerate": 48,
 *     "offset": [0, 0],
 *     "startPrefix": "holdCoverStart",
 *     "loopPrefix":  "holdCover",
 *     "endPrefix":   "holdCoverEnd"
 *   }
 * }
 *
 * Con perColorTextures:true (default), se carga {texturePrefix}{Color}.png
 * por cada dirección (e.g. holdCoverPurple.png, holdCoverBlue.png…).
 * Con perColorTextures:false, se carga {texturePrefix}.png — atlas compartido.
 *
 * Los prefijos de animación siempre reciben el nombre del color como sufijo:
 *   startPrefix="holdCoverStart" → "holdCoverStartPurple", "holdCoverStartBlue"…
 */
typedef NoteHoldCoverData =
{
	/** true (default): una textura por color; false: atlas único compartido. */
	var ?perColorTextures:Bool;

	/** Prefijo del archivo de textura. Default: "holdCover". */
	var ?texturePrefix:String;

	/** Tipo de atlas. "sparrow" | "packer". Default: "sparrow". */
	var ?textureType:String;

	/** Escala del sprite. Default: 1.0. */
	var ?scale:Float;

	/** Antialiasing. Default: true. */
	var ?antialiasing:Bool;

	/** FPS de las animaciones de start y end. Default: 24. */
	var ?framerate:Int;

	/** FPS de la animación de loop continuo. Default: 48. */
	var ?loopFramerate:Int;

	/**
	 * Offset [x, y] en píxeles aplicado al sprite.
	 * Null = auto (width*0.3, height*0.3), igual que el comportamiento original.
	 */
	var ?offset:Array<Float>;

	/** Prefijo de la animación de inicio. Default: "holdCoverStart". */
	var ?startPrefix:String;

	/** Prefijo de la animación de loop. Default: "holdCover". */
	var ?loopPrefix:String;

	/** Prefijo de la animación de fin. Default: "holdCoverEnd". */
	var ?endPrefix:String;

	/**
	 * Sistema de animaciones al estilo personaje — PRIORIDAD sobre startPrefix/loopPrefix/endPrefix.
	 *
	 * Los `name` de cada entrada deben coincidir con los nombres calculados por NoteHoldCover:
	 *   e.g. "holdCoverStartPurple", "holdCoverPurple", "holdCoverEndPurple"
	 * Con perColorTextures:false el sufijo de color está vacío:
	 *   e.g. "holdCoverStart", "holdCover", "holdCoverEnd"
	 *
	 * Permite offsets, flipX y flipY por animación.
	 * Una sola hold cover (sin distinción de color): usar perColorTextures:false.
	 */
	var ?animList:Array<SkinAnimEntry>;
}

// ==================== SISTEMA PRINCIPAL ====================

class NoteSkinSystem
{
	public static var currentSkin:String = "Default";
	public static var currentSplash:String = "Default";

	/**
	 * Splash elegido permanentemente por el jugador.
	 * Solo se modifica con setSplash() (que guarda en disco).
	 * setTemporarySplash() y applySplashForStage() modifican currentSplash
	 * pero NO _globalSplash, por lo que restoreGlobalSplash() siempre
	 * vuelve al valor real del jugador — sin importar si el save.data
	 * fue corrompido por el bug anterior que llamaba setSplash() en cada cancion.
	 */
	private static var _globalSplash:String = "Default";

	/**
	 * Skin/splash por defecto del MOD ACTIVO (desde global.json del mod).
	 * Se usa como fallback en restoreGlobalSkin/Splash() cuando el jugador
	 * no tiene preferencia guardada. Sin esto, applySkinForStage() en PlayState
	 * ignoraba el global.json del mod y volvía siempre a "Default".
	 */
	private static var _modDefaultSkin:String = null;
	private static var _modDefaultSplash:String = null;

	public static var availableSkins:Map<String, NoteSkinData> = new Map();
	public static var availableSplashes:Map<String, NoteSplashData> = new Map();

	/**
	 * Mapa stage-name → skin-name.
	 * Defaults registrados en init(). Editable vía registerStageSkin().
	 */
	private static var stageSkinMap:Map<String, String> = new Map();

	private static var stageSplashMap:Map<String, String> = new Map();

	private static var initialized:Bool = false;

	/** Último mod activo durante el init — si cambia, forzamos re-init. */
	private static var _lastInitMod:Null<String> = null;

	/** Si la skin actual aplica el offset -13,-13 estándar en confirm. */
	public static var offsetDefault:Bool = true;

	// Paths calculados en init() según el mod activo
	private static var SKINS_PATH:String = "assets/notes/skins";
	private static var SPLASHES_PATH:String = "assets/notes/splashes";

	/** Previene re-entrada en init() cuando setTemporarySkin/setModDefault son llamados durante la inicialización. */
	private static var _initializing:Bool = false;

	// ==================== SKIN / SPLASH SCRIPT SYSTEM ====================

	/**
	 * Scripts Lua activos para la skin actual (se cargan en loadSkinScript).
	 * Se ejecutan cuando se usan los hooks onNoteHit, onNoteMiss, onSplashSpawn,
	 * onHoldSplash, onNoteSpawn, onStrumConfirm, onStrumPress, onStrumRelease.
	 */
	public static var skinScripts:Array<funkin.scripting.RuleScriptInstance> = [];
	public static var splashScripts:Array<funkin.scripting.RuleScriptInstance> = [];

	/**
	 * Carga y ejecuta el script de la skin activa si existe.
	 * Se llama automáticamente desde setSkin() / setTemporarySkin().
	 * Admite .lua y .hx (HScript) — se detecta por extensión.
	 */
	public static function loadSkinScript(?skinName:String):Void
	{
		#if (LUA_ALLOWED && linc_luajit && sys)
		// Limpiar scripts anteriores
		for (s in skinScripts) try s.destroy() catch(_) {}
		skinScripts = [];

		final name = skinName ?? currentSkin;
		final data = availableSkins.get(name);
		if (data == null) return;

		// Buscar script: prioridad a campo "script" del JSON, luego skin.lua / skin.hx
		final folder = data.folder ?? name;
		final candidates:Array<String> = [];
		if (data.script != null && data.script != '')
		{
			candidates.push('$SKINS_PATH/$folder/${data.script}');
			// Buscar también en mod
			final modRoot = mods.ModManager.modRoot();
			if (modRoot != null) candidates.push('$modRoot/notes/skins/$folder/${data.script}');
		}
		else
		{
			for (ext in ['lua', 'hx'])
			{
				candidates.push('$SKINS_PATH/$folder/skin.$ext');
				final modRoot = mods.ModManager.modRoot();
				if (modRoot != null) candidates.push('$modRoot/notes/skins/$folder/skin.$ext');
			}
		}

		for (path in candidates)
		{
			if (FileSystem.exists(path))
			{
				trace('[NoteSkinSystem] Loading skin script: $path');
				final script = new funkin.scripting.RuleScriptInstance('noteSkin_$name', path);
				script.loadFile(path);
				// Expose skin context to the script
				script.set('skinName',         name);
				script.set('NoteSkinSystem',    funkin.gameplay.notes.NoteSkinSystem);
				script.set('NoteColorSwapShader',     funkin.shaders.NoteColorSwapShader);
				script.set('applyRGBShader',    funkin.gameplay.notes.NoteSkinSystem.applyRGBShader);
				script.set('applyRGBColor',     funkin.gameplay.notes.NoteSkinSystem.applyRGBColor);
				script.set('setRGBIntensity',   funkin.gameplay.notes.NoteSkinSystem.setRGBIntensity);
				script.set('removeRGBShader',      funkin.gameplay.notes.NoteSkinSystem.removeRGBShader);
				script.set('tweenRGBToDirection',  funkin.gameplay.notes.NoteSkinSystem.tweenRGBToDirection);
				script.set('tweenRGBToColor',      funkin.gameplay.notes.NoteSkinSystem.tweenRGBToColor);
				script.set('tweenRGBIntensity',    funkin.gameplay.notes.NoteSkinSystem.tweenRGBIntensity);
				script.call('onCreate', []);
				skinScripts.push(script);
				break; // one script per skin
			}
		}
		#end
	}

	/**
	 * Carga y ejecuta el script del splash activo si existe.
	 * Se llama automáticamente desde setSplash() / setTemporarySplash().
	 */
	public static function loadSplashScript(?splashName:String):Void
	{
		#if (LUA_ALLOWED && linc_luajit && sys)
		for (s in splashScripts) try s.destroy() catch(_) {}
		splashScripts = [];

		final name = splashName ?? currentSplash;
		final data = availableSplashes.get(name);
		if (data == null) return;

		final folder = data.folder ?? name;
		final candidates:Array<String> = [];
		if (data.script != null && data.script != '')
		{
			candidates.push('$SPLASHES_PATH/$folder/${data.script}');
			final modRoot = mods.ModManager.modRoot();
			if (modRoot != null) candidates.push('$modRoot/notes/splashes/$folder/${data.script}');
		}
		else
		{
			for (ext in ['lua', 'hx'])
			{
				candidates.push('$SPLASHES_PATH/$folder/splash.$ext');
				final modRoot = mods.ModManager.modRoot();
				if (modRoot != null) candidates.push('$modRoot/notes/splashes/$folder/splash.$ext');
			}
		}

		for (path in candidates)
		{
			if (FileSystem.exists(path))
			{
				trace('[NoteSkinSystem] Loading splash script: $path');
				final script = new funkin.scripting.RuleScriptInstance('noteSplash_$name', path);
				script.loadFile(path);
				// Expose splash context to the script
				script.set('splashName',        name);
				script.set('NoteSkinSystem',     funkin.gameplay.notes.NoteSkinSystem);
				script.set('NoteColorSwapShader',      funkin.shaders.NoteColorSwapShader);
				script.set('applyRGBShader',     funkin.gameplay.notes.NoteSkinSystem.applyRGBShader);
				script.set('applyRGBColor',      funkin.gameplay.notes.NoteSkinSystem.applyRGBColor);
				script.set('setRGBIntensity',    funkin.gameplay.notes.NoteSkinSystem.setRGBIntensity);
				script.set('removeRGBShader',      funkin.gameplay.notes.NoteSkinSystem.removeRGBShader);
				script.set('tweenRGBToDirection',  funkin.gameplay.notes.NoteSkinSystem.tweenRGBToDirection);
				script.set('tweenRGBToColor',      funkin.gameplay.notes.NoteSkinSystem.tweenRGBToColor);
				script.set('tweenRGBIntensity',    funkin.gameplay.notes.NoteSkinSystem.tweenRGBIntensity);
				script.call('onCreate', []);
				splashScripts.push(script);
				break;
			}
		}
		#end
	}

	/** Llama un hook en todos los scripts de skin activos. */
	public static inline function callSkinHook(fn:String, ?args:Array<Dynamic>):Void
	{
		#if (LUA_ALLOWED && linc_luajit)
		for (s in skinScripts) s.call(fn, args ?? []);
		#end
	}

	/** Llama un hook en todos los scripts de splash activos. */
	public static inline function callSplashHook(fn:String, ?args:Array<Dynamic>):Void
	{
		#if (LUA_ALLOWED && linc_luajit)
		for (s in splashScripts) s.call(fn, args ?? []);
		#end
	}

	/** Limpia todos los scripts de skin y splash (llamar al destruir PlayState). */
	public static function destroyScripts():Void
	{
		#if (LUA_ALLOWED && linc_luajit)
		for (s in skinScripts)  try s.destroy() catch(_) {}
		for (s in splashScripts) try s.destroy() catch(_) {}
		skinScripts  = [];
		splashScripts = [];
		#end
	}

	// ==================== COLOR / SHADER HELPERS ====================
	// Estos métodos permiten que los scripts (.lua / .hx) de skins y splashes
	// apliquen o quiten el shader RGB en runtime sobre cualquier sprite.

	/**
	 * Aplica NoteColorSwapShader a un sprite con los presets estándar o un preset custom.
	 * Úsalo desde el script de la skin:
	 *   applyRGBShader(note, noteData)           -- preset estándar
	 *   applyRGBShader(note, noteData, 0.5)      -- intensidad reducida
	 *   applyRGBShader(note, noteData, 1.0, preset) -- paleta completamente custom
	 */
	public static function applyRGBShader(sprite:flixel.FlxSprite, direction:Int,
		mult:Float = 1.0,
		?customPreset:{ r:Array<Float>, g:Array<Float>, b:Array<Float> }):Void
	{
		if (sprite == null) return;
		sprite.shader = new funkin.shaders.NoteColorSwapShader(direction % 4, mult, customPreset);
	}

	/**
	 * Aplica NoteColorSwapShader a partir de un color hex (convierte automáticamente al preset).
	 * Úsalo desde el script de la skin:
	 *   applyRGBColor(note, 0xFF00FF00)       -- verde puro
	 *   applyRGBColor(note, 0xC24B99)         -- púrpura FNF
	 */
	public static function applyRGBColor(sprite:flixel.FlxSprite,
		color:flixel.util.FlxColor, mult:Float = 1.0):Void
	{
		if (sprite == null) return;
		sprite.shader = funkin.shaders.NoteColorSwapShader.fromColor(color, mult);
	}

	/**
	 * Cambia la intensidad del NoteColorSwapShader ya aplicado en un sprite (0.0–1.0).
	 * No hace nada si el sprite no tiene un NoteColorSwapShader.
	 */
	public static function setRGBIntensity(sprite:flixel.FlxSprite, mult:Float):Void
	{
		if (sprite == null) return;
		final s = Std.downcast(sprite.shader, funkin.shaders.NoteColorSwapShader);
		if (s != null) s.intensity = mult;
	}

	/**
	 * Elimina el shader RGB de un sprite (restaura el shader por defecto / null).
	 */
	public static function removeRGBShader(sprite:flixel.FlxSprite):Void
	{
		if (sprite == null) return;
		if (Std.isOfType(sprite.shader, funkin.shaders.NoteColorSwapShader))
			sprite.shader = null;
	}

	/**
	 * Tween del color del NoteColorSwapShader de un sprite hacia un preset de dirección.
	 * Si el sprite no tiene NoteColorSwapShader, se le aplica uno primero.
	 *
	 * @param sprite     Sprite objetivo (nota, splash, hold cover...).
	 * @param direction  Dirección destino (0=izq, 1=abajo, 2=arriba, 3=der).
	 * @param duration   Duración en segundos. Default: 0.25.
	 * @param ease       Nombre del ease como String (e.g. "quadOut", "sineInOut").
	 *                   Acepta cualquier función de FlxEase. Default: "linear".
	 * @return           El FlxTween creado.
	 */
	public static function tweenRGBToDirection(sprite:flixel.FlxSprite, direction:Int,
		duration:Float = 0.25, ease:String = 'linear'):flixel.tweens.FlxTween
	{
		if (sprite == null) return null;
		var s = Std.downcast(sprite.shader, funkin.shaders.NoteColorSwapShader);
		if (s == null) { s = new funkin.shaders.NoteColorSwapShader(direction); sprite.shader = s; }
		return s.tweenToDirection(direction, duration, _ease(ease));
	}

	/**
	 * Tween del color del NoteColorSwapShader de un sprite hacia un color hex.
	 */
	public static function tweenRGBToColor(sprite:flixel.FlxSprite,
		color:flixel.util.FlxColor, duration:Float = 0.25, ease:String = 'linear'):flixel.tweens.FlxTween
	{
		if (sprite == null) return null;
		var s = Std.downcast(sprite.shader, funkin.shaders.NoteColorSwapShader);
		if (s == null) { s = new funkin.shaders.NoteColorSwapShader(0, 1.0, funkin.shaders.NoteColorSwapShader.fromColor(color, 1.0).getCurrentPreset()); sprite.shader = s; }
		return s.tweenToColor(color, duration, _ease(ease));
	}

	/**
	 * Tween de la intensidad del NoteColorSwapShader (efecto de pulso / flash).
	 * Muy útil en onBeatHit para hacer un flash de color en beat.
	 *
	 * Ejemplo de pulso en beat:
	 *   tweenRGBIntensity(note, 1.5, 0.6, 0.3, "quadOut")  // flash fuerte → normal
	 */
	public static function tweenRGBIntensity(sprite:flixel.FlxSprite,
		fromMult:Float, toMult:Float, duration:Float = 0.2, ease:String = 'linear'):flixel.tweens.FlxTween
	{
		if (sprite == null) return null;
		final s = Std.downcast(sprite.shader, funkin.shaders.NoteColorSwapShader);
		if (s == null) return null;
		return s.tweenIntensity(fromMult, toMult, duration, _ease(ease));
	}

	/** Convierte nombre de ease a función. */
	static function _ease(name:String):Float->Float
	{
		return switch (name ?? 'linear') {
			case 'quadIn':      flixel.tweens.FlxEase.quadIn;
			case 'quadOut':     flixel.tweens.FlxEase.quadOut;
			case 'quadInOut':   flixel.tweens.FlxEase.quadInOut;
			case 'cubeIn':      flixel.tweens.FlxEase.cubeIn;
			case 'cubeOut':     flixel.tweens.FlxEase.cubeOut;
			case 'cubeInOut':   flixel.tweens.FlxEase.cubeInOut;
			case 'sineIn':      flixel.tweens.FlxEase.sineIn;
			case 'sineOut':     flixel.tweens.FlxEase.sineOut;
			case 'sineInOut':   flixel.tweens.FlxEase.sineInOut;
			case 'bounceOut':   flixel.tweens.FlxEase.bounceOut;
			case 'elasticOut':  flixel.tweens.FlxEase.elasticOut;
			case 'expoIn':      flixel.tweens.FlxEase.expoIn;
			case 'expoOut':     flixel.tweens.FlxEase.expoOut;
			default:            flixel.tweens.FlxEase.linear;
		};
	}

	/**
	 * Fuerza una re-inicialización completa del sistema en el próximo acceso.
	 * Úsalo cuando el mod activo cambia para que se descubran las skins del nuevo mod.
	 * Más seguro que acceder a `initialized` directamente (es private).
	 */
	public static function forceReinit():Void
	{
		initialized = false;
	}

	// ==================== HOT-RELOAD (F5) ====================

	/**
	 * Recarga desde disco el skin.json de la skin activa y el splash.json
	 * del splash activo, sin reinicializar todo el sistema.
	 *
	 * Uso típico: pulsar F5 en PlayState para ver cambios al JSON al instante.
	 *
	 * Devuelve true si al menos un archivo fue releído con éxito.
	 * Solo funciona en builds de escritorio (#if sys).
	 */
	public static function reloadCurrentJsonsFromDisk():Bool
	{
		#if sys
		var reloaded = false;

		// ── Skin ────────────────────────────────────────────────────────────
		final skinData = availableSkins.get(currentSkin);
		if (skinData != null && skinData.folder != null)
		{
			final folder = skinData.folder;
			final candidates:Array<String> = [];
			final modRoot = mods.ModManager.modRoot();
			if (modRoot != null)
				candidates.push('$modRoot/notes/skins/$folder/skin.json');
			candidates.push('$SKINS_PATH/$folder/skin.json');

			for (configPath in candidates)
			{
				if (FileSystem.exists(configPath))
				{
					try
					{
						var newData:NoteSkinData = Json.parse(File.getContent(configPath));
						newData.folder = folder;
						// Quitar la entrada vieja (por si el nombre cambió) y registrar la nueva
						availableSkins.remove(currentSkin);
						availableSkins.set(newData.name, newData);
						currentSkin = newData.name;
						reloaded = true;
						trace('[NoteSkinSystem] 🔄 Hot-reloaded skin "$currentSkin" desde $configPath');
					}
					catch (e:Dynamic)
					{
						trace('[NoteSkinSystem] Error hot-reload skin $configPath: $e');
					}
					break; // usar solo el primer candidato encontrado
				}
			}
		}

		// ── Splash ──────────────────────────────────────────────────────────
		if (currentSplash != "Default" && currentSplash != null)
		{
			final splData = availableSplashes.get(currentSplash);
			if (splData != null && splData.folder != null)
			{
				final folder = splData.folder;
				final candidates:Array<String> = [];
				final modRoot = mods.ModManager.modRoot();
				if (modRoot != null)
					candidates.push('$modRoot/notes/splashes/$folder/splash.json');
				candidates.push('$SPLASHES_PATH/$folder/splash.json');

				for (configPath in candidates)
				{
					if (FileSystem.exists(configPath))
					{
						try
						{
							var newData:NoteSplashData = Json.parse(File.getContent(configPath));
							newData.folder = folder;
							availableSplashes.remove(currentSplash);
							availableSplashes.set(newData.name, newData);
							currentSplash = newData.name;
							reloaded = true;
							trace('[NoteSkinSystem] 🔄 Hot-reloaded splash "$currentSplash" desde $configPath');
						}
						catch (e:Dynamic)
						{
							trace('[NoteSkinSystem] Error hot-reload splash $configPath: $e');
						}
						break;
					}
				}
			}
		}

		return reloaded;
		#else
		return false;
		#end
	}

	// ==================== INIT ====================

	public static function init():Void
	{
		// Si el mod activo cambió desde el último init, forzar re-inicialización
		// para que se descubran las skins del nuevo mod.
		final currentMod:Null<String> = mods.ModManager.activeMod;
		if (initialized && currentMod == _lastInitMod)
			return;

		if (initialized)
		{
			// Reiniciar estado para el nuevo mod
			availableSkins = new Map();
			availableSplashes = new Map();
			stageSkinMap = new Map();
			stageSplashMap = new Map();
			_globalSplash = "Default";
			_modDefaultSkin = null;
			_modDefaultSplash = null;
			initialized = false;
		}

		trace("[NoteSkinSystem] Initializing...");

		_initializing = true;

		// Calcular paths en runtime según el mod activo
		// SIEMPRE apuntamos a assets/ como base (los skins de mod se descubren
		// adicionalmente en discoverSkins / discoverSplashes).
		SKINS_PATH = "assets/notes/skins";
		SPLASHES_PATH = "assets/notes/splashes";

		_lastInitMod = currentMod;

		// Skins built-in
		availableSkins.set("Default", getDefaultSkin());
		availableSkins.set("Pixel", getDefaultPixelSkin());

		// Defaults de stage → skin (editables con registerStageSkin)
		stageSkinMap.set("school", "Pixel");
		stageSkinMap.set("schoolEvil", "Pixel");

		// Defaults de stage → splash (editables con registerStageSplash)
		// Se aplican con applySplashForStage() — sin guardar en disco (temporal).
		stageSplashMap.set("school", "PixelSplash");
		stageSplashMap.set("schoolEvil", "PixelSplash");

		discoverSkins();
		discoverSplashes();
		loadSavedSkin();
		loadSavedSplash();

		_initializing = false;
		initialized = true;
		trace('[NoteSkinSystem] Ready — ${Lambda.count(availableSkins)} skins, ${Lambda.count(availableSplashes)} splashes');
	}

	// ==================== STAGE → SKIN MAPPING ====================

	/**
	 * Registra la skin a usar para un stage concreto.
	 * Llama esto desde tu Stage.hx o PlayState al cargar el stage.
	 *
	 *   NoteSkinSystem.registerStageSkin("schoolEvil", "DefaultPixel");
	 *   NoteSkinSystem.registerStageSkin("myCustomStage", "MyFancySkin");
	 */
	public static function registerStageSkin(stageName:String, skinName:String):Void
	{
		stageSkinMap.set(stageName, skinName);
		trace('[NoteSkinSystem] Stage "$stageName" → skin "$skinName"');
	}

	/**
	 * Devuelve el nombre de skin configurado para un stage, o null si no hay override.
	 */
	public static function getSkinNameForStage(stageName:String):String
	{
		return stageSkinMap.exists(stageName) ? stageSkinMap.get(stageName) : null;
	}

	/**
	 * Aplica temporalmente la skin asignada al stage.
	 * Si el stage no tiene skin propia, restaura la skin global del jugador.
	 *
	 * Úsalo en PlayState al cargar el stage:
	 *   NoteSkinSystem.applySkinForStage(PlayState.curStage);
	 */
	public static function applySkinForStage(stageName:String):Void
	{
		var skinForStage = getSkinNameForStage(stageName);
		if (skinForStage != null)
			setTemporarySkin(skinForStage);
		else
			restoreGlobalSkin();
	}

	/** Registra el splash a usar para un stage concreto (temporal, sin guardar). */
	public static function registerStageSplash(stageName:String, splashName:String):Void
	{
		stageSplashMap.set(stageName, splashName);
		trace('[NoteSkinSystem] Stage "$stageName" → splash "$splashName"');
	}

	/** Devuelve el nombre de splash configurado para un stage, o null si no hay override. */
	public static function getSplashNameForStage(stageName:String):String
	{
		return stageSplashMap.exists(stageName) ? stageSplashMap.get(stageName) : null;
	}

	/**
	 * Aplica temporalmente el splash asignado al stage.
	 * Si el stage no tiene splash propio, restaura el splash global del jugador.
	 * Llama esto justo despues de applySkinForStage() en PlayState.
	 */
	public static function applySplashForStage(stageName:String):Void
	{
		var splashForStage = getSplashNameForStage(stageName);
		if (splashForStage != null)
			setTemporarySplash(splashForStage);
		else
			restoreGlobalSplash();
	}

	// ==================== DESCUBRIMIENTO ====================

	private static function discoverSkins():Void
	{
		#if sys
		// Descubrir siempre desde assets/skins (base)
		_discoverSkinsInPath(SKINS_PATH);
		// Adicionalmente desde el mod activo (overrides y añadidos)
		final modRoot = mods.ModManager.modRoot();
		if (modRoot != null)
		{
			final modSkinsPath = '$modRoot/notes/skins';
			if (modSkinsPath != SKINS_PATH)
				_discoverSkinsInPath(modSkinsPath);
		}
		#else
		for (skinPath in Assets.list().filter(p -> p.contains("notes/skins/") && p.endsWith("skin.json")))
		{
			try
			{
				var data:NoteSkinData = Json.parse(Assets.getText(skinPath));
				var m = ~/skins\/([^\/]+)\//;
				if (m.match(skinPath))
					data.folder = m.matched(1);
				availableSkins.set(data.name, data);
			}
			catch (e:Dynamic)
			{
				trace('[NoteSkinSystem] Error loading $skinPath: $e');
			}
		}
		#end
	}

	#if sys
	private static function _discoverSkinsInPath(basePath:String):Void
	{
		if (!FileSystem.exists(basePath) || !FileSystem.isDirectory(basePath))
			return;
		for (skinFolder in FileSystem.readDirectory(basePath))
		{
			var skinPath = '$basePath/$skinFolder';
			if (!FileSystem.isDirectory(skinPath))
				continue;
			var configPath = '$skinPath/skin.json';
			if (FileSystem.exists(configPath))
			{
				try
				{
					var data:NoteSkinData = Json.parse(File.getContent(configPath));
					data.folder = skinFolder;
					availableSkins.set(data.name, data);
					trace('[NoteSkinSystem] Loaded skin "${data.name}" from $basePath/$skinFolder');
				}
				catch (e:Dynamic)
				{
					trace('[NoteSkinSystem] Error loading $configPath: $e');
				}
			}
			else
			{
				var auto = autoDetectSkin(skinPath, skinFolder);
				if (auto != null)
				{
					availableSkins.set(auto.name, auto);
					trace('[NoteSkinSystem] Auto-detected skin "${auto.name}"');
				}
			}
		}
	}
	#end

	private static function discoverSplashes():Void
	{
		availableSplashes.set("Default", getDefaultSplash());
		#if sys
		_discoverSplashesInPath(SPLASHES_PATH);
		// Adicionalmente desde el mod activo
		final modRoot = mods.ModManager.modRoot();
		if (modRoot != null)
		{
			final modSplashesPath = '$modRoot/notes/splashes';
			if (modSplashesPath != SPLASHES_PATH)
				_discoverSplashesInPath(modSplashesPath);
		}
		#else
		for (splashPath in Assets.list().filter(p -> p.contains("splashes/") && p.endsWith("splash.json")))
		{
			try
			{
				var data:NoteSplashData = Json.parse(Assets.getText(splashPath));
				var m = ~/splashes\/([^\/]+)\//;
				if (m.match(splashPath))
					data.folder = m.matched(1);
				availableSplashes.set(data.name, data);
			}
			catch (e:Dynamic)
			{
				trace('[NoteSkinSystem] Error loading $splashPath: $e');
			}
		}
		#end
	}

	#if sys
	private static function _discoverSplashesInPath(basePath:String):Void
	{
		if (!FileSystem.exists(basePath) || !FileSystem.isDirectory(basePath))
			return;
		for (splashFolder in FileSystem.readDirectory(basePath))
		{
			var splashPath = '$basePath/$splashFolder';
			if (!FileSystem.isDirectory(splashPath))
				continue;
			var configPath = '$splashPath/splash.json';
			if (FileSystem.exists(configPath))
			{
				try
				{
					var data:NoteSplashData = Json.parse(File.getContent(configPath));
					data.folder = splashFolder;
					availableSplashes.set(data.name, data);
				}
				catch (e:Dynamic)
				{
					trace('[NoteSkinSystem] Error loading $configPath: $e');
				}
			}
			else
			{
				var auto = autoDetectSplash(splashPath, splashFolder);
				if (auto != null)
					availableSplashes.set(auto.name, auto);
			}
		}
	}
	#end

	// ==================== AUTO-DETECCIÓN ====================
	#if sys
	private static function autoDetectSkin(skinPath:String, folderName:String):NoteSkinData
	{
		var files = FileSystem.readDirectory(skinPath);
		var mainPath = "";
		var mainType = "sparrow";
		var holdPath = "";

		for (file in files)
		{
			var lower = file.toLowerCase();
			if (!lower.endsWith(".png"))
				continue;
			var base = file.substr(0, file.length - 4);
			var hasXml = files.indexOf(base + ".xml") != -1;
			var hasTxt = files.indexOf(base + ".txt") != -1;
			var isHold = lower.contains("hold") || lower.contains("end");

			if (isHold && holdPath == "")
				holdPath = base;
			else if (!isHold && mainPath == "")
			{
				mainPath = base;
				mainType = hasXml ? "sparrow" : (hasTxt ? "packer" : "image");
			}
		}

		if (mainPath == "")
			return null;

		var skin:NoteSkinData = {
			name: folderName,
			author: "Unknown",
			folder: folderName,
			texture: {path: mainPath, type: mainType},
			animations: {}
		};
		if (holdPath != "")
			skin.holdTexture = {path: holdPath, type: "image"};

		return skin;
	}

	private static function autoDetectSplash(splashPath:String, folderName:String):NoteSplashData
	{
		var files = FileSystem.readDirectory(splashPath);
		for (file in files)
		{
			if (!file.toLowerCase().contains("splash") || !file.toLowerCase().endsWith(".png"))
				continue;
			var base = file.substr(0, file.length - 4);
			var hasXml = files.indexOf(base + ".xml") != -1;
			return {
				name: folderName,
				author: "Unknown",
				folder: folderName,
				assets: {path: base, type: hasXml ? "sparrow" : "image"},
				animations: {
					left: ["note impact 1 purple", "note impact 2 purple"],
					down: ["note impact 1 blue", "note impact 2 blue"],
					up: ["note impact 1 green", "note impact 2 green"],
					right: ["note impact 1 red", "note impact 2 red"],
					framerate: 24
				}
			};
		}
		return null;
	}
	#end

	// ==================== DEFAULTS ====================

	/**
	 * Skin normal por defecto — NOTE_assets.xml, animaciones sparrow estándar FNF.
	 */
	private static function getDefaultSkin():NoteSkinData
	{
		return {
			name: "Default",
			author: "ninjamuffin99",
			description: "Default Friday Night Funkin' notes",
			folder: "Default",
			texture: {
				path: "NOTE_assets",
				type: "sparrow",
				scale: 0.7,
				antialiasing: true
			},
			confirmOffset: true,
			animations: {
				left: "purple0",
				down: "blue0",
				up: "green0",
				right: "red0",
				leftHold: "purple hold piece",
				downHold: "blue hold piece",
				upHold: "green hold piece",
				rightHold: "red hold piece",
				leftHoldEnd: "pruple end hold",
				downHoldEnd: "blue hold end",
				upHoldEnd: "green hold end",
				rightHoldEnd: "red hold end",
				strumLeft: "arrowLEFT",
				strumDown: "arrowDOWN",
				strumUp: "arrowUP",
				strumRight: "arrowRIGHT",
				strumLeftPress: "left press",
				strumDownPress: "down press",
				strumUpPress: "up press",
				strumRightPress: "right press",
				strumLeftConfirm: "left confirm",
				strumDownConfirm: "down confirm",
				strumUpConfirm: "up confirm",
				strumRightConfirm: "right confirm"
			}
		};
	}

	/**
	 * Skin PIXEL por defecto — arrows-pixels.png + arrowEnds.png, animaciones por índice.
	 *
	 * Layout arrows-pixels.png (frameWidth=17, frameHeight=17):
	 *   fila 0 (frames  0-3):  strums static
	 *   fila 1 (frames  4-7):  notas scroll
	 *   fila 2 (frames  8-11): strums pressed
	 *   fila 3 (frames 12-15): confirm frame 1
	 *   fila 4 (frames 16-19): confirm frame 2
	 *
	 * Layout arrowEnds.png (frameWidth=7, frameHeight=6):
	 *   fila 0 (frames  0-3):  hold pieces
	 *   fila 1 (frames  4-7):  hold tails
	 */
	private static function getDefaultPixelSkin():NoteSkinData
	{
		return {
			name: "Pixel",
			author: "ninjamuffin99",
			description: "Default pixel/week 6 note skin",
			folder: "Default",
			isPixel: true,
			confirmOffset: false,
			sustainOffset: 30.0,
			holdStretch: 1.19,
			texture: {
				path: "arrows-pixels",
				type: "image",
				frameWidth: 17,
				frameHeight: 17,
				scale: 6.0,
				antialiasing: false
			},
			holdTexture: {
				path: "arrowEnds",
				type: "image",
				frameWidth: 7,
				frameHeight: 6,
				scale: 6.0,
				antialiasing: false
			},
			animations: {
				// Notas scroll — fila 1 (frames 4-7)
				left: {indices: [4]},
				down: {indices: [5]},
				up: {indices: [6]},
				right: {indices: [7]},
				// Hold pieces — fila 0 de arrowEnds (frames 0-3)
				leftHold: {indices: [0]},
				downHold: {indices: [1]},
				upHold: {indices: [2]},
				rightHold: {indices: [3]},
				// Hold tails — fila 1 de arrowEnds (frames 4-7)
				leftHoldEnd: {indices: [4]},
				downHoldEnd: {indices: [5]},
				upHoldEnd: {indices: [6]},
				rightHoldEnd: {indices: [7]},
				// Strums static — fila 0 (frames 0-3)
				strumLeft: {indices: [0]},
				strumDown: {indices: [1]},
				strumUp: {indices: [2]},
				strumRight: {indices: [3]},
				// Strums pressed — filas 1+2 (fps 12)
				strumLeftPress: {indices: [4, 8], framerate: 12},
				strumDownPress: {indices: [5, 9], framerate: 12},
				strumUpPress: {indices: [6, 10], framerate: 12},
				strumRightPress: {indices: [7, 11], framerate: 12},
				// Strums confirm — filas 3+4 (fps 24)
				strumLeftConfirm: {indices: [12, 16], framerate: 24},
				strumDownConfirm: {indices: [13, 17], framerate: 24},
				strumUpConfirm: {indices: [14, 18], framerate: 24},
				strumRightConfirm: {indices: [15, 19], framerate: 24}
			}
		};
	}

	private static function getDefaultSplash():NoteSplashData
	{
		return {
			name: "Default",
			author: "FNF Team",
			description: "Default note splash effects",
			folder: "Default",
			assets: {
				path: "noteSplashes",
				type: "sparrow",
				scale: 1.0,
				antialiasing: true,
				offset: [0, 0]
			},
			animations: {
				left: ["note impact 1 purple", "note impact 2 purple"],
				down: ["note impact 1 blue", "note impact 2 blue"],
				up: ["note impact 1 green", "note impact 2 green"],
				right: ["note impact 1 red", "note impact 2 red"],
				framerate: 24,
				randomFramerateRange: 3
			}
		};
	}

	// ==================== CARGA / GUARDADO ====================

	private static function loadSavedSkin():Void
	{
		if (SaveData.data.noteSkin != null && availableSkins.exists(SaveData.data.noteSkin))
		{
			currentSkin = SaveData.data.noteSkin;
		}
		else
		{
			currentSkin = "Default";
			if (SaveData.data.noteSkin != "Default")
			{
				SaveData.data.noteSkin = "Default";
				SaveData.flush(); // solo flush cuando realmente cambia algo
			}
		}
	}

	private static function loadSavedSplash():Void
	{
		// Determinar el splash global del jugador a partir del save.
		// SANITIZACIÓN: si el save tiene un splash que es específico de pixel
		// (e.g. "PixelSplash") almacenado por el bug antiguo que llamaba setSplash()
		// desde PlayState en cada cancion — lo reseteamos a "Default".
		// Un jugador que QUIERA PixelSplash global lo tiene que elegir manualmente
		// en el menú de opciones (que llama setSplash() explícitamente).
		// La heurística: si el save tiene "PixelSplash" pero no hay skin Pixel activa
		// global, revertir. Mas simple: los splash que contengan "pixel" en el nombre
		// (case-insensitive) no deben ser el splash global por defecto.
		var savedSplash:String = SaveData.data.noteSplash;
		var isValidGlobal:Bool = (savedSplash != null
			&& availableSplashes.exists(savedSplash)
			&& savedSplash.toLowerCase().indexOf('pixel') < 0); // no pixel-only splashes as global default

		if (isValidGlobal)
		{
			_globalSplash = savedSplash;
			currentSplash = savedSplash;
		}
		else
		{
			_globalSplash = "Default";
			currentSplash = "Default";
			// Reparar el save si estaba corrompido
			if (SaveData.data.noteSplash != "Default")
			{
				SaveData.data.noteSplash = "Default";
				SaveData.flush();
			}
		}
	}

	// ==================== SETTERS ====================

	public static function setSkin(skinName:String):Bool
	{
		if (!availableSkins.exists(skinName))
		{
			trace('Note skin "$skinName" not found!');
			return false;
		}
		currentSkin = skinName;
		SaveData.data.noteSkin = skinName;
		SaveData.flush();
		loadSkinScript(skinName);
		return true;
	}

	public static function setTemporarySkin(skinName:String):Void
	{
		if (!initialized && !_initializing)
			init();
		if (skinName == null || skinName == '' || skinName == 'default')
		{
			currentSkin = SaveData.data.noteSkin != null ? SaveData.data.noteSkin : 'Default';
			loadSkinScript(currentSkin);
			return;
		}
		if (availableSkins.exists(skinName))
		{
			currentSkin = skinName;
			loadSkinScript(currentSkin);
			return;
		}
		for (key in availableSkins.keys())
		{
			if (key.toLowerCase() == skinName.toLowerCase())
			{
				currentSkin = key;
				loadSkinScript(currentSkin);
				return;
			}
		}
		currentSkin = SaveData.data.noteSkin != null ? SaveData.data.noteSkin : 'Default';
		loadSkinScript(currentSkin);
		trace('[NoteSkinSystem] Skin "$skinName" no encontrada, usando global: $currentSkin');
	}

	/**
	 * Registra la skin del mod activo (llamado desde GlobalConfig).
	 * A diferencia de setTemporarySkin(), este valor se preserva en
	 * restoreGlobalSkin() cuando el jugador no tiene preferencia guardada.
	 */
	public static function setModDefaultSkin(skinName:String):Void
	{
		_modDefaultSkin = (skinName != null && skinName.toLowerCase() != 'default') ? skinName : null;
		setTemporarySkin(skinName);
	}

	public static function restoreGlobalSkin():Void
	{
		var saved = SaveData.data.noteSkin;
		// Si el jugador eligió una skin específica en Opciones, respetarla.
		if (saved != null && saved != 'Default' && availableSkins.exists(saved))
		{
			currentSkin = saved;
			return;
		}
		// Sin preferencia del jugador → usar la skin del mod (global.json) si existe.
		if (_modDefaultSkin != null && availableSkins.exists(_modDefaultSkin))
		{
			currentSkin = _modDefaultSkin;
			return;
		}
		currentSkin = 'Default';
	}

	public static function setSplash(splashName:String):Bool
	{
		if (!availableSplashes.exists(splashName))
		{
			trace('Splash "$splashName" not found!');
			return false;
		}
		// BUGFIX: actualizar _globalSplash ademas de currentSplash y save.data
		// para que restoreGlobalSplash() use siempre el valor correcto.
		_globalSplash = splashName;
		currentSplash = splashName;
		SaveData.data.noteSplash = splashName;
		SaveData.flush();
		loadSplashScript(splashName);
		return true;
	}

	/**
	 * Cambia el splash TEMPORALMENTE sin guardar en disco ni tocar _globalSplash.
	 * Usa esto desde PlayState / Stage para sobreescribir el splash por cancion
	 * sin contaminar la preferencia global del jugador.
	 * Llama restoreGlobalSplash() al salir del PlayState.
	 */
	public static function setTemporarySplash(splashName:String):Void
	{
		if (!initialized && !_initializing)
			init();
		if (splashName == null || splashName == '' || splashName == 'default')
		{
			// Splash vacío en meta = usar el global del jugador
			currentSplash = _globalSplash;
			loadSplashScript(currentSplash);
			return;
		}
		if (availableSplashes.exists(splashName))
		{
			currentSplash = splashName;
			loadSplashScript(currentSplash);
			return;
		}
		for (key in availableSplashes.keys())
		{
			if (key.toLowerCase() == splashName.toLowerCase())
			{
				currentSplash = key;
				loadSplashScript(currentSplash);
				return;
			}
		}
		// Fallback al global (sin tocar _globalSplash)
		currentSplash = _globalSplash;
		loadSplashScript(currentSplash);
		trace('[NoteSkinSystem] Splash "$splashName" not found, usando global: $currentSplash');
	}

	/**
	 * Registra el splash del mod activo (llamado desde GlobalConfig).
	 * A diferencia de setTemporarySplash(), este valor se preserva en
	 * restoreGlobalSplash() cuando el jugador no tiene preferencia guardada.
	 */
	public static function setModDefaultSplash(splashName:String):Void
	{
		_modDefaultSplash = (splashName != null && splashName.toLowerCase() != 'default') ? splashName : null;
		setTemporarySplash(splashName);
	}

	/**
	 * Restaura currentSplash al valor elegido por el jugador (_globalSplash),
	 * con fallback al splash del mod activo (global.json) si el jugador no eligió nada.
	 */
	public static function restoreGlobalSplash():Void
	{
		// Si el jugador eligió un splash válido y no es pixel-only, respetarlo.
		if (_globalSplash != null && _globalSplash != 'Default' && availableSplashes.exists(_globalSplash))
		{
			currentSplash = _globalSplash;
			return;
		}
		// Sin preferencia del jugador → usar el splash del mod (global.json) si existe.
		if (_modDefaultSplash != null && availableSplashes.exists(_modDefaultSplash))
		{
			currentSplash = _modDefaultSplash;
			return;
		}
		currentSplash = _globalSplash;
	}

	// ==================== GETTERS DE SKIN ====================

	/** Set to true by loadAtlas() when the requested asset didn't exist and the
	 *  Default skin texture was used as fallback. Checked by Note.loadSkin() to
	 *  avoid applying the custom skin's scale on top of the wrong (Default) texture
	 *  — which caused giant Default-looking notes when a custom skin had a missing
	 *  asset (e.g. scale:3.0 but texture file not found → 3x Default notes).
	 *  Reset to false at the start of every loadAtlas() call. */
	public static var lastLoadFellBack:Bool = false;

	/**
	 * Devuelve el NoteSkinData completo de la skin actual.
	 * Úsalo en Note.hx / StrumNote.hx — contiene textura, escala, anims, flags, todo.
	 */
	public static function getCurrentSkinData(?skinName:String):NoteSkinData
	{
		if (!initialized)
			init();
		var skin = skinName != null ? skinName : currentSkin;
		var data = availableSkins.get(skin);
		if (data == null)
			data = availableSkins.get("Default");
		return data;
	}

	/**
	 * Carga y devuelve el FlxAtlasFrames de una NoteSkinTexture.
	 * Usa folder de la skin como prefijo de assets.
	 */
	public static function loadSkinFrames(tex:NoteSkinTexture, ?folder:String):FlxAtlasFrames
	{
		return loadAtlas(tex, folder != null ? folder : "Default");
	}

	/**
	 * Devuelve la textura correcta para los STRUMS del skin dado.
	 * Prioridad: strumsTexture > texture
	 */
	public static function getStrumsTexture(?skinName:String):NoteSkinTexture
	{
		var d = getCurrentSkinData(skinName);
		if (d == null) return null;
		return d.strumsTexture != null ? d.strumsTexture : d.texture;
	}

	/**
	 * Construye un mapa animName → [offsetX, offsetY] a partir de los campos
	 * `offset` definidos en cada NoteAnimDef de strum.
	 *
	 * Lógica de prioridad (de mayor a menor):
	 *   1. El campo `offset` explícito en la def de la animación del JSON.
	 *   2. Si la animación es un confirm Y `confirmOffset:true` en la skin
	 *      (o no se define, que vale true por defecto para skins no-pixel),
	 *      se usa el fallback [-13, -13] — comportamiento original del engine.
	 *   3. Sin offset (sin entrada en el mapa).
	 *
	 * Parámetro `noteID`: índice de la flecha (0=left, 1=down, 2=up, 3=right).
	 * Solo se procesan las defs de la dirección correcta.
	 *
	 * El mapa resultante tiene como claves los nombres internos de animación
	 * usados por StrumNote: 'static', 'pressed', 'confirm'.
	 */
	public static function buildStrumOffsets(skinData:NoteSkinData, noteID:Int):Map<String, Array<Float>>
	{
		var map:Map<String, Array<Float>> = new Map();
		if (skinData == null) return map;

		var i = Std.int(Math.abs(noteID)) % 4;

		// ── animList tiene prioridad ─────────────────────────────────────────
		if (skinData.animList != null)
		{
			for (entry in skinData.animList)
			{
				if (entry == null || entry.name == null) continue;
				// Filtrar por dirección: noteID coincide o null = todas las dirs
				var entryDir:Null<Int> = entry.noteID;
				if (entryDir != null && entryDir >= 0 && entryDir != i) continue;
				// Solo añadir offset si es una animación de strum
				if (entry.name != "static" && entry.name != "pressed" && entry.name != "confirm") continue;
				if (entry.offsets != null && entry.offsets.length >= 2)
					map.set(entry.name, [entry.offsets[0], entry.offsets[1]]);
			}
			// Si no hay confirm explícito, aplicar confirmOffset global
			if (!map.exists("confirm"))
			{
				var useDefault = skinData.confirmOffset != null
					? skinData.confirmOffset
					: (skinData.offsetDefault != null ? skinData.offsetDefault : !(skinData.isPixel == true));
				if (useDefault) map.set("confirm", [-13.0, -13.0]);
			}
			return map;
		}

		// ── Sistema legacy ───────────────────────────────────────────────────
		if (skinData.animations == null) return map;

		var anims = skinData.animations;

		// Defs para este noteID — resueltas con la cadena de fallback libre
		var strumDirs   = ["strumLeft",        "strumDown",        "strumUp",        "strumRight"];
		var pressDirs   = ["strumLeftPress",   "strumDownPress",   "strumUpPress",   "strumRightPress"];
		var confirmDirs = ["strumLeftConfirm", "strumDownConfirm", "strumUpConfirm", "strumRightConfirm"];
		var staticDefs  = [for (d in strumDirs)   resolveAnimDef(anims, [d, "strum",         "allStrum"])];
		var pressDefs   = [for (d in pressDirs)   resolveAnimDef(anims, [d, "strumPress",    "allStrumPress"])];
		var confirmDefs = [for (d in confirmDirs) resolveAnimDef(anims, [d, "strumConfirm",  "allStrumConfirm"])];

		// Helper: extrae offset de una def dinámica (String o NoteAnimDef)
		inline function offsetOf(def:Dynamic):Array<Float>
		{
			if (def == null || Std.isOfType(def, String)) return null;
			var arr:Dynamic = def.offset;
			if (arr == null) return null;
			return [Std.parseFloat(Std.string(arr[0])), Std.parseFloat(Std.string(arr[1]))];
		}

		// static
		var so = offsetOf(staticDefs[i]);
		if (so != null)
			map.set('static', so);

		// pressed
		var po = offsetOf(pressDefs[i]);
		if (po != null)
			map.set('pressed', po);

		// confirm: si la def tiene offset propio, usarlo; si no, fallback a confirmOffset global
		var co = offsetOf(confirmDefs[i]);
		if (co != null)
		{
			map.set('confirm', co);
		}
		else
		{
			// confirmOffset global: true para skins normales (default), false para pixel
			var useDefault = skinData.confirmOffset != null
				? skinData.confirmOffset
				: (skinData.offsetDefault != null ? skinData.offsetDefault : !(skinData.isPixel == true));
			if (useDefault)
				map.set('confirm', [-13.0, -13.0]);
		}

		return map;
	}

	/**
	 * Devuelve la textura correcta para las NOTAS SCROLL del skin dado.
	 * Prioridad: notesTexture > texture
	 * Construye un par [offsetX, offsetY] para las notas scroll/hold de una
	 * dirección concreta a partir del campo `offset` de las animaciones de nota.
	 *
	 * Lógica de prioridad (de mayor a menor):
	 *   1. offset de la animación scroll (left/down/up/right) — cabeza de nota.
	 *   2. Sin offset (devuelve [0.0, 0.0]).
	 *
	 * Los offsets de hold/holdEnd se resuelven por separado con las defs
	 * leftHold downHold* etc., pero si no están definidos usan el mismo offset
	 * de la cabeza para mantener coherencia visual entre cabeza y cuerpo.
	 *
	 * @param skinData  Datos de la skin activa.
	 * @param noteID    Dirección (0=left, 1=down, 2=up, 3=right).
	 * @return  Array [offsetX, offsetY] listo para aplicar; nunca null.
	*/
	public static function buildNoteOffsets(skinData:NoteSkinData, noteID:Int):Array<Float>
	{
		if (skinData == null) return [0.0, 0.0];

		var i = Std.int(Math.abs(noteID)) % 4;

		// ── animList tiene prioridad sobre el sistema legacy ─────────────────
		if (skinData.animList != null)
		{
			var dirs = ["purple", "blue", "green", "red"];
			// Buscar por nombre específico de dir, luego genérico "scroll"
			for (key in [dirs[i] + "Scroll", "scroll"])
			{
				var data = getAnimListData(skinData.animList, key);
				if (data != null) return [data[0], data[1]];
			}
		}

		// ── Sistema legacy ───────────────────────────────────────────────────
		if (skinData.animations == null) return [0.0, 0.0];
		var anims = skinData.animations;

		// Defs de animación de nota scroll — cadena de fallback libre
		var scrollKeys = [["left","note","allNotes"],["down","note","allNotes"],
						  ["up","note","allNotes"],["right","note","allNotes"]];
		var def:Dynamic = resolveAnimDef(anims, scrollKeys[i]);

		// Extraer offset del def (puede ser String shorthand → sin offset)
		if (def != null && !Std.isOfType(def, String))
		{
			var arr:Dynamic = def.offset;
			if (arr != null)
				return [Std.parseFloat(Std.string(arr[0])), Std.parseFloat(Std.string(arr[1]))];
		}

		return [0.0, 0.0];
	}

	/**
	 * Resuelve el offset para notas HOLD/HOLDEND de una dirección.
	 * Prioridad: offset de la def hold > offset de la def scroll (coherencia) > [0,0].
	 *
	 * @param skinData  Datos de la skin activa.
	 * @param noteID    Dirección (0=left, 1=down, 2=up, 3=right).
	 * @return  Array [offsetX, offsetY] listo para aplicar; nunca null.
	 */
	public static function buildHoldNoteOffsets(skinData:NoteSkinData, noteID:Int):Array<Float>
	{
		if (skinData == null) return [0.0, 0.0];

		var i = Std.int(Math.abs(noteID)) % 4;

		// ── animList tiene prioridad ─────────────────────────────────────────
		if (skinData.animList != null)
		{
			var dirs = ["purple", "blue", "green", "red"];
			for (key in [dirs[i] + "holdend", dirs[i] + "hold", "holdend", "hold"])
			{
				var data = getAnimListData(skinData.animList, key);
				if (data != null) return [data[0], data[1]];
			}
			// Fallback al offset de scroll en animList
			var dirs2 = ["purple", "blue", "green", "red"];
			var data = getAnimListData(skinData.animList, dirs2[i] + "Scroll");
			if (data != null) return [data[0], data[1]];
		}

		// ── Sistema legacy ───────────────────────────────────────────────────
		if (skinData.animations == null) return buildNoteOffsets(skinData, noteID);

		var anims = skinData.animations;

		// Helper inline
		inline function offsetOf(def:Dynamic):Array<Float>
		{
			if (def == null || Std.isOfType(def, String)) return null;
			var arr:Dynamic = def.offset;
			if (arr == null) return null;
			return [Std.parseFloat(Std.string(arr[0])), Std.parseFloat(Std.string(arr[1]))];
		}

		// Defs de hold (piezas) y holdEnd (tail) — cadena de fallback libre
		var holdDirs    = ["leftHold",    "downHold",    "upHold",    "rightHold"];
		var holdEndDirs = ["leftHoldEnd", "downHoldEnd", "upHoldEnd", "rightHoldEnd"];
		var holdDef    = resolveAnimDef(anims, [holdDirs[i],    "hold",    "allHold"]);
		var holdEndDef = resolveAnimDef(anims, [holdEndDirs[i], "holdEnd", "allHoldEnd"]);

		// Preferir holdEnd si tiene offset, si no hold, si no fallback al scroll offset
		var off = offsetOf(holdEndDef);
		if (off != null) return off;
		off = offsetOf(holdDef);
		if (off != null) return off;

		// Fallback: mismo offset que la cabeza de nota para coherencia visual
		return buildNoteOffsets(skinData, noteID);
	}

	public static function getNotesScrollTexture(?skinName:String):NoteSkinTexture
	{
		var d = getCurrentSkinData(skinName);
		if (d == null) return null;
		return d.notesTexture != null ? d.notesTexture : d.texture;
	}

	/**
	 * Devuelve la textura correcta para los HOLDS del skin dado.
	 * Prioridad: holdTexture > notesTexture > texture
	 */
	public static function getHoldTexture(?skinName:String):NoteSkinTexture
	{
		var d = getCurrentSkinData(skinName);
		if (d == null) return null;
		if (d.holdTexture != null) return d.holdTexture;
		if (d.notesTexture != null) return d.notesTexture;
		return d.texture;
	}

	/**
	 * Devuelve true si la textura dada es de tipo "funkinsprite".
	 * Usado por Note/StrumNote para decidir si usar FunkinSprite en vez de FlxSprite.
	 */
	public static inline function isFunkinSpriteType(tex:NoteSkinTexture):Bool
	{
		return tex != null && tex.type != null && tex.type.toLowerCase() == "funkinsprite";
	}

	// ── Helpers de escala convenientes ───────────────────────────────────

	public static function getNoteScale(?skinName:String):Float
	{
		var d = getCurrentSkinData(skinName);
		return (d != null && d.texture != null && d.texture.scale != null) ? d.texture.scale : 0.7;
	}

	public static function getPixelNoteScale(?skinName:String):Float
	{
		var d = getCurrentSkinData(skinName);
		return (d != null && d.texture != null && d.texture.scale != null) ? d.texture.scale : funkin.gameplay.PlayStateConfig.PIXEL_ZOOM;
	}

	public static function getPixelEndsScale(?skinName:String):Float
	{
		var d = getCurrentSkinData(skinName);
		if (d == null)
			return funkin.gameplay.PlayStateConfig.PIXEL_ZOOM;
		var tex = d.holdTexture != null ? d.holdTexture : d.texture;
		return (tex != null && tex.scale != null) ? tex.scale : funkin.gameplay.PlayStateConfig.PIXEL_ZOOM;
	}

	// ── Getters legacy (siguen funcionando para código externo) ──────────

	public static function getNoteSkin(?skinName:String):FlxAtlasFrames
	{
		var d = getCurrentSkinData(skinName);
		return loadAtlas(d.texture, d.folder);
	}

	public static function getPixelNoteSkin(?skinName:String):FlxAtlasFrames
	{
		var d = getCurrentSkinData(skinName);
		return loadAtlas(d.texture, d.folder);
	}

	public static function getPixelNoteEnds(?skinName:String):FlxAtlasFrames
	{
		var d = getCurrentSkinData(skinName);
		var tex = d.holdTexture != null ? d.holdTexture : d.texture;
		return loadAtlas(tex, d.folder);
	}

	public static function getSkinAnimations(?skinName:String):NoteSkinAnims
	{
		var d = getCurrentSkinData(skinName);
		return d != null ? d.animations : null;
	}

	// ==================== HELPERS DE RESOLUCIÓN DE ANIMACIONES ====================

	/**
	 * Resuelve una definición de animación desde el objeto `animations` (Dynamic).
	 * Prueba cada clave en orden y devuelve el primer valor no-null.
	 *
	 * Esto permite que el JSON sea completamente libre: el mismo método funciona
	 * tanto con los nombres clásicos ("left", "strumLeftConfirm"…) como con los
	 * nuevos genéricos ("note", "hold", "strum"…) o cualquier clave custom.
	 *
	 * Uso típico en Note.hx:
	 *   var def = NoteSkinSystem.resolveAnimDef(anims, ["left", "note", "allNotes"]);
	 *   NoteSkinSystem.addAnimToSprite(this, "leftScroll", def);
	 *
	 * @param anims  Objeto Dynamic del JSON (skinData.animations).
	 * @param keys   Claves a probar en orden de prioridad.
	 * @return  Primera definición no-null encontrada, o null si ninguna existe.
	 */
	public static function resolveAnimDef(anims:Dynamic, keys:Array<String>):Dynamic
	{
		if (anims == null) return null;
		for (key in keys)
		{
			var val:Dynamic = Reflect.field(anims, key);
			if (val != null) return val;
		}
		return null;
	}

	/**
	 * Resuelve la lista de variantes de animación para un splash en una dirección.
	 *
	 * Orden de prioridad:
	 *   1. Campo específico de dirección: "left" / "down" / "up" / "right"
	 *   2. Campo genérico compartido:     "all"
	 *
	 * Esto permite un splash con una sola animación para todas las columnas:
	 *   "animations": { "all": ["note impact 1", "note impact 2"] }
	 * O con overrides por dirección:
	 *   "animations": { "all": ["generic"], "left": ["specialLeft1", "specialLeft2"] }
	 *
	 * @param anims     Bloque animations del splash JSON.
	 * @param noteData  Índice de dirección (0=left, 1=down, 2=up, 3=right).
	 * @return Array de prefijos de animación, o null si no hay ninguno definido.
	 */
	public static function resolveSplashList(anims:SplashAnimations, noteData:Int):Array<String>
	{
		if (anims == null) return null;
		var dirs = ["left", "down", "up", "right"];
		var specific:Array<String> = Reflect.field(anims, dirs[noteData % 4]);
		if (specific != null && specific.length > 0) return specific;
		return anims.all;
	}

	// ==================== HELPER: AÑADIR ANIMACIÓN ====================

	/**
	 * Añade una animación a un FlxSprite desde un campo de animación del JSON.
	 *
	 * Acepta:
	 *   String:         "purple0"                     → addByPrefix("purple0")
	 *   Objeto prefix:  {"prefix":"purple0"}           → addByPrefix("purple0")
	 *   Objeto indices: {"indices":[4],"framerate":24} → animation.add([4], 24)
	 *
	 * Si def es null no hace nada — la animación simplemente no se registra.
	 *
	 * @param overrideLoop  When non-null, forces the loop flag regardless of what
	 *                      the JSON definition says.  Pass `false` for strum
	 *                      animations (pressed / confirm) so that
	 *                      animation.curAnim.finished works correctly and the
	 *                      auto-reset to 'static' fires as expected.
	 *                      Passing `null` (default) preserves the original
	 *                      behaviour: loop comes from the def object, or defaults
	 *                      to false for indices/prefix objects and false for plain
	 *                      strings (previously defaulted to Flixel's loop=true).
	 */
	public static function addAnimToSprite(sprite:FlxSprite, animName:String, def:Dynamic, ?overrideLoop:Bool):Void
	{
		if (sprite == null || def == null)
			return;

		if (Std.isOfType(def, String))
		{
			// Plain string shorthand — no framerate or loop info in the def.
			// Default to loop=false so strum confirm/pressed finish correctly.
			// overrideLoop takes precedence when explicitly supplied.
			var loop:Bool = overrideLoop != null ? overrideLoop : false;
			sprite.animation.addByPrefix(animName, cast(def, String), 24, loop);
			return;
		}

		var prefix:String = def.prefix;
		var indices:Dynamic = def.indices;
		var fps:Int = def.framerate != null ? Std.int(def.framerate) : 24;
		// overrideLoop wins; fall back to the def's loop field; then false.
		var loop:Bool = overrideLoop != null ? overrideLoop : (def.loop != null ? (def.loop == true) : false);

		if (indices != null)
		{
			var arr:Array<Int> = [];
			for (v in (indices : Array<Dynamic>))
				arr.push(Std.int(v));
			sprite.animation.add(animName, arr, fps, loop);
		}
		else if (prefix != null)
		{
			sprite.animation.addByPrefix(animName, prefix, fps, loop);
		}
		else
		{
			trace('[NoteSkinSystem] addAnimToSprite: "$animName" no tiene prefix ni indices — ignorado');
		}
	}

	// ==================== ANIMLIST (ESTILO PERSONAJE) ====================

	/**
	 * Registra todas las animaciones de un SkinAnimEntry list en un FlxSprite.
	 *
	 * Acepta los campos `fps` o `framerate` (compatibilidad AnimData),
	 * `loop` o `looped`, y aplica flipX/flipY cuando se reproduce (no al registrar).
	 *
	 * @return  Mapa animName → [offsetX, offsetY, flipX:0|1, flipY:0|1].
	 *          Se usa en _applyNoteAnim / playAnim / _playRandomAnim para
	 *          aplicar offsets y volteos por animación igual que los personajes.
	 */
	public static function loadAnimList(sprite:FlxSprite, list:Array<SkinAnimEntry>):Map<String, Array<Float>>
	{
		var offsetMap:Map<String, Array<Float>> = new Map();
		if (sprite == null || list == null) return offsetMap;

		for (entry in list)
		{
			if (entry == null || entry.name == null || entry.prefix == null) continue;

			var fps:Int  = entry.fps      != null ? entry.fps
			             : entry.framerate != null ? Std.int(entry.framerate) : 24;
			var loop:Bool = entry.loop   != null ? entry.loop
			              : entry.looped != null ? entry.looped : false;

			if (entry.indices != null && entry.indices.length > 0)
				sprite.animation.add(entry.name, entry.indices, fps, loop);
			else
				sprite.animation.addByPrefix(entry.name, entry.prefix, fps, loop);

			var ox:Float = (entry.offsets != null && entry.offsets.length > 0) ? entry.offsets[0] : 0.0;
			var oy:Float = (entry.offsets != null && entry.offsets.length > 1) ? entry.offsets[1] : 0.0;
			var fx:Float = entry.flipX == true ? 1.0 : 0.0;
			var fy:Float = entry.flipY == true ? 1.0 : 0.0;
			offsetMap.set(entry.name, [ox, oy, fx, fy]);
		}

		return offsetMap;
	}

	/**
	 * Obtiene los datos de una animación del animList: [offsetX, offsetY, flipX:0|1, flipY:0|1].
	 * Devuelve null si la animación no existe en el list.
	 */
	public static function getAnimListData(list:Array<SkinAnimEntry>, animName:String):Array<Float>
	{
		if (list == null || animName == null) return null;
		for (entry in list)
			if (entry != null && entry.name == animName)
			{
				var ox:Float = (entry.offsets != null && entry.offsets.length > 0) ? entry.offsets[0] : 0.0;
				var oy:Float = (entry.offsets != null && entry.offsets.length > 1) ? entry.offsets[1] : 0.0;
				var fx:Float = entry.flipX == true ? 1.0 : 0.0;
				var fy:Float = entry.flipY == true ? 1.0 : 0.0;
				return [ox, oy, fx, fy];
			}
		return null;
	}

	/**
	 * Resuelve los nombres de variante de splash del animList para una dirección.
	 *
	 * Prioridad:
	 *   1. Entradas cuyo `name` comienza con "{dir}_"  (e.g. "left_0", "left_1")
	 *   2. Entradas cuyo `name` comienza con "all_"    (fallback compartido)
	 *   3. Si solo hay UNA entrada en el list → se usa para todas las dirs (single splash)
	 *
	 * @param list      animList del NoteSplashData.
	 * @param noteData  Dirección (0=left, 1=down, 2=up, 3=right).
	 * @return  Array con los nombres internos de las variantes, vacío si no hay nada.
	 */
	public static function resolveSplashNamesFromAnimList(list:Array<SkinAnimEntry>, noteData:Int):Array<String>
	{
		if (list == null || list.length == 0) return [];
		var dirs = ["left", "down", "up", "right"];
		var dir  = dirs[noteData % 4];

		// 1. Variantes específicas de dirección: "left_0", "left_1", etc.
		var specific:Array<String> = [];
		for (entry in list)
			if (entry != null && entry.name != null && entry.name.startsWith(dir + "_"))
				specific.push(entry.name);
		if (specific.length > 0) return specific;

		// 2. Fallback compartido "all_N"
		var all:Array<String> = [];
		for (entry in list)
			if (entry != null && entry.name != null && entry.name.startsWith("all_"))
				all.push(entry.name);
		if (all.length > 0) return all;

		// 3. Single splash: una sola entrada → usar para todas las dirs
		if (list.length == 1 && list[0] != null)
			return [list[0].name];

		return [];
	}

	// ==================== GETTERS DE SPLASH ====================

	public static function getSplashTexture(?splashName:String):FlxAtlasFrames
	{
		if (!initialized)
			init();
		var d = availableSplashes.get(splashName != null ? splashName : currentSplash);
		if (d == null)
			d = availableSplashes.get("Default");
		return loadAtlasSplash(d.assets, d.folder);
	}

	public static function getSplashAnimations(?splashName:String):SplashAnimations
	{
		if (!initialized)
			init();
		var d = availableSplashes.get(splashName != null ? splashName : currentSplash);
		if (d == null)
			d = availableSplashes.get("Default");
		return d.animations;
	}

	public static function getSplashData(?splashName:String):NoteSplashData
	{
		if (!initialized)
			init();
		var d = availableSplashes.get(splashName != null ? splashName : currentSplash);
		if (d == null)
			d = availableSplashes.get("Default");
		return d;
	}

	// ==================== HOLD COVERS ====================

	/**
	 * Devuelve los datos de configuración del hold cover para el splash actual.
	 * Si el splash.json no tiene sección "holdCover", devuelve los defaults que
	 * reproducen el comportamiento original (perColorTextures=true, prefijos estándar).
	 */
	public static function getHoldCoverData(?splashName:String):NoteHoldCoverData
	{
		if (!initialized)
			init();
		var d = availableSplashes.get(splashName != null ? splashName : currentSplash);
		if (d == null)
			d = availableSplashes.get("Default");

		// Si el splash tiene datos propios, devolverlos completando los nulls con defaults.
		var hc:NoteHoldCoverData = (d != null && d.holdCover != null) ? d.holdCover : {};

		// Rellenar defaults inline para que NoteHoldCover nunca tenga que hacer null-checks.
		if (hc.perColorTextures == null) hc.perColorTextures = true;
		if (hc.texturePrefix    == null) hc.texturePrefix    = "holdCover";
		if (hc.textureType      == null) hc.textureType      = "sparrow";
		if (hc.scale            == null) hc.scale            = 1.0;
		if (hc.antialiasing     == null) hc.antialiasing     = true;
		if (hc.framerate        == null) hc.framerate        = 24;
		if (hc.loopFramerate    == null) hc.loopFramerate    = 48;
		if (hc.startPrefix      == null) hc.startPrefix      = "holdCoverStart";
		if (hc.loopPrefix       == null) hc.loopPrefix       = "holdCover";
		if (hc.endPrefix        == null) hc.endPrefix        = "holdCoverEnd";
		// offset null = auto calculado en NoteHoldCover (width*0.3, height*0.3)

		return hc;
	}

	/**
	 * Comprueba si existen los assets de hold cover para el color y splash dados.
	 * Usa la configuración del splash.json si está disponible.
	 */
	public static function holdCoverExists(color:String, ?splashName:String):Bool
	{
		if (!initialized)
			init();
		var d = availableSplashes.get(splashName != null ? splashName : currentSplash);
		if (d == null)
			d = availableSplashes.get("Default");
		var folder = d != null && d.folder != null ? d.folder : "Default";
		var hc = getHoldCoverData(splashName);

		var texPath = hc.perColorTextures
			? '${hc.texturePrefix}$color'
			: hc.texturePrefix;
		return splashAssetExists(texPath, folder);
	}

	/**
	 * Carga el FlxAtlasFrames del hold cover para el color y splash dados.
	 * Respeta la configuración de texturePrefix, perColorTextures y textureType
	 * del splash.json — sin nada hardcodeado.
	 */
	public static function getHoldCoverTexture(color:String, ?splashName:String):FlxAtlasFrames
	{
		if (!initialized)
			init();
		var d = availableSplashes.get(splashName != null ? splashName : currentSplash);
		if (d == null)
			d = availableSplashes.get("Default");
		var folder = d != null && d.folder != null ? d.folder : "Default";
		var hc = getHoldCoverData(splashName);

		// Construir path según modo (per-color o atlas único)
		var texPath = hc.perColorTextures
			? '${hc.texturePrefix}$color'
			: hc.texturePrefix;

		if (!splashAssetExists(texPath, folder))
		{
			// Fallback a Default si el splash actual no tiene el asset
			if (folder != "Default" && splashAssetExists(texPath, "Default"))
				folder = "Default";
			else
				return null;
		}

		try
		{
			var fullPath = '$folder/$texPath';
			return switch (hc.textureType.toLowerCase())
			{
				case "packer": FlxAtlasFrames.fromSpriteSheetPacker(
					flixel.FlxG.bitmap.add('assets/notes/splashes/$fullPath.png'),
					'assets/notes/splashes/$fullPath.txt');
				default: Paths.splashSprite(fullPath); // sparrow
			};
		}
		catch (e:Dynamic)
		{
			trace('[NoteSkinSystem] Error cargando holdCover $folder/$texPath: $e');
			return null;
		}
	}

	public static function getCurrentSplashFolder():String
	{
		if (!initialized)
			init();
		var d = availableSplashes.get(currentSplash);
		if (d == null)
			d = availableSplashes.get("Default");
		return d.folder != null ? d.folder : "Default";
	}

	// ==================== LISTAS ====================

	public static function getSkinList():Array<String>
	{
		if (!initialized)
			init();
		return [for (k in availableSkins.keys()) k];
	}

	public static function getSplashList():Array<String>
	{
		if (!initialized)
			init();
		return [for (k in availableSplashes.keys()) k];
	}

	public static function getSkinInfo(n:String):NoteSkinData
	{
		if (!initialized)
			init();
		return availableSkins.get(n);
	}

	public static function getSplashInfo(n:String):NoteSplashData
	{
		if (!initialized)
			init();
		return availableSplashes.get(n);
	}

	// ==================== CARGA INTERNA DE ATLAS ====================

	private static function loadAtlas(tex:Dynamic, ?folderName:String):FlxAtlasFrames
	{
		// BUG C FIX: reset flag at start of every call so callers get accurate info.
		lastLoadFellBack = false;

		if (tex == null || tex.path == null)
		{
			trace('[NoteSkinSystem] loadAtlas: textura inválida, usando Default');
			lastLoadFellBack = true;
			var fallback = Paths.skinSprite('Default/NOTE_assets');
			if (fallback != null) return fallback;
			return _makeFallbackFrames();
		}

		var path:String = tex.path;
		var type:String = tex.type != null ? tex.type : "sparrow";
		var folder:String = folderName != null ? folderName : "Default";

		if (!assetExists(path, folder))
		{
			trace('[NoteSkinSystem] loadAtlas: "$folder/$path" not found, usando Default');
			lastLoadFellBack = true;
			var fallback = Paths.skinSprite('Default/NOTE_assets');
			if (fallback != null) return fallback;
			return _makeFallbackFrames();
		}

		try
		{
			var result:FlxAtlasFrames = null;
			switch (type.toLowerCase())
			{
				case "sparrow":
					result = Paths.skinSprite('$folder/$path');

				case "packer":
					result = Paths.skinSpriteTxt('$folder/$path');

				case "funkinsprite":
					// FunkinSprite (Adobe Animate Atlas) — devolvemos null intencionalmente.
					// Note.hx y StrumNote.hx detectan isFunkinSpriteType() ANTES de llamar
					// loadSkinFrames() y crean un FunkinSprite en su lugar.
					// Este case evita el trace de "tipo desconocido" y el fallback a Default.
					return null;

				case "image":
					var graphic = FlxG.bitmap.add('assets/notes/skins/$folder/$path.png');
					if (graphic == null) throw 'PNG not found para image skin: $folder/$path';
					// BUGFIX: FlxG.bitmap.add() deja persist=false y useCount=0.
					// FunkinCache.clearSecondLayer() → clearUnused() destruye cualquier
					// gráfico con persist=false + useCount=0 al final de postStateSwitch,
					// ANTES de que los StrumNotes/Notes hayan dibujado su primer frame.
					// Resultado: frame.parent.bitmap = null → FlxDrawQuadsItem::render crash.
					// Solución: marcar persist=true y registrar en PathsCache para que el
					// sistema de caché lo gestione correctamente entre sesiones.
					graphic.persist = true;
					graphic.destroyOnNoUse = false;
					funkin.cache.PathsCache.instance.trackGraphic('assets/notes/skins/$folder/$path.png', graphic);
					// Dimensiones de frame leídas del JSON — sin hardcodeo por nombre de archivo
					var fw:Int = tex.frameWidth != null ? Std.int(tex.frameWidth) : 17;
					var fh:Int = tex.frameHeight != null ? Std.int(tex.frameHeight) : 17;
					trace('[NoteSkinSystem] image atlas $folder/$path — frame: ${fw}×${fh}px');
					result = FlxAtlasFramesExt.fromGraphic(graphic, fw, fh);

				default:
					trace('[NoteSkinSystem] tipo desconocido "$type" en $folder/$path, usando sparrow');
					result = Paths.skinSprite('$folder/$path');
			}

			if (result != null) return result;

			// Resultado null (ej: XML faltante con PNG presente) → fallback Default
			trace('[NoteSkinSystem] loadAtlas: "$folder/$path" devolvió null, probando Default');
			var fallback = Paths.skinSprite('Default/NOTE_assets');
			if (fallback != null) return fallback;
			return _makeFallbackFrames();
		}
		catch (e:Dynamic)
		{
			trace('[NoteSkinSystem] Error cargando $folder/$path: $e');
			var fallback = Paths.skinSprite('Default/NOTE_assets');
			if (fallback != null) return fallback;
			return _makeFallbackFrames();
		}
	}

	/**
	 * Último recurso: crea un FlxAtlasFrames de 1×1 píxel para que los sprites
	 * nunca tengan frames=null. Sin esto, cualquier StrumNote/Note con skin rota
	 * causa FlxDrawQuadsItem::render crash en el primer frame de PlayState.
	 */
	private static function _makeFallbackFrames():FlxAtlasFrames
	{
		trace('[NoteSkinSystem] FALLBACK: usando frames de 1×1 para evitar crash de render');
		var bmp = new openfl.display.BitmapData(1, 1, true, 0x00000000);
		var g = FlxG.bitmap.add(bmp, false, 'note_skin_fallback_${Math.random()}');
		if (g == null)
		{
			// Último último recurso: crear FlxGraphic directamente
			g = flixel.graphics.FlxGraphic.fromBitmapData(bmp, false, null, false);
		}
		// fromGraphic con frames 1×1 → atlas de 1 frame, 1×1 px
		return FlxAtlasFramesExt.fromGraphic(g, 1, 1);
	}

	private static function loadAtlasSplash(assets:Dynamic, ?folderName:String):FlxAtlasFrames
	{
		if (assets == null || assets.path == null)
			return Paths.splashSprite('Default/noteSplashes');
		var path = (assets.path : String);
		var type = assets.type != null ? (assets.type : String) : "sparrow";
		var folder = folderName != null ? folderName : "Default";
		if (!splashAssetExists(path, folder))
			return Paths.splashSprite('Default/noteSplashes');
		try
		{
			switch (type.toLowerCase())
			{
				case "sparrow":
					return Paths.splashSprite('$folder/$path');
				case "packer":
					return FlxAtlasFrames.fromSpriteSheetPacker(FlxG.bitmap.add('assets/notes/splashes/$folder/$path.png'), 'assets/notes/splashes/$folder/$path.txt');
				case "image":
					var g = FlxG.bitmap.add('assets/notes/splashes/$folder/$path.png');
					if (g == null) throw 'PNG not found para image splash: $folder/$path';
					// BUGFIX: igual que loadAtlas "image" — persist=true para evitar que
					// clearSecondLayer() → clearUnused() destruya el gráfico antes del primer render.
					g.persist = true;
					g.destroyOnNoUse = false;
					funkin.cache.PathsCache.instance.trackGraphic('assets/notes/splashes/$folder/$path.png', g);
					return FlxAtlasFramesExt.fromGraphic(g, g.width, g.height);
				default:
					return Paths.splashSprite('$folder/$path');
			}
		}
		catch (e:Dynamic)
		{
			return Paths.splashSprite('Default/noteSplashes');
		}
	}

	private static function assetExists(path:String, folder:String):Bool
	{
		#if sys
		// Comprobar primero en el mod activo, luego en assets base.
		// Sin esto, skins en mods/MyMod/notes/skins/ZoneNotes/NOTE_assets.png
		// son ignoradas y el juego cae silenciosamente al Default.
		final modRoot = mods.ModManager.modRoot();
		if (modRoot != null && sys.FileSystem.exists('$modRoot/notes/skins/$folder/$path.png'))
			return true;
		return sys.FileSystem.exists('assets/notes/skins/$folder/$path.png') || sys.FileSystem.exists('$path.png');
		#else
		return openfl.utils.Assets.exists('assets/notes/skins/$folder/$path.png');
		#end
	}

	private static function splashAssetExists(path:String, folder:String):Bool
	{
		#if sys
		// Misma lógica que assetExists: comprobar mod primero.
		final modRoot = mods.ModManager.modRoot();
		if (modRoot != null && sys.FileSystem.exists('$modRoot/notes/splashes/$folder/$path.png'))
			return true;
		return sys.FileSystem.exists('assets/notes/splashes/$folder/$path.png') || sys.FileSystem.exists('$path.png');
		#else
		return openfl.utils.Assets.exists('assets/notes/splashes/$folder/$path.png');
		#end
	}

	// ==================== EXPORT EXAMPLES ====================

	/**
	 * Genera un JSON de ejemplo para una skin normal.
	 * Colócalo en:  assets/notes/skins/MiSkin/skin.json
	 */
	public static function exportSkinExample():String
	{
		return Json.stringify({
			name: "Custom Skin",
			author: "Your Name",
			description: "My custom note skin",
			// texture: textura principal (fallback para todo si no se definen las otras)
			texture: {
				path: "NOTE_assets",
				type: "sparrow", // "sparrow" | "packer" | "image" | "funkinsprite"
				scale: 0.7,
				antialiasing: true
			},
			// strumsTexture: SOLO para los strums (null = usa texture)
			// strumsTexture: { path: "MY_strums", type: "sparrow", scale: 0.7 },
			// notesTexture: SOLO para las notas que bajan (null = usa texture)
			// notesTexture: { path: "MY_notes", type: "sparrow", scale: 0.7 },
			confirmOffset: true,
			animations: {
				left: "purple0",
				down: "blue0",
				up: "green0",
				right: "red0",
				leftHold: "purple hold piece",
				downHold: "blue hold piece",
				upHold: "green hold piece",
				rightHold: "red hold piece",
				leftHoldEnd: "pruple end hold",
				downHoldEnd: "blue hold end",
				upHoldEnd: "green hold end",
				rightHoldEnd: "red hold end",
				strumLeft: "arrowLEFT",
				strumDown: "arrowDOWN",
				strumUp: "arrowUP",
				strumRight: "arrowRIGHT",
				strumLeftPress: "left press",
				strumDownPress: "down press",
				strumUpPress: "up press",
				strumRightPress: "right press",
				strumLeftConfirm: "left confirm",
				strumDownConfirm: "down confirm",
				strumUpConfirm: "up confirm",
				strumRightConfirm: "right confirm"
			}
		}, null, "  ");
	}

	/**
	 * Genera un JSON de ejemplo para una skin PIXEL.
	 * Colócalo en:  assets/notes/skins/MiSkinPixel/skin.json
	 *
	 * Para asociarlo a un stage:
	 *   NoteSkinSystem.registerStageSkin("miStage", "MiSkinPixel");
	 * O desde PlayState:
	 *   NoteSkinSystem.applySkinForStage(PlayState.curStage);
	 */
	public static function exportPixelSkinExample():String
	{
		return Json.stringify({
			name: "Custom Pixel Skin",
			author: "Your Name",
			description: "My pixel note skin",
			isPixel: true,
			confirmOffset: false,
			sustainOffset: 30,
			holdStretch: 1.19,
			texture: {
				path: "arrows-pixels",
				type: "image",
				frameWidth: 17,
				frameHeight: 17,
				scale: 6.0,
				antialiasing: false
			},
			holdTexture: {
				path: "arrowEnds",
				type: "image",
				frameWidth: 7,
				frameHeight: 6,
				scale: 6.0,
				antialiasing: false
			},
			animations: {
				left: {indices: [4]},
				down: {indices: [5]},
				up: {indices: [6]},
				right: {indices: [7]},
				leftHold: {indices: [0]},
				downHold: {indices: [1]},
				upHold: {indices: [2]},
				rightHold: {indices: [3]},
				leftHoldEnd: {indices: [4]},
				downHoldEnd: {indices: [5]},
				upHoldEnd: {indices: [6]},
				rightHoldEnd: {indices: [7]},
				strumLeft: {indices: [0]},
				strumDown: {indices: [1]},
				strumUp: {indices: [2]},
				strumRight: {indices: [3]},
				strumLeftPress: {indices: [4, 8], framerate: 12},
				strumDownPress: {indices: [5, 9], framerate: 12},
				strumUpPress: {indices: [6, 10], framerate: 12},
				strumRightPress: {indices: [7, 11], framerate: 12},
				strumLeftConfirm: {indices: [12, 16], framerate: 24},
				strumDownConfirm: {indices: [13, 17], framerate: 24},
				strumUpConfirm: {indices: [14, 18], framerate: 24},
				strumRightConfirm: {indices: [15, 19], framerate: 24}
			}
		}, null, "  ");
	}

	public static function exportSplashExample():String
	{
		return Json.stringify({
			name: "Custom Splash",
			author: "Your Name",
			description: "My custom splash",
			assets: {
				path: "noteSplashes",
				type: "sparrow",
				scale: 1.0,
				antialiasing: true,
				offset: [0, 0]
			},
			animations: {
				left: ["note impact 1 purple", "note impact 2 purple"],
				down: ["note impact 1 blue", "note impact 2 blue"],
				up: ["note impact 1 green", "note impact 2 green"],
				right: ["note impact 1 red", "note impact 2 red"],
				framerate: 24,
				randomFramerateRange: 3
			},
			// Sección holdCover opcional — omitirla usa los defaults del engine.
			// Copia y personaliza para modificar el cover visual de notas largas.
			holdCover: {
				perColorTextures: true,
				texturePrefix: "holdCover",
				textureType: "sparrow",
				scale: 1.0,
				antialiasing: true,
				framerate: 24,
				loopFramerate: 48,
				offset: [0, 0],
				startPrefix: "holdCoverStart",
				loopPrefix: "holdCover",
				endPrefix: "holdCoverEnd"
			}
		}, null, "  ");
	}

	/**
	 * Genera un JSON de ejemplo de splash.json con sección holdCover personalizada.
	 * Útil como punto de partida para un splash con atlas único compartido.
	 *
	 * Coloca el JSON en: assets/notes/splashes/MySplash/splash.json
	 * Y los assets en:   assets/notes/splashes/MySplash/holdCoverAll.png  (+ .xml)
	 */
	public static function exportHoldCoverExample():String
	{
		return Json.stringify({
			name: "Custom Hold Cover",
			author: "Your Name",
			description: "Single-atlas hold cover example",
			assets: {
				path: "noteSplashes",
				type: "sparrow",
				scale: 1.0,
				antialiasing: true
			},
			animations: {
				left: ["note impact 1 purple", "note impact 2 purple"],
				down: ["note impact 1 blue", "note impact 2 blue"],
				up: ["note impact 1 green", "note impact 2 green"],
				right: ["note impact 1 red", "note impact 2 red"],
				framerate: 24
			},
			holdCover: {
				// Atlas único: holdCoverAll.png contiene todos los colores
				perColorTextures: false,
				texturePrefix: "holdCoverAll",
				textureType: "sparrow",
				scale: 1.0,
				antialiasing: true,
				framerate: 24,
				loopFramerate: 48,
				// offset null = auto (width*0.3, height*0.3)
				// Los prefijos de animación reciben el color como sufijo:
				// "myStart" → "myStartPurple", "myStartBlue"...
				startPrefix: "holdCoverStart",
				loopPrefix: "holdCover",
				endPrefix: "holdCoverEnd"
			}
		}, null, "  ");
	}
}
