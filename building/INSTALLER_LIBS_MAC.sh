#!/bin/bash
# ===============================================
#   FNF Cool Engine — Environment Setup — macOS
# ===============================================
# Prerequisites:
#   - Git          (xcode-select --install)
#   - Homebrew     (https://brew.sh)
# ===============================================

set -e

HAXE_VERSION="4.3.6"
LIME_VERSION="8.3.1"
OPENFL_VERSION="9.5.1"

echo "==============================================="
echo "   FNF Cool Engine — Environment Setup — macOS"
echo "==============================================="
echo ""
echo "Requirements: Git + Homebrew"
echo ""
read -rp "Press ENTER to continue..."

# ── Neko ─────────────────────────────────────────
echo ""
echo "Installing Neko via Homebrew..."
brew install neko
sudo mkdir -p /usr/local/lib
sudo ln -sf "$(brew --prefix neko)/lib/libneko.2.dylib" /usr/local/lib/libneko.2.dylib

# ── Haxe ─────────────────────────────────────────
echo ""
echo "Installing Haxe $HAXE_VERSION..."
curl -fsSL "https://github.com/HaxeFoundation/haxe/releases/download/${HAXE_VERSION}/haxe-${HAXE_VERSION}-osx.tar.gz" -o haxe.tar.gz
tar -xzf haxe.tar.gz
HAXE_DIR="$(pwd)/$(tar -tzf haxe.tar.gz | head -1 | cut -d/ -f1)"
export PATH="$HAXE_DIR:$PATH"
export HAXE_STD_PATH="$HAXE_DIR/std"
mkdir -p ~/haxelib
"$HAXE_DIR/haxelib" setup ~/haxelib
rm haxe.tar.gz
echo "Haxe installed at: $HAXE_DIR"

# ── libvlc ──────────────────────────────────────
echo ""
echo "Installing VLC (libvlc) via Homebrew..."
brew install --cask vlc

# ── Clean conflicting libraries ──────────────────
echo ""
echo "Cleaning conflicting libraries..."
haxelib remove flixel        2>/dev/null || true
haxelib remove openfl        2>/dev/null || true
haxelib remove lime          2>/dev/null || true
haxelib remove flixel-addons 2>/dev/null || true

# ── Core ─────────────────────────────────────────
echo ""
echo "Installing core dependencies..."
haxelib install hxcpp  --quiet --never
haxelib install lime   $LIME_VERSION   --never
haxelib install openfl $OPENFL_VERSION --never
haxelib set    lime    $LIME_VERSION
haxelib set    openfl  $OPENFL_VERSION

# ── HaxeFlixel ───────────────────────────────────
echo ""
echo "Installing HaxeFlixel (FunkinCrew fork)..."
haxelib install flixel 6.1.2         --never
haxelib install flixel-addons  4.0.1 --never
haxelib install extension-haptics
haxelib git funkin.vis     https://github.com/FunkinCrew/funkVis        --never
haxelib git    coolui https://github.com/The-Cool-Engine-Crew/coolui --never
haxelib install flixel-tools 1.5.1  --quiet --never
haxelib git grig.audio     https://github.com/FunkinCrew/grig.audio
haxelib install tink_core --quiet --never

# ── Additional ───────────────────────────────────
echo ""
echo "Installing additional libraries..."
haxelib install actuate           --quiet --never
haxelib install hscript           --quiet --never
haxelib install linc_luajit          --quiet --never
haxelib install hxcpp-debug-server --quiet --never
haxelib install format            --quiet --never
haxelib install hxp               --quiet --never

# ── Discord RPC, flxanimate, hxvlc ───────────────
echo ""
echo "Installing Discord RPC, flxanimate, hxvlc..."
haxelib git discord_rpc    https://github.com/Aidan63/linc_discord-rpc  --never
haxelib git flixel-animate https://github.com/MaybeMaru/flixel-animate  --never
haxelib git hxvlc          https://github.com/MAJigsaw77/hxvlc.git      --never

# ── Lime setup + rebuild for arm64 ───────────────
echo ""
echo "Setting up Lime..."
haxelib run lime setup -y

echo ""
echo "Rebuilding Lime native libs for arm64..."
haxelib run lime rebuild mac

# ── Done ─────────────────────────────────────────
echo ""
echo "==============================================="
echo "Setup completed!"
echo "==============================================="
echo ""
echo "Versions installed:"
echo "  Lime:           $LIME_VERSION"
echo "  OpenFL:         $OPENFL_VERSION"
echo "  Flixel:         6.1.2"
echo "  flixel-addons:  4.0.1"
echo "  flixel-animate: MaybeMaru/flixel-animate (git)
  coolui:         The-Cool-Engine-Crew/coolui (git)"
echo "  funkin.vis:     FunkinCrew/funkVis (git)"
echo "  hxvlc:          MAJigsaw77/hxvlc (git)"
echo "  discord_rpc:    Aidan63/linc_discord-rpc (git)"
echo ""
echo "To compile:"
echo "  haxelib run lime build mac"
echo "  haxelib run lime build mac -debug"
echo ""
read -rp "Press ENTER to exit."
