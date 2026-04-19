package funkin.scripting.interp;

#if HSCRIPT_ALLOWED
import hscript.Interp;
import hscript.Expr;
#end

/**
 * FunkinInterp — intérprete extendido para los scripts del engine.
 *
 * Extiende hscript.Interp con soporte para:
 *
 *   scriptObject   — objeto Haxe "host" al que el script puede leer/escribir
 *                    campos directamente sin prefix (igual que @:hscriptClass).
 *
 *   = assignment   — escribe de vuelta al scriptObject cuando el ident vive ahí.
 *
 *   += -= *= /= %= — operadores compuestos que también escriben al scriptObject.
 *   &= |= ^= <<= >>= >>>=   El Interp base solo escribe en variables/locals;
 *                            sin este fix "campo += 5" leía del SO pero escribía
 *                            en variables → el valor del SO nunca cambiaba.
 *
 *   ?? ??=         — operadores de null-coalescing (HScript 2.6+ los parsea como
 *                    EBinop pero el Interp base no los evalúa → error en runtime).
 *                    ?? : devuelve el lado izquierdo si no es null, si no el derecho.
 *                    ??=: asigna el derecho solo si el izquierdo es null.
 */
class FunkinInterp extends Interp
{
	/** Objeto Haxe que actúa como "this" implícito para los scripts. */
	public var scriptObject(default, set):Dynamic = null;

	/** Campos del scriptObject (para lookup O(1)). */
	var _soFields:haxe.ds.StringMap<Bool> = new haxe.ds.StringMap();

	/** Cache de métodos enlazados del scriptObject para evitar createMethod en cada acceso. */
	var _soMethods:haxe.ds.StringMap<Dynamic> = new haxe.ds.StringMap();

	function set_scriptObject(v:Dynamic):Dynamic
	{
		_soFields  = new haxe.ds.StringMap();
		_soMethods = new haxe.ds.StringMap();

		if (v != null)
		{
			for (f in Reflect.fields(v))
				_soFields.set(f, true);

			final cls = Type.getClass(v);
			if (cls != null)
				for (f in Type.getInstanceFields(cls))
					_soFields.set(f, true);
		}

		return scriptObject = v;
	}

	// ── Detección de formato de hscript (struct vs enum directo) ─────────────
	var _fmtIsStruct:Bool  = false;
	var _fmtDetected:Bool  = false;

	// Índices de enum cacheados (evitar Type.enumConstructor() en hot-path)
	var _idxEBinop:Int = -1;
	var _idxEIdent:Int = -1;

	// Operadores compuestos que el base Interp NO escribe al scriptObject.
	static final _COMPOUND_OPS:Array<String> = [
		"+=", "-=", "*=", "/=", "%=",
		"&=", "|=", "^=",
		"<<=", ">>=", ">>>="
	];

	public function new()
	{
		super();
	}

	// ── resolve ───────────────────────────────────────────────────────────────

	override public function resolve(id:String):Dynamic
	{
		final l = locals.get(id);
		if (l != null)
			return l.r;

		if (variables.exists(id))
			return variables.get(id);

		if (scriptObject != null && _soFields.exists(id))
		{
			final cached = _soMethods.get(id);
			if (cached != null)
				return cached;

			final prop = Reflect.getProperty(scriptObject, id);

			if (Reflect.isFunction(prop))
			{
				final obj = scriptObject;
				final bound = Reflect.makeVarArgs(function(args)
					return Reflect.callMethod(obj, prop, args));
				_soMethods.set(id, bound);
				return bound;
			}

			return prop; // getter / campo normal
		}

		throw hscript.Expr.Error.EUnknownVariable(id);
	}

	// ── expr ─────────────────────────────────────────────────────────────────

	override public function expr(e:hscript.Expr):Dynamic
	{
		#if HSCRIPT_ALLOWED

		// Detectar una sola vez si hscript usa el formato struct {e:...}
		// (versiones recientes) o enum directo (versiones anteriores).
		if (!_fmtDetected)
		{
			_fmtIsStruct = Reflect.hasField(e, "e");
			_fmtDetected = true;
		}

		final def:Dynamic = _fmtIsStruct ? Reflect.field(e, "e") : e;
		if (def == null)
			return super.expr(e);

		final defIdx:Int = Type.enumIndex(def);

		// Fast-path: si ya sabemos el índice de EBinop, comparamos enteros.
		if (_idxEBinop >= 0)
		{
			if (defIdx != _idxEBinop)
				return super.expr(e);
		}
		else
		{
			if (Type.enumConstructor(def) != "EBinop")
				return super.expr(e);
			_idxEBinop = defIdx;
		}

		final params = Type.enumParameters(def);
		final op:String = params[0];

		// ── ?? null-coalescing ────────────────────────────────────────────────
		//   a ?? b  →  a != null ? a : b
		// hscript 2.6+ parsea ?? como EBinop("??", ...) pero el Interp base
		// no lo evalúa y lanza "Unknown operator ??".
		if (op == "??")
		{
			final lv:Dynamic = expr(params[1]);
			return lv != null ? lv : expr(params[2]);
		}

		// ── ??= null-coalescing assignment ────────────────────────────────────
		//   a ??= b  →  if (a == null) a = b
		// Solo se intercepta cuando el LHS es un EIdent simple.
		if (op == "??=")
		{
			final id = _getEIdentId(params[1]);
			if (id == null)
				return super.expr(e); // LHS complejo — dejar al base

			// Leer valor actual (tolerante: si no existe, asumimos null)
			var current:Dynamic = null;
			try { current = resolve(id); } catch (_:Dynamic) {}

			if (current != null)
				return current; // ya tiene valor — no asignar

			// Asignar y devolver el nuevo valor
			final val:Dynamic = expr(params[2]);
			return _writeIdent(id, val);
		}

		// ── = plain assignment ────────────────────────────────────────────────
		// Escribe al scriptObject si el ident vive ahí (el base solo escribe
		// en variables/locals y nunca llama Reflect.setProperty al scriptObject).
		if (op == "=")
		{
			final lhsRaw:Dynamic = _fmtIsStruct ? Reflect.field(params[1], "e") : params[1];
			if (lhsRaw == null)
				return super.expr(e);

			final lhsIdx:Int = Type.enumIndex(lhsRaw);

			if (_idxEIdent >= 0)
			{
				if (lhsIdx != _idxEIdent)
					return super.expr(e); // LHS no es EIdent (acceso a campo, array, etc.)
			}
			else
			{
				if (Type.enumConstructor(lhsRaw) != "EIdent")
					return super.expr(e);
				_idxEIdent = lhsIdx;
			}

			final id:String   = Type.enumParameters(lhsRaw)[0];
			final val:Dynamic = expr(params[2]);
			return _writeIdent(id, val);
		}

		// ── Operadores compuestos (+= -= *= /= %= &= |= ^= <<= >>= >>>=) ─────
		//
		// El Interp base evalúa estos como:
		//   1. leer valor actual via expr(lhs)    ← nuestro resolve() lo maneja bien
		//   2. calcular nuevo valor
		//   3. assign(lhs, nuevovalor)             ← el base SOLO escribe en
		//                                             variables/locals, NUNCA en
		//                                             scriptObject → BUG
		//
		// Solución: si el LHS es un EIdent que vive en scriptObject (no en locals
		// ni variables), nos encargamos nosotros.  Si vive en locals/variables,
		// dejamos pasar al base (ya funciona bien allí).
		if (_COMPOUND_OPS.indexOf(op) >= 0)
		{
			final id = _getEIdentId(params[1]);
			if (id != null)
			{
				final inLocal = locals.get(id) != null;
				final inVars  = variables.exists(id);

				if (!inLocal && !inVars && scriptObject != null && _soFields.exists(id))
				{
					final cur:Dynamic = Reflect.getProperty(scriptObject, id);
					final rhs:Dynamic = expr(params[2]);
					final newVal:Dynamic = _applyCompound(op, cur, rhs);
					Reflect.setProperty(scriptObject, id, newVal);
					return newVal;
				}
			}
			// ident en locals/variables → el base lo resuelve correctamente
		}

		return super.expr(e);

		#else
		return super.expr(e);
		#end
	}

	// ── Helpers privados ─────────────────────────────────────────────────────

	/**
	 * Extrae el nombre de un nodo EIdent, o null si el nodo no es EIdent.
	 * Usa el mismo formato-struct detection que expr().
	 */
	inline function _getEIdentId(node:Dynamic):Null<String>
	{
		final raw:Dynamic = _fmtIsStruct ? Reflect.field(node, "e") : node;
		if (raw == null) return null;
		if (Type.enumConstructor(raw) != "EIdent") return null;
		return Type.enumParameters(raw)[0];
	}

	/**
	 * Escribe `val` al identificador `id` en la capa correcta:
	 *   1. local scope  (var declarada dentro del script)
	 *   2. scriptObject (campo del objeto host Haxe)
	 *   3. variables    (scope global del intérprete)
	 */
	function _writeIdent(id:String, val:Dynamic):Dynamic
	{
		final loc = locals.get(id);
		if (loc != null)
		{
			loc.r = val;
			return val;
		}

		if (scriptObject != null && _soFields.exists(id))
		{
			Reflect.setProperty(scriptObject, id, val);
			return val;
		}

		variables.set(id, val);
		return val;
	}

	/**
	 * Aplica un operador compuesto a dos valores y devuelve el resultado.
	 * Usado exclusivamente por el bloque de compound-assignment de expr().
	 */
	static function _applyCompound(op:String, a:Dynamic, b:Dynamic):Dynamic
	{
		return switch (op)
		{
			case "+=":   a + b;
			case "-=":   a - b;
			case "*=":   a * b;
			case "/=":   a / b;
			case "%=":   a % b;
			case "&=":   (a : Int) &   (b : Int);
			case "|=":   (a : Int) |   (b : Int);
			case "^=":   (a : Int) ^   (b : Int);
			case "<<=":  (a : Int) <<  (b : Int);
			case ">>=":  (a : Int) >>  (b : Int);
			case ">>>=": (a : Int) >>> (b : Int);
			default:     b; // fallback: tratar como asignación directa
		}
	}
}
