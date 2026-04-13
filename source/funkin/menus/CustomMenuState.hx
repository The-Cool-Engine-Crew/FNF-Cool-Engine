package funkin.menus;

import flixel.*;
import flixel.effects.FlxFlicker;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.math.FlxMath;
import flixel.text.FlxText;
import flixel.tweens.*;
import flixel.util.*;
import funkin.scripting.StateScriptHandler;
import funkin.transitions.StateTransition;
import haxe.Json;
import ui.Alphabet;
import funkin.data.SaveData;

/**
 * CustomMenuState — Ejecuta en el juego cualquier menú creado con MenuEditor.
 *
 * Uso desde código Haxe:
 *   StateTransition.switchState(new CustomMenuState("my_custom_menu"));
 *
 * Uso desde HScript (assets/states/mainmenustate/override.hx):
 *   function onAccept() {
 *       StateTransition.switchState(new CustomMenuState("my_custom_menu"));
 *       return true; // cancela el comportamiento normal
 *   }
 *
 * Búsqueda de datos en orden:
 *   1. mods/{mod}/data/menus/{name}.json    (si hay mod activo)
 *   2. assets/data/menus/{name}.json
 *
 * ─── Acciones predefinidas (campo "action" del ítem) ─────────────────────────
 *   "play" / "storymode"  → StoryMenuState
 *   "freeplay"            → FreeplayState
 *   "options"             → OptionsMenuState
 *   "credits"             → CreditsState
 *   "back"                → estado anterior (backState)
 *   "exit"                → TitleState
 *   "menu:{nombre}"       → otro CustomMenuState con ese nombre
 *   (cualquier otra)      → se pasa al script via onAction(action, item)
 */
class CustomMenuState extends funkin.states.MusicBeatState
{
	// ─── Datos ────────────────────────────────────────────────────────────────
	var _menuName  : String;
	var _data      : CustomMenuData;
	var _backState : FlxState;

	// ─── Items ────────────────────────────────────────────────────────────────
	var _items     : Array<CustomMenuItemData> = [];  // solo items navegables
	var _curIdx    : Int = 0;

	/** Objetos Flixel creados para cada ítem navegable (mismo índice que _items). */
	var _alphabets : Array<Alphabet>  = [];
	var _sprites   : Array<FlxSprite> = [];

	// ─── Sprites de fondo ─────────────────────────────────────────────────────
	var _bgSprite  : FlxSprite;

	// ─── Estado ───────────────────────────────────────────────────────────────
	var _canMove        : Bool = false;
	var _selected       : Bool = false;
	var _musicStarted   : Bool = false;
	var _useAlphabet    : Bool = true;

	// ─── Cámara follow (como MainMenuState) ───────────────────────────────────
	var _camFollow : FlxObject;

	// ─────────────────────────────────────────────────────────────────────────
	//  Constructor
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * @param menuName   Nombre del menú (sin extensión) — busca en assets/data/menus/
	 * @param backState  Estado al que volver con BACK (null = TitleState)
	 */
	public function new(menuName:String, ?backState:FlxState)
	{
		super();
		_menuName  = menuName;
		_backState = backState;
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Create
	// ─────────────────────────────────────────────────────────────────────────

	override public function create() : Void
	{
		funkin.system.CursorManager.hide();
		persistentUpdate = persistentDraw = true;

		// ── Cargar datos ──────────────────────────────────────────────────────
		_data = _loadMenuData(_menuName);
		if (_data == null) {
			trace('[CustomMenuState] No se encontró "$_menuName" — usando fallback');
			_data = _fallbackData(_menuName);
		}

		// ── Fondo ──────────────────────────────────────────────────────────────
		_bgSprite = new FlxSprite(-80).makeGraphic(FlxG.width + 160, FlxG.height, _parseColor(_data.bgColor, 0xFF1A1A2E));

		if (_data.bgImage != null && _data.bgImage.trim() != "") {
			try {
				_bgSprite.loadGraphic(Paths.image(_data.bgImage));
				_bgSprite.setGraphicSize(Std.int(_bgSprite.width * 0.8));
				_bgSprite.updateHitbox();
			} catch (_) {}
		}
		_bgSprite.scrollFactor.x = 0;
		_bgSprite.scrollFactor.y = _data.bgScroll ? 0.18 : 0;
		_bgSprite.screenCenter();
		add(_bgSprite);

		// ── Cámara follow ─────────────────────────────────────────────────────
		_camFollow = new FlxObject(0, 0, 1, 1);
		add(_camFollow);

		// ── Título ────────────────────────────────────────────────────────────
		if (_data.title != null && _data.title.trim() != "") {
			var titleTxt = new FlxText(0, 20, FlxG.width, _data.title, 24);
			titleTxt.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, CENTER,
				FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			titleTxt.scrollFactor.set();
			add(titleTxt);
		}

		// ── Construir items navegables ─────────────────────────────────────────
		_buildItems();

		// ── Música ────────────────────────────────────────────────────────────
		_startMusic();

		// ── Scripts ───────────────────────────────────────────────────────────
		#if HSCRIPT_ALLOWED
		StateScriptHandler.init();
		StateScriptHandler.loadStateScripts('CustomMenuState', this);
		StateScriptHandler.setOnScripts('menuName', _menuName);
		StateScriptHandler.setOnScripts('menuData', _data);
		StateScriptHandler.callOnScripts('onCreate', []);
		#end

		// Animación de entrada — los ítems vienen desde abajo
		_enterAnimation();

		super.create();

		#if mobileC
		addTouchMenuControls(true, false);
		#end

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('postCreate', []);
		#end
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Build items
	// ─────────────────────────────────────────────────────────────────────────

	function _buildItems() : Void
	{
		_items     = [];
		_alphabets = [];
		_sprites   = [];

		for (item in (_data.items ?? [])) {
			if (!item.visible) continue;
			if (item.type == "Separator") {
				// Separador visual — no es navegable
				var line = new FlxSprite(40, 0).makeGraphic(FlxG.width - 80, 2, _parseColor(item.color, 0xFF333333));
				line.scrollFactor.x = 0; line.alpha = 0.5;
				add(line);
				continue;
			}
			_items.push(item);
		}

		_useAlphabet = _items.length > 0 && _items[0].type == "Alphabet";

		// Construir según tipo del primer ítem
		if (_useAlphabet) {
			_buildAlphabetItems();
		} else {
			_buildSpriteItems();
		}
	}

	/** Estilo MainMenu/FreePlay — usa ui.Alphabet con targetY. */
	function _buildAlphabetItems() : Void
	{
		for (i in 0..._items.length) {
			var it  = _items[i];
			var col = _parseColor(it.color, 0xFFFFFFFF);

			var al = new Alphabet(0, 0, it.label, it.bold ?? false);
			al.isMenuItem  = it.isMenuItem ?? true;
			al.targetY     = i;
			al.alpha       = it.alpha ?? 1.0;
			al.scrollFactor.set();

			if (it.x != 0) al.x = it.x;
			if (it.y != 0) al.y = it.y;

			add(al);
			_alphabets.push(al);
		}
		_changeSelection(0);
	}

	/** Estilo Button/Text — usa FlxSprite o FlxText con posición fija. */
	function _buildSpriteItems() : Void
	{
		var totalH   = _items.length * 56;
		var startY   = (FlxG.height - totalH) / 2;

		for (i in 0..._items.length) {
			var it  = _items[i];
			var ix  = it.x != 0 ? it.x : 0.0;
			var iy  = it.y != 0 ? it.y : startY + i * 56;
			var col = _parseColor(it.color, 0xFFFFFFFF);

			var spr = new FlxSprite(ix, iy);
			if (it.spritePath != null && it.spritePath.trim() != "") {
				try {
					spr.frames = Paths.getSparrowAtlas(it.spritePath);
					spr.animation.addByPrefix('idle',     it.label.toLowerCase() + ' idle',     24);
					spr.animation.addByPrefix('selected', it.label.toLowerCase() + ' selected', 24);
					spr.animation.play('idle');
				} catch (_) {
					spr.makeGraphic(300, 50, col);
				}
			} else {
				// FlxText como sprite (sin atlas)
				spr.makeGraphic(300, 50, 0x00000000);
				var lbl = new FlxText(ix, iy, 300, it.label, it.fontSize ?? 24);
				lbl.setFormat(Paths.font("vcr.ttf"), it.fontSize ?? 24, col, CENTER,
					FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				lbl.screenCenter(X);
				lbl.scrollFactor.set();
				add(lbl);
				_sprites.push(spr); // guarda spr aunque esté vacío para mantener índices
				continue;
			}
			spr.antialiasing = SaveData.data.antialiasing;
			spr.scrollFactor.set();
			add(spr);
			_sprites.push(spr);
		}
		_changeSelection(0);
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Enter animation
	// ─────────────────────────────────────────────────────────────────────────

	function _enterAnimation() : Void
	{
		_canMove = false;
		switch (_data.transition ?? "fade") {
			case "slide_left", "slide_right":
				FlxTween.tween(FlxG.camera, {x: 0}, 0.4, {
					ease: FlxEase.cubeOut,
					onComplete: function(_) { _canMove = true; }
				});
			default:
				FlxTween.tween(FlxG.camera, {zoom: FlxG.camera.zoom}, 0.4, {
					ease: FlxEase.cubeOut,
					onComplete: function(_) { _canMove = true; }
				});
		}
		// Simple tween de alpha para dar sensación de fade-in
		FlxG.camera.alpha = 0;
		FlxTween.tween(FlxG.camera, {alpha: 1}, 0.25, {
			onComplete: function(_) { _canMove = true; }
		});
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Update
	// ─────────────────────────────────────────────────────────────────────────

	override public function update(elapsed:Float) : Void
	{
		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onUpdate', [elapsed]);
		#end

		if (!_selected && _canMove) {
			if (controls.UP_P)   { FlxG.sound.play(Paths.sound('menus/scrollMenu')); _changeSelection(-1); }
			if (controls.DOWN_P) { FlxG.sound.play(Paths.sound('menus/scrollMenu')); _changeSelection(1);  }

			if (controls.ACCEPT) _onAccept();
			if (controls.BACK)   _onBack();
		}

		// Música fade in
		if (_musicStarted && FlxG.sound.music != null && FlxG.sound.music.volume < 0.7)
			FlxG.sound.music.volume += 0.5 * elapsed;

		super.update(elapsed);

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onUpdatePost', [elapsed]);
		#end
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Navigation
	// ─────────────────────────────────────────────────────────────────────────

	function _changeSelection(dir:Int = 0) : Void
	{
		if (_items.length == 0) return;
		_curIdx = (_curIdx + dir + _items.length) % _items.length;

		if (_useAlphabet) {
			for (i in 0..._alphabets.length) {
				_alphabets[i].targetY = i - _curIdx;
			}
		} else {
			for (i in 0..._sprites.length) {
				if (_sprites[i] != null) {
					_sprites[i].alpha = i == _curIdx ? 1.0 : 0.5;
					// Play idle/selected animations
					if (_sprites[i].animation.exists('selected'))
						_sprites[i].animation.play(i == _curIdx ? 'selected' : 'idle');
				}
			}
		}

		// Mueve la cámara como MainMenuState
		if (_useAlphabet && _alphabets.length > _curIdx) {
			var al = _alphabets[_curIdx];
			_camFollow.setPosition(al.getGraphicMidpoint().x, al.getGraphicMidpoint().y);
			FlxG.camera.follow(_camFollow, LOCKON, 0.06);
		}

		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onSelectionChanged', [_curIdx, _items[_curIdx].label]);
		#end
	}

	function _onAccept() : Void
	{
		if (_items.length == 0) return;

		#if HSCRIPT_ALLOWED
		var cancelled = StateScriptHandler.callOnScripts('onAccept', [_curIdx, _items[_curIdx].label]);
		if (cancelled) return;
		#end

		_selected = true;
		FlxG.sound.play(Paths.sound('menus/confirmMenu'));
		if (SaveData.data.flashing) FlxG.camera.flash(FlxColor.WHITE);

		var action = _items[_curIdx].action ?? "";
		var itemScript = _items[_curIdx].script ?? "";

		// Flickering igual que MainMenuState
		if (_useAlphabet && _alphabets.length > _curIdx) {
			FlxFlicker.flicker(_alphabets[_curIdx], 1, 0.06, false, false, function(_) {
				_dispatch(action, itemScript, _curIdx);
			});
		} else {
			FlxTween.tween(this, {}, 0.6, { onComplete: function(_) { _dispatch(action, itemScript, _curIdx); } });
		}
	}

	function _onBack() : Void
	{
		#if HSCRIPT_ALLOWED
		var cancelled = StateScriptHandler.callOnScripts('onBack', []);
		if (cancelled) return;
		#end
		FlxG.sound.play(Paths.sound('menus/cancelMenu'));
		if (_backState != null) StateTransition.switchState(_backState);
		else StateTransition.switchState(new MainMenuState());
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Action dispatch
	// ─────────────────────────────────────────────────────────────────────────

	function _dispatch(action:String, itemScript:String, idx:Int) : Void
	{
		// 1) Intentar itemScript HScript primero
		if (itemScript != null && itemScript.trim() != "") {
			#if HSCRIPT_ALLOWED
			try {
				var interp = new hscript.Interp();
				var parser = new hscript.Parser();
				funkin.scripting.ScriptAPI.expose(interp);
				interp.variables.set("StateTransition", StateTransition);
				interp.variables.set("FlxG",            FlxG);
				interp.variables.set("action",          action);
				interp.variables.set("menuName",        _menuName);
				interp.execute(parser.parseString(itemScript));
				return;
			} catch (e:Dynamic) {
				trace('[CustomMenuState] Script error: $e');
			}
			#end
		}

		// 2) Acciones predefinidas por nombre
		#if HSCRIPT_ALLOWED
		var scriptHandled = StateScriptHandler.callOnScripts('onAction', [action, idx, _items[idx]]);
		if (scriptHandled) return;
		#end

		_doDefaultAction(action);
	}

	function _doDefaultAction(action:String) : Void
	{
		switch (action.toLowerCase()) {
			case "play", "storymode":
				StateTransition.switchState(new StoryMenuState());
			case "freeplay":
				StateTransition.switchState(new FreeplayState());
			case "options":
				StateTransition.switchState(new funkin.menus.OptionsMenuState());
			case "credits":
				StateTransition.switchState(new CreditsState());
			case "back":
				_onBack();
			case "exit":
				StateTransition.switchState(new TitleState());
			case _ if (action.startsWith("menu:")):
				// menu:otro_menu → abre otro CustomMenuState
				var nextMenu = action.substr(5);
				StateTransition.switchState(new CustomMenuState(nextMenu, this));
			default:
				trace('[CustomMenuState] Acción desconocida: "$action" — maneja en script');
				_selected = false; // permite volver a navegar
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Music
	// ─────────────────────────────────────────────────────────────────────────

	function _startMusic() : Void
	{
		if (_data.music == null || _data.music.trim() == "") return;
		try {
			var path = _data.music;
			var snd = openfl.Assets.exists(path) ? openfl.Assets.getSound(path) : null;
			if (snd != null) {
				FlxG.sound.playMusic(snd, 0, true);
				_musicStarted = true;
			} else {
				// Intentar con Paths
				FlxG.sound.playMusic(Paths.music(_data.music), 0, true);
				_musicStarted = true;
			}
		} catch (_) {}
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Data loading
	// ─────────────────────────────────────────────────────────────────────────

	static function _loadMenuData(name:String) : CustomMenuData
	{
		var paths : Array<String> = [];

		#if sys
		// Mod override primero
		if (mods.ModManager.isActive()) {
			var mr = mods.ModManager.modRoot();
			paths.push('$mr/data/menus/$name.json');
			paths.push('$mr/assets/data/menus/$name.json');
		}
		paths.push('assets/data/menus/$name.json');

		for (p in paths) {
			if (sys.FileSystem.exists(p)) {
				try {
					var raw : CustomMenuData = cast Json.parse(sys.io.File.getContent(p));
					if (raw.items == null) raw.items  = [];
					if (raw.groups == null) raw.groups = [];
					trace('[CustomMenuState] Cargado: $p');
					return raw;
				} catch (e:Dynamic) {
					trace('[CustomMenuState] Error cargando $p: $e');
				}
			}
		}
		#end

		// Fallback openfl Assets
		var assetPath = 'assets/data/menus/$name.json';
		if (openfl.Assets.exists(assetPath)) {
			try {
				var raw : CustomMenuData = cast Json.parse(openfl.Assets.getText(assetPath));
				if (raw.items == null)  raw.items  = [];
				if (raw.groups == null) raw.groups = [];
				return raw;
			} catch (_) {}
		}

		return null;
	}

	static function _fallbackData(name:String) : CustomMenuData
	{
		return {
			name: name, title: name.toUpperCase(), bgColor: "0xFF1A1A2E", bgImage: "",
			bgScrollX: 0, bgScrollY: 0, music: "", transition: "fade", transitionCode: "",
			bgScroll: true, groups: [], items: [
				{label:"BACK", action:"back", type:"Alphabet", color:"0xFFAAAAAA", script:"",
				 visible:true, enabled:true, x:0, y:0, groupId:"main",
				 fontSize:24, bold:false, spritePath:"", animPath:"", animName:"idle",
				 scaleX:1, scaleY:1, alpha:1, isMenuItem:true}
			]
		};
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Helpers
	// ─────────────────────────────────────────────────────────────────────────

	static inline function _parseColor(hex:String, fallback:Int) : Int
	{
		if (hex == null || hex == "") return fallback;
		var v = Std.parseInt(hex); return v != null ? v : fallback;
	}

	// ─────────────────────────────────────────────────────────────────────────
	//  Expose to scripts
	// ─────────────────────────────────────────────────────────────────────────

	/** Navega al índice dado (callable desde scripts). */
	public function selectIndex(idx:Int) : Void { _changeSelection(idx - _curIdx); }

	/** Devuelve el label del ítem seleccionado. */
	public function getSelectedLabel() : String { return _items.length > 0 ? _items[_curIdx].label : ""; }

	/** Devuelve los datos del ítem en el índice dado. */
	public function getItem(idx:Int) : CustomMenuItemData { return _items[idx]; }

	/** Número de ítems navegables. */
	public function getItemCount() : Int { return _items.length; }

	override public function destroy() : Void
	{
		#if HSCRIPT_ALLOWED
		StateScriptHandler.callOnScripts('onDestroy', []);
		StateScriptHandler.clearStateScripts();
		#end
		super.destroy();
	}
}

// ─── Aliases para compatibilidad con MenuEditor JSON ──────────────────────────

typedef CustomMenuData     = funkin.debug.MenuEditorData;
typedef CustomMenuItemData = funkin.debug.MenuEditorItemData;
