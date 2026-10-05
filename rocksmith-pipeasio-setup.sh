#!/usr/bin/env bash
# Rocksmith 2014 on Linux — PipeASIO setup, one shot.
#
# Builds PipeASIO with 32-bit WoW64 support, installs it to ~/.local, registers
# it in the game prefix, installs RS_ASIO, and writes both config files. Proton
# loads the driver via WINEDLLPATH, so nothing is copied into the Proton tree.
# Detects distro family, Steam library, game, prefix,
# Proton build, Wine lib root, and the guitar adapter.
#
#   ./rocksmith-pipeasio-setup.sh              full run
#   ./rocksmith-pipeasio-setup.sh --reapply    no-op, kept for old habits
#   ./rocksmith-pipeasio-setup.sh --launch CMD just exec CMD (old Steam launch
#                                              options keep working)
#   PROTON=/path/to/proton/files ./rocksmith-pipeasio-setup.sh
#
# Steam launch options must be set by hand — printed at the end.
set -euo pipefail

APPID=221680
BUILDLOG=/tmp/pipeasio-build.log

say() { printf '\n>> %s\n' "$*"; }
die() { printf '\n!! %s\n' "$*" >&2; exit 1; }

# Paths relative to the wine lib dir (~/.local/lib/wine after install).
# tests/install-layout.sh reads this list.
PIPEASIO_FILES=(
  x86_64-unix/pipeasio32.so
  x86_64-unix/pipeasio64.so
  x86_64-windows/pipeasio64.dll
  i386-windows/pipeasio32.dll
)

case "${1:-}" in
  --reapply) say "--reapply is no longer needed: the driver lives in ~/.local and loads via WINEDLLPATH, so Proton updates don't affect it."; exit 0 ;;
  --launch)  shift; exec "$@" ;;
esac

# ---------- distro family ----------
FAMILY=""
if [ -r /etc/os-release ]; then
  . /etc/os-release
  case " ${ID:-} ${ID_LIKE:-} " in
    *" fedora "*) FAMILY=fedora ;;
    *" arch "*)   FAMILY=arch ;;
    *" debian "*) FAMILY=debian ;;
  esac
fi

# ---------- locate Steam / game / prefix ----------
STEAMROOT=""
for c in "$HOME/.steam/root" "$HOME/.steam/steam" "$HOME/.local/share/Steam" \
         "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"; do
  [ -f "$c/steamapps/libraryfolders.vdf" ] && { STEAMROOT=$(readlink -f "$c"); break; }
done
[ -n "$STEAMROOT" ] || die "Steam not found."

mapfile -t LIBS < <(grep -oP '"path"\s*"\K[^"]+' "$STEAMROOT/steamapps/libraryfolders.vdf")
LIBS+=("$STEAMROOT")

LIB="" INSTALLDIR=""
for l in "${LIBS[@]}"; do
  acf="$l/steamapps/appmanifest_$APPID.acf"
  [ -f "$acf" ] && { LIB="$l"; INSTALLDIR=$(grep -oP '"installdir"\s*"\K[^"]+' "$acf"); break; }
done
[ -n "$LIB" ] || die "Rocksmith (appid $APPID) not found in any Steam library."

GAME="$LIB/steamapps/common/$INSTALLDIR"
PFX="$LIB/steamapps/compatdata/$APPID/pfx"
[ -d "$GAME" ] || die "Game folder missing: $GAME"
[ -d "$PFX" ]  || die "Prefix missing — launch the game once from Steam, quit, rerun."
say "game:   $GAME"

# ---------- Proton: prefer newest GE/CachyOS (the tested runners; Valve builds before 11.0-1 ignore PROTON_USE_WOW64) ----------
newest() {  # stdin: Proton files dirs. Highest build timestamp in <parent>/version, else sort -V
  local d t
  while read -r d; do
    t=$(awk '{print $1; exit}' "${d%/*}/version" 2>/dev/null || true)
    case "$t" in ''|*[!0-9]*) t=0 ;; esac
    printf '%s %s\n' "$t" "$d"
  done | sort -k1,1n -k2V | tail -1 | cut -d' ' -f2-
}
if [ -z "${PROTON:-}" ]; then
  mapfile -t CAND < <( { ls -d "$STEAMROOT"/compatibilitytools.d/*/files 2>/dev/null
      for l in "${LIBS[@]}"; do
        ls -d "$l"/steamapps/common/Proton*/files "$l"/steamapps/common/Proton*/dist 2>/dev/null
      done; } | while read -r d; do [ -x "$d/bin/wine" ] && echo "$d"; done )
  [ "${#CAND[@]}" -gt 0 ] || die "No Proton found. Set PROTON=... and rerun."
  GE=$(printf '%s\n' "${CAND[@]}" | grep -i -E 'GE-Proton|Proton-GE|CachyOS' | newest || true)
  PROTON="${GE:-$(printf '%s\n' "${CAND[@]}" | newest)}"
  [ -n "$GE" ] || cat <<'WARN'

   WARNING: no GE-Proton / Proton-CachyOS build found.
   PipeASIO's 32-bit front end needs PROTON_USE_WOW64=1. Valve builds before
   11.0-1 ignore it, and GE-Proton is the tested runner. Install GE-Proton 11.x
   (ProtonPlus) and rerun.

WARN
fi
[ -x "$PROTON/bin/wine" ] || die "PROTON invalid: $PROTON"
say "proton: $PROTON"

# ---------- Proton wine dll dirs (layout varies: lib/wine vs lib64/wine) ----------
find_dir() {  # $1 root, $2 dirname — must be wine's own dir, not dxvk/vkd3d/d7vk/nvapi/icu
  find "$1"/lib "$1"/lib64 "$1"/lib32 -maxdepth 3 -type d -path "*/wine/$2" -print -quit 2>/dev/null
}
P_U64=$(find_dir "$PROTON" x86_64-unix)
P_W64=$(find_dir "$PROTON" x86_64-windows)
P_W32=$(find_dir "$PROTON" i386-windows)
[ -n "$P_U64" ] && [ -n "$P_W64" ] && [ -n "$P_W32" ] \
  || die "Couldn't map Proton wine dll dirs under $PROTON"

# Proton's own lib/wine is searched before WINEDLLPATH, so old copies there would shadow the ~/.local build
purge_proton_copies() {
  local f d n=0
  for d in "$P_U64" "$P_W64" "$P_W32"; do
    for f in "${PIPEASIO_FILES[@]}" x86_64-unix/pipeasio64.dll.so; do
      [ -e "$d/$(basename "$f")" ] && { rm -f "$d/$(basename "$f")"; n=$((n+1)); }
    done
  done
  [ "$n" -eq 0 ] || say "removed $n stale PipeASIO file(s) from the Proton tree"
}

register_pipeasio() {
  say "registering in the game prefix (cancel any Wine Mono prompt)"
  # Host wine would migrate the Proton prefix, so register with Proton's own wine
  WINE="$PROTON/bin/wine" WINEPREFIX="$PFX" "$HOME/.local/bin/pipeasio-register" >/tmp/pipeasio-reg.log 2>&1 || true
  WINEPREFIX="$PFX" "$PROTON/bin/wineserver" -k >/dev/null 2>&1 || true
  if grep -q "32-bit WoW64 front end registered" /tmp/pipeasio-reg.log; then
    say "registered (64-bit + 32-bit)"
  else
    printf '   !! 32-bit registration not confirmed. See /tmp/pipeasio-reg.log\n'
  fi
}

# ---------- dependencies ----------
# cmake wants libpipewire-0.3 >= 1.4.2 and stops hard below it.
have_deps() {
  command -v cmake >/dev/null && command -v gcc >/dev/null && command -v unzip >/dev/null \
    && command -v git >/dev/null && command -v curl >/dev/null \
    && command -v winegcc >/dev/null && command -v winebuild >/dev/null \
    && pkg-config --atleast-version=1.4.2 libpipewire-0.3 \
    && command -v i686-w64-mingw32-gcc >/dev/null \
    && command -v i686-w64-mingw32-g++ >/dev/null \
    && command -v x86_64-w64-mingw32-gcc >/dev/null \
    && command -v x86_64-w64-mingw32-g++ >/dev/null
}

install_deps() {
  case "$FAMILY" in
    fedora)
      local wd="wine-devel"
      [ -d /opt/wine-staging ] && wd="wine-staging-devel"
      [ -d /opt/wine-stable ]  && wd="wine-stable-devel"
      # pkgconf has no pkg-config binary. pipewire-devel pulls in pkgconf-pkg-config, which does.
      sudo dnf install -y --skip-unavailable cmake ninja-build gcc gcc-c++ pkgconf unzip \
        git curl pipewire-devel mingw32-gcc mingw32-gcc-c++ mingw64-gcc mingw64-gcc-c++ "$wd" ;;
    arch)
      sudo pacman -S --needed --noconfirm cmake ninja gcc pkgconf unzip \
        git curl libpipewire mingw-w64-gcc wine ;;
    debian)
      sudo apt-get install -y cmake ninja-build gcc g++ pkg-config unzip \
        git curl libpipewire-0.3-dev gcc-mingw-w64-i686 g++-mingw-w64-i686 gcc-mingw-w64-x86-64 g++-mingw-w64-x86-64 wine64-tools libwine-dev ;;
    *) return 1 ;;
  esac
}

if ! have_deps; then
  say "installing build dependencies (${FAMILY:-unknown distro})"
  install_deps || true
fi
have_deps || die "Dependencies still missing: need cmake, gcc, git, curl, unzip, winegcc/winebuild (Wine SDK),
   libpipewire-0.3 >= 1.4.2 dev headers, and i686 + x86_64 MinGW cross-compilers (gcc and g++). Install them and rerun."

# ---------- Wine lib root (holds the <arch>-windows import libs) ----------
# cmake builds both front ends from one root, so it needs i386 and x86_64 import libs.
# Arch keeps an i386-only tree in /usr/lib32/wine beside the full one in /usr/lib/wine.
WLR="" WLR32=""
while read -r c; do
  r=$(dirname "$(dirname "$c")")
  [ -n "$WLR32" ] || WLR32="$r"
  [ -f "$r/x86_64-windows/libwinecrt0.a" ] || continue
  WLR="$r"; break
done < <(find /usr/lib /usr/lib64 /usr/lib32 /opt -maxdepth 5 \
           -path '*/i386-windows/libwinecrt0.a' 2>/dev/null | sort)
[ -n "$WLR32" ] || die "Couldn't find i386-windows/libwinecrt0.a — install your Wine SDK's 32-bit part."
if [ -z "$WLR" ]; then
  WLR="$WLR32"
  printf '   !! %s has no x86_64-windows import libraries, cmake may refuse it.\n' "$WLR"
fi
say "wine lib root: $WLR"

# ---------- build PipeASIO ----------
SRC=$(mktemp -d); trap 'rm -rf "$SRC"' EXIT
# pinned to the latest release: upstream HEAD moves daily and renamed outputs before
TAG=$(curl -fsSL https://api.github.com/repos/M0n7y5/pipeasio/releases/latest \
  | grep -oP '"tag_name":\s*"\K[^"]+') || true
[ -n "$TAG" ] || die "Could not resolve the latest PipeASIO release tag from the GitHub API (rate limit or network?)."
: > "$BUILDLOG"
say "cloning PipeASIO $TAG  (build log: $BUILDLOG)"
git clone --depth 1 --branch "$TAG" https://github.com/M0n7y5/pipeasio "$SRC/pipeasio" >>"$BUILDLOG" 2>&1 \
  || die "git clone failed — see $BUILDLOG"
cd "$SRC/pipeasio"

# BUILD_TESTS=OFF: the test hosts are never installed and only add ways for the build to fail.
say "building (32-bit WoW64 enabled)"
cmake -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_WOW64_32=ON -DBUILD_TESTS=OFF \
      -DBUILD_SETTINGS_PANEL=OFF -DBUILD_MANAGER=OFF \
      -DWINE_LIB_ROOT="$WLR" >>"$BUILDLOG" 2>&1 \
  || die "cmake configure failed — see $BUILDLOG"
cmake --build build -j"$(nproc)" >>"$BUILDLOG" 2>&1 \
  || die "cmake build failed — see $BUILDLOG"
[ -n "$(find build -name pipeasio32.dll -not -path '*/CMakeFiles/*' -print -quit)" ] \
  || die "32-bit front end was not built — see $BUILDLOG"

say "installing to \$HOME/.local"
cmake --install build --prefix "$HOME/.local" >>"$BUILDLOG" 2>&1 \
  || die "cmake install failed — see $BUILDLOG"
for f in "${PIPEASIO_FILES[@]}"; do
  [ -f "$HOME/.local/lib/wine/$f" ] || die "$f missing after install."
done

cd /
purge_proton_copies
register_pipeasio

# ---------- RS_ASIO (0.7.5+ required for Proton 11 / WoW64) ----------
say "installing RS_ASIO"
RS_URL=$(curl -fsSL https://api.github.com/repos/mdias/rs_asio/releases/latest \
  | grep -oP '"browser_download_url":\s*"\K[^"]+\.zip')
[ -n "$RS_URL" ] || die "Could not resolve the RS_ASIO download URL."
RSTMP=$(mktemp -d)
curl -fsSL "$RS_URL" -o "$RSTMP/rs.zip"
unzip -oq "$RSTMP/rs.zip" -d "$RSTMP/x"
# An empty find result would make dirname return ".", which is / here
RSDLL=$(find "$RSTMP/x" -name RS_ASIO.dll | head -1)
[ -n "$RSDLL" ] || { rm -rf "$RSTMP"; die "RS_ASIO.dll not found in $RS_URL"; }
cp -rf "$(dirname "$RSDLL")"/. "$GAME"/
rm -rf "$RSTMP"

cat > "$GAME/RS_ASIO.ini" <<'INI'
[Config]
EnableWasapiOutputs=0
EnableWasapiInputs=0
EnableAsio=1

[Asio]
BufferSizeMode=driver
CustomBufferSize=

[Asio.Output]
Driver=PipeASIO
BaseChannel=0

[Asio.Input.0]
Driver=PipeASIO
Channel=0
INI

# RS_ASIO needs these two keys at 1. Edit in place so LatencyBuffer etc. survive reruns.
# Missing keys go after LatencyBuffer/EnableMicrophone (the audio section). CRLF is kept.
set_rs_ini() {
  local f=$1 cr='' tmp
  grep -q $'\r$' "$f" && cr=$'\r'
  tmp=$(mktemp)
  awk -v cr="$cr" '
    { sub(/\r$/, ""); L[NR] = $0
      if ($0 ~ /^ExclusiveMode[ \t]*=/) { L[NR] = "ExclusiveMode=1"; e = 1 }
      else if ($0 ~ /^Win32UltraLowLatencyMode[ \t]*=/) { L[NR] = "Win32UltraLowLatencyMode=1"; w = 1 }
      else if (!a && $0 ~ /^(LatencyBuffer|EnableMicrophone)[ \t]*=/) a = NR
      else if (!h && $0 ~ /^\[Audio\]/) h = NR }
    function add() { if (!e) print "ExclusiveMode=1" cr; if (!w) print "Win32UltraLowLatencyMode=1" cr }
    END { if (!a) a = h
      for (i = 1; i <= NR; i++) { print L[i] cr; if (i == a) add() }
      if (!a && (!e || !w)) { print "[Audio]" cr; add() } }' "$f" > "$tmp" && cat "$tmp" > "$f"
  rm -f "$tmp"
}
INI_NOTE=""
if [ -f "$GAME/Rocksmith.ini" ]; then
  set_rs_ini "$GAME/Rocksmith.ini"
else
  INI_NOTE="After the first launch, quit and rerun this script once so Rocksmith.ini gets ExclusiveMode=1 and Win32UltraLowLatencyMode=1 set."
fi

# ---------- PipeASIO config: detect the adapter, mono vs stereo ----------
CFG="$HOME/.config/pipeasio/config.ini"
if [ -f "$CFG" ]; then
  say "keeping your $CFG (delete it and rerun to detect the input again)"
else
  say "detecting guitar input"
  # Only a Real Tone cable names itself. Anything else is left to the user, a guess fails silently.
  NODE=$(pw-cli ls Node 2>/dev/null \
    | grep -oP 'node\.name = "\K[^"]+' \
    | grep -i -E 'guitar|rocksmith|real.?tone' | head -1 || true)
  NIN=1
  case "$NODE" in ''|*mono*) ;; *) NIN=2 ;; esac

  mkdir -p "$HOME/.config/pipeasio"
  cat > "$CFG" <<INI
[pipeasio]
sample_rate = 48000
buffer_size = 256
inputs = $NIN
outputs = 2
input_device = $NODE
INI

  if [ -n "$NODE" ]; then
    say "input device: $NODE  (inputs = $NIN)"
  else
    printf '   !! No Real Tone cable found. input_device is empty, so PipeASIO uses your\n'
    printf '      PipeWire default input. If that is not your guitar, set input_device in\n'
    printf '      %s (find it with: pw-cli ls Node | grep node.name)\n' "$CFG"
  fi
fi

# ---------- done ----------
cat <<EOM

============================================================
Setup complete. One manual step left.

In Steam: right-click Rocksmith > Properties > General >
Launch Options, paste exactly this (one line):

    PROTON_USE_WOW64=1 WINEDLLPATH=$HOME/.local/lib/wine %command%

And under Properties > Compatibility, force:

    $(basename "$(dirname "$PROTON")")

Then hit Play. Verify with:

    grep -E "PipeASIO|ASIO Error|unixlib" "$GAME/RS_ASIO-log.txt" | head

"bufferSwitch" lines mean audio is streaming.

Tune inputs/device/latency by editing ~/.config/pipeasio/config.ini
(PipeASIO re-reads it live).
${INI_NOTE:+$INI_NOTE
}To get a newer PipeASIO later, rerun:  $0
============================================================

EOM
