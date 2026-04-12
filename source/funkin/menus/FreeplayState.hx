package funkin.menus;

#if desktop
import data.Discord.DiscordClient;
#end
import openfl.filters.BitmapFilterQuality;
import openfl.filters.GlowFilter;
import openfl.filters.BlurFilter;
import flash.text.TextField;
import flash.geom.Rectangle;
import flixel.FlxG;
import lime.app.Application;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.util.FlxTimer;
import funkin.transitions.StateTransition;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.group.FlxGroup;
import flixel.math.FlxMath;
import flixel.tweens.FlxEase;
import funkin.menus.StoryMenuState;
import flixel.text.FlxText;
import flixel.util.FlxColor;
import flixel.tweens.FlxTween;
import lime.utils.Assets;
import flixel.sound.FlxSound;
import funkin.states.LoadingState;
import flixel.effects.particles.FlxEmitter;
import flixel.effects.particles.FlxParticle;
import funkin.gameplay.objects.character.HealthIcon;
import funkin.data.Song;
import funkin.gameplay.objects.hud.Highscore;
import funkin.scripting.StateScriptHandler;
import funkin.transitions.StickerTransition;
import funkin.data.FreeplayList;
import funkin.data.FreeplayList.FreeplayListData;
import funkin.data.FreeplayList.FreeplaySongEntry;
import funkin.gameplay.PlayState;
import funkin.data.Conductor;
import funkin.data.CoolUtil;
import animationdata.FunkinSprite;

using StringTools;

import haxe.Json;
import funkin.audio.MusicManager;
#if sys
import sys.FileSystem;
import funkin.data.SaveData;
#end

/**
 * FreeplayState v3 — cinematic two-panel layout.
 *
 * Changes from v2:
 *   • Song names use CapsuleText-style (Funkin.otf + cyan glow, no more Alphabet)
 *   • Album art bottom-right, softcoded from songList.json via `album` + `albumText` fields
 */
class FreeplayState extends funkin.states.MusicBeatState
{
	var toBeFinished = 0;
	var finished = 0;

	/** Datos de freeplay (freeplayList.json). */
	public static var freeplayData:FreeplayListData;

	var songs:Array<SongMetadata> = [];

	// ── Selection state ────────────────────────────────────────────────────────
	private static var curSelected:Int = 0;
	private static var curDifficulty:Int = 1;

	// ── Score data ────────────────────────────────────────────────────────────
	var lerpScore:Float = 0;
	var lerpRating:Float = 0;
	var intendedScore:Int = 0;
	var intendedRating:Float = 0;

	// ── Left panel — song list ─────────────────────────────────────────────────
	private var grpSongs:FlxTypedGroup<FreeplaySongText>;
	private var iconArray:Array<HealthIcon> = [];

	// ── Right panel — spotlight ───────────────────────────────────────────────
	var cardBg:FlxSprite;
	var cardAccent:FlxSprite;
	var spotlightTitle:FreeplaySongText; // big song name (CapsuleText style)
	var spotlightArtist:FlxText;
	var spotlightIcon:HealthIcon;
	var rankBadge:FlxSprite;
	var rankBadgeBg:FlxSprite;
	var congrats:FlxText;
	var scoreCard:FlxSprite;
	var scoreValueTxt:FlxText;
	var accuracyTxt:FlxText;
	var diffPills:FlxTypedGroup<FlxSprite>;
	var diffTexts:Array<FlxText> = [];

	// ── Album art (bottom-right) ───────────────────────────────────────────────
	var albumArt:FlxSprite; // static cover image
	var albumTextSpr:FunkinSprite; // animated title text atlas
	var _curAlbumKey:String = '';
	var _curAlbumTextKey:String = '';

	// ── Waveform bars ─────────────────────────────────────────────────────────
	static inline final NUM_BARS = 32;
	static inline final BAR_W = 8;
	static inline final BAR_GAP = 4;

	var waveGroup:FlxTypedGroup<FlxSprite>;
	var beatTimer:Float = 0;

	// ── Background ────────────────────────────────────────────────────────────
	var bg:FlxSprite;
	var bgTint:FlxSprite;
	var intendedColor:Int = 0xFF0d0820;
	var colorTween:FlxTween;

	// ── Disc / record player ──────────────────────────────────────────────────
	var discSpr:FlxSprite;

	var _discBaseAngle:Float = 0.0; // accumulated rotation (deg)
	var _discSpinSpeed:Float = 45.0; // deg/sec at rest
	var _discBeatBump:Float = 0.0; // extra speed added on beat, decays to 0

	// ── Error overlay ─────────────────────────────────────────────────────────
	var errorText:FlxText;
	var errorTween:FlxTween;

	// ── Layout constants ──────────────────────────────────────────────────────
	static inline final LEFT_W = 440;
	static inline final CARD_X = 450;
	static inline final CARD_W = 790;
	static inline final CARD_Y = 60;
	static inline final CARD_H = 570;

	// ── Album layout ──────────────────────────────────────────────────────────
	static inline final ALBUM_X = 1000; // center X of album art
	static inline final ALBUM_Y = 480; // center Y of album art
	static inline final ALBUM_SZ = 235; // display size
	static inline final ATEXT_Y = 570; // Y of album text label

	public static var instPlaying:Int = -1;
	public static var difficultyStuff:Array<Dynamic> = [['Easy', '-easy'], ['Normal', ''], ['Hard', '-hard']];
	public static var coolColors:Array<Int> = [];

	var _previewSound:FlxSound = null;

	// ── Rank helpers ──────────────────────────────────────────────────────────
	static function _rankFromAcc(acc:Float):String
	{
		if (acc <= 0)
			return '';
		var p = acc * 100.0;
		if (p >= 99.99)
			return 'SS';
		if (p >= 94.99)
			return 'S';
		if (p >= 89.99)
			return 'A';
		if (p >= 79.99)
			return 'B';
		if (p >= 69.99)
			return 'C';
		if (p >= 59.99)
			return 'D';
		return 'F';
	}

	static function _rankColor(rank:String):FlxColor
	{
		return switch (rank)
		{
			case 'SS': FlxColor.fromString('#FFD700');
			case 'S': FlxColor.fromString('#64FF64');
			case 'A': FlxColor.fromString('#64FFFF');
			case 'B': FlxColor.fromString('#FFFF00');
			case 'C': FlxColor.fromString('#FFA000');
			case 'D': FlxColor.fromString('#FF6464');
			default: FlxColor.fromString('#888888');
		};
	}

	static function _congratsMsg(rank:String):String
	{
		return switch (rank)
		{
			case 'SS': 'ABSOLUTELY PERFECT!! ✦';
			case 'S': 'Amazing job! Keep it up! ✦';
			case 'A': 'Excellent run! So clean!';
			case 'B': 'Great work! Almost there!';
			case 'C': 'Nice try! Practice makes perfect.';
			case 'D': 'Keep grinding, you got this!';
			default: '';
		};
	}

	var artist = '';

	// ─────────────────────────────────────────────────────────────────────────

	override function create()
	{
		FlxG.mouse.visible = false;
		FlxG.keys.reset();

		if (StickerTransition.enabled)
		{
			transIn = null;
			transOut = null;
		}

		// Resetear preview estático — puede quedar con índice viejo si venimos de PlayState
		instPlaying = -1;

		// Registrar el resolver de paths en PathsCache para que la clave corta
		// 'menu/ratings/SS' se resuelva a 'assets/images/menu/ratings/SS.png', etc.
		// Esto elimina los falsos "No se pudo cargar" cuando el asset sí existe.
		funkin.cache.PathsCache.pathResolver = function(k) return Paths.image(k);

		MusicManager.play('girlfriendsRingtone/girlfriendsRingtone', 0.7);

		loadSongsData();

		// FIX: cargar scripts ANTES de songsSystem() para que preFilterSongs()
		// pueda modificar freeplayData.songs antes de que se construya la UI.
		// Sin este cambio, los scripts se cargaban DESPUÉS de la lista de canciones
		// y no podían filtrarla.
		#if HSCRIPT_ALLOWED
		StateScriptHandler.init();
		StateScriptHandler.loadStateScripts('FreeplayState', this);
		StateScriptHandler.exposeElement('freeplayData', freeplayData);
		StateScriptHandler.callOnScripts('preFilterSongs', []);
		#end

		if (freeplayData != null && freeplayData.songs != null)
			songsSystem();

		#if desktop
		DiscordClient.changePresence("In the FreePlay", null);
		#end

		// ── Background ────────────────────────────────────────────────────────
		bg = new FlxSprite();
		try
		{
			bg.loadGraphic(Paths.image('menu/menuBG'));
		}
		catch (_)
		{
			bg.makeGraphic(FlxG.width, FlxG.height, 0xFF0d0820);
		}
		bg.color = 0xFF0d0820;
		bg.alpha = 0.5;
		bg.scrollFactor.set(0.06, 0.06);
		bg.scale.set(1.05, 1.05);
		bg.screenCenter();
		add(bg);

		bgTint = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xFF0d0820);
		bgTint.alpha = 0.82;
		bgTint.scrollFactor.set();
		add(bgTint);

		// ── Left stripe ───────────────────────────────────────────────────────
		var leftStripe = new FlxSprite().makeGraphic(LEFT_W + 10, FlxG.height, 0xFF000000);
		leftStripe.alpha = 0.35;
		leftStripe.scrollFactor.set();
		add(leftStripe);

		var divider = new FlxSprite(LEFT_W, 0).makeGraphic(2, FlxG.height, 0xFFffffff);
		divider.alpha = 0.07;
		divider.scrollFactor.set();
		add(divider);

		// ── Right card ────────────────────────────────────────────────────────
		cardBg = new FlxSprite(CARD_X, CARD_Y).makeGraphic(CARD_W, CARD_H, 0xFF0d0820);
		cardBg.alpha = 0.55;
		cardBg.scrollFactor.set();
		add(cardBg);

		cardAccent = new FlxSprite(CARD_X, CARD_Y).makeGraphic(4, CARD_H, 0xFFffffff);
		cardAccent.scrollFactor.set();
		add(cardAccent);

		// ── Waveform bars ─────────────────────────────────────────────────────
		waveGroup = new FlxTypedGroup<FlxSprite>();
		add(waveGroup);
		for (i in 0...NUM_BARS)
		{
			var bar = new FlxSprite(CARD_X + 20 + i * (BAR_W + BAR_GAP), CARD_Y + CARD_H - 10);
			bar.makeGraphic(BAR_W, 80, FlxColor.WHITE);
			bar.alpha = 0.18;
			bar.scrollFactor.set();
			waveGroup.add(bar);
		}

		// ── Song list (left panel) ─────────────────────────────────────────────
		grpSongs = new FlxTypedGroup<FreeplaySongText>();
		add(grpSongs);

		for (i in 0...songs.length)
		{
			var txt = new FreeplaySongText(28, (70 * i) + 60, songs[i].songName);
			txt.isMenuItem = true;
			txt.targetY = i;
			grpSongs.add(txt);

			var icon = new HealthIcon(songs[i].songCharacter);
			icon.sprTracker = txt;
			icon.scale.set(0.6, 0.6);
			icon.updateHitbox();
			iconArray.push(icon);
			add(icon);
		}

		// Scripts ya cargados arriba (antes de songsSystem).
		// Aquí solo llamamos onCreate — la UI ya está construida,
		// el script puede añadir elementos extra o modificar estado.
		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onCreate', []);
		#end

		// ── Right panel ───────────────────────────────────────────────────────

		// Large icon
		spotlightIcon = new HealthIcon('bf');
		spotlightIcon.setGraphicSize(148, 148);
		spotlightIcon.updateHitbox();
		spotlightIcon.x = CARD_X + CARD_W - 180;
		spotlightIcon.y = CARD_Y;
		spotlightIcon.scrollFactor.set();
		add(spotlightIcon);

		// Song title — CapsuleText style (big, glow)
		spotlightTitle = new FreeplaySongText(CARD_X + 20, CARD_Y + 18, '', 44);
		spotlightTitle.maxWidth = CARD_W - 230;
		spotlightTitle.scrollFactor.set();
		add(spotlightTitle);

		// Artist / week subtitle
		spotlightArtist = new FlxText(CARD_X + 20, CARD_Y + 72, CARD_W - 220, '', 18);
		spotlightArtist.setFormat(Paths.font('vcr.ttf'), 18, FlxColor.fromString('#aaaacc'), LEFT);
		spotlightArtist.scrollFactor.set();
		add(spotlightArtist);

		// Difficulty pills
		diffPills = new FlxTypedGroup<FlxSprite>();
		add(diffPills);

		// Score sub-card
		scoreCard = new FlxSprite(CARD_X + 20, CARD_Y + 140).makeGraphic(CARD_W - 40, 80, 0xFF000000);
		scoreCard.alpha = 0.45;
		scoreCard.scrollFactor.set();
		add(scoreCard);

		scoreValueTxt = new FlxText(CARD_X + 36, CARD_Y + 148, 0, 'BEST: 0', 28);
		scoreValueTxt.setFormat(Paths.font('vcr.ttf'), 28, FlxColor.WHITE, LEFT);
		scoreValueTxt.scrollFactor.set();
		add(scoreValueTxt);

		accuracyTxt = new FlxText(CARD_X + 36, CARD_Y + 182, 0, '', 18);
		accuracyTxt.setFormat(Paths.font('vcr.ttf'), 18, FlxColor.fromString('#aaddff'), LEFT);
		accuracyTxt.scrollFactor.set();
		add(accuracyTxt);

		// Rank badge
		rankBadgeBg = new FlxSprite(CARD_X + CARD_W - 132, CARD_Y + 136).makeGraphic(100, 100, FlxColor.WHITE);
		rankBadgeBg.alpha = 0;
		rankBadgeBg.scrollFactor.set();
		add(rankBadgeBg);

		rankBadge = new FlxSprite(CARD_X + CARD_W - 130, CARD_Y + 140);
		rankBadge.alpha = 0;
		rankBadge.scrollFactor.set();
		add(rankBadge);

		// Congrats
		congrats = new FlxText(CARD_X + 30, CARD_Y + 280, CARD_W - 40, '', 20);
		congrats.setFormat(Paths.font('Funkin.otf'), 20, FlxColor.fromString('#ffee88'), LEFT, OUTLINE, FlxColor.BLACK);
		congrats.borderSize = 1;
		congrats.alpha = 0;
		congrats.scrollFactor.set();
		add(congrats);

		// ── Album art (bottom-right) ───────────────────────────────────────────
		albumArt = new FlxSprite();
		albumArt.makeGraphic(1, 1, FlxColor.TRANSPARENT);
		albumArt.alpha = 0;
		albumArt.scrollFactor.set();
		add(albumArt);

		albumTextSpr = new FunkinSprite();
		albumTextSpr.makeGraphic(1, 1, FlxColor.TRANSPARENT);
		albumTextSpr.alpha = 0;
		albumTextSpr.scrollFactor.set();
		add(albumTextSpr);

		// ── Footer hint ───────────────────────────────────────────────────────
		var footerBg = new FlxSprite(0, FlxG.height - 32).makeGraphic(FlxG.width, 32, 0xFF000000);
		footerBg.alpha = 0.65;
		footerBg.scrollFactor.set();
		add(footerBg);

		var hintText = new FlxText(0, FlxG.height - 28, FlxG.width, 'UP/DOWN Select  |  LEFT/RIGHT Difficulty  |  SPACE Preview  |  ENTER Play  |  ESC Back',
			16);
		hintText.setFormat(Paths.font('vcr.ttf'), 16, FlxColor.fromString('#888899'), CENTER);
		hintText.scrollFactor.set();
		add(hintText);

		// ── Error text ────────────────────────────────────────────────────────
		errorText = new FlxText(0, FlxG.height * 0.5 - 50, FlxG.width, '', 28);
		errorText.setFormat(Paths.font('vcr.ttf'), 28, FlxColor.RED, CENTER, OUTLINE, FlxColor.BLACK);
		errorText.setBorderStyle(OUTLINE, FlxColor.BLACK, 3);
		errorText.scrollFactor.set();
		errorText.alpha = 0;
		add(errorText);

		// ── Initial state ─────────────────────────────────────────────────────
		if (songs.length > 0)
		{
			bgTint.color = songs[curSelected].color;
			intendedColor = songs[curSelected].color;
			cardAccent.color = songs[curSelected].color;
		}

		_updateDifficultyStuff();
		// Precachear álbumes y rank badges en el main thread.
		// PathsCache/FlxG.bitmap/HarfBuzz NO son thread-safe — llamarlos desde
		// un hilo secundario corrompe buffers internos de HarfBuzz y causa
		// "Assertion failed: bits == (allocated_var_bits & bits)" al volver al freeplay.
		#if sys
		for (s in songs)
		{
			var ak = _albumKeyFor(s);
			if (ak != '' && Paths.exists('images/menu/freeplay/albums/$ak.png'))
				try
				{
					funkin.cache.PathsCache.instance.cacheGraphic('menu/freeplay/albums/$ak');
				}
				catch (_)
				{
				}
		}
		for (rank in ['SS', 'S', 'A', 'B', 'C', 'D'])
			if (Paths.exists('images/menu/ratings/$rank.png'))
				try
				{
					funkin.cache.PathsCache.instance.cacheGraphic('menu/ratings/$rank');
				}
				catch (_)
				{
				}
		#end
		changeSelection(0);
		_rebuildDiffPills();
		changeDiff(0);

		StickerTransition.clearStickers();

		if (songs.length == 0)
		{
			showError('No songs found!\nPlease add songs to your songList.json');
			new FlxTimer().start(2.0, function(_)
			{
				if (mods.ModManager.developerMode)
					StateTransition.switchState(new funkin.debug.editors.FreeplayEditorState());
			});
		}

		#if HSCRIPT_ALLOWED
		StateScriptHandler.refreshStateFields(this);
		StateScriptHandler.callOnScripts('postCreate', []);
		#end

		#if mobileC
		addVirtualPad(FULL, A_B);
		#end

		super.create();
	}

	// ── Album loading / display ───────────────────────────────────────────────

	/**
	 * Returns the album key for the currently selected song, or '' if none.
	 * Album is stored directly on SongMetadata, populated from freeplayList.json.
	 */
	function _albumKeyFor(song:SongMetadata):String
		return (song.album != null && song.album != '') ? song.album : '';

	function _albumTextKeyFor(song:SongMetadata):String
		return (song.albumText != null && song.albumText != '') ? song.albumText : '';

	/**
	 * Updates the album art + text label for the given song.
	 * Animates old out, new in. Works for both base game and mods —
	 * Paths.resolve() automatically checks mods/{activeMod}/ first.
	 *
	 * Asset paths checked (in order):
	 *   mods/{mod}/images/menu/freeplay/albums/{key}.png   ← mod override
	 *   assets/images/menu/freeplay/albums/{key}.png       ← base game
	 *
	 * If the file does not exist in either location the album is hidden.
	 */
	function _updateAlbum(song:SongMetadata):Void
	{
		var artKey = _albumKeyFor(song);
		var textKey = _albumTextKeyFor(song);

		// No change — skip
		if (artKey == _curAlbumKey && textKey == _curAlbumTextKey)
			return;
		_curAlbumKey = artKey;
		_curAlbumTextKey = textKey;

		FlxTween.cancelTweensOf(albumArt);
		FlxTween.cancelTweensOf(albumTextSpr);

		// ── Hide both if no album key ──────────────────────────────────────────
		if (artKey == '')
		{
			_hideAlbum();
			return;
		}

		// ── Check art file exists (mod-aware via Paths.exists) ────────────────
		//   Paths.image returns a resolved path; Paths.exists checks that path.
		var artAssetKey = 'images/menu/freeplay/albums/$artKey.png';
		if (!Paths.exists(artAssetKey))
		{
			// Not in base assets — also check mod root explicitly for safety
			#if sys
			var modPath = mods.ModManager.isActive() ? '${mods.ModManager.modRoot()}/images/menu/freeplay/albums/$artKey.png' : null;
			var found = (modPath != null && sys.FileSystem.exists(modPath));
			if (!found)
			{
				_hideAlbum();
				return;
			}
			#else
			_hideAlbum();
			return;
			#end
		}

		// ── Load art via PathsCache (evita decodificar PNG cada cambio) ────────
		try
		{
			final _cacheKey = 'menu/freeplay/albums/$artKey';
			final _gfx = funkin.cache.PathsCache.instance.cacheGraphic(_cacheKey);
			if (_gfx != null && _gfx.bitmap != null)
			{
				albumArt.loadGraphic(_gfx);
			}
			else
			{
				albumArt.loadGraphic(Paths.getGraphic(_cacheKey));
			}
			albumArt.setGraphicSize(ALBUM_SZ, ALBUM_SZ);
			albumArt.updateHitbox();
		}
		catch (e:Dynamic)
		{
			trace('[FreeplayState] Failed to load album art "$artKey": $e');
			_hideAlbum();
			return;
		}

		// Slide in from right
		albumArt.x = FlxG.width + 10;
		albumArt.y = ALBUM_Y - albumArt.height / 2;
		albumArt.alpha = 0;
		FlxTween.tween(albumArt, {
			alpha: 1.0,
			x: ALBUM_X - albumArt.width / 2 + 50
		}, 0.4, {ease: FlxEase.expoOut});

		// ── Load text atlas (optional) ─────────────────────────────────────────
		if (textKey != '')
		{
			var textPngKey = 'images/menu/freeplay/albums/$textKey.png';
			var textXmlKey = 'images/menu/freeplay/albums/$textKey.xml';

			var textExists = Paths.exists(textPngKey) && Paths.exists(textXmlKey);
			#if sys
			if (!textExists && mods.ModManager.isActive())
			{
				var r = mods.ModManager.modRoot();
				textExists = sys.FileSystem.exists('$r/images/menu/freeplay/albums/$textKey.png')
					&& sys.FileSystem.exists('$r/images/menu/freeplay/albums/$textKey.xml');
			}
			#end

			if (textExists)
			{
				try
				{
					albumTextSpr.loadAsset('menu/freeplay/albums/$textKey');
					albumTextSpr.addAnim('idle', 'idle', 24, true);
					albumTextSpr.addAnim('switch', 'switch', 24, false);
					albumTextSpr.setGraphicSize(Std.int(albumTextSpr.width * 0.9));
					albumTextSpr.updateHitbox();
					albumTextSpr.x = FlxG.width + 10;
					albumTextSpr.y = ATEXT_Y;
					albumTextSpr.alpha = 0;
					albumTextSpr.playAnim('switch', true);
					FlxTween.tween(albumTextSpr, {
						alpha: 1.0,
						x: ALBUM_X - albumTextSpr.width / 2 + 50
					}, 0.4, {
						ease: FlxEase.expoOut,
						startDelay: 0.05,
						onComplete: function(_)
						{
							if (albumTextSpr.hasAnim('idle'))
								albumTextSpr.playAnim('idle', true);
						}
					});
				}
				catch (e:Dynamic)
				{
					trace('[FreeplayState] Failed to load album text "$textKey": $e');
					albumTextSpr.alpha = 0;
					albumTextSpr.visible = false;
				}
			}
			else
			{
				// Text atlas declared but file missing — hide gracefully
				FlxTween.tween(albumTextSpr, {alpha: 0}, 0.2, {
					ease: FlxEase.quadIn,
					onComplete: function(_)
					{
						albumTextSpr.visible = false;
					}
				});
			}
		}
		else
		{
			// No albumText key — just hide
			FlxTween.tween(albumTextSpr, {alpha: 0}, 0.2, {
				ease: FlxEase.quadIn,
				onComplete: function(_)
				{
					albumTextSpr.visible = false;
				}
			});
		}
	}

	/** Fades out and hides both album sprites. */
	inline function _hideAlbum():Void
	{
		FlxTween.tween(albumArt, {alpha: 0}, 0.2, {
			ease: FlxEase.quadIn,
			onComplete: function(_)
			{
				albumArt.visible = false;
			}
		});
		FlxTween.tween(albumTextSpr, {alpha: 0}, 0.2, {
			ease: FlxEase.quadIn,
			onComplete: function(_)
			{
				albumTextSpr.visible = false;
			}
		});
	}

	// ── Data loading (unchanged) ──────────────────────────────────────────────

	function songsSystem()
	{
		coolColors = [];

		for (i in 0...freeplayData.songs.length)
		{
			final entry = freeplayData.songs[i];
			final meta = new SongMetadata(entry.name, entry.group ?? i, entry.icon ?? 'bf', i);

			// Artista: campo directo > meta.json
			#if sys
			try
			{
				final m = funkin.data.MetaData.load(entry.name.toLowerCase());
				if (m.artist != null)
					artist = m.artist;
			}
			catch (_)
			{
			}
			#end
			if (artist == '')
				artist = entry.artist ?? '';
			meta.album = entry.album ?? '';
			meta.albumText = entry.albumText ?? '';

			songs.push(meta);

			// Color del grupo (un color por grupo, usando el de la primera canción del grupo)
			if (i >= coolColors.length)
			{
				final colorInt:Null<Int> = Std.parseInt(entry.color ?? '0xFFFFD900');
				coolColors.push(colorInt != null ? colorInt : 0xFFFFD900);
			}
		}
	}

	function loadSongsData():Void
	{
		// Compat: Psych Engine mods inyectan sus canciones con su propio sistema
		#if sys
		if (mods.ModManager.isActive())
		{
			final fmt = mods.compat.ModCompatLayer.getActiveModFormat();
			if (fmt == mods.compat.ModFormat.PSYCH_ENGINE)
			{
				final entries:Array<FreeplaySongEntry> = [];
				for (modWeek in mods.compat.ModCompatLayer.getModSongsInfo())
				{
					if (Reflect.field(modWeek, 'hideFreeplay') == true)
						continue;
					final ws:Array<String> = cast(Reflect.field(modWeek, 'weekSongs') ?? []);
					final si:Array<String> = cast(Reflect.field(modWeek, 'songIcons') ?? []);
					final bp:Array<Float> = cast(Reflect.field(modWeek, 'bpm') ?? []);
					final cl:Array<String> = cast(Reflect.field(modWeek, 'color') ?? []);
					for (j in 0...ws.length)
						entries.push({
							name: ws[j],
							icon: (si != null && j < si.length) ? si[j] : 'bf',
							bpm: (bp != null && j < bp.length) ? bp[j] : 120.0,
							color: (cl != null && cl.length > 0) ? cl[0] : '0xFFFFD900',
							group: 0
						});
				}
				freeplayData = {songs: entries};
				return;
			}
		}
		#end
		// Cargar freeplayList.json (con fallback a songList.json legacy)
		freeplayData = FreeplayList.load();

		// Mod sin freeplayList.json → auto-discover
		#if sys
		if (mods.ModManager.isActive() && (freeplayData == null || freeplayData.songs.length == 0))
			freeplayData = _autoDiscoverModSongs();
		#end
	}

	#if sys
	function _autoDiscoverModSongs():FreeplayListData
	{
		final modId = mods.ModManager.activeMod;
		if (modId == null)
			return {songs: []};
		final songsDir = '${mods.ModManager.MODS_FOLDER}/$modId/songs';
		if (!sys.FileSystem.exists(songsDir))
			return {songs: []};
		final entries:Array<FreeplaySongEntry> = [];
		for (entry in sys.FileSystem.readDirectory(songsDir))
		{
			final ep = '$songsDir/$entry';
			if (!sys.FileSystem.isDirectory(ep))
				continue;
			var hasChart = sys.FileSystem.exists('$ep/$entry.level');
			if (!hasChart)
				for (diff in ['hard', 'normal', 'easy', 'chart'])
					if (sys.FileSystem.exists('$ep/$diff.json'))
					{
						hasChart = true;
						break;
					}
			if (!hasChart)
				continue;
			entries.push({
				name: entry,
				icon: 'icon-$entry',
				bpm: 120.0,
				color: '0xFFFF9900',
				group: 0
			});
		}
		if (entries.length > 0)
			trace('[Freeplay] Auto-discovered ${entries.length} songs from mod $modId');
		return {songs: entries};
	}
	#end

	override function closeSubState()
	{
		changeSelection();
		FlxG.keys.reset();
		super.closeSubState();
	}

	public function addSong(songName:String, weekNum:Int, songCharacter:String)
		songs.push(new SongMetadata(songName, weekNum, songCharacter));

	public function addWeek(songs:Array<String>, weekNum:Int, ?songCharacters:Array<String>)
	{
		if (songCharacters == null)
			songCharacters = ['bf'];
		var num = 0;
		for (song in songs)
		{
			addSong(song, weekNum, songCharacters[num]);
			if (songCharacters.length != 1)
				num++;
		}
	}

	// ── Update ────────────────────────────────────────────────────────────────

	override function update(elapsed:Float)
	{
		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onUpdate', [elapsed]);
		#end

		if (StickerTransition.isActive())
		{
			super.update(elapsed);
			return;
		}

		// Score lerp
		lerpScore = FlxMath.lerp(lerpScore, intendedScore, boundTo(elapsed * 22, 0, 1));
		lerpRating = FlxMath.lerp(lerpRating, intendedRating, boundTo(elapsed * 14, 0, 1));
		if (Math.abs(lerpScore - intendedScore) <= 5)
			lerpScore = intendedScore;
		if (Math.abs(lerpRating - intendedRating) <= 0.001)
			lerpRating = intendedRating;

		scoreValueTxt.text = 'BEST: ${Std.int(lerpScore)}';
		var pct = lerpRating * 100.0 / 100;
		var pctStr = Std.string(Math.floor(pct * 100) / 100);
		accuracyTxt.text = pct > 0 ? 'Accuracy: $pctStr%' : 'Not played yet';

		if (discSpr != null)
		{
			_discBeatBump = _discBeatBump * Math.pow(0.04, elapsed); // fast decay
			var curSpeed = _discSpinSpeed + _discBeatBump;
			_discBaseAngle += curSpeed * elapsed;
			discSpr.angle = _discBaseAngle;
		}

		// Waveform
		beatTimer += elapsed;
		var i = 0;
		for (bar in waveGroup.members)
		{
			var phase = beatTimer * 3.5 + i * 0.45;
			var target = 0.06 + Math.abs(Math.sin(phase)) * 0.55;
			if (FlxG.sound.music != null && FlxG.sound.music.playing)
				target = 0.1 + Math.abs(Math.sin(phase * 1.8)) * 0.85;
			bar.scale.y = FlxMath.lerp(bar.scale.y, target, elapsed * 7);
			bar.y = (CARD_Y + CARD_H - 14) - bar.scale.y * 80;
			bar.alpha = 0.12 + bar.scale.y * 0.22;
			i++;
		}

		// Update FreeplaySongText positions (mirrors old Alphabet system)
		for (txt in grpSongs.members)
		{
			if (txt == null)
				continue;
			var targetX = 28.0;
			var targetY = (txt.targetY * 70.0) + 30;
			txt.x = FlxMath.lerp(txt.x, targetX, boundTo(elapsed * 20, 0, 1));
			txt.y = FlxMath.lerp(txt.y, targetY, boundTo(elapsed * 18, 0, 1)) + 15;
		}

		FlxG.camera.zoom = FlxMath.lerp(FlxG.camera.zoom, 1.0, elapsed * 4);

		// Input
		var upP = controls.UP_P;
		var downP = controls.DOWN_P;
		var leftP = controls.LEFT_P;
		var rightP = controls.RIGHT_P;
		var accepted = FlxG.keys.justPressed.ENTER;
		var space = FlxG.keys.justPressed.SPACE;

		switch (songs.length)
		{
			case 0:
				accepted = false;
				space = false;
			case 1:
				upP = false;
				downP = false;
		}

		#if HSCRIPT_ALLOWED
		if (upP && !StateScriptHandler.callOnScripts('interceptNav', [-1, 0]))
			changeSelection(-1);
		if (downP && !StateScriptHandler.callOnScripts('interceptNav', [1, 0]))
			changeSelection(1);
		if (leftP && !StateScriptHandler.callOnScripts('interceptNav', [0, -1]))
			changeDiff(-1);
		if (rightP && !StateScriptHandler.callOnScripts('interceptNav', [0, 1]))
			changeDiff(1);
		#else
		if (upP)
			changeSelection(-1);
		if (downP)
			changeSelection(1);
		if (leftP)
			changeDiff(-1);
		if (rightP)
			changeDiff(1);
		#end

		if (controls.BACK)
		{
			FlxG.sound.play(Paths.sound('menus/cancelMenu'));
			StateTransition.switchState(new MainMenuState());
		}
		if (FlxG.keys.justPressed.E && mods.ModManager.developerMode)
			StateTransition.switchState(new funkin.debug.editors.FreeplayEditorState());

		#if sys
		if (space)
		{
			if (instPlaying != curSelected)
			{
				var songLowercase = songs[curSelected].songName.toLowerCase();
				var poop = Highscore.formatSong(songLowercase, curDifficulty);
				if (!(funkin.data.LevelFile.exists(songLowercase) || Song.findChart(songLowercase, poop) != null))
				{
					showError('Cannot preview: chart not found!');
					FlxG.sound.play(Paths.sound('menus/cancelMenu'));
					return;
				}
				try
				{
					PlayState.SONG = Song.loadFromJson(poop, songLowercase);
				}
				catch (_:Dynamic)
				{
					showError('Cannot preview: failed to load!');
					FlxG.sound.play(Paths.sound('menus/cancelMenu'));
					return;
				}
				if (PlayState.SONG == null)
				{
					showError('Cannot preview: corrupted!');
					FlxG.sound.play(Paths.sound('menus/cancelMenu'));
					return;
				}

				final diffSuffix = difficultyStuff.length > curDifficulty ? difficultyStuff[curDifficulty][1] : '';
				final audioSuffix = (PlayState.SONG.instSuffix != null && PlayState.SONG.instSuffix != '') ? '-' + PlayState.SONG.instSuffix : diffSuffix;
				// loadStream lanza SampleDataEvent en cpp/Windows cuando el backend OpenAL
				// no puede cumplir el requisito de 2048-8192 muestras por ciclo.
				// El try/catch de Haxe no puede capturar esa excepción nativa de cpp.
				// Solución: usar loadEmbedded para el preview (decodifica el OGG completo,
				// ligeramente más RAM pero sin excepciones nativas).
				final _instPath = Paths.inst(PlayState.SONG.song, audioSuffix);
				if (_instPath != null)
				{
					_cleanupPreviewSound();
					_previewSound = new flixel.sound.FlxSound();
					_previewSound.loadEmbedded(_instPath, true, false);
					FlxG.sound.list.add(_previewSound);
					funkin.audio.CoreAudio.playPreloadedMusic(_previewSound, 0.7);
				}
				instPlaying = curSelected;

				// BPM handled by Conductor on chart load

				if (discSpr != null)
				{
					remove(discSpr);
					discSpr.destroy();
				}
				discSpr = new FlxSprite(CARD_X, CARD_Y + 280);
				discSpr.loadGraphic(Paths.image('menu/freeplay/disc'));
				discSpr.antialiasing = SaveData.data.antialiasing;
				discSpr.setGraphicSize(Std.int(discSpr.width * 0.45));
				discSpr.updateHitbox();
				discSpr.scrollFactor.set();
				// Insertar el disco DEBAJO del albumArt en el display list
				// para que el album quede encima y el disco sobresalga por detrás.
				var _albumIdx = members.indexOf(albumArt);
				if (_albumIdx >= 0)
					insert(_albumIdx, discSpr);
				else
					add(discSpr);
				// Destino: centrado verticalmente sobre el album, sobresaliendo ~60px a la izquierda
				final _discTargetX = ALBUM_X - ALBUM_SZ / 2;
				final _discTargetY = ALBUM_Y - discSpr.height / 2;
				discSpr.x = _discTargetX;
				discSpr.y = _discTargetY;
				FlxTween.tween(discSpr, {x: _discTargetX - 15}, 0.55, {ease: FlxEase.elasticOut});
			}
			else
			{
				// ── Restaurar música de menú sin forceRestart ────────────────
				// Igual que en changeSelection: CoreAudio restaurará la posición
				// guardada cuando rearranca girlfriendsRingtone.
				_cleanupPreviewSound();
				MusicManager.play('girlfriendsRingtone/girlfriendsRingtone', 0.7, false);
				instPlaying = -1;
				if (discSpr != null)
					FlxTween.tween(discSpr, {x: FlxG.width + 50}, 0.4, {
						ease: FlxEase.expoIn,
						onComplete: function(_)
						{
							if (discSpr != null)
							{
								remove(discSpr);
								discSpr.destroy();
								discSpr = null;
							}
						}
					});
			}
		}
		#end

		if (accepted)
		{
			#if HSCRIPT_ALLOWED
			if (StateScriptHandler.callOnScriptsReturn('onAccept', [], false))
				return;
			#end
			var songLowercase = songs[curSelected].songName.toLowerCase();
			var poop = Highscore.formatSong(songLowercase, curDifficulty);
			if (!(funkin.data.LevelFile.exists(songLowercase) || Song.findChart(songLowercase, poop) != null))
			{
				showError('ERROR: chart not found!\n"$songLowercase"');
				FlxG.sound.play(Paths.sound('menus/cancelMenu'));
				FlxG.camera.shake(0.01, 0.3);
				return;
			}
			try
			{
				PlayState.SONG = Song.loadFromJson(poop, songLowercase);
			}
			catch (e:Dynamic)
			{
				showError('ERROR: failed to load!\n' + e);
				FlxG.sound.play(Paths.sound('menus/cancelMenu'));
				FlxG.camera.shake(0.01, 0.3);
				return;
			}
			if (PlayState.SONG == null || PlayState.SONG.song == null)
			{
				showError('ERROR: corrupted chart!\n"$songLowercase"');
				FlxG.sound.play(Paths.sound('menus/cancelMenu'));
				FlxG.camera.shake(0.01, 0.3);
				return;
			}
			PlayState.isStoryMode = false;
			PlayState.storyDifficulty = curDifficulty;
			PlayState.storyWeek = songs[curSelected].week;
			if (colorTween != null)
				colorTween.cancel();
			funkin.audio.MusicManager.stop();
			if (SaveData.data.flashing)
				FlxG.camera.flash(FlxColor.WHITE, 1);
			FlxG.sound.play(Paths.sound('menus/confirmMenu'), 0.7);
			StickerTransition.setCurrentContext(songs[curSelected].week, songs[curSelected].songName);
			StickerTransition.start(function() LoadingState.loadAndSwitchState(new PlayState()));
		}

		super.update(elapsed);
		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onUpdatePost', [elapsed]);
		#end
	}

	// ── changeSelection ────────────────────────────────────────────────────────

	function changeSelection(change:Int = 0)
	{
		if (songs.length == 0)
			return;
		FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.4);

		// ── Detener preview de música al navegar ──────────────────────────────
		// Si había una canción previsualizándose y el jugador scrollea, detener
		// la música y restaurar el menú. Evita que suenen dos audios a la vez
		// y que instPlaying quede desincronizado con curSelected.
		#if sys
		if (change != 0 && instPlaying != -1)
		{
			_cleanupPreviewSound();
			MusicManager.play('girlfriendsRingtone/girlfriendsRingtone', 0.7, false);
			instPlaying = -1;
			if (discSpr != null)
			{
				FlxTween.cancelTweensOf(discSpr);
				FlxTween.tween(discSpr, {x: FlxG.width + 50}, 0.3, {
					ease: FlxEase.expoIn,
					onComplete: function(_)
					{
						if (discSpr != null)
						{
							remove(discSpr);
							discSpr.destroy();
							discSpr = null;
						}
					}
				});
			}
		}
		#end

		curSelected += change;
		if (curSelected < 0)
			curSelected = songs.length - 1;
		if (curSelected >= songs.length)
			curSelected = 0;

		// Background color tween
		var newColor:Int = songs[curSelected].color;
		if (newColor != intendedColor)
		{
			if (colorTween != null)
				colorTween.cancel();
			intendedColor = newColor;
			colorTween = FlxTween.color(bgTint, 0.55, bgTint.color, intendedColor, {ease: FlxEase.sineInOut, onComplete: function(_) colorTween = null});
			cardAccent.color = intendedColor;
		}

		// Song list
		for (i in 0...iconArray.length)
			if (iconArray[i] != null)
				iconArray[i].alpha = 0.5;
		if (iconArray[curSelected] != null)
			iconArray[curSelected].alpha = 1;
		var bullShit = 0;
		for (item in grpSongs.members)
		{
			if (item == null)
				continue;
			item.targetY = bullShit - curSelected;
			bullShit++;
			item.alpha = (item.targetY == 0) ? 1.0 : 0.45;
			if (item.targetY == 0)
			{
				FlxTween.cancelTweensOf(item.scale);
				item.scale.set(1.04, 1.04);
				FlxTween.tween(item.scale, {x: 1, y: 1}, 0.22, {ease: FlxEase.expoOut});
			}
		}

		_updateAlbum(songs[curSelected]);
		_updateDifficultyStuff();
		FlxG.camera.zoom = 1.018;

		// changeDiff con suppressSpotlight=true para que NO llame _refreshSpotlight()
		// aquí — lo llamamos nosotros UNA sola vez al final.
		// Esto evita el doble-render del spotlight que causaba stutter perceptible
		// al scrollear rápido (HealthIcon.updateIcon, rank badge load, tweens).
		changeDiff(0, true);

		_refreshSpotlight(); // ← única llamada por selección

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onSelectionChanged', [curSelected]);
		StateScriptHandler.callOnScripts('onSongSelected', [songs[curSelected].songName]);
		#end
	}

	function _refreshSpotlight()
	{
		if (songs.length == 0)
			return;
		var song = songs[curSelected];
		spotlightTitle.setText(song.songName);

		// ── Artist — lee del SongMetadata (ya resuelto en songsSystem) ────────
		// Formato: "by <artista>"  si hay artista; si no, "from <weekName>" como antes.
		var artistStr = artist;
		if (artistStr != '')
		{
			spotlightArtist.text = 'by  $artistStr';
		}
		else
		{
			var weekName = '';
			// week name no longer available here; cleared in songsSystem refactor
			spotlightArtist.text = weekName.length > 0 ? 'from  $weekName' : '';
		}

		if (spotlightIcon == null)
		{
			// Primera vez: crear el icono y añadirlo
			spotlightIcon = new HealthIcon(song.songCharacter);
			spotlightIcon.scrollFactor.set();
			add(spotlightIcon);
		}
		else
		{
			// Reusar icono existente — updateIcon() cambia el atlas sin destruir el objeto
			FlxTween.cancelTweensOf(spotlightIcon.scale);
			spotlightIcon.updateIcon(song.songCharacter);
		}
		spotlightIcon.setGraphicSize(148, 148);
		spotlightIcon.updateHitbox();
		spotlightIcon.x = CARD_X + CARD_W - 180;
		spotlightIcon.y = CARD_Y;
		// Guardar la escala correcta calculada por setGraphicSize (puede diferir de 1.0
		// si el atlas tiene frames grandes), y animar desde 0.6× hasta esa escala.
		// Si se hiciera tween hasta {x:1, y:1}, el icono terminaría en tamaño incorrecto
		// y el offset quedaría desajustado, provocando que se desplace a la derecha/abajo.
		var _tgX = spotlightIcon.scale.x;
		var _tgY = spotlightIcon.scale.y;
		spotlightIcon.scale.set(_tgX * 0.6, _tgY * 0.6);
		spotlightIcon.updateHitbox(); // recalcular offset para la escala inicial del pop-in
		var _ico = spotlightIcon; // captura local para el closure del tween
		FlxTween.tween(spotlightIcon.scale, {x: _tgX, y: _tgY}, 0.35, {
			ease: FlxEase.elasticOut,
			type: ONESHOT,
			// updateHitbox() en cada frame mantiene el offset alineado con la escala
			// durante la animación, evitando el desplazamiento visual incorrecto.
			onUpdate: function(_)
			{
				if (_ico != null && _ico.alive && _ico.frames != null)
					_ico.updateHitbox();
			}
		});

		var diffSuffix = difficultyStuff.length > curDifficulty ? difficultyStuff[curDifficulty][1] : '';
		var acc = Highscore.getRating(song.songName, diffSuffix);
		var rank = _rankFromAcc(acc);

		FlxTween.cancelTweensOf(rankBadge);
		FlxTween.cancelTweensOf(rankBadgeBg);
		if (rank.length > 0)
		{
			try
			{
				// Usar PathsCache para badges de rank (pocas imágenes, muy repetidas)
				final _rankGfx = funkin.cache.PathsCache.instance.cacheGraphic('menu/ratings/$rank');
				if (_rankGfx != null && _rankGfx.bitmap != null)
					rankBadge.loadGraphic(_rankGfx);
				else
					rankBadge.loadGraphic(Paths.image('menu/ratings/$rank'));
				rankBadge.setGraphicSize(88, 88);
				rankBadge.updateHitbox();
				rankBadge.x = CARD_X + CARD_W - 122;
				rankBadge.y = CARD_Y + 146;
				rankBadge.alpha = 0;
				FlxTween.tween(rankBadge, {alpha: 1}, 0.3, {ease: FlxEase.quadOut});

				rankBadgeBg.color = _rankColor(rank);
				rankBadgeBg.x = CARD_X + CARD_W - 132;
				rankBadgeBg.y = CARD_Y + 136;
				rankBadgeBg.alpha = 0;
				FlxTween.tween(rankBadgeBg, {alpha: 0.18}, 0.3, {ease: FlxEase.quadOut});
			}
			catch (_)
			{
				rankBadge.alpha = 0;
				rankBadgeBg.alpha = 0;
			}
			var msg = _congratsMsg(rank);
			if (msg.length > 0)
			{
				congrats.text = msg;
				congrats.color = _rankColor(rank);
				congrats.alpha = 0;
				FlxTween.tween(congrats, {alpha: 1}, 0.4, {ease: FlxEase.quadOut, startDelay: 0.15});
			}
			else
			{
				congrats.alpha = 0;
				FlxTween.cancelTweensOf(congrats);
			}
		}
		else
		{
			rankBadge.alpha = 0;
			rankBadgeBg.alpha = 0;
			congrats.alpha = 0;
			FlxTween.cancelTweensOf(congrats);
		}

		intendedScore = Highscore.getScore(song.songName, diffSuffix);
		intendedRating = acc;
	}

	// ── changeDiff ─────────────────────────────────────────────────────────────

	/**
	 * @param suppressSpotlight  Pasar true cuando se llama desde changeSelection para
	 *                           evitar que _refreshSpotlight() se invoque dos veces
	 *                           (changeSelection ya lo llama después de changeDiff).
	 */
	function changeDiff(change:Int = 0, suppressSpotlight:Bool = false)
	{
		if (songs.length == 0)
			return;
		curDifficulty += change;
		if (curDifficulty < 0)
			curDifficulty = difficultyStuff.length - 1;
		if (curDifficulty >= difficultyStuff.length)
			curDifficulty = 0;
		#if !switch
		var diffSuffix = difficultyStuff.length > curDifficulty ? difficultyStuff[curDifficulty][1] : '';
		intendedScore = Highscore.getScore(songs[curSelected].songName, diffSuffix);
		intendedRating = Highscore.getRating(songs[curSelected].songName, diffSuffix);
		#end
		PlayState.storyDifficulty = curDifficulty;
		_rebuildDiffPills();
		if (!suppressSpotlight)
			_refreshSpotlight();
		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onDifficultyChanged', [curDifficulty]);
		#end
	}

	function _rebuildDiffPills()
	{
		if (diffPills == null)
			return;
		// ── Destruir los sprites de la vuelta anterior ────────────────────
		// diffPills.clear() solo los saca del grupo sin liberar sus bitmaps.
		// Cada píldora tiene un makeGraphic() propio; sin destroy() el bitmap
		// queda en el heap cada vez que se llama a _rebuildDiffPills().
		diffPills.forEach(function(s) { if (s != null) { remove(s, true); s.destroy(); } }, true);
		diffPills.clear();
		for (t in diffTexts)
		{
			remove(t);
			t.destroy();
		}
		diffTexts = [];
		var pillY = CARD_Y + 234;
		var pillH = 26;
		var pillW = 86;
		var gap = 6;
		var startX = CARD_X + 20;
		for (i in 0...difficultyStuff.length)
		{
			var label:String = difficultyStuff[i][0];
			var px = startX + i * (pillW + gap);
			var pill = new FlxSprite(px, pillY).makeGraphic(pillW, pillH, FlxColor.BLACK);
			pill.alpha = (i == curDifficulty) ? 0.75 : 0.30;
			pill.scrollFactor.set();
			diffPills.add(pill);
			var color:FlxColor = switch (label.toLowerCase())
			{
				case 'easy': FlxColor.fromString('#64ff64');
				case 'normal': FlxColor.fromString('#64ffff');
				case 'hard': FlxColor.fromString('#ff6464');
				case 'erect': FlxColor.fromString('#ff64ff');
				default: FlxColor.WHITE;
			};
			var txt = new FlxText(px, pillY + 5, pillW, label, 14);
			txt.setFormat(Paths.font('vcr.ttf'), 14, i == curDifficulty ? color : FlxColor.fromString('#778899'), CENTER);
			txt.scrollFactor.set();
			add(txt);
			diffTexts.push(txt);
		}
	}

	override function beatHit()
	{
		super.beatHit();

		_discBeatBump = 280.0; // deg/sec extra burst (decays in ~_onBeat)
	}

	// ── Helpers ────────────────────────────────────────────────────────────────

	function _updateDifficultyStuff():Void
	{
		if (songs == null || songs.length == 0)
			return;
		difficultyStuff = cast Song.getAvailableDifficulties(songs[curSelected].songName.toLowerCase());

		// ── Hook para scripts: permite filtrar dificultades por variante de personaje ──
		// El script recibe (songName, diffs) y devuelve el array filtrado.
		// Si devuelve null o un valor no-Array, se conserva el original.
		// Uso en freeplay_main.hx:
		//   function onDifficultyStuffBuilt(songName, diffs) { ... return filteredDiffs; }
		final _filtered = StateScriptHandler.callOnScriptsReturn('onDifficultyStuffBuilt', [songs[curSelected].songName, difficultyStuff], null);
		if (_filtered != null && Std.isOfType(_filtered, Array))
			difficultyStuff = cast _filtered;

		if (curDifficulty >= difficultyStuff.length)
			curDifficulty = difficultyStuff.length - 1;
		if (curDifficulty < 0)
			curDifficulty = 0;
	}

	function showError(message:String):Void
	{
		if (errorTween != null)
			errorTween.cancel();
		errorText.text = message;
		errorText.visible = true;
		errorText.alpha = 0;
		errorTween = FlxTween.tween(errorText, {alpha: 1}, 0.3, {
			ease: FlxEase.expoOut,
			onComplete: function(_)
			{
				errorTween = FlxTween.tween(errorText, {alpha: 0}, 0.5, {
					ease: FlxEase.expoIn,
					startDelay: 3.0,
					onComplete: function(_)
					{
						errorText.visible = false;
						errorTween = null;
					}
				});
			}
		});
	}

	public static function boundTo(value:Float, min:Float, max:Float):Float
	{
		if (value < min)
			return min;
		if (value > max)
			return max;
		return value;
	}

	public static function getCurrentWeekNumber():Int
	{
		return getWeekNumber(PlayState.storyWeek);
	}

	public static function getWeekNumber(num:Int):Int
	{
		return num; // group index from freeplayList.json
	}

	/**
	 * Stop and safely release the FlxSound from the active preview.
	 * Call stop(), remove(), and destroy() in order,
	 so that the OGG buffer is immediately eligible for garbage collection.
	 * It is idempotent: it is safe to call even if there is no active preview.
	*/
	function _cleanupPreviewSound():Void
	{
		if (_previewSound != null)
		{
			_previewSound.stop();
			FlxG.sound.list.remove(_previewSound, true);
			_previewSound.destroy();
			_previewSound = null;
		}
	}

	override function destroy()
	{
		// ── Cancelar tweens activos ANTES de nullear referencias ─────────────
		// Si no se cancelan, los callbacks de FlxTween se disparan después de
		// que el state fue destruido → crash o referencias a objetos muertos.
		if (colorTween != null)
		{
			colorTween.cancel();
			colorTween = null;
		}
		if (albumArt != null)    FlxTween.cancelTweensOf(albumArt);
		if (albumTextSpr != null) FlxTween.cancelTweensOf(albumTextSpr);

		// ── discSpr: puede estar en medio de un tween de salida ──────────────
		// El tween tiene un onComplete que intenta discSpr.destroy().
		// Si destroy() llega antes que el tween termine, el callback se ejecuta
		// sobre un objeto ya muerto. Cancelamos y destruimos aquí.
		if (discSpr != null)
		{
			FlxTween.cancelTweensOf(discSpr);
			remove(discSpr, true);
			discSpr.destroy();
			discSpr = null;
		}

		// ── FIX Bug 3a: iconArray acumulaba HealthIcon sin destruir ──────────
		// Flixel los destruye eventualmente, pero el GC no los recoge antes del
		// siguiente create() → la RAM sube con cada ciclo FreeplayState → PlayState.
		for (icon in iconArray)
			if (icon != null) icon.destroy();
		iconArray = [];

		// ── diffPills: clear() solo los saca del grupo sin destruirlos ────────
		// Cada píldora es un FlxSprite con bitmap propio (makeGraphic).
		// Sin destroy() explícito los bitmaps quedan vivos en el cache de OpenFL.
		if (diffPills != null)
		{
			diffPills.forEach(function(s) if (s != null) s.destroy(), true);
			diffPills.clear();
		}
		// diffTexts son FlxText añadidos directamente al state — super.destroy()
		// los limpia vía members, pero vaciamos la referencia local igualmente.
		diffTexts = [];

		freeplayData = null;

		songs = [];

		_cleanupPreviewSound();
		funkin.audio.CoreAudio.stopMenu();

		instPlaying = -1;

		super.destroy();
	}

	/**
	 * Resetea todo el estado estático de FreeplayState.
	 * Debe llamarse desde ModSelectorState al cambiar de mod, ANTES de
	 * switchState(new CacheState()), para que el nuevo mod arranque limpio:
	 *   - freeplayData = null  → se recargará desde el nuevo mod en el próximo create()
	 *   - coolColors   = []   → los colores son específicos de cada mod
	 *   - curSelected  = 0    → el índice viejo puede quedar fuera de rango
	 *   - curDifficulty = 1   → reset a "Normal"
	 */
	public static function resetStaticState():Void
	{
		freeplayData    = null;
		coolColors      = [];
		curSelected     = 0;
		curDifficulty   = 1;
		instPlaying     = -1;
		// Resetear dificultades al default estándar del engine.
		// difficultyStuff se sobreescribe en _buildDifficultyStuff() al cargar
		// una canción, pero si permaneciera con dificultades del mod anterior,
		// PauseSubState / Highscore.resolveSuffix() leerían sufijos incorrectos
		// antes de que FreeplayState haga el primer _buildDifficultyStuff().
		difficultyStuff = [['Easy', '-easy'], ['Normal', ''], ['Hard', '-hard']];
	}
}

// ── SongMetadata ──────────────────────────────────────────────────────────────

class SongMetadata
{
	public var songName:String = '';
	public var week:Int = 0;
	public var songCharacter:String = '';
	public var color:Int = -7179779;

	/** Índice dentro del array de canciones (para leer album, etc.). */
	public var songIndex:Int = 0;

	/** Clave de álbum para esta canción. */
	public var album:String = '';

	/** Clave de atlas de texto de álbum para esta canción. */
	public var albumText:String = '';

	public function new(song:String, week:Int, songCharacter:String, ?songIndex:Int = 0)
	{
		this.songName = song;
		this.week = week;
		this.songCharacter = songCharacter;
		this.songIndex = songIndex;
		this.color = -7179779;
	}
}

// ── FreeplaySongText ──────────────────────────────────────────────────────────
//
// Replaces Alphabet for song names in the freeplay list and spotlight.
// Renders with Funkin.otf + cyan GlowFilter (matching V-Slice CapsuleText feel).
// Has targetY for smooth scroll animation (same pattern as Alphabet.isMenuItem).
//

class FreeplaySongText extends FlxText
{
	/** Scroll target — same convention as Alphabet.targetY. */
	public var targetY:Float = 0;

	/** Set true for list items — enables targetY-based scroll. */
	public var isMenuItem:Bool = false;

	/** Maximum width before text clips. */
	public var maxWidth:Float = 380;

	/** Glow color (cyan by default, matches CapsuleText). */
	public var glowColor(default, set):FlxColor = FlxColor.fromString('#00ccff');

	function set_glowColor(v:FlxColor):FlxColor
	{
		glowColor = v;
		_applyFilters();
		return v;
	}

	static inline final FONT_SIZE_DEFAULT = 28;
	static inline final FONT_SIZE_LARGE = 50;

	public function new(x:Float, y:Float, text:String = '', fontSize:Int = FONT_SIZE_DEFAULT)
	{
		super(x, y, 0, text, fontSize);
		font = Paths.font('5by7.ttf');
		color = FlxColor.WHITE;
		antialiasing = true;
		_applyFilters();
	}

	/** Change displayed text and re-apply glow. */
	public function setText(value:String):Void
	{
		this.text = value;
		_applyFilters();
	}

	function _applyFilters():Void
	{
		var glow = new openfl.filters.GlowFilter(glowColor, 1.0, 6, 6, 200, BitmapFilterQuality.MEDIUM);
		textField.filters = [glow];
	}
}
