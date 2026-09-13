# Proximity Monitor ("the cardiogram") — Design & Implementation Plan

Companion to the noise meter (`docs/NOISE_METER.md`).
Status: **BUILT (R25)** — `scenes/ui/proximity_monitor.{gd,tscn}` +
`proximity_trace.gd`, wired in `main.tscn`, tested by
`tests/proximity_selftest.gd` (23 checks), captures via `tests/prox_capture.gd`
(`shots/prox_bands_sheet_zoom.png` is the real widget in the four bands).
Mockups: `docs/img/proximity/prox_mock_ingame.jpg`,
`prox_mock_states.jpg`, plus a rejected alternative in
`prox_mock_tracker_alt.jpg`. Game-reference screenshots saved alongside them
(`alien-isolation-...jpeg`, `rainbow-six-...jpeg`).

---

## 1. The idea in one line

The noise meter answers *"how loud am I?"*. The proximity monitor answers
*"how close is it?"* — rendered as a **found-footage camcorder biosignal**: a
small oscilloscope strip whose heartbeat trace flatlines when the creature is far
and escalates into a clipped, jittering red cardiogram at contact.

It deliberately shows **distance, never direction**. Direction is what turns a
horror game into a radar game (see §7); ambiguity is the genre.

## 2. Why a cardiogram and not the obvious alternatives

| Candidate | Precedent | Verdict here |
|---|---|---|
| Sweep tracker disc with blips | Alien: Isolation motion tracker; MGS Soliton radar (R6 crossover gadget) | Gives **direction** → removes the ambiguity this game runs on; also reads as a *tool you hold*, and this protagonist has no diegetic device. Kept as mockup `prox_mock_tracker_alt.jpg` in case direction is ever wanted as a late-game upgrade. |
| Ripple rings + raw metres ("17 M") | R6 Pulse heartbeat sensor | Too tactical/clean for VHS found-footage; a number kills dread (dread lives in curves, not digits). |
| Audio-only static | Silent Hill pocket radio | Great layer, but the brief asks for a GUI; keep as the **audio tie-in** (§6), not the whole system. |
| Screen-edge vignette pulse | Dead by Daylight terror radius visuals | Easy to miss during a fight; works as an ambient *addon* at CONTACT (§6), not as the indicator. |
| **Cardiogram strip** | camcorder OSD / medical monitor language | Glanceable, directionless, escalates continuously (no binary alert), and it rhymes with the VHS treatment the noise meter already established. A heartbeat is also thematically the creature's *or yours* — the ambiguity is a feature. |

## 3. On-screen placement & theme

```
┌──────────────────────────────────────────────────────────┐
│                                                          │
│                     (world, VHS pass)                    │
│                                                          │
│  [health/stamina]        [NOISE METER]      [TRK CLOSE ─]│
│  bottom-left             bottom-centre      ▗cardiogram▖ │
│  (SurvivalHUD)           (NoiseMeter)       bottom-right │
└──────────────────────────────────────────────────────────┘
```

- **Bottom-right**, mirroring the SurvivalHUD bottom-left and clearing the noise
  meter bottom-centre; same vertical band as the noise meter so the bottom edge
  reads as one instrument row.
- Size ~220×40 px strip at the 1280×720 design res, anchored
  `anchor_left/right = 1.0`, `anchor_top/bottom = 1.0`, offsets ≈ (−236, −106) →
  (−16, −66): same ~12-13% bottom margin family as the noise meter.
- Frame: thin rounded dark bezel (same StyleBox language as the noise meter),
  faint border, **4 segment LEDs** at the right end of the bezel (off → lit left
  to right per band), tiny pixel label above-left of the strip:
  `TRK FAR / TRK NEAR / TRK CLOSE / TRK CONTACT` (label optional via export;
  uses the project's Special Elite face at tiny size, or none).
- Treatment: the **same bleed overlay shader** as the noise meter
  (`shaders/noise_meter_bleed.gdshader`, second ColorRect + second material), so
  both widgets weather identically. `shader_influence` export, default 1.0 to
  match the noise meter's shipped look.
- CRT phosphor glow is faked in the draw (double polyline: wide low-alpha +
  narrow bright), no bloom dependency.

## 4. The four bands (all thresholds are exports)

`prox = 1 - clamp(dist / max_range, 0, 1)`, eased `pow(prox, prox_curve)`.

| Band | Distance (defaults) | Trace | Colour / alpha | LEDs | Label |
|---|---|---|---|---|---|
| FAR | > `near_at` (20 m) | near-flat line, tiny noise | desat green, α 0.35 | 0 | TRK FAR |
| NEAR | 10–20 m | calm ripples | amber, α 0.6 | 1 | TRK NEAR |
| CLOSE | 4–10 m | lub-dub heartbeat, beating faster as it closes | orange, α 0.9 | 2–3 | TRK CLOSE |
| CONTACT | < `contact_at` (4 m) | clipped saturated peaks + glitch offsets + widget jitter | red, α 1.0 | 4 (blinking) | TRK CONTACT |

Waveform math (drawn, not textured):

```
beat_hz  = lerp(beat_hz_far, beat_hz_contact, prox)      # 0.8 Hz → 2.6 Hz
amp      = half_height * lerp(amp_far, amp_contact, pow(prox, amp_curve))
y(x)     = mid - amp * heartbeat(frac(x/width * cycles + phase))
           + jitter_noise(x) * prox * jitter_amount
phase   += beat_hz * delta                                 # scroll = the pulse
```

`heartbeat(u)` = two gaussians per period (lub-dub): `exp(-((u-0.10)/0.035)²) -
0.35*exp(-((u-0.22)/0.05)²) + 0.55*exp(-((u-0.34)/0.03)²)` — tune by eye.
At CONTACT the peaks are **clipped** (`min(y, clip_top)`) and occasional 1-2 px
horizontal glitch offsets are injected (hash-gated, same trick as the bleed
grain), plus the whole widget jitters via `offset_transform_position`
(visual-only, exactly like the noise meter's internal shake — and exactly like
it, immune to camera shake by construction).

Fade/hide behaviour copies the noise meter contract: `Events.inventory_toggled`
→ counter-based `_set_menu_open()`, one fade factor driving alpha + slide +
shader influence; keeps updating while hidden.

## 5. Data source (decoupled, read-only)

- Distance: `get_tree().get_first_node_in_group("creature")` →
  `dist_to_player()` (lazy-resolved each frame like the noise meter resolves the
  player; the group already exists and `ai_selftest` uses it the same way).
- Optional `gate_on_awake` export (default **false**): if true, a dormant
  creature reads as FAR regardless of distance. Default false = the monitor is a
  *presence* sensor, honest even while it sleeps (sleeping-next-door dread is
  good dread). Flip per-design later.
- Nothing is written back to gameplay. If a future system needs the value,
  expose `current_prox()`; do not emit per-frame signals.

## 6. Optional layers (exports, all default-conservative)

- `heartbeat_audio` (default off for now): tie the beat to AudioMgr — one muted
  thump per `heartbeat()` period, pan-neutral, volume ∝ prox. This is the
  Silent Hill / DbD layer; keep it switchable because the trace already carries
  the information and double-coding can get noisy.
- `contact_vignette` (default off): at CONTACT, pulse a screen-edge darkening
  (a full-screen ColorRect with a radial alpha, same fade system). Ambient
  dread for players who don't glance at the HUD.
- Direction upgrade (not planned): if ever wanted, add a slow sweep + blip bias
  on the strip — the tracker-alt mockup shows the escape hatch.

## 7. Implementation plan (mirror the noise meter's architecture)

| File | Role |
|---|---|
| `scenes/ui/proximity_monitor.gd` | state, prox curve, beat phase, fade, menu funnel, exports (`class_name ProximityMonitor`) |
| `scenes/ui/proximity_trace.gd` | the drawn half (child of the shaken node), `_draw()` polyline + LEDs + label; duck-typed `owner` like `NoiseMeterBar` (avoids the circular `class_name` trap) |
| `scenes/ui/proximity_monitor.tscn` | layout, bezel StyleBox, LED rects, bleed-overlay ColorRect with its own material of `noise_meter_bleed.gdshader` |
| `scenes/main.tscn` | one line: instance under `UI` layer, after NoiseMeter |
| `tests/proximity_selftest.gd` | teleport creature to distances (5 / 15 / 7 / 2 m), assert band, amplitude ordering, alpha, LED count, menu fade, shake immunity |
| `tests/prox_capture.gd` (dev) | strip captures per band for art review, same pattern as `meter_capture.gd` |

Export surface (inspector-tunable, nothing hard-coded): `max_range` (24),
`near_at` (20→10 boundary naming: `close_at` 10), `contact_at` (4),
`prox_curve`, `amp_far/amp_contact`, `beat_hz_far/beat_hz_contact`, `amp_curve`,
`jitter_amount`, `clip_top`, `trace_width`, `color_far/near/close/contact`,
`alpha_far/near/close/contact`, `led_count` (4), `show_label`, `scroll_speed`,
`shader_influence` (1.0), `menu_open`, fade/slide exports, `gate_on_awake`,
`heartbeat_audio`, `contact_vignette`, `shake_magnitude/frequency/threshold`.

Draw order per frame: bezel → grid ticks → glow polyline (wide, α*0.35) →
core polyline (width `trace_width`) → clip glitch segments → LEDs → label.
Cost: one ~110-point polyline ×2 + LEDs = trivial; the bleed overlay reuses the
existing shader on a 220×40 rect.

## 8. Game references (screenshots saved in `image-search/`)

- **Alien: Isolation** — the motion tracker: diegetic green sweep disc, blips,
  audible ping; the gold standard for proximity dread *with* direction. Its AI
  director also keeps a hidden "menace gauge" — proximity pacing as a system,
  not just a widget: https://www.gamedeveloper.com/design/revisiting-the-ai-of-alien-isolation
  (saved: `alien-isolation-motion-tracker-hud-scree-1/2.jpeg`)
- **Rainbow Six Siege — Pulse's heartbeat sensor**: through-wall detection as a
  timed red ripple + raw metre readout; tactical opposite of our curve:
  https://staticctf.ubisoft.com/J3yJr34U2pZ2Ieem48Dwy9uqj5PNUQTn/668ebz07ZirvKFOzis6Ihh/8b40174a5cccc7cb2287190970413988/r6s_pulse_line_up_the_shot.jpg
  (saved: `rainbow-six-siege-heartbeat-sensor-hud-s-1/2.jpeg`)
- **Metal Gear Solid Soliton radar** (via R6's Snake crossover gadget):
  green/yellow/red area states — banding without numbers, closest cousin to our
  four-band design: https://www.facebook.com/RainbowSixUK/videos/25317907811220549/
- **Silent Hill** pocket radio / **Dead by Daylight** terror radius: audio-first
  proximity; the reason §6 keeps an audio layer as an option.

## 9. Decisions taken at build time (R25)

1. **Label OFF** (`show_label = false` default). The export stays for later.
2. **Asleep = hidden.** `require_awake = true`: while the creature is dormant
   the widget fades out completely (trace node also stops drawing); on wake it
   fades back in with the same ease/slide system as the menu fade. Visibility
   target = `awake AND NOT menu_open`, one shared fade factor.
3. **Heartbeat audio BUILT.** One realistic lub-dub one-shot per visual beat:
   `audio/sfx/heartbeat.wav` — a single beat extracted from Woodingp's CC0
   recording (Freesound 116642; the same original behind patobottos's 53k-
   download "Heartbeats 61"), trimmed/faded/peak-normalised to -3 dBFS mono,
   per the project's existing CC0-preview credits workflow. Volume lerps
   `audio_vol_far_db -> audio_vol_contact_db` with prox, ±4% pitch jitter so
   repeats never machine-gun; silent while far, hidden, or asleep; bus is an
   export (`heart_bus`, default SFX). Synthesised heartbeat candidates were
   rejected on review as exactly the "cheap audio" to avoid.
4. **Boots hidden, not flatlined** — consequence of (2): first wake is also the
   first time the player sees the trace, which teaches both meanings at once.
5. **Centre glow BUILT** as a runtime radial-gradient texture behind the trace,
   strength `glow_strength * (0.35 + 0.65 * prox)`, tinted by the band colour —
   the mockup's hot phosphor middle.
6. **Bleed shader reused** (`noise_meter_bleed.gdshader`, second material on the
   overlay ColorRect, `shader_influence` default 1.0 to match the noise meter's
   shipped look), so both widgets weather identically and the influence fades
   with visibility (no ghosting, asserted in the selftest).

## 10. Build-time bugs caught by the captures (kept as warnings)

- The lub-dub gaussians were narrower than the 2 px draw step, so peaks
  undersampled into ripples; now 1 px step + sigmas tuned against it
  (commented in `proximity_trace.gd:_heartbeat`).
- Any capture/preview harness must settle the monitor's smoothed `_prox`
  (8/s exp lerp) before sampling, or it photographs the previous band.


---

## R25 fix — why widget content vanished in-game (and the crisp-edge complaint)

**Symptom (in-game only):** the noise meter showed a grainy dark strip with no
fill; the proximity monitor showed a grainy box with no trace. Captures without
the full `main.tscn` stack looked perfect, which is why it slipped through.

**Cause:** `hint_screen_texture` is copied ONCE per frame at the FIRST sampling
point in the render list — here the VHS pass on CanvasLayer 2, i.e. before any
UI draws. The old `noise_meter_bleed.gdshader` overlay sampled that stale copy
(world only) and, being an opaque `mix(clean, treated, influence)`, painted OVER
the widget's own bezel/fill/trace with blurred world + grain. Its sharp
rectangle bounds were also the "too crisp on the edges" artifact.

**Fix (both widgets):**
- New `shaders/ui_weather.gdshader` replaces the bleed shader: samples NOTHING,
  outputs only atmosphere (grain / scanlines / vignette / grade tint) as a
  blended pattern layer, multiplied by a **rounded-rect feather mask**
  (`corner_radius`, `edge_feather` uniforms; `rect_size` is set from code each
  frame) so the treatment melts into the screen instead of ending in a crisp
  rectangle.
- Chromatic bleed moved to **draw time**: offset R/B fringe passes under the
  fill / trace (`bleed_pixels` export on both widgets, default 1.5 px).
- `noise_meter_bleed.gdshader` deleted; both `.tscn` materials now reference
  `ui_weather.gdshader` (uniform set: influence, grain_*, scanline_*,
  vignette_*, grade_*, rect_size, corner_radius, edge_feather).
- Heartbeat one-shot levels raised ~4 dB (`audio_vol_far_db` -12,
  `audio_vol_contact_db` 0) after playtest feedback ("a bit louder, not
  exaggerated").
- Warnings cleaned: `size` param shadowing in `proximity_trace.gd`, unused
  loop counter.

Verified with an in-game repro (full `main.tscn` under Xvfb, creature awake at
6 m): fill and trace visible, corners rounded and feathered
(`shots/repro_pair_zoom.png`); 23/23 + 47/47 selftests and smoke pass.

### Audio troubleshooting kit (added after a "no heartbeat" field report)

Local repro proved the voice fires correctly in-game (beats increment, stream
0.75 s, bus SFX unmuted, vol ≈ -2.5 dB at contact). Silence on a specific
machine is therefore environmental, so the widget now self-diagnoses:

- `_ready()` pushes warnings if the stream is missing/unimported, if `heart_bus`
  does not exist (falls back to Master), or if that bus is muted.
- The first beat pushes a one-shot `HEARTBEAT DIAG` warning with volume, bus,
  stream length, prox and fade. `push_warning` output is captured by the
  creature log's ENGINEERR drain, so an uploaded `creature_log.txt` contains the
  answer.
- `debug_force_beats` export beats regardless of gating for instant audibility
  checks on a new setup.

- R25b follow-up: the first-beat DIAG line originally formatted a *concatenated*
  literal (`"..." + "..." % args`); `%` binds tighter than `+`, so the argument
  list misaligned and every first beat logged "String formatting error: a number
  is required" plus a raw-format warning. Fixed by formatting into a variable
  with a single literal. (The error never blocked `play()` — GDScript returns the
  unformatted string and continues — but it spammed the console and the log.)

### R25c — "shader only in the middle" moire fix

Field report: the weather treatment appeared as a dirty smear band across the
widget centre instead of covering it evenly (visible in editor preview too).
Cause: the scanline and grain patterns were defined in UV space —
`scanline_density = 140` lines over a 44 px-tall widget is a 0.31 px period,
which no framebuffer can resolve; it aliases into moire beat bands whose
position depends on window scale (centre in the reported shots). Captures at
fixed 720p read it as mild texture, which is why it passed review.

Fix: patterns now live in PIXEL space with resolvable periods —
`scanline_period_px` (default 3.0) and `grain_block_px` (default 2.0, chunky
VHS cells). Both are uniforms; keep periods >= 2 px or the moire returns.
Verified: band capture shows even coverage, rounded feathered corners, intact
trace/LEDs; 23/23 + 47/47 selftests and smoke pass.
