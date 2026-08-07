class_name ShopConfig
extends Resource

# 商店经济配置（resources/config/shop_config.tres）——从 shop_system.gd 的内联字典抽出。
# 价格模型：price = base + jitter + max(0, 已持数 - 初始配额 + 1) * step，再夹 price_floor。
# base 按类定起点、step 按类定递增斜率（护符最大：唯一收集乘区须最贵；增益次之；武器居中；消耗品最低）。
# 数值与节奏闸门说明见 shop_system.gd 头注释与 shop_price 的注释。

@export var base_price: Dictionary = {"weapon": 8, "passive": 10, "active": 5, "skill": 6}
@export var step_price: Dictionary = {"weapon": 5, "passive": 8, "active": 4, "skill": 6}
@export var fallback_base: int = 6   # 未收录类别的兜底 base
@export var fallback_step: int = 4   # 未收录类别的兜底 step
@export var jitter_min: int = -1     # 每次报价的随机浮动下限
@export var jitter_max: int = 2      # 每次报价的随机浮动上限
@export var price_floor: int = 3     # 价格下限（防零价/负价）
@export var sell_refund_ratio: float = 0.5   # 卖出返还实际购入价的比例（过高会刷金，过低换装几乎免费）
