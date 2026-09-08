extends Area3D
## ============================================================================
## CRAWLSPACE ZONE — Phase 9 (design doc: narrow crawlspace trigger).
##
## While the player body is inside: crouch is FORCED (movement.external_crouch)
## and standing up is blocked — the capsule physically cannot rise under the
## 1.15 m ceiling. The reverb probe chokes automatically because the real
## geometry is tight (no fake audio parameters needed).
## ============================================================================

@export var force_crouch: bool = true


func _ready() -> void:
	body_entered.connect(_on_entered)
	body_exited.connect(_on_exited)


func _on_entered(body: Node3D) -> void:
	var m: PlayerMovement = body as PlayerMovement
	if m != null:
		m.external_crouch = force_crouch


func _on_exited(body: Node3D) -> void:
	var m: PlayerMovement = body as PlayerMovement
	if m != null:
		m.external_crouch = false
