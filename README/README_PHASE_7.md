# Phase 7 Delivery — Impact System Polish (damage pipeline end-to-end)

## Files to copy

| File | Action |
|---|---|
| `scenes/player/camera_rig.gd` | **REPLACE** — damage entry point, daze state, directional debug hits |
| `scenes/ui/debug_panel.gd` | **REPLACE** — inventory-UI jolt on damage |
| `project.godot` | **REPLACE** — 4 new actions: arrow keys = directional hits |

Commit: `git commit -m "phase 7: damage pipeline, daze, UI jolt"`.

## The architecture change that matters

Debug hits no longer call the rig directly. **Every test hit emits `Events.player_damaged(amount, direction)`** — the exact signal real enemies/traps/debris will emit later. The rig subscribes and converts (`amount * damage_impulse_scale` → impulse), the panel subscribes for its jolt. One signal, three subscribers, zero direct coupling. When a monster exists, it just emits — everything below already works.

## New controls

| Key | Effect |
|---|---|
| **← / → / ↑ / ↓** | Hit from LEFT / RIGHT / FRONT / BACK (25 damage each) |
| **H** | Random-direction hit, 15–35 damage (sometimes under daze threshold — watch the difference) |

## Behaviors (design doc → implementation)

- **Directional traumatic displacement**: hit from the right → camera snaps LEFT and rolls counter-clockwise (and mirrored); front hit snaps the head backward; back hit pitches it forward. FOV punch + noise suppression blend-back included, as before.
- **Daze / "limp and recovery" physics**: damage ≥ `daze_threshold` (25 hits it) triggers 2.5 s of dazed state — spring **mass ×1.5** and bob depth ×1.5, smoothed in and out (watch `daze` countdown + `mass` climb in the F3 overlay). The character feels concussed: heavier, slower to recover, then gradually back to normal.
- **Inventory jolt ("breached safe space")**: take a hit while the F2 panel is open → the panel **shudders** for 0.35 s via Godot 4.7's `offset_transform_*` (position jitter + micro-rotation, decaying). Purely visual: layout, sliders, and hover are never touched — that's the whole point of the 4.7 API. The world behind jolts independently via the spring.
- Small hits (H rolls 15–19) knock but do **not** daze — threshold behavior you can feel.

## ✅ Acceptance test

- [ ] ← → ↑ ↓ each produce a knock from the correct side (right hit = snap left + CCW roll).
- [ ] After a 25-dmg hit: overlay `daze` counts 2.5→0, `mass` swells ~×1.5, bob feels concussed, then smoothly recovers.
- [ ] H sometimes dazes (≥20), sometimes doesn't (<20) — both feel distinct.
- [ ] F2 open + any hit: panel visibly shudders ~0.35 s and settles back exactly in place; sliders still draggable afterward.
- [ ] Walking/sprinting/limp/focus modes/VHS/snap: unchanged.
- [ ] No red errors.

## Knobs (MainCamera → "Impacts Phase 7")

`damage_impulse_scale` 0.2 (HP→impulse), `debug_hit_amount` 25, `daze_threshold` 20, `daze_duration` 2.5, `daze_mass_mult` 1.5.

## Next

Pass → **Phase 8: audio** — bus layout (Master/SFX/Reverb/Ambient), heel-strike-synced footsteps with weight pitch-shift, 6-ray reverb probe, impact deafness (low-pass slam + tinnitus), flashlight hum on the lag rig. The `heel_strike(strength, foot)` signal has been firing sample-accurately since v2, waiting for this.
