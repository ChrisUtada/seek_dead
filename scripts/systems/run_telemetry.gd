extends RefCounted

# M1-06 局内遥测（真人评测指标）：只在内存累计，不落盘、不消耗随机数、不影响任何结算。
# 指标：旋转耗时、三连率、意图出手/格挡、TTK、承伤、武器替换率、奖励选择率。
# 入口：controller._telemetry（每局 _reset_run_state 时清零）；局末/战败打印一行 summary。

var spins := 0                  # 完成旋转次数
var spin_seconds := 0.0         # 累计旋转耗时（秒）
var turns := 0                  # 已结算回合（一次 evaluate = 一回）
var triples := 0                # 三连回合数
var enemy_attacks := 0          # 敌人出手次数（意图落地次数）
var damage_taken := 0           # 实际承伤
var damage_blocked := 0         # 护盾格挡量
var weapon_swaps := 0           # 武器替换次数（奖励/BOSS/商店）
var rewards_shown := 0          # 展示过的奖励卡总数（算「奖励选择率」分母）
var reward_picks: Dictionary = {}   # reward id -> 选择次数
var room_times: Array = []      # 每房通关耗时（秒）= TTK 观测
# P1 目押：目标停中率与输入缓冲（只读统计，不参与结算）
var target_symbol := ""         # 本局声明的目标符号 resource_path
var stop_total := 0             # 玩家主动按停列数（不含敌人夺轮）
var target_hits := 0            # 其中落在目标符号的列数
var forced_stops := 0           # 敌人夺轮/机制替玩家停的列数
var buffer_queues := 0          # 进入一拍输入缓冲的次数
var stop_outcomes: Dictionary = {}   # target/normal/miss/jam/lock/forced -> 次数
var stop_kinds: Dictionary = {}      # G7-D：玩家主动停中的符号类别 damage/shield/heal/special/status/buff/trash -> 次数
var consumable_uses: Dictionary = {} # G7-D：消耗品 effect -> 使用次数（多对策模式记录真实选择）
# 2026-11-11 Step 1：三连收益校准专用（只统计，不参与结算）
var counter_triples := 0        # 克制元素三连触发的核爆次数
var counter_burst_damage := 0   # 核爆穿透伤害合计
var heal_total := 0             # 实际回复 HP 合计（不含溢出）
var heal_overflow_shield := 0   # 治疗三连溢出转护盾合计

var _spin_started := -1
var _room_started := -1


func reset() -> void:
	spins = 0
	spin_seconds = 0.0
	turns = 0
	triples = 0
	enemy_attacks = 0
	damage_taken = 0
	damage_blocked = 0
	weapon_swaps = 0
	rewards_shown = 0
	reward_picks = {}
	room_times = []
	target_symbol = ""
	stop_total = 0
	target_hits = 0
	forced_stops = 0
	buffer_queues = 0
	stop_outcomes = {}
	stop_kinds = {}
	consumable_uses = {}
	counter_triples = 0
	counter_burst_damage = 0
	heal_total = 0
	heal_overflow_shield = 0
	_spin_started = -1
	_room_started = -1


func spin_start() -> void:
	_spin_started = Time.get_ticks_msec()


func spin_end() -> void:
	if _spin_started >= 0:
		spin_seconds += float(Time.get_ticks_msec() - _spin_started) / 1000.0
		spins += 1
		_spin_started = -1


func on_turn(triple: bool) -> void:
	turns += 1
	if triple:
		triples += 1


# P1：一次落子（玩家/机制）。forced=true 仅用于敌人夺轮等非玩家目押。
# kind = 符号类别（G7-D 多对策模式记录玩家实际选择）。
func on_stop(path: String, target: String, outcome: String, forced: bool, kind: String = "") -> void:
	stop_outcomes[outcome] = int(stop_outcomes.get(outcome, 0)) + 1
	if forced:
		forced_stops += 1
		return
	stop_total += 1
	if kind != "":
		stop_kinds[kind] = int(stop_kinds.get(kind, 0)) + 1
	if target != "" and path == target:
		target_hits += 1


# G7-D：记录消耗品实际使用（effect = heal/purify/cleanse/assault/armor_shred/...）。
func on_consumable(effect: String) -> void:
	if effect == "":
		return
	consumable_uses[effect] = int(consumable_uses.get(effect, 0)) + 1


func on_buffer_queued() -> void:
	buffer_queues += 1


func on_player_hit(eff: int, blocked: int, dealt: int) -> void:
	enemy_attacks += 1
	damage_blocked += blocked
	damage_taken += dealt


# Step 1：克制元素三连核爆（穿透直击）— 只统计伤害，不改结算。
func on_counter_burst(damage: int) -> void:
	counter_triples += 1
	counter_burst_damage += damage


# Step 1：治疗实际入账与三连溢出转盾— 只统计，不改结算。
func on_heal(hp_gain: int, overflow_shield: int) -> void:
	heal_total += hp_gain
	heal_overflow_shield += overflow_shield


func on_room_start() -> void:
	_room_started = Time.get_ticks_msec()


func on_room_clear() -> void:
	if _room_started >= 0:
		room_times.append(float(Time.get_ticks_msec() - _room_started) / 1000.0)
		_room_started = -1


func on_weapon_swap() -> void:
	weapon_swaps += 1


func on_reward_shown(n: int) -> void:
	rewards_shown += n


func on_reward_pick(id: String) -> void:
	reward_picks[id] = int(reward_picks.get(id, 0)) + 1


func triple_rate() -> float:
	return float(triples) / float(turns) if turns > 0 else 0.0


func avg_spin_seconds() -> float:
	return spin_seconds / float(spins) if spins > 0 else 0.0


func avg_ttk() -> float:
	var t := 0.0
	for v in room_times:
		t += float(v)
	return t / float(room_times.size()) if room_times.size() > 0 else 0.0


func reward_pick_rate() -> float:
	var picked := 0
	for k in reward_picks:
		picked += int(reward_picks[k])
	return float(picked) / float(rewards_shown) if rewards_shown > 0 else 0.0


func target_hit_rate() -> float:
	return float(target_hits) / float(stop_total) if stop_total > 0 else 0.0


func summary() -> Dictionary:
	return {
		"turns": turns, "triples": triples, "triple_rate": triple_rate(),
		"spins": spins, "spin_seconds": spin_seconds, "avg_spin": avg_spin_seconds(),
		"enemy_attacks": enemy_attacks, "damage_taken": damage_taken, "damage_blocked": damage_blocked,
		"rooms_cleared": room_times.size(), "avg_ttk": avg_ttk(),
		"weapon_swaps": weapon_swaps, "rewards_shown": rewards_shown,
		"reward_pick_rate": reward_pick_rate(), "reward_picks": reward_picks.duplicate(),
		"target_symbol": target_symbol, "stop_total": stop_total, "target_hits": target_hits,
		"target_hit_rate": target_hit_rate(), "forced_stops": forced_stops,
		"buffer_queues": buffer_queues, "stop_outcomes": stop_outcomes.duplicate(),
		"stop_kinds": stop_kinds.duplicate(), "consumable_uses": consumable_uses.duplicate(),
		"counter_triples": counter_triples, "counter_burst_damage": counter_burst_damage,
		"heal_total": heal_total, "heal_overflow_shield": heal_overflow_shield,
	}


func summary_text() -> String:
	var picks := []
	for k in reward_picks:
		picks.append("%s×%d" % [k, int(reward_picks[k])])
	var extra := ""
	if not stop_kinds.is_empty():
		var ks := []
		for k in stop_kinds:
			ks.append("%s×%d" % [k, int(stop_kinds[k])])
		extra += " · 停轮类别[%s]" % ",".join(ks)
	if not consumable_uses.is_empty():
		var cs := []
		for k in consumable_uses:
			cs.append("%s×%d" % [k, int(consumable_uses[k])])
		extra += " · 消耗品[%s]" % ",".join(cs)
	return "回合%d · 三连%d(%.0f%%) · 旋转%d次均%.2fs · 敌攻%d 承伤%d 格挡%d · 清房%d 均TTK%.1fs · 换武器%d · 奖励卡%d 选择率%.0f%% · 目标停中%d/%d(%.0f%%) 缓冲%d [%s]%s" % [
		turns, triples, triple_rate() * 100.0, spins, avg_spin_seconds(),
		enemy_attacks, damage_taken, damage_blocked,
		room_times.size(), avg_ttk(), weapon_swaps, rewards_shown, reward_pick_rate() * 100.0,
		target_hits, stop_total, target_hit_rate() * 100.0, buffer_queues,
		",".join(picks), extra]
