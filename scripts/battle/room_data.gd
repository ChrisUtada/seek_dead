class_name RoomData
extends Resource

# Phase D 资源化：房间序列的数据载体（原 ROOMS 内联字典数组）。
# 每个房间一个 resources/rooms/*.tres；扫描收集见 duel_controller._ready 的 ResourceScan。
# 字段与原 ROOMS 字典键一一对应，结算逻辑（克制/胜负/净化/房奖励）行为不变。

@export var name: String = ""
@export var hp: int = 0
@export var atk: int = 0
@export var jam: float = 0.0      # 注废意图概率
@export var lock: float = 0.0     # 锁轮意图概率
@export var chaos: float = 0.0    # 乱权意图概率
@export var heavy: float = 0.0    # 重击意图概率（其余=普攻）
@export var armor: int = 0          # 护甲（扁平池）：伤害先破甲后掉血；0 = 无护甲（RPG 式破甲机制）
@export var element: String = "none"  # fire|ice|poison|light|dark|none（单向克制：敌人属性）
@export var kind: String = "normal"    # normal|elite|boss（房间类型；boss 由 _is_boss_room 判定专属机制）
@export var gimmick_script: Script      # BOSS 专属机制脚本（extends BossGimmick）；非 BOSS 房留空。_start_room 实例化并赋值 current_gimmick
@export var act: int = 1                # 幕号（1/2/3）；_build_run 按幕分组抽房（每幕 2 normal + 1 elite + 1 boss）
@export var boss_reward_weapons: Array[String] = []   # BOSS 战利品·主题武器池（武器 .tres 路径）；空则按 element 从 WEAPON_POOL 取未持有者
@export var boss_relic_path: String = ""              # BOSS 战利品·专属信物（ItemData passive .tres 路径），占护符槽 1/3；空则不掉信物
