package funkin.states;

import lime.app.Promise;
import lime.app.Future;
import flixel.FlxG;
import flixel.FlxState;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.math.FlxMath;
import flixel.math.FlxRect;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import funkin.gameplay.PlayState;
import funkin.transitions.StateTransition;
import funkin.scripting.StateScriptHandler;
import openfl.utils.Assets;
import lime.utils.Assets as LimeAssets;
import lime.utils.AssetLibrary;
import lime.utils.AssetManifest;
import haxe.io.Path;
#if sys
import sys.FileSystem;
import sys.io.File;
import openfl.display.BitmapData;
import openfl.media.Sound;
#end

using StringTools;

import Paths;

class LoadingState extends funkin.states.MusicBeatState {
	// ── Tiempo mínimo en pantalla ────────────────────────────────────────────
	inline static var MIN_TIME:Float = 1.0;

	// ── Colores UI procedural ────────────────────────────────────────────────
	inline static var COLOR_BG:Int = 0xFF0D0D0D;
	inline static var COLOR_PANEL:Int = 0xFF1A1A2E;
	inline static var COLOR_TRACK:Int = 0xFF16213E;
	inline static var COLOR_START:Int = 0xFFAF66CE;
	inline static var COLOR_MID:Int = 0xFFFF78BF;
	inline static var COLOR_END:Int = 0xFF00FF99;

	// ── Dimensiones panel ────────────────────────────────────────────────────
	inline static var PANEL_W:Float = 560.0;
	inline static var PANEL_H:Float = 140.0;
	inline static var BAR_H:Float = 22.0;
	inline static var BAR_PADDING:Float = 5.0;

	// ─────────────────────────────────────────────────────────────────────────
	var target:FlxState;
	var stopMusic:Bool;
	var callbacks:MultiCallback;

	// ── Estado ───────────────────────────────────────────────────────────────
	var loadProgress:Float = 0.0;
	var visualProgress:Float = 0.0;
	var totalTime:Float = 0.0;

	// Guard para evitar que callbacks async de imagen disparen tras destroy()
	var _bitmapAlive:Bool = true;

	/** Nombre de la canción actual, expuesto a HScript. */
	public var songName(get, never):String;
	inline function get_songName():String
		return (PlayState.SONG != null && PlayState.SONG.song != null) ? PlayState.SONG.song : "";

	// ─────────────────────────────────────────────────────────────────────────

	function new(target:FlxState, stopMusic:Bool) {
		super();
		this.target = target;
		this.stopMusic = stopMusic;
	}

	override function create() {
		super.create();
		FlxG.camera.bgColor = COLOR_BG;

		#if HSCRIPT_ALLOWED
		StateScriptHandler.init();
		StateScriptHandler.loadStateScripts('LoadingState', this);
		StateScriptHandler.callOnScripts('onCreate', []);
		#end

		callbacks = new MultiCallback(onLoad);
		var introComplete = callbacks.add("introComplete");

		checkLoadSong(getSongPath());
		if (PlayState.SONG != null && PlayState.SONG.needsVoices)
			checkLoadSong(getVocalPath());

		_precacheChartEvents();

		new FlxTimer().start(MIN_TIME, function(_) introComplete());

		#if HSCRIPT_ALLOWED
		StateScriptHandler.refreshStateFields(this);
		StateScriptHandler.callOnScripts('postCreate', []);
		#end
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Carga de imagen desde filesystem en hilo separado (no bloquea el render)
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Método público de instancia expuesto a HScript.
	 * En plataformas sys carga la imagen desde disco; en las demás llama cb(null).
	 */
	public function tryLoadBitmap(id:String, cb:BitmapData->Void):Void {
		#if sys
		// Envuelve el callback: si el estado ya fue destruido cuando el hilo async
		// termina, no tocamos el contexto HScript (que ya fue limpiado).
		_tryLoadBitmapAsync(id, function(bmp) {
			if (_bitmapAlive) cb(bmp);
		});
		#else
		cb(null);
		#end
	}

	#if sys
	/**
	 * Busca la imagen <id> en las rutas de assets comunes y la carga
	 * en un hilo separado. El callback llega al hilo principal vía ENTER_FRAME.
	 */
	static function _tryLoadBitmapAsync(id:String, cb:BitmapData->Void):Void {
		var candidates:Array<String> = [];
		for (ext in ['png', 'jpg', 'jpeg']) {
			var resolved = Paths.resolve('images/$id.$ext');
			if (resolved != null && resolved != '')
				candidates.push(resolved);
			candidates.push('assets/images/$id.$ext');
			candidates.push('assets/shared/images/$id.$ext');
			candidates.push('assets/preload/images/$id.$ext');
		}

		#if (cpp || hl)
		sys.thread.Thread.create(function() {
			var bmp:BitmapData = null;
			for (c in candidates) {
				if (!FileSystem.exists(c))
					continue;
				try {
					bmp = BitmapData.fromFile(c);
				} catch (_:Dynamic) {}
				if (bmp != null) {
					trace('[LoadingState] Imagen OK (async): $c');
					break;
				}
			}
			var stage = openfl.Lib.current.stage;
			var listener:openfl.events.Event->Void = null;
			listener = function(_) {
				stage.removeEventListener(openfl.events.Event.ENTER_FRAME, listener);
				cb(bmp);
			};
			stage.addEventListener(openfl.events.Event.ENTER_FRAME, listener);
		});
		#else
		var bmp:BitmapData = null;
		for (c in candidates) {
			if (!FileSystem.exists(c))
				continue;
			try {
				bmp = BitmapData.fromFile(c);
			} catch (_:Dynamic) {}
			if (bmp != null)
				break;
		}
		cb(bmp);
		#end
	}
	#end

	// ─────────────────────────────────────────────────────────────────────────
	//  Precacheo de eventos del chart
	// ─────────────────────────────────────────────────────────────────────────

	function _precacheChartEvents():Void {
		final songData = PlayState.SONG;
		if (songData == null)
			return;

		funkin.scripting.ScriptHandler.init();
		funkin.scripting.ScriptHandler.loadSongScripts(songData.song);

		var dispatched = 0;

		if (songData.events != null && songData.events.length > 0) {
			for (evt in songData.events) {
				var v1 = evt.value != null ? evt.value : '';
				var v2 = '';
				if (v1.contains('|')) {
					final idx = v1.indexOf('|');
					final rest = v1.substring(idx + 1);
					if (!rest.contains('|')) {
						v2 = rest.trim();
						v1 = v1.substring(0, idx).trim();
					}
				}
				final ms:Float = funkin.scripting.events.EventManager.stepToMs(evt.stepTime, songData.bpm);
				funkin.scripting.ScriptHandler.callOnScripts('onEventPushed', [evt.type, v1, v2, ms]);
				dispatched++;
			}
		} else if (songData.notes != null) {
			for (section in songData.notes) {
				if (section.sectionNotes == null)
					continue;
				for (note in section.sectionNotes) {
					if (note.length < 5 || note[4] == null || Std.string(note[4]) == '')
						continue;
					final evtName:String = Std.string(note[4]);
					final ev1:String = note.length >= 6 ? Std.string(note[5]) : '';
					final ev2:String = note.length >= 7 ? Std.string(note[6]) : '';
					final evMs:Float = cast(note[0], Float);
					funkin.scripting.ScriptHandler.callOnScripts('onEventPushed', [evtName, ev1, ev2, evMs]);
					dispatched++;
				}
			}
		}
		trace('[LoadingState] onEventPushed: $dispatched eventos para "${songData.song}".');
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Update
	// ─────────────────────────────────────────────────────────────────────────

	override function update(elapsed:Float) {
		super.update(elapsed);

		totalTime += elapsed;

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onUpdate', [elapsed]);
		#end

		if (callbacks != null && callbacks.length > 0)
			loadProgress = (callbacks.length - callbacks.numRemaining) / callbacks.length;

		visualProgress = FlxMath.lerp(visualProgress, loadProgress, Math.min(elapsed * 9.0, 1.0));
		if (Math.abs(visualProgress - loadProgress) < 0.001)
			visualProgress = loadProgress;

		#if debug
		if (FlxG.keys.justPressed.SPACE && callbacks != null)
			trace('fired: ' + callbacks.getFired() + " unfired:" + callbacks.getUnfired());
		#end

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onUpdatePost', [elapsed]);
		#end
	}

	inline function _barColor(t:Float):FlxColor {
		return t <= 0.5 ? FlxColor.interpolate(COLOR_START, COLOR_MID, t * 2.0) : FlxColor.interpolate(COLOR_MID, COLOR_END, (t - 0.5) * 2.0);
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Filesystem helpers (solo en plataformas #if sys)
	// ─────────────────────────────────────────────────────────────────────────
	#if sys
	static var _libraryDirCache:Map<String, String> = new Map();

	static function getLibraryDir(library:String):String {
		var cached = _libraryDirCache.get(library);
		if (cached != null)
			return cached;
		var candidates = [
			Paths.resolve('$library/'),
			Paths.resolve('data/$library/'),
			Paths.resolve('images/$library/'),
		];
		for (c in candidates)
			if (c != null && FileSystem.exists(c) && FileSystem.isDirectory(c)) {
				_libraryDirCache.set(library, c);
				return c;
			}
		var fallback = Paths.resolve('$library/');
		if (fallback == null)
			fallback = '$library/';
		_libraryDirCache.set(library, fallback);
		return fallback;
	}

	static function scanDirForEntries(rootDir:String, currentDir:String, known:Map<String, Bool>, out:Array<Dynamic>):Void {
		if (!FileSystem.exists(currentDir) || !FileSystem.isDirectory(currentDir))
			return;
		for (entry in FileSystem.readDirectory(currentDir)) {
			var fullPath = currentDir + entry;
			if (FileSystem.isDirectory(fullPath)) {
				scanDirForEntries(rootDir, fullPath + "/", known, out);
				continue;
			}
			var relativePath = fullPath.substring(rootDir.length);
			var assetId = Path.withoutExtension(relativePath);
			if (known.exists(assetId))
				continue;
			var ext = Path.extension(entry).toLowerCase();
			var assetType = switch (ext) {
				case "ogg" | "mp3": cast lime.utils.AssetType.MUSIC;
				case "wav": cast lime.utils.AssetType.SOUND;
				case "png" | "jpg" | "jpeg": cast lime.utils.AssetType.IMAGE;
				case "json" | "xml" | "txt" | "csv" | "hx": cast lime.utils.AssetType.TEXT;
				case "ttf" | "otf": cast lime.utils.AssetType.FONT;
				case _: cast lime.utils.AssetType.BINARY;
			};
			out.push({id: assetId, path: relativePath, type: assetType});
		}
	}

	static function buildAndRegisterLibraryFromFs(libraryId:String, dir:String):Bool {
		if (!FileSystem.exists(dir) || !FileSystem.isDirectory(dir))
			return false;
		var entries:Array<Dynamic> = [];
		scanDirForEntries(dir, dir, new Map<String, Bool>(), entries);
		if (entries.length == 0)
			return false;
		var manifest = new AssetManifest();
		manifest.name = libraryId;
		manifest.rootPath = dir;
		for (e in entries)
			manifest.assets.push(e);
		var lib = AssetLibrary.fromManifest(manifest);
		if (lib == null)
			return false;
		@:privateAccess LimeAssets.libraries.set(libraryId, lib);
		lib.onChange.add(LimeAssets.onChange.dispatch);
		trace('[LoadingState] Librería "$libraryId" desde fs: $dir (${entries.length} assets)');
		return true;
	}

	/**
	 * Localiza el archivo de audio en disco probando extensiones comunes.
	 * Soporta formato "library:path/relativo".
	 */
	static function resolveSoundFsPath(assetId:String):Null<String> {
		var libId = "songs";
		var relative = assetId;
		if (assetId.contains(":")) {
			var sep = assetId.indexOf(":");
			libId = assetId.substring(0, sep);
			relative = assetId.substring(sep + 1);
		}
		var dir = getLibraryDir(libId);
		for (ext in ["ogg", "mp3", "wav"]) {
			var candidate = dir + relative + "." + ext;
			if (FileSystem.exists(candidate))
				return candidate;
		}
		return null;
	}
	#end // sys

	// ─────────────────────────────────────────────────────────────────────────
	//  Carga de audio — 100% filesystem, sin tocar el manifiesto
	// ─────────────────────────────────────────────────────────────────────────

	function checkLoadSong(path:String) {
		// Ya en caché → nada que hacer (no añadimos callback).
		if (Assets.cache.hasSound(path))
			return;

		var callback = callbacks.add("song:" + path);

		#if sys
		var fsPath = resolveSoundFsPath(path);

		if (fsPath != null) {
			// ── Carga en hilo de fondo (cpp/hl) ─────────────────────────────
			#if (cpp || hl)
			sys.thread.Thread.create(function() {
				var sound:Sound = null;
				try {
					sound = Sound.fromFile(fsPath);
				} catch (e:Dynamic) {
					trace('[LoadingState] Error cargando audio (async) $fsPath: $e');
				}
				// Volver al hilo principal vía ENTER_FRAME one-shot
				var stage = openfl.Lib.current.stage;
				var listener:openfl.events.Event->Void = null;
				listener = function(_) {
					stage.removeEventListener(openfl.events.Event.ENTER_FRAME, listener);
					if (sound != null) {
						Assets.cache.setSound(path, sound);
						trace('[LoadingState] Audio listo (async fs): $fsPath');
					} else {
						trace('[LoadingState] Audio no disponible: $fsPath — continuando.');
					}
					callback(); // siempre desbloquear el MultiCallback
				};
				stage.addEventListener(openfl.events.Event.ENTER_FRAME, listener);
			});
			return;
			#else
			// ── Carga síncrona (targets sin hilos) ───────────────────────────
			try {
				var sound = Sound.fromFile(fsPath);
				if (sound != null) {
					Assets.cache.setSound(path, sound);
					trace('[LoadingState] Audio listo (sync fs): $fsPath');
					callback();
					return;
				}
			} catch (e:Dynamic) {
				trace('[LoadingState] Error síncrono cargando $fsPath: $e');
			}
			// Falló la carga directa → desbloquear igualmente
			callback();
			return;
			#end
		}

		// ── No encontrado en disco → fallback a Assets ───────────────────────
		trace('[LoadingState] "$path" no encontrado en disco, intentando Assets.loadSound...');
		Assets.loadSound(path).onComplete(function(_) {
			callback();
		}).onError(function(e) {
			trace('[LoadingState] Assets.loadSound también falló para "$path": $e — continuando.');
			callback(); // nunca dejar el MultiCallback colgado
		});
		#else
		// ── Plataformas no-sys: solo Assets ─────────────────────────────────
		Assets.loadSound(path).onComplete(function(_) {
			callback();
		}).onError(function(e) {
			trace('[LoadingState] Assets.loadSound falló para "$path": $e — continuando.');
			callback();
		});
		#end
	}

	function checkLibrary(library:String) {
		trace(Assets.hasLibrary(library));
		if (Assets.getLibrary(library) == null) {
			@:privateAccess
			var inPaths = LimeAssets.libraryPaths.exists(library);
			if (!inPaths) {
				#if sys
				var dir = getLibraryDir(library);
				if (buildAndRegisterLibraryFromFs(library, dir))
					return;
				#end
				throw "Missing library: " + library;
			}
			var callback = callbacks.add("library:" + library);
			Assets.loadLibrary(library).onComplete(function(_) {
				callback();
			}).onError(function(e) {
				trace('[LoadingState] Error cargando librería "$library": $e — continuando.');
				callback();
			});
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  onLoad — todo cargado, cambiar de estado
	// ─────────────────────────────────────────────────────────────────────────

	function onLoad() {
		if (stopMusic && FlxG.sound.music != null)
			FlxG.sound.music.stop();

		StateScriptHandler.callOnScripts('onLoadComplete', []);

		#if (android || mobileC || ios)
		new FlxTimer().start(0.45, function(_) StateTransition.switchState(target));
		#else
		new FlxTimer().start(0.20, function(_) StateTransition.switchState(target));
		#end
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  API estática pública
	// ─────────────────────────────────────────────────────────────────────────

	static function getSongPath()
		return Paths.inst(PlayState.SONG.song);

	static function getVocalPath()
		return Paths.voices(PlayState.SONG.song);

	inline static public function loadAndSwitchState(target:FlxState, stopMusic = false) {
		StateTransition.switchState(getNextState(target, stopMusic));
	}

	static function getNextState(target:FlxState, stopMusic = false):FlxState {
		#if NO_PRELOAD_ALL
		if (PlayState.SONG != null) {
			var loaded = isSoundLoaded(getSongPath()) && (!PlayState.SONG.needsVoices || isSoundLoaded(getVocalPath()));
			if (!loaded)
				return new LoadingState(target, stopMusic);
		}
		#end
		if (stopMusic && FlxG.sound.music != null)
			FlxG.sound.music.stop();
		return target;
	}

	#if NO_PRELOAD_ALL
	static function isSoundLoaded(path:String):Bool
		return Assets.cache.hasSound(path);

	static function isLibraryLoaded(library:String):Bool
		return Assets.getLibrary(library) != null;
	#end

	override function destroy() {
		_bitmapAlive = false; // cancela callbacks async pendientes
		// NOTE: Paths.clearUnusedMemory() fue eliminado de aquí.
		// FunkinCache ya limpia los assets en preStateSwitch/postStateSwitch.
		// Llamarlo desde destroy() borraba gráficos con useCount==0 ANTES de
		// que PlayState hiciese su create(), provocando que los iconos de salud
		// y otros assets cacheados por FreeplayState desaparecieran justo cuando
		// PlayState los necesitaba — el bug solo se daba desde Freeplay porque
		// StoryMenu tiene un ciclo de assets distinto.
		super.destroy();
		callbacks = null;
		#if sys _libraryDirCache.clear(); #end

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onDestroy', []);
		StateScriptHandler.clearStateScripts();
		#end
	}
}

// ═════════════════════════════════════════════════════════════════════════════
//  MultiCallback
// ═════════════════════════════════════════════════════════════════════════════

class MultiCallback {
	public var callback:Void->Void;
	public var logId:String = null;
	public var length(default, null) = 0;
	public var numRemaining(default, null) = 0;

	var unfired = new Map<String, Void->Void>();
	var fired = new Array<String>();

	public function new(callback:Void->Void, logId:String = null) {
		this.callback = callback;
		this.logId = logId;
	}

	public function add(id = "untitled") {
		id = '$length:$id';
		length++;
		numRemaining++;
		var func:Void->Void = null;
		func = function() {
			if (unfired.exists(id)) {
				unfired.remove(id);
				fired.push(id);
				numRemaining--;
				if (logId != null)
					log('fired $id, $numRemaining remaining');
				if (numRemaining == 0) {
					if (logId != null)
						log('all callbacks fired');
					callback();
				}
			} else
				log('already fired $id');
		};
		unfired[id] = func;
		return func;
	}

	inline function log(msg):Void {
		if (logId != null)
			trace('$logId: $msg');
	}

	public function getFired()
		return fired.copy();

	public function getUnfired()
		return [for (id in unfired.keys()) id];
}
