extends Control
class_name ItemToast
## ============================================================================
## ITEM TOAST — functionality only; layout/style in item_toast.tscn.
## Small centered-lower text: "Picked up X" / "Dropped X", driven purely by
## Events (item_picked_up / item_dropped). Fades in, holds, fades out;
## a new message restarts the timer. Nothing is hardcoded into code except
## the timings below (exported, inspector-tweakable).
## ============================================================================

@export var hold_time: float = 1.6
@export var fade_time: float = 0.5
@export var alpha_mix: float = 1.0   # 0.7 on the crisp-layer instance = 70/30 crisp/degraded blend

@onready var _label: Label = $ToastLabel

var _timer: float = 0.0


func _ready() -> void:
	modulate = Color(1, 1, 1, 0)
	Events.item_picked_up.connect(_on_pickup)
	Events.item_dropped.connect(_on_drop)


func _on_pickup(item_id: String) -> void:
	_show("Picked up: %s" % _pretty(item_id))


func _on_drop(item_id: String) -> void:
	_show("Dropped: %s" % _pretty(item_id))


func _pretty(item_id: String) -> String:
	return item_id.capitalize()


func _show(text: String) -> void:
	_label.text = text
	_timer = hold_time


func _process(delta: float) -> void:
	var target: float = 0.0
	if _timer > 0.0:
		_timer -= delta
		target = 1.0
	var k: float = 1.0 - exp(-(10.0 if target > 0.0 else 1.0 / fade_time * 3.0) * delta)
	modulate = Color(1, 1, 1, lerpf(modulate.a, target, k) * alpha_mix)
