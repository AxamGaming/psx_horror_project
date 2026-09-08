# Prop Workflow — placing real meshes in your levels

## How the level is built (answering "is it script-generated?")

**No.** Levels are plain editor scenes. Everything you see is a node you can
click, move, and duplicate in the 3D view:

- **Architecture** (walls/floors/ceilings): `StaticBody3D` + shared unit-box
  mesh/shape, sized by the node's *scale* in the transform. Graybox technique —
  swap for real modular kits whenever you want.
- **Props**: instanced prop scenes (`scenes/props/*.tscn`) wrapping imported
  Poly Haven meshes (CC0). Placed/rotated like any node.
- **Code-built visuals only** (by design): pickup crates, muzzle flash, lamp —
  things that must spawn at runtime.

## Adding a new prop (30 seconds)

1. Drop the mesh into `assets/models/<name>/` (`.gltf`/`.glb` + its bin/textures).
   Godot imports it on the next editor scan.
2. Either:
   - **Quick:** in the level scene, `Node3D`-less: add a `StaticBody3D`,
     attach `scenes/props/prop_static.gd`, drag the imported mesh scene in as
     a child. Done — collision + footstep tag come from the script.
   - **Reusable:** save that pair as `scenes/props/prop_<name>.tscn` and
     instance it everywhere (like the barrel/crate/chair already do).
3. Set `surface_tag` on the StaticBody: `wood`, `metal`, … → footsteps on top
   of it use that material's step sounds (the heel-strike ray reads the
   `surface_<tag>` group). Unknown tags fall back to concrete until you add
   a step pool for them in `footsteps.gd`.
4. `auto_collide` (default on) builds trimesh collision from the mesh at
   runtime if you didn't add a CollisionShape yourself. For hero props you
   stand on often, hand-made convex/box shapes are cheaper — add them and the
   script leaves them alone.

## Editing existing placements

Select the instance in the level scene → move/rotate/scale in the 3D view or
the transform fields. Per-instance overrides (like pickup `item_id`) are just
exported properties shown in the inspector.

## Current prop library (all CC0, Poly Haven, credited in CREDITS.md)

| Scene | Mesh | Surface tag |
|---|---|---|
| prop_barrel | barrel_03 | metal |
| prop_crate | old_military_crate | wood |
| prop_cardboard | cardboard_box_01 | wood |
| prop_chair | painted_wooden_chair_01 | wood |
| prop_pipes | modular_industrial_pipes_01 | metal |
| prop_medbox | medical_box | metal |

## Placing PICKUP ITEMS (shotgun, shells, medkit, anything in the DB)

1. In the level scene: instance `scenes/level/pickup_item.tscn` (or Node3D +
   `pickup_item.gd`) and move it where you want — it auto-snaps to the ground.
2. `item_id` = a key from `data/item_database.tres` (add new item types there:
   name, weight, color — the inventory, toasts and weight math follow).
3. `mesh_scene` = **any mesh or prop scene** as its world visual (assign in the
   inspector). Null = default tinted crate. `mesh_offset` /
   `mesh_rotation_deg` / `mesh_scale` position the visual; collision inside
   assigned scenes is auto-disabled so pickups never block the player.
4. Done. E within `take_distance` picks it up; dropping from the inventory
   spawns the same node type at your feet (default crate visual).

Example in corridor_level.tscn: `MedkitPickup` uses the real medical-box mesh;
`ShotgunPickup`/`ShellPickup*` use the default crate until weapon/shell models
are sourced (art pass) — assign them then, zero code changes.

## Notes

- Models are 2k PBR. For the PSX half of our look, the vertex-snap shader
  (Phase: art pass) will land on these materials later; nearest/no-mip import
  presets get applied per-texture at that time.
- Trimesh collision is static-only friendly — never put PropStatic on moving
  things (doors use their own hinge setup).
