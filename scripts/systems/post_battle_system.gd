# PostBattleSystem — M1 战后成长三槽（补给 / 构筑 / 成长）
#
# 运行时经 duel_controller preload 实例化（不注册全局 class_name——headless 测试环境不刷新类缓存）。
# 职责：
# - 普通 / 精英房胜利后，按槽位生成三张具体候选：补给、构筑、成长（成长位走队列）。
# - 成长位来自 GrowthSystem.pending_picks（技艺）与 WeaponMastery.owed（铭印），
#   按触发先后排队；候选在首次展示时冻结（id / 武器 / 符号），确认前不再随机。
# - 未选择的成长留在队列，进入下一战斗房的成长位；一次胜利最多选中一项。
# - 无待处理成长时，成长位给「下一房对策」（护盾 / 金币），保持槽位始终可用。
#
# 规格：docs/棋盘探索_战后成长与局外生涯_制作执行方案.md §4、§11 M1。
# 边界：不改伤害 / 成长数值 / 掉落 / 存档；奖励数据仍由 RewardSystem 生成与结算。

var _ctrl: DuelController

# 成长队列。元素：
#   {"kind":"perk", "id":String, "view":Dictionary}
#   {"kind":"imprint", "path":String, "id":String, "sym":String, "view":Dictionary}
var queue: Array = []


func _init(ctrl: DuelController) -> void:
	_ctrl = ctrl


func reset_run() -> void:
	queue.clear()


# 生成三槽候选（顺序固定：补给 / 构筑 / 成长），并同步 reward_choices 供既有奖励结算路径读取。
func build(kind: String) -> Array:
	_sync_queue()
	var rewards: Array = _ctrl._reward_system.roll_slot_rewards(kind)
	_ctrl.reward_choices = rewards
	_ctrl.reward_is_boss = false
	_ctrl.invalidate_state()
	var out: Array = []
	out.append(_reward_view(rewards, 0, "supply", "补给", "生存与资源"))
	out.append(_reward_view(rewards, 1, "build", "构筑", "武器与符号"))
	out.append(_growth_view(rewards))
	return out


# 应用成长位（技艺 / 铭印 / 下一房对策）。返回是否成功；失败时调用方应结束本次界面。
func apply_choice(cand: Dictionary) -> bool:
	var kind := String(cand.get("kind", ""))
	var ok := false
	match kind:
		"perk":
			var e: Dictionary = cand.get("entry", {})
			ok = _ctrl.growth.pick(String(e.get("id", "")))
			# 技艺由 GrowthSystem.pick 自己写记录，这里不重复
		"imprint":
			var e: Dictionary = cand.get("entry", {})
			# sym 为首次展示时冻结的调律目标；其余铭印忽略该参数。
			ok = _ctrl.mastery.choose(String(e.get("path", "")), String(e.get("id", "")), String(e.get("sym", "")))
			if ok:
				# 2026-11-08：成长位的铭印选择此前不进自动记录（只有技艺会记），补上
				var im_id := String(e.get("id", ""))
				var im_label := String(_ctrl.mastery.IMPRINT_NAMES.get(im_id, im_id))
				_ctrl._journal.note_growth("imprint", "铭印：%s ×%s" % [
					im_label, _ctrl.mastery.display_name(String(e.get("path", "")))])
		"fallback_shield":
			var n := int(cand.get("shield", 0))
			_ctrl._reward_system.run_shield_next += n
			_ctrl.hud._log("成长：进入下一房 +%d 护盾" % n)
			_ctrl.hud._popup("🛡下一房+%d" % n, Palette.POP_SHIELD, _ctrl.hud._player_sprite_anchor())
			ok = n > 0
			if ok:
				_ctrl._journal.note_growth("fallback_shield", "成长位：下一房护盾 +%d" % n)
		"fallback_gold":
			var g := int(cand.get("gold", 0))
			_ctrl.gold += g
			_ctrl.hud._log("成长：金币 +%d（共 %d）" % [g, _ctrl.gold])
			_ctrl.hud._popup("💰+%d" % g, Palette.POP_GOLD, _ctrl.hud._player_sprite_anchor())
			ok = g > 0
			if ok:
				_ctrl._journal.note_growth("fallback_gold", "成长位：金币 +%d" % g)
		"fallback_power":
			var p := int(cand.get("power", 0))
			_ctrl._reward_system.run_power_bonus += p
			_ctrl.hud._log("成长：本局符号伤害 +%d（当前 +%d）" % [p, _ctrl._reward_system.run_power_bonus])
			_ctrl.hud._popup("⚔伤害+%d" % p, Palette.POP_BUFF, _ctrl.hud._player_sprite_anchor())
			ok = p > 0
			if ok:
				_ctrl._journal.note_growth("fallback_power", "成长位：符号伤害 +%d" % p)
	if ok:
		var idx := int(cand.get("entry_index", -1))
		if idx >= 0 and idx < queue.size():
			queue.remove_at(idx)
		_ctrl.invalidate_state()
		_ctrl.hud._refresh_meta()
	return ok


# 失败兜底：丢掉队列中的这一项，避免同一张卡反复卡住界面。
func drop(cand: Dictionary) -> void:
	var idx := int(cand.get("entry_index", -1))
	if idx >= 0 and idx < queue.size():
		queue.remove_at(idx)


# ---------------------------------------------------------------------------
# 成长队列
# ---------------------------------------------------------------------------

# 与 GrowthSystem.pending_picks / WeaponMastery.owed 对齐：
# - 已选 / 已消耗 / 武器卸下的项移出；
# - 新触发的技艺先入队，再补本房新触发的铭印（与结算顺序一致：历练 → 熟练）。
func _sync_queue() -> void:
	var g = _ctrl.growth
	var m = _ctrl.mastery
	# 已卸下 / 没有有效候选的武器移出欠选，避免永久占位或展示死升级（沿用 M2-03 规则）。
	for path in m.owed.duplicate():
		if not _ctrl.selected_loadout.has(path) or m.imprint_choices(path).is_empty():
			m.owed.erase(path)
	var kept: Array = []
	var queued_perks := 0
	for e in queue:
		if String(e["kind"]) == "perk":
			if g.perk_ids.has(String(e["id"])):
				continue
			kept.append(e)
			queued_perks += 1
		else:
			if not m.owed.has(String(e["path"])) or not _ctrl.selected_loadout.has(String(e["path"])):
				continue
			kept.append(e)
	queue = kept
	while queued_perks < g.pending_picks:
		var e := _freeze_perk()
		if e.is_empty():
			break
		queue.append(e)
		queued_perks += 1
	var seen := {}
	for e in queue:
		if String(e["kind"]) == "imprint":
			seen[String(e["path"])] = true
	for path in m.owed:
		if seen.has(path) or not _ctrl.selected_loadout.has(path):
			continue
		var e := _freeze_imprint(path)
		if e.is_empty():
			continue
		queue.append(e)
		seen[path] = true


func _freeze_perk() -> Dictionary:
	var choices: Array = _ctrl.growth.roll_choices()
	if choices.is_empty():
		return {}
	var v: Dictionary = choices[randi() % choices.size()]
	var hint := String(v.get("hint", ""))
	var fam := String(v.get("family", ""))
	var tag := fam if hint == "" else "%s·%s" % [fam, hint]
	return {"kind": "perk", "id": String(v["id"]), "view": {
		"title": "技艺 · %s" % v["name"],
		"desc": "[%s] %s" % [tag, v["desc"]],
		"tooltip": "%s（%s）\n%s" % [v["name"], tag, v["desc"]],
		"icon": "✦",
	}}


func _freeze_imprint(path: String) -> Dictionary:
	var choices: Array = _ctrl.mastery.imprint_choices(path)
	if choices.is_empty():
		return {}
	# M1 成长位只给一张具体铭印卡：在锋铸 / 调律中随机取一项并冻结（不总是偏向某一类）。
	var v: Dictionary = choices[randi() % choices.size()]
	var e := {
		"kind": "imprint", "path": path, "id": String(v["id"]),
		"view": {
			"title": "铭印 · %s ×%s" % [v["name"], _ctrl.mastery.display_name(path)],
			"desc": "[%s] %s" % [String(v.get("hint", "")), String(v["desc"])],
			"tooltip": "%s ×%s（%s）\n%s" % [v["name"], _ctrl.mastery.display_name(path),
				String(v.get("hint", "")), String(v["desc"])],
			"icon": "⚒",
		},
	}
	if String(v["id"]) == "tune":
		e["sym"] = String(_ctrl.mastery.tune_target(path).get("sym", ""))
	return e


func _head() -> Dictionary:
	for i in range(queue.size()):
		var e: Dictionary = queue[i]
		if String(e["kind"]) == "perk":
			if _ctrl.growth.pending_picks > 0 and not _ctrl.growth.perk_ids.has(String(e["id"])):
				return {"entry": e, "index": i}
		else:
			if _ctrl.mastery.owed.has(String(e["path"])) and _ctrl.selected_loadout.has(String(e["path"])):
				return {"entry": e, "index": i}
	return {}


# ---------------------------------------------------------------------------
# 槽位视图
# ---------------------------------------------------------------------------

func _reward_view(rewards: Array, index: int, slot: String, label: String, hint: String) -> Dictionary:
	var rw: RewardData = rewards[index] if index < rewards.size() else null
	var pl: Dictionary = _ctrl._reward_system.payload_at(index)
	return {
		"slot": slot, "slot_label": label, "slot_hint": hint, "kind": "reward",
		"reward": rw, "index": index,
		"title": String(pl.get("title", rw.label if rw != null else "补给")),
		"desc": String(pl.get("desc", rw.desc if rw != null else "")),
		"icon": String(rw.icon) if rw != null else "🎁",
	}


func _growth_view(rewards: Array = []) -> Dictionary:
	var head: Dictionary = _head()
	if not head.is_empty():
		var e: Dictionary = head["entry"]
		var v: Dictionary = e["view"]
		return {
			"slot": "growth", "slot_label": "成长", "slot_hint": "路线与下一步",
			"kind": String(e["kind"]), "entry": e, "entry_index": int(head["index"]),
			"growth_id": String(e["id"]),
			"title": String(v["title"]), "desc": String(v["desc"]),
			"tooltip": String(v.get("tooltip", v["desc"])), "icon": String(v.get("icon", "✦")),
		}
	# 无待处理成长：给「下一房对策」（真实生效，不是伪选项）。
	# 避开本屏补给 / 构筑已占用的同义效果，避免三张卡出现两张护盾或两袋金币。
	var taken := {}
	for rw in rewards:
		if rw != null:
			taken[String(rw.id)] = true
	if _ctrl.has_next_battle():
		if not taken.has("shield") and not taken.has("elite_ward"):
			var rw: RewardData = _ctrl._reward_system.reward_by_id("shield")
			var n := int(rw.value) if rw != null else 8
			return {
				"slot": "growth", "slot_label": "成长", "slot_hint": "路线与下一步",
				"kind": "fallback_shield", "shield": n, "growth_id": "",
				"title": "下一房对策 · 护盾 +%d" % n,
				"desc": "进入下一房时获得 %d 护盾" % n,
				"tooltip": "本房没有待处理成长。选择后进入下一房时获得 %d 护盾，可与下一房开局护盾叠加。" % n,
				"icon": "🛡",
			}
		if not taken.has("gold") and not taken.has("elite_gold"):
			var g: RewardData = _ctrl._reward_system.reward_by_id("gold")
			var gn := int(g.value) if g != null else 15
			return {
				"slot": "growth", "slot_label": "成长", "slot_hint": "路线与下一步",
				"kind": "fallback_gold", "gold": gn, "growth_id": "",
				"title": "下一房对策 · 金币 +%d" % gn,
				"desc": "金币 +%d，用于下一房间歇" % gn,
				"tooltip": "本房没有待处理成长。选择后获得金币 +%d，用于下一房间歇的商店。" % gn,
				"icon": "💰",
			}
		var p: RewardData = _ctrl._reward_system.reward_by_id("power")
		var pn := int(p.value) if p != null else 1
		return {
			"slot": "growth", "slot_label": "成长", "slot_hint": "路线与下一步",
			"kind": "fallback_power", "power": pn, "growth_id": "",
			"title": "下一房对策 · 伤害 +%d" % pn,
			"desc": "本局符号伤害 +%d → +%d" % [_ctrl._reward_system.run_power_bonus,
				_ctrl._reward_system.run_power_bonus + pn],
			"tooltip": "本房没有待处理成长，且补给 / 构筑位已占用护盾与金币：改为本局符号伤害 +%d。" % pn,
			"icon": "⚔",
		}
	var g2: RewardData = _ctrl._reward_system.reward_by_id("gold")
	var gn2 := int(g2.value) if g2 != null else 10
	return {
		"slot": "growth", "slot_label": "成长", "slot_hint": "路线与下一步",
		"kind": "fallback_gold", "gold": gn2, "growth_id": "",
		"title": "远征补给 · 金币 +%d" % gn2,
		"desc": "金币 +%d（无下一房时的补给替代）" % gn2,
		"tooltip": "本房没有待处理成长，且已是最后一场战斗：折算为金币 +%d。" % gn2,
		"icon": "💰",
	}
