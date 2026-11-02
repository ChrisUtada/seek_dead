extends Node

# ============================================================================
# M4-01 ACT1 Demo 配置/白名单 · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/m4_demo_test.tscn
#
# 覆盖：
# ① DemoConfig 白名单完整性：路径存在、类别匹配、starter 武器在池内
# ② 开关关闭：武器 38 / 技能 17 / 装备 55、ROOMS = 3 幕 × 8 + 真·最终（25）
# ③ 开关开启：池收窄为白名单（14 武器 / 10 技能 / 27 装备）、ROOMS = ACT1 8 房、无真·最终
# ④ 旧存档池外装备不删除、但整备/商店/铁砧/奖励均不可见
# ⑤ BOSS 主题武器按白名单过滤（ACT1 的 flame_staff 不出现在候选）
# ⑥ 武器熟练/铭印覆盖白名单内非样板武器（毒匕首等）
# 测试结束还原 meta 与 demo 开关（不污染玩家存档/配置）。
# ============================================================================

const CONFIG_PATH := "res://resources/config/demo_config.tres"
const DAGGER := "res://resources/weapon_templates/dagger.tres"
const POISON_DAGGER := "res://resources/weapon_templates/poison_dagger.tres"
const HOLY_SWORD := "res://resources/weapon_templates/holy_sword.tres"
const FLAME_STAFF := "res://resources/weapon_templates/flame_staff.tres"
const OUT_OF_POOL_WEAPON := "res://resources/weapon_templates/holy_lance.tres"
const POISON := "res://resources/symbols/poison.tres"

var _fails := 0
var _checks := 0

const EXPECT_FULL_WEAPONS := 38   # B01 毒系 7 把 + B02 毒系 7 把入库（2026-11-02）
const EXPECT_FULL_SKILLS := 17
const EXPECT_FULL_ITEMS := 55        # 34 护符 + 21 消耗品
const EXPECT_DEMO_WEAPONS := 14      # 计划 13 + ice_staff（M0-02 starter 必须可用，见配置注释）
const EXPECT_DEMO_SKILLS := 10
const EXPECT_DEMO_ITEMS := 27        # 17 护符（含 4 信物）+ 10 消耗品


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	var cfg = load(CONFIG_PATH)
	if cfg == null:
		print("RESULT FAIL (demo_config missing)")
		get_tree().quit(2)
		return
	var was_enabled: bool = cfg.enabled

	_test_whitelist(cfg)

	# —— 关闭开关：正式版全量 ——
	cfg.enabled = false
	var full: DuelController = await _boot()
	if full == null:
		_finish(cfg, was_enabled, null, {})
		return
	var meta_backup: Dictionary = full.meta.duplicate(true)
	_test_full_mode(full)
	_test_non_sample_mastery(full, "正式版全武器熟练")
	full.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# —— 开启开关：ACT1 Demo ——
	cfg.enabled = true
	var demo: DuelController = await _boot()
	if demo == null:
		_finish(cfg, was_enabled, null, meta_backup)
		return
	_check(demo.demo_config == cfg, "测试与 controller 共用同一 DemoConfig 实例")
	_test_demo_pools(demo)
	_test_demo_rooms(demo)
	_test_hidden_owned(demo)
	_test_shop_anvil_filtered(demo)
	_test_boss_reward_filtered(demo)
	_test_non_sample_mastery(demo, "demo 白名单内非样板武器熟练")
	_test_run_end_returns_to_loadout(demo)

	_finish(cfg, was_enabled, demo, meta_backup)


func _test_run_end_returns_to_loadout(duel: DuelController) -> void:
	# 2026-10-31（P0）：一局结束（元进度结算）后回整备，而不是静默开新一局——
	# 试玩者要能花铁砧点、看图鉴、换配装；同时 demo 标题写成试玩收束口径。
	duel.hud._show_meta_choice()
	_check(duel.hud.meta_screen.visible, "局末弹出元进度结算屏")
	_check(String(duel.hud.meta_screen.title_label.text).find("试玩结束") >= 0, "demo 局末标题为「ACT1 试玩结束」")
	var opt: Dictionary = duel._reward_system.roll_meta_choices()[0]
	var before: int = int(duel.meta.get("anvil_points", 0))
	duel._on_meta_choice_chosen(opt)
	_check(int(duel.meta.get("anvil_points", 0)) == before + int(duel.BALANCE.meta_anvil_bonus), "元进度结算：铁砧点数入账")
	_check(not duel.hud.meta_screen.visible, "结算后关闭元进度屏")
	_check(duel.hud.loadout_screen != null and duel.hud.loadout_screen.visible, "一局结束回整备（可换配装 / 花铁砧点 / 看图鉴）")


func _finish(cfg, was_enabled: bool, duel: DuelController, meta_backup: Dictionary) -> void:
	cfg.enabled = was_enabled
	if duel != null and not meta_backup.is_empty():
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


# ① 白名单自身完整性
func _test_whitelist(cfg) -> void:
	_check(cfg.weapon_pool.size() == EXPECT_DEMO_WEAPONS, "武器白名单 %d 条" % EXPECT_DEMO_WEAPONS)
	_check(cfg.skill_pool.size() == EXPECT_DEMO_SKILLS, "技能白名单 %d 条" % EXPECT_DEMO_SKILLS)
	_check(cfg.charm_pool.size() == 17, "护符白名单 17 条（13 普通 + 4 信物）")
	_check(cfg.consumable_pool.size() == 10, "消耗品白名单 10 条")

	var bad_weapon := _first_invalid(cfg.weapon_pool, func(d): return d is WeaponData)
	var bad_skill := _first_invalid(cfg.skill_pool, func(d): return d is SkillData)
	var bad_charm := _first_invalid(cfg.charm_pool, func(d): return d is ItemData and d.category == "passive")
	var bad_item := _first_invalid(cfg.consumable_pool, func(d): return d is ItemData and d.category == "active")
	_check(bad_weapon == "", "武器白名单路径存在且为 WeaponData" + ("" if bad_weapon == "" else "：" + bad_weapon))
	_check(bad_skill == "", "技能白名单路径存在且为 SkillData" + ("" if bad_skill == "" else "：" + bad_skill))
	_check(bad_charm == "", "护符白名单路径存在且为 passive" + ("" if bad_charm == "" else "：" + bad_charm))
	_check(bad_item == "", "消耗品白名单路径存在且为 active" + ("" if bad_item == "" else "：" + bad_item))

	for p in [DAGGER, "res://resources/weapon_templates/fire_sword.tres",
			"res://resources/weapon_templates/battle_axe.tres", "res://resources/weapon_templates/ice_staff.tres"]:
		_check(cfg.weapon_pool.has(p), "新档 starter 武器在白名单内：" + p.get_file())
	var common_charms := 0
	for p in cfg.charm_pool:
		if String(load(p).get("rarity")) == "common":
			common_charms += 1
	_check(common_charms >= 4, "白名单至少 4 个 common 护符（starter 护符来源）")


func _first_invalid(paths: Array, pred: Callable) -> String:
	for p in paths:
		if not ResourceLoader.exists(p):
			return p
		var d = load(p)
		if d == null or not pred.call(d):
			return p
	return ""


# ② 关闭开关 = 正式版全量
func _test_full_mode(duel: DuelController) -> void:
	_check(duel.WEAPON_POOL.size() == EXPECT_FULL_WEAPONS, "关闭开关：武器池全量 %d" % EXPECT_FULL_WEAPONS)
	_check(duel.SKILL_POOL.size() == EXPECT_FULL_SKILLS, "关闭开关：技能池全量 %d" % EXPECT_FULL_SKILLS)
	_check(duel.ITEM_POOL.size() == EXPECT_FULL_ITEMS, "关闭开关：装备池全量 %d" % EXPECT_FULL_ITEMS)
	_check(duel.ROOMS.size() == 25, "关闭开关：ROOMS = 3 幕 × 8 + 真·最终（25）")
	var final_count := 0
	for r in duel.ROOMS:
		if r.final_boss:
			final_count += 1
	_check(final_count == 1, "关闭开关：含真·最终战")


# ③ demo 池收窄
func _test_demo_pools(duel: DuelController) -> void:
	_check(duel.WEAPON_POOL.size() == EXPECT_DEMO_WEAPONS, "demo：武器池收窄为 %d" % EXPECT_DEMO_WEAPONS)
	_check(duel.SKILL_POOL.size() == EXPECT_DEMO_SKILLS, "demo：技能池收窄为 %d" % EXPECT_DEMO_SKILLS)
	_check(duel.ITEM_POOL.size() == EXPECT_DEMO_ITEMS, "demo：装备池收窄为 %d" % EXPECT_DEMO_ITEMS)
	var leaked := ""
	for p in duel.WEAPON_POOL:
		if not duel.demo_config.allows_weapon(p):
			leaked = p
	for p in duel.SKILL_POOL:
		if not duel.demo_config.allows_skill(p):
			leaked = p
	for p in duel.ITEM_POOL:
		if not (duel.demo_config.allows_charm(p) or duel.demo_config.allows_consumable(p)):
			leaked = p
	_check(leaked == "", "demo：池内无白名单外内容" + ("" if leaked == "" else "：" + leaked))


# ④ ACT1 房间范围
func _test_demo_rooms(duel: DuelController) -> void:
	_check(duel.ROOMS.size() == 8, "demo：ROOMS = ACT1 8 房")
	var all_act1 := true
	var has_final := false
	for r in duel.ROOMS:
		if int(r.act) != 1:
			all_act1 = false
		if r.final_boss:
			has_final = true
	_check(all_act1, "demo：全部房间 act == 1")
	_check(not has_final, "demo：不含真·最终战")
	_check(duel.ALL_ROOMS.size() == 20, "demo：ALL_ROOMS 收窄为 ACT1 20 房（12 普通 + 4 精英 + 4 BOSS）")


# ④b 旧存档池外内容保留但不可见
func _test_hidden_owned(duel: DuelController) -> void:
	duel.meta["owned_weapons"] = [DAGGER, OUT_OF_POOL_WEAPON]
	var arr: Array = duel._loadout_system.owned_arr("weapon")
	_check(arr.has(DAGGER), "demo：整备可选白名单内已拥有武器")
	_check(not arr.has(OUT_OF_POOL_WEAPON), "demo：整备隐藏池外已拥有武器")
	_check(duel.meta["owned_weapons"].has(OUT_OF_POOL_WEAPON), "demo：池外已拥有内容未被删除（关闭开关即恢复）")


# ⑤ 商店 / 铁砧候选均落在白名单
func _test_shop_anvil_filtered(duel: DuelController) -> void:
	var bad := ""
	for i in range(6):
		duel._shop_system.roll_shop()
		for o in duel._shop_system.shop_offers:
			if not _in_whitelist(duel.demo_config, o["kind"], o["path"]):
				bad = "%s (%s)" % [o["path"], o["kind"]]
	_check(bad == "", "demo：商店 6 次刷新全部在白名单内" + ("" if bad == "" else "：" + bad))

	var anvil_bad := ""
	for p in duel._anvil_system._anvil_pool():
		var d = load(p)
		var ok: bool = (d is WeaponData and duel.demo_config.allows_weapon(p)) \
			or (d is ItemData and d.category == "passive" and duel.demo_config.allows_charm(p))
		if not ok:
			anvil_bad = p
	_check(anvil_bad == "", "demo：铁砧池全部在白名单内" + ("" if anvil_bad == "" else "：" + anvil_bad))


# ⑤b BOSS 主题武器过滤
func _test_boss_reward_filtered(duel: DuelController) -> void:
	var boss_room: RoomData = null
	for r in duel.ROOMS:
		if r.kind == "boss":
			boss_room = r
			break
	_check(boss_room != null, "demo：能找到 ACT1 BOSS 房")
	if boss_room == null:
		return
	var card_paths := []
	for i in range(8):
		for c in duel._reward_system.roll_boss_rewards(boss_room):
			if c.get("kind", "") == "boss_weapon":
				card_paths.append(c["path"])
	var bad := ""
	for p in card_paths:
		if not duel.demo_config.allows_weapon(p):
			bad = p
	_check(not card_paths.has(FLAME_STAFF), "demo：BOSS 候选不含白名单外的 flame_staff")
	_check(bad == "", "demo：BOSS 武器候选全部在白名单内" + ("" if bad == "" else "：" + bad))


# ⑥ 成长规则覆盖非样板武器（毒匕首）
func _test_non_sample_mastery(duel: DuelController, label: String) -> void:
	duel.selected_loadout.clear()
	duel.selected_loadout.append(POISON_DAGGER)
	duel.selected_loadout.append(HOLY_SWORD)
	duel.mastery.reset_run()
	duel.mastery.note_settle(POISON)
	duel.mastery.settle_room("normal")
	_check(int(duel.mastery.mastery.get(POISON_DAGGER, 0)) == 1, label + "：毒匕首获得 +1 熟练")
	_check(duel.mastery.progress_text(POISON_DAGGER) != "", label + "：毒匕首显示 R 进度")
	_check(duel.mastery.imprint_choices(POISON_DAGGER).size() > 0, label + "：毒匕首可选择铭印")
	duel.mastery.reset_room()
	duel.mastery.mastery[POISON_DAGGER] = 2
	duel.mastery.note_settle(POISON)
	duel.mastery.settle_room("normal")
	_check(duel.mastery.r_level(POISON_DAGGER) == 2 and duel.mastery.owed.count(POISON_DAGGER) == 1,
		label + "：累计 3 → R2 并欠一次铭印")
	duel.mastery.reset_run()


func _in_whitelist(cfg, kind: String, path: String) -> bool:
	match kind:
		"weapon": return cfg.allows_weapon(path)
		"skill":  return cfg.allows_skill(path)
		"passive": return cfg.allows_charm(path)
		"active": return cfg.allows_consumable(path)
	return false
