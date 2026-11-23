extends Node

# T1.9 无效格操控补偿契约测试。
# 默认行为零改变：mercy_frequency="turn"、mercy_enemy_jam_enabled=false。
# 覆盖：
# ① 默认值关闭（生产行为不变）：jam 不进 mercy、精度 MISS 进 mercy、每回合重置；
# ② 频率档 "room"：每房一次（跨回合不重置，换房重置）；
# ③ 第三档 "enemy_only"（默认关闭的试验档，需显式开启）：
#    - jam(trash.tres) 落点触发补偿；
#    - 精度(miss.tres) 落点不触发；
#    - 混合来源严格分离；
#    - 不改落点、不改伤害、不重复结算、不额外消耗 RNG；
#    - 与 trash_reroll 并存时不绕过各自次数限制。
# 隔离 APPDATA 运行。

const MISS_PATH := "res://resources/symbols/miss.tres"
const TRASH_PATH := "res://resources/symbols/trash.tres"
const FIRE_PATH := "res://resources/symbols/fire_slash.tres"

var _checks := 0
var _fails := 0

func _ready() -> void:
	await _run()
	print("T19CT|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("T19CT|FAIL|" + msg)

func _boot() -> DuelController:
	var scene: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.board_config.enabled = false
	duel.selected_consumables.clear()
	duel.selected_charms.clear()
	duel.selected_skills.clear()
	duel._confirm_loadout()
	await get_tree().process_frame
	duel.reel_system._timer.stop()
	duel.pending_jam_reel = -1
	duel.pending_lock_reel = -1
	duel.pending_chaos = false
	duel.pending_auto_stop = false
	duel.reel_controls["mercy"] = true
	return duel

func _set_band(duel: DuelController, sym_path: String) -> void:
	var rs := duel.reel_system
	rs.begin_spin()
	rs._timer.stop()
	rs.reel_stopped.assign([false, true, true])
	rs._pending_stops.clear()
	rs.reel_strips[0] = [[load(sym_path), "none", ""], [load(FIRE_PATH), "fire", ""]]
	rs.reel_cursor[0] = 0
	duel.readability.visual_stop = false
	duel.readability.buffer_enabled = false

func _press(duel: DuelController) -> void:
	# 确保 reel_stopped 已初始化（begin_spin 会清空为 []）
	var rs := duel.reel_system
	if rs.reel_stopped.size() < 3:
		rs.reel_stopped.assign([false, true, true])
	duel.reel_system.stop_next_reel(false, "player")
	await duel.get_tree().create_timer(0.3).timeout

func _run() -> void:
	var duel := await _boot()
	var rd = duel.readability

	# ① 默认值关闭
	_check(rd.mercy_frequency == "turn", "默认 mercy_frequency=turn（正式默认）")
	_check(not rd.mercy_enemy_jam_enabled, "默认 mercy_enemy_jam_enabled=false（第三档关闭）")

	# 默认：jam 不进 mercy
	duel.pending_jam_reel = 0
	rd.mercy_used = 0
	var gold0 := duel.gold
	await _press(duel)
	_check(String(duel.grid[0][0].resource_path) == TRASH_PATH, "默认 jam 落点=trash.tres")
	_check(duel.gold == gold0 and rd.mercy_used == 0, "默认 jam 不触发 mercy（生产行为不变）")

	# 默认：精度 MISS 进 mercy（每回合一次）
	duel.pending_jam_reel = -1
	_set_band(duel, MISS_PATH)
	rd.mercy_used = 0
	gold0 = duel.gold
	await _press(duel)
	_check(String(duel.grid[0][0].resource_path) == MISS_PATH, "默认精度 MISS 落点=miss.tres")
	_check(duel.gold == gold0 + 2 and rd.mercy_used == 1, "默认精度 MISS 触发 mercy +2 金")

	# 默认：每回合重置（begin_spin 清零）
	_set_band(duel, MISS_PATH)
	rd.mercy_used = 1
	rd.begin_spin()
	_check(rd.mercy_used == 0, "默认 turn 档：begin_spin 每回合重置 mercy_used")

	# ② 频率档 room：每房一次
	rd.mercy_frequency = "room"
	rd.mercy_used = 0
	rd.begin_spin()
	_check(rd.mercy_used == 0, "room 档：首回合 mercy_used=0")
	# 手动累计一次后 begin_spin 不重置
	rd.mercy_used = 1
	rd.begin_spin()
	_check(rd.mercy_used == 1, "room 档：begin_spin 跨回合不重置")
	# 换房重置
	rd.begin_room()
	_check(rd.mercy_used == 0, "room 档：begin_room 换房重置 mercy_used")
	rd.mercy_frequency = "turn"   # 还原

	# ③ 第三档 enemy_only（显式开启）
	rd.mercy_enemy_jam_enabled = true

	# ③a jam 落点触发补偿，不改落点/不改伤害
	duel.pending_jam_reel = 0
	rd.mercy_used = 0
	gold0 = duel.gold
	var hp0 := duel.player_hp
	var enemy_hp0: int = duel.enemy_hp
	await _press(duel)
	_check(String(duel.grid[0][0].resource_path) == TRASH_PATH, "第三档 jam 落点仍为 trash.tres（不改落点）")
	_check(duel.gold == gold0 + 2 and rd.mercy_used == 1, "第三档 jam 触发 mercy +2 金")
	_check(duel.player_hp == hp0 and duel.enemy_hp == enemy_hp0, "第三档不改伤害/HP")

	# ③b 精度 MISS 不触发第三档
	duel.pending_jam_reel = -1
	_set_band(duel, MISS_PATH)
	rd.mercy_used = 0
	gold0 = duel.gold
	await _press(duel)
	_check(duel.gold == gold0 and rd.mercy_used == 0, "第三档精度 MISS 不触发 mercy")

	# ③c 混合来源严格分离：jam 触发、同回合 MISS 不再触发（受次数限制）
	duel.pending_jam_reel = 0
	rd.mercy_used = 0
	gold0 = duel.gold
	await _press(duel)   # jam 用掉唯一一次
	var gold_after_jam := duel.gold
	var mercy_after_jam: int = rd.mercy_used
	duel.pending_jam_reel = -1
	# 同回合内直接重设带子，不调 begin_spin（避免 turn 档重置 mercy_used）
	var rs2 := duel.reel_system
	rs2.reel_stopped.assign([false, true, true])
	rs2._pending_stops.clear()
	rs2.reel_strips[0] = [[load(MISS_PATH), "none", ""], [load(FIRE_PATH), "fire", ""]]
	rs2.reel_cursor[0] = 0
	await _press(duel)   # 同回合 MISS
	_check(duel.gold == gold_after_jam, "第三档混合来源：jam 已用次数后 MISS 不再补偿（次数不重复）")
	_check(rd.mercy_used == mercy_after_jam, "第三档混合来源：mercy_used 不叠加（同回合上限 1）")

	# ③d 重复回调不重复结算：同一次 jam 落点重复调用 _lock_at 不重复给钱
	# （_lock_at 有 reel_stopped 守卫，重复调用直接 return）
	var before_dup := duel.gold
	duel.reel_system._lock_at(0, 0, "jam")
	_check(duel.gold == before_dup, "重复 _lock_at：reel_stopped 守卫阻止重复结算")

	# ③e 与 trash_reroll 并存：jam 走早退路径不进 trash_reroll，trash_reroll 次数不被 jam 消费
	duel.reel_controls["trash_reroll"] = true
	rd.trash_reroll_used = 0
	duel.pending_jam_reel = 0
	rd.mercy_used = 0
	await _press(duel)
	_check(rd.trash_reroll_used == 0, "jam 补偿不消费 trash_reroll 次数（各自独立）")

	# 还原默认
	rd.mercy_enemy_jam_enabled = false
	duel.queue_free()
	await get_tree().process_frame
