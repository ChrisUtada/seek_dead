extends Node

# S4-1 幕间锻魂幂等测试（2026-11-21）
# 验证 granted_acts 唯一守卫：同幕重复调用不重复发放，不同幕各发一次，
# 新局 reset_run 清空后可按新生命周期重新发放；Journal 不另建账本。

var _fails := 0
var _checks := 0

func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("S4 ACT BOON FAIL: " + label)

func _ready() -> void:
	await get_tree().process_frame
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.demo_config.enabled = false
	duel._confirm_loadout()
	await get_tree().process_frame

	var g = duel.growth
	var rs = duel._reward_system
	_ok(g != null and rs != null, "growth & reward system present")

	# 基线
	var base_power: int = int(rs.run_power_bonus)
	var base_hp_max: int = int(duel.player_hp_max)
	var base_hp: int = int(duel.player_hp)
	var boons0: int = 0
	if duel._journal != null and duel._journal._data.has("act_boons"):
		boons0 = (duel._journal._data["act_boons"] as Array).size()

	# ACT2 首次调用发放
	g.grant_act_boon(2)
	var after2_power: int = int(rs.run_power_bonus)
	var after2_hpmax: int = int(duel.player_hp_max)
	var after2_hp: int = int(duel.player_hp)
	var boons2: int = 0
	if duel._journal != null and duel._journal._data.has("act_boons"):
		boons2 = (duel._journal._data["act_boons"] as Array).size()
	_ok(after2_power == base_power + g.ACT_BOON_POWER, "ACT2 first: power +8")
	# T1.7 收口：锻魂不再改 HP
	_ok(after2_hpmax == base_hp_max, "ACT2 first: hp_max unchanged")
	_ok(after2_hp == base_hp, "ACT2 first: hp unchanged")
	_ok(boons2 == boons0 + 1, "ACT2 first: journal +1 record")
	_ok(g.granted_acts.has(2), "granted_acts has act 2")

	# ACT2 第二次调用不重复
	g.grant_act_boon(2)
	_ok(int(rs.run_power_bonus) == after2_power, "ACT2 repeat: power unchanged")
	_ok(int(duel.player_hp_max) == after2_hpmax, "ACT2 repeat: hp_max unchanged")
	_ok(int(duel.player_hp) == after2_hp, "ACT2 repeat: hp unchanged")
	var boons2r: int = 0
	if duel._journal != null and duel._journal._data.has("act_boons"):
		boons2r = (duel._journal._data["act_boons"] as Array).size()
	_ok(boons2r == boons2, "ACT2 repeat: journal unchanged")

	# ACT3 首次仍正常发放
	g.grant_act_boon(3)
	_ok(int(rs.run_power_bonus) == after2_power + g.ACT_BOON_POWER, "ACT3 first: power +8 again")
	_ok(int(duel.player_hp_max) == after2_hpmax, "ACT3 first: hp_max unchanged again")
	_ok(g.granted_acts.has(3), "granted_acts has act 3")
	var boons3: int = 0
	if duel._journal != null and duel._journal._data.has("act_boons"):
		boons3 = (duel._journal._data["act_boons"] as Array).size()
	_ok(boons3 == boons2 + 1, "ACT3 first: journal +1 record")

	# ACT1 不发（act < 2 守卫）
	var before1: int = int(rs.run_power_bonus)
	g.grant_act_boon(1)
	_ok(int(rs.run_power_bonus) == before1, "ACT1: no boon (act<2 guard)")

	# 新局 reset_run 清空后可重发
	g.reset_run()
	_ok(not g.granted_acts.has(2) and not g.granted_acts.has(3), "reset_run clears granted_acts")
	var before_reset_power: int = int(rs.run_power_bonus)
	g.grant_act_boon(2)
	_ok(int(rs.run_power_bonus) == before_reset_power + g.ACT_BOON_POWER, "after reset: ACT2 re-grants")

	print("S4 ACT BOON RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
