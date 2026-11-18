class_name BranchMapConfig
extends Resource

# ============================================================================
# BranchMapConfig — 分岔路线图的布局/内容配置（2026-11-18，L2 可维护性改造）
#
# 目的：把层数、每层候选类型池、候选数量从 GDScript 硬编码外置到 .tres。
# 加层 / 改类型分布 / 调每层候选数 → 只改资源文件，不改代码、不重编译。
# 与 BalanceConfig / ShopConfig 同一模式（preload .tres 作单一真源）。
#
# 数据结构：
#   layer_types: {层索引(int, 0=起点, layer_count-1=BOSS) -> Array[String] 候选类型}
#   起点层与 BOSS 层由生成器固定处理，layer_types 只需配置中间层。
#   未配置的中间层回退到 fallback_types。
# ============================================================================

@export var layer_count: int = 15              # 总层数（含起点、BOSS）；BOSS 在 layer_count-1
@export var candidates_per_layer: int = 3      # 每层宣传候选数上限（实际取 min(此值, 池大小)）
@export var fallback_types: Array[String] = ["battle", "chest", "event"]   # 未配置层的回退池

# 13 个中间层的候选类型池（经典风险收益节奏）：
# 前段战斗/宝箱 → 中段精英/商店/休整 → 后段精英强化 → BOSS 前休整。
@export var layer_types: Dictionary = {
	1: ["battle", "chest", "battle"],
	2: ["battle", "event", "chest"],
	3: ["elite", "battle", "shop"],
	4: ["battle", "rest", "event"],
	5: ["shop", "armory", "battle"],
	6: ["battle", "elite", "chest"],
	7: ["rest", "event", "battle"],
	8: ["battle", "elite", "shop"],
	9: ["armory", "chest", "battle"],
	10: ["elite", "event", "rest"],
	11: ["battle", "shop", "battle"],
	12: ["elite", "armory", "event"],
	13: ["rest", "chest", "battle"],
}


# 取某层的类型池；未配置则回退。
func types_for_layer(layer: int) -> Array:
	var arr: Array = layer_types.get(layer, [])
	return arr.duplicate() if not arr.is_empty() else fallback_types.duplicate()


# 校验：层数至少 3（起点+1中间+BOSS），候选数至少 1。
func validate() -> Array:
	var errs: Array = []
	if layer_count < 3:
		errs.append("layer_count_too_small:%d" % layer_count)
	if candidates_per_layer < 1:
		errs.append("invalid_candidates_per_layer:%d" % candidates_per_layer)
	for k in layer_types:
		var arr: Array = layer_types[k]
		if not (k is int) or int(k) < 1 or int(k) >= layer_count - 1:
			errs.append("layer_index_out_of_range:%s" % k)
		if arr.is_empty():
			errs.append("empty_type_pool:%s" % k)
	return errs
