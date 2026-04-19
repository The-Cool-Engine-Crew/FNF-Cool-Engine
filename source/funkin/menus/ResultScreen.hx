package funkin.menus;

import flixel.addons.display.FlxBackdrop;
import flixel.effects.FlxFlicker;
import flixel.text.FlxText;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.group.FlxSpriteGroup;
import flixel.effects.particles.FlxEmitter;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxGradient;
import flixel.util.FlxTimer;
import flixel.math.FlxMath;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxSubState;
import haxe.Json;
import funkin.gameplay.PlayState;
import funkin.gameplay.GameState;
import funkin.scripting.StateScriptHandler;
import funkin.transitions.StateTransition;
import funkin.transitions.StickerTransition;
import funkin.states.LoadingState;
import funkin.data.SaveData;

using StringTools;

/**
 * ResultScreen v4 — V-Slice inspired result screen.
 *
 * ─── Layout ───────────────────────────────────────────────────────────────────
 *
 *  ┌──────────────── BLACK TOP BAR (slides down) ──────────────────────────────┐
 *  │  [SONG TITLE scrolling] ··· [DIFFICULTY] ··· [XX%]                        │
 *  └────────────────────────────────────────────────────────────────────────────┘
 *  │                                                   │
 *  │  SCORE (digit-shuffle anim)                       │  RANK  (drops in)      │
 *  │  ──────────────────────────                       │  [FC badge if FC]       │
 *  │  Sicks   ████████████  N                          │                         │
 *  │  Goods   ████████      N                          │  BF character           │
 *  │  Bads    ██            N                          │  (animates in)          │
 *  │  Shits   █             N                          │                         │
 *  │  Misses  ██            N                          │                         │
 *  │  MaxCombo              N                          │                         │
 *  │                                                   │                         │
 *  └──────────── [ENTER] Continue • [R] Retry ────────────────────────────────┘
 *
 * ─── Rank backdrop ─────────────────────────────────────────────────────────────
 *  After rank lands: vertical scrolling rank text + horizontal rows (like V-Slice)
 *
 * ─── Sequence timeline ─────────────────────────────────────────────────────────
 *   0.0s  bg / gradient fade in
 *   0.3s  BF slides in from left
 *   0.5s  black top bar drops down
 *   0.8s  song title + difficulty + %small slide in from top
 *   0.9s  score popin anim plays, digits start shuffling
 *   1.2s  tally rows appear one by one (staggered 0.09s each)
 *         each row: label slides in + counter animates to target value
 *   2.0s  % counter big animates from near-target to target
 *   2.8s  rank sprite drops in with elastic bounce
 *   3.0s  rank lands → camera shake + flash + backdrop scrolling starts
 *   3.1s  FC badge fades in (if full combo)
 *   3.5s  canExit = true
 *
 * ─── Rank config (ranking_config.json) ────────────────────────────────────────
 * Same format as v3 — fully backwards compatible.
 *
 * ─── Script hooks ──────────────────────────────────────────────────────────────
 *   onCreate / postCreate / onDestroy
 *   onRankConfigLoaded(config)
 *   onBackgroundsCreate(bg, gradient, pattern)
 *   onTopBarCreate(bar)
 *   onSongTitleCreate(titleText, diffText, pctText)
 *   onScoreCreate(scoreGroup)
 *   onTallyCreate(tallyGroup)
 *   onRankCreate(rankSprite)
 *   onRankLanded(rankSprite, rankKey)         ← camera shake happens here
 *   onFCBadgeCreate(fcBadge)
 *   onBFCreate(bf)
 *   onAccuracyCreate(bigPct, ratingText)
 *   onBackdropCreate(vertBackdrop, horzBackdrops)
 *   onParticlesCreate(particles, confetti)
 *   onIntroStart()
 *   onCanExitChange(canExit)
 *   onBeatHit(beat)
 *   onExit(retry)        → return true to cancel default
 *   onExitComplete(retry)
 *   getCustomRank(accuracy)         → return String to override rank
 *   getSongDisplayName(song, diff)  → return String to override title
 *   getRatingText(accuracy)         → return String
 *   getRatingColor(accuracy)        → return Int (FlxColor)
 *   getCustomBgColor(rankKey)       → return Int
 *   getRankMusic(rankKey)           → return String (music key)
 *   getHelpText()                   → return String
 *   getBFCharacter()                → return String (char id)
 *   getCustomStats()                → return Array<{label, value, color}>
 */
class ResultScreen extends funkin.states.MusicBeatSubstate {
	// ─── Visual elements ──────────────────────────────────────────────────────
	public var bg:FlxSprite;
	public var bgGradient:FlxSprite;
	public var bgPattern:FlxSprite;
	public var topBar:FlxSprite;
	public var songTitleText:FlxText;
	public var difficultyText:FlxText;
	public var pctSmallText:FlxText;
	public var bf:funkin.gameplay.objects.character.Character;
	public var rankSprite:FlxSprite;
	public var fcBadge:FlxSprite;
	public var scoreGroup:FlxTypedGroup<FlxText>;
	public var tallyGroup:FlxTypedGroup<FlxSprite>;
	public var bigPctText:FlxText;
	public var ratingText:FlxText;
	public var glowOverlay:FlxSprite;
	public var particles:FlxEmitter;
	public var confetti:FlxEmitter;
	public var helpText:FlxText;
	public var highscoreNew:FlxSprite;

	// Tally counter rows (label + bar + number)
	var _tallyRows:Array<TallyRow> = [];

	// Backdrop scrollers (rank text)
	var _vertBackdrop:FlxBackdrop;
	var _horzBackdrops:Array<FlxBackdrop> = [];

	// Score digit display
	var _scoreDigits:ScoreDigitGroup;

	// Big percent counter (animates from start to target)
	var _pctStart:Float = 0;
	var _pctTarget:Float = 0;
	var _pctCurrent:Float = 0;
	var _pctAnimating:Bool = false;

	// State
	public var canExit:Bool = false;
	public var isExiting:Bool = false;
	public var currentRank:String = 'B';
	public var rankConfig:RankConfig;

	// Beat tracking
	var _lastBeat:Int = -1;
	var _pulseSprites:Array<FlxSprite> = [];

	// Song title scroll
	var _titleScrolling:Bool = false;
	var _titleScrollSpeed:Float = -1.5; // px/frame at 60fps, set by angle calc

	public var currentRankEntry(get, never):Null<RankEntry>;

	function get_currentRankEntry():Null<RankEntry> {
		if (rankConfig == null)
			return null;
		for (r in rankConfig.ranks)
			if (r.key == currentRank)
				return r;
		return null;
	}

	// ─── Lifecycle ────────────────────────────────────────────────────────────

	override public function create():Void {
		StateScriptHandler.init();
		StateScriptHandler.loadStateScripts('ResultScreen', this);
		StateScriptHandler.callOnScripts('onCreate', []);

		super.create();

		#if mobileC
		addTouchMenuControls(true, false);
		#end

		rankConfig = RankConfig.load(_songId());
		StateScriptHandler.callOnScripts('onRankConfigLoaded', [rankConfig]);

		currentRank = _generateRank();
		_exposeData();

		// Build in sequence order (painter's algo)
		_buildBg();
		_buildParticles();
		_buildGlowOverlay();
		_buildTopBar();
		_buildBF();
		_buildRankDisplay();
		_buildScoreDisplay();
		_buildTallyRows();
		_buildBigAccuracy();
		_buildHelpText();
		_buildHighscoreNew();

		_startIntroSequence();

		#if HSCRIPT_ALLOWED
		StateScriptHandler.refreshStateFields(this);
		StateScriptHandler.callOnScripts('postCreate', []);
		#end
		
		StateTransition.onStateCreated();
	}

	override function update(elapsed:Float):Void {
		StateScriptHandler.callOnScripts('onUpdate', [elapsed]);
		super.update(elapsed);

		// Beat detection
		if (FlxG.sound.music != null && FlxG.sound.music.playing) {
			var bpm = (rankConfig != null && rankConfig.bpm > 0) ? rankConfig.bpm : 120.0;
			var beatLen = (60.0 / bpm) * 1000.0;
			var curBeat = Math.floor(FlxG.sound.music.time / beatLen);
			if (curBeat != _lastBeat) {
				_lastBeat = curBeat;
				_onBeat(curBeat);
			}
		}

		// Slowly rotate bg pattern
		if (bgPattern != null)
			bgPattern.angle += elapsed * 1.5;

		// Scroll song title
		if (_titleScrolling && songTitleText != null) {
			songTitleText.x += _titleScrollSpeed * 60 * elapsed;
			if (difficultyText != null)
				difficultyText.x += _titleScrollSpeed * 60 * elapsed;
			if (pctSmallText != null)
				pctSmallText.x += _titleScrollSpeed * 60 * elapsed;

			// Wrap: when title goes fully off the left, reset to the right
			if (songTitleText.x + songTitleText.width < -50)
				_resetTitleScroll();
		}

		// Animate big pct counter
		if (_pctAnimating && bigPctText != null) {
			// driven by tween callback, nothing needed here
		}

		// Input
		var enter = FlxG.keys.justPressed.ENTER || FlxG.keys.justPressed.SPACE;
		var retry = FlxG.keys.justPressed.R;

		#if mobile
		for (t in FlxG.touches.list)
			if (t.justPressed)
				enter = true;
		#end

		if (enter && canExit && !isExiting)
			_exit(false);
		if (retry && canExit && !isExiting)
			_exit(true);

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onUpdatePost', [elapsed]);
		#end
	}

	override function destroy():Void {
		StateScriptHandler.callOnScripts('onDestroy', []);
		StateScriptHandler.clearStateScripts();

		// FIX Bug 2: ResultScreen creates 9 makeGraphic() sprites including two
		// full-screen ones (1280×720 = ~3.5 MB each). Without explicit destroy()
		// calls here the BitmapData backing those sprites is not released until
		// the next postStateSwitch, leaving 5-8 MB stranded in RAM per cycle.
		if (bg != null)          { bg.destroy();          bg = null; }
		if (glowOverlay != null) { glowOverlay.destroy();  glowOverlay = null; }
		if (topBar != null)      { topBar.destroy();       topBar = null; }

		// Prune any atlases whose FlxGraphic was destroyed above so they don't
		// sit as zombie entries until the next postStateSwitch cleanup.
		try { Paths.pruneAtlasCache(); } catch (_:Dynamic) {}

		// Liberar el singleton de GameState ahora que ya mostramos las stats.
		// PlayState dejó de hacerlo en su propio destroy() para que este
		// estado pueda leer los valores correctos en create().
		GameState.destroy();
		super.destroy();
	}

	// ─── Background ──────────────────────────────────────────────────────────

	function _buildBg():Void {
		bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, _getBgColor());
		bg.scrollFactor.set(0, 0); // sin parallax para evitar bordes negros
		bg.alpha = 0;

		// Intentar superponer textura opcional si el archivo existe
		final _bgKey = 'images/menu/menuBGBlue.png';
		var _bgLoaded = false;
		#if sys
		if (sys.FileSystem.exists('assets/' + _bgKey) || openfl.Assets.exists('assets/' + _bgKey))
		#else
		if (openfl.Assets.exists(Paths.image('menu/menuBGBlue')))
		#end
		{
			try {
				bg.loadGraphic(Paths.image('menu/menuBGBlue'));
				// Forzar a tamaño de pantalla — loadGraphic cambia dimensiones
				// al tamaño de la imagen, que puede no coincidir con la pantalla.
				bg.setGraphicSize(FlxG.width, FlxG.height);
				bg.updateHitbox();
				bg.color = _getBgColor();
				_bgLoaded = true;
			} catch (_) {
				// Falló la carga — volver al solid color seguro
				bg.makeGraphic(FlxG.width, FlxG.height, _getBgColor());
			}
		}

		add(bg);

		// Dark gradient overlay
		bgGradient = FlxGradient.createGradientFlxSprite(FlxG.width, FlxG.height, [FlxColor.TRANSPARENT, 0x14000000], 90);
		bgGradient.alpha = 0;
		bgGradient.scrollFactor.set(0, 0);
		add(bgGradient);

		// Optional pattern overlay (multiply blend)
		bgPattern = new FlxSprite();
		final _patKey = 'images/menu/blackslines_finalrating.png';
		var _patLoaded = false;
		#if sys
		if (sys.FileSystem.exists('assets/' + _patKey) || openfl.Assets.exists('assets/' + _patKey))
		#else
		if (openfl.Assets.exists(Paths.image('menu/blackslines_finalrating')))
		#end
		{
			try {
				bgPattern.loadGraphic(Paths.image('menu/blackslines_finalrating'));
				bgPattern.blend = MULTIPLY;
				bgPattern.setGraphicSize(FlxG.width + 200, FlxG.height + 200);
				bgPattern.updateHitbox();
				bgPattern.screenCenter();
				_patLoaded = true;
			} catch (_) {}
		}
		if (!_patLoaded)
			bgPattern.makeGraphic(1, 1, FlxColor.TRANSPARENT);
		bgPattern.alpha = 0;
		bgPattern.scrollFactor.set(0, 0);
		add(bgPattern);

		StateScriptHandler.exposeAll(['bg' => bg, 'bgGradient' => bgGradient, 'bgPattern' => bgPattern]);
		StateScriptHandler.callOnScripts('onBackgroundsCreate', [bg, bgGradient, bgPattern]);
	}

	// ─── Particles ───────────────────────────────────────────────────────────

	function _buildParticles():Void {
		particles = new FlxEmitter(FlxG.width / 2, FlxG.height + 20, 120);
		particles.makeParticles(5, 5, FlxColor.WHITE, 120);
		particles.launchMode = FlxEmitterMode.SQUARE;
		particles.velocity.set(-80, -300, 80, -500);
		particles.lifespan.set(3, 7);
		particles.alpha.set(0.4, 0.7, 0, 0);
		particles.scale.set(0.8, 1.8, 0.1, 0.4);
		particles.width = FlxG.width;
		particles.height = 1;
		add(particles);

		var doConfetti = _shouldDoConfetti();
		if (doConfetti) {
			confetti = new FlxEmitter(FlxG.width / 2, -60, 200);
			confetti.makeParticles(7, 7, FlxColor.WHITE, 200);
			confetti.launchMode = FlxEmitterMode.SQUARE;
			confetti.velocity.set(-180, 80, 180, 320);
			confetti.angularVelocity.set(-200, 200);
			confetti.lifespan.set(3, 8);
			confetti.alpha.set(0.85, 1, 0, 0);
			confetti.width = FlxG.width;
			add(confetti);
		}

		StateScriptHandler.exposeAll(['particles' => particles, 'confetti' => confetti]);
		StateScriptHandler.callOnScripts('onParticlesCreate', [particles, confetti]);
	}

	// ─── Glow overlay ────────────────────────────────────────────────────────

	function _buildGlowOverlay():Void {
		glowOverlay = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.WHITE);
		glowOverlay.alpha = 0;
		glowOverlay.blend = ADD;
		add(glowOverlay);
		StateScriptHandler.exposeElement('glowOverlay', glowOverlay);
	}

	// ─── Top bar + song title ─────────────────────────────────────────────────

	function _buildTopBar():Void {
		// Black bar — same idea as V-Slice blackTopBar
		topBar = new FlxSprite().makeGraphic(FlxG.width, 72, 0xFF000000);
		topBar.y = -topBar.height;
		topBar.scrollFactor.set(0, 0);
		add(topBar);

		// Song title (scrolls once intro timer fires)
		var displayName = StateScriptHandler.callOnScriptsReturn('getSongDisplayName', [PlayState.SONG?.song ?? '', funkin.data.CoolUtil.difficultyString()],
			(PlayState.SONG?.song ?? 'Unknown').toUpperCase());

		songTitleText = new FlxText(FlxG.width + 20, 14, 0, displayName, 28);
		songTitleText.setFormat(Paths.font('vcr.ttf'), 28, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		songTitleText.borderSize = 3;
		songTitleText.scrollFactor.set(0, 0);
		songTitleText.alpha = 0;
		add(songTitleText);

		// Difficulty label
		var diffStr = funkin.data.CoolUtil.difficultyString();
		difficultyText = new FlxText(FlxG.width + 20, 14, 0, '  [ ' + diffStr + ' ]', 20);
		difficultyText.setFormat(Paths.font('vcr.ttf'), 20, FlxColor.fromRGB(180, 180, 255), LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		difficultyText.borderSize = 2;
		difficultyText.scrollFactor.set(0, 0);
		difficultyText.alpha = 0;
		add(difficultyText);

		// Accuracy small (top-right)
		var pctVal = Std.int(GameState.get().accuracy);
		pctSmallText = new FlxText(FlxG.width + 20, 12, 0, pctVal + '%', 24);
		pctSmallText.setFormat(Paths.font('vcr.ttf'), 24, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		pctSmallText.borderSize = 2;
		pctSmallText.scrollFactor.set(0, 0);
		pctSmallText.alpha = 0;
		add(pctSmallText);

		StateScriptHandler.exposeAll([
			'topBar' => topBar,
			'songTitleText' => songTitleText,
			'difficultyText' => difficultyText,
			'pctSmallText' => pctSmallText
		]);
		StateScriptHandler.callOnScripts('onTopBarCreate', [topBar]);
		StateScriptHandler.callOnScripts('onSongTitleCreate', [songTitleText, difficultyText, pctSmallText]);
	}

	// ─── BF character ─────────────────────────────────────────────────────────

	function _buildBF():Void {
		var charId:String = StateScriptHandler.callOnScriptsReturn('getBFCharacter', [], PlayState.SONG?.player1 ?? 'bf') ?? 'bf';

		bf = new funkin.gameplay.objects.character.Character(-220, FlxG.height * 0.28, charId);
		bf.scrollFactor.set(0, 0);
		// add(bf);

		_pulseSprites.push(bf);
		StateScriptHandler.exposeElement('bf', bf);
		StateScriptHandler.callOnScripts('onBFCreate', [bf]);
	}

	// ─── Rank sprite + FC badge ───────────────────────────────────────────────

	function _buildRankDisplay():Void {
		rankSprite = new FlxSprite();
		try {
			rankSprite.loadGraphic(Paths.image('menu/ratings/' + currentRank));
		} catch (_) {
			rankSprite.makeGraphic(120, 120, FlxColor.YELLOW);
		}
		rankSprite.scale.set(1.6, 1.6);
		rankSprite.antialiasing = (SaveData.data?.antialiasing ?? true);
		rankSprite.updateHitbox();
		rankSprite.screenCenter(X);
		rankSprite.x += 360;
		rankSprite.y = -rankSprite.height - 100;
		rankSprite.scrollFactor.set(0, 0);
		rankSprite.alpha = 0;
		add(rankSprite);
		_pulseSprites.push(rankSprite);

		if (GameState.get().misses == 0) {
			fcBadge = new FlxSprite();
			try {
				fcBadge.loadGraphic(Paths.image('menu/ratings/FC'));
			} catch (_) {
				fcBadge.makeGraphic(60, 60, FlxColor.WHITE);
			}
			fcBadge.scale.set(1.1, 1.1);
			fcBadge.updateHitbox();
			fcBadge.x = rankSprite.x - 80;
			fcBadge.y = rankSprite.y + 220;
			fcBadge.scrollFactor.set(0, 0);
			fcBadge.alpha = 0;
			add(fcBadge);
			_pulseSprites.push(fcBadge);
			StateScriptHandler.exposeElement('fcBadge', fcBadge);
			StateScriptHandler.callOnScripts('onFCBadgeCreate', [fcBadge]);
		}

		StateScriptHandler.exposeElement('rankSprite', rankSprite);
		StateScriptHandler.callOnScripts('onRankCreate', [rankSprite]);
	}

	// ─── Score digits ─────────────────────────────────────────────────────────

	function _buildScoreDisplay():Void {
		scoreGroup = new FlxTypedGroup<FlxText>();
		add(scoreGroup);

		_scoreDigits = new ScoreDigitGroup(48, 90, GameState.get().score);
		_scoreDigits.alpha = 0;
		_scoreDigits.scrollFactor.set(0, 0);
		add(_scoreDigits);

		var scoreLabel = new FlxText(48, 68, 200, 'SCORE', 18);
		scoreLabel.setFormat(Paths.font('vcr.ttf'), 18, FlxColor.fromRGB(180, 180, 180), LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		scoreLabel.borderSize = 2;
		scoreLabel.alpha = 0;
		scoreLabel.scrollFactor.set(0, 0);
		scoreGroup.add(scoreLabel);

		StateScriptHandler.exposeAll(['scoreGroup' => scoreGroup, 'scoreDigits' => _scoreDigits]);
		StateScriptHandler.callOnScripts('onScoreCreate', [scoreGroup]);
	}

	// ─── Tally rows ───────────────────────────────────────────────────────────

	function _buildTallyRows():Void {
		tallyGroup = new FlxTypedGroup<FlxSprite>();
		add(tallyGroup);

		var gs = GameState.get();
		var total:Int = gs.sicks + gs.goods + gs.bads + gs.shits + gs.misses;
		if (total <= 0)
			total = 1;

		var rowDefs:Array<Dynamic> = [
			{
				label: 'SICKS',
				value: gs.sicks,
				color: FlxColor.fromRGB(80, 255, 140),
				barColor: FlxColor.fromRGB(80, 255, 140)
			},
			{
				label: 'GOODS',
				value: gs.goods,
				color: FlxColor.fromRGB(80, 200, 255),
				barColor: FlxColor.fromRGB(80, 200, 255)
			},
			{
				label: 'BADS',
				value: gs.bads,
				color: FlxColor.fromRGB(255, 200, 80),
				barColor: FlxColor.fromRGB(255, 200, 80)
			},
			{
				label: 'SHITS',
				value: gs.shits,
				color: FlxColor.fromRGB(180, 100, 40),
				barColor: FlxColor.fromRGB(180, 100, 40)
			},
			{
				label: 'MISSES',
				value: gs.misses,
				color: FlxColor.fromRGB(255, 70, 70),
				barColor: FlxColor.fromRGB(255, 70, 70)
			},
			{
				label: 'COMBO',
				value: gs.maxCombo,
				color: FlxColor.fromRGB(200, 200, 255),
				barColor: FlxColor.fromRGB(200, 200, 255)
			},
		];

		// Custom stats from scripts
		var customStats:Array<Dynamic> = StateScriptHandler.collectArrays('getCustomStats');
		for (cs in customStats)
			rowDefs.push(cs);

		final startX:Float = 48;
		final startY:Float = 170;
		final rowH:Float = 50;

		for (i in 0...rowDefs.length) {
			var def = rowDefs[i];
			var row = new TallyRow(startX, startY + i * rowH, def.label, def.value, def.color, def.value / total, def.barColor);
			row.alpha = 0;
			row.scrollFactor.set(0, 0);
			tallyGroup.add(row);
			_tallyRows.push(row);
		}

		StateScriptHandler.exposeElement('tallyGroup', tallyGroup);
		StateScriptHandler.callOnScripts('onTallyCreate', [tallyGroup]);
	}

	// ─── Big accuracy + rating text ───────────────────────────────────────────

	function _buildBigAccuracy():Void {
		_pctTarget = GameState.get().accuracy;
		_pctStart = Math.max(0, _pctTarget - 30);
		_pctCurrent = _pctStart;

		bigPctText = new FlxText(0, FlxG.height + 60, FlxG.width, Std.int(_pctCurrent) + '%', 80);
		bigPctText.setFormat(Paths.font('vcr.ttf'), 80, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		bigPctText.borderSize = 5;
		bigPctText.alpha = 0;
		bigPctText.scrollFactor.set(0, 0);
		add(bigPctText);
		_pulseSprites.push(cast bigPctText);

		var ratingTxt = _getRatingText(GameState.get().accuracy);
		var ratingClr = _getRatingColor(GameState.get().accuracy);
		ratingText = new FlxText(0, FlxG.height + 150, FlxG.width, ratingTxt, 32);
		ratingText.setFormat(Paths.font('vcr.ttf'), 32, ratingClr, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		ratingText.borderSize = 2;
		ratingText.alpha = 0;
		ratingText.scrollFactor.set(0, 0);
		add(ratingText);

		StateScriptHandler.exposeAll(['bigPctText' => bigPctText, 'ratingText' => ratingText]);
		StateScriptHandler.callOnScripts('onAccuracyCreate', [bigPctText, ratingText]);
	}

	// ─── Highscore badge ─────────────────────────────────────────────────────

	/**
	 * Shows the "NEW HIGHSCORE" Sparrow anim when the player beats their best.
	 * Asset: assets/images/resultScreen/highscoreNew.png + .xml
	 * Animation prefix: "highscoreAnim0" (frames 0000-0028, 24fps)
	 * After the intro plays it loops from frame 16 (the color-cycling idle).
	 */
	function _buildHighscoreNew():Void {
		if (!GameState.get().isNewHighscore)
			return;

		highscoreNew = new FlxSprite();
		try {
			highscoreNew.frames = Paths.getSparrowAtlas('menu/resultScreen/highscoreNew');
			highscoreNew.animation.addByPrefix('new', 'highscoreAnim0', 24, false);
			// Once the intro finishes, loop from frame 16 (color cycle idle)
			highscoreNew.animation.onFinish.add(function(_) {
				if (highscoreNew != null && highscoreNew.animation.exists('new'))
					highscoreNew.animation.play('new', true, false, 16);
			});
		} catch (_) {
			// Asset not found — skip silently
			highscoreNew = null;
			return;
		}

		// Position: top-left, just below the top bar, near the score
		highscoreNew.x = -210;
		highscoreNew.y = -350; // starts off-screen above
		highscoreNew.alpha = 0;
		highscoreNew.scrollFactor.set(0, 0);
		highscoreNew.antialiasing = (SaveData.data?.antialiasing ?? true);
		add(highscoreNew);

		StateScriptHandler.exposeElement('highscoreNew', highscoreNew);
		StateScriptHandler.callOnScripts('onHighscoreNewCreate', [highscoreNew]);
	}

	// ─── Help text ────────────────────────────────────────────────────────────

	function _buildHelpText():Void {
		var helpMsg:String = StateScriptHandler.callOnScriptsReturn('getHelpText', [], '[ENTER] Continue   [R] Retry');
		helpText = new FlxText(0, FlxG.height - 46, FlxG.width, helpMsg, 22);
		helpText.setFormat(Paths.font('vcr.ttf'), 22, 0xAAFFFFFF, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		helpText.borderSize = 2;
		helpText.alpha = 0;
		helpText.scrollFactor.set(0, 0);
		add(helpText);
		StateScriptHandler.exposeElement('helpText', helpText);
	}

	// ─── Intro sequence ───────────────────────────────────────────────────────

	function _startIntroSequence():Void {
		FlxG.camera.fade(FlxColor.BLACK, 0.9, true);

		// Step 0: bg fades in immediately
		FlxTween.tween(bg, {alpha: 1.0}, 1.0, {ease: FlxEase.quadOut});
		FlxTween.tween(bgGradient, {alpha: 0.85}, 1.3, {ease: FlxEase.quadOut});
		FlxTween.tween(bgPattern, {alpha: 0.20}, 1.8, {ease: FlxEase.quadOut});

		// Step 1 (0.3s): BF slides in
		new FlxTimer().start(0.3, function(_) {
			FlxTween.tween(bf, {x: 60}, 0.9, {ease: FlxEase.expoOut});
		});

		// Step 2 (0.5s): Top bar drops down
		new FlxTimer().start(0.5, function(_) {
			FlxTween.tween(topBar, {y: 0}, 7 / 24, {ease: FlxEase.quartOut});
		});

		// Step 3 (0.8s): Song title + diff slide in from top, then start scrolling
		new FlxTimer().start(0.8, function(_) {
			// Place elements relative to bar
			_resetTitleScroll();

			songTitleText.alpha = 1;
			difficultyText.alpha = 1;
			pctSmallText.alpha = 1;

			// Start scroll after a brief pause
			new FlxTimer().start(2.5, function(_) {
				_titleScrolling = true;
			});
		});

		// Step 4 (0.9s): Score label + digits
		new FlxTimer().start(0.9, function(_) {
			for (txt in scoreGroup)
				FlxTween.tween(txt, {alpha: 1}, 0.4, {ease: FlxEase.quadOut});
			FlxTween.tween(_scoreDigits, {alpha: 1}, 0.4, {
				ease: FlxEase.quadOut,
				onComplete: function(_) {
					_scoreDigits.animateIn();
				}
			});
		});

		// Step 5 (1.2s): Tally rows staggered
		for (i in 0..._tallyRows.length) {
			var row = _tallyRows[i];
			new FlxTimer().start(1.2 + i * 0.09, function(_) {
				FlxTween.tween(row, {alpha: 1, x: row.x + 0}, 0.35, {ease: FlxEase.backOut});
				row.x -= 60;
				new FlxTimer().start(0.15, function(_) {
					row.animateCounter();
				});
			});
		}

		// Step 6 (2.0s): Big % counter
		new FlxTimer().start(2.0, function(_) {
			FlxTween.tween(bigPctText, {y: FlxG.height - 190, alpha: 1}, 0.7, {ease: FlxEase.backOut});
			FlxTween.tween(ratingText, {y: FlxG.height - 108, alpha: 1}, 0.7, {ease: FlxEase.backOut, startDelay: 0.08});

			_pctAnimating = true;
			FlxTween.num(_pctStart, _pctTarget, 1.6, {
				ease: FlxEase.quartOut,
				onUpdate: function(t:FlxTween) {
					if (bigPctText == null)
						return;
					bigPctText.text = Std.int(_pctCurrent) + '%';
				}
			}, function(v:Float) {
				_pctCurrent = v;
			});
		});

		// Step 7 (2.8s): Rank drops in
		new FlxTimer().start(2.8, function(_) {

			FlxG.sound.play(Paths.sound('menus/confirmMenu'));

			var targetY:Float = (currentRank == 'SS' || currentRank == 'S') ? 90 : 130;
			FlxTween.tween(rankSprite, {y: targetY, alpha: 1}, 0.75, {
				ease: FlxEase.elasticOut,
				onComplete: function(_) {
					// Rank landed
					var shakeAmt = (currentRankEntry?.camShake ?? 0.01);
					FlxG.camera.shake(shakeAmt, 0.3);
					glowOverlay.alpha = 0.45;
					FlxTween.tween(glowOverlay, {alpha: 0}, 0.55);
					FlxFlicker.flicker(rankSprite, 0.5, 1 / 24, true);
					if (confetti != null)
						confetti.start(false, 0.04, 0);
					particles.start(false, 0.06, 0);
					_buildRankBackdrop();
					StateScriptHandler.callOnScripts('onRankLanded', [rankSprite, currentRank]);
				}
			});
		});

		// Step 8 (3.1s): FC badge
		if (fcBadge != null) {
			new FlxTimer().start(3.1, function(_) {
				fcBadge.x = rankSprite.x - 80;
				fcBadge.y = rankSprite.y + rankSprite.height * rankSprite.scale.y + 8;
				FlxTween.tween(fcBadge, {alpha: 1}, 0.5, {ease: FlxEase.quadOut});
			});
		}

		// Step 9 (3.5s): canExit, help text
		new FlxTimer().start(3.5, function(_) {
			canExit = true;
			FlxTween.tween(helpText, {alpha: 0.85}, 0.4, {ease: FlxEase.quadOut});
			StateScriptHandler.callOnScripts('onCanExitChange', [true]);
		});

		// Highscore badge (3.2s): drops in from top after rank lands
		if (highscoreNew != null) {
			new FlxTimer().start(3.2, function(_) {
				if (highscoreNew == null)
					return;
				highscoreNew.y = -highscoreNew.height - 520;
				highscoreNew.alpha = 1;
				highscoreNew.animation.play('new', true);
				FlxTween.tween(highscoreNew, {y: 20}, 0.55, {ease: FlxEase.elasticOut});
			});
		}

		// Music
		_startMusic();

		StateScriptHandler.callOnScripts('onIntroStart', []);
	}

	// ─── Rank backdrop scrollers (V-Slice style) ──────────────────────────────

	function _buildRankBackdrop():Void {
		// BUGFIX: en cpp/desktop, FlxBackdrop con imagen inexistente loguea [ERROR]
		// sin lanzar excepción Haxe → try/catch NO ayuda. Verificar existencia primero.
		final _vertKey = 'images/menu/ratings/rankScrollVert_${currentRank}.png';
		final _horzKey = 'images/menu/ratings/rankScroll${currentRank}.png';

		#if sys
		final _vertExists = sys.FileSystem.exists('assets/' + _vertKey);
		final _horzExists = sys.FileSystem.exists('assets/' + _horzKey);
		#else
		final _vertExists = openfl.Assets.exists('assets/' + _vertKey);
		final _horzExists = openfl.Assets.exists('assets/' + _horzKey);
		#end

		// Vertical right-side scroller
		if (_vertExists) {
			try {
				_vertBackdrop = new FlxBackdrop(Paths.image('menu/ratings/rankScrollVert_' + currentRank), Y, 0, 20);
				_vertBackdrop.x = FlxG.width - 48;
				_vertBackdrop.y = 0;
				_vertBackdrop.alpha = 0;
				add(_vertBackdrop);

				FlxFlicker.flicker(_vertBackdrop, 6 / 24, 2 / 24, true);
				new FlxTimer().start(30 / 24, function(_) {
					_vertBackdrop.velocity.y = -70;
				});
			} catch (_) {}
		}

		// Horizontal rows (alternating scroll directions like V-Slice)
		_horzBackdrops = [];
		if (_horzExists) {
			for (row in 0...8) {
				try {
					var bk = new FlxBackdrop(Paths.image('menu/ratings/rankScroll' + currentRank), X, 12, 0);
					bk.x = -FlxG.width;
					bk.y = 90 + row * 62;
					bk.alpha = 0;
					add(bk);
					_horzBackdrops.push(bk);

					FlxFlicker.flicker(bk, 6 / 24, 2 / 24, true);
					var speed:Float = (row % 2 == 0) ? -6.0 : 6.0;
					new FlxTimer().start(24 / 24, function(_) {
						bk.velocity.x = speed;
					});
					FlxTween.tween(bk, {alpha: 0.55}, 0.25, {startDelay: row * 0.02});
				} catch (_) {}
			}
		}

		if (_vertBackdrop != null)
			FlxTween.tween(_vertBackdrop, {alpha: 0.7}, 0.3);

		StateScriptHandler.callOnScripts('onBackdropCreate', [_vertBackdrop, _horzBackdrops]);
	}

	// ─── Title scroll helpers ─────────────────────────────────────────────────

	function _resetTitleScroll():Void {
		// Lay out: [songTitle]  [diff]  [pct%] — all start just off right edge
		songTitleText.x = FlxG.width + 20;
		difficultyText.x = songTitleText.x + songTitleText.width + 12;
		pctSmallText.x = difficultyText.x + difficultyText.width + 12;
	}

	// ─── Music ────────────────────────────────────────────────────────────────

	function _startMusic():Void {
		var overrideKey:String = StateScriptHandler.callOnScriptsReturn('getRankMusic', [currentRank], null);
		var musicKey:String;

		if (overrideKey != null) {
			musicKey = overrideKey;
		} else {
			var entry = currentRankEntry;
			if (entry != null && entry.music != null && entry.music.length > 0)
				musicKey = entry.music;
			else
				musicKey = (currentRank == 'C' || currentRank == 'D' || currentRank == 'F') ? 'B' : currentRank;
		}

		try {
			FlxG.sound.playMusic(Paths.music('results$musicKey/results$musicKey'), 0);
			FlxTween.tween(FlxG.sound.music, {volume: 0.7}, 1.8, {ease: FlxEase.quadOut});
		} catch (_) {}
	}

	// ─── Beat pulse ───────────────────────────────────────────────────────────

	function _onBeat(beat:Int):Void {
		StateScriptHandler.callOnScripts('onBeatHit', [beat]);

		for (spr in _pulseSprites) {
			if (spr == null || !spr.alive)
				continue;
			FlxTween.cancelTweensOf(spr.scale);
			spr.scale.x *= 1.04;
			spr.scale.y *= 1.04;
			FlxTween.tween(spr.scale, {x: spr.scale.x / 1.04, y: spr.scale.y / 1.04}, 0.22, {ease: FlxEase.quadOut});
		}

		FlxG.camera.zoom = 1.012;
		FlxTween.tween(FlxG.camera, {zoom: 1.0}, 0.22, {ease: FlxEase.quadOut});
	}

	// ─── Exit ─────────────────────────────────────────────────────────────────

	function _exit(retry:Bool):Void {
		if (StateScriptHandler.callOnScripts('onExit', [retry]))
			return;

		isExiting = true;

		if (bf != null)
			try {
				bf.playAnim('hey', true);
			} catch (_) {}

		if (SaveData.data?.flashing ?? true)
			FlxG.camera.flash(FlxColor.WHITE, 0.4);
		FlxG.camera.shake(0.005, 0.25);

		if (FlxG.sound.music != null)
			FlxTween.tween(FlxG.sound.music, {volume: 0, pitch: 0.3}, 0.8, {ease: FlxEase.quadIn});

		// Outro tweens
		if (rankSprite != null)
			FlxTween.tween(rankSprite, {y: -200, alpha: 0}, 0.5, {ease: FlxEase.backIn});
		if (fcBadge != null)
			FlxTween.tween(fcBadge, {alpha: 0}, 0.3, {ease: FlxEase.quadIn});
		if (bf != null)
			FlxTween.tween(bf, {x: -300, alpha: 0}, 0.7, {ease: FlxEase.expoIn});
		if (bigPctText != null)
			FlxTween.tween(bigPctText, {y: FlxG.height + 100, alpha: 0}, 0.5, {ease: FlxEase.backIn});
		if (ratingText != null)
			FlxTween.tween(ratingText, {y: FlxG.height + 100, alpha: 0}, 0.5, {ease: FlxEase.backIn, startDelay: 0.04});
		if (topBar != null)
			FlxTween.tween(topBar, {y: -topBar.height}, 0.4, {ease: FlxEase.backIn});
		if (helpText != null)
			FlxTween.tween(helpText, {alpha: 0}, 0.3, {ease: FlxEase.quadIn});

		for (row in _tallyRows)
			FlxTween.tween(row, {x: row.x - 80, alpha: 0}, 0.4, {ease: FlxEase.quadIn, startDelay: _tallyRows.indexOf(row) * 0.03});

		FlxTween.tween(_scoreDigits, {alpha: 0, y: _scoreDigits.y - 40}, 0.4, {ease: FlxEase.quadIn});

		for (txt in scoreGroup)
			FlxTween.tween(txt, {alpha: 0}, 0.3, {ease: FlxEase.quadIn});

		FlxG.camera.fade(FlxColor.BLACK, 1.0, false);

		new FlxTimer().start(1.0, function(_) {
			if (FlxG.sound.music != null)
				FlxG.sound.music.stop();
			StateScriptHandler.callOnScripts('onExitComplete', [retry]);

			if (retry && PlayState.SONG?.song != null) {
				PlayState.startFromTime = null;
				FlxG.sound.play(Paths.sound('menus/confirmMenu'), 0.6);
				new FlxTimer().start(0.25, function(_) {
					funkin.system.CursorManager.hide();
					LoadingState.loadAndSwitchState(new PlayState());
				});
			} else {
				if (PlayState.isStoryMode)
					StateTransition.switchState(funkin.scripting.ScriptBridge.resolveState('StoryMenuState') ?? new funkin.menus.StoryMenuState());
				else
					StickerTransition.start(function() StateTransition.switchState(funkin.scripting.ScriptBridge.resolveState('FreeplayState') ?? new funkin.menus.FreeplayState()));
			}
		});
	}

	// ─── Rank generation ──────────────────────────────────────────────────────

	function _generateRank():String {
		var acc = GameState.get().accuracy;

		var scriptRank = StateScriptHandler.callOnScriptsReturn('getCustomRank', [acc], null);
		if (scriptRank != null)
			return scriptRank;

		if (rankConfig.naWhenZero && acc == 0 && GameState.get().misses == 0)
			return 'N/A';
		if (acc <= rankConfig.failAt)
			return 'F';

		var sorted = rankConfig.ranks.copy();
		sorted.sort(function(a, b) return b.minAccuracy > a.minAccuracy ? 1 : -1);
		for (entry in sorted)
			if (acc >= entry.minAccuracy)
				return entry.key;

		return 'F';
	}

	// ─── Rating text / color / bg color ──────────────────────────────────────

	function _getRatingText(acc:Float):String {
		var ov = StateScriptHandler.callOnScriptsReturn('getRatingText', [acc], null);
		if (ov != null)
			return ov;

		var e = currentRankEntry;
		if (e?.displayName != null && e.displayName.length > 0)
			return e.displayName;

		if (acc == 100)
			return 'PERFECT!!';
		if (acc >= 95)
			return 'AMAZING!';
		if (acc >= 90)
			return 'EXCELLENT!';
		if (acc >= 85)
			return 'GREAT!';
		if (acc >= 80)
			return 'GOOD!';
		if (acc >= 70)
			return 'NICE!';
		if (acc >= 60)
			return 'OK';
		return 'KEEP TRYING';
	}

	function _getRatingColor(acc:Float):Int {
		var ov = StateScriptHandler.callOnScriptsReturn('getRatingColor', [acc], null);
		if (ov != null)
			return ov;

		var e = currentRankEntry;
		if (e?.color != null && e.color.length > 0) {
			// BUGFIX: mismo error que _getBgColor — usar Std.parseInt con prefijo 0xFF
			var parsed = Std.parseInt('0xFF' + e.color.replace('#', '').replace('0x', '').replace('0X', ''));
			if (parsed != null)
				return parsed;
		}

		if (acc == 100)
			return FlxColor.fromRGB(255, 215, 0);
		if (acc >= 95)
			return FlxColor.fromRGB(100, 255, 100);
		if (acc >= 85)
			return FlxColor.CYAN;
		if (acc >= 70)
			return FlxColor.YELLOW;
		if (acc >= 60)
			return FlxColor.ORANGE;
		return FlxColor.RED;
	}

	function _getBgColor():Int {
		var ov = StateScriptHandler.callOnScriptsReturn('getCustomBgColor', [currentRank], null);
		if (ov != null)
			return ov;

		var e = currentRankEntry;
		if (e?.bgColor != null && e.bgColor.length > 0) {
			// BUGFIX: FlxColor.fromString('#0xFF${e.bgColor}') producía negro porque
			// el string '#0xFF112233' tiene un prefijo inválido — fromString lo parsea
			// como 9+ chars y falla, devolviendo null/0 (negro).
			// Correcto: pasar solo el valor hex con el prefijo 0xFF para opacidad total.
			var parsed = Std.parseInt('0xFF' + e.bgColor.replace('#', '').replace('0x', '').replace('0X', ''));
			if (parsed != null)
				return parsed;
		}

		return switch (currentRank) {
			case 'SS': FlxColor.fromRGB(255, 215, 0);
			case 'S': FlxColor.fromRGB(120, 255, 120);
			case 'A': FlxColor.fromRGB(80, 180, 255);
			case 'B': FlxColor.fromRGB(80, 120, 220);
			case 'C' | 'D': FlxColor.fromRGB(220, 140, 60);
			case 'F': FlxColor.fromRGB(180, 60, 60);
			default: FlxColor.fromRGB(100, 100, 200);
		};
	}

	function _shouldDoConfetti():Bool {
		var e = currentRankEntry;
		if (e != null && e.sparkles)
			return true;
		return currentRank == 'S' || currentRank == 'SS';
	}

	// ─── Helpers ─────────────────────────────────────────────────────────────

	function _songId():String
		return (PlayState.SONG?.song ?? '').toLowerCase();

	function _exposeData():Void {
		var gs = GameState.get();
		StateScriptHandler.exposeAll([
			'songScore' => gs.score,
			'accuracy' => gs.accuracy,
			'misses' => gs.misses,
			'sicks' => gs.sicks,
			'goods' => gs.goods,
			'bads' => gs.bads,
			'shits' => gs.shits,
			'maxCombo' => gs.maxCombo,
			'isStoryMode' => PlayState.isStoryMode,
			'songName' => PlayState.SONG?.song ?? '',
			'difficulty' => PlayState.storyDifficulty,
			'resultScreen' => this,
			'currentRank' => currentRank,
			'rankConfig' => rankConfig
		]);
	}
}

// =============================================================================
//  TallyRow — one stat row: label + animated counter + bar
// =============================================================================
class TallyRow extends FlxSpriteGroup {
	var _label:FlxText;
	var _counter:FlxText;
	var _bgBar:FlxSprite;
	var _fillBar:FlxSprite;
	var _targetValue:Int;
	var _barPct:Float;
	var _barColor:Int;

	static final BAR_MAX:Float = 360.0;
	static final BAR_H:Float = 14.0;

	public function new(x:Float, y:Float, label:String, value:Int, textColor:Int, barPct:Float, barColor:Int) {
		super(x, y);
		_targetValue = value;
		_barPct = barPct;
		_barColor = barColor;

		_label = new FlxText(0, 0, 110, label, 20);
		_label.setFormat(Paths.font('vcr.ttf'), 20, textColor, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		_label.borderSize = 2;
		add(_label);

		_bgBar = new FlxSprite(116, 8);
		_bgBar.makeGraphic(Std.int(BAR_MAX), Std.int(BAR_H), FlxColor.fromRGB(30, 30, 30));
		_bgBar.alpha = 0.55;
		add(_bgBar);

		_fillBar = new FlxSprite(116, 8);
		_fillBar.makeGraphic(Std.int(Math.max(1, BAR_MAX)), Std.int(BAR_H), barColor);
		_fillBar.scale.x = 0;
		_fillBar.origin.x = 0;
		add(_fillBar);

		_counter = new FlxText(BAR_MAX + 126, 0, 80, '0', 20);
		_counter.setFormat(Paths.font('vcr.ttf'), 20, FlxColor.WHITE, RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		_counter.borderSize = 2;
		add(_counter);
	}

	public function animateCounter():Void {
		FlxTween.tween(_fillBar.scale, {x: Math.max(0.001, _barPct)}, 0.8, {ease: FlxEase.expoOut});

		FlxTween.num(0, _targetValue, 0.65, {ease: FlxEase.quartOut}, function(v:Float) {
			_counter.text = Std.string(Std.int(v));
		});
	}
}

// =============================================================================
//  ScoreDigitGroup — animated score display (slot machine style)
// =============================================================================
class ScoreDigitGroup extends FlxSpriteGroup {
	var _digits:Array<ScoreDigit> = [];
	var _score:Int;

	static final DIGIT_W:Float = 48.0;

	public function new(x:Float, y:Float, score:Int) {
		super(x, y);
		_score = score;

		// Max 9 digits
		for (i in 0...9) {
			var d = new ScoreDigit(i * DIGIT_W, 0);
			_digits.push(d);
			add(d);
		}
		_setScore(score);
	}

	function _setScore(score:Int):Void {
		var s = Std.string(score);
		// Right-align: fill with 'blank' on the left
		var idx = _digits.length - 1;
		var si = s.length - 1;
		while (idx >= 0) {
			if (si >= 0) {
				_digits[idx].setDigit(Std.parseInt(s.charAt(si)));
				si--;
			} else {
				_digits[idx].setDigit(-1); // blank
			}
			idx--;
		}
	}

	/** Call this after alpha tween completes to start the shuffle animation */
	public function animateIn():Void {
		var s = Std.string(_score);
		var offset = _digits.length - s.length;
		for (i in 0..._digits.length) {
			var d = _digits[i];
			var pos = i - offset;
			if (pos < 0)
				continue; // leading blank
			new FlxTimer().start(pos * (1 / 24), function(_) {
				d.animateShuffle();
			});
		}
	}
}

class ScoreDigit extends FlxText {
	var _target:Int = -1; // -1 = blank

	public function new(x:Float, y:Float) {
		super(x, y, 44, '', 38);
		setFormat(Paths.font('vcr.ttf'), 38, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		borderSize = 3;
		text = '';
	}

	public function setDigit(n:Int):Void {
		_target = n;
		text = (n < 0) ? '' : '0';
	}

	public function animateShuffle():Void {
		if (_target < 0)
			return;

		// Quick shuffle through random digits, then land on target
		var ticks = 18;
		var cur = FlxG.random.int(0, 9);
		var timer = new FlxTimer();
		timer.start(1 / 24, function(t:FlxTimer) {
			if (t.loopsLeft == 0) {
				text = Std.string(_target);
				// Flash on final landing
				FlxTween.tween(this, {alpha: 0.3}, 0.05, {
					onComplete: function(_) {
						alpha = 1.0;
					}
				});
			} else {
				cur = (cur + 1) % 10;
				text = Std.string(cur);
				FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.4);
			}
		}, ticks);
	}
}

// =============================================================================
//  RankEntry / RankConfig  (identical format to v3)
// =============================================================================
typedef RankEntry = {
	var key:String;
	var minAccuracy:Float;
	@:optional var displayName:String;
	@:optional var color:String;
	@:optional var bgColor:String;
	@:optional var music:String;
	@:optional var sparkles:Bool;
	@:optional var camShake:Float;
}

class RankConfig {
	public var ranks:Array<RankEntry>;
	public var failAt:Float;
	public var naWhenZero:Bool;
	public var bpm:Float;

	public function new() {
		ranks = _defaultRanks();
		failAt = 59.99;
		naWhenZero = true;
		bpm = 120.0;
	}

	public static function defaults():RankConfig
		return new RankConfig();

	public static function load(songId:String):RankConfig {
		var cfg = new RankConfig();
		var paths:Array<String> = [];

		#if sys
		var activeMod = mods.ModManager.activeMod;
		if (activeMod != null) {
			var base = '${mods.ModManager.MODS_FOLDER}/$activeMod';
			if (songId.length > 0)
				paths.push('$base/data/songs/$songId/ranking_config.json');
			paths.push('$base/data/ranking_config.json');
		}
		#end
		if (songId.length > 0)
			paths.push('assets/data/songs/$songId/ranking_config.json');
		paths.push('assets/data/ranking_config.json');

		for (p in paths) {
			#if sys
			if (!sys.FileSystem.exists(p))
				continue;
			try {
				_parseInto(cfg, Json.parse(sys.io.File.getContent(p)));
				trace('[ResultScreen] Config loaded: $p');
				break;
			} catch (e:Dynamic) {
				trace('[ResultScreen] Parse error $p: $e');
			}
			#else
			try {
				if (!openfl.utils.Assets.exists(p))
					continue;
				_parseInto(cfg, Json.parse(openfl.utils.Assets.getText(p)));
				break;
			} catch (_:Dynamic) {}
			#end
		}
		return cfg;
	}

	static function _parseInto(cfg:RankConfig, raw:Dynamic):Void {
		if (raw.failAt != null)
			cfg.failAt = raw.failAt;
		if (raw.naWhenZero != null)
			cfg.naWhenZero = raw.naWhenZero;
		if (raw.bpm != null)
			cfg.bpm = raw.bpm;

		if (raw.ranks != null) {
			cfg.ranks = [];
			for (r in (raw.ranks : Array<Dynamic>))
				cfg.ranks.push({
					key: r.key ?? '?',
					minAccuracy: r.minAccuracy ?? 0,
					displayName: r.displayName,
					color: r.color,
					bgColor: r.bgColor,
					music: r.music,
					sparkles: r.sparkles ?? false,
					camShake: r.camShake ?? 0.01
				});
		}
	}

	static function _defaultRanks():Array<RankEntry> {
		return [
			{
				key: 'SS',
				minAccuracy: 99.99,
				displayName: 'PERFECT!!',
				color: 'FFD700',
				bgColor: 'FFD700',
				music: 'SS',
				sparkles: true,
				camShake: 0.012
			},
			{
				key: 'S',
				minAccuracy: 94.99,
				displayName: 'AMAZING!',
				color: '64FF64',
				bgColor: '64FF00',
				music: 'S',
				sparkles: true,
				camShake: 0.010
			},
			{
				key: 'A',
				minAccuracy: 89.99,
				displayName: 'EXCELLENT!',
				color: '64FFFF',
				bgColor: '64C8FF',
				music: 'A',
				sparkles: false,
				camShake: 0.008
			},
			{
				key: 'B',
				minAccuracy: 79.99,
				displayName: 'GREAT!',
				color: 'FFFF00',
				bgColor: '64C8FF',
				music: 'B',
				sparkles: false,
				camShake: 0.006
			},
			{
				key: 'C',
				minAccuracy: 69.99,
				displayName: 'NICE!',
				color: 'FFA000',
				bgColor: 'FF9664',
				music: 'B',
				sparkles: false,
				camShake: 0.004
			},
			{
				key: 'D',
				minAccuracy: 59.99,
				displayName: 'OK',
				color: 'FF6400',
				bgColor: 'FF9664',
				music: 'B',
				sparkles: false,
				camShake: 0.004
			},
			{
				key: 'F',
				minAccuracy: 0,
				displayName: 'KEEP TRYING',
				color: 'FF3333',
				bgColor: 'C86464',
				music: 'B',
				sparkles: false,
				camShake: 0.008
			}
		];
	}
}
