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
class FunkinCache extends AssetCache
{
	public static var instance:FunkinCache;

	// ── Capa SECOND ───────────────────────────────────────────────────────────
	@:noCompletion public var bitmapData2 : Map<String, BitmapData>;
	@:noCompletion public var font2       : Map<String, Font>;
	@:noCompletion public var sound2      : Map<String, Sound>;

	// ── Capa PERMANENT ────────────────────────────────────────────────────────
	@:noCompletion var _permanentBitmaps : Map<String, BitmapData> = [];
	@:noCompletion var _permanentSounds  : Map<String, Sound>      = [];

	// ── Contadores O(1) ───────────────────────────────────────────────────────
	var _bitmapCount  : Int = 0;
	var _bitmap2Count : Int = 0;
	var _soundCount   : Int = 0;
	var _fontCount    : Int = 0;

	/**
	 * Callback llamado cuando un asset se destruye.
	 * Firma: (key:String, assetType:String) → Void
	 * assetType ∈ { "bitmap", "font", "sound" }
	 */
	public var onEvict:Null<(String, String)->Void> = null;

	// ── Constructor ────────────────────────────────────────────────────────────
	public function new()
	{
		super();
		moveToSecondLayer();
		instance = this;
	}

	// ══════════════════════════════════════════════════════════════════════════
	// INIT — señales de Flixel
	// ══════════════════════════════════════════════════════════════════════════

	public static function init():Void
	{
		openfl.utils.Assets.cache = new FunkinCache();

		FlxG.signals.preStateSwitch.add(function()
		{
			// ── Paso 0: expulsar FlxGraphics muertos ANTES de rotar ───────────
			// Si el state anterior dejó FlxGraphics con useCount=0 en el pool de
			// Flixel (sprites destruidos pero gráfico aún referenciado), deben
			// eliminarse ANTES de moverlos a SECOND para que clearSecondLayer()
			// no los evalúe ni intente rescatarlos.
			try { FlxG.bitmap.clearUnused(); } catch (_:Dynamic) {}

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
			try
			{
				for (snd in FlxG.sound.list)
					if (snd != null && !snd.persist)
						try { snd.stop(); } catch (_:Dynamic) {}
			}
			catch (_:Dynamic) {}

			// ── Paso 3: limpiar capas de scripts de la sesión anterior ────────
			// Red de seguridad: si PlayState.destroy() no llegó a ejecutarse
			// (crash, excepción, resetState mid-frame), las capas de scripts
			// song/stage/char siguen activas y sus callbacks se dispararían en el
			// nuevo state. Limpiarlas aquí garantiza un arranque limpio.
			// globalScripts NO se limpia — son permanentes toda la sesión.
			try
			{
				funkin.scripting.ScriptHandler.clearSongScripts();
				funkin.scripting.ScriptHandler.clearStageScripts();
				funkin.scripting.ScriptHandler.clearCharScripts();
				funkin.scripting.ScriptHandler.clearMenuScripts();
			}
			catch (_:Dynamic) {}

			#if (android || mobileC || ios)
			try { MemoryUtil.collectMinor(); } catch (_:Dynamic) {}
			#end
		});

		FlxG.signals.postStateSwitch.add(function()
		{
			// ── FIX Bug 4: disableCount puede desincronizarse ─────────────────
			// Si PlayState es destruido por excepción/crash antes de llegar a su
			// destroy(), resumeGC() nunca se llama y disableCount queda en 1+.
			// El GC permanece desactivado para todas las sesiones siguientes →
			// la RAM sube sin parar. Este reset forzado es la red de seguridad.
			if (MemoryUtil.disableCount > 0)
			{
				trace('[FunkinCache] WARN: disableCount=${MemoryUtil.disableCount} al cambiar state — GC forzado a reactivar.');
				@:privateAccess MemoryUtil.disableCount = 0;
				@:privateAccess MemoryUtil._enableGC();
			}

			instance.clearSecondLayer();

			// ── Limpiar wrappers FlxGraphic huérfanos de PathsCache ───────────────
			// clearSecondLayer() ya dispuso los BitmapData nativos vía removeByKey().
			// PathsCache._previousGraphics sigue sosteniendo los wrappers FlxGraphic
			// (con bitmap=null). Liberarlos aquí, DESPUÉS de clearSecondLayer(),
			// para que el GC pueda recogerlos en el collectMajor() siguiente.
			funkin.cache.PathsCache.instance.clearPreviousGraphics();

			// ── Limpiar sonidos huérfanos de PathsCache ───────────────────────
			// clearSecondLayer() ya cerró los Sound natives vía s.close().
			// PathsCache._previousSounds aún sostenía esas referencias cerradas,
			// bloqueando al GC. Llamar aquí, DESPUÉS de clearSecondLayer().
			funkin.cache.PathsCache.instance.clearPreviousSounds();

			Paths.pruneAtlasCache();
			
			try { FlxG.bitmap.clearUnused(); } catch (_:Dynamic) {}

			#if lime
			try { lime.utils.Assets.cache.clear('songs');  } catch (_:Dynamic) {}
			try { lime.utils.Assets.cache.clear('music');  } catch (_:Dynamic) {}
			#end

			#if (android || mobileC || ios)
			try { MemoryUtil.collectMinor(); } catch (_:Dynamic) {} // inmediato: libera wrappers rápido
			new flixel.util.FlxTimer().start(0.13, function(_) // ~8 frames a 60fps
			{
				try { MemoryUtil.collectMajor(); } catch (_:Dynamic) {}
				try { flixel.FlxG.bitmap.clearUnused(); } catch (_:Dynamic) {}
			});
			#else
			MemoryUtil.collectMajor();
			try { FlxG.bitmap.clearUnused(); } catch (_:Dynamic) {}
			#end
		});
	}

	// ══════════════════════════════════════════════════════════════════════════
	// ROTACIÓN DE CAPAS
	// ══════════════════════════════════════════════════════════════════════════

	public function moveToSecondLayer():Void
	{
		bitmapData2   = bitmapData != null ? bitmapData : new Map();
		font2         = font       != null ? font       : new Map();
		sound2        = sound      != null ? sound      : new Map();
		_bitmap2Count = _bitmapCount;

		bitmapData   = new Map();
		font         = new Map();
		sound        = new Map();
		_bitmapCount = 0;
		_soundCount  = 0;
		_fontCount   = 0;
	}

	/**
	 * Destruye los assets de SECOND no rescatados.
	 * OPTIMIZACIÓN: batch eviction — acumula claves en un Array local
	 * y ejecuta los removes en una sola pasada para evitar rehash del Map.
	 */
	public function clearSecondLayer():Void
	{
		if (bitmapData2 == null) return; // guard double-clear

		// ── Bitmaps ────────────────────────────────────────────────────────────
		final toRemove:Array<String> = [];
		for (k => b in bitmapData2)
		{
			if (_permanentBitmaps.exists(k)) continue;
			final graphic = FlxG.bitmap.get(k);
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
			final shouldRescue = graphic != null
				&& (graphic.useCount > 0
					|| funkin.cache.PathsCache.instance.isInCurrentSession(k));
			if (shouldRescue)
			{
				// Aún en uso → rescatar a CURRENT
				bitmapData.set(k, b);
				_bitmapCount++;
				bitmapData2.remove(k);
				_bitmap2Count--;
				continue;
			}
			toRemove.push(k);
		}
		for (k in toRemove)
		{
			final b = bitmapData2.get(k);
			FlxG.bitmap.removeByKey(k);
			#if lime LimeAssets.cache.image.remove(k); #end
			// CRÍTICO: dispose() libera la textura nativa (GPU/Stage3D).
			// Sin esto el wrapper Haxe se GC-ea pero la VRAM/RAM nativa queda retenida.
			// FIX Bug 2: no destruir BitmapData que PathsCache considera permanentes.
			// FunkinCache solo veía useCount de FlxG.bitmap; si el useCount era 0
			// en ese instante (e.g. entre frames) llamaba dispose() aunque el asset
			// estuviera en _permanentGraphics de PathsCache → textura destruida,
			// recarga innecesaria y subida de RAM en cada visita a FreeplayState.
			if (b != null && !funkin.cache.PathsCache.instance.isPermanent(k))
				try { b.dispose(); } catch (_:Dynamic) {}
			bitmapData2.remove(k);
			if (onEvict != null) try { onEvict(k, 'bitmap'); } catch (_:Dynamic) {}
		}
		_bitmap2Count = 0;

		// ── Fonts ─────────────────────────────────────────────────────────────
		for (k in font2.keys())
		{
			#if lime LimeAssets.cache.font.remove(k); #end
			if (onEvict != null) try { onEvict(k, 'font'); } catch (_:Dynamic) {}
		}

		// ── Sounds ────────────────────────────────────────────────────────────
		for (k => s in sound2)
		{
			if (_permanentSounds.exists(k)) continue;
			if (funkin.cache.PathsCache.instance.isInCurrentSoundSession(k))
			{
				// Rescatar a CURRENT — el nuevo state ya lo cargó en PathsCache
				sound.set(k, s);
				_soundCount++;
				sound2.remove(k);
				continue;
			}
			#if lime LimeAssets.cache.audio.remove(k); #end
			// close() libera el buffer de audio nativo; sin esto solo muere el wrapper.
			if (s != null) try { s.close(); } catch (_:Dynamic) {}
			if (onEvict != null) try { onEvict(k, 'sound'); } catch (_:Dynamic) {}
		}

		bitmapData2 = new Map();
		font2       = new Map();
		sound2      = new Map();
	}

	/** Limpieza segura — solo durante pantalla de carga. */
	public static function safeCleanup():Void
		try { FlxG.bitmap.clearUnused(); } catch (_:Dynamic) {}

	// ══════════════════════════════════════════════════════════════════════════
	// PERMANENTES
	// ══════════════════════════════════════════════════════════════════════════

	public function markPermanentBitmap(id:String):Void
	{
		final b = bitmapData.get(id) ?? bitmapData2.get(id);
		if (b != null) _permanentBitmaps.set(id, b);
	}

	public function markPermanentSound(id:String):Void
	{
		final s = sound.get(id) ?? sound2.get(id);
		if (s != null) _permanentSounds.set(id, s);
	}

	public function unmarkPermanentBitmap(id:String):Void
		_permanentBitmaps.remove(id);

	// ══════════════════════════════════════════════════════════════════════════
	// getBitmapData — HOT PATH
	// ══════════════════════════════════════════════════════════════════════════

	public override function getBitmapData(id:String):BitmapData
	{
		// 1. CURRENT (hot path — hit más frecuente)
		var s = bitmapData.get(id);
		if (s != null) return s;

		// 2. PERMANENT
		s = _permanentBitmaps.get(id);
		if (s != null) return s;

		// 3. RESCUE SECOND → CURRENT
		final s2 = bitmapData2.get(id);
		if (s2 != null)
		{
			bitmapData2.remove(id);
			bitmapData.set(id, s2);
			_bitmapCount++;
			_bitmap2Count--;
			return s2;
		}

		// 4. FALLBACK desde disco (assets de mods no compilados)
		#if sys
		if (id != null)
		{
			// Intentar en el mod activo primero
			final modPath = _resolveModPath(id);
			if (modPath != null)
			{
				try
				{
					final bitmap = BitmapData.fromFile(modPath);
					if (bitmap != null)
					{
						trace('[FunkinCache] Cargado desde mod: $modPath');
						bitmapData.set(id, bitmap);
						_bitmapCount++;
						return bitmap;
					}
				}
				catch (e:Dynamic) { trace('[FunkinCache] Error bitmap mod "$modPath": $e'); }
			}
			// Path literal en disco
			if (sys.FileSystem.exists(id))
			{
				try
				{
					final bitmap = BitmapData.fromFile(id);
					if (bitmap != null)
					{
						bitmapData.set(id, bitmap);
						_bitmapCount++;
						return bitmap;
					}
				}
				catch (e:Dynamic) { trace('[FunkinCache] Error bitmap disco "$id": $e'); }
			}
		}
		#end
		return null;
	}

	public override function hasBitmapData(id:String):Bool
	{
		if (bitmapData.exists(id) || bitmapData2.exists(id) || _permanentBitmaps.exists(id)) return true;
		#if sys
		final modPath = _resolveModPath(id);
		if (modPath != null) return true;
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

	public override function setBitmapData(id:String, bitmapDataValue:BitmapData):Void
	{
		if (!bitmapData.exists(id)) _bitmapCount++;
		bitmapData.set(id, bitmapDataValue);
	}

	public override function removeBitmapData(id:String):Bool
	{
		#if lime LimeAssets.cache.image.remove(id); #end
		final r1 = bitmapData.remove(id);
		final r2 = bitmapData2.remove(id);
		if (r1) _bitmapCount--;
		if (r2) _bitmap2Count--;
		_permanentBitmaps.remove(id);
		return r1 || r2;
	}

	// ══════════════════════════════════════════════════════════════════════════
	// getFont
	// ══════════════════════════════════════════════════════════════════════════

	public override function getFont(id:String):Font
	{
		var s = font.get(id);
		if (s != null) return s;
		final s2 = font2.get(id);
		if (s2 != null) { font2.remove(id); font.set(id, s2); _fontCount++; }
		return s2;
	}

	public override function hasFont(id:String):Bool
		return font.exists(id) || font2.exists(id);

	public override function setFont(id:String, fontValue:Font):Void
	{
		if (!font.exists(id)) _fontCount++;
		font.set(id, fontValue);
	}

	public override function removeFont(id:String):Bool
	{
		#if lime LimeAssets.cache.font.remove(id); #end
		final r1 = font.remove(id);
		if (r1) _fontCount--;
		return r1 || font2.remove(id);
	}

	// ══════════════════════════════════════════════════════════════════════════
	// getSound
	// ══════════════════════════════════════════════════════════════════════════

	public override function getSound(id:String):Sound
	{
		var s = sound.get(id);
		if (s != null) return s;
		s = _permanentSounds.get(id);
		if (s != null) return s;
		final s2 = sound2.get(id);
		if (s2 != null) { sound2.remove(id); sound.set(id, s2); _soundCount++; return s2; }

		#if sys
		if (id != null)
		{
			final modPath = _resolveModPath(id);
			final actualPath = modPath ?? (sys.FileSystem.exists(id) ? id : null);
			if (actualPath != null)
			{
				try
				{
					final snd = Sound.fromFile(actualPath);
					if (snd != null) { sound.set(id, snd); _soundCount++; return snd; }
				}
				catch (e:Dynamic) { trace('[FunkinCache] Error sonido "$actualPath": $e'); }
			}
		}
		#end
		return null;
	}

	public override function hasSound(id:String):Bool
	{
		if (sound.exists(id) || sound2.exists(id) || _permanentSounds.exists(id)) return true;
		#if sys
		final modPath = _resolveModPath(id);
		if (modPath != null) return true;
		return id != null && sys.FileSystem.exists(id);
		#else
		return false;
		#end
	}

	public override function setSound(id:String, soundValue:Sound):Void
	{
		if (!sound.exists(id)) _soundCount++;
		sound.set(id, soundValue);
	}

	public override function removeSound(id:String):Bool
	{
		#if lime LimeAssets.cache.audio.remove(id); #end
		final r1 = sound.remove(id);
		if (r1) _soundCount--;
		_permanentSounds.remove(id);
		return r1 || sound2.remove(id);
	}

	// ══════════════════════════════════════════════════════════════════════════
	// clear
	// ══════════════════════════════════════════════════════════════════════════

	public override function clear(?id:String):Void
	{
		if (id != null) { removeBitmapData(id); removeFont(id); removeSound(id); return; }
		bitmapData.clear();  font.clear();  sound.clear();
		bitmapData2.clear(); font2.clear(); sound2.clear();
		_bitmapCount = 0; _bitmap2Count = 0; _soundCount = 0; _fontCount = 0;
	}

	/** Limpieza total incluyendo permanentes (al cerrar el juego o cambiar de mod). */
	public function clearAll():Void
	{
		clear();
		_permanentBitmaps.clear();
		_permanentSounds.clear();
	}

	// ══════════════════════════════════════════════════════════════════════════
	// STATS / DEBUG
	// ══════════════════════════════════════════════════════════════════════════

	public function getStats():String
	{
		var perm = 0;
		for (_ in _permanentBitmaps) perm++;
		return '[FunkinCache] CURRENT: ${_bitmapCount} bmp / ${_soundCount} snd / ${_fontCount} fnt'
			 + ' | SECOND: ${_bitmap2Count} bmp | PERM: $perm bmp';
	}

	public function dumpKeys():String
	{
		final sb = new StringBuf();
		sb.add('[FunkinCache] CURRENT:\n');
		for (k in bitmapData.keys()) sb.add('  $k\n');
		sb.add('[FunkinCache] SECOND:\n');
		for (k in bitmapData2.keys()) sb.add('  $k\n');
		sb.add('[FunkinCache] PERMANENT:\n');
		for (k in _permanentBitmaps.keys()) sb.add('  $k\n');
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
	static function _resolveModPath(id:String):Null<String>
	{
		return funkin.cache.PathsCache.instance.resolveWithMod(id);
	}
}
