package funkin.states;

import funkin.data.Conductor.BPMChangeEvent;
import funkin.transitions.StateTransition;
import flixel.FlxG;
import flixel.FlxSubState;
import flixel.FlxCamera;
#if mobileC
import ui.FlxVirtualPad;
import flixel.input.actions.FlxActionInput;
import funkin.util.plugins.mobile.TouchMenuPlugin;
#end
import funkin.data.Conductor;
import data.PlayerSettings;
import funkin.gameplay.controls.Controls;
import funkin.scripting.StateScriptHandler;

class MusicBeatSubstate extends FlxSubState {
	public function new() {
		super();
	}

	private var lastBeat:Float = 0;
	private var lastStep:Float = 0;

	private var curStep:Int = 0;
	private var curBeat:Int = 0;
	private var controls(get, never):Controls;

	// Cache para búsqueda incremental en bpmChangeMap (misma optimización que MusicBeatState)
	private var _bpmIdx:Int = 0;

	/** Si true, carga automáticamente scripts desde assets/states/{ClassName}/
	 *  y rutas de mods al crear el substate. */
	public var autoScriptLoad:Bool = true;

	inline function get_controls():Controls
		return PlayerSettings.player1.controls;

	#if mobileC
	var _virtualpad:FlxVirtualPad;

	var trackedinputs:Array<FlxActionInput> = [];

	/** Plugin de gestos táctiles. Se crea con addTouchMenuControls(). */
	var _touchPlugin:TouchMenuPlugin = null;

	public function addVirtualPad(?DPad:FlxDPadMode, ?Action:FlxActionMode) {
		_virtualpad = new FlxVirtualPad(DPad, Action);
		_virtualpad.alpha = 0.75;
		add(_virtualpad);
		controls.setVirtualPad(_virtualpad, DPad, Action);
		trackedinputs = controls.trackedinputs;
		controls.trackedinputs = [];

		var padscam = new FlxCamera();
		FlxG.cameras.add(padscam);
		padscam.bgColor.alpha = 0;
		_virtualpad.cameras = [padscam];

		#if android
		controls.addAndroidBack();
		#end
	}

	/**
	 * Registra un TouchMenuPlugin que convierte gestos táctiles en inputs
	 * de Controls (UP/DOWN/LEFT/RIGHT/ACCEPT/BACK).
	 * @param includeBack      Si false, no se genera BACK con gestos.
	 * @param includeLeftRight Si false, los swipes horizontales se ignoran.
	 */
	public function addTouchMenuControls(includeBack:Bool = true, includeLeftRight:Bool = true):Void {
		if (_touchPlugin != null)
			return;
		_touchPlugin = new TouchMenuPlugin(includeBack, includeLeftRight);
		_touchPlugin.bindToControls(controls);
		add(_touchPlugin);
	}

	override function destroy() {
		controls.removeFlxInput(trackedinputs);
		if (_touchPlugin != null) {
			_touchPlugin.destroy();
			_touchPlugin = null;
		}
		_onSubDestroy();
		super.destroy();
	}

	#else
	public function addVirtualPad(?DPad, ?Action) {};

	/** No-op en plataformas no-mobile. */
	public function addTouchMenuControls(includeBack:Bool = true, includeLeftRight:Bool = true):Void {}

	override function destroy():Void {
		_onSubDestroy();
		super.destroy();
	}
	#end

	override function create() {
		_bpmIdx = 0;
		super.create();

		StateTransition.onStateCreated();

		if (autoScriptLoad)
			_autoLoadSubScripts();
	}

	override function update(elapsed:Float) {
		var oldStep:Int = curStep;

		updateCurStep();
		curBeat = Math.floor(curStep / 4);

		if (oldStep != curStep && curStep > 0)
			stepHit();

		#if HSCRIPT_ALLOWED
		if (Lambda.count(StateScriptHandler.scripts) > 0) {
			StateScriptHandler.callOnScripts('onUpdate', [elapsed]);
			super.update(elapsed);
			StateScriptHandler.callOnScripts('onUpdatePost', [elapsed]);
			return;
		}
		#end

		super.update(elapsed);
	}

	// ─── Auto-scripting ───────────────────────────────────────────────────────

	/**
	 * Carga scripts para este substate desde todas las rutas posibles.
	 * Igual que MusicBeatState pero para substates (PauseSubState, GameOverSubstate…).
	 *
	 * NOTA: StateScriptHandler es estático. Si el state padre también tiene
	 * scripts activos, abrirlos aquí los reemplazará. Esto es intencional —
	 * los substates tienen su propio contexto de scripting mientras están abiertos.
	 */
	function _autoLoadSubScripts():Void {
		#if HSCRIPT_ALLOWED
		if (Lambda.count(StateScriptHandler.scripts) > 0)
			return;

		final className = Type.getClassName(Type.getClass(this)).split('.').pop();

		StateScriptHandler.init();
		StateScriptHandler.loadStateScripts(className, this);

		if (Lambda.count(StateScriptHandler.scripts) > 0) {
			StateScriptHandler.refreshStateFields(this);
			StateScriptHandler.callOnScripts('onCreate', []);
			StateScriptHandler.callOnScripts('postCreate', []);
			trace('[MusicBeatSubstate] Scripts cargados para $className.');
		}
		#end
	}

	function _onSubDestroy():Void {
		#if HSCRIPT_ALLOWED
		if (Std.isOfType(FlxG.state, funkin.scripting.ScriptableState))
			return;
		StateScriptHandler.callOnScripts('onDestroy', []);
		StateScriptHandler.clearStateScripts();
		#end
	}

	// ─── BPM / Beat ───────────────────────────────────────────────────────────

	/**
	 * Búsqueda incremental O(1) amortizado — igual que MusicBeatState.
	 */
	private function updateCurStep():Void {
		final map = Conductor.bpmChangeMap;
		final pos = Conductor.songPosition;
		final len = map.length;

		if (len == 0) {
			curStep = Math.floor(pos / Conductor.stepCrochet);
			return;
		}

		if (_bpmIdx > 0 && pos < map[_bpmIdx].songTime)
			_bpmIdx = 0;

		while (_bpmIdx + 1 < len && pos >= map[_bpmIdx + 1].songTime)
			_bpmIdx++;

		final ev = map[_bpmIdx];
		curStep = ev.stepTime + Math.floor((pos - ev.songTime) / Conductor.stepCrochet);
	}

	public function stepHit():Void {
		#if HSCRIPT_ALLOWED
		if (Lambda.count(StateScriptHandler.scripts) > 0)
			StateScriptHandler.fireRaw('onStepHit', [curStep]);
		#end

		if (curStep % 4 == 0)
			beatHit();
	}

	public function beatHit():Void {
		#if HSCRIPT_ALLOWED
		if (Lambda.count(StateScriptHandler.scripts) > 0)
			StateScriptHandler.fireRaw('onBeatHit', [curBeat]);
		#end
		// override en subclases
	}
}
