class_name AnvilSystem
extends RefCounted

# T22：平衡常量收敛于 BalanceConfig（balance_config.tres，与 ShopConfig 同模式）
const BALANCE = preload("res://resources/config/balance_config.tres")

# M6 铁砧锻造（gacha：摇奖 / 保底 / 图鉴里程碑 / 点数 drip）——从 duel_controller.gd 抽出。
#
# 由 controller 在 _ready 处实例化并注入：AnvilSystem.new(ctrl)。
# 约定（与 docs/[已完成]duel_controller拆分方案B.md 步骤2一致，并延续步骤1 MetaStore 的写法）：
# - meta 不随本子系统走，统一经 _ctrl.meta 访问与改写，改写后经 _ctrl._meta_store.save_meta() 落盘
#   （保持 controller 单一持有 meta，避免"只读快照不可写回"类 bug）。
# - @export 常量（ANVIL_ROLL_COST / ANVIL_BLANK_CHANCE / ANVIL_PITY_MAX / ANVIL_PER_RUN_CAP /
#   ANVIL_DUPE_REFUND / ANVIL_RARITY_WEIGHT / ANVIL_MILESTONE_PCT / ANVIL_MILESTONE_BONUS）
#   留 controller（RefCounted 无法在 Inspector 编辑），本子系统动态读 _ctrl.xxx。
# - 跨系统联动（授予后刷新 UI 等）留在 controller 编排层；本子系统不互调其他子系统。
# - ctrl 标类型 DuelController（已加 class_name），成员访问获得编译期检查。

var _ctrl: DuelController          # DuelController 实例（类型标注，编译期检查）
var anvil_run_awarded: int = 0   # 本局铁砧点数 drip 累计（不持久，_full_reset 调 reset_run 清零）
var last_anvil_drops: Array[Dictionary] = []   # 最近一次铁砧摇动结果（非持久，仅供 UI 显示）

func _init(ctrl: DuelController) -> void:
	_ctrl = ctrl


# ---------------------------------------------------------------------------
# 公共编排入口
# ---------------------------------------------------------------------------

# 纯 gacha 一次：扣点 → 摇单格 → 结算 → 写 last_anvil_drops（单格结果）→ 落盘。
# 返回 drops 数组（单格）；点数不足时日志并返回空数组（调用方据此提前 return）。
func roll_anvil() -> Array:
	if _ctrl.meta["anvil_points"] < BALANCE.anvil_roll_cost:
		_ctrl.hud._log("铁砧点数不足（需 %d）" % BALANCE.anvil_roll_cost)
		return []
	_ctrl.meta["anvil_points"] -= BALANCE.anvil_roll_cost
	var result = _roll_anvil_cell()           # 摇出单格结果（含 blank 可能）
	_resolve_anvil_drop(result)               # 结算一次：授予 / 返还 / 保底计数
	result["cell"] = 0
	var drops: Array[Dictionary] = [result]
	last_anvil_drops = drops
	_ctrl._meta_store.save_meta()
	return drops


# 新一局清零本局 drip 累计（对应原 _full_reset 的 anvil_run_awarded = 0）。
func reset_run() -> void:
	anvil_run_awarded = 0


# ---------------------------------------------------------------------------
# 公开查询（anvil_screen 渲染入口；UI 不再穿透 _anvil_* 私有方法）
# ---------------------------------------------------------------------------

# 铁砧图鉴/抽奖展示数据：池 / 显示名表 / 已拥有 / 全池 / 未拥有 / 收集百分比。
func collection_info() -> Dictionary:
	var pool = _anvil_pool()
	var owned := 0
	for p in pool:
		if _anvil_is_owned(p):
			owned += 1
	var names := []
	for p in pool:
		names.append(_anvil_drop_for(p)["name"])
	return {
		"pool": pool,
		"names": names,
		"owned": owned,
		"total": pool.size(),
		"not_yet": pool.size() - owned,
		"pct": float(owned) / float(pool.size()) if pool.size() > 0 else 1.0,
	}


# ---------------------------------------------------------------------------
# 房间通关发放铁砧点数（Hades 式 drip）——is_boss 给额外奖励
# ---------------------------------------------------------------------------

func award_meta(is_boss: bool) -> void:
	var amt: int = 5
	if not is_boss:
		var kind = "normal"
		if _ctrl.room_index >= 0 and _ctrl.room_index < _ctrl.ROOMS.size():
			kind = _ctrl.ROOMS[_ctrl.room_index].kind
		amt = 3 if kind == "elite" else 1
	var remain = BALANCE.anvil_per_run_cap - anvil_run_awarded
	if remain <= 0:
		_ctrl.hud._log("铁砧点数本局已达上限 %d（本次 +0）" % BALANCE.anvil_per_run_cap)
		return
	amt = mini(amt, remain)
	anvil_run_awarded += amt
	_ctrl.meta["anvil_points"] += amt
	_ctrl._meta_store.save_meta()
	_ctrl.hud._log("铁砧点数 +%d（本局 %d/%d，共 %d）" % [amt, anvil_run_awarded, BALANCE.anvil_per_run_cap, _ctrl.meta["anvil_points"]])


# ---------------------------------------------------------------------------
# 摇奖核心
# ---------------------------------------------------------------------------

func _roll_anvil_cell() -> Dictionary:
	# 单格：10% 空白；保底触发且仍有未拥有 → 强制从 not-yet-owned 抽；否则按 rarity 加权抽
	if randf() < BALANCE.anvil_blank_chance:
		return {"kind": "blank"}
	var pool = _anvil_pool()
	var not_yet = _anvil_not_yet_owned(pool)
	if _ctrl.meta["anvil_pity"] >= BALANCE.anvil_pity_max and not_yet.size() > 0:
		var p = not_yet[randi() % not_yet.size()]
		return _anvil_drop_for(p)
	var total := 0.0
	var weights := []
	for p in pool:
		var w = _anvil_rarity_weight(p)
		weights.append(w)
		total += w
	var r := randf() * total
	var acc := 0.0
	for i in pool.size():
		acc += weights[i]
		if r <= acc:
			return _anvil_drop_for(pool[i])
	return _anvil_drop_for(pool[pool.size() - 1])


func _anvil_drop_for(p: String) -> Dictionary:
	var res = load(p)
	var kind := "weapon"
	var rarity := "common"
	var name := p.get_file().get_basename()
	if res != null and "rarity" in res:
		rarity = res.rarity
	if res is WeaponData:
		kind = "weapon"
		name = res.weapon_name
	elif res is SkillData:
		kind = "skill"
		name = res.buff_name
	elif res is ItemData:
		kind = res.category
		name = res.item_name
	return {"kind": kind, "path": p, "rarity": rarity, "name": name}


func _anvil_rarity_weight(p: String) -> float:
	var res = load(p)
	var r := "common"
	if res != null and "rarity" in res:
		r = res.rarity
	return float(BALANCE.anvil_rarity_weight.get(r, BALANCE.anvil_rarity_weight["common"]))


func _anvil_pool() -> Array:
	# 铁砧池 = 武器 + 护符(passive) 仅此两类；消耗品(active)/技能不进池（设计：铁砧只产武器或护符）
	var pool := []
	for p in _ctrl.WEAPON_POOL:
		pool.append(p)
	for p in _ctrl.ITEM_POOL:
		var d = load(p)
		if d is ItemData and d.category == "passive":
			pool.append(p)
	return pool


func _anvil_is_owned(p: String) -> bool:
	return _ctrl.meta["owned_weapons"].has(p) or _ctrl.meta["owned_charms"].has(p) or _ctrl.meta["owned_consumables"].has(p)


func _anvil_not_yet_owned(pool: Array) -> Array:
	var out := []
	for p in pool:
		if not _anvil_is_owned(p):
			out.append(p)
	return out


func _anvil_grant_owned(p: String) -> void:
	var res = load(p)
	if res is WeaponData or res is SkillData:
		if not _ctrl.meta["owned_weapons"].has(p):
			_ctrl.meta["owned_weapons"].append(p)
	elif res is ItemData:
		if res.category == "passive":
			if not _ctrl.meta["owned_charms"].has(p):
				_ctrl.meta["owned_charms"].append(p)
		else:
			if not _ctrl.meta["owned_consumables"].has(p):
				_ctrl.meta["owned_consumables"].append(p)


func _resolve_anvil_drop(d: Dictionary) -> void:
	# 单格结算（仪式感三连只调用一次）：空白跳过；已拥有→按 rarity 返还+保底+1；未拥有→授予+保底清零
	if d["kind"] == "blank":
		d["is_new"] = false
		return
	var p = d["path"]
	if _anvil_is_owned(p):
		var rb = int(BALANCE.anvil_dupe_refund.get(d["rarity"], BALANCE.anvil_dupe_refund["common"]))
		_ctrl.meta["anvil_points"] += rb
		_ctrl.meta["anvil_pity"] += 1
		d["is_new"] = false
		_ctrl.hud._log("铁砧重复：%s（%s，返还 %d 点）" % [d["name"], d["rarity"], rb])
	else:
		_anvil_grant_owned(p)
		_ctrl.meta["anvil_pity"] = 0
		d["is_new"] = true
		_ctrl.hud._log("铁砧新获取：%s（%s）" % [d["name"], d["rarity"]])
	_check_collection_milestones()


func _anvil_collection_pct() -> float:
	var pool = _anvil_pool()
	if pool.is_empty():
		return 1.0
	var owned := 0
	for p in pool:
		if _anvil_is_owned(p):
			owned += 1
	return float(owned) / float(pool.size())


func _check_collection_milestones() -> void:
	var pct = _anvil_collection_pct()
	for i in BALANCE.anvil_milestone_pct.size():
		var thr = BALANCE.anvil_milestone_pct[i]
		if pct >= thr and not _ctrl.meta["collection_milestones"].has(i):
			_ctrl.meta["collection_milestones"].append(i)
			var bonus = int(BALANCE.anvil_milestone_bonus[i])
			_ctrl.meta["anvil_points"] += bonus
			_ctrl.hud._log("收藏里程碑 %.0f%%：铁砧点数 +%d（共 %d）" % [thr * 100, bonus, _ctrl.meta["anvil_points"]])

