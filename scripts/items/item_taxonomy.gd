class_name ItemTaxonomy
extends RefCounted

# 四级品质战利品 Step 1：物品构筑标签的统一词表。
# 只定义可用取值与显示名，不承担掉落、结算或 UI 逻辑。
# 资源侧字段写在 LoadoutItem / ItemData 上（family_tags / role / source_tags / ...）。

const FAMILIES: Array[String] = [
	"fire", "ice", "poison", "light", "dark",
	"shield", "charge", "combo", "reel", "resource",
]

const ROLES: Array[String] = [
	"damage", "defense", "recovery", "control", "resource", "utility", "conversion",
]

# normal/elite/boss/chest/event 对应来源；shop/anvil/start 为现有确定性或开局渠道。
const SOURCES: Array[String] = [
	"normal", "elite", "boss", "chest", "event", "shop", "anvil", "start",
]

const RARITIES: Array[String] = ["common", "uncommon", "rare", "epic"]

const FAMILY_LABEL := {
	"fire": "火焰/灼烧",
	"ice": "冰霜/迟滞",
	"poison": "毒素/酸蚀",
	"light": "光明/恢复",
	"dark": "暗影/风险",
	"shield": "护盾/反击",
	"charge": "充能/爆发",
	"combo": "连击/三连",
	"reel": "转轮操作",
	"resource": "消耗品/资源",
}

const ROLE_LABEL := {
	"damage": "输出",
	"defense": "防御",
	"recovery": "恢复",
	"control": "控制",
	"resource": "资源",
	"utility": "操作",
	"conversion": "转化",
}

const SOURCE_LABEL := {
	"normal": "普通战",
	"elite": "精英战",
	"boss": "BOSS 战利品",
	"chest": "探索宝箱",
	"event": "特殊事件",
	"shop": "商店",
	"anvil": "铁砧",
	"start": "开局收藏",
}

const RARITY_LABEL := {
	"common": "基础",
	"uncommon": "进阶",
	"rare": "稀有",
	"epic": "传说",
}


static func is_valid_family(tag: String) -> bool:
	return FAMILIES.has(tag)


static func is_valid_role(role: String) -> bool:
	return ROLES.has(role)


static func is_valid_source(source: String) -> bool:
	return SOURCES.has(source)


static func is_valid_rarity(rarity: String) -> bool:
	return RARITIES.has(rarity)


static func family_label(tag: String) -> String:
	return String(FAMILY_LABEL.get(tag, tag))


static func role_label(role: String) -> String:
	return String(ROLE_LABEL.get(role, role))


static func source_label(source: String) -> String:
	return String(SOURCE_LABEL.get(source, source))


static func rarity_label(rarity: String) -> String:
	return String(RARITY_LABEL.get(rarity, rarity))
