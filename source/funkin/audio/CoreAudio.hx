package funkin.audio;

import flixel.FlxBasic;
import flixel.FlxG;
import flixel.sound.FlxSound;
import flixel.util.FlxSignal.FlxTypedSignal;

using StringTools;
/**
 * CoreAudio — API de audio totalmente independiente de FlxG.sound.
 *
 * ─── Por qué ─────────────────────────────────────────────────────────────────
 * FlxG.sound.volume / FlxG.sound.muted son irrecuperablemente rotos:
 *   • set_volume itera FlxG.sound.list, pero music está en defaultMusicGroup.
 *   • set_muted no dispara onVolumeChange, así que cualquier listener que
 *     dependa de esa señal nunca se entera del mute.
 *   • FlxSoundGroup multiplica volumenes de forma que un sound en dos grupos
 *     puede recibir el cambio dos veces o ninguna.
 *
 * ─── Solución ────────────────────────────────────────────────────────────────
 * CoreAudio gestiona su propio `masterVolume` y `muted`. El volumen se aplica
 * en dos capas:
 *
 *   1. FlxG.sound.volume = masterVolume
 *      → Flixel aplica esto a TODOS los sounds (SFX, UI, menú) vía
 *        updateTransform() automáticamente.
 *
 *   2. _applyTo(snd): snd.volume = baseVolume
 *      → Solo para música/vocales (en defaultMusicGroup, fuera de list).
 *        El volumen efectivo final es:
 *          transform = FlxG.sound.volume × group.volume × snd._volume
 *                    = masterVolume × 1.0 × baseVolume
 *
 * ANTES (bug): FlxG.sound.volume se fijaba a 1.0 siempre → todos los sounds
 * fuera del registry (SFX, UI) sonaban al máximo ignorando masterVolume.
 *
 * ─── Uso básico ───────────────────────────────────────────────────────────────
 *
 *   // Main.setupGame():
 *   CoreAudio.initialize();
 *
 *   // PlayState.generateSong():
 *   CoreAudio.setInst(instSound);                 // registra instrumental
 *   CoreAudio.addVocal('bf', bfSound);            // registra vocal
 *
 *   // PlayState.startSong():
 *   CoreAudio.playAll();
 *
 *   // resyncVocals():
 *   CoreAudio.resync();
 *
 *   // PlayState.destroy():
 *   CoreAudio.stopAll();
 *
 *   // SoundTray / VolumePlugin:
 *   CoreAudio.setMasterVolume(0.7);
 *   CoreAudio.setMuted(true);
 *   CoreAudio.masterVolume   // → Float
 *   CoreAudio.muted          // → Bool
 */
class CoreAudio extends FlxBasic
{
	// ── Singleton ─────────────────────────────────────────────────────────────

	private static var _self:Null<CoreAudio> = null;

	/** Registra CoreAudio como plugin de Flixel. Llamar UNA VEZ en Main.setupGame(). */
	public static function initialize():Void
	{
		if (_self != null) return;
		// Cargar el volumen guardado ANTES de sincronizar FlxG.sound.volume,
		// para que masterVolume ya tenga el valor correcto desde el primer frame.
		loadVolume();
		// Sincronizar FlxG.sound.volume con masterVolume para que TODOS los
		// sonidos (SFX, UI, música de menú) respeten el volumen maestro.
		// Flixel aplica FlxG.sound.volume como multiplicador global a cada
		// FlxSound.updateTransform(), por lo que basta con mantenerlo en sync.
		FlxG.sound.volume = muted ? 0.0 : masterVolume;
		FlxG.sound.muted  = false;
		// Vaciar las teclas de volumen por defecto de Flixel (ya las gestiona
		// VolumePlugin / SoundTray con CoreAudio).
		FlxG.sound.volumeUpKeys   = [];
		FlxG.sound.volumeDownKeys = [];
		FlxG.sound.muteKeys       = [];

		_self = new CoreAudio();
		FlxG.plugins.addPlugin(_self);
		trace('[CoreAudio] Inicializado. masterVolume=${masterVolume} muted=${muted}.');
	}

	// ── Volumen maestro (independiente de FlxG.sound) ─────────────────────────

	/** Volumen maestro (0.0–1.0). Afecta a todos los sounds registrados. */
	public static var masterVolume(default, null):Float = 1.0;

	/** Estado de mute maestro. */
	public static var muted(default, null):Bool = false;

	/**
	 * Cambia el volumen maestro y lo aplica inmediatamente a todos los sounds.
	 * @param v  Volumen (0.0–1.0). Se redondea a 1 decimal para evitar float drift.
	 */
	public static function setMasterVolume(v:Float):Void
	{
		masterVolume = Math.round(Math.max(0.0, Math.min(1.0, v)) * 10) / 10;
		// Auto-mute implícito cuando el volumen llega a 0 (bajando con '-').
		// Sin esto, SoundTray.isMuted y CoreAudio.muted quedan desincronizados
		// → la tecla 0 deja de funcionar correctamente.
		if (masterVolume <= 0 && !muted)
		{
			muted = true;
			// NO tocar _explicitMute: esto es mute por volumen, no por toggle.
		}
		// Auto-unmute cuando se sube desde 0 (solo si no era mute explícito).
		else if (masterVolume > 0 && muted && !_explicitMute)
		{
			muted = false;
		}
		FlxG.sound.volume = muted ? 0.0 : masterVolume;
		FlxG.sound.muted  = false;
		_applyAll();
		if (_sig != null) _sig.dispatch(muted ? 0.0 : masterVolume);
	}

	/**
	 * Activa o desactiva el mute maestro.
	 * @param m  true = silencio total, false = restaurar volumen.
	 */
	public static function setMuted(m:Bool):Void
	{
		_explicitMute = m;
		muted = m;
		// Sincronizar FlxG.sound.volume → SFX/UI en FlxG.sound.list
		FlxG.sound.volume = muted ? 0.0 : masterVolume;
		FlxG.sound.muted  = false;
		// Sincronizar sounds registrados (música/vocales en defaultMusicGroup
		// que NO reciben el update de FlxG.sound.volume automáticamente).
		_applyAll();
		if (_sig != null) _sig.dispatch(muted ? 0.0 : masterVolume);
	}

	/** Alterna mute. Devuelve el nuevo estado. */
	public static function toggleMute():Bool
	{
		setMuted(!muted);
		return muted;
	}

	/** Volumen efectivo actual (0.0 si muted). */
	public static var effectiveVolume(get, never):Float;
	private static inline function get_effectiveVolume():Float
		return muted ? 0.0 : masterVolume;

	// ── Señal pública ─────────────────────────────────────────────────────────

	/** Se dispara en cada cambio de volumen/mute. Valor = volumen efectivo. */
	public static var onVolumeChanged(get, never):FlxTypedSignal<Float->Void>;
	private static var _sig:Null<FlxTypedSignal<Float->Void>> = null;
	private static inline function get_onVolumeChanged():FlxTypedSignal<Float->Void>
	{
		if (_sig == null) _sig = new FlxTypedSignal<Float->Void>();
		return _sig;
	}

	// ── Estado de gameplay ────────────────────────────────────────────────────

	/** Instrumental activo (null si no hay canción). */
	public static var inst(default, null):Null<FlxSound> = null;

	/** Vocales por nombre de personaje. */
	public static var vocals(default, null):Map<String, FlxSound> = [];

	// ── Estado de menú ────────────────────────────────────────────────────────

	/** Track de menú activa. '' si no hay. */
	public static var menuTrack(default, null):String = '';

	/**
	 * Nombre de la track de menú que fue interrumpida por un preview.
	 * Se restaura cuando el preview termina y esa misma track vuelve a pedirse.
	 */
	private static var _savedMenuTrack:String   = '';
	/** Posición (ms) de la música de menú cuando fue interrumpida por un preview. */
	private static var _savedMenuPosition:Float = 0.0;

	// ── Registro interno de sounds + baseVolume ───────────────────────────────

	/**
	 * Todos los FlxSounds registrados → su baseVolume (0.0–1.0).
	 * El volumen efectivo que se aplica a cada uno es:
	 *   snd.volume = muted ? 0 : masterVolume × baseVolume
	 */
	private static var _registry:Map<FlxSound, Float> = [];

	/** true si el mute fue activado explícitamente por toggleMute/setMuted(true). */
	private static var _explicitMute:Bool = false;

	// ── Constructor ───────────────────────────────────────────────────────────

	private function new()
	{
		super();
	}

	// ══════════════════════════════════════════════════════════════════════════
	// API — Registro de sounds
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Registra un FlxSound para que CoreAudio gestione su volumen.
	 * @param snd        El sound a registrar.
	 * @param baseVolume Volumen local deseado (0.0–1.0). Default: 1.0.
	 */
	public static function register(snd:FlxSound, baseVolume:Float = 1.0):Void
	{
		if (snd == null) return;
		_registry.set(snd, Math.max(0, Math.min(1, baseVolume)));
		_applyTo(snd);
	}

	/** Elimina un FlxSound del registro. */
	public static function unregister(snd:FlxSound):Void
	{
		if (snd == null) return;
		_registry.remove(snd);
	}

	/** Cambia el baseVolume de un sound ya registrado y lo aplica. */
	public static function setBaseVolume(snd:FlxSound, baseVolume:Float):Void
	{
		if (snd == null || !_registry.exists(snd)) return;
		_registry.set(snd, Math.max(0, Math.min(1, baseVolume)));
		_applyTo(snd);
	}

	/** Devuelve el baseVolume de un sound registrado (1.0 si no está en el registry). */
	public static function getBaseVolume(snd:FlxSound):Float
	{
		if (snd == null) return 0.0;
		return _registry.exists(snd) ? _registry.get(snd) : 1.0;
	}

	// ══════════════════════════════════════════════════════════════════════════
	// API — Gameplay (instrumental + vocales)
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Registra el instrumental de la canción.
	 * Asigna el sound a FlxG.sound.music (Flixel lo gestiona fuera de la list).
	 * NO lo añade a FlxG.sound.list para evitar que Flixel lo procese dos veces.
	 * @param snd  FlxSound cargado y pausado (null → no-op).
	 */
	public static function setInst(snd:Null<FlxSound>):Void
	{
		_unregisterInst();
		if (snd == null) return;

		inst = snd;
		FlxG.sound.music = snd;
		register(snd, 1.0); // baseVolume 1.0 — _applyTo lo pondrá a masterVolume×1.0
	}

	/**
	 * Añade un track de vocales.
	 * @param key  Nombre del personaje ('bf', 'dad', etc.)
	 * @param snd  FlxSound cargado y pausado.
	 */
	public static function addVocal(key:String, snd:Null<FlxSound>):Void
	{
		if (snd == null) return;
		removeVocal(key);
		vocals.set(key, snd);
		_ensureInList(snd);
		register(snd, 1.0); // baseVolume 1.0 — PlayState no necesita sobreescribir .volume
	}

	/** Elimina y desregistra un vocal por clave. */
	public static function removeVocal(key:String):Void
	{
		final snd = vocals.get(key);
		if (snd == null) return;
		if (snd.alive) snd.stop();   // guarda contra FlxSounds ya destruidos
		unregister(snd);
		FlxG.sound.list.remove(snd, false);
		vocals.remove(key);
	}

	/** Elimina y desregistra todos los vocales. */
	public static function clearVocals():Void
	{
		for (_ => snd in vocals)
		{
			if (snd == null) continue;
			if (snd.alive) snd.stop();
			unregister(snd);
			FlxG.sound.list.remove(snd, false);
		}
		vocals.clear();
	}

	/**
	 * Limpia todo el estado de audio antes de cambiar de mod.
	 * Detiene y desregistra el inst, las voces y todos los sonidos registrados.
	 * Llamar justo antes de hacer switchState/resetGame al cambiar de mod.
	 */
	public static function flushForModSwitch():Void
	{
		// Parar y limpiar inst
		_unregisterInst();

		// Parar y limpiar voces
		clearVocals();

		// Parar música de menú
		_stopMenuInternal();
		menuTrack          = '';
		_savedMenuTrack    = '';
		_savedMenuPosition = 0.0;

		// Vaciar el registry — cualquier FlxSound que siga ahí es de la sesión anterior
		for (snd => _ in _registry)
		{
			try { if (snd != null && snd.alive) snd.stop(); } catch (_) {}
		}
		_registry.clear();
	}

	/** Inicia el instrumental al volumen maestro actual. */
	public static function playInst():Void
	{
		if (inst == null) return;
		setBaseVolume(inst, 1.0);
		_applyTo(inst);
		_play(inst);
	}

	/** Inicia todos los vocales. */
	public static function playVocals():Void
	{
		for (_ => snd in vocals)
		{
			if (snd == null) continue;
			setBaseVolume(snd, 1.0);
			_applyTo(snd);
			_play(snd);
		}
	}

	/** Inicia instrumental + vocales. */
	public static function playAll():Void
	{
		playInst();
		playVocals();
	}

	/** Pausa instrumental + vocales. */
	public static function pauseAll():Void
	{
		if (inst != null) inst.pause();
		for (_ => snd in vocals) if (snd != null) snd.pause();
	}

	/** Reanuda instrumental + vocales sin reinicializar el backend. */
	public static function resumeAll():Void
	{
		if (inst != null && !inst.playing) inst.resume();
		for (_ => snd in vocals) if (snd != null && !snd.playing) snd.resume();
	}

	/**
	 * Restaura el estado completo de audio al volver la app a primer plano.
	 * Llamar desde Main._onMobileActivate() justo después del ACTIVATE event.
	 *
	 * ¿Por qué hace falta?
	 * ─────────────────────
	 * En Android/iOS el sistema puede suspender o destruir el contexto OpenAL
	 * mientras la app está en segundo plano.  Cuando el OS dispara ACTIVATE:
	 *
	 *  1. Flixel reanuda FlxG.sound.list (SFX, vocales) vía onFocus().
	 *  2. Flixel reanuda FlxG.sound.music (inst) directamente.
	 *  3. PERO FlxG.sound.volume puede haber sido reseteado a 1.0 por el driver
	 *     o por algún reset interno de Lime, ignorando nuestro masterVolume.
	 *  4. En algunos dispositivos el resume() de Flixel llega antes de que el
	 *     contexto OpenAL esté del todo listo → los sounds quedan silenciosos.
	 *
	 * Este método corrige los puntos 3 y 4: re-propaga masterVolume a Flixel,
	 * re-aplica baseVolumes a todos los sounds registrados y, como fallback,
	 * intenta reanudar la música de menú e inst/vocales si siguen pausados.
	 */
	public static function onMobileResume():Void
	{
		// ── 1. Re-sincronizar FlxG.sound.volume con masterVolume ─────────────
		// Algunos drivers Android resetean FlxG.sound.volume a 1.0 al recrear
		// el contexto OpenAL, ignorando lo que pusimos antes del background.
		FlxG.sound.volume = muted ? 0.0 : masterVolume;
		FlxG.sound.muted  = false;

		// ── 2. Re-aplicar baseVolumes a todos los sounds registrados ─────────
		// _applyTo() llama updateTransform() directamente → fuerza que el
		// backend OpenAL reciba el valor correcto sin esperar al next frame.
		_applyAll();

		// ── 3. Fallback: reanudar música de menú ─────────────────────────────
		// Flixel reanuda FlxG.sound.music vía onFocus(), pero en algunos
		// dispositivos el resume() llega antes de que el contexto OpenAL esté
		// listo → el sound queda en pausa silenciosa.  Reintentamos aquí.
		if (menuTrack != '' && FlxG.sound.music != null && !FlxG.sound.music.playing)
		{
			try { FlxG.sound.music.resume(); } catch (_:Dynamic) {}
		}

		// ── 4. Fallback: reanudar inst + vocales ─────────────────────────────
		// Flixel reanuda FlxG.sound.list (donde están las vocales) en onFocus().
		// resumeAll() añade un segundo intento por si el primero llegó demasiado
		// pronto (race condition contexto OpenAL en Android Vulkan / algunos ARM).
		resumeAll();
	}

	/**
	 * Resync: ajusta el tiempo de vocales al del instrumental.
	 * Usa pause()+time+resume() → CERO FPS drop (no reinicia el backend).
	 */
	public static function resync():Void
	{
		if (inst == null) return;
		if (!inst.playing) inst.resume();
		final t:Float = inst.time;
		funkin.data.Conductor.songPosition = t;
		for (_ => snd in vocals)
		{
			if (snd == null) continue;
			final was = snd.playing;
			snd.pause();
			snd.time = t;
			if (was) snd.resume();
		}
	}

	/** Mueve todos los sounds a un timestamp. */
	public static function syncTime(ms:Float):Void
	{
		if (inst != null) inst.time = ms;
		for (_ => snd in vocals) if (snd != null) snd.time = ms;
	}

	/** Detiene y desregistra instrumental + vocales. */
	public static function stopAll():Void
	{
		_unregisterInst();
		clearVocals();
	}

	// ── Volumen de gameplay ───────────────────────────────────────────────────

	/** Cambia el baseVolume del instrumental (0.0–1.0). */
	public static function setInstVolume(v:Float):Void
	{
		if (inst != null) setBaseVolume(inst, v);
	}

	/** Cambia el baseVolume de todos los vocales. */
	public static function setVocalsVolume(v:Float):Void
	{
		for (_ => snd in vocals) if (snd != null) setBaseVolume(snd, v);
	}

	// ══════════════════════════════════════════════════════════════════════════
	// API — Menú
	// ══════════════════════════════════════════════════════════════════════════

	/** Reproduce una track de menú. */
	public static function playMenu(track:String, volume:Float = 1.0,
		forceRestart:Bool = false, loop:Bool = true):Void
	{
		if (track == null || track.trim() == '') return;
		if (!forceRestart && menuTrack == track
			&& FlxG.sound.music != null && FlxG.sound.music.playing)
			return;

		// Si la nueva pista es distinta a la guardada, descartar posición salvada.
		if (_savedMenuTrack != track)
		{
			_savedMenuTrack   = '';
			_savedMenuPosition = 0.0;
		}

		_stopMenuInternal();
		menuTrack = track;

		final asset = Paths.loadMusic(track);
		if (asset != null)
			FlxG.sound.playMusic(asset, 1.0, loop);
		else
			FlxG.sound.playMusic(Paths.music(track), 1.0, loop);

		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.persist = true;
			_ensureInList(FlxG.sound.music);
			register(FlxG.sound.music, volume);   // baseVolume = el "volumen de menú"

			// ── Restaurar posición interrumpida por un preview ──────────────
			// Si el jugador abrió un preview y luego volvió a la música de menú,
			// se retoma desde donde estaba en lugar de reiniciar desde 0.
			if (_savedMenuTrack == track && _savedMenuPosition > 0)
			{
				FlxG.sound.music.time = _savedMenuPosition;
				_savedMenuTrack    = '';
				_savedMenuPosition = 0.0;
			}
		}
	}

	/** Igual que playMenu() pero con fade-in. */
	public static function playMenuFade(track:String, targetVolume:Float = 0.7,
		fadeDuration:Float = 4.0, forceRestart:Bool = false):Void
	{
		if (track == null || track.trim() == '') return;
		if (!forceRestart && menuTrack == track
			&& FlxG.sound.music != null && FlxG.sound.music.playing)
			return;

		// Si la nueva pista es distinta a la guardada, descartar posición salvada.
		if (_savedMenuTrack != track)
		{
			_savedMenuTrack   = '';
			_savedMenuPosition = 0.0;
		}

		_stopMenuInternal();
		menuTrack = track;

		final asset = Paths.loadMusic(track);
		if (asset != null) FlxG.sound.playMusic(asset, 1.0);
		else               FlxG.sound.playMusic(Paths.music(track), 1.0);

		if (FlxG.sound.music == null) return;
		FlxG.sound.music.persist = true;
		_ensureInList(FlxG.sound.music);

		// Restaurar posición interrumpida (no tiene sentido hacer fade-in desde 0
		// cuando simplemente volvemos al punto donde dejamos la música).
		if (_savedMenuTrack == track && _savedMenuPosition > 0)
		{
			FlxG.sound.music.time = _savedMenuPosition;
			_savedMenuTrack    = '';
			_savedMenuPosition = 0.0;
		}

		// Registrar con baseVolume=0 y hacer fade manual sobre el baseVolume
		register(FlxG.sound.music, 0.0);
		if (!FlxG.sound.music.playing) FlxG.sound.music.play();

		if (masterVolume <= 0.0 || muted)
		{
			// Volumen global silenciado: poner baseVolume al target directamente
			// para que suene en cuanto el usuario suba el volumen.
			setBaseVolume(FlxG.sound.music, targetVolume);
		}
		else
		{
			// Fade manual: animar el baseVolume de 0 → targetVolume
			_fadeInSound(FlxG.sound.music, targetVolume, fadeDuration);
		}
	}

	/** Para la música de menú. */
	public static function stopMenu():Void
	{
		_stopMenuInternal();
		menuTrack = '';
	}

	/** true si la track de menú indicada está sonando. */
	public static inline function isMenuPlaying(track:String):Bool
		return menuTrack == track && FlxG.sound.music != null && FlxG.sound.music.playing;

	/**
	 * Reproduce un FlxSound ya cargado como música activa (para previews en Freeplay
	 * u otros casos donde el caller ya tiene el FlxSound listo).
	 * Detiene la música anterior, registra el nuevo sound en CoreAudio y lo
	 * añade a FlxG.sound.list para que Flixel lo pause/reanude automáticamente.
	 *
	 * @param snd         FlxSound ya cargado. Si es null, solo para la música anterior.
	 * @param baseVolume  Volumen local (0.0–1.0). El volumen efectivo será masterVolume×baseVolume.
	 * @param loop        Si true, la música hace loop.
	 */
	public static function playPreloadedMusic(snd:Null<FlxSound>, baseVolume:Float = 1.0, loop:Bool = true):Void
	{
		_stopMenuInternal();
		if (snd == null) return;

		menuTrack = '__preview__';
		FlxG.sound.music = snd;
		FlxG.sound.music.persist = true;
		FlxG.sound.music.looped = loop;
		_ensureInList(snd);
		register(snd, baseVolume);
		if (!snd.playing) snd.play();
	}

	// ══════════════════════════════════════════════════════════════════════════
	// play() público — sin FPS drop en targets nativos
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Inicia un FlxSound directamente.
	 * En targets nativos (OpenAL): play() directo, sin tocar stage.frameRate.
	 * En Flash: solo baja FPS la primera vez (warm-up de backend).
	 */
	public static function play(snd:FlxSound):Void
	{
		if (snd == null) return;
		#if flash
		_warmPlayFlash(snd);
		#else
		try snd.play() catch (e:Dynamic) trace('[CoreAudio] play() error: $e');
		#end
	}

	// ══════════════════════════════════════════════════════════════════════════
	// Save / Load del volumen (independiente de FlxG.sound)
	// ══════════════════════════════════════════════════════════════════════════

	/** Guarda masterVolume y muted en FlxG.save. */
	public static function saveVolume():Void
	{
		// Guardamos el volumen REAL (antes del mute) para que al cargar
		// podamos restaurar correctamente aunque estuviera muteado.
		FlxG.save.data.coreVolume  = masterVolume;
		FlxG.save.data.coreMuted   = _explicitMute;
		FlxG.save.flush();
	}

	/** Carga masterVolume y muted desde FlxG.save. */
	public static function loadVolume():Void
	{
		final savedVol:Float = (FlxG.save.data.coreVolume != null)
			? FlxG.save.data.coreVolume : 1.0;
		masterVolume  = Math.max(0, Math.min(1, savedVol));
		_explicitMute = (FlxG.save.data.coreMuted == true);
		muted         = _explicitMute || (masterVolume <= 0.0);
		// No llamar _applyAll() aquí: aún no hay sounds registrados en el boot.
		trace('[CoreAudio] Loaded: vol=${masterVolume} muted=${muted}');
	}

	// ══════════════════════════════════════════════════════════════════════════
	// Internals
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Aplica el volumen a un FlxSound concreto.
	 *
	 * Flixel calcula el volumen efectivo como:
	 *   transform = FlxG.sound.volume × group.volume × snd._volume
	 *
	 * Como ahora FlxG.sound.volume = masterVolume (no 1.0), aquí solo
	 * necesitamos fijar snd._volume = base. El resultado final es:
	 *   transform = masterVolume × 1.0 × base = masterVolume × base  ✓
	 *
	 * Esto se aplica a música y vocales (que no están en FlxG.sound.list
	 * y por tanto no reciben el update de FlxG.sound.volume automáticamente).
	 */
	private static function _applyTo(snd:FlxSound):Void
	{
		if (snd == null) return;
		final base = _registry.exists(snd) ? _registry.get(snd) : 1.0;

		// FIX: doble-volumen en música / mute roto
		// ─────────────────────────────────────────────────────────────────────
		// La música vive en defaultMusicGroup (FlxG.sound.music), que Flixel
		// gestiona con su propio FlxSoundGroup.  El volumen efectivo de
		// cualquier FlxSound se calcula en updateTransform():
		//
		//   effective = FlxG.sound.volume  ← masterVolume (nosotros lo controlamos)
		//             × group.volume       ← 1.0 (defaultMusicGroup sin tocar)
		//             × snd._volume        ← lo que ponemos con snd.volume
		//
		// ANTES: snd.volume = masterVolume × base
		//   → effective = masterVolume × 1.0 × (masterVolume × base)
		//               = masterVolume²  × base   ← DOBLE aplicación
		//   A vol=0.7 la música sonaba a 0.49 en lugar de 0.70.
		//   Con muted=true, FlxG.sound.volume = 0, pero snd.volume
		//   se seteaba a 0 también → al desmutear snd.volume seguía en 0
		//   hasta el siguiente _applyAll() → se oía un frame de silencio
		//   extra y en race conditions la música no arrancaba.
		//
		// AHORA: snd.volume = base  (solo baseVolume, sin masterVolume)
		//   → effective = masterVolume × 1.0 × base   ← correcto
		//   Mute: FlxG.sound.volume = 0 → effective = 0 para todos los sounds
		//   sin necesidad de tocar snd.volume individualmente.
		// ─────────────────────────────────────────────────────────────────────
		if (muted)
			snd.volume = 0.0;  // silencio explícito por si defaultMusicGroup ignora FlxG.sound.volume
		else
			snd.volume = base; // FlxG.sound.volume = masterVolume ya actúa de multiplicador

		// Forzar aplicación inmediata al backend OpenAL/SDL.
		// Sin esto, FlxSound.updateTransform() solo se llama en el próximo frame
		// de audio → hay un delay audible al mutear o bajar el volumen a 0.
		@:privateAccess snd.updateTransform();
	}

	/** Aplica el volumen efectivo a todos los sounds registrados. */
	private static function _applyAll():Void
	{
		for (snd => _ in _registry) _applyTo(snd);
	}

	private static function _unregisterInst():Void
	{
		if (inst == null) return;
		if (inst.alive) inst.stop();
		unregister(inst);
		// El inst vive en FlxG.sound.music, no en FlxG.sound.list — no hay que removarlo de la list.
		if (FlxG.sound.music == inst) FlxG.sound.music = null;
		inst = null;
	}

	private static function _stopMenuInternal():Void
	{
		if (FlxG.sound.music != null)
		{
			// ── Guardar posición de menú si se interrumpe por un preview ─────
			// Así, al volver a la misma track, se retoma desde donde estaba
			// en lugar de reiniciar desde 0 (el "lagazo" al parar preview).
			if (menuTrack != '' && menuTrack != '__preview__')
			{
				_savedMenuTrack    = menuTrack;
				_savedMenuPosition = FlxG.sound.music.time;
			}

			final isPreview = (menuTrack == '__preview__');
			final snd = FlxG.sound.music;
			unregister(snd);
			FlxG.sound.list.remove(snd, false);
			snd.persist = false;
			snd.stop();
			FlxG.sound.music = null;   // evitar referencias fantasma al cambiar state

			// ── Liberar buffer OGG de los previews (evita acumulación RAM) ──
			// Los previews son FlxSounds creados on-demand por FreeplayState
			// con loadEmbedded() — cada canción descomprime el OGG entero en RAM.
			// Sin destroy() explícito el buffer persiste hasta el siguiente GC
			// mayor, pudiendo acumular varios MB por cada canción previsuada.
			if (isPreview)
			{
				try { snd.destroy(); } catch (_:Dynamic) {}
			}
		}
	}

	/** Garantiza que el sound esté en FlxG.sound.list (para pause/resume de Flixel). */
	private static inline function _ensureInList(snd:FlxSound):Void
	{
		if (snd != null && !FlxG.sound.list.members.contains(snd))
			FlxG.sound.list.add(snd);
	}

	/** Llama play() sin manipular FPS (OpenAL no lo necesita). */
	private static inline function _play(snd:FlxSound):Void
	{
		try snd.play() catch (e:Dynamic) trace('[CoreAudio] _play error: $e');
	}

	// ── Fade manual sobre baseVolume (para menú fade-in) ─────────────────────

	private static var _fadeSound:Null<FlxSound>   = null;
	private static var _fadeTarget:Float            = 0.0;
	private static var _fadeDuration:Float          = 1.0;
	private static var _fadeElapsed:Float           = 0.0;

	private static function _fadeInSound(snd:FlxSound, target:Float, duration:Float):Void
	{
		_fadeSound    = snd;
		_fadeTarget   = target;
		_fadeDuration = duration;
		_fadeElapsed  = 0.0;
	}

	private function _tickFade(elapsed:Float):Void
	{
		if (_fadeSound == null) return;
		_fadeElapsed += elapsed;
		final t = Math.min(_fadeElapsed / _fadeDuration, 1.0);
		final cur = _fadeTarget * t;
		setBaseVolume(_fadeSound, cur);
		if (t >= 1.0) _fadeSound = null;
	}

	// ── Flash warm-up (solo en target Flash) ─────────────────────────────────

	#if flash
	private static var _flashWarmed:Bool = false;
	private static function _warmPlayFlash(snd:FlxSound):Void
	{
		if (_flashWarmed) { try snd.play() catch (_:Dynamic) {}; return; }
		final s = openfl.Lib.current.stage;
		final fps = s.frameRate;
		s.frameRate = 20;
		try snd.play() catch (_:Dynamic) {};
		_flashWarmed = true;
		haxe.Timer.delay(function() { s.frameRate = fps; }, 200);
	}
	#end

	// ── Plugin update ─────────────────────────────────────────────────────────

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);
		// Tick de fade-in manual (menú).
		_tickFade(elapsed);
		// Mantener FlxG.sound.volume sincronizado con masterVolume.
		// Algún código externo (FlxGame, addons) podría cambiarlo.
		final expectedVol:Float = muted ? 0.0 : masterVolume;
		if (FlxG.sound.volume != expectedVol) FlxG.sound.volume = expectedVol;
		if (FlxG.sound.muted)                 FlxG.sound.muted  = false;
	}

	override public function destroy():Void
	{
		_self = null;
		_sig  = null;
		super.destroy();
	}
}
