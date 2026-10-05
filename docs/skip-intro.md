# Skip the intro (optional)

Rocksmith's intro is long enough to make a sandwich. Second script kills it.

```sh
./rocksmith-skip-intro.py              # patch (default variant: mid)
./rocksmith-skip-intro.py --variant max
./rocksmith-skip-intro.py --restore    # put the original back
```

Same trick as RSMods' "Fast Load", minus Windows. It swaps
`gfxassets/views/introsequence.gfx` inside `cache4.7z` inside `cache.psarc`.
Archive inception. The original goes to `cache.psarc.orig` first, `--restore`
copies it back.

- Needs `python3`, `openssl` and `7z`. Add `--game DIR` if it can't find the game.
- Close Rocksmith first. It refuses otherwise.
- `mid` is the default. RSMods warns `max` can crash if the game isn't on NVMe.
- The `.gfx` comes from RSMods' GitHub at a pinned commit, checked against a
  sha256. RSMods has no license, so none of it lives in this repo.
- Steam's "verify files" or a game update undoes it. Run it again.

**Status:** tested in-game on one machine, NVMe. Byte-checked too: every other
entry in the archive is identical, and a restore gives back the same sha256.
`mid` still shows the sponsor logos for a few seconds. `max` jumps to the white
"ENTER Begin" screen, which waits for a key press. RSMods' "Auto enter last used
profile" DLL mod presses it for you. Untested here.

Credit: [RSMods](https://github.com/Lovrom8/RSMods) for the `.gfx` files and
the whole idea,
[rocksmith-custom-song-toolkit](https://github.com/rscustom/rocksmith-custom-song-toolkit)
for the PSARC format.
