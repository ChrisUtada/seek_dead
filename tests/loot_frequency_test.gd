extends Node

# ============================================================================
# 四级品质战利品 · Step 2 · 品质与转轮频率解耦 · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/loot_frequency_test.tscn
#
# 覆盖（docs/四级品质战利品与大奖池_分步执行计划_2026-11-12.md Step 2）：
# ① 格数只由聚合权重决定：<2 → 2 格，[2,4) → 3 格，≥4 → 4 格；
# ② 同一 Build 仅替换物品 rarity（common/uncommon/rare/epic），带子逐格完全相同；
# ③ 旧「rare/epic 非伤害符号封顶 2 格」已移除：火焰剑的「燃」(权重5) = 4 格，
#    寒冰刃的「霜」(权重3) = 3 格——与同权重 common 物品占格一致；
# ④ 符号灌注预览（_symbol_cells / symbol_infusions）不读 rarity，+1 权重仍按档位增格；
# ⑤ 主动减带仍按原规则 -1 格（保底 1 格），预览与实际带子一致；
# ⑥ 熟练/铭印只改攻击、命中、权重，不写物品 rarity；调律增重后格数按同一规则上涨。
# 测试在隔离 APPDATA 下运行；结束还原 meta，不触碰真实存档与 .tres。
# ============================================================================

const FIRE_SWORD := "res://resources/weapon_templates/fire_sword.tres"
const FROST_BLADE := "res://resources/weapon_templates/frost_blade.tres"
const FIRE_SLASH := "res://resources/symbols/fire_slash.tres"
const BURN := "res://resources/symbols/burn.tres"
const FROST := "res://resources/symbols/frost.tres"

var _checks := 0
var _fails := 0
var _save_backup := {}


func _ready() -> void:
	_save_backup = SaveSystem.load_lobby_data().duplicate(true)
	await _run()
	SaveSystem.save_lobby_data(_save_backup)
	SaveSystem.flush_lobby_data()
	print("---")
	print("LOOTFREQ|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	await get_tree().process_frame
	var duel: DuelController = await _boot()
	_test_weight_tiers()
	_test_rarity_invariance(duel)
	_test_old_cap_removed(duel)
	_test_infusion_preview(duel)
	_test_mastery_keeps_rarity(duel)
	_test_trim_still_works(duel)


func _boot() -> DuelController:
	var duel: DuelController = load("res://scenes/duel/duel.tscn").instantiate()
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.selected_loadout.assign([FIRE_SWORD, FROST_BLADE])
	duel.selected_consumables.clear()
	duel.selected_charms.clear()
	duel.selected_skills.clear()
	duel._confirm_loadout()
	duel.growth.perk_ids.clear()
	duel._reward_system.run_power_bonus = 0
	duel.reel_system._timer.stop()
	duel.pending_jam_reel = -1
	duel.pending_lock_reel = -1
	duel.pending_chaos = false
	duel.pending_auto_stop = false
	duel.frozen_cols.clear()
	duel._trim.reset_run()
	return duel


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("LOOTFREQ|FAIL|" + msg)


# ① 权重档位：类型不参与，只有权重决定格数
func _test_weight_tiers() -> void:
	_check(ReelSystem.cells_for(1.0) == 2, "权重 1 → 2 格")
	_check(ReelSystem.cells_for(1.9) == 2, "权重 1.9 → 2 格")
	_check(ReelSystem.cells_for(2.0) == 3, "权重 2 → 3 格")
	_check(ReelSystem.cells_for(3.9) == 3, "权重 3.9 → 3 格")
	_check(ReelSystem.cells_for(4.0) == 4, "权重 4 → 4 格")
	_check(ReelSystem.cells_for(9.0) == 4, "权重 9 → 4 格（封顶 4）")


# ② 只改 rarity，带子逐格不变
func _test_rarity_invariance(duel: DuelController) -> void:
	duel._build_pool(duel.selected_loadout)
	var baseline := _strip_signature(duel)
	var baseline_len: int = duel.reel_system.reel_strips[0].size()
	for rarity in ["common", "uncommon", "rare", "epic"]:
		_set_all_rarity(duel, String(rarity))
		var sig := _strip_signature(duel)
		var len_ok: bool = duel.reel_system.reel_strips[0].size() == baseline_len
		_check(sig == baseline, "全员 rarity=%s 时带子逐格不变" % rarity)
		_check(len_ok, "全员 rarity=%s 时带长不变" % rarity)
	duel._build_pool(duel.selected_loadout)   # 还原真实 rarity


# ③ 旧封顶移除后的真实格数（单件装备携带、无外部加成）
func _test_old_cap_removed(duel: DuelController) -> void:
	# 单武器：火焰剑（rare，燃 权重5 / 火斩 权重3）
	duel.selected_loadout.assign([FIRE_SWORD])
	duel._build_pool(duel.selected_loadout)
	var rows := _compose_rows(duel)
	_check(int(rows.get(BURN, -1)) == 4, "火焰剑「燃」权重5 = 4 格（旧封顶为 2）")
	_check(int(rows.get(FIRE_SLASH, -1)) == 3, "火焰剑「火斩」权重3 = 3 格")
	# 单武器：寒冰刃（rare，霜 权重3）
	duel.selected_loadout.assign([FROST_BLADE])
	duel._build_pool(duel.selected_loadout)
	rows = _compose_rows(duel)
	_check(int(rows.get(FROST, -1)) == 3, "寒冰刃「霜」权重3 = 3 格（旧封顶为 2）")
	# 同权重 common 物品不应更少格：同种子比较 rare / common 的实际带子
	duel.selected_loadout.assign([FIRE_SWORD])
	duel._build_pool(duel.selected_loadout)
	var rare_burn: int = int(_compose_rows(duel).get(BURN, -1))
	duel.reel_system.build_strips()
	var rare_count: int = _strip_cells_for(duel, BURN, "fire")
	_set_all_rarity(duel, "common")
	duel.reel_system.build_strips()
	var common_count: int = _strip_cells_for(duel, BURN, "fire")
	_check(rare_count == common_count and rare_count > 0,
		"火焰剑 rarity=rare / common 时「燃」实际格数相同（%d vs %d）" % [rare_count, common_count])
	_check(rare_burn == 4, "火焰剑「燃」理论格数 4（旧封顶为 2）")
	duel._build_pool(duel.selected_loadout)


# ④ 灌注预览不读 rarity；+1 权重跨档位时真实增格
func _test_infusion_preview(duel: DuelController) -> void:
	duel.selected_loadout.assign([FIRE_SWORD])
	duel._build_pool(duel.selected_loadout)
	var rs = duel._reward_system
	var slash: SymbolData = load(FIRE_SLASH)
	_set_all_rarity(duel, "common")
	var common_cells: int = rs._symbol_cells(slash, 0.0)
	_set_all_rarity(duel, "epic")
	var epic_cells: int = rs._symbol_cells(slash, 0.0)
	_check(common_cells == epic_cells, "灌注预览格数与 rarity 无关（%d vs %d）" % [common_cells, epic_cells])
	_check(common_cells == 3, "火斩权重3 = 3 格")
	_check(rs._symbol_cells(slash, 1.0) == 4, "灌注 +1 权重后真实增到 4 格")
	var cands: Array = rs.symbol_infusions()
	_check(not cands.is_empty(), "存在可增格的灌注候选")
	var bad := 0
	for c in cands:
		if int(c["after"]) <= int(c["before"]):
			bad += 1
	_check(bad == 0, "灌注候选全部真实增格")
	duel._build_pool(duel.selected_loadout)


# ⑥ 熟练/铭印不写 rarity；调律按权重规则增格
func _test_mastery_keeps_rarity(duel: DuelController) -> void:
	duel.selected_loadout.assign([FROST_BLADE])
	duel._build_pool(duel.selected_loadout)
	duel.mastery.reset_run()
	var rarity_before := String((load(FROST_BLADE) as WeaponData).rarity)
	var frost_before: int = int(_compose_rows(duel).get(FROST, -1))
	_check(frost_before == 3, "调律前「霜」= 3 格")
	_check(duel.mastery.choose(FROST_BLADE, "tune", FROST), "调律选择成功")
	duel._build_pool(duel.selected_loadout)
	_check(int(_compose_rows(duel, {}, duel.mastery.tune_map()).get(FROST, -1)) == 4, "调律 +1 权重后「霜」= 4 格（同一格数规则）")
	_check(duel.mastery.choose(FROST_BLADE, "forge"), "锋铸选择成功")
	duel._build_pool(duel.selected_loadout)
	_check(String((load(FROST_BLADE) as WeaponData).rarity) == rarity_before,
		"熟练/铭印不修改物品原始品质（仍为 %s）" % rarity_before)
	duel.mastery.reset_run()


# ⑤ 减带仍 -1 格，且预览与实际一致
func _test_trim_still_works(duel: DuelController) -> void:
	duel.selected_loadout.assign([FIRE_SWORD, FROST_BLADE])
	duel._build_pool(duel.selected_loadout)
	duel._trim.reset_run()
	var cands: Array = duel._trim.candidates()
	_check(not cands.is_empty(), "减带存在合法候选")
	if cands.is_empty():
		return
	var cand: Dictionary = cands[0]
	var key := String(cand["key"])
	var shown: Dictionary = duel._trim.preview(cand)
	var expected: int = int(shown.get("after_target", -1))
	_check(int(shown.get("before_target", -2)) - expected == 1, "减带预览：目标符号恰少 1 格")
	duel._trim.apply(cand)
	duel.reel_system.build_strips()
	var after_cells: int = _cells_for_key(duel, key)
	var mult: int = _strip_size(duel) / maxi(1, _compose_cells_total(duel, duel._trim.trimmed))
	_check(after_cells > 0, "减带后符号仍有格（保底 1）")
	_check(after_cells == expected * maxi(1, mult),
		"减带实际 %s：%d 格/份（预期 %d）" % [key, after_cells / maxi(1, mult), expected])
	_check(int(shown.get("after_cells", -1)) == _compose_cells_total(duel, duel._trim.trimmed),
		"减带预览的带长与实际建带一致")


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _set_all_rarity(duel: DuelController, rarity: String) -> void:
	for it in duel.pool_items:
		it["rarity"] = rarity


# 固定种子下的完整带子签名（路径|元素|来源），逐格比较
func _strip_signature(duel: DuelController) -> String:
	seed(7301)
	duel.reel_system.build_strips()
	var parts: Array[String] = []
	for e in duel.reel_system.reel_strips[0]:
		parts.append("%s|%s|%s" % [String(e[0].resource_path), String(e[1]), String(e[2])])
	return "\n".join(parts)


# ReelPreview 口径下「符号路径 → 格数」
func _compose_rows(duel: DuelController, trim: Dictionary = {}, tune: Dictionary = {}) -> Dictionary:
	var comp: Dictionary = ReelPreview.compose(
		duel.selected_loadout, duel.selected_skills, duel.selected_charms,
		duel.room_element_mult, duel._reward_system.run_symbol_bonus, duel.deprived_level,
		duel.pending_chaos, int(duel.boss_trash), tune, {}, trim)
	var out := {}
	for r in comp["rows"]:
		var p := String(r["path"])
		out[p] = int(out.get(p, 0)) + int(r["cells"])
	return out


func _compose_cells_total(duel: DuelController, trim: Dictionary = {}) -> int:
	var comp: Dictionary = ReelPreview.compose(
		duel.selected_loadout, duel.selected_skills, duel.selected_charms,
		duel.room_element_mult, duel._reward_system.run_symbol_bonus, duel.deprived_level,
		duel.pending_chaos, int(duel.boss_trash), {}, {}, trim)
	return int(comp["total_cells"])


func _strip_size(duel: DuelController) -> int:
	return duel.reel_system.reel_strips[0].size() if not duel.reel_system.reel_strips.is_empty() else 0


func _strip_cells_for(duel: DuelController, path: String, elem: String) -> int:
	var n := 0
	for e in duel.reel_system.reel_strips[0]:
		if String(e[0].resource_path) == path and String(e[1]) == elem:
			n += 1
	return n


func _cells_for_key(duel: DuelController, key: String) -> int:
	var parts := key.split("|", true, 1)
	var path := String(parts[0])
	var elem := String(parts[1]) if parts.size() > 1 else "none"
	return _strip_cells_for(duel, path, elem)
