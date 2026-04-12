package extensions;

// ─────────────────────────────────────────────────────────────────────────────
// VSyncAPI — Control nativo de VSync en tiempo de ejecución.
//
// Implementa VSync sin depender de lime.ui.Window.vsync (que no existe
// en muchas versiones de Lime) accediendo directamente a la API de
// intercambio de buffers OpenGL de cada plataforma:
//
//   Windows  → wglSwapIntervalEXT   (extensión WGL_EXT_swap_control)
//   Linux    → glXSwapIntervalMESA  (MESA) + glXSwapIntervalEXT (SGI) fallback
//   macOS    → CGLSetParameter(kCGLCPSwapInterval)
//
// En todas las plataformas:
//   0 = VSync OFF  (sin límite / tan rápido como la GPU pueda)
//   1 = VSync ON   (sincronizado con el refresco del monitor)
//
// Uso desde Haxe:
//   VSyncAPI.setVSync(true);   // activar
//   VSyncAPI.setVSync(false);  // desactivar
//   var on = VSyncAPI.isVSyncEnabled(); // consultar
//
// ─────────────────────────────────────────────────────────────────────────────

#if (cpp && windows)

@:buildXml('
<target id="haxe">
    <lib name="opengl32.lib" if="windows" />
    <lib name="gdi32.lib"    if="windows" />
</target>
')
@:headerCode('
#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <GL/gl.h>

// WGL_EXT_swap_control — control de intervalo de swap
typedef BOOL (WINAPI * PFNWGLSWAPINTERVALEXTPROC)(int interval);
typedef int  (WINAPI * PFNWGLGETSWAPINTERVALEXTPROC)(void);

static PFNWGLSWAPINTERVALEXTPROC    _wglSwapIntervalEXT    = nullptr;
static PFNWGLGETSWAPINTERVALEXTPROC _wglGetSwapIntervalEXT = nullptr;
static bool _vsync_initialized = false;

static void _initVSyncProcs() {
    if (_vsync_initialized) return;
    _vsync_initialized = true;
    _wglSwapIntervalEXT    = (PFNWGLSWAPINTERVALEXTPROC)   wglGetProcAddress("wglSwapIntervalEXT");
    _wglGetSwapIntervalEXT = (PFNWGLGETSWAPINTERVALEXTPROC)wglGetProcAddress("wglGetSwapIntervalEXT");
}

#undef TRUE
#undef FALSE
#undef NO_ERROR
')
class VSyncAPI
{
    /** Activa o desactiva el VSync a través de wglSwapIntervalEXT. */
    @:functionCode('
        _initVSyncProcs();
        if (_wglSwapIntervalEXT != nullptr) {
            _wglSwapIntervalEXT(enable ? 1 : 0);
        }
    ')
    public static function setVSync(enable:Bool):Void {}

    /** Devuelve true si el VSync está activo. */
    @:functionCode('
        _initVSyncProcs();
        if (_wglGetSwapIntervalEXT != nullptr) {
            return _wglGetSwapIntervalEXT() > 0;
        }
        return false;
    ')
    public static function isVSyncEnabled():Bool { return false; }
}

#elseif (cpp && linux)

@:buildXml('
<target id="haxe">
    <lib name="-lGL" if="linux" />
    <lib name="-lX11" if="linux" />
</target>
')
@:headerCode('
#include <GL/glx.h>
#include <dlfcn.h>
#include <string.h>

typedef void (*PFNGLXSWAPINTERVALEXTPROC)(Display*, GLXDrawable, int);
typedef int  (*PFNGLXSWAPINTERVALMESAPROC)(unsigned int);
typedef int  (*PFNGLXGETSWAPINTERVALMESAPROC)(void);

static PFNGLXSWAPINTERVALEXTPROC     _glXSwapIntervalEXT  = nullptr;
static PFNGLXSWAPINTERVALMESAPROC    _glXSwapIntervalMESA = nullptr;
static PFNGLXGETSWAPINTERVALMESAPROC _glXGetSwapIntervalMESA = nullptr;
static bool _glx_initialized = false;

static void* _glGetProc(const char* name) {
    typedef void* (*PFNglXGetProcAddressARB)(const GLubyte*);
    static PFNglXGetProcAddressARB _glXGetProcAddressARB = nullptr;
    if (!_glXGetProcAddressARB) {
        void* libGL = dlopen("libGL.so.1", RTLD_LAZY | RTLD_GLOBAL);
        if (!libGL) libGL = dlopen("libGL.so", RTLD_LAZY | RTLD_GLOBAL);
        if (libGL) _glXGetProcAddressARB = (PFNglXGetProcAddressARB)dlsym(libGL, "glXGetProcAddressARB");
    }
    if (_glXGetProcAddressARB) return (void*)_glXGetProcAddressARB((const GLubyte*)name);
    return nullptr;
}

static void _initGLXProcs() {
    if (_glx_initialized) return;
    _glx_initialized = true;
    _glXSwapIntervalEXT     = (PFNGLXSWAPINTERVALEXTPROC)    _glGetProc("glXSwapIntervalEXT");
    _glXSwapIntervalMESA    = (PFNGLXSWAPINTERVALMESAPROC)   _glGetProc("glXSwapIntervalMESA");
    _glXGetSwapIntervalMESA = (PFNGLXGETSWAPINTERVALMESAPROC)_glGetProc("glXGetSwapIntervalMESA");
}
')
class VSyncAPI
{
    @:functionCode('
        _initGLXProcs();
        int interval = enable ? 1 : 0;
        if (_glXSwapIntervalMESA != nullptr) {
            _glXSwapIntervalMESA(interval);
        } else if (_glXSwapIntervalEXT != nullptr) {
            Display* dpy = glXGetCurrentDisplay();
            GLXDrawable drawable = glXGetCurrentDrawable();
            if (dpy && drawable) _glXSwapIntervalEXT(dpy, drawable, interval);
        }
    ')
    public static function setVSync(enable:Bool):Void {}

    @:functionCode('
        _initGLXProcs();
        if (_glXGetSwapIntervalMESA != nullptr) {
            return _glXGetSwapIntervalMESA() > 0;
        }
        return false;
    ')
    public static function isVSyncEnabled():Bool { return false; }
}

#elseif (cpp && mac)
@:buildXml('
<target id="haxe">
    <lib name="-framework" if="mac" />
    <lib name="OpenGL"     if="mac" />
</target>
')
@:headerCode('
#include <OpenGL/OpenGL.h>
#ifndef kCGLCPSwapInterval
  #define kCGLCPSwapInterval 222
#endif
')
class VSyncAPI
{
    @:functionCode('
        CGLContextObj ctx = CGLGetCurrentContext();
        if (ctx) {
            GLint interval = enable ? 1 : 0;
            CGLSetParameter(ctx, (CGLContextParameter)kCGLCPSwapInterval, &interval);
        }
    ')
    public static function setVSync(enable:Bool):Void {}

    @:functionCode('
        CGLContextObj ctx = CGLGetCurrentContext();
        if (ctx) {
            GLint interval = 0;
            CGLGetParameter(ctx, (CGLContextParameter)kCGLCPSwapInterval, &interval);
            return interval > 0;
        }
        return false;
    ')
    public static function isVSyncEnabled():Bool { return false; }
}

#elseif mobileC

// ──────────────────────────────────────────────────────────────────────────────
//  Android / iOS — VSync via la ventana de Lime (SDL swap interval).
//
//  VSyncAPI no puede usar directamente wgl/glX/CGL en móvil porque el contexto
//  OpenGL ES está gestionado por SDL/EGL, no por las extensiones de escritorio.
//  Lime expone lime.ui.Window.vsync que internamente llama SDL_GL_SetSwapInterval,
//  que sí funciona en Android (EGL) e iOS (EAGL/CADisplayLink).
//
//  Por qué importa:
//    • Sin esto, setVSync() es un stub vacío → el VSync nunca se aplica en móvil.
//    • SDL puede resetear el swap interval al recrear la superficie EGL cuando la
//      app vuelve de segundo plano. Re-llamar setVSync() desde _onMobileActivate
//      (junto con este bloque) garantiza que el estado se restaura correctamente.
// ──────────────────────────────────────────────────────────────────────────────
class VSyncAPI
{
    /**
     * Activa o desactiva el VSync en la ventana de Lime/SDL.
     * Internamente llama SDL_GL_SetSwapInterval(1|0) en Android/iOS.
     */
    public static function setVSync(enable:Bool):Void
    {
        // 1. Obtenemos la aplicación actual de forma segura
        var app = lime.app.Application.current;
        if (app != null && app.window != null)
        {
            var win = app.window;
            try {
                // 2. Reflect.setProperty es "invisible" para el compilador.
                // Si la propiedad existe en el móvil, la cambia. Si no, no pasa nada.
                Reflect.setProperty(win, "vsync", enable);
            } catch(e:Dynamic) {
                // Silenciamos cualquier error en tiempo de ejecución
            }
        }
    }

    /**
     * Consulta el estado del VSync de forma segura.
     */
    public static function isVSyncEnabled():Bool
    {
        var app = lime.app.Application.current;
        if (app != null && app.window != null)
        {
            try {
                // Intentamos obtener el valor dinámicamente
                var val:Dynamic = Reflect.getProperty(app.window, "vsync");
                if (val != null) return (val == true);
            } catch(e:Dynamic) {}
        }
        return false;
    }
}

#else

// Otras plataformas (HTML5, etc.) — stubs vacios
class VSyncAPI
{
    public static inline function setVSync(enable:Bool):Void {}
    public static inline function isVSyncEnabled():Bool return false;
}

#end
