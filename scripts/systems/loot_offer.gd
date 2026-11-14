class_name LootOffer
extends RefCounted

# 四级品质战利品 Step 4：同层三选一 + 冻结 payload。
#
# 职责：
#   - 一次定层：build 时按来源表抽一次品质，重抽（reroll）不再抽品质；
#   - 同层候选：只从该品质层取合法物品，跨类别（武器/护符/消耗品）混合；
#   - 三项有效：路径不重复、尽量不同 unique_group、至少覆盖两种用途；
#   - 不跨层补位：同层物品不足时用同层「转化 / 强化」补齐；
#   - 展示前冻结：物品与转化数值在 build 时写死；跳过固定为免费且无收益。
#
# 本类只负责生成与冻结；实际发奖（进槽/替换/腰带/金币/伤害）由 Step 5 接入来源时调用上层结算。
# 随机数全部来自 LootPool 的专用流，不消耗全局/地图 RNG。

const BALANCE = preload("res://resources/config/balance_config.tres")
const ITEM_CATEGORIES := ["weapon", "passive", "active"]

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
var _pool_paths: Array = []    # Step 8：本次同层合法候选顺序（换用途时从这里找替代）
var _chosen_paths := {}        # Step 8：已入选的 item 路径


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
	return LootSourceTable.quality_label(quality)


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
	_pool_paths = pool_paths.duplicate()

	# 贪心：优先不同 unique_group，其次不同路径；最多 3 项。
	var chosen: Array = []
	var seen := {}
	var groups := {}
	for p in pool_paths:
		if chosen.size() >= 3:
			break
		var g := _pool.group_of(p)
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
	_chosen_paths.clear()
	for p in chosen:
		options.append(_item_option(String(p)))
		_chosen_paths[String(p)] = true
	_ensure_two_roles()
	_last_paths = []
	for o in options:
		if String(o.get("kind", "")) == "item":
			_last_paths.append(String(o["path"]))
	_fill_conversions()
	skip = _make_skip()


# 三项至少两种用途；全同用途时优先换成池里另一种用途的真实物品，池内没有才退化为同层转化。
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
	# Step 8：先换真实物品（不因贪心连续抽到同用途而白送一次转化）。
	for p in _pool_paths:
		var path := String(p)
		if _chosen_paths.has(path):
			continue
		var res: Resource = _pool.resource_of(path)
		var role := String(res.get("role")) if res != null else ""
		if _purpose_of(res, role) == only:
			continue
		var last := options.size() - 1
		_chosen_paths.erase(String(options[last].get("path", "")))
		options[last] = _item_option(path)
		_chosen_paths[path] = true
		return
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
	var res: Resource = _pool.resource_of(path)
	var nm := _display_name(res, path)
	var role := String(res.get("role")) if res != null else ""
	var state := _grant_state(cat, path)
	var opt := {
		"kind": "item", "quality": quality, "quality_name": quality_name(), "category": cat,
		"path": path, "role": role, "purpose": _purpose_of(res, role),
		"unique_group": String(e.get("unique_group", "")),
		"icon": _icon_of(cat),
		"tooltip": _mechanism(res),
		"condition": "", "result": "", "mechanism": _mechanism(res),
		"grant": state,
		"gold": 0, "power": 0, "mastery": 0,
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
		opt["condition"] = "本局已拥有 / 槽位已满"
		opt["result"] = "金币 +%d" % g
	elif state == "mastery":
		var m := _duplicate_mastery()
		opt["mastery"] = m
		opt["title"] = "%s · 已拥有 → 熟练 +%d" % [nm, m]
		opt["desc"] = "本局已装备：转化为该武器熟练 +%d（R%d · %d/%d）" % [
			m, _mastery_rank(path), _mastery_points(path), _mastery_next(path)]
		opt["condition"] = "本局已装备（重复武器）"
		opt["result"] = "熟练 +%d（R%d · %d/%d）" % [
			m, _mastery_rank(path), _mastery_points(path), _mastery_next(path)]
	else:
		opt["title"] = "%s · %s" % [_category_label(cat), nm]
		opt["desc"] = _grant_desc(cat)
		opt["condition"] = _condition_text(cat)
		opt["result"] = _grant_desc(cat)
	opt["tooltip"] = _item_tooltip(res, opt)
	return opt


func _conversion_option(type: String) -> Dictionary:
	if type == "power":
		var p := int(BALANCE.loot_conversion_power.get(quality, 0))
		return {
			"kind": "conversion", "conversion": "power", "quality": quality,
			"quality_name": quality_name(),
			"role": "damage", "purpose": "damage", "icon": "⚔", "power": p, "gold": 0,
			"title": "同层强化 · 伤害 +%d" % p,
			"desc": "本局符号伤害 +%d（同品质转化，不跨层）" % p,
			"condition": "同层转化（无前置）", "result": "本局符号伤害 +%d" % p,
			"mechanism": "同层强化：本局所有符号伤害 +%d，不改变来源层。" % p,
			"tooltip": "同层强化：本局所有符号伤害 +%d。品质 %s，不改变来源层。" % [p, quality_name()],
		}
	var g := _conversion_gold()
	return {
		"kind": "conversion", "conversion": "gold", "quality": quality,
		"quality_name": quality_name(),
		"role": "resource", "purpose": "resource", "icon": "💰", "gold": g, "power": 0,
		"title": "同层转化 · 金币 +%d" % g,
		"desc": "金币 +%d（同品质转化，不跨层）" % g,
		"condition": "同层转化（无前置）", "result": "金币 +%d" % g,
		"mechanism": "同层转化：金币 +%d，不改变来源层。" % g,
		"tooltip": "同层转化：金币 +%d。品质 %s，不改变来源层。" % [g, quality_name()],
	}


func _make_skip() -> Dictionary:
	return {
		"kind": "skip", "quality": quality,
		"quality_name": quality_name(),
		"role": "resource", "purpose": "resource", "icon": "▶", "gold": 0, "power": 0,
		"title": "跳过 · 免费",
		"desc": "放弃本次战利品，不支付金币，也不获得物品或资源",
		"condition": "免费跳过", "result": "不获得战利品",
		"mechanism": "放弃本次战利品，无额外收益或费用。",
		"tooltip": "免费跳过本次战利品，不获得金币、强化或物品。",
	}


# ---------------------------------------------------------------------------
# 状态判定 / 文案
# ---------------------------------------------------------------------------

# 该物品在当前状态下的结算方式："item" 正常授予，"mastery" 重复武器转熟练，"gold" 重复/溢出转金币。
func _grant_state(cat: String, path: String) -> String:
	if _ctrl == null:
		return "item"
	match cat:
		"weapon":
			if _ctrl.selected_loadout.has(path):
				# Step 6：重复武器优先进入既有成长通道（熟练）；无熟练系统时才回落金币。
				return "mastery" if _ctrl.mastery != null else "gold"
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


func _duplicate_mastery() -> int:
	return int(BALANCE.loot_duplicate_mastery.get(quality, 0))


func _mastery_rank(path: String) -> int:
	return int(_ctrl.mastery.r_level(path)) if _ctrl != null and _ctrl.mastery != null else 1


func _mastery_points(path: String) -> int:
	if _ctrl == null or _ctrl.mastery == null:
		return 0
	return int(_ctrl.mastery.mastery.get(path, 0))


func _mastery_next(path: String) -> int:
	if _ctrl == null or _ctrl.mastery == null:
		return 0
	return int(_ctrl.mastery._next_threshold(_mastery_rank(path)))


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


# Step 7：卡面「条件」行——只描述当前槽位与获得方式，不制造品质对比。
func _condition_text(cat: String) -> String:
	if _ctrl == null:
		return "无前置"
	match cat:
		"weapon":
			var cap: int = int(_ctrl._loadout_system.cat_cap("weapon"))
			return "武器槽 %d/%d" % [_ctrl.selected_loadout.size(), cap]
		"passive":
			var pcap: int = int(_ctrl._loadout_system.cat_max("passive"))
			return "护符槽 %d/%d" % [_ctrl.selected_charms.size(), pcap]
		"active":
			return "腰带 %d/%d" % [_ctrl.consumable_slots.size(), _ctrl.CONSUMABLE_CAP]
	return "无前置"


# 悬停窗：机制 + 条件 + 结果三段齐全（卡面只放短句）。
func _item_tooltip(res: Resource, opt: Dictionary) -> String:
	var parts: Array[String] = []
	var mech := String(opt.get("mechanism", ""))
	if mech != "":
		parts.append(mech)
	parts.append("条件：%s" % String(opt.get("condition", "")))
	parts.append("结果：%s" % String(opt.get("result", "")))
	if res != null and bool(opt.get("needs_replace", false)):
		parts.append("武器槽已满：选择后进入替换流程（旧武器回收藏，熟练/铭印保留）。")
	return "\n".join(parts)


func _mechanism(res: Resource) -> String:
	if res == null:
		return ""
	var m := String(res.get("mechanism_summary"))
	if m != "":
		return m
	return String(res.get("description"))


func _result(ok: bool) -> Dictionary:
	return {"ok": ok, "reason": reason, "quality": quality,
		"quality_name": quality_name(), "source": source,
		"source_label": LootSourceTable.source_label(source),
		"options": options.duplicate(true), "skip": skip.duplicate(true)}
