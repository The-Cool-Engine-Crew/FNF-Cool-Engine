package funkin.cache;

import flixel.FlxG;
import openfl.display.BitmapData;
import openfl.media.Sound;
import openfl.text.Font;
import openfl.utils.AssetCache;
import animationdata.FunkinSprite;
import funkin.system.MemoryUtil;
#if lime
import lime.utils.Assets as LimeAssets;
import Paths;
#end

/**
 * FunkinCache v2 — Gestión optimizada del ciclo de vida de assets entre estados.
 *
 * ─── Mejoras v2 ──────────────────────────────────────────────────────────────
 *
 *  RENDIMIENTO
 *    • Batch eviction: clearSecondLayer() acumula las claves a eliminar y hace
 *      una sola pasada (evita re-hashing del Map en cada remove individual).
 *    • Hot path en getBitmapData(): lookup CURRENT primero, cortocircuita
 *      bitmapData2 si no es necesario.
 *    • Contadores O(1) para bitmap/sound/font.
 *
 *  SOPORTE DE MODS
 *    • Fallback mejorado: busca en el directorio del mod activo ANTES del disco.
 *    • markPermanentBitmap / markPermanentSound: assets que nunca se evictan.
 *    • onEvict callback: mods reciben notificación al destruir un asset.
 *
 *  DIAGNÓSTICO
 *    • getStats() devuelve string compacto con contadores en tiempo real.
 *    • dumpKeys() lista todas las claves en caché.
 *
 * ─── Arquitectura (3 capas) ───────────────────────────────────────────────────
 *
 *  PERMANENT  — UI esencial, fonts. Nunca se destruyen.
 *  CURRENT    — Assets sesión activa. Se mueven a SECOND en preStateSwitch.
 *  SECOND     — Assets sesión anterior. Se destruyen en postStateSwitch
 *               salvo que el nuevo estado los "rescate".
 *
 * @author Cool Engine Team
 * @version 2.0.0
 */
class FunkinCache extends AssetCache {
	public static var instance:FunkinCache;

	// ── Capa SECOND ───────────────────────────────────────────────────────────
	@:noCompletion public var bitmapData2:Map<String, BitmapData>;
	@:noCompletion public var font2:Map<String, Font>;
	@:noCompletion public var sound2:Map<String, Sound>;

	// ── Capa PERMANENT ────────────────────────────────────────────────────────
	@:noCompletion var _permanentBitmaps:Map<String, BitmapData> = [];
	@:noCompletion var _permanentSounds:Map<String, Sound> = [];

	// ── Contadores O(1) ───────────────────────────────────────────────────────
	var _bitmapCount:Int = 0;
	var _bitmap2Count:Int = 0;
	var _soundCount:Int = 0;
	var _fontCount:Int = 0;

	// ── Cola de dispose() diferido ────────────────────────────────────────────
	// b.dispose() libera la textura GPU y puede tardar varios milisegundos por
	// bitmap. Hacer todos los disposes del clearSecondLayer() en un solo frame
	// (el primero del nuevo state) provoca la bajada de FPS en cada cambio de
	// state. En su lugar se acumulan aquí y se procesan a razón de
	// _DISPOSE_PER_FRAME por ENTER_FRAME, repartiendo el trabajo en varios frames
	// invisibles mientras el overlay de transición cubre la pantalla.
	var _disposeQueue:Array<BitmapData> = [];
	var _disposeFrameListener:Null<openfl.events.Event->Void> = null;
	static inline final _DISPOSE_PER_FRAME:Int = 20; // texturas liberadas por frame (dobrado para liberar VRAM antes)

	/**
	 * Callback llamado cuando un asset se destruye.
	 * Firma: (key:String, assetType:String) → Void
	 * assetType ∈ { "bitmap", "font", "sound" }
	 */
	public var onEvict:Null<(String, String) -> Void> = null;

	// ── Constructor ────────────────────────────────────────────────────────────
	public function new() {
		super();
		moveToSecondLayer();
		instance = this;
	}

	// ══════════════════════════════════════════════════════════════════════════
	// INIT — señales de Flixel
	// ══════════════════════════════════════════════════════════════════════════

	public static function init():Void {
		openfl.utils.Assets.cache = new FunkinCache();

		// FIX: asignar el path resolver para que PathsCache._loadGraphic (Intento 3)
		// pueda resolver keys con prefijo de librería Lime/OpenFL como
		// "shared:icons/icon-bf.png". Sin esto, el Intento 3 es siempre saltado
		// (pathResolver == null) y los iconos de personaje fallan al cargar cuando
		// el cache está vacío (e.g. primera entrada desde Freeplay → LoadingState →
		// PlayState), mientras que F5 funcionaba porque rescataba de _previousGraphics.
		funkin.cache.PathsCache.pathResolver = Paths.image;

		FlxG.signals.preStateSwitch.add(function() {
			try {
				openfl.system.System.gc();
			} catch (_:Dynamic) {}

			// ── FIX Bug 5: prune stale atlas entries BEFORE rotating layers ────
			// pruneAtlasCache() was only called in postStateSwitch, after
			// clearPreviousGraphics() had already nulled the BitmapData pointers.
			// Running it here first ensures atlases whose FlxGraphic was destroyed
			// by the previous state are evicted before they are moved to SECOND,
			// preventing a full extra cycle of stale entries in RAM.
			try {
				Paths.pruneAtlasCache();
			} catch (_:Dynamic) {}

			// ── FIX Bug 4: clear Character JSON/path caches ───────────────────
			// _dataCache and _pathCache are static Maps that grow indefinitely —
			// one entry per character loaded across all songs in a session. In
			// large mod packs this can accumulate 1-2 MB of JSON strings. The
			// caches are safe to wipe here; they are rebuilt on next access.
			try {
				funkin.gameplay.objects.character.Character.clearCharCaches();
			} catch (_:Dynamic) {}

			// ── FIX Bug 12: clear NoteTypeManager frame cache ─────────────────
			// _frames and _holdFrames hold FlxAtlasFrames that point into
			// BitmapData destroyed by the previous state's clearSecondLayer().
			// After that, _atlasValid() fails and they are reloaded from disk on
			// the next gameplay session — causing a redundant RAM spike. Clearing
			// them here lets the next session start with a clean cache.
			try {
				funkin.gameplay.notes.NoteTypeManager.clearCache();
			} catch (_:Dynamic) {}

			// ── Paso 0b: expulsar FlxGraphics muertos ANTES de rotar ─────────
			// Si el state anterior dejó FlxGraphics con useCount=0 en el pool de
			// Flixel (sprites destruidos pero gráfico aún referenciado), deben
			// eliminarse ANTES de moverlos a SECOND para que clearSecondLayer()
			// no los evalúe ni intente rescatarlos.
			try {
				FlxG.bitmap.clearUnused();
			} catch (_:Dynamic) {}

			try {
				MemoryUtil.collectMinor();
			} catch (_:Dynamic) {}

			// ── Paso 1: rotar capas de assets ─────────────────────────────────
			instance.moveToSecondLayer();
			funkin.cache.PathsCache.instance.rotateSession();
			FunkinSprite.clearAllCaches();

			// ── Paso 2: detener todos los FlxSounds no persistentes ───────────
			// Flixel destruye los sounds de la lista en el switch, pero no cierra
			// el buffer nativo de OpenFL hasta que el GC los recoge (puede tardar
			// varios frames). Llamar stop() explícitamente cierra el canal de audio
			// inmediatamente y evita que los sonidos de menú/gameplay sigan
			// consumiendo buffers PCM durante la transición.
			// persist=true indica que el sound debe sobrevivir el cambio de state
			// (e.g. música de fondo que continúa) — esos se respetan.
			try {
				for (snd in FlxG.sound.list)
					if (snd != null && !snd.persist)
						try {
							snd.stop();
						} catch (_:Dynamic) {}
			} catch (_:Dynamic) {}

			try {
				if (FlxG.sound.music != null && !FlxG.sound.music.persist) {
					FlxG.sound.music.stop();
					try {
						@:privateAccess FlxG.sound.music._sound?.close();
					} catch (_:Dynamic) {}
					FlxG.sound.list.remove(FlxG.sound.music, true);
					FlxG.sound.music = null;
				}
				funkin.audio.MusicManager.invalidate();
			} catch (_:Dynamic) {}

			// ── Paso 3: limpiar capas de scripts de la sesión anterior ────────
			// Red de seguridad: si PlayState.destroy() no llegó a ejecutarse
			// (crash, excepción, resetState mid-frame), las capas de scripts
			// song/stage/char siguen activas y sus callbacks se dispararían en el
			// nuevo state. Limpiarlas aquí garantiza un arranque limpio.
			// globalScripts NO se limpia — son permanentes toda la sesión.
			try {
				funkin.scripting.ScriptHandler.clearSongScripts();
				funkin.scripting.ScriptHandler.clearStageScripts();
				funkin.scripting.ScriptHandler.clearCharScripts();
				funkin.scripting.ScriptHandler.clearMenuScripts();
			} catch (_:Dynamic) {}
		});

		FlxG.signals.postStateSwitch.add(function() {
			// ── FIX Bug 4: disableCount puede desincronizarse ─────────────────
			if (MemoryUtil.disableCount > 0) {
				trace('[FunkinCache] WARN: disableCount=${MemoryUtil.disableCount} al cambiar state — GC forzado a reactivar.');
				@:privateAccess MemoryUtil.disableCount = 0;
				@:privateAccess MemoryUtil._enableGC();
			}

			// ── FASE SÍNCRONA (frame 1 del nuevo state) ───────────────────────
			// clearSecondLayer() toma las decisiones de rescate/eviction y retira
			// todos los assets de los mapas de caché inmediatamente. Los dispose()
			// reales de los bitmaps se encolan en _disposeQueue y se reparten en
			// frames siguientes (_flushDisposeQueue) para NO colapsar el frame 1.
			instance.clearSecondLayer();
			funkin.cache.PathsCache.instance.clearPreviousGraphics();
			funkin.cache.PathsCache.instance.clearPreviousSounds();
			Paths.pruneAtlasCache();
			try { FlxG.bitmap.clearUnused(); } catch (_:Dynamic) {}

			// ── FASE DIFERIDA: GPU flush + GC mayor ───────────────────────────
			// Se retrasan hasta DESPUÉS de que la animación de entrada del nuevo
			// state haya terminado. La duración por defecto de la transición es
			// globalDuration s (fade-out) + globalDuration*0.5 s (fade-in) ≈ 350ms.
			// Añadimos un margen generoso para que el overlay ya haya desaparecido.
			//
			// compact=false en collectMajor(): Gc.compact() es un stop-the-world
			// de varios ms que provoca el stutter visible; se omite aquí y se deja
			// para collectMajor() completo en el próximo PlayState.destroy() o al
			// volver al menú principal.
			final transMs = Std.int(funkin.transitions.StateTransition.globalDuration * 1000 + 200);
			final gcMs    = transMs + 150;

			#if lime
			try { lime.utils.Assets.cache.clear('songs');  } catch (_:Dynamic) {}
			try { lime.utils.Assets.cache.clear('music');  } catch (_:Dynamic) {}
			try { lime.utils.Assets.cache.clear('sounds'); } catch (_:Dynamic) {}
			try { lime.utils.Assets.cache.clear('images'); } catch (_:Dynamic) {}
			#end

			haxe.Timer.delay(function() {
				try { funkin.cache.PathsCache.instance.flushGPUCache(); } catch (_:Dynamic) {}
			}, transMs);

			#if (android || mobileC || ios)
			try { MemoryUtil.collectMinor(); } catch (_:Dynamic) {}
			haxe.Timer.delay(function() {
				try { MemoryUtil.collectMajor(false); } catch (_:Dynamic) {}
				try { flixel.FlxG.bitmap.clearUnused(); } catch (_:Dynamic) {}
			}, gcMs);
			#else
			haxe.Timer.delay(function() {
				MemoryUtil.collectMajor(false);
				try { FlxG.bitmap.clearUnused(); } catch (_:Dynamic) {}
			}, gcMs);
			#end
		});
	}

	// ══════════════════════════════════════════════════════════════════════════
	// ROTACIÓN DE CAPAS
	// ══════════════════════════════════════════════════════════════════════════

	public function moveToSecondLayer():Void {
		bitmapData2 = bitmapData != null ? bitmapData : new Map();
		font2 = font != null ? font : new Map();
		sound2 = sound != null ? sound : new Map();
		_bitmap2Count = _bitmapCount;

		bitmapData = new Map();
		font = new Map();
		sound = new Map();
		_bitmapCount = 0;
		_soundCount = 0;
		_fontCount = 0;
	}

	// ══════════════════════════════════════════════════════════════════════════
	// DISPOSE QUEUE — reparte dispose() en varios frames para no colapsar frame 1
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Encola un BitmapData para dispose() diferido.
	 * Si el listener de ENTER_FRAME no está activo, lo registra.
	 */
	function _queueDispose(b:BitmapData):Void {
		if (b == null) return;
		_disposeQueue.push(b);
		if (_disposeFrameListener == null) {
			_disposeFrameListener = _flushDisposeQueue;
			FlxG.stage.addEventListener(openfl.events.Event.ENTER_FRAME, _disposeFrameListener);
		}
	}

	/**
	 * Listener de ENTER_FRAME: dispone hasta _DISPOSE_PER_FRAME bitmaps por frame.
	 * Cuando la cola se vacía se desregistra solo y lanza un collectMinor().
	 */
	function _flushDisposeQueue(_:openfl.events.Event):Void {
		var count = 0;
		while (_disposeQueue.length > 0 && count < _DISPOSE_PER_FRAME) {
			final b = _disposeQueue.shift();
			if (b != null) try { b.dispose(); } catch (_:Dynamic) {}
			count++;
		}
		if (_disposeQueue.length == 0) {
			FlxG.stage.removeEventListener(openfl.events.Event.ENTER_FRAME, _disposeFrameListener);
			_disposeFrameListener = null;
			// Ciclo menor rápido ahora que todos los BitmapData nativos están libres
			try { MemoryUtil.collectMinor(); } catch (_:Dynamic) {}
		}
	}

	/**
	 * Destruye los assets de SECOND no rescatados.
	 *
	 * FIX CRÍTICO (RAM no se vacía al cambiar de state):
	 *   Los tres bucles de este método (bitmaps, fonts, sounds) llamaban a
	 *   map.remove(k) DURANTE su propio `for (k => v in map)`. En Haxe/CPP,
	 *   modificar un Map mientras se itera es comportamiento indefinido: el
	 *   iterador puede saltar entradas. Las entradas saltadas que debían
	 *   evictarse nunca recibían removeByKey/dispose/close, dejando sus
	 *   texturas y buffers de audio nativos vivos en RAM indefinidamente.
	 *
	 *   Solución: separar completamente la fase de DECISIÓN (recoger claves
	 *   en arrays sin tocar los Maps) de la fase de MUTACIÓN (procesar los
	 *   arrays actuando sobre los Maps). Ningún Map se modifica mientras
	 *   su iterador está activo.
	 *
	 * OPTIMIZACIÓN: batch eviction — acumula las claves a eliminar en Arrays
	 * locales y ejecuta los removes en una sola pasada.
	 */
	public function clearSecondLayer():Void {
		if (bitmapData2 == null)
			return; // guard double-clear

		// ── Bitmaps ────────────────────────────────────────────────────────────
		// Fase 1: decisión — iterar sin modificar bitmapData2.
		// BUG FIX CRÍTICO — antes: `graphic.persist` era siempre `true` para
		// TODOS los FlxGraphic gestionados por PathsCache, por lo que NINGÚN
		// asset de la capa SECOND se descartaba nunca: todos se rescataban a
		// CURRENT aunque el nuevo state no los necesitara, duplicando la RAM
		// usada en cada cambio de state.
		//
		// Solución: rescatar solo si:
		//   a) useCount > 0: un FlxSprite del nuevo state tiene referencia activa
		//   b) isInCurrentSession(): PathsCache ya incorporó el asset a la
		//      sesión actual (lo rescató de _previous o lo cargó de nuevo)
		//
		// graphic.persist sigue a `true` — es necesario para que Flixel no lo
		// evicte por su cuenta. Pero FunkinCache ya no lo usa como criterio de
		// rescate; usa PathsCache como fuente de verdad.
		final bmpRescue:Array<String> = [];
		final bmpEvict:Array<String> = [];
		for (k => b in bitmapData2) {
			if (_permanentBitmaps.exists(k))
				continue;
			final graphic = FlxG.bitmap.get(k);
			var shouldRescue = graphic != null && (graphic.useCount > 0 || funkin.cache.PathsCache.instance.isInCurrentSession(k));
			// KEY-MISMATCH GUARD:
			// FunkinCache indexa BitmapData por el path completo de OpenFL
			// (e.g. "assets/shared/images/icons/icon-bf.png"), mientras que
			// PathsCache usa la clave corta (e.g. "icons/icon-bf").
			// Cuando el lookup por key falla (FlxG.bitmap.get(k)==null y
			// isInCurrentSession(k)==false), clearSecondLayer() tomaría la
			// decisión incorrecta de evictar aunque PathsCache haya rescatado
			// el gráfico bajo un key distinto → BitmapData disposed → invisible.
			// Solución: fallback por identidad de objeto — si algún gráfico de la
			// sesión actual en PathsCache referencia este mismo BitmapData, rescatar.
			if (!shouldRescue && b != null)
				shouldRescue = funkin.cache.PathsCache.instance.isBitmapObjectInCurrentSession(b);
			if (shouldRescue)
				bmpRescue.push(k);
			else
				bmpEvict.push(k);
		}

		// Fase 2a: rescatar bitmaps a CURRENT.
		for (k in bmpRescue) {
			final b = bitmapData2.get(k);
			if (b == null)
				continue;
			bitmapData.set(k, b);
			_bitmapCount++;
			bitmapData2.remove(k);
			_bitmap2Count--;
		}

		// Fase 2b: evictar bitmaps.
		// CRÍTICO: _queueDispose() encola la liberación de textura nativa para
		// repartirla en frames posteriores y no colapsar el frame 1 del nuevo state.
		// FlxG.bitmap.removeByKey() se hace aquí (síncrono) porque Flixel no debe
		// ver estos bitmaps desde el frame 1; el dispose() nativo puede diferirse.
		for (k in bmpEvict) {
			final b = bitmapData2.get(k);
			final existingGraphic = FlxG.bitmap.get(k);
			final bitmapAlreadyDisposed = existingGraphic == null || existingGraphic.bitmap == null;
			FlxG.bitmap.removeByKey(k);
			#if lime LimeAssets.cache.image.remove(k); #end
			if (!bitmapAlreadyDisposed && b != null && !funkin.cache.PathsCache.instance.isPermanent(k))
				_queueDispose(b); // diferido — no dispose() síncrono aquí
			bitmapData2.remove(k);
			if (onEvict != null)
				try {
					onEvict(k, 'bitmap');
				} catch (_:Dynamic) {}
		}
		_bitmap2Count = 0;

		// ── Fonts ─────────────────────────────────────────────────────────────
		// FIX Issue #6 — rescatar fuentes usadas por el nuevo state antes de evictar.
		// Antes todas las fuentes eran evictadas en cada state switch (sin rescue),
		// forzando una recarga desde disco aunque el nuevo state las necesite
		// (Funkin.otf, etc.). Ahora se rescatan a CURRENT si PathsCache las considera
		// activas en la sesión actual, igual que bitmaps y sounds.
		// Fase 1: decisión sin modificar font2.
		final fontRescue:Array<String> = [];
		final fontEvict:Array<String> = [];
		for (k => _ in font2) {
			if (funkin.cache.PathsCache.instance.isInCurrentSession(k))
				fontRescue.push(k);
			else
				fontEvict.push(k);
		}
		// Fase 2a: rescatar.
		for (k in fontRescue) {
			final f = font2.get(k);
			if (f == null)
				continue;
			font.set(k, f);
			_fontCount++;
			font2.remove(k);
		}
		// Fase 2b: evictar.
		for (k in fontEvict) {
			#if lime LimeAssets.cache.font.remove(k); #end
			if (onEvict != null)
				try {
					onEvict(k, 'font');
				} catch (_:Dynamic) {}
		}

		// ── Sounds ────────────────────────────────────────────────────────────
		// Fase 1: decisión sin modificar sound2.
		final sndRescue:Array<String> = [];
		final sndEvict:Array<String> = [];
		for (k => _ in sound2) {
			if (_permanentSounds.exists(k))
				continue;
			if (funkin.cache.PathsCache.instance.isInCurrentSoundSession(k))
				sndRescue.push(k);
			else
				sndEvict.push(k);
		}
		// Fase 2a: rescatar a CURRENT — el nuevo state ya lo cargó en PathsCache.
		for (k in sndRescue) {
			final s = sound2.get(k);
			if (s == null)
				continue;
			sound.set(k, s);
			_soundCount++;
			sound2.remove(k);
		}
		// Fase 2b: evictar — close() libera el buffer de audio nativo.
		// Sin close(), solo muere el wrapper Haxe; el PCM buffer permanece en RAM
		// hasta que el GC finaliza el objeto Sound, lo que puede tardar cientos
		// de frames o no ocurrir antes del siguiente cambio de state.
		for (k in sndEvict) {
			final s = sound2.get(k);
			#if lime LimeAssets.cache.audio.remove(k); #end
			if (s != null)
				try {
					s.close();
				} catch (_:Dynamic) {}
			if (onEvict != null)
				try {
					onEvict(k, 'sound');
				} catch (_:Dynamic) {}
		}

		bitmapData2.clear();
		font2.clear();
		sound2.clear();
	}

	/** Limpieza segura — solo durante pantalla de carga. */
	public static function safeCleanup():Void
		try {
			FlxG.bitmap.clearUnused();
		} catch (_:Dynamic) {}

	// ══════════════════════════════════════════════════════════════════════════
	// VRAM — estimación y evicción proactiva
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Estima el uso de VRAM de los bitmaps en caché (bytes).
	 * Fórmula: ancho × alto × bytesPerPixel (4 si transparente, 3 si no).
	 * Es una aproximación — no cuenta mipmaps ni alineación de GPU.
	 */
	public function estimateVRAMBytes():Int {
		var total = 0;
		for (b in bitmapData)
			if (b != null)
				total += b.width * b.height * (b.transparent ? 4 : 3);
		for (b in bitmapData2)
			if (b != null)
				total += b.width * b.height * (b.transparent ? 4 : 3);
		for (b in _permanentBitmaps)
			if (b != null)
				total += b.width * b.height * (b.transparent ? 4 : 3);
		return total;
	}

	/** Estimación de VRAM en MB. */
	public inline function estimateVRAMMB():Int
		return Math.ceil(estimateVRAMBytes() / (1024 * 1024));

	/**
	 * Si la VRAM estimada supera `budgetMB`, evicta la capa SECOND de inmediato
	 * sin esperar al siguiente cambio de state.
	 * @param budgetMB   Presupuesto de VRAM en MB (por defecto 512).
	 * @return           true si se evictó la capa SECOND.
	 */
	public function evictSecondLayerIfOverBudget(budgetMB:Int = 256):Bool {
		final usedMB = estimateVRAMMB();
		if (usedMB > budgetMB) {
			trace('[FunkinCache] VRAM presupuesto excedido ($usedMB MB > $budgetMB MB) — evictando capa SECOND.');
			clearSecondLayer();
			try {
				FlxG.bitmap.clearUnused();
			} catch (_:Dynamic) {}
			// Liberar copias CPU de texturas ya subidas a VRAM (desktop)
			try {
				funkin.cache.PathsCache.instance.flushGPUCache();
			} catch (_:Dynamic) {}
			// Móvil: disposeImage() directo sin context3D
			try {
				funkin.cache.PathsCache.instance.flushGPUCacheMobile();
			} catch (_:Dynamic) {}
			try {
				funkin.system.MemoryUtil.collectMinor();
			} catch (_:Dynamic) {}
			return true;
		}
		return false;
	}

	/**
	 * Almacena un BitmapData optimizándolo automáticamente antes de guardarlo:
	 *   • Convierte RGBA→RGB cuando no hay transparencia real (~25% menos VRAM).
	 *   • Opcionalmente recorta la textura a `maxSide` píxeles por lado.
	 *
	 * A diferencia de `setBitmapData()`, este método es seguro para llamar con
	 * bitmaps recién cargados del disco cuando no hay otras referencias activas.
	 *
	 * @param id        Clave de caché.
	 * @param bitmap    BitmapData recién cargado (puede ser reemplazado internamente).
	 * @param maxSide   Si > 0, reduce la textura al tamaño máximo indicado.
	 */
	public function addOptimizedBitmap(id:String, bitmap:BitmapData, maxSide:Int = 0):Void {
		if (bitmap == null)
			return;
		// Convertir RGBA→RGB si no hay transparencia real
		var b = funkin.assets.AssetOptimizer.optimizeBitmapData(bitmap);
		// Recortar si se pasó un límite de tamaño
		if (maxSide > 0)
			b = funkin.assets.AssetOptimizer.capTextureDimensions(b, maxSide);
		setBitmapData(id, b);
	}

	// ══════════════════════════════════════════════════════════════════════════
	// PERMANENTES
	// ══════════════════════════════════════════════════════════════════════════

	public function markPermanentBitmap(id:String):Void {
		final b = bitmapData.get(id) ?? bitmapData2.get(id);
		if (b != null)
			_permanentBitmaps.set(id, b);
	}

	public function markPermanentSound(id:String):Void {
		final s = sound.get(id) ?? sound2.get(id);
		if (s != null)
			_permanentSounds.set(id, s);
	}

	public function unmarkPermanentBitmap(id:String):Void
		_permanentBitmaps.remove(id);

	// ══════════════════════════════════════════════════════════════════════════
	// getBitmapData — HOT PATH
	// ══════════════════════════════════════════════════════════════════════════

	public override function getBitmapData(id:String):BitmapData {
		// 1. CURRENT (hot path — hit más frecuente)
		var s = bitmapData.get(id);
		if (s != null)
			return s;

		// 2. PERMANENT
		s = _permanentBitmaps.get(id);
		if (s != null)
			return s;

		// 3. RESCUE SECOND → CURRENT
		final s2 = bitmapData2.get(id);
		if (s2 != null) {
			bitmapData2.remove(id);
			bitmapData.set(id, s2);
			_bitmapCount++;
			_bitmap2Count--;
			return s2;
		}

		// 4. FALLBACK desde disco (assets de mods no compilados)
		#if sys
		if (id != null) {
			// Intentar en el mod activo primero
			final modPath = _resolveModPath(id);
			if (modPath != null) {
				try {
					final bitmap = BitmapData.fromFile(modPath);
					if (bitmap != null) {
						trace('[FunkinCache] Cargado desde mod: $modPath');
						bitmapData.set(id, bitmap);
						_bitmapCount++;
						return bitmap;
					}
				} catch (e:Dynamic) {
					trace('[FunkinCache] Error bitmap mod "$modPath": $e');
				}
			}
			// Path literal en disco
			if (sys.FileSystem.exists(id)) {
				try {
					final bitmap = BitmapData.fromFile(id);
					if (bitmap != null) {
						bitmapData.set(id, bitmap);
						_bitmapCount++;
						return bitmap;
					}
				} catch (e:Dynamic) {
					trace('[FunkinCache] Error bitmap disco "$id": $e');
				}
			}
		}
		#end
		return null;
	}

	public override function hasBitmapData(id:String):Bool {
		if (bitmapData.exists(id) || bitmapData2.exists(id) || _permanentBitmaps.exists(id))
			return true;
		#if sys
		final modPath = _resolveModPath(id);
		if (modPath != null)
			return true;
		return id != null && sys.FileSystem.exists(id);
		#else
		return false;
		#end
	}

	/**
	 * Returns true ONLY when the bitmap is actually held in one of the in-memory maps.
	 *
	 * BUGFIX (Bug 2 — mod-switch re-registration):
	 * `hasBitmapData()` has a filesystem fallback (`FileSystem.exists(id)`) that makes
	 * `OpenFlAssets.exists(path, IMAGE)` return true even AFTER `Assets.cache.clear()`.
	 * Code that guards registration with `!OpenFlAssets.exists(path, IMAGE)` therefore
	 * never re-registers the bitmap — the condition is always false post-clear.
	 * Use this method instead of `hasBitmapData` / `OpenFlAssets.exists` whenever you
	 * need to know whether the bitmap is really cached in RAM (not just on disk).
	 */
	public inline function isBitmapInMaps(id:String):Bool
		return bitmapData.exists(id) || bitmapData2.exists(id) || _permanentBitmaps.exists(id);

	public override function setBitmapData(id:String, bitmapDataValue:BitmapData):Void {
		if (!bitmapData.exists(id))
			_bitmapCount++;
		bitmapData.set(id, bitmapDataValue);
	}

	public override function removeBitmapData(id:String):Bool {
		#if lime LimeAssets.cache.image.remove(id); #end
		final r1 = bitmapData.remove(id);
		final r2 = bitmapData2.remove(id);
		if (r1)
			_bitmapCount--;
		if (r2)
			_bitmap2Count--;
		_permanentBitmaps.remove(id);
		return r1 || r2;
	}

	// ══════════════════════════════════════════════════════════════════════════
	// getFont
	// ══════════════════════════════════════════════════════════════════════════

	public override function getFont(id:String):Font {
		var s = font.get(id);
		if (s != null)
			return s;
		final s2 = font2.get(id);
		if (s2 != null) {
			font2.remove(id);
			font.set(id, s2);
			_fontCount++;
		}
		return s2;
	}

	public override function hasFont(id:String):Bool
		return font.exists(id) || font2.exists(id);

	public override function setFont(id:String, fontValue:Font):Void {
		if (!font.exists(id))
			_fontCount++;
		font.set(id, fontValue);
	}

	public override function removeFont(id:String):Bool {
		#if lime LimeAssets.cache.font.remove(id); #end
		final r1 = font.remove(id);
		if (r1)
			_fontCount--;
		return r1 || font2.remove(id);
	}

	// ══════════════════════════════════════════════════════════════════════════
	// getSound
	// ══════════════════════════════════════════════════════════════════════════

	public override function getSound(id:String):Sound {
		var s = sound.get(id);
		if (s != null)
			return s;
		s = _permanentSounds.get(id);
		if (s != null)
			return s;
		final s2 = sound2.get(id);
		if (s2 != null) {
			sound2.remove(id);
			sound.set(id, s2);
			_soundCount++;
			return s2;
		}

		#if sys
		if (id != null) {
			final modPath = _resolveModPath(id);
			final actualPath = modPath ?? (sys.FileSystem.exists(id) ? id : null);
			if (actualPath != null) {
				try {
					final snd = Sound.fromFile(actualPath);
					if (snd != null) {
						sound.set(id, snd);
						_soundCount++;
						return snd;
					}
				} catch (e:Dynamic) {
					trace('[FunkinCache] Error sonido "$actualPath": $e');
				}
			}
		}
		#end
		return null;
	}

	public override function hasSound(id:String):Bool {
		if (sound.exists(id) || sound2.exists(id) || _permanentSounds.exists(id))
			return true;
		#if sys
		final modPath = _resolveModPath(id);
		if (modPath != null)
			return true;
		return id != null && sys.FileSystem.exists(id);
		#else
		return false;
		#end
	}

	public override function setSound(id:String, soundValue:Sound):Void {
		if (!sound.exists(id))
			_soundCount++;
		sound.set(id, soundValue);
	}

	public override function removeSound(id:String):Bool {
		#if lime LimeAssets.cache.audio.remove(id); #end
		final r1 = sound.remove(id);
		if (r1)
			_soundCount--;
		_permanentSounds.remove(id);
		return r1 || sound2.remove(id);
	}

	// ══════════════════════════════════════════════════════════════════════════
	// clear
	// ══════════════════════════════════════════════════════════════════════════

	public override function clear(?id:String):Void {
		if (id != null) {
			removeBitmapData(id);
			removeFont(id);
			removeSound(id);
			return;
		}
		bitmapData.clear();
		font.clear();
		sound.clear();
		bitmapData2.clear();
		font2.clear();
		sound2.clear();
		_bitmapCount = 0;
		_bitmap2Count = 0;
		_soundCount = 0;
		_fontCount = 0;
	}

	/** Limpieza total incluyendo permanentes (al cerrar el juego o cambiar de mod). */
	public function clearAll():Void {
		// FIX Bug #1 — cerrar buffers de audio nativos antes de vaciar los mapas.
		// clear() hace sound.clear() / sound2.clear() que solo suelta las referencias
		// Haxe; los buffers PCM nativos de OpenFL quedan vivos hasta que el GC
		// los recoge (puede tardar cientos de frames). Llamar close() explícitamente
		// los libera de inmediato, igual que hace clearSecondLayer() en cada switch.
		for (s in sound)
			try {
				s.close();
			} catch (_:Dynamic) {}
		for (s in sound2)
			try {
				s.close();
			} catch (_:Dynamic) {}
		for (s in _permanentSounds)
			try {
				s.close();
			} catch (_:Dynamic) {}

		// FIX Bug #3 — dispose() los BitmapData permanentes antes de limpiar el mapa.
		// clearAll() es llamado en cambios de mod: los permanentes del mod anterior
		// deben liberar su VRAM/RAM ahora, no esperar al GC.
		// NOTA: no llamar FlxG.bitmap.removeByKey() aquí porque destroy() ya se
		// encargará de eso; dispose() es suficiente para liberar el pixel buffer nativo.
		for (b in _permanentBitmaps)
			try {
				b.dispose();
			} catch (_:Dynamic) {}

		clear();
		_permanentBitmaps.clear();
		_permanentSounds.clear();
	}

	// ══════════════════════════════════════════════════════════════════════════
	// STATS / DEBUG
	// ══════════════════════════════════════════════════════════════════════════

	public function getStats():String {
		var perm = 0;
		for (_ in _permanentBitmaps)
			perm++;
		return '[FunkinCache] CURRENT: ${_bitmapCount} bmp / ${_soundCount} snd / ${_fontCount} fnt'
			+ ' | SECOND: ${_bitmap2Count} bmp | PERM: $perm bmp'
			+ ' | VRAM estimada: ${estimateVRAMMB()} MB';
	}

	public function dumpKeys():String {
		final sb = new StringBuf();
		sb.add('[FunkinCache] CURRENT:\n');
		for (k in bitmapData.keys())
			sb.add('  $k\n');
		sb.add('[FunkinCache] SECOND:\n');
		for (k in bitmapData2.keys())
			sb.add('  $k\n');
		sb.add('[FunkinCache] PERMANENT:\n');
		for (k in _permanentBitmaps.keys())
			sb.add('  $k\n');
		return sb.toString();
	}

	// ══════════════════════════════════════════════════════════════════════════
	// HELPERS
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Delega en PathsCache.resolveWithMod para que TODAS las resoluciones de
	 * path de mod pasen por el único caché compartido (_modPathCache).
	 * Antes, esta función llamaba a ModManager.resolveInMod directamente,
	 * duplicando el trabajo e ignorando el caché de PathsCache.
	 */
	static function _resolveModPath(id:String):Null<String> {
		return funkin.cache.PathsCache.instance.resolveWithMod(id);
	}
}
