extends Node3D
class_name BloodBurst
## ============================================================================
## BLOOD BURST (R30) — the physical half of the gore.
##
##   burst(pos, dir, power)  one-shot GPU-particle spray + a splatter decal on
##                           whatever surface the blow was travelling toward
##   pool_under(pos)         starts the floor pool under the body
##   grow_pool(k)            the pool creeps outward during SETTLE
##
## Everything is built in CODE (particle material, decals, draw passes) because
## a ParticleProcessMaterial serialised into a .tscn is a wall of 40 properties
## that nobody edits, while these five numbers are the whole look.
##
## Gore dial: Settings.gore scales the particle count, decal darkness and pool
## size. 0.0 skips the whole node — no particles, no decals, no raycasts.
## ============================================================================

const DOT_TEX := preload("res://assets/textures/blood_dot.png")
const SPLAT_TEX := preload("res://assets/textures/blood_splat.png")
const POOL_TEX := preload("res://assets/textures/blood_pool.png")

@export_group("Spray")
@export var particle_count: int = 110
@export var spray_speed: float = 3.4
@export var spray_spread_deg: float = 38.0
@export var spray_lifetime: float = 0.85
@export_range(0.0, 4.0) var gravity_scale: float = 2.2
## Trails live on the EMITTER in Godot 4 (Godot 3 had SpatialMaterial.particle_trails,
## which now only emits a "remapped parameter not found" warning and does nothing).
## Off by default: ribbon trails on 110 droplets read as smeary at PSX resolution.
@export var spray_trails: bool = false
@export_range(0.05, 2.0) var spray_trail_lifetime: float = 0.22

@export_group("Decals")
@export var splat_size: float = 1.1
@export var pool_radius: float = 1.5
@export var pool_grow_time: float = 2.2

var _spray: GPUParticles3D = null
var _splat: Decal = null
var _pool: Decal = null
var _pool_target: float = 0.0
var _pool_k: float = 0.0
var _pool_started: bool = false


func _ready() -> void:
	_build_spray()
	_build_splat()
	_build_pool()


func _build_spray() -> void:
	_spray = GPUParticles3D.new()
	_spray.name = "Spray"
	add_child(_spray)
	_spray.amount = particle_count
	_spray.lifetime = spray_lifetime
	_spray.one_shot = true
	_spray.explosiveness = 1.0
	_spray.emitting = false
	_spray.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 5, 8))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = spray_spread_deg
	pm.initial_velocity_min = spray_speed * 0.55
	pm.initial_velocity_max = spray_speed
	pm.gravity = Vector3(0, -9.81 * gravity_scale, 0)
	pm.damping_min = 0.6
	pm.damping_max = 2.4
	pm.scale_min = 0.02
	pm.scale_max = 0.055
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_texture = DOT_TEX
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_spray.process_material = pm
	_spray.trail_enabled = spray_trails
	_spray.trail_lifetime = spray_trail_lifetime
	_spray.draw_passes = 1
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = dm
	_spray.draw_pass_1 = quad


func _build_splat() -> void:
	_splat = Decal.new()
	_splat.name = "Splat"
	add_child(_splat)
	_splat.visible = false
	_splat.texture_albedo = SPLAT_TEX
	_splat.size = Vector3(splat_size, splat_size, splat_size)
	_splat.modulate = Color(1, 1, 1, 0.9)


func _build_pool() -> void:
	_pool = Decal.new()
	_pool.name = "Pool"
	add_child(_pool)
	_pool.visible = false
	_pool.texture_albedo = POOL_TEX
	_pool.modulate = Color(1, 1, 1, 0.85)
	_pool.size = Vector3(0.01, 0.02, 0.01)


## The blow lands: spray + a splatter on the surface the hit was heading for.
func burst(world_pos: Vector3, hit_dir: Vector3, power: float = 1.0) -> void:
	var gore: float = Settings.gore
	if gore <= 0.001:
		return
	_spray.emitting = false
	_spray.amount = maxi(8, int(round(float(particle_count) * gore * power)))
	# Spray away from the blow: blood leaves the wound opposite the fist.
	var away: Vector3 = -hit_dir
	if away.length_squared() < 0.0001:
		away = Vector3(0, 1, 0)
	away = away.normalized()
	var pm := _spray.process_material as ParticleProcessMaterial
	pm.direction = away * Vector3(1.0, 0.35, 1.0) + Vector3(0, 0.7, 0)
	pm.direction = pm.direction.normalized()
	_spray.global_transform = Transform3D(Basis(), world_pos)
	_spray.restart()
	_spray.emitting = true
	_place_splat(world_pos, hit_dir, power, gore)


## Splatter decal on the first solid thing along the blow's travel direction.
func _place_splat(world_pos: Vector3, hit_dir: Vector3, power: float, gore: float) -> void:
	var space := get_world_3d()
	if space == null:
		return
	var from: Vector3 = world_pos - hit_dir.normalized() * 0.35
	var to: Vector3 = world_pos + hit_dir.normalized() * 2.2
	var res: PhysicsDirectSpaceState3D = space.direct_space_state
	if res == null:
		return
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 0xFFFFFFFF
	q.exclude = []
	var hit: Dictionary = res.intersect_ray(q)
	var normal: Vector3 = Vector3(0, 1, 0)
	var point: Vector3 = world_pos
	if not hit.is_empty():
		normal = Vector3(hit["normal"])
		point = Vector3(hit["position"]) - normal * 0.02
	else:
		# Nothing in front (open corridor): stain the floor instead.
		normal = Vector3(0, 1, 0)
		point = Vector3(world_pos.x, world_pos.y - 1.4, world_pos.z)
	var up: Vector3 = Vector3(0, 0, 1) if absf(normal.y) > 0.9 else Vector3(0, 1, 0)
	var basis := Basis().looking_at(-normal, up)
	# Decals project along -Y; rotate the random spin into the surface plane.
	var spin := Basis(normal, randf_range(0.0, TAU))
	_splat.global_transform = Transform3D(spin * basis, point)
	var s: float = splat_size * (0.7 + 0.6 * power) * (0.6 + 0.4 * gore)
	_splat.size = Vector3(s, s, s)
	_splat.modulate.a = 0.9 * gore
	_splat.visible = true


## Start the pool under the body (called on CRASH).
func pool_under(world_pos: Vector3) -> void:
	if Settings.gore <= 0.001:
		return
	_pool.global_transform = Transform3D(Basis(), Vector3(world_pos.x, world_pos.y + 0.02, world_pos.z))
	_pool_target = pool_radius * (0.6 + 0.4 * Settings.gore)
	_pool_k = 0.0
	_pool_started = true
	_pool.visible = true


## Creep the pool outward (director drives it through SETTLE).
func grow_pool(delta: float) -> void:
	if not _pool_started or not _pool.visible:
		return
	_pool_k = minf(1.0, _pool_k + delta / maxf(pool_grow_time, 0.05))
	var e: float = 1.0 - pow(1.0 - _pool_k, 2.0)   # ease-out creep
	var s: float = maxf(0.05, _pool_target * e)
	_pool.size = Vector3(s, 0.02, s)
