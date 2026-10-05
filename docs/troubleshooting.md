# When it breaks

<img width="480" height="278" alt="Iron Man Kill GIF" src="https://github.com/user-attachments/assets/4d181b3a-d22e-4836-a3ac-33e306e62377" />

| Symptom | What's actually going on | Fix |
|---|---|---|
| `the 64-bit unixlib is unavailable` | WoW64's off, or Proton can't see the driver | Add `PROTON_LOG=1`, launch, `grep -m1 "Options:" ~/steam-221680.log`. On GE, no `wow64` in there → it's ignoring you (Valve never prints it, even when it works, so on Valve just switch to GE). It's there → check `WINEDLLPATH=/home/<you>/.local/lib/wine` is in your launch options and the folder has the four `pipeasio` files |
| Dies in a second, no window, no log | Busted launch options | Check the trailing `%` on `%command%`. Steam fails dead silent on a broken string. Fantastic. Tremendous |
| Constant buzz or dead silence, plucking does nothing | Wrong `inputs`, or it's listening to the wrong thing (webcam mic, your interface's other jack) | Fix `inputs` and `input_device` in `~/.config/pipeasio/config.ini`. Device names: `pw-cli ls Node \| grep node.name`. The settings GUI isn't built anymore |
| Crackling, dropouts | Buffer's too small | `buffer_size` 256 → 512 in `~/.config/pipeasio/config.ini`. Re-reads live so you can tune it mid-song. `sample_rate` has to be 48000, no exceptions. Going lower instead: [latency.md](latency.md) |
| Tone won't switch mid-song, Riff Repeater's possessed | Game's just like that | Nothing. Standard operating procedure. Does it on Windows too. It's a decade old, let it live |
