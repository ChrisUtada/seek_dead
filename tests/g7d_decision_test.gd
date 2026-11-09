extends Node

# ============================================================================
# G7-D · 战斗决策深度 Step 1–3 headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/g7d_decision_test.tscn
#
# 覆盖：
# ① 局势提示：重击 / 低血 / 高甲 / 熔铸间隙 / 干扰 / 残血 / 输出窗口；
# ② 对策只列当前带内与腰带内真实存在的资源，无资源时不生成虚假建议；
# ③ 重击保留「硬吃」兜底，干扰保留「照常停轮」兜底，不把不跟随建议记为错误；
# ④ 固定目标对照（--p1-target）仍走 🎯 单目标口径；
# ⑤ 遥测新增 stop_kinds / consumable_uses，记录玩家实际选择；
# ⑥ 寒铁精英 / 冰封铁瓮的机制摘要与实际回合一致（每 3 回合加压、次回合间隙、特殊三连破甲）；
# ⑦ Step 5：底部反馈只报真实结算值（护盾入账 / 实际回血 / 溢出转盾 / 收尾窗口），护盾行与状态一致。
# 测试在隔离 APPDATA 下运行，不触碰真实存档。
# ============================================================================

const FIRE_SLASH := "res://resources/symbols/fire_slash.tres"
const BLOCK := "res://resources/symbols/block.tres"
const HEAL := "res://resources/symbols/heal.tres"
const SPECIAL := "res://resources/symbols/flame_special.tres"
const PIERCE := "res://resources/symbols/bolt_shot.tres"
const HEAL_POTION := "res://resources/consumables/heal_potion.tres"
const PURIFY_POTION := "res://resources/consumables/purify_potion.tres"
const CLEANSE_POTION := "res://resources/consumables/cleanse_potion.tres"
const ACID_SOLVENT := "res://resources/consumables/acid_solvent.tres"

var _checks := 0
var _fails := 0


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	SaveSystem.reset_lobby_data()
	var duel: DuelController = await _boot()
	if duel == null:
		print("RESULT FAIL (boot)")
		get_tree().quit(2)
		return
	_setup(duel)

	_test_output(duel)
	_test_heavy(duel)
	_test_low_hp(duel)
	_test_armor(duel)
	_test_recovery(duel)
	_test_interference(duel)
	_test_finishing(duel)
	_test_feedback_consistency(duel)
	_test_fixed_target(duel)
	_test_telemetry(duel)
	_test_rhythm_resources()

	SaveSystem.reset_lobby_data()
	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _boot() -> DuelController:
	seed(9401)
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.board_config.enabled = false
	return duel


func _setup(duel: DuelController) -> void:
	var out: Array[String] = []
	for w in ["fire_sword", "ice_staff"]:
		for p in duel.WEAPON_POOL:
			if p.ends_with(w + ".tres"):
				out.append(p)
				break
	duel.selected_loadout.assign(out)
	duel.selected_consumables.clear()
	duel.selected_charms.clear()
	duel.selected_skills.clear()
	duel._confirm_loadout()
	duel.reel_system._timer.stop()
	duel.readability.apply_preset("control")


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


# 把三列转轮换成受控符号，避免依赖默认配装。
func _set_band(duel: DuelController, paths: Array) -> void:
	for r in duel.REELS:
		duel.reel_system.reel_strips[r] = []
		for p in paths:
			duel.reel_system.reel_strips[r].append([load(String(p)), "none"])


func _set_belt(duel: DuelController, paths: Array) -> void:
	duel.consumable_slots.clear()
	var i := 0
	for p in paths:
		var d = load(String(p))
		duel.consumable_slots.append({"path": String(p), "item_id": String(d.item_id),
			"charges": int(d.charges), "uid": "t%d" % i})
		i += 1


func _clear_situation(duel: DuelController) -> void:
	duel.enemy_intent = {}
	duel.enemy_armor = 0
	duel.enemy_armor_max = 0
	duel.enemy_hp = 100
	duel.enemy_hp_max = 100
	duel.player_hp = duel.player_hp_max
	duel.player_frost = 0
	duel.player_status.clear()
	duel.pending_jam_reel = -1
	duel.pending_lock_reel = -1
	duel.pending_chaos = false
	duel.pending_auto_stop = false
	duel.current_gimmick = null
	_set_belt(duel, [])


func _kinds(rd) -> Array:
	var out: Array = []
	for c in rd.counters:
		out.append(String(c.get("kind", "")))
	return out


func _has_kind(rd, kind: String) -> bool:
	return _kinds(rd).has(kind)


func _has_label(rd, text: String) -> bool:
	for c in rd.counters:
		if String(c.get("label", "")).contains(text):
			return true
	return false


func _test_output(duel: DuelController) -> void:
	_clear_situation(duel)
	_set_band(duel, [FIRE_SLASH])
	duel.readability.update_turn_target()
	var rd = duel.readability
	_check(rd.situation == "输出窗口", "输出窗口局势（实际 %s）" % rd.situation)
	_check(_has_kind(rd, "symbol_damage"), "输出窗口列出带内输出符号")
	_check(String(duel.hud.p1_target_label.text).contains("可应对"), "目标行使用「局势 + 可应对」结构")
	_check(not String(duel.hud.p1_target_label.text).begins_with("🎯"), "标准模式不再显示唯一目标")
	_check(duel.hud.p1_target_label.clip_text, "局势行开启裁切，长文本不撑宽 UI")
	_check(duel.hud.p1_target_label.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS,
		"局势行超长时用省略号收口")
	_check(not String(duel.hud.p1_target_label.text).contains("control"),
		"主栏不再拼接预设名（预设名过长）")
	_check(String(duel.hud.p1_target_label.tooltip_text).split("\n").size() == rd.counters.size() + 1,
		"tooltip 每条对策一行")
	# 长文本回归：裁切开启后，超长局势行不能把状态行撑到屏幕宽（480 逻辑分辨率）之外。
	duel.hud.p1_target_label.text = "⚖ " + "超长局势".repeat(40)
	_check(duel.hud.p1_status_row.get_combined_minimum_size().x < 480.0,
		"超长局势文本不撑宽状态行（最小宽 %.0f）" % duel.hud.p1_status_row.get_combined_minimum_size().x)
	duel.readability.update_turn_target()
	duel.hud.feedback_label.text = "超长反馈".repeat(60)
	_check(duel.hud.feedback_label.get_combined_minimum_size().x < 480.0,
		"超长反馈文本不撑宽 ReelDock（最小宽 %.0f）" % duel.hud.feedback_label.get_combined_minimum_size().x)
	duel.hud.feedback_label.text = ""


func _test_heavy(duel: DuelController) -> void:
	# 有护盾符号
	_clear_situation(duel)
	_set_band(duel, [FIRE_SLASH, BLOCK])
	duel.enemy_intent = {"data": null, "type": "heavy", "value": 46}
	duel.readability.update_turn_target()
	var rd = duel.readability
	_check(rd.situation == "重击 46", "重击局势显示真实数值（实际 %s）" % rd.situation)
	_check(_has_kind(rd, "symbol_shield"), "重击列出护盾符号")
	_check(_has_label(rd, "硬吃 46"), "重击保留硬吃兜底")
	_check(rd.target_symbol_path == BLOCK, "固定口径目标仍优先护盾")

	# 无护盾、有治疗符号、未满血
	_clear_situation(duel)
	_set_band(duel, [FIRE_SLASH, HEAL])
	duel.player_hp = 50
	duel.enemy_intent = {"data": null, "type": "heavy", "value": 30}
	duel.readability.update_turn_target()
	rd = duel.readability
	_check(not _has_kind(rd, "symbol_shield"), "无护盾时不列护盾")
	_check(_has_kind(rd, "symbol_heal"), "重击且未满血时列出治疗符号")

	# 无防御符号、有治疗药剂
	_clear_situation(duel)
	_set_band(duel, [FIRE_SLASH])
	_set_belt(duel, [HEAL_POTION])
	duel.enemy_intent = {"data": null, "type": "heavy", "value": 30}
	duel.readability.update_turn_target()
	rd = duel.readability
	_check(_has_kind(rd, "consumable_heal"), "重击列出腰带内的治疗药剂")
	_check(not _has_kind(rd, "symbol_shield"), "无护盾符号时不生成虚假护盾建议")

	# 三条以上对策：主栏只留 2 条 + 省略号，其余进 tooltip（防止长文本撑宽 UI）
	_clear_situation(duel)
	_set_band(duel, [FIRE_SLASH, BLOCK, HEAL])
	duel.player_hp = 50
	duel.enemy_intent = {"data": null, "type": "heavy", "value": 30}
	duel.readability.update_turn_target()
	var row_txt := String(duel.hud.p1_target_label.text)
	_check(row_txt.contains("…"), "对策超过 2 条时主栏用省略号收口（实际 %s）" % row_txt)
	_check(not row_txt.contains("硬吃"), "第 3 条对策只进 tooltip")

	# 无任何资源：只剩硬吃
	_clear_situation(duel)
	_set_band(duel, [FIRE_SLASH])
	duel.enemy_intent = {"data": null, "type": "heavy", "value": 52}
	duel.readability.update_turn_target()
	rd = duel.readability
	_check(rd.counters.size() == 1 and _has_label(rd, "硬吃 52"), "无资源时只保留可计算的硬吃选项")
	_check(String(duel.hud.p1_target_label.tooltip_text).contains("预计承受 52"), "硬吃 tooltip 给出预计伤害")


func _test_low_hp(duel: DuelController) -> void:
	_clear_situation(duel)
	_set_band(duel, [FIRE_SLASH, HEAL])
	duel.player_hp = 30
	duel.readability.update_turn_target()
	var rd = duel.readability
	_check(String(rd.situation).begins_with("低血"), "低血局势（实际 %s）" % rd.situation)
	_check(_has_kind(rd, "symbol_heal"), "低血列出治疗符号")
	_check(_has_label(rd, "抢攻"), "低血保留抢攻兜底")


func _test_armor(duel: DuelController) -> void:
	_clear_situation(duel)
	_set_band(duel, [FIRE_SLASH, SPECIAL, PIERCE])
	_set_belt(duel, [ACID_SOLVENT])
	duel.enemy_armor = 20
	duel.enemy_armor_max = 20
	duel.readability.update_turn_target()
	var rd = duel.readability
	_check(String(rd.situation).begins_with("高甲"), "高甲局势（实际 %s）" % rd.situation)
	_check(_has_kind(rd, "symbol_special"), "高甲列出特殊三连")
	_check(_has_kind(rd, "symbol_pierce"), "高甲列出穿透符号")
	_check(_has_kind(rd, "consumable_armor_shred"), "高甲列出破甲酸液")


func _test_recovery(duel: DuelController) -> void:
	_clear_situation(duel)
	_set_band(duel, [FIRE_SLASH, SPECIAL])
	duel.enemy_armor = 20
	duel.enemy_armor_max = 20
	var rust = load("res://scripts/battle/gimmicks/rust_armor_gimmick.gd").new()
	rust.on_room_start(duel)
	rust._interval = 3
	for i in 3:
		rust.on_turn_begin(duel)
	rust.on_turn_begin(duel)
	duel.current_gimmick = rust
	duel.readability.update_turn_target()
	var rd = duel.readability
	_check(rust.recovery_window(duel), "加压后次回合是真实恢复窗口")
	_check(rd.situation == "熔铸间隙", "间隙局势（实际 %s）" % rd.situation)
	_check(String(rd.situation_detail).contains("不新增叠甲/冻结"), "间隙说明不新增叠甲/冻结")
	_check(_has_kind(rd, "symbol_special"), "间隙列出破甲选项")


func _test_interference(duel: DuelController) -> void:
	_clear_situation(duel)
	_set_band(duel, [FIRE_SLASH])
	duel.pending_jam_reel = 0
	duel.readability.update_turn_target()
	var rd = duel.readability
	_check(String(rd.situation).begins_with("干扰"), "干扰局势（实际 %s）" % rd.situation)
	_check(not _has_kind(rd, "consumable_purify"), "无净化药剂时不生成净化建议")
	_check(_has_label(rd, "照常停轮"), "干扰保留照常停轮兜底")

	_set_belt(duel, [PURIFY_POTION])
	duel.readability.update_turn_target()
	rd = duel.readability
	_check(_has_kind(rd, "consumable_purify"), "有净化药剂时才列出净化")

	_clear_situation(duel)
	_set_band(duel, [FIRE_SLASH])
	duel.player_frost = 1
	_set_belt(duel, [CLEANSE_POTION])
	duel.readability.update_turn_target()
	rd = duel.readability
	_check(_has_kind(rd, "consumable_cleanse"), "冻结时列出清净药剂")


func _test_finishing(duel: DuelController) -> void:
	_clear_situation(duel)
	_set_band(duel, [FIRE_SLASH])
	duel.enemy_hp = 20
	duel.enemy_hp_max = 100
	duel.readability.update_turn_target()
	var rd = duel.readability
	_check(String(rd.situation).begins_with("残血"), "残血局势（实际 %s）" % rd.situation)
	_check(_has_kind(rd, "symbol_damage"), "残血列出输出符号")


func _test_feedback_consistency(duel: DuelController) -> void:
	# G7-D Step 5：底部反馈只报真实结算值；满血无回血时不显示「恢复」；护盾行与状态一致。
	var block_sym: SymbolData = load(BLOCK)
	var heal_sym: SymbolData = load(HEAL)
	var shield_counts := {BLOCK + "|none": [block_sym, "none", 2]}
	var heal_counts := {HEAL + "|none": [heal_sym, "none", 2]}

	duel.enemy_hp = 80
	duel.enemy_hp_max = 100
	duel.hud._show_turn_feedback(shield_counts, 10, false, false, 5, 0, 0)
	var txt := String(duel.hud.feedback_label.text)
	_check(txt.contains("护盾+5"), "反馈显示护盾真实入账值（实际 %s）" % txt)
	_check(not txt.contains("护盾准备"), "有结算值时不再显示无数字的「护盾准备」")

	duel.hud._show_turn_feedback(heal_counts, 0, false, false, 0, 0, 0)
	txt = String(duel.hud.feedback_label.text)
	_check(not txt.contains("恢复"), "满血且无溢出时不显示虚假「恢复」（实际 %s）" % txt)

	duel.hud._show_turn_feedback(heal_counts, 0, false, false, 0, 7, 0)
	txt = String(duel.hud.feedback_label.text)
	_check(txt.contains("恢复+7"), "反馈显示真实回血量（实际 %s）" % txt)

	duel.hud._show_turn_feedback(heal_counts, 0, false, false, 0, 0, 3)
	txt = String(duel.hud.feedback_label.text)
	_check(txt.contains("恢复→盾+3"), "治疗三连溢出显示转盾值（实际 %s）" % txt)

	duel.enemy_hp = 20
	duel.hud._show_turn_feedback(shield_counts, 10, false, false, 5, 0, 0)
	_check(String(duel.hud.feedback_label.text).contains("收尾窗口"), "残血收尾时反馈提示收尾窗口")
	duel.enemy_hp = 80
	duel.hud._show_turn_feedback(shield_counts, 10, false, false, 5, 0, 0)
	_check(not String(duel.hud.feedback_label.text).contains("收尾窗口"), "非残血时不提示收尾窗口")

	duel.player_shield = 0
	duel.invalidate_state()
	duel.hud._refresh_meta()
	_check(not duel.hud.player_shield_row.visible, "无护盾时护盾行隐藏")
	duel.player_shield = 7
	duel.invalidate_state()
	duel.hud._refresh_meta()
	_check(duel.hud.player_shield_row.visible, "有护盾时护盾行显示")
	_check(String(duel.hud.player_shield_label.text) == "盾 7", "护盾行数值与状态一致（实际 %s）" % duel.hud.player_shield_label.text)
	duel.player_shield = 0
	duel.enemy_hp = 100
	duel.enemy_hp_max = 100


func _test_fixed_target(duel: DuelController) -> void:
	_clear_situation(duel)
	_set_band(duel, [FIRE_SLASH, BLOCK])
	duel.readability._forced_target = BLOCK
	duel.readability.update_turn_target()
	var rd = duel.readability
	_check(rd.target_symbol_path == BLOCK, "固定目标对照仍钉住指定符号")
	_check(String(duel.hud.p1_target_label.text).begins_with("🎯"), "固定对照模式保留单目标行")
	_check(String(duel.hud.p1_target_label.text).contains("指定目标"), "固定对照模式显示指定目标理由")
	duel.readability._forced_target = ""
	duel.readability.update_turn_target()


func _test_telemetry(duel: DuelController) -> void:
	_clear_situation(duel)
	_set_band(duel, [FIRE_SLASH, BLOCK])
	duel.readability.on_stop(0, load(BLOCK), "player")
	_check(int(duel._telemetry.stop_kinds.get("shield", 0)) == 1, "遥测记录停中的符号类别 shield")
	duel.readability.on_stop(1, null, "forced")
	_check(int(duel._telemetry.stop_kinds.get("trash", 0)) == 0, "机制替停不计入玩家停轮类别")

	_set_belt(duel, [HEAL_POTION])
	duel.in_loadout = false
	duel.in_interroom = false
	duel._busy = false
	duel.game_state = DuelController.FlowState.PLAYING
	duel.player_hp = 50
	duel.consumable_system.use("t0")
	_check(int(duel._telemetry.consumable_uses.get("heal", 0)) == 1, "遥测记录消耗品实际使用 heal")
	var s: Dictionary = duel._telemetry.summary()
	_check(s.has("stop_kinds") and s.has("consumable_uses"), "遥测 summary 包含新字段")
	_check(String(duel._telemetry.summary_text()).contains("停轮类别"), "遥测摘要输出停轮类别")


func _test_rhythm_resources() -> void:
	for path in ["res://resources/rooms/frozen_urn.tres", "res://resources/rooms/a1_elite_brute_ice.tres"]:
		var room: RoomData = load(path)
		_check(room != null, "房间资源可加载：%s" % path.get_file())
		if room == null:
			continue
		_check(String(room.mechanic_summary).contains("特殊三连破甲"),
			"%s 机制摘要写明特殊三连破甲（实际 %s）" % [room.name, String(room.mechanic_summary).replace("\n", " / ")])
		_check(not String(room.mechanic_summary).contains("火系可破"),
			"%s 机制摘要不再误导为火系破甲" % room.name)
		_check(int(room.gimmick_params.get("interval", 0)) == 3, "%s 加压间隔 = 3 回合" % room.name)
