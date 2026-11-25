class_name ComboCatalog
extends RefCounted

# T3-3 C 轮前置（2026-11-25）：组合目录的只读数据契约。
#
# 全 static、无状态。唯一入口 build_rows() 产出固定字段的 Dictionary 数组，
# 供 C 轮面板消费；面板不得直接读 acc。
# 铁律：不读写 enemy_hp / enemy_status / charge / RNG；不调用任何会改状态的方法。
# G01/G02/G03 是 pattern_matcher.gd 的脚本常量，这里合成三行只读展示行，不迁资源。

const MATCHER = preload("res://scripts/battle/pattern_matcher.gd")

# G 系合成行（非资源牌谱，仅展示用；字段与资源行同构）
const G_ROWS := [
	{"id": "G01", "name": "同源刻", "desc": "三张同族同来源（非资源牌谱）"},
	{"id": "G02", "name": "同族刻", "desc": "三张同族，来源不限（非资源牌谱）"},
	{"id": "G03", "name": "清一色", "desc": "三张同元素（非资源牌谱）"},
]


# group 映射（按 StepA §D 裁决）：
# base=G 系合成行；main=weapon_attack；aux=skill / skill_support；
# signature=signature；universal=其余。
static func _group_of(pattern) -> String:
	var track: String = String(pattern.track)
	match track:
		"weapon_attack": return "main"
		"skill", "skill_support": return "aux"   # 实际资源用 skill_support（T01–T03）
		"signature": return "signature"
		_: return "universal"


# 从 last_acc 只读取「当前命中」：装备位、技能位、通用位。
static func _matched_ids(last_acc: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var w: String = String(last_acc.get("pattern_weapon", ""))
	var s: String = String(last_acc.get("pattern_skill", ""))
	if w != "":
		out.append(w)
	if s != "" and s != w:
		out.append(s)
	var sig: String = String(last_acc.get("pattern_signature", ""))
	if sig != "" and not out.has(sig):
		out.append(sig)
	for u in (last_acc.get("patterns_universal", []) as Array):
		if u == null:
			continue
		var uid: String = String(u.id) if u is Resource else String(u.get("id", ""))
		if uid != "" and not out.has(uid):
			out.append(uid)
	return out


# condition_text：复用 PatternMatcher.describe_condition()，多条件用「 + 」拼接。
# matcher 未覆盖 symbol_category，这里只在目录层补一句可读描述，不改 matcher。
static func _condition_text(pattern) -> String:
	var rule: Dictionary = pattern.match_rule
	var conds: Array = rule.get("all", []) as Array
	var parts: Array[String] = []
	for c in conds:
		if not (c is Dictionary):
			continue
		var text: String = MATCHER.describe_condition(c as Dictionary)
		var cat: String = String((c as Dictionary).get("symbol_category", ""))
		if cat != "":
			parts.append("%s符号" % cat)
		elif text != "":
			parts.append(text)
	return " + ".join(parts)


# contribution_text：只从 acc["lines"] 里按牌谱名匹配，取不到留空。
static func _contribution_text(pattern, last_acc: Dictionary) -> String:
	var name: String = String(pattern.name)
	if name == "":
		return ""
	for line in (last_acc.get("lines", []) as Array):
		if String(line).contains(name):
			return String(line)
	return ""


static func build_rows(pattern_system, loadout_paths: Array, tag_of: Callable,
		last_acc: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var matched: Array[String] = _matched_ids(last_acc)

	# 资源牌谱行：unlocked 直接复用 PatternData.unlocked()，不另写判定。
	for p in (pattern_system.all_patterns() as Array):
		if p == null:
			continue
		var id: String = String(p.id)
		var unlocked: bool = bool(p.unlocked(loadout_paths, tag_of))
		rows.append({
			"id": id,
			"name": String(p.name),
			"group": _group_of(p),
			"priority": int(p.priority),
			"unlocked": unlocked,
			"matched_now": matched.has(id),
			"condition_text": _condition_text(p),
			"contribution_text": _contribution_text(p, last_acc),
		})

	# G 系三行（合成、非资源、恒定 unlocked，matched_now 看通用位）。
	for g in G_ROWS:
		var gid: String = String(g["id"])
		var gname: String = String(g["name"])
		var gline: String = ""
		for line in (last_acc.get("lines", []) as Array):
			if String(line).contains(gname):
				gline = String(line)
				break
		rows.append({
			"id": gid,
			"name": gname,
			"group": "base",
			"priority": 0,
			"unlocked": true,
			"matched_now": matched.has(gid),
			"condition_text": "%s（非资源牌谱）" % String(g["desc"]),
			"contribution_text": gline,
		})
	return rows
