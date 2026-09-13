# R23 — Mid-chase nav rebake hitch (the "huge lag at the hallway wall")

## Symptom

Multi-second freeze whenever the creature, mid-chase, slams into the hallway
doorway (reads as a "wall" while closed). `creature_log` pins it exactly:

```
59317 | STEERDBG ... onwall=true ...      ← pinned at the doorway (z ≈ -6.9)
60536 | UNSTICK fail=1 ...
60598 | MSG | NAVBAKE #3 polys=231 ...     ← the freeze: a full navmesh rebake, mid-chase
60598 | MSG | NAVPROBE hall->corridor ...
```

## Cause chain

1. Creature pins against the closed door; the navigator's unstick ladder calls
   `heavy_door.force_open()` (`creature_navigator.gd`).
2. Door swings 1.6 s, then `state_changed.emit(true)` (`heavy_door.gd:_on_swing_done`).
3. `nav_baker._on_door_changed()` sets `_dirty = true`, 0.5 s debounce.
4. `_region.bake_navigation_mesh(true)` runs **in the middle of gameplay** — source
   geometry parse on the main thread, server bake, mesh swap. That is the freeze.

## Why the rebake was pure cost

Doors are invisible to the bake **twice over**:

- `mesh.geometry_source_geometry_mode = SOURCE_GEOMETRY_GROUPS_EXPLICIT` — only
  nodes in `NAV_GROUP` are parsed; doors are not in it.
- `mesh.geometry_collision_mask = 1` — doors live on layer 16, filtered out even
  if they were tagged.

So a post-door rebake produces a **byte-identical mesh** (the log agrees: #3 has the
same polys/bounds as #2) while costing a main-thread stall. The `true` argument
(`create_uv_map`) added editor-only UV unwrapping on top, for nothing: runtime
pathfinding never reads navmesh UVs.

## Fix (`scenes/level/nav_baker.gd`)

- New `@export var rebake_on_door_change: bool = false`. The door handler no-ops
  unless a future level genuinely bakes doors into the mesh (then flip it on — and
  solve the hitch separately, e.g. pre-baked open/closed mesh variants).
- Remaining (boot) bakes call `bake_navigation_mesh(false)` — no UV map.

## Verification

- Bench (headless, corridor level): fire the exact door signal → **0 bakes
  started**, `is_baking()` false, 121-frame window worst **1 ms**, avg 0.33 ms.
- Boot unchanged: NAVBAKE #1/#2 + NAVPROBE connectivity proof still run.
- `ai_selftest.gd`: door force-open (P4a), doorway pass (P4b), corridor search (P5)
  all pass without the rebake — navigation never depended on it.
- `noise_meter_selftest.gd` 47/47, boot smoke test pass.

## Pre-existing flake, NOT caused by this fix

`P5` (stall < 3 s) and `P11` (pinned < 4 s) are seed-sensitive: 4 runs per behaviour
showed the same failure rate and stall spread with the rebake **on** (3 pass /
1 fail, stalls 1.6–4.4 s) and **off** (3 pass / 1 fail, stalls 1.6–2.5 s plus one
no-cross run). The rebake was never shortening stalls; chase RNG (lunge knockback,
prowl direction) is. If a red P5/P11 shows up, rerun once before bisecting.
