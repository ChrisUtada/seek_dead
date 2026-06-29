class_name EscapeSkill
extends SkillBase

func _init():
	skill_name = "紧急撤离"
	skill_description = "逃离当前房间，跳至下一间（CD 90秒）"
	energy_cost = 0.0
	cooldown = 90.0

func _activate_skill(_user: Node2D):
	RoomManager.escape_current_room()
