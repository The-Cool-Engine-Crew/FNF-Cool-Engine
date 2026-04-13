package funkin.menus.substate;

import funkin.gameplay.controls.Controls.Control;
import flixel.FlxG;
import flixel.FlxSprite;
import funkin.transitions.StickerTransition;
import flixel.group.FlxGroup.FlxTypedGroup;
import funkin.gameplay.GameState;
import flixel.sound.FlxSound;
import flixel.text.FlxText;
import funkin.scripting.StateScriptHandler;
import funkin.transitions.StateTransition;
import flixel.tweens.FlxEase;
import funkin.gameplay.PlayState;
import funkin.data.CoolUtil;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import ui.Alphabet;
import funkin.cutscenes.VideoManager;
import funkin.data.Song;

using StringTools;

// ─────────────────────────────────────────────────────────────────────────────
// Modos del menú de pausa
// ─────────────────────────────────────────────────────────────────────────────
enum PauseMode {
	Standard; // Gameplay normal
	Difficulty; // Submenú de cambio de dificultad
	Cutscene; // Pausado durante cutscene de video
}

class PauseSubState extends funkin.states.MusicBeatSubstate {
	var grpMenuShit:FlxTypedGroup<Alphabet>;

	// Entradas base para cada modo
	static final ENTRIES_STANDARD:Array<String> = ['Resume', 'Restart Song', 'Change Difficulty', 'Options', 'Exit to menu'];
	static final ENTRIES_CUTSCENE:Array<String> = ['Resume', 'Skip Cutscene', 'Exit to menu'];

	var menuItems:Array<String> = [];
	var curSelected:Int = 0;
	var currentMode:PauseMode = Standard;

	/** true si se abrió durante una cutscene de video. */
	var isCutsceneMode:Bool = false;

	/**
	 * Guard contra spam de ACCEPT: una vez que se eligió una opción
	 * no se procesa ninguna otra pulsación hasta que el substate se destruya.
	 */
	var _acted:Bool = false;

	/**
	 * Cuando alguna ruta de salida ya gestionó el audio (resume o deja que
	 * la transición lo maneje) se pone a true para que destroy() no llame
	 * FlxG.sound.resume() de más y arranque las vocales en medio de la transición.
	 */
	var _soundHandled:Bool = false;

	var pauseMusic:FlxSound;

	// Visual elements
	var bg:FlxSprite;
	var levelInfo:FlxText;
	var levelDifficulty:FlxText;
	var levelDeaths:FlxText;
	var levelAuthor:FlxText;
	var helpText:FlxText;

	var _pauseCam:flixel.FlxCamera;

	/**
	 * When paused during a cutscene the video bitmap sits ABOVE the normal
	 * Flixel camera canvases in the display list (added via addChildBelowMouse).
	 * A camera that is added to FlxG.cameras AFTER the video will have its
	 * flashSprite inserted above the video → renders on top of it.
	 * We track whether we created and own this camera so we can remove it cleanly.
	 */
	var _ownedCam:Bool = false;

	/**
	 * @param cutsceneMode  Pasar `true` cuando se pausa durante un video en curso.
	 */
	public function new(?cutsceneMode:Bool = false) {
		super();

		isCutsceneMode = cutsceneMode;

		if (isCutsceneMode && VideoManager.isPlaying) {
			_pauseCam = new flixel.FlxCamera();
			_pauseCam.bgColor = flixel.util.FlxColor.TRANSPARENT;
			_pauseCam.zoom = 1.0;
			FlxG.cameras.add(_pauseCam, false);
			_ownedCam = true;
		} else {
			// Normal mode: cámara propia para garantizar zoom=1 siempre.
			_pauseCam = new flixel.FlxCamera();
			_pauseCam.bgColor = flixel.util.FlxColor.TRANSPARENT;
			_pauseCam.zoom = 1.0;
			FlxG.cameras.add(_pauseCam, false);
			_ownedCam = true;
		}
		cameras = [_pauseCam];

		_cleanSoundList();

		// Música de pausa
		pauseMusic = new FlxSound().loadEmbedded(Paths.music('breakfast'), true, true);
		pauseMusic.volume = 0;
		pauseMusic.play(false, FlxG.random.int(0, Std.int(pauseMusic.length / 2)));
		FlxG.sound.list.add(pauseMusic);

		// Fondo semitransparente (1×1 escalado para no alocar un bitmap enorme)
		bg = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		bg.setGraphicSize(FlxG.width, FlxG.height);
		bg.updateHitbox();
		bg.alpha = 0;
		bg.scrollFactor.set();
		bg.cameras = [_pauseCam];
		add(bg);

		var rawSongName:String = PlayState.SONG.song;
		var formattedSongName:String = rawSongName.charAt(0).toUpperCase() + rawSongName.substring(1);

		// Info de la canción (esquina superior derecha)
		levelInfo = new FlxText(FlxG.width - 400, 20, 380, formattedSongName, 32);
		levelInfo.scrollFactor.set();
		levelInfo.setFormat(Paths.font("Funkin.otf"), 32, FlxColor.WHITE, RIGHT, OUTLINE, FlxColor.BLACK);
		levelInfo.borderSize = 2;
		levelInfo.antialiasing = true;
		levelInfo.updateHitbox();
		levelInfo.alpha = 0;
		levelInfo.cameras = [_pauseCam];
		add(levelInfo);

		levelDifficulty = new FlxText(FlxG.width - 400, 60, 380, "Difficulty: " + CoolUtil.difficultyString(), 24);
		levelDifficulty.scrollFactor.set();
		levelDifficulty.setFormat(Paths.font('Funkin.otf'), 32, FlxColor.WHITE, RIGHT, OUTLINE, FlxColor.BLACK);
		levelDifficulty.borderSize = 1.5;
		levelDifficulty.antialiasing = true;
		levelDifficulty.updateHitbox();
		levelDifficulty.alpha = 0;
		levelDifficulty.cameras = [_pauseCam];
		add(levelDifficulty);

		levelDeaths = new FlxText(FlxG.width - 400, 95, 380, "Deaths: " + GameState.deathCounter, 20);
		levelDeaths.scrollFactor.set();
		levelDeaths.setFormat(Paths.font('Funkin.otf'), 32, FlxColor.WHITE, RIGHT, OUTLINE, FlxColor.BLACK);
		levelDeaths.borderSize = 1.5;
		levelDeaths.antialiasing = true;
		levelDeaths.alpha = 0;
		levelDeaths.cameras = [_pauseCam];
		add(levelDeaths);

		levelAuthor = new FlxText(FlxG.width - 400, 125, 380, "Artist: " + GameState.listArtist, 20);
		levelAuthor.scrollFactor.set();
		levelAuthor.setFormat(Paths.font('Funkin.otf'), 32, FlxColor.WHITE, RIGHT, OUTLINE, FlxColor.BLACK);
		levelAuthor.borderSize = 1.5;
		levelAuthor.antialiasing = true;
		levelAuthor.alpha = 0;
		levelAuthor.cameras = [_pauseCam];
		add(levelAuthor);

		// Tweens de entrada
		FlxTween.tween(bg, {alpha: 0.7}, 0.4, {ease: FlxEase.quartInOut});
		FlxTween.tween(levelInfo, {alpha: 1, x: levelInfo.x + 10}, 0.4, {ease: FlxEase.quartInOut, startDelay: 0.3});
		FlxTween.tween(levelDifficulty, {alpha: 1, x: levelDifficulty.x + 10}, 0.4, {ease: FlxEase.quartInOut, startDelay: 0.4});
		FlxTween.tween(levelDeaths, {alpha: 1, x: levelDeaths.x + 10}, 0.4, {ease: FlxEase.quartInOut, startDelay: 0.5});
		FlxTween.tween(levelAuthor, {alpha: 1, x: levelAuthor.x + 10}, 0.4, {ease: FlxEase.quartInOut, startDelay: 0.6});

		// Grupo de ítems del menú
		grpMenuShit = new FlxTypedGroup<Alphabet>();
		grpMenuShit.cameras = [_pauseCam];
		add(grpMenuShit);

		// Texto de ayuda (parte inferior)
		helpText = new FlxText(20, FlxG.height - 40, FlxG.width - 40, "ENTER: Select  |  ARROWS: Navigate  |  ESC: Resume", 16);
		helpText.setFormat(Paths.font("Funkin.otf"), 22, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		helpText.scrollFactor.set();
		helpText.antialiasing = true;
		helpText.alpha = 0;
		helpText.cameras = [_pauseCam];
		add(helpText);

		FlxTween.tween(helpText, {alpha: 0.85}, 0.4, {ease: FlxEase.quartInOut, startDelay: 0.7});

		switchMode(isCutsceneMode ? Cutscene : Standard);

		#if mobileC
		addTouchMenuControls(true, false);
		#end
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Update
	// ─────────────────────────────────────────────────────────────────────────

	override function update(elapsed:Float) {
		if (pauseMusic != null && pauseMusic.volume < 0.5)
			pauseMusic.volume += 0.01 * elapsed;

		super.update(elapsed);

		if (controls.UP_P)
			changeSelection(-1);
		if (controls.DOWN_P)
			changeSelection(1);

		// ESC / BACK: volver al menú padre o hacer resume
		if (FlxG.keys.justPressed.ESCAPE || controls.BACK) {
			if (currentMode == Difficulty)
				switchMode(Standard);
			else
				_doResume();
			return;
		}

		if (controls.ACCEPT && !OptionsMenuState.isOpenOptions) {
			// Guard contra spam: ignorar si ya se eligió una opción
			if (_acted)
				return;
			_acted = true;

			var daSelected:String = menuItems[curSelected];

			#if HSCRIPT_ALLOWED
			StateScriptHandler.callOnScripts('onMenuItemSelected', [daSelected, curSelected]);
			#end

			switch (daSelected) {
				case "Resume":
					_doResume();

				case "Restart Song":
					if (PlayState.instance != null) {
						// BUGFIX: Poner paused=false ANTES de close() para que
						// PlayState.closeSubState() no llame a resyncVocals() mientras
						// el audio ya fue pausado por startRewindRestart().
						PlayState.instance.paused = false;
						PlayState.instance.startRewindRestart();
					}
					_soundHandled = true; // startRewindRestart gestiona el audio
					close();

				case "Skip Song":
					if (PlayState.instance != null)
						PlayState.instance.endSong();
					_soundHandled = true;

				case "Change Difficulty":
					_acted = false; // permitir ACCEPT dentro del submenú de dificultad
					switchMode(Difficulty);

				case "Options":
					_acted = false; // se abre un substate y puede volver
					OptionsMenuState.fromPause = true;
					openSubState(new OptionsMenuState());

				case "Exit to menu":
					PlayState.isPlaying = false;
					PlayState.isBotPlay = false;
					// BUGFIX: Poner paused=false ANTES de la transición para que
					// PlayState.closeSubState() no llame a resyncVocals() durante el
					// destroy del estado, lo que provocaba un crash al intentar
					// reproducir música en un estado inválido.
					if (PlayState.instance != null)
						PlayState.instance.paused = false;
					_soundHandled = true; // la transición gestiona el audio, no queremos resume aquí
					if (StickerTransition.enabled) {
						if (PlayState.isStoryMode) {
							StickerTransition.setCurrentContext(PlayState.storyWeek, PlayState.storyPlaylist[0]);
							StickerTransition.start(() -> {
								StateTransition.switchState(new StoryMenuState());
							});
						} else {
							StickerTransition.setCurrentContext(PlayState.storyWeek, PlayState.storyPlaylist[0]);
							StickerTransition.start(() -> {
								StateTransition.switchState(new FreeplayState());
							});
						}
					}

				case "Skip Cutscene":
					_skipCutscene();
					_soundHandled = true;

				case "Back":
					_acted = false; // volver al menú anterior → permitir más acciones
					switchMode(Standard);

				default:
					// Toggle Bot Play (devmode)
					if (daSelected.startsWith("BotPlay")) {
						PlayState.isBotPlay = !PlayState.isBotPlay;
						// Actualizar label en el menú
						menuItems[curSelected] = PlayState.isBotPlay ? "BotPlay ON" : "BotPlay OFF";
						_rebuildMenu();
						_acted = false; // permitir más acciones en este menú
						return;
					}
					// Selección de dificultad generada dinámicamente
					if (currentMode == Difficulty) {
						_soundHandled = true; // FlxG.resetState() o close() gestionan el audio
						_applyDifficulty(daSelected);
					}
			}
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Cambio de modo
	// ─────────────────────────────────────────────────────────────────────────

	function switchMode(mode:PauseMode):Void {
		currentMode = mode;
		curSelected = 0;

		switch (mode) {
			case Standard:
				menuItems = ENTRIES_STANDARD.copy();
				// Añadir "Skip Song" en modo historia con playlist > 1
				if (PlayState.storyPlaylist.length > 1 && PlayState.isStoryMode)
					menuItems.insert(2, "Skip Song");
				// Añadir "Bot Play" si el Developer Mode está activo
				if (mods.ModManager.developerMode) {
					var botLabel = PlayState.isBotPlay ? "BotPlay ON" : "BotPlay OFF";
					menuItems.insert(menuItems.length - 3, botLabel);
				}

			case Cutscene:
				menuItems = ENTRIES_CUTSCENE.copy();

			case Difficulty:
				menuItems = [];
				// Usar las dificultades reales de la canción actual (detectadas por
				// FreeplayState/Song.getAvailableDifficulties), no las 3 hardcodeadas.
				final diffs = funkin.menus.FreeplayState.difficultyStuff;
				for (i in 0...diffs.length) {
					// diffs[i][0] = label de display (ej: "Easy", "Nightmare")
					var label:String = diffs[i][0];
					if (i == PlayState.storyDifficulty)
						label += '  ◀';
					menuItems.push(label);
				}
				menuItems.push('Back');
		}

		_rebuildMenu();
	}

	function _rebuildMenu():Void {
		if (grpMenuShit != null) {
			for (item in grpMenuShit.members)
				if (item != null)
					FlxTween.cancelTweensOf(item);
			grpMenuShit.clear();
		}

		for (i in 0...menuItems.length) {
			var songText:Alphabet = new Alphabet(0, (70 * i) + 30, menuItems[i], true, false);
			songText.isMenuItem = true;
			songText.targetY = i;
			songText.alpha = 0;
			grpMenuShit.add(songText);

			var targetAlpha = (i == curSelected) ? 1.0 : 0.6;
			FlxTween.tween(songText, {alpha: targetAlpha}, 0.3, {
				ease: FlxEase.quartOut,
				startDelay: 0.1 + (i * 0.04)
			});
		}

		changeSelection(0, true);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Acciones
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Resume: si hay video pausado, lo reanuda.
	 * Solo llama FlxG.sound.resume() si la pausa vino de gameplay normal
	 * (no de un video), para no arrancar la música en medio de una cutscene.
	 */
	function _doResume():Void {
		_soundHandled = true;
		if (isCutsceneMode && VideoManager.isPlaying) {
			// Volvemos a un video: solo reanudar el video.
			// FlxG.sound.pause/resume NO se llamaron, así que no hay nada que restaurar.
			VideoManager.resume();
		} else {
			// Pausa normal de gameplay: restaurar todos los sonidos.
			FlxG.sound.resume();
		}

		close();

		if (PlayState.instance != null)
			PlayState.instance.paused = false;
	}

	/**
	 * Skip cutscene: para el video y reanuda el gameplay.
	 * La música empezará cuando el countdown termine normalmente.
	 */
	function _skipCutscene():Void {
		// Restaurar estado de PlayState ANTES de stop() para que el callback
		// de finishCallback (que llama startCountdown) encuentre el estado correcto.
		if (PlayState.instance != null) {
			PlayState.instance.inCutscene = false;
			PlayState.instance.canPause = true;
			PlayState.instance.paused = false;
		}

		// stop() → kill() → finishCallback() → startCountdown() / continueAfterSong()
		if (VideoManager.isPlaying)
			VideoManager.stop();

		close();
	}

	/**
	 * Aplica la dificultad elegida del submenú y reinicia la canción.
	 */
	function _applyDifficulty(label:String):Void {
		// Quitar el marcador "  ◀" si aparece
		var cleanLabel = label.split("  ◀")[0];
		final diffs = funkin.menus.FreeplayState.difficultyStuff;
		var idx = -1;
		for (i in 0...diffs.length)
			if (diffs[i][0] == cleanLabel) {
				idx = i;
				break;
			}
		if (idx == -1)
			return;

		if (idx == PlayState.storyDifficulty) {
			// Misma dificultad: restart normal sin recargar chart
			if (PlayState.instance != null)
				PlayState.instance.startRewindRestart();
			close();
			return;
		}

		PlayState.storyDifficulty = idx;

		// Sufijo real de la dificultad elegida (ej: "-nightmare", "", "-hard")
		final suffix = diffs[idx][1];

		// Recargar chart con la nueva dificultad
		var songId = PlayState.SONG.song.toLowerCase();
		PlayState.SONG = Song.loadFromJson(songId + suffix, songId);

		// Actualizar etiqueta antes de resetear
		if (levelDifficulty != null)
			levelDifficulty.text = "Difficulty: " + CoolUtil.difficultyString();

		// Reset completo del state para aplicar el nuevo chart
		if (PlayState.instance != null)
			PlayState.instance.paused = false;
		close(); // cerrar el substate antes de resetear
		FlxG.resetState();
	}

	// ─────────────────────────────────────────────────────────────────────────
	// closeSubState override
	// ─────────────────────────────────────────────────────────────────────────

	override function closeSubState():Void {
		super.closeSubState();
		if (funkin.menus.OptionsMenuState.pendingRewind) {
			funkin.menus.OptionsMenuState.pendingRewind = false;
			if (PlayState.instance != null)
				FlxG.resetState();
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Destroy
	// ─────────────────────────────────────────────────────────────────────────

	override function destroy() {
		if (bg != null) {
			FlxTween.cancelTweensOf(bg);
			bg = null;
		}
		if (levelInfo != null) {
			FlxTween.cancelTweensOf(levelInfo);
			levelInfo = null;
		}
		if (levelDifficulty != null) {
			FlxTween.cancelTweensOf(levelDifficulty);
			levelDifficulty = null;
		}
		if (levelDeaths != null) {
			FlxTween.cancelTweensOf(levelDeaths);
			levelDeaths = null;
		}
		if (levelAuthor != null) {
			FlxTween.cancelTweensOf(levelAuthor);
			levelAuthor = null;
		}
		if (helpText != null) {
			FlxTween.cancelTweensOf(helpText);
			helpText = null;
		}

		if (grpMenuShit != null) {
			for (item in grpMenuShit.members) {
				if (item != null) {
					FlxTween.cancelTweensOf(item);
					FlxTween.cancelTweensOf(item.scale);
				}
			}
			grpMenuShit = null;
		}

		if (pauseMusic != null) {
			pauseMusic.stop();
			FlxG.sound.list.remove(pauseMusic, true);
			pauseMusic.destroy();
			pauseMusic = null;
		}

		super.destroy();

		// Remove the camera we created (cutscene mode only) so it doesn't leak.
		if (_ownedCam && _pauseCam != null) {
			FlxG.cameras.remove(_pauseCam, true);
			_pauseCam = null;
			_ownedCam = false;
		}

		// Seguridad: si el substate se destruyó sin pasar por Resume/Exit
		// Solo restaurar sonido si no fue gestionado ya por alguna ruta de salida
		// ni hay un video activo (la música la gestiona VideoManager/startSong).
		if (!_soundHandled && !VideoManager.isPlaying)
			FlxG.sound.resume();
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Helpers privados
	// ─────────────────────────────────────────────────────────────────────────

	private static function _cleanSoundList():Void {
		var i = FlxG.sound.list.length - 1;
		while (i >= 0) {
			var s = FlxG.sound.list.members[i];
			if (s != null && !s.alive)
				FlxG.sound.list.remove(s, true);
			i--;
		}
	}

	function changeSelection(change:Int = 0, silent:Bool = false):Void {
		if (grpMenuShit == null)
			return;

		if (!silent)
			FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.4);

		curSelected += change;
		if (curSelected < 0)
			curSelected = menuItems.length - 1;
		if (curSelected >= menuItems.length)
			curSelected = 0;

		var bullShit:Int = 0;
		for (item in grpMenuShit.members) {
			item.targetY = bullShit - curSelected;
			bullShit++;

			// Cancelar tweens de alpha pendientes (del _rebuildMenu) para que
			// no sobreescriban el valor que asignamos al navegar.
			FlxTween.cancelTweensOf(item);
			item.alpha = (item.targetY == 0) ? 1.0 : 0.6;

			FlxTween.cancelTweensOf(item.scale);
			FlxTween.tween(item.scale, {x: item.targetY == 0 ? 1.1 : 1.0, y: item.targetY == 0 ? 1.1 : 1.0}, 0.1, {ease: FlxEase.quadOut});
		}

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onSelectionChanged', [curSelected]);
		#end
	}
}
