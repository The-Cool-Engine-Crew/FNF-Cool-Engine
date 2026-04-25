package funkin.scripting;

import flixel.FlxG;
import funkin.states.MusicBeatState;
import funkin.scripting.StateScriptHandler;
import funkin.transitions.StateTransition;

/**
 * ScriptableState — estado completo definido en HScript.
 *
 * Inspirado en el sistema @:hscriptClass de V-Slice pero sin polymod.
 * En lugar de extender la clase desde script, el estado actúa como
 * proxy delegando TODOS los métodos de ciclo de vida al script.
 *
 * ─── Uso ─────────────────────────────────────────────────────────────────────
 *
 * 1. En Haxe (para navegar a un estado scripted):
 *      StateTransition.switchState(new ScriptableState('myCustomState'));
 *
 * 2. Desde un script existente:
 *      ui.switchStateInstance(new funkin.scripting.ScriptableState('myCustomState'));
 *
 * 3. Archivo del script: assets/states/mycustomstate/main.hx
 *    (o el primero que se encuentre en esa carpeta)
 *
 * ─── API disponible en el script ─────────────────────────────────────────────
 *
 *   // Ciclo de vida
 *   function onCreate()      { ... }   // al crear el state
 *   function onUpdate(dt)    { ... }   // cada frame (antes de super)
 *   function onUpdatePost(dt){ ... }   // cada frame (después de super)
 *   function onBeatHit(beat) { ... }
 *   function onStepHit(step) { ... }
 *   function onDestroy()     { ... }
 *
 *   // Control del state
 *   ui.add(spr);
 *   ui.tween(spr, {alpha:0}, 1.0);
 *   ui.switchState('FreeplayState');
 *
 *   // Puede cancelar el input
 *   function onKeyJustPressed(key)  { return true; } // true = consumido
 *   function onKeyJustReleased(key) { ... }
 *
 * ─── Ejemplo de state completamente en script ────────────────────────────────
 *
 *   // assets/states/mycoolmenu/main.hx
 *   import flixel.util.FlxColor;
 *
 *   var bg;
 *   var title;
 *
 *   function onCreate() {
 *       bg    = ui.solidSprite(0, 0, FlxG.width, FlxG.height, FlxColor.BLACK);
 *       title = ui.text('MY COOL MENU', 0, 100, 48);
 *       ui.center(title);
 *       ui.add(bg);
 *       ui.add(title);
 *       ui.tween(title, {alpha: 1}, 1.0, {ease: 'quadOut'});
 *   }
 *
 *   function onUpdate(dt) {
 *       if (FlxG.keys.justPressed.ESCAPE)
 *           ui.switchState('MainMenuState');
 *   }
 *
 *   function onBeatHit(beat) {
 *       ui.zoom(1.05, 0.1);
 *   }
 */
class ScriptableState extends MusicBeatState {
	/** Nombre del estado (busca carpeta assets/states/{name}/). */
	public var scriptName:String;

	/** Scripts cargados para este estado. */
	var _scripts:Array<HScriptInstance> = [];

	public function new(scriptName:String) {
		super();
		this.scriptName = scriptName;
	}

	override function create():Void {
		autoScriptLoad = false;
		super.create();

		StateScriptHandler.init();
		_scripts = StateScriptHandler.loadStateScripts(scriptName, this);

		StateScriptHandler.exposeElement('FlxG', FlxG);

		StateScriptHandler.callOnScripts('onCreate', []);

		#if sys
		if (mods.ModManager.developerMode)
			_initScriptWatcher();
		#end
	}

	override private function _hotReloadRestart():Void {
		StateScriptHandler.callOnScripts('onDestroy', []);
		StateScriptHandler.clearStateScripts();

		#if HSCRIPT_ALLOWED
		funkin.scripting.ScriptHandler.clearSongScripts();
		funkin.scripting.ScriptHandler.clearStageScripts();
		funkin.scripting.ScriptHandler.clearCharScripts();
		funkin.scripting.ScriptHandler.clearMenuScripts();
		#end

		StateTransition.switchState(new ScriptableState(scriptName));
	}

	override function update(elapsed:Float):Void {
		// FIX: MusicBeatState.update() ya llama callOnScripts('onUpdate') y
		// callOnScripts('onUpdatePost') internamente. Si los duplicamos aquí
		// el script se ejecuta DOS VECES por frame, lo que provoca que tweens
		// y animaciones corran doble y — en transiciones — accedan a sprites
		// ya destruidos ("Cannot queue X. This sprite was destroyed.").
		// Solo propagamos el input, que MusicBeatState no maneja.
		#if !mobile
		if (Lambda.count(StateScriptHandler.scripts) > 0)
		{
			for (key in _getPressedKeys())
				StateScriptHandler.callOnScripts('onKeyJustPressed', [key]);
		}
		#end

		super.update(elapsed);
	}

	override function beatHit():Void {
		// FIX: MusicBeatState.beatHit() ya lanza fireRaw('onBeatHit').
		// Llamar callOnScripts aquí también provocaba un doble disparo.
		super.beatHit();
	}

	override function stepHit():Void {
		// FIX: MusicBeatState.stepHit() ya lanza fireRaw('onStepHit').
		super.stepHit();
	}

	override function destroy():Void {
		var isOurScriptActive = false;
		if (_scripts != null && _scripts.length > 0) {
			for (s in _scripts) {
				if (StateScriptHandler.scripts.exists(s.name) && StateScriptHandler.scripts.get(s.name) == s) {
					isOurScriptActive = true;
					break;
				}
			}
		}

		if (isOurScriptActive) {
			StateScriptHandler.callOnScripts('onDestroy', []);
			StateScriptHandler.clearStateScripts();
		} else {
			if (_scripts != null) {
				for (s in _scripts) {
					if (s != null) {
						try { s.call('onDestroy', []); } catch(e:Dynamic) {}
						try { s.destroy(); } catch(e:Dynamic) {}
					}
				}
			}
		}

		super.destroy();
	}

	// ─── Helpers internos ─────────────────────────────────────────────────────

	/** Devuelve las teclas presionadas este frame como strings. */
	static function _getPressedKeys():Array<String> {
		final keys:Array<String> = [];
		#if !mobile
		// getIsDown() returns all currently-held FlxKeyInput objects.
		// We filter to those that were just pressed this frame.
		for (keyInput in FlxG.keys.getIsDown()) {
			if (keyInput.justPressed)
				keys.push(keyInput.ID.toString());
		}
		#end
		return keys;
	}
}

// ─────────────────────────────────────────────────────────────────────────────

/**
 * ScriptableSubState — substate completo desde HScript.
 *
 * Igual que ScriptableState pero para substates (pausas, popups, etc.).
 *
 * ─── Uso desde Haxe ──────────────────────────────────────────────────────────
 *   openSubState(new ScriptableSubState('myPopup'));
 *
 * ─── Uso desde script ────────────────────────────────────────────────────────
 *   state.openSubState(new funkin.scripting.ScriptableSubState('myPopup'));
 *
 * ─── Script en: assets/states/mypopup/main.hx ───────────────────────────────
 *   function onCreate() {
 *       var bg = ui.solidSprite(0, 0, FlxG.width, FlxG.height, 0xAA000000);
 *       ui.add(bg);
 *   }
 *   function onUpdate(dt) {
 *       if (FlxG.keys.justPressed.ESCAPE)
 *           close(); // cierra el substate
 *   }
 */
class ScriptableSubState extends flixel.FlxSubState {
	public var scriptName:String;

	public function new(scriptName:String) {
		super();
		this.scriptName = scriptName;
	}

	override function create():Void {
		super.create();

		StateScriptHandler.init();
		StateScriptHandler.loadStateScripts(scriptName, null);

		// Exponer `close` al script
		StateScriptHandler.setOnScripts('close', () -> close());
		StateScriptHandler.setOnScripts('FlxG', FlxG);

		StateScriptHandler.callOnScripts('onCreate', []);
	}

	override function update(elapsed:Float):Void {
		StateScriptHandler.callOnScripts('onUpdate', [elapsed]);
		super.update(elapsed);
		StateScriptHandler.callOnScripts('onUpdatePost', [elapsed]);
	}

	override function destroy():Void {
		StateScriptHandler.callOnScripts('onDestroy', []);
		StateScriptHandler.clearStateScripts();
		super.destroy();
	}
}
