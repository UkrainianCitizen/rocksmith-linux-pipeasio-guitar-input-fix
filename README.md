# Rocksmith 2014 on Linux: guitar input that actually works ©

Run one script. Click two things in Steam. Your guitar makes noise in the game.
That's it, that's the repo.

## Contents

- [Why this exists](#why-this-exists)
- [Setup](#setup)
- [What the script does](#what-the-script-does)
- [Three things that will absolutely get you](#three-things-that-will-absolutely-get-you)
- [Tuning latency](#tuning-latency)
- [Contributing](#contributing)
- [Skip the intro (optional)](#skip-the-intro-optional)
- [When it breaks](#when-it-breaks)

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

1. **Compatibility** → force **GE-Proton 11.x**. Tested on GE-Proton11-7.
   Valve's 11.0-1+ should work. Should. Never played a song on it.
   [Why GE](docs/gotchas.md).
2. **Launch Options** → the script prints the exact line at the end, with your
   real home directory in it. Looks like this:

```
PROTON_USE_WOW64=1 WINEDLLPATH=/home/<you>/.local/lib/wine %command%
```

Copy the one the script prints, not this one. Absolute path, no `~`, no `$HOME`.

Hit Play, run the calibration, go be a rockstar alone in your room.

Proton updates don't touch it. The driver lives in `~/.local`, not in the Proton
folder. `--reapply` is a no-op now, kept so old habits don't explode.

> Heads up, the full run works start to finish on my machine: guitar detected,
> audio streaming. It has never run on a clean box. Read the script first. It's
> short. I'm not your dad.

---

## What the script does


Builds PipeASIO with 32-bit WoW64 support, installs it to `~/.local`, registers
it in the prefix, grabs RS_ASIO, writes the configs, and finds your Real Tone
cable and whether it's mono. Finds your distro, your Steam library, and wherever
you stashed the game.

The fine print:

- PipeASIO builds from the latest release tag, not whatever's on `HEAD` that
  morning.
- Needs i686 **and** x86_64 MinGW gcc and g++. No Qt, no yaml-cpp, no
  `pipeasio-settings`. You edit `~/.config/pipeasio/config.ini` and PipeASIO
  re-reads it live.
- `config.ini` gets written once. Reruns leave it alone, so your tweaks survive
  updates. Delete it and rerun to detect again.
- No Real Tone cable? `input_device` stays empty and PipeASIO uses your PipeWire
  default input. On an audio interface, check that's actually your guitar.
- `Rocksmith.ini` gets `ExclusiveMode=1` and `Win32UltraLowLatencyMode=1`
  (RS_ASIO says so). Everything else stays. No file yet? Launch the game once,
  quit, rerun.

No paths to fill in. If it can't find something it says what and stops, instead
of barreling ahead and handing you a half-wired audio stack.

<img width="209" height="241" alt="1000011101" src="https://github.com/user-attachments/assets/c2e0a63d-b812-47ee-9b9c-15f9241092f1" />

---

## Three things that will absolutely get you

Two Proton traps and one cable. [docs/gotchas.md](docs/gotchas.md). Read it
before you lose a weekend.

## Tuning latency

Feel lag? [docs/latency.md](docs/latency.md). Opt-in, the defaults are safe.

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md)

## Skip the intro (optional)

Intro takes forever? Second script. [docs/skip-intro.md](docs/skip-intro.md).

## When it breaks

Symptom, cause, fix: [docs/troubleshooting.md](docs/troubleshooting.md).

---

<sub>Originally confirmed in-game on Nobara 43, GE-Proton 11, PipeWire 1.6.8, PipeASIO 1.5.0, RS_ASIO 0.7.5, Real Tone Cable. The WINEDLLPATH change was checked with a 32-bit ASIO probe on GE-Proton11-7, and the game was then played on it with PipeASIO v1.10.0. Written to work anywhere, tested on that. Ran it somewhere else? Open an issue and tell me if it worked or exploded, both help.</sub>

<sub>None of this is my discovery, I just glued it together and wrote it down. [nizo's](https://codeberg.org/nizo) [guide](https://codeberg.org/nizo/linux-rocksmith) is the only reason this game runs on Linux at all, and he's the one who pointed me at PipeASIO when WineASIO dead-ended. [rein](https://codeberg.org/rein) told me about the Proton ≥ 11 thing, that RS_ASIO has to be 0.7.5, and casually mentioned pipeasio-settings exists, which I'd completely missed (the script doesn't build it anymore, but thanks). [M0n7y5](https://github.com/M0n7y5) makes [PipeASIO](https://github.com/M0n7y5/pipeasio), [mdias](https://github.com/mdias) makes [RS_ASIO](https://github.com/mdias/rs_asio). Built with AI, tested on my own machine. CC BY-SA 4.0, same as nizo's, since it stands on his work.</sub>

<sub>Smell ya later.</sub>
