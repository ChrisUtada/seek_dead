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
	# G7-A S4：act_summaries 属于「本局」而不是「本张棋盘」，换盘不清；
	# 新局由 clear_summaries() 显式清空（reset_run_state 调用）。


# 生成一局棋盘。返回 false 表示拓扑/房间分配不合法（调用方应回退线性模式）。
# act_override >= 0 时按该幕生成（三幕串联逐幕换盘），不修改共享 BoardConfig。
func generate(cfg, act_override: int = -1) -> bool:
	reset()
	act = int(cfg.act) if act_override < 0 else int(act_override)
	dice_sides = maxi(1, int(cfg.dice_sides))
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


func _validate() -> bool:
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


func is_boss_node(node: Dictionary) -> bool:
	return String(node.get("type", "")) == "boss"


func is_boss_id(id: String) -> bool:
	return boss_ids.has(id)


func current_is_boss() -> bool:
	return is_boss_id(current_id)


func is_final_node(node: Dictionary) -> bool:
	return bool(node.get("final", false))


# 单局路径长度：起点到 BOSS 的共同深度 + 1（所有路线同构）。
func route_length() -> int:
	return boss_depth + 1


func progress_text() -> String:
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
	return generated and dice == 0 and not current_is_boss() and not next_nodes().is_empty()


func has_steps() -> bool:
	return dice > 0 and not current_is_boss()


# 1D3（骰面数由 BoardConfig 提供）；同一移动期间重复调用返回同一预算。
func roll_dice() -> int:
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
func legal_targets() -> Array:
	if not generated or dice <= 0:
		return []
	return next_nodes()


# 前进一步：只接受相邻的未消耗节点；每次调用消耗 1 步预算。
# 调用方必须在移动动画结束后调用一次，负责执行节点效果。
func advance_to(id: String) -> Dictionary:
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
	_ctrl.game_state = _ctrl.FlowState.PLAYING
	_ctrl.in_interroom = false
	_ctrl.hud.set_interroom_enabled(false)
	_ctrl.hud.show_board_screen(self)
