package funkin.system;

#if cpp
import cpp.vm.Gc;
#elseif hl
import hl.Gc;
#end
import openfl.system.System;

/**
 * MemoryUtil — control del GC y consultas de memoria.
 *
 * ─── Diseño ──────────────────────────────────────────────────────────────────
 * Inspirado en Codename Engine pero integrado con el sistema de módulos de
 * Cool Engine.  Usa un contador de "solicitudes de desactivación" (disableCount)
 * en vez de un bool simple, para que múltiples sistemas puedan pedir que el GC
 * esté inactivo de forma independiente y se reactive sólo cuando todos lo hayan
 * liberado.
 *
 * ─── Uso típico ──────────────────────────────────────────────────────────────
 *   // Antes de cargar assets pesados (bloquea GC durante la carga):
 *   MemoryUtil.pauseGC();
 *   loadHeavyStuff();
 *   MemoryUtil.resumeGC();
 *   MemoryUtil.collectMajor();   // forzar ciclo después de la carga
 *
 * @author  Cool Engine Team
 * @since   0.5.1
 */
class MemoryUtil {
	// ── Estado del GC ─────────────────────────────────────────────────────────

	/** Número de llamadas a pauseGC() sin su correspondiente resumeGC(). */
	@:allow(funkin.cache.FunkinCache)
	public static var disableCount(default, null):Int = 0;

	// ── GC control ───────────────────────────────────────────────────────────

	/**
	 * Solicita pausar el GC.  El GC se desactiva sólo cuando disableCount > 0.
	 * Siempre acompañar con `resumeGC()` en un bloque try/finally.
	 */
	public static function pauseGC():Void {
		disableCount++;
		if (disableCount > 0)
			_disableGC();
	}

	/**
	 * Libera una pausa del GC.
	 * El GC se reactiva cuando disableCount vuelve a 0.
	 */
	public static function resumeGC():Void {
		if (disableCount > 0)
			disableCount--;
		if (disableCount == 0)
			_enableGC();
	}

	/**
	 * Fuerza un ciclo menor del GC (rápido, solo generación joven).
	 * Llamar entre canciones o al cambiar de estado.
	 */
	public static function collectMinor():Void {
		#if cpp
		Gc.run(false);
		#elseif hl
		// hl.Gc has no run(); a major() cycle is the closest equivalent
		Gc.major();
		#end
	}

	/**
	 * Fuerza un ciclo completo del GC + compactación del heap.
	 * Llamar al volver al menú principal o después de una carga pesada.
	 * Evitar durante gameplay — provoca un stutter visible.
	 *
	 * @param compact  Si true (por defecto) se llama a Gc.compact() después de
	 *                 Gc.run(). Pasar false en el path post-state-switch para
	 *                 evitar el stop-the-world que provoca la bajada de FPS
	 *                 justo cuando el nuevo state está pintando sus primeros frames.
	 *                 La compactación se puede omitir sin riesgo porque el heap
	 *                 se compactará en el siguiente collectMajor() completo (p.ej.
	 *                 al volver al menú principal).
	 *
	 * NOTA MÓVIL: Gc.compact() puede bloquear el hilo principal en Android.
	 */
	public static function collectMajor(compact:Bool = true):Void {
		// openfl.system.System.gc() notifica al motor nativo de OpenFL para que
		// libere referencias en su propio heap (Bitmap pools, Sound buffers, etc.)
		// antes de que el GC de hxcpp/HL barra los objetos Haxe.
		// Es un no-op en targets que no lo soportan → siempre seguro llamarlo.
		try {
			openfl.system.System.gc();
		} catch (_:Dynamic) {}

		#if cpp
		Gc.run(true);
		if (compact)
			Gc.compact();
		#elseif hl
		Gc.major();
		#end
	}

	// ── Consultas de memoria ─────────────────────────────────────────────────

	/** Memoria RAM usada por el proceso en bytes. */
	public static inline function usedBytes():Float
		return System.totalMemory;

	/** Memoria RAM usada en MB (redondeado). */
	public static inline function usedMB():Int
		return Math.round(System.totalMemory / (1024 * 1024));

	/**
	 * Estima la VRAM utilizada por los BitmapData registrados en FlxG.bitmap.
	 * Suma ancho × alto × bytesPerPixel para cada textura viva.
	 * Es una aproximación — no cuenta mipmaps ni alineación de hardware.
	 * @return Estimación en MB.
	 */
	public static function estimateVRAMMB():Int {
		var total:Float = 0;
		try {
			for (graphic in @:privateAccess flixel.FlxG.bitmap._cache) {
				if (graphic == null || graphic.bitmap == null)
					continue;
				final b = graphic.bitmap;
				total += b.width * b.height * (b.transparent ? 4 : 3);
			}
		} catch (_:Dynamic) {}
		return Math.ceil(total / (1024 * 1024));
	}

	/**
	 * Formatea bytes en una string legible: "152 MB" / "1.2 GB".
	 * @param bytes  Cantidad en bytes.
	 */
	public static function formatBytes(bytes:Float):String {
		if (bytes < 0)
			return "0 B";
		if (bytes < 1024)
			return Std.int(bytes) + " B";
		if (bytes < 1024 * 1024)
			return Std.int(bytes / 1024) + " KB";
		if (bytes < 1024 * 1024 * 1024)
			return Std.int(bytes / (1024 * 1024)) + " MB";
		var gb:Float = bytes / (1024 * 1024 * 1024);
		return (Math.round(gb * 10) / 10) + " GB";
	}

	// ── Internals ─────────────────────────────────────────────────────────────

	static function _enableGC():Void {
		#if cpp Gc.enable(true); #end
		// HashLink: enable no-op — Gc.major() lo reactiva implícitamente
	}

	static function _disableGC():Void {
		#if cpp Gc.enable(false); #end
		// HashLink no expone disable — la pausa se simula no llamando a Gc.major()
	}
}
