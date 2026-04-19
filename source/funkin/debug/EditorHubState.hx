package funkin.debug;

import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.text.FlxText;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import flixel.util.FlxColor;
import funkin.transitions.StateTransition;
import funkin.states.MusicBeatState;

/**
 * EditorHubState — Central editor selection screen for the engine.
 *
 * ──────────────────────────────────────────────────────────────────────────
 * LAYOUT
 * ──────────────────────────────────────────────────────────────────────────
 *
 *  ┌─────────────────────────────────────────────────────────────────────┐
 *  │  EDITOR HUB  (fixed header — never scrolls)                         │
 *  │  Select a editor  •  [ENTER] Open  •  [ESC] Back                    │
 *  ├────────────────────────────────┬────────────────────────────────────┤  ← accent line
 *  │  ┌──────────────────────────┐  │  [ICON]                            │
 *  │  │ card 0  (scrollable)     │  │  Editor Name                       │ ← right info
 *  │  └──────────────────────────┘  │  Description text…                 │   panel (fixed)
 *  │  ┌──────────────────────────┐  │                                    │
 *  │  │ card 1                   │  │                                    │
 *  │  └──────────────────────────┘  │                                    │
 *  │  ┌──────────────────────────┐  │                                    │
 *  │  │ card 2                   │  │                                    │
 *  │  └──────────────────────────┘  │                                    │
 *  ├────────────────────────────────┴────────────────────────────────────┤
 *  │  UP/DOWN Navigate  ENTER Open  ESC Main Menu  WHEEL/DRAG Scroll     │
 *  └─────────────────────────────────────────────────────────────────────┘
 *           ↑                        ↑
 *  scrollable card list        white divider
 *  (own FlxCamera viewport)
 *
 * ──────────────────────────────────────────────────────────────────────────
 * SCROLL BEHAVIOUR
 * ──────────────────────────────────────────────────────────────────────────
 *  • Mouse wheel                    — scroll up / down
 *  • Click + drag (left panel only) — drag to scroll
 *  • UP / DOWN keys                 — navigate cards and auto-scroll into view
 *
 *  The card list uses a dedicated FlxCamera so the cards are automatically
 *  clipped to the scroll viewport. The header, divider, right panel, and
 *  footer are on the default camera and never move.
 *
 * ──────────────────────────────────────────────────────────────────────────
 * ADDING PREVIEW IMAGES TO CARDS
 * ──────────────────────────────────────────────────────────────────────────
 *  Edit EDITOR_IMAGES below. Each entry maps to the same index in
 *  EDITOR_NAMES.  Use the same path convention as Paths.image():
 *
 *      static var EDITOR_IMAGES:Array<String> = [
 *          "editors/char_preview",   // assets/images/editors/char_preview.png
 *          null,                     // null → shows icon placeholder
 *          ...
 *      ];
 *
 *  When non-null the image is loaded and scaled to fit the card's preview
 *  zone (left third of the card), preserving aspect ratio.
 *
 * ──────────────────────────────────────────────────────────────────────────
 * ACCESS
 * ──────────────────────────────────────────────────────────────────────────
 *  MainMenuState → press [3] in Developer Mode.
 */
class EditorHubState extends MusicBeatState
{
	// ── Colour palette ────────────────────────────────────────────────────────
	static inline var C_BG:Int = 0xFF080810;
	static inline var C_ACCENT:Int = 0xFF00D9FF;
	static inline var C_TEXT:Int = 0xFFE0E0FF;
	static inline var C_SUBTEXT:Int = 0xFF8888AA;
	static inline var C_DIVIDER:Int = 0xFFFFFFFF;

	// ── Layout constants ──────────────────────────────────────────────────────

	/** Screen Y where the scrollable viewport starts (below the fixed header). */
	static inline var SCROLL_TOP:Int = 112;

	/** Screen height reserved for the footer hint bar. */
	static inline var SCROLL_BOTTOM:Int = 28;

	/**
	 * X position of the vertical white divider line.
	 * Everything to the left is the scrollable card list;
	 * everything to the right is the fixed info panel.
	 */
	static inline var DIVIDER_X:Int = 510;

	// ── Card geometry ─────────────────────────────────────────────────────────
	static inline var CARD_X:Int = 14;
	static inline var CARD_W:Int = 480;
	static inline var CARD_H:Int = 130;
	static inline var CARD_GAP:Int = 12;

	// ── Scroll ────────────────────────────────────────────────────────────────

	/** Pixels scrolled per mouse-wheel notch. */
	static inline var WHEEL_SPEED:Float = 38.0;

	// ── Per-editor metadata ───────────────────────────────────────────────────

	/** Left-border accent colour for each card (index = editor index). */
	static var EDITOR_ACCENTS:Array<Int> = [
		0xFF00D9FF, // Character Editor  — cyan
		0xFFFF3399, // Story Menu Editor — pink
		0xFFFFCC00, // Menu Editor       — yellow
		0xFF44FF88, // Sprite Editor     — green
		0xFFFF6644, // Chart Editor      — orange
		0xFF9966FF, // Dialogue Editor   — purple
		0xFFFFAA00, // Stage Editor      — gold
	];

	/** Unicode icon shown as placeholder when no preview image is provided. */
	static var EDITOR_ICONS:Array<String> = ["✦", "☰", "⊞", "⬡", "♩", "✎", "⬚"];

	static var EDITOR_NAMES:Array<String> = ["Character Editor", "Story Menu Editor", "Menu Editor", "Sprite Editor", "Note Skin Editor", "Script Console", "Node Menu Editor"];

	static var EDITOR_DESCS:Array<String> = [
		"Edit characters, animations, and offsets",
		"Create and edit Story Mode weeks with visual preview",
		"Design custom menus with objects and scripts",
		"Edit sprite sheets, create XML atlases, view frame data and hitboxes",
		"Create and edit note skins with visual preview",
		"Console for test things",
		"Edit your access to Menus, etc",
	];

	/**
	 * Optional preview image asset path for each editor card.
	 *
	 * Uses the same convention as Paths.image() — path relative to
	 * assets/images/ without extension.
	 *
	 *   Example: "editors/char_editor"  →  assets/images/editors/char_editor.png
	 *
	 * Set to null to show the icon placeholder instead.
	 */
	static var EDITOR_IMAGES:Array<String> = [
		'editors/character editor', // Character Editor  — e.g. replace with "editors/char_editor"
		null, // Story Menu Editor
		null, // Menu Editor
		null, // Sprite Editor
		null, // Note Skin Editor
		null, // Script Console
		null, // Node Menu Editor
	];

	// ── Internal state ────────────────────────────────────────────────────────
	var _cards:Array<EditorCard> = [];
	var _curSel:Int = 0;

	/** Current vertical scroll offset (world-space pixels). */
	var _scrollY:Float = 0.0;

	/** Maximum allowed scroll offset (computed after cards are built). */
	var _maxScroll:Float = 0.0;

	// Drag-scroll bookkeeping
	var _dragging:Bool = false;
	var _dragStartY:Float = 0.0;
	var _scrollAtDragStart:Float = 0.0;

	/**
	 * Dedicated camera that renders the scrollable card list.
	 *
	 * Screen region : x=0, y=SCROLL_TOP, w=DIVIDER_X, h=(viewable height)
	 * Scrolling     : camera.scroll.y = _scrollY
	 *
	 * The camera's viewport automatically clips cards that scroll above or
	 * below the visible area — no manual masking sprites needed.
	 */
	var _scrollCam:FlxCamera;

	// Right-panel info elements (rebuilt on each selection change)
	var _infoAccentBar:FlxSprite;
	var _infoIcon:FlxText;
	var _infoName:FlxText;
	var _infoDesc:FlxText;

	// ─────────────────────────────────────────────────────────────────────────
	// Lifecycle
	// ─────────────────────────────────────────────────────────────────────────

	override public function create():Void
	{
		super.create();

		// ── Background ────────────────────────────────────────────────────────
		var bg = new FlxSprite(0, 0);
		bg.makeGraphic(FlxG.width, FlxG.height, C_BG);
		bg.scrollFactor.set();
		add(bg);

		_buildGrid(); // subtle decorative grid

		// ── Scroll camera (left-panel viewport) ───────────────────────────────
		var viewH = FlxG.height - SCROLL_TOP - SCROLL_BOTTOM;
		_scrollCam = new FlxCamera(0, SCROLL_TOP, DIVIDER_X, viewH);
		_scrollCam.bgColor = FlxColor.TRANSPARENT;
		FlxG.cameras.add(_scrollCam, false);

		// ── Cards (rendered exclusively by _scrollCam) ────────────────────────
		_buildCards();

		// ── Fixed header (main camera) ────────────────────────────────────────
		var title = new FlxText(0, 18, FlxG.width, "EDITOR HUB", 32);
		title.alignment = CENTER;
		title.color = C_ACCENT;
		title.font = Paths.font("vcr.ttf");
		title.scrollFactor.set();
		add(title);

		var sub = new FlxText(0, title.y + title.height + 4, FlxG.width, "Select a editor  •  [ENTER] Open  •  [ESC] Back", 11);
		sub.alignment = CENTER;
		sub.color = C_SUBTEXT;
		sub.font = Paths.font("vcr.ttf");
		sub.scrollFactor.set();
		add(sub);

		// Thin horizontal accent line separating header from scroll area
		var hLine = new FlxSprite(0, SCROLL_TOP - 4);
		hLine.makeGraphic(FlxG.width, 1, C_ACCENT);
		hLine.alpha = 0.30;
		hLine.scrollFactor.set();
		add(hLine);

		// ── Vertical white divider ────────────────────────────────────────────
		//
		// A 2-pixel white line running from below the header accent line to the
		// bottom of the screen, separating the card list from the info panel.
		var divider = new FlxSprite(DIVIDER_X, SCROLL_TOP - 4);
		divider.makeGraphic(2, FlxG.height - SCROLL_TOP + 4, C_DIVIDER);
		divider.alpha = 0.55;
		divider.scrollFactor.set();
		add(divider);

		// ── Right info panel (fixed, main camera) ─────────────────────────────
		_buildInfoPanel();

		// ── Footer hint ───────────────────────────────────────────────────────
		var hint = new FlxText(0, FlxG.height - 22, FlxG.width, "UP/DOWN  Navigate    ENTER  Open    ESC  Main Menu    WHEEL / DRAG  Scroll", 10);
		hint.alignment = CENTER;
		hint.color = C_SUBTEXT;
		hint.font = Paths.font("vcr.ttf");
		hint.scrollFactor.set();
		add(hint);

		// ── Initial state ─────────────────────────────────────────────────────
		_updateSelection(0, true);
		FlxG.camera.fade(FlxColor.BLACK, 0.25, true);
	}

	override public function destroy():Void
	{
		FlxG.cameras.remove(_scrollCam);
		super.destroy();
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Decorative grid
	// ─────────────────────────────────────────────────────────────────────────

	function _buildGrid():Void
	{
		var cols = 20;
		var rows = 12;
		var cw = FlxG.width / cols;
		var rh = FlxG.height / rows;

		for (c in 0...cols)
		{
			var vl = new FlxSprite(Std.int(c * cw), 0);
			vl.makeGraphic(1, FlxG.height, 0x06FFFFFF);
			vl.scrollFactor.set();
			add(vl);
		}
		for (r in 0...rows)
		{
			var hl = new FlxSprite(0, Std.int(r * rh));
			hl.makeGraphic(FlxG.width, 1, 0x06FFFFFF);
			hl.scrollFactor.set();
			add(hl);
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Card list
	// ─────────────────────────────────────────────────────────────────────────

	function _buildCards():Void
	{
		for (i in 0...EDITOR_NAMES.length)
		{
			// Cards live in world-space starting at y = 0.
			// The scroll camera viewport maps them to the visible region on screen.
			var worldY:Float = i * (CARD_H + CARD_GAP);
			var imgPath:String = (i < EDITOR_IMAGES.length) ? EDITOR_IMAGES[i] : null;

			var card = new EditorCard(CARD_X, worldY, CARD_W, CARD_H, EDITOR_NAMES[i], EDITOR_DESCS[i], EDITOR_ICONS[i], EDITOR_ACCENTS[i], imgPath);

			// Assign exclusively to the scroll camera so the card is clipped
			// to the left-panel viewport and responds to camera.scroll.y.
			card.cameras = [_scrollCam];
			add(card);
			_cards.push(card);

			// Staggered fade-in entrance
			card.alpha = 0;
			var capturedY = worldY;
			FlxTween.tween(card, {alpha: 1.0, y: capturedY}, 0.35, {
				startDelay: i * 0.06,
				ease: FlxEase.quartOut,
				onStart: function(_)
				{
					card.y = capturedY + 20;
				}
			});
		}

		// Maximum scroll = total list height minus the visible viewport height
		var totalH = EDITOR_NAMES.length * (CARD_H + CARD_GAP) - CARD_GAP;
		var viewH = FlxG.height - SCROLL_TOP - SCROLL_BOTTOM;
		_maxScroll = Math.max(0.0, totalH - viewH);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Right info panel
	// ─────────────────────────────────────────────────────────────────────────

	function _buildInfoPanel():Void
	{
		var rx = DIVIDER_X + 28;
		var rw = FlxG.width - rx - 24;
		var ry = SCROLL_TOP + 24;

		// Coloured bar at the top of the panel (colour matches selected editor)
		_infoAccentBar = new FlxSprite(rx, ry);
		_infoAccentBar.makeGraphic(rw, 3, C_ACCENT);
		_infoAccentBar.scrollFactor.set();
		add(_infoAccentBar);

		// Large icon glyph
		_infoIcon = new FlxText(rx, ry + 18, rw, "", 52);
		_infoIcon.alignment = LEFT;
		_infoIcon.color = C_ACCENT;
		_infoIcon.font = Paths.font("vcr.ttf");
		_infoIcon.scrollFactor.set();
		add(_infoIcon);

		// Editor name
		_infoName = new FlxText(rx, ry + 82, rw, "", 20);
		_infoName.alignment = LEFT;
		_infoName.color = C_TEXT;
		_infoName.font = Paths.font("vcr.ttf");
		_infoName.scrollFactor.set();
		add(_infoName);

		// Description
		_infoDesc = new FlxText(rx, ry + 116, rw, "", 11);
		_infoDesc.alignment = LEFT;
		_infoDesc.color = C_SUBTEXT;
		_infoDesc.font = Paths.font("vcr.ttf");
		_infoDesc.scrollFactor.set();
		add(_infoDesc);
	}

	/** Refreshes the right info panel to reflect the currently selected editor. */
	function _refreshInfoPanel(idx:Int):Void
	{
		var accent:FlxColor = FlxColor.fromInt(EDITOR_ACCENTS[idx]);
		var rw = FlxG.width - (DIVIDER_X + 28) - 24;

		_infoAccentBar.makeGraphic(rw, 3, accent);
		_infoIcon.text = EDITOR_ICONS[idx];
		_infoIcon.color = accent;
		_infoName.text = EDITOR_NAMES[idx];
		_infoDesc.text = EDITOR_DESCS[idx];

		// Brief fade-in to signal the panel updated
		_infoIcon.alpha = 0.0;
		_infoName.alpha = 0.0;
		_infoDesc.alpha = 0.0;
		FlxTween.tween(_infoIcon, {alpha: 1.0}, 0.18, {ease: FlxEase.quartOut});
		FlxTween.tween(_infoName, {alpha: 1.0}, 0.18, {ease: FlxEase.quartOut, startDelay: 0.04});
		FlxTween.tween(_infoDesc, {alpha: 1.0}, 0.18, {ease: FlxEase.quartOut, startDelay: 0.08});
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Update
	// ─────────────────────────────────────────────────────────────────────────

	override public function update(elapsed:Float):Void
	{
		super.update(elapsed);

		_handleScrollInput();

		var prev = _curSel;

		if (controls.UP_P && _curSel > 0)
			_curSel--;
		if (controls.DOWN_P && _curSel < _cards.length - 1)
			_curSel++;

		if (_curSel != prev)
		{
			FlxG.sound.play(Paths.sound('menus/scrollMenu'));
			_updateSelection(_curSel);
			_ensureCardVisible(_curSel);
		}

		if (controls.ACCEPT)
		{
			FlxG.sound.play(Paths.sound('menus/confirmMenu'));
			_cards[_curSel].pulse(() -> _openEditor(_curSel));
		}

		if (controls.BACK)
		{
			FlxG.sound.play(Paths.sound('menus/cancelMenu'));
			StateTransition.switchState(new funkin.menus.MainMenuState());
		}
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Scroll input
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Handles mouse-wheel and click-drag scrolling for the left card panel.
	 *
	 * Drag detection is limited to mouse.x < DIVIDER_X so interacting with
	 * the right info panel does not accidentally scroll the card list.
	 *
	 * The final _scrollY value is applied directly to _scrollCam.scroll.y so
	 * the FlxCamera viewport clips the cards automatically.
	 */
	function _handleScrollInput():Void
	{
		// Mouse wheel
		var wheel = FlxG.mouse.wheel;
		if (wheel != 0)
			_scrollY = _clampScroll(_scrollY - wheel * WHEEL_SPEED);

		// Click-drag (left panel only)
		var mx = FlxG.mouse.screenX;
		var my = FlxG.mouse.screenY;

		if (FlxG.mouse.justPressed && mx < DIVIDER_X && my > SCROLL_TOP)
		{
			_dragging = true;
			_dragStartY = my;
			_scrollAtDragStart = _scrollY;
		}

		if (_dragging)
		{
			if (FlxG.mouse.pressed)
				_scrollY = _clampScroll(_scrollAtDragStart + (_dragStartY - my));
			else
				_dragging = false;
		}

		// Push scroll value into the camera
		_scrollCam.scroll.y = _scrollY;
	}

	inline function _clampScroll(v:Float):Float
		return Math.max(0.0, Math.min(v, _maxScroll));

	/**
	 * Adjusts _scrollY so that the card at `idx` is fully inside the viewport.
	 * Called after keyboard UP/DOWN navigation changes the selection.
	 */
	function _ensureCardVisible(idx:Int):Void
	{
		var viewH = FlxG.height - SCROLL_TOP - SCROLL_BOTTOM;
		var cardTop = idx * (CARD_H + CARD_GAP);
		var cardBot = cardTop + CARD_H;

		if (cardTop < _scrollY)
			_scrollY = _clampScroll(cardTop - 6.0);
		else if (cardBot > _scrollY + viewH)
			_scrollY = _clampScroll(cardBot - viewH + 6.0);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Selection
	// ─────────────────────────────────────────────────────────────────────────

	function _updateSelection(idx:Int, instant:Bool = false):Void
	{
		for (i in 0..._cards.length)
			_cards[i].setSelected(i == idx, instant);
		_curSel = idx;
		_refreshInfoPanel(idx);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Open editor
	// ─────────────────────────────────────────────────────────────────────────

	function _openEditor(idx:Int):Void
	{
		FlxG.camera.fade(FlxColor.BLACK, 0.22, false, function()
		{
			switch (idx)
			{
				case 0:
					StateTransition.switchState(new funkin.menus.CharacterSelectorState());
				case 1:
					StateTransition.switchState(new funkin.debug.editors.StoryMenuEditor());
				case 2:
					StateTransition.switchState(new funkin.debug.editors.MenuEditor());
				case 3:
					StateTransition.switchState(new funkin.debug.editors.SpriteEditorState());
				case 4:
					//trace('Note Skin Editor not implemented yet!');
					StateTransition.switchState(new funkin.debug.editors.NoteSkinEditorState());
				case 5:
					StateTransition.switchState(new funkin.debug.ScriptConsoleState());
				case 6:
					StateTransition.switchState(new funkin.debug.editors.NodeMenuEditor());
				default:
					StateTransition.switchState(new funkin.menus.MainMenuState());
			}
		});
	}
}

// =============================================================================
// EditorCard
// =============================================================================

/**
 * A single row in the EditorHub card list.
 *
 *  ┌──────────────────────────────────────────────────────────────────────┐
 *  │▌  ┌─────────────────┐  Editor Name  (14 pt)                         │
 *  │▌  │ preview image   │  Short description…  (10 pt, muted)           │
 *  │▌  │ OR icon glyph   │                                               │
 *  │▌  └─────────────────┘                                               │
 *  └──────────────────────────────────────────────────────────────────────┘
 *   ↑
 *   3 px accent border (colour from EDITOR_ACCENTS)
 *
 * ──────────────────────────────────────────────────────────────────────────
 * Adding a preview image
 * ──────────────────────────────────────────────────────────────────────────
 *  Pass a non-null `imagePath` (same format as Paths.image()).  The image is
 *  loaded via loadGraphic() and down-scaled to fit the PREVIEW_W × card-height
 *  area while preserving aspect ratio.  Pass null to use the icon glyph.
 */
class EditorCard extends flixel.group.FlxSpriteGroup
{
	/**
	 * Width of the left preview / icon zone inside the card.
	 * Chosen so the usable area (PREVIEW_W - 8) × (CARD_H - 12)
	 * matches a 16:9 ratio  →  210 × 118 ≈ 16:9.
	 */
	static inline var PREVIEW_W:Int = 218;

	var _bg:FlxSprite;
	var _preview:FlxSprite; // non-null when a preview image is loaded
	var _icon:FlxText; // icon glyph fallback (used when _preview is null)
	var _name:FlxText;
	var _desc:FlxText;
	var _cw:Int;
	var _ch:Int;
	var _selected:Bool = false;

	public function new(cx:Float, cy:Float, cw:Int, ch:Int, name:String, desc:String, icon:String, accent:Int, ?imagePath:String)
	{
		super(cx, cy);
		_cw = cw;
		_ch = ch;

		// Card background
		_bg = new FlxSprite(0, 0);
		_bg.makeGraphic(cw, ch, 0xFF141426);
		add(_bg);

		// Left accent border (3 px wide, full card height)
		var border = new FlxSprite(0, 0);
		border.makeGraphic(3, ch, accent);
		add(border);

		// Preview zone — image or icon placeholder
		if (imagePath != null)
		{
			// Load the image and scale it to fit the preview area
			_preview = new FlxSprite(8, 6);
			_preview.loadGraphic(Paths.image(imagePath));

			var sx = (PREVIEW_W - 8) / _preview.frameWidth;
			var sy = (ch - 12) / _preview.frameHeight;
			var s = Math.min(sx, sy);
			_preview.setGraphicSize(Std.int(_preview.frameWidth * s), Std.int(_preview.frameHeight * s));
			_preview.updateHitbox();
			add(_preview);
		}
		else
		{
			// Dark inset box behind the icon glyph
			var iconBg = new FlxSprite(8, 6);
			iconBg.makeGraphic(PREVIEW_W - 8, ch - 12, 0xFF0A0A18);
			add(iconBg);

			// Icon glyph vertically centred in the inset box
			_icon = new FlxText(8, 0, PREVIEW_W - 8, icon, 34);
			_icon.alignment = CENTER;
			_icon.color = FlxColor.fromInt(accent);
			_icon.font = Paths.font("vcr.ttf");
			_icon.y = 6 + ((ch - 12) - Std.int(_icon.height)) * 0.5;
			add(_icon);
		}

		// Text area to the right of the preview zone
		var textX = PREVIEW_W + 14;
		var textW = cw - textX - 10;

		_name = new FlxText(textX, 16, textW, name, 14);
		_name.color = 0xFFE0E0FF;
		_name.font = Paths.font("vcr.ttf");
		add(_name);

		_desc = new FlxText(textX, _name.y + _name.height + 6, textW, desc, 10);
		_desc.color = 0xFF8888AA;
		_desc.font = Paths.font("vcr.ttf");
		add(_desc);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Selection
	// ─────────────────────────────────────────────────────────────────────────

	public function setSelected(sel:Bool, instant:Bool = false):Void
	{
		if (_selected == sel && !instant)
			return;
		_selected = sel;

		var targetBg:Int = sel ? 0xFF1C1C38 : 0xFF141426;
		var targetAlpha:Float = sel ? 1.0 : 0.52;

		if (instant)
		{
			_bg.makeGraphic(_cw, _ch, targetBg);
			if (_icon != null)
				_icon.alpha = targetAlpha;
			if (_preview != null)
				_preview.alpha = targetAlpha;
			_name.alpha = targetAlpha;
			_desc.alpha = targetAlpha;
		}
		else
		{
			FlxTween.color(_bg, 0.13, FlxColor.fromInt(_bg.color), FlxColor.fromInt(targetBg));
			if (_icon != null)
				FlxTween.tween(_icon, {alpha: targetAlpha}, 0.13);
			if (_preview != null)
				FlxTween.tween(_preview, {alpha: targetAlpha}, 0.13);
			FlxTween.tween(_name, {alpha: targetAlpha}, 0.13);
			FlxTween.tween(_desc, {alpha: targetAlpha}, 0.13);
		}

		// Subtle scale-up on selection
		var sc = sel ? 1.015 : 1.0;
		if (!instant)
			FlxTween.tween(this.scale, {x: sc, y: sc}, 0.15, {ease: FlxEase.quartOut});
		else
			scale.set(sc, sc);
	}

	// ─────────────────────────────────────────────────────────────────────────
	// Confirm pulse animation
	// ─────────────────────────────────────────────────────────────────────────

	/**
	 * Squish-and-bounce animation played when the user confirms a selection.
	 * Calls `onDone` after the animation finishes so the state can transition.
	 */
	public function pulse(onDone:Void->Void):Void
	{
		FlxTween.tween(this.scale, {x: 0.96, y: 0.96}, 0.07, {
			ease: FlxEase.quartIn,
			onComplete: function(_)
			{
				FlxTween.tween(this.scale, {x: 1.06, y: 1.06}, 0.10, {
					ease: FlxEase.quartOut,
					onComplete: function(_)
					{
						if (onDone != null)
							onDone();
					}
				});
			}
		});
	}
}
