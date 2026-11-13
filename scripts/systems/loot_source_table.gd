class_name LootSourceTable
extends RefCounted

# 四级品质战利品 Step 3：来源品质表。
# 职责只有一件事——给定来源与幕次，返回该次奖励应进入的品质层权重。
# 不扫描物品、不抽具体候选、不读玩家 Build；这些在 LootPool 里做。
#
# 规则来源：docs/四级品质战利品与大奖池_分步执行计划_2026-11-12.md §4.1。
# 首版以本表为战斗/探索来源的唯一品质概率来源：
#   - 不叠加旧的 acquisition_weight / boss_depth_bias；
#   - 商店不随机品质，走 loot_shop_ladder 的确定性阶梯；
#   - 特殊事件（event）需要公开风险配置，未配置时明确返回空原因，不借用其它来源表。

const BALANCE = preload("res://resources/config/balance_config.tres")

const QUALITIES := ["common", "uncommon", "rare", "epic"]
const BATTLES := ["normal", "elite", "boss", "chest"]
const SOURCES := ["normal", "elite", "boss", "chest", "event", "shop", "anvil"]
# Step 7：四级品质统一显示名（存档值不变，只收口展示文案）。
const QUALITY_LABELS := {"common": "基础", "uncommon": "进阶", "rare": "稀有", "epic": "传说"}
# 来源显示名（奖励屏标题与图鉴共用一套口径）。
const SOURCE_LABELS := {
	"normal": "普通战", "elite": "精英战", "boss": "BOSS",
	"chest": "探索宝箱", "event": "特殊事件", "shop": "商店", "anvil": "铁砧",
}


static func quality_label(quality: String) -> String:
	return String(QUALITY_LABELS.get(quality, quality))


static func source_label(source: String) -> String:
	return String(SOURCE_LABELS.get(source, source))
const ACT_NOTES := {
	"event": "特殊事件按公开风险单独配置，首版未配置",
	"anvil": "铁砧是局外 gacha，不进入战斗来源表",
}


static func is_valid_source(source: String) -> bool:
	return source in SOURCES


static func is_valid_act(act: int) -> bool:
	return act >= 1 and act <= int(BALANCE.run_acts)


# 该来源是否由本表随机品质（商店/特殊事件/铁砧返回 false）。
static func uses_random_quality(source: String) -> bool:
	return source in BATTLES


# 返回 {ok, weights, reason}。weights 为品质 → 整数权重（合计 100）。
static func weights_for(source: String, act: int) -> Dictionary:
	if not is_valid_source(source):
		return {"ok": false, "weights": {}, "reason": "invalid_source"}
	if not is_valid_act(act):
		return {"ok": false, "weights": {}, "reason": "invalid_act"}
	if not uses_random_quality(source):
		return {"ok": false, "weights": {}, "reason": "not_random:" + source}
	var table: Dictionary = BALANCE.loot_source_weights.get(source, {})
	if table.is_empty():
		return {"ok": false, "weights": {}, "reason": "unconfigured:" + source}
	var w := {}
	var total := 0
	for q in QUALITIES:
		var v := int(table.get(q, 0))
		if v < 0:
			v = 0
		w[q] = v
		total += v
	if total <= 0:
		return {"ok": false, "weights": {}, "reason": "empty_table:" + source}
	return {"ok": true, "weights": w, "reason": ""}


# 按来源表抽一个品质。rng 必须是调用方持有的专用流（不得用全局 RNG）。
# 返回 "" 表示该来源不随机/未配置（配合 weights_for 的 reason 使用）。
static func roll_quality(source: String, act: int, rng: RandomNumberGenerator) -> String:
	var res := weights_for(source, act)
	if not bool(res["ok"]):
		return ""
	var w: Dictionary = res["weights"]
	var total := 0
	for q in QUALITIES:
		total += int(w[q])
	var roll := rng.randf() * float(total)
	for q in QUALITIES:
		roll -= float(w[q])
		if roll <= 0.0:
			return q
	return QUALITIES[QUALITIES.size() - 1]


# 商店货架的确定性品质阶梯（每幕 6 格；不足/越界返回空数组）。
static func shop_tiers(act: int) -> Array:
	if not is_valid_act(act):
		return []
	var tiers: Array = BALANCE.loot_shop_ladder.get(act, [])
	return tiers.duplicate()


# 商店货架的确定性类别序列（与 shop_tiers 同下标；Step 5）。
static func shop_categories(act: int) -> Array:
	if not is_valid_act(act):
		return []
	var cats: Array = BALANCE.loot_shop_categories.get(act, [])
	return cats.duplicate()


# 品质序（仅用于排序与测试，不参与抽取）。
static func rank(quality: String) -> int:
	var idx := QUALITIES.find(quality)
	return idx if idx >= 0 else -1
