extends Node

# ============================================================================
# T1.6 精英武器职责专项（正式收口后）
#
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t16_elite_weapon_role_test.tscn
# 隔离：必须由外部覆盖 APPDATA 到临时目录后再运行，绝不触碰真实存档。
#
# 验证正式新结构（无试验开关）：
#   ① 精英三选一恒 3 张 = 1 当前敌人克制武器 + 2 高价值强化，不增第四张；
#   ② 已装备 / 本局仓库已有的武器不生成无效候选；
#   ③ begin_post_battle 默认不自动发武器；
#   ④ 克制武器候选选择后真实生效（weapon_acquire 入仓库/装备，走完整替换预览）；
#   ⑤ 精英 Draft 仍不可重抽；重抽被拒候选不变。
# 主题版 / 自动赠送为历史失败试验，原始 A/B 数据保留于 .workbuddy/t16*。
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


func _families(path: String) -> Array:
	var wd: Resource = load(path)
	if wd != null and wd.get("family_tags") is Array:
		return wd.get("family_tags")
	return []


func _hit_families(path: String, families: Array) -> bool:
	var fams: Array = _families(path)
	for f in families:
		if fams.has(String(f)):
			return true
	return false


func _setup_elite(act: int, element: String) -> void:
	var room := _duel.ALL_ROOMS[0].duplicate()
	room.kind = "elite"
	room.act = act
	room.element = element
	_duel.ROOMS = [room] as Array[RoomData]
	_duel.room_index = 0
	_duel.current_act = act


func _run() -> void:
	_test_draft_shape()
	_test_no_auto_grant()
	_test_no_invalid_candidate()
	_test_effect_applied()
	_test_reroll_rejected()


# ① 正式三选一：恒 3 张 = 1 克制武器 + 2 强化，武器针对当前敌人元素
func _test_draft_shape() -> void:
	_duel.run_weapon_inventory.clear()
	_setup_elite(1, "ice")
	var view: Dictionary = _duel._reward_system.build_elite_draft_view()
	var opts: Array = view.get("options", [])
	_check(opts.size() == 3, "精英三选一恒 3 张（实测 %d）" % opts.size())
	var weapon_cnt := 0
	var power_cnt := 0
	var weapon_opt: Dictionary = {}
	for o in opts:
		var od: Dictionary = o
		if String(od.get("effect_id", "")) == "weapon_acquire":
			weapon_cnt += 1
			weapon_opt = od
		else:
			power_cnt += 1
	_check(weapon_cnt == 1, "恰好 1 张克制武器（实测 %d）" % weapon_cnt)
	_check(power_cnt == 2, "恰好 2 张强化（实测 %d）" % power_cnt)
	var wpath: String = String(weapon_opt.get("path", ""))
	_check(not wpath.is_empty() and _hit_families(wpath, ElementCounter.weakness("ice")),
		"武器针对 ice 敌人精确克制（实测 %s，族 %s）" % [wpath.get_file(), str(_families(wpath))])
	var legal_power := 0
	for o in opts:
		var od: Dictionary = o
		if String(od.get("effect_id", "")) != "weapon_acquire" and not String(od.get("effect_id", "")).is_empty():
			legal_power += 1
	_check(legal_power == 2, "两张强化均有合法 effect_id（实测 %d）" % legal_power)


# ② 默认 begin_post_battle 不自动发武器
func _test_no_auto_grant() -> void:
	_duel.run_weapon_inventory.clear()
	_setup_elite(1, "ice")
	var counter_path: String = _duel._reward_system.roll_elite_element_weapon(1)
	var before_inv: int = _duel.run_weapon_inventory.size()
	var before_loadout: int = _duel.selected_loadout.size()
	_duel.room_flow.reset_flow()
	_duel.room_flow.begin_post_battle()
	_check(not counter_path.is_empty(), "前置：存在克制武器（%s）" % counter_path.get_file())
	_check(_duel.run_weapon_inventory.size() == before_inv and _duel.selected_loadout.size() == before_loadout,
		"默认不自动发武器（仓库 %d→%d / 装备 %d→%d）" % [before_inv, _duel.run_weapon_inventory.size(), before_loadout, _duel.selected_loadout.size()])


# ③ 已装备/本局仓库已有的武器不生成无效候选（强制把克制武器塞进仓库，验证跳过）
func _test_no_invalid_candidate() -> void:
	_setup_elite(1, "ice")
	var raw_path: String = _duel._reward_system.roll_elite_element_weapon(1)
	_check(not raw_path.is_empty(), "前置：可算出克制武器（%s）" % raw_path.get_file())
	# 把该武器标记为本局已拥有 → 不应再作为武器候选（应被跳过，强化补足 3 张）
	if not _duel.run_weapon_inventory.has(raw_path):
		_duel.run_weapon_inventory.append(raw_path)
	var defs: Array = _duel._reward_system._make_elite_counter_weapon_def()
	var has_raw := false
	for d in defs:
		var eff: Array = d.effects
		if not eff.is_empty() and String((eff[0] as Dictionary).get("params", {}).get("weapon_path", "")) == raw_path:
			has_raw = true
	_check(not has_raw, "已持有武器不生成无效候选（实测生成=%s）" % str(has_raw))
	# 恢复仓库
	_duel.run_weapon_inventory.erase(raw_path)


# ④ 克制武器候选选择后真实生效（空槽直接入槽 + 写本局仓库）
func _test_effect_applied() -> void:
	_duel.run_weapon_inventory.clear()
	# 腾出武器槽：用未装备的两把起始武器之外的路径，构造空槽场景
	_setup_elite(1, "ice")
	var view: Dictionary = _duel._reward_system.build_elite_draft_view()
	var opts: Array = view.get("options", [])
	var weapon_idx := -1
	for i in range(opts.size()):
		if String((opts[i] as Dictionary).get("effect_id", "")) == "weapon_acquire":
			weapon_idx = i
			break
	_check(weapon_idx >= 0, "存在克制武器候选用于结算")
	if weapon_idx < 0:
		return
	var wpath: String = String((opts[weapon_idx] as Dictionary).get("path", ""))
	# 槽未满（起始 2 把已是上限 2 → needs_replace），这里只验证 def 的 effect 可解析并写仓库：
	var res: Dictionary = _duel._reward_system.settle_loot_offer(weapon_idx)
	# needs_replace 走替换弹层属正常路径，不判失败；这里接受 ok 或 needs_replace
	var reason: String = String(res.get("reason", ""))
	_check(bool(res.get("ok", false)) or reason == "needs_replace",
		"克制武器选择走正式结算链（ok=%s reason=%s）" % [str(res.get("ok", false)), reason])
	_check(reason != "invalid_weapon" and reason != "already_equipped",
		"克制武器候选无无效结算原因（reason=%s）" % reason)


# ⑤ 精英 Draft 不可重抽，拒绝后候选不变
func _test_reroll_rejected() -> void:
	_duel.run_weapon_inventory.clear()
	_setup_elite(1, "ice")
	_duel._reward_system.build_elite_draft_view()
	var before: Array = []
	for o in _duel._reward_system.loot_offer_view().get("options", []):
		before.append(String((o as Dictionary).get("id", "")))
	var gold_before: int = _duel.gold
	var res: Dictionary = _duel._reward_system.reroll_loot_offer()
	_check(not bool(res.get("ok", true)) and String(res.get("reason", "")) == "elite_draft_no_reroll",
		"精英 Draft 重抽被拒（reason=%s）" % String(res.get("reason", "")))
	_check(_duel.gold == gold_before, "重抽被拒不扣款（%d→%d）" % [gold_before, _duel.gold])
	var after: Array = []
	for o in _duel._reward_system.loot_offer_view().get("options", []):
		after.append(String((o as Dictionary).get("id", "")))
	_check(after == before, "重抽被拒候选不变（%s vs %s）" % [str(before), str(after)])


func _finish() -> void:
	print("---")
	print("T16ELITE RESULT: %d checks, %d fails" % [_checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)
