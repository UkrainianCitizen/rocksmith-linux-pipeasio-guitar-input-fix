# Rocksmith 2014 on Linux: guitar input that actually works ©

Run one script. Click two things in Steam. Your guitar makes noise in the game.
That's it, that's the repo.

## Why this exists

Okay so Rocksmith 2014 is genuinely one of the coolest things Ubisoft has ever
put out. You plug a real guitar into a computer and it teaches you to play it.
And they've done nothing with it. No Linux build, no port, no patch, nothing.

<img width="500" height="620" alt="out" src="https://github.com/user-attachments/assets/74442f4e-63e7-40bf-9836-0e2563e59c4d" />
<br>

It's just sitting there. 

---
So I had to go balls deep, cause I'd rather fall into coma than switch back to Windows. I got u.

<img width="498" height="278" alt="Ill Do It Myself GIF" src="https://github.com/user-attachments/assets/fe12ab6f-ca10-41b2-a789-a357cb3a0b85" />

---
The game runs fine under Proton, that part's whatever. Your guitar is the
problem. Rocksmith wants ASIO, which is a Windows audio thing that doesn't exist
on Linux, and the normal fix for that (WineASIO) doesn't build anymore on a
bunch of distros. Not "it's tricky." Not "you need a flag." The 32-bit Wine libs
it needs literally aren't packaged. Cast into oblivion. Gone.

<img width="480" height="272" alt="Hold Up Superman GIF" src="https://github.com/user-attachments/assets/1a8ff1f2-f223-4172-a254-22e98a189e0c" />

---

I found this out by watching a linker fail for days in like six
different flavors. Masterclass in bad decision-making and I was the whole
faculty. Anyway PipeASIO fixes it. Talks straight to PipeWire, builds its 32-bit half with
MinGW instead of Wine's toolchain, dodges the whole mess. Works great. Just
annoying enough to set up that you'd quit around step four.


---

So, script.

```
your guitar → PipeWire → PipeASIO → RS_ASIO → Rocksmith
```
## Setup

```sh
git clone https://github.com/UkrainianCitizen/rocksmith-linux-pipeasio-guitar-input-fix
cd rocksmith-linux-pipeasio-guitar-input-fix
./rocksmith-pipeasio-setup.sh
```

Two things it can't do for you, because they live in Steam's binary config and
get wiped if Steam's running when you poke it:

1. **Compatibility** → force **GE-Proton 11.x**. I tested on GE-Proton11-7.
   Valve's Proton 11.0-1 and newer should work too, but I haven't played a
   single song on it, so that's a vibe, not a result. Read the next bit.
2. **Launch Options** → the script prints the exact line at the end, with your
   real home directory in it. It looks like this:

```
PROTON_USE_WOW64=1 WINEDLLPATH=/home/<you>/.local/lib/wine %command%
```

Copy the one the script prints, not this one. Absolute path, no `~`, no `$HOME`.

Hit Play, run the calibration, go be a rockstar alone in your room.

Proton updates are fine now. The driver lives in `~/.local`, outside the Proton
folder, so there's nothing to redo. `--reapply` still exists, prints "not needed"
and exits, so old habits don't break anything.

> Heads up, the full run has never gone start to finish on a clean box. It's
> stitched from steps I did by hand one at a time. The Proton and WINEDLLPATH
> part is tested with a 32-bit ASIO probe on GE-Proton11-7 (loads with
> `WINEDLLPATH` set, fails without), and the game itself runs on it: guitar
> detected, audio streaming, on my machine. Read the script first. It's short. I'm not
> your dad.

---

## Three things that will absolutely get you

**Older Valve Proton just ignores the flag.** You set `PROTON_USE_WOW64=1`,
Valve's `11.0-100` looks at it, and does nothing. No error. No warning. Nothing
in the log going "hey, skipping that." It just doesn't, and then PipeASIO
faceplants with "the 64-bit unixlib is unavailable" and you're forty minutes deep
debugging a driver that was fine the whole time. This one cost me the most and
I'm still kind of mad. Valve fixed it in 11.0-1 (commit `4cc52e80`), so newer
builds should be fine, but GE is what I actually tested. Use GE.

**You have to pass `WINEDLLPATH` yourself.** Proton used to throw away the one you
set, which is why this guide used to copy files into the Proton folder and tell you
to redo it after every update. Valve 11.0-1+ (commit `cf186442`) and GE-Proton11-7
now keep it. So the driver stays in `~/.local/lib/wine` and the launch options
point at it. Forget the `WINEDLLPATH` part and PipeASIO won't load, same
symptom as above. The script also deletes any old PipeASIO copies from the Proton
tree, because those get searched first and would shadow the new build.

**The Real Tone Cable is mono.** One channel. Set `inputs = 2` and you get this
beautiful uninterrupted buzz and zero detected notes, and you'll sit there
plucking at a dead game like a goober wondering what you broke. Skill issue.
Mine. Took me way too long.

---

## When it breaks

<img width="480" height="278" alt="Iron Man Kill GIF" src="https://github.com/user-attachments/assets/4d181b3a-d22e-4836-a3ac-33e306e62377" />

| Symptom | What's actually going on | Fix |
|---|---|---|
| `the 64-bit unixlib is unavailable` | WoW64's off, or Proton can't see the driver | Add `PROTON_LOG=1`, launch, `grep -m1 "Options:" ~/steam-221680.log`. On GE, no `wow64` in there → it's ignoring you (Valve never prints it, even when it works, so on Valve just switch to GE). It's there → check `WINEDLLPATH=/home/<you>/.local/lib/wine` is in your launch options and the folder has the four `pipeasio` files |
| Dies in a second, no window, no log | Busted launch options | Check the trailing `%` on `%command%`. Steam fails dead silent on a broken string. Fantastic. Tremendous |
| Constant buzz, plucking does nothing | Wrong `inputs`, or it grabbed your webcam mic | Fix `inputs` and `input_device` in `~/.config/pipeasio/config.ini`. The settings GUI isn't built anymore |
| Crackling, dropouts | Buffer's too small | `buffer_size` 256 → 512 in `~/.config/pipeasio/config.ini`. Re-reads live so you can tune it mid-song. `sample_rate` has to be 48000, no exceptions. Going the other way is in the tuning section below |
| Tone won't switch mid-song, Riff Repeater's possessed | Game's just like that | Nothing. Standard operating procedure. Does it on Windows too. It's a decade old, let it live |

## What the script does


Builds PipeASIO with 32-bit WoW64 support, installs it to `~/.local`, registers
it in the prefix, grabs RS_ASIO, writes the configs, and works out which thing is
your guitar adapter and whether it's mono. Finds your distro, your Steam library,
and wherever you stashed the game.

Some specifics, since they changed:

- PipeASIO is pinned to the latest release tag (v1.10.0 right now), not
  whatever's on `HEAD` that morning.
- The build needs i686 **and** x86_64 MinGW gcc and g++. Qt and yaml-cpp are no
  longer needed. The settings panel and manager are off, so there's no
  `pipeasio-settings`. You edit `~/.config/pipeasio/config.ini` and PipeASIO
  re-reads it live.
- It no longer deletes `Rocksmith.ini`. If the file exists, the script sets
  `ExclusiveMode=1` and `Win32UltraLowLatencyMode=1` (what the RS_ASIO README
  recommends) and leaves everything else alone. If it doesn't exist yet, launch
  the game once, quit, and rerun the script.

You don't edit anything. No paths to fill in. If it can't find something it says
what and stops, instead of barreling ahead and handing you a half-wired audio
stack.

<img width="209" height="241" alt="1000011101" src="https://github.com/user-attachments/assets/c2e0a63d-b812-47ee-9b9c-15f9241092f1" />

---

## Skip the intro (optional)

Rocksmith's startup sequence is long enough to make a sandwich in. There's a
second script for it:

```sh
./rocksmith-skip-intro.py              # patch (default variant: mid)
./rocksmith-skip-intro.py --variant max
./rocksmith-skip-intro.py --restore    # put the original back
```

It does what RSMods' "Fast Load" does, minus Windows. It swaps
`gfxassets/views/introsequence.gfx` inside `cache4.7z` inside `cache.psarc`. The
original goes to `cache.psarc.orig` first, and `--restore` copies it back. Needs
`python3`, `openssl`, and `7z`. Optionally `--game DIR` if it can't find the game.
Close Rocksmith first, it refuses to run otherwise.

- `mid` is the default. RSMods warns `max` can crash if the game isn't on NVMe.
- The replacement `.gfx` is downloaded from RSMods' GitHub at a pinned commit and
  checked against a sha256. RSMods has no license, so nothing from it is stored
  in this repo.
- Steam's "verify files" or a game update puts the original back. Run it again.

**Status:** byte-level checked (every other entry in the archive is identical,
a restore round-trip gives the same sha256) and tested in-game on one machine,
NVMe drive. `mid` still shows the sponsor logos for a few seconds. `max` goes
straight to the white "ENTER Begin" title screen after a short delay. That
screen waits for a key press, which this patch doesn't touch. RSMods' "Auto
enter last used profile" DLL mod presses Enter for you. Not tested here.

Credit where it's due: [RSMods](https://github.com/Lovrom8/RSMods) for the
`.gfx` files and the whole idea, and
[rocksmith-custom-song-toolkit](https://github.com/rscustom/rocksmith-custom-song-toolkit)
for the PSARC format.

---

## Tuning latency (optional, you run it)

None of this is a script default. The defaults are safe. Go lower only if you
feel lag, and test with a full song, not the menu.

**`LatencyBuffer` in `Rocksmith.ini`.** Default is 4. The RS_ASIO README says
try 4, 3, 2, 1, going down until it crackles, then go back up one. At
`buffer_size = 256` and 48 kHz each step is 256 / 48000 = 5.33 ms. Going from 4
to 2 is 2 steps, so about 10.7 ms.

**`buffer_size` in `~/.config/pipeasio/config.ini`.** 256 to 128 saves
128 / 48000 = 2.67 ms. Run `pw-top` during a whole song. The ERR column has to
stay at 0. Any crackle, revert. Don't go under 64 without a clean run at the
value above it.

Leave `realtime` and `follow_device_clock` off. PipeASIO's README measured
`realtime` at about 39x more xruns on a multi-threaded host. Not worth it.

If the tone doesn't change mid-song after all this, that's the game, not your
buffer. Same note as the table above.

---

## Contributing

`tests/install-layout.sh` builds the pinned PipeASIO with the script's own cmake
flags and checks that the installed files land where the script says. It doesn't
test the game.

---

<sub>Originally confirmed in-game on Nobara 43, GE-Proton 11, PipeWire 1.6.8, PipeASIO 1.5.0, RS_ASIO 0.7.5, Real Tone Cable. The WINEDLLPATH change was checked with a 32-bit ASIO probe on GE-Proton11-7, and the game was then played on it with PipeASIO v1.10.0. Written to work anywhere, tested on that. Ran it somewhere else? Open an issue and tell me if it worked or exploded, both help.</sub>

<sub>None of this is my discovery, I just glued it together and wrote it down. [nizo's](https://codeberg.org/nizo) [guide](https://codeberg.org/nizo/linux-rocksmith) is the only reason this game runs on Linux at all, and he's the one who pointed me at PipeASIO when WineASIO dead-ended. [rein](https://codeberg.org/rein) told me about the Proton ≥ 11 thing, that RS_ASIO has to be 0.7.5, and casually mentioned pipeasio-settings exists, which I'd completely missed (the script doesn't build it anymore, but thanks). [M0n7y5](https://github.com/M0n7y5) makes [PipeASIO](https://github.com/M0n7y5/pipeasio), [mdias](https://github.com/mdias) makes [RS_ASIO](https://github.com/mdias/rs_asio). Built with AI, tested on my own machine. CC BY-SA 4.0, same as nizo's, since it stands on his work.</sub>

<sub>Smell ya later.</sub>
