class_name SkillManager
extends Node

signal skill_used(skill_index: int, skill: SkillBase)
signal skill_added(skill: SkillBase)
signal skill_removed(skill: SkillBase)
signal skill_upgraded(skill: SkillBase, old_level: int, new_level: int)
signal skill_replace_needed(new_skill: SkillBase)

var skills: Array[SkillBase] = []
const MAX_SLOTS: int = 2


func add_or_upgrade(skill: SkillBase) -> bool:
	for existing in skills:
		if existing.skill_name == skill.skill_name:
			if existing.level >= existing.max_level:
				return false
			var old = existing.level
			existing.level += 1
			skill_upgraded.emit(existing, old, existing.level)
			return true
	if skills.size() < MAX_SLOTS:
		skills.append(skill)
		skill_added.emit(skill)
		return true
	skill_replace_needed.emit(skill)
	return false


func replace_skill(index: int, new_skill: SkillBase):
	if index < 0 or index >= skills.size():
		return
	var old = skills[index]
	skills[index] = new_skill
	skill_removed.emit(old)
	skill_added.emit(new_skill)


func use_skill(index: int, user: Node2D) -> bool:
	if index < 0 or index >= skills.size():
		return false
	var skill = skills[index]
	if skill.use(user):
		skill_used.emit(index, skill)
		EventManager.skill_used.emit({"skill_name": skill.skill_name})
		return true
	return false


func _process(delta: float):
	for skill in skills:
		skill.tick(delta)
