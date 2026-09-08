# Phase 6 Delivery — Gameplay Hooks + Crisp Debug Panel

> **SPEED REALISM PASS (folded in):** walk 3.0 → **2.2 m/s**, sprint 5.2 → **4.5**, crouch 1.4 → **1.0**, accel/decel 12/14 → **10/12** (heavier start/stop). Cadence followed the speed drop so strides stay believable instead of gliding: walk 1.7 → **1.9 steps/s**, sprint 2.4 → **2.6** (≈1.7 m stride = real sprinting), crouch → **1.2**. All exported — fine-tune live on the Player node (Speeds) and MainCamera (Cadence); tell me your final numbers and I'll bake them in.

## Files to copy

| File | Action |
|---|---|
| `scenes/ui/debug_panel.gd` | **NEW** |
| `scenes/player/camera_rig.gd` | **REPLACE** — focus modes, gasping, aim tremble, limp |
| `scenes/player/mouse_look.gd` | **REPLACE** — click-recapture respects `Events.ui_wants_mouse` |
| `autoload/events.gd` | **REPLACE** — adds `ui_wants_mouse` flag |
| `scenes/main.gd` | **REPLACE** — wires rig → panel |
| `scenes/main.tscn` | **REPLACE** — DebugPanel node under UI layer |
| `project.godot` | **REPLACE** — adds `debug_panel` action (**F2**) |

Commit: `git commit -m "phase 6: gameplay hooks + debug panel"`.

## What's live now (design doc → behavior)

- **Carry weight** (slider 0–1): spring mass climbs to ×1.6 and step depth +25% at full load. Walk with the slider at 0 vs 1: the whole body-feel gets slower to dip, slower to recover — the doc's "weight of the backpack."
- **Stamina** (slider, start 1): at low values breathing becomes a **gasping heave** (rate + depth scale up). At ≤0.35 while **AIMING**, hand tremble doubles — the held-breath shiver.
- **Health** (slider, start 1): below 0.35 the gait turns into the doc's **asymmetrical limp** — every second step dips ~60% deeper and drags a roll kick, then slow painful recovery.
- **Focus modes** (dropdown): `EXPLORING` normal · `INVENTORY` gait damps to ×0.2 over ~0.4 s (tense micro-sway while the world stays "alive" behind the menu) · `AIMING` ×0.35 steadying. The rig is also **already connected to `Events.inventory_toggled`** — the real inventory only needs to emit that signal later.
- **Crisp UI proof**: the panel renders on CanvasLayer 10, *above* the VHS layer — razor sharp while the world behind it is tape mush. Exactly the doc's "crisp retro UI over chunky world."

## Mouse etiquette (new, important)

- **F2** opens/closes the panel. Opening **releases the mouse**; closing **recaptures** it.
- While open, `Events.ui_wants_mouse = true` blocks MouseLook's click-to-recapture → you can drag sliders freely. WASD still moves (poll-based) — **walk while dragging carry weight**, that's the best test.
- Clicking the world while the panel is open does NOT recapture (by design). F2 to go back to gameplay.

## ✅ Acceptance test

- [ ] F2 → crisp panel top-right; mouse freed; sliders draggable; F2 again → captured, panel gone.
- [ ] Carry weight 0 → walk: current approved feel. Drag to 1 while walking: bob visibly heavier/slower within ~0.5 s (mass smoothing), deeper dips.
- [ ] Stamina → 0.1 standing still: breathing heave clearly stronger/faster.
- [ ] Health → 0.2 + walk: limp — one step noticeably deeper + tilt, alternating rhythm (check `depth` in the F3 overlay spiking every second step).
- [ ] Focus INVENTORY while walking: gait collapses to a gentle sway (~0.3 s crossfade), breathing still present. Back to EXPLORING: full gait returns smoothly.
- [ ] Focus AIMING + stamina 0.2: visible fine shiver.
- [ ] H impacts, landings, VHS, snap filter: all unchanged.
- [ ] No red errors; panel never appears smeared by VHS.

## Knobs (Inspector → MainCamera → "Gameplay Hooks (Phase 6)")

`focus_gait_mult_inventory` (0.2) / `focus_gait_mult_aiming` (0.35) / `focus_blend_rate` (6) / `breath_gasping_mult` (1.5) / `aim_tremble_mult` (2) / `low_state_threshold` (0.35) / `limp_depth_extra` (0.6) / `limp_roll_kick_deg` (25).

## Next

Pass → **Phase 7: impact system polish** — directional `apply_impulse` callers (test-hit from 4 named directions instead of random), limp-recovery temp physics after heavy hits, UI jolt on the inventory via 4.7's `offset_transform_*`, and wiring `Events.player_damaged` end-to-end.
