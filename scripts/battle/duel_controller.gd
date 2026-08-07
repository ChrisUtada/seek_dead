class_name DuelController
extends Control
# ============================================================================
# 官方对决控制器（DuelController）：由原型 prototypes/reel_combat/reel_combat.gd 迁移而来。
# 符号数据层：scripts/battle/symbol_data.gd（SymbolData 资源）、WeaponData.symbols、
#   8 把武器 .tres、ItemData（合并原 ConsumableData/CharmData）+ 8 个 .tres。
# 铁砧元进度存档于 SaveSystem.lobby_data["anvil_meta"]（与项目统一 JSON 存档）。
# 全代码 UI（Control 树），可直接作为 duel.tscn 脚本运行（F6）或由 RoomManager 进入。
#
# 拆分（docs/duel_controller拆分方案B.md）：M0–M6 历史增量注释已清理；职责分区——
#   存档 MetaStore / 铁砧 AnvilSystem / 商店 ShopSystem / 奖励 RewardSystem / 整备 LoadoutSystem
#   均为 RefCounted 子系统（scripts/systems/），本文件只留编排 + 薄转发 + 战斗核心。
#   各子系统 _init(ctrl: DuelController) 注入本 controller，_ctrl 均已标类型（编译期检查）。
# ============================================================================

const TRASH_SYMBOL = preload("res://resources/symbols/trash.tres")
const GOLD_SYMBOL = preload("res://resources/symbols/gold.tres")
@export var GOLD_POOL_WEIGHT: float = 3.0      # 金币符号在转轮池中的权重（远低于伤害符号，防稀释 DPS）
@export var GOLD_PER_COIN: int = 1           # 每枚落在连线上的金币符号产出的金币数

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
#   · 进池类（武器 weapon · 技能 skill）→ **无天花板**（UNCAPPED）。
#     它们的符号会挤进同一条转轮带，带越多则：废铁占比升高、目标符号命中率被稀释、
#     克制浓度摊薄、按停到想要的符号更难 —— 稀释效应本身就是刹车，无需人为封顶。
#     再叠加金币线性递增价（见 _shop_price），越买越贵，双闸门足矣。
#   · 不进池类（消耗品 active · 护符 passive）→ **硬天花板**（2 / 3）。
#     它们不进转轮、零稀释代价、没有任何自然刹车（尤其护符是「唯一收集乘区」，
#     纯收益、越多越强），故必须硬限量，否则乘区无限叠加直接崩坏数值。
const LOADOUT_MIN := 1
# 初始配额（每局开局值；_full_reset 与 _shop_price 的加价起点均以此为准）
const SLOT_INIT := {"weapon": 2, "skill": 1, "active": 1, "passive": 1}
const UNCAPPED := -1        # 天花板哨兵值：该类无上限，仅由稀释效应 + 金币递增价约束
const CONSUMABLE_CAP := 4   # 消耗品腰带上限（不进池，硬限；每格独立持有、允许同类重复占格）
const CHARM_CAP      := 3   # 护符槽天花板（不进池、唯一收集乘区，严格硬限）
# 房间序列排序权重：normal/elite 在前、boss 殿后（同档按路径稳定排序）
const ROOM_KIND_RANK := {"normal": 0, "elite": 0, "boss": 2}
# 各类当前上限：每局从初始配额起步，商店「买即开槽」逐步逼近天花板（_full_reset 重置）
var loadout_max    := 2
var skill_max      := 1
var charm_max      := 1

const REELS = 3
const ROWS = 1

# 房间难度曲线（ante）：按「幕间台阶 × 幕内爬升」两段缩放，取代原单一 α 全局 idx 缩放。
# 等价关系：原 1.15^idx（每幕恰 4 房，idx=4*(act-1)+幕内位置）= (1.15^4)^(act-1)·1.15^(幕内位置)
#   = ACT_STEP^(act-1) · ROOM_STEP^(幕内位置)。解耦两个旋钮，且对幕内房数变化稳健（boss 永远幕内位置=3=天然峰值）。
# 当前常量刻意保留用户 F6 验证过的手感（漂移 <0.1%）：幕1/2/3 BOSS 缩放后 HP ≈ 266/771/2140。
@export var ANTE_ACT_STEP_HP: float = 1.75   # 幕间台阶：每进一幕敌方 HP ×1.75（原 1.15^4）
@export var ANTE_ACT_STEP_ATK: float = 1.46   # 幕间台阶：每进一幕敌方 ATK ×1.46（原 1.10^4）
@export var ANTE_ROOM_STEP_HP: float = 1.15   # 幕内爬升：同幕每过一房敌方 HP ×1.15
@export var ANTE_ROOM_STEP_ATK: float = 1.10  # 幕内爬升：同幕每过一房敌方 ATK ×1.10
const PLAYER_DMG_MULT := 1.5   # 玩家直击总伤害永久倍率（F6 验证手感合理，保留为正式平衡值）。
const STATUS_DMG_MULT := 3.0  # 给敌人的状态 DoT（灼烧/毒）永久倍率（原 base 仅 3~4/层/回合，幕三 BOSS 高血量下需此倍率才可见；F6 验证合理，保留）。
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
# jam=注废意图概率, lock=锁轮意图概率, chaos=乱权意图概率, heavy=重击意图概率, 其余=普攻。
# Phase D 资源化：改为扫描 resources/rooms/*.tres（RoomData），见 _ready 内填充。
var ALL_ROOMS: Array[RoomData] = []          # 全量房间池（扫描收集；_build_run 从中按幕抽 12 房）
var ROOMS: Array[RoomData] = []             # 当前一局的 12 房序列（每局 _full_reset 时由 _build_run 重建）

# grid[reel][row] = SymbolData 引用
var grid = []
# grid_elem[reel][row] = 该格符号的「有效元素」（武器元素继承后的实际元素，用于逐符号克制结算）
var grid_elem = []

# 合并后的加权符号池：元素为 [SymbolData, weight, element]（element = 有效元素）
var pool: Array[Array] = []
var loadout_names: Array[String] = []
var _weapon_power_map: Dictionary = {}   # 符号 resource_path -> 该物品有效攻击力(base_power + 元进度武器加成)，由 _build_pool 构建。P3：结算时 _contribute 读此值把「物品强度轴」灌进符号伤害（docs/物品中心重构方案.md §8）
var _item_crit_map: Dictionary = {}   # 符号 resource_path -> 该物品三连暴击倍率(crit_mult)，由 _build_pool 构建（方案 A）。普通/special 三连均按此倍率结算，共享符号取最高 crit_mult。
var pool_items: Array[Dictionary] = []              # 装备自洽：每件装备一段 [ {name, hit, syms:[[SymbolData, weight, element]]} ]，_build_strips 据此生成各自的转轮子带

var _busy: bool = false                 # 旋转序列进行中，防重入
var _eval_adv := false                  # _evaluate 阶段2：本回合是否触发过「克制」
var _eval_dis := false                  # _evaluate 阶段2：本回合是否触发过「抵抗」
var _last_special_triple := false        # 上一次 _evaluate 是否触发 special 三连（供连锁重触发循环读取）

# —— 实体转轮带（方案 A）：权重 = 带子上该符号的格子数，落点由停止时机决定 ——
var reel_strips: Array = []            # [reel] -> Array[ [SymbolData, element] ]
var reel_cursor: Array[int] = []            # [reel] -> 当前带子索引（旋转时递增，取模长度）
var reel_stopped: Array[bool] = []           # [reel] -> 该列是否已停
var _locked_prev_sym: Array = []       # [reel] -> 锁轮保留的上一轮符号
var _locked_prev_elem: Array[String] = []      # [reel] -> 锁轮保留的上一轮有效元素
var _spinning := false                 # 旋转进行中（供输入分支判断）
var _spin_timer: Timer                 # 旋转节拍器（每跳推进一格 + 加速）
var _spin_ticks := 0                   # 已跳次数（用于加速上限）
const _SPIN_BASE_WAIT := 0.15          # 起始每跳间隔（秒）——调慢以便看清落点、凑三连 special
const _SPIN_MIN_WAIT := 0.06           # 最快每跳间隔（封顶也调慢，整体更易控）
const _STRIP_MIN_CELLS := 30           # 转轮带最小格数（整份平铺补足，不改变符号占比）
# 频率层（装备自洽 / 直觉模型，见下方 _ITEM_STRIP_TARGET）：频率由每件装备自身 weight 决定，
# 稀有度只定强度（见 LoadoutItem），不影响出现次数——避免「神装打不出去」。原 f(kind) 中央预算已退役。
const _ITEM_STRIP_TARGET := 16   # 每件装备转轮子带长（频率由该装备自身 weight 定，各装备等权、互不挤压）
const _GOLD_CELLS := 2           # 金币符号常驻格数（经济引擎，与装备频率解耦）

# miss（废铁）占比来自武器命中率，人为留底以防转轮变无脑（§12：命中率不能趋近 100%）。
@export var MISS_FLOOR: float = 0.08          # 废铁占比下限（转轮永远有 miss）
@export var MISS_CEIL: float = 0.30          # 废铁占比上限（防低命中武器把转轮打成纯废铁）

# P3：物品强度轴基准（docs/物品中心重构方案.md §8）。伤害 = (物品 base_power × 符号 base 偏移) × 连线 × 克制。
# BASE_POWER_REF 是「base_power → 伤害」的归一化支点：base_power == REF 的武器，其符号伤害等于 sym.base（即旧模型数值）；
# base_power 高于 REF 的武器（高稀有度）符号伤害按比例放大（落实「稀有度→强度」），低于则缩小。
# 此为调参旋钮：P11 内容广度阶段会把 sym.base 重标为相对 base_power 的真正偏移比，届时可去掉 REF 归一化。
@export var BASE_POWER_REF: float = 32.0        # 武器 base_power 支点（≈ 当前 8 武器均值，使平均武器伤害与旧模型持平）
@export var CHAIN_MAX: int = 4                      # 连锁重触发上限：special 三连最多再免费重转 3 次（共 4 发）
@export var CHAIN_STEP: float = 1.5                   # 连锁倍率：每多一层 ×1.5（叠在 special×CRIT 之上，封顶 ≈ ×3.4）
@export var CHARM_MULT_CAP: float = 6.0              # 总护符乘区硬上限（防失控膨胀）
@export var META_ANVIL_BONUS: int = 2              # 元进度三选一选「铁砧点数」时获得的点数
@export var ANVIL_ROLL_COST: int = 10
@export var ANVIL_BLANK_CHANCE: float = 0.10
@export var ANVIL_PITY_MAX: int = 10
@export var ANVIL_PER_RUN_CAP: int = 40
@export var ANVIL_DUPE_REFUND: Dictionary = {"common": 3, "uncommon": 5, "rare": 7, "epic": 10}
@export var ANVIL_RARITY_WEIGHT: Dictionary = {"common": 100, "uncommon": 40, "rare": 12, "epic": 3}
@export var ANVIL_MILESTONE_PCT: Array = [0.25, 0.5, 0.75, 1.0]
@export var ANVIL_MILESTONE_BONUS: Array = [50, 100, 150, 200]
@export var META_CHOICE_COUNT: int = 3             # 每局结束元进度候选张数（三选一，候选池随机抽）

# S12 局内金币升级（深化已有乘区，不新增第4乘区；每局清零，管局内临时）
# 设计：爆炸感来自「在现有 3 乘区(连线/护符·增益/克制)内做深」，而非开第 4 条独立乘区。
#   · 锋锐研磨(power)：+基础伤害（喂入全部乘区，线性保底）
#   · 连线精通(line)：匹配连线倍率 +N（深化 lane1，仅 ≥2 的同符号生效）
#   · 护符共鸣(joker)：本局伤害乘区 ×(1+N·step)，并入 buff_mult（深化 lane2·护符/增益同轨）
#   · 壁垒(shield)：每房开局护盾 +N（韧性保底，少量）
@export var POWER_STEP: int = 3           # 锋锐研磨：每级 +3 本局基础伤害
@export var LINE_STEP: int = 1           # 连线精通：每级 +1 连线倍率
@export var JOKER_STEP: float = 0.25        # 护符共鸣：每级 +0.25 本局伤害乘区（封顶见 JOKER_CAP_FACTOR）
@export var JOKER_CAP_FACTOR: float = 3.0   # 共鸣乘区硬上限（1 + maxlv*step ≤ 此值）
@export var SHIELD_STEP: int = 5          # 壁垒：每级 +5 每房开局护盾
# 金币升级定义表（icon/name/base/step/max）已抽至 GoldUpgradeDef 资源：
# resources/config/gold_upgrades/*.tres（ShopSystem 扫描收集，见 _shop_system）
# 注：不设自动停止上限——转轮何时停完全由玩家决定，不操作就一直转。
signal spin_finished                   # 全部转轮停下后发出，_on_spin_pressed 等待它

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

const STATUS_NAMES := {"burn": "燃", "frost": "霜", "poison": "毒"}

# Phase C 主动增益运行时：SymbolData -> 剩余回合数（本房内有效，进房清空）
var player_buffs: Dictionary = {}

# 消耗品运行时（战斗中主动使用）
var consumable_slots: Array[Dictionary] = []          # 消耗品腰带实例：[{path, item_id, charges, uid}]，上限 CONSUMABLE_CAP，允许同类重复占格
var _consumable_uid := 0                   # 腰带格唯一 id 计数器（卖出/使用精准定位，避免同类重复撞 key）
# 4 格子（2x2）由 HUD 自管（hud.consumable_cells），controller 不再持有引用
var assault_next_spin: int = 1            # 强袭药剂：下次转轮伤害倍率（1=正常）

# 玩家状态
var player_hp = 100
var player_hp_max = 100
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
var enemy_jam = 0.2
var enemy_lock = 0.1
var enemy_chaos = 0.1
var enemy_heavy = 0.2
var enemy_status: Dictionary = {}      # status_type(str) -> 叠加层数(int)
var enemy_intent: Dictionary = {}      # 当前敌人意图（SPIN 后执行），空字典表示已执行/未定
var enemy_element: String = "none"     # 敌人属性元素（用于单向克制：玩家符号元素 → 敌人元素）
var pending_jam_reel = -1              # 敌人注废 → 下一轮强制废铁列索引（-1 无）
var pending_lock_reel = -1             # 敌人锁轮 → 下一轮该列固定为当前符号（-1 无）
var pending_chaos = false              # 敌人乱权 → 下一轮权重削弱优势符号
# 净化完全走消耗品（净化药剂·charges 用尽即移出腰带），不再有"净化上限/净化次数"局内缓存

# M6 护符被动（整局生效，_apply_charms 在 _confirm_loadout 结算）
var charm_power_bonus: int = 0         # 锋锐护符：本局所有伤害符号 +N
var charm_room_shield: int = 0         # 守望护符：每房开局护盾 +N
var charm_shield_trickle: int = 0      # 守备护符：每回合护盾涓流（整局生效，见 §8）
var charm_heal_trickle: int = 0       # 回春护符：每回合回复（与瞬回药剂互补）
var charm_interf_resist: int = 0       # 抗扰护符：本局敌人干扰概率降低（等效抗扰等级）
# 净化完全走消耗品，「丰沛护符·净化上限」机制已废除（charm_purify_bonus 字段随之删除，purify_charm.tres 已删除）

var charm_damage_mult: float = 1.0      # Phase G v2.0：护符全局乘区（joker），默认 ×1.0

# 流程状态（enum 化：原字符串字面量易拼错且无编译期检查）
enum FlowState { PLAYING, WON, LOST }
var game_state: FlowState = FlowState.PLAYING
var turn_count = 1

# M4 本局（Run）加成层（run_symbol_bonus / run_power_bonus / run_shield_next）已抽至
# RewardSystem（步骤4，见 _reward_system）；reward_choices / reward_is_boss 仍由本 controller 持有（HUD 直读写）
var reward_choices: Array = []         # 当前展示的 3 个奖励
var reward_is_boss: bool = false       # 当前奖励是否来自 Boss 房（选完开新局）
# S7/S12 商店状态（shop_offers / paid_price / gold_upgrades）已抽至 ShopSystem（步骤3，见 _shop_system）

# M5 元进度（铁砧锻造 + 存档持久化，跨局保留）
# 已退役键（元进度三选一退化为仅 anvil）：weapon_upgrades / weapon_base_bonus / weapon_hit_bonus / charm_upgrades / interference_resist / first_clears
var meta: Dictionary = {"anvil_points": 0, "owned_weapons": [], "owned_charms": [], "owned_consumables": [], "anvil_pity": 0, "collection_milestones": []}
var _anvil_system                     # 铁砧锻造子系统 AnvilSystem（步骤2抽出；_ready 实例化并注入 self）
const ANVIL_SAVE_KEY := "anvil_meta"   # 铁砧元进度存于 SaveSystem.lobby_data
var _meta_store                        # 存档子系统 MetaStore（步骤1抽出；_ready 实例化并注入 self + meta）
var _shop_system                       # 商店子系统 ShopSystem（步骤3抽出；_ready 实例化并注入 self）
var _reward_system                     # 奖励子系统 RewardSystem（步骤4抽出；_ready 实例化并注入 self）
var _loadout_system                    # 整备子系统 LoadoutSystem（步骤5抽出；_ready 实例化并注入 self）

# 仅 1 行 3 格。特殊符号需 3 同才触发；普通符号单颗即结算，出现 n 次 ×n。
var PAYLINES = [
	[[0,0],[1,0],[2,0]],
]

# —— P1：只读状态快照（HUD 渲染只从此读，不再直读下方私有字段）——
var state: BattleState:
	get:
		return _build_state()

func _build_state() -> BattleState:
	var s := BattleState.new()
	s.grid = grid
	s.grid_elem = grid_elem
	s.reward_choices = reward_choices
	s.room_index = room_index
	s.REELS = REELS
	s.meta = meta
	s.gold = gold
	s.enemy_intent = enemy_intent
	s.enemy_element = enemy_element
	s.selected_loadout = selected_loadout
	s.run_symbol_bonus = _reward_system.run_symbol_bonus
	s.ROWS = ROWS
	s.ROOMS = ROOMS
	s.LOADOUT_MIN = LOADOUT_MIN
	s.WEAPON_POOL = WEAPON_POOL
	s.UNCAPPED = UNCAPPED
	s.selected_skills = selected_skills
	s.selected_charms = selected_charms
	s.run_shield_next = _reward_system.run_shield_next
	s.run_power_bonus = _reward_system.run_power_bonus
	s.pool = pool
	s.loadout_names = loadout_names
	s.in_loadout = in_loadout
	s.game_state = game_state
	s.enemy_status = enemy_status
	s.enemy_armor_max = enemy_armor_max
	s.consumable_slots = consumable_slots
	s.CONSUMABLE_CAP = CONSUMABLE_CAP
	s.charm_room_shield = charm_room_shield
	s.charm_power_bonus = charm_power_bonus
	s.charm_interf_resist = charm_interf_resist
	s.charm_damage_mult = charm_damage_mult
	s.turn_count = turn_count
	s.SKILL_POOL = SKILL_POOL
	s.skill_max = skill_max
	s.shop_offers = _shop_system.shop_offers
	s.selected_consumables = selected_consumables
	s.reward_is_boss = reward_is_boss
	s.player_shield = player_shield
	s.player_hp_max = player_hp_max
	s.player_hp = player_hp
	s.loadout_max = loadout_max
	s.ITEM_POOL = ITEM_POOL
	s.enemy_name = enemy_name
	s.enemy_hp_max = enemy_hp_max
	s.enemy_hp = enemy_hp
	s.enemy_armor = enemy_armor
	s.charm_max = charm_max
	return s



const BATTLE_HUD = preload("res://scenes/ui/battle_hud.tscn")
var hud: BattleHud

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Phase D：文件夹自动扫描内容池（替代手写路径数组）。必须在构建整备界面之前完成。
	# 扫描返回未泛型 Array，经 assign() 显式转为泛型（元素逐一校验）。
	WEAPON_POOL.assign(ResourceScan.scan_paths("res://resources/weapon_templates/"))
	ITEM_POOL.assign(ResourceScan.scan_paths("res://resources/charms/") + ResourceScan.scan_paths("res://resources/consumables/"))
	SKILL_POOL.assign(ResourceScan.scan_paths("res://resources/skills/"))
	ALL_ROOMS.assign(_sort_rooms(ResourceScan.scan_resources("res://resources/rooms/", "RoomData")))
	REWARD_POOL.assign(ResourceScan.scan_resources("res://resources/rewards/", "RewardData"))
	ELITE_REWARD_POOL.assign(ResourceScan.scan_resources("res://resources/rewards/elite/", "RewardData"))
	hud = BATTLE_HUD.instantiate()
	add_child(hud)
	hud.controller = self
	_meta_store = preload("res://scripts/systems/meta_store.gd").new(self, meta)
	_anvil_system = preload("res://scripts/systems/anvil_system.gd").new(self)
	_shop_system = preload("res://scripts/systems/shop_system.gd").new(self)
	_reward_system = preload("res://scripts/systems/reward_system.gd").new(self)
	_loadout_system = preload("res://scripts/systems/loadout_system.gd").new(self)
	_load_meta()
	_sanitize_owned()	# 自愈：清洗历史上误写入 owned_* 的非本类路径（如技能）
	_seed_default_owned()
	hud.build_all()   # P2：HUD 自构建全部界面（build_all 内部调各 _build_* + _show_loadout_screen），controller 不再戳私有构建方法
	# P2：HUD 意图信号 → controller 处理器（HUD 不再调用 controller 私有方法）
	hud.spin_requested.connect(_on_spin_button_pressed)
	hud.reel_clicked.connect(_on_reel_clicked)
	hud.buy_requested.connect(_on_shop_buy_pressed)
	hud.sell_requested.connect(_on_shop_sell_pressed)
	hud.reward_chosen.connect(_on_reward_chosen)
	hud.boss_reward_chosen.connect(_on_boss_reward_chosen)
	hud.reward_skip_requested.connect(_on_reward_skip_pressed)
	hud.shop_requested.connect(_on_shop_requested)
	hud.next_room_requested.connect(_on_next_room_pressed)
	hud.card_toggled.connect(_on_card_toggled)
	hud.meta_choice_chosen.connect(_on_meta_choice_chosen)
	hud.gold_upgrade_requested.connect(_on_gold_upgrade_pressed)
	hud.overlay_button_pressed.connect(_on_overlay_button_pressed)
	hud.consumable_used.connect(_on_consumable_pressed)
	hud.shop_leave_requested.connect(_on_shop_leave_pressed)
	hud.anvil_back_requested.connect(_on_anvil_back_pressed)
	# 方案 A：旋转节拍器（转轮带滚动 + 加速 + 停止时机判定）
	_spin_timer = Timer.new()
	_spin_timer.one_shot = false
	_spin_timer.connect("timeout", _on_spin_tick)
	add_child(_spin_timer)
func _build_pool(loadout: Array) -> void:
	pool = []
	pool_items = []
	loadout_names = []
	_weapon_power_map = {}
	_item_crit_map = {}
	# 强度轴映射（P3，未变）：符号 resource_path -> 该物品有效攻击力(base_power)；
	# 共享符号若被多装备持有，取最高者（反映「最强来源」）。结算时 _contribute 读此值把强度轴灌进符号伤害。
	for path in loadout:
		var wd: WeaponData = load(path)
		if wd == null or wd.symbols == null:
			continue
		var eff: float = wd.base_power
		for sw in wd.symbols:
			if sw == null or sw.symbol == null:
				continue
			var sp = sw.symbol.resource_path
			_weapon_power_map[sp] = max(_weapon_power_map.get(sp, 0.0), eff)
			_item_crit_map[sp] = max(_item_crit_map.get(sp, 1.0), wd.crit_mult)
	for path in selected_skills:
		var sd: SkillData = load(path)
		if sd == null or sd.symbol == null:
			continue
		var eff: float = sd.base_power
		var sp = sd.symbol.resource_path
		_weapon_power_map[sp] = max(_weapon_power_map.get(sp, 0.0), eff)
		_item_crit_map[sp] = max(_item_crit_map.get(sp, 1.0), sd.crit_mult)
	# —— 装备自洽（docs/物品中心重构方案.md §4 重构）：频率不再由中央 f(kind) 预算决定，
	# 而是「每件装备用自身 weight 决定自己符号多常出现、用自身命中率决定自己转轮的废铁占比」。
	# 每件装备生成一段等长的「自洽子带」，拼成共享转轮带；共享符号不再跨装备累加权重（垄断根因消除），
	# 稀有度仍只定强度（base_power / hit_rate），不影响出现次数（「神装打不出去」退化被避开）。
	for path in loadout:
		var wd: WeaponData = load(path)
		if wd == null:
			continue
		loadout_names.append(wd.weapon_name)
		if wd.symbols == null or wd.symbols.is_empty():
			continue
		var syms := []
		for sw in wd.symbols:
			if sw == null or sw.symbol == null:
				continue
			syms.append([sw.symbol, float(sw.weight), _eff_element(sw.symbol, wd)])
		var hit: float = clamp(wd.hit_rate, 0.0, 1.0)
		pool_items.append({"name": wd.weapon_name, "hit": hit, "syms": syms})
	# 主动技能同样作为「装备」生成自己的符号段（与武器等权、频率由自身 weight 定）
	for path in selected_skills:
		var sd: SkillData = load(path)
		if sd == null or sd.symbol == null:
			continue
		var eff_elem: String = sd.symbol.element if sd.symbol.element != "none" else "none"
		var hit: float = clamp(sd.hit_rate, 0.0, 1.0)
		pool_items.append({"name": ("技能" + sd.icon), "hit": hit, "syms": [[sd.symbol, float(sd.weight), eff_elem]]})
	# 扁平池（供图例 / 状态查询 / 奖励随机 等 legacy 消费者；weight 仅作展示/兼容）
	for it in pool_items:
		for s in it["syms"]:
			pool.append([s[0], s[1], s[2]])
	pool.append([GOLD_SYMBOL, GOLD_POOL_WEIGHT, "none"])
	# 敌人元素/弱/抗（取代原底部 LegendBar，写入右侧 EnemyPanel 三 Label）
	hud._update_enemy_element()



# 计算某符号的「有效元素」（Phase G v2.0 武器元素化）：
# - special 符号：优先用武器 reel_element（特殊符号属性），否则用符号自身 element
# - 其余符号：自身 element 非 none 用之，否则继承武器 element（火武器 → 伤害符号带火）
func _eff_element(sym: SymbolData, wd: WeaponData) -> String:
	if sym.kind == "special":
		return wd.reel_element if wd.reel_element != "none" else sym.element
	return sym.element if sym.element != "none" else wd.element



# ---------------------------------------------------------------------------
# UI 构建（全代码）
# ---------------------------------------------------------------------------
# 整备勾选 / 槽位 / 拥有池已抽至 LoadoutSystem（步骤5，见 _loadout_system）：
# on_card_toggled / sel_arr / cat_max / cat_cap / can_grow_slot / cap_text /
# grow_slot / cat_name / owned_arr；下方保留薄转发（loadout_scene / battle_hud /
# shop_screen / 各子系统直调签名不变），_confirm_loadout / _apply_charms 留本编排层。
func _on_card_toggled(card: Dictionary) -> void:
	_loadout_system.on_card_toggled(card)


func _sel_arr(cat: String) -> Array:
	return _loadout_system.sel_arr(cat)


func _cat_max(cat: String) -> int:
	return _loadout_system.cat_max(cat)


func _cat_cap(cat: String) -> int:
	return _loadout_system.cat_cap(cat)


func _can_grow_slot(cat: String) -> bool:
	return _loadout_system.can_grow_slot(cat)


func _cap_text(cat: String) -> String:
	return _loadout_system.cap_text(cat)


func _grow_slot(cat: String) -> void:
	_loadout_system.grow_slot(cat)


func _cat_name(cat: String) -> String:
	return _loadout_system.cat_name(cat)


func _confirm_loadout() -> void:
	if selected_loadout.size() < LOADOUT_MIN:
		return
	# 消耗品：整备确认时把去重勾选清单实例化为腰带格（每格独立 charges；允许后续商店重复购买同类）
	consumable_slots = []
	for path in selected_consumables:
		var cd: Resource = load(path)
		if cd != null:
			_consumable_uid += 1
			consumable_slots.append({"path": path, "item_id": cd.item_id, "charges": cd.charges, "uid": "c%d" % _consumable_uid})
	hud._hide_loadout_screen()
	_full_reset()


# 结算护符被动（整局生效）
func _apply_charms() -> void:
	charm_power_bonus = 0
	charm_room_shield = 0
	charm_interf_resist = 0
	charm_damage_mult = 1.0
	charm_shield_trickle = 0
	charm_heal_trickle = 0
	for path in selected_charms:
		var cd: Resource = load(path)
		if cd == null:
			continue
		match cd.effect:
			"damage_bonus":         charm_power_bonus += cd.value
			"room_shield":          charm_room_shield += cd.value
			"interference_resist":  charm_interf_resist += cd.value
			# "purify_bonus" 丰沛护符已删除（净化完全走消耗品）
			"shield":               charm_shield_trickle += cd.value   # 守备护符：每回合护盾涓流
			"heal":                charm_heal_trickle += cd.value    # 回春护符：每回合回复
			"damage_mult":
				charm_damage_mult *= cd.mult_value   # 护符乘数增值（封顶在循环后）
		# 混合护符的负面效果（未来卡用）：与正面同枚举、加成型数值取反、乘区型乘 downside_mult
		if cd.downside_effect != "":
			match cd.downside_effect:
				"damage_bonus":         charm_power_bonus -= cd.downside_value
				"room_shield":          charm_room_shield -= cd.downside_value
				"interference_resist":  charm_interf_resist -= cd.downside_value
				"shield":               charm_shield_trickle -= cd.downside_value
				"heal":                charm_heal_trickle -= cd.downside_value
				"damage_mult":          charm_damage_mult *= cd.downside_mult
	# 总护符乘区硬上限（防失控膨胀）
	charm_damage_mult = min(charm_damage_mult, CHARM_MULT_CAP)
	var charm_log = "护符已装配：伤害+%d / 开局护盾+%d / 每回合护盾+%d / 每回合回血+%d / 抗扰+%d" % [charm_power_bonus, charm_room_shield, charm_shield_trickle, charm_heal_trickle, charm_interf_resist]
	if charm_damage_mult != 1.0:
		charm_log += " / 伤害×%s" % ElementCounter.fmt_mult(charm_damage_mult)
	hud._log(charm_log)


# ---------------------------------------------------------------------------
# M4 房奖励三选一界面（Roguelike 构筑）
# ---------------------------------------------------------------------------
func _on_reward_chosen(id: String) -> void:
	_finish_room(func(): _apply_reward(id), reward_is_boss)


func _on_reward_skip_pressed() -> void:
	_finish_room(Callable(), reward_is_boss)    # 跳过奖励：不应用任何效果


func _on_boss_reward_chosen(cand: Dictionary) -> void:
	_finish_room(func(): _apply_boss_reward(cand), true)


# 房奖励三选一 / 跳过 / BOSS 战利品共用的房间推进编排：
# hide → 应用奖励（可选）→ 发放铁砧点数 + 金币 → 通关则元进度三选一，否则进房间歇态 → 刷元进度栏。
func _finish_room(apply_fn: Callable, is_boss: bool) -> void:
	hud.hide_reward_screen()
	if apply_fn.is_valid():
		apply_fn.call()
	_anvil_system.award_meta(is_boss)    # M5：房间通关发放铁砧点数
	_award_gold(is_boss)    # S6+S8：清房金币 + 利息
	if _is_run_final(room_index):
		_show_meta_choice()        # 通关整局（最终 BOSS）→元进度三选一（持久生效）
	else:
		_enter_interroom()        # opt-in 商店：进入房间歇态（🛒 可选，▶ 下一房继续）
	hud._refresh_meta()


# ---------------------------------------------------------------------------
# 每局结束元进度三选一（膨胀双轨：武器 base 线性 × 护符乘数增值，持久跨局）
# ---------------------------------------------------------------------------
# M4 房奖励 / BOSS 战利品 / 局末元进度逻辑已抽至 RewardSystem（步骤4，见 _reward_system）：
# roll_meta_choices / on_meta_choice_chosen / roll_rewards / roll_elite_rewards /
# roll_boss_rewards / apply_reward / apply_boss_reward；下方保留薄转发（meta_screen /
# reward_screen / battle_hud 直调签名不变），_on_reward_* / _show_meta_choice 留本编排层。
func _roll_meta_choices() -> Array:
	return _reward_system.roll_meta_choices()


func _show_meta_choice() -> void:
	hud._show_meta_choice()


func _on_meta_choice_chosen(opt: Dictionary) -> void:
	hud.hide_meta_screen()
	_reward_system.on_meta_choice_chosen(opt)   # 元进度应用 + 落盘（_save_meta 在子系统内）
	hud._refresh_meta()
	_full_reset()   # 元进度生效后开新一局（金币/槽位随局清零，但 meta 持久）


func _roll_rewards() -> Array:
	return _reward_system.roll_rewards()


# T6 精英房「战前补给」三选一（逻辑已抽至 RewardSystem）
func _roll_elite_rewards() -> Array:
	return _reward_system.roll_elite_rewards()


# BOSS 战利品三选一（逻辑已抽至 RewardSystem）
func _roll_boss_rewards(room) -> Array:
	return _reward_system.roll_boss_rewards(room)


# 打开奖励屏的语义入口：由 controller 填充 reward_choices / reward_is_boss，
# reward_screen 只调用本方法并从 state 快照读取（不再直写 controller 字段）。
func _open_reward_screen(is_boss: bool) -> void:
	reward_is_boss = is_boss
	if is_boss:
		reward_choices = _roll_boss_rewards(ROOMS[room_index])
	elif ROOMS[room_index].kind == "elite":
		reward_choices = _roll_elite_rewards()
	else:
		reward_choices = _roll_rewards()


func _apply_reward(id: String) -> void:
	_reward_system.apply_reward(id)


func _apply_boss_reward(cand: Dictionary) -> void:
	_reward_system.apply_boss_reward(cand)


# ---------------------------------------------------------------------------
# M5 元进度（铁砧锻造 + 存档持久化）
# ---------------------------------------------------------------------------
func _load_meta() -> void:
	_meta_store.load_meta()   # 步骤1：转发到 MetaStore


func _save_meta() -> void:
	_meta_store.save_meta()   # 步骤1：转发到 MetaStore

func _seed_default_owned() -> void:
	_meta_store.seed_default_owned()   # 步骤1：转发到 MetaStore

func _sanitize_owned() -> void:
	_meta_store.sanitize_owned()   # 步骤1：转发到 MetaStore

func _owned_arr(kind: String) -> Array:
	return _loadout_system.owned_arr(kind)   # 步骤5：转发到 LoadoutSystem



# M5 铁砧点数 drip 已抽至 AnvilSystem（步骤2，见 award_meta）
func _award_gold(is_boss: bool) -> void:
	_meta_store.award_gold(is_boss)   # 步骤1：转发到 MetaStore

# S6–S12 商店逻辑已抽至 ShopSystem（步骤3）：shop_price / shop_name / roll_shop /
# on_shop_buy_pressed / sell_price / on_shop_sell_pressed / gold_upgrade_* / on_gold_upgrade_pressed
func _shop_price(kind: String, owned: int = -1) -> int:
	return _shop_system.shop_price(kind, owned)


func _shop_name(path: String, kind: String) -> String:
	return _shop_system.shop_name(path, kind)


func _roll_shop() -> void:
	_shop_system.roll_shop()


# 商店状态变更后的统一 UI 刷新（买卖/金币升级共用，防新增路径漏刷）
func _after_shop_change() -> void:
	hud._refresh_shop()
	hud._refresh_meta()


func _on_shop_buy_pressed(offer: Dictionary) -> void:
	_shop_system.on_shop_buy_pressed(offer)
	_after_shop_change()


func _sell_price(kind: String, path: String) -> int:
	return _shop_system.sell_price(kind, path)


func _on_shop_sell_pressed(path: String, kind: String) -> void:
	_shop_system.on_shop_sell_pressed(path, kind)
	_after_shop_change()


func _gold_upgrade_defs() -> Array:
	return _shop_system.gold_upgrade_defs()


func _on_gold_upgrade_pressed(id: String) -> void:
	_shop_system.on_gold_upgrade_pressed(id)
	_after_shop_change()


func _on_shop_leave_pressed() -> void:
	hud.hide_shop_screen()
	hud.set_shop_button_text("🛒 商店")
	_enter_interroom()      # 离开商店回房间歇态，不自动进下一房（玩家可再开或点 ▶）


# ---------------------------------------------------------------------------
# opt-in 房间歇态（替代强制全屏商店）
# ---------------------------------------------------------------------------
func _enter_interroom() -> void:
	in_interroom = true
	hud._hide_overlay()    # 防御性：确保胜利弹层已关闭，避免顶栏被其遮挡/重触发
	hud.set_interroom_enabled(true)


func _on_shop_requested() -> void:
	if not in_interroom:
		return
	# 🛒 按钮在抽屉展开/收起间切换
	if hud.shop_screen_is_open():
		hud.hide_shop_screen()
		hud.set_shop_button_text("🛒 商店")
	else:
		hud._show_shop_screen()
		hud.set_shop_button_text("🛒 收起")


func _on_next_room_pressed() -> void:
	# 若抽屉仍展开，进下一房前先收起，避免遮挡新房间
	if hud.shop_screen_is_open():
		hud.hide_shop_screen()
		hud.set_shop_button_text("🛒 商店")
	in_interroom = false
	hud.set_interroom_enabled(false)
	_start_room(room_index + 1)



func _on_anvil_roll_pressed() -> void:
	# 铁砧纯 gacha：委托 AnvilSystem 完成扣点→摇→结算→写 last_anvil_drops→落盘（§6 纯 gacha 定案）
	var drops = _anvil_system.roll_anvil()
	if drops.is_empty():
		return   # 点数不足（已在子系统内日志）
	# 注意：不在此处刷新铁砧屏——由 anvil_screen 旋转动画收尾后自行 refresh
	hud._refresh_meta()
	hud._refresh_loadout_cards()
	hud._update_loadout_anvil()
# M6 铁砧 gacha 核心已抽至 AnvilSystem（步骤2）：roll_anvil / award_meta / _anvil_*
func _on_anvil_back_pressed() -> void:
	hud.hide_anvil_screen()
	hud._show_loadout_screen()   # 铁砧返回后重建整备 2D 场景（loadout 内会 hud.hide()）
	hud._update_loadout_anvil()


func _full_reset() -> void:
	_anvil_system.reset_run()   # 本局铁砧点数 drip 累计清零
	player_hp = player_hp_max
	in_interroom = false                     # opt-in 商店：新一局不可能处于房间歇态
	gold = 4                                 # S6：新一局金币清零（每局清零，见 §11）
	# 新一局四类槽位回到初始配额（商店「买即开槽」可再逐步扩至各自天花板）
	loadout_max = int(SLOT_INIT["weapon"])
	skill_max = int(SLOT_INIT["skill"])
	charm_max = int(SLOT_INIT["passive"])
	_shop_system.reset_run()   # 步骤3：新一局商店状态清零（购入价记录 + 金币升级等级）
	_reward_system.reset_run()   # 步骤4：新一局本局加成层清零（符号灌注 / 伤害加成 / 下一房护盾）
	ROOMS = _build_run()                 # S10 T3：每局从全量池按幕抽 12 房
	_build_pool(selected_loadout)
	_start_room(0)


# 房间是否为 BOSS 房：以 RoomData.kind == "boss" 判定（不再依赖「最后一间」的位置约定，
# 否则插入熔毁之间等中间房型会让 BOSS 判定错位）。
func _is_boss_room(idx: int) -> bool:
	return idx >= 0 and idx < ROOMS.size() and ROOMS[idx].kind == "boss"


# 是否为本局最后一间房（=通关整局）。S10 起一局有 3 个幕 BOSS，只有最后一个才结束 run：
# 幕一/幕二 BOSS 通关后照常进商店并推进下一房，否则幕二幕三永远进不去。
func _is_run_final(idx: int) -> bool:
	return idx >= ROOMS.size() - 1


# S10 T3：每局运行时从全量池构建 12 房（3 幕 × 2 normal + 1 elite + 1 boss）。
# 房间序列不再依赖文件名字母序或固定数组；每局随机、按幕分组（幕内顺序：普通→普通→精英→BOSS）。
# 未抽中的房间留作内容广度（不同 run 体验不同）。
func _build_run() -> Array[RoomData]:
	var by_act := {}   # act -> {kind: [RoomData,...]}
	for r in ALL_ROOMS:
		var a = int(r.act)
		if not by_act.has(a):
			by_act[a] = {"normal": [], "elite": [], "boss": []}
		by_act[a][r.kind].append(r)
	var run: Array[RoomData] = []
	for a in [1, 2, 3]:
		if not by_act.has(a):
			continue
		var grp = by_act[a]
		var normals = grp["normal"].duplicate()
		normals.shuffle()
		for i in range(min(2, normals.size())):
			run.append(normals[i])
		var elites = grp["elite"].duplicate()
		if not elites.is_empty():
			elites.shuffle()
			run.append(elites[0])
		var bosses = grp["boss"].duplicate()
		if not bosses.is_empty():
			run.append(bosses[0])
	return run


# 房间序列排序：normal/elite 在前、boss 殿后（同档按 resource_path 稳定排序）。
# 保持「扫描文件夹」资源化原则（不硬编码路径），仅对扫描结果做语义重排。
func _sort_rooms(rms: Array) -> Array:
	rms.sort_custom(func(a, b):
		var ra = ROOM_KIND_RANK.get(a.kind, 0)
		var rb = ROOM_KIND_RANK.get(b.kind, 0)
		if ra != rb:
			return ra < rb
		return a.resource_path < b.resource_path)
	return rms


func _start_room(idx: int) -> void:
	if idx >= ROOMS.size():                 # 兜底：越界视为通关整局，走元进度三选一而非崩溃
		_show_meta_choice()
		return
	_apply_charms()                         # S7：每次开房重算护符被动（含商店购入的护符）
	_build_pool(selected_loadout)           # S7：重建符号池（含商店购入的武器）
	room_index = idx
	var r: RoomData = ROOMS[idx]
	enemy_name = r.name
	# ante 难度曲线：RoomData.hp/atk 视为基础值，按「幕间台阶 × 幕内爬升」缩放。
	var s = _ante_scale(r, room_index)
	enemy_hp_max = int(round(float(r.hp) * s["hp_scale"]))
	enemy_hp = enemy_hp_max
	enemy_atk = int(round(float(r.atk) * s["atk_scale"]))
	enemy_jam = r.jam
	enemy_lock = r.lock
	enemy_chaos = r.chaos
	enemy_heavy = r.heavy
	enemy_element = r.element if r.element != "" else "none"   # 单向克制：敌人属性（仅供玩家符号克制判定）
	# 护甲（扁平池）：随 ante 缩放；BOSS 机制可在此基础上成长（如锈蚀傀儡熔铸护甲）
	enemy_armor_max = int(round(float(r.armor) * s["hp_scale"])) if r.armor > 0 else 0
	enemy_armor = enemy_armor_max
	# 抗干扰：抗扰护符 降低敌人干扰概率（每级 -12%，最低保留 25%）
	var total_resist = charm_interf_resist
	if total_resist > 0:
		var rf = max(0.25, 1.0 - total_resist * 0.12)
		enemy_jam *= rf
		enemy_lock *= rf
		enemy_chaos *= rf
	enemy_status = {}
	player_buffs = {}                     # Phase C：主动技能不跨房保留
	player_shield = 0
	player_shield += _reward_system.run_shield_next   # M4：上一房奖励的结界在本房开局生效
	player_shield += charm_room_shield    # M6：守望护符每房开局护盾
	player_shield += _shop_system.gold_upgrades["shield"] * SHIELD_STEP   # S12：壁垒——每房开局护盾（韧性保底）
	_reward_system.run_shield_next = 0
	pending_jam_reel = -1
	pending_lock_reel = -1
	pending_chaos = false
	# 净化完全走消耗品（净化药剂·charges 用尽即移出腰带），无需每房回满
	game_state = FlowState.PLAYING                # 必须在重建消耗品按钮前置为 playing，否则房间过渡瞬间按钮被误判为禁用
	_refresh_consumable_panel()
	turn_count = 1
	enemy_intent = {}
	hud._hide_overlay()
	_build_strips()
	_reset_grid()
	# S10 T2：BOSS 机制实例化（仅 BOSS 房；非 BOSS 房置 null，钩子调用处显式判空跳过）
	current_gimmick = null
	boss_atk_mult = 1.0
	boss_trash = 0
	if _is_boss_room(idx) and r.gimmick_script != null:
		current_gimmick = r.gimmick_script.new()
		current_gimmick.on_room_start(self)
	_begin_player_turn()
	_refresh_consumable_panel()           # 双重保险：同步按钮禁用状态与当前战斗状态
	hud._refresh_meta()
	hud._update_enemy_element()
	hud._log("▶ 进入房间 %d/%d：%s（HP %d，攻击 %d）" % [idx + 1, ROOMS.size(), enemy_name, enemy_hp_max, enemy_atk])


# ante 难度曲线纯函数：RoomData.hp/atk 视为基础值，按「幕间台阶 × 幕内爬升」缩放。
# act = RoomData.act（1/2/3）；幕内位置 = 本房之前与本房同幕房数 - 1（boss 恒为 3 = 幕内峰值）。
func _ante_scale(r: RoomData, idx: int) -> Dictionary:
	var a = r.act
	var ria = 0   # room-in-act：同幕内序号（0 起）
	for i in range(idx + 1):
		if ROOMS[i].act == a:
			ria += 1
	ria -= 1
	return {
		"hp_scale": pow(ANTE_ACT_STEP_HP, a - 1) * pow(ANTE_ROOM_STEP_HP, ria),
		"atk_scale": pow(ANTE_ACT_STEP_ATK, a - 1) * pow(ANTE_ROOM_STEP_ATK, ria),
	}


func _begin_player_turn() -> void:
	if game_state != FlowState.PLAYING:
		return
	var rnd = randf()
	if rnd < enemy_jam:
		enemy_intent = {"type": "jam", "value": 0}
	elif rnd < enemy_jam + enemy_lock:
		enemy_intent = {"type": "lock", "value": 0}
	elif rnd < enemy_jam + enemy_lock + enemy_chaos:
		enemy_intent = {"type": "chaos", "value": 0}
	elif rnd < enemy_jam + enemy_lock + enemy_chaos + enemy_heavy:
		enemy_intent = {"type": "heavy", "value": enemy_atk * 2}
	else:
		enemy_intent = {"type": "attack", "value": enemy_atk}
	# S10 T2：每玩家回合重置 BOSS 倍率，再由 gimmick 钩子按本回合状态设定
	boss_atk_mult = 1.0
	if current_gimmick != null:
		current_gimmick.on_turn_begin(self)


func _on_spin_pressed() -> void:
	if in_loadout or in_interroom or game_state != FlowState.PLAYING or _busy:
		return
	_busy = true
	turn_count += 1
	# 阶段 0：旋转（实体转轮带滚动，玩家按停止键锁定落点；不立即结算）
	_begin_spin()
	await spin_finished
	await get_tree().create_timer(0.25).timeout
	# 阶段 1+2：结算（先防御/增益/状态，后攻击；含飘字）
	await _chain_loop()
	if enemy_hp <= 0:
		hud._log("★ 击败 %s！" % enemy_name)
		game_state = FlowState.WON
		hud._show_reward_screen(_is_boss_room(room_index))
		hud._refresh_meta()
		_busy = false
		return

	# 阶段 3：敌人行动（先让玩家看清敌人刚掉的血）
	await get_tree().create_timer(0.35).timeout
	_enemy_turn()
	hud._refresh_meta()
	await get_tree().create_timer(0.55).timeout
	if enemy_hp <= 0:
		# 敌人可能在自身回合被状态 DoT 结算致死
		hud._log("★ 击败 %s！（状态结算）" % enemy_name)
		game_state = FlowState.WON
		hud._show_reward_screen(_is_boss_room(room_index))
		_busy = false
		return
	if player_hp <= 0:
		hud._log("✖ 你被 %s 击倒。" % enemy_name)
		game_state = FlowState.LOST
		hud._show_overlay("✖ 失败\n你倒在了 %s 面前" % enemy_name, "返回整备 ▶")
		hud._refresh_meta()
		_busy = false
		return

	await get_tree().create_timer(0.30).timeout
	# 阶段 4：预告下一回合意图
	_begin_player_turn()
	hud._refresh_meta()
	_busy = false


# 连锁重触发（① 数值爆炸）：special 三连后免费重转，倍率逐层 ×1.5，封顶 CHAIN_MAX 发。
# 重转全部用 fresh 随机——连锁是否续上完全看 RNG 是否再给 special 三连，是可见的尖峰而非黑箱。
func _chain_loop() -> void:
	var _chain := 0
	while true:
		await _evaluate(1.0 if _chain == 0 else CHAIN_STEP ** _chain)
		if not _last_special_triple or enemy_hp <= 0:
			break
		_chain += 1
		if _chain >= CHAIN_MAX:
			break
		hud._log("⚡ 连锁 ×%d！免费重转…" % (_chain + 1))
		hud._popup("⚡连锁 ×%d" % (_chain + 1), Palette.POP_DAMAGE, hud._enemy_sprite_anchor())
		_begin_spin()
		await spin_finished
		await get_tree().create_timer(0.25).timeout


# ---------------------------------------------------------------------------
# 方案 A：实体转轮带 + 停止时机（SPIN 与重转卷轴共用）
# 权重 = 带子上该符号的格子数；落点由玩家按停时机决定，而非后台加权随机。
# ---------------------------------------------------------------------------

# 开始一次旋转：构建转轮带、随机起点、启动节拍器。结果在 spin_finished 后结算。
func _begin_spin() -> void:
	reel_cursor = []
	reel_stopped = []
	_locked_prev_sym = []
	_locked_prev_elem = []
	for r in REELS:
		var strip_len = reel_strips[r].size() if reel_strips.size() > r and not reel_strips[r].is_empty() else 1
		reel_cursor.append(randi() % strip_len)
		reel_stopped.append(false)
		# 锁轮列：保留旋转前该列的符号与有效元素
		_locked_prev_sym.append(grid[r][0] if grid.size() > r and grid[r].size() > 0 else TRASH_SYMBOL)
		_locked_prev_elem.append(grid_elem[r][0] if grid_elem.size() > r and grid_elem[r].size() > 0 else "none")
		# 旋转期间允许点击该列以停止
		hud.set_reel_enabled(r, true)
	_spinning = true
	_spin_ticks = 0
	_spin_timer.wait_time = _SPIN_BASE_WAIT
	_spin_timer.start()
	hud._log("转轮旋转中——按【空格】逐列停止，或点击某一列单独停下（不停就一直转）")


# 装备自洽（docs/物品中心重构方案.md §4 重构）：由「每件装备生成自己的转轮子带」拼接成共享转轮带。
# 频率 = 该装备自身 weight（权重越大越常出现）；废铁占比 = 1 - 该装备自身命中率（夹在 MISS_FLOOR/CEIL）。
# 共享符号不再跨装备累加权重，垄断根因结构性消除；稀有度仍只定强度，不影响出现次数。
# 结算/连锁/special 三连等下游逻辑完全不变（仍按 REELS x ROWS 落子统计）。
func _build_strips() -> void:
	reel_strips = []
	if pool_items.is_empty():
		for r in REELS:
			reel_strips.append([[TRASH_SYMBOL, "none"]])
		return
	var base := []
	for it in pool_items:
		var syms: Array = it["syms"]
		if syms.is_empty():
			continue
		# F-0 符号权重修正（本局符号灌注 / 词缀）落在该装备自己的段内
		var mod := []
		for s in syms:
			var w = max(0.0, s[1] + _agg_symbol_weight_mod(s[0]))
			mod.append([s[0], w, s[2]])
		var wsum: float = 0.0
		for s in mod:
			wsum += s[1]
		if wsum <= 0.0:
			continue
		var target: int = _ITEM_STRIP_TARGET
		# 按自身 weight 分配符号格（每符号至少 1 格，权重越大越常出现）
		var cells := []
		for s in mod:
			var cnt: int = maxi(1, roundi(float(target) * s[1] / wsum))
			for _c in cnt:
				cells.append([s[0], s[2]])
		# 废铁占比 = 1 - 该装备自身命中率（转轮永远有 miss，MISS_FLOOR/CEIL 兜底）
		var miss_frac: float = clamp(1.0 - float(it["hit"]), MISS_FLOOR, MISS_CEIL)
		var miss_cnt: int = roundi(float(target) * miss_frac)
		for _c in miss_cnt:
			cells.append([TRASH_SYMBOL, "none"])
		base.append_array(cells)
	# 金币常驻（经济引擎，与装备频率解耦）
	for _c in _GOLD_CELLS:
		base.append([GOLD_SYMBOL, "none"])
	# 敌人乱权：向整带注入额外废铁（等比重削弱所有装备，忠实还原「削弱优势」意图）
	if pending_chaos:
		var extra: int = roundi(float(base.size()) * 0.20)
		for _c in extra:
			base.append([TRASH_SYMBOL, "none"])
	# S10 T2：深渊侵蚀注入额外废铁
	for _i in boss_trash:
		base.append([TRASH_SYMBOL, "none"])
	# 最小带长保护：整份平铺到 _STRIP_MIN_CELLS 以上——只拉长周期，各符号占比完全不变
	if base.size() < _STRIP_MIN_CELLS:
		var unit = base.duplicate(true)
		while base.size() < _STRIP_MIN_CELLS:
			base.append_array(unit.duplicate(true))
	# 3 根转轮 = base 的洗牌副本（落点由玩家停止时机决定）
	for r in REELS:
		var copy = base.duplicate(true)
		for i in range(copy.size() - 1, 0, -1):
			var j = randi() % (i + 1)
			var tmp = copy[i]
			copy[i] = copy[j]
			copy[j] = tmp
		reel_strips.append(copy)


# 节拍器回调：推进仍在旋转的转轮并逐步加速。没有自动停止——只有玩家按停才会锁定。
func _on_spin_tick() -> void:
	if not _spinning:
		return
	_spin_ticks += 1
	var any_moving := false
	for r in REELS:
		if not reel_stopped[r]:
			var strip_len = reel_strips[r].size() if reel_strips.size() > r and not reel_strips[r].is_empty() else 1
			reel_cursor[r] = (reel_cursor[r] + 1) % strip_len
			_write_reel_cell(r)
			any_moving = true
	if not any_moving:
		_finish_spin()
		return
	var w = max(_SPIN_MIN_WAIT, _SPIN_BASE_WAIT - _spin_ticks * 0.0010)
	_spin_timer.wait_time = w


# 把当前带子位置的符号写入展示格（旋转中每跳调用，复用既有 _refresh_cell）。
func _write_reel_cell(r: int) -> void:
	var strip = reel_strips[r] if reel_strips.size() > r else null
	if strip == null or strip.is_empty():
		grid[r][0] = TRASH_SYMBOL
		grid_elem[r][0] = "none"
	else:
		var idx = reel_cursor[r] % strip.size()
		grid[r][0] = strip[idx][0]
		grid_elem[r][0] = strip[idx][1]
	hud._refresh_cell(r, 0)


# 锁定某列：pos<0 表示锁定在当前带子位置（按停时机）。注废/锁轮列覆盖结果。
func _lock_reel(r: int) -> void:
	if r < 0 or r >= REELS or reel_stopped[r]:
		return
	if r == pending_jam_reel:
		grid[r][0] = TRASH_SYMBOL
		grid_elem[r][0] = "none"
		pending_jam_reel = -1
	elif r == pending_lock_reel:
		grid[r][0] = _locked_prev_sym[r]
		grid_elem[r][0] = _locked_prev_elem[r]
		pending_lock_reel = -1
	else:
		var strip = reel_strips[r]
		var idx = reel_cursor[r] % strip.size()
		grid[r][0] = strip[idx][0]
		grid_elem[r][0] = strip[idx][1]
	reel_stopped[r] = true
	hud._refresh_cell(r, 0)
	hud.set_reel_enabled(r, false)
	var all := true
	for rr in REELS:
		if not reel_stopped[rr]:
			all = false
			break
	if all:
		_finish_spin()


# 停止下一列（空格）：依次锁定尚未停下的列，时机由玩家掌握。
func _stop_next_reel() -> void:
	for r in REELS:
		if not reel_stopped[r]:
			_lock_reel(r)
			return


# 全部转轮停下：停止节拍器、复位交互态、发信号让结算继续。
func _finish_spin() -> void:
	if not _spinning:
		return
	_spinning = false
	_spin_timer.stop()
	for r in REELS:
		hud.set_reel_enabled(r, false)
	pending_jam_reel = -1
	pending_lock_reel = -1
	pending_chaos = false
	emit_signal("spin_finished")


# SPIN 按钮：旋转中=停止下一列，否则开始旋转。
func _on_spin_button_pressed() -> void:
	if _spinning:
		_stop_next_reel()
	else:
		_on_spin_pressed()


# 点击某列直接锁定该列（旋转中有效）。
func _on_reel_clicked(r: int) -> void:
	if not _spinning or reel_stopped[r]:
		return
	_lock_reel(r)


# 重转卷轴：免费重转一次（不触发敌人回合）
func _free_spin() -> void:
	if _busy:
		return
	_busy = true
	_begin_spin()
	await spin_finished
	await get_tree().create_timer(0.25).timeout
	await _evaluate()
	if enemy_hp <= 0:
		hud._log("★ 重转触发击败 %s！" % enemy_name)
		game_state = FlowState.WON
		hud._show_reward_screen(_is_boss_room(room_index))
	hud._refresh_meta()
	_busy = false


func _enemy_turn() -> void:
	var it: Dictionary = enemy_intent
	match it.get("type", "attack"):
		"attack", "heavy":
			_enemy_deal_damage(it.get("value", enemy_atk))
		"jam":
			pending_jam_reel = randi() % REELS
			hud._log("敌人注废 → 下一轮第 %d 列被废铁占据" % (pending_jam_reel + 1))
		"lock":
			pending_lock_reel = randi() % REELS
			hud._log("敌人锁轮 → 下一轮第 %d 列固定不变" % (pending_lock_reel + 1))
		"chaos":
			pending_chaos = true
			hud._log("敌人乱权 → 下一轮权重被打乱（优势符号被削弱）")
		"none":
			hud._log("敌人意图落空（已被净化）")
	enemy_intent = {}
	_tick_status()


func _enemy_deal_damage(raw: int) -> void:
	# 敌人 debuff 减益（元素驱动）：frost/poison = 敌人减攻。本函数是对敌人伤害的唯一闸口，
	# 且 _enemy_turn 在玩家结算之后，故当回合挂的 debuff 当回合生效。
	var atk_down = 1.0 - min(0.5, enemy_status.get("frost", 0) * 0.2 + enemy_status.get("poison", 0) * 0.2)
	var eff = int(round(float(raw) * atk_down * boss_atk_mult))
	if boss_atk_mult != 1.0:
		hud._log("🔒 呓语强化：敌人攻击 ×%s" % ElementCounter.fmt_mult(boss_atk_mult))
	if atk_down < 1.0:
		hud._log("敌人被削弱：攻击×%s" % ElementCounter.fmt_mult(atk_down))
	var blocked = min(player_shield, eff)
	player_shield -= blocked
	var dealt = max(0, eff - blocked)
	player_hp -= dealt
	if dealt > 0:
		hud._popup("-%d" % dealt, Palette.POP_DAMAGE, hud._player_sprite_anchor())
		if hud.animator != null:
			hud.animator.play_enemy_attack()
	hud._log("敌人攻击 %d（盾挡 %d，受 %d）" % [eff, blocked, dealt])


# 对敌人造成伤害（先破甲后掉血）：非穿透先扣护甲、溢出进 HP；穿透直接扣 HP。返回实际造成的总值。
func _apply_enemy_damage(amount: float, pierce: bool) -> float:
	var dmg = max(0, int(round(amount)))
	if dmg <= 0:
		return 0.0
	if pierce:
		enemy_hp -= dmg
		return float(dmg)
	var to_armor = min(enemy_armor, float(dmg))
	enemy_armor -= to_armor
	var to_hp = dmg - to_armor
	enemy_hp -= to_hp
	return float(dmg)


# 反制即爆发（Plan C）：
# · "special" = 通用破甲：清空敌人护甲，开启「伤害直击 HP」的爆发窗口（所有敌人通用破绽）。
# · "element" = 进阶核爆：克制元素三连，除破甲外再追加一次直接打血（穿透）的核爆伤害。
func _on_counter(kind: String) -> void:
	if enemy_armor > 0:
		hud._log("💥 %s破甲！护甲清零（%d）" % ["special 三连" if kind == "special" else "克制元素三连", int(enemy_armor)])
		enemy_armor = 0
	if kind == "element":
		var burst = int(enemy_hp_max * 0.20)
		if burst > 0:
			_apply_enemy_damage(burst, true)
			hud._popup("💥克制核爆!-%d" % burst, Palette.POP_DAMAGE, hud._enemy_sprite_anchor())
			hud._log("⚡ 克制元素三连触发核爆：%d 伤害（穿透护甲）" % burst)
	if hud.animator != null:
		hud.animator.play_counter(kind)


func _tick_status() -> void:
	var dot = 0
	for st in enemy_status.keys():
		var base = _status_base(st)
		var mult = ElementCounter.multiplier(_status_element(st), enemy_element)
		dot += int(round(enemy_status[st] * base * mult * STATUS_DMG_MULT))
		enemy_status[st] = max(0, enemy_status[st] - 1)
		if enemy_status[st] <= 0:
			enemy_status.erase(st)
	if dot > 0:
		enemy_hp -= dot
		hud._log("状态结算 %d 伤害（灼烧/毒·含克制）" % dot)


func _intent_name(t: String) -> String:
	match t:
		"jam":   return "注废"
		"lock":  return "锁轮"
		"chaos": return "乱权"
		"heavy": return "重击"
		"attack": return "攻击"
		_:      return t


# ---------------------------------------------------------------------------
# M6 消耗品：战斗中主动使用
# ---------------------------------------------------------------------------
# 4 格子（2x2）由 HUD 自管，本函数只触发刷新同步状态（不增删 cell，charges 用尽直接移出 slots 即可）
func _refresh_consumable_panel() -> void:
	hud._refresh_consumable_panel()


func _on_consumable_pressed(uid: String) -> void:
	if in_loadout or in_interroom or game_state != FlowState.PLAYING or _busy:
		return
	var target = -1
	for i in range(consumable_slots.size()):
		if consumable_slots[i]["uid"] == uid:
			target = i
			break
	if target < 0:
		return
	var slot = consumable_slots[target]
	if slot["charges"] <= 0:
		hud._log("「%s」已用尽" % slot["item_id"])
		return
	var data: Resource = load(slot["path"])
	if data == null:
		return
	slot["charges"] -= 1
	match data.effect:
		"purify":
			# 净化完全走消耗品：扣 1 charges，抵消当前干扰意图（如果有）；data.value 字段已废弃
			if enemy_intent.get("type") in ["jam", "lock", "chaos"]:
				var t = enemy_intent.get("type")
				enemy_intent = {"type": "none", "value": 0}
				hud._log("净化药剂：抵消了敌人的%s" % _intent_name(t))
			else:
				hud._log("净化药剂：当前无干扰意图可抵消")
		"heal":
			player_hp = min(player_hp_max, player_hp + data.value)
			hud._log("治疗药剂：回复 %d HP（现 %d）" % [data.value, player_hp])
		"assault":
			assault_next_spin = data.value
			hud._log("强袭药剂：下一次转轮伤害 ×%d" % data.value)
		"reroll":
			hud._log("重转卷轴：免费重转！")
			await _free_spin()
	_refresh_consumable_panel()
	if slot["charges"] <= 0:
		consumable_slots.remove_at(target)
		_refresh_consumable_panel()   # 4 cell 永远在位，只刷状态；charges=0 槽位自动变空
		hud._log("「%s」已用尽，移出腰带（可于商店补给）" % slot["item_id"])
	hud._refresh_meta()


func _on_overlay_button_pressed() -> void:
	hud._hide_overlay()    # 关闭失败弹层（通关已改走 reward→meta 直链，无 cleared 弹层）
	match game_state:
		FlowState.LOST:   _return_to_loadout()


func _return_to_loadout() -> void:
	# 玩家死亡 = 本局结束，回到整备页重选装备后开新 run（不再重开本房）。
	# 先落盘，确保当局铁砧点数 drip / 商店购买 / 铁砧授予等写入 owned_* 的进度不丢失。
	_save_meta()
	# selected_* 保留上局勾选，玩家可在整备页调整；确认开战时 _full_reset 重置本局状态。
	game_state = FlowState.PLAYING   # 解除 lost 终态，避免整备/铁砧界面误读终局
	hud._show_loadout_screen()


# ---------------------------------------------------------------------------
# 结算（方案 A：单符号必结算 + 匹配倍率）
# ---------------------------------------------------------------------------
func _reset_grid() -> void:
	hud._clear_badges()
	grid_elem = []
	for reel in REELS:
		grid_elem.append([])
		for row in ROWS:
			grid_elem[reel].append("none")
			grid[reel][row] = TRASH_SYMBOL
			if reel_strips.size() > reel and not reel_strips[reel].is_empty():
				var idx = randi() % reel_strips[reel].size()
				grid[reel][row] = reel_strips[reel][idx][0]
				grid_elem[reel][row] = reel_strips[reel][idx][1]
			hud._refresh_cell(reel, row)


func _contribute(sym: SymbolData, raw: int, acc: Dictionary, elem: String) -> void:
	# 连线精通(S12)：仅当实落 ≥2（确为连线匹配）时才叠加倍率，单符号必结算不受影响
	var mult = raw + (_shop_system.gold_upgrades["line"] * LINE_STEP if raw >= 2 else 0)
	# P3（docs/物品中心重构方案.md §8）：伤害 = (物品 base_power × 符号 base 偏移) × 连线 × 克制。
	# 物品有效攻击力来自 _weapon_power_map（base_power + 元进度武器加成）；未命中映射时退化为旧模型（flat = sym.base），
	# 保证非武器符号（异常路径）不丢伤害。BASE_POWER_REF 为归一化支点（见常量注释）。
	var item_power: float = _weapon_power_map.get(sym.resource_path, 0.0)
	var power_scale: float = item_power / BASE_POWER_REF if item_power > 0.0 else 1.0
	# bonus = 非 sym.base 部分（base_power 缩放增量 + F-0 元进度聚合），供 _push_dmg_line 分解展示；
	# flat = sym.base + bonus 与「sym.base × scale + _agg_power_flat()」恒等。
	var bonus: float = sym.base * power_scale - sym.base + _agg_power_flat()
	var flat: float = sym.base + bonus
	# 逐符号元素克制倍率（Phase G v2.0：通用元素乘区，奖罚并存·温和）
	var em = ElementCounter.multiplier(elem, enemy_element)
	if em > 1.0:
		_eval_adv = true
		# 反制即爆发（Plan C）：克制元素连线/三连标记，供 _evaluate 触发核爆
		if raw >= 2:
			acc["counter_triple"] = true
	elif em < 1.0:
		_eval_dis = true
	var crit_mult_val: float = _item_crit_map.get(sym.resource_path, 1.0) if raw >= 3 else 1.0
	match sym.kind:
		"damage":
			var dv = flat * mult * em
			if crit_mult_val > 1.0:
				dv *= crit_mult_val
			if sym.pierce_armor:
				acc["pierce"] += dv     # 穿透护甲：直接扣 HP
			else:
				acc["dmg"] += dv
			_push_dmg_line(acc, sym, elem, flat, bonus, mult, em, dv, crit_mult_val)
		"shield":  acc["shield"]  += sym.base * power_scale * mult * crit_mult_val   # P3：护盾/治疗符号同样随物品 base_power 缩放（强度轴），但不吃伤害元进度(_agg_power_flat)与元素克制；三连按 crit_mult 暴击（方案 A）
		"heal":    acc["heal"]    += sym.base * power_scale * mult * crit_mult_val
		"status":  acc["status_stacks"][sym.status_type] = acc["status_stacks"].get(sym.status_type, 0) + mult * crit_mult_val
		"special":
			# special：1 同即生效（base×连线数×克制）；三连触发暴击倍率（方案 A 统一为 crit_mult_val，普通/special 同源，保留破甲+连锁）
			var sv = flat * mult * em
			if crit_mult_val > 1.0:
				sv *= crit_mult_val
				acc["special_triple"] = true   # S10 T5 钩子埋点：三连发生标记，供 BOSS 机制感知
			if sym.pierce_armor:
				acc["pierce"] += sv
			else:
				acc["special"] += sv
			_push_dmg_line(acc, sym, elem, flat, bonus, mult, em, sv, crit_mult_val)
		_: pass


# S2：伤害分解行（§5.2 标为 P0——"爽感的一半来自看懂这一下为什么这么大"；
# 同时是 ante 调参（ANTE_ACT_STEP_HP/ATK、ANTE_ROOM_STEP_HP/ATK）的唯一 debug 依据）。
# 逐符号记录「基础 × 连线 × 克制 = 小计」，回合级乘区（护符/增益/强袭）在 _evaluate 汇总。
func _push_dmg_line(acc: Dictionary, sym: SymbolData, elem: String, flat, bonus, mult: int, em: float, v: float, crit_mult_val: float = 1.0) -> void:
	if not acc.has("lines"):
		return
	var parts := []
	if bonus > 0:
		parts.append("基础%d(=%d+%d)" % [int(flat), int(sym.base), int(bonus)])
	else:
		parts.append("基础%d" % int(flat))
	if mult > 1:
		parts.append("连线%d" % mult)
	# S-结算核查：带元素的符号永远显式写出克制关系（含中性×1.0），让"抗性数值"不再隐形
	if elem != "none":
		if em > 1.0:
			parts.append("克制×%s" % ElementCounter.fmt_mult(em))
		elif em < 1.0:
			parts.append("抗性×%s" % ElementCounter.fmt_mult(em))
		else:
			parts.append("中性×1.0")
	var etxt = "" if elem == "none" else "·" + ElementCounter.label(elem)
	var line = "   %s %s%s  %s = %d" % [sym.label, sym.name, etxt, " × ".join(parts), int(round(v))]
	if crit_mult_val > 1.0:
		line += "（⚡暴击 ×%s）" % ElementCounter.fmt_mult(crit_mult_val)
	acc["lines"].append(line)


# 结算：分两阶段（先防御/增益/状态，后攻击），接单向属性克制与强袭药剂。
# chain_mult：连锁重触发倍率（仅作用于 special 部分），由 _on_spin_pressed 的连锁循环逐层传入，默认 1.0。
func _evaluate(chain_mult := 1.0) -> void:
	hud._clear_badges()
	var acc = { "dmg": 0, "shield": 0, "heal": 0, "status_stacks": {}, "special": 0, "lines": [], "pierce": 0.0, "counter_triple": false }
	_eval_adv = false
	_eval_dis = false

	# 按「符号 + 有效元素」计数（解决共享符号跨武器元素冲突；HUD 角标据此展示）
	var counts = {}
	for p in PAYLINES[0]:
		var sym: SymbolData = grid[p[0]][p[1]]
		var elem: String = grid_elem[p[0]][p[1]]
		var key: String = sym.resource_path + "|" + elem
		if not counts.has(key):
			counts[key] = [sym, elem, 0]
		counts[key][2] += 1
	# Phase C：先结算 buff 符号（本回合即生效，命中当回合就吃到增益）
	for key in counts:
		var s: SymbolData = counts[key][0]
		if s == TRASH_SYMBOL or s.kind != "buff":
			continue
		_grant_buff(s, counts[key][2])
	# 金币符号（常驻）：落在线上的金币直接转化为金币资源，不造成任何伤害
	for key in counts:
		var s: SymbolData = counts[key][0]
		if s == GOLD_SYMBOL:
			var g = GOLD_PER_COIN * counts[key][2]
			if g > 0:
				gold += g
				hud._log("💰 金币 +%d" % g)
				hud._popup("💰+%d" % g, Palette.POP_GOLD, hud._player_sprite_anchor())
	# 再结算常规符号（此时 _contribute 读到的已是含新增益的加成，并按各自有效元素吃克制）
	for key in counts:
		var s: SymbolData = counts[key][0]
		var elem: String = counts[key][1]
		var c: int = counts[key][2]
		if s == TRASH_SYMBOL or s.kind == "buff" or s == GOLD_SYMBOL:
			continue
		if s.kind == "special" and c < 1:
			continue
		_contribute(s, c, acc, elem)

	# 匹配角标（×N，N>=2）
	hud._update_match_badges(counts)

	# —— 阶段 1：防御 / 增益 / 状态先落地 ——
	# Phase C：铁壁(shield)/回春(regen) 按回合生效，并入本回合护盾与治疗（F-0 聚合层）
	acc["shield"] += int(_agg_shield())
	acc["heal"] += int(_agg_regen())
	for st in acc["status_stacks"].keys():
		enemy_status[st] = enemy_status.get(st, 0) + acc["status_stacks"][st]
	if acc["shield"] > 0:
		player_shield += acc["shield"]
		hud._popup("🛡+%d" % acc["shield"], Palette.POP_SHIELD, hud._player_sprite_anchor())
		hud._log("获得 %d 护盾" % acc["shield"])
	if acc["heal"] > 0:
		player_hp = min(player_hp_max, player_hp + acc["heal"])
		hud._popup("❤+%d" % acc["heal"], Palette.POP_HEAL, hud._player_sprite_anchor())
		hud._log("回复 %d HP" % acc["heal"])
	if not acc["status_stacks"].is_empty():
		hud._log("敌人获得状态: " + _status_summary(acc["status_stacks"]))
		hud._popup(_status_summary(acc["status_stacks"]), Palette.POP_STATUS, hud._enemy_sprite_anchor())

	hud._refresh_meta()
	await get_tree().create_timer(0.45).timeout

	# S10 T5 钩子点 + 反制即爆发（Plan C）：special 三连 = 通用破甲；克制元素三连 = 进阶核爆。
	# current_gimmick 仅在 BOSS 房由 T2 的 BossGimmick 子类赋值；非 BOSS 房为 null，显式判空跳过（避免 ?. 在某些 4.x 不兼容）。
	if acc.get("special_triple", false):
		hud._log("⚡ special 三连触发")
		if current_gimmick != null:
			current_gimmick.on_special_triple(self)   # BOSS 自定义（如保留），通用破甲由 _on_counter 处理
	_last_special_triple = acc.get("special_triple", false)
	# 反制即爆发：克制元素三连（element）给核爆；否则 special 三连给通用破甲（清护甲窗口）
	if acc.get("counter_triple", false):
		_on_counter("element")
	elif acc.get("special_triple", false):
		_on_counter("special")

	# —— 阶段 2：攻击结算（先破甲后掉血；穿透符号直接扣 HP）——
	# Phase C：迅捷(damage_mult) 对本回合总伤害做乘算（F-0 聚合层，含护符乘区）
	var buff_mult = _agg_damage_mult()
	var assault = assault_next_spin
	var normal_subtotal = acc["dmg"] + acc["special"] * chain_mult
	var pierce_subtotal = acc.get("pierce", 0.0)
	var normal_total = int(normal_subtotal * assault * buff_mult * PLAYER_DMG_MULT)
	var pierce_total = int(pierce_subtotal * assault * buff_mult * PLAYER_DMG_MULT)
	assault_next_spin = 1
	var total = normal_total + pierce_total
	# S2：伤害分解只进调试日志（Debug.log），屏幕仅保留总伤害飘字（见下方 _popup）
	if not acc["lines"].is_empty():
		var blk := ["🔍 伤害分解"]
		blk.append_array(acc["lines"])
		var tail := []
		var cm = charm_damage_mult
		var bm = _buff_damage_mult()
		var jf = 1.0 + min(float(_shop_system.gold_upgrades["joker"]) * JOKER_STEP, JOKER_CAP_FACTOR - 1.0)
		if cm != 1.0:
			tail.append("护符×%s" % ElementCounter.fmt_mult(cm))
		if bm != 1.0:
			tail.append("增益×%s" % ElementCounter.fmt_mult(bm))
		if jf != 1.0:
			tail.append("共鸣×%s" % ElementCounter.fmt_mult(jf))
		if assault != 1:
			tail.append("强袭×%s" % ElementCounter.fmt_mult(float(assault)))
		if chain_mult != 1.0:
			tail.append("连锁×%s" % ElementCounter.fmt_mult(chain_mult))
		if pierce_total > 0:
			tail.append("穿透×直接HP")
		if tail.is_empty():
			blk.append("   合计 = %d" % total)
		else:
			blk.append("   小计 %d × %s = %d" % [int(round(normal_subtotal + pierce_subtotal)), " × ".join(tail), total])
		Debug.log("\n".join(blk))
	# 先破甲后掉血：非穿透先扣护甲溢出进 HP；穿透直接扣 HP
	if normal_total > 0:
		_apply_enemy_damage(normal_total, false)
	if pierce_total > 0:
		_apply_enemy_damage(pierce_total, true)
	if total > 0:
		if current_gimmick != null:
			current_gimmick.on_damaged(self, total)
		var elem_tag := ""
		if _eval_adv:
			elem_tag += " [克制]"
		if _eval_dis:
			elem_tag += " [抵抗]"
		if buff_mult != 1.0:
			elem_tag += "⚡"
		hud._popup("-%d%s" % [total, elem_tag], Palette.POP_DAMAGE, hud._enemy_sprite_anchor())
		hud._log("连线造成 %d 伤害%s（护甲剩 %d）" % [total, elem_tag, int(enemy_armor)])
		if hud.animator != null:
			hud.animator.play_attack("player", "enemy")
	hud._refresh_meta()   # 伤害落地后立即刷新：HP/护甲即时变化（破甲窗口需即时可见）
	await get_tree().create_timer(0.55).timeout
	# Phase C：回合末递减增益剩余回合
	_tick_buffs()


# ---------------------------------------------------------------------------
# 属性聚合层 (F-0) — 所有「修正轴」的统一查询入口
# ---------------------------------------------------------------------------
# 背景：M4 本局加成(run_*)、M6 护符(charm_*)、Phase C 增益(_buff_*) 各自独立地
# 散落在 _contribute / _evaluate / _build_pool 中，每加一类修正就要在三四处各插一刀。
# 本层把「加法标量 / 乘法标量 / 符号权重」三类轴统一成一组 _agg_* 查询，
# 调用方只认聚合层、不认具体来源。
#
# 新增一条修正轴只需在对应 _agg_* 末尾加一行求和，战斗结算零改动。
#
# 注意：本层只聚合「每符号 / 每回合」类修正。房开局护盾（守望护符 charm_room_shield
# / 守望结界 run_shield_next）与抗扰等是「房间级」修正，仍在各自原位处理，
# 不进入此层。
# ---------------------------------------------------------------------------

# —— 加法型标量轴（多个来源直接相加）——
# —— P0：以下结算聚合已抽到 BattleMath（参数化纯函数），controller 仅留薄包装，零行为变化 ——
func _agg_power_flat() -> float:
	return BattleMath.agg_power_flat(_reward_system.run_power_bonus, charm_power_bonus, player_buffs, _shop_system.gold_upgrades, POWER_STEP)

func _agg_shield() -> float:
	return BattleMath.agg_shield(player_buffs, charm_shield_trickle)


func _agg_regen() -> float:
	return BattleMath.agg_regen(player_buffs, charm_heal_trickle)

# —— 乘法型轴（各乘区独立相乘，基值 1.0）——
func _agg_damage_mult() -> float:
	return BattleMath.agg_damage_mult(charm_damage_mult, player_buffs, _shop_system.gold_upgrades, JOKER_STEP, JOKER_CAP_FACTOR)

# —— 符号权重轴（本局符号灌注；武器级权重见 _build_pool）——
func _agg_symbol_weight_mod(sym: SymbolData) -> float:
	return BattleMath.agg_symbol_weight_mod(_reward_system.run_symbol_bonus, sym)

# ---------------------------------------------------------------------------
# Phase C 主动增益：符号自描述（sym.buff_effect / buff_value / buff_turns），零查表
# player_buffs: SymbolData -> 剩余回合数
# ---------------------------------------------------------------------------
func _grant_buff(sym: SymbolData, mult: int) -> void:
	var add = max(1, sym.buff_turns) * mult
	player_buffs[sym] = int(player_buffs.get(sym, 0)) + add
	hud._popup("%s+%d" % [sym.label, add], Palette.POP_BUFF, hud._player_sprite_anchor())
	hud._log("技能：%s %s（剩余 %d 回合）" % [sym.label, sym.name, player_buffs[sym]])


# 乘法型增益（多个同时生效则连乘）
func _buff_damage_mult() -> float:
	return BattleMath.buff_damage_mult(player_buffs)


func _tick_buffs() -> void:
	var expired: Array = []
	for sym in player_buffs.keys():
		player_buffs[sym] = int(player_buffs[sym]) - 1
		if player_buffs[sym] <= 0:
			expired.append(sym)
	for sym in expired:
		player_buffs.erase(sym)
		hud._log("增益结束：%s %s" % [sym.label, sym.name])


func _buff_summary() -> String:
	return BattleMath.buff_summary(player_buffs)


func _buff_effect_name(effect: String) -> String:
	return BattleMath.buff_effect_name(effect)


func _status_base(type_str: String) -> float:
	return BattleMath.status_base(pool, type_str)


# 状态类型对应的属性元素（用于 DoT 单向克制）
func _status_element(st: String) -> String:
	return BattleMath.status_element(pool, st)


func _status_summary(stacks: Dictionary) -> String:
	return BattleMath.status_summary(stacks, STATUS_NAMES)


# ---------------------------------------------------------------------------
# 表现刷新
# ---------------------------------------------------------------------------
func _input(event) -> void:
	if in_loadout:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		if _spinning:
			_stop_next_reel()
		else:
			_on_spin_pressed()
