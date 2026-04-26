package funkin.menus.substate;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.group.FlxSpriteGroup;
import flixel.math.FlxMath;
import flixel.util.FlxColor;

using StringTools;

class MenuItem extends FlxSpriteGroup
{
	public var targetY:Float = 0;
	public var week:SafeSprite;
	public var flashingInt:Int = 0;

	var weekPath:String = 'week1';

	var weekInfo:Dynamic; // formerly StoryMenuState.SongsInfo

	public function new(x:Float, y:Float, weekNum:Int = 0, ?customWeekPath:String = null)
	{
		super(x, y);
		week = new SafeSprite();

		if (customWeekPath != null && customWeekPath != '')
		{
			// Si el weekPath del JSON ya incluye carpetas (contiene '/') se usa tal cual.
			// Si es solo un nombre como "tutorial" o "weekend1", se le añade el prefijo
			// estándar para que Paths.image() lo encuentre en el lugar correcto.
			weekPath = customWeekPath.contains('/')
				? customWeekPath
				: 'menu/storymenu/titles/' + customWeekPath;
		}
		else
			weekPath = 'menu/storymenu/titles/week' + weekNum;

		// FIX: loadGraphic(String) pasa el path por el sistema de assets embebidos
		// de OpenFL, que NO puede cargar archivos arbitrarios del disco (ej: mods/).
		// Paths.getGraphic() usa BitmapData.fromFile() internamente via _loadBitmapFromDisk,
		// que sí carga cualquier ruta del sistema de archivos en runtime.
		var loaded:Bool = false;
		try
		{
			var graphic:Null<FlxGraphic> = Paths.getGraphic(weekPath);
			if (graphic != null && graphic.bitmap != null)
			{
				week.loadGraphic(graphic);
				loaded = true;
			}
		}
		catch (e:Dynamic) { trace('[MenuItem] Error cargando week$weekNum: $e'); }

		if (!loaded || week.graphic == null || week.graphic.bitmap == null)
			week.makeGraphic(256, 80, 0xFF888888);

		add(week);
	}

	private var isFlashing:Bool = false;

	public function startFlashing():Void
	{
		isFlashing = true;
	}

	var fakeFramerate:Int = 6;

	override function update(elapsed:Float)
	{
		var fr = Math.round((1 / (elapsed > 0 ? elapsed : 1.0 / 60.0)) / 10);
		fakeFramerate = fr > 0 ? fr : 6;

		super.update(elapsed);
		y = FlxMath.lerp(y, (targetY * 120) + 480, 0.17);

		if (isFlashing)
			flashingInt += 1;

		if (flashingInt % fakeFramerate >= Math.floor(fakeFramerate / 2))
			week.color = 0xFF33ffff;
		else
			week.color = FlxColor.WHITE;
	}
}

/**
 * FlxSprite con override de draw() que corta el pipeline de render
 * si graphic o bitmap son null, evitando el crash en FlxDrawQuadsItem::render.
 */
class SafeSprite extends FlxSprite
{
	override function draw():Void
	{
		if (graphic == null || graphic.bitmap == null) return;
		super.draw();
	}
}
