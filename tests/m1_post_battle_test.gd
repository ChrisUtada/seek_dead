extends Node

# ============================================================================
# M1 战后成长三槽 · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/m1_post_battle_test.tscn
#
# 覆盖：
# ① 普通房胜利 → 三槽屏（补给 / 构筑 / 成长），标题与槽位标签固定；
# ② 候选合法性：满血不出治疗、槽位间不重复、卡面带当前值 → 选择后值；
# ③ 成长队列：同一胜利只取一项；未选的技艺/铭印进入下一战斗房成长位（候选冻结）；
# ④ 跳过 = 放弃本次成长，待处理成长保留；
# ⑤ BOSS 胜利不显示普通三槽屏；未处理成长随队列进入下一战斗房；
# ⑥ 腰带满时消耗品卡明确折算金币，不在选择后静默失败。
# 测试结束还原 meta（不污染玩家真实存档）。
# ============================================================================

var _fails := 0
var _checks := 0


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	var duel: DuelController = await _boot()
	if duel == null:
		print("RESULT FAIL (boot)")
		get_tree().quit(2)
		return
	var meta_backup: Dictionary = duel.meta.duplicate(true)

	_test_three_slots(duel)
	_test_slot_legality(duel)
	_test_growth_queue(duel)
	_test_skip_keeps_growth(duel)
	_test_boss_keeps_growth(duel)
	_test_consumable_full_belt(duel)

	duel.meta.clear()
	for k in meta_backup:
		duel.meta[k] = meta_backup[k]
	duel._meta_store.save_meta()

	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _boot() -> DuelController:
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame
	return duel


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _normal_room_index(duel: DuelController) -> int:
	for i in range(duel.ROOMS.size()):
		if duel.ROOMS[i].kind == "normal":
			return i
	return 0


func _fresh(duel: DuelController, kind: String = "normal") -> void:
	duel.growth.reset_run()
	duel.mastery.reset_run()
	duel._post_battle.reset_run()
	duel.player_hp_max = 100
	duel.player_hp = 100
	duel.turn_count = 1
	var idx := _normal_room_index(duel)
	if kind == "boss":
		for i in range(duel.ROOMS.size()):
			if duel.ROOMS[i].kind == "boss" and not duel._is_run_final(i):
				idx = i
				break
	duel.room_index = idx
	duel.in_interroom = false
	duel.hud.set_interroom_enabled(false)
	duel.hud.hide_reward_screen()


func _test_three_slots(duel: DuelController) -> void:
	_fresh(duel)
	duel.growth.xp = 2   # 普通房 +1 → Lv.2，成长位为技艺
	duel.room_flow.begin_post_battle()
	var screen = duel.hud.reward_screen
	_check(duel.room_flow.post_battle_active, "普通房胜利进入战后成长")
	_check(screen.visible, "战后成长屏可见")
	_check(screen.title_label.text == "战后成长 · 选择一项", "标题为「战后成长 · 选择一项」")
	_check(screen.reward_grid.get_child_count() == 3, "固定三张卡")
	_check(screen._skip_btn.text == "放弃本次成长", "跳过按钮写明「放弃本次成长」")
	_check(screen.sub_label.text.find("本局成长") >= 0, "页头保留本局成长摘要")
	var offer: Array = duel.room_flow.post_offer()
	_check(offer.size() == 3, "候选槽位 = 3")
	_check(String(offer[0].get("slot_label", "")) == "补给", "第 1 槽为补给")
	_check(String(offer[1].get("slot_label", "")) == "构筑", "第 2 槽为构筑")
	_check(String(offer[2].get("slot_label", "")) == "成长", "第 3 槽为成长")
	_check(String(offer[2].get("kind", "")) == "perk", "成长位为技艺（本房触发）")
	for i in range(3):
		var desc := String(offer[i].get("desc", ""))
		_check(desc != "", "槽位 %d 带效果说明" % (i + 1))
		_check(desc.find("→") >= 0 or desc.find("提前") >= 0 or desc.find("获得") >= 0
			or desc.find("入腰带") >= 0 or desc.find("折算金币") >= 0,
			"槽位 %d 给出可感知结果（%s）" % [i + 1, desc])
	_check(offer[0].get("reward") != null and offer[1].get("reward") != null, "补给/构筑为具体奖励对象")
	duel.room_flow.auto_pick_post_battle(["growth"])
	_check(duel.growth.perk_ids.size() == 1 and duel.growth.pending_picks == 0, "成长位选择后技艺入列")
	_check(duel.in_interroom and not duel.room_flow.post_battle_active, "选择后进入间歇")
	duel.in_interroom = false
	duel.hud.set_interroom_enabled(false)


func _test_slot_legality(duel: DuelController) -> void:
	_fresh(duel)
	var seen := {}
	for i in range(20):
		var offer: Array = duel._post_battle.build("normal")
		var s_id := String(offer[0]["reward"].id)
		var b_id := String(offer[1]["reward"].id)
		_check(s_id != "heal", "满血补给位不出纯治疗（第 %d 次）" % (i + 1))
		_check(s_id != b_id, "补给位与构筑位不重复（第 %d 次）" % (i + 1))
		seen[s_id] = true
		seen[b_id] = true
	_check(seen.size() >= 3, "多次生成覆盖多种候选（%d 类）" % seen.size())
	var full: Dictionary = {}
	for i in range(30):
		var offer2: Array = duel._post_battle.build("normal")
		full[String(offer2[0]["reward"].id) + "|" + String(offer2[1]["reward"].id)] = true
	_check(full.size() > 1, "补给/构筑组合不是固定同义卡")


func _test_growth_queue(duel: DuelController) -> void:
	_fresh(duel)
	duel.growth.xp = 2
	duel.room_flow.begin_post_battle()
	var first: Array = duel.room_flow.post_offer()
	var frozen_id := String(first[2].get("growth_id", ""))
	_check(frozen_id != "", "成长位冻结具体技艺 id")
	# 本次选补给 → 技艺未选，进入队列。
	duel.room_flow.auto_pick_post_battle(["supply"])
	_check(duel.growth.pending_picks == 1, "选补给后技艺仍待选")
	_check(not duel.room_flow.post_battle_active and duel.in_interroom, "本次成长选择结束")
	# 下一战斗房：同一技艺仍在成长位，候选不重新随机。
	duel.in_interroom = false
	duel.hud.set_interroom_enabled(false)
	duel.room_flow.begin_post_battle()
	var second: Array = duel.room_flow.post_offer()
	_check(String(second[2].get("kind", "")) == "perk", "下一战斗房成长位仍为技艺")
	_check(String(second[2].get("growth_id", "")) == frozen_id, "未选成长候选冻结（id 不变）")
	duel.room_flow.auto_pick_post_battle(["growth"])
	_check(duel.growth.perk_ids.size() == 1 and duel.growth.pending_picks == 0, "下一房选中后技艺入列")
	duel.in_interroom = false
	duel.hud.set_interroom_enabled(false)


func _test_skip_keeps_growth(duel: DuelController) -> void:
	_fresh(duel)
	duel.growth.xp = 2
	duel.room_flow.begin_post_battle()
	_check(duel.room_flow.post_battle_has_growth(), "跳过前成长位有真实成长")
	duel._on_reward_skip_pressed()
	_check(duel.growth.pending_picks == 1, "跳过 = 放弃本次成长，待选保留")
	_check(not duel.room_flow.post_battle_active and duel.in_interroom, "跳过后进入间歇")
	duel.in_interroom = false
	duel.hud.set_interroom_enabled(false)
	duel.room_flow.begin_post_battle()
	_check(duel.room_flow.post_battle_has_growth(), "下一战斗房重新提供成长位")
	duel.room_flow.auto_pick_post_battle(["growth"])
	duel.in_interroom = false
	duel.hud.set_interroom_enabled(false)


func _test_boss_keeps_growth(duel: DuelController) -> void:
	_fresh(duel, "boss")
	duel.growth.xp = 2   # BOSS +3 → Lv.2，成长进入队列
	duel.hud._show_reward_screen(true)
	_check(not duel.room_flow.post_battle_active, "BOSS 不进入普通三槽屏")
	_check(duel.hud.reward_screen.title_label.text.find("BOSS") >= 0, "BOSS 显示专属战利品")
	duel._on_reward_skip_pressed()
	_check(not duel.room_flow.post_battle_active, "BOSS 结算后仍无普通三槽屏")
	_check(duel.growth.pending_picks == 1, "BOSS 触发的成长留在队列")
	_check(duel.in_interroom, "BOSS 结算后进入间歇")
	# 下一战斗房（普通）成长位提供 BOSS 触发的成长。
	duel.in_interroom = false
	duel.hud.set_interroom_enabled(false)
	duel.room_index = _normal_room_index(duel)
	duel.room_flow.begin_post_battle()
	_check(duel.room_flow.post_battle_has_growth(), "下一战斗房成长位接住 BOSS 未处理成长")
	duel.room_flow.auto_pick_post_battle(["growth"])
	duel.in_interroom = false
	duel.hud.set_interroom_enabled(false)


func _test_consumable_full_belt(duel: DuelController) -> void:
	_fresh(duel)
	duel.consumable_slots.clear()
	for i in range(duel.CONSUMABLE_CAP):
		duel.consumable_slots.append({"path": "", "item_id": "full_%d" % i, "charges": 1, "uid": "full%d" % i})
	var rw: RewardData = duel._reward_system.reward_by_id("consumable")
	_check(rw != null, "消耗品奖励资源存在")
	var pl: Dictionary = duel._reward_system._slot_payload(rw)
	_check(pl.has("desc") and String(pl["desc"]).find("折算金币") >= 0,
		"腰带满时消耗品卡明确折算金币（%s）" % String(pl.get("desc", "")))
	duel.consumable_slots.clear()
