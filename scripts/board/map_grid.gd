extends RefCounted

# ============================================================================
# MapGrid — 14×9 三区域逻辑地图（地图巡逻诱导 · Step 1，2026-11-14）
#
# 不注册 class_name（与 board_config.gd / board_grid.gd 同约定）：
# headless 测试与新检出环境不会自动刷新类缓存，一律用 preload / load 引用。
#
# 单一地图口径（作者 2026-11-14 拍板）：本类是 14×9 地图**唯一**静态数据源。
# 旧的 board_generator.gd（1D3 节点骨架）与 board_grid.gd（4×4 扫雷灰盒）
# 暂留磁盘但不再扩展；运行入口切换与两者退役统一放到 Step 2。
#
# Step 0 冻结口径：
#   · 静态字段（terrain / row·col / content / 区域 / 门 / 陷阱位）归本类；
#   · 运行时消耗 / 击败 / 揭示状态一律不写进 cell，由 BoardSystem 字典持有；
#   · content 复用 BoardNodeData 的 11 种 type，不新增平行类型；
#   · 陷阱不是节点类型，作为公开位置叠加在可行走格上。
# ============================================================================

const COLS := 14
const ROWS := 9
const CELL_COUNT := 126

const TERRAIN_WALL := "wall"
const TERRAIN_WALK := "walkable"
const TERRAIN_DOOR := "door"

const REGION_A := "A"
const REGION_B := "B"
const REGION_C := "C"

# 字符：# 墙 / . 空可走 / S 起点 / B BOSS / N 普通 / E 精英 / T 宝箱
#       P 商店 / R 休整 / V 特殊事件(神龛) / X 破甲陷阱 / D 区域门
# 可行走 61 格；三区域只有 row4 的两道门互通；主干 row4 不含精英。
# Step 4（2026-11-14）：三个陷阱从 row4 咽喉（59/64）与 C 区死胡同（94）
# 移到三条巡逻环上的非咽喉格（45 / 39 / 110），使「怪物踩陷阱」在真实路线上可达，
# 且任意陷阱被占都不会切断 起点→BOSS。可行走格与内容数量不变。
const LAYOUT := [
	"##############",
	"#..T##T.V#..T#",
	"#N..##..E##XE#",
	"#V.X##P.N##N.#",
	"#SN.NDNN.NDNB#",
	"#...##R.N##R.#",
	"#..N##..E#..T#",
	"#V.N##V#.##.X#",
	"##############",
]

const WALKABLE_MIN := 55
const WALKABLE_MAX := 70

# 计划 §1.2 固定预算：数量是内容预算，校验按闭区间判定。
const BUDGET := {
	"normal": [10, 14],
	"elite": [2, 3],
	"boss": [1, 1],
	"battle": [14, 18],
	"treasure": [3, 5],
	"shop": [1, 2],
	"rest": [1, 2],
	"shrine": [3, 5],
	"trap": [2, 4],
}

const CHAR_CONTENT := {
	"S": "start",
	"B": "boss",
	"N": "normal",
	"E": "elite",
	"T": "treasure",
	"P": "shop",
	"R": "rest",
	"V": "shrine",
}

const BATTLE_TYPES := ["normal", "elite", "boss"]
const EXPLORE_TYPES := ["treasure", "shrine", "shop", "rest"]
const TRAP_TYPE := "armor_break"

# 巡逻起点（§3.1：A 区 1 只，C 区最多 2 只）。Step 1 只冻结坐标，不实现巡逻。
const PATROL_SPAWNS := [30, 25, 95]  # (row2,col2) A / (row1,col11) C / (row6,col11) C

const NODE = preload("res://scripts/board/board_node_data.gd")


static func cell_id(col: int, row: int) -> int:
	return col + row * COLS


static func region_of(col: int) -> String:
	if col <= 4:
		return REGION_A
	if col <= 9:
		return REGION_B
	return REGION_C


# 固定种子生成：只读 seed / act，不读任何运行时状态。
# 揭示、回访、重开界面都不会改变结果；同种子逐字段一致。
static func generate(seed_value: int, act: int = 1) -> Dictionary:
	var cells: Array = []
	var nodes: Dictionary = {}
	var traps: Array = []
	var doors: Array = []
	var counts: Dictionary = {}
	var walkable := 0
	var start_id := -1
	var boss_id := -1
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	for row in range(ROWS):
		var line: String = String(LAYOUT[row])
		for col in range(COLS):
			var ch: String = line.substr(col, 1)
			var id: int = cell_id(col, row)
			var terrain: String = TERRAIN_WALK
			if ch == "#":
				terrain = TERRAIN_WALL
			elif ch == "D":
				terrain = TERRAIN_DOOR
			var is_walk: bool = terrain != TERRAIN_WALL
			var content: String = ""
			if CHAR_CONTENT.has(ch):
				content = String(CHAR_CONTENT[ch])
			var region: String = region_of(col)

			cells.append({
				"id": id,
				"row": row,
				"col": col,
				"terrain": terrain,
				"region": region,
				"walkable": is_walk,
				"content": content,
			})
			if not is_walk:
				continue
			walkable += 1

			if ch == "D":
				doors.append(id)
			elif ch == "X":
				traps.append({
					"cell_id": id,
					"row": row,
					"col": col,
					"region": region,
					"type": TRAP_TYPE,
				})

			if content != "":
				var node: Dictionary = NODE.make("m%d" % id, content, col)
				node["cell_id"] = id
				node["row"] = row
				node["col"] = col
				node["region"] = region
				node["terrain"] = terrain
				node["act"] = act
				node["final"] = content == "boss"
				# 种子只决定内容变体，供 Step 3 之后绑定房间 / 奖励；布局不受影响。
				node["variant"] = rng.randi() % 3
				nodes[id] = node
				counts[content] = int(counts.get(content, 0)) + 1
				if content == "start":
					start_id = id
				elif content == "boss":
					boss_id = id

	var battle_total := 0
	for t in BATTLE_TYPES:
		battle_total += int(counts.get(t, 0))
	counts["battle"] = battle_total
	counts["trap"] = traps.size()
	counts["walkable"] = walkable

	return {
		"seed": seed_value,
		"act": act,
		"cols": COLS,
		"rows": ROWS,
		"cells": cells,
		"nodes": nodes,
		"traps": traps,
		"doors": doors,
		"patrol_spawns": PATROL_SPAWNS.duplicate(),
		"counts": counts,
		"start_id": start_id,
		"boss_id": boss_id,
	}


static func neighbors(data: Dictionary, id: int) -> Array:
	var cells: Array = data["cells"]
	if id < 0 or id >= CELL_COUNT:
		return []
	var col: int = int(cells[id]["col"])
	var row: int = int(cells[id]["row"])
	var out: Array = []
	for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
		var nc: int = col + int(d[0])
		var nr: int = row + int(d[1])
		if nc < 0 or nc >= COLS or nr < 0 or nr >= ROWS:
			continue
		var nid: int = cell_id(nc, nr)
		if bool(cells[nid]["walkable"]):
			out.append(nid)
	return out


# 4 邻接 BFS。avoid_types 排除含指定 content 的格，avoid_cells 排除指定格。
# 返回 id 路径（含首尾），不可达返回空数组。
static func reachable(data: Dictionary, from_id: int, to_id: int,
		avoid_types: Array = [], avoid_cells: Array = []) -> Array:
	var cells: Array = data["cells"]
	if from_id < 0 or to_id < 0 or from_id >= CELL_COUNT or to_id >= CELL_COUNT:
		return []
	if not bool(cells[from_id]["walkable"]) or not bool(cells[to_id]["walkable"]):
		return []
	var q: Array = [from_id]
	var prev: Dictionary = {from_id: -1}
	while not q.is_empty():
		var cur: int = int(q.pop_front())
		if cur == to_id:
			var path: Array = []
			var x: int = cur
			while x != -1:
				path.append(x)
				x = int(prev[x])
			path.reverse()
			return path
		for raw in neighbors(data, cur):
			var nid: int = int(raw)
			if prev.has(nid) or avoid_cells.has(nid):
				continue
			var t: String = String(cells[nid]["content"])
			if t != "" and avoid_types.has(t):
				continue
			prev[nid] = cur
			q.append(nid)
	return []


static func all_reachable_from(data: Dictionary, from_id: int) -> Dictionary:
	var cells: Array = data["cells"]
	var seen: Dictionary = {from_id: true}
	var q: Array = [from_id]
	while not q.is_empty():
		var cur: int = int(q.pop_front())
		for raw in neighbors(data, cur):
			var nid: int = int(raw)
			if seen.has(nid):
				continue
			seen[nid] = true
			q.append(nid)
	return seen


# 计划 §6 Step 1 六条出口 + §1.2 预算 + §3.2 路线要求。
# 返回错误字符串数组，空数组代表合法。
static func validate(data: Dictionary) -> Array:
	var errs: Array = []
	var cells: Array = data.get("cells", [])
	var counts: Dictionary = data.get("counts", {})
	var nodes: Dictionary = data.get("nodes", {})
	var traps: Array = data.get("traps", [])
	var doors: Array = data.get("doors", [])
	var start_id: int = int(data.get("start_id", -1))
	var boss_id: int = int(data.get("boss_id", -1))

	if int(data.get("cols", 0)) != COLS or int(data.get("rows", 0)) != ROWS:
		errs.append("尺寸不是 14×9")
	if cells.size() != CELL_COUNT:
		errs.append("格数不是 126（%d）" % cells.size())

	var walkable := 0
	var region_walk := {"A": 0, "B": 0, "C": 0}
	var runtime_keys := ["revealed", "visible", "consumed", "defeated", "frozen"]
	for i in range(min(int(cells.size()), CELL_COUNT)):
		var c: Dictionary = cells[i]
		if int(c.get("id", -1)) != i:
			errs.append("cell[%d] id 与行优先下标不一致" % i)
		if int(c.get("col", -1)) != i % COLS or int(c.get("row", -1)) != i / COLS:
			errs.append("cell[%d] row/col 与下标不一致" % i)
		var terrain: String = String(c.get("terrain", ""))
		if not (terrain == TERRAIN_WALL or terrain == TERRAIN_WALK or terrain == TERRAIN_DOOR):
			errs.append("cell[%d] terrain 非法：%s" % [i, terrain])
		var region: String = String(c.get("region", ""))
		if not (region == REGION_A or region == REGION_B or region == REGION_C):
			errs.append("cell[%d] region 非法：%s" % [i, region])
		for k in runtime_keys:
			if c.has(k):
				errs.append("cell[%d] 写入了运行时状态 %s" % [i, k])
		if bool(c.get("walkable", false)):
			walkable += 1
			region_walk[region] = int(region_walk.get(region, 0)) + 1
			if terrain == TERRAIN_WALL:
				errs.append("cell[%d] 墙被标为可行走" % i)
		elif terrain != TERRAIN_WALL:
			errs.append("cell[%d] 非墙却不可行走" % i)

	if walkable < WALKABLE_MIN or walkable > WALKABLE_MAX:
		errs.append("可行走格 %d 不在 55–70" % walkable)
	if int(counts.get("walkable", -1)) != walkable:
		errs.append("counts.walkable 与实际不符")
	for key in [REGION_A, REGION_B, REGION_C]:
		if int(region_walk.get(key, 0)) <= 0:
			errs.append("区域 %s 没有可行走格" % key)

	for key in BUDGET.keys():
		var band: Array = BUDGET[key]
		var got: int = int(counts.get(key, 0))
		if got < int(band[0]) or got > int(band[1]):
			errs.append("%s 数量 %d 不在 %d–%d" % [key, got, int(band[0]), int(band[1])])
	var battle_sum := 0
	for t in BATTLE_TYPES:
		battle_sum += int(counts.get(t, 0))
	if int(counts.get("battle", -1)) != battle_sum:
		errs.append("battle 合计与三类战斗之和不符")

	if int(counts.get("start", 0)) != 1:
		errs.append("起点不是唯一")
	if int(counts.get("boss", 0)) != 1:
		errs.append("BOSS 不是唯一")
	if start_id < 0 or boss_id < 0:
		errs.append("起点 / BOSS id 缺失")
	if nodes.has(boss_id) and not bool(nodes[boss_id].get("final", false)):
		errs.append("BOSS 节点未标记 final")

	if doors.size() != 2:
		errs.append("区域门不是 2 道（%d）" % doors.size())
	for raw in doors:
		var did: int = int(raw)
		if did < 0 or did >= CELL_COUNT or not bool(cells[did]["walkable"]):
			errs.append("门 %d 不可行走" % did)
		elif String(cells[did]["terrain"]) != TERRAIN_DOOR:
			errs.append("门 %d 地形不是 door" % did)

	if traps.size() != int(counts.get("trap", -1)):
		errs.append("陷阱数量与 counts.trap 不符")
	var trap_in_a := 0
	for t in traps:
		var tid: int = int(t.get("cell_id", -1))
		if tid < 0 or tid >= CELL_COUNT or not bool(cells[tid]["walkable"]):
			errs.append("陷阱 %d 不在可行走格" % tid)
		if String(t.get("type", "")) != TRAP_TYPE:
			errs.append("陷阱 %d 类型不是 armor_break" % tid)
		if String(t.get("region", "")) == REGION_A:
			trap_in_a += 1
	if trap_in_a < 1:
		errs.append("入口区 A 没有陷阱")

	var patrol: Array = data.get("patrol_spawns", [])
	var patrol_a := 0
	var patrol_c := 0
	for raw in patrol:
		var pid: int = int(raw)
		if pid < 0 or pid >= CELL_COUNT or not bool(cells[pid]["walkable"]):
			errs.append("巡逻起点 %d 不在可行走格" % pid)
			continue
		var region: String = String(cells[pid]["region"])
		if region == REGION_A:
			patrol_a += 1
		elif region == REGION_C:
			patrol_c += 1
		else:
			errs.append("巡逻起点 %d 落在区域 %s" % [pid, region])
	if patrol_a != 1:
		errs.append("入口区 A 巡逻起点不是 1 只（%d）" % patrol_a)
	if patrol_c > 2:
		errs.append("深层区 C 巡逻起点超过 2 只（%d）" % patrol_c)

	if start_id >= 0 and boss_id >= 0:
		if reachable(data, start_id, boss_id).is_empty():
			errs.append("起点到 BOSS 不可达")
		# 精英可绕行：存在一条不经过任何精英的通路。
		if reachable(data, start_id, boss_id, ["elite"]).is_empty():
			errs.append("不存在绕过精英的起点→BOSS 路径")
		# BOSS 无探索率门票：存在一条不依赖宝箱 / 事件 / 商店 / 休整的通路。
		if reachable(data, start_id, boss_id, EXPLORE_TYPES).is_empty():
			errs.append("BOSS 被探索收益节点锁门")
		var start_neighbors: Array = neighbors(data, start_id)
		if start_neighbors.size() < 2:
			errs.append("起点可走邻格少于 2")
		for raw in start_neighbors:
			var nid: int = int(raw)
			var t: String = String(cells[nid]["content"])
			if t == "elite" or t == "boss":
				errs.append("起点相邻存在 %s，构成必败开局" % t)
		var seen: Dictionary = all_reachable_from(data, start_id)
		if int(seen.size()) != walkable:
			errs.append("存在从起点不可达的可行走格（%d/%d）" % [int(seen.size()), walkable])
		for id_key in nodes.keys():
			var nid: int = int(id_key)
			if not seen.has(nid):
				errs.append("内容节点 %d 不可达" % nid)
	return errs


# 重建 ASCII，便于日志与人工核对；含陷阱 X 标记，与 LAYOUT 一致。
static func ascii_map(data: Dictionary) -> String:
	var cells: Array = data["cells"]
	var trap_ids: Dictionary = {}
	for t in data.get("traps", []):
		trap_ids[int(t["cell_id"])] = true
	var lines: Array = []
	for row in range(ROWS):
		var line := ""
		for col in range(COLS):
			var id: int = cell_id(col, row)
			var c: Dictionary = cells[id]
			var ch: String = String(c["content"])
			if ch == "":
				var terrain: String = String(c["terrain"])
				if terrain == TERRAIN_WALL:
					ch = "#"
				elif terrain == TERRAIN_DOOR:
					ch = "D"
				elif trap_ids.has(id):
					ch = "X"
				else:
					ch = "."
			else:
				for key in CHAR_CONTENT.keys():
					if String(CHAR_CONTENT[key]) == ch:
						ch = String(key)
						break
			line += ch
		lines.append(line)
	return "\n".join(lines)
