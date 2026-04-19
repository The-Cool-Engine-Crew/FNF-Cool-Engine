@echo off
title FNF Cool Engine — Environment Setup
color 0A

echo ===============================================
echo      FNF Cool Engine — Environment Setup
echo ===============================================
echo.
echo This script installs a COMPATIBLE HaxeFlixel
echo environment for FNF Cool Engine.
echo.
echo Requirements:
echo  - Haxe 4.3.6  (haxe.org/download)
echo  - Git          (git-scm.com)
echo  - Visual Studio Build Tools (windows)
echo.
pause

:: ── Versions ──────────────────────────────────────
set LIME_VERSION=8.3.1
set OPENFL_VERSION=9.5.1

cls
echo ===============================================
echo Cleaning conflicting libraries...
echo ===============================================

haxelib remove flixel        >nul 2>&1
haxelib remove openfl        >nul 2>&1
haxelib remove lime          >nul 2>&1
haxelib remove flixel-addons >nul 2>&1

cls
echo ===============================================
echo Installing core dependencies...
echo ===============================================

haxelib install hxcpp    --quiet --never
haxelib install lime     %LIME_VERSION%   --never
haxelib install openfl   %OPENFL_VERSION% --never
haxelib set    lime      %LIME_VERSION%
haxelib set    openfl    %OPENFL_VERSION%

cls
echo ===============================================
echo Installing HaxeFlixel (FunkinCrew fork)...
echo ===============================================

haxelib install flixel 6.1.2          --never
haxelib install flixel-addons  4.0.1 --never
haxelib git funkin.vis https://github.com/FunkinCrew/funkVis         --never
haxelib git coolui https://github.com/The-Cool-Engine-Crew/coolui --never
haxelib install flixel-tools 1.5.1  --quiet --never
haxelib install extension-haptics

haxelib git grig.audio     https://github.com/FunkinCrew/grig.audio          --never
haxelib install tink_core --quiet --never

cls
echo ===============================================
echo Installing additional libraries...
echo ===============================================

haxelib install actuate          --quiet --never
haxelib install hscript          --quiet --never
haxelib install hxcpp-debug-server --quiet --never
haxelib install format           --quiet --never
haxelib install linc_luajit        --quiet --never
haxelib install hxp              --quiet --never

cls
echo ===============================================
echo Installing Discord RPC, flxanimate, hxvlc...
echo ===============================================

haxelib git discord_rpc   https://github.com/Aidan63/linc_discord-rpc   --never
haxelib git flixel-animate https://github.com/MaybeMaru/flixel-animate  --never
haxelib git hxvlc          https://github.com/MAJigsaw77/hxvlc.git      --never

cls
echo ===============================================
echo Setting up Lime...
echo ===============================================

haxelib run lime setup -y

cls
echo ===============================================
echo Setup completed!
echo ===============================================
echo.
echo Versions installed:
echo   Lime:           %LIME_VERSION%
echo   OpenFL:         %OPENFL_VERSION%
echo   Flixel:         6.1.2
echo   flixel-addons:  4.0.1
echo   flixel-animate: MaybeMaru/flixel-animate (git)
echo   coolui:         The-Cool-Engine-Crew/coolui (git)
echo   funkin.vis:     FunkinCrew/funkVis (git)
echo   hxvlc:          MAJigsaw77/hxvlc (git)
echo   discord_rpc:    Aidan63/linc_discord-rpc (git)
echo.
echo To compile:
echo   haxelib run lime build windows
echo   haxelib run lime build windows -debug
echo.
pause
exit
