extends Node

# ============================================================================
# M1 战后结算 · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/m1_post_battle_test.tscn
#
# 成长三选一同屏结算；本套件锁定：
# ① 普通房胜利 → 成长三选一（来源 / 品质 / 重抽 / 跳过）；
# ② 旧三槽候选生成（补给 / 构筑）仍合法：满血不出治疗、槽位间不重复；
# ③ 任意结算或跳过后，未选成长全部放弃；新触发可生成新候选；
# ④ BOSS 胜利不显示普通战利品屏，未选成长采用同一清空规则；
# ⑤ 腰带满时普通战不发放消耗品，只提供成长。
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
	duel.room_flow.reset_flow()
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
	duel.room_flow.begin_post_battle()
	var screen = duel.hud.reward_screen
	_check(duel.room_flow.post_battle_active, "普通房胜利进入战后结算")
	_check(duel.room_flow.post_battle_phase() == "loot", "先进入战利品三选一阶段")
	_check(screen.visible, "战利品屏可见")
	_check(screen.title_label.text.find("成长") >= 0,
		"标题写明成长（%s）" % screen.title_label.text)
	_check(screen.title_label.text.find("普通战") >= 0, "标题写明来源（普通战）")
	_check(screen.reward_grid.get_child_count() == 3, "固定三张同层候选")
	_check(screen._skip_btn.text == "跳过 · 免费",
		"跳过按钮免费且不发奖励（%s）" % screen._skip_btn.text)
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
	# 2026-11-19 技艺改由 Draft 概率注入，成长队列不再固定为技艺
	# 手动点一张不需要替换弹层的卡 → 战利品结算一次 → 进入成长阶段。
	var pick := -1
	for i in range(opts.size()):
		if not bool((opts[i] as Dictionary).get("needs_replace", false)) \
			and String((opts[i] as Dictionary).get("kind", "")) != "queued_growth":
			pick = i
			break
	if pick >= 0:
		duel._on_loot_offer_chosen(pick)
	else:
		duel._on_loot_offer_skip()
	_check(not duel.room_flow.post_battle_active and duel.in_interroom,
		"成长与战利品同屏结算后直接收尾，不再打开第二成长页")
	_check(not screen.visible, "收尾后不再显示成长页")
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


func _test_consumable_full_belt(duel: DuelController) -> void:
	_fresh(duel)
	duel.consumable_slots.clear()
	for i in range(duel.CONSUMABLE_CAP):
		duel.consumable_slots.append({"path": "", "item_id": "full_%d" % i, "charges": 1, "uid": "full%d" % i})
	duel.room_flow.begin_post_battle()
	var view: Dictionary = duel.room_flow.loot_view()
	var has_item := false
	for opt in view.get("options", []):
		if String(opt.get("kind", "")) == "item":
			has_item = true
	_check(bool(view.get("growth_only", false)) and not has_item,
		"腰带满时普通战仍只给成长，不发放消耗品")
	duel.consumable_slots.clear()
