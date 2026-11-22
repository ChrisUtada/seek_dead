class_name ShopConfig
extends Resource

# 商店经济配置（resources/config/shop_config.tres）——从 shop_system.gd 的内联字典抽出。
# 价格模型（固定目录价，T1.2）：price = base × rarity_price_mult[稀有度]，再夹 price_floor。
# 同稀有度同价、跨局同价、不随持有数递增。数值说明见 shop_system.gd 的 shop_price 注释。

@export var base_price: Dictionary = {"weapon": 8, "passive": 10, "active": 5, "skill": 6}
@export var rarity_price_mult: Dictionary = {"common": 1.0, "uncommon": 1.6, "rare": 2.4, "epic": 3.6}   # L1 经济：稀有度定价阶梯（武器 rare 8×2.4≈19、epic 8×3.6≈29；原 3.0/5.0=24/40 对低产出偏高）
@export var fallback_base: int = 6   # 未收录类别的兜底 base
@export var price_floor: int = 3     # 价格下限（防零价/负价）
@export var sell_refund_ratio: float = 0.5   # 卖出返还实际购入价的比例（过高会刷金，过低换装几乎免费）
@export var free_item_sell_price: int = 3    # 无购入价物品（BOSS/宝箱免费掉落、腰带满折算）的固定卖出价——堵住"免费掉落变现"白嫖

# —— 货架刷新（reroll，2026-08-09）——
# 每房间歇期可付费重滚货架：价格 = reroll_base + 已刷次数 × reroll_step（Balatro 式递增，自然抑制滥用），
# 上限 reroll_max 次（双闸门防金币无限转化）。reroll_used 随房间歇期清零（_enter_interroom 重置）。
@export var reroll_base: int = 4     # 首次刷新价格
@export var reroll_step: int = 2     # 每次刷新递增价（4→6→8→10）
@export var reroll_max: int = 3      # 每房间歇期刷新次数上限
