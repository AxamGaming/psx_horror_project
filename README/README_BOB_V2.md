# Bob Engine v2 — "Gait Backbone + Noise Seasoning"

> **v3 TUNING PASS (current):** playtest verdict was "dips too aggressive at walk, sprint slightly too much".
> Changed defaults: walk dip **3.5 → 2.2 cm**, sprint **6.0 → 4.8 cm** (mult 2.2), heel spike softened (`dip_sharpness` 0.25 → 0.18), gaze-drop per step 0.45 → 0.30°, roll 1.2 → 1.0° (sprint mult 2.0 → 1.7), lateral 2.0 → 1.6 cm, and the FOV pulse is now **proportional to actual dip depth** (`fov_bob_gain` 25°/m → walk ≈ 0.55°, sprint ≈ 1.2°) instead of a fixed 1°.
> New master slider: **`bob_intensity`** (0–2) scales ALL gait motion at once — drag it while running (F5, inspector stays live) to find your feel in seconds, then set that value on MainCamera in the editor and save the scene. Scene-saved values override script defaults forever, so your tuning survives all my future script updates.

**Only one file changed: `scenes/player/camera_rig.gd`** — copy it over, F5, done. (No scene, project, or asset changes. And no — nothing needs a Perlin texture; `FastNoiseLite` generates all noise procedurally in-engine.)

## Why v1 felt "weird but correct"

Amplitudes and frequencies were right, but the **waveform** was wrong: raw simplex noise has minima of random depth at random spacing, so every step was a slightly different step. Your vestibular system expects periodic gait — irregular steps read as "drunk float." Two more artifacts: phase locked to raw energy made steps go slow-motion when you started/stopped, and heel-strikes were detected by noise-derivative guesswork.

## What v2 does differently

| Layer | v1 | v2 |
|---|---|---|
| Backbone | raw noise (random steps) | **periodic gait curve**: 2-harmonic vertical (sharp loading dip at each heel-strike, softer push-off rise), lateral sway once per stride, yaw/pitch/surge once per step |
| Noise | everything | **seasoning only**: ±12% step-depth drift, subtle timing jitter (human cadence, not metronome), thin 18% raw-noise layer for the doc's organic path |
| Cadence | rate ∝ energy → slow-mo at walk start/stop | rate has a **floor (60%)**; amplitude carries the ramp. On stop: one natural **settling step**, then rest |
| Heel-strike | derivative-flip detection + refractory | **exact**: fires on integer crossings of `step_phase`; feet alternate deterministically |

Spring/landing/impulse/inertia/FOV layers are unchanged — they were fine.

## ✅ What should feel different

- [ ] Walking now has a recognizable *rhythm*: dip–rise, dip–rise, with sharp loading and a consistent sway onto each stance leg. No more "floating on a balloon."
- [ ] Starting to walk: first steps are small but at human tempo (no slow-motion windup).
- [ ] Stopping: one final settling step, then stillness — no ghost crawl.
- [ ] FOV pulses once per step now (was erratic).
- [ ] Sprint = same waveform, deeper/faster/wider — still coherent.
- [ ] Steps are *not* perfectly identical: depth drifts slowly over several steps, cadence wobbles subtly. Repeat a 10 s walk — it shouldn't loop audibly/visibly.
- [ ] Overlay (`F3`): `step` counter increments ~1.8/s walking, ~2.5/s sprinting; `strikes` matches it.
- [ ] Everything from the Phase 3–4 checklist still passes (landings, H impacts, no explosion on frame spikes).

## New knobs (Inspector → MainCamera)

| If it feels… | Turn… |
|---|---|
| **Anything, globally** | **`bob_intensity`** (master 0–2, live at runtime) |
| Dips still too aggressive | `vert_amp_walk` ↓ (0.022), `dip_sharpness` ↓ (0.18) |
| Too metronomic / robotic | `step_variation` ↑ (0.12→0.25), `timing_jitter_rad` ↑ (0.06→0.12), `noise_mix` ↑ (0.18→0.3) |
| Still too random / floaty | those three ↓ (variation 0.06, jitter 0.02, mix 0.1) |
| Steps too fast/slow | `walk_step_rate` (1.8), `sprint_step_rate` (2.5), `crouch_step_rate` (1.1) |
| Side-sway too much | `lat_amp_walk` ↓ (0.016) |
| Roll leans the *wrong way* onto the stance leg | tell me — it's a one-character sign flip |
| Final settling step too slow/fast | `finish_step_rate_mult` (0.5) |
| Walk-start feels wind-up-y | `cadence_floor` ↑ (0.6→0.75) |
| FOV pulse too strong/weak | `fov_bob_gain` (25 °/m; 0 disables) |

## Report back

Same as before: errors, checklist fails, feel notes. Specifically: **does it read as "walking" now?** Next up regardless: **Phase 5 (PSX presentation)** — 640×360 SubViewport, nearest upscale, snap filter into the stubbed hook — unless you want more gait tuning passes first.
