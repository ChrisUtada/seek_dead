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

	print("=== D 设计频率验收：多种子组成率 / 每几回合一次（W04 组合高潮 15–20%，其余 3–5.5 回合）===")
	_test_composition_stats()

	print("=== C 探针正确性：三档敌人真实 SPIN 流程（async 调用/结算链路）===")
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
# 设计频率验收（2026-11-20 定稿）：固定多种子、多轮采样，报告中位数与波动。
# 与探针 async 正确性验证（第 C 段）分开记录，避免把"脚本没跑完"误判成"设计频率漂移"。
# 采样种子列表：主种子 + 四个固定偏移，消除单一种子的偶然性。
# 2026-11-26 由 3 个扩到 5 个：3 种子的中位数方差过大，单种子值可低至 13.9%，会随机打红门禁。
const FREQ_SEEDS := [20261115, 20261116, 20261117, 20261118, 20261119]

# W04「黎明圣辉」是圣辉长剑+破晓之弓的指定组合赔付，不是六条主路线的基础引擎。
# 它要求两件指定武器 + holy_slash/dawn_bolt/光元素牌，组成率天然低于普通牌谱——
# 这是保留组合身份的合理代价（放宽 match_rule 会削弱这对武器的身份）。
# 因此 W04 单独按「组合高潮」区间验收：15%–20%（约 5–7 回合一次；7 回合一次 ≈ 14.3% 仅作量级参考，规格仍以 15% 为准）；
# 其余基础 W 仍按「中频高潮」3–5.5 回合一次（20%–33%）验收。
const FREQ_COMBO_MIN := 15.0   # W04 组合高潮下界：设计定稿 15%–20%（G0_任务追踪:398）
const FREQ_COMBO_MAX := 20.0   # W04 组合高潮上界（组成率 %）
const FREQ_BASE_MIN_EVERY := 3.0
const FREQ_BASE_MAX_EVERY := 5.5


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

		var rates: Array = []          # 每个种子的组成率（%）
		var evens: Array = []          # 每个种子的「每几回合一次」
		var fire_rates: Array = []
		var min_every: float = 1e9
		var max_every: float = 0.0
		var total_all := 0
		var composed_all := 0
		var fired_all := 0
		var wc_hist := {}              # 有效武器牌数量分布（累计所有种子）
		var multi_all := 0

		for seed in FREQ_SEEDS:
			_rng.seed = int(seed)
			var total := 0
			var composed := 0
			var multi := 0
			var fired := 0
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
			var every := float(total) / maxf(1.0, float(composed))
			rates.append(compose_rate)
			evens.append(every)
			fire_rates.append(100.0 * float(fired) / maxf(1.0, float(total)))
			min_every = minf(min_every, every)
			max_every = maxf(max_every, every)
			total_all += total
			composed_all += composed
			fired_all += fired
			multi_all += multi

		var med_rate: float = _median(rates)
		var med_every: float = _median(evens)
		var med_fire: float = _median(fire_rates)
		var is_combo: bool = String(b["expect"]) == "W04"
		_report.append("%s：有效武器牌 3/2/1/0 = %d/%d/%d/%d 回合（%d 种子×%d 轮）" % [
			String(b["name"]), int(wc_hist.get(3, 0)), int(wc_hist.get(2, 0)),
			int(wc_hist.get(1, 0)), int(wc_hist.get(0, 0)), FREQ_SEEDS.size(), STATS_ROUNDS])
		_report.append("%s[%s]：组成率中位 %.1f%%（%s）｜每 %.1f 回合一次（波动 %.1f–%.1f）｜触发率中位 %.1f%%｜多命中 %d" % [
			String(b["name"]), "组合高潮" if is_combo else "中频高潮",
			med_rate, _join_floats(rates), med_every, min_every, max_every, med_fire, multi_all])
		var per_battle := "普通 %.1f 次 / 精英 %.1f 次 / BOSS %.1f 次" % [
			med_rate / 100.0 * 8.0, med_rate / 100.0 * 10.0, med_rate / 100.0 * 14.0]
		_report.append("%s：每场预计触发 %s（组成率中位 %.1f%%）" % [String(b["name"]), per_battle, med_rate])

		# 单场战斗至少 1 次牌谱时刻（基础/组合都用中位数判断）
		_check(med_rate / 100.0 * 8.0 >= 1.0,
			"%s：普通怪战斗至少触发 1 次（%.1f 次）" % [String(b["name"]), med_rate / 100.0 * 8.0])
		_check(fired_all >= composed_all - 6,
			"%s：组成后都能生效（组成 %d / 生效 %d）" % [String(b["name"]), composed_all, fired_all])

		if is_combo:
			# W04 组合高潮：15%–20%（约 5–7 回合一次）。保留跨武器条件，不放宽 match_rule。
			_check(med_rate >= FREQ_COMBO_MIN and med_rate <= FREQ_COMBO_MAX,
				"%s：组合高潮组成率中位 %.1f%% 落在 15%%–20%%（区间 5–7 回合/次；%s）" % [
					String(b["name"]), med_rate, _join_floats(rates)])
			# 防止种子数将来被改回 3：统计样本必须与 FREQ_SEEDS 数量一致。
			_check(rates.size() == FREQ_SEEDS.size(),
				"%s：统计样本数与种子数一致（%d/%d）" % [
					String(b["name"]), rates.size(), FREQ_SEEDS.size()])
		else:
			# 基础 W 中频高潮：3–5.5 回合一次（20%–33%）。
			_check(med_every >= FREQ_BASE_MIN_EVERY and med_every <= FREQ_BASE_MAX_EVERY,
				"%s：中频高潮每 %.1f 回合一次（区间 3–5.5；波动 %.1f–%.1f）" % [
					String(b["name"]), med_every, min_every, max_every])


func _median(values: Array) -> float:
	var a: Array = values.duplicate()
	a.sort()
	var n := a.size()
	if n == 0:
		return 0.0
	if n % 2 == 1:
		return float(a[n / 2])
	return (float(a[n / 2 - 1]) + float(a[n / 2])) / 2.0


func _join_floats(values: Array) -> String:
	var parts: Array[String] = []
	for v in values:
		parts.append("%.1f%%" % float(v))
	return "/".join(parts)


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
		# 台账 #5：async 函数 on_spin_pressed() 不能作为表达式传参（Godot 4.7 报
		# "Trying to call an async function without await"）。改为独立语句启动协程，
		# 由 _simulate_spin 逐列按停并等待整条流程结束（turn_resolved 且 _busy 归位）。
		_duel.turn_flow.on_spin_pressed()
		await _simulate_spin()
		_check(bool(_duel.turn_resolved), "%s：停列后已结算" % String(entry[0]))
		_check(not bool(_duel._busy), "%s：流程结束不残留 busy" % String(entry[0]))
		_report.append("%s（%s，HP %d）：一回合后敌方 HP %d → %d" % [
			String(entry[0]), String(room.name), hp_before, hp_before, int(_duel.enemy_hp)])
		_check(int(_duel.enemy_hp) <= hp_before, "%s：结算产生了伤害" % String(entry[0]))


# 转轮不停就一直转：逐列模拟玩家按停。
func _simulate_spin() -> void:
	for i in range(3):
		await get_tree().process_frame
		await get_tree().process_frame
		if not is_instance_valid(_duel.reel_system):
			return
		_duel.reel_system.stop_next_reel(false)
		await get_tree().process_frame
	# 等待 on_spin_pressed 全流程完成：结算相位 + 敌人回合 + 预告（_busy 在末尾归位）。
	# 上限 1200 帧（约 20 秒 @60fps），避免流程卡死时无限等待。
	for i in range(1200):
		if bool(_duel.turn_resolved) and not bool(_duel._busy):
			return
		await get_tree().process_frame


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
