extends Node

# L2-E 收集品框架 · 遗物栏定向探针（2026-11-18）
# 验证：① 护符槽满时 BOSS 信物仍必得 ② 入 run_relics 不占槽 ③ 遗物被动本局生效
#       ④ 跨局图鉴 owned_charms 保留 ⑤ 每局 run_relics 清零但图鉴不清
# 运行：Godot --headless --path . res://tests/l2e_relic_probe.tscn

const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const ROOM := "res://resources/rooms/frozen_urn.tres"
const RELIC := "res://resources/charms/frost_core_relic.tres"

var _pass := 0
var _fail := 0
var _duel = null


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  %s" % label)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _ready() -> void:
	await get_tree().process_frame
	var scene_res: PackedScene = load(DUEL_SCENE)
	_duel = scene_res.instantiate()
	add_child(_duel)
	await _frames(3)

	var room: Resource = load(ROOM)
	var relic_path: String = String(room.boss_relic_path)
	_check(relic_path == RELIC, "测试 BOSS 挂接目标信物（got %s）" % relic_path)

	# --- ① 把护符槽塞满 ---
	_duel.selected_charms.clear()
	var filler := "res://resources/charms/rust_relic.tres"
	while _duel.selected_charms.size() < _duel._loadout_system.cat_max("passive"):
		_duel.selected_charms.append(filler)
	var cap_before: int = _duel.selected_charms.size()
	_check(cap_before >= _duel._loadout_system.cat_max("passive"), "护符槽已满（%d）" % cap_before)
	_duel.run_relics.clear()

	# --- ② G6-2：信物不再混入三选一候选（避免玩家不选就错过） ---
	var cands: Array = _duel._reward_system.roll_boss_rewards(room)
	var has_relic_cand := false
	for c in cands:
		if String(c.get("kind", "")) == "boss_relic":
			has_relic_cand = true
			break
	_check(not has_relic_cand, "G6-2 BOSS 信物不再作为三选一候选")

	# --- ③ 胜利保证入账：入遗物栏、不占槽、图鉴保留 ---
	var granted: bool = _duel._reward_system.grant_boss_relic(room)
	_check(granted, "G6-2 胜利时遗物保证入账")
	_check(_duel.run_relics.has(relic_path), "入账后进入本局遗物栏 run_relics")
	_check(_duel.selected_charms.size() == cap_before, "遗物不占护符槽（仍 %d）" % cap_before)
	_check(_duel.meta["owned_charms"].has(relic_path), "跨局图鉴 owned_charms 仍收录")
	_check(not _duel._reward_system.grant_boss_relic(room), "重复入账被去重")

	# --- ④ 遗物被动本局生效（frost_core_relic: damage_bonus +6）---
	_duel._apply_charms()
	var power_from_relic: int = 0
	if _duel.run_relics.has(relic_path):
		# 单独再算一次：仅遗物贡献（临时移除护符对比）
		var saved: Array[String] = _duel.selected_charms.duplicate()
		_duel.selected_charms.clear()
		_duel._apply_charms()
		power_from_relic = int(_duel.charm_power_bonus)
		_duel.selected_charms.assign(saved)
		_duel._apply_charms()
	_check(power_from_relic >= 6, "遗物被动生效（damage_bonus=%d，期望>=6）" % power_from_relic)

	# --- ⑤ 每局清零：run_relics 空、图鉴不清 ---
	_duel._reset_run_state()
	_check(_duel.run_relics.is_empty(), "新局 run_relics 清零")
	_check(_duel.meta["owned_charms"].has(relic_path), "新局跨局图鉴仍在")

	_finish()


func _finish() -> void:
	print("L2ERELIC|RESULT %s (pass=%d fail=%d)" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	get_tree().quit(0 if _fail == 0 else 2)
