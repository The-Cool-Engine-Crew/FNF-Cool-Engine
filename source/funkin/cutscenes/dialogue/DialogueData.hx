package funkin.cutscenes.dialogue;

import haxe.Json;
import sys.io.File;
import sys.FileSystem;
import Paths;

using StringTools;

/**
 * Tipos de estilos de diálogo
 */
enum DialogueStyle {
    PIXEL;
    NORMAL;
    CUSTOM;
}

/**
 * Tipos de burbujas de diálogo
 */
enum BubbleType {
    NORMAL;
    LOUD;
    ANGRY;
    EVIL;
    CUSTOM;
}

/**
 * Configuración de un portrait personalizado
 */
typedef PortraitConfig = {
    var name:String;              // Nombre del portrait
    var fileName:String;          // Nombre del archivo (sin ruta)
    var ?x:Float;                 // Posición X
    var ?y:Float;                 // Posición Y
    var ?scaleX:Float;            // Escala X
    var ?scaleY:Float;            // Escala Y
    var ?flipX:Bool;              // Voltear horizontalmente
    var ?animation:String;        // Nombre de la animación
}

/**
 * Configuración de una caja de diálogo personalizada
 */
typedef BoxConfig = {
    var name:String;              // Nombre de la caja
    var fileName:String;          // Nombre del archivo (sin ruta)
    var ?x:Float;                 // Posición X
    var ?y:Float;                 // Posición Y
    var ?width:Int;               // Ancho
    var ?height:Int;              // Alto
    var ?scaleX:Float;            // Escala X
    var ?scaleY:Float;            // Escala Y
    var ?animation:String;        // Animación a usar
}

/**
 * Configuración de posición del texto
 */
typedef TextConfig = {
    var ?x:Float;                 // Posición X del texto
    var ?y:Float;                 // Posición Y del texto
    var ?width:Int;               // Ancho del área de texto
    var ?size:Int;                // Tamaño de fuente
    var ?font:String;             // Fuente
    var ?color:String;            // Color del texto (hex)
}

/**
 * Configuración de un fondo o overlay de la skin.
 * Reutilizada para fondos (backgrounds/) y overlays (overlays/).
 */
typedef BackgroundConfig = {
    var name:String;              // Nombre identificador
    var fileName:String;          // Nombre del archivo (sin ruta)
    var ?x:Float;                 // Posición X
    var ?y:Float;                 // Posición Y
    var ?scaleX:Float;            // Escala X
    var ?scaleY:Float;            // Escala Y
    var ?alpha:Float;             // Transparencia (0.0–1.0); default 1.0 para bg, 0.8 para overlay
    var ?blendMode:String;        // Blend mode ('normal', 'add', 'multiply', …)
}

/**
 * Configuración completa de una skin de diálogo.
 *
 * ─── scriptFile ───────────────────────────────────────────────────────────────
 *
 *  Si se define, `DialogueBoxImproved` cargará ese archivo HScript y lo
 *  ejecutará. El script recibe la variable `ctx` (DialogueScriptContext) y
 *  puede definir las funciones:
 *
 *    onCreate()               — una vez al crear el diálogo
 *    onUpdate(elapsed:Float)  — cada frame
 *    onInput(action:String)   — al pulsar 'accept' o 'skip'; devolver true consume el input
 *    onMessageStart(msg)      — al iniciar cada mensaje
 *    onMessageEnd(msg)        — cuando el texto termina de escribirse
 *    onEnd()                  — antes del cierre del diálogo
 *
 *  La ruta es relativa a la carpeta de la skin:
 *    assets/cutscenes/dialogue/<skinName>/<scriptFile>
 *
 *  Ejemplo en config.json:
 *    { "scriptFile": "myFormat.hx", ... }
 */
typedef DialogueSkin = {
    var name:String;                                      // Nombre de la skin
    var style:String;                                     // 'pixel' o 'normal' o 'custom'
    var ?backgroundColor:String;                          // Color de fondo (hex)
    var ?fadeTime:Float;                                  // Tiempo de fade (default: 0.83)
    var ?scriptFile:String;                               // Archivo HScript opcional (relativo a la skin)
    var portraits:Map<String, PortraitConfig>;            // Portraits de la skin
    var boxes:Map<String, BoxConfig>;                     // Cajas de la skin
    var ?backgrounds:Map<String, BackgroundConfig>;       // Fondos de la skin (assets en backgrounds/)
    var ?overlays:Map<String, BackgroundConfig>;          // Overlays de la skin  (assets en overlays/)
    var ?textConfig:TextConfig;                           // Configuración del texto
}

/**
 * Datos de un mensaje individual de diálogo
 */
typedef DialogueMessage = {
    var character:String;           // 'dad' o 'bf' o nombre personalizado
    var text:String;               // Texto del diálogo
    var ?bubbleType:String;        // 'normal', 'loud', 'angry', 'evil'
    var ?speed:Float;              // Velocidad del texto (default: 0.04)
    var ?portrait:String;          // Nombre del portrait a usar
    var ?boxSprite:String;         // Nombre de la caja a usar
    var ?music:String;             // Música de fondo (opcional)
    var ?sound:String;             // Sonido del texto (opcional)
}

/**
 * Datos de una conversación (solo mensajes + referencia a skin)
 */
typedef DialogueConversation = {
    var name:String;                // Nombre de la conversación
    var skinName:String;            // Nombre de la skin a usar
    var messages:Array<DialogueMessage>;
}

/**
 * Clase para manejar datos de diálogos y skins
 */
class DialogueData {
    /**
     * Ruta base de las skins para LECTURA.
     * Busca primero en el mod activo, luego en assets/.
     * Equivale a Paths.resolve('cutscenes/dialogue/').
     */
    public static function getSkinsBasePath():String {
        return Paths.resolve('cutscenes/dialogue/');
    }

    /**
     * Ruta base de las skins para ESCRITURA.
     * Escribe en el mod activo si hay uno activo, o en assets/.
     */
    public static function getSkinsWritePath():String {
        return Paths.resolveWrite('cutscenes/dialogue/');
    }

    /**
     * Ruta al asset de un portrait dentro de una skin.
     */
    public static function getPortraitAssetPath(skinName:String, fileName:String):String {
        return 'cutscenes/dialogue/$skinName/portraits/$fileName';
    }

    /**
     * Ruta al asset de una caja dentro de una skin.
     */
    public static function getBoxAssetPath(skinName:String, fileName:String):String {
        return 'cutscenes/dialogue/$skinName/boxes/$fileName';
    }

    /**
     * Ruta al asset de un fondo dentro de una skin.
     */
    public static function getBackgroundAssetPath(skinName:String, fileName:String):String {
        return 'cutscenes/dialogue/$skinName/backgrounds/$fileName';
    }

    /**
     * Ruta al asset de un overlay dentro de una skin.
     */
    public static function getOverlayAssetPath(skinName:String, fileName:String):String {
        return 'cutscenes/dialogue/$skinName/overlays/$fileName';
    }

    /**
     * Ruta al script HScript de una skin.
     * Devuelve null si la skin no tiene scriptFile.
     */
    public static function getScriptPath(skin:DialogueSkin):Null<String> {
        if (skin == null || skin.scriptFile == null || skin.scriptFile == '')
            return null;
        // Buscar en el mod activo primero, luego en assets/
        var candidate = Paths.resolve('cutscenes/dialogue/${skin.name}/${skin.scriptFile}');
        #if sys
        if (FileSystem.exists(candidate))
            return candidate;
        // Fallback: buscar con extensión .hx si no la tiene
        if (!skin.scriptFile.endsWith('.hx')) {
            var withExt = Paths.resolve('cutscenes/dialogue/${skin.name}/${skin.scriptFile}.hx');
            if (FileSystem.exists(withExt))
                return withExt;
        }
        #end
        return candidate; // devolver de todos modos (el intérprete logrará un error descriptivo)
    }

    /**
     * Listar todas las conversaciones disponibles para una canción.
     * Devuelve los nombres (sin extensión) de todos los .json en assets/songs/<songName>/.
     */
    public static function listConversations(songName:String):Array<String> {
        var result:Array<String> = [];
        #if sys
        var dir = Paths.resolve('songs/${songName.toLowerCase()}/');
        if (!FileSystem.exists(dir))
            return result;
        for (entry in FileSystem.readDirectory(dir)) {
            if (entry.endsWith('.json'))
                result.push(entry.substr(0, entry.length - 5));
        }
        #end
        return result;
    }

    /**
     * Cargar conversación desde JSON.
     * Busca en assets/songs/<songName>/<conversationName>.json.
     */
    public static function loadConversation(songName:String, conversationName:String):DialogueConversation {
        try {
            var path = Paths.resolve('songs/${songName.toLowerCase()}/${conversationName}.json');
            #if sys
            if (!FileSystem.exists(path)) {
                trace('Dialogue file not found: $path');
                return null;
            }
            var content = File.getContent(path);
            #else
            var content = Assets.getText(path);
            if (content == null) return null;
            #end
            var data:DialogueConversation = Json.parse(content);
            return data;
        } catch(e:Dynamic) {
            trace('Error loading conversation for $songName: $e');
            return null;
        }
    }

    /**
     * Cargar skin desde JSON.
     * Busca en assets/cutscenes/dialogue/<skinName>/config.json.
     */
    public static function loadSkin(skinName:String):DialogueSkin {
        try {
            var path = Paths.resolve('cutscenes/dialogue/$skinName/config.json');
            #if sys
            if (!FileSystem.exists(path)) {
                trace('Skin file not found: $path');
                return null;
            }
            var content = File.getContent(path);
            #else
            var content = Assets.getText(path);
            if (content == null) return null;
            #end

            var jsonData:Dynamic = Json.parse(content);

            // Convertir portraits de Dynamic a Map
            var portraitsMap = new Map<String, PortraitConfig>();
            if (jsonData.portraits != null) {
                var portraitsObj:Dynamic = jsonData.portraits;
                for (key in Reflect.fields(portraitsObj)) {
                    var config:PortraitConfig = Reflect.field(portraitsObj, key);
                    portraitsMap.set(key, config);
                }
            }

            var boxesMap = new Map<String, BoxConfig>();
            if (jsonData.boxes != null) {
                var boxesObj:Dynamic = jsonData.boxes;
                for (key in Reflect.fields(boxesObj)) {
                    var config:BoxConfig = Reflect.field(boxesObj, key);
                    boxesMap.set(key, config);
                }
            }

            var backgroundsMap = new Map<String, BackgroundConfig>();
            if (jsonData.backgrounds != null) {
                var bgsObj:Dynamic = jsonData.backgrounds;
                for (key in Reflect.fields(bgsObj)) {
                    backgroundsMap.set(key, cast Reflect.field(bgsObj, key));
                }
            }

            var overlaysMap = new Map<String, BackgroundConfig>();
            if (jsonData.overlays != null) {
                var ovsObj:Dynamic = jsonData.overlays;
                for (key in Reflect.fields(ovsObj)) {
                    overlaysMap.set(key, cast Reflect.field(ovsObj, key));
                }
            }

            // Construir DialogueSkin con Maps convertidos
            var data:DialogueSkin = {
                name: jsonData.name,
                style: jsonData.style,
                backgroundColor: jsonData.backgroundColor,
                fadeTime: jsonData.fadeTime,
                scriptFile: jsonData.scriptFile,   // ← nuevo campo
                portraits: portraitsMap,
                boxes: boxesMap,
                backgrounds: backgroundsMap,
                overlays: overlaysMap,
                textConfig: jsonData.textConfig
            };

            return data;
        } catch(e:Dynamic) {
            trace('Error parsing skin JSON: $e');
            return null;
        }
    }

    /**
     * Guardar configuración de una skin
     */
    public static function saveSkin(skinName:String, skin:DialogueSkin):Bool {
        #if sys
        try {
            createSkinDirectories(skinName);
            var path = getSkinsWritePath() + '$skinName/config.json';

            // Convertir Maps a objetos para JSON
            var portraitsObj:Dynamic = {};
            for (key => val in skin.portraits)
                Reflect.setField(portraitsObj, key, val);

            var boxesObj:Dynamic = {};
            for (key => val in skin.boxes)
                Reflect.setField(boxesObj, key, val);

            var backgroundsObj:Dynamic = {};
            if (skin.backgrounds != null)
                for (key => val in skin.backgrounds)
                    Reflect.setField(backgroundsObj, key, val);

            var overlaysObj:Dynamic = {};
            if (skin.overlays != null)
                for (key => val in skin.overlays)
                    Reflect.setField(overlaysObj, key, val);

            var jsonData:Dynamic = {
                name: skin.name,
                style: skin.style,
                backgroundColor: skin.backgroundColor,
                fadeTime: skin.fadeTime,
                scriptFile: skin.scriptFile,        // ← serializar scriptFile
                portraits: portraitsObj,
                boxes: boxesObj,
                backgrounds: backgroundsObj,
                overlays: overlaysObj,
                textConfig: skin.textConfig
            };

            File.saveContent(path, Json.stringify(jsonData, null, '  '));
            return true;
        } catch(e:Dynamic) {
            trace('Error saving skin: $e');
            return false;
        }
        #else
        return false;
        #end
    }

    /**
     * Crear directorios de una skin si no existen.
     */
    public static function createSkinDirectories(skinName:String):Void {
        #if sys
        var base = getSkinsWritePath() + '$skinName/';
        for (sub in ['', 'portraits/', 'boxes/', 'backgrounds/', 'overlays/', 'sounds/', 'music/']) {
            var dir = base + sub;
            if (!FileSystem.exists(dir))
                FileSystem.createDirectory(dir);
        }
        #end
    }

    /**
     * Crear una skin vacía con valores por defecto.
     */
    public static function createEmptySkin(skinName:String, style:String = 'pixel'):DialogueSkin {
        return {
            name: skinName,
            style: style,
            backgroundColor: '#000000',
            fadeTime: 0.83,
            scriptFile: null,                        // sin script por defecto
            portraits: new Map<String, PortraitConfig>(),
            boxes: new Map<String, BoxConfig>(),
            backgrounds: new Map<String, BackgroundConfig>(),
            overlays: new Map<String, BackgroundConfig>(),
            textConfig: null
        };
    }

    /**
     * Obtener todos los nombres de skins disponibles.
     */
    public static function getAvailableSkins():Array<String> {
        var skins:Array<String> = [];
        #if sys
        var basePath = getSkinsBasePath();
        if (!FileSystem.exists(basePath))
            return skins;
        for (entry in FileSystem.readDirectory(basePath)) {
            var fullPath = basePath + entry;
            if (FileSystem.isDirectory(fullPath)) {
                var configPath = fullPath + '/config.json';
                if (FileSystem.exists(configPath))
                    skins.push(entry);
            }
        }
        #end
        return skins;
    }

    /**
     * Alias de getAvailableSkins() para uso desde el editor.
     */
    public static function listSkins():Array<String> {
        return getAvailableSkins();
    }

    /**
     * Crear una conversación vacía con valores por defecto.
     */
    public static function createEmptyConversation(name:String, skinName:String):DialogueConversation {
        return {
            name: name,
            skinName: skinName,
            messages: []
        };
    }

    /**
     * Guardar conversación en assets/songs/<songName>/<conversation.name>.json.
     * El nombre del archivo es el campo `name` de la conversación (ej: "intro" → intro.json).
     */
    public static function saveConversation(songName:String, conversation:DialogueConversation):Bool {
        #if sys
        try {
            var dir = Paths.resolveWrite('songs/${songName.toLowerCase()}/');
            if (!FileSystem.exists(dir))
                FileSystem.createDirectory(dir);
            var path = dir + '${conversation.name}.json';
            File.saveContent(path, Json.stringify(conversation, null, '  '));
            return true;
        } catch(e:Dynamic) {
            trace('Error saving conversation for $songName: $e');
            return false;
        }
        #else
        return false;
        #end
    }

    /**
     * Devuelve el color de fondo por defecto según el estilo.
     */
    public static function getDefaultBackgroundColor(style:String):String {
        return switch (style) {
            case 'normal': '#B3DFD8';
            default:       '#000000'; // pixel y cualquier otro
        };
    }

    /**
     * Copiar un archivo de imagen al directorio portraits/ de una skin.
     * Devuelve true si tuvo éxito.
     */
    public static function copyPortraitToSkin(sourcePath:String, skinName:String, fileName:String):Bool {
        #if sys
        try {
            createSkinDirectories(skinName);
            var destPath = getSkinsWritePath() + '$skinName/portraits/$fileName';
            var bytes = sys.io.File.getBytes(sourcePath);
            sys.io.File.saveBytes(destPath, bytes);
            return true;
        } catch(e:Dynamic) {
            trace('Error copying portrait to skin: $e');
            return false;
        }
        #else
        return false;
        #end
    }

    /**
     * Crear una configuración de portrait con valores por defecto.
     */
    public static function createPortraitConfig(name:String, fileName:String):PortraitConfig {
        return {
            name: name,
            fileName: fileName,
            x: 0.0,
            y: 0.0,
            scaleX: 1.0,
            scaleY: 1.0,
            flipX: false,
            animation: 'idle'
        };
    }

    /**
     * Copiar un archivo de imagen al directorio boxes/ de una skin.
     * Devuelve true si tuvo éxito.
     */
    public static function copyBoxToSkin(sourcePath:String, skinName:String, fileName:String):Bool {
        #if sys
        try {
            createSkinDirectories(skinName);
            var destPath = getSkinsWritePath() + '$skinName/boxes/$fileName';
            var bytes = sys.io.File.getBytes(sourcePath);
            sys.io.File.saveBytes(destPath, bytes);
            return true;
        } catch(e:Dynamic) {
            trace('Error copying box to skin: $e');
            return false;
        }
        #else
        return false;
        #end
    }

    /**
     * Crear una configuración de caja con valores por defecto.
     */
    public static function createBoxConfig(name:String, fileName:String):BoxConfig {
        return {
            name: name,
            fileName: fileName,
            x: 0.0,
            y: 0.0,
            width: null,
            height: null,
            scaleX: 1.0,
            scaleY: 1.0,
            animation: 'normal'
        };
    }

    /**
     * Copiar un archivo de imagen al directorio backgrounds/ de una skin.
     */
    public static function copyBackgroundToSkin(sourcePath:String, skinName:String, fileName:String):Bool {
        #if sys
        try {
            createSkinDirectories(skinName);
            var destPath = getSkinsWritePath() + '$skinName/backgrounds/$fileName';
            var bytes = sys.io.File.getBytes(sourcePath);
            sys.io.File.saveBytes(destPath, bytes);
            return true;
        } catch(e:Dynamic) {
            trace('Error copying background to skin: $e');
            return false;
        }
        #else
        return false;
        #end
    }

    /**
     * Copiar un archivo de imagen al directorio overlays/ de una skin.
     */
    public static function copyOverlayToSkin(sourcePath:String, skinName:String, fileName:String):Bool {
        #if sys
        try {
            createSkinDirectories(skinName);
            var destPath = getSkinsWritePath() + '$skinName/overlays/$fileName';
            var bytes = sys.io.File.getBytes(sourcePath);
            sys.io.File.saveBytes(destPath, bytes);
            return true;
        } catch(e:Dynamic) {
            trace('Error copying overlay to skin: $e');
            return false;
        }
        #else
        return false;
        #end
    }

    /**
     * Ruta lógica a un sound effect dentro de la skin (para Paths.resolve).
     */
    public static function getSoundAssetPath(skinName:String, fileName:String):String {
        return 'cutscenes/dialogue/$skinName/sounds/$fileName';
    }

    /**
     * Ruta lógica a un archivo de música dentro de la skin.
     */
    public static function getMusicAssetPath(skinName:String, fileName:String):String {
        return 'cutscenes/dialogue/$skinName/music/$fileName';
    }

    /**
     * Copiar un sound effect al directorio sounds/ de una skin.
     */
    public static function copySoundToSkin(sourcePath:String, skinName:String, fileName:String):Bool {
        #if sys
        try {
            createSkinDirectories(skinName);
            var destPath = getSkinsWritePath() + '$skinName/sounds/$fileName';
            sys.io.File.saveBytes(destPath, sys.io.File.getBytes(sourcePath));
            return true;
        } catch(e:Dynamic) {
            trace('Error copying sound to skin: $e');
            return false;
        }
        #else
        return false;
        #end
    }

    /**
     * Copiar un archivo de música al directorio music/ de una skin.
     */
    public static function copyMusicToSkin(sourcePath:String, skinName:String, fileName:String):Bool {
        #if sys
        try {
            createSkinDirectories(skinName);
            var destPath = getSkinsWritePath() + '$skinName/music/$fileName';
            sys.io.File.saveBytes(destPath, sys.io.File.getBytes(sourcePath));
            return true;
        } catch(e:Dynamic) {
            trace('Error copying music to skin: $e');
            return false;
        }
        #else
        return false;
        #end
    }

    /**
     * Crear una configuración de fondo/overlay con valores por defecto.
     * alpha=1.0 para fondos, 0.8 para overlays (ajustar después si hace falta).
     */
    public static function createBackgroundConfig(name:String, fileName:String, ?alpha:Float = 1.0):BackgroundConfig {
        return {
            name: name,
            fileName: fileName,
            x: 0.0,
            y: 0.0,
            scaleX: 1.0,
            scaleY: 1.0,
            alpha: alpha,
            blendMode: 'normal'
        };
    }
}
