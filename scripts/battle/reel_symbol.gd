class_name ReelSymbol
extends RefCounted

# ============================================================================
# 老虎机战斗 — 符号单一事实来源（单一来源）
# 原型 (reel_combat.gd) 与正式 WeaponData 共用此定义。
# 符号 id 同时作为 WeaponData.reel_symbols 字典的 key（整数）。
# ============================================================================

enum Id { SLASH, SHOT, BURN, FROST, POISON, BLOCK, HEAL, SPECIAL, TRASH }

# kind: damage / shield / heal / status / special / trash
# base: 伤害/护盾/治疗的基础值；status 时为「每堆叠每回合 DoT」
# status: status 类型字符串（仅 kind=="status" 有）
const CATALOG: Dictionary = {
	Id.SLASH:  { "label": "⚔️", "name": "斩",   "kind": "damage", "base": 10.0, "color": Color(0.95, 0.35, 0.30) },
	Id.SHOT:   { "label": "🔫", "name": "射",   "kind": "damage", "base": 9.0,  "color": Color(1.00, 0.85, 0.40) },
	Id.BURN:   { "label": "🔥", "name": "燃",   "kind": "status", "base": 4.0,  "status": "burn",   "color": Color(1.00, 0.50, 0.20) },
	Id.FROST:  { "label": "❄️", "name": "霜",   "kind": "status", "base": 3.0,  "status": "frost",  "color": Color(0.50, 0.80, 1.00) },
	Id.POISON: { "label": "☠️", "name": "毒",   "kind": "status", "base": 3.0,  "status": "poison", "color": Color(0.60, 0.90, 0.40) },
	Id.BLOCK:  { "label": "🛡️", "name": "格挡", "kind": "shield", "base": 8.0,  "color": Color(0.55, 0.70, 0.95) },
	Id.HEAL:   { "label": "❤️", "name": "治疗", "kind": "heal",   "base": 6.0,  "color": Color(0.50, 0.95, 0.60) },
	Id.SPECIAL:{ "label": "💥", "name": "特殊", "kind": "special","base": 25.0, "color": Color(1.00, 0.80, 0.20) },
	Id.TRASH:  { "label": "🗑️", "name": "废铁", "kind": "trash",  "base": 0.0,  "color": Color(0.50, 0.50, 0.55) },
}


# 按 id 取符号定义；越界/未知返回 TRASH 定义。
static func get_symbol(id: int) -> Dictionary:
	if CATALOG.has(id):
		return CATALOG[id]
	return CATALOG[Id.TRASH]


static func label_of(id: int) -> String:
	return get_symbol(id)["label"]


static func color_of(id: int) -> Color:
	return get_symbol(id)["color"]
