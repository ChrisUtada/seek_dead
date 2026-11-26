extends Node

# ============================================================================
# T3-3 C 轮前置：ComboCatalog 只读数据契约验收
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t3c_combo_catalog_test.tscn
# ============================================================================

const IRON_SWORD := "res://resources/weapon_templates/iron_sword.tres"

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
	await _run()
	print("T3CCAT|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _rows(loadout: Array, acc: Dictionary) -> Array[Dictionary]:
	return ComboCatalog.build_rows(_duel._pattern_system, loadout, _duel._pattern_tag_of, acc)


func _row(rows: Array[Dictionary], id: String) -> Dictionary:
	for r in rows:
		if String(r["id"]) == id:
			return r
	return {}


func _run() -> void:
	var loadout: Array = [IRON_SWORD, "res://resources/weapon_templates/dagger.tres"]
	var rows: Array[Dictionary] = _rows(loadout, {})

	# 行数 25 = 22 PatternData（含本轮 W07）+ 3 合成 G 行。
	# 工单写的 24/21/11 是 W07 入库前的数字；本轮按实际资源数校验（main 由 6→7）。
	_check(rows.size() == 25, "行数 == 25（22 PatternData + 3 G，实测 %d）" % rows.size())

	# 分组计数
	var counts := {"main": 0, "aux": 0, "signature": 0, "base": 0, "universal": 0}
	for r in rows:
		var g: String = String(r["group"])
		counts[g] = int(counts.get(g, 0)) + 1
	_check(int(counts["main"]) == 7, "main 7（W01–W07，实测 %d）" % int(counts["main"]))
	_check(int(counts["aux"]) == 3, "aux 3（T01–T03，实测 %d）" % int(counts["aux"]))
	_check(int(counts["signature"]) == 12, "signature 12（11 sig_* + s02，实测 %d）" % int(counts["signature"]))
	_check(int(counts["base"]) == 3, "base 3（G01–G03，实测 %d）" % int(counts["base"]))
	Debug.log("T3CCAT|GROUPS " + str(counts))

	# W07 unlocked：含 iron_sword true、不含 false
	_check(bool(_row(rows, "W07").get("unlocked", false)), "W07 unlocked（含 iron_sword）=true")
	var rows_no: Array[Dictionary] = _rows(["res://resources/weapon_templates/dagger.tres",
		"res://resources/weapon_templates/short_sword.tres"], {})
	_check(not bool(_row(rows_no, "W07").get("unlocked", false)), "W07 unlocked（不含 iron_sword）=false")

	# matched_now：acc.pattern_weapon = W07
	var acc: Dictionary = {"pattern_weapon": "W07", "lines": ["🗂 武器牌谱 W07 强化燃刃", "   🔥 强化燃刃：燃烧 +1 层"]}
	var rows_m: Array[Dictionary] = _rows(loadout, acc)
	_check(bool(_row(rows_m, "W07").get("matched_now", false)), "acc 命中时 W07 matched_now=true")
	var other_main := 0
	for r in rows_m:
		if String(r["group"]) == "main" and String(r["id"]) != "W07" and bool(r["matched_now"]):
			other_main += 1
	_check(other_main == 0, "其余 main 行 matched_now=false（实测 %d 条误命中）" % other_main)
	_check(String(_row(rows_m, "W07").get("condition_text", "")) != "", "W07 condition_text 非空")
	_check(String(_row(rows_m, "W07").get("condition_text", "")) == "blade×1 + flame×2",
		"W07 condition_text 折叠为 blade×1 + flame×2（实测 %s）" % String(_row(rows_m, "W07").get("condition_text", "")))
	_check(String(_row(rows_m, "W07").get("contribution_text", "")).contains("强化燃刃"),
		"W07 contribution_text 含名称（实测 %s）" % String(_row(rows_m, "W07").get("contribution_text", "")))

	# B2 反向：空 acc → 所有 matched_now=false
	var all_false := true
	for r in rows:
		if bool(r["matched_now"]):
			all_false = false
			break
	_check(all_false, "B2 空 acc 时所有 matched_now=false")

	# G 系命中接线：acc.pattern_match.patterns（同源刻）
	var acc_g: Dictionary = {"pattern_match": {"patterns": [{"id": "G01", "name": "同源刻"}]}}
	var rows_g: Array[Dictionary] = _rows(loadout, acc_g)
	_check(bool(_row(rows_g, "G01").get("matched_now", false)), "G01 命中（来自 acc.pattern_match）")
	_check(not bool(_row(rows_g, "G02").get("matched_now", false)), "G02 未命中")
	_check(not bool(_row(rows_g, "G03").get("matched_now", false)), "G03 未命中")
	var resource_hits := 0
	for r in rows_g:
		if String(r["group"]) != "base" and bool(r["matched_now"]):
			resource_hits += 1
	_check(resource_hits == 0, "G 命中时资源行全部 false（实测 %d）" % resource_hits)

	# G01+G02 可并存（同源刻与同族刻互不排斥）
	var acc_gg: Dictionary = {"pattern_match": {"patterns": [
		{"id": "G01", "name": "同源刻"}, {"id": "G02", "name": "同族刻"}]}}
	var rows_gg: Array[Dictionary] = _rows(loadout, acc_gg)
	_check(bool(_row(rows_gg, "G01").get("matched_now", false)) and bool(_row(rows_gg, "G02").get("matched_now", false)),
		"G01+G02 同时命中（同源+同族并存）")

	# 只读证明：seed / enemy_hp / enemy_armor 不变
	var seed0: int = _duel._reward_system._loot.seed_value()
	var hp0: int = _duel.enemy_hp
	var armor0: int = _duel.enemy_armor
	var _ignored: Array[Dictionary] = _rows(loadout, acc)
	_check(_duel._reward_system._loot.seed_value() == seed0, "只读：_loot.seed_value() 不变（%d）" % seed0)
	_check(_duel.enemy_hp == hp0, "只读：enemy_hp 不变（%d）" % hp0)
	_check(_duel.enemy_armor == armor0, "只读：enemy_armor 不变（%d）" % armor0)
