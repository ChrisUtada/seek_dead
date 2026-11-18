extends RefCounted

# ============================================================================
# BranchRuntime — 分岔路线图（DAG）的轻量运行时状态机（2026-11-18，L2-B）
# 只做"选边推进"：current_id + 下一层候选 + consumed 记录。
# 无 14×9 坐标 / 回合 / 巡逻 / 陷阱 / 回访 / 镜头 —— 这些是旧开放网格的概念。
#
# 与 MapRuntime 并列，由 BoardSystem 根据 data.branch 选择委托；旧网格路径零改动。
# ============================================================================

var board: Dictionary = {}
var current_id: String = ""
var consumed: Dictionary = {}       # node_id -> true（进入即消耗，不可回访）
var path: Array[String] = []        # 本幕走过的节点序列（可视化 / 日志）
var feedback: String = ""
var act: int = 1
# 兼容字段：BoardSystem.summary() 等门面会读这些（旧 MapRuntime 同名）。
# 分岔图无回合/坐标概念，battles 按战斗节点记录，visits 复用 consumed，turn 恒 0。
var battles: Dictionary = {}        # node_id -> {type}
var visits: Dictionary = {}         # node_id -> 次数（每次进入 +1）
var turn: int = 0


# 从 MapBoardBuilder.build_branch() 的数据初始化。
func setup(data: Dictionary) -> void:
	board = data
	current_id = String(data.get("start_id", ""))
	act = int(data.get("act", 1))
	consumed.clear()
	path.clear()
	feedback = ""
	battles.clear()
	visits.clear()
	turn = 0
	consumed[current_id] = true
	path.append(current_id)
	visits[current_id] = 1


# 当前节点字典。
func current_node() -> Dictionary:
	var by_id: Dictionary = board.get("by_id", {})
	return by_id.get(current_id, {})


# 下一层可选节点（连线终点）。分岔图只能向前，不能回头。
func legal_targets() -> Array:
	var cur := current_node()
	var out: Array = []
	var by_id: Dictionary = board.get("by_id", {})
	for nid in cur.get("next", []):
		if by_id.has(nid):
			out.append(by_id[nid])
	return out


# 是否可以进入某节点：必须是当前节点的下一层连线终点。
func can_advance_to(id: String) -> bool:
	var cur := current_node()
	return cur.get("next", []).has(id)


# 沿边推进到 id。返回 {ok, reason, node}。
# 成功时更新 current_id / path / consumed；分岔图无回访（已消耗节点不可再进）。
func advance_to(id: String) -> Dictionary:
	if not can_advance_to(id):
		return {"ok": false, "reason": "not_in_next_layer", "node": {}}
	if consumed.has(id):
		return {"ok": false, "reason": "already_consumed", "node": {}}
	var by_id: Dictionary = board.get("by_id", {})
	var node: Dictionary = by_id.get(id, {})
	if node.is_empty():
		return {"ok": false, "reason": "node_missing", "node": {}}
	current_id = id
	path.append(id)
	consumed[id] = true
	visits[id] = int(visits.get(id, 0)) + 1
	turn += 1
	var t: String = String(node.get("type", ""))
	if t in ["battle", "elite", "boss"]:
		battles[id] = {"type": t}
	# 非战斗节点的结算反馈由 controller 填充；这里只标记进入。
	if t in ["chest", "armory", "shop", "rest", "event"]:
		feedback = "进入%s" % String(node.get("title", t))
	return {"ok": true, "reason": "ok", "node": node}


# 是否已到达 BOSS（当前节点即 boss）。
func current_is_boss() -> bool:
	return String(current_node().get("type", "")) == "boss"


# 路径摘要（run_journal / 可视化用）。
func summary() -> Dictionary:
	return {
		"act": act,
		"path": path.duplicate(),
		"current_id": current_id,
		"consumed_count": consumed.size(),
		"boss_id": String(board.get("boss_id", "")),
	}
