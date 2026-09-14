# Noise Meter — Build Notes

Built 2026-09-12 on Godot 4.7.2 / `psx_horror_project`.
Design history: `noise_meter_design.md` (workspace root). This file documents
**what shipped**, **how to tune it**, and **what is deliberately left for later**.

---

## 1. What was built

| File | Role |
|---|---|
| `scenes/ui/noise_meter.gd` | The widget. All state, smoothing, shake, fades, event spikes, menu subscription. `class_name NoiseMeter`. |
| `scenes/ui/noise_meter_bar.gd` | The drawn half (track, ticks, rounded fill). Lives on the node that carries the shake offset so the art stays glued to it. Deliberately untyped (see §6). |
| `scenes/ui/noise_meter.tscn` | Layout only, house convention: anchors/geometry + the overlay's `ShaderMaterial` with every uniform value written out for the inspector. |
| `shaders/noise_meter_bleed.gdshader` | Widget-local VHS treatment (chromatic bleed, grain, grade, crush, scanline, vignette). No UV displacement — bleed only. |
| `scenes/main.tscn` | One new line: `NoiseMeter` instanced under `UI` (CanvasLayer 10), before `DebugPanel` so menus paint over it. |
| `scenes/enemies/nightmare_creature.gd` | Two new exports: `hear_noise_floor` (0.3), `crouch_hear_range` (1.6). |
| `scenes/enemies/creature_awareness.gd` | Two-tier `_hearing_check()` + `heard_quietly()` query. |
| `tests/noise_meter_selftest.gd` | 47-check self-test (hearing tiers + widget behaviour). |
| `tests/meter_capture.gd` | Dev tool: renders the meter strip at 6 loudness levels to `user://meter_cap/` for art review. |

Nothing else in the project was touched. `player_movement.gd`'s noise bands, the
`gun_fired` / `hard_landed` / `wall_hit` signals, the VHS pass and the camera
shake systems are all exactly as they were.

---

## 2. How each requirement is met

| Requirement | Mechanism |
|---|---|
| Centred near bottom | `noise_meter.tscn`: `Bar` anchored `0.5/1.0`, offsets place a 220×14 bar ~13% of viewport height above the bottom edge (1280×720 design res; stretch mode keeps it proportional). |
| ~40% affected by the post shader | A full-screen pass cannot affect one widget "40%" (below PostFX = 100%, above = 0%), so the meter draws crisp above PostFX and `BleedOverlay` — a `ColorRect` covering exactly the bar rect — re-samples the screen inside the widget area and runs **the project's own `vhs_wiggle.gdshader` colour pipeline** on it (YIQ chroma smear, three-pass blur, darkness lift), then `mix(clean, treated, influence)`. The mix weight is exact: whatever `shader_influence` says is precisely how much of the VHS look is applied. **Ships at 1.0 — the full tape-degraded look — per art decision** (it just reads better; reference: `shots/theirs_vs_default.png`). The original stealth-HUD spec asked for ~0.4; that value is one inspector click away and still supported. Wiggle/displacement is gated behind `vhs_wiggle` (default 0 = colour bleed only); raise it and the meter wobbles like the world does. |
| Not affected by external shake | All project shake is camera-space (`CameraRig` springs/impulses inside `GameViewport`). The meter is a `CanvasLayer` child in screen space — no code path reaches it. Test B13 asserts the meter has no `SubViewport` ancestor. |
| No stacking with other shake | Its own jitter writes only `Bar.offset_transform_position`; `offset_transform_visual_only = true` keeps layout/input untouched. Nothing else writes that channel. |
| Smooth fill, rise snappier than fall | Asymmetric exponential lerp in `_update_noise()` (`rise_speed` 10, `fall_speed` 4 ⇒ ≈0.3 s up / ≈0.7 s down), same `1 - exp(-rate*delta)` idiom as `SurvivalHUD`. |
| White → pale orange → red | Two-segment gradient `fill_color_low → mid → high` split at `red_threshold` (0.7). Verified visually: `shots/contact_sheet.png`. |
| Subtle shake at high loudness, scaled | `FastNoiseLite` x/y samples at `shake_frequency`, amplitude `shake_magnitude * t^shake_curve_power * fade`, `t = inverse_lerp(shake_threshold, 1, displayed)`. Zero below threshold, ~2.5 px max. |
| Crouch < walk < run visibly | Reads the live `player.noise_level` (0.15 / 0.5 / 1.0) — the same float the creature hears. |
| Menus hide/show smoothly, no ghosting | `Events.inventory_toggled` → counter-based `_set_menu_open()`. One fade factor drives bar alpha, slide (`slide_offset`, ease-out on show) **and** the overlay's `influence` uniform; overlay is hidden entirely at ~0 alpha. |
| Noise keeps updating while hidden | `_update_noise()` runs regardless of fade; only presentation is gated. |
| Landing / gunshot / impact spikes | `Events.hard_landed` (× `landing_spike_scale`), `Events.gun_fired` (`gunshot_spike` = 0.85), `Events.wall_hit` (× `wall_hit_spike_scale`). Display-only; decays via `spike_decay_rate`. |
| Decoupled from the source | Widget reads one float + existing signals. Public `add_noise_spike(amount)` lets any future system (doors, glass) add loudness without the meter knowing what it was. |

---

## 3. Creature hearing — the agreed behaviour

Authoritative path: `CreatureAwareness.tick()` → `_hearing_check()`, queried by the
LimboAI task `CondHearsPlayer`. `perception.gd`/`memory.gd` are legacy, never
instantiated — untouched.

```gdscript
if noise > hear_noise_floor:            # LOUD tier
	heard = dist < hear_radius * noise  # louder => audible from further
else:                                    # QUIET tier (idle / crouch)
	heard = dist < crouch_hear_range    # point-blank only; 0.0 disables
```

Defaults (`hear_noise_floor = 0.3`, `crouch_hear_range = 1.6`,
`hear_radius = 16.0`, `gunshot_hear_range = 40.0` — all `@export`):

| Player state | noise | Heard? | Audible radius |
|---|---|---|---|
| Idle / still | 0.06 | **no** | — |
| Crouch-walk | 0.15 | **no**, unless inside 1.6 m | 1.6 m (quiet tier) |
| Walk | 0.5 | yes | 8 m |
| Sprint | 1.0 | yes | 16 m |
| Gunshot | event | yes | 40 m (`gunshot_hear_range`, already range-gated before this change) |

Sight is independent of all this: `CondSeesPlayer` → chase works at any noise
level, including while crouched — that is your "can't hear me but sees me and
chases". Hearing alone leads to *investigate* (`ActSetAlert` → `ActInvestigate`),
never straight to a chase, so a heard crouch-rustle sends it to look, not to kill.

**Balance note (intentional):** crouch-walking used to be faintly audible inside
~2.4 m. It is now silent beyond 1.6 m. Some tension that came from "crouch isn't
free" must now come from sight lines — worth a playtest pass on encounter spacing.
Set `hear_noise_floor = 0.05` to restore the old single-tier behaviour exactly.

---

## 4. Tuning reference (nothing hard-coded that you'd need to change)

Everything below is inspector-editable, per-instance.

**NoiseMeter (`scenes/ui/noise_meter.gd`)**

| Group | Export | Default | Notes |
|---|---|---|---|
| Value | `noise_level` | live | 0–1; also settable for tests/cutscenes |
| Value | `idle/crouch/walk/run_noise` | .06/.15/.5/1 | preview bands when no player bound |
| Value | `rise_speed` / `fall_speed` | 10 / 4 | smoothing rates |
| Value | `gunshot_spike` | **0.85** | your decision: 85%, not pinned to 100% |
| Value | `landing_spike_scale` | 0.6 | × `hard_landed` energy |
| Value | `wall_hit_spike_scale` | 0.25 | × impact strength |
| Value | `spike_decay_rate` | 3.0 | spike relaxation |
| Look | `track_color`, `border_color`, `border_width` | dark grays | |
| Look | `corner_radius` | 4 | rounded track + pill fill |
| Look | `fill_padding` | 2 | fill inset inside the frame |
| Look | `fill_color_low/mid/high` | off-white / pale orange / red | gradient stops |
| Look | `red_threshold` | 0.7 | where red takes over |
| Look | `tick_count/color/width` | 5 | decorative scale marks |
| Shake | `shake_threshold` | 0.65 | jitter onset |
| Shake | `shake_magnitude` | 2.5 px | peak jitter |
| Shake | `shake_frequency` | 28 | jitter rate |
| Shake | `shake_curve_power` | 2 | onset curve (higher = gentler start) |
| Shake | `shake_seed` | 20260912 | noise pattern |
| Shake | `shake_cutoff_px` | 0.05 | below this, offset disabled |
| Shader | `shader_influence` | **1.0** | exact linear mix weight; 0.4 = the spec's subtle read, 0.0 = clean UI |
| Visibility | `menu_open` | false | driven by inventory; settable for tests |
| Visibility | `fade_in_speed` / `fade_out_speed` | 10 / 14 | ≈0.25 s in, ≈0.2 s out |
| Visibility | `slide_offset` | 16 px | hide-slide distance |
| Visibility | `show_ease_power` | 3 | ease-out on show |

**BleedOverlay shader uniforms** (on the `ShaderMaterial` in `noise_meter.tscn`,
grouped in the inspector). Defaults below are the calibrated set — at
`influence = 0.4` they measured a mean pixel delta of ~0.04 against the clean bar
and read clearly as grain/bleed/grade without hurting legibility:

| Group | Uniform | Default | Notes |
|---|---|---|---|
| Blend | `influence` | **1.0** | driven by the widget each frame from `shader_influence` — do not hand-edit |
| VHS | `vhs_wiggle` | **0.0** | 0 = colour bleed only. Set ~0.03 (the VHS node's value) to give the meter the world's tracking wiggle too |
| VHS | `vhs_wiggle_speed` | 25.0 | matches `vhs_wiggle.gdshader` |
| VHS | `vhs_smear` | 1.0 | chroma smear radius scale, matches the VHS node |
| VHS | `vhs_blur_samples` | 15 | matches the VHS node; lower for perf, costs smear quality |
| Grain | `grain_amount` / `grain_speed` / `grain_scale` | 0.14 / 17 / 1.6 | animated film grain |
| Grade | `grade_tint` / `grade_amount` | cold tint / 0.35 | colour grading pull |
| Vignette | `vignette_amount` / `vignette_softness` | 0.45 / 1.4 | edge darkening across the widget only |
| Scanline | `scanline_amount` / `scanline_density` | 0.16 / 140 | CRT banding |

Why the extra cues exist at all: on a *flat* fill the VHS colour pipeline is close
to the identity transform — its personality lives in displacement (wiggle) and in
smearing *edges*. Grain/grade/vignette/scanline are what make the treatment
perceptible on a uniform bar. If you enable `vhs_wiggle`, you can dial the cues
back down.

**Creature (`nightmare_creature.gd`, AI group)**: `hear_radius`, `hear_noise_floor`,
`crouch_hear_range`, `gunshot_hear_range`, plus the pre-existing
`sight_range` / `sight_fov_deg` / `confirm_time` / `proximity_range`.

---

## 5. Verification

```bash
# 47 checks: hearing tiers (real creature + real player + real input injection)
# and widget behaviour (gradient, asymmetry, spikes, shake ramp, fades, dial).
godot --headless --path . --fixed-fps 60 --quit-after 8000 \
	  -s res://tests/noise_meter_selftest.gd        # → PASS, 0 failed

# project's own AI regression suite, unmodified: 0 failures
godot --headless --path . --fixed-fps 60 --quit-after 7800 \
      -s res://tests/ai_selftest.gd

# art review strips (needs a framebuffer)
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --fixed-fps 60 \
      --quit-after 200 -s res://tests/meter_capture.gd
```

Shader-treatment visibility is measured, not eyeballed: `influence` 0 vs 0.4
vs 1.0 framebuffer captures of the bar rect (mean pixel delta ~0.04 at 0.4,
~0.10 at 1.0; `shots/vis_compare.png` shows clean / 0.4 / 1.0 stacked). The
shipped default is 1.0 — `shots/theirs_vs_default.png` compares the art-direction
reference crop against the out-of-the-box render and they match.
Reference renders live in the workspace root's `shots/` (kept out of the repo:
they are dev captures, not game assets). `contact_sheet.png` is the gradient
sweep at 0 / 0.15 / 0.5 / 0.72 / 0.9 / 1.0; the 0.72 strip is visibly
shake-offset, which is the internal jitter doing its job.
A framebuffer probe confirmed the overlay truly samples the bar: at noise 1.0 the
centre pixel of the rendered frame is the graded red-orange mix, not raw red.

---

## 6. Gotchas baked into the code (read before refactoring)

1. **Why the art is on `Bar`, not on the parent.** Shake and slide are applied via
   `Bar.offset_transform_*`; anything drawn by the *parent* would not follow that
   offset. `BleedOverlay` is a child of `Bar` for the same reason.
2. **Why `Bar` has no `class_name`.** Naming both halves creates a circular
   `class_name` dependency GDScript refuses to parse. The bar calls back into the
   meter duck-typed (`owner_meter.call(...)`), matching the project's existing
   `float(x.get("noise_level"))` habit in `tests/fly_selftest.gd`.
3. **Why the test loads the scene with `load()`, not `preload()`.** `preload()`
   compiles `noise_meter.gd` while the test script is parsed — before autoloads
   exist — so the `Events` identifier inside it fails to resolve.
4. **Why the test injects real key events.** `player_movement.gd` recomputes
   `noise_level` from `input_active`/`planar_speed`/`is_crouched`/`is_sprinting` at
   the end of *every* physics frame, so any value poked from outside is clobbered
   before the creature reads it. The test presses real W/Shift keys via
   `Input.parse_input_event` and uses `external_crouch` (authoritative, not
   input-latched).
5. **Hearing probes must avoid `proximity_range` (2.5 m).** Inside it the
   point-blank vision path fires regardless of hearing, so a hearing check placed
   there measures the wrong sense.
6. **`pow(negative, 3)` is undefined in GLSL — do not "fix" the safe cube back to
   `pow()`.** `vhs_wiggle.gdshader` ends with `- pow(s + e*2.0, 3.0)`; with
   `vhs_wiggle = 0` the `s` term goes slightly negative every 3 s cycle, some
   drivers return NaN, and `mix(clean, NaN, influence)` is NaN *even at influence
   0* — the whole overlay collapses to black (reproduced on llvmpipe). The port
   uses `x*x*x` instead. The original shader keeps its `pow()` because real-world
   drivers happen to tolerate it; leave each as is.

---

## 7. Future work (deliberately not built yet)

1. **Landing/impact audibility.** Today a hard landing spikes the *meter only*;
   the creature does not hear it. Hook: `CreatureAwareness` subscribes to
   `Events.hard_landed(energy)` and applies a temporary noise boost in
   `_hearing_check()`. No meter involvement needed.
2. **Noisy objects (doors, glass, machinery).** `heavy_door.gd` currently emits
   nothing (its header says the camera nudge is deliberately "no noise"). When you
   want it: emit a spike via `meter.add_noise_spike(amount)`, or better add an
   `Events.noise_made(position, amount)` signal the meter *and* the creature
   subscribe to, so gameplay and HUD agree.
3. **More menus hiding the meter.** Today only the inventory (`Events.inventory_toggled`);
   the debug panel deliberately does **not** (it sets `Events.ui_wants_mouse`, so
   keying off that flag would wrongly hide on F2). When pause/map/journal/crafting
   exist, add a generalized `Events.menu_state_changed(is_open)` emitted by every
   menu and connect it in `_set_menu_open()` — nothing else changes. The counter
   already handles overlapping menus.
4. **Flat audible range option.** Range currently scales with loudness
   (`hear_radius * noise`). If you ever want "audible or not within R", drop the
   `* noise` factor in `_hearing_check()` — one line.
5. **Textured HUD look.** The meter is fully procedural (no image assets), which
   is why it scales and re-skins from the inspector alone. If you later want a
   worn-tape texture on the track, add a `Texture2D` export and draw it in
   `noise_meter_bar.gd`.
6. **Gunshot wake vs. range.** `_on_gun_fired` wakes a dormant creature anywhere
   inside `gunshot_hear_range` (40 m). If distant shots should only *alert* an
   awake creature and never wake a sleeping one, gate `_wake()` on distance.

---

## 8. Online GUI resources (CC0 / permissive), for future HUD work

The meter itself needs no downloaded assets, but when you build the rest of the
HUD these match the project's existing credit discipline (`README/CREDITS.md`
already lists Freesound/Poly Haven/OpenGameArt CC0 sources):

- **Kenney UI Pack** — 400+ interface sprites, 5 colourways, CC0 1.0.
  https://kenney.nl/assets/ui-pack (also https://kenney-assets.itch.io/ui-pack)
  Good for menu panels/buttons/slot frames if the inventory ever gets a reskin.
- **OpenGameArt CC0 texture collections** — including a horror-themed pack of
  ~300 textures, useful for worn panel/backdrop art behind HUD elements.
  https://opengameart.org/content/horror-texture-pack and
  https://opengameart.org/content/cc0-textures-0
- **Fonts:** the project already ships Special Elite (Apache-2.0) for typewriter
  text; keep it for any meter label you add rather than introducing a second face.

If you download anything, follow the repo convention: drop it under
`assets/textures/` (or `assets/fonts/`) and add a row to `README/CREDITS.md`
with author + source + licence.


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
