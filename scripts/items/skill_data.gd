class_name SkillData
extends LoadoutItem

# 主动技能（Phase C 重构：原「增益」改名「技能」，机制不变）——可携带的「符号来源」，与 WeaponData 同为符号容器。
# 与武器的区别：武器提供多个战斗符号（Array[SymbolWeight]），
# 技能只提供一个符号，故直接持有 symbol + weight，无需 SymbolWeight 包装。
#
# 技能形态（需求③：参照经典 RPG）——符号的 kind 决定其战斗行为，技能本身只是「把该符号塞进转轮」：
#   - 远程攻击：symbol.kind == "damage"（如 magic_bolt → arcane_bolt，带 light 元素用于克制）
#   - 恢复：    symbol.kind == "heal"（如 recovery → heal）
#   - 增益：    symbol.kind == "buff"（如 haste/rage，走 buff_effect 回合增益；见 _evaluate/_grant_buff）
# 强度轴（base_power / hit_rate / rarity）继承自 LoadoutItem，与武器同源。
#
# 数据流：整备勾选技能 → _build_pool 把 symbol 按 weight 注入转轮池（与武器同池竞争、
#         base_power 经 _weapon_power_map 缩放其符号，补 P3 缺口）
#        → 符号落在连线上 → _evaluate 按 kind 路由（damage/heal 走 _contribute，buff 走 _grant_buff）
# 单向引用 SymbolData，无循环引用。

@export var buff_id: String = ""
@export var buff_name: String = ""
@export var icon: String = "✦"            # 展示用字符
@export var description: String = ""
@export var symbol: SymbolData            # 该技能在转轮上的符号（自带效果字段）
@export var weight: float = 3.0           # 注入转轮池的权重
