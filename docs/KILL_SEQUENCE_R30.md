# KILL SEQUENCE — R30 ("the kill, done properly")

Replaces the R26–R29 jumpscare director (`jumpscare_director.gd`, deleted).
User verdict that started this round: *"the current one is not too good."*
Agreed targets from the R30 design questions: hybrid choreography, PSX-stepped
creature vs smooth camera, hard whip + roll on impact, 3 kill variants, full
5–6-layer audio mix from real library sources, full screen FX, cinematic
~3.5–4 s, settle-then-fade ending, accessibility sliders, pure cinema (no
struggle input).

Run the self-test:

```
godot --headless --path . --fixed-fps 60 --quit-after 1600 \
	  -s res://tests/jumpscare_selftest.gd        # 35 checks
```

---

## 1. The seven beats

| beat (authored t) | state | what happens |
|---|---|---|
| 0.00 `beat_impact` | IMPACT | the blow lands. Camera **whips toward the hit direction** with roll on a damped spring (impulse → overshoot → settle); red flash, chromatic aberration, FOV punch, blood spray + splatter decal; layers: `js_impact_hit` + `js_sub_boom` + `js_metal_pierce` + `js_swing_whoosh` |
| 0.16 `beat_grab` | IMPACT | hands on you: `js_grab_cloth` + `js_screech_long` |
| 0.62 `beat_gape` / `beat_lift` | HANG | jaws open (or body hoisted, slam variant); `js_riser` + `js_breath_close`; **slow-mo begins** (warped clock ×0.55) |
| 1.15 `beat_bite` | HANG | the kill bite: `js_jaw_chomp` + `js_bone_crack` + `js_gore_slash` + `js_screech_bite`; second FX hit |
| 1.55 `beat_slowmo_end` | HANG→THRASH | world speeds back up |
| 1.95 `beat_thrash` | THRASH | thrash kicks, tape tears |
| 2.65 `beat_drop` | CRASH | you are dropped: camera falls under gravity, one bounce |
| 3.15 `beat_settle` | SETTLE | on the floor: `js_body_fall` + `js_sub_drop` + `js_tinnitus`; lens smear; breathing jitter; tilted horizon; **creature legs/shadow cross the lens**; blood pool creeps out |
| 4.00 `beat_fade` | FADE→HOLD | slow desaturating fade → death overlay (player presses R; softlock guard at `respawn_timeout_sec`) |

Real-time length: impact→settle ≈ **3.7 s** (the cinematic), +1.1 s fade into
the death screen. Slow-mo stretches authored 0.62–1.55 s by ×1/0.55.

## 2. The PSX read

The creature performance (`scenes/enemies/kill_anim.tres`) is **12 fps stepped
poses, `INTERPOLATION_NEAREST`, no vertex wobble**: each pose holds until the
next beat. The camera is **perfectly smooth** (spring + damped follow at render
rate). That frame-rate mismatch between subject and lens is the 1998 read.
Poses are authored in `audio_work/kill_pose_lib.py` + `gen_kill_beats.py`
(→ `tools/beats.json`), serialised by `tools/build_kill_anims.gd`:

```
godot --headless --path . -s res://tools/build_kill_anims.gd
```

which rewrites `kill_anim.tres` (body, 3 variants × 45 bone tracks) and
`kill_staging.tres` (the beat sheet: method keys + scare-light curve).

## 3. One warped clock

`_wt` (authored time) advances by `delta * warp(_wt)`; both players are
`seek(_wt, true)`ed every frame, so slow-mo can never desync audio beats from
creature poses. **`seek()` does not fire method tracks** (verified:
`tests/_seek_test.gd`), so the director *reads* the staging clip's method keys
as a beat table and calls them itself — designers move beats in the animation
panel and everything (audio, FX, camera) follows. The staging
AnimationPlayer is **never played or seeked**: a paused player re-fires
method callbacks on every `seek(update)` (found the hard way — `beat_settle`
was resetting its own timer every frame). The scare-light curve is sampled by
hand (`_sample_light`) for the same reason.

The creature's own gait AnimationPlayer is deactivated for the duration (two
mixers writing one Skeleton3D is a fistfight), and `nightmare_creature.gd`'s
`_find_anim()` skips kill-rig players by name so the feeding/gait selector can
never grab `KillBodyAnim`.

## 4. Camera

* **Whip**: impulse into a damped spring (`whip_strength`, `whip_stiffness`,
  `whip_damping`) in the pre-hit eye frame; direction from
  `survival.last_damage_direction` (creature→player), so a hit from the left
  whips left. Roll couples off the sideways impulse (`roll_coupling`,
  clamped `roll_max_deg`). FOV gets its own spring impulse (the punch).
* **Hang**: damped follow (`hang_rate`) to a per-variant head-bone weld with a
  slow dolly-in (`push_in`); grab = low front into the jaws, swipe = off-side,
  slam = high front looking down. Handheld noise rides on top.
* **Crash** (R31 heavy-object pass): the release is a *throw*
  (`crash_throw_out`, `crash_drop_v`), the fall is hard (`fall_gravity` 14.5)
  with a horizon tumble (`crash_tumble_speed`, damped by `crash_spin_damping`),
  and the floor meeting is a bounce chain (`floor_restitution` 0.34 first
  contact, `restitution_falloff`, `max_bounces`, `bounce_stop_speed`,
  `crash_scatter`). Rotation alignment is lazy airborne (`crash_align_air`) and
  snappy after contact (`crash_align_ground`), drifting to the floor framing
  with `settle_tilt_deg` of roll toward the hit side. Landing jolts ride the
  whip spring (applied during CRASH/SETTLE since R31), with impact-scaled
  thuds and an FOV punch on first contact. See §11.
* **Settle**: breathing sine + noise (`breath_hz`, `breath_amp`), creature
  translated `cross_distance` across the lens (legs + shadow sweep). Entered
  by the *physics*, not the beat sheet — see §11.

All impulses/noise scale by `Settings.camera_shake` (0 = rock steady).

## 5. Screen FX — `scenes/fx/kill_fx.*`

CanvasLayer **4** (above VHS layer 2 and HUD 1, below crisp UI 10), one
ColorRect, `shaders/kill_fx.gdshader`: red flash, radial chromatic
aberration, scanline tear, pulsing vignette, lens blood/dust smear
(`assets/textures/lens_blood.png`), desaturation, grain, narrative fade.
Effect channels scale by `Settings.kill_fx`; flashes are additionally capped
by `Settings.reduce_flashes`. The narrative fade is never gated.

## 6. Gore — `scenes/fx/blood_burst.*`

GPU-particle spray (one-shot, direction = away from the blow), a splatter
Decal raycast-placed on whatever the blow was heading for, and a floor pool
Decal that creeps out during SETTLE. Textures are generated
(`audio_work/gen_blood_textures.py`) — splatter/pool/dot/lens, hard PSX edges.
Everything scales by `Settings.gore`; 0 skips particles, decals and raycasts.

## 7. Audio

16 mono 44.1 kHz layers in `audio/sfx/jumpscare/`, mixed in
`audio_work/produce_audio.py` from Mixkit previews + synthesised sub/tinnitus
elements (see README/CREDITS.md for per-file provenance). 16 pooled
`AudioStreamPlayer`s on the SFX bus, ±3 % pitch jitter per hit. dB trims are
exports on the director.

## 8. Accessibility — `autoload/settings.gd` + `scenes/ui/settings_menu.*`

F1 or Esc opens the pause/settings menu (pauses the tree, releases the mouse).
Sliders: **Camera Shake**, **Kill Screen FX**, **Gore / Blood**; checkbox
**Reduce Flashes**. Persisted to `user://settings.cfg`. The menu refuses to
open while group `kill_active` exists (pausing mid-scare would park the player
in a frozen kill cam). Mouse-look no longer fights the menu for Escape.

## 9. Files

| file | role |
|---|---|
| `scenes/enemies/kill_director.gd` | the director (state machine, spring, beats) |
| `scenes/enemies/kill_anim.tres` | creature body performance (built) |
| `scenes/enemies/kill_staging.tres` | beat sheet + scare-light curve (built) |
| `scenes/enemies/kill_rig.tscn` | standalone rig (auto-instanced if a level loses the inline block) |
| `scenes/fx/kill_fx.{gd,tscn}`, `shaders/kill_fx.gdshader` | screen pass |
| `scenes/fx/blood_burst.gd` | particles + decals |
| `autoload/settings.gd`, `scenes/ui/settings_menu.{gd,tscn}` | dials + menu |
| `tools/build_kill_anims.gd`, `tools/beats.json` | animation builder + authored poses |
| `tests/jumpscare_selftest.gd` | 43-check suite (35 at R30, +8 in R31) |

## 10. Delivery zips — `tools/make_release_zip.py`, `tools/make_delta_zip.py`

Two flavours, both written to the workspace root (one level above the project):

| zip | size | use it when |
|---|---|---|
| `kill_r31_DELTA.zip` | < 0.2 MB | you already installed the R30 delta. Code/docs/tests only — nothing to re-import. Built with `python3 tools/make_delta_zip.py --base e91f99b --tag R31 --out ../kill_r31_DELTA.zip`. |
| `kill_sequence_r31_whole_game[_linux].zip` | 27-34 MB | fresh start / no earlier copy. |
| ~~`kill_r30_DELTA.zip`~~ | ~3.4 MB | superseded by R31; historical: R29 tip → R30. |

The delta is built from `git diff 821f317..HEAD` (R29 tip → now) minus `.godot/`,
so it can never drift from what is committed; `_R30_MANIFEST.txt` inside it carries
byte counts + sha256 prefixes if you want to check a file landed.

**Why the full zip is not the whole repo:** `addons/limboai/bin` ships ~88 MB of
native libraries for every platform (iOS, Android, macOS, Web, Linux arm64/x86_64,
Windows). `tools/make_release_zip.py` takes a platform argument and keeps only the
binaries that host can load:

```
python3 tools/make_release_zip.py linux      # 27.7 MB  (EndeavourOS / any x86_64 Linux)
python3 tools/make_release_zip.py windows    # ~28 MB
python3 tools/make_release_zip.py desktop    # 34.1 MB, default: linux+windows+macos
python3 tools/make_release_zip.py all        # ~50 MB, every target — the version that
											 # tripped the upload limit, don't ship it
```

The dropped binaries are still in git — restore any of them with:

```
git checkout -- addons/limboai/bin
```

Godot only loads the library matching the host platform, so the missing ones are
harmless until you export to that platform.

**R30b fix:** `blood_burst.gd` set `StandardMaterial3D.particle_trails`, a Godot 3
property. Godot 4 warns `remapped parameter not found` and ignores it, so the line
did nothing. Trails now go through the emitter (`GPUParticles3D.trail_enabled` /
`trail_lifetime`, exposed as `spray_trails` / `spray_trail_lifetime` exports, off by
default). Note 4.7 exposes only those two trail properties — `trail_sections` and
`trail_section_subdivisions` are not script-visible and assigning them is a hard
script error.

---

## 11. R31 addendum — first-playtest fixes

Full write-up: `docs/FIXES_R31_footsteps_killstart_crashweight.md`. Summary of
what changed *behaviourally*:

1. **Kill start = your own eyes.** The director no longer hard-cuts to the
   authored scare-cam pose (`(0, 1.8, −2.25)` on the creature, 94.25° FOV) —
   that read as "the camera rises from the ground", worst while crouched. It
   now captures the player camera's transform **and** FOV and snaps the kill
   cam onto them before taking authority. The only rise left is the HANG weld
   hoisting you toward the jaws (intentional; tune `hang_rate`, `push_in`).
2. **SETTLE/FADE are armed by beats, entered by physics.** `beat_settle` sets
   `_settle_pending`; `_enter_settle()` fires when the body has actually
   landed (`_crashed`), with `crash_timeout` (1.6 s) as the safety net.
   `beat_fade` waits for `settle_before_fade` (0.5 s) of floor-shot breathing.
   The staged 0.5 s drop→settle window used to teleport the lens to the floor
   mid-bounce. Total kill ≈ 5.1 s now.
3. **Heavy-object crash dials** (all in the `Crash & settle` export group):

   | Dial | Default | Meaning |
   |---|---|---|
   | `fall_gravity` | 14.5 | fall acceleration (was 11) |
   | `crash_throw_out` | 0.7 | release speed away from the creature |
   | `crash_drop_v` | 1.2 | initial downward speed at the drop beat |
   | `floor_restitution` | 0.34 | first-bounce energy kept (was 0.22) |
   | `restitution_falloff` | 0.5 | each further bounce keeps this fraction |
   | `max_bounces` | 2 | hard cap |
   | `bounce_stop_speed` | 0.55 | contact slower than this = the landing |
   | `crash_scatter` | 0.3 | random sideways scatter per bounce |
   | `crash_tumble_speed` | 26 | horizon roll °/s while airborne |
   | `crash_spin_damping` | 5.5 | how fast the tumble dies after contact |
   | `crash_align_air` / `_ground` | 1.6 / 6.5 | framing-align rate before/after contact |
   | `crash_timeout` | 1.6 | force-land safety net |
   | `settle_before_fade` | 0.5 | minimum floor-shot time before the fade |

4. **Landing weight is visible + audible.** `_cam_crash`/`_cam_settle` apply
   the whip-spring leftovers, so `_on_ground_hit`'s impact-scaled jolt (pitch/
   roll/FOV kick ∝ impact velocity) actually reaches the lens and rings out
   into SETTLE. Every contact plays `js_body_fall` at `linear_to_db(v/7)`
   (first hit +2 dB, later −5 dB); first contact adds `js_sub_boom` −6 dB and
   the FX crash pulse scaled by impact speed.
5. **No ghost footsteps after death.** `freeze_corpse()` on PlayerMovement
   (called by the dead branch *and* by the kill lock) republishes dead-still
   `input_active`/`planar_speed`/`gait`/`noise_level`; the camera rig's gait
   engine is additionally gated on its `_dead` flag (set by
   `Events.player_died`, cleared by `player_respawned`).

Selftest grew 35 → 43 checks (K2h/K2h2/K2h3/K2i kill-start, K12 footsteps,
K13/K13b/K13c crash physics).
