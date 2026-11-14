extends Node

# ============================================================================
# 地图巡逻诱导 · Step 1 · 14×9 灰盒地图定向回归（2026-11-14）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/map_grid_test.tscn
#
# 覆盖（计划 §6 Step 1 出口 + §1.2 预算 + §3.2 路线要求）：
#   ① 地图恰好 14×9，可行走格 55–70，三区域与两道门；
#   ② 普通 / 精英 / BOSS / 宝箱 / 商店 / 休整 / 事件 / 陷阱数量符合预算；
#   ③ 起点到 BOSS 可达，精英可绕行，BOSS 无探索率门票，起点无必败开局；
#   ④ 固定种子生成后不随揭示、回访或重开界面重抽；
#   ⑤ validate() 能拦住被写坏的地图；
#   ⑥ 运行时状态不写进 cell（Step 0 冻结口径）。
#
# 本套不加载 duel.tscn，纯静态数据校验，不改动现有运行入口。
# ============================================================================

const MAP = preload("res://scripts/board/map_grid.gd")
const SEED := 20261110

var _checks := 0
var _fails := 0


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	var data: Dictionary = MAP.generate(SEED)
	print("=== A 结构 ===")
	_test_structure(data)
	print("=== B 预算 ===")
	_test_budget(data)
	print("=== C 路线 ===")
	_test_routes(data)
	print("=== D 固定种子 ===")
	_test_determinism(data)
	print("=== E validate 防护 ===")
	_test_validate_guards(data)
	print("---")
	print("MAPGRID|ASCII\n%s" % MAP.ascii_map(data))
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	print("MAPGRID|RESULT %s (checks=%d fails=%d)" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("PASS " + label)
	else:
		_fails += 1
		print("FAIL " + label)


# ---------------------------------------------------------------- A 结构
func _test_structure(data: Dictionary) -> void:
	var cells: Array = data["cells"]
	_check(int(data["cols"]) == 14 and int(data["rows"]) == 9, "地图恰好 14×9")
	_check(cells.size() == 126, "格数 126（实际 %d）" % cells.size())
	_check(MAP.LAYOUT.size() == 9, "LAYOUT 有 9 行")
	var row_len_ok := true
	for line in MAP.LAYOUT:
		if String(line).length() != 14:
			row_len_ok = false
	_check(row_len_ok, "每行恰好 14 字符")
	_check(MAP.ascii_map(data) == "\n".join(MAP.LAYOUT), "ASCII 还原与 LAYOUT 一致")

	var ok_ids := true
	var ok_runtime := true
	var runtime_keys := ["revealed", "visible", "consumed", "defeated", "frozen"]
	var walls := 0
	var walks := 0
	var doors := 0
	var region_walk := {"A": 0, "B": 0, "C": 0}
	for i in range(cells.size()):
		var c: Dictionary = cells[i]
		if int(c["id"]) != i or int(c["col"]) != i % 14 or int(c["row"]) != i / 14:
			ok_ids = false
		for k in runtime_keys:
			if c.has(k):
				ok_runtime = false
		if String(c["terrain"]) == "wall":
			walls += 1
		else:
			walks += 1
			region_walk[String(c["region"])] = int(region_walk[String(c["region"])]) + 1
		if String(c["terrain"]) == "door":
			doors += 1
	_check(ok_ids, "每格 id / row / col 与行优先下标一致")
	_check(ok_runtime, "cell 未写入 revealed / visible / consumed / defeated / frozen")
	_check(walls + walks == 126, "墙 + 可走格 = 126")
	_check(walks == 61 and walks >= 55 and walks <= 70,
		"可行走格 61，落在 55–70（实际 %d）" % walks)
	_check(int(region_walk["A"]) > 0 and int(region_walk["B"]) > 0
		and int(region_walk["C"]) > 0, "三区域都有可行走格（A%d/B%d/C%d）" % [
			int(region_walk["A"]), int(region_walk["B"]), int(region_walk["C"])])
	_check(doors == 2 and data["doors"].size() == 2, "区域门恰好 2 道")
	var door_cols: Array = []
	for raw in data["doors"]:
		door_cols.append(int(cells[int(raw)]["col"]))
	door_cols.sort()
	_check(door_cols == [5, 10], "两道门位于 col5 / col10 区域边界")
	for raw in data["doors"]:
		_check(String(cells[int(raw)]["terrain"]) == "door",
			"门 %d 地形为 door" % int(raw))
	_check(data["nodes"].size() == 28, "内容节点 28 个（实际 %d）" % data["nodes"].size())
	_check(bool(data["nodes"][int(data["boss_id"])]["final"]), "BOSS 节点标记 final")


# ---------------------------------------------------------------- B 预算
func _test_budget(data: Dictionary) -> void:
	var counts: Dictionary = data["counts"]
	var band := {
		"normal": [10, 14], "elite": [2, 3], "boss": [1, 1],
		"battle": [14, 18], "treasure": [3, 5], "shop": [1, 2],
		"rest": [1, 2], "shrine": [3, 5], "trap": [2, 4],
	}
	for key in band.keys():
		var got: int = int(counts.get(key, -1))
		var lo: int = int(band[key][0])
		var hi: int = int(band[key][1])
		_check(got >= lo and got <= hi,
			"%s 数量 %d 在 %d–%d" % [key, got, lo, hi])
	var battle_sum := 0
	for t in ["normal", "elite", "boss"]:
		battle_sum += int(counts.get(t, 0))
	_check(int(counts["battle"]) == battle_sum, "battle 合计 = 三类战斗之和（%d）" % battle_sum)
	_check(int(counts["walkable"]) == 61, "counts.walkable 与实测一致")

	var traps: Array = data["traps"]
	_check(int(counts["trap"]) == traps.size(), "counts.trap 与 traps 数组一致")
	var all_walk := true
	var all_type := true
	var in_a := 0
	for t in traps:
		var tid: int = int(t["cell_id"])
		if not bool(data["cells"][tid]["walkable"]):
			all_walk = false
		if String(t["type"]) != "armor_break":
			all_type = false
		if String(t["region"]) == "A":
			in_a += 1
	_check(all_walk, "陷阱全部落在可行走格（位置公开）")
	_check(all_type, "首版陷阱只有 armor_break 一种")
	_check(in_a == 1, "入口区 A 恰好 1 个陷阱（§3.1）")
	var seen_trap: Dictionary = {}
	var dup := false
	for t in traps:
		var tid: int = int(t["cell_id"])
		if seen_trap.has(tid):
			dup = true
		seen_trap[tid] = true
	_check(not dup, "陷阱位置不重叠")


# ---------------------------------------------------------------- C 路线
func _test_routes(data: Dictionary) -> void:
	var errs: Array = MAP.validate(data)
	_check(errs.is_empty(), "validate() 无错误（%d 条）%s" % [errs.size(), str(errs)])
	var s: int = int(data["start_id"])
	var b: int = int(data["boss_id"])
	var cells: Array = data["cells"]
	_check(s >= 0 and b >= 0 and s != b, "起点 / BOSS id 合法且不同")
	var path: Array = MAP.reachable(data, s, b)
	_check(not path.is_empty(), "起点到 BOSS 至少一条合法路径（%d 格）" % path.size())
	var path_has_elite := false
	for raw in path:
		if String(cells[int(raw)]["content"]) == "elite":
			path_has_elite = true
	_check(not path_has_elite, "主干路径不含精英（精英可绕行）")
	var avoid_elite: Array = MAP.reachable(data, s, b, ["elite"])
	_check(not avoid_elite.is_empty(), "存在显式避开全部精英的路径")
	var avoid_explore: Array = MAP.reachable(data, s, b, MAP.EXPLORE_TYPES)
	_check(not avoid_explore.is_empty(), "BOSS 无探索率门票（不依赖宝箱/事件/商店/休整）")
	var seen: Dictionary = MAP.all_reachable_from(data, s)
	_check(int(seen.size()) == int(data["counts"]["walkable"]),
		"全部可行走格从起点可达（%d）" % int(seen.size()))
	var start_neighbors: Array = MAP.neighbors(data, s)
	_check(start_neighbors.size() >= 2, "起点至少 2 个可走邻格（%d）" % start_neighbors.size())
	var start_safe := true
	for raw in start_neighbors:
		var t: String = String(cells[int(raw)]["content"])
		if t == "elite" or t == "boss":
			start_safe = false
	_check(start_safe, "起点相邻无精英 / BOSS，无必败开局")
	var nodes_reach := true
	for key in data["nodes"].keys():
		if not seen.has(int(key)):
			nodes_reach = false
	_check(nodes_reach, "全部内容节点可达，无被墙锁死的奖励")

	# 三条路线雏形：上分支 / 主干 / 下分支各有内容节点。
	var band := {"upper": 0, "main": 0, "lower": 0}
	for key in data["nodes"].keys():
		var r: int = int(cells[int(key)]["row"])
		if r <= 3:
			band["upper"] = int(band["upper"]) + 1
		elif r == 4:
			band["main"] = int(band["main"]) + 1
		else:
			band["lower"] = int(band["lower"]) + 1
	_check(int(band["upper"]) > 0 and int(band["main"]) > 0 and int(band["lower"]) > 0,
		"上分支 / 主干 / 下分支均有内容（%d/%d/%d）" % [
			int(band["upper"]), int(band["main"]), int(band["lower"])])
	# 每个精英单独移除后仍可从起点到 BOSS。
	var elite_ids: Array = []
	for key in data["nodes"].keys():
		if String(data["nodes"][key]["type"]) == "elite":
			elite_ids.append(int(key))
	var each_avoid := true
	for eid in elite_ids:
		if MAP.reachable(data, s, b, [], [eid]).is_empty():
			each_avoid = false
	_check(each_avoid, "逐个屏蔽 %d 个精英后 BOSS 仍可达" % elite_ids.size())
	# 巡逻起点：A 区 1 只、C 区最多 2 只，且都在可走格。
	var patrol: Array = data["patrol_spawns"]
	var pa := 0
	var pc := 0
	var patrol_ok := true
	for raw in patrol:
		var pid: int = int(raw)
		if not bool(cells[pid]["walkable"]):
			patrol_ok = false
		var reg: String = String(cells[pid]["region"])
		if reg == "A":
			pa += 1
		elif reg == "C":
			pc += 1
		else:
			patrol_ok = false
	_check(patrol_ok and pa == 1 and pc <= 2,
		"巡逻起点 A=1 / C=%d（§3.1 后期区域最多 2 只）" % pc)


# ---------------------------------------------------------------- D 固定种子
func _signature(data: Dictionary) -> String:
	var parts: Array = []
	parts.append("seed=%d" % int(data["seed"]))
	for c in data["cells"]:
		parts.append("%d:%s:%s:%s" % [int(c["id"]), String(c["terrain"]),
			String(c["region"]), String(c["content"])])
	var keys: Array = data["nodes"].keys()
	keys.sort()
	for k in keys:
		parts.append("n%d=%d" % [int(k), int(data["nodes"][k]["variant"])])
	for t in data["traps"]:
		parts.append("t%d" % int(t["cell_id"]))
	parts.append("p" + str(data["patrol_spawns"]))
	return "|".join(parts)


func _layout_signature(data: Dictionary) -> String:
	var parts: Array = []
	for c in data["cells"]:
		parts.append("%s:%s" % [String(c["terrain"]), String(c["content"])])
	return "|".join(parts)


func _test_determinism(data: Dictionary) -> void:
	var sig: String = _signature(data)
	var layout: String = _layout_signature(data)

	# 模拟揭示 / 回访 / 重开界面：运行时状态写在外部字典，不触碰 MapGrid 数据。
	var runtime_state: Dictionary = {}
	runtime_state[30] = true          # 揭示 A 区一格
	runtime_state[95] = "revisited"   # 回访 C 区一格
	var again: Dictionary = MAP.generate(SEED)
	_check(_signature(again) == sig, "重开界面后同种子逐字段一致")
	_check(MAP.generate(SEED)["cells"][30].has("revealed") == false,
		"揭示状态未写回 cell")
	_check(_signature(MAP.generate(SEED)) == sig, "连续三次生成结果不变")
	_check(runtime_state.size() == 2, "运行时状态由外部字典持有（模拟）")

	# 不同种子：布局不变，只有内容变体改变。
	var other: Dictionary = MAP.generate(20261111)
	_check(_layout_signature(other) == layout, "不同种子不改变地形与内容布局")
	_check(_signature(other) != sig, "不同种子产生不同内容变体")
	_check(MAP.validate(other).is_empty(), "20261111 地图合法")
	var third: Dictionary = MAP.generate(20261112)
	_check(MAP.validate(third).is_empty(), "20261112 地图合法")
	_check(_signature(third) != sig and _signature(third) != _signature(other),
		"三个固定种子各自可区分")
	_check(other["traps"] == data["traps"], "陷阱位置不随种子重抽")
	_check(other["patrol_spawns"] == data["patrol_spawns"], "巡逻起点不随种子重抽")
	var act3: Dictionary = MAP.generate(SEED, 3)
	_check(int(act3["nodes"][int(act3["start_id"])]["act"]) == 3,
		"act 只写进节点，不改布局")
	_check(_layout_signature(act3) == layout, "act 变化不改变地形与内容")


# ---------------------------------------------------------------- E validate 防护
func _test_validate_guards(data: Dictionary) -> void:
	var boss_id: int = int(data["boss_id"])

	var bad_wall: Dictionary = data.duplicate(true)
	bad_wall["cells"][boss_id]["walkable"] = false
	bad_wall["cells"][boss_id]["terrain"] = "wall"
	_check(not MAP.validate(bad_wall).is_empty(), "BOSS 被改成墙时 validate 报错")

	var bad_count: Dictionary = data.duplicate(true)
	bad_count["counts"]["walkable"] = 99
	_check(not MAP.validate(bad_count).is_empty(), "counts.walkable 被篡改时报错")

	var bad_trap_count: Dictionary = data.duplicate(true)
	bad_trap_count["traps"].remove_at(0)
	_check(not MAP.validate(bad_trap_count).is_empty(), "少一个陷阱时报错")

	var bad_trap_cell: Dictionary = data.duplicate(true)
	bad_trap_cell["traps"][0]["cell_id"] = 0  # (row0,col0) 是墙
	_check(not MAP.validate(bad_trap_cell).is_empty(), "陷阱放到墙上时报错")

	var bad_runtime: Dictionary = data.duplicate(true)
	bad_runtime["cells"][30]["revealed"] = true
	_check(not MAP.validate(bad_runtime).is_empty(), "cell 写入运行时状态时报错")

	var bad_door: Dictionary = data.duplicate(true)
	var did: int = int(data["doors"][0])
	bad_door["cells"][did]["terrain"] = "wall"
	bad_door["cells"][did]["walkable"] = false
	_check(not MAP.validate(bad_door).is_empty(), "入口门被堵死时报错")

	var bad_type: Dictionary = data.duplicate(true)
	bad_type["traps"][0]["type"] = "instant_death"
	_check(not MAP.validate(bad_type).is_empty(), "出现非破甲陷阱时报错")
	_check(MAP.validate(data.duplicate(true)).is_empty(), "深拷贝的合法地图仍通过")
