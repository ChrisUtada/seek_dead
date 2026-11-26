extends RefCounted

# ============================================================================
# PatternMatcher —— 纯牌型判定（2026-11-15，转轮凑牌 Step 1）
# 方案：docs/转轮凑牌战斗重构_24种牌型与制作执行方案_2026-11-15.md §9.2
#
# 边界：只读输入，不写任何战斗状态、不修改 grid、不碰 RNG。
# 输入是「最终三格」，不是结算累加器；调用方负责把结果喂给 CombatSystem。
#
# 与现有实现的对应关系（Step 1 验收要求两者结果一致）：
#   现有 combat_system.contribute 里
#     raw >= 3        → 同源三连（用该武器专精倍率）      ← 本类 triple_kind = "source"
#     combo_raw >= 3  → 同族三连（固定 ×1.5）             ← 本类 triple_kind = "family"
#   _phase_symbols 里
#     elem_total >= 3 → 元素共鸣（充能+1、本回合状态+1）  ← 本类 G03
# ============================================================================

# 不参与牌型的符号类型：MISS 与废铁同为 trash
const INVALID_KINDS := ["trash"]
# 通用牌型 id
const G_SOURCE := "G01"    # 同源刻
const G_FAMILY := "G02"    # 同族刻
const G_COLOR := "G03"     # 清一色


# cards: Array[Dictionary]，每项 {
#   "sym": SymbolData,      # 该格的符号（null 视为无效）
#   "element": String,      # 该格的有效元素（grid_elem）
#   "source": String,       # 产生该符号的来源 id（grid_src），空串 = 无来源
#   "valid": bool           # 可选；冻结列传 false
# }
# 返回 {
#   "ok": bool, "reason": String,
#   "valid_count": int,
#   "triple_kind": "source" | "family" | "",
#   "patterns": Array[Dictionary]   # 命中的通用牌型（G01/G02/G03，可同时命中）
# }
static func match(cards: Array) -> Dictionary:
	var out := {"ok": false, "reason": "", "valid_count": 0, "triple_kind": "", "patterns": []}
	var valid: Array = []
	for c in cards:
		if not bool(c.get("valid", true)):
			continue
		var sym = c.get("sym")
		if sym == null:
			continue
		if String(sym.kind) in INVALID_KINDS:
			continue
		valid.append(c)
	out["valid_count"] = valid.size()
	if valid.size() < 3:
		out["reason"] = "not_enough_valid"
		# 单牌/双牌：没有牌型，但不是错误
		out["ok"] = true
		return out
	# 只判前三张有效牌（本项目是固定三列）
	var a: Dictionary = valid[0]
	var fam_same := true
	var src_same := true
	var elem_same := true
	for i in range(1, 3):
		var c: Dictionary = valid[i]
		if String(c["sym"].resource_path) != String(a["sym"].resource_path) \
				or String(c.get("element", "none")) != String(a.get("element", "none")):
			fam_same = false
		if String(c.get("source", "")) != String(a.get("source", "")):
			src_same = false
		if String(c.get("element", "none")) != String(a.get("element", "none")):
			elem_same = false
	var src: String = String(a.get("source", ""))
	# 同源刻：三个同族符号且同一来源（来源必须非空，否则只是「同族」）
	if fam_same and src_same and src != "":
		out["triple_kind"] = "source"
		out["patterns"].append({"id": G_SOURCE, "name": "同源刻"})
	# 同族刻：三个同族符号、来源不限。同源时同样满足，但不额外叠加倍率
	# （同源已经在上面设了 triple_kind = "source"，这里只在没有更精确分类时降级为 family）。
	if fam_same:
		out["patterns"].append({"id": G_FAMILY, "name": "同族刻"})
		if String(out["triple_kind"]) == "":
			out["triple_kind"] = "family"
	# 清一色：三个有效牌同元素且非 none（与三连互不排斥）
	var elem: String = String(a.get("element", "none"))
	if elem_same and elem != "none":
		out["patterns"].append({"id": G_COLOR, "name": "清一色"})
	out["ok"] = true
	return out


# 按牌谱的 match_rule 求解：match_rule = {"all": [条件, ...]}，每个条件必须分配到
# 一张「未被其它条件占用」的有效牌。三张牌对三个条件，用回溯匹配即可（规模固定为 3）。
# 条件形式：
#   {"sym": "res://...tres"}      精确符号
#   {"element": "fire"}           指定元素的有效牌
#   {"any": true}                 任意有效牌
#   {"source": "武器路径"}        来自指定来源
#   {"symbol_category": "flame"}  符号类别（SymbolData.symbol_category，默认 none 不误命中）
# 条件值必须与 SymbolData.symbol_category 严格相等；"none" 是可匹配类别（命中未分类符号），
# 不是通配；已打标 blade/flame/frost/guard/projectile，arcane 尚未打标（写进来会永不命中）。
static func solve_rule(cards: Array, rule: Dictionary) -> bool:
	var conds: Array = rule.get("all", [])
	if conds.is_empty():
		return false
	var valid: Array = []
	for c in cards:
		if not bool(c.get("valid", true)):
			continue
		var sym = c.get("sym")
		if sym == null or String(sym.kind) in INVALID_KINDS:
			continue
		valid.append(c)
	if valid.size() < conds.size():
		return false
	return _solve(valid, conds, 0, {})


static func _solve(valid: Array, conds: Array, idx: int, used: Dictionary) -> bool:
	if idx >= conds.size():
		return true
	var cond: Dictionary = conds[idx]
	for i in range(valid.size()):
		if used.has(i):
			continue
		if not _card_satisfies(valid[i], cond):
			continue
		used[i] = true
		if _solve(valid, conds, idx + 1, used):
			return true
		used.erase(i)
	return false


static func _card_satisfies(card: Dictionary, cond: Dictionary) -> bool:
	if cond.has("sym") and String(card["sym"].resource_path) != String(cond["sym"]):
		return false
	if cond.has("element") and String(card.get("element", "none")) != String(cond["element"]):
		return false
	if cond.has("source") and String(card.get("source", "")) != String(cond["source"]):
		return false
	if cond.has("kind") and String(card["sym"].kind) != String(cond["kind"]):
		return false
	if cond.has("source_kind") and String(card.get("source_kind", "")) != String(cond["source_kind"]):
		return false
	if cond.has("source_element") and String(card.get("source_element", "none")) != String(cond["source_element"]):
		return false
	if cond.has("skill_role") and String(card.get("skill_role", "")) != String(cond["skill_role"]):
		return false
	if cond.has("symbol_category"):
		# T3-3 B 轮：类别相等才命中；sym 为空或未知类别不回退成「任意」。
		var sym_obj = card.get("sym")
		if sym_obj == null:
			return false
		var cat: String = ""
		if sym_obj is Dictionary:
			cat = String((sym_obj as Dictionary).get("symbol_category", "none"))
		else:
			cat = String(sym_obj.symbol_category)
		if cat != String(cond["symbol_category"]):
			return false
	return true


# 诊断一条 match_rule：哪些条件被满足、哪些没有（供常驻面板显示「缺什么」）。
# 用贪心分配：按条件顺序各取一张未占用的牌，与 solve_rule 的回溯结果可能略有差异，
# 但只在「无解」时才用于展示缺失项，不影响判定本身。
# 返回 {"done": bool, "satisfied": Array[int], "missing": Array[int]}
static func diagnose(cards: Array, rule: Dictionary) -> Dictionary:
	var conds: Array = rule.get("all", [])
	var out := {"done": false, "satisfied": [], "missing": []}
	if conds.is_empty():
		return out
	var valid: Array = []
	for c in cards:
		if not bool(c.get("valid", true)):
			continue
		var sym = c.get("sym")
		if sym == null or String(sym.kind) in INVALID_KINDS:
			continue
		valid.append(c)
	var used := {}
	for i in range(conds.size()):
		var cond: Dictionary = conds[i]
		var hit := false
		for j in range(valid.size()):
			if used.has(j):
				continue
			if _card_satisfies(valid[j], cond):
				used[j] = true
				hit = true
				break
		if hit:
			(out["satisfied"] as Array).append(i)
		else:
			(out["missing"] as Array).append(i)
	out["done"] = (out["missing"] as Array).is_empty()
	return out


# 把一条结构化条件翻成玩家看得懂的短标签（常驻面板用）。
static func describe_condition(cond: Dictionary) -> String:
	if cond.has("sym"):
		var path := String(cond["sym"])
		var res = load(path)
		if res != null and String(res.get("name")) != "":
			return String(res.get("name"))
		return path.get_file().get_basename()
	if cond.has("skill_role"):
		match String(cond["skill_role"]):
			"power": return "增伤技能"
			"shield": return "护盾技能"
			"heal": return "治疗技能"
		return "技能牌"
	if cond.has("source_kind") and String(cond["source_kind"]) == "skill":
		return "技能牌"
	if cond.has("kind") and String(cond["kind"]) == "shield":
		return "护盾牌"
	if cond.has("kind") and String(cond["kind"]) == "buff":
		return "增益牌"
	if cond.has("source_element"):
		var el := String(cond["source_element"])
		var label := ElementCounter.label(el) if el != "none" else "无"
		if cond.has("kind") and String(cond["kind"]) == "damage":
			return "%s系伤害" % label
		return "%s系武器牌" % label
	if cond.has("source_kind") and String(cond["source_kind"]) == "weapon":
		return "任意武器牌"
	return "任意牌"


# 返回命中 match_rule 的牌谱 id 列表（顺序与传入一致）。
static func match_rules(cards: Array, patterns: Array) -> Array:
	var out: Array = []
	for p in patterns:
		if bool(p.is_universal()):
			continue
		if solve_rule(cards, p.match_rule):
			out.append(String(p.id))
	return out


# 单格 → 牌卡元数据（T3-3 C 轮修正：预览与实盘共用同一构造口径）。
# sym 为符号资源，elem 为该格有效元素，src 为来源 id（武器 id / 空串）。
# source_kind/source_element/skill_role 由 ctrl 的来源元数据解析；valid 恒为 true，
# 冻结列由 cards_from_grid 按列覆盖（预览候选格不冻结）。
static func card_meta(ctrl, sym, elem: String, src: String) -> Dictionary:
	var entry := {
		"sym": sym,
		"element": String(elem),
		"source": String(src),
		"source_kind": "resource",
		"source_element": "none",
		"skill_role": "",
		"valid": true,
	}
	if sym != null:
		var sp := String(sym.resource_path)
		# T3-0A Q5：source 非空一律判 weapon，即使该符号也属于某个技能；
		# 仅 source 为空（技能位 / 精华位）才判 skill。
		if String(entry["source"]) == "" and ctrl != null and ctrl._skill_sym_kind != null \
				and ctrl._skill_sym_kind.has(sp):
			entry["source_kind"] = "skill"
			entry["source_element"] = String(ctrl._skill_sym_kind[sp])
			# 技能能力角色：三个术式各认一种，避免用「两张增益」这类凑不出的条件
			var b := String(sym.buff_effect)
			var k := String(sym.kind)
			if b == "power" or b == "damage_mult":
				entry["skill_role"] = "power"
			elif k == "shield" or b == "shield":
				entry["skill_role"] = "shield"
			elif k == "heal" or b == "regen":
				entry["skill_role"] = "heal"
		elif String(entry["source"]) != "" and ctrl != null and ctrl._source_element_map != null \
				and ctrl._source_element_map.has(String(entry["source"])):
			entry["source_kind"] = "weapon"
			entry["source_element"] = String(ctrl._source_element_map[String(entry["source"])])
	return entry


# 从 DuelController 的 grid 构造输入（供战斗与测试共用同一份口径）。
# 冻结列按「无效牌」处理：不参与牌型，与 combat_system 跳过 frozen_cols 一致。
static func cards_from_grid(ctrl, reel: int = 0) -> Array:
	var cards: Array = []
	var paylines: Array = ctrl.PAYLINES[0]
	for p in paylines:
		var col: int = int(p[0])
		var row: int = int(p[1])
		var sym = ctrl.grid[col][row]
		# 先取元素与来源，再判来源类别（顺序错了会永远判成 resource）
		var elem := "none"
		if ctrl.grid_elem.size() > col and ctrl.grid_elem[col].size() > row:
			elem = String(ctrl.grid_elem[col][row])
		var src := ""
		if ctrl.grid_src.size() > col and ctrl.grid_src[col].size() > row:
			src = String(ctrl.grid_src[col][row])
		var entry := card_meta(ctrl, sym, elem, src)
		entry["valid"] = not (col in ctrl.frozen_cols)
		cards.append(entry)
	return cards
