@tool
class_name ActChase
extends BTAction

func _tick(_delta: float) -> Status:
    var cre = agent as NightmareCreature
    if not cre:
        return FAILURE
    cre.set_task_tag("ActChase")
    var mem = cre.get_memory()
    if not mem.is_visible:
        if mem.has_recent_visual(2.0):
            pass
        else:
            return FAILURE
    var target = mem.last_known_position
    var dist = cre.dist_to_player()
    if dist <= cre.attack_standoff:
        cre.stop_move()
        cre.play_anim(cre.anim_battle_idle)
    else:
        cre.move_toward_point(target, cre.run_speed, cre.attack_standoff)
        cre.play_gait(cre.run_speed)
    return RUNNING
