"""Build a drop-in delta zip between two git states of the project.

Everything that changed between `--base` (what the user already has installed)
and HEAD, minus the .godot import cache (Godot rebuilds that on first open).

Layout inside the zip is `psx_horror_project/...`, so extracting it into the
folder that CONTAINS your project merges the changes in place.

Also writes _<TAG>_DELETE_THESE.txt (files the delta removes), _<TAG>_INSTALL.md
(with an auto-generated changelog from `git log base..HEAD`) and
_<TAG>_MANIFEST.txt (sha256[:12] per file).

Usage:
    python3 tools/make_delta_zip.py                          # R30 defaults
    python3 tools/make_delta_zip.py --base e91f99b --tag R31 \
            --out ../kill_r31_DELTA.zip
"""

import argparse
import hashlib
import os
import subprocess
import zipfile

PROJ = "psx_horror_project"
PROJ_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # .../psx_horror_project
ROOT = os.path.dirname(PROJ_DIR)                                        # workspace root

INSTALL = """# {tag} delta — drop-in (base {base})

This is ONLY the files that changed since `{base}` ({base_subject}). If you do
NOT have the project from an earlier round, ask for the full zip instead.

## What's new in this delta

{changelog}

## Install (20 seconds)

1. Close Godot.
2. Extract this zip into the folder that CONTAINS `psx_horror_project/`
   (so `psx_horror_project/` from the zip merges onto your existing one —
   overwrite everything when prompted).
3. Delete the files listed in `_{tag}_DELETE_THESE.txt` (paths are relative to
   `psx_horror_project/`), if the list is not empty.
4. Open the project in Godot 4.7.2. ({import_note})
5. Play. Get caught by the creature.

## Verify it installed

```
godot --headless --path psx_horror_project --fixed-fps 60 --quit-after 1600 \\
      -s res://tests/jumpscare_selftest.gd
```
Expect every check to PASS (the count grows each round; {tag_lower} reports
43 for the kill suite).

## Tuning (all exports, nothing hardcoded)

KillDirector → `Crash & settle` group carries the R31 heavy-object dials
(fall_gravity, crash_throw_out, crash_drop_v, floor_restitution,
restitution_falloff, max_bounces, bounce_stop_speed, crash_scatter,
crash_tumble_speed, crash_spin_damping, crash_align_air/ground, crash_timeout,
settle_before_fade). Full table: `docs/KILL_SEQUENCE_R30.md` §11 and
`docs/FIXES_R31_footsteps_killstart_crashweight.md`.
"""


def git_lines(*args: str) -> list[str]:
    out = subprocess.run(
        ["git", "-C", PROJ_DIR, *args],
        capture_output=True, text=True, check=True,
    ).stdout
    return [l for l in out.splitlines() if l.strip()]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--base", default="821f317",
                    help="git ref the recipient already has (default: R29 tip)")
    ap.add_argument("--tag", default="R30", help="label used in the zip's info files")
    ap.add_argument("--out", default=os.path.join(ROOT, "kill_r30_DELTA.zip"),
                    help="output zip path")
    args = ap.parse_args()
    base, tag, out = args.base, args.tag, args.out

    rows = git_lines("diff", "--name-status", base, "HEAD", "--", ".", ":(exclude).godot")
    added_mod, deleted = [], []
    for row in rows:
        parts = row.split("\t")
        status, path = parts[0], parts[-1]
        (deleted if status.startswith("D") else added_mod).append(path)

    log = git_lines("log", "--oneline", "--no-decorate", f"{base}..HEAD")
    changelog = "\n".join(f"- `{l.split(' ', 1)[0]}` {l.split(' ', 1)[1]}"
                          for l in log) or "- (no commits?)"
    base_subject = (git_lines("log", "-1", "--format=%s", base) or ["?"])[0]

    # New binary assets (audio/textures/models) mean a re-import on first open;
    # pure script/doc deltas do not.
    asset_exts = (".wav", ".ogg", ".mp3", ".png", ".jpg", ".glb", ".gltf", ".tres", ".tscn")
    touches_assets = any(p.lower().endswith(asset_exts) for p in added_mod)
    import_note = ("first open re-imports the changed assets — give it a minute"
                   if touches_assets else
                   "code-only delta — no re-import needed, it opens instantly")

    if os.path.exists(out):
        os.remove(out)

    manifest = []
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for rel in sorted(added_mod):
            full = os.path.join(PROJ_DIR, rel)
            if not os.path.isfile(full):
                print(f"  !! missing on disk, skipped: {rel}")
                continue
            z.write(full, f"{PROJ}/{rel}")
            digest = hashlib.sha256(open(full, "rb").read()).hexdigest()[:12]
            manifest.append(f"{os.path.getsize(full):>9,}  {digest}  {rel}")
        z.writestr(f"_{tag}_DELETE_THESE.txt",
                   f"# {tag} removed these. Delete them from your {PROJ}/ folder.\n"
                   + ("\n".join(sorted(deleted)) if deleted else "(nothing — this delta deletes no files)")
                   + "\n")
        z.writestr(f"_{tag}_INSTALL.md", INSTALL.format(
            tag=tag, tag_lower=tag.lower(), base=base, base_subject=base_subject,
            changelog=changelog, import_note=import_note))
        z.writestr(f"_{tag}_MANIFEST.txt",
                   f"# {len(manifest)} files, sha256[:12] prefix, base {base} -> HEAD\n"
                   + "\n".join(manifest) + "\n")

    size = os.path.getsize(out) / 1048576.0
    print(f"wrote {out}")
    print(f"files: {len(manifest)}   deleted-list entries: {len(deleted)}   size: {size:.2f} MB")


if __name__ == "__main__":
    main()
