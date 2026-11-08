extends Node

# ============================================================================
# G6-04 图鉴详情 · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/g6_codex_test.tscn
#
# 覆盖：
# ① 老档缺 codex 键：默认空统计、不崩溃；
# ② 装备/使用计数：武器护符按整备确认计数，消耗品按实际使用计数；
# ③ 最高熟练与铭印组合：只升不降，铭印快照跟随最高熟练；
# ④ 真实来源：meta.item_sources 格式化并去重；
# ⑤ 详情行包含路线 / 机制 / 来源 / 使用 / 熟练 / 铭印；
# ⑥ 图鉴面板：分类列表、未拥有占位、选中详情。
# 测试结束还原 meta（不污染玩家真实存档）。
# ============================================================================

const DAGGER := "res://resources/weapon_templates/dagger.tres"
const FIRE_SWORD := "res://resources/weapon_templates/fire_sword.tres"
const GUARD_CHARM := "res://resources/charms/guard_charm.tres"
const HEAL_POTION := "res://resources/consumables/heal_potion.tres"
const SYM := "res://resources/symbols/fire_slash.tres"

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

	_test_defaults(duel)
	_test_counts(duel)
	_test_mastery_record(duel)
	_test_sources(duel)
	_test_detail_lines(duel)
	_test_ui(duel)

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


func _fresh(duel: DuelController) -> void:
	duel.meta["codex"] = {}
	duel._codex = preload("res://scripts/systems/codex_system.gd").new(duel)


func _test_defaults(duel: DuelController) -> void:
	duel.meta.erase("codex")
	var c = preload("res://scripts/systems/codex_system.gd").new(duel)
	_check(duel.meta.has("codex"), "老档缺 codex 键时载入自动补默认")
	_check(c.uses_of(DAGGER) == 0, "老档默认使用次数为 0")
	_check(c.best_rank_of(DAGGER) == 0, "老档默认最高熟练为 0")
	_check(c.detail_lines(DAGGER).size() > 0, "老档也能生成详情行")


func _test_counts(duel: DuelController) -> void:
	_fresh(duel)
	duel._codex.note_equipped([DAGGER, FIRE_SWORD], [GUARD_CHARM])
	_check(duel._codex.uses_of(DAGGER) == 1, "整备确认给武器计 1 次使用")
	_check(duel._codex.uses_of(FIRE_SWORD) == 1, "第二把武器同样计数")
	_check(duel._codex.uses_of(GUARD_CHARM) == 1, "护符按装备计 1 次使用")
	duel._codex.note_used(HEAL_POTION)
	_check(duel._codex.uses_of(HEAL_POTION) == 1, "消耗品按实际使用计数")
	_check(duel.meta["codex"] is Dictionary, "codex 以字典写入 meta")


func _test_mastery_record(duel: DuelController) -> void:
	_fresh(duel)
	duel.mastery.mastery.clear()
	duel.mastery.imprints.clear()
	duel.mastery.mastery[DAGGER] = 7
	duel.mastery.imprints[DAGGER] = {"forge": 2, "tune": {SYM: 1}}
	duel._codex.record_run(duel.mastery)
	_check(duel._codex.best_rank_of(DAGGER) == 3, "7 点熟练记录为 R3")
	_check(duel._codex.best_mastery_of(DAGGER) == 7, "最高熟练记录为 7 点")
	var lines: Array = duel._codex.detail_lines(DAGGER)
	_check(_joined(lines).contains("锋铸×2"), "铭印组合记录锋铸次数")
	_check(_joined(lines).contains("调律 火斩×1"), "铭印组合记录调律符号")

	# 低于纪录的下一局不 downgrade。
	duel.mastery.mastery[DAGGER] = 3
	duel.mastery.imprints[DAGGER] = {"forge": 0, "tune": {}}
	duel._codex.record_run(duel.mastery)
	_check(duel._codex.best_rank_of(DAGGER) == 3 and duel._codex.best_mastery_of(DAGGER) == 7, "低纪录不覆盖最高熟练")
	_check(_joined(duel._codex.detail_lines(DAGGER)).contains("锋铸×2"), "低纪录不覆盖铭印快照")

	# 全新 CodexSystem 从同一 meta 载入。
	var again = preload("res://scripts/systems/codex_system.gd").new(duel)
	_check(again.best_rank_of(DAGGER) == 3, "最高熟练跨 CodexSystem 实例保留")
	duel.mastery.mastery.clear()
	duel.mastery.imprints.clear()


func _test_sources(duel: DuelController) -> void:
	_fresh(duel)
	duel.meta["item_sources"] = {}
	duel._meta_store.record_source(DAGGER, {"act": 1, "mode": "board", "node_type": "weapon", "room": "测试武器格"})
	duel._meta_store.record_source(DAGGER, {"act": 1, "mode": "linear", "room_kind": "boss", "room": "测试 BOSS"})
	var srcs: Array = duel._codex.source_lines(DAGGER)
	_check(srcs.size() == 2, "两个不同来源各留一条")
	_check(_joined(srcs).contains("棋盘") and _joined(srcs).contains("测试武器格"), "棋盘来源带节点类型与房间")
	_check(_joined(srcs).contains("BOSS 房"), "线性来源带 BOSS 房标记")


func _test_detail_lines(duel: DuelController) -> void:
	_fresh(duel)
	var w := _joined(duel._codex.detail_lines(DAGGER))
	_check(w.contains("路线："), "武器详情有路线行")
	_check(w.contains("机制：") and w.contains("攻"), "武器详情有机制行")
	_check(w.contains("来源：") and w.contains("使用："), "武器详情有来源与使用行")
	_check(w.contains("熟练：") and w.contains("铭印："), "武器详情有熟练与铭印行")
	var p := _joined(duel._codex.detail_lines(GUARD_CHARM))
	_check(p.contains("护符") and p.contains("路线："), "护符详情显示类别与路线")
	_check(p.contains("熟练 / 铭印：不适用"), "护符不伪造熟练度")


func _test_ui(duel: DuelController) -> void:
	duel.meta["owned_weapons"] = [DAGGER]
	var before_keys: int = duel._codex._stats.size()
	var entries: Array = duel._codex.list_entries("weapon")
	_check(duel._codex._stats.size() == before_keys, "浏览图鉴不创建空统计条目")
	_check(not entries.is_empty(), "图鉴武器列表非空")
	_check(bool(entries[0].get("owned", false)), "已拥有条目排在前面")
	var locked := 0
	for e in entries:
		if not bool(e.get("owned", false)):
			locked += 1
	_check(locked > 0, "未拥有装备以占位形式保留")
	_check(String(entries[0].get("name", "")) != "？？？", "已拥有条目显示真实名称")

	var anvil = duel.hud.anvil_screen
	anvil.show_screen()
	anvil._toggle_codex()
	_check(anvil._codex_panel != null and anvil._codex_panel.visible, "铁砧屏可打开图鉴面板")
	_check(anvil._codex_list.get_child_count() == entries.size() + 1, "图鉴列表含标题与全部条目")
	_check(anvil._codex_detail.get_child_count() > 1, "默认选中已拥有装备并展示详情")
	anvil._set_codex_kind("passive")
	_check(anvil._codex_kind == "passive", "图鉴可切换护符分类")
	anvil._toggle_codex()


func _joined(lines: Array) -> String:
	var out := ""
	for l in lines:
		out += String(l) + "\n"
	return out
