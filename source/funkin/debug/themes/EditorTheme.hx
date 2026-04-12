package funkin.debug.themes;

import coolui.CoolUITheme;

import haxe.Json;
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/**
 * Datos de un tema de editor.
 * Todos los colores son enteros ARGB (0xFFRRGGBB).
 */
typedef ThemeData =
{
	var name:String;

	// ── Fondos ────────────────────────────────────────────────────────────────
	var bgDark:Int;       // fondo del canvas / ventana principal
	var bgPanel:Int;      // fondo de paneles laterales
	var bgPanelAlt:Int;   // fondo de encabezados / filas alternas
	var bgHover:Int;      // botones de toolbar, badges de tipo

	// ── Bordes ────────────────────────────────────────────────────────────────
	var borderColor:Int;

	// ── Accentos ──────────────────────────────────────────────────────────────
	var accent:Int;       // color principal del título / texto seleccionado
	var accentAlt:Int;    // animated / secondary accent
	var selection:Int;    // caja de selección de canvas

	// ── Texto ─────────────────────────────────────────────────────────────────
	var textPrimary:Int;
	var textSecondary:Int;
	var textDim:Int;

	// ── Estado ────────────────────────────────────────────────────────────────
	var warning:Int;
	var success:Int;
	var error:Int;

	// ── Filas de la layer list ────────────────────────────────────────────────
	var rowSelected:Int;
	var rowEven:Int;
	var rowOdd:Int;
}

/**
 * EditorTheme — gestor estático del tema visual de todos los editores.
 *
 * Uso:
 *   EditorTheme.load();             // al inicio del editor
 *   var T = EditorTheme.current;    // acceso a los colores
 *   EditorTheme.apply(presetName);  // cambia y guarda tema
 */
class EditorTheme
{
	// ─────────────────────────────────────────────────────────────────────────
	// Tema activo
	// ─────────────────────────────────────────────────────────────────────────

	public static var current(default, null):ThemeData = _darkTheme();

	static inline final SAVE_PATH:String = 'assets/data/config/editorTheme.json';

	// ─────────────────────────────────────────────────────────────────────────
	// Carga / guardado
	// ─────────────────────────────────────────────────────────────────────────

	// Versión del formato de guardado. Incrementar si cambia la estructura.
	// Archivos con version < FORMAT_VERSION se ignoran (pueden estar corruptos).
	static inline final FORMAT_VERSION:Int = 2;

	/** Carga el tema guardado en disco, o el por defecto si no existe. */
	public static function load():Void
	{
		#if sys
		if (!FileSystem.exists(SAVE_PATH))
		{
			current = _darkTheme();
			CoolUITheme.syncFromDynamic(current);
			return;
		}
		try
		{
			var raw:Dynamic = Json.parse(File.getContent(SAVE_PATH));

			// Elegir la base según el campo 'preset'
			var presetName:String = (raw.preset : String) ?? 'dark';
			var base:ThemeData = switch (presetName.toLowerCase())
			{
				case 'neon':      _neonTheme();
				case 'pastel':    _pastelTheme();
				case 'light':     _lightTheme();
				case 'flstudio':  _flStudioTheme();
				case 'midnight':  _midnightTheme();
				default:          _darkTheme();
			};

			// ── Comprobación de formato ───────────────────────────────────
			var fileVersion:Int = (raw.version == null) ? 0 : Std.int(raw.version);
			if (fileVersion < FORMAT_VERSION)
			{
				trace('[EditorTheme] Archivo antiguo/corrupto (v$fileVersion < v$FORMAT_VERSION). Regenerando desde preset "$presetName".');
				current = base;
				save();
				CoolUITheme.syncFromDynamic(current);
				return;
			}

			// Si el nombre del preset coincide con uno conocido y no hay overrides custom,
			// usamos el preset directamente para evitar cualquier problema de parsing.
			var knownPresets = ['dark', 'neon', 'midnight', 'flstudio', 'pastel', 'light'];
			var isKnownPreset = Lambda.has(knownPresets, presetName.toLowerCase());
			var hasCustom = (raw.name != null && raw.name != presetName);
			if (isKnownPreset && !hasCustom)
			{
				// Verificar si hay algún color custom diferente al preset base
				var hasCustomColors = false;
				var fields = ['bgDark','bgPanel','bgPanelAlt','bgHover','borderColor',
					'accent','accentAlt','selection','textPrimary','textSecondary',
					'textDim','warning','success','error','rowSelected','rowEven','rowOdd'];
				for (f in fields)
				{
					var rawVal = Reflect.field(raw, f);
					if (rawVal != null)
					{
						// Parsear y comparar con el preset base
						var parsedColor = _parseColorString(Std.string(rawVal));
						var baseColor:Int = cast Reflect.field(base, f);
						if (parsedColor != null && parsedColor != baseColor)
						{
							hasCustomColors = true;
							break;
						}
					}
				}
				if (!hasCustomColors)
				{
					current = base;
					trace('[EditorTheme] Cargado preset limpio: "$presetName"');
					CoolUITheme.syncFromDynamic(current);
					return;
				}
			}

			// Sobreescribe campos individuales si están en el JSON (tema custom)
			current = _mergeTheme(base, raw);
			trace('[EditorTheme] Cargado: "${current.name}"');
		}
		catch (e:Dynamic)
		{
			trace('[EditorTheme] Error al cargar: $e — usando Dark');
			current = _darkTheme();
		}
		#else
		current = _darkTheme();
		#end
		CoolUITheme.syncFromDynamic(current);
	}

	/** Guarda el tema actual en disco. */
	public static function save():Void
	{
		#if sys
		try
		{
			var dir = 'assets/data/config';
			if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);

			// ─── IMPORTANTE ────────────────────────────────────────────────
			// Los colores ARGB (0xFFRRGGBB) son > Int32.MAX en unsigned.
			// Serializar el Int con signo da números negativos, y al releer
			// Std.parseInt('0xFF...') OVERFLOWEA en C++ devolviendo 0x7FFFFFFF,
			// lo que hace que todos los colores aparezcan #FFFFFF tras reiniciar.
			//
			// Solución: guardamos sólo los 6 dígitos RGB como string "#RRGGBB".
			// Al cargar, parseamos el RGB (cabe en Int32) y le ponemos el alpha
			// manualmente con OR (0xFF000000 = -16777216 en Int32 con signo).
			// ───────────────────────────────────────────────────────────────
			var fields = [
				'bgDark','bgPanel','bgPanelAlt','bgHover','borderColor',
				'accent','accentAlt','selection','textPrimary','textSecondary',
				'textDim','warning','success','error','rowSelected','rowEven','rowOdd'
			];
			var obj:Dynamic = {};
			obj.version = FORMAT_VERSION; // ← detecta archivos viejos/corruptos al cargar
			obj.preset  = current.name;
			obj.name    = current.name;
			for (f in fields)
			{
				// Leer el color del ThemeData de forma segura
				var colorInt:Int = 0;
				try { colorInt = cast Reflect.field(current, f); } catch (_:Dynamic) {}
				// Solo los 6 dígitos RGB, sin el byte alpha (evita overflow en C++)
				var rgb = colorInt & 0xFFFFFF;
				// Asegurar que tenemos 6 dígitos (rellenar con ceros a la izquierda)
				var hex = StringTools.hex(rgb < 0 ? 0 : rgb, 6);
				Reflect.setField(obj, f, '#' + hex);
			}

			File.saveContent(SAVE_PATH, Json.stringify(obj, null, '\t'));
			trace('[EditorTheme] Guardado: "${current.name}"');
		}
		catch (e:Dynamic) { trace('[EditorTheme] Error al guardar: $e'); }
		#end
	}

	/** Aplica un tema por nombre, lo guarda y actualiza `current`. */
	public static function apply(name:String):Void
	{
		current = switch (name.toLowerCase())
		{
			case 'neon':      _neonTheme();
			case 'pastel':    _pastelTheme();
			case 'light':     _lightTheme();
			case 'flstudio':  _flStudioTheme();
			case 'midnight':  _midnightTheme();
			default:          _darkTheme();
		};
		save();
		CoolUITheme.syncFromDynamic(current);
	}

	/** Aplica un ThemeData personalizado y lo guarda. */
	public static function applyCustom(theme:ThemeData):Void
	{
		current = theme;
		save();
		CoolUITheme.syncFromDynamic(current);
	}

	/** Lista de nombres de presets disponibles. */
	public static function presetNames():Array<String>
	{
		return ['dark', 'neon', 'midnight', 'flstudio', 'pastel', 'light'];
	}

	/** Devuelve una copia del preset indicado (sin aplicarlo). */
	public static function getPreset(name:String):ThemeData
	{
		return switch (name.toLowerCase())
		{
			case 'neon':      _neonTheme();
			case 'pastel':    _pastelTheme();
			case 'light':     _lightTheme();
			case 'flstudio':  _flStudioTheme();
			case 'midnight':  _midnightTheme();
			default:          _darkTheme();
		};
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Helper: merge JSON sobre ThemeData
	// ─────────────────────────────────────────────────────────────────────────

	/** Parsea un string "#RRGGBB" o "RRGGBB" a Int ARGB. Devuelve null si falla. */
	static function _parseColorString(s:String):Null<Int>
	{
		if (s == null) return null;
		s = s.trim().replace('#', '').replace('0x', '').replace('0X', '');
		if (s.length == 6)
		{
			var rgb = Std.parseInt('0x' + s);
			return (rgb != null) ? (rgb | 0xFF000000) : null;
		}
		if (s.length == 8)
		{
			var hi = Std.parseInt('0x' + s.substr(0, 2));
			var lo = Std.parseInt('0x' + s.substr(2));
			if (hi != null && lo != null)
				return ((hi & 0xFF) << 24) | lo;
		}
		return null;
	}

	static function _mergeTheme(base:ThemeData, raw:Dynamic):ThemeData
	{
		inline function _col(field:String, fallback:Int):Int
		{
			var v = Reflect.field(raw, field);
			if (v == null) return fallback;

			// ── Caso Int (guardado directamente como número) ──────────────
			if (Std.isOfType(v, Int))
			{
				var iv:Int = v;
				if (iv >= 0 && iv < 0x1000000) return iv | 0xFF000000;
				return iv;
			}
			if (Std.isOfType(v, Float))
			{
				var fv:Float = v;
				var iv:Int   = Std.int(fv);
				if (iv >= 0 && iv < 0x1000000) return iv | 0xFF000000;
				return iv;
			}

			// ── Caso String "#RRGGBB" o "AARRGGBB" ────────────────────────
			var parsed = _parseColorString(Std.string(v));
			return (parsed != null) ? parsed : fallback;
		}

		return {
			name:          raw.name   ?? base.name,
			bgDark:        _col('bgDark',        base.bgDark),
			bgPanel:       _col('bgPanel',       base.bgPanel),
			bgPanelAlt:    _col('bgPanelAlt',    base.bgPanelAlt),
			bgHover:       _col('bgHover',       base.bgHover),
			borderColor:   _col('borderColor',   base.borderColor),
			accent:        _col('accent',        base.accent),
			accentAlt:     _col('accentAlt',     base.accentAlt),
			selection:     _col('selection',     base.selection),
			textPrimary:   _col('textPrimary',   base.textPrimary),
			textSecondary: _col('textSecondary', base.textSecondary),
			textDim:       _col('textDim',       base.textDim),
			warning:       _col('warning',       base.warning),
			success:       _col('success',       base.success),
			error:         _col('error',         base.error),
			rowSelected:   _col('rowSelected',   base.rowSelected),
			rowEven:       _col('rowEven',       base.rowEven),
			rowOdd:        _col('rowOdd',        base.rowOdd),
		};
	}

	// ─────────────────────────────────────────────────────────────────────────
	// PRESETS
	// ─────────────────────────────────────────────────────────────────────────

	/** Oscuro clásico (por defecto) */
	static function _darkTheme():ThemeData return {
		name:          'dark',
		bgDark:        0xFF0B0B16,
		bgPanel:       0xFF13131F,
		bgPanelAlt:    0xFF1B1B2B,
		bgHover:       0xFF242438,
		borderColor:   0xFF3A3A5C,
		accent:        0xFF00E5FF,
		accentAlt:     0xFFFF6FD8,
		selection:     0xFF00CFFF,
		textPrimary:   0xFFE8E8FF,
		textSecondary: 0xFFAAA8CC,
		textDim:       0xFF5A5878,
		warning:       0xFFFFB300,
		success:       0xFF00D97E,
		error:         0xFFFF4444,
		rowSelected:   0xFF1E2B3C,
		rowEven:       0xFF16162A,
		rowOdd:        0xFF111124,
	};

	/** Neon / ciberpunk */
	static function _neonTheme():ThemeData return {
		name:          'neon',
		bgDark:        0xFF060612,
		bgPanel:       0xFF0E0E22,
		bgPanelAlt:    0xFF14142E,
		bgHover:       0xFF1C1C3C,
		borderColor:   0xFF4400FF,
		accent:        0xFF00FF88,
		accentAlt:     0xFFFF00AA,
		selection:     0xFF00FF88,
		textPrimary:   0xFFEEFFEE,
		textSecondary: 0xFF88FFCC,
		textDim:       0xFF335544,
		warning:       0xFFFFEE00,
		success:       0xFF00FF66,
		error:         0xFFFF0055,
		rowSelected:   0xFF001A22,
		rowEven:       0xFF0A0A1E,
		rowOdd:        0xFF080816,
	};

	/** Medianoche — azul profundo */
	static function _midnightTheme():ThemeData return {
		name:          'midnight',
		bgDark:        0xFF080C18,
		bgPanel:       0xFF0D1226,
		bgPanelAlt:    0xFF131830,
		bgHover:       0xFF1C2240,
		borderColor:   0xFF2A3566,
		accent:        0xFF7EB8FF,
		accentAlt:     0xFFB388FF,
		selection:     0xFF5599EE,
		textPrimary:   0xFFD8E4FF,
		textSecondary: 0xFF8899CC,
		textDim:       0xFF3A4466,
		warning:       0xFFFFCC44,
		success:       0xFF44DDAA,
		error:         0xFFFF6677,
		rowSelected:   0xFF18203A,
		rowEven:       0xFF10162E,
		rowOdd:        0xFF0C1224,
	};

	/** FL Studio 25 — dark orange/grey */
	static function _flStudioTheme():ThemeData return {
		name:          'flstudio',
		bgDark:        0xFF1C1C1C,
		bgPanel:       0xFF252525,
		bgPanelAlt:    0xFF2E2E2E,
		bgHover:       0xFF363636,
		borderColor:   0xFF4A4A4A,
		accent:        0xFFFF8C00,
		accentAlt:     0xFFFFBB44,
		selection:     0xFFFF8C00,
		textPrimary:   0xFFE8E8E8,
		textSecondary: 0xFFAAAAAA,
		textDim:       0xFF666666,
		warning:       0xFFFFBB00,
		success:       0xFF66CC44,
		error:         0xFFDD4444,
		rowSelected:   0xFF3A2800,
		rowEven:       0xFF282828,
		rowOdd:        0xFF222222,
	};

	/** Pastel — suave y colorido */
	static function _pastelTheme():ThemeData return {
		name:          'pastel',
		bgDark:        0xFF1A1028,
		bgPanel:       0xFF221638,
		bgPanelAlt:    0xFF2B1C48,
		bgHover:       0xFF362458,
		borderColor:   0xFF6655AA,
		accent:        0xFFFF99CC,
		accentAlt:     0xFF99CCFF,
		selection:     0xFFDD88FF,
		textPrimary:   0xFFFFEEFF,
		textSecondary: 0xFFCCAADD,
		textDim:       0xFF664466,
		warning:       0xFFFFDD66,
		success:       0xFF88FFCC,
		error:         0xFFFF88AA,
		rowSelected:   0xFF3A1858,
		rowEven:       0xFF201240,
		rowOdd:        0xFF1C1035,
	};

	/** Claro / día */
	static function _lightTheme():ThemeData return {
		name:          'light',
		bgDark:        0xFFD8D8E8,
		bgPanel:       0xFFEAEAF4,
		bgPanelAlt:    0xFFF2F2FF,
		bgHover:       0xFFDDDDEE,
		borderColor:   0xFFAAAAAA,
		accent:        0xFF0055CC,
		accentAlt:     0xFF8800CC,
		selection:     0xFF0077FF,
		textPrimary:   0xFF111122,
		textSecondary: 0xFF444466,
		textDim:       0xFF888899,
		warning:       0xFFCC7700,
		success:       0xFF007744,
		error:         0xFFCC2222,
		rowSelected:   0xFFCCDDFF,
		rowEven:       0xFFE8E8F8,
		rowOdd:        0xFFEEEEFF,
	};
}
