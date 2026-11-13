extends Node

# ============================================================================
# M1 战后结算 · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/m1_post_battle_test.tscn
#
# Step 7 起玩家界面 = 战利品三选一（同层）+ 成长位分开结算；本套件锁定：
# ① 普通房胜利 → 战利品阶段（来源 / 品质 / 三项同层 / 重抽 / 跳过）→ 成长阶段；
# ② 旧三槽候选生成（补给 / 构筑）仍合法：满血不出治疗、槽位间不重复；
# ③ 成长队列：同一胜利只取一项；未选的技艺/铭印进入下一战斗房（候选冻结）；
# ④ 整体跳过 = 跳过战利品 + 放弃本次成长，待处理成长保留；
# ⑤ BOSS 胜利不显示普通战利品屏；未处理成长随队列进入下一战斗房；
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
	# 留 1 个武器空位：本用例要验证「点卡 → 结算 → 成长阶段」，不在这里测替换弹层。
	if duel.selected_loadout.size() >= 2:
		duel.selected_loadout.resize(1)
		duel._build_pool(duel.selected_loadout)
	duel.growth.xp = 2   # 普通房 +1 → Lv.2，成长队列有技艺
	duel.room_flow.begin_post_battle()
	var screen = duel.hud.reward_screen
	_check(duel.room_flow.post_battle_active, "普通房胜利进入战后结算")
	_check(duel.room_flow.post_battle_phase() == "loot", "先进入战利品三选一阶段")
	_check(screen.visible, "战利品屏可见")
	_check(screen.title_label.text.find("战利品") >= 0,
		"标题写明战利品（%s）" % screen.title_label.text)
	_check(screen.title_label.text.find("普通战") >= 0, "标题写明来源（普通战）")
	_check(screen.reward_grid.get_child_count() == 3, "固定三张同层候选")
	_check(screen._skip_btn.text.begins_with("跳过 · 金币 +"),
		"跳过按钮写明冻结金币（%s）" % screen._skip_btn.text)
	_check(screen._reroll_btn != null and screen._reroll_btn.visible, "战利品阶段提供重抽")
	var view: Dictionary = duel.room_flow.loot_view()
	var opts: Array = view.get("options", [])
	_check(opts.size() == 3, "冻结 payload 为 3 项")
	var q := String(view.get("quality", ""))
	var same_tier := true
	for o in opts:
		if String(o.get("quality", "")) != q:
			same_tier = false
		_check(String(o.get("quality_name", "")) != "", "候选带品质名")
		_check(String(o.get("condition", "")) != "", "候选带条件文本")
		_check(String(o.get("result", "")) != "", "候选带结果文本")
		_check(String(o.get("tooltip", "")) != "", "候选带机制文本")
	_check(same_tier, "三项同层")
	_check(duel.room_flow.post_battle_has_growth(), "成长队列已就绪（战利品阶段即可回答）")
	_check(String(duel.room_flow.post_battle_growth_candidate().get("kind", "")) == "perk",
		"成长位为技艺（本房触发）")
	# 手动点一张不需要替换弹层的卡 → 战利品结算一次 → 进入成长阶段。
	var pick := 0
	for i in range(opts.size()):
		if not bool((opts[i] as Dictionary).get("needs_replace", false)):
			pick = i
			break
	duel._on_loot_offer_chosen(pick)
	_check(duel.room_flow.post_battle_phase() == "growth", "战利品结算后进入成长阶段")
	_check(screen.title_label.text.begins_with("成长 ·"),
		"成长阶段标题正确（%s）" % screen.title_label.text)
	_check(screen.reward_grid.get_child_count() == 1, "成长阶段只展示真实成长卡")
	_check(not screen._reroll_btn.visible, "成长阶段不提供重抽")
	_check(screen._skip_btn.text == "保留到下次战斗", "成长阶段跳过 = 保留")
	duel._on_post_battle_defer()
	_check(duel.growth.pending_picks == 1, "保留后技艺仍待选")
	_check(duel.in_interroom and not duel.room_flow.post_battle_active, "收尾进入间歇")
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
	var first: Dictionary = duel.room_flow.post_battle_growth_candidate()
	var frozen_id := String(first.get("growth_id", ""))
	_check(frozen_id != "", "成长候选冻结具体技艺 id")
	# 只结算战利品、不取成长 → 技艺未选，进入队列。
	duel.room_flow.auto_pick_post_battle([])
	_check(duel.growth.pending_picks == 1,
		"只结算战利品后技艺仍待选（pending=%d）" % duel.growth.pending_picks)
	_check(not duel.room_flow.post_battle_active and duel.in_interroom, "本次成长选择结束")
	# 下一战斗房：同一技艺仍在成长位，候选不重新随机。
	duel.in_interroom = false
	duel.hud.set_interroom_enabled(false)
	duel.room_flow.begin_post_battle()
	var second: Dictionary = duel.room_flow.post_battle_growth_candidate()
	_check(String(second.get("kind", "")) == "perk", "下一战斗房成长位仍为技艺")
	_check(String(second.get("growth_id", "")) == frozen_id, "未选成长候选冻结（id 不变）")
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
	_check(duel.growth.pending_picks == 1,
		"跳过 = 放弃本次成长，待选保留（pending=%d）" % duel.growth.pending_picks)
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
