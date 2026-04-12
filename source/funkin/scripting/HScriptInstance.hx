package funkin.scripting;

import haxe.Exception;
// ── Compatibilidad hscript 2.4.x / 2.5.x ─────────────────────────────────────
#if HSCRIPT_ALLOWED
import hscript.Interp;
import hscript.Expr;
// hscript.Expr.Error existe en 2.4+ como clase base de errores
// En versiones muy antiguas puede no tener `.e` — usar Dynamic como fallback
#end
#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/**
 * HScriptInstance v3 — instancia individual de script HScript.
 *
 * ─── Nuevas features v3 ──────────────────────────────────────────────────────
 *
 *  • Guards de compatibilidad de librerías:
 *      - hscript 2.4.x / 2.5.x  → allowMetadata manejado con try/catch
 *      - openfl 8.x / 9.x        → no hay dependencias directas aquí
 *      - sys-only FileSystem     → guard #if sys
 *
 *  • hotReload() mejorado: también re-expone el ScriptAPI completo tras recargar.
 *  • Errores más legibles: formato "NombreScript.hx:42 — mensaje".
 *  • set/get son más seguros: null-check antes de acceder a interp.variables.
 *  • dispose() para limpiar el intérprete sin destruir el objeto.
 *
 * ─── Compatibilidad garantizada ──────────────────────────────────────────────
 *  Flixel 4.x, 5.x — no hay dependencias directas de Flixel aquí
 *  hscript 2.4.x, 2.5.x — API de Parser/Interp es igual
 *  OpenFL 8.x, 9.x — sin dependencias directas
 *
 * @author Cool Engine Team
 * @version 3.0.0
 */
class HScriptInstance implements IScript
{
	public var name:String;
	public var path:String;
	public var active:Bool = true;
	public var priority:Int = 0;
	public var tag:String = '';

	// ── IScript contract ──────────────────────────────────────────────────────
	// `id` y `filePath` cumplen el contrato de IScript exactamente:
	//   • id       → var simple (lectura/escritura pública)
	//   • filePath → (default, null) (escritura sólo interna)
	// El constructor los sincroniza con `name` y `path` al crearse.

	/** IScript.id — identificador del script (var simple, igual que IScript). */
	public var id:String;

	/** IScript.filePath — ruta al fuente, read-only desde fuera. */
	public var filePath(default, null):Null<String>;

	/** true si ocurrió un error irrecuperable que desactivó el script. */
	public var errored:Bool = false;

	/** Texto del último error, o null. */
	public var lastError:Null<String> = null;

	/**
	 * Number of consecutive runtime errors this script has thrown.
	 * When it reaches MAX_SCRIPT_ERRORS the script is automatically
	 * deactivated so a broken onUpdate can't spam the console or
	 * slow down gameplay every single frame.
	 * Reset to 0 after a successful call or a hotReload().
	 */
	public var errorCount:Int = 0;

	/** How many consecutive errors before the script is force-disabled. */
	static inline final MAX_SCRIPT_ERRORS:Int = 5;

	/** hasFunction — requerido por IScript. Comprueba caché + variables del intérprete. */
	public function hasFunction(name:String):Bool
	{
		#if HSCRIPT_ALLOWED
		if (interp == null)
			return false;
		final cached = _funcCache.get(name);
		if (cached != null)
			return cached != _MISSING;
		final resolved = interp.variables.get(name);
		return resolved != null && Reflect.isFunction(resolved);
		#else
		return false;
		#end
	}

	/** Último valor devuelto por `call()`. */
	public var returnValue:Dynamic = null;

	/** Callback de error: (scriptName, funcName, error) → Void. */
	public var onError:Null<String->String->Dynamic->Void> = null;

	#if HSCRIPT_ALLOWED
	public var interp:Null<funkin.scripting.interp.FunkinInterp> = null;

	/** Objeto de contexto automático (Stage o Character) */
	public var scriptObject(get, set):Dynamic;

	inline function get_scriptObject()
		return interp != null ? interp.scriptObject : null;

	inline function set_scriptObject(v:Dynamic)
	{
		if (interp != null)
			interp.scriptObject = v;
		return v;
	}

	public var program:Null<Expr> = null;

	/** Cached source code — used for hot-reload and for pinpointing error lines. */
	public var _source:String = '';

	private var _reloading:Bool = false;

	/**
	 * Caché de funciones: mapea nombre → función (o _MISSING si no existe).
	 * Evita hacer interp.variables.get() + Reflect.isFunction() en cada llamada
	 * cuando la función simplemente no está definida en el script.
	 * Se invalida en hotReload() y dispose().
	 */
	var _funcCache:haxe.ds.StringMap<Dynamic> = new haxe.ds.StringMap();

	/** Sentinel: indica que la función NO existe en este script. */
	static final _MISSING:{} = {};
	#end

	// ── Constructor ───────────────────────────────────────────────────────────

	public function new(name:String, path:String, priority:Int = 0, tag:String = '')
	{
		this.name = name;
		this.path = path;
		this.priority = priority;
		this.tag = tag;
		// Sincronizar con el contrato IScript
		this.id = name;
		this.filePath = path;
	}

	// ── Llamadas ──────────────────────────────────────────────────────────────

	/**
	 * Llama a `funcName` con `args`. Devuelve el resultado o null.
	 * Null-safe: si la función no existe, no hace nada.
	 *
	 * OPTIMIZACIÓN: usa _funcCache para evitar interp.variables.get() +
	 * Reflect.isFunction() en cada llamada cuando la función no está definida.
	 * El caché se rellena perezosamente en la primera llamada a cada nombre.
	 */
	public function call(funcName:String, args:Array<Dynamic> = null):Dynamic
	{
		if (!active)
			return null;
		// BUG FIX #8: bloquear llamadas mientras hotReload() re-ejecuta el programa.
		// Sin este guard, onUpdate/onBeatHit del mismo frame acceden al intérprete
		// en estado intermedio → crash cuando BF canta durante un hot-reload.
		if (_reloading)
			return null;

		#if HSCRIPT_ALLOWED
		if (interp == null)
			return null;
		if (args == null)
			args = [];

		try
		{
			var func = _funcCache.get(funcName);

			if (func == null)
			{
				// Primera vez que se llama con este nombre — resolver y cachear
				final resolved = interp.variables.get(funcName);
				func = (resolved != null && Reflect.isFunction(resolved)) ? resolved : _MISSING;
				_funcCache.set(funcName, func);
			}

			if (func != _MISSING)
			{
				returnValue = Reflect.callMethod(null, func, args);
				errorCount = 0; // successful call — reset the error streak
				return returnValue;
			}
		}
		catch (e:Dynamic)
		{
			_handleError(funcName, e);
		}
		#end

		return null;
	}

	/**
	 * Llama con cast tipado al valor de retorno.
	 * Si el resultado no es del tipo T, devuelve `fallback`.
	 */
	public function callReturn<T>(funcName:String, args:Array<Dynamic> = null, fallback:T):T
	{
		final r = call(funcName, args);
		if (r == null)
			return fallback;
		try
		{
			return cast r;
		}
		catch (_)
		{
			return fallback;
		}
	}

	/**
	 * Llama a `funcName` y devuelve true si el resultado es literalmente `true`.
	 * Usado por StateScriptHandler para la mecánica de cancelación de eventos.
	 */
	public function callBool(funcName:String, args:Array<Dynamic> = null):Bool
	{
		final r = call(funcName, args);
		return r == true;
	}

	// ── Variables ─────────────────────────────────────────────────────────────

	/** Inyecta o actualiza una variable. Invalida el _funcCache si era una función cacheada. */
	public function set(varName:String, value:Dynamic):Void
	{
		#if HSCRIPT_ALLOWED
		if (interp != null)
		{
			interp.variables.set(varName, value);
			// Si existía en el caché de funciones, invalidar: el valor cambió.
			if (_funcCache.exists(varName))
				_funcCache.remove(varName);
		}
		#end
	}

	/**
	 * Sets multiple variables at once from a map or anonymous struct.
	 * FIX #4: invalida `_funcCache` para cada campo sobreescrito, igual que
	 * hace `set()`, para que el caché no devuelva la versión anterior de una
	 * función que se reemplazó con `setAll()`.
	 */
	public function setAll(vars:Dynamic):Void
	{
		#if HSCRIPT_ALLOWED
		if (interp == null || vars == null)
			return;
		for (field in Reflect.fields(vars))
		{
			interp.variables.set(field, Reflect.field(vars, field));
			if (_funcCache.exists(field))
				_funcCache.remove(field);
		}
		#end
	}

	/** Lee una variable del script. Devuelve null si no existe. */
	public function get(varName:String):Dynamic
	{
		#if HSCRIPT_ALLOWED
		if (interp == null)
			return null;
		return interp.variables.get(varName);
		#else
		return null;
		#end
	}

	/** Comprueba si la variable existe. */
	public function exists(varName:String):Bool
	{
		#if HSCRIPT_ALLOWED
		if (interp == null)
			return false;
		return interp.variables.exists(varName);
		#else
		return false;
		#end
	}

	/**
	 * Sobreescribe completamente una función en el script con una implementación Haxe.
	 * Útil para que el engine overridee comportamiento sin que el script lo sepa.
	 */
	public function overrideFunction(funcName:String, impl:Dynamic):Void
	{
		#if HSCRIPT_ALLOWED
		if (interp != null)
		{
			interp.variables.set(funcName, impl);
			_funcCache.remove(funcName); // invalidar solo esta entrada
		}
		#end
	}

	// ── Hot-reload ────────────────────────────────────────────────────────────

	/**
	 * Initialises the interpreter from a raw code string instead of a file.
	 * Useful for the PlayState editor's inline script panel.
	 */
	public function loadString(code:String):Bool
	{
		#if HSCRIPT_ALLOWED
		if (code == null || code == '')
			return false;
		try
		{
			_source = code;
			if (interp == null)
			{
				interp = new funkin.scripting.interp.FunkinInterp();
				#if HSCRIPT_ALLOWED
				try
				{
					Reflect.setField(interp, 'allowMetadata', true);
				}
				catch (_)
				{
				}
				#end
				ScriptAPI.expose(interp);
			}
			// Pre-procesar imports antes de parsear
			final _processedSource = ScriptHandler.processImports(_source, interp);
			program = ScriptHandler.parser.parseString(_processedSource, name);
			interp.execute(program);
			return true;
		}
		catch (e:Dynamic)
		{
			_handleError('loadString', e);
			return false;
		}
		#else
		return false;
		#end
	}

	/**
	 * Recarga el archivo desde disco sin recrear el intérprete.
	 * Las variables que ya existen en `interp` se preservan.
	 * El ScriptAPI se re-expone para que nuevas APIs sean visibles.
	 */
	public function hotReload():Bool
	{
		#if (HSCRIPT_ALLOWED && sys)
		if (interp == null || path == null || path == '')
			return false;
		if (!FileSystem.exists(path))
		{
			trace('[HScript] hotReload: no existe "$path"');
			return false;
		}

		try
		{
			_source = File.getContent(path);
			program = ScriptHandler.parser.parseString(_source, path);

			// Re-exponer ScriptAPI (podría haber cambiado entre recargas)
			ScriptAPI.expose(interp);

			// Invalidar caché de funciones — el script redefinió sus funciones
			_funcCache.clear();
			errorCount = 0; // fresh reload — give the script a clean slate

			// BUG FIX #8: bloquear call() durante la re-ejecución del programa.
			// onUpdate/onBeatHit del mismo frame crashean si acceden al intérprete
			// mientras interp.execute() está redefiniendo las funciones del script.
			_reloading = true;
			try
			{
				interp.execute(program);
				call('onCreate');
				call('postCreate');
			}
			catch (innerErr:Dynamic)
			{
				_reloading = false;
				throw innerErr;
			}
			_reloading = false;

			trace('[HScript] Hot-reloaded: $name');
			return true;
		}
		catch (e:Dynamic)
		{
			trace('[HScript] hotReload FAIL "$name": ${Std.string(e)}');
			return false;
		}
		#else
		return false;
		#end
	}

	// ── Módulos (require) ─────────────────────────────────────────────────────

	/**
	 * Importa otro script como módulo.
	 * Devuelve el intérprete del módulo para acceder a sus variables.
	 * Uso desde un script: `var mod = require('ruta/otroScript.hx');`
	 */
	public function require(modulePath:String):Dynamic
	{
		#if (HSCRIPT_ALLOWED && sys)
		final resolved = _resolvePath(modulePath);
		if (resolved == null)
		{
			trace('[HScript] require: not found "$modulePath"');
			return null;
		}

		final mod = ScriptHandler.loadScript(resolved, 'song');
		if (mod == null || mod.interp == null)
			return null;

		// BUG FIX: devolver objeto dinámico en lugar del StringMap crudo.
		// mod.interp.variables es StringMap<Dynamic>. En C++/HL, Reflect.field
		// no puede acceder a los métodos del StringMap, así que vizModule.get('create')
		// retornaba null silenciosamente → viz = null → barras nunca se añadían.
		// Con un objeto anónimo, vizModule.create(x, y) funciona directamente.
		final proxy:Dynamic = {};
		for (k => v in mod.interp.variables)
			Reflect.setField(proxy, k, v);
		return proxy;
		#else
		return null;
		#end
	}

	// ── Limpieza ──────────────────────────────────────────────────────────────

	/**
	 * Alias de dispose() para compatibilidad con código que llame destroy().
	 * Destruye el intérprete y desactiva la instancia.
	 */
	public function destroy():Void
		dispose();

	/**
	 * Destruye el intérprete pero preserva metadata (name, path, tag).
	 * Útil para liberar RAM manteniendo el slot registrado.
	 */
	public function dispose():Void
	{
		#if HSCRIPT_ALLOWED
		if (interp != null)
		{
			try { interp.variables.clear(); } catch (_:Dynamic) {}
			try { @:privateAccess interp.locals.clear(); } catch (_:Dynamic) {}
			interp.scriptObject = null;

			interp = null;
		}
		program = null;
		_source = '';
		_funcCache.clear();
		#end
		active = false;
	}

	// ── Helpers privados ─────────────────────────────────────────────────────

	function _handleError(funcName:String, e:Dynamic):Void
	{
		// ── Capa exterior: garantizar que SIEMPRE mostramos algo aunque todo falle ──
		// Si cualquier bloque interior lanza una excepción secundaria, el catch
		// externo lo captura y escribe al menos en stderr.
		try
		{
			var msg = "(error desconocido)";
			var lineNum = -1;
			var lineContent = '';

			// ── Convertir el error a string ───────────────────────────────────
			try { msg = Std.string(e); } catch (_se:Dynamic) {}

			// ── Extraer info estructurada de hscript.Expr.Error ───────────────
			#if HSCRIPT_ALLOWED
			try
			{
				final exprErr = cast(e, hscript.Expr.Error);
				if (exprErr != null)
				{
					try
					{
						final defMsg = _formatErrorDef(Reflect.field(exprErr, 'e'));
						if (defMsg != null && defMsg != '')
							msg = defMsg;
					}
					catch (_fmtErr:Dynamic) {}

					try
					{
						if (Reflect.hasField(exprErr, 'line'))
						{
							final raw = Reflect.field(exprErr, 'line');
							if (raw != null) lineNum = raw;
						}
					}
					catch (_lineErr:Dynamic) {}

					try
					{
						if (lineNum <= 0 && Reflect.hasField(exprErr, 'pmin'))
						{
							final pmin:Int = Reflect.field(exprErr, 'pmin');
							if (pmin >= 0)
								lineNum = _lineFromOffset(_getSource(), pmin);
						}
					}
					catch (_pminErr:Dynamic) {}
				}
			}
			catch (_castErr:Dynamic) {}
			#end

			// ── Extraer línea de fuente ───────────────────────────────────────
			if (lineNum > 0)
				try { lineContent = _getSourceLine(_getSource(), lineNum); } catch (_) {}

			// ── Trace ─────────────────────────────────────────────────────────
			try
			{
				final location = lineNum > 0 ? '$name:$lineNum' : (name ?? "?");
				final fn = funcName ?? "?";
				trace('[HScript] Error in $location ($fn) → $msg');
				if (lineContent != '')
					trace('  >> $lineContent');
			}
			catch (_traceErr:Dynamic) {}

			// ── Actualizar contrato IScript ───────────────────────────────────
			try { lastError = msg; } catch (_) {}

			// ── Auto-disable on repeated errors ─────────────────────────────────
			// If the same script keeps erroring on every call (e.g. a broken
			// onUpdate), disable it after MAX_SCRIPT_ERRORS consecutive failures.
			// This prevents console spam and frame-rate drops every single frame.
			// errorCount is reset to 0 on any successful call or hotReload().
			try
			{
				errorCount++;
				if (errorCount >= MAX_SCRIPT_ERRORS)
				{
					active  = false;
					errored = true;
					trace('[HScript] Script "$name" has been DISABLED after'
						+ ' $MAX_SCRIPT_ERRORS consecutive errors.'
						+ ' Fix the script and reload to re-enable it.');
				}
			}
			catch (_counterErr:Dynamic) {}

			// ── Popup in-game (no bloqueante) ─────────────────────────────────
			// ScriptErrorNotifier tiene su propia capa de try/catch interna,
			// pero lo envolvemos también aquí por si la construcción del Sprite
			// OpenFL falla por un estado de render corrupto.
			try
			{
				final popupMsg = lineContent != '' ? '$msg\n\n>> $lineContent' : msg;
				final safeScript = (name != null) ? name : "?";
				final safeFunc = (funcName != null) ? funcName : "?";
				ScriptErrorNotifier.notify(safeScript, safeFunc, popupMsg, lineNum);
			}
			catch (_notifyErr:Dynamic)
			{
				// Si el popup falla, escribir en stderr como último recurso
				try
				{
					Sys.stderr().writeString('[HScript][popup-failed] Error in ${name ?? "?"} (${funcName ?? "?"}) → $msg\n');
				}
				catch (_) {}
			}

			// ── onError callback ──────────────────────────────────────────────
			if (onError != null)
				try { onError(name, funcName, e); } catch (_e2:Dynamic) {}
		}
		catch (_outerErr:Dynamic)
		{
			// Fallback absoluto: el manejador de error falló internamente.
			// Intentar escribir cualquier info disponible a stderr.
			try
			{
				var fallback = "[HScript] _handleError falló internamente.\n";
				try { fallback += "  Script:   " + Std.string(name) + "\n"; } catch (_) {}
				try { fallback += "  Función:  " + Std.string(funcName) + "\n"; } catch (_) {}
				try { fallback += "  Error:    " + Std.string(e) + "\n"; } catch (_) {}
				try { fallback += "  Causa:    " + Std.string(_outerErr) + "\n"; } catch (_) {}
				Sys.stderr().writeString(fallback);
			}
			catch (_) {}
		}
	}

	/**
	 * Returns the cached source string, loading it from disk on first access
	 * if it was never set (e.g. when the script was loaded via ScriptHandler
	 * before this field was being populated).
	 */
	function _getSource():String
	{
		#if (HSCRIPT_ALLOWED && sys)
		if (_source == '' && path != null && path != '' && sys.FileSystem.exists(path))
			_source = sys.io.File.getContent(path);
		#end
		return _source;
	}

	/**
	 * Converts an hscript ErrorDef enum value into a readable error string.
	 *
	 * Tries structured enum access first (hscript 2.5+), then falls back to
	 * parsing the stringified representation for older versions.
	 *
	 * Examples of output:
	 *   EUnknownVariable("myVar")  → Unknown variable "myVar"
	 *   EInvalidAccess("length")   → Invalid field access "length"
	 *   ECustom("division by 0")   → division by 0
	 */
	static function _formatErrorDef(errDef:Dynamic):Null<String>
	{
		if (errDef == null)
			return null;

		// Structured path: works when errDef is a real hscript enum instance
		try
		{
			final tag = Type.enumConstructor(errDef);
			final params = Type.enumParameters(errDef);
			return switch (tag)
			{
				case 'EUnknownVariable': 'Unknown variable "${params[0]}"';
				case 'EInvalidAccess': 'Invalid field access "${params[0]}"';
				case 'ECustom': Std.string(params[0]);
				case 'EUnexpected': 'Unexpected token "${params[0]}"';
				case 'EUnterminatedString': 'Unterminated string literal';
				case 'EUnterminatedComment': 'Unterminated block comment';
				case 'EInvalidOp': 'Invalid operator "${params[0]}"';
				case 'EInvalidIterator': 'Invalid iterator "${params[0]}"';
				case 'EInvalidChar': 'Invalid character (code ${params[0]})';
				default: Std.string(errDef);
			};
		}
		catch (_e:Dynamic)
		{
		}

		// String-parse fallback for older hscript versions where enum casting fails
		try
		{
			final s = Std.string(errDef);
			if (s.startsWith('EUnknownVariable('))
				return 'Unknown variable: ${s.substring(17, s.length - 1)}';
			if (s.startsWith('EInvalidAccess('))
				return 'Invalid field access: ${s.substring(15, s.length - 1)}';
			if (s.startsWith('ECustom('))
				return s.substring(8, s.length - 1);
			if (s.startsWith('EUnexpected('))
				return 'Unexpected token: ${s.substring(12, s.length - 1)}';
			if (s == 'EUnterminatedString')
				return 'Unterminated string literal';
			if (s.startsWith('EInvalidOp('))
				return 'Invalid operator: ${s.substring(11, s.length - 1)}';
			if (s.startsWith('EInvalidIterator('))
				return 'Invalid iterator: ${s.substring(17, s.length - 1)}';
			return s;
		}
		catch (_e:Dynamic)
		{
		}

		return null;
	}

	/**
	 * Converts a pmin character offset to a 1-based line number by counting
	 * newline characters in the source up to that position.
	 */
	static function _lineFromOffset(source:String, offset:Int):Int
	{
		if (offset <= 0 || source == '')
			return 1;
		var line = 1;
		final len = Std.int(Math.min(offset, source.length));
		for (i in 0...len)
			if (source.charAt(i) == '\n')
				line++;
		return line;
	}

	/**
	 * Returns the trimmed content of the given 1-based line number from source.
	 * Returns an empty string if lineNum is out of range.
	 */
	static function _getSourceLine(source:String, lineNum:Int):String
	{
		if (source == '' || lineNum <= 0)
			return '';
		final lines = source.split('\n');
		final idx = lineNum - 1;
		if (idx >= lines.length)
			return '';
		return StringTools.trim(lines[idx]);
	}

	function _resolvePath(rawPath:String):Null<String>
	{
		#if sys
		// 1. Ruta absoluta
		if (FileSystem.exists(rawPath))
			return rawPath;

		// 2. Relativa al directorio del script actual
		if (path != null && path != '')
		{
			final dir = StringTools.contains(path, '/') ? path.substring(0, path.lastIndexOf('/') + 1) : path.substring(0, path.lastIndexOf('\\') + 1);
			final rel = dir + rawPath;
			if (FileSystem.exists(rel))
				return rel;
			// Con extensión .hx
			if (FileSystem.exists(rel + '.hx'))
				return rel + '.hx';
		}

		// 3. Relativa a assets/
		if (FileSystem.exists('assets/$rawPath'))
			return 'assets/$rawPath';
		if (FileSystem.exists('assets/$rawPath.hx'))
			return 'assets/$rawPath.hx';

		// 4. Relativa al mod activo
		if (mods.ModManager.isActive())
		{
			final modPath = '${mods.ModManager.modRoot()}/$rawPath';
			if (FileSystem.exists(modPath))
				return modPath;
			if (FileSystem.exists(modPath + '.hx'))
				return modPath + '.hx';
		}
		#end
		return null;
	}
}
