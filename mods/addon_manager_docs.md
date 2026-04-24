# AddonManager

**AddonManager** is the system responsible for loading and managing
engine addons.

------------------------------------------------------------------------

## What is an Addon vs a Mod

### Mod

A **mod** adds game content such as:

-   Songs
-   Characters
-   Stages
-   Skins
-   Scripts

Mods live in:

    mods/<id>/

Mods **cannot change the engine's internal behavior**.\
They only extend gameplay through the systems already exposed by the
engine.

------------------------------------------------------------------------

### Addon

An **addon** extends the **engine itself**.

Addons can:

-   Register new systems accessible from mod scripts
-   Intercept gameplay hooks (`onNoteHit`, `onBeat`, `onUpdate`, etc.)
-   Expose new APIs to the **HScript ScriptAPI**
-   Change global gameplay mechanics
-   Be enabled or disabled independently from mods

Addons live in:

    addons/<id>/addon.json

------------------------------------------------------------------------

# Expected Folder Structure in 
    assets/...
    manifest/...
    mods/...
    addons/
    └── my-addon/
        ├── addon.json        # metadata and hook/system declarations
        ├── scripts/
        │   ├── onNoteHit.hx
        │   ├── onMissNote.hx
        │   ├── onSongStart.hx
        │   ├── exposeAPI.hx
        │   └── onUpdate.hx
        │
        └── assets/           # optional addon resources
            ├── images/
            └── data/

### File descriptions

  -----------------------------------------------------------------------
  File                             Purpose
  -------------------------------- --------------------------------------
  `addon.json`                     Contains metadata and declares which
                                   hooks the addon uses

  `onNoteHit.hx`                   Runs when a note is successfully hit

  `onMissNote.hx`                  Runs when a note is missed

  `onSongStart.hx`                 Runs when the song begins

  `exposeAPI.hx`                   Exposes new variables and functions to
                                   the HScript API

  `onUpdate.hx`                    Runs every frame
  -----------------------------------------------------------------------

------------------------------------------------------------------------

# Addon Loading Flow

### Engine Startup

    Main.setupGame()
      → AddonManager.init()
          loads all enabled addons

      → AddonManager.callHook("exposeAPI", interp)
          exposes addon APIs to HScript

------------------------------------------------------------------------

### PlayState Lifecycle

    PlayState.create()
      → AddonManager.callHook("onStateCreate", args)

    PlayState.update(elapsed)
      → AddonManager.callHook("onUpdate", args)

    PlayState.onNoteHit(note)
      → AddonManager.callHook("onNoteHit", args)

------------------------------------------------------------------------

# Summary

  Type        Purpose                        Location
  ----------- ------------------------------ ----------------
  **Mod**     Adds gameplay content          `mods/<id>/`
  **Addon**   Extends engine functionality   `addons/<id>/`

Mods focus on **content**, while addons extend the **engine
architecture**.
