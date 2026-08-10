class_name ElementCounter
extends RefCounted

# ============================================================================
# 属性克制 v2（互克对 + 同元素 + 毒链）——设计定稿见 docs/元素克制设计_v2.md
# 设计原则（不变）：玩家角色本身无属性，仅「玩家符号元素 → 敌人元素」单向生效；
# 敌人对玩家的攻击永远忽略元素（恒中性，= 普通攻击）。
#
# 克制 ×1.5（全部直觉可解释）：
#   火 → 冰（融化）、火 → 毒（高温消毒）
#   冰 → 火（灭火，与火互克）
#   光 → 暗（驱散）、光 → 毒（圣光净化）
#   暗 → 光（吞噬，与光互克）
#   毒 → 暗（腐蚀幽冥）
# 抵抗 ×0.85（被克方的还击 + 同元素，宝可梦式同属性减伤）：
#   同元素对打（火打火/冰打冰/毒打毒/光打光/暗打暗）
#   毒 打 火、毒 打 光（被消毒/净化）
# 中性 ×1.0：其余组合；任意一方为 none（无属性/普通攻击恒中性）
# ============================================================================

const ELEMENTS := ["fire", "ice", "poison", "light", "dark"]

# BEATS[a] = a 克制的元素数组（一个元素可克多个）
const BEATS := {
	"fire":   ["ice", "poison"],
	"ice":    ["fire"],
	"poison": ["dark"],
	"light":  ["dark", "poison"],
	"dark":   ["light"],
}

# 克制倍率（温和版）
const MULT_ADVANTAGE := 1.5    # 克制（弱点）
const MULT_RESIST := 0.85      # 抵抗（抗性/同元素，温和惩罚）
const MULT_NEUTRAL := 1.0      # 中性 / 任意一方为 none

# 攻击方元素 atk 对防守方元素 def 的伤害倍率
static func multiplier(atk: String, def: String) -> float:
	if atk == "none" or def == "none":
		return MULT_NEUTRAL
	if atk == def:
		return MULT_RESIST   # 同元素对打（宝可梦式同属性减伤）
	if BEATS.get(atk, []).has(def):
		return MULT_ADVANTAGE
	if BEATS.get(def, []).has(atk):
		return MULT_RESIST
	return MULT_NEUTRAL


# 关系描述：克制 / 抵抗 / 同源 / 中性
static func relation(atk: String, def: String) -> String:
	if atk == "none" or def == "none":
		return "中性"
	if atk == def:
		return "同源"
	if BEATS.get(atk, []).has(def):
		return "克制"
	if BEATS.get(def, []).has(atk):
		return "抵抗"
	return "中性"


# 战斗日志用的简短标注（如 "🔥克❄" / "🛡抵抗" / "同源" / ""）
static func tag(atk: String, def: String) -> String:
	var r := relation(atk, def)
	if r == "克制":
		return " [克制]"
	if r == "抵抗":
		return " [抵抗]"
	if r == "同源":
		return " [同源]"
	return ""


# S3：敌人视角反查 —— 「什么元素能克它」（可能多个）。用于 HUD 呈现「弱 X ×1.5」。
static func weakness(def: String) -> Array[String]:
	var out: Array[String] = []
	if def == "none":
		return out
	for a in ELEMENTS:
		if BEATS.get(a, []).has(def):
			out.append(a)
	return out


# S3：敌人视角反查 —— 「它抗什么元素」= 打它伤害 ×0.85 的元素（同元素 + 被它克制且非互克的元素）。
# 用 multiplier 反查而非 BEATS 直推：互克对（火↔冰）里火打冰是 1.5 克制而非抗性，直推会误报。
static func resists(def: String) -> Array[String]:
	var out: Array[String] = []
	if def == "none":
		return out
	for a in ELEMENTS:
		if multiplier(a, def) == MULT_RESIST:
			out.append(a)
	return out


# 倍率文本：1.50 → "1.5"、0.85 → "0.85"（去掉无意义的尾零）
static func fmt_mult(m: float) -> String:
	var s := "%.2f" % m
	while s.ends_with("0"):
		s = s.substr(0, s.length() - 1)
	if s.ends_with("."):
		s = s.substr(0, s.length() - 1)
	return s


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
