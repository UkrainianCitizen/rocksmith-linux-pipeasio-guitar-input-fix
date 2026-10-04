#!/usr/bin/env python3
"""Skip Rocksmith 2014's intro sequence by patching cache.psarc.

Linux equivalent of RSMods' "Fast Load" (Set & Forget Mods).  Replaces
gfxassets/views/introsequence.gfx inside cache4.7z inside cache.psarc.

Usage: rocksmith-skip-intro.py [--variant mid|max] [--restore] [--game DIR]

Needs: python3 (stdlib only), `openssl` and `7z` on PATH.

Sources
- PSARC layout, TOC entry format, block table, and the zlib/raw block rules
  come from RocksmithToolkitLib/PSARC/PSARC.cs and
  RocksmithToolkitLib/DLCPackage/Packer.cs in
  https://github.com/rscustom/rocksmith-custom-song-toolkit
  (the packer RSMods links as Rocksmith2014PsarcLib.dll).
- The TOC key is RijndaelEncryptor.PsarcKey in the same repo
  (DLCPackage/RijndaelEncryptor.cs).  The TOC is AES-256-CFB (128-bit
  feedback), zero IV, encrypted in place after the 32-byte header.
- The replacement .gfx files are RSMods' (https://github.com/Lovrom8/RSMods,
  no license), so they are downloaded at runtime from a pinned commit and
  checked against a hardcoded sha256.  Nothing from RSMods is stored here.
"""
import argparse
import hashlib
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import urllib.request
import zlib

APPID = "221680"
RSMODS_COMMIT = "072a670ced59457d4110bcc35d75c9da5f6ae308"
RAW_URL = ("https://raw.githubusercontent.com/Lovrom8/RSMods/"
           + RSMODS_COMMIT + "/GUI/Resources/introsequence_{}.gfx")
VARIANTS = {
    "mid": "37b6e409dfeabe12b775dc18184e9ab665c38d0e95e77063541579ff965978e0",
    "max": "b985a2c7eef68cfedb924ddcd258a78f22c1625c6bce6428b10d33f15ec06de9",
}
# RSMods' introsequence_original.gfx: what an unmodified game ships.
ORIGINAL_GFX_SHA256 = "997c1d3aaeeddc90bfa1ec158c6eab89283fdba9f2782693de46a779d1ac25c4"
INNER_ARCHIVE = "cache4.7z"
GFX_PATH = "gfxassets/views/introsequence.gfx"

PSARC_KEY_HEX = ("C53DB23870A1A2F71CAE64061FDD0E1157309DC85204D4C5BFDF25090DF2572C")
ZLIB_TAG = 0x7A6C6962  # 'zlib'
ALIGN = 8192


def say(msg):
    print(msg, flush=True)


def die(msg):
    print("error: " + msg, file=sys.stderr)
    sys.exit(1)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# ---------------------------------------------------------------- PSARC

def _aes_cfb(data, decrypt):
    # openssl's aes-256-cfb is CFB128, same as RijndaelManaged with a 128-bit block.
    cmd = ["openssl", "enc", "-d" if decrypt else "-e", "-aes-256-cfb",
           "-K", PSARC_KEY_HEX, "-iv", "0" * 32]
    r = subprocess.run(cmd, input=data, capture_output=True)
    if r.returncode != 0:
        die("openssl failed: " + r.stderr.decode(errors="replace"))
    return r.stdout


class Psarc:
    """entries: list of (md5, name, data) in archive order, manifest excluded."""

    def __init__(self, entries, block_size=65536, version=0x00010004):
        self.entries = entries
        self.block_size = block_size
        self.version = version

    @classmethod
    def read(cls, raw):
        if len(raw) < 32 or raw[:4] != b"PSAR":
            die("not a PSARC file")
        (_, version, comp, toc_len, entry_size, count, block_size,
         flags) = struct.unpack(">4sIIIIIII", raw[:32])
        if comp != ZLIB_TAG:
            die("unsupported PSARC compression 0x%08x (only zlib)" % comp)
        if entry_size != 30:
            die("unexpected TOC entry size %d" % entry_size)
        if flags & ~4:
            die("unsupported PSARC archive flags %d" % flags)
        toc = raw[32:toc_len]
        if flags & 4:
            toc = _aes_cfb(toc, decrypt=True)
        zsize_bytes = 2 if block_size <= 0x10000 else (3 if block_size <= 0x1000000 else 4)
        if zsize_bytes != 2:
            die("unsupported block size %d" % block_size)
        table_off = count * entry_size
        nblocks = (len(toc) - table_off) // zsize_bytes
        zsizes = struct.unpack(">%dH" % nblocks, toc[table_off:table_off + nblocks * 2])

        raw_entries = []
        for i in range(count):
            e = toc[i * 30:(i + 1) * 30]
            raw_entries.append((e[:16], struct.unpack(">I", e[16:20])[0],
                                int.from_bytes(e[20:25], "big"),
                                int.from_bytes(e[25:30], "big")))

        def inflate(zidx, length, offset):
            out = bytearray()
            while len(out) < length:
                zs = zsizes[zidx]
                zidx += 1
                want = min(block_size, length - len(out))
                if zs == 0 or zs == want:      # stored raw
                    chunk = raw[offset:offset + want]
                    offset += want
                else:
                    chunk = zlib.decompress(raw[offset:offset + zs])
                    offset += zs
                if len(chunk) != want:
                    die("corrupt PSARC block")
                out += chunk
            return bytes(out)

        manifest = inflate(*raw_entries[0][1:]) if raw_entries[0][2] else b""
        names = manifest.decode("ascii").split("\n") if manifest else []
        if len(names) != count - 1:
            die("manifest lists %d names for %d entries" % (len(names), count - 1))
        entries, stored = [], {}
        for (md5, zidx, length, offset), name in zip(raw_entries[1:], names):
            entries.append((md5, name, inflate(zidx, length, offset) if length else b""))
            nblk = -(-length // block_size)
            # Steam stores the cache*.7z entries uncompressed: keep that per entry.
            stored[name] = all(
                zsizes[zidx + k] in (0, min(block_size, length - k * block_size))
                for k in range(nblk))
        p = cls(entries, block_size, version)
        p.stored = stored
        p.manifest_md5 = raw_entries[0][0]
        # Steam's cache.psarc starts large entries on 8192-byte boundaries (zero
        # padding between).  The toolkit does not do this, but keep the stock layout.
        big = [e for e in raw_entries[1:] if e[2] >= ALIGN]
        p.align = ALIGN if big and all(e[3] % ALIGN == 0 for e in big) else 0
        return p

    def pack(self):
        bs = self.block_size
        manifest = "\n".join(n for _, n, _ in self.entries).encode("ascii")
        all_entries = [(getattr(self, "manifest_md5", hashlib.md5(b"").digest()),
                        manifest)] + [(m, d) for m, _, d in self.entries]
        streams, blocks = [], []
        stored = getattr(self, "stored", {})
        names = [None] + [n for _, n, _ in self.entries]
        for (md5, data), name in zip(all_entries, names):
            out = bytearray()
            zl = []
            keep_raw = stored.get(name, name is not None and name.endswith(".7z"))
            for pos in range(0, len(data), bs):
                plain = data[pos:pos + bs]
                packed = b"" if keep_raw else zlib.compress(plain, 9)
                # Same rule as PSARC.DeflateEntries: keep raw if packing does not help.
                if keep_raw or len(packed) >= len(plain) or len(packed) >= bs - 1:
                    out += plain
                    zl.append(len(plain) & 0xFFFF)   # 65536 stored as 0
                else:
                    out += packed
                    zl.append(len(packed))
            streams.append(bytes(out))
            blocks.append(zl)

        align = getattr(self, "align", 0)
        # Padding before an aligned entry is recorded in the stock file as one extra
        # block-table slot (size = pad bytes) at the end of the previous entry.  The
        # slots change the TOC size, which moves the offsets, so iterate to a fixed point.
        pads = [0] * len(streams)
        for _ in range(8):
            nblocks = sum(len(z) + (1 if p else 0) for z, p in zip(blocks, pads))
            offset = 32 + len(all_entries) * 30 + nblocks * 2
            new_pads = [0] * len(streams)
            for i, s in enumerate(streams):
                offset += len(s)
                if align and i + 1 < len(streams) and len(streams[i + 1]) >= align and offset % align:
                    new_pads[i] = align - offset % align
                    offset += new_pads[i]
            if new_pads == pads:
                break
            pads = new_pads
        else:
            die("could not lay out PSARC padding")

        toc_len = 32 + len(all_entries) * 30 + nblocks * 2
        toc, zlens, body = bytearray(), [], bytearray()
        offset = toc_len
        for (md5, data), s, zl, pad in zip(all_entries, streams, blocks, pads):
            toc += (md5 + struct.pack(">I", len(zlens)) + len(data).to_bytes(5, "big")
                    + offset.to_bytes(5, "big"))
            zlens += zl
            body += s
            offset += len(s)
            if pad:
                zlens.append(pad)
                body += b"\0" * pad
                offset += pad
        toc += struct.pack(">%dH" % len(zlens), *zlens)
        header = struct.pack(">4sIIIIIII", b"PSAR", self.version, ZLIB_TAG, toc_len,
                             30, len(all_entries), bs, 4)
        return header + _aes_cfb(bytes(toc), decrypt=False) + bytes(body)

    def get(self, name):
        for i, (_, n, d) in enumerate(self.entries):
            if n == name:
                return i, d
        die("%s not found in cache.psarc" % name)

    def replace(self, name, data):
        i, _ = self.get(name)
        md5, n, _ = self.entries[i]
        self.entries[i] = (md5, n, data)


# ---------------------------------------------------------------- 7z

def have_tools():
    for t in ("openssl", "7z"):
        if shutil.which(t) is None:
            die("%s not found on PATH" % t)


def sevenzip_extract_file(archive_bytes, inner_path):
    with tempfile.TemporaryDirectory() as td:
        a = os.path.join(td, "a.7z")
        with open(a, "wb") as f:
            f.write(archive_bytes)
        r = subprocess.run(["7z", "e", "-so", "-y", a, inner_path],
                           capture_output=True)
        if r.returncode != 0 or not r.stdout:
            die("%s not readable inside %s: %s" % (
                inner_path, INNER_ARCHIVE, r.stderr.decode(errors="replace")[-300:]))
        return r.stdout


def sevenzip_replace_file(archive_bytes, inner_path, new_bytes):
    """Replace one item: LZMA, non-solid, other items untouched."""
    with tempfile.TemporaryDirectory() as td:
        a = os.path.join(td, "a.7z")
        with open(a, "wb") as f:
            f.write(archive_bytes)
        target = os.path.join(td, inner_path)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "wb") as f:
            f.write(new_bytes)
        os.utime(target, (0, 0))   # fixed mtime so reruns give byte-identical output
        # Delete then add: `7z u` skips an item whose size and mtime match, and the
        # mid variant has the same size as the stock file.
        for cmd in (["d", "-y", a, inner_path],
                    ["a", "-y", "-m0=LZMA", "-ms=off", a, inner_path]):
            r = subprocess.run(["7z"] + cmd, cwd=td, capture_output=True)
            if r.returncode != 0:
                die("7z %s failed: %s" % (cmd[0], r.stderr.decode(errors="replace")[-300:]))
        with open(a, "rb") as f:
            return f.read()


# ---------------------------------------------------------------- Steam

def find_game_dir():
    home = os.path.expanduser("~")
    root = None
    for c in (home + "/.steam/root", home + "/.steam/steam",
              home + "/.local/share/Steam",
              home + "/.var/app/com.valvesoftware.Steam/data/Steam"):
        if os.path.isfile(c + "/steamapps/libraryfolders.vdf"):
            root = os.path.realpath(c)
            break
    if root is None:
        die("Steam not found. Pass --game DIR.")
    with open(root + "/steamapps/libraryfolders.vdf", errors="replace") as f:
        libs = re.findall(r'"path"\s*"([^"]+)"', f.read())
    libs.append(root)
    for lib in libs:
        acf = "%s/steamapps/appmanifest_%s.acf" % (lib, APPID)
        if os.path.isfile(acf):
            with open(acf, errors="replace") as f:
                m = re.search(r'"installdir"\s*"([^"]+)"', f.read())
            if m:
                return "%s/steamapps/common/%s" % (lib, m.group(1))
    die("Rocksmith (appid %s) not found in any Steam library. Pass --game DIR." % APPID)


def rocksmith_running():
    # /proc scan instead of pgrep so this process can never match itself.
    for pid in filter(str.isdigit, os.listdir("/proc")):
        try:
            with open("/proc/%s/cmdline" % pid, "rb") as f:
                args = f.read().split(b"\0")
            if any(a.lower().endswith(b"rocksmith2014.exe") for a in args):
                return True
        except OSError:
            pass
    return False


# ---------------------------------------------------------------- actions

def atomic_write(path, data=None, src=None):
    d = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(prefix=".skip-intro-", dir=d)
    try:
        with os.fdopen(fd, "wb") as f:
            if src is not None:
                with open(src, "rb") as s:
                    shutil.copyfileobj(s, f)
            else:
                f.write(data)
            f.flush()
            os.fsync(f.fileno())
        shutil.copymode(path, tmp) if os.path.exists(path) else os.chmod(tmp, 0o644)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def check_original(psarc_bytes, what):
    p = Psarc.read(psarc_bytes)
    _, inner = p.get(INNER_ARCHIVE)
    gfx = sevenzip_extract_file(inner, GFX_PATH)
    got = sha256(gfx)
    if got != ORIGINAL_GFX_SHA256:
        die("%s: %s has sha256 %s, expected %s (the stock game file).\n"
            "The game version differs from the one this tool was written for, or the\n"
            "file was already modified (RSMods keeps its own backup as cache.bak).\n"
            "Refusing to patch." % (what, GFX_PATH, got, ORIGINAL_GFX_SHA256))
    return p


def download_variant(variant):
    url = RAW_URL.format(variant)
    say("downloading " + url)
    with urllib.request.urlopen(url, timeout=60) as r:
        data = r.read()
    got = sha256(data)
    if got != VARIANTS[variant]:
        die("sha256 mismatch for downloaded %s variant: %s != %s"
            % (variant, got, VARIANTS[variant]))
    return data


def do_patch(game, variant):
    cache = os.path.join(game, "cache.psarc")
    orig = cache + ".orig"
    if not os.path.isfile(cache):
        die("no cache.psarc in " + game)
    new_gfx = download_variant(variant)

    if not os.path.exists(orig):
        say("checking current cache.psarc is stock before backing it up")
        with open(cache, "rb") as f:
            check_original(f.read(), "cache.psarc")
        shutil.copy2(cache, orig)
        say("backup: " + orig)
    else:
        say("backup exists, not overwriting: " + orig)

    with open(orig, "rb") as f:
        p = check_original(f.read(), "cache.psarc.orig")
    _, inner = p.get(INNER_ARCHIVE)
    p.replace(INNER_ARCHIVE, sevenzip_replace_file(inner, GFX_PATH, new_gfx))
    out = p.pack()

    # Re-read what we are about to write.
    chk = Psarc.read(out)
    _, inner2 = chk.get(INNER_ARCHIVE)
    if sha256(sevenzip_extract_file(inner2, GFX_PATH)) != VARIANTS[variant]:
        die("self-check failed: patched gfx not found in output, nothing written")
    atomic_write(cache, data=out)
    say("patched (%s) cache.psarc, sha256 %s" % (variant, sha256(out)))


def do_restore(game):
    cache = os.path.join(game, "cache.psarc")
    orig = cache + ".orig"
    if not os.path.isfile(orig):
        die("no backup at " + orig)
    atomic_write(cache, src=orig)
    say("restored cache.psarc, sha256 %s" % sha256_file(cache))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--variant", choices=sorted(VARIANTS), default="mid",
                    help="mid is safe on SSDs. max is faster and may crash unless the game is on NVMe.")
    ap.add_argument("--restore", action="store_true", help="put the original cache.psarc back")
    ap.add_argument("--game", metavar="DIR", help="Rocksmith2014 install dir (default: detect via Steam)")
    a = ap.parse_args()

    have_tools()
    game = a.game or find_game_dir()
    if not os.path.isdir(game):
        die("game folder missing: " + game)
    say("game:   " + game)
    if rocksmith_running():
        die("Rocksmith2014.exe is running. Close it first.")
    if a.restore:
        do_restore(game)
    else:
        do_patch(game, a.variant)


if __name__ == "__main__":
    main()
