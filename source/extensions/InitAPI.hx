package extensions;

// ─────────────────────────────────────────────────────────────────────────────
// InitAPI — funciones nativas de ventana por plataforma.
//
// ─── Windows (DWM / User32) ───────────────────────────────────────────────────
//  setWindowBorderColor(r,g,b)  — tint DWM Win11 (DWMWA_BORDER_COLOR)
//  setWindowCaptionColor(r,g,b) — tint título DWM Win11 (DWMWA_CAPTION_COLOR)
//  setDarkMode(enable)          — Win10 1809+ dark/light frame
//  setDPIAware()                — SetProcessDPIAware para monitores HiDPI
//  hasValidWindow()             — true si se pudo obtener un HWND válido
//
// ─── macOS (AppKit / NSAppearance) ────────────────────────────────────────────
//  setDarkMode(enable)          — NSApp.appearance = Dark/Light Aqua (10.14+)
//  hasValidWindow()             — siempre true (NSApp disponible desde el arranque)
//
// ─── Linux (GTK / putenv) ─────────────────────────────────────────────────────
//  setDarkMode(enable)          — GTK_THEME=Adwaita:dark  (debe llamarse ANTES
//                                 de que se cree la ventana, desde __init__)
//  hasValidWindow()             — siempre true
//
// ─────────────────────────────────────────────────────────────────────────────

// ══════════════════════════════════════════════════════════════════════════════
//  WINDOWS
// ══════════════════════════════════════════════════════════════════════════════
#if (windows && cpp)

@:buildXml('
<target id="haxe">
    <lib name="dwmapi.lib"  if="windows" />
    <lib name="user32.lib"  if="windows" />
</target>
')
@:headerCode('
#include <Windows.h>
#include <cstdio>
#include <iostream>
#include <tchar.h>
#include <dwmapi.h>
#include <winuser.h>
#include <vector>
#include <string>
#undef TRUE
#undef FALSE
#undef NO_ERROR

// DWMWA constants que pueden no estar en SDKs viejos
#ifndef DWMWA_BORDER_COLOR
  #define DWMWA_BORDER_COLOR   34
#endif
#ifndef DWMWA_CAPTION_COLOR
  #define DWMWA_CAPTION_COLOR  35
#endif
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
  #define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

static BOOL CALLBACK _enumGameWindow(HWND w, LPARAM lParam) {
    DWORD pid = 0;
    GetWindowThreadProcessId(w, &pid);
    if (pid == GetCurrentProcessId() && IsWindowVisible(w) && GetParent(w) == NULL) {
        *(HWND*)lParam = w;
        return false;
    }
    return true;
}

static inline HWND _getGameHwnd() {
    HWND hwnd = GetActiveWindow();
    if (hwnd != NULL) return hwnd;
    hwnd = GetForegroundWindow();
    if (hwnd != NULL) {
        DWORD pid = 0;
        GetWindowThreadProcessId(hwnd, &pid);
        if (pid == GetCurrentProcessId()) return hwnd;
    }

    hwnd = NULL;
    EnumWindows(_enumGameWindow, (LPARAM)&hwnd);
    return hwnd;
}
')
class InitAPI
{
    /**
     * Devuelve true si se puede obtener un HWND valido para la ventana del juego.
     * Usar como guarda antes de llamar a las funciones DWM; si devuelve false,
     * reintentar en el siguiente ENTER_FRAME.
     */
    @:functionCode('
        return (_getGameHwnd() != NULL);
    ')
    public static function hasValidWindow():Bool { return false; }

    /**
     * Cambia el color del borde de la ventana (DWMWA_BORDER_COLOR).
     * Solo visible en Windows 11 (build 22000+).
     */
    @:functionCode('
        HWND hwnd = _getGameHwnd();
        if (hwnd == NULL) return;
        COLORREF color = RGB(r, g, b);
        DwmSetWindowAttribute(hwnd, DWMWA_BORDER_COLOR, &color, sizeof(COLORREF));
        UpdateWindow(hwnd);
    ')
    public static function setWindowBorderColor(r:Int, g:Int, b:Int):Void {}

    /**
     * Cambia el color del caption/titlebar (DWMWA_CAPTION_COLOR).
     * Solo visible en Windows 11 (build 22000+).
     */
    @:functionCode('
        HWND hwnd = _getGameHwnd();
        if (hwnd == NULL) return;
        COLORREF color = RGB(r, g, b);
        DwmSetWindowAttribute(hwnd, DWMWA_CAPTION_COLOR, &color, sizeof(COLORREF));
        UpdateWindow(hwnd);
    ')
    public static function setWindowCaptionColor(r:Int, g:Int, b:Int):Void {}

    /**
     * Activa/desactiva el frame oscuro (DWMWA_USE_IMMERSIVE_DARK_MODE).
     * Disponible en Windows 10 build 1809+ y Windows 11.
     * Intenta primero el atributo 20 (Win11 / Win10 21H1+) y hace fallback al
     * atributo 19 (Win10 1809-20H2) si el primero falla.
     */
    @:functionCode('
        HWND hwnd = _getGameHwnd();
        if (hwnd == NULL) return;
        BOOL darkMode = (BOOL)enable;
        if (S_OK != DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &darkMode, sizeof(BOOL))) {
            // Fallback: atributo 19 usado en Win10 1809-20H2
            DwmSetWindowAttribute(hwnd, 19, &darkMode, sizeof(BOOL));
        }
        UpdateWindow(hwnd);
    ')
    public static function setDarkMode(enable:Bool):Void {}

    /**
     * Registra el proceso como DPI-aware.
     * Llamar antes de que se cree cualquier ventana (en __init__).
     * Sin esto, Windows escala el framebuffer en monitores HiDPI -> blur + coords incorrectas.
     */
    @:functionCode('
        SetProcessDPIAware();
    ')
    public static function setDPIAware():Void {}
}

// ══════════════════════════════════════════════════════════════════════════════
//  macOS  — NSAppearance via AppKit
// ══════════════════════════════════════════════════════════════════════════════
#elseif (mac && cpp)
@:buildXml('
<target id="haxe">
    <compilerflag value="-ObjC++" if="mac" />
    <vflag name="-framework" value="AppKit" if="mac" />
</target>
')
@:cppFileCode('
#import <AppKit/AppKit.h>
')
@:objc
class InitAPI
{
    public static inline function hasValidWindow():Bool return true;

    @:functionCode('
        if (@available(macOS 10.14, *)) {
            NSAppearanceName name = enable
                ? NSAppearanceNameDarkAqua
                : NSAppearanceNameAqua;
            [NSApp setAppearance:[NSAppearance appearanceNamed:name]];
        }
    ')
    public static function setDarkMode(enable:Bool):Void {}

    public static inline function setWindowBorderColor(r:Int, g:Int, b:Int):Void {}
    public static inline function setWindowCaptionColor(r:Int, g:Int, b:Int):Void {}
    public static inline function setDPIAware():Void {}
}

// ══════════════════════════════════════════════════════════════════════════════
//  Linux  — GTK_THEME via putenv
//  IMPORTANTE: setDarkMode() debe llamarse ANTES de que SDL/Lime inicialice GTK
//  (es decir, desde Main.__init__() o muy al inicio de setupStage()).
//  Una vez que GTK ha creado la ventana, el cambio de env var no tiene efecto
//  en la sesion actual.
// ══════════════════════════════════════════════════════════════════════════════
#elseif (linux && cpp)

@:headerCode('
#include <stdlib.h>
')
class InitAPI
{
    public static inline function hasValidWindow():Bool return true;

    /**
     * Establece GTK_THEME=Adwaita:dark (o Adwaita) para que la ventana SDL/GTK
     * use el tema oscuro del sistema.
     * Llamar desde __init__() ANTES de que se cree la ventana.
     */
    @:functionCode('
        if (enable) {
            putenv((char*)"GTK_THEME=Adwaita:dark");
        } else {
            putenv((char*)"GTK_THEME=Adwaita");
        }
    ')
    public static function setDarkMode(enable:Bool):Void {}

    public static inline function setWindowBorderColor(r:Int, g:Int, b:Int):Void {}
    public static inline function setWindowCaptionColor(r:Int, g:Int, b:Int):Void {}
    public static inline function setDPIAware():Void {}
}

// ══════════════════════════════════════════════════════════════════════════════
//  Otras plataformas (HTML5, consolas, etc.) — stubs vacios
// ══════════════════════════════════════════════════════════════════════════════
#else

class InitAPI
{
    public static inline function hasValidWindow():Bool                       return true;
    public static inline function setWindowBorderColor(r:Int, g:Int, b:Int):Void {}
    public static inline function setWindowCaptionColor(r:Int, g:Int, b:Int):Void {}
    public static inline function setDarkMode(enable:Bool):Void               {}
    public static inline function setDPIAware():Void                          {}
}

#end
