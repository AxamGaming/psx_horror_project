extends Control
class_name DeathOverlay
## ============================================================================
## DEATH OVERLAY — functionality only; layout in death_overlay.tscn.
## Fades in on Events.player_died; R emits Events.respawn_requested
## (SurvivalSystem performs the reset and emits player_respawned -> hide).
## ============================================================================

func _ready() -> void:
	visible = false
	modulate = Color(1, 1, 1, 0)
	Events.player_died.connect(_show)
	Events.player_respawned.connect(_hide)


func _show() -> void:
	visible = true
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate", Color(1, 1, 1, 1), 1.2).set_trans(Tween.TRANS_SINE)


func _hide() -> void:
	visible = false
	modulate = Color(1, 1, 1, 0)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("respawn"):
		Events.respawn_requested.emit()
