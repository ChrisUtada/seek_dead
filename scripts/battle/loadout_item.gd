class_name LoadoutItem
extends Resource

# 物品中心重构（P1 · docs/物品中心重构方案.md）
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
