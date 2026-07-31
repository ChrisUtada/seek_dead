class_name BuffData
extends Resource

# 主动增益（Phase C）——可携带的「符号来源」，与 WeaponData 同为符号容器。
# 与武器的区别：武器提供多个战斗符号（Array[SymbolWeight]），
# buff 只提供一个增益符号，故直接持有 symbol + weight，无需 SymbolWeight 包装。
#
# 数据流：整备勾选 buff → _build_pool 把 symbol 按 weight 注入转轮池
#        → 符号落在连线上 → _evaluate 读 symbol.buff_effect/buff_value/buff_turns
#        → 写入 player_buffs（回合递减）。
# 单向引用 SymbolData，无循环引用。

@export var buff_id: String = ""
@export var buff_name: String = ""
@export var icon: String = "✦"            # 展示用字符
@export var description: String = ""
@export var symbol: SymbolData            # 该 buff 在转轮上的符号（自带效果字段）
@export var weight: float = 3.0           # 注入转轮池的权重
