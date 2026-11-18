extends SceneTree

# ============================================================================
# 战后三选一 · 平衡探针（headless 独立脚本，不启动 duel）
# 运行：Godot --headless --path . --script res://tests/reward_balance_probe.gd
#
# 目的：用合成快照跑 N 次 Draft，输出可解释的统计，辅助平衡迭代：
#   - 各卡 offer 次数/占比
#   - 不同 HP 段下治疗评分与入选率（验证"低血才高价值"）
#   - 同屏三卡组合重复率（验证多样性）
#   - 硬过滤原因分布
# 注意：这只是算法探针，不是玩家实测；真实选择率需 F6 +遥测事件分析。
# ============================================================================

const TRIALS := 2000

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 20261118
	var composer = load("res://scripts/reward/draft_composer.gd").new(4242)
	var analyzer = load("res://scripts/reward/run_state_analyzer.gd")
	var evaluator = load("res://scripts/reward/reward_evaluator.gd")

	var offer_count := {}
	var combo_count := {}
	var heal_score_by_band := {"low": 0.0, "low_n": 0, "mid": 0.0, "mid_n": 0, "high": 0.0, "high_n": 0}
	var heal_pick_by_band := {"low": 0, "mid": 0, "high": 0}
	var filter_reasons := {}

	for i in range(TRIALS):
		# 合成 HP 段：低/中/高各 1/3
		var band: String = ["low", "mid", "high"][i % 3]
		var ratio: float = {"low": 0.2, "mid": 0.5, "high": 0.9}[band]
		var snap = RunSnapshot.new()
		snap.survival = {"current_hp": int(100 * ratio), "max_hp": 100, "hp_ratio": ratio}
		snap.build_state.build_scores["fire"] = 0

		# 治疗评分按段累计
		var heal_def = load("res://resources/rewards/defs/seed_battle_ready.tres")
		heal_score_by_band[band + "_n"] += 1
		heal_score_by_band[band] += evaluator.score(heal_def, snap)

		var draft = composer.compose(snap, 3, false)
		var ids: Array = []
		for d in draft.rewards:
			ids.append(d.id)
			offer_count[d.id] = int(offer_count.get(d.id, 0)) + 1
			var q: String = d.rarity
			offer_count["__rarity__" + q] = int(offer_count.get("__rarity__" + q, 0)) + 1
			if d.id == "seed_battle_ready":
				heal_pick_by_band[band] += 1
		ids.sort()
		var key: String = ",".join(ids)
		combo_count[key] = int(combo_count.get(key, 0)) + 1

	_report(offer_count, combo_count, heal_score_by_band, heal_pick_by_band, filter_reasons)

	# 展示一次可解释输出样例（Debug.log 在 release 自动静默）
	var demo_snap = RunSnapshot.new()
	demo_snap.survival = {"current_hp": 20, "max_hp": 100, "hp_ratio": 0.2}
	composer.compose(demo_snap, 3, true)
	quit()


func _report(offer: Dictionary, combos: Dictionary, hs: Dictionary, hp: Dictionary, filters: Dictionary) -> void:
	print("=== 战后三选一平衡探针 (%d 次 Draft) ===" % TRIALS)
	print("\n[稀有度 offer 占比（应 common > uncommon > rare > epic）]")
	for q in ["common", "uncommon", "rare", "epic"]:
		var n := int(offer.get("__rarity__" + q, 0))
		if n > 0:
			print("  %-10s %5d  %5.1f%%" % [q, n, 100.0 * n / (TRIALS * 3.0)])
	print("\n[卡片 offer 占比]")
	for id in offer:
		if String(id).begins_with("__rarity__"):
			continue
		print("  %-28s %5d  %5.1f%%" % [id, offer[id], 100.0 * offer[id] / (TRIALS * 3.0)])
	print("\n[治疗入选次数（解耦后应三段接近，系统不再讨好玩家）]")
	for band in ["low", "mid", "high"]:
		var n := int(hs.get(band + "_n", 1))
		var avg := float(hs.get(band, 0.0)) / float(maxi(1, n))
		print("  %-5s 评分均值 %.2f  入选次数 %d" % [band, avg, hp.get(band, 0)])
	print("\n[同屏组合 TOP8（重复率；越低越多样）]")
	var sorted: Array = combos.keys()
	sorted.sort_custom(func(a, b): return combos[a] > combos[b])
	for i in range(mini(8, sorted.size())):
		var k: String = sorted[i]
		print("  %5d  %s" % [combos[k], k])
	print("\n[硬过滤原因] 本探针用合成快照未触发过滤；详细原因见上方 explain 样例（compose debug=true）")
