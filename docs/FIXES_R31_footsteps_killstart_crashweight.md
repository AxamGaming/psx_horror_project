# R31 — Playtest fixes: ghost footsteps, the "rising" kill start, heavy-object crash

Round 31. The first real playtest of the R30 kill sequence came back with three
reports. All three are fixed here; each section is *symptom → root cause → fix →
regression guard*.

Test totals after this round: **kill 43/43**, noise 47/47, proximity 23/23,
fly 0 failures, ai 0 failures, boot smoke PASS.

---

## 1. Footsteps kept marching into the death menu

**Symptom.** Die while holding a walk key → footstep audio keeps playing through
the kill cinematic and the death screen, as if the corpse were still walking.

**Root cause.** Two stale-state holes, one of them enough on its own:

1. `PlayerMovement._physics_process()` early-returns in its `dead` branch
   *before* `_update_gait_state()`, so the published state (`input_active`,
   `planar_speed`, `gait`, `noise_level`) freezes at its last living values —
   `input_active == true` if a key was held at the moment of death. This
   affected **every** death route, including the classic (non-creature) one.
2. `KillDirector._lock_player(true)` then calls `set_physics_process(false)` on
   the body for the duration of the kill, so even the `dead` branch never runs —
   nothing can ever republish zeros.

   The camera rig (`CameraRig`, a *child* of the body, still processing) drives
   its gait engine from exactly those stale fields: `_advance_phase()` saw
   `input_active == true` + `planar_speed` → kept advancing `step_phase`, and
   `_check_step_boundary()` kept emitting `heel_strike` → `footsteps.gd` kept
   playing takes on the FootL/FootR buses (plain non-positional players, so
   switching to the kill camera never muffled them).

**Fix (belt and braces).**

- `camera_rig.gd`: the gait engine is gated on `not _dead` in **both**
  `_advance_phase()` and `_check_step_boundary()`, and `_on_player_died_flag()`
  now zeroes `energy`/`step_rate` on the spot. `_dead` is driven by
  `Events.player_died`, which fires on *every* death route.
- `movement.gd`: new public `freeze_corpse()` (the script stays the single
  writer of its own state) zeroes `input_active`, `planar_speed`,
  `noise_level`, `gait`, `is_sprinting`. Called from the top of the `dead`
  branch.
- `kill_director.gd`: `_lock_player(true)` calls `freeze_corpse()` *before*
  freezing processing, so the published state is dead-still for any other
  reader too (noise meter, creature hearing, debug panel).

**Regression guard.** Selftest **K12**: after a kill starts, the harness plants
the stale living state (`input_active=true`, `planar_speed=2.2`) exactly as the
freeze could have left it and counts `heel_strike` emissions all the way to
HOLD — must be **zero** (without the fix, ~7 strikes fire).

The last footfall already in flight when you die still finishes its ~0.3 s
take — that one is real sound, not a ghost.

---

## 2. "Did you intentionally make the camera rise from the ground at the start?"

**Short answer: no — that was a bug. Fixed. The only rise left is the
intentional one: the HANG beat hoisting you toward the jaws.**

**Root cause.** `_on_creature_kill()` captured the player's viewpoint into
`_base_xf` — and then, eight lines later in the "camera authority" block,
**overwrote it** with `_kill_cam.global_transform`: the authored scare-cam pose
baked into the creature scene at `(0, 1.8, −2.25)` local (1.8 m up, 2.25 m out
along the creature's facing). So every kill:

1. hard-cut from your eyes to that pose (up to ~0.8 m higher if you died
   crouched — crawling reads as "the camera lifted off the floor"), and
2. then climbed/dollied from there into the head weld — a second visible rise.

It also read `_base_fov` from the kill cam (94.25°) instead of the player lens,
so the cut popped the FOV as well. The leftover line contradicted the design
comment right above the capture ("that pose is dead weight now: we drive the
cam") — a residue from the R26–R29 rig that used to *play back* that pose.

**Fix.** The scare-cam pose is now truly dead weight: the capture is
transform **and** FOV from `Events.main_camera`, the overwriting line is gone,
and the kill cam is snapped *to the player's exact view* before
`current = true` — frame one of the kill is frame zero of the whip spring. The
HANG weld (creature lifts you toward its face) remains the only authored rise,
as designed; `hang_rate`/`push_in` still tune it.

**Regression guards.** Selftest **K2h** (kill cam holds the captured
`_base_xf` through early IMPACT — no teleport), **K2h2** (the capture *is* the
player's view, within damage-spring recoil), **K2h3** (the capture is
demonstrably NOT the scare-cam pose), **K2i** (kill cam FOV starts at the
captured player FOV, not 94.25).

---

## 3. The crash now lands like a heavy object (with a real bounce)

**Symptom.** "When the camera falls down after the creature finishes you off,
should it bounce a bit then fall like a heavy object?" — it should, and it
didn't. Three compounding reasons:

1. **The settle beat cut the fall mid-air.** `beat_settle` is authored at
   2.65 s + 0.5 s; the fall alone (old gravity 11, ~1.6 m) takes ~0.54 s, and
   the bounce another ~0.3 s. `beat_settle` hard-set `State.SETTLE`, whose
   handler rebuilds the camera from `_floor_xf` — an instant teleport to the
   floor. The bounce was truncated or skipped entirely, most of the time.
2. **The landing jolt was kicked into a spring nobody read.**
   `_on_ground_hit()` added velocities to the whip spring, but the spring
   offsets were only applied during IMPACT/HANG/THRASH — during CRASH/SETTLE
   `_cam_crash`/`_cam_settle` never applied them. The impact had no visible
   weight.
3. **A single weak bounce.** Restitution 0.22 from ~5.9 m/s gives a ~7 cm hop,
   and the old stop rule (`_fall_v.length() < 0.6` on contact) could never
   actually trigger after the first bounce (speed only grows while pinned to
   the floor), so the sim quietly ground against the floor plane.

**Fix — R31 "heavy object" pass** (all dials exported, all in the
`Crash & settle` group):

- **Physics owns the hand-off.** `beat_settle` now only *arms* SETTLE
  (`_settle_pending`); `_enter_settle()` runs the instant the body actually
  finishes landing (`_crashed`), with a `crash_timeout = 1.6 s` safety net that
  force-lands rather than hanging the sequence. `beat_fade` is armed the same
  way and enters only after the floor shot has breathed `settle_before_fade
  = 0.5 s` — so a late landing delays the fade instead of skipping it. The
  full kill is now ~5.1 s (was ~4.8 s).
- **The release is a throw, not a placement.** `beat_drop` gives the body
  `crash_throw_out = 0.7 m/s` horizontally *away from the creature* plus
  `crash_drop_v = 1.2 m/s` downward, with a little random spread.
- **Harder gravity**: `fall_gravity` 11 → **14.5** (impact ≈ 6.7 m/s from the
  grab weld — a fast, committed fall, no float).
- **A real bounce chain**: `floor_restitution` 0.22 → **0.34** first contact
  (~17 cm visible hop), each further bounce scaled by `restitution_falloff =
  0.5`, capped by `max_bounces = 2`, and any contact slower than
  `bounce_stop_speed = 0.55 m/s` is the landing, not a bounce. Every bounce
  scatters sideways a touch (`crash_scatter = 0.3`) — bodies don't bounce
  straight up.
- **Airborne tumble**: the horizon rolls at `crash_tumble_speed = 26°/s` while
  falling (random direction per kill), damped out by `crash_spin_damping` after
  first contact; rotation alignment is lazy in the air
  (`crash_align_air = 1.6` — heavy things don't steer mid-fall) and snappy
  after (`crash_align_ground = 6.5`).
- **The landing is felt**: `_cam_crash`/`_cam_settle` now apply the whip-spring
  leftovers (pitch/yaw/roll/pos), so `_on_ground_hit`'s jolt — scaled by
  impact velocity — is finally visible, rings out through the first breaths of
  SETTLE, and decays to zero in ~0.4 s. First contact also gets an FOV punch
  (`impact_v × 5 °/s` into the spring) and a low `js_sub_boom` layer under the
  thud.
- **Impact-scaled audio**: every ground contact plays `js_body_fall` with
  loudness tracking impact speed (`linear_to_db(v/7)`, first hit +2 dB, later
  contacts −5 dB) — the first slam is the mix peak, the settling contact is a
  fraction of it.
- `_enter_settle()` keeps the staged audio bed (`js_sub_drop`, `js_tinnitus`),
  the blood pool and the creature crossing the lens — but `js_body_fall` moved
  to the contacts above so the thud is synced to the *real* landing frame.

**Regression guards.** Selftest **K13** (floor contact happens), **K13b**
(bounce apex after first contact is ≥ 5 cm above the floor — measured 16.8 cm
at defaults), **K13c** (SETTLE is entered only with `_crashed == true` — no
mid-air teleport). K5 still walks IMPACT→…→HOLD in order; K7 still finds the
lens on the floor.

---

## Files touched

| File | Change |
|---|---|
| `scenes/player/camera_rig.gd` | `_dead` gates on phase advance + step boundary; energy/step_rate zeroed on death |
| `scenes/player/movement.gd` | `freeze_corpse()` + called from the dead branch |
| `scenes/enemies/kill_director.gd` | player-view kill start (transform + FOV); `freeze_corpse()` under the player lock; R31 crash physics (throw, tumble, bounce chain, spring jolt applied, impact-scaled thuds); physics-armed SETTLE/FADE; new `Crash & settle` dials |
| `tests/jumpscare_selftest.gd` | K2h/K2h2/K2h3/K2i + K12 + K13/K13b/K13c (35 → 43 checks) |
| `docs/KILL_SEQUENCE_R30.md` | §11 R31 addendum (dial table + hand-off rules) |
| `tools/make_delta_zip.py` | generalized: `--base/--out/--tag`, auto changelog from git log |
| `tools/make_release_zip.py` | output renamed r30 → r31 |

No assets, scenes or resources changed — this round is pure script/docs/tests,
so the delta install has nothing to re-import.
