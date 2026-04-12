package funkin.menus;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxCamera;
import flixel.FlxSubState;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import mods.ModManager;
import mods.ModManager.ModInfo;
import funkin.data.LevelFile;
import mods.compat.PsychConverter;
import mods.compat.CodenameConverter;
import mods.compat.ModFormat;
import mods.compat.ModFormat.ModFormatDetector;
import funkin.debug.themes.EditorTheme;
import haxe.Json;

#if sys
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;
#end

using StringTools;

/**
 * ModImportSubState — Importa y convierte mods de otros engines.
 *
 * ─── Motores soportados ────────────────────────────────────────────────────
 *  - Psych Engine   -- detecta data/songs/SONG/chart.json, campos player1/player2,
 *                     assets/images/, assets/sounds/.
 *  - Codename Engine -- detecta data/songs/SONG con .yml o codenameChart.
 *  - Generico FNF  -- cualquier carpeta con data/songs/ y mod.json.
 *
 * ─── Formas de importar ────────────────────────────────────────────────────
 *  1. Escribe la ruta a mano y pulsa [Enter].
 *  2. Pulsa [B] o el boton Browse para abrir el selector nativo del SO.
 *  3. Arrastra la carpeta del mod (o un .zip) encima de la ventana.
 *
 * ─── Proceso ──────────────────────────────────────────────────────────────
 *  1. Se detecta el engine de origen.
 *  2. Los assets se copian y renombran a la estructura del engine actual.
 *  3. Los charts se convierten al formato .level nativo.
 *  4. Se crea/actualiza el mod.json del mod importado.
 */
class ModImportSubState extends FlxSubState
{
	// ── Callbacks ─────────────────────────────────────────────────────────────
	var _onDone : Null<Void->Void>;

	// ── UI ────────────────────────────────────────────────────────────────────
	var _camSub      : FlxCamera;
	var _pathInput   : FlxText;
	var _statusTxt   : FlxText;
	var _progressTxt : FlxText;
	var _hintTxt     : FlxText;
	var _stepTxt     : FlxText;
	var _bg          : FlxSprite;
	var _panel       : FlxSprite;
	var _dropZoneBg  : FlxSprite;   // drop zone fill
	var _dropZoneBorder : FlxSprite; // drop zone dashed border (solid here)
	var _dropZoneTxt : FlxText;
	var _browseBtnBg : FlxSprite;
	var _browseBtnTxt: FlxText;

	// ── State machine ─────────────────────────────────────────────────────────
	var _phase       : ImportPhase = WAITING_PATH;
	var _path        : String      = '';
	var _logs        : Array<String> = [];

	// ── Layout constants ──────────────────────────────────────────────────────
	static final PW     = 820;
	static final PH     = 530;
	static final BTN_W  = 90;
	static final INP_W  = PW - 32 - BTN_W - 8; // input width leaving room for button

	// ── Lime input ────────────────────────────────────────────────────────────
	var _limeWindow : lime.app.Application;

	public function new(?onDone:Void->Void)
	{
		super(0x00000000);
		_onDone = onDone;
	}

	override function create()
	{
		_camSub = new FlxCamera();
		_camSub.bgColor = FlxColor.TRANSPARENT;
		FlxG.cameras.add(_camSub, false);
		cameras = [_camSub];

		final T  = EditorTheme.current;
		final px = (FlxG.width  - PW) / 2;
		final py = (FlxG.height - PH) / 2;

		// ── Overlay + panel ───────────────────────────────────────────────────
		_bg = new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, 0xCC000000);
		_bg.scrollFactor.set(); _bg.alpha = 0; add(_bg);
		FlxTween.tween(_bg, {alpha: 1}, 0.18);

		_panel = new FlxSprite(px, py).makeGraphic(PW, PH, T.bgPanel);
		_panel.scrollFactor.set(); add(_panel);

		final accent = new FlxSprite(px, py).makeGraphic(PW, 4, T.accent);
		accent.scrollFactor.set(); add(accent);

		// ── Title ────────────────────────────────────────────────────────────
		final title = new FlxText(px, py + 12, PW, '⬆  IMPORT MOD');
		title.setFormat(Paths.font('vcr.ttf'), 20, T.textPrimary, CENTER, OUTLINE, T.bgDark);
		title.scrollFactor.set(); add(title);

		final sep = new FlxSprite(px + 16, py + 44).makeGraphic(PW - 32, 1, T.borderColor);
		sep.scrollFactor.set(); add(sep);

		// ── Description ───────────────────────────────────────────────────────
		#if mobileC
		final desc = new FlxText(px + 20, py + 52, PW - 40,
			'On mobile, copy your mod folder or .zip to the mods directory shown below.\n' +
			'Supported: Psych Engine, Codename Engine, Base FNF.');
		#else
		final desc = new FlxText(px + 20, py + 52, PW - 40,
			'Type a path, click [Browse], or drag a mod folder / .zip onto this window.\n' +
			'Supported: Psych Engine, Codename Engine, Base FNF.');
		#end
		desc.setFormat(Paths.font('vcr.ttf'), 12, T.textSecondary, LEFT);
		desc.wordWrap = true;
		desc.scrollFactor.set(); add(desc);

		// ── Path input ────────────────────────────────────────────────────────
		final iBg = new FlxSprite(px + 16, py + 88).makeGraphic(Std.int(INP_W), 36, T.bgPanelAlt);
		iBg.scrollFactor.set(); add(iBg);

		_pathInput = new FlxText(px + 24, py + 94, INP_W - 16, '|');
		_pathInput.setFormat(Paths.font('vcr.ttf'), 14, T.textPrimary, LEFT);
		_pathInput.scrollFactor.set(); add(_pathInput);

		// ── Browse button / indicator disponibility ───────────────────────
		final bx = px + 16 + INP_W + 8;
		#if mobileC
		_browseBtnBg = new FlxSprite(bx, py + 88).makeGraphic(BTN_W, 36, T.bgPanelAlt);
		_browseBtnBg.scrollFactor.set(); add(_browseBtnBg);
		_browseBtnTxt = new FlxText(bx, py + 96, BTN_W, 'Browse');
		_browseBtnTxt.setFormat(Paths.font('vcr.ttf'), 13, T.textDim, CENTER, NONE, 0x00000000);
		_browseBtnTxt.scrollFactor.set(); add(_browseBtnTxt);
		#else
		_browseBtnBg = new FlxSprite(bx, py + 88).makeGraphic(BTN_W, 36, T.accent);
		_browseBtnBg.scrollFactor.set(); add(_browseBtnBg);
		_browseBtnTxt = new FlxText(bx, py + 96, BTN_W, 'Browse');
		_browseBtnTxt.setFormat(Paths.font('vcr.ttf'), 13, T.bgDark, CENTER, OUTLINE, 0x00000000);
		_browseBtnTxt.scrollFactor.set(); add(_browseBtnTxt);
		#end

		// ── Drop zone / instructions rute mobile ──────────────────────────
		_dropZoneBorder = new FlxSprite(px + 16, py + 136)
			.makeGraphic(PW - 32, 90, T.borderColor);
		_dropZoneBorder.scrollFactor.set(); add(_dropZoneBorder);

		_dropZoneBg = new FlxSprite(px + 18, py + 138)
			.makeGraphic(PW - 36, 86, T.bgPanelAlt);
		_dropZoneBg.scrollFactor.set(); add(_dropZoneBg);

		#if mobileC
		_dropZoneTxt = new FlxText(px + 16, py + 148, PW - 32,
			'Copy mods here:\n' + mods.ModManager.MODS_FOLDER);
		_dropZoneTxt.setFormat(Paths.font('vcr.ttf'), 13, T.accent, CENTER);
		_dropZoneTxt.wordWrap = true;
		#else
		_dropZoneTxt = new FlxText(px + 16, py + 164, PW - 32,
			'\u{1F4C1}  Drop mod folder or .zip here');
		_dropZoneTxt.setFormat(Paths.font('vcr.ttf'), 16, T.textDim, CENTER);
		#end
		_dropZoneTxt.scrollFactor.set(); add(_dropZoneTxt);

		// ── Step / log ────────────────────────────────────────────────────────
		final logSep = new FlxSprite(px + 16, py + 238).makeGraphic(PW - 32, 1, T.borderColor);
		logSep.scrollFactor.set(); add(logSep);

		_stepTxt = new FlxText(px + 20, py + 248, PW - 40, 'Step: Enter folder path or Browse');
		_stepTxt.setFormat(Paths.font('vcr.ttf'), 13, T.accent, LEFT);
		_stepTxt.scrollFactor.set(); add(_stepTxt);

		_progressTxt = new FlxText(px + 20, py + 274, PW - 40, '');
		_progressTxt.setFormat(Paths.font('vcr.ttf'), 11, T.textSecondary, LEFT);
		_progressTxt.wordWrap = true;
		_progressTxt.scrollFactor.set(); add(_progressTxt);

		// ── Status + hint ─────────────────────────────────────────────────────
		_statusTxt = new FlxText(px + 20, py + PH - 72, PW - 40, '');
		_statusTxt.setFormat(Paths.font('vcr.ttf'), 14, T.success, CENTER);
		_statusTxt.scrollFactor.set(); add(_statusTxt);

		#if mobileC
		_hintTxt = new FlxText(px + 20, py + PH - 42, PW - 40,
			'Tap path field to type   [Enter] Import   [Esc] Cancel');
		#else
		_hintTxt = new FlxText(px + 20, py + PH - 42, PW - 40,
			'[Enter] Import   [B] Browse   [Esc] Cancel');
		#end
		_hintTxt.setFormat(Paths.font('vcr.ttf'), 12, T.textDim, CENTER);
		_hintTxt.scrollFactor.set(); add(_hintTxt);

		// ── Native input hooks ────────────────────────────────────────────────
		try
		{
			_limeWindow = lime.app.Application.current;
			_limeWindow.window.onTextInput.add(_onText);
			// onDropFile solo existe y funciona en desktop — ignorar en móvil
			#if !mobileC
			_limeWindow.window.onDropFile.add(_onDropFile);
			#end
			FlxG.stage.addEventListener(openfl.events.KeyboardEvent.KEY_DOWN, _onKeyDown);
		}
		catch (_) {}

		super.create();
	}

	// ── Native input ──────────────────────────────────────────────────────────

	function _onText(text:String):Void
	{
		if (_phase != WAITING_PATH) return;
		_path += text;
		_pathInput.text = _path + '|';
	}

	function _onKeyDown(e:openfl.events.KeyboardEvent):Void
	{
		if (_phase != WAITING_PATH) return;
		if (e.keyCode == 8 && _path.length > 0)
		{
			_path = _path.substr(0, _path.length - 1);
			_pathInput.text = _path + '|';
		}
	}

	/** Called by Lime when any file or folder is dragged onto the window. */
	function _onDropFile(droppedPath:String):Void
	{
		if (_phase != WAITING_PATH) return;
		_path = droppedPath.trim();
		_pathInput.text = _path + '|';

		// Flash the drop zone to give feedback
		_dropZoneBorder.color = EditorTheme.current.accent;
		_dropZoneTxt.color    = EditorTheme.current.textPrimary;
		_dropZoneTxt.text     = '✓  ' + _path.split('/').pop().split('\\').pop();
		FlxTween.tween(_dropZoneBorder, {}, 0.6, {
			onComplete: _ -> {
				_dropZoneBorder.color = EditorTheme.current.borderColor;
				_dropZoneTxt.color    = EditorTheme.current.textDim;
				_dropZoneTxt.text     = '📁  Drop mod folder or .zip here';
			}
		});

		// Auto-start import after a short delay so the user sees the feedback
		haxe.Timer.delay(_startImport, 400);
	}

	// ── Update ────────────────────────────────────────────────────────────────

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (FlxG.keys.justPressed.ESCAPE)
		{
			FlxG.sound.play(Paths.sound('menus/scrollMenu'));
			_close();
			return;
		}

		if (_phase == WAITING_PATH)
		{
			if (FlxG.keys.justPressed.ENTER)
			{
				FlxG.sound.play(Paths.sound('menus/confirmMenu'));
				_startImport();
			}

			#if !mobileC
			if (FlxG.keys.justPressed.B)
				_browseForFolder();

			if (FlxG.mouse.justPressed && _browseBtnBg != null
				&& _browseBtnBg.overlapsPoint(FlxG.mouse.getWorldPosition(null), true, _camSub))
			{
				FlxG.sound.play(Paths.sound('menus/confirmMenu'));
				_browseForFolder();
			}
			#end
		}
		else if (_phase == DONE && (FlxG.keys.justPressed.ENTER || FlxG.keys.justPressed.ESCAPE))
		{
			_close();
		}
	}

	// ── Browse ────────────────────────────────────────────────────────────────

	/**
	 * Opens the OS native folder-picker dialog (blocking).
	 * Windows: PowerShell FolderBrowserDialog
	 * macOS:   osascript choose folder
	 * Linux:   zenity (or kdialog as fallback)
	 */
	function _browseForFolder():Void
	{
		#if sys
		_stepTxt.text = 'Opening folder picker…';
		var picked : Null<String> = null;
		try
		{
			#if windows
			final script = '[System.Reflection.Assembly]::LoadWithPartialName(\'System.Windows.Forms\') | Out-Null; '
				+ '$$d = New-Object System.Windows.Forms.FolderBrowserDialog; '
				+ '$$d.Description = \'Select mod folder\'; '
				+ 'if ($$d.ShowDialog() -eq \'OK\') { Write-Output $$d.SelectedPath }';
			final proc = new Process('powershell', ['-NoProfile', '-Command', script]);
			picked = proc.stdout.readAll().toString().trim();
			proc.close();
			#elseif mac
			final proc = new Process('osascript', ['-e', 'POSIX path of (choose folder with prompt "Select mod folder")']);
			picked = proc.stdout.readAll().toString().trim();
			proc.close();
			// osascript adds a trailing newline and sometimes a trailing /
			if (picked != null && picked.endsWith('/'))
				picked = picked.substr(0, picked.length - 1);
			#elseif linux
			// Try zenity first, fall back to kdialog
			var proc : Null<Process> = null;
			try
			{
				proc = new Process('zenity', ['--file-selection', '--directory', '--title=Select mod folder']);
			}
			catch (_)
			{
				try { proc = new Process('kdialog', ['--getexistingdirectory', '.', 'Select mod folder']); }
				catch (_) {}
			}
			if (proc != null)
			{
				picked = proc.stdout.readAll().toString().trim();
				proc.close();
			}
			#end
		}
		catch (e:Dynamic)
		{
			trace('[ModImport] Browse error: $e');
		}

		if (picked != null && picked != '')
		{
			_path = picked;
			_pathInput.text = _path + '|';
			_stepTxt.text = 'Path selected — press [Enter] to import';
		}
		else
		{
			_stepTxt.text = 'Step: Enter folder path or Browse';
		}
		#else
		_stepTxt.text = 'Browse not available on this platform';
		#end
	}

	// ── Import pipeline ───────────────────────────────────────────────────────

	function _startImport():Void
	{
		#if sys
		if (_phase != WAITING_PATH) return;
		final T = EditorTheme.current;
		_logs = [];
		_phase = IMPORTING;
		_hintTxt.text = 'Importing…';

		var srcPath = _path.trim();
		if (srcPath == '' || !FileSystem.exists(srcPath))
		{
			_fail('Path not found: $srcPath');
			return;
		}

		// ── Zip extraction ────────────────────────────────────────────────────
		if (srcPath.toLowerCase().endsWith('.zip'))
		{
			_log('Extracting zip…');
			final extracted = _extractZip(srcPath);
			if (extracted == null)
			{
				_fail('Could not extract zip file.');
				return;
			}
			srcPath = extracted;
			_log('Extracted to: $srcPath');
		}

		// ── Resolve folder (handle case where a file inside was dropped) ──────
		if (!FileSystem.isDirectory(srcPath))
			srcPath = haxe.io.Path.directory(srcPath);

		_log('Scanning: $srcPath');
		final engine = _detectEngine(srcPath);
		_log('Detected engine: $engine');
		_stepTxt.text = 'Engine: $engine';

		final folderName = srcPath.replace('\\', '/').split('/').pop() ?? 'imported_mod';
		final modId      = folderName.toLowerCase().replace(' ', '_');
		final destDir    = '${mods.ModManager.MODS_FOLDER}/$modId';

		_log('Installing to: $destDir');
		if (!FileSystem.exists(destDir)) FileSystem.createDirectory(destDir);

		final ok = switch (engine)
		{
			case 'Psych Engine':    _importPsych(srcPath, destDir, modId);
			case 'Codename Engine': _importCodename(srcPath, destDir, modId);
			default:                _importGeneric(srcPath, destDir, modId);
		};

		if (ok)
		{
			_log('Refreshing ModManager…');
			ModManager.init();
			_phase = DONE;
			_statusTxt.text = '✓ Import complete! Mod "$modId" installed.';
			_statusTxt.color = T.success;
			_hintTxt.text = '[Enter / Esc] Close';
			if (_onDone != null) _onDone();
		}
		else
		{
			_fail('Import failed. Check logs above.');
		}
		#else
		_fail('File system not available on this platform.');
		#end
	}

	// ── Zip extraction ────────────────────────────────────────────────────────

	/**
	 * Extracts a .zip to a temp directory and returns the path of the
	 * extracted folder (the first top-level directory inside the zip).
	 * Returns null on failure.
	 */
	function _extractZip(zipPath:String):Null<String>
	{
		#if sys
		try
		{
			// Destination: next to the zip, without the .zip extension
			final base    = haxe.io.Path.withoutExtension(zipPath);
			final destDir = FileSystem.exists(base) ? base + '_imported' : base;
			if (!FileSystem.exists(destDir)) FileSystem.createDirectory(destDir);

			final bytes  = File.getBytes(zipPath);
			final input  = new haxe.io.BytesInput(bytes);
			final reader = new haxe.zip.Reader(input);
			final entries = reader.read();

			for (entry in entries)
			{
				if (entry.fileName.endsWith('/') || entry.fileName.endsWith('\\'))
					continue; // directory entry — skip, createDirectory handles it

				final outPath = '$destDir/${entry.fileName}';
				final outDir  = haxe.io.Path.directory(outPath);
				if (!FileSystem.exists(outDir)) FileSystem.createDirectory(outDir);

				final data = entry.compressed
					? haxe.zip.Reader.unzip(entry)
					: entry.data;
				File.saveBytes(outPath, data);
			}

			// Return the single top-level folder if there is one, else destDir
			final entries2 = FileSystem.readDirectory(destDir);
			if (entries2.length == 1 && FileSystem.isDirectory('$destDir/${entries2[0]}'))
				return '$destDir/${entries2[0]}';
			return destDir;
		}
		catch (e:Dynamic)
		{
			trace('[ModImport] Zip extraction error: $e');
			return null;
		}
		#else
		return null;
		#end
	}

	// ── Engine detection ──────────────────────────────────────────────────────

	function _detectEngine(dir:String):String
	{
		#if sys
		if (FileSystem.exists('$dir/data/songs'))
		{
			for (song in _listDirs('$dir/data/songs'))
			{
				if (FileSystem.exists('$dir/data/songs/$song/chart.json'))
				{
					try
					{
						final c = Json.parse(File.getContent('$dir/data/songs/$song/chart.json'));
						final s:Dynamic = Reflect.field(c, 'song') ?? c;
						if (Reflect.hasField(s, 'player1') && Reflect.hasField(s, 'speed'))
							return 'Psych Engine';
					}
					catch (_) {}
				}
			}
		}

		if (FileSystem.exists('$dir/data/songs'))
		{
			for (song in _listDirs('$dir/data/songs'))
			{
				for (f in _listFiles('$dir/data/songs/$song'))
				{
					if (f.endsWith('.yml')) return 'Codename Engine';
					if (f.endsWith('.json'))
					{
						try
						{
							final c:Dynamic = Json.parse(File.getContent('$dir/data/songs/$song/$f'));
							if (Reflect.hasField(c, 'codenameChart')) return 'Codename Engine';
						}
						catch (_) {}
					}
				}
			}
		}
		#end
		return 'Generic FNF';
	}

	// ── Psych Engine importer ─────────────────────────────────────────────────

	function _importPsych(src:String, dest:String, modId:String):Bool
	{
		#if sys
		try
		{
			if (FileSystem.exists('$src/data/songs'))
			{
				final destSongs = '$dest/assets/songs';
				if (!FileSystem.exists(destSongs)) FileSystem.createDirectory(destSongs);

				for (songFolder in _listDirs('$src/data/songs'))
				{
					final srcSong  = '$src/data/songs/$songFolder';
					final destSong = '$destSongs/$songFolder';
					if (!FileSystem.exists(destSong)) FileSystem.createDirectory(destSong);

					final diffs : Map<String, funkin.data.Song.SwagSong> = new Map();
					for (f in _listFiles(srcSong))
					{
						if (!f.endsWith('.json')) continue;
						final diffLabel = f.replace('.json', '').toLowerCase();
						final suffix    = _psychFileSuffix(diffLabel, songFolder.toLowerCase());
						try
						{
							final raw      = File.getContent('$srcSong/$f').trim();
							final diffName = suffix == '' ? 'normal' : suffix.substr(1);
							final song     = PsychConverter.convertChart(raw, diffName);
							diffs.set(suffix, song);
							_log('  Converted: $songFolder [$diffLabel → "$suffix"]');
						}
						catch (e) { _log('  Skip $f: $e'); }
					}

					if (Lambda.count(diffs) == 0) continue;

					final firstSong = diffs.exists('') ? diffs.get('') : diffs.iterator().next();
					LevelFile.saveAll(songFolder, diffs, null, firstSong.song ?? songFolder, null);
				}
			}

			_convertPsychCharacters('$src/data/characters', '$dest/assets/data/characters');
			_copyDir('$src/images',      '$dest/assets/images');
			_copyDir('$src/sounds',      '$dest/assets/sounds');
			_copyDir('$src/music',       '$dest/assets/music');
			_copyDir('$src/data/stages', '$dest/assets/data/stages');
			_mergeSongAudio('$src/songs', '$dest/assets/songs');

			_writePsychModJson(src, dest, modId);
			_log('Psych Engine import finished.');
			return true;
		}
		catch (e:Dynamic)
		{
			_log('Psych import error: $e');
			return false;
		}
		#else
		return false;
		#end
	}

	function _psychFileSuffix(diffFile:String, songFolder:String):String
	{
		if (diffFile == songFolder) return '';
		if (diffFile.startsWith(songFolder + '-'))
			return diffFile.substr(songFolder.length);
		return switch (diffFile)
		{
			case 'normal': '';
			case 'easy':   '-easy';
			case 'hard':   '-hard';
			default:       '-$diffFile';
		};
	}

	function _convertPsychCharacters(srcDir:String, destDir:String):Void
	{
		#if sys
		if (!FileSystem.exists(srcDir)) return;
		if (!FileSystem.exists(destDir)) FileSystem.createDirectory(destDir);
		for (f in _listFiles(srcDir))
		{
			if (!f.endsWith('.json')) continue;
			try
			{
				final charName  = f.replace('.json', '');
				final raw       = File.getContent('$srcDir/$f').trim();
				final converted = PsychConverter.convertCharacter(raw, charName);
				File.saveContent('$destDir/$f', Json.stringify(converted, null, '\t'));
				_log('  Converted char: $charName');
			}
			catch (e) { _log('  Skip char $f: $e'); }
		}
		#end
	}

	function _writePsychModJson(src:String, dest:String, modId:String):Void
	{
		#if sys
		var name        = modId;
		var description = 'Imported from Psych Engine';
		var author      = '';
		var version     = '1.0.0';
		try
		{
			final pack = '$src/pack.json';
			if (FileSystem.exists(pack))
			{
				final d : Dynamic = Json.parse(File.getContent(pack));
				name        = Reflect.field(d, 'name')        ?? modId;
				description = Reflect.field(d, 'description') ?? description;
				author      = Reflect.field(d, 'author')      ?? '';
			}
		}
		catch (_) {}

		final info : Dynamic = {
			id: modId, name: name, description: description,
			author: author, version: version, priority: 0,
			color: 0xFF8844FF, website: '', enabled: true, startupDefault: false
		};
		File.saveContent('$dest/mod.json', Json.stringify(info, null, '\t'));
		#end
	}

	// ── Codename Engine importer ──────────────────────────────────────────────

	function _importCodename(src:String, dest:String, modId:String):Bool
	{
		#if sys
		try
		{
			if (FileSystem.exists('$src/data/songs'))
			{
				final destSongs = '$dest/assets/songs';
				if (!FileSystem.exists(destSongs)) FileSystem.createDirectory(destSongs);

				for (songFolder in _listDirs('$src/data/songs'))
				{
					final srcSong = '$src/data/songs/$songFolder';

					for (f in _listFiles(srcSong))
					{
						if (!f.endsWith('.json')) continue;
						try
						{
							final raw        = File.getContent('$srcSong/$f').trim();
							final diffs      : Map<String, funkin.data.Song.SwagSong> = new Map();
							final root       : Dynamic = Json.parse(raw);
							final cs         : Dynamic = root.song ?? root;
							final notesField = cs.notes;

							if (notesField != null && !Std.isOfType(notesField, Array))
							{
								for (diffKey in Reflect.fields(notesField))
								{
									final suffix = _codenameDiffSuffix(diffKey);
									diffs.set(suffix, CodenameConverter.convertChart(raw, diffKey));
									_log('  Converted: $songFolder [$diffKey → "$suffix"]');
								}
							}
							else
							{
								final diffLabel = f.replace('.json', '').toLowerCase();
								final suffix    = _codenameDiffSuffix(diffLabel);
								diffs.set(suffix, CodenameConverter.convertChart(raw, diffLabel));
								_log('  Converted: $songFolder [$diffLabel → "$suffix"]');
							}

							if (Lambda.count(diffs) == 0) continue;
							final first = diffs.exists('') ? diffs.get('') : diffs.iterator().next();
							LevelFile.saveAll(songFolder, diffs, null, first.song ?? songFolder, null);
						}
						catch (e) { _log('  Skip $f: $e'); }
					}
				}
			}

			_convertCodenameCharacters('$src/data/characters', '$dest/assets/data/characters');
			_copyDir('$src/images', '$dest/assets/images');
			_copyDir('$src/sounds', '$dest/assets/sounds');
			_copyDir('$src/music',  '$dest/assets/music');
			_mergeSongAudio('$src/songs', '$dest/assets/songs');

			_writeCodenameModJson(src, dest, modId);
			_log('Codename Engine import finished.');
			return true;
		}
		catch (e:Dynamic) { _log('Codename import error: $e'); return false; }
		#else
		return false;
		#end
	}

	function _codenameDiffSuffix(diffKey:String):String
	{
		return switch (diffKey.toLowerCase())
		{
			case 'normal': '';
			case 'easy':   '-easy';
			case 'hard':   '-hard';
			default:       '-$diffKey';
		};
	}

	function _convertCodenameCharacters(srcDir:String, destDir:String):Void
	{
		#if sys
		if (!FileSystem.exists(srcDir)) return;
		if (!FileSystem.exists(destDir)) FileSystem.createDirectory(destDir);
		for (f in _listFiles(srcDir))
		{
			if (!f.endsWith('.json')) continue;
			try
			{
				final charName  = f.replace('.json', '');
				final raw       = File.getContent('$srcDir/$f').trim();
				final converted = CodenameConverter.convertCharacter(raw, charName);
				File.saveContent('$destDir/$f', Json.stringify(converted, null, '\t'));
				_log('  Converted char: $charName');
			}
			catch (e) { _log('  Skip char $f: $e'); }
		}
		#end
	}

	function _writeCodenameModJson(src:String, dest:String, modId:String):Void
	{
		#if sys
		var name = modId; var description = 'Imported from Codename Engine'; var author = '';
		try
		{
			final pack = '$src/pack.json';
			if (FileSystem.exists(pack))
			{
				final d : Dynamic = Json.parse(File.getContent(pack));
				name   = Reflect.field(d, 'name')   ?? modId;
				author = Reflect.field(d, 'author') ?? '';
			}
		}
		catch (_) {}

		final info : Dynamic = {
			id: modId, name: name, description: description,
			author: author, version: '1.0.0', priority: 0,
			color: 0xFF44AAFF, website: '', enabled: true, startupDefault: false
		};
		File.saveContent('$dest/mod.json', Json.stringify(info, null, '\t'));
		#end
	}

	// ── Generic importer ──────────────────────────────────────────────────────

	function _importGeneric(src:String, dest:String, modId:String):Bool
	{
		#if sys
		try
		{
			_copyDir(src, dest);
			if (!FileSystem.exists('$dest/mod.json'))
			{
				final info : Dynamic = {
					id: modId, name: modId, description: 'Imported mod',
					author: '', version: '1.0.0', priority: 0,
					color: 0xFF888888, website: '', enabled: true, startupDefault: false
				};
				File.saveContent('$dest/mod.json', Json.stringify(info, null, '\t'));
			}
			_log('Generic copy finished.');
			return true;
		}
		catch (e:Dynamic) { _log('Generic import error: $e'); return false; }
		#else
		return false;
		#end
	}

	// ── File helpers ──────────────────────────────────────────────────────────

	function _copyDir(src:String, dest:String):Void
	{
		#if sys
		if (!FileSystem.exists(src)) return;
		if (!FileSystem.exists(dest)) FileSystem.createDirectory(dest);
		for (entry in FileSystem.readDirectory(src))
		{
			final s = '$src/$entry';
			final d = '$dest/$entry';
			if (FileSystem.isDirectory(s)) _copyDir(s, d);
			else File.saveBytes(d, File.getBytes(s));
		}
		#end
	}

	function _mergeSongAudio(src:String, dest:String):Void
	{
		#if sys
		if (!FileSystem.exists(src)) return;
		for (song in FileSystem.readDirectory(src))
		{
			final s = '$src/$song';
			if (FileSystem.isDirectory(s)) _copyDir(s, '$dest/$song');
		}
		#end
	}

	function _listDirs(path:String):Array<String>
	{
		#if sys
		if (!FileSystem.exists(path)) return [];
		return [for (f in FileSystem.readDirectory(path)) if (FileSystem.isDirectory('$path/$f')) f];
		#else return []; #end
	}

	function _listFiles(path:String):Array<String>
	{
		#if sys
		if (!FileSystem.exists(path)) return [];
		return [for (f in FileSystem.readDirectory(path)) if (!FileSystem.isDirectory('$path/$f')) f];
		#else return []; #end
	}

	// ── Logging ───────────────────────────────────────────────────────────────

	function _log(msg:String):Void
	{
		_logs.push(msg);
		trace('[ModImport] $msg');
		final lines = _logs.slice(Std.int(Math.max(0, _logs.length - 8)));
		_progressTxt.text = lines.join('\n');
	}

	function _fail(msg:String):Void
	{
		final T = EditorTheme.current;
		_log('✗ $msg');
		_phase = ERROR;
		_statusTxt.text = '✗ $msg';
		_statusTxt.color = T.error;
		_hintTxt.text = '[Esc] Close';
	}

	// ── Close ─────────────────────────────────────────────────────────────────

	function _close():Void
	{
		try
		{
			if (_limeWindow != null)
			{
				_limeWindow.window.onTextInput.remove(_onText);
				_limeWindow.window.onDropFile.remove(_onDropFile);
			}
			FlxG.stage.removeEventListener(openfl.events.KeyboardEvent.KEY_DOWN, _onKeyDown);
		}
		catch (_) {}
		close();
	}

	override function destroy()
	{
		// Cancel any in-flight tweens on our sprites BEFORE super.destroy()
		// nukes them. If we don't, FlxTween's global manager will keep updating
		// them on the next frame and crash inside VarTween::update.
		FlxTween.cancelTweensOf(_bg);
		FlxTween.cancelTweensOf(_dropZoneBorder);

		if (cameras != null && cameras.length > 0)
		{
			final cam = cameras[0];
			if (cam != null) FlxG.cameras.remove(cam, true);
		}
		super.destroy();
	}
}

// ── Phase enum ────────────────────────────────────────────────────────────────
enum ImportPhase
{
	WAITING_PATH;
	IMPORTING;
	DONE;
	ERROR;
}
