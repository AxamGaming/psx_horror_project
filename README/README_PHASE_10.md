# Phase 10 Delivery — Corridor Level + Crisp-Layer Inventory

> **10-FIX (current): UI de-hardcoded per user request.** Inventory and debug panel are now **scene files** (`inventory_ui.tscn`, `debug_panel.tscn`): every visual — PanelContainer, StyleBoxFlat borders/backgrounds, 20 slot Buttons with per-slot StyleBoxes, sliders, OptionButton, fonts, anchors — is an inspector-editable node/resource. Scripts contain **functionality only** (open/close, weight math, refresh, jolt); even signal wiring for Use/Drop/Close/sliders/focus lives in the scenes as `[connection]` entries. Resolution discipline: UI designed at **1280×720**, project stretch set to `canvas_items` + `keep` so the crisp layer scales correctly at any window size/aspect. Re-copy: both `.tscn` (new), both `.gd` (replace), `main.tscn`, `main.gd`, `project.godot`.

## Copy list

| File | Action |
|---|---|
| `scenes/levels/corridor_level.tscn` | **NEW** — the reverb-probe showcase level |
| `scenes/level/pickup_item.gd` | **NEW** — world pickups (shotgun on the hall stage) |
| `scenes/ui/inventory_ui.gd` | **NEW** — crisp grid inventory |
| `scenes/main.tscn` | **REPLACE** — boots the corridor level; InventoryUI on the crisp layer |
| `scenes/main.gd` | **REPLACE** — level-agnostic rig lookup (`find_child`) |
| `autoload/events.gd` | **REPLACE** — `pickup_triggered` signal |
| `scenes/player/camera_rig.gd` | **REPLACE** — damage now reduces real health (25 dmg = −0.25) |

Graybox remains for regression: open `scenes/levels/test_graybox.tscn` and **F6** to run it directly.

## The level (walk it north → south)

1. **Spawn room** (8×8, 3 m ceiling, warm light) — medium reverb: present but tight.
2. **Heavy door 1** (E) → **corridor** (1.8 m wide, 2.2 m ceiling, cold lights) — reverb visibly dries up; footsteps feel close and dead.
3. **Crawl choke** (mid-corridor, 1.15 m ceiling) — forced crouch, reverb at its most choked, muffled little steps.
4. **Heavy door 2** (E) → **the hall** (16×16, 6 m ceiling, fog, pillars, dim cold light) — the doc's "abandoned chapel flood": every step and door creak now has a long hollow tail. **This walk is the reverb probe's demo reel.**
5. **Wood stage** (hall SW): wood footstep takes + the **shotgun pickup** (E within 2.5 m).

## The inventory (Tab)

- 5×4 grid on the **crisp layer** — razor-sharp over the tape-degraded world.
- **Real-time**: world keeps simulating while open (vulnerability by design); gait damps to the INVENTORY focus mode automatically via `Events.inventory_toggled`.
- **Real API callers at last**: total item weight / 10 kg capacity → `set_carry_weight()` (pick up the shotgun mid-walk and feel the bob get heavier *immediately*); Medkit USE → `set_health(+0.5)` (heals the limp from arrow damage); damage while open → `offset_transform` jolt.
- Mouse etiquette handled: opening releases the cursor + sets `ui_wants_mouse` (click-recapture stands down); closing recaptures.
- Starting kit: Medkit + Old Key + Crowbar (2.9 kg → carry 0.29, light on your feet).

## ✅ Test route

- [ ] Spawn → walk the corridor: reverb dries; crawl section forces crouch + chokes further; hall floods with tail. Doors creak positionally at both thresholds.
- [ ] Hall: step on the stage = wood takes; step off = concrete.
- [ ] E at the shotgun crate: item lands in a slot; **walking away feels heavier** (mass smoothing ~0.5 s); weight readout updates.
- [ ] Tab: crisp grid; world still moves behind it; gait dampens while open; close → full gait returns.
- [ ] Arrow-hit yourself ×3 (limp starts), then Tab → USE medkit → limp eases over the next steps.
- [ ] Get hit with inventory open: panel jolts, settles exactly back.
- [ ] F2 debug panel and F3 overlay still fine; VHS + snap unchanged.

## Notes

- Level geometry uses **scaled unit boxes** (one shared mesh + shape) — tiny scene, easy to extend; swap for real art anytime.
- Fog + low ambient are tuned for flashlight exploration: **F** matters in the hall now.
- `pickup_item.gd` is the template for all future item drops (export `item_id`).
