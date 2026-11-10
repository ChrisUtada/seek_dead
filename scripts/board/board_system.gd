extends RefCounted

# ============================================================================
# BoardSystem — 棋盘运行状态：当前节点 / 1D3 步数预算 / 逐格移动 / 一次性消耗
# 规格：docs/棋盘探索_战后成长与局外生涯_制作执行方案.md §5、§10.1、§11 M2
#
# 边界：
# - 只决定「接下来进入哪个 RoomData / 节点」，不写战斗伤害与奖励数值。
# - 掷骰得到的是「步数预算」：每次只沿一条边前进一格并立即结算该节点，
#   不再按落点跳过中间节点；到 BOSS 自动停止。
# - 移动只允许向 BOSS 方向；节点进入即标记 consumed，重复调用不会二次结算。
# - 掷骰使用全局 RNG（种子可复现）；移动动画由 BoardScreen 负责，且不得消耗 RNG。
# ============================================================================

const NODE = preload("res://scripts/board/board_node_data.gd")
const GENERATOR = preload("res://scripts/board/board_generator.gd")
const GRID = preload("res://scripts/board/board_grid.gd")

var _ctrl
var _gen

var nodes: Array = []
var by_id: Dictionary = {}
var battle_rooms: Array[RoomData] = []
var current_id := ""
var consumed: Dictionary = {}
var dice := 0                 # 本次掷骰剩余的步数（0 = 待掷 / 已走完）
var last_roll := 0
var feedback := ""            # 非战斗节点结算反馈（棋盘信息栏展示）
var act := 1
var boss_ids: Array[String] = []
var boss_depth := 0
var dice_sides := 3
var generated := false
var template_id := ""
var shape_id := ""
var layout := {}
# 扫雷棋盘 Step 2（2026-11-10）：4×4 网格运行状态。
# grid_mode = 本局走 board_grid.gd；revealed = 已揭示内容的格；
# defeated = 已击败的战斗节点（普通怪由此从相邻数字中移除）。
# 移动允许经过已消耗格（不重复结算），避免自避行走把 BOSS 封死。
var grid_mode := false
var revealed: Dictionary = {}
var defeated: Dictionary = {}
var last_move_revisit := false
var _grid_data: Dictionary = {}
var _grid_validator = null
# G7-A S4：已经打完的幕（每幕 BOSS 通关时的棋盘快照），供局末总结与记录回看。
var act_summaries: Array[Dictionary] = []


func _init(ctrl) -> void:
	_ctrl = ctrl
	_gen = GENERATOR.new(ctrl)


func reset() -> void:
	nodes.clear()
	by_id.clear()
	battle_rooms.clear()
	current_id = ""
	consumed.clear()
	dice = 0
	last_roll = 0
	feedback = ""
	act = 1
	boss_ids.clear()
	boss_depth = 0
	dice_sides = 3
	generated = false
	template_id = ""
	shape_id = ""
	layout = {}
	grid_mode = false
	revealed.clear()
	defeated.clear()
	last_move_revisit = false
	_grid_data = {}
	_grid_validator = null
	# G7-A S4：act_summaries 属于「本局」而不是「本张棋盘」，换盘不清；
	# 新局由 clear_summaries() 显式清空（reset_run_state 调用）。


# 生成一局棋盘。返回 false 表示拓扑/房间分配不合法（调用方应回退线性模式）。
# act_override >= 0 时按该幕生成（三幕串联逐幕换盘），不修改共享 BoardConfig。
func generate(cfg, act_override: int = -1) -> bool:
	reset()
	act = int(cfg.act) if act_override < 0 else int(act_override)
	dice_sides = maxi(1, int(cfg.dice_sides))
	grid_mode = cfg != null and cfg.has_method("use_grid") and bool(cfg.use_grid())
	if grid_mode:
		return _generate_grid(cfg, act)
	var data: Dictionary = _gen.generate(act, cfg)
	nodes = data["nodes"]
	by_id = data["by_id"]
	battle_rooms.assign(data["battle_rooms"])
	current_id = String(data["start_id"])
	for id in data["boss_ids"]:
		boss_ids.append(String(id))
	boss_depth = int(data["boss_depth"])
	consumed[current_id] = true
	template_id = String(data.get("template_id", ""))
	shape_id = String(data.get("shape_id", ""))
	layout = data.get("layout", {})
	generated = true
	return _validate()


# 扫雷棋盘 Step 2：固定 4×4 内容。内容在生成时冻结，运行期只改
# current / revealed / consumed / defeated，不重抽房间或物品。
func _generate_grid(cfg, gen_act: int) -> bool:
	_grid_validator = GRID.new(_ctrl)
	var data: Dictionary = _grid_validator.generate(gen_act, int(cfg.grid_seed))
	_grid_data = data
	nodes = data["nodes"]
	by_id = data["by_id"]
	battle_rooms.assign(data["battle_rooms"])
	current_id = String(data["start_id"])
	boss_ids.clear()
	boss_ids.append(String(data["boss_id"]))
	boss_depth = 0
	consumed.clear()
	revealed.clear()
	defeated.clear()
	last_move_revisit = false
	consumed[current_id] = true
	for n in nodes:
		if bool(n.get("revealed", false)):
			revealed[String(n["id"])] = true
	revealed[current_id] = true
	template_id = "manual"
	shape_id = "grid4x4"
	# 4 列 × 4 行；与 board_screen 的 480×270 灰盒布局一致。
	layout = {
		"x0": 48.0, "dx": 110.0, "node_w": 80.0,
		"row_y": [34.0, 74.0, 114.0, 154.0],
	}
	generated = true
	return _validate()


func _validate() -> bool:
	if grid_mode:
		return _validate_grid()
	# 节点总数随骨架变化（标准 25 / 长尾 29），拓扑合法性逐条校验。
	if nodes.is_empty() or nodes.size() != by_id.size():
		return false
	if boss_ids.size() != 4:
		return false
	for id in boss_ids:
		if not by_id.has(id):
			return false
	for n in nodes:
		if NODE.is_battle(String(n["type"])) and n.get("room") == null:
			return false
		# 所有连线必须指向更深的节点（无环、只向 BOSS 前进）
		for nx in n.get("next", []):
			var t: Dictionary = by_id.get(String(nx), {})
			if t.is_empty() or int(t.get("depth", 0)) <= int(n["depth"]):
				return false
	# 4 个 BOSS 必须都能从起点沿 next 可达（无软锁）
	var seen := {}
	var stack: Array = [current_id]
	while not stack.is_empty():
		var id: String = stack.pop_back()
		if seen.has(id):
			continue
		seen[id] = true
		for nx in by_id[id]["next"]:
			stack.append(String(nx))
	for id in boss_ids:
		if not seen.has(id):
			return false
	return true


# 4×4 内容校验：沿用 board_grid.validate 的 Step 1 出口，并确认 BOSS 唯一。
func _validate_grid() -> bool:
	if _grid_validator == null or _grid_data.is_empty():
		return false
	if boss_ids.size() != 1:
		return false
	var errs: Array = _grid_validator.validate(_grid_data)
	for e in errs:
		push_error("BoardGrid: %s" % e)
	return errs.is_empty()


# ---------------------------------------------------------------------------
# 查询
# ---------------------------------------------------------------------------

func node_count() -> int:
	return nodes.size()


func visited_count() -> int:
	return consumed.size()


func current_node() -> Dictionary:
	return by_id.get(current_id, {})


func current_depth() -> int:
	return int(current_node().get("depth", 0))


func current_index() -> int:
	for i in range(nodes.size()):
		if String(nodes[i]["id"]) == current_id:
			return i
	return -1


func node_by_id(id: String) -> Dictionary:
	return by_id.get(id, {})


func node_at_index(i: int) -> Dictionary:
	if i < 0 or i >= nodes.size():
		return {}
	return nodes[i]


func is_consumed(id: String) -> bool:
	return consumed.has(id)


func is_revealed(id: String) -> bool:
	return revealed.has(id)


func is_defeated(id: String) -> bool:
	return defeated.has(id)


# 扫雷数字：该格上下左右未击败的普通怪数量（精英 / BOSS 不计入）。
func number_of(id: String) -> int:
	if not grid_mode:
		return -1
	var n: Dictionary = by_id.get(id, {})
	if n.is_empty():
		return -1
	var count := 0
	for nx in n.get("next", []):
		var t: Dictionary = by_id.get(String(nx), {})
		if String(t.get("type", "")) == "normal" and not defeated.has(String(nx)):
			count += 1
	return count


func numbers_snapshot() -> Dictionary:
	var out := {}
	if not grid_mode:
		return out
	for n in nodes:
		var id := String(n["id"])
		out[id] = number_of(id)
	return out


# 普通 / 精英 / BOSS 战斗胜利后由 return_to_board 调用；只影响扫雷数字与状态，不发奖励。
func note_battle_won() -> void:
	if not grid_mode:
		return
	var n := current_node()
	if n.is_empty():
		return
	if NODE.is_battle(String(n.get("type", ""))):
		defeated[current_id] = true


func is_boss_node(node: Dictionary) -> bool:
	return String(node.get("type", "")) == "boss"


func is_boss_id(id: String) -> bool:
	return boss_ids.has(id)


func current_is_boss() -> bool:
	return is_boss_id(current_id)


func is_final_node(node: Dictionary) -> bool:
	return bool(node.get("final", false))


# 单局路径长度：起点到 BOSS 的共同深度 + 1（所有路线同构）。
# 扫雷网格没有单一共享路径，这里改用总格数，UI 显示为「已探索 x/16」。
func route_length() -> int:
	if grid_mode:
		return node_count()
	return boss_depth + 1


func progress_text() -> String:
	if grid_mode:
		return "%s · 已探索 %d/%d 格" % [act_label(), visited_count(), node_count()]
	return "%s · 第 %d/%d 格" % [act_label(), visited_count(), route_length()]


# G7-A S3：棋盘所属幕的名称（ACT I / II / III），文案与配色共用 Palette.ACT_THEME。
func act_label() -> String:
	return Palette.act_name(act)


# G7-A S4：新局清空幕快照（换盘不清，见 reset 注释）。
func clear_summaries() -> void:
	act_summaries.clear()


# G7-A S4：当前棋盘的快照（幕间推进前收集，局末总结 / 记录按幕分段用）。只读。
func summary() -> Dictionary:
	var boss_name := ""
	if current_is_boss():
		var r: RoomData = current_node().get("room")
		boss_name = String(r.name) if r != null else ""
	return {
		"act": act,
		"shape": shape_id,
		"template": template_id,
		"boss": boss_name,
		"nodes": node_count(),
		"cells": route_length(),
		"mode": "grid4x4" if grid_mode else "legacy",
	}


# ---------------------------------------------------------------------------
# 掷骰 / 前进一格
# ---------------------------------------------------------------------------

# 未被消耗的下一格（不管当前是否有步数）。
func next_nodes() -> Array:
	var out: Array = []
	for nx in current_node().get("next", []):
		var id := String(nx)
		if consumed.has(id):
			continue
		var n: Dictionary = by_id.get(id, {})
		if not n.is_empty():
			out.append(n)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["id"]) < String(b["id"]))
	return out


func can_roll() -> bool:
	if grid_mode:
		return false
	return generated and dice == 0 and not current_is_boss() and not next_nodes().is_empty()


func has_steps() -> bool:
	if grid_mode:
		return false
	return dice > 0 and not current_is_boss()


# 1D3（骰面数由 BoardConfig 提供）；同一移动期间重复调用返回同一预算。
# 扫雷网格不使用骰子。
func roll_dice() -> int:
	if grid_mode:
		return 0
	if dice > 0:
		return dice
	if not generated or current_is_boss():
		return 0
	if next_nodes().is_empty():
		return 0
	last_roll = 1 + randi() % dice_sides
	dice = last_roll
	feedback = ""
	return dice


# 本步可走的格子：有剩余步数时 = 下一格（分支处多个）。
# 扫雷网格：四方向相邻格全部可选；已消耗格可再次经过（只移动，不重复结算）。
func legal_targets() -> Array:
	if grid_mode:
		if not generated:
			return []
		var out: Array = []
		for nx in current_node().get("next", []):
			var n: Dictionary = by_id.get(String(nx), {})
			if not n.is_empty() and String(n["id"]) != current_id:
				out.append(n)
		out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return String(a["id"]) < String(b["id"]))
		return out
	if not generated or dice <= 0:
		return []
	return next_nodes()


# 前进一步：只接受相邻的未消耗节点；每次调用消耗 1 步预算。
# 调用方必须在移动动画结束后调用一次，负责执行节点效果。
func advance_to(id: String) -> Dictionary:
	if grid_mode:
		if not generated:
			return {}
		var target: Dictionary = by_id.get(id, {})
		if target.is_empty():
			return {}
		if not (id in (current_node().get("next", []) as Array)):
			return {}
		var was_consumed := consumed.has(id)
		current_id = id
		if not was_consumed:
			consumed[id] = true
		revealed[id] = true          # 进入即揭示；内容本身在生成时已冻结，不会重抽
		last_move_revisit = was_consumed
		feedback = ""
		return target
	last_move_revisit = false
	if not generated or dice <= 0:
		return {}
	var pick: Dictionary = {}
	for n in legal_targets():
		if String(n["id"]) == id:
			pick = n
			break
	if pick.is_empty():
		return {}
	consumed[id] = true
	current_id = id
	dice = maxi(0, dice - 1)
	if is_boss_node(pick):
		dice = 0
	feedback = ""
	return pick


func set_feedback(text: String) -> void:
	feedback = text


# 非战斗节点 / 战斗胜利后回到棋盘：恢复主视图（隐藏战斗 HUD）。
# 棋盘待机不是战斗态：把 WON / LOST 过渡态收回 PLAYING（否则胜利后再掷骰会重复结算）。
func return_to_board() -> void:
	# 扫雷棋盘：从战斗回到棋盘 = 当前战斗节点已胜利（战败走局末，不经过这里）。
	# 标记后相邻数字会移除这只普通怪；重复调用幂等。
	if grid_mode:
		note_battle_won()
	_ctrl.game_state = _ctrl.FlowState.PLAYING
	_ctrl.in_interroom = false
	_ctrl.hud.set_interroom_enabled(false)
	_ctrl.hud.show_board_screen(self)
