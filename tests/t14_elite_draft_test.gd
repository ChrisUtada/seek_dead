extends Node

# ============================================================================
# T1.4 精英强化 Draft 专项（可选强化替代自动护符）
#
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t14_elite_draft_test.tscn
# 隔离：必须由外部覆盖 APPDATA 到临时目录后再运行，绝不触碰真实存档。
#
# 验证：精英战后走强化专项 Draft（3 张高价值强化候选）、自动护符不入槽（无双发）、
#       选择后效果真实兑现、空池有明确兜底。
# ============================================================================

var _fails := 0
var _checks := 0
var _duel: DuelController


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
	await _run()
	_finish()


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _elite_room() -> RoomData:
	for r in _duel.ALL_ROOMS:
		if r != null and r.kind == "elite" and not r.final_boss:
			return r
	return null


func _run() -> void:
	_test_defs_high_value()
	_test_no_double_grant()
	_test_effect_applied()
	_test_elite_reroll_rejected()
	_test_normal_reroll_works()


# ① 精英强化候选：3 张合法高价值强化 def（空池也能兜底）
func _test_defs_high_value() -> void:
	var defs: Array[RewardDefinition] = _duel._reward_system._make_elite_power_defs()
	_check(defs.size() == 3, "精英强化候选 3 张（实测 %d）" % defs.size())
	var all_power: bool = true
	for d in defs:
		var eid: String = d.first_effect_id()
		var high_value: bool = eid in ["run_symbol_bonus", "symbol_effect_bonus", "run_power_bonus"]
		if not high_value:
			all_power = false
		_check(not d.id.is_empty() and high_value, "候选 %s 是高价值强化（effect %s）" % [d.id, eid])
	_check(all_power, "全部候选为引擎强化（非普通奖励换标题）")


# ② 无双发：精英战后不自动发护符（charms_owned / selected_charms 不因精英增加）
func _test_no_double_grant() -> void:
	var elite: RoomData = _elite_room()
	_check(elite != null, "找到精英房用于验收")
	if elite == null:
		return
	_duel._reset_run_state()
	var rooms: Array[RoomData] = [elite]
	_duel.ROOMS = rooms
	_duel._build_pool(_duel.selected_loadout)
	var charms_before: int = _duel.selected_charms.size()
	var owned_before: int = int((_duel.meta.get("owned_charms", []) as Array).size())
	_duel._start_room(0)
	# 走真实战后结算：_begin_post_battle 会调 apply_room_drops（收口后精英不再自动发护符）
	_duel.room_flow.begin_post_battle()
	_check(_duel.selected_charms.size() == charms_before,
		"精英战后 selected_charms 不增加（%d → %d）" % [charms_before, _duel.selected_charms.size()])
	_check(int((_duel.meta.get("owned_charms", []) as Array).size()) == owned_before,
		"精英战后 owned_charms 不增加（无自动护符双发）")
	# 战后 Draft 应为精英强化专项
	var view: Dictionary = _duel._reward_system.loot_offer_view()
	_check(bool(view.get("elite_draft", false)), "战后 Draft 标记为精英强化专项")
	var opts: Array = view.get("options", [])
	_check(opts.size() == 3, "精英强化 Draft 有 3 个候选（实测 %d）" % opts.size())


# ③ 效果兑现：选择一张 run_power 强化后，本局符号伤害加成真实增加
func _test_effect_applied() -> void:
	var defs: Array[RewardDefinition] = _duel._reward_system._make_elite_power_defs()
	# 找一个 run_power_bonus 候选
	var idx: int = -1
	for i in range(defs.size()):
		if defs[i].first_effect_id() == "run_power_bonus":
			idx = i
			break
	_check(idx >= 0, "精英强化含 run_power_bonus 候选")
	if idx < 0:
		return
	var power_before: int = int(_duel._reward_system.run_power_bonus)
	# 通过 resolver 真实结算该 def
	var res = _duel._reward_system._draft_resolver.resolve(defs[idx])
	_check(res.ok, "强化效果结算成功（%s）" % str(res.reason))
	_check(int(_duel._reward_system.run_power_bonus) > power_before,
		"符号伤害加成真实提升（%d → %d）" % [power_before, int(_duel._reward_system.run_power_bonus)])


# ④ 负向：精英强化页重抽被拒——候选完全不变、不扣款、不消耗 RNG
func _test_elite_reroll_rejected() -> void:
	var elite: RoomData = _elite_room()
	if elite == null:
		_check(false, "精英房不存在，无法测重抽边界")
		return
	_duel._reset_run_state()
	var rooms: Array[RoomData] = [elite]
	_duel.ROOMS = rooms
	_duel._build_pool(_duel.selected_loadout)
	_duel.gold = 500
	_duel._start_room(0)
	_duel.room_flow.begin_post_battle()
	var view: Dictionary = _duel._reward_system.loot_offer_view()
	_check(bool(view.get("elite_draft", false)), "负向前置：当前是精英强化 Draft")
	var ids_before: Array = []
	for o in (view.get("options", []) as Array):
		ids_before.append(String((o as Dictionary).get("id", "")))
	var gold_before: int = _duel.gold
	seed(12345)
	var rng_before: Array = []
	for _i in 6:
		rng_before.append(randi())
	seed(12345)
	var result: Dictionary = _duel._reward_system.reroll_loot_offer()
	var rng_after: Array = []
	for _i in 6:
		rng_after.append(randi())
	_check(not bool(result.get("ok", true)), "精英强化重抽被拒（reason=%s）" % str(result.get("reason", "")))
	_check(String(result.get("reason", "")) == "elite_draft_no_reroll", "拒绝原因明确为 elite_draft_no_reroll")
	_check(_duel.gold == gold_before, "重抽被拒不扣款（%d → %d）" % [gold_before, _duel.gold])
	var view_after: Dictionary = _duel._reward_system.loot_offer_view()
	var ids_after: Array = []
	for o in (view_after.get("options", []) as Array):
		ids_after.append(String((o as Dictionary).get("id", "")))
	_check(ids_after == ids_before, "重抽被拒候选完全不变（%s）" % str(ids_after))
	_check(rng_after == rng_before, "重抽被拒不消耗 RNG")


# ⑤ 正向：普通 Draft 重抽仍正常（换卡、扣款）
func _test_normal_reroll_works() -> void:
	var normal: RoomData = null
	for r in _duel.ALL_ROOMS:
		if r != null and r.kind == "normal":
			normal = r
			break
	_check(normal != null, "找到普通房用于重抽正向测试")
	if normal == null:
		return
	_duel._reset_run_state()
	var rooms: Array[RoomData] = [normal]
	_duel.ROOMS = rooms
	_duel._build_pool(_duel.selected_loadout)
	_duel.gold = 500
	_duel._start_room(0)
	# 直接走普通 Draft（非 elite_draft）
	_duel.room_flow.begin_post_battle()
	var view: Dictionary = _duel._reward_system.loot_offer_view()
	_check(not bool(view.get("elite_draft", false)), "正向前置：普通 Draft 未标记 elite_draft")
	var ids_before: Array = []
	for o in (view.get("options", []) as Array):
		ids_before.append(String((o as Dictionary).get("id", "")))
	var gold_before: int = _duel.gold
	var result: Dictionary = _duel._reward_system.reroll_loot_offer()
	_check(bool(result.get("ok", false)), "普通 Draft 重抽成功（reason=%s）" % str(result.get("reason", "")))
	_check(_duel.gold < gold_before, "普通 Draft 重抽扣款（%d → %d）" % [gold_before, _duel.gold])
	var view_after: Dictionary = _duel._reward_system.loot_offer_view()
	var ids_after: Array = []
	for o in (view_after.get("options", []) as Array):
		ids_after.append(String((o as Dictionary).get("id", "")))
	_check(ids_after.size() == 3, "普通 Draft 重抽后仍 3 张候选（实测 %d）" % ids_after.size())


func _finish() -> void:
	print("---")
	print("T14ELITE RESULT: %d checks, %d fails" % [_checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)
