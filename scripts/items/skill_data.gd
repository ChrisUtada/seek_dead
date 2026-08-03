class_name SkillData
extends LoadoutItem

# 主动技能（Phase C 重构：原「增益」改名「技能」，机制不变）——可携带的「符号来源」，与 WeaponData 同为符号容器。
# 与武器的区别：武器提供多个战斗符号（Array[SymbolWeight]），
# 技能只提供一个符号，故直接持有 symbol + weight，无需 SymbolWeight 包装。
#
# 数据流：整备勾选技能 → _build_pool 把 symbol 按 weight 注入转轮池
#        → 符号落在连线上 → _evaluate 读 symbol.buff_effect/buff_value/buff_turns
#        → 写入 player_buffs（回合递减）。
# 单向引用 SymbolData，无循环引用。

@export var buff_id: String = ""
@export var buff_name: String = ""
@export var icon: String = "✦"            # 展示用字符
@export var description: String = ""
@export var symbol: SymbolData            # 该技能在转轮上的符号（自带效果字段）
@export var weight: float = 3.0           # 注入转轮池的权重
