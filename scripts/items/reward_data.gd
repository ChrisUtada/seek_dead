class_name RewardData
extends Resource

# Phase D 资源化：房奖励的数据载体（原 REWARD_POOL 内联字典数组）。
# 每个奖励一个 resources/rewards/*.tres；扫描收集见 duel_controller._ready 的 ResourceScan。
# id 仍用于 _apply_reward 的 match 分发，icon/label/desc 供 HUD 奖励卡直接读取。

@export var id: String = ""        # heal|maxhp|purify|symbol|shield|power（对应 _apply_reward 分支）
@export var icon: String = ""
@export var label: String = ""
@export var desc: String = ""
