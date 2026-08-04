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
const META_SCENE = preload("res://scenes/ui/meta_screen.tscn")
const REWARD_SCENE = preload("res://scenes/ui/reward_screen.tscn")
const ANVIL_SCENE = preload("res://scenes/ui/anvil_screen.tscn")
const SHOP_SCENE = preload("res://scenes/ui/shop_screen.tscn")
const LOADOUT_SCENE = preload("res://scenes/ui/loadout_screen.tscn")

var controller   # DuelController 引用（运行时由 _ready 设置）

# ---- 意图信号（HUD → controller，单向数据流；P2 解耦）----
# HUD 只发「用户想做什么」，不调用 controller 私有方法、不读 controller 字段名。
signal spin_requested                         # 点击「旋转」按钮
signal reel_clicked(col: int)                # 点击某一列转轮
signal buy_requested(offer: Dictionary)      # 商店购入
signal sell_requested(uid_or_path: String, kind: String)  # 卖出（消耗品按 uid，其余按 path）
signal reward_chosen(id: String)             # 房奖励三选一
signal boss_reward_chosen(cand: Dictionary)  # BOSS 战利品三选一
signal reward_skip_requested                 # 跳过房奖励

# ---- 公开语义接口（controller → HUD 单向调用，替代直接戳私有节点/字段；P2 解耦）----
func build_all() -> void:
	_build_ui()
	_build_loadout_screen()
	_build_reward_screen()
	_build_anvil_screen()
	_build_shop_screen()
	_build_meta_screen()
	_show_loadout_screen()

func set_reel_enabled(reel: int, enabled: bool) -> void:
	if cells.size() > reel and cells[reel].size() > 0:
		cells[reel][0].disabled = not enabled

func hide_reward_screen() -> void: reward_screen.hide()
func hide_meta_screen() -> void: meta_screen.hide()
func hide_shop_screen() -> void: shop_screen.hide()
func hide_anvil_screen() -> void: anvil_screen.hide()

# ---- UI 节点引用 ----
var cells = []   # 展示用 Button 引用 [reel][row]
var cell_badges = []   # 每格右上角匹配角标 Label 引用 [reel][row]
var loadout_screen                     # 整备覆盖层（loadout_screen.tscn 实例）
var reward_screen                       # 奖励三选一覆盖层（reward_screen.tscn 实例）
var meta_screen                         # 每局结束元进度三选一覆盖层（meta_screen.tscn 实例）

var shop_screen                         # 商店覆盖层（shop_screen.tscn 实例）
var anvil_screen                        # 铁砧锻造覆盖层（anvil_screen.tscn 实例）

# ---- 主 HUD 静态节点（P3b-1）：battle_hud.tscn 编辑器提供，脚本按节点路径引用 ----
# 注：手写 .tscn 的 %Name 唯一名在含 instance= 覆盖节点的场景里注册不可靠，
#     故改用确定性 $节点路径（.tscn 结构改动时同步更新此处路径）。
@onready var grid_container = $Margin/Content/MainRow/CenterCol/ReelCenter/GridContainer
@onready var log_label = $Margin/Content/MainRow/EnemyPanel/VBox/LogScroll/LogLabel
@onready var log_scroll = $Margin/Content/MainRow/EnemyPanel/VBox/LogScroll
@onready var player_hp_label = $Margin/Content/MainRow/PlayerPanel/VBox/PlayerHpLabel
@onready var player_shield_label = $Margin/Content/MainRow/PlayerPanel/VBox/PlayerShieldLabel
@onready var player_buff_label = $Margin/Content/MainRow/PlayerPanel/VBox/PlayerBuffLabel
@onready var enemy_name_label = $Margin/Content/MainRow/EnemyPanel/VBox/EnemyNameLabel
@onready var boss_badge = $Margin/Content/MainRow/EnemyPanel/VBox/BossBadge
@onready var enemy_hp_label = $Margin/Content/MainRow/EnemyPanel/VBox/EnemyHpLabel
@onready var enemy_armor_label = $Margin/Content/MainRow/EnemyPanel/VBox/EnemyArmorLabel
@onready var enemy_intent_label = $Margin/Content/MainRow/CenterCol/IntentBox/EnemyIntentLabel
@onready var enemy_status_label = $Margin/Content/MainRow/CenterCol/IntentBox/EnemyStatusLabel
@onready var dmg_breakdown_box = $Margin/Content/MainRow/CenterCol/DmgBreakdownBox
@onready var dmg_breakdown_label = $Margin/Content/MainRow/CenterCol/DmgBreakdownBox/DmgBreakdownLabel
@onready var legend_box = $Margin/Content/MainRow/CenterCol/LegendBox
@onready var legend_container = $Margin/Content/MainRow/CenterCol/LegendBox/LegendContainer
@onready var player_panel = $Margin/Content/MainRow/PlayerPanel
@onready var enemy_panel = $Margin/Content/MainRow/EnemyPanel
@onready var loadout_label = $Margin/Content/LoadoutLabel
@onready var room_label = $Margin/Content/InfoBar/RoomLabel
@onready var turn_label = $Margin/Content/InfoBar/TurnLabel
@onready var run_label = $Margin/Content/InfoBar/RunLabel
@onready var gold_label = $Margin/Content/MainRow/PlayerPanel/VBox/GoldLabel
@onready var purify_label = $Margin/Content/BottomBar/PurifyLabel

# 覆盖层 / tooltip / popup（P3b-1 仍代码构建，后续 P3b-2 抽独立 .tscn）
var overlay
var overlay_label
var overlay_button
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
	# 主 HUD 静态骨架（背景/标题/信息栏/三栏/底部栏）已由 battle_hud.tscn 编辑器提供，
	# 这里仅做动态内容：转轮格子创建 + 底部按钮信号连接 + 飘字/tooltip 浮层。

	# 转轮格子：GridContainer 由 .tscn 提供，按 REELS×ROWS 实例化 symbol_cell。
	grid_container.columns = controller.state.REELS
	for reel in controller.state.REELS:
		cells.append([])
		controller.grid.append([])
		cell_badges.append([])
		for row in controller.state.ROWS:
			var cell = SYMBOL_CELL.instantiate()
			cell.custom_minimum_size = Vector2(84, 84)
			cell.add_theme_font_size_override("font_size", TypeScale.REEL)
			cell.disabled = true   # 无锁定，格子仅作展示
			cell.mouse_default_cursor_shape = Control.CURSOR_HELP   # Phase 3：悬停提示
			cell.mouse_filter = Control.MOUSE_FILTER_STOP
			cell.connect("mouse_entered", _on_cell_hover.bind(reel, row))
			cell.connect("mouse_exited", _on_cell_unhover)
			cell.pressed.connect(reel_clicked.emit.bind(reel))
			grid_container.add_child(cell)
			cells[reel].append(cell)
			controller.grid[reel].append(TRASH_SYMBOL)
			# 匹配角标（右上角锚定，封装在 symbol_cell.tscn 的 Badge 子节点）
			var badge = cell.get_node("Badge")
			cell_badges[reel].append(badge)

	# 底部操作栏按钮：由 .tscn 提供，这里连信号与快捷键。
	var spin_btn = $Margin/Content/BottomBar/SpinButton
	var purify_btn = $Margin/Content/BottomBar/PurifyButton
	var reload_btn = $Margin/Content/BottomBar/ReloadButton
	var reset_btn = $Margin/Content/BottomBar/ResetButton
	spin_btn.pressed.connect(spin_requested.emit)
	purify_btn.shortcut = _make_shortcut(KEY_P, true)
	purify_btn.connect("pressed", controller._on_purify_pressed)
	reload_btn.shortcut = _make_shortcut(KEY_E, true)
	reload_btn.connect("pressed", controller._on_reload_loadout_pressed)
	reset_btn.shortcut = _make_shortcut(KEY_R, true)
	reset_btn.connect("pressed", controller._full_reset)
	controller.consumable_panel = $Margin/Content/BottomBar/ConsumablePanel

	_build_overlay()
	# Phase 3：键盘焦点链（Tab/方向键可在底部操作间移动）
	_chain_focus([spin_btn, purify_btn, reload_btn, reset_btn])
	# Phase 3：悬停 tooltip 与飘字对象池浮层
	_build_symbol_tooltip()
	_build_popup_layer()

func _build_loadout_screen() -> void:
	loadout_screen = LOADOUT_SCENE.instantiate()
	add_child(loadout_screen)   # 必须先入树：configure 内访问 @onready 节点
	loadout_screen.configure(controller, self)
	loadout_screen.hide()


func _item_pool_of(category: String) -> Array:
	var out := []
	for p in controller.state.ITEM_POOL:
		var d = load(p)
		if d is ItemData and d.category == category:
			out.append(p)
	return out


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
			if wd != null and wd.symbols != null and not wd.symbols.is_empty():
				var parts := []
				for sw in wd.symbols:
					if sw == null or sw.symbol == null:
						continue
					parts.append("%s×%d" % [sw.symbol.label, int(sw.weight)])
				line1 = " ".join(parts)
			# P5：整备屏显示强度轴（攻击力 + 命中率 + 特殊符号），让玩家理解「稀有度→强度」
			var sp_name := "无"
			if wd != null and wd.symbols != null:
				for sw in wd.symbols:
					if sw != null and sw.symbol != null and sw.symbol.kind == "special":
						sp_name = sw.symbol.name
						break
			line2 = "攻击力 %d · 命中 %.0f%% · 特殊 %s" % [int(wd.base_power), wd.hit_rate * 100.0, sp_name]
	elif kind == "skill":
		name = data.buff_name if (data != null) else path.get_file().get_basename()
		if data != null:
			line1 = "%s %s" % [data.icon, data.description]
			# P5：技能同样显示强度轴（攻击力 + 命中率）
			var sym_txt := "无符号"
			if data.symbol != null:
				sym_txt = "符号 %s×%d · 持续 %d 回合" % [data.symbol.label, int(data.weight), data.symbol.buff_turns]
			line2 = "攻击力 %d · 命中 %.0f%% · %s" % [int(data.base_power), data.hit_rate * 100.0, sym_txt]
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


# 整备屏已抽独立 loadout_screen.tscn（P3b-2）；以下仅保留薄包装，
# 供 duel_controller 按原接口调用，实际逻辑在 loadout_screen.gd。
func _show_loadout_screen() -> void:
	loadout_screen.show_screen()

func _hide_loadout_screen() -> void:
	loadout_screen.hide()

func _update_loadout_cards_visual() -> void:
	loadout_screen._update_loadout_cards_visual()

func _update_loadout_count() -> void:
	loadout_screen._update_loadout_count()

func _update_loadout_anvil() -> void:
	loadout_screen._update_loadout_anvil()


func _build_reward_screen() -> void:
	reward_screen = REWARD_SCENE.instantiate()
	add_child(reward_screen)   # 必须先入树：configure 内访问 @onready 节点
	reward_screen.configure(controller, self)
	reward_screen.hide()


func _show_reward_screen(is_boss: bool) -> void:
	reward_screen.show_screen(is_boss)


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
	btn.pressed.connect(reward_chosen.emit.bind(rw.id))
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
	btn.pressed.connect(boss_reward_chosen.emit.bind(cand))
	return btn


# ---------------------------------------------------------------------------
# 每局结束元进度三选一（膨胀双轨：武器 base 线性 × 护符乘数增值，持久跨局）
# ---------------------------------------------------------------------------
func _build_meta_screen() -> void:
	meta_screen = META_SCENE.instantiate()
	add_child(meta_screen)   # 必须先入树：configure 内访问 @onready 节点
	meta_screen.configure(controller, self)
	meta_screen.hide()


func _show_meta_choice() -> void:
	meta_screen.show_choice()


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
	shop_screen = SHOP_SCENE.instantiate()
	add_child(shop_screen)   # 必须先入树：configure 内访问 @onready 节点
	shop_screen.configure(controller, self)
	shop_screen.hide()


func _show_shop_screen() -> void:
	shop_screen.show_screen()


func _refresh_shop() -> void:
	shop_screen.refresh()


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
	var cap = controller.state.CONSUMABLE_CAP if is_active else controller._cat_max(offer["kind"])          # 消耗品按腰带总容量 4；其余按整备上限
	var cur = controller.state.consumable_slots.size() if is_active else controller._sel_arr(offer["kind"]).size()   # 消耗品按腰带实占数
	var can_grow_slot = (not is_active) and controller._can_grow_slot(offer["kind"])   # 消耗品不「开槽」、仅追加腰带格
	var slot_full = (cur >= cap) and not can_grow_slot
	var can_buy = (not offer["sold"]) and controller.state.gold >= price and not slot_full
	var status: String
	if offer["sold"]:
		status = "已购入"
	elif controller.state.gold < price:
		status = "金币不足"
	elif slot_full:
		var cap_txt = controller.state.CONSUMABLE_CAP if is_active else controller._cap_text(offer["kind"])
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
	btn.pressed.connect(buy_requested.emit.bind(offer))
	return btn


# 商店「卖出」区：四列列出已持有物品，点击回收约50%金币并释放槽位
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



func _make_upgrade_card(u: Dictionary) -> Button:
	var btn = UI_BUTTON.instantiate()
	btn.custom_minimum_size = Vector2(150, 104)
	btn.text = ""
	var cc = CenterContainer.new()
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.add_child(cc)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	cc.add_child(vb)
	vb.add_child(_label("%s %s Lv%d/%d" % [u["icon"], u["name"], u["level"], u["max"]], 12))
	var dl = _label(u["desc"], TypeScale.TINY)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dl.custom_minimum_size = Vector2(140, 0)
	vb.add_child(dl)
	var status = "已满级" if u["maxed"] else ("%d 金" % u["cost"])
	var pl = _label(status, TypeScale.TINY)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.add_theme_color_override("font_color", Palette.MUTED_DIM if u["maxed"] else (Palette.ACCENT_GOLD if u["can_afford"] else Palette.ENEMY))
	vb.add_child(pl)
	btn.disabled = (u["maxed"] or not u["can_afford"])
	btn.connect("pressed", controller._on_gold_upgrade_pressed.bind(u["id"]))
	return btn


func _build_anvil_screen() -> void:
	anvil_screen = ANVIL_SCENE.instantiate()
	add_child(anvil_screen)   # 必须先入树：configure 内访问 @onready 节点
	anvil_screen.configure(controller, self)
	anvil_screen.hide()


func _show_anvil_screen() -> void:
	anvil_screen.show_screen()


func _refresh_anvil() -> void:
	anvil_screen.refresh()


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


# 读某格的「有效元素」——即符号继承武器 element 之后的结果（controller.state.grid_elem）。
# 注意：不能读 SymbolData.element（符号原生元素）。共享 .tres（如 slash）在火剑下
# 有效元素是 fire、在铁剑下是 none，只有 grid_elem 与 _contribute 的结算口径一致。
func _cell_element(reel: int, row: int) -> String:
	if controller == null:
		return "none"
	if controller.state.grid_elem.size() <= reel:
		return "none"
	if controller.state.grid_elem[reel].size() <= row:
		return "none"
	return controller.state.grid_elem[reel][row]


func _on_cell_hover(reel: int, row: int) -> void:
	if symbol_tooltip == null or controller == null:
		return
	if controller.state.grid.size() <= reel or controller.state.grid[reel].size() <= row:
		return
	var s: SymbolData = controller.state.grid[reel][row]
	# S1 修复：原先读 s.element（符号原生元素），火剑的斩击会显示"无属性"，
	# 而结算按 fire 吃 ×1.5——tooltip 与实际伤害对不上。改读有效元素。
	var elem = _cell_element(reel, row)
	var rel = ElementCounter.relation(elem, controller.state.enemy_element)
	var rel_mult = ElementCounter.multiplier(elem, controller.state.enemy_element)
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
	for reel in controller.state.REELS:
		for row in controller.state.ROWS:
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
		for reel in controller.state.REELS:
			for row in controller.state.ROWS:
				if controller.state.grid[reel][row] == s:
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
	var eelem: String = controller.state.enemy_element
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
	for p in controller.state.pool:
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
	for p in controller.state.pool:
		var pelem: String = p[2] if p.size() > 2 else "none"
		ids.append(p[0].resource_path + "|" + pelem)
	ids.sort()
	return "%s|%s" % [",".join(ids), controller.state.enemy_element]


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
	var s: SymbolData = controller.state.grid[reel][row]
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
	loadout_label.text = "已装备: " + ("/".join(controller.state.loadout_names) if not controller.state.loadout_names.is_empty() else "—")
	var is_boss = controller._is_boss_room(controller.state.room_index)
	room_label.text = "房间: %d/%d%s" % [controller.state.room_index + 1, controller.state.ROOMS.size(), " · ★BOSS" if is_boss else ""]
	turn_label.text = "回合: %d" % controller.state.turn_count
	player_hp_label.text = "HP %d/%d" % [controller.state.player_hp, controller.state.player_hp_max]
	player_shield_label.text = "护盾 %d" % controller.state.player_shield
	player_buff_label.text = "【转轮】技能: " + controller._buff_summary()
	gold_label.text = "金币 %d" % controller.state.gold
	enemy_name_label.text = controller.state.enemy_name
	boss_badge.visible = is_boss
	enemy_hp_label.text = "HP %d/%d" % [max(controller.state.enemy_hp, 0), controller.state.enemy_hp_max]
	# 护甲（扁平池）：有护甲才显示；破甲后剩 0 也显示（提示已破甲窗口），仅无护甲敌人隐藏
	enemy_armor_label.visible = controller.state.enemy_armor_max > 0
	enemy_armor_label.text = "护甲 %d/%d" % [max(controller.state.enemy_armor, 0), controller.state.enemy_armor_max]
	enemy_status_label.text = "状态: " + ("无" if controller.state.enemy_status.is_empty() else controller._status_summary(controller.state.enemy_status))
	purify_label.text = "%d/%d" % [controller.state.purify_charges, controller.state.purify_max_base]
	# M4+M6 本局加成概览
	var parts := []
	if controller.state.run_power_bonus + controller.state.charm_power_bonus > 0:
		parts.append("伤害+%d" % (controller.state.run_power_bonus + controller.state.charm_power_bonus))
	# 护符乘区（damage_mult 类型，如 rage_charm ×1.5）此前漏显示 → 带乘区护符时概览空显示"无"
	if controller.state.charm_damage_mult != 1.0:
		parts.append("护符×%s" % ElementCounter.fmt_mult(controller.state.charm_damage_mult))
	if controller.state.purify_max_base > 0:
		parts.append("净化上限%d" % controller.state.purify_max_base)
	if controller.state.charm_room_shield > 0:
		parts.append("护盾+%d" % controller.state.charm_room_shield)
	if controller.state.charm_interf_resist > 0:
		parts.append("抗扰+%d" % controller.state.charm_interf_resist)
	if not controller.state.run_symbol_bonus.is_empty():
		var sp := []
		for spath in controller.state.run_symbol_bonus.keys():
			var sym: SymbolData = load(spath)
			sp.append("%s+%d" % [sym.name, controller.state.run_symbol_bonus[spath]])
		parts.append("符号:" + "/".join(sp))
	if controller.state.run_shield_next > 0:
		parts.append("下房盾+%d" % controller.state.run_shield_next)
	run_label.text = "本局加成: " + ("无" if parts.is_empty() else " / ".join(parts))
	if controller.state.enemy_intent.is_empty():
		enemy_intent_label.text = "意图: —"
	else:
		var t = controller.state.enemy_intent["type"]
		match t:
			"attack": enemy_intent_label.text = "意图: ⚔ 攻击 %d" % controller.state.enemy_intent["value"]
			"heavy":  enemy_intent_label.text = "意图: 💥 重击 %d" % controller.state.enemy_intent["value"]
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
	controller.state.logs.push_front(msg)
	if controller.state.logs.size() > 10:
		controller.state.logs.pop_back()
	if log_label != null:
		log_label.text = "\n".join(controller.state.logs)
