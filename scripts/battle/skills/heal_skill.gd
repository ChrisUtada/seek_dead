class_name HealSkill
extends SkillBase

@export var heal_percent: float = 0.5

func _init():
	skill_name = "治疗"
	skill_description = "恢复50%生命值"
	energy_cost = 30.0
	cooldown = 10.0

func _activate_skill(user: Node2D):
	var state = user.get_node("StateComponent")
	var heal_amount = state.max_hp * heal_percent
	state.hp = min(state.hp + heal_amount, state.max_hp)
	print("治疗技能：恢复 %.0f HP" % heal_amount)
