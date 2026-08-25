class_name DuelController
extends Control
# ============================================================================
# 官方对决控制器（DuelController）：由原型 prototypes/reel_combat/reel_combat.gd 迁移而来。
# 符号数据层：scripts/battle/symbol_data.gd（SymbolData 资源）、WeaponData.symbols、
#   8 把武器 .tres、ItemData（合并原 ConsumableData/CharmData）+ 8 个 .tres。
# 铁砧元进度存档于 SaveSystem.lobby_data["anvil_meta"]（与项目统一 JSON 存档）。
# 全代码 UI（Control 树），可直接作为 duel.tscn 脚本运行（F6）或由 RoomManager 进入。
#
# 拆分（docs/[已完成]duel_controller拆分方案B.md）：M0–M6 历史增量注释已清理；职责分区——
#   存档 MetaStore / 铁砧 AnvilSystem / 商店 ShopSystem / 奖励 RewardSystem / 整备 LoadoutSystem
#   均为 RefCounted 子系统（scripts/systems/），本文件只留编排 + 薄转发 + 战斗核心。
#   各子系统 _init(ctrl: DuelController) 注入本 controller，_ctrl 均已标类型（编译期检查）。
# ============================================================================

const TRASH_SYMBOL = preload("res://resources/symbols/trash.tres")
const GOLD_SYMBOL = preload("res://resources/symbols/gold.tres")
# 元素精华（消耗品）：使用后向当前房间转轮池注入对应元素的攻击符号（多一种攻击方式，新房间失效）
const ESSENCE_SYMBOLS: Dictionary = {
	"fire":   preload("res://resources/symbols/essence_fire.tres"),
	"ice":    preload("res://resources/symbols/essence_ice.tres"),
	"poison": preload("res://resources/symbols/essence_poison.tres"),
	"light":  preload("res://resources/symbols/essence_light.tres"),
	"dark":   preload("res://resources/symbols/essence_dark.tres"),
}
const ESSENCE_POOL_WEIGHT := 7.0           # 精华符号注入权重（≈普通武器 3-5 的 1.5-2 倍：让带子有 2-4 格，2/3 连可达成）
# T22：平衡常量全部收敛于 BalanceConfig（resources/config/balance_config.tres，Inspector 可编辑）
const BALANCE = preload("res://resources/config/balance_config.tres")

# Phase 1 组件化：UI 复用场景与脚手架（按钮/面板/卡片构建均在 battle_hud 与各 screen，本控制器不再持有）

# 可选物品池（整备界面从这里自由勾选，真实 .tres 数据）。
# Phase D 软注册表清理：改为文件夹自动扫描，新增内容只需在对应 resources/ 子目录放 .tres，
# 不再手写路径数组（见 _ready 内的 ResourceScan 填充）。默认空，待 _ready 填充。
var WEAPON_POOL: Array[String] = []
var ITEM_POOL: Array[String] = []
# Phase C 主动技能：携带后其符号进入转轮，连线命中施加限时增益
var SKILL_POOL: Array[String] = []

# 携带约束（Phase G）：四类各自占【独立槽位】，互不算总、不共享上限。
# 【初始配额】武器 2 · 增益 1 · 消耗品 1 · 护符 1（合计 5——仅为初始值之和，**不是**共享闸门；
#   任一类满槽绝不影响其他类，杜绝旧 TOTAL_MAX 时代「带满护符就买不了武器」的误判）。
# 【成长方式】统一「买即开槽」：商店购买某类物品时，若该类当前槽位已满且未触天花板，
#   本次购买直接把该类上限 +1（不单独售卖抽象的「槽扩展」商品）。
#   节奏闸门 = 同类价格随已持数递增（见 _shop_price 的 step 表）。
# 【天花板：按「进池 / 不进池」分野，不按类别拍脑袋】
#   · 进池类（武器 weapon）→ **硬上限 2**（2026-08-07 拍板：主手+副手，商店不可买第 3 把，
#     cat_cap("weapon")=2；原「UNCAPPED + 稀释自刹车」语义已失效，哨兵常量仅留给逻辑分支复用）。
#     武器符号挤进同一条转轮带；硬限 2 后武器符号密度恒定，稀释只来自技能种类（封顶 3）/
#     MISS / 废铁注入 / 符号灌注（见 docs/[已完成]整备结构_技能槽上限与频率规范.md §4.3）。
#     再叠加金币线性递增价（见 _shop_price），越买越贵，双闸门足矣。
#   · 技能 skill（2026-08-10 起退出 UNCAPPED）→ 硬上限 3（初始 1 → 商店买到 3）。
#     武器硬限 2 把，若技能无上限则技能符号（功能/buff）无限挤占主输出带子——不对称稀释
#     （见 docs/[已完成]整备结构_技能槽上限与频率规范.md）。
#   · 不进池类（消耗品 active · 护符 passive）→ **硬天花板**（2 / 3）。
#     它们不进转轮、零稀释代价、没有任何自然刹车（尤其护符是「唯一收集乘区」，
#     纯收益、越多越强），故必须硬限量，否则乘区无限叠加直接崩坏数值。
# 初始配额（每局开局值；_full_reset 与 _shop_price 的加价起点均以此为准；weapon=2 + loadout_min=2 强制双武器，见 balance_config.slot_init）
var SLOT_INIT: Dictionary = BALANCE.slot_init
const UNCAPPED := -1        # 天花板哨兵值：该类无上限，仅由稀释效应 + 金币递增价约束
const CONSUMABLE_CAP := 4   # 消耗品腰带上限（不进池，硬限；每格独立持有、允许同类重复占格）
const CHARM_CAP      := 3   # 护符槽天花板（不进池、唯一收集乘区，严格硬限）
var LOADOUT_MIN: int = BALANCE.loadout_min   # 武器最小携带数（T22：来自平衡配置）
# 房间序列排序权重：normal/elite 在前、boss 殿后（同档按路径稳定排序）
const ROOM_KIND_RANK := {"normal": 0, "elite": 0, "boss": 2}
# 各类当前上限：每局从初始配额起步（武器 2 起步 + loadout_min=2 强制双武），商店「买即开槽」逐步逼近天花板（武器硬限 2 / 技能硬限 3，_full_reset 重置）
var loadout_max: int = int(BALANCE.slot_init["weapon"])
var skill_max: int = int(BALANCE.slot_init["skill"])
var charm_max: int = int(BALANCE.slot_init["passive"])

const REELS = 3
const ROWS = 1

# 房间难度曲线（ante）：数值见 balance_config.tres（ante_act_step_*/ante_room_step_*，T22 资源化）。
# 等价关系：原 1.15^idx（每幕恰 4 房）= (1.15^4)^(act-1)·1.15^(幕内位置)。T25 房数重排（2026-08-09）后每幕 8 房、
# BOSS 幕内位置 ria=3→7（ante 倍率随 ria 自动爬升，数值待 F6 复核）。当前手感：幕1/2/3 BOSS HP ≈ 266/771/2140。
@export var SMALL_OWNED: bool = false   # 调试用：铁砧效果测试时把拥有池压到 SMALL_OWNED_WEAPONS 武器 / SMALL_OWNED_CHARMS 护符（默认 false 用正式全池）
@export var SMALL_OWNED_WEAPONS: int = 3
@export var SMALL_OWNED_CHARMS: int = 4

# M4 房奖励池（每清一房随机 3 选 1；Boss 房走同池但标为「残余物」）。
# Phase D 资源化：改为扫描 resources/rewards/*.tres（RewardData），见 _ready 内填充。
var REWARD_POOL: Array[RewardData] = []

# T6 精英房专属「战前补给」奖励池（扫描 resources/rewards/elite/）。
# 精英房卡在每个 BOSS 前，定位为「补给锚点」而非普通小增益 / BOSS 战力飞跃，
# 故与普通房奖励池解耦，提供 金币囤 / 铁砧点 / 结界备战 三类 prep 选项。
var ELITE_REWARD_POOL: Array[RewardData] = []

# 房间序列（肉鸽逐房推进）。
# 2026-08-09 拆分：意图/状态定义与查询（INTENT_DEFS / STATUS_DEFS / _roll_intent / _status_*）迁至 StatusSystem。

func _intent_def(id: String) -> IntentData:
	return status_system.intent_def(id)
# Phase D 资源化：改为扫描 resources/rooms/*.tres（RoomData），见 _ready 内填充。
var ALL_ROOMS: Array[RoomData] = []          # 全量房间池（扫描收集；_build_run 从中按幕抽 24 房 + 真·最终槽）
var ROOMS: Array[RoomData] = []             # 当前一局的房序列（每局 _full_reset 时由 _build_run 重建：24 房 + 真·最终）

# grid[reel][row] = SymbolData 引用
var grid = []
# grid_elem[reel][row] = 该格符号的「有效元素」（武器元素继承后的实际元素，用于逐符号克制结算）
var grid_elem = []

# 合并后的加权符号池：元素为 [SymbolData, weight, element]（element = 有效元素）
var pool: Array[Array] = []
var loadout_names: Array[String] = []
var _weapon_power_map: Dictionary = {}   # 符号 resource_path -> 该物品有效攻击力(base_power + 元进度武器加成)，由 _build_pool 构建。P3：结算时 _contribute 读此值把「物品强度轴」灌进符号伤害（docs/[已完成]物品中心重构方案.md §8）
var _item_crit_map: Dictionary = {}   # 符号 resource_path -> 该物品三连暴击倍率(crit_mult)，由 _build_pool 构建（方案 A）。普通/special 三连均按此倍率结算，共享符号取最高 crit_mult。
var _item_crit_chance_map: Dictionary = {}   # 符号 resource_path -> 该物品非三连暴击率加成(crit_chance)，_build_pool 构建（2026-08-07：高 base 低暴击代价轴）
var _item_pierce_map: Dictionary = {}   # 符号 resource_path -> 该物品是否带破甲机制(triple_pierce)，_build_pool 构建（2026-08-07：破甲=武器/技能机制，非三连通用）
var pool_items: Array[Dictionary] = []              # 装备自洽：每件装备一段 [ {name, hit, syms:[[SymbolData, weight, element]]} ]，_build_strips 据此生成各自的转轮子带

var _busy: bool = false                 # 旋转序列进行中，防重入
var _eval_adv := false                  # _evaluate 阶段2：本回合是否触发过「克制」
var _eval_dis := false                  # _evaluate 阶段2：本回合是否触发过「抵抗」
var _elem_triple := false               # 2026-08-07 同元素三连：3 列有效元素相同（可不同符号）→ 必暴 + 克制核爆（参考 Slots & Skulls 匹配判定宽容化）
var _last_triple := false               # 保留（重转机制移除后暂未使用，供未来重转设计）
var charge_points := 0                   # T21 元素充能：克制命中累计，满 BALANCE.charge_max 释放元素爆发（每房清零）
var _charge_elem_counts: Dictionary = {} # 2026-08-14 主导元素统计：本回合各元素克制命中次数（释放爆发时取最高者）
var train_points := 0                    # ⚠ 已废弃（训练点系统 2026-08-14 移除），保留字段兼容旧存档读取

var player_frost := 0                    # T30 寒霜侵蚀：玩家 frost 层数（每层冻结转轮 1 列，上限见 frost StatusDef.max_cols）
var frozen_cols: Array[int] = []         # T30：本回合被冻结的列（失效格：不参与匹配/结算），每轮 _begin_spin 重选
var player_status: Dictionary = {}       # 2026-08-09 酸蚀恶鬼：玩家侧 DoT（{"poison": 层数}），本房清零；tick/爆炸由 gimmick 结算（acid_bomb_gimmick.on_turn_begin）
var player_dot_bomb_stacks: int = 10     # 2026-08-09：玩家 DoT 爆炸阈值（HUD 警示用；gimmick on_room_start 按 gimmick_params 覆盖）

# —— 实体转轮带（方案 A）：权重 = 带子上该符号的格子数，落点由停止时机决定 ——
# 2026-08-09 拆分：转轮状态/旋转逻辑迁至 ReelSystem（scripts/battle/reel_system.gd），
# 本控制器仅保留共享状态（grid / pending_* / pool_items）与输入入口（reel_system 调用）。

# 物品强度轴基准（P3）：伤害 = (物品 base_power × 符号 base 偏移) × 连线 × 克制。
# 2026-08-07 重构（T12）：伤害只由武器攻击力决定，BASE_POWER_REF 已退役。

# S12 局内金币升级 4 轨道（T3 重构收敛版：数据驱动，不新增乘区；每局清零，管局内临时）
# 设计：爆炸感来自「在现有 3 乘区(连线/护符·增益/克制)内做深」，而非开第 4 条独立乘区。
#   · power  训练：锋锐 —— +基础伤害（喂入全部乘区，线性保底）
#   · line   连线精通 —— 匹配连线倍率 +N（深化 lane1，仅 ≥2 的同符号生效）
#   · shield 训练：壁垒 —— 每房开局护盾 +N（韧性保底，少量）
#   · hp_max 训练：体魄 —— 生命上限 +N（替换 joker，§7.4 拍板）
# 收敛决策（2026-08-07）：原 6 轨的 精准/回复 已删——精准由武器 hit_rate 自带（命中成长=换武器），
# 注：不设自动停止上限——转轮何时停完全由玩家决定，不操作就一直转。

var current_gimmick = null              # 当前房间 BOSS 机制实例（S10 T2 赋值；非 BOSS 房为 null，钩子空安全跳过）
var boss_atk_mult := 1.0                # S10 T2：敌人→玩家伤害倍率（whisper_lock 呓语锁轮强化），每玩家回合重置为 1.0 后由 gimmick 命中时设 1.5
var boss_trash := 0                     # S10 T2：深渊侵蚀注入的额外废铁格数（每列），_build_strips 落实，默认 0

# 整备（M3–M6）：玩家自由勾选武器 / 消耗品 / 护符三分类
var in_loadout := false
var in_interroom := false   # 房间歇态：房奖励结算后、进下一房前（opt-in 商店，替代强制全屏商店）
var selected_loadout: Array[String] = []          # 玩家勾选的武器路径
var selected_consumables: Array[String] = []      # 玩家勾选的消耗品路径
var selected_charms: Array[String] = []           # 玩家勾选的护符路径
var selected_skills: Array[String] = []           # 玩家勾选的主动技能路径（Phase C 重构：原「增益」改名「技能」）

# T23：状态定义资源化（StatusDef：base/element/name/icon/decay/desc），定义表已迁至 StatusSystem（2026-08-09）

# Phase C 主动增益运行时：SymbolData -> 剩余回合数（本房内有效，进房清空）
var player_buffs: Dictionary = {}

# 消耗品运行时（战斗中主动使用）
var consumable_slots: Array[Dictionary] = []          # 消耗品腰带实例：[{path, item_id, charges, uid}]，上限 CONSUMABLE_CAP，允许同类重复占格
var locked_consumable_slot: int = -1                  # 天平审判官 P2：律法惩罚锁定的腰带格（-1 = 未锁定；回合开始复位）
var _consumable_uid := 0                   # 腰带格唯一 id 计数器（卖出/使用精准定位，避免同类重复撞 key）
# 4 格子（2x2）由 HUD 自管（hud.consumable_cells），controller 不再持有引用
var assault_next_spin: int = 1            # 强袭药剂：下次转轮伤害倍率（1=正常）
var room_element_mult: Dictionary = {}    # 元素精华（消耗品）：本房间内 元素 → 强制克制倍率（新房间清零）

# 玩家状态
var player_hp: int = int(BALANCE.player_hp_base)
var player_hp_max: int = int(BALANCE.player_hp_base)
var gold = 4                           # S6：局内金币（每局清零，见 §11）
var player_shield = 0

# 敌人 / 房间状态
var room_index = 0
var enemy_name = "敌人"
var enemy_hp = 120
var enemy_hp_max = 120
var enemy_armor_max = 0                # 护甲上限（扁平池；来自 RoomData.armor × ante，BOSS 机制可成长）
var enemy_armor = 0                    # 当前护甲：伤害先破甲后掉血；0 = 无护甲
var enemy_atk = 14
var _interf_resist_rf := 1.0             # T20：抗扰减免系数（干扰类意图权重 × 此值，_start_room 计算）
var enemy_status: Dictionary = {}      # status_type(str) -> 叠加层数(int)
var enemy_intent: Dictionary = {}      # 当前敌人意图 {"data": IntentData, "type": id, "value": N}（SPIN 后执行），空字典表示已执行/未定
var enemy_element: String = "none"     # 敌人属性元素（用于单向克制：玩家符号元素 → 敌人元素）
var pending_jam_reel = -1              # 敌人注废 → 下一轮强制废铁列索引（-1 无）
var pending_lock_reel = -1             # 敌人锁轮 → 下一轮该列固定为当前符号（-1 无）
var pending_chaos = false              # 敌人乱权 → 下一轮权重削弱优势符号
var pending_auto_stop = false          # 敌人夺轮（auto_stop）→ 下一轮转轮自动停止（落点随机，无法目押）
# 净化完全走消耗品（净化药剂·charges 用尽即移出腰带），不再有"净化上限/净化次数"局内缓存

# M6 护符被动（整局生效，_apply_charms 在 _confirm_loadout 结算）
var charm_power_bonus: int = 0         # 锋锐护符：本局所有伤害符号 +N
var charm_room_shield: int = 0         # 守望护符：每房开局护盾 +N
var charm_shield_trickle: int = 0      # 守备护符：每回合护盾涓流（整局生效，见 §8）
var charm_heal_trickle: int = 0       # 回春护符：每回合回复（与瞬回药剂互补）
var charm_interf_resist: int = 0       # 抗扰护符：本局敌人干扰概率降低（等效抗扰等级）
# 净化完全走消耗品，「丰沛护符·净化上限」机制已废除（charm_purify_bonus 字段随之删除，purify_charm.tres 已删除）

var charm_damage_mult: float = 1.0      # Phase G v2.0：护符全局乘区，默认 ×1.0
var charm_dot_reduce: int = 0            # 2026-08-09 蚀毒壁垒护符：玩家侧挂毒量每回合 -N（acid_bomb 系 BOSS 读取）
var deprived_level: int = 0              # 无名虚空（emotional_vacuum）：装备剥夺开关——0=正常 / 1=护符禁 / 2=护符+技能禁（聚合层消费点读取）
# T2 护符三项缺口（2026-08-07 落地，BOSS 克制矩阵 §59/§60/§62）：
var charm_pierce_chance: float = 0.0    # 破甲护符：非穿透伤害符号直击 HP（穿透护甲）概率 0~1
var charm_element_boost: float = 0.0    # 元素优势护符：克制倍率额外加成（×1.5 → ×1.5+boost，仅克制时）
var charm_status_boost: float = 1.0     # 状态护符：灼烧/霜冻/毒 DoT 伤害倍率
# BOSS 信物（12 个 epic 稀有护符，2026-08-14，见 docs/BOSS信物_设计方案.md）：
var charm_thorns: float = 0.0           # 石屑之心：敌人攻击反弹比例（0.2 = 反弹 20%）
var charm_dot_amp: int = 0              # 毒腺囊：你给敌人挂的 DoT 层数 +N
var charm_free_reroll: int = 0          # 迷宫回声：每房间歇期免费货架刷新次数
var charm_charge_start: int = 0         # 深渊凝视：每回合开始元素充能 +N
var charm_first_hit: float = 1.0        # 碎片王冠：每回合首个伤害符号倍率（1.5 = ×1.5）
var _turn_hit_used := false             # 碎片王冠：本回合是否已吃过首击加成（evaluate 重置）

# 流程状态（enum 化：原字符串字面量易拼错且无编译期检查）
enum FlowState { PLAYING, WON, LOST }
var game_state: FlowState = FlowState.PLAYING
var peaceful_win := false              # 勇者的阴影 P3：和解通关标志（_start_room 复位；spin 流程检测早退）
var turn_count = 1

# M4 本局（Run）加成层（run_symbol_bonus / run_power_bonus / run_shield_next）已抽至
# RewardSystem（步骤4，见 _reward_system）；reward_choices / reward_is_boss 仍由本 controller 持有（HUD 直读写）
var reward_choices: Array = []         # 当前展示的 3 个奖励
var reward_is_boss: bool = false       # 当前奖励是否来自 Boss 房（选完开新局）
# S7/S12 商店状态（shop_offers / paid_price）已抽至 ShopSystem（步骤3，见 _shop_system）

# M5 元进度（铁砧锻造 + 存档持久化，跨局保留）
# 已退役键（元进度三选一退化为仅 anvil）：weapon_upgrades / weapon_base_bonus / weapon_hit_bonus / charm_upgrades / interference_resist / first_clears
var meta: Dictionary = {"anvil_points": 0, "owned_weapons": [], "owned_charms": [], "owned_consumables": [], "anvil_pity": 0, "collection_milestones": []}
var _anvil_system                     # 铁砧锻造子系统 AnvilSystem（步骤2抽出；_ready 实例化并注入 self）
const ANVIL_SAVE_KEY := "anvil_meta"   # 铁砧元进度存于 SaveSystem.lobby_data
var _meta_store                        # 存档子系统 MetaStore（步骤1抽出；_ready 实例化并注入 self + meta）
var _shop_system                       # 商店子系统 ShopSystem（步骤3抽出；_ready 实例化并注入 self）
var _reward_system                     # 奖励子系统 RewardSystem（步骤4抽出；_ready 实例化并注入 self）
var _loadout_system                    # 整备子系统 LoadoutSystem（步骤5抽出；_ready 实例化并注入 self）
var _synergy_system                    # 装备共鸣系统 SynergySystem（方案 B 配套；_ready 实例化并注入 self）

# 仅 1 行 3 格。特殊符号需 3 同才触发；普通符号单颗即结算，出现 n 次 ×n。
var PAYLINES = [
	[[0,0],[1,0],[2,0]],
]

# —— P1：只读状态快照（HUD 渲染只从此读，不再直读下方私有字段）——
# 性能优化（2026-08-14）：快照缓存 + 显式置脏——每次访问重建会在转轮旋转热路径
# （_refresh_cell 每跳每列多次读 state）产生每秒数百次 BattleState 分配；现改为
# 写入方在语义函数末尾调用 invalidate_state()（读取方 _refresh_meta 前置脏兜底，
# 防未来新增 gimmick 直写字段漏网），热路径纯命中缓存。
var _state_cache: BattleState = null
var _state_dirty := true

var state: BattleState:
	get:
		if _state_dirty:
			_state_cache = _build_state()
			_state_dirty = false
		return _state_cache

func invalidate_state() -> void:
	_state_dirty = true

func _build_state() -> BattleState:
	return BattleState.build(self)   # P2：快照构建迁至 BattleState.build（数据类自带工厂）



const BATTLE_HUD = preload("res://scenes/ui/battle_hud.tscn")
var hud: BattleHud
var reel_system: ReelSystem             # 2026-08-09 拆分：转轮带/旋转/按停逻辑（reel_system.gd）
var combat: CombatSystem                # 2026-08-09 拆分：回合结算/符号贡献/敌我攻防（combat_system.gd）
var status_system: StatusSystem         # 2026-08-09 拆分：意图/状态定义与查询（status_system.gd）
var consumable_system: ConsumableSystem # 2026-08-09 拆分：消耗品使用/效果分发（consumable_system.gd）
var enemy_system: EnemySystem           # 2026-08-09 拆分：敌人回合/意图执行（enemy_system.gd）
var run_setup                         # P2 架构还债（2026-08-24）：对局构建/BOSS 抽取/ante 曲线（run_setup.gd，preload 实例化）
var room_flow                         # P2 架构还债（2026-08-24）：房间推进/间歇态/元进度/铁砧编排（room_flow.gd）
var turn_flow                         # P2 架构还债（2026-08-24）：SPIN 主流程/回合开始/免费重转/和解（turn_flow.gd）

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	run_setup = preload("res://scripts/battle/run_setup.gd").new(self)   # 须先于 ALL_ROOMS 扫描（_sort_rooms 依赖）
	# Phase D：文件夹自动扫描内容池（替代手写路径数组）。必须在构建整备界面之前完成。
	# 扫描返回未泛型 Array，经 assign() 显式转为泛型（元素逐一校验）。
	WEAPON_POOL.assign(ResourceScan.scan_paths("res://resources/weapon_templates/"))
	ITEM_POOL.assign(ResourceScan.scan_paths("res://resources/charms/") + ResourceScan.scan_paths("res://resources/consumables/"))
	SKILL_POOL.assign(ResourceScan.scan_paths("res://resources/skills/"))
	ALL_ROOMS.assign(_sort_rooms(ResourceScan.scan_resources("res://resources/rooms/", "RoomData")))
	for r in ALL_ROOMS:
		if not ElementCounter.is_valid_element(r.element):
			push_warning("房间 %s 元素非法：%s" % [r.name, r.element])   # 启动即暴露错字，防战斗中才发现
	REWARD_POOL.assign(ResourceScan.scan_resources("res://resources/rewards/", "RewardData"))
	ELITE_REWARD_POOL.assign(ResourceScan.scan_resources("res://resources/rewards/elite/", "RewardData"))
	# 导出构建防御：池为空即告警（防 ResourceScan 回归导致导出内容缺失——2026-08-10 修复）
	if OS.has_feature("template") and WEAPON_POOL.is_empty():
		push_warning("导出构建：武器池为空——资源扫描可能失效，请检查 ResourceScan")
	if OS.has_feature("template") and ALL_ROOMS.is_empty():
		push_warning("导出构建：房间池为空——资源扫描可能失效，请检查 ResourceScan")
	hud = BATTLE_HUD.instantiate()
	add_child(hud)
	hud.controller = self
	_meta_store = preload("res://scripts/systems/meta_store.gd").new(self, meta)
	_anvil_system = preload("res://scripts/systems/anvil_system.gd").new(self)
	_shop_system = preload("res://scripts/systems/shop_system.gd").new(self)
	_reward_system = preload("res://scripts/systems/reward_system.gd").new(self)
	_loadout_system = preload("res://scripts/systems/loadout_system.gd").new(self)
	_synergy_system = preload("res://scripts/systems/synergy_system.gd").new(self)
	# 2026-08-09 拆分：转轮系统独立（ReelSystem）
	reel_system = ReelSystem.new(self)
	combat = CombatSystem.new(self)
	status_system = StatusSystem.new(self)
	consumable_system = ConsumableSystem.new(self)
	enemy_system = EnemySystem.new(self)
	room_flow = preload("res://scripts/battle/room_flow.gd").new(self)
	turn_flow = preload("res://scripts/battle/turn_flow.gd").new(self)
	_meta_store.load_meta()
	_meta_store.sanitize_owned()   # 自愈：清洗历史上误写入 owned_* 的非本类路径（如技能）
	_meta_store.seed_default_owned()
	hud.build_all()   # P2：HUD 自构建全部界面（build_all 内部调各 _build_* + _show_loadout_screen），controller 不再戳私有构建方法
	# P2：HUD 意图信号 → controller 处理器（HUD 不再调用 controller 私有方法）
	hud.spin_requested.connect(_on_spin_button_pressed)
	hud.reel_clicked.connect(_on_reel_clicked)
	hud.buy_requested.connect(_on_shop_buy_pressed)
	hud.buy_replace_requested.connect(_on_shop_buy_replace_pressed)
	hud.sell_requested.connect(_on_shop_sell_pressed)
	hud.shop_reroll_requested.connect(_on_shop_reroll_pressed)
	hud.reward_chosen.connect(_on_reward_chosen)
	hud.boss_reward_chosen.connect(_on_boss_reward_chosen)
	hud.reward_skip_requested.connect(_on_reward_skip_pressed)
	hud.shop_requested.connect(_on_shop_requested)
	hud.next_room_requested.connect(_on_next_room_pressed)
	hud.card_toggled.connect(_loadout_system.on_card_toggled)
	hud.meta_choice_chosen.connect(_on_meta_choice_chosen)
	hud.overlay_button_pressed.connect(_on_overlay_button_pressed)
	hud.consumable_used.connect(_on_consumable_pressed)
	hud.shop_leave_requested.connect(_on_shop_leave_pressed)
	hud.anvil_back_requested.connect(_on_anvil_back_pressed)
func _build_pool(loadout: Array) -> void:
	reel_system.build_pool(loadout)   # P2 架构还债（2026-08-24）：池构建迁 ReelSystem（池/带子/落子同域）


# 符号「有效元素」解析已随池构建迁 reel_system.eff_element（唯一调用方是建池本身）。


# ---------------------------------------------------------------------------
# 房奖励 / BOSS 战利品 / 清房推进 / 元进度确认：已迁 RoomFlow（P2 架构还债，2026-08-24）——单行转发。
# ---------------------------------------------------------------------------
func _on_reward_chosen(id: String) -> void:
	room_flow.finish_room(func(): _reward_system.apply_reward(id), reward_is_boss)


func _on_reward_skip_pressed() -> void:
	room_flow.finish_room(Callable(), reward_is_boss)


func _on_boss_reward_chosen(cand: Dictionary) -> void:
	# 武器槽上限 2：BOSS 武器战利品满 2 时 → 替换弹层（旧武器回 owned 图鉴）
	if cand.get("kind", "") == "boss_weapon" and selected_loadout.size() >= 2:
		var p: String = cand.get("path", "")
		if p != "" and not selected_loadout.has(p):
			var info := ""
			var res: WeaponData = load(p)
			if res != null:
				var elem_txt := ElementCounter.label(res.element)
				var hit_pct: int = int(res.hit_rate * 100)
				info = "新武器：%s · %s · 攻%d · 命中%d%% · %s" % [cand.get("label", "?"), res.rarity, int(res.base_power), hit_pct, elem_txt]
			else:
				info = "新武器：%s" % cand.get("label", "?")
			hud.request_weapon_replace("★ BOSS 战利品：替换武器", info, func(old_path: String):
				_apply_boss_weapon_replace(p, old_path))
			return
	_finish_room(func(): _reward_system.apply_boss_reward(cand), true)


func _apply_boss_weapon_replace(p: String, old_path: String) -> void:
	if p == "" or not selected_loadout.has(old_path) or selected_loadout.has(p):
		_finish_room(Callable(), true)
		return
	var old_name = _shop_name(old_path, "weapon")
	selected_loadout.erase(old_path)
	selected_loadout.append(p)
	if not meta["owned_weapons"].has(p):
		meta["owned_weapons"].append(p)
	_build_pool(selected_loadout)
	hud._log("BOSS 武器替换：%s → %s" % [old_name, _shop_name(p, "weapon")])
	_finish_room(Callable(), true)


func _finish_room(apply_fn: Callable, is_boss: bool) -> void:
	room_flow.finish_room(apply_fn, is_boss)


func _on_meta_choice_chosen(opt: Dictionary) -> void:
	room_flow.on_meta_choice_chosen(opt)


func _confirm_loadout() -> void:
	_loadout_system.confirm_loadout()


func _apply_charms() -> void:
	_loadout_system.apply_charms()


# M5 元进度（铁砧锻造 + 存档持久化）已全迁至 MetaStore（load/save/seed/sanitize/award_gold）
# ---------------------------------------------------------------------------
# S6–S12 商店逻辑已抽至 ShopSystem（步骤3）：shop_price / shop_name / roll_shop /
# on_shop_buy_pressed / sell_price / on_shop_sell_pressed
func _shop_price(kind: String, owned: int = -1, item_path: String = "") -> int:
	return _shop_system.shop_price(kind, owned, item_path)


func _shop_name(path: String, kind: String) -> String:
	return _shop_system.shop_name(path, kind)


func _roll_shop() -> void:
	_shop_system.roll_shop()


# 商店状态变更后的统一 UI 刷新（买卖/金币升级共用，防新增路径漏刷）
func _after_shop_change() -> void:
	hud._refresh_shop()
	hud._refresh_meta()


func _on_shop_buy_replace_pressed(offer: Dictionary, old_path: String) -> void:
	_shop_system.on_shop_buy_replace_pressed(offer, old_path)
	_after_shop_change()


func _on_shop_buy_pressed(offer: Dictionary) -> void:
	_shop_system.on_shop_buy_pressed(offer)
	_after_shop_change()


func _sell_price(kind: String, path: String) -> int:
	return _shop_system.sell_price(kind, path)


func _on_shop_sell_pressed(path: String, kind: String) -> void:
	_shop_system.on_shop_sell_pressed(path, kind)
	_after_shop_change()


# 商店货架刷新（2026-08-09）：Balatro 式递增价 + 每房间歇期限次，见 shop_system.on_shop_reroll_pressed
func _on_shop_reroll_pressed() -> void:
	_shop_system.on_shop_reroll_pressed()
	_after_shop_change()


func _on_shop_leave_pressed() -> void:
	room_flow.on_shop_leave_pressed()


# 间歇态 / 下一房 / 铁砧入口：已迁 RoomFlow（P2 架构还债，2026-08-24）——单行转发。
func _enter_interroom(roll_shop: bool = true) -> void:
	room_flow.enter_interroom(roll_shop)


func _on_shop_requested() -> void:
	room_flow.on_shop_requested()


func _on_next_room_pressed() -> void:
	room_flow.on_next_room_pressed()


func _on_anvil_roll_pressed() -> void:
	room_flow.on_anvil_roll_pressed()


func _on_anvil_back_pressed() -> void:
	room_flow.on_anvil_back_pressed()


func _full_reset() -> void:
	_loadout_system.full_reset()


# 新一局公共状态重置（不含开战）：已迁至 LoadoutSystem.reset_run_state（P2 架构还债，2026-08-24）——单行转发。
func _reset_run_state() -> void:
	_loadout_system.reset_run_state()


# 房间是否为 BOSS 房：以 RoomData.kind == "boss" 判定（不再依赖「最后一间」的位置约定，
# 否则插入熔毁之间等中间房型会让 BOSS 判定错位）。
func _is_boss_room(idx: int) -> bool:
	return idx >= 0 and idx < ROOMS.size() and ROOMS[idx].kind == "boss"


# 是否为本局最后一间房（=通关整局）。S10 起一局有 3 个幕 BOSS，只有最后一个才结束 run：
# 幕一/幕二 BOSS 通关后照常进商店并推进下一房，否则幕二幕三永远进不去。
func _is_run_final(idx: int) -> bool:
	return idx >= ROOMS.size() - 1


# T25 对局构建 / BOSS 加权抽取 / 房间语义排序：已迁至 RunSetup（P2 架构还债，2026-08-24）——单行转发。
func _build_run() -> Array[RoomData]:
	return run_setup.build_run()


func _pick_boss(candidates: Array) -> RoomData:
	return run_setup.pick_boss(candidates)


func _sort_rooms(rms: Array) -> Array:
	return run_setup.sort_rooms(rms)


func _start_room(idx: int) -> void:
	if idx >= ROOMS.size():                 # 兜底：越界视为通关整局，走元进度三选一而非崩溃
		_reward_system.show_meta_choice()
		return
	room_element_mult = {}                # 元素精华：新房间失效（须在 _build_pool 之前清，否则旧房精华注入新房池）
	peaceful_win = false                  # 勇者的阴影：和解标志每房复位
	_apply_charms()                         # S7：每次开房重算护符被动（含商店购入的护符）
	_build_pool(selected_loadout)           # S7：重建符号池（含商店购入的武器）
	room_index = idx
	var r: RoomData = ROOMS[idx]
	enemy_name = r.name
	# ante 难度曲线：RoomData.hp/atk 视为基础值（T5：为 0 时取行为族基准），按「幕间台阶 × 幕内爬升」缩放。
	var s = _ante_scale(r, room_index)
	var base_hp: int = r.hp if r.hp > 0 else (r.archetype.hp_base if r.archetype != null else 0)
	var base_atk: int = r.atk if r.atk > 0 else (r.archetype.atk_base if r.archetype != null else 0)
	enemy_hp_max = int(round(float(base_hp) * s["hp_scale"]))
	enemy_hp = enemy_hp_max
	enemy_atk = int(round(float(base_atk) * s["atk_scale"]))
	enemy_element = r.element if r.element != "" else "none"   # 单向克制：敌人属性（仅供玩家符号克制判定）
	# 护甲（扁平池）：随 ante 缩放；为 0 时取行为族护甲倾向；BOSS 机制可在此基础上成长
	var base_armor: int = r.armor if r.armor > 0 else (r.archetype.armor_base if r.archetype != null else 0)
	enemy_armor_max = int(round(float(base_armor) * s["hp_scale"])) if base_armor > 0 else 0
	enemy_armor = enemy_armor_max
	# 抗干扰（T20）：抗扰护符 降低干扰类意图（purifiable）权重，每级 -12%，最低保留 25%
	var total_resist = charm_interf_resist
	_interf_resist_rf = max(0.25, 1.0 - total_resist * 0.12) if total_resist > 0 else 1.0
	enemy_status = {}
	charge_points = 0                     # T21：元素充能每房清零
	_charge_elem_counts = {}              # 主导元素统计随充能清零
	player_frost = 0                      # T30：寒霜侵蚀每房清零（BOSS 战状态，不跨房）
	frozen_cols = []                      # T30：冻结列随 frost 清零
	player_status = {}                    # 2026-08-09：玩家侧 DoT 每房清零（BOSS 战状态，不跨房）
	player_dot_bomb_stacks = 10           # 2026-08-09：爆炸阈值回落默认（gimmick on_room_start 覆盖）
	player_buffs = {}                     # Phase C：主动技能不跨房保留
	player_shield = 0
	player_shield += _reward_system.run_shield_next   # M4：上一房奖励的结界在本房开局生效
	player_shield += charm_room_shield    # M6：守望护符每房开局护盾（无名虚空由 gimmick on_room_start 扣回）
	_reward_system.run_shield_next = 0
	pending_jam_reel = -1
	pending_lock_reel = -1
	pending_chaos = false
	pending_auto_stop = false
	# 净化完全走消耗品（净化药剂·charges 用尽即移出腰带），无需每房回满
	game_state = FlowState.PLAYING                # 必须在重建消耗品按钮前置为 playing，否则房间过渡瞬间按钮被误判为禁用
	_refresh_consumable_panel()
	turn_count = 0   # 首回合由 _begin_player_turn 统一 +1（经典回合结构：计数在回合开始）
	enemy_intent = {}
	hud._hide_overlay()
	reel_system.build_strips()
	reel_system.reset_grid()
	# BOSS 专属立绘（RoomData.art 数据驱动）：有 art 时旧敌人图退场 + 新图入场；无 art 恢复默认
	hud.set_enemy_art(r.art, r.art_scale)
	# S10 T2：BOSS 机制实例化（仅 BOSS 房；非 BOSS 房置 null，钩子调用处显式判空跳过）
	current_gimmick = null
	boss_atk_mult = 1.0
	boss_trash = 0
	# 课程化（2026-08-24）：精英房挂 BOSS gimmick 弱化版（mini 机制）——门控从「仅 boss」
	# 放宽为「凡配置了 gimmick_script 即实例化」；普通房不配脚本，行为不变。
	if r.gimmick_script != null:
		current_gimmick = r.gimmick_script.new()
		current_gimmick.on_room_start(self)
	_begin_player_turn()
	_refresh_consumable_panel()           # 双重保险：同步按钮禁用状态与当前战斗状态
	hud._refresh_meta()
	hud._update_enemy_element()
	hud._log("▶ 进入房间 %d/%d：%s（HP %d，攻击 %d）" % [idx + 1, ROOMS.size(), enemy_name, enemy_hp_max, enemy_atk])
	invalidate_state()


# Ante 难度曲线纯函数：已迁至 RunSetup.ante_scale（P2 架构还债，2026-08-24）——单行转发。
func _ante_scale(r: RoomData, idx: int) -> Dictionary:
	return run_setup.ante_scale(r, idx)


func _begin_player_turn() -> void:
	turn_flow.begin_player_turn()


# 勇者的阴影 P3：非暴力和解通关（gimmick 调用）——已迁 TurnFlow（P2 架构还债，2026-08-24）。
func resolve_peaceful_win() -> void:
	turn_flow.resolve_peaceful_win()


# T20：加权抽取意图（已迁至 StatusSystem.roll_intent，2026-08-09）
func _roll_intent(room: RoomData) -> Dictionary:
	return status_system.roll_intent(room)


func _on_spin_pressed() -> void:
	turn_flow.on_spin_pressed()   # 协程体在 TurnFlow（fire-and-forget，调用方不 await——语义同前）


# SPIN 按钮：旋转中=停止下一列，否则开始旋转。
func _on_spin_button_pressed() -> void:
	if reel_system.spinning:
		reel_system.stop_next_reel()
	else:
		_on_spin_pressed()


# 点击某列直接锁定该列（旋转中有效）。
func _on_reel_clicked(r: int) -> void:
	if not reel_system.spinning or reel_system.reel_stopped[r]:
		return
	reel_system.lock_reel(r)


# 重转卷轴：免费重转一次（不触发敌人回合）
func _free_spin() -> void:
	turn_flow.free_spin()


func _intent_name(t: String) -> String:
	return status_system.intent_name(t)


# ---------------------------------------------------------------------------
# M6 消耗品：战斗中主动使用（2026-08-09 逻辑已迁至 ConsumableSystem，此处仅留信号转发）
# ---------------------------------------------------------------------------
# 4 格子（2x2）由 HUD 自管，本函数只触发刷新同步状态（不增删 cell，charges 用尽直接移出 slots 即可）
func _refresh_consumable_panel() -> void:
	hud._refresh_consumable_panel()


func _on_consumable_pressed(uid: String) -> void:
	consumable_system.use(uid)


func _on_overlay_button_pressed() -> void:
	room_flow.on_overlay_button_pressed()


func _return_to_loadout() -> void:
	room_flow.return_to_loadout()


# ---------------------------------------------------------------------------
# 结算与属性聚合已拆分至 CombatSystem（scripts/battle/combat_system.gd，2026-08-09）：
#   contribute / push_dmg_line / evaluate / agg_* / grant_buff / tick_buffs /
#   enemy_deal_damage / apply_enemy_damage / on_counter / tick_status / release_element_burst
# 本控制器仅保留流程编排（_enemy_turn / _buff_summary / 状态工具）。

# ---------------------------------------------------------------------------
# Phase C 主动增益：符号自描述（sym.buff_effect / buff_value / buff_turns），零查表
# player_buffs: SymbolData -> 剩余回合数
# ---------------------------------------------------------------------------
func _buff_summary() -> String:
	return BattleMath.buff_summary(player_buffs)


func _buff_effect_name(effect: String) -> String:
	return status_system.buff_effect_name(effect)


func _status_def(st: String) -> StatusDef:
	return status_system.status_def(st)


func _status_base(type_str: String) -> float:
	return status_system.status_base(type_str)


# 状态类型对应的属性元素（用于 DoT 单向克制）
func _status_element(st: String) -> String:
	return status_system.status_element(st)


func _status_summary(stacks: Dictionary) -> String:
	return status_system.status_summary(stacks)


# ---------------------------------------------------------------------------
# 表现刷新
# ---------------------------------------------------------------------------
func _input(event) -> void:
	if in_loadout:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		if reel_system.spinning:
			reel_system.stop_next_reel()
		else:
			_on_spin_pressed()
