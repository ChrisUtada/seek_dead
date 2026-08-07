class_name RewardData
extends Resource

# Phase D 资源化：房奖励的数据载体（原 REWARD_POOL 内联字典数组）。
# 每个奖励一个 resources/rewards/*.tres；扫描收集见 duel_controller._ready 的 ResourceScan。
# id 用于 apply_reward 的分发（效果类型），value 为效果数值（heal 为最大 HP 百分比，其余为 += 绝对值），
# icon/label/desc 供 HUD 奖励卡直接读取——数值与文案同文件，防双写漂移。

@export var id: String = ""        # heal|maxhp|symbol|shield|power|elite_*（对应 apply_reward 分支）
@export var icon: String = ""
@export var label: String = ""
@export var desc: String = ""
@export var value: int = 0         # 效果数值：heal 为最大 HP 百分比（35=35%），其余为绝对值（+= 语义）
