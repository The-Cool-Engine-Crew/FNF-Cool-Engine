package funkin.cache;

import flixel.FlxG;
import flixel.graphics.FlxGraphic;
import funkin.assets.AssetOptimizer;
import openfl.display.BitmapData;
import openfl.media.Sound;
#if sys
import sys.FileSystem;
import sys.io.File;
#end
// ── Compatibilidad con OpenFL antiguo / nuevo ─────────────────────────────────
#if (openfl >= "9.2.0")
import openfl.utils.Assets as OpenFLAssets;
#else
import openfl.Assets as OpenFLAssets;
#end
import animationdata.FunkinSprite;

using StringTools;

/**
 * PathsCache v4 — sistema de caché tricapa con prefetch asíncrono y LRU.
 *
 * ─── Mejoras v4 ──────────────────────────────────────────────────────────────
 *
 *  LRU REAL
 *    • _lruOrder: Array<String> que mantiene el orden de acceso.
 *    • Cuando _currentGraphics supera maxGraphics, evicta el menos usado.
 *    • Evita acumulación silenciosa de texturas no referenciadas.
 *
 *  PREFETCH ASÍNCRONO (desktop C++)
 *    • prefetchAsync(keys): inicia la carga de texturas en background.
 *    • isPrefetchDone(): true cuando todas las texturas están listas.
 *    • Integrado con CacheState para mostrar progreso real.
 *
 *  HIT RATE METRICS
 *    • Contadores: _hits, _misses, _rescues para diagnóstico de rendimiento.
 *    • hitRate(): porcentaje de hits sobre el total de lookups.
 *    • Visibles en el debug overlay.
 *
 *  SOPORTE MODS MEJORADO
 *    • _modPathCache: Map<String, String> para evitar rellamadas a ModManager.
 *    • resolveWithMod(id): resuelve el path real teniendo en cuenta el mod activo.
 *    • clearModPathCache(): llamar al cambiar de mod para invalidar el cache.
 *
 * ─── Capas de caché ──────────────────────────────────────────────────────────
 *
 *   PERMANENTE  — UI esencial, countdown, fonts. Nunca se destruye.
 *   CURRENT     — Assets de la sesión actual. Se rota al cambiar estado.
 *   PREVIOUS    — Assets de la sesión anterior. Se rescatan o destruyen.
 *
 * ─── Compatibilidad ──────────────────────────────────────────────────────────
 *  OpenFL ≥ 9.2.0 / OpenFL < 9.2.0 (via import condicional)
 *  Flixel ≥ 5.0.0 con null-safety
 *
 * @author Cool Engine Team
 * @version 4.0.0
 */
@:access(openfl.display.BitmapData)
class PathsCache {
	// ── Singleton ─────────────────────────────────────────────────────────────
	public static var instance(get, null):PathsCache;

	static function get_instance():PathsCache {
		if (instance == null)
			instance = new PathsCache();
		return instance;
	}

	// ── Opciones globales ─────────────────────────────────────────────────────
	public static var gpuCaching:Bool = #if (desktop && !hl && cpp) true #else false #end;

	public static var lowMemoryMode(default, set):Bool = false;

	static function set_lowMemoryMode(v:Bool):Bool {
		lowMemoryMode = v;
		if (instance != null) {
			// Mobile tiene RAM más limitada — límites más bajos incluso en modo normal
			#if (mobileC || android || ios)
			instance.maxGraphics = v ? 12 : 25;
			instance.maxSounds = v ? 10 : 20;
			#else
			instance.maxGraphics = v ? 25 : 40;
			instance.maxSounds = v ? 20 : 32;
			#end
		}
		return v;
	}

	/**
	 * Modo gameplay: límites más estrictos para mantener el baseline bajo
	 * durante la canción. Llamar al entrar a PlayState y restaurar al salir.
	 * En gameplay no se cargan nuevas texturas de UI/menú, así que 30/24
	 * cubre perfectamente el set de assets activos.
	 */
	public static function setGameplayMode(enabled:Bool):Void {
		if (instance == null)
			return;
		#if (mobileC || android || ios)
		instance.maxGraphics = enabled ? 20 : (lowMemoryMode ? 12 : 25);
		instance.maxSounds = enabled ? 12 : (lowMemoryMode ? 10 : 20);
		#else
		instance.maxGraphics = enabled ? 32 : (lowMemoryMode ? 25 : 40);
		instance.maxSounds = enabled ? 20 : (lowMemoryMode ? 20 : 32);
		#end
	}

	public static var streamedMusic:Bool = false;

	/**
	 * Resolvedor opcional de paths cortos → paths completos de asset.
	 * Ejemplo: `PathsCache.pathResolver = function(k) return Paths.image(k);`
	 * Registrar desde Main o create() del primer estado.
	 * Cuando `fromAssetKey(key)` falla, se intenta con el path resuelto.
	 */
	public static var pathResolver:(String) -> String = null;

	// ── Límites de caché ──────────────────────────────────────────────────────
	// Desktop: 80 texturas / 64 sonidos.
	// Mobile (Android/iOS): 25 / 20 — RAM muy limitada, sin swap real.
	// Con el fix de isInCurrentSession(), los assets no usados por el nuevo
	// state se destruyen en clearSecondLayer(), así que el LRU actúa solo
	// sobre assets DENTRO de la sesión activa. 25 sigue siendo suficiente para
	// gameplay normal (personajes + escenario + UI ≈ 15-20 texturas activas).
	// FIX RAM: desktop bajado de 80→40 texturas y 64→32 sonidos.
	// Los límites anteriores eran tan altos que el LRU nunca evictaba nada
	// en gameplay normal, acumulando texturas de sesiones anteriores en RAM.
	public var maxGraphics:Int = #if (mobileC || android || ios) 25 #else 40 #end;
	public var maxSounds:Int = #if (mobileC || android || ios) 20 #else 32 #end;

	// ── Tricapa de texturas ───────────────────────────────────────────────────
	final _permanentGraphics:Map<String, FlxGraphic> = [];
	final _currentGraphics:Map<String, FlxGraphic> = [];
	var _previousGraphics:Map<String, FlxGraphic> = [];

	// ── LRU de texturas current ───────────────────────────────────────────────
	// Mantiene el orden de acceso: [más antiguo ... más reciente]
	var _lruOrder:Array<String> = [];

	// ── Tricapa de sonidos ────────────────────────────────────────────────────
	final _permanentSounds:Map<String, Sound> = [];
	final _currentSounds:Map<String, Sound> = [];
	var _previousSounds:Map<String, Sound> = [];

	// ── Caché de paths de mod ─────────────────────────────────────────────────
	// Evita llamar a ModManager.resolveInMod en cada carga repetida.
	// Se mantiene entre sesiones (el mod activo no cambia al rotar state).
	// Se limita a _MOD_PATH_CACHE_MAX entradas para evitar crecimiento ilimitado.
	static inline final _MOD_PATH_CACHE_MAX:Int = 512;

	var _modPathCache:Map<String, String> = [];

	// ── Métricas de hit rate ──────────────────────────────────────────────────
	var _hits:Int = 0;
	var _misses:Int = 0;
	var _rescues:Int = 0; // hits rescatados desde previous

	// ── API de compatibilidad ─────────────────────────────────────────────────
	public var localTrackedAssets(get, never):Array<String>;

	inline function get_localTrackedAssets():Array<String> {
		final out:Array<String> = [];
		for (k in _currentGraphics.keys())
			out.push(k);
		for (k in _currentSounds.keys())
			out.push(k);
		return out;
	}

	public var currentTrackedGraphics(get, never):Map<String, FlxGraphic>;

	inline function get_currentTrackedGraphics()
		return _currentGraphics;

	public var currentTrackedSounds(get, never):Map<String, Sound>;

	inline function get_currentTrackedSounds()
		return _currentSounds;

	// ── Contadores O(1) ───────────────────────────────────────────────────────
	var _graphicCount:Int = 0;
	var _soundCount:Int = 0;

	public function graphicCount():Int
		return _graphicCount;

	public function soundCount():Int
		return _soundCount;

	static inline function _count<K, V>(m:Map<K, V>):Int {
		var n = 0;
		for (_ in m)
			n++;
		return n;
	}

	// ── Hit rate ──────────────────────────────────────────────────────────────

	/** Porcentaje de hits sobre el total de lookups (0.0 - 1.0). */
	public function hitRate():Float {
		final total = _hits + _misses;
		return total > 0 ? _hits / total : 0.0;
	}

	/** Reset de métricas. */
	public function resetMetrics():Void {
		_hits = 0;
		_misses = 0;
		_rescues = 0;
	}

	// ── API compatibilidad ────────────────────────────────────────────────────

	public function hasValidGraphic(key:String):Bool {
		var g = _permanentGraphics.get(key);
		if (g != null)
			return g.bitmap != null;
		g = _currentGraphics.get(key);
		if (g != null) {
			if (g.bitmap != null)
				return true;
			_currentGraphics.remove(key);
			_lruOrder.remove(key);
			_graphicCount--;
			return false;
		}
		g = _previousGraphics.get(key);
		if (g != null)
			return g.bitmap != null;
		return false;
	}

	public inline function peekGraphic(key:String):Null<FlxGraphic>
		return getGraphic(key);

	public function hasSound(key:String):Bool {
		if (_permanentSounds.exists(key))
			return true;
		if (_currentSounds.exists(key))
			return true;
		if (_previousSounds.exists(key))
			return true;
		return false;
	}

	// ── Constructor ───────────────────────────────────────────────────────────

	function new() {}

	// ═══════════════════════════════════════════════════════════════════════════
	// GESTIÓN DE SESIÓN
	// ═══════════════════════════════════════════════════════════════════════════

	/**
	 * Inicia una nueva sesión.
	 * Los assets de current pasan a previous.
	 * Los assets que se carguen ahora se añaden a current.
	 */
	public function beginSession():Void {
		// No-op: FunkinCache maneja el lifecycle via preStateSwitch/postStateSwitch.
		// PathsCache ya no destruye FlxGraphics durante cambios de estado — es solo un loader.
		trace('[PathsCache] beginSession() — no-op, FunkinCache gestiona el lifecycle');
	}

	/**
	 * Rota las capas de gráficos: _current → _previous, _previous descartada.
	 * Llamar desde FunkinCache.preStateSwitch, ANTES de que el nuevo estado cargue assets.
	 *
	 * Por qué es necesario:
	 *   FunkinCache.clearSecondLayer() llama FlxG.bitmap.removeByKey() → g.destroy()
	 *   → g.bitmap = null sobre los gráficos de la sesión anterior.
	 *   Sin esta rotación, PathsCache._currentGraphics retiene esos FlxGraphics muertos
	 *   indefinidamente. hasValidGraphic() veía el objeto != null y devolvía true.
	 *   El nuevo estado obtenía un gráfico con bitmap=null, lo usaba en FlxAtlasFrames,
	 *   y el primer draw → FlxDrawQuadsItem::render → null-object crash.
	 *
	 * Con esta rotación:
	 *   - Los gráficos actuales se mueven a _previousGraphics.
	 *   - Si el nuevo estado los necesita, getGraphic() los rescata a _current (siempre
	 *     que bitmap != null — si ya fueron destruidos se descartan y se recargan).
	 *   - _currentGraphics queda vacío → hasValidGraphic() devuelve false → carga limpia.
	 */
	public function rotateSession():Void {
		// ── Gráficos ──────────────────────────────────────────────────────────
		// _currentGraphics y _previousGraphics son `final` — no se pueden reasignar.
		// Copiar current → previous y limpiar current en su lugar.
		_previousGraphics.clear();
		for (k => g in _currentGraphics)
			_previousGraphics.set(k, g);
		_currentGraphics.clear();
		_graphicCount = 0;
		// Nota: _permanentGraphics NO se rota — nunca se destruyen.

		// ── FIX Bug 1: LRU crece sin límite ───────────────────────────────────
		// _lruOrder acumulaba todos los keys de todas las sesiones anteriores.
		// _touchLRU hace indexOf+splice O(n) sobre ese array creciente → lag.
		// Al rotar sesión el LRU debe reiniciarse junto con _currentGraphics.
		_lruOrder = [];

		// ── FIX Bug 2: sonidos nunca rotaban → retención indefinida de Sound ──
		// FunkinCache llama s.close() sobre los Sound de la capa anterior, pero
		// PathsCache._currentSounds seguía sosteniendo esas referencias cerradas,
		// impidiendo que el GC las recolectara. Se rota igual que los gráficos.
		// Igual que con gráficos: evictar sonidos sin usar antes de rotar.
		final _evictSndBefore:Array<String> = [];
		for (k in _currentSounds.keys())
			if (!_permanentSounds.exists(k))
				_evictSndBefore.push(k);
		// No hay useCount en Sound; los sonidos de menú (efectos de UI) son
		// de corta duración y siempre seguros de evictar al cambiar de state.
		// Los que el nuevo state necesite los recargará.
		for (k in _evictSndBefore) {
			final s = _currentSounds.get(k);
			_currentSounds.remove(k);
			_soundCount--;
			if (s != null) try { s.close(); } catch (_:Dynamic) {}
		}

		_previousSounds.clear();
		for (k => s in _currentSounds)
			_previousSounds.set(k, s);
		_currentSounds.clear();
		_soundCount = 0;

		// FIX: Clean up _pendingExclusions on each session rotation.
		// addExclusion() annotates keys to promote them to permanent when loaded.
		// The assets in the CacheState that were loaded were already promoted (flushed) before
		// the first state change. Any remaining pending entries
		// are from assets that were NEVER loaded (wrong path, missing asset) and will never
		// be promoted. Accumulating them only makes indexOf() slower on each
		// subsequent load.
		if (_pendingExclusions.length > 0)
			_pendingExclusions = [];

		// _modPathCache se conserva entre sesiones: el mod activo no cambia al
		// rotar state, así que las entradas siguen siendo válidas y reutilizarlas
		// evita re-llamar ModManager.resolveInMod para cada asset en la nueva sesión.
		// El tamaño se controla en resolveWithMod() con _MOD_PATH_CACHE_MAX.
	}

	/**
	 * Libera las referencias a gráficos de la sesión anterior.
	 * Llamar desde FunkinCache.postStateSwitch DESPUÉS de que clearSecondLayer()
	 * haya destruido los BitmapData vía removeByKey + dispose().
	 * En ese punto ningún gráfico de _previousGraphics es rescatable (sus bitmaps
	 * ya fueron dispuestos), así que retener los wrappers FlxGraphic solo gasta RAM.
	 */
	public function clearPreviousGraphics():Void
		_previousGraphics.clear();

	public function clearPreviousSounds():Void {
		_previousSounds.clear();
	}

	// ═══════════════════════════════════════════════════════════════════════════
	// TEXTURAS
	// ═══════════════════════════════════════════════════════════════════════════

	/**
	 * Carga o rescata una textura con LRU eviction.
	 * Si _currentGraphics supera maxGraphics, evicta el menos usado (front del LRU).
	 */
	public function cacheGraphic(key:String):Null<FlxGraphic> {
		final gPerm = _permanentGraphics.get(key);
		if (gPerm != null) {
			if (!_currentGraphics.exists(key)) {
				_currentGraphics.set(key, gPerm);
				_graphicCount++;
				_addToLRU(key);
			}
			_hits++;
			_touchLRU(key);
			return gPerm;
		}

		final gCur = _currentGraphics.get(key);
		if (gCur != null) {
			if (gCur.bitmap != null) {
				_hits++;
				_touchLRU(key);
				return gCur;
			}
			// Stale (bitmap dispuesto por clearSecondLayer mientras estaba en current) — evictar.
			_currentGraphics.remove(key);
			_lruOrder.remove(key);
			_graphicCount--;
			// Caer al bloque de previous/reload abajo.
		}

		if (_previousGraphics.exists(key)) {
			final g = _previousGraphics.get(key);
			_previousGraphics.remove(key);
			if (g != null && g.bitmap != null) {
				_rescues++;
				_hits++;
				_currentGraphics.set(key, g);
				_graphicCount++;
				_flushPendingExclusion(key);
				_addToLRU(key);
				_evictIfNeeded();
				// FIX Bug 2 — NO llamar disposeImage() aquí.
				// Durante el rescate desde _previousGraphics, el BitmapData aún está
				// en bitmapData2 (FunkinCache) y puede no haber pasado por
				// clearSecondLayer() todavía. Su lime.graphics.Image es la fuente
				// de la textura GPU: disposeImage() en este punto invalida esa textura
				// y deja el sprite invisible o causa un crash en el primer draw call.
				//
				// flushGPUCache() ya libera las copias CPU de forma segura, después
				// de que el nuevo state ha completado create() y ha renderizado al
				// menos un frame (llamado vía haxe.Timer.delay 80ms en FunkinCache).
				// No duplicar esa lógica aquí.
				//
				// FIX GPU diamond (4-color debug texture) en health icons:
				// El rescue mueve el FlxGraphic a _currentGraphics, pero sin llamar
				// _forceGPURender() la textura no queda pre-registrada en context3D.
				// flushGPUCache() (80ms) llama getTexture() por primera vez →
				// schedules upload para el siguiente draw call → disposeImage() limpia
				// el image data inmediatamente → el draw call llega sin datos → Stage3D
				// usa la textura de placeholder (diamond de colores).
				// _forceGPURender() registra la textura ANTES de que flushGPUCache()
				// corra, garantizando que el upload ocurra mientras image != null.
				// Si bitmap.image ya era null (flush previo), getTexture() devuelve el
				// handle existente sin re-upload — operación segura y sin coste.
				_forceGPURender(g);
				return g;
			}
		}

		_misses++;
		final g = _loadGraphic(key, false);
		if (g != null) {
			_addToLRU(key);
			_evictIfNeeded();
		}
		return g;
	}

	// ── LRU helpers ──────────────────────────────────────────────────────────

	inline function _addToLRU(key:String):Void
		_lruOrder.push(key);

	inline function _touchLRU(key:String):Void {
		final idx = _lruOrder.indexOf(key);
		if (idx >= 0)
			_lruOrder.splice(idx, 1);
		_lruOrder.push(key);
	}

	/**
	 * If _currentGraphics exceeds maxGraphics, evict the oldest entries.
	 * Only evict charts without active references (useCount == 0, not permanent).
	 */
	function _evictIfNeeded():Void {
		if (_graphicCount <= maxGraphics)
			return;
		var evicted = 0;
		var i = 0;
		while (_graphicCount > maxGraphics && i < _lruOrder.length) {
			final k = _lruOrder[i];
			if (_permanentGraphics.exists(k)) {
				i++;
				continue;
			}
			// FIX: nunca evictar texturas de UI de score/rating durante gameplay.
			// Los sprites de combo (num0–num9, sick, good, etc.) tienen useCount=0
			// momentáneamente entre un popup y el siguiente hit. Si se destruyen,
			// el siguiente loadGraphic() crashea con "This sprite was destroyed"
			// porque FlxG.bitmap.removeByKey() destruye el FlxGraphic subyacente
			// y Flixel no puede recargarlo en el mismo sprite ya en curso.
			if (k.indexOf('UI/normal/score') >= 0
				|| k.indexOf('UI/pixel/score')  >= 0
				|| k.indexOf('score/nums')       >= 0) {
				i++;
				continue;
			}
			// FIX: nunca evictar iconos de salud (health bar) durante gameplay.
			// Los iconos de personaje (icon-bf, icon-dad, etc.) caen a useCount==0
			// en el frame exacto en que la health bar cambia de estado
			// (normal → winning → losing) porque el sprite suelta la referencia
			// al gráfico anterior antes de asignar la nueva animación.
			// removeByKey() en ese instante destruye el FlxGraphic permanentemente
			// → el icono queda invisible o crashea en el siguiente render.
			if (k.indexOf('/icon-') >= 0 || k.indexOf('icons/') >= 0) {
				i++;
				continue;
			}
			final g = _currentGraphics.get(k);
			if (g != null && g.useCount <= 0) {
				_currentGraphics.remove(k);
				_lruOrder.splice(i, 1);
				_graphicCount--;
				evicted++;
				// FIX Issue #5 — liberar la textura de GPU/RAM real al evictar.
				// Antes, solo se eliminaba del mapa interno y del _lruOrder, pero
				// el FlxGraphic seguía vivo en FlxG.bitmap._cache (persist=true),
				// reteniendo toda la VRAM/RAM de la textura. El LRU era cosmético.
				// removeByKey() llama g.destroy() → bitmap.dispose() → libera la
				// textura nativa. La siguiente llamada a cacheGraphic(k) descubrirá
				// que el graphic ya no existe y lo recargará desde disco.
				try { FlxG.bitmap.removeByKey(k); } catch (_) {}
			} else
				i++;
		}
		if (evicted > 0)
			trace('[PathsCache] LRU evict: $evicted texturas (total=$_graphicCount/$maxGraphics)');
	}

	// ══════════════════════════════════════════════════════════════════════════
	// PREFETCH ASÍNCRONO
	// ══════════════════════════════════════════════════════════════════════════
	var _prefetchQueue:Array<String> = [];
	var _prefetchResults:Map<String, Bool> = [];
	var _prefetchDone:Bool = true;

	/**
	 * Inicia la precarga de una lista de texturas en background (desktop C++).
	 * En otras plataformas, hace la carga sincrónica normal.
	 *
	 * @param keys      Lista de claves/paths a precargar.
	 * @param onProgress Callback (loaded:Int, total:Int) llamado tras cada carga.
	 * @param onDone    Callback llamado cuando todas las texturas están listas.
	 */
	public function prefetchAsync(keys:Array<String>, ?onProgress:(Int, Int) -> Void, ?onDone:() -> Void):Void {
		if (keys == null || keys.length == 0) {
			if (onDone != null)
				onDone();
			return;
		}

		_prefetchQueue = keys.copy();
		_prefetchResults = [];
		_prefetchDone = false;
		final total = keys.length;
		var loaded = 0;

		// En cpp (desktop Y Android) cargamos por lotes via FlxTimer para no bloquear el render loop.
		#if cpp
		final batchSize = 4;
		var batchStart = 0;

		function loadBatch():Void {
			final end = Std.int(Math.min(batchStart + batchSize, total));
			for (i in batchStart...end) {
				final k = keys[i];
				if (!hasValidGraphic(k)) {
					final g = cacheGraphic(k);
					_prefetchResults.set(k, g != null);
				} else
					_prefetchResults.set(k, true);
				loaded++;
				if (onProgress != null)
					try {
						onProgress(loaded, total);
					} catch (_:Dynamic) {}
			}
			batchStart = end;
			if (batchStart >= total) {
				_prefetchDone = true;
				if (onDone != null)
					try {
						onDone();
					} catch (_:Dynamic) {}
			} else {
				// Siguiente batch en el próximo frame
				new flixel.util.FlxTimer().start(0, function(_) loadBatch());
			}
		}
		loadBatch();
		#else
		// Plataformas sin hilos: carga síncrona
		for (k in keys) {
			if (!hasValidGraphic(k))
				cacheGraphic(k);
			loaded++;
			if (onProgress != null)
				try {
					onProgress(loaded, total);
				} catch (_:Dynamic) {}
		}
		_prefetchDone = true;
		if (onDone != null)
			try {
				onDone();
			} catch (_:Dynamic) {}
		#end
	}

	/** true cuando el prefetch ha completado. */
	public function isPrefetchDone():Bool
		return _prefetchDone;

	/** Cuántos assets del último prefetch se cargaron correctamente. */
	public function prefetchSuccessCount():Int {
		var n = 0;
		for (v in _prefetchResults)
			if (v)
				n++;
		return n;
	}

	// ══════════════════════════════════════════════════════════════════════════
	// SOPORTE MODS — resolución de paths con caché
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Resuelve el path real de un asset teniendo en cuenta el mod activo.
	 * Usa _modPathCache para evitar llamadas repetidas a ModManager.
	 * El caché se limita a _MOD_PATH_CACHE_MAX entradas; cuando se llena,
	 * se descarta la mitad más antigua para evitar crecimiento ilimitado.
	 *
	 * @return Path del archivo en el mod, o null si no existe override en el mod.
	 */
	public function resolveWithMod(id:String):Null<String> {
		final cached = _modPathCache.get(id);
		if (cached != null)
			return cached == '' ? null : cached;

		#if sys
		try {
			final modPath = mods.ModManager.resolveInMod(id);
			if (modPath != null && sys.FileSystem.exists(modPath)) {
				_setModPathCache(id, modPath);
				return modPath;
			}
		} catch (_:Dynamic) {}
		#end
		_setModPathCache(id, ''); // cache miss — evita re-llamar ModManager
		return null;
	}

	/**
	 * Inserta una entrada en _modPathCache respetando el límite de tamaño.
	 * Cuando se alcanza _MOD_PATH_CACHE_MAX, elimina la mitad de las entradas
	 * más antiguas (las primeras en el orden de iteración del Map).
	 */
	inline function _setModPathCache(id:String, value:String):Void {
		if (_modPathCache.exists(id)) {
			_modPathCache.set(id, value);
			return;
		}
		// Evictar la mitad cuando el mapa está lleno.
		// BUG FIX: recoger las claves en un Array ANTES de borrar.
		// Modificar un Map<> mientras se itera su .keys() en Haxe/CPP es
		// comportamiento indefinido y puede causar crashes o evictions incorrectas.
		if (_count(_modPathCache) >= _MOD_PATH_CACHE_MAX) {
			final half = _MOD_PATH_CACHE_MAX >> 1;
			final toEvict:Array<String> = [];
			final keysIter = _modPathCache.keys();
			while (toEvict.length < half && keysIter.hasNext())
				toEvict.push(keysIter.next());
			for (k in toEvict)
				_modPathCache.remove(k);
		}
		_modPathCache.set(id, value);
	}

	/** Invalida el caché de paths de mod (llamar al cambiar de mod). */
	public function clearModPathCache():Void
		_modPathCache.clear();

	/**
	 * Carga una textura y la marca como permanente.
	 * Usada durante el pre-caché de arranque.
	 */
	public function permanentCacheGraphic(key:String):Null<FlxGraphic> {
		if (_permanentGraphics.exists(key))
			return _permanentGraphics.get(key);
		final g = _loadGraphic(key, true);
		if (g != null) {
			_permanentGraphics.set(key, g);
			_currentGraphics.set(key, g);
		}
		return g;
	}

	/** Registra un FlxGraphic ya existente en la sesión actual. */
	public function trackGraphic(key:String, graphic:FlxGraphic):Void {
		if (_currentGraphics.exists(key))
			return;
		graphic.persist = true;
		_currentGraphics.set(key, graphic);
		_graphicCount++;
	}

	/**
	 * Rescata un FlxGraphic de _previousGraphics a _currentGraphics.
	 * Llamar cuando un atlas cacheado se reutiliza entre sesiones para
	 * evitar que su gráfico sea destruido por clearPreviousSession().
	 *
	 * BUGFIX: también rescata el BitmapData subyacente en FunkinCache.
	 * Sin esto, FunkinCache.clearSecondLayer() llama dispose() sobre el
	 * BitmapData que este FlxGraphic sigue usando → graphic.bitmap = null
	 * → FlxDrawQuadsItem::render null-object crash en el primer frame.
	 */
	public function rescueFromPrevious(key:String, graphic:FlxGraphic):Void {
		if (_currentGraphics.exists(key) || _permanentGraphics.exists(key))
			return;
		if (_previousGraphics.exists(key)) {
			_previousGraphics.remove(key);
		}
		graphic.persist = true;
		_currentGraphics.set(key, graphic);
		_graphicCount++;
	}

	/** Devuelve un FlxGraphic buscando en todas las capas. */
	public function getGraphic(key:String, ?bitmapData:openfl.display.BitmapData, allowGPU:Bool = true):Null<FlxGraphic> {
		// BUGFIX: siempre verificar bitmap != null antes de devolver un gráfico.
		// FunkinCache.clearSecondLayer() puede haber destruido el gráfico (g.bitmap = null)
		// mientras PathsCache._currentGraphics sigue sosteniendo la referencia.
		// Devolver un gráfico muerto → FlxAtlasFrames con bitmap=null → crash en primer render.
		var gPerm = _permanentGraphics.get(key);
		if (gPerm != null) {
			if (gPerm.bitmap != null)
				return gPerm;
			_permanentGraphics.remove(key); // permanente destruido — limpiar y recargar
		}
		var gCur = _currentGraphics.get(key);
		if (gCur != null) {
			if (gCur.bitmap != null)
				return gCur;
			// Stale: evictar para que la siguiente carga lo recargue desde disco.
			// FIX Bug F (parte 1) — también limpiar _lruOrder al evictar entry stale.
			// Sin esto la clave queda en _lruOrder apuntando a una entry que ya no
			// existe en _currentGraphics → _evictIfNeeded() hace get() → null →
			// condición falla → i++ en bucle vacío, nunca evicta lo que debería.
			_currentGraphics.remove(key);
			_graphicCount--;
			final staleIdx = _lruOrder.indexOf(key);
			if (staleIdx >= 0)
				_lruOrder.splice(staleIdx, 1);
		}
		// ── RESCUE: mover de previous a current para que sobreviva esta sesión ──
		if (_previousGraphics.exists(key)) {
			final g = _previousGraphics.get(key);
			_previousGraphics.remove(key);
			// BUGFIX: si el gráfico fue destruido (bitmap=null), no rescatar — recargar.
			if (g != null && g.bitmap != null) {
				_currentGraphics.set(key, g);
				_graphicCount++;
				_flushPendingExclusion(key);
				// FIX Bug F (parte 2) — registrar rescate en LRU.
				// getGraphic() es el punto de entrada usado por Paths._getGraphicForPath()
				// (y por tanto por getSparrowAtlas/stageSprite/characterSprite). Sin _addToLRU
				// estos gráficos quedan fuera del LRU y nunca son evictables durante la sesión.
				_addToLRU(key);
				_evictIfNeeded();
				// FIX GPU diamond — mismo motivo que en cacheGraphic(): el rescue no
				// llama _forceGPURender(), dejando la textura sin pre-registrar en
				// context3D. flushGPUCache() llama getTexture() + disposeImage() antes
				// del primer draw call → Stage3D sube el placeholder de 4 colores.
				// Ver comentario extendido en cacheGraphic() rescue path.
				_forceGPURender(g);
				return g;
			}
			// Caer al bloque de bitmapData / retorno nulo abajo
		}
		// If a BitmapData was supplied, create and register the graphic now
		if (bitmapData != null) {
			var g = FlxGraphic.fromBitmapData(bitmapData, false, key, true);
			if (g != null) {
				g.persist = true;
				if (allowGPU)
					_forceGPURender(g);
				_currentGraphics.set(key, g);
				_graphicCount++;
				_flushPendingExclusion(key);
				// FIX Bug F (parte 3) — registrar nuevo gráfico en LRU.
				// Esta rama es la que usa Paths._getGraphicForPath() para TODO el atlas
				// loading (getSparrowAtlas, stageSprite, characterSprite, skinSprite...).
				// Sin _addToLRU aquí, el 100% de los atlas cargados durante gameplay
				// quedaban fuera del LRU → _evictIfNeeded() nunca los evictaba
				// → maxGraphics era ignorado → acumulación ilimitada de texturas en VRAM.
				_addToLRU(key);
				_evictIfNeeded();
			}
			return g;
		}
		return null;
	}

	function _loadGraphic(key:String, permanent:Bool):Null<FlxGraphic> {
		// Intentar con FlxG.bitmap primero (puede que Flixel ya lo tenga en caché propia)
		var existing = FlxG.bitmap.get(key);
		if (existing != null) {
			// BUGFIX CRÍTICO — FlxDrawQuadsItem::render null object reference:
			// FlxG.bitmap._cache conserva entradas cuyo FlxGraphic fue destruido por
			// clearPreviousSession() (llamado desde PlayState.destroy() vía clearUnusedMemory).
			// destroy() llama bitmap.dispose() → bitmap = null, pero la entrada sigue en el cache.
			// Si aceptamos ese gráfico sin verificar, lo metemos en _currentGraphics con bitmap=null
			// → FlxDrawQuadsItem::render falla en el primer frame con null object reference.
			// Solución: si bitmap es null, eliminar la entrada huérfana y recargar desde disco.
			if (existing.bitmap == null) {
				trace('[PathsCache] FlxGraphic huérfano detectado para "$key" (bitmap=null), recargando desde disco.');
				@:privateAccess FlxG.bitmap.removeKey(key);
				existing = null;
				// Caer al bloque de carga desde disco abajo
			} else {
				// MOD-SWITCH STALE HIT GUARD:
				// After destroy(), _currentGraphics and _permanentGraphics are both empty.
				// FlxG.bitmap may still hold persist=true FlxGraphics from the previous mod
				// session — they survived because Flixel only evicts non-persist entries.
				// Accepting them here would stamp the old-mod bitmap as current and serve
				// wrong textures to the new mod without any origin check.
				// Fix: if the key is not registered in any of our own maps, this graphic
				// is a stale survivor — evict it from FlxG.bitmap and fall through to a
				// fresh disk load so the new mod gets its own texture.
				//
				// FIX: _previousGraphics MUST be included in the ownership check.
				// After rotateSession(), _currentGraphics is empty but valid assets from
				// the previous session live in _previousGraphics until cacheGraphic() or
				// _loadGraphic() rescues them. Without this check, every asset that
				// cacheGraphic() didn't rescue before calling _loadGraphic() (e.g. icons
				// and ratings that had useCount==0 at preStateSwitch time) would be
				// incorrectly treated as a stale mod-survivor and evicted — forcing a
				// full disk reload even when the BitmapData was still intact in bitmapData2.
				if (!_currentGraphics.exists(key) && !_permanentGraphics.exists(key) && !_previousGraphics.exists(key)) {
					trace('[PathsCache] FlxG.bitmap stale hit for "$key" (not owned by current session) — evicting and reloading.');
					@:privateAccess FlxG.bitmap.removeKey(key);
					existing = null;
					// Fall through to fresh disk load below.
				} else {
					existing.persist = true;
					// FIX: if the asset was tracked in _previousGraphics (rescued via
					// normal session rotation), remove it from there before promoting
					// to _currentGraphics so it is not processed twice.
					if (_previousGraphics.exists(key)) {
						_previousGraphics.remove(key);
						_rescues++;
					}
					_currentGraphics.set(key, existing);
					_graphicCount++;
					// BUGFIX (crash FlxDrawQuadsItem::render):
					// FlxG.bitmap todavía contiene FlxGraphics de la sesión anterior —
					// no se limpian hasta postStateSwitch → clearPreviousSession().
					// Su BitmapData fue movido a bitmapData2 por moveToSecondLayer().
					// Si no lo rescatamos aquí, clearSecondLayer() llama dispose() sobre él
					// mientras este FlxGraphic (ya en _currentGraphics) sigue usándolo →
					// bitmap dispuesto en el primer frame de render → crash.
					return existing;
				}
			}
		}

		// Cargar vía FlxGraphic.fromAssetKey — igual que V-Slice FunkinMemory.cacheTexture().
		// Es más directo que getBitmapData → fromBitmapData y funciona con todas las
		// versiones de OpenFL porque delega la resolución al pipeline nativo de Flixel.
		//
		// FALLBACK PARA MODS (build no recompilada):
		// Los assets de mods existen en disco pero NO están en el manifest de OpenFL
		// (solo se registran en compilación). fromAssetKey → Assets.getBitmapData falla
		// con "Could not find a BitmapData asset with ID mods/...".
		// Solución: si fromAssetKey falla y el archivo existe en disco, cargamos el
		// BitmapData directamente con BitmapData.fromFile() y construimos el FlxGraphic.
		var g:FlxGraphic = null;
		try {
			g = FlxGraphic.fromAssetKey(key, false, null, true);

			// BUGFIX (Bug 1): después de Assets.cache.clear(), FunkinCache.hasBitmapData()
			// devuelve true vía el fallback FileSystem.exists(). fromAssetKey lo detecta
			// como "asset presente" y llama getBitmapData(), pero si la clave es corta
			// ("UI/alphabet") FileSystem.exists("UI/alphabet")=false → getBitmapData()=null
			// → fromBitmapData(null) devuelve un FlxGraphic con bitmap=null en vez de null.
			// Guardar ese gráfico muerto en _currentGraphics causaría:
			//   hasValidGraphic() → true (objeto != null) → se devuelve el gráfico
			//   → FlxAtlasFrames con bitmap=null → null-object crash en primer render.
			// Solución: detectar bitmap=null, purgar la entrada huérfana de FlxG.bitmap
			// y caer al bloque de carga desde disco.
			if (g != null && g.bitmap == null) {
				trace('[PathsCache] fromAssetKey devolvió FlxGraphic con bitmap=null para "$key" — descartando y recargando desde disco.');
				try {
					@:privateAccess FlxG.bitmap.removeKey(key);
				} catch (_:Dynamic) {}
				g = null;
			}
		} catch (e:Dynamic) {
			#if sys
			// Intento 2: carga directa desde disco (rutas de mods no compilados)
			if (FileSystem.exists(key)) {
				trace('[PathsCache] fromAssetKey falló para "$key", intentando carga directa desde disco...');
				try {
					var bitmap = BitmapData.fromFile(key);
					if (bitmap != null) {
						// Optimización de textura: elimina canal alpha si no se usa
						// (ahorra ~25% VRAM en sprites sin transparencia) — runtime lossless.
						bitmap = AssetOptimizer.optimizeBitmapData(bitmap);
						g = FlxGraphic.fromBitmapData(bitmap, false, key, true);
					}
				} catch (e2:Dynamic) {
					trace('[PathsCache] Error en carga directa de "$key": $e2');
				}
			}
			#end

			// Intento 3: resolver el path completo vía pathResolver (ej: Paths.image)
			// Evita los falsos "no se pudo cargar" cuando el key corto no está en el
			// manifiesto de OpenFL pero el asset existe bajo assets/images/<key>.png.
			if (g == null && pathResolver != null) {
				try {
					final resolved = pathResolver(key);
					if (resolved != null && resolved != key) {
						g = FlxGraphic.fromAssetKey(resolved, false, key, true);
						// g.key es (default, null) en Flixel — no se puede asignar.
						// Lo guardamos en _currentGraphics bajo el key corto más abajo.
					}
				} catch (e3:Dynamic) {}

				#if sys
				// Si fromAssetKey con path resuelto también falló, intentar disco directamente
				if (g == null && pathResolver != null) {
					try {
						final resolved2 = pathResolver(key);
						if (resolved2 != null && FileSystem.exists(resolved2)) {
							var bitmap2 = BitmapData.fromFile(resolved2);
							if (bitmap2 != null) {
								// Misma optimización que el intento 2.
								bitmap2 = AssetOptimizer.optimizeBitmapData(bitmap2);
								g = FlxGraphic.fromBitmapData(bitmap2, false, key, true);
							}
						}
					} catch (_:Dynamic) {}
				}
				#end
			}

			if (g == null)
				trace('[PathsCache] Error cargando "$key": $e');
		}

		if (g == null) {
			trace('[PathsCache] No se pudo cargar "$key"');
			return null;
		}

		g.persist = true;

		// ── AssetOptimizer: runtime bitmap optimization ───────────────────────
		// Elimina el canal alpha de texturas que no lo usan → ahorra ~25% VRAM.
		// Se ejecuta aquí (después de cargar, antes del upload GPU) para que
		// _forceGPURender suba ya la versión optimizada. Lossless: solo cambia
		// el formato interno de ARGB a RGB; los pixels visibles son idénticos.
		if (g.bitmap != null)
		{
			final _prevBitmap = g.bitmap;
			g.bitmap = AssetOptimizer.optimizeBitmapData(g.bitmap);
			if (g.bitmap != _prevBitmap)
				try { FunkinCache.instance.setBitmapData(key, g.bitmap); } catch (_:Dynamic) {}
		}

		// GPU pre-render: llama getTexture() para registrar la textura en el pipeline de OpenFL.
		// El upload real de pixels ocurre en el PRIMER DRAW CALL del render thread.
		// NO llamamos disposeImage() aquí — los pixels deben existir hasta ese primer draw.
		// flushGPUCache() (llamado 5 frames después via ENTER_FRAME en PlayState.create())
		// se encarga de liberar los pixels DESPUÉS de confirmar que el render ocurrió.
		_forceGPURender(g);

		_currentGraphics.set(key, g);
		_graphicCount++;
		_flushPendingExclusion(key);
		// FIX Bug 3: los graficos cargados desde disco (no rescates) no se añadían
		// al LRU, por lo que _evictIfNeeded() no podía evictarlos nunca.
		// Resultado: maxGraphics se ignoraba para cargas nuevas → crecimiento ilimitado.
		if (!permanent) {
			_addToLRU(key);
			_evictIfNeeded();
		}
		// FIX cross-song: las texturas de score/rating se cargan lazy (primer combo)
		// y clearSecondLayer() las destruye al cambiar canción porque no están en
		// _currentGraphics todavía. Promoverlas a _permanentGraphics la primera vez
		// que se cargan garantiza que sobrevivan todas las rotaciones de sesión.
		// Son texturas pequeñas (~10 archivos PNG) — el coste de memoria es mínimo.
		if (key.indexOf('score/') >= 0 || key.indexOf('UI/normal/score') >= 0
		    || key.indexOf('UI/pixel/score') >= 0) {
			_permanentGraphics.set(key, g);
		}
		return g;
	}

	/**
		* Pre-carga la textura en la GPU dibujando un sprite temporal.
		* Replicado de V-Slice FunkinMemory.forceRender() para evitar el stutter
		* del primer frame en el que OpenGL sube la textura.
		*
		/**
		* Pre-sube la textura a VRAM usando getTexture() directo.
		*
		* El dummy FlxSprite + draw() fue eliminado: instanciar un FlxSprite fuera
		* del render loop causa stutter durante el precacheo (especialmente al
		* cargar 40-100 texturas en LoadingState→PlayState). Flixel sube la textura
		* a GPU en el primer draw call real, lo que ocurre suavemente dentro del
		* frame loop cuando la loading screen ya está visible.
		*
		* getTexture() se mantiene como optimización opcional para context3D
		* disponible (desktop, no web/mobile).
	 */
	static function _forceGPURender(graphic:FlxGraphic):Void {
		if (graphic == null || graphic.bitmap == null)
			return;
		#if (desktop && !hl)
		try {
			if (FlxG.stage != null && FlxG.stage.context3D != null) {
				// Guard: si image == null (ya liberada por disposeImage() en una sesión
				// anterior), NO llamar getTexture(). La textura GPU puede seguir válida
				// (sesión B normal) — no hay nada que re-subir. Si hubo un context reset
				// mientras image era null, getTexture() intentaría reconstruir la textura
				// desde datos vacíos → diamond de debug de nuevo. En ese caso el asset
				// necesita recargarse desde disco, lo que gestiona la lógica de
				// invalidación del cache (bitmap=null → reload path en cacheGraphic).
				@:privateAccess
				if (graphic.bitmap.image != null)
					graphic.bitmap.getTexture(FlxG.stage.context3D);
			}
		} catch (_:Dynamic) {}
		#end
	}

	// ═══════════════════════════════════════════════════════════════════════════
	// SONIDOS
	// ═══════════════════════════════════════════════════════════════════════════

	public function cacheSound(key:String):Null<Sound> {
		if (_currentSounds.exists(key))
			return _currentSounds.get(key);

		// Rescatar de previous
		if (_previousSounds.exists(key)) {
			final s = _previousSounds.get(key);
			_previousSounds.remove(key);
			if (s != null) {
				_currentSounds.set(key, s);
				_soundCount++;
				_flushPendingExclusion(key);
				return s;
			}
			// FIX Bug C — si el Sound en _previousSounds era null (entrada huérfana),
			// antes se devolvía null directamente sin intentar cargar desde disco.
			// Ahora se cae al _loadSound() para dar al asset una segunda oportunidad.
			// (La entrada ya fue removida de _previousSounds arriba, así que no hay loop.)
		}

		return _loadSound(key, false);
	}

	public function permanentCacheSound(key:String):Null<Sound> {
		if (_permanentSounds.exists(key))
			return _permanentSounds.get(key);
		final s = _loadSound(key, true);
		if (s != null) {
			_permanentSounds.set(key, s);
			_currentSounds.set(key, s);
		}
		return s;
	}

	public function getSound(key:String, ?sound:Sound, safety:Bool = false):Null<Sound> {
		if (_permanentSounds.exists(key))
			return _permanentSounds.get(key);
		if (_currentSounds.exists(key))
			return _currentSounds.get(key);
		if (_previousSounds.exists(key)) {
			final s = _previousSounds.get(key);
			_previousSounds.remove(key);
			if (s != null) {
				_currentSounds.set(key, s);
				_soundCount++;
			}
			return s;
		}
		if (sound != null) {
			_currentSounds.set(key, sound);
			_soundCount++;
			return sound;
		}
		return null;
	}

	function _loadSound(key:String, permanent:Bool):Null<Sound> {
		var sound:Sound = null;

		// ── AssetOptimizer: disk-side OGG optimization ────────────────────────
		// Equivalente al hook de optimizeBitmapData en _loadGraphic.
		// Strippea el Vorbis Comment del .ogg antes de que OpenFL lo cargue en
		// memoria → el audio decodificado ocupa lo mismo, pero el archivo en disco
		// (y la copia interna del AssetCache) es más pequeño.
		// Solo en targets nativos (#if sys); en HTML5 OpenFL nunca tiene una ruta
		// física real accesible, así que no hacemos nada allí.
		// La operación es idempotente: si el archivo ya no tiene metadatos,
		// _optimizeOGG detecta que el resultado tiene el mismo tamaño y sale sin
		// reescribir. El coste es O(file_size) lectura de disco, una sola vez.
		#if sys
		try {
			final physPath = openfl.utils.Assets.getPath(key);
			if (physPath != null && physPath.endsWith('.ogg') && sys.FileSystem.exists(physPath))
				funkin.assets.AssetOptimizer.optimizeOGG(physPath);
		} catch (_:Dynamic) {} // nunca bloquear la carga por un error de optimización
		#end

		try {
			if (OpenFLAssets.exists(key, openfl.utils.AssetType.SOUND) || OpenFLAssets.exists(key, openfl.utils.AssetType.MUSIC))
				sound = OpenFLAssets.getSound(key);
		} catch (e:Dynamic) {
			trace('[PathsCache] Error de audio "$key": $e');
			return null;
		}

		if (sound == null)
			return null;

		_currentSounds.set(key, sound);
		_soundCount++;
		_flushPendingExclusion(key);
		return sound;
	}

	// ═══════════════════════════════════════════════════════════════════════════
	// LIBERACIÓN DE MEMORIA
	// ═══════════════════════════════════════════════════════════════════════════

	/**
	 * Destruye los assets de la sesión ANTERIOR que no fueron rescatados.
	 * Llamar después de `beginSession()` cuando la nueva sesión ya cargó sus assets.
	 */
	/**
	 * DEPRECATED — la destrucción de assets la hace FunkinCache.clearSecondLayer()
	 * via FlxG.bitmap.removeByKey (modelo Codename). Mantener como no-op para
	 * compatibilidad con Paths.clearPreviousSession() en PlayState/LoadingState.
	 */
	public function clearPreviousSession():Void {
		// No-op: FunkinCache.postStateSwitch ya llama clearSecondLayer() que
		// usa FlxG.bitmap.removeByKey para destruir los gráficos no rescatados.
		// Destruir FlxGraphics aquí (como hacía antes) causaba el crash porque
		// se destruían DESPUÉS de que los sprites del nuevo estado los cargaron.
		trace('[PathsCache] clearPreviousSession() — no-op, FunkinCache gestiona la destrucción');
	}

	function _clearPreviousGraphics():Void {
		// No-op: FunkinCache.clearSecondLayer() via FlxG.bitmap.removeByKey() maneja la destrucción.
		// Destruir FlxGraphics aquí causaba crashes porque ocurría después de que
		// los sprites del nuevo estado ya tenían referencias a esos gráficos.
		_previousGraphics.clear();
	}

	function _clearPreviousSounds():Void {
		for (key => sound in _previousSounds) {
			if (_permanentSounds.exists(key)) {
				_previousSounds.remove(key);
				continue;
			}
			if (sound == null) {
				_previousSounds.remove(key);
				continue;
			}
			try {
				OpenFLAssets.cache.removeSound(key);
			} catch (_) {}
			_previousSounds.remove(key);
		}

		// Limpiar las librerías de canciones completas — igual que V-Slice purgeSoundCache().
		// removeSound() por key individual no libera los bundles de audio de OpenFL.
		try {
			OpenFLAssets.cache.clear('songs');
		} catch (_) {}
		try {
			OpenFLAssets.cache.clear('music');
		} catch (_) {}

		if (_soundCount > maxSounds)
			_soundCount = _count(_currentSounds);
	}

	/** Limpieza completa (al salir del juego). */
	public function destroy():Void {
		_clearPreviousGraphics();
		for (k => g in _currentGraphics) {
			if (_permanentGraphics.exists(k))
				continue;
			if (g == null)
				continue;
			FlxG.bitmap.remove(g);
			g.persist = false;
			try {
				g.destroy();
			} catch (_) {}
		}
		_currentGraphics.clear();
		_permanentGraphics.clear();

		// FIX Bug #1 — cerrar buffers nativos de audio antes de limpiar los mapas.
		// .clear() solo suelta las referencias Haxe; los PCM buffers de OpenFL
		// permanecen vivos hasta el GC. close() los libera de inmediato.
		for (s in _currentSounds)   try { s.close(); } catch (_) {}
		for (s in _permanentSounds) try { s.close(); } catch (_) {}
		_currentSounds.clear();
		_permanentSounds.clear();

		// FIX Issue #4 — llamar _clearPreviousSounds() en lugar de .clear() directo.
		// _clearPreviousSounds() también limpia OpenFLAssets.cache y los bundles
		// 'songs'/'music' de Lime, que .clear() directo dejaba sin limpiar.
		// FIX Bug D — cerrar los buffers de _previousSounds antes de limpiarlos.
		// Cuando destroy() se llama directamente (cambio de mod, no via postStateSwitch),
		// los sounds en _previousSounds nunca pasaron por FunkinCache.clearSecondLayer()
		// y sus buffers PCM nativos siguen abiertos. close() los libera inmediatamente.
		for (s in _previousSounds) try { s.close(); } catch (_) {}
		_clearPreviousSounds();

		_graphicCount = 0;
		_soundCount = 0;
		// ── FIX: limpiar el cache de paths de mod al destruir ─────────────────
		// destroy() se llama desde forceFullClear() durante cambio de mod.
		// Sin esto, _modPathCache retiene los paths del mod anterior y
		// resolveWithMod() devuelve rutas del mod viejo en el nuevo mod,
		// haciendo que assets como getSparrowAtlas carguen del folder incorrecto
		// hasta reiniciar el juego.
		_modPathCache.clear();
	}

	/** Limpieza de assets de un contexto específico (p.ej. "freeplay"). */
	public function clearContext(contextTag:String):Void {
		final toRemove:Array<String> = [];
		@:privateAccess
		if (FlxG.bitmap._cache != null) {
			@:privateAccess
			for (k in FlxG.bitmap._cache.keys()) {
				if (!k.contains(contextTag))
					continue;
				if (_permanentGraphics.exists(k) || k.contains('fonts'))
					continue;
				toRemove.push(k);
			}
		}

		for (k in toRemove) {
			final g = FlxG.bitmap.get(k);
			if (g != null) {
				g.destroy();
				@:privateAccess FlxG.bitmap.removeKey(k);
			}
			// FIX Bug B — decrementar _graphicCount y limpiar _lruOrder al evictar.
			// Antes, clearContext() removía de _currentGraphics pero nunca decrementaba
			// _graphicCount ni eliminaba la clave de _lruOrder.
			// Resultado: _graphicCount quedaba inflado → _evictIfNeeded() se activaba
			// prematuramente y recorría entradas ya inexistentes en _lruOrder
			// (get() retornaba null → if(g != null && ...) false → i++ sin evictar nada).
			if (_currentGraphics.remove(k)) {
				_graphicCount--;
				final lruIdx = _lruOrder.indexOf(k);
				if (lruIdx >= 0)
					_lruOrder.splice(lruIdx, 1);
			}
			try {
				OpenFLAssets.cache.clear(k);
			} catch (_) {}
		}
	}

	// ═══════════════════════════════════════════════════════════════════════════
	// COMPAT — métodos esperados por Paths.hx y el resto del engine
	// ═══════════════════════════════════════════════════════════════════════════

	/** Lista de claves pendientes de marcar como permanentes. */
	var _pendingExclusions:Array<String> = [];

	/**
	 * Marca una clave como permanente (nunca se evicta).
	 * Si el asset ya está cargado en current, lo promueve a permanente.
	 * Si aún no está cargado, lo anota para promoverlo cuando se cargue.
	 */
	public function addExclusion(key:String):Void {
		final g = _currentGraphics.get(key);
		if (g != null) {
			_permanentGraphics.set(key, g);
			return;
		}
		final s = _currentSounds.get(key);
		if (s != null) {
			_permanentSounds.set(key, s);
			return;
		}
		if (!_pendingExclusions.contains(key))
			_pendingExclusions.push(key);
	}

	/**
	 * Comprueba si una clave está en la lista de exclusiones pendientes y,
	 * si el asset ya fue registrado en current, lo promueve a permanente
	 * y lo elimina de la lista pendiente.
	 *
	 * FIX Bug 1 — _pendingExclusions nunca se procesaban:
	 * addExclusion() anotaba la key pero nadie la promovía a permanente cuando
	 * el asset se cargaba después. Resultado: los assets de UI del CacheState
	 * nunca quedaban como permanentes en PathsCache, se recargaban desde disco
	 * en cada vuelta a FreeplayState y la memoria subía con cada visita.
	 * Llamar este método desde _loadGraphic/_loadSound y desde las rutas de
	 * rescate de cacheGraphic/cacheSound cierra ese hueco.
	 */
	inline function _flushPendingExclusion(key:String):Void {
		final idx = _pendingExclusions.indexOf(key);
		if (idx < 0)
			return;
		_pendingExclusions.splice(idx, 1);
		final g = _currentGraphics.get(key);
		if (g != null) {
			_permanentGraphics.set(key, g);
			return;
		}
		final s = _currentSounds.get(key);
		if (s != null)
			_permanentSounds.set(key, s);
	}

	/**
	 * Devuelve true si la key está en la sesión ACTUAL de PathsCache
	 * (ya sea como permanente o como asset cargado en este state).
	 *
	 * Usado por FunkinCache.clearSecondLayer() para decidir qué assets de la
	 * capa SECOND rescatar a CURRENT. Solo se rescatan los que el nuevo state
	 * realmente necesita — los demás se destruyen para liberar RAM.
	 *
	 * Por qué NO usar `graphic.persist`:
	 *   PathsCache establece `g.persist = true` en TODOS los FlxGraphics para
	 *   que Flixel no los evicte por su cuenta. Si FunkinCache usara ese flag
	 *   como criterio de rescate, NUNCA liberaría nada en el cambio de state.
	 */
	public inline function isInCurrentSession(key:String):Bool
		return _permanentGraphics.exists(key) || _currentGraphics.exists(key);

	public inline function isInCurrentSoundSession(key:String):Bool
		return _permanentSounds.exists(key) || _currentSounds.exists(key);

	/**
	 * Devuelve true si el BitmapData dado es referenciado por algún gráfico
	 * de la sesión actual o permanente — independientemente de su clave.
	 *
	 * Por qué existe esto:
	 *   FunkinCache indexa BitmapData por el path completo de OpenFL
	 *   (e.g. "assets/shared/images/icons/icon-bf.png"), mientras que
	 *   PathsCache indexa FlxGraphics por una clave corta (e.g. "icons/icon-bf").
	 *   clearSecondLayer() usa la clave de FunkinCache para consultar
	 *   isInCurrentSession(), que comprueba PathsCache._currentGraphics —
	 *   siempre devuelve false con paths completos porque PathsCache nunca
	 *   los vio. Este método resuelve la ambigüedad buscando por identidad
	 *   de objeto (==) en lugar de por nombre de clave.
	 *
	 * Coste: O(n) sobre _permanentGraphics + _currentGraphics. En práctica
	 * n ≤ 50 y solo se invoca cuando el lookup por clave ya falló.
	 */
	public function isBitmapObjectInCurrentSession(bitmap:BitmapData):Bool {
		if (bitmap == null) return false;
		for (g in _permanentGraphics)
			if (g != null && g.bitmap == bitmap) return true;
		for (g in _currentGraphics)
			if (g != null && g.bitmap == bitmap) return true;
		return false;
	}

	/**
	 * Devuelve true si la key está marcada como permanente en PathsCache.
	 * Usado por FunkinCache.clearSecondLayer() para no destruir assets que
	 * PathsCache considera permanentes aunque su FlxGraphic.useCount sea 0.
	 */
	public inline function isPermanent(key:String):Bool
		return _permanentGraphics.exists(key) || _permanentSounds.exists(key);

	/** Libera assets de la sesión anterior. FunkinCache maneja la destrucción real. */
	public function clearStoredMemory():Void {
		// FunkinCache.clearSecondLayer() ya destruye via removeByKey en postStateSwitch.
		// Esta función queda como no-op para compatibilidad con Paths.clearStoredMemory().
		try {
			FlxG.bitmap.clearUnused();
		} catch (_:Dynamic) {}
	}

	/** Destruye gráficos sin uso y fuerza GC. */
	public function clearUnusedMemory():Void {
		try {
			FlxG.bitmap.clearUnused();
		} catch (_:Dynamic) {}
		try {
			openfl.system.System.gc();
		} catch (_:Dynamic) {}
		#if cpp
		cpp.vm.Gc.run(true);
		try {
			cpp.vm.Gc.compact();
		} catch (_:Dynamic) {}
		#end
		#if hl hl.Gc.major(); #end
	}

	/**
	 * GPU caching post-load flush: Frees up RAM (CPU image) from all 
	 * graphics in the current session that have already been loaded into VRAM.
	 * Call it AFTER the state has completed its create() and has rendered at 
	 * least one frame—it ensures that context3D is ready and that all textures have been loaded by OpenFL.
	 * Effective on desktop C++ and Android/iOS OpenGL ES 3 (any target with context3D available, 
	 * excluding Flash and HTML5). It typically frees up 50–400 MB of RAM in songs with many sprites.
	 */
	public function flushGPUCache():Void {
		#if (!flash && !html5)
		if (FlxG.stage == null || FlxG.stage.context3D == null)
			return;
		final ctx = FlxG.stage.context3D;
		var released = 0;
		var skipped = 0;
		// BUG FIX: iterar con k => g para usar la clave del Map, NO g.key.
		// _permanentGraphics está indexado por la clave corta (ej: "UI/alphabet"),
		// mientras que g.key puede ser el path completo de OpenFL. Usar g.key
		// hacía que el check de permanencia siempre fallase → disposeImage() se
		// llamaba sobre permanentes en desktop, corrompiendo la textura ante
		// pérdida de contexto GPU.
		for (k => g in _currentGraphics) {
			if (g == null || g.bitmap == null)
				continue;
			// Nunca liberar permanentes — se reutilizan en cada state sin recarga
			if (_permanentGraphics.exists(k))
				continue;
			// FIX: nunca disponer la imagen CPU de iconos de salud aquí.
			// Los HealthIcon pueden estar siendo rescatados de _previousGraphics en
			// el mismo frame (create() del nuevo state) y aún no han tenido ningún
			// draw call que confirme el upload GPU. disposeImage() antes de ese
			// primer draw deja la textura como un placeholder (diamond de colores)
			// o invisible. _evictIfNeeded() ya aplica esta misma guardia; aquí
			// se replica para coherencia y para cubrir el path de flushGPUCache().
			if (k.indexOf('/icon-') >= 0 || k.indexOf('icons/') >= 0)
				continue;
			// Si ya fue dispuesto (bitmap.image == null), saltear
			@:privateAccess
			if (g.bitmap.image == null)
				continue;
			try {
				final tex = g.bitmap.getTexture(ctx);
				if (tex != null) {
					g.bitmap.disposeImage(); // libera pixels CPU manteniendo textura GPU
					released++;
				} else {
					skipped++;
				}
			} catch (_:Dynamic) {}
		}
		if (released > 0 || skipped > 0)
			trace('[PathsCache] flushGPUCache: $released texturas liberadas a VRAM-only, $skipped sin textura GPU aún');
		#end
	}

	/**
	 * Versión selectiva: libera RAM de una textura específica si ya fue subida a VRAM.
	 * Útil para liberar sprites de personaje/stage individualmente.
	 */
	public function flushGPUCacheFor(key:String):Void {
		#if (!flash && !html5)
		if (FlxG.stage == null || FlxG.stage.context3D == null)
			return;
		var g = _currentGraphics.get(key);
		if (g == null)
			g = _previousGraphics.get(key);
		if (g == null || g.bitmap == null)
			return;
		try {
			final tex = g.bitmap.getTexture(FlxG.stage.context3D);
			@:privateAccess
			if (tex != null && g.bitmap.image != null)
				g.bitmap.disposeImage();
		} catch (_:Dynamic) {}
		#end
	}

	/**
	 * Versión mobile de flushGPUCache(): libera las copias CPU de los BitmapData
	 * sin requerir context3D (Stage3D no disponible en OpenGL ES / Android / iOS).
	 *
	 * CUÁNDO LLAMAR: después de N frames de render (MusicBeatState usa 10).
	 * En ese punto todos los sprites visibles ya tuvieron al menos un draw call →
	 * OpenGL ya llamó glTexImage2D → los pixels CPU son redundantes.
	 *
	 * disposeImage() libera lime.graphics.Image (raw RGBA en RAM) conservando
	 * el handle de textura OpenGL. En unified memory (Android/iOS) esto libera
	 * la misma cantidad que en desktop porque CPU/GPU comparten la misma RAM física.
	 *
	 * NO llamar en PlayState — tiene su propio mecanismo granular por personaje/stage.
	 */
	public function flushGPUCacheMobile():Void {
		#if (android || mobileC || ios)
		var released = 0;
		for (k => g in _currentGraphics) {
			if (g == null || g.bitmap == null)
				continue;
			// Nunca liberar permanentes — se reutilizan en cada state sin recarga.
			if (_permanentGraphics.exists(k))
				continue;
			@:privateAccess
			if (g.bitmap.image == null)
				continue; // ya dispuesto
			try {
				g.bitmap.disposeImage();
				released++;
			} catch (_:Dynamic) {}
		}
		if (released > 0)
			trace('[PathsCache] flushGPUCacheMobile: $released texturas liberadas (copias CPU)');
		#end
	}

	/** Limpieza total — alias de destroy() para cambio de mod / reinicio. */
	public function forceFullClear():Void
		destroy();

	/** Limpia assets de gameplay (prefijos char_, stage_, skin_). */
	public function clearGameplayAssets():Void {
		for (prefix in ['char_', 'stage_', 'skin_'])
			clearContext(prefix);
	}

	/** String compacto para el overlay de debug. */
	public function debugString():String // OPT: _graphicCount/_soundCount son contadores O(1) — evita _count() O(n).
		return 'Cache: $_graphicCount tex / $_soundCount snd';

	/** Stats completos (alias de getStats). */
	public function fullStats():String
		return getStats();

	// ═══════════════════════════════════════════════════════════════════════════
	// STATS / DEBUG
	// ═══════════════════════════════════════════════════════════════════════════

	public function getStats():String {
		final total = _hits + _misses;
		final hr = total > 0 ? '${Math.round(hitRate() * 100)}%' : 'n/a';
		return '[PathsCache v4] Permanent: ${_count(_permanentGraphics)} tex / ${_count(_permanentSounds)} snd'
			+ ' | Current: ${_count(_currentGraphics)} tex (LRU ${_lruOrder.length}) / ${_count(_currentSounds)} snd'
			+ ' | Previous: ${_count(_previousGraphics)} tex / ${_count(_previousSounds)} snd'
			+ ' | HitRate: $hr (hits=$_hits miss=$_misses rescue=$_rescues)';
	}
}
