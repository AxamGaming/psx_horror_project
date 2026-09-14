"""Build the full-project release zip, minus the platform binaries you won't run.

Usage:
    python3 tools/make_release_zip.py [linux|windows|macos|desktop|all]

`addons/limboai/bin` ships ~88 MB of native libraries for every target Godot
supports (iOS, Android, macOS, Web, Linux arm64/x86_64, Windows). Godot loads only
the one matching the host, so a delivery zip keeps just that set. Everything dropped
is still tracked by git — restore with:

    git checkout -- addons/limboai/bin

Output goes to the workspace root (one level above the project) so the zip never ends
up inside the tree it is zipping.

See also tools/make_delta_zip.py for the small drop-in delta.
"""

import fnmatch
import os
import zipfile

PROJ = "psx_horror_project"
PROJ_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(PROJ_DIR)
OUT = os.path.join(ROOT, "kill_sequence_r31_whole_game.zip")

SKIP_DIRS = {".godot", ".git"}

# Never shipped: scratch probes and generated caches.
ALWAYS_SKIP = [
    "tests/_seek_test.gd",
    "tests/_seek_test.gd.uid",
]

# Which LimboAI binaries survive, by target platform.
PLATFORM_KEEP = {
    "linux": ["liblimboai.linux.*x86_64*"],
    "windows": ["liblimboai.windows.*x86_64*"],
    "macos": ["liblimboai.macos.*"],
    "desktop": ["liblimboai.linux.*x86_64*", "liblimboai.windows.*x86_64*",
                "liblimboai.macos.*"],
    "all": ["liblimboai.*"],
}

BIN_SUBDIR = os.path.join("addons", "limboai", "bin")


def dropped_binaries(keep: list[str]) -> list[str]:
    """Project-relative paths of LimboAI binaries that do not match `keep`."""
    out: list[str] = []
    bin_dir = os.path.join(PROJ_DIR, BIN_SUBDIR)
    for dirpath, dirnames, filenames in os.walk(bin_dir):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fname in filenames:
            rel = os.path.relpath(os.path.join(dirpath, fname), PROJ_DIR).replace(os.sep, "/")
            if rel.endswith(".gdextension") or rel.endswith(".uid"):
                continue  # the manifest must always ship
            if not any(fnmatch.fnmatch(fname, pat) for pat in keep):
                out.append(rel)
    return out


def build(platform: str) -> str:
    keep = PLATFORM_KEEP[platform]
    skip = set(ALWAYS_SKIP) | set(dropped_binaries(keep))
    out = OUT if platform == "desktop" else OUT.replace(".zip", f"_{platform}.zip")
    if os.path.exists(out):
        os.remove(out)

    count = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for dirpath, dirnames, filenames in os.walk(PROJ_DIR):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            for fname in filenames:
                full = os.path.join(dirpath, fname)
                inner = os.path.relpath(full, PROJ_DIR).replace(os.sep, "/")
                if inner in skip:
                    continue
                z.write(full, f"{PROJ}/{inner}")
                count += 1

    size = os.path.getsize(out) / 1048576.0
    print(f"wrote {out}")
    print(f"  platform={platform}  files={count}  skipped={len(skip)}  size={size:.1f} MB")
    with zipfile.ZipFile(out) as z:
        names = z.namelist()
        kept = sorted(n for n in names if BIN_SUBDIR.replace(os.sep, "/") in n)
        print("  limboai binaries kept:")
        for n in kept:
            print(f"    {n.split('/bin/')[1]:<52} {z.getinfo(n).file_size / 1048576:5.1f} MB")
        for probe in ("kill_director.gd", "kill_anim.tres", "kill_rig.tscn", "kill_fx.gdshader",
                      "blood_burst.gd", "settings_menu.tscn", "CREDITS.md", "KILL_SEQUENCE_R30.md"):
            if not any(n.endswith(probe) for n in names):
                raise SystemExit(f"  !! MISSING FROM ZIP: {probe}")
        wavs = [n for n in names if n.startswith(f"{PROJ}/audio/sfx/jumpscare/") and n.endswith(".wav")]
        print(f"  kill-system files: verified present | jumpscare wav layers: {len(wavs)}")
    return out


if __name__ == "__main__":
    import sys
    arg = sys.argv[1] if len(sys.argv) > 1 else "desktop"
    if arg not in PLATFORM_KEEP:
        raise SystemExit(f"unknown platform {arg!r}; pick from {sorted(PLATFORM_KEEP)}")
    build(arg)
