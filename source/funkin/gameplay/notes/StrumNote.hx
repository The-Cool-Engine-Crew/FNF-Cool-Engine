package funkin.gameplay.notes;

import flixel.FlxSprite;
import flixel.FlxG;
import funkin.gameplay.PlayState;
import lime.utils.Assets;
import funkin.gameplay.PlayStateConfig;

using StringTools;

class StrumNote extends FlxSprite
{
	public var noteID:Int = 0;

	/**
	 * Posición X de referencia para el posicionamiento de notas — igual a
	 * `baseX + offsetX` del StrumState, sin modificadores visuales (drunk, tipsy…).
	 * Actualizado cada frame por ModChartManager.applyAllStates().
	 * Cuando no hay modchart activo mantiene el valor del constructor.
	 */
	public var logicalX:Float = 0.0;

	/**
	 * Posición Y de referencia para el posicionamiento de notas — igual a
	 * `baseY + offsetY` del StrumState, sin modificadores visuales.
	 */
	public var logicalY:Float = 0.0;

	var animArrow:Array<String> = ['LEFT', 'DOWN', 'UP', 'RIGHT'];

	// ── Estado de skin ────────────────────────────────────────────────────

	/** true si la skin tiene isPixel:true. */
	private var _isPixelSkin:Bool = false;

	/**
	 * Mapa animName → [offsetX, offsetY] construido desde la skin activa.
	 * Puede tener entradas para 'pressed' y/o 'confirm'.
	 * Si no hay entrada para una animación, no se aplica ningún offset extra.
	 */
	private var _animOffsets:Map<String, Array<Float>> = new Map();

	/**
	 * Cache animList: animName → [offsetX, offsetY, flipX:0|1, flipY:0|1].
	 * Construido por loadSkin() cuando skinData.animList != null.
	 * Usado en playAnim() para aplicar offsets y flipX al estilo personaje.
	 */
	private var _animListData:Map<String, Array<Float>> = null;

	/** flipX base del strum (antes de aplicar per-anim flipX del animList). */
	private var _baseFlipX:Bool = false;

	/**
	 * Shader de colorización automática (colorAuto:true en skin.json).
	 * Se reutiliza entre recargas de skin para evitar crear un objeto nuevo en cada frame.
	 */
	private var _colorSwapShader:funkin.shaders.NoteColorSwapShader = null;

	/** Shader RGB por paleta (colorAuto + colorDirections). Mismo enfoque que NightmareVision. Mutex con _colorSwapShader. */
	private var _rgbShader:funkin.shaders.NoteRGBPaletteShader = null;

	public function new(x:Float, y:Float, noteID:Int = 0)
	{
		super(x, y);

		logicalX = x;
		logicalY = y;
		this.noteID = noteID;

		NoteSkinSystem.init();
		loadSkin(NoteSkinSystem.getCurrentSkinData());

		updateHitbox();
		scrollFactor.set();
		playAnim('static');
	}

	// ==================== CARGA DE SKIN ====================

	/**
	 * Carga la textura y las animaciones de strum desde un NoteSkinData.
	 *
	 * Sin ninguna referencia a PlayState.curStage.
	 * El índice noteID determina qué animaciones cargar (left/down/up/right).
	 */
	function loadSkin(skinData:NoteSkinSystem.NoteSkinData):Void
	{
		if (skinData == null)
			return;

		_isPixelSkin = skinData.isPixel == true;

		// Construir el mapa de offsets por animación desde la skin.
		// buildStrumOffsets() aplica la prioridad: offset del JSON > confirmOffset global > sin offset.
		_animOffsets = NoteSkinSystem.buildStrumOffsets(skinData, noteID);

		// ── Cargar textura de strums ────────────────────────────────────────────
		// Prioridad: strumsTexture > texture
		var tex = NoteSkinSystem.getStrumsTexture(skinData.name);
		// FunkinSprite en StrumNote (FlxSprite) no es posible directamente;
		// si el tipo es funkinsprite, fallback a texture principal.
		if (NoteSkinSystem.isFunkinSpriteType(tex))
		{
			trace('[StrumNote] FunkinSprite type detectado — fallback a texture principal (StrumNote es FlxSprite)');
			tex = skinData.texture;
		}
		frames = NoteSkinSystem.loadSkinFrames(tex, skinData.folder);

		// BUGFIX CRÍTICO: si frames sigue siendo null aquí (asset faltante, XML roto, etc.)
		// el sprite se renderizará en el primer frame de PlayState con frame=null
		// → FlxDrawQuadsItem::render line 119 crash.
		// makeGraphic() crea un BitmapData de 1x1 garantizado que evita el crash.
		// El sprite quedará invisible (scale 0.7 → 0.7×0.7 px) pero el juego no crashea.
		if (frames == null)
		{
			trace('[StrumNote] WARN: frames null para skin "${skinData.name}" noteID=$noteID — usando placeholder para evitar crash');
			makeGraphic(Std.int(Note.swagWidth), Std.int(Note.swagWidth), 0x00000000);
		}

		var noteScale = tex.scale != null ? tex.scale : 1.0;
		// BUG C FIX: si loadAtlas() cayó al fallback Default, no aplicar la escala
		// del skin custom sobre la textura incorrecta → strums gigantes.
		if (NoteSkinSystem.lastLoadFellBack)
			noteScale = 0.7;
		// BUGFIX: usar scale.set() directo en lugar de setGraphicSize(width*scale)
		// que usaría el hitbox stale si loadSkin() se llamara de nuevo (recarga de skin).
		scale.set(noteScale, noteScale);
		updateHitbox();

		antialiasing = tex.antialiasing != null ? tex.antialiasing : !_isPixelSkin;

		// ── Cargar animaciones ────────────────────────────────────────────
		// Prioridad: animList (estilo personaje) → campo animations (legacy)
		var i = Std.int(Math.abs(noteID));

		// ── Sistema animList ─────────────────────────────────────────────
		if (skinData.animList != null && skinData.animList.length > 0)
		{
			_animListData = new Map();
			for (entry in skinData.animList)
			{
				if (entry == null || entry.name == null || entry.prefix == null) continue;
				// Solo cargar entradas de strum: static/pressed/confirm
				if (entry.name != "static" && entry.name != "pressed" && entry.name != "confirm") continue;
				// Filtrar por dirección: noteID coincide o null/negativo = todas las dirs
				var entryDir:Null<Int> = entry.noteID;
				if (entryDir != null && entryDir >= 0 && entryDir != i) continue;

				var fps:Int  = entry.fps      != null ? entry.fps
				             : entry.framerate != null ? Std.int(entry.framerate) : 24;
				var loop:Bool = (entry.name == "static")
				             ? (entry.loop != null ? entry.loop : (entry.looped != null ? entry.looped : true))
				             : false; // pressed/confirm NO deben hacer loop

				if (entry.indices != null && entry.indices.length > 0)
					animation.add(entry.name, entry.indices, fps, loop);
				else
					animation.addByPrefix(entry.name, entry.prefix, fps, loop);

				// Cache offset/flipX para playAnim()
				var ox:Float = (entry.offsets != null && entry.offsets.length > 0) ? entry.offsets[0] : 0.0;
				var oy:Float = (entry.offsets != null && entry.offsets.length > 1) ? entry.offsets[1] : 0.0;
				var fx:Float = entry.flipX == true ? 1.0 : 0.0;
				var fy:Float = entry.flipY == true ? 1.0 : 0.0;
				_animListData.set(entry.name, [ox, oy, fx, fy]);
			}
			_baseFlipX = this.flipX;
		}

		// ── Sistema legacy (si no hay animList o como respaldo) ───────────
		var anims = skinData.animations;
		if (anims != null && !animation.exists("static"))
		{
			var strumKeys   = ["strumLeft",        "strumDown",        "strumUp",        "strumRight"];
			var pressKeys   = ["strumLeftPress",   "strumDownPress",   "strumUpPress",   "strumRightPress"];
			var confirmKeys = ["strumLeftConfirm", "strumDownConfirm", "strumUpConfirm", "strumRightConfirm"];

			var staticDef  = NoteSkinSystem.resolveAnimDef(anims, [strumKeys[i],   "strum",         "allStrum"]);
			var pressDef   = NoteSkinSystem.resolveAnimDef(anims, [pressKeys[i],   "strumPress",    "allStrumPress"]);
			var confirmDef = NoteSkinSystem.resolveAnimDef(anims, [confirmKeys[i], "strumConfirm",  "allStrumConfirm"]);

			NoteSkinSystem.addAnimToSprite(this, 'static',  staticDef);
			NoteSkinSystem.addAnimToSprite(this, 'pressed', pressDef,   false);
			NoteSkinSystem.addAnimToSprite(this, 'confirm', confirmDef, false);
		}

		// Fallback si no se definió animación estática
		if (!animation.exists('static'))
		{
			trace('[StrumNote] "static" no encontrada en skin "${skinData.name}" para noteID $noteID — cargando defaults');
			loadDefaultStrumAnimations();
		}

		// FIX: aplicar shader de colorización automática si la skin lo pide.
		// Antes esta función terminaba aquí sin tocar el shader, así que
		// `colorAuto:true` en skin.json nunca tenía efecto en los strums.
		_applyShaderForSkin(skinData);
	}

	/**
	 * Aplica el shader correcto al strum según la skin activa.
	 *
	 * Prioridad (mismo orden que Note.hx para consistencia visual):
	 *   1. colorAuto + colorDirections → NoteRGBPaletteShader (enfoque NightmareVision)
	 *   2. colorAuto + colorHSV        → NoteColorSwapShader  (HSV shift, fallback)
	 *   3. sin colorAuto               → sin shader
	 */
	function _applyShaderForSkin(skinData:NoteSkinSystem.NoteSkinData):Void
	{
		if (skinData != null && skinData.colorAuto == true)
		{
			final dir = noteID % 4;

			// PRIORIDAD 1: colorDirections → RGB palette shader (igual que NightmareVision).
			// Reemplaza canales R/G/B de la textura con colores reales por dirección.
			if (skinData.colorDirections != null && dir < skinData.colorDirections.length)
			{
				final cd = skinData.colorDirections[dir];
				// GC FIX: reutilizar shader entre recargas de skin.
				if (_rgbShader == null)
					_rgbShader = new funkin.shaders.NoteRGBPaletteShader();
				_rgbShader.setColors(cd.r, cd.g, cd.b);
				_colorSwapShader = null;
				shader = _rgbShader;
				return;
			}

			// PRIORIDAD 2: colorHSV → HSV shift (fallback cuando no hay colorDirections).
			final mult = (skinData.colorMult != null) ? skinData.colorMult : 1.0;
			if (_colorSwapShader == null)
				_colorSwapShader = new funkin.shaders.NoteColorSwapShader(dir, mult, null);
			else
			{
				_colorSwapShader.setDirection(dir, null);
				_colorSwapShader.intensity = mult;
			}
			_rgbShader = null;
			shader = _colorSwapShader;
		}
		else
		{
			_colorSwapShader = null;
			_rgbShader = null;
			shader = null;
		}
	}

	/** Recarga la skin en un strum existente (útil en rewind para corregir scale). */
	public function reloadSkin(skinData:NoteSkinSystem.NoteSkinData):Void
	{
		loadSkin(skinData);
		animation.play('static');
		centerOffsets();
	}

	function loadDefaultStrumAnimations():Void
	{
		var i = Std.int(Math.abs(noteID));
		animation.addByPrefix('static', 'arrow' + animArrow[i]);
		animation.addByPrefix('pressed', animArrow[i].toLowerCase() + ' press', 24, false);
		animation.addByPrefix('confirm', animArrow[i].toLowerCase() + ' confirm', 24, false);
	}

	// ==================== ANIMACIÓN ====================

	/**
	 * Reproduce una animación de forma segura.
	 * Aplica el offset -13,-13 al confirm si la skin lo requiere (confirmOffset:true).
	 * centerOffsets() siempre resetea el offset, por lo que el ajuste se re-aplica
	 * en cada llamada a confirm para mantener la posición correcta.
	 */
	public function playAnim(animName:String, force:Bool = false):Void
	{
		if (animation == null)
			return;

		animation.play(animName, force);
		centerOffsets();

		// ── animList: offsets + flipX al estilo personaje ─────────────────
		if (_animListData != null)
		{
			var data = _animListData.get(animName);
			if (data != null)
			{
				offset.x += data[0];
				offset.y += data[1];
				// flipX: XOR con el base igual que Character.hx
				var animFlipX:Bool = data[2] > 0.5;
				this.flipX = _baseFlipX != animFlipX;
				if (data[3] > 0.5) this.flipY = !this.flipY;
			}
			else
			{
				// Sin datos específicos → restaurar flipX base
				this.flipX = _baseFlipX;
			}
			return;
		}

		// ── Sistema legacy: offset de la skin para esta animación ─────────
		var off = _animOffsets.get(animName);
		if (off != null)
		{
			offset.x += off[0];
			offset.y += off[1];
		}
	}

	override function update(elapsed:Float):Void
	{
		super.update(elapsed);

		// Auto-reset confirm → static cuando termina la animación
		if (animation.curAnim != null && animation.curAnim.name == 'confirm' && animation.curAnim.finished)
		{
			playAnim('static');
		}
	}
}
