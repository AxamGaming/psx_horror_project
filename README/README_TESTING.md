# Phase 0–2 Delivery — Foundation Bundle

**Contents:** project setup + input map, `Events` autoload, first-person movement, mouse look, graybox test level.
**Deliverable for:** Godot **4.7.x** (4.7.2 recommended), Linux, Forward+.

---

## How to run

1. Copy the whole `psx_horror_project/` folder somewhere permanent (e.g. `~/dev/`).
2. `git init && git add -A && git commit -m "phase 0-2: movement + mouse look foundation"` (Rule 5: commit every working phase).
3. Open Godot 4.7 → **Import** → select `psx_horror_project/project.godot` → Edit.
4. First open: Godot scans and may print *harmless* notices that it generated `.uid` files for the scripts — that's normal for 4.4+ projects, just let it save them and commit again.
5. Press **F5** — the main scene (`test_graybox.tscn`) is already set.

## Controls

| Action | Key |
|---|---|
| Move | W A S D |
| Sprint (forward) | Shift (hold) |
| Crouch | C or Ctrl (hold) |
| Jump (test aid only) | Space |
| Free mouse / recapture | Esc / click |
| Interact, Inventory, Flashlight, Aim | E, Tab/I, F, RMB — *mapped now, wired in later phases* |

## ✅ Phase acceptance test (run through this, then report back)

**Phase 0 — Project:**
- [ ] Project imports with no red errors in the Output panel (warnings about `.uid` generation are fine).
- [ ] Input Map (Project Settings → Input Map) shows all 11 actions.

**Phase 1 — Movement:**
- [ ] Walk feels weighty but responsive; stopping is quick, not slidey.
- [ ] Sprint only engages while holding Shift **and** pushing forward.
- [ ] Crouch smoothly lowers the eye height; standing back up is smooth.
- [ ] Crouch under the stacked crates… then jump so the crate would block you: the player must **not** stand up through geometry (walk into the gap under Crate2 while crouched, release C — should stay crouched).
- [ ] Walk up the ramp onto the green platform, jump off the edge — clean landing, no jitter, no console errors.
- [ ] No jitter when standing perfectly still on the floor and on the ramp.

**Phase 2 — Mouse look:**
- [ ] Aiming is pixel-precise; no drift when not moving the mouse.
- [ ] Pitch clamps at ±88° (look straight up/down — never flips).
- [ ] **Zero roll at all times** (horizon line of the walls stays level).
- [ ] Esc releases the mouse, click recaptures it.

## Tuning knobs (Inspector → Player node)

- Movement: speeds, accel/decel, gravity, air control, crouch rate.
- HeadPivot: mouse sensitivity, invert Y.

Try `gravity = 24` for an even heavier horror feel, or `sensitivity = 0.08` if 0.12 feels too fast.

## What's deliberately NOT here yet

- No head bob, no spring, no PSX viewport, no audio — those are **Phases 3–5**, delivered after this passes. The `Events.hard_landed` signal already fires on hard landings (nothing listens yet; that's Phase 4's camera spring).

## Report back format

Just paste anything from the Output/bottom panel that isn't a warning, plus which checklist items felt wrong ("slidey stop", "crouch pops", etc.). Then I generate Phase 3–4 (bob engine + spring/landing + FOV shift + heel-strike signal).
