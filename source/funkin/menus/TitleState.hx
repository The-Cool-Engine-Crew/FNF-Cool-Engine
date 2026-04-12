package funkin.menus;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.group.FlxGroup;
import flixel.input.gamepad.FlxGamepad;
import funkin.debug.charting.ChartingState;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import lime.app.Application;
import funkin.data.Conductor;
import funkin.states.OutdatedSubState;
import ui.Alphabet;
import funkin.scripting.StateScriptHandler;
import animationdata.FunkinSprite;
import funkin.transitions.StateTransition;
import funkin.audio.MusicManager;
import haxe.Json;
import funkin.data.SaveData;

using StringTools;

/**
 * Estructura de datos de titlescreen.json
 *
 * Ruta: assets/data/titlescreen.json
 */
typedef TitleBeat = {
	var beat:Int;
	@:optional var texts:Array<String>;
	@:optional var clear:Bool;
	@:optional var random:Bool;
	@:optional var randomSecond:Bool;
	@:optional var skipIntro:Bool;
}

typedef TitleScreenData = {
	@:optional var bpm:Float;
	@:optional var introBeats:Array<TitleBeat>;
	@:optional var randomLines:Array<Array<String>>;
}

class TitleState extends funkin.states.MusicBeatState
{
	/** Puesto a false por ModSelectorState al cambiar de mod para reproducir el intro del nuevo mod. */
	public static var initialized:Bool = false;

	var blackScreen:FlxSprite;
	var credGroup:FlxGroup;
	var textGroup:FlxGroup;

	/** Datos cargados de assets/data/titlescreen.json */
	var titleData:TitleScreenData = null;
	/** Lista de pares de strings aleatorios (del JSON). */
	var _randomLines:Array<Array<String>> = [];
	/** Índice de la línea random elegida este ciclo. */
	var _randomIdx:Int = 0;

	// ── Tween refs para evitar acumulación ───────────────────────────────
	var _cameraZoomTween:FlxTween = null;
	var _logoAngleTween:FlxTween  = null;
	var _logoYTween:FlxTween      = null;
	// ─────────────────────────────────────────────────────────────────────

	static function _loadTitleData():TitleScreenData
	{
		var paths:Array<String> = [];
		#if sys
		var modRoot = mods.ModManager.modRoot();
		if (modRoot != null)
			paths.push(modRoot + '/data/titlescreen.json');
		paths.push('assets/data/titlescreen.json');
		for (p in paths)
		{
			if (sys.FileSystem.exists(p))
			{
				try { return cast haxe.Json.parse(sys.io.File.getContent(p)); }
				catch (e:Dynamic) { trace('[TitleState] Error parseando $p: $e'); }
			}
		}
		#end
		return null;
	}

	override public function create():Void
	{
		super.create();

		#if HSCRIPT_ALLOWED
		StateScriptHandler.init();
		StateScriptHandler.loadStateScripts('TitleState', this);
		StateScriptHandler.callOnScripts('onCreate', []);
		#end

		bg = new FlxSprite().loadGraphic(Paths.getGraphic('menu/menuBGtitle'));
		var bgScale:Float = Math.max(FlxG.width / bg.width, FlxG.height / bg.height);
		bg.scale.set(bgScale, bgScale);
		bg.updateHitbox();
		bg.screenCenter();
		add(bg);

		if (SaveData.data.weekUnlocked != null)
		{
			if (StoryMenuState.weekUnlocked.length < 4)
				StoryMenuState.weekUnlocked.insert(0, true);

			if (!StoryMenuState.weekUnlocked[0])
				StoryMenuState.weekUnlocked[0] = true;
		}

		#if FREEPLAY
		StateTransition.switchState(funkin.scripting.ScriptBridge.resolveState('FreeplayState') ?? new FreeplayState());
		#elseif CHARTING
		StateTransition.switchState(new ChartingState());
		#elseif MAINMENU
		StateTransition.switchState(funkin.scripting.ScriptBridge.resolveState('MainMenuState') ?? new MainMenuState());
		#else
		titleData = _loadTitleData();
		if (titleData != null && titleData.randomLines != null && titleData.randomLines.length > 0)
			_randomLines = titleData.randomLines;
		else
			_randomLines = [
				['Thx PabloelproxD210', 'for the Android port LOL'],
				['Thx Chase for...', 'SOMTHING'],
				['Thx TheStrexx for', "you'r 3 commits :D"]
			];
		startIntro();
		#end

		#if HSCRIPT_ALLOWED
		StateScriptHandler.refreshStateFields(this);
		StateScriptHandler.callOnScripts('postCreate', []);
		#end
	}

	// FIX: promoted from local var inside create() to class field so that
	// StateScriptHandler.refreshStateFields() / Type.getInstanceFields() can
	// expose it to mod scripts.
	var bg:FlxSprite;

	var logoBl:FunkinSprite;
	var gfDance:FunkinSprite;
	var danceLeft:Bool = false;
	var titleText:FunkinSprite;
	var transitioning:Bool = false;

	function startIntro()
	{
		persistentUpdate = true;

		logoBl = new FunkinSprite(-150, -100);
		logoBl.loadAsset('titlestate/logoBumpin');
		logoBl.antialiasing = true;
		logoBl.addAnim('bump', 'logo bumpin', 24);
		logoBl.playAnim('bump');
		logoBl.updateHitbox();

		gfDance = new FunkinSprite(FlxG.width * 0.4, FlxG.height * 0.07);
		gfDance.loadAsset('titlestate/gfDanceTitle');
		gfDance.addAnim('danceLeft',  'gfDance', 24, false, [30, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]);
		gfDance.addAnim('danceRight', 'gfDance', 24, false, [15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29]);
		gfDance.antialiasing = true;
		add(gfDance);
		add(logoBl);

		titleText = new FunkinSprite(100, FlxG.height * 0.8);
		titleText.loadAsset('titlestate/titleEnter');
		titleText.addAnim('idle',  "Press Enter to Begin", 24);
		titleText.addAnim('press', "ENTER PRESSED", 24);
		titleText.antialiasing = true;
		titleText.playAnim('idle');
		titleText.updateHitbox();
		add(titleText);

		credGroup = new FlxGroup();
		add(credGroup);
		textGroup = new FlxGroup();

		blackScreen = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, FlxColor.BLACK);
		credGroup.add(blackScreen);

		funkin.system.CursorManager.hide();

		if (initialized)
		{
			MusicManager.play('freakyMenu', 0.7);
			Conductor.changeBPM(titleData != null && titleData.bpm != null ? titleData.bpm : 102);
			skipIntro();
		}
		else
		{
			transIn  = null;
			transOut = null;

			MusicManager.playWithFade('freakyMenu', 0.7, 4.0);
			Conductor.changeBPM(titleData != null && titleData.bpm != null ? titleData.bpm : 102);
			initialized = true;
		}
	}

	override function update(elapsed:Float)
	{
		if (FlxG.sound.music != null)
			Conductor.songPosition = FlxG.sound.music.time;

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onUpdate', [elapsed]);
		#end

		if (FlxG.keys.justPressed.F11)
			FlxG.fullscreen = !FlxG.fullscreen;

		var pressedEnter:Bool = FlxG.keys.justPressed.ENTER;

		#if mobile
		for (touch in FlxG.touches.list)
		{
			if (touch.justPressed)
			{
				pressedEnter = true;
				break; // FIX: no necesitamos seguir iterando
			}
		}
		#end

		var gamepad:FlxGamepad = FlxG.gamepads.lastActive;
		if (gamepad != null)
		{
			if (gamepad.justPressed.START)
				pressedEnter = true;

			#if switch
			if (gamepad.justPressed.B)
				pressedEnter = true;
			#end
		}

		if (pressedEnter && !transitioning && skippedIntro)
		{
			if (titleText != null)
				titleText.playAnim('press');

			if (SaveData.data.flashing)
				FlxG.camera.flash(FlxColor.WHITE, 1);
			FlxG.sound.play(Paths.sound('menus/confirmMenu'), 0.7);

			transitioning = true;

			new FlxTimer().start(2, function(tmr:FlxTimer)
			{
				var http = new haxe.Http("https://raw.githubusercontent.com/Manux123/FNF-Cool-Engine/master/ver.thing");
				var version:String = Application.current.meta.get('version') ?? '';

				http.onData = function(data:String)
				{
					var normalized:String = data.replace('\r\n', '\n').replace('\r', '\n');

					var firstNewline:Int  = normalized.indexOf('\n');
					var versionRaw:String = firstNewline >= 0
						? normalized.substring(0, firstNewline)
						: normalized;

					var latestVersion:String = versionRaw.replace('-', '').trim();

					var changelog:String = firstNewline >= 0
						? normalized.substring(firstNewline + 1).trim()
						: '';

					if (latestVersion.length > 0
						&& !version.contains(latestVersion)
						&& !OutdatedSubState.leftState)
					{
						trace('[TitleState] Outdated Version: local=$version latest=$latestVersion');
						OutdatedSubState.daVersionNeeded   = latestVersion;
						OutdatedSubState.daChangelogNeeded = changelog;
						OutdatedSubState.downloadUrl       = 'https://github.com/The-Cool-Engine-Crew/FNF-Cool-Engine/releases/latest';
						StateTransition.switchState(new OutdatedSubState());
					}
					else
					{
						StateTransition.switchState(funkin.scripting.ScriptBridge.resolveState('MainMenuState') ?? new MainMenuState());
					}
				}

				http.onError = function(error)
				{
					trace('[TitleState] Error al comprobar versión: $error');
					StateTransition.switchState(funkin.scripting.ScriptBridge.resolveState('MainMenuState') ?? new MainMenuState());
				}

				http.request();
			});
		}

		if (pressedEnter && !skippedIntro)
			skipIntro();

		super.update(elapsed);

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onUpdatePost', [elapsed]);
		#end
	};

	function createCoolText(textArray:Array<String>)
	{
		for (i in 0...textArray.length)
		{
			var money:Alphabet = new Alphabet(0, 0, textArray[i], true, false);
			money.screenCenter(X);
			money.y += (i * 60) + 200;
			credGroup.add(money);
			textGroup.add(money);
		}
	}

	function addMoreText(text:String, yOffset:Float = 0)
	{
		var coolText:Alphabet = new Alphabet(0, 0, text, true, false);
		coolText.screenCenter(X);
		if (yOffset != 0)
			coolText.y -= yOffset;
		credGroup.add(coolText);
		textGroup.add(coolText);

		FlxTween.tween(coolText, {y: coolText.y + (textGroup.length * 60) + 150}, 0.4, {
			ease: FlxEase.expoInOut
		});
	}

	function deleteCoolText()
	{
		while (textGroup.members.length > 0)
		{
			var textItem = textGroup.members[0];
			FlxTween.cancelTweensOf(textItem);
			credGroup.remove(textItem, true);
			textGroup.remove(textItem, true);
			if (textItem != null)
				textItem.destroy();
		}
	}

	override function beatHit()
	{
		super.beatHit();

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onBeatHit', [curBeat]);
		#end

		logoBl.playAnim('bump');
		danceLeft = !danceLeft;

		if (danceLeft)
			gfDance.playAnim('danceRight');
		else
			gfDance.playAnim('danceLeft');

		FlxG.log.add(curBeat);

		if (_cameraZoomTween != null)
			_cameraZoomTween.cancel();
		_cameraZoomTween = FlxTween.tween(FlxG.camera, {zoom: 1.02}, 0.3, {ease: FlxEase.quadOut, type: BACKWARD});

		switch (curBeat)
		{
			default:
				if (titleData != null && titleData.introBeats != null)
				{
					for (entry in titleData.introBeats)
					{
						if (entry.beat != curBeat) continue;
						if (entry.clear == true)        deleteCoolText();
						if (entry.skipIntro == true)    { skipIntro(); break; }
						if (entry.random == true)
						{
							_randomIdx = FlxG.random.int(0, _randomLines.length - 1);
							if (_randomLines[_randomIdx].length > 0)
								createCoolText([_randomLines[_randomIdx][0]]);
						}
						if (entry.randomSecond == true)
						{
							if (_randomLines[_randomIdx].length > 1)
								addMoreText(_randomLines[_randomIdx][1]);
						}
						if (entry.texts != null)
						{
							if (textGroup.length == 0)
								createCoolText(entry.texts);
							else
								for (t in entry.texts) addMoreText(t);
						}
						break;
					}
				}
				else
				{
					switch (curBeat)
					{
						case 0:  deleteCoolText();
						case 1:  createCoolText(['ninjamuffin99', 'phantomArcade', 'kawaisprite', 'evilsk8er']);
						case 3:  addMoreText('present');
						case 4:  deleteCoolText();
						case 5:  createCoolText(['Cool Engine Team']);
						case 7:
							addMoreText('Manux');
							addMoreText('Juanen100');
							addMoreText('MrClogsworthYt');
							addMoreText('JloorMC');
							addMoreText('Overcharged Dev');
						case 8:  deleteCoolText();
						case 9:
							_randomIdx = FlxG.random.int(0, _randomLines.length - 1);
							createCoolText([_randomLines[_randomIdx][0]]);
						case 11:
							if (_randomLines[_randomIdx].length > 1)
								addMoreText(_randomLines[_randomIdx][1]);
						case 12: deleteCoolText();
						case 13: addMoreText('Friday');
						case 14: addMoreText('Night');
						case 15: addMoreText('Funkin');
						case 16: skipIntro();
					}
				}
		}
	}

	var skippedIntro:Bool = false;

	function skipIntro():Void
	{
		if (!skippedIntro)
		{
			// FIX: limpiar todos los textos pendientes con sus tweens antes de saltar
			deleteCoolText();

			if (SaveData.data.flashing)
				FlxG.camera.flash(FlxColor.WHITE, 4);
			remove(credGroup);

			// FIX: cancelar tweens de logo previos antes de arrancar los de skipIntro
			if (_logoYTween != null)     _logoYTween.cancel();
			if (_logoAngleTween != null) _logoAngleTween.cancel();

			_logoYTween = FlxTween.tween(logoBl, {y: -100}, 1.4, {ease: FlxEase.expoInOut});

			logoBl.angle = -4;

			// FIX: guardar referencia del FlxTimer (antes se perdía y podía filtrar)
			// FIX: el timer original tenía loops=0, lo que crea un loop infinito.
			//      Con loops=1 se ejecuta una sola vez y se destruye correctamente.
			new FlxTimer().start(0.01, function(tmr:FlxTimer)
			{
				if (_logoAngleTween != null) _logoAngleTween.cancel();
				_logoAngleTween = FlxTween.angle(logoBl, logoBl.angle, 4, 4, {ease: FlxEase.quartInOut});
			}, 1);

			skippedIntro = true;
		}
	}

	override function destroy()
	{
		if (_cameraZoomTween != null) _cameraZoomTween.cancel();
		if (_logoYTween != null)      _logoYTween.cancel();
		if (_logoAngleTween != null)  _logoAngleTween.cancel();

		if (textGroup != null)
			deleteCoolText();

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onDestroy', []);
		StateScriptHandler.clearStateScripts();
		#end

		super.destroy();
	}
}