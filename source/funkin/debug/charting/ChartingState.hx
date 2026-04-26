package funkin.debug.charting;
import coolui.CoolInputText;
import coolui.CoolNumericStepper;
import coolui.CoolCheckBox;
import coolui.CoolDropDown;
import coolui.CoolTabMenu;
import funkin.data.Conductor.BPMChangeEvent;
import funkin.data.Section.SwagSection;
import funkin.data.Song.SwagSong;
import funkin.data.Song.CharacterSlotData;
import funkin.data.Song.StrumsGroupData;
import funkin.data.LevelFile;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.addons.display.FlxGridOverlay;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.group.FlxGroup;
import flixel.math.FlxMath;
import flixel.math.FlxPoint;
import flixel.sound.FlxSound;
import flixel.text.FlxText;
import funkin.data.Conductor;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.ui.FlxButton;
import flixel.util.FlxColor;
import flixel.util.FlxStringUtil;
import flixel.util.FlxTimer;
import haxe.Json;
import haxe.io.Path as HaxePath;
import lime.utils.Assets;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import openfl.net.FileReference;
import funkin.menus.MainMenuState;
import openfl.utils.ByteArray;
import funkin.states.LoadingState;
import funkin.gameplay.PlayState;
import funkin.gameplay.notes.Note;
import funkin.gameplay.notes.NoteTypeManager;
import funkin.gameplay.objects.character.CharacterList;
import flixel.util.FlxSpriteUtil;
#if desktop
import data.Discord.DiscordClient;
#end
import funkin.gameplay.objects.character.HealthIcon;

// init
using StringTools;

// BPM detection & waveform

class ChartingState extends funkin.states.MusicBeatState
{
	// COLORES — actualizados desde EditorTheme en _applyTheme()
	static var BG_DARK:Int = 0xFF1E1E1E;
	static var BG_PANEL:Int = 0xFF2D2D2D;
	static var ACCENT_CYAN:Int = 0xFF00D9FF;
	static var ACCENT_PINK:Int = 0xFFFF00E5;
	static var ACCENT_GREEN:Int = 0xFF00FF88;
	static var ACCENT_SUCCESS:Int = 0xFF00FF88;
	static var ACCENT_WARNING:Int = 0xFFFFAA00;
	static var ACCENT_ERROR:Int = 0xFFFF3366;
	static var TEXT_WHITE:Int = 0xFFFFFFFF;
	static var TEXT_GRAY:Int = 0xFFAAAAAA;

	/** Sincroniza las vars de color con el tema activo. */
	static function _applyTheme():Void
	{
		var T = funkin.debug.themes.EditorTheme.current;
		BG_DARK = T.bgDark;
		BG_PANEL = T.bgPanel;
		ACCENT_CYAN = T.accent;
		ACCENT_PINK = T.accentAlt;
		ACCENT_GREEN = T.success;
		ACCENT_SUCCESS = T.success;
		ACCENT_WARNING = T.warning;
		ACCENT_ERROR = T.error;
		TEXT_WHITE = T.textPrimary;
		TEXT_GRAY = T.textSecondary;
	}

	// NOTAS COLORES
	static var NOTE_COLORS:Array<Int> = [
		0xFFC24B99, 0xFF00FFFF, 0xFF12FA05, 0xFFF9393F,
		0xFF8B3A7C, 0xFF00A8A8, 0xFF0CAF00, 0xFFBD2831
	];

	// GRID
	var GRID_SIZE:Int = 40;
	var totalGridHeight:Float = 0;
	var gridScrollY:Float = 0;
	var maxScroll:Float = 0;
	var _gridWindowOffset:Int = 0; // fila absoluta donde empieza la textura
	var _gridWindowRows:Int = 0; // filas que caben en la textura

	/**
	 * Flag que los sub-componentes del editor (CharacterIconRow, etc.) ponen a `true`
	 * cuando consumen el evento de la rueda del mouse en su propio update().
	 * ChartingState lo resetea al inicio de cada frame y lo chequea antes de hacer
	 * scroll del grid — evita que el scroll "se filtre" al grid de fondo.
	 */
	public var wheelConsumed:Bool = false;

	/** Set to true by CharacterPreviewWindow when the mouse is over it.
	 *  handleMouseInput() skips grid interaction while this is true. */
	public var clickConsumed:Bool = false;

	var gridBG:FlxSprite;
	var gridBlackWhite:FlxSprite;
	var strumLine:FlxSprite;
	var highlight:FlxSprite;

	// DATOS
	var _file:FileReference;
	var _song:SwagSong;
	var curSection:Int = 0;

	public static var lastSection:Int = 0;

	var curSelectedNote:Array<Dynamic>;
	var tempBpm:Float = 0;
	var vocals:FlxSound;

	/**
	 * Mapa dinámico de vocals por personaje para el editor.
	 * Clave = nombre del personaje. Soporta N personajes.
	 */
	var vocalsPerChar:Map<String, FlxSound> = new Map();

	/** Alias de compatibilidad — primer track Player */
	var vocalsBf(get, never):FlxSound;

	inline function get_vocalsBf():FlxSound
	{
		for (k in _chartPlayerKeys)
		{
			var v = vocalsPerChar.get(k);
			if (v != null)
				return v;
		}
		return null;
	}

	/** Alias de compatibilidad — primer track Opponent */
	var vocalsDad(get, never):FlxSound;

	inline function get_vocalsDad():FlxSound
	{
		for (k in _chartOpponentKeys)
		{
			var v = vocalsPerChar.get(k);
			if (v != null)
				return v;
		}
		return null;
	}

	/** true cuando se cargaron vocals por personaje */
	var _chartPerCharVocals:Bool = false;

	var _chartPlayerKeys:Array<String> = [];
	var _chartOpponentKeys:Array<String> = [];

	/**
	 * Sufijo de dificultad actual para guardar el chart con el nombre correcto.
	 * Ej: '' → song.json, '-nightmare' → song-nightmare.json
	 * Equivale al CoolUtil.difficultySuffix() del momento en que se abrió el editor.
	 */
	public var curDiffSuffix:String = '';

	// UI PRINCIPAL
	var UI_box:CoolTabMenu;
	var camGame:FlxCamera;
	var camHUD:FlxCamera;
	var camPopUp:FlxCamera;

	// TABS
	var tab_group_song:coolui.CoolUIGroup;
	var tab_group_section:coolui.CoolUIGroup;
	var tab_group_note:coolui.CoolUIGroup;
	// tab_group_characters fue REEMPLAZADO por CharacterIconRow
	var tab_group_settings:coolui.CoolUIGroup;

	// UI MODERNA
	var titleBar:FlxSprite;
	var toolbar:FlxSprite;
	var statusBar:FlxSprite;
	var infoPanel:FlxSprite;
	var titleText:FlxText;
	var songNameText:FlxText;
	var timeText:FlxText;
	var bpmText:FlxText;
	var sectionText:FlxText;
	var statusText:FlxText;
	var infoLabels:Array<FlxText> = [];
	var infoValues:Array<FlxText> = [];

	// BOTONES
	var _themeBtnRect:{
		x:Float,
		y:Float,
		w:Int,
		h:Int
	} = {
		x: 0,
		y: 0,
		w: 0,
		h: 0
	};
	var playBtn:FlxSprite;
	var pauseBtn:FlxSprite;
	var stopBtn:FlxSprite;
	var testBtn:FlxSprite;

	// TIPS
	var tips:Array<String>;
	var currentTip:Int = 0;
	var tipTimer:Float = 0;

	// NOTAS
	var curRenderedNotes:FlxTypedGroup<Note>;
	var curRenderedSustains:FlxTypedGroup<FlxSprite>;

	/** End caps de los sustains (uno por nota con daSus > 0). */
	var _curSusTails:FlxTypedGroup<FlxSprite>;

	var curRenderedTypeLabels:FlxTypedGroup<FlxText>;

	/** Receptores de strum en la línea de hit del editor. */
	var _editorStrums:FlxTypedGroup<funkin.gameplay.notes.StrumNote>;

	/**
	 * Mapa col -> timestamp (ms) hasta el que la columna debe mostrar confirm.
	 * noteTime + daSus cuando una sustain pasa por el playhead.
	 * Cada frame: si currentTime < valor se mantiene/reinicia confirm; si no, vuelve a idle.
	 */
	var _strumConfirmUntil:Map<Int, Float> = new Map();

	var noteTypeDropdown:CoolDropDown;
	var _noteTypesList:Array<String> = ['normal'];
	var dummyArrow:FlxSprite;

	// ── DRAG-AND-DROP DE NOTAS (single) ─────────────────────────────────────
	var _dragNote:Array<Dynamic> = null;
	var _dragNoteSection:Int = -1;
	/** Pool de 4 sprites Note (uno por dirección) usados como ghost de drag Y como hover preview. */
	var _ghostNotes:Array<Note> = [];
	var _dragGhostCol:Int = -1;
	/** Columna visual que se muestra actualmente en el hover preview (-1 = oculto). */
	var _hoverNoteCol:Int = -1;
	var _dragActive:Bool = false;
	var _dragStartX:Float = 0;
	var _dragStartY:Float = 0;
	var _dragPending:Array<Dynamic> = null;
	var _dragPendingSection:Int = -1;
	/** true cuando el drag-pending empezó sobre una nota que ya estaba seleccionada (click para deseleccionar). */
	var _dragPendingWasSelected:Bool = false;

	// ── SUSTAIN RESIZE (drag hacia abajo sobre nota existente) ────────────────
	/** true mientras el usuario está arrastrando hacia abajo para extender/reducir el sustain. */
	var _susResizeActive:Bool = false;
	var _susResizeNote:Array<Dynamic> = null;
	var _susResizeSection:Int = -1;
	/** Sustain original antes de empezar el resize (para undo). */
	var _susResizeOriginalSus:Float = 0;
	/** Posición Y del mouse al iniciar el resize. */
	var _susResizeStartY:Float = 0;

	static inline var NOTE_DRAG_THRESHOLD:Float = 6.0;

	// ── MULTI-SELECCIÓN ───────────────────────────────────────────────────────

	/** Notas actualmente seleccionadas. */
	var _selectedNotes:Array<{note:Array<Dynamic>, section:Int}> = [];

	/** Rectángulos amarillos detrás de las notas seleccionadas (más visibles que tinte de color). */
	var _selHighlights:FlxTypedGroup<FlxSprite>;

	/** Sprite del rectángulo de selección (box select). */
	var _selBox:FlxSprite;

	var _selBoxBorder:FlxSprite;

	/** true mientras se dibuja el rectángulo de selección. */
	var _selBoxActive:Bool = false;

	/** Coordenadas de inicio del box select (en espacio de step absoluto y col visual). */
	var _selBoxStartStep:Float = 0;

	var _selBoxStartCol:Float = 0;

	// ── MULTI-DRAG ────────────────────────────────────────────────────────────

	/** true cuando se arrastra la selección múltiple. */
	var _multiDragActive:Bool = false;

	var _multiDragPending:Bool = false;

	/** Grupo de ghosts: uno por cada nota seleccionada. */
	var _multiDragGhosts:FlxTypedGroup<FlxSprite>;

	/** Datos originales de cada nota en el multi-drag: posición absoluta y col visual. */
	var _multiDragOriginals:Array<{
		note:Array<Dynamic>,
		section:Int,
		absStep:Float,
		visCol:Int
	}> = [];

	/** Posición del cursor al inicio del multi-drag (para calcular delta). */
	var _multiDragAnchorStep:Float = 0;

	var _multiDragAnchorCol:Int = 0;

	// INDICADORES DE SECCIÓN
	var sectionIndicators:FlxTypedGroup<FlxSprite>;

	/** Sprites de animación flip cuando una nota cambia de columna. Renderiza encima de todo. */
	var _noteFlipGroup:FlxTypedGroup<FlxSprite>;

	// ── CHART OVERVIEW PREVIEW (like V-Slice) ────────────────────────────────

	/** Background del panel de preview. */
	var _prvBg:FlxSprite;

	/** Sprite que contiene todos los píxeles de notas del chart completo. */
	var _prvSprite:FlxSprite;

	/** Overlay semitransparente que indica el área visible del grid. */
	var _prvViewport:FlxSprite;

	/** Línea que indica la posición del playhead. */
	var _prvPlayhead:FlxSprite;

	/** Marcas de sección (líneas horizontales). */
	var _prvSections:FlxSprite;

	/** true cuando hay que redibujar los píxeles de notas. */
	var _prvDirty:Bool = true;

	/** Longitud total del song en ms (cacheado). */
	var _prvSongMs:Float = 0;

	/** true mientras se arrastra el playhead del preview. */
	var _prvDragging:Bool = false;

	// ── Constantes del preview ────────────────────────────────────────────────
	static inline var PRV_X:Int = 5; // posición X (izquierda de la pantalla)
	static inline var PRV_NOTE_W:Int = 4; // ancho de cada columna de nota en px
	static inline var PRV_NOTE_H:Int = 2; // alto de cada nota en px
	// Ancho total: 4 cols * 2 grupos * PRV_NOTE_W + 2px separador + 4px events = 36px aprox
	static inline var PRV_C_BG:Int = 0xFF181820;
	static inline var PRV_C_BORDER:Int = 0xFF00CCFF;
	static inline var PRV_C_SECT:Int = 0xFF334455;
	static inline var PRV_C_VP:Int = 0x3300CCFF;
	static inline var PRV_C_PH:Int = 0xFFFF2244;

	// DROPDOWNS (characters dropdowns moved to CharacterIconRow extension)
	// bfDropDown, dadDropDown, gfDropDown, stageDropDown -> removed
	// STEPPERS
	var stepperLength:CoolNumericStepper;
	var stepperBPM:CoolNumericStepper;
	var stepperSpeed:CoolNumericStepper;
	var stepperSusLength:CoolNumericStepper;

	// CHECKBOXES
	var check_mustHitSection:CoolCheckBox;
	var check_changeBPM:CoolCheckBox;
	var check_altAnim:CoolCheckBox;

	// ===== NUEVAS EXTENSIONES =====
	public var charIconRow:CharacterIconRow;

	var eventsSidebar:EventsSidebar;
	var previewPanel:PreviewPanel;
	var metaPopup:MetaPopup;
	var toolsPanel:ToolsPanel;

	// Botón META en toolbar (zona clickeable)
	var metaBtn:FlxSprite;
	var metaBtnText:FlxText;

	// BPM y Section clickeables - indicadores en toolbar
	var bpmClickable:Bool = false; // ¿Está en modo edición de BPM?
	var bpmInputActive:CoolInputText;
	var sectionInputActive:CoolInputText;

	var openSectionNav:Bool = false;

	/** Sprites/texts del section navigator — guardados para poder cerrarlos desde fuera. */
	var _sectionNavElements:Array<flixel.FlxBasic> = [];

	// HERRAMIENTAS
	var clipboard:Array<Dynamic> = [];

	public var currentSnap:Int = 16;
	public var hitsoundsEnabled:Bool = false;
	public var metronomeEnabled:Bool = false;

	var lastMetronomeBeat:Int = -1;
	var autosaveTimer:Float = 0;

	// ── Unsaved-changes tracking ──────────────────────────────────────────────
	var _hasUnsaved:Bool = false;
	var _unsavedDlg:funkin.debug.EditorDialogs.UnsavedChangesDialog = null;
	var _unsavedDot:FlxSprite = null;
	var _windowCloseFn:Void->Void = null;

	// HITSOUND POR NOTA (durante reproducción)
	var _hitsoundFiredNotes:Map<String, Bool> = new Map();
	var _lastHitsoundTime:Float = -999;

	// WAVEFORM
	public var waveformEnabled:Bool = false;

	var waveformSprite:FlxSprite;
	var _waveformData:Array<Float> = [];
	var _waveformBuilt:Bool = false;

	// Botón de waveform en la toolbar
	var waveformBtn:FlxSprite;
	var waveformBtnText:FlxText;

	// CACHE DE TIEMPOS DE SECCIÓN (evita O(n²) en updateNotePositions cada frame)
	var _sectionStartTimeCache:Array<Float> = [];
	var _sectionTimeCacheDirty:Bool = true;

	// DIRTY FLAG para updateNotePositions (solo recalcular cuando el grid se movió o se editó)
	var _notePositionsDirty:Bool = true;
	var _lastGridY:Float = -99999;

	// OBJECT POOL para notas y sustains del grid (evita GC spikes al editar)
	var _notePool:Array<Note> = [];
	var _susPool:Array<FlxSprite> = [];
	/** Pool de FlxSprites para los highlights de selección (evita makeGraphic cada frame). */
	var _hlPool:Array<FlxSprite> = [];

	// BPM DETECTION
	var _bpmDetecting:Bool = false;

	// UNDO/REDO System
	var undoStack:Array<ChartAction> = [];
	var redoStack:Array<ChartAction> = [];
	var MAX_UNDO_STEPS:Int = 50;

	// ANIMACIÓN DE NOTA SELECCIONADA
	var selectedNotePulse:Float = 0;
	var selectedNotePulseSpeed:Float = 3.0; // Velocidad de pulsación

	override function create()
	{
		funkin.debug.themes.EditorTheme.load();
		_applyTheme();
		funkin.system.CursorManager.show();

		#if desktop
		DiscordClient.changePresence("Chart Editor", null, null, true);
		#end

		curSection = lastSection;

		// Inicializar CharacterList
		CharacterList.init();

		// Cargar canción
		if (PlayState.SONG != null)
			_song = PlayState.SONG;
		else
		{
			_song = {
				song: 'Test',
				notes: [],
				bpm: 120,
				needsVoices: true,
				stage: 'stage_week1',
				player1: 'bf',
				player2: 'dad',
				gfVersion: 'gf',
				speed: 2,
				validScore: false
			};
		}

		// Capturar dificultad actual para guardar el chart con el nombre correcto
		curDiffSuffix = funkin.data.CoolUtil.difficultySuffix();

		// BUGFIX: PlayState previously cleared all sectionNotes after generateNotes()
		// as a GC optimization. Detect this case and reload from disk so the editor
		// doesn't open with an empty grid despite the song having notes.
		if (PlayState.SONG != null && _song.song != null)
		{
			var _hasAnyNote = false;
			if (_song.notes != null)
				for (_sec in _song.notes)
					if (_sec.sectionNotes != null && _sec.sectionNotes.length > 0)
					{ _hasAnyNote = true; break; }

			if (!_hasAnyNote)
			{
				final _reloadInput = (_song.song.toLowerCase()) + curDiffSuffix;
				try
				{
					final _reloaded = funkin.data.Song.loadFromJson(_reloadInput, _song.song.toLowerCase());
					if (_reloaded != null)
					{
						trace('[ChartingState] sectionNotes were empty — reloaded chart from disk');
						_song = _reloaded;
						PlayState.SONG = _song;
					}
				}
				catch (e:Dynamic)
				{
					trace('[ChartingState] Could not reload song from disk: ' + e);
				}
			}
		}

		// Normalizar sectionBeats → lengthInSteps (charts .level cargados desde disco
		// pueden llegar con sectionBeats en vez de lengthInSteps; sin esto el grid
		// calcula totalGridHeight = 0 y el editor queda bloqueado).
		if (_song.notes != null)
		{
			for (rawSec in _song.notes)
			{
				var sec:Dynamic = rawSec;
				if (sec.lengthInSteps == null || sec.lengthInSteps <= 0)
				{
					var beats:Float = (sec.sectionBeats != null) ? cast sec.sectionBeats : 4.0;
					sec.lengthInSteps = Std.int(beats * 4);
				}
			}
		}

		// Garantizar que strumsGroups y characters existan (incluye grupo de GF)
		funkin.data.Song.ensureMigrated(_song);

		// CRÍTICO: Crear sección por defecto si el array está vacío
		if (_song.notes == null || _song.notes.length == 0)
		{
			trace('[ChartingState] Notes array is empty, creating default section');
			_song.notes = [
				{
					lengthInSteps: 16,
					bpm: _song.bpm,
					changeBPM: false,
					mustHitSection: true,
					sectionNotes: [],
					typeOfSection: 0,
					altAnim: false
				}
			];
		}

		// Asegurar que curSection sea válido
		if (curSection < 0)
			curSection = 0;
		if (curSection >= _song.notes.length)
			curSection = _song.notes.length - 1;

		// Setup cameras
		camGame = new FlxCamera();
		camHUD = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		camPopUp = new FlxCamera();
		camPopUp.bgColor.alpha = 0;
		FlxG.cameras.reset(camGame);
		FlxG.cameras.add(camHUD);
		FlxG.cameras.add(camPopUp);
		@:privateAccess FlxCamera._defaultCameras = [camGame];

		// Setup UI
		setupBackground();
		setupTips();
		setupTitleBar();
		setupToolbar();
		setupGrid();
		setupNotes();
		setupUITabs();
		setupInfoPanel();
		setupStatusBar();
		setupNewExtensions(); // ← NUEVAS EXTENSIONES

		// Cargar audio
		loadSong(_song.song);

		// Estado inicial
		changeSection();
		updateGrid(); // ✨ Cargar todas las notas al inicio

		// ── Window-close guard: mostrar diálogo si hay cambios sin guardar ──
		#if sys
		_windowCloseFn = function()
		{
			if (_hasUnsaved)
			{
				// No podemos bloquear el cierre sincrónicamente en desktop;
				// guardamos automáticamente para no perder el trabajo.
				try { LevelFile.saveDiff(_song.song,
					(curDiffSuffix != null && curDiffSuffix != '') ? curDiffSuffix : '',
					_song); }
				catch (_) {}
			}
		};
		lime.app.Application.current.window.onClose.add(_windowCloseFn);
		#end

		super.create();
	}

	function setupBackground():Void
	{
		var bg = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, BG_DARK);
		bg.scrollFactor.set();
		bg.cameras = [camGame];
		add(bg);
	}

	function setupTips():Void
	{
		tips = [
			"💡 Left-click grid to place a note",
			"💡 Right-click to erase a note",
			"💡 1-8 keys: place note at current playhead position",
			"💡 F5 to test from current section",
			"💡 Ctrl+Z / Ctrl+Y — undo / redo",
			"💡 Ctrl+C/V/X to copy/paste/cut section",
			"💡 N to mirror section",
			"💡 Q/E = sustain resize | Shift+Q/E = snap",
			"💡 T for hitsounds  |  M for metronome",
			"💡 Settings tab → change difficulty to reload chart + audio",
			"💡 Click 🌊 Wave button to toggle waveform",
			"💡 Go to Settings → Auto-Detect BPM",
			"💡 Ctrl+Scroll over icons to scroll characters",
			"💡 PageUp/Down to navigate sections",
			"💡 Mouse wheel to scroll grid",
			"💡 Shift+Wheel for pixel scroll",
			"💡 Space to play/pause  |  Enter to restart section",
			"💡 W/S or Up/Down to seek audio",
			"💡 ESC to go back to PlayState"
		];
	}

	function setupTitleBar():Void
	{
		titleBar = new FlxSprite(0, 0);
		titleBar.makeGraphic(FlxG.width, 35, 0xFF121212);
		titleBar.scrollFactor.set();
		titleBar.cameras = [camHUD];
		add(titleBar);

		titleText = new FlxText(10, 8, 0, "⚡ CHART EDITOR", 16);
		titleText.setFormat(Paths.font("vcr.ttf"), 16, ACCENT_CYAN, LEFT, OUTLINE, FlxColor.BLACK);
		titleText.scrollFactor.set();
		titleText.cameras = [camHUD];
		add(titleText);

		songNameText = new FlxText(180, 8, 0, '• ${_song.song}' + (curDiffSuffix != '' ? ' [${curDiffSuffix.substr(1).toUpperCase()}]' : ' [NORMAL]'), 16);
		songNameText.setFormat(Paths.font("vcr.ttf"), 16, TEXT_GRAY, LEFT);
		songNameText.scrollFactor.set();
		songNameText.cameras = [camHUD];
		add(songNameText);
	}

	function setupToolbar():Void
	{
		toolbar = new FlxSprite(0, 35);
		toolbar.makeGraphic(FlxG.width, 45, BG_PANEL);
		toolbar.scrollFactor.set();
		toolbar.cameras = [camHUD];
		add(toolbar);

		// Botones de playback — primero añadir el FONDO, luego el TEXTO encima
		playBtn = createToolButton(10, 40);
		pauseBtn = createToolButton(55, 40);
		stopBtn = createToolButton(100, 40);
		testBtn = createToolButton(145, 40);

		add(playBtn);
		add(pauseBtn);
		add(stopBtn);
		add(testBtn);

		// Labels DESPUES de los sprites para que queden encima (z-order correcto)
		// VCR.ttf soporta ASCII; evitamos emojis/unicode que pueden no renderizar
		addToolButtonLabel(playBtn, ">");
		addToolButtonLabel(pauseBtn, "||");
		addToolButtonLabel(stopBtn, "[]");
		addToolButtonLabel(testBtn, "F5");

		// Time (solo display)
		timeText = new FlxText(200, 45, 0, "00:00.000", 12);
		timeText.setFormat(Paths.font("vcr.ttf"), 12, TEXT_GRAY, LEFT);
		timeText.scrollFactor.set();
		timeText.cameras = [camHUD];
		add(timeText);

		// BPM - CLICKEABLE para editar
		var bpmBg = new FlxSprite(320, 10).makeGraphic(70, 18, 0xFF2A2A00);
		bpmBg.scrollFactor.set();
		bpmBg.cameras = [camHUD];
		add(bpmBg);

		bpmText = new FlxText(322, 11, 66, "120 BPM", 11);
		bpmText.setFormat(Paths.font("vcr.ttf"), 11, ACCENT_WARNING, CENTER);
		bpmText.scrollFactor.set();
		bpmText.cameras = [camHUD];
		add(bpmText);

		// Section - CLICKEABLE para navegar
		var secBg = new FlxSprite(400, 10).makeGraphic(90, 18, 0xFF002A1A);
		secBg.scrollFactor.set();
		secBg.cameras = [camHUD];
		add(secBg);

		sectionText = new FlxText(402, 11, 86, "Section 1/1", 11);
		sectionText.setFormat(Paths.font("vcr.ttf"), 11, ACCENT_GREEN, CENTER);
		sectionText.scrollFactor.set();
		sectionText.cameras = [camHUD];
		add(sectionText);

		// Botón META
		metaBtn = new FlxSprite(502, 10).makeGraphic(55, 22, 0xFF1A1A3A);
		metaBtn.scrollFactor.set();
		metaBtn.cameras = [camHUD];
		add(metaBtn);

		metaBtnText = new FlxText(502, 10, 55, "Meta", 12);
		metaBtnText.setFormat(Paths.font("vcr.ttf"), 12, ACCENT_CYAN, CENTER);
		metaBtnText.scrollFactor.set();
		metaBtnText.cameras = [camHUD];
		add(metaBtnText);

		// Borde del botón Meta
		var metaBorder = new FlxSprite(502, 29).makeGraphic(55, 2, ACCENT_CYAN);
		metaBorder.alpha = 0.6;
		metaBorder.scrollFactor.set();
		metaBorder.cameras = [camHUD];
		add(metaBorder);

		// 🌊 Botón de Waveform (ya no usa la tecla W)
		waveformBtn = new FlxSprite(568, 10).makeGraphic(68, 22, 0xFF001A2A);
		waveformBtn.scrollFactor.set();
		waveformBtn.cameras = [camHUD];
		add(waveformBtn);

		waveformBtnText = new FlxText(568, 10, 68, "Wave", 11);
		waveformBtnText.setFormat(Paths.font("vcr.ttf"), 11, TEXT_GRAY, CENTER);
		waveformBtnText.scrollFactor.set();
		waveformBtnText.cameras = [camHUD];
		add(waveformBtnText);

		var waveBorder = new FlxSprite(568, 29).makeGraphic(68, 2, TEXT_GRAY);
		waveBorder.alpha = 0.4;
		waveBorder.scrollFactor.set();
		waveBorder.cameras = [camHUD];
		add(waveBorder);

		// Tools button — abre el panel de herramientas (sin tocar el grid)
		var toolsBtnBg = new FlxSprite(648, 10).makeGraphic(58, 22, 0xFF1A1A00);
		toolsBtnBg.scrollFactor.set();
		toolsBtnBg.cameras = [camHUD];
		add(toolsBtnBg);

		var toolsBtnTxt = new FlxText(648, 10, 58, "Tools", 12);
		toolsBtnTxt.setFormat(Paths.font("vcr.ttf"), 12, ACCENT_WARNING, CENTER);
		toolsBtnTxt.scrollFactor.set();
		toolsBtnTxt.cameras = [camHUD];
		add(toolsBtnTxt);

		var toolsBorder = new FlxSprite(648, 29).makeGraphic(58, 2, ACCENT_WARNING);
		toolsBorder.alpha = 0.6;
		toolsBorder.scrollFactor.set();
		toolsBorder.cameras = [camHUD];
		add(toolsBorder);

		// ✨ Botón de tema (abre ThemePickerSubState)
		var themeBtnBg = new FlxSprite(FlxG.width - 38, 40).makeGraphic(32, 32, BG_PANEL);
		themeBtnBg.scrollFactor.set();
		themeBtnBg.cameras = [camHUD];
		add(themeBtnBg);
		_themeBtnRect = {
			x: FlxG.width - 38.0,
			y: 40.0,
			w: 32,
			h: 32
		};
		var themeBtnTxt = new FlxText(FlxG.width - 38, 46, 32, "\u2728", 13);
		themeBtnTxt.setFormat(Paths.font("vcr.ttf"), 13, ACCENT_CYAN, CENTER);
		themeBtnTxt.scrollFactor.set();
		themeBtnTxt.cameras = [camHUD];
		add(themeBtnTxt);
	}

	/**
	 * Creates a toolbar button sprite WITHOUT adding a text overlay.
	 * Text labels are added separately in setupToolbar() AFTER all buttons
	 * so the text renders on top of the button background (correct z-order).
	 */
	function createToolButton(x:Float, y:Float):FlxSprite
	{
		var btn = new FlxSprite(x, y);
		btn.makeGraphic(35, 35, 0xFF3A3A3A);
		btn.scrollFactor.set();
		btn.cameras = [camHUD];
		return btn;
	}

	/**
	 * Adds a text label centered over a button sprite.
	 * Call this AFTER adding the button sprite to the display list.
	 */
	function addToolButtonLabel(btn:FlxSprite, label:String):FlxText
	{
		// Vertical center: nudge slightly to optically center the glyph
		var lbl = new FlxText(btn.x, btn.y + 9, Std.int(btn.width), label, 14);
		lbl.setFormat(Paths.font("vcr.ttf"), 14, TEXT_WHITE, CENTER);
		lbl.scrollFactor.set();
		lbl.cameras = [camHUD];
		add(lbl);
		return lbl;
	}

	function getGridColumns():Int
	{
		// 4 columnas por cada grupo de strums. Mínimo 8 (2 grupos default)
		if (_song.strumsGroups != null && _song.strumsGroups.length > 0)
			return _song.strumsGroups.length * 4;
		return 8;
	}

	function setupGrid():Void
	{
		// Calcular altura total del grid basado en todas las secciones
		totalGridHeight = 0;

		// VALIDACIÓN CRÍTICA: Asegurar que hay secciones
		if (_song.notes == null || _song.notes.length == 0)
		{
			trace('[GRID ERROR] No hay secciones en _song.notes!');
			_song.notes = [
				{
					lengthInSteps: 16,
					bpm: _song.bpm,
					changeBPM: false,
					mustHitSection: true,
					sectionNotes: [],
					typeOfSection: 0,
					altAnim: false
				}
			];
		}

		for (sec in _song.notes)
		{
			// Validar que lengthInSteps sea válido (mayor que 0)
			var steps = (sec.lengthInSteps > 0) ? sec.lengthInSteps : 16;
			totalGridHeight += steps * GRID_SIZE;
		}

		// VALIDACIÓN: Asegurar altura mínima
		if (totalGridHeight <= 0)
		{
			trace('[GRID ERROR] totalGridHeight es 0 o negativo! Forzando altura mínima.');
			totalGridHeight = 16 * GRID_SIZE; // Al menos 16 steps
		}

		// La altura REAL del grid (para scroll y navegación)
		var realGridHeight = totalGridHeight;

		// Limitar la altura del GRÁFICO al máximo que soporta la GPU (~16k px)
		var MAX_GRID_HEIGHT = 16000;
		if (totalGridHeight > MAX_GRID_HEIGHT)
		{
			trace('[GRID WARNING] totalGridHeight muy grande (${totalGridHeight}), limitando gráfico a $MAX_GRID_HEIGHT');
			totalGridHeight = MAX_GRID_HEIGHT;
		}

		trace('[GRID] Song: ${_song.song}, realGridHeight: $realGridHeight, graphicHeight: $totalGridHeight, secciones: ${_song.notes.length}');

		// maxScroll basado en la altura REAL, no la del gráfico
		maxScroll = realGridHeight - (FlxG.height - 100);
		if (maxScroll < 0)
			maxScroll = 0;

		// === COLUMNAS DINÁMICAS basadas en strumsGroups ===
		var numCols = getGridColumns();
		var gridWidth = GRID_SIZE * numCols;

		// Centrar el grid según su ancho real
		var centerX = (FlxG.width / 2) - (gridWidth / 2);
		// Si el grid es muy ancho, colocarlo más a la izquierda
		if (gridWidth > FlxG.width * 0.6)
			centerX = (FlxG.width - gridWidth) / 2;

		// Ventana deslizante: solo renderizar lo que cabe en pantalla
		_gridWindowRows = Std.int((FlxG.height + 200) / GRID_SIZE) + 4;
		_gridWindowOffset = 0;
		var windowH = _gridWindowRows * GRID_SIZE;

		gridBG = new FlxSprite();
		gridBG.makeGraphic(gridWidth, windowH, 0xFF000000, true);
		_redrawGridBG(gridWidth, numCols);

		gridBG.x = centerX;
		gridBG.y = 100;
		gridBG.scrollFactor.set();
		gridBG.cameras = [camGame];
		add(gridBG);

		trace('[GRID] Grid creado: ${gridWidth}x${Std.int(totalGridHeight)}, $numCols columnas (${Std.int(numCols / 4)} grupos)');

		// Overlay divisores de sección
		gridBlackWhite = new FlxSprite(gridBG.x, gridBG.y);
		gridBlackWhite.makeGraphic(gridWidth, _gridWindowRows * GRID_SIZE, 0x00000000, true);
		_redrawGridBW(gridWidth);

		gridBlackWhite.scrollFactor.set();
		gridBlackWhite.cameras = [camGame];
		add(gridBlackWhite);

		// Strum line
		// Inicializar/reconstruir el panel de preview del chart
		initChartPreview();

		strumLine = new FlxSprite(gridBG.x, gridBG.y);
		strumLine.makeGraphic(Std.int(gridBG.width), 4, ACCENT_CYAN);
		strumLine.scrollFactor.set();
		strumLine.cameras = [camGame];
		add(strumLine);

		// ── Receptores de strum (StrumNote) en la línea de hit ─────────────────
		// Uno por columna, posicionados sobre la strumLine (y=100 - GRID_SIZE).
		// Se animan al pasar una nota durante la reproducción.
		// FIX posición: strums en camHUD a y=100 (sobre la strumLine).
		// Antes estaban en camGame a y=60 → el HUD (camHUD) los tapaba completamente.
		if (_editorStrums != null)
		{
			for (s in _editorStrums.members)
				if (s != null)
					remove(s, true);
			_editorStrums.clear();
		}
		else
		{
			_editorStrums = new FlxTypedGroup<funkin.gameplay.notes.StrumNote>();
		}
		for (col in 0...numCols)
		{
			var strum = new funkin.gameplay.notes.StrumNote(gridBG.x + col * GRID_SIZE -95, 5, // FIX: en la strumLine, no 40px encima donde el HUD lo tapaba
				col % 4);
			strum.setGraphicSize(GRID_SIZE + 1, GRID_SIZE + 1);
			strum.updateHitbox();
			strum.scrollFactor.set();
			strum.cameras = [camHUD]; // FIX
			_editorStrums.add(strum);
			add(strum);
		}

		// Highlight
		highlight = new FlxSprite(gridBG.x, gridBG.y);
		highlight.makeGraphic(GRID_SIZE, GRID_SIZE, 0x40FFFFFF);
		highlight.scrollFactor.set();
		highlight.cameras = [camGame];
		highlight.visible = false;
		add(highlight);

		// Etiquetas de grupos de strums encima de cada grupo de 4 columnas
		drawStrumsGroupLabels();

		// Sección indicators
		sectionIndicators = new FlxTypedGroup<FlxSprite>();
		add(sectionIndicators);
		updateSectionIndicators();

		// Dummy arrow
		dummyArrow = new FlxSprite().makeGraphic(GRID_SIZE, GRID_SIZE);
		add(dummyArrow);

		// Pool de 4 Notes (una por dirección) para ghost de drag y hover preview.
		// Se nullea el shader DESPUÉS de construir para que .color funcione siempre
		// (si noteRGB está activo el constructor aplica un shader que anula el tint).
		_ghostNotes = [];
		for (d in 0...4)
		{
			var gn = new Note(0, d);
			gn.setGraphicSize(GRID_SIZE, GRID_SIZE);
			gn.updateHitbox();
			// Eliminar shader RGB: los ghost notes usan tint directo (NOTE_COLORS)
			gn.shader = null;
			gn.color  = 0xFFFFFFFF;
			gn.scrollFactor.set();
			gn.cameras = [camGame];
			gn.visible = false;
			add(gn);
			_ghostNotes.push(gn);
		}

		// Box de selección (fill + border)
		_selBox = new FlxSprite().makeGraphic(1, 1, 0xFF00CCFF);
		_selBox.scrollFactor.set();
		_selBox.cameras = [camGame];
		_selBox.alpha = 0.18;
		_selBox.visible = false;
		add(_selBox);
		_selBoxBorder = new FlxSprite().makeGraphic(1, 1, 0xFF00CCFF);
		_selBoxBorder.scrollFactor.set();
		_selBoxBorder.cameras = [camGame];
		_selBoxBorder.alpha = 0.70;
		_selBoxBorder.visible = false;
		add(_selBoxBorder);

		// Grupo de ghosts para multi-drag
		_multiDragGhosts = new FlxTypedGroup<FlxSprite>();
		_multiDragGhosts.cameras = [camGame];
		add(_multiDragGhosts);
	}

	// Etiquetas de nombre del grupo encima de cada bloque de 4 columnas
	var strumsGroupLabels:FlxTypedGroup<FlxText>;

	function drawStrumsGroupLabels():Void
	{
		if (strumsGroupLabels != null)
		{
			for (lbl in strumsGroupLabels.members)
				remove(lbl, true);
			strumsGroupLabels.clear();
		}
		else
			strumsGroupLabels = new FlxTypedGroup<FlxText>();

		var orderedGroups = getOrderedStrumsGroups();
		var numGroups = orderedGroups.length;
		var groupColors:Array<Int> = [0xFFFF8888, 0xFF88FFFF, 0xFF88FF88, 0xFFFFFF88, 0xFFFF88FF, 0xFF88AAFF];

		for (g in 0...numGroups)
		{
			var gd = orderedGroups[g];
			var groupX = gridBG.x + (g * 4 * GRID_SIZE);
			var groupW = 4 * GRID_SIZE;
			var isInvis = !gd.visible;

			var labelBg = new FlxSprite(groupX, gridBG.y - 18).makeGraphic(groupW, 18, isInvis ? 0xAA2A1500 : 0xAA000000);
			labelBg.scrollFactor.set();
			labelBg.cameras = [camHUD];
			add(labelBg);

			var cpuTag = gd.cpu ? " [CPU]" : " [P]";
			var visTag = isInvis ? " 👁" : "";
			var groupName = gd.id + cpuTag + visTag;

			var labelColor = isInvis ? 0xFFFFAA00 : groupColors[g % groupColors.length];

			var lbl = new FlxText(groupX + 2, gridBG.y - 16, groupW - 4, groupName, 9);
			lbl.setFormat(Paths.font("vcr.ttf"), 9, labelColor, CENTER);
			lbl.scrollFactor.set();
			lbl.cameras = [camHUD];
			strumsGroupLabels.add(lbl);
			add(lbl);
		}
	}

	/**
	 * Reconstruye todo el grid desde cero.
	 * Llamar cuando se agregan/eliminan grupos de strums.
	 */
	public function rebuildGrid():Void
	{
		// Limpiar sprites del grid anteriores
		if (gridBG != null)
		{
			remove(gridBG, true);
			gridBG.destroy();
		}
		if (gridBlackWhite != null)
		{
			remove(gridBlackWhite, true);
			gridBlackWhite.destroy();
		}
		if (strumLine != null)
		{
			remove(strumLine, true);
			strumLine.destroy();
		}
		if (highlight != null)
		{
			remove(highlight, true);
			highlight.destroy();
		}
		if (sectionIndicators != null)
			sectionIndicators.clear();

		// ← NUEVO: sacar los grupos de notas de la lista para re-insertarlos encima del grid
		if (curRenderedSustains != null)
			remove(curRenderedSustains);
		if (_curSusTails != null)
			remove(_curSusTails);
		if (_selHighlights != null)
			remove(_selHighlights);
		if (curRenderedNotes != null)
			remove(curRenderedNotes);

		// Recrear grid (añade los sprites del fondo)
		setupGrid();

		// ← NUEVO: volver a añadir notas y sustains ENCIMA del grid
		if (curRenderedSustains != null)
			add(curRenderedSustains);
		if (_curSusTails != null)
			add(_curSusTails);
		if (_selHighlights != null)
			add(_selHighlights);
		if (curRenderedNotes != null)
			add(curRenderedNotes);

		// Actualizar notas y extensiones
		updateGrid();

		if (eventsSidebar != null)
			eventsSidebar.setScrollY(gridScrollY, gridBG.y);

		if (charIconRow != null)
			charIconRow.refreshIcons();

		if (previewPanel != null)
			previewPanel.refreshAll();

		showMessage('🔧 Grid updated: ${getGridColumns() / 4} groups of strums', ACCENT_CYAN);
		trace('[ChartingState] Grid rebuilt with ${getGridColumns()} columns');
	}

	function setupNotes():Void
	{
		curRenderedNotes = new FlxTypedGroup<Note>();
		curRenderedSustains = new FlxTypedGroup<FlxSprite>();
		_curSusTails = new FlxTypedGroup<FlxSprite>();
		_selHighlights = new FlxTypedGroup<FlxSprite>();

		add(curRenderedSustains);
		add(_curSusTails);
		add(_selHighlights); // encima de sustains, debajo de note heads
		add(curRenderedNotes);
	}

	function setupUITabs():Void
	{
		UI_box = new CoolTabMenu(null, [
			{name: "Song", label: 'Song'},
			{name: "Section", label: 'Section'},
			{name: "Note", label: 'Note'},
			{name: "Settings", label: 'Settings'}
		], true);

		UI_box.resize(300, 400);
		UI_box.x = FlxG.width - 320;
		UI_box.y = 20;
		UI_box.scrollFactor.set();
		UI_box.cameras = [camHUD];

		addSongUI();
		addSectionUI();
		// Build noteTypes list for dropdown
		_noteTypesList = ['normal'];
		for (t in NoteTypeManager.getTypes())
			_noteTypesList.push(t);

		addNoteUI();
		curRenderedTypeLabels = new FlxTypedGroup<FlxText>();
		add(curRenderedTypeLabels);

		_noteFlipGroup = new FlxTypedGroup<FlxSprite>();
		add(_noteFlipGroup); // siempre encima de las notas renderizadas
		addSettingsUI();
		// ↑ El tab de Characters fue reemplazado por la fila de iconos encima del grid

		add(UI_box);
	}

	function addSongUI():Void
	{
		tab_group_song = new coolui.CoolUIGroup();
		tab_group_song.name = 'Song';

		// Song name
		var songLabel = new FlxText(10, 10, 0, 'Song:', 10);
		tab_group_song.add(songLabel);

		var songText = new FlxText(10, 25, 0, _song.song, 12);
		songText.color = ACCENT_CYAN;
		tab_group_song.add(songText);

		// BPM
		var bpmLabel = new FlxText(10, 50, 0, 'BPM:', 10);
		tab_group_song.add(bpmLabel);

		stepperBPM = new CoolNumericStepper(10, 65, 1, _song.bpm, 1, 999, 0);
		stepperBPM.value = _song.bpm;
		tab_group_song.add(stepperBPM);

		// Speed
		var speedLabel = new FlxText(10, 100, 0, 'Speed:', 10);
		tab_group_song.add(speedLabel);

		stepperSpeed = new CoolNumericStepper(10, 115, 0.1, _song.speed, 0.1, 10, 1);
		stepperSpeed.value = _song.speed;
		tab_group_song.add(stepperSpeed);

		// Player 1 & 2 info
		var p1Label = new FlxText(10, 150, 0, 'Player 1: ${_song.player1}', 10);
		tab_group_song.add(p1Label);

		var p2Label = new FlxText(10, 165, 0, 'Player 2: ${_song.player2}', 10);
		tab_group_song.add(p2Label);

		// Buttons
		var reloadBtn = new FlxButton(10, 200, "Reload Audio", function()
		{
			loadSong(_song.song);
		});
		tab_group_song.add(reloadBtn);

		var clearAllBtn = new FlxButton(10, 230, "Clear All Notes", function()
		{
			for (sec in _song.notes)
				sec.sectionNotes = [];
			updateGrid();
			_markUnsaved();
		});
		tab_group_song.add(clearAllBtn);

		UI_box.addGroup(tab_group_song);
	}

	function addSectionUI():Void
	{
		tab_group_section = new coolui.CoolUIGroup();
		tab_group_section.name = 'Section';

		// Section info
		var secLabel = new FlxText(10, 10, 0, 'Section: ${curSection + 1}/${_song.notes.length}', 12);
		tab_group_section.add(secLabel);

		// Checkboxes
		check_mustHitSection = new CoolCheckBox(10, 40, null, null, "Must Hit Section", 100);
		check_mustHitSection.checked = false;
		tab_group_section.add(check_mustHitSection);

		check_changeBPM = new CoolCheckBox(10, 70, null, null, "Change BPM", 100);
		check_changeBPM.checked = false;
		tab_group_section.add(check_changeBPM);

		check_altAnim = new CoolCheckBox(10, 100, null, null, "Alt Animation", 100);
		check_altAnim.checked = false;
		tab_group_section.add(check_altAnim);

		// Section length
		var lengthLabel = new FlxText(10, 135, 0, 'Section Length (steps):', 10);
		tab_group_section.add(lengthLabel);

		stepperLength = new CoolNumericStepper(10, 150, 4, 0, 0, 999, 0);
		stepperLength.value = 16;
		tab_group_section.add(stepperLength);

		// Buttons
		var copyBtn = new FlxButton(10, 190, "Copy Section", copySection);
		tab_group_section.add(copyBtn);

		var clearBtn = new FlxButton(10, 220, "Clear Section", function()
		{
			_song.notes[curSection].sectionNotes = [];
			updateGrid();
			_markUnsaved();
		});
		tab_group_section.add(clearBtn);

		UI_box.addGroup(tab_group_section);
	}

	function addNoteUI():Void
	{
		tab_group_note = new coolui.CoolUIGroup();
		tab_group_note.name = 'Note';

		// Sustain length
		var susLabel = new FlxText(10, 10, 0, 'Sustain Length:', 10);
		tab_group_note.add(susLabel);

		stepperSusLength = new CoolNumericStepper(10, 25, Conductor.stepCrochet / 2, 0, 0, Conductor.stepCrochet * 16);
		stepperSusLength.value = 0;
		tab_group_note.add(stepperSusLength);

		// Note Type dropdown
		var typeLabel = new FlxText(10, 55, 0, 'Note Type:', 10);
		tab_group_note.add(typeLabel);

		var ddItems:Array<String> = [];
		for (i in 0..._noteTypesList.length)
			ddItems.push('$i: ${_noteTypesList[i]}');

		noteTypeDropdown = new CoolDropDown(10, 68, CoolDropDown.makeStrIdLabelArray(ddItems, true), function(chosen:String)
		{
			if (curSelectedNote == null)
				return;
			var colonIdx = chosen.indexOf(':');
			var idx = colonIdx > 0 ? Std.parseInt(chosen.substr(0, colonIdx).trim()) : 0;
			if (idx == null || idx < 0 || idx >= _noteTypesList.length)
				idx = 0;
			var typeName:String = _noteTypesList[idx];
			curSelectedNote[3] = (typeName == 'normal' || typeName == '') ? null : typeName;
			updateGrid();
		});
		noteTypeDropdown.selectedLabel = '0: normal';

		tab_group_note.add(noteTypeDropdown);

		UI_box.addGroup(tab_group_note);
	}

	// addCharactersUI() fue REEMPLAZADO por CharacterIconRow
	// Los personajes ahora se gestionan desde la fila de iconos encima del grid

	function addSettingsUI():Void
	{
		tab_group_settings = new coolui.CoolUIGroup();
		tab_group_settings.name = 'Settings';

		// Separador
		var sep = new FlxText(10, 10, 270, '── Audio Analysis ──', 9);
		sep.color = TEXT_GRAY;
		tab_group_settings.add(sep);

		// Botón Auto-Detect BPM
		var detectBpmBtn = new FlxButton(10, 24, "Auto-Detect BPM", function()
		{
			detectBPM();
		});
		tab_group_settings.add(detectBpmBtn);

		var bpmHint = new FlxText(10, 50, 270, "Analyses the loaded audio to\nestimate BPM automatically.", 9);
		bpmHint.color = TEXT_GRAY;
		tab_group_settings.add(bpmHint);

		// Separador
		var sep2 = new FlxText(10, 80, 270, '── Chart Files ──', 9);
		sep2.color = TEXT_GRAY;
		tab_group_settings.add(sep2);

		// ── Selector de dificultad dinámica ─────────────────────────────────
		var diffLabel = new FlxText(10, 93, 270, 'Difficulty suffix (for saving):', 9);
		diffLabel.color = TEXT_GRAY;
		tab_group_settings.add(diffLabel);

		// Construir la lista de dificultades disponibles
		// Incluye 'normal' (sin sufijo) + las de FreeplayState si existen
		var diffOptions:Array<String> = ['normal (no suffix)'];
		var diffSuffixes:Array<String> = [''];
		// difficultyStuff es Array<[nombre, sufijo]>, ej: [['Easy','-easy'],['Normal',''],['Hard','-hard']]
		var fDiffs = funkin.menus.FreeplayState.difficultyStuff;
		if (fDiffs != null && fDiffs.length > 0)
		{
			for (i in 0...fDiffs.length)
			{
				final pair:Array<Dynamic> = cast fDiffs[i];
				final diffName:String = pair != null && pair.length > 0 ? Std.string(pair[0]) : '';
				final suffix:String = pair != null && pair.length > 1 ? Std.string(pair[1]) : '';
				if (suffix == '' || diffName == '')
					continue; // 'normal' ya está
				diffOptions.push(diffName.toLowerCase());
				diffSuffixes.push(suffix);
			}
		}
		// Asegurar que el sufijo actual esté representado
		if (!diffSuffixes.contains(curDiffSuffix))
		{
			if (curDiffSuffix != '' && curDiffSuffix != null)
			{
				diffOptions.push(curDiffSuffix.substr(1)); // quitar '-'
				diffSuffixes.push(curDiffSuffix);
			}
		}
		final diffDropdown = new CoolDropDown(10, 107, CoolDropDown.makeStrIdLabelArray(diffOptions, true), function(selected:String)
		{
			final idx = Std.parseInt(selected);
			if (idx != null && idx >= 0 && idx < diffSuffixes.length)
			{
				curDiffSuffix = diffSuffixes[idx];

				// ── Recargar chart para la nueva dificultad ──────────────────
				// Intentar cargar el diff correspondiente del .level
				#if sys
				final _reloaded = funkin.data.LevelFile.loadDiff(_song.song.toLowerCase(), curDiffSuffix);
				if (_reloaded != null)
				{
					_song = _reloaded;
					// Garantizar secciones mínimas
					if (_song.notes == null || _song.notes.length == 0)
						_song.notes = [
							{
								lengthInSteps: 16,
								bpm: _song.bpm,
								changeBPM: false,
								mustHitSection: true,
								sectionNotes: [],
								typeOfSection: 0,
								altAnim: false
							}
						];
					Conductor.changeBPM(_song.bpm);
					Conductor.mapBPMChanges(_song);
					curSection = 0;
					rebuildGrid();
					changeSection(0);
				}
				#end

				// Recargar audio (inst + vocals) con la nueva dificultad
				loadSong(_song.song);
				showMessage('🎵 Difficulty: ${diffOptions[idx]} — audio + chart reloaded', ACCENT_CYAN);

				// Actualizar el título de la ventana para reflejar el sufijo actual
				if (songNameText != null)
					songNameText.text = '• ${_song.song}' + (curDiffSuffix != '' ? ' [${curDiffSuffix.substr(1).toUpperCase()}]' : ' [NORMAL]');
			}
		});
		diffDropdown.selectedLabel = diffOptions[0];
		// Preseleccionar la dificultad actual
		if (diffSuffixes.contains(curDiffSuffix))
		{
			final curIdx = diffSuffixes.indexOf(curDiffSuffix);
			if (curIdx >= 0)
				diffDropdown.selectedLabel = diffOptions[curIdx];
		}
		tab_group_settings.add(diffDropdown);

		// Save/Load
		var saveBtn = new FlxButton(10, 140, "Save Chart (.level)", saveChart);
		tab_group_settings.add(saveBtn);

		var loadBtn = new FlxButton(10, 170, "Load Chart", loadChart);
		tab_group_settings.add(loadBtn);

		// Migrate: convierte los .json viejos de esta canción a un único .level
		var migrateBtn = new FlxButton(10, 200, "Migrate to .level", function()
		{
			final ok = funkin.data.LevelFile.migrateFromJson(_song.song);
			showMessage(ok ? 'Migrated to ${_song.song.toLowerCase()}.level' : 'Migration failed (check console)', ok ? ACCENT_SUCCESS : ACCENT_WARNING);
		});
		tab_group_settings.add(migrateBtn);

		UI_box.addGroup(tab_group_settings);
	}

	function setupInfoPanel():Void
	{
		// Background del panel
		infoPanel = new FlxSprite(FlxG.width - 220, FlxG.height - 240);
		infoPanel.makeGraphic(200, 200, BG_PANEL);
		infoPanel.alpha = 0.95;
		infoPanel.scrollFactor.set();
		infoPanel.cameras = [camHUD];
		add(infoPanel);

		// Title del panel
		var panelTitle = new FlxText(infoPanel.x + 10, infoPanel.y + 10, 180, "📊 INFO", 14);
		panelTitle.setFormat(Paths.font("vcr.ttf"), 14, ACCENT_CYAN, LEFT, OUTLINE, FlxColor.BLACK);
		panelTitle.borderSize = 1;
		panelTitle.scrollFactor.set();
		panelTitle.cameras = [camHUD];
		add(panelTitle);

		// Labels y valores
		var labels = ["TIME", "BPM", "SECTION", "STEP", "BEAT", "NOTES", "SNAP"];

		for (i in 0...labels.length)
		{
			// Label
			var label = new FlxText(infoPanel.x + 15, infoPanel.y + 40 + (i * 22), 0, labels[i], 10);
			label.setFormat(Paths.font("vcr.ttf"), 10, TEXT_GRAY, LEFT);
			label.scrollFactor.set();
			label.cameras = [camHUD];
			infoLabels.push(label);
			add(label);

			// Value
			var value = new FlxText(infoPanel.x + 100, infoPanel.y + 40 + (i * 22), 90, "---", 12);
			value.setFormat(Paths.font("vcr.ttf"), 12, TEXT_WHITE, RIGHT);
			value.scrollFactor.set();
			value.cameras = [camHUD];
			infoValues.push(value);
			add(value);
		}
	}

	function setupStatusBar():Void
	{
		statusBar = new FlxSprite(0, FlxG.height - 25);
		statusBar.makeGraphic(FlxG.width, 25, BG_PANEL);
		statusBar.scrollFactor.set();
		statusBar.cameras = [camHUD];
		add(statusBar);

		statusText = new FlxText(10, FlxG.height - 20, FlxG.width - 20, tips[0], 12);
		statusText.setFormat(Paths.font("vcr.ttf"), 12, TEXT_GRAY, LEFT);
		statusText.scrollFactor.set();
		statusText.cameras = [camHUD];
		add(statusText);

		// Waveform sprite (inicialmente oculto)
		waveformSprite = new FlxSprite(0, 0);
		waveformSprite.makeGraphic(1, 1, 0x00000000);
		waveformSprite.scrollFactor.set();
		waveformSprite.cameras = [camGame];
		waveformSprite.visible = false;
		add(waveformSprite);
	}

	/** Toggle waveform ON/OFF — usado por el botón en toolbar y ToolsPanel. */
	public function _toggleWaveform():Void
	{
		waveformEnabled = !waveformEnabled;
		if (waveformEnabled)
		{
			if (!_waveformBuilt)
				buildWaveform();
			if (waveformSprite != null)
				waveformSprite.visible = true;
			showMessage('🌊 Waveform ON', ACCENT_CYAN);
		}
		else
		{
			if (waveformSprite != null)
				waveformSprite.visible = false;
			showMessage('🌊 Waveform OFF', TEXT_GRAY);
		}
		// Actualizar estilo del botón
		if (waveformBtn != null)
			waveformBtn.color = waveformEnabled ? 0xFF003A55 : 0xFF001A2A;
		if (waveformBtnText != null)
			waveformBtnText.color = waveformEnabled ? ACCENT_CYAN : TEXT_GRAY;
	}

	/**
	 * Reconstruye el cache de tiempos de inicio de sección.
	 * Llamar siempre que cambien las secciones o el BPM.
	 */
	function rebuildSectionTimeCache():Void
	{
		_sectionStartTimeCache = [];
		var time:Float = 0;
		for (i in 0..._song.notes.length)
		{
			_sectionStartTimeCache.push(time);
			var section = _song.notes[i];
			var bpm = section.changeBPM ? section.bpm : _song.bpm;
			var beats = section.lengthInSteps / 4;
			time += (beats * 60 / bpm) * 1000;
		}
		_sectionTimeCacheDirty = false;
	}

	/**
	 * Versión cacheada de getSectionStartTime.
	 * O(1) en lugar de O(n) — evita O(n²) en updateNotePositions.
	 */
	inline function getSectionStartTimeFast(sectionNum:Int):Float
	{
		if (_sectionTimeCacheDirty)
			rebuildSectionTimeCache();
		if (sectionNum < 0 || sectionNum >= _sectionStartTimeCache.length)
			return getSectionStartTime(sectionNum); // fallback
		return _sectionStartTimeCache[sectionNum];
	}

	/**
	 * Devuelve una Note del pool o crea una nueva.
	 */
	function poolGetNote(strumTime:Float, direction:Int):Note
	{
		if (_notePool.length > 0)
		{
			var n = _notePool.pop();
			// Reinicializar los campos mínimos necesarios
			n.strumTime = strumTime;
			n.visible = true;
			n.alpha = 1.0;
			return n;
		}
		return new Note(strumTime, direction);
	}

	/**
	 * Devuelve un sustain FlxSprite del pool o crea uno nuevo.
	 */
	function poolGetSus():FlxSprite
	{
		if (_susPool.length > 0)
		{
			var s = _susPool.pop();
			s.visible = true;
			s.alpha = 0.6;
			return s;
		}
		return new FlxSprite();
	}

	function buildWaveform():Void
	{
		if (FlxG.sound.music == null)
		{
			showMessage('X No audio loaded for waveform', ACCENT_ERROR);
			return;
		}

		showMessage('📈 Building waveform...', ACCENT_CYAN);
		trace('[ChartingState] Building waveform...');

		// Obtener referencia al Sound subyacente
		var sound:openfl.media.Sound = null;
		try
		{
			sound = @:privateAccess FlxG.sound.music._sound;
		}
		catch (e:Dynamic)
		{
		}

		if (sound == null)
		{
			showMessage('X Cannot access audio data for waveform', ACCENT_ERROR);
			return;
		}

		var waveW:Int = 40;
		var waveH:Int = Std.int(totalGridHeight);

		if (waveH <= 0 || waveH > 32000)
			waveH = Std.int(Math.min(totalGridHeight, 16000));

		// Extraer datos de amplitud
		_waveformData = BPMDetector.extractWaveform(sound, waveH);

		// Dibujar
		if (waveformSprite != null)
		{
			remove(waveformSprite, true);
			waveformSprite.destroy();
		}

		waveformSprite = new FlxSprite(gridBG.x - waveW - 4, gridBG.y);
		waveformSprite.makeGraphic(waveW, waveH, 0xFF111122, true);
		waveformSprite.scrollFactor.set();
		waveformSprite.cameras = [camGame];
		waveformSprite.visible = waveformEnabled;
		add(waveformSprite);

		// Dibujar barras
		var midX:Int = Std.int(waveW / 2);
		for (row in 0...waveH)
		{
			var amp:Float = (row < _waveformData.length) ? _waveformData[row] : 0.0;
			var barW:Int = Std.int(amp * (waveW - 2));
			if (barW < 1)
				barW = 1;

			// Color: degradado de cyan a magenta según amplitud
			var r:Int = Std.int(amp * 0xFF);
			var g:Int = Std.int((1 - amp) * 0x80);
			var b:Int = 0xFF;
			var col:Int = (0xFF << 24) | (r << 16) | (g << 8) | b;

			flixel.util.FlxSpriteUtil.drawRect(waveformSprite, midX - Std.int(barW / 2), row, barW, 1, col);
		}

		_waveformBuilt = true;
		showMessage('✅ Waveform built! (W to toggle)', ACCENT_SUCCESS);
		trace('[ChartingState] Waveform built: ${waveW}x${waveH}');
	}

	/**
	 * Detecta el BPM automáticamente desde el audio cargado.
	 */
	function detectBPM():Void
	{
		if (_bpmDetecting)
		{
			showMessage('⏳ BPM detection already running...', ACCENT_WARNING);
			return;
		}

		if (FlxG.sound.music == null)
		{
			showMessage('X No audio loaded for BPM detection', ACCENT_ERROR);
			return;
		}

		var sound:openfl.media.Sound = null;
		try
		{
			sound = @:privateAccess FlxG.sound.music._sound;
		}
		catch (e:Dynamic)
		{
		}

		if (sound == null)
		{
			showMessage('X Cannot access audio for BPM detection', ACCENT_ERROR);
			return;
		}

		_bpmDetecting = true;
		showMessage('🎵 Detecting BPM from audio...', ACCENT_WARNING);
		trace('[ChartingState] Starting BPM detection...');

		// Detectar de forma inline (síncrono — puede tardar 1-2 segundos)
		var detected:Float = BPMDetector.detect(sound, 60, 240);

		_bpmDetecting = false;

		if (detected <= 0)
		{
			showMessage('X Could not detect BPM from audio', ACCENT_ERROR);
			trace('[ChartingState] BPM detection failed');
			return;
		}

		trace('[ChartingState] Detected BPM: $detected');

		// Aplicar BPM
		_song.bpm = detected;
		tempBpm = detected;
		Conductor.changeBPM(detected);
		Conductor.mapBPMChanges(_song);

		// Actualizar stepper de BPM si existe
		if (stepperBPM != null)
			stepperBPM.value = detected;

		showMessage('✅ BPM detected: ${detected}', ACCENT_SUCCESS);
		FlxG.sound.play(Paths.sound('menus/confirmMenu'), 0.6);
	}

	function setupNewExtensions():Void
	{
		// 1. Meta popup (Stage y Speed)
		metaPopup = new MetaPopup(this, _song, camPopUp);
		add(metaPopup);

		// 2. Preview panel (izquierdo, colapsable) — con Character.hx real
		previewPanel = new PreviewPanel(this, _song, camGame, camPopUp);
		add(previewPanel);

		// 3. Events sidebar (izquierdo, encima del grid)
		eventsSidebar = new EventsSidebar(this, _song, camGame, camPopUp, gridBG.x, gridBG.y);
		add(eventsSidebar);

		// 4. Character icon row (encima del grid)
		charIconRow = new CharacterIconRow(this, _song, camPopUp, gridBG.x);
		add(charIconRow);

		// 5. Tools panel — panel lateral con controles de preview y herramientas
		//    Se abre/cierra desde la toolbar sin interactuar con el grid
		toolsPanel = new ToolsPanel(this, _song, previewPanel, camPopUp);
		add(toolsPanel);

		// Asegurar que los eventos estén inicializados en la canción
		if (_song.events == null)
			_song.events = [];
	}

	function updateInfoPanel():Void
	{
		// Time
		var time = FlxG.sound.music != null ? FlxG.sound.music.time / 1000 : 0;
		infoValues[0].text = formatTime(time);

		// BPM
		infoValues[1].text = '${Conductor.bpm}';

		// Section
		infoValues[2].text = '${curSection + 1}/${_song.notes.length}';

		// Step
		var curStep = Math.floor(Conductor.songPosition / Conductor.stepCrochet);
		infoValues[3].text = '$curStep';

		// Beat
		var curBeat = Math.floor(curStep / 4);
		infoValues[4].text = '$curBeat';

		// Notes in section
		var notesInSec = _song.notes[curSection].sectionNotes.length;
		infoValues[5].text = '$notesInSec';

		// Snap
		var snapDisplay = getSnapName(currentSnap);
		infoValues[6].text = snapDisplay;
	}

	function updateToolbar():Void
	{
		// Time
		var time = FlxG.sound.music != null ? FlxG.sound.music.time / 1000 : 0;
		var minutes = Math.floor(time / 60);
		var seconds = Math.floor(time % 60);
		var ms = Math.floor((time % 1) * 1000);
		timeText.text = '${StringTools.lpad('$minutes', "0", 2)}:${StringTools.lpad('$seconds', "0", 2)}.${StringTools.lpad('$ms', "0", 3)}';

		// BPM - mostrar valor editable
		bpmText.text = '${Conductor.bpm} BPM';

		// Section
		sectionText.text = 'Section ${curSection + 1}/${_song.notes.length}';

		// Resaltar botón Meta si el popup está abierto
		if (metaBtn != null && metaPopup != null)
			metaBtn.color = metaPopup.isOpen ? 0xFF2A2A6A : 0xFF1A1A3A;
	}

	function updateStatusBar(elapsed:Float):Void
	{
		// Rotar tips cada 5 segundos
		tipTimer += elapsed;
		if (tipTimer >= 5.0)
		{
			tipTimer = 0;
			currentTip = (currentTip + 1) % tips.length;

			FlxTween.tween(statusText, {alpha: 0}, 0.2, {
				onComplete: function(twn:FlxTween)
				{
					statusText.text = tips[currentTip];
					FlxTween.tween(statusText, {alpha: 1}, 0.2);
				}
			});
		}
	}

	public function showMessage(msg:String, ?color:FlxColor):Void
	{
		tipTimer = 0;

		// ── Animación: flash rápido y slide-up desde abajo ────────────────
		FlxTween.cancelTweensOf(statusText);
		statusText.text = msg;
		statusText.color = (color != null) ? color : cast TEXT_GRAY;
		statusText.alpha = 0;

		// Posición base
		final baseY:Float = FlxG.height - 20;
		statusText.y = baseY + 10;

		// Slide up + fade in rápido
		FlxTween.tween(statusText, {alpha: 1, y: baseY}, 0.18, {ease: FlxEase.backOut});

		// Mantener visible 2.5s, luego fade out
		FlxTween.tween(statusText, {alpha: 0}, 0.30, {
			ease: FlxEase.quadIn,
			startDelay: 2.5,
			onComplete: function(_)
			{
				statusText.color = cast TEXT_GRAY;
			}
		});
	}

	function loadSong(daSong:String):Void
	{
		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.stop();
			FlxG.sound.music = null;
		}

		// Invalidar waveform al cambiar canción
		_waveformBuilt = false;
		_waveformData = [];
		_hitsoundFiredNotes = new Map();
		_lastHitsoundTime = -999;
		if (waveformSprite != null)
			waveformSprite.visible = false;

		// ── Sufijo de audio efectivo (igual que PlayState) ────────────────────
		// Prioridad: _song.instSuffix (campo del chart, ej "erect") > curDiffSuffix.
		// Esto cubre canciones con audio separado por "variante" (no por dificultad),
		// como los tracks "Erect" de la base que tienen Inst-erect.ogg pero la
		// dificultad puede llamarse "Nightmare" con sufijo "-nightmare".
		// Resuelve también Voices-bf-erect.ogg, Voices-dad-erect.ogg, etc.
		final _audioSuffix:String = (_song != null && _song.instSuffix != null && _song.instSuffix != '') ? '-' + _song.instSuffix : curDiffSuffix;

		trace('[ChartingState] loadSong "$daSong" audioSuffix="$_audioSuffix" (instSuffix=${_song?.instSuffix}, curDiff=$curDiffSuffix)');

		try
		{
			// Intentar cargar el inst con el sufijo de audio efectivo.
			// Paths.loadInst hace fallback a Inst.ogg si no existe la variante.
			// Orden de búsqueda en Paths.inst():
			//   1. songs/{song}/song/Inst-{suffix}.ogg
			//   2. songs/{song}/Inst-{suffix}.ogg
			//   3. songs/{song}/song/Inst.ogg
			//   4. songs/{song}/Inst.ogg
			FlxG.sound.music = Paths.loadInst(daSong, _audioSuffix);
			FlxG.sound.music.pause();
			FlxG.sound.music.onComplete = function()
			{
				FlxG.sound.music.pause();
				FlxG.sound.music.time = 0;
			};
		}
		catch (e:Dynamic)
		{
			trace('Error loading song: $e');
			showMessage("X Error loading song!", ACCENT_ERROR);
		}

		// Vocals
		_destroyChartVocals();
		if (_song.needsVoices)
		{
			// Construir lista de candidatos desde SONG.characters
			var candidates:Array<{name:String, type:String}> = [];
			if (_song.characters != null && _song.characters.length > 0)
			{
				for (c in _song.characters)
				{
					var t = c.type != null ? c.type : 'Opponent';
					if (t == 'Girlfriend' || t == 'Other')
						continue;
					var dup = false;
					for (prev in candidates)
						if (prev.name == c.name)
						{
							dup = true;
							break;
						}
					if (!dup)
						candidates.push({name: c.name, type: t});
				}
			}
			// Fallback legacy player1/player2
			if (candidates.length == 0)
			{
				var p1 = (_song.player1 != null && _song.player1 != '') ? _song.player1 : 'bf';
				var p2 = (_song.player2 != null && _song.player2 != '') ? _song.player2 : 'dad';
				candidates.push({name: p1, type: 'Player'});
				if (p2 != p1)
					candidates.push({name: p2, type: 'Opponent'});
			}

			_chartPlayerKeys = [];
			_chartOpponentKeys = [];
			var loaded = 0;
			for (cand in candidates)
			{
				// Usar _audioSuffix para la búsqueda de per-char vocals.
				// Paths.loadVoicesForChar resuelve en orden:
				//   1. Voices-{char}-{suffix}.ogg  (ej: Voices-bf-erect.ogg)
				//   2. Voices-{char}.ogg            (ej: Voices-bf.ogg)
				//   3. null si no existe ninguno
				var snd = Paths.loadVoicesForChar(daSong, cand.name, _audioSuffix);
				if (snd == null)
					continue;
				snd.volume = 0.6;
				snd.looped = false;
				snd.pause();
				FlxG.sound.list.add(snd);
				vocalsPerChar.set(cand.name, snd);
				if (cand.type == 'Player' || cand.type == 'Boyfriend')
					_chartPlayerKeys.push(cand.name);
				else
					_chartOpponentKeys.push(cand.name);
				loaded++;
			}

			if (loaded > 0)
			{
				_chartPerCharVocals = true;
				trace('[ChartingState] Per-char vocals cargadas: $loaded / ${candidates.length} personajes (suffix="$_audioSuffix")');
			}
			else
			{
				// Fallback al Voices.ogg genérico (o Voices-{suffix}.ogg si existe)
				// Paths.voices() resuelve:
				//   1. Voices-{suffix}.ogg  (ej: Voices-erect.ogg)
				//   2. Voices.ogg
				_chartPerCharVocals = false;
				try
				{
					vocals = Paths.loadVoices(daSong, _audioSuffix);
					vocals.volume = 0.6;
					vocals.looped = false;
					vocals.pause();
					FlxG.sound.list.add(vocals);
				}
				catch (e:Dynamic)
				{
					trace('Error loading vocals: $e');
				}
			}
		}
		else
		{
			_chartPerCharVocals = false;
		}

		Conductor.changeBPM(_song.bpm);
		Conductor.mapBPMChanges(_song);
	}

	// Sincronizar vocales con la música
	function syncVocals():Void
	{
		if (FlxG.sound.music == null)
			return;

		if (_chartPerCharVocals)
		{
			for (v in vocalsPerChar)
			{
				if (v == null)
					continue;
				if (Math.abs(v.time - FlxG.sound.music.time) > 50)
					v.time = FlxG.sound.music.time;
				v.volume = FlxG.sound.music.volume;
				if (FlxG.sound.music.playing)
				{
					if (!v.playing)
						v.play();
				}
				else
				{
					if (v.playing)
						v.pause();
				}
			}
		}
		else if (vocals != null)
		{
			var timeDiff = Math.abs(vocals.time - FlxG.sound.music.time);
			if (timeDiff > 50)
				vocals.time = FlxG.sound.music.time;
			vocals.volume = FlxG.sound.music.volume;
			if (FlxG.sound.music.playing)
			{
				if (!vocals.playing)
					vocals.play();
			}
			else
			{
				if (vocals.playing)
					vocals.pause();
			}
		}
	}

	override function update(elapsed:Float):Void
	{
		// Resetear el flag de consumo de rueda ANTES de actualizar los hijos
		// (CharacterIconRow y otros componentes lo ponen a true si consumen el wheel)
		wheelConsumed = false;
		clickConsumed = false;
		super.update(elapsed);

		updateToolbar();
		updateInfoPanel();
		updateStatusBar(elapsed);

		// ✨ SINCRONIZAR VOCALES - llamar en cada frame
		syncVocals();

		// ✨ Actualizar animación pulsante de nota seleccionada
		selectedNotePulse += elapsed * selectedNotePulseSpeed;

		// Ejemplo de cómo debería calcularse el tiempo según la sección

		Conductor.songPosition = FlxG.sound.music != null ? FlxG.sound.music.time : 0;

		// ✅ SOLO ESTAS DOS LÍNEAS NUEVAS:
		updateGridScroll();
		updateCurrentSection();
		updateNotePositions(); // ✨ Actualizar posiciones cuando el grid se mueve
		// updateSectionIndicators(); // ✨ Actualizar indicadores de sección
		cullNotes();

		// Preview character: detectar notas que pasa el playhead
		if (previewPanel != null && FlxG.sound.music != null && FlxG.sound.music.playing)
			checkNotesForPreview();

		// Hitsounds durante reproducción
		if (hitsoundsEnabled && FlxG.sound.music != null && FlxG.sound.music.playing)
			checkNotesForHitsound();

		updateChartPreview();
		_updateEditorStrums();
		updateNoteDrag();
		updateMultiDragAndSelBox();
		handleMouseInput();
		handleKeyboardInput();
		handlePlaybackButtons();

		// Metronome
		if (metronomeEnabled && FlxG.sound.music != null && FlxG.sound.music.playing)
		{
			var curBeat = Math.floor(Conductor.songPosition / Conductor.crochet);
			if (curBeat != lastMetronomeBeat)
			{
				FlxG.sound.play(Paths.soundRandom('menus/chartingSounds/metronome', 1, 2), 0.5);
				lastMetronomeBeat = curBeat;
			}
		}

		// Autosave
		autosaveTimer += elapsed;
		if (autosaveTimer >= 300.0)
		{
			autosaveTimer = 0;
			autosaveChart();
		}

		if (UI_box != null)
			UI_box.selected_tab_id = UI_box.selected_tab_id;
	}

	function updateCurrentSection():Void
	{
		// Determinar en qué sección estamos basado en la posición de la música
		if (FlxG.sound.music == null)
			return;

		var currentTime = FlxG.sound.music.time;
		var accumulatedTime:Float = 0;

		for (i in 0..._song.notes.length)
		{
			var sectionTime = getSectionDuration(i);

			if (currentTime >= accumulatedTime && currentTime < accumulatedTime + sectionTime)
			{
				if (curSection != i)
				{
					curSection = i;
					updateSectionUI();
					updateSectionIndicators();
				}
				break;
			}

			accumulatedTime += sectionTime;
		}
	}

	function getSectionDuration(sectionNum:Int):Float
	{
		var section = _song.notes[sectionNum];
		var bpm = section.changeBPM ? section.bpm : _song.bpm;
		var beats = section.lengthInSteps / 4;
		return (beats * 60 / bpm) * 1000;
	}

	/**
	 * Detecta qué notas están siendo "tocadas" por el playhead en este momento
	 * y dispara onNotePass en el PreviewPanel.
	 * Se llama cada frame mientras la música esté reproduciendo.
	 */
	function checkNotesForPreview():Void
	{
		if (previewPanel == null)
			return;

		var currentTime = FlxG.sound.music.time;
		var tolerance = Conductor.stepCrochet * 0.6;

		if (Math.abs(currentTime - _lastMusicTime) > 500)
			_firedNotes = new Map();
		_lastMusicTime = currentTime;

		for (secNum in 0..._song.notes.length)
		{
			var section = _song.notes[secNum];
			for (noteData in section.sectionNotes)
			{
				var noteTime:Float = noteData[0];
				var rawData:Int = Std.int(noteData[1]);

				if (Math.abs(noteTime - currentTime) > tolerance)
					continue;

				var key = '${Std.int(noteTime)}_${rawData}';
				if (_firedNotes.exists(key))
					continue;
				_firedNotes.set(key, true);

				var groupIndex = Math.floor(rawData / 4);
				var direction = rawData % 4;

				previewPanel.onNotePass(direction, groupIndex);
			}
		}
	}

	/**
	 * Actualiza los strums del editor cada frame:
	 *  - Detecta notas que cruzan el playhead y registra en _strumConfirmUntil
	 *    el timestamp hasta el que debe mostrarse confirm (noteTime + daSus para holds).
	 *  - Cada frame aplica confirm/static según el tiempo, reiniciando confirm si
	 *    la animación terminó pero el hold sigue activo.
	 *  - Fuerza setGraphicSize(GRID_SIZE, GRID_SIZE) cada frame para compensar que
	 *    los frames de 'confirm' tienen dimensiones distintas a 'static', lo que
	 *    hace que el strum aparezca más grande/desplazado tras la animación.
	 */
	function _updateEditorStrums():Void
	{
		if (_editorStrums == null)
			return;

		var isPlaying = (FlxG.sound.music != null && FlxG.sound.music.playing);
		var currentTime = isPlaying ? FlxG.sound.music.time : -9999.0;
		var tolerance   = Conductor.stepCrochet * 0.6;

		// ── Detectar notas que entran al playhead ─────────────────────────────
		if (isPlaying)
		{
			// Reset cuando la música salta (seek / reinicio)
			if (Math.abs(currentTime - _lastMusicTime) > 500)
			{
				_firedNotes        = new Map();
				_strumConfirmUntil = new Map();
			}
			if (previewPanel == null)
				_lastMusicTime = currentTime;

			for (secNum in 0..._song.notes.length)
			{
				var section = _song.notes[secNum];
				for (noteData in section.sectionNotes)
				{
					var noteTime:Float = noteData[0];
					var rawData:Int    = Std.int(noteData[1]);
					var daSus:Float    = (noteData[2] != null) ? noteData[2] : 0.0;

					if (Math.abs(noteTime - currentTime) > tolerance)
						continue;

					// Clave con prefijo distinta a la de checkNotesForPreview
					var key = 's${Std.int(noteTime)}_${rawData}';
					if (_firedNotes.exists(key))
						continue;
					_firedNotes.set(key, true);

					var visCol = _noteVisColFromRaw(rawData, secNum);
					if (visCol < 0 || visCol >= _editorStrums.length)
						continue;

					// Nota normal: confirm dura ~1 frame (20 ms mínimo)
					// Sustain:     confirm dura todo el hold (daSus ms)
					var holdEnd = noteTime + (daSus > 0 ? daSus : 20.0);
					var prev = _strumConfirmUntil.exists(visCol) ? _strumConfirmUntil.get(visCol) : 0.0;
					if (holdEnd > prev)
						_strumConfirmUntil.set(visCol, holdEnd);
				}
			}
		}
		else
		{
			// Música parada → todos los strums a static
			_strumConfirmUntil = new Map();
		}

		// ── Actualizar animación y tamaño de cada strum ───────────────────────
		for (i in 0..._editorStrums.length)
		{
			var strum = _editorStrums.members[i];
			if (strum == null)
				continue;

			var confirmUntil  = _strumConfirmUntil.exists(i) ? _strumConfirmUntil.get(i) : 0.0;
			var shouldConfirm = isPlaying && (currentTime < confirmUntil);
			var curAnim       = (strum.animation.curAnim != null) ? strum.animation.curAnim.name : '';

			if (shouldConfirm)
			{
				if (curAnim != 'confirm')
				{
					strum.playAnim('confirm');
				}
				else if (strum.animation.curAnim.finished)
				{
					// El hold sigue pero la animación completó su ciclo → reiniciarla
					strum.playAnim('confirm');
				}
			}
			else
			{
				if (curAnim != 'static' && curAnim != 'idle')
				{
					strum.playAnim('static');
				}
			}
			strum.setGraphicSize(GRID_SIZE + 1, GRID_SIZE + 1);
			strum.updateHitbox();
			strum.offset.set(0, 0);
		}
	}

	// Timestamp de la última nota enviada al preview (evitar spam)
	var _firedNotes:Map<String, Bool> = new Map();
	var _lastMusicTime:Float = -999;

	/**
	 * Dispara hitsounds por cada nota del chart cuando el playhead la cruza.
	 * Usa su propio mapa independiente de _firedNotes (preview).
	 */
	function checkNotesForHitsound():Void
	{
		var currentTime:Float = FlxG.sound.music.time;
		var tolerance:Float = Conductor.stepCrochet * 0.55;

		// Reset si el audio saltó (seek / reinicio)
		if (Math.abs(currentTime - _lastHitsoundTime) > 500)
			_hitsoundFiredNotes = new Map();
		_lastHitsoundTime = currentTime;

		// Sonidos disponibles para hitsound por dirección
		var hitSounds:Array<String> = [
			'menus/chartingSounds/ClickLeft',
			'menus/chartingSounds/ClickDown',
			'menus/chartingSounds/ClickUp',
			'menus/chartingSounds/ClickRight'
		];
		// Fallback si no hay direccionales
		var hitFallback:String = 'menus/chartingSounds/noteLay';

		for (secNum in 0..._song.notes.length)
		{
			var section = _song.notes[secNum];
			for (noteData in section.sectionNotes)
			{
				var noteTime:Float = noteData[0];
				if (Math.abs(noteTime - currentTime) > tolerance)
					continue;

				// Clave única por nota
				var key = '${Std.int(noteTime)}_${Std.int(noteData[1])}';
				if (_hitsoundFiredNotes.exists(key))
					continue;
				_hitsoundFiredNotes.set(key, true);

				// Elegir sonido según dirección (columna % 4)
				var dir:Int = Std.int(noteData[1]) % 4;
				var sndPath:String = hitSounds[dir % hitSounds.length];

				try
				{
					playHitSound();
				}
				catch (e:Dynamic)
				{
					// Fallback si el sonido específico no existe
					try
					{
						FlxG.sound.play(Paths.sound(hitFallback), 0.5);
					}
					catch (_)
					{
					}
				}
			}
		}
	}

	// ── Hitsound pool (evita new FlxSound cada golpe) ─────────────────────
	private var _hitSounds:Array<FlxSound> = [];
	private var _hitSoundIdx:Int = 0;

	private static inline var HIT_SOUND_POOL_SIZE:Int = 4;

	private function initHitSoundPool():Void
	{
		_hitSounds = [];
		for (i in 0...HIT_SOUND_POOL_SIZE)
		{
			var snd = new FlxSound();
			try
			{
				snd.loadEmbedded(Paths.sound('hitsounds/hit-1'));
			}
			catch (_:Dynamic)
			{
			}
			snd.looped = false;
			FlxG.sound.list.add(snd);
			_hitSounds.push(snd);
		}
	}

	/**
	 * Play hitsound — usa pool de FlxSound para evitar alloc por golpe
	 */
	private function playHitSound():Void
	{
		if (_hitSounds.length == 0)
			initHitSoundPool();
		var snd = _hitSounds[_hitSoundIdx % HIT_SOUND_POOL_SIZE];
		_hitSoundIdx++;
		if (snd == null)
			return;
		snd.volume = 1 + FlxG.random.float(-0.2, 0.2);
		snd.play(true);
	}

	function updateSectionIndicators():Void
	{
		// Limpiar indicadores previos
		sectionIndicators.clear();

		var currentY:Float = 0;
		for (i in 0..._song.notes.length)
		{
			var sectionHeight = _song.notes[i].lengthInSteps * GRID_SIZE;

			// Línea divisora
			var divider = new FlxSprite(gridBG.x, (100 - gridScrollY) + currentY);
			divider.makeGraphic(Std.int(gridBG.width), 2, (i == curSection ? ACCENT_CYAN : 0x80FFFFFF));
			divider.scrollFactor.set();
			divider.cameras = [camGame];
			sectionIndicators.add(divider);

			// Número de sección
			var numText = new FlxText(gridBG.x - 30, (100 - gridScrollY) + currentY + 5, 0, '${i + 1}', 12);
			numText.setFormat(Paths.font("vcr.ttf"), 12, (i == curSection ? ACCENT_CYAN : TEXT_GRAY), LEFT);
			numText.scrollFactor.set();
			numText.cameras = [camGame];
			numText.antialiasing = FlxG.save.data.antialiasing;
			sectionIndicators.add(cast numText);

			currentY += sectionHeight;
		}
	}

	function updateGridScroll():Void
	{
		// ✨ AUTO-SCROLL cuando la música está tocando
		if (FlxG.sound.music != null && FlxG.sound.music.playing)
		{
			// Calcular posición del grid basada en la posición de la música
			var accumulatedSteps:Float = 0;
			var targetScrollY:Float = 0;

			for (i in 0..._song.notes.length)
			{
				var sectionStartTime = getSectionStartTime(i);
				var sectionEndTime = sectionStartTime + getSectionDuration(i);

				if (Conductor.songPosition >= sectionStartTime && Conductor.songPosition < sectionEndTime)
				{
					// Estamos en esta sección
					var progressInSection = (Conductor.songPosition - sectionStartTime) / getSectionDuration(i);
					var sectionHeight = _song.notes[i].lengthInSteps * GRID_SIZE;
					targetScrollY = accumulatedSteps + (progressInSection * sectionHeight);
					break;
				}

				accumulatedSteps += _song.notes[i].lengthInSteps * GRID_SIZE;
			}

			// Suavizar el movimiento de la cámara
			gridScrollY = FlxMath.lerp(gridScrollY, targetScrollY, 0.15);
			gridScrollY = clamp(gridScrollY, 0, maxScroll);

			_applyGridScroll(gridScrollY);
			_notePositionsDirty = true; // ← grid se movió

			// Actualizar waveform con el scroll
			if (waveformSprite != null && waveformSprite.visible)
				waveformSprite.y = 100 - gridScrollY;

			// Actualizar sidebar de eventos con nuevo scroll
			if (eventsSidebar != null)
				eventsSidebar.setScrollY(gridScrollY, gridBG.y);
		}

		// Scroll con rueda del mouse
		// • No scrollear si hay un popup abierto (CharacterPickerMenu, MetaPopup, etc.)
		// • No scrollear si un sub-componente ya consumió el evento (p.ej. CTRL+wheel en el icon row)
		if (FlxG.mouse.wheel != 0 && !isAnyPopupOpen() && !wheelConsumed)
		{
			updateSectionIndicators();
			var scrollAmount = FlxG.mouse.wheel * (FlxG.keys.pressed.SHIFT ? GRID_SIZE : GRID_SIZE * 4);
			gridScrollY -= scrollAmount;
			gridScrollY = clamp(gridScrollY, 0, maxScroll);

			_applyGridScroll(gridScrollY);
			_notePositionsDirty = true; // ← scroll manual

			// Actualizar waveform con el scroll
			if (waveformSprite != null && waveformSprite.visible)
				waveformSprite.y = 100 - gridScrollY;

			// Actualizar sidebar de eventos con nuevo scroll
			if (eventsSidebar != null)
				eventsSidebar.setScrollY(gridScrollY, gridBG.y);

			// ✨ SINCRONIZAR posición de música cuando haces scroll con la rueda (si está pausado).
			// Esto garantiza que al presionar Space se reproduzca desde donde ves el grid,
			// no desde donde estaba antes de scrollear.
			if (FlxG.sound.music != null && !FlxG.sound.music.playing)
			{
				var seekMs = _gridScrollToTime(gridScrollY);
				FlxG.sound.music.time = seekMs;
			}
			syncVocals();
		}
	}

	function handleMouseInput():Void
	{
		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;

		// ── Sustain resize activo: se procesa ANTES del guard de retorno ──────
		// (si estuviera después del return no se ejecutaría nunca)
		if (_susResizeActive && _susResizeNote != null)
		{
			if (FlxG.mouse.pressed)
			{
				var dyPixels = my - _susResizeStartY;
				var stepsPerSnap = 16.0 / currentSnap;
				var rawSteps = dyPixels / GRID_SIZE;
				var snappedSteps = Math.max(0, Math.round(rawSteps / stepsPerSnap) * stepsPerSnap);
				var newSus = snappedSteps * Conductor.stepCrochet;
				if (_susResizeNote[2] != newSus)
				{
					_susResizeNote[2] = newSus;
					_notePositionsDirty = true;
					updateGrid();
				}
			}
			else if (FlxG.mouse.justReleased)
			{
				if (_susResizeNote[2] == _susResizeOriginalSus)
					undoStack.pop();
				_susResizeNote   = null;
				_susResizeSection = -1;
				_susResizeActive  = false;
			}
			return; // no procesar ningún otro input mientras se está resizeando
		}

		// Drag activo (single o multi) o box select: sus propias funciones se encargan
		if (_dragActive || _multiDragActive || _selBoxActive)
			return;

		// ── Bounds check corregido ────────────────────────────────────────────
		// gridBG.y cambia con el scroll (puede ser negativo), así que NO sirve
		// como cota superior fija. El grid visualmente siempre empieza en y=100.
		var mouseOverGrid = (mx >= gridBG.x && mx < gridBG.x + gridBG.width && my >= 100.0 && my < FlxG.height);

		var popupBlocking = isAnyPopupOpen();

		// ── Left click: selección, drag, box select ─────────────────────────────
		if (FlxG.mouse.justPressed && mouseOverGrid && !popupBlocking && !clickConsumed && !_dragActive && !_multiDragActive)
		{
			if (openfl.Lib.current.stage.focus != null)
				openfl.Lib.current.stage.focus = null;

			var mouseGridX = mx - gridBG.x;
			var mouseGridY = my - gridBG.y;
			var col = Math.floor(mouseGridX / GRID_SIZE);

			if (col >= 0)
			{
				var foundNote = _findNoteAtGrid(mouseGridY, col);

				if (foundNote != null)
				{
					if (FlxG.keys.pressed.SHIFT)
					{
						// Shift+click → añadir/quitar de selección sin drag
						_toggleSelectNote(foundNote.note, foundNote.section);
					}
					else if (_isSelected(foundNote.note) && _selectedNotes.length > 1)
					{
						// Nota seleccionada en multi-selección → multi-drag pending
						_multiDragPending = true;
						_dragStartX = mx;
						_dragStartY = my;
					}
					else
					{
						// Nota normal → drag single pending.
						// NO limpiamos la selección aquí; lo haremos al soltar o al iniciar drag.
						// _dragPendingWasSelected = true si la nota PARECE seleccionada
						// (está en _selectedNotes O es curSelectedNote — evita el bug de nota
						// que pulsa pero no está en el array).
						_dragPendingWasSelected = _isSelected(foundNote.note) || (curSelectedNote == foundNote.note);
						_dragPending = foundNote.note;
						_dragPendingSection = foundNote.section;
						_dragStartX = mx;
						_dragStartY = my;
					}
				}
				else
				{
					// Espacio vacío
					if (!FlxG.keys.pressed.SHIFT)
						_clearSelection();
					// Iniciar box select
					_selBoxActive = true;
					var rawStep = (mouseGridY / GRID_SIZE) + _gridWindowOffset;
					_selBoxStartStep = rawStep;
					_selBoxStartCol = mx - gridBG.x;
					_dragStartX = mx;
					_dragStartY = my;
				}
			}
		}

		// ── Multi-drag pending: activar si supera threshold ───────────────────
		if (_multiDragPending && !_multiDragActive && FlxG.mouse.pressed)
		{
			var dx = mx - _dragStartX;
			var dy = my - _dragStartY;
			if (Math.sqrt(dx * dx + dy * dy) > NOTE_DRAG_THRESHOLD)
			{
				_multiDragPending = false;
				_startMultiDrag(mx, my);
			}
		}
		// Multi-drag pending soltado sin moverse → limpiar selección
		// (el usuario hizo click sobre las notas seleccionadas pero no las arrastró)
		if (_multiDragPending && !_multiDragActive && FlxG.mouse.justReleased)
		{
			_multiDragPending = false;
			_clearSelection();
			_notePositionsDirty = true;
		}

		// ── Single drag pending: activar si supera threshold ─────────────────
		if (_dragPending != null && !_dragActive && FlxG.mouse.pressed)
		{
			var dx = mx - _dragStartX;
			var dy = my - _dragStartY;
			if (Math.sqrt(dx * dx + dy * dy) > NOTE_DRAG_THRESHOLD)
			{
				_startNoteDrag(_dragPending, _dragPendingSection, mx, my);
			}
		}
		// Single drag pending soltado sin moverse → click normal
		if (_dragPending != null && !_dragActive && FlxG.mouse.justReleased)
		{
			if (_dragPendingWasSelected)
			{
				// La nota ya estaba seleccionada y no se arrastró → deseleccionar
				_clearSelection();
				updateNoteUI();
			}
			else
			{
				// Click en nota no seleccionada → limpiar selección previa y seleccionar esta
				_clearSelection();
				var mouseGridX = mx - gridBG.x;
				var mouseGridY = my - gridBG.y;
				var col = Math.floor(mouseGridX / GRID_SIZE);
				if (col >= 0)
				{
					var noteFound = selectNoteAtPosition(mouseGridY, col);
					if (!noteFound)
						addNoteAtWorldPosition(mouseGridY, col);
				}
			}
			_dragPending = null;
			_dragPendingSection = -1;
			_dragPendingWasSelected = false;
		}

		// ── Sustain resize activo: actualizar sustain en tiempo real ──────────
		if (_susResizeActive && _susResizeNote != null)
		{
			if (FlxG.mouse.pressed)
			{
				// Delta en píxeles → convertir a ms respetando el snap actual
				var dyPixels = my - _susResizeStartY;
				var stepsPerSnap = 16.0 / currentSnap; // pasos por subdivisión del snap
				var rawSteps = dyPixels / GRID_SIZE;    // pasos flotantes
				// Snap al múltiplo de stepCrochet más cercano (snapeo a la subdivisión)
				var snappedSteps = Math.max(0, Math.round(rawSteps / stepsPerSnap) * stepsPerSnap);
				var newSus = snappedSteps * Conductor.stepCrochet;
				if (_susResizeNote[2] != newSus)
				{
					_susResizeNote[2] = newSus;
					_notePositionsDirty = true;
					updateGrid();
				}
			}
			else if (FlxG.mouse.justReleased)
			{
				// Si el sustain final coincide con el original, descartar el undo
				if (_susResizeNote[2] == _susResizeOriginalSus)
					undoStack.pop();
				_susResizeNote    = null;
				_susResizeSection = -1;
				_susResizeActive  = false;
			}
		}

		// ── Hover note preview + highlight del cursor ────────────────────────
		if (mouseOverGrid && !_dragActive && !_susResizeActive && !popupBlocking && !_multiDragActive)
		{
			var mouseGridX = mx - gridBG.x;
			var mouseGridY = my - gridBG.y;

			var col = Math.floor(mouseGridX / GRID_SIZE);
			var stepHeight = GRID_SIZE / (currentSnap / 16);
			var gridY = Math.floor(mouseGridY / stepHeight) * stepHeight;

			// Cuadro de highlight sutil de fondo (siempre visible al hacer hover)
			highlight.x = gridBG.x + col * GRID_SIZE;
			highlight.y = gridBG.y + gridY;
			highlight.visible = true;

			// Note preview: mostrar solo en celdas vacías (sin nota existente)
			if (col >= 0 && col < getGridColumns())
			{
				var existingNote = _findNoteAtGrid(mouseGridY, col);
				if (existingNote == null)
				{
					// Celda vacía: mostrar preview semi-transparente de la nota
					_showGhostNote(col, mouseGridY, 0.42);
					_hoverNoteCol = col;
				}
				else
				{
					// Hay nota: ocultar preview
					_hideAllGhostNotes();
				}
			}
		}
		else if (!_dragActive)
		{
			highlight.visible = false;
			_hideAllGhostNotes();
		}

		// ── Right click: borrar nota ─────────────────────────────────────────
		if (FlxG.mouse.justPressedRight && mouseOverGrid && !popupBlocking && !clickConsumed)
		{
			var mouseGridX = mx - gridBG.x;
			var mouseGridY = my - gridBG.y;
			var noteData = Math.floor(mouseGridX / GRID_SIZE);

			if (noteData >= 0)
				deleteNoteAtPosition(mouseGridY, noteData);
		}
	}

	// =========================================================================
	//  DRAG-AND-DROP DE NOTAS
	// =========================================================================

	/**
	 * Busca la nota que está exactamente en la celda (worldY, visualCol).
	 * Devuelve { note, section } o null si no hay ninguna.
	 */
	function _findNoteAtGrid(worldY:Float, visualCol:Int):Null<{note:Array<Dynamic>, section:Int}>
	{
		var clickedStep = (worldY / GRID_SIZE) + _gridWindowOffset;
		var snapSteps = (currentSnap / 16);
		clickedStep = Math.floor(clickedStep / snapSteps) * snapSteps;

		var accumulatedSteps:Float = 0;
		for (i in 0..._song.notes.length)
		{
			var sectionSteps = _song.notes[i].lengthInSteps;
			if (clickedStep < accumulatedSteps + sectionSteps)
			{
				var noteTimeInSection = (clickedStep - accumulatedSteps) * Conductor.stepCrochet;
				var noteStrumTime = getSectionStartTime(i) + noteTimeInSection;
				var reordered = visualColToDataCol(visualCol);
				var actualData = reordered;
				if (reordered < 8 && _song.notes[i].mustHitSection)
					actualData = (reordered < 4) ? reordered + 4 : reordered - 4;
				for (nd in _song.notes[i].sectionNotes)
					if (Math.abs(nd[0] - noteStrumTime) < 5 && Std.int(nd[1]) == actualData)
						return {note: nd, section: i};
				return null;
			}
			accumulatedSteps += sectionSteps;
		}
		return null;
	}

	/** Activa el drag: quita la nota del chart y muestra el ghost. */
	function _startNoteDrag(note:Array<Dynamic>, section:Int, mx:Float, my:Float):Void
	{
		_dragNote = note;
		_dragNoteSection = section;
		_dragActive = true;
		_dragPending = null;
		_dragPendingSection = -1;

		// Limpiar selección al iniciar el drag (evita highlights fantasma)
		_clearSelection();

		// Quitar nota del chart (se reinserta en _stopNoteDrag)
		saveUndoState("delete", {section: section, note: [note[0], note[1], note[2]]});
		_song.notes[section].sectionNotes.remove(note);
		updateGrid();

		// Columna visual inicial
		var daNoteData:Int = Std.int(note[1]);
		var swapped = daNoteData;
		if (daNoteData < 8 && _song.notes[section].mustHitSection)
			swapped = (daNoteData < 4) ? daNoteData + 4 : daNoteData - 4;
		var initCol = dataColToVisualCol(swapped);
		_dragGhostCol = initCol;

		// Mostrar Note-ghost en posición inicial
		var mouseGridY = my - gridBG.y;
		_showGhostNote(initCol, mouseGridY, 0.78);
		curSelectedNote = null;
	}

	/** Llamado cada frame mientras _dragActive. Mueve el ghost y anima el color. */
	function updateNoteDrag():Void
	{
		if (!_dragActive || _dragNote == null)
			return;

		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;

		// Columna visual actual bajo el cursor
		var mouseGridX = mx - gridBG.x;
		var mouseGridY = my - gridBG.y;
		var curCol = Math.floor(mouseGridX / GRID_SIZE);
		var numCols = getGridColumns();
		curCol = Std.int(Math.max(0, Math.min(numCols - 1, curCol)));

		// Actualizar Note-ghost (cambia dirección si la columna cambió)
		if (curCol != _dragGhostCol)
			_dragGhostCol = curCol;
		_showGhostNote(curCol, mouseGridY, 0.78);

		// Soltar → finalizar drag
		if (FlxG.mouse.justReleased)
			_stopNoteDrag(mx, my);

		// ESC → cancelar drag (devolver nota a su posición original)
		if (FlxG.keys.justPressed.ESCAPE)
			_cancelNoteDrag();
	}

	/** Actualiza posición X/Y del ghost snapeado a la celda más cercana. */
	function _updateGhostPosition(mx:Float, my:Float):Void
	{
		var mouseGridX = mx - gridBG.x;
		var mouseGridY = my - gridBG.y;
		var numCols = getGridColumns();
		var snapCol = Std.int(Math.max(0, Math.min(numCols - 1, Math.floor(mouseGridX / GRID_SIZE))));
		_showGhostNote(snapCol, mouseGridY, 0.78);
	}

	/** Suelta la nota: la inserta en la nueva posición. */
	function _stopNoteDrag(mx:Float, my:Float):Void
	{
		_hideAllGhostNotes();

		var mouseGridX = mx - gridBG.x;
		var mouseGridY = my - gridBG.y;
		var numCols = getGridColumns();
		var snapSteps = (currentSnap / 16);

		// Calcular step absoluto snapeado
		var rawStep = (mouseGridY / GRID_SIZE) + _gridWindowOffset;
		var snapStep = Math.max(0, Math.floor(rawStep / snapSteps) * snapSteps);
		var snapCol = Std.int(Math.max(0, Math.min(numCols - 1, Math.floor(mouseGridX / GRID_SIZE))));

		// Encontrar sección destino
		var accumulatedSteps:Float = 0;
		var targetSection:Int = 0;
		var noteTimeInSection:Float = 0;
		for (i in 0..._song.notes.length)
		{
			if (snapStep < accumulatedSteps + _song.notes[i].lengthInSteps)
			{
				targetSection = i;
				noteTimeInSection = (snapStep - accumulatedSteps) * Conductor.stepCrochet;
				break;
			}
			accumulatedSteps += _song.notes[i].lengthInSteps;
		}

		// Columna destino en espacio de datos
		var reorderedData = visualColToDataCol(snapCol);
		var actualData = reorderedData;
		if (reorderedData < 8 && _song.notes[targetSection].mustHitSection)
			actualData = (reorderedData < 4) ? reorderedData + 4 : reorderedData - 4;

		var newStrumTime = getSectionStartTime(targetSection) + noteTimeInSection;
		var newNote:Array<Dynamic> = [newStrumTime, actualData, _dragNote[2]];
		if (_dragNote.length > 3 && _dragNote[3] != null)
			newNote.push(_dragNote[3]);

		// Columna visual original de la nota arrastrada (para la animación)
		var origDragData:Int = Std.int(_dragNote[1]);
		var origSwapped = origDragData;
		if (origDragData < 8 && _song.notes[_dragNoteSection].mustHitSection)
			origSwapped = (origDragData < 4) ? origDragData + 4 : origDragData - 4;
		var origVisCol = dataColToVisualCol(origSwapped);

		// ✨ Animar flip si la columna visual cambió
		if (origVisCol != snapCol)
		{
			var srcX  = gridBG.x + origVisCol * GRID_SIZE;
			var dstX  = gridBG.x + snapCol   * GRID_SIZE;
			// Calcular Y de la nota desde el snapStep (misma lógica que _showGhostNote)
			var noteY = (100 - gridScrollY) + snapStep * GRID_SIZE;
			_spawnNoteFlip(srcX, dstX, noteY, NOTE_COLORS[origVisCol % 8], NOTE_COLORS[snapCol % 8]);
		}

		saveUndoState("add", {section: targetSection, note: newNote});
		_song.notes[targetSection].sectionNotes.push(newNote);
		curSelectedNote = newNote;

		_dragNote = null;
		_dragNoteSection = -1;
		_dragActive = false;
		_dragGhostCol = -1;

		updateGrid();
		updateNoteUI();
		showMessage('✔ Nota movida', ACCENT_GREEN);
	}

	/**
	 * Lanza una animación de "card-flip" entre dos columnas del grid.
	 *
	 * Fase 1 (squeeze):  el sprite viaja de srcX a dstX mientras scaleX va de 1→0
	 *                    y rota 90° — como una carta girando de canto.
	 * Fase 2 (expand):   en el lado opuesto el sprite abre scaleX de 0→1 con el
	 *                    nuevo color y una leve vibración de escala.
	 * Fase 3 (fade-out): el sprite se desvanece suavemente.
	 *
	 * Todo ocurre en ~0.45 s y no bloquea el hilo principal.
	 */
	function _spawnNoteFlip(srcX:Float, dstX:Float, noteY:Float, srcColor:Int, dstColor:Int):Void
	{
		if (_noteFlipGroup == null) return;

		// ── Crear sprite base ───────────────────────────────────────────────
		var s = new FlxSprite(srcX, noteY);
		s.makeGraphic(GRID_SIZE, GRID_SIZE, srcColor);
		s.scrollFactor.set(0, 0);
		s.cameras = [camGame];
		// Punto de origen centrado para que el flip gire alrededor del centro
		s.origin.set(GRID_SIZE * 0.5, GRID_SIZE * 0.5);
		_noteFlipGroup.add(s);

		// ── Añadir brillo interior (overlay blanco semitransparente) ────────
		var glow = new FlxSprite(srcX + 4, noteY + 4);
		glow.makeGraphic(GRID_SIZE - 8, GRID_SIZE - 8, 0x55FFFFFF);
		glow.scrollFactor.set(0, 0);
		glow.cameras = [camGame];
		_noteFlipGroup.add(glow);

		final HALF  = 0.13; // segundos para la primera mitad (squeeze)
		final HALF2 = 0.13; // segundos para la segunda mitad (expand)
		final FADE  = 0.16; // segundos para fade-out final

		// ── FASE 1: squeeze hacia el centro + viaje lateral ─────────────────
		// NOTE: FlxSprite no expone scaleX/scaleY como propiedades directas.
		// Se usan FlxTween.num() paralelos para animar scale.x / scale.y.
		FlxTween.tween(s, {x: dstX, angle: 15}, HALF, {
			ease: FlxEase.quadIn,
			onComplete: function(_)
			{
				// ── Cambio de cara en el punto de inflexión ──────────────────
				s.color   = dstColor;
				s.angle   = -15;
				s.scale.x = 0.0;
				s.makeGraphic(GRID_SIZE, GRID_SIZE, dstColor);

				// ── FASE 2: expand con overshoot + glow ─────────────────────
				FlxTween.num(0.0, 1.1, HALF2 * 0.6, {ease: FlxEase.quadOut,
					onComplete: function(_)
					{
						FlxTween.num(1.1, 1.0, HALF2 * 0.4, {ease: FlxEase.quadInOut,
							onComplete: function(_)
							{
								// ── FASE 3: fade-out ─────────────────────────
								FlxTween.tween(s,    {alpha: 0.0}, FADE, {ease: FlxEase.quadIn,
									onComplete: function(_) { _noteFlipGroup.remove(s, true); }});
								FlxTween.tween(glow, {alpha: 0.0}, FADE, {ease: FlxEase.quadIn,
									onComplete: function(_) { _noteFlipGroup.remove(glow, true); }});
							}
						}, function(v) { s.scale.x = v; });
					}
				}, function(v) { s.scale.x = v; });
				FlxTween.tween(s, {angle: 0}, HALF2 * 0.6, {ease: FlxEase.quadOut});

				// Glow viaja con el sprite
				FlxTween.tween(glow, {x: dstX + 4, alpha: 0.7}, HALF2, {ease: FlxEase.quadOut});
			}
		});
		// Scale squeeze paralelo a la posición (fase 1)
		FlxTween.num(1.0, 0.0, HALF, {ease: FlxEase.quadIn}, function(v) { s.scale.x = v; });

		// El glow también viaja durante la fase 1
		FlxTween.tween(glow, {x: dstX + 4}, HALF, {ease: FlxEase.quadIn});
		FlxTween.num(1.0, 0.0, HALF, {ease: FlxEase.quadIn}, function(v) { glow.scale.x = v; });

		// ── Partícula de "chispa" en el origen ──────────────────────────────
		var spark = new FlxSprite(srcX + GRID_SIZE * 0.5 - 4, noteY + GRID_SIZE * 0.5 - 4);
		spark.makeGraphic(8, 8, srcColor);
		spark.scrollFactor.set(0, 0);
		spark.cameras = [camGame];
		_noteFlipGroup.add(spark);

		FlxTween.tween(spark, {x: srcX - 6, y: noteY - 10, alpha: 0}, HALF + HALF2, {
			ease: FlxEase.quadOut,
			onComplete: function(_) { _noteFlipGroup.remove(spark, true); }
		});
		FlxTween.num(1.0, 0.3, HALF + HALF2, {ease: FlxEase.quadOut}, function(v) {
			spark.scale.x = v;
			spark.scale.y = v;
		});
	}

	/** Cancela el drag con ESC: devuelve la nota a su sección original. */
	function _cancelNoteDrag():Void
	{
		_hideAllGhostNotes();

		if (_dragNote != null && _dragNoteSection >= 0)
		{
			_song.notes[_dragNoteSection].sectionNotes.push(_dragNote);
			undo(); // deshacer el saveUndoState del _startNoteDrag
		}

		_dragNote = null;
		_dragNoteSection = -1;
		_dragActive = false;
		_dragPending = null;
		_dragPendingSection = -1;
		_dragGhostCol = -1;

		updateGrid();
		showMessage('✖ Drag cancelado', ACCENT_WARNING);
	}

	// =========================================================================
	//  MULTI-SELECCIÓN — helpers
	// =========================================================================

	function _isSelected(note:Array<Dynamic>):Bool
	{
		for (s in _selectedNotes)
			if (s.note == note)
				return true;
		return false;
	}

	function _addToSelection(note:Array<Dynamic>, section:Int):Void
	{
		if (!_isSelected(note))
		{
			_selectedNotes.push({note: note, section: section});
			curSelectedNote = note; // sincronizar panel de nota con la última seleccionada
		}
	}

	function _toggleSelectNote(note:Array<Dynamic>, section:Int):Void
	{
		if (_isSelected(note))
		{
			_selectedNotes = _selectedNotes.filter(function(s) return s.note != note);
			curSelectedNote = _selectedNotes.length > 0 ? _selectedNotes[_selectedNotes.length - 1].note : null;
		}
		else
			_addToSelection(note, section);
		updateNoteUI();
		_notePositionsDirty = true;
	}

	function _clearSelection():Void
	{
		_selectedNotes = [];
		curSelectedNote = null; // deseleccionar también del panel de nota
		_notePositionsDirty = true;
	}

	/** Devuelve el step absoluto de una nota dado su índice de sección. */
	function _noteAbsStep(note:Array<Dynamic>, section:Int):Float
	{
		var sectionStartStep:Float = 0;
		for (i in 0...section)
			sectionStartStep += _song.notes[i].lengthInSteps;
		var noteStep = (note[0] - getSectionStartTime(section)) / Conductor.stepCrochet;
		return sectionStartStep + noteStep;
	}

	/** Devuelve la columna visual de una nota. */
	function _noteVisCol(note:Array<Dynamic>, section:Int):Int
	{
		var daNoteData:Int = Std.int(note[1]);
		var swapped = daNoteData;
		if (daNoteData < 8 && _song.notes[section].mustHitSection)
			swapped = (daNoteData < 4) ? daNoteData + 4 : daNoteData - 4;
		return dataColToVisualCol(swapped);
	}

	// =========================================================================
	//  BOX SELECT + MULTI-DRAG
	// =========================================================================

	/**
	 * Llamado cada frame desde update(). Gestiona:
	 *  - Box select (dibuja el rectángulo y finaliza al soltar)
	 *  - Multi-drag (mueve los ghosts y finaliza al soltar)
	 */
	function updateMultiDragAndSelBox():Void
	{
		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;

		// ── Box select ─────────────────────────────────────────────────────────
		if (_selBoxActive)
		{
			_updateSelBox(mx, my);

			if (FlxG.mouse.justReleased)
			{
				_finalizeBoxSelect(mx, my);
				_selBox.visible = false;
				_selBoxBorder.visible = false;
				_selBoxActive = false;
			}
			if (FlxG.keys.justPressed.ESCAPE)
			{
				_selBox.visible = false;
				_selBoxBorder.visible = false;
				_selBoxActive = false;
			}
			return;
		}

		// ── Multi-drag activo ──────────────────────────────────────────────────
		if (_multiDragActive)
		{
			_updateMultiDragGhosts(mx, my);

			if (FlxG.mouse.justReleased)
				_stopMultiDrag(mx, my);

			if (FlxG.keys.justPressed.ESCAPE)
				_cancelMultiDrag();
		}
	}

	/** Actualiza la posición y tamaño del rectángulo de selección. */
	function _updateSelBox(mx:Float, my:Float):Void
	{
		var mouseGridX = mx - gridBG.x;
		var mouseGridY = my - gridBG.y;
		var curStep = (mouseGridY / GRID_SIZE) + _gridWindowOffset;
		var curColF = mx - gridBG.x;

		var minStep = Math.min(_selBoxStartStep, curStep);
		var maxStep = Math.max(_selBoxStartStep, curStep);
		var minColF = Math.min(_selBoxStartCol, curColF);
		var maxColF = Math.max(_selBoxStartCol, curColF);

		var x1 = gridBG.x + minColF;
		var y1 = (100 - gridScrollY) + minStep * GRID_SIZE;
		var w = Math.max(2, maxColF - minColF);
		var h = Math.max(2, (maxStep - minStep) * GRID_SIZE);

		_selBox.x = x1;
		_selBox.y = y1;
		_selBox.setGraphicSize(Std.int(w), Std.int(h));
		_selBox.updateHitbox();
		_selBox.visible = true;

		// Borde: 4 píxeles de grosor simulado con un sprite ligeramente más grande y alpha
		_selBoxBorder.x = x1 - 1;
		_selBoxBorder.y = y1 - 1;
		_selBoxBorder.setGraphicSize(Std.int(w + 2), Std.int(h + 2));
		_selBoxBorder.updateHitbox();
		_selBoxBorder.visible = true;
	}

	/** Al soltar el box select: selecciona todas las notas dentro del rectángulo. */
	function _finalizeBoxSelect(mx:Float, my:Float):Void
	{
		var mouseGridY = my - gridBG.y;
		var curStep = (mouseGridY / GRID_SIZE) + _gridWindowOffset;
		var curColF = mx - gridBG.x;

		var minStep = Math.min(_selBoxStartStep, curStep);
		var maxStep = Math.max(_selBoxStartStep, curStep);
		var minCol = Math.min(_selBoxStartCol, curColF) / GRID_SIZE;
		var maxCol = Math.max(_selBoxStartCol, curColF) / GRID_SIZE;

		// Si el box es demasiado pequeño (solo click) → colocar nota en esa posición
		if (Math.abs(maxStep - minStep) < 0.1 && Math.abs(maxCol - minCol) < 0.1)
		{
			var mouseGridX = mx - gridBG.x;
			var mouseGridY = my - gridBG.y;
			var col = Std.int(Math.floor(mouseGridX / GRID_SIZE));
			if (col >= 0)
				addNoteAtWorldPosition(mouseGridY, col);
			return;
		}

		var accStep:Float = 0;
		for (i in 0..._song.notes.length)
		{
			for (nd in _song.notes[i].sectionNotes)
			{
				var absStep = accStep + (nd[0] - getSectionStartTime(i)) / Conductor.stepCrochet;
				var visCol = _noteVisCol(nd, i);
				if (absStep >= minStep && absStep <= maxStep && visCol >= minCol && visCol <= maxCol)
					_addToSelection(nd, i);
			}
			accStep += _song.notes[i].lengthInSteps;
		}

		_notePositionsDirty = true;
		if (_selectedNotes.length > 0)
			showMessage('${_selectedNotes.length} nota${_selectedNotes.length == 1 ? "" : "s"} seleccionada${_selectedNotes.length == 1 ? "" : "s"}',
				ACCENT_CYAN);
	}

	/** Inicia el multi-drag: elimina todas las notas seleccionadas y crea ghosts. */
	function _startMultiDrag(mx:Float, my:Float):Void
	{
		_multiDragActive = true;
		_multiDragOriginals = [];

		// Anchor: step y col bajo el cursor al iniciar
		var mouseGridX = mx - gridBG.x;
		var mouseGridY = my - gridBG.y;
		var snapSteps = (currentSnap / 16);
		var rawStep = (mouseGridY / GRID_SIZE) + _gridWindowOffset;
		_multiDragAnchorStep = Math.floor(rawStep / snapSteps) * snapSteps;
		_multiDragAnchorCol = Std.int(Math.floor(mouseGridX / GRID_SIZE));

		// Borrar todas las notas seleccionadas del chart y guardar info original
		saveUndoState("clear", null); // snapshot antes de empezar
		for (sel in _selectedNotes)
		{
			var absStep = _noteAbsStep(sel.note, sel.section);
			var visCol = _noteVisCol(sel.note, sel.section);
			_multiDragOriginals.push({
				note: sel.note,
				section: sel.section,
				absStep: absStep,
				visCol: visCol
			});
			_song.notes[sel.section].sectionNotes.remove(sel.note);
		}
		updateGrid();

		// Crear un ghost por cada nota
		_multiDragGhosts.clear();
		for (orig in _multiDragOriginals)
		{
			var g = new FlxSprite();
			g.makeGraphic(GRID_SIZE - 2, GRID_SIZE - 2, NOTE_COLORS[orig.visCol % 8]);
			g.alpha = 0.75;
			g.scrollFactor.set();
			g.cameras = [camGame];
			_multiDragGhosts.add(g);
		}
		_updateMultiDragGhosts(mx, my);
	}

	/** Actualiza posiciones de todos los ghosts del multi-drag. */
	function _updateMultiDragGhosts(mx:Float, my:Float):Void
	{
		var mouseGridX = mx - gridBG.x;
		var mouseGridY = my - gridBG.y;
		var snapSteps = (currentSnap / 16);
		var numCols = getGridColumns();

		var rawStep = (mouseGridY / GRID_SIZE) + _gridWindowOffset;
		var curStep = Math.floor(rawStep / snapSteps) * snapSteps;
		var curCol = Std.int(Math.floor(mouseGridX / GRID_SIZE));

		var deltaStep = curStep - _multiDragAnchorStep;
		var deltaCol = curCol - _multiDragAnchorCol;

		for (i in 0..._multiDragOriginals.length)
		{
			var orig = _multiDragOriginals[i];
			var ghost = _multiDragGhosts.members[i];
			if (ghost == null)
				continue;

			var newStep = Math.max(0, orig.absStep + deltaStep);
			var newCol = Std.int(Math.max(0, Math.min(numCols - 1, orig.visCol + deltaCol)));

			ghost.x = gridBG.x + newCol * GRID_SIZE + 1;
			ghost.y = (100 - gridScrollY) + newStep * GRID_SIZE + 1;

			// Animar color si la columna cambió
			var targetColor = NOTE_COLORS[newCol % 8];
			if (ghost.color != targetColor)
			{
				FlxTween.cancelTweensOf(ghost);
				FlxTween.color(ghost, 0.10, ghost.color, targetColor, {ease: FlxEase.quadOut});
			}
		}
	}

	/** Finaliza el multi-drag: reinserta todas las notas en sus nuevas posiciones. */
	function _stopMultiDrag(mx:Float, my:Float):Void
	{
		var mouseGridX = mx - gridBG.x;
		var mouseGridY = my - gridBG.y;
		var snapSteps = (currentSnap / 16);
		var numCols = getGridColumns();

		var rawStep = (mouseGridY / GRID_SIZE) + _gridWindowOffset;
		var curStep = Math.floor(rawStep / snapSteps) * snapSteps;
		var curCol = Std.int(Math.floor(mouseGridX / GRID_SIZE));

		var deltaStep = curStep - _multiDragAnchorStep;
		var deltaCol = curCol - _multiDragAnchorCol;

		var newSelection:Array<{note:Array<Dynamic>, section:Int}> = [];

		for (orig in _multiDragOriginals)
		{
			var newAbsStep = Math.max(0, orig.absStep + deltaStep);
			var newVisCol = Std.int(Math.max(0, Math.min(numCols - 1, orig.visCol + deltaCol)));

			// Encontrar sección destino para el step absoluto
			var accStep:Float = 0;
			var tgtSection:Int = 0;
			var stepInSection:Float = 0;
			for (i in 0..._song.notes.length)
			{
				if (newAbsStep < accStep + _song.notes[i].lengthInSteps)
				{
					tgtSection = i;
					stepInSection = newAbsStep - accStep;
					break;
				}
				accStep += _song.notes[i].lengthInSteps;
			}

			var newStrumTime = getSectionStartTime(tgtSection) + stepInSection * Conductor.stepCrochet;
			var reordered = visualColToDataCol(newVisCol);
			var actualData = reordered;
			if (reordered < 8 && _song.notes[tgtSection].mustHitSection)
				actualData = (reordered < 4) ? reordered + 4 : reordered - 4;

			var newNote:Array<Dynamic> = [newStrumTime, actualData, orig.note[2]];
			if (orig.note.length > 3 && orig.note[3] != null)
				newNote.push(orig.note[3]);

			_song.notes[tgtSection].sectionNotes.push(newNote);
			newSelection.push({note: newNote, section: tgtSection});
		}

		// Limpiar ghosts
		for (g in _multiDragGhosts.members)
			if (g != null)
			{
				FlxTween.cancelTweensOf(g);
			}
		_multiDragGhosts.clear();

		_multiDragActive = false;
		_multiDragOriginals = [];
		// BUGFIX: limpiar selección al soltar el drag para que los highlights
		// amarillos desaparezcan. La selección ya no es válida tras el reinsert
		// porque las notas son objetos nuevos con nuevas posiciones.
		_selectedNotes = [];
		curSelectedNote = newSelection.length > 0 ? newSelection[newSelection.length - 1].note : null;

		updateGrid();
		updateNoteUI();
		showMessage('${newSelection.length} nota${newSelection.length == 1 ? "" : "s"} movida${newSelection.length == 1 ? "" : "s"}', ACCENT_GREEN);
	}

	/** Cancela el multi-drag: devuelve todas las notas a su posición original. */
	function _cancelMultiDrag():Void
	{
		for (g in _multiDragGhosts.members)
			if (g != null)
			{
				FlxTween.cancelTweensOf(g);
			}
		_multiDragGhosts.clear();

		// Reinsertar notas originales
		for (orig in _multiDragOriginals)
			_song.notes[orig.section].sectionNotes.push(orig.note);

		_multiDragActive = false;
		_multiDragOriginals = [];
		_multiDragPending = false;

		updateGrid();
		showMessage('Drag cancelado', ACCENT_WARNING);
	}

	function _selectAllInSection():Void
	{
		_clearSelection();
		for (nd in _song.notes[curSection].sectionNotes)
			_addToSelection(nd, curSection);
		_notePositionsDirty = true;
		showMessage('${_selectedNotes.length} notas seleccionadas', ACCENT_CYAN);
	}

	function _deleteSelection():Void
	{
		if (_selectedNotes.length == 0)
			return;
		for (sel in _selectedNotes)
		{
			saveUndoState("delete", {section: sel.section, note: [sel.note[0], sel.note[1], sel.note[2]]});
			_song.notes[sel.section].sectionNotes.remove(sel.note);
		}
		_clearSelection();
		curSelectedNote = null;
		updateGrid();
		showMessage('Notas borradas', ACCENT_WARNING);
	}

	/** Devuelve la columna visual de una nota a partir de su rawData y sección. */
	function _noteVisColFromRaw(rawData:Int, sectionIndex:Int):Int
	{
		var swapped = rawData;
		if (rawData < 8 && sectionIndex < _song.notes.length && _song.notes[sectionIndex].mustHitSection)
			swapped = (rawData < 4) ? rawData + 4 : rawData - 4;
		return dataColToVisualCol(swapped);
	}

	// =========================================================================
	//  CHART OVERVIEW PREVIEW
	// =========================================================================

	/**
	 * Calcula el ancho del preview según el número de grupos de strums.
	 * 4 columnas por grupo × PRV_NOTE_W px + 4px para eventos = dinámico.
	 */
	function _prvWidth():Int
	{
		var numGroups = Std.int(Math.max(2, Math.ceil(getGridColumns() / 4)));
		return numGroups * 4 * PRV_NOTE_W + PRV_NOTE_W; // cols + events col
	}

	/**
	 * Calcula la altura disponible para el preview
	 * (desde y=100 hasta el borde inferior menos margen).
	 */
	function _prvHeight():Int
		return Std.int(FlxG.height - 100 - 20);

	/**
	 * Inicializa o reconstruye los sprites del panel de preview.
	 * Llamar después de buildGrid() cuando cambia el número de columnas.
	 */
	function initChartPreview():Void
	{
		var pw = _prvWidth();
		var ph = _prvHeight();

		// Limpiar sprites previos si existían
		for (s in [_prvBg, _prvSprite, _prvSections, _prvViewport, _prvPlayhead])
			if (s != null)
				remove(s, true);

		// Fondo
		_prvBg = new FlxSprite(PRV_X, 100);
		_prvBg.makeGraphic(pw + 4, ph, PRV_C_BG);
		_prvBg.scrollFactor.set();
		_prvBg.cameras = [camHUD];
		add(_prvBg);

		// Borde izquierdo de color
		var border = new FlxSprite(PRV_X, 100).makeGraphic(2, ph, PRV_C_BORDER);
		border.scrollFactor.set();
		border.cameras = [camHUD];
		add(border);

		// Notas (bitmap que se redibuja cuando hay cambios)
		_prvSprite = new FlxSprite(PRV_X + 2, 100);
		_prvSprite.makeGraphic(pw, ph, PRV_C_BG, true);
		_prvSprite.scrollFactor.set();
		_prvSprite.cameras = [camHUD];
		add(_prvSprite);

		// Líneas de sección
		_prvSections = new FlxSprite(PRV_X + 2, 100);
		_prvSections.makeGraphic(pw, ph, 0x00000000, true);
		_prvSections.scrollFactor.set();
		_prvSections.cameras = [camHUD];
		add(_prvSections);

		// Viewport (área visible)
		_prvViewport = new FlxSprite(PRV_X + 2, 100);
		_prvViewport.makeGraphic(pw, 10, PRV_C_VP, true);
		_prvViewport.scrollFactor.set();
		_prvViewport.cameras = [camHUD];
		add(_prvViewport);

		// Playhead
		_prvPlayhead = new FlxSprite(PRV_X + 2, 100);
		_prvPlayhead.makeGraphic(pw, 2, PRV_C_PH);
		_prvPlayhead.scrollFactor.set();
		_prvPlayhead.cameras = [camHUD];
		add(_prvPlayhead);

		_prvDirty = true;
	}

	/**
	 * Calcula la longitud total del song en ms.
	 */
	function _prvGetSongMs():Float
	{
		var total:Float = 0;
		for (i in 0..._song.notes.length)
			total += getSectionDuration(i);
		return Math.max(1, total);
	}

	/**
	 * Redibuja el bitmap de notas del preview.
	 * Solo se llama cuando _prvDirty es true.
	 */
	function _prvRedraw():Void
	{
		if (_prvSprite == null || _prvSections == null)
			return;

		_prvSongMs = _prvGetSongMs();
		var pw = _prvWidth();
		var ph = _prvHeight();

		// Limpiar
		flixel.util.FlxSpriteUtil.drawRect(_prvSprite, 0, 0, pw, ph, PRV_C_BG);
		flixel.util.FlxSpriteUtil.drawRect(_prvSections, 0, 0, pw, ph, 0x00000000);

		// Dibujar líneas de sección
		var accMs:Float = 0;
		for (i in 0..._song.notes.length)
		{
			var sy = Std.int((accMs / _prvSongMs) * ph);
			flixel.util.FlxSpriteUtil.drawRect(_prvSections, 0, sy, pw, 1, PRV_C_SECT);
			accMs += getSectionDuration(i);
		}

		// Dibujar notas
		var accMs2:Float = 0;
		var numGroups = Std.int(Math.max(2, Math.ceil(getGridColumns() / 4)));
		for (secNum in 0..._song.notes.length)
		{
			for (nd in _song.notes[secNum].sectionNotes)
			{
				var noteTime:Float = nd[0];
				var rawData:Int = Std.int(nd[1]);
				var daSus:Float = nd[2];
				var dir = rawData % 4;
				var group = Std.int(rawData / 4);

				// Columna X en el preview
				var noteX = Std.int(Math.min(group, numGroups - 1) * 4 * PRV_NOTE_W + dir * PRV_NOTE_W);

				// Y basada en el strumTime absoluto
				var noteY = Std.int((noteTime / _prvSongMs) * ph);

				// Color por dirección (igual que NOTE_COLORS)
				var col:Int = switch (dir)
				{
					case 0: 0xFFC24B99; // izquierda – morado
					case 1: 0xFF00FFFF; // abajo – cian
					case 2: 0xFF12FA05; // arriba – verde
					case 3: 0xFFF9393F; // derecha – rojo
					default: 0xFFAAAAAA;
				};

				// Nota cabeza
				flixel.util.FlxSpriteUtil.drawRect(_prvSprite, noteX, noteY, PRV_NOTE_W - 1, PRV_NOTE_H, col);

				// Sustain: línea más delgada y oscurecida
				if (daSus > 0)
				{
					var susH = Std.int((daSus / _prvSongMs) * ph);
					if (susH < 1)
						susH = 1;
					var susCol:Int = (col & 0xFFFFFF) | 0x88000000; // misma tinta pero 50% alpha
					flixel.util.FlxSpriteUtil.drawRect(_prvSprite, noteX + 1, noteY + PRV_NOTE_H, PRV_NOTE_W - 3, susH, col & 0x88FFFFFF);
				}
			}
			accMs2 += getSectionDuration(secNum);
		}

		// Columna de eventos (última columna)
		if (_song.events != null)
		{
			for (evt in _song.events)
			{
				var evtY = Std.int((evt.stepTime * Conductor.stepCrochet / _prvSongMs) * ph);
				flixel.util.FlxSpriteUtil.drawRect(_prvSprite, pw - PRV_NOTE_W, evtY, PRV_NOTE_W - 1, PRV_NOTE_H, 0xFFFFAA00);
			}
		}

		_prvDirty = false;
	}

	/**
	 * Actualiza la posición del viewport overlay y del playhead.
	 * Llamado cada frame.
	 */
	function updateChartPreview():Void
	{
		if (_prvSprite == null)
			return;

		var mx = FlxG.mouse.x;
		var my = FlxG.mouse.y;
		var ph = _prvHeight();
		var pw = _prvWidth();

		// ── Redibujar notas si hay cambios ───────────────────────────────────
		if (_prvDirty)
			_prvRedraw();

		// ── Viewport ─────────────────────────────────────────────────────────
		if (_prvViewport != null && _prvSongMs > 0)
		{
			var visibleMs = (FlxG.height / GRID_SIZE) * Conductor.stepCrochet;
			var vpH = Std.int(Math.max(4, (visibleMs / _prvSongMs) * ph));
			var vpY = Std.int((gridScrollY / (totalGridHeight / GRID_SIZE * Conductor.stepCrochet)) * ph);
			vpY = Std.int(Math.max(0, Math.min(ph - vpH, vpY)));

			_prvViewport.y = 100 + vpY;
			_prvViewport.setGraphicSize(pw, vpH);
			_prvViewport.updateHitbox();
		}

		// ── Playhead ─────────────────────────────────────────────────────────
		if (_prvPlayhead != null && _prvSongMs > 0 && FlxG.sound.music != null)
		{
			var songMs = FlxG.sound.music.time;
			var phY = Std.int((songMs / _prvSongMs) * ph);
			_prvPlayhead.y = 100 + Math.max(0, Math.min(ph - 2, phY));
		}

		// ── Click / drag en el preview → seek ────────────────────────────────
		var onPreview = mx >= PRV_X && mx <= PRV_X + pw + 4 && my >= 100 && my <= 100 + ph;

		if (onPreview && FlxG.mouse.justPressed)
			_prvDragging = true;
		if (FlxG.mouse.justReleased)
			_prvDragging = false;

		if (_prvDragging && _prvSongMs > 0)
		{
			var relY = Math.max(0, Math.min(ph - 1, my - 100));
			var seekMs = (relY / ph) * _prvSongMs;

			// Convertir ms a scroll pixels
			var seekStep = seekMs / Conductor.stepCrochet;
			var newScroll = seekStep * GRID_SIZE;
			newScroll = Math.max(0, Math.min(maxScroll, newScroll));
			gridScrollY = newScroll;
			_applyGridScroll(gridScrollY);
			_notePositionsDirty = true;

			// También sincronizar la música si está pausada
			if (FlxG.sound.music != null && !FlxG.sound.music.playing)
				FlxG.sound.music.time = seekMs;
		}
	}

	function isAnyPopupOpen():Bool
	{
		if (openSectionNav)
			return true;

		if (metaPopup != null && metaPopup.isOpen)
			return true;

		if (charIconRow != null && charIconRow.isAnyModalOpen())
			return true;

		if (eventsSidebar != null && eventsSidebar.isAnyPopupOpen())
			return true;

		// NOTE: toolsPanel is NOT a modal popup — it handles its own mouse
		// consumption via parent.clickConsumed in ToolsPanel.update().
		// Adding it here blocked Space, note placement keys (1-8) and all
		// other shortcuts whenever the panel was visible. Removed.

		return false;
	}

	function addNoteAtWorldPosition(worldY:Float, noteData:Int):Void
	{
		// worldY es relativo al origen de la textura del gridBG (que empieza en _gridWindowOffset).
		// Sumamos _gridWindowOffset para obtener el step global absoluto.
		var clickedStep = (worldY / GRID_SIZE) + _gridWindowOffset;

		// Snap
		var snapSteps = (currentSnap / 16);
		clickedStep = Math.floor(clickedStep / snapSteps) * snapSteps;

		// Encontrar en qué sección está
		var accumulatedSteps:Float = 0;
		var targetSection:Int = 0;
		var noteTimeInSection:Float = 0;

		for (i in 0..._song.notes.length)
		{
			var sectionSteps = _song.notes[i].lengthInSteps;

			if (clickedStep < accumulatedSteps + sectionSteps)
			{
				targetSection = i;
				noteTimeInSection = (clickedStep - accumulatedSteps) * Conductor.stepCrochet;
				break;
			}

			accumulatedSteps += sectionSteps;
		}

		// CRITICAL FIX: Deshacer el mapeo visual antes de guardar
		// Solo los primeros 2 grupos (col 0-7) hacen swap si mustHitSection
		// Paso 1: deshacer reordenamiento visual → columna en espacio de datos
		var reorderedData = visualColToDataCol(noteData);

		// Paso 2: deshacer mustHitSection swap
		var actualNoteData = reorderedData;
		if (reorderedData < 8 && _song.notes[targetSection].mustHitSection)
		{
			if (reorderedData < 4)
				actualNoteData = reorderedData + 4;
			else
				actualNoteData = reorderedData - 4;
		}
		// Para noteData ≥ 8 (grupos extra): no hay swap, actualNoteData = noteData

		// Calcular strumTime absoluto
		var noteStrumTime = getSectionStartTime(targetSection) + noteTimeInSection;

		// Verificar si ya existe
		var noteExists = false;
		for (i in _song.notes[targetSection].sectionNotes)
		{
			if (Math.abs(i[0] - noteStrumTime) < 5 && i[1] == actualNoteData)
			{
				saveUndoState("delete", {
					section: targetSection,
					note: [i[0], i[1], i[2]]
				});
				_song.notes[targetSection].sectionNotes.remove(i);
				noteExists = true;
				FlxG.sound.play(Paths.sound('menus/chartingSounds/undo'), 0.6);
				curSelectedNote = null; // ✨ Deseleccionar la nota eliminada
				break;
			}
		}

		// Si no existe, crear
		if (!noteExists)
		{
			// ✨ Obtener el sustain actual del stepper si hay uno
			var currentSus:Float = (stepperSusLength != null) ? stepperSusLength.value : 0;

			var newNote = [noteStrumTime, actualNoteData, currentSus];

			saveUndoState("add", {
				section: targetSection,
				note: newNote
			});
			_song.notes[targetSection].sectionNotes.push(newNote);

			// ✨ Seleccionar automáticamente la nota recién creada
			curSelectedNote = newNote;
			updateNoteUI();

			FlxG.sound.play(Paths.sound('menus/chartingSounds/openWindow'), 0.6);
		}
		updateGrid();
	}

	function deleteNoteAtPosition(worldY:Float, noteData:Int):Void
	{
		var clickedStep = (worldY / GRID_SIZE) + _gridWindowOffset;
		var snapSteps = (currentSnap / 16);
		clickedStep = Math.floor(clickedStep / snapSteps) * snapSteps;

		var accumulatedSteps:Float = 0;
		var targetSection:Int = 0;
		var noteTimeInSection:Float = 0;

		for (i in 0..._song.notes.length)
		{
			var sectionSteps = _song.notes[i].lengthInSteps;

			if (clickedStep < accumulatedSteps + sectionSteps)
			{
				targetSection = i;
				noteTimeInSection = (clickedStep - accumulatedSteps) * Conductor.stepCrochet;
				break;
			}

			accumulatedSteps += sectionSteps;
		}

		// CRITICAL FIX: Deshacer el mapeo visual antes de buscar la nota
		// Solo los primeros 2 grupos hacen swap si mustHitSection
		// Paso 1: deshacer reordenamiento visual → columna en espacio de datos
		var reorderedData = visualColToDataCol(noteData);

		// Paso 2: deshacer mustHitSection swap
		var actualNoteData = reorderedData;
		if (reorderedData < 8 && _song.notes[targetSection].mustHitSection)
		{
			if (reorderedData < 4)
				actualNoteData = reorderedData + 4;
			else
				actualNoteData = reorderedData - 4;
		}

		var noteStrumTime = getSectionStartTime(targetSection) + noteTimeInSection;

		for (i in _song.notes[targetSection].sectionNotes)
		{
			if (Math.abs(i[0] - noteStrumTime) < 5 && i[1] == actualNoteData)
			{
				saveUndoState("delete", {
					section: targetSection,
					note: [i[0], i[1], i[2]]
				});
				_song.notes[targetSection].sectionNotes.remove(i);
				FlxG.sound.play(Paths.sound('menus/chartingSounds/noteErase'), 0.6);
				updateGrid();
				return;
			}
		}
	}

	// ✨ NUEVA FUNCIÓN: Seleccionar una nota al hacer clic en ella
	function selectNoteAtPosition(worldY:Float, noteData:Int):Bool
	{
		var clickedStep = (worldY / GRID_SIZE) + _gridWindowOffset;
		var snapSteps = (currentSnap / 16);
		clickedStep = Math.floor(clickedStep / snapSteps) * snapSteps;

		var accumulatedSteps:Float = 0;
		var targetSection:Int = 0;
		var noteTimeInSection:Float = 0;

		for (i in 0..._song.notes.length)
		{
			var sectionSteps = _song.notes[i].lengthInSteps;

			if (clickedStep < accumulatedSteps + sectionSteps)
			{
				targetSection = i;
				noteTimeInSection = (clickedStep - accumulatedSteps) * Conductor.stepCrochet;
				break;
			}

			accumulatedSteps += sectionSteps;
		}

		// Deshacer el mapeo visual antes de buscar la nota
		// Paso 1: deshacer reordenamiento visual → columna en espacio de datos
		var reorderedData = visualColToDataCol(noteData);

		// Paso 2: deshacer mustHitSection swap
		var actualNoteData = reorderedData;
		if (reorderedData < 8 && _song.notes[targetSection].mustHitSection)
		{
			if (reorderedData < 4)
				actualNoteData = reorderedData + 4;
			else
				actualNoteData = reorderedData - 4;
		}

		var noteStrumTime = getSectionStartTime(targetSection) + noteTimeInSection;

		// Buscar la nota en esa posición
		for (i in _song.notes[targetSection].sectionNotes)
		{
			if (Math.abs(i[0] - noteStrumTime) < 5 && i[1] == actualNoteData)
			{
				// FIX: click izquierdo NUNCA borra — solo selecciona.
				// El borrado es EXCLUSIVO del click derecho (deleteNoteAtPosition).
				curSelectedNote = i;
				_addToSelection(i, targetSection);
				updateNoteUI();
				showMessage('Note selected (Sus: ${i[2]}ms)', ACCENT_CYAN);
				FlxG.sound.play(Paths.sound('menus/chartingSounds/ClickUp'), 0.6);
				return true;
			}
		}

		return false;
	}

	function handleKeyboardInput():Void
	{
		// ── Space / ESC / Enter SIEMPRE funcionan — van ANTES del guard de popups ──
		if (FlxG.keys.justPressed.ESCAPE)
		{
			if (_dragActive)
			{
				_cancelNoteDrag();
			}
			else if (openSectionNav)
			{
				_closeSectionNavigator();
			}
			else
			{
				_tryExitEditor(testChart);
			}
		}

		if (FlxG.keys.justPressed.SPACE)
		{
			if (FlxG.sound.music != null && FlxG.sound.music.playing)
			{
				FlxG.sound.music.pause();
				syncVocals();
			}
			else if (FlxG.sound.music != null)
			{
				// Reproducir desde la posición actual del grid/scroll, no desde el inicio de sección.
				// music.time ya fue sincronizado con el scroll (por rueda o por teclas W/S/A/D),
				// así que simplemente hacemos play() sin resetear el tiempo.
				FlxG.sound.music.play();
				syncVocals();
				showMessage('▶ Playing from ${formatTime(FlxG.sound.music.time / 1000)}', ACCENT_CYAN);
			}
		}

		if (FlxG.keys.justPressed.ENTER && FlxG.sound.music != null)
		{
			FlxG.sound.music.time = getSectionStartTime(curSection);
			FlxG.sound.music.play();
			syncVocals();
			showMessage('▶ Playing from Section ${curSection + 1}', ACCENT_CYAN);
		}

		// El resto de shortcuts sí se bloquean con popups
		if (isAnyPopupOpen() || openSectionNav)
			return;

		// ── All remaining shortcuts blocked while a text widget has focus ────
		// Typing numbers in a BPM/speed/sustain stepper must not accidentally
		// place notes or seek the timeline.
		var stageFocus = openfl.Lib.current.stage.focus;
		if (stageFocus != null && (stageFocus is openfl.text.TextField))
			return;

		// F5 - Test chart from current section (was bound to key 1, now correct)
		if (FlxG.keys.justPressed.F5)
			testChartFromSection();

		// NAVEGACIÓN
		if (FlxG.sound.music != null)
		{
			if (FlxG.keys.pressed.W || FlxG.keys.pressed.UP)
			{
				FlxG.sound.music.time -= 100 * FlxG.elapsed;
			}

			if (FlxG.keys.pressed.S || FlxG.keys.pressed.DOWN)
			{
				FlxG.sound.music.time += 100 * FlxG.elapsed;
			}

			if (FlxG.keys.justPressed.A || FlxG.keys.justPressed.LEFT)
			{
				FlxG.sound.music.time -= Conductor.stepCrochet;
			}

			if (FlxG.keys.justPressed.D || FlxG.keys.justPressed.RIGHT)
			{
				FlxG.sound.music.time += Conductor.stepCrochet;
			}
		} // end music != null

		// SECCIONES
		if (FlxG.keys.justPressed.PAGEUP)
		{
			changeSection(-1);
		}

		if (FlxG.keys.justPressed.PAGEDOWN)
		{
			changeSection(1);
		}
		/*
			// QUICK NOTE PLACEMENT (1-8) — deshabilitado: se hace con mouse
		 */

		// QUICK NOTE PLACEMENT via teclado (1-8)
		// Solo funciona cuando NO hay foco en un TextField (chequeado arriba)
		if (FlxG.keys.justPressed.ONE)
			placeQuickNote(0);
		if (FlxG.keys.justPressed.TWO)
			placeQuickNote(1);
		if (FlxG.keys.justPressed.THREE)
			placeQuickNote(2);
		if (FlxG.keys.justPressed.FOUR)
			placeQuickNote(3);
		if (FlxG.keys.justPressed.FIVE)
			placeQuickNote(4);
		if (FlxG.keys.justPressed.SIX)
			placeQuickNote(5);
		if (FlxG.keys.justPressed.SEVEN)
			placeQuickNote(6);
		if (FlxG.keys.justPressed.EIGHT)
			placeQuickNote(7);

		// COPY/PASTE/MIRROR
		if (FlxG.keys.pressed.CONTROL)
		{
			if (FlxG.keys.justPressed.C)
				copySection();
			if (FlxG.keys.justPressed.V)
				pasteSection();
			if (FlxG.keys.justPressed.X)
				cutSection();
			if (FlxG.keys.justPressed.S)
				saveChart();
			if (FlxG.keys.justPressed.Z)
				undo();
			if (FlxG.keys.justPressed.Y)
				redo();
			// Ctrl+A → seleccionar todas las notas visibles en la sección actual
			if (FlxG.keys.justPressed.A)
				_selectAllInSection();
			// Ctrl+D → deseleccionar todo
			if (FlxG.keys.justPressed.D)
				_clearSelection();
		}

		// Delete → borrar todas las notas seleccionadas
		if (FlxG.keys.justPressed.DELETE && _selectedNotes.length > 1)
			_deleteSelection();

		if (FlxG.keys.justPressed.N)
			mirrorSection();

		// Q / E — sustain resize si hay nota(s) seleccionada(s).
		// Shift+Q / Shift+E — cambiar snap (siempre disponible).
		var _shift = FlxG.keys.pressed.SHIFT;

		if (FlxG.keys.justPressed.E)
		{
			if (!_shift && (curSelectedNote != null || _selectedNotes.length > 0))
			{
				var step:Float = Conductor.stepCrochet * (16.0 / currentSnap);
				var targets:Array<Array<Dynamic>> = [];
				if (_selectedNotes.length > 0)
					for (sel in _selectedNotes) targets.push(sel.note);
				else if (curSelectedNote != null)
					targets.push(curSelectedNote);
				saveUndoState("sustain_resize", null);
				for (n in targets)
					n[2] = ((n[2] != null) ? n[2] : 0.0) + step;
				updateGrid();
				var plural = targets.length > 1 ? '${targets.length} notes' : '1 note';
				showMessage('\u2195 Sustain +1 subdiv ($plural)', ACCENT_CYAN);
			}
			else if (_shift)
			{
				currentSnap -= 16;
				if (currentSnap < 16) currentSnap = 64;
				showMessage('\u2699\uFE0F Snap: ${getSnapName(currentSnap)}', ACCENT_CYAN);
			}
		}

		if (FlxG.keys.justPressed.Q)
		{
			if (!_shift && (curSelectedNote != null || _selectedNotes.length > 0))
			{
				var step:Float = Conductor.stepCrochet * (16.0 / currentSnap);
				var targets:Array<Array<Dynamic>> = [];
				if (_selectedNotes.length > 0)
					for (sel in _selectedNotes) targets.push(sel.note);
				else if (curSelectedNote != null)
					targets.push(curSelectedNote);
				saveUndoState("sustain_resize", null);
				for (n in targets)
					n[2] = Math.max(0, ((n[2] != null) ? n[2] : 0.0) - step);
				updateGrid();
				var plural = targets.length > 1 ? '${targets.length} notes' : '1 note';
				showMessage('\u2195 Sustain -1 subdiv ($plural)', ACCENT_CYAN);
			}
			else if (_shift)
			{
				currentSnap += 16;
				if (currentSnap > 64) currentSnap = 16;
				showMessage('\u2699\uFE0F Snap: ${getSnapName(currentSnap)}', ACCENT_CYAN);
			}
		}

		// TOGGLE HITSOUNDS
		if (FlxG.keys.justPressed.T)
		{
			hitsoundsEnabled = !hitsoundsEnabled;
			showMessage(hitsoundsEnabled ? '🔊 Hitsounds ON' : '🔇 Hitsounds OFF', ACCENT_CYAN);
		}

		// TOGGLE METRONOME
		if (FlxG.keys.justPressed.M)
		{
			metronomeEnabled = !metronomeEnabled;
			showMessage(metronomeEnabled ? '🎵 Metronome ON' : '🔇 Metronome OFF', ACCENT_CYAN);
		}

		// Nota: el Waveform ahora se activa con el botón 🌊 en la toolbar (no con W)
	}

	function handlePlaybackButtons():Void
	{
		// Play button
		if (FlxG.mouse.overlaps(playBtn, camHUD) && FlxG.mouse.justPressed)
		{
			if (FlxG.sound.music != null && !FlxG.sound.music.playing)
			{
				// ✨ Reproducir desde la sección actual basado en el scroll del grid
				FlxG.sound.music.time = getSectionStartTime(curSection);
				FlxG.sound.music.play();
				syncVocals(); // ✨ SINCRONIZAR VOCALES
				showMessage('▶ Playing from Section ${curSection + 1}', ACCENT_CYAN);
			}
		}

		// Pause button
		if (FlxG.mouse.overlaps(pauseBtn, camHUD) && FlxG.mouse.justPressed)
		{
			if (FlxG.sound.music != null && FlxG.sound.music.playing)
			{
				FlxG.sound.music.pause();
				syncVocals(); // ✨ SINCRONIZAR VOCALES
			}
		}

		// Stop button
		if (FlxG.mouse.overlaps(stopBtn, camHUD) && FlxG.mouse.justPressed)
		{
			if (FlxG.sound.music != null)
			{
				FlxG.sound.music.stop();
				FlxG.sound.music.time = 0;
			}
			syncVocals(); // ✨ SINCRONIZAR VOCALES
		}

		// Test button - Go to PlayState to test the chart from current section
		if (FlxG.mouse.overlaps(testBtn, camHUD) && FlxG.mouse.justPressed)
		{
			testChartFromSection();
		}

		// ===== NUEVOS BOTONES CLICKEABLES EN TOOLBAR =====

		// Click en BPM → abrir diálogo de input en el Song tab
		if (bpmText != null && FlxG.mouse.justPressed && FlxG.mouse.overlaps(bpmText, camHUD))
		{
			// Cambiar al Song tab para editar el BPM
			UI_box.selected_tab_id = 'Song';
			showMessage('✏️ Edit the BPM in the tab Song', ACCENT_WARNING);
		}

		// Click en Section → abrir diálogo de navegación
		if (sectionText != null && FlxG.mouse.justPressed && FlxG.mouse.overlaps(sectionText, camHUD))
		{
			openSectionNavigator();
		}

		// Click en botón Meta → toggle del popup
		if (metaBtn != null && FlxG.mouse.justPressed && FlxG.mouse.overlaps(metaBtn, camHUD))
		{
			if (metaPopup != null)
			{
				if (metaPopup.isOpen)
					metaPopup.close();
				else
					metaPopup.open();
			}
		}

		// 🌊 Click en botón Waveform → toggle
		if (waveformBtn != null && FlxG.mouse.justPressed && FlxG.mouse.overlaps(waveformBtn, camHUD))
		{
			_toggleWaveform();
		}

		// Tools button → toggle panel
		if (toolsPanel != null && FlxG.mouse.justPressed)
		{
			// El botón de Tools está en x=648, y=10, w=58, h=22
			var mx = FlxG.mouse.x;
			var my = FlxG.mouse.y;
			if (mx >= 648 && mx <= 706 && my >= 10 && my <= 32)
				toolsPanel.toggle();
		}
	}

	// Abre un diálogo rápido para saltar a una sección específica
	function openSectionNavigator():Void
	{
		if (openSectionNav)
			return; // evitar doble apertura
		openSectionNav = true;
		_sectionNavElements = [];

		// Overlay oscuro — click fuera del panel lo cierra
		var overlay = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, 0x88000000);
		overlay.scrollFactor.set();
		overlay.cameras = [camHUD];

		var panelW = 260;
		var panelH = 130;
		var cx = FlxG.width / 2 - panelW / 2;
		var cy = FlxG.height / 2 - panelH / 2;

		var panel = new FlxSprite(cx, cy).makeGraphic(panelW, panelH, 0xFF1A1A33);
		panel.scrollFactor.set();
		panel.cameras = [camHUD];

		var label = new FlxText(cx + 10, cy + 12, panelW - 20, 'Go to section (1-${_song.notes.length}):', 11);
		label.setFormat(Paths.font("vcr.ttf"), 11, 0xFFAAAAAA, CENTER);
		label.scrollFactor.set();
		label.cameras = [camHUD];

		var input = new CoolInputText(cx + panelW / 2 - 50, cy + 38, 100, '${curSection + 1}', 14);
		input.scrollFactor.set();
		input.cameras = [camHUD];

		var confirmBtn:FlxButton = null;
		var cancelBtn:FlxButton = null;

		confirmBtn = new FlxButton(cx + panelW / 2 - 55, cy + panelH - 38, "Go", function()
		{
			var target = Std.parseInt(input.text);
			if (target != null && target >= 1 && target <= _song.notes.length)
			{
				changeSection(target - 1 - curSection);
				showMessage('📍 Navigating to section ${target}', ACCENT_CYAN);
			}
			_closeSectionNavigator();
		});
		confirmBtn.scrollFactor.set();
		confirmBtn.cameras = [camHUD];

		cancelBtn = new FlxButton(cx + panelW / 2 + 5, cy + panelH - 38, "Cancel", function()
		{
			_closeSectionNavigator();
		});
		cancelBtn.scrollFactor.set();
		cancelBtn.cameras = [camHUD];

		for (el in [overlay, panel, label, input, confirmBtn, cancelBtn])
		{
			_sectionNavElements.push(el);
			add(el);
		}
	}

	/** Cierra el section navigator y limpia todos sus sprites. */
	function _closeSectionNavigator():Void
	{
		for (el in _sectionNavElements)
			remove(el, true);
		_sectionNavElements = [];
		openSectionNav = false;
		// Quitar foco del text input para que los atajos de teclado vuelvan a funcionar
		if (openfl.Lib.current.stage.focus != null)
			openfl.Lib.current.stage.focus = null;
	}

	function placeQuickNote(noteData:Int):Void
	{
		var strumTime = FlxG.sound.music.time;
		strumTime = Math.floor(strumTime / (Conductor.stepCrochet / (currentSnap / 16))) * (Conductor.stepCrochet / (currentSnap / 16));

		_song.notes[curSection].sectionNotes.push([strumTime, noteData, 0]);

		if (hitsoundsEnabled)
			FlxG.sound.play(Paths.sound('menus/scrollMenu'), 0.4);

		updateGrid();
		showMessage('➕ Note placed', ACCENT_SUCCESS);
	}

	function updateGrid():Void
	{
		// Invalidar caches al reconstruir el grid
		_sectionTimeCacheDirty = true;
		_notePositionsDirty = true;
		_susHeightCache = new Map();

		// Destruir sprites anteriores antes de vaciar los grupos para evitar memory leaks.
		// .clear() sólo vacía el array — sin destroy() los Note quedan en heap sin GC.
		for (n in curRenderedNotes)
			if (n != null) n.destroy();
		curRenderedNotes.clear();

		for (s in curRenderedSustains)
			if (s != null) s.destroy();
		curRenderedSustains.clear();

		if (_curSusTails != null)
		{
			for (t in _curSusTails)
				if (t != null) t.destroy();
			_curSusTails.clear();
		}

		if (_selHighlights != null)
		{
			for (h in _selHighlights)
				if (h != null) h.destroy();
			_selHighlights.clear();
		}

		if (curRenderedTypeLabels != null)
		{
			for (lbl in curRenderedTypeLabels)
				if (lbl != null) lbl.destroy();
			curRenderedTypeLabels.clear();
		}
		_prvDirty = true; // chart ha cambiado → redibujar preview

		var currentStep:Float = 0;

		for (secNum in 0..._song.notes.length)
		{
			var section = _song.notes[secNum];
			var sectionY = currentStep * GRID_SIZE;

			for (noteData in section.sectionNotes)
			{
				var daStrumTime:Float = noteData[0];
				var daNoteData:Int = Std.int(noteData[1]);
				var daSus:Float = noteData[2];

				var noteStep = (daStrumTime - getSectionStartTime(secNum)) / Conductor.stepCrochet;

				// === REMAPEAR COLUMNA VISUAL ===
				// Solo los primeros 2 grupos (col 0-7) hacen swap si mustHitSection
				// Los grupos extra (col ≥8) nunca hacen swap
				// Paso 1: mustHitSection swap (solo grupos 0 y 1 de datos)
				var swappedCol = daNoteData;
				if (daNoteData < 8 && section.mustHitSection)
				{
					if (daNoteData < 4)
						swappedCol = daNoteData + 4;
					else
						swappedCol = daNoteData - 4;
				}
				// Paso 2: reordenamiento visual por personaje
				var visualColumn = dataColToVisualCol(swappedCol);

				// Para noteData ≥ 8 (grupos extra): visualColumn = daNoteData sin cambios

				var note:Note = new Note(daStrumTime, visualColumn % 4);
				note.setGraphicSize(GRID_SIZE, GRID_SIZE);
				note.updateHitbox();
				note.x = gridBG.x + (GRID_SIZE * visualColumn);
				note.y = (100 - gridScrollY) + sectionY + (noteStep * GRID_SIZE);

				// Color base — note.color sobre un gráfico blanco funciona correctamente
				var baseColor = NOTE_COLORS[visualColumn % 8];

				// FIX noteRGB: si la nota tiene un shader activo (colorAuto / colorDirections /
				// NoteRGBPaletteShader) NO aplicar el tint de NOTE_COLORS encima — el shader
				// ya provee el color correcto y multiplicarlo distorsiona el resultado.
				var hasShader:Bool = (note.shader != null);

				// ✨ Aplicar efecto pulsante si es la nota seleccionada
				if (curSelectedNote != null && noteData == curSelectedNote)
				{
					var pulseAmount = 0.4 + (Math.sin(selectedNotePulse) * 0.5 + 0.5) * 0.6;
					if (hasShader)
					{
						// Con shader: pulso de alpha para no interferir con el RGB del shader
						note.color = 0xFFFFFFFF;
						note.alpha  = pulseAmount;
					}
					else
					{
						var r = Std.int((baseColor >> 16 & 0xFF) * pulseAmount);
						var g = Std.int((baseColor >> 8 & 0xFF) * pulseAmount);
						var b = Std.int((baseColor & 0xFF) * pulseAmount);
						note.color = (0xFF << 24) | (r << 16) | (g << 8) | b;
						note.alpha  = 1.0;
					}
				}
				else
				{
					note.alpha = 1.0;
					note.color = hasShader ? 0xFFFFFFFF : baseColor;
				}

				note.scrollFactor.set();

				curRenderedNotes.add(note);

				// NoteType: etiqueta sobre la nota
				var _ntLabel:String = (noteData.length > 3 && noteData[3] != null) ? Std.string(noteData[3]) : '';
				if (_ntLabel != '' && _ntLabel != 'normal' && curRenderedTypeLabels != null)
				{
					var tl = new FlxText(note.x, note.y - 8, GRID_SIZE, _ntLabel, 7);
					tl.color = 0xFFFFFFFF;
					tl.borderStyle = OUTLINE;
					tl.borderColor = 0xFF000000;
					tl.borderSize = 1;
					tl.scrollFactor.set();
					curRenderedTypeLabels.add(tl);
				}

				// Sustain
				if (daSus > 0)
				{
					var susHeight = (daSus / Conductor.stepCrochet) * GRID_SIZE;

					if (susHeight < 2)
						susHeight = 2;

					// Mismo enfoque que NoteManager: cadena prevNote para que las animaciones
					// (hold / holdend) se asignen igual que en gameplay.
					//   body (prevNote=null→self): setupSustainNote juega hold en sí mismo
					//   tail (prevNote=body):      setupSustainNote: body→hold, tail→holdend
					var _prevSong = PlayState.SONG;
					if (PlayState.SONG == null)
						PlayState.SONG = _song;

					var _susBody = new Note(daStrumTime, visualColumn % 4, null, true);
					var _susTail = new Note(daStrumTime, visualColumn % 4, _susBody, true);

					PlayState.SONG = _prevSong;

					// Sustain fino: 28% del ancho de celda, arranca desde el centro de la nota.
					var SUS_W:Float = GRID_SIZE * 0.28;
					var susStartY:Float = note.y + GRID_SIZE * 0.5;

					if (_susBody.frameHeight > 0)
					{
						_susBody.scale.y = susHeight / _susBody.frameHeight;
						if (_susBody.frameWidth > 0)
							_susBody.scale.x = SUS_W / _susBody.frameWidth;
						_susBody.updateHitbox();
						_susBody.offset.x += _susBody.noteOffsetX;
						_susBody.offset.y += _susBody.noteOffsetY;
					}
					_susBody.x = note.x + (GRID_SIZE - _susBody.width) / 2 + 4;
					_susBody.y = susStartY;
					_susBody.scrollFactor.set();
					_susBody.cameras = [camGame];
					curRenderedSustains.add(_susBody);

					if (_susTail.frameWidth > 0)
					{
						_susTail.scale.x = SUS_W / _susTail.frameWidth;
						_susTail.updateHitbox();
						_susTail.offset.x += _susTail.noteOffsetX;
						_susTail.offset.y += _susTail.noteOffsetY;
					}
					_susTail.x = note.x + (GRID_SIZE - _susTail.width) / 2 + 4;
					_susTail.y = susStartY + susHeight;
					_susTail.scrollFactor.set();
					_susTail.cameras = [camGame];
					_curSusTails.add(_susTail);
				}
			}

			currentStep += section.lengthInSteps;
		}
		updateNotePositions();
	}

	function getSectionStartTime(sectionNum:Int):Float
	{
		var time:Float = 0;

		for (i in 0...sectionNum)
		{
			var section = _song.notes[i];
			var bpm = section.changeBPM ? section.bpm : _song.bpm;
			var beats = section.lengthInSteps / 4;
			time += (beats * 60 / bpm) * 1000;
		}

		return time;
	}

	function getYfromStrum(strumTime:Float):Float
	{
		return FlxMath.remapToRange(strumTime, 0, 16 * Conductor.stepCrochet, gridBG.y, gridBG.y + gridBG.height);
	}

	function getStrumTime(yPos:Float):Float
	{
		return FlxMath.remapToRange(yPos, gridBG.y, gridBG.y + gridBG.height, 0, 16 * Conductor.stepCrochet);
	}

	// Cache de alturas de sustain para evitar makeGraphic cada frame
	var _susHeightCache:Map<Int, Int> = new Map();

	// ✨ Actualizar posiciones de notas cuando el grid se mueve (con dirty flag)
	function updateNotePositions():Void
	{
		// Solo recalcular si el grid se movió o hubo una edición
		if (!_notePositionsDirty && Math.abs(gridBG.y - _lastGridY) < 0.5)
			return;

		_notePositionsDirty = false;
		_lastGridY = gridBG.y;

		// Devolver highlights al pool antes de reconstruir (evita destroy + realloc).
		if (_selHighlights != null)
		{
			for (h in _selHighlights)
				if (h != null) _hlPool.push(h);
			_selHighlights.clear();
		}

		var currentStep:Float = 0;
		var noteIndex = 0;
		var susIndex = 0;

		for (secNum in 0..._song.notes.length)
		{
			var section = _song.notes[secNum];
			var sectionY = currentStep * GRID_SIZE;

			for (noteData in section.sectionNotes)
			{
				if (noteIndex >= curRenderedNotes.length)
					break;

				var note = curRenderedNotes.members[noteIndex];
				if (note == null)
				{
					noteIndex++;
					continue;
				}

				var daStrumTime:Float = noteData[0];
				var daNoteData:Int = Std.int(noteData[1]);
				var daSus:Float = noteData[2];
				var noteStep = (daStrumTime - getSectionStartTimeFast(secNum)) / Conductor.stepCrochet;

				// REMAPEAR POSICIÓN VISUAL (igual que en updateGrid)
				var swappedCol = daNoteData;
				if (daNoteData < 8 && section.mustHitSection)
				{
					if (daNoteData < 4)
						swappedCol = daNoteData + 4;
					else if (daNoteData < 8)
						swappedCol = daNoteData - 4;
				}
				var visualColumn = dataColToVisualCol(swappedCol);

				// ACTUALIZAR posición X e Y
				note.x = gridBG.x + (GRID_SIZE * visualColumn);
				note.y = (100 - gridScrollY) + sectionY + (noteStep * GRID_SIZE);

				// Efecto visual: color normal siempre. El highlight se hace con _selHighlights.
				var baseColor = NOTE_COLORS[visualColumn % 8];
				// FIX noteRGB: si la nota tiene shader activo, no aplicar tint de NOTE_COLORS.
				var hasShader:Bool = (note.shader != null);
				if (curSelectedNote != null && noteData == curSelectedNote)
				{
					// Nota primaria seleccionada: pulso de brillo
					var pulseAmount = 0.4 + (Math.sin(selectedNotePulse) * 0.5 + 0.5) * 0.6;
					if (hasShader)
					{
						note.color = 0xFFFFFFFF;
						note.alpha  = pulseAmount;
					}
					else
					{
						var r = Std.int((baseColor >> 16 & 0xFF) * pulseAmount);
						var g = Std.int((baseColor >> 8 & 0xFF) * pulseAmount);
						var b = Std.int((baseColor & 0xFF) * pulseAmount);
						note.color = (0xFF << 24) | (r << 16) | (g << 8) | b;
						note.alpha  = 1.0;
					}
				}
				else
				{
					note.alpha = 1.0;
					note.color = hasShader ? 0xFFFFFFFF : baseColor;
				}

				// Rectángulo amarillo detrás de notas seleccionadas.
				// FIX: se reutilizan sprites del pool _hlPool para evitar makeGraphic()
				// (nueva BitmapData en heap) en cada frame por cada nota seleccionada.
				if (_selHighlights != null && (_isSelected(noteData) || (curSelectedNote != null && noteData == curSelectedNote)))
				{
					var hlColor = (noteData == curSelectedNote) ? 0xCCFFFFFF : 0x99FFEE00;
					var hl:FlxSprite;
					if (_hlPool.length > 0)
					{
						hl = _hlPool.pop();
						// Solo redibujar si el color cambió (evita BitmapData innecesaria)
						if (hl.color != hlColor)
							hl.makeGraphic(GRID_SIZE, GRID_SIZE, hlColor);
					}
					else
					{
						hl = new FlxSprite();
						hl.makeGraphic(GRID_SIZE, GRID_SIZE, hlColor);
						hl.scrollFactor.set();
						hl.cameras = [camGame];
					}
					hl.x = note.x;
					hl.y = note.y;
					hl.visible = true;
					_selHighlights.add(hl);
				}

				// Actualizar sustain body + tail — setGraphicSize en vez de makeGraphic
				if (daSus > 0 && susIndex < curRenderedSustains.length)
				{
					var sus = curRenderedSustains.members[susIndex];
					var tail = (_curSusTails != null && susIndex < _curSusTails.length) ? _curSusTails.members[susIndex] : null;
					var susHeight:Int = Std.int(Math.max(5, (daSus / Conductor.stepCrochet) * GRID_SIZE));

					// updateGrid ya establece scale.y y offsets correctamente vía prevNote chain.
					// Aquí solo actualizamos x/y (scroll) y rescalamos body si la duración cambió.
					var susNote = Std.isOfType(sus, Note) ? cast(sus, Note) : null;

					if (sus != null)
					{
						var cachedH:Null<Int> = _susHeightCache.get(susIndex);
						if (cachedH == null || cachedH != susHeight)
						{
							if (susNote != null && susNote.frameHeight > 0)
							{
								susNote.scale.y = susHeight / susNote.frameHeight;
								susNote.updateHitbox();
								susNote.offset.x += susNote.noteOffsetX;
								susNote.offset.y += susNote.noteOffsetY;
							}
							_susHeightCache.set(susIndex, susHeight);
						}
						// Posición: misma lógica que updateGrid (centro de nota, ancho fino)
						var susStartY:Float = note.y + GRID_SIZE * 0.5;
						sus.x = note.x + (GRID_SIZE - sus.width) / 2 + 4;
						sus.y = susStartY;
					}
					if (tail != null)
					{
						var susStartY:Float = note.y + GRID_SIZE * 0.5;
						tail.x = note.x + (GRID_SIZE - tail.width) / 2 + 4;
						tail.y = susStartY + susHeight;
					}
					susIndex++;
				}

				noteIndex++;
			}

			currentStep += section.lengthInSteps;
		}
	}

	function cullNotes():Void
	{
		var minY = 0;
		var maxY = FlxG.height;
		var margin = 200;

		for (note in curRenderedNotes)
		{
			if (note == null) continue;
			note.visible = (note.y + note.height >= minY - margin && note.y <= maxY + margin);
		}

		// FIX: usar note.y + note.height para sustains altos que empiezan fuera
		// pero llegan a la pantalla (body puede ser muy alto).
		for (sus in curRenderedSustains)
		{
			if (sus == null) continue;
			sus.visible = (sus.y + sus.height >= minY - margin && sus.y <= maxY + margin);
		}

		// FIX: _curSusTails no se culleaba nunca — misma lógica que sustain body.
		if (_curSusTails != null)
		{
			for (tail in _curSusTails)
			{
				if (tail == null) continue;
				tail.visible = (tail.y + tail.height >= minY - margin && tail.y <= maxY + margin);
			}
		}
	}

	function changeSection(change:Int = 0):Void
	{
		curSection += change;

		// Safety checks mejorados
		if (_song.notes.length == 0)
		{
			trace('[ChartingState] ERROR: Cannot change section, notes array is empty!');
			return;
		}

		if (curSection < 0)
			curSection = 0;
		if (curSection >= _song.notes.length)
			curSection = _song.notes.length - 1;

		// En lugar de cambiar vista, hacer scroll al section
		var targetY:Float = 0;
		for (i in 0...curSection)
		{
			targetY += _song.notes[i].lengthInSteps * GRID_SIZE;
		}

		gridScrollY = targetY;
		if (gridScrollY > maxScroll)
			gridScrollY = maxScroll;

		_applyGridScroll(gridScrollY);

		// Mover música al inicio de la sección
		if (FlxG.sound.music != null)
		{
			FlxG.sound.music.time = getSectionStartTime(curSection);
			// Reset hitsound map al hacer seek
			_hitsoundFiredNotes = new Map();
			_lastHitsoundTime = -999;
		}

		updateSectionUI();

		// ✨ SINCRONIZAR VOCALES cuando cambias de sección
		syncVocals();
	}

	function addSection(lengthInSteps:Int = 16):Void
	{
		var sec:SwagSection = {
			lengthInSteps: lengthInSteps,
			bpm: _song.bpm,
			stage: 'stage_week1',
			changeBPM: false,
			mustHitSection: true,
			sectionNotes: [],
			typeOfSection: 0,
			altAnim: false,
			gfSing: false
		};

		_song.notes.push(sec);
		showMessage("➕ Section added", ACCENT_SUCCESS);
	}

	function updateSectionUI():Void
	{
		// Safety check: asegurar que curSection es válido
		if (curSection < 0 || curSection >= _song.notes.length)
		{
			trace('[ChartingState] WARNING: Invalid curSection ($curSection), clamping to valid range');
			curSection = FlxMath.maxInt(0, FlxMath.minInt(curSection, _song.notes.length - 1));
		}

		if (check_mustHitSection != null)
			check_mustHitSection.checked = _song.notes[curSection].mustHitSection;

		if (check_altAnim != null)
			check_altAnim.checked = _song.notes[curSection].altAnim;

		if (check_changeBPM != null)
			check_changeBPM.checked = _song.notes[curSection].changeBPM;

		if (stepperLength != null)
			stepperLength.value = _song.notes[curSection].lengthInSteps;
	}

	function updateNoteUI():Void
	{
		if (stepperSusLength != null && curSelectedNote != null)
		{
			stepperSusLength.value = curSelectedNote[2];
		}

		// Sync noteType dropdown
		if (noteTypeDropdown != null)
		{
			var typeName:String = (curSelectedNote != null && curSelectedNote.length > 3 && curSelectedNote[3] != null) ? Std.string(curSelectedNote[3]) : 'normal';
			var idx = _noteTypesList.indexOf(typeName);
			if (idx < 0)
				idx = 0;
			noteTypeDropdown.selectedLabel = '$idx: ${_noteTypesList[idx]}';
		}
	}



	function copySection():Void
	{
		clipboard = [];
		for (note in _song.notes[curSection].sectionNotes)
		{
			clipboard.push([note[0], note[1], note[2], note.length > 3 ? note[3] : null]);
		}

		showMessage('📋 Copied ${clipboard.length} notes', ACCENT_SUCCESS);
		FlxG.sound.play(Paths.sound('menus/chartingSounds/noteLay'), 0.6);
	}

	function pasteSection():Void
	{
		if (clipboard.length == 0)
		{
			showMessage('X Clipboard is empty!', ACCENT_ERROR);
			return;
		}

		saveUndoState("paste", {
			oldNotes: _song.notes[curSection].sectionNotes.copy(),
			newNotes: clipboard.copy()
		});

		_song.notes[curSection].sectionNotes = [];
		for (note in clipboard)
		{
			_song.notes[curSection].sectionNotes.push([note[0], note[1], note[2]]);
		}

		updateGrid();
		showMessage('📌 Pasted ${clipboard.length} notes', ACCENT_SUCCESS);
		FlxG.sound.play(Paths.sound('menus/chartingSounds/stretchSNAP_UI'), 0.6);
	}

	function cutSection():Void
	{
		copySection();
		_song.notes[curSection].sectionNotes = [];
		updateGrid();
		showMessage('✂️ Cut section', ACCENT_WARNING);
	}

	function mirrorSection():Void
	{
		for (note in _song.notes[curSection].sectionNotes)
		{
			var noteData:Int = note[1];

			// Swap player <-> opponent solo en los primeros 2 grupos (0-7)
			if (noteData < 8)
			{
				if (noteData < 4)
					note[1] = noteData + 4;
				else
					note[1] = noteData - 4;
			}
			// Grupos extra (≥8): no se hace swap
		}

		updateGrid();
		showMessage('🔄 Section mirrored (P1 ↔ P2)', ACCENT_CYAN);
		FlxG.sound.play(Paths.sound('menus/chartingSounds/stretchSNAP_UI'), 0.6);
		_markUnsaved();
	}

	function mirrorHorizontal():Void
	{
		for (note in _song.notes[curSection].sectionNotes)
		{
			var noteData:Int = note[1];
			var group = Math.floor(noteData / 4);
			var column:Int = noteData % 4;

			// Invertir columnas dentro de su grupo: 0<->3, 1<->2
			var newColumn:Int = switch (column)
			{
				case 0: 3;
				case 1: 2;
				case 2: 1;
				case 3: 0;
				default: column;
			};

			note[1] = (group * 4) + newColumn;
		}

		updateGrid();
		showMessage('↔️ Section flipped horizontally', ACCENT_CYAN);
		_markUnsaved();
	}

	function saveUndoState(actionType:String, data:Dynamic):Void
	{
		if (undoStack.length >= MAX_UNDO_STEPS)
			undoStack.shift();

		// BUG FIX: usar data.section si está disponible.
		// Antes siempre se guardaba curSection, por lo que notas añadidas/borradas en
		// secciones distintas a la visible se restauraban en la sección equivocada al deshacer.
		var sec:Int = (data != null && Reflect.hasField(data, 'section') && data.section != null)
			? Std.int(data.section)
			: curSection;

		undoStack.push({
			type: actionType,
			section: sec,
			data: data
		});

		redoStack = [];
		_markUnsaved();
	}

	function undo():Void
	{
		if (undoStack.length == 0)
		{
			showMessage('X Nothing to undo!', ACCENT_WARNING);
			return;
		}

		var action = undoStack.pop();
		redoStack.push(action);

		switch (action.type)
		{
			case "add":
				var note = action.data.note;
				_song.notes[action.section].sectionNotes.remove(note);

			case "delete":
				var note = action.data.note;
				_song.notes[action.section].sectionNotes.push(note);

			case "paste":
				_song.notes[curSection].sectionNotes = action.data.oldNotes.copy();
		}

		updateGrid();
		showMessage('↶ Undo', ACCENT_CYAN);
		FlxG.sound.play(Paths.sound('menus/chartingSounds/undo'), 0.6);
	}

	function redo():Void
	{
		if (redoStack.length == 0)
		{
			showMessage('X Nothing to redo!', ACCENT_WARNING);
			return;
		}

		var action = redoStack.pop();
		undoStack.push(action);

		switch (action.type)
		{
			case "add":
				var note = action.data.note;
				_song.notes[action.section].sectionNotes.push(note);

			case "delete":
				var note = action.data.note;
				_song.notes[action.section].sectionNotes.remove(note);

			case "paste":
				_song.notes[curSection].sectionNotes = action.data.newNotes.copy();
		}

		updateGrid();
		showMessage('↷ Redo', ACCENT_CYAN);
		FlxG.sound.play(Paths.sound('menus/chartingSounds/openWindow'), 0.6);
	}

	function calculateNPS():Float
	{
		if (_song.notes.length == 0)
			return 0;

		var totalNotes = countTotalNotes();
		var totalSeconds = getSectionStartTime(_song.notes.length) / 1000;

		if (totalSeconds <= 0)
			return 0;

		return totalNotes / totalSeconds;
	}

	function autosaveChart():Void
	{
		if (!validateChart())
			return;

		#if sys
		final diff = (curDiffSuffix != null && curDiffSuffix != '') ? curDiffSuffix : '';
		final ok = LevelFile.saveDiff(_song.song, diff, _song);
		if (ok)
			showMessage('💾 Autosaved (${_song.song}$diff.level)', ACCENT_SUCCESS);
		else
			showMessage('⚠ Autosave failed — check console', ACCENT_WARNING);
		#else
		showMessage('💾 Autosave not available on this platform', ACCENT_WARNING);
		#end
	}

	function saveChart():Void
	{
		if (!validateChart())
			return;

		final diff = (curDiffSuffix != null && curDiffSuffix != '') ? curDiffSuffix : '';

		#if sys
		// Desktop: guardar directamente en disco usando LevelFile
		final ok = LevelFile.saveDiff(_song.song, diff, _song);
		if (ok)
		{
			showMessage('💾 Saved → ${_song.song.toLowerCase()}$diff.level', ACCENT_SUCCESS);
			FlxG.sound.play(Paths.sound('menus/confirmMenu'), 0.6);
			_markSaved();
		}
		else
		{
			showMessage('X Error saving chart!', ACCENT_ERROR);
		}
		#else
		// Web / non-sys: exportar JSON legacy mediante FileReference (igual que antes)
		final json = {"song": _song};
		final data:String = Json.stringify(json, "\t");
		if (data.length > 0)
		{
			final fileName = _song.song.toLowerCase() + diff + ".json";
			_file = new FileReference();
			_file.addEventListener(Event.COMPLETE, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data, fileName);
		}
		showMessage('💾 Saving chart...', ACCENT_CYAN);
		#end
	}

	function onSaveComplete(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;

		showMessage('✅ Chart saved successfully!', ACCENT_SUCCESS);
		FlxG.sound.play(Paths.sound('menus/confirmMenu'), 0.6);
		_markSaved();
	}

	function onSaveCancel(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;

		showMessage('X Save cancelled', ACCENT_WARNING);
	}

	function onSaveError(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;

		showMessage('X Error saving chart!', ACCENT_ERROR);
	}

	/** Devuelve strumsGroups en el orden visual (igual que los iconos de personajes). */
	function getOrderedStrumsGroups():Array<StrumsGroupData>
	{
		if (_song.strumsGroups == null || _song.strumsGroups.length == 0)
			return _song.strumsGroups != null ? _song.strumsGroups : [];

		var ordered:Array<StrumsGroupData> = [];
		var usedIds:Array<String> = [];

		if (_song.characters != null)
		{
			for (char in _song.characters)
			{
				if (char.strumsGroup == null || char.strumsGroup.length == 0)
					continue;
				if (usedIds.indexOf(char.strumsGroup) >= 0)
					continue;
				for (sg in _song.strumsGroups)
				{
					if (sg.id == char.strumsGroup)
					{
						ordered.push(sg);
						usedIds.push(sg.id);
						break;
					}
				}
			}
		}

		// Grupos sin personaje asignado van al final
		for (sg in _song.strumsGroups)
			if (usedIds.indexOf(sg.id) < 0)
				ordered.push(sg);

		return ordered;
	}

	/** Columna de datos → columna visual (aplica reordenamiento por personaje). */
	function dataColToVisualCol(dataCol:Int):Int
	{
		if (_song.strumsGroups == null || _song.strumsGroups.length == 0)
			return dataCol;
		var dataGroupIdx = Math.floor(dataCol / 4);
		var direction = dataCol % 4;
		if (dataGroupIdx >= _song.strumsGroups.length)
			return dataCol;

		var dataGroupId = _song.strumsGroups[dataGroupIdx].id;
		var ordered = getOrderedStrumsGroups();

		for (i in 0...ordered.length)
			if (ordered[i].id == dataGroupId)
				return i * 4 + direction;

		return dataCol;
	}

	/** Columna visual → columna de datos (inverso del anterior). */
	function visualColToDataCol(visualCol:Int):Int
	{
		var visualGroupIdx = Math.floor(visualCol / 4);
		var direction = visualCol % 4;
		var ordered = getOrderedStrumsGroups();

		if (visualGroupIdx >= ordered.length)
			return visualCol;
		var visualGroupId = ordered[visualGroupIdx].id;

		if (_song.strumsGroups == null)
			return visualCol;
		for (i in 0..._song.strumsGroups.length)
			if (_song.strumsGroups[i].id == visualGroupId)
				return i * 4 + direction;

		return visualCol;
	}

	// ✨ NUEVA FUNCIÓN: Probar el chart en PlayState
	function testChart():Void
	{
		if (!validateChart())
		{
			showMessage('X Chart has errors! Fix them before testing.', ACCENT_ERROR);
			return;
		}

		showMessage('🎮 Loading PlayState from start...', ACCENT_CYAN);
		FlxG.sound.play(Paths.sound('menus/confirmMenu'), 0.6);

		// Detener audio
		FlxG.sound.music.stop();
		_stopChartVocals();

		// Actualizar PlayState.SONG con el chart actual
		PlayState.SONG = _song;
		PlayState.isStoryMode = false;
		PlayState.storyDifficulty = 1;
		PlayState.startFromTime = null; // ✨ Empezar desde el inicio

		// Pequeño delay para que el usuario vea el mensaje
		new FlxTimer().start(0.3, function(tmr:FlxTimer)
		{
			funkin.system.CursorManager.hide();
			LoadingState.loadAndSwitchState(new PlayState());
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
				trace('[ChartingState] GPU flush post-prewarm completed');
			});
			#end
		});
	}

	// ✨ NUEVA FUNCIÓN: Probar el chart desde la sección actual
	function testChartFromSection():Void
	{
		if (!validateChart())
		{
			showMessage('X Chart has errors! Fix them before testing.', ACCENT_ERROR);
			return;
		}

		var sectionStartTime = getSectionStartTime(curSection);

		showMessage('🎮 Testing from Section ${curSection + 1} (${formatTime(sectionStartTime)})...', ACCENT_CYAN);
		FlxG.sound.play(Paths.sound('menus/confirmMenu'), 0.6);

		// Detener audio
		FlxG.sound.music.stop();
		_stopChartVocals();

		// Actualizar PlayState.SONG con el chart actual
		PlayState.SONG = _song;
		PlayState.isStoryMode = false;
		PlayState.storyDifficulty = 1;
		PlayState.startFromTime = sectionStartTime; // ✨ Empezar desde esta sección

		trace('[ChartingState] Testing chart from section ${curSection + 1}, time: ${sectionStartTime}ms');

		// Pequeño delay para que el usuario vea el mensaje
		new FlxTimer().start(0.3, function(tmr:FlxTimer)
		{
			funkin.system.CursorManager.hide();
			LoadingState.loadAndSwitchState(new PlayState());
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
				trace('[ChartingState] GPU flush post-prewarm completed');
			});
			#end
		});
	}

	function loadChart():Void
	{
		_file = new FileReference();
		_file.addEventListener(Event.SELECT, onLoadSelect);
		_file.addEventListener(Event.CANCEL, onLoadCancel);
		_file.addEventListener(IOErrorEvent.IO_ERROR, onLoadError);
		// Acepta tanto .level (nuevo) como .json (legacy)
		_file.browse([new openfl.net.FileFilter('Level files (*.level, *.json)', '*.level;*.json')]);
		showMessage('📂 Select chart to load...', ACCENT_CYAN);
	}

	function onLoadSelect(_):Void
	{
		_file.addEventListener(Event.COMPLETE, onLoadComplete);
		_file.load();
	}

	function onLoadComplete(_):Void
	{
		final fullText:String = _file.data.toString();
		final fileName:String = _file.name?.toLowerCase() ?? '';

		try
		{
			var loadedSong:SwagSong = null;

			if (fileName.endsWith('.level'))
			{
				// ── Formato .level ────────────────────────────────────────
				final level:funkin.data.LevelFile.LevelData = cast haxe.Json.parse(fullText);
				// Intentar cargar la dificultad actual; si no existe, usar normal
				final dk = (curDiffSuffix != null && curDiffSuffix != '') ? curDiffSuffix : '';
				loadedSong = cast Reflect.field(level.difficulties, dk);
				if (loadedSong == null)
					loadedSong = cast Reflect.field(level.difficulties, '');
				if (loadedSong == null)
				{
					// Último recurso: primer campo
					final fields = Reflect.fields(level.difficulties);
					if (fields.length > 0)
						loadedSong = cast Reflect.field(level.difficulties, fields[0]);
				}
				if (loadedSong == null)
					throw 'No difficulties found in .level file';
			}
			else
			{
				// ── Formato .json legacy ──────────────────────────────────
				final parsedJson = haxe.Json.parse(fullText);
				loadedSong = parsedJson.song ?? cast parsedJson;
			}

			_song = loadedSong;

			// NORMALIZAR sectionBeats → lengthInSteps
			// Los charts de Psych Engine y los .level nativos usan `sectionBeats`
			// en lugar de `lengthInSteps`. Si lengthInSteps es nulo o 0 el grid
			// calcula altura 0 por sección y el editor no avanza.
			if (_song.notes != null)
			{
				for (rawSec in _song.notes)
				{
					var sec:Dynamic = rawSec;
					if (sec.lengthInSteps == null || sec.lengthInSteps <= 0)
					{
						var beats:Float = (sec.sectionBeats != null) ? cast sec.sectionBeats : 4.0;
						sec.lengthInSteps = Std.int(beats * 4);
					}
				}
			}

			// Verificar que tenga los campos necesarios
			if (_song.player1 == null)
				_song.player1 = 'bf';
			if (_song.player2 == null)
				_song.player2 = 'dad';
			if (_song.gfVersion == null)
				_song.gfVersion = 'gf';
			if (_song.stage == null)
				_song.stage = CharacterList.getDefaultStageForSong(_song.song);

			// Migrar formato legacy → nuevo (strumsGroups + characters con GF)
			funkin.data.Song.ensureMigrated(_song);

			// CRÍTICO: Crear sección por defecto si el array está vacío
			if (_song.notes == null || _song.notes.length == 0)
			{
				trace('[ChartingState] Loaded chart has empty notes array, creating default section');
				_song.notes = [
					{
						lengthInSteps: 16,
						bpm: _song.bpm,
						changeBPM: false,
						mustHitSection: true,
						sectionNotes: [],
						typeOfSection: 0,
						altAnim: false
					}
				];
			}

			PlayState.SONG = _song;

			// Reload
			loadSong(_song.song);
			curSection = 0;
			// Reconstruir grid con las columnas correctas (incluye GF si el chart la tiene)
			rebuildGrid();
			changeSection(0);

			// Update UI
			songNameText.text = '• ${_song.song}';
			if (stepperBPM != null)
				stepperBPM.value = _song.bpm;
			if (stepperSpeed != null)
				stepperSpeed.value = _song.speed;

			showMessage('✅ Chart loaded: ${_song.song}', ACCENT_SUCCESS);
			FlxG.sound.play(Paths.sound('menus/confirmMenu'), 0.6);
		}
		catch (e:Dynamic)
		{
			showMessage('X Error parsing JSON: $e', ACCENT_ERROR);
			trace('Load error: $e');
		}

		_file.removeEventListener(Event.SELECT, onLoadSelect);
		_file.removeEventListener(Event.CANCEL, onLoadCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);
		_file.removeEventListener(Event.COMPLETE, onLoadComplete);
		_file = null;
	}

	function onLoadCancel(_):Void
	{
		_file.removeEventListener(Event.SELECT, onLoadSelect);
		_file.removeEventListener(Event.CANCEL, onLoadCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);
		_file = null;

		showMessage('X Load cancelled', ACCENT_WARNING);
	}

	function onLoadError(_):Void
	{
		_file.removeEventListener(Event.SELECT, onLoadSelect);
		_file.removeEventListener(Event.CANCEL, onLoadCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);
		_file = null;

		showMessage('X Error loading chart!', ACCENT_ERROR);
	}

	function exportChart():Void
	{
		// Exportar chart con metadata adicional
		var json = {
			"song": _song,
			"metadata": {
				"editor": "Chart Editor v2.0",
				"exportDate": Date.now().toString(),
				"totalNotes": countTotalNotes(),
				"nps": Math.round(calculateNPS() * 100) / 100,
				"difficulty": "unknown"
			}
		};

		var data:String = Json.stringify(json, "\t");

		if (data.length > 0)
		{
			_file = new FileReference();
			_file.addEventListener(Event.COMPLETE, onExportComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data, _song.song.toLowerCase() + "-export.json");
		}
	}

	function onExportComplete(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onExportComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;

		showMessage('📦 Chart exported with metadata!', ACCENT_SUCCESS);
	}

	function countTotalNotes():Int
	{
		var total = 0;
		for (section in _song.notes)
			total += section.sectionNotes.length;
		return total;
	}

	function validateChart():Bool
	{
		// Validar que el chart tenga sentido
		if (_song.notes.length == 0)
		{
			showMessage('⚠️ Chart is empty!', ACCENT_WARNING);
			return false;
		}

		if (_song.bpm <= 0)
		{
			showMessage('⚠️ Invalid BPM!', ACCENT_WARNING);
			return false;
		}

		if (_song.song == null || _song.song == "")
		{
			showMessage('⚠️ Song name is empty!', ACCENT_WARNING);
			return false;
		}

		return true;
	}

	// ══════════════════════════════════════════════════════════════════
	// HELPERS DE VOCALES
	// ══════════════════════════════════════════════════════════════════

	/** Para (pausa) todos los tracks de vocales activos. */
	function _stopChartVocals():Void
	{
		if (vocals != null)
			vocals.stop();
		for (snd in vocalsPerChar)
			if (snd != null)
				snd.stop();
	}

	// ─── Unsaved-changes helpers ──────────────────────────────────────────────

	function _markUnsaved():Void
	{
		_hasUnsaved = true;
	}

	function _markSaved():Void
	{
		_hasUnsaved = false;
	}

	/**
	 * Intenta salir del editor de vuelta a PlayState.
	 * Si hay cambios sin guardar muestra el diálogo UnsavedChangesDialog.
	 * onProceed: acción a ejecutar una vez confirmado (normalmente testChart/goBack).
	 */
	function _tryExitEditor(onProceed:Void->Void):Void
	{
		if (!_hasUnsaved)
		{
			onProceed();
			return;
		}

		if (_unsavedDlg != null)
			return; // ya hay un diálogo abierto

		_unsavedDlg = new funkin.debug.EditorDialogs.UnsavedChangesDialog([camHUD]);

		_unsavedDlg.onSaveAndExit = () ->
		{
			saveChart();
			remove(_unsavedDlg, true);
			_unsavedDlg = null;
			onProceed();
		};

		_unsavedDlg.onSave = () ->
		{
			saveChart();
			remove(_unsavedDlg, true);
			_unsavedDlg = null;
		};

		_unsavedDlg.onExit = () ->
		{
			remove(_unsavedDlg, true);
			_unsavedDlg = null;
			onProceed();
		};

		add(_unsavedDlg);
	}

	/** Destruye y libera todos los tracks de vocales del editor. */
	function _destroyChartVocals():Void
	{
		if (vocals != null)
		{
			FlxG.sound.list.remove(vocals, true);
			vocals.stop();
			vocals.destroy();
			vocals = null;
		}
		for (snd in vocalsPerChar)
		{
			if (snd == null)
				continue;
			FlxG.sound.list.remove(snd, true);
			snd.stop();
			snd.destroy();
		}
		vocalsPerChar.clear();
		_chartPlayerKeys = [];
		_chartOpponentKeys = [];
		_chartPerCharVocals = false;
	}

	override function destroy():Void
	{
		// ── Audio ──────────────────────────────────────────────────────────
		_destroyChartVocals();

		// ── Waveform ───────────────────────────────────────────────────────
		if (waveformSprite != null)
		{
			waveformSprite.destroy();
			waveformSprite = null;
		}
		_waveformData = null;
		_waveformBuilt = false;

		// ── Maps / caches ─────────────────────────────────────────────────
		_firedNotes = null;
		_hitsoundFiredNotes = null;
		_susHeightCache = null;
		_sectionStartTimeCache = [];

		// ── Object pools ──────────────────────────────────────────────────
		_notePool = [];
		_susPool = [];
		for (h in _hlPool) if (h != null) h.destroy();
		_hlPool = [];

		// ── Notes groups ──────────────────────────────────────────────────
		if (curRenderedNotes != null)
		{
			curRenderedNotes.clear();
			curRenderedNotes = null;
		}
		if (curRenderedSustains != null)
		{
			curRenderedSustains.clear();
			curRenderedSustains = null;
		}
		if (_curSusTails != null)
		{
			_curSusTails.clear();
			_curSusTails = null;
		}
		if (curRenderedTypeLabels != null)
		{
			curRenderedTypeLabels.clear();
			curRenderedTypeLabels = null;
		}

		// ── Section indicators ────────────────────────────────────────────
		if (sectionIndicators != null)
		{
			sectionIndicators.clear();
			sectionIndicators = null;
		}

		// ── Undo/redo stacks ──────────────────────────────────────────────
		undoStack = null;
		redoStack = null;
		clipboard = null;

		// ── File reference ────────────────────────────────────────────────
		if (_file != null)
		{
			_file.removeEventListener(openfl.events.Event.COMPLETE, onSaveComplete);
			_file.removeEventListener(openfl.events.Event.CANCEL, onSaveCancel);
			_file.removeEventListener(openfl.events.IOErrorEvent.IO_ERROR, onSaveError);
			_file = null;
		}

		// ── State ─────────────────────────────────────────────────────────
		lastSection = curSection;

		// ── Quitar listener de cierre de ventana ───────────────────────────
		#if sys
		if (_windowCloseFn != null)
		{
			try { lime.app.Application.current.window.onClose.remove(_windowCloseFn); }
			catch (_) {}
			_windowCloseFn = null;
		}
		#end
		_unsavedDlg = null;

		super.destroy();

		// ── Liberar memoria del ChartingState ────────────────────────────────
		// Esto asegura que las texturas del editor (grid, notas del editor, etc.)
		// se liberen antes de que PlayState empiece a cargar sus assets.
		// Sin esto, al volver a PlayState la memoria pico puede ser muy alta
		// porque ambos estados tienen assets en memoria simultáneamente.
		try
		{
			Paths.clearStoredMemory();
		}
		catch (_:Dynamic)
		{
		}
		try
		{
			Paths.clearUnusedMemory();
		}
		catch (_:Dynamic)
		{
		}
		try
		{
			openfl.system.System.gc();
		}
		catch (_:Dynamic)
		{
		}
		#if cpp
		try
		{
			cpp.vm.Gc.compact();
		}
		catch (_:Dynamic)
		{
		}
		#end
		// Prune atlas cache DESPUÉS del GC (bitmap==null ya es detectable).
		// PlayState.create() llamará beginSession()+clearStoredMemory() para carga limpia.
		try
		{
			Paths.pruneAtlasCache();
		}
		catch (_:Dynamic)
		{
		}
		try
		{
			FlxG.bitmap.clearUnused();
		}
		catch (_:Dynamic)
		{
		}
	}

	// ==================== HELPER FUNCTIONS ====================

	function formatTime(seconds:Float):String
	{
		var minutes = Math.floor(seconds / 60);
		var secs = Math.floor(seconds % 60);
		var ms = Math.floor((seconds % 1) * 1000);

		return '${StringTools.lpad('$minutes', "0", 2)}:${StringTools.lpad('$secs', "0", 2)}.${StringTools.lpad('$ms', "0", 3)}';
	}

	// ── Ventana deslizante del grid ────────────────────────────────────────

	/** Redibuja gridBG para la ventana actual de filas */
	function _redrawGridBG(gridWidth:Int, numCols:Int):Void
	{
		var windowH = _gridWindowRows * GRID_SIZE;
		gridBG.pixels.fillRect(new openfl.geom.Rectangle(0, 0, gridWidth, windowH), 0xFF000000);

		for (row in 0..._gridWindowRows)
		{
			var absRow = _gridWindowOffset + row;
			for (col in 0...numCols)
			{
				var xPos = col * GRID_SIZE;
				var yPos = row * GRID_SIZE;
				var groupIndex = Math.floor(col / 4);
				var baseLight = (groupIndex % 2 == 0) ? 0x40 : 0x35;
				var baseDark = (groupIndex % 2 == 0) ? 0x2A : 0x22;
				var isEven = (absRow + col) % 2 == 0;
				var r = isEven ? baseLight : baseDark;
				var cellColor = (0xFF << 24) | (r << 16) | (r << 8) | r;
				FlxSpriteUtil.drawRect(gridBG, xPos, yPos, GRID_SIZE, GRID_SIZE, cellColor);
			}
		}
		// Líneas horizontales
		for (row in 0..._gridWindowRows)
		{
			var absRow = _gridWindowOffset + row;
			var yPos = row * GRID_SIZE;
			var lineColor = (absRow % 4 == 0) ? 0xFF707070 : 0xFF505050;
			FlxSpriteUtil.drawRect(gridBG, 0, yPos, gridWidth, 1, lineColor);
		}
		// Líneas verticales
		for (col in 0...(numCols + 1))
		{
			var xPos = col * GRID_SIZE;
			var isGroupBorder = (col % 4 == 0);
			var lineColor = isGroupBorder ? 0xFFB0B0B0 : 0xFF707070;
			var lineWidth = isGroupBorder ? 2 : 1;
			FlxSpriteUtil.drawRect(gridBG, xPos, 0, lineWidth, _gridWindowRows * GRID_SIZE, lineColor);
		}
		gridBG.dirty = true;
	}

	/** Redibuja gridBlackWhite (divisores de sección) para la ventana actual */
	function _redrawGridBW(gridWidth:Int):Void
	{
		var windowH = _gridWindowRows * GRID_SIZE;
		gridBlackWhite.pixels.fillRect(new openfl.geom.Rectangle(0, 0, gridWidth, windowH), 0x00000000);

		var absStartY = _gridWindowOffset * GRID_SIZE;
		var absEndY = absStartY + windowH;
		var currentAbsY:Float = 0;

		for (i in 0..._song.notes.length)
		{
			var steps = (_song.notes[i].lengthInSteps > 0) ? _song.notes[i].lengthInSteps : 16;
			var sectionHeight = steps * GRID_SIZE;
			var lineAbsY = currentAbsY;

			if (lineAbsY >= absStartY && lineAbsY < absEndY)
			{
				var lineLocalY = Std.int(lineAbsY - absStartY);
				var lineColor = (i % 2 == 0) ? 0x80FFFFFF : 0x4000D9FF;
				FlxSpriteUtil.drawRect(gridBlackWhite, 0, lineLocalY, gridWidth, 2, lineColor);
			}
			currentAbsY += sectionHeight;
			if (currentAbsY > absEndY + sectionHeight)
				break;
		}
		gridBlackWhite.dirty = true;
	}

	/** Mueve el grid y redibuja la ventana si es necesario */
	function _applyGridScroll(scrollY:Float):Void
	{
		var numCols = getGridColumns();
		var gridWidth = GRID_SIZE * numCols;

		var currentRow = Std.int(scrollY / GRID_SIZE);
		var windowEnd = _gridWindowOffset + _gridWindowRows;
		var buffer = 3; // filas de margen antes de redibujar

		if (currentRow < _gridWindowOffset + buffer || currentRow + Std.int(FlxG.height / GRID_SIZE) > windowEnd - buffer)
		{
			_gridWindowOffset = Std.int(Math.max(0, currentRow - buffer));
			_redrawGridBG(gridWidth, numCols);
			_redrawGridBW(gridWidth);
		}

		gridBG.y = 100 - scrollY + _gridWindowOffset * GRID_SIZE;
		gridBlackWhite.y = gridBG.y;
		strumLine.y = 100;
		// Strums fijos en y=100 (camHUD — no necesitan reposicionarse con el scroll)
	}

	/**
	 * Muestra la Note-ghost en la columna y posición world indicadas.
	 * alpha: 0.75 para drag, 0.45 para hover preview.
	 */
	function _showGhostNote(visualCol:Int, worldY:Float, alpha:Float):Void
	{
		var dir = visualCol % 4;
		var stepHeight = GRID_SIZE / (currentSnap / 16);
		var snapLocalY = Math.floor(worldY / stepHeight) * stepHeight;
		var screenY = gridBG.y + snapLocalY;

		for (i in 0...4)
		{
			var gn = _ghostNotes[i];
			if (gn == null) continue;
			if (i == dir)
			{
				gn.x = gridBG.x + visualCol * GRID_SIZE;
				gn.y = screenY;
				gn.alpha = alpha;
				gn.color = NOTE_COLORS[visualCol % 8];
				gn.visible = true;
			}
			else
			{
				gn.visible = false;
			}
		}
	}

	/** Oculta todos los ghost Notes (drag y hover). */
	function _hideAllGhostNotes():Void
	{
		for (gn in _ghostNotes)
			if (gn != null) gn.visible = false;
		_hoverNoteCol = -1;
	}

	function _gridScrollToTime(scrollY:Float):Float
	{
		var accumulatedSteps:Float = 0;
		for (i in 0..._song.notes.length)
		{
			var sectionHeight:Float = _song.notes[i].lengthInSteps * GRID_SIZE;
			if (scrollY < accumulatedSteps + sectionHeight)
			{
				var progressInSection = (scrollY - accumulatedSteps) / sectionHeight;
				return getSectionStartTime(i) + progressInSection * getSectionDuration(i);
			}
			accumulatedSteps += sectionHeight;
		}
		// Pasó del final → devolver tiempo del último frame
		return getSectionStartTime(_song.notes.length - 1) + getSectionDuration(_song.notes.length - 1);
	}

	function clamp(value:Float, min:Float, max:Float):Float
	{
		if (value < min)
			return min;
		if (value > max)
			return max;
		return value;
	}

	function getNoteDataName(noteData:Int):String
	{
		var names = ["Left", "Down", "Up", "Right"];
		return names[noteData % 4];
	}

	function getSnapName(snap:Int):String
	{
		return switch (snap)
		{
			case 16: "1/4";
			case 32: "1/8";
			case 48: "1/12";
			case 64: "1/16";
			default: "1/4";
		};
	}
}

typedef ChartAction =
{
	var type:String;
	var section:Int;
	var data:Dynamic;
}
/*
 * 
 * SHORTCUTS:
 * - 1-8: Colocar notas rápido
 * - Shift+1-8: Colocar holds
 * - Ctrl+C/V/X: Copy/Paste/Cut
 * - M: Mirror section
 * - Q/E: Change snap
 * - T: Toggle hitsounds
 * - M: Toggle metronome
 * - Space: Play/Pause
 * - Enter: Restart from section
 * - PageUp/Down: Navigate sections
 * - ESC: Exit
 * 
 * FEATURES:
 * ✅ UI Moderna con colores
 * ✅ Info panel en tiempo real
 * ✅ Status bar con tips rotativos
 * ✅ Copy/Paste/Mirror
 * ✅ Quick note placement
 * ✅ Hitsounds y metronome
 * ✅ Autosave cada 5 minutos
 * ✅ Selector de personajes y stages
 * ✅ Save/Load con metadata
 * ✅ Chart validation
 * ✅ Playtest mode
 * ✅ Sincronización de vocales mejorada
 * 
 * AUTOSAVE:
 * - Cada 5 minutos automáticamente
 * - Guarda en assets/data/[song]/autosave-[song].json
 * - Backups manuales disponibles
 * 
 * DISFRUTA! 🎮✨
 */
