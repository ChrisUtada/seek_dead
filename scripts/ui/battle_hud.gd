extends Control
class_name BattleHud
# BattleHud — 老虎机对决的常驻 HUD 与全屏子界面（Phase 2 关注点分离）
# 由 duel_controller.gd 抽出：所有 UI 构建/刷新/飘字/图例。控制器只保留战斗逻辑，
# 通过 controller 引用回 DuelController 的游戏状态与逻辑方法。

const TRASH_SYMBOL = preload("res://resources/symbols/trash.tres")
const ElementCounter = preload("res://scripts/battle/element_counter.gd")
const UI_BUTTON = preload("res://scenes/ui/ui_button.tscn")
const UI_PANEL = preload("res://scenes/ui/ui_panel.tscn")
const SYMBOL_CELL = preload("res://scenes/ui/symbol_cell.tscn")
const Screen = preload("res://scripts/ui/screen.gd")
const ItemData = preload("res://scripts/items/item_data.gd")

var controller   # DuelController 引用（运行时由 _ready 设置）

# ---- UI 节点引用 ----
var cells = []   # 展示用 Button 引用 [reel][row]
var cell_badges = []   # 每格右上角匹配角标 Label 引用 [reel][row]
var loadout_screen
var loadout_columns: Dictionary = {}  # col_category -> VBoxContainer for refresh
var loadout_slot_strips: Dictionary = {}   # category -> HBoxContainer（槽位条 ◆已装备/◇空位/·未解锁）
var loadout_cards := []                   # 卡片元数据列表 {path, btn, selected, kind}
var loadout_count_label
var loadout_confirm_btn
var loadout_anvil_label                # M5：整备屏显示铁砧点数
var reward_screen                       # 奖励三选一覆盖层
var meta_screen                         # 每局结束元进度三选一覆盖层
var meta_grid                           # 元进度三选一卡片网格
var reward_title_label
var reward_grid
var reward_skip_btn

# S6–S8 局内经济 UI
var gold_label                           # 玩家面板：局内金币
var shop_screen
var shop_title_label
var shop_gold_label
var shop_grid
var shop_leave_btn
var anvil_screen
var anvil_title_label
var anvil_points_label
var anvil_grid
var anvil_back_btn
# 商店「卖出」专用列表（与购入同屏，统一整备闭环）
var shop_sell_weapon_list
var shop_sell_skill_list
var shop_sell_charm_list
var shop_sell_consum_list
var grid_container
var log_label
var log_scroll
var player_hp_label
var player_shield_label
var enemy_name_label
var boss_badge            # BOSS 战标识（金色徽章，仅 BOSS 房显示）
var enemy_hp_label
var enemy_intent_label
var enemy_status_label
var player_buff_label     # Phase C：玩家当前生效的主动增益
var loadout_label
var room_label
var turn_label
var run_label
var purify_label
var overlay
var overlay_label
var overlay_button
var legend_box
var legend_container
# S2：伤害分解面板（中栏，转轮正下方；每次结算整体替换，不走战斗日志）
var dmg_breakdown_box
var dmg_breakdown_label
var player_panel          # 左：玩家面板（飘字锚点）
var enemy_panel           # 右：敌人面板（飘字锚点）

# ---- Phase 3：悬停 tooltip / 飘字对象池 ----
var symbol_tooltip                  # 转轮格子悬停提示面板
var symbol_tooltip_label
var symbol_tooltip_detail
var popup_layer                    # 飘字专用浮层（满屏，忽略鼠标）
var _popup_pool := []              # 预建 Label 池
var _popup_free := []              # 空闲 Label 栈
var _legend_sig := ""              # 图例 diff 签名缓存

func _label(text: String, size: int = TypeScale.BODY) -> Label:
	var l = Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	return l


func _make_side_panel(min_width: int) -> PanelContainer:
	# 面板外观（bg/border/圆角/边距）已由 duel.tscn 挂载的 battle_theme.tres 统一提供
	var panel = UI_PANEL.instantiate()
	panel.custom_minimum_size = Vector2(min_width, 0)
	return panel


# ---- Phase 3 辅助：快捷键 / 焦点链 / 分类名 ----
func _make_shortcut(keycode: int, ctrl := false, alt := false) -> Shortcut:
	var ev = InputEventKey.new()
	ev.keycode = keycode
	ev.ctrl_pressed = ctrl
	ev.alt_pressed = alt
	var s = Shortcut.new()
	s.events = [ev]
	return s


func _chain_focus(buttons: Array) -> void:
	for i in buttons.size():
		var b = buttons[i]
		var nxt = buttons[(i + 1) % buttons.size()]
		var prv = buttons[(i - 1 + buttons.size()) % buttons.size()]
		b.focus_mode = Control.FOCUS_ALL
		b.focus_next = nxt.get_path()
		b.focus_previous = prv.get_path()
		b.focus_neighbor_right = nxt.get_path()
		b.focus_neighbor_left = prv.get_path()


func _kind_name(kind: String) -> String:
	match kind:
		"damage":  return "伤害"
		"shield":  return "护盾"
		"heal":    return "治疗"
		"status":  return "状态"
		"special": return "特殊"
		"skill":    return "技能"
		"trash":   return "废铁"
		_:         return kind

func _source_tag(kind: String) -> String:
	# 来源标签：让玩家一眼看懂「同一效果为何出现在不同分类（常驻/主动/转轮）」
	match kind:
		"weapon":  return "【武器】"
		"passive": return "【常驻】"
		"active":  return "【主动】"
		"skill":   return "【转轮】"
		_:         return ""


func _build_ui() -> void:
	var root = Screen.build_scaffold(self, Palette.BG_MAIN, {"l": 10, "r": 10, "t": 8, "b": 8}, 6)

	# 标题
	var title_label = _label("Seek Dead · 老虎机对决", TypeScale.TITLE)
	title_label.add_theme_color_override("font_color", Palette.TITLE)
	root.add_child(title_label)

	# 信息栏：房间 / 回合 / 本局加成（单行，不占用垂直空间）
	var info = HBoxContainer.new()
	info.add_theme_constant_override("separation", 10)
	root.add_child(info)
	room_label = _label("房间: 1/1", TypeScale.META)
	room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	turn_label = _label("回合: 1", TypeScale.META)
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	run_label = _label("本局加成: —", TypeScale.TINY)
	run_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var info_spacer = Control.new()
	info_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(room_label)
	info.add_child(turn_label)
	info.add_child(info_spacer)
	info.add_child(run_label)

	loadout_label = _label("已装备: —", TypeScale.TINY)
	loadout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(loadout_label)

	# 主区域：玩家面板 | 转轮+意图 | 敌人面板+日志
	var main = HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 10)
	root.add_child(main)

	# 左：玩家面板（固定宽度，视觉分组）
	var ppanel = _make_side_panel(130)
	var ppv = ppanel.get_child(0)
	ppv.add_theme_constant_override("separation", 4)
	var ptitle = _label("玩家", TypeScale.BODY)
	ptitle.add_theme_color_override("font_color", Palette.PLAYER)
	ppv.add_child(ptitle)
	player_hp_label = _label("HP 100/100", TypeScale.MEDIUM)
	player_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	player_shield_label = _label("护盾 0", TypeScale.META)
	player_shield_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	player_buff_label = _label("技能: 无", TypeScale.TINY)
	player_buff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	player_buff_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	player_buff_label.add_theme_color_override("font_color", Palette.POP_BUFF)
	ppv.add_child(player_hp_label)
	ppv.add_child(player_shield_label)
	ppv.add_child(player_buff_label)
	gold_label = _label("金币 4", TypeScale.META)
	gold_label.add_theme_color_override("font_color", Palette.ACCENT_GOLD)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ppv.add_child(gold_label)
	ppv.add_child(Control.new())  # 占位撑开
	main.add_child(ppanel)

	# 中：转轮 + 敌人意图/状态
	player_panel = ppanel
	var center = VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 8)
	main.add_child(center)

	var reel_center = CenterContainer.new()
	reel_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(reel_center)
	grid_container = GridContainer.new()
	grid_container.columns = controller.REELS
	grid_container.add_theme_constant_override("h_separation", 10)
	grid_container.add_theme_constant_override("v_separation", 10)
	reel_center.add_child(grid_container)

	for reel in controller.REELS:
		cells.append([])
		controller.grid.append([])
		cell_badges.append([])
		for row in controller.ROWS:
			var cell = SYMBOL_CELL.instantiate()
			cell.custom_minimum_size = Vector2(84, 84)
			cell.add_theme_font_size_override("font_size", TypeScale.REEL)
			cell.disabled = true   # 无锁定，格子仅作展示
			cell.mouse_default_cursor_shape = Control.CURSOR_HELP   # Phase 3：悬停提示
			cell.mouse_filter = Control.MOUSE_FILTER_STOP
			cell.connect("mouse_entered", _on_cell_hover.bind(reel, row))
			cell.connect("mouse_exited", _on_cell_unhover)
			cell.connect("pressed", controller._on_reel_clicked.bind(reel))
			grid_container.add_child(cell)
			cells[reel].append(cell)
			controller.grid[reel].append(TRASH_SYMBOL)
			# 匹配角标（右上角锚定，封装在 symbol_cell.tscn 的 Badge 子节点）
			var badge = cell.get_node("Badge")
			cell_badges[reel].append(badge)

	var intent_box = HBoxContainer.new()
	intent_box.add_theme_constant_override("separation", 14)
	intent_box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(intent_box)
	enemy_intent_label = _label("意图: —", TypeScale.MEDIUM)
	enemy_status_label = _label("状态: 无", TypeScale.META)
	intent_box.add_child(enemy_intent_label)
	intent_box.add_child(enemy_status_label)

	# S2：伤害分解面板。放在中栏（最宽、正对转轮），每回合整体替换。
	# 不走战斗日志的原因：_log 是 push_front（多行会倒序）、上限 10 条、右栏仅 170px 宽会挤爆。
	dmg_breakdown_box = PanelContainer.new()
	var dstyle = StyleBoxFlat.new()
	dstyle.bg_color = Palette.PANEL_BG_ALT
	dstyle.border_color = Palette.PANEL_BORDER
	dstyle.set_border_width_all(1)
	dstyle.set_corner_radius_all(6)
	dstyle.content_margin_left = 8
	dstyle.content_margin_right = 8
	dstyle.content_margin_top = 4
	dstyle.content_margin_bottom = 4
	dmg_breakdown_box.add_theme_stylebox_override("panel", dstyle)
	dmg_breakdown_box.visible = false
	center.add_child(dmg_breakdown_box)
	dmg_breakdown_label = _label("", TypeScale.TINY)
	dmg_breakdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	dmg_breakdown_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dmg_breakdown_box.add_child(dmg_breakdown_label)

	# 符号图例（每符号名称/类型/元素 + 敌人属性），帮助理解"符号作用"
	legend_box = PanelContainer.new()
	var lstyle = StyleBoxFlat.new()
	lstyle.bg_color = Palette.PANEL_BG_ALT
	lstyle.border_color = Palette.PANEL_BORDER
	lstyle.set_border_width_all(1)
	lstyle.set_corner_radius_all(6)
	lstyle.content_margin_left = 8
	lstyle.content_margin_right = 8
	lstyle.content_margin_top = 6
	lstyle.content_margin_bottom = 6
	legend_box.add_theme_stylebox_override("panel", lstyle)
	center.add_child(legend_box)
	legend_container = VBoxContainer.new()
	legend_container.add_theme_constant_override("separation", 2)
	legend_box.add_child(legend_container)

	# 右：敌人面板 + 日志
	var rpanel = _make_side_panel(170)
	var rpv = rpanel.get_child(0)
	rpv.add_theme_constant_override("separation", 4)
	var etitle = _label("敌人", TypeScale.BODY)
	etitle.add_theme_color_override("font_color", Palette.ENEMY)
	rpv.add_child(etitle)
	boss_badge = _label("★ BOSS", TypeScale.BODY)
	boss_badge.add_theme_color_override("font_color", Palette.ACCENT_GOLD)
	boss_badge.visible = false
	rpv.add_child(boss_badge)
	enemy_name_label = _label("—", TypeScale.MEDIUM)
	enemy_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	enemy_hp_label = _label("HP 0/0", TypeScale.META)
	enemy_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rpv.add_child(enemy_name_label)
	rpv.add_child(enemy_hp_label)

	var log_title = _label("战斗日志", TypeScale.META)
	log_title.add_theme_color_override("font_color", Palette.MUTED)
	rpv.add_child(log_title)
	log_scroll = ScrollContainer.new()
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	rpv.add_child(log_scroll)
	log_label = Label.new()
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.add_theme_font_size_override("font_size", TypeScale.TINY)
	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.add_child(log_label)
	main.add_child(rpanel)
	enemy_panel = rpanel

	# 底部操作栏：始终可见，不被日志或内容挤出
	var bot = HBoxContainer.new()
	bot.add_theme_constant_override("separation", 8)
	root.add_child(bot)
	var spin = UI_BUTTON.instantiate()
	spin.text = "SPIN (空格)"
	spin.custom_minimum_size = Vector2(140, 48)
	spin.add_theme_font_size_override("font_size", TypeScale.SUBTITLE)
	spin.connect("pressed", controller._on_spin_button_pressed)
	bot.add_child(spin)

	var purify = UI_BUTTON.instantiate()
	purify.text = "净化 (Ctrl+P)"
	purify.custom_minimum_size = Vector2(110, 44)
	purify.add_theme_font_size_override("font_size", TypeScale.META)
	purify.shortcut = _make_shortcut(KEY_P, true)
	purify.connect("pressed", controller._on_purify_pressed)
	bot.add_child(purify)
	purify_label = _label("2", TypeScale.META)
	bot.add_child(purify_label)

	controller.consumable_panel = HBoxContainer.new()
	controller.consumable_panel.add_theme_constant_override("separation", 6)
	bot.add_child(controller.consumable_panel)

	var bot_spacer = Control.new()
	bot_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot.add_child(bot_spacer)

	var re_eq = UI_BUTTON.instantiate()
	re_eq.text = "整备 (Ctrl+E)"
	re_eq.custom_minimum_size = Vector2(110, 40)
	re_eq.add_theme_font_size_override("font_size", TypeScale.META)
	re_eq.shortcut = _make_shortcut(KEY_E, true)
	re_eq.connect("pressed", controller._on_reload_loadout_pressed)
	bot.add_child(re_eq)
	var reset = UI_BUTTON.instantiate()
	reset.text = "重置 (Ctrl+R)"
	reset.custom_minimum_size = Vector2(110, 40)
	reset.add_theme_font_size_override("font_size", TypeScale.META)
	reset.shortcut = _make_shortcut(KEY_R, true)
	reset.connect("pressed", controller._full_reset)
	bot.add_child(reset)

	_build_overlay()
	# Phase 3：键盘焦点链（Tab/方向键可在底部操作间移动）
	_chain_focus([spin, purify, re_eq, reset])
	# Phase 3：悬停 tooltip 与飘字对象池浮层
	_build_symbol_tooltip()
	_build_popup_layer()


# ---------------------------------------------------------------------------
# 整备界面（M3–M6）：武器 / 消耗品 / 护符 三分类自由勾选
# ---------------------------------------------------------------------------
func _build_loadout_screen() -> void:
	loadout_screen = Control.new()
	loadout_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loadout_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	var root = Screen.build_scaffold(loadout_screen, Palette.BG_LOADOUT, {"l": 10, "r": 10, "t": 8, "b": 8}, 6)

	var title = _label("⚙ 整备 · 选择携带物品", TypeScale.LEAD)
	title.add_theme_color_override("font_color", Palette.TITLE)
	root.add_child(title)
	var rule = _label("四类独立槽位 · 武器/技能=进转轮(稀释自然刹车·无硬顶) · 消耗品/护符=不进池(硬限) · 买即开槽扩槽", 10)
	rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(rule)

	# 四分类并列卡片区：每类一列、各自一条槽位条，杜绝跨类合计的视觉暗示
	var cat_box = HBoxContainer.new()
	cat_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cat_box.add_theme_constant_override("separation", 6)
	root.add_child(cat_box)

	loadout_cards = []
	loadout_columns = {}
	loadout_slot_strips = {}
	_add_loadout_column(cat_box, "武器", controller.WEAPON_POOL, "weapon", 1)
	_add_loadout_column(cat_box, "技能", controller.SKILL_POOL, "skill", 1)
	_add_loadout_column(cat_box, "消耗品", _item_pool_of("active"), "active", 1)
	_add_loadout_column(cat_box, "护符", _item_pool_of("passive"), "passive", 1)

	# 底部：计数 + 铁砧点数 + 铁砧按钮 + 确认（始终可见）
	var bot = HBoxContainer.new()
	bot.add_theme_constant_override("separation", 10)
	root.add_child(bot)
	loadout_count_label = _label("武器 0/%d · 技能 0/%d · 消耗品 0/%d · 护符 0/%d" % [controller.loadout_max, controller.skill_max, controller._cat_max("active"), controller.charm_max], TypeScale.META)
	loadout_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	bot.add_child(loadout_count_label)
	var bot_spacer = Control.new()
	bot_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot.add_child(bot_spacer)
	loadout_anvil_label = _label("铁砧点数: 0", TypeScale.TINY)
	bot.add_child(loadout_anvil_label)
	var anvil_btn = UI_BUTTON.instantiate()
	anvil_btn.text = "🔨 铁砧"
	anvil_btn.custom_minimum_size = Vector2(90, 36)
	anvil_btn.add_theme_font_size_override("font_size", TypeScale.TINY)
	anvil_btn.connect("pressed", _show_anvil_screen)
	bot.add_child(anvil_btn)
	loadout_confirm_btn = UI_BUTTON.instantiate()
	loadout_confirm_btn.text = "确认开战 ▶"
	loadout_confirm_btn.custom_minimum_size = Vector2(120, 40)
	loadout_confirm_btn.add_theme_font_size_override("font_size", TypeScale.MEDIUM)
	loadout_confirm_btn.connect("pressed", controller._confirm_loadout)
	bot.add_child(loadout_confirm_btn)

	add_child(loadout_screen)
	loadout_screen.visible = false


func _add_loadout_column(parent: Control, title: String, pool: Array, category: String, _columns: int) -> void:
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(250, 0)   # 四列并排：250*4 + 间隔 < 1280 设计宽
	var style = StyleBoxFlat.new()
	style.bg_color = Palette.CARD_BG
	style.border_color = Palette.PANEL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)

	var title_label = _label("%s 0/%d" % [title, controller._cat_max(category)], 12)
	loadout_columns[category] = title_label
	v.add_child(title_label)

	# 槽位条：按该类天花板画满格子，直观呈现「还能扩几格」
	var strip = HBoxContainer.new()
	strip.add_theme_constant_override("separation", 2)
	loadout_slot_strips[category] = strip
	v.add_child(strip)
	_refresh_slot_strip(category)

	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	v.add_child(scroll)

	# 单列纵向列表（固定最小宽度 170 设计 px，确保文字不会竖排；
	# 实际渲染时会按 ScrollContainer 可用宽度进一步扩展）。
	var list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size = Vector2(0, 0)
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	for path in pool:
		var data: Resource = load(path)
		var kind := "weapon"
		if data is ItemData:
			kind = data.category
		elif data is SkillData:
			kind = "skill"
		var card = _make_item_card(data, path, kind)
		list.add_child(card["btn"])
		loadout_cards.append(card)


# 从 ITEM_POOL 按 category 过滤：消耗品(active) 与 护符(passive) 各自独立成列
func _item_pool_of(category: String) -> Array:
	var out := []
	for p in controller.ITEM_POOL:
		var d = load(p)
		if d is ItemData and d.category == category:
			out.append(p)
	return out


# 刷新某类槽位条：天花板 = 格子总数，当前上限 = 已解锁边界，已选数 = 已装备边界
#   ◆ 已装备(绿) · ◇ 已解锁空位(常规) · · 未解锁(暗，需商店「买即开槽」)
func _refresh_slot_strip(category: String) -> void:
	if not loadout_slot_strips.has(category):
		return
	var strip: HBoxContainer = loadout_slot_strips[category]
	for c in strip.get_children():
		strip.remove_child(c)
		c.queue_free()
	var used = controller._sel_arr(category).size()
	var unlocked = controller._cat_max(category)
	var ceiling = controller._cat_cap(category)
	var uncapped = (ceiling == controller.UNCAPPED)
	# 无天花板（进池类 武器/增益）：只画已解锁的格子，末尾以 ＋ 表示可继续「买即开槽」（无限）
	# 有天花板（不进池类 消耗品/护符）：按天花板画满，· 表示尚未解锁的格子
	var cells = unlocked if uncapped else ceiling
	for i in cells:
		var glyph := "·"
		var tint := Palette.PANEL_BORDER
		if i < used:
			glyph = "◆"
			tint = Palette.CARD_SEL_BORDER
		elif i < unlocked:
			glyph = "◇"
			tint = Palette.MUTED
		var g = _label(glyph, 12)
		g.add_theme_color_override("font_color", tint)
		strip.add_child(g)
	if uncapped:
		var plus = _label("＋", 12)
		plus.add_theme_color_override("font_color", Palette.PANEL_BORDER)
		strip.add_child(plus)


func _make_item_card(data: Resource, path: String, kind: String) -> Dictionary:
	var btn = UI_BUTTON.instantiate()
	btn.custom_minimum_size = Vector2(0, 66)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.text = ""
	var vb = VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 1)
	btn.add_child(vb)

	var name := ""
	var line1 := ""   # 图标/核心信息
	var line2 := ""   # 数值/权重
	if kind == "weapon":
		name = data.weapon_name if (data != null) else path.get_file().get_basename()
		if data != null:
			var wd := data as WeaponData
			if wd != null and wd.reel != null and not wd.reel.is_empty():
				var parts := []
				for sw in wd.reel:
					if sw == null or sw.symbol == null:
						continue
					parts.append("%s×%d" % [sw.symbol.label, int(sw.weight)])
				line1 = " ".join(parts)
		line2 = "特殊: 无"
		if data != null:
			var wd := data as WeaponData
			if wd != null and wd.reel != null:
				for sw in wd.reel:
					if sw != null and sw.symbol != null and sw.symbol.kind == "special":
						line2 = "特殊: %s" % sw.symbol.name
						break
	elif kind == "skill":
		name = data.buff_name if (data != null) else path.get_file().get_basename()
		if data != null:
			line1 = "%s %s" % [data.icon, data.description]
			if data.symbol != null:
				line2 = "符号 %s×%d · 持续 %d 回合" % [data.symbol.label, int(data.weight), data.symbol.buff_turns]
	else:
		name = data.item_name if (data != null) else path.get_file().get_basename()
		if data != null:
			line1 = "%s %s" % [data.icon, data.description]
			line2 = "持有 %d" % data.charges if (kind == "active" and data.get("charges") != null) else "被动"

	name = _source_tag(kind) + name
	var nl = _label(name, TypeScale.META)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(nl)
	var l1 = _label(line1, TypeScale.TINY)
	l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(l1)
	if line2 != "":
		var l2 = _label(line2, TypeScale.CAPTION)
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l2.add_theme_color_override("font_color", Palette.MUTED_DIM)
		vb.add_child(l2)
	var card := {"path": path, "btn": btn, "selected": false, "kind": kind}
	btn.connect("pressed", controller._on_card_toggled.bind(card))
	return card


# 卡片点击：三分类通用 toggle（受各自分类上限约束，互不算总）
func _update_loadout_cards_visual() -> void:
	var wfull = controller.selected_loadout.size() >= controller._cat_max("weapon")
	var cfull = controller._sel_arr("active").size() >= controller._cat_max("active")
	var hfull = controller.selected_charms.size() >= controller._cat_max("passive")
	var bfull = controller.selected_skills.size() >= controller._cat_max("skill")
	for card in loadout_cards:
		var sb = StyleBoxFlat.new()
		if card["selected"]:
			sb.bg_color = Palette.CARD_SEL_BG
			sb.border_color = Palette.CARD_SEL_BORDER
			sb.set_border_width_all(2)
			card["btn"].disabled = false
		else:
			sb.bg_color = Palette.CARD_NORM_BG
			sb.border_color = Palette.CARD_NORM_BORDER
			sb.set_border_width_all(1)
			var cf = (card["kind"] == "weapon" and wfull) or (card["kind"] == "active" and cfull) or (card["kind"] == "passive" and hfull) or (card["kind"] == "skill" and bfull)
			card["btn"].disabled = cf
		card["btn"].add_theme_stylebox_override("normal", sb)
		card["btn"].add_theme_stylebox_override("hover", sb)
		card["btn"].add_theme_stylebox_override("pressed", sb)
		card["btn"].add_theme_stylebox_override("disabled", sb)


# 单类计数文本：「名称 已装备/当前上限」；无天花板的进池类补 ＋ 表示仍可继续扩槽
func _cat_count_text(cat: String, label: String) -> String:
	var grow = "＋" if controller._cat_cap(cat) == controller.UNCAPPED else ""
	return "%s %d/%d%s" % [label, controller._sel_arr(cat).size(), controller._cat_max(cat), grow]


func _update_loadout_count() -> void:
	# 四类各自独立计数，不再出现任何跨类合计
	loadout_count_label.text = "%s · %s · %s · %s" % [
		_cat_count_text("weapon", "武器"), _cat_count_text("skill", "技能"),
		_cat_count_text("active", "消耗品"), _cat_count_text("passive", "护符")]
	var titles = {"weapon": "武器", "skill": "技能", "active": "消耗品", "passive": "护符"}
	for cat in titles:
		if loadout_columns.has(cat):
			loadout_columns[cat].text = _cat_count_text(cat, titles[cat])
		_refresh_slot_strip(cat)
	var ok = controller.selected_loadout.size() >= controller.LOADOUT_MIN
	loadout_confirm_btn.disabled = not ok
	loadout_confirm_btn.text = ("确认开战 ▶" if ok else "至少选 %d 把武器 ▶" % controller.LOADOUT_MIN)


func _show_loadout_screen() -> void:
	controller.in_loadout = true
	_sync_card_selection()      # 从数组重建卡片 selected 标志（防止 Boss 奖励等外部路径直接改数组导致不同步）
	_update_loadout_cards_visual()
	_update_loadout_count()
	_update_loadout_anvil()
	loadout_screen.visible = true


# 每次打开整备屏时，从 controller 的四个选中数组重建所有卡片的 selected 标志。
# 必须做：Boss 奖励（_apply_boss_reward）会直接 append 到 selected_loadout / selected_charms
# 而不经过 _on_card_toggled，导致卡片标志与数组不同步——不同步会使 wfull 误判、
# 点掉武器后全部卡片仍被 disabled 锁死。
func _sync_card_selection() -> void:
	var weapons = controller.selected_loadout
	var consumables = controller.selected_consumables
	var charms = controller.selected_charms
	var skills = controller.selected_skills
	for card in loadout_cards:
		match card["kind"]:
			"weapon":
				card["selected"] = weapons.has(card["path"])
			"active":
				card["selected"] = consumables.has(card["path"])
			"passive":
				card["selected"] = charms.has(card["path"])
			"skill":
				card["selected"] = skills.has(card["path"])


func _update_loadout_anvil() -> void:
	if loadout_anvil_label != null:
		loadout_anvil_label.text = "铁砧点数: %d" % controller.meta["anvil_points"]


func _hide_loadout_screen() -> void:
	controller.in_loadout = false
	loadout_screen.visible = false


func _build_reward_screen() -> void:
	reward_screen = Control.new()
	reward_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reward_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	var v = Screen.build_scaffold(reward_screen, Palette.BG_REWARD, {"l": 18, "r": 18, "t": 14, "b": 14}, 6)
	reward_title_label = _label("", TypeScale.OVERLAY)
	v.add_child(reward_title_label)
	v.add_child(_label("选择一项奖励带入后续房间（Roguelike 构筑，跳过则不取）", TypeScale.META))

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	reward_grid = GridContainer.new()
	reward_grid.columns = 3
	reward_grid.add_theme_constant_override("h_separation", 8)
	reward_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(reward_grid)

	var bot = HBoxContainer.new()
	v.add_child(bot)
	var sp = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot.add_child(sp)
	reward_skip_btn = UI_BUTTON.instantiate()
	reward_skip_btn.text = "跳过 ▶"
	reward_skip_btn.custom_minimum_size = Vector2(120, 40)
	reward_skip_btn.connect("pressed", controller._on_reward_skip_pressed)
	bot.add_child(reward_skip_btn)

	add_child(reward_screen)
	reward_screen.visible = false


func _show_reward_screen(is_boss: bool) -> void:
	controller.reward_is_boss = is_boss
	# 清理旧卡片
	for c in reward_grid.get_children():
		reward_grid.remove_child(c)
		c.queue_free()
	if is_boss:
		controller.reward_choices = controller._roll_boss_rewards(controller.ROOMS[controller.room_index])
		reward_title_label.text = "★ BOSS 战利品！选择一项（主题武器 / 强化券 / 信物）"
		for rw in controller.reward_choices:
			reward_grid.add_child(_make_boss_reward_card(rw))
	else:
		controller.reward_choices = controller._roll_rewards()
		reward_title_label.text = "胜利！选择一项房奖励"
		for rw in controller.reward_choices:
			reward_grid.add_child(_make_reward_card(rw))
	reward_screen.visible = true


func _make_reward_card(rw: RewardData) -> Button:
	var btn = UI_BUTTON.instantiate()
	btn.custom_minimum_size = Vector2(96, 64)
	btn.text = ""
	var cc = CenterContainer.new()
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.add_child(cc)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	cc.add_child(vb)
	vb.add_child(_label("%s %s" % [rw.icon, rw.label], 13))
	var dl = _label(rw.desc, TypeScale.TINY)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(dl)
	btn.connect("pressed", controller._on_reward_chosen.bind(rw.id))
	return btn


# BOSS 战利品卡（候选为 dict，点击调 _on_boss_reward_chosen）
func _make_boss_reward_card(cand: Dictionary) -> Button:
	var btn = UI_BUTTON.instantiate()
	btn.custom_minimum_size = Vector2(96, 64)
	btn.text = ""
	var cc = CenterContainer.new()
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.add_child(cc)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	cc.add_child(vb)
	vb.add_child(_label("%s %s" % [cand.get("icon", ""), cand.get("label", "")], 13))
	var dl = _label(cand.get("desc", ""), TypeScale.TINY)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(dl)
	btn.connect("pressed", controller._on_boss_reward_chosen.bind(cand))
	return btn


# ---------------------------------------------------------------------------
# 每局结束元进度三选一（膨胀双轨：武器 base 线性 × 护符乘数增值，持久跨局）
# ---------------------------------------------------------------------------
func _build_meta_screen() -> void:
	meta_screen = Control.new()
	meta_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	meta_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	var v = Screen.build_scaffold(meta_screen, Palette.BG_REWARD, {"l": 18, "r": 18, "t": 14, "b": 14}, 6)
	v.add_child(_label("★ 通关一局！选择一项元进度升级（持久生效）", TypeScale.OVERLAY))
	v.add_child(_label("武器基础伤害线性成长 × 护符伤害乘区增值——下一局起爆炸", TypeScale.META))
	var center = CenterContainer.new()      # 三选一固定 ≤3 张，居中呈现（不需要滚动）
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(center)
	meta_grid = GridContainer.new()
	meta_grid.columns = 3
	meta_grid.add_theme_constant_override("h_separation", 12)
	meta_grid.add_theme_constant_override("v_separation", 12)
	center.add_child(meta_grid)
	add_child(meta_screen)
	meta_screen.visible = false


func _show_meta_choice() -> void:
	for c in meta_grid.get_children():
		meta_grid.remove_child(c)
		c.queue_free()
	var choices = controller._roll_meta_choices()
	for opt in choices:
		meta_grid.add_child(_make_meta_card(opt))
	meta_screen.visible = true


func _make_meta_card(opt: Dictionary) -> Button:
	var btn = UI_BUTTON.instantiate()
	btn.custom_minimum_size = Vector2(210, 92)   # 仅 3 张、覆盖层空间充足，放大提升可读性
	btn.text = ""
	var cc = CenterContainer.new()
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.add_child(cc)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	cc.add_child(vb)
	vb.add_child(_label("%s %s" % [opt.get("icon", ""), opt.get("label", "")], 13))
	var dl = _label(opt.get("desc", ""), TypeScale.TINY)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dl.custom_minimum_size = Vector2(190, 0)     # 约束宽度，保证长描述换行而非撑破卡片
	vb.add_child(dl)
	btn.connect("pressed", controller._on_meta_choice_chosen.bind(opt))
	return btn


func _build_shop_screen() -> void:
	shop_screen = Control.new()
	shop_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shop_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	var v = Screen.build_scaffold(shop_screen, Palette.BG_REWARD, {"l": 18, "r": 18, "t": 14, "b": 14}, 6)
	shop_title_label = _label("🛒 商店 · 用金币投资战力", TypeScale.OVERLAY)
	v.add_child(shop_title_label)
	shop_gold_label = _label("金币: 0", TypeScale.BODY)
	shop_gold_label.add_theme_color_override("font_color", Palette.ACCENT_GOLD)
	v.add_child(shop_gold_label)
	v.add_child(_label("购买后带入后续房间；也可卖出回收约50%金币并释放槽位（随机刷新，先到先得）", TypeScale.META))

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var inner = VBoxContainer.new()
	inner.add_theme_constant_override("separation", 14)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)

	inner.add_child(_label("📥 购入", TypeScale.BODY))
	shop_grid = GridContainer.new()
	shop_grid.columns = 3
	shop_grid.add_theme_constant_override("h_separation", 8)
	shop_grid.add_theme_constant_override("v_separation", 8)
	inner.add_child(shop_grid)

	inner.add_child(_label("📤 卖出（回收约50%金币 · 释放槽位）", TypeScale.BODY))
	var sell_box = HBoxContainer.new()
	sell_box.add_theme_constant_override("separation", 6)
	sell_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_sell_weapon_list = _sell_column(sell_box, "武器")
	shop_sell_skill_list = _sell_column(sell_box, "技能")
	shop_sell_charm_list = _sell_column(sell_box, "护符")
	shop_sell_consum_list = _sell_column(sell_box, "消耗品")
	inner.add_child(sell_box)

	var bot = HBoxContainer.new()
	v.add_child(bot)
	var sp = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot.add_child(sp)
	shop_leave_btn = UI_BUTTON.instantiate()
	shop_leave_btn.text = "离开商店 ▶"
	shop_leave_btn.custom_minimum_size = Vector2(140, 40)
	shop_leave_btn.connect("pressed", controller._on_shop_leave_pressed)
	bot.add_child(shop_leave_btn)

	add_child(shop_screen)
	shop_screen.visible = false


func _show_shop_screen() -> void:
	controller._roll_shop()
	_refresh_shop()
	shop_screen.visible = true


func _refresh_shop() -> void:
	shop_gold_label.text = "金币: %d" % controller.gold
	for c in shop_grid.get_children():
		shop_grid.remove_child(c)
		c.queue_free()
	for offer in controller.shop_offers:
		shop_grid.add_child(_make_shop_card(offer))
	_refresh_shop_sell()


func _make_shop_card(offer: Dictionary) -> Button:
	var btn = UI_BUTTON.instantiate()
	btn.custom_minimum_size = Vector2(110, 86)
	btn.text = ""
	var cc = CenterContainer.new()
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.add_child(cc)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	cc.add_child(vb)
	var kind_name = {"weapon": "武器", "passive": "护符", "active": "物品", "skill": "技能"}.get(offer["kind"], "物品")
	vb.add_child(_label("%s%s · %s" % [_source_tag(offer["kind"]), kind_name, offer["name"]], 12))
	var price = controller._shop_price(offer["kind"])   # 价格随当前持有数递增；卖出回落，换装成本=买卖价差（防刷价）
	var is_active = (offer["kind"] == "active")
	var cap = controller.CONSUMABLE_CAP if is_active else controller._cat_max(offer["kind"])          # 消耗品按腰带总容量 4；其余按整备上限
	var cur = controller.consumable_slots.size() if is_active else controller._sel_arr(offer["kind"]).size()   # 消耗品按腰带实占数
	var can_grow_slot = (not is_active) and controller._can_grow_slot(offer["kind"])   # 消耗品不「开槽」、仅追加腰带格
	var slot_full = (cur >= cap) and not can_grow_slot
	var can_buy = (not offer["sold"]) and controller.gold >= price and not slot_full
	var status: String
	if offer["sold"]:
		status = "已购入"
	elif controller.gold < price:
		status = "金币不足"
	elif slot_full:
		var cap_txt = controller.CONSUMABLE_CAP if is_active else controller._cap_text(offer["kind"])
		status = "槽位已满 %d/%s" % [cur, cap_txt]
	elif cur >= cap:
		status = "开槽 %d 金" % price   # 本次购买会把该类槽 +1
	else:
		status = "%d 金" % price
	var pl = _label(status, TypeScale.TINY)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if offer["sold"]:
		pl.add_theme_color_override("font_color", Palette.MUTED_DIM)
	elif not can_buy:
		pl.add_theme_color_override("font_color", Palette.ENEMY)
	else:
		pl.add_theme_color_override("font_color", Palette.ACCENT_GOLD)
	vb.add_child(pl)
	btn.disabled = not can_buy
	btn.connect("pressed", controller._on_shop_buy_pressed.bind(offer))
	return btn


# 商店「卖出」区：四列列出已持有物品，点击回收约50%金币并释放槽位
func _refresh_shop_sell() -> void:
	_sell_fill(shop_sell_weapon_list, "weapon")
	_sell_fill(shop_sell_skill_list, "skill")
	_sell_fill(shop_sell_charm_list, "passive")   # 护符计价 kind = passive
	_sell_fill(shop_sell_consum_list, "active")


func _sell_fill(list: VBoxContainer, kind: String) -> void:
	for c in list.get_children():
		if c is Label:        # 保留列标题
			continue
		list.remove_child(c)
		c.queue_free()
	if kind == "active":
		# 消耗品：按腰带实例逐格列出（同类重复各占一格），点击按 uid 卖出
		for slot in controller.consumable_slots:
			var name = _source_tag(kind) + controller._shop_name(slot["path"], kind)
			var refund = controller._sell_price(kind, slot["uid"])
			var sub = "卖出 +%d 金" % refund
			list.add_child(_make_sell_card(name, sub, false, controller._on_shop_sell_pressed.bind(slot["uid"], kind)))
		return
	var owned = controller._sel_arr(kind)
	for path in owned:
		var name = _source_tag(kind) + controller._shop_name(path, kind)
		var refund = controller._sell_price(kind, path)
		var last = (kind == "weapon" and owned.size() <= controller.LOADOUT_MIN)
		var sub: String
		if last:
			sub = "最后一把 · 不可卖"
		else:
			sub = "卖出 +%d 金" % refund
		list.add_child(_make_sell_card(name, sub, last, controller._on_shop_sell_pressed.bind(path, kind)))


func _sell_column(parent: Control, title: String) -> VBoxContainer:
	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 3)
	col.add_child(_label(title, TypeScale.TINY))
	parent.add_child(col)
	return col


func _make_sell_card(title_text: String, sub_text: String, disabled: bool, cb: Callable) -> Button:
	var btn = UI_BUTTON.instantiate()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 46)
	btn.text = ""
	var cc = CenterContainer.new()
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_child(cc)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	cc.add_child(vb)
	vb.add_child(_label(title_text, TypeScale.TINY))
	var pl = _label(sub_text, TypeScale.TINY)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var col := Palette.ACCENT_GOLD
	if disabled:
		col = Palette.MUTED_DIM
	pl.add_theme_color_override("font_color", col)
	vb.add_child(pl)
	btn.disabled = disabled
	if not cb.is_null():
		btn.connect("pressed", cb)
	return btn



func _build_anvil_screen() -> void:
	anvil_screen = Control.new()
	anvil_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anvil_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	var v = Screen.build_scaffold(anvil_screen, Palette.BG_ANVIL, {"l": 12, "r": 12, "t": 10, "b": 10}, 4)
	anvil_title_label = _label("🔨 铁砧锻造 · 元进度", TypeScale.BODY)
	v.add_child(anvil_title_label)
	anvil_points_label = _label("铁砧点数: 0", TypeScale.META)
	v.add_child(anvil_points_label)
	v.add_child(_label("消耗点数永久强化转轮 / 抗干扰（跨局保留）", TypeScale.CAPTION))

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	anvil_grid = GridContainer.new()
	anvil_grid.columns = 3
	anvil_grid.add_theme_constant_override("h_separation", 6)
	anvil_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(anvil_grid)

	var bot = HBoxContainer.new()
	v.add_child(bot)
	var sp = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot.add_child(sp)
	anvil_back_btn = UI_BUTTON.instantiate()
	anvil_back_btn.text = "返回整备"
	anvil_back_btn.custom_minimum_size = Vector2(120, 40)
	anvil_back_btn.add_theme_font_size_override("font_size", TypeScale.MEDIUM)
	anvil_back_btn.connect("pressed", controller._on_anvil_back_pressed)
	bot.add_child(anvil_back_btn)

	add_child(anvil_screen)
	anvil_screen.visible = false


func _show_anvil_screen() -> void:
	_refresh_anvil()
	anvil_screen.visible = true


func _refresh_anvil() -> void:
	anvil_points_label.text = "铁砧点数: %d" % controller.meta["anvil_points"]
	# 清理旧卡片
	for c in anvil_grid.get_children():
		anvil_grid.remove_child(c)
		c.queue_free()
	# 武器转轮升级
	for path in controller.WEAPON_POOL:
		var wd: Resource = load(path)
		var wname = wd.weapon_name if (wd != null) else path.get_file().get_basename()
		var lvl = controller.meta["weapon_upgrades"].get(path, 0)
		var cost = (lvl + 1) * 10
		var btn = UI_BUTTON.instantiate()
		btn.custom_minimum_size = Vector2(96, 56)
		btn.text = ""
		var cc = CenterContainer.new()
		cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.add_child(cc)
		var vb = VBoxContainer.new()
		vb.add_theme_constant_override("separation", 1)
		cc.add_child(vb)
		vb.add_child(_label(wname, TypeScale.META))
		vb.add_child(_label("转轮 Lv%d" % lvl, TypeScale.CAPTION))
		vb.add_child(_label("升级 %d 点" % cost, TypeScale.CAPTION))
		btn.connect("pressed", controller._on_anvil_weapon_pressed.bind(path))
		anvil_grid.add_child(btn)
	# 抗干扰
	var rl = controller.meta["interference_resist"]
	var rcost = (rl + 1) * 15
	var rbtn = UI_BUTTON.instantiate()
	rbtn.custom_minimum_size = Vector2(96, 56)
	rbtn.text = ""
	var rcc = CenterContainer.new()
	rcc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rcc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rbtn.add_child(rcc)
	var rvb = VBoxContainer.new()
	rvb.add_theme_constant_override("separation", 1)
	rcc.add_child(rvb)
	rvb.add_child(_label("锤炼意志", TypeScale.META))
	rvb.add_child(_label("抗干扰 Lv%d/5" % rl, TypeScale.CAPTION))
	if rl >= 5:
		rvb.add_child(_label("已满级", TypeScale.CAPTION))
	else:
		rvb.add_child(_label("升级 %d 点" % rcost, TypeScale.CAPTION))
	rbtn.connect("pressed", controller._on_anvil_resist_pressed)
	anvil_grid.add_child(rbtn)


func _build_overlay() -> void:
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var ov_v = Screen.build_centered(overlay, Palette.BG_OVERLAY, 18)
	overlay_label = _label("", TypeScale.REEL)
	ov_v.add_child(overlay_label)
	overlay_button = UI_BUTTON.instantiate()
	overlay_button.custom_minimum_size = Vector2(220, 50)
	overlay_button.connect("pressed", controller._on_overlay_button_pressed)
	ov_v.add_child(overlay_button)
	add_child(overlay)
	overlay.visible = false


# ---------------------------------------------------------------------------
# Phase 3：符号 tooltip（转轮格子悬停提示）
# ---------------------------------------------------------------------------
func _build_symbol_tooltip() -> void:
	symbol_tooltip = PanelContainer.new()
	symbol_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	symbol_tooltip.visible = false
	var sb = StyleBoxFlat.new()
	sb.bg_color = Palette.TOOLTIP_BG
	sb.border_color = Palette.PANEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	symbol_tooltip.add_theme_stylebox_override("panel", sb)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	symbol_tooltip.add_child(vb)
	symbol_tooltip_label = _label("", TypeScale.META)
	symbol_tooltip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vb.add_child(symbol_tooltip_label)
	symbol_tooltip_detail = _label("", TypeScale.TINY)
	symbol_tooltip_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	symbol_tooltip_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(symbol_tooltip_detail)
	add_child(symbol_tooltip)


# 读某格的「有效元素」——即符号继承武器 element 之后的结果（controller.grid_elem）。
# 注意：不能读 SymbolData.element（符号原生元素）。共享 .tres（如 slash）在火剑下
# 有效元素是 fire、在铁剑下是 none，只有 grid_elem 与 _contribute 的结算口径一致。
func _cell_element(reel: int, row: int) -> String:
	if controller == null:
		return "none"
	if controller.grid_elem.size() <= reel:
		return "none"
	if controller.grid_elem[reel].size() <= row:
		return "none"
	return controller.grid_elem[reel][row]


func _on_cell_hover(reel: int, row: int) -> void:
	if symbol_tooltip == null or controller == null:
		return
	if controller.grid.size() <= reel or controller.grid[reel].size() <= row:
		return
	var s: SymbolData = controller.grid[reel][row]
	# S1 修复：原先读 s.element（符号原生元素），火剑的斩击会显示"无属性"，
	# 而结算按 fire 吃 ×1.5——tooltip 与实际伤害对不上。改读有效元素。
	var elem = _cell_element(reel, row)
	var rel = ElementCounter.relation(elem, controller.enemy_element)
	var rel_mult = ElementCounter.multiplier(elem, controller.enemy_element)
	var rel_text = ("" if elem == "none" else " · 对敌%s ×%s" % [rel, ElementCounter.fmt_mult(rel_mult)])
	symbol_tooltip_label.text = "%s %s" % [s.label, s.name]
	if s.kind == "buff":
		# Phase C：增益符号显示效果与持续回合，而非属性克制
		var vtxt = ("×%.1f" % s.buff_value) if s.buff_effect == "damage_mult" else ("+%d" % int(s.buff_value))
		symbol_tooltip_detail.text = "技能 · %s %s · 持续 %d 回合" % [controller._buff_effect_name(s.buff_effect), vtxt, s.buff_turns]
	else:
		symbol_tooltip_detail.text = "%s · %s%s" % [_kind_name(s.kind), (ElementCounter.label(elem) if elem != "none" else "无属性"), rel_text]
	# 定位到格子上方并夹紧屏幕边界
	var gp = cells[reel][row].get_global_rect()
	var pr = get_global_rect()
	var tp = symbol_tooltip.get_combined_minimum_size()
	var x = gp.position.x - pr.position.x
	x = clamp(x, 4.0, pr.size.x - tp.x - 4.0)
	var y = gp.position.y - pr.position.y - tp.y - 4.0
	symbol_tooltip.position = Vector2(x, y)
	symbol_tooltip.visible = true


func _on_cell_unhover() -> void:
	if symbol_tooltip != null:
		symbol_tooltip.visible = false


# ---------------------------------------------------------------------------
# Phase 3：飘字对象池（避免每次 new + queue_free）
# ---------------------------------------------------------------------------
func _build_popup_layer() -> void:
	popup_layer = Control.new()
	popup_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(popup_layer)
	for i in 16:
		var l = Label.new()
		l.visible = false
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		popup_layer.add_child(l)
		_popup_pool.append(l)
		_popup_free.append(l)


# ---------------------------------------------------------------------------
# 房间 / 流程
# ---------------------------------------------------------------------------
func _clear_badges() -> void:
	for reel in controller.REELS:
		for row in controller.ROWS:
			if cell_badges.size() > reel and cell_badges[reel].size() > row:
				cell_badges[reel][row].text = ""


func _update_match_badges(counts: Dictionary) -> void:
	_clear_badges()
	for key in counts:
		var entry = counts[key]
		var s: SymbolData = entry[0]
		var c = entry[2]
		if s == TRASH_SYMBOL or c < 2:
			continue
		for reel in controller.REELS:
			for row in controller.ROWS:
				if controller.grid[reel][row] == s:
					cell_badges[reel][row].text = "×%d" % c


# 符号图例：每符号名称/类型/元素 + 敌人属性（Phase 3：签名未变则跳过重建）
func _refresh_legend() -> void:
	if legend_container == null:
		return
	var sig = _legend_signature()
	if sig == _legend_sig:
		return
	_legend_sig = sig
	for c in legend_container.get_children():
		legend_container.remove_child(c)
		c.queue_free()
	# S3：敌人栏改为「弱点 / 抗性」视角。原先只显示"敌人属性：火"，玩家还得
	# 自己在脑子里跑一遍五元环才知道该带什么武器——这里直接把结论摆出来。
	var eelem: String = controller.enemy_element
	var et = _label("敌人 %s" % ElementCounter.label(eelem), TypeScale.META)
	et.add_theme_color_override("font_color", ElementCounter.color(eelem))
	et.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	legend_container.add_child(et)
	var ewk := ElementCounter.weakness(eelem)
	var ers := ElementCounter.resists(eelem)
	if ewk == "none":
		var en = _label("无属性 · 不吃克制（任何元素均 ×1.0）", TypeScale.TINY)
		en.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		en.add_theme_color_override("font_color", ElementCounter.color("none"))
		legend_container.add_child(en)
	else:
		var lw = _label("弱 %s ×%s" % [ElementCounter.label(ewk), ElementCounter.fmt_mult(ElementCounter.MULT_ADVANTAGE)], TypeScale.TINY)
		lw.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lw.add_theme_color_override("font_color", ElementCounter.color(ewk))
		legend_container.add_child(lw)
		var lr = _label("抗 %s ×%s" % [ElementCounter.label(ers), ElementCounter.fmt_mult(ElementCounter.MULT_RESIST)], TypeScale.TINY)
		lr.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lr.add_theme_color_override("font_color", ElementCounter.color(ers))
		legend_container.add_child(lr)
	var seen := {}
	for p in controller.pool:
		var d: SymbolData = p[0]
		var pelem: String = p[2] if p.size() > 2 else d.element
		var key = d.resource_path + "|" + pelem
		if seen.has(key):
			continue
		seen[key] = true
		var elem = pelem
		var kindname = _kind_name(d.kind)
		var t = "%s %s · %s%s" % [d.label, d.name, kindname, ("" if elem == "none" else " · " + ElementCounter.label(elem))]
		var tint = ElementCounter.color(elem)
		if d.kind == "buff":
			# Phase C：增益符号在图例里展示效果与持续回合，用符号自身配色
			var vtxt = ("×%.1f" % d.buff_value) if d.buff_effect == "damage_mult" else ("+%d" % int(d.buff_value))
			t = "%s %s · 技能 · %s %s（%d 回合）" % [d.label, d.name, controller._buff_effect_name(d.buff_effect), vtxt, d.buff_turns]
			tint = d.color
		var l = _label(t, TypeScale.TINY)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.add_theme_color_override("font_color", tint)
		legend_container.add_child(l)


func _legend_signature() -> String:
	var ids := []
	for p in controller.pool:
		var pelem: String = p[2] if p.size() > 2 else "none"
		ids.append(p[0].resource_path + "|" + pelem)
	ids.sort()
	return "%s|%s" % [",".join(ids), controller.enemy_element]


# 飘字：在 anchor 面板顶部中央弹出并上浮淡出（Phase 3：固定对象池借出/归还）
func _popup(text: String, color: Color, anchor: Control) -> void:
	if anchor == null or popup_layer == null:
		return
	var lbl: Label
	if _popup_free.is_empty():
		lbl = Label.new()
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		popup_layer.add_child(lbl)
		_popup_pool.append(lbl)
	else:
		lbl = _popup_free.pop_back()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", TypeScale.OVERLAY)
	lbl.add_theme_color_override("font_color", color)
	lbl.modulate = Color(1, 1, 1, 1)
	lbl.visible = true
	var gp = anchor.get_global_rect()
	var pr = popup_layer.get_global_rect()
	var w = lbl.get_minimum_size().x
	lbl.position = Vector2(gp.position.x - pr.position.x + gp.size.x * 0.5 - w * 0.5, gp.position.y - pr.position.y + 6)
	var tw = create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - 38, 0.8)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.8)
	tw.tween_callback(_return_popup.bind(lbl))


func _return_popup(lbl: Label) -> void:
	lbl.visible = false
	if not _popup_free.has(lbl):
		_popup_free.append(lbl)


func _player_panel_anchor() -> Control:
	return player_panel


# S2：显示本回合伤害分解（整块替换；传空则隐藏面板）
func _show_damage_breakdown(text: String) -> void:
	if dmg_breakdown_box == null:
		return
	if text.strip_edges().is_empty():
		dmg_breakdown_box.visible = false
		dmg_breakdown_label.text = ""
		return
	dmg_breakdown_label.text = text
	dmg_breakdown_box.visible = true


func _clear_damage_breakdown() -> void:
	_show_damage_breakdown("")


func _enemy_panel_anchor() -> Control:
	return enemy_panel


# S4：元素样式缓存。旋转最高速约 28 跳/秒 × 3 列，若每次 new StyleBoxFlat
# 会产生大量短命对象；按元素各缓存一份即可（StyleBox 可跨按钮共享）。
var _cell_style_cache := {}


func _cell_style(elem: String) -> StyleBoxFlat:
	if _cell_style_cache.has(elem):
		return _cell_style_cache[elem]
	var sb = StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	if elem == "none":
		sb.bg_color = Palette.CELL_BG
		sb.border_color = Palette.PANEL_BORDER
		sb.set_border_width_all(1)
	else:
		var ec: Color = ElementCounter.color(elem)
		sb.bg_color = Palette.CELL_BG.lerp(ec, 0.14)
		sb.border_color = ec
		sb.set_border_width_all(3)
	_cell_style_cache[elem] = sb
	return sb


func _refresh_cell(reel: int, row: int) -> void:
	var b: Button = cells[reel][row]
	var s: SymbolData = controller.grid[reel][row]
	# S4：按「有效元素」着色。同一个 slash.tres 在火剑下是火、在铁剑下是无属性，
	# 靠边框/底色一眼分辨谁吃 ×1.5；元素为 none 时回落符号自身配色。
	var elem = _cell_element(reel, row)
	b.text = s.label
	var fc: Color = s.color if elem == "none" else s.color.lerp(ElementCounter.color(elem), 0.55)
	# 格子在非旋转期是 disabled 态，只覆盖 font_color 会被主题的禁用色盖掉，四态都要给。
	b.add_theme_color_override("font_color", fc)
	b.add_theme_color_override("font_disabled_color", fc)
	b.add_theme_color_override("font_hover_color", fc)
	b.add_theme_color_override("font_pressed_color", fc)
	var sb = _cell_style(elem)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("disabled", sb)


func _refresh_meta() -> void:
	loadout_label.text = "已装备: " + ("/".join(controller.loadout_names) if not controller.loadout_names.is_empty() else "—")
	var is_boss = controller._is_boss_room(controller.room_index)
	room_label.text = "房间: %d/%d%s" % [controller.room_index + 1, controller.ROOMS.size(), " · ★BOSS" if is_boss else ""]
	turn_label.text = "回合: %d" % controller.turn_count
	player_hp_label.text = "HP %d/%d" % [controller.player_hp, controller.player_hp_max]
	player_shield_label.text = "护盾 %d" % controller.player_shield
	player_buff_label.text = "【转轮】技能: " + controller._buff_summary()
	gold_label.text = "金币 %d" % controller.gold
	enemy_name_label.text = controller.enemy_name
	boss_badge.visible = is_boss
	enemy_hp_label.text = "HP %d/%d" % [max(controller.enemy_hp, 0), controller.enemy_hp_max]
	enemy_status_label.text = "状态: " + ("无" if controller.enemy_status.is_empty() else controller._status_summary(controller.enemy_status))
	purify_label.text = "%d/%d" % [controller.purify_charges, controller.purify_max_base]
	# M4+M6 本局加成概览
	var parts := []
	if controller.run_power_bonus + controller.charm_power_bonus > 0:
		parts.append("伤害+%d" % (controller.run_power_bonus + controller.charm_power_bonus))
	# 护符乘区（damage_mult 类型，如 rage_charm ×1.5）此前漏显示 → 带乘区护符时概览空显示"无"
	if controller.charm_damage_mult != 1.0:
		parts.append("护符×%s" % ElementCounter.fmt_mult(controller.charm_damage_mult))
	if controller.purify_max_base > 0:
		parts.append("净化上限%d" % controller.purify_max_base)
	if controller.charm_room_shield > 0:
		parts.append("护盾+%d" % controller.charm_room_shield)
	if controller.charm_interf_resist > 0:
		parts.append("抗扰+%d" % controller.charm_interf_resist)
	if not controller.run_symbol_bonus.is_empty():
		var sp := []
		for spath in controller.run_symbol_bonus.keys():
			var sym: SymbolData = load(spath)
			sp.append("%s+%d" % [sym.name, controller.run_symbol_bonus[spath]])
		parts.append("符号:" + "/".join(sp))
	if controller.run_shield_next > 0:
		parts.append("下房盾+%d" % controller.run_shield_next)
	run_label.text = "本局加成: " + ("无" if parts.is_empty() else " / ".join(parts))
	if controller.enemy_intent.is_empty():
		enemy_intent_label.text = "意图: —"
	else:
		var t = controller.enemy_intent["type"]
		match t:
			"attack": enemy_intent_label.text = "意图: ⚔ 攻击 %d" % controller.enemy_intent["value"]
			"heavy":  enemy_intent_label.text = "意图: 💥 重击 %d" % controller.enemy_intent["value"]
			"jam":    enemy_intent_label.text = "意图: ☣ 注废（可净化）"
			"lock":   enemy_intent_label.text = "意图: 🔒 锁轮（可净化）"
			"chaos":  enemy_intent_label.text = "意图: 🌀 乱权（可净化）"
			"none":   enemy_intent_label.text = "意图: ✔ 已净化(无)"
			_:        enemy_intent_label.text = "意图: —"


func _show_overlay(title: String, btn_text: String) -> void:
	overlay_label.text = title
	overlay_button.text = btn_text
	overlay.visible = true


func _hide_overlay() -> void:
	overlay.visible = false


func _log(msg: String) -> void:
	controller.logs.push_front(msg)
	if controller.logs.size() > 10:
		controller.logs.pop_back()
	if log_label != null:
		log_label.text = "\n".join(controller.logs)
