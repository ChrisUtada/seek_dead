class_name Affix
extends Resource

@export var affix_name: String = ""
@export var affix_description: String = ""
@export var affix_icon: Texture2D

@export var stat_modifiers: Array = []
@export var trigger_effects: Array = []
@export var conditional_bonuses: Array = []
@export var allowed_slots: Array = []
@export var level: int = 1


func can_appear_on(slot: int) -> bool:
	return allowed_slots.is_empty() or slot in allowed_slots


func get_description() -> String:
	if not stat_modifiers.is_empty() and not trigger_effects.is_empty():
		return _mods_text() + " / " + _triggers_text()
	if not stat_modifiers.is_empty():
		return _mods_text()
	if not trigger_effects.is_empty():
		return _triggers_text()
	if not conditional_bonuses.is_empty():
		return _conds_text()
	return affix_description


func _mods_text() -> String:
	var parts: Array[String] = []
	for m in stat_modifiers:
		var v = m.value
		var prefix = "+" if v >= 0 else ""
		var pct = m.modifier_type == 1
		parts.append(prefix + ("%.0f" % v if abs(v) >= 10 else "%.2f" % v) + ("%" if pct else ""))
	return " ".join(parts)


func _triggers_text() -> String:
	var parts: Array[String] = []
	for e in trigger_effects:
		parts.append("%d%%概率 %.0f伤害" % [e.chance * 100, e.param_value])
	return " / ".join(parts)


func _conds_text() -> String:
	var parts: Array[String] = []
	for c in conditional_bonuses:
		if c.bonus:
			var v = c.bonus.value
			var prefix = "+" if v >= 0 else ""
			parts.append("条件: %s" % prefix + ("%.0f" % v if abs(v) >= 10 else "%.2f" % v))
	return "\n".join(parts)
