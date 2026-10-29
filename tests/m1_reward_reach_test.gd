extends Node

# ============================================================================
# M1 奖励可达性 / 结果前置 / 新档收藏 / 预览 / 遥测 · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/m1_reward_reach_test.tscn
#
# 覆盖（docs/统一落地执行计划.md M1）：
# ① 候选池：幕一不出武器；幕二/幕三满双武器时武器卡仍入池（不再被槽位前置拦截）
# ② 展示前预确定：武器卡 payload 指向具体未装备武器，确认后不再二次随机
# ③ 空槽：奖励武器进本局配装 + 写局外收藏
# ④ 满槽：选择武器卡 → 替换弹层 → 替换后旧武器移除、新武器入槽入收藏
# ⑤ BOSS 主题武器在满双武器时仍可作为候选
# ⑥ 精英动态位在满双武器时仍可出武器
# ⑦ 卖出不低于双武器下限（loadout_min=2）
# ⑧ M1-02 符号灌注：只出真实增格候选、展示前定符号、无二次随机、无死 roll
# ⑨ M1-02 消耗品：展示前定物、按 payload 入腰带、腰带满折金币
# ⑩ M1-03 新档初始收藏子集 + 老档只补不删 + 图鉴留有未解锁
# ⑪ M1-05 局末元进度单结果 + 过期文案清除
# ⑫ M1-04 转轮带预览与真实带子/共鸣激活集一致
# ⑬ M1-06 遥测计数
# 测试结束还原 meta（不污染玩家真实存档）。
# ============================================================================

const TRIALS := 60

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
	var meta_backup: Dictionary = duel.meta.duplicate(true)   # 测试会写 owned/milestone：结束还原，不污染真实存档

	_test_pool_gating(duel)
	_test_roll_prepick(duel)
	_test_apply_free_slot(duel)
	_test_full_slot_replace(duel)
	_test_boss_weapons_when_full(duel)
	_test_elite_weapon_when_full(duel)
	_test_sell_guard(duel)
	_test_symbol_prepick(duel)
	_test_consumable_prepick(duel)
	_test_starter_seed(duel)
	_test_meta_single_result(duel)
	_test_preview_matches_reels(duel)
	_test_telemetry(duel)

	# 还原 meta（保持引用，MetaStore 仍指向同一字典）并落盘
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
	duel._confirm_loadout()   # 构建本局房间序列（ROOMS 为空时 act 默认 1，无法测幕二/三）
	await get_tree().process_frame
	return duel


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _room_index_of(duel: DuelController, act: int, kind: String) -> int:
	for i in range(duel.ROOMS.size()):
		var r: RoomData = duel.ROOMS[i]
		if r.act == act and r.kind == kind and not r.final_boss:
			return i
	return 0


func _fill_two_weapons(duel: DuelController) -> void:
	duel.selected_loadout.clear()
	duel.loadout_max = 2
	for i in range(min(2, duel.WEAPON_POOL.size())):
		duel.selected_loadout.append(duel.WEAPON_POOL[i])
	duel._build_pool(duel.selected_loadout)


func _payload_only(duel: DuelController, path: String) -> void:
	duel._reward_system.choice_payloads.clear()
	duel._reward_system.choice_payloads.append({"kind": "weapon", "path": path, "title": "武器 · 测试", "desc": "测试"})


# ① 候选池闸门：幕一排除，幕二/三保留（与武器槽占用无关）
func _test_pool_gating(duel: DuelController) -> void:
	_fill_two_weapons(duel)
	var p1: Array = duel._reward_system.build_reward_pool(1)
	var p2: Array = duel._reward_system.build_reward_pool(2)
	var p3: Array = duel._reward_system.build_reward_pool(3)
	_check(p1.filter(func(rw): return rw.id == "weapon").is_empty(), "幕一候选池不含武器")
	_check(not p2.filter(func(rw): return rw.id == "weapon").is_empty(), "幕二满双武器时武器仍在候选池")
	_check(not p3.filter(func(rw): return rw.id == "weapon").is_empty(), "幕三满双武器时武器仍在候选池")


# ② roll_rewards 产出的武器卡带已确定 payload；幕一不会出现
func _test_roll_prepick(duel: DuelController) -> void:
	_fill_two_weapons(duel)
	duel.room_index = _room_index_of(duel, 1, "normal")
	var act1_weapon := false
	for i in range(10):
		for rw in duel._reward_system.roll_rewards():
			if rw.id == "weapon":
				act1_weapon = true
	_check(not act1_weapon, "幕一 10 次 roll 不出武器卡")

	duel.room_index = _room_index_of(duel, 2, "normal")
	var saw := false
	var payload_ok := true
	for i in range(TRIALS):
		var choices: Array = duel._reward_system.roll_rewards()
		for j in range(choices.size()):
			if choices[j].id != "weapon":
				continue
			saw = true
			var pl: Dictionary = duel._reward_system.payload_at(j)
			if pl.is_empty():
				payload_ok = false
				continue
			var path := String(pl.get("path", ""))
			var wd: WeaponData = load(path)
			if path == "" or duel.selected_loadout.has(path) or wd == null:
				payload_ok = false
			elif not String(pl.get("title", "")).contains(wd.weapon_name):
				payload_ok = false
			break
		if saw:
			break
	_check(saw, "幕二 %d 次 roll 内出现武器卡" % TRIALS)
	_check(payload_ok, "武器卡 payload 指向具体未装备武器且标题含武器名")


# ③ 空槽：进配装 + 写入收藏
func _test_apply_free_slot(duel: DuelController) -> void:
	_fill_two_weapons(duel)
	duel.selected_loadout.erase(duel.selected_loadout[1])
	var new_p := ""
	for p in duel.WEAPON_POOL:
		if not duel.selected_loadout.has(p):
			new_p = p
			break
	duel.meta["owned_weapons"].erase(new_p)
	_payload_only(duel, new_p)
	duel._reward_system.apply_reward("weapon", 0)
	_check(duel.selected_loadout.has(new_p), "空槽奖励武器进入本局配装")
	_check(duel.selected_loadout.size() == 2, "配装回到双武器")
	_check(duel.meta["owned_weapons"].has(new_p), "新武器写入局外收藏 owned_weapons")


# ④ 满槽：替换弹层 + 替换结果
func _test_full_slot_replace(duel: DuelController) -> void:
	_fill_two_weapons(duel)
	var new_p := ""
	for p in duel.WEAPON_POOL:
		if not duel.selected_loadout.has(p):
			new_p = p
			break
	var old_p: String = duel.selected_loadout[0]
	duel.meta["owned_weapons"].erase(new_p)
	duel.reward_is_boss = false
	duel.reward_choices = [duel._reward_system._find_reward("weapon")]
	_payload_only(duel, new_p)
	duel._on_reward_chosen("weapon", 0)
	_check(duel.hud._replace_dialog != null and duel.hud._replace_dialog.visible, "满槽选武器卡弹出替换弹层")
	duel.hud._on_replace_chosen(old_p)
	_check(not duel.selected_loadout.has(old_p), "替换后旧武器移出配装")
	_check(duel.selected_loadout.has(new_p), "替换后新武器进入配装")
	_check(duel.selected_loadout.size() == 2, "替换后仍为双武器")
	_check(duel.meta["owned_weapons"].has(new_p), "替换获得的新武器写入局外收藏")


# ⑤ BOSS 主题武器：满双武器仍作为候选
func _test_boss_weapons_when_full(duel: DuelController) -> void:
	_fill_two_weapons(duel)
	var urn: RoomData = null
	for r in duel.ALL_ROOMS:
		if r.final_boss == false and r.kind == "boss" and r.boss_reward_weapons.size() >= 2:
			urn = r
			break
	_check(urn != null, "找到带主题武器池的 BOSS 房")
	if urn == null:
		return
	var saw := false
	for i in range(20):
		for c in duel._reward_system.roll_boss_rewards(urn):
			if String(c.get("kind", "")) == "boss_weapon":
				saw = true
				_check(not duel.selected_loadout.has(String(c.get("path", ""))), "BOSS 武器候选不重复已装备武器")
				break
		if saw:
			break
	_check(saw, "满双武器时 BOSS 主题武器仍出现在候选中")


# ⑥ 精英动态位：满双武器仍可出武器
func _test_elite_weapon_when_full(duel: DuelController) -> void:
	_fill_two_weapons(duel)
	duel.room_index = _room_index_of(duel, 2, "elite")
	var saw := false
	for i in range(TRIALS):
		for rw in duel._reward_system.roll_elite_rewards():
			if rw.id == "weapon":
				saw = true
				break
		if saw:
			break
	_check(saw, "满双武器时精英动态位仍可出现武器")


# ⑦ 卖出下限
func _test_sell_guard(duel: DuelController) -> void:
	_fill_two_weapons(duel)
	var before := duel.selected_loadout.size()
	duel._on_shop_sell_pressed(duel.selected_loadout[0], "weapon")
	_check(duel.selected_loadout.size() == before, "双武器时无法卖出低于下限")


# ⑧ M1-02 符号灌注：候选只含真实增格；卡片 payload 定死符号；应用不再随机
func _test_symbol_prepick(duel: DuelController) -> void:
	_fill_two_weapons(duel)
	var rs = duel._reward_system
	var cands: Array = rs.symbol_infusions()
	_check(not cands.is_empty(), "双武器下存在可使格数增加的灌注候选")
	var bad := 0
	for c in cands:
		if int(c["after"]) <= int(c["before"]):
			bad += 1
	_check(bad == 0, "灌注候选全部能让转轮带格数真正增加（无死 roll 兜底）")
	var pl: Dictionary = rs._symbol_payload()
	_check(String(pl.get("kind", "")) == "symbol" and String(pl.get("path", "")) != "", "符号灌注可在展示前确定具体符号")
	var sym: SymbolData = load(String(pl.get("path", "")))
	var before: int = rs._symbol_cells(sym, 0.0)
	rs.run_symbol_bonus.clear()
	rs.choice_payloads.clear()
	rs.choice_payloads.append(pl)
	rs.apply_reward("symbol", 0)
	_check(rs.run_symbol_bonus.has(String(pl["path"])), "灌注按 payload 的符号生效（无二次随机）")
	_check(rs.run_symbol_bonus.size() == 1, "一次灌注只影响一个符号")
	_check(rs._symbol_cells(sym, 0.0) > before, "灌注后该符号的转轮带格数真实增加")
	# 无有效变化 → 整张符号卡不进候选池
	duel.selected_loadout.clear()
	duel.selected_loadout.append("res://resources/weapon_templates/dagger.tres")
	duel._build_pool(duel.selected_loadout)
	rs.run_symbol_bonus.clear()
	var pool: Array = rs.build_reward_pool(2)
	_check(pool.filter(func(rw): return rw.id == "symbol").is_empty(), "无有效灌注时不出现符号卡")


# ⑨ M1-02 消耗品：展示前定物、按 payload 入腰带；腰带满时卡片直接说明折算金币
func _test_consumable_prepick(duel: DuelController) -> void:
	var rs = duel._reward_system
	duel.consumable_slots.clear()
	var pl: Dictionary = rs._consumable_payload()
	_check(String(pl.get("kind", "")) == "consumable" and String(pl.get("path", "")) != "", "消耗品奖励可在展示前确定具体物品")
	rs.choice_payloads.clear()
	rs.choice_payloads.append(pl)
	rs.apply_reward("consumable", 0)
	var got := duel.consumable_slots.size() == 1 and String(duel.consumable_slots[0]["path"]) == String(pl["path"])
	_check(got, "消耗品按 payload 入腰带（无二次随机）")
	while duel.consumable_slots.size() < duel.CONSUMABLE_CAP:
		duel.consumable_slots.append({"path": String(pl["path"]), "item_id": "", "charges": 1, "uid": "test%d" % duel.consumable_slots.size()})
	var pl2: Dictionary = rs._consumable_payload()
	_check(String(pl2.get("desc", "")).contains("折算金币"), "腰带满时卡片直接说明折算金币")
	var g0: int = duel.gold
	rs.choice_payloads.clear()
	rs.choice_payloads.append(pl2)
	rs.apply_reward("consumable", 0)
	_check(duel.gold > g0 and duel.consumable_slots.size() == duel.CONSUMABLE_CAP, "腰带满时按卖价折算金币且不塞格")


# ⑩ M1-03 新档初始收藏：基础子集 + 老档只补不删
func _test_starter_seed(duel: DuelController) -> void:
	var ms = duel._meta_store
	var starters: Array = ms._starter_weapons()
	_check(starters.size() == 4 and starters.has("res://resources/weapon_templates/dagger.tres")
		and starters.has("res://resources/weapon_templates/fire_sword.tres")
		and starters.has("res://resources/weapon_templates/battle_axe.tres")
		and starters.has("res://resources/weapon_templates/ice_staff.tres"), "初始武器子集 = 匕首/火焰剑/战斧/霜晶法杖")
	var charms: Array = ms._starter_charms()
	_check(charms.size() == 4, "初始护符子集 4 件")
	var relic_leak := false
	for p in charms:
		if ms._is_boss_relic(load(p), p):
			relic_leak = true
	_check(not relic_leak, "初始护符不含 BOSS 信物")
	# 迁移：老档已有收藏保留 + 补足基础子集 + 新档图鉴仍留未解锁内容
	var backup := {}
	for k in ["owned_weapons", "owned_charms", "owned_consumables"]:
		backup[k] = duel.meta[k].duplicate()
	duel.meta["owned_weapons"] = ["res://resources/weapon_templates/iron_sword.tres"]
	duel.meta["owned_charms"] = []
	duel.meta["owned_consumables"] = []
	ms.seed_default_owned()
	_check(duel.meta["owned_weapons"].has("res://resources/weapon_templates/iron_sword.tres"), "老档已获得的武器不被删除")
	_check(duel.meta["owned_weapons"].has("res://resources/weapon_templates/dagger.tres"), "老档补足基础武器子集")
	_check(duel.meta["owned_consumables"].size() > 0, "基础消耗品已播种")
	var pct: float = duel._anvil_system._anvil_collection_pct()
	_check(pct < 0.5, "新档初始图鉴完成度 < 50%（存在真实未解锁内容）")
	for k in backup:
		duel.meta[k] = backup[k]
	ms.save_meta()


# ⑪ M1-05 局末元进度：只有铁砧点一个真实结果，文案不再承诺线性成长
func _test_meta_single_result(duel: DuelController) -> void:
	var choices: Array = duel._reward_system.roll_meta_choices()
	_check(choices.size() == 1 and String(choices[0].get("kind", "")) == "anvil", "局末元进度只有铁砧点一个结果")
	duel.hud.meta_screen.configure(duel, duel.hud)
	duel.hud.meta_screen.show_choice()
	var sub: String = duel.hud.meta_screen.sub_label.text
	var title: String = duel.hud.meta_screen.title_label.text
	_check(not sub.contains("线性成长") and not sub.contains("基础伤害"), "元进度文案不再承诺不存在的线性成长")
	_check(title.contains("本局获得"), "单结果时标题改为「本局获得」")
	duel.hud.meta_screen.hide_screen()


# ⑫ M1-04/M1-06 预览与实际带子一致 + 共鸣激活集一致（读代码无法解释的偏差在此暴露）
func _test_preview_matches_reels(duel: DuelController) -> void:
	_fill_two_weapons(duel)
	duel.reel_system.build_strips()
	var strip: Array = duel.reel_system.reel_strips[0]
	var comp: Dictionary = ReelPreview.compose(
		duel.selected_loadout, duel.selected_skills, duel.selected_charms,
		duel.room_element_mult, duel._reward_system.run_symbol_bonus, duel.deprived_level,
		duel.pending_chaos, int(duel.boss_trash))
	var cells_by_path := {}
	for r in comp["rows"]:
		cells_by_path[String(r["path"])] = int(cells_by_path.get(String(r["path"]), 0)) + int(r["cells"])
	var actual := {}
	for c in strip:
		var p: String = c[0].resource_path
		actual[p] = int(actual.get(p, 0)) + 1
	var total: int = int(comp["total_cells"])
	# 最小带长保护会把整份带子平铺到 ≥30 格——各符号/各类型按同一倍数放大，先求倍数再比对
	var mult: int = strip.size() / maxi(1, total) if strip.size() % maxi(1, total) == 0 else -1
	var per_path_ok := mult > 0
	for p in cells_by_path:
		if int(actual.get(p, 0)) != int(cells_by_path[p]) * mult:
			per_path_ok = false
	_check(per_path_ok, "预览各符号格数与实际带子一致")
	_check(mult > 0, "预览带长与实际带子成整数倍（含 MISS/金币）")
	_check(int(actual.get("res://resources/symbols/miss.tres", -1)) == int(comp["miss_cells"]) * mult, "预览 MISS 格数与实际一致")
	var prev_syn: Array = ReelPreview.active_synergies(duel.selected_loadout, duel.selected_charms)
	var real_syn: Array = duel._synergy_system.active_synergies()
	_check(prev_syn.size() == real_syn.size(), "共鸣预览与结算激活集一致")


# ⑬ M1-06 遥测计数
func _test_telemetry(duel: DuelController) -> void:
	var t = duel._telemetry
	t.reset()
	t.spin_start()
	t.spin_end()
	t.on_turn(true)
	t.on_turn(false)
	t.on_player_hit(10, 3, 7)
	t.on_reward_shown(3)
	t.on_reward_pick("gold")
	t.on_weapon_swap()
	t.on_room_start()
	t.on_room_clear()
	_check(t.spins == 1 and t.turns == 2 and t.triples == 1, "遥测：旋转/回合/三连计数")
	_check(t.damage_taken == 7 and t.damage_blocked == 3 and t.enemy_attacks == 1, "遥测：承伤与格挡")
	_check(absf(t.triple_rate() - 0.5) < 0.001, "遥测：三连率")
	_check(t.weapon_swaps == 1 and t.room_times.size() == 1, "遥测：武器替换与清房耗时")
	_check(t.reward_pick_rate() > 0.0, "遥测：奖励选择率")
	_check(t.summary_text().contains("三连"), "遥测：可输出一行摘要")
	t.reset()
	_check(t.turns == 0 and t.spin_seconds == 0.0, "遥测：reset 清零")
