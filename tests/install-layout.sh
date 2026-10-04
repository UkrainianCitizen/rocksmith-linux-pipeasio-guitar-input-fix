#!/usr/bin/env bash
# Builds PipeASIO at the pinned tag with the setup script's cmake flags, installs
# into a temp prefix, and checks every file in PIPEASIO_FILES is there.
# Flags, tag lookup, Wine lib root lookup and the file list are all read from
# the setup script, so they cannot drift.
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/rocksmith-pipeasio-setup.sh"
die() { printf '\n!! %s\n' "$*" >&2; exit 1; }
say() { printf '\n>> %s\n' "$*"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

eval "$(sed -n '/^WLR=""/,/^say "wine lib root/p' "$SCRIPT")"
eval "$(sed -n '/^TAG=\$(curl/,/^\[ -n "\$TAG" \]/p' "$SCRIPT")"

# every -DNAME=value on the script's cmake configure line
mapfile -t FLAGS < <(sed -n '/^cmake -B build/,/WINE_LIB_ROOT/p' "$SCRIPT" | grep -oP -- '-D\w+=\S+')
[ "${#FLAGS[@]}" -gt 0 ] || die "could not read cmake flags from $SCRIPT"
# WINE_LIB_ROOT keeps its quoted $WLR in the script, resolve it here
FLAGS=("${FLAGS[@]//\"\$WLR\"/$WLR}")

eval "$(sed -n '/^PIPEASIO_FILES=(/,/^)/p' "$SCRIPT")"
FILES=("${PIPEASIO_FILES[@]}")
[ "${#FILES[@]}" -eq 4 ] || die "expected 4 files in PIPEASIO_FILES, found ${#FILES[@]}"

say "cloning PipeASIO $TAG"
git clone --depth 1 --branch "$TAG" https://github.com/M0n7y5/pipeasio "$TMP/src" >/dev/null 2>&1
say "building: ${FLAGS[*]}"
cmake -S "$TMP/src" -B "$TMP/build" "${FLAGS[@]}" >/dev/null
cmake --build "$TMP/build" -j"$(nproc)" >/dev/null
cmake --install "$TMP/build" --prefix "$TMP/prefix" >/dev/null

missing=0
for f in "${FILES[@]/#/lib/wine/}" bin/pipeasio-register; do
  if [ -e "$TMP/prefix/$f" ]; then echo "ok       $f"; else echo "MISSING  $f"; missing=1; fi
done
[ "$missing" -eq 0 ] || { echo "installed tree:"; (cd "$TMP/prefix" && find . -type f); die "install layout does not match PIPEASIO_FILES"; }
say "install layout OK ($TAG)"
