class_name EnemyArchetype
extends Resource

# T5 敌人行为族（兵种模板）：意图剖面 + 数值基准 + 护甲倾向。
# 设计纪律：**族只管行为/基准，元素/幕/名字/微调属于实例（RoomData）**——族可随时调整/新增，不触碰实例。
# 引用链路：RoomData.archetype 非空 → 意图表优先取族（intent_weights），hp/atk/armor 为 0 时取族基准；
#           否则回落 T20 默认表（按 kind）与 RoomData 自身数值（现状行为不变）。
# 族库是内容：落地时先建示范族，随 BOSS（T10）/课程化验证后扩充，不改架构。

@export var id: String = ""                          # heavy_brawler|jammer|status_sower|sentinel...
@export var display_name: String = ""                # 重击者|干扰者|状态播种者|哨兵
@export var intent_weights: Dictionary = {}          # 意图剖面（id → 权重，复用 T20 IntentData 体系）；空 = 回落 kind 默认表
@export var hp_base: int = 0                         # 数值基准（0 = 不用族基准，实例自己写）
@export var atk_base: int = 0                        # 同上
@export var armor_base: int = 0                      # 护甲倾向（0 = 无）
@export var desc: String = ""                        # 族说明（课程化/调参用）
