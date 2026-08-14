class_name SynergySystem
extends RefCounted

# 装备共鸣（Synergy）系统：自由组合的条件效果层，叠加在方案 B 频率经济之上。
# 扫描 resources/synergies/*.tres（SynergyData）；_build_pool 时 refresh() 评估激活集并缓存，
# 结算点经查询方法读取效果（weight_mod / crit_bonus / element_boost），
# 不在 _contribute/_evaluate 热路径重复扫描。匹配语义见 synergy_data.gd 头注释。

var _ctrl: DuelController
var _defs: Array[SynergyData] = []
var _active: Array[SynergyData] = []

func _init(ctrl: DuelController) -> void:
	_ctrl = ctrl
	_defs.assign(ResourceScan.scan_resources("res://resources/synergies/", "SynergyData"))


# 在装备集合变化时调用（_build_pool 入口）：重估激活集。
func refresh() -> void:
	_active = []
	for sd in _defs:
		if _activated(sd):
			_active.append(sd)


# 当前激活的共鸣（供 HUD 显示"已激活：xxx"）
func active_synergies() -> Array:
	return _active


# —— 效果查询（各结算点调用；激活集为空时快速返回）——

func weight_mod(sym: SymbolData) -> float:
	if _active.is_empty():
		return 0.0
	var total := 0.0
	for sd in _active:
		total += float(sd.weight_bonus.get(sym.resource_path, 0.0))
	return total


func crit_bonus(sym: SymbolData) -> float:
	if _active.is_empty():
		return 0.0
	var total := 0.0
	for sd in _active:
		total += sd.crit_bonus
	return total


func element_boost(elem: String) -> float:
	var mult := 1.0
	for sd in _active:
		if sd.element_boost != "" and sd.element_boost == elem:
			mult *= sd.element_boost_mult
	return mult


# —— 激活判定（语义见 synergy_data.gd 头注释）——

func _activated(sd: SynergyData) -> bool:
	if sd.require_paths.is_empty() and sd.require_tags.is_empty():
		return false
	var candidates: Array[String] = []
	candidates.append_array(_ctrl.selected_loadout)
	candidates.append_array(_ctrl.selected_charms)
	var matched: Dictionary = {}   # path -> true（去重）
	for p in sd.require_paths:
		if not candidates.has(p):
			return false
		matched[p] = true
	for tag in sd.require_tags:
		var tag_hit := false
		for p in candidates:
			if _tag_matches(p, tag):
				tag_hit = true
				matched[p] = true
		if not tag_hit:
			return false
	return matched.size() >= sd.require_count


func _tag_matches(item_path: String, tag: String) -> bool:
	var parts := tag.split(":", false)
	if parts.size() != 2:
		return false
	var res = load(item_path)
	if res == null:
		return false
	match parts[0]:
		"element":
			return ("element" in res) and String(res.get("element")) == parts[1]
		"category":
			return ("category" in res) and String(res.get("category")) == parts[1]
		"rarity":
			return ("rarity" in res) and String(res.get("rarity")) == parts[1]
		"type":
			if res is WeaponData:
				var wt: int = (res as WeaponData).weapon_type
				return (parts[1] == "melee" and wt == WeaponData.WeaponType.MELEE) or (parts[1] == "ranged" and wt == WeaponData.WeaponType.RANGED)
	return false
