class_name ReelPreview
extends RefCounted

# M1-04 转轮带预览（纯计算，不写 controller 状态）：
# 给定「假设配装」→ 真实带子构成（聚合 / 稀有度封顶 / 共享来源 / MISS / 金币 / 精华注入），
# 口径与 reel_system.build_strips 完全一致（格子数走同一个 ReelSystem.cells_for），
# 两者一致性由 M1 回归守护（tests/m1_reward_reach_test.gd）。
#
# 用途：整备页「🎰 转轮带」总览、武器替换弹层的得失预览。

static var _syn_defs: Array = []

# 敌方注入（乱权废铁 / 深渊侵蚀）来自房间状态，默认 0/false；传入后按 build_strips 同式计入带长。
static func compose(weapons: Array, skills: Array, charms: Array, elements = [],
		run_bonus: Dictionary = {}, deprived_level: int = 0,
		chaos: bool = false, boss_trash: int = 0) -> Dictionary:
	var agg := {}
	var miss_w := 0.0
	var wsum := 0.0
	var syn_w := _synergy_weight_map(active_synergies(weapons, charms))
	for wpath in weapons:
		var wd: WeaponData = load(wpath)
		if wd == null or wd.symbols == null:
			continue
		var rank: int = ReelSystem.RARITY_RANK.get(String(_rarity(wd)), 0)
		var it_total := 0.0
		for sw in wd.symbols:
			if sw == null or sw.symbol == null:
				continue
			var sym: SymbolData = sw.symbol
			var elem: String = ReelSystem.effective_element(sym, wd.element, wd.reel_element)
			var w: float = _add(agg, sym, elem, float(sw.weight), float(run_bonus.get(sym.resource_path, 0.0)) + float(syn_w.get(sym.resource_path, 0.0)), rank, wd.weapon_name)
			if w > 0.0:
				it_total += w
		if it_total > 0.0:
			wsum += it_total
			var hit: float = clamp(wd.hit_rate, 0.0, 1.0)
			if hit < 1.0:
				miss_w += it_total * (1.0 - hit)
	if deprived_level < 2:
		for spath in skills:
			var sd: SkillData = load(spath)
			if sd == null or sd.symbol == null:
				continue
			var rank2: int = ReelSystem.RARITY_RANK.get(String(_rarity(sd)), 0)
			var elem2: String = sd.symbol.element if sd.symbol.element != "none" else "none"
			var w2: float = _add(agg, sd.symbol, elem2, float(sd.weight), float(run_bonus.get(sd.symbol.resource_path, 0.0)) + float(syn_w.get(sd.symbol.resource_path, 0.0)), rank2, "技能" + sd.icon)
			if w2 > 0.0:
				wsum += w2
				var hit2: float = clamp(sd.hit_rate, 0.0, 1.0)
				if hit2 < 1.0:
					miss_w += w2 * (1.0 - hit2)
	var elem_list: Array = elements.keys() if elements is Dictionary else elements
	for e in elem_list:
		var ess: SymbolData = DuelController.ESSENCE_SYMBOLS.get(e)
		if ess == null:
			continue
		var w3: float = _add(agg, ess, String(e), DuelController.ESSENCE_POOL_WEIGHT, float(run_bonus.get(ess.resource_path, 0.0)) + float(syn_w.get(ess.resource_path, 0.0)), 0, "精华·" + ElementCounter.label(String(e)))
		if w3 > 0.0:
			wsum += w3
	# 行 + 格数（含共享来源/稀有度封顶）
	var rows := []
	var total_cells := 0
	for key in agg:
		var g: Dictionary = agg[key]
		var cells: int = ReelSystem.cells_for(float(g["w"]), g["sym"].kind, int(g["rank"]), int(g["sources"]))
		total_cells += cells
		var disp: String = g["sym"].label if g["sym"].label != "" else g["sym"].name
		rows.append({
			"key": key, "path": g["sym"].resource_path, "name": disp,
			"kind": g["sym"].kind, "elem": g["elem"], "weight": float(g["w"]),
			"cells": cells, "sources": int(g["sources"]), "rank": int(g["rank"]),
			"items": g["items"],
		})
	rows.sort_custom(func(a, b): return float(a["weight"]) > float(b["weight"]))
	# MISS：按 miss_w/wsum 折算格数（保底 1）——与 build_strips 同式
	var miss_cells := 0
	if miss_w > 0.0 and wsum > 0.0:
		miss_cells = maxi(1, roundi(float(total_cells) * miss_w / maxf(0.001, wsum)))
	# 敌人注入：乱权按当前带长 20% 注入废铁（先于深渊侵蚀，与 build_strips 同序），深渊侵蚀固定 +N 格
	var base_cells: int = total_cells + miss_cells + ReelSystem._GOLD_CELLS
	var chaos_cells: int = roundi(float(base_cells) * 0.20) if chaos else 0
	var trash_cells: int = chaos_cells + maxi(0, boss_trash)
	return {
		"rows": rows,
		"miss_cells": miss_cells,
		"gold_cells": ReelSystem._GOLD_CELLS,
		"trash_cells": trash_cells,
		"symbol_cells": total_cells,
		"total_cells": base_cells + trash_cells,
		"synergies": active_synergies(weapons, charms),
	}


# 当前激活共鸣（含触发装备路径）。匹配语义复用 SynergySystem.active_for（与结算同一套判定）。
static func active_synergies(weapons: Array, charms: Array) -> Array:
	if _syn_defs.is_empty():
		_syn_defs = ResourceScan.scan_resources("res://resources/synergies/", "SynergyData")
	var items: Array = []
	items.append_array(weapons)
	items.append_array(charms)
	var out := []
	for sd in _syn_defs:
		var trig: Array = SynergySystem.active_for(sd, items)
		if not trig.is_empty():
			out.append({"def": sd, "paths": trig})
	return out


# 两套配装的差异文案（替换弹层用）：格数增减 + 共鸣得失；无变化返回空数组。
static func diff_lines(weapons_a: Array, weapons_b: Array, skills: Array, charms: Array,
		elements = [], run_bonus: Dictionary = {}, deprived_level: int = 0,
		chaos: bool = false, boss_trash: int = 0) -> Array:
	var a := compose(weapons_a, skills, charms, elements, run_bonus, deprived_level, chaos, boss_trash)
	var b := compose(weapons_b, skills, charms, elements, run_bonus, deprived_level, chaos, boss_trash)
	var out := []
	var ca := _cells_by_key(a["rows"])
	var cb := _cells_by_key(b["rows"])
	var names := _names_by_key(a["rows"])
	names.merge(_names_by_key(b["rows"]), true)
	for key in names:
		var d: int = int(cb.get(key, 0)) - int(ca.get(key, 0))
		if d != 0:
			out.append("%s %s%d格（%d→%d）" % [names[key], "+" if d > 0 else "", d, int(ca.get(key, 0)), int(cb.get(key, 0))])
	var sa := _syn_names(a["synergies"])
	var sb := _syn_names(b["synergies"])
	for s in sb:
		if not sa.has(s):
			out.append("获得共鸣 " + s)
	for s in sa:
		if not sb.has(s):
			out.append("失去共鸣 " + s)
	return out


# 单行摘要（整备页底部/提示用）："带长N · 符号M格 · MISS K · 废铁T · 共鸣X"
static func summary_line(comp: Dictionary) -> String:
	var syns := _syn_names(comp["synergies"])
	return "带长%d · 符号%d格 · MISS %d · 金币%d · 废铁%d · 共鸣%s" % [
		int(comp["total_cells"]), int(comp["symbol_cells"]), int(comp["miss_cells"]),
		int(comp["gold_cells"]), int(comp.get("trash_cells", 0)),
		"、".join(syns) if not syns.is_empty() else "无"]


static func _add(agg: Dictionary, sym: SymbolData, elem: String, base_w: float, mod: float, rank: int, source_name: String) -> float:
	var w: float = maxf(0.0, base_w + mod)
	if w <= 0.0:
		return 0.0
	var key: String = sym.resource_path + "|" + elem
	if not agg.has(key):
		agg[key] = {"sym": sym, "elem": elem, "w": 0.0, "rank": 0, "sources": 0, "items": []}
	var g: Dictionary = agg[key]
	g["w"] = float(g["w"]) + w
	g["rank"] = maxi(int(g["rank"]), rank)
	g["sources"] = int(g["sources"]) + 1
	if not g["items"].has(source_name):
		g["items"].append(source_name)
	return w


static func _synergy_weight_map(syns: Array) -> Dictionary:
	var out := {}
	for s in syns:
		var sd: SynergyData = s["def"]
		for p in sd.weight_bonus.keys():
			out[p] = float(out.get(p, 0.0)) + float(sd.weight_bonus[p])
	return out


static func _cells_by_key(rows: Array) -> Dictionary:
	var out := {}
	for r in rows:
		out[r["key"]] = int(r["cells"])
	return out


static func _names_by_key(rows: Array) -> Dictionary:
	var out := {}
	for r in rows:
		out[r["key"]] = String(r["name"])
	return out


static func _syn_names(syns: Array) -> Array:
	var out := []
	for s in syns:
		out.append(String((s["def"] as SynergyData).name))
	return out


static func _rarity(res: Resource) -> String:
	var r: Variant = res.get("rarity")
	return String(r) if r != null else "common"
