package funkin.gameplay.notes;

import lime.utils.Assets;
import funkin.gameplay.PlayState;
import flixel.FlxSprite;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.FlxG;
import funkin.data.Conductor;
import funkin.gameplay.PlayStateConfig;
import animationdata.FunkinSprite;
import funkin.data.SaveData;

using StringTools;

class Note extends FlxSprite
{
	public var strumTime:Float = 0;
	public var mustPress:Bool = false;
	public var noteData:Int = 0;
	public var canBeHit:Bool = false;
	public var tooLate:Bool = false;
	public var wasGoodHit:Bool = false;
	public var prevNote:Note;
	public var sustainLength:Float = 0;
	public var isSustainNote:Bool = false;

	/**
	 * true si esta pieza de sustain es la cola (holdend). false = hold piece o nota normal.
	 * Se asigna en setupSustainNote() y se resetea en recycle().
	 * NoteManager lo usa en updateNotePosition() para detectar el tail cap sin depender
	 * de curAnim?.name, que puede ser null por un frame durante transiciones de animación
	 * y causar el bug de "flash de holdend" donde el scale.y de tail se aplica incorrectamente
	 * a una pieza hold body por un frame.
	 */
	public var isTailCap:Bool = false;

	/** Scale.y base de la pieza de sustain, calculado en setupSustainNote().
	 *  NoteManager lo usa en la compensacion de rotacion sin acumulacion:
	 *    note.scale.y = sustainBaseScaleY / cos(deformAngle)
	 */
	public var sustainBaseScaleY:Float = 1.0;

	// ── Speed-transition lerp state (escrito por NoteManager) ─────────────
	/** Y de partida cuando empieza una transición de scroll speed. -1 = sin transición. */
	public var _lerpFromY:Float       = -1.0;
	/** scale.y de partida de este sustain al inicio de la transición. */
	public var _lerpFromScaleY:Float  = -1.0;
	/** Progreso 0→1 del lerp de velocidad. 1.0 = sin transición activa. */
	public var _lerpT:Float           = 1.0;

	public var noteScore:Float = 1;
	public var noteRating:String = 'sick';

	public var strumsGroupIndex:Int = 0;

	/** Tipo de nota personalizado. "" / "normal" = normal. */
	public var noteType:String = '';

	public static var swagWidth:Float = 160 * 0.7;
	public static var PURP_NOTE:Int = 0;
	public static var BLUE_NOTE:Int = 1;
	public static var GREEN_NOTE:Int = 2;
	public static var RED_NOTE:Int = 3;

	var animArrows:Array<String> = ['purple', 'blue', 'green', 'red'];

	// ── Estado de skin ────────────────────────────────────────────────────

	/** Nombre de la skin actualmente cargada. Usado para detectar cambios en recycle(). */
	private var _loadedSkinName:String = '';

	/**
	 * Nombre de la skin cargada actualmente — solo lectura.
	 * NoteRenderer lo usa como clave de pool para garantizar que las notas
	 * del pool de skin "A" nunca se reciclen como notas de skin "B" sin
	 * pasar por loadSkin(), eliminando el bug de skin cross-contamination.
	 */
	public var loadedSkinName(get, never):String;
	inline function get_loadedSkinName():String return _loadedSkinName;

	/** Tipo con el que se cargó la skin: true=sustain, false=normal. Si cambia hay que recargar animaciones. */
	private var _loadedAsSustain:Bool = false;

	/** true si la skin cargada tiene isPixel:true. */
	private var isPixelNote:Bool = false;

	/** Escala aplicada al sprite, leída del JSON de skin. */
	private var _noteScale:Float = 1.0;

	/** Offset X extra para notas sustain, leído del JSON de skin. */
	private var _skinSustainOffset:Float = 0.0;

	/** Multiplicador de scale.y para hold chain, leído del JSON de skin. */
	public var _skinHoldStretch:Float = 1.0;

	/**
	 * Offset X/Y para notas scroll (cabeza), leído del campo `offset` de la
	 * animación de nota en el JSON de skin (e.g. "left": { "offset": [2, -4] }).
	 * Se aplica en NoteManager.updateNotePosition() a la posición calculada.
	 * 0.0 por defecto → sin efecto si la skin no define offsets de nota.
	 */
	public var noteOffsetX:Float = 0.0;

	public var noteOffsetY:Float = 0.0;

	// ── Cache de hit window ───────────────────────────────────────────────
	private var _lastSongPos:Float = -1;
	private var _hitWindowCache:Float = 0;

	/** Referencia directa al shader de glow para actualizar intensidad por proximidad. */
	private var _glowShader:funkin.shaders.NoteGlowShader = null;

	/** Shader de colorización automática (colorAuto:true en skin.json). Mutex con _glowShader. */
	private var _colorSwapShader:funkin.shaders.NoteColorSwapShader = null;

	/** Shader RGB por paleta (colorAuto + colorDirections). Mismo enfoque que NightmareVision. Mutex con _colorSwapShader y _glowShader. */
	private var _rgbShader:funkin.shaders.NoteRGBPaletteShader = null;

	/**
	 * Cache de datos de animList: animName → [offsetX, offsetY, flipX:0|1, flipY:0|1].
	 * Construido por loadSkin() cuando skinData.animList != null.
	 * Usado en _applyNoteAnim() para aplicar offsets y flipX al estilo personaje.
	 */
	private var _animListData:Map<String, Array<Float>> = null;

	/** Distancia (ms) dentro de la safe zone en la que el glow alcanza su máximo.
	 *  Igual que FPS Plus: el glow se activa exactamente cuando canBeHit = true
	 *  (dentro de safeZoneOffset), y hace flash total en los últimos 60 ms. */
	static inline final GLOW_PEAK_MS:Float = 60.0;

	public function new(strumTime:Float, noteData:Int, ?prevNote:Note, ?sustainNote:Bool = false, ?mustHitNote:Bool = false)
	{
		super();

		if (prevNote == null)
			prevNote = this;
		this.prevNote = prevNote;
		isSustainNote = sustainNote;
		this.mustPress = mustHitNote;

		// BUGFIX: aplicar el offset de dirección aquí mismo — setupNoteDirection
		// ya no hace x += swagWidth*i para notas sustain (causaba WARNING),
		// así que calculamos la X final directamente igual que en recycle().
		x = _calcBaseX(mustHitNote) + (swagWidth * noteData);
		y = -2000;
		this.strumTime = strumTime + SaveData.data.offset;
		this.noteData = noteData;

		NoteSkinSystem.init();
		loadSkin(NoteSkinSystem.getCurrentSkinData());

		setupNoteDirection();

		if (isSustainNote && prevNote != null)
			setupSustainNote();

		var hitWindowMultiplier = isSustainNote ? 1.05 : 1.0;
		_hitWindowCache = Conductor.safeZoneOffset * hitWindowMultiplier;

		if (NoteTypeManager.isCustomType(noteType))
			NoteTypeManager.onNoteSpawn(this);
	}

	// ==================== CARGA DE SKIN ====================

	/**
	 * Carga la textura y las animaciones desde un NoteSkinData.
	 *
	 * No hay ninguna referencia a PlayState.curStage aquí.
	 * El caller (constructor / recycle) pasa el skinData ya resuelto
	 * por NoteSkinSystem (que sabe qué skin corresponde al stage actual).
	 */
	public function loadSkin(skinData:NoteSkinSystem.NoteSkinData):Void
	{
		if (skinData == null)
			return;

		_loadedSkinName = skinData.name;
		_loadedAsSustain = isSustainNote; // rastrear tipo para detectar cambio en recycle
		isPixelNote = skinData.isPixel == true;
		_skinSustainOffset = skinData.sustainOffset != null ? skinData.sustainOffset : 0.0;
		_skinHoldStretch = skinData.holdStretch != null ? skinData.holdStretch : 1.0;

		// ── Offsets de nota desde la skin ────────────────────────────────────
		// buildNoteOffsets / buildHoldNoteOffsets leen el campo `offset` de las
		// animaciones de nota en el JSON de skin. Son [0,0] si no se definen.
		// TIMING: seguro — la skin ya está cargada en NoteSkinSystem al inicio de
		// PlayState. Se re-evalúan en cada loadSkin() (constructor + recycle) por
		// si la skin cambia a mitad de la canción (stage con skin diferente, etc.).
		if (!isSustainNote)
		{
			var off = NoteSkinSystem.buildNoteOffsets(skinData, noteData);
			noteOffsetX = off[0];
			noteOffsetY = off[1];
		}
		else
		{
			var off = NoteSkinSystem.buildHoldNoteOffsets(skinData, noteData);
			noteOffsetX = off[0];
			noteOffsetY = off[1];
		}

		// ── Elegir textura ────────────────────────────────────────────────
		// Notas cabeza y strums → texture principal
		// Sustain pieces + tails → holdTexture (si existe) o fallback a texture
		var tex:NoteSkinSystem.NoteSkinTexture;
		// Por tipo de nota: hold usa holdTexture > notesTexture > texture
		//                   nota scroll usa notesTexture > texture
		// Strums usan strumsTexture en StrumNote.hx
		if (isSustainNote)
			tex = NoteSkinSystem.getHoldTexture(skinData.name);
		else
			tex = NoteSkinSystem.getNotesScrollTexture(skinData.name);

		// FunkinSprite (type:"funkinsprite") no puede usarse directamente
		// en Note (que extiende FlxSprite). Fallback a texture principal.
		if (NoteSkinSystem.isFunkinSpriteType(tex))
		{
			trace('[Note] FunkinSprite type detectado — fallback a texture principal (Note es FlxSprite)');
			tex = skinData.texture;
		}
		frames = NoteSkinSystem.loadSkinFrames(tex, skinData.folder);

		// ── NoteType: textura de sustain custom ───────────────────────────
		// Si el noteType tiene su propio atlas de hold, sobreescribir aquí.
		// Solo aplica a sustain notes; las cabezas se sobreescriben en onNoteSpawn.
		if (isSustainNote && NoteTypeManager.isCustomType(noteType))
		{
			final typeHoldFrames = NoteTypeManager.getHoldFrames(noteType);
			if (typeHoldFrames != null)
				frames = typeHoldFrames;
		}

		// BUGFIX CRÍTICO: si frames es null (asset faltante, XML roto, etc.)
		// el sprite crashea en FlxDrawQuadsItem::render al primer frame de PlayState.
		if (frames == null)
		{
			trace('[Note] WARN: frames null para skin "${skinData.name}" noteData=$noteData — usando placeholder');
			makeGraphic(Std.int(Note.swagWidth), Std.int(Note.swagWidth), 0x00000000);
		}

		// ── Escala ────────────────────────────────────────────────────────
		// BUGFIX: NO usar `width * _noteScale` porque `width` es el hitbox del
		// ciclo anterior (stale) hasta que se llame updateHitbox(). Usar
		// scale.set() directamente para evitar que el scale se multiplique
		// acumulativamente en cada recycle (_noteScale^N en la N-ésima reutilización).
		_noteScale = tex.scale != null ? tex.scale : 1.0;
		// BUG C FIX: si loadAtlas() no encontró el asset del skin personalizado y
		// cayó al fallback (textura Default), la escala del skin custom NO debe
		// aplicarse sobre la textura Default — si no, las notas aparecen con la
		// textura Default pero escaladas al tamaño del skin custom (notas gigantes).
		// NoteSkinSystem.lastLoadFellBack se activa en todos los fallbacks de loadAtlas().
		if (NoteSkinSystem.lastLoadFellBack)
			_noteScale = 0.7; // escala fija de la skin Default
		scale.set(_noteScale, _noteScale);
		updateHitbox();

		// ── Antialiasing ──────────────────────────────────────────────────
		antialiasing = tex.antialiasing != null ? tex.antialiasing : !isPixelNote;

		// ── Animaciones ───────────────────────────────────────────────────
		// Prioridad: animList (estilo personaje) → campo animations (legacy)

		// ── Sistema animList ─────────────────────────────────────────────
		if (skinData.animList != null && skinData.animList.length > 0)
		{
			// Registrar TODAS las entradas del animList en el sprite.
			// Las entradas con noteID solo son relevantes para strums (StrumNote.hx),
			// pero registrarlas aquí no hace daño — simplemente no se reproducen.
			_animListData = NoteSkinSystem.loadAnimList(this, skinData.animList);
		}

		// ── Sistema legacy (adicional o principal si no hay animList) ─────
		var anims = skinData.animations;
		if (anims != null)
		{
			// Claves de resolución por dirección — nombre específico → genérico → fallback
			var scrollKeys = [
				["left", "note", "allNotes"], ["down", "note", "allNotes"],
				  ["up", "note", "allNotes"], ["right", "note", "allNotes"]
			];
			var holdKeys = [
				["leftHold", "hold", "allHold"], ["downHold", "hold", "allHold"],
				  ["upHold", "hold", "allHold"], ["rightHold", "hold", "allHold"]
			];
			var holdEndKeys = [
				["leftHoldEnd", "holdEnd", "allHoldEnd"], ["downHoldEnd", "holdEnd", "allHoldEnd"],
				  ["upHoldEnd", "holdEnd", "allHoldEnd"], ["rightHoldEnd", "holdEnd", "allHoldEnd"]
			];

			if (!isSustainNote)
			{
				for (i in 0...animArrows.length)
				{
					var def = NoteSkinSystem.resolveAnimDef(anims, scrollKeys[i]);
					NoteSkinSystem.addAnimToSprite(this, animArrows[i] + 'Scroll', def);
				}
			}
			else
			{
				for (i in 0...animArrows.length)
				{
					var holdDef = NoteSkinSystem.resolveAnimDef(anims, holdKeys[i]);
					var holdEndDef = NoteSkinSystem.resolveAnimDef(anims, holdEndKeys[i]);
					NoteSkinSystem.addAnimToSprite(this, animArrows[i] + 'hold', holdDef);
					NoteSkinSystem.addAnimToSprite(this, animArrows[i] + 'holdend', holdEndDef);
				}
			}
		}

		// BUGFIX RGB: el shader (colorAuto/RGB/glow) debe aplicarse a AMBOS tipos de nota.
		// Antes solo se aplicaba cuando !isSustainNote, así que los sustains recién creados
		// (vía constructor, no recycle) nunca recibían el shader → sustains sin colorear
		// aunque la skin tuviera colorAuto:true o colorDirections definidos.
		_applyShaderForSkin(skinData);
		if (!isSustainNote && SaveData.data.downscroll)
		{
			flipX = true;
			flipY = true;
		}
	}

	// ==================== SHADER HELPER ====================

	/**
	 * Aplica el shader correcto para la skin dada y la dirección actual (noteData).
	 *
	 * Prioridad:
	 *   1. colorAuto:true en la skin  → NoteColorSwapShader con preset de dirección
	 *   2. ShaderManager activo       → NoteGlowShader de proximidad
	 *   3. Fallback                   → sin shader
	 *
	 * Centralizar aquí evita el bug donde el constructor y recycle() tomaban
	 * `getCurrentSkinData()` sin `groupSkin`, lo que provocaba que notas
	 * recicladas entre grupos CPU↔player aparecieran con la skin del grupo
	 * equivocado cuando ambos grupos usan skins distintas.
	 */
	private function _applyShaderForSkin(skinData:NoteSkinSystem.NoteSkinData):Void
	{
		if (skinData != null && skinData.colorAuto == true)
		{
			final dir = noteData % 4;

			// PRIORIDAD 1: colorDirections → RGB palette shader (mismo enfoque que NightmareVision).
			// Reemplaza los canales R/G/B de la textura con colores reales por dirección.
			if (skinData.colorDirections != null && dir < skinData.colorDirections.length)
			{
				final cd = skinData.colorDirections[dir];
				// GC FIX: reutilizar shader existente entre recycles.
				if (_rgbShader == null)
					_rgbShader = new funkin.shaders.NoteRGBPaletteShader();
				_rgbShader.setColors(cd.r, cd.g, cd.b);
				_colorSwapShader = null;
				_glowShader = null;
				shader = _rgbShader;
				return;
			}

			// PRIORIDAD 2: colorHSV → HSV shift (fallback cuando no hay colorDirections).
			final hsv = skinData.colorHSV;
			final entry = (hsv != null && dir < hsv.length) ? hsv[dir] : {h: 0.0, s: 0.0, b: 0.0};
			// GC FIX: reutilizar el shader existente en vez de `new` en cada recycle.
			if (_colorSwapShader == null)
				_colorSwapShader = new funkin.shaders.NoteColorSwapShader();
			_colorSwapShader.applyEntry(entry);
			_rgbShader = null;
			_glowShader = null;
			shader = _colorSwapShader;
		}
		else if (funkin.graphics.shaders.ShaderManager.enabled && (skinData.noteGlow == null || skinData.noteGlow == true))
		{
			final dir = noteData % 4;
			if (_glowShader == null)
				_glowShader = funkin.shaders.NoteGlowShader.forDirection(dir, 0.0);
			else
			{
				_glowShader.intensity = 0.0;
				_glowShader.pulse = 0.0;
			}
			_colorSwapShader = null;
			_rgbShader = null;
			shader = _glowShader;
		}
		else
		{
			_glowShader = null;
			_colorSwapShader = null;
			_rgbShader = null;
			shader = null;
		}
	}

	// ==================== RECYCLE (Object Pooling) ====================

	/**
	 * groupSkin: nombre de la skin exclusiva del grupo de strums al que
	 * pertenece esta nota (guardado en StrumsGroupData.noteSkin por PlayState).
	 * Si es null se usa la skin global activa (comportamiento original).
	 */
	public function recycle(strumTime:Float, noteData:Int, ?prevNote:Note, ?sustainNote:Bool = false, ?mustHitNote:Bool = false, ?groupSkin:String):Void
	{
		this.strumTime = strumTime + SaveData.data.offset;
		this.noteData = noteData;
		this.prevNote = prevNote != null ? prevNote : this;
		this.isSustainNote = sustainNote;
		this.mustPress = mustHitNote;
		this.canBeHit = false;
		this.tooLate = false;
		this.wasGoodHit = false;
		this.noteScore = 1;
		this.noteRating = 'sick';
		this.strumsGroupIndex = 0;
		this.noteType = '';
		this.alpha = sustainNote ? 0.6 : 1.0;
		this.visible = true;
		this.clipRect = null;
		this.isTailCap = false; // se reasignará en setupSustainNote() si corresponde
		// Resetear estado de transición de velocidad — la nota empieza sin lerp
		this._lerpFromY      = -1.0;
		this._lerpFromScaleY = -1.0;
		this._lerpT          = 1.0;

		x = _calcBaseX(mustHitNote) + (swagWidth * noteData);
		y = -2000;

		var hitWindowMultiplier = isSustainNote ? 1.05 : 1.0;
		_hitWindowCache = Conductor.safeZoneOffset * hitWindowMultiplier;
		_lastSongPos = -1;

		revive();

		noteOffsetX = 0.0;
		noteOffsetY = 0.0;

		var skinData = (groupSkin != null && groupSkin != '') ? NoteSkinSystem.getCurrentSkinData(groupSkin) : NoteSkinSystem.getCurrentSkinData();
		if (skinData == null)
			skinData = NoteSkinSystem.getCurrentSkinData(); // fallback a global
		if (skinData.name != _loadedSkinName || isSustainNote != _loadedAsSustain)
			loadSkin(skinData); // loadSkin() ya recalcula noteOffsetX/Y
		else
		{
			var off = isSustainNote ? NoteSkinSystem.buildHoldNoteOffsets(skinData, noteData) : NoteSkinSystem.buildNoteOffsets(skinData, noteData);
			noteOffsetX = off[0];
			noteOffsetY = off[1];
		}

		// ── Restaurar animación y escala ──────────────────────────────────
		if (!isSustainNote)
		{
			scale.set(_noteScale, _noteScale);
			updateHitbox();

			_applyNoteAnim(animArrows[noteData] + 'Scroll');

			_applyShaderForSkin(skinData);
		}
		else
		{
			scale.set(_noteScale, _noteScale);
			sustainBaseScaleY = _noteScale; // se actualizara en setupSustainNote
			updateHitbox();
			flipY = false;
			flipX = false;
			setupSustainNote();
			// FIX: los hold pieces también necesitan colorización.
			// Antes _applyShaderForSkin() solo se llamaba en el bloque !isSustainNote,
			// así que los sustains siempre quedaban sin shader aunque colorAuto fuera true.
			_applyShaderForSkin(skinData);
		}
	}

	// ==================== SETUP HELPERS ====================

	function setupNoteDirection():Void
	{
		// BUGFIX: las notas sustain NO tienen animación 'purpleScroll' registrada.
		// Además, la X ya fue calculada en el constructor con swagWidth*noteData,
		// así que no necesitamos x += aquí.
		if (isSustainNote)
			return;

		// Solo reproducir la animación de scroll (X ya calculada en constructor).
		// _applyNoteAnim aplica centerOffsets() + noteOffsetX/Y (igual que StrumNote.playAnim).
		_applyNoteAnim(animArrows[noteData] + 'Scroll');
	}

	function setupSustainNote():Void
	{
		noteScore * 0.2;
		alpha = 0.6;
		/*
			if (SaveData.data.downscroll)
			{
				flipY = true;
				flipX = true;
		}*/

		x += width / 2;

		for (i in 0...animArrows.length)
		{
			if (noteData == i)
			{
				// BUGFIX: check existence para no disparar WARNING si la skin
				// aún no tiene esta animación registrada
				_applyNoteAnim(animArrows[i] + 'holdend');
				isTailCap = true; // esta pieza es la cola — NoteManager lo usa para scale.y
				break;
			}
		}

		updateHitbox();
		// Re-aplicar offset de skin: el updateHitbox() de arriba (para recalcular
		// width y centrar x) llama centerOffsets() borrando el offset de _applyNoteAnim.
		offset.x += noteOffsetX;
		offset.y += noteOffsetY;
		x -= width / 2;

		// Offset X extra (leído del JSON de skin — e.g. 30 para pixel, 0 para normal)
		x += _skinSustainOffset;

		if (prevNote.isSustainNote)
		{
			for (i in 0...animArrows.length)
			{
				if (prevNote.noteData == i)
				{
					prevNote._applyNoteAnim(animArrows[i] + 'hold');
					prevNote.isTailCap = false; // ya no es cola — NoteManager usará scale.y euclidiano
					break;
				}
			}

			if (prevNote.frameHeight > 0)
			{
				final targetHeight:Float = Conductor.stepCrochet * 0.45 * PlayState.SONG.speed;
				prevNote.scale.y = (targetHeight * _skinHoldStretch) / prevNote.frameHeight;
			}
			else
			{
				// Fallback si frameHeight es 0 (frame aún no cargado)
				prevNote.scale.y *= Conductor.stepCrochet / 100 * 1.5 * PlayState.SONG.speed;
				prevNote.scale.y *= _skinHoldStretch;
			}
			// Guardar el scale.y base para que NoteManager pueda compensar la
			// rotacion de deformacion sin acumulacion (lee este valor, no scale.y).
			prevNote.sustainBaseScaleY = prevNote.scale.y;
			prevNote.updateHitbox();
			// Re-aplicar offset de skin: updateHitbox() borra el offset que
			// _applyNoteAnim('hold') aplicó justo arriba.
			prevNote.offset.x += prevNote.noteOffsetX;
			prevNote.offset.y += prevNote.noteOffsetY;
		}
	}

	// ==================== SETUP DE ANIMACIONES DE TIPO ====================

	/**
	 * Reconfigura animaciones cuando NoteTypeManager asigna sus propios frames.
	 * Llamado desde NoteTypeManager.onNoteSpawn().
	 */
	public function setupTypeAnimations():Void
	{
		var dirs = ['purple', 'blue', 'green', 'red'];
		if (!isSustainNote)
		{
			for (i in 0...dirs.length)
			{
				try
				{
					animation.addByPrefix(dirs[i] + 'Scroll', dirs[i] + '0');
				}
				catch (_:Dynamic)
				{
				}
				try
				{
					animation.addByPrefix(dirs[i] + 'Scroll', dirs[i]);
				}
				catch (_:Dynamic)
				{
				}
			}
			for (i in 0...dirs.length)
				if (noteData == i)
				{
					_applyNoteAnim(dirs[i] + 'Scroll');
					break;
				}
		}
		else
		{
			for (i in 0...dirs.length)
			{
				try
				{
					animation.addByPrefix(dirs[i] + 'holdend', dirs[i] + ' hold end');
				}
				catch (_:Dynamic)
				{
				}
				try
				{
					animation.addByPrefix(dirs[i] + 'holdend', dirs[i] + 'holdend');
				}
				catch (_:Dynamic)
				{
				}
				try
				{
					animation.addByPrefix(dirs[i] + 'hold', dirs[i] + ' hold piece');
				}
				catch (_:Dynamic)
				{
				}
				try
				{
					animation.addByPrefix(dirs[i] + 'hold', dirs[i] + 'hold');
				}
				catch (_:Dynamic)
				{
				}
			}
			for (i in 0...dirs.length)
				if (noteData == i)
				{
					_applyNoteAnim(dirs[i] + 'holdend');
					break;
				}
		}
		setGraphicSize(Std.int(width * _noteScale));
		updateHitbox();
	}

	// ==================== UTILIDADES ====================

	/**
	 * Reproduce una animación de nota aplicando el offset de skin correspondiente.
	 * Equivalente a StrumNote.playAnim() pero para notas scroll/hold/holdend.
	 *
	 * Flujo: animation.play() → centerOffsets() → offset.x += noteOffsetX, offset.y += noteOffsetY
	 * Si la animación no existe se ignora silenciosamente (sin WARNING).
	 */
	private function _applyNoteAnim(animName:String, force:Bool = false):Void
	{
		if (animation == null || !animation.exists(animName))
			return;
		animation.play(animName, force);
		centerOffsets();
		offset.x += noteOffsetX;
		offset.y += noteOffsetY;

		// Aplicar flipX/flipY del animList (solo en notas scroll — sustain maneja flipX por downscroll)
		if (!isSustainNote && _animListData != null)
		{
			var data = _animListData.get(animName);
			if (data != null && data.length >= 4)
			{
				if (data[2] > 0.5)
					flipX = !flipX;
				if (data[3] > 0.5)
					flipY = !flipY;
			}
		}
	}

	/**
	 * Convierte esta pieza de sustain de holdend → hold body inmediatamente.
	 * NoteManager lo llama en spawnNotes() cuando ya sabe que el siguiente raw
	 * es un sustain contiguo, evitando el flash de holdend de 1 frame que ocurría
	 * cuando piezas consecutivas entraban en la ventana de spawn en frames distintos.
	 */
	public function confirmHoldPiece():Void
	{
		_applyNoteAnim(animArrows[noteData] + 'hold');
		isTailCap = false;
	}

	/** Calcula la posición X base según mustPress y middlescroll. */
	inline function _calcBaseX(mustHitNote:Bool):Float
	{
		if (SaveData.data.middlescroll)
			return mustHitNote ? (FlxG.width / 2 - swagWidth * 2) : -275;
		else
			return mustHitNote ? (FlxG.width / 2 + 100) : 100;
	}

	// ==================== UPDATE ====================

	override function update(elapsed:Float)
	{
		super.update(elapsed);

		if (!mustPress)
		{
			canBeHit = false;
			if (strumTime <= Conductor.songPosition)
				wasGoodHit = true;
		}

		if (tooLate && alpha > 0.3)
			alpha = 0.3;

		// ── Glow (comportamiento idéntico a FPS Plus) ─────────────────────────
		// FPS Plus activa el glow ÚNICAMENTE cuando canBeHit = true (dentro de
		// safeZoneOffset), solo en notas normales (no sustains), y lo apaga
		// en cuanto tooLate o wasGoodHit.  El shader añade la rampa de proximidad
		// dentro de esa ventana — lo que FPS Plus hace con frames de animación
		// lo hacemos aquí en GLSL sin cambiar el atlas.
		if (_glowShader != null && mustPress && canBeHit && !isSustainNote && !wasGoodHit && !tooLate)
		{
			// Proximidad dentro de la safe zone: 0 al entrar, 1 justo en el strum.
			// Usamos _hitWindowCache (ya calculado) como denominador igual que
			// FPS Plus usa safeZoneOffset para determinar canBeHit.
			final dist:Float = strumTime - Conductor.songPosition;
			final safeZone:Float = _hitWindowCache > 0 ? _hitWindowCache : Conductor.safeZoneOffset;
			final t:Float = Math.max(0.0, 1.0 - (dist / safeZone));
			// Curva cuadrática: suave al entrar, explosiva al llegar al strum
			final curved:Float = t * t;
			_glowShader.intensity = 0.35 + curved * 0.40;
			_glowShader.pulse     = (dist < GLOW_PEAK_MS) ? 1.0 : curved;
			_glowShader.proximity = curved;
		}
		else if (_glowShader != null && (_glowShader.intensity > 0.0))
		{
			// Apagar glow: nota fuera de rango, golpeada o perdida.
			// Solo escribe los uniforms si hay algo que apagar (evita writes redundantes).
			_glowShader.intensity = 0.0;
			_glowShader.pulse     = 0.0;
			_glowShader.proximity = 0.0;
		}
	}
}
