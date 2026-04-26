package funkin.gameplay;

// Core imports
import flixel.FlxG;
import flixel.FlxCamera;
import flixel.FlxObject;
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;
import funkin.transitions.StateTransition;
import flixel.sound.FlxSound;
import flixel.text.FlxText;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.tweens.FlxEase;
import flixel.FlxSubState;
// Game objects
import funkin.gameplay.objects.character.Character;
import funkin.gameplay.objects.stages.Stage;
import funkin.gameplay.notes.Note;
import funkin.gameplay.notes.NoteSplash;
import funkin.gameplay.notes.NoteHoldCover;
import funkin.gameplay.notes.StrumNote;
import funkin.gameplay.notes.NoteSkinSystem;
import funkin.gameplay.notes.NotePool;
import funkin.optimization.GPURenderer;
import funkin.optimization.OptimizationManager;
import funkin.system.MemoryUtil;
import funkin.gameplay.objects.character.CharacterSlot;
import funkin.gameplay.objects.StrumsGroup;
import funkin.data.Song.CharacterSlotData;
import funkin.data.Song.StrumsGroupData;
// NUEVO: Import de batching
import funkin.gameplay.notes.NoteBatcher;
import funkin.gameplay.notes.ModchartHoldMesh;
// Gameplay modules
import funkin.gameplay.*;
// Scripting
import funkin.scripting.ScriptHandler;
import funkin.scripting.events.EventManager;
// Other
import funkin.data.Song.SwagSong;
import funkin.data.Song;
import funkin.data.Section.SwagSection;
import funkin.data.Section;
import funkin.data.Conductor;
import funkin.data.CoolUtil;
import funkin.gameplay.objects.hud.Highscore;
import funkin.states.LoadingState;
import funkin.states.GameOverSubstate;
import funkin.menus.ResultScreen;
import funkin.gameplay.objects.hud.ScoreManager;
import funkin.transitions.StickerTransition;
// Menu Pause
import funkin.menus.substate.GitarooPause;
import funkin.menus.substate.PauseSubState;
import funkin.debug.charting.ChartingState;
#if desktop
import data.Discord.DiscordClient;
#end
// Cutscenes
import funkin.cutscenes.dialogue.DialogueBoxImproved;
import funkin.cutscenes.dialogue.DialogueData;
import funkin.cutscenes.VideoManager;
import funkin.cutscenes.SpriteCutscene;
import funkin.data.MetaData;
import funkin.gameplay.UIScriptedManager;
// ModChart
import funkin.gameplay.modchart.ModChartEvent;
import funkin.gameplay.modchart.ModChartManager;
import funkin.gameplay.modchart.ModChartEditorState;
import funkin.gameplay.notes.NoteSkinSystem.NoteSkinData;
import funkin.data.SaveData;

using StringTools;

class PlayState extends funkin.states.MusicBeatState {
	// === SINGLETON ===
	public static var instance:PlayState = null;

	// ─── Managers dedicados de gameplay (se pausan al abrir el PauseSubState) ──

	/** FlxTweenManager exclusivo del gameplay. Usar en lugar de FlxTween.tween()
	 *  para que los tweens se congelen automáticamente al pausar. */
	public static var gameplayTweens:flixel.tweens.FlxTweenManager = null;

	/** FlxTimerManager exclusivo del gameplay. Usar en lugar de new FlxTimer()
	 *  para que los timers se congelen automáticamente al pausar. */
	public static var gameplayTimers:flixel.util.FlxTimerManager = null;

	// === STATIC DATA ===
	public static var SONG:SwagSong;
	public static var curStage:String = '';

	/**
	 * Versión en minúsculas de SONG.song, cacheada en create() para evitar
	 * llamar toLowerCase() en cada uso.
	 */
	public var songId:String = '';

	public static var isStoryMode:Bool = false;
	public static var storyWeek:Int = 0;
	public static var storyPlaylist:Array<String> = [];
	public static var storyDifficulty:Int = 1;
	public static var weekSong:Int = 0;

	// ✨ CHART TESTING: Tiempo desde el cual empezar (para testear secciones específicas)
	public static var startFromTime:Null<Float> = null;

	/**
	 * Acumulador de score para el modo Story.
	 */
	public static var campaignScore:Int = 0;

	/** Proxy to gameState.health for compatibility. */
	public var health(get, set):Float;

	inline function get_health():Float
		return gameState != null ? gameState.health : 1.0;

	inline function set_health(v:Float):Float {
		if (gameState != null)
			gameState.health = v;
		return v;
	}

	// === CORE SYSTEMS ===
	public var gameState:GameState;
	public var noteManager:NoteManager;

	private var inputHandler:InputHandler;

	#if mobileC
	private var mobileControls:ui.Mobilecontrols;
	#end

	public var cameraController:CameraController;
	public var uiManager:UIScriptedManager;
	public var characterController:CharacterController;
	public var metaData:MetaData;
	public var scriptsEnabled:Bool = true;

	var isCutscene:Bool = false;

	public var scoreManager:ScoreManager;

	// === CAMERAS ===
	public var camGame:FlxCamera;
	public var camHUD:FlxCamera;
	public var camCountdown:FlxCamera;
	public var camSubtitles:FlxCamera;

	// === CHARACTERS ===
	public var boyfriend:Character;
	public var dad:Character;
	public var gf:Character;

	// === STAGE ===
	public var currentStage:Stage;

	// ── MODCHART ──
	public var modChartManager:ModChartManager;

	/** Renderizador de holds curvados cuando hay modificadores activos. */
	public var holdMesh:ModchartHoldMesh;

	private var gfSpeed:Int = 1;

	// === NOTES ===
	public var notes:FlxTypedGroup<Note>;

	/** Grupo de notas sustain — se añade ANTES que notes para z-order correcto. */
	public var sustainNotes:FlxTypedGroup<Note>;

	public var strumLineNotes:FlxTypedGroup<FlxSprite>;

	private var playerStrums:FlxTypedGroup<FlxSprite>;

	public static var cpuStrums:FlxTypedGroup<FlxSprite> = null;

	public var grpNoteSplashes:FlxTypedGroup<NoteSplash>;
	public var grpHoldCovers:FlxTypedGroup<NoteHoldCover>;

	// === AUDIO ===
	public var vocals:FlxSound;

	/**
	 * Mapa dinámico de vocales por personaje.
	 */
	public var vocalsPerChar:Map<String, FlxSound> = new Map();

	/** Alias de compatibilidad — apunta al track del primer Player. */
	public var vocalsBf(get, never):FlxSound;

	inline function get_vocalsBf():FlxSound {
		for (k in _vocalsPlayerKeys) {
			var v = vocalsPerChar.get(k);
			if (v != null)
				return v;
		}
		return null;
	}

	/** Alias de compatibilidad — apunta al track del primer Opponent. */
	public var vocalsDad(get, never):FlxSound;

	inline function get_vocalsDad():FlxSound {
		for (k in _vocalsOpponentKeys) {
			var v = vocalsPerChar.get(k);
			if (v != null)
				return v;
		}
		return null;
	}

	private var _usingPerCharVocals:Bool = false;
	private var _vocalsPlayerKeys:Array<String> = [];
	private var _vocalsOpponentKeys:Array<String> = [];

	// === STATE ===
	private var generatedMusic:Bool = false;
	private var _gcPausedForSong:Bool = false;

	public static var startingSong:Bool = false;

	public var inCutscene:Bool = false;

	public static var isPlaying:Bool = false;
	public static var isBotPlay:Bool = false;

	/** true = modo cinemático sin HUD, sin game-over, sin pausa. */
	public static var cinematicMode:Bool = false;

	/** Callback al terminar la canción en cinematicMode. */
	public var onCinematicEnd:Void->Void = null;

	/**
	 * Alias de conveniencia — lee PlayStateConfig.minimalMode.
	 * true = modo osu-like: sin stage ni personajes, sólo strums + notas + HUD.
	 */
	public static var minimalMode(get, set):Bool;

	static inline function get_minimalMode():Bool
		return PlayStateConfig.minimalMode;

	static inline function set_minimalMode(v:Bool):Bool {
		PlayStateConfig.minimalMode = v;
		return v;
	}

	public var canPause:Bool = true;
	public var paused:Bool = false;

	// === HOOKS ===
	public var onBeatHitHooks:Map<String, Int->Void> = new Map();
	public var onStepHitHooks:Map<String, Int->Void> = new Map();
	public var onUpdateHooks:Map<String, Float->Void> = new Map();
	public var onNoteHitHooks:Map<String, Note->Void> = new Map();
	public var onNoteMissHooks:Map<String, Note->Void> = new Map();

	private var _beatHookArr:Array<Int->Void> = [];
	private var _stepHookArr:Array<Int->Void> = [];
	private var _updateHookArr:Array<Float->Void> = [];
	private var _noteHitHookArr:Array<Note->Void> = [];
	private var _noteMissHookArr:Array<Note->Void> = [];

	public function rebuildHookArrays():Void {
		_beatHookArr = [for (h in onBeatHitHooks) h];
		_stepHookArr = [for (h in onStepHitHooks) h];
		_updateHookArr = [for (h in onUpdateHooks) h];
		_noteHitHookArr = [for (h in onNoteHitHooks) h];
		_noteMissHookArr = [for (h in onNoteMissHooks) h];
	}

	// === OPTIMIZATION ===
	private var strumLiney:Float = PlayStateConfig.STRUM_LINE_Y;

	public var optimizationManager:OptimizationManager;

	// === SECTION CACHE ===
	private var cachedSection:SwagSection = null;
	private var cachedSectionIndex:Int = -1;
	private var _cachedSectionClass:Section = null;
	private var _cachedSectionClassIdx:Int = -2;

	// === BATCHING AND HOLD NOTES ===
	private var noteBatcher:NoteBatcher;
	private var heldNotes:Map<Int, Note> = new Map();

	// ── Lane Backdrop ─────────────────────────────────────────
	public var laneBackdrop:FlxSprite;

	public var enableBatching:Bool = true;

	private var showDebugStats:Bool = false;
	private var debugText:FlxText;

	// ─── Rewind Restart ──────────────────────────────────────────
	private var isRewinding:Bool = false;
	private var _rewindTimer:Float = 0;
	private var _rewindDuration:Float = 1.0;
	private var _rewindFromPos:Float = 0;
	private var _rewindToPos:Float = 0;

	// ── Stutter / lag-spike protection ────────────────────────────────────────
	// Si entre dos frames el audio avanza más de STUTTER_THRESHOLD_MS, es un
	// lag spike. En ese caso damos a las notas cercanas una ventana de gracia
	// igual al tiempo perdido para que no se pierdan combos por culpa del motor.
	private static inline var STUTTER_THRESHOLD_MS:Float = 80.0; // ~5 frames a 60fps
	private var _prevSongPosition:Float = 0.0;

	public var countdown:Countdown;

	// ─── Resync cooldown ───────────────────────────────────────
	private var _resyncCooldown:Int = 0;

	private var characterSlots:Array<CharacterSlot> = [];

	public var strumsGroups:Array<StrumsGroup> = [];
	public var strumsGroupMap:Map<String, StrumsGroup> = new Map();

	private var activeCharIndices:Array<Int> = [];

	public var playerStrumsGroup:StrumsGroup = null;
	public var cpuStrumsGroup:StrumsGroup = null;

	var skinSystem:NoteSkinData;

	#if desktop
	var storyDifficultyText:String = "";
	var iconRPC:String = "";
	var detailsText:String = "";
	var detailsPausedText:String = "";
	#end

	override public function create() {
		if (StickerTransition.enabled) {
			transIn = null;
			transOut = null;
		}
		instance = this;
		isPlaying = true;

		funkin.system.CursorManager.hide();
		#if android
		lime.app.Application.current.window.onKeyDown.add(_onAndroidKeyDown);
		#end

		Paths.clearPreviousSession();

		// FIX: setGameplayMode(true) debe llamarse ANTES de cargar cualquier asset.
		// Si se llama al final de create() (como estaba antes), el LRU ya tiene 35-50
		// texturas cargadas y el límite reducido (32 desktop) dispara evictions sobre
		// assets de personaje/stage que siguen activos durante la canción.
		funkin.cache.PathsCache.setGameplayMode(true);

		if (scriptsEnabled) {
			ScriptHandler.init();
			ScriptHandler.loadSongScripts(SONG.song);
			EventManager.loadEventsFromSong();
			ScriptHandler.setOnScripts('SONG', SONG);
			ScriptHandler.callOnScripts('onCreate', ScriptHandler._argsEmpty);
		}

		if (SONG.stage == null)
			SONG.stage = 'stage_week1';

		songId = SONG.song != null ? SONG.song.toLowerCase() : '';
		curStage = SONG.stage;
		Paths.currentStage = curStage;

		#if desktop
		setupDiscord();
		#end

		setupCameras();

		if (scriptsEnabled) {
			ScriptHandler.setOnScripts('camGame', camGame);
			ScriptHandler.setOnScripts('camHUD', camHUD);
			ScriptHandler.setOnScripts('camCountdown', camCountdown);
			ScriptHandler.setOnScripts('camSubtitles', camSubtitles);
		}

		gameState = GameState.get();
		gameState.reset();

		RatingManager.reload(SONG.song);

		loadStageAndCharacters();

		metaData = MetaData.load(SONG.song, funkin.data.CoolUtil.difficultySuffix());
		NoteSkinSystem.init();
		funkin.data.GlobalConfig.applyToSkinSystem();
		_applySkinFromMeta();
		_applySplashFromMeta();
		NoteSkinSystem.loadSkinScript();
		NoteSkinSystem.loadSplashScript();

		setupUI();

		StickerTransition.clearStickers();

		createNoteGroups();

		setupControllers();

		modChartManager = new ModChartManager(strumsGroups);
		modChartManager.data.song = SONG.song;
		modChartManager.loadFromFile(SONG.song);

		// Conectar modchart ↔ noteManager y holdMesh ahora que ambos existen.
		noteManager.modManager = modChartManager;
		holdMesh.noteManager = noteManager;

		generateSong();

		initHitSoundPool();

		setupDebugDisplay();

		optimizationManager = new OptimizationManager();
		optimizationManager.init();

		funkin.optimization.RenderOptimizer.init();
		funkin.optimization.RenderOptimizer.optimizeCameras(camGame, camHUD);

		countdown.preload();

		startCountdown();

		super.create();

		gameplayTweens = new flixel.tweens.FlxTweenManager();
		FlxG.plugins.addPlugin(gameplayTweens);
		gameplayTimers = new flixel.util.FlxTimerManager();
		FlxG.plugins.addPlugin(gameplayTimers);

		if (scriptsEnabled) {
			ScriptHandler.injectPlayState(this);
			ScriptHandler.callOnNonStageScripts('postStageCreate', ScriptHandler._argsEmpty);
			ScriptHandler.callOnScripts('postCreate', ScriptHandler._argsEmpty);

			if (metaData != null && metaData.artist != null && metaData.artist != '')
				GameState.listArtist = metaData.artist;
			else if (SONG.artist != null && SONG.artist != '')
				GameState.listArtist = SONG.artist;
			ScriptHandler.setOnScripts('author', GameState.listArtist);
		}

		funkin.ui.SubtitleManager.instance.refreshCamera();

		FlxG.signals.focusLost.add(_onGlobalFocusLost);

		#if (!flash && !html5)
		var _flushFrameCount:Int = 0;
		final _flushFramesNeeded:Int = 1;
		FlxG.stage.addEventListener(openfl.events.Event.ENTER_FRAME, function _onFlushFrame(_:openfl.events.Event):Void {
			_flushFrameCount++;
			if (_flushFrameCount < _flushFramesNeeded)
				return;
			FlxG.stage.removeEventListener(openfl.events.Event.ENTER_FRAME, _onFlushFrame);
			funkin.cache.PathsCache.instance.flushGPUCache();
			#if (cpp && !mobileC)
			cpp.vm.Gc.run(true);
			try {
				cpp.vm.Gc.compact();
			} catch (_:Dynamic) {}
			#end
			#if hl hl.Gc.major(); #end
			trace('[PlayState] GPU flush + GC completed after ${_flushFramesNeeded} frame(s)');
		});
		#end
	}

	// ──────────────────────────────────────────────────────────────────────
	// HELPERS: Skin / Splash desde meta
	// ──────────────────────────────────────────────────────────────────────

	private function _applySkinFromMeta():Void {
		if (metaData.noteSkin != null && metaData.noteSkin != 'default' && metaData.noteSkin != '') {
			NoteSkinSystem.setTemporarySkin(metaData.noteSkin);
			trace('[PlayState] Skin override from meta.json: "${metaData.noteSkin}"');
		} else {
			if (metaData.stageSkins != null) {
				for (stageName in metaData.stageSkins.keys())
					NoteSkinSystem.registerStageSkin(stageName, metaData.stageSkins.get(stageName));
				trace('[PlayState] stageSkins from meta.json applied');
			}
			NoteSkinSystem.applySkinForStage(curStage);
		}
	}

	private function _applySplashFromMeta():Void {
		if (metaData.noteSplash != null && metaData.noteSplash != '')
			NoteSkinSystem.setTemporarySplash(metaData.noteSplash);
		else
			NoteSkinSystem.applySplashForStage(curStage);
	}

	// ──────────────────────────────────────────────────────────────────────
	// DISCORD
	// ──────────────────────────────────────────────────────────────────────
	#if desktop
	private function setupDiscord():Void {
		storyDifficultyText = CoolUtil.difficultyString();
		var _dadData = dad?.characterData;
		if (_dadData?.discordIcon != null && _dadData.discordIcon != '')
			iconRPC = _dadData.discordIcon;
		else if (_dadData?.healthIcon != null && _dadData.healthIcon != '')
			iconRPC = _dadData.healthIcon;
		else
			iconRPC = SONG.player2 ?? 'dad';

		detailsText = isStoryMode ? "Story Mode: Week " + storyWeek : "Freeplay";
		detailsPausedText = "Paused - " + detailsText;
		updatePresence();
	}

	function updatePresence():Void {
		DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconRPC);
	}
	#end

	// ──────────────────────────────────────────────────────────────────────
	// SETUP: Cameras
	// ──────────────────────────────────────────────────────────────────────

	private function setupCameras():Void {
		camGame = new FlxCamera();
		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		camCountdown = new FlxCamera();
		camCountdown.bgColor.alpha = 0;
		camSubtitles = new FlxCamera();
		camSubtitles.bgColor.alpha = 0;

		final _sd = PlayStateConfig.minimalMode ? null : funkin.gameplay.objects.stages.Stage.getStageData(curStage);
		final isPixelStage = (_sd != null && _sd.isPixelStage == true);

		countdown = new Countdown(this, camCountdown, isPixelStage);

		if (scriptsEnabled)
			ScriptHandler.setOnScripts('countdown', countdown);

		FlxG.cameras.reset(camGame);
		FlxG.cameras.add(camHUD, false);
		FlxG.cameras.add(camCountdown, false);
		FlxG.cameras.add(camSubtitles, false);
	}

	// ──────────────────────────────────────────────────────────────────────
	// SETUP: Stage + Characters
	// ──────────────────────────────────────────────────────────────────────

	private function loadStageAndCharacters():Void {
		// ── MINIMAL MODE: sin stage ni personajes ─────────────────────────────
		if (PlayStateConfig.minimalMode) {
			trace('[PlayState] minimalMode: loadStageAndCharacters omitido');
			// Fondo negro limpio (igual que osu! / Quaver)
			camGame.bgColor = flixel.util.FlxColor.BLACK;
			return;
		}
		// ─────────────────────────────────────────────────────────────────────
		currentStage = new Stage(curStage);
		currentStage.cameras = [camGame];
		_assignStageCameras(currentStage, [camGame]);

		if (scriptsEnabled)
			ScriptHandler.callOnNonStageScripts('onStageCreate', ScriptHandler._argsEmpty);

		loadCharacters();

		if (currentStage._useCharAnchorSystem) {
			add(currentStage);
			_addCharactersWithAnchors();
		} else {
			add(currentStage);
			for (slot in characterSlots)
				if (slot.character != null)
					add(slot.character);

			if (currentStage.aboveCharsGroup != null && currentStage.aboveCharsGroup.length > 0)
				add(currentStage.aboveCharsGroup);
		}

		// Asignar refs legacy por tipo
		for (slot in characterSlots) {
			if (slot.isGFSlot && gf == null)
				gf = slot.character;
			else if (slot.isOpponentSlot && dad == null)
				dad = slot.character;
			else if (slot.isPlayerSlot && boyfriend == null)
				boyfriend = slot.character;
		}

		if (scriptsEnabled) {
			for (slot in characterSlots) {
				final char = slot.character;
				if (char == null)
					continue;
				ScriptHandler.loadCharacterScripts(char.curCharacter);
				ScriptHandler.setOnCharacterScripts(char.curCharacter, 'character', char);
				ScriptHandler.setOnCharacterScripts(char.curCharacter, 'char', char);
				ScriptHandler.callOnCharacterScripts(char.curCharacter, 'postCreate', ScriptHandler._argsEmpty);
				trace('[PlayState] Scripts de personaje cargados para "${char.curCharacter}"');
			}
		}
	}

	/** Añade sprites de stage y personajes respetando los char-anchor del JSON. */
	private function _addCharactersWithAnchors():Void {
		var addedCharSlots:Map<String, Bool> = new Map();
		var addedCharObjects:Array<Character> = [];

		for (entry in currentStage.spriteList) {
			if (entry.sprite != null) {
				entry.sprite.cameras = [camGame];
				add(entry.sprite);
			} else if (entry.element.type != null && entry.element.type.toLowerCase() == 'character' && entry.element.charSlot != null) {
				var slotKey = entry.element.charSlot.toLowerCase();
				for (slot in characterSlots) {
					var matches = switch (slotKey) {
						case 'bf', 'boyfriend', 'player', 'player1': slot.isPlayerSlot;
						case 'gf', 'girlfriend', 'spectator': slot.isGFSlot;
						case 'dad', 'opponent', 'player2': slot.isOpponentSlot;
						default: false;
					};
					if (matches && !addedCharSlots.exists(slotKey)) {
						add(slot.character);
						addedCharSlots.set(slotKey, true);
						addedCharObjects.push(slot.character);
						break;
					}
				}
			}
		}

		// Safety: añadir personajes no colocados por un anchor
		for (slot in characterSlots)
			if (slot.character != null && !addedCharObjects.contains(slot.character))
				add(slot.character);
	}

	private function loadCharacters():Void {
		if (SONG.characters == null || SONG.characters.length == 0) {
			SONG.characters = [];
			SONG.characters.push({
				name: SONG.gfVersion ?? 'gf',
				x: 0,
				y: 0,
				visible: true,
				isGF: true,
				type: 'Girlfriend',
				strumsGroup: 'gf_strums_0'
			});
			SONG.characters.push({
				name: SONG.player2 ?? 'dad',
				x: 0,
				y: 0,
				visible: true,
				type: 'Opponent',
				strumsGroup: 'cpu_strums_0'
			});
			SONG.characters.push({
				name: SONG.player1 ?? 'bf',
				x: 0,
				y: 0,
				visible: true,
				type: 'Player',
				strumsGroup: 'player_strums_0'
			});
		}

		for (i in 0...SONG.characters.length) {
			var charData = SONG.characters[i];
			var slot = new CharacterSlot(charData, i);

			if (charData.x == 0 && charData.y == 0) {
				switch (slot.charType) {
					case 'Girlfriend':
						slot.character.setPosition(currentStage.gfPosition.x, currentStage.gfPosition.y);
					case 'Opponent':
						slot.character.setPosition(currentStage.dadPosition.x, currentStage.dadPosition.y);
					case 'Player':
						slot.character.setPosition(currentStage.boyfriendPosition.x, currentStage.boyfriendPosition.y);
					default:
				}
			} else {
				slot.character.setPosition(charData.x, charData.y);
			}

			if (slot.character.characterData != null) {
				final posOff = slot.character.characterData.positionOffset;
				if (posOff != null && posOff.length >= 2) {
					slot.character.x += posOff[0];
					slot.character.y += posOff[1];
				}
			}

			characterSlots.push(slot);
		}

		// BUG FIX #HIDEGF
		if (currentStage != null && currentStage.hideGirlfriend) {
			for (slot in characterSlots) {
				if (slot.isGFSlot && slot.character != null) {
					slot.character.visible = false;
					trace('[PlayState] hideGirlfriend: ocultando "${slot.character.curCharacter}"');
				}
			}
		}
	}

	// ──────────────────────────────────────────────────────────────────────
	// SETUP: Note groups
	// ──────────────────────────────────────────────────────────────────────

	private function createNoteGroups():Void {
		strumLineNotes = new FlxTypedGroup<FlxSprite>();
		strumLineNotes.cameras = [camHUD];

		loadStrums();

		laneBackdrop = new FlxSprite();
		laneBackdrop.cameras = [camHUD];
		laneBackdrop.scrollFactor.set(0, 0);
		_updateLaneBackdrop();
		add(laneBackdrop);

		noteBatcher = new NoteBatcher();
		noteBatcher.cameras = [camHUD];
		add(noteBatcher);

		add(strumLineNotes);

		// FIX race condition draw order: holdMesh PRIMERO → oculta sprites rectos antes de que sustainNotes los renderice.
		// Orden correcto cada frame:
		//   1. holdMesh.draw()     → renderiza mesh curvo + pone visible=false en notas curvadas
		//   2. sustainNotes.draw() → notas curvadas ya tienen visible=false → no renderizan sprite recto
		// noteManager se asigna después de setupControllers(); cam ya está disponible aquí.
		holdMesh = new ModchartHoldMesh(null, camHUD);
		add(holdMesh);

		sustainNotes = new FlxTypedGroup<Note>();
		sustainNotes.cameras = [camHUD];
		add(sustainNotes);

		notes = new FlxTypedGroup<Note>();
		notes.cameras = [camHUD];
		add(notes);

		grpNoteSplashes = new FlxTypedGroup<NoteSplash>();
		grpNoteSplashes.cameras = [camHUD];
		add(grpNoteSplashes);

		grpHoldCovers = new FlxTypedGroup<NoteHoldCover>();
		grpHoldCovers.cameras = [camHUD];
		add(grpHoldCovers);

		if (cinematicMode) {
			strumLineNotes.visible = false;
			sustainNotes.visible = false;
			holdMesh.visible = false;
			notes.visible = false;
			grpNoteSplashes.visible = false;
			grpHoldCovers.visible = false;
			laneBackdrop.visible = false;
			if (noteBatcher != null)
				noteBatcher.visible = false;
		}
	}

	private function _updateLaneBackdrop():Void {
		if (laneBackdrop == null)
			return;

		var alpha:Float = (SaveData.data.laneAlpha != null) ? SaveData.data.laneAlpha : 0.0;
		laneBackdrop.alpha = alpha;

		if (playerStrums == null || playerStrums.members == null || playerStrums.members.length < 4) {
			laneBackdrop.makeGraphic(4, FlxG.height, flixel.util.FlxColor.BLACK);
			laneBackdrop.x = -999;
			return;
		}

		var firstStrum:FlxSprite = playerStrums.members[0];
		var lastStrum:FlxSprite = playerStrums.members[playerStrums.members.length - 1];
		if (firstStrum == null || lastStrum == null)
			return;

		var bw:Int = Std.int(lastStrum.x + lastStrum.width - firstStrum.x + 20);
		if (bw < 4)
			bw = 4;

		laneBackdrop.makeGraphic(bw, FlxG.height, flixel.util.FlxColor.BLACK);
		laneBackdrop.setPosition(firstStrum.x - 10, 0);
	}

	private function loadStrums():Void {
		if (SONG.strumsGroups == null || SONG.strumsGroups.length == 0)
			return;

		for (groupData in SONG.strumsGroups) {
			var group = new StrumsGroup(groupData);
			strumsGroups.push(group);
			strumsGroupMap.set(groupData.id, group);

			group.strums.forEach(function(strum:FlxSprite) {
				strumLineNotes.add(strum);
			});

			if (groupData.cpu && cpuStrums == null) {
				var isGFGroup = groupData.id.startsWith('gf_') || (!groupData.visible && groupData.id.indexOf('gf') >= 0);
				if (!isGFGroup) {
					cpuStrums = group.strums;
					cpuStrumsGroup = group;
					if (SaveData.data.downscroll)
						for (i in 0...cpuStrums.members.length)
							cpuStrums.members[i].y = FlxG.height - 150;
					if (SaveData.data.middlescroll)
						for (i in 0...cpuStrums.members.length) {
							cpuStrums.members[i].visible = false;
							cpuStrums.members[i].alpha = 0;
						}
				}
			} else if (!groupData.cpu && playerStrums == null) {
				playerStrums = group.strums;
				playerStrumsGroup = group;
				for (i in 0...playerStrums.members.length) {
					if (SaveData.data.downscroll)
						playerStrums.members[i].y = FlxG.height - 150;
					if (SaveData.data.middlescroll)
						playerStrums.members[i].x -= (FlxG.width / 4);
				}
			}
		}

		_applyGroupSkinOverrides();
	}

	// ──────────────────────────────────────────────────────────────────────
	// HELPER: aplica noteSkins del meta.json a cada StrumsGroup
	// ──────────────────────────────────────────────────────────────────────

	private function _applyGroupSkinOverrides():Void {
		if (metaData == null || metaData.noteSkins == null)
			return;

		for (group in strumsGroups) {
			var skinOverride:Null<String> = metaData.noteSkins.get(group.id);

			if (skinOverride == null && group.data.characters != null)
				for (charId in group.data.characters) {
					var s = metaData.noteSkins.get(charId);
					if (s != null) {
						skinOverride = s;
						break;
					}
				}

			if (skinOverride == null || skinOverride == '')
				continue;

			var skinData = NoteSkinSystem.getCurrentSkinData(skinOverride);
			if (skinData != null) {
				group.reloadAllStrumSkins(skinData);
				group.data.noteSkin = skinOverride;
				trace('[PlayState] noteSkins: grupo "${group.id}" → skin "$skinOverride"');
			} else {
				trace('[PlayState] noteSkins: skin "$skinOverride" no encontrada para grupo "${group.id}"');
			}
		}
	}

	// ──────────────────────────────────────────────────────────────────────
	// SETUP: Controllers
	// ──────────────────────────────────────────────────────────────────────

	private function setupControllers():Void {
		if (!PlayStateConfig.minimalMode) {
			// ── Modo normal: requiere personajes y stage ──────────────────
			if (boyfriend == null || dad == null) {
				#if debug
				if (boyfriend == null) {
					boyfriend = new Character(100, 100, 'bf');
					add(boyfriend);
				}
				if (dad == null) {
					dad = new Character(100, 100, 'dad');
					add(dad);
				}
				#else
				StateTransition.switchState(new funkin.menus.MainMenuState());
				return;
				#end
			}

			cameraController = new CameraController(camGame, camHUD, boyfriend, dad, gf);

			if (currentStage != null && currentStage.defaultCamZoom > 0)
				cameraController.defaultZoom = currentStage.defaultCamZoom;

			final sd = currentStage?.stageData;
			if (sd?.cameraBoyfriend != null)
				cameraController.stageOffsetBf.add(currentStage.cameraBoyfriend.x, currentStage.cameraBoyfriend.y);
			if (sd?.cameraDad != null)
				cameraController.stageOffsetDad.add(currentStage.cameraDad.x, currentStage.cameraDad.y);
			if (sd?.cameraGirlfriend != null)
				cameraController.stageOffsetGf.add(currentStage.cameraGirlfriend.x, currentStage.cameraGirlfriend.y);

			cameraController.lerpSpeed = CameraController.BASE_LERP_SPEED * (currentStage?.cameraSpeed ?? 1.0);
			cameraController.snapshotInitialState();

			characterController = new CharacterController();
			characterController.initFromSlots(characterSlots);
		} else {
			// ── MINIMAL MODE: cámara estática, sin CharacterController ────
			trace('[PlayState] minimalMode: CameraController y CharacterController omitidos');
			// Centrar camGame en el origen (el HUD no depende de esto)
			camGame.focusOn(flixel.math.FlxPoint.get(FlxG.width / 2, FlxG.height / 2));
		}

		// ── Lo siguiente es idéntico en ambos modos ───────────────────────

		inputHandler = new InputHandler();
		inputHandler.ghostTapping = SaveData.data.ghosttap;
		inputHandler.onNoteHit = onPlayerNoteHit;
		inputHandler.onNoteMiss = onPlayerNoteMiss;
		inputHandler.inputBuffering = true;
		inputHandler.bufferTime = 0.1;
		inputHandler.onKeyRelease = onKeyRelease;

		#if mobileC
		mobileControls = new ui.Mobilecontrols();
		mobileControls.cameras = [camHUD];
		mobileControls.scrollFactor.set(0, 0);
		add(mobileControls);
		var _hitbox = mobileControls._hitbox;
		var _vpad = mobileControls._virtualPad;

		inputHandler.strumTapEnabled = (SaveData.data.strumTap == true);

		if (_hitbox != null) {
			if (inputHandler.strumTapEnabled) {
				_hitbox.buttonLeft.visible = false;
				_hitbox.buttonDown.visible = false;
				_hitbox.buttonUp.visible = false;
				_hitbox.buttonRight.visible = false;
				_hitbox.visible = false;
			}
			inputHandler.mobileLeft = _hitbox.buttonLeft;
			inputHandler.mobileDown = _hitbox.buttonDown;
			inputHandler.mobileUp = _hitbox.buttonUp;
			inputHandler.mobileRight = _hitbox.buttonRight;
		} else if (_vpad != null) {
			inputHandler.mobileLeft = _vpad.buttonLeft;
			inputHandler.mobileDown = _vpad.buttonDown;
			inputHandler.mobileUp = _vpad.buttonUp;
			inputHandler.mobileRight = _vpad.buttonRight;
		}

		if (inputHandler.strumTapEnabled && playerStrums != null) {
			for (i in 0...playerStrums.members.length) {
				var s = playerStrums.members[i];
				if (s != null)
					inputHandler.strumTapPositions[i] = s.x + s.width * 0.5;
			}
		}
		#end

		strumLiney = SaveData.data.downscroll ? FlxG.height - 150 : PlayStateConfig.STRUM_LINE_Y;

		noteManager = new NoteManager(notes, playerStrums, cpuStrums, grpNoteSplashes, grpHoldCovers, playerStrumsGroup, cpuStrumsGroup, strumsGroups,
			sustainNotes);
		noteManager.strumLineY = strumLiney;
		noteManager.downscroll = SaveData.data.downscroll;
		noteManager.middlescroll = SaveData.data.middlescroll;
		noteManager.onCPUNoteHit = onCPUNoteHit;
		noteManager.onNoteHit = null;
		noteManager.onBotNoteHit = onPlayerNoteHit;
		noteManager.onNoteMiss = onPlayerNoteMiss;
	}

	private function setupDebugDisplay():Void {
		debugText = new FlxText(10, 10, 0, "", 14);
		debugText.setBorderStyle(FlxTextBorderStyle.OUTLINE, FlxColor.BLACK, 2);
		debugText.cameras = [camHUD];
		debugText.visible = showDebugStats;
		add(debugText);
	}

	public function setupUI():Void {
		uiManager = new UIScriptedManager(camHUD, gameState, metaData);

		if (cinematicMode) {
			uiManager.active = false;
			uiManager.visible = false;
			add(uiManager);
			return;
		}

		var icons:Array<String> = [SONG.player1 ?? 'bf', SONG.player2 ?? 'dad'];
		if (boyfriend?.healthIcon != null && dad?.healthIcon != null)
			icons = [boyfriend.healthIcon, dad.healthIcon];

		uiManager.setIcons(icons[0], icons[1]);
		uiManager.setStage(curStage);
		add(uiManager);
		uiManager.active = false;
	}

	private function generateStaticArrows(player:Int):Void {
		for (i in 0...4) {
			var targetAlpha:Float = (player < 1 && SaveData.data.middlescroll) ? 0 : 1;
			var babyArrow:StrumNote = new StrumNote(0, strumLiney, i);
			babyArrow.ID = i;

			var xPos = 100 + (Note.swagWidth * i);
			if (player == 1) {
				xPos = SaveData.data.middlescroll ? FlxG.width / 2 - (Note.swagWidth * 2) + (Note.swagWidth * i) : xPos + FlxG.width / 2;
				playerStrums.add(babyArrow);
			} else {
				if (SaveData.data.middlescroll)
					xPos = -275 + (Note.swagWidth * i);
				cpuStrums.add(babyArrow);
			}

			babyArrow.x = xPos;
			if (!isStoryMode) {
				babyArrow.alpha = 0;
				// FIX: usar gameplayTweens en lugar del manager global para que
				// el tween se congele al pausar y se limpie con el estado.
				// gameplayTweens puede ser null si llamamos antes de super.create(),
				// así que usamos el manager global como fallback seguro.
				final _mgr = PlayState.gameplayTweens ?? FlxTween.globalManager;
				_mgr.tween(babyArrow, {alpha: targetAlpha}, 0.5, {startDelay: 0.5 + (0.2 * i)});
			}
			babyArrow.animation.play('static');
			babyArrow.cameras = [camHUD];
			strumLineNotes.add(babyArrow);
		}
	}

	// ──────────────────────────────────────────────────────────────────────
	// AUDIO
	// ──────────────────────────────────────────────────────────────────────

	private function generateSong():Void {
		Conductor.changeBPM(SONG.bpm);

		final _diffSuffix:String = (SONG.instSuffix != null && SONG.instSuffix != '') ? '-' + SONG.instSuffix : funkin.data.CoolUtil.difficultySuffix();
		trace('[PlayState] Audio suffix: "$_diffSuffix" (instSuffix=${SONG.instSuffix})');

		funkin.audio.MusicManager.invalidate();

		final _rawInst = Paths.loadInst(SONG.song, _diffSuffix);
		if (_rawInst == null)
			trace('[PlayState] WARNING: Paths.loadInst returned null for "${SONG.song}" — audio will be silent.');

		funkin.audio.CoreAudio.setInst(_rawInst);
		if (_rawInst != null) {
			FlxG.sound.music = _rawInst;
			funkin.audio.CoreAudio.setInstVolume(0); // FIX: usar CoreAudio para mantener el registry en sync (evita que _applyAll restaure vol=1.0 durante el cutscene)
			_rawInst.pause();
		}

		_clearVocals();
		_reloadVocals(_diffSuffix);

		NotePool.clear();
		noteManager.generateNotes(SONG);
		generatedMusic = true;

		funkin.cache.PathsCache.instance.flushGPUCache();
		#if cpp
		cpp.vm.Gc.run(true);
		try {
			cpp.vm.Gc.compact();
		} catch (_:Dynamic) {}
		trace('[PlayState] GC forzado post-generateNotes → baseline RAM estabilizado');
		#end
		#if hl hl.Gc.major(); #end

		if (!_gcPausedForSong) {
			_gcPausedForSong = true;
			MemoryUtil.pauseGC();
		}

		_prewarmNoteTextures();

		// FIX RAM: flush CPU copies de las texturas de notes/splashes/holdCovers
		// cargadas durante el prewarm. Son las últimas texturas que se cargan antes
		// del inicio de la canción — sin este flush quedan con doble copia (CPU+GPU)
		// hasta el siguiente flushGPUCache, que no volvería a correr hasta destroy().
		#if (!flash && !html5)
		new flixel.util.FlxTimer().start(0, function(_) {
			funkin.cache.PathsCache.instance.flushGPUCache();
			#if cpp
			cpp.vm.Gc.run(true);
			try {
				cpp.vm.Gc.compact();
			} catch (_:Dynamic) {}
			#end
			#if hl hl.Gc.major(); #end
			trace('[PlayState] GPU flush post-prewarm completed');
		});
		#end
	}

	/**
	 * Elimina todos los tracks de vocals actuales de CoreAudio y del sound list.
	 */
	private function _clearVocals():Void {
		funkin.audio.CoreAudio.clearVocals();
		if (vocals != null) {
			FlxG.sound.list.remove(vocals, true);
			vocals.destroy();
			vocals = null;
		}
		_cleanPerCharVocals();
	}

	/**
	 * Carga los tracks de vocals según diffSuffix (per-char o genérico).
	 * Llama a _clearVocals() ANTES si hay que reemplazar los tracks existentes.
	 */
	private function _reloadVocals(diffSuffix:String):Void {
		if (SONG.needsVoices) {
			_usingPerCharVocals = _tryLoadPerCharVocals(diffSuffix);
			if (!_usingPerCharVocals)
				vocals = Paths.loadVoices(SONG.song, diffSuffix);
		}

		if (!_usingPerCharVocals) {
			if (vocals == null)
				vocals = new FlxSound();
			FlxG.sound.list.add(vocals);
			funkin.audio.CoreAudio.addVocal('vocals', vocals);
			vocals.pause(); // FIX: pausar DESPUÉS de addVocal para que _applyTo no reactive el buffer
		}
	}

	/**
	 * Ajusta el volumen base de los vocals del jugador (isPlayer=true)
	 * o del oponente (isPlayer=false). Usa setBaseVolume para no pelear con CoreAudio.
	 */
	private function _setVocalsVolume(isPlayer:Bool, vol:Float):Void {
		if (_usingPerCharVocals) {
			var keys = isPlayer ? _vocalsPlayerKeys : _vocalsOpponentKeys;
			for (k in keys) {
				var snd = vocalsPerChar.get(k);
				if (snd != null)
					funkin.audio.CoreAudio.setBaseVolume(snd, vol);
			}
		} else if (vocals != null) {
			funkin.audio.CoreAudio.setBaseVolume(vocals, vol);
		}
	}

	/** Pausa TODOS los streams de vocals (player + opponent). */
	private function _pauseAllVocals():Void {
		if (_usingPerCharVocals) {
			for (snd in vocalsPerChar)
				if (snd != null && snd.playing)
					snd.pause();
		} else if (vocals != null && vocals.playing) {
			vocals.pause();
		}
	}

	/** Detiene TODOS los streams de vocals. */
	private function _stopAllVocals():Void {
		if (_usingPerCharVocals) {
			for (snd in vocalsPerChar)
				if (snd != null)
					snd.stop();
		} else if (vocals != null) {
			vocals.stop();
		}
	}

	/** Sincroniza el tiempo de TODOS los vocals con el instrumental. */
	private function _syncVocalsTime(time:Float):Void {
		if (_usingPerCharVocals) {
			for (snd in vocalsPerChar)
				if (snd != null)
					snd.time = time;
		} else if (vocals != null) {
			vocals.time = time;
		}
	}

	private function _prewarmNoteTextures():Void {
		var skinData = NoteSkinSystem.getCurrentSkinData();
		if (skinData == null)
			return;

		NoteSkinSystem.loadSkinFrames(skinData.texture, skinData.folder);
		if (skinData.holdTexture != null)
			NoteSkinSystem.loadSkinFrames(skinData.holdTexture, skinData.folder);

		final splashOn:Bool = funkin.data.GlobalConfig.instance.noteSplashEnabled;
		if (splashOn) {
			try {
				NoteSkinSystem.getSplashTexture();
			} catch (e:Dynamic) {
				trace('[PlayState] Warning: could not pre-warm splash texture: $e');
			}

			if (grpNoteSplashes != null && grpNoteSplashes.length == 0) {
				try {
					var warmSplash = new NoteSplash();
					warmSplash.cameras = [camHUD];
					warmSplash.kill();
					grpNoteSplashes.add(warmSplash);
				} catch (e:Dynamic) {
					trace('[PlayState] Warning: could not pre-warm splash pool: $e');
				}
			}
		}

		final holdCoverOn:Bool = funkin.data.GlobalConfig.instance.holdCoverEnabled;
		if (holdCoverOn) {
			var coverColors = ["Purple", "Blue", "Green", "Red"];
			for (color in coverColors) {
				try {
					NoteSkinSystem.getHoldCoverTexture(color);
				} catch (e:Dynamic) {
					trace('[PlayState] Warning: could not pre-warm holdCover$color texture: $e');
				}
			}

			if (grpHoldCovers != null && grpHoldCovers.length == 0) {
				for (i in 0...4) {
					try {
						var warmCover = new NoteHoldCover();
						warmCover.cameras = [camHUD];
						warmCover.setup(0, 0, i);
						warmCover.kill();
						grpHoldCovers.add(warmCover);
						if (noteManager?.renderer != null)
							noteManager.renderer.holdCoverPool.push(warmCover);
					} catch (e:Dynamic) {
						trace('[PlayState] Warning: could not pre-warm holdCover pool dir $i: $e');
					}
				}
			}
		}

		if (noteManager?.renderer != null) {
			if (holdCoverOn) {
				for (cover in grpHoldCovers.members)
					if (cover != null)
						noteManager.renderer.registerHoldCoverInPool(cover);
			}
			noteManager.renderer.prewarmPools(4, 8);
		}

		trace('[PlayState] Note + Splash + HoldCover textures pre-warmed');
	}

	// ──────────────────────────────────────────────────────────────────────
	// COUNTDOWN + CUTSCENES
	// ──────────────────────────────────────────────────────────────────────
	public var startedCountdown:Bool = false;

	public function startCountdown():Void {
		if (scriptsEnabled) {
			var result = ScriptHandler.callOnScriptsReturn('onCountdownStarted', ScriptHandler._argsEmpty, false);
			if (result == true)
				return;
		}

		if (startedCountdown)
			return;

		if (scriptsEnabled) {
			var _startCb:Dynamic = function() {
				inCutscene = false;
				fixInstandVocals();
				startCountdown();
			};
			if (ScriptHandler.callOnScriptsReturn('onIntroCutscene', [_startCb], false) == true) {
				inCutscene = true;
				return;
			}
		}

		if (isStoryMode && metaData != null && (metaData.introVideo != null || metaData.introCutscene != null)) {
			final vidKey = metaData.introVideo;
			final cutKey = metaData.introCutscene;
			metaData.introVideo = null;
			metaData.introCutscene = null;

			var runSpriteCutscene:Void->Void = null;
			runSpriteCutscene = function() {
				if (cutKey != null && SpriteCutscene.exists(cutKey, songId)) {
					inCutscene = true;
					SpriteCutscene.create(this, cutKey, songId, function() {
						inCutscene = false;
						fixInstandVocals();
						startCountdown();
					});
				} else {
					fixInstandVocals();
					startCountdown();
				}
			};

			var runIntroDialogueThenCutscene:Void->Void = function() {
				if (checkForDialogue('intro') && isStoryMode) {
					inCutscene = true;
					showDialogue('intro', function() {
						inCutscene = false;
						runSpriteCutscene();
					});
				} else {
					runSpriteCutscene();
				}
			};

			if (vidKey != null && VideoManager._resolvePath(vidKey) != null) {
				inCutscene = true;
				VideoManager.playCutscene(vidKey, function() {
					inCutscene = false;
					runIntroDialogueThenCutscene();
				});
			} else {
				runIntroDialogueThenCutscene();
			}
			return;
		}

		if (checkForDialogue('intro') && isStoryMode) {
			inCutscene = true;
			showDialogue('intro', function() {
				fixInstandVocals();
				executeCountdown();
			});
			return;
		}

		executeCountdown();
	}

	function fixInstandVocals():Void {
		final _diffSuffix:String = (SONG.instSuffix != null && SONG.instSuffix != '') ? '-' + SONG.instSuffix : funkin.data.CoolUtil.difficultySuffix();

		if (FlxG.sound.music == null || !FlxG.sound.music.active) {
			final _reloadedInst = Paths.loadInst(SONG.song, _diffSuffix);
			funkin.audio.CoreAudio.setInst(_reloadedInst);
			if (_reloadedInst != null) {
				FlxG.sound.music = _reloadedInst;
				funkin.audio.CoreAudio.setInstVolume(0); // FIX: usar CoreAudio para mantener el registry en sync (evita que _applyAll restaure vol=1.0 durante el cutscene)
				_reloadedInst.pause();
			}
		} else if (funkin.audio.CoreAudio.inst == null) {
			funkin.audio.CoreAudio.setInst(FlxG.sound.music);
		} else {
			// FIX: inst existe pero puede tener vol>0 del estado anterior — asegurarse de que esté en 0 antes del countdown
			funkin.audio.CoreAudio.setInstVolume(0);
		}

		_clearVocals();
		_reloadVocals(_diffSuffix);
	}

	public function executeCountdown():Void {
		isCutscene = false;

		if (cinematicMode) {
			startingSong = false;
			startedCountdown = true;
			startSong();
			return;
		}

		if (startFromTime != null) {
			if (FlxG.sound.music == null) {
				startFromTime = null;
			} else {
				var targetTime = startFromTime;
				startingSong = false;
				startedCountdown = true;
				startFromTime = null;

				notes.forEachAlive(function(note:Note) {
					if (note.strumTime < targetTime - 100) {
						note.kill();
						notes.remove(note, true);
					}
				});

				if (inputHandler != null) {
					inputHandler.resetMash();
					inputHandler.clearBuffer();
				}

				new FlxTimer().start(0.2, function(_) {
					if (FlxG.sound.music == null)
						return;

					FlxG.sound.music.onComplete = endSong;
					funkin.audio.CoreAudio.play(FlxG.sound.music);
					FlxG.sound.music.time = targetTime;

					if (Math.abs(FlxG.sound.music.time - targetTime) > 100)
						FlxG.sound.music.time = targetTime;

					if (_usingPerCharVocals) {
						for (snd in vocalsPerChar) {
							if (snd == null)
								continue;
							funkin.audio.CoreAudio.play(snd);
							snd.time = targetTime;
						}
					} else if (vocals != null) {
						funkin.audio.CoreAudio.play(vocals);
						vocals.time = targetTime;
					}

					Conductor.songPosition = FlxG.sound.music.time;
				});
				return;
			}
		}

		Conductor.songPosition = -Conductor.crochet * 5;
		startingSong = true;
		startedCountdown = true;

		for (group in strumsGroups)
			group.strums.forEach(function(s:FlxSprite) {
				if (Std.isOfType(s, funkin.gameplay.notes.StrumNote))
					cast(s, funkin.gameplay.notes.StrumNote).playAnim('static', true);
			});

		modChartManager?.onCountdownStart();
		countdown.start(function() {});
	}

	// ──────────────────────────────────────────────────────────────────────
	// UPDATE
	// ──────────────────────────────────────────────────────────────────────

	override public function update(elapsed:Float) {
		if (scriptsEnabled) {
			ScriptHandler._argsUpdate[0] = elapsed;
			// Use callOnNonStageScripts here — Stage.update is the sole owner of
			// dispatching onUpdate/onUpdatePost to stage scripts (via
			// callOnStageScripts). Calling the full callOnScripts here would
			// cause stage scripts to receive the event twice per frame.
			ScriptHandler.callOnNonStageScripts('onUpdate', ScriptHandler._argsUpdate);
		}

		if (elapsed > 0.2)
			elapsed = 1.0 / 60.0;

		if (modChartManager != null && !paused && generatedMusic)
			modChartManager.update(Conductor.songPosition);

		super.update(elapsed);

		if (optimizationManager != null)
			optimizationManager.update(elapsed);

		// ═══ REWIND RESTART ════
		if (isRewinding) {
			_rewindTimer += elapsed;
			var t:Float = Math.min(1.0, _rewindTimer / _rewindDuration);
			Conductor.songPosition = _rewindFromPos + (_rewindToPos - _rewindFromPos) * flixel.tweens.FlxEase.quadIn(t);

			if (noteManager != null)
				noteManager.updatePositionsForRewind(Conductor.songPosition);
			if (cameraController != null)
				cameraController.update(elapsed);
			if (uiManager != null)
				uiManager.update(elapsed);

			if (t >= 1.0)
				_finishRestart();
			return;
		}

		if (!paused && !inCutscene) {
			if (startingSong && startedCountdown)
				Conductor.songPosition += FlxG.elapsed * 1000;
			else if (FlxG.sound.music != null && FlxG.sound.music.playing)
				Conductor.songPosition = FlxG.sound.music.time;

			// ── Stutter detection ──────────────────────────────────────────
			// Si el audio saltó más de STUTTER_THRESHOLD_MS en un solo frame
			// (lag spike), damos a las notas una ventana de gracia proporcional
			// al tiempo perdido para que no se generen misses injustos.
			if (!isRewinding && noteManager != null && generatedMusic) {
				final posJump = Conductor.songPosition - _prevSongPosition;
				if (posJump > STUTTER_THRESHOLD_MS)
					noteManager.lagGraceMs = Math.max(noteManager.lagGraceMs, posJump - (1000.0 / 60.0));
			}
			_prevSongPosition = Conductor.songPosition;
		}

		for (hook in _updateHookArr)
			hook(elapsed);

		if (!paused && !inCutscene) {
			characterController?.update(elapsed);
			cameraController?.update(elapsed);

			if (generatedMusic) {
				if (inputHandler != null && noteManager != null) {
					noteManager.playerHeld[0] = inputHandler.held[0];
					noteManager.playerHeld[1] = inputHandler.held[1];
					noteManager.playerHeld[2] = inputHandler.held[2];
					noteManager.playerHeld[3] = inputHandler.held[3];
				}
				noteManager.update(Conductor.songPosition);
			}

			if (boyfriend != null && !boyfriend.stunned) {
				inputHandler.update();
				inputHandler.processInputs(notes);
				inputHandler.processSustains(sustainNotes);
				updatePlayerStrums();
				if (paused)
					inputHandler.clearBuffer();
			}

			uiManager.update(elapsed);

			if (!cinematicMode && (gameState.isDead() || FlxG.keys.anyJustPressed(inputHandler.killBind)))
				gameOver();
		}

		if (SONG.needsVoices && !inCutscene && !_usingPerCharVocals && vocals != null) {
			if (funkin.audio.CoreAudio.getBaseVolume(vocals) < 1.0) {
				final newBase = Math.min(1.0, funkin.audio.CoreAudio.getBaseVolume(vocals) + elapsed * 2);
				funkin.audio.CoreAudio.setBaseVolume(vocals, newBase);
			}
		}

		if (controls.PAUSE && !paused) {
			if (VideoManager.isPlaying)
				pauseMenu();
			else if (startedCountdown && canPause && !inCutscene)
				pauseMenu();
		}

		if (FlxG.keys.justPressed.SEVEN && mods.ModManager.developerMode) {
			funkin.system.CursorManager.show();
			StateTransition.switchState(new ChartingState());
		}

		// Teclas 4/5: bajar/subir playback rate (solo durante la canción activa)
		if (!startingSong && generatedMusic && !paused) {
			if (FlxG.keys.justPressed.FOUR)
				playbackRate -= 0.25;
			if (FlxG.keys.justPressed.FIVE)
				playbackRate += 0.25;
		}

		if (FlxG.keys.justPressed.F8 && startedCountdown && canPause && mods.ModManager.developerMode) {
			ModChartEditorState.pendingManager = modChartManager;
			ModChartEditorState.pendingStrumsData = strumsGroups.map(function(g) return g.data);
			modChartManager = null;
			funkin.system.CursorManager.show();
			StateTransition.switchState(new ModChartEditorState());
		}

		if (startingSong && startedCountdown && !inCutscene)
			if (FlxG.sound.music != null && Conductor.songPosition >= 0)
				startSong();

		if (scriptsEnabled && !paused) {
			EventManager.update(Conductor.songPosition);
			ScriptHandler._argsUpdatePost[0] = elapsed;
			// Same rationale as onUpdate above — stage scripts handled by Stage.update.
			ScriptHandler.callOnNonStageScripts('onUpdatePost', ScriptHandler._argsUpdatePost);
		}
	}

	public var playbackRate(default, set):Float = 1.0;

	function set_playbackRate(v:Float):Float {
		v = Math.max(0.25, Math.min(4.0, v));
		playbackRate = v;
		FlxG.timeScale = v; // escala tweens, timers y elapsed → scripts/eventos aceleran igual

		if (noteManager != null)
			noteManager.targetScrollRate = v;
		return v;
	}

	private function updateDebugControls():Void {
		if (FlxG.keys.justPressed.F3) {
			showDebugStats = !showDebugStats;
			if (debugText != null)
				debugText.visible = showDebugStats;
		}
	}

	function pauseMenu() {
		persistentUpdate = false;
		persistentDraw = true;
		paused = true;

		// Congelar la cámara para que no siga transitando durante el pause
		cameraController?.freeze();

		if (gameplayTweens != null)
			gameplayTweens.active = false;
		if (gameplayTimers != null)
			gameplayTimers.active = false;

		if (countdown != null && countdown.running)
			countdown.pause();

		if (VideoManager.isPlaying)
			VideoManager.pause();
		else
			FlxG.sound.pause();

		if (FlxG.random.bool(0.1))
			StateTransition.switchState(new GitarooPause());
		else
			openSubState(new PauseSubState(inCutscene && VideoManager.isPlaying));
	}

	private function startSong():Void {
		startingSong = false;

		if (FlxG.sound.music != null && !inCutscene) {
			FlxG.sound.music.time = 0;
			funkin.audio.CoreAudio.setInstVolume(1.0); // FIX: restablecer volumen silenciado al cargar
			funkin.audio.CoreAudio.play(FlxG.sound.music);
			FlxG.sound.music.onComplete = endSong;
		}

		if (SONG.needsVoices && !inCutscene) {
			if (_usingPerCharVocals) {
				for (snd in vocalsPerChar) {
					if (snd == null)
						continue;
					snd.time = 0;
					funkin.audio.CoreAudio.play(snd);
				}
			} else if (vocals != null) {
				vocals.time = 0;
				funkin.audio.CoreAudio.play(vocals);
			}
		}

		#if desktop
		DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconRPC, true, FlxG.sound.music?.length ?? 0);
		#end

		if (scriptsEnabled)
			ScriptHandler.callOnScripts('onSongStart', ScriptHandler._argsEmpty);

		modChartManager?.onSongStart();
	}

	private function updatePlayerStrums():Void {
		if (playerStrumsGroup != null) {
			for (i in 0...4) {
				if (!isPlayingConfirm(i)) {
					if (inputHandler.pressed[i]) {
						playerStrumsGroup.playPressed(i);
					} else if (inputHandler.held[i]) {
						var strum = playerStrumsGroup.getStrum(i);
						if (strum?.animation?.curAnim?.name == 'static')
							playerStrumsGroup.playPressed(i);
					}
				}
				if (inputHandler.released[i])
					playerStrumsGroup.resetStrum(i);
			}
			return;
		}

		// Legacy fallback
		playerStrums.forEach(function(spr:FlxSprite) {
			if (spr.animation == null || spr.animation.curAnim == null)
				return;

			if (Std.isOfType(spr, StrumNote)) {
				var strumNote:StrumNote = cast(spr, StrumNote);
				var curAnim = strumNote.animation.curAnim.name;
				if (curAnim != 'confirm') {
					if (inputHandler.pressed[spr.ID])
						strumNote.playAnim('pressed');
					else if (inputHandler.held[spr.ID] && curAnim == 'static')
						strumNote.playAnim('pressed');
				}
				if (inputHandler.released[spr.ID])
					strumNote.playAnim('static');
			} else {
				var curAnim = spr.animation.curAnim.name;
				if (curAnim != 'confirm') {
					if (inputHandler.pressed[spr.ID])
						spr.animation.play('pressed');
					else if (inputHandler.held[spr.ID] && curAnim == 'static')
						spr.animation.play('pressed');
				}
				if (inputHandler.released[spr.ID]) {
					spr.animation.play('static');
					spr.centerOffsets();
				}
			}
		});
	}

	private function isPlayingConfirm(direction:Int):Bool {
		if (playerStrumsGroup != null) {
			var strum = playerStrumsGroup.getStrum(direction);
			return strum?.animation?.curAnim?.name == 'confirm';
		}
		return false;
	}

	#if android
	private function _onAndroidKeyDown(keyCode:Int, modifier:Int):Void {
		final BACK_KEY = #if (openfl >= "8.0.0") 0x4000010E #else 27 #end;
		if (keyCode == BACK_KEY && !paused && !inCutscene)
			openSubState(new PauseSubState(false));
	}
	#end

	private function onKeyRelease(direction:Int):Void {
		if (direction < 0 || direction > 3)
			return;
		noteManager?.releaseHoldNote(direction);
		heldNotes.remove(direction);
	}

	// ──────────────────────────────────────────────────────────────────────
	// HELPER: índice del jugador con fallback legacy
	// ──────────────────────────────────────────────────────────────────────

	private inline function _getPlayerCharIndex():Int {
		var idx = characterController.findPlayerIndex();
		return idx >= 0 ? idx : 2;
	}

	private inline function _getOpponentCharIndex():Int {
		var idx = characterController.findOpponentIndex();
		return idx >= 0 ? idx : 1;
	}

	// ──────────────────────────────────────────────────────────────────────
	// NOTE CALLBACKS
	// ──────────────────────────────────────────────────────────────────────

	private function onPlayerNoteHit(note:Note):Void {
		var _pressedAt:Float = inputHandler.pressSongPos[note.noteData];
		// FIX bot: el bot siempre golpea perfecto → noteDiff = 0 garantiza SICK
		var noteDiff:Float = funkin.gameplay.PlayState.isBotPlay ? 0.0 : Math.abs(note.strumTime - (_pressedAt >= 0 ? _pressedAt : Conductor.songPosition));
		inputHandler.pressSongPos[note.noteData] = -1;

		var rating:String = gameState.processNoteHit(noteDiff, note.isSustainNote);

		if (scriptsEnabled) {
			ScriptHandler._argsNote[0] = note;
			ScriptHandler._argsNote[1] = rating;
			if (ScriptHandler.callOnScriptsReturn('onPlayerNoteHit', ScriptHandler._argsNote, false) == true)
				return;
		}

		var _ntCancelled:Bool = funkin.gameplay.notes.NoteTypeManager.onPlayerHit(note, this);

		if (!note.wasGoodHit) {
			if (!_ntCancelled) {
				if (!note.isSustainNote) {
					gameState.modifyHealth(getHealthForRating(rating));
					uiManager.showRatingPopup(rating, gameState.combo);
					if (SaveData.data.hitsounds && rating == 'sick')
						playHitSound();
				} else {
					gameState.modifyHealth(0.023);
				}
			}

			var playerCharIndex = _getPlayerCharIndex();
			if (characterSlots.length > playerCharIndex) {
				characterController.singByIndex(playerCharIndex, note.noteData);
				var playerChar = characterController.getCharacter(playerCharIndex);
				cameraController.applyNoteOffset(playerChar ?? boyfriend, note.noteData);
			} else if (boyfriend != null) {
				characterController.sing(boyfriend, note.noteData);
				cameraController.applyNoteOffset(boyfriend, note.noteData);
			}

			noteManager.hitNote(note, rating);
			_setVocalsVolume(true, 1.0);

			for (hook in _noteHitHookArr)
				hook(note);
		}

		funkin.gameplay.notes.NoteTypeManager.onPlayerHitPost(note, this);

		if (scriptsEnabled) {
			ScriptHandler._argsNote[0] = note;
			ScriptHandler._argsNote[1] = rating;
			ScriptHandler.callOnScripts('onPlayerNoteHitPost', ScriptHandler._argsNote);
		}
		NoteSkinSystem.callSkinHook('onNoteHit', [note, rating]);
	}

	private function onPlayerNoteMiss(missedNote:funkin.gameplay.notes.Note):Void {
		// FIX bot: el bot nunca falla — segunda línea de defensa además del continue en NoteManager
		if (funkin.gameplay.PlayState.isBotPlay)
			return;
		if (scriptsEnabled) {
			ScriptHandler._argsNote[0] = missedNote;
			ScriptHandler._argsNote[1] = null;
			if (ScriptHandler.callOnScriptsReturn('onPlayerNoteMiss', ScriptHandler._argsNote, false) == true)
				return;
		}

		var direction:Int = missedNote != null ? missedNote.noteData : 0;
		var _ntMissCancelled:Bool = missedNote != null ? funkin.gameplay.notes.NoteTypeManager.onMiss(missedNote, this) : false;

		if (!_ntMissCancelled) {
			gameState.processMiss();
			gameState.modifyHealth(PlayStateConfig.MISS_HEALTH);

			if (_missSounds.length > 0) {
				var snd = _missSounds[_missSoundIdx % MISS_SOUND_POOL_SIZE];
				_missSoundIdx++;
				if (snd != null) {
					snd.volume = FlxG.random.float(0.1, 0.2);
					snd.play(true);
				}
			} else {
				FlxG.sound.play(Paths.soundRandom('missnote', 1, 3), FlxG.random.float(0.1, 0.2));
			}
		}

		var playerCharIndex = _getPlayerCharIndex();
		if (characterSlots.length > playerCharIndex) {
			if (characterSlots[playerCharIndex] != null)
				characterController.missByIndex(playerCharIndex, direction);
		} else if (boyfriend != null) {
			var anims = ['LEFT', 'DOWN', 'UP', 'RIGHT'];
			boyfriend.playAnim('sing' + anims[direction] + 'miss', true);
		}

		var gfIdx = characterController.findGFIndex();
		var gfChar = gfIdx >= 0 ? characterController.getCharacter(gfIdx) : gf;
		if (gfChar?.animOffsets.exists('sad') == true)
			gfChar.playAnim('sad', true);

		if (!_ntMissCancelled)
			uiManager.showMissPopup();

		_setVocalsVolume(true, 0.0);

		if (scriptsEnabled) {
			ScriptHandler._argsOne[0] = direction;
			ScriptHandler.callOnScripts('onPlayerNoteMissPost', ScriptHandler._argsOne);
			if (boyfriend != null) {
				ScriptHandler._argsAnim[0] = direction;
				ScriptHandler._argsAnim[1] = null;
				ScriptHandler.callOnCharacterScripts(boyfriend.curCharacter, 'onNoteMiss', ScriptHandler._argsAnim);
			}
		}
		NoteSkinSystem.callSkinHook('onNoteMiss', [missedNote, direction]);
		modChartManager?.onNoteMiss(missedNote);
	}

	private function onCPUNoteHit(note:Note):Void {
		if (scriptsEnabled) {
			ScriptHandler._argsNote[0] = note;
			ScriptHandler._argsNote[1] = null;
			ScriptHandler.callOnScripts('onOpponentNoteHit', ScriptHandler._argsNote);
			ScriptHandler._argsNote[0] = 'dad';
			ScriptHandler._argsNote[1] = note.noteData;
			ScriptHandler.callOnScripts('onCharacterSing', ScriptHandler._argsNote);
		}

		funkin.gameplay.notes.NoteTypeManager.onCPUHit(note, this);

		if (metaData == null || !metaData.disableCameraZoom)
			cameraController.zoomEnabled = true;

		var altAnim:String = getHasAltAnim(curStep) ? '-alt' : '';
		var dadIndex:Int = _getOpponentCharIndex();

		var section = getSectionAsClass(curStep);
		if (section != null) {
			var charIndices = section.getActiveCharacterIndices(1, 2);

			if (section.gfSing == true) {
				characterController.singGF(note.noteData, altAnim);
			} else if (characterSlots.length > dadIndex && characterSlots[dadIndex]?.isActive == true) {
				characterController.singByIndex(dadIndex, note.noteData, altAnim);
			} else if (dad != null) {
				characterController.sing(dad, note.noteData, altAnim);
			}

			// Routing adicional para múltiples grupos CPU
			if (note.strumsGroupIndex > 0 && strumsGroups.length > note.strumsGroupIndex) {
				var sg = strumsGroups[note.strumsGroupIndex].data.id;
				var extraIdx = characterController.findByStrumsGroup(sg);
				if (extraIdx >= 0 && extraIdx != dadIndex)
					characterController.singByIndex(extraIdx, note.noteData, altAnim);
			}

			var camChar = charIndices.length > 0 ? characterController.getCharacter(charIndices[0]) : dad;
			if (camChar != null)
				cameraController.applyNoteOffset(camChar, note.noteData);
		} else {
			// Fallback sin sección
			if (characterSlots.length > dadIndex && characterSlots[dadIndex]?.isActive == true)
				characterController.singByIndex(dadIndex, note.noteData, altAnim);
			else if (dad != null)
				characterController.sing(dad, note.noteData, altAnim);

			if (dad != null)
				cameraController.applyNoteOffset(dad, note.noteData);
		}

		if (SONG.needsVoices)
			_setVocalsVolume(false, 1.0);
	}

	private function getHealthForRating(rating:String):Float {
		var data = RatingManager.getByName(rating);
		return data != null ? data.health : 0.0;
	}

	// ──────────────────────────────────────────────────────────────────────
	// SOUND POOLS
	// ──────────────────────────────────────────────────────────────────────
	private var _hitSounds:Array<FlxSound> = [];
	private var _hitSoundIdx:Int = 0;
	private var _missSounds:Array<FlxSound> = [];
	private var _missSoundIdx:Int = 0;

	private static inline var HIT_SOUND_POOL_SIZE:Int = 2;
	private static inline var MISS_SOUND_POOL_SIZE:Int = 3;

	private function initHitSoundPool():Void {
		_hitSounds = _fillSoundPool(HIT_SOUND_POOL_SIZE, function(_) return Paths.sound('hitsounds/hit-1'));
		_missSounds = _fillSoundPool(MISS_SOUND_POOL_SIZE, function(i) return Paths.sound('missnote${(i % 3) + 1}'));
	}

	private function _fillSoundPool(size:Int, pathFn:Int->Dynamic):Array<FlxSound> {
		var pool:Array<FlxSound> = [];
		for (i in 0...size) {
			var snd = new FlxSound();
			try {
				snd.loadEmbedded(pathFn(i));
			} catch (_:Dynamic) {}
			snd.looped = false;
			FlxG.sound.list.add(snd);
			pool.push(snd);
		}
		return pool;
	}

	private function _destroySoundPoolItems(pool:Array<FlxSound>):Void {
		for (snd in pool) {
			if (snd == null)
				continue;
			snd.stop();
			FlxG.sound.list.remove(snd, true);
			snd.destroy();
		}
		pool.resize(0);
	}

	private function playHitSound():Void {
		if (_hitSounds.length == 0)
			initHitSoundPool();
		var snd = _hitSounds[_hitSoundIdx % HIT_SOUND_POOL_SIZE];
		_hitSoundIdx++;
		if (snd == null)
			return;
		snd.volume = 1 + FlxG.random.float(-0.2, 0.2);
		snd.play(true);
	}

	// ──────────────────────────────────────────────────────────────────────
	// SUBSTATE
	// ──────────────────────────────────────────────────────────────────────

	override function openSubState(SubState:FlxSubState) {
		if (paused) {
			if (scriptsEnabled) {
				if (ScriptHandler.callOnScriptsReturn('onPause', ScriptHandler._argsEmpty, false) == true)
					return;
			}

			modChartManager?.onPause();

			if (FlxG.sound.music != null) {
				FlxG.sound.music.pause();
				_pauseAllVocals();
			}

			#if desktop updatePresence(); #end
		}

		super.openSubState(SubState);
	}

	override function closeSubState() {
		if (paused) {
			var shouldResync = isPlaying && !isRewinding && FlxG.sound.music != null && !startingSong && !VideoManager.isPlaying && !inCutscene;

			if (shouldResync) {
				if (FlxG.sound.music.playing)
					Conductor.songPosition = FlxG.sound.music.time;
				else
					resyncVocals();
			}
			paused = false;

			// Descongelar la cámara para que continúe la transición
			cameraController?.unfreeze();

			if (gameplayTweens != null)
				gameplayTweens.active = true;
			if (gameplayTimers != null)
				gameplayTimers.active = true;
			if (countdown != null && countdown.running)
				countdown.resume();

			if (scriptsEnabled)
				ScriptHandler.callOnScripts('onResume', ScriptHandler._argsEmpty);

			modChartManager?.onResume();
		}

		super.closeSubState();
	}

	// ──────────────────────────────────────────────────────────────────────
	// BEAT / STEP HIT
	// ──────────────────────────────────────────────────────────────────────

	override function beatHit() {
		super.beatHit();
		if (isRewinding) return;

		for (hook in _beatHookArr)
			hook(curBeat);
		currentStage?.beatHit(curBeat);
		modChartManager?.onBeatHit(curBeat);

		// ── Countdown tick (beats -4…-1 → step 0-3; beat 0 = "GO!" = step 4) ──
		if (startingSong && curBeat >= -4 && curBeat <= 0)
			modChartManager?.onCountdownTick(curBeat + 4);

		if (scriptsEnabled)
			ScriptHandler._argsBeat[0] = curBeat;
		ScriptHandler.callOnScripts('onBeatHit', ScriptHandler._argsBeat);

		characterController.danceOnBeat(curBeat);
		if (curBeat % 4 == 0)
			cameraController.bumpZoom();
		uiManager.onBeatHit(curBeat);
	}

	override function stepHit() {
		super.stepHit();
		if (isRewinding) return;
		
		for (hook in _stepHookArr)
			hook(curStep);
		modChartManager?.onStepHit(curStep);
		currentStage?.stepHit(curStep);

		if (scriptsEnabled) {
			ScriptHandler._argsStep[0] = curStep;
			ScriptHandler.callOnScripts('onStepHit', ScriptHandler._argsStep);

			final section:Int = curStep >> 4;
			if (section != cachedSectionIndex) {
				ScriptHandler._argsOne[0] = section;
				ScriptHandler.callOnScripts('onSectionHit', ScriptHandler._argsOne);
			}
		}

		if (FlxG.sound.music != null && Math.abs(FlxG.sound.music.time - Conductor.songPosition) > 100) {
			if (_resyncCooldown <= 0) {
				resyncVocals();
				_resyncCooldown = 8;
			}
		}
		if (_resyncCooldown > 0)
			_resyncCooldown--;
	}

	function resyncVocals():Void {
		_pauseAllVocals();

		if (FlxG.sound.music != null) {
			if (!FlxG.sound.music.playing)
				funkin.audio.CoreAudio.play(FlxG.sound.music);
			else
				FlxG.sound.music.resume();
			Conductor.songPosition = FlxG.sound.music.time;
		}

		if (_usingPerCharVocals) {
			for (snd in vocalsPerChar) {
				if (snd == null)
					continue;
				snd.time = Conductor.songPosition;
				snd.resume();
			}
		} else if (SONG.needsVoices && vocals != null) {
			vocals.time = Conductor.songPosition;
			vocals.resume();
		}
	}

	// ──────────────────────────────────────────────────────────────────────
	// END SONG
	// ──────────────────────────────────────────────────────────────────────

	public function endSong():Void {
		if (scriptsEnabled)
			ScriptHandler.callOnScripts('onSongEnd', ScriptHandler._argsEmpty);

		if (cinematicMode) {
			isPlaying = false;
			FlxG.sound.music?.pause();
			if (onCinematicEnd != null)
				onCinematicEnd();
			return;
		}

		playbackRate = 1.0;

		canPause = false;
		if (FlxG.sound.music != null)
			funkin.audio.CoreAudio.setInstVolume(0.0);
		_setVocalsVolume(true, 0.0);
		_setVocalsVolume(false, 0.0);
		isPlaying = false;

		if (SONG.validScore) {
			final diffSuffix = funkin.data.CoolUtil.difficultySuffix();
			final _prevScore = Highscore.getScore(SONG.song, diffSuffix);
			gameState.isNewHighscore = (gameState.score > _prevScore);
			Highscore.saveScore(SONG.song, gameState.score, diffSuffix);
			Highscore.saveRating(SONG.song, gameState.accuracy, diffSuffix);
		}

		if (scriptsEnabled) {
			var _continueCb:Dynamic = function() {
				inCutscene = false;
				continueAfterSong();
			};
			if (ScriptHandler.callOnScriptsReturn('onOutroCutscene', [_continueCb], false) == true) {
				inCutscene = true;
				return;
			}
		}

		if (metaData != null && (metaData.outroVideo != null || metaData.outroCutscene != null)) {
			final vidKey = metaData.outroVideo;
			final cutKey = metaData.outroCutscene;
			metaData.outroVideo = null;
			metaData.outroCutscene = null;

			var runOutroVideo:Void->Void = null;
			runOutroVideo = function() {
				if (vidKey != null && VideoManager._resolvePath(vidKey) != null) {
					isCutscene = true;
					VideoManager.playCutscene(vidKey, function() {
						isCutscene = false;
						continueAfterSong();
					});
				} else {
					isCutscene = false;
					continueAfterSong();
				}
			};

			var runSpriteCutscene:Void->Void = null;
			runSpriteCutscene = function() {
				if (cutKey != null && SpriteCutscene.exists(cutKey, songId)) {
					isCutscene = true;
					SpriteCutscene.create(this, cutKey, songId, function() {
						runOutroVideo();
					});
				} else
					runOutroVideo();
			};

			if (showOutroDialogue() && isStoryMode) {
				if (checkForDialogue('outro')) {
					isCutscene = true;
					showDialogue('outro', function() {
						runSpriteCutscene();
					});
				} else
					runSpriteCutscene();
			} else
				runSpriteCutscene();
			return;
		}

		if (showOutroDialogue() && isStoryMode)
			return;
		if (!isCutscene)
			continueAfterSong();
	}

	function gameOver():Void {
		if (scriptsEnabled)
			if (ScriptHandler.callOnScriptsReturn('onGameOver', ScriptHandler._argsEmpty, false) == true)
				return;

		if (boyfriend == null) {
			StateTransition.switchState(new funkin.menus.MainMenuState());
			return;
		}

		GameState.deathCounter++;
		boyfriend.stunned = true;
		persistentUpdate = false;
		persistentDraw = false;
		paused = true;

		FlxG.sound.music?.stop();
		openSubState(new GameOverSubstate(boyfriend.getScreenPosition().x, boyfriend.getScreenPosition().y, boyfriend));

		#if desktop
		DiscordClient.changePresence("GAME OVER", SONG.song + " (" + storyDifficultyText + ")", iconRPC);
		#end
	}

	// ──────────────────────────────────────────────────────────────────────
	// SECTION HELPERS
	// ──────────────────────────────────────────────────────────────────────

	public function getCharacterByName(name:String):Null<Character> {
		if (name == null || name == '')
			return null;
		var n = name.toLowerCase().trim();

		var idx = Std.parseInt(n);
		if (idx != null && idx >= 0 && idx < characterSlots.length)
			return characterSlots[idx].character;

		switch (n) {
			case 'bf', 'boyfriend', 'player', 'player1':
				return boyfriend;
			case 'dad', 'opponent', 'player2':
				return dad;
			case 'gf', 'girlfriend', 'player3':
				return gf;
		}

		for (slot in characterSlots)
			if (slot.character?.curCharacter.toLowerCase() == n)
				return slot.character;

		return null;
	}

	public function getSection(step:Int):SwagSection {
		final sectionIndex:Int = step >> 4;
		if (cachedSectionIndex == sectionIndex && cachedSection != null)
			return cachedSection;

		cachedSectionIndex = sectionIndex;
		cachedSection = SONG.notes[sectionIndex] ?? null;
		return cachedSection;
	}

	public function getSectionAsClass(step:Int):Section {
		final sectionIndex:Int = step >> 4;
		if (_cachedSectionClassIdx == sectionIndex && _cachedSectionClass != null)
			return _cachedSectionClass;

		final swagSection = getSection(step);
		if (swagSection == null) {
			_cachedSectionClassIdx = sectionIndex;
			_cachedSectionClass = null;
			return null;
		}

		if (_cachedSectionClass == null)
			_cachedSectionClass = new Section();

		_cachedSectionClass.sectionNotes = swagSection.sectionNotes;
		_cachedSectionClass.lengthInSteps = swagSection.lengthInSteps;
		_cachedSectionClass.typeOfSection = swagSection.typeOfSection;
		_cachedSectionClass.mustHitSection = swagSection.mustHitSection;
		_cachedSectionClass.characterIndex = swagSection.characterIndex ?? -1;
		_cachedSectionClass.strumsGroupId = swagSection.strumsGroupId;
		_cachedSectionClass.activeCharacters = swagSection.activeCharacters;

		_cachedSectionClassIdx = sectionIndex;
		return _cachedSectionClass;
	}

	public function getMustHitSection(step:Int):Bool {
		var section = getSection(step);
		return section?.mustHitSection ?? true;
	}

	public function getHasAltAnim(step:Int):Bool {
		var section = getSection(step);
		return section?.altAnim ?? false;
	}

	// ──────────────────────────────────────────────────────────────────────
	// REWIND RESTART
	// ──────────────────────────────────────────────────────────────────────

	public function startRewindRestart():Void {
		if (isRewinding)
			return;

		if (FlxG.sound.music != null) {
			funkin.audio.CoreAudio.setInstVolume(0.0);
			FlxG.sound.music.pause();
		}
		_setVocalsVolume(true, 0.0);
		_setVocalsVolume(false, 0.0);
		_pauseAllVocals();

		if (camHUD.alpha == 0)
			camHUD.alpha = 1;
		if (!camHUD.visible)
			camHUD.visible = true;

		_rewindFromPos = Conductor.songPosition;
		_rewindToPos = -(Conductor.crochet * 5);

		var songProgress = Math.max(0, Conductor.songPosition);
		_rewindDuration = songProgress < 500 ? 0.1 : Math.max(0.5, Math.min(1.5, songProgress / 8000.0));
		_rewindTimer = 0;
		isRewinding = true;
		paused = false;
		canPause = false;
		inCutscene = false;

		for (slot in characterSlots) {
			if (slot.character != null) {
				slot.character.animation?.pause();
				slot.character.active = false;
			}
		}

		if (inputHandler != null) {
			inputHandler.resetMash();
			inputHandler.clearBuffer();
			for (i in 0...4)
				inputHandler.held[i] = false;
		}

		trace('[PlayState] Rewind restart iniciado — desde ${_rewindFromPos}ms, duración ${_rewindDuration}s');
	}

	private function _finishRestart():Void {
		isRewinding = false;

		gameState.reset();

		Conductor.changeBPM(SONG.bpm);
		Conductor.mapBPMChanges(SONG);
		Conductor.songPosition = _rewindToPos;

		_rewindRestoreSkins();
		_rewindResetAudio();
		_rewindResetFlags();
		_rewindResetStrums();

		if (noteManager != null)
			noteManager.rewindTo(_rewindToPos);
		if (scriptsEnabled)
			EventManager.rewindToStart();
		if (cameraController != null)
			cameraController.resetToInitial();
		if (characterController != null)
			characterController.forceIdleAll();
		if (modChartManager != null)
			modChartManager.resetToStart();
		if (scriptsEnabled)
			ScriptHandler.callOnScripts('onRestart', ScriptHandler._argsEmpty);

		for (slot in characterSlots) {
			if (slot.character != null) {
				slot.character.active = true;
			}
		}

		final _restartTimer = new flixel.util.FlxTimer(gameplayTimers).start(0.15, function(_) {
			startCountdown();
		});
		trace('[PlayState] Rewind restart completado.');
	}

	private function _rewindRestoreSkins():Void {
		if (metaData?.noteSkin != null && metaData.noteSkin != 'default' && metaData.noteSkin != '')
			NoteSkinSystem.setTemporarySkin(metaData.noteSkin);
		else
			NoteSkinSystem.applySkinForStage(curStage);

		if (metaData?.noteSplash != null && metaData.noteSplash != '')
			NoteSkinSystem.setTemporarySplash(metaData.noteSplash);
		else
			NoteSkinSystem.applySplashForStage(curStage);

		var _skinData = NoteSkinSystem.getCurrentSkinData();
		for (group in strumsGroups)
			group.reloadAllStrumSkins(_skinData);

		_applyGroupSkinOverrides();
	}

	private function _rewindResetAudio():Void {
		FlxG.sound.resume();

		if (_usingPerCharVocals) {
			for (snd in vocalsPerChar) {
				if (snd == null)
					continue;
				snd.time = 0;
				snd.stop();
				funkin.audio.CoreAudio.setBaseVolume(snd, 1.0);
			}
		} else if (vocals != null) {
			vocals.time = 0;
			vocals.stop();
			funkin.audio.CoreAudio.setBaseVolume(vocals, 1.0);
		}

		if (FlxG.sound.music != null) {
			FlxG.sound.music.time = 0;
			FlxG.sound.music.pause();
			funkin.audio.CoreAudio.setInstVolume(1.0);
		}
	}

	private function _rewindResetFlags():Void {
		startedCountdown = false;
		startingSong = false;
		generatedMusic = true;
		canPause = true;
		inCutscene = false;
		startFromTime = null;

		heldNotes.clear();
		if (grpNoteSplashes != null)
			grpNoteSplashes.forEachAlive(function(s) {
				s.kill();
			});
	}

	private function _rewindResetStrums():Void {
		var _isDownscroll = SaveData.data.downscroll;
		var _isMiddlescroll = SaveData.data.middlescroll;
		var _strumY:Float = _isDownscroll ? FlxG.height - 150 : PlayStateConfig.STRUM_LINE_Y;
		strumLiney = _strumY;

		if (noteManager != null) {
			noteManager.strumLineY = _strumY;
			noteManager.downscroll = _isDownscroll;
			noteManager.middlescroll = _isMiddlescroll;
		}

		_updateLaneBackdrop();

		for (group in strumsGroups) {
			group.applyScrollSettings(_isDownscroll, _isMiddlescroll, PlayStateConfig.STRUM_LINE_Y);
			final shouldBeVisible = (group.isVisible == true);

			group.strums.forEach(function(s:FlxSprite) {
				if (Std.isOfType(s, funkin.gameplay.notes.StrumNote))
					cast(s, funkin.gameplay.notes.StrumNote).playAnim('static', true);

				if (group.isCPU && _isMiddlescroll) {
					s.visible = false;
					s.alpha = 0;
				} else {
					s.visible = shouldBeVisible;
					s.alpha = shouldBeVisible ? 1.0 : 0.0;
				}
			});
		}

		// Fallback
		if (strumsGroups.length == 0) {
			_resetStrumsGroupToStatic(playerStrums);
			_resetStrumsGroupToStatic(cpuStrums);
		}
	}

	private inline function _resetStrumsGroupToStatic(group:FlxTypedGroup<FlxSprite>):Void {
		if (group == null)
			return;
		group.forEach(function(s:FlxSprite) {
			if (Std.isOfType(s, funkin.gameplay.notes.StrumNote))
				cast(s, funkin.gameplay.notes.StrumNote).playAnim('static', true);
		});
	}

	// ──────────────────────────────────────────────────────────────────────
	// DESTROY
	// ──────────────────────────────────────────────────────────────────────

	override function destroy() {
		// Auto-reset del modo osu-like para no contaminar la siguiente sesión
		PlayStateConfig.minimalMode = false;

		// FIX Bug 3: EventManager.clear() (which calls releasePrecachePool()) was
		// only reached inside the `if (scriptsEnabled)` block below. On restart or
		// switchState paths that bypass destroy(), dummy Characters in _precachePool
		// were never freed. Calling it unconditionally here — with a guard — ensures
		// the pool is always released regardless of the scriptsEnabled flag.
		try {
			funkin.scripting.events.EventManager.clear();
		} catch (_:Dynamic) {}

		funkin.audio.CoreAudio.stopAll();

		FlxG.signals.focusLost.remove(_onGlobalFocusLost);

		if (gameplayTweens != null) {
			FlxG.plugins.remove(gameplayTweens);
			gameplayTweens = null;
		}
		if (gameplayTimers != null) {
			FlxG.plugins.remove(gameplayTimers);
			gameplayTimers = null;
		}

		// Statics
		instance = null;
		isPlaying = false;
		cpuStrums = null;
		startingSong = false;

		#if android
		lime.app.Application.current.window.onKeyDown.remove(_onAndroidKeyDown);
		#end

		_clearVocals();

		if (FlxG.sound.music != null) {
			FlxG.sound.list.remove(FlxG.sound.music, true);
			FlxG.sound.music = null;
		}

		if (scriptsEnabled) {
			ScriptHandler.callOnScripts('onDestroy', ScriptHandler._argsEmpty);
			ScriptHandler.clearSongScripts();
			ScriptHandler.clearStageScripts();
			ScriptHandler.clearCharScripts();
			EventManager.clear();
			funkin.scripting.events.EventHandlerLoader.clearContext('chart');
			funkin.scripting.events.EventHandlerLoader.clearContext('global');
		}

		optimizationManager?.destroy();
		optimizationManager = null;

		vocalsPerChar.clear();
		vocalsPerChar = null;

		// SONG = null;

		FlxG.timeScale = 1.0;
		playbackRate = 1.0;

		cameraController?.destroy();
		cameraController = null;

		// FIX: characterController nunca se destruía → los CharacterSlots y sus
		// referencias a Character quedaban vivos en heap tras salir de la canción.
		characterController?.destroy();
		characterController = null;

		noteManager?.destroy();
		noteManager = null;

		holdMesh?.destroy();
		holdMesh = null;

		modChartManager?.destroy();
		modChartManager = null;

		if (noteBatcher != null) {
			remove(noteBatcher, true);
			noteBatcher.destroy();
			noteBatcher = null;
		}

		NoteSkinSystem.restoreGlobalSkin();
		NoteSkinSystem.restoreGlobalSplash();
		NoteSkinSystem.destroyScripts();
		heldNotes.clear();
		heldNotes = null;

		// resize(0) reutiliza el array existente sin allocar — más eficiente que = []
		characterSlots.resize(0);
		characterSlots = null;
		strumsGroups.resize(0);
		strumsGroups = null;
		strumsGroupMap.clear();
		strumsGroupMap = null;
		activeCharIndices.resize(0);
		activeCharIndices = null;

		RatingManager.destroy();

		_destroySoundPoolItems(_hitSounds);
		_destroySoundPoolItems(_missSounds);

		_hitSounds = null;
		_missSounds = null;

		countdown?.destroy();
		countdown = null;

		// Los listeners de KeyboardEvent se registran en new() y deben eliminarse
		// explícitamente — sin esto quedan activos tras destruir el PlayState.
		if (inputHandler != null) {
			inputHandler.destroy();
			inputHandler = null;
		}

		// Hooks: resize(0) evita alloc de nuevo array vacío
		onBeatHitHooks.clear();
		onStepHitHooks.clear();
		onUpdateHooks.clear();
		onNoteHitHooks.clear();
		onNoteMissHooks.clear();
		_beatHookArr.resize(0);
		_stepHookArr.resize(0);
		_updateHookArr.resize(0);
		_noteHitHookArr.resize(0);
		_noteMissHookArr.resize(0);
		_beatHookArr = null;
		_stepHookArr = null;
		_updateHookArr = null;
		_noteHitHookArr = null;
		_noteMissHookArr = null;

		_cachedSectionClass = null;
		_cachedSectionClassIdx = -2;
		cachedSection = null;

		// Nullear objetos de escena grandes ANTES de super.destroy() para que el GC
		// pueda reclamar la memoria mientras seguimos controlando el estado.
		// FPS Plus hace lo mismo en su switchState() con removeSound().
		laneBackdrop = null;
		scoreManager = null;
		gameState = null;
		uiManager = null;
		skinSystem = null;
		boyfriend = null;
		dad = null;
		gf = null;
		currentStage = null;

		// Resumir el GC ANTES de super.destroy(): con el GC activo, el destructor
		// de FlxTypedGroup liberará las notas del pool en el mismo frame.
		if (_gcPausedForSong) {
			_gcPausedForSong = false;
			MemoryUtil.resumeGC();
		}

		super.destroy();

		// Nullear grupos DESPUÉS de super.destroy() (super los destruye internamente)
		notes = null;
		sustainNotes = null;
		strumLineNotes = null;
		playerStrums = null;
		grpNoteSplashes = null;
		grpHoldCovers = null;

		StickerTransition.invalidateCache();

		// FIX RAM: Paths.clearUnusedMemory() hacía Gc.run(true) + Gc.compact() aquí,
		// pero FunkinCache.postStateSwitch ejecuta otro collectMajor() completo justo
		// después de que el nuevo state haya cargado sus assets. Dos GC completos
		// consecutivos = stutter doble sin beneficio extra. Se reemplaza por solo
		// bitmap.clearUnused() para limpiar wrappers FlxGraphic huérfanos sin bloquear.
		// El GC completo final queda exclusivamente en manos de postStateSwitch,
		// que es el único punto donde se sabe exactamente qué assets sobreviven.
		try {
			flixel.FlxG.bitmap.clearUnused();
		} catch (_:Dynamic) {}
		Paths.pruneAtlasCache();

		funkin.cache.PathsCache.setGameplayMode(false);
		funkin.cache.PathsCache.instance.flushGPUCache();
	}

	// ──────────────────────────────────────────────────────────────────────
	// DIALOGUES
	// ──────────────────────────────────────────────────────────────────────

	private function checkForDialogue(type:String = 'intro'):Bool {
		var dialoguePath = Paths.resolve('songs/${songId}/${type}.json');
		#if sys
		return sys.FileSystem.exists(dialoguePath);
		#else
		try {
			return DialogueData.loadDialogue(dialoguePath) != null;
		} catch (_:Dynamic) {
			return false;
		}
		#end
	}

	private function showDialogue(type:String = 'intro', ?onFinish:Void->Void):Void {
		isCutscene = true;
		var doof:DialogueBoxImproved = null;
		try {
			doof = new DialogueBoxImproved(songId, type);
		} catch (_:Dynamic) {
			if (onFinish != null)
				onFinish();
			return;
		}

		if (doof == null) {
			if (onFinish != null)
				onFinish();
			return;
		}

		doof.finishThing = function() {
			inCutscene = false;
			if (onFinish != null)
				onFinish();
		};
		add(doof);
		doof.cameras = [camHUD];
	}

	private function showOutroDialogue():Bool {
		if (!checkForDialogue('outro'))
			return false;
		isCutscene = true;
		showDialogue('outro', function() {
			FlxG.sound.music?.stop();
			isCutscene = false;
			continueAfterSong();
		});
		return true;
	}

	private function continueAfterSong():Void {
		if (isStoryMode) {
			campaignScore += gameState.score;
			storyPlaylist.remove(storyPlaylist[0]);

			if (storyPlaylist.length <= 0) {
				FlxG.sound.playMusic(Paths.music('freakyMenu'));
				if (SONG.validScore)
					Highscore.saveWeekScore(storyWeek, campaignScore, funkin.data.CoolUtil.difficultySuffix());
				SaveData.flush();
				LoadingState.loadAndSwitchState(new ResultScreen());
			} else {
				SONG = Song.loadFromJson(storyPlaylist[0].toLowerCase() + CoolUtil.difficultySuffix(), storyPlaylist[0]);
				FlxG.sound.music?.stop();
				LoadingState.loadAndSwitchState(new PlayState());
			}
		} else {
			FlxG.sound.music?.stop();
			_stopAllVocals();
			LoadingState.loadAndSwitchState(new ResultScreen());
		}
	}

	// ──────────────────────────────────────────────────────────────────────
	// GAMEPLAY SETTINGS (called from pause menu)
	// ──────────────────────────────────────────────────────────────────────

	public function updateGameplaySettings():Void {
		if (!paused)
			return;

		if (uiManager != null)
			uiManager.visible = !SaveData.data.HUD;
		updateAntialiasing();
		if (inputHandler != null)
			inputHandler.ghostTapping = SaveData.data.ghosttap;
	}

	private function updateAntialiasing():Void {
		if (currentStage == null)
			return;
		final skinData = NoteSkinSystem.getCurrentSkinData();
		if (skinData?.isPixel == true)
			return;

		final aa:Bool = (SaveData.data.antialiasing == true);
		for (sprite in currentStage.members)
			if (sprite != null && Std.isOfType(sprite, FlxSprite))
				(cast sprite : FlxSprite).antialiasing = aa;

		if (boyfriend != null)
			boyfriend.antialiasing = aa;
		if (dad != null)
			dad.antialiasing = aa;
		if (gf != null)
			gf.antialiasing = aa;
	}

	// ──────────────────────────────────────────────────────────────────────
	// FOCUS
	// ──────────────────────────────────────────────────────────────────────

	function _onGlobalFocusLost():Void {
		if (paused) {
			_pauseVocalsOnly();
			return;
		}
		if (!canPause)
			return;
		pauseMenu();
	}

	function _pauseVocalsOnly():Void {
		_pauseAllVocals();
	}

	override public function onFocusLost():Void {
		super.onFocusLost();
		if (!paused && canPause)
			pauseMenu();
	}

	override public function onFocus():Void {
		super.onFocus();
		// Compactar el GC al recuperar foco (FPS Plus hace Utils.gc() aquí).
		// Libera fragmentación acumulada durante la pausa sin coste perceptible.
		#if cpp
		cpp.vm.Gc.compact();
		#end
		if (FlxG.sound.music != null && !startingSong && generatedMusic && !paused) {
			final t = FlxG.sound.music.time;
			if (SONG.needsVoices)
				_syncVocalsTime(t);
			funkin.audio.CoreAudio.resumeAll();
		}
	}

	// ──────────────────────────────────────────────────────────────────────
	// PER-CHAR VOCALS
	// ──────────────────────────────────────────────────────────────────────

	private function _tryLoadPerCharVocals(diffSuffix:String):Bool {
		_vocalsPlayerKeys = [];
		_vocalsOpponentKeys = [];

		var candidates:Array<{name:String, type:String}> = [];

		if (SONG.characters != null && SONG.characters.length > 0) {
			for (c in SONG.characters) {
				var t = c.type ?? 'Opponent';
				if (t == 'Girlfriend' || t == 'Other')
					continue;
				var dup = false;
				for (prev in candidates)
					if (prev.name == c.name) {
						dup = true;
						break;
					}
				if (!dup)
					candidates.push({name: c.name, type: t});
			}
		}

		if (candidates.length == 0) {
			var p1 = SONG.player1 ?? 'bf';
			var p2 = SONG.player2 ?? 'dad';
			candidates.push({name: p1, type: 'Player'});
			if (p2 != p1)
				candidates.push({name: p2, type: 'Opponent'});
		}

		var loaded = 0;
		for (cand in candidates) {
			var snd = Paths.loadVoicesForChar(SONG.song, cand.name, diffSuffix);
			if (snd == null)
				continue;

			FlxG.sound.list.add(snd);
			vocalsPerChar.set(cand.name, snd);
			funkin.audio.CoreAudio.addVocal(cand.name, snd);
			snd.pause(); // FIX: pausar DESPUÉS de addVocal para que _applyTo no reactive el buffer

			if (cand.type == 'Player' || cand.type == 'Boyfriend')
				_vocalsPlayerKeys.push(cand.name);
			else
				_vocalsOpponentKeys.push(cand.name);

			loaded++;
		}

		trace('[PlayState] Per-char vocals cargadas: $loaded / ${candidates.length} personajes');
		return loaded > 0;
	}

	private function _cleanPerCharVocals():Void {
		for (snd in vocalsPerChar) {
			if (snd == null)
				continue;
			FlxG.sound.list.remove(snd, true);
			snd.stop();
			snd.destroy();
		}
		vocalsPerChar.clear();
		// Vaciar las arrays de keys sin reasignar (evita GC pressure)
		_vocalsPlayerKeys.resize(0);
		_vocalsOpponentKeys.resize(0);
		_usingPerCharVocals = false;
	}

	// ──────────────────────────────────────────────────────────────────────
	// MISC
	// ──────────────────────────────────────────────────────────────────────

	private function _assignStageCameras(group:flixel.group.FlxGroup, cams:Array<flixel.FlxCamera>):Void {
		for (member in group.members) {
			if (member == null)
				continue;
			member.cameras = cams;
			if (Std.isOfType(member, flixel.group.FlxGroup))
				_assignStageCameras(cast member, cams);
		}
	}
}
