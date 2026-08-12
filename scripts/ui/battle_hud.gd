extends Control
class_name BattleHud
# BattleHud — 老虎机对决的常驻 HUD 与全屏子界面（Phase 2 关注点分离）
# 由 duel_controller.gd 抽出：所有 UI 构建/刷新/飘字/图例。控制器只保留战斗逻辑，
# 通过 controller 引用回 DuelController 的游戏状态与逻辑方法。

const TRASH_SYMBOL = preload("res://resources/symbols/trash.tres")
const DEFAULT_ENEMY_TEXTURE = preload("res://assets/enemy.png")   # 默认敌人立绘（RoomData.art 为空时使用）
const ENEMY_SPRITE_SIZE := Vector2(44, 60)    # 敌人立绘基础容器尺寸（stretch KEEP_ASPECT → 渲染 44×44，与玩家同规格）
const UI_BUTTON = preload("res://scenes/ui/ui_button.tscn")
const ITEM_CARD = preload("res://scenes/ui/item_card.tscn")
const UI_PANEL = preload("res://scenes/ui/ui_panel.tscn")
const SYMBOL_CELL = preload("res://scenes/ui/symbol_cell.tscn")
const Screen = preload("res://scripts/ui/screen.gd")
const META_SCENE = preload("res://scenes/ui/meta_screen.tscn")
const REWARD_SCENE = preload("res://scenes/ui/reward_screen.tscn")
const ANVIL_SCENE = preload("res://scenes/ui/anvil_screen.tscn")
const SHOP_SCENE = preload("res://scenes/ui/shop_screen.tscn")
const LOADOUT_SCENE = preload("res://scenes/ui/loadout_scene.tscn")
const TRAIN_SCENE = preload("res://scenes/ui/train_screen.tscn")   # T28 训练房

var controller   # DuelController 引用（运行时由 _ready 设置）

# ---- 意图信号（HUD → controller，单向数据流；P2 解耦）----
# HUD 只发「用户想做什么」，不调用 controller 私有方法、不读 controller 字段名。
signal spin_requested                         # 点击「旋转」按钮
signal reel_clicked(col: int)                # 点击某一列转轮
# @warning_ignore 以下信号由子屏（shop_screen/anvil_screen/train_screen/reward_screen）emit、
# controller connect——跨文件连接，静态分析器误报 UNUSED_SIGNAL。
@warning_ignore("unused_signal")
signal buy_requested(offer: Dictionary)      # 商店购入
@warning_ignore("unused_signal")
signal sell_requested(uid_or_path: String, kind: String)  # 卖出（消耗品按 uid，其余按 path）
signal reward_chosen(id: String)             # 房奖励三选一
signal boss_reward_chosen(cand: Dictionary)  # BOSS 战利品三选一
@warning_ignore("unused_signal")
signal reward_skip_requested                 # 跳过房奖励
signal shop_requested                          # 🛒 打开商店（房间歇态 opt-in）
signal next_room_requested                     # ▶ 下一房（房间歇态）
signal card_toggled(card: Dictionary)         # 整备卡片勾选
signal meta_choice_chosen(opt: Dictionary)    # 局末元进度三选一
signal gold_upgrade_requested(id: String)     # 商店金币升级
signal overlay_button_pressed                 # 失败弹层按钮（回整备）
signal consumable_used(uid: String)           # 使用腰带消耗品
@warning_ignore("unused_signal")
signal shop_leave_requested                   # 离开商店（回房间歇态）
@warning_ignore("unused_signal")
signal anvil_back_requested                   # 铁砧返回整备
@warning_ignore("unused_signal")
signal train_continue_requested               # T28 训练房「继续」→ 推进下一房/元进度
signal shop_card_pressed(offer: Dictionary)   # 商店卡片点击（shop_screen 拦截：武器满 2 弹替换）
@warning_ignore("unused_signal")
signal buy_replace_requested(offer: Dictionary, old_path: String)   # 替换购买（2026-08-07：武器槽上限 2 后的换装）
@warning_ignore("unused_signal")
signal shop_reroll_requested                   # 商店货架刷新（2026-08-09：Balatro 式递增价 + 每房间歇期限次）

# ---- 公开语义接口（controller → HUD 单向调用，替代直接戳私有节点/字段；P2 解耦）----
func build_all() -> void:
	_build_ui()
	_build_loadout_screen()
	_build_reward_screen()
	_build_anvil_screen()
	_build_shop_screen()
	_build_meta_screen()
	_build_train_screen()
	_show_loadout_screen()

func set_reel_enabled(reel: int, enabled: bool) -> void:
	if cells.size() > reel and cells[reel].size() > 0:
		cells[reel][0].disabled = not enabled


func set_interroom_enabled(on: bool) -> void:
	if interroom_shop_btn != null:
		interroom_shop_btn.disabled = not on
	if interroom_next_btn != null:
		interroom_next_btn.disabled = not on
	# 下一房预告横幅：间歇态点亮（内容随当前房推进刷新），战斗隐藏
	if on:
		_refresh_next_room_bar()
	elif next_room_bar != null:
		next_room_bar.visible = false


# 2026-08-09 下一房预告（L2 分级）：房型 + 敌人名 + 元素 + BOSS 机制图标。
# 隐秘 BOSS（boss_role=hidden）幕内全清前不剧透 → ？？？；最后一房（通关整局）无下一房 → 隐藏。
func _refresh_next_room_bar() -> void:
	if next_room_bar == null or controller == null:
		return
	var rooms: Array = controller.state.ROOMS
	var idx: int = controller.state.room_index
	if idx + 1 >= rooms.size():
		next_room_bar.visible = false
		return
	var r: RoomData = rooms[idx + 1]
	if r.boss_role == "hidden":
		next_room_bar.text = "▶ 下一房：？？？（隐秘 · 条件解锁）"
		next_room_bar.visible = true
		return
	var kind_txt: String = {"normal": "普通", "elite": "精英", "boss": "★BOSS"}.get(r.kind, r.kind)
	var icon := ""
	if r.kind == "boss" and r.gimmick_script != null:
		icon = String(r.gimmick_script.get_script_constant_map().get("ICON", ""))
	next_room_bar.text = "▶ 下一房：%s（%s · %s%s）" % [r.name, ElementCounter.label(r.element), kind_txt, " " + icon if icon != "" else ""]
	next_room_bar.visible = true

func hide_reward_screen() -> void: reward_screen.hide_screen()
func hide_meta_screen() -> void: meta_screen.hide_screen()
func hide_shop_screen() -> void: shop_screen.hide_screen()
func shop_screen_is_open() -> bool:
	if shop_screen == null:
		return false
	return shop_screen.is_shown()
func set_shop_button_text(t: String) -> void:
	if interroom_shop_btn != null:
		interroom_shop_btn.text = t
func hide_anvil_screen() -> void: anvil_screen.hide_screen()

# ---- UI 节点引用 ----
var cells = []   # 展示用 Button 引用 [reel][row]
var cell_badges = []   # 每格右上角匹配角标 Label 引用 [reel][row]
var loadout_screen                     # 整备场景（scenes/ui/loadout_scene.tscn 实例，hud 兄弟节点）
# 消耗品腰带 4 个固定格子（2x2），由 hud._refresh_consumable_panel 同步状态；
# consumable_panel 字段（controller 持有）已废弃，HUD 内聚管理 cell。
# 位置：左栏 PlayerPanel/VBox（GearBox 之后、PlayerBuffLabel 之前），保持 4 格子 2x2 形态
# 与 CONSUMABLE_CAP=4 对齐，玩家一眼能数清剩余消耗品。
@onready var consumable_cells: Array = [
	$Margin/Content/MainRow/PlayerPanel/VBox/ConsumablePanel/Cell1,
	$Margin/Content/MainRow/PlayerPanel/VBox/ConsumablePanel/Cell2,
	$Margin/Content/MainRow/PlayerPanel/VBox/ConsumablePanel/Cell3,
	$Margin/Content/MainRow/PlayerPanel/VBox/ConsumablePanel/Cell4,
]
var reward_screen                       # 奖励三选一覆盖层（reward_screen.tscn 实例）
var meta_screen                         # 每局结束元进度三选一覆盖层（meta_screen.tscn 实例）
var train_screen                        # T28 训练房覆盖层（train_screen.tscn 实例）

var shop_screen                         # 商店覆盖层（shop_screen.tscn 实例）
var anvil_screen                        # 铁砧锻造覆盖层（anvil_screen.tscn 实例）

# 房间歇态按钮（opt-in 商店 + 下一房）：静态节点在 battle_hud.tscn InfoBar，默认禁用，间歇态由 controller 点亮
@onready var interroom_shop_btn = $Margin/Content/InfoBar/ShopBtn
@onready var interroom_next_btn = $Margin/Content/InfoBar/NextRoomBtn
# 2026-08-09 下一房预告横幅：仅房间歇态显示（购买/腰带决策窗口），战斗隐藏零常驻占位
@onready var next_room_bar = $Margin/Content/NextRoomBar

# ---- 主 HUD 静态节点（P3b-1）：battle_hud.tscn 编辑器提供，脚本按节点路径引用 ----
# 注：手写 .tscn 的 %Name 唯一名在含 instance= 覆盖节点的场景里注册不可靠，
#     故改用确定性 $节点路径（.tscn 结构改动时同步更新此处路径）。
@onready var grid_container = $Margin/Content/MainRow/CenterStage/ReelDock/TopRow/ReelCenter/GridContainer
@onready var player_hp_label = $Margin/Content/MainRow/PlayerPanel/VBox/PlayerHpLabel
@onready var weapons_row = $Margin/Content/MainRow/PlayerPanel/VBox/GearBox/WeaponsRow
@onready var charms_row = $Margin/Content/MainRow/PlayerPanel/VBox/GearBox/CharmsRow
@onready var skills_row = $Margin/Content/MainRow/PlayerPanel/VBox/GearBox/SkillsRow
@onready var player_buff_label = $Margin/Content/MainRow/PlayerPanel/VBox/PlayerBuffLabel
@onready var enemy_name_label = $Margin/Content/MainRow/EnemyPanel/VBox/EnemyNameLabel
@onready var boss_badge = $Margin/Content/MainRow/EnemyPanel/VBox/BossBadge
@onready var enemy_hp_label = $Margin/Content/MainRow/EnemyPanel/VBox/EnemyHpLabel
@onready var enemy_armor_label = $Margin/Content/MainRow/EnemyPanel/VBox/EnemyArmorLabel
@onready var enemy_intent_label = $Margin/Content/MainRow/EnemyPanel/VBox/EnemyIntentLabel
@onready var enemy_status_label = $Margin/Content/MainRow/EnemyPanel/VBox/EnemyStatusLabel
@onready var enemy_charge_label = $Margin/Content/MainRow/EnemyPanel/VBox/EnemyChargeLabel
@onready var enemy_element_label = $Margin/Content/MainRow/EnemyPanel/VBox/EnemyElementLabel
@onready var enemy_weak_label = $Margin/Content/MainRow/EnemyPanel/VBox/EnemyWeakLabel
@onready var enemy_resist_label = $Margin/Content/MainRow/EnemyPanel/VBox/EnemyResistLabel
@onready var player_sprite = $Margin/Content/MainRow/CenterStage/StageRow/PlayerCenter/PlayerSprite
@onready var enemy_sprite = $Margin/Content/MainRow/CenterStage/StageRow/EnemyCenter/EnemySprite
@onready var player_panel = $Margin/Content/MainRow/PlayerPanel
@onready var enemy_panel = $Margin/Content/MainRow/EnemyPanel
@onready var room_label = $Margin/Content/InfoBar/RoomLabel
@onready var turn_label = $Margin/Content/InfoBar/TurnLabel
@onready var run_label = $Margin/Content/InfoBar/RunLabel
@onready var gold_label = $Margin/Content/MainRow/PlayerPanel/VBox/GoldLabel

var animator = null   # P4 战斗动画器（tween 驱动立绘演出），_build_ui 末尾创建

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

func _label(text: String, font_size: int = TypeScale.BODY) -> Label:
	var l = Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font_size > 0:
		l.add_theme_font_size_override("font_size", font_size)
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
			cell.custom_minimum_size = Vector2(32, 32)
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

	# 底部操作栏按钮（SpinBar 在转轮下方居中）：由 .tscn 提供，这里连信号与快捷键。
	# 注：原"重置"按钮（Ctrl+R → _full_reset 放弃整局重开）已删除——其为无确认的一键自毁本局陷阱，
	# 失败/通关均有正统出口：失败弹层→返回整备（重选装备开新 run）/ 通关弹层→开新 run，无需常驻按钮。
	var spin_btn = $Margin/Content/MainRow/CenterStage/ReelDock/SpinBar/SpinButton
	spin_btn.pressed.connect(spin_requested.emit)
	# 消耗品 4 格子：连信号（点击格子=使用该格消耗品）
	for i in range(consumable_cells.size()):
		consumable_cells[i].pressed.connect(_on_consumable_cell_pressed.bind(i))
	# 净化按钮已删除（净化完全走消耗品·净化药剂，charges 用尽即移出腰带）
	# 4 格子初次刷新（带空占位文案）
	_refresh_consumable_panel()

	_build_overlay()
	# Phase 3：键盘焦点链（Tab/方向键可在底部操作间移动；仅 SPIN）
	_chain_focus([spin_btn])
	# Phase 3：悬停 tooltip 与飘字对象池浮层
	_build_symbol_tooltip()
	_build_popup_layer()

	# 房间歇态按钮（opt-in 商店 + 下一房）：静态节点已在 battle_hud.tscn，这里只接信号
	interroom_shop_btn.connect("pressed", shop_requested.emit)
	interroom_next_btn.connect("pressed", next_room_requested.emit)

	# P4：战斗动画器挂在 hud 下，setup 时缓存 PlayerSprite/EnemySprite 节点
	animator = BattleAnimator.new()
	add_child(animator)
	animator.setup(self)

func _build_loadout_screen() -> void:
	# 纯 2D 整备场景（scenes/ui/loadout_scene.tscn）：作为 hud 的兄弟节点挂到 Duel 根，
	# 以便进入整备时 hud.hide() 隐藏 Game Boy 外框 + 战斗 HUD。布局可在编辑器里直接调。
	loadout_screen = LOADOUT_SCENE.instantiate()
	get_parent().add_child(loadout_screen)
	loadout_screen.configure(controller, self)
	loadout_screen.hide_screen()


func _item_pool_of(category: String) -> Array:
	var out := []
	for p in controller.state.ITEM_POOL:
		var d = load(p)
		if d is ItemData and d.category == category:
			out.append(p)
	return out


func _make_item_card(data: Resource, path: String, kind: String) -> Dictionary:
	# 重要：根节点是 Button（来自 ui_button.tscn），它只渲染自己 text 字段。
	# 之前 btn.add_child(VBox) 是被 Button 忽略的——必须用 \n 拼多行 + 紧凑 line_spacing。
	var btn = UI_BUTTON.instantiate()
	btn.custom_minimum_size = Vector2(0, 26)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_constant_override("line_spacing", 0)
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	btn.autowrap_mode = TextServer.AUTOWRAP_OFF
	btn.clip_text = true
	btn.text = ""
	var title := ""
	var line1 := ""   # 图标/核心信息
	var line2 := ""   # 数值/权重
	if kind == "weapon":
		title = data.weapon_name if (data != null) else path.get_file().get_basename()
		if data != null:
			var wd := data as WeaponData
			# line1 = 符号概览（主攻 + 特殊机制符号的 label，不显示权重——2026-08-07 重构后武器只带主攻+机制）
			if wd != null and wd.symbols != null and not wd.symbols.is_empty():
				var parts := []
				for sw in wd.symbols:
					if sw == null or sw.symbol == null:
						continue
					parts.append(sw.symbol.label)
				line1 = "⚔️ " + " ".join(parts)
			# line2 = 强度轴（2026-08-09 更新）：攻击力 · 元素 · 命中率 · 非三连暴击率 · 特殊机制（MISS 恢复后命中率复活）
			var elem_txt := "无"
			if wd != null and wd.element != "":
				elem_txt = ElementCounter.label(wd.element)
			var crit_total: int = int((controller.BALANCE.crit_chance + (wd.crit_chance if wd != null else 0.0)) * 100)
			var hit_pct: int = int((wd.hit_rate if wd != null else 1.0) * 100)
			var mech_name := "—"
			if wd != null and wd.symbols != null:
				for sw in wd.symbols:
					if sw == null or sw.symbol == null:
						continue
					if sw.symbol.kind == "special" or sw.symbol.kind == "status":
						mech_name = sw.symbol.name
						break
			line2 = "攻%d · %s · 命中%d%% · 暴%d%% · %s" % [int(wd.base_power), elem_txt, hit_pct, crit_total, mech_name]
	elif kind == "skill":
		title = data.buff_name if (data != null) else path.get_file().get_basename()
		if data != null:
			line1 = "%s %s" % [data.icon, data.description]
			# 技能强度轴（2026-08-09 更新）：攻击力 · 命中率 · 非三连暴击率 · 符号回合
			var sym_txt := "无符号"
			if data.symbol != null:
				sym_txt = "×%d·%dT" % [int(data.weight), data.symbol.buff_turns]
			var s_crit: int = int((controller.BALANCE.crit_chance + data.crit_chance) * 100)
			var s_hit: int = int(data.hit_rate * 100)
			line2 = "攻%d · 命中%d%% · 暴%d%% · %s" % [int(data.base_power), s_hit, s_crit, sym_txt]
	else:
		title = data.item_name if (data != null) else path.get_file().get_basename()
		if data != null:
			line1 = "%s %s" % [data.icon, data.description]
			line2 = "持有 %d" % data.charges if (kind == "active" and data.get("charges") != null) else "被动"

	title = _source_tag(kind) + title
	# Button 多行：title(line1)line2。靠 \n 排版；首行用 BBCode 强调名字(可选)
	var body := title
	if line1 != "":
		body += "\n" + line1
	if line2 != "":
		body += "\n" + line2
	btn.text = body
	var card := {"path": path, "btn": btn, "selected": false, "kind": kind}
	btn.connect("pressed", card_toggled.emit.bind(card))
	return card


# 整备屏已抽为纯 2D 场景 loadout_scene.gd（q-0）；以下仅保留薄包装，
# 供 duel_controller 按原接口调用，实际逻辑在 loadout_scene.gd。
func _show_loadout_screen() -> void:
	loadout_screen.show_screen()

func _hide_loadout_screen() -> void:
	loadout_screen.hide_screen()

func _update_loadout_cards_visual() -> void:
	loadout_screen._update_loadout_cards_visual()

func _update_loadout_count() -> void:
	loadout_screen._update_loadout_count()

func _update_loadout_anvil() -> void:
	loadout_screen._update_loadout_anvil()

func _refresh_loadout_cards() -> void:
	# 铁砧授予后 owned_* 变化：整备页开着则立即重建副屏；隐藏则下次 show_screen 自动重建
	if loadout_screen != null and loadout_screen.visible:
		loadout_screen.refresh_data()


func _build_reward_screen() -> void:
	reward_screen = REWARD_SCENE.instantiate()
	add_child(reward_screen)   # 必须先入树：configure 内访问 @onready 节点
	reward_screen.configure(controller, self)
	reward_screen.hide_screen()


func _show_reward_screen(is_boss: bool) -> void:
	reward_screen.show_screen(is_boss)


func _make_reward_card(rw: RewardData) -> Button:
	var card: ItemCard = ITEM_CARD.instantiate()
	card.custom_minimum_size = Vector2(84, 60)
	card.configure("%s %s" % [rw.icon, rw.label], rw.desc)
	card.set_art(rw.art)
	card.pressed.connect(reward_chosen.emit.bind(rw.id))
	return card


# BOSS 战利品卡（候选为 dict，点击调 _on_boss_reward_chosen；完整说明进 tooltip，卡片只放短文案）
func _make_boss_reward_card(cand: Dictionary) -> Button:
	var card: ItemCard = ITEM_CARD.instantiate()
	card.custom_minimum_size = Vector2(84, 60)
	card.configure("%s %s" % [cand.get("icon", ""), cand.get("label", "")], cand.get("desc", ""))
	card.set_art(cand.get("art", null))
	card.tooltip_text = String(cand.get("tip", cand.get("desc", "")))
	card.pressed.connect(boss_reward_chosen.emit.bind(cand))
	return card


# ---------------------------------------------------------------------------
# 每局结束元进度三选一（膨胀双轨：武器 base 线性 × 护符乘数增值，持久跨局）
# ---------------------------------------------------------------------------
func _build_meta_screen() -> void:
	meta_screen = META_SCENE.instantiate()
	add_child(meta_screen)   # 必须先入树：configure 内访问 @onready 节点
	meta_screen.configure(controller, self)
	meta_screen.hide_screen()


# T28 训练房：BOSS 战后当场分配训练点（升级轨道唯一货币）
func _build_train_screen() -> void:
	train_screen = TRAIN_SCENE.instantiate()
	add_child(train_screen)   # 必须先入树：configure 内访问 @onready 节点
	train_screen.configure(controller, self)
	train_screen.hide_screen()


func _show_train_screen() -> void:
	train_screen.show_screen()


func hide_train_screen() -> void:
	train_screen.hide_screen()


func _show_meta_choice() -> void:
	meta_screen.show_choice()


func _make_meta_card(opt: Dictionary) -> Button:
	var card: ItemCard = ITEM_CARD.instantiate()
	card.custom_minimum_size = Vector2(130, 60)   # 仅 3 张、覆盖层空间充足，放大提升可读性
	card.configure("%s %s" % [opt.get("icon", ""), opt.get("label", "")], opt.get("desc", ""), TypeScale.META, 110.0)
	card.pressed.connect(meta_choice_chosen.emit.bind(opt))
	return card


func _build_shop_screen() -> void:
	shop_screen = SHOP_SCENE.instantiate()
	add_child(shop_screen)   # 必须先入树：configure 内访问 @onready 节点
	shop_screen.configure(controller, self)
	shop_screen.hide_screen()


func _show_shop_screen() -> void:
	shop_screen.show_screen()


func _refresh_shop() -> void:
	shop_screen.refresh()


func _make_shop_card(offer: Dictionary) -> Button:
	var card: ItemCard = ITEM_CARD.instantiate()
	card.custom_minimum_size = Vector2(0, 46)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var kind_name = {"weapon": "武器", "passive": "护符", "active": "物品", "skill": "技能"}.get(offer["kind"], "物品")
	card.configure("%s%s · %s" % [_source_tag(offer["kind"]), kind_name, offer["name"]], "", TypeScale.TITLE, 0.0, 2)
	card.set_tooltip(load(offer["path"]), offer["kind"])   # 物品悬停信息窗（ItemTooltip 生成器）
	var price = controller._shop_price(offer["kind"], -1, offer["path"])   # 价格随当前持有数递增 + 稀有度阶梯（T6/T21）；卖出回落，换装成本=买卖价差（防刷价）
	var is_active = (offer["kind"] == "active")
	var cap = controller.state.CONSUMABLE_CAP if is_active else controller._loadout_system.cat_max(offer["kind"])          # 消耗品按腰带总容量 4；其余按整备上限
	var cur = controller.state.consumable_slots.size() if is_active else controller._loadout_system.sel_arr(offer["kind"]).size()   # 消耗品按腰带实占数
	var can_grow_slot = (not is_active) and controller._loadout_system.can_grow_slot(offer["kind"])   # 消耗品不「开槽」、仅追加腰带格
	var slot_full = (cur >= cap) and not can_grow_slot
	# 2026-08-07 武器替换：武器槽满（上限 2）时可点——触发替换弹层（换装），不禁用
	var weapon_replace: bool = (offer["kind"] == "weapon" and cur >= cap and not can_grow_slot)
	if weapon_replace:
		slot_full = false
	var can_buy = (not offer["sold"]) and controller.state.gold >= price and not slot_full
	var status: String
	if offer["sold"]:
		status = "已购入"
	elif controller.state.gold < price:
		status = "金币不足"
	elif weapon_replace:
		status = "替换 %d 金" % price   # 槽满 2：点击弹替换选择（旧武器回收藏库）
	elif slot_full:
		var cap_txt = controller.state.CONSUMABLE_CAP if is_active else controller._loadout_system.cap_text(offer["kind"])
		status = "槽位已满 %d/%s" % [cur, cap_txt]
	elif cur >= cap:
		status = "开槽 %d 金" % price   # 本次购买会把该类槽 +1
	else:
		status = "%d 金" % price
	var col: Color = Palette.ACCENT_GOLD
	if offer["sold"]:
		col = Palette.MUTED_DIM
	elif not can_buy:
		col = Palette.ENEMY
	card.set_status(status, col)
	card.disabled = not can_buy
	card.pressed.connect(shop_card_pressed.emit.bind(offer))
	return card


# 商店「卖出」区：四列列出已持有物品，点击回收约50%金币并释放槽位
func _make_sell_card(title_text: String, sub_text: String, disabled: bool, cb: Callable, res: Resource = null) -> Button:
	var card: ItemCard = ITEM_CARD.instantiate()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 26)
	card.configure(title_text, sub_text, TypeScale.TINY)
	card.set_desc_color(Palette.ACCENT_GOLD if not disabled else Palette.MUTED_DIM)
	if res != null:
		card.set_tooltip(res)   # 物品悬停信息窗（ItemTooltip 生成器）
	card.disabled = disabled
	if not cb.is_null():
		card.pressed.connect(cb)
	return card


func _make_upgrade_card(u: Dictionary) -> Button:
	var card: ItemCard = ITEM_CARD.instantiate()
	card.custom_minimum_size = Vector2(0, 60)   # 训练房轨道卡：2行=60×2+6=126 ≤ 网格区131，不溢出
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.configure("%s %s" % [u["icon"], u["name"]], "", TypeScale.OVERLAY, 0.0, 6)
	var status = "已满级" if u["maxed"] else ("Lv%d/%d · %d点" % [u["level"], u["max"], u["cost"]])
	card.set_status(status, Palette.MUTED_DIM if u["maxed"] else (Palette.ACCENT_GOLD if u["can_afford"] else Palette.ENEMY))
	card.disabled = (u["maxed"] or not u["can_afford"])
	card.pressed.connect(gold_upgrade_requested.emit.bind(u["id"]))
	return card

func _build_anvil_screen() -> void:
	anvil_screen = ANVIL_SCENE.instantiate()
	add_child(anvil_screen)   # 必须先入树：configure 内访问 @onready 节点
	anvil_screen.configure(controller, self)
	anvil_screen.hide_screen()


func _show_anvil_screen() -> void:
	anvil_screen.show_screen()


func _build_overlay() -> void:
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var ov_v = Screen.build_centered(overlay, Palette.BG_OVERLAY, 18)
	overlay_label = _label("", TypeScale.REEL)
	ov_v.add_child(overlay_label)
	overlay_button = UI_BUTTON.instantiate()
	overlay_button.custom_minimum_size = Vector2(140, 28)
	overlay_button.add_theme_font_size_override("font_size", TypeScale.MEDIUM)
	overlay_button.connect("pressed", overlay_button_pressed.emit)
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
	sb.set_border_width_all(Palette.BORDER_WIDTH)
	sb.set_corner_radius_all(Palette.PANEL_RADIUS)
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
		symbol_tooltip_detail.text = "技能 · %s %s · 持续 %d 回合" % [controller.status_system.buff_effect_name(s.buff_effect), vtxt, s.buff_turns]
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
		if s == TRASH_SYMBOL or s.kind == "trash" or c < 2:   # trash/MISS 不显示匹配角标
			continue
		for reel in controller.state.REELS:
			for row in controller.state.ROWS:
				if controller.state.grid[reel][row] == s:
					cell_badges[reel][row].text = "×%d" % c


# 敌人元素 / 弱 / 抗：写入右侧 EnemyPanel 内三 Label（取代原底部 LegendBar）。
# 进入房间时由 duel_controller._begin_room 调一次；切换目标元素时无需重调。
func _update_enemy_element() -> void:
	if enemy_element_label == null:
		return
	var eelem: String = controller.state.enemy_element
	# 元素（始终显示，紧贴"敌人"标题）
	enemy_element_label.text = "%s" % ElementCounter.label(eelem)
	enemy_element_label.add_theme_color_override("font_color", ElementCounter.color(eelem))
	# 弱 / 抗：仅在有属性时显示（none 元素没有克制定义）；多元素用「·」拼接（v2 互克对+毒链）
	var ewk := ElementCounter.weakness(eelem)
	if ewk.is_empty():
		enemy_weak_label.visible = false
		enemy_resist_label.visible = false
	else:
		enemy_weak_label.visible = true
		var wk_names := []
		for e in ewk:
			wk_names.append(ElementCounter.label(e))
		enemy_weak_label.text = "弱 %s ×%s" % ["·".join(wk_names), ElementCounter.fmt_mult(ElementCounter.MULT_ADVANTAGE)]
		enemy_weak_label.add_theme_color_override("font_color", ElementCounter.color(ewk[0]))
		var ers := ElementCounter.resists(eelem)
		enemy_resist_label.visible = true
		var rs_names := []
		for e in ers:
			rs_names.append(ElementCounter.label(e))
		enemy_resist_label.text = "抗 %s ×%s" % ["·".join(rs_names), ElementCounter.fmt_mult(ElementCounter.MULT_RESIST)]
		enemy_resist_label.add_theme_color_override("font_color", ElementCounter.color(ers[0]))


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
	lbl.position = Vector2(gp.position.x - pr.position.x + gp.size.x * 0.5 - w * 0.5, gp.position.y - pr.position.y + 2)
	var tw = create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - 14, 0.8)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.8)
	tw.tween_callback(_return_popup.bind(lbl))


func _return_popup(lbl: Label) -> void:
	lbl.visible = false
	if not _popup_free.has(lbl):
		_popup_free.append(lbl)


func _player_sprite_anchor() -> Control:
	return player_sprite if player_sprite != null else player_panel


func _enemy_sprite_anchor() -> Control:
	return enemy_sprite if enemy_sprite != null else enemy_panel


# 敌人立绘切换（RoomData.art 数据驱动）：旧图退场（淡出+缩小）→ 换图 → 新图入场（淡入复位）。
# tex = null 恢复默认敌人图（非 BOSS 房）。入场时序由 controller._start_room 触发。
# 尺寸按 RoomData.art_scale 倍率（1.0 = 44×60 同规格，2.0 = 2 倍）——素材观感验证用。
func set_enemy_art(tex: Texture2D, art_scale: float = 1.0) -> void:
	if enemy_sprite == null:
		return
	var target := tex if tex != null else DEFAULT_ENEMY_TEXTURE
	var target_size := ENEMY_SPRITE_SIZE * art_scale
	if enemy_sprite.texture == target and enemy_sprite.modulate.a >= 1.0 and enemy_sprite.custom_minimum_size == target_size:
		return
	var tw := create_tween()
	tw.tween_property(enemy_sprite, "modulate:a", 0.0, 0.16)
	tw.parallel().tween_property(enemy_sprite, "scale", Vector2(0.85, 0.85), 0.16)
	tw.tween_callback(func() -> void:
		enemy_sprite.texture = target
		enemy_sprite.custom_minimum_size = target_size
		enemy_sprite.modulate = Color.WHITE
		enemy_sprite.scale = Vector2.ONE)
	tw.tween_property(enemy_sprite, "modulate:a", 1.0, 0.16)


# S4：元素样式缓存。旋转最高速约 28 跳/秒 × 3 列，若每次 new StyleBoxFlat
# 会产生大量短命对象；按元素各缓存一份即可（StyleBox 可跨按钮共享）。
var _cell_style_cache := {}


func _cell_style(elem: String) -> StyleBoxFlat:
	# 统一基础样式：灰边框 + 底色（2026-08-07 用户拍板：去掉元素色边框，仅冻结格保留彩色边框提示）
	if _cell_style_cache.has(elem):
		return _cell_style_cache[elem]
	var sb = StyleBoxFlat.new()
	sb.set_corner_radius_all(Palette.PANEL_RADIUS)
	sb.bg_color = Palette.CELL_BG
	sb.border_color = Palette.PANEL_BORDER
	sb.set_border_width_all(Palette.BORDER_WIDTH)
	_cell_style_cache[elem] = sb
	return sb


func _refresh_cell(reel: int, row: int) -> void:
	var b: Button = cells[reel][row]
	var s: SymbolData = controller.state.grid[reel][row]
	# S4：按「有效元素」着色。同一个共享符号（如 special.tres）在火剑下是火、在铁剑下是无属性，
	# 靠边框/底色一眼分辨谁吃 ×1.5；元素为 none 时回落符号自身配色。
	var elem = _cell_element(reel, row)
	b.text = s.label
	var fc: Color = s.color if elem == "none" else s.color.lerp(ElementCounter.color(elem), 0.55)
	# T30 冻结格（失效格）：蓝色边框框住作为 frost 提示（❄ 前缀/冰色文字不需要，边框即提示）
	var frozen: bool = controller.state.frozen_cols.has(reel)
	if not frozen:
		b.add_theme_color_override("font_color", fc)
		b.add_theme_color_override("font_disabled_color", fc)
		b.add_theme_color_override("font_hover_color", fc)
		b.add_theme_color_override("font_pressed_color", fc)
	var sb = _cell_style(elem)
	if frozen:
		# 冻结格：蓝色边框（3px）框住，作为 frost 触发提示
		var fsb: StyleBoxFlat = sb.duplicate()
		fsb.set_border_width_all(3)
		fsb.border_color = ElementCounter.color("ice")
		sb = fsb
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("disabled", sb)


func _refresh_meta() -> void:
	_refresh_gear_icons()
	var is_boss = controller._is_boss_room(controller.state.room_index)
	var essence_txt := ""
	for e in controller.state.room_element_mult:
		essence_txt += " · 精华·%s" % ElementCounter.label(e)
	# 2026-08-10 ACT 标注：当前幕（RoomData.act）+ 草案主题短名（BOSS设计草案三幕主题）
	var act_txt := "ACT 1"
	var act_theme := {1: "冰封", 2: "狂热", 3: "深渊"}
	var rooms: Array = controller.state.ROOMS
	if rooms.size() > 0 and controller.state.room_index >= 0 and controller.state.room_index < rooms.size():
		var a: int = int(rooms[controller.state.room_index].act)
		act_txt = "ACT %d%s" % [a, " " + act_theme.get(a, "") if act_theme.has(a) else ""]
	room_label.text = "%s · 房间: %d/%d%s%s" % [act_txt, controller.state.room_index + 1, rooms.size(), " · ★BOSS" if is_boss else "", essence_txt]
	turn_label.text = "回合: %d" % controller.state.turn_count
	player_hp_label.text = "HP %d/%d · 护盾 %d" % [controller.state.player_hp, controller.state.player_hp_max, controller.state.player_shield]
	player_buff_label.text = "【转轮】技能: " + controller._buff_summary()
	# T30 玩家 frost 状态（冻结转轮列数）
	if controller.state.player_frost > 0:
		player_buff_label.text += " · ❄霜冻×%d" % controller.state.player_frost
	# 2026-08-09 酸蚀恶鬼：玩家 DoT 状态（毒层；≥ 爆炸阈值整行警示色）
	var poison: int = int(controller.state.player_status.get("poison", 0))
	if poison > 0:
		player_buff_label.text += " · ☣酸蚀×%d" % poison
		if poison >= controller.state.player_dot_bomb_stacks:
			player_buff_label.add_theme_color_override("font_color", Palette.POP_DAMAGE)
		else:
			player_buff_label.remove_theme_color_override("font_color")
	else:
		player_buff_label.remove_theme_color_override("font_color")
	gold_label.text = "金币 %d" % controller.state.gold
	enemy_name_label.text = controller.state.enemy_name
	boss_badge.visible = is_boss
	enemy_hp_label.text = "HP %d/%d" % [max(controller.state.enemy_hp, 0), controller.state.enemy_hp_max]
	# 护甲（扁平池）：有护甲才显示；破甲后剩 0 也显示（提示已破甲窗口），仅无护甲敌人隐藏
	enemy_armor_label.visible = controller.state.enemy_armor_max > 0
	enemy_armor_label.text = "护甲 %d/%d" % [max(controller.state.enemy_armor, 0), controller.state.enemy_armor_max]
	enemy_status_label.text = "状态: " + ("无" if controller.state.enemy_status.is_empty() else controller.status_system.status_summary(controller.state.enemy_status))
	# T21 元素充能条：克制命中进度（满额释放元素爆发）
	if controller.state.charge_points > 0:
		enemy_charge_label.text = "⚡充能 %d/%d（克制命中攒满爆发）" % [controller.state.charge_points, controller.BALANCE.charge_max]
		enemy_charge_label.visible = true
	else:
		enemy_charge_label.visible = false
	# M4+M6 本局加成概览
	var parts := []
	if controller.state.run_power_bonus + controller.state.charm_power_bonus > 0:
		parts.append("伤害+%d" % (controller.state.run_power_bonus + controller.state.charm_power_bonus))
	# 护符乘区（damage_mult 类型，如 rage_charm ×1.5）此前漏显示 → 带乘区护符时概览空显示"无"
	if controller.state.charm_damage_mult != 1.0:
		parts.append("护符×%s" % ElementCounter.fmt_mult(controller.state.charm_damage_mult))
	# 净化已走消耗品（净化药剂 charges 用完即移出），不再有"净化上限"局内缓存；消耗品状态在 4 格子自显
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
		# T20：图标/名字读 IntentData（enemy_intent.data）；match 仅剩攻击/重击的数值格式分支
		var t = controller.state.enemy_intent["type"]
		var data: IntentData = controller.state.enemy_intent.get("data")
		var icon: String = data.icon if data != null and data.icon != "" else ""
		var name_txt: String = _intent_display_name(t)
		if data != null and data.display_name != "":
			name_txt = data.display_name
		match t:
			"attack": enemy_intent_label.text = "意图: %s%s %d" % [icon if icon != "" else "⚔", name_txt, controller.state.enemy_intent["value"]]
			"heavy":  enemy_intent_label.text = "意图: %s%s %d" % [icon if icon != "" else "💥", name_txt, controller.state.enemy_intent["value"]]
			"jam", "lock", "chaos":
				enemy_intent_label.text = "意图: %s%s（用净化药剂）" % [icon if icon != "" else "☣", name_txt]
			"none":   enemy_intent_label.text = "意图: —"
			_:        enemy_intent_label.text = "意图: %s%s" % [icon if icon != "" else "", name_txt]


func _intent_display_name(t: String) -> String:
	# T20：IntentData.display_name 优先；未定义时回落默认名（新意图类型兜底）
	match t:
		"jam":    return "注废"
		"lock":   return "锁轮"
		"chaos":  return "乱权"
		"heavy":  return "重击"
		"attack": return "攻击"
	return t


# 2026-08-07 通用武器替换弹层（商店 / BOSS 战利品共用）：顶部显示新武器详情，下方点旧武器替换
var _replace_dialog: PanelContainer = null
var _replace_vbox: VBoxContainer = null
var _replace_cb: Callable = Callable()

func request_weapon_replace(title: String, new_weapon_info: String, on_chosen: Callable) -> void:
	_replace_cb = on_chosen
	if _replace_dialog == null:
		_replace_dialog = PanelContainer.new()
		_replace_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_replace_dialog.z_index = 95   # 高于商店/覆盖层（90）、低于掌机外壳（100）
		var sb = StyleBoxFlat.new()
		sb.bg_color = Palette.BG_OVERLAY
		_replace_dialog.add_theme_stylebox_override("panel", sb)
		var center = CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var dlg = PanelContainer.new()
		var sb2 = StyleBoxFlat.new()
		sb2.bg_color = Palette.PANEL_BG
		sb2.border_color = Palette.ACCENT_GOLD
		sb2.set_border_width_all(2)
		dlg.add_theme_stylebox_override("panel", sb2)
		_replace_vbox = VBoxContainer.new()
		_replace_vbox.add_theme_constant_override("separation", 6)
		dlg.add_child(_replace_vbox)
		center.add_child(dlg)
		_replace_dialog.add_child(center)
		add_child(_replace_dialog)
	for c in _replace_vbox.get_children():
		_replace_vbox.remove_child(c)
		c.queue_free()
	var title_lbl = _label("", TypeScale.OVERLAY)
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_replace_vbox.add_child(title_lbl)
	var new_lbl = _label("", TypeScale.MEDIUM)
	new_lbl.text = new_weapon_info
	new_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	new_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	new_lbl.add_theme_color_override("font_color", Palette.ACCENT_GOLD)
	_replace_vbox.add_child(new_lbl)
	var hint = _label("", TypeScale.TINY)
	hint.text = "点击要替换的武器："
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_replace_vbox.add_child(hint)
	for path in controller.selected_loadout:
		var btn = UI_BUTTON.instantiate()
		btn.text = "替换「%s」" % controller._shop_name(path, "weapon")
		btn.custom_minimum_size = Vector2(220, 34)
		btn.pressed.connect(_on_replace_chosen.bind(path))
		_replace_vbox.add_child(btn)
	var cancel = UI_BUTTON.instantiate()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(120, 30)
	cancel.pressed.connect(func(): _replace_dialog.visible = false)
	_replace_vbox.add_child(cancel)
	_replace_dialog.visible = true


func _on_replace_chosen(old_path: String) -> void:
	_replace_dialog.visible = false
	var cb = _replace_cb
	_replace_cb = Callable()
	if cb.is_valid():
		cb.call(old_path)


func _show_overlay(title: String, btn_text: String) -> void:
	overlay_label.text = title
	overlay_button.text = btn_text
	overlay.visible = true


func _hide_overlay() -> void:
	overlay.visible = false


# 战斗日志统一走编辑器控制台（Debug.log），战斗界面不再显示滚动日志框
func _log(msg: String) -> void:
	Debug.log(msg)


# 玩家面板装备图标刷新：武器取首个符号 label emoji（无符号回退 ⚔️），
# 护符取 ItemData.icon emoji；技能取 SkillData.icon（回退 ✦）。tooltip = 名字(+ 描述)。
# 每次清空旧的 WIcon_/CIcon_/SIcon_ 子节点后重建（数量极小，无性能问题）。
# 临时图标区分（T21 配套，待美术资源替换）：
# 攻击武器 = 「⚔️ + 元素」；技能/护符保持自身 icon——避免武器取符号 label 与技能共用同一元素符号分不清
func _element_icon(elem: String) -> String:
	match elem:
		"fire":   return "🔥"
		"ice":    return "❄️"
		"poison": return "☠️"
		"light":  return "✨"
		"dark":   return "🌑"
		_:        return "⚔️"


func _refresh_gear_icons() -> void:
	if weapons_row == null or charms_row == null or skills_row == null:
		return
	for child in weapons_row.get_children().duplicate():
		if child.name.begins_with("WIcon_"):
			weapons_row.remove_child(child)
			child.queue_free()
	for child in charms_row.get_children().duplicate():
		if child.name.begins_with("CIcon_"):
			charms_row.remove_child(child)
			child.queue_free()
	for child in skills_row.get_children().duplicate():
		if child.name.begins_with("SIcon_"):
			skills_row.remove_child(child)
			child.queue_free()
	for path in controller.state.selected_loadout:
		var wd = load(path)
		if wd == null:
			continue
		var icon := "⚔️"
		if wd != null and "element" in wd:
			icon = "⚔️" + _element_icon(String(wd.element))
		var tip: String = wd.weapon_name if "weapon_name" in wd else path.get_file().get_basename()
		var lbl = Label.new()
		lbl.name = "WIcon_" + path.get_file().get_basename()
		lbl.text = icon
		lbl.add_theme_font_size_override("font_size", TypeScale.REEL)
		lbl.tooltip_text = tip
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		weapons_row.add_child(lbl)
	for path in controller.state.selected_charms:
		var cd = load(path)
		if cd == null:
			continue
		var icon_str: String = cd.get("icon") if cd.get("icon") != null else ""
		var icon: String = icon_str if icon_str != "" else "🛡"
		var name_str: String = cd.get("item_name") if cd.get("item_name") != null else path.get_file().get_basename()
		var desc_str: String = cd.get("description") if cd.get("description") != null else ""
		var lbl = Label.new()
		lbl.name = "CIcon_" + path.get_file().get_basename()
		lbl.text = icon
		lbl.add_theme_font_size_override("font_size", TypeScale.REEL)
		lbl.tooltip_text = name_str + (" · " + desc_str if desc_str != "" else "")
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		charms_row.add_child(lbl)
	for path in controller.state.selected_skills:
		var sd = load(path)
		if sd == null:
			continue
		var icon_str: String = sd.get("icon") if sd.get("icon") != null else ""
		var icon: String = icon_str if icon_str != "" else "✦"
		var name_str: String = sd.get("buff_name") if sd.get("buff_name") != null else path.get_file().get_basename()
		var desc_str: String = sd.get("description") if sd.get("description") != null else ""
		var lbl = Label.new()
		lbl.name = "SIcon_" + path.get_file().get_basename()
		lbl.text = icon
		lbl.add_theme_font_size_override("font_size", TypeScale.REEL)
		lbl.tooltip_text = name_str + (" · " + desc_str if desc_str != "" else "")
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		skills_row.add_child(lbl)


# 4 格子刷新：按 consumable_slots 顺序填，缺位留空占位文案
# - 有消耗品：显示 emoji + 名字 + charges 角标；按 game_state/in_loadout/律法锁槽 决定是否禁用
# - 空格子：显示 "—"，禁用（仅占位）
func _refresh_consumable_panel() -> void:
	if consumable_cells.is_empty():
		return
	# 与 consumable_used 信号的 controller 守卫保持一致：playing 状态 + 非整备
	var can_use = (controller.state.game_state == DuelController.FlowState.PLAYING) and (not controller.state.in_loadout)
	for i in range(consumable_cells.size()):
		var cell = consumable_cells[i]
		if i < controller.state.consumable_slots.size():
			var slot = controller.state.consumable_slots[i]
			var cd: Resource = load(slot["path"])
			if cd != null:
				cell.text = "%s %s" % [cd.icon, cd.item_name]
				cell.tooltip_text = ItemTooltip.for_resource(cd) + "\n剩 %d 次" % slot["charges"]   # 统一生成器 + 腰带余量
			else:
				cell.text = "?"
				cell.tooltip_text = "资源缺失"
			var locked: bool = controller.state.locked_consumable_slot == i   # 天平审判官：律法封印该格
			cell.disabled = not can_use or slot["charges"] <= 0 or locked
			if locked and not cell.text.begins_with("⚖ "):
				cell.text = "⚖ " + cell.text
		else:
			cell.text = "—"
			cell.tooltip_text = "消耗品空位"
			cell.disabled = true   # 空位不响应点击


# 4 格子点击：发 consumable_used(uid) 信号让 controller 走统一扣减+结算路径
func _on_consumable_cell_pressed(cell_index: int) -> void:
	if cell_index < 0 or cell_index >= controller.state.consumable_slots.size():
		return
	var uid = controller.state.consumable_slots[cell_index]["uid"]
	consumable_used.emit(uid)
