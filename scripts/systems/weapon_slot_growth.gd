extends RefCounted

# ============================================================================
# WeaponSlotGrowth — 双武器槽的通用数值成长（2026-11-15）
# 方案：docs/武器成长与BOSS换装解耦_执行方案_2026-11-15.md §4–§6
#
# 边界：
# - 只负责本局两个武器槽的通用铭印（锋铸 / 校准 / 暴虐），不碰 UI、奖励、存档；
# - 熟练、调律、横向铸式仍归 WeaponMastery / ForgeStyleSystem，本类不复制它们；
# - 槽位是「战斗位置」，不是武器身份：换装后新武器立刻继承该槽的通用成长，
#   被换下的武器不带走、也不留下任何数值；
# - 预算在整局内不随换装重置，卸下再装回同样不刷新。
# ============================================================================

const SLOT_COUNT := 2
# 每槽最多 2 次通用数值铭印（锋铸 / 校准 / 暴虐共享），同一种最多 2 次。
const BUDGET_TOTAL := 2
const BUDGET_PER_KIND := 2
const FORGE_STEP := 2          # 每级基础攻击
const HIT_STEP := 0.05         # 每级命中率
const CRIT_STEP := 0.25        # 每级三连暴击倍率
const KINDS := ["forge", "calibrate", "tyrant"]

var _slots: Array = []


func _init() -> void:
	reset_run()


# 新一局：两槽清零。只清本局槽位成长，不动图鉴 / 历史最高熟练 / 横向铸式。
func reset_run() -> void:
	_slots.clear()
	for i in SLOT_COUNT:
		_slots.append({"forge": 0, "calibrate": 0, "tyrant": 0})


func _slot(index: int) -> Dictionary:
	if index < 0 or index >= _slots.size():
		return {}
	return _slots[index]


func valid_slot(index: int) -> bool:
	return index >= 0 and index < _slots.size()


# 该槽已消耗的通用铭印总次数。
func total(index: int) -> int:
	var s: Dictionary = _slot(index)
	if s.is_empty():
		return 0
	var n := 0
	for k in KINDS:
		n += int(s.get(k, 0))
	return n


func count(index: int, kind: String) -> int:
	var s: Dictionary = _slot(index)
	return int(s.get(kind, 0)) if not s.is_empty() else 0


# 能否在该槽选择某一项通用铭印。
# need_hit / need_crit：用于「校准已到命中上限」「武器没有暴击字段」这类无效候选。
func can_choose(index: int, kind: String, current_hit: float = 0.0,
		current_crit: float = 0.0, hit_cap: float = 1.0, hit_near_cap: float = 0.95) -> bool:
	if not valid_slot(index) or not KINDS.has(kind):
		return false
	if total(index) >= BUDGET_TOTAL:
		return false
	if count(index, kind) >= BUDGET_PER_KIND:
		return false
	if kind == "calibrate" and current_hit > hit_near_cap:
		return false
	if kind == "tyrant" and current_crit <= 1.0:
		return false
	return true


# 选择一次：只消耗一次预算；重复结算不会再加。
func choose(index: int, kind: String) -> bool:
	if not valid_slot(index) or not KINDS.has(kind):
		return false
	if total(index) >= BUDGET_TOTAL or count(index, kind) >= BUDGET_PER_KIND:
		return false
	_slots[index][kind] = count(index, kind) + 1
	return true


func forge_bonus(index: int) -> int:
	return FORGE_STEP * count(index, "forge")


func hit_bonus(index: int) -> float:
	return HIT_STEP * float(count(index, "calibrate"))


func crit_bonus(index: int) -> float:
	return CRIT_STEP * float(count(index, "tyrant"))


# 只读导出（预览 / UI / 测试用），返回副本，避免外部改内部字典。
func snapshot() -> Array:
	var out: Array = []
	for s in _slots:
		out.append((s as Dictionary).duplicate())
	return out


# 文案：「锋铸×1（攻 +2）· 校准×1（命中 +5%）」，无成长时返回空串。
func describe(index: int) -> String:
	if not valid_slot(index):
		return ""
	var parts: Array[String] = []
	var f := count(index, "forge")
	var c := count(index, "calibrate")
	var t := count(index, "tyrant")
	if f > 0:
		parts.append("锋铸×%d（攻 +%d）" % [f, FORGE_STEP * f])
	if c > 0:
		parts.append("校准×%d（命中 +%d%%）" % [c, int(round(HIT_STEP * 100.0)) * c])
	if t > 0:
		parts.append("暴虐×%d（暴击 +%.2f）" % [t, CRIT_STEP * float(t)])
	return " · ".join(parts)
