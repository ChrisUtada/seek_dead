extends Node

# ============================================================================
# 扫雷棋盘 Step 5 · 精英与 BOSS 节奏样板（2026-11-11）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/rhythm_windows_test.tscn
#
# 覆盖（Step 5 出口）：
# ① 样板：ACT1 精英「寒铁精英」+ ACT1 BOSS「冰封铁瓮」，同一 rust_armor 机制；
# ② 蓄势—爆发—恢复窗口按真实回合顺序出现（首轮第 2 回合爆发，之后每 3 回合，次回合恢复）；
# ③ HUD 在机制摘要前显示【蓄势/爆发/恢复】，并按窗口变色；
# ④ 标准提示在三个窗口都列出当前真实多对策，不指定唯一答案；
# ⑤ 不修改基础 HP/攻击，不读取玩家 Build / 玩家 HP 动态调值；
# ⑥ 4×4 棋盘优先放入两只节奏样板，默认 seed 可直接验收。
# 测试在隔离 APPDATA 下运行，不触碰真实存档。
# ============================================================================

const ELITE := "res://resources/rooms/a1_elite_brute_ice.tres"
const BOSS := "res://resources/rooms/frozen_urn.tres"
const FIRE_SLASH := "res://resources/symbols/fire_slash.tres"
const BLOCK := "res://resources/symbols/block.tres"
const SPECIAL := "res://resources/symbols/flame_special.tres"
const PIERCE := "res://resources/symbols/bolt_shot.tres"
const ACID_SOLVENT := "res://resources/consumables/acid_solvent.tres"
const CLEANSE_POTION := "res://resources/consumables/cleanse_potion.tres"
const ASSAULT_POTION := "res://resources/consumables/assault_potion.tres"

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

	_test_sample_rooms(duel)
	_test_elite_windows(duel)
	_test_boss_windows(duel)
	_test_hud_tag(duel)
	_test_readability(duel)
	_test_no_build_scaling(duel)
	_test_board_samples(duel)

	SaveSystem.reset_lobby_data()
	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _boot() -> DuelController:
	seed(11501)
	var scene: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.board_config.enabled = false
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
	await get_tree().process_frame
	duel.reel_system._timer.stop()
	duel.readability.apply_preset("control")
	return duel


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _start_room(duel: DuelController, path: String) -> RoomData:
	var r: RoomData = load(path)
	duel.ROOMS.clear()
	duel.ROOMS.append(r)
	duel.start_room_data(r, 0, 0, false)
	duel.enemy_intent = {}
	duel.reel_system._timer.stop()
	return r


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
			"charges": int(d.charges), "uid": "r%d" % i})
		i += 1


func _has_kind(rd, kind: String) -> bool:
	for c in rd.counters:
		if String(c.get("kind", "")) == kind:
			return true
	return false


func _has_label(rd, text: String) -> bool:
	for c in rd.counters:
		if String(c.get("label", "")).contains(text):
			return true
	return false


func _non_fallback(rd) -> int:
	var n := 0
	for c in rd.counters:
		if String(c.get("kind", "")) != "fallback":
			n += 1
	return n


# ---------------------------------------------------------------------------
# ① 样板房间：类型 / 参数 / 摘要
# ---------------------------------------------------------------------------

func _test_sample_rooms(duel: DuelController) -> void:
	var elite: RoomData = load(ELITE)
	var boss: RoomData = load(BOSS)
	_check(elite != null and String(elite.kind) == "elite" and int(elite.act) == 1,
		"寒铁精英是 ACT1 精英")
	_check(boss != null and String(boss.kind) == "boss" and int(boss.act) == 1,
		"冰封铁瓮是 ACT1 BOSS")
	if elite == null or boss == null:
		return
	_check(int(elite.atk) == 20, "寒铁精英基础攻击保持 20（未改）")
	_check(int(elite.hp) == 0 and elite.archetype != null and int(elite.archetype.hp_base) == 200,
		"寒铁精英基础 HP 保持行为族 200（未改）")
	_check(int(boss.hp) == 240 and int(boss.atk) == 17, "冰封铁瓮基础 HP/攻击保持 240/17（未改）")
	for room in [elite, boss]:
		_check(room.gimmick_script != null
			and room.gimmick_script.resource_path.get_file() == "rust_armor_gimmick.gd",
			"%s 使用熔铸护甲机制" % room.name)
		_check(int(room.gimmick_params.get("interval", 0)) == 3, "%s 加压间隔 3 回合" % room.name)
		_check(int(room.gimmick_params.get("first_pressure_turn", 0)) == 2,
			"%s 首轮第 2 回合爆发（保证 2 回合击杀也看到蓄势→爆发）" % room.name)
		var summary := String(room.mechanic_summary)
		if room == elite:
			_check(summary.contains("破甲") and summary.contains("冻结"),
				"%s 摘要写明叠甲/冻结与破甲解除（实际 %s）" % [room.name, summary.replace("\n", " / ")])
		else:
			_check(summary.contains("蓄势") and summary.contains("爆发") and summary.contains("恢复"),
				"%s 摘要写明蓄势—爆发—恢复（实际 %s）" % [room.name, summary.replace("\n", " / ")])
			_check(summary.contains("特殊三连破甲"), "%s 摘要保留破甲对策" % room.name)
	_check(int(elite.gimmick_params.get("max_stacks", 0)) == 2, "寒铁精英封顶 2 层")
	_check(int(boss.gimmick_params.get("max_stacks", 0)) == 3, "冰封铁瓮封顶 3 层")


# ---------------------------------------------------------------------------
# ② 窗口顺序：蓄势 → 爆发 → 恢复
# ---------------------------------------------------------------------------

func _test_elite_windows(duel: DuelController) -> void:
	var room := _start_room(duel, ELITE)
	var g = duel.current_gimmick
	_check(g != null, "寒铁精英实例化机制")
	if g == null:
		return
	var base_armor: int = int(duel.enemy_armor)
	var seq: Array = [g.rhythm_window(duel)]
	for i in 5:
		g.on_turn_begin(duel)
		seq.append(g.rhythm_window(duel))
	_check(seq == ["蓄势", "爆发", "恢复", "蓄势", "爆发", "恢复"],
		"寒铁精英窗口顺序（实际 %s）" % str(seq))
	_check(seq[1] == "爆发", "寒铁精英首轮在第 2 回合爆发（不是第 3 回合）")
	_check(int(duel.enemy_armor) == base_armor + 8, "两次爆发共叠 8 护甲（%d → %d）" % [base_armor, int(duel.enemy_armor)])
	_check(g.rhythm_window(duel) == "恢复" and g.recovery_window(duel), "恢复窗口与 recovery_window 一致")
	g.on_turn_begin(duel)
	_check(g.rhythm_window(duel) == "", "叠满 2 层后不再声明节奏窗口")
	_check(not g.recovery_window(duel), "封顶后不再有恢复窗口")
	_check(String(room.mechanic_summary) != "", "寒铁精英摘要供确认层直接读取")


func _test_boss_windows(duel: DuelController) -> void:
	_start_room(duel, BOSS)
	var g = duel.current_gimmick
	_check(g != null, "冰封铁瓮实例化机制")
	if g == null:
		return
	var base_armor: int = int(duel.enemy_armor)
	var seq: Array = [g.rhythm_window(duel)]
	for i in 8:
		g.on_turn_begin(duel)
		seq.append(g.rhythm_window(duel))
	_check(seq == ["蓄势", "爆发", "恢复", "蓄势", "爆发", "恢复", "蓄势", "爆发", "恢复"],
		"冰封铁瓮窗口顺序（实际 %s）" % str(seq))
	_check(int(duel.enemy_armor) == base_armor + 24, "三次爆发共叠 24 护甲（%d → %d）" % [base_armor, int(duel.enemy_armor)])
	g.on_turn_begin(duel)
	_check(g.rhythm_window(duel) == "", "叠满 3 层后不再声明节奏窗口")


# ---------------------------------------------------------------------------
# ③ HUD 节奏标签
# ---------------------------------------------------------------------------

func _test_hud_tag(duel: DuelController) -> void:
	_start_room(duel, BOSS)
	var g = duel.current_gimmick
	var lbl: Label = duel.hud.enemy_mechanic_label
	_check(lbl.visible and String(lbl.text).begins_with("【蓄势】"),
		"蓄势回合 HUD 显示【蓄势】（实际 %s）" % String(lbl.text).split("\n")[0])
	_check(String(lbl.text).contains(String((load(BOSS) as RoomData).mechanic_summary)),
		"HUD 仍保留完整机制摘要")
	_check(lbl.get_theme_color("font_color") == Palette.ACCENT_GOLD, "蓄势标签用交互金")
	g.on_turn_begin(duel)
	duel.invalidate_state()
	duel.hud._refresh_meta()
	_check(String(lbl.text).begins_with("【爆发】"), "爆发回合 HUD 显示【爆发】（实际 %s）" % String(lbl.text).split("\n")[0])
	_check(lbl.get_theme_color("font_color") == Palette.POP_DAMAGE, "爆发标签用危险红")
	g.on_turn_begin(duel)
	duel.invalidate_state()
	duel.hud._refresh_meta()
	_check(String(lbl.text).begins_with("【恢复】"), "恢复回合 HUD 显示【恢复】（实际 %s）" % String(lbl.text).split("\n")[0])
	_check(lbl.get_theme_color("font_color") == Palette.POP_HEAL, "恢复标签用治疗绿")


# ---------------------------------------------------------------------------
# ④ 标准提示：三个窗口都有真实多对策
# ---------------------------------------------------------------------------

func _test_readability(duel: DuelController) -> void:
	_start_room(duel, ELITE)
	var g = duel.current_gimmick
	_set_band(duel, [FIRE_SLASH, BLOCK, SPECIAL, PIERCE])
	_set_belt(duel, [ACID_SOLVENT, CLEANSE_POTION, ASSAULT_POTION])
	duel.player_hp = duel.player_hp_max
	duel.enemy_intent = {}

	# 蓄势回合（进房即第 1 回合）
	duel.readability.update_turn_target()
	var rd = duel.readability
	_check(String(rd.situation).begins_with("蓄势"), "蓄势局势（实际 %s）" % rd.situation)
	_check(rd.situation_detail.contains("爆发"), "蓄势说明预告下一次爆发")
	_check(rd.counters.size() >= 2 and _non_fallback(rd) >= 2, "蓄势给出至少 2 条真实对策（%d）" % rd.counters.size())
	_check(_has_kind(rd, "symbol_damage"), "蓄势列出保持输出")
	_check(_has_label(rd, "保留资源"), "蓄势保留「保留资源」兜底")
	_check(not String(duel.hud.p1_target_label.text).begins_with("🎯"), "标准提示不显示唯一目标")

	# 爆发回合（第 2 回合）
	g.on_turn_begin(duel)
	_check(g.rhythm_window(duel) == "爆发", "第 2 回合进入爆发")
	duel.enemy_intent = {}
	duel.readability.update_turn_target()
	rd = duel.readability
	_check(String(rd.situation).begins_with("爆发"), "爆发局势（实际 %s）" % rd.situation)
	_check(_has_kind(rd, "symbol_special"), "爆发列出特殊三连破甲")
	_check(_has_kind(rd, "symbol_pierce"), "爆发列出穿透直击")
	_check(_has_kind(rd, "consumable_armor_shred"), "爆发列出破甲酸液")
	_check(_has_kind(rd, "consumable_cleanse"), "爆发且冻结时列出清净药剂")
	_check(_has_kind(rd, "symbol_damage"), "爆发仍可承压输出")
	_check(_has_label(rd, "直接承伤"), "爆发保留直接承伤兜底")
	_check(rd.counters.size() >= 3 and _non_fallback(rd) >= 3, "爆发给出多条真实对策（%d）" % rd.counters.size())

	# 恢复回合（第 3 回合）
	g.on_turn_begin(duel)
	duel.enemy_intent = {}
	duel.readability.update_turn_target()
	rd = duel.readability
	_check(String(rd.situation) == "熔铸间隙", "恢复局势仍为熔铸间隙（实际 %s）" % rd.situation)
	_check(_has_kind(rd, "symbol_special") and _has_kind(rd, "symbol_pierce"), "恢复列出两种破甲路线")
	_check(_has_kind(rd, "consumable_armor_shred") and _has_kind(rd, "symbol_damage"), "恢复也可直接输出")
	_check(rd.counters.size() >= 3 and _non_fallback(rd) >= 2, "恢复给出至少 3 条对策（%d）" % rd.counters.size())

	_set_belt(duel, [])


# ---------------------------------------------------------------------------
# ⑤ 不改基础数值 / 不读玩家 Build
# ---------------------------------------------------------------------------

func _test_no_build_scaling(duel: DuelController) -> void:
	_start_room(duel, ELITE)
	var g = duel.current_gimmick
	var atk: int = int(duel.enemy_atk)
	var hp_max: int = int(duel.enemy_hp_max)
	for i in 10:
		g.on_turn_begin(duel)
	_check(int(duel.enemy_atk) == atk, "10 回合内敌人攻击不变（%d）" % atk)
	_check(int(duel.enemy_hp_max) == hp_max, "10 回合内敌人最大 HP 不变（%d）" % hp_max)
	_check(int(duel.enemy_hp) == hp_max, "熔铸机制不回血、不扣自身 HP")
	var src := FileAccess.get_file_as_string("res://scripts/battle/gimmicks/rust_armor_gimmick.gd")
	_check(src != "", "可读取熔铸机制源码用于静态检查")
	_check(not src.contains("selected_loadout") and not src.contains("player_hp"),
		"熔铸机制不读取玩家 Build / 玩家 HP 动态调值")
	_check(not src.contains("growth") and not src.contains("player_hp_max"),
		"熔铸机制不读取成长或玩家上限调值")
	var elite: RoomData = load(ELITE)
	var keys: Array = elite.gimmick_params.keys()
	keys.sort()
	_check(keys == ["first_pressure_turn", "freeze_clears_on_break", "interval", "max_stacks", "per_stack", "two_cols_chance"],
		"样板参数只有节奏/护甲/破甲解冻六项（实际 %s）" % str(keys))


# ---------------------------------------------------------------------------
# ⑥ 棋盘优先放入节奏样板
# ---------------------------------------------------------------------------

func _test_board_samples(duel: DuelController) -> void:
	var grid = load("res://scripts/board/board_grid.gd").new(duel)
	var data: Dictionary = grid.generate(1, 20261110)
	var by_id: Dictionary = data["by_id"]
	var elite_room: RoomData = by_id[String(data["elite_id"])].get("room")
	var boss_room: RoomData = by_id[String(data["boss_id"])].get("room")
	_check(elite_room != null and String(elite_room.name) == "寒铁精英",
		"默认 4×4 棋盘精英位放入寒铁精英")
	_check(boss_room != null and String(boss_room.name) == "冰封铁瓮",
		"默认 4×4 棋盘 BOSS 位放入冰封铁瓮")
	_check(boss_room != null and String(boss_room.mechanic_summary).contains("爆发"),
		"棋盘确认层可直接读到 BOSS 的节奏摘要")
	var errs: Array = grid.validate(data)
	_check(errs.is_empty(), "放入节奏样板后棋盘校验通过（%s）" % str(errs))
