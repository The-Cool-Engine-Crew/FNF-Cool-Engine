package funkin.gameplay;

import flixel.FlxG;
import flixel.FlxCamera;
import flixel.FlxObject;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.FlxCamera.FlxCameraFollowStyle;
import funkin.gameplay.objects.character.Character;

using StringTools;

/**
 * CameraController — Control de cámara basado en eventos.
 * 
 * La cámara sigue al personaje definido por `currentTarget`,
 * que se cambia EXCLUSIVAMENTE a través del evento "Camera Follow"
 * del EventManager. No hay ninguna lógica de mustHitSection aquí.
 */
class CameraController {
	// === CAMERAS ===
	public var camGame:FlxCamera;
	public var camHUD:FlxCamera;

	// === FOLLOW OBJECT ===
	// Expuesto para que EventManager pueda leerlo si hace falta.
	public var camFollow:FlxObject;

	private var camPos:FlxPoint;

	// === CHARACTERS ===
	// Se guardan las referencias para poder resolver el target por nombre.
	private var boyfriend:Character;
	private var dad:Character;
	private var gf:Character;

	// === TARGET ACTUAL ===
	// "player" | "opponent" | "gf"
	// Cambiar con setTarget() desde EventManager.
	public var currentTarget:String = 'opponent';

	// === INITIAL STATE (for restart/rewind) ===
	// Saved at construction time so resetToInitial() can fully restore the camera.
	private var _initialTarget:String = 'opponent';
	private var _initialZoom:Float = 1.05;
	private var _initialLerp:Float = 0.04;

	// === LERP SPEED del follow ===
	// Puede sobreescribirse por evento (Camera Follow, value2).
	public var followLerp:Float = 0.04;

	// === ZOOM ===
	public var defaultZoom:Float = 1.05;
	public var zoomEnabled:Bool = false;

	private var zoomTween:FlxTween;

	// Pan manual — sin tween manager, inmune a pausas/limpiezas externas.
	private var _panActive:Bool = false;
	private var _panFromX:Float = 0.0;
	private var _panFromY:Float = 0.0;
	private var _panToX:Float = 0.0;
	private var _panToY:Float = 0.0;
	private var _panDuration:Float = 0.6;
	private var _panElapsed:Float = 0.0;
	private var _panEase:Float->Float;
	private var _panOnComplete:Void->Void;
	private var _panKeepLocked:Bool = false;

	// Freeze — congela la transición de cámara durante el pause.
	// freeze() desconecta el follow de Flixel; unfreeze() lo reconecta.
	private var _frozen:Bool = false;

	// Snapshot completo del estado de cámara al momento del freeze,
	// para que unfreeze() restaure EXACTAMENTE lo que había antes del pause
	// sin importar qué modifiquen los callbacks (onPause, onResume, scripts, etc.).
	private var _frozenFollowLerp:Float   = 0.04;
	private var _frozenSavedLerp:Float    = 0.04;
	private var _frozenLocked:Bool        = false;
	private var _frozenLockedX:Float      = 0.0;
	private var _frozenLockedY:Float      = 0.0;
	private var _frozenPanActive:Bool     = false;
	private var _frozenExplicitLock:Bool  = false;

	// === NOTE MOVEMENT OFFSETS ===
	public var dadOffsetX:Int = 0;
	public var dadOffsetY:Int = 0;
	public var bfOffsetX:Int = 0;
	public var bfOffsetY:Int = 0;

	// === STAGE CAMERA OFFSETS ===
	// Definidos en el stage JSON como cameraBoyfriend / cameraDad / cameraGirlfriend.
	// Defaults reproducen el comportamiento clásico del engine:
	//   player   → -100 X, -100 Y  (cámara ligeramente a la izquierda/arriba de BF)
	//   opponent → +150 X, -100 Y  (cámara más a la derecha para el oponente)
	//   gf       →    0 X,  -80 Y
	// Los stages que definen cameraBoyfriend/cameraDad en su JSON sobreescriben estos valores.
	public var stageOffsetBf:FlxPoint = new FlxPoint(-100, -100);
	public var stageOffsetDad:FlxPoint = new FlxPoint(150, -100);

	/** Offset de cámara para GF (camera_girlfriend en Psych). */
	public var stageOffsetGf:FlxPoint = new FlxPoint(0, -80);

	/** Offset adicional pasado por el evento (campo x/y de FocusCamera en V-Slice). */
	var _extraOffsetX:Float = 0.0;

	var _extraOffsetY:Float = 0.0;

	// === CONFIG ===

	/**
	 * Cuando `true`, el follow de la cámara está bloqueado: `updateFollowPosition`
	 * es un no-op y camFollow se queda donde está (o en _lockedPos si se usó lock()).
	 * Cambiar con lock() / unlock().
	 */
	public var locked:Bool = false;

	/** Posición de mundo a la que se bloqueó la cámara (solo válida cuando locked=true). */
	private var _lockedPos:FlxPoint = new FlxPoint(0, 0);

	/**
	 * Velocidad del lerp de cámara. Equivalente a camera_speed en Psych.
	 * Se inicializa a 2.4 (default de Cool Engine). PlayState lo sobreescribe
	 * con currentStage.cameraSpeed * BASE_LERP_SPEED tras cargar el stage.
	 */
	public var lerpSpeed:Float = 2.4;

	public static inline var BASE_LERP_SPEED:Float = 2.4;
	private static inline var NOTE_OFFSET_AMOUNT:Float = 30.0;

	private var _savedLerp:Float = 0.04;

	// When lock() is called while a panTo is active, we don't kill the pan.
	// Instead we store the lock request and apply it the moment the pan ends.
	private var _pendingLock:Bool = false;
	private var _pendingLockX:Float = Math.NaN;
	private var _pendingLockY:Float = Math.NaN;

	private var _explicitLock:Bool = false;

	// ─────────────────────────────────────────────────────────────

	public function new(camGame:FlxCamera, camHUD:FlxCamera, boyfriend:Character, dad:Character, ?gf:Character) {
		this.camGame = camGame;
		this.camHUD = camHUD;
		this.boyfriend = boyfriend;
		this.dad = dad;
		this.gf = gf;

		camFollow = new FlxObject(0, 0, 1, 1);
		camPos = new FlxPoint();

		// Escalar defaultZoom según resolución (fix 1080p: 1280/1920 = 1.5×)
		defaultZoom *= Main.resolutionScale();

		// Iniciar la cámara siguiendo el objeto de follow con lerp suave.
		camGame.follow(camFollow, FlxCameraFollowStyle.LOCKON, followLerp);
		camGame.zoom = defaultZoom;

		// Save initial state so resetToInitial() can fully restore it on rewind/restart.
		_initialTarget = currentTarget;
		_initialZoom = defaultZoom;
		_initialLerp = followLerp;

		// Posición inicial: sobre el oponente (target por defecto).
		_snapToTarget();
	}

	// ─────────────────────────────────────────────────────────────
	//  API PÚBLICA
	// ─────────────────────────────────────────────────────────────

	/**
	 * Cambiar el personaje al que sigue la cámara.
	 * Llamar desde EventManager al procesar el evento "Camera Follow".
	 *
	 * @param target    "player" | "opponent" | "gf" | "position"
	 *                  (también acepta aliases bf/dad/boyfriend/girlfriend)
	 * @param extraOffX Offset X adicional del evento (campo "x" en FocusCamera V-Slice).
	 * @param extraOffY Offset Y adicional del evento (campo "y" en FocusCamera V-Slice).
	 * @param snap      Si true, mueve camFollow instantáneamente (sin lerp de follow point).
	 *                  Para CLASSIC de V-Slice usar snap=true: el follow point salta
	 *                  al nuevo target y solo camGame.follow() hace el lerp suave.
	 */
	public function setTarget(target:String, extraOffX:Float = 0.0, extraOffY:Float = 0.0, snap:Bool = true):Void {
		currentTarget = resolveTarget(target);
		_extraOffsetX = extraOffX;
		_extraOffsetY = extraOffY;
		trace('[CameraController] Target → $currentTarget (extraOff=${extraOffX},${extraOffY} snap=$snap locked=$locked)');

		// Siempre snapear camFollow al nuevo target — la transición suave la
		// hace camGame.follow(camFollow, LOCKON, followLerp), igual que V-Slice.
		// El lerpSpeed de updateFollowPosition añadiría un segundo lerp encadenado
		// que ralentiza y suaviza en exceso la transición.
		// NOTA: _snapToTarget() respeta `locked` internamente — si está bloqueada
		// no moverá camFollow aunque se cambie el target.
		_snapToTarget();
	}

	/**
	 * Actualizar lerp speed del follow.
	 * Llamar desde EventManager si se especifica value2 en el evento.
	 */
	public function setFollowLerp(lerp:Float):Void {
		followLerp = lerp;
		camGame.followLerp = lerp;
	}

	/**
	 * Cancela cualquier pan tween activo, desbloquea el follow y snapeaa
	 * camFollow al target actual.
	 * Llamar desde EventManager antes de setTarget() en eventos tipo snap
	 * (sin duration) para que un FocusCamera CLASSIC/snap no quede bloqueado
	 * por un pan largo que aún esté en curso.
	 */
	public function cancelPan():Void {
		// Si hay un pan activo, NO lo cancelamos: dejamos que termine en su destino.
		// El target ya se actualiza vía setTarget(), que respeta locked=true.
		// cancelPan() solo limpia estado residual cuando NO hay pan en curso.
		if (_panActive)
			return;

		_pendingLock = false;
		_pendingLockX = Math.NaN;
		_pendingLockY = Math.NaN;

		if (!_explicitLock)
			locked = false;
	}

	/**
	 * Cancela el pan incondicionalmente aunque esté en curso.
	 * Usar solo cuando realmente se necesite interrumpir (restart, rewind).
	 */
	public function forceCancel():Void {
		_panActive = false;
		_panOnComplete = null;
		_pendingLock = false;
		_pendingLockX = Math.NaN;
		_pendingLockY = Math.NaN;
		_explicitLock = false;
		locked = false;
	}

	// ─────────────────────────────────────────────────────────────
	//  LOCK / UNLOCK
	// ─────────────────────────────────────────────────────────────

	/**
	 * Locks the camera at its current position (or at x/y if supplied).
	 *
	 * If a panTo() is currently running, the lock is DEFERRED — the pan plays
	 * to completion first, then the lock is applied automatically. This guarantees
	 * that panTo always has higher priority than lock, so cinematic pans are never
	 * cut short by a simultaneous lock event.
	 *
	 * To cancel a pan AND lock immediately, call cancelPan() first, then lock().
	 *
	 * @param x  World X to lock on. If null, uses the camera's current center X.
	 * @param y  World Y to lock on. If null, uses the camera's current center Y.
	 */
	public function lock(?x:Float, ?y:Float):Void {
		// ── Pan is active → queue the lock, don't kill the pan ───────────────
		if (_panActive) {
			_pendingLock = true;
			_pendingLockX = x ?? Math.NaN;
			_pendingLockY = y ?? Math.NaN;
			return;
		}

		// ── No active pan → apply immediately ────────────────────────────────
		_applyLock(x, y);
	}

	/** Internal: applies the lock unconditionally. Called by lock() and by panTo's onComplete. */
	private function _applyLock(?x:Float, ?y:Float):Void {
		_pendingLock = false;
		_pendingLockX = Math.NaN;
		_pendingLockY = Math.NaN;

		locked = true;
		_explicitLock = true; // lock() llamado directamente → inmune a cancelPan()

		final actualX:Float = (camGame != null) ? camGame.scroll.x + camGame.width * 0.5 : camFollow.x;
		final actualY:Float = (camGame != null) ? camGame.scroll.y + camGame.height * 0.5 : camFollow.y;

		_lockedPos.x = x ?? actualX;
		_lockedPos.y = y ?? actualY;

		camFollow.setPosition(_lockedPos.x, _lockedPos.y);

		if (camGame != null) {
			_savedLerp = camGame.followLerp;
			camGame.scroll.set(_lockedPos.x - camGame.width * 0.5, _lockedPos.y - camGame.height * 0.5);
			camGame.target = null;
		}
	}

	/**
	 * Desbloquea el follow. La cámara vuelve a lerpar hacia el personaje
	 * definido por currentTarget desde la siguiente llamada a update().
	 */
	public function unlock():Void {
		locked = false;
		_explicitLock = false;

		if (camGame != null) {
			camGame.follow(camFollow, FlxCameraFollowStyle.LOCKON, _savedLerp);
		}
	}

	/**
	 * Mueve camFollow instantáneamente a una posición de mundo (sin tween).
	 * No deshabilita el follow — si quieres que se quede ahí usa lock() después.
	 *
	 * @param x  Posición X de mundo.
	 * @param y  Posición Y de mundo.
	 */
	public function moveTo(x:Float, y:Float):Void {
		camFollow.setPosition(x, y);
	}

	/**
	 * Smoothly pans the camera to a world position over `duration` seconds.
	 *
	 * @param x           World X destination (camera center).
	 * @param y           World Y destination (camera center).
	 * @param duration    Tween duration in seconds (default 0.6).
	 * @param ease        Ease function (default FlxEase.sineInOut).
	 * @param keepLocked  If true the camera stays locked after the tween (default false).
	 * @param onComplete  Optional callback fired when the tween finishes.
	 */
	public function panTo(x:Float, y:Float, ?duration:Float, ?ease:Float->Float, ?keepLocked:Bool, ?onComplete:Void->Void):Void {
		var dur:Float = (duration != null && duration > 0) ? duration : 0.6;

		// Cancelar pan anterior si había uno en curso.
		_panActive = false;
		_panOnComplete = null;

		locked = true;
		_explicitLock = false;
		_savedLerp = followLerp;

		camGame.target = null;
		camGame.followLerp = 0;

		camFollow.setPosition(x, y);

		_panFromX = camGame.scroll.x;
		_panFromY = camGame.scroll.y;
		_panToX   = x - camGame.width  * 0.5;
		_panToY   = y - camGame.height * 0.5;

		_panDuration   = dur;
		_panElapsed    = 0.0;
		_panEase       = ease ?? FlxEase.sineInOut;
		_panOnComplete = onComplete;
		_panKeepLocked = keepLocked ?? false;

		_panActive = true;
	}

	/** Llamado cada frame desde update() mientras _panActive == true. */
	private function _tickPan(elapsed:Float):Void {
		// Re-afirmar cada frame por si PlayState u otro sistema reactiva el follow.
		camGame.target = null;
		camGame.followLerp = 0;

		_panElapsed += elapsed;
		var t:Float = Math.min(_panElapsed / _panDuration, 1.0);
		var et:Float = _panEase(t);

		camGame.scroll.x = _panFromX + (_panToX - _panFromX) * et;
		camGame.scroll.y = _panFromY + (_panToY - _panFromY) * et;

		if (t >= 1.0) {
			_panActive = false;

			if (_pendingLock) {
				var px = Math.isNaN(_pendingLockX) ? null : _pendingLockX;
				var py = Math.isNaN(_pendingLockY) ? null : _pendingLockY;
				_applyLock(px, py);
			} else if (!_panKeepLocked) {
				locked = false;
				// camFollow ya está en el destino → reconectar sin salto.
				camGame.followLerp = _savedLerp;
				camGame.follow(camFollow, FlxCameraFollowStyle.LOCKON, _savedLerp);
			}

			var cb = _panOnComplete;
			_panOnComplete = null;
			if (cb != null)
				cb();
		}
	}

	/**
	 * Tweenea camFollow al target actual (calculado en este momento) con
	 * la duración y ease dados. Equivalente a panTo pero calcula el destino
	 * desde el personaje activo en lugar de una posición fija.
	 * Usado por FocusCamera V-Slice con ease/duration.
	 */
	public function tweenToTarget(duration:Float, ?ease:Float->Float):Void {
		final dest = _computeTargetPos();
		if (dest == null)
			return;
		panTo(dest.x, dest.y, duration, ease ?? FlxEase.sineOut);
		dest.put();
	}

	/**
	 * Centra la cámara en el punto medio entre bf y dad.
	 * Equivalente a setTarget('both') pero instantáneo o con snap.
	 *
	 * @param snap  Si true (default) mueve camFollow instantáneamente.
	 *              Si false aplica un panTo suave de 0.6s.
	 */
	public function centerBetweenChars(?snap:Bool):Void {
		if (boyfriend == null || dad == null)
			return;
		var bfMid = boyfriend.getMidpoint();
		var dadMid = dad.getMidpoint();
		var cx = (bfMid.x + dadMid.x) * 0.5;
		var cy = (bfMid.y + dadMid.y) * 0.5;
		bfMid.put();
		dadMid.put();

		if (snap ?? true)
			moveTo(cx, cy);
		else
			panTo(cx, cy);
	}

	/**
	 * Restaura el estado inicial de la cámara (target, zoom, lerp).
	 * Llamar desde PlayState._finishRestart() y GameplayEditorState._onRestart()
	 * DESPUÉS de que EventManager.rewindToStart() haya marcado los eventos como
	 * no disparados, para que la cámara quede donde estaba al inicio de la canción.
	 */
	public function resetToInitial():Void {
		// Cancel any active zoom tween first
		if (zoomTween != null) {
			zoomTween.cancel();
			zoomTween = null;
		}
		_panActive = false;
		_panOnComplete = null;

		locked = false;
		_explicitLock = false;
		_pendingLock = false;
		_pendingLockX = Math.NaN;
		_pendingLockY = Math.NaN;

		currentTarget = _initialTarget;
		defaultZoom = _initialZoom;
		followLerp = _initialLerp;
		zoomEnabled = false;
		dadOffsetX = 0;
		dadOffsetY = 0;
		bfOffsetX = 0;
		bfOffsetY = 0;

		camGame.zoom = defaultZoom;
		camGame.followLerp = followLerp;

		_snapToTarget();
		trace('[CameraController] resetToInitial → target=$currentTarget zoom=$defaultZoom');
	}

	/**
	 * Toma una foto del estado actual como "estado inicial".
	 * PlayState llama esto DESPUÉS de aplicar todos los overrides del stage
	 * (defaultCamZoom, stageOffsets, lerpSpeed) para que resetToInitial()
	 * vuelva al punto correcto tras un rewind.
	 */
	public function snapshotInitialState():Void {
		_initialTarget = currentTarget;
		_initialZoom = defaultZoom;
		_initialLerp = followLerp;
		trace('[CameraController] snapshotInitialState → target=$_initialTarget zoom=$_initialZoom lerp=$_initialLerp');
	}

	// ─────────────────────────────────────────────────────────────
	//  UPDATE
	// ─────────────────────────────────────────────────────────────

	/**
	 * Llamar desde PlayState.update() cada frame.
	 * Ya NO recibe mustHitSection — el target se controla por eventos.
	 */
	public function update(elapsed:Float):Void {
		if (_frozen) return; // Congelado durante pause — no mover nada
		if (_panActive)
			_tickPan(elapsed);
		updateFollowPosition(elapsed);
		lerpZoom(elapsed);
	}

	/**
	 * Congela la cámara durante el pause.
	 * Desconecta el follow de Flixel para que el lerp nativo no siga
	 * deslizando la cámara mientras el juego está pausado.
	 * Toma un snapshot COMPLETO del estado actual para que unfreeze()
	 * restaure exactamente la misma situación, sin importar qué modifiquen
	 * los callbacks de scripts (onPause, onResume, Lua, HScript, etc.)
	 * entre freeze() y unfreeze().
	 */
	public function freeze():Void {
		if (_frozen) return;
		_frozen = true;

		// ── Snapshot completo del estado en el momento del pause ─────────
		_frozenPanActive    = _panActive;
		_frozenLocked       = locked;
		_frozenLockedX      = _lockedPos.x;
		_frozenLockedY      = _lockedPos.y;
		_frozenSavedLerp    = _savedLerp;
		_frozenExplicitLock = _explicitLock;

		if (camGame != null) {
			_frozenFollowLerp = camGame.followLerp; // guardar ANTES de desconectar
			camGame.target = null; // desconecta el follow nativo de Flixel
		}
	}

	/**
	 * Descongela la cámara al reanudar el juego.
	 * Restaura desde el snapshot tomado en freeze() para garantizar que
	 * el estado sea EXACTAMENTE el que había antes del pause, ignorando
	 * cualquier modificación hecha por scripts/callbacks durante la pausa.
	 *
	 *   - Pan activo al freezear  → re-afirma target=null + followLerp=0 (pan sigue en update).
	 *   - Locked al freezear      → restaura locked, _lockedPos, _savedLerp y fuerza
	 *                               camGame.target=null para que el lock no se pierda.
	 *   - Follow normal           → reconecta camGame con el lerp exacto del snapshot.
	 */
	public function unfreeze():Void {
		if (!_frozen) return;
		_frozen = false;
		if (camGame == null) return;

		if (_frozenPanActive) {
			// Pan estaba en curso al freezearse → mantener desconectado; _tickPan lo gestiona.
			camGame.target = null;
			camGame.followLerp = 0;
		} else if (_frozenLocked) {
			// Estaba bloqueada al freezearse → restaurar el lock COMPLETO desde el snapshot.
			// Esto revierte cualquier unlock() / forceCancel() que hayan llamado
			// scripts o callbacks durante la pausa.
			locked        = true;
			_explicitLock = _frozenExplicitLock;
			_savedLerp    = _frozenSavedLerp;
			_lockedPos.set(_frozenLockedX, _frozenLockedY);
			camFollow.setPosition(_frozenLockedX, _frozenLockedY);
			camGame.target = null;
			camGame.scroll.set(_frozenLockedX - camGame.width * 0.5, _frozenLockedY - camGame.height * 0.5);
		} else {
			// Follow normal → reconectar con el lerp exacto del snapshot.
			// También asegurarse de que locked no quedó true por un script durante la pausa.
			locked = false;
			camGame.follow(camFollow, FlxCameraFollowStyle.LOCKON, _frozenFollowLerp);
		}
	}

	// ─────────────────────────────────────────────────────────────
	//  INTERNOS
	// ─────────────────────────────────────────────────────────────

	private function updateFollowPosition(elapsed:Float):Void {
		// Si la cámara está bloqueada, no mover camFollow en absoluto.
		if (locked)
			return;
		// ── Target 'both': centrar entre bf y dad ─────────────────────────
		if (currentTarget == 'both') {
			if (boyfriend == null || dad == null)
				return;

			var bfMid = boyfriend.getMidpoint();
			var dadMid = dad.getMidpoint();

			var midX = (bfMid.x + dadMid.x) * 0.5;
			var midY = (bfMid.y + dadMid.y) * 0.5;

			// Offset vertical genérico para que no quede en los pies
			midY -= 100;

			camFollow.x = midX;
			camFollow.y = midY;

			bfMid.put();
			dadMid.put();
			return;
		}

		// ── Target normal ─────────────────────────────────────────────────
		var targetChar = getTargetCharacter();
		if (targetChar == null)
			return;

		var targetPos = targetChar.getMidpoint();

		// Offsets propios del personaje (definidos en su JSON).
		targetPos.x += targetChar.cameraOffset[0];
		targetPos.y += targetChar.cameraOffset[1];

		// Stage offset (cameraBoyfriend/cameraDad/cameraGirlfriend del stage.json).
		var stageOff = switch (currentTarget) {
			case 'player': stageOffsetBf;
			case 'opponent': stageOffsetDad;
			case 'gf': stageOffsetGf;
			default: stageOffsetDad;
		};
		targetPos.x += stageOff.x + _extraOffsetX;
		targetPos.y += stageOff.y + _extraOffsetY;

		// Offsets de animación de nota.
		var noteOffX = currentTarget == 'player' ? bfOffsetX : dadOffsetX;
		var noteOffY = currentTarget == 'player' ? bfOffsetY : dadOffsetY;

		// Setear camFollow directo al destino. La transición suave la hace
		// camGame.follow(camFollow, LOCKON, followLerp) — sin doble lerp encadenado.
		// El noteOffset se aplica directamente para el micro-movimiento de notas.
		camFollow.x = targetPos.x + noteOffX;
		camFollow.y = targetPos.y + noteOffY;

		targetPos.put();
	}

	/**
	 * Calcula la posición destino del follow para el target actual.
	 * Devuelve un FlxPoint pooled — el caller debe llamar .put().
	 */
	private function _computeTargetPos():Null<flixel.math.FlxPoint> {
		var targetChar = getTargetCharacter();
		if (targetChar == null)
			return null;
		var pos = targetChar.getMidpoint();
		pos.x += targetChar.cameraOffset[0];
		pos.y += targetChar.cameraOffset[1];
		var stageOff = switch (currentTarget) {
			case 'player': stageOffsetBf;
			case 'opponent': stageOffsetDad;
			case 'gf': stageOffsetGf;
			default: stageOffsetDad;
		};
		pos.x += stageOff.x + _extraOffsetX;
		pos.y += stageOff.y + _extraOffsetY;
		return pos;
	}

	private function lerpZoom(elapsed:Float):Void {
		var lerpVal:Float = FlxMath.bound(elapsed * 3.125, 0, 1);
		camGame.zoom = FlxMath.lerp(camGame.zoom, defaultZoom, lerpVal);
		camHUD.zoom = FlxMath.lerp(camHUD.zoom, 1.0, lerpVal);
	}

	/** Mueve camFollow instantáneamente al target actual (sin lerp). */
	private function _snapToTarget():Void {
		// Si la cámara está bloqueada, nunca mover camFollow desde aquí.
		if (locked)
			return;

		// ── Target 'both': snap al centro entre bf y dad ──────────────────
		if (currentTarget == 'both') {
			if (boyfriend == null || dad == null)
				return;
			var bfMid = boyfriend.getMidpoint();
			var dadMid = dad.getMidpoint();
			camFollow.setPosition((bfMid.x + dadMid.x) * 0.5, (bfMid.y + dadMid.y) * 0.5);
			bfMid.put();
			dadMid.put();
			return;
		}

		var targetChar = getTargetCharacter();
		if (targetChar == null)
			return;

		var mid = targetChar.getMidpoint();
		// BUG FIX: igual que en updateFollowPosition, GF necesita su propio stageOffset.
		var stageOff = switch (currentTarget) {
			case 'player': stageOffsetBf;
			case 'opponent': stageOffsetDad;
			case 'gf': stageOffsetGf;
			default: stageOffsetDad;
		};
		camFollow.setPosition(mid.x + targetChar.cameraOffset[0] + stageOff.x + _extraOffsetX, mid.y + targetChar.cameraOffset[1] + stageOff.y + _extraOffsetY);
		mid.put();
	}

	private function getTargetCharacter():Character {
		return switch (currentTarget) {
			case 'player': boyfriend;
			case 'opponent': dad;
			case 'gf': gf;
			default: dad;
		};
	}

	/** Normaliza aliases a los cuatro nombres canónicos. */
	private function resolveTarget(raw:String):String {
		return switch (raw.toLowerCase().trim()) {
			case 'player' | 'bf' | 'boyfriend': 'player';
			case 'opponent' | 'dad' | 'enemy': 'opponent';
			case 'gf' | 'girlfriend': 'gf';
			case 'both' | 'center' | 'middle' | 'all': 'both';
			default: raw;
		};
	}

	// ─────────────────────────────────────────────────────────────
	//  ZOOM Y EFECTOS
	// ─────────────────────────────────────────────────────────────

	public function bumpZoom():Void {
		if (!zoomEnabled)
			return;
		// El límite de bump se escala con la resolución para mantener
		// la misma "sensación" visual que en 720p.
		var bumpLimit:Float = 1.35 * Main.resolutionScale();
		if (camGame.zoom < bumpLimit) {
			camGame.zoom += 0.015 * Main.resolutionScale();
			camHUD.zoom += 0.03;
		}
	}

	public function applyNoteOffset(character:Character, noteData:Int):Void {
		var camX:Float = 0;
		var camY:Float = 0;

		switch (noteData) {
			case 0:
				camX = -NOTE_OFFSET_AMOUNT;
			case 1:
				camY = NOTE_OFFSET_AMOUNT;
			case 2:
				camY = -NOTE_OFFSET_AMOUNT;
			case 3:
				camX = NOTE_OFFSET_AMOUNT;
		}

		if (character == dad) {
			dadOffsetX = Std.int(camX);
			dadOffsetY = Std.int(camY);
		} else if (character == boyfriend) {
			bfOffsetX = Std.int(camX);
			bfOffsetY = Std.int(camY);
		}
	}

	public function resetOffsets():Void {
		dadOffsetX = 0;
		dadOffsetY = 0;
		bfOffsetX = 0;
		bfOffsetY = 0;
	}

	public function tweenZoomIn():Void {
		if (zoomTween != null)
			zoomTween.cancel();
		// FIX: misma razón que _panTween — manager global no se pausa.
		final _mgr = PlayState.gameplayTweens ?? FlxTween.globalManager;
		zoomTween = _mgr.tween(camGame, {zoom: defaultZoom}, 1, {ease: FlxEase.elasticInOut});
	}

	public function shake(intensity:Float = 0.05, duration:Float = 0.1):Void
		camGame.shake(intensity, duration);

	public function flash(duration:Float = 0.5, color:Int = 0xFFFFFFFF):Void
		camGame.flash(color, duration);

	// ─────────────────────────────────────────────────────────────

	public function destroy():Void {
		if (zoomTween != null) {
			zoomTween.cancel();
			zoomTween = null;
		}
		_panActive = false;
		_panOnComplete = null;
		camPos.put();
		stageOffsetBf.put();
		stageOffsetDad.put();
		stageOffsetGf.put();
		_lockedPos.put();
		camFollow = null;
	}
}
