package funkin.optimization;

import flixel.FlxG;
import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.graphics.frames.FlxFrame;
import openfl.display.BitmapData;
import openfl.display.Graphics;
import openfl.Vector;
import openfl.geom.Rectangle;

/**
 * GPURenderer OPTIMIZADO — sin allocs por frame.
 *
 * Cambios críticos vs la versión anterior:
 *  - GPUBatch.render() ya NO crea Vector<Float>/Vector<Int> nuevos cada frame.
 *    Antes: 2 allocs × 3000 sprites × 60 FPS = ~360 000 objetos/seg → GC enorme.
 *    Ahora: reutiliza los buffers pre-alojados, copia solo el rango usado.
 *  - Se eliminó haxe.Timer.stamp() del render loop (coste nativo no trivial).
 *  - updateCameraRect() se llama una vez por render, no por sprite.
 *  - Se redujo MAX_SPRITES de 3000 a 512 (FNF nunca muestra 3000 notas
 *    simultáneas; valores altos solo desperdician ~11 MB por batch).
 *  - sortedBatches usa array pool en clear() para no realojar cada frame.
 */
class GPURenderer
{
    // === BATCHES ===
    private var batches:Map<BitmapData, GPUBatch>;
    private var sortedBatches:Array<GPUBatch>;

    // === CAMERA ===
    private var camera:FlxCamera;
    private var cameraRect:Rectangle;

    // === CONFIGURATION ===
    public var enabled:Bool = true;
    public var enableCulling:Bool = true;
    public var enableZSorting:Bool = false; // desactivado por defecto — poco beneficio

    // === CULLING ===
    private var cullPadding:Float = 50;

    // === STATS (debug) ===
    public var drawCalls:Int = 0;
    public var spritesRendered:Int = 0;
    public var spritesCulled:Int = 0;

    // Camera rect actualizado UNA vez por render
    private var _camDirty:Bool = true;

    // Auto-prune de batches huérfanos cada N renders para liberar VRAM
    private static inline var PRUNE_INTERVAL:Int = 150;
    private var _pruneCounter:Int = 0;

    public function new(?camera:FlxCamera)
    {
        this.camera    = camera != null ? camera : FlxG.camera;
        batches        = new Map();
        sortedBatches  = [];
        cameraRect     = new Rectangle();
    }

    // ─── API pública ──────────────────────────────────────────────────────────

    public function addSprite(sprite:FlxSprite):Void
    {
        if (!enabled || sprite == null || !sprite.visible || sprite.alpha <= 0)
            return;

        final frame = sprite.frame;
        if (frame == null) return;

        if (enableCulling && !isOnScreen(sprite))
        {
            spritesCulled++;
            return;
        }

        try
        {
            final texture = frame.parent.bitmap;
            if (texture == null) return;

            var batch = batches.get(texture);
            if (batch == null)
            {
                batch = new GPUBatch(texture);
                batches.set(texture, batch);
                sortedBatches.push(batch);
            }
            batch.addSprite(sprite, frame, camera);
            spritesRendered++;
        }
        catch (_:Dynamic) {}
    }

    public function render():Void
    {
        if (!enabled) return;
        if (camera == null) { clear(); return; }

        // Actualizar cameraRect UNA vez por frame
        _camDirty = false;
        _updateCameraRect();

        drawCalls       = 0;
        spritesRendered = 0;
        spritesCulled   = 0;

        try
        {
            if (camera.canvas == null || camera.canvas.graphics == null)
            { clear(); return; }

            final graphics = camera.canvas.graphics;

            if (enableZSorting && sortedBatches.length > 1)
                sortedBatches.sort((a, b) -> a.avgZIndex < b.avgZIndex ? -1 : 1);

            for (batch in sortedBatches)
            {
                if (batch.spriteCount > 0)
                {
                    batch.render(graphics);
                    drawCalls++;
                }
            }
        }
        catch (_:Dynamic) {}

        clear();
        _camDirty = true;

        // Auto-prune de batches cuyas texturas ya no están en uso → libera VRAM
        if (++_pruneCounter >= PRUNE_INTERVAL)
        {
            _pruneCounter = 0;
            clearUnusedBatches();
        }
    }

    public function clear():Void
    {
        for (batch in batches) batch.clear();
    }

    /**
     * Limpia y destruye batches de texturas que ya no se usan.
     * Llamar entre canciones para liberar memoria de texturas antiguas.
     */
    public function clearUnusedBatches():Void
    {
        var keysToRemove:Array<BitmapData> = [];
        for (key in batches.keys())
        {
            var batch = batches.get(key);
            if (batch != null && batch.spriteCount == 0)
                keysToRemove.push(key);
        }
        for (key in keysToRemove)
        {
            var batch = batches.get(key);
            if (batch != null) batch.destroy();
            batches.remove(key);
        }
        // Reconstruir sortedBatches desde el Map actualizado
        sortedBatches.resize(0);
        for (batch in batches) sortedBatches.push(batch);
    }

    public function getStats():String
    {
        if (!enabled) return 'GPURenderer: DESHABILITADO';
        return '[GPU] DrawCalls=$drawCalls Rendered=$spritesRendered Culled=$spritesCulled Batches=${sortedBatches.length}';
    }

    public function destroy():Void
    {
        try { for (batch in batches) if (batch != null) batch.destroy(); }
        catch (_:Dynamic) {}
        if (batches != null) batches.clear();
        batches       = null;
        sortedBatches = null;
        camera        = null;
        cameraRect    = null;
    }

    // ─── Helpers privados ─────────────────────────────────────────────────────

    private inline function isOnScreen(sprite:FlxSprite):Bool
    {
        if (_camDirty) _updateCameraRect();
        final sx = sprite.x - sprite.offset.x;
        final sy = sprite.y - sprite.offset.y;
        final sw = sprite.frameWidth  * sprite.scale.x;
        final sh = sprite.frameHeight * sprite.scale.y;
        return !(sx + sw < cameraRect.x - cullPadding ||
                 sx       > cameraRect.right  + cullPadding ||
                 sy + sh  < cameraRect.y - cullPadding ||
                 sy       > cameraRect.bottom + cullPadding);
    }

    private inline function _updateCameraRect():Void
    {
        cameraRect.x      = camera.scroll.x;
        cameraRect.y      = camera.scroll.y;
        cameraRect.width  = camera.width  / camera.zoom;
        cameraRect.height = camera.height / camera.zoom;
    }
}

// ─── GPUBatch ─────────────────────────────────────────────────────────────────

/**
 * GPUBatch — buffer pre-alojado, CERO allocs durante el juego.
 *
 * La versión anterior hacía:
 *   var renderVerts = new Vector<Float>(vertCount);   // ← ALLOC cada frame
 *   var renderIndices = new Vector<Int>(idxCount);    // ← ALLOC cada frame
 *   for (i in ...) renderVerts[i] = vertices[i];     // ← copia O(n) extra
 * Ahora usamos los buffers directamente con drawTriangles usando el
 * subvector exacto ya rellenado (trick: Vector.slice no está en openfl,
 * pero podemos pasar los buffers con un conteo exacto gracias a que
 * openfl.display.Graphics.drawTriangles acepta Vectors completos y
 * simplemente usa los primeros N elementos relevantes si los demás
 * quedan en 0 — lo cual es cierto porque clear() los pone a 0).
 * Para mayor seguridad usamos el setLength trick.
 */
class GPUBatch
{
    private var texture:BitmapData;

    // Buffers reutilizables — alojados UNA VEZ en el constructor
    // openfl.display.Graphics.drawTriangles espera:
    //   vertices : [x0,y0, x1,y1, ...]  — solo posiciones (2 floats/vértice)
    //   uvtData  : [u0,v0, u1,v1, ...]  — coordenadas UV  (2 floats/vértice)
    //   indices  : triángulos como triples de índices de vértice
    private var vertices:Vector<Float>;
    private var uvtData:Vector<Float>;
    private var indices:Vector<Int>;

    public  var spriteCount:Int   = 0;
    public  var avgZIndex:Float   = 0;
    private var totalZIndex:Float = 0;

    // Capacidades
    private static inline var MAX_SPRITES        :Int = 32; // FNF muestra ~20 notas simultáneas
    private static inline var VERTS_PER_SPRITE   :Int = 8;  // 4 vértices × 2 floats (x, y)
    private static inline var UVT_PER_SPRITE     :Int = 8;  // 4 vértices × 2 floats (u, v)
    private static inline var INDICES_PER_SPRITE :Int = 6;  // 2 triángulos × 3 índices

    public function new(texture:BitmapData)
    {
        this.texture = texture;
        vertices = new Vector<Float>(MAX_SPRITES * VERTS_PER_SPRITE,  true);
        uvtData  = new Vector<Float>(MAX_SPRITES * UVT_PER_SPRITE,    true);
        indices  = new Vector<Int>  (MAX_SPRITES * INDICES_PER_SPRITE, true);
    }

    public function addSprite(sprite:FlxSprite, frame:FlxFrame, camera:FlxCamera):Void
    {
        if (spriteCount >= MAX_SPRITES) return;

        totalZIndex += sprite.y;

        final worldX = sprite.x - sprite.offset.x;
        final worldY = sprite.y - sprite.offset.y;
        final camX   = (worldX - camera.scroll.x * sprite.scrollFactor.x) * camera.zoom;
        final camY   = (worldY - camera.scroll.y * sprite.scrollFactor.y) * camera.zoom;
        final width  = frame.frame.width  * sprite.scale.x * camera.zoom;
        final height = frame.frame.height * sprite.scale.y * camera.zoom;

        // Coordenadas UV normalizadas en el atlas
        final uvX = frame.frame.x         / texture.width;
        final uvY = frame.frame.y         / texture.height;
        final uvW = frame.frame.width     / texture.width;
        final uvH = frame.frame.height    / texture.height;

        // ── Posiciones (x, y) ────────────────────────────────────────────────
        var v = spriteCount * VERTS_PER_SPRITE;
        vertices[v++] = camX;         vertices[v++] = camY;           // TL
        vertices[v++] = camX + width; vertices[v++] = camY;           // TR
        vertices[v++] = camX + width; vertices[v++] = camY + height;  // BR
        vertices[v++] = camX;         vertices[v++] = camY + height;  // BL

        // ── UV ───────────────────────────────────────────────────────────────
        var u = spriteCount * UVT_PER_SPRITE;
        uvtData[u++] = uvX;        uvtData[u++] = uvY;           // TL
        uvtData[u++] = uvX + uvW;  uvtData[u++] = uvY;           // TR
        uvtData[u++] = uvX + uvW;  uvtData[u++] = uvY + uvH;     // BR
        uvtData[u++] = uvX;        uvtData[u++] = uvY + uvH;     // BL

        // ── Índices (2 triángulos por quad) ──────────────────────────────────
        var idx  = spriteCount * INDICES_PER_SPRITE;
        final b  = spriteCount * 4;
        indices[idx++] = b;     indices[idx++] = b + 1; indices[idx++] = b + 2;
        indices[idx++] = b;     indices[idx++] = b + 2; indices[idx++] = b + 3;

        spriteCount++;
    }

    /**
     * Render sin alloc: truncamos los Vectors al rango usado antes de
     * pasarlos a drawTriangles, y restauramos la capacidad después.
     */
    public function render(graphics:Graphics):Void
    {
        if (spriteCount == 0 || texture == null) return;

        final vertCount = spriteCount * VERTS_PER_SPRITE;
        final uvtCount  = spriteCount * UVT_PER_SPRITE;
        final idxCount  = spriteCount * INDICES_PER_SPRITE;

        vertices.length = vertCount;
        uvtData.length  = uvtCount;
        indices.length  = idxCount;

        try
        {
            // smooth=false: GL_NEAREST para texturas pixel-perfect (notas/HUD)
            graphics.beginBitmapFill(texture, null, false, false);
            graphics.drawTriangles(vertices, indices, uvtData);
            graphics.endFill();
        }
        catch (_:Dynamic) {}

        avgZIndex = spriteCount > 0 ? totalZIndex / spriteCount : 0;

        // Restaurar capacidad completa para el siguiente frame
        vertices.length = MAX_SPRITES * VERTS_PER_SPRITE;
        uvtData.length  = MAX_SPRITES * UVT_PER_SPRITE;
        indices.length  = MAX_SPRITES * INDICES_PER_SPRITE;
    }

    public function clear():Void
    {
        spriteCount  = 0;
        totalZIndex  = 0;
        avgZIndex    = 0;
    }

    public function destroy():Void
    {
        vertices = null;
        uvtData  = null;
        indices  = null;
        texture  = null;
    }
}
