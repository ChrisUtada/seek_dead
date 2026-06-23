class_name ShieldSkill
extends SkillBase

@export var damage_reduction: float = 0.5

func _init():
	skill_name = "护盾"
	skill_description = "5秒内减少50%伤害"
	energy_cost = 25.0
	cooldown = 15.0
	duration = 5.0

func _activate_skill(user: Node2D):
	var state = user.get_node("StateComponent")
	state.defenses["all_defense"] = damage_reduction
	print("护盾技能：%.0f秒内减少%.0f%%伤害" % [duration, damage_reduction * 100])

func _on_skill_finished(user: Node2D):
	var state = user.get_node("StateComponent")
	state.defenses.erase("all_defense")
	print("护盾技能结束")
