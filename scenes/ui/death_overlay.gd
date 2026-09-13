extends Control
class_name DeathOverlay
## ============================================================================
## DEATH OVERLAY — functionality only; layout in death_overlay.tscn.
## Fades in on Events.player_died; R emits Events.respawn_requested
## (SurvivalSystem performs the reset and emits player_respawned -> hide).
## ============================================================================

## R26: one-shot gate set by JumpscareDirector when a creature kill routes
## through the jumpscare instead of the death screen.
var _suppressed: bool = false


func _ready() -> void:
	add_to_group("death_overlay")
	visible = false
	modulate = Color(1, 1, 1, 0)
	Events.player_died.connect(_show)
	Events.player_respawned.connect(_hide)


## R26: called by JumpscareDirector before player_died propagates.
func suppress_next() -> void:
	_suppressed = true


func _show() -> void:
	if _suppressed:
		_suppressed = false   # consume the flag, skip the fade-in entirely
		return
	visible = true
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate", Color(1, 1, 1, 1), 1.2).set_trans(Tween.TRANS_SINE)


func _hide() -> void:
	visible = false
	modulate = Color(1, 1, 1, 0)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("respawn"):
		Events.respawn_requested.emit()
