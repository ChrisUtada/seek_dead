# ⚠️ 死代码 / 预留接口（Phase D 死代码治理）：
# 词缀（StatModifier）是给未来 Phase F 词缀系统预留的数据载体，【老虎机对决流程当前零调用】。
# target_stat / modifier_type 引用自 equipment/enums.gd（同为预留）。本文件未接线、不生效、不报错。
# 待词缀生成方式（随机 / 固定 / 混合）与挂载点确定后再接入，不要在此处改动战斗逻辑。
class_name StatModifier
extends Resource

@export var target_stat: EquipmentEnums.StatTarget
@export var modifier_type: EquipmentEnums.ModifierType
@export var value: float
@export var per_level: float = 0.0
