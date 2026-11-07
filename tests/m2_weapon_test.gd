extends Node

# ============================================================================
# M2-02 武器熟练 R1–R4 与铭印 · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/m2_weapon_test.tscn
#
# 覆盖（docs/M0-02_样板范围.md §2）：
# ① 熟练：仅本房有效结算的已装备样板武器获得；普通 +1 / 精英 +2 / BOSS +2（基础 1 + 额外 1）；每房上限 3（保险）
# ② R 等级：R2 @3、R3 @7、R4 @12；跨过 R2 / R3 各欠一次铭印，R4 不欠
# ③ 铭印候选：锋铸恒在（≤2 次）；调律仅在真实改变格数时出现，且达上限后不再出现
# ④ 锋铸：基础攻击 +2（经 build_pool 写入武器攻击力映射），不改共享 .tres
# ⑤ 调律：主符号（权重最高）池内权重 +1，带子格数由同一口径（build_strips）计算
# ⑥ 流程：房间胜利后欠选铭印 → 三选一弹层 → 选完才进房间间歇；bot 自动选亦走同一路径
# 测试结束还原 meta（不污染玩家真实存档）。
# ============================================================================

const FIRE := "res://resources/weapon_templates/fire_sword.tres"
const DAGGER := "res://resources/weapon_templates/dagger.tres"
const BURN := "res://resources/symbols/burn.tres"
const DAGGER_SLASH := "res://resources/symbols/dagger_slash.tres"
const FIRE_SLASH := "res://resources/symbols/fire_slash.tres"

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

	_test_mastery_gain(duel)
	_test_catchup(duel)
	_test_r_levels_and_owed(duel)
	_test_imprint_candidates(duel)
	_test_forge_applies(duel)
	_test_display_state(duel)
	_test_sources(duel)
	_test_tune_applies(duel)
	_test_offer_queue(duel)
	_test_merged_settlement(duel)

	duel.mastery.reset_run()
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


# 本测试的装备：火焰剑 + 匕首（两把样板武器），状态清零。
func _equip(duel: DuelController) -> void:
	duel.selected_loadout.clear()
	duel.selected_loadout.append(FIRE)
	duel.selected_loadout.append(DAGGER)
	duel.mastery.reset_run()
	duel.mastery.reset_room()
	duel.reel_system.build_pool(duel.selected_loadout)


# 本房「火焰剑的符号」结算一次（模拟 combat evaluate 的有效结算点）
func _settle_fire(duel: DuelController) -> void:
	duel.mastery.note_settle(BURN)


func _test_mastery_gain(duel: DuelController) -> void:
	_equip(duel)
	_settle_fire(duel)
	duel.mastery.settle_room("normal")
	_check(duel.mastery.mastery.get(FIRE, 0) == 1, "普通房有效结算：火焰剑 +1 熟练")
	_check(duel.mastery.mastery.get(DAGGER, 0) == 0, "未结算的匕首不获得熟练")
	duel.mastery.reset_room()
	_settle_fire(duel)
	duel.mastery.settle_room("elite")
	_check(duel.mastery.mastery.get(FIRE, 0) == 3, "精英房额外 +1：本房 +2（累计 3）")
	duel.mastery.reset_room()
	_settle_fire(duel)
	duel.mastery.settle_room("boss")
	_check(duel.mastery.mastery.get(FIRE, 0) == 5, "BOSS 房额外 +1：本房 +2（累计 5）")
	duel.mastery.reset_room()
	_settle_fire(duel)
	duel.mastery.settle_room("normal")
	_check(duel.mastery.mastery.get(FIRE, 0) == 6, "下一房重新计数（累计 6）")
	# 未装备的样板武器即使有结算也不获得熟练
	duel.selected_loadout.erase(DAGGER)
	duel.mastery.reset_room()
	duel.mastery.note_settle(DAGGER_SLASH)
	duel.mastery.settle_room("boss")
	_check(duel.mastery.mastery.get(DAGGER, 0) == 0, "未装备的武器不获得熟练")
	duel.selected_loadout.append(DAGGER)


# G2-01：局中新换上的武器追赶；开局配装不追赶；不复制铭印；卸下再装保留。
func _test_catchup(duel: DuelController) -> void:
	var m = duel.mastery
	# 开局只有火焰剑，匕首为本局中途换上的新武器
	duel.selected_loadout.clear()
	duel.selected_loadout.append(FIRE)
	m.reset_run()
	duel.selected_loadout.append(DAGGER)
	m.mastery[FIRE] = 5
	m.reset_room()
	m.note_settle(DAGGER_SLASH)
	m.settle_room("normal")
	_check(int(m.mastery.get(DAGGER, 0)) == 2, "新武器普通房：基础 +1 + 追赶 +1")
	_check(m.catchup_target(DAGGER) == 5, "追赶目标 = 本局其它武器最高熟练")
	_check(duel._weapon_info(DAGGER).find("追赶") >= 0, "替换/获得预览展示追赶目标")

	m.reset_room()
	m.note_settle(DAGGER_SLASH)
	m.settle_room("elite")
	_check(int(m.mastery.get(DAGGER, 0)) == 5, "精英房 +3（2 基础 +1 追赶），受每房上限 3")

	m.reset_room()
	m.note_settle(DAGGER_SLASH)
	m.settle_room("normal")
	_check(int(m.mastery.get(DAGGER, 0)) == 6, "追平后按正常 +1，不再追赶")

	# 开局配装不追赶
	_equip(duel)
	m.mastery[FIRE] = 5
	m.reset_room()
	m.note_settle(DAGGER_SLASH)
	m.settle_room("normal")
	_check(int(m.mastery.get(DAGGER, 0)) == 1, "开局配装武器不触发追赶")

	# 追赶只补基础熟练，跨过 R2 仍进入现有铭印队列
	duel.selected_loadout.clear()
	duel.selected_loadout.append(FIRE)
	m.reset_run()
	duel.selected_loadout.append(DAGGER)
	m.mastery[FIRE] = 5
	m.mastery[DAGGER] = 2
	m.reset_room()
	m.note_settle(DAGGER_SLASH)
	m.settle_room("normal")
	_check(int(m.mastery.get(DAGGER, 0)) == 4, "追赶可跨过 R2 门槛")
	_check(m.owed.has(DAGGER), "追赶跨过 R2 时进入现有铭印队列（不自动补发铭印）")

	# 卸下再装：熟练与铭印保留
	m.mastery[FIRE] = 4
	m.imprints[FIRE] = {"forge": 1, "tune": {}}
	duel.selected_loadout.erase(FIRE)
	duel.selected_loadout.append(FIRE)
	_check(int(m.mastery.get(FIRE, 0)) == 4 and m.forge_bonus(FIRE) == 2, "卸下再装保留熟练与铭印")
	duel.mastery.reset_run()
	duel.mastery.reset_room()


func _test_r_levels_and_owed(duel: DuelController) -> void:
	_equip(duel)
	var m = duel.mastery
	_check(m.r_level(FIRE) == 1, "新局火焰剑 R1")
	m.mastery[FIRE] = 2
	m.reset_room()
	_settle_fire(duel)
	m.settle_room("normal")
	_check(m.r_level(FIRE) == 2 and m.owed.count(FIRE) == 1, "累计 3 → R2，欠 1 次铭印")
	m.reset_room()
	m.mastery[FIRE] = 6
	m.reset_room()
	_settle_fire(duel)
	m.settle_room("normal")
	_check(m.r_level(FIRE) == 3 and m.owed.count(FIRE) == 2, "累计 7 → R3，再欠 1 次铭印")
	m.mastery[FIRE] = 10
	m.reset_room()
	_settle_fire(duel)
	m.settle_room("normal")
	_check(m.r_level(FIRE) == 3 and m.owed.count(FIRE) == 2, "累计 11 仍为 R3")
	m.reset_room()
	_settle_fire(duel)
	m.settle_room("normal")
	_check(m.r_level(FIRE) == 4 and m.owed.count(FIRE) == 2, "累计 12 → R4，R4 不再欠铭印")
	m.reset_run()


func _test_imprint_candidates(duel: DuelController) -> void:
	_equip(duel)
	var m = duel.mastery
	var ids := []
	for c in m.imprint_choices(FIRE):
		ids.append(c["id"])
	_check(ids.has("forge"), "锋铸恒在候选中（未达上限）")
	for c in m.imprint_choices(FIRE):
		if c["id"] == "forge":
			_check(c["desc"].begins_with("基础攻击 18 → 20") and c["desc"].find("%") >= 0,
				"锋铸描述给出当前 → 升级后基础攻击与提升幅度")
	_check(m.tune_target(FIRE).get("sym", "") == FIRE_SLASH, "调律目标 = 权重最高且 +1 真实改变格数者（燃烧 5→6 不改格；火斩 3→4 改格）")
	_check(ids.has("tune"), "调律在真实改变格数时出现（火焰剑）")
	for c in m.imprint_choices(FIRE):
		if c["id"] == "tune":
			_check(c["desc"].find("格") >= 0, "调律描述包含真实格数变化")
	m.imprints[FIRE] = {"forge": 2, "tune": {FIRE_SLASH: 2}}
	ids.clear()
	for c in m.imprint_choices(FIRE):
		ids.append(c["id"])
	_check(ids.is_empty(), "同一铭印各 2 次达上限后不再出现候选")
	m.imprints.clear()


func _test_forge_applies(duel: DuelController) -> void:
	_equip(duel)
	var m = duel.mastery
	m.owed.append(FIRE)
	_check(m.choose(FIRE, "forge"), "选择锋铸成功")
	_check(m.forge_bonus(FIRE) == 2, "锋铸：基础攻击加成 +2")
	_check(m.owed.count(FIRE) == 0, "选定后消耗一次欠选")
	duel.reel_system.build_pool(duel.selected_loadout)
	_check(int(duel._weapon_power_map.get(BURN, 0)) == 20, "锋铸写入攻击力映射：18 → 20")
	var fire_res: WeaponData = load(FIRE)
	_check(fire_res.base_power == 18, "共享 .tres 的 base_power 未被修改")
	m.imprints.clear()
	duel.reel_system.build_pool(duel.selected_loadout)


# G2-01：来源记录（ACT / 模式 / 房间 / 节点）与去重、封顶；护符获得写入图鉴。
func _test_sources(duel: DuelController) -> void:
	var act_before: int = duel.current_act
	var node_before: bool = duel.node_mode
	duel.meta["item_sources"] = {}
	duel.current_act = 2
	duel.node_mode = false
	duel._reward_system.remember_weapon(FIRE)
	var arr: Array = duel.meta["item_sources"].get(FIRE, [])
	_check(arr.size() == 1, "武器获得写入来源记录")
	_check(int(arr[0].get("act", 0)) == 2 and String(arr[0].get("mode", "")) == "linear", "来源记录含 ACT 与模式")
	duel._reward_system.remember_weapon(FIRE)
	_check((duel.meta["item_sources"][FIRE] as Array).size() == 1, "同一来源不重复记录")
	for i in 7:
		duel._meta_store.record_source(FIRE, {"act": i, "node_id": "n%d" % i})
	_check((duel.meta["item_sources"][FIRE] as Array).size() == 5, "来源记录按件封顶 5 条")
	var charm := "res://resources/charms/berserker_nail.tres"
	duel.meta["owned_charms"].erase(charm)
	duel._reward_system.remember_charm(charm)
	_check(duel.meta["owned_charms"].has(charm), "护符获得写入图鉴")
	_check(duel.meta["item_sources"].has(charm), "护符获得写入来源记录")
	duel.current_act = act_before
	duel.node_mode = node_before


# G0-02：UI 显示的真实攻击 / 成长状态与结算同一口径，且不写回共享 .tres。
func _test_display_state(duel: DuelController) -> void:
	_equip(duel)
	var m = duel.mastery
	m.owed.append(FIRE)
	_check(m.choose(FIRE, "forge"), "显示测试：选择锋铸成功")
	var info: String = duel._weapon_info(FIRE)
	_check(info.find("攻20") >= 0, "替换摘要显示锋铸后的真实攻击（18→20）")
	_check(info.find("锋铸+2") >= 0, "替换摘要标注锋铸加成")
	_check(info.find("R1") >= 0 and info.find("熟练") >= 0, "替换摘要包含 R 等级与熟练进度")
	var off: String = duel._weapon_off_info(FIRE)
	_check(off.find("卸下") >= 0 and off.find("攻20") >= 0 and off.find("保留") >= 0, "替换预览显示旧武器卸下与熟练保留说明")
	var tip: String = ItemTooltip.for_resource(load(FIRE))
	_check(tip.find("攻20") >= 0 and tip.find("锋铸+2") >= 0, "物品 tooltip 显示真实攻击与锋铸")
	var fire_res: WeaponData = load(FIRE)
	_check(fire_res.base_power == 18, "显示层不写回共享 .tres 的 base_power")
	# 调律目标展示的格数变化 = 真实 build_strips 口径
	var tgt: Dictionary = m.tune_target(FIRE)
	if not tgt.is_empty():
		var before: Dictionary = m.tune_map()
		var after: Dictionary = before.duplicate(true)
		after[FIRE] = after.get(FIRE, {}).duplicate()
		after[FIRE][String(tgt["sym"])] = int(after[FIRE].get(String(tgt["sym"]), 0)) + 1
		var lines: Array = ReelPreview.diff_lines(duel.selected_loadout, duel.selected_loadout,
			duel.selected_skills, duel.selected_charms, duel.room_element_mult,
			duel._reward_system.run_symbol_bonus, duel.deprived_level, duel.pending_chaos,
			int(duel.boss_trash), before, after)
		_check(lines == tgt["lines"], "调律目标展示的格数变化与真实带子口径一致")
	else:
		_check(false, "调律目标候选存在（火焰剑应能真实改变格数）")
	m.imprints.clear()
	duel.reel_system.build_pool(duel.selected_loadout)


func _test_tune_applies(duel: DuelController) -> void:
	_equip(duel)
	var m = duel.mastery
	m.owed.append(FIRE)
	_check(m.choose(FIRE, "tune"), "选择调律成功")
	_check(m.tune_map().get(FIRE, {}).get(FIRE_SLASH, 0) == 1, "调律：目标符号火斩 +1")
	duel.reel_system.build_pool(duel.selected_loadout)
	var w_fs := -1.0
	for it in duel.pool_items:
		if it["name"] == "火焰剑":
			for s in it["syms"]:
				if s[0].resource_path == FIRE_SLASH:
					w_fs = float(s[1])
	_check(is_equal_approx(w_fs, 4.0), "池内火焰剑火斩权重 3 → 4")
	m.imprints.clear()
	duel.reel_system.build_pool(duel.selected_loadout)


# M1：同一房间既升技艺又欠铭印 → 三槽屏只给一张成长卡；本次选技艺，铭印排队到下一战斗房。
func _test_merged_settlement(duel: DuelController) -> void:
	_equip(duel)
	duel.growth.reset_run()
	duel._post_battle.reset_run()
	var m = duel.mastery
	var idx := 0
	for i in range(duel.ROOMS.size()):
		if duel.ROOMS[i].kind == "normal":
			idx = i
			break
	duel.room_index = idx
	duel.in_interroom = false
	duel.growth.xp = 2   # 普通房 +1 → Lv.2，待选技艺
	m.mastery[FIRE] = 2
	m.reset_room()
	_settle_fire(duel)
	duel.room_flow.begin_post_battle()
	_check(duel.room_flow.post_battle_active, "战后成长三槽待选择")
	_check(duel.room_flow.post_battle_has_growth(), "同房触发技艺 + 铭印时成长位有真实成长")
	var first: Array = duel.room_flow.post_offer()
	_check(String(first[2].get("kind", "")) == "perk", "成长队列先给技艺（触发顺序）")
	_check(not duel.in_interroom, "确认前不进入间歇（只打断一次）")
	duel.room_flow.auto_pick_post_battle(["growth"])
	_check(duel.growth.perk_ids.size() == 1 and m.owed.has(FIRE), "本次只应用技艺；铭印留在队列")
	_check(duel.in_interroom and not duel.room_flow.post_battle_active, "确认后进入间歇且无残留")

	# 下一战斗房：未选的铭印进入成长位（同一候选冻结，不重新随机类型）。
	duel.in_interroom = false
	duel.hud.set_interroom_enabled(false)
	duel.room_flow.begin_post_battle()
	var second: Array = duel.room_flow.post_offer()
	_check(String(second[2].get("kind", "")) == "imprint", "下一战斗房成长位轮到铭印")
	duel.room_flow.auto_pick_post_battle(["growth"])
	_check(int(m.imprints[FIRE]["forge"]) + m._tune_count(FIRE) == 1, "第二次成长位应用一次铭印")
	_check(m.owed.is_empty(), "铭印队列清空")
	_check(duel.in_interroom and not duel.room_flow.post_battle_active, "铭印选完进入间歇")
	duel.hud._refresh_meta()
	# 2026-10-31 纠偏 C2：武器区改为大图标卡片，R 等级/熟练/铭印按任务书放进 tooltip；
	# 技艺不再单独占图标行，按任务书并入技能卡 tooltip。断言改为校验新结构的可见信息。
	var row = duel.hud.panel_view.weapons_row
	var fire_card = null
	for c in row.get_children():
		if c.name.begins_with("WCard_") and c.name.ends_with("fire_sword"):
			fire_card = c
	var skill_card = null
	if duel.hud.panel_view.skills_row.get_child_count() > 0:
		skill_card = duel.hud.panel_view.skills_row.get_child(0)
	var perk_name := ""
	if duel.growth.perk_ids.size() > 0:
		perk_name = duel.growth.perk_name(duel.growth.perk_ids[0])
	_check(fire_card != null and fire_card.tooltip_text.find("R2") >= 0, "武器卡 tooltip 含 R2 熟练等级")
	_check(fire_card != null and fire_card.tooltip_text.find("熟练") >= 0, "武器 tooltip 含熟练进度")
	_check(skill_card != null and perk_name != "" and skill_card.tooltip_text.find(perk_name) >= 0,
		"技能卡 tooltip 含已习得技艺")
	# P0-2：等级进玩家标题；常驻行显示历练进度与成长计数（艺/铭），不再重复 Lv.
	_check(duel.hud.player_title.text.find("Lv.2") >= 0, "玩家区：标题显示 Lv.2")
	_check(duel.hud.player_level_label.visible and duel.hud.player_level_label.text.find("/7") >= 0,
		"玩家区：常驻成长行显示历练进度")
	_check(duel.hud.player_level_label.text.find("艺1") >= 0, "玩家区：常驻成长行显示技艺计数")
	duel.growth.reset_run()
	m.reset_run()
	duel._post_battle.reset_run()
	duel.hud.set_interroom_enabled(false)
	duel.in_interroom = false


func _test_offer_queue(duel: DuelController) -> void:
	_equip(duel)
	duel.growth.reset_run()
	duel._post_battle.reset_run()
	var m = duel.mastery
	# 选一间普通房（避免升级带入技艺三选一，单独验证铭印队列）
	var idx := 0
	for i in range(duel.ROOMS.size()):
		if duel.ROOMS[i].kind == "normal":
			idx = i
			break
	duel.room_index = idx
	duel.in_interroom = false
	m.mastery[FIRE] = 2
	m.reset_room()
	_settle_fire(duel)
	duel.room_flow.begin_post_battle()
	_check(m.owed.has(FIRE), "房间胜利后火焰剑 R2 欠铭印")
	var cands: Array = duel.room_flow.post_offer()
	_check(String(cands[2].get("kind", "")) == "imprint", "欠铭印时成长位为铭印")
	_check(duel.room_flow.post_battle_active, "战后成长三槽待处理")
	_check(not duel.in_interroom, "铭印未选完前不进入房间间歇")
	duel.room_flow.auto_pick_post_battle(["growth"])
	_check(int(m.imprints[FIRE]["forge"]) + m._tune_count(FIRE) == 1, "选定后写入一次铭印")
	_check(m.owed.is_empty(), "欠选队列清空")
	_check(duel.in_interroom, "选完铭印后进入房间间歇")
	_check(not duel.room_flow.post_battle_active, "队列结束后无待选")
	m.reset_run()
	duel._post_battle.reset_run()
	duel.hud.set_interroom_enabled(false)
	duel.in_interroom = false
