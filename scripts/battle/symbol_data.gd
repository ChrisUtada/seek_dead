class_name SymbolData
extends Resource

# 老虎机战斗符号 — 数据即资源（Godot 4 最佳实践）。
# 符号完全由「武器装备 / 主动 buff」持有，无全局注册表、无 enum 查表。
# 每个武器/buff 用 @export var symbol: SymbolData 直接引用本资源。

@export var label: String = ""
@export var name: String = ""
@export var kind: String = "damage"        # damage | shield | heal | status | special | buff | trash（结算行为由 kind 决定）
@export var base: float = 0.0
@export var element: String = "none"        # fire | ice | poison | light | dark | none（单向克制）
@export var status_type: String = ""        # 仅 kind=="status"：burn | frost | poison
@export var color: Color = Color(0.7, 0.7, 0.75, 1)
@export var pierce_armor: bool = false   # 穿透护甲：该符号伤害直接扣 HP，不先扣敌人护甲（RPG 式破甲）

# Phase C — 仅 kind=="buff"：主动技能符号自带效果，符号自描述。
# 结算时 _evaluate 直接读这三个字段，无需从 SkillData 回查，保持零查表。
@export var buff_effect: String = ""        # power | shield | regen | damage_mult
@export var buff_value: float = 0.0         # damage_mult 为倍率（如 1.5），其余为整数值
@export var buff_turns: int = 2             # 命中一次可持续回合数（含命中当回合）
