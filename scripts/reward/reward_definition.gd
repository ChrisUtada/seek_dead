class_name RewardDefinition
extends Resource

# 战后三选一重构 P0：新奖励的统一数据定义。
#
# 与旧 RewardData 的区别：
# - 旧 RewardData 只有单个 value:int，无法表达双效果/复合效果；
#   本类用 effects:Array[Dictionary]（每项 {effect_id, params}）承载一个或多个效果。
# - rarity 是「战利品品质」四档（common/uncommon/rare/epic，见 LootSourceTable.QUALITIES），
#   与旧 RewardData.rarity（房奖励三档稀有度）是两套体系，勿混用。
# - 本类只描述奖励，不执行效果；执行由 RewardResolver 负责（契约 §1）。
#
# 规则字段（eligibility/context/synergy）存「规则键名」而非 Callable：
# Resource 里 Callable 无法可靠序列化，键名映射到 RewardEvaluator 内的规则函数，
# 做到数据驱动、不在 Evaluator 里为每张卡写 if/else（v2.0 §20.4）。

@export var id: String = ""                      # 稳定唯一 ID（如 seed_battle_ready）
@export var name: String = ""                    # 展示名称
@export var desc: String = ""                    # 玩家可理解的效果说明

@export var icon: Texture2D = null               # 图标资源
@export var art: Texture2D = null                # 卡面美术，空则用 icon

@export var rarity: String = "common"            # common|uncommon|rare|epic（战利品品质四档）
@export var tags: Array[String] = []             # 开放标签：weapon / element.fire / build.fire / survival.* 等
@export var base_weight: float = 1.0             # 基础出现权重
@export var base_value: float = 1.0              # 设计基准价值（供 Draft 评分，≠效果数值）

# 效果列表：每项 {"effect_id": String, "params": Dictionary}
# effect_id 取值：heal / shield_next_battle / run_power_bonus / flame_affinity（原 free_reroll 卡已删除）
@export var effects: Array[Dictionary] = []

@export var stack_rule: StackRule = StackRule.NONE
@export var max_stack: int = -1                  # -1 = 无限

@export var eligibility_rule: String = ""        # 有效性规则键名 → RewardEvaluator 内映射
@export var context_rule: String = ""            # 情境价值规则键名
@export var synergy_rule: String = ""            # 构筑协同规则键名

@export var unlock_rule: String = ""             # 解锁条件（可选）
@export var offer_rule: String = ""              # 出现频率控制（可选）
@export var risk_cost: Dictionary = {}           # 代价参数（可选，如 {hp: -10, gold: 20}）

enum StackRule {
	NONE,        # 不叠加：已拥有即过滤
	LINEAR,      # 线性叠加：可重复获取，数值累加
	DIMINISHING, # 递减叠加：每次收益递减
	REPLACE,     # 替换：重复获取时升级/替换旧效果
}

const VALID_RARITIES := ["common", "uncommon", "rare", "epic"]


# 数据校验：Registry 扫描时调用，返回错误原因数组（空 = 合法）。
# 只做静态数据合法性检查，不涉及运行时状态（后者归 EligibilityFilter）。
func validate() -> Array[String]:
	var errors: Array[String] = []
	if id.is_empty():
		errors.append("id_empty")
	if name.is_empty():
		errors.append("name_empty")
	if not VALID_RARITIES.has(rarity):
		errors.append("invalid_rarity:" + rarity)
	if effects.is_empty():
		errors.append("no_effects")
	else:
		for i in range(effects.size()):
			var e: Dictionary = effects[i]
			if not e.has("effect_id") or String(e.get("effect_id", "")).is_empty():
				errors.append("effect_missing_id:%d" % i)
			if not e.has("params") or not (e.get("params") is Dictionary):
				errors.append("effect_missing_params:%d" % i)
	if base_weight <= 0.0:
		errors.append("invalid_base_weight")
	if max_stack == 0:
		errors.append("invalid_max_stack")
	return errors


# 首个效果 id（当前 4 张种子卡均为单效果，便于 Resolver 分发）。
# 多效果卡由 Resolver 遍历 effects 逐个分发。
func first_effect_id() -> String:
	if effects.is_empty():
		return ""
	return String(effects[0].get("effect_id", ""))


func has_tag(tag: String) -> bool:
	return tags.has(tag)
