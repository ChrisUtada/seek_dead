extends Node

# ============================================================================
# T4 前置（2026-11-24）：统一伤害事件队列结构验收
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t4_damage_queue_test.tscn
#
# 口径：只做结构断言 + 固定种子不变，不做截图对比；checks 数不固定，只认 fails=0。
# 不启动完整战斗：直调 apply_enemy_damage / tick_status 构造事件。
# 隔离：必须由外部覆盖 APPDATA 到临时目录后再运行。
# ============================================================================

class KillProbeAnimator:
	var real
	var kill_calls: int = 0
	var bar_ratio_at_kill: float = 1.0

	func setup(p_hud) -> void:
		real.setup(p_hud)

	func play_attack(attacker: String, target: String, with_slash: bool = false) -> void:
		real.play_attack(attacker, target, with_slash)

	func play_enemy_attack() -> void:
		real.play_enemy_attack()

	func play_counter(kind: String) -> void:
		real.play_counter(kind)

	func enemy_hit_shake() -> void:
		real.enemy_hit_shake()

	func play_kill(skip: bool = false):
		kill_calls += 1
		# 死亡演出开始时，血条必须已被回放走到 0（C2 顺序锁）。
		bar_ratio_at_kill = real.hud.enemy_hp_bar.ratio
		return real.play_kill(skip)


var _fails := 0
var _checks := 0
var _duel: DuelController
var _probe: KillProbeAnimator


func _ready() -> void:
	await get_tree().process_frame
	SaveSystem.reset_lobby_data()
	_duel = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(_duel)
	await get_tree().process_frame
	await get_tree().process_frame
	_duel.demo_config.enabled = false
	_duel._confirm_loadout()
	await get_tree().process_frame
	_probe = KillProbeAnimator.new()
	_probe.real = _duel.hud.animator
	_duel.hud.animator = _probe
	await _run()
	print("T4DQ|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _fresh(hp: int) -> void:
	_duel.enemy_hp = hp
	_duel.enemy_armor = 0
	_duel.enemy_status.clear()
	_duel.enemy_status_pending.clear()
	_duel.damage_ledger.begin(1, hp)


func _samples(match_kind: String) -> String:
	var parts: Array[String] = []
	for e in _duel.damage_ledger.events:
		if match_kind == "" or String(e["kind"]) == match_kind:
			parts.append("%s/%d/%d→%d" % [String(e["kind"]), int(e["amount"]), int(e["before"]), int(e["after"])])
	return " ".join(parts)


func _run() -> void:
	await _case1_single_hit()
	await _case2_two_dots()
	await _case3_burst()
	await _case4_conservation()
	await _case5_lethal_order()
	await _case6_fixed_seed()
	await _case7_skip_bar()
	await _case8_tag_and_purity()
	await _case9_single_popup()


# A3：单段攻击只弹一次飘字，不得叠加第二条总伤害
func _case9_single_popup() -> void:
	_fresh(100)
	_duel.combat.apply_enemy_damage(17, false)
	var ev: Array = _duel.damage_ledger.events.duplicate(true)
	_check(ev.size() == 1, "A3 构造单段事件（实测 %d）" % ev.size())
	var before: int = _duel.hud.damage_pop_count
	await _duel.hud.play_damage_events(ev, _duel.enemy_hp_max, false)
	var replay_pops: int = _duel.hud.damage_pop_count - before
	_check(replay_pops == ev.size(), "A3 单段回放飘字次数 == 事件数（实测 %d）" % replay_pops)
	# 总伤害大数字：恰好 1 段时不得再弹（A1 的判定接缝）。
	_check(not _duel.combat._should_show_total_popup(1), "A3 单段时不再弹总伤害大数字")
	_check(_duel.combat._should_show_total_popup(0), "A3 0 段（纯破甲/空转）仍弹总伤害")
	# B2：多段（2 段）时判定为 false，且回放飘字总数 == 事件数（不叠总伤害）
	_check(not _duel.combat._should_show_total_popup(2), "B2 2 段时不叠总伤害")
	_fresh(200)
	_duel.combat.apply_enemy_damage(17, false)
	_duel.enemy_status["burn"] = 1
	_duel.combat.tick_status()
	var multi: Array = _duel.damage_ledger.events.duplicate(true)
	_check(multi.size() == 2, "B2 构造双段事件（实测 %d）" % multi.size())
	var before2: int = _duel.hud.damage_pop_count
	await _duel.hud.play_damage_events(multi, _duel.enemy_hp_max, false)
	var multi_pops: int = _duel.hud.damage_pop_count - before2
	_check(multi_pops == multi.size(), "B2 双段回放飘字总数 == 事件数（实测 %d）" % multi_pops)


# A6-① 每条 dot/dot_burst 事件 tag 非空；hit/pierce 允许为空
func _case8_tag_and_purity() -> void:
	_fresh(300)
	_duel.combat.apply_enemy_damage(17, false)
	_duel.enemy_status["burn"] = 3
	_duel.enemy_status["poison"] = 4
	_duel.combat.tick_status()
	var tags_ok := true
	for e in _duel.damage_ledger.events:
		var k: String = String(e["kind"])
		if (k == "dot" or k == "dot_burst") and String(e["tag"]) == "":
			tags_ok = false
	_check(tags_ok, "A6-① dot/dot_burst 事件 tag 均非空（%s）" % _samples(""))

	# A6-② 回放前后 HP / 护甲 / game_state / 战利品 RNG seed 完全不变
	var hp_before: int = _duel.enemy_hp
	var armor_before: int = _duel.enemy_armor
	var state_before = _duel.game_state
	var seed_before: int = _duel._reward_system._loot.seed_value()
	var ev: Array = _duel.damage_ledger.drain()
	await _duel.hud.play_damage_events(ev, _duel.enemy_hp_max, true)
	_check(_duel.enemy_hp == hp_before, "A6-② 回放不改 enemy_hp（%d）" % hp_before)
	_check(_duel.enemy_armor == armor_before, "A6-② 回放不改 enemy_armor（%d）" % armor_before)
	_check(_duel.game_state == state_before, "A6-② 回放不改 game_state")
	_check(_duel._reward_system._loot.seed_value() == seed_before, "A6-② 回放不改战利品 RNG seed（%d）" % seed_before)


# 1 单段攻击：1 条事件，before/after 与实际 HP 差一致
func _case1_single_hit() -> void:
	_fresh(100)
	_duel.combat.apply_enemy_damage(17, false)
	var ev: Array = _duel.damage_ledger.events
	_check(ev.size() == 1, "用例1 单段攻击 → 1 条事件（实测 %d：%s）" % [ev.size(), _samples("")])
	if ev.is_empty():
		return
	_check(String(ev[0]["kind"]) == "hit", "用例1 kind=hit（实测 %s）" % String(ev[0]["kind"]))
	_check(int(ev[0]["before"]) - int(ev[0]["after"]) == int(ev[0]["amount"]), "用例1 before-after == amount")
	_check(int(ev[0]["after"]) == _duel.enemy_hp, "用例1 after == 实际 enemy_hp")


# 2 双状态 DoT：2 条、kind=dot、tag 不同、链式守恒；改前红就看这三条
func _case2_two_dots() -> void:
	_fresh(200)
	_duel.enemy_status["burn"] = 3
	_duel.enemy_status["poison"] = 4
	var dot: int = _duel.combat.tick_status()
	var ev: Array = _duel.damage_ledger.events
	_check(ev.size() == 2, "用例2 双状态 DoT → 2 条事件（实测 %d：%s）" % [ev.size(), _samples("")])
	if ev.size() >= 2:
		_check(String(ev[0]["kind"]) == "dot" and String(ev[1]["kind"]) == "dot", "用例2 两条 kind 都是 dot")
		_check(String(ev[0]["tag"]) != String(ev[1]["tag"]), "用例2 两条 tag 不同（%s / %s）" % [String(ev[0]["tag"]), String(ev[1]["tag"])])
		_check(int(ev[0]["after"]) == int(ev[1]["before"]), "用例2 e0.after == e1.before（链不断）")
	_check(dot > 0 and 200 - dot == _duel.enemy_hp, "用例2 tick_status 返回值与真实 HP 差一致（dot=%d，hp=%d）" % [dot, _duel.enemy_hp])


# 3 爆发：dot_burst 紧随该状态的 dot
func _case3_burst() -> void:
	_fresh(500)
	_duel.enemy_status["poison"] = 12
	var dot: int = _duel.combat.tick_status()
	var ev: Array = _duel.damage_ledger.events
	var burst_idx: int = -1
	for i in range(ev.size()):
		if String(ev[i]["kind"]) == "dot_burst":
			burst_idx = i
			break
	_check(burst_idx >= 0, "用例3 出现 dot_burst 事件（%s）" % _samples(""))
	if burst_idx > 0:
		_check(String(ev[burst_idx - 1]["kind"]) == "dot", "用例3 dot_burst 紧随同状态 dot")
		_check(String(ev[burst_idx]["tag"]).contains("爆发"), "用例3 爆发 tag 带「爆发」")
	_check(dot == 500 - _duel.enemy_hp, "用例3 含爆发的总数守恒（dot=%d）" % dot)


# 4 链路守恒：首条 before == 回合开始 HP；末条 after == enemy_hp；total() == sum(amount)
func _case4_conservation() -> void:
	_fresh(300)
	_duel.combat.apply_enemy_damage(23, false)
	_duel.enemy_status["burn"] = 5
	_duel.enemy_status["poison"] = 6
	_duel.combat.tick_status()
	var ev: Array = _duel.damage_ledger.events
	_check(ev.size() >= 3, "用例4 攻击 + 双 DoT 至少 3 条（实测 %d：%s）" % [ev.size(), _samples("")])
	if ev.is_empty():
		return
	_check(int(ev[0]["before"]) == 300, "用例4 first.before == 回合开始 HP（300）")
	_check(int(ev[ev.size() - 1]["after"]) == _duel.enemy_hp, "用例4 last.after == enemy_hp（%d）" % _duel.enemy_hp)
	var sum := 0
	for e in ev:
		sum += int(e["amount"])
	_check(_duel.damage_ledger.total() == sum, "用例4 total() == sum(amount)（%d）" % sum)
	_check(300 - sum == _duel.enemy_hp, "用例4 起始 HP - sum == 实际 HP")
	# 真实事件样例（攻击 + 2 个 DoT）打印一次，供回报引用。
	print("T4DQ|SAMPLE " + _samples(""))


# 5 致死顺序：致死段 after<=0；play_kill 时血条已走到 0
func _case5_lethal_order() -> void:
	_fresh(1)
	_probe.kill_calls = 0
	_duel.enemy_status["burn"] = 5
	var dot: int = _duel.combat.tick_status()
	var ev: Array = _duel.damage_ledger.events
	_check(not ev.is_empty() and int(ev[ev.size() - 1]["after"]) <= 0,
		"用例5 致死段 after<=0（%s）" % _samples(""))
	await _duel.hud.play_damage_events(_duel.damage_ledger.drain(), _duel.enemy_hp_max, true)
	_check(_duel.hud.enemy_hp_bar.ratio < 0.01, "用例5 回放后 bar 比例=0（实测 %.3f）" % _duel.hud.enemy_hp_bar.ratio)
	# 真实击杀入口：沿用 t0_death_seq 的按停驱动，验证 play_kill 时 bar 已在 0
	for attempt in 6:
		if _duel.game_state == _duel.FlowState.WON and _probe.kill_calls > 0:
			break
		_duel.game_state = _duel.FlowState.PLAYING
		_duel._busy = false
		_duel.in_interroom = false
		_duel.enemy_hp = 1
		_duel.enemy_armor = 0
		_duel.player_hp = _duel.player_hp_max
		_duel.presentation_skip = true
		_duel._on_spin_pressed()
		for _i in 30:
			if _duel.reel_system.spinning:
				break
			await get_tree().process_frame
		for col in 3:
			_duel.reel_system.stop_next_reel()
			for _w in 40:
				if _duel.reel_system.reel_stopped[col]:
					break
				await get_tree().process_frame
		for _i in 60:
			await get_tree().create_timer(0.05).timeout
			if _duel.game_state == _duel.FlowState.WON and _probe.kill_calls > 0:
				break
	_check(_duel.game_state == _duel.FlowState.WON, "用例5 真实入口击杀推进到 WON")
	_check(_probe.kill_calls >= 1, "用例5 play_kill 已调用（%d 次）" % _probe.kill_calls)
	if _probe.kill_calls > 0:
		_check(_probe.bar_ratio_at_kill < 0.01, "用例5 play_kill 时血条已是 0（实测 %.3f）" % _probe.bar_ratio_at_kill)


# 6 固定种子：同一 seed 两次 amount 序列相同；战利品 RNG seed 前后不变
func _case6_fixed_seed() -> void:
	var seed_before: int = _duel._reward_system._loot.seed_value()
	var seqs: Array = []
	for _run_i in 2:
		seed(4242)
		_fresh(400)
		_duel.combat.apply_enemy_damage(19, false)
		_duel.enemy_status["burn"] = 4
		_duel.enemy_status["poison"] = 5
		_duel.combat.tick_status()
		var amounts: Array = []
		for e in _duel.damage_ledger.events:
			amounts.append(int(e["amount"]))
		seqs.append(amounts)
	_check(seqs.size() == 2 and seqs[0] == seqs[1], "用例6 同种子 amount 序列相同（%s vs %s）" % [str(seqs[0]), str(seqs[1])])
	_check(_duel._reward_system._loot.seed_value() == seed_before, "用例6 战利品 RNG seed_value() 前后不变（%d）" % seed_before)


# 7 跳过：skip=true 时 bar 终值仍等于真实比例
func _case7_skip_bar() -> void:
	_fresh(100)
	_duel.combat.apply_enemy_damage(25, false)
	_duel.enemy_status["burn"] = 1
	_duel.combat.tick_status()
	var hp_now: int = _duel.enemy_hp
	await _duel.hud.play_damage_events(_duel.damage_ledger.drain(), _duel.enemy_hp_max, true)
	var expect: float = clampf(float(hp_now) / float(maxi(1, _duel.enemy_hp_max)), 0.0, 1.0)
	_check(absf(_duel.hud.enemy_hp_bar.ratio - expect) < 0.02,
		"用例7 skip 后 bar 终值 == 真实 HP 比例（实测 %.3f，期望 %.3f）" % [_duel.hud.enemy_hp_bar.ratio, expect])
	_check(_duel.enemy_hp == hp_now, "用例7 回放不改 enemy_hp（%d）" % _duel.enemy_hp)
