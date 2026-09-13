extends Node
## ============================================================================
## NAV BAKER — Round 14. Own navigation map, exact cell match, connectivity probe.
##
## History of the bake, because it has now failed three different ways:
##   R7  SOURCE_GEOMETRY_ROOT_NODE does not exist in 4.7 -> parse error.
##   R7-R9  cell 0.15 mesh on the default 0.25 map -> rasterization mismatch.
##   R10-R13  cell 0.25 to match the map, but the bake CEILS agent_height and
##            agent_radius to voxel units. 1.8/0.25 -> 8 voxels = 2.0 m of required
##            headroom, and Door2's lintel underside sits at exactly y=2.0, so
##            EVERY doorway was filtered as low-hanging: the rooms became
##            disconnected islands. creature_log R13 shows it plainly -- 158/158
##            diag lines `navs=2 snapped=1`, waypoint frozen at the threshold
##            (wp=(0.3,-6.7)) no matter where the target was.
##
## R14 creates a DEDICATED map with cell_size 0.15 / cell_height 0.2, identical to
## the mesh, so nothing is mismatched and the ceils land safely: agent_height
## 1.8/0.2 = 9 voxels exactly = 1.8 m, and the lintel at y=2.0 clears it; radius
## 0.4/0.15 -> 3 voxels = 0.45 m erosion, leaving 0.9 m = 6 voxels of doorway.
## Connected.
##
## And after every bake it prints NAVPROBE: two real path queries across the
## doorways. If the mesh is ever disconnected again, the log says so in one line
## with point counts, instead of us inferring it from frozen waypoints.
## ============================================================================

const NAV_GROUP := &"nav_src_r9"
const CELL := 0.15
const CELL_H := 0.2

var _region: NavigationRegion3D
var _map: RID = RID()
var _rebake_t: float = 0.0
var _dirty: bool = false
var _bakes: int = 0
var _retries: int = 0
var _polys: int = 0


func _ready() -> void:
	add_to_group("nav_baker")
	# Dedicated map: same cell size as the mesh, so the bake neither ceils the
	# agent radius nor fights a mismatched voxel grid.
	_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(_map, CELL)
	NavigationServer3D.map_set_cell_height(_map, CELL_H)
	NavigationServer3D.map_set_active(_map, true)
	_region = NavigationRegion3D.new()
	_region.name = "NavRegion"
	var mesh := NavigationMesh.new()
	mesh.cell_size = CELL
	mesh.cell_height = CELL_H
	# ROUND 15: exact voxel multiples (cell 0.15 / cell_height 0.2) so the bake
	# stops warning "agent_radius is ceiled / agent_max_climb is floored ... loses
	# precision" on every single bake (your console screenshot): 0.45 = 3 voxels,
	# 1.8 = 9 voxels, 0.2 = 1 voxel. Doorway strip stays 1.8 - 0.9 = 0.9 m.
	mesh.agent_radius = 0.45
	mesh.agent_height = 1.8        # carves out the 1.15 m crawlspace
	# R16: the 0.4 m hall Stage top used to bake as a DISCONNECTED island
	# (climb 0.2 < 0.4): a player on or beside it made every chase target
	# "unreachable", the goal snapped onto the island, the path ended at the
	# Stage foot and the creature body-checked the side forever. 0.6 gives the
	# voxel conversion real margin (0.4/0.2 truncates to 1-2 voxels depending
	# on float rounding — measured: the Stage stayed disconnected at 0.4,
	# polys 87; at 0.6 it merges, polys 100+ and the probe path shortens).
	# Paths now route OVER the Stage (or cleanly around it), and the
	# creature's step-hop (step_height 0.5, jump anim) can physically follow.
	# Crates (1 m) and barrels (0.93 m) remain obstacles.
	mesh.agent_max_climb = 0.6
	mesh.agent_max_slope = 45.0
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_EXPLICIT
	mesh.geometry_source_group_name = NAV_GROUP
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1     # doors (layer 16) invisible to the bake
	var tagged: int = _tag_static(get_parent())
	_region.navigation_mesh = mesh
	add_child(_region)
	_region.set_navigation_map(_map)
	_region.bake_finished.connect(_on_bake_finished)
	# ROUND 10: do NOT bake in _ready; the first bake raced the level entering
	# the tree and produced zero bounds. Defer through the debounce below.
	_dirty = true
	_rebake_t = 0.75
	print("NAVBAKE start tagged_static_bodies=%d map=own cell=%.2f (deferred 0.75s)"
			% [tagged, CELL])
	for door in get_tree().get_nodes_in_group("heavy_door"):
		if door.has_signal("state_changed"):
			door.connect("state_changed", _on_door_changed)


## Creatures call this to put their NavigationAgent3D on our map.
func get_map_rid() -> RID:
	return _map


## ROUND 15: true once a bake has produced geometry. The creature gates its
## nav-failure ladder on this so the startup window (degenerate first bake +
## retry) can never latch _nav_dead again.
func is_ready() -> bool:
	return _polys > 0


## Tag every static collider under `n` recursively; returns how many.
func _tag_static(n: Node) -> int:
	var count: int = 0
	if n is StaticBody3D:
		n.add_to_group(NAV_GROUP, true)
		count += 1
	for c in n.get_children():
		count += _tag_static(c)
	return count


func _on_bake_finished() -> void:
	_bakes += 1
	var m: NavigationMesh = _region.navigation_mesh
	var polys: int = m.get_polygon_count() if m != null else 0
	_polys = polys
	var bounds: AABB = _region.get_bounds()
	print("NAVBAKE #%d polys=%d bounds=%s" % [_bakes, polys, str(bounds)])
	if (polys == 0 or bounds.size.length_squared() < 0.001) and _retries < 2:
		_retries += 1
		_dirty = true
		_rebake_t = 0.5
		print("NAVBAKE #%d DEGENERATE -- retrying (%d/2)" % [_bakes, _retries])
		return
	if polys == 0:
		print("NAVBAKE #%d EMPTY -- check geometry_collision_mask / group tagging" % _bakes)
		return
	_probe()


## ROUND 14: prove the rooms are connected, every bake, in one line.
func _probe() -> void:
	var hall := Vector3(0.0, 0.0, -14.0)
	var corridor := Vector3(0.0, 0.0, -3.0)
	var spawn := Vector3(0.0, 0.0, 4.0)
	var p1: PackedVector3Array = NavigationServer3D.map_get_path(_map, hall, corridor, true)
	var p2: PackedVector3Array = NavigationServer3D.map_get_path(_map, corridor, spawn, true)
	print("NAVPROBE hall->corridor pts=%d corridor->spawn pts=%d" % [p1.size(), p2.size()])
	if p1.is_empty():
		print("NAVPROBE FAIL: Hall and Corridor are disconnected in the mesh")


## R23: rebaking when a door swings is PURE COST. Doors are invisible to the
## bake twice over — they are not in NAV_GROUP (SOURCE_GEOMETRY_GROUPS_EXPLICIT)
## and geometry_collision_mask = 1 excludes their layer 16 — so a rebake after a
## door change produces a byte-identical mesh while freezing the main thread
## (creature_log: NAVBAKE #3 lands exactly when the creature force-opens a door
## mid-chase; measured: the in-game rebake stalls for seconds, and under
## contention far longer). Kept as an export in case a future level ever puts
## doors INTO the bake groups/mask — then flip this on.
@export var rebake_on_door_change: bool = false


func _on_door_changed(_open: bool) -> void:
	if not rebake_on_door_change:
		return
	_dirty = true
	_rebake_t = 0.5                # debounce: let the 1.6 s swing finish first


func _process(delta: float) -> void:
	if not _dirty:
		return
	_rebake_t -= delta
	if _rebake_t > 0.0:
		return
	_dirty = false
	if _region != null and not _region.is_baking():
		# R23: create_uv_map=false. The second UV array is editor/debug-only;
		# runtime pathfinding never reads it, and building it is a large share
		# of bake cost. Both call sites pass false now.
		_region.bake_navigation_mesh(false)
