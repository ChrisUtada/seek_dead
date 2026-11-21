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
# S5-4：收藏里程碑常量从 AnvilSystem 迁入 CareerSystem（配置字段沿用 balance_config）
const BALANCE = preload("res://resources/config/balance_config.tres")

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
# S5-1：生涯成为唯一定向解锁账本。
# _directed_balance 为唯一可用余额（旧 anvil.directed_unlocks 与 career.unlock_charges 迁移后归一）。
var _directed_balance := 0
var _directed_claimed: Array[String] = []
# 迁移标记：meta.career.directed_v1 为 true 时不再重复折算老档
const MIGRATION_FLAG := "directed_v1"

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
	# S5-1：读取统一余额；兼容旧存档 unlock_charges 字段（历史证据）。
	_directed_balance = maxi(0, int(raw.get("directed_balance", raw.get("unlock_charges", 0))))
	var claimed = raw.get("directed_claimed", [])
	if claimed is Array:
		for p in claimed:
			var sp := String(p)
			if sp != "" and not _directed_claimed.has(sp):
				_directed_claimed.append(sp)
	_migrate_legacy_directed(raw)
	_write()


# S5-1 老档一次性迁移：把 anvil.directed_unlocks 与 career.unlock_charges 归一到生涯单账本。
# 口径（不宣称完美去重）：余额取两边较大值而非求和（BOSS/首通曾双写）；
# directed_claimed / collection_milestones / 生涯成就与 Boss 记录并集；不恢复已消耗历史额度。
# 老点数每 10 点折算 1 次（若 meta_store 尚未折算则在此补算），迁移成功后写 flag，重复加载不再发放。
func _migrate_legacy_directed(raw: Dictionary) -> void:
	if bool(raw.get(MIGRATION_FLAG, false)):
		return
	var old_anvil: int = maxi(0, int(_ctrl.meta.get("directed_unlocks", 0)))
	var old_career: int = maxi(0, int(raw.get("unlock_charges", 0)))
	_directed_balance = maxi(_directed_balance, maxi(old_anvil, old_career))
	# 老点数折算（若 meta_store 的 G7-3 折算已写 directed_unlocks 则不再重复计算）
	var legacy_points: int = int(_ctrl.meta.get("anvil_points", 0))
	var converted: int = legacy_points / 10
	if old_anvil <= 0 and old_career <= 0 and converted > 0:
		_directed_balance = maxi(_directed_balance, converted)
	# 已领取记录并集：anvil.directed_claimed + meta.collection_milestones（后者作为已达成标记，非额度）
	var old_claimed = _ctrl.meta.get("directed_claimed", [])
	if old_claimed is Array:
		for p in (old_claimed as Array):
			var sp := String(p)
			if sp != "" and not _directed_claimed.has(sp):
				_directed_claimed.append(sp)
	# 写迁移标记到 meta.career
	raw[MIGRATION_FLAG] = true
	if _ctrl.hud != null:
		_ctrl.hud._log("生涯定向解锁迁移：旧账本 %d/%d、老点 %d → 统一余额 %d（取较大值，不求和）" % [
			old_anvil, old_career, legacy_points, _directed_balance])
	# 立即落盘，防重复迁移
	_save()


func _write() -> void:
	_ctrl.meta[META_KEY] = {
		"unlocked": _unlocked.duplicate(),
		"bosses": _bosses.duplicate(),
		"directed_balance": _directed_balance,
		"directed_claimed": _directed_claimed.duplicate(),
		"unlock_charges": _directed_balance,   # S5-1：旧字段镜像统一余额（只读兼容，不再独立更新）
		MIGRATION_FLAG: true,
	}


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
# 定向解锁：成就积攒「未拥有装备三选一」机会，不新增货币。
# ---------------------------------------------------------------------------

func unlock_charges() -> int:
	return _directed_balance


func has_unlock_charge() -> bool:
	return _directed_balance > 0


# S5-1：生涯统一账本 API。旧 AnvilSystem 定向 API 转发到此处，避免双写双领。
func available_directed() -> int:
	return _directed_balance


func earn_directed(reason: String) -> bool:
	if reason.is_empty():
		return false
	_directed_balance += 1
	_save()
	if _ctrl.hud != null:
		_ctrl.hud._log("定向解锁 +1（来源：%s，当前 %d）" % [reason, _directed_balance])
	return true


# 确定性全候选：全部未拥有的武器/护符/技能（含技能，排除 BOSS 信物），按已有候选格式返回。
func directed_candidates() -> Array:
	var out: Array = []
	var owned_w: Array = _ctrl.meta.get("owned_weapons", [])
	var owned_c: Array = _ctrl.meta.get("owned_charms", [])
	var owned_a: Array = _ctrl.meta.get("owned_consumables", [])
	var owned_s: Array = _ctrl.meta.get("owned_skills", [])
	for p in _ctrl.WEAPON_POOL:
		if owned_w.has(p): continue
		var d = load(String(p))
		if d == null: continue
		out.append(_candidate_entry(String(p)))
	for p in _ctrl.ITEM_POOL:
		var d = load(String(p))
		if not (d is ItemData): continue
		if _ctrl._meta_store._is_boss_relic(d, String(p)): continue
		if d.category == "passive" and owned_c.has(p): continue
		if d.category == "active" and owned_a.has(p): continue
		out.append(_candidate_entry(String(p)))
	for p in _ctrl.SKILL_POOL:
		if owned_s.has(p): continue
		out.append(_candidate_entry(String(p)))
	return out


# 唯一 claim：花 1 次额度解锁指定内容，返回 {ok, reason}。
func claim_directed(path: String) -> Dictionary:
	if _directed_balance <= 0:
		return {"ok": false, "reason": "no_unlock_available"}
	if path.is_empty() or ResourceLoader.load(path) == null:
		return {"ok": false, "reason": "invalid_path"}
	var valid := false
	for c in directed_candidates():
		if String(c["path"]) == path:
			valid = true
			break
	if not valid:
		# 明确空池/无效原因，区分已拥有与不在池
		if _is_owned_path(path):
			return {"ok": false, "reason": "already_owned"}
		return {"ok": false, "reason": "not_in_pool"}
	if not _directed_claimed.has(path):
		_directed_claimed.append(path)
	# S5-1 过渡兼容：顶层 directed_claimed 镜像（真源在 meta.career.directed_claimed，S5-4 清理）
	var legacy_claimed = _ctrl.meta.get("directed_claimed", [])
	if not (legacy_claimed is Array): legacy_claimed = []
	if not (legacy_claimed as Array).has(path):
		(legacy_claimed as Array).append(path)
		_ctrl.meta["directed_claimed"] = legacy_claimed
	_grant_directed_owned(path)
	_directed_balance -= 1
	_save()
	if _ctrl.hud != null:
		_ctrl.hud._log("定向解锁：%s（剩余 %d 次）" % [path.get_file().get_basename(), _directed_balance])
	return {"ok": true, "reason": ""}


func _is_owned_path(path: String) -> bool:
	var res = load(path)
	if res is WeaponData: return (_ctrl.meta.get("owned_weapons", []) as Array).has(path)
	if res is SkillData: return (_ctrl.meta.get("owned_skills", []) as Array).has(path)
	if res is ItemData:
		if res.category == "passive": return (_ctrl.meta.get("owned_charms", []) as Array).has(path)
		if res.category == "active": return (_ctrl.meta.get("owned_consumables", []) as Array).has(path)
	return false


func _grant_directed_owned(path: String) -> void:
	var res = load(path)
	var key := ""
	if res is WeaponData: key = "owned_weapons"
	elif res is SkillData: key = "owned_skills"
	elif res is ItemData:
		if res.category == "passive": key = "owned_charms"
		elif res.category == "active": key = "owned_consumables"
	if key == "": return
	var arr: Array = _ctrl.meta.get(key, [])
	if not arr.has(path):
		arr.append(path)
		_ctrl.meta[key] = arr


# 3 个合法未拥有候选：优先武器/护符/消耗品各一，再补齐；排除 BOSS 信物。
func roll_unlock_candidates(n: int = 3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _directed_balance <= 0:
		return out
	var pool := _unlock_pool()
	if pool.is_empty():
		return out
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for kind in ["weapon", "passive", "active"]:
		if out.size() >= n:
			break
		var sub: Array[String] = []
		for p in pool:
			if _kind_of(p) == kind:
				sub.append(p)
		if sub.is_empty():
			continue
		var pick: String = sub[rng.randi_range(0, sub.size() - 1)]
		out.append(_candidate_entry(pick))
		pool.erase(pick)
	while out.size() < n and not pool.is_empty():
		var pick: String = pool[rng.randi_range(0, pool.size() - 1)]
		out.append(_candidate_entry(pick))
		pool.erase(pick)
	return out


# 选中后立即写入图鉴与开局拥有池；一次机会只结算一次。
func grant_unlock(path: String) -> bool:
	# S5-1：统一转发到生涯单账本 claim，避免与 anvil claim 双领。
	return bool(claim_directed(path).get("ok", false))


func _unlock_pool() -> Array[String]:
	var out: Array[String] = []
	var owned_w: Array = _ctrl.meta.get("owned_weapons", [])
	var owned_c: Array = _ctrl.meta.get("owned_charms", [])
	var owned_a: Array = _ctrl.meta.get("owned_consumables", [])
	for p in _ctrl.WEAPON_POOL:
		if not owned_w.has(p):
			out.append(String(p))
	for p in _ctrl.ITEM_POOL:
		var d = load(String(p))
		if not d is ItemData:
			continue
		if _ctrl._meta_store._is_boss_relic(d, String(p)):
			continue
		if d.category == "passive" and owned_c.has(p):
			continue
		if d.category == "active" and owned_a.has(p):
			continue
		out.append(String(p))
	return out


func _kind_of(path: String) -> String:
	var d = load(path)
	if d is WeaponData:
		return "weapon"
	if d is ItemData:
		return String(d.category)
	return ""


func _candidate_entry(path: String) -> Dictionary:
	var res = load(path)
	if res == null:
		return {}
	var kind := _kind_of(path)
	var name := ""
	var icon := "◆"
	var desc := ""
	var art = res.get("art")
	if art == null:
		art = res.get("icon_tex")
	if res is WeaponData:
		name = String(res.weapon_name)
		if res.symbols != null and res.symbols.size() > 0:
			var sw = res.symbols[0]
			if sw != null and sw.symbol != null and String(sw.symbol.label) != "":
				icon = String(sw.symbol.label)
		var elem := ElementCounter.label(String(res.element))
		var elem_txt := "" if elem == "" or elem == "无" else " · " + elem
		desc = "武器%s · 攻%d · 命中%d%%" % [elem_txt, int(res.base_power), int(round(res.hit_rate * 100.0))]
	elif res is SkillData:
		# S5-1：技能候选（SkillData 无 item_name 字段）
		name = String(res.get("buff_name")) if res.get("buff_name") != null else path.get_file().get_basename()
		desc = "技艺"
		var sd = String(res.get("description")) if res.get("description") != null else ""
		if sd.length() > 28: sd = sd.left(28) + "…"
		if sd != "": desc += " · " + sd
	else:
		name = String(res.item_name)
		icon = String(res.icon) if String(res.icon) != "" else "◆"
		var kind_label := "护符" if kind == "passive" else "消耗品"
		desc = kind_label
		var elem := ElementCounter.label(String(res.element))
		if elem != "" and elem != "无":
			desc += " · " + elem
		var short := String(res.description)
		if short.length() > 28:
			short = short.left(28) + "…"
		if short != "":
			desc += " · " + short
	if name == "":
		name = path.get_file().get_basename()
	return {
		"path": path, "kind": kind, "name": name, "icon": icon,
		"desc": desc, "tip": ItemTooltip.for_resource(res), "art": art,
	}


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
		# S5-1：BOSS 首杀额度统一由下方成就（first_clear 等）发放，
		# 不再单独 +1——原 BOSS 首杀与首通成就属同一事件的两笔账（双写）。

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
		var id := _unlocked[i]
		_announce(id)
		# S5-1：里程碑额度由 _unlock() 内 earn_directed 统一发放，不再独立 +1（消灭双写）

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
		_unlock("four_hunters")   # S5-1：额度由 _unlock() 内 earn_directed 统一发放
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
	# S5-1：仅定向额度类成就发放（对齐原 first_clear/four_hunters 语义，避免全成就滥发）
	if id == "first_clear" or id == "four_hunters":
		earn_directed("career:%s" % id)
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


# ---------------------------------------------------------------------------
# S5-4：收藏查询与里程碑基座（原 AnvilSystem 共享功能迁入）
# 供商店/奖励/BOSS 战利品写入收藏后结算里程碑；图鉴/整备只读收藏度。
# ---------------------------------------------------------------------------

func collection_pool() -> Array:
	var pool := []
	for p in _ctrl.WEAPON_POOL:
		pool.append(p)
	for p in _ctrl.ITEM_POOL:
		var d = load(p)
		if d is ItemData and d.category == "passive":
			if _ctrl._meta_store._is_boss_relic(d, p):
				continue
			pool.append(p)
	for p in _ctrl.SKILL_POOL:
		pool.append(p)
	return pool


func is_collection_owned(p: String) -> bool:
	return _ctrl.meta["owned_weapons"].has(p) or _ctrl.meta["owned_charms"].has(p) \
		or _ctrl.meta["owned_consumables"].has(p) or _ctrl.meta["owned_skills"].has(p)


func grant_collection_owned(p: String) -> void:
	var res = load(p)
	if res is WeaponData:
		if not _ctrl.meta["owned_weapons"].has(p):
			_ctrl.meta["owned_weapons"].append(p)
	elif res is SkillData:
		if not _ctrl.meta["owned_skills"].has(p):
			_ctrl.meta["owned_skills"].append(p)
		_ctrl._meta_store.record_source(p, _ctrl._item_source())
	elif res is ItemData:
		if res.category == "passive":
			_ctrl._reward_system.remember_charm(p)
		else:
			if not _ctrl.meta["owned_consumables"].has(p):
				_ctrl.meta["owned_consumables"].append(p)


func collection_pct() -> float:
	var pool = collection_pool()
	if pool.is_empty():
		return 1.0
	var owned := 0
	for p in pool:
		if is_collection_owned(p):
			owned += 1
	return float(owned) / float(pool.size())


func check_collection_milestones() -> void:
	var pct = collection_pct()
	for i in BALANCE.anvil_milestone_pct.size():
		var thr = BALANCE.anvil_milestone_pct[i]
		if pct >= thr and not _ctrl.meta["collection_milestones"].has(i):
			_ctrl.meta["collection_milestones"].append(i)
			var bonus = int(BALANCE.anvil_milestone_bonus[i])
			var unlocks: int = maxi(1, bonus / 10)
			for j in range(unlocks):
				earn_directed("milestone")
			if _ctrl.hud != null:
				_ctrl.hud._log("收藏里程碑 %.0f%%：定向解锁 +%d（可自选装备）" % [thr * 100, unlocks])
