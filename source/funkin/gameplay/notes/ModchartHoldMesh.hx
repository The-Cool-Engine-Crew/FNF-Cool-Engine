package funkin.gameplay.notes;

/**
 * ModchartHoldMesh — v2.3
 *
 * MEJORAS RESPECTO A v1:
 *
 * 1. wasGoodHit en el mesh con clip suave:
 *    En v1, las notas wasGoodHit eran ignoradas por el mesh y se dejaban al
 *    sprite con clipRect recto. Cuando hay curva activa (drunk, wave, spin…)
 *    ese rectángulo recto no sigue la curva → aspecto "cortado" antinatural.
 *    Ahora el mesh procesa wasGoodHit y aplica alpha-fade por vértice
 *    en la zona del strum → el hold sigue siendo curvo incluso mientras se consume.
 *    Inspirado en SustainStrip de FNF-Modcharting-Tools:
 *    (constructVertices calcula 3 puntos del path completo; aquí generalizamos
 *    a HOLD_SUBS puntos con fade progresivo en lugar de clip binario.)
 *
 * 2. Color por vértice (isColored=true):
 *    v1 usaba isColored=false, delegando el alpha al batch completo.
 *    Esto impedía fade diferencial entre vértices (necesario para el clip suave).
 *    Ahora cada vértice lleva su propio ARGB = note.color * vertex_alpha,
 *    lo que también respeta correctamente note.alpha (stealth, fadeout, etc.).
 *
 * 3. Tinte de color (note.color):
 *    Los skins pueden teñir holds con color personalizado. v1 ignoraba esto.
 *    Ahora se lee note.color (FlxColor ARGB) y se multiplica con el alpha
 *    por vértice para producir el color final correcto.
 *
 * 4. Zona de fade (CLIP_FADE_PX):
 *    En lugar de cortar el hold en duro en el threshold del strum,
 *    se hace un gradiente suave de CLIP_FADE_PX píxeles → aspecto orgánico
 *    como el que producía SustainStrip con sus 3 puntos interpolados.
 *
 * 5. Optimización de draw calls vacíos:
 *    Si tras el fade todos los vértices quedan con alpha=0 (hold 100% consumido),
 *    se salta el addTriangles en lugar de enviar triángulos invisibles.
 *
 * INVARIANTES que se conservan de v1:
 *  - HOLD_SUBS = 12 (12 subdivisiones por pieza, buen equilibrio curva/coste)
 *  - Buffers preallocados (sin allocs por frame en el caso habitual)
 *  - tooLate usa sprite con alpha reducido (el feedback visual de fallo)
 *  - Rotación (confusion, tornado) con precálculo cos/sin para el caso uniforme
 *  - Fix UV rotadas de atlas (TexturePacker ANGLE_90/270)
 *  - Fix flipX: mirror completo después de modificadores, no por modificador
 *
 * FIX v2.1 (RGB shader + clip zone doble render):
 *
 *  6. Shader por nota → startTrianglesBatch recibe cast(note.shader, FlxShader):
 *     NoteRGBPaletteShader / NoteColorSwapShader / NoteGlowShader no se
 *     propagaban al DrawTrianglesItem → holds curvados sin colorizar.
 *     Ahora el shader del sprite se aplica también al mesh.
 *
 *  7. Pre-ocultación en update() — elimina el "clip zone con RGB, resto sin RGB":
 *     NoteManager.update() restaura visible=true ANTES de draw(). Flixel dibuja el
 *     FlxGroup de sustains (sprite con shader + clipRect) y DESPUÉS holdMesh.draw()
 *     ponía visible=false. El clip zone se dibujaba DOS veces: sprite (con shader ✓)
 *     y mesh (sin shader ✗). FIX: _preHideCurvedNotes() en update() oculta los
 *     sprites después de que NoteManager los active pero antes de que el grupo los
 *     dibuje, eliminando el doble render y dejando el mesh como única fuente.
 */

import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxSprite;
import flixel.system.FlxAssets.FlxShader;
import flixel.graphics.tile.FlxDrawTrianglesItem;
import flixel.math.FlxPoint;
import funkin.data.Conductor;
import funkin.gameplay.NoteManager;
import funkin.gameplay.modchart.ModChartManager.StrumState;
import funkin.gameplay.notes.StrumNote;

class ModchartHoldMesh extends FlxBasic {

	// ── Configuración ────────────────────────────────────────────────────────

	/**
	 * Subdivisiones por pieza de hold.
	 * 12 da curvas suaves incluso con drunkX/Y extremo (>200 px).
	 * Aumentar si ves "codos" con modificadores muy altos.
	 */
	static inline final HOLD_SUBS:Int = 12;

	/**
	 * Ancho de la zona de fade en el límite del strum (píxeles de pantalla).
	 * Los vértices dentro de esta franja pasan de alpha=1 a alpha=0 suavemente,
	 * en lugar del corte brusco del clipRect del sprite.
	 * Inspirado en el suavizado natural de SustainStrip con sus 3 sample-points.
	 */
	static inline final CLIP_FADE_PX:Float = 10.0;

	// ── Estado ───────────────────────────────────────────────────────────────

	/** Referencia al NoteManager activo. Asignar después de crear el NoteManager.
	 *  Al asignar, registra automáticamente _syncAfterNoteUpdate en
	 *  NoteManager.onAfterUpdate para garantizar el orden correcto de ejecución. */
	public var noteManager(get, set):NoteManager;
	var _noteManager:NoteManager = null;
	inline function get_noteManager():NoteManager return _noteManager;
	function set_noteManager(nm:NoteManager):NoteManager {
		// Desregistrar del NoteManager anterior si era nuestro callback
		if (_noteManager != null && _noteManager.onAfterUpdate == _syncAfterNoteUpdate)
			_noteManager.onAfterUpdate = null;
		_noteManager = nm;
		// Registrar en el nuevo NoteManager para que nos llame al final de su update()
		if (nm != null)
			nm.onAfterUpdate = _syncAfterNoteUpdate;
		return nm;
	}

	/**
	 * Notas que este mesh renderiza este frame. Poblado en _syncAfterNoteUpdate()
	 * (llamado desde NoteManager.onAfterUpdate al final de NoteManager.update()),
	 * consumido en draw().
	 *
	 * FIX (Bug invisible v2.2): draw() itera _meshNotes directamente, independiente
	 * de note.visible, para que las notas curvadas (ocultas con visible=false para
	 * evitar doble render) sigan siendo procesadas por el mesh.
	 *
	 * FIX (doble render + sustains que no siguen — v2.3):
	 *   La lógica de poblar _meshNotes y poner note.visible=false se ejecuta ahora
	 *   en _syncAfterNoteUpdate(), disparado por NoteManager.onAfterUpdate DESPUÉS
	 *   de que NoteManager restaure note.visible para las notas en rango.
	 *   Antes estaba en update() de Flixel, que podía correr ANTES de
	 *   NoteManager.update() si PlayState llamaba al NoteManager manualmente tras
	 *   super.update() — causando que NoteManager volviera a poner visible=true y
	 *   el sprite se dibujara junto al mesh (doble render), o que el check
	 *   `!note.visible && !note.wasGoodHit` saltara notas válidas (sustains sin curva).
	 */
	var _meshNotes:Array<Note> = [];

	// Buffers preallocados de camino (HOLD_SUBS+1 puntos)
	var _ptsX:Array<Float>;
	var _ptsY:Array<Float>;

	// Buffers para una pieza: HOLD_SUBS quads × 4 vértices × 2 coords
	var _verts:openfl.Vector<Float>;
	var _uvts:openfl.Vector<Float>;
	// Colores por vértice: HOLD_SUBS quads × 4 vértices = HOLD_SUBS*4 ints (ARGB)
	var _colors:openfl.Vector<Int>;
	// Índices estáticos (construidos una vez en new())
	var _idx:openfl.Vector<Int>;

	// ── Constructor ──────────────────────────────────────────────────────────

	public function new(?nm:NoteManager, ?cam:FlxCamera) {
		super();
		noteManager = nm; // usa el setter que registra onAfterUpdate
		if (cam != null)
			cameras = [cam];

		_ptsX = [for (_ in 0...HOLD_SUBS + 1) 0.0];
		_ptsY = [for (_ in 0...HOLD_SUBS + 1) 0.0];

		// HOLD_SUBS quads: 4 vértices × 2 coords = 8 floats por quad
		_verts  = new openfl.Vector<Float>(HOLD_SUBS * 8, true);
		_uvts   = new openfl.Vector<Float>(HOLD_SUBS * 8, true);
		// 4 vértices × 1 color ARGB por quad
		_colors = new openfl.Vector<Int>(HOLD_SUBS * 4, true);
		// 2 triángulos × 3 índices = 6 por quad
		_idx    = new openfl.Vector<Int>(HOLD_SUBS * 6, true);

		//  Topología de índices (constante para todas las piezas):
		//
		//   vBase+0 (TL) ── vBase+1 (TR)
		//       │  ╲              │
		//       │    ╲            │
		//   vBase+2 (BL) ── vBase+3 (BR)
		//
		//   Tri 1: TL, TR, BL  →  (vBase, vBase+1, vBase+2)
		//   Tri 2: TR, BR, BL  →  (vBase+1, vBase+3, vBase+2)
		for (s in 0...HOLD_SUBS) {
			var ii    = s * 6;
			var vBase = s * 4;
			_idx[ii]     = vBase;
			_idx[ii + 1] = vBase + 1;
			_idx[ii + 2] = vBase + 2;
			_idx[ii + 3] = vBase + 1;
			_idx[ii + 4] = vBase + 3;
			_idx[ii + 5] = vBase + 2;
		}
	}

	// ── Helpers internos ─────────────────────────────────────────────────────

	/**
	 * true si algún modificador produce desplazamiento curvilíneo o rotación de carril.
	 */
	@:inline
	function _hasCurve(st:StrumState, strumAngle:Float):Bool
		return st.drunkX != 0 || st.drunkY != 0 || st.wave != 0 || st.bumpy != 0
			|| st.tipsy != 0 || st.zigzag != 0 || st.flipX > 0.5
			|| strumAngle != 0 || st.confusion != 0 || st.tornado != 0;

	/**
	 * Ángulo total (grados) para el punto a tiempo `t`.
	 * Réplica de _baseAngle en NoteManager: strum.angle + confusion + tornado senoidal.
	 */
	@:inline
	function _evalAngle(t:Float, strumAngle:Float, confusion:Float, tornado:Float, drunkFreq:Float):Float {
		var a:Float = strumAngle + confusion;
		if (tornado != 0)
			a += tornado * Math.sin(t * 0.001 * drunkFreq);
		return a;
	}

	/** Posición X del path a tiempo `t` — replica NoteManager.updateNotePosition(). */
	@:inline
	function _evalX(t:Float, songPos:Float, st:StrumState, strumX:Float, strumW:Float, noteW:Float):Float {
		var nx:Float = strumX + (strumW - noteW) * 0.5 + st.noteOffsetX;

		if (st.drunkX != 0)
			nx += st.drunkX * Math.sin(t * 0.001 * st.drunkFreq + songPos * 0.0008);
		if (st.tipsy != 0)
			nx += st.tipsy * Math.sin(songPos * 0.001 * st.tipsySpeed);
		if (st.zigzag != 0) {
			var zz:Float = Math.sin(t * 0.001 * st.zigzagFreq * Math.PI);
			nx += st.zigzag * (zz >= 0 ? 1.0 : -1.0);
		}

		// FIX flipX: mirror completo después de todos los modificadores
		if (st.flipX > 0.5) {
			final strumCenter:Float = strumX + strumW * 0.5;
			nx = strumCenter - (nx - strumCenter + noteW * 0.5) - noteW * 0.5;
		}

		return nx;
	}

	/** Posición Y del path a tiempo `t` — replica NoteManager.updateNotePosition(). */
	@:inline
	function _evalY(t:Float, songPos:Float, st:StrumState, refY:Float, effSpeed:Float, effDown:Bool):Float {
		var ny:Float = effDown ? refY + (songPos - t) * effSpeed : refY - (songPos - t) * effSpeed;

		ny += st.noteOffsetY;

		if (st.drunkY != 0)
			ny += st.drunkY * Math.sin(t * 0.001 * st.drunkFreq + songPos * 0.0008);
		if (st.bumpy != 0)
			ny += st.bumpy * Math.sin(songPos * 0.001 * st.bumpySpeed);
		if (st.wave != 0)
			ny += st.wave * Math.sin(songPos * 0.001 * st.waveSpeed - t * 0.001);

		return ny;
	}

	/**
	 * Alpha de clip para el fade suave en la zona del strum.
	 *
	 * - Devuelve 1.0 lejos del strum (lado visible = no consumido).
	 * - Devuelve 0.0 en el lado consumido (pasó el strum).
	 * - Gradiente lineal de CLIP_FADE_PX de ancho en la transición.
	 *
	 * En upscroll (effDown=false): consumido = py < threshold (nota ya pasó arriba).
	 * En downscroll (effDown=true): consumido = py > threshold (nota ya pasó abajo).
	 *
	 * Este gradiente reemplaza el clipRect recto del sprite y sigue la curva del hold,
	 * produciendo el mismo efecto orgánico que la interpolación de 3 puntos de SustainStrip.
	 */
	@:inline
	function _clipAlpha(py:Float, strumThreshold:Float, effDown:Bool):Float {
		// dist > 0 → consumido; dist < 0 → visible
		var dist:Float = effDown ? py - strumThreshold : strumThreshold - py;
		if (dist >= 0)               return 0.0;              // consumido
		if (dist <= -CLIP_FADE_PX)   return 1.0;              // completamente visible
		return (-dist) / CLIP_FADE_PX;                        // gradiente lineal
	}

	// ── Update / Sync ─────────────────────────────────────────────────────────

	/**
	 * FIX v2.3 — update() ya NO hace el pre-hide de sprites.
	 *
	 * Razón del cambio:
	 *   En v2.2, update() ponía note.visible=false y llenaba _meshNotes. Esto funcionaba
	 *   solo si update() corría DESPUÉS de NoteManager.update(). Cuando PlayState llama a
	 *   NoteManager.update() manualmente después de super.update(), el orden era:
	 *     1. ModchartHoldMesh.update() → visible=false, llena _meshNotes
	 *     2. NoteManager.update()      → visible=true  (restaura notas en rango)
	 *     3. FlxGroup.draw()           → dibuja sprite (visible=true) → doble render ✗
	 *     4. ModchartHoldMesh.draw()   → dibuja mesh                  → doble render ✗
	 *
	 *   La lógica se movió a _syncAfterNoteUpdate(), registrado en
	 *   NoteManager.onAfterUpdate y disparado al FINAL de NoteManager.update(),
	 *   garantizando siempre el orden correcto independientemente de cómo PlayState
	 *   organice sus llamadas.
	 */
	override public function update(elapsed:Float):Void {
		super.update(elapsed);
		// _meshNotes se reconstruye en _syncAfterNoteUpdate(), llamado desde
		// NoteManager.onAfterUpdate. Limpiar aquí solo si el NoteManager no está
		// asignado (sin manager, sin notas que procesar).
		if (_noteManager == null)
			_meshNotes.resize(0);
	}

	/**
	 * Puebla _meshNotes y oculta sprites curvados.
	 *
	 * Llamado desde NoteManager.onAfterUpdate al final de NoteManager.update(),
	 * DESPUÉS de que NoteManager haya restaurado note.visible para notas en rango.
	 * Esto garantiza que:
	 *   - note.visible refleja el estado real de ESTE frame (no el anterior).
	 *   - Los sprites que el mesh va a renderizar están ocultos ANTES de FlxGroup.draw().
	 *   - No hay doble render (sprite + mesh) ni sustains que ignoran la curva.
	 */
	function _syncAfterNoteUpdate():Void {
		_meshNotes.resize(0);

		var nm = _noteManager;
		if (nm == null) return;

		var mm = nm.modManager;
		if (mm == null || !mm.enabled) return;

		var allGroups = nm.strumsGroups;

		for (note in nm.sustainNotes.members) {
			if (note == null || !note.alive || !note.isSustainNote || note.tooLate)
				continue;

			// CPU en middlescroll: NoteManager las oculta permanentemente; no entrar al mesh.
			if (nm.middlescroll && !note.mustPress)
				continue;

			// Notas fuera del rango de culling de NoteManager (visible=false, no wasGoodHit):
			// ahora este check usa el note.visible que NoteManager acaba de actualizar este
			// frame (correcto), no el del frame anterior (que causaba saltar notas válidas).
			if (!note.visible && !note.wasGoodHit)
				continue;

			var groupId:String = note.mustPress ? "player" : "cpu";
			if (allGroups != null && note.strumsGroupIndex >= 2 && note.strumsGroupIndex < allGroups.length)
				groupId = allGroups[note.strumsGroupIndex].id;

			var st:StrumState = mm.getState(groupId, note.noteData);
			if (st == null) continue;

			var strum:FlxSprite = nm.getStrumForDir(note.noteData, note.strumsGroupIndex, note.mustPress);
			if (strum == null) continue;

			// Solo procesar si hay curva activa
			if (!_hasCurve(st, strum.angle)) continue;

			// Ocultar sprite AHORA (después de que NoteManager actualizó visible este frame)
			// para que FlxGroup.draw() no lo renderice. draw() usará _meshNotes, no note.visible.
			note.visible = false;
			_meshNotes.push(note);
		}
	}

	// ── Draw loop ────────────────────────────────────────────────────────────

	override public function draw():Void {
		var nm = _noteManager;
		if (nm == null) return;

		var mm = nm.modManager;
		if (mm == null || !mm.enabled) return;

		// Sin notas con curva este frame → nada que hacer
		if (_meshNotes.length == 0) return;

		var songPos:Float   = Conductor.songPosition;
		var stepC:Float     = Conductor.stepCrochet;
		var baseDown:Bool   = nm.downscroll;
		var baseSpeed:Float = nm.scrollSpeed;

		// Threshold del strum para el clip de wasGoodHit (media nota de radio)
		final halfStrum:Float = funkin.gameplay.notes.Note.swagWidth * 0.5;

		for (cam in cameras) {
			for (note in _meshNotes) {
				// Guards de seguridad: la nota puede haber muerto entre update() y draw()
				if (!note.alive || note.tooLate)
					continue;

				// ── Resolver StrumState ───────────────────────────────────────

				var groupId:String = note.mustPress ? "player" : "cpu";
				var allGroups = nm.strumsGroups;
				if (allGroups != null && note.strumsGroupIndex >= 2 && note.strumsGroupIndex < allGroups.length)
					groupId = allGroups[note.strumsGroupIndex].id;

				var st:StrumState = mm.getState(groupId, note.noteData);
				if (st == null)
					continue;

				var strum:FlxSprite = nm.getStrumForDir(note.noteData, note.strumsGroupIndex, note.mustPress);
				if (strum == null)
					continue;

				// Curva comprobada en update(); re-comprobar por si el mod cambió en este frame.
				if (!_hasCurve(st, strum.angle)) {
					// El mod se desactivó entre update() y draw(): restaurar sprite.
					note.visible = true;
					continue;
				}

				// ── Parámetros de scroll ──────────────────────────────────────

				var scrollMult:Float  = st.scrollMult;
				var pEffSpeed:Float   = baseSpeed * scrollMult;
				var isInvert:Bool     = st.invert > 0.5;
				var pEffDown:Bool     = baseDown != isInvert;  // XOR

				var sn:StrumNote    = Std.downcast(strum, StrumNote);
				var strumX:Float    = (sn != null) ? sn.logicalX : strum.x;
				var strumW:Float    = strum.width;
				var noteW:Float     = note.width;
				var refY:Float      = (sn != null) ? sn.logicalY : strum.y;

				// Threshold del strum para este hold (offset media nota, igual que NoteManager)
				var strumThreshold:Float = pEffDown ? refY - halfStrum : refY + halfStrum;
				var isWGH:Bool           = note.wasGoodHit;

				// ── Muestrear path: HOLD_SUBS+1 puntos ───────────────────────

				var _strumAngle:Float = strum.angle;
				var _confusion:Float  = st.confusion;
				var _tornado:Float    = st.tornado;
				var _applyRot:Bool    = (_strumAngle != 0.0 || _confusion != 0.0 || _tornado != 0.0);
				var _strumCX:Float    = strumX + strumW * 0.5;

				// Para rotación uniforme (sin tornado) precalcular cos/sin una vez
				var _cosU:Float = 1.0;
				var _sinU:Float = 0.0;
				if (_applyRot && _tornado == 0.0) {
					var _radU:Float = (_strumAngle + _confusion) * (Math.PI / 180.0);
					_cosU = Math.cos(_radU);
					_sinU = Math.sin(_radU);
				}

				var dt:Float = stepC / HOLD_SUBS;
				for (i in 0...HOLD_SUBS + 1) {
					var t:Float  = note.strumTime + i * dt;
					var px:Float = _evalX(t, songPos, st, strumX, strumW, noteW);
					var py:Float = _evalY(t, songPos, st, refY, pEffSpeed, pEffDown);

					if (_applyRot) {
						var cosA:Float = _cosU;
						var sinA:Float = _sinU;
						if (_tornado != 0.0) {
							var rad:Float = _evalAngle(t, _strumAngle, _confusion, _tornado, st.drunkFreq) * (Math.PI / 180.0);
							cosA = Math.cos(rad);
							sinA = Math.sin(rad);
						}
						var dxR:Float = px - _strumCX;
						var dyR:Float = py - refY;
						_ptsX[i] = _strumCX + dxR * cosA - dyR * sinA;
						_ptsY[i] = refY      + dxR * sinA + dyR * cosA;
					} else {
						_ptsX[i] = px;
						_ptsY[i] = py;
					}
				}

				// ── Optimización wasGoodHit: skip si 100% consumido ───────────
				// Si todos los puntos muestreados tienen alpha=0, no hay nada visible.
				// Equivale a clipH=0 en el NoteManager para sprites.
				if (isWGH) {
					var anyVisible:Bool = false;
					for (i in 0...HOLD_SUBS + 1) {
						if (_clipAlpha(_ptsY[i], strumThreshold, pEffDown) > 0.0) {
							anyVisible = true;
							break;
						}
					}
					if (!anyVisible)
						continue;
				}

				// note.visible ya es false (update() lo puso antes de FlxGroup.draw()).
				// No es necesario repetirlo aquí.

				// ── Textura ───────────────────────────────────────────────────

				var graphic = note.graphic;
				if (graphic == null)
					continue;

				// Guard: frame puede ser null si la animación aún no está cargada
				if (note.frame == null)
					continue;

				// UV normalizadas (frame.uv es lo que usa el renderer interno de FlxSprite)
				var frameUV  = note.frame.uv;
				var uL:Float = #if (flixel >= "6.1.0") frameUV.left   #else frameUV.x      #end;
				var uR:Float = #if (flixel >= "6.1.0") frameUV.right  #else frameUV.y      #end;
				var vT:Float = #if (flixel >= "6.1.0") frameUV.top    #else frameUV.width  #end;
				var vB:Float = #if (flixel >= "6.1.0") frameUV.bottom #else frameUV.height #end;

				// FIX flipY del tail cap en el mesh:
				//
				// Cuando el SPRITE renderiza el tail cap (holdend) con flipY=true, OpenFL
				// invierte la textura verticalmente — la parte redondeada que apunta hacia
				// el final del hold queda del lado correcto (arriba en downscroll, abajo en
				// upscroll). El MESH lo ignoraba y siempre mapeaba vT→vB, así que en
				// downscroll (flipY=true) el tail cap salía al revés, y al activar invert
				// (que cambia flipY a false) el mesh no reflejaba ningún cambio visual
				// aunque NoteManager sí calculase el flipY correcto.
				//
				// FIX: si isTailCap && note.flipY, intercambiar vT y vB antes de calcular
				// vRng → vRng queda negativo → las UVs van de vB→vT (invertido en V) →
				// idéntico al flipY del sprite.
				//
				// Casos resultantes:
				//   upscroll / invert=false  → flipY=false → vT→vB (redondeado abajo) ✓
				//   downscroll / invert=false → flipY=true  → vB→vT (redondeado arriba) ✓
				//   upscroll   + invert=true  → flipY=true  → vB→vT (effective downscroll) ✓
				//   downscroll + invert=true  → flipY=false → vT→vB (effective upscroll)  ✓
				if (note.isTailCap && note.flipY) {
					var tmp:Float = vT; vT = vB; vB = tmp;
				}

				var vRng:Float = vB - vT; // negativo cuando flipY=true → UVs invertidas en V

				// Fix atlas rotado (TexturePacker ANGLE_90/270)
				var frameAngle:Float = switch (note.frame.angle) {
					case ANGLE_90:  -90.0;
					case ANGLE_270:  90.0;
					default:          0.0;
				};
				var _uvCosA:Float = 1.0, _uvSinA:Float = 0.0;
				var _uvUCen:Float = 0.0, _uvVCen:Float = 0.0;
				var _frameRotated:Bool = (frameAngle != 0.0);
				if (_frameRotated) {
					var rad = frameAngle * (Math.PI / 180.0);
					_uvCosA = Math.cos(rad);
					_uvSinA = Math.sin(rad);
					_uvUCen = (uL + uR) * 0.5;
					// _uvVCen se calcula DESPUÉS del posible swap de vT/vB para que
					// el centro de rotación de atlas sea siempre el centro real del frame.
					_uvVCen = (vT + vB) * 0.5;
				}

				// Ancho real renderizado (incluye padding sourceSize de TexturePacker si lo hay).
				// ANTES: note.frame.frame.width * scale — ignoraba el sourceSize del atlas,
				// causando quads más estrechos que el sprite real cuando había padding transparente.
				// AHORA: note.width ya tiene width = frame.sourceSize.width * scale aplicado por Flixel.
				var halfW:Float = note.width * 0.5;

				// ── Color por vértice (NUEVO en v2) ───────────────────────────
				//
				// note.color es FlxColor (ARGB como Int). Extraemos R,G,B para
				// poder multiplicar el alpha por vértice independientemente.
				// En la mayoría de skins note.color = 0xFFFFFFFF (blanco, sin tinte),
				// pero skins custom pueden teñir holds con colores arbitrarios.
				//
				// El alpha por vértice se compone de:
				//   - note.alpha          (stealth, fadeout, etc.)
				//   - _clipAlpha(...)     (fade suave en el strum para wasGoodHit)
				var nc:Int    = note.color;
				var nR:Int    = (nc >> 16) & 0xFF;
				var nG:Int    = (nc >> 8)  & 0xFF;
				var nB:Int    =  nc        & 0xFF;
				var baseA:Float = note.alpha; // [0..1]

				// ── Construir quads ───────────────────────────────────────────

				var allInvisible:Bool = true; // para detectar batch vacío

				for (s in 0...HOLD_SUBS) {
					var x0:Float = _ptsX[s],     y0:Float = _ptsY[s];
					var x1:Float = _ptsX[s + 1], y1:Float = _ptsY[s + 1];

					// ── Alpha por fila de vértices ────────────────────────────
					//
					// Cada "fila" del quad (top = punto s, bottom = punto s+1)
					// puede tener distinto alpha si cruza el threshold del strum.
					// Esto produce el degradado suave que sigue la curva del hold
					// (imposible con un clipRect recto).
					var rowA0:Float = isWGH ? _clipAlpha(y0, strumThreshold, pEffDown) : 1.0;
					var rowA1:Float = isWGH ? _clipAlpha(y1, strumThreshold, pEffDown) : 1.0;

					// Aplicar note.alpha base
					rowA0 *= baseA;
					rowA1 *= baseA;

					// Empaquetar ARGB
					var c0:Int = (Math.round(rowA0 * 255) << 24) | (nR << 16) | (nG << 8) | nB;
					var c1:Int = (Math.round(rowA1 * 255) << 24) | (nR << 16) | (nG << 8) | nB;

					var ci:Int = s * 4;
					_colors[ci]     = c0; // TL
					_colors[ci + 1] = c0; // TR (misma fila que TL)
					_colors[ci + 2] = c1; // BL
					_colors[ci + 3] = c1; // BR (misma fila que BL)

					if (rowA0 > 0 || rowA1 > 0)
						allInvisible = false;

					// ── Vértices (perpendiculares a la tangente local) ────────
					var dx:Float = x1 - x0;
					var dy:Float = y1 - y0;
					var len:Float = Math.sqrt(dx * dx + dy * dy);
					if (len < 0.001) len = 0.001;

					// Normal unitaria escalada a halfW
					var nx:Float = -dy / len * halfW;
					var ny:Float =  dx / len * halfW;

					var vi:Int = s * 8;
					// TL
					_verts[vi]     = x0 + nx; _verts[vi + 1] = y0 + ny;
					// TR
					_verts[vi + 2] = x0 - nx; _verts[vi + 3] = y0 - ny;
					// BL
					_verts[vi + 4] = x1 + nx; _verts[vi + 5] = y1 + ny;
					// BR
					_verts[vi + 6] = x1 - nx; _verts[vi + 7] = y1 - ny;

					// ── UV ────────────────────────────────────────────────────
					var vTop2:Float = vT + (s       / HOLD_SUBS) * vRng;
					var vBot2:Float = vT + ((s + 1) / HOLD_SUBS) * vRng;

					if (!_frameRotated) {
						// Caso habitual: sin rotación de atlas
						_uvts[vi]     = uL; _uvts[vi + 1] = vTop2; // TL
						_uvts[vi + 2] = uR; _uvts[vi + 3] = vTop2; // TR
						_uvts[vi + 4] = uL; _uvts[vi + 5] = vBot2; // BL
						_uvts[vi + 6] = uR; _uvts[vi + 7] = vBot2; // BR
					} else {
						// Atlas rotado 90°/270° (TexturePacker) — rotar esquinas UV
						var du:Float; var dv:Float;

						// TL: (uL, vTop2)
						du = uL - _uvUCen; dv = vTop2 - _uvVCen;
						_uvts[vi]     = du * _uvCosA - dv * _uvSinA + _uvUCen;
						_uvts[vi + 1] = du * _uvSinA + dv * _uvCosA + _uvVCen;
						// TR: (uR, vTop2)
						du = uR - _uvUCen;
						_uvts[vi + 2] = du * _uvCosA - dv * _uvSinA + _uvUCen;
						_uvts[vi + 3] = du * _uvSinA + dv * _uvCosA + _uvVCen;
						// BL: (uL, vBot2)
						du = uL - _uvUCen; dv = vBot2 - _uvVCen;
						_uvts[vi + 4] = du * _uvCosA - dv * _uvSinA + _uvUCen;
						_uvts[vi + 5] = du * _uvSinA + dv * _uvCosA + _uvVCen;
						// BR: (uR, vBot2)
						du = uR - _uvUCen;
						_uvts[vi + 6] = du * _uvCosA - dv * _uvSinA + _uvUCen;
						_uvts[vi + 7] = du * _uvSinA + dv * _uvCosA + _uvVCen;
					}
				}

				if (allInvisible)
					continue;

				var _meshShader:FlxShader =
					(note.shader != null) ? Std.downcast(note.shader, FlxShader) : null;

				var dc:FlxDrawTrianglesItem = cam.startTrianglesBatch(
					graphic,
					note.antialiasing,
					true,          // isColored — colores por vértice
					note.blend,
					_meshShader    // FIX: shader RGB/ColorSwap/Glow aplicado al mesh
				);
				if (dc == null)
					continue;

				var scrollPt = FlxPoint.weak(
					cam.scroll.x * -note.scrollFactor.x,
					cam.scroll.y * -note.scrollFactor.y
				);

				dc.addTriangles(_verts, _idx, _uvts, _colors, scrollPt, null);
			}
		}
	}
}
