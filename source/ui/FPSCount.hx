package ui;

import haxe.Int32;
import openfl.events.Event;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.system.System;
#if gl_stats
import openfl.display._internal.stats.Context3DStats;
import openfl.display._internal.stats.DrawCallContext;
#end

/**
 * FPSCount — muestra FPS + Memoria + GC Mem.
 *
 * v2: Ring buffer O(1) en vez de Array + shift() O(n).
 *   ANTES: times.push() + while(shift()) movía el array entero cada frame.
 *   AHORA: escritura circular, sin alocaciones ni copies en el game loop.
 */
#if !openfl_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
class FPSCount extends TextField
{
	public var currentFPS(default, null):Int;

	@:noCompletion private var cacheCount:Int = 0;
	@:noCompletion private var currentTime:Float = 0.0;
	@:noCompletion private var showFps:Int = 0;
	@:noCompletion private var memPeak:Float = 0;
	@:noCompletion private var byteValue:Int32 = 1024;

	// ── Ring buffer: 2000 slots (cubre hasta 2000fps en 1 segundo) ──
	static inline var RING_CAP:Int = 2000; // 1 segundo a 120fps (era 2000 → innecesario)

	@:noCompletion private var _ring:Array<Float>;
	@:noCompletion private var _ringHead:Int = 0; // siguiente posición de escritura
	@:noCompletion private var _ringFill:Int = 0; // cuántas entradas válidas hay

	public function new(x:Float = 10, y:Float = 10, color:Int = 0xFFFFFF)
	{
		super();
		this.x = x;
		this.y = y;

		#if androidC
		byteValue = 1000;
		#end

		currentFPS = 0;
		selectable = false;
		mouseEnabled = false;
		defaultTextFormat = new TextFormat(openfl.utils.Assets.getFont(Paths.font("Funkin.otf")).fontName, 16, color);
		visible = true;
		autoSize = openfl.text.TextFieldAutoSize.LEFT;
		text = "FPS: 0 | Mem: 0MB/0MB - GC: 0MB";

		// Pre-alocar buffer una sola vez — cero alocaciones en el game loop
		_ring = [for (_ in 0...RING_CAP) 0.0];

		addEventListener(Event.ENTER_FRAME, _onFrame);
	}

	@:noCompletion
	private function _onFrame(_:Event):Void
	{
		var now:Float = openfl.Lib.getTimer();
		currentTime = now;

		// ── Escribir timestamp en el ring buffer (O(1)) ───────────────────
		_ring[_ringHead] = now;
		_ringHead = (_ringHead + 1) % RING_CAP;
		if (_ringFill < RING_CAP)
			_ringFill++;

		// ── Contar frames en el último segundo ────────────────────────────
		// Se recorre hacia atrás desde la entrada más reciente hasta encontrar
		// un timestamp más viejo de 1 segundo. Con RING_CAP=120 son máx 120
		// iteraciones (<<1ms), seguro hacerlo cada frame.
		var cutoff:Float = now - 1000.0;
		var validCount:Int = 0;
		for (k in 0..._ringFill)
		{
			var idx:Int = ((_ringHead - 1 - k) % RING_CAP + RING_CAP) % RING_CAP;
			if (_ring[idx] < cutoff)
				break;
			validCount++;
		}

		currentFPS = validCount;

		if (currentFPS > showFps)
		{
			showFps = currentFPS;
			textColor = 0x17FF00;
		}
		else if (currentFPS < showFps)
		{
			textColor = 0xFF4444;
			showFps = currentFPS;
		}
		else
		{
			textColor = 0xFFFFFF;
		}

		if (validCount != cacheCount && visible)
		{
			var mem:Float;
			var gcMem:Float;

			var line1:String = 'FPS: $showFps | ';
			#if cpp
			mem = cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE) / (byteValue * byteValue);
			gcMem = cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_CURRENT) / (byteValue * byteValue);
			if (mem > memPeak) memPeak = mem;
			line1 += 'Mem: ${formatMem(mem)}/${formatMem(memPeak)} - GC: ${formatMem(gcMem)}';
			#else
			mem = System.totalMemory / (byteValue * byteValue);
			if (mem > memPeak) memPeak = mem;
			line1 += 'Mem: ${formatMem(mem)}/${formatMem(memPeak)}';
			#end
			if (mem > memPeak)
				memPeak = mem;

			#if (gl_stats && !disable_cffi && (!html5 || !canvas))
			line1 += "  DC: " + Context3DStats.totalDrawCalls();
			#end

			text = line1;
		}

		cacheCount = validCount;
	}

	/** Muestra el valor en MB o GB (cuando supera 1000 MB). */
	@:noCompletion
	private inline function formatMem(mb:Float):String
	{
		if (mb >= 1000)
			return (Math.round(mb / 10.24) / 100) + "GB"; // 2 decimales
		return Math.round(mb) + "MB";
	}
}
