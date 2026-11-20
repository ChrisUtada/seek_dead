class_name CircuitSystem
extends RefCounted

# ============================================================================
# 本局回路系统（G4-2，2026-11-20）
#
# 权威方案 §5.3「固有牌谱 / 本局回路双层结构」+ G4-2「回路状态、2 槽替换、
# 触发限制和来源日志」。
#
# 回路 ≠ 牌谱：牌谱由装备驱动、固有、不占槽；回路由战后三选一获得、按声明事件
# 触发、最多占 2 槽。详见 docs/G4-1_结算顺序契约_2026-11-20.md。
#
# 由 controller 在 _ready 实例化并注入：CircuitSystem.new(ctrl)。
# 首版回路定义为代码内白名单（G4-3 再扩到 ≥6 并资源化）；不做开放递归脚本。
# ============================================================================

const MAX_SLOTS := 2

# 回路定义表（首版 3 个不同事件原型，G4-3 扩到 ≥6）。
# event: 白名单触发事件名；payout: 赔付类型（由结算层解释，本系统只记录"该触发"）；
# limits: {spin, turn, room} 每SPIN/回合/房间上限；chain: 是否允许由追加结果再次触发。
const DEFINITIONS: Dictionary = {
	"circuit_triple_echo": {
		"name": "三连回响", "event": "triple", "target": "damage",
		"payout": "bonus_damage", "limits": {"spin": 1, "turn": 2, "room": 8}, "chain": false,
		"desc": "同族三连时追加一次固定伤害回响",
	},
	"circuit_status_react": {
		"name": "状态反应", "event": "status_applied", "target": "status",
		"payout": "extra_stack", "limits": {"spin": 1, "turn": 3, "room": 10}, "chain": false,
		"desc": "施加状态时额外叠一层",
	},
	"circuit_armor_break": {
		"name": "破甲余波", "event": "armor_break", "target": "damage",
		"payout": "pierce_damage", "limits": {"spin": 1, "turn": 1, "room": 5}, "chain": false,
		"desc": "破甲时追加穿透伤害",
	},
}

var _ctrl: DuelController
var inventory: Array[String] = []        # 本局拥有的回路 id（仓库）
var equipped: Array[String] = []         # 当前装备（最多 MAX_SLOTS）
var log: Array[Dictionary] = []           # 来源日志：每次触发记录 {id, event, spin, turn, room, acked}
var _count_spin: Dictionary = {}          # id → 本SPIN触发次数
var _count_turn: Dictionary = {}          # id → 本回合触发次数
var _count_room: Dictionary = {}          # id → 本房间触发次数
var _resolving := false                   # 递归防护：结算追加结果时不再触发回路


func _init(ctrl: DuelController) -> void:
	_ctrl = ctrl


# ---------------------------------------------------------------------------
# 仓库与 2 槽
# ---------------------------------------------------------------------------

func acquire(id: String) -> bool:
	if not DEFINITIONS.has(id) or inventory.has(id):
		return false
	inventory.append(id)
	return true


func equip(id: String, replace_id: String = "") -> Dictionary:
	"""装备回路。槽未满直接装；槽满须指定 replace_id（必须在 equipped 中）。
	返回 {ok: bool, reason: String}。"""
	if not inventory.has(id):
		return _fail("not_in_inventory")
	if equipped.has(id):
		return _fail("already_equipped")
	if equipped.size() < MAX_SLOTS:
		equipped.append(id)
		return _ok()
	if replace_id.is_empty() or not equipped.has(replace_id):
		return _fail("need_replace")
	equipped[equipped.find(replace_id)] = id
	return _ok()


func unequip(id: String) -> bool:
	if not equipped.has(id):
		return false
	equipped.erase(id)
	return true


# ---------------------------------------------------------------------------
# 触发与限制
# ---------------------------------------------------------------------------

# 尝试触发某事件。返回本次"应触发"的回路 id 数组（结算层据此应用 payout）。
# 只响应白名单原始事件；递归防护期间直接返回空。
func try_trigger(event: String) -> Array[String]:
	if _resolving or event.is_empty():
		return []
	var fired: Array[String] = []
	for id in equipped:
		if not DEFINITIONS.has(id):
			continue
		var def: Dictionary = DEFINITIONS[id]
		if String(def["event"]) != event:
			continue
		if not _within_limits(id, def):
			continue
		_bump(id)
		fired.append(id)
		log.append({"id": id, "event": event,
			"spin": int(_count_spin.get(id, 0)), "turn": int(_count_turn.get(id, 0)),
			"room": int(_count_room.get(id, 0))})
	return fired


# 在结算层应用回路追加结果时调用：期间 try_trigger 不再触发（防自触发/递归）。
func begin_resolve() -> void:
	_resolving = true


func end_resolve() -> void:
	_resolving = false


func _within_limits(id: String, def: Dictionary) -> bool:
	var limits: Dictionary = def.get("limits", {})
	if limits.has("spin") and int(_count_spin.get(id, 0)) >= int(limits["spin"]):
		return false
	if limits.has("turn") and int(_count_turn.get(id, 0)) >= int(limits["turn"]):
		return false
	if limits.has("room") and int(_count_room.get(id, 0)) >= int(limits["room"]):
		return false
	return true


func _bump(id: String) -> void:
	_count_spin[id] = int(_count_spin.get(id, 0)) + 1
	_count_turn[id] = int(_count_turn.get(id, 0)) + 1
	_count_room[id] = int(_count_room.get(id, 0)) + 1


# ---------------------------------------------------------------------------
# 生命周期重置（与 controller 阶段对齐）
# ---------------------------------------------------------------------------

func reset_spin() -> void:
	_count_spin.clear()


func reset_turn() -> void:
	_count_turn.clear()
	reset_spin()


func reset_room() -> void:
	_count_room.clear()
	reset_turn()


func reset_run() -> void:
	inventory.clear()
	equipped.clear()
	log.clear()
	reset_room()


# ---------------------------------------------------------------------------
# 查询（构筑摘要 / 调试）
# ---------------------------------------------------------------------------

func definition(id: String) -> Dictionary:
	return DEFINITIONS.get(id, {})


# G4-4 可达性：该回路声明的事件在当前构筑下是否"可能产生"。
# 与"本回合是否已触发"不同——可达性是构筑层判定，用于过滤"合法展示但整局无法触发"的死回路。
# 返回 {ok: bool, reason: String}。
func is_reachable(id: String) -> Dictionary:
	var def: Dictionary = DEFINITIONS.get(id, {})
	if def.is_empty():
		return {"ok": false, "reason": "unknown_id"}
	if _ctrl == null:
		return {"ok": false, "reason": "no_controller"}
	var event: String = String(def.get("event", ""))
	var reason: String = _event_source_reason(event)
	if reason.is_empty():
		return {"ok": true, "reason": ""}
	return {"ok": false, "reason": reason}


# 事件源可达性判定：当前构筑是否具备产生该事件的条件。
# 三连→需某符号族格数≥3；状态→需 status 类符号；破甲→需破甲机制或重武器三连。
func _event_source_reason(event: String) -> String:
	var pool: Array = _ctrl.pool_items if _ctrl.pool_items != null else []
	if pool.is_empty():
		return "event_unreachable:empty_pool"
	match event:
		"triple":
			# 任一符号族的聚合格数 ≥3（用基础权重 round，与 cells_for 同口径）
			var agg: Dictionary = {}
			for it in pool:
				if not (it is Dictionary):
					continue
				for s in it.get("syms", []):
					if not (s is Array) or s.is_empty() or s[0] == null:
						continue
					var key: String = String(s[0].resource_path) + "|" + String(s[2])
					agg[key] = float(agg.get(key, 0.0)) + maxf(0.0, float(s[1]))
			for k in agg:
				if ReelSystem.cells_for(float(agg[k])) >= 3:
					return ""
			return "event_unreachable:no_triple_source"
		"status_applied":
			for it in pool:
				if not (it is Dictionary):
					continue
				for s in it.get("syms", []):
					if not (s is Array) or s.is_empty() or s[0] == null:
						continue
					if String(s[0].kind) == "status" and float(s[1]) > 0.0:
						return ""
			return "event_unreachable:no_status_source"
		"armor_break":
			# 破甲机制武器（_item_pierce_map 有 true）或重武器三连（选 >=3 格的重武器符号）
			for k in _ctrl._item_pierce_map:
				if bool(_ctrl._item_pierce_map[k]):
					return ""
			# 重武器三连兜底：有重武器 archetype 的符号族 ≥3 格
			for it in pool:
				if not (it is Dictionary):
					continue
				for s in it.get("syms", []):
					if not (s is Array) or s.size() < 4 or s[0] == null:
						continue
					var wid: String = String(s[3]) if s.size() > 3 else ""
					if wid != "" and int(_ctrl._source_archetype_map.get(wid, -1)) == WeaponData.Archetype.HEAVY \
						and ReelSystem.cells_for(float(s[1])) >= 3:
						return ""
			return "event_unreachable:no_pierce_source"
		_:
			return "event_unreachable:unknown_event"
	return ""


# G4-4 可达性报告：所有回路的当前可达状态，供 G4-6 门槛验收与构筑摘要。
func reachability_report() -> Dictionary:
	var out: Dictionary = {}
	for id in DEFINITIONS:
		var r: Dictionary = is_reachable(id)
		out[id] = {
			"reachable": bool(r["ok"]),
			"reason": String(r["reason"]),
			"owned": inventory.has(id),
			"equipped": equipped.has(id),
		}
	return out


func why_not_triggered(id: String) -> String:
	"""G4-4 调试信息：为什么该回路当前未触发（可达性优先于上限与等待事件）。"""
	if not equipped.has(id):
		return "not_equipped"
	var def: Dictionary = DEFINITIONS.get(id, {})
	if def.is_empty():
		return "unknown_id"
	# 可达性优先：事件源构不成的死回路，比"等待事件"更根本
	var reach: Dictionary = is_reachable(id)
	if not bool(reach["ok"]):
		return String(reach["reason"])
	var limits: Dictionary = def.get("limits", {})
	if limits.has("spin") and int(_count_spin.get(id, 0)) >= int(limits["spin"]):
		return "spin_limit"
	if limits.has("turn") and int(_count_turn.get(id, 0)) >= int(limits["turn"]):
		return "turn_limit"
	if limits.has("room") and int(_count_room.get(id, 0)) >= int(limits["room"]):
		return "room_limit"
	return "waiting_for_event:" + String(def["event"])


func _ok() -> Dictionary:
	return {"ok": true, "reason": ""}


func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
