package funkin.assets;

import openfl.display.BitmapData;
import openfl.geom.Rectangle;
import openfl.geom.Point;
import openfl.utils.ByteArray;
#if sys
import sys.FileSystem;
import sys.io.File;
import haxe.io.Bytes;
import haxe.io.BytesOutput;
import haxe.zip.Compress;
import haxe.zip.Uncompress;
#end

using StringTools;

/**
 * AssetOptimizer v2 — Optimiza assets SIN pérdida de calidad.
 *
 * ─── Técnicas (todas lossless) ────────────────────────────────────────────────
 *
 *  PNG (disco)
 *    • Elimina metadata chunks innecesarios (tEXt, zTXt, iTXt, tIME, bKGD…).
 *    • Funde todos los IDAT en uno solo.
 *    • Desfiltrado completo + re-filtrado óptimo POR FILA (elige entre None/
 *      Sub/Up/Average/Paeth el que produce el stream más comprimible).
 *    • Recompresión DEFLATE nivel 9 sobre datos re-filtrados.
 *    • Conversión RGBA→RGB en el propio archivo cuando ningún pixel usa alpha
 *      (reduce peso ~25% y VRAM necesaria).
 *    • Marca el archivo como ya-optimizado (chunk privado 'opTK') para saltar
 *      re-ejecuciones sin reprocesar.
 *
 *  ATLAS XML (disco)
 *    • Elimina comentarios XML.
 *    • Elimina atributos frameX/Y/Width/Height = "0" (redundantes en Sparrow).
 *    • Compacta espacios y líneas vacías.
 *
 *  OGG (disco)
 *    • Reemplaza el paquete Vorbis Comment con uno mínimo (vendor="", 0 tags).
 *      Lossless — solo elimina metadatos (título, artista, encoder…).
 *      Re-calcula el checksum CRC32 de la página OGG modificada.
 *
 *  BitmapData (runtime)
 *    • Conversión RGBA→RGB cuando no hay alpha real (ahorra ~25% VRAM).
 *    • Detección de alpha vía getPixels() en bloque — 4-5× más rápida que
 *      getPixel32() pixel a pixel.
 *    • trimTransparent() recorta bordes vacíos con lectura masiva.
 *
 * ─── Bugs corregidos respecto a v1 ───────────────────────────────────────────
 *    • CRÍTICO: getInt32/writeInt32 eran little-endian → PNGs escritos corruptos.
 *      Ahora usa _readBE32/_writeBE32 (big-endian correcto para PNG).
 *    • `else ;` inválido en Haxe (error de compilación) → eliminado.
 *    • OGG era un TODO sin implementar → implementado con CRC correcto.
 *    • _hasAlpha usaba getPixel32() lento → reemplazado por getPixels() en bloque.
 *
 * ─── Uso ──────────────────────────────────────────────────────────────────────
 *
 *  AssetOptimizer.optimizeMod("mods/mi_mod");
 *  AssetOptimizer.optimizeBaseAssets("assets/images");
 *  AssetOptimizer.optimizePNG("assets/images/ui/logo.png");
 *  trace(AssetOptimizer.lastStats.summary());
 *
 * @version 2.0.0
 */
class AssetOptimizer
{
	// ── Stats de la última ejecución ───────────────────────────────────────────
	public static var lastStats(default, null):OptimizerStats = new OptimizerStats();

	// ── Constantes PNG ─────────────────────────────────────────────────────────
	static final PNG_SIG = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

	// Chunks a conservar + 'opTK' (marcador privado: ancillary+private+safe-to-copy).
	static final PNG_KEEP = [
		'IHDR', 'PLTE', 'IDAT', 'IEND', 'tRNS', 'gAMA', 'cHRM', 'sRGB', 'sBIT', 'pHYs', 'opTK'
	];

	// ══════════════════════════════════════════════════════════════════════════
	// API PÚBLICA
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Optimiza TODOS los assets de un directorio de mod (PNG, XML, OGG).
	 * @param modPath   Raíz del mod (ej: "mods/mi_mod").
	 * @param recursive Buscar en subcarpetas.
	 */
	public static function optimizeMod(modPath:String, recursive:Bool = true):OptimizerStats
	{
		#if sys
		lastStats = new OptimizerStats();
		lastStats.rootPath = modPath;
		if (!FileSystem.exists(modPath))
		{
			trace('[AssetOptimizer] Mod no encontrado: $modPath');
			return lastStats;
		}
		trace('[AssetOptimizer] ── Optimizando mod: $modPath ──');
		for (sub in ['images', 'sounds', 'music'])
		{
			final p = '$modPath/$sub';
			if (FileSystem.exists(p))
				_walkDirectory(p, _processFile, recursive);
		}
		trace('[AssetOptimizer] ── Finalizado ──\n${lastStats.summary()}');
		#else
		trace('[AssetOptimizer] Solo disponible en targets nativos (sys).');
		#end
		return lastStats;
	}

	/** Optimiza los assets base del engine. */
	public static function optimizeBaseAssets(basePath:String = 'assets', recursive:Bool = true):OptimizerStats
	{
		#if sys
		lastStats = new OptimizerStats();
		lastStats.rootPath = basePath;
		if (FileSystem.exists(basePath))
			_walkDirectory(basePath, _processFile, recursive);
		trace('[AssetOptimizer] Base assets:\n${lastStats.summary()}');
		#end
		return lastStats;
	}

	/** Optimiza solo los PNG de un directorio. */
	public static function optimizeImages(dirPath:String, recursive:Bool = true):OptimizerStats
	{
		#if sys
		lastStats = new OptimizerStats();
		lastStats.rootPath = dirPath;
		if (FileSystem.exists(dirPath))
			_walkDirectory(dirPath, function(p:String)
			{
				if (p.endsWith('.png'))
					_optimizePNGFile(p);
			}, recursive);
		#end
		return lastStats;
	}

	/**
	 * Optimiza un único PNG in-place.
	 * @return Bytes ahorrados (positivo = redujo tamaño, 0 = ya óptimo o error).
	 */
	public static function optimizePNG(path:String):Int
	{
		#if sys
		if (!FileSystem.exists(path))
			return 0;
		return _optimizePNGFile(path);
		#else
		return 0;
		#end
	}

	/**
	 * Optimiza un atlas Sparrow en disco (PNG + XML companion).
	 * @param atlasPath Ruta al PNG del atlas.
	 */
	public static function optimizeSparrowAtlas(atlasPath:String):Int
	{
		#if sys
		var saved = 0;
		if (FileSystem.exists(atlasPath))
			saved += _optimizePNGFile(atlasPath);
		final xp = atlasPath.replace('.png', '.xml');
		if (FileSystem.exists(xp))
			saved += _optimizeXML(xp);
		return saved;
		#else
		return 0;
		#end
	}

	/**
	 * Optimiza un único OGG in-place (strip Vorbis Comment).
	 * @return Bytes ahorrados (positivo = redujo tamaño, 0 = ya óptimo o error).
	 */
	public static function optimizeOGG(path:String):Int
	{
		#if sys
		if (!FileSystem.exists(path))
			return 0;
		return _optimizeOGG(path);
		#else
		return 0;
		#end
	}

	/**
	 * Optimiza todos los OGG de un directorio de sonidos (SFX).
	 * Equivalente a `optimizeImages` pero para la carpeta `sounds/`.
	 * @param dirPath   Carpeta a procesar (ej: "mods/mi_mod/sounds").
	 * @param recursive Buscar en subcarpetas.
	 */
	public static function optimizeSounds(dirPath:String, recursive:Bool = true):OptimizerStats
	{
		#if sys
		lastStats = new OptimizerStats();
		lastStats.rootPath = dirPath;
		if (FileSystem.exists(dirPath))
			_walkDirectory(dirPath, function(p:String)
			{
				if (p.endsWith('.ogg'))
					_optimizeOGG(p);
			}, recursive);
		trace('[AssetOptimizer] Sounds: ${lastStats.summary()}');
		#end
		return lastStats;
	}

	/**
	 * Optimiza todos los OGG de un directorio de música.
	 * Equivalente a `optimizeSounds` pero semánticamente apunta a la carpeta `music/`.
	 * @param dirPath   Carpeta a procesar (ej: "mods/mi_mod/music").
	 * @param recursive Buscar en subcarpetas.
	 */
	public static function optimizeMusic(dirPath:String, recursive:Bool = true):OptimizerStats
	{
		#if sys
		lastStats = new OptimizerStats();
		lastStats.rootPath = dirPath;
		if (FileSystem.exists(dirPath))
			_walkDirectory(dirPath, function(p:String)
			{
				if (p.endsWith('.ogg'))
					_optimizeOGG(p);
			}, recursive);
		trace('[AssetOptimizer] Music: ${lastStats.summary()}');
		#end
		return lastStats;
	}

	// ── Runtime ───────────────────────────────────────────────────────────────

	/**
	 * Optimiza un BitmapData en runtime:
	 *   • Si no hay transparencia real convierte a RGB (~25% menos VRAM).
	 * Usa getPixels() en bloque — mucho más rápido que getPixel32() × N.
	 */
	public static function optimizeBitmapData(bitmap:BitmapData):BitmapData
	{
		if (bitmap == null)
			return bitmap;
		if (bitmap.transparent && !_hasAlphaFast(bitmap))
		{
			final rgb = new BitmapData(bitmap.width, bitmap.height, false, 0);
			rgb.copyPixels(bitmap, bitmap.rect, new Point(0, 0));
			bitmap.dispose();
			return rgb;
		}
		return bitmap;
	}

	/**
	 * Recorta márgenes transparentes de un BitmapData (runtime, no toca disco).
	 * @param bitmap   BitmapData fuente.
	 * @param outRect  Si se pasa, recibe el rectángulo recortado.
	 */
	public static function trimTransparent(bitmap:BitmapData, ?outRect:Rectangle):BitmapData
	{
		if (bitmap == null)
			return bitmap;
		final bounds = _getOpaqueBoundsFast(bitmap);
		if (bounds == null)
		{
			if (outRect != null)
			{
				outRect.x = 0;
				outRect.y = 0;
				outRect.width = 1;
				outRect.height = 1;
			}
			return new BitmapData(1, 1, true, 0x00000000);
		}
		if (bounds.x == 0 && bounds.y == 0 && bounds.width == bitmap.width && bounds.height == bitmap.height)
		{
			if (outRect != null)
				outRect.copyFrom(bounds);
			return bitmap;
		}
		final trimmed = new BitmapData(Std.int(bounds.width), Std.int(bounds.height), true, 0);
		trimmed.copyPixels(bitmap, bounds, new Point(0, 0));
		if (outRect != null)
			outRect.copyFrom(bounds);
		return trimmed;
	}

	// ══════════════════════════════════════════════════════════════════════════
	// INTERNALS — PNG (sys only)
	// ══════════════════════════════════════════════════════════════════════════
	#if sys
	static function _optimizePNGFile(path:String):Int
	{
		try
		{
			final original = File.getBytes(path);
			final originalSize = original.length;

			if (!_isPNG(original))
			{
				trace('[AssetOptimizer] No es un PNG válido: $path');
				return 0;
			}

			final chunks = _parsePNGChunks(original);
			if (chunks == null || chunks.length == 0)
				return 0;

			// Saltar archivos ya procesados (marcador 'opTK')
			for (c in chunks)
				if (c.name == 'opTK')
				{
					lastStats.pngSkipped++;
					return 0;
				}

			// Parsear IHDR (dimensiones + color type)
			final ihdr = _parseIHDR(chunks);

			// Pipeline: desfiltrado + re-filtrado óptimo + DEFLATE 9 + RGBA→RGB
			final optimizedChunks = _optimizePNGChunks(chunks, ihdr);

			// Añadir marcador de ya-optimizado
			optimizedChunks.push({name: 'opTK', data: Bytes.ofString('v2')});

			final optimized = _writePNG(optimizedChunks);
			if (optimized == null)
				return 0;

			final saved = originalSize - optimized.length;
			if (optimized.length <= originalSize)
			{
				File.saveBytes(path, optimized);
				lastStats.pngOptimized++;
				lastStats.bytesSaved += saved;
				if (saved > 0)
					trace('[AssetOptimizer] PNG ${_fname(path)}: ${_hb(originalSize)} → ${_hb(optimized.length)} (−${_hb(saved)})');
			}
			else
			{
				lastStats.pngSkipped++;
			}
			return saved;
		}
		catch (e:Dynamic)
		{
			trace('[AssetOptimizer] Error PNG "$path": $e');
			lastStats.errors++;
			return 0;
		}
	}

	// ── Chunk I/O — BIG-ENDIAN (PNG spec, RFC 2083) ───────────────────────────

	/** Lee un int32 en big-endian (formato correcto para PNG). */
	static inline function _readBE32(b:Bytes, pos:Int):Int
		return ((b.get(pos) & 0xFF) << 24) | ((b.get(pos + 1) & 0xFF) << 16) | ((b.get(pos + 2) & 0xFF) << 8) | (b.get(pos + 3) & 0xFF);

	/** Escribe un int32 en big-endian (formato correcto para PNG). */
	static inline function _writeBE32(out:BytesOutput, v:Int):Void
	{
		out.writeByte((v >>> 24) & 0xFF);
		out.writeByte((v >>> 16) & 0xFF);
		out.writeByte((v >>> 8) & 0xFF);
		out.writeByte(v & 0xFF);
	}

	static function _isPNG(b:Bytes):Bool
	{
		if (b.length < 8)
			return false;
		for (i in 0...8)
			if (b.get(i) != PNG_SIG[i])
				return false;
		return true;
	}

	static function _parsePNGChunks(bytes:Bytes):Null<Array<PNGChunk>>
	{
		final chunks:Array<PNGChunk> = [];
		var offset = 8; // saltar la firma PNG (8 bytes)
		while (offset + 12 <= bytes.length)
		{
			final len = _readBE32(bytes, offset); // BIG-ENDIAN
			final name = bytes.getString(offset + 4, 4);
			// Guardia de sanidad
			if (len < 0 || offset + 12 + len > bytes.length)
				break;
			final data = bytes.sub(offset + 8, len);
			offset += 12 + len; // 4 (len) + 4 (name) + len (data) + 4 (CRC)

			if (PNG_KEEP.indexOf(name) >= 0)
				chunks.push({name: name, data: data});
			// else: descartar tEXt, zTXt, iTXt, tIME, bKGD, hIST, pCAL…
		}
		return chunks.length > 0 ? chunks : null;
	}

	static function _writePNG(chunks:Array<PNGChunk>):Null<Bytes>
	{
		final out = new BytesOutput();
		for (b in PNG_SIG)
			out.writeByte(b);
		for (c in chunks)
		{
			final len = c.data.length;
			_writeBE32(out, len);
			out.writeString(c.name);
			out.write(c.data);
			// CRC32 cubre name(4) + data(len)
			final crcBuf = Bytes.alloc(4 + len);
			crcBuf.blit(0, Bytes.ofString(c.name), 0, 4);
			crcBuf.blit(4, c.data, 0, len);
			_writeBE32(out, _crc32(crcBuf));
		}
		return out.getBytes();
	}

	// ── IHDR ──────────────────────────────────────────────────────────────────

	static function _parseIHDR(chunks:Array<PNGChunk>):Null<IHDRInfo>
	{
		for (c in chunks)
		{
			if (c.name != 'IHDR' || c.data.length < 13)
				continue;
			return {
				width: _readBE32(c.data, 0),
				height: _readBE32(c.data, 4),
				bitDepth: c.data.get(8),
				colorType: c.data.get(9),
				interlaced: c.data.get(12) != 0
			};
		}
		return null;
	}

	/** Bytes por pixel según colorType y bitDepth del IHDR. */
	static function _bpp(colorType:Int, bitDepth:Int):Int
	{
		final sb = bitDepth <= 8 ? 1 : 2;
		return switch (colorType)
		{
			case 0: sb; // Grayscale
			case 2: 3 * sb; // RGB
			case 3: 1; // Palette (índice 1 byte)
			case 4: 2 * sb; // Grayscale+Alpha
			case 6: 4 * sb; // RGBA
			default: 1;
		};
	}

	// ── Pipeline principal de optimización ────────────────────────────────────

	/**
	 * Núcleo del optimizador PNG:
	 *  1. Fusiona y descomprime todos los IDAT.
	 *  2. Desfiltra completamente → pixels sin filtrar.
	 *  3. Si RGBA sin alpha real → convierte a RGB (strip canal A).
	 *  4. Re-filtra con el filtro óptimo por fila.
	 *  5. Recomprime con DEFLATE nivel 9.
	 *  6. Actualiza IHDR si cambió colorType.
	 */
	static function _optimizePNGChunks(chunks:Array<PNGChunk>, ihdr:Null<IHDRInfo>):Array<PNGChunk>
	{
		// 1. Fusionar todos los IDAT
		final idatOut = new BytesOutput();
		for (c in chunks)
			if (c.name == 'IDAT')
				idatOut.write(c.data);
		final compressed = idatOut.getBytes();
		if (compressed.length == 0)
			return chunks;

		// 2. Descomprimir IDAT (zlib/deflate)
		var filtered:Bytes = null;
		try
		{
			filtered = Uncompress.run(compressed);
		}
		catch (e:Dynamic)
		{
			trace('[AssetOptimizer] Decompress IDAT error: $e');
			return chunks;
		}

		// Sin IHDR o imagen interlaced: solo recomprimir con nivel 9
		if (ihdr == null || ihdr.interlaced)
			return _replaceIDAT(chunks, _best(Compress.run(filtered, 9), compressed));

		final bpp = _bpp(ihdr.colorType, ihdr.bitDepth);
		final stride = ihdr.width * bpp;
		if (filtered.length < (stride + 1) * ihdr.height)
			return _replaceIDAT(chunks, _best(Compress.run(filtered, 9), compressed));

		// 3. Desfiltar → pixels sin filtrar
		final orig = _defilter(filtered, ihdr.height, stride, bpp);

		// 4. Conversión RGBA→RGB si no hay transparencia real
		var finalOrig = orig;
		var finalBpp = bpp;
		var finalColorType = ihdr.colorType;

		if (ihdr.colorType == 6 && !_rawHasAlpha(orig, ihdr.width, ihdr.height))
		{
			finalOrig = _stripAlphaChannel(orig, ihdr.width, ihdr.height);
			finalBpp = 3;
			finalColorType = 2;
			trace('[AssetOptimizer] RGBA→RGB: ${ihdr.width}×${ihdr.height}');
		}

		// 5. Re-filtrar con filtro óptimo por fila
		final finalStride = ihdr.width * finalBpp;
		final refiltered = _refilterOptimal(finalOrig, ihdr.height, finalStride, finalBpp);

		// 6. Comprimir nivel 9 (o mantener original si es mejor)
		var newIDATData:Bytes = null;
		try
		{
			newIDATData = _best(Compress.run(refiltered, 9), compressed);
		}
		catch (_:Dynamic)
		{
			newIDATData = compressed;
		}

		// Reconstruir chunks con nuevo IDAT (e IHDR actualizado si hubo conversión)
		final result:Array<PNGChunk> = [];
		var idatDone = false;
		for (c in chunks)
		{
			if (c.name == 'IDAT')
			{
				if (!idatDone)
				{
					result.push({name: 'IDAT', data: newIDATData});
					idatDone = true;
				}
				// else: descartar IDAT adicionales (ya fusionados)
			}
			else if (c.name == 'IHDR' && finalColorType != ihdr.colorType)
			{
				// Actualizar colorType en IHDR
				final newHdr = Bytes.alloc(13);
				newHdr.blit(0, c.data, 0, 13);
				newHdr.set(9, finalColorType);
				result.push({name: 'IHDR', data: newHdr});
			}
			else
			{
				result.push(c);
			}
		}
		if (!idatDone)
			result.push({name: 'IDAT', data: newIDATData});

		// Garantizar IEND al final
		if (result.length == 0 || result[result.length - 1].name != 'IEND')
			result.push({name: 'IEND', data: Bytes.alloc(0)});

		return result;
	}

	/** Devuelve el Bytes más corto entre a y b. */
	static inline function _best(a:Bytes, b:Bytes):Bytes
		return a.length <= b.length ? a : b;

	/** Sustituye todos los IDAT por un único IDAT con newData. */
	static function _replaceIDAT(chunks:Array<PNGChunk>, newData:Bytes):Array<PNGChunk>
	{
		final result:Array<PNGChunk> = [];
		var done = false;
		for (c in chunks)
		{
			if (c.name == 'IDAT')
			{
				if (!done)
				{
					result.push({name: 'IDAT', data: newData});
					done = true;
				}
			}
			else
				result.push(c);
		}
		if (!done)
			result.push({name: 'IDAT', data: newData});
		return result;
	}

	// ── PNG Defilter ──────────────────────────────────────────────────────────

	/**
	 * Desfiltrado PNG completo (RFC 2083 §6.2).
	 * Entrada: bytes filtrados = (1 filtro + stride datos) × height
	 * Salida:  bytes sin filtrar = (stride) × height
	 */
	static function _defilter(filtered:Bytes, height:Int, stride:Int, bpp:Int):Bytes
	{
		final orig = Bytes.alloc(height * stride);
		final rowLen = stride + 1;

		for (y in 0...height)
		{
			final ft = filtered.get(y * rowLen); // tipo de filtro
			final rowIn = y * rowLen + 1; // inicio datos filtrados
			final rowOut = y * stride; // inicio datos reconstruidos
			final priorOff = (y > 0) ? (y - 1) * stride : -1;

			for (x in 0...stride)
			{
				final fv = filtered.get(rowIn + x) & 0xFF;
				final a = (x >= bpp) ? (orig.get(rowOut + x - bpp) & 0xFF) : 0;
				final b = (priorOff >= 0) ? (orig.get(priorOff + x) & 0xFF) : 0;
				final c = (priorOff >= 0 && x >= bpp) ? (orig.get(priorOff + x - bpp) & 0xFF) : 0;
				orig.set(rowOut + x, (fv + switch (ft)
				{
					case 1: a;
					case 2: b;
					case 3: (a + b) >> 1;
					case 4: _paeth(a, b, c);
					default: 0; // case 0 (None)
				}) & 0xFF);
			}
		}
		return orig;
	}

	// ── PNG Re-filter óptimo ──────────────────────────────────────────────────

	/**
	 * Re-filtra datos de imagen eligiendo el mejor filtro por fila.
	 * Heurística: elige el filtro cuya suma de min(v, 256−v) es menor
	 * → maximiza la compresibilidad DEFLATE.
	 *
	 * Entrada: orig = datos SIN filtrar (height × stride)
	 * Salida:  stream PNG filtrado = (1 + stride) × height
	 */
	static function _refilterOptimal(orig:Bytes, height:Int, stride:Int, bpp:Int):Bytes
	{
		final rowLen = stride + 1;
		final out = Bytes.alloc(height * rowLen);
		// Buffers reutilizables para los 5 filtros
		final fb:Array<Bytes> = [for (_ in 0...5) Bytes.alloc(stride)];

		for (y in 0...height)
		{
			final rowOff = y * stride;
			final priorOff = (y > 0) ? (y - 1) * stride : -1;

			var bestFt = 0;
			var bestScore = 0x7FFFFFFF;

			for (ft in 0...5)
			{
				var score = 0;
				for (x in 0...stride)
				{
					final o = orig.get(rowOff + x) & 0xFF;
					final a = (x >= bpp) ? (orig.get(rowOff + x - bpp) & 0xFF) : 0;
					final b = (priorOff >= 0) ? (orig.get(priorOff + x) & 0xFF) : 0;
					final c = (priorOff >= 0 && x >= bpp) ? (orig.get(priorOff + x - bpp) & 0xFF) : 0;
					final v:Int = (o - switch (ft)
					{
						case 1: a;
						case 2: b;
						case 3: (a + b) >> 1;
						case 4: _paeth(a, b, c);
						default: 0;
					}) & 0xFF;
					fb[ft].set(x, v);
					score += (v > 128) ? (256 - v) : v;
				}
				if (score < bestScore)
				{
					bestScore = score;
					bestFt = ft;
				}
			}

			final outOff = y * rowLen;
			out.set(outOff, bestFt);
			out.blit(outOff + 1, fb[bestFt], 0, stride);
		}
		return out;
	}

	/** Predictor Paeth (RFC 2083 §9.4). */
	static inline function _paeth(a:Int, b:Int, c:Int):Int
	{
		final p = a + b - c;
		final pa = p > a ? p - a : a - p;
		final pb = p > b ? p - b : b - p;
		final pc = p > c ? p - c : c - p;
		if (pa <= pb && pa <= pc)
			return a;
		if (pb <= pc)
			return b;
		return c;
	}

	// ── RGBA → RGB ────────────────────────────────────────────────────────────

	/** Comprueba si algún pixel en datos sin filtrar tiene alpha < 255. */
	static function _rawHasAlpha(orig:Bytes, width:Int, height:Int):Bool
	{
		final stride = width * 4;
		for (y in 0...height)
		{
			final rowOff = y * stride;
			for (x in 0...width)
				if ((orig.get(rowOff + x * 4 + 3) & 0xFF) < 255)
					return true;
		}
		return false;
	}

	/** Extrae RGB de datos RGBA sin filtrar → datos RGB sin filtrar. */
	static function _stripAlphaChannel(orig:Bytes, width:Int, height:Int):Bytes
	{
		final rgb = Bytes.alloc(height * width * 3);
		final stride4 = width * 4;
		final stride3 = width * 3;
		for (y in 0...height)
			for (x in 0...width)
			{
				final s = y * stride4 + x * 4;
				final d = y * stride3 + x * 3;
				rgb.set(d, orig.get(s));
				rgb.set(d + 1, orig.get(s + 1));
				rgb.set(d + 2, orig.get(s + 2));
			}
		return rgb;
	}

	// ── XML ───────────────────────────────────────────────────────────────────

	static function _optimizeXML(path:String):Int
	{
		try
		{
			final original = File.getContent(path);
			final origSize = original.length;

			// Eliminar comentarios XML
			var opt = ~/<!--[\s\S]*?-->/g.replace(original, '');
			// Eliminar atributos con valor "0" por defecto en Sparrow atlas
			opt = ~/\s+frameX="0"/g.replace(opt, '');
			opt = ~/\s+frameY="0"/g.replace(opt, '');
			opt = ~/\s+frameWidth="0"/g.replace(opt, '');
			opt = ~/\s+frameHeight="0"/g.replace(opt, '');
			// Comprimir espacios múltiples
			opt = ~/[ \t]{2,}/g.replace(opt, ' ');
			// Eliminar líneas vacías
			opt = ~/\n\s*\n/g.replace(opt, '\n');
			// Trim línea a línea
			opt = opt.split('\n')
				.map(function(l) return l.trim())
				.filter(function(l) return l.length > 0)
				.join('\n');

			final saved = origSize - opt.length;
			if (saved > 0)
			{
				File.saveContent(path, opt);
				lastStats.xmlOptimized++;
				lastStats.bytesSaved += saved;
				trace('[AssetOptimizer] XML ${_fname(path)}: −${_hb(saved)}');
			}
			return saved;
		}
		catch (e:Dynamic)
		{
			trace('[AssetOptimizer] Error XML "$path": $e');
			lastStats.errors++;
			return 0;
		}
	}

	// ── OGG — Vorbis Comment strip ────────────────────────────────────────────

	/**
	 * Reemplaza el paquete Vorbis Comment con uno mínimo (vendor="", 0 tags).
	 * Recalcula el checksum CRC32 OGG de la página afectada.
	 * 100% lossless — solo elimina metadatos embebidos en el container.
	 */
	static function _optimizeOGG(path:String):Int
	{
		try
		{
			final data = File.getBytes(path);
			final origLen = data.length;
			final result = _stripVorbisComment(data);

			if (result == null || result.length >= origLen)
			{
				lastStats.oggSkipped++;
				return 0;
			}

			final saved = origLen - result.length;
			File.saveBytes(path, result);
			lastStats.oggOptimized++;
			lastStats.bytesSaved += saved;
			trace('[AssetOptimizer] OGG ${_fname(path)}: −${_hb(saved)}');
			return saved;
		}
		catch (e:Dynamic)
		{
			trace('[AssetOptimizer] Error OGG "$path": $e');
			lastStats.errors++;
			return 0;
		}
	}

	/**
	 * Recorre las páginas OGG buscando el paquete Vorbis Comment (0x03 + "vorbis")
	 * y lo reemplaza con uno mínimo. Devuelve null si no es un OGG Vorbis válido
	 * o si no se encontró el comment packet.
	 */
	static function _stripVorbisComment(data:Bytes):Null<Bytes>
	{
		// Paquete Vorbis Comment mínimo:
		//   0x03 "vorbis" [4 bytes LE: vendor_len=0] [4 bytes LE: comment_count=0] [framing=1]
		final minCmt = Bytes.alloc(16);
		minCmt.set(0, 0x03);
		final vStr = [0x76, 0x6F, 0x72, 0x62, 0x69, 0x73]; // "vorbis"
		for (i in 0...6)
			minCmt.set(1 + i, vStr[i]);
		// bytes 7-14 = 0 (vendor_len y comment_count, LE int32)
		minCmt.set(15, 0x01); // framing bit

		var pos = 0;
		var foundComment = false;
		final out = new BytesOutput();

		while (pos + 27 <= data.length)
		{
			// Verificar captura OggS
			if (data.get(pos) != 0x4F || data.get(pos + 1) != 0x67 || data.get(pos + 2) != 0x67 || data.get(pos + 3) != 0x53)
				return null;

			final numSegs = data.get(pos + 26);
			if (pos + 27 + numSegs > data.length)
				return null;

			// Calcular longitud de datos de la página
			var pageDataLen = 0;
			for (i in 0...numSegs)
				pageDataLen += data.get(pos + 27 + i);

			final headerLen = 27 + numSegs;
			final pageEnd = pos + headerLen + pageDataLen;
			if (pageEnd > data.length)
				return null;

			// ¿Es esta la página del Vorbis Comment? (empieza con 0x03 "vorbis")
			final isComment = !foundComment
				&& pageDataLen >= 7
				&& data.get(pos + headerLen) == 0x03
				&& data.get(pos + headerLen + 1) == 0x76
				&& data.get(pos + headerLen + 2) == 0x6F
				&& data.get(pos + headerLen + 3) == 0x72
				&& data.get(pos + headerLen + 4) == 0x62
				&& data.get(pos + headerLen + 5) == 0x69
				&& data.get(pos + headerLen + 6) == 0x73;

			if (isComment)
			{
				foundComment = true;
				_writeOggPage(out, data, pos, minCmt);
			}
			else
			{
				// Copiar página sin cambios
				for (i in 0...headerLen + pageDataLen)
					out.writeByte(data.get(pos + i));
			}

			pos = pageEnd;
		}

		return foundComment ? out.getBytes() : null;
	}

	/**
	 * Escribe una página OGG con newData como payload.
	 * Copia los campos del header original (granule position, serial number, etc.),
	 * reconstruye la tabla de segmentos y recalcula el CRC32 OGG.
	 */
	static function _writeOggPage(out:BytesOutput, orig:Bytes, origPos:Int, newData:Bytes):Void
	{
		final dataLen = newData.length;

		// Calcular tabla de segmentos (lacing values)
		// Un paquete de N bytes: floor(N/255) segmentos de 255 + 1 de N%255 (o 0 si múltiplo)
		final fullSegs = Math.floor(dataLen / 255);
		final remainder = dataLen - fullSegs * 255;
		final numSegs = fullSegs + 1; // +1 siempre (el terminador)
		final lastLace = remainder; // si remainder==0 → terminador de paquete = 0

		final headerLen = 27 + numSegs;
		final page = Bytes.alloc(headerLen + dataLen);

		// Copiar los primeros 27 bytes del header original (version, type, granule, serial, seq)
		page.blit(0, orig, origPos, 27);
		// Borrar CRC previo (debe ser 0 al calcular el nuevo)
		page.set(22, 0);
		page.set(23, 0);
		page.set(24, 0);
		page.set(25, 0);
		// Nuevo número de segmentos
		page.set(26, numSegs);
		// Tabla de lacing
		for (i in 0...fullSegs)
			page.set(27 + i, 255);
		page.set(27 + fullSegs, lastLace);
		// Datos del paquete
		page.blit(headerLen, newData, 0, dataLen);

		// Calcular CRC32 OGG y escribir en bytes 22-25
		final crc = _oggCRC32(page);
		page.set(22, (crc) & 0xFF);
		page.set(23, (crc >>> 8) & 0xFF);
		page.set(24, (crc >>> 16) & 0xFF);
		page.set(25, (crc >>> 24) & 0xFF);

		for (i in 0...page.length)
			out.writeByte(page.get(i));
	}

	// CRC32 OGG: polinomio 0x04c11db7, no reflejado, init=0, no XOR final
	static var _oggCrcTab:Array<Int> = null;

	static function _buildOggCRCTable():Void
	{
		_oggCrcTab = [];
		for (i in 0...256)
		{
			var crc:Int = i << 24;
			for (_ in 0...8)
				crc = ((crc & 0x80000000) != 0) ? ((crc << 1) ^ 0x04c11db7) : (crc << 1);
			_oggCrcTab.push(crc & 0xFFFFFFFF);
		}
	}

	static function _oggCRC32(b:Bytes):Int
	{
		if (_oggCrcTab == null)
			_buildOggCRCTable();
		var crc:Int = 0;
		for (i in 0...b.length)
			crc = ((crc << 8) ^ _oggCrcTab[((crc >>> 24) ^ b.get(i)) & 0xFF]) & 0xFFFFFFFF;
		return crc;
	}

	// ── Walker ────────────────────────────────────────────────────────────────

	static function _walkDirectory(dir:String, fn:String->Void, recursive:Bool):Void
	{
		if (!FileSystem.exists(dir) || !FileSystem.isDirectory(dir))
			return;
		for (entry in FileSystem.readDirectory(dir))
		{
			final fullPath = '$dir/$entry';
			if (FileSystem.isDirectory(fullPath))
			{
				if (recursive)
					_walkDirectory(fullPath, fn, recursive);
			}
			else
				fn(fullPath);
		}
	}

	static function _processFile(path:String):Void
	{
		if (path.endsWith('.png'))
			_optimizePNGFile(path);
		else if (path.endsWith('.xml'))
			_optimizeXML(path);
		else if (path.endsWith('.ogg'))
			_optimizeOGG(path);
	}
	#end // sys

	// ══════════════════════════════════════════════════════════════════════════
	// INTERNALS — BitmapData (runtime, no necesita sys)
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Detección rápida de alpha mediante getPixels() en bloque.
	 * getPixels() devuelve ARGB por pixel: byte 0=A, 1=R, 2=G, 3=B.
	 * Leer solo el byte alpha cada 4 posiciones → 4-5× más rápido que getPixel32().
	 */
	static function _hasAlphaFast(bitmap:BitmapData):Bool
	{
		if (!bitmap.transparent)
			return false;
		try
		{
			final pixels = bitmap.getPixels(bitmap.rect);
			final len = pixels.length;
			var i = 0;
			while (i < len)
			{
				if ((pixels[i] & 0xFF) < 0xFF)
					return true;
				i += 4; // saltar R, G, B y avanzar al siguiente alpha
			}
			return false;
		}
		catch (_:Dynamic)
		{
		}
		// Fallback: muestreo cada 2 pixels si getPixels() no está disponible
		var x = 0;
		while (x < bitmap.width)
		{
			var y = 0;
			while (y < bitmap.height)
			{
				if ((bitmap.getPixel32(x, y) >>> 24) < 255)
					return true;
				y += 2;
			}
			x += 2;
		}
		return false;
	}

	/**
	 * Bounding box de pixels opacos usando getPixels() en bloque.
	 * Evita el overhead de getPixel32() por pixel en imágenes grandes.
	 */
	static function _getOpaqueBoundsFast(bitmap:BitmapData):Null<Rectangle>
	{
		final w = bitmap.width;
		final h = bitmap.height;
		var minX = w;
		var minY = h;
		var maxX = 0;
		var maxY = 0;
		var found = false;
		try
		{
			final pixels = bitmap.getPixels(bitmap.rect);
			for (y in 0...h)
				for (x in 0...w)
				{
					final idx = (y * w + x) * 4; // byte alpha en ARGB
					if ((pixels[idx] & 0xFF) > 0)
					{
						if (x < minX)
							minX = x;
						if (y < minY)
							minY = y;
						if (x > maxX)
							maxX = x;
						if (y > maxY)
							maxY = y;
						found = true;
					}
				}
		}
		catch (_:Dynamic)
		{
			// Fallback pixel a pixel
			for (y in 0...h)
				for (x in 0...w)
					if ((bitmap.getPixel32(x, y) >>> 24) > 0)
					{
						if (x < minX)
							minX = x;
						if (y < minY)
							minY = y;
						if (x > maxX)
							maxX = x;
						if (y > maxY)
							maxY = y;
						found = true;
					}
		}
		if (!found)
			return null;
		return new Rectangle(minX, minY, maxX - minX + 1, maxY - minY + 1);
	}

	// ── CRC32 PNG (reflejado, polinomio 0xEDB88320) ───────────────────────────
	static var _crcTable:Array<Int> = null;

	static function _buildCRCTable():Void
	{
		_crcTable = [];
		for (n in 0...256)
		{
			var c = n;
			for (_ in 0...8)
				c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
			_crcTable.push(c);
		}
	}

	static function _crc32(data:Bytes):Int
	{
		if (_crcTable == null)
			_buildCRCTable();
		var crc = 0xFFFFFFFF;
		for (i in 0...data.length)
			crc = _crcTable[(crc ^ data.get(i)) & 0xFF] ^ (crc >>> 8);
		return (crc ^ 0xFFFFFFFF);
	}

	// ── Helpers ───────────────────────────────────────────────────────────────

	static inline function _fname(p:String):String
	{
		final parts = p.split('/');
		return parts[parts.length - 1];
	}

	static inline function _hb(b:Int):String
	{
		if (b < 1024)
			return '$b B';
		if (b < 1048576)
			return '${Math.round(b / 1024)} KB';
		return '${Math.round(b / 104857.6) / 10} MB';
	}
}

// ── Tipos privados ────────────────────────────────────────────────────────────

private typedef PNGChunk =
{
	name:String,
	data:haxe.io.Bytes
}

private typedef IHDRInfo =
{
	width:Int,
	height:Int,
	bitDepth:Int,
	colorType:Int, // 0=Gray 2=RGB 3=Palette 4=GrayAlpha 6=RGBA
	interlaced:Bool
}

// ── OptimizerStats ────────────────────────────────────────────────────────────

/**
 * Estadísticas acumuladas de una pasada del optimizador.
 */
class OptimizerStats
{
	public var rootPath:String = '';
	public var pngOptimized:Int = 0;
	public var pngSkipped:Int = 0;
	public var xmlOptimized:Int = 0;
	/** OGGs optimizados (sounds + music combinados). */
	public var oggOptimized:Int = 0;
	/** OGGs saltados porque ya eran óptimos. */
	public var oggSkipped:Int = 0;
	public var bytesSaved:Int = 0;
	public var errors:Int = 0;

	public function new()
	{
	}

	public function summary():String
	{
		final saved = bytesSaved > 0 ? _hb(bytesSaved) : '0 B';
		return '[AssetOptimizer] Raíz: $rootPath\n'
			+ '  PNGs:    $pngOptimized opt  /  $pngSkipped sin cambios\n'
			+ '  XMLs:    $xmlOptimized opt\n'
			+ '  OGGs:    $oggOptimized opt  /  $oggSkipped sin cambios\n'
			+ '  Errores: $errors\n'
			+ '  Total ahorrado: $saved';
	}

	static inline function _hb(b:Int):String
	{
		if (b < 1024)
			return '$b B';
		if (b < 1048576)
			return '${Math.round(b / 1024)} KB';
		return '${Math.round(b / 104857.6) / 10} MB';
	}
}
