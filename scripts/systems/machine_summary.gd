class_name MachineSummary
extends RefCounted

# ============================================================================
# G7-4 统一机器摘要（2026-11-20）
# 权威方案 §11.2：一个统一面板回答六类问题，同时服务整备/换装预览/战后复核/局末总结，
# 不再为每个入口写不同口径。
# §2.2 可归因："大数字能回答由哪个符号、牌谱、回路和乘区产生"。
#
# 纯查询、无副作用：注入 ctrl，只读现有子系统状态，不改任何数据。
# ============================================================================

var _ctrl


func _init(ctrl) -> void:
	_ctrl = ctrl


# §11.2 统一快照：六类信息结构化，供 UI / 局末总结复用同一口径。
func snapshot() -> Dictionary:
	return {
		"weapons": _weapons(),
		"symbols": _symbols(),
		"patterns": _patterns(),
		"circuits": _circuits(),
		"controls": _controls(),
		"survival": _survival(),
	}


# ① 当前两把武器和本局仓库
func _weapons() -> Dictionary:
	var loadout: Array = _ctrl.selected_loadout.duplicate(true) if _ctrl.selected_loadout != null else []
	var inventory: Array = _ctrl.run_weapon_inventory.duplicate(true) if _ctrl.run_weapon_inventory != null else []
	var names: Array[String] = []
	for p in loadout:
		var wd = load(p)
		names.append(String(wd.weapon_name) if wd != null else p.get_file().get_basename())
	return {"equipped": loadout, "equipped_names": names, "inventory": inventory}


# ② 每个符号的真实格数、占比和来源（复用 reel_preview 同一口径）
func _symbols() -> Dictionary:
	var comp: Dictionary = ReelPreview.compose(
		_ctrl.selected_loadout, _ctrl.selected_skills, _ctrl.selected_charms,
		_ctrl.room_element_mult if _ctrl.room_element_mult != null else [],
		_ctrl._reward_system.run_symbol_bonus if _ctrl._reward_system != null else {},
		_ctrl.deprived_level,
		_ctrl.pending_chaos, _ctrl.boss_trash,
		_ctrl.mastery.tune_map() if _ctrl.mastery != null else {},
		_ctrl._forge_styles.preview_map() if _ctrl._forge_styles != null else {},
		{})
	var rows: Array = comp.get("rows", [])
	var total: int = int(comp.get("total_cells", 0)) + int(comp.get("trash_cells", 0))
	var out: Array = []
	for r in rows:
		if not (r is Dictionary):
			continue
		var d: Dictionary = r
		var cells: int = int(d.get("cells", 0))
		var pct: float = (float(cells) / float(total) * 100.0) if total > 0 else 0.0
		out.append({
			"name": String(d.get("name", "")),
			"path": String(d.get("path", "")),
			"cells": cells,
			"pct": pct,
			"sources": d.get("items", []),
		})
	return {
		"total_cells": total,
		"symbol_cells": int(comp.get("symbol_cells", 0)),
		"miss_cells": int(comp.get("miss_cells", 0)),
		"rows": out,
		"synergies": comp.get("synergies", []),
	}


# ③ 当前可触发牌谱/签名与所需牌型
func _patterns() -> Array:
	var out: Array = []
	if _ctrl._pattern_system == null:
		return out
	var unlocked: Array = _ctrl._pattern_system.unlocked_patterns(
		_ctrl.selected_loadout, _ctrl._pattern_tag_of)
	for p in unlocked:
		if p == null:
			continue
		out.append({
			"id": String(p.id),
			"name": String(p.name),
			"track": String(p.track),
			"desc": String(p.desc),
		})
	return out


# ④ 已装备回路、触发条件和次数
func _circuits() -> Dictionary:
	var c = _ctrl.circuit_system
	if c == null:
		return {"equipped": [], "report": {}}
	var equipped: Array = []
	for id in c.equipped:
		var def: Dictionary = c.definition(String(id))
		equipped.append({
			"id": String(id),
			"name": String(def.get("name", id)),
			"event": String(def.get("event", "")),
			"why": c.why_not_triggered(String(id)),
		})
	return {"equipped": equipped, "report": c.reachability_report()}


# ⑤ 操控能力与剩余次数
func _controls() -> Dictionary:
	var r = _ctrl.readability
	var out: Dictionary = {}
	if r != null:
		out["trash_reroll_ready"] = r.trash_reroll_ready() if r.has_method("trash_reroll_ready") else false
		out["mercy_ready"] = r.mercy_ready() if r.has_method("mercy_ready") else false
	out["preset"] = String(r.preset) if r != null else ""
	return out


# ⑥ 关键生存与经济状态
func _survival() -> Dictionary:
	return {
		"hp": int(_ctrl.player_hp),
		"hp_max": int(_ctrl.player_hp_max),
		"gold": int(_ctrl.gold),
		"room": int(_ctrl.room_index),
	}


# 可读摘要（服务 UI 单行入口；口径与 reel_preview.summary_line 一致，避免分裂）。
func lines() -> Array[String]:
	var out: Array[String] = []
	var s: Dictionary = snapshot()
	var w: Dictionary = s["weapons"]
	var sym: Dictionary = s["symbols"]
	out.append("武器：%s" % (" + ".join(w["equipped_names"]) if not w["equipped_names"].is_empty() else "无"))
	out.append("带子：格%d / 符号%d / MISS%d" % [
		int(sym["total_cells"]), int(sym["symbol_cells"]), int(sym["miss_cells"])])
	var pats: Array = s["patterns"]
	out.append("牌谱：%s" % (str(pats.size()) if pats.size() > 0 else "无"))
	var cir: Dictionary = s["circuits"]
	out.append("回路：%s" % (str(cir["equipped"].size()) if not cir["equipped"].is_empty() else "无"))
	var ctl: Dictionary = s["controls"]
	out.append("操控：%s" % String(ctl.get("preset", "")))
	var sv: Dictionary = s["survival"]
	out.append("生存：HP %d/%d · 金 %d" % [sv["hp"], sv["hp_max"], sv["gold"]])
	return out


# 可归因（§2.2）：把"大数字由什么产生"拆到可查来源——
# 回路日志（事件/次数）+ 回路可达性（为何未触发）+ 赔付表契约（G4-5 文档路径）。
# 只读，不改状态；不臆造 combat 临时 acc 数据。
func attribution_lines() -> Array[String]:
	var out: Array[String] = []
	var c = _ctrl.circuit_system
	if c != null:
		# ① 已触发回路：event + 次数（按 id 聚合）
		var fired: Dictionary = {}
		for entry in c.log:
			var id: String = String(entry.get("id", ""))
			fired[id] = int(fired.get(id, 0)) + 1
		for id in fired:
			var def: Dictionary = c.definition(id)
			out.append("回路触发：%s ×%d（事件 %s）" % [
				String(def.get("name", id)), int(fired[id]), String(def.get("event", ""))])
		# ② 已装备但未触发：可达性原因（为什么这个回路没贡献）
		for id in c.equipped:
			if not fired.has(String(id)):
				out.append("回路未触发：%s（%s）" % [
					String(c.definition(String(id)).get("name", id)),
					c.why_not_triggered(String(id))])
	# ③ 赔付口径：指向统一赔付表（G4-5），避免每个入口重复解释公式
	out.append("赔付口径：见 docs/G4-5_当前赔付表（连线/牌谱/回路/乘区优先级与互斥）")
	return out
