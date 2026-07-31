class_name ElementCounter
extends RefCounted

# ============================================================================
# 属性克制（五元素单向环）
# 设计原则（来自需求）：玩家角色本身无属性，仅「玩家符号元素 → 敌人元素」
# 单向生效；敌人对玩家的攻击永远忽略元素（恒中性）。
#
# 克制环：火 > 冰 > 毒 > 光 > 暗 > 火
#   · 克制（atk 克 def）：伤害 ×1.5
#   · 抵抗（def 克 atk）：伤害 ×0.7
#   · 中性 / 任意一方为 none：×1.0
# ============================================================================

const ELEMENTS := ["fire", "ice", "poison", "light", "dark"]

# BEATS[a] = a 克制的元素
const BEATS := {
	"fire":   "ice",
	"ice":    "poison",
	"poison": "light",
	"light":  "dark",
	"dark":   "fire",
}

# 攻击方元素 atk 对防守方元素 def 的伤害倍率
static func multiplier(atk: String, def: String) -> float:
	if atk == "none" or def == "none":
		return 1.0
	if BEATS.get(atk, "") == def:
		return 1.5
	if BEATS.get(def, "") == atk:
		return 0.7
	return 1.0


# 关系描述：克制 / 抵抗 / 中性
static func relation(atk: String, def: String) -> String:
	if atk == "none" or def == "none":
		return "中性"
	if BEATS.get(atk, "") == def:
		return "克制"
	if BEATS.get(def, "") == atk:
		return "抵抗"
	return "中性"


# 战斗日志用的简短标注（如 "🔥克❄" / "🛡抵抗" / ""）
static func tag(atk: String, def: String) -> String:
	var r := relation(atk, def)
	if r == "克制":
		return " [克制]"
	if r == "抵抗":
		return " [抵抗]"
	return ""


static func label(element: String) -> String:
	match element:
		"fire":   return "火"
		"ice":    return "冰"
		"poison": return "毒"
		"light":  return "光"
		"dark":   return "暗"
		_:        return "无"


static func color(element: String) -> Color:
	match element:
		"fire":   return Color(1.00, 0.45, 0.20)
		"ice":    return Color(0.50, 0.80, 1.00)
		"poison": return Color(0.60, 0.90, 0.40)
		"light":  return Color(1.00, 0.92, 0.55)
		"dark":   return Color(0.65, 0.55, 0.85)
		_:        return Color(0.70, 0.70, 0.75)
