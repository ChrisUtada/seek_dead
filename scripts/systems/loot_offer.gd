class_name LootOffer
extends RefCounted

# 四级品质战利品 Step 4：同层三选一 + 冻结 payload。
#
# 职责：
#   - 一次定层：build 时按来源表抽一次品质，重抽（reroll）不再抽品质；
#   - 同层候选：只从该品质层取合法物品，跨类别（武器/护符/消耗品）混合；
#   - 三项有效：路径不重复、尽量不同 unique_group、至少覆盖两种用途；
#   - 不跨层补位：同层物品不足时用同层「转化 / 强化」补齐；
#   - 展示前冻结：物品、转化数值、跳过收益在 build 时写死，确认后不再随机。
#
# 本类只负责生成与冻结；实际发奖（进槽/替换/腰带/金币/伤害）由 Step 5 接入来源时调用上层结算。
# 随机数全部来自 LootPool 的专用流，不消耗全局/地图 RNG。

const BALANCE = preload("res://resources/config/balance_config.tres")
const ITEM_CATEGORIES := ["weapon", "passive", "active"]
const QUALITY_NAMES := {"common": "基础", "uncommon": "进阶", "rare": "稀有", "epic": "传说"}

var source := ""
var act := 1
var quality := ""
var options: Array[Dictionary] = []
var skip: Dictionary = {}
var reason := ""

var _ctrl                      # DuelController；可为 null（纯生成测试）
var _pool: LootPool
var _opts: Dictionary = {}
var _last_paths: Array = []


func _init(ctrl, pool: LootPool) -> void:
	_ctrl = ctrl
	_pool = pool


# 生成一组同层三选一。
# opts:
#   categories Array，默认 weapon/passive/active
#   theme      Array，主题白名单（BOSS）
#   exclude    Array，额外排除路径
# forced_quality 仅供测试/上层已定层时使用。
# 返回 {ok, reason, quality, options, skip}
func build(src: String, act_no: int, opts: Dictionary = {}, forced_quality: String = "") -> Dictionary:
	source = String(src)
	act = act_no
	_opts = opts.duplicate(true)
	quality = forced_quality
	if quality != "" and not (quality in LootSourceTable.QUALITIES):
		reason = "invalid_quality"
		options.clear()
		skip = {}
		return _result(false)
	if quality == "":
		quality = _pool.roll_quality(source, act)
	if quality == "":
		reason = "source_not_random:" + source
		options.clear()
		skip = {}
		_last_paths = []
		return _result(false)
	_last_paths = []
	_rebuild([])
	reason = ""
	return _result(true)


# 重抽：品质层不变，只换同层候选（优先避开上一组路径）。
func reroll() -> Dictionary:
	if quality == "":
		return _result(false)
	_rebuild(_last_paths)
	reason = ""
	return _result(true)


func payload_at(index: int) -> Dictionary:
	if index < 0 or index >= options.size():
		return {}
	return options[index].duplicate(true)


func skip_result() -> Dictionary:
	return skip.duplicate(true)


func quality_name() -> String:
	return String(QUALITY_NAMES.get(quality, quality))


# ---------------------------------------------------------------------------
# 生成
# ---------------------------------------------------------------------------

func _rebuild(avoid: Array) -> void:
	var opts := _opts.duplicate(true)
	var cats: Array = opts.get("categories", ITEM_CATEGORIES)
	opts.erase("categories")
	opts["category"] = cats
	if not opts.has("include_relics"):
		opts["include_relics"] = false
	var exclude: Array = opts.get("exclude", []).duplicate()
	for p in avoid:
		if not exclude.has(String(p)):
			exclude.append(String(p))
	opts["exclude"] = exclude

	var tier_res: Dictionary = _pool.tier_items(source, act, quality, opts)
	var paths: Array = tier_res.get("items", [])
	var pool_paths: Array = []
	for p in paths:
		if not avoid.has(String(p)):
			pool_paths.append(String(p))
	for p in paths:   # 避开后不足时补回上一组，保证同层可用
		if not pool_paths.has(String(p)):
			pool_paths.append(String(p))
	_pool.shuffle_in_place(pool_paths)

	# 贪心：优先不同 unique_group，其次不同路径；最多 3 项。
	var chosen: Array = []
	var seen := {}
	var groups := {}
	for p in pool_paths:
		if chosen.size() >= 3:
			break
		var g := String(_pool.entry_of(p).get("unique_group", ""))
		if g != "" and groups.has(g):
			continue
		chosen.append(p)
		seen[p] = true
		if g != "":
			groups[g] = true
	if chosen.size() < 3:
		for p in pool_paths:
			if chosen.size() >= 3:
				break
			if seen.has(p):
				continue
			chosen.append(p)
			seen[p] = true

	options.clear()
	for p in chosen:
		options.append(_item_option(String(p)))
	_last_paths = []
	for o in options:
		if String(o.get("kind", "")) == "item":
			_last_paths.append(String(o["path"]))
	_ensure_two_roles()
	_fill_conversions()
	skip = _make_skip()


# 三项至少两种用途；全同用途时把最后一项换成另一种同层转化。
# 用途口径：普通物品用 role；同为 damage 时按家族细分（火焰/冰霜/暗影…），避免三把同族换皮。
func _ensure_two_roles() -> void:
	if options.size() < 2:
		return
	var roles := {}
	for o in options:
		roles[String(o.get("purpose", ""))] = true
	if roles.size() >= 2:
		return
	var only := String(options[0].get("purpose", ""))
	options.remove_at(options.size() - 1)
	options.append(_conversion_option("power" if not only.begins_with("damage") else "gold"))


# 同层物品不足 3 项时，用同层转化/强化补齐（金币与伤害交替）。
func _fill_conversions() -> void:
	var used := {}
	for o in options:
		if String(o.get("kind", "")) == "conversion":
			used[String(o.get("conversion", ""))] = true
	var guard := 0
	while options.size() < 3:
		var t := ""
		for k in ["gold", "power"]:
			if not used.has(k):
				t = String(k)
				break
		if t == "":
			t = "gold"
		used[t] = true
		options.append(_conversion_option(t))
		guard += 1
		if guard > 8:
			break


func _item_option(path: String) -> Dictionary:
	var e := _pool.entry_of(path)
	var cat := String(e.get("kind", ""))
	var res: Resource = load(path)
	var nm := _display_name(res, path)
	var role := String(res.get("role")) if res != null else ""
	var state := _grant_state(cat, path)
	var opt := {
		"kind": "item", "quality": quality, "category": cat, "path": path,
		"role": role, "purpose": _purpose_of(res, role),
		"unique_group": String(e.get("unique_group", "")),
		"icon": _icon_of(cat),
		"tooltip": _mechanism(res),
		"grant": state,
		"gold": 0, "power": 0,
		"needs_replace": false,
	}
	if state == "item" and cat == "weapon" and _ctrl != null \
		and _ctrl.selected_loadout.size() >= _ctrl._loadout_system.cat_cap("weapon"):
		opt["needs_replace"] = true   # 展示前冻结：该候选必须走替换流程
	if state == "gold":
		var g := _conversion_gold()
		opt["gold"] = g
		opt["title"] = "%s · 已拥有 → 金币 +%d" % [nm, g]
		opt["desc"] = "本局已拥有 / 槽位已满：按同层转化结算金币 +%d" % g
	else:
		opt["title"] = "%s · %s" % [_category_label(cat), nm]
		opt["desc"] = _grant_desc(cat)
	return opt


func _conversion_option(type: String) -> Dictionary:
	if type == "power":
		var p := int(BALANCE.loot_conversion_power.get(quality, 0))
		return {
			"kind": "conversion", "conversion": "power", "quality": quality,
			"role": "damage", "purpose": "damage", "icon": "⚔", "power": p, "gold": 0,
			"title": "同层强化 · 伤害 +%d" % p,
			"desc": "本局符号伤害 +%d（同品质转化，不跨层）" % p,
			"tooltip": "同层强化：本局所有符号伤害 +%d。品质 %s，不改变来源层。" % [p, quality_name()],
		}
	var g := _conversion_gold()
	return {
		"kind": "conversion", "conversion": "gold", "quality": quality,
		"role": "resource", "purpose": "resource", "icon": "💰", "gold": g, "power": 0,
		"title": "同层转化 · 金币 +%d" % g,
		"desc": "金币 +%d（同品质转化，不跨层）" % g,
		"tooltip": "同层转化：金币 +%d。品质 %s，不改变来源层。" % [g, quality_name()],
	}


func _make_skip() -> Dictionary:
	var g := int(BALANCE.loot_skip_gold.get(quality, 0))
	return {
		"kind": "conversion", "conversion": "gold", "quality": quality,
		"role": "resource", "purpose": "resource", "icon": "💰", "gold": g, "power": 0,
		"title": "跳过 · 金币 +%d" % g,
		"desc": "不取战利品，直接获得同层转化金币 +%d" % g,
		"tooltip": "跳过本次战利品，获得 %s 层固定转化：金币 +%d（展示值即结算值）。" % [quality_name(), g],
	}


# ---------------------------------------------------------------------------
# 状态判定 / 文案
# ---------------------------------------------------------------------------

# 该物品在当前状态下的结算方式："item" 正常授予，"gold" 重复/溢出转金币。
func _grant_state(cat: String, path: String) -> String:
	if _ctrl == null:
		return "item"
	match cat:
		"weapon":
			if _ctrl.selected_loadout.has(path):
				return "gold"
		"passive":
			if _ctrl.selected_charms.has(path):
				return "gold"
			if _ctrl.selected_charms.size() >= _ctrl._loadout_system.cat_max("passive") \
				and not _ctrl._loadout_system.can_grow_slot("passive"):
				return "gold"
		"active":
			if _ctrl.consumable_slots.size() >= _ctrl.CONSUMABLE_CAP:
				return "gold"
	return "item"


func _conversion_gold() -> int:
	return int(BALANCE.loot_conversion_gold.get(quality, 0))


# 决策用途：damage 类按家族细分（火焰/冰霜/暗影…），其余直接用 role。
func _purpose_of(res: Resource, role: String) -> String:
	if role != "damage" or res == null:
		return role
	var fams: Variant = res.get("family_tags")
	if fams is Array and not (fams as Array).is_empty():
		return "damage:" + String((fams as Array)[0])
	return "damage"


func _display_name(res: Resource, path: String) -> String:
	if res == null:
		return path.get_file().get_basename()
	if res is WeaponData:
		return String(res.weapon_name)
	if res is SkillData:
		return String(res.buff_name)
	if res is ItemData:
		return String(res.item_name)
	return String(res.get("name"))


func _icon_of(cat: String) -> String:
	match cat:
		"weapon": return "⚔"
		"passive": return "🛡"
		"active": return "🧪"
	return "🎁"


func _category_label(cat: String) -> String:
	match cat:
		"weapon": return "武器"
		"passive": return "护符"
		"active": return "消耗品"
	return "战利品"


func _grant_desc(cat: String) -> String:
	match cat:
		"weapon": return "加入转轮带；武器槽满则替换"
		"passive": return "装配护符，占 1 个护符槽"
		"active": return "放入消耗品腰带"
	return "加入本局构筑"


func _mechanism(res: Resource) -> String:
	if res == null:
		return ""
	var m := String(res.get("mechanism_summary"))
	if m != "":
		return m
	return String(res.get("description"))


func _result(ok: bool) -> Dictionary:
	return {"ok": ok, "reason": reason, "quality": quality,
		"options": options.duplicate(true), "skip": skip.duplicate(true)}
