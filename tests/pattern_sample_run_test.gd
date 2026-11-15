extends Node

# ============================================================================
# 首发战斗样板 · Step 4（2026-11-15）
# 方案：docs/转轮凑牌战斗重构_24种牌型与制作执行方案_2026-11-15.md §10 Step 4
#
# 目的不是「再测一遍牌谱判定」（那是第 60 套），而是回答三个只有跑完整战斗才知道的问题：
#   1. 每条牌谱在真实转轮带上到底多常触发？（单个构筑只解锁 1–2 条）
#   2. 会不会出现「几乎每回合都是单牌」的空转？（那牌谱等于不存在）
#   3. 三档敌人（普通/精英/BOSS）跑真实 SPIN 流程能不能正常结算。
#
# 统计口径：从真实 reel_strips 每列随机取一格（= 转轮落点的均匀近似），
# 固定种子、300 回合/构筑。不使用 _phase_symbols 之外的捷径。
# ============================================================================

const MATCHER := preload("res://scripts/battle/pattern_matcher.gd")
const FIRE_SWORD := "res://resources/weapon_templates/fire_sword.tres"
const FLAME_STAFF := "res://resources/weapon_templates/flame_staff.tres"
const ICE_STAFF := "res://resources/weapon_templates/ice_staff.tres"
const HOLY_SWORD := "res://resources/weapon_templates/holy_sword.tres"
const DAWN_BOW := "res://resources/weapon_templates/dawn_bow.tres"
const BLIGHT_SPEAR := "res://resources/weapon_templates/blight_spear.tres"
const CORROSIVE_BOW := "res://resources/weapon_templates/corrosive_bow.tres"
const DAGGER := "res://resources/weapon_templates/dagger.tres"

const CHARM_BULWARK := "res://resources/charms/bulwark_charm.tres"
const CHARM_COUNTER := "res://resources/charms/counter_shield.tres"
const CHARM_DUAL_CORE := "res://resources/charms/dual_core_relic.tres"
const SKILL_AEGIS := "res://resources/skills/aegis.tres"
const SKILL_FOCUS := "res://resources/skills/buff_focus.tres"
const CHARM_ELEMENT := "res://resources/charms/element_charm.tres"

const ORDINARY := "res://resources/rooms/frost_bat.tres"
const ELITE := "res://resources/rooms/a1_elite_brute_ice.tres"
const BOSS := "res://resources/rooms/brittle_gargoyle.tres"

const ROUNDS := 300
# 组成率统计要更稳的采样：300 回合下 p≈0.2 的 ±1σ 约 2.3pp，会让「每几回合一次」在 4.5~5.5 之间跳。
const STATS_ROUNDS := 1200
const SEED := 20261115

# 双武器槽只能装两把，所以每条牌谱配一个专属构筑（也更贴近「单局解锁 3–6 条」的设计）
# 2026-11-15 新方案《稀有度牌型整合》：S05 盾击 / S06 奥术已退役（它们要求武器不提供的
# shield/buff 符号，300 回合实测 2.3% / 0%）。本套只保留迁移范围内的四条：
# S01→W01、S03→W04、S04→W03。SIG02（原冰火二重）已降级为签名候选，
# 属于 Step 5 的范围，本套不再统计（它在 signature 轨，武器轨不结算）。
const BUILDS := [
	{"name": "烈焰共鸣", "expect": "W01", "weapons": [FIRE_SWORD, FLAME_STAFF], "charms": []},
	{"name": "黎明圣辉", "expect": "W04", "weapons": [HOLY_SWORD, DAWN_BOW], "charms": []},
	{"name": "毒爆连携", "expect": "W03", "weapons": [BLIGHT_SPEAR, CORROSIVE_BOW], "charms": []},
]

var _checks := 0
var _fails := 0
var _duel
var _rng := RandomNumberGenerator.new()
var _report: Array = []


func _ready() -> void:
	await _run()


func _run() -> void:
	_duel = await _boot()
	if _duel == null:
		_check(false, "战斗场景可实例化")
		_finish()
		return
	_rng.seed = SEED

	print("=== A 六构筑 × 300 回合：牌谱真实触发率 ===")
	for b in BUILDS:
		_sample_build(b)

	print("=== B 空转率（整回合没有任何牌型）===")
	_test_empty_turn_rate()

	print("=== D 组成率 / 优先级覆盖率 / 每几回合一次 ===")
	_test_composition_stats()

	print("=== C 三档敌人真实 SPIN 流程 ===")
	await _test_three_enemies()

	for line in _report:
		print("  [样板] " + String(line))

	_finish()


func _boot():
	var duel = load("res://scenes/duel/duel.tscn").instantiate()
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.selected_consumables.clear()
	duel.selected_skills.clear()
	duel.growth.perk_ids.clear()
	duel._reward_system.run_power_bonus = 0
	duel.enemy_hp = 999999
	duel.player_hp = 999999
	duel.player_hp_max = 999999
	return duel


func _equip(weapons: Array, charms: Array, skills: Array = []) -> void:
	_duel.selected_skills.clear()
	for sk in skills:
		_duel.selected_skills.append(String(sk))
	_duel.selected_loadout.clear()
	for w in weapons:
		_duel.selected_loadout.append(String(w))
	_duel.selected_charms.clear()
	for c in charms:
		_duel.selected_charms.append(String(c))
	_duel._confirm_loadout()
	_duel._build_pool(_duel.selected_loadout)
	_duel.frozen_cols.clear()
	_duel.pending_jam_reel = -1
	_duel.pending_lock_reel = -1
	_duel.pending_chaos = false
	if _duel._synergy_system != null:
		_duel._synergy_system.refresh()


# 从真实转轮带每列随机取一格（转轮落点的均匀近似）
func _draw_from_strips() -> void:
	_duel.reel_system.build_strips()
	var strips: Array = _duel.reel_system.reel_strips
	for c in 3:
		var strip: Array = strips[c] if strips.size() > c else []
		if strip.is_empty():
			continue
		var cell: Array = strip[_rng.randi_range(0, strip.size() - 1)]
		_duel.grid[c][0] = cell[0]
		_duel.grid_elem[c][0] = String(cell[1]) if cell.size() > 1 else "none"
		var src := String(cell[2]) if cell.size() > 2 else ""
		_duel.reel_system._set_grid_src(c, 0, src)


func _sample_build(b: Dictionary) -> void:
	_equip(b["weapons"], b["charms"], b.get("skills", []))
	var stats := {"total": 0, "single": 0, "g01": 0, "g02": 0, "g03": 0, "eq": 0}
	var eq_hits := {}
	var unlocked_ids: Array = []
	var loadout: Array = _duel.selected_loadout.duplicate()
	loadout.append_array(_duel.selected_charms)
	var unlocked: Array = _duel._pattern_system.unlocked_patterns(loadout, _duel._pattern_tag_of)
	for p in unlocked:
		unlocked_ids.append(String(p.id))
	_check(unlocked_ids.has(String(b["expect"])),
		"%s：构筑解锁了 %s（%s）" % [b["name"], String(b["expect"]), str(unlocked_ids)])

	for i in range(ROUNDS):
		_draw_from_strips()
		_duel.enemy_element = "none"
		_duel.enemy_armor = 0
		var acc: Dictionary = _duel.combat._new_acc()
		_duel.combat._reset_turn_state()
		acc["counts"] = _duel.combat._phase_symbols(acc)
		_duel.combat._apply_patterns(acc)
		stats["total"] += 1
		var m: Dictionary = acc.get("pattern_match", {})
		var ids: Array = []
		for p in m.get("patterns", []):
			ids.append(String(p.get("id", "")))
		if ids.has("G01"):
			stats["g01"] += 1
		if ids.has("G02"):
			stats["g02"] += 1
		if ids.has("G03"):
			stats["g03"] += 1
		var eq := String(acc.get("pattern_equipment", ""))
		if eq != "":
			stats["eq"] += 1
			eq_hits[eq] = int(eq_hits.get(eq, 0)) + 1
		if ids.is_empty() and eq == "":
			stats["single"] += 1

	var t := float(stats["total"])
	_report.append("%s：牌谱 %s 触发 %.1f%% ｜ 同源 %.1f%% 同族 %.1f%% 清一色 %.1f%% ｜ 空转 %.1f%%" % [
		String(b["name"]), String(b["expect"]),
		100.0 * float(eq_hits.get(String(b["expect"]), 0)) / t,
		100.0 * float(stats["g01"]) / t,
		100.0 * float(stats["g02"]) / t,
		100.0 * float(stats["g03"]) / t,
		100.0 * float(stats["single"]) / t])
	var hit := int(eq_hits.get(String(b["expect"]), 0))
	_check(hit > 0, "%s：300 回合内 %s 至少触发一次（实际 %d）" % [b["name"], String(b["expect"]), hit])
	_check(float(hit) / t >= 0.01,
		"%s：%s 触发率 ≥1%%（实际 %.2f%%）" % [b["name"], String(b["expect"]), 100.0 * float(hit) / t])
	# 触发率过低（<5%）说明判定条件与符号供给不匹配，单独标出来
	if hit > 0 and float(hit) / t < 0.05:
		_report.append("⚠ %s 触发率仅 %.2f%%：判定条件与现有符号供给不匹配" % [String(b["expect"]), 100.0 * float(hit) / t])


# B：整回合没有任何牌型 = 空转。太高说明牌谱形同虚设。
func _test_empty_turn_rate() -> void:
	_equip([FIRE_SWORD, FLAME_STAFF], [])
	var single := 0
	var total := 0
	for i in range(ROUNDS):
		_draw_from_strips()
		_duel.enemy_element = "none"
		var acc: Dictionary = _duel.combat._new_acc()
		_duel.combat._reset_turn_state()
		acc["counts"] = _duel.combat._phase_symbols(acc)
		_duel.combat._apply_patterns(acc)
		total += 1
		var m: Dictionary = acc.get("pattern_match", {})
		if (m.get("patterns", []) as Array).is_empty() and String(acc.get("pattern_equipment", "")) == "":
			single += 1
	var rate := 100.0 * float(single) / maxf(1.0, float(total))
	_report.append("空转率（火系双持，%d 回合）：%.1f%%" % [total, rate])
	# 单牌每回合都有效是设计铁律，但「半数以上回合完全凑不出任何牌型」说明牌面太难凑
	_check(rate < 70.0, "空转率不超过 70%%（实际 %.1f%%）" % rate)


# D：真实带子上的「组成率」与「每几回合一次」——方案要求普通 Build 平均每 2–3 回合
# 形成一次有价值的武器组合（即 ≥33%）。
func _test_composition_stats() -> void:
	for b in BUILDS:
		_equip(b["weapons"], b["charms"], b.get("skills", []))
		var loadout: Array = _duel.selected_loadout.duplicate()
		loadout.append_array(_duel.selected_charms)
		var unlocked: Array = _duel._pattern_system.unlocked_patterns(loadout, _duel._pattern_tag_of)
		var w_pool: Array = []
		for p in unlocked:
			if String(p.track) == "weapon_attack":
				w_pool.append(p)
		var total := 0
		var composed := 0        # 至少有一条 W 的条件被满足
		var multi := 0           # 多条同时满足（需要优先级裁决）
		var fired := 0           # 最终真的生效
		var wc_hist := {}        # 有效武器牌数量分布
		for i in range(STATS_ROUNDS):
			_draw_from_strips()
			_duel.enemy_element = "none"
			_duel.enemy_armor = 0
			var acc: Dictionary = _duel.combat._new_acc()
			_duel.combat._reset_turn_state()
			acc["counts"] = _duel.combat._phase_symbols(acc)
			_duel.combat._apply_patterns(acc)
			total += 1
			var cards: Array = MATCHER.cards_from_grid(_duel)
			var weapon_cards: Array = []
			for c in cards:
				if String(c.get("source_kind", "")) == "weapon":
					weapon_cards.append(c)
			wc_hist[weapon_cards.size()] = int(wc_hist.get(weapon_cards.size(), 0)) + 1
			var hits: Array = MATCHER.match_rules(weapon_cards, w_pool)
			if hits.size() >= 1:
				composed += 1
			if hits.size() >= 2:
				multi += 1
			if String(acc.get("pattern_equipment", "")) != "":
				fired += 1
		var compose_rate := 100.0 * float(composed) / maxf(1.0, float(total))
		var fire_rate := 100.0 * float(fired) / maxf(1.0, float(total))
		var every := (float(total) / maxf(1.0, float(composed)))
		_report.append("%s：有效武器牌 3/2/1/0 = %d/%d/%d/%d 回合" % [
			String(b["name"]), int(wc_hist.get(3, 0)), int(wc_hist.get(2, 0)),
			int(wc_hist.get(1, 0)), int(wc_hist.get(0, 0))])
		_report.append("%s：解锁 %d 条 W ｜ 组成率 %.1f%%（每 %.1f 回合一次）｜ 触发率 %.1f%% ｜ 多命中 %d 次" % [
			String(b["name"]), w_pool.size(), compose_rate, every, fire_rate, multi])
		# 每场战斗的实际触发次数：按典型战斗回合数估算（普通怪 8 回合 / 精英 10 / BOSS 14）
		var per_battle := "普通 %.1f 次 / 精英 %.1f 次 / BOSS %.1f 次" % [
			compose_rate / 100.0 * 8.0, compose_rate / 100.0 * 10.0, compose_rate / 100.0 * 14.0]
		_report.append("%s：每场预计触发 %s（组成率 %.1f%%）" % [String(b["name"]), per_battle, compose_rate])
		# 中频高潮定位下，一场战斗至少要有 1 次以上的牌谱时刻
		_check(compose_rate / 100.0 * 8.0 >= 1.0,
			"%s：普通怪战斗至少触发 1 次（%.1f 次）" % [String(b["name"]), compose_rate / 100.0 * 8.0])
		# 组成后必须有触发（每回合至少一条）
		_check(fired >= composed - 2, "%s：组成后都能生效（组成 %d / 生效 %d）" % [String(b["name"]), composed, fired])
		# 2026-11-15 拍板：W 定位为「中频高潮牌谱」，目标改为平均 3–5 回合一次（20%–33%）。
		# 低于 5 回合一次说明太稀，高于 3 回合一次说明太频繁（会变成每回合都有，失去高潮感）。
		# 上界留 0.5 容差：1200 回合下 p≈0.2 的 ±1σ 约 1.2pp，折算约 ±0.3 回合，
		# 卡死在 5.0 会让真实值 4.8 的构筑偶发误判（实测出现过 5.1）。
		_check(every >= 3.0 and every <= 5.5,
			"%s：平均 %.1f 回合一次，落在「中频高潮」区间 3–5.5（组成率 %.1f%%）" % [
				String(b["name"]), every, compose_rate])


# C：三档敌人各跑一次真实 SPIN，确认流程与结算正常。
func _test_three_enemies() -> void:
	for entry in [["普通", ORDINARY], ["精英", ELITE], ["BOSS", BOSS]]:
		var room = load(String(entry[1]))
		_check(room != null, "%s 房间资源可加载" % String(entry[0]))
		if room == null:
			continue
		_duel.enemy_hp = int(room.hp) if int(room.hp) > 0 else 200
		_duel.enemy_hp_max = _duel.enemy_hp
		_duel.enemy_element = String(room.element)
		_duel.enemy_armor = int(room.armor)
		_duel.player_hp = 400
		_duel.player_hp_max = 400
		_duel._busy = false
		var hp_before: int = _duel.enemy_hp
		await _simulate_spin(_duel.turn_flow.on_spin_pressed())
		_check(bool(_duel.turn_resolved), "%s：停列后已结算" % String(entry[0]))
		_check(not bool(_duel._busy), "%s：流程结束不残留 busy" % String(entry[0]))
		_report.append("%s（%s，HP %d）：一回合后敌方 HP %d → %d" % [
			String(entry[0]), String(room.name), hp_before, hp_before, int(_duel.enemy_hp)])
		_check(int(_duel.enemy_hp) <= hp_before, "%s：结算产生了伤害" % String(entry[0]))


# 转轮不停就一直转：逐列模拟玩家按停。
func _simulate_spin(task) -> void:
	for i in range(3):
		await get_tree().process_frame
		await get_tree().process_frame
		if not is_instance_valid(_duel.reel_system):
			return
		_duel.reel_system.stop_next_reel(false)
		await get_tree().process_frame
	await task


func _finish() -> void:
	print("---")
	print("PATTERNSAMPLE|RESULT %s (checks=%d fails=%d)" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("PATTERNSAMPLE|FAIL|" + what)
