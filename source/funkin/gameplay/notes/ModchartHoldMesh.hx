package funkin.gameplay.notes;

/**
 * ModchartHoldMesh
 *
 * Renderizador de holds curvados para usar cuando hay modificadores activos
 * (drunkX/Y, wave, bumpy, tipsy, zigzag, …).
 *
 * PROBLEMA QUE RESUELVE:
 *   Con el sistema FlxSprite estándar cada pieza de hold es un segmento recto
 *   entre dos puntos (strumTime y strumTime+stepCrochet). Con modificadores que
 *   desplazan en X o Y de forma senoidal, segmentos consecutivos forman ángulos
 *   visibles y gaps entre sí.
 *
 * SOLUCIÓN:
 *   Para cada pieza body (no tail, no wasGoodHit, no tooLate) con curva activa:
 *   1. Se oculta el FlxSprite original.
 *   2. Se muestrea el path en HOLD_SUBS+1 puntos entre strumTime y
 *      strumTime+stepCrochet usando exactamente la misma lógica de
 *      NoteManager.updateNotePosition().
 *   3. Se construyen HOLD_SUBS quads perpendiculares a la tangente local.
 *   4. Se envía al pipeline de HaxeFlixel con camera.startTrianglesBatch()
 *      + FlxDrawTrianglesItem.addTriangles() — sin allocs por frame en el
 *      caso habitual (buffers preallocados).
 *
 * INTEGRACIÓN:
 *   - Añadir entre sustainNotes y notes en PlayState.createNoteGroups().
 *   - Asignar holdMesh.noteManager = noteManager después de crear NoteManager.
 *   - Asignar noteManager.modManager = modChartManager después de crear ambos.
 *
 * COSTE:
 *   - O(k × HOLD_SUBS) donde k = piezas body con curva activa en pantalla.
 *   - Sin curvas activas: coste ≈ cero (guard temprano).
 *   - Sin allocs por frame: buffers _verts/_uvts/_idx son instancia, solo se
 *     reasignan si HOLD_SUBS cambia (nunca en runtime).
 */
import flixel.FlxBasic;
import flixel.FlxCamera;
import flixel.FlxSprite;
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
	 * 12 es un buen equilibrio: suficiente para curvas suaves incluso con
	 * drunkX/Y extremo, sin saturar el pipeline de triángulos.
	 * Aumentar si ves "codos" con valores de modificador muy altos (> 200 px).
	 */
	static inline final HOLD_SUBS:Int = 12;

	// ── Estado ───────────────────────────────────────────────────────────────

	/** Referencia al NoteManager activo. Asignar después de crear el NoteManager. */
	public var noteManager:NoteManager;

	// Buffers preallocados de camino (HOLD_SUBS+1 puntos)
	var _ptsX:Array<Float>;
	var _ptsY:Array<Float>;

	// Buffers preallocados para una pieza: HOLD_SUBS quads × 4 vértices × 2 coords
	var _verts:openfl.Vector<Float>;
	var _uvts:openfl.Vector<Float>;
	// Índices estáticos: construidos una vez en new(), nunca cambian
	var _idx:openfl.Vector<Int>;

	// ── Constructor ──────────────────────────────────────────────────────────

	public function new(?nm:NoteManager, ?cam:FlxCamera) {
		super();
		noteManager = nm;
		if (cam != null)
			cameras = [cam];

		_ptsX = [for (_ in 0...HOLD_SUBS + 1) 0.0];
		_ptsY = [for (_ in 0...HOLD_SUBS + 1) 0.0];

		// HOLD_SUBS quads: 4 vértices × 2 coords = 8 floats por quad
		_verts = new openfl.Vector<Float>(HOLD_SUBS * 8, true);
		_uvts = new openfl.Vector<Float>(HOLD_SUBS * 8, true);
		// 2 triángulos por quad × 3 índices = 6 índices por quad
		_idx = new openfl.Vector<Int>(HOLD_SUBS * 6, true);

		// Construir tabla de índices estática (topología igual para todas las piezas)
		//
		//  vBase+0 (TL) ─ vBase+1 (TR)
		//      │   ╲             │
		//      │     ╲           │
		//  vBase+2 (BL) ─ vBase+3 (BR)
		//
		//  Tri 1: TL, TR, BL  →  (vBase, vBase+1, vBase+2)
		//  Tri 2: TR, BR, BL  →  (vBase+1, vBase+3, vBase+2)
		for (s in 0...HOLD_SUBS) {
			var ii = s * 6;
			var vBase = s * 4;
			_idx[ii] = vBase;
			_idx[ii + 1] = vBase + 1;
			_idx[ii + 2] = vBase + 2;
			_idx[ii + 3] = vBase + 1;
			_idx[ii + 4] = vBase + 3;
			_idx[ii + 5] = vBase + 2;
		}
	}

	// ── Helpers internos ─────────────────────────────────────────────────────

	/**
	 * Devuelve true si algún modificador que produce desplazamiento curvilíneo
	 * o rotación de carril tiene valor distinto de cero.
	 *
	 * @param st          StrumState del grupo/nota
	 * @param strumAngle  strum.angle actual (spin acumulado + st.angle)
	 */
	@:inline
	function _hasCurve(st:StrumState, strumAngle:Float):Bool
		return st.drunkX != 0 || st.drunkY != 0 || st.wave != 0 || st.bumpy != 0
			|| st.tipsy != 0 || st.zigzag != 0 || st.flipX > 0.5
			|| strumAngle != 0 || st.confusion != 0 || st.tornado != 0;

	/**
	 * Ángulo total en grados para el punto a tiempo `t`.
	 * Replica _baseAngle de NoteManager: strum.angle + confusion + tornado senoidal.
	 *
	 * @param t           strumTime del punto (ms)
	 * @param strumAngle  strum.angle actual
	 * @param confusion   st.confusion
	 * @param tornado     st.tornado
	 * @param drunkFreq   st.drunkFreq (frecuencia compartida con tornado)
	 */
	@:inline
	function _evalAngle(t:Float, strumAngle:Float, confusion:Float, tornado:Float, drunkFreq:Float):Float {
		var a:Float = strumAngle + confusion;
		if (tornado != 0)
			a += tornado * Math.sin(t * 0.001 * drunkFreq);
		return a;
	}

	/**
	 * Calcula la posición X en pantalla de un punto del path a tiempo `t`.
	 * Replica exactamente el bloque X de NoteManager.updateNotePosition().
	 *
	 * @param t         strumTime del punto a evaluar (ms)
	 * @param songPos   posición actual de la canción (ms)
	 * @param st        StrumState con los valores de los modificadores
	 * @param strumX    note.strum.x (posición X del receptor)
	 * @param strumW    note.strum.width (ancho del receptor, con escala)
	 * @param noteW     note.width (ancho de la nota, con escala)
	 */
	@:inline
	function _evalX(t:Float, songPos:Float, st:StrumState, strumX:Float, strumW:Float, noteW:Float):Float {
		var nx:Float = strumX + (strumW - noteW) * 0.5 + st.noteOffsetX;

		// Aplicar modificadores SIN invertir el signo — igual que NoteManager.
		// El mirror de flipX se aplica al final sobre el resultado total, no
		// negando cada desplazamiento individualmente (eso solo refleja las ondas
		// pero deja la posición base sin espejear, causando el desalineamiento).
		if (st.drunkX != 0)
			nx += st.drunkX * Math.sin(t * 0.001 * st.drunkFreq + songPos * 0.0008);

		if (st.tipsy != 0)
			nx += st.tipsy * Math.sin(songPos * 0.001 * st.tipsySpeed);

		if (st.zigzag != 0) {
			var zz:Float = Math.sin(t * 0.001 * st.zigzagFreq * Math.PI);
			nx += st.zigzag * (zz >= 0 ? 1.0 : -1.0);
		}

		// FIX: mirror completo después de todos los modificadores, igual que
		// NoteManager:  _noteX = strumCenter - (_noteX - strumCenter + noteW/2) - noteW/2
		// Sin este mirror el mesh queda desplazado respecto al sprite en flipX.
		if (st.flipX > 0.5) {
			final strumCenter:Float = strumX + strumW * 0.5;
			nx = strumCenter - (nx - strumCenter + noteW * 0.5) - noteW * 0.5;
		}

		return nx;
	}

	/**
	 * Calcula la posición Y en pantalla de un punto del path a tiempo `t`.
	 * Replica exactamente el bloque Y de NoteManager.updateNotePosition().
	 *
	 * @param t         strumTime del punto a evaluar (ms)
	 * @param songPos   posición actual de la canción (ms)
	 * @param st        StrumState con los valores de los modificadores
	 * @param refY      strum.y del receptor (igual que _refY en NoteManager.updateNotePosition)
	 * @param effSpeed  velocidad de scroll efectiva (scrollSpeed × scrollMult)
	 * @param effDown   true si el scroll efectivo es downscroll
	 */
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

	// ── Draw loop ────────────────────────────────────────────────────────────

	override public function draw():Void {
		// ── Guard: sin noteManager o sin modchart activo, no hacer nada ──────
		var nm = noteManager;
		if (nm == null)
			return;

		var mm = nm.modManager;
		if (mm == null || !mm.enabled)
			return;

		var songPos:Float = Conductor.songPosition;
		var stepC:Float = Conductor.stepCrochet;
		var allGroups = nm.strumsGroups; // public getter que expone allStrumsGroups
		var baseDown:Bool = nm.downscroll;
		var baseSpeed:Float = nm.scrollSpeed; // public getter que expone _scrollSpeed

		for (cam in cameras) {
			for (note in nm.sustainNotes.members) {
				// ── Guards por nota ──────────────────────────────────────────

				if (note == null || !note.alive)
					continue;

				// Solo piezas sustain (body y tail cap — ambos entran al mesh)
				if (!note.isSustainNote)
					continue;

				// wasGoodHit: dejar que el sprite con clipRect maneje el recorte
				// (la porción consumida desaparece correctamente con el rect).
				if (note.wasGoodHit)
					continue;

				// tooLate: mantener sprite faded para feedback visual de fallo
				if (note.tooLate)
					continue;

				// Si NoteManager ya lo ocultó (culling por fuera de pantalla), respetar
				if (!note.visible)
					continue;

				// ── Resolver StrumState del ModChartManager ──────────────────

				// Grupos 0/1: alias mustPress-based, igual que NoteManager.
				// Grupos >= 2: groupId propio del JSON.
				var groupId:String = note.mustPress ? "player" : "cpu";
				if (allGroups != null && note.strumsGroupIndex >= 2 && note.strumsGroupIndex < allGroups.length)
					groupId = allGroups[note.strumsGroupIndex].id;

				var st:StrumState = mm.getState(groupId, note.noteData);
				if (st == null)
					continue;

				// ── Obtener receptor (antes del guard para leer strum.angle) ──

				var strum:FlxSprite = nm.getStrumForDir(note.noteData, note.strumsGroupIndex, note.mustPress);
				if (strum == null)
					continue;

				// Guard unificado: desplazamiento curvilíneo O rotación de carril
				if (!_hasCurve(st, strum.angle))
					continue;

				// ── Parámetros de scroll efectivos para esta nota ────────────

				var scrollMult:Float = st.scrollMult;
				var pEffSpeed:Float = baseSpeed * scrollMult;
				var isInvert:Bool = st.invert > 0.5;
				var pEffDown:Bool = baseDown != isInvert; // XOR, igual que NoteManager

				// Cast a StrumNote para acceder a logicalX/Y — posiciones de referencia
				// lógicas (baseX/Y + offsetX/Y) sin modificadores visuales (drunk, tipsy…).
				// Esto espeja exactamente NoteManager: _refY = sn.logicalY, _logStrumX = sn.logicalX.
				var sn:StrumNote = Std.downcast(strum, StrumNote);
				var strumX:Float = (sn != null) ? sn.logicalX : strum.x;
				var strumW:Float = strum.width;
				var noteW:Float = note.width;
				// Centro Y del receptor — usar logicalY para paridad exacta con
				// NoteManager._refY = sn.logicalY. strum.y puede incluir offsets
				// visuales de mods (drunk, tipsy, beat-bump…) que desalinearían
				// el mesh respecto a los sprites de nota y sustain.
				var refY:Float = (sn != null) ? sn.logicalY : strum.y;

				// ── Muestrear path: HOLD_SUBS+1 puntos ──────────────────────
				//
				// Evaluamos de strumTime a strumTime+stepCrochet para cubrir
				// exactamente esta pieza de sustain.  Los puntos se acumulan
				// en los buffers de instancia sin ningún alloc.
				//
				// ANGLE FIX: después de calcular la posición en espacio sin rotar,
				// giramos cada punto alrededor del centro del strum (strumCenterX, refY)
				// por el ángulo total = strum.angle + confusion + tornado(t).
				// Esto replica exactamente _baseAngle de NoteManager pero aplicado
				// a la posición, no al sprite individual → el snake completo rota
				// como una unidad y los segmentos siempre conectan entre sí.
				var _strumAngle:Float   = strum.angle; // spin acumulado + st.angle
				var _confusion:Float    = st.confusion;
				var _tornado:Float      = st.tornado;
				var _applyRot:Bool      = (_strumAngle != 0.0 || _confusion != 0.0 || _tornado != 0.0);
				var _strumCX:Float      = strumX + strumW * 0.5; // centro X del receptor
				// Para rotación uniforme (sin tornado) precalcular cos/sin una sola vez.
				var _cosU:Float = 1.0;
				var _sinU:Float = 0.0;
				if (_applyRot && _tornado == 0.0) {
					var _radU:Float = (_strumAngle + _confusion) * (Math.PI / 180.0);
					_cosU = Math.cos(_radU);
					_sinU = Math.sin(_radU);
				}

				var dt:Float = stepC / HOLD_SUBS;
				for (i in 0...HOLD_SUBS + 1) {
					var t:Float = note.strumTime + i * dt;
					var px:Float = _evalX(t, songPos, st, strumX, strumW, noteW);
					var py:Float = _evalY(t, songPos, st, refY, pEffSpeed, pEffDown);

					if (_applyRot) {
						var cosA:Float = _cosU;
						var sinA:Float = _sinU;
						if (_tornado != 0.0) {
							// Tornado: ángulo diferente por punto → recalcular cada vez
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

				// ── Ocultar sprite original ──────────────────────────────────
				note.visible = false;

				// ── Obtener textura del atlas ────────────────────────────────

				var graphic = note.graphic;
				if (graphic == null)
					continue;

				// Bug 4 fix: usar frame.uv (coordenadas normalizadas precalculadas por
				// HaxeFlixel) en lugar de dividir frame.frame manualmente entre
				// bitmap.width/height. frame.uv es lo que usa el renderer interno de
				// FlxSprite, por lo que siempre está sincronizado con el atlas real.
				var frameUV = note.frame.uv;
				var uL:Float = #if (flixel >= "6.1.0") frameUV.left #else frameUV.x #end;
				var uR:Float = #if (flixel >= "6.1.0") frameUV.right #else frameUV.y #end;
				var vT:Float = #if (flixel >= "6.1.0") frameUV.top #else frameUV.width #end;
				var vB:Float = #if (flixel >= "6.1.0") frameUV.bottom #else frameUV.height #end;
				var vRng:Float = vB - vT;

				// Bug 2 fix: leer la rotación del frame en el atlas.
				// TexturePacker rota sprites 90° para ganar eficiencia de empaquetado.
				// Sin este fix los UVs se asignan como si angle==0 y el hold aparece
				// con la textura cortada o visualmente cizallada.
				var frameAngle:Float = switch (note.frame.angle) {
					case ANGLE_90: -90.0;
					case ANGLE_270: 90.0;
					default: 0.0;
				};
				var _uvCosA:Float = 1.0;
				var _uvSinA:Float = 0.0;
				var _uvUCen:Float = 0.0;
				var _uvVCen:Float = 0.0;
				var _frameRotated:Bool = (frameAngle != 0.0);
				if (_frameRotated) {
					var rad = frameAngle * (Math.PI / 180.0);
					_uvCosA = Math.cos(rad);
					_uvSinA = Math.sin(rad);
					_uvUCen = (uL + uR) * 0.5;
					_uvVCen = (vT + vB) * 0.5;
				}

				// Bug 1 fix: usar el ancho recortado del frame (texels reales en el atlas)
				// note.width = sourceSize × scale, que incluye padding transparente.
				// frame.frame.width × scale.x es el ancho real de los texels.
				var halfW:Float = note.frame.frame.width * note.scale.x * 0.5;

				// ── Rellenar buffers de vértices y UV ────────────────────────
				//
				// Para cada subdivisión s construimos un quad perpendicular a la
				// tangente local del path:
				//
				//   tangente = (dx, dy) = p[s+1] - p[s]
				//   normal   = (-dy, dx) / |tangente|  (gira 90° a la izquierda)
				//
				//   TL = p[s]   + normal * halfW     → (uL, vTop)
				//   TR = p[s]   - normal * halfW     → (uR, vTop)
				//   BL = p[s+1] + normal * halfW     → (uL, vBot)
				//   BR = p[s+1] - normal * halfW     → (uR, vBot)
				//
				// Demostración de corrección UV con flip:
				//
				//   Upscroll (dy>0, nx<0):
				//     TL = (x-|nx|, ...) = screen-left  → uL ✓
				//     TR = (x+|nx|, ...) = screen-right → uR ✓
				//
				//   Downscroll (dy<0, nx>0) con flipX=true en sprite:
				//     TL = (x+nx,  ...) = screen-right → uL
				//     Con flipX: atlas-left aparece en screen-right ✓
				//     TR = (x-nx,  ...) = screen-left  → uR
				//     Con flipX: atlas-right aparece en screen-left ✓
				//
				//   El signo de nx cambia naturalmente con la dirección del
				//   path, replicando el comportamiento de flipX del sprite
				//   sin código extra.

				for (s in 0...HOLD_SUBS) {
					var x0:Float = _ptsX[s], y0:Float = _ptsY[s];
					var x1:Float = _ptsX[s + 1], y1:Float = _ptsY[s + 1];

					var dx:Float = x1 - x0;
					var dy:Float = y1 - y0;
					var len:Float = Math.sqrt(dx * dx + dy * dy);
					if (len < 0.001)
						len = 0.001; // evitar NaN en el extremo

					// Normal unitaria escalada a halfW
					var nx:Float = -dy / len * halfW;
					var ny:Float = dx / len * halfW;

					var vi:Int = s * 8;
					// TL
					_verts[vi] = x0 + nx;
					_verts[vi + 1] = y0 + ny;
					// TR
					_verts[vi + 2] = x0 - nx;
					_verts[vi + 3] = y0 - ny;
					// BL
					_verts[vi + 4] = x1 + nx;
					_verts[vi + 5] = y1 + ny;
					// BR
					_verts[vi + 6] = x1 - nx;
					_verts[vi + 7] = y1 - ny;

					// UV: interpolar V de vT a vB a lo largo de la pieza
					var vTop2:Float = vT + (s / HOLD_SUBS) * vRng;
					var vBot2:Float = vT + ((s + 1) / HOLD_SUBS) * vRng;

					if (!_frameRotated) {
						// Caso rápido: sin rotación de atlas (ANGLE_0, el más común)
						_uvts[vi] = uL;
						_uvts[vi + 1] = vTop2; // TL
						_uvts[vi + 2] = uR;
						_uvts[vi + 3] = vTop2; // TR
						_uvts[vi + 4] = uL;
						_uvts[vi + 5] = vBot2; // BL
						_uvts[vi + 6] = uR;
						_uvts[vi + 7] = vBot2; // BR
					} else {
						// Bug 2 fix: rotar las 4 esquinas UV alrededor del centro del frame.
						// Necesario cuando TexturePacker rotó el sprite 90° en el atlas.
						// Inline para evitar allocs (sin array temporal).

						// TL: (uL, vTop2)
						var du:Float = uL - _uvUCen;
						var dv:Float = vTop2 - _uvVCen;
						_uvts[vi] = du * _uvCosA - dv * _uvSinA + _uvUCen;
						_uvts[vi + 1] = du * _uvSinA + dv * _uvCosA + _uvVCen;

						// TR: (uR, vTop2)
						du = uR - _uvUCen;
						dv = vTop2 - _uvVCen;
						_uvts[vi + 2] = du * _uvCosA - dv * _uvSinA + _uvUCen;
						_uvts[vi + 3] = du * _uvSinA + dv * _uvCosA + _uvVCen;

						// BL: (uL, vBot2)
						du = uL - _uvUCen;
						dv = vBot2 - _uvVCen;
						_uvts[vi + 4] = du * _uvCosA - dv * _uvSinA + _uvUCen;
						_uvts[vi + 5] = du * _uvSinA + dv * _uvCosA + _uvVCen;

						// BR: (uR, vBot2)
						du = uR - _uvUCen;
						dv = vBot2 - _uvVCen;
						_uvts[vi + 6] = du * _uvCosA - dv * _uvSinA + _uvUCen;
						_uvts[vi + 7] = du * _uvSinA + dv * _uvCosA + _uvVCen;
					}
				}

				// ── Enviar al pipeline de HaxeFlixel ─────────────────────────
				//
				// startTrianglesBatch() devuelve (o reutiliza) un FlxDrawTrianglesItem
				// del pipeline de la cámara para el atlas de esta nota.
				// isColored=false: sin colores por vértice (alpha uniforme de la nota
				// lo aplica el motor internamente a través del blend mode y alpha del
				// ítem padre).

				var dc:FlxDrawTrianglesItem = cam.startTrianglesBatch(graphic, note.antialiasing, false, // isColored — sin per-vertex color
					note.blend // blend mode de la nota
				);
				if (dc == null)
					continue;

				// scrollFactor de notas en camHUD es (1,1) pero camHUD.scroll=(0,0),
				// por lo que el punto de desplazamiento efectivo es (0,0).
				// Se usa FlxPoint.weak() para devolver al pool automáticamente.
				var scrollPt = FlxPoint.weak(cam.scroll.x * -note.scrollFactor.x, cam.scroll.y * -note.scrollFactor.y);

				// cameraBounds=null desactiva culling por frústum (NoteManager ya lo hace)
				dc.addTriangles(_verts, _idx, _uvts, null, scrollPt, null);
			}
		}
	}
}
