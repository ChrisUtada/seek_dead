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
# M4-01：ACT1 Demo 开关 + 内容白名单（resources/config/demo_config.tres，enabled 或导出 custom_features 启用）
const DEMO_CONFIG = preload("res://resources/config/demo_config.tres")
var demo_config = DEMO_CONFIG   # 无 class_name：避免 headless 首次加载的全局类缓存依赖
# M2：ACT1 棋盘灰盒开关（resources/config/board_config.tres，enabled 或命令行 --board 启用）
const BOARD_CONFIG = preload("res://resources/config/board_config.tres")
var board_config = BOARD_CONFIG
const NODE_START_FEEDBACK := "起点：掷骰前进"

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
# M1-03：新档改为只播种基础子集（MetaStore.STARTER_*），SMALL_OWNED 调试开关已删除（不再需要压缩全池）。

# M4 房奖励池（每清一房随机 3 选 1；Boss 房走同池但标为「残余物」）。
# Phase D 资源化：改为扫描 resources/rewards/*.tres（RewardData），见 _ready 内填充。
var REWARD_POOL: Array[RewardData] = []

# T6 精英房专属「战前补给」奖励池（扫描 resources/rewards/elite/）。
# 精英房卡在每个 BOSS 前，定位为「补给锚点」而非普通小增益 / BOSS 战力飞跃，
# 故与普通房奖励池解耦，提供 金币囤 / 铁砧点 / 结界备战 三类 prep 选项。
var ELITE_REWARD_POOL: Array[RewardData] = []

# 房间序列（肉鸽逐房推进）。
# 2026-08-09 拆分：意图/状态定义与查询（INTENT_DEFS / STATUS_DEFS / _roll_intent / _status_*）迁至 StatusSystem。
# Phase D 资源化：改为扫描 resources/rooms/*.tres（RoomData），见 _ready 内填充。
var ALL_ROOMS: Array[RoomData] = []          # 全量房间池（扫描收集；_build_run 从中按幕抽 24 房 + 真·最终槽）
var ROOMS: Array[RoomData] = []             # 当前一局的房序列（每局 _full_reset 时由 _build_run 重建：24 房 + 真·最终）

# M2 棋盘模式状态。棋盘模式下 ROOMS = 本局全部战斗房（按路径顺序），room_index 仍是其在 ROOMS 中的下标，
# 因此既有 ROOMS[room_index] 消费者（奖励 / 铁砧 / gimmick / HUD）保持不变。
# current_room / current_act / current_room_ria / run_final 是线性强索引之外的第二状态源，
# 供棋盘入口显式传入当前 RoomData 与幕内难度位置，不再用 ROOMS.size() 混合表达进度。
var node_mode := false                      # 本局是否棋盘模式（BoardConfig 开关）
var board                                   # M2 棋盘运行状态（board_system.gd，preload 实例化）
var current_room: RoomData = null
var current_act: int = 1
var current_room_ria: int = -1              # -1 = 线性模式按 ROOMS 扫描计算
var run_final := false                      # 棋盘模式：当前是否本局最终战

# grid[reel][row] = SymbolData 引用
var grid = []
# grid_elem[reel][row] = 该格符号的「有效元素」（武器元素继承后的实际元素，用于逐符号克制结算）
var grid_elem = []
# grid_src[reel][row] = 实际停中格的来源武器 id。符号族仍负责同族连线，来源负责完整图标与物品特性。
var grid_src: Array = []
# 单源或无来源格子的图标兜底；多源格必须读 grid_src / 带子 entry[2]，不能再只显示最高攻来源。
var _sym_src_map: Dictionary = {}

# 合并后的加权符号池：元素为 [SymbolData, weight, element]（element = 有效元素）
var pool: Array[Array] = []
var loadout_names: Array[String] = []
# 基础键 = 符号路径，保留单源/技能/旧探针口径；扩展键 = 符号路径|武器id，保存该来源自己的数值。
var _weapon_power_map: Dictionary = {}
var _item_crit_map: Dictionary = {}
var _item_crit_chance_map: Dictionary = {}
var _item_pierce_map: Dictionary = {}
var _item_pierce_at: Dictionary = {}
var _item_status_bonus: Dictionary = {}
var _source_archetype_map: Dictionary = {} # 武器id -> WeaponData.Archetype，用于同源三连原型效果
var _source_weapon_type_map: Dictionary = {} # 武器id -> WeaponData.WeaponType，用于远程穿透
var pool_items: Array[Dictionary] = []              # 装备自洽：每件装备一段 [ {name, hit, syms:[[SymbolData, weight, element]]} ]，_build_strips 据此生成各自的转轮子带

var _busy: bool = false                 # 旋转序列进行中，防重入
var _eval_adv := false                  # _evaluate 阶段2：本回合是否触发过「克制」
var _eval_dis := false                  # _evaluate 阶段2：本回合是否触发过「抵抗」
var _elem_triple := false               # 同元素3格触发元素共鸣：充能与状态强化，不再自动必暴+核爆
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
var enemy_stunned := 0                 # 2026-11-12 Step 2：敌人下一次行动失效（裂石像破甲窗口），由 EnemySystem 消耗
var turn_damage_elems: Array[String] = []   # 2026-11-12 Step 2：本回合实际造成伤害的元素（余烬傀儡等元素触发读取）
# —— 2026-11-12 Step 3：普通怪机制通用支撑（全部确定性，不消耗 RNG）——
var turn_resolved := false             # 本回合是否已进入结算（debuff 计时区分「转轮前/后施加」）
var last_enemy_intent: Dictionary = {} # 上一次敌人实际执行的意图（虚空低语者/回响复制用）
var enemy_extra_attacks: Array = []    # 本次行动追加攻击 [{"value": int, "poison": int}]，执行后清空
var enemy_attack_poison := 0           # 本次行动命中后附加给玩家的毒层数，执行后清空
var enemy_attack_pierce_pct := 0.0     # 本次行动按比例穿透护盾（圣辉游侠），执行后清空
var enemy_self_damage_after := 0       # 本次行动结束后自损 HP（湮灭使徒），执行后清空
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
var meta: Dictionary = {"anvil_points": 0, "owned_weapons": [], "owned_charms": [], "owned_consumables": [], "owned_skills": [], "anvil_pity": 0, "collection_milestones": [], "item_sources": {}, "career": {"unlocked": [], "bosses": []}, "codex": {}, "forge_styles": {}}
var _anvil_system                     # 铁砧锻造子系统 AnvilSystem（步骤2抽出；_ready 实例化并注入 self）
const ANVIL_SAVE_KEY := "anvil_meta"   # 铁砧元进度存于 SaveSystem.lobby_data
var _meta_store                        # 存档子系统 MetaStore（步骤1抽出；_ready 实例化并注入 self + meta）
var _career                            # G6-01：生涯成就子系统 CareerSystem（只读局内事件，跨局记录）
var _run_summary                      # G6-03：局末路线总结（只读本局状态，不写存档）
var _codex                            # G6-04：图鉴详情与跨局使用统计
var _forge_styles                     # G6-05：4 把武器的横向铸式（整备选择，有得有失）
var _trim                             # G7-B B1：主动减带（符号精简 / 技能卸除，每幕 1 次，只改本局状态）
var _shop_system                       # 商店子系统 ShopSystem（步骤3抽出；_ready 实例化并注入 self）
var _camp_offers: Array = []           # G2-01：营地补给货架（休整后一次性购买）
var _reward_system                     # 奖励子系统 RewardSystem（步骤4抽出；_ready 实例化并注入 self）
var _post_battle                       # M1 战后成长三槽 PostBattleSystem（补给/构筑/成长队列）
var _loadout_system                    # 整备子系统 LoadoutSystem（步骤5抽出；_ready 实例化并注入 self）
var _synergy_system                    # 装备共鸣系统 SynergySystem（方案 B 配套；_ready 实例化并注入 self）
var growth                             # M2-01 角色历练与技艺（经验/等级/三选一技艺；每局清零）
var mastery                            # M2-02 武器熟练 R1–R4 与铭印（锋铸/调律；每局清零）
var readability                        # P1 目押可读性原型（速度/预览/视觉落点/缓冲/反馈；不改数值）
var _telemetry                         # M1-06 局内遥测（内存计数，不落盘/不吃随机；每局清零）
var _journal                           # G5 工具：自动记录客观项（只读；导出包/--runlog 才落盘）

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
var debuffs                             # 2026-11-12 Step 1：玩家侧共用减益模块（debuff_system.gd；怪物经 apply_debuff 施加）
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
	_apply_demo_filters()   # M4-01：demo 开关只收窄池，必须在 seed_default_owned / build_all 之前
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
	_post_battle = preload("res://scripts/systems/post_battle_system.gd").new(self)
	board = preload("res://scripts/board/board_system.gd").new(self)   # M2：棋盘状态（默认关闭，线性模式不使用）
	_loadout_system = preload("res://scripts/systems/loadout_system.gd").new(self)
	_synergy_system = preload("res://scripts/systems/synergy_system.gd").new(self)
	growth = preload("res://scripts/systems/growth_system.gd").new(self)
	mastery = preload("res://scripts/systems/weapon_mastery.gd").new(self)
	# G0-02：物品 tooltip 读取运行时武器状态（锋铸后的真实攻击 / R 等级 / 铭印），
	# 静态生成器不持有 controller，由这里注入；共享 .tres 不被修改。
	ItemTooltip.weapon_state_provider = _weapon_tooltip_state
	# P1：可读性预设须先于 ReelSystem（速度由它提供）
	readability = preload("res://scripts/systems/readability_system.gd").new(self)
	# 2026-08-09 拆分：转轮系统独立（ReelSystem）
	reel_system = ReelSystem.new(self)
	combat = CombatSystem.new(self)
	status_system = StatusSystem.new(self)
	debuffs = preload("res://scripts/battle/debuff_system.gd").new()   # Step 1：玩家侧减益（不注册全局 class_name，避免 headless 类缓存）
	consumable_system = ConsumableSystem.new(self)
	enemy_system = EnemySystem.new(self)
	room_flow = preload("res://scripts/battle/room_flow.gd").new(self)
	turn_flow = preload("res://scripts/battle/turn_flow.gd").new(self)
	_telemetry = preload("res://scripts/systems/run_telemetry.gd").new()
	_journal = preload("res://scripts/systems/run_journal.gd").new(self)   # G5 工具：局内自动记录
	_meta_store.load_meta()
	_meta_store.sanitize_owned()   # 自愈：清洗历史上误写入 owned_* 的非本类路径（如技能）
	_meta_store.seed_default_owned()
	_career = preload("res://scripts/systems/career_system.gd").new(self)   # G6-01：生涯成就（只读事件，不改数值）
	_run_summary = preload("res://scripts/systems/run_summary.gd").new(self)   # G6-03：局末路线总结
	_codex = preload("res://scripts/systems/codex_system.gd").new(self)   # G6-04：图鉴详情（只读资源 + meta 统计）
	_forge_styles = preload("res://scripts/systems/forge_style_system.gd").new(self)   # G6-05：铸式（整备选择，运行时修正）
	_trim = preload("res://scripts/systems/strip_trim_system.gd").new(self)   # G7-B B1：主动减带（每幕 1 次）
	hud.build_all()   # P2：HUD 自构建全部界面（build_all 内部调各 _build_* + _show_loadout_screen），controller 不再戳私有构建方法
	# P2：HUD 意图信号 → controller 处理器（HUD 不再调用 controller 私有方法）
	hud.spin_requested.connect(_on_spin_button_pressed)
	hud.reel_clicked.connect(_on_reel_clicked)
	hud.buy_requested.connect(_on_shop_buy_pressed)
	hud.buy_replace_requested.connect(_on_shop_buy_replace_pressed)
	hud.sell_requested.connect(_on_shop_sell_pressed)
	hud.shop_reroll_requested.connect(_on_shop_reroll_pressed)
	hud.reward_chosen.connect(_on_reward_chosen)
	hud.post_battle_growth_chosen.connect(_on_post_battle_growth_chosen)
	hud.loot_offer_chosen.connect(_on_loot_offer_chosen)
	hud.loot_offer_reroll_requested.connect(_on_loot_offer_reroll)
	hud.loot_offer_skip_requested.connect(_on_loot_offer_skip)
	hud.post_battle_defer_requested.connect(_on_post_battle_defer)
	hud.boss_reward_chosen.connect(_on_boss_reward_chosen)
	hud.reward_skip_requested.connect(_on_reward_skip_pressed)
	hud.shop_requested.connect(_on_shop_requested)
	hud.next_room_requested.connect(_on_next_room_pressed)
	hud.card_toggled.connect(_loadout_system.on_card_toggled)
	hud.meta_choice_chosen.connect(_on_meta_choice_chosen)
	hud.career_unlock_chosen.connect(_on_career_unlock_chosen)
	hud.overlay_button_pressed.connect(_on_overlay_button_pressed)
	hud.consumable_used.connect(_on_consumable_pressed)
	hud.shop_leave_requested.connect(_on_shop_leave_pressed)
	hud.anvil_back_requested.connect(_on_anvil_back_pressed)


# M4-01：ACT1 Demo 内容收窄（关闭时零影响）。只过滤池，不删除存档已有内容。
# 白名单覆盖 ACT1 全量敌人/装备；ACT1 四 BOSS 主题武器里不在白名单的（如 flame_staff）在奖励候选处再过滤。
func demo_active() -> bool:
	return demo_config.is_active()

func _apply_demo_filters() -> void:
	if not demo_config.is_active():
		return
	WEAPON_POOL.assign(demo_config.filter_weapons(WEAPON_POOL))
	ITEM_POOL.assign(demo_config.filter_items(ITEM_POOL))
	SKILL_POOL.assign(demo_config.filter_skills(SKILL_POOL))
	if demo_config.act_only:
		var act1_rooms: Array[RoomData] = []
		for r in ALL_ROOMS:
			if not r.final_boss and int(r.act) == 1:
				act1_rooms.append(r)
		ALL_ROOMS.assign(act1_rooms)
	# 启动日志：试玩包 / 编辑器里一眼确认白名单已生效，也便于按日志定位试玩反馈
	Debug.log("◆ ACT1 DEMO 模式：武器 %d / 技能 %d / 道具 %d / 房间 %d%s" % [
		WEAPON_POOL.size(), SKILL_POOL.size(), ITEM_POOL.size(), ALL_ROOMS.size(),
		"（仅 ACT1，不含真·最终）" if demo_config.act_only else "（全幕）"])

func _build_pool(loadout: Array) -> void:
	reel_system.build_pool(loadout)   # P2 架构还债（2026-08-24）：池构建迁 ReelSystem（池/带子/落子同域）


# 符号「有效元素」解析已随池构建迁 reel_system.eff_element（唯一调用方是建池本身）。


# ---------------------------------------------------------------------------
# 房奖励 / BOSS 战利品 / 清房推进 / 元进度确认：已迁 RoomFlow（P2 架构还债，2026-08-24）——单行转发。
# ---------------------------------------------------------------------------
func _on_reward_chosen(id: String, index: int = -1) -> void:
	if _telemetry != null:
		_telemetry.on_reward_pick(id)   # M1-06：奖励选择率
	# M1-01：满双武器时武器奖励不再被隐藏——卡片展示前已定具体武器，选择后走替换弹层
	if id == "weapon":
		var payload: Dictionary = _reward_system.payload_at(index)
		var p: String = String(payload.get("path", ""))
		if p != "" and not selected_loadout.has(p) and selected_loadout.size() >= _loadout_system.cat_cap("weapon"):
			hud.request_weapon_replace("胜利奖励：替换武器", _weapon_info(p), func(old_path: String) -> void:
				_apply_reward_weapon_replace(p, old_path), p)
			return
	room_flow.finish_room(func(): _reward_system.apply_reward(id, index), reward_is_boss)


# 武器奖励替换：旧武器回收藏（本局卸下），新武器进槽并入图鉴；替换即消耗本次奖励
func _apply_reward_weapon_replace(p: String, old_path: String) -> void:
	if p == "" or not selected_loadout.has(old_path) or selected_loadout.has(p):
		room_flow.finish_room(Callable(), reward_is_boss)
		return
	var old_name = _shop_name(old_path, "weapon")
	selected_loadout.erase(old_path)
	selected_loadout.append(p)
	_reward_system.remember_weapon(p)
	if _telemetry != null:
		_telemetry.on_weapon_swap()
	if _journal != null:
		_journal.note_weapon_change(String(old_name), _shop_name(p, "weapon"), "奖励")
	_build_pool(selected_loadout)
	hud._log("奖励替换：%s → %s" % [old_name, _shop_name(p, "weapon")])
	room_flow.finish_room(Callable(), reward_is_boss)


# 新武器摘要（商店替换 / 奖励替换 / BOSS 战利品共用）
# G0-02：攻击显示锋铸后的真实值；G6-05：再叠加铸式修正。R 等级 / 熟练 / 铭印与转轮带使用同一份运行时状态。
func weapon_power(path: String) -> int:
	var res: WeaponData = load(path)
	if res == null:
		return 0
	var forge: int = mastery.forge_bonus(path) if mastery != null else 0
	var style: int = _forge_styles.power_bonus(path) if _forge_styles != null else 0
	return int(res.base_power) + forge + style


func weapon_hit(path: String) -> float:
	var res: WeaponData = load(path)
	if res == null:
		return 1.0
	var delta: float = _forge_styles.hit_delta(path) if _forge_styles != null else 0.0
	if mastery != null:
		delta += mastery.hit_bonus(path)   # G7-A S2 校准：并入同一命中通道，不加新乘区
	return clampf(float(res.hit_rate) + delta, 0.0, 1.0)


func _weapon_info(p: String) -> String:
	var res: WeaponData = load(p)
	if res == null:
		return "新武器：%s" % _shop_name(p, "weapon")
	var forge: int = mastery.forge_bonus(p) if mastery != null else 0
	var atk_txt := "攻%d" % weapon_power(p)
	if forge > 0:
		atk_txt += "（锋铸+%d）" % forge
	var out := "新武器：%s · %s · %s · 命中%d%% · %s" % [
		res.weapon_name, res.rarity, atk_txt, int(weapon_hit(p) * 100), ElementCounter.label(res.element)]
	if _forge_styles != null:
		var style_txt: String = String(_forge_styles.describe(p))
		if style_txt != "":
			out += "\n" + style_txt
	if mastery != null:
		for extra in [mastery.progress_text(p), mastery.imprint_text(p)]:
			if String(extra) != "":
				out += "\n" + String(extra)
		var target: int = mastery.catchup_target(p)
		if target > int(mastery.mastery.get(p, 0)):
			out += "\n追赶：熟练 %d → %d（有效清房每房 +1）" % [int(mastery.mastery.get(p, 0)), target]
	return out


# G2-01：当前获取上下文（来源记录用）。只读，不触发状态变化。
func _item_source(loot_source: String = "") -> Dictionary:
	var d := {"act": current_act, "mode": "board" if node_mode else "linear"}
	if loot_source != "":
		d["loot_source"] = loot_source
	if node_mode and board != null:
		var node: Dictionary = board.current_node()
		d["node_id"] = String(board.current_id)
		d["node_type"] = String(node.get("type", ""))
		if current_room == null:
			d["item"] = String(node.get("title", ""))
	if current_room != null:
		d["room"] = String(current_room.name)
		d["room_kind"] = String(current_room.kind)
	return d


# G2-01：替换预览的「旧武器卸下」行——只描述本局当前贡献；熟练/铭印按规则保留。
func _weapon_off_info(p: String) -> String:
	var res: WeaponData = load(p)
	if res == null:
		return "卸下：%s（熟练/铭印保留）" % _shop_name(p, "weapon")
	var atk: int = weapon_power(p)
	var out := "卸下：%s · 攻%d · %s" % [res.weapon_name, atk, ElementCounter.label(res.element)]
	if mastery != null:
		for extra in [mastery.progress_text(p), mastery.imprint_text(p)]:
			if String(extra) != "":
				out += " · " + String(extra)
	out += "（熟练/铭印保留，重装恢复）"
	return out


# ItemTooltip 的运行时状态回调（只读；不改共享资源）。
func _weapon_tooltip_state(path: String) -> Dictionary:
	if mastery == null or path == "":
		return {}
	return {
		"forge": mastery.forge_bonus(path),
		"progress": mastery.progress_text(path),
		"imprint": mastery.imprint_text(path),
		"power": weapon_power(path),
		"hit": weapon_hit(path),
		"style": _forge_styles.describe(path) if _forge_styles != null else "",
	}


func _on_reward_skip_pressed() -> void:
	# 战后阶段：免费跳过战利品并放弃本次成长；其余路径沿用旧跳过。
	if room_flow.post_battle_active:
		room_flow.skip_post_battle()
		return
	room_flow.finish_room(Callable(), reward_is_boss)


# ---------------------------------------------------------------------------
# Step 7：同层三选一交互（查看 / 确认 / 替换 / 重抽 / 跳过）
# ---------------------------------------------------------------------------

# 点击战利品卡：正常授予 / 重复转化直接结算；武器槽满先走替换弹层（取消则留在本屏）。
func _on_loot_offer_chosen(index: int) -> void:
	var opt: Dictionary = _reward_system.loot_offer_option(index)
	if opt.is_empty():
		return
	if String(opt.get("kind", "")) == "queued_growth":
		var growth_res: Dictionary = _reward_system.settle_loot_queued_growth(opt.get("growth_entry", {}))
		if not bool(growth_res.get("ok", false)):
			hud._log("成长结算失败：%s" % String(growth_res.get("reason", "")))
			return
		room_flow.after_loot_settled()
		return
	if bool(opt.get("needs_replace", false)):
		var p := String(opt.get("path", ""))
		if p == "" or selected_loadout.has(p):
			return
		hud.request_weapon_replace("战利品：替换武器", _weapon_info(p),
			func(old_path: String) -> void: _on_loot_replace_chosen(index, old_path), p)
		return
	if _telemetry != null:
		_telemetry.on_reward_pick("loot_" + String(opt.get("kind", "")))
	var res: Dictionary = _reward_system.settle_loot_offer(index)
	if not bool(res.get("ok", false)):
		hud._log("战利品结算失败：%s" % String(res.get("reason", "")))
		return
	room_flow.after_loot_settled()


# 替换弹层选定旧武器：由 RewardSystem 统一结算并置位「已结算」（同一组只发一次）。
func _on_loot_replace_chosen(index: int, old_path: String) -> void:
	var res: Dictionary = _reward_system.settle_loot_replace(index, old_path)
	if not bool(res.get("ok", false)):
		hud._log("战利品替换失败：%s" % String(res.get("reason", "")))
		return
	room_flow.after_loot_settled()


func _on_loot_offer_reroll() -> void:
	room_flow.on_loot_reroll()


func _on_loot_offer_skip() -> void:
	# UI「跳过 · 免费」= 只跳过战利品，不发奖励；成长位照常提供。
	room_flow.skip_loot()


func _on_post_battle_defer() -> void:
	room_flow.defer_growth()


# M1：战后成长屏的成长位（技艺 / 铭印 / 下一房对策）。与奖励卡走同一条收尾路径：
# 应用 → finish_room（三槽屏激活时自动路由到 finish_post_battle）。
func _on_post_battle_growth_chosen(cand: Dictionary) -> void:
	if _telemetry != null:
		_telemetry.on_reward_pick("growth_" + String(cand.get("kind", "")))
	var ok: bool = _post_battle.apply_choice(cand)
	if not ok:
		_post_battle.drop(cand)   # 失效候选不阻塞界面；对应待选仍留在下一房成长位
		hud._log("成长候选已失效，本次未结算")
	else:
		hud._log("📈 %s" % room_flow._growth_summary_text())
	room_flow.finish_room(Callable(), false)


func _on_boss_reward_chosen(cand: Dictionary) -> void:
	if _telemetry != null:
		_telemetry.on_reward_pick("boss_" + String(cand.get("kind", "")))
	# 武器槽上限 2：BOSS 武器战利品满 2 时 → 替换弹层（旧武器回 owned 图鉴）
	if cand.get("kind", "") == "boss_weapon" and selected_loadout.size() >= _loadout_system.cat_cap("weapon"):
		var p: String = cand.get("path", "")
		if p != "" and not selected_loadout.has(p):
			hud.request_weapon_replace("★ BOSS 战利品：替换武器", _weapon_info(p), func(old_path: String):
				_apply_boss_weapon_replace(p, old_path), p)
			return
	_finish_room(func(): _reward_system.apply_boss_reward(cand), true)


func _apply_boss_weapon_replace(p: String, old_path: String) -> void:
	if p == "" or not selected_loadout.has(old_path) or selected_loadout.has(p):
		_finish_room(Callable(), true)
		return
	var old_name = _shop_name(old_path, "weapon")
	selected_loadout.erase(old_path)
	selected_loadout.append(p)
	_reward_system.remember_weapon(p)
	if _telemetry != null:
		_telemetry.on_weapon_swap()
	if _journal != null:
		_journal.note_weapon_change(String(old_name), _shop_name(p, "weapon"), "BOSS 战利品")
	_build_pool(selected_loadout)
	hud._log("BOSS 武器替换：%s → %s" % [old_name, _shop_name(p, "weapon")])
	_finish_room(Callable(), true)


func _finish_room(apply_fn: Callable, is_boss: bool) -> void:
	room_flow.finish_room(apply_fn, is_boss)


func _on_meta_choice_chosen(opt: Dictionary) -> void:
	room_flow.on_meta_choice_chosen(opt)


# G6-02：生涯定向解锁 → 写入拥有池/图鉴 → 继续原有局末元进度结算。
func _on_career_unlock_chosen(path: String) -> void:
	if _career == null or not _career.grant_unlock(path):
		hud._log("生涯解锁：选择失败（候选已失效）")
		return
	var res = load(path)
	var nm := path.get_file().get_basename()
	if res is WeaponData:
		nm = String(res.weapon_name)
	elif res is ItemData:
		nm = String(res.item_name)
	hud._log("生涯解锁：获得 %s（已写入图鉴与开局拥有池）" % nm)
	hud._refresh_meta()
	hud._show_meta_choice()   # 解锁机会已消耗 → 回到铁砧点结算


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
	if room_flow != null:
		room_flow.reset_flow()   # Step 7：清掉上一局未完成的战后结算状态
	if _career != null:
		_career.reset_run()   # G6-01：每局临时成就标记清零（跨局解锁仍在 meta）
	if _run_summary != null:
		_run_summary.snapshot()   # G6-03：记录本局拥有池基线（局末算新收藏）
	if _telemetry != null:
		_telemetry.reset()   # M1-06：新一局遥测清零
	if _journal != null:
		_journal.reset()   # G5 工具：新一局记录清空（start_run 在 full_reset 末尾启动）
	if readability != null:
		readability.reset_run()   # P1：目标声明与停轮统计随新局重置
	if hud != null:
		hud._refresh_p1_ui()


# 房间是否为 BOSS 房：以 RoomData.kind == "boss" 判定（不再依赖「最后一间」的位置约定，
# 否则插入熔毁之间等中间房型会让 BOSS 判定错位）。
func _is_boss_room(idx: int) -> bool:
	return idx >= 0 and idx < ROOMS.size() and ROOMS[idx].kind == "boss"


# 是否为本局最后一间房（=通关整局）。S10 起一局有 3 个幕 BOSS，只有最后一个才结束 run：
# 幕一/幕二 BOSS 通关后照常进商店并推进下一房，否则幕二幕三永远进不去。
# M2：棋盘模式由节点 final 标记显式传入（不再用 ROOMS.size() 表达棋盘总进度）。
func _is_run_final(idx: int) -> bool:
	if node_mode:
		return run_final
	return idx >= ROOMS.size() - 1


# 是否还有下一场战斗（M1 成长位「下一房对策」判定）。棋盘模式看是否已到 BOSS 终局。
func has_next_battle() -> bool:
	if node_mode:
		return not run_final
	return room_index + 1 < ROOMS.size()


# G7-A S4：本局幕数（试玩包 act_only 时强制 1 幕——ALL_ROOMS 已收窄成 ACT1，第二幕会无房可分）。
func run_act_count() -> int:
	var n: int = maxi(1, int(board_config.acts))
	if demo_active() and demo_config.act_only:
		n = 1
	return n


# G7-A S4：幕间推进——只换棋盘与幕号，本局状态（HP/上限/金币/装备/成长/技艺/铭印/消耗品）全部保留，
# 不走 reset_run。返回 false 表示无法进入下一幕（非棋盘 / 已是最后一幕 / 生成失败），调用方负责收口。
func advance_act() -> bool:
	if not node_mode or board == null or not board.generated:
		return false
	var next_act: int = int(board.act) + 1
	var total: int = run_act_count()
	if next_act > total:
		return false
	var prev: Dictionary = board.summary()
	# 按幕生成：不动共享 BoardConfig（否则本局结束后 act 会残留成 2/3）。
	if not board.generate(board_config, next_act):
		push_error("G7-A：ACT%d 棋盘生成失败，本局按通关收口" % next_act)
		hud._log("⚠ ACT%d 棋盘生成失败，本局按通关收口" % next_act)
		return false
	board.act_summaries.append(prev)
	# ROOMS 仍是「本幕全部战斗房、room_index 为其下标」的口径：换幕后同步重建。
	ROOMS.clear()
	for r in board.battle_rooms:
		ROOMS.append(r)
	run_final = false                 # 只有进入最后一幕的 BOSS 节点时才会再置真
	current_act = next_act
	growth.grant_act_boon(next_act)   # G7-A S5 后续：幕间锻魂（符号伤害 +8 / 最大 HP +20）
	if _journal != null:
		_journal.note_act_start(next_act, board.summary(), prev)
	board.set_feedback("%s 完成 → 进入 %s（第 %d/%d 幕）" % [
		Palette.act_name(next_act - 1), board.act_label(), next_act, total])
	hud._log("◆ 幕间：%s 完成 → 进入 %s（HP %d/%d · 金 %d · 装备 %d）" % [
		Palette.act_name(next_act - 1), board.act_label(), player_hp, player_hp_max, gold,
		selected_loadout.size()])
	board.return_to_board()   # 收起战斗态（WON → PLAYING）并展示新一幕棋盘
	invalidate_state()
	return true


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
	start_room_data(ROOMS[idx], idx, -1, false)


# M2：统一战斗入口——显式接收当前 RoomData 与幕内难度位置（棋盘不再依赖线性强索引推断最终 BOSS）。
# ria_override >= 0 时跳过「按 ROOMS 位置扫描同幕房数」的旧口径；线性路径传 -1 保持零行为变化。
func start_room_data(r: RoomData, idx: int, ria_override: int = -1, is_final: bool = false) -> void:
	if r == null:
		return
	room_element_mult = {}                # 元素精华：新房间失效（须在 _build_pool 之前清，否则旧房精华注入新房池）
	peaceful_win = false                  # 勇者的阴影：和解标志每房复位
	_apply_charms()                         # S7：每次开房重算护符被动（含商店购入的护符）
	_build_pool(selected_loadout)           # S7：重建符号池（含商店购入的武器）
	room_index = idx
	current_room = r
	current_act = int(r.act)
	current_room_ria = ria_override
	if node_mode:
		run_final = is_final
	if _telemetry != null:
		_telemetry.on_room_start()   # M1-06：TTK 观测起点
	enemy_name = r.name
	# ante 难度曲线：RoomData.hp/atk 视为基础值（T5：为 0 时取行为族基准），按「幕间台阶 × 幕内爬升」缩放。
	var s = _ante_scale(r, room_index, ria_override)
	var base_hp: int = r.hp if r.hp > 0 else (r.archetype.hp_base if r.archetype != null else 0)
	var base_atk: int = r.atk if r.atk > 0 else (r.archetype.atk_base if r.archetype != null else 0)
	enemy_hp_max = int(round(float(base_hp) * s["hp_scale"]))
	enemy_hp = enemy_hp_max
	enemy_atk = int(round(float(base_atk) * s["atk_scale"]))
	enemy_element = r.element if r.element != "" else "none"   # 单向克制：敌人属性（仅供玩家符号克制判定）
	if _journal != null:
		_journal.note_battle_start(r)   # G5 工具：战斗开打（HP/攻已按 ante 缩放，记录真实值）
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
	debuffs.reset()                       # 2026-11-12 Step 1：玩家侧减益每房清零（不跨房残留）
	player_dot_bomb_stacks = 10           # 2026-08-09：爆炸阈值回落默认（gimmick on_room_start 覆盖）
	player_buffs = {}                     # Phase C：主动技能不跨房保留
	player_shield = 0
	player_shield += _reward_system.run_shield_next   # M4：上一房奖励的结界在本房开局生效
	player_shield += charm_room_shield    # M6：守望护符每房开局护盾（无名虚空由 gimmick on_room_start 扣回）
	player_shield += growth.room_shield()   # M2-01：技艺「守势」每房开局护盾
	mastery.reset_room()                  # M2-02：本房结算记录清零（熟练按房结算）
	_reward_system.run_shield_next = 0
	pending_jam_reel = -1
	pending_lock_reel = -1
	pending_chaos = false
	pending_auto_stop = false
	enemy_stunned = 0                     # 2026-11-12 Step 2：行动失效不跨房
	turn_damage_elems.clear()             # 2026-11-12 Step 2：元素触发记录每房清零
	turn_resolved = false                 # 2026-11-12 Step 3：debuff 计时相位
	last_enemy_intent = {}
	enemy_extra_attacks.clear()
	enemy_attack_poison = 0
	enemy_attack_pierce_pct = 0.0
	enemy_self_damage_after = 0
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
	if node_mode and board != null:
		hud._log("▶ 进入节点 %d/%d：%s（HP %d，攻击 %d）" % [
			board.visited_count(), board.route_length(), enemy_name, enemy_hp_max, enemy_atk])
	else:
		hud._log("▶ 进入房间 %d/%d：%s（HP %d，攻击 %d）" % [idx + 1, ROOMS.size(), enemy_name, enemy_hp_max, enemy_atk])
	invalidate_state()


# Ante 难度曲线纯函数：已迁至 RunSetup.ante_scale（P2 架构还债，2026-08-24）——单行转发。
func _ante_scale(r: RoomData, idx: int, ria_override: int = -1) -> Dictionary:
	return run_setup.ante_scale(r, idx, ria_override)


# ---------------------------------------------------------------------------
# M2 棋盘节点效果（由 BoardScreen 在移动动画结束后调用一次）
# ---------------------------------------------------------------------------

func _on_board_node_entered(node: Dictionary) -> void:
	if node.is_empty():
		return
	# 14×9 地图的节点类型是 battle / chest / event；旧名（normal / treasure / shrine）
	# 保留在同一分支里，历史存档与旧骨架不会走进默认分支被弹回地图。
	match String(node.get("type", "")):
		"battle", "normal", "elite", "boss":
			if String(node.get("type", "")) == "elite" and _career != null:
				_career.note_elite_route()   # G6-01：高危路线标记（击败 BOSS 时结算）
			_start_board_battle(node)
		"shop":
			_board_shop()
		"rest":
			_board_rest()
		"chest", "treasure":
			_board_treasure(node)
		"event", "shrine":
			_board_shrine(node)
		"armory":
			_board_armory(node)
		"weapon":
			_board_weapon(node)
		"charm":
			_board_charm(node)
		_:
			board.set_feedback(NODE_START_FEEDBACK)
			board.return_to_board()


func _start_board_battle(node: Dictionary) -> void:
	var r: RoomData = node.get("room")
	if r == null:
		board.set_feedback("战斗节点缺少 RoomData，已返回棋盘")
		board.return_to_board()
		return
	hud.hide_camp_supply()   # 防御：任何残留营地弹层都不得盖在战斗上
	hud.hide_board_screen(true)
	hud.set_interroom_enabled(false)
	start_room_data(r, int(node.get("battle_index", -1)), int(node.get("ria", -1)),
		bool(node.get("final", false)))


# 商店格：复用现有货架 / 刷新 / 价格；离开后回棋盘，节点已在进入时消耗。
func _board_shop() -> void:
	in_interroom = true
	hud.hide_board_screen(true)
	hud.set_interroom_enabled(false)
	_roll_shop()
	hud._show_shop_screen()
	hud._log("🛒 棋盘商店：离开后节点消耗")


func _board_rest() -> void:
	var heal := int(ceil(float(player_hp_max) * 0.25))
	var before := player_hp
	player_hp = mini(player_hp_max, player_hp + heal)
	var msg := ""
	if player_hp == before:
		msg = "休整：HP 已满，无需休整"
	else:
		msg = "休整：HP %d/%d → %d/%d（+%d）" % [before, player_hp_max, player_hp, player_hp_max, player_hp - before]
	hud._log(msg)
	invalidate_state()
	hud._refresh_meta()
	# G2-01：休整后开营地补给（最多买 1 件，离开不扣费）。
	_camp_offers = _roll_camp_offers()
	if _camp_offers.is_empty():
		board.set_feedback(msg)
		board.return_to_board()
		return
	hud.request_camp_supply(_camp_offers, _camp_buy, _camp_leave)


# 营地货架：武器 / 护符 / 消耗品各 1（护符排除信物与本局已带）。
func _roll_camp_offers() -> Array:
	var out: Array = []
	var weapons: Array = []
	for p in WEAPON_POOL:
		weapons.append(String(p))
	if not weapons.is_empty():
		out.append(_camp_offer(String(_reward_system.acq_weighted_pick(weapons)), "weapon"))
	var charms: Array = []
	for p in ITEM_POOL:
		var d = load(p)
		if d is ItemData and String(d.category) == "passive" and not selected_charms.has(String(p)) \
			and not _meta_store._is_boss_relic(d, String(p)):
			charms.append(String(p))
	if not charms.is_empty():
		out.append(_camp_offer(String(_reward_system.acq_weighted_pick(charms)), "passive"))
	var items: Array = []
	for p in ITEM_POOL:
		var d = load(p)
		if d is ItemData and String(d.category) == "active":
			items.append(String(p))
	if not items.is_empty():
		out.append(_camp_offer(String(_reward_system.acq_weighted_pick(items)), "active"))
	return out


func _camp_offer(path: String, kind: String) -> Dictionary:
	return {"path": path, "kind": kind, "name": _shop_name(path, kind),
		"price": _shop_price(kind, -1, path), "sold": false}


func _camp_buy(offer: Dictionary) -> void:
	if offer.is_empty() or bool(offer.get("sold", false)):
		return
	var price := int(offer.get("price", 0))
	if gold < price:
		hud._log("金币不足（需 %d）" % price)
		return
	var p := String(offer.get("path", ""))
	var kind := String(offer.get("kind", ""))
	if kind == "weapon" and selected_loadout.size() >= _loadout_system.cat_cap("weapon") and not selected_loadout.has(p):
		hud.hide_camp_supply()
		# 替换弹层挂在战斗 HUD 下：棋盘视图正把 HUD 藏着，先切回 HUD 再弹，取消时回棋盘营地。
		hud.hide_board_screen(true)
		hud.request_weapon_replace("营地补给：替换武器", _weapon_info(p),
			func(old_path: String) -> void: _camp_buy_replace(offer, old_path), p,
			func() -> void: _camp_reopen())
		return
	_shop_system.on_shop_buy_pressed(offer, "camp")
	_after_shop_change()
	_camp_finish()


func _camp_buy_replace(offer: Dictionary, old_path: String) -> void:
	_shop_system.on_shop_buy_replace_pressed(offer, old_path, "camp")
	_after_shop_change()
	_camp_finish()


func _camp_reopen() -> void:
	# 替换取消：回棋盘视图再弹营地（营地面板与 board_screen 同级，不依赖 HUD 可见）。
	board.return_to_board()
	hud.request_camp_supply(_camp_offers, _camp_buy, _camp_leave)


func _camp_leave() -> void:
	_camp_finish("营地：未购买，继续前进")


func _camp_finish(msg: String = "营地：补给结束") -> void:
	hud.hide_camp_supply()
	board.set_feedback(msg)
	hud._log(msg)
	invalidate_state()
	hud._refresh_meta()
	board.return_to_board()


# 神龛（G4-04）：效果生成时冻结并公开；数值沿用既有奖励效果
# （恢复 35% 最大 HP / 最大 HP +12 并回 20% / 下一场 +15 护盾）。
func _board_shrine(node: Dictionary) -> void:
	var kind := String(node.get("shrine_kind", ""))
	var before_hp := player_hp
	var before_max := player_hp_max
	var msg := ""
	match kind:
		"heal":
			var heal := int(ceil(float(player_hp_max) * 0.35))
			player_hp = mini(player_hp_max, player_hp + heal)
			if player_hp == before_hp:
				msg = "神龛：HP 已满（%d/%d），无需恢复" % [before_hp, before_max]
			else:
				msg = "神龛：恢复 %d HP（%d/%d → %d/%d）" % [
					player_hp - before_hp, before_hp, before_max, player_hp, player_hp_max]
		"maxhp":
			player_hp_max += 12
			var heal2 := int(ceil(float(player_hp_max) * 0.2))
			player_hp = mini(player_hp_max, player_hp + heal2)
			msg = "神龛：最大 HP +12（%d → %d）并恢复 %d" % [
				before_max, player_hp_max, player_hp - before_hp]
		"ward":
			_reward_system.run_shield_next += 15
			msg = "神龛：下一场战斗开局 +15 护盾（累计 %d）" % _reward_system.run_shield_next
		_:
			if _journal != null:
				_journal.note_special("shrine", "金币 +15")
			_board_node_gold(15, "神龛：金币")
			return
	if _journal != null:
		_journal.note_special("shrine", msg.trim_prefix("神龛："))
	board.set_feedback(msg)
	hud._log(msg)
	invalidate_state()
	hud._refresh_meta()
	board.return_to_board()


# 武器藏库（G4-04）：两把可见武器二选一；满槽沿用替换流程，跳过则节点消耗。
func _board_armory(node: Dictionary) -> void:
	var paths: Array = node.get("armory_paths", [])
	if paths.is_empty():
		_board_node_gold(15, "武器藏库：已空，折算金币")
		return
	# 弹层挂在 duel 根节点，棋盘保持可见作为背景（不切到战斗 HUD）。
	hud.request_armory(paths,
		func(p: String) -> void: _board_armory_pick(p),
		func() -> void: _board_armory_skip())


func _board_armory_pick(p: String) -> void:
	if p == "" or selected_loadout.has(p):
		if _journal != null:
			_journal.note_special("armory", "已持有，折算金币")
		_board_node_gold(15, "武器藏库：已持有，折算金币")
		return
	if selected_loadout.size() >= _loadout_system.cat_cap("weapon"):
		# 替换弹层挂在 HUD 上：先切到战斗 HUD 视图，否则面板不可见。
		hud.hide_board_screen(true)
		hud.request_weapon_replace("武器藏库：替换武器", _weapon_info(p),
			func(old_path: String) -> void: _board_weapon_replace(p, old_path, "武器藏库"), p,
			func() -> void: _board_weapon_cancel(p, "武器藏库"))
		return
	selected_loadout.append(p)
	_reward_system.remember_weapon(p)
	if _journal != null:
		_journal.note_weapon_change("", _shop_name(p, "weapon"), "武器藏库")
		_journal.note_special("armory", "选择：" + _shop_name(p, "weapon"))
	_build_pool(selected_loadout)
	var msg := "武器藏库：获得 %s（已加入转轮带）" % _shop_name(p, "weapon")
	board.set_feedback(msg)
	hud._log(msg)
	invalidate_state()
	hud._refresh_meta()
	board.return_to_board()


func _board_armory_skip() -> void:
	if _journal != null:
		_journal.note_special("armory", "跳过")
	var msg := "武器藏库：放弃选择（节点已消耗）"
	board.set_feedback(msg)
	hud._log(msg)
	board.return_to_board()


# 宝箱（G4-04）：类别与具体物品在生成时冻结；武器/护符复用节点授予与替换流程。
func _board_treasure(node: Dictionary) -> void:
	var kind := String(node.get("treasure_kind", ""))
	var p := String(node.get("item_path", ""))
	if p == "" or kind == "gold":
		_board_node_gold(15, "宝箱：金币")
		return
	match kind:
		"weapon":
			_board_weapon(node, "宝箱")
		"charm":
			_board_charm(node, "宝箱")
		"active":
			_board_treasure_active(p)
		_:
			_board_node_gold(15, "宝箱：金币")


func _board_treasure_active(p: String) -> void:
	var cd = load(p)
	if cd == null:
		_board_node_gold(15, "宝箱：物品缺失，折算金币")
		return
	var nm := String(cd.item_name)
	var msg := ""
	if consumable_slots.size() >= CONSUMABLE_CAP:
		var refund := _sell_price("active", p)
		gold += refund
		msg = "宝箱：%s 但腰带已满 → 折算金币 +%d" % [nm, refund]
	else:
		_consumable_uid += 1
		consumable_slots.append({"path": p, "item_id": cd.item_id, "charges": cd.charges,
			"uid": "c%d" % _consumable_uid})
		msg = "宝箱：获得 %s（入腰带）" % nm
	if _journal != null:
		_journal.note_special("treasure", msg.trim_prefix("宝箱："))
	board.set_feedback(msg)
	hud._log(msg)
	invalidate_state()
	hud._refresh_meta()
	_refresh_consumable_panel()
	board.return_to_board()


func _board_weapon(node: Dictionary, label: String = "武器格") -> void:
	var p := String(node.get("item_path", ""))
	if p == "" or selected_loadout.has(p):
		_board_node_gold(15, "%s：无可用候选，折算金币" % label)
		return
	if selected_loadout.size() >= _loadout_system.cat_cap("weapon"):
		hud.hide_board_screen(true)
		hud.request_weapon_replace("棋盘武器：替换", _weapon_info(p),
			func(old_path: String) -> void: _board_weapon_replace(p, old_path, label), p,
			func() -> void: _board_weapon_cancel(p, label))
		return
	selected_loadout.append(p)
	_reward_system.remember_weapon(p)
	if _career != null:
		_career.note_board_weapon()   # G6-01：棋盘寻宝（主动获得武器格）
	if _journal != null:
		_journal.note_weapon_change("", _shop_name(p, "weapon"), label)
		if label == "宝箱":
			_journal.note_special("treasure", "武器：" + _shop_name(p, "weapon"))
	_build_pool(selected_loadout)
	var msg := "%s：获得 %s（已加入转轮带）" % [label, _shop_name(p, "weapon")]
	board.set_feedback(msg)
	hud._log(msg)
	invalidate_state()
	hud._refresh_meta()
	board.return_to_board()


func _board_weapon_replace(p: String, old_path: String, label: String = "武器格") -> void:
	if p == "" or not selected_loadout.has(old_path) or selected_loadout.has(p):
		_board_weapon_cancel(p, label)
		return
	var old_name := _shop_name(old_path, "weapon")
	selected_loadout.erase(old_path)
	selected_loadout.append(p)
	_reward_system.remember_weapon(p)
	if _career != null:
		_career.note_board_weapon()   # G6-01：替换获得同样算主动获得武器格
	if _telemetry != null:
		_telemetry.on_weapon_swap()
	if _journal != null:
		_journal.note_weapon_change(String(old_name), _shop_name(p, "weapon"), label)
		if label == "宝箱":
			_journal.note_special("treasure", "武器替换：" + _shop_name(p, "weapon"))
		elif label == "武器藏库":
			_journal.note_special("armory", "替换：" + _shop_name(p, "weapon"))
	_build_pool(selected_loadout)
	var msg := "%s：%s → %s" % [label, old_name, _shop_name(p, "weapon")]
	board.set_feedback(msg)
	hud._log(msg)
	invalidate_state()
	hud._refresh_meta()
	board.return_to_board()


func _board_weapon_cancel(p: String, label: String = "武器格") -> void:
	if _journal != null:
		if label == "宝箱":
			_journal.note_special("treasure", "跳过")
		elif label == "武器藏库":
			_journal.note_special("armory", "取消替换：" + _shop_name(p, "weapon"))
	var msg := "%s：跳过 %s（节点已消耗）" % [label, _shop_name(p, "weapon")]
	board.set_feedback(msg)
	hud._log(msg)
	board.return_to_board()


func _board_charm(node: Dictionary, label: String = "护符格") -> void:
	var p := String(node.get("item_path", ""))
	if p == "" or selected_charms.has(p):
		_board_node_gold(15, "%s：无可用候选，折算金币" % label)
		return
	var cap: int = int(_loadout_system.cat_cap("passive"))
	if selected_charms.size() >= _loadout_system.cat_max("passive"):
		# 未到硬天花板才开槽；已到天花板（或已越界）则折算金币，绝不突破 CHARM_CAP。
		if selected_charms.size() < cap and _loadout_system.can_grow_slot("passive"):
			_loadout_system.grow_slot("passive")
		else:
			var refund := _sell_price("passive", p)
			gold += refund
			var full_msg := "%s：%s 但护符槽已满 → 折算金币 +%d" % [
				label, _shop_name(p, "passive"), refund]
			if _journal != null and label == "宝箱":
				_journal.note_special("treasure", "护符槽满，折算金币 +%d" % refund)
			board.set_feedback(full_msg)
			hud._log(full_msg)
			invalidate_state()
			hud._refresh_meta()
			board.return_to_board()
			return
	selected_charms.append(p)
	_reward_system.remember_charm(p)   # G2-01：棋盘护符格也写入图鉴/来源
	_apply_charms()
	var msg := "%s：获得 %s（已生效）" % [label, _shop_name(p, "passive")]
	if _journal != null and label == "宝箱":
		_journal.note_special("treasure", "护符：" + _shop_name(p, "passive"))
	board.set_feedback(msg)
	hud._log(msg)
	invalidate_state()
	hud._refresh_meta()
	board.return_to_board()


func _board_node_gold(n: int, reason: String) -> void:
	gold += n
	var msg := "%s +%d" % [reason, n]
	board.set_feedback(msg)
	hud._log(msg)
	invalidate_state()
	hud._refresh_meta()
	board.return_to_board()


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


func _status_def(st: String) -> StatusDef:
	return status_system.status_def(st)


# ---------------------------------------------------------------------------
# 表现刷新
# ---------------------------------------------------------------------------
func _input(event) -> void:
	if in_loadout:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		if readability != null:
			readability.cycle_preset()   # P1：战斗内快速切换 control / readable 做 A/B
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		if reel_system.spinning:
			reel_system.stop_next_reel()
		else:
			_on_spin_pressed()


## P-审计 P1（2026-08-24）：不可击杀锁血统一收口。
## 任何扣血路径（直击/穿透/DoT/元素爆发）结算后调用；由当前 gimmick 声明下限
## （勇者的阴影 P3 = 1，和解为唯一出口），杜绝旁路击杀。无 gimmick 或未声明 = 不干预。
func apply_enemy_hp_floor() -> void:
	if current_gimmick != null and current_gimmick.has_method("hp_floor"):
		var floor_v: int = current_gimmick.hp_floor(self)
		if floor_v > 0:
			enemy_hp = maxi(floor_v, enemy_hp)
	# 2026-11-12 Step 1：阶段触发统一在「任何扣血路径收口之后」检查，避免 DoT/爆发漏检。
	if current_gimmick != null and current_gimmick.has_method("on_hp_changed"):
		current_gimmick.on_hp_changed(self)


# ---------------------------------------------------------------------------
# 2026-11-12 Step 1：玩家侧减益（debuff_system）对外入口
# 怪物/gimmick 只调 apply_debuff；结算层只读 debuffs 的 *_mult() 查询。
# ---------------------------------------------------------------------------
func apply_debuff(id: String, turns: int = -1, stacks: int = 1, extra: Dictionary = {}) -> bool:
	if debuffs == null:
		return false
	return debuffs.apply(self, id, turns, stacks, extra)


func debuff_summary() -> String:
	return debuffs.summary() if debuffs != null else ""


func notify_armor_break() -> void:
	# 腐蚀随破甲解除；再通知 gimmick 的「首次破甲」触发。
	if debuffs != null:
		debuffs.clear_on_armor_break(self)
	if current_gimmick != null and current_gimmick.has_method("on_armor_break"):
		current_gimmick.on_armor_break(self)
