# [Cool Engine REBORN (70%)](https://github.com/The-Cool-Engine-Crew/FNF-Cool-Engine)

> **Note**
> This engine is currently a work in progress. If you find any bugs or unexpected behavior, please open an issue in the repository.
> It may contain [Psych Engine](https://github.com/ShadowMario/FNF-PsychEngine), [NMV](https://github.com/NMVTeam/NightmareVision), [CNE](https://github.com/CodenameCrew/CodenameEngine), and [V-Slice](https://github.com/FunkinCrew/Funkin) code, things just for optimization and to make mod porting possible.

[![Build Cool Engine](https://github.com/The-Cool-Engine-Crew/FNF-Cool-Engine/actions/workflows/main.yml/badge.svg)](https://github.com/The-Cool-Engine-Crew/FNF-Cool-Engine/actions/workflows/main.yml)


**FNF': Cool Engine is a modification of the original FNF' source code the mod includes new Options and better Graphics!!**
----------------------------------------------
<p align="center">
  <img src="/art/posterCool-min.png" width="455">
  <img src="/art/cool-logo-animated.gif" width="345">
  <img width="400" alt="Captura de pantalla 2026-03-14 203029" src="https://github.com/user-attachments/assets/af9c7d84-f749-4cf6-9d51-79d0dfcb894a" />
  <img width="400" alt="Captura de pantalla 2026-03-11 221232" src="https://github.com/user-attachments/assets/80ab40aa-9f88-414a-8cfe-d2eddcd3e51b" />
  <img width="400" alt="Captura de pantalla 2026-03-11 213628" src="https://github.com/user-attachments/assets/5294054f-44c3-4186-9004-e808eecae4d9" />
  <img width="400" alt="Captura de pantalla 2026-03-04 011947" src="https://github.com/user-attachments/assets/7016a562-e777-4034-9d64-279704331cbf" />
</p>

**MODS SUPPORT AND COMPATIBILITY WITH PSYCH MODS!**
----------------------------------------------
<p align="center">
  <img width="400" alt="Captura de pantalla 2026-02-25 163406" src="https://github.com/user-attachments/assets/349bf923-6781-4e37-a7d8-c07df237364e" />
  <img width="400" alt="Captura de pantalla 2026-03-04 162713" src="https://github.com/user-attachments/assets/4692dfb2-8450-426b-ab07-aea5c86db9d8" />
</p>

<p align="center">
    <img alt="Stars" src="https://img.shields.io/github/stars/The-Cool-Engine-Crew/FNF-Cool-Engine?style=flat-square" style=";padding-right:10px;">
    <img alt="Forks" src="https://img.shields.io/github/forks/The-Cool-Engine-Crew/FNF-Cool-Engine?style=flat-square" style=";padding-right:10px;">
    <img alt="Issues" src="https://img.shields.io/github/issues/The-Cool-Engine-Crew/FNF-Cool-Engine?style=flat-square" style=";padding-right:10px;">
    <img alt="License" src="https://img.shields.io/github/license/The-Cool-Engine-Crew/FNF-Cool-Engine?style=flat-square">
</p>

----------------------------------------------

## Cool Engine WIKI
- https://the-cool-engine-crew.github.io/FNF-Cool-Engine-Wiki/ - Link

## Cool Engine Build for Beta Testers
- https://github.com/The-Cool-Engine-Crew/FNF-Cool-Engine-Build-Beta-Tester - Link
  
## The Cool Engine Team Credits
- [Manux (me)](https://x.com/ManuxAc) - Programmer, Artist and Composer Friday Night Funkin: Cool Engine
- [Juanen100](https://github.com/Juanen100) - Programmer Friday Night Funkin: Cool Engine
- [Seevent](https://www.youtube.com/@SEEV3NT) - Guest Composer Pause Menu Friday Night Funkin: Cool Engine
- [MrClogsworthYT](https://youtube.com/c/MrClogsworthYT) -  Composer Friday Night Funkin: Cool Engine
- [Kass.wav](https://x.com/SoyJulian_XP) and [Zero Artist](https://x.com/zero_artist24) - Artists Friday Night Funkin: Cool Engine

## FNF
- [Kawaisprite](https://twitter.com/kawaisprite) - Musician of fnf
- [ninjamuffin99](https://twitter.com/ninja_muffin99) - Programmer of fnf
- [PhantomArcade3K](https://twitter.com/phantomarcade3k) - Animator of of fnf
- [Evilsk8r](https://twitter.com/evilsk8r)  - Artist of fnf

## Cool Engine Build for Beta Testers
- https://github.com/Manux123/FNF-Cool-Engine-Build-Beta-Tester - Link

# Building
THESE INSTRUCTIONS ARE FOR COMPILING THE GAME'S SOURCE CODE!!!
IF YOU JUST WANT TO PLAY AND NOT EDIT THE CODE CLICK [HERE](https://github.com/The-Cool-Engine-Crew/FNF-Cool-Engine/releases)!!!

### Installing the Required Programs

First, you need to install Haxe and HaxeFlixel. I'm too lazy to write and keep updated with that setup (which is pretty simple). 
1. [Install Haxe](https://haxe.org/download/)
2. [Install HaxeFlixel](https://haxeflixel.com/documentation/install-haxeflixel/) after downloading Haxe (This is a required step and compilation will fail if it isn't installed!)

You'll also need to install a couple things that involve Gits. To do this, you need to do a few things first.
1. Download [git-scm](https://git-scm.com/downloads). Works for Windows, and Mac, just select your build. (Linux users can install the git package via their respective package manager.)
2. Run [this](https://github.com/The-Cool-Engine-Crew/FNF-Cool-Engine/blob/master/INSTALLER_LIBS_WINDOWS_LINUX.bat), and everything should be installed automatically
if it doesnt use the errors to download the left libraries

You should have everything ready for compiling the game! Follow the guide below to continue!

NOTE: If you see any messages relating to deprecated packages, ignore them. They're just warnings that don't affect compiling

The -debug flag is completely optional.
Applying it will make a folder called `export/debug/[TARGET]/bin` instead of `export/release/[TARGET]/bin`

Once you have all those installed, it's pretty easy to compile the game. You just need to run `lime build html5 -minify` in the root of the project to build and run the HTML5 version command prompt navigation guide can be found [here](https://ninjamuffin99.newgrounds.com/news/post/1090480).
To run it from your desktop (Windows, Mac, Linux) it can be a bit more involved. For Linux, you only need to open a terminal in the project directory and run `lime test linux -debug` and then run the executable file in export/release/linux/bin. For Windows, you need to install Visual Studio Community 2019. While installing VSC, don't click on any of the options to install workloads. Instead, go to the individual components tab and choose the following:
* MSVC v142 - VS 2019 C++ x64/x86 build tools
* Windows SDK (10.0.17763.0)

Once that is done you can open up a command line in the project's directory and run `lime test windows -debug`. Once that command finishes (it takes forever even on a higher end PC), you can run FNF from the .exe file under export\release\windows\bin

As for Mac, `lime test mac -debug` will work,
----------------------------------------------

## The Cool Engine Team Legacy Credits
- [Manux (me)](https://x.com/ManuxAc) - Programmer Friday Night Funkin: Cool Engine
- [Jloor](https://twitter.com/GamerJloor) - Programmer Friday Night Funkin: Cool Engine
- [Chasetodie](https://x.com/Chasetodie10) - Programmer Friday Night Funkin: Cool Engine
- [MrClogsworthYT](https://youtube.com/c/MrClogsworthYT) - Programmer and composer Friday Night Funkin: Cool Engine
- [Overcharged Dev](https://www.youtube.com/channel/UCkcscIIXyUsfj2DsnNDWQbg/) - Programmer Friday Night Funkin: Cool Engine
- [Kass.wav](https://x.com/SoyJulian_XP) and [Zero Artist](https://x.com/zero_artist24) - Artists Friday Night Funkin: Cool Engine

ADDITIONS IN 0.4.1

- REWRITTED ALL
- Stickers!
- Freeplay Editor
- More Softcoding
- HUD for Script
- New Chart Editor
- New Character Editor
- Mods Support ZIP, RAR, Folder
- More Optimization
- Better Options

----------------------------------------------
Thanks for checking out our Engine! Do you have any question? Go to the [discussions](https://github.com/The-Cool-Engine-Crew/FNF-Cool-Engine/discussion) tab!