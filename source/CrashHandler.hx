package;

/**
 * CrashHandler — Cool Engine (v4)
 *
 * ── What's new in v4 ─────────────────────────────────────────────────────────
 *
 *  v3 introduced CrashWatcher.exe as an independent sibling process so crash
 *  dialogs appear even when the game's heap is too corrupt to run any code.
 *
 *  v4 focuses on making crash reports ACTIONABLE rather than just readable:
 *
 *  1. TRACE BUFFER  — The last 60 trace() calls are captured in a circular
 *     buffer and appended to every crash report, showing execution history
 *     leading up to the crash without any extra work from callers.
 *
 *  2. BREADCRUMBS   — CrashHandler.breadcrumb("LoadChart", {song:"Bopeebo"})
 *     records checkpoints. The last 20 are included in the crash report,
 *     identifying the high-level operation that was in progress.
 *
 *  3. FRAME TAGS    — Every stack frame is labelled [USER], [LIB ], [MOD ] or
 *     [C++ ].  The first [USER] frame gets a "← likely crash location" marker.
 *     CrashWatcher.exe syntax-highlights these tags with different colours.
 *
 *  4. LIVE SNAPSHOT — At crash time, the handler reads the current song, chart
 *     difficulty, and FlxG state via reflection (no PlayState import) and
 *     appends them to the report.
 *
 *  5. WARN DEDUP    — warn() skips identical errors within a 5-second window
 *     so a looping script error doesn't spawn 60 warning dialogs per second.
 *
 *  6. LOG ROTATION  — The crash folder is pruned to the 20 most recent files
 *     before each new log is written.
 *
 *  7. RICHER INFO   — Static section now includes GPU renderer, OpenGL version,
 *     Flixel / OpenFL versions, and the absolute crash-dir path.
 *
 * ── Architecture ─────────────────────────────────────────────────────────────
 *
 *  init()
 *    ├─ _spawnWatcher()         → CrashWatcher.exe --pid X --logdir <abs>
 *    ├─ haxe.Log.trace hook     → fills _traceLog[] circular buffer
 *    ├─ UncaughtErrorEvent      → _onUncaughtError()  (Hook A)
 *    └─ hxcpp critical hook     → _onCriticalError()  (Hook B, cpp only)
 *
 *  warn(error, ?context)        → log + WarningDialog (game continues)
 *  report(error, ?ctx, fatal)   → log + optional fatal exit
 *  breadcrumb(label, ?data)     → circular buffer of checkpoints
 *
 * ── Usage ────────────────────────────────────────────────────────────────────
 *
 *  // In Main, before createGame():
 *  CrashHandler.init();
 *
 *  // Optional — sprinkle in hot paths for better crash context:
 *  CrashHandler.breadcrumb("LoadChart", {song: songName, diff: difficulty});
 *  CrashHandler.breadcrumb("SpawnPlayer");
 *
 *  // For non-fatal script / mod errors:
 *  try { script.run(); } catch (e) { CrashHandler.warn(e, "MyScript.run"); }
 *
 * ── Distribution ─────────────────────────────────────────────────────────────
 *
 *  Compile CrashWatcher.exe with tools/build_watcher.bat and place it next to
 *  the game executable.  Missing watcher → silent fallback to in-process hooks.
 */
import openfl.Lib;
import openfl.events.UncaughtErrorEvent;
import haxe.CallStack;
import haxe.CallStack.StackItem;
import haxe.io.Path;
#if sys
import sys.FileSystem;
import sys.io.File;
#end
#if (desktop && DISCORD_ALLOWED)
import data.Discord.DiscordClient;
#end

using StringTools;

// ── C++ declarations needed by _getOwnPid() ───────────────────────────────────
#if (cpp && windows)
@:headerCode('
#ifndef _CE_GCPID_FWD_DECLARED_
#define _CE_GCPID_FWD_DECLARED_
extern "C" __declspec(dllimport) unsigned long __stdcall GetCurrentProcessId(void);
#endif
')
#elseif (cpp && (linux || mac || android))
@:cppInclude("unistd.h")
#end
class CrashHandler {
	// =========================================================================
	//  CONFIGURATION
	// =========================================================================
	private static var CRASH_DIR:String = _resolveCrashDir();

	private static inline final LOG_PREFIX:String = "CoolEngine_";
	private static inline final REPORT_URL:String = "https://github.com/The-Cool-Engine-Crew/FNF-Cool-Engine/issues";
	private static inline final ENGINE_VERSION:String = "0.6.1B";
	private static inline final WATCHER_EXE:String = "CrashWatcher.exe";

	/** Maximum number of crash log files to keep in the crash folder. */
	private static inline final MAX_CRASH_LOGS:Int = 20;

	/** Maximum number of trace() entries stored in the circular buffer. */
	private static inline final TRACE_BUFFER_SIZE:Int = 60;

	/** Maximum number of breadcrumb entries to keep. */
	private static inline final BREADCRUMB_LIMIT:Int = 20;

	/**
	 * Minimum seconds between two warn() dialogs with the same error signature.
	 * Prevents a single looping script error from spamming hundreds of dialogs.
	 */
	private static inline final WARN_COOLDOWN_SECS:Float = 5.0;

	// =========================================================================
	//  INTERNAL STATE
	// =========================================================================
	private static var _initialized:Bool = false;
	private static var _handling:Bool = false;
	private static var _watcherRunning:Bool = false;
	private static var _inTrace:Bool = false;

	/** Pre-built system info (captured at init time while the heap is healthy). */
	private static var _staticInfo:String = "";

	/** Epoch at init() — used for relative timestamps in the trace buffer. */
	#if sys
	private static var _startTime:Float = 0;
	#end

	/** Circular buffer of the last TRACE_BUFFER_SIZE trace() calls. */
	private static var _traceLog:Array<String> = [];

	/**
	 * Breadcrumb trail — records high-level checkpoints set by callers.
	 * Each entry: { label, data, t } where t is seconds since init().
	 */
	private static var _breadcrumbs:Array<{label:String, data:String, t:Float}> = [];

	/**
	 * Deduplication map for warn().
	 * Maps error-signature → last-warn-timestamp (Sys.time()).
	 */
	private static var _recentWarnings:Map<String, Float> = new Map();

	/**
	 * Queue of script errors collected during startup / script loading.
	 * Call flushScriptWarnings() once loading is done to show them all
	 * in a single CrashWatcher warning dialog.
	 */
	private static var _scriptWarnings:Array<{script:String, func:String, line:Int, msg:String, lineContent:String}> = [];

	// =========================================================================
	//  PUBLIC API
	// =========================================================================

	/**
	 * Installs all crash hooks and spawns CrashWatcher.exe.
	 * Must be called once from Main before createGame().
	 */
	public static function init():Void {
		if (_initialized)
			return;
		_initialized = true;

		#if sys
		_startTime = Sys.time();
		#end

		_staticInfo = _buildStaticInfo();

		// ── Trace hook — fills circular buffer ───────────────────────────────
		try {
			var orig = haxe.Log.trace;
			haxe.Log.trace = function(v:Dynamic, ?pos:haxe.PosInfos) {
				if (!_inTrace) {
					_inTrace = true;
					try {
						#if sys
						var t = Std.int(Sys.time() - _startTime);
						var loc = pos != null ? '${pos.fileName}:${pos.lineNumber}' : "?";
						var entry = '[+${t}s $loc] ${Std.string(v)}';
						#else
						var loc = pos != null ? '${pos.fileName}:${pos.lineNumber}' : "?";
						var entry = '[$loc] ${Std.string(v)}';
						#end
						_traceLog.push(entry);
						if (_traceLog.length > TRACE_BUFFER_SIZE)
							_traceLog.shift();
					} catch (_) {}
					_inTrace = false;
				}
				try {
					orig(v, pos);
				} catch (_) {}
			};
		} catch (_) {}

		// ── External watcher (v3+, highest priority) ─────────────────────────
		_spawnWatcher();

		// ── Hook A: Haxe / OpenFL uncaught errors ────────────────────────────
		Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, _onUncaughtError, false, 1000);

		// ── Hook B: C++ null ptr / stack overflow / assert ───────────────────
		#if cpp
		untyped __global__.__hxcpp_set_critical_error_handler(_onCriticalError);
		#end

		trace('[CrashHandler] v4 ready. Crash dir → $CRASH_DIR');
	}

	/**
	 * Records a high-level checkpoint to aid crash diagnosis.
	 * The last BREADCRUMB_LIMIT entries appear in every crash report.
	 *
	 *   CrashHandler.breadcrumb("LoadChart", {song: "Bopeebo", diff: "Hard"});
	 *   CrashHandler.breadcrumb("SpawnCharacter", characterId);
	 */
	public static function breadcrumb(label:String, ?data:Dynamic):Void {
		try {
			#if sys
			var t = Sys.time() - _startTime;
			#else
			var t = 0.0;
			#end
			var dataStr = "";
			try {
				dataStr = data != null ? Std.string(data) : "";
			} catch (_) {}
			_breadcrumbs.push({label: label, data: dataStr, t: t});
			if (_breadcrumbs.length > BREADCRUMB_LIMIT)
				_breadcrumbs.shift();
		} catch (_) {}
	}

	/**
	 * Manually report an error.
	 * fatal=true  → saves log + shows dialog + Sys.exit(1)
	 * fatal=false → saves log only (+ dialog in debug builds)
	 */
	public static function report(error:Dynamic, ?context:String, fatal:Bool = false):Void {
		var message:String = "";
		try {
			var stack = _captureStack();
			var errorStr = _safeString(error, "(non-serialisable error)");
			var ctx:Null<String> = null;
			try {
				ctx = context;
			} catch (_) {}
			message = _buildReport(errorStr, ctx, stack);
		} catch (_:Dynamic) {
			message = "COOL ENGINE — ERROR\n" + _safeString(error, "(error)");
		}

		_logToConsoleAndFile(message);

		if (fatal) {
			try {
				_showAndExit(message);
			} catch (_) {
				try {
					_nativeDialog(_truncate(message, 2000), "Cool Engine — Fatal Error");
				} catch (_) {}
				#if sys
				try {
					Sys.exit(1);
				} catch (_) {}
				#end
			}
		}
		#if debug
		else {
			try {
				_nativeDialog('[NON-FATAL]\n\n' + message, "Cool Engine — Non-Fatal Error");
			} catch (_) {}
		}
		#end
	}

	/**
	 * Shows a non-fatal warning via CrashWatcher (amber dialog, OK only).
	 * Identical error messages within WARN_COOLDOWN_SECS are silently skipped
	 * to prevent looping scripts from spamming dialogs.
	 *
	 * The game continues running after this call returns.
	 */
	public static function warn(error:Dynamic, ?context:String):Void {
		var errorStr = _safeString(error, "(non-serialisable error)");

		// Deduplication — skip if we showed this same error recently
		#if sys
		var sig = _errorSignature(errorStr);
		var lastTime = _recentWarnings.get(sig);
		if (lastTime != null && (Sys.time() - lastTime) < WARN_COOLDOWN_SECS)
			return;
		_recentWarnings.set(sig, Sys.time());
		#end

		var message:String = "";
		try {
			var stack = _captureStack();
			message = _buildWarning(errorStr, context, stack);
		} catch (_:Dynamic) {
			message = "COOL ENGINE — SCRIPT WARNING\n" + errorStr;
		}

		_logToConsoleAndFile(message);

		// Non-blocking: spawn a separate CrashWatcher in warning mode
		#if (cpp && desktop)
		if (_spawnWarningDialog(message))
			return;
		#end

		// Fallback: in-process native dialog
		try {
			_nativeDialog('[SCRIPT WARNING]\n\n' + _truncate(message, 2000), "Cool Engine — Script Warning");
		} catch (_) {}
	}

	// =========================================================================
	//  SCRIPT WARNING QUEUE  (batch errors from load-time / hot-reload)
	// =========================================================================

	/**
	 * Enqueues a single script error to be shown later via flushScriptWarnings().
	 * Call this from HScriptInstance._handleError() during loadString / load.
	 *
	 * @param script      Script file name or path.
	 * @param func        Function where the error occurred ("loadString", "onUpdate", …).
	 * @param line        Line number in the script (-1 if unknown).
	 * @param msg         Human-readable error message.
	 * @param lineContent Optional: the actual source line that caused the error.
	 */
	public static function queueScriptWarning(script:String, func:String, line:Int, msg:String, ?lineContent:String):Void {
		try {
			if (script == null || script == "") script = "(unknown script)";
			if (func   == null || func   == "") func   = "?";
			if (msg    == null || msg    == "") msg    = "(unknown error)";
			_scriptWarnings.push({
				script      : script,
				func        : func,
				line        : line,
				msg         : msg,
				lineContent : (lineContent != null) ? lineContent : ""
			});
		} catch (_) {}
	}

	/**
	 * Flushes all queued script errors into a single CrashWatcher warning dialog.
	 * Call once from Main after all scripts have been loaded.
	 * No-op if the queue is empty.
	 */
	public static function flushScriptWarnings():Void {
		try {
			if (_scriptWarnings == null || _scriptWarnings.length == 0)
				return;

			var errors = _scriptWarnings.copy();
			_scriptWarnings = [];

			var count  = errors.length;
			var plural = count > 1 ? "s" : "";

			var sb = new StringBuf();

			// Header
			sb.add("===========================================\n");
			sb.add("  COOL ENGINE \u2014 SCRIPT LOAD WARNINGS\n");
			sb.add("===========================================\n\n");
			sb.add('$count script error$plural found during startup.\n');
			sb.add("The game will continue running, but the affected\n");
			sb.add("scripts may not work correctly.\n\n");
			sb.add("===========================================\n\n");

			// One block per error
			for (i in 0...errors.length) {
				var e = errors[i];
				sb.add('--- Error ${i + 1} of $count ---\n');
				sb.add('Script   : ${e.script}\n');
				sb.add('Function : ${e.func}\n');
				if (e.line > 0)
					sb.add('Line     : ${e.line}\n');
				sb.add('Error    : ${e.msg}\n');
				if (e.lineContent != null && e.lineContent != "")
					sb.add('Source   : ${e.lineContent}\n');
				sb.add('\n');
			}

			// Footer
			sb.add("===========================================\n");
			sb.add("None of these errors crashed the game.\n");
			sb.add("Fix the issues above and restart.\n");
			sb.add("===========================================\n");
			sb.add(REPORT_URL + "\n");

			warn(sb.toString(), "ScriptLoader");

		} catch (_) {}
	}

	// =========================================================================
	//  EXTERNAL WATCHER
	// =========================================================================

	private static function _spawnWatcher():Void {
		#if (cpp && desktop)
		try {
			#if sys
			if (!FileSystem.exists(WATCHER_EXE)) {
				trace('[CrashHandler] CrashWatcher.exe not found — using in-process fallback.');
				return;
			}
			#end

			var pid = _getOwnPid();
			if (pid <= 0) {
				trace('[CrashHandler] Could not get own PID — skipping external watcher.');
				return;
			}

			var dir = CRASH_DIR;
			if (dir == null || dir == "")
				dir = "./crash/";

			#if sys
			try {
				var abs = FileSystem.absolutePath(dir);
				if (abs != null && abs != "")
					dir = abs;
			} catch (_) {}
			#end

			var args = ["--pid", Std.string(pid), "--logdir", dir, "--url", REPORT_URL];

			new sys.io.Process(WATCHER_EXE, args);

			trace('[CrashHandler] CrashWatcher launched (PID=$pid).');
			_watcherRunning = true;
		} catch (e:Dynamic) {
			try {
				trace('[CrashHandler] CrashWatcher launch failed: ' + Std.string(e));
			} catch (_) {}
		}
		#end
	}

	/**
	 * Spawns CrashWatcher in --mode warning (non-blocking, game keeps running).
	 * Returns true if the spawn succeeded.
	 */
	private static function _spawnWarningDialog(message:String):Bool {
		#if (cpp && desktop && sys)
		try {
			if (!FileSystem.exists(WATCHER_EXE))
				return false;

			var logPath:Null<String> = null;
			try {
				logPath = _saveLog(message);
			} catch (_) {}
			if (logPath == null || logPath == "")
				return false;

			var args = ["--mode", "warning", "--logfile", logPath];

			new sys.io.Process(WATCHER_EXE, args);

			return true;
		} catch (_) {}
		#end
		return false;
	}

	private static function _getOwnPid():Int {
		#if cpp
		try {
			#if windows
			return untyped __cpp__("(int)GetCurrentProcessId()");
			#else
			return untyped __cpp__("(int)getpid()");
			#end
		} catch (_:Dynamic) {
			return -1;
		}
		#else
		return -1;
		#end
	}

	// =========================================================================
	//  INTERNAL HOOKS
	// =========================================================================

	private static function _onUncaughtError(e:UncaughtErrorEvent):Void {
		if (_handling)
			return;
		_handling = true;

		var message = "COOL ENGINE — UNCAUGHT ERROR\n(failed to build report)";
		try {
			var stack = _captureStack();
			var errorStr = _safeString(e.error, "(unknown error)");

			// Walk the haxe.Exception cause chain
			var causeChain:Array<String> = [];
			try {
				@:privateAccess
				var ex = haxe.Exception.caught(e.error);
				var cur = ex.previous;
				while (cur != null) {
					var msg = "";
					try {
						msg = cur.message;
					} catch (_) {
						msg = Std.string(cur);
					}
					if (msg != null && msg != "")
						causeChain.push(msg);
					cur = cur.previous;
				}
			} catch (_) {}

			message = _buildReport(errorStr, "UncaughtErrorEvent", stack, causeChain, null);
		} catch (_:Dynamic) {
			message = "COOL ENGINE — UNCAUGHT ERROR\n\n" + _safeString(e.error, "");
		}

		_logToConsoleAndFile(message);

		try {
			_showAndExit(message);
		} catch (_:Dynamic) {
			try {
				_nativeDialog(_truncate(message, 2000), "Cool Engine — Fatal Error");
			} catch (_) {}
			try {
				Sys.stderr().writeString("=== FATAL UNCAUGHT ERROR ===\n" + message + "\n");
			} catch (_) {}
			#if sys
			try {
				Sys.exit(1);
			} catch (_) {}
			#end
		}
	}

	/**
	 * Called by hxcpp for C++ critical errors (null ptr, stack overflow, assert).
	 * The heap may be partially corrupt — each block is in its own try/catch.
	 */
	#if cpp
	private static function _onCriticalError(cppMessage:String):Void {
		if (_handling)
			return;
		_handling = true;

		// ── 1. Build report ───────────────────────────────────────────────────
		var report = "COOL ENGINE — C++ CRASH\n";
		try {
			var cpp = cppMessage ?? "(no message)";
			var errorType = _classifyCppError(cpp);
			var stack = _captureStack();
			var nullDiag:Null<String> = null;
			try {
				nullDiag = _buildNullRefDiagnostic(cpp, stack);
			} catch (_) {}
			report = _buildReport(cpp, errorType, stack, null, nullDiag);
		} catch (_:Dynamic) {
			try {
				report += "\n" + Std.string(cppMessage);
			} catch (_) {}
		}

		// ── 2. Save log (uses only Float arithmetic and File — heap-safe) ─────
		var logPath = "";
		#if sys
		try {
			var dir = CRASH_DIR ?? "./crash/";
			if (!FileSystem.exists(dir))
				FileSystem.createDirectory(dir);
			var ts = Std.string(Std.int(Sys.time()));
			logPath = dir + LOG_PREFIX + ts + ".txt";
			File.saveContent(logPath, report + "\n");
		} catch (_) {
			logPath = "";
		}
		#end

		// ── 3. In-process dialog (only when watcher is not available) ─────────
		if (!_watcherRunning) {
			// On Android/iOS the native dialog has no scroll; use the overlay.
			// The overlay close button calls Sys.exit(1), so we return here to
			// avoid the unconditional Sys.exit(1) at step 5 below.
			#if (android || mobileC || ios)
			try {
				_showMobileScrollOverlay(report, "Cool Engine — Fatal Error", logPath != "" ? logPath : null);
				return;
			} catch (_:Dynamic) {}
			#end

			try {
				var msg = _truncate(report, 2000);
				if (logPath != "")
					try {
						msg += '\n\nLog: $logPath';
					} catch (_) {}
				_nativeDialog(msg, "Cool Engine — Fatal Error");
			} catch (_:Dynamic) {
				try {
					Sys.stderr().writeString("=== FATAL C++ CRASH ===\n" + report + "\n");
				} catch (_) {}
			}
		}

		// ── 4. Open crash folder ──────────────────────────────────────────────
		try {
			if (logPath != "")
				_openCrashFolder(CRASH_DIR);
		} catch (_) {}

		// ── 5. Exit — watcher detects non-zero exit code ─────────────────────
		try {
			Sys.exit(1);
		} catch (_) {}
	}
	#end

	// =========================================================================
	//  REPORT BUILDING
	// =========================================================================

	/**
	 * Builds a full crash report string.
	 * causeChain  — list of .previous exception messages (outermost first)
	 * extraSection — pre-formatted extra block to insert before the call stack
	 *                (used for null-ref diagnostics)
	 */
	private static function _buildReport(error:String, ?context:String, stack:Array<StackItem>, ?causeChain:Array<String>, ?extraSection:String):String {
		var sb = new StringBuf();
		_appendHeader(sb, false);

		if (context != null && context != "")
			sb.add('Context  : $context\n\n');

		sb.add('Error    : $error\n\n');

		// Null-ref / C++ diagnostic tips
		if (extraSection != null && extraSection != "") {
			sb.add(extraSection);
			sb.add('\n');
		}

		// Exception cause chain
		if (causeChain != null && causeChain.length > 0) {
			sb.add("--- Cause Chain (outermost → root) ---\n");
			for (i in 0...causeChain.length)
				sb.add('  [${i + 1}] ${causeChain[i]}\n');
			sb.add('\n');
		}

		// Call stack with frame tags
		_appendStack(sb, stack);

		// Breadcrumb trail
		_appendBreadcrumbs(sb);

		// Recent trace log
		_appendTraceLog(sb);

		// Runtime snapshot at crash time
		try {
			sb.add(_buildLiveSnapshot());
		} catch (_) {}

		_appendFooter(sb);
		return sb.toString();
	}

	/** Builds a warning-style (non-fatal) report for warn(). */
	private static function _buildWarning(error:String, ?context:String, stack:Array<StackItem>):String {
		var sb = new StringBuf();
		_appendHeader(sb, true);

		sb.add("⚠  This error did NOT crash the game. Functionality may be affected.\n\n");

		if (context != null && context != "")
			sb.add('Context  : $context\n\n');

		sb.add('Error    : $error\n\n');
		_appendStack(sb, stack);
		_appendBreadcrumbs(sb);
		_appendFooter(sb);

		return sb.toString();
	}

	/** Returns a human-readable category label for a C++ critical error. */
	private static function _classifyCppError(msg:String):String {
		if (msg == null)
			return "C++ Critical Error";
		var lo = msg.toLowerCase();
		if (lo.indexOf("null object reference") >= 0)
			return "C++ Critical Error — Null Object Reference";
		if (lo.indexOf("null function pointer") >= 0)
			return "C++ Critical Error — Null Function Pointer";
		if (lo.indexOf("invalid field") >= 0 && lo.indexOf("null") >= 0)
			return "C++ Critical Error — Field Access on Null";
		if (lo.indexOf("stack overflow") >= 0)
			return "C++ Critical Error — Stack Overflow";
		if (lo.indexOf("out of memory") >= 0)
			return "C++ Critical Error — Out of Memory";
		if (lo.indexOf("assert") >= 0)
			return "C++ Critical Error — Assertion Failed";
		if (lo.indexOf("access violation") >= 0)
			return "C++ Critical Error — Access Violation";
		return "C++ Critical Error";
	}

	/**
	 * For null-reference class errors, builds a diagnostic block that:
	 *   – identifies the most likely user-code frame
	 *   – explains what the error means
	 *   – lists common causes (including HScript / mod-specific ones)
	 * Returns null when the error is not a null-reference type.
	 */
	private static function _buildNullRefDiagnostic(msg:String, stack:Array<StackItem>):Null<String> {
		if (msg == null)
			return null;
		var lo = msg.toLowerCase();
		var isNullRef = lo.indexOf("null object") >= 0
			|| lo.indexOf("null function") >= 0
			|| (lo.indexOf("invalid field") >= 0 && lo.indexOf("null") >= 0);

		if (!isNullRef)
			return null;

		var sb = new StringBuf();
		sb.add("--- Null Reference Diagnostic ---\n");

		// Find first non-library frame as the probable crash site
		var firstUserFrame:Null<String> = null;
		var firstModFrame:Null<String> = null;
		if (stack != null) {
			for (item in stack) {
				switch (item) {
					case FilePos(s, file, line, _):
						if (file != null) {
							var tag = _getFrameTag(file, null);
							if (tag == "USER" && firstUserFrame == null)
								firstUserFrame = '$file:$line';
							if (tag == "MOD" && firstModFrame == null)
								firstModFrame = '$file:$line';
						}
					default:
				}
			}
		}

		if (firstModFrame != null) {
			sb.add('  ⚠ Likely from mod/script : $firstModFrame\n');
			sb.add('    This crash may originate from a mod or HScript file.\n');
		} else if (firstUserFrame != null)
			sb.add('  Most likely location     : $firstUserFrame\n');

		sb.add('\n  What this means:\n');
		if (lo.indexOf("null function pointer") >= 0) {
			sb.add('    A function variable or callback was null when called.\n');
			sb.add('    Common causes:\n');
			sb.add('      • Callback/listener was never assigned before being called\n');
			sb.add('      • A dynamic function field was explicitly set to null\n');
			sb.add('      • An HScript function reference was not resolved correctly\n');
			sb.add('      • A listener registered to a destroyed object\n');
		} else {
			sb.add('    An object was used (field access / method call) while null.\n');
			sb.add('    Common causes:\n');
			sb.add('      • Accessing a field before the object is created\n');
			sb.add('      • A mod or HScript returned null where an object was expected\n');
			sb.add('      • An asset (sprite, sound) failed to load and returned null\n');
			sb.add('      • A FlxSprite/FlxGroup member was destroyed mid-update\n');
			sb.add('      • A singleton (e.g. PlayState.instance) accessed outside its lifetime\n');
			sb.add('      • A variable captured in a closure was already GC\'d\n');
		}

		return sb.toString();
	}

	// =========================================================================
	//  REPORT SECTIONS
	// =========================================================================

	private static function _appendHeader(sb:StringBuf, isWarning:Bool):Void {
		if (isWarning) {
			sb.add("===========================================\n");
			sb.add("     COOL ENGINE — SCRIPT WARNING\n");
			sb.add("===========================================\n\n");
		} else {
			sb.add("===========================================\n");
			sb.add("       COOL ENGINE — CRASH REPORT\n");
			sb.add("===========================================\n\n");
		}
		sb.add(_staticInfo);
		sb.add("\n===========================================\n\n");
	}

	private static function _appendFooter(sb:StringBuf):Void {
		sb.add('\n===========================================\n');
		sb.add('Report this issue at:\n');
		sb.add('$REPORT_URL\n');
		sb.add('===========================================\n');
	}

	/**
	 * Appends the call stack with [USER] / [LIB ] / [MOD ] / [C++ ] frame tags.
	 * The first [USER] frame gets a "← likely crash location" marker.
	 */
	private static function _appendStack(sb:StringBuf, stack:Array<StackItem>):Void {
		if (stack == null || stack.length == 0) {
			sb.add("--- Call Stack ---\n(not available)\n\n");
			return;
		}

		sb.add("--- Call Stack ---\n");
		var markedFirst = false;
		for (item in stack) {
			switch (item) {
				case FilePos(s, file, line, column):
					var col = (column != null) ? ':$column' : '';
					var method = "";
					var methCls:Null<String> = null;
					if (s != null)
						switch (s) {
							case Method(cls, m):
								method = ' [$cls.$m()]';
								methCls = cls;
							default:
						}
					var tag = _getFrameTag(file, methCls);
					var marker = (tag == "USER" && !markedFirst) ? "  ← likely crash location" : "";
					if (tag == "USER" && !markedFirst)
						markedFirst = true;
					sb.add('  [$tag] $file:$line$col$method$marker\n');

				case CFunction:
					sb.add("  [C++ ] (native C function)\n");

				case Module(m):
					sb.add('  [LIB ] [Module: $m]\n');

				case Method(cls, method):
					var tag = _getFrameTag(null, cls);
					sb.add('  [$tag] $cls.$method()\n');

				case LocalFunction(v):
					sb.add('  [USER] [LocalFunction #$v]\n');

				default:
					sb.add('  [????] ${Std.string(item)}\n');
			}
		}
		sb.add('\n');
	}

	private static function _appendBreadcrumbs(sb:StringBuf):Void {
		if (_breadcrumbs == null || _breadcrumbs.length == 0)
			return;

		sb.add("--- Breadcrumbs (oldest → newest) ---\n");
		for (bc in _breadcrumbs) {
			var data = (bc.data != null && bc.data != "") ? '  |  ${bc.data}' : "";
			var t = '${bc.t > 0 ? "+${Std.int(bc.t)}s" : "init"}';
			sb.add('  [$t] ${bc.label}$data\n');
		}
		sb.add('\n');
	}

	private static function _appendTraceLog(sb:StringBuf):Void {
		if (_traceLog == null || _traceLog.length == 0)
			return;

		sb.add('--- Recent Trace Log (last ${_traceLog.length} entries) ---\n');
		for (entry in _traceLog)
			sb.add('  $entry\n');
		sb.add('\n');
	}

	// =========================================================================
	//  SYSTEM / RUNTIME INFO
	// =========================================================================

	/**
	 * Builds the static info block captured at init() while the heap is healthy.
	 * Includes engine version, OS, GPU, library versions, and initial Flixel state.
	 */
	private static function _buildStaticInfo():String {
		var sb = new StringBuf();

		sb.add('Version  : $ENGINE_VERSION\n');
		sb.add('Date     : ${Date.now().toString()}\n');
		sb.add('System   : ${_systemName()}\n');

		// CPU core count
		#if sys
		try {
			var env = Sys.getEnv("NUMBER_OF_PROCESSORS");
			if (env != null && env != "")
				sb.add('CPU Cores: $env\n');
		} catch (_) {}
		#end

		// GPU info via OpenGL
		try {
			var renderer = lime.graphics.opengl.GL.getString(lime.graphics.opengl.GL.RENDERER);
			if (renderer != null && renderer != "")
				sb.add('GPU      : $renderer\n');
			var glVersion = lime.graphics.opengl.GL.getString(lime.graphics.opengl.GL.VERSION);
			if (glVersion != null && glVersion != "")
				sb.add('GL       : $glVersion\n');
		} catch (_) {}

		// Library versions
		#if flixel
		try {
			sb.add('Flixel   : ${flixel.FlxG.VERSION}\n');
		} catch (_) {}
		#end

		// Memory at startup
		#if sys
		sb.add('Memory   : ${_memMB()} MB used\n');
		#end

		// Window info
		try {
			var app = lime.app.Application.current;
			if (app != null && app.window != null)
				sb.add('Window   : ${app.window.width}x${app.window.height}\n');
		} catch (_) {}

		// Crash dir (absolute path)
		#if sys
		try {
			var abs = FileSystem.absolutePath(CRASH_DIR);
			sb.add('Crash dir: $abs\n');
		} catch (_) {}
		#end

		// Initial Flixel state
		sb.add('\n--- Initial State ---\n');
		try {
			if (flixel.FlxG.game != null && flixel.FlxG.state != null) {
				var cls = Type.getClass(flixel.FlxG.state);
				sb.add('State    : ${cls != null ? Type.getClassName(cls) : "???"}\n');
				sb.add('FPS      : ${Math.round(openfl.Lib.current.stage.frameRate)}\n');
			} else
				sb.add('State    : (FlxG not available at init)\n');
		} catch (_) {
			sb.add('State    : (error reading state)\n');
		}

		return sb.toString();
	}

	/**
	 * Captures a live runtime snapshot at crash time.
	 * Uses reflection to read PlayState without a compile-time dependency.
	 */
	private static function _buildLiveSnapshot():String {
		var sb = new StringBuf();
		sb.add("--- Live Snapshot (at crash time) ---\n");

		// Memory at crash time (may differ from startup value)
		#if sys
		try {
			sb.add('Memory   : ${_memMB()} MB used\n');
		} catch (_) {}
		#end

		// Current Flixel state + FPS
		try {
			if (flixel.FlxG.game != null) {
				var state = flixel.FlxG.state;
				if (state != null) {
					var cls = Type.getClass(state);
					sb.add('State    : ${cls != null ? Type.getClassName(cls) : "???"}\n');
				}
				try {
					sb.add('FPS      : ${Math.round(openfl.Lib.current.stage.frameRate)} fps\n');
				} catch (_) {}
			}
		} catch (_) {}

		// Song / difficulty via reflection — no PlayState import needed
		try {
			var psClass = Type.resolveClass("PlayState");
			if (psClass != null) {
				// Only snapshot if PlayState actually has an instance alive
				var inst = Reflect.getProperty(psClass, "instance");
				if (inst != null) {
					try {
						var song = Reflect.getProperty(psClass, "SONG");
						if (song != null) {
							var name = Reflect.getProperty(song, "song");
							if (name != null)
								sb.add('Song     : $name\n');
						}
					} catch (_) {}
					try {
						var diff = Reflect.getProperty(psClass, "storyDifficulty");
						if (diff != null)
							sb.add('Difficulty: $diff\n');
					} catch (_) {}
				}
			}
		} catch (_) {}

		return sb.toString() + '\n';
	}

	// =========================================================================
	//  NATIVE DIALOGS
	// =========================================================================

	// ── Mobile scrollable overlay (Android / iOS / mobileC) ──────────────────

	#if (android || mobileC || ios)
	/**
	 * Shows a full-screen OpenFL overlay with the crash report text.
	 *
	 * WHY: lime.app.Application.current.window.alert() on Android renders a
	 * standard AlertDialog that has no scroll support.  Long crash reports are
	 * silently truncated and the bottom frames (the most useful ones) are never
	 * visible.  This overlay replaces that with an openfl.text.TextField that:
	 *   • shows the full, untruncated report
	 *   • supports finger-drag scrolling
	 *   • calls Sys.exit(1) from the Close button so the app exits cleanly
	 *     (instead of from _showAndExit(), which would kill the app before the
	 *     user can read anything)
	 *
	 * @param message  Full crash-report string (NOT truncated).
	 * @param title    Title bar text.
	 * @param logPath  Optional: path to the saved .txt log (appended at bottom).
	 */
	private static function _showMobileScrollOverlay(message:String, title:String, ?logPath:String):Void
	{
		var stage = openfl.Lib.current.stage;
		final W:Float = stage.stageWidth;
		final H:Float = stage.stageHeight;

		// ── Root container ────────────────────────────────────────────────────
		var overlay = new openfl.display.Sprite();
		overlay.name = "__CrashOverlay__";

		// Opaque background (keeps the broken game render hidden)
		var bgShape = new openfl.display.Shape();
		bgShape.graphics.beginFill(0x0F0F0F, 0.97);
		bgShape.graphics.drawRect(0, 0, W, H);
		bgShape.graphics.endFill();
		overlay.addChild(bgShape);

		// ── Title bar ─────────────────────────────────────────────────────────
		var titleBar = new openfl.display.Shape();
		titleBar.graphics.beginFill(0xAA1111);
		titleBar.graphics.drawRect(0, 0, W, 64);
		titleBar.graphics.endFill();
		overlay.addChild(titleBar);

		var titleFmt = new openfl.text.TextFormat("_sans", 20, 0xFFFFFF, true);
		var titleField = new openfl.text.TextField();
		titleField.defaultTextFormat = titleFmt;
		titleField.text = title;
		titleField.x = 10;
		titleField.y = 14;
		titleField.width = W - 130;
		titleField.height = 44;
		titleField.selectable = false;
		titleField.mouseEnabled = false;
		overlay.addChild(titleField);

		// ── Close / Exit button ───────────────────────────────────────────────
		final BTN_W:Float = 110;
		final BTN_H:Float = 44;
		var closeBtn = new openfl.display.Sprite();

		var closeBg = new openfl.display.Shape();
		closeBg.graphics.beginFill(0x661111);
		closeBg.graphics.drawRoundRect(0, 0, BTN_W, BTN_H, 10, 10);
		closeBg.graphics.endFill();
		closeBtn.addChild(closeBg);

		var closeLbl = new openfl.text.TextField();
		closeLbl.defaultTextFormat = new openfl.text.TextFormat("_sans", 16, 0xFFFFFF, true);
		closeLbl.text = "Close";
		closeLbl.width = BTN_W;
		closeLbl.height = BTN_H;
		closeLbl.selectable = false;
		closeLbl.mouseEnabled = false;
		closeBtn.addChild(closeLbl);

		closeBtn.x = W - BTN_W - 8;
		closeBtn.y = 10;
		closeBtn.buttonMode = true;
		closeBtn.mouseChildren = false;
		closeBtn.useHandCursor = true;
		closeBtn.addEventListener(openfl.events.MouseEvent.CLICK, function(_)
		{
			try { stage.removeChild(overlay); } catch (_) {}
			try { Sys.exit(1);               } catch (_) {}
		});
		overlay.addChild(closeBtn);

		// ── Scrollable report text ────────────────────────────────────────────
		final MARGIN:Float = 10;
		final TOP:Float    = 70;

		var fullText = (message != null) ? message : "(no message)";
		if (logPath != null && logPath != "")
			fullText += '\n\n─────────────────────\nLog saved at:\n$logPath';

		var tf = new openfl.text.TextField();
		tf.defaultTextFormat = new openfl.text.TextFormat("_typewriter", 14, 0xDDDDDD);
		tf.multiline  = true;
		tf.wordWrap   = true;
		tf.text       = fullText;
		tf.x          = MARGIN;
		tf.y          = TOP;
		tf.width      = W - MARGIN * 2;
		tf.height     = H - TOP - MARGIN;
		tf.selectable = true;
		tf.scrollV    = 1;
		overlay.addChild(tf);

		// ── Touch-drag scrolling ──────────────────────────────────────────────
		// On Android/iOS, OpenFL maps touch events to MOUSE_DOWN/MOUSE_MOVE,
		// so standard MouseEvent listeners work for finger scrolling.
		var dragStartY:Float    = 0;
		var dragStartScroll:Int = 1;
		var dragging:Bool       = false;

		overlay.addEventListener(openfl.events.MouseEvent.MOUSE_DOWN, function(e:openfl.events.MouseEvent)
		{
			dragging       = true;
			dragStartY     = e.stageY;
			dragStartScroll = tf.scrollV;
		});
		// Register MOUSE_UP on stage so a fast swipe that leaves the overlay
		// still stops dragging.
		stage.addEventListener(openfl.events.MouseEvent.MOUSE_UP, function(_)
		{
			dragging = false;
		});
		overlay.addEventListener(openfl.events.MouseEvent.MOUSE_MOVE, function(e:openfl.events.MouseEvent)
		{
			if (!dragging) return;
			final delta:Float  = dragStartY - e.stageY;
			// Estimate pixel height per text line.
			final lineH:Float  = (tf.maxScrollV > 1) ? tf.textHeight / tf.maxScrollV : 20.0;
			var newV:Int = dragStartScroll + Std.int(delta / Math.max(lineH, 1.0));
			if (newV < 1)           newV = 1;
			if (newV > tf.maxScrollV) newV = tf.maxScrollV;
			tf.scrollV = newV;
		});

		stage.addChild(overlay);
	}
	#end

	/**
	 * Shows a modal error dialog using OS tools without going through Lime/OpenFL.
	 * Each platform spawns an independent process so there is no deadlock even
	 * if the render thread is blocked.
	 *
	 * Windows → PowerShell + Windows.Forms.MessageBox
	 * macOS   → osascript
	 * Linux   → zenity → kdialog → xmessage
	 * Fallback → lime.app.Application → stderr
	 */
	private static function _nativeDialog(message:String, title:String):Void {
		if (message == null)
			message = "(no message)";
		if (title == null)
			title = "Cool Engine — Error";

		var shown = false;

		#if (sys && windows)
		if (!shown)
			try {
				var msg = message.replace("'", "''");
				var ttl = title.replace("'", "''");
				var ps = "Add-Type -AssemblyName System.Windows.Forms;"
					+ "[System.Windows.Forms.MessageBox]::Show('"
					+ msg
					+ "','"
					+ ttl
					+ "',0,16)|Out-Null";
				var ret = Sys.command("powershell", ["-NonInteractive", "-Command", ps]);
				if (ret != 9009)
					shown = true;
			} catch (_) {}
		#end

		#if (sys && mac)
		if (!shown)
			try {
				var esc = message.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n");
				var escT = title.replace('"', '\\"');
				Sys.command("osascript", ["-e", 'display alert "$escT" message "$esc" as critical']);
				shown = true;
			} catch (_) {}
		#end

		#if (sys && linux)
		if (!shown)
			try {
				var ret = Sys.command("zenity", ["--error", '--title=$title', '--text=$message', "--width=600"]);
				if (ret != 127)
					shown = true;
			} catch (_) {}

		if (!shown)
			try {
				var ret = Sys.command("kdialog", ["--error", message, "--title", title]);
				if (ret != 127)
					shown = true;
			} catch (_) {}

		if (!shown)
			try {
				var ret = Sys.command("xmessage", ["-center", message]);
				if (ret != 127)
					shown = true;
			} catch (_) {}
		#end

		if (!shown)
			try {
				lime.app.Application.current.window.alert(_truncate(message, 3000), title);
				shown = true;
			} catch (_) {}

		if (!shown)
			try {
				Sys.stderr().writeString("=== FATAL CRASH ===\n" + message + "\n");
			} catch (_) {}
	}

	// =========================================================================
	//  HELPERS
	// =========================================================================

	/**
	 * Captures the exception stack, falling back to the call stack.
	 * Never throws — returns an empty array on failure.
	 */
	private static function _captureStack():Array<StackItem> {
		var stack = [];
		try {
			stack = CallStack.exceptionStack(true);
		} catch (_:Dynamic) {}
		if (stack.length == 0)
			try {
				stack = CallStack.callStack();
			} catch (_:Dynamic) {}
		return stack;
	}

	/** Returns a string representation of any value, never throws. */
	private static function _safeString(v:Dynamic, fallback:String):String {
		try {
			return Std.string(v);
		} catch (_:Dynamic) {
			return fallback;
		}
	}

	/** Prints to console and saves a log file. */
	private static function _logToConsoleAndFile(message:String):Void {
		#if sys
		try {
			Sys.println(message);
		} catch (_) {}
		try {
			var path = _saveLog(message);
			if (path != null)
				Sys.println('[CrashHandler] Log → ${Path.normalize(path)}');
		} catch (_) {}
		#end
	}

	/**
	 * Classifies a stack frame as USER, LIB, MOD, or C++.
	 * Tags are exactly 4 characters to align columns in the report.
	 */
	private static function _getFrameTag(file:Null<String>, cls:Null<String>):String {
		var path = "";
		if (file != null)
			path = file.toLowerCase();
		else if (cls != null)
			path = cls.toLowerCase();
		if (path == "")
			return "C++ ";

		// Mod / HScript files (check before lib to catch mod-loaded libs)
		if (path.indexOf("mods/") >= 0 || path.indexOf("mods\\") >= 0 || path.indexOf("scripts/") >= 0 || path.indexOf("scripts\\") >= 0
			|| path.indexOf("hscript") >= 0 || path.indexOf("polymod") >= 0 || path.indexOf("modscript") >= 0)
			return "MOD ";

		// Library frames
		if (path.indexOf("flixel/") >= 0 || path.indexOf("flixel\\") >= 0 || path.indexOf("openfl/") >= 0 || path.indexOf("openfl\\") >= 0
			|| path.indexOf("lime/") >= 0 || path.indexOf("lime\\") >= 0 || path.indexOf("hxcpp/") >= 0 || path.indexOf("hxcpp\\") >= 0
			|| path.indexOf("haxe/") >= 0 || path.indexOf("format/") >= 0)
			return "LIB ";

		return "USER";
	}

	/** A short hash of an error message used for warn() deduplication. */
	private static function _errorSignature(msg:String):String {
		if (msg == null || msg == "")
			return "empty";
		var clean = msg.replace("\r", "").replace("\n", " ").trim();
		return clean.length > 120 ? clean.substr(0, 120) : clean;
	}

	private static function _showAndExit(message:String):Void {
		#if (desktop && DISCORD_ALLOWED)
		try {
			DiscordClient.shutdown();
		} catch (_) {}
		#end

		var logPath:Null<String> = null;
		try {
			logPath = _saveLog(message);
		} catch (_) {}

		var dialogMsg = "(no message)";
		try {
			dialogMsg = _truncate(message, 2800);
			if (logPath != null)
				dialogMsg += '\n\n─────────────────────\nLog saved at:\n${Path.normalize(logPath)}';
		} catch (_) {
			try {
				dialogMsg = message;
			} catch (_) {}
		}

		// ── Mobile path ───────────────────────────────────────────────────────
		// On Android/iOS, lime.app.Application.current.window.alert() renders a
		// native AlertDialog without scroll support — long reports get truncated.
		// Show the custom OpenFL overlay instead.  The Close button calls
		// Sys.exit(1), so we must NOT call it here or the app dies before the
		// user can read the report.
		#if (android || mobileC || ios)
		try {
			_showMobileScrollOverlay(dialogMsg, "Cool Engine — Fatal Error", logPath);
			return; // ← overlay owns the exit; do NOT fall through to Sys.exit below
		} catch (_:Dynamic) {
			// Overlay failed (e.g. stage not ready) — fall back to native alert
			// and exit immediately so at least something is shown.
			try { lime.app.Application.current.window.alert(_truncate(message, 2000), "Cool Engine — Fatal Error"); } catch (_) {}
			try { Sys.exit(1); } catch (_) {}
			return;
		}
		#end

		// ── Desktop / other path ──────────────────────────────────────────────
		if (!_watcherRunning)
			try {
				_nativeDialog(dialogMsg, "Cool Engine — Fatal Error");
			} catch (_) {
				try {
					Sys.stderr().writeString("=== FATAL ERROR ===\n" + message + "\n");
				} catch (_) {}
			}

		try {
			if (logPath != null)
				_openCrashFolder(CRASH_DIR);
		} catch (_) {}

		#if sys
		try {
			Sys.exit(1);
		} catch (_) {}
		#end
	}

	private static function _saveLog(content:String):Null<String> {
		#if sys
		try {
			var dir = (CRASH_DIR != null && CRASH_DIR != "") ? CRASH_DIR : "./crash/";
			if (!FileSystem.exists(dir))
				FileSystem.createDirectory(dir);

			// Rotate old logs before writing a new one
			_pruneOldLogs(dir, MAX_CRASH_LOGS);

			var ts = "";
			try {
				ts = Date.now().toString().replace(" ", "_").replace(":", "-");
			} catch (_) {
				try {
					ts = Std.string(Std.int(Sys.time()));
				} catch (_) {
					ts = "unknown";
				}
			}

			var path = dir + LOG_PREFIX + ts + ".txt";
			File.saveContent(path, (content ?? "(empty)") + "\n");
			return path;
		} catch (e:Dynamic) {
			try {
				Sys.println("[CrashHandler] Could not save log: " + Std.string(e));
			} catch (_) {}
		}
		#end
		return null;
	}

	/**
	 * Deletes the oldest CoolEngine_*.txt files in dir so at most maxFiles remain
	 * (one slot is reserved for the file we are about to write).
	 */
	private static function _pruneOldLogs(dir:String, maxFiles:Int):Void {
		#if sys
		try {
			if (!FileSystem.exists(dir))
				return;
			var files = FileSystem.readDirectory(dir).filter(f -> f.startsWith(LOG_PREFIX) && f.endsWith(".txt")).map(f -> dir + f);

			files.sort((a, b) -> {
				var ta = FileSystem.stat(a).mtime.getTime();
				var tb = FileSystem.stat(b).mtime.getTime();
				return ta < tb ? -1 : (ta > tb ? 1 : 0);
			});

			while (files.length >= maxFiles) {
				try {
					FileSystem.deleteFile(files.shift());
				} catch (_) {}
			}
		} catch (_) {}
		#end
	}

	private static function _openCrashFolder(dir:String):Void {
		try {
			#if windows
			Sys.command("explorer", [Path.normalize(dir).replace("/", "\\")]);
			#elseif mac
			Sys.command("open", [dir]);
			#elseif linux
			Sys.command("xdg-open", [dir]);
			#end
		} catch (_) {}
	}

	private static function _truncate(s:String, max:Int):String {
		if (s == null || s.length <= max)
			return s ?? "";
		return s.substr(0, max) + "\n\n[... truncated — see full log file]";
	}

	private static function _resolveCrashDir():String {
		#if mobileC
		try {
			var base = lime.system.System.documentsDirectory;
			if (base == null || base == "")
				base = "./";
			if (!base.endsWith("/"))
				base += "/";
			return base + "CoolEngine/crash/";
		} catch (_:Dynamic) {
			return "./crash/";
		}
		#else
		return "./crash/";
		#end
	}

	private static function _systemName():String {
		#if sys
		return Sys.systemName();
		#elseif windows
		return "Windows";
		#elseif linux
		return "Linux";
		#elseif mac
		return "macOS";
		#else
		return "Unknown";
		#end
	}

	#if sys
	private static function _memMB():String {
		try {
			#if cpp
			var bytes = cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_USAGE);
			return Std.string(Math.round(bytes / 1024 / 1024));
			#else
			return Std.string(Math.round(openfl.system.System.totalMemory / 1024 / 1024));
			#end
		} catch (_) {
			return "??";
		}
	}
	#end
}
