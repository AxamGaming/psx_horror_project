# R24 — Prop trimesh collision lag ("the whole game lags near that wall")

## Symptom

Sustained frame drops (not a one-off freeze — that was R23) whenever the creature
fights near the hallway spot around `(-0.3, 0, -2.2)`. Distinct from R23: no
`NAVBAKE` line at the lag moment, and the lag persists for as long as the creature
works that area.

## How it was measured (two tools, both kept)

1. **The creature log is a wall-clock trace.** `_log()` stamps
   `Time.get_ticks_msec()`, and the `state ...` line is throttled at 1 Hz of
   *sim* time — so the wall-clock gap between consecutive `state` lines is an FPS
   graph: ~1000 ms = healthy, 2000+ ms = the game is dropping frames. The gaps
   clustered exactly while the creature sat at `(±0.4, 0, -1.9…-3.1)`.
2. **`tests/lag_probe.gd`** (new, kept): headless A/B — teleport-hold the creature
   at a spot, measure per-frame CPU ms (rendering excluded).
   - `hold_zone` (-0.3,0,-2.2): **8.1 ms/frame avg**
   - `hold_far` / `hold_onmesh_near` / `hold_onmesh_far`: 0.6-0.7 ms
   Deletion bisect inside the probe: cost vanished only with the creature's
   `_physics_process` frozen, survived dormancy (no BT/nav/awareness), survived
   removing doors/model/nav/awareness — and vanished when **PropBarrel1/2 were
   deleted**. Physics-server pair counts were identical between spots, which is
   why broadphase monitors never pointed at it.

## Root cause

`PropStatic.auto_collide` calls `MeshInstance3D.create_trimesh_collision()` for any
prop without a `CollisionShape3D` child. The barrel (375 tris) therefore got a
**ConcavePolygonShape3D**. The creature carries a capsule **plus eight bone-hull
sphere shapes**; whenever that 9-shape cluster's AABB came near the barrel's
trimesh, narrowphase ran triangle-level queries for all nine shapes **every physics
frame** — ~8 ms of pure contact solving, on the main thread, for as long as the
chase kept the creature beside the barrel. Position-dependence was razor-thin
(2 m away: clean), which is why it felt like "that wall".

## Fix

- `scenes/props/prop_barrel.tscn`: explicit `CylinderShape3D` child
  (radius 0.33, height 0.94, **position (0, 0.465, 0)** — the mesh AABB centre in
  body space; the mesh sits ON the body origin, not centred on it). Per the
  PropStatic contract, a CollisionShape child skips trimesh generation entirely.
  Getting that offset wrong sinks the collider half into the floor and leaves an
  invisible stump in the chase corridor — `ai_selftest` P5/L2 catch it.
- `scenes/props/prop_static.gd`: new `trimesh_warn_tris` export (default 200).
  Any prop that still auto-generates a trimesh above that prints a warning at
  boot, so the next trap is loud instead of silent.

## Verification

- `lag_probe.gd`: hold_zone 8.1 ms → **0.6 ms** (same as every other spot).
- `ai_selftest.gd`: passes on clean seeds (P4a/P4b/P5 door & corridor behaviour
  unchanged — the cylinder footprint matches the barrel).
- `noise_meter_selftest.gd` 47/47; boot smoke test pass; the only new boot warning
  is the intended `PropMedbox1` trimesh notice (below).

## Known follow-ups (deliberately not changed here)

- **PropMedbox1** now warns at boot: its auto-trimesh is 260 tris of the *latch*
  sub-mesh only (`_find_mesh()` returns the first MeshInstance3D, which for the
  medbox is the latch — so the medbox's collision is a thin sliver, a pre-existing
  quirk). It is cheap (tiny AABB) so it causes no lag; giving the medbox a proper
  BoxShape3D child would make it solid for the first time, which changes hallway
  traversal and needs an `ai_selftest` re-baseline — do it as its own change.
- `ai_selftest` P5/L2 remain seed-flaky at a ~25-40% rate independent of this fix
  (see R23 doc): one attractor fails P5 with `crossed=false frac=0.00` plus L2.
  Rerun once before bisecting any red.
