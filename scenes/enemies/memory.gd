class_name Memory
extends Node

var last_known_position: Vector3 = Vector3.ZERO
var last_seen_time: float = -100.0
var last_heard_position: Vector3 = Vector3.ZERO
var last_heard_time: float = -100.0
var is_visible: bool = false
var was_visible_ever: bool = false

func update_from_perception(perception: Perception) -> void:
    var state = perception.state
    is_visible = state.is_visible
    if is_visible:
        last_known_position = state.last_seen_position
        last_seen_time = state.last_seen_time
        was_visible_ever = true
    if state.is_heard:
        last_heard_position = state.last_heard_position
        last_heard_time = state.last_heard_time

func has_recent_visual(time_window: float) -> bool:
    return (Time.get_ticks_msec() / 1000.0 - last_seen_time) < time_window

func has_recent_hearing(time_window: float) -> bool:
    return (Time.get_ticks_msec() / 1000.0 - last_heard_time) < time_window

func clear() -> void:
    is_visible = false
    was_visible_ever = false
    last_known_position = Vector3.ZERO
    last_seen_time = -100.0
    last_heard_time = -100.0
