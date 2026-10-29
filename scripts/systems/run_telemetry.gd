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


func on_player_hit(eff: int, blocked: int, dealt: int) -> void:
	enemy_attacks += 1
	damage_blocked += blocked
	damage_taken += dealt


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


func summary() -> Dictionary:
	return {
		"turns": turns, "triples": triples, "triple_rate": triple_rate(),
		"spins": spins, "spin_seconds": spin_seconds, "avg_spin": avg_spin_seconds(),
		"enemy_attacks": enemy_attacks, "damage_taken": damage_taken, "damage_blocked": damage_blocked,
		"rooms_cleared": room_times.size(), "avg_ttk": avg_ttk(),
		"weapon_swaps": weapon_swaps, "rewards_shown": rewards_shown,
		"reward_pick_rate": reward_pick_rate(), "reward_picks": reward_picks.duplicate(),
	}


func summary_text() -> String:
	var picks := []
	for k in reward_picks:
		picks.append("%s×%d" % [k, int(reward_picks[k])])
	return "回合%d · 三连%d(%.0f%%) · 旋转%d次均%.2fs · 敌攻%d 承伤%d 格挡%d · 清房%d 均TTK%.1fs · 换武器%d · 奖励卡%d 选择率%.0f%% [%s]" % [
		turns, triples, triple_rate() * 100.0, spins, avg_spin_seconds(),
		enemy_attacks, damage_taken, damage_blocked,
		room_times.size(), avg_ttk(), weapon_swaps, rewards_shown, reward_pick_rate() * 100.0,
		",".join(picks)]
