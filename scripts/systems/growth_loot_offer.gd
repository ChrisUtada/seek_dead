extends "res://scripts/systems/loot_offer.gd"

# 普通/精英战后成长三选一：只强化当前 Build，不直接授予装备。
# 候选来自已装备武器、真实可增格符号和未拥有技艺；探索/商店/BOSS 继续使用物品池。


func _rebuild(avoid: Array) -> void:
	var candidates := _growth_candidates()
	var pool: Array = []
	for c in candidates:
		if not avoid.has(String(c["id"])):
			pool.append(c)
	if pool.size() < 3:
		pool = candidates.duplicate(true)
	_pool.shuffle_in_place(pool)
	options.clear()
	var seen := {}
	for c in pool:
		var kind := String(c["kind"])
		if seen.has(kind):
			continue
		seen[kind] = true
		options.append(c)
		if options.size() >= 3:
			break
	_fill_conversions()
	_inject_queued_growth()
	_last_paths = []
	for o in options:
		_last_paths.append(String(o.get("id", "")))
	skip = _make_skip()


func _inject_queued_growth() -> void:
	if _ctrl == null:
		return
	var cand: Dictionary = _ctrl._post_battle.build_growth(source)
	if cand.is_empty():
		return
	var idx := -1
	for i in range(options.size()):
		if String(options[i].get("kind", "")) == "perk":
			idx = i
			break
	if idx < 0:
		idx = 0
	options[idx] = _option("queued_growth", "queued_" + String(cand.get("growth_id", "growth")), "special", {
		"growth_entry": cand,
		"growth_id": String(cand.get("growth_id", "")),
		"title": String(cand.get("title", "待选成长")),
		"desc": String(cand.get("desc", "")),
		"result": "选择此项成长；其余未选成长随本次战利品放弃",
		"mechanism": String(cand.get("tooltip", cand.get("desc", ""))),
	})


func _growth_candidates() -> Array:
	var out: Array = []
	if _ctrl == null:
		return out
	for path in _ctrl.selected_loadout:
		var wd: WeaponData = load(path)
		if wd == null:
			continue
		var amount := _mastery_amount()
		out.append(_option("mastery", "mastery_" + String(path), "damage", {
			"path": String(path), "amount": amount,
			"title": "武器训练 · %s 熟练 +%d" % [wd.weapon_name, amount],
			"desc": "提升 %s 的熟练，达到门槛后解锁铭印" % wd.weapon_name,
			"result": "%s 熟练 +%d" % [wd.weapon_name, amount],
			"mechanism": "只强化当前已装备武器，不授予新武器。",
		}))
	var infusions: Array = _ctrl._reward_system.symbol_infusions()
	for entry in infusions:
		var sym: SymbolData = entry["sym"]
		var weight: int = _ctrl._reward_system._symbol_bonus_value()
		out.append(_option("symbol", "symbol_" + String(sym.resource_path), "damage", {
			"path": String(sym.resource_path), "weight": weight,
			"before": int(entry["before"]), "after": int(entry["after"]),
			"title": "符号灌注 · %s 权重 +%d" % [sym.name, weight],
			"desc": "转轮带 %d 格 → %d 格（本局生效）" % [int(entry["before"]), int(entry["after"])],
			"result": "%s %d格 → %d格" % [sym.name, int(entry["before"]), int(entry["after"])],
			"mechanism": "提升现有符号的出现频率，不添加新装备。",
		}))
	for p in _ctrl.growth._unowned_in(""):
		var view: Dictionary = _ctrl.growth._choice_view(p)
		out.append(_option("perk", "perk_" + String(p["id"]), "special", {
			"path": String(p["id"]), "perk_id": String(p["id"]),
			"title": "技艺 · %s" % String(view["name"]),
			"desc": String(view["desc"]),
			"result": "习得技艺「%s」" % String(view["name"]),
			"mechanism": "%s（%s）" % [String(view["desc"]), String(view["hint"])],
		}))
	out.append(_option("maxhp", "maxhp", "defense", {
		"amount": _maxhp_amount(),
		"title": "坚韧 · 最大 HP +%d" % _maxhp_amount(),
		"desc": "最大 HP 增加并恢复等量生命",
		"result": "最大 HP 与当前 HP +%d" % _maxhp_amount(),
		"mechanism": "提高本局生存能力，不改变装备。",
	}))
	out.append(_option("shield", "shield", "defense", {
		"amount": _shield_amount(),
		"title": "守望 · 下房护盾 +%d" % _shield_amount(),
		"desc": "进入下一场战斗时获得护盾",
		"result": "下房开局护盾 +%d" % _shield_amount(),
		"mechanism": "为下一场战斗提供防御准备。",
	}))
	if _ctrl.player_hp < _ctrl.player_hp_max:
		out.append(_option("heal", "heal", "defense", {
			"title": "休整 · 恢复 35% HP",
			"desc": "恢复当前最大 HP 的35%，不超过上限",
			"result": "恢复生命",
			"mechanism": "仅在当前未满血时出现。",
		}))
	return out


func _option(kind: String, id: String, purpose: String, data: Dictionary) -> Dictionary:
	var opt := {
		"kind": kind, "id": id, "quality": quality, "quality_name": quality_name(),
		"role": purpose, "purpose": purpose, "unique_group": kind,
		"icon": _purpose_icon(purpose), "path": "", "gold": 0, "power": 0,
		"condition": "当前 Build 成长", "tooltip": "",
	}
	opt.merge(data, true)
	opt["tooltip"] = "条件：当前 Build 成长\n结果：%s\n%s" % [String(opt["result"]), String(opt["mechanism"])]
	return opt


func _purpose_icon(purpose: String) -> String:
	match purpose:
		"damage": return "⚔"
		"defense": return "🛡"
		"special": return "✦"
	return "🎁"


func _mastery_amount() -> int:
	return int(BALANCE.loot_duplicate_mastery.get(quality, 1))


func _maxhp_amount() -> int:
	return {"common": 5, "uncommon": 8, "rare": 12, "epic": 16}.get(quality, 5)


func _shield_amount() -> int:
	return {"common": 8, "uncommon": 12, "rare": 18, "epic": 25}.get(quality, 8)
