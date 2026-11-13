extends Node

# ============================================================================
# 四级品质战利品 · Step 7 · 信息展示与交互收口 · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/loot_ui_test.tscn
#
# 覆盖（docs/四级品质战利品与大奖池_分步执行计划_2026-11-12.md Step 7）：
# ① 四级品质名称 / 颜色 / 来源名统一（LootSourceTable + Palette 单一来源）；
# ② 480×270 下战利品三选一卡、按钮、数值都在容器内（卡片文本不裁切）；
# ③ 三项同层，卡面不带「更高品质」诱导；每项都有品质、机制、条件、结果文本；
# ④ 重抽只换同层候选：品质层与跳过金币不变，标题不变；
# ⑤ 查看 / 确认 / 跳过 / 替换 / 保留 都有明确状态，且只结算一次；
# ⑥ ESC（ui_cancel）不结算、不发奖；
# ⑦ 开关奖励屏与重抽不改变地图内容与战利品专用 RNG 种子；
# ⑧ BOSS 战利品卡同样带四级品质名与颜色。
# ============================================================================

const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const SCREEN_W := 480.0
const SCREEN_H := 270.0
const EPS := 0.5

var _checks := 0
var _fails := 0
var _duel: DuelController


func _ready() -> void:
	await _run()
	print("---")
	print("LOOTUI|RESULT %s (checks=%d fails=%d)"
		% ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	get_window().size = Vector2i(int(SCREEN_W), int(SCREEN_H))
	await _frames(2)
	var duel: DuelController = await _boot()
	if duel == null:
		print("LOOTUI|RESULT FAIL (boot)")
		get_tree().quit(2)
		return
	_duel = duel
	var meta_backup: Dictionary = duel.meta.duplicate(true)

	_test_quality_labels()
	await _test_loot_screen_layout()
	await _test_no_rarity_bait()
	await _test_reroll_keeps_quality()
	await _test_click_settles_once()
	await _test_skip_settles_once()
	await _test_esc_no_settle()
	await _test_replace_flow()
	await _test_growth_phase()
	_test_rng_isolation()
	_test_boss_quality_badge()

	duel.meta.clear()
	for k in meta_backup:
		duel.meta[k] = meta_backup[k]
	duel._meta_store.save_meta()


func _boot() -> DuelController:
	var scene_res: PackedScene = load(DUEL_SCENE)
	_duel = scene_res.instantiate() as DuelController
	add_child(_duel)
	await _frames(3)
	_duel._confirm_loadout()
	await _frames(3)
	return _duel


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


# ---------------------------------------------------------------------------
# ① 统一名称 / 颜色
# ---------------------------------------------------------------------------

func _test_quality_labels() -> void:
	_check(LootSourceTable.quality_label("common") == "基础", "common 显示「基础」")
	_check(LootSourceTable.quality_label("uncommon") == "进阶", "uncommon 显示「进阶」")
	_check(LootSourceTable.quality_label("rare") == "稀有", "rare 显示「稀有」")
	_check(LootSourceTable.quality_label("epic") == "传说", "epic 显示「传说」")
	_check(LootSourceTable.source_label("normal") == "普通战", "normal 来源名「普通战」")
	_check(LootSourceTable.source_label("elite") == "精英战", "elite 来源名「精英战」")
	_check(LootSourceTable.source_label("chest") == "探索宝箱", "chest 来源名「探索宝箱」")
	var colors := {}
	for q in LootSourceTable.QUALITIES:
		colors[Palette.quality_color(q)] = true
	_check(colors.size() == 4, "四级品质颜色互不相同（%d）" % colors.size())


# ---------------------------------------------------------------------------
# ②③ 版面与文案
# ---------------------------------------------------------------------------

func _fresh(kind: String = "normal") -> void:
	_duel.growth.reset_run()
	_duel.mastery.reset_run()
	_duel._post_battle.reset_run()
	_duel.player_hp_max = 100
	_duel.player_hp = 100
	_duel.turn_count = 1
	_duel.room_index = _room_index(kind)
	_duel.in_interroom = false
	_duel.hud.set_interroom_enabled(false)
	_duel.hud.hide_reward_screen()
	_duel.room_flow.reset_flow()


func _room_index(kind: String) -> int:
	for i in range(_duel.ROOMS.size()):
		if String(_duel.ROOMS[i].kind) == kind:
			return i
	return 0


func _begin() -> RewardScreen:
	_duel.room_flow.begin_post_battle()
	return _duel.hud.reward_screen


func _test_loot_screen_layout() -> void:
	_fresh()
	var r := _begin()
	await _frames(6)
	_check(r.visible, "战利品屏可见")
	_check(_in_screen(r), "战利品屏根节点在屏内")
	_check(r.title_label.text.find("战利品") >= 0, "标题写明战利品（%s）" % r.title_label.text)
	_check(r.title_label.text.find("普通战") >= 0, "标题写明来源（普通战）")
	_check(r.sub_label.text.find("同层三选一") >= 0, "副标题写明同层三选一")
	_check(r.reward_grid.get_child_count() == 3, "固定三张同层候选")
	_check(r._skip_btn.text.begins_with("跳过 · 金币 +"),
		"跳过按钮写明冻结金币（%s）" % r._skip_btn.text)
	_check(r._reroll_btn != null and r._reroll_btn.visible, "战利品阶段提供重抽")
	_check(_in_screen(r._skip_btn) and _in_screen(r._reroll_btn), "跳过 / 重抽按钮都在屏内")
	var view: Dictionary = _duel.room_flow.loot_view()
	var opts: Array = view.get("options", [])
	_check(opts.size() == 3, "冻结 payload 为 3 项")
	for i in range(opts.size()):
		var o: Dictionary = opts[i]
		_check(String(o.get("quality_name", "")) != "", "候选 %d 带品质名" % i)
		_check(String(o.get("mechanism", "")) != "", "候选 %d 带机制文本" % i)
		_check(String(o.get("condition", "")) != "", "候选 %d 带条件文本" % i)
		_check(String(o.get("result", "")) != "", "候选 %d 带结果文本" % i)
		_check(String(o.get("tooltip", "")).find("条件：") >= 0,
			"候选 %d 悬停窗含条件" % i)
		_check(String(o.get("tooltip", "")).find("结果：") >= 0,
			"候选 %d 悬停窗含结果" % i)
	# 卡片内容不越出卡片（480×270 固定分辨率）
	for i in range(r.reward_grid.get_child_count()):
		_check_card_content("战利品卡 %d" % i, r.reward_grid.get_child(i) as Button)
	var scroll: ScrollContainer = r.reward_grid.get_parent()
	_check(scroll != null, "战利品卡组在滚动容器内")
	if scroll != null:
		_check(r.reward_grid.get_combined_minimum_size().x <= scroll.size.x + EPS,
			"战利品卡组横向不溢出（min %.1f / 宽 %.1f）"
			% [r.reward_grid.get_combined_minimum_size().x, scroll.size.x])
	_duel.room_flow.skip_post_battle()


func _test_no_rarity_bait() -> void:
	_fresh()
	var r := _begin()
	await _frames(4)
	var view: Dictionary = _duel.room_flow.loot_view()
	var q := String(view.get("quality", ""))
	var all_same := true
	for o in view.get("options", []):
		if String((o as Dictionary).get("quality", "")) != q:
			all_same = false
	_check(all_same, "三项品质完全相同（%s）" % q)
	# 同层候选不得出现「更高品质」诱导字样或向上箭头
	var bait := false
	for i in range(r.reward_grid.get_child_count()):
		var card: Button = r.reward_grid.get_child(i) as Button
		if card == null:
			continue
		var txt := _card_text(card) + " " + String(card.tooltip_text)
		for word in ["更高品质", "升级品质", "↑品质", "推荐"]:
			if txt.find(word) >= 0:
				bait = true
	_check(not bait, "卡面不出现「更高品质 / 推荐」诱导")
	_duel.room_flow.skip_post_battle()


# ---------------------------------------------------------------------------
# ④ 重抽只换同层
# ---------------------------------------------------------------------------

func _test_reroll_keeps_quality() -> void:
	_fresh()
	var r := _begin()
	await _frames(4)
	var v0: Dictionary = _duel.room_flow.loot_view()
	var q0 := String(v0.get("quality", ""))
	var skip0 := int((v0.get("skip", {}) as Dictionary).get("gold", 0))
	var title0: String = r.title_label.text
	var paths0 := _paths(v0)
	var changed := false
	for i in range(6):
		_duel._on_loot_offer_reroll()
		await _frames(1)
		var v: Dictionary = _duel.room_flow.loot_view()
		_check(String(v.get("quality", "")) == q0, "重抽 %d 后品质层不变" % (i + 1))
		_check(int((v.get("skip", {}) as Dictionary).get("gold", 0)) == skip0,
			"重抽 %d 后跳过金币不变" % (i + 1))
		_check((v.get("options", []) as Array).size() == 3, "重抽 %d 后仍为三项" % (i + 1))
		if _paths(v) != paths0:
			changed = true
	_check(r.title_label.text == title0, "重抽不改标题")
	_check(r.reward_grid.get_child_count() == 3, "重抽后卡组仍是三张")
	_check(changed, "多次重抽确实换过同层候选")
	_duel.room_flow.skip_post_battle()


func _paths(view: Dictionary) -> Array:
	var out: Array = []
	for o in view.get("options", []):
		out.append(String((o as Dictionary).get("path", "")) + "|" + String((o as Dictionary).get("conversion", "")))
	return out


# ---------------------------------------------------------------------------
# ⑤ 只结算一次
# ---------------------------------------------------------------------------

func _pick_settleable(opts: Array) -> int:
	for i in range(opts.size()):
		if not bool((opts[i] as Dictionary).get("needs_replace", false)):
			return i
	return -1


func _test_click_settles_once() -> void:
	_fresh()
	# 留 1 个武器空位，保证至少有一项能直接授予
	if _duel.selected_loadout.size() >= 2:
		_duel.selected_loadout.resize(1)
		_duel._build_pool(_duel.selected_loadout)
	var r := _begin()
	await _frames(4)
	var opts: Array = _duel.room_flow.loot_view().get("options", [])
	var idx := _pick_settleable(opts)
	_check(idx >= 0, "存在可直接结算的候选")
	if idx < 0:
		_duel.room_flow.skip_post_battle()
		return
	var before := _snapshot()
	_duel._on_loot_offer_chosen(idx)
	var after1 := _snapshot()
	_check(before != after1, "第一次点击产生结算变化")
	# 第二次点击同一项：幂等拒绝，不再发奖
	_duel._on_loot_offer_chosen(idx)
	var after2 := _snapshot()
	_check(after1 == after2, "重复点击不二次发奖")
	var res: Dictionary = _duel._reward_system.settle_loot_offer(idx)
	_check(not bool(res.get("ok", false)) and String(res.get("reason", "")) == "already_settled",
		"直接重复结算返回 already_settled（%s）" % String(res.get("reason", "")))
	_check(after2 == _snapshot(), "已结算后再结算不改变状态")
	# 收尾
	if _duel.room_flow.post_battle_active:
		_duel._on_post_battle_defer()


func _snapshot() -> String:
	return "%d|%s|%s|%s" % [_duel.gold, str(_duel.selected_loadout), str(_duel.selected_charms),
		str(_duel.consumable_slots.size())]


func _test_skip_settles_once() -> void:
	_fresh()
	var r := _begin()
	await _frames(4)
	var skip_gold := int((_duel.room_flow.loot_view().get("skip", {}) as Dictionary).get("gold", 0))
	var g0 := int(_duel.gold)
	_duel._on_loot_offer_skip()
	# 收尾还会结算清房金币（与战利品无关），这里只断言「至少拿到冻结值」。
	_check(int(_duel.gold) - g0 >= skip_gold,
		"跳过至少获得冻结金币（+%d，期望 ≥%d）" % [int(_duel.gold) - g0, skip_gold])
	_check(_duel._reward_system._loot_settled, "跳过走同一套「已结算」标记")
	_check(not _duel.room_flow.post_battle_active, "跳过后面板收尾")
	var g1 := int(_duel.gold)
	_duel._on_loot_offer_skip()
	_check(int(_duel.gold) == g1, "再次跳过不二次发奖")
	_check(r.visible == false, "收尾后奖励屏已隐藏")


func _test_esc_no_settle() -> void:
	_fresh()
	var r := _begin()
	await _frames(4)
	var before := _snapshot()
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	r._unhandled_input(ev)
	_check(_snapshot() == before, "ESC 不结算、不发奖")
	_check(_duel.room_flow.post_battle_phase() == "loot", "ESC 后仍在战利品阶段")
	_check(r.visible, "ESC 不关闭战利品屏")
	_duel.room_flow.skip_post_battle()


# ---------------------------------------------------------------------------
# ⑤ 替换流程
# ---------------------------------------------------------------------------

func _test_replace_flow() -> void:
	_fresh()
	# 武器槽满：任一武器候选都必须走替换
	var cap: int = int(_duel._loadout_system.cat_cap("weapon"))
	while _duel.selected_loadout.size() < cap:
		var p := _first_unowned_weapon()
		if p == "":
			break
		_duel.selected_loadout.append(p)
	_duel._build_pool(_duel.selected_loadout)
	var view: Dictionary = _duel._reward_system.build_loot_offer(
		"normal", 1, {"categories": ["weapon"]}, "common")
	_duel.hud.show_loot_offer(view)
	_duel.room_flow.post_battle_active = true
	_duel.room_flow._phase = "loot"
	await _frames(3)
	var opts: Array = view.get("options", [])
	var idx := -1
	for i in range(opts.size()):
		if String((opts[i] as Dictionary).get("kind", "")) == "item" \
			and String((opts[i] as Dictionary).get("category", "")) == "weapon":
			idx = i
			break
	_check(idx >= 0, "构造出满槽武器候选")
	if idx < 0:
		_duel.room_flow.reset_flow()
		_duel.hud.hide_reward_screen()
		return
	_check(bool((opts[idx] as Dictionary).get("needs_replace", false)), "满槽武器候选冻结 needs_replace")
	var new_p := String((opts[idx] as Dictionary).get("path", ""))
	var old_p: String = _duel.selected_loadout[0]
	_duel._on_loot_offer_chosen(idx)
	_check(_duel.hud._replace_dialog != null and _duel.hud._replace_dialog.visible,
		"满槽点武器卡弹出替换弹层")
	_check(_duel.room_flow.post_battle_phase() == "loot", "替换弹层期间未结算")
	# 取消：不消耗结算机会
	_duel.hud._on_replace_cancelled()
	await _frames(1)
	_check(_duel.room_flow.post_battle_phase() == "loot", "取消替换后仍留在战利品阶段")
	_check(_duel.selected_loadout.has(old_p) and not _duel.selected_loadout.has(new_p),
		"取消替换不改配装")
	# 再次点卡 → 选旧武器 → 结算一次
	_duel._on_loot_offer_chosen(idx)
	_duel.hud._on_replace_chosen(old_p)
	_check(not _duel.selected_loadout.has(old_p), "替换后旧武器移出配装")
	_check(_duel.selected_loadout.has(new_p), "替换后新武器进入配装")
	var res: Dictionary = _duel._reward_system.settle_loot_replace(idx, old_p)
	_check(not bool(res.get("ok", false)) and String(res.get("reason", "")) == "already_settled",
		"替换结算同样只发一次（%s）" % String(res.get("reason", "")))
	_duel.room_flow.reset_flow()
	_duel.hud.hide_reward_screen()


func _first_unowned_weapon() -> String:
	for p in _duel.ITEM_POOL:
		var s := String(p)
		if s.get_file().contains("_relic"):
			continue
		var d: Resource = load(s)
		if d is WeaponData and not _duel.selected_loadout.has(s):
			return s
	return ""


# ---------------------------------------------------------------------------
# ⑤ 成长阶段
# ---------------------------------------------------------------------------

func _test_growth_phase() -> void:
	_fresh()
	_duel.growth.xp = 2
	var r := _begin()
	await _frames(4)
	_check(_duel.room_flow.post_battle_has_growth(), "本房有真实成长")
	_check(String(_duel.room_flow.post_battle_growth_candidate().get("kind", "")) == "perk",
		"成长队列为技艺")
	# 先结算战利品 → 成长阶段
	var opts: Array = _duel.room_flow.loot_view().get("options", [])
	var idx := _pick_settleable(opts)
	if idx >= 0:
		_duel._on_loot_offer_chosen(idx)
	else:
		_duel._on_loot_offer_skip()
	_check(_duel.room_flow.post_battle_phase() == "growth", "战利品结算后进入成长阶段")
	_check(r.title_label.text.begins_with("成长 ·"), "成长阶段标题正确（%s）" % r.title_label.text)
	_check(r.reward_grid.get_child_count() == 1, "成长阶段只展示真实成长卡")
	_check(not r._reroll_btn.visible, "成长阶段不提供重抽")
	_check(r._skip_btn.text == "保留到下次战斗", "成长阶段按钮写明保留")
	# ESC = 保留（不发放）
	var ev := InputEventAction.new()
	ev.action = "ui_cancel"
	ev.pressed = true
	r._unhandled_input(ev)
	_check(_duel.growth.pending_picks == 1, "ESC 保留成长，待选不清零")
	_check(not _duel.room_flow.post_battle_active, "保留后收尾")
	# 再来一次：这次真的选成长
	_fresh()
	_duel.growth.xp = 2
	_begin()
	await _frames(3)
	var opts2: Array = _duel.room_flow.loot_view().get("options", [])
	var idx2 := _pick_settleable(opts2)
	if idx2 >= 0:
		_duel._on_loot_offer_chosen(idx2)
	else:
		_duel._on_loot_offer_skip()
	_check(_duel.room_flow.post_battle_phase() == "growth", "第二次进入成长阶段")
	_duel._on_post_battle_growth_chosen(_duel.room_flow.post_battle_growth_candidate())
	_check(_duel.growth.perk_ids.size() == 1 and _duel.growth.pending_picks == 0,
		"选择成长后技艺入列、待选清零")


# ---------------------------------------------------------------------------
# ⑦ RNG / 地图隔离
# ---------------------------------------------------------------------------

func _test_rng_isolation() -> void:
	_fresh()
	var seed0: int = int(_duel._reward_system._loot.seed_value())
	var rooms0 := _rooms_signature()
	var board0 := _board_signature()
	_duel.room_flow.begin_post_battle()
	_duel._on_loot_offer_reroll()
	_duel._on_loot_offer_reroll()
	_duel.hud.hide_reward_screen()
	_duel.room_flow.reset_flow()
	_check(int(_duel._reward_system._loot.seed_value()) == seed0, "开关奖励屏不改战利品 RNG 种子")
	_check(_rooms_signature() == rooms0, "开关奖励屏不改房间表")
	_check(_board_signature() == board0, "开关奖励屏不改棋盘内容")


func _rooms_signature() -> String:
	var bits: Array[String] = []
	for r in _duel.ROOMS:
		bits.append("%s:%d" % [String(r.kind), int(r.act)])
	return ",".join(bits)


func _board_signature() -> String:
	if _duel.board == null:
		return "no_board"
	var bits: Array[String] = []
	for n in _duel.board.nodes:
		bits.append(str(n))
	return "|".join(bits)


# ---------------------------------------------------------------------------
# ⑧ BOSS 卡品质角标
# ---------------------------------------------------------------------------

func _test_boss_quality_badge() -> void:
	var rooms: Array = []
	for r in _duel.ALL_ROOMS:
		if String(r.kind) == "boss" and not r.final_boss:
			rooms.append(r)
	_check(not rooms.is_empty(), "找到非最终 BOSS 房")
	var saw_weapon := false
	var saw_quality := false
	for room in rooms:
		for c in _duel._reward_system.roll_boss_rewards(room):
			var cd: Dictionary = c
			if String(cd.get("kind", "")) != "boss_weapon":
				continue
			saw_weapon = true
			if String(cd.get("quality", "")) == "":
				continue
			saw_quality = true
			var card: Button = _duel.hud._make_boss_reward_card(cd)
			_check(_card_text(card).find("【") >= 0,
				"BOSS 战利品卡带品质角标（%s）" % _card_text(card))
			card.queue_free()
			break
		if saw_quality:
			break
	_check(saw_weapon, "BOSS 战利品出现武器候选")
	_check(saw_quality, "BOSS 武器候选带品质字段")


# ---------------------------------------------------------------------------
# 通用检查（与 g8_screens_layout_test 同一口径）
# ---------------------------------------------------------------------------

func _in_screen(c: Control) -> bool:
	if c == null:
		return false
	var r: Rect2 = c.get_global_rect()
	return r.position.x >= -EPS and r.position.y >= -EPS \
		and r.position.x + r.size.x <= SCREEN_W + EPS \
		and r.position.y + r.size.y <= SCREEN_H + EPS


# ItemCard 的可见文本在子 Label 里（Button.text 为空），检查文案时统一取这三行。
func _card_text(btn: Button) -> String:
	var parts: Array[String] = []
	for p in ["Center/VBox/TitleLabel", "Center/VBox/DescLabel", "Center/VBox/StatusLabel"]:
		var l := btn.get_node_or_null(p) as Label
		if l != null and l.visible:
			parts.append(String(l.text))
	return " ".join(parts)


func _check_card_content(what: String, btn: Button) -> void:
	if btn == null or not (btn is ItemCard):
		_check(false, "%s 是 ItemCard" % what)
		return
	var vb: Control = btn.get_node("Center/VBox")
	var vmin: Vector2 = vb.get_combined_minimum_size()
	_check(vmin.x <= btn.size.x + EPS,
		"%s 内容横向够（min %.1f / avail %.1f）" % [what, vmin.x, btn.size.x])
	_check(vmin.y <= btn.size.y + EPS,
		"%s 内容纵向够（min %.1f / avail %.1f）" % [what, vmin.y, btn.size.y])
