extends CharacterBody3D
class_name NightmareCreature
## ============================================================================
## NIGHTMARE CREATURE — LimboAI agent (R16 ORIENT/NAV/ANIM FIX PASS).
##
## Architecture:
##   CreatureAwareness   — all sensors (vision, hearing, proximity) + memory
##   CreatureNavigator   — all navigation and steering (single velocity writer)
##   LimboAI BT          — high-level decisions (patrol / investigate / combat)
##   This script         — combat resolution, animation, audio, health rules
##
## R16 fixes (see creature_log.txt from R15 for the evidence):
##   ORIENT  ModelRoot now carries the 180° yaw the awareness doc always claimed
##           it had. The GLB faces +Z, the AI forward is -Z: that mismatch made
##           the creature "see" you while showing its back and moonwalk-glide
##           toward you during chases. Head hitbox moved to the (now) front.
##   HEAD    The head sphere is an Area3D hitbox, NOT body collision. Its old
##           top (y=2.039) overlapped every door lintel (underside y=2.0) and
##           its 1 m snout snagged posts/barrels — the "can't go through doors"
##           report. Pellets still hit it (weapon ray tests areas).
##   STEP    Ledge hop (jump anim) for obstacles <= step_height, so the 0.4 m
##           hall Stage is climbable (nav agent_max_climb raised to match).
##   FACE    Combat facing: the body turns toward the player while winding,
##           lunging, feeding, or when the player is confirmed close — attacks
##           no longer swing at empty air and the "glide, correct later" is gone.
##   LUNGE   Distance-scaled duration (no more 4 m overshoot on a 2.2 m pounce),
##           early-out on contact + wall block, jump→bite animation chain,
##           post-hit cooldowns so swipe↔lunge can't machine-gun.
##   SWIPE   Randomised attack_1/2/3, strike on anim end, 0.3 s anim hold after
##           the hit so the swing is never cut mid-frame.
##   DOWNED  Full chain on neutralize: hit_1/hit_2/defence flinch → death_1/2 →
##           state_to_crawl → crawl_idol loop (crawl_bite snap if you poke it)
##           → crawl_to_state get-up → recover roar. No more frozen T-pose-ish
##           empty-animation corpse for 20 s (log lines: `anim=` blank).
##   FEED    On player death: state_to_crawl → crawl to the body → eating loop.
##           Respawn snaps it out (amnesiac). Uses the last unused clips.
##   WAKE    Roar/defence startle now holds its clip (react latch) instead of
##           being cut after one frame by the gait selector.
##   CLAMP   _clamp_to_ground no longer teleports the body 0.9 m INTO THE AIR
##           (origin is at the feet) and never fires during an intentional hop.
##   MISC    Smooth depenetration (no teleport pop), amnesiac startle at point
##           blank, LOS/lunge "clear path" rays lowered to y+0.3 so the 0.4 m
##           Stage actually blocks them (the y+0.7 ray flew over it — that was
##           the "rams the stage forever" steering fallback).
##
## BT shape (unchanged — it was correct; perception/nav were the problems):
##   BTDynamicSelector
##   ├─ DynSeq [ CondNeutralized, ActRecover ]
##   ├─ DynSeq [ CondSeesPlayer, BTDynamicSelector[
##   │        DynSeq[CondInSwipeRange, ActSwipe],
##   │        DynSeq[CondCanLunge,     ActLunge],
##   │        ActChase ] ]
##   ├─ Seq    [ CondHearsPlayer, ActSetAlert ]
##   ├─ DynSeq [ CondHasAlert, ActInvestigate ]
##   └─ ActPatrol
## ============================================================================
const BUILD_TAG := "R16"
const LOG_PATH  := "user://creature_log.txt"

@export_group("AI")
@export var patrol_points: Array[Vector3] = []
@export var auto_patrol_radius: float = 4.0
@export var hear_radius: float = 16.0
@export var sight_range: float = 12.0
## R16: 75° felt arbitrary once the model actually faces where it looks; 90°
## matches the visible head sweep far better (sneaking up behind still works).
@export var sight_fov_deg: float = 90.0
@export var confirm_time: float = 0.4
@export var proximity_range: float = 2.5
@export var investigate_dwell: float = 4.0
@export var gunshot_hear_range: float = 40.0

@export_group("Movement")
@export var walk_speed: float = 2.2
@export var run_speed: float = 4.6
@export var lunge_speed: float = 7.5
@export var gravity: float = 18.0
## Ledges up to this tall are hopped onto (jump anim) when they block a
## commanded move — the 0.4 m hall Stage is the design case.
@export var step_height: float = 0.5

@export_group("Combat")
@export var max_health: float = 100.0
@export var swipe_range: float = 1.9
@export var swipe_damage: float = 25.0
@export var swipe_cooldown: float = 1.6
@export var windup_time: float = 0.55
@export var lunge_min: float = 2.2
@export var lunge_max: float = 6.5
@export var lunge_damage: float = 35.0
@export var lunge_cooldown: float = 4.0
@export var lunge_time: float = 0.55
@export var knockback_force: float = 7.0
@export var attack_standoff: float = 1.35
@export var neutralize_time: float = 25.0
@export var void_y: float = -0.5
## Inside this range (and visually confirmed) the body turns to FACE the player
## instead of the steering direction — attacks always swing at you now.
@export var combat_face_range: float = 3.2
## Downed creature snaps (crawl_bite, no damage) if you stand over it.
@export var downed_snap_range: float = 1.7

@export_group("Feeding (player-death sequence)")
@export var feed_speed: float = 1.6

@export_group("Debug")
@export var debug_beacon: bool = true

@export_group("Animations (from nightmare_creature_1.glb)")
@export var anim_idle: String = "Creature_armature|idle"
@export var anim_battle_idle: String = "Creature_armature|battle_idle"
@export var anim_walk: String = "Creature_armature|walk"
@export var anim_run: String = "Creature_armature|Run"
@export var anim_attack: String = "Creature_armature|attack_1"
@export var anim_attack_2: String = "Creature_armature|attack_2"
@export var anim_attack_3: String = "Creature_armature|attack_3"
@export var anim_bite: String = "Creature_armature|bite"
@export var anim_jump: String = "Creature_armature|jump"
@export var anim_hit: String = "Creature_armature|hit_1"
@export var anim_hit_2: String = "Creature_armature|hit_2"
@export var anim_defence: String = "Creature_armature|defence"
@export var anim_roar: String = "Creature_armature|roar"
@export var anim_death: String = "Creature_armature|death_1"
@export var anim_death_2: String = "Creature_armature|death_2"
@export var anim_state_to_crawl: String = "Creature_armature|state_to_crawl"
@export var anim_crawl: String = "Creature_armature|crawl"
@export var anim_crawl_idle: String = "Creature_armature|crawl_idol"
@export var anim_crawl_bite: String = "Creature_armature|crawl_bite"
@export var anim_getup: String = "Creature_armature|crawl_to_state"
## NOTE: the GLB calls this "crawl_to_state.001", but Godot's importer
## sanitizes the dot — the AnimationPlayer list name is crawl_to_state_001.
@export var anim_getup_2: String = "Creature_armature|crawl_to_state_001"
@export var anim_eating: String = "Creature_armature|eating"

# ── Node refs ─────────────────────────────────────────────────────────────────
@onready var _bt_player: BTPlayer = $BTPlayer
@onready var _roar: AudioStreamPlayer = $Roar
@onready var _growl: AudioStreamPlayer = $Growl
@onready var _step: AudioStreamPlayer = $Step
@onready var _screech: AudioStreamPlayer = $Screech
@onready var _beacon: MeshInstance3D = $DebugBeacon

# ── Child controllers (added in _ready) ──────────────────────────────────────
var awareness: CreatureAwareness = null
var nav: CreatureNavigator = null

# ── Player reference ──────────────────────────────────────────────────────────
var _player: PlayerMovement = null

# ── State flags ───────────────────────────────────────────────────────────────
var _awake: bool = false
var _neutralized: bool = false

# ── Alert (investigation target) ─────────────────────────────────────────────
var _alert_target: Vector3 = Vector3.ZERO
var _has_alert: bool = false
var _alert_cd: float = 0.0

# ── Patrol ────────────────────────────────────────────────────────────────────
var _patrol_idx: int = 0
var _spawn_pos: Vector3 = Vector3.ZERO

# ── Combat timers ─────────────────────────────────────────────────────────────
var _attack_cd: float = 0.0
var _lunge_cd: float = 0.0
var _winding: bool = false
var _windup_t: float = 0.0
var _attack_anim_done: bool = true
var _attack_clip: String = ""          # which attack_N variant is swinging
var _lunging: bool = false
var _lunge_t: float = 0.0
var _lunge_dir: Vector3 = Vector3.ZERO
var _lunge_hit: bool = false
var _lunge_hit_t: float = 0.0          # when contact happened (follow-through)
var _lunge_max_t: float = 0.55         # distance-scaled dash duration
var _lunge_wall_t: float = 0.0         # blocked-by-geometry accumulator
## Short hold after a strike/landing: play_anim() ignores gait swaps so the
## attack/bite clip never snaps mid-swing into Run (the R15 close-range
## animation glitch).
var _anim_lock_t: float = 0.0

# ── Step assist (ledge hop) ───────────────────────────────────────────────────
var _step_cd: float = 0.0
var _hop_t: float = 0.0
var _cmd_hvel: Vector3 = Vector3.ZERO   # commanded h-velocity, pre-move_and_slide

# ── Amnesia / react telegraph ─────────────────────────────────────────────────
var _amnesia_t: float = 0.0
var _react_t: float = 0.0
var _was_combat: bool = false
var _noncombat_t: float = 999.0

# ── Facing (written by navigator, read here) ──────────────────────────────────
var _move_dir: Vector3 = Vector3.ZERO

# ── Task tag (BT tasks stamp their name; used by navigator and log) ──────────
var _task_tag: String = "-"

# ── Animation helpers ─────────────────────────────────────────────────────────
var _anim: AnimationPlayer = null
var _anim_map: Dictionary = {}

# ── 2.5D audio ────────────────────────────────────────────────────────────────
var _voices: Array[AudioStreamPlayer] = []
var _pan_fx: Array[AudioEffectPanner] = []

# ── Dwell sweep (investigate) ─────────────────────────────────────────────────
var _sweep_t: float = 0.0
var _sweep_gap: float = 999.0
var _sweep_center: float = 0.0

# ── Footstep timer ────────────────────────────────────────────────────────────
var _step_t: float = 0.0

# ── Ground clamp cooldown ─────────────────────────────────────────────────────
var _clamp_cd: float = 0.0

# ── Downed animation chain ────────────────────────────────────────────────────
enum DownPhase { NONE, FLINCH, DEATH, TO_CRAWL, CRAWL_IDLE, SNAP, GETUP }
var _down_phase: int = DownPhase.NONE
var _down_t: float = 0.0               # time inside current phase
var _down_total: float = 0.0           # total downed time (schedules GETUP)
var _down_speed: float = 1.0           # anim speed_scale while downed
var _down_flinch: String = ""
var _down_flinch_len: float = 0.5
var _down_death: String = ""
var _down_death_len: float = 1.4
var _down_tocrawl_len: float = 1.25
var _down_getup: String = ""
var _down_getup_len: float = 1.25
var _down_snap_cd: float = 0.0
var _down_growl_t: float = 999.0

# ── Feeding (player-death) sequence ──────────────────────────────────────────
enum FeedPhase { NONE, DROP, CRAWL, EAT }
var _feed_phase: int = FeedPhase.NONE
var _feed_t: float = 0.0
var _feed_growl_t: float = 999.0

# ── Log / debug ───────────────────────────────────────────────────────────────
var _logf: FileAccess = null
var _dbg_t: float = 0.0


# ── Engine error logger ───────────────────────────────────────────────────────
class CreatureErrorLogger extends Logger:
	var lines: Array[String] = []
	var mutex: Mutex = Mutex.new()
	func _log_message(message: String, error: bool) -> void:
		mutex.lock()
		lines.append(("ERR | " if error else "MSG | ") + message)
		mutex.unlock()
	func _log_error(fn: String, file: String, line: int, code: String,
			rationale: String, _editor_notify: bool, error_type: int,
			_script_backtraces: Array[ScriptBacktrace]) -> void:
		mutex.lock()
		lines.append("ENGINEERR[t%d] %s:%d in %s() %s %s" % [
			error_type, file, line, fn, code, rationale])
		mutex.unlock()
	func take_lines() -> Array[String]:
		mutex.lock()
		var out: Array[String] = lines.duplicate()
		lines.clear()
		mutex.unlock()
		return out

var _err_logger: CreatureErrorLogger = null


# ═══════════════════════════════════════════════════════════════════════════════
# Initialisation
# ═══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	set_physics_process(false)
	await get_tree().physics_frame
	set_physics_process(true)

	health = max_health
	_spawn_pos = global_position
	add_to_group("creature")

	_anim = _find_anim(self)
	_build_anim_map()

	if patrol_points.is_empty():
		for i in range(4):
			var a: float = TAU * float(i) / 4.0
			patrol_points.append(_spawn_pos + Vector3(cos(a), 0.0, sin(a)) * auto_patrol_radius)

	_player = get_tree().get_first_node_in_group("player") as PlayerMovement
	Events.gun_fired.connect(_on_gun_fired)
	Events.player_died.connect(_on_player_died)
	Events.player_respawned.connect(_on_player_respawned)

	_voices = [_roar, _growl, _step, _screech]
	var bus_names: Array[String] = ["CreaRoar", "CreaGrowl", "CreaStep", "CreaScreech"]
	for i in range(_voices.size()):
		_voices[i].bus = StringName(bus_names[i])
		_pan_fx.append(AudioMgr.ensure_pan_bus(bus_names[i]))

	# ── Awareness controller ──────────────────────────────────────────────────
	awareness = CreatureAwareness.new()
	awareness.name = "Awareness"
	add_child(awareness)
	awareness.setup(self)

	# ── Navigation controller ─────────────────────────────────────────────────
	var nav_agent := NavigationAgent3D.new()
	nav_agent.name = "NavAgent"
	add_child(nav_agent)
	nav = CreatureNavigator.new()
	nav.name = "Navigator"
	add_child(nav)
	nav.setup(self, nav_agent)

	# ── LimboAI ───────────────────────────────────────────────────────────────
	_bt_player.behavior_tree = _build_tree()
	_bt_player.active = false

	if _anim != null:
		_anim.animation_finished.connect(_on_anim_finished)
	if _beacon != null:
		_beacon.visible = debug_beacon

	_logf = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	_log("=== spawn build=%s pos=%s" % [BUILD_TAG, str(global_position)])
	_err_logger = CreatureErrorLogger.new()
	OS.add_logger(_err_logger)
	print("R16 SELFTEST _log_message path")
	push_warning("R16 SELFTEST _log_error path")


func _exit_tree() -> void:
	_drain_engine_log()
	if _err_logger != null:
		if OS.has_method("remove_logger"):
			OS.remove_logger(_err_logger)
		_err_logger = null
	_log("=== exit tree")
	if _logf != null:
		_logf.flush()
		_logf.close()
		_logf = null


# ═══════════════════════════════════════════════════════════════════════════════
# Behavior tree construction
# ═══════════════════════════════════════════════════════════════════════════════

func _build_tree() -> BehaviorTree:
	var bt := BehaviorTree.new()
	var root := BTDynamicSelector.new()
	bt.set_root_task(root)

	var seq_recover := BTDynamicSequence.new()
	seq_recover.add_child(CondNeutralized.new())
	seq_recover.add_child(ActRecover.new())
	root.add_child(seq_recover)

	var seq_combat := BTDynamicSequence.new()
	seq_combat.add_child(CondSeesPlayer.new())
	var combat_sel := BTDynamicSelector.new()
	var seq_swipe := BTDynamicSequence.new()
	seq_swipe.add_child(CondInSwipeRange.new())
	seq_swipe.add_child(ActSwipe.new())
	var seq_lunge := BTDynamicSequence.new()
	seq_lunge.add_child(CondCanLunge.new())
	seq_lunge.add_child(ActLunge.new())
	combat_sel.add_child(seq_swipe)
	combat_sel.add_child(seq_lunge)
	combat_sel.add_child(ActChase.new())
	seq_combat.add_child(combat_sel)
	root.add_child(seq_combat)

	var seq_hear := BTSequence.new()
	seq_hear.add_child(CondHearsPlayer.new())
	seq_hear.add_child(ActSetAlert.new())
	root.add_child(seq_hear)

	var seq_inv := BTDynamicSequence.new()
	seq_inv.add_child(CondHasAlert.new())
	seq_inv.add_child(ActInvestigate.new())
	root.add_child(seq_inv)

	root.add_child(ActPatrol.new())
	return bt


# ═══════════════════════════════════════════════════════════════════════════════
# Wake / damage / neutralize
# ═══════════════════════════════════════════════════════════════════════════════

var health: float = 100.0


func _on_gun_fired(pos: Vector3) -> void:
	if global_position.distance_to(pos) > gunshot_hear_range:
		return
	if _neutralized:
		return
	if not _awake:
		_wake(pos)
	else:
		set_alert(pos, true)
		if awareness != null:
			awareness.stamp_position(pos)


func _wake(pos: Vector3) -> void:
	_awake = true
	# Startle pose: usually the full roar, occasionally the defence flinch.
	# The react latch holds the clip AND freezes travel_to for its duration,
	# so the wake telegraph is never cut after one frame by the gait selector
	# (R15 bug: roar played 16 ms, then walk overwrote it).
	if randf() < 0.3:
		_play_anim_raw(anim_defence, 0.0)
		_react_t = maxf(_react_t, _clip_len(anim_defence))
		_growl.play()
	else:
		# R18: blend 0.0 — the roar VOICE and the roar POSE must start on the
		# same frame (a 0.12 s crossfade delayed the mouth ~7 frames).
		_play_anim_raw(anim_roar, 0.0)
		_react_t = maxf(_react_t, _clip_len(anim_roar))
		_roar.play()
	set_alert(pos, true)
	if awareness != null:
		awareness.stamp_position(pos)
	_bt_player.active = true
	_log("WAKE at %s (player %s)" % [str(global_position), str(pos)])


## Amnesia break: awareness calls this when the player is at biting distance
## during the post-recover daze. It doesn't remember you, but it reacts.
func startle() -> void:
	_amnesia_t = 0.0
	_react_t = maxf(_react_t, 0.5)


# ── Alert API (investigation target) ──────────────────────────────────────────

func has_alert() -> bool:
	return _has_alert


func get_alert_target() -> Vector3:
	return _alert_target


func set_alert(pos: Vector3, force: bool = false) -> void:
	if not force and _has_alert and _alert_cd > 0.0 \
			and pos.distance_to(_alert_target) < 4.0:
		return
	_alert_cd = 3.0
	_alert_target = pos
	_has_alert = true


func clear_alert() -> void:
	_has_alert = false


# ── Damage / neutralize ────────────────────────────────────────────────────────

func take_damage(amount: float, push_dir: Vector3) -> void:
	if _neutralized:
		return
	if not _awake:
		_wake(_player.global_position if _player != null else global_position)
	health -= amount
	_amnesia_t = 0.0
	_screech.play()
	_log("DAMAGE %.1f -> hp %.1f" % [amount, health])
	position += Vector3(push_dir.x, 0.0, push_dir.z).normalized() * 0.25
	# Being shot cancels any feeding sequence and hands control back to the BT
	# so CondNeutralized/ActRecover actually runs.
	if _feed_phase != FeedPhase.NONE:
		_feed_phase = FeedPhase.NONE
		_bt_player.active = true
	_winding = false
	_windup_t = 0.0
	_lunging = false
	_lunge_t = 0.0
	_task_tag = "-"
	if nav != null:
		nav.stop()
	_start_down_chain()
	_log("NEUTRALIZED for %.1fs (flinch=%s death=%s)" % [
		neutralize_time, _down_flinch, _down_death])


## R16: the downed body now plays a real chain instead of one death clip and
## 20+ seconds of blank AnimationPlayer (see R15 log `anim=` empty lines):
##   flinch (hit_1/hit_2/defence) → death_1/2 → state_to_crawl → crawl_idol
##   loop (crawl_bite snap if the player looms) → crawl_to_state → recover().
func _start_down_chain() -> void:
	_neutralized = true
	# R18: flinches play at NATURAL speed. The 1.4x/2.2x playback made the
	# knockdown read as a twitchy glitch ("weird change of animation state
	# when it's shot"): hit clips are 0.62 s, defence 1.25 s — the 25 s down
	# window absorbs the slower chain with room to spare.
	var opts: Array = [[anim_hit, 1.0], [anim_hit_2, 1.0], [anim_defence, 1.0]]
	var pick: Array = opts[randi() % opts.size()]
	_down_flinch = pick[0]
	_down_speed = pick[1]
	_down_flinch_len = _clip_len(_down_flinch, _down_speed)
	_down_death = anim_death if randf() < 0.5 else anim_death_2
	_down_death_len = _clip_len(_down_death)
	_down_tocrawl_len = _clip_len(anim_state_to_crawl)
	_down_getup = anim_getup if randf() < 0.5 else anim_getup_2
	_down_getup_len = _clip_len(_down_getup)
	_down_phase = DownPhase.FLINCH
	_down_t = 0.0
	_down_total = 0.0
	_down_snap_cd = 0.0
	_down_growl_t = randf_range(2.0, 4.0)
	_play_anim_raw(_down_flinch)


func is_neutralized() -> bool:
	return _neutralized


func recover() -> void:
	_neutralized = false
	_winding = false
	_windup_t = 0.0
	_lunging = false
	_lunge_t = 0.0
	_lunge_hit = false
	_attack_cd = 0.0
	_lunge_cd = 0.0
	_task_tag = "-"
	_down_phase = DownPhase.NONE
	_down_speed = 1.0
	health = max_health
	_patrol_idx = 0
	clear_alert()
	forget_player()
	# Get-up roar: latch holds the clip while the BT restarts underneath it.
	# R18: blend 0.0 + the trimmed 1.85 s roar wav → voice and pose start and
	# end together (the old 10.5 s wav kept droning through the patrol that
	# followed — "the roar sound is not played in sync").
	_play_anim_raw(anim_roar, 0.0)
	_react_t = maxf(_react_t, _clip_len(anim_roar))
	_roar.play()
	_log("RECOVER at %s (amnesiac patrol)" % str(global_position))


# ═══════════════════════════════════════════════════════════════════════════════
# Feeding sequence (player death) — uses crawl / eating clips
# ═══════════════════════════════════════════════════════════════════════════════

func _on_player_died() -> void:
	if not _awake or _neutralized or _feed_phase != FeedPhase.NONE:
		return
	_feed_phase = FeedPhase.DROP
	_feed_t = 0.0
	_feed_growl_t = randf_range(5.0, 8.0)
	_task_tag = "Feeding"
	_react_t = 0.0
	_anim_lock_t = 0.0
	_bt_player.active = false
	if nav != null:
		nav.stop()
	_play_anim_raw(anim_state_to_crawl)
	_log("FEED START at %s" % str(global_position))


func _on_player_respawned() -> void:
	if _feed_phase == FeedPhase.NONE:
		return
	_feed_phase = FeedPhase.NONE
	_task_tag = "-"
	if _awake:
		_bt_player.active = true
	forget_player()
	_react_t = 0.0
	_log("FEED END (respawn)")


func _update_feeding(delta: float) -> void:
	_feed_t += delta
	match _feed_phase:
		FeedPhase.DROP:
			if _feed_t >= _clip_len(anim_state_to_crawl):
				_feed_phase = FeedPhase.CRAWL
				_feed_t = 0.0
				_play_anim_raw(anim_crawl)
		FeedPhase.CRAWL:
			if nav != null and nav.travel_to(player_pos(), feed_speed, 1.35):
				_feed_phase = FeedPhase.EAT
				_feed_t = 0.0
				nav.stop()
				_play_anim_raw(anim_eating)
				_growl.play()
				_log("FEED EAT at %s" % str(global_position))
		FeedPhase.EAT:
			_feed_growl_t -= delta
			if _feed_growl_t <= 0.0:
				_feed_growl_t = randf_range(5.0, 8.0)
				_growl.play()
		_:
			pass


# ═══════════════════════════════════════════════════════════════════════════════
# Senses (proxies to awareness — tasks should prefer awareness directly)
# ═══════════════════════════════════════════════════════════════════════════════

func player_pos() -> Vector3:
	if _player == null:
		return global_position
	return _player.global_position


func dist_to_player() -> float:
	var d: Vector3 = player_pos() - global_position
	d.y = 0.0
	return d.length()


## Legacy compat: tasks that call sees_player() directly still work.
## New tasks should call awareness.confirmed() instead.
func sees_player(check_fov: bool = true) -> bool:
	if awareness == null:
		return false
	if check_fov:
		return awareness.confirmed()
	return awareness.proximity()


func hears_player() -> bool:
	if awareness == null:
		return false
	return awareness.heard()


# ═══════════════════════════════════════════════════════════════════════════════
# Movement API (delegates to navigator)
# ═══════════════════════════════════════════════════════════════════════════════

## Returns true when arrived. BT tasks call this instead of writing velocity.
func move_toward_point(target: Vector3, speed: float, arrive: float = 0.7) -> bool:
	if nav == null:
		return true
	return nav.travel_to(target, speed, arrive)


func stop_move() -> void:
	if nav != null:
		nav.stop()


func is_stuck() -> bool:
	if nav == null:
		return false
	return nav.is_stuck()


func clear_stuck() -> void:
	pass   # navigator manages its own stuck state; patrol calls this on skip


## R16: ray lowered from y+0.7 to y+0.3. At 0.7 the "is the lane clear" check
## flew straight OVER the 0.4 m hall Stage, which is exactly why the steering
## fallback rammed the stage forever while the player stood behind it.
func clear_path(dir: Vector3, dist: float) -> bool:
	var world: World3D = get_world_3d()
	if world == null or world.direct_space_state == null:
		return true
	var from: Vector3 = global_position + Vector3(0.0, 0.3, 0.0)
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			from, from + dir * dist)
	q.exclude = [get_rid()]
	q.collision_mask = 17
	return world.direct_space_state.intersect_ray(q).is_empty()


## Walkable point near `around` for investigation search points.
func search_point_near(around: Vector3, radius: float) -> Vector3:
	var best: Vector3 = around
	for i in range(6):
		var a: float = randf() * TAU
		var r: float = radius * sqrt(randf())
		var p: Vector3 = around + Vector3(cos(a), 0.0, sin(a)) * r
		if nav != null:
			p = NavigationServer3D.map_get_closest_point(
					nav._nav.get_navigation_map(), p)
		best = p
		if p.distance_to(global_position) > 1.5:
			break
	return best


# ═══════════════════════════════════════════════════════════════════════════════
# Patrol
# ═══════════════════════════════════════════════════════════════════════════════

func current_patrol_point() -> Vector3:
	if patrol_points.is_empty():
		return _spawn_pos
	return patrol_points[_patrol_idx]


func next_patrol_point() -> void:
	_patrol_idx = (_patrol_idx + 1) % patrol_points.size()


# ═══════════════════════════════════════════════════════════════════════════════
# Combat resolution
# ═══════════════════════════════════════════════════════════════════════════════

func attack_ready() -> bool:
	# R16: the react latch (wake roar / recover roar / combat-start flinch)
	# gates attacks too — the old code let a point-blank wake start WINDUP
	# literally 1 ms into the roar, cutting the clip after one frame.
	return _attack_cd <= 0.0 and _react_t <= 0.0 and not _winding and not _lunging


func lunge_ready() -> bool:
	return _lunge_cd <= 0.0 and _react_t <= 0.0


func start_windup() -> void:
	_windup_t = 0.0
	_winding = true
	if nav != null:
		nav.stop()
	# R19: plant the feet. nav.stop() only deactivates the navigator, and the
	# velocity watchdog used to skip winding frames — so whatever speed the
	# chase/backoff had bled into the swing and the creature SKATED through
	# the whole attack pose (player log: ActSwipe vreal=2.17).
	velocity.x = 0.0
	velocity.z = 0.0
	# R16: randomised swing variant — attack_1/2/3 all see use now.
	var opts: Array[String] = [anim_attack, anim_attack_2, anim_attack_3]
	_attack_clip = opts[randi() % opts.size()]
	_play_anim_raw(_attack_clip)
	_attack_anim_done = false
	_growl.play()
	_log("WINDUP dist=%.2f clip=%s" % [dist_to_player(), _attack_clip])


## Strike lands when the chosen swing clip ends (0.83-1.04 s — the telegraph
## IS the animation now), with a small margin in case the finished signal is
## swallowed by an abort.
func windup_done() -> bool:
	return _attack_anim_done or _windup_t >= _clip_len(_attack_clip) + 0.25


func do_swipe() -> void:
	_winding = false
	if _player != null and dist_to_player() < swipe_range * 1.25 \
			and absf(player_pos().y - global_position.y) < 1.6:
		var dir: Vector3 = (player_pos() - global_position).normalized()
		Events.player_damaged.emit(swipe_damage, dir)
		_player.apply_knockback(dir, knockback_force * 0.6)
		_growl.play()
		_log("SWIPE HIT dist=%.2f" % dist_to_player())
	_attack_cd = swipe_cooldown
	# R16: the knockback used to drop the player at exactly lunge_min..max
	# range, so every swipe chained into an instant free lunge (log:
	# `SWIPE HIT dist=2.29` → `LUNGE START dist=2.34` 16 ms later).
	_lunge_cd = maxf(_lunge_cd, 0.9)
	# R17: hold only what is actually LEFT of the swing clip. The strike
	# normally fires exactly at animation_finished, so the old flat 0.3 s
	# latch held NOTHING — the AnimationPlayer went blank and the body ran
	# off at 4.6 m/s on a frozen pose (the `anim=` lines in the player log).
	_anim_lock_t = maxf(_anim_lock_t,
			clampf(_clip_len(_attack_clip) - _windup_t, 0.0, 0.35))


func cancel_windup() -> void:
	_winding = false
	_windup_t = 0.0
	velocity.x = 0.0
	velocity.z = 0.0


func is_winding() -> bool:
	return _winding


func start_lunge() -> void:
	_lunge_dir = player_pos() - global_position
	_lunge_dir.y = 0.0
	if _lunge_dir.length_squared() > 0.001:
		_lunge_dir = _lunge_dir.normalized()
	# R16: duration scaled to the actual gap (+0.6 m bite margin) instead of a
	# fixed 0.55 s × 7.5 m/s = 4.1 m dash that overshot every close lunge and
	# then had to moonwalk back — the "lunge→chase glitch".
	_lunge_max_t = clampf((dist_to_player() + 0.6) / lunge_speed, 0.22, lunge_time)
	_lunge_t = 0.0
	_lunge_hit = false
	_lunge_hit_t = 0.0
	_lunge_wall_t = 0.0
	_lunging = true
	_play_anim_raw(anim_jump)
	_roar.play()
	_log("LUNGE START dist=%.2f dur=%.2f" % [dist_to_player(), _lunge_max_t])


func lunge_done() -> bool:
	return not _lunging


func cancel_lunge() -> void:
	_lunging = false
	_lunge_t = 0.0
	_lunge_hit = false
	_lunge_cd = lunge_cooldown
	# R19: an aborted dash (a one-frame vision flicker mid-lunge used to do
	# this) must LAND, not snap jump→attack in 0.16 s (player log: LUNGE
	# START 8290 → WINDUP 8457). Hold the jump pose briefly and lock out the
	# swing so the next tick can't insta-windup.
	_anim_lock_t = maxf(_anim_lock_t, 0.35)
	_attack_cd = maxf(_attack_cd, 0.45)


func _end_lunge(hit: bool, blocked: bool) -> void:
	_lunging = false
	if blocked:
		_lunge_cd = lunge_cooldown * 0.5   # slammed terrain: retry sooner
		_attack_cd = maxf(_attack_cd, 0.4)
		_log("LUNGE BLOCKED by geometry")
	elif hit:
		_lunge_cd = lunge_cooldown
		_attack_cd = maxf(_attack_cd, 0.55)  # no instant swipe on landing
	else:
		_lunge_cd = lunge_cooldown
		_attack_cd = maxf(_attack_cd, 0.55)
	_anim_lock_t = maxf(_anim_lock_t, 0.35)  # let jump/bite finish its arc


# ═══════════════════════════════════════════════════════════════════════════════
# Task-tag / BT interface
# ═══════════════════════════════════════════════════════════════════════════════

func set_task_tag(t: String) -> void:
	_task_tag = t


func task_tag() -> String:
	return _task_tag


func note_combat_start() -> void:
	if not _was_combat:
		# maxf: never shortens the wake/recover startle latch.
		_react_t = maxf(_react_t, 0.7)
		_was_combat = true


func is_amnesiac() -> bool:
	return _amnesia_t > 0.0


func forget_player() -> void:
	_amnesia_t = 5.0
	_react_t = 0.0
	if awareness != null:
		awareness.reset()


# ═══════════════════════════════════════════════════════════════════════════════
# Frame update
# ═══════════════════════════════════════════════════════════════════════════════

func _physics_process(delta: float) -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as PlayerMovement
	_drain_engine_log()

	# Void reset.
	if global_position.y < -5.0 or global_position.y < void_y:
		_log("VOID RESET from y=%.2f" % global_position.y)
		global_position = _spawn_pos
		velocity = Vector3.ZERO
		_neutralized = false
		_winding = false
		_lunging = false
		_down_phase = DownPhase.NONE
		_down_speed = 1.0
		if _feed_phase != FeedPhase.NONE:
			_feed_phase = FeedPhase.NONE
			_bt_player.active = _awake

	# Proximity wake.
	if not _awake and not _neutralized and _player != null \
			and dist_to_player() < proximity_range:
		_wake(player_pos())

	# ── Tick sub-controllers BEFORE move_and_slide ────────────────────────────
	if awareness != null:
		awareness.tick(delta)
	if nav != null:
		nav.tick(delta)          # writes velocity.x/z

	_attack_cd = maxf(0.0, _attack_cd - delta)
	_lunge_cd  = maxf(0.0, _lunge_cd - delta)
	_anim_lock_t = maxf(0.0, _anim_lock_t - delta)

	if _neutralized:
		nav.stop()
		velocity = Vector3.ZERO
		_update_downed(delta)
	elif _feed_phase != FeedPhase.NONE:
		_update_feeding(delta)
	elif not _awake:
		nav.stop()
		_play_anim_raw(anim_idle)
	else:
		if _winding:
			_windup_t += delta
		if _lunging:
			_lunge_t += delta
			velocity.x = _lunge_dir.x * lunge_speed
			velocity.z = _lunge_dir.z * lunge_speed
			_move_dir = _lunge_dir      # face the dash, not stale steering
			# Blocked head-on by geometry (stage side, closed door, wall):
			# abort the dash instead of grinding against it for the full 0.55 s.
			if is_on_wall():
				var wn: Vector3 = get_wall_normal()
				if wn.dot(_lunge_dir) < -0.5:
					_lunge_wall_t += delta
				else:
					_lunge_wall_t = 0.0
			else:
				_lunge_wall_t = 0.0
			if _lunge_wall_t > 0.1 and not _lunge_hit:
				_end_lunge(false, true)
			elif not _lunge_hit and _player != null and dist_to_player() < 1.7 \
					and absf(player_pos().y - global_position.y) < 1.6:
				_lunge_hit = true
				_lunge_hit_t = _lunge_t
				var dir: Vector3 = (player_pos() - global_position).normalized()
				Events.player_damaged.emit(lunge_damage, dir)
				_player.apply_knockback(dir, knockback_force)
				_growl.play()
				_play_anim_raw(anim_bite)   # contact chomp mid-dash
				_log("LUNGE HIT dist=%.2f" % dist_to_player())
			if _lunging:
				# Hit → 0.14 s follow-through, then the chase resumes;
				# miss → the distance-scaled dash window ends it.
				var end_t: float = (_lunge_hit_t + 0.14) if _lunge_hit else _lunge_max_t
				if _lunge_t >= end_t:
					_end_lunge(_lunge_hit, false)

	# ── Physics ───────────────────────────────────────────────────────────────
	# R16: remember the COMMANDED horizontal velocity before move_and_slide
	# scrubs the into-wall component — the step-assist hop gate died on
	# head-on presses (velocity ≈ 0 after the slide) exactly when a ledge
	# hop was needed most (log: 4 s pinned at the Stage south face, no hop).
	_cmd_hvel = Vector3(velocity.x, 0.0, velocity.z)
	if not _neutralized:
		velocity.y = maxf(velocity.y - gravity * delta, -40.0)
		move_and_slide()
	_clamp_to_ground()

	# ── Step assist: hop ledges up to step_height (the 0.4 m Stage) ──────────
	_try_step_assist(delta)

	# ── Depenetration from player (R16: smooth push, no teleport pop) ────────
	if not _lunging and _player != null:
		var away: Vector3 = global_position - player_pos()
		away.y = 0.0
		var ov: float = away.length()
		if ov < 1.05:
			if ov < 0.0001:
				away = Vector3(1.0, 0.0, 0.0)
			var push: float = minf(1.05 - ov, 7.0 * delta)
			global_position += away.normalized() * push

	# ── Combat state tracking ─────────────────────────────────────────────────
	if _task_tag == "ActChase" or _task_tag == "ActSwipe" or _task_tag == "ActLunge":
		_noncombat_t = 0.0
	else:
		_noncombat_t += delta
	if _noncombat_t > 2.0:
		_was_combat = false

	_amnesia_t = maxf(0.0, _amnesia_t - delta)
	_react_t   = maxf(0.0, _react_t - delta)
	_alert_cd  = maxf(0.0, _alert_cd - delta)
	_sweep_gap += delta

	# ── Animation ─────────────────────────────────────────────────────────────
	var real_hspd: float = nav.real_hspd if nav != null else 0.0
	if _anim != null:
		if _neutralized and _down_phase != DownPhase.NONE:
			_anim.speed_scale = _down_speed
		elif _hop_t > 0.0:
			_anim.speed_scale = 2.0        # hop: jump clip at double speed
		else:
			var cur: StringName = _anim.current_animation
			var nominal: float = walk_speed
			if cur == _resolve(anim_run):
				nominal = run_speed
			elif cur == _resolve(anim_crawl):
				nominal = feed_speed
			elif cur == _resolve(anim_jump):
				nominal = 5.5
			elif cur == _resolve(anim_bite):
				nominal = 4.5
			if real_hspd > 0.05 and not (nav != null and nav.is_pinned()):
				_anim.speed_scale = clampf(real_hspd / maxf(nominal, 0.1), 0.55, 1.45)
			else:
				_anim.speed_scale = 1.0

	# ── Blank-anim watchdog (R17) ──────────────────────────────────────────
	# Non-looping clips that finish while every authority is briefly latched
	# used to leave current_animation == "" — a frozen pose skating across the
	# level. If nothing owns the animation right now, never leave it empty.
	if _anim != null and _awake and not _neutralized \
			and _feed_phase == FeedPhase.NONE and not _winding and not _lunging \
			and _react_t <= 0.0 and _anim_lock_t <= 0.0 and _hop_t <= 0.0 \
			and String(_anim.current_animation) == "":
		if real_hspd > walk_speed * 1.25:
			_play_anim_raw(anim_run)
		elif real_hspd > 0.3:
			_play_anim_raw(anim_walk)
		else:
			_play_anim_raw(anim_battle_idle)

	# ── Roar voice guard (R18) ───────────────────────────────────────────────
	# The roar VOICE may never outlive the roar POSE: when the animation moves
	# on (patrol walk after recover, a flinch after a mid-roar shot) any
	# remaining roar audio is cut. Mid-lunge the roar is a battle cry over the
	# jump→bite combo, so it gets a 1.2 s grace window after the dash instead.
	if _roar != null and _roar.playing and _anim != null and not _lunging \
			and _anim_lock_t <= 0.0 and _hop_t <= 0.0 \
			and _lunge_cd <= lunge_cooldown - 1.2 \
			and _anim.current_animation != _resolve(anim_roar):
		_roar.stop()

	# ── Facing ────────────────────────────────────────────────────────────────
	# Base: commanded direction from the navigator. R16 addition: while winding,
	# lunging, feeding, or when the player is CONFIRMED and close, the body
	# turns toward the player — swipes/bites now always face their target and
	# the old "glides in showing its back, corrects only when attacking" is
	# gone (that was the reversed model + movement-only facing compounding).
	var face_dir: Vector3 = _move_dir
	if _awake and not _neutralized and _player != null:
		var dp: Vector3 = player_pos() - global_position
		dp.y = 0.0
		var dp_len: float = dp.length()
		var combat_face: bool = _winding or _lunging \
				or _feed_phase == FeedPhase.EAT \
				or (dp_len < combat_face_range and awareness != null \
					and awareness.confirmed())
		if combat_face and dp_len > 0.01:
			face_dir = dp / dp_len
	if not _neutralized and _awake and face_dir.length_squared() > 0.000001:
		var rate: float = 14.0 if (_winding or _lunging) else 10.0
		# R16: atan2(-x, -z) so the body's -Z axis leads the movement. The old
		# atan2(x, z) aligned +Z with the travel direction — but AI forward,
		# the FOV cone and (since the ModelRoot fix) the model's FACE are all
		# -Z. That inverted yaw is why the creature "saw" you precisely when
		# it showed you its backside and moonwalk-glided through chases.
		var desired: float = atan2(-face_dir.x, -face_dir.z)
		rotation.y = lerp_angle(rotation.y, desired, 1.0 - exp(-rate * delta))

	# Footsteps.
	if not _neutralized and _awake and is_on_floor() and real_hspd > 0.3:
		_step_t -= delta
		if _step_t <= 0.0:
			_step.play()
			_step.pitch_scale = randf_range(0.9, 1.1)
			# Cadence follows the clip actually playing: run ~0.38 s/footfall,
			# walk ~0.6, crawl (feeding approach) ~0.42 — divided by the anim
			# speed scale so fast/slow playback stays in step with the feet.
			var cadence: float = 0.6
			if _anim != null and _anim.current_animation == _resolve(anim_crawl):
				cadence = 0.42
			elif real_hspd > walk_speed * 1.4:
				cadence = 0.38
			_step_t = cadence / maxf(_anim.speed_scale if _anim != null else 1.0, 0.55)

	# ── Debug log (1 Hz) ──────────────────────────────────────────────────────
	_dbg_t -= delta
	if _dbg_t <= 0.0:
		_dbg_t = 1.0
		var aname: String = String(_anim.current_animation) if _anim != null else "-"
		_log("state awake=%s neu=%s pos=(%.2f,%.2f,%.2f) vreal=%.2f task=%s anim=%s dist=%.2f conf=%s heard=%s mem=%s" % [
			str(_awake), str(_neutralized),
			global_position.x, global_position.y, global_position.z,
			real_hspd, _task_tag, aname, dist_to_player(),
			str(awareness.confirmed() if awareness else false),
			str(awareness.heard() if awareness else false),
			str(awareness.has_memory() if awareness else false)])

	_update_audio()


# ── Downed chain driver ────────────────────────────────────────────────────────

func _update_downed(delta: float) -> void:
	_down_t += delta
	_down_total += delta
	_down_snap_cd = maxf(0.0, _down_snap_cd - delta)
	match _down_phase:
		DownPhase.FLINCH:
			if _down_t >= _down_flinch_len:
				_down_t = 0.0
				_down_speed = 1.0
				_down_phase = DownPhase.DEATH
				_play_anim_raw(_down_death)
		DownPhase.DEATH:
			if _down_t >= _down_death_len:
				_down_t = 0.0
				_down_phase = DownPhase.TO_CRAWL
				_play_anim_raw(anim_state_to_crawl)
		DownPhase.TO_CRAWL:
			if _down_t >= _down_tocrawl_len:
				_down_t = 0.0
				_down_growl_t = randf_range(1.0, 3.0)
				_down_phase = DownPhase.CRAWL_IDLE
				_play_anim_raw(anim_crawl_idle)
		DownPhase.CRAWL_IDLE:
			_down_growl_t -= delta
			if _down_growl_t <= 0.0:
				_down_growl_t = randf_range(4.0, 7.0)
				_growl.play()
			# Get-up is scheduled off the TOTAL downed time so crawl_bite
			# snaps (player poking the downed creature) eat idle time and
			# can never push the get-up past ActRecover's neutralize_time.
			if _down_total >= neutralize_time - _down_getup_len - 0.05:
				_down_t = 0.0
				_down_phase = DownPhase.GETUP
				_play_anim_raw(_down_getup)
				_log("GETUP %s" % _down_getup)
			elif _down_snap_cd <= 0.0 and _player != null \
					and dist_to_player() < downed_snap_range \
					and _down_total < neutralize_time - _down_getup_len \
						- _clip_len(anim_crawl_bite) - 0.1:
				# Poke the downed thing: it snaps at you (no damage — a scare).
				# The total-time budget guarantees a snap can never still be
				# playing when the get-up window (and ActRecover) come due.
				_down_t = 0.0
				_down_phase = DownPhase.SNAP
				_down_snap_cd = 2.8
				_play_anim_raw(anim_crawl_bite)
				_growl.play()
				_log("DOWNED SNAP dist=%.2f" % dist_to_player())
		DownPhase.SNAP:
			if _down_t >= _clip_len(anim_crawl_bite):
				_down_t = 0.0
				_down_phase = DownPhase.CRAWL_IDLE
				_play_anim_raw(anim_crawl_idle)
		_:
			pass   # GETUP rides until ActRecover calls recover()


# ── Step assist (ledge hop) ────────────────────────────────────────────────────

## When a commanded move is blocked by a ledge no taller than step_height with
## headroom above, hop onto it (jump clip). This is what makes the 0.4 m hall
## Stage climbable — paired with nav_baker agent_max_climb 0.4, the navigator
## now routes OVER it, and the body can actually follow that route.
func _try_step_assist(delta: float) -> void:
	_step_cd = maxf(0.0, _step_cd - delta)
	_hop_t = maxf(0.0, _hop_t - delta)
	if _step_cd > 0.0 or not _awake or _neutralized or _lunging or _winding \
			or _feed_phase != FeedPhase.NONE:
		return
	if not is_on_floor() or not is_on_wall():
		return
	if _cmd_hvel.length() < 0.8:
		return
	var world: World3D = get_world_3d()
	if world == null or world.direct_space_state == null:
		return
	var ss: PhysicsDirectSpaceState3D = world.direct_space_state
	var dir: Vector3 = _cmd_hvel.normalized()
	if nav != null and nav.move_dir.length_squared() > 0.0001:
		dir = nav.move_dir
	dir.y = 0.0
	dir = dir.normalized()
	# 1) Anything taller than step_height ahead? (ray above the ledge line)
	var o1: Vector3 = global_position + Vector3(0.0, step_height + 0.08, 0.0)
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			o1, o1 + dir * 0.65)
	q.exclude = [get_rid()]
	q.collision_mask = 17
	if not ss.intersect_ray(q).is_empty():
		return
	# 2) Is there a surface to land on within step height?
	var o2: Vector3 = o1 + dir * 0.6
	q = PhysicsRayQueryParameters3D.create(
			o2, o2 + Vector3(0.0, -(step_height + 0.5), 0.0))
	q.exclude = [get_rid()]
	q.collision_mask = 17
	var hit: Dictionary = ss.intersect_ray(q)
	if hit.is_empty():
		return
	var gp: Vector3 = hit["position"]
	var dh: float = gp.y - global_position.y
	if dh < 0.08 or dh > step_height:
		return
	# 3) Headroom above the landing spot?
	var o3: Vector3 = Vector3(o2.x, gp.y + 0.05, o2.z)
	q = PhysicsRayQueryParameters3D.create(o3, o3 + Vector3(0.0, 1.85, 0.0))
	q.exclude = [get_rid()]
	q.collision_mask = 17
	if not ss.intersect_ray(q).is_empty():
		return
	# Hop.
	velocity.y = sqrt(2.0 * gravity * (dh + 0.10))
	_step_cd = 0.7
	_hop_t = 0.5
	_anim_lock_t = maxf(_anim_lock_t, 0.5)
	_play_anim_raw(anim_jump)
	_log("STEP HOP dh=%.2f" % dh)


# ── Investigate dwell sweep ────────────────────────────────────────────────────

func turn_slow(delta: float) -> void:
	if _sweep_gap > 0.3:
		_sweep_center = rotation.y
		_sweep_t = 0.0
	_sweep_gap = 0.0
	_sweep_t += delta
	rotation.y = _sweep_center + sin(_sweep_t * 1.3) * 1.1


# ── Locomotion clip selector ───────────────────────────────────────────────────

func play_gait(speed: float) -> void:
	play_anim(anim_run if speed > walk_speed * 1.25 else anim_walk)


# ── Ground clamp ──────────────────────────────────────────────────────────────

## Rescue from sinking into geometry. R16 fixes two things: the old version
## snapped to gp.y + 0.9 (the body origin is AT THE FEET — that launched the
## creature a metre into the air whenever it fired), and it could fire during
## an intentional step-hop, cancelling the arc.
func _clamp_to_ground() -> void:
	_clamp_cd = maxf(0.0, _clamp_cd - get_physics_process_delta_time())
	if velocity.y > 0.1 or _hop_t > 0.0:
		return
	var world: World3D = get_world_3d()
	if world == null or world.direct_space_state == null:
		return
	var from: Vector3 = global_position + Vector3(0.0, 0.6, 0.0)
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			from, from + Vector3(0.0, -4.0, 0.0))
	q.exclude = [get_rid()]
	q.collision_mask = 1
	var hit: Dictionary = world.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var gp: Vector3 = hit["position"]
	if gp.y > global_position.y + 0.05:
		var was: float = global_position.y
		global_position.y = gp.y + 0.02
		velocity.y = 0.0
		if _clamp_cd <= 0.0:
			_log("GROUND CLAMP y %.2f -> %.2f" % [was, global_position.y])
			_clamp_cd = 2.0


# ── Debug state (for debug panel) ─────────────────────────────────────────────

func debug_state() -> Dictionary:
	var aname: String = String(_anim.current_animation) if _anim != null else "-"
	return {
		"tag":        BUILD_TAG,
		"pos":        global_position,
		"awake":      _awake,
		"neutralized":_neutralized,
		"dist":       dist_to_player(),
		"sees":       awareness.confirmed() if awareness else false,
		"hears":      awareness.heard() if awareness else false,
		"mem":        awareness.has_memory() if awareness else false,
		"anim":       aname,
		"hp":         health,
		"task":       _task_tag,
		"vreal":      nav.real_hspd if nav else 0.0,
	}


# ═══════════════════════════════════════════════════════════════════════════════
# Animation helpers
# ═══════════════════════════════════════════════════════════════════════════════

func _find_anim(n: Node) -> AnimationPlayer:
	for c in n.get_children():
		var a: AnimationPlayer = c as AnimationPlayer
		if a != null:
			return a
		var r: AnimationPlayer = _find_anim(c)
		if r != null:
			return r
	return null


func _build_anim_map() -> void:
	if _anim == null:
		return
	for a in _anim.get_animation_list():
		var s: String = String(a)
		var low: String = s.to_lower()
		_anim_map[low] = s
		var parts: PackedStringArray = low.split("|")
		_anim_map[parts[parts.size() - 1]] = s
	# Looping clips: locomotion idles/gaits + the downed crawl idle + feeding.
	for n in [anim_idle, anim_walk, anim_run, "Creature_armature|battle_idle",
			anim_crawl, anim_crawl_idle, anim_eating]:
		var r: String = _resolve(n)
		if r != "":
			_anim.get_animation(r).loop_mode = Animation.LOOP_LINEAR


func _resolve(anim_name: String) -> String:
	if _anim == null or anim_name == "":
		return ""
	var low: String = anim_name.to_lower()
	if _anim_map.has(low):
		return _anim_map[low]
	var parts: PackedStringArray = low.split("|")
	var key: String = parts[parts.size() - 1]
	if _anim_map.has(key):
		return _anim_map[key]
	# Importer sanitization tolerance: "crawl_to_state.001" arrives as
	# "crawl_to_state_001" — retry with dots folded to underscores.
	var folded: String = key.replace(".", "_")
	if _anim_map.has(folded):
		return _anim_map[folded]
	for k in _anim_map:
		var ks: String = String(k)
		if ks.contains(key) or ks.replace(".", "_") == folded:
			return _anim_map[k]
	return ""


## Length of a clip in seconds (at `speed` playback rate), with a sane fallback
## when the clip is missing — all sequence timers run off this.
func _clip_len(anim_name: String, speed: float = 1.0) -> float:
	var fallback: float = 0.8 / maxf(speed, 0.1)
	if _anim == null:
		return fallback
	var res: String = _resolve(anim_name)
	if res == "":
		return fallback
	if not _anim.has_animation(res):
		return fallback
	return maxf(0.1, _anim.get_animation(res).length / maxf(speed, 0.1))


func play_anim(anim_name: String) -> void:
	if _neutralized or _winding or _lunging or _anim_lock_t > 0.0:
		return
	if _feed_phase != FeedPhase.NONE:
		return                    # feeding chain drives its own clips
	if _react_t > 0.0:
		# Startle telegraph (wake roar / defence / recover roar) holds its clip
		# against EVERYTHING. R17: the old version let "non-locomotion" poses
		# through, so ActChase's point-blank standoff swapped the recover roar
		# to battle_idle ~0.3 s in (run-3 log line 3473) — same class of
		# animation-snap glitch the latch exists to prevent.
		return
	# R17: the pinned conversion is for "commanded but going nowhere" — require
	# the body to actually BE near-stationary, otherwise prowl flicker could
	# play battle_idle at 4.6 m/s (player log line 399377).
	if nav != null and nav.is_pinned() and nav.real_hspd < 0.6 \
			and (anim_name == anim_walk or anim_name == anim_run):
		anim_name = anim_battle_idle
	_play_anim_raw(anim_name)


## R17: every clip switch crossfades over 0.12 s. The old hard cuts were the
## remaining "animation state changing glitches" — jump→Run on lunge landing,
## attack→battle_idle on strike, walk→Run on gait changes all snapped poses.
const ANIM_BLEND := 0.12


func _play_anim_raw(anim_name: String, blend: float = ANIM_BLEND) -> void:
	if _anim == null:
		return
	var resolved: String = _resolve(anim_name)
	if resolved == "":
		return
	if _anim.current_animation != resolved:
		_anim.play(resolved, blend)


func _on_anim_finished(anim_name: StringName) -> void:
	if _anim == null:
		return
	if _attack_clip != "" and anim_name == _resolve(_attack_clip):
		_attack_anim_done = true


# ═══════════════════════════════════════════════════════════════════════════════
# 2.5D audio
# ═══════════════════════════════════════════════════════════════════════════════

func _update_audio() -> void:
	var cam: Camera3D = Events.main_camera
	if cam == null:
		return
	var rel: Vector3 = global_position - cam.global_position
	var dist: float = rel.length()
	var right: float = 0.0
	if dist > 0.01:
		right = cam.global_transform.basis.x.dot(rel.normalized())
	var panv: float = clampf(right, -1.0, 1.0) * 0.85
	for i in range(_voices.size()):
		var p: AudioStreamPlayer = _voices[i]
		if p == null or not p.playing:
			continue
		var maxd: float = _max_dist(p)
		var vol: float = clampf(1.0 - dist / maxd, 0.0, 1.0)
		p.volume_db = linear_to_db(maxf(vol, 0.001)) if vol > 0.02 else -80.0
		if i < _pan_fx.size() and _pan_fx[i] != null:
			_pan_fx[i].pan = panv


func _max_dist(p: AudioStreamPlayer) -> float:
	if p == _roar:    return 45.0
	if p == _growl:   return 20.0
	if p == _screech: return 30.0
	return 25.0


# ═══════════════════════════════════════════════════════════════════════════════
# Telemetry
# ═══════════════════════════════════════════════════════════════════════════════

func _log(msg: String) -> void:
	if _logf == null:
		return
	_logf.store_line("%8d | %s" % [Time.get_ticks_msec(), msg])
	_logf.flush()


func _drain_engine_log() -> void:
	if _err_logger == null or _logf == null:
		return
	for l in _err_logger.take_lines():
		_log(l)
