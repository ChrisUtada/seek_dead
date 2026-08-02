class_name ElementCounter
extends RefCounted

# ============================================================================
# 属性克制（五元素单向环）
# 设计原则（来自需求）：玩家角色本身无属性，仅「玩家符号元素 → 敌人元素」
# 单向生效；敌人对玩家的攻击永远忽略元素（恒中性）。
#
# 克制环：火 > 冰 > 毒 > 光 > 暗 > 火
#   · 克制（atk 克 def）：伤害 ×1.5（爽点）
#   · 抵抗（def 克 atk）：伤害 ×0.85（温和惩罚，不崩盘，中性武器可作对冲）
#   · 中性 / 任意一方为 none：×1.0
# 设计意图（Phase G v2.0）：奖罚并存但温和，保留"带错元素小亏"的真实感与策略深度，
# 同时避免强惩罚（×0.7）带来的挫败与"背五元环"负担。敌人以「弱 X / 抗 Y」视角呈现，
# 玩家从敌人属性判断，无需记忆整个克制环。
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

# 克制倍率（温和版）
const MULT_ADVANTAGE := 1.5    # 克制（弱点）
const MULT_RESIST := 0.85      # 抵抗（抗性，温和惩罚）
const MULT_NEUTRAL := 1.0      # 中性 / 任意一方为 none

# 攻击方元素 atk 对防守方元素 def 的伤害倍率
static func multiplier(atk: String, def: String) -> float:
	if atk == "none" or def == "none":
		return MULT_NEUTRAL
	if BEATS.get(atk, "") == def:
		return MULT_ADVANTAGE
	if BEATS.get(def, "") == atk:
		return MULT_RESIST
	return MULT_NEUTRAL


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


# S3：敌人视角反查 —— 「什么元素能克它」。用于 HUD 呈现「弱 X ×1.5」，
# 让玩家从敌人身上直接读出该带什么武器，无需在脑子里跑一遍五元环。
static func weakness(def: String) -> String:
	if def == "none":
		return "none"
	for a in ELEMENTS:
		if BEATS.get(a, "") == def:
			return a
	return "none"


# S3：敌人视角反查 —— 「它抗什么元素」。敌人抵抗自己所克制的那一环。
static func resists(def: String) -> String:
	if def == "none":
		return "none"
	return BEATS.get(def, "none")


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
