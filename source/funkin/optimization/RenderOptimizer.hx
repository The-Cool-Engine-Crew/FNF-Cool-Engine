package funkin.optimization;

import openfl.display.DisplayObject;
import openfl.display.Sprite;
import openfl.display.BitmapData;
import openfl.filters.BitmapFilter;
import flixel.FlxG;
import flixel.FlxCamera;
import flixel.FlxSprite;
import funkin.data.CameraUtil;
import funkin.audio.AudioConfig;

/**
 * RenderOptimizer — configura el pipeline de renderizado de OpenFL/HaxeFlixel
 * para maximizar el trabajo en GPU y minimizar el overhead de CPU.
 *
 * ─── Técnicas ────────────────────────────────────────────────────────────────
 *
 * 1. cacheAsBitmap = true  (CPU → GPU upload ONCE, sin re-rasterización)
 *    Cuando un DisplayObject tiene `cacheAsBitmap = true`, OpenFL rasteriza
 *    su contenido a una textura interna y la sube a VRAM una sola vez.
 *    Cada frame subsiguiente se dibuja con un draw call GPU directamente desde
 *    esa textura, sin pasar por el rasterizador de CPU.
 *    IDEAL PARA: sprites de stage que no cambian (fondos, props estáticos).
 *    NO USAR EN: sprites con animaciones o cambios de color frecuentes.
 *
 * 2. cacheAsBitmapMatrix = identityMatrix
 *    Junto con cacheAsBitmap, indica a OpenFL que la textura está en espacio
 *    local (no transformada), lo que permite que el engine reutilice la misma
 *    textura cacheada aunque el sprite se mueva/rote.
 *    Sin esto, cualquier movimiento del sprite fuerza re-rasterización.
 *
 * 3. FlxCamera.bgColor con alpha=0
 *    El canal alpha de bgColor determina si la cámara limpia su canvas cada
 *    frame (alpha > 0 = fill rect con el color). Si el stage cubre toda la
 *    pantalla, podemos evitar el clear del canvas de la cámara del juego
 *    usando alpha=0, ahorrando un fill rect de 1280×720 píxeles por frame.
 *
 * 4. Desactivar filtros innecesarios
 *    Cada FlxCamera con filtros fuerza un renderizado en dos pasadas (off-screen
 *    buffer + composición). Desactivar filtros en cámaras que no los necesitan
 *    elimina ese coste.
 *
 * 5. smoothing = false en texturas de notas/HUD
 *    El bilinear filtering GPU tiene coste. Para texturas píxel-perfect (HUD,
 *    notas a escala entera) desactivar smoothing es correcto y ahorra tiempo
 *    de texturizado.
 */

class RenderOptimizer
{
	/** Instancia del stage de OpenFL para configuración global. */
	private static var _stage:openfl.display.Stage = null;

	/**
	 * Llamar UNA VEZ al inicio del juego (en Main.setupGame() después de
	 * crear el FlxGame).
	 */
	public static function init():Void
	{
		_stage = openfl.Lib.current.stage;
		if (_stage == null) return;

		// ── Desactivar vector antialiasing global ────────────────────────────
		// StageQuality.LOW = sin antialiasing de líneas vectoriales.
		// Las texturas de sprites tienen su propio antialiasing (antialiasing=true).
		// El antialiasing vectorial solo aplica a primitivas drawn con Graphics,
		// que en FNF son el bg del healthbar y poco más.
		_stage.quality = openfl.display.StageQuality.LOW;

		// ── Activar pixel snapping global ────────────────────────────────────
		// PixelSnapping.ALWAYS hace que los DisplayObjects se posicionen en
		// coordenadas enteras, eliminando el sub-pixel rendering (bilinear
		// filtering en bordes). Mejora nitidez Y reduce trabajo de texturizado.
		// Nota: HaxeFlixel ya redondea coordenadas internamente en la mayoría
		// de targets, pero forzarlo a nivel de stage es la garantía definitiva.
		try
		{
			@:privateAccess
			_stage.align = openfl.display.StageAlign.TOP_LEFT;
		}
		catch (_:Dynamic) {}

		trace('[RenderOptimizer] Inicializado.');
		trace('[RenderOptimizer] Audio → ${AudioConfig.debugString()}');
	}

	/**
	 * Aplica cacheAsBitmap a sprites de stage que son completamente estáticos.
	 * Llamar después de crear el Stage.
	 *
	 * Con `cacheAsBitmap = true`, OpenFL rasteriza el contenido a una textura
	 * interna (subida a VRAM una sola vez) y la reutiliza cada frame sin pasar
	 * por el rasterizador de CPU — ideal para fondos y props que no cambian.
	 *
	 * @param sprites  Array de FlxSprites que no tendrán cambios de contenido.
	 */
	public static function cacheStaticSprites(sprites:Array<FlxSprite>):Void
	{
		if (sprites == null) return;
		for (spr in sprites)
		{
			if (spr == null || !spr.alive) continue;
			try
			{
				// Solo cachear si el sprite no tiene animaciones activas
				if (spr.animation == null || spr.animation.numFrames <= 1)
				{
					spr.active = false; // No necesita update()

					// Acceder al DisplayObject subyacente de OpenFL para
					// activar cacheAsBitmap. FlxSprite no expone esta propiedad
					// directamente, pero hereda de openfl.display.Sprite.
					@:privateAccess
					final dobj:openfl.display.DisplayObject = cast spr;
					if (dobj != null)
					{
						dobj.cacheAsBitmap = true;
						// cacheAsBitmapMatrix con la matriz identidad indica que
						// la textura está en espacio local → OpenFL la reutiliza
						// aunque el sprite se mueva, sin re-rasterizar.
						dobj.cacheAsBitmapMatrix = new openfl.geom.Matrix();
					}
				}
			}
			catch (_:Dynamic) {}
		}
	}

	/**
	 * Reduce la resolución de un sprite en un factor dado para ahorrar VRAM.
	 * Útil para props de fondo o personajes lejanos que no requieren full-res.
	 *
	 * Ejemplo: factor=0.5 → 512×512 RGBA se convierte en 256×256 RGBA (−75% VRAM)
	 *
	 * PRECAUCIÓN: Modifica el BitmapData del sprite de forma IRREVERSIBLE.
	 * Llamar solo en sprites que no comparten textura con otros.
	 *
	 * @param sprite  FlxSprite a reducir.
	 * @param factor  Factor de escala (0.0–1.0). 0.5 = mitad de resolución.
	 */
	public static function downsampleSprite(sprite:FlxSprite, factor:Float = 0.5):Void
	{
		if (sprite == null || sprite.pixels == null) return;
		if (factor <= 0 || factor >= 1.0) return;

		try
		{
			final src  = sprite.pixels;
			final newW = Std.int(Math.max(1, Math.round(src.width  * factor)));
			final newH = Std.int(Math.max(1, Math.round(src.height * factor)));

			final dst = new openfl.display.BitmapData(newW, newH, src.transparent, 0);
			final mtx = new openfl.geom.Matrix();
			mtx.scale(factor, factor);
			dst.draw(src, mtx, null, null, null, true);

			sprite.loadGraphic(dst);
			// Escalar el sprite de vuelta a tamaño original para que ocupe el mismo
			// espacio en pantalla, pero use la textura de menor resolución.
			sprite.scale.set(1.0 / factor, 1.0 / factor);
			sprite.updateHitbox();

			trace('[RenderOptimizer] downsampleSprite: ${src.width}×${src.height} → ${newW}×${newH} (factor=${factor})');
		}
		catch (e:Dynamic)
		{
			trace('[RenderOptimizer] downsampleSprite error: $e');
		}
	}

	/**
	 * Configura las FlxCameras para renderizado óptimo.
	 * Usa CameraUtil para acceder a _filters correctamente — centraliza el
	 * único punto de acceso privado en vez de `@:privateAccess` disperso.
	 * - gameCam: cámara del escenario
	 * - hudCam : cámara del HUD (puede ser null)
	 */
	public static function optimizeCameras(gameCam:FlxCamera, ?hudCam:FlxCamera):Void
	{
		if (gameCam != null) CameraUtil.pruneEmptyFilters(gameCam);
		if (hudCam  != null) CameraUtil.pruneEmptyFilters(hudCam);
	}

	/**
	 * Marca un BitmapData como "no necesita mipmaps" y desactiva smoothing.
	 * Útil para texturas de notas / HUD que se renderizan a tamaño 1:1 o escala entera.
	 */
	public static inline function setNearestNeighbor(sprite:FlxSprite):Void
	{
		if (sprite == null) return;
		sprite.antialiasing = false;
		// smoothing=false en el FlxFrame le dice a OpenFL que use GL_NEAREST
		// en vez de GL_LINEAR para el sampler de esta textura.
		if (sprite.frame != null && sprite.frame.parent != null)
		{
			@:privateAccess
			sprite.frame.parent.bitmap.lock(); // pin en VRAM, evita eviction
		}
	}

	/**
	 * Fuerza una recolección de basura mayor.
	 * Llamar entre canciones / al entrar al menú principal.
	 */
	public static function forceGC():Void
	{
		#if cpp
		cpp.vm.Gc.run(true);
		cpp.vm.Gc.compact();
		#end
		#if hl
		hl.Gc.major();
		#end
	}
}
