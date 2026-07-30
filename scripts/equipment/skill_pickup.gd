class_name SkillPickup
extends PickupBase

var skill: SkillBase


func setup(s: SkillBase):
	skill = s
	_init_pickup()


func _build_visual():
	super._build_visual()
	_add_orb(Color(0.2, 0.8, 1.0, 0.9), Vector2(16, 16), Vector2(-8, -8))
	_add_border(Color(1, 1, 1, 0.3), Vector2(20, 20), Vector2(-10, -10))
	_add_label("S", Vector2(16, 16), Vector2(-8, -7), 12)


func _apply_effect(target: Node2D) -> bool:
	var sm := target.get_node_or_null("SkillManager") as SkillManager
	if not sm:
		return false
	var dup := skill.duplicate(true)
	if sm.add_or_upgrade(dup):
		Debug.log("[技能拾取] %s (Lv.%d)" % [dup.skill_name, dup.level])
		EventManager.skill_picked_up.emit({"skill": dup})
		return true
	return false  # 技能槽满且无法升级，保留拾取物供重试
