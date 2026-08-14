class_name BalanceConfig
extends Resource

# T22 平衡常量表（resources/config/balance_config.tres，策划可在 Inspector 直接编辑，替代 controller 顶部散落 @export）。
# 用法：各处 `const BALANCE = preload("res://resources/config/balance_config.tres")`（与 ShopConfig 同模式）。
# 结构常量（转轮引擎/流程）不迁入：REELS/ROWS/_SPIN_*/_ITEM_STRIP_TARGET/_GOLD_CELLS/UNCAPPED/CONSUMABLE_CAP 等留代码。
# 调试旗标（SMALL_OWNED_*）留 controller（非平衡数值）。

# —— 经济 ——
@export var gold_pool_weight: float = 3.0     # 金币符号在转轮池中的权重（远低于伤害符号，防稀释 DPS）
@export var gold_per_coin: int = 1            # 每枚落在连线上的金币符号产出的金币数

# —— 难度曲线（ante）：幕间台阶 × 幕内爬升 ——
@export var ante_act_step_hp: float = 1.75    # 每进一幕敌方 HP ×
@export var ante_act_step_atk: float = 1.46   # 每进一幕敌方 ATK ×
@export var ante_room_step_hp: float = 1.15   # 同幕每过一房敌方 HP ×
@export var ante_room_step_atk: float = 1.10  # 同幕每过一房敌方 ATK ×

# —— 伤害基准 ——
@export var player_dmg_mult: float = 1.5      # 玩家直击总伤害永久倍率（F6 验证手感）
@export var status_dmg_mult: float = 3.0      # 敌人状态 DoT（灼烧/毒）永久倍率

# —— 转轮频率 ——
# 2026-08-09 恢复 MISS：带子按装备 hit_rate 聚合 MISS 格（高 base 低命中武器付出命中代价）；
# miss_floor/miss_ceil（旧静态 miss 比例）不恢复——miss 占比由 hit_rate 自然决定，无需额外常量

# —— 爆发 ——
@export var crit_chance: float = 0.20         # 方案 B：非三连每符号实例独立暴击率（三连必暴）
@export var charm_mult_cap: float = 6.0       # 总护符乘区硬上限（防失控膨胀）

# —— 整备/槽位 ——
@export var loadout_min: int = 2              # 武器最小携带数（2026-08-07：强制带满 2 把主+副——消灭单带，三连率结构性控制）
@export var slot_init: Dictionary = {"weapon": 2, "skill": 1, "active": 1, "passive": 1}
#   ↑ 2026-08-14 勘误：旧注释「T21：weapon 2→1（整备 1 武器开局）」与实际相反——weapon=2 + loadout_min=2 强制双武器（08-07 同日反转拍板），已删除

# —— 玩家基础 ——
@export var player_hp_base: int = 100         # 玩家基础生命上限（新一局起点；体魄/局内奖励在局中增长，跨局不保留）

# —— 元进度/铁砧 ——
@export var meta_anvil_bonus: int = 2         # 元进度三选一选「铁砧点数」获得的点数
@export var boss_anvil_bonus: int = 3         # BOSS 战利品空池兜底（武器/护符槽双满）：铁砧点数补偿
@export var meta_choice_count: int = 3        # 元进度候选张数（三选一）
@export var anvil_roll_cost: int = 10
@export var anvil_blank_chance: float = 0.10
@export var anvil_pity_max: int = 10
@export var anvil_per_run_cap: int = 40
@export var anvil_dupe_refund: Dictionary = {"common": 3, "uncommon": 5, "rare": 7, "epic": 10}
@export var anvil_rarity_weight: Dictionary = {"common": 100, "uncommon": 40, "rare": 12, "epic": 3}
@export var anvil_milestone_pct: Array = [0.25, 0.5, 0.75, 1.0]
@export var anvil_milestone_bonus: Array = [50, 100, 150, 200]

# —— T21 元素充能（覆盖流爆发赛道）——
@export var charge_max: int = 5               # 克制命中充能上限（满则释放元素爆发）
@export var charge_burst_pct: float = 0.15    # 元素爆发伤害 = 敌人 max HP × 此比例（穿透直击）

# —— T25 关卡结构（2026-08-09 房数重排：一局 24 房 = 3 幕 × 每幕 8 房 + 真·最终通关后战）——
@export var run_acts: int = 3                                     # 幕数
@export var run_act_layout: Array = ["normal", "normal", "normal", "elite", "normal", "normal", "elite", "boss"]   # 每幕房型序列（5 普通 + 2 精英 + 1 常规 BOSS 战）
@export var run_boss_weights: Dictionary = {"fixed": 6, "rotating": 3, "hidden": 2}   # 常规 BOSS「4 候选选 1」角色权重（固定首领默认高权重；隐秘=幕内全清后开启，恒可入选）
@export var run_include_final_boss: bool = true                    # 真·最终（RoomData.final_boss 房）通关 Act3 后追加为整局最后一间（当前无内容，槽位预留）
