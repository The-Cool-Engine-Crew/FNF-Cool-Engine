package funkin.scripting;

import flixel.FlxG;
import flixel.FlxState;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.util.FlxTimer;
import flixel.group.FlxGroup;
import flixel.group.FlxSpriteGroup;
import funkin.states.LoadingState;
import funkin.transitions.StateTransition;
import funkin.transitions.StickerTransition;
import funkin.scripting.ScriptableState;
import funkin.data.GlobalConfig;

/**
 * ScriptBridge — puente entre HScript y el motor.
 *
 * Permite a los scripts:
 *   • Crear sprites, textos, grupos de forma sencilla
 *   • Navegar entre estados
 *   • Ejecutar tweens y timers inline
 *   • Acceder al objeto `ui` (builder de elementos para un state)
 *
 * No se instancia directamente — se accede vía el objeto `ui` en scripts.
 *
 * ─── En un script de state ───────────────────────────────────────────────────
 *   var spr = ui.sprite('mySprite', 100, 200, 'assets/images/foo.png');
 *   ui.add(spr);
 *
 *   var txt = ui.text('hello', 'Hello World!', 400, 30);
 *   ui.remove(txt);
 *
 *   ui.tween(spr, {alpha: 0}, 1.0, {ease: 'quadOut'});
 *   ui.timer(2.0, function() { trace('timeout'); });
 *
 *   ui.switchState('FreeplayState');
 *   ui.switchStateInstance(new funkin.menus.FreeplayState());
 */
class ScriptBridge
{
	/**
	 * Construye el objeto `ui` inyectado en cada script de state.
	 * Contiene helpers tipados para crear y gestionar elementos del state.
	 */
	public static function buildUIHelper(state:FlxState):Dynamic
	{
		return {
			// ─── Creación de elementos ─────────────────────────────────────────

			/** Crea un FlxSprite con imagen opcional. */
			sprite: function(?name:String, x:Float = 0, y:Float = 0, ?imagePath:String):FlxSprite
			{
				final spr = new FlxSprite(x, y);
				if (imagePath != null)
					spr.loadGraphic(Paths.image(imagePath));
				return spr;
			},

			/** Crea un FlxSprite de color sólido. */
			solidSprite: function(x:Float, y:Float, w:Int, h:Int, color:Int = 0xFFFFFFFF):FlxSprite
			{
				final spr = new FlxSprite(x, y);
				spr.makeGraphic(w, h, color);
				return spr;
			},

			/** Crea un FlxText. */
			text: function(txt:String = '', x:Float = 0, y:Float = 0, size:Int = 24, ?font:String):FlxText
			{
				final t = new FlxText(x, y, 0, txt, size);
				if (font != null)
					t.setFormat(Paths.font(font), size, FlxColor.WHITE);
				return t;
			},

			/** Crea un FlxSpriteGroup. */
			group: function():FlxSpriteGroup return new FlxSpriteGroup(),

			/** Crea un FlxGroup genérico. */
			baseGroup: function():FlxGroup return new FlxGroup(),

			// ─── Añadir / eliminar del state ──────────────────────────────────

			/** Añade un objeto al state. */
			add: function(obj:Dynamic) { state.add(obj); return obj; },

			/** Elimina un objeto del state. */
			remove: function(obj:Dynamic) { state.remove(obj); return obj; },

			/** Añade y devuelve (chaineable). */
			insert: function(pos:Int, obj:Dynamic) { state.insert(pos, obj); return obj; },

			// ─── Tweens inline ─────────────────────────────────────────────────

			/**
			 * Tween simplificado.
			 *   ui.tween(spr, {alpha: 0}, 1.0, {ease: 'quadOut', delay: 0.5});
			 */
			tween: function(obj:Dynamic, props:Dynamic, duration:Float = 0.5,
				?options:Dynamic):Dynamic
			{
				final opts:flixel.tweens.FlxTween.TweenOptions = {};
				if (options != null)
				{
					if (Reflect.hasField(options, 'ease'))
					{
						final easeName:String = Reflect.field(options, 'ease');
						opts.ease = _resolveEase(easeName);
					}
					if (Reflect.hasField(options, 'delay'))
						opts.startDelay = Reflect.field(options, 'delay');
					if (Reflect.hasField(options, 'onComplete'))
						opts.onComplete = Reflect.field(options, 'onComplete');
					if (Reflect.hasField(options, 'type'))
						opts.type = Reflect.field(options, 'type');
					if (Reflect.hasField(options, 'loopDelay'))
						opts.loopDelay = Reflect.field(options, 'loopDelay');
				}
				return FlxTween.tween(obj, props, duration, opts);
			},

			/** Cancela los tweens de un objeto. */
			cancelTweens: function(obj:Dynamic) FlxTween.cancelTweensOf(obj),

			// ─── Timers ────────────────────────────────────────────────────────

			/**
			 * Timer de un disparo.
			 *   ui.timer(1.5, function() { trace('tick'); });
			 */
			timer: function(delay:Float, callback:FlxTimer->Void):FlxTimer
			{
				return new FlxTimer().start(delay, callback);
			},

			/**
			 * Timer repetitivo.
			 *   ui.interval(0.5, function(t) { trace(t.loops); }, 5);
			 */
			interval: function(delay:Float, callback:FlxTimer->Void, loops:Int = 0):FlxTimer
			{
				return new FlxTimer().start(delay, callback, loops);
			},

			// ─── Navegación ────────────────────────────────────────────────────

			/**
			 * Navega a un state por nombre de clase.
			 * Soporta: 'MainMenuState', 'FreeplayState', 'StoryMenuState',
			 *          'TitleState', 'PlayState', 'OptionsMenuState'
			 */
			switchState: function(stateName:String)
				_switchStateByName(stateName),

			/** Navega a una instancia concreta de FlxState. */
			switchStateInstance: function(stateInst:FlxState)
				StateTransition.switchState(stateInst),

			/** Navega con sticker transition. */
			stickerSwitch: function(stateInst:FlxState)
				StickerTransition.start(function() StateTransition.switchState(stateInst)),

			/** Carga un state con pantalla de loading. */
			loadState: function(stateInst:FlxState)
				LoadingState.loadAndSwitchState(stateInst),

			// ─── Cámara ────────────────────────────────────────────────────────

			shake: function(intensity:Float = 0.005, duration:Float = 0.25)
				FlxG.camera.shake(intensity, duration),

			flash: function(color:Int = 0xFFFFFFFF, duration:Float = 0.5)
				FlxG.camera.flash(color, duration),

			fade: function(color:Int = 0xFF000000, duration:Float = 0.5, fadeIn:Bool = false)
				FlxG.camera.fade(color, duration, fadeIn),

			zoom: function(target:Float = 1.0, duration:Float = 0.3)
				FlxTween.tween(FlxG.camera, {zoom: target}, duration, {ease: FlxEase.quadOut}),

			// ─── Sonido ────────────────────────────────────────────────────────
			// Usamos Paths.getSound() para que los assets de mods (no en el manifest
			// de OpenFL) se carguen directamente desde disco via Sound.fromFile().

			playSound: function(path:String, vol:Float = 1.0)
			{
				final resolvedPath = Paths.sound(path);
				final snd = Paths.getSound(resolvedPath);
				if (snd != null) FlxG.sound.play(snd, vol);
				else FlxG.sound.play(resolvedPath, vol);
			},

			playMusic: function(path:String, vol:Float = 1.0)
			{
				final resolvedPath = Paths.music(path);
				final snd = Paths.getSound(resolvedPath);
				if (snd != null) FlxG.sound.playMusic(snd, vol);
				else FlxG.sound.playMusic(resolvedPath, vol);
			},

			stopMusic: function() { if (FlxG.sound.music != null) FlxG.sound.music.stop(); },

			// ─── Utilidades ────────────────────────────────────────────────────

			/** Centra un sprite horizontalmente en pantalla. */
			centerX: function(spr:FlxSprite) { spr.screenCenter(flixel.util.FlxAxes.X); return spr; },

			/** Centra un sprite verticalmente en pantalla. */
			centerY: function(spr:FlxSprite) { spr.screenCenter(flixel.util.FlxAxes.Y); return spr; },

			/** Centra un sprite en ambos ejes. */
			center: function(spr:FlxSprite) { spr.screenCenter(); return spr; },

			/** Ancho de pantalla. */
			width: FlxG.width,

			/** Alto de pantalla. */
			height: FlxG.height,

			/** Referencia al state actual. */
			state: state
		};
	}

	// ─── Helpers internos ─────────────────────────────────────────────────────

	/** Alias público de _switchStateByName para compatibilidad con ScriptAPI. */
	public static inline function switchStateByName(name:String):Void
		_switchStateByName(name);

	/**
	 * Construye una instancia de FlxState a partir de su nombre de clase,
	 * aplicando primero los stateOverrides de GlobalConfig.
	 *
	 * Si existe un override para `name` en global.json, devuelve un
	 * ScriptableState con el nombre del override en lugar del state nativo.
	 *
	 * Uso desde Haxe (para que los menus propios también respeten los overrides):
	 *   StateTransition.switchState(ScriptBridge.resolveState('MainMenuState'));
	 */
	public static function resolveState(name:String):Null<FlxState>
	{
		// Verificar override primero
		final overrideName = GlobalConfig.resolveStateOverride(name);
		if (overrideName != null)
		{
			trace('[ScriptBridge] State override: "$name" → ScriptableState("$overrideName")');
			return new ScriptableState(overrideName);
		}
		return _buildNativeState(name);
	}

	static function _switchStateByName(name:String):Void
	{
		final inst = resolveState(name);
		if (inst != null)
			StateTransition.switchState(inst);
		else
			trace('[ScriptBridge] Estado desconocido: "$name"');
	}

	static function _buildNativeState(name:String):Null<FlxState>
	{
		return switch (name.toLowerCase())
		{
			case 'mainmenu'  | 'mainmenustate':    new funkin.menus.MainMenuState();
			case 'freeplay'  | 'freeplaystate':    new funkin.menus.FreeplayState();
			case 'story'     | 'storymenustate':   new funkin.menus.StoryMenuState();
			case 'title'     | 'titlestate':       new funkin.menus.TitleState();
			case 'options'   | 'optionsmenustate': new funkin.menus.OptionsMenuState();
			case 'credits'   | 'creditsstate':     new funkin.menus.credits.CreditsState();
			case 'play'      | 'playstate':        new funkin.gameplay.PlayState();
			case 'charselector' | 'characterselectorstate': new funkin.menus.CharacterSelectorState();
			case 'modselector'  | 'modselectorstate':       new funkin.menus.ModSelectorState();
			default: null;
		};
	}

	static function _resolveEase(name:String):Float->Float
	{
		return switch (name.toLowerCase())
		{
			case 'linear':        FlxEase.linear;
			case 'quadout':       FlxEase.quadOut;
			case 'quadin':        FlxEase.quadIn;
			case 'quadinout':     FlxEase.quadInOut;
			case 'cubeout':       FlxEase.cubeOut;
			case 'cubein':        FlxEase.cubeIn;
			case 'backout':       FlxEase.backOut;
			case 'backin':        FlxEase.backIn;
			case 'bounceout':     FlxEase.bounceOut;
			case 'bouncein':      FlxEase.bounceIn;
			case 'elasticout':    FlxEase.elasticOut;
			case 'elasticin':     FlxEase.elasticIn;
			case 'expoout':       FlxEase.expoOut;
			case 'expoin':        FlxEase.expoIn;
			case 'sineout':       FlxEase.sineOut;
			case 'sinein':        FlxEase.sineIn;
			case 'circout':       FlxEase.circOut;
			case 'circin':        FlxEase.circIn;
			default:              FlxEase.linear;
		};
	}
}
