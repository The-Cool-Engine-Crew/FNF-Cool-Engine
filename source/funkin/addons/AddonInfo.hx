package funkin.addons;

/**
 * AddonInfo — Metadatos de un addon cargados desde addon.json.
 *
 * ─── Ejemplo de addon.json ────────────────────────────────────────────────────
 * {
 *   "id":          "my-addon",
 *   "name":        "My Addon",
 *   "description": "Añade mecánicas de combo extendidas",
 *   "author":      "NombreAutor",
 *   "version":     "1.0.0",
 *   "priority":    10,
 *   "enabled":     true,
 *
 *   "systems": ["comboSystem", "scoreMultiplier"],
 *
 *   "hooks": {
 *     "onNoteHit":       "scripts/onNoteHit.hx",
 *     "onMissNote":      "scripts/onMiss.hx",
 *     "onSongStart":     "scripts/onSongStart.hx",
 *     "onSongEnd":       "scripts/onSongEnd.hx",
 *     "onBeat":          "scripts/onBeat.hx",
 *     "onStep":          "scripts/onStep.hx",
 *     "onUpdate":        "scripts/onUpdate.hx",
 *     "onCountdown":     "scripts/onCountdown.hx",
 *     "onGameOver":      "scripts/onGameOver.hx",
 *     "onStateCreate":   "scripts/onStateCreate.hx",
 *     "onStateSwitch":   "scripts/onStateSwitch.hx",
 *     "exposeAPI":       "scripts/exposeAPI.hx"
 *   },
 *
 *   "modCompat": ["my-mod", "other-mod"],
 *   "requires":  ["base-addon >= 1.0.0"]
 * }
 */
typedef AddonInfo = {
	/** Identificador único del addon (nombre de carpeta). */
	var id: String;
	/** Nombre visible. */
	var name: String;
	/** Descripción. */
	var ?description: String;
	/** Autor. */
	var ?author: String;
	/** Versión semántica. */
	var ?version: String;
	/** Prioridad de carga (mayor = se carga antes). Default: 0. */
	var ?priority: Int;
	/** Si false, el addon no se carga. Default: true. */
	var ?enabled: Bool;

	/**
	 * Sistemas que este addon registra.
	 * Son identificadores usados por mods para declarar dependencia.
	 * Ejemplo: ["3dScene", "comboExtended", "customNoteTypes"]
	 */
	var ?systems: Array<String>;

	/**
	 * Mapa de hooks a scripts HScript.
	 * Cada clave es el nombre del hook, el valor es la ruta al .hx relativa
	 * a la carpeta del addon.
	 */
	var ?hooks: Dynamic;

	/**
	 * Lista explícita de librerías HScript que este addon provee.
	 * Cada entrada es una ruta relativa a la carpeta del addon, sin extensión.
	 * Ejemplo: ["MiLib", "utils/StringUtils"]
	 *
	 * Si se omite, AddonManager auto-escanea la carpeta `libs/` del addon
	 * y registra todos los .hx que encuentre.
	 *
	 * Las libs quedan disponibles via require() tanto para scripts del addon
	 * como para scripts de mods activos (fallback de búsqueda global).
	 */
	var ?libs: Array<String>;

	/**
	 * IDs de mods con los que este addon es compatible/diseñado.
	 * Si es null/vacío = compatible con todos.
	 */
	var ?modCompat: Array<String>;

	/**
	 * Addons requeridos (con versión mínima opcional).
	 * Ejemplo: ["base-addon >= 1.0.0"]
	 */
	var ?requires: Array<String>;

	/**
	 * Dependencias externas de librerías HScript.
	 * Se descargan desde GitHub u otras URLs en tiempo de ejecución
	 * y se cachean en `addons/<id>/.deps/`.
	 * Quedan disponibles vía require() exactamente igual que las libs locales.
	 *
	 * Ejemplos:
	 *
	 *   // URL directa a un .hx crudo
	 *   { "name": "EaseLib", "url": "https://raw.githubusercontent.com/user/repo/main/Ease.hx" }
	 *
	 *   // Shorthand GitHub con un único archivo
	 *   { "name": "ArrayUtils", "github": "user/repo", "branch": "main", "path": "src/ArrayUtils.hx" }
	 *
	 *   // Múltiples archivos del mismo repo
	 *   { "github": "user/repo", "paths": [
	 *       { "name": "Foo", "path": "src/Foo.hx" },
	 *       { "name": "Bar", "path": "src/Bar.hx" }
	 *   ]}
	 *
	 * IMPORTANTE: sólo funcionan librerías Haxe puras sin macros, externs
	 * ni bindings nativos — HScript es un intérprete, no un compilador.
	 */
	var ?dependencies: Array<funkin.addons.ScriptDependency.ScriptDepInfo>;
}
