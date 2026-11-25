extends Node

# ============================================================================
# T3-3 C 轮第 2 步：组合面板接线验收（D1 + B3）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t3c_combo_wiring_test.tscn
# 覆盖：
#   D1 入口按钮只在间歇期出现；点击后 open(25 行)；首行「基础组合」、主组合区有 W07；
#      点 ✕ 关闭且按钮仍在；开/关前后 seed / enemy_hp / charge_points / turn_count 不变。
#   B3 evaluate 后 last_settlement_acc 非空且含 pattern_match / pattern_weapon；新局清空。
# ============================================================================

const IRON_SWORD := "res://resources/weapon_templates/iron_sword.tres"
const DAGGER := "res://resources/weapon_templates/dagger.tres"
const SY_BLADE := "res://resources/symbols/iron_slash.tres"
const SY_FLAME_A := "res://resources/symbols/burn.tres"
const SY_FLAME_B := "res://resources/symbols/fire_slash.tres"

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
	_duel.reel_system._timer.stop()
	await _run()
	print("T3CWIRE|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _run() -> void:
	var hud = _duel.hud
	var btn = hud.interroom_combo_btn
	_check(btn != null, "interroom_combo_btn 已创建")
	if btn == null:
		return

	# —— 非间歇期：入口隐藏 ——
	_check(not btn.visible, "非间歇期：interroom_combo_btn.visible == false")
	_check(hud.combo_panel != null, "combo_panel 已实例化")
	if hud.combo_panel == null:
		return
	_check(not hud.combo_panel.visible, "非间歇期：panel.visible == false")

	# —— 进间歇期（真实入口）——
	_duel._enter_interroom(false)
	await get_tree().process_frame
	_check(_duel.in_interroom, "已进入房间歇态")
	_check(btn.visible and not btn.disabled, "间歇期：interroom_combo_btn 可见且可用")
	_check(hud.interroom_shop_btn.visible and hud.interroom_next_btn.visible,
		"间歇期：商店 / 下一房按钮仍可见（入口未挤压隐藏）")
	Debug.log("T3CWIRE|TOPBAR viewport=%s combo=%s trim=%s(vis=%s) shop=%s next=%s" % [
		str(hud.get_viewport().get_visible_rect().size),
		str(btn.get_global_rect()), str(hud.interroom_trim_btn.get_global_rect()), str(hud.interroom_trim_btn.visible),
		str(hud.interroom_shop_btn.get_global_rect()), str(hud.interroom_next_btn.get_global_rect())])

	# —— 点击入口：打开面板（只读快照）——
	var seed0: int = _duel._reward_system._loot.seed_value()
	var hp0: int = int(_duel.enemy_hp)
	var charge0: int = int(_duel.charge_points)
	var turn0: int = int(_duel.turn_count)

	btn.pressed.emit()
	await get_tree().process_frame
	_check(hud.combo_panel.visible, "点击入口后 panel.visible == true")
	var rows: Array[Dictionary] = hud.combo_panel.last_rendered_rows
	_check(rows.size() == 25, "面板行数 == 25（实测 %d）" % rows.size())
	var texts: Array[String] = hud.combo_panel.rendered_texts
	_check(not texts.is_empty() and texts[0] == "基础组合",
		"面板首行是「基础组合」区段标题（实测 %s）" % (texts[0] if not texts.is_empty() else "<empty>"))
	# W07 必须落在「主组合」区段内（标题之后、下一个区段标题之前）
	var main_idx: int = texts.find("主组合")
	var has_w07 := false
	if main_idx >= 0:
		for i in range(main_idx + 1, texts.size()):
			if texts[i] == "辅助组合":
				break
			if texts[i].contains("强化燃刃"):
				has_w07 = true
				break
	_check(main_idx >= 0 and has_w07, "主组合区内存在 W07「强化燃刃」行（main_idx=%d）" % main_idx)

	_check(_duel._reward_system._loot.seed_value() == seed0, "打开面板不消耗 RNG（seed %d）" % seed0)
	_check(int(_duel.enemy_hp) == hp0, "打开面板不改 enemy_hp（%d）" % hp0)
	_check(int(_duel.charge_points) == charge0, "打开面板不改 charge_points（%d）" % charge0)
	_check(int(_duel.turn_count) == turn0, "打开面板不推进回合（turn %d）" % turn0)

	# —— 点 ✕ 关闭 ——
	var close_btn := hud.combo_panel.find_child("CloseBtn", true, false) as Button
	_check(close_btn != null, "面板存在「✕」关闭按钮")
	if close_btn != null:
		close_btn.pressed.emit()
		await get_tree().process_frame
	_check(not hud.combo_panel.visible, "点 ✕ 后 panel.visible == false")
	_check(btn.visible, "关闭后入口按钮仍可见")
	_check(_duel._reward_system._loot.seed_value() == seed0, "关闭面板不消耗 RNG（seed %d）" % seed0)
	_check(int(_duel.enemy_hp) == hp0, "关闭面板不改 enemy_hp（%d）" % hp0)
	_check(int(_duel.charge_points) == charge0, "关闭面板不改 charge_points（%d）" % charge0)
	_check(int(_duel.turn_count) == turn0, "关闭面板不推进回合（turn %d）" % turn0)

	# —— B3：上一 SPIN 的只读结算快照 ——
	await _test_last_settlement_acc()


func _test_last_settlement_acc() -> void:
	_check(_duel.last_settlement_acc.is_empty(), "开局 last_settlement_acc 为空")
	# 构造 W07 落线（同 t3b T9 口径）：iron_slash + burn + fire_slash，来源 iron_sword。
	_duel.selected_loadout.clear()
	_duel.selected_loadout.append(IRON_SWORD)
	_duel.selected_loadout.append(DAGGER)
	_duel._build_pool(_duel.selected_loadout)
	_duel._sync_pattern_source_meta()
	_duel.frozen_cols.clear()
	var syms: Array = [SY_BLADE, SY_FLAME_A, SY_FLAME_B]
	for rr in 3:
		_duel.grid[rr][0] = load(String(syms[rr]))
		_duel.grid_elem[rr][0] = "none"
		_duel.reel_system._set_grid_src(rr, 0, "iron_sword")
	_duel.enemy_hp = 300
	_duel.enemy_hp_max = 300
	_duel.enemy_armor = 10
	_duel.enemy_status.clear()
	_duel.player_hp = _duel.player_hp_max
	_duel.player_shield = 0
	_duel.charge_points = 0
	_duel.turn_count = 1
	_duel.enemy_intent.clear()
	seed(12345)
	await _duel.combat.evaluate()

	var acc: Dictionary = _duel.last_settlement_acc
	_check(not acc.is_empty(), "evaluate 后 last_settlement_acc 非空")
	_check(acc.has("pattern_match") and acc.has("pattern_weapon"),
		"快照含 pattern_match / pattern_weapon 键（实测 %s）" % str(acc.keys()))
	_check(String(acc.get("pattern_weapon", "")) == "W07",
		"快照 pattern_weapon == W07（实测 %s）" % String(acc.get("pattern_weapon", "")))
	_check(acc.has("lines") and acc.has("dmg"), "快照含 lines / dmg 结算字段")

	_duel._reset_run_state()
	_check(_duel.last_settlement_acc.is_empty(), "_reset_run_state 后 last_settlement_acc 为空")
