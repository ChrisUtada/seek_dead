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
	# G 系命中来自 acc["pattern_match"]["patterns"]（matcher 的 {id,name} 列表）。
	# pattern_match 可能为空字典或缺 patterns 键，必须安全跳过。
	var pm = last_acc.get("pattern_match", null)
	if pm is Dictionary:
		var pats = (pm as Dictionary).get("patterns", [])
		if pats is Array:
			for p in (pats as Array):
				if not (p is Dictionary):
					continue
				var pid: String = String((p as Dictionary).get("id", ""))
				if pid != "" and not out.has(pid):
					out.append(pid)
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
			parts.append(cat)
		elif text != "":
			parts.append(text)
	# 相邻相同描述折叠为「描述×N」；没有重复时保留原描述（W01 三条不同描述用 " + " 拼接）。
	var has_dup := false
	for i in range(1, parts.size()):
		if parts[i] == parts[i - 1]:
			has_dup = true
			break
	if not has_dup:
		return " + ".join(parts)
	var folded: Array[String] = []
	for text in parts:
		if not folded.is_empty() and folded[folded.size() - 1].begins_with(text + "×"):
			var prev: String = folded[folded.size() - 1]
			var n: int = int(prev.substr(text.length() + 1))
			folded[folded.size() - 1] = "%s×%d" % [text, n + 1]
		else:
			folded.append(text + "×1")
	return " + ".join(folded)


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

	# G 系三行（合成、非资源、恒定 unlocked，matched_now 读 acc["pattern_match"]）
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


# T3-3 C 轮第 4 步（2026-11-26）：第三格只读预览（纯函数）。
# base_cards 为已锁两格的真实牌卡（与 cards_from_grid 同构）；candidates 为候选符号路径。
# 对每个候选拼出三张卡，跑 weapon_attack / skill_support 牌谱的 solve_rule；
# G01–G03 用 PatternMatcher.match(cards).patterns 一并记。每个候选都出一行（无命中也出）。
# 铁律：不读 _ctrl、不写状态、不调用结算、不消耗 RNG。
static func preview_third_slot(base_cards: Array, candidates: Array[String],
		pattern_system, tag_of) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if base_cards.size() != 2:
		return out   # 未锁两格不产出预览
	var patterns: Array = []
	if pattern_system != null:
		for p in (pattern_system.all_patterns() as Array):
			if p == null:
				continue
			var track := String(p.track)
			if track == "weapon_attack" or track == "skill_support":
				patterns.append(p)
	for c in candidates:
		var path := String(c)
		var sym = load(path)
		var cname := path.get_file().get_basename()
		if sym != null and String(sym.name) != "":
			cname = String(sym.name)
		var cards: Array = base_cards.duplicate()
		cards.append({
			"sym": sym, "element": "none", "source": "",
			"source_kind": "resource", "source_element": "none",
			"skill_role": "", "valid": true,
		})
		var matched: Array[Dictionary] = []
		if sym != null:
			for p in patterns:
				if MATCHER.solve_rule(cards, p.match_rule):
					matched.append({
						"id": String(p.id),
						"name": String(p.name),
						"group": _group_of(p),
					})
			for g in (MATCHER.match(cards).get("patterns", []) as Array):
				if not (g is Dictionary):
					continue
				matched.append({
					"id": String((g as Dictionary).get("id", "")),
					"name": String((g as Dictionary).get("name", "")),
					"group": "base",
				})
		out.append({"candidate": path, "candidate_name": cname, "matched": matched})
	return out


# 状态键 → 展示名（与工单示例一致；未收录的键回退原文）。
const STATUS_LABELS := {
	"burn": "燃烧",
	"frost": "霜冻",
	"poison": "中毒",
	"holy_burn": "圣灼",
	"shadow_blight": "蚀影",
}


# T3-3 C 轮第 3 步（2026-11-26）：本轮来源分解（只读）。
# 消费 evaluate() 的只读快照 last_acc，不改任何字段。
# 键形态实测：source_dmg / source_heal / source_shield 的 key = 武器或符号的 source_id
# （如 "iron_sword"，无 source_id 时为符号资源路径）；value 为 float。
static func build_sources(last_acc: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if last_acc.is_empty():
		return out
	_append_source_rows(out, last_acc.get("source_dmg", {}), "damage", "点")
	_append_source_rows(out, last_acc.get("source_heal", {}), "heal", "点")
	_append_source_rows(out, last_acc.get("source_shield", {}), "shield", "点")

	# 牌谱追加的状态层（pattern_status），如 {"burn": 1} → 燃烧 +1 层。
	var pst = last_acc.get("pattern_status", {})
	if pst is Dictionary:
		for key in (pst as Dictionary):
			var n := int((pst as Dictionary)[key])
			if n <= 0:
				continue
			var sk := String(key)
			out.append({
				"kind": "status",
				"label": String(STATUS_LABELS.get(sk, sk)),
				"value": n,
				"unit": "层",
			})

	# 牌谱行：优先 pending_banners（形如 "<icon> <id> <名字>"），无 banner 时回退 lines。
	var seen: Array[String] = []
	for b in (last_acc.get("pending_banners", []) as Array):
		if not (b is Dictionary):
			continue
		var nm := _banner_pattern_name(String((b as Dictionary).get("text", "")))
		if nm != "" and not seen.has(nm):
			seen.append(nm)
			out.append({"kind": "pattern", "label": nm, "value": 1, "unit": "条"})
	if seen.is_empty():
		for line in (last_acc.get("lines", []) as Array):
			var nm2 := _line_pattern_name(String(line))
			if nm2 != "" and not seen.has(nm2):
				seen.append(nm2)
				out.append({"kind": "pattern", "label": nm2, "value": 1, "unit": "条"})
	return out


static func _append_source_rows(out: Array[Dictionary], by_source, kind: String, unit: String) -> void:
	if not (by_source is Dictionary):
		return
	for key in (by_source as Dictionary):
		var value := int(roundf(float((by_source as Dictionary)[key])))
		if value == 0:
			continue   # B5：不产生 "0 伤害" 这类噪声行
		out.append({
			"kind": kind,
			"label": _source_label(String(key)),
			"value": value,
			"unit": unit,
		})


# source_id 原文（"iron_sword"）或资源路径 → 短标签。
static func _source_label(key: String) -> String:
	var base := key.get_file().get_basename()
	return base if base != "" else key


# banner 形如 "<icon> <id> <name>[·signature]" → 取牌谱名（名字不含空格）。
static func _banner_pattern_name(text: String) -> String:
	var parts := text.strip_edges().split(" ", false)
	if parts.size() < 3:
		return ""
	var nm := String(parts[2]).strip_edges()
	var dot := nm.find("·")
	if dot >= 0:
		nm = nm.substr(0, dot)
	return nm


# lines 回退：只认「牌谱「name」」行，避免把伤害分解行误当牌谱。
static func _line_pattern_name(text: String) -> String:
	var t := text.strip_edges()
	if not t.contains("牌谱"):
		return ""
	var open := t.find("「")
	var close := t.find("」", open + 1)
	if open >= 0 and close > open:
		return t.substr(open + 1, close - open - 1)
	return ""


