extends Control
class_name InventoryUI
## ============================================================================
## INVENTORY UI — functionality only. ALL layout/design lives in
## inventory_ui.tscn (nodes, StyleBoxes, anchors, fonts — inspector-tweakable).
## Designed at 1280x720; project stretch mode canvas_items+keep scales it
## correctly at any window size/aspect.
##
## Lives on the UI CanvasLayer (10), ABOVE the VHS post layer (1): crisp grid
## over tape-degraded world. Real-time: world keeps simulating while open.
## Opening emits Events.inventory_toggled (CameraRig focus mode) and sets
## Events.ui_wants_mouse (MouseLook click-recapture stands down).
##
## Real API callers: weight -> set_carry_weight, medkit -> set_health,
## damage-while-open -> offset_transform jolt, pickups -> slot storage.
## ============================================================================

const CAPACITY := 10.0
const JOLT_TIME := 0.35
const PICKUP_SCENE: PackedScene = preload("res://scenes/level/pickup_item.tscn")

## Item definitions live in data/item_database.tres — inspector-editable data,
## not code. Add/rebalance items there; ids are the contract with pickups.
const ITEM_DB_RES: ItemDatabase = preload("res://data/item_database.tres")
var _db: Dictionary = {}

var _slots: Array[String] = []
var _selected: int = -1
var _open: bool = false
var _jolt_t: float = 0.0

@onready var _panel: PanelContainer = $Panel
@onready var _weight_label: Label = $Panel/VBox/Header/WeightLabel
@onready var _grid: GridContainer = $Panel/VBox/Grid
@onready var _info: Label = $Panel/VBox/InfoLabel


func _ready() -> void:
	for entry in ITEM_DB_RES.items:
		var d: ItemData = entry as ItemData
		if d != null:
			_db[d.id] = d
	_slots.resize(_grid.get_child_count())
	for i in range(_slots.size()):
		_slots[i] = ""
	# Starting kit (3.1 kg / 10 -> carry 0.31: light on your feet)
	_slots[0] = "medkit"
	_slots[1] = "key"
	_slots[2] = "crowbar"
	_slots[3] = "shells"
	_slots[4] = "shells"
	# Slot buttons are scene nodes; wiring them is functionality.
	for i in range(_grid.get_child_count()):
		var b: Button = _grid.get_child(i) as Button
		if b != null:
			b.pressed.connect(_on_slot.bind(i))
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Events.player_damaged.connect(_on_damaged)
	Events.pickup_triggered.connect(_on_pickup)
	Events.shells_requested.connect(_on_shells_requested)
	_refresh_weight()


## WeaponSystem asks for ammo; the inventory IS the ammo pool.
func _on_shells_requested(count: int) -> void:
	var granted: int = 0
	for i in range(count):
		var idx: int = _slots.find("shells")
		if idx < 0:
			break
		_slots[idx] = ""
		granted += 1
	Events.shells_granted.emit(granted)
	if granted > 0:
		_refresh_weight()
		if _open:
			_refresh()


# ------------------------------------------------------------------------------
# Open / close
# ------------------------------------------------------------------------------

func toggle() -> void:
	_open = not _open
	visible = _open
	mouse_filter = Control.MOUSE_FILTER_STOP if _open else Control.MOUSE_FILTER_IGNORE
	Events.ui_wants_mouse = _open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if _open else Input.MOUSE_MODE_CAPTURED
	Events.inventory_toggled.emit(_open)
	if _open:
		_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action("open_inventory") and event.is_action_pressed("open_inventory"):
		toggle()


# ------------------------------------------------------------------------------
# Content (scene-connected: Use/Drop/Close buttons)
# ------------------------------------------------------------------------------

func _on_slot(i: int) -> void:
	_selected = i
	var id: String = _slots[i]
	if id == "" or not _db.has(id):
		_info.text = "Empty slot."
	else:
		var db: ItemData = _db[id]
		_info.text = "%s — %.1f kg" % [db.item_name, db.weight]
	_refresh()


func _on_use() -> void:
	if _selected < 0 or _slots[_selected] == "":
		return
	var id: String = _slots[_selected]
	if id == "medkit":
		var rig: CameraRig = Events.main_camera as CameraRig
		if rig != null:
			rig.set_health(minf(1.0, rig.health01 + 0.5))
		_slots[_selected] = ""
		_info.text = "Medkit used. Wounds knit, limp eases."
	elif id == "shotgun":
		# Equipping does NOT consume the item — it IS your gun.
		Events.item_used.emit(id)
		_info.text = "Equipped. RMB aim · LMB fire · R reload."
	else:
		Events.item_used.emit(id)
		_info.text = "Nothing happens. (Yet.)"
	_refresh_weight()
	_refresh()


func _on_drop() -> void:
	if _selected < 0 or _slots[_selected] == "":
		return
	var id: String = _slots[_selected]
	_slots[_selected] = ""
	_spawn_drop(id)
	var db: ItemData = _db.get(id) as ItemData
	_info.text = "Dropped %s — it's on the floor now." % [db.item_name if db != null else id]
	_refresh_weight()
	_refresh()


## Dropped items become world pickups (tinted crate, ground-snapped), so
## nothing ever vanishes: drop your shotgun and it's lying where you left it.
func _spawn_drop(id: String) -> void:
	var cam: Node = Events.main_camera
	if cam == null or cam.get_parent() == null:
		return
	var player: Node = cam.get_parent().get_parent()
	if player == null or player.get_parent() == null:
		return
	var pk: PickupItem = PICKUP_SCENE.instantiate() as PickupItem
	if pk == null:
		return
	pk.item_id = id
	player.get_parent().add_child(pk)
	pk.global_position = player.global_position + (-player.global_transform.basis.z) * 0.9
	pk.request_snap()
	Events.item_dropped.emit(id)


func _on_pickup(item_id: String) -> void:
	var idx: int = _slots.find("")
	if idx < 0:
		_info.text = "Inventory full — leave something behind."
		return
	_slots[idx] = item_id
	var db: ItemData = _db.get(item_id) as ItemData
	_info.text = "Picked up %s. It has weight now." % [db.item_name if db != null else item_id]
	Events.item_picked_up.emit(item_id)
	_refresh_weight()
	if _open:
		_refresh()


func _refresh() -> void:
	for i in range(_grid.get_child_count()):
		var b: Button = _grid.get_child(i) as Button
		if b == null:
			continue
		var box: StyleBoxTexture = b.get_theme_stylebox("normal") as StyleBoxTexture
		var id: String = _slots[i] if i < _slots.size() else ""
		if id == "":
			b.text = ""
			b.tooltip_text = ""
			if box != null:
				box.modulate_color = Color(0.1, 0.09, 0.08, 0.92)
		else:
			var db: ItemData = _db.get(id) as ItemData
			if db == null:
				b.text = "?"
				b.tooltip_text = ""
			else:
				b.text = db.item_name.left(1)
				b.tooltip_text = "%s (%.1f kg)" % [db.item_name, db.weight]
				if box != null:
					var c: Color = db.color.darkened(0.5)
					c.a = 0.92
					box.modulate_color = c
		# Selection highlight: StyleBoxTexture has no border props, so the
		# selected slot reads via an overbright bone tint on the button itself.
		if i == _selected:
			b.modulate = Color(1.35, 1.25, 0.95, 1.0)
		else:
			b.modulate = Color(1, 1, 1, 1)


func _refresh_weight() -> void:
	var total: float = 0.0
	for id in _slots:
		if id != "":
			var db: ItemData = _db.get(id) as ItemData
			if db != null:
				total += db.weight
	_weight_label.text = "%.1f / %.1f kg" % [total, CAPACITY]
	var rig: CameraRig = Events.main_camera as CameraRig
	if rig != null:
		rig.set_carry_weight(clampf(total / CAPACITY, 0.0, 1.0))


# ------------------------------------------------------------------------------
# Jolt (damage while open) + per-frame
# ------------------------------------------------------------------------------

func _on_damaged(_amount: float, _direction: Vector3) -> void:
	if _open:
		_jolt_t = JOLT_TIME


func _process(delta: float) -> void:
	if _jolt_t > 0.0:
		_jolt_t = maxf(0.0, _jolt_t - delta)
		var k: float = _jolt_t / JOLT_TIME
		_panel.offset_transform_enabled = true
		_panel.offset_transform_position = Vector2(randf_range(-6.0, 6.0), randf_range(-4.0, 4.0)) * k
		_panel.offset_transform_rotation = randf_range(-1.5, 1.5) * k
	elif _panel.offset_transform_enabled:
		_panel.offset_transform_enabled = false
		_panel.offset_transform_position = Vector2.ZERO
		_panel.offset_transform_rotation = 0.0
