extends RefCounted

# ============================================================================
# MapTrap — 破甲陷阱数据与护甲口径（Step 4）
# 规格：docs/地图巡逻诱导_第一版预算与分步执行计划_2026-11-14.md
#       §3.4 陷阱规则、§6 Step 4 任务 1–4 与出口
#
# 边界：
# - 首版只有一种陷阱：`armor_break`（破甲），位置始终公开，不做随机即死；
# - 陷阱不是节点类型，是叠加在可行走格上的公开位置，唯一数据源仍是 MapGrid.traps；
# - 触发记录是运行时状态（由 MapRuntime 持有），不写回 cell、不写怪物资源；
# - 护甲口径与 duel_controller 保持一致：RoomData.armor 优先，否则取行为族基准。
#   实际战斗仍走 `enemy_armor_max = base × hp_scale`，破甲把该值降到 0；
#   地图预告显示的是基础护甲 X → 0。
# ============================================================================

const TYPE := "armor_break"
const LABEL := "破甲陷阱"
const ARMOR_AFTER := 0


static func traps(grid: Dictionary) -> Array:
	return grid.get("traps", [])


static func is_trap_cell(grid: Dictionary, cell: int) -> bool:
	for t in traps(grid):
		if int(t.get("cell_id", -1)) == cell:
			return true
	return false


static func trap_at(grid: Dictionary, cell: int) -> Dictionary:
	for t in traps(grid):
		if int(t.get("cell_id", -1)) == cell:
			return t
	return {}


# 与 duel_controller.gd 的 `base_armor` 同口径（不含 hp_scale，那是战斗期缩放）。
static func armor_of(room: RoomData) -> int:
	if room == null:
		return 0
	if int(room.armor) > 0:
		return int(room.armor)
	if room.archetype != null:
		return int(room.archetype.armor_base)
	return 0


# §3.4：触发后向玩家显示「下一场战斗：敌方护甲 X → 0」。
static func describe(armor_before: int) -> String:
	return "下一场战斗：敌方护甲 %d → %d" % [armor_before, ARMOR_AFTER]


# 本次战斗的护甲变化。armor_before 若是 0（无甲怪），破甲无意义但要如实标注。
static func change(armor_before: int) -> Dictionary:
	return {
		"before": armor_before,
		"after": ARMOR_AFTER,
		"effective": armor_before > ARMOR_AFTER,
		"text": describe(armor_before),
	}
