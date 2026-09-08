# Phase 8 Delivery — Audio (footsteps, reverb, deafness, flashlight hum)

> **8-FINAL (current — supersedes all previous fix rounds):** after four playtest failures the audio layer was rebuilt once, from official 4.7 documentation, on machinery that cannot fail silently:
> - **Every sound is a plain `AudioStreamPlayer`** — the only type proven audible in this project (root viewport AND inside the SubViewport; the flashlight click never failed once). `AudioStreamPlayer3D` is unreliable in SubViewports (godot#94403); `AudioStreamPlayer2D` proved silent here; plain players have **no `pan` property in 4.7** (that was the parse error).
> - **Panning = per-bus `AudioEffectPanner`** (4.7 class: single `pan` float −1..1, verified in the class reference): buses `FootL`/`FootR` (fixed ±`foot_pan`), `Hum` (dynamic, driven by the lamp's lag), `World0-3` (pooled for world sounds) — all sending into `SFX`, so deafness + room reverb still apply to panned sounds.
> - **Self-healing buses:** AudioMgr guarantees every bus + panner exists at boot (`_ensure_pan_bus` creates anything the layout file didn't provide). A stale or missing `default_bus_layout.tres` can never silently kill audio again; worst case a player falls back to `SFX` (audible, unpanned).
> - Bus graph (editor-visible in `default_bus_layout.tres`): `Master ← SFX[LowPass,Reverb] ← {FootL,FootR,Hum,World0-3}[Panner]`; `Master ← Ambient[LowPass,Reverb]`; tinnitus → `Master` direct (never muffled).
> - All one-shots are silence-trimmed mono **WAV** (mp3/ogg priming padding = sounds landing late).
>
> **Re-copy (full audio set):** `default_bus_layout.tres`, `autoload/audio_mgr.gd`, `scenes/player/footsteps.gd`, `scenes/player/flashlight_rig.gd`, `scenes/player/player.tscn`, `scenes/main.tscn`, `scenes/main.gd`. (AudioListener2D / audio_listener_3d machinery removed — obsolete with this design.)

## Files to copy

| File | Action |
|---|---|
| `audio/sfx/*.wav` (5 files) | **NEW folder** — procedural placeholders, swap for real recordings later (same filenames = zero code changes) |
| `autoload/audio_mgr.gd` | **NEW** — buses, deafness/tinnitus, reverb probe, landing thud |
| `scenes/player/footsteps.gd` | **NEW** — heel-strike-synced steps |
| `scenes/player/flashlight_rig.gd` | **NEW** — lagging lamp + 3D hum (F key) |
| `scenes/player/player.tscn` | **REPLACE** — Footsteps + FlashlightRig nodes |
| `autoload/events.gd` | **REPLACE** — `main_camera` registration var |
| `scenes/player/camera_rig.gd` | **REPLACE** — registers itself as `Events.main_camera` |
| `project.godot` | **REPLACE** — AudioMgr autoload |

Commit: `git commit -m "phase 8: audio systems"`.

## Architecture

- **Bus layout is serialized** in `default_bus_layout.tres` (editor-visible, mixable in the Audio panel): `SFX` and `Ambient`, each with `[0] AudioEffectLowPassFilter` (deafness) + `[1] AudioEffectReverb` (room), both sending to `Master`. AudioMgr resolves the effect instances at boot; if the layout ever fails to load, it rebuilds the same graph at runtime as a fallback (warning in Output). Effect ORDER is a contract: 0 = deafness, 1 = reverb.
- **Footsteps** fire from the rig's `heel_strike(strength, foot)` — the exact bottom of each step curve, alternating feet. Pitch drops up to −20% with carry weight (drag the F2 slider while walking!), volume follows step strength.
- **Reverb probe**: 6 physics rays from the camera @10 Hz (player's own capsule excluded — otherwise every room reads "coffin"). Average distance → room size + wet + damping, smoothed. Tight corners choke the echo; open space floods it.
- **Impact deafness**: damage ≥12 → low-pass slams to 400 Hz on SFX+Ambient and re-opens over 2 s (quadratic: fast slam, slow recovery), while a 7.2 kHz **tinnitus ring fades on Master** — the ring is internal, so it must NOT be muffled. That contrast is the whole effect.
- **Landing thud** on `Events.hard_landed`, volume/pitch scaled by impact energy.
- **Flashlight (F)**: SpotLight + hum live on a rig that **lags the camera exponentially** — the beam swims a beat behind your head, shadows shift while walking, and the hum pans in 3D from wherever the lamp currently is (design doc verbatim).

## ✅ Acceptance test

- [ ] Walk: a thump per step, alternating character, locked to the visual dip (no timer drift). Sprint: faster; crouch: softer/slower.
- [ ] F2 → carry weight to 1 → steps audibly deeper/lower-pitched while walking.
- [ ] Jump off the platform: distinct heavy thud on landing; small hop = small thud.
- [ ] Arrow-key hit (≥12 dmg): world goes underwater + high ring; both recover over ~2 s. Hits <12 (H can roll low): no deafness.
- [ ] F: cone appears, lagging your look swings; hum audible, positioned at the lamp; F again: off.
- [ ] Stand in a corner vs middle of the room: subtle reverb difference (graybox is one box — this is faint by design; real levels will sing).
- [ ] No red errors; Audio panel (while running) shows Master/SFX/Ambient with effects.

## Knobs

AudioMgr (Project → Autoloads → AudioMgr): `deaf_threshold`, `deaf_recovery`, `tinnitus_peak_db`, `probe_range`, `reverb_wet_max`…
Footsteps node: `pitch_weight_drop`, `volume_base`. FlashlightRig: `lag_rate` (lower = swimmier beam), `spot_angle_deg`.

## Known placeholders (by design)

- **Real recordings now**: footsteps (3 concrete variants, CC0 Freesound), landing thud, hit impact, door creak, flashlight click — see `CREDITS.md` for titles/authors/licenses. Tinnitus ring + flashlight hum remain synthesized (they're electrical/internal sounds — synth is correct for those).
- Footstep takes are picked randomly per step with per-foot pitch character; swap the three `footstep_concrete_*.mp3` files anytime.
- Surface types (wood/metal/grass sets) arrive in Phase 9 via raycast surface tags.
- Stereo foot panning is minimal (feet are under the camera) — fine for now.

## Next

Pass → **Phase 9: environmental triggers** — crawlspace Area3Ds (forced crouch + reverb choke + thud loop), wall-collision thuds from velocity·normal, heavy-door interaction impulses, and surface-tagged footsteps. The graybox gets a crawlspace + door built in.
