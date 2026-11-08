extends RefCounted

# ============================================================================
# BoardGenerator — ACT1 固定拓扑 + 房间/物品分配（M2 灰盒）
# 规格：docs/棋盘探索_战后成长与局外生涯_制作执行方案.md §6、§7.1、§10.1
#
# 三套固定骨架（共享骨架 + 两段岔路 + 四个 BOSS 结局），每局随机抽一套：
#   standard   25 节点 / 13 格 / 尾路 3 格（普通 → 休整 → BOSS）
#   long_tail  29 节点 / 14 格 / 尾路 4 格（普通 → 休整 → 商店 → BOSS，BOSS 前花钱）
#   long_share 26 节点 / 14 格 / 共享段 8 格（额外商店）→ 中段/尾路整体后移 1 格
#
# 三套骨架的单局路径都是 8 场战斗（7 战 + BOSS），尾路第一格战斗、第二格保底营地：
#   standard  ：起点 → 普通 → 武器 → 普通 → 精英 → 护符 → 普通 → 岔路 A
#      上路：普通 → 精英 → 商店 ─ 岔路 B ─┬─ 普通 → 营地 → BOSS（结局 1）
#                                         └─ 普通 → 营地 → BOSS（结局 2）
#      下路：普通 → 精英 → 休整 ─ 岔路 B ─┬─ 普通 → 营地 → BOSS（结局 3）
#                                         └─ 普通 → 营地 → BOSS（结局 4）
#   long_tail ：骨架与中段同上；四条尾路统一为 普通 → 营地 → 商店 → BOSS。
#   long_share：共享段在护符后多一格商店（n29），岔路 A / B 各后移 1 格，尾路仍 3 格。
#
# 一局只走一条尾路、只打一个 BOSS；另外三个 BOSS 留在图上未结算。
# 4 个 ACT1 BOSS 每局随机分配到四条尾路，岔路提示里如实展示，保证选择有信息。
# 三套骨架都保持「BOSS 前营地」；多出的格只给商店（只提供消费机会，不发奖励/不加战斗）。
#
# G4 主题分布：尾路主题 = 该尾路 BOSS 元素，首战优先同元素；
# 共享段/中段相邻战斗不同元素，同一条路径的两个精英不同元素（只选房，不改数值）。
#
# 只随机骨架、类型分配、具体房间与物品，不改战斗数值 / 掉落 / 存档。
# 输出 Dictionary：
#   {nodes:Array, by_id:Dictionary, battle_rooms:Array[RoomData], start_id:String,
#    boss_ids:Array, boss_depth:int, template_id:String, shape_id:String, layout:Dictionary}
# battle_rooms 按固定顺序排列，节点 battle_index 即其在 battle_rooms 中的下标。
# ============================================================================

const NODE = preload("res://scripts/board/board_node_data.gd")

# [id, type, depth, row]；depth = 列号，岔路两侧同深度；row = 0..4 对应 ROW_Y。
# 标准骨架（25 节点 / 13 格）——G4 之前的唯一形状，保持坐标不变。
const TOPOLOGY := [
	["n0", "start", 0, 2],
	["n1", "normal", 1, 2],
	["n2", "weapon", 2, 2],
	["n3", "normal", 3, 2],
	["n4", "elite", 4, 2],
	["n5", "charm", 5, 2],
	["n6", "normal", 6, 2],
	["n7", "normal", 7, 1],
	["n8", "elite", 8, 1],
	["n9", "shop", 9, 1],
	["n10", "normal", 7, 3],
	["n11", "elite", 8, 3],
	["n12", "rest", 9, 3],
	["n13", "normal", 10, 0],
	["n21", "rest", 11, 0],
	["n14", "boss", 12, 0],
	["n15", "normal", 10, 1],
	["n22", "rest", 11, 1],
	["n16", "boss", 12, 1],
	["n17", "normal", 10, 3],
	["n23", "rest", 11, 3],
	["n18", "boss", 12, 3],
	["n19", "normal", 10, 4],
	["n24", "rest", 11, 4],
	["n20", "boss", 12, 4],
]

# 长尾骨架（29 节点 / 14 格）：n25–n28 是尾路商店，BOSS 顺延到第 13 列。
const LONG_TOPOLOGY := [
	["n0", "start", 0, 2],
	["n1", "normal", 1, 2],
	["n2", "weapon", 2, 2],
	["n3", "normal", 3, 2],
	["n4", "elite", 4, 2],
	["n5", "charm", 5, 2],
	["n6", "normal", 6, 2],
	["n7", "normal", 7, 1],
	["n8", "elite", 8, 1],
	["n9", "shop", 9, 1],
	["n10", "normal", 7, 3],
	["n11", "elite", 8, 3],
	["n12", "rest", 9, 3],
	["n13", "normal", 10, 0],
	["n21", "rest", 11, 0],
	["n25", "shop", 12, 0],
	["n14", "boss", 13, 0],
	["n15", "normal", 10, 1],
	["n22", "rest", 11, 1],
	["n26", "shop", 12, 1],
	["n16", "boss", 13, 1],
	["n17", "normal", 10, 3],
	["n23", "rest", 11, 3],
	["n27", "shop", 12, 3],
	["n18", "boss", 13, 3],
	["n19", "normal", 10, 4],
	["n24", "rest", 11, 4],
	["n28", "shop", 12, 4],
	["n20", "boss", 13, 4],
]

# 延展共享段骨架（26 节点 / 14 格）：n29 是护符后的第二间商店，岔路 A/B 与尾路整体后移 1 格。
# 尾路仍 3 格（普通 → 营地 → BOSS），单局仍是 8 战 / 4 BOSS / 1 武器 / 1 护符。
const SHARE_TOPOLOGY := [
	["n0", "start", 0, 2],
	["n1", "normal", 1, 2],
	["n2", "weapon", 2, 2],
	["n3", "normal", 3, 2],
	["n4", "elite", 4, 2],
	["n5", "charm", 5, 2],
	["n29", "shop", 6, 2],
	["n6", "normal", 7, 2],
	["n7", "normal", 8, 1],
	["n8", "elite", 9, 1],
	["n9", "shop", 10, 1],
	["n10", "normal", 8, 3],
	["n11", "elite", 9, 3],
	["n12", "rest", 10, 3],
	["n13", "normal", 11, 0],
	["n21", "rest", 12, 0],
	["n14", "boss", 13, 0],
	["n15", "normal", 11, 1],
	["n22", "rest", 12, 1],
	["n16", "boss", 13, 1],
	["n17", "normal", 11, 3],
	["n23", "rest", 12, 3],
	["n18", "boss", 13, 3],
	["n19", "normal", 11, 4],
	["n24", "rest", 12, 4],
	["n20", "boss", 13, 4],
]

# G4-01 分支价值模板：不改变骨架 / 深度 / 边，只换节点类型分配。
# 标准骨架满足：25 节点 / 13 格 / 8 战 / 4 BOSS / 商店与休整同深度互斥。
# 5 套（计划要求 4–6）：精英可两侧都前置，也可只前置一侧，形成非对称风险取舍。
# 只允许在「本就在 BATTLE_ORDER 里的战斗节点」之间换精英/普通，避免单局战斗数变化。
const TEMPLATES := [
	{"id": "standard", "overrides": {}},
	{"id": "mirror", "overrides": {"n2": "charm", "n5": "weapon", "n9": "rest", "n12": "shop"}},
	{"id": "elite_first", "overrides": {"n7": "elite", "n8": "normal", "n10": "elite", "n11": "normal"}},
	{"id": "elite_upper", "overrides": {"n7": "elite", "n8": "normal"}},
	{"id": "elite_lower", "overrides": {"n10": "elite", "n11": "normal"}},
]

# 五条横向车道：尾路 0 / 尾路 1（与上路同排）/ 共享骨架 / 尾路 2（与下路同排）/ 尾路 3。
const ROW_Y := [24.0, 58.0, 92.0, 126.0, 160.0]

const EDGES := {
	"n0": ["n1"],
	"n1": ["n2"],
	"n2": ["n3"],
	"n3": ["n4"],
	"n4": ["n5"],
	"n5": ["n6"],
	"n6": ["n7", "n10"],
	"n7": ["n8"],
	"n8": ["n9"],
	"n9": ["n13", "n15"],
	"n10": ["n11"],
	"n11": ["n12"],
	"n12": ["n17", "n19"],
	"n13": ["n21"],
	"n21": ["n14"],
	"n14": [],
	"n15": ["n22"],
	"n22": ["n16"],
	"n16": [],
	"n17": ["n23"],
	"n23": ["n18"],
	"n18": [],
	"n19": ["n24"],
	"n24": ["n20"],
	"n20": [],
}

const LONG_EDGES := {
	"n0": ["n1"],
	"n1": ["n2"],
	"n2": ["n3"],
	"n3": ["n4"],
	"n4": ["n5"],
	"n5": ["n6"],
	"n6": ["n7", "n10"],
	"n7": ["n8"],
	"n8": ["n9"],
	"n9": ["n13", "n15"],
	"n10": ["n11"],
	"n11": ["n12"],
	"n12": ["n17", "n19"],
	"n13": ["n21"],
	"n21": ["n25"],
	"n25": ["n14"],
	"n14": [],
	"n15": ["n22"],
	"n22": ["n26"],
	"n26": ["n16"],
	"n16": [],
	"n17": ["n23"],
	"n23": ["n27"],
	"n27": ["n18"],
	"n18": [],
	"n19": ["n24"],
	"n24": ["n28"],
	"n28": ["n20"],
	"n20": [],
}

const SHARE_EDGES := {
	"n0": ["n1"],
	"n1": ["n2"],
	"n2": ["n3"],
	"n3": ["n4"],
	"n4": ["n5"],
	"n5": ["n29"],
	"n29": ["n6"],
	"n6": ["n7", "n10"],
	"n7": ["n8"],
	"n8": ["n9"],
	"n9": ["n13", "n15"],
	"n10": ["n11"],
	"n11": ["n12"],
	"n12": ["n17", "n19"],
	"n13": ["n21"],
	"n21": ["n14"],
	"n14": [],
	"n15": ["n22"],
	"n22": ["n16"],
	"n16": [],
	"n17": ["n23"],
	"n23": ["n18"],
	"n18": [],
	"n19": ["n24"],
	"n24": ["n20"],
	"n20": [],
}

# G4-02 骨架随机：列宽按 480px 内排布（x = x0 + depth·dx，节点宽 node_w）。
const SHAPES := [
	{"id": "standard", "topology": TOPOLOGY, "edges": EDGES,
		"x0": 6.0, "dx": 36.0, "node_w": 34.0, "boss_depth": 12, "tail_battle_depth": 10},
	{"id": "long_tail", "topology": LONG_TOPOLOGY, "edges": LONG_EDGES,
		"x0": 4.0, "dx": 34.0, "node_w": 30.0, "boss_depth": 13, "tail_battle_depth": 10},
	{"id": "long_share", "topology": SHARE_TOPOLOGY, "edges": SHARE_EDGES,
		"x0": 4.0, "dx": 34.0, "node_w": 30.0, "boss_depth": 13, "tail_battle_depth": 11},
]

# 战斗节点按固定路径推进顺序（决定 battle_rooms 顺序）；ria 按本骨架的战斗深度顺序查表。
const BATTLE_ORDER := [
	"n1", "n3", "n4", "n6",
	"n7", "n8", "n10", "n11",
	"n13", "n15", "n17", "n19",
	"n14", "n16", "n18", "n20",
]

# 战斗深度 → 幕内位置（ria）。每套骨架按自己的战斗深度排序编码 0..6，
# 因此标准 / 长尾共享段不变，延展共享段骨架整体后移仍得到同一组 ria（不改难度曲线）。
# 1,3,4,6 共享段；7,8 中段；10 尾段（长尾的尾路商店 / BOSS 不参与此表）。

var _ctrl


func _init(ctrl) -> void:
	_ctrl = ctrl


func generate(act: int, cfg) -> Dictionary:
	var shape: Dictionary = _pick_shape(cfg)
	var tpl: Dictionary = _pick_template(cfg)
	var overrides: Dictionary = tpl.get("overrides", {})
	var topology: Array = shape["topology"]
	var edges: Dictionary = shape["edges"]
	var nodes: Array = []
	var by_id := {}
	for spec in topology:
		var id := String(spec[0])
		var type := String(spec[1])
		if overrides.has(id):
			type = String(overrides[id])
		var n: Dictionary = NODE.make(id, type, int(spec[2]))
		n["act"] = act
		n["row"] = int(spec[3])
		n["next"] = (edges[id] as Array).duplicate()
		nodes.append(n)
		by_id[id] = n

	# G4-04：每张棋盘 1 个特殊格（宝箱 / 神龛 / 武器藏库），替换一条尾路的普通战斗（节点总数不变）。
	_assign_special(cfg, nodes, shape)
	var combat_depths: Array = _combat_depths(topology, overrides)

	var pools := _room_pools(act)
	var used_rooms := {}   # G4-02：同一张棋盘内战斗房不重复（含 BOSS）
	# G4 主题分布：先定 BOSS（尾路主题来源），再定尾路首战（优先同元素），最后共享段/中段。
	_assign_bosses(by_id, pools, act, used_rooms)
	_assign_battle_rooms(by_id, pools, act, used_rooms)

	var battle_rooms: Array[RoomData] = []
	for id in BATTLE_ORDER:
		var n: Dictionary = by_id[id]
		var type := String(n["type"])
		if not NODE.is_battle(type):
			continue   # 该格已被特殊格替换，不再分配 RoomData
		var room: RoomData = n.get("room")
		if room == null:
			continue
		n["battle_index"] = battle_rooms.size()
		var depth: int = int(n["depth"])
		if type == "boss":
			n["ria"] = int(cfg.boss_ria)
			n["final"] = true
		else:
			n["ria"] = maxi(0, combat_depths.find(depth))
		n["title"] = room.name
		n["desc"] = _room_desc(room, type)
		battle_rooms.append(room)

	# 尾路主题写回节点文案（普通首战前置说明；特殊格只记录 theme，不覆盖自身文案）
	_apply_tail_themes(by_id)

	_assign_weapon(_node_of_type(by_id, "weapon"))
	_assign_charm(_node_of_type(by_id, "charm"))
	by_id["n0"]["title"] = "起点"
	by_id["n0"]["desc"] = NODE.hint("start")
	# 所有商店 / 休整节点都写标题：长尾 / 延展共享段一局有多个商店与休整，
	# 不能只给第一个写，否则后段节点会回退成类型名。
	# 尾路营地按固定 id 判定（n21–n24），不能按深度阈值——延展共享段的中段休整会落到深度 10。
	for n in nodes:
		var t := String(n["type"])
		if t == "shop":
			n["title"] = "商店"
			n["desc"] = NODE.hint("shop")
		elif t == "rest":
			if String(n["id"]) in ["n21", "n22", "n23", "n24"]:
				n["title"] = "营地"
				n["desc"] = "恢复 25% 最大 HP · 可购买 1 件补给"
			else:
				n["title"] = "休整"
				n["desc"] = NODE.hint("rest")
	# 岔路提示：把下游两条尾路的 BOSS 写在岔路节点上（选择前可见）。
	_set_fork_desc(by_id, "n6")
	_set_fork_desc(by_id, "n9")
	_set_fork_desc(by_id, "n12")

	var boss_ids: Array[String] = []
	for n in nodes:
		if String(n["type"]) == "boss":
			boss_ids.append(String(n["id"]))

	return {
		"nodes": nodes,
		"by_id": by_id,
		"battle_rooms": battle_rooms,
		"start_id": "n0",
		"boss_ids": boss_ids,
		"boss_depth": int(shape["boss_depth"]),
		"template_id": String(tpl["id"]),
		"shape_id": String(shape["id"]),
		"layout": {
			"x0": float(shape["x0"]),
			"dx": float(shape["dx"]),
			"node_w": float(shape["node_w"]),
			"row_y": ROW_Y,
		},
	}


# G4-02：骨架随机（默认）；BoardConfig.shape_id 非空时用于测试 / 调试固定形状。
func _pick_shape(cfg) -> Dictionary:
	var want := ""
	if cfg != null and "shape_id" in cfg:
		want = String(cfg.shape_id)
	if want != "":
		for s in SHAPES:
			if String(s["id"]) == want:
				return s
	return SHAPES[randi() % SHAPES.size()]


# G4-01：模板随机（默认）；BoardConfig.template_id 非空时用于测试 / 调试 / 采集固定模板。
func _pick_template(cfg) -> Dictionary:
	var want := ""
	if cfg != null and "template_id" in cfg:
		want = String(cfg.template_id)
	if want != "":
		for t in TEMPLATES:
			if String(t["id"]) == want:
				return t
	return TEMPLATES[randi() % TEMPLATES.size()]


# 按类型找唯一节点（模板换位后不再依赖固定 id）
func _node_of_type(by_id: Dictionary, type: String) -> Dictionary:
	for id in by_id:
		if String(by_id[id].get("type", "")) == type:
			return by_id[id]
	return {}


# 本骨架的战斗深度（去重升序）：模板只在战斗节点之间换精英/普通，不改变这个集合。
func _combat_depths(topology: Array, overrides: Dictionary) -> Array:
	var depths: Array = []
	for spec in topology:
		var id := String(spec[0])
		var type := String(spec[1])
		if overrides.has(id):
			type = String(overrides[id])
		if type == "normal" or type == "elite":
			var d := int(spec[2])
			if not d in depths:
				depths.append(d)
	depths.sort()
	return depths


# ---------------------------------------------------------------------------
# G4-04 特殊格：每张棋盘 1 个（宝箱 / 神龛 / 武器藏库），替换一条尾路的普通战斗。
# 节点总数不变；该尾路少一场战斗、多一个特殊格，作为「少打一仗换确定收益」的取舍。
# BoardConfig.special_id 非空时用于测试/调试固定类型（"treasure" / "shrine" / "armory"）。
# ---------------------------------------------------------------------------

const SPECIALS := ["treasure", "shrine", "armory"]


func _assign_special(cfg, nodes: Array, shape: Dictionary = {}) -> void:
	var tail_depth: int = int(shape.get("tail_battle_depth", 10))
	var tails: Array = []
	for n in nodes:
		if String(n["type"]) == "normal" and int(n["depth"]) == tail_depth:
			tails.append(n)
	if tails.is_empty():
		return
	var t: Dictionary = tails[randi() % tails.size()]
	var kind := ""
	if cfg != null and "special_id" in cfg:
		kind = String(cfg.special_id)
	if not kind in SPECIALS:
		kind = String(SPECIALS[randi() % SPECIALS.size()])
	if kind == "shrine":
		_assign_shrine(t)
	elif kind == "armory":
		_assign_armory(t)
	else:
		_assign_treasure(t)


# 宝箱：类别（武器 / 护符 / 消耗品 / 金币）与具体物品在生成时冻结，节点只公开类别。
func _assign_treasure(t: Dictionary) -> void:
	t["type"] = "treasure"
	t["icon"] = NODE.icon("treasure")
	var kinds := ["weapon", "charm", "active"]
	var kind := String(kinds[randi() % kinds.size()])
	var path := ""
	match kind:
		"weapon":
			path = String(_ctrl._reward_system.pick_reward_weapon_path())
		"charm":
			path = _pick_charm_path()
		_:
			path = _pick_active_path()
	if path == "":
		kind = "gold"
	t["treasure_kind"] = kind
	t["item_path"] = path
	t["title"] = "宝箱"
	t["desc"] = _treasure_desc(kind, path)


# 神龛：效果在生成时冻结并公开；数值沿用既有奖励效果（35% 回复 / +12 上限 / +15 护盾）。
func _assign_shrine(t: Dictionary) -> void:
	t["type"] = "shrine"
	t["icon"] = NODE.icon("shrine")
	var kinds := ["heal", "maxhp", "ward"]
	var kind := String(kinds[randi() % kinds.size()])
	t["title"] = "神龛"
	t["shrine_kind"] = kind
	match kind:
		"heal":
			t["shrine_value"] = 35
			t["desc"] = "神龛 · 恢复 35% 最大 HP（落地生效）"
		"maxhp":
			t["shrine_value"] = 12
			t["desc"] = "神龛 · 最大 HP +12 并恢复 20%（落地生效）"
		_:
			t["shrine_value"] = 15
			t["desc"] = "神龛 · 下一场战斗开局 +15 护盾（落地生效）"


func _treasure_desc(kind: String, path: String) -> String:
	if path == "":
		return "宝箱 · 金币（开启时结算）"
	var label: String = {"weapon": "武器", "charm": "护符", "active": "消耗品"}.get(kind, "奖励")
	return "宝箱 · %s（具体物品开启时揭晓）" % label


# 武器藏库：两把可见武器在生成时冻结，节点直接公开名字；落地二选一（或跳过）。
func _assign_armory(t: Dictionary) -> void:
	t["type"] = "armory"
	t["icon"] = NODE.icon("armory")
	t["title"] = "武器藏库"
	var paths := _pick_armory_paths()
	t["armory_paths"] = paths
	if paths.is_empty():
		t["desc"] = "武器藏库 · 已空（落地折算金币 +15）"
		return
	var names: Array[String] = []
	for p in paths:
		names.append(_weapon_brief(String(p)))
	if paths.size() >= 2:
		t["desc"] = "武器藏库 · 二选一：%s（落地自选一把）" % " / ".join(names)
	else:
		t["desc"] = "武器藏库 · 仅此一把：%s（落地自选）" % names[0]


# 两把互不重复、且当前装配未持有的武器；池不足时返回能凑到的数量。
func _pick_armory_paths() -> Array:
	var out: Array = []
	for i in 2:
		var cand: Array = []
		for p in _ctrl.WEAPON_POOL:
			var s := String(p)
			if _ctrl.selected_loadout.has(p) or s in out:
				continue
			cand.append(s)
		if cand.is_empty():
			break
		out.append(String(_ctrl._reward_system.acq_weighted_pick(cand)))
	return out


func _weapon_brief(path: String) -> String:
	var wd: WeaponData = load(path)
	if wd == null:
		return path.get_file().get_basename()
	return String(wd.weapon_name)


func _pick_charm_path() -> String:
	var relics: Array = _ctrl._reward_system.relic_paths()
	var cand: Array = []
	for p in _ctrl.ITEM_POOL:
		if p in relics:
			continue
		var res: Resource = load(p)
		if res != null and String(res.get("category")) == "passive":
			cand.append(p)
	if cand.is_empty():
		return ""
	return String(_ctrl._reward_system.acq_weighted_pick(cand))


func _pick_active_path() -> String:
	var cand: Array = []
	for p in _ctrl.ITEM_POOL:
		var res: Resource = load(p)
		if res != null and String(res.get("category")) == "active":
			cand.append(p)
	if cand.is_empty():
		return ""
	return String(_ctrl._reward_system.acq_weighted_pick(cand))


# ---------------------------------------------------------------------------
# 岔路说明
# ---------------------------------------------------------------------------

func _set_fork_desc(by_id: Dictionary, id: String) -> void:
	var n: Dictionary = by_id.get(id, {})
	if n.is_empty():
		return
	var lines: Array[String] = [NODE.hint(String(n["type"]))]
	for nx in n.get("next", []):
		var bosses := _bosses_under(by_id, String(nx))
		var names: Array[String] = []
		for b in bosses:
			names.append(_boss_brief(b))
		if not names.is_empty():
			var special := _special_under(by_id, String(nx))
			var extra := (" · " + special) if special != "" else ""
			lines.append("%s：%s%s" % [_side_label(id, String(nx)), " / ".join(names), extra])
	n["desc"] = "\n".join(lines)


# 分支下游的特殊格标签（宝箱 / 神龛 / 武器藏库）；没有则返回空串。
func _special_under(by_id: Dictionary, id: String) -> String:
	var stack: Array = [id]
	var seen := {}
	while not stack.is_empty():
		var cur := String(stack.pop_back())
		if seen.has(cur):
			continue
		seen[cur] = true
		var n: Dictionary = by_id.get(cur, {})
		var t := String(n.get("type", ""))
		if t == "treasure":
			return "宝箱"
		if t == "shrine":
			return "神龛"
		if t == "armory":
			return "武器藏库"
		for nx in n.get("next", []):
			stack.append(String(nx))
	return ""


func _side_label(fork_id: String, id: String) -> String:
	# 岔路 A 的两条中段支线：n7 一侧为上路，n10 一侧为下路。
	if fork_id == "n6":
		return "上路" if id in ["n7", "n8", "n9", "n13", "n15"] else "下路"
	# 尾路岔路：n13/n17 在上方，n15/n19 在下方。
	return "上方" if id in ["n13", "n17"] else "下方"


func _bosses_under(by_id: Dictionary, id: String) -> Array:
	var out: Array = []
	var stack: Array = [id]
	var seen := {}
	while not stack.is_empty():
		var cur := String(stack.pop_back())
		if seen.has(cur):
			continue
		seen[cur] = true
		var n: Dictionary = by_id.get(cur, {})
		if String(n.get("type", "")) == "boss":
			out.append(n)
			continue
		for nx in n.get("next", []):
			stack.append(String(nx))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["id"]) < String(b["id"]))
	return out


func _boss_brief(n: Dictionary) -> String:
	var r: RoomData = n.get("room")
	if r == null:
		return "BOSS"
	return "%s（%s）" % [r.name, ElementCounter.label(r.element)]


# ---------------------------------------------------------------------------
# G4 主题分布：BOSS 元素 → 尾路主题；尾路首战优先同元素；
# 共享段/中段避免相邻战斗同元素，同一条路径的两个精英不同元素。
# 只影响“选哪间房”，不改变房间数值、掉落、ria 或战斗规则。
# ---------------------------------------------------------------------------

# 尾路首战 → 该尾路的 BOSS（主题来源）。
const TAIL_PAIRS := [["n13", "n14"], ["n15", "n16"], ["n17", "n18"], ["n19", "n20"]]


func _assign_bosses(by_id: Dictionary, pools: Dictionary, act: int, used: Dictionary) -> void:
	for id in ["n14", "n16", "n18", "n20"]:
		var n: Dictionary = by_id[id]
		var room: RoomData = _take_room(pools, "boss", act, used)
		if room == null:
			continue
		n["room"] = room
		used[room.resource_path] = true


func _assign_battle_rooms(by_id: Dictionary, pools: Dictionary, act: int, used: Dictionary) -> void:
	# 1) 尾路首战：优先与 BOSS 同元素，形成尾路主题；先取可保证主题房不被前置节点占用。
	for pair in TAIL_PAIRS:
		var n: Dictionary = by_id[pair[0]]
		if not NODE.is_battle(String(n["type"])):
			continue
		var theme := _room_element(by_id[pair[1]])
		var room: RoomData = _take_room(pools, "normal", act, used, theme)
		if room != null:
			n["room"] = room
			used[room.resource_path] = true
	# 2) 共享段与中段：先定共享精英与两条支路的精英（同路径精英不同元素），
	#    再定它们之间的普通节点（避免与所有已定邻居同元素），最后补首段。
	#    约束顺序与路径顺序不同：先满足精英元素差异，普通节点再避开两侧。
	var upper_elite := _branch_elite_id(by_id, ["n7", "n8"])
	var lower_elite := _branch_elite_id(by_id, ["n10", "n11"])
	var upper_normal := "n8" if upper_elite == "n7" else "n7"
	var lower_normal := "n11" if lower_elite == "n10" else "n10"
	var neighbors := {
		"n1": ["n3"], "n3": ["n1", "n4"], "n4": ["n3", "n6"],
		"n6": ["n4", "n7", "n10"], "n7": ["n6", "n8"], "n8": ["n7"],
		"n10": ["n6", "n11"], "n11": ["n10"],
	}
	# 先精英后普通：支路精英必须避开共享精英；支路普通再避开精英，避免「普通占用了
	# 精英唯一可用的另一元素」导致精英被迫与邻居同元素。
	for id in ["n1", "n4", upper_elite, lower_elite, upper_normal, lower_normal, "n6", "n3"]:
		if id == "":
			continue
		var n: Dictionary = by_id[id]
		if not NODE.is_battle(String(n["type"])):
			continue
		var banned: Array = []
		for nb in neighbors.get(id, []):
			var e := _room_element(by_id[String(nb)])
			if e != "":
				banned.append(e)
		# 同一条路径的两个精英：支路精英必须与共享精英不同元素（n4 已先分配）。
		if id != "n4" and String(n["type"]) == "elite":
			var se := _room_element(by_id["n4"])
			if se != "":
				banned.append(se)
		var room: RoomData = _take_room(pools, String(n["type"]), act, used, "", banned)
		if room != null:
			n["room"] = room
			used[room.resource_path] = true


func _branch_elite_id(by_id: Dictionary, ids: Array) -> String:
	for id in ids:
		if String(by_id[id].get("type", "")) == "elite":
			return String(id)
	return ""


# 尾路首战的元素主题：与 BOSS 同元素；特殊格只写 theme，保留自身功能文案。
func _apply_tail_themes(by_id: Dictionary) -> void:
	for pair in TAIL_PAIRS:
		var n: Dictionary = by_id[pair[0]]
		var theme := _room_element(by_id[pair[1]])
		if theme == "":
			continue
		n["theme"] = theme
		if NODE.is_battle(String(n["type"])):
			n["desc"] = "主题：%s（与 BOSS 同系）\n%s" % [
				ElementCounter.label(theme), String(n.get("desc", ""))]


func _room_element(n: Dictionary) -> String:
	var r: RoomData = n.get("room")
	return String(r.element) if r != null else ""


# ---------------------------------------------------------------------------
# 房间分配
# ---------------------------------------------------------------------------

func _room_pools(act: int) -> Dictionary:
	var out := {"normal": [], "elite": [], "boss": [], "any": []}
	for r in _ctrl.ALL_ROOMS:
		if r == null or r.final_boss or int(r.act) != act:
			continue
		out["any"].append(r)
		if out.has(String(r.kind)):
			out[String(r.kind)].append(r)
	for k in ["normal", "elite", "boss", "any"]:
		(out[k] as Array).shuffle()
	return out


func _take_room(pools: Dictionary, type: String, act: int, used: Dictionary = {},
		preferred: String = "", banned: Array = []) -> RoomData:
	var arr: Array = pools.get(type, [])
	# 优先元素（尾路主题）→ 避开禁用元素（相邻战斗/同路径精英）→ 仅保证未用 → 兜底。
	if preferred != "":
		var i := _room_index(arr, used, preferred, banned)
		if i >= 0:
			return _take_at(arr, i)
	var j := _room_index(arr, used, "", banned)
	if j >= 0:
		return _take_at(arr, j)
	var k := _room_index(arr, used, "", [])
	if k >= 0:
		return _take_at(arr, k)
	# 池不足兜底：同幕任意非最终房；仍无则全量任意非最终房。绝不让战斗节点空置。
	var any: Array = pools.get("any", [])
	if not any.is_empty():
		return any.pop_back()
	for r in _ctrl.ALL_ROOMS:
		if r != null and not r.final_boss and int(r.act) == act:
			return r
	for r in _ctrl.ALL_ROOMS:
		if r != null and not r.final_boss:
			return r
	return null


# 从 arr 末尾向前找：未使用、可选要求元素、不在禁用元素内。
func _room_index(arr: Array, used: Dictionary, required: String, banned: Array) -> int:
	for i in range(arr.size() - 1, -1, -1):
		var r: RoomData = arr[i]
		if r == null or used.has(r.resource_path):
			continue
		var e := String(r.element)
		if required != "" and e != required:
			continue
		if e in banned:
			continue
		return i
	return -1


func _take_at(arr: Array, i: int) -> RoomData:
	var pick: RoomData = arr[i]
	arr.remove_at(i)
	return pick


func _room_desc(r: RoomData, type: String) -> String:
	var kind_txt: String = {"normal": "普通战斗", "elite": "精英战斗", "boss": "BOSS 战"}.get(type, "战斗")
	var bits: Array[String] = [kind_txt, ElementCounter.label(r.element)]
	if r.gimmick_script != null:
		var icon := String(r.gimmick_script.get_script_constant_map().get("ICON", ""))
		if icon != "":
			bits.append("机制 %s" % icon)
	# G4-03：精英公开奖励方向（保底护符），BOSS 公开专属战利品；普通房只说明进入成长。
	if type == "elite":
		bits.append("胜利后进入战后成长 · 保底护符")
	elif type == "boss":
		bits.append("专属战利品")
	else:
		bits.append("胜利后进入战后成长")
	return " · ".join(bits)


# ---------------------------------------------------------------------------
# 武器格 / 护符格（M2 基础授予；替换预览与图鉴来源记录留 M3）
# ---------------------------------------------------------------------------

func _assign_weapon(n: Dictionary) -> void:
	var path := String(_ctrl._reward_system.pick_reward_weapon_path())
	if path == "":
		for p in _ctrl.WEAPON_POOL:
			if not _ctrl.selected_loadout.has(p):
				path = String(p)
				break
	n["item_path"] = path
	if path == "":
		n["title"] = "武器（无可用候选）"
		n["desc"] = "落地折算金币 +15（武器池已空）"
		return
	var wd: WeaponData = load(path)
	if wd == null:
		n["title"] = "武器 · %s" % path.get_file().get_basename()
		n["desc"] = "落地直接获得"
		return
	n["title"] = "武器 · %s" % wd.weapon_name
	n["desc"] = "攻%d · %s · 命中%d%% · %s\n落地直接入槽；双武器满则替换" % [
		int(wd.base_power), String(wd.rarity), int(wd.hit_rate * 100.0), ElementCounter.label(wd.element)]


func _assign_charm(n: Dictionary) -> void:
	var path := _pick_charm_path()
	n["item_path"] = path
	if path == "":
		n["title"] = "护符（无可用候选）"
		n["desc"] = "落地折算金币 +15（护符池已空）"
		return
	var cd: ItemData = load(path)
	n["title"] = "护符 · %s" % (cd.item_name if cd != null else path.get_file().get_basename())
	var body := String(cd.description) if cd != null else ""
	n["desc"] = "%s\n落地入护符槽；满 3 折算金币" % body
