package funkin.menus;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import funkin.cutscenes.VideoManager;
import funkin.scripting.StateScriptHandler;
import funkin.transitions.StateTransition;
import animationdata.FunkinSprite;
import haxe.Json;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

using StringTools;

/**
 * IntroState — Scriptable engine intro sequence.
 *
 * Plays a series of slides before reaching TitleState.
 * Each slide can be a video, a static image, a Sparrow-animated sprite,
 * a FlxAnimate Texture Atlas, or a solid color screen.
 *
 * ── JSON config ──────────────────────────────────────────────────────────────
 *   assets/data/intro.json   (or   mods/{mod}/data/intro.json)
 *
 *   {
 *     "skipable": true,
 *     "defaultFadeIn":  0.4,
 *     "defaultFadeOut": 0.4,
 *     "slides": [
 *       { "type": "video",   "asset": "videos/engine_intro" },
 *       { "type": "image",   "asset": "images/intro/logo", "duration": 3.0,
 *                            "sound": "intro_jingle" },
 *       { "type": "sparrow", "asset": "images/intro/splash",
 *                            "animation": "intro", "fps": 24, "waitForEnd": true },
 *       { "type": "atlas",   "asset": "images/intro/engineLogo",
 *                            "animation": "intro anim", "waitForEnd": true },
 *       { "type": "color",   "color": "0xFF1a1a2e", "duration": 1.5 }
 *     ]
 *   }
 *
 * ── Scripting ─────────────────────────────────────────────────────────────────
 *   Drop .hscript / .hx files in:  assets/states/introstate/
 *
 *   Available hooks:
 *     onCreate()
 *     onSlideStart(index:Int, slide:Dynamic)
 *     onSlideEnd(index:Int,   slide:Dynamic)
 *     onSkip()
 *     onFinish()
 *     onUpdate(elapsed:Float)
 *     onDestroy()
 *
 * ── Example HScript override ──────────────────────────────────────────────────
 *   function onSlideStart(i, data) {
 *       if (i == 0) FlxG.sound.play(Paths.sound('engine_jingle'));
 *   }
 *   function onFinish() {
 *       StateTransition.switchState(new MainMenuState());
 *   }
 */

// ─────────────────────────────────────────────────────────────────────────────
//  JSON typedefs
// ─────────────────────────────────────────────────────────────────────────────

typedef IntroSlideData =
{
	/**
	 * Slide type. One of:
	 *   "video"   → full-screen MP4 via VideoManager
	 *   "image"   → static PNG centered on screen
	 *   "sparrow" → frame-animated sprite (Sparrow XML + PNG atlas)
	 *   "atlas"   → FunkinSprite / FlxAnimate Texture Atlas folder
	 *   "color"   → solid color screen with a duration
	 */
	var type:String;

	/**
	 * Asset path without extension, relative to assets/.
	 *   video   → "videos/intro_engine"
	 *   image   → "images/intro/logo"
	 *   sparrow → "images/intro/splash"
	 *   atlas   → "images/intro/engineLogo"  (folder)
	 *   color   → ignored
	 */
	@:optional var asset:Null<String>;

	/** Duration in seconds. null = natural length (valid for video / sparrow+waitForEnd / atlas+waitForEnd). */
	@:optional var duration:Null<Float>;

	/** Fade-in duration in seconds. 0 or null = use global default. */
	@:optional var fadeIn:Null<Float>;

	/** Fade-out duration in seconds. 0 or null = use global default. */
	@:optional var fadeOut:Null<Float>;

	/** Background color behind the sprite. Hex string "0xFF000000". Default black. */
	@:optional var bgColor:Null<String>;

	/** Fill color for "color" slides. Hex string "0xFF1a1a2e". Default black. */
	@:optional var color:Null<String>;

	/** Animation name to play (sparrow / atlas types). */
	@:optional var animation:Null<String>;

	/** Animation FPS for sparrow type. Default 24. */
	@:optional var fps:Null<Int>;

	/**
	 * If true, waits for the animation to finish before advancing.
	 * Works with sparrow and atlas types.
	 * duration is ignored when this is true.
	 */
	@:optional var waitForEnd:Null<Bool>;

	/** Uniform sprite scale. Default 1.0. */
	@:optional var scale:Null<Float>;

	/** Sound to play when this slide starts. Logical path without extension. */
	@:optional var sound:Null<String>;

	/** Whether this individual slide can be skipped. Inherits global if null. */
	@:optional var skipable:Null<Bool>;
}

typedef IntroData =
{
	/** Ordered list of slides to play. */
	var slides:Array<IntroSlideData>;

	/** Whether any key / button skips the entire intro. Default true. */
	@:optional var skipable:Null<Bool>;

	/** Default fade-in duration applied to slides that don't set their own. Default 0.4. */
	@:optional var defaultFadeIn:Null<Float>;

	/** Default fade-out duration applied to slides that don't set their own. Default 0.4. */
	@:optional var defaultFadeOut:Null<Float>;
}

// ─────────────────────────────────────────────────────────────────────────────
//  IntroState
// ─────────────────────────────────────────────────────────────────────────────

class IntroState extends funkin.states.MusicBeatState
{
	// ── Static flags ──────────────────────────────────────────────────────────

	/** Set to true once the intro has fully played through. */
	public static var finished:Bool = false;

	// ── Data ──────────────────────────────────────────────────────────────────

	var _data:IntroData        = null;
	var _curSlide:Int          = 0;
	var _totalSlides:Int       = 0;
	var _skipped:Bool          = false;

	// ── Active slide references ───────────────────────────────────────────────

	/** Solid background quad — always present, color-tinted per slide. */
	var _bg:FlxSprite          = null;
	/** Current static image or Sparrow-animated sprite. */
	var _sprite:FlxSprite      = null;
	/** Current FlxAnimate Texture Atlas sprite. */
	var _funkinSprite:FunkinSprite = null;

	// ── Timers / tweens ───────────────────────────────────────────────────────

	var _slideTimer:FlxTimer   = null;
	var _fadeInTween:FlxTween  = null;
	var _fadeOutTween:FlxTween = null;

	// ── Video state ───────────────────────────────────────────────────────────

	var _videoPlaying:Bool     = false;

	// ─────────────────────────────────────────────────────────────────────────
	//  Static helpers
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Returns true if a valid intro.json exists (with at least one slide).
	 * Called by CacheState to decide whether to insert IntroState before TitleState.
	 */
	public static function introExists():Bool
	{
		#if sys
		for (p in _jsonCandidatePaths())
			if (FileSystem.exists(p))
				return true;
		#end
		return false;
	}

	static function _jsonCandidatePaths():Array<String>
	{
		final list:Array<String> = [];
		#if sys
		final modRoot = mods.ModManager.modRoot();
		if (modRoot != null)
		{
			list.push('$modRoot/data/intro.json');
			list.push('$modRoot/assets/data/intro.json');
		}
		list.push('assets/data/intro.json');
		#end
		return list;
	}

	static function _loadJson():Null<IntroData>
	{
		#if sys
		for (p in _jsonCandidatePaths())
		{
			if (!FileSystem.exists(p)) continue;
			try
			{
				final raw:IntroData = cast Json.parse(File.getContent(p));
				if (raw != null && raw.slides != null && raw.slides.length > 0)
				{
					trace('[IntroState] Loaded intro.json from: $p  (${raw.slides.length} slide(s))');
					return raw;
				}
			}
			catch (e:Dynamic) { trace('[IntroState] Error parsing $p: $e'); }
		}
		#end
		return null;
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Lifecycle
	// ─────────────────────────────────────────────────────────────────────────

	override function create():Void
	{
		// We load scripts manually below — disable auto-load to avoid duplicates.
		autoScriptLoad = false;

		super.create();

		_data = _loadJson();
		if (_data == null || _data.slides == null || _data.slides.length == 0)
		{
			trace('[IntroState] No slides found — jumping straight to TitleState.');
			// FIX (Android/Adreno): calling StateTransition.switchState() synchronously
			// inside create() corrupts the OpenGL context because the previous state's
			// render cycle has not finished yet.  Defer by one frame so Flixel has time
			// to complete the state transition bookkeeping before we switch again.
			new FlxTimer().start(0, function(_) _goNext());
			return;
		}
		_totalSlides = _data.slides.length;

		// Base black background — always visible, tinted per slide.
		_bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		_bg.scrollFactor.set();
		add(_bg);

		// Load scripts from assets/states/introstate/
		#if HSCRIPT_ALLOWED
		StateScriptHandler.init();
		StateScriptHandler.loadStateScripts('IntroState', this);
		StateScriptHandler.refreshStateFields(this);
		StateScriptHandler.callOnScripts('onCreate', []);
		#end

		// FIX (Android/Adreno): defer first slide by one frame for the same reason
		// as the no-slides path above.  This also prevents any synchronous callback
		// chains triggered by _playSlide (e.g., an immediately-missing video asset
		// calling its onComplete inside create()) from reaching _goNext() before
		// Flixel's state machine is ready.
		new FlxTimer().start(0, function(_) _playSlide(0));
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		if (!_skipped && _canSkipGlobal())
		{
			final anyKey    = FlxG.keys.justPressed.ANY;
			final anyButton = FlxG.gamepads.anyJustPressed(flixel.input.gamepad.FlxGamepadInputID.ANY);
			if (anyKey || anyButton)
				_skip();
		}
	}

	override function destroy():Void
	{
		_cancelPending();
		VideoManager.onVideoEnded.remove(_onVideoEnded);

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onDestroy', []);
		StateScriptHandler.clearStateScripts();
		#end

		super.destroy();
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Slide dispatch
	// ─────────────────────────────────────────────────────────────────────────

	function _playSlide(index:Int):Void
	{
		if (index >= _totalSlides)
		{
			_finish();
			return;
		}

		_curSlide = index;
		final slide = _data.slides[index];

		// ── Script hook ───────────────────────────────────────────────────────
		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onSlideStart', [index, slide]);
		#end

		// ── Background color ──────────────────────────────────────────────────
		final bgHex = (slide.bgColor != null) ? slide.bgColor : '0xFF000000';
		_bg.color = _parseColor(bgHex);
		_bg.alpha  = 1;

		// ── Optional sound ────────────────────────────────────────────────────
		if (slide.sound != null && slide.sound.trim() != '')
		{
			final sndPath = Paths.sound(slide.sound);
			if (sndPath != null)
				FlxG.sound.play(sndPath);
		}

		// ── Dispatch by type ──────────────────────────────────────────────────
		switch (slide.type.toLowerCase().trim())
		{
			case 'video':   _playVideo(index, slide);
			case 'image':   _playImage(index, slide);
			case 'sparrow': _playSparrow(index, slide);
			case 'atlas':   _playAtlas(index, slide);
			case 'color':   _playColor(index, slide);
			default:
				trace('[IntroState] Unknown slide type "${slide.type}" at index $index — skipping.');
				_endSlide(index);
		}
	}

	// ── Video ─────────────────────────────────────────────────────────────────

	function _playVideo(index:Int, slide:IntroSlideData):Void
	{
		if (slide.asset == null || slide.asset.trim() == '')
		{
			trace('[IntroState] Slide $index (video) has no asset — skipping.');
			new FlxTimer().start(0, function(_) _endSlide(index));
			return;
		}

		// FIX: pre-validate the path BEFORE calling playCutscene.
		// If the video asset is missing, VideoManager.playCutscene() fires its
		// onComplete synchronously (before returning).  Without this guard that
		// would kick off _endSlide → ... → _goNext() all within the same call
		// frame, which is the same OpenGL-context corruption bug as the create()
		// crash — but triggered by a missing video rather than missing slides.
		final resolvedPath = VideoManager._resolvePath(slide.asset);
		if (resolvedPath == null)
		{
			trace('[IntroState] Slide $index: video not found "${slide.asset}" — skipping.');
			new FlxTimer().start(0, function(_) _endSlide(index));
			return;
		}

		_videoPlaying = true;
		VideoManager.onVideoEnded.add(_onVideoEnded);

		VideoManager.playCutscene(slide.asset, function()
		{
			// Guard against double-advance: _onVideoEnded (the signal safety-
			// fallback below) may fire first on some platforms, clearing
			// _videoPlaying before this callback runs.
			if (!_videoPlaying) return;
			_videoPlaying = false;
			VideoManager.onVideoEnded.remove(_onVideoEnded);
			// Defer: never call _endSlide synchronously from a video callback —
			// the callback may arrive inside a Lime event dispatch where Flixel's
			// render cycle is already in progress.
			new FlxTimer().start(0, function(_) _endSlide(_curSlide));
		});
	}

	/**
	 * Safety fallback: fired when VideoManager dispatches onVideoEnded but the
	 * playCutscene callback was never called (e.g. platforms where the
	 * finishCallback pipe is unreliable).  Also acts as the first handler when
	 * both fire, preventing a double _endSlide via the _videoPlaying guard.
	 */
	function _onVideoEnded():Void
	{
		if (!_videoPlaying) return; // already handled — don't double-advance
		_videoPlaying = false;
		VideoManager.onVideoEnded.remove(_onVideoEnded);
		new FlxTimer().start(0, function(_) _endSlide(_curSlide));
	}

	// ── Static image ──────────────────────────────────────────────────────────

	function _playImage(index:Int, slide:IntroSlideData):Void
	{
		_clearSprites();

		if (slide.asset != null && slide.asset.trim() != '')
		{
			final imgPath = Paths.image(slide.asset);
			if (imgPath != null)
			{
				_sprite = new FlxSprite();
				_sprite.loadGraphic(imgPath);
				_sprite.scrollFactor.set();
				if (slide.scale != null && slide.scale != 1.0)
					_sprite.scale.set(slide.scale, slide.scale);
				_sprite.updateHitbox();
				_sprite.screenCenter();
				_sprite.alpha = 0;
				add(_sprite);
			}
			else trace('[IntroState] Slide $index: image not found "${slide.asset}"');
		}

		_runFadeSequence(index, slide, _sprite);
	}

	// ── Sparrow atlas ─────────────────────────────────────────────────────────

	function _playSparrow(index:Int, slide:IntroSlideData):Void
	{
		_clearSprites();

		if (slide.asset == null || slide.asset.trim() == '')
		{
			trace('[IntroState] Slide $index (sparrow) has no asset — skipping.');
			_endSlide(index);
			return;
		}

		final frames:FlxAtlasFrames = Paths.getSparrowAtlas(slide.asset);
		if (frames == null)
		{
			trace('[IntroState] Slide $index: Sparrow atlas not found "${slide.asset}"');
			_endSlide(index);
			return;
		}

		_sprite = new FlxSprite();
		_sprite.frames = frames;

		final animName = (slide.animation != null && slide.animation.trim() != '')
			? slide.animation : 'anim';
		final fps:Int = (slide.fps != null) ? slide.fps : 24;

		_sprite.animation.addByPrefix(animName, animName, fps, false);
		_sprite.animation.play(animName);

		if (slide.scale != null && slide.scale != 1.0)
			_sprite.scale.set(slide.scale, slide.scale);
		_sprite.updateHitbox();
		_sprite.screenCenter();
		_sprite.scrollFactor.set();
		_sprite.alpha = 0;
		add(_sprite);

		final waitForEnd = (slide.waitForEnd == true);

		if (waitForEnd)
		{
			// Wait for the animation to finish, then fade out.
			final fadeOut = _resolveFloat(slide.fadeOut, _data.defaultFadeOut, 0.4);
			_runFadeIn(index, slide, _sprite, function()
			{
				// Poll every frame until the animation is done.
				var _pollTimer:FlxTimer = null;
				_pollTimer = new FlxTimer().start(1 / 60, function(t:FlxTimer)
				{
					if (_sprite == null || _sprite.animation.curAnim == null
						|| _sprite.animation.curAnim.finished)
					{
						_pollTimer.cancel();
						_runFadeOut(index, slide, _sprite, function() _endSlide(index));
					}
					else
						_pollTimer.start(1 / 60, t.onComplete);
				});
			});
		}
		else
		{
			_runFadeSequence(index, slide, _sprite);
		}
	}

	// ── Texture Atlas (FlxAnimate / FunkinSprite) ─────────────────────────────

	function _playAtlas(index:Int, slide:IntroSlideData):Void
	{
		_clearSprites();

		if (slide.asset == null || slide.asset.trim() == '')
		{
			trace('[IntroState] Slide $index (atlas) has no asset — skipping.');
			_endSlide(index);
			return;
		}

		_funkinSprite = new FunkinSprite(0, 0);
		_funkinSprite.loadAnimateAtlas(slide.asset);

		final animName = (slide.animation != null && slide.animation.trim() != '')
			? slide.animation : null;
		if (animName != null)
			_funkinSprite.anim.play(animName, true);

		if (slide.scale != null && slide.scale != 1.0)
			_funkinSprite.scale.set(slide.scale, slide.scale);
		_funkinSprite.updateHitbox();
		_funkinSprite.screenCenter();
		_funkinSprite.scrollFactor.set();
		_funkinSprite.alpha = 0;
		add(_funkinSprite);

		final waitForEnd = (slide.waitForEnd == true);

		if (waitForEnd)
		{
			final fadeOut = _resolveFloat(slide.fadeOut, _data.defaultFadeOut, 0.4);
			_runFadeIn(index, slide, _funkinSprite, function()
			{
				var _pollTimer:FlxTimer = null;
				_pollTimer = new FlxTimer().start(1 / 60, function(t:FlxTimer)
				{
					// FIX: the original condition was `finished == false` which
					// evaluated done=true while the animation was STILL PLAYING,
					// causing the fade-out to start immediately instead of waiting.
					// Correct: done when finished IS true (or sprite was destroyed).
					final done = (_funkinSprite == null)
						|| (_funkinSprite.anim == null)
						|| _funkinSprite.anim.finished;

					if (done)
					{
						_pollTimer.cancel();
						_runFadeOut(index, slide, _funkinSprite, function() _endSlide(index));
					}
					else
						_pollTimer.start(1 / 60, t.onComplete);
				});
			});
		}
		else
		{
			_runFadeSequence(index, slide, _funkinSprite);
		}
	}

	// ── Solid color ───────────────────────────────────────────────────────────

	function _playColor(index:Int, slide:IntroSlideData):Void
	{
		_clearSprites();

		final hex = (slide.color != null) ? slide.color : '0xFF000000';
		_bg.color = _parseColor(hex);
		_bg.alpha  = 1;

		// Color slides use a dedicated sprite overlay for fades so the bg stays solid.
		final overlay = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		overlay.color = _parseColor(hex);
		overlay.scrollFactor.set();
		overlay.alpha  = 0;
		_sprite        = overlay;
		add(_sprite);

		_runFadeSequence(index, slide, _sprite);
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Fade helpers
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Full fade-in → hold → fade-out sequence driven by slide.duration.
	 * If the sprite is null (asset missing) it just waits the duration and advances.
	 */
	function _runFadeSequence(index:Int, slide:IntroSlideData, ?target:FlxSprite):Void
	{
		final fadeIn  = _resolveFloat(slide.fadeIn,  _data.defaultFadeIn,  0.4);
		final fadeOut = _resolveFloat(slide.fadeOut, _data.defaultFadeOut, 0.4);
		final dur     = (slide.duration != null) ? slide.duration : 2.0;

		// Nothing to fade — just wait.
		if (target == null)
		{
			_slideTimer = new FlxTimer().start(dur, function(_) _endSlide(index));
			return;
		}

		target.alpha = 0;

		_runFadeIn(index, slide, target, function()
		{
			// Hold duration minus the two fades (don't go negative).
			final holdTime = Math.max(0, dur - fadeIn - fadeOut);
			_slideTimer = new FlxTimer().start(holdTime, function(_)
			{
				_runFadeOut(index, slide, target, function() _endSlide(index));
			});
		});
	}

	function _runFadeIn(index:Int, slide:IntroSlideData, target:FlxSprite, onDone:Void->Void):Void
	{
		final dur = _resolveFloat(slide.fadeIn, _data.defaultFadeIn, 0.4);
		if (dur <= 0 || target == null)
		{
			if (target != null) target.alpha = 1;
			onDone();
			return;
		}
		_fadeInTween = FlxTween.tween(target, {alpha: 1}, dur,
		{
			ease: FlxEase.quadOut,
			onComplete: function(_) onDone()
		});
	}

	function _runFadeOut(index:Int, slide:IntroSlideData, target:FlxSprite, onDone:Void->Void):Void
	{
		final dur = _resolveFloat(slide.fadeOut, _data.defaultFadeOut, 0.4);
		if (dur <= 0 || target == null)
		{
			onDone();
			return;
		}
		_fadeOutTween = FlxTween.tween(target, {alpha: 0}, dur,
		{
			ease: FlxEase.quadIn,
			onComplete: function(_) onDone()
		});
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Slide completion
	// ─────────────────────────────────────────────────────────────────────────

	function _endSlide(index:Int):Void
	{
		// Script hook — scripts can call IntroState.skipToEnd() here if they want.
		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onSlideEnd', [index, _data.slides[index]]);
		#end

		_clearSprites();
		_cancelPending();
		_playSlide(index + 1);
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Skip logic
	// ─────────────────────────────────────────────────────────────────────────

	function _canSkipGlobal():Bool
	{
		// Global skipable flag — defaults to true if not set.
		return (_data.skipable == null || _data.skipable == true);
	}

	function _canSkipSlide(slide:IntroSlideData):Bool
	{
		if (slide.skipable != null) return slide.skipable;
		return _canSkipGlobal();
	}

	function _skip():Void
	{
		_skipped = true;
		_cancelPending();
		_clearSprites();

		if (VideoManager.isPlaying)
			VideoManager.onVideoEnded.remove(_onVideoEnded);

		#if HSCRIPT_ALLOWED
		// If a script cancels the skip it should set a shared "cancelSkip" flag
		// and handle navigation itself.
		final cancelled = StateScriptHandler.callOnScripts('onSkip', []);
		if (cancelled == true) return;
		#end

		_finish();
	}

	/**
	 * Exposed so HScripts can call IntroState.skipToEnd() to jump immediately
	 * to _finish() from any hook without going through _skip().
	 */
	public function skipToEnd():Void
	{
		_cancelPending();
		_clearSprites();
		_finish();
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Finish
	// ─────────────────────────────────────────────────────────────────────────

	function _finish():Void
	{
		finished = true;

		#if HSCRIPT_ALLOWED
		// Scripts can switch to a custom state inside onFinish() and return true
		// to prevent the default TitleState switch.
		final handled = StateScriptHandler.callOnScripts('onFinish', []);
		if (handled == true) return;
		#end

		_goNext();
	}

	function _goNext():Void
	{
		StateTransition.switchState(funkin.scripting.ScriptBridge.resolveState('TitleState') ?? new TitleState());
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Cleanup helpers
	// ─────────────────────────────────────────────────────────────────────────

	/** Removes and destroys the active sprites from the scene. */
	function _clearSprites():Void
	{
		if (_sprite != null)
		{
			remove(_sprite, true);
			_sprite.destroy();
			_sprite = null;
		}
		if (_funkinSprite != null)
		{
			remove(_funkinSprite, true);
			_funkinSprite.destroy();
			_funkinSprite = null;
		}
	}

	/** Cancels all active timers and tweens. */
	function _cancelPending():Void
	{
		if (_slideTimer != null)   { _slideTimer.cancel();   _slideTimer   = null; }
		if (_fadeInTween != null)  { _fadeInTween.cancel();  _fadeInTween  = null; }
		if (_fadeOutTween != null) { _fadeOutTween.cancel(); _fadeOutTween = null; }
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Utilities
	// ─────────────────────────────────────────────────────────────────────────

	/** Parses a hex color string like "0xFF1a2b3c" into FlxColor. Falls back to black. */
	static function _parseColor(hex:String):FlxColor
	{
		try
		{
			final clean = hex.trim().toLowerCase()
				.replace('0x', '').replace('#', '');
			return FlxColor.fromInt(Std.parseInt('0x$clean'));
		}
		catch (e:Dynamic) {}
		return FlxColor.BLACK;
	}

	/** Returns `a` if not null, else `b` if not null, else `fallback`. */
	static inline function _resolveFloat(a:Null<Float>, b:Null<Float>, fallback:Float):Float
	{
		if (a != null) return a;
		if (b != null) return b;
		return fallback;
	}
}
