extends Node

# ============================================================================
# M2 武器卡 tooltip 缓存稳定性专项（2026-11-22）
#
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/m2_weapon_tooltip_cache_test.tscn
# 隔离：必须由外部覆盖 APPDATA 到临时目录后再运行，绝不触碰真实存档。
#
# 根因：player_panel_view._gear_sig 原只含装备/技能/护符/技艺，不含 mastery 熟练，
#       导致熟练 R1→R2 后 refresh_gear_icons 直接 return，tooltip 停留旧等级。
# 修复：签名按当前装备武器聚合 mastery.progress_text/imprint_text/铸式描述，
#       且与 tooltip 共用 _weapon_detail_text 生成，避免缓存与展示脱节。
# ============================================================================

const FIRE := "res://resources/weapon_templates/fire_sword.tres"

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
	_run()
	_finish()


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _fire_card():
	var row = _duel.hud.panel_view.weapons_row
	for c in row.get_children():
		if c.name.begins_with("WCard_") and c.name.ends_with("fire_sword"):
			return c
	return null


func _has_r2() -> bool:
	var c = _fire_card()
	return c != null and c.tooltip_text.find("R2") >= 0


# 1：装备/技艺完全不变，仅熟练 R1→R2，正常 HUD 刷新后 tooltip 更新
func _test_mastery_only_refresh() -> void:
	var m = _duel.mastery
	m.mastery[FIRE] = 0
	_duel.hud._refresh_meta()
	_check(not _has_r2(), "前置 R1 tooltip 不含 R2")
	var card_id_before: int = (_fire_card() as Node).get_instance_id()
	# 只改熟练到 R2（门槛 3），不动装备/技艺
	m.mastery[FIRE] = 3
	_check(m.r_level(FIRE) == 2, "前置 mastery 已达 R2（实测 R%d）" % m.r_level(FIRE))
	_duel.hud._refresh_meta()
	_check(_has_r2(), "熟练 R1→R2 后 tooltip 更新含 R2（实测：%s）" % str((_fire_card() as Control).tooltip_text))
	var card_id_after: int = (_fire_card() as Node).get_instance_id()
	_check(card_id_after != card_id_before, "熟练变化触发卡片重建（实例已更换）")


# 2：铭印描述变化也能刷新（imprint_text 属于 tooltip 动态内容）
func _test_imprint_change_refresh() -> void:
	var m = _duel.mastery
	# 先确保有 R2 进度文本（imprint 只在 progress 非空时显示）
	m.mastery[FIRE] = 3
	# 用完整合法结构（_imprint_of 口径），避免破坏 imprints 导致 SCRIPT ERROR
	var im: Dictionary = m._imprint_of(FIRE)
	im["tune"] = {"res://resources/symbols/fire_slash.tres": 1}
	_duel.hud._refresh_meta()
	var tip_with: String = (_fire_card() as Control).tooltip_text
	_check(tip_with.find("调律") >= 0,
		"铭印写入后 tooltip 含调律描述（实测：%s）" % tip_with)
	# 清空调律（保留合法的空字典结构），再刷新，应不再含该描述
	m.imprints[FIRE]["tune"] = {}
	_duel.hud._refresh_meta()
	var tip_without: String = (_fire_card() as Control).tooltip_text
	_check(tip_without.find("调律") < 0,
		"铭印移除后 tooltip 不再含调律描述（实测：%s）" % tip_without)


# 3：内容完全不变时不重建卡片（保留防闪烁优化）
func _test_no_rebuild_when_unchanged() -> void:
	_duel.hud._refresh_meta()
	var card_id_1: int = (_fire_card() as Node).get_instance_id()
	var sig_1: String = _duel.hud.panel_view._gear_sig
	_duel.hud._refresh_meta()
	_duel.hud._refresh_meta()
	var card_id_2: int = (_fire_card() as Node).get_instance_id()
	var sig_2: String = _duel.hud.panel_view._gear_sig
	_check(sig_1 == sig_2, "内容不变时签名稳定（防闪烁）")
	_check(card_id_1 == card_id_2, "内容不变时卡片实例未被重建（实测 %d vs %d）" % [card_id_1, card_id_2])


# 4：刷新不消耗全局 RNG
func _test_no_rng_consumption() -> void:
	seed(424242)
	var base: Array[int] = []
	for _i in 6:
		base.append(randi())
	seed(424242)
	_duel.hud._refresh_meta()
	_duel.hud._refresh_meta()
	var after: Array[int] = []
	for _i in 6:
		after.append(randi())
	_check(base == after, "HUD 刷新不消耗全局 RNG（%s vs %s）" % [str(base), str(after)])


func _run() -> void:
	_test_mastery_only_refresh()
	_test_imprint_change_refresh()
	_test_no_rebuild_when_unchanged()
	_test_no_rng_consumption()


func _finish() -> void:
	print("---")
	print("M2TOOLTIPCACHE RESULT: %d checks, %d fails" % [_checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)
