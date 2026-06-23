class_name SkillManager
extends Node

signal skill_used(skill_index: int, skill: SkillBase)

var skills: Array[SkillBase] = []

func add_skill(skill: SkillBase):
	skills.append(skill)

func use_skill(index: int, user: Node2D) -> bool:
	if index < 0 or index >= skills.size():
		return false
	var skill = skills[index]
	if skill.use(user):
		skill_used.emit(index, skill)
		return true
	return false

func _process(delta: float):
	for skill in skills:
		skill.tick(delta)
