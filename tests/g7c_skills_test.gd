extends Node

# ============================================================================
# G7-C · 技能收藏语义（owned_skills）headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/g7c_skills_test.tscn
#
# 覆盖：
# ① 新档只给 4 个基础技能；老档（有存档但无 owned_skills）迁移授予当时全部技能；
# ② 铁砧池包含技能，且 owned 判定 / 授予写入 owned_skills（不再误写 owned_weapons）；
# ③ 商店购买技能写入 owned_skills，并同时进本局 selected_skills；
# ④ 整备屏 owned_arr("skill") 只返回已拥有技能；
# ⑤ 图鉴支持技能分类（列表 / 详情不报错），局末「新收藏」计入技能；
# ⑥ sanitize_owned 只保留 SkillData，不污染其它收藏池。
# 测试在隔离 APPDATA 下运行，不触碰真实存档。
# ============================================================================

const STARTERS := [
	"res://resources/skills/haste.tres",
	"res://resources/skills/magic_bolt.tres",
	"res://resources/skills/rage.tres",
	"res://resources/skills/recovery.tres",
]

var _fails := 0
var _checks := 0


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	SaveSystem.reset_lobby_data()

	# ① 老档迁移：有存档但没有 owned_skills → 授予当时全部技能。
	SaveSystem.save_lobby_data({"anvil_meta": {
		"anvil_points": 0, "owned_weapons": [], "owned_charms": [], "owned_consumables": [],
		"anvil_pity": 0, "collection_milestones": [], "item_sources": {},
		"career": {"unlocked": [], "bosses": []}, "codex": {}, "forge_styles": {},
	}})
	SaveSystem.flush_lobby_data()
	var old_duel: DuelController = await _boot()
	if old_duel != null:
		_check(old_duel.meta["owned_skills"].size() == 17,
			"老档迁移只授予 G7-C 前的 17 件技能（实际 %d）" % old_duel.meta["owned_skills"].size())
		_check(old_duel.meta["owned_skills"].has("res://resources/skills/atonement_light.tres"),
			"老档迁移包含非初始旧技能 atonement_light")
		_check(not old_duel.meta["owned_skills"].has("res://resources/skills/frost_shard.tres"),
			"老档迁移不赠送 G7-C 新增技能 frost_shard")
		old_duel.queue_free()
		await get_tree().process_frame
	SaveSystem.reset_lobby_data()

	# ① 新档：只给 4 个基础技能。
	var duel: DuelController = await _boot()
	if duel == null:
		print("RESULT FAIL (boot)")
		get_tree().quit(2)
		return
	var meta_backup: Dictionary = duel.meta.duplicate(true)
	_test_new_save(duel)
	_test_anvil(duel, meta_backup)
	_test_shop(duel, meta_backup)
	_test_loadout(duel)
	_test_codex(duel)
	_test_run_summary(duel, meta_backup)
	_test_sanitize(duel, meta_backup)

	_restore_meta(duel, meta_backup)
	SaveSystem.reset_lobby_data()
	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _boot() -> DuelController:
	seed(9301)
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.board_config.enabled = false
	return duel


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _test_new_save(duel: DuelController) -> void:
	var owned: Array = duel.meta.get("owned_skills", [])
	_check(owned.size() == STARTERS.size(), "新档初始技能 %d 个（期望 %d）" % [owned.size(), STARTERS.size()])
	for p in STARTERS:
		_check(owned.has(p), "新档包含初始技能 %s" % p.get_file())
	_check(not owned.has("res://resources/skills/atonement_light.tres"), "新档不含非初始技能 atonement_light")


func _test_anvil(duel: DuelController, meta_backup: Dictionary) -> void:
	var pool: Array = duel._anvil_system._anvil_pool()
	var has_skill := false
	for p in pool:
		if duel.SKILL_POOL.has(p):
			has_skill = true
			break
	_check(has_skill, "铁砧池包含技能")
	_check(pool.size() == duel.WEAPON_POOL.size() + _passive_count(duel) + duel.SKILL_POOL.size(),
		"铁砧池 = 武器 + 非信物护符 + 技能（%d）" % pool.size())
	_check(duel._anvil_system._anvil_is_owned(STARTERS[0]), "初始技能判定为已拥有")
	var unowned := _first_unowned_skill(duel)
	_check(unowned != "", "存在未拥有技能用于授予测试")
	if unowned != "":
		_check(not duel._anvil_system._anvil_is_owned(unowned), "未拥有技能判定为未拥有")
		duel._anvil_system._anvil_grant_owned(unowned)
		_check(duel.meta["owned_skills"].has(unowned), "铁砧授予写入 owned_skills")
		_check(not duel.meta["owned_weapons"].has(unowned), "铁砧授予不写入 owned_weapons")
		_restore_meta(duel, meta_backup)


func _test_shop(duel: DuelController, meta_backup: Dictionary) -> void:
	var unowned := _first_unowned_skill(duel)
	if unowned == "":
		_check(false, "商店购买测试缺少未拥有技能")
		return
	duel.selected_skills.erase(unowned)
	duel.gold = 9999
	duel.skill_max = maxi(duel.skill_max, duel.selected_skills.size() + 1)
	var offer := {"path": unowned, "kind": "skill", "name": unowned.get_file().get_basename(), "price": 1, "sold": false}
	duel._shop_system.on_shop_buy_pressed(offer)
	_check(duel.meta["owned_skills"].has(unowned), "商店购买技能写入 owned_skills")
	_check(duel.selected_skills.has(unowned), "商店购买技能同时进入本局技能列表")
	_restore_meta(duel, meta_backup)


func _test_loadout(duel: DuelController) -> void:
	var owned: Array = duel._loadout_system.owned_arr("skill")
	var meta_owned: Array = duel.meta.get("owned_skills", [])
	_check(owned.size() == meta_owned.size(), "整备技能池 = owned_skills（%d / %d）" % [owned.size(), meta_owned.size()])
	for p in owned:
		_check(meta_owned.has(p), "整备技能池项均来自 owned_skills：%s" % String(p).get_file())


func _test_codex(duel: DuelController) -> void:
	var entries: Array = duel._codex.list_entries("skill")
	_check(entries.size() == duel.SKILL_POOL.size(), "图鉴技能分类覆盖全池（%d / %d）" % [entries.size(), duel.SKILL_POOL.size()])
	var starter := String(STARTERS[0])
	var found: Dictionary = {}
	for e in entries:
		if String(e.get("path", "")) == starter:
			found = e
			break
	_check(not found.is_empty(), "图鉴技能列表包含初始技能")
	_check(bool(found.get("owned", false)), "初始技能在图鉴标记为已拥有")
	_check(String(found.get("name", "")) != "？？？", "已拥有技能显示真实名称")
	var lines: Array = duel._codex.detail_lines(starter)
	_check(lines.size() > 0, "图鉴技能详情可生成")
	if lines.size() > 0:
		_check(String(lines[0]).contains("技能"), "图鉴详情首行标注技能类别")


func _test_run_summary(duel: DuelController, meta_backup: Dictionary) -> void:
	duel._run_summary.snapshot()
	var unowned := _first_unowned_skill(duel)
	if unowned == "":
		_check(false, "局末新收藏测试缺少未拥有技能")
		return
	duel.meta["owned_skills"].append(unowned)
	var line := String(duel._run_summary.collection_line())
	var nm := String(load(unowned).buff_name)
	_check(line.contains(nm), "局末新收藏计入技能（%s）" % nm)
	_restore_meta(duel, meta_backup)


func _test_sanitize(duel: DuelController, meta_backup: Dictionary) -> void:
	duel.meta["owned_skills"].append("res://resources/weapon_templates/dagger.tres")
	duel._meta_store.sanitize_owned()
	_check(not duel.meta["owned_skills"].has("res://resources/weapon_templates/dagger.tres"), "sanitize 清除 owned_skills 中的非技能路径")
	_check(duel.meta["owned_skills"].has(STARTERS[0]), "sanitize 保留真实技能")
	_restore_meta(duel, meta_backup)


func _restore_meta(duel: DuelController, backup: Dictionary) -> void:
	# 原地恢复：MetaStore 持有 ctrl.meta 的引用，不能整体替换字典对象。
	duel.meta.clear()
	for k in backup.keys():
		duel.meta[k] = backup[k].duplicate(true) if backup[k] is Dictionary or backup[k] is Array else backup[k]


func _passive_count(duel: DuelController) -> int:
	var n := 0
	for p in duel.ITEM_POOL:
		var d = load(p)
		if d is ItemData and d.category == "passive" and not duel._meta_store._is_boss_relic(d, p):
			n += 1
	return n


func _first_unowned_skill(duel: DuelController) -> String:
	for p in duel.SKILL_POOL:
		if not duel.meta["owned_skills"].has(p):
			return String(p)
	return ""
