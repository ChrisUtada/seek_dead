class_name EscapeSkill
extends SkillBase

func _init():
	skill_name = "紧急撤离"
	skill_description = "逃离当前房间，跳至下一间（全局限2次）"
	energy_cost = 0.0
	cooldown = 0.0

func can_use(_state: StateComponent) -> bool:
	return RoomManager.get_escape_charges() > 0

func use(user: Node2D) -> bool:
	var state = user.get("state") as StateComponent
	if not state or not can_use(state):
		return false
	_activate_skill(user)
	return true

func _activate_skill(_user: Node2D):
	RoomManager.escape_current_room()
