package funkin.gameplay;

import flixel.FlxG;
import flixel.input.keyboard.FlxKey;
import flixel.util.FlxSignal.FlxTypedSignal;
import funkin.gameplay.notes.Note;
import flixel.group.FlxGroup.FlxTypedGroup;
import funkin.data.Conductor;
import funkin.data.SaveData;
import haxe.Int64;
import openfl.events.KeyboardEvent;
import openfl.Lib;
#if mobileC
import flixel.ui.FlxButton;
#end

using StringTools;

/**
 * Evento de input preciso — inspirado en el PreciseInputEvent de V-Slice.
 *
 * Transporta la dirección, el timestamp en nanosegundos y el keyCode original.
 * Permite medir latencia real entre la pulsación y el procesamiento de nota:
 *
 *   inputHandler.onInputPressed.add(function(e:PreciseInputEvent) {
 *     var lagMs = (InputHandler.getCurrentTimestamp() - e.timestamp).toFloat()
 *                 / InputHandler.NS_PER_MS;
 *     trace('Latencia: ${lagMs}ms');
 *   });
 */
typedef PreciseInputEvent =
{
	/** Dirección: 0=LEFT, 1=DOWN, 2=UP, 3=RIGHT */
	dir:Int,
	/**
	 * Timestamp en nanosegundos (Lib.getTimer() × NS_PER_MS).
	 * Solo útil para comparar contra otros timestamps del mismo sistema.
	 */
	timestamp:Int64,
	/** keyCode de OpenFL — distingue entre varios binds de la misma dirección. */
	keyCode:Int
};

/**
 * InputHandler — Input del jugador con detección sub-frame via OpenFL KeyboardEvent.
 *
 * ── MEJORAS vs versión anterior (inspiradas en V-Slice PreciseInputManager) ──
 *
 *  1. TIMESTAMPS Int64 en NANOSEGUNDOS:
 *     _pressTimeNs almacena Lib.getTimer() × NS_PER_MS. Permite medir latencias
 *     con mayor resolución. Compatible con getCurrentTimestamp() y
 *     getTimeSincePressed() para comparaciones consistentes.
 *
 *  2. FlxTypedSignal (V-Slice style):
 *     onInputPressed / onInputReleased son FlxTypedSignal<PreciseInputEvent->Void>.
 *     Se disparan sub-frame desde el handler de KeyboardEvent, no en update().
 *     Permiten múltiples suscriptores sin sobrescribir callbacks.
 *     Los callbacks heredados (onNoteHit, onNoteMiss, onKeyRelease) se mantienen
 *     para compatibilidad total con PlayState sin ningún cambio.
 *
 *  3. LOOKUP O(1) con _keyMap:
 *     Mapa FlxKey(Int) → dirección preconstruido en new() y rebuildKeyMap().
 *     Evita iterar los arrays de binds en cada evento de teclado.
 *
 *  4. bufferNs pre-calculado por frame:
 *     Se calcula una sola vez en processInputs() y se pasa a _processDir()
 *     en lugar de recalcular bufferTime * 1000 en cada dirección.
 *
 *  5. getTimeSincePressed(dir) / getTimeSinceReleased(dir):
 *     Equivalentes a PreciseInputManager.getTimeSincePressed() de V-Slice.
 *
 *  6. rebuildKeyMap():
 *     Reconstruye el mapa si los keybinds cambian en tiempo de ejecución.
 *
 * ── COMPATIBILIDAD con PlayState ────────────────────────────────────────────
 *
 *  API pública idéntica: pressed, held, released, onNoteHit, onNoteMiss,
 *  onKeyRelease, pressSongPos, clearBuffer(), resetMash(), anyKeyHeld().
 *  PlayState no necesita ninguna modificación.
 *
 * ── GHOST TAP OFF — misses diferidos ────────────────────────────────────────
 *
 *  Si el jugador pulsa sin nota en rango el miss queda "pendiente" durante
 *  la ventana del buffer. Si llega una nota antes de que expire se cancela.
 *  Solo si el buffer expira sin nota se dispara el miss.
 */
class InputHandler
{
	// ── CONSTANTE DE TIEMPO ───────────────────────────────────────────────────

	/** Nanosegundos por milisegundo. Lib.getTimer() devuelve ms; × NS_PER_MS = ns. */
	public static inline var NS_PER_MS:Int = 1_000_000;

	// ── KEYBINDS ─────────────────────────────────────────────────────────────

	public var leftBind:Array<FlxKey>  = [A, LEFT];
	public var downBind:Array<FlxKey>  = [S, DOWN];
	public var upBind:Array<FlxKey>    = [W, UP];
	public var rightBind:Array<FlxKey> = [D, RIGHT];
	public var killBind:Array<FlxKey>  = [R];

	/**
	 * Mapa FlxKey(Int) → dirección (0-3) para lookup O(1) en el hot path.
	 * Construido en new() a partir de los arrays *Bind.
	 */
	private var _keyMap:Map<Int, Int> = new Map<Int, Int>();

	// ── INPUT STATE ───────────────────────────────────────────────────────────

	/** true durante el frame en que se detectó la pulsación. */
	public var pressed:Array<Bool>  = [false, false, false, false];
	/** true mientras la tecla está físicamente pulsada. */
	public var held:Array<Bool>     = [false, false, false, false];
	/** true durante el frame en que se soltó la tecla. */
	public var released:Array<Bool> = [false, false, false, false];

	// ── SEÑALES PRECISAS (V-Slice style) ─────────────────────────────────────

	/**
	 * Disparada sub-frame en el KEY_DOWN handler.
	 * Múltiples suscriptores pueden añadirse con .add() sin sobrescribirse.
	 */
	public var onInputPressed:FlxTypedSignal<PreciseInputEvent->Void>;

	/** Disparada sub-frame en el KEY_UP handler. */
	public var onInputReleased:FlxTypedSignal<PreciseInputEvent->Void>;

	// ── CALLBACKS HEREDADOS (compat. con PlayState) ───────────────────────────

	public var onNoteHit:Note->Void   = null;
	public var onNoteMiss:Note->Void  = null;
	public var onKeyRelease:Int->Void = null;
	public var onKeyPress:Int->Void   = null;

	// ── CONFIG ────────────────────────────────────────────────────────────────

	public var ghostTapping:Bool   = true;
	public var inputBuffering:Bool = true;
	/** Ventana del buffer en SEGUNDOS (0.1 = 100ms). */
	public var bufferTime:Float    = 0.1;

	// ── ESTADO CRUDO (escrito por KEY_DOWN/KEY_UP, consumido en update()) ─────

	private var _rawHeld:Array<Bool>     = [false, false, false, false];
	private var _rawPressed:Array<Bool>  = [false, false, false, false];
	private var _rawReleased:Array<Bool> = [false, false, false, false];

	/**
	 * Timestamp en nanosegundos del KEY_DOWN más reciente por dirección.
	 * Capturado al inicio del handler para minimizar varianza.
	 */
	private var _pressTimeNs:Array<Int64>   = [0, 0, 0, 0];

	/** Timestamp en nanosegundos del KEY_UP más reciente por dirección. */
	private var _releaseTimeNs:Array<Int64> = [0, 0, 0, 0];

	// ── PRESS-TIME SONG POSITION ──────────────────────────────────────────────

	/**
	 * Conductor.songPosition en el frame en que se detectó cada pulsación.
	 * Usado por PlayState.onPlayerNoteHit() para que noteDiff refleje cuándo
	 * pulsó el jugador, no cuándo se procesó el buffer (hasta bufferTime después).
	 */
	public var pressSongPos:Array<Float> = [-1.0, -1.0, -1.0, -1.0];

	// ── INPUT BUFFER ──────────────────────────────────────────────────────────

	/** Timestamp (ns) de la última pulsación no procesada por dirección. */
	private var bufferedInputs:Array<Int64> = [0, 0, 0, 0];
	private var inputProcessed:Array<Bool>  = [false, false, false, false];

	// ── GHOST-TAP MISS DEFERRAL ───────────────────────────────────────────────

	private var _pendingGhostMiss:Array<Bool> = [false, false, false, false];

	// ── ANTI-MASH ─────────────────────────────────────────────────────────────

	private var mashCounter:Int    = 0;
	private var mashViolations:Int = 0;
	private static inline var MAX_MASH_VIOLATIONS:Int = 8;

	// ── NOTAS POR DIRECCIÓN (preallocadas) ────────────────────────────────────

	private var _notesByDir0:Array<Note> = [];
	private var _notesByDir1:Array<Note> = [];
	private var _notesByDir2:Array<Note> = [];
	private var _notesByDir3:Array<Note> = [];

	// ── CONTROLES MÓVILES ─────────────────────────────────────────────────────
	#if mobileC
	public var mobileLeft:FlxButton  = null;
	public var mobileDown:FlxButton  = null;
	public var mobileUp:FlxButton    = null;
	public var mobileRight:FlxButton = null;

	/**
	 * Estado held persistente para botones móviles (hitbox/vpad).
	 * held[] se resetea cada frame con _rawHeld[] (teclado), por lo que sin
	 * este array _updateMobileButton() detectaría un "justPressed" en cada
	 * frame que el botón estuviera pulsado, rompiendo sustains y el buffer.
	 */
	private var _mobileHeld:Array<Bool> = [false, false, false, false];

	// ── Strum Tap ─────────────────────────────────────────────────────────────

	/**
	 * Si true, el jugador toca sobre las flechas del strum para golpear notas
	 * en lugar de usar los botones del Hitbox / VirtualPad.
	 * Activado por PlayState cuando SaveData.data.strumTap == true.
	 */
	public var strumTapEnabled:Bool = false;

	/**
	 * Centro X en pantalla de cada strum del jugador (índice = dirección).
	 * 0=LEFT  1=DOWN  2=UP  3=RIGHT
	 * Asignado por PlayState.setupControllers() justo después de crear los strums.
	 */
	public var strumTapPositions:Array<Float> = [0.0, 0.0, 0.0, 0.0];

	/**
	 * Semiancho de la zona de toque alrededor del centro de cada strum.
	 * Default 60 px — ligeramente mayor que el spacing típico (110/2 = 55)
	 * para que sea cómodo de tocar sin ser impreciso.
	 */
	public var strumTapRadius:Float = 60.0;

	/** Estado held persistente por dirección en strum-tap mode. */
	private var _strumTapHeld:Array<Bool> = [false, false, false, false];

	/** Mapa touchId → dirección para rastrear cada dedo en strum-tap mode. */
	private var _strumTouchDir:Map<Int, Int> = new Map();
	#end

	// ── CONSTRUCTOR ───────────────────────────────────────────────────────────

	public function new()
	{
		leftBind[0]  = FlxKey.fromString(SaveData.data.leftBind);
		downBind[0]  = FlxKey.fromString(SaveData.data.downBind);
		upBind[0]    = FlxKey.fromString(SaveData.data.upBind);
		rightBind[0] = FlxKey.fromString(SaveData.data.rightBind);
		killBind[0]  = FlxKey.fromString(SaveData.data.killBind);

		onInputPressed  = new FlxTypedSignal<PreciseInputEvent->Void>();
		onInputReleased = new FlxTypedSignal<PreciseInputEvent->Void>();

		rebuildKeyMap();

		FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, _onKeyDown, false, 10);
		FlxG.stage.addEventListener(KeyboardEvent.KEY_UP,   _onKeyUp,   false, 10);
	}

	// ── TIMESTAMPS ────────────────────────────────────────────────────────────

	/**
	 * Timestamp actual en nanosegundos, compatible con _pressTimeNs.
	 * Lib.getTimer() devuelve ms desde el inicio; × NS_PER_MS convierte a ns.
	 */
	public static inline function getCurrentTimestamp():Int64
		return haxe.Int64.fromFloat(Lib.getTimer()) * NS_PER_MS;

	/**
	 * Tiempo transcurrido en ns desde la última pulsación de `dir`.
	 * Equivalente a PreciseInputManager.getTimeSincePressed() de V-Slice.
	 * @param dir Dirección (0=LEFT, 1=DOWN, 2=UP, 3=RIGHT).
	 */
	public inline function getTimeSincePressed(dir:Int):Int64
		return getCurrentTimestamp() - _pressTimeNs[dir];

	/**
	 * Tiempo transcurrido en ns desde el último release de `dir`.
	 */
	public inline function getTimeSinceReleased(dir:Int):Int64
		return getCurrentTimestamp() - _releaseTimeNs[dir];

	// ── GESTIÓN DE KEYBINDS ───────────────────────────────────────────────────

	/**
	 * Reconstruye el mapa FlxKey → dirección a partir de los arrays *Bind.
	 * Llamar si los keybinds cambian en tiempo de ejecución.
	 */
	public function rebuildKeyMap():Void
	{
		_keyMap.clear();
		for (k in leftBind)  _keyMap.set((k:Int), 0);
		for (k in downBind)  _keyMap.set((k:Int), 1);
		for (k in upBind)    _keyMap.set((k:Int), 2);
		for (k in rightBind) _keyMap.set((k:Int), 3);
	}

	/**
	 * Elimina los listeners de OpenFL y limpia las señales.
	 * Llamar en PlayState.destroy().
	 */
	public function destroy():Void
	{
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, _onKeyDown);
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_UP,   _onKeyUp);
		onInputPressed.removeAll();
		onInputReleased.removeAll();
	}

	// ── HANDLERS OPENFL (sub-frame) ───────────────────────────────────────────

	/**
	 * Llamado por OpenFL en el momento exacto del KEY_DOWN, fuera del update loop.
	 *
	 * El timestamp se captura al inicio del handler (antes de cualquier lógica)
	 * para minimizar la varianza. El key-repeat del OS se filtra con _rawHeld:
	 * solo el primer KEY_DOWN real actualiza _rawPressed y dispara onInputPressed.
	 */
	private function _onKeyDown(e:KeyboardEvent):Void
	{
		// Capturar timestamp lo antes posible en el handler
		final tsNs:Int64 = haxe.Int64.fromFloat(Lib.getTimer()) * NS_PER_MS;

		var dir:Int = _keyMap.exists(e.keyCode) ? _keyMap.get(e.keyCode) : -1;
		if (dir < 0) return;

		if (!_rawHeld[dir])
		{
			_rawPressed[dir]  = true;
			_pressTimeNs[dir] = tsNs;

			// Señal sub-frame (V-Slice style): se dispara aquí, no en update().
			// Permite medir latencia antes de que el frame procese el input.
			onInputPressed.dispatch({
				dir:       dir,
				timestamp: tsNs,
				keyCode:   e.keyCode
			});
		}
		_rawHeld[dir] = true;
	}

	/**
	 * Llamado por OpenFL en el momento exacto del KEY_UP.
	 */
	private function _onKeyUp(e:KeyboardEvent):Void
	{
		final tsNs:Int64 = haxe.Int64.fromFloat(Lib.getTimer()) * NS_PER_MS;

		var dir:Int = _keyMap.exists(e.keyCode) ? _keyMap.get(e.keyCode) : -1;
		if (dir < 0) return;

		_rawHeld[dir]       = false;
		_rawReleased[dir]   = true;
		_releaseTimeNs[dir] = tsNs;

		onInputReleased.dispatch({
			dir:       dir,
			timestamp: tsNs,
			keyCode:   e.keyCode
		});
	}

	// ── UPDATE ────────────────────────────────────────────────────────────────

	/**
	 * Consume los flags crudos y actualiza los arrays públicos pressed/held/released.
	 * Llamar una vez por frame desde PlayState.update().
	 */
	public function update():Void
	{
		for (dir in 0...4)
		{
			pressed[dir]  = _rawPressed[dir];
			held[dir]     = _rawHeld[dir];
			released[dir] = _rawReleased[dir];

			if (_rawReleased[dir])
			{
				_rawReleased[dir] = false;
				if (onKeyRelease != null) onKeyRelease(dir);
			}

			_rawPressed[dir] = false;
		}

		#if mobileC
		_updateMobileButton(mobileLeft,  0);
		_updateMobileButton(mobileDown,  1);
		_updateMobileButton(mobileUp,    2);
		_updateMobileButton(mobileRight, 3);

		if (strumTapEnabled)
			_updateStrumTap();
		#end
	}

	#if mobileC
	/**
	 * Actualiza el estado de un botón móvil usando _mobileHeld[] como
	 * referencia persistente entre frames.
	 *
	 * BUG ANTERIOR: usaba held[dir], que se resetea a _rawHeld[] (teclado)
	 * al inicio de update(). Resultado: cada frame con el botón pulsado se
	 * detectaba como "justPressed" de nuevo → onInputPressed en bucle,
	 * sustains rotos, pressSongPos siempre sobreescrito.
	 */
	private inline function _updateMobileButton(btn:FlxButton, dir:Int):Void
	{
		if (btn == null) return;

		final isPressed = (btn.status == flixel.ui.FlxButton.PRESSED);

		if (isPressed && !_mobileHeld[dir])
		{
			// Botón recién pulsado este frame
			final tsNs        = getCurrentTimestamp();
			_mobileHeld[dir]  = true;
			pressed[dir]      = true;
			held[dir]         = true;
			_pressTimeNs[dir] = tsNs;
			pressSongPos[dir] = Conductor.songPosition;
			onInputPressed.dispatch({dir: dir, timestamp: tsNs, keyCode: 0});
		}
		else if (isPressed)
		{
			// Botón mantenido — held debe seguir a true entre frames
			held[dir] = true;
		}

		if (!isPressed && _mobileHeld[dir])
		{
			// Botón recién soltado este frame
			final tsNs          = getCurrentTimestamp();
			_mobileHeld[dir]    = false;
			released[dir]       = true;
			_releaseTimeNs[dir] = tsNs;
			onInputReleased.dispatch({dir: dir, timestamp: tsNs, keyCode: 0});
			if (onKeyRelease != null) onKeyRelease(dir);
		}
	}

	/**
	 * Strum Tap — el jugador toca directamente sobre la zona de cada strum.
	 *
	 * Cada dedo se registra en _strumTouchDir al hacer justPressed con la
	 * dirección determinada por su X en pantalla. Mientras el dedo esté
	 * activo esa dirección se mantiene held. Al soltar, se dispara release.
	 *
	 * La asignación de dirección es "lock-on-press": si el dedo baja sobre
	 * LEFT y luego se desliza fuera de su zona, sigue siendo LEFT hasta
	 * que se suelte. Esto evita falsos cambios de dirección durante sustains.
	 */
	private function _updateStrumTap():Void
	{
		var nowHeld:Array<Bool> = [false, false, false, false];

		for (touch in FlxG.touches.list)
		{
			if (touch == null) continue;
			final id = touch.touchPointID;

			if (touch.justPressed)
			{
				final dir = _getStrumDirFromX(touch.screenX);
				if (dir >= 0)
					_strumTouchDir.set(id, dir);
				else
				{
					_strumTouchDir.remove(id);
					continue; // toque fuera de cualquier strum → ignorar
				}
			}

			if (!_strumTouchDir.exists(id)) continue;
			nowHeld[_strumTouchDir.get(id)] = true;

			if (touch.justReleased)
				_strumTouchDir.remove(id);
		}

		// Limpiar entradas de toques que ya no están activos (p.ej. forzados)
		for (id in _strumTouchDir.keys())
		{
			var alive = false;
			for (t in FlxG.touches.list)
				if (t != null && t.touchPointID == id) { alive = true; break; }
			if (!alive) _strumTouchDir.remove(id);
		}

		// Propagar a pressed/held/released (idéntico al patrón de _mobileHeld)
		for (dir in 0...4)
		{
			final isPressed = nowHeld[dir];

			if (isPressed && !_strumTapHeld[dir])
			{
				final tsNs         = getCurrentTimestamp();
				_strumTapHeld[dir] = true;
				pressed[dir]       = true;
				held[dir]          = true;
				_pressTimeNs[dir]  = tsNs;
				pressSongPos[dir]  = Conductor.songPosition;
				onInputPressed.dispatch({dir: dir, timestamp: tsNs, keyCode: 0});
			}
			else if (isPressed)
			{
				held[dir] = true;
			}

			if (!isPressed && _strumTapHeld[dir])
			{
				final tsNs           = getCurrentTimestamp();
				_strumTapHeld[dir]   = false;
				released[dir]        = true;
				_releaseTimeNs[dir]  = tsNs;
				onInputReleased.dispatch({dir: dir, timestamp: tsNs, keyCode: 0});
				if (onKeyRelease != null) onKeyRelease(dir);
			}
		}
	}

	/** Devuelve la dirección (0-3) cuyo strum está dentro del radio de screenX, o -1. */
	private function _getStrumDirFromX(screenX:Float):Int
	{
		for (dir in 0...4)
			if (Math.abs(screenX - strumTapPositions[dir]) <= strumTapRadius)
				return dir;
		return -1;
	}
	#end

	// ── PROCESS INPUTS ────────────────────────────────────────────────────────

	public function processInputs(notes:FlxTypedGroup<Note>):Void
	{
		if (funkin.gameplay.PlayState.isBotPlay)
		{
			pressed[0]  = pressed[1]  = pressed[2]  = pressed[3]  = false;
			held[0]     = held[1]     = held[2]     = held[3]     = false;
			released[0] = released[1] = released[2] = released[3] = false;

			final members = notes.members;
			final len = members.length;
			for (i in 0...len)
			{
				final note = members[i];
				if (note == null || !note.alive) continue;
				if (note.canBeHit && note.mustPress && !note.tooLate
					&& !note.wasGoodHit && !note.isSustainNote)
				{
					if (onNoteHit != null) onNoteHit(note);
					pressed[note.noteData] = true;
					if (onKeyPress != null) onKeyPress(note.noteData);
				}
			}
			return;
		}

		final nowNs:Int64 = getCurrentTimestamp();

		// Anti-mash: contar teclas pulsadas este frame
		var keysPressed:Int = 0;
		if (pressed[0]) keysPressed++;
		if (pressed[1]) keysPressed++;
		if (pressed[2]) keysPressed++;
		if (pressed[3]) keysPressed++;
		mashCounter = keysPressed;

		// Registrar nuevas pulsaciones en el buffer con timestamp ns
		for (dir in 0...4)
		{
			if (pressed[dir])
			{
				bufferedInputs[dir]    = _pressTimeNs[dir];
				inputProcessed[dir]    = false;
				_pendingGhostMiss[dir] = false;
				pressSongPos[dir]      = Conductor.songPosition;
			}
		}

		// Clasificar notas por dirección (buckets preallocados)
		_notesByDir0.resize(0);
		_notesByDir1.resize(0);
		_notesByDir2.resize(0);
		_notesByDir3.resize(0);

		final members = notes.members;
		final len = members.length;
		for (i in 0...len)
		{
			final note = members[i];
			if (note == null || !note.alive) continue;
			if (note.canBeHit && note.mustPress && !note.tooLate
				&& !note.wasGoodHit && !note.isSustainNote)
			{
				switch (note.noteData)
				{
					case 0: _notesByDir0.push(note);
					case 1: _notesByDir1.push(note);
					case 2: _notesByDir2.push(note);
					case 3: _notesByDir3.push(note);
				}
			}
		}

		if (_notesByDir0.length > 1) _notesByDir0.sort(_compareByStrumTime);
		if (_notesByDir1.length > 1) _notesByDir1.sort(_compareByStrumTime);
		if (_notesByDir2.length > 1) _notesByDir2.sort(_compareByStrumTime);
		if (_notesByDir3.length > 1) _notesByDir3.sort(_compareByStrumTime);

		// Pre-calcular ventana del buffer en ns una sola vez por frame
		final bufferNs:Int64 = haxe.Int64.fromFloat(bufferTime * 1_000_000_000.0);

		_processDir(0, _notesByDir0, nowNs, bufferNs);
		_processDir(1, _notesByDir1, nowNs, bufferNs);
		_processDir(2, _notesByDir2, nowNs, bufferNs);
		_processDir(3, _notesByDir3, nowNs, bufferNs);

		// Misses diferidos de ghost-tap OFF
		if (!ghostTapping)
		{
			for (dir in 0...4)
			{
				if (!_pendingGhostMiss[dir]) continue;
				if (inputProcessed[dir])
				{
					_pendingGhostMiss[dir] = false;
				}
				else if ((nowNs - bufferedInputs[dir]) > bufferNs)
				{
					_pendingGhostMiss[dir] = false;
					inputProcessed[dir]    = true;
					if (onNoteMiss != null) onNoteMiss(null);
				}
			}
		}
	}

	private static function _compareByStrumTime(a:Note, b:Note):Int
		return Std.int(a.strumTime - b.strumTime);

	/**
	 * Procesa una dirección: input directo o buffered → onNoteHit, o miss diferido.
	 * @param bufferNs Ventana del buffer en ns (pre-calculada una vez por frame).
	 */
	private inline function _processDir(
		dir:Int,
		possibleNotes:Array<Note>,
		nowNs:Int64,
		bufferNs:Int64
	):Void
	{
		var hasValidInput = pressed[dir];

		if (!hasValidInput && inputBuffering && !inputProcessed[dir])
			hasValidInput = (nowNs - bufferedInputs[dir]) <= bufferNs;

		if (!hasValidInput) return;

		if (possibleNotes.length > 0)
		{
			final canHit = !ghostTapping
				|| (mashCounter <= possibleNotes.length + 1)
				|| (mashViolations > MAX_MASH_VIOLATIONS);

			if (canHit)
			{
				if (onNoteHit != null)
				{
					onNoteHit(possibleNotes[0]);
					inputProcessed[dir]    = true;
					_pendingGhostMiss[dir] = false;
				}
			}
			else
			{
				mashViolations++;
			}
		}
		else if (!ghostTapping && pressed[dir])
		{
			_pendingGhostMiss[dir] = true;
		}
	}

	// ── PROCESS SUSTAINS ──────────────────────────────────────────────────────

	public function processSustains(notes:FlxTypedGroup<Note>):Void
	{
		final members = notes.members;
		final len = members.length;

		if (funkin.gameplay.PlayState.isBotPlay)
		{
			for (i in 0...len)
			{
				final note = members[i];
				if (note == null || !note.alive) continue;
				if (note.mustPress && note.isSustainNote && !note.wasGoodHit
					&& note.canBeHit && !note.tooLate)
				{
					held[note.noteData] = true;
					if (onNoteHit != null) onNoteHit(note);
				}
			}
			return;
		}

		for (i in 0...len)
		{
			final note = members[i];
			if (note == null || !note.alive) continue;
			if (note.canBeHit && note.mustPress && note.isSustainNote
				&& !note.wasGoodHit && held[note.noteData])
			{
				if (onNoteHit != null) onNoteHit(note);
			}
		}
	}

	// ── UTILIDADES ────────────────────────────────────────────────────────────

	public function checkMisses(notes:FlxTypedGroup<Note>):Void {}

	public function resetMash():Void
	{
		mashViolations = 0;
		mashCounter    = 0;
	}

	public function clearBuffer():Void
	{
		for (i in 0...4)
		{
			bufferedInputs[i]    = 0;
			inputProcessed[i]    = false;
			_pendingGhostMiss[i] = false;
			pressSongPos[i]      = -1.0;
		}
	}

	public function anyKeyHeld():Bool
		return held[0] || held[1] || held[2] || held[3];
}
