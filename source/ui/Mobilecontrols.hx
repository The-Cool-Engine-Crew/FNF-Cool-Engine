package ui;

import flixel.FlxG;
import flixel.group.FlxSpriteGroup;

import ui.FlxVirtualPad;
import ui.Hitbox;

import data.Config;

class Mobilecontrols extends FlxSpriteGroup
{
	public var mode:ControlsGroup = HITBOX;

	public var _hitbox:Hitbox;
	public var _virtualPad:FlxVirtualPad;

	var config:Config;

	public function new() 
	{
		super();
		
		config = new Config();

		// load control mode num from Config.hx
		mode = getModeFromNumber(config.getcontrolmode());
		trace(config.getcontrolmode());

		switch (mode)
		{
			case VIRTUALPAD_RIGHT:
				initVirtualPad(0);
			case VIRTUALPAD_LEFT:
				initVirtualPad(1);
			case VIRTUALPAD_CUSTOM:
				initVirtualPad(2);
			case HITBOX:
				_hitbox = new Hitbox(FlxG.width);
				add(_hitbox);
			case KEYBOARD:
		}

		// Aplicar opacidad guardada (solo al pad, el hitbox maneja la suya propia)
		var savedAlpha:Float = FlxG.save.data.mobileAlpha != null ? FlxG.save.data.mobileAlpha : 0.75;
		if (_virtualPad != null)
			_virtualPad.alpha = savedAlpha;
	}

	function initVirtualPad(vpadMode:Int) 
	{
		switch (vpadMode)
		{
			case 1:
				_virtualPad = new FlxVirtualPad(FULL, NONE);
			case 2:
				_virtualPad = new FlxVirtualPad(FULL, NONE);
				_applyCustomLayout(_virtualPad);
			default: // 0
				_virtualPad = new FlxVirtualPad(RIGHT_FULL, NONE);
		}
		
		add(_virtualPad);	
	}

	/**
	 * Aplica el layout personalizado guardado en FlxG.save.data.mobilePadLayout.
	 * El layout es un Array de {x, y} con las posiciones de cada botón del pad
	 * en el mismo orden que FlxVirtualPad.FULL: UP, LEFT, RIGHT, DOWN.
	 *
	 * Si no hay layout guardado, usa las posiciones por defecto del VirtualPad.
	 */
	function _applyCustomLayout(pad:FlxVirtualPad):Void
	{
		var savedLayout:Array<Dynamic> = FlxG.save.data.mobilePadLayout;
		if (savedLayout == null || savedLayout.length < 4)
			return;

		// Orden de los botones en MobileControlsEditor: LEFT=0, DOWN=1, UP=2, RIGHT=3
		var buttons = [pad.buttonLeft, pad.buttonDown, pad.buttonUp, pad.buttonRight];
		for (i in 0...buttons.length)
		{
			if (buttons[i] != null && i < savedLayout.length && savedLayout[i] != null)
			{
				buttons[i].x = savedLayout[i].x;
				buttons[i].y = savedLayout[i].y;
			}
		}
	}


	public static function getModeFromNumber(modeNum:Int):ControlsGroup {
		return switch (modeNum)
		{
			case 0: VIRTUALPAD_RIGHT;
			case 1: VIRTUALPAD_LEFT;
			case 2: KEYBOARD;
			case 3: VIRTUALPAD_CUSTOM;
			case 4:	HITBOX;

			default: VIRTUALPAD_RIGHT;

		}
	}
}

enum ControlsGroup {
	VIRTUALPAD_RIGHT;
	VIRTUALPAD_LEFT;
	KEYBOARD;
	VIRTUALPAD_CUSTOM;
	HITBOX;
}
