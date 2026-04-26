package;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;
import sys.io.File;
import sys.FileSystem;

using StringTools;

/**
 * WinMacroFix.hx — source/WinMacroFix.hx
 *
 * Evita colisiones entre macros del Windows SDK y constantes de HaxeFlixel
 * (FlxKey, FlxColor) que provocan errores C2059/C2238 en MSVC.
 *
 * ════════════════════════════════════════════════════════════════════════════
 *  POR QUÉ LAS VERSIONES ANTERIORES FALLABAN
 * ════════════════════════════════════════════════════════════════════════════
 *  Las versiones 1-5 parcheaban directamente los archivos .h generados por
 *  Haxe (FlxKey_Impl_.h, FlxColor_Impl_.h). El problema: HXCPP tiene su
 *  propio sistema de caché y puede restaurar los headers sin parchear en
 *  export\debug\windows\obj\include\ DESPUÉS de que onAfterGenerate haya
 *  ejecutado, deshaciendo el parche.
 *
 * ════════════════════════════════════════════════════════════════════════════
 *  SOLUCIÓN v7 — @:headerCode (compile-time, cache-proof, space-safe)
 * ════════════════════════════════════════════════════════════════════════════
 *  El enfoque v6 (/FI en Build.xml) fallaba cuando la ruta del proyecto
 *  contiene espacios (ej. "H:\MOD FNF\...") porque HXCPP parte el argumento
 *  en dos al invocar cl.exe y MSVC nunca recibe el flag correctamente.
 *
 *  v7 usa Context.addGlobalMetadata con @:headerCode para inyectar:
 *    #include "H:/ruta/con espacios/source/macros/WinUndefs.h"
 *  directamente en los headers generados de FlxKey y FlxColor DURANTE la
 *  fase de generación de código de Haxe.  Las comillas dobles en #include
 *  son ISO C/C++ estándar y admiten espacios en la ruta → no hay problema.
 *
 *  Flujo v7:
 *   1. apply() llama addGlobalMetadata → @:headerCode registrado en FlxKey/FlxColor
 *   2. Haxe genera FlxKey_Impl_.h con #include "WinUndefs.h" al principio
 *   3. HXCPP compila: MSVC ve los #undef ANTES de los enum values → sin C2059
 *
 *  El fallback v6 (onAfterGenerate + Build.xml + header patching) se mantiene
 *  como cinturón + tirantes para entornos donde @:headerCode no aplique.
 */
class WinMacroFix {
	// Versión del parche — cambiar para forzar re-parche en builds incrementales.
	static final MARKER = '// WinMacroFix-v6';
	static final MARKER_XML = '<!-- WinMacroFix-v6 -->';

	// ── FlxColor undefs ────────────────────────────────────────────────────────
	static final UNDEFS_COLOR = MARKER
		+ '
#ifdef TRANSPARENT
#undef TRANSPARENT
#endif
#ifdef OPAQUE
#undef OPAQUE
#endif
#ifdef BLACK
#undef BLACK
#endif
#ifdef WHITE
#undef WHITE
#endif
#ifdef RED
#undef RED
#endif
#ifdef GREEN
#undef GREEN
#endif
#ifdef BLUE
#undef BLUE
#endif
#ifdef GRAY
#undef GRAY
#endif
#ifdef LIGHT_GRAY
#undef LIGHT_GRAY
#endif
#ifdef DARK_GRAY
#undef DARK_GRAY
#endif
#ifdef LIME
#undef LIME
#endif
#ifdef MAGENTA
#undef MAGENTA
#endif
#ifdef CYAN
#undef CYAN
#endif
#ifdef YELLOW
#undef YELLOW
#endif
#ifdef ORANGE
#undef ORANGE
#endif
#ifdef PURPLE
#undef PURPLE
#endif
#ifdef PINK
#undef PINK
#endif
#ifdef BROWN
#undef BROWN
#endif
';

	// ── FlxKey undefs ──────────────────────────────────────────────────────────
	static final UNDEFS_KEY = MARKER
		+ '
#ifdef NONE
#undef NONE
#endif
#ifdef ANY
#undef ANY
#endif
#ifdef A
#undef A
#endif
#ifdef B
#undef B
#endif
#ifdef C
#undef C
#endif
#ifdef D
#undef D
#endif
#ifdef E
#undef E
#endif
#ifdef F
#undef F
#endif
#ifdef G
#undef G
#endif
#ifdef H
#undef H
#endif
#ifdef I
#undef I
#endif
#ifdef J
#undef J
#endif
#ifdef K
#undef K
#endif
#ifdef L
#undef L
#endif
#ifdef M
#undef M
#endif
#ifdef N
#undef N
#endif
#ifdef O
#undef O
#endif
#ifdef P
#undef P
#endif
#ifdef Q
#undef Q
#endif
#ifdef R
#undef R
#endif
#ifdef S
#undef S
#endif
#ifdef T
#undef T
#endif
#ifdef U
#undef U
#endif
#ifdef V
#undef V
#endif
#ifdef W
#undef W
#endif
#ifdef X
#undef X
#endif
#ifdef Y
#undef Y
#endif
#ifdef Z
#undef Z
#endif
#ifdef ZERO
#undef ZERO
#endif
#ifdef ONE
#undef ONE
#endif
#ifdef TWO
#undef TWO
#endif
#ifdef THREE
#undef THREE
#endif
#ifdef FOUR
#undef FOUR
#endif
#ifdef FIVE
#undef FIVE
#endif
#ifdef SIX
#undef SIX
#endif
#ifdef SEVEN
#undef SEVEN
#endif
#ifdef EIGHT
#undef EIGHT
#endif
#ifdef NINE
#undef NINE
#endif
#ifdef NUMPAD_0
#undef NUMPAD_0
#endif
#ifdef NUMPAD_1
#undef NUMPAD_1
#endif
#ifdef NUMPAD_2
#undef NUMPAD_2
#endif
#ifdef NUMPAD_3
#undef NUMPAD_3
#endif
#ifdef NUMPAD_4
#undef NUMPAD_4
#endif
#ifdef NUMPAD_5
#undef NUMPAD_5
#endif
#ifdef NUMPAD_6
#undef NUMPAD_6
#endif
#ifdef NUMPAD_7
#undef NUMPAD_7
#endif
#ifdef NUMPAD_8
#undef NUMPAD_8
#endif
#ifdef NUMPAD_9
#undef NUMPAD_9
#endif
#ifdef NUMPAD_DECIMAL
#undef NUMPAD_DECIMAL
#endif
#ifdef NUMPAD_ADD
#undef NUMPAD_ADD
#endif
#ifdef NUMPAD_SUBTRACT
#undef NUMPAD_SUBTRACT
#endif
#ifdef NUMPAD_MULTIPLY
#undef NUMPAD_MULTIPLY
#endif
#ifdef NUMPAD_DIVIDE
#undef NUMPAD_DIVIDE
#endif
#ifdef F1
#undef F1
#endif
#ifdef F2
#undef F2
#endif
#ifdef F3
#undef F3
#endif
#ifdef F4
#undef F4
#endif
#ifdef F5
#undef F5
#endif
#ifdef F6
#undef F6
#endif
#ifdef F7
#undef F7
#endif
#ifdef F8
#undef F8
#endif
#ifdef F9
#undef F9
#endif
#ifdef F10
#undef F10
#endif
#ifdef F11
#undef F11
#endif
#ifdef F12
#undef F12
#endif
#ifdef HOME
#undef HOME
#endif
#ifdef END
#undef END
#endif
#ifdef PAGE_UP
#undef PAGE_UP
#endif
#ifdef PAGE_DOWN
#undef PAGE_DOWN
#endif
#ifdef UP
#undef UP
#endif
#ifdef DOWN
#undef DOWN
#endif
#ifdef LEFT
#undef LEFT
#endif
#ifdef RIGHT
#undef RIGHT
#endif
#ifdef ESCAPE
#undef ESCAPE
#endif
#ifdef BACKSPACE
#undef BACKSPACE
#endif
#ifdef TAB
#undef TAB
#endif
#ifdef ENTER
#undef ENTER
#endif
#ifdef SHIFT
#undef SHIFT
#endif
#ifdef CONTROL
#undef CONTROL
#endif
#ifdef ALT
#undef ALT
#endif
#ifdef CAPS_LOCK
#undef CAPS_LOCK
#endif
#ifdef NUM_LOCK
#undef NUM_LOCK
#endif
#ifdef SCROLL_LOCK
#undef SCROLL_LOCK
#endif
#ifdef INSERT
#undef INSERT
#endif
#ifdef DELETE
#undef DELETE
#endif
#ifdef SPACE
#undef SPACE
#endif
#ifdef MINUS
#undef MINUS
#endif
#ifdef PLUS
#undef PLUS
#endif
#ifdef PERIOD
#undef PERIOD
#endif
#ifdef COMMA
#undef COMMA
#endif
#ifdef SLASH
#undef SLASH
#endif
#ifdef BACK_SLASH
#undef BACK_SLASH
#endif
#ifdef GRAVEACCENT
#undef GRAVEACCENT
#endif
#ifdef QUOTE
#undef QUOTE
#endif
#ifdef SEMICOLON
#undef SEMICOLON
#endif
#ifdef LBRACKET
#undef LBRACKET
#endif
#ifdef RBRACKET
#undef RBRACKET
#endif
#ifdef WINDOWS
#undef WINDOWS
#endif
#ifdef COMMAND
#undef COMMAND
#endif
#ifdef BREAK
#undef BREAK
#endif
#ifdef PRINTSCREEN
#undef PRINTSCREEN
#endif
#ifdef PAUSE
#undef PAUSE
#endif
#ifdef PRINT
#undef PRINT
#endif
#ifdef ERROR
#undef ERROR
#endif
#ifdef BOOL
#undef BOOL
#endif
#ifdef VOID
#undef VOID
#endif
#ifdef TRUE
#undef TRUE
#endif
#ifdef FALSE
#undef FALSE
#endif
#ifdef IGNORE
#undef IGNORE
#endif
#ifdef INFINITE
#undef INFINITE
#endif
#ifdef DOMAIN
#undef DOMAIN
#endif
#ifdef OVERFLOW
#undef OVERFLOW
#endif
#ifdef UNDERFLOW
#undef UNDERFLOW
#endif
#ifdef PASCAL
#undef PASCAL
#endif
#ifdef CALLBACK
#undef CALLBACK
#endif
#ifdef FAR
#undef FAR
#endif
#ifdef NEAR
#undef NEAR
#endif
';

	// ══════════════════════════════════════════════════════════════════════════
	//  ENTRY POINT
	// ══════════════════════════════════════════════════════════════════════════

	public static function apply():Void {
		if (!Context.defined('cpp')) {
			trace('[WinMacroFix] Target is not cpp — skipping (no C++ headers generated)');
			return;
		}

		var cwd = Sys.getCwd().split("\\").join("/");
		if (cwd.endsWith("/"))
			cwd = cwd.substr(0, cwd.length - 1);
		var undefsPath = cwd + '/source/macros/WinUndefs.h';

		if (!FileSystem.exists(undefsPath)) {
			trace('[WinMacroFix v7] WARNING: source/macros/WinUndefs.h not found — @:headerCode fix skipped');
		} else {
			// #include con comillas dobles soporta espacios en la ruta (ISO C/C++)
			var meta = '@:headerCode(\'#include "$undefsPath"\')';

			// FlxKey: abstract enum cuyos valores colisionan con macros de windows.h
			// (DELETE, HOME, END, ESCAPE, etc.)
			// FlxKey: abstract enum cuyos valores colisionan con macros de windows.h
			// (DELETE, HOME, END, ESCAPE, etc.)
			Compiler.addGlobalMetadata("flixel.input.keyboard.FlxKey", meta, false, true, false);
			Compiler.addGlobalMetadata("flixel.input.keyboard._FlxKey", meta, true, true, false);

			// FlxColor: abstract cuyos valores colisionan con wingdi.h / winbase.h
			// (TRANSPARENT, BLACK, WHITE, RED, GREEN, BLUE, etc.)
			Compiler.addGlobalMetadata("flixel.util.FlxColor", meta, false, true, false);
			Compiler.addGlobalMetadata("flixel.util._FlxColor", meta, true, true, false);

			trace('[WinMacroFix v7] @:headerCode injection registered for FlxKey + FlxColor');
			trace('[WinMacroFix v7] WinUndefs.h path: $undefsPath');
		}

		// ══════════════════════════════════════════════════════════════════════
		//  LINUX / macOS — X11 macro conflicts (v7)
		// ══════════════════════════════════════════════════════════════════════
		//  X11's Xlib.h defines  #define Status int  (and Bool, True, False…).
		//  HXCPP-generated FlxKeyManager.h has  bool checkStatus(::Dynamic KeyCode, int Status)
		//  which the preprocessor expands to  int int  → "two or more data types" error.
		//
		//  WHY THE PREVIOUS ATTEMPT FAILED:
		//   1. It targeted "flixel.input.FlxKeyManager" but in flixel 6.x the
		//      checkStatus method is declared in FlxTypedKeyManager (the generic
		//      base).  FlxKeyManager.h may be just a typedef and never receives
		//      the @:headerCode injection.
		//   2. Even when the class is right, @:headerCode injects into *_obj.h
		//      which is pulled in AFTER the HXCPP precompiled header has already
		//      brought in X11 — the #undef fires too late.
		//
		//  FIX (belt + suspenders):
		//   • Primary (v7 @:headerCode): target the entire flixel.input package
		//     recursively so FlxTypedKeyManager, FlxKeyManager, FlxBaseKeyManager
		//     and any other class in that subtree all get the undefs.
		//   • Secondary (v6 Build.xml fallback): inject -include LinuxUndefs.h
		//     into Build.xml (GCC/Clang equivalent of MSVC /FI) so the undefs
		//     fire before EVERY translation unit, including those that include
		//     FlxKeyManager.h via the precompiled header path.
		if (Context.defined('linux') || Context.defined('mac')) {
			// Real newlines inside the string are required so the C preprocessor
			// sees each directive on its own line.  Use a Haxe string with \n.
			var x11Undefs = '#ifdef Status\n#undef Status\n#endif\n' + '#ifdef Bool\n#undef Bool\n#endif\n' + '#ifdef True\n#undef True\n#endif\n'
				+ '#ifdef False\n#undef False\n#endif\n' + '#ifdef None\n#undef None\n#endif\n' + '#ifdef Success\n#undef Success\n#endif\n'
				+ '#ifdef Always\n#undef Always\n#endif\n' + '#ifdef Expose\n#undef Expose\n#endif';

			// addGlobalMetadata takes the metadata as a Haxe source string.
			// The inner double-quoted string is parsed by the Haxe compiler,
			// so \n inside it becomes a real newline in the generated header.
			var linuxMeta = '@:headerCode("$x11Undefs")';

			// Target the whole flixel.input package (recursive = true) so
			// FlxKeyManager, FlxTypedKeyManager, FlxBaseKeyManager etc. all
			// receive the injection regardless of where the method is declared.
			Compiler.addGlobalMetadata("flixel.input", linuxMeta, true, true, false);

			trace('[WinMacroFix v7] @:headerCode X11 fix registered for flixel.input.* (recursive)');
		}

		// ══════════════════════════════════════════════════════════════════════
		//  SECONDARY / FALLBACK (v6) — onAfterGenerate patches
		// ══════════════════════════════════════════════════════════════════════
		//  Se mantiene como cinturón + tirantes por si @:headerCode no aplica
		//  en alguna configuración de HXCPP.
		Context.onAfterGenerate(function() {
			var cwd = Sys.getCwd().split("\\").join("/");
			if (cwd.endsWith("/"))
				cwd = cwd.substr(0, cwd.length - 1);

			var buildType = Context.defined('debug') ? 'debug' : 'release';
			if (Context.defined('32bit'))
				buildType = '32bit';

			trace('[WinMacroFix v6 fallback] buildType=$buildType  cwd=$cwd');

			// ── PRIMARY: patch Build.xml with /FI (Windows/MSVC) ─────────────
			// Source/WinUndefs.h must exist alongside this file.
			var winUndefsPath = cwd + '/source/macros/WinUndefs.h';
			if (!FileSystem.exists(winUndefsPath)) {
				trace('[WinMacroFix] WARNING: source/macros/WinUndefs.h not found at $winUndefsPath');
				trace('[WinMacroFix] Make sure WinUndefs.h is in your source/macros/ directory.');
			} else {
				var searchRoot = cwd + '/export/' + buildType;
				if (FileSystem.exists(searchRoot)) {
					var buildXmls = _findFiles(searchRoot, 'Build.xml');
					trace('[WinMacroFix] Found ${buildXmls.length} Build.xml file(s)');
					for (xmlPath in buildXmls)
						_patchBuildXml(xmlPath, winUndefsPath);
				} else
					trace('[WinMacroFix] WARNING: export dir not found: $searchRoot');
			}

			// ── PRIMARY (Linux/macOS): patch Build.xml with -include ──────────
			// GCC and Clang use  -include <path>  which is the exact equivalent
			// of MSVC's /FI.  This fires before EVERY translation unit, including
			// those that pull in X11 via the precompiled header, so the #undef
			// Status (and friends) always lands before FlxKeyManager.h is parsed.
			if (Context.defined('linux') || Context.defined('mac')) {
				var linuxUndefsPath = cwd + '/source/macros/LinuxUndefs.h';
				if (!FileSystem.exists(linuxUndefsPath)) {
					trace('[WinMacroFix] WARNING: source/macros/LinuxUndefs.h not found at $linuxUndefsPath');
					trace('[WinMacroFix] Make sure LinuxUndefs.h is in your source/macros/ directory.');
				} else {
					var searchRoot = cwd + '/export/' + buildType;
					if (FileSystem.exists(searchRoot)) {
						var buildXmls = _findFiles(searchRoot, 'Build.xml');
						trace('[WinMacroFix] Found ${buildXmls.length} Build.xml file(s) for -include patch');
						for (xmlPath in buildXmls)
							_patchBuildXmlGcc(xmlPath, linuxUndefsPath);
					} else
						trace('[WinMacroFix] WARNING: export dir not found: $searchRoot');
				}
			}

			// ── SECONDARY (belt + suspenders): patch headers directly ─────────
			// Even if HXCPP restores headers from cache, the /FI from Build.xml
			// will apply the undefs first. But patching headers is kept as a
			// safety net for environments where /FI behaves unexpectedly.
			var colorRel = 'flixel/util/_FlxColor/FlxColor_Impl_.h';
			var keyRel = 'flixel/input/keyboard/_FlxKey/FlxKey_Impl_.h';

			var headerTargets:Array<{path:String, undefs:String, cls:String}> = [];

			// 1. HXCPP_OUT env var
			var envOut = Context.definedValue('HXCPP_OUT') ?? '';
			if (envOut != '') {
				var base = envOut.split("\\").join("/");
				_tryAdd(headerTargets, base + '/include/' + colorRel, UNDEFS_COLOR, 'FlxColor_Impl_');
				_tryAdd(headerTargets, base + '/include/' + keyRel, UNDEFS_KEY, 'FlxKey_Impl_');
			}

			// 2. Recursive search under export/<buildType>/ — NO early exit (v5+)
			{
				var needles = [
					{rel: colorRel, undefs: UNDEFS_COLOR, cls: 'FlxColor_Impl_'},
					{rel: keyRel, undefs: UNDEFS_KEY, cls: 'FlxKey_Impl_'},
				];
				var searchRoot = cwd + '/export/' + buildType;
				if (FileSystem.exists(searchRoot))
					for (t in _findHeaders(searchRoot, needles))
						if (!_alreadyHas(headerTargets, t.path))
							headerTargets.push(t);
			}

			// 3. HXCPP global cache
			{
				var cache = Sys.getEnv("HXCPP_CACHE") ?? '';
				if (cache != '' && FileSystem.exists(cache)) {
					var needles = [
						{rel: colorRel, undefs: UNDEFS_COLOR, cls: 'FlxColor_Impl_'},
						{rel: keyRel, undefs: UNDEFS_KEY, cls: 'FlxKey_Impl_'},
					];
					for (t in _findHeaders(cache, needles))
						if (!_alreadyHas(headerTargets, t.path))
							headerTargets.push(t);
				}
			}

			trace('[WinMacroFix] Header targets: ${headerTargets.length}');
			for (t in headerTargets)
				trace('[WinMacroFix]   -> ${t.path}');

			for (t in headerTargets)
				_patchHeader(t.path, t.undefs, t.cls);
		});
	}

	// ══════════════════════════════════════════════════════════════════════════
	//  BUILD.XML PATCHING
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Parchea Build.xml añadiendo un compilerflag /FI que force-incluye
	 * WinUndefs.h antes de cualquier otro header en cada unidad de compilación.
	 *
	 * HXCPP lee Build.xml directamente (no lo cachea), así que este parche
	 * sobrevive al sistema de caché de HXCPP y garantiza que los #undef
	 * siempre se apliquen antes de que FlxKey_Impl_.h o FlxColor_Impl_.h
	 * sean procesados por MSVC.
	 *
	 * El parche se inserta DESPUÉS de la apertura de <target id="default">,
	 * que es donde HXCPP espera los flags de compilación.
	 */
	static function _patchBuildXml(xmlPath:String, winUndefsPath:String):Void {
		var content:String;
		try {
			content = File.getContent(xmlPath);
		} catch (e) {
			trace('[WinMacroFix] Cannot read Build.xml: $xmlPath — $e');
			return;
		}

		// Ya parcheado con esta versión — salir (útil en builds incrementales
		// donde Haxe no regenera Build.xml si nada cambió).
		if (content.indexOf(MARKER_XML) != -1) {
			trace('[WinMacroFix] Build.xml already patched: $xmlPath');
			return;
		}

		// Buscar el tag de apertura del target principal
		var needle = '<target id="default"';
		var idx = content.indexOf(needle);
		if (idx < 0) {
			trace('[WinMacroFix] No <target id="default"> found in $xmlPath — skipping');
			return;
		}

		// Avanzar hasta el '>' de cierre del tag de apertura
		var tagEnd = content.indexOf('>', idx);
		if (tagEnd < 0) {
			trace('[WinMacroFix] Malformed <target> tag in $xmlPath');
			return;
		}
		tagEnd++; // incluir el '>'

		// MSVC /FI flag: /FI"path" (sin espacio entre /FI y la ruta).
		// &quot; es la entidad XML para las comillas dobles necesarias para
		// manejar rutas con espacios (ej. "H:/MOD FNF/FNF-Cool-Engine/...").
		var escapedPath = winUndefsPath; // ya está en formato forward-slash
		var flag = '\n\t\t$MARKER_XML' + '\n\t\t<compilerflag value="/FI&quot;$escapedPath&quot;"/>';

		content = content.substr(0, tagEnd) + flag + content.substr(tagEnd);

		try {
			File.saveContent(xmlPath, content);
			trace('[WinMacroFix] Patched Build.xml with /FI flag: $xmlPath');
		} catch (e) {
			trace('[WinMacroFix] Cannot write Build.xml: $xmlPath — $e');
		}
	}

	// ══════════════════════════════════════════════════════════════════════════
	//  BUILD.XML PATCHING — Linux/macOS (GCC/Clang -include flag)
	// ══════════════════════════════════════════════════════════════════════════

	/**
	 * Linux/macOS equivalent of _patchBuildXml.
	 * Injects a  -include /path/to/LinuxUndefs.h  compilerflag into Build.xml.
	 * GCC and Clang's -include behaves identically to MSVC's /FI: the specified
	 * file is force-included at the start of every translation unit, BEFORE the
	 * source file's own includes.  This guarantees #undef Status (and the other
	 * X11 macros) fires before FlxKeyManager.h or any other flixel header is
	 * processed, regardless of precompiled headers.
	 *
	 * Note: unlike MSVC's /FI, GCC/Clang -include does NOT need quoting for
	 * spaces in the path when expressed as an XML attribute value — XML handles
	 * that automatically.  If the path contains spaces, the Build.xml attribute
	 * value itself carries them safely.
	 */
	static function _patchBuildXmlGcc(xmlPath:String, linuxUndefsPath:String):Void {
		var content:String;
		try {
			content = File.getContent(xmlPath);
		} catch (e) {
			trace('[WinMacroFix] Cannot read Build.xml: $xmlPath — $e');
			return;
		}

		// Already patched with this version — skip (safe for incremental builds).
		if (content.indexOf(MARKER_XML) != -1) {
			trace('[WinMacroFix] Build.xml already patched (gcc): $xmlPath');
			return;
		}

		var needle = '<target id="default"';
		var idx = content.indexOf(needle);
		if (idx < 0) {
			trace('[WinMacroFix] No <target id="default"> found in $xmlPath — skipping');
			return;
		}

		var tagEnd = content.indexOf('>', idx);
		if (tagEnd < 0) {
			trace('[WinMacroFix] Malformed <target> tag in $xmlPath');
			return;
		}
		tagEnd++;

		// GCC/Clang:  -include <path>  (no quoting needed in XML attribute).
		var flag = '\n\t\t$MARKER_XML' + '\n\t\t<compilerflag value="-include $linuxUndefsPath"/>';

		content = content.substr(0, tagEnd) + flag + content.substr(tagEnd);

		try {
			File.saveContent(xmlPath, content);
			trace('[WinMacroFix] Patched Build.xml with -include flag (gcc): $xmlPath');
		} catch (e) {
			trace('[WinMacroFix] Cannot write Build.xml: $xmlPath — $e');
		}
	}

	static function _patchHeader(path:String, undefs:String, className:String):Void {
		var content:String;
		try {
			content = File.getContent(path);
		} catch (e) {
			trace('[WinMacroFix] Cannot read header: $path — $e');
			return;
		}

		if (content.indexOf(MARKER) != -1) {
			trace('[WinMacroFix] Header already patched: $path');
			return;
		}

		content = _stripOldUndefs(content);

		var insertIdx = _findClassInsertPoint(content, className);
		if (insertIdx < 0)
			insertIdx = _findAfterLastInclude(content);

		if (insertIdx < 0) {
			trace('[WinMacroFix] WARNING: no insert point found in $path — skipping');
			return;
		}

		content = content.substr(0, insertIdx) + '\n' + undefs + '\n' + content.substr(insertIdx);

		try {
			File.saveContent(path, content);
			trace('[WinMacroFix] Patched header: $path');
		} catch (e) {
			trace('[WinMacroFix] Cannot write header: $path — $e');
		}
	}

	static function _stripOldUndefs(content:String):String {
		var lines = content.split('\n');
		var result = [];
		var i = 0;
		while (i < lines.length) {
			var line = lines[i].trim();
			if (line.startsWith('// WinMacroFix')) {
				i++;
				continue;
			}
			if (line.startsWith('#ifdef ') && i + 2 < lines.length) {
				var sym = line.substr(7).trim();
				var next1 = lines[i + 1].trim();
				var next2 = lines[i + 2].trim();
				if (next1 == '#undef ' + sym && next2 == '#endif') {
					i += 3;
					while (i < lines.length && lines[i].trim() == '')
						i++;
					continue;
				}
			}
			result.push(lines[i]);
			i++;
		}
		return result.join('\n');
	}

	static function _findClassInsertPoint(content:String, className:String):Int {
		var needle = 'class ' + className;
		var pos = 0;
		while (true) {
			var idx = content.indexOf(needle, pos);
			if (idx < 0)
				return -1;
			var after = idx + needle.length;
			if (after >= content.length)
				return idx;
			var ch = content.charCodeAt(after);
			if (ch == 32 || ch == 10 || ch == 13 || ch == 58 || ch == 123)
				return idx;
			pos = idx + 1;
		}
	}

	static function _findAfterLastInclude(content:String):Int {
		var lastEnd = -1;
		var pos = 0;
		while (true) {
			var idx = content.indexOf('#include', pos);
			if (idx < 0)
				break;
			var lineEnd = content.indexOf('\n', idx);
			if (lineEnd < 0)
				lineEnd = content.length;
			else
				lineEnd++;
			lastEnd = lineEnd;
			pos = lineEnd;
		}
		return lastEnd;
	}

	// ══════════════════════════════════════════════════════════════════════════
	//  FILE SEARCH UTILITIES
	// ══════════════════════════════════════════════════════════════════════════

	/** Encuentra TODOS los archivos con nombre exacto `filename` bajo `startDir`. */
	static function _findFiles(startDir:String, filename:String):Array<String> {
		var out:Array<String> = [];
		_walkForFile(startDir, filename, out);
		return out;
	}

	static function _walkForFile(dir:String, filename:String, out:Array<String>):Void {
		var entries:Array<String>;
		try {
			entries = FileSystem.readDirectory(dir);
		} catch (_) {
			return;
		}
		for (entry in entries) {
			var full = dir + '/' + entry;
			if (FileSystem.isDirectory(full)) {
				if (entry == 'assets' || entry == 'backup')
					continue;
				_walkForFile(full, filename, out);
			} else if (entry == filename)
				out.push(full.split("\\").join("/"));
		}
	}

	/** Encuentra TODAS las copias de los headers especificados en `needles`.
	 *  v6: sin early-exit — busca en TODO el árbol para cubrir tanto
	 *  cpp/include/ como obj/include/ y cualquier otra ubicación. */
	static function _findHeaders(startDir:String, needles:Array<{rel:String, undefs:String, cls:String}>):Array<{path:String, undefs:String, cls:String}> {
		var out:Array<{path:String, undefs:String, cls:String}> = [];
		_walk(startDir, needles, out);
		return out;
	}

	static function _walk(dir:String, needles:Array<{rel:String, undefs:String, cls:String}>, out:Array<{path:String, undefs:String, cls:String}>):Void {
		// v6: SIN early-exit — encontrar TODAS las copias del header.
		var entries:Array<String>;
		try {
			entries = FileSystem.readDirectory(dir);
		} catch (_) {
			return;
		}
		for (entry in entries) {
			var full = dir + '/' + entry;
			if (FileSystem.isDirectory(full)) {
				if (entry == 'assets' || entry == 'backup')
					continue;
				_walk(full, needles, out);
			} else {
				var norm = full.split("\\").join("/");
				for (n in needles)
					if (norm.endsWith('/' + n.rel) && !_alreadyHas(out, norm)) {
						out.push({path: norm, undefs: n.undefs, cls: n.cls});
						break;
					}
			}
		}
	}

	static function _tryAdd(arr:Array<{path:String, undefs:String, cls:String}>, path:String, undefs:String, cls:String):Void {
		if (FileSystem.exists(path) && !_alreadyHas(arr, path))
			arr.push({path: path, undefs: undefs, cls: cls});
	}

	static function _alreadyHas(arr:Array<{path:String, undefs:String, cls:String}>, path:String):Bool {
		for (t in arr)
			if (t.path == path)
				return true;
		return false;
	}
}
#end
