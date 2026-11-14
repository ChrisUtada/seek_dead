extends Node

# ============================================================================
# 地图巡逻诱导 · Step 4 · 破甲陷阱与战斗联动定向回归（2026-11-14）
# 规格：docs/地图巡逻诱导_第一版预算与分步执行计划_2026-11-14.md
#       §3.4 陷阱规则、§6 Step 4 任务 1–4 与出口
#
# 覆盖四条出口：
#   1) 陷阱触发一次，效果只结算一次；
#   2) 战斗护甲变化与地图预告一致；
#   3) 不秒杀、不重复触发、不重复发奖；
#   4) 玩家无陷阱路线也能正常击败怪物。
# 以及 §3.4 的公开位置 / 玩家踩陷阱不受无预告伤害。
#
# 只使用开发／AI 测试入口（MapRuntime with_patrols），不接产品默认入口，
# 不改 board_system / board_screen / board_config，不退役任何旧测试。
# ============================================================================

const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const MAP_GRID := preload("res://scripts/board/map_grid.gd")
const MAP_PATROL := preload("res://scripts/board/map_patrol.gd")
const MAP_TRAP := preload("res://scripts/board/map_trap.gd")
const RUNTIME := preload("res://scripts/board/map_runtime.gd")

const SEED := 20261110

const START := 57
const BOSS := 68

# 冻结坐标：三个陷阱都在巡逻环上（Step 4 口径）。
const TRAP_A := 45         # p0 环第 3 格（A 区）
const TRAP_C1 := 39        # p1 环第 2 格（C 区）
const TRAP_C2 := 110       # p2 环第 3 格（C 区）
const P0_SPAWN := 30
const P0_AFTER_TRAP := 44  # p0 走到陷阱后的下一格
const NEAR_P0 := 29        # 与 p0 起点相邻
const NEAR_TRAP_A := 59    # 与陷阱 45 相邻（原 B 区咽喉位，现在只是通路）

var _checks := 0
var _fails := 0
var _duel: DuelController = null


func _ready() -> void:
	await _run()


func _run() -> void:
	await get_tree().process_frame
	var scene_res: PackedScene = load(DUEL_SCENE)
	if scene_res == null:
		print("MAPTRAP|RESULT FAIL (duel scene missing)")
		get_tree().quit(2)
		return
	_duel = scene_res.instantiate() as DuelController
	add_child(_duel)
	await _frames(3)

	var cfg = _duel.board_config
	var dev_was: bool = bool(cfg.map_dev_override)
	cfg.map_dev_override = true

	print("=== A 陷阱数据与公开性 ===")
	_test_data()
	print("=== B 怪物踩陷阱记录一次 ===")
	_test_trigger_once()
	print("=== C 同一怪物不重复武装 ===")
	_test_no_rearm()
	print("=== D 接触应用破甲且只结算一次 ===")
	_test_apply_once()
	print("=== E 预告与实战护甲一致 ===")
	_test_preview_matches()
	print("=== F 不秒杀、不跳过战斗 ===")
	_test_no_instakill()
	print("=== G 玩家踩陷阱不受无预告伤害 ===")
	_test_player_on_trap()
	print("=== H 无陷阱路线也能正常战斗 ===")
	_test_without_trap()
	print("=== I 存档恢复含陷阱状态 ===")
	_test_save_restore()

	cfg.map_dev_override = dev_was
	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	print("MAPTRAP|RESULT %s (checks=%d fails=%d)" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _rt():
	return RUNTIME.create(_duel, 1, SEED, 1, true)


func _patrol(rt, pid: String) -> Dictionary:
	for p in rt.patrols:
		if String(p["id"]) == pid:
			return p
	return {}


# ---------------------------------------------------------------------------
# A 陷阱数据与公开性
# ---------------------------------------------------------------------------

func _test_data() -> void:
	var rt = _rt()
	var traps: Array = MAP_TRAP.traps(rt.grid)
	_check(traps.size() == 3, "陷阱 3 个（%d）" % traps.size())
	var ids: Array = []
	var in_a := 0
	var on_ring := 0
	for t in traps:
		var cid: int = int(t["cell_id"])
		ids.append(cid)
		_check(String(t["type"]) == "armor_break", "陷阱 %d 类型是 armor_break" % cid)
		_check(rt.is_walkable(cid), "陷阱 %d 在可行走格" % cid)
		if String(t["region"]) == "A":
			in_a += 1
		var ring := false
		for cfg in MAP_PATROL.PATROLS:
			if (cfg["path"] as Array).has(cid):
				ring = true
		if ring:
			on_ring += 1
		# 陷阱被占也不切断 起点→BOSS（拦路陷阱会违反「不永久堵死」）。
		var path: Array = MAP_GRID.reachable(rt.grid, START, BOSS, [], [cid])
		_check(not path.is_empty(), "陷阱 %d 被占时 BOSS 仍可达" % cid)
	_check(ids.has(TRAP_A) and ids.has(TRAP_C1) and ids.has(TRAP_C2),
		"陷阱位置为 45/39/110（%s）" % str(ids))
	_check(in_a >= 1, "入口区 A 至少 1 个陷阱（%d）" % in_a)
	_check(on_ring == traps.size(), "全部陷阱都在巡逻环上（%d/%d）" % [on_ring, traps.size()])

	# 位置公开：view 直接给出陷阱与类型，不需要先踩。
	var info: Dictionary = rt.view(TRAP_A)
	_check(bool(info["trap"]), "view 显示该格是陷阱（公开）")
	_check(String(info["trap_type"]) == "armor_break", "view 给出陷阱类型")
	var plain: Dictionary = rt.view(START)
	_check(not bool(plain["trap"]), "非陷阱格标记为 false")
	_check(not MAP_TRAP.is_trap_cell(rt.grid, START), "起点不是陷阱格")

	_check(MAP_TRAP.trap_at(rt.grid, TRAP_A).size() > 0, "trap_at 可取到陷阱记录")
	_check(MAP_TRAP.trap_at(rt.grid, START).is_empty(), "非陷阱格 trap_at 为空")

	# 三只巡逻怪都必须有护甲，否则破甲是 0→0 的空机制。
	for p in rt.patrols:
		var armor: int = MAP_TRAP.armor_of(p.get("room"))
		_check(armor > 0, "%s 绑定的怪有护甲（%d）" % [String(p["id"]), armor])
	var distinct: Dictionary = {}
	for p in rt.patrols:
		distinct[String(p.get("room_path", ""))] = true
	_check(distinct.size() == 3, "三只巡逻绑定不同房间（%d）" % distinct.size())


# ---------------------------------------------------------------------------
# B 怪物踩陷阱记录一次
# ---------------------------------------------------------------------------

func _test_trigger_once() -> void:
	var rt = _rt()
	_check(rt.trap_triggers_count() == 0, "初始没有陷阱触发")
	_check(rt.trap_state.is_empty(), "初始没有陷阱状态")

	# 第 1 回合：p1 走到 39（陷阱），p0 → 31，p2 → 109。
	rt.wait_turn()
	_check(rt.trap_triggers_count() == 1, "第 1 回合记录 1 次触发（%d）" % rt.trap_triggers_count())
	_check(String(rt.trap_triggers[0]["patrol"]) == "p1", "触发者是 p1")
	_check(int(rt.trap_triggers[0]["cell"]) == TRAP_C1, "触发格是 39")
	_check(int(rt.trap_triggers[0]["turn"]) == 1, "触发回合是 1")
	_check(bool(_patrol(rt, "p1")["trap_armed"]), "p1 已被武装")
	_check(rt.trap_state.has(TRAP_C1), "陷阱状态记录到 39")
	_check(String(rt.trap_state[TRAP_C1]["patrol"]) == "p1", "39 记录的怪物是 p1")
	_check(not bool(rt.trap_state[TRAP_C1]["consumed"]), "尚未被战斗结算")

	# 第 2 回合：p0 → 45，p2 → 110，两者都踩陷阱。
	rt.wait_turn()
	_check(rt.trap_triggers_count() == 3, "第 2 回合累计 3 次触发（%d）" % rt.trap_triggers_count())
	_check(bool(_patrol(rt, "p0")["trap_armed"]), "p0 已被武装")
	_check(int(_patrol(rt, "p0")["trap_cell"]) == TRAP_A, "p0 的陷阱是 45")
	_check(bool(_patrol(rt, "p2")["trap_armed"]), "p2 已被武装")
	_check(int(_patrol(rt, "p2")["trap_cell"]) == TRAP_C2, "p2 的陷阱是 110")

	# 记录结构完整。
	var rec: Dictionary = rt.trap_triggers[2]
	_check(rec.has("turn") and rec.has("patrol") and rec.has("cell"), "触发记录含回合/怪物/格")


# ---------------------------------------------------------------------------
# C 同一怪物不重复武装
# ---------------------------------------------------------------------------

func _test_no_rearm() -> void:
	var rt = _rt()
	for i in range(2):
		rt.wait_turn()
	var base: int = rt.trap_triggers_count()
	_check(base == 3, "两回合后触发数 3")
	# 再走两整圈（p0 环长 4），三只都会再次踩到同一陷阱。
	for i in range(8):
		rt.wait_turn()
	_check(rt.trap_triggers_count() == base,
		"再走 8 回合不新增触发（%d → %d）" % [base, rt.trap_triggers_count()])
	_check(bool(_patrol(rt, "p0")["trap_armed"]), "p0 仍保持武装")
	_check(not bool(_patrol(rt, "p0")["trap_used"]), "未被战斗消耗前 trap_used 仍为 false")
	_check(rt.trap_state.size() == 3, "陷阱状态仍是 3 条（%d）" % rt.trap_state.size())


# ---------------------------------------------------------------------------
# D 接触应用破甲且只结算一次
# ---------------------------------------------------------------------------

func _test_apply_once() -> void:
	var rt = _rt()
	rt.wait_turn()
	rt.wait_turn()
	var p0: Dictionary = _patrol(rt, "p0")
	_check(bool(p0["trap_armed"]), "p0 在 45 处已武装")

	# 玩家站在 44（p0 环上的下一格，此时为空）并撞向 45。
	rt.player_cell = P0_AFTER_TRAP
	var bump: Dictionary = rt.try_move(TRAP_A)
	_check(String(bump["reason"]) == "patrol", "撞到被占陷阱格返回 patrol")
	var contact: Dictionary = bump["contact"]
	_check(bool(contact["armor_break"]), "接触时应用破甲")
	_check(int(contact["armor_before"]) > 0, "破甲前护甲 > 0（%d）" % int(contact["armor_before"]))
	_check(int(contact["armor_after"]) == 0, "破甲后护甲为 0")

	var node: Dictionary = rt.pending_battle
	_check(bool(node["armor_break"]), "待战节点标记 armor_break")
	_check(int(node["armor_before"]) == int(contact["armor_before"]), "待战节点护甲前值一致")
	_check(int(node["armor_after"]) == 0, "待战节点护甲后值为 0")
	_check(String(node["armor_text"]).find("→ 0") >= 0, "文案写出「护甲 X → 0」（%s）" % String(node["armor_text"]))
	_check(int(node["trap_cell"]) == TRAP_A, "待战节点记录陷阱格 45")

	_check(bool(rt.trap_state[TRAP_A]["consumed"]), "陷阱标记为已结算")
	_check(not bool(_patrol(rt, "p0")["trap_armed"]), "结算后 p0 解除武装")
	_check(bool(_patrol(rt, "p0")["trap_used"]), "结算后 p0 标记已用过")
	var triggers: int = rt.trap_triggers_count()

	# 战斗返回后再次撞击：不再有破甲。
	rt.resolve_contact(false)
	_check(rt.pending_battle.is_empty(), "战斗返回后待战节点清空")
	var again: Dictionary = rt.try_move(TRAP_A)
	var c2: Dictionary = again["contact"]
	_check(not bool(c2["armor_break"]), "第二次接触不再破甲")
	_check(int(c2["armor_before"]) == int(c2["armor_after"]), "第二次护甲不变")
	_check(rt.trap_triggers_count() == triggers, "第二次接触不新增陷阱触发")

	# 第三只怪各自独立：p1/p2 仍各自武装，互不影响。
	_check(bool(_patrol(rt, "p1")["trap_armed"]), "p1 的武装不受 p0 影响")
	_check(bool(_patrol(rt, "p2")["trap_armed"]), "p2 的武装不受 p0 影响")


# ---------------------------------------------------------------------------
# E 预告与实战护甲一致
# ---------------------------------------------------------------------------

func _test_preview_matches() -> void:
	var rt = _rt()
	rt.wait_turn()
	rt.wait_turn()
	var preview: Array = rt.trap_preview()
	_check(preview.size() == 3, "预告覆盖 3 只（%d）" % preview.size())

	var p0_row: Dictionary = {}
	for row in preview:
		if String(row["id"]) == "p0":
			p0_row = row
	_check(not p0_row.is_empty(), "预告包含 p0")
	_check(bool(p0_row["armed"]), "预告显示 p0 已武装")
	_check(int(p0_row["armor_after"]) == 0, "预告破甲后为 0")
	_check(String(p0_row["text"]).find("→ 0") >= 0, "预告文案含「→ 0」")

	# 预告值 == 实战值。
	rt.player_cell = P0_AFTER_TRAP
	var contact: Dictionary = rt.try_move(TRAP_A)["contact"]
	_check(int(contact["armor_before"]) == int(p0_row["armor"]), "实战护甲前值等于预告值")
	_check(int(contact["armor_after"]) == int(p0_row["armor_after"]), "实战护甲后值等于预告值")

	# 未武装但下一步踩陷阱 → 有明确预告文案。
	var rt2 = _rt()
	var hint_found := false
	for row in rt2.trap_preview():
		if String(row["hint"]).find("护甲") >= 0:
			hint_found = true
			_check(bool(row["next_is_trap"]), "提示对应下一步是陷阱格")
			_check(not bool(row["armed"]), "提示出现在未武装状态")
	_check(hint_found, "未踩陷阱前给出「下一步踩到陷阱」护甲提示")


# ---------------------------------------------------------------------------
# F 不秒杀、不跳过战斗
# ---------------------------------------------------------------------------

func _test_no_instakill() -> void:
	var rt = _rt()
	rt.wait_turn()
	rt.wait_turn()
	var room: RoomData = _patrol(rt, "p0")["room"]
	var hp_before: int = int(room.hp)
	rt.player_cell = P0_AFTER_TRAP
	var contact: Dictionary = rt.try_move(TRAP_A)["contact"]
	var node: Dictionary = contact["node"]
	_check(String(node["type"]) == "battle", "破甲后仍是战斗节点，不跳过转轮")
	_check(String(node["kind"]) == "patrol", "战斗对象是巡逻怪")
	_check(node["room"] != null, "战斗仍绑定真实房间")
	_check(int((node["room"] as RoomData).hp) == hp_before, "破甲不修改房间 HP（%d）" % hp_before)
	_check(int(node["armor_after"]) == 0 and hp_before > 0, "只把护甲降到 0，不杀怪")
	_check(not node.has("instant_kill"), "节点没有即时击杀标记")
	_check(rt.settled_log.is_empty(), "接触本身不发奖、不结算地图内容")
	_check(rt.consumed.is_empty(), "接触不写探索消耗表")


# ---------------------------------------------------------------------------
# G 玩家踩陷阱不受无预告伤害
# ---------------------------------------------------------------------------

func _test_player_on_trap() -> void:
	var rt = _rt()
	# 推进到 p0 离开 45（3 回合后 p0 在 44）。
	for i in range(3):
		rt.wait_turn()
	var triggers: int = rt.trap_triggers_count()
	rt.player_cell = NEAR_TRAP_A
	var before_turn: int = rt.turn
	var moved: Dictionary = rt.try_move(TRAP_A)
	_check(bool(moved["ok"]), "玩家可以正常走进陷阱格")
	_check(rt.player_cell == TRAP_A, "玩家位于陷阱格")
	_check(rt.turn == before_turn + 1, "进陷阱格只推进一个回合")
	_check(rt.trap_triggers_count() == triggers, "玩家踩陷阱不产生怪物触发")
	_check(rt.pending_battle.is_empty(), "玩家踩陷阱不进入战斗")
	_check(rt.settled_log.is_empty(), "玩家踩陷阱不产生结算（无伤害、无奖励）")
	_check(bool(rt.view(TRAP_A)["trap"]), "陷阱位置对玩家始终公开")


# ---------------------------------------------------------------------------
# H 无陷阱路线也能正常战斗
# ---------------------------------------------------------------------------

func _test_without_trap() -> void:
	var rt = _rt()
	rt.player_cell = NEAR_P0
	var bump: Dictionary = rt.try_move(P0_SPAWN)
	var contact: Dictionary = bump["contact"]
	_check(not bool(contact["armor_break"]), "未踩陷阱时接触不破甲")
	_check(int(contact["armor_before"]) == MAP_TRAP.armor_of(_patrol(rt, "p0")["room"]),
		"未破甲时护甲等于基础值")
	_check(int(contact["armor_after"]) == int(contact["armor_before"]),
		"未破甲时护甲不变（不会误降为 0）")
	_check(not bool(_patrol(rt, "p0")["trap_used"]), "未破甲不消耗陷阱")
	_check(rt.trap_triggers_count() == 0, "整条路线都没踩陷阱")
	var node: Dictionary = contact["node"]
	_check(String(node["type"]) == "battle" and node["room"] != null,
		"无陷阱路线照样进入正常战斗")
	_check(String(node["armor_text"]) == "", "无破甲时不显示破甲文案")
	# 玩家 61 房裸 Build 全通由第 48 套 counterplay_test 覆盖（won=61/61），
	# 本套只证「破甲不是开战的必要条件」。
	_check(not bool(rt.pending_battle.is_empty()), "无陷阱也能正常挂起待战节点")


# ---------------------------------------------------------------------------
# I 存档恢复含陷阱状态
# ---------------------------------------------------------------------------

func _test_save_restore() -> void:
	var rt = _rt()
	rt.wait_turn()
	rt.wait_turn()
	_check(rt.trap_triggers_count() == 3, "存档前已三次触发")
	var saved: Dictionary = rt.to_dict()
	var states: Array = saved["patrols"]
	var armed_flags: Array = []
	for s in states:
		armed_flags.append(bool(s.get("trap_armed", false)))
	_check(armed_flags == [true, true, true], "存档记录三只都已武装（%s）" % str(armed_flags))

	var parsed = JSON.parse_string(JSON.stringify(saved))
	_check(parsed is Dictionary, "含陷阱状态的存档可 JSON 往返")
	var restored = _rt()
	_check(restored.from_dict(parsed), "含陷阱状态的存档可恢复")
	_check(restored.signature() == rt.signature(), "恢复后状态指纹一致")
	_check(restored.trap_state.size() == 3, "恢复后陷阱状态 3 条")
	_check(bool(_patrol(restored, "p0")["trap_armed"]), "恢复后 p0 仍武装")
	_check(int(_patrol(restored, "p0")["trap_cell"]) == TRAP_A, "恢复后 p0 的陷阱格正确")

	for i in range(4):
		rt.wait_turn()
		restored.wait_turn()
	_check(restored.signature() == rt.signature(), "恢复后继续推进结果一致")
	_check(restored.trap_triggers_count() <= rt.trap_triggers_count(),
		"恢复后不会重复记录已发生的触发")


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("PASS  " + what)
	else:
		_fails += 1
		print("FAIL  " + what)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
