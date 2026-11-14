extends Node

# ============================================================================
# G8-05 商店 / 奖励 / 铁砧+图鉴 / 局末 排版回归（2026-11-09）
# 目的：延续 G8-04（整备屏）做法，用真实节点尺寸把四个覆盖屏的排版条件锁住：
#   1. 覆盖屏根节点不超出 480x270 逻辑分辨率；
#   2. 标签文本不横向溢出（Label 不裁切，宽度不够会压到邻居/屏外）；
#   3. 卡片网格 / 列表的合成最小宽度不超过容器（横向不溢出），纵向超长可滚动；
#   4. 底部按钮行不越界；
#   5. 图鉴面板（铁砧屏内）列表 + 详情横向不溢出，内容可滚动。
# 运行：
#   Godot_v4.7-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/g8_screens_layout_test.tscn
# 会实例化 duel（可能写存档）：用隔离 APPDATA 运行（run_smoke.bat 已统一隔离）。
# ============================================================================

const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const SCREEN_W := 480.0
const SCREEN_H := 270.0
const EPS := 0.5

var _pass := 0
var _fail := 0
var _duel: DuelController


func _ready() -> void:
	await _run()


func _run() -> void:
	get_window().size = Vector2i(int(SCREEN_W), int(SCREEN_H))
	await _frames(2)

	var scene_res: PackedScene = load(DUEL_SCENE)
	_duel = scene_res.instantiate() as DuelController
	add_child(_duel)
	await _frames(3)
	_duel._confirm_loadout()
	await _frames(4)

	var meta_backup: Dictionary = _duel.meta.duplicate(true)

	await _test_shop()
	await _test_reward()
	await _test_anvil()
	await _test_meta()

	_duel.meta.clear()
	for k in meta_backup:
		_duel.meta[k] = meta_backup[k]
	_duel._meta_store.save_meta()

	print("G8_SCREENS|RESULT %s (%d/%d)" % ["PASS" if _fail == 0 else "FAIL", _pass, _pass + _fail])
	get_tree().quit(0 if _fail == 0 else 1)


# --- 商店 ---------------------------------------------------------------

func _test_shop() -> void:
	_duel._shop_system.roll_shop()
	_duel.hud._show_shop_screen()
	await _frames(24)   # 等滑入补间结束（0.22s ≈ 14 帧，留余量）再量尺寸
	var s: ShopScreen = _duel.hud.shop_screen
	_check(s.visible, "商店屏可见")
	_check_in_screen("商店根节点", s)
	_check_label_fits("商店标题", s.title_label)
	_check_label_fits("商店金币行", s.gold_label)

	var content: Control = s.title_label.get_parent()
	var content_w: float = content.size.x

	# 页签：两个按钮不越出内容宽度
	_check(s.shop_tab_buy_btn.size.x + s.shop_tab_sell_btn.size.x
		+ 4.0 <= content_w + EPS, "商店页签不横向溢出")

	# 购入页：3 列卡片网格
	s.show_tab("buy")
	await _frames(4)
	_check(s.shop_grid.get_child_count() > 0, "购入货架有卡片（%d）" % s.shop_grid.get_child_count())
	_check_grid_fits("购入货架", s.shop_grid)

	# 货架卡片：文本不裁切（与整备卡同一卡工厂，但商店卡有自己的构造器）
	for i in range(s.shop_grid.get_child_count()):
		_check_card_content("购入卡 %d" % i, s.shop_grid.get_child(i) as Button)

	# 卖出页：4 列列表（G8-05：列表放进滚动容器，避免技能/护符变多后底部不可达）
	s.show_tab("sell")
	await _frames(4)
	var box: HBoxContainer = s.weapon_list.get_parent()
	_check(box.get_combined_minimum_size().x <= box.size.x + EPS,
		"卖出四列不横向溢出（min %.1f / 宽 %.1f）" % [box.get_combined_minimum_size().x, box.size.x])
	var sell_scroll: ScrollContainer = box.get_parent() as ScrollContainer
	_check(sell_scroll != null, "卖出列表在滚动容器内")
	for list in [s.weapon_list, s.skill_list, s.charm_list, s.consum_list]:
		for c in list.get_children():
			if c is Button:
				_check_card_content("卖出卡（%s）" % list.name, c as Button)

	# 卖出内容变多：技能 10 条 → 列表可滚动，卡片内容不越出卡片
	var skill_backup: Array = _duel.selected_skills.duplicate()
	_duel.selected_skills.assign(_duel.SKILL_POOL)
	s.refresh()
	await _frames(6)
	_check(s.skill_list.get_child_count() >= 10, "满技能时卖出列表有 %d 条" % s.skill_list.get_child_count())
	if sell_scroll != null:
		_check(sell_scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED,
			"卖出列表可纵向滚动")
	for c in s.skill_list.get_children():
		if c is Button:
			_check_card_content("技能卖出卡", c as Button)
	_duel.selected_skills.assign(skill_backup)
	s.refresh()
	await _frames(4)

	# 底栏：刷新 + 关闭按钮不越界
	s.show_tab("buy")
	await _frames(3)
	var bot: HBoxContainer = s.reroll_btn.get_parent()
	_check(bot.get_combined_minimum_size().x <= bot.size.x + EPS,
		"商店底栏不横向溢出（min %.1f / 宽 %.1f）" % [bot.get_combined_minimum_size().x, bot.size.x])
	_check_in_screen("商店刷新按钮", s.reroll_btn)
	_check_in_screen("商店关闭按钮", s.leave_btn)

	# 快速关→开：旧滑出补间的隐藏回调不能把刚展开的抽屉关掉（G8-05 修复的补间竞争）
	_duel.hud.hide_shop_screen()
	await _frames(2)
	_duel.hud._show_shop_screen()
	await _frames(18)
	_check(s.visible, "快速关→开后商店仍可见（旧补间已终止）")

	_duel.hud.hide_shop_screen()
	await _frames(12)


# --- 奖励（战后同层三选一 + BOSS 战利品） -------------------------------

func _test_reward() -> void:
	_duel.growth.reset_run()
	_duel.mastery.reset_run()
	_duel._post_battle.reset_run()
	_duel.player_hp_max = 100
	_duel.player_hp = 100
	_duel.turn_count = 1
	_duel.room_index = _normal_room_index()
	_duel.in_interroom = false
	_duel.hud.set_interroom_enabled(false)
	_duel.growth.xp = 2
	_duel.room_flow.begin_post_battle()
	await _frames(6)

	var r: RewardScreen = _duel.hud.reward_screen
	_check(r.visible, "战利品屏可见")
	_check_in_screen("奖励屏根节点", r)
	var dialog: PanelContainer = r.title_label.get_parent().get_parent().get_parent()
	_check_in_screen("奖励对话框", dialog)
	_check_label_fits("奖励屏标题", r.title_label)
	_check_label_fits("奖励屏副标题", r.sub_label)
	_check(r.sub_label.autowrap_mode != TextServer.AUTOWRAP_OFF, "奖励副标题开启自动换行")
	_check(r.title_label.text.find("成长") >= 0, "成长屏标题正确（%s）" % r.title_label.text)
	_check(r.sub_label.text.find("成长三选一") >= 0, "成长屏副标题说明成长三选一")
	_check(r.reward_grid.get_child_count() == 3, "战后战利品固定三张卡（%d）" % r.reward_grid.get_child_count())
	_check_grid_fits("战后战利品卡组", r.reward_grid)
	# 卡片内容：文本不裁切 + 高度够
	for i in range(r.reward_grid.get_child_count()):
		_check_card_content("战后战利品卡 %d" % i, r.reward_grid.get_child(i) as Button)
	_check(r._skip_btn != null, "奖励屏有跳过按钮")
	if r._skip_btn != null:
		_check_in_screen("奖励跳过按钮", r._skip_btn)
		_check(r._skip_btn.text.length() > 0, "跳过按钮有文案")
	# Step 7：重抽按钮在战利品阶段可见，且不越界。
	_check(r._reroll_btn != null and r._reroll_btn.visible, "战利品屏有重抽按钮")
	if r._reroll_btn != null:
		_check_in_screen("奖励重抽按钮", r._reroll_btn)
	# 纵向：内容超出时滚动可用（或内容本来够小）
	var scroll: ScrollContainer = r.reward_grid.get_parent()
	_check(scroll != null, "奖励卡组在滚动容器内")
	if scroll != null:
		var min_size: Vector2 = r.reward_grid.get_combined_minimum_size()
		_check(min_size.y <= scroll.size.y + EPS
			or scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED,
			"奖励卡组纵向可达（min %.1f / 视口 %.1f）" % [min_size.y, scroll.size.y])

	# BOSS 战利品屏（走 show_screen(true) 真实路径）
	_duel.hud.hide_reward_screen()
	await _frames(3)
	var boss_idx := -1
	for i in range(_duel.ROOMS.size()):
		if _duel.ROOMS[i].kind == "boss":
			boss_idx = i
			break
	if boss_idx >= 0:
		_duel.room_index = boss_idx
		_duel.hud._show_reward_screen(true)
		await _frames(6)
		_check(r.visible, "BOSS 战利品屏可见")
		_check(r.title_label.text.find("BOSS") >= 0, "BOSS 战利品屏标题正确")
		_check_checklist_grid("BOSS 战利品卡组", r.reward_grid)
		for i in range(r.reward_grid.get_child_count()):
			_check_card_content("BOSS 战利品卡 %d" % i, r.reward_grid.get_child(i) as Button)
		var scroll2: ScrollContainer = r.reward_grid.get_parent()
		if scroll2 != null:
			_check(r.reward_grid.get_combined_minimum_size().x <= scroll2.size.x + EPS,
				"BOSS 战利品卡组横向不溢出")
		_duel.hud.hide_reward_screen()
	await _frames(3)


# --- 铁砧 + 图鉴 --------------------------------------------------------

func _test_anvil() -> void:
	_duel.hud._show_anvil_screen()
	await _frames(6)
	var a: AnvilScreen = _duel.hud.anvil_screen
	_check(a.visible, "铁砧屏可见")
	_check_in_screen("铁砧屏根节点", a)
	_check_label_fits("铁砧标题", a.title_label)
	_check_label_fits("铁砧点数行", a.points_label)
	_check_label_fits("铁砧副标题", a.sub_label)
	_check_label_fits("铁砧图鉴信息行", a.info_label)
	var content: Control = a.title_label.get_parent()
	_check(a.roll_btn.size.x + a.back_btn.size.x <= content.size.x + EPS, "铁砧底部按钮不横向溢出")
	_check_in_screen("铁砧摇动按钮", a.roll_btn)
	_check_in_screen("铁砧返回按钮", a.back_btn)
	# 三连格子：横向排布不越界
	_check(a.reel_box.get_combined_minimum_size().x <= content.size.x + EPS,
		"铁砧三连格不横向溢出（min %.1f / 宽 %.1f）" % [
			a.reel_box.get_combined_minimum_size().x, content.size.x])

	# 图鉴面板（G6-04，运行时构建）
	a._toggle_codex()
	await _frames(6)
	_check(a._codex_panel != null and a._codex_panel.visible, "图鉴面板可打开")
	_check_in_screen("图鉴面板", a._codex_panel)
	var list_scroll: ScrollContainer = a._codex_list.get_parent()
	var detail_scroll: ScrollContainer = a._codex_detail.get_parent()
	_check(list_scroll != null and detail_scroll != null, "图鉴列表/详情在滚动容器内")
	if list_scroll != null and detail_scroll != null:
		var row: HBoxContainer = list_scroll.get_parent() as HBoxContainer
		if row != null:
			_check(row.get_combined_minimum_size().x <= row.size.x + EPS,
				"图鉴列表+详情横向不溢出（min %.1f / 宽 %.1f）" % [
					row.get_combined_minimum_size().x, row.size.x])
		var list_min: Vector2 = a._codex_list.get_combined_minimum_size()
		_check(list_min.y <= list_scroll.size.y + EPS
			or list_scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED,
			"图鉴列表纵向可达（min %.1f / 视口 %.1f）" % [list_min.y, list_scroll.size.y])
		var detail_min: Vector2 = a._codex_detail.get_combined_minimum_size()
		_check(detail_min.y <= detail_scroll.size.y + EPS
			or detail_scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED,
			"图鉴详情纵向可达（min %.1f / 视口 %.1f）" % [detail_min.y, detail_scroll.size.y])
	# 图鉴详情标签不横向溢出
	for c in a._codex_detail.get_children():
		if c is Label:
			_check_label_fits("图鉴详情行", c as Label)
	a._toggle_codex()
	await _frames(3)
	_duel.hud.hide_anvil_screen()
	await _frames(3)


# --- 局末 ---------------------------------------------------------------

func _test_meta() -> void:
	if _duel._career != null:
		_duel._career._unlock_charges = 0
	_duel.hud._show_meta_choice()
	await _frames(6)
	var m: MetaScreen = _duel.hud.meta_screen
	_check(m.visible, "局末屏可见")
	_check_in_screen("局末屏根节点", m)
	_check_label_fits("局末标题", m.title_label)
	_check_label_fits("局末副标题", m.sub_label)
	_check(m.sub_label.autowrap_mode != TextServer.AUTOWRAP_OFF, "局末副标题开启自动换行")
	var center: Control = m.meta_grid.get_parent()
	_check(m.meta_grid.get_combined_minimum_size().x <= m.size.x + EPS,
		"局末卡组横向不溢出（min %.1f / 屏宽 %.1f）" % [
			m.meta_grid.get_combined_minimum_size().x, m.size.x])
	_check_grid_fits("局末卡组", m.meta_grid)
	for i in range(m.meta_grid.get_child_count()):
		_check_card_content("局末卡 %d" % i, m.meta_grid.get_child(i) as Button)
	_duel.hud.hide_meta_screen()
	await _frames(3)


# --- 通用检查 -----------------------------------------------------------

func _normal_room_index() -> int:
	for i in range(_duel.ROOMS.size()):
		if _duel.ROOMS[i].kind == "normal":
			return i
	return 0


func _check_in_screen(what: String, c: Control) -> void:
	if c == null:
		_check(false, "%s 存在" % what)
		return
	var r: Rect2 = c.get_global_rect()
	_check(r.position.x >= -EPS and r.position.y >= -EPS
		and r.position.x + r.size.x <= SCREEN_W + EPS
		and r.position.y + r.size.y <= SCREEN_H + EPS,
		"%s 在屏内（%s）" % [what, r])


func _check_label_fits(what: String, l: Label) -> void:
	if l == null:
		_check(false, "%s 存在" % what)
		return
	var min_x: float = l.get_combined_minimum_size().x
	var ok := min_x <= l.size.x + EPS
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
		ok = true   # 换行标签的横向由容器决定，纵向检查见下
	var min_y: float = l.get_combined_minimum_size().y
	var ok_y := min_y <= l.size.y + EPS
	_check(ok and ok_y, "%s 不溢出（min %.1f/%.1f · 实 %.1f/%.1f · wrap=%d）" % [
		what, min_x, min_y, l.size.x, l.size.y, l.autowrap_mode])


func _check_grid_fits(what: String, grid: Control) -> void:
	_check(grid.get_combined_minimum_size().x <= grid.size.x + EPS,
		"%s 横向不溢出（min %.1f / 宽 %.1f）" % [what, grid.get_combined_minimum_size().x, grid.size.x])


func _check_checklist_grid(what: String, grid: Control) -> void:
	_check(grid.get_child_count() > 0, "%s 有卡片" % what)
	_check_grid_fits(what, grid)


func _check_card_content(what: String, btn: Button) -> void:
	if btn == null:
		return
	if not (btn is ItemCard):
		_check_button_text(what, btn)
		return
	# ItemCard 的 CenterContainer 是整卡满矩形锚定（不受 Button 样式 margin 内缩），
	# 所以内容可用区按按钮自身尺寸算；样式 margin 只影响按钮文字，不影响卡片内容。
	var avail_w: float = btn.size.x
	var avail_h: float = btn.size.y
	var vb: Control = btn.get_node("Center/VBox")
	var vmin: Vector2 = vb.get_combined_minimum_size()
	_check(vmin.x <= avail_w + EPS, "%s 内容横向够（min %.1f / avail %.1f）" % [what, vmin.x, avail_w])
	_check(vmin.y <= avail_h + EPS, "%s 内容纵向够（min %.1f / avail %.1f）" % [what, vmin.y, avail_h])
	var d: Label = btn._desc_label
	if d != null and d.is_visible_in_tree():
		var fs: int = d.get_theme_font_size("font_size")
		var f: Font = d.get_theme_font("font")
		var wrapped: Vector2 = f.get_multiline_string_size(
			d.text, HORIZONTAL_ALIGNMENT_CENTER, d.size.x, fs)
		_check(wrapped.y <= d.size.y + EPS,
			"%s 状态行高度够（need %.1f / h %.1f）" % [what, wrapped.y, d.size.y])


func _check_button_text(what: String, btn: Button) -> void:
	if btn == null:
		return
	var fs: int = btn.get_theme_font_size("font_size")
	var font: Font = btn.get_theme_font("font")
	var sb: StyleBox = btn.get_theme_stylebox("normal")
	var icon_w := 0.0
	if btn.icon != null:
		icon_w = btn.icon.get_width() + btn.get_theme_constant("h_separation")
	var avail: float = btn.size.x - sb.content_margin_left - sb.content_margin_right - icon_w
	var wrapped: Vector2 = font.get_multiline_string_size(
		btn.text, HORIZONTAL_ALIGNMENT_CENTER, avail, fs)
	var need_h: float = wrapped.y + sb.content_margin_top + sb.content_margin_bottom
	_check(need_h <= btn.size.y + EPS,
		"%s 高度够（need %.1f / h %.1f）" % [what, need_h, btn.size.y])
	_check(btn.autowrap_mode != TextServer.AUTOWRAP_OFF or wrapped.x <= avail + EPS,
		"%s 文本不横向溢出（need %.1f / avail %.1f）" % [what, wrapped.x, avail])


func _check(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + msg)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
