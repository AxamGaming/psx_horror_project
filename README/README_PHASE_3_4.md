# Phase 3–4 Delivery — Bob Engine + Spring/Landing/Impulse Layer

## Files to copy into your project

| File | Action |
|---|---|
| `scenes/player/camera_rig.gd` | **NEW** — copy in |
| `scenes/player/player.tscn` | **REPLACE** (adds the rig script to MainCamera) |
| `project.godot` | **REPLACE** — or, if Godot already modified yours, just add 2 input actions manually: `debug_impulse` → **H**, `debug_overlay` → **F3** |

Everything else is unchanged. Commit before and after: `git add -A && git commit -m "phase 3-4: bob engine + spring layer"`.

## What you should feel (design doc → implementation map)

- **Biomechanical momentum** — bob swells in over ~0.2 s when you start moving (energy rise/fall smoothing), and the first step out of idle kicks a small "heavy dip" (start-dip impulse). Stopping lets the bob linger ~0.3 s before fading.
- **Steadicam noise balance** — 3 `FastNoiseLite` SIMPLEX_SMOOTH channels (single scale, no fractal ripples): vertical stride rhythm, lateral weight-shift (drives side-sway + roll + yaw), always-on slow breathing. Paths never repeat.
- **Phase-driven stride** — bob advances with *movement*, not the clock: ~1.8 steps/s walking, ~2.5 sprinting, slower and smaller while crouched. Standing still = zero drift except breathing.
- **Focal shift ("breathing lens")** — FOV opens ~1° as the camera dips under a step, +5° smoothed widen while sprinting, punch on hard landings/impacts.
- **Spring weight formula** — all impulses (landing, gait start, impacts) go through one sub-stepped semi-implicit spring (mass/stiffness/damping). Underdamped on purpose (ζ≈0.58): deep dip → one clean overshoot wobble → settle < 1 s.
- **Landing physics** — every touchdown dips proportional to fall speed; above 7 m/s it goes *hard*: extra kick + random lateral scatter + "knees buckle" roll + FOV punch.
- **Breaking the noise loop** — big impacts silence the organic bob (suppress), which blends back over ~0.4 s exactly as the doc's "re-introducing the organic sway" step describes.
- **Heel-strike signal** — fires at the exact bottom of each step (vertical noise derivative flip, refractory-guarded, left/right alternating). Nothing listens yet — Phase 8 footsteps will.

## New controls

| Key | What |
|---|---|
| **H** | Debug impact: random-direction hit, magnitude 4–7. Phase 7 enemies will call the same `apply_impulse()`. |
| **F3** | Toggle debug overlay (top-left, 10 Hz): energy, gait, phase, spring magnitude, roll, mass, strike counter, FOV, suppress. |

## ✅ Acceptance test

**Idle**
- [ ] Standing still: only faint breathing drift; overlay `energy ≈ 0.00`; `strikes` counter does NOT climb.
- [ ] Look around with mouse: aiming is unaffected, horizon snaps back level when you stop (roll never accumulates).

**Walk / Sprint / Crouch**
- [ ] Walk: rhythmic bob with slight side-sway and roll; `strikes` climbs ~2/s; subtle FOV pulse.
- [ ] First step from idle has a visible small dip.
- [ ] Sprint: deeper, faster bob; wider roll; FOV visibly widens; ~2.5 strikes/s.
- [ ] Stop from sprint: bob fades smoothly over ~0.3–0.5 s, no instant freeze, no pop.
- [ ] Crouch: smaller, slower bob.

**Landings**
- [ ] Jump in place (Space): small dip on touchdown.
- [ ] Walk up the ramp, jump off the platform: deep dip + brief wobble + slight random tilt + FOV punch, fully settled < 1 s.
- [ ] Bigger fall = visibly bigger response (jump off while sprinting, or from the stacked crates).

**Impacts (H)**
- [ ] Camera snaps sharply in one direction + roll tilt, bob goes quiet for a beat, then organic sway fades back in over ~0.4 s.
- [ ] Mash H repeatedly: spring never explodes, always recovers to center.

**Stress (Rule 3 checks)**
- [ ] While running, drag/resize the game window or cause a hitch (open overlay, alt-tab): no spring explosion, no camera teleport.
- [ ] Sprint in circles while spinning the mouse: no stutter, no drift, no roll buildup.

## Tuning guide (Inspector → Player → HeadPivot → MainCamera)

| If it feels… | Turn… |
|---|---|
| Too floaty / response too slow | `energy_rise_rate` ↑ (5→8) |
| Bob too big/small | `vert_amp_walk` (meters) |
| Too bouncy after landings | `spring_damping` ↑ (11→14) |
| Not wobbly enough | `spring_damping` ↓ (11→9) |
| Too heavy overall | `spring_stiffness` ↑ (90→120) |
| Landing too dramatic | `land_dip_scale` ↓ / `land_hard_vel` ↓ |
| FOV wobble annoying | `fov_bob_amp` ↓ (1.0→0.4) or 0 to disable |
| Roll direction feels wrong | that's aesthetic — tell me and I'll flip the sign |
| Steps feel too regular/rare | `noise_freq_vert` (1.0) / `noise_units_per_cycle` (2.0) |

Note: steps are *organic*, not metronomic — noise-driven minima vary in spacing slightly. That's the doc's intent ("natural variation"); the refractory timer prevents double-steps.

## Report back

Output-panel errors (if any), checklist failures, and feel notes ("bob too big", "landing too weak", "roll leans wrong way"). Once this passes: **Phase 5 = PSX presentation** (640×360 SubViewport + nearest upscale + the quantize hook that's already stubbed in `_apply_to_camera`).
