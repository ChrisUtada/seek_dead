class_name SkillDatabase
extends RefCounted


static func get_all_skills() -> Array[SkillBase]:
	var dir = DirAccess.open("res://resources/skills")
	if not dir:
		return []
	var result: Array[SkillBase] = []
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var path = "res://resources/skills/" + fname
			var res = ResourceLoader.load(path)
			if res and res is SkillBase and not res is EscapeSkill:
				result.append(res)
		fname = dir.get_next()
	dir.list_dir_end()
	return result


static func get_random_skill() -> SkillBase:
	var pool = get_all_skills()
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()].duplicate(true)
