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
# 2026-08-07 去 MISS：miss_floor/miss_ceil 退役（转轮无静态废铁，按停更准；废铁仅由敌人意图注入）

# —— 爆发 ——
@export var chain_max: int = 4                # 连锁重触发上限（special 三连免费重转，共 4 发）
@export var chain_step: float = 1.5           # 连锁倍率逐层 ×
@export var crit_chance: float = 0.20         # 方案 B：非三连每符号实例独立暴击率（三连必暴）
@export var charm_mult_cap: float = 6.0       # 总护符乘区硬上限（防失控膨胀）

# —— 整备/槽位 ——
@export var loadout_min: int = 1              # 武器最小携带数（确认开战门槛 / 卖出保护）
@export var slot_init: Dictionary = {"weapon": 1, "skill": 1, "active": 1, "passive": 1}
#   ↑ T21：weapon 2→1（整备 1 武器 + 1 技能开局，输出源 3→2；局内商店「买即开槽」扩到多武器）

# —— 元进度/铁砧 ——
@export var meta_anvil_bonus: int = 2         # 元进度三选一选「铁砧点数」获得的点数
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

# —— T27 升级点经济（BOSS 点）：升级用独立「训练点」，金币回归纯装备职能 ——
@export var train_boss_reward: int = 1        # 击败 BOSS 获得的训练点（一局 3 BOSS = 3 点；精英是否 +1 待拍板）
@export var train_per_level: int = 1          # 每级升级消耗的训练点（固定每级 1 点）
