class_name DashSkill
extends SkillBase

@export var dash_distance: float = 200.0

func _init():
	skill_name = "冲刺"
	skill_description = "向目标方向冲刺200像素"
	energy_cost = 20.0
	cooldown = 5.0

func _activate_skill(user: Node2D):
	var direction = Vector2.RIGHT.rotated(user.global_rotation)
	var end_pos = user.global_position + direction * dash_distance
	var tween = user.create_tween()
	tween.tween_property(user, "global_position", end_pos, 0.2)
	print("冲刺技能：向目标方向冲刺 %.0f 像素" % dash_distance)
