# Tuning latency (optional, you run it)

Not a script default. The defaults are safe. Go lower only if you feel lag, and
test with a full song, not the menu.

**`LatencyBuffer` in `Rocksmith.ini`.** Default 4. RS_ASIO says walk it down
4, 3, 2, 1 until it crackles, then back up one. At `buffer_size = 256` and
48 kHz each step is 256 / 48000 = 5.33 ms, so 4 → 2 saves about 10.7 ms.

**`buffer_size` in `~/.config/pipeasio/config.ini`.** 256 → 128 saves
128 / 48000 = 2.67 ms. Keep `pw-top` open for a whole song. The ERR column
stays at 0 or you revert. Don't go under 64 without a clean run at the value
above it.

Leave `realtime` and `follow_device_clock` off. PipeASIO's README measured
`realtime` at about 39x more xruns on a multi-threaded host. Hard pass.

Tone still won't change mid-song? That's the game, not your buffer. See
[troubleshooting](troubleshooting.md).
