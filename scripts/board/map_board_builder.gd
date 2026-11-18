extends RefCounted

# ============================================================================
# MapBoardBuilder — 14×9 MapGrid → 新地图节点图（开发／AI 测试入口专用）
# 规格：docs/地图巡逻诱导_第一版预算与分步执行计划_2026-11-14.md
#       §6 Step 0.5 任务 1–4、§6 Step 1、§6 Step 2 任务 6、§6 Step 5A
#
# 边界（Step 0.5 / Step 2 阶段）：
# - 只做静态数据转换与冻结，不改产品默认入口、不收敛 board_system / board_screen / board_config、
#   不退役任何旧模型或旧测试（g7_run3_test / loot_explore_test / g8_loadout_layout_test 持续有效）；
# - BOSS 的 `final` 由 (act, total_acts) 配置驱动，不静态写死（Step 0.5 任务 1）；
# - 内容节点 `type` 取自 MapNodeTypes 注册表，禁止空类型（Step 0.5 任务 2）；
# - 探索字段按真实来源写入（Step 0.5 任务 3/4）；
# - 运行时状态（consumed / revealed / defeated）不写回 cell，由上层持有。
# ============================================================================

const NODE = preload("res://scripts/board/board_node_data.gd")
const MAP_GRID = preload("res://scripts/board/map_grid.gd")
const TYPES = preload("res://scripts/board/map_node_types.gd")
const PATROL = preload("res://scripts/board/map_patrol.gd")

# 节奏样板（沿用冻结的 ACT1 样板，避免首战手感漂移）。
const RHYTHM_SAMPLE := {
	1: {
		"elite": "res://resources/rooms/a1_elite_brute_ice.tres",
		"boss": "res://resources/rooms/frozen_urn.tres",
	},
}

# Step 0.5 任务 1：三幕封顶，不得推进 ACT IV。
const MAX_ACTS := 3

var _ctrl
var _rng := RandomNumberGenerator.new()


func _init(ctrl) -> void:
	_ctrl = ctrl


static func normalized_acts(acts: int) -> int:
	return clampi(acts, 1, MAX_ACTS)


# total_acts 来自 cfg.acts：决定哪一幕的 BOSS 才是本局最终战。
func build(act: int, seed_value: int, total_acts: int = 1) -> Dictionary:
	total_acts = normalized_acts(total_acts)
	var data: Dictionary = MAP_GRID.generate(seed_value, act)
	_rng.seed = seed_value
	var cells: Array = data["cells"]
	var contents: Dictionary = data["nodes"]
	var armory_cell: int = _first_treasure_cell(contents)
	var nodes: Array = []
	var by_id: Dictionary = {}
	for cell in cells:
		if not bool(cell["walkable"]):
			continue
		var cid: int = int(cell["id"])
		var id: String = "m%d" % cid
		var content: String = String(cell["content"])
		var type: String = TYPES.PATH
		if content != "":
			type = TYPES.content_to_type(content, cid, armory_cell)
		var n: Dictionary = NODE.make(id, TYPES.legacy_of(type) if TYPES.is_registered(type) else "normal", int(cell["col"]))
		n["type"] = type
		n["legacy_type"] = TYPES.legacy_of(type)
		n["row"] = int(cell["row"])
		n["col"] = int(cell["col"])
		n["cell_id"] = cid
		n["region"] = String(cell["region"])
		n["terrain"] = String(cell["terrain"])
		n["act"] = act
		n["next"] = []
		n["frozen"] = true
		n["revealed"] = true          # §3.4：位置始终公开
		n["visible"] = true
		n["distance"] = int(cell["row"]) + int(cell["col"])
		n["source"] = TYPES.source_of(type)
		if type == TYPES.PATH:
			n["icon"] = "·"
			n["title"] = "通路"
			n["desc"] = "可通行格，移动不结算"
		elif type == TYPES.START:
			n["icon"] = "🚩"
			n["title"] = "起点"
			n["desc"] = "本幕起点，无结算"
		else:
			n["icon"] = TYPES.icon_of(type)
			n["title"] = TYPES.label_of(type)
			n["desc"] = "%s · 来源 %s" % [TYPES.label_of(type), TYPES.source_of(type)]
		if contents.has(cid):
			n["variant"] = int(contents[cid]["variant"])
		# Step 0.5 任务 1：final 由幕数与当前幕决定，不静态写死。
		n["final"] = (type == "boss" and act >= total_acts)
		nodes.append(n)
		by_id[id] = n

	# 四方向邻接：坐标唯一来源是 MapGrid.neighbors()。
	for n in nodes:
		var ns: Array = []
		for nb in MAP_GRID.neighbors(data, int(n["cell_id"])):
			ns.append("m%d" % int(nb))
		n["next"] = ns

	_assign_rooms(nodes, act, total_acts)
	var used: Dictionary = {}
	for n in nodes:
		if TYPES.is_registered(String(n["type"])):
			TYPES.fill_explore_fields(n, _ctrl, act, _rng, used)
	var battle_rooms: Array = []
	for n in nodes:
		if not TYPES.is_battle(String(n["type"])):
			continue
		n["battle_index"] = battle_rooms.size()
		battle_rooms.append(n["room"])

	return {
		"nodes": nodes,
		"by_id": by_id,
		"start_id": "m%d" % int(data["start_id"]),
		"boss_id": "m%d" % int(data["boss_id"]),
		"battle_rooms": battle_rooms,
		"grid": data,
		# Step 3：巡逻初始状态（手写闭合环 + 确定性房间绑定），运行时按需启用。
		"patrols": PATROL.build(data, _ctrl, act),
		"cols": MAP_GRID.COLS,
		"rows": MAP_GRID.ROWS,
		"act": act,
		"total_acts": total_acts,
		"seed": seed_value,
	}


# ---------------------------------------------------------------------------
# 分岔路线图（经典 roguelike DAG）：替代 14×9 网格拓扑。
# 只换拓扑层；节点内容生成 / 房间分配 / 结算字段全部复用本文件既有辅助函数。
# 结构：7 层（起点 → 5 中间层 × 2-3 候选 → BOSS 汇聚），连线只连相邻层。
# ---------------------------------------------------------------------------

# 每层的候选类型池（经典风险收益节奏）。每层从中随机取 2-3 个不重复类型。
const BRANCH_LAYERS := {
	1: ["battle", "chest", "battle"],
	2: ["battle", "elite", "event"],
	3: ["shop", "armory", "event"],
	4: ["rest", "elite", "battle"],
	5: ["battle", "chest", "rest"],
}

const BOSS_LAYER := 6


# 生成一张分岔图。返回结构对齐 build()（board_system / map_runtime 消费者零改）。
func build_branch(act: int, seed_value: int, total_acts: int = 1) -> Dictionary:
	total_acts = normalized_acts(total_acts)
	_rng.seed = seed_value
	var nodes: Array = []
	var by_id: Dictionary = {}
	var layer_of: Dictionary = {}

	# 层0：起点
	var start := NODE.make("b0_0", TYPES.START, 0)
	start["act"] = act
	start["next"] = []
	start["frozen"] = true
	start["revealed"] = true
	start["visible"] = true
	start["distance"] = 0
	start["source"] = "start"
	start["icon"] = "🚩"
	start["title"] = "起点"
	start["desc"] = "本幕起点，无结算"
	nodes.append(start)
	by_id[start.id] = start
	layer_of[start.id] = 0

	# 层1-5：候选节点
	for layer in range(1, BOSS_LAYER):
		var pool: Array = BRANCH_LAYERS.get(layer, ["battle"]).duplicate()
		_shuffle(pool)
		var count: int = mini(3, pool.size())
		for i in range(count):
			var type: String = String(pool[i])
			var id: String = "b%d_%d" % [layer, i]
			var n := NODE.make(id, TYPES.legacy_of(type) if TYPES.is_registered(type) else "normal", layer)
			n["type"] = type
			n["legacy_type"] = TYPES.legacy_of(type)
			n["act"] = act
			n["next"] = []
			n["frozen"] = true
			n["revealed"] = true
			n["visible"] = true
			n["distance"] = layer
			n["source"] = TYPES.source_of(type)
			n["final"] = false
			n["icon"] = TYPES.icon_of(type)
			n["title"] = TYPES.label_of(type)
			n["desc"] = "%s · 来源 %s" % [TYPES.label_of(type), TYPES.source_of(type)]
			nodes.append(n)
			by_id[id] = n
			layer_of[id] = layer

	# 层6：BOSS 汇聚（4 选 1 随机，复用 controller 的 pick_boss）
	var boss_id: String = "b%d_0" % BOSS_LAYER
	var boss_node := NODE.make(boss_id, "boss", BOSS_LAYER)
	boss_node["type"] = "boss"
	boss_node["legacy_type"] = "boss"
	boss_node["act"] = act
	boss_node["next"] = []
	boss_node["frozen"] = true
	boss_node["revealed"] = true
	boss_node["visible"] = true
	boss_node["distance"] = BOSS_LAYER
	boss_node["source"] = "room"
	boss_node["final"] = (act >= total_acts)
	boss_node["icon"] = "👑"
	boss_node["title"] = "BOSS"
	boss_node["desc"] = "本幕首领（提前公开，可针对性构筑）"
	nodes.append(boss_node)
	by_id[boss_id] = boss_node
	layer_of[boss_id] = BOSS_LAYER

	# 第二遍：统一连边（此时所有层的节点都已存在）→ 每个节点连下一层全部候选，全连通无死路
	for n in nodes:
		var layer: int = int(layer_of[n.id])
		n["next"] = _ids_in_layer(layer_of, layer + 1) if layer < BOSS_LAYER else []

	_assign_rooms(nodes, act, total_acts)

	# BOSS 房间必须在 _assign_rooms 之后定：最后一幕强制 final_boss，否则 4 选 1 随机。
	# 这样"提前公开的 BOSS"由 pick_boss 决定，与线性模式同一套加权随机（总纲 §3.5）。
	if total_acts > 1 and act >= total_acts:
		var fin: RoomData = _final_room()
		if fin != null:
			boss_node["room"] = fin
			boss_node["title"] = String(fin.name)
	else:
		var candidates: Array = _pool(act, "boss")
		var picked: RoomData = _ctrl._pick_boss(candidates) if candidates.size() > 0 else _preferred_room(act, "boss")
		if picked != null:
			boss_node["room"] = picked
			boss_node["title"] = String(picked.name)
	boss_node["ria"] = 7

	var used: Dictionary = {}
	for n in nodes:
		if TYPES.is_registered(String(n["type"])):
			TYPES.fill_explore_fields(n, _ctrl, act, _rng, used)
	var battle_rooms: Array = []
	for n in nodes:
		if not TYPES.is_battle(String(n["type"])):
			continue
		n["battle_index"] = battle_rooms.size()
		battle_rooms.append(n["room"])

	return {
		"nodes": nodes,
		"by_id": by_id,
		"start_id": start.id,
		"boss_id": boss_id,
		"battle_rooms": battle_rooms,
		"grid": {},              # 分岔图无网格；消费者若读 grid 只会拿到空
		"patrols": [],           # 分岔图无巡逻怪
		"branch": true,          # 标记新拓扑，供 runtime / screen 判定
		"cols": BRANCH_LAYERS.size(),
		"rows": BOSS_LAYER + 1,
		"act": act,
		"total_acts": total_acts,
		"seed": seed_value,
	}


# 取某一层的所有节点 id（按插入顺序）。
static func _ids_in_layer(layer_of: Dictionary, layer: int) -> Array:
	var out: Array = []
	for id in layer_of:
		if int(layer_of[id]) == layer:
			out.append(id)
	return out


# 4 个 treasure 中固定 cell_id 最小者为武器藏库（布局稳定，不随 seed 漂移）。
func _first_treasure_cell(contents: Dictionary) -> int:
	var best := -1
	for cid in contents:
		if String(contents[cid]["type"]) == "treasure" and (best < 0 or int(cid) < best):
			best = int(cid)
	return best


# ---------------------------------------------------------------------------
# 战斗房冻结：只从现有 resources/rooms/ 池取，不新增平行目录。
# ---------------------------------------------------------------------------

func _assign_rooms(nodes: Array, act: int, total_acts: int = 1) -> void:
	var used: Dictionary = {}
	for n in nodes:
		var t: String = String(n["type"])
		if t != "boss" and t != "elite":
			continue
		# 最后一幕的 BOSS 必须是真·最终房（勇者的阴影），由 (act, total_acts) 决定。
		if t == "boss" and total_acts > 1 and act >= total_acts:
			var fin: RoomData = _final_room()
			if fin != null:
				n["room"] = fin
				n["ria"] = 7
				n["title"] = String(fin.name)
				used[fin.resource_path] = true
				continue
		var room: RoomData = _preferred_room(act, t)
		if room == null:
			room = _take(_pool(act, t), used)
		if room == null:
			push_error("MapBoardBuilder: ACT%d %s 池为空" % [act, t])
			continue
		n["room"] = room
		n["ria"] = 7 if t == "boss" else mini(6, int(n["distance"]))
		n["title"] = String(room.name)
		used[room.resource_path] = true

	# 普通战：按距离排序，前 3 个优先带 trait 的样板房。
	var pool: Array = _pool(act, "normal")
	var sample: Array = []
	var plain: Array = []
	for r in pool:
		if r.gimmick_script != null and String(r.gimmick_params.get("trait", "")) != "":
			sample.append(r)
		else:
			plain.append(r)
	var ordered: Array = []
	for i in mini(3, sample.size()):
		ordered.append(sample[i])
	ordered.append_array(plain)
	for r in sample:
		if not ordered.has(r):
			ordered.append(r)
	var targets: Array = []
	for n in nodes:
		if String(n["type"]) == "battle":
			targets.append(n)
	targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["distance"]) != int(b["distance"]):
			return int(a["distance"]) < int(b["distance"])
		return String(a["id"]) < String(b["id"]))
	for n in targets:
		var room: RoomData = _take(ordered, used)
		if room == null:
			push_error("MapBoardBuilder: ACT%d 普通房池为空" % act)
			continue
		n["room"] = room
		n["ria"] = mini(6, int(n["distance"]))
		n["title"] = String(room.name)
		used[room.resource_path] = true


# 真·最终房（勇者的阴影）：独立于候选池，只在最后一幕的 BOSS 上使用。
func _final_room() -> RoomData:
	for room in _ctrl.ALL_ROOMS:
		if room != null and bool(room.final_boss):
			return room
	return null


func _pool(act: int, kind: String) -> Array:
	var arr: Array = []
	for room in _ctrl.ALL_ROOMS:
		if room == null or int(room.act) != act:
			continue
		if bool(room.final_boss):
			continue
		if String(room.kind) == kind:
			arr.append(room)
	_shuffle(arr)
	return arr


# 池耗尽时允许复用首项：每幕 normal 池恰好 12 个，去重后可能不足；复用仍由 seed 决定。
func _take(arr: Array, used: Dictionary) -> RoomData:
	for room in arr:
		if not used.has(room.resource_path):
			return room
	if not arr.is_empty():
		return arr[0]
	return null


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = _rng.randi() % (i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _preferred_room(act: int, kind: String) -> RoomData:
	var sample: Dictionary = RHYTHM_SAMPLE.get(act, {})
	var path: String = String(sample.get(kind, ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var room: RoomData = load(path)
	if room == null or String(room.kind) != kind or int(room.act) != act:
		return null
	return room
