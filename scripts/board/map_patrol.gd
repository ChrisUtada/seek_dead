extends RefCounted

# ============================================================================
# MapPatrol — 14×9 地图巡逻怪数据层（Step 3）
# 规格：docs/地图巡逻诱导_第一版预算与分步执行计划_2026-11-14.md
#       §3.3 巡逻规则、§6 Step 3 任务 1–5 与出口
#
# 边界：
# - 路径为**手写冻结的闭合环**，不随机生成：巡逻必须可预测、可复现、可人工核对；
# - 起点与 MapGrid.PATROL_SPAWNS 一致（A 区 1 只 / C 区最多 2 只），顺序固定 0→1→2；
# - 怪物只沿路径前进，path_index 每次 +1 取模，绝不进入墙体或不可行走格；
# - 巡逻可以经过宝箱 / 休整 / 精英格（游戏语义＝守卫），但禁止经过起点与 BOSS 格，
#   保证「巡逻不永久堵死 BOSS」在结构上成立；
# - 接触与战斗结算在 MapRuntime，本类只负责位置、预告与确定性房间绑定。
# ============================================================================

const MAP_GRID = preload("res://scripts/board/map_grid.gd")
const MAP_TRAP = preload("res://scripts/board/map_trap.gd")

# 手写闭合环。校验由 validate() 负责：首格 = 起点、逐段相邻、含回环、无重复、非墙。
# P0 入口区 4 格纯通路（教学用，不穿任何内容格）
# P1 深层区上路 4 格（经过 1 个精英与 1 个宝箱＝守卫）
# P2 深层区下路 6 格（经过 1 个宝箱与 1 个休整）
const PATROLS := [
	{
		"id": "p0", "order": 0, "spawn": 30, "region": "A", "kind": "normal",
		"path": [30, 31, 45, 44],
	},
	{
		"id": "p1", "order": 1, "spawn": 25, "region": "C", "kind": "normal",
		"path": [25, 39, 40, 26],
	},
	{
		"id": "p2", "order": 2, "spawn": 95, "region": "C", "kind": "normal",
		"path": [95, 109, 110, 96, 82, 81],
	},
]

const MIN_PATH := 3


# 生成巡逻初始状态。房间从现有 resources/rooms/ 池按路径字典序确定性选，
# 不新增平行目录，也不受 seed 影响（同幕同顺序永远同一只怪）。
static func build(grid: Dictionary, ctrl, act: int) -> Array:
	var out: Array = []
	for cfg in PATROLS:
		var path: Array = (cfg["path"] as Array).duplicate()
		var order: int = int(cfg["order"])
		var room: RoomData = _pick_room(ctrl, act, order)
		out.append({
			"id": String(cfg["id"]),
			"order": order,
			"spawn": int(cfg["spawn"]),
			"region": String(cfg["region"]),
			"kind": String(cfg["kind"]),
			"path": path,
			"path_index": 0,
			"cell": int(cfg["spawn"]),
			"active": true,
			"room": room,
			"room_path": "" if room == null else room.resource_path,
			"title": "巡逻怪" if room == null else String(room.name),
		})
	return out


# 下一步预告：路径下一格。纯只读，不改变任何状态。
static func preview_cell(patrol: Dictionary) -> int:
	var path: Array = patrol["path"]
	if path.is_empty():
		return int(patrol["cell"])
	return int(path[(int(patrol["path_index"]) + 1) % path.size()])


# 前进一格并返回新位置。
static func step(patrol: Dictionary) -> int:
	var path: Array = patrol["path"]
	if path.is_empty():
		return int(patrol["cell"])
	patrol["path_index"] = (int(patrol["path_index"]) + 1) % path.size()
	patrol["cell"] = int(path[int(patrol["path_index"])])
	return int(patrol["cell"])


static func validate(grid: Dictionary) -> Array:
	var errs: Array = []
	var cells: Array = grid.get("cells", [])
	if cells.is_empty():
		return ["地图数据为空"]
	var start_id: int = int(grid.get("start_id", -1))
	var boss_id: int = int(grid.get("boss_id", -1))
	var spawns: Array = grid.get("patrol_spawns", [])

	if PATROLS.size() != spawns.size():
		errs.append("巡逻数量 %d 与 PATROL_SPAWNS %d 不一致" % [PATROLS.size(), spawns.size()])

	var region_count := {"A": 0, "C": 0, "B": 0}
	var seen_ids: Dictionary = {}
	for i in range(PATROLS.size()):
		var cfg: Dictionary = PATROLS[i]
		var pid: String = String(cfg["id"])
		var path: Array = cfg["path"]
		if seen_ids.has(pid):
			errs.append("巡逻 id 重复：%s" % pid)
		seen_ids[pid] = true
		if int(cfg["order"]) != i:
			errs.append("%s 的 order 不是 %d（行动顺序不固定）" % [pid, i])
		if path.size() < MIN_PATH:
			errs.append("%s 路径少于 %d 格" % [pid, MIN_PATH])
		if path.is_empty() or int(path[0]) != int(cfg["spawn"]):
			errs.append("%s 路径首格不是冻结起点" % pid)
			continue
		if int(cfg["spawn"]) not in spawns:
			errs.append("%s 起点不在 PATROL_SPAWNS 内" % pid)

		var uniq: Dictionary = {}
		for raw in path:
			var cid: int = int(raw)
			if cid < 0 or cid >= cells.size():
				errs.append("%s 路径格 %d 越界" % [pid, cid])
				continue
			if uniq.has(cid):
				errs.append("%s 路径重复格 %d（非简单环）" % [pid, cid])
			uniq[cid] = true
			if not bool(cells[cid]["walkable"]):
				errs.append("%s 路径格 %d 不可行走（穿墙）" % [pid, cid])
			if cid == start_id:
				errs.append("%s 路径经过起点格 %d" % [pid, cid])
			if cid == boss_id:
				errs.append("%s 路径经过 BOSS 格 %d（会永久堵门）" % [pid, cid])
			if grid.get("doors", []).has(cid):
				errs.append("%s 路径经过区域门 %d（会临时堵门）" % [pid, cid])
			var region: String = String(cells[cid]["region"])
			if region != String(cfg["region"]):
				errs.append("%s 路径格 %d 落在区域 %s，与登记 %s 不符" % [pid, cid, region, cfg["region"]])

		for j in range(path.size()):
			var a: int = int(path[j])
			var b: int = int(path[(j + 1) % path.size()])
			if not MAP_GRID.neighbors(grid, a).has(b):
				errs.append("%s 路径 %d→%d 不相邻（含回环）" % [pid, a, b])

		var spawn_region: String = String(cells[int(cfg["spawn"])]["region"])
		region_count[spawn_region] = int(region_count.get(spawn_region, 0)) + 1
		if spawn_region != String(cfg["region"]):
			errs.append("%s 起点区域 %s 与登记 %s 不符" % [pid, spawn_region, cfg["region"]])

	if int(region_count.get("A", 0)) != 1:
		errs.append("入口区 A 巡逻不是 1 只（%d）" % int(region_count.get("A", 0)))
	if int(region_count.get("C", 0)) > 2:
		errs.append("深层区 C 巡逻超过 2 只（%d）" % int(region_count.get("C", 0)))
	if int(region_count.get("B", 0)) != 0:
		errs.append("交汇区 B 不应有巡逻起点（%d）" % int(region_count.get("B", 0)))
	return errs


# 确定性房间绑定：先按「有护甲优先」再按 resource_path 排序，取 order % size。
# 有甲优先的理由：破甲陷阱（Step 4）只对有护甲的怪有意义，act1 的 12 个 normal 房里
# 只有 3 个带甲，若按纯字典序会选到护甲 0 的怪，陷阱变成 0→0 的空机制。
static func _pick_room(ctrl, act: int, order: int) -> RoomData:
	if ctrl == null:
		return null
	var arr: Array = []
	for room in ctrl.ALL_ROOMS:
		if room == null or int(room.act) != act:
			continue
		if bool(room.final_boss):
			continue
		if String(room.kind) != "normal":
			continue
		arr.append(room)
	arr.sort_custom(func(a: RoomData, b: RoomData) -> bool:
		var ha: bool = armor_of(a) > 0
		var hb: bool = armor_of(b) > 0
		if ha != hb:
			return ha
		return String(a.resource_path) < String(b.resource_path))
	if arr.is_empty():
		return null
	return arr[order % arr.size()]


# 与 duel_controller 一致的基础护甲口径：RoomData.armor 优先，否则取行为族基准。
# 唯一实现在 MapTrap，这里只做转发，避免两套护甲口径漂移。
static func armor_of(room: RoomData) -> int:
	return MAP_TRAP.armor_of(room)
