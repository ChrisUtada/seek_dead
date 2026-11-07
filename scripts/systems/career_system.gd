class_name CareerSystem
extends RefCounted

# G6-01 最小生涯：首批一次性成就 + 跨局记录（P2）
#
# 职责：
# - 维护成就定义与一次性解锁（写入 meta["career"]，只加不删，老档缺键自动补空）
# - 接收局内事件（BOSS 通关 / 破甲 / 状态伤害 / 精英路线 / 棋盘武器格 / 和解）
# - 向 HUD 与局末界面提供「新解锁」和「下一目标」
#
# 边界：
# - 不修改战斗数值、奖励、掉落、RNG；只读事件与配装，不反向影响结算
# - 成就不发属性，只做生涯标记（奖励方向由后续定向解锁承接）
# - 每局状态（破甲/状态伤害/精英路线）在 reset_run 清零；跨局记录落 meta

const META_KEY := "career"
const STATUS_DAMAGE_TARGET := 25   # 「状态使徒」单场 BOSS 战状态伤害门槛
const GUARD_TARGET := 40           # 「坚守」本局累计格挡门槛

# 顺序 = 生涯面板展示顺序 = next_goal_hint 的优先顺序。
const DEFINITIONS := [
	{"id": "first_clear", "title": "初次深入", "desc": "首次击败任意 ACT1 BOSS",
		"goal": "击败一条尾路的 BOSS"},
	{"id": "four_hunters", "title": "四席猎手", "desc": "累计击败 4 个不同 ACT1 BOSS",
		"goal": "换一条尾路，击败另一个 BOSS"},
	{"id": "same_element", "title": "同系共振", "desc": "用两把同元素武器击败 BOSS",
		"goal": "凑齐两把同元素武器"},
	{"id": "off_element", "title": "异系调度", "desc": "用两把不同元素武器击败 BOSS",
		"goal": "带两把不同元素的武器"},
	{"id": "armor_break", "title": "破甲专家", "desc": "在 BOSS 战触发破甲并获胜",
		"goal": "用带破甲机制的武器凑三连"},
	{"id": "status_apostle", "title": "状态使徒", "desc": "BOSS 战状态伤害 ≥ %d 并获胜" % STATUS_DAMAGE_TARGET,
		"goal": "用灼烧/中毒压 BOSS"},
	{"id": "guardian", "title": "坚守", "desc": "击败 BOSS 时本局格挡 ≥ %d" % GUARD_TARGET,
		"goal": "用护盾/格挡路线打到 BOSS"},
	{"id": "board_treasure", "title": "棋盘寻宝", "desc": "在棋盘武器格获得一把武器",
		"goal": "走一次带武器格的路线"},
	{"id": "elite_route", "title": "高危路线", "desc": "经过精英分支并击败 BOSS",
		"goal": "走精英分支并通关"},
	{"id": "peaceful", "title": "特殊结局", "desc": "以非暴力和解击败 BOSS",
		"goal": "试试不靠伤害的和解条件"},
]

var _ctrl: DuelController
var _unlocked: Array[String] = []
var _bosses: Array[String] = []
var _new_unlocks: Array[String] = []

# 每局临时状态（不落盘）
var _elite_route_seen := false
var _boss_armor_break := false
var _boss_status_damage := 0


func _init(ctrl: DuelController) -> void:
	_ctrl = ctrl
	_load()


# ---------------------------------------------------------------------------
# 存档
# ---------------------------------------------------------------------------

func _load() -> void:
	var raw = _ctrl.meta.get(META_KEY, {})
	if not raw is Dictionary:
		raw = {}
	var unlocked = raw.get("unlocked", [])
	if unlocked is Array:
		for id in unlocked:
			var sid := String(id)
			if not _definition(sid).is_empty() and not _unlocked.has(sid):
				_unlocked.append(sid)
	var bosses = raw.get("bosses", [])
	if bosses is Array:
		for b in bosses:
			var sb := String(b)
			if sb != "" and not _bosses.has(sb):
				_bosses.append(sb)
	_write()


func _write() -> void:
	_ctrl.meta[META_KEY] = {"unlocked": _unlocked.duplicate(), "bosses": _bosses.duplicate()}


func _save() -> void:
	_write()
	if _ctrl._meta_store != null:
		_ctrl._meta_store.save_meta()


# ---------------------------------------------------------------------------
# 查询
# ---------------------------------------------------------------------------

func _definition(id: String) -> Dictionary:
	for d in DEFINITIONS:
		if String(d["id"]) == id:
			return d
	return {}


func has(id: String) -> bool:
	return _unlocked.has(id)


func title_of(id: String) -> String:
	var d := _definition(id)
	return String(d.get("title", id))


func unlocked_count() -> int:
	return _unlocked.size()


func total_count() -> int:
	return DEFINITIONS.size()


func entries() -> Array:
	var out := []
	for d in DEFINITIONS:
		var e: Dictionary = d.duplicate(true)
		e["unlocked"] = has(String(d["id"]))
		out.append(e)
	return out


func boss_count() -> int:
	return _bosses.size()


func had_boss(id: String) -> bool:
	return _bosses.has(id)


# 最靠前的未完成成就目标；全完成时返回空串。
func next_goal_hint() -> String:
	for d in DEFINITIONS:
		if not has(String(d["id"])):
			return String(d.get("goal", ""))
	return ""


# 局末界面取走新解锁（只读一次，避免每次开屏重复展示）。
func take_new_unlocks() -> Array[String]:
	var out := _new_unlocks.duplicate()
	_new_unlocks.clear()
	return out


# ---------------------------------------------------------------------------
# 局内事件
# ---------------------------------------------------------------------------

func reset_run() -> void:
	_elite_route_seen = false
	_boss_armor_break = false
	_boss_status_damage = 0
	_new_unlocks.clear()


func note_elite_route() -> void:
	_elite_route_seen = true


func note_armor_break() -> void:
	if _ctrl._is_boss_room(_ctrl.room_index):
		_boss_armor_break = true


func note_status_damage(amount: int) -> void:
	if amount <= 0:
		return
	if _ctrl._is_boss_room(_ctrl.room_index):
		_boss_status_damage += amount


func note_board_weapon() -> void:
	if _unlock("board_treasure"):
		_announce("board_treasure")
		_save()


func on_boss_cleared() -> void:
	var room := _current_boss_room()
	if room == null:
		return
	var boss_id := _boss_id(room)
	if boss_id != "" and not _bosses.has(boss_id):
		_bosses.append(boss_id)

	var before := _unlocked.size()
	_unlock("first_clear")
	if _bosses.size() >= 4:
		_unlock("four_hunters")

	var elems := _equipped_elements()
	if elems.size() >= 2:
		if elems[0] == elems[1]:
			_unlock("same_element")
		else:
			_unlock("off_element")

	if _boss_armor_break:
		_unlock("armor_break")
	if _boss_status_damage >= STATUS_DAMAGE_TARGET:
		_unlock("status_apostle")
	if _ctrl._telemetry != null and _ctrl._telemetry.damage_blocked >= GUARD_TARGET:
		_unlock("guardian")
	if _ctrl.node_mode and _elite_route_seen:
		_unlock("elite_route")
	if _ctrl.peaceful_win:
		_unlock("peaceful")

	for i in range(before, _unlocked.size()):
		_announce(_unlocked[i])

	# 每场 BOSS 的临时标记只对本场有效；精英路线是本局标记，留给 reset_run。
	_boss_armor_break = false
	_boss_status_damage = 0
	_save()


# 供测试/后续挑战入口：按稳定 ID 记录一个 BOSS（不触发本场配装类成就）。
func record_boss(boss_id: String) -> bool:
	if boss_id == "" or _bosses.has(boss_id):
		return false
	_bosses.append(boss_id)
	if _bosses.size() >= 4:
		_unlock("four_hunters")
	_save()
	return true


# ---------------------------------------------------------------------------
# 内部
# ---------------------------------------------------------------------------

func _unlock(id: String) -> bool:
	if _definition(id).is_empty() or has(id):
		return false
	_unlocked.append(id)
	_new_unlocks.append(id)
	return true


func _announce(id: String) -> void:
	if _ctrl.hud == null:
		return
	var d := _definition(id)
	_ctrl.hud._log("🏅 生涯成就：%s — %s" % [String(d.get("title", id)), String(d.get("desc", ""))])


func _current_boss_room() -> RoomData:
	var i: int = _ctrl.room_index
	if i < 0 or i >= _ctrl.ROOMS.size():
		return null
	var r: RoomData = _ctrl.ROOMS[i]
	if r == null or String(r.kind) != "boss":
		return null
	return r


func _boss_id(room: RoomData) -> String:
	if room.resource_path != "":
		return String(room.resource_path)
	return "name:" + String(room.name)


func _equipped_elements() -> Array[String]:
	var out: Array[String] = []
	for p in _ctrl.selected_loadout:
		var w = load(String(p))
		if w is WeaponData:
			var e := String(w.element)
			if e != "" and e != "none":
				out.append(e)
	return out
