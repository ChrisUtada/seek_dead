extends RefCounted

# ============================================================================
# BoardGrid — 扫雷装备探索棋盘 · Step 1 固定 4×4 内容灰盒（2026-11-10）
# 规格：docs/扫雷装备探索_棋盘重设计与执行计划_2026-11-10.md §4、§5、§12 Step 1
#
# 本文件只负责「16 格内容与位置」：
# - 固定 4×4 人工验证模板（Step 7 起 3 套按 seed 稳定轮换），起点左上、BOSS 右下，
#   精英与装备开局即可见；
# - 四方向邻接（上下左右），供后续 Step 2 计算普通威胁数字；
# - 战斗房、武器、护符在生成时一次冻结，不随揭示 / 查看 / 撤回重抽；
# - 不接入移动、数字、揭示、战斗确认或新战斗机制（Step 2/3 负责）。
#
# 节点结构与 board_node_data.gd 的运行时 Dictionary 对齐，额外字段：
#   row / col        网格坐标（0..3）
#   distance         与起点的曼哈顿距离
#   revealed         是否已揭示（Step 1 只给公开类型置 true）
#   visible          开局是否可见（精英 / BOSS / 装备 / 商店 / 休整 / 起点）
#   frozen           内容已冻结
#   number           普通威胁数字；Step 1 固定 -1，Step 2 计算
#
# 输出 Dictionary：
#   {nodes, by_id, start_id, boss_id, elite_id, weapon_ids, charm_id,
#    rows, cols, act, seed, battle_rooms}
# ============================================================================

const NODE = preload("res://scripts/board/board_node_data.gd")

const ROWS := 4
const COLS := 4
const CELL_COUNT := ROWS * COLS

# 行优先人工布置（row, col）；起点固定 (0,0)，BOSS 固定 (3,3)，精英与装备开局可见。
# Step 7：3 套人工验证模板按 seed 稳定轮换；索引 1 对应当前默认样板
# （seed 20261110 % 3 == 1），保证既有 Step 1–5 回归的默认盘面不变。
# 每套模板共同约束：类型数量一致、起点有非战斗首选格、精英/BOSS 可见、
# 至少一件武器距起点 ≤2、存在一条全程数字 ≤2 的起点→BOSS 路径。
const TEMPLATES := [
	# 0：补给夹击——起点左侧武器 / 上方休整，护符与精英在中下。
	[
		["start", "rest", "normal", "weapon"],
		["weapon", "normal", "shop", "normal"],
		["normal", "elite", "charm", "normal"],
		["rest", "normal", "shop", "boss"],
	],
	# 1：默认样板——起点右侧武器，护符在左，精英守望中段武器。
	[
		["start", "weapon", "normal", "rest"],
		["normal", "charm", "elite", "normal"],
		["normal", "normal", "weapon", "shop"],
		["shop", "normal", "rest", "boss"],
	],
	# 2：中庭护符——起点上方普通 / 下方休整，武器沿右列推进。
	[
		["start", "normal", "weapon", "shop"],
		["rest", "normal", "normal", "normal"],
		["normal", "elite", "charm", "weapon"],
		["shop", "normal", "rest", "boss"],
	],
]
const DEFAULT_TEMPLATE_INDEX := 1

# 开局公开类型；普通怪身份留到 Step 2 揭示。
const ALWAYS_VISIBLE := ["start", "elite", "boss", "weapon", "charm", "shop", "rest"]

const SHORT_CN := {
	"start": "起",
	"normal": "普",
	"elite": "精",
	"boss": "王",
	"weapon": "武",
	"charm": "符",
	"shop": "店",
	"rest": "休",
}

const EXPECTED_COUNTS := {
	"start": 1,
	"normal": 6,
	"elite": 1,
	"boss": 1,
	"weapon": 2,
	"charm": 1,
	"shop": 2,
	"rest": 2,
}

# Step 5 节奏样板：ACT1 棋盘优先放入寒铁精英 / 冰封铁瓮，
# 保证「蓄势—爆发—恢复」在默认棋盘就能被读到；资源缺失或幕不匹配时回落到随机池。
const RHYTHM_SAMPLE := {
	1: {
		"elite": "res://resources/rooms/a1_elite_brute_ice.tres",
		"boss": "res://resources/rooms/frozen_urn.tres",
	},
}

var _ctrl
var _rng := RandomNumberGenerator.new()
# Step 5：装备格的探索来源（chest 品质表）。内容在生成时冻结，同 seed 可复现。
var _gen_act := 1


func _init(ctrl) -> void:
	_ctrl = ctrl


# 生成固定 4×4 内容。同 seed 结果完全一致；不改全局 RNG、meta、装配或资源。
# template_override >= 0 时强制指定模板（测试 / 采集用）；-1 = 按 seed 轮换。
func generate(act: int = 1, seed_value: int = 20261110, template_override: int = -1) -> Dictionary:
	_rng.seed = seed_value
	_gen_act = act
	var tpl_index: int = template_override if template_override >= 0 else template_index_for(seed_value)
	tpl_index = clampi(tpl_index, 0, TEMPLATES.size() - 1)
	var tpl: Array = TEMPLATES[tpl_index]
	var nodes: Array = []
	var by_id := {}
	for r in range(ROWS):
		for c in range(COLS):
			var id := cell_id(r, c)
			var type := String(tpl[r][c])
			var n: Dictionary = NODE.make(id, type, c)
			n["row"] = r
			n["col"] = c
			n["act"] = act
			n["distance"] = r + c
			n["next"] = _neighbors(r, c)
			n["frozen"] = true
			n["revealed"] = type != "normal"
			n["visible"] = type in ALWAYS_VISIBLE
			n["number"] = -1
			nodes.append(n)
			by_id[id] = n

	var used := {}
	_assign_boss(by_id, act, used)
	_assign_elite(by_id, act, used)
	_assign_normals(by_id, act, used)
	_assign_weapons(by_id, used)
	_assign_charm(by_id)
	_fill_text(by_id)

	var battle_rooms: Array = []
	for n in nodes:
		if not NODE.is_battle(String(n["type"])):
			continue
		n["battle_index"] = battle_rooms.size()
		battle_rooms.append(n["room"])

	return {
		"nodes": nodes,
		"by_id": by_id,
		"start_id": cell_id(0, 0),
		"boss_id": cell_id(ROWS - 1, COLS - 1),
		"elite_id": _first_id(by_id, "elite"),
		"weapon_ids": _ids_of_type(by_id, "weapon"),
		"charm_id": _first_id(by_id, "charm"),
		"rows": ROWS,
		"cols": COLS,
		"act": act,
		"seed": seed_value,
		"template_index": tpl_index,
		"battle_rooms": battle_rooms,
	}


# Step 7：seed → 模板索引（稳定、可复现；不同 seed 会轮换到不同人工模板）。
static func template_index_for(seed_value: int) -> int:
	return absi(seed_value) % TEMPLATES.size()


static func cell_id(row: int, col: int) -> String:
	return "g%d%d" % [row, col]


static func expected_degree(row: int, col: int) -> int:
	var d := 0
	if row > 0:
		d += 1
	if row < ROWS - 1:
		d += 1
	if col > 0:
		d += 1
	if col < COLS - 1:
		d += 1
	return d


func _neighbors(row: int, col: int) -> Array:
	var out: Array = []
	for d in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
		var rr: int = row + int(d[0])
		var cc: int = col + int(d[1])
		if rr >= 0 and rr < ROWS and cc >= 0 and cc < COLS:
			out.append(cell_id(rr, cc))
	return out


# ---------------------------------------------------------------------------
# 房间 / 物品分配（全部在生成时冻结）
# ---------------------------------------------------------------------------

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


func _take(arr: Array, used: Dictionary, preferred: String = "") -> RoomData:
	if preferred != "":
		for room in arr:
			if used.has(room.resource_path):
				continue
			if String(room.element) == preferred:
				return room
	for room in arr:
		if not used.has(room.resource_path):
			return room
	return null


func _assign_boss(by_id: Dictionary, act: int, used: Dictionary) -> void:
	var room: RoomData = _preferred_room(act, "boss")
	if room == null:
		room = _take(_pool(act, "boss"), used)
	var id := cell_id(ROWS - 1, COLS - 1)
	if room == null:
		push_error("BoardGrid: ACT%d BOSS 池为空，%s 无法冻结 BOSS" % [act, id])
		by_id[id]["desc"] = "BOSS（池为空）"
		return
	by_id[id]["room"] = room
	by_id[id]["ria"] = 7
	by_id[id]["final"] = false   # ACT1 原型；三幕接入时由 Step 9 决定
	used[room.resource_path] = true


func _assign_elite(by_id: Dictionary, act: int, used: Dictionary) -> void:
	var room: RoomData = _preferred_room(act, "elite")
	if room == null:
		room = _take(_pool(act, "elite"), used)
	var id := _first_id(by_id, "elite")
	if room == null:
		push_error("BoardGrid: ACT%d 精英池为空，%s 无法冻结精英" % [act, id])
		by_id[id]["desc"] = "精英（池为空）"
		return
	by_id[id]["room"] = room
	by_id[id]["ria"] = mini(6, int(by_id[id]["distance"]))
	used[room.resource_path] = true


# Step 5：按幕读取节奏样板房间；不存在 / 类型或幕不匹配时返回 null（调用方回落随机池）。
func _preferred_room(act: int, kind: String) -> RoomData:
	var sample: Dictionary = RHYTHM_SAMPLE.get(act, {})
	var path := String(sample.get(kind, ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var room: RoomData = load(path)
	if room == null or String(room.kind) != kind or int(room.act) != act:
		return null
	return room


func _assign_normals(by_id: Dictionary, act: int, used: Dictionary) -> void:
	var pool: Array = _pool(act, "normal")
	# Step 4 样板保证：每张棋盘至少出现 3 只带早期特性的普通怪（4 只样板中按 seed 抽 3），
	# 其余位置由无特性普通怪补足；仍然是同一 seed 完全可复现的内容。
	var sample: Array = []
	var plain: Array = []
	for room in pool:
		if room.gimmick_script != null and String(room.gimmick_params.get("trait", "")) != "":
			sample.append(room)
		else:
			plain.append(room)
	var ordered: Array = []
	for i in mini(3, sample.size()):
		ordered.append(sample[i])
	ordered.append_array(plain)
	for room in sample:
		if not ordered.has(room):
			ordered.append(room)
	pool = ordered
	var targets: Array = []
	for id in by_id:
		if String(by_id[id]["type"]) == "normal":
			targets.append(by_id[id])
	targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["distance"]) != int(b["distance"]):
			return int(a["distance"]) < int(b["distance"])
		return String(a["id"]) < String(b["id"]))
	for n in targets:
		var room: RoomData = _take(pool, used)
		if room == null:
			push_error("BoardGrid: ACT%d 普通房池不足，%s 无法冻结房间" % [act, n["id"]])
			continue
		n["room"] = room
		n["ria"] = mini(6, int(n["distance"]))
		used[room.resource_path] = true


func _assign_weapons(by_id: Dictionary, used: Dictionary) -> void:
	for id in _ids_of_type(by_id, "weapon"):
		var exclude: Array = _ctrl.selected_loadout.duplicate()
		for k in used:
			exclude.append(String(k))
		var pick := String(_ctrl._reward_system.pick_explore_loot("weapon", _gen_act, _rng, exclude))
		if pick == "":
			by_id[id]["title"] = "武器（无可用候选）"
			by_id[id]["desc"] = "落地折算金币 +15（武器池已空）"
			continue
		used[pick] = true
		by_id[id]["item_path"] = pick
		_fill_weapon_text(by_id[id], pick)


func _assign_charm(by_id: Dictionary) -> void:
	var id := _first_id(by_id, "charm")
	var pick := String(_ctrl._reward_system.pick_explore_loot(
		"passive", _gen_act, _rng, _ctrl.selected_charms))
	if pick == "":
		by_id[id]["title"] = "护符（无可用候选）"
		by_id[id]["desc"] = "落地折算金币 +15（护符池已空）"
		return
	by_id[id]["item_path"] = pick
	var cd: ItemData = load(pick)
	by_id[id]["title"] = "护符 · %s" % (cd.item_name if cd != null else pick.get_file().get_basename())
	var body := String(cd.description) if cd != null else ""
	by_id[id]["desc"] = "%s\n落地入护符槽；满 3 折算金币" % body


func _fill_weapon_text(n: Dictionary, path: String) -> void:
	var wd: WeaponData = load(path)
	if wd == null:
		n["title"] = "武器 · %s" % path.get_file().get_basename()
		n["desc"] = "落地直接获得"
		return
	n["title"] = "武器 · %s" % wd.weapon_name
	n["desc"] = "攻%d · %s · 命中%d%% · %s\n落地直接入槽；双武器满则替换" % [
		int(wd.base_power), String(wd.rarity), int(wd.hit_rate * 100.0),
		ElementCounter.label(wd.element)]


func _fill_text(by_id: Dictionary) -> void:
	for id in by_id:
		var n: Dictionary = by_id[id]
		var t := String(n["type"])
		match t:
			"start":
				n["title"] = "起点"
				n["desc"] = NODE.hint("start")
			"shop":
				n["title"] = "商店"
				n["desc"] = NODE.hint("shop")
			"rest":
				n["title"] = "休整"
				n["desc"] = NODE.hint("rest")
			"normal", "elite", "boss":
				var room: RoomData = n.get("room")
				if room != null:
					n["title"] = room.name
					n["desc"] = _room_desc(room, t)


func _room_desc(r: RoomData, type: String) -> String:
	var kind_txt: String = {"normal": "普通战斗", "elite": "精英战斗", "boss": "BOSS 战"}.get(type, "战斗")
	var bits: Array[String] = [kind_txt, ElementCounter.label(r.element)]
	if r.gimmick_script != null:
		var icon := String(r.gimmick_script.get_script_constant_map().get("ICON", ""))
		if icon != "":
			bits.append("机制 %s" % icon)
	if type == "elite":
		bits.append("胜利后进入战后成长 · 保底护符")
	elif type == "boss":
		bits.append("专属战利品")
	else:
		bits.append("胜利后进入战后成长")
	return " · ".join(bits)


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _first_id(by_id: Dictionary, type: String) -> String:
	for id in by_id:
		if String(by_id[id]["type"]) == type:
			return String(id)
	return ""


func _ids_of_type(by_id: Dictionary, type: String) -> Array:
	var out: Array = []
	for id in by_id:
		if String(by_id[id]["type"]) == type:
			out.append(String(id))
	out.sort()
	return out


# ---------------------------------------------------------------------------
# 校验与可视化
# ---------------------------------------------------------------------------

# 返回错误列表；空数组 = Step 1 出口满足。
func validate(data: Dictionary) -> Array:
	var errs: Array = []
	var nodes: Array = data.get("nodes", [])
	var by_id: Dictionary = data.get("by_id", {})
	var rows := int(data.get("rows", 0))
	var cols := int(data.get("cols", 0))
	if rows != ROWS or cols != COLS:
		errs.append("网格尺寸不是 4×4：%d×%d" % [rows, cols])
	if nodes.size() != CELL_COUNT or by_id.size() != CELL_COUNT:
		errs.append("格数不是 16：nodes=%d by_id=%d" % [nodes.size(), by_id.size()])

	var tally := {}
	var coords := {}
	for n in nodes:
		var id := String(n.get("id", ""))
		var r := int(n.get("row", -1))
		var c := int(n.get("col", -1))
		if r < 0 or r >= ROWS or c < 0 or c >= COLS:
			errs.append("%s 坐标越界：(%d,%d)" % [id, r, c])
		var key := "%d,%d" % [r, c]
		if coords.has(key):
			errs.append("坐标重复：%s" % key)
		coords[key] = true
		if id != cell_id(r, c):
			errs.append("%s 与坐标 (%d,%d) 不一致" % [id, r, c])
		var t := String(n.get("type", ""))
		tally[t] = int(tally.get(t, 0)) + 1
		if not bool(n.get("frozen", false)):
			errs.append("%s 未冻结" % id)
		var next: Array = n.get("next", [])
		if next.size() != expected_degree(r, c):
			errs.append("%s 邻接数 %d，应为 %d" % [id, next.size(), expected_degree(r, c)])
		for nx in next:
			var tgt: Dictionary = by_id.get(String(nx), {})
			if tgt.is_empty():
				errs.append("%s 指向不存在的格 %s" % [id, nx])
			elif not (String(id) in (tgt.get("next", []) as Array)):
				errs.append("邻接不对称：%s → %s" % [id, nx])
		if NODE.is_battle(t):
			var room: RoomData = n.get("room")
			if room == null:
				errs.append("%s（%s）没有冻结房间" % [id, t])
			elif String(room.kind) != t:
				errs.append("%s 类型 %s 与房间 kind=%s 不符" % [id, t, room.kind])
			if int(n.get("ria", -1)) < 0:
				errs.append("%s 没有 ria" % id)
			if t == "boss" and int(n.get("ria", -1)) != 7:
				errs.append("BOSS %s ria 应为 7" % id)
			if t != "boss" and int(n.get("ria", -99)) > 6:
				errs.append("%s 普通/精英 ria 应在 0–6" % id)
		if t == "weapon" or t == "charm":
			var path := String(n.get("item_path", ""))
			if path == "":
				errs.append("%s 没有冻结物品路径" % id)
			elif not ResourceLoader.exists(path):
				errs.append("%s 物品路径不存在：%s" % [id, path])
			elif not bool(n.get("visible", false)):
				errs.append("%s 装备格应开局可见" % id)
		if t == "charm" and String(n.get("item_path", "")) != "":
			var item: Resource = load(String(n["item_path"]))
			if item != null and String(item.get("category")) != "passive":
				errs.append("%s 护符格物品不是 passive" % id)
		if (t == "boss" or t == "elite") and not bool(n.get("visible", false)):
			errs.append("%s 应开局可见" % id)
		if int(n.get("number", 0)) != -1:
			errs.append("%s 的 Step 1 威胁数字应为 -1" % id)

	for t in EXPECTED_COUNTS:
		var want := int(EXPECTED_COUNTS[t])
		var got := int(tally.get(t, 0))
		if got != want:
			errs.append("类型 %s 数量 %d，应为 %d" % [t, got, want])

	# 起点的首个可选格至少有一个不是战斗。
	var start_id := String(data.get("start_id", ""))
	var start: Dictionary = by_id.get(start_id, {})
	var safe := false
	for nx in start.get("next", []):
		var tgt: Dictionary = by_id.get(String(nx), {})
		if not NODE.is_battle(String(tgt.get("type", ""))):
			safe = true
			break
	if not safe:
		errs.append("起点没有安全/低风险的首选格")

	# BOSS 在右下、起点在左上。
	var boss_id := String(data.get("boss_id", ""))
	if boss_id != cell_id(ROWS - 1, COLS - 1):
		errs.append("BOSS 不在右下角")
	var boss: Dictionary = by_id.get(boss_id, {})
	if boss.is_empty() or String(boss.get("type", "")) != "boss":
		errs.append("BOSS 格不是 boss 类型")

	# 全图连通：从起点四方向可达全部 16 格。
	var seen := {}
	var stack: Array = [start_id]
	while not stack.is_empty():
		var id: String = stack.pop_back()
		if seen.has(id):
			continue
		seen[id] = true
		for nx in by_id[id].get("next", []):
			stack.append(String(nx))
	if seen.size() != CELL_COUNT:
		errs.append("存在孤立格：仅 %d/16 可达" % seen.size())

	return errs


# 4 行文本地图，用于文档/日志核对（不影响运行）。
func ascii_map(data: Dictionary) -> String:
	var by_id: Dictionary = data.get("by_id", {})
	var lines: Array[String] = []
	for r in range(ROWS):
		var row: Array[String] = []
		for c in range(COLS):
			var n: Dictionary = by_id.get(cell_id(r, c), {})
			var t := String(n.get("type", "?"))
			var mark := String(SHORT_CN.get(t, "?"))
			if bool(n.get("visible", false)):
				row.append(mark)
			else:
				row.append("·" + mark)
		lines.append(" ".join(row))
	return "\n".join(lines)
