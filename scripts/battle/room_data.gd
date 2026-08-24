class_name RoomData
extends Resource

# Phase D 资源化：房间序列的数据载体（原 ROOMS 内联字典数组）。
# 每个房间一个 resources/rooms/*.tres；扫描收集见 duel_controller._ready 的 ResourceScan。
# 字段与原 ROOMS 字典键一一对应，结算逻辑（克制/胜负/净化/房奖励）行为不变。

@export var name: String = ""
@export var hp: int = 0
@export var atk: int = 0
@export var archetype: EnemyArchetype = null  # T5 行为族引用（意图剖面/数值基准；空 = 走按幕分档默认表 + 自身数值）
@export var intents: Array[IntentData] = []  # T20：本房意图加权表（空 = 行为族剖面/按幕分档默认表，见 StatusSystem.ACT_INTENT_WEIGHTS；显式表不受按幕过滤）
@export var armor: int = 0          # 护甲（扁平池）：伤害先破甲后掉血；0 = 无护甲（RPG 式破甲机制）
# 检查器下拉：@export_enum 需字面量（Godot 限制），词汇与 ElementCounter.ELEMENT_ENUM 同步，
# 漂移由 duel_controller._ready 的 is_valid_element 启动校验兜底。
@export_enum("none", "fire:火", "ice:冰", "poison:毒", "light:光", "dark:暗") var element: String = "none"  # 元素（弱/抗由 ElementCounter 推导，不存冗余字段）
@export_enum("normal", "elite", "boss") var kind: String = "normal"    # 房间类型（boss 由 _is_boss_room 判定专属机制）
@export var gimmick_script: Script      # BOSS 专属机制脚本（extends BossGimmick）；非 BOSS 房留空。_start_room 实例化并赋值 current_gimmick
@export var gimmick_params: Dictionary = {}  # T24：gimmick 参数字典（如 rust_armor 的 interval/per_stack/max_stacks）；空 = gimmick 默认值
@export var act: int = 1                # 幕号（1/2/3）；_build_run 按幕分组抽房（每幕 5 normal + 2 elite + 1 常规 boss）
@export_enum("fixed", "rotating", "hidden") var boss_role: String = "fixed"  # T25：常规 BOSS 候选角色——fixed 固定首领（默认高权重）/ rotating 轮替 / hidden 隐秘（幕内全清后开启）
@export var final_boss: bool = false     # T25：真·最终——独立于候选池，通关 Act3 后追加为整局最后一间（勇者的阴影）
@export var boss_reward_weapons: Array[String] = []   # BOSS 战利品·主题武器池（武器 .tres 路径）；空则按 element 从 WEAPON_POOL 取未持有者
@export var boss_relic_path: String = ""              # BOSS 战利品·专属信物（ItemData passive .tres 路径），占护符槽 1/3；空则不掉信物
@export var art: Texture2D = null                     # 专属立绘（BOSS 用）：入场时替换默认 enemy.png 并演出退场/入场；空 = 默认敌人图
@export var art_scale: float = 1.0                    # 立绘显示倍率（相对玩家 44×60 规格；1.0 = 同规格，2.0 = 2 倍）——素材观感验证用
