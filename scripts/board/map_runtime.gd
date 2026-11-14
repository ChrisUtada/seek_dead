extends RefCounted

# ============================================================================
# MapRuntime — 14×9 地图回合运行时（开发／AI 测试入口专用 · Step 2）
# 规格：docs/地图巡逻诱导_第一版预算与分步执行计划_2026-11-14.md
#       §2.1 玩家循环、§2.2 地图操作、§3.3 巡逻时机、§4.1 镜头、§4.3 操作栏、§6 Step 2
#
# 边界（Step 2 任务 6）：
# - 只服务开发／AI 测试入口：本类不被 board_screen / board_system / board_config 引用，
#   产品默认入口保持关闭（cfg.map14x9_enabled = false）；
# - 不改 board_system / board_screen / board_config，不退役任何旧模型或旧测试
#   （g7_run3_test / loot_explore_test / g8_loadout_layout_test 持续有效）；
# - 地图内容由 MapBoardBuilder 冻结，本类只持有运行时状态（坐标 / 回合 / 消耗），
#   不写回 cell，不重抽内容，也不持有 RNG；
# - 巡逻怪物移动属 Step 3，本类只保留回合推进钩子（patrol_ticks），不实现怪物行为；
# - 陷阱结算属 Step 4，踩陷阱格在本步只移动，不结算。
# ============================================================================

const MAP_GRID = preload("res://scripts/board/map_grid.gd")
const MAP_TYPES = preload("res://scripts/board/map_node_types.gd")
const MAP_BUILDER = preload("res://scripts/board/map_board_builder.gd")
const MAP_PATROL = preload("res://scripts/board/map_patrol.gd")
const MAP_TRAP = preload("res://scripts/board/map_trap.gd")

const SAVE_VERSION := 1

# §4.1 主视口一次显示约 8×6–9×7 格；取上限 9×7，绝不让 14×9 整图入屏。
const VIEW_COLS := 9
const VIEW_ROWS := 7

# 480×270 目标分辨率下的布局契约（实际绘制在 Step 6 收口）。
const VIEWPORT := Vector2i(480, 270)
const PANEL_W := 132
const ACTION_BAR_H := 24
const TILE_SIZE := 34

# §4.3 底部操作栏顺序，文案由 UI 层给出，数据层只冻结顺序与占位。
const ACTIONS := ["move", "wait", "build", "withdraw"]
const ACTION_LABELS := {
	"move": "移动（点击相邻格）",
	"wait": "等待一回合",
	"build": "查看构筑",
	"withdraw": "撤回整备",
}
const ACTION_BTN := Vector2i(92, 18)
const ACTION_GAP := 6

const REASON_OK := "ok"
const REASON_NOT_ADJACENT := "not_adjacent"
const REASON_BLOCKED := "blocked"
const REASON_OUT_OF_RANGE := "out_of_range"
const REASON_SAME_CELL := "same_cell"
const REASON_PATROL := "patrol"

var board: Dictionary = {}
var grid: Dictionary = {}
var cols: int = MAP_GRID.COLS
var rows: int = MAP_GRID.ROWS
var player_cell: int = -1
var turn: int = 0
# 探索内容一次性结算记录：cell_id -> true。战斗格不进这里（进入次数见 encounters）。
var consumed: Dictionary = {}
var visits: Dictionary = {}
var encounters: Dictionary = {}
var settled_log: Array = []
var pending_battle: Dictionary = {}
# Step 3 巡逻：默认关闭，由 create(..., with_patrols=true) 显式启用，
# 以保证 Step 2 的移动 / 等待 / 回访契约不受巡逻占格影响。
var patrols: Array = []
var patrol_enabled: bool = false
var contacts: Array = []
# Step 4：陷阱触发记录（运行时状态，不写回 cell）。
# cell_id -> {"patrol": id, "turn": 回合, "consumed": 是否已被某场战斗结算}
var trap_state: Dictionary = {}
var trap_triggers: Array = []
# Step 3 巡逻钩子：每次回合推进 +1。
var patrol_ticks: int = 0

var _nodes_by_cell: Dictionary = {}


# ---------------------------------------------------------------------------
# 初始化
# ---------------------------------------------------------------------------

# ctrl 是 DuelController（提供 ALL_ROOMS / _reward_system / selected_loadout）。
# 只允许开发／AI 测试显式调用，产品入口不调用。
# with_patrols：Step 3 巡逻为显式开关，默认关闭以保持 Step 2 契约不变。
static func create(ctrl, act: int, seed_value: int, total_acts: int = 1,
		with_patrols: bool = false):
	var builder = MAP_BUILDER.new(ctrl)
	var rt = new()
	rt.setup(builder.build(act, seed_value, total_acts), with_patrols)
	return rt


func setup(board_data: Dictionary, with_patrols: bool = false) -> void:
	board = board_data
	grid = board_data.get("grid", {})
	cols = int(board_data.get("cols", MAP_GRID.COLS))
	rows = int(board_data.get("rows", MAP_GRID.ROWS))
	_nodes_by_cell.clear()
	for n in board_data.get("nodes", []):
		_nodes_by_cell[int(n["cell_id"])] = n
	player_cell = int(grid.get("start_id", -1))
	turn = 0
	patrol_ticks = 0
	consumed.clear()
	visits.clear()
	encounters.clear()
	settled_log.clear()
	pending_battle.clear()
	contacts.clear()
	patrols.clear()
	patrol_enabled = with_patrols
	trap_state.clear()
	trap_triggers.clear()
	if with_patrols:
		for p in board_data.get("patrols", []):
			patrols.append({
				"id": String(p["id"]),
				"order": int(p["order"]),
				"spawn": int(p["spawn"]),
				"region": String(p["region"]),
				"kind": String(p["kind"]),
				"path": (p["path"] as Array).duplicate(),
				"path_index": 0,
				"cell": int(p["spawn"]),
				"active": true,
				"room": p.get("room"),
				"room_path": String(p.get("room_path", "")),
				"title": String(p.get("title", "巡逻怪")),
				"trap_armed": false,
				"trap_used": false,
				"trap_cell": -1,
			})
	if player_cell >= 0:
		visits[player_cell] = 1


func cell_of(node_id: String) -> int:
	if node_id == "":
		return -1
	return int(node_id.trim_prefix("m"))


func node_at(cell: int) -> Dictionary:
	return _nodes_by_cell.get(cell, {})


func is_walkable(cell: int) -> bool:
	if cell < 0 or cell >= cols * rows:
		return false
	var c: Dictionary = _cell(cell)
	return bool(c.get("walkable", false))


func is_consumed(cell: int) -> bool:
	return consumed.has(cell)


func start_cell() -> int:
	return int(grid.get("start_id", -1))


func boss_cell() -> int:
	return int(grid.get("boss_id", -1))


# ---------------------------------------------------------------------------
# 移动（§2.2 点击相邻可行走格 → 移动一格并推进一个地图回合）
# ---------------------------------------------------------------------------

func can_move(to_cell: int) -> Dictionary:
	if to_cell < 0 or to_cell >= cols * rows:
		return {"ok": false, "reason": REASON_OUT_OF_RANGE}
	if to_cell == player_cell:
		return {"ok": false, "reason": REASON_SAME_CELL}
	if not is_walkable(to_cell):
		return {"ok": false, "reason": REASON_BLOCKED}
	if not MAP_GRID.neighbors(grid, player_cell).has(to_cell):
		return {"ok": false, "reason": REASON_NOT_ADJACENT}
	# §3.3：怪物占格，玩家不能穿过；撞上去进入战斗。
	if patrol_enabled and not patrol_at(to_cell).is_empty():
		return {"ok": false, "reason": REASON_PATROL}
	return {"ok": true, "reason": REASON_OK}


# 非法输入不改任何状态：坐标、回合、消耗、钩子计数全都不动。
# 撞巡逻怪是唯一的「非移动但进入战斗」结果，同样不推进回合、不扣 HP。
func try_move(to_cell: int) -> Dictionary:
	var gate: Dictionary = can_move(to_cell)
	if String(gate["reason"]) == REASON_PATROL:
		var hit: Dictionary = patrol_at(to_cell)
		var bump: Dictionary = _start_contact(hit, to_cell)
		return {
			"ok": false,
			"reason": REASON_PATROL,
			"player_cell": player_cell,
			"turn": turn,
			"settled": {},
			"contact": bump,
		}
	if not bool(gate["ok"]):
		return {
			"ok": false,
			"reason": String(gate["reason"]),
			"player_cell": player_cell,
			"turn": turn,
			"settled": {},
			"contact": {},
		}
	var from_cell := player_cell
	player_cell = to_cell
	visits[to_cell] = int(visits.get(to_cell, 0)) + 1
	# §2.1 顺序：先移动 → 地图推进一个回合（怪物公开行动）→ 再触发内容。
	var contact: Dictionary = _advance_turn()
	var settled: Dictionary = _settle(to_cell)
	# 接触优先：同格若同时是战斗节点，待战节点仍是巡逻怪，避免被节点覆盖。
	if not contact.is_empty():
		pending_battle = contact["node"]
	return {
		"ok": true,
		"reason": REASON_OK,
		"from": from_cell,
		"to": to_cell,
		"player_cell": player_cell,
		"turn": turn,
		"settled": settled,
		"contact": contact,
	}


# ---------------------------------------------------------------------------
# 等待（原地不动，只推进一个地图回合；怪物按预告行动一次）
# ---------------------------------------------------------------------------

func wait_turn() -> Dictionary:
	var before := turn
	var contact: Dictionary = _advance_turn()
	return {
		"ok": true,
		"advanced": turn - before,
		"player_cell": player_cell,
		"turn": turn,
		"contact": contact,
	}


# ---------------------------------------------------------------------------
# 巡逻（§3.3、§6 Step 3）
# ---------------------------------------------------------------------------

func patrol_at(cell: int) -> Dictionary:
	for p in patrols:
		if bool(p.get("active", true)) and int(p["cell"]) == cell:
			return p
	return {}


# 下一步预告，供地图与右侧栏同步显示。纯只读：不推进索引、不推回合。
func patrol_preview() -> Array:
	var out: Array = []
	for p in patrols:
		if not bool(p.get("active", true)):
			continue
		out.append({
			"id": String(p["id"]),
			"order": int(p["order"]),
			"cell": int(p["cell"]),
			"next": MAP_PATROL.preview_cell(p),
			"title": String(p.get("title", "巡逻怪")),
		})
	return out


func patrols_state() -> Array:
	var out: Array = []
	for p in patrols:
		out.append({
			"id": String(p["id"]),
			"order": int(p["order"]),
			"cell": int(p["cell"]),
			"path_index": int(p["path_index"]),
			"active": bool(p.get("active", true)),
			"region": String(p["region"]),
			"title": String(p.get("title", "巡逻怪")),
		})
	return out


# 「巡逻不永久堵死 BOSS」的可判定形式：当前巡逻占格之外仍存在通往 BOSS 的路径。
func reachable_avoiding_patrols(target: int) -> Array:
	var blocked: Array = []
	for p in patrols:
		if bool(p.get("active", true)):
			blocked.append(int(p["cell"]))
	return MAP_GRID.reachable(grid, player_cell, target, [], blocked)


# ---------------------------------------------------------------------------
# 陷阱（§3.4、§6 Step 4）
# ---------------------------------------------------------------------------

func trap_at(cell: int) -> Dictionary:
	return MAP_TRAP.trap_at(grid, cell)


func is_trap_cell(cell: int) -> bool:
	return MAP_TRAP.is_trap_cell(grid, cell)


# 右侧栏用：每只巡逻的当前位置、下一步是否陷阱、是否已武装、护甲会怎么变。
func trap_preview() -> Array:
	var out: Array = []
	for p in patrols:
		if not bool(p.get("active", true)):
			continue
		var next_cell: int = MAP_PATROL.preview_cell(p)
		var armor_now: int = MAP_TRAP.armor_of(p.get("room"))
		var armed: bool = bool(p.get("trap_armed", false))
		var next_is_trap: bool = MAP_TRAP.is_trap_cell(grid, next_cell)
		var text := ""
		if armed:
			text = MAP_TRAP.describe(armor_now)
		var hint := ""
		if next_is_trap and not armed and not bool(p.get("trap_used", false)):
			hint = "若下一步踩到陷阱：护甲 %d → %d" % [armor_now, MAP_TRAP.ARMOR_AFTER]
		out.append({
			"id": String(p["id"]),
			"order": int(p["order"]),
			"cell": int(p["cell"]),
			"next": next_cell,
			"next_is_trap": next_is_trap,
			"armed": armed,
			"armor": armor_now,
			"armor_after": MAP_TRAP.ARMOR_AFTER if armed else armor_now,
			"text": text,
			"hint": hint,
		})
	return out


func trap_triggers_count() -> int:
	return trap_triggers.size()


# 战斗返回：清除待战节点；击败则巡逻怪退场，地图状态保持可解释。
func resolve_contact(defeated: bool) -> void:
	var node: Dictionary = pending_battle
	pending_battle = {}
	if node.is_empty():
		return
	var pid: String = String(node.get("id", "")).trim_prefix("patrol_")
	if not defeated:
		return
	for p in patrols:
		if String(p["id"]) == pid:
			p["active"] = false


# ---------------------------------------------------------------------------
# 只读操作（§2.2 查看目标 / 查看构筑；不推进回合、不改 RNG、不改内容）
# ---------------------------------------------------------------------------

func view(cell: int) -> Dictionary:
	var c: Dictionary = _cell(cell)
	var node: Dictionary = node_at(cell)
	var type := String(node.get("type", MAP_TYPES.PATH))
	var label := MAP_TYPES.label_of(type)
	if type == MAP_TYPES.PATH:
		label = "通路"
	elif type == MAP_TYPES.START:
		label = "起点"
	return {
		"cell": cell,
		"walkable": bool(c.get("walkable", false)),
		"region": String(c.get("region", "")),
		"terrain": String(c.get("terrain", "")),
		"type": type,
		"label": label,
		"source": String(node.get("source", "")),
		"consumed": is_consumed(cell),
		"visits": int(visits.get(cell, 0)),
		"adjacent": MAP_GRID.neighbors(grid, player_cell).has(cell),
		"final": bool(node.get("final", false)),
		"trap": MAP_TRAP.is_trap_cell(grid, cell),
		"trap_type": String(MAP_TRAP.trap_at(grid, cell).get("type", "")),
	}


func view_build() -> Dictionary:
	return {
		"hp": 0,
		"gold": 0,
		"items": [],
		"note": "构筑详情由整备界面提供，本快照只读且不改变地图状态",
	}


func cancel() -> Dictionary:
	return {"ok": true, "player_cell": player_cell, "turn": turn}


# ---------------------------------------------------------------------------
# 镜头（§4.1 跟随角色、只显示 9×7 窗口）
# ---------------------------------------------------------------------------

func camera_origin() -> Vector2i:
	var pc: int = player_cell % cols
	var pr: int = player_cell / cols
	var ox: int = clampi(pc - VIEW_COLS / 2, 0, maxi(0, cols - VIEW_COLS))
	var oy: int = clampi(pr - VIEW_ROWS / 2, 0, maxi(0, rows - VIEW_ROWS))
	return Vector2i(ox, oy)


func camera_cells() -> Rect2i:
	return Rect2i(camera_origin(), Vector2i(VIEW_COLS, VIEW_ROWS))


# 地图绘制区（右侧信息栏与底部操作栏之外）。
func map_area() -> Rect2i:
	return Rect2i(0, 0, VIEWPORT.x - PANEL_W, VIEWPORT.y - ACTION_BAR_H)


func panel_rect() -> Rect2i:
	return Rect2i(VIEWPORT.x - PANEL_W, 0, PANEL_W, VIEWPORT.y - ACTION_BAR_H)


func camera_pixels() -> Rect2i:
	var content := Vector2i(VIEW_COLS * TILE_SIZE, VIEW_ROWS * TILE_SIZE)
	var area: Rect2i = map_area()
	return Rect2i(
		area.position.x + (area.size.x - content.x) / 2,
		area.position.y + (area.size.y - content.y) / 2,
		content.x, content.y)


# 格内绘制原点（左上角）在视口中的像素坐标。
func cell_pixels(cell: int) -> Vector2i:
	var rect: Rect2i = camera_cells()
	var pc: int = cell % cols
	var pr: int = cell / cols
	return camera_pixels().position + Vector2i(
		(pc - rect.position.x) * TILE_SIZE,
		(pr - rect.position.y) * TILE_SIZE)


func action_bar_rects() -> Array:
	var total: int = ACTIONS.size() * ACTION_BTN.x + (ACTIONS.size() - 1) * ACTION_GAP
	var x0: int = (VIEWPORT.x - total) / 2
	var y0: int = VIEWPORT.y - ACTION_BAR_H + (ACTION_BAR_H - ACTION_BTN.y) / 2
	var out: Array = []
	for i in range(ACTIONS.size()):
		out.append(Rect2i(x0 + i * (ACTION_BTN.x + ACTION_GAP), y0,
			ACTION_BTN.x, ACTION_BTN.y))
	return out


# ---------------------------------------------------------------------------
# 存档（§6 Step 2 任务 5：坐标 / 回合 / 内容消耗状态）
# 只做纯数据序列化，接入 SaveSystem 待正式入口开放（Step 5A 之后）。
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var pstate: Array = []
	for p in patrols:
		pstate.append({
			"id": String(p["id"]),
			"path_index": int(p["path_index"]),
			"active": bool(p.get("active", true)),
			"trap_armed": bool(p.get("trap_armed", false)),
			"trap_used": bool(p.get("trap_used", false)),
			"trap_cell": int(p.get("trap_cell", -1)),
		})
	return {
		"version": SAVE_VERSION,
		"seed": int(board.get("seed", 0)),
		"act": int(board.get("act", 1)),
		"player_cell": player_cell,
		"turn": turn,
		"patrol_ticks": patrol_ticks,
		"patrol_enabled": patrol_enabled,
		"patrols": pstate,
		"consumed": _sorted_keys(consumed),
		"visits": _string_keys(visits),
		"encounters": _string_keys(encounters),
	}


func from_dict(d: Dictionary) -> bool:
	if int(d.get("version", 0)) != SAVE_VERSION:
		return false
	# 地图内容必须来自同一个种子与幕，否则坐标与消耗都对不上。
	if int(d.get("seed", -1)) != int(board.get("seed", -2)):
		return false
	if int(d.get("act", -1)) != int(board.get("act", -2)):
		return false
	# 巡逻开关必须一致，否则坐标与巡逻占格会对不上。
	if bool(d.get("patrol_enabled", false)) != patrol_enabled:
		return false
	var cell: int = int(d.get("player_cell", -1))
	if not is_walkable(cell):
		return false
	player_cell = cell
	turn = int(d.get("turn", 0))
	patrol_ticks = int(d.get("patrol_ticks", turn))
	consumed.clear()
	for raw in d.get("consumed", []):
		consumed[int(raw)] = true
	visits.clear()
	var raw_visits: Dictionary = d.get("visits", {})
	for k in raw_visits.keys():
		visits[int(k)] = int(raw_visits[k])
	encounters.clear()
	var raw_enc: Dictionary = d.get("encounters", {})
	for k in raw_enc.keys():
		encounters[int(k)] = int(raw_enc[k])
	# 巡逻恢复：path_index 为权威，cell 由路径推出，保证与冻结环一致。
	var raw_patrols: Array = d.get("patrols", [])
	for entry in raw_patrols:
		var pid: String = String(entry.get("id", ""))
		for p in patrols:
			if String(p["id"]) != pid:
				continue
			var path: Array = p["path"]
			var idx: int = int(entry.get("path_index", 0)) % maxi(1, path.size())
			p["path_index"] = idx
			p["cell"] = int(path[idx])
			p["active"] = bool(entry.get("active", true))
			p["trap_armed"] = bool(entry.get("trap_armed", false))
			p["trap_used"] = bool(entry.get("trap_used", false))
			p["trap_cell"] = int(entry.get("trap_cell", -1))
			if bool(p["trap_armed"]):
				trap_state[int(p["trap_cell"])] = {
					"patrol": String(p["id"]), "turn": turn, "consumed": false,
				}
	settled_log.clear()
	pending_battle.clear()
	contacts.clear()
	return true


# ---------------------------------------------------------------------------
# 状态指纹：用于证明查看 / 取消没有副作用
# ---------------------------------------------------------------------------

func signature() -> String:
	var parts: Array = ["p=%d" % player_cell, "t=%d" % turn, "k=%d" % patrol_ticks]
	parts.append("c=" + ",".join(_sorted_keys(consumed).map(func(v): return str(v))))
	for p in patrols:
		parts.append("g%s=%d/%d/%d/%d/%d" % [String(p["id"]), int(p["cell"]),
			int(p["path_index"]), 1 if bool(p.get("active", true)) else 0,
			1 if bool(p.get("trap_armed", false)) else 0,
			1 if bool(p.get("trap_used", false)) else 0])
	parts.append("n=%d" % contacts.size())
	var vkeys: Array = visits.keys()
	vkeys.sort()
	for k in vkeys:
		parts.append("v%d=%d" % [int(k), int(visits[k])])
	var ekeys: Array = encounters.keys()
	ekeys.sort()
	for k in ekeys:
		parts.append("e%d=%d" % [int(k), int(encounters[k])])
	return "|".join(parts)


# 内容指纹：证明回合推进与查看都不会重抽奖励。
func content_fingerprint() -> String:
	var nodes: Array = board.get("nodes", [])
	var keys: Array = []
	for n in nodes:
		keys.append(int(n["cell_id"]))
	keys.sort()
	var parts: Array = []
	for cid in keys:
		var n: Dictionary = _nodes_by_cell[int(cid)]
		parts.append("%d:%s:%s:%s:%s" % [
			int(cid), String(n.get("type", "")), str(n.get("variant", "")),
			String(n.get("item_path", "")), str(n.get("armory_paths", []))])
	return "|".join(parts)


func take_pending_battle() -> Dictionary:
	var n: Dictionary = pending_battle
	pending_battle = {}
	return n


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------

func _advance_turn() -> Dictionary:
	turn += 1
	patrol_ticks += 1
	# §3.3 多只怪物行动顺序固定：严格按 order 0→1→2 依次前进，不用随机顺序。
	for p in patrols:
		if not bool(p.get("active", true)):
			continue
		MAP_PATROL.step(p)
		# §3.4 顺序固定：先移动 → 再记录陷阱触发 → 最后判定接触。
		_on_patrol_enter(p)
	return _check_contact()


# 怪物进入公开陷阱 → 记录一次触发并武装破甲；同一只怪物只武装一次。
func _on_patrol_enter(p: Dictionary) -> void:
	var cell: int = int(p["cell"])
	if not MAP_TRAP.is_trap_cell(grid, cell):
		return
	if bool(p.get("trap_armed", false)) or bool(p.get("trap_used", false)):
		return
	p["trap_armed"] = true
	p["trap_cell"] = cell
	trap_triggers.append({"turn": turn, "patrol": String(p["id"]), "cell": cell})
	trap_state[cell] = {"patrol": String(p["id"]), "turn": turn, "consumed": false}


# 怪物行动后若与玩家同格 → 接触。取 order 最小者作为本次战斗对象。
func _check_contact() -> Dictionary:
	for p in patrols:
		if not bool(p.get("active", true)):
			continue
		if int(p["cell"]) != player_cell:
			continue
		return _start_contact(p, player_cell)
	return {}


# 接触＝进入现有转轮战斗：只挂待战节点，不扣 HP、不额外结算。
func _start_contact(p: Dictionary, cell: int) -> Dictionary:
	if p.is_empty():
		return {}
	var armor_before: int = MAP_TRAP.armor_of(p.get("room"))
	var armed: bool = bool(p.get("trap_armed", false))
	var change: Dictionary = MAP_TRAP.change(armor_before) if armed \
		else {"before": armor_before, "after": armor_before, "effective": false, "text": ""}
	var node := {
		"id": "patrol_%s" % String(p["id"]),
		"type": "battle",
		"kind": "patrol",
		"cell_id": cell,
		"source": "patrol",
		"room": p.get("room"),
		"title": String(p.get("title", "巡逻怪")),
		"final": false,
		"armor_break": armed,
		"armor_before": int(change["before"]),
		"armor_after": int(change["after"]),
		"armor_text": String(change["text"]),
		"trap_cell": int(p.get("trap_cell", -1)),
	}
	if armed:
		# 效果只结算一次：武装立即消耗，该怪不再从陷阱获益。
		p["trap_armed"] = false
		p["trap_used"] = true
		var tc: int = int(p.get("trap_cell", -1))
		if trap_state.has(tc):
			trap_state[tc]["consumed"] = true
	pending_battle = node
	contacts.append({
		"turn": turn,
		"cell": cell,
		"patrol": String(p["id"]),
		"order": int(p["order"]),
		"armor_break": armed,
	})
	return {
		"patrol": String(p["id"]),
		"order": int(p["order"]),
		"cell": cell,
		"armor_break": armed,
		"armor_before": int(change["before"]),
		"armor_after": int(change["after"]),
		"node": node,
	}


func _settle(cell: int) -> Dictionary:
	var node: Dictionary = node_at(cell)
	if node.is_empty():
		return {}
	var type := String(node.get("type", ""))
	if type == "" or type == MAP_TYPES.PATH or type == MAP_TYPES.START:
		return {}
	if MAP_TYPES.is_battle(type):
		encounters[cell] = int(encounters.get(cell, 0)) + 1
		pending_battle = node
		return {"cell": cell, "type": type, "kind": "battle", "node": node}
	if consumed.has(cell):
		# 回访：只移动，不发奖、不重复触发。
		return {"cell": cell, "type": type, "kind": "revisit", "node": node}
	consumed[cell] = true
	settled_log.append({"turn": turn, "cell": cell, "type": type})
	return {
		"cell": cell,
		"type": type,
		"kind": "settle",
		"source": String(node.get("source", "")),
		"node": node,
	}


func _cell(cell: int) -> Dictionary:
	var cells: Array = grid.get("cells", [])
	if cell < 0 or cell >= cells.size():
		return {}
	return cells[cell]


func _sorted_keys(d: Dictionary) -> Array:
	var keys: Array = d.keys()
	keys.sort()
	return keys


func _string_keys(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d.keys():
		out[str(k)] = int(d[k])
	return out
