# Three things that will absolutely get you

**Valve's Proton ignored the flag on me.** You set `PROTON_USE_WOW64=1`, Valve's
`11.0-100` looks at it, and does nothing. No error. No warning. Nothing in the
log going "hey, skipping that." It just doesn't, and then PipeASIO faceplants
with "the 64-bit unixlib is unavailable" and you're forty minutes deep debugging
a driver that was fine the whole time. This one cost me the most and I'm still
kind of mad. Plot twist: Valve says 11.0-1 and newer honor it (commit
`4cc52e80`), so no clue what happened there. Old build, misread log, who knows.
GE is what I actually tested. Use GE.

**You have to pass `WINEDLLPATH` yourself.** Proton used to throw away the one
you set, so this guide used to copy files into the Proton folder and make you
redo it after every update. Valve 11.0-1+ (commit `cf186442`) and GE-Proton11-7
keep it now. So the driver stays in `~/.local/lib/wine` and the launch options
point at it. Forget the `WINEDLLPATH` part and PipeASIO won't load, same symptom
as above. The script also deletes old PipeASIO copies from the Proton tree,
because Proton searches there first and they'd shadow the new build.

**The Real Tone Cable is mono.** One channel. Set `inputs = 2` and you get this
beautiful uninterrupted buzz and zero detected notes, and you'll sit there
plucking at a dead game like a goober wondering what you broke. Skill issue.
Mine. Took me way too long.
