class_name AwarenessState
extends Resource

var is_visible: bool = false
var last_seen_position: Vector3 = Vector3.ZERO
var last_seen_time: float = -100.0
var is_heard: bool = false
var last_heard_position: Vector3 = Vector3.ZERO
var last_heard_time: float = -100.0
var proximity_detected: bool = false

func clear() -> void:
    is_visible = false
    is_heard = false
    proximity_detected = false
