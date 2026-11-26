extends RefCounted

# ============================================================================
# PatternSystem —— 装备解锁集、牌谱优先级与补牌候选（2026-11-15，转轮凑牌 Step 1）
# 方案：docs/转轮凑牌战斗重构_24种牌型与制作执行方案_2026-11-15.md §3.4 / §9.2
#
# 规则：
#   - 通用牌型（G0x）每种每回合最多触发一次，可同时生效、加算不乘算；
#   - 装备牌谱每回合最多触发**一条**；
#   - 同时满足多条时按 priority 降序，同优先级按 id 升序 —— 禁止弹窗让玩家选；
#   - 连携卷轴已确定的牌谱优先于普通优先级（assist 固定优先，避免被吞）。
#
# Step 1 只落地「解锁集 + 优先级解析」的结构；S01–S20 的资源在 Step 2 实装。
# ============================================================================

const PATTERN_MATCHER = preload("res://scripts/battle/pattern_matcher.gd")

var _all: Array = []              # Array[PatternData]
var _by_id := {}


func register(pattern) -> void:
	if pattern == null or String(pattern.id) == "":
		return
	_all.append(pattern)
	_by_id[String(pattern.id)] = pattern


func all_patterns() -> Array:
	return _all


# T3 阶段 1：归档牌谱资源保留，但不进入目录、不参与匹配 / 解锁 / 补牌。
# 只在消费点过滤，注册表（all_patterns / by_track / get_pattern）仍可查询，
# 供图鉴标注「已归档」与测试核对资源存在。
static func is_archived(p) -> bool:
	return p != null and bool(p.get("archived"))


# 按轨取牌谱（weapon_public / weapon_attack / skill_support）。
func by_track(track: String) -> Array:
	var out: Array = []
	for p in _all:
		if String(p.track) == track:
			out.append(p)
	return out


func get_pattern(id: String):
	return _by_id.get(id, null)


# 当前构筑下可用的牌谱：通用牌型恒可用，装备牌谱按解锁条件。
# tag_of：Callable(path) -> Array[String]，用于按标签解锁（如 element:fire）。
func unlocked_patterns(loadout_paths: Array, tag_of: Callable) -> Array:
	var out: Array = []
	for p in _all:
		if is_archived(p):
			continue
		if bool(p.unlocked(loadout_paths, tag_of)):
			out.append(p)
	return out


# 按优先级排序：priority 降序 → id 升序（稳定、无随机、无弹窗）。
func sort_by_priority(patterns: Array) -> Array:
	var out: Array = patterns.duplicate()
	out.sort_custom(func(a, b):
		var pa := int(a.priority)
		var pb := int(b.priority)
		if pa != pb:
			return pa > pb
		return String(a.id) < String(b.id))
	return out


# 从命中的牌型里选出本回合真正生效的装备牌谱（至多一条）。
# matched_ids：PatternMatcher 命中的 id 列表。
# assist_id：连携卷轴已确定的牌谱 id（非空时优先）。
func resolve_equipment(matched_ids: Array, unlocked: Array, assist_id: String = "") -> Variant:
	if assist_id != "":
		for p in unlocked:
			if is_archived(p):
				continue
			if String(p.id) == assist_id and matched_ids.has(assist_id):
				return p
	var candidates: Array = []
	for p in unlocked:
		if is_archived(p) or bool(p.is_universal()):
			continue
		if matched_ids.has(String(p.id)):
			candidates.append(p)
	if candidates.is_empty():
		return null
	return sort_by_priority(candidates)[0]


# 通用牌型：不排序、不互斥，全部返回（各自每回合一次）。
func resolve_universal(matched_ids: Array, unlocked: Array) -> Array:
	var out: Array = []
	for p in unlocked:
		if bool(p.is_universal()) and matched_ids.has(String(p.id)):
			out.append(p)
	return out


# 查找某条基础牌谱的生效签名（2026-11-15 Step 5）。
# 2026-11-19 用户拍板：签名牌谱全部解锁，玩家通过武器与构筑自行触发，
# 取消"三选一习得"门槛——签名 = 那把专属武器的内置能力，和基础牌谱一样自动判定。
# 生效需两条件同时满足：
#   ① 携带专属武器（key_paths）——签名是"那把武器"的专属强化；
#   ② 签名自己的 match_rule 牌型满足。
# 历史变更：b9400af 曾移除 key_paths 检查；2026-11-19 恢复 key_paths、同时去掉 learned 门槛。
# 多条同时可用时取 priority 最高；同优先级按 id 升序，保证确定性。
func find_signature(base_id: String, loadout: Array, cards: Array) -> Variant:
	if base_id == "":
		return null
	var best = null
	for p in _all:
		if String(p.track) != "signature":
			continue
		# T3 阶段 1：归档签名即使绑定的武器被直接构造，也不参与匹配。
		if is_archived(p):
			continue
		if String(p.base_pattern_id) != base_id:
			continue
		# 条件②：必须携带专属武器（key_paths 任一在 loadout 中即算，与 PatternData.unlocked 同口径）。
		# 签名 = 那把武器的专属强化，不带它就不生效（2026-11-19 恢复）。
		var key_paths: Array = p.key_paths
		if not key_paths.is_empty():
			var has_key := false
			for kp in key_paths:
				if loadout.has(String(kp)):
					has_key = true
					break
			if not has_key:
				continue
		# 条件③：签名自己的牌型条件满足
		if not (p.match_rule as Dictionary).is_empty() \
				and not PATTERN_MATCHER.solve_rule(cards, p.match_rule):
			continue
		if best == null:
			best = p
			continue
		if int(p.priority) != int(best.priority):
			if int(p.priority) > int(best.priority):
				best = p
			continue
		# 同优先级：先比签名层级（epic > rare > 其它），再比 id 保证确定性。
		# 方案「传说品质不自动获得更高优先级」指的是不能凭品质压低别人的 priority，
		# 而同 priority 的 tiebreak 用层级是合理的——否则两把武器都带签名时，
		# 谁的 id 字典序靠前纯属偶然。
		var rp := _tier_rank(p)
		var rb := _tier_rank(best)
		if rp != rb:
			if rp > rb:
				best = p
		elif String(p.id) < String(best.id):
			best = p
	return best


static func _tier_rank(p) -> int:
	match String(p.pattern_tier):
		"mastery": return 3
		"epic_signature": return 2
		"rare_signature": return 1
	return 0


# 连携卷轴的候选：当前可用、可被补牌凑成、且尚未命中的装备牌谱。
func assist_candidates(unlocked: Array, matched_ids: Array) -> Array:
	var out: Array = []
	for p in unlocked:
		if is_archived(p) or bool(p.is_universal()) or not bool(p.assist_allowed):
			continue
		if not matched_ids.has(String(p.id)):
			out.append(p)
	return sort_by_priority(out)
