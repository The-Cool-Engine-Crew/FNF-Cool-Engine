var healthBarBG;
var healthBar;
var iconP1;
var iconP2;
var scoreTxt;
var scoreManager;
var curStage = '';
var iconP1Name = 'bf';
var iconP2Name = 'dad';
var lastScore = -1;
var lastMisses = -1;
var lastAccuracy = -1.0;
var lastHealth = -1.0;

// Target X that the icons are tracking each frame.
// It updates only when health changes, so the tracking doesn't
// track a target X that moves with the beat bounce scale.

var iconTargetX = -1.0;

// Beat bounce — separate scale multiplier that decays each frame.
// Keeps icon lerp-X target stable (uses fixed 150px base, not current width).
var iconP1Bounce = 1.0;
var iconP2Bounce = 1.0;

// How fast the bounce decays back to 1.0 (higher = snappier return).
var BOUNCE_DECAY = 14.0;

// Peak scale on beat hit.
var BOUNCE_PEAK = 1.2;

// ── Pools (same 3 as the original + miss) ──────────────────────────────────
var ratingPool = [];
var numberPool = [];
var comboPool = [];
var missPool = [];

// ══════════════════════════════════════════════════════════════════════════
//  onCreate ─ replicate new UIManager() + createHealthBar() + createScoreText()
// ══════════════════════════════════════════════════════════════════════════
function onCreate()
{
	onInit();
	scoreManager = new ScoreManager();
	_createScoreText();
	_createHealthBar();
}

function _createHealthBar()
{
	var healthBarY = SaveData.data.downscroll ? FlxG.height * 0.1 : FlxG.height * 0.88;

	healthBarBG = makeSprite(0, healthBarY);
	healthBarBG.loadGraphic(Paths.getGraphic('UI/healthBar'));
	screenCenterX(healthBarBG);
	uiAdd(healthBarBG);

	// makeBar already sets RIGHT_TO_LEFT, scrollFactor and camHUD
	healthBar = makeBar(healthBarBG.x + 4, healthBarBG.y + 4, Std.int(healthBarBG.width - 8), Std.int(healthBarBG.height - 8), gameState, 'health', 0, 2);
	var dadColor = (dad != null && dad.characterData != null && dad.characterData.healthBarColor != null)
		? dad.healthBarColor : 0xFFFF0000;
	var bfColor  = (boyfriend != null && boyfriend.characterData != null && boyfriend.characterData.healthBarColor != null)
		? boyfriend.healthBarColor : 0xFF66FF33;
	healthBar.createFilledBar(dadColor, bfColor);
	uiAdd(healthBar);

	// HealthIcon is exposed from UIScriptedManager
	iconP1 = new HealthIcon(iconP1Name, true);
	iconP1.y = healthBar.y - (iconP1.height / 2);
	uiAdd(iconP1);

	iconP2 = new HealthIcon(iconP2Name, false);
	iconP2.y = healthBar.y - (iconP2.height / 2);
	uiAdd(iconP2);
}

function _createScoreText()
{
    var healthBarY = SaveData.data.downscroll ? FlxG.height * 0.1 : FlxG.height * 0.98;
    scoreTxt = makeText(0, healthBarY - 35, '', 20);
    scoreTxt.fieldWidth = FlxG.width;
    scoreTxt.antialiasing = SaveData.data.antialiasing;
    scoreTxt.setFormat(Paths.font('Funkin.otf'), 20, 0xFFFFFFFF, "center");
    setTextBorder(scoreTxt, 'outline', 0xFF000000, 2, 1);
    scoreTxt.size = 20;
    uiAdd(scoreTxt);
}

// ══════════════════════════════════════════════════════════════════════════
//  onUpdate
// ══════════════════════════════════════════════════════════════════════════
function onUpdate(elapsed)
{
	if (lastScore != gameState.score || lastMisses != gameState.misses || lastAccuracy != gameState.accuracy)
	{
		_updateScoreText();
		lastScore = gameState.score;
		lastMisses = gameState.misses;
		lastAccuracy = gameState.accuracy;
	}

	_updateIcons();
}

function _formatScore(n)
{
	var s = Std.string(Std.int(n));
	var result = '';
	var count = 0;
	var i = s.length - 1;
	while (i >= 0)
	{
		if (count > 0 && count % 3 == 0)
			result = ',' + result;
		result = s.charAt(i) + result;
		count++;
		i--;
	}
	return result;
}

function _updateScoreText()
{
	if (scoreTxt == null)
		return;

	var rawScore = Std.string(Std.int(gameState.score));
	var formattedScore = _formatScore(gameState.score);

	if (SaveData.data.accuracyDisplay)
		scoreTxt.text = StringTools.replace(scoreManager.getHUDText(gameState), rawScore, formattedScore);
	else
		scoreTxt.text = 'Score: ' + formattedScore + ' - Misses: ' + gameState.misses;
}

function _updateIcons()
{
	if (iconP1 == null || iconP2 == null || healthBar == null)
		return;

	var healthPercent = FlxMath.remapToRange(gameState.health, 0, 2, 0, 100);

	// ── Beat bounce decay ───────────────────────────────────────────────────
	// Decay the bounce multiplier towards 1.0 exponentially each frame.
	// This is independent of setGraphicSize so it never moves iconTargetX.
	var decayFactor = 1 - (BOUNCE_DECAY * FlxG.elapsed);
	iconP1Bounce = 1.0 + (iconP1Bounce - 1.0) * decayFactor;
	iconP2Bounce = 1.0 + (iconP2Bounce - 1.0) * decayFactor;

	// Clamp bounce to avoid negative scale on edge cases
	if (iconP1Bounce < 1.0)
		iconP1Bounce = 1.0;
	if (iconP2Bounce < 1.0)
		iconP2Bounce = 1.0;

	// Apply bounce scale — base size is always 150px, bounce on top of that.
	var p1Size = Std.int(150 * iconP1Bounce);
	var p2Size = Std.int(150 * iconP2Bounce);
	iconP1.setGraphicSize(p1Size);
	iconP2.setGraphicSize(p2Size);
	iconP1.updateHitbox();
	iconP2.updateHitbox();

	// ── Lerp of position X ────────────────────────────────────────────────────
	// iconTargetX is computed from the health bar position only.
	// The anchor offsets use a FIXED base width (150) so the target never
	// oscillates when the bounce scale changes — the lerp stays stable.
	var rawTargetX = healthBar.x + (healthBar.width * (FlxMath.remapToRange(healthPercent, 0, 100, 100, 0) * 0.01));
	if (gameState.health != lastHealth)
	{
		iconTargetX = rawTargetX;
		lastHealth = gameState.health;
	}
	else if (iconTargetX < 0)
	{
		iconTargetX = rawTargetX;
	}

	// FIX: use fixed 150px for the width offset — not iconP2.width (which
	// oscillates with bounce) — so the lerp target is rock-stable every frame.
	iconP1.x = FlxMath.lerp(iconP1.x, iconTargetX - 26, 0.15 * FlxG.elapsed * 60);
	iconP2.x = FlxMath.lerp(iconP2.x, iconTargetX - (150 - 26), 0.15 * FlxG.elapsed * 60);

	var p1Anim = 'normal';
	if (healthPercent < 20)
		p1Anim = 'losing';
	else if (healthPercent > 80)
		p1Anim = 'winning';

	var p2Anim = 'normal';
	if (healthPercent > 80)
		p2Anim = 'losing';
	else if (healthPercent < 20)
		p2Anim = 'winning';

	_changeIconAnim(iconP1, p1Anim);
	_changeIconAnim(iconP2, p2Anim);
}

function _changeIconAnim(icon, anim)
{
	if (icon.animation.curAnim != null && icon.animation.curAnim.name != anim)
		icon.animation.play(anim);
}

// ══════════════════════════════════════════════════════════════════════════
//  onBeatHit
// ══════════════════════════════════════════════════════════════════════════
function onBeatHit(beat)
{
	// FIX: instead of abruptly setting scale (which snaps width and breaks
	// the lerp-X target), we set the bounce multiplier to the peak value.
	// The decay in _updateIcons() eases it back to 1.0 smoothly each frame,
	// producing a natural "pulse" without ever touching iconP*.width directly.
	if (iconP1 != null)
		iconP1Bounce = BOUNCE_PEAK;
	if (iconP2 != null)
		iconP2Bounce = BOUNCE_PEAK;
}

// Rating Position Offset — configurable from Options > Gameplay > Rating Position
// Saved in FlxG.save.data.ratingOffsetX / ratingOffsetY.
var posX = 0;
var posY = 0;

function onInit()
{
	// Read the saved offsets (default: original base position = -50, 0)
	posX = (SaveData.data.ratingOffsetX != null) ? SaveData.data.ratingOffsetX : -100;
	posY = (SaveData.data.ratingOffsetY != null) ? SaveData.data.ratingOffsetY : 0;
}

// ══════════════════════════════════════════════════════════════════════════
//  onRatingPopup
// ══════════════════════════════════════════════════════════════════════════
function onRatingPopup(ratingName, combo)
{
	var pixelPart1 = 'normal/score/';
	var pixelPart2 = '';

	if (isPixel)
	{
		pixelPart1 = 'pixelUI/score/';
		pixelPart2 = '-pixel';
	}

	// Kill the previous rating and combo numbers before showing the new one
	_killPoolInstant(ratingPool);
	_killPoolInstant(numberPool);

	var ratingSprite = _getFromPool(ratingPool);
	ratingSprite.alpha = 1;
	ratingSprite.visible = true;

	ratingSprite.loadGraphic(Paths.getGraphic('UI/' + pixelPart1 + ratingName + pixelPart2));

	ratingSprite.x = FlxG.width * 0.55 - 40 + posX;
	ratingSprite.y = FlxG.height * 0.5 - 90 + posY;

	if (!isPixel)
	{
		ratingSprite.setGraphicSize(Std.int(ratingSprite.width * 0.7));
		ratingSprite.antialiasing = SaveData.data.antialiasing;
	}
	else
	{
		ratingSprite.setGraphicSize(Std.int(ratingSprite.width * PIXEL_ZOOM * 0.7));
		ratingSprite.antialiasing = false;
	}
	ratingSprite.updateHitbox();

	var sx = ratingSprite.scale.x * 1.15;
	var sy = ratingSprite.scale.y * 1.15;
	FlxTween.tween(ratingSprite.scale, {x: sx, y: sy}, 0.07, {
		ease: FlxEase.quadOut,
		onComplete: function(_)
		{
			FlxTween.tween(ratingSprite.scale, {x: ratingSprite.scale.x / 1.15, y: ratingSprite.scale.y / 1.15}, 0.10, {ease: FlxEase.quadIn});
		}
	});

	FlxTween.tween(ratingSprite, {alpha: 0}, 0.20, {
		startDelay: 0.45,
		ease: FlxEase.quadIn,
		onComplete: function(_)
		{
			ratingSprite.kill();
		}
	});

	if (combo >= 10)
		_showComboNumbers(combo, pixelPart1, pixelPart2);
}

// ══════════════════════════════════════════════════════════════════════════
//  _showComboNumbers
// ══════════════════════════════════════════════════════════════════════════
function _showComboNumbers(combo, pixelPart1, pixelPart2)
{
	var comboStr = Std.string(combo);
	var separatedScore = [];

	for (i in 0...comboStr.length)
		separatedScore.push(Std.parseInt(comboStr.charAt(i)));

	var daLoop = 0;
	for (i in separatedScore)
	{
		var numScore = _getFromPool(numberPool);
		numScore.alpha = 1;
		numScore.visible = true;
		numScore.loadGraphic(Paths.getGraphic('UI/' + pixelPart1 + 'nums/num' + Std.int(i) + pixelPart2));

		numScore.x = FlxG.width * 0.55 + (43 * daLoop) - 90 + 140 + posX;
		numScore.y = FlxG.height * 0.5 + 20 + posY;

		if (!isPixel)
		{
			numScore.antialiasing = SaveData.data.antialiasing;
			numScore.setGraphicSize(Std.int(numScore.width * 0.35));
		}
		else
		{
			numScore.setGraphicSize(Std.int(numScore.width * 5.4));
		}
		numScore.updateHitbox();

		FlxTween.tween(numScore, {"scale.x": numScore.scale.x * 1.15, "scale.y": numScore.scale.y * 1.15}, 0.07, {
			ease: FlxEase.quadOut,
			onComplete: function(_)
			{
				FlxTween.tween(numScore, {"scale.x": numScore.scale.x / 1.15, "scale.y": numScore.scale.y / 1.15}, 0.10, {
					ease: FlxEase.quadIn
				});
			}
		});
		FlxTween.tween(numScore, {alpha: 0}, 0.20, {
			startDelay: 0.45,
			ease: FlxEase.quadIn,
			onComplete: function(_)
			{
				numScore.kill();
			}
		});
		daLoop++;
	}
}

// ══════════════════════════════════════════════════════════════════════════
//  onMissPopup  ─ replica showMissPopup()
// The original creates a fresh sprite and destroys it upon completion (without a pool).
// We replicate that exact behavior with uiAdd / uiRemove / destroy.
// ═════════════════════════════════════ ═════════════════════════════════════
// onMissPopup ─ use pool to avoid alloc/destroy on every miss
// ══════════════════════════════════════════════════════════════════════════
function onMissPopup()
{
	_killPoolInstant(missPool);

	var rating = _getFromPool(missPool);
	rating.alpha = 1;
	rating.visible = true;

	if (isPixel)
		rating.loadGraphic(Paths.getGraphic('UI/pixelUI/score/miss-pixel'));
	else
		rating.loadGraphic(Paths.getGraphic('UI/normal/score/miss'));

	rating.x = FlxG.width * 0.55 - 40 + posX;
	rating.y = FlxG.height * 0.5 - 90 + posY;

	if (!isPixel)
	{
		rating.setGraphicSize(Std.int(rating.width * 0.7));
		rating.antialiasing = SaveData.data.antialiasing;
	}
	else
	{
		rating.setGraphicSize(Std.int(rating.width * PIXEL_ZOOM * 0.7));
		rating.antialiasing = false;
	}
	rating.updateHitbox();

	// Bump appears
	FlxTween.tween(rating, {"scale.x": rating.scale.x * 1.15, "scale.y": rating.scale.y * 1.15}, 0.07, {
		ease: FlxEase.quadOut,
		onComplete: function(_)
		{
			FlxTween.tween(rating, {"scale.x": rating.scale.x / 1.15, "scale.y": rating.scale.y / 1.15}, 0.10, {
				ease: FlxEase.quadIn
			});
		}
	});
	FlxTween.tween(rating, {alpha: 0}, 0.20, {
		startDelay: 0.45,
		ease: FlxEase.quadIn,
		onComplete: function(_)
		{
			rating.kill();
		}
	});
}

// ══════════════════════════════════════════════════════════════════════════
//  onIconsSet
// ══════════════════════════════════════════════════════════════════════════
function onIconsSet(p1, p2)
{
	iconP1Name = p1;
	iconP2Name = p2;
	if (iconP1 != null)
		iconP1.updateIcon(p1, true);
	if (iconP2 != null)
		iconP2.updateIcon(p2, false);
}

// ══════════════════════════════════════════════════════════════════════════
//  onDestroy
// ══════════════════════════════════════════════════════════════════════════
function onDestroy()
{
	ratingPool = [];
	comboPool = [];
	numberPool = [];
	missPool = [];
}

function _killPoolInstant(pool)
{
	for (sprite in pool)
	{
		if (sprite.exists && sprite.alive)
		{
			FlxTween.cancelTweensOf(sprite);
			FlxTween.cancelTweensOf(sprite.scale);
			sprite.alpha = 0;
			sprite.kill();
		}
	}
}

function _getFromPool(pool)
{
	for (sprite in pool)
	{
		if (!sprite.exists)
		{
			sprite.revive();
			return sprite;
		}
	}

	var newSprite = makeSprite();
	pool.push(newSprite);
	uiAdd(newSprite);
	return newSprite;
}