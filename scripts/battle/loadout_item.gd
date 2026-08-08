class_name LoadoutItem
extends Resource

# 物品中心重构（P1 · docs/[已完成]物品中心重构方案.md）
# 武器与技能的统一基类，只承载「强度轴」字段。
#
# 刻意不含 element / symbols / reel：
#   - WeaponData.element 已在子类定义（duel_controller L698 消费 wd.element），
#     基类重定义会触发 GDScript 字段重声明错误；
#   - 符号容器在子类形态不同（武器用 Array[SymbolWeight] reel，技能用单个 SymbolData symbol），
#     统一字段名（reel→symbols）留待 P2 池代码重写时再做。
#
# 频率轴（符号出现多少次）不由本类管，由符号 kind → 频率档派生（§4）。
# 稀有度只定强度（base_power 量级 / hit_rate 基线 / 升级上限 / 商店价），不定频率，
# 避免「神装稀有→符号少出现→打不出去」的退化。

@export var category: String = "weapon"   # "weapon" | "skill" —— 槽位规则与 UI 分列依据
@export var rarity: String = "common"     # 强度档位 common|uncommon|rare|epic（只定强度，不定频率）
@export var base_power: float = 10.0      # 攻击力 / 效能（升级主通道；P3 结算改读此字段取代 weapon.damage 缝合）
@export var hit_rate: float = 0.85        # 命中率（1 - hit_rate = 废铁 miss 格占比；P2 按此注入转轮）
@export var crit_mult: float = 2.0        # 三连暴击倍率（方案A：确定性，符号/元素凑齐 3 连即按此倍率结算；
@export var crit_chance: float = 0.0      # 非三连暴击率加成（0~0.15）：总暴击率 = BALANCE.crit_chance + 此值；高 base 武器低暴击（代价轴，2026-08-07）
@export var triple_pierce: bool = false   # 破甲机制（2026-08-07）：该武器/技能符号凑成三连时清空敌人护甲；无此机制的三连只必暴+连锁
# 落在强度轴由 .tres 定义，取代硬编码 SPECIAL_TRIPLE_CRIT；稀有度高的装备可给更高值（2.5~3.0）制造强度纹理。
# 仅设计期属性，非战斗内新开乘区，符合「膨胀/策略放 build 层」铁律）
