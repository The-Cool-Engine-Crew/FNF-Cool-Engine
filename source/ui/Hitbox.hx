package ui;

import flixel.graphics.FlxGraphic;

import flixel.FlxSprite;
import flixel.FlxG;
import flixel.graphics.frames.FlxTileFrames;
import flixel.group.FlxSpriteGroup;
import flixel.math.FlxPoint;
import flixel.system.FlxAssets;
import flixel.util.FlxDestroyUtil;
import flixel.ui.FlxButton;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.graphics.frames.FlxFrame;
import flixel.ui.FlxVirtualPad;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;

class Hitbox extends FlxSpriteGroup
{
    var sizex:Int;

    public var buttonLeft:FlxButton;
    public var buttonDown:FlxButton;
    public var buttonUp:FlxButton;
    public var buttonRight:FlxButton;

    public function new(?widthScreen:Int)
    {
        super();

        sizex = widthScreen != null ? Std.int(widthScreen / 4) : Std.int(FlxG.width / 4);

        var hitbox_hint:FlxSprite = new FlxSprite(0, 0).loadGraphic(Paths.image('hitbox/hitbox_hint'));
        hitbox_hint.alpha = 0.2;
        add(hitbox_hint);

        add(buttonLeft  = createhitbox(0,         "left"));
        add(buttonDown  = createhitbox(sizex,      "down"));
        add(buttonUp    = createhitbox(sizex * 2,  "up"));
        add(buttonRight = createhitbox(sizex * 3,  "right"));
    }

    public function createhitbox(X:Float, framestring:String):FlxButton
    {
        var button = new FlxButton(X, 0);

        var frames = Paths.getSparrowAtlas('hitbox/hitbox');
        var graphic:FlxGraphic = FlxGraphic.fromFrame(frames.getByName(framestring));

        button.loadGraphic(graphic);
        button.alpha = 0;
        button.scrollFactor.set();

        button.onDown.callback = function() {
            FlxTween.num(0, 0.75, .075, {ease: FlxEase.circInOut}, function(a:Float) { button.alpha = a; });
        };

        button.onUp.callback = function() {
            FlxTween.num(0.75, 0, .1, {ease: FlxEase.circInOut}, function(a:Float) { button.alpha = a; });
        };

        button.onOut.callback = function() {
            FlxTween.num(button.alpha, 0, .2, {ease: FlxEase.circInOut}, function(a:Float) { button.alpha = a; });
        };

        return button;
    }

    override public function destroy():Void
    {
        super.destroy();

        buttonLeft  = null;
        buttonDown  = null;
        buttonUp    = null;
        buttonRight = null;
    }
}