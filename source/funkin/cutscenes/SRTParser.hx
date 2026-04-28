package funkin.cutscenes;

/**
 * SRTParser — Parser de archivos de subtítulos en formato SubRip (.srt).
 *
 * Convierte un archivo .srt en un array de SRTEntry con tiempos en
 * milisegundos, listo para sincronizar con VideoManager.
 *
 * Formato .srt esperado:
 *
 *   1
 *   00:00:01,500 --> 00:00:04,000
 *   Primera línea de texto
 *   Segunda línea
 *
 *   2
 *   00:00:05,000 --> 00:00:07,500
 *   Otra línea
 *
 * ─── Uso ───────────────────────────────────────────────────────────────────
 *
 *   var entries = SRTParser.parseFile("assets/videos/intro.srt");
 *   var entries = SRTParser.parseString(rawText);
 *
 *   // Obtener subtítulo activo en un instante dado (ms):
 *   var current = SRTParser.getEntryAt(entries, videoTimeMs);
 *
 */
using StringTools;

class SRTParser {
	// ══════════════════════════════════════════════════════════════════════════
	//  API pública
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Carga y parsea un archivo .srt desde disco.
	 * @param path  Ruta absoluta o relativa al archivo .srt.
	 * @return      Array de entradas ordenadas por startMs, o [] si falla.
	 */
	public static function parseFile(path:String):Array<SRTEntry> {
		#if sys
		try {
			if (!sys.FileSystem.exists(path))
				return [];
			return parseString(sys.io.File.getContent(path));
		} catch (_) {
			return [];
		}
		#else
		try {
			var content = openfl.utils.Assets.getText(path);
			return content != null ? parseString(content) : [];
		} catch (_) {
			return [];
		}
		#end
	}

	/**
	 * Parsea el contenido de un .srt ya cargado como String.
	 * Tolerante a saltos de línea Windows (\r\n), Unix (\n) y Mac (\r).
	 * Ignora entradas malformadas en silencio.
	 */
	public static function parseString(content:String):Array<SRTEntry> {
		if (content == null || content.length == 0)
			return [];

		// Normalizar saltos de línea
		content = content.split('\r\n').join('\n').split('\r').join('\n');

		// Separar bloques por línea en blanco
		final blocks = content.split('\n\n');
		final result:Array<SRTEntry> = [];

		for (block in blocks) {
			var entry = _parseBlock(block.trim());
			if (entry != null)
				result.push(entry);
		}

		// Ordenar por tiempo de inicio (normalmente ya está en orden)
		result.sort(function(a, b) return a.startMs - b.startMs);
		return result;
	}

	/**
	 * Devuelve la entrada activa para el instante `timeMs` dado, o null si
	 * no hay ningún subtítulo activo en ese instante.
	 *
	 * @param entries  Array devuelto por parseFile/parseString.
	 * @param timeMs   Tiempo actual del video en milisegundos.
	 */
	public static function getEntryAt(entries:Array<SRTEntry>, timeMs:Int):Null<SRTEntry> {
		if (entries == null || entries.length == 0)
			return null;

		// Búsqueda binaria para eficiencia con archivos grandes
		var lo = 0;
		var hi = entries.length - 1;

		while (lo <= hi) {
			final mid = (lo + hi) >> 1;
			final e = entries[mid];

			if (timeMs < e.startMs)
				hi = mid - 1;
			else if (timeMs > e.endMs)
				lo = mid + 1;
			else
				return e; // dentro del rango [startMs, endMs]
		}
		return null;
	}

	/**
	 * Devuelve la ruta .srt esperada dado el path de un video .mp4.
	 * Prueba también una sub-carpeta "subs/" junto al video.
	 *
	 * Ejemplo: "assets/videos/intro.mp4" → "assets/videos/intro.srt"
	 */
	public static function srtPathForVideo(videoPath:String):Null<String> {
		if (videoPath == null)
			return null;

		// Mismo directorio, misma base, extensión .srt
		final base = videoPath.endsWith('.mp4') ? videoPath.substr(0, videoPath.length - 4) : videoPath;

		final candidates = [base + '.srt', base + '.SRT',];

		// También buscar en sub-carpeta subs/
		final slash = Std.int(Math.max(base.lastIndexOf('/'), base.lastIndexOf('\\')));
		if (slash >= 0) {
			final dir = base.substr(0, slash + 1);
			final name = base.substr(slash + 1);
			candidates.push(dir + 'subs/' + name + '.srt');
		}

		#if sys
		for (c in candidates)
			if (sys.FileSystem.exists(c))
				return c;
		#else
		for (c in candidates)
			if (openfl.utils.Assets.exists(c))
				return c;
		#end

		return null;
	}

	/**
	 * Elimina etiquetas HTML/SRT del texto de un subtítulo.
	 * Soporta: <i>, <b>, <u>, <font color="...">, <c.clase>, {\an8}, etc.
	 *
	 * Ejemplo: "<i>Hello</i> <font color=\"#ff0\">World</font>" → "Hello World"
	 */
	public static function stripTags(text:String):String {
		if (text == null || text.length == 0)
			return text;

		// Eliminar bloques de estilo ASS/SSA entre llaves: {\an8}  {\pos(x,y)}
		var result = ~/\{[^}]*\}/g.replace(text, '');

		// Eliminar etiquetas HTML estándar: <i>, </i>, <b>, <font color="...">, etc.
		result = ~/<[^>]+>/g.replace(result, '');

		// Limpiar espacios dobles y recortar
		result = ~/  +/g.replace(result, ' ');
		return result.trim();
	}

	/**
	 * Parsea y devuelve entradas limpias (sin tags HTML/SRT en el texto).
	 * Equivalente a parseFile() + stripTags() sobre cada entrada.
	 */
	public static function parseFileClean(path:String):Array<SRTEntry> {
		var entries = parseFile(path);
		for (e in entries)
			e.text = stripTags(e.text);
		return entries;
	}

	/**
	 * Devuelve todas las rutas SRT candidatas para un video dado, incluyendo
	 * variantes de idioma (intro.es.srt, intro.en.srt…).
	 * Útil para construir un selector de pistas en el futuro.
	 */
	public static function findAllSrtPaths(videoPath:String):Array<String> {
		if (videoPath == null)
			return [];

		final base = videoPath.endsWith('.mp4') ? videoPath.substr(0, videoPath.length - 4) : videoPath;

		final slash = Std.int(Math.max(base.lastIndexOf('/'), base.lastIndexOf('\\\\')));
		final dir = slash >= 0 ? base.substr(0, slash + 1) : '';
		final name = slash >= 0 ? base.substr(slash + 1) : base;

		var found:Array<String> = [];

		// Candidatos directos
		var candidates = [
			base + '.srt',
			base + '.SRT',
			dir + 'subs/' + name + '.srt',
			dir + 'subtitles/' + name + '.srt',
		];

		// Variantes de idioma para los 12 idiomas soportados en opciones
		var langCodes = ['es', 'en', 'fr', 'de', 'it', 'pt', 'ja', 'ko', 'zh', 'ru', 'ar'];
		for (lang in langCodes) {
			candidates.push(base + '.$lang.srt');
			candidates.push(dir + 'subs/' + name + '.$lang.srt');
		}

		#if sys
		for (c in candidates)
			if (sys.FileSystem.exists(c) && found.indexOf(c) < 0)
				found.push(c);
		#else
		for (c in candidates)
			if (openfl.utils.Assets.exists(c) && found.indexOf(c) < 0)
				found.push(c);
		#end

		return found;
	}

	/**
	 * Parsea un único bloque SRT (número, timestamps, texto).
	 * Devuelve null si el bloque no tiene el formato esperado.
	 */
	static function _parseBlock(block:String):Null<SRTEntry> {
		if (block == null || block.length == 0)
			return null;

		final lines = block.split('\n');
		if (lines.length < 2)
			return null;

		// Buscar la línea de timestamps (puede estar en la línea 0 si falta el número)
		var timeLine = -1;
		for (i in 0...lines.length) {
			if (lines[i].indexOf('-->') >= 0) {
				timeLine = i;
				break;
			}
		}
		if (timeLine < 0)
			return null;

		// Parsear índice (línea anterior al timestamp, si existe)
		var index = 0;
		if (timeLine > 0) {
			final idx = Std.parseInt(lines[timeLine - 1].trim());
			if (idx != null)
				index = idx;
		}

		// Parsear timestamps  "00:01:23,456 --> 00:01:27,890"
		final parts = lines[timeLine].split('-->');
		if (parts.length < 2)
			return null;

		final startMs = _parseTimestamp(parts[0].trim());
		final endMs = _parseTimestamp(parts[1].trim());
		if (startMs < 0 || endMs < 0 || endMs < startMs)
			return null;

		// El texto son todas las líneas después del timestamp
		final textLines = lines.slice(timeLine + 1);
		final text = textLines.join('\n').trim();
		if (text.length == 0)
			return null;

		return {
			index: index,
			startMs: startMs,
			endMs: endMs,
			text: text
		};
	}

	/**
	 * Convierte "HH:MM:SS,mmm" o "HH:MM:SS.mmm" a milisegundos.
	 * Devuelve -1 en caso de error.
	 */
	static function _parseTimestamp(s:String):Int {
		if (s == null)
			return -1;

		// Normalizar separador decimal , → .
		s = s.split(',').join('.');

		// Formato esperado: HH:MM:SS.mmm
		final colParts = s.split(':');
		if (colParts.length < 3)
			return -1;

		final h = Std.parseInt(colParts[0]);
		final m = Std.parseInt(colParts[1]);
		final dotParts = colParts[2].split('.');
		final sec = Std.parseInt(dotParts[0]);
		final ms = dotParts.length > 1 ? Std.parseInt(dotParts[1].substr(0, 3)) : 0;

		if (h == null || m == null || sec == null || ms == null)
			return -1;

		return (h * 3600 + m * 60 + sec) * 1000 + ms;
	}
}

// ── Entrada de subtítulo parseada ─────────────────────────────────────────────

typedef SRTEntry = {
	/** Número de secuencia del bloque SRT (1-based). */
	var index:Int;

	/** Tiempo de inicio en ms. */
	var startMs:Int;

	/** Tiempo de fin en ms. */
	var endMs:Int;

	/** Texto del subtítulo (puede contener \n para varias líneas). */
	var text:String;
}
