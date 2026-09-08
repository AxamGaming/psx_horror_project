# Bob v4 — FOUND-FOOTAGE / VHS Mode

> **v4.1 TUNING PASS (current):** playtest #4 — "idle micro-shakes too much; walking swings down-left/down-right too much".
> **Idle fix:** hand tremor is now *exertion-biased* (new `tremor_idle_scale` 0.35 → idle gets ~0.03°, sprint ~0.11°), tremor base 0.15→0.08° at 7 Hz instead of 9, roll wander 0.6→0.3°, breathing 1.2→0.7 cm with roll 0.35→0.18°. Idle = calm-but-alive, not caffeinated.
> **Waddle fix:** lateral sway 2.0→**1.2 cm** (real head lateral ≈ half of vertical, not 83% of it), surge 1.2→0.8 cm, step roll 1.6→**0.9°** (sprint ×1.5 not ×1.8), shoulder yaw 0.8→0.6°. Head path is now a vertical-dominated bounce with a subtle weight-shift instead of big side arcs.
> Still swaying too much? `lat_amp_walk` → 0.008, `roll_amp_deg` → 0.5. Still buzzing at idle? `hand_tremor_deg` → 0.04, `tremor_idle_scale` → 0.15.

**One file changed again: `scenes/player/camera_rig.gd`.** Copy, F5, walk around.

## Why v3's ups-and-downs still felt wrong

v2/v3 were a *game gait cycle*: crisp heel-dips arriving on a metronome. Real found footage is a **person carrying a camera** — the bounce is rounder, everything trails behind the footfalls, the gaze fights to stay framed, and the horizon is never level. Your "not correct but not bad" = right rhythm family, wrong *physics of flesh*.

## The five new layers (all in the new "Found-Footage Feel" inspector group)

1. **Flesh follow-through** — the whole gait signal passes through a lag stage and blends back (`flesh_lag_mix` 0.55): every rise/fall trails ~50–80 ms and overshoots slightly. This is *the* handheld signature. `flesh_lag_mix = 0` gives you the old crisp game-bob, `1` is maximum floppy-camcorder. **This is your main style dial.**
2. **Gaze counter-nod** — pitch now follows the *lagged* vertical: as the head dips, gaze rotates slightly up (the operator keeping the subject framed), and settles back down as it rises. That rolling nod-bounce coupling is what makes VHS footage look *operated* instead of animated. Strength: `pitch_amp_deg` (0.7).
3. **Never-level horizon** — slow roll wander (`roll_wander_deg` 0.6, ~5 s features) + tiny ~9 Hz hand tremor (`hand_tremor_deg` 0.15) that worsens with exertion. Both always alive, even standing still — a handheld camera is never truly static.
4. **No two steps alike** — per-step random depth ±15% (`step_randomize`) on top of the slow ±22% drift (`step_variation`) and bigger cadence jitter (0.12 rad).
5. **Exertion breathing** — breath rate and depth climb with energy (`breath_exertion_mult` 2.5): walking = calm, sprinting = panting heave. Base breathing is more visible now (0.012 m + 0.35° roll).

Gait backbone retuned to match: rounder dips (`dip_sharpness` 0.10), slightly slower cadence (walk 1.7, sprint 2.4 steps/s), walk bounce 2.4 cm, sprint 5.3 cm, more sway/roll (1.6°/2.9° sprint).

## ✅ Test

- [ ] Walking: a *rolling* bounce with a subtle nodding counter-motion — feels filmed, not animated.
- [ ] Standing still: frame is alive — faint breath, whisper of tremor, horizon drifting a hair. Never frozen.
- [ ] Sprinting: heavy bounding bounce, panting rhythm, horizon working harder to stay roughly level — chaotic but still readable.
- [ ] No two steps identical, but the *rhythm* still reads as walking (not v1's drunk float).
- [ ] Stop from sprint: settling step, then the alive-idle.
- [ ] Landings/H-impacts unchanged and still clean.

## The style spectrum (find your spot live via the Remote inspector while running)

| Want | Do |
|---|---|
| More VHS / floatier | `flesh_lag_mix` ↑ (0.55→0.8), `flesh_lag_rate` ↓ (12→8) |
| Back toward crisp game-bob | `flesh_lag_mix` ↓ (→0.2), `dip_sharpness` ↑ (→0.2) |
| Nod feels wrong / too much | `pitch_amp_deg` ↓ (0.7→0.3) or 0 to disable counter-nod |
| Too shaky at idle | `hand_tremor_deg` ↓ (0.15→0.08), `roll_wander_deg` ↓ |
| Bounce too big overall | `bob_intensity` ↓ (master, 1.0→0.8) |
| Sprint too bouncy only | `vert_amp_sprint_mult` ↓ (2.2→1.8) |
| More chaotic steps | `step_randomize` ↑ (0.15→0.3), `timing_jitter_rad` ↑ |
| Too chaotic | `step_randomize` ↓, `step_variation` ↓ (0.22→0.1) |

**Workflow reminder:** drag values while running (Scene dock → Remote tab → MainCamera), and when it feels right, apply the same numbers to MainCamera in the editor and save the scene — scene values override my script defaults permanently. Then tell me your final numbers and I'll bake them into the defaults so the file stays canonical.

## Phase 8 footnote (already in the code header)

`heel_strike` fires at the phase boundary; the *visual* dip lands ~50–80 ms later because of flesh lag. If footsteps ever feel early against the picture, we delay the audio by that offset (or raise `flesh_lag_rate`). Noted so we don't rediscover it later.
