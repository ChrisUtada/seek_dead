extends Node

# ============================================================================
# 真实槽位与可达性 · Step 1（2026-11-15）
# 方案：docs/转轮凑牌战斗重构_稀有度牌型整合_完整执行方案_2026-11-15.md §10 Step 1
#
# 这一套只回答一个问题：**12 种基础内容，在「2 武器 + 1 技能 + 1 护符」的真实配置下，
# 到底有没有可组成的牌？**
#
# 做法：
#   枚举全部双武器组合（90 把 → 4005 对），用两把武器**真实能提供的符号**构造三张牌，
#   再交给 PatternMatcher.solve_rule 判定。这不是「理想牌面」——牌面严格限制在这两把
#   武器产出的符号范围内，正是「真实可达」的定义。
#   触发率统计才必须用真实转轮带（第 62 套在做）。
#
# 为什么不自己写判定：测试与实现两套逻辑会漂移，这里直接复用 solve_rule。
# ============================================================================

const WEAPON_DIR := "res://resources/weapon_templates"
const SKILL_DIR := "res://resources/skills"
const PATTERN_DIR := "res://resources/patterns"
const MATCHER := preload("res://scripts/battle/pattern_matcher.gd")
const SKILL_DATA = preload("res://scripts/items/skill_data.gd")

var _checks := 0
var _fails := 0
var _weapons: Array = []      # [{path, name, element, role, family_tags, symbols: [{sym, kind, elem}]}]
var _skills: Array = []       # [{path, name, kind, buff}]
var _report: Array = []


func _ready() -> void:
	_load_weapons()
	_load_skills()
	_run()


func _load_weapons() -> void:
	var dir := DirAccess.open(WEAPON_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var wd = load(WEAPON_DIR + "/" + f)
		if wd == null:
			continue
		var syms: Array = []
		for sw in (wd.symbols as Array):
			if sw == null or sw.symbol == null:
				continue
			syms.append({
				"sym": String(sw.symbol.resource_path),
				"kind": String(sw.symbol.kind),
				"elem": String(sw.symbol.element),
				"cat": String(sw.symbol.symbol_category),
			})
		var fams: Array = []
		if wd.family_tags is Array:
			for t in wd.family_tags:
				fams.append(String(t))
		_weapons.append({
			"path": WEAPON_DIR + "/" + f,
			"name": String(wd.weapon_name),
			"element": String(wd.element),
			"role": String(wd.get("role")),
			"family_tags": fams,
			"symbols": syms,
		})
	_weapons.sort_custom(func(a, b): return String(a["name"]) < String(b["name"]))


func _load_skills() -> void:
	var dir := DirAccess.open(SKILL_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var sd = load(SKILL_DIR + "/" + f)
		if sd == null or sd.symbol == null:
			continue
		_skills.append({
			"path": SKILL_DIR + "/" + f,
			"name": String(sd.buff_name) if String(sd.buff_name) != "" else f.get_basename(),
			"kind": String(sd.symbol.kind),
			"buff": String(sd.symbol.buff_effect),
		})


func _run() -> void:
	_check(_weapons.size() >= 80, "武器资源加载（%d 把）" % _weapons.size())
	_check(_skills.size() >= 30, "技能资源加载（%d 个）" % _skills.size())

	print("=== A 公共牌型的真实可达性 ===")
	_test_public()
	print("=== B 六条武器攻击牌谱的真实可达性 ===")
	_test_weapon_patterns()
	print("=== C 三条技能术式的真实可达性 ===")
	_test_skill_patterns()
	print("=== D 反例：不该通过的条件 ===")
	_test_negatives()
	print("=== E 扩槽不是必要条件 ===")
	_test_no_extra_slots()

	print("=== F 语义审计（可达 ≠ 语义正确）===")
	_audit_semantics()

	for line in _report:
		print("  [可达] " + String(line))
	_finish()


# —— 用两把武器真实能提供的符号，构造所有三格组合 ——
func _all_hands(a: Dictionary, b: Dictionary) -> Array:
	var pool: Array = []
	for s in (a["symbols"] as Array):
		pool.append(s)
	for s in (b["symbols"] as Array):
		pool.append(s)
	if pool.is_empty():
		return []
	var hands: Array = []
	for i in range(pool.size()):
		for j in range(pool.size()):
			for k in range(pool.size()):
				hands.append([_card(pool[i], a), _card(pool[j], b if j % 2 == 1 else a), _card(pool[k], a)])
	return hands


func _card(sym_entry: Dictionary, src_weapon: Dictionary) -> Dictionary:
	return {
		"sym": _fake_sym(sym_entry),
		"element": String(sym_entry["elem"]),
		"source": String(src_weapon["path"]),
		"source_kind": "weapon",
		"source_element": String(src_weapon["element"]),
		"valid": true,
	}


# solve_rule 只需要 sym.kind 与 resource_path，这里造一个轻量替身，避免反复 load。
var _sym_cache := {}
func _fake_sym(entry: Dictionary) -> Dictionary:
	return {
		"kind": String(entry["kind"]),
		"resource_path": String(entry["sym"]),
		"symbol_category": String(entry.get("cat", "none")),
		"base": 1.0,
	}


# 某个组合能否满足某条 match_rule
func _combo_can(a: Dictionary, b: Dictionary, rule: Dictionary) -> bool:
	var hands := _all_hands(a, b)
	for h in hands:
		if MATCHER.solve_rule(h, rule):
			return true
	return false


func _rule_of(id: String) -> Dictionary:
	var pd = load(PATTERN_DIR + "/" + id + ".tres")
	if pd == null:
		return {}
	return pd.match_rule


# A：G01 同源、G02 同族、G03 清一色
func _test_public() -> void:
	# G01：三张同族同来源 —— 任何带至少 1 个符号的武器都能给出（三格都出同一符号）
	var g01_ok := 0
	for w in _weapons:
		if not (w["symbols"] as Array).is_empty():
			g01_ok += 1
	_check(g01_ok == _weapons.size(), "G01 同源刻：全部 %d 把武器都能单独凑出（%d）" % [_weapons.size(), g01_ok])

	# G02：三张同族、来源不限 —— 需要两把武器共享同一符号
	var g02_pairs := 0
	for i in range(_weapons.size()):
		for j in range(i + 1, _weapons.size()):
			var a: Dictionary = _weapons[i]
			var b: Dictionary = _weapons[j]
			var shared := false
			for sa in (a["symbols"] as Array):
				for sb in (b["symbols"] as Array):
					if String(sa["sym"]) == String(sb["sym"]):
						shared = true
			if shared:
				g02_pairs += 1
	_check(g02_pairs > 0, "G02 同族刻：存在共享符号的双武器组合（%d 对）" % g02_pairs)
	_report.append("G02 同族刻：%d 对双武器共享同一符号" % g02_pairs)

	# G03：三张同元素 —— 需要至少一把武器能连续给出同元素牌
	var g03_ok := 0
	for w in _weapons:
		var el := String(w["element"])
		if el == "none":
			continue
		var syms: Array = w["symbols"]
		var elem_syms := 0
		for s in syms:
			if String(s["elem"]) == el:
				elem_syms += 1
		if elem_syms >= 1:
			g03_ok += 1
	_check(g03_ok > 0, "G03 清一色：有 %d 把武器能单独给出同元素牌" % g03_ok)


# B：W01–W06 的资源判定条件在真实双武器下是否有正例
func _test_weapon_patterns() -> void:
	var ids := ["W01", "W02", "W03", "W04", "W05", "W06"]
	var legacy := {"W01": "w01_flame_resonance", "W03": "w03_venom_burst",
		"W04": "w04_holy_volley", "W02": "w02_frost_seal",
		"W05": "w05_shadow_execution", "W06": "w06_plain_grind"}
	for wid in ids:
		var rule: Dictionary = {}
		if legacy.has(wid):
			rule = _rule_of(String(legacy[wid]))
		# 尚未实装的 W 用方案 §5.2 的条件临时构造（Step 3 才落资源）
		if rule.is_empty():
			rule = _spec_rule(wid)
		_check(not rule.is_empty(), "%s 有可判定的组合条件" % wid)
		if rule.is_empty():
			continue
		var hits := 0
		var sample := ""
		for i in range(_weapons.size()):
			for j in range(i + 1, _weapons.size()):
				var a: Dictionary = _weapons[i]
				var b: Dictionary = _weapons[j]
				if _unlock_ok(wid, a, b) and _combo_can(a, b, rule):
					hits += 1
					if sample == "":
						sample = "%s + %s" % [String(a["name"]), String(b["name"])]
		_report.append("%s 正例 %d 对%s" % [wid, hits, ("（例：%s）" % sample) if sample != "" else ""])
		_check(hits > 0, "%s 在真实双武器下有正例（%d 对）" % [wid, hits])


# 方案 §5.2 的解锁条件（武器元素层面）
func _unlock_ok(wid: String, a: Dictionary, b: Dictionary) -> bool:
	match wid:
		"W01":
			return String(a["element"]) == "fire" and String(b["element"]) == "fire"
		"W02":
			return String(a["element"]) == "ice" and String(b["element"]) == "ice"
		"W03":
			return String(a["element"]) == "poison" and String(b["element"]) == "poison"
		"W04":
			var names := [String(a["name"]), String(b["name"])]
			return names.has("圣辉长剑") and names.has("破晓之弓")
		"W05":
			return String(a["element"]) == "dark" and String(b["element"]) == "dark"
		"W06":
			return String(a["element"]) == "none" and String(b["element"]) == "none"
	return false


# 方案 §5.2 的组合条件（W02/W05/W06 尚未落资源，这里按文档写成结构化条件）
func _spec_rule(wid: String) -> Dictionary:
	match wid:
		"W02":
			return {"all": [{"kind": "status"}, {"kind": "damage"}, {}]}
		"W05":
			return {"all": [{"kind": "damage"}, {"kind": "damage"}, {}]}
		"W06":
			return {"all": [{"kind": "damage"}, {"kind": "damage"}, {}]}
	return {}


# C：T01–T03 —— 一张技能牌 + 两张武器牌
func _test_skill_patterns() -> void:
	var tiers := {
		"T01": func(s): return String(s["buff"]) == "power" or String(s["buff"]) == "damage_mult",
		"T02": func(s): return String(s["kind"]) == "shield" or String(s["buff"]) == "shield",
		"T03": func(s): return String(s["kind"]) == "heal" or String(s["buff"]) == "regen",
	}
	for tid in tiers:
		var n := 0
		for s in _skills:
			if (tiers[tid] as Callable).call(s):
				n += 1
		_report.append("%s 可用技能 %d 个" % [tid, n])
		_check(n > 0, "%s 至少有一个技能能提供核心牌（%d）" % [tid, n])
	# 术式只需要 1 张技能牌：断言不存在「需要 2 张技能牌」的条件
	var need_two := false
	for f in DirAccess.get_files_at(PATTERN_DIR):
		if not f.ends_with(".tres"):
			continue
		var pd = load(PATTERN_DIR + "/" + f)
		if pd == null:
			continue
		var conds: Array = (pd.match_rule as Dictionary).get("all", [])
		var skill_like := 0
		for c in conds:
			if (c as Dictionary).has("source_kind") and String(c["source_kind"]) == "skill":
				skill_like += 1
		if skill_like >= 2:
			need_two = true
	_check(not need_two, "没有牌谱要求两张技能牌")


# D：反例 —— 这些都不该被任何基础内容接受
func _test_negatives() -> void:
	var dagger: Dictionary = _find_weapon("匕首")
	var guard_rule := {"all": [{"kind": "shield"}, {"kind": "shield"}, {}]}
	# 2026-11-20 测试契约更新（S2-2 防御武器试点）：
	# 旧断言「任何武器都不带 shield/heal」已被正式防御武器设计推翻，改为验证新不变量：
	# ① 普通 damage 角色武器不得携带 shield/heal 符号；
	# ② 携带 shield/heal 的武器必须有 defense/recovery 等相符角色；
	# ③ 坚壁钉锤（防御原型）真实含铁誓护盾且 role=defense；
	# ④ 牌谱可达性反例继续用明确的无护盾配装夹具，不依赖"全项目永远没有防御武器"。
	var plain_with_guard := 0
	var guard_without_role := 0
	for w in _weapons:
		var has_guard := false
		for s in (w["symbols"] as Array):
			var k := String(s["kind"])
			if k == "shield" or k == "heal":
				has_guard = true
				break
		if not has_guard:
			continue
		var role := String(w.get("role", ""))
		if role == "damage" or role == "":
			plain_with_guard += 1
		if role != "defense" and role != "recovery":
			guard_without_role += 1
	_check(plain_with_guard == 0, "普通 damage 武器不带护盾/治疗符号（违规 %d）" % plain_with_guard)
	_check(guard_without_role == 0, "携带护盾/治疗的武器角色相符（违规 %d）" % guard_without_role)
	var mace: Dictionary = _find_weapon("坚壁钉锤")
	var mace_guard := false
	for s in (mace.get("symbols", []) as Array):
		if String(s["kind"]) == "shield" and String(s["sym"]).ends_with("iron_wall.tres"):
			mace_guard = true
	_check(not mace.is_empty() and String(mace.get("role", "")) == "defense" and mace_guard,
		"坚壁钉锤为 defense 且真实携带铁誓护盾")
	# 反例夹具：用明确的无护盾武器（匕首）验证「单把武器无法凑护盾×2」，
	# 不再依赖"全项目没有防御武器"这一已被推翻的全局假设。
	_check(not dagger.is_empty() and (dagger.get("symbols", []) as Array).is_empty() == false
		and not _weapon_has_guard(dagger) and not _combo_can(dagger, dagger, guard_rule),
		"无护盾夹具（匕首）单把无法凑出「护盾牌×2」")

	# W05 不能要求暗状态符号（6.2 后暗系 DoT 符号已存在，改测牌谱规则本身而非符号声明）
	var w05: Resource = load("res://resources/patterns/w05_shadow_execution.tres")
	var w05_rule_txt := JSON.stringify(w05.match_rule) if w05 != null else ""
	_check(not w05_rule_txt.contains("status"), "W05 牌谱规则不要求状态符号——只看暗系伤害牌")
	# 6.2 新增暗系 DoT 符号后，W05 可达性由暗系伤害符号保证（ WITNESS 暗武器存在）
	var dark_dmg := 0
	for w in _weapons:
		for s in (w["symbols"] as Array):
			if String(s["kind"]) == "damage" and String(s["elem"]) == "dark":
				dark_dmg += 1
	_check(dark_dmg > 0, "暗系伤害符号存在（%d）——W05 可达" % dark_dmg)

	# 金币不是牌面组件
	var gold_cond := false
	for f in DirAccess.get_files_at(PATTERN_DIR):
		if not f.ends_with(".tres"):
			continue
		var pd = load(PATTERN_DIR + "/" + f)
		if pd != null and JSON.stringify(pd.match_rule).find("gold") >= 0:
			gold_cond = true
	_check(not gold_cond, "没有牌谱把金币当作组件")

	# 三武器 / 三来源不可能出现（双武器槽上限为 2）
	_check(_weapons.size() > 2, "武器总数远大于槽位上限（%d > 2），但单局只能装 2 把" % _weapons.size())


# F：语义审计 —— 火系武器的伤害符号多数不带 fire 元素（火斩是「无属性伤害」），
# 2026-11-27 焚世法杖把状态位替换为 ember_spark（element=fire 的伤害符号）后，
# 「按符号 element 判火系」会漏掉火斩，W01 仍必须按**来源武器元素**判定。
func _audit_semantics() -> void:
	var fire_dmg_fire := 0
	var fire_status := 0
	for w in _weapons:
		if String(w["element"]) != "fire":
			continue
		for s in (w["symbols"] as Array):
			if String(s["kind"]) == "damage" and String(s["elem"]) == "fire":
				fire_dmg_fire += 1
			if String(s["kind"]) == "status":
				fire_status += 1
	_report.append("⚠ 火系武器：element=fire 的伤害符号 %d 个，状态符号 %d 个 → W01「火系伤害」必须按**来源武器元素**判定" % [fire_dmg_fire, fire_status])
	var w01_rule_txt := JSON.stringify((load(PATTERN_DIR + "/w01_flame_resonance.tres") as PatternData).match_rule)
	_check(w01_rule_txt.contains('"source_element":"fire"') and not w01_rule_txt.contains('"element":"fire"'),
		"W01 按来源武器元素判定火系（不按符号 element；裸 element=fire 伤害符号 %d 个）" % fire_dmg_fire)

	# 同理确认冰/毒系：这两个有元素伤害符号，语义没坑
	var ice_dmg := 0
	var poison_dmg := 0
	for w in _weapons:
		for s in (w["symbols"] as Array):
			if String(s["kind"]) != "damage":
				continue
			if String(s["elem"]) == "ice":
				ice_dmg += 1
			if String(s["elem"]) == "poison":
				poison_dmg += 1
	_check(ice_dmg > 0 and poison_dmg > 0,
		"冰/毒系存在元素伤害符号（冰 %d / 毒 %d），W02/W03 可按符号元素判定" % [ice_dmg, poison_dmg])
	_report.append("冰系元素伤害符号 %d 个、毒系 %d 个（W02/W03 无语义坑）" % [ice_dmg, poison_dmg])


# E：扩槽不是任何基础内容的前提
func _test_no_extra_slots() -> void:
	# 6 条 W 的解锁全部在「两把武器」范围内
	for wid in ["W01", "W02", "W03", "W04", "W05", "W06"]:
		var ok := false
		for i in range(_weapons.size()):
			for j in range(i + 1, _weapons.size()):
				if _unlock_ok(wid, _weapons[i], _weapons[j]):
					ok = true
					break
			if ok:
				break
		_check(ok, "%s 只用两把武器即可解锁（不需要第三个槽）" % wid)
	# 3 条 T 只需要 1 个技能
	_check(_skills.size() > 0, "存在技能资源，1 个技能槽即可参与术式")


func _find_weapon(name: String) -> Dictionary:
	for w in _weapons:
		if String(w["name"]) == name:
			return w
	return {}


func _weapon_has_guard(w: Dictionary) -> bool:
	for s in (w.get("symbols", []) as Array):
		var k := String(s["kind"])
		if k == "shield" or k == "heal":
			return true
	return false


func _finish() -> void:
	print("---")
	print("PATTERNREACH|RESULT %s (checks=%d fails=%d)" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("PATTERNREACH|FAIL|" + what)
