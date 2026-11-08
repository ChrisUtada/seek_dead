class_name StripTrimSystem
extends RefCounted

# G7-B B1：主动减带（符号精简 / 技能卸除）——每幕 1 次的灰盒服务。
#
# 规则来源：`docs/转轮目押_成长与减带优化_执行方案.md` §7.2、`docs/G7-B_切片拆分与验收清单_2026-11-09.md`
# 边界（P0 §7 已锁）：只改本局运行时状态——不写 res://resources/、不写 MetaStore.meta、
# 不退款、不新增货币、不刷新商店/成长/随机结果。
#
# 一期口径：
#   - 符号精简：键与建带聚合键一致（符号 resource_path|有效元素），每个符号本局最多 1 次，
#     每次 -1 格，保底 1 格；
#   - 技能卸除：从本局 selected_skills 移除（符号与 MISS 贡献按现有建带规则自然消失）；
#   - 保护：金币/MISS/废铁/BOSS 注入不进候选（它们本就不在符号聚合里）；整条带至少保留 1 个
#     damage 符号；每把已装备武器至少保留 1 个仍有格的符号；
#   - 次数：符号精简与技能卸除共享「每幕 1 次」，按幕记账，随幕重置，不跨局累计。

const TRIMS_PER_ACT := 1
const PER_SYMBOL_MAX := 1

var _ctrl: DuelController
var trimmed: Dictionary = {}          # "sym_path|elem" -> 已精简次数（本局）
var used_by_act: Dictionary = {}      # act -> 已用次数（本局）


func _init(ctrl: DuelController) -> void:
	_ctrl = ctrl


func reset_run() -> void:
	trimmed.clear()
	used_by_act.clear()


# 当前幕（棋盘模式读棋盘幕号，线性模式恒为 1）。
func current_act() -> int:
	if _ctrl != null and _ctrl.node_mode and _ctrl.board != null:
		return int(_ctrl.board.act)
	return 1


func trims_left() -> int:
	return maxi(0, TRIMS_PER_ACT - int(used_by_act.get(current_act(), 0)))


# 入口状态（B3 灰盒按钮）："ready" = 本幕还有次数且有合法候选；
# "used" = 本幕次数已用尽；"none" = 还有次数但无合法候选（无符号可减 / 保护规则挡住）。
func entry_state() -> String:
	if trims_left() <= 0:
		return "used"
	return "ready" if not candidates().is_empty() else "none"


# ---------------------------------------------------------------------------
# 候选 / 预览 / 应用
# ---------------------------------------------------------------------------

# 合法候选：符号精简（按格数降序）+ 技能卸除。
func candidates() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if trims_left() <= 0:
		return out
	var comp := _compose(trimmed, _ctrl.selected_skills)
	for r in comp["rows"]:
		var key := String(r["key"])
		var cells := int(r["cells"])
		if cells < 2:
			continue   # 保底 1 格：只有 ≥2 格才有可减空间
		if int(trimmed.get(key, 0)) >= PER_SYMBOL_MAX:
			continue
		if not _symbol_allowed(key, 1):
			continue
		out.append({"kind": "symbol", "key": key, "path": String(r["path"]), "name": String(r["name"]),
			"elem": String(r["elem"]), "cells": cells, "sym_kind": String(r["kind"])})
	for path in _ctrl.selected_skills:
		if not _skill_allowed(String(path)):
			continue
		var sd: SkillData = load(path)
		if sd == null:
			continue
		var disp: String = sd.symbol.label if sd.symbol != null and sd.symbol.label != "" else String(sd.symbol.name if sd.symbol != null else "")
		out.append({"kind": "skill", "path": String(path), "key": "",
			"name": "技能 " + String(sd.icon) + disp,
			"cells": _skill_cells(String(path))})
	out.sort_custom(func(a, b): return int(a["cells"]) > int(b["cells"]))
	return out


# 真实前后预览：逻辑格数 / 实际带长（含最小带长平铺）/ 目标符号格数 / 伤害符号格数。
func preview(cand: Dictionary) -> Dictionary:
	var before := _compose(trimmed, _ctrl.selected_skills)
	var trim_after: Dictionary = trimmed.duplicate()
	var skills_after: Array = _ctrl.selected_skills.duplicate()
	if String(cand.get("kind", "")) == "symbol":
		trim_after[String(cand["key"])] = int(trim_after.get(String(cand["key"]), 0)) + 1
	else:
		skills_after.erase(String(cand.get("path", "")))
	var after := _compose(trim_after, skills_after)
	return {
		"before_cells": int(before["total_cells"]), "after_cells": int(after["total_cells"]),
		"before_len": actual_len(int(before["total_cells"])), "after_len": actual_len(int(after["total_cells"])),
		"before_target": _target_cells(before, cand), "after_target": _target_cells(after, cand),
		"before_damage": _damage_cells(before), "after_damage": _damage_cells(after),
		"before_miss": int(before["miss_cells"]), "after_miss": int(after["miss_cells"]),
	}


# 应用（不可逆）。返回给日志的一行；拒绝时返回 ""。
func apply(cand: Dictionary) -> String:
	if trims_left() <= 0:
		return ""
	var kind := String(cand.get("kind", ""))
	if kind == "symbol":
		var key := String(cand.get("key", ""))
		if not _symbol_allowed(key, 1):
			return ""
		var was: int = _cells_of(key)
		trimmed[key] = int(trimmed.get(key, 0)) + 1
		_use_trim()
		_ctrl._build_pool(_ctrl.selected_loadout)
		return "✂ 精简：%s %d→%d 格（本幕精简次数已用尽）" % [String(cand.get("name", "")), was, maxi(1, was - 1)]
	if kind == "skill":
		var path := String(cand.get("path", ""))
		if not _skill_allowed(path):
			return ""
		_ctrl.selected_skills.erase(path)
		_use_trim()
		_ctrl._build_pool(_ctrl.selected_loadout)
		return "✂ 卸除技能：%s（本幕精简次数已用尽）" % String(cand.get("name", ""))
	return ""


func _use_trim() -> void:
	var a := current_act()
	used_by_act[a] = int(used_by_act.get(a, 0)) + 1


# ---------------------------------------------------------------------------
# 规则判定
# ---------------------------------------------------------------------------

# 精简后是否仍合法：每条带至少 1 个 damage 格；每把已装备武器至少 1 个仍有格的符号。
func _symbol_allowed(key: String, cut: int) -> bool:
	var comp := _compose(trimmed, _ctrl.selected_skills)
	var cells := {}
	for r in comp["rows"]:
		cells[String(r["key"])] = maxi(1, int(r["cells"]) - cut if String(r["key"]) == key else int(r["cells"]))
	var damage_left := 0
	for r in comp["rows"]:
		if String(r["kind"]) == "damage":
			damage_left += int(cells.get(String(r["key"]), 0))
	if damage_left <= 0:
		return false
	return _weapons_have_cells(cells)


func _skill_allowed(path: String) -> bool:
	var skills: Array = []
	for p in _ctrl.selected_skills:
		if String(p) != path:
			skills.append(p)
	var comp := _compose(trimmed, skills)
	if _damage_cells(comp) <= 0:
		return false
	var cells := {}
	for r in comp["rows"]:
		cells[String(r["key"])] = int(r["cells"])
	return _weapons_have_cells(cells)


func _weapons_have_cells(cells: Dictionary) -> bool:
	for path in _ctrl.selected_loadout:
		var wd: WeaponData = load(path)
		if wd == null or wd.symbols == null:
			continue
		var usable := false
		for sw in wd.symbols:
			if sw == null or sw.symbol == null:
				continue
			var k: String = String(sw.symbol.resource_path) + "|" + ReelSystem.effective_element(sw.symbol, wd.element, wd.reel_element)
			if int(cells.get(k, 0)) > 0:
				usable = true
				break
		if not usable:
			return false
	return true


# ---------------------------------------------------------------------------
# 计算辅助
# ---------------------------------------------------------------------------

func _compose(trim_state: Dictionary, skills: Array) -> Dictionary:
	var styles: Dictionary = {}
	if _ctrl._forge_styles != null:
		styles = _ctrl._forge_styles.preview_map()
	var bonus: Dictionary = {}
	if _ctrl._reward_system != null:
		bonus = _ctrl._reward_system.run_symbol_bonus
	return ReelPreview.compose(_ctrl.selected_loadout, skills, _ctrl.selected_charms,
		_ctrl.room_element_mult, bonus, _ctrl.deprived_level,
		_ctrl.pending_chaos, _ctrl.boss_trash, _ctrl.mastery.tune_map(), styles, trim_state)


func _damage_cells(comp: Dictionary) -> int:
	var n := 0
	for r in comp["rows"]:
		if String(r["kind"]) == "damage":
			n += int(r["cells"])
	return n


# 候选对应的格数：符号看 key，技能看它自己的符号键。
func _target_cells(comp: Dictionary, cand: Dictionary) -> int:
	if String(cand.get("kind", "")) == "skill":
		return _skill_cells(String(cand.get("path", "")), comp)
	var n := 0
	for r in comp["rows"]:
		if String(r["key"]) == String(cand.get("key", "")):
			n = int(r["cells"])
	return n


func _skill_cells(path: String, comp: Dictionary = {}) -> int:
	var sd: SkillData = load(path)
	if sd == null or sd.symbol == null:
		return 0
	if comp.is_empty():
		comp = _compose(trimmed, _ctrl.selected_skills)
	var elem: String = sd.symbol.element if sd.symbol.element != "none" else "none"
	var key := String(sd.symbol.resource_path) + "|" + elem
	for r in comp["rows"]:
		if String(r["key"]) == key:
			return int(r["cells"])
	return 0


func _cells_of(key: String) -> int:
	var comp := _compose(trimmed, _ctrl.selected_skills)
	for r in comp["rows"]:
		if String(r["key"]) == key:
			return int(r["cells"])
	return 0


# 实际带长：逻辑格数按最小带长整份平铺（与 reel_system.build_strips 同一规则）。
static func actual_len(unit: int) -> int:
	if unit <= 0:
		return 0
	var copies := 1
	while unit * copies < int(ReelSystem._STRIP_MIN_CELLS):
		copies += 1
	return unit * copies
