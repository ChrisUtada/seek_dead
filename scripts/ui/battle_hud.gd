extends Control
class_name BattleHud
# BattleHud — 老虎机对决的常驻 HUD 与全屏子界面（Phase 2 关注点分离）
# 由 duel_controller.gd 抽出：所有 UI 构建/刷新/飘字/图例。控制器只保留战斗逻辑，
# 通过 controller 引用回 DuelController 的游戏状态与逻辑方法。

const TRASH_SYMBOL = preload("res://resources/symbols/trash.tres")
const DEFAULT_ENEMY_TEXTURE = preload("res://assets/enemy_ember.png")   # 普通敌人立绘（C5：红色少色副本；RoomData.art 为空时使用）
const ENEMY_SPRITE_SIZE := Vector2(48, 48)    # 敌人立绘基准尺寸（1× = 48×48，与玩家同规格；art_scale 为整数倍）
const UI_BUTTON = preload("res://scenes/ui/ui_button.tscn")
const GROWTH_PICKER = preload("res://scripts/ui/growth_picker.gd")
const SYMBOL_CELL = preload("res://scenes/ui/symbol_cell.tscn")
# 转轮格底框素材（与左栏槽位同一套；32px 九宫格 8px）
const SLOT_FRAME_TEX = preload("res://assets/ui/dark_ages/frames/slot_blue.png")
const REEL_SPIN_VIEW = preload("res://scripts/ui/reel_spin_view.gd")
const POPUP_POOL = preload("res://scripts/ui/popup_pool.gd")
const SYMBOL_TOOLTIP = preload("res://scripts/ui/symbol_tooltip.gd")
const META_SCENE = preload("res://scenes/ui/meta_screen.tscn")
const REWARD_SCENE = preload("res://scenes/ui/reward_screen.tscn")
const SHOP_SCENE = preload("res://scenes/ui/shop_screen.tscn")
const LOADOUT_SCENE = preload("res://scenes/ui/loadout_scene.tscn")
const BRANCH_SCREEN = preload("res://scripts/board/branch_screen.gd")   # 分岔路线图 UI（唯一地图）
const CARD_FACTORY = preload("res://scripts/ui/card_factory.gd")   # G8 第二切片：卡片构造外迁

var controller   # DuelController 引用（运行时由 _ready 设置）
var _cards       # CardFactory（build_all 内实例化；只造控件，不持有状态）

# ---- 意图信号（HUD → controller，单向数据流；P2 解耦）----
# HUD 只发「用户想做什么」，不调用 controller 私有方法、不读 controller 字段名。
signal spin_requested                         # 点击「旋转」按钮
signal reel_clicked(col: int)                # 点击某一列转轮
# @warning_ignore 以下信号由子屏（shop_screen/reward_screen）emit、
# controller connect——跨文件连接，静态分析器误报 UNUSED_SIGNAL。
@warning_ignore("unused_signal")
signal buy_requested(offer: Dictionary)      # 商店购入
@warning_ignore("unused_signal")
signal sell_requested(uid_or_path: String, kind: String)  # 卖出（消耗品按 uid，其余按 path）
@warning_ignore("unused_signal")
signal reward_chosen(id: String, index: int)  # 房奖励三选一（index 对齐 reward_payloads，M1-01）
@warning_ignore("unused_signal")
signal loot_offer_chosen(index: int)          # Step 7：同层三选一卡点击（冻结 payload 下标）
@warning_ignore("unused_signal")
signal loot_offer_reroll_requested            # Step 7：重抽（同层，不重抽品质）
@warning_ignore("unused_signal")
signal loot_offer_skip_requested              # Step 7：免费跳过战利品（不发奖励）
@warning_ignore("unused_signal")
signal post_battle_defer_requested            # Step 7：成长位「保留到下次战斗」
@warning_ignore("unused_signal")
signal post_battle_growth_chosen(cand: Dictionary)  # M1 战后成长屏的成长位（技艺 / 铭印 / 下一房对策）
@warning_ignore("unused_signal")
signal boss_reward_chosen(cand: Dictionary)  # BOSS 战利品三选一
@warning_ignore("unused_signal")
signal reward_skip_requested                 # 跳过房奖励
signal shop_requested                          # 🛒 打开商店（房间歇态 opt-in）
signal next_room_requested                     # ▶ 下一房（房间歇态）
@warning_ignore("unused_signal")
signal card_toggled(card: Dictionary)         # 整备卡片勾选
@warning_ignore("unused_signal")
signal meta_choice_chosen(opt: Dictionary)    # 局末元进度结算（当前仅铁砧点单结果，GAME+ 后恢复多选）
@warning_ignore("unused_signal")
signal career_unlock_chosen(path: String)     # G6-02：生涯定向解锁三选一
signal overlay_button_pressed                 # 失败弹层按钮（回整备）
@warning_ignore("unused_signal")
signal consumable_used(uid: String)           # 使用腰带消耗品
@warning_ignore("unused_signal")
signal shop_leave_requested                   # 离开商店（回房间歇态）
@warning_ignore("unused_signal")
signal shop_card_pressed(offer: Dictionary)   # 商店卡片点击（shop_screen 拦截：武器满 2 弹替换）
@warning_ignore("unused_signal")
signal buy_replace_requested(offer: Dictionary, old_path: String)   # 替换购买（2026-08-07：武器槽上限 2 后的换装）
@warning_ignore("unused_signal")
signal shop_reroll_requested                   # 商店货架刷新（2026-08-09：Balatro 式递增价 + 每房间歇期限次）

# ---- 公开语义接口（controller → HUD 单向调用，替代直接戳私有节点/字段；P2 解耦）----
func build_all() -> void:
	_cards = CARD_FACTORY.new(self, controller)
	panel_view = preload("res://scripts/ui/player_panel_view.gd").new()
	panel_view.configure(self, weapons_row, charms_row, skills_row, consumable_cells)   # P2：左栏刷新逻辑外迁（须先于 _build_ui——其内会首次刷腰带）
	_build_ui()
	_layout_bottom_zones()
	_wire_spin_feedback()
	_build_loadout_screen()
	_build_branch_screen()     # 分岔路线图 UI（唯一地图）
	_build_reward_screen()
	_build_shop_screen()
	_build_meta_screen()
	_show_loadout_screen()

func set_reel_enabled(reel: int, enabled: bool) -> void:
	if cells.size() > reel and cells[reel].size() > 0:
		cells[reel][0].disabled = not enabled


func set_interroom_enabled(on: bool) -> void:
	# 2026-11-17：商店/下一房改为「间歇期才出现」（原为常驻灰化，长期占位）
	if interroom_shop_btn != null:
		interroom_shop_btn.visible = on
		interroom_shop_btn.disabled = not on
	if interroom_next_btn != null:
		interroom_next_btn.visible = on
		interroom_next_btn.disabled = not on
	_interroom_on = on
	_refresh_trim_entry()
	# 间歇时战斗已结束，隐藏中央 BOSS 名称/意图
	if on:
		enemy_stage_intent.visible = false
		enemy_stage_name.visible = false
	else:
		_refresh_meta()


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

# ---- UI 节点引用 ----
var cells = []   # 展示用 Button 引用 [reel][row]
var cell_spin_views = []   # P1：每格 ReelSpinView 引用 [reel][row]（视觉中心/预览查询）
var cell_badges = []   # 每格右上角匹配角标 Label 引用 [reel][row]
var cell_icon_layers = []   # 每格图标覆盖层（TextureRect）：符号图标独立于 Button.icon，便于叠粒子
var cell_icon_fx = []       # 每格图标粒子（1px 火花，元素色）
var _cell_want_icon = []    # [reel][row] -> Texture2D / null（滚轮遮挡时暂不显示）
var _cell_want_text = []    # [reel][row] -> String（无图标时的 label 兜底）
const PX1_TEX = preload("res://assets/fx/fx_px1.png")
# 2026-11-12 转轮手感 Step 4：停列短反馈（边框闪 + 轻微缩放，0.12–0.16s）。
var cell_stop_flashes = []   # [reel][row] -> Panel（仅边框 StyleBoxFlat）
var cell_stop_tweens = []    # [reel][row] -> Tween（复用前先 kill，避免叠加）
var _feedback_tween: Tween = null   # 底部短反馈的缩放脉冲（纯视觉）
var loadout_screen                     # 整备场景（scenes/ui/loadout_scene.tscn 实例，hud 兄弟节点）
var branch_screen                      # 分岔路线图 UI（唯一地图，hud 兄弟节点）
# 消耗品腰带 4 个固定格子（2x2），由 hud._refresh_consumable_panel 同步状态；
# consumable_panel 字段（controller 持有）已废弃，HUD 内聚管理 cell。
# 位置：左栏 PlayerPanel/VBox（GearBox 之后、PlayerBuffLabel 之前），保持 4 格子 2x2 形态
# 与 CONSUMABLE_CAP=4 对齐，玩家一眼能数清剩余消耗品。
var feedback_label: Control = null
# 2026-11-17：转轮下方文字提示已移除（用户要求）；所有调用点均有判空，恒 null 即自动跳过
@onready var consumable_cells: Array = [
	$ConsumablePanel/Cell1,
	$ConsumablePanel/Cell2,
	$ConsumablePanel/Cell3,
	$ConsumablePanel/Cell4,
]
var reward_screen                       # 奖励三选一覆盖层（reward_screen.tscn 实例）
var meta_screen                         # 每局结束元进度结算覆盖层（meta_screen.tscn 实例）

var shop_screen                         # 商店覆盖层（shop_screen.tscn 实例）

# 房间歇态按钮（opt-in 商店 + 下一房）：静态节点在 battle_hud.tscn TopBar，默认禁用，间歇态由 controller 点亮
@onready var interroom_shop_btn = $Margin/Content/TopBar/ShopBtn
@onready var interroom_next_btn = $Margin/Content/TopBar/NextRoomBtn
# G7-B B3：主动减带入口（线性间歇态）。代码内建在 TopBar 上，与棋盘屏按钮共用同一弹层。
var interroom_trim_btn = null
var _interroom_on := false
# 下一房预告为根节点浮层：不参与 Content 高度计算，避免间歇态把 HUD 顶出 480×270

# ---- 主 HUD 静态节点（P3b-1）：battle_hud.tscn 编辑器提供，脚本按节点路径引用 ----
# 注：手写 .tscn 的 %Name 唯一名在含 instance= 覆盖节点的场景里注册不可靠，
#     故改用确定性 $节点路径（.tscn 结构改动时同步更新此处路径）。
@onready var grid_container = $ReelDock/TopRow/ReelCenter/GridContainer
@onready var player_title = $Margin/Content/Middle/PlayerPanel/VBox/PlayerTitle
@onready var player_hp_label = $Margin/Content/Middle/PlayerPanel/VBox/HpRow/PlayerHpLabel
@onready var player_hp_icon = $Margin/Content/Middle/PlayerPanel/VBox/HpRow/HpIcon
@onready var player_shield_row = $Margin/Content/Middle/PlayerPanel/VBox/ShieldRow
@onready var player_shield_label = $Margin/Content/Middle/PlayerPanel/VBox/ShieldRow/PlayerShieldLabel
@onready var player_level_label = $Margin/Content/Middle/PlayerPanel/VBox/PlayerLevelLabel
@onready var weapons_title = $GearBox/WeaponsTitle
@onready var weapons_row = $GearBox/WeaponsRow
@onready var charms_row = $GearBox/GearCards/CharmsRow
@onready var skills_row = $GearBox/GearCards/SkillsRow
@onready var player_buff_label = $Margin/Content/Middle/PlayerPanel/VBox/PlayerBuffLabel
@onready var enemy_name_label = $Margin/Content/Middle/EnemyPanel/VBox/NameRow/EnemyNameLabel
@onready var boss_badge = $Margin/Content/Middle/EnemyPanel/VBox/BossBadge
@onready var enemy_hp_label = $Margin/Content/Middle/EnemyPanel/VBox/HpRow/EnemyHpLabel
@onready var enemy_armor_row = $Margin/Content/Middle/EnemyPanel/VBox/ArmorRow
@onready var enemy_armor_label = $Margin/Content/Middle/EnemyPanel/VBox/ArmorRow/EnemyArmorLabel
@onready var enemy_intent_icon = $Margin/Content/Middle/EnemyPanel/VBox/IntentRow/EnemyIntentIcon
@onready var enemy_intent_label = $Margin/Content/Middle/EnemyPanel/VBox/IntentRow/EnemyIntentLabel
@onready var enemy_status_label = $Margin/Content/Middle/EnemyPanel/VBox/EnemyStatusLabel
@onready var enemy_charge_row = $Margin/Content/Middle/EnemyPanel/VBox/ChargeRow
@onready var enemy_charge_label = $Margin/Content/Middle/EnemyPanel/VBox/ChargeRow/EnemyChargeLabel
@onready var enemy_element_label = $Margin/Content/Middle/EnemyPanel/VBox/NameRow/EnemyElementLabel
@onready var enemy_weak_label = $Margin/Content/Middle/EnemyPanel/VBox/EnemyWeakLabel
@onready var enemy_resist_label = $Margin/Content/Middle/EnemyPanel/VBox/EnemyResistLabel
@onready var enemy_mechanic_label = $Margin/Content/Middle/EnemyPanel/VBox/EnemyMechanicLabel
@onready var player_sprite = $Margin/Content/Middle/CenterStage/StageRow/PlayerCenter/PlayerSprite
@onready var enemy_sprite = $Margin/Content/Middle/CenterStage/StageRow/EnemyCenter/EnemySprite
@onready var player_shadow = $ShadowLayer/PlayerShadow
@onready var enemy_shadow = $ShadowLayer/EnemyShadow
@onready var enemy_stage_intent = $Margin/Content/Middle/CenterStage/StageRow/EnemyCenter/EnemySprite/EnemyStageIntent
@onready var enemy_stage_intent_label = $Margin/Content/Middle/CenterStage/StageRow/EnemyCenter/EnemySprite/EnemyStageIntent/Row/Label
@onready var enemy_stage_name = $Margin/Content/Middle/CenterStage/StageRow/EnemyCenter/EnemySprite/EnemyStageName
# P1 可读性原型：目标声明 + 换拍预览 + 每列停轮结果（纯展示，不参与结算）
var p1_preview_row: VBoxContainer = null
var p1_preview_labels: Array = []       # [reel][slot] -> Label
var p1_status_row: HBoxContainer = null
var p1_target_label: Label = null
var p1_stop_labels: Array = []          # [reel] -> Label（每列停轮结果，颜色区分目标/普通/MISS）
@onready var player_panel = $Margin/Content/Middle/PlayerPanel
@onready var enemy_panel = $Margin/Content/Middle/EnemyPanel
@onready var room_label = $Margin/Content/TopBar/RoomLabel
@onready var turn_label = $Margin/Content/TopBar/TurnLabel
@onready var gold_label = $GoldLabel

var animator = null   # P4 战斗动画器（tween 驱动立绘演出），_build_ui 末尾创建
var fx = null         # 战斗特效层（属性攻击的像素特效），_build_ui 末尾创建

# 2026-11-16 P0：敌人攻击的「掉血表现延后到命中帧」。
# 数值在闸口同步结算（判定/测试不变），但血条与 HP 数字暂时显示扣血前的影子值，
# 等前摇命中帧（普通 0.231s / 冰系 0.95s）才释放：血条掉 + 飘字 + 屏震同拍发生。
var _hp_display_hold: int = -1   # >=0 时血条/数字显示此值；-1 = 跟随真实 player_hp
var _hit_release_token: int = 0  # 多段伤害聚合 + 防止旧 timer 误释放
var _hit_pending_text: String = ""

# N-03（2026-11-21）：敌人侧幽灵值——玩家出手结算后真实 HP/护甲已落地，
# 但命中帧前血条/数字仍显示结算前的快照，命中帧才切到真实值。
# 与玩家侧 _hp_display_hold 对称；值来自账本 enemy_hp_before/enemy_armor_before（不重算）。
var _ev_hp_display_hold: int = -1      # >=0 时敌人 HP 显示此幽灵值；-1 = 跟随真实 enemy_hp
var _ev_armor_display_hold: int = -1   # >=0 时敌人护甲显示此幽灵值；-1 = 跟随真实 enemy_armor

var panel_view                       # P2（2026-08-24）：左栏玩家面板视图逻辑（player_panel_view.gd）
var overlay
var overlay_label
var overlay_button
var symbol_tooltip                  # 转轮格子悬停提示面板（scripts/ui/symbol_tooltip.gd）
var popup_layer                    # 飘字专用浮层（scripts/ui/popup_pool.gd）

func _label(text: String, font_size: int = TypeScale.BODY) -> Label:
	var l = Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if font_size > 0:
		l.add_theme_font_size_override("font_size", font_size)
	return l


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
		"trash":   return "无效格"   # F-03：统称（含未命中/废铁两来源）
		_:         return kind

func _source_tag(kind: String) -> String:
	return _cards.source_tag(kind)


func _build_ui() -> void:
	# 主 HUD 静态骨架（背景/标题/信息栏/三栏/底部栏）已由 battle_hud.tscn 编辑器提供，
	# 这里仅做动态内容：转轮格子创建 + 底部按钮信号连接 + 飘字/tooltip 浮层。

	# 转轮格子：容器已改为普通 Control（2026-11-17），格子位置由 _layout_row 统一摆放，
	# 不再依赖 GridContainer 的 columns / separation（容器会按最小尺寸拉伸格子，造成大小不一）。
	for reel in controller.state.REELS:
		cells.append([])
		controller.grid.append([])
		cell_spin_views.append([])
		cell_badges.append([])
		cell_icon_layers.append([])
		cell_icon_fx.append([])
		_cell_want_icon.append([])
		_cell_want_text.append([])
		cell_stop_flashes.append([])
		cell_stop_tweens.append([])
		for row in controller.state.ROWS:
			var cell = SYMBOL_CELL.instantiate()
			# 转轮格：42 格 / 32 图标，四周各留 5px 让外框完整露出
			# （32 格时图标正好铺满，会把边框整条吃掉 —— 「图标超出框」就是这么来的）
			cell.custom_minimum_size = Vector2(42, 42)
			cell.clip_text = true
			cell.add_theme_font_size_override("font_size", TypeScale.SYMBOL)
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
			# 图标覆盖层：静态格用它显示 32px 符号图，便于做动效（Button.icon 无法单独位移）
			var icon_layer := TextureRect.new()
			icon_layer.name = "IconLayer"
			icon_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
			# 内缩 7px：42px 格留出 28px 居中区，32px 图标等比缩到 28px，
			# 四周露出 7px 边框（原来内缩 5px 时图标正好铺满 32px 内腔、盖住边框）。
			icon_layer.offset_left = 7.0
			icon_layer.offset_top = 7.0
			icon_layer.offset_right = -7.0
			icon_layer.offset_bottom = -7.0
			# 32px 符号图塞进 26px 格子：不缩放会溢出盖住边框，这里等比缩进格内
			icon_layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon_layer.material = _icon_outline_material()
			icon_layer.visible = false
			cell.add_child(icon_layer)
			cell.move_child(icon_layer, 0)      # 放到 Badge 之下，避免盖住匹配角标
			cell_icon_layers[reel].append(icon_layer)
			# 图标粒子：1px 火花贴着图标往上飘（元素色），比"呼吸上下动"更符合像素画的动感
			@warning_ignore("shadowed_variable")
			var fx := CPUParticles2D.new()
			fx.name = "IconFx"
			fx.texture = PX1_TEX
			fx.position = Vector2(19, 20)
			fx.amount = 12
			fx.lifetime = 0.55
			fx.one_shot = true
			fx.explosiveness = 1.0
			fx.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
			fx.emission_rect_extents = Vector2(4, 4)
			fx.direction = Vector2(0, -1)
			fx.spread = 180.0          # 四散炸开
			fx.gravity = Vector2(0, 120)
			fx.initial_velocity_min = 22.0
			fx.initial_velocity_max = 48.0
			# 2026-11-12 Step 0：粒子固定种子，避免停列爆裂在每次触发时从全局 RNG 取样
			# （否则每停一列都会平移种子局的随机流）。
			fx.use_fixed_seed = true
			fx.seed = 20261112
			fx.emitting = false
			var ramp := Gradient.new()
			ramp.set_color(0, Color(1, 1, 1, 0.0))
			ramp.add_point(0.25, Color(1, 1, 1, 0.95))
			ramp.add_point(0.7, Color(1, 1, 1, 0.6))
			ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0.0))
			fx.color_ramp = ramp
			var mat := CanvasItemMaterial.new()
			mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			fx.material = mat
			cell.add_child(fx)
			cell_icon_fx[reel].append(fx)
			_cell_want_icon[reel].append(null)
			_cell_want_text[reel].append("")
			var badge = cell.get_node("Badge")
			cell_badges[reel].append(badge)
			# 2026-11-17：格底元素色条已去掉（用户嫌它盖住底框），元素色改由图标粒子+文字染色表达。
			# 2026-10-30：旋转时覆盖纵向滚动视觉（纯展示层，停止后隐藏）
			var spin_view = REEL_SPIN_VIEW.new()
			cell.add_child(spin_view)
			spin_view.configure(controller, reel)
			cell_spin_views[reel].append(spin_view)
			# Step 4：停列短边框（全透明底，仅 2px 边框；停稳时闪一下后淡出）
			var flash := Panel.new()
			flash.name = "StopFlash"
			flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
			flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var fsb := StyleBoxFlat.new()
			fsb.bg_color = Color(0, 0, 0, 0)
			fsb.draw_center = false
			fsb.border_color = Palette.ACCENT_GOLD
			for side in ["left", "top", "right", "bottom"]:
				fsb.set("border_width_" + side, 2)
			flash.add_theme_stylebox_override("panel", fsb)
			flash.modulate.a = 0.0
			cell.add_child(flash)
			cell_stop_flashes[reel].append(flash)
			cell_stop_tweens[reel].append(null)

	# P1：在转轮与 SPIN 之间插入「下一格预览 / 目标与停轮结果」两行（纯展示）。
	_build_p1_ui()

	# 底部操作栏按钮（SpinBar 在转轮下方居中）：由 .tscn 提供，这里连信号与快捷键。
	# 注：原"重置"按钮（Ctrl+R → _full_reset 放弃整局重开）已删除——其为无确认的一键自毁本局陷阱，
	# 失败/通关均有正统出口：失败弹层→返回整备（重选装备开新 run）/ 通关弹层→开新 run，无需常驻按钮。
	var spin_btn = $ReelDock/SpinBar/SpinButton
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
	_build_cell_sweep()
	_build_snow()
	_build_vitals()
	_build_charm_row()
	_build_relic_row()   # L2-F：遗物行（护符行下方，风格一致）
	_hide_panel_vitals()

	# 房间歇态按钮（opt-in 商店 + 下一房）：静态节点已在 battle_hud.tscn，这里只接信号
	interroom_shop_btn.connect("pressed", shop_requested.emit)
	interroom_next_btn.connect("pressed", next_room_requested.emit)

	# G7-B B3：主动减带入口（线性间歇态）。插在「商店」左边，地图入口在整备页。
	interroom_trim_btn = UI_BUTTON.instantiate()
	interroom_trim_btn.text = "✂ 精简"
	interroom_trim_btn.custom_minimum_size = Vector2(58, 18)
	interroom_trim_btn.add_theme_font_size_override("font_size", 9)
	interroom_trim_btn.disabled = true
	interroom_trim_btn.visible = false
	interroom_trim_btn.pressed.connect(show_trim_dialog)
	var info_bar = $Margin/Content/TopBar
	info_bar.add_child(interroom_trim_btn)
	info_bar.move_child(interroom_trim_btn, interroom_shop_btn.get_index())

	# P4：战斗动画器挂在 hud 下，setup 时缓存 PlayerSprite/EnemySprite 节点
	animator = BattleAnimator.new()
	add_child(animator)
	animator.setup(self)

	# 2026-11-17 P0：给立绘加 1px 暗色描边，把角色从复杂背景（雪地石砖明暗交错）里分离出来。
	# 复用转轮图标的描边 shader（TEXTURE_PIXEL_SIZE=1px 外扩），玩家/敌人 sprite 共用一份材质。
	var outline_mat := _icon_outline_material()
	if player_sprite != null:
		player_sprite.material = outline_mat
	if enemy_sprite != null:
		enemy_sprite.material = outline_mat

	# 特效层：属性攻击的像素特效（冰风/爆发/冰锥），同样由 setup 缓存立绘引用
	fx = BattleFx.new()
	add_child(fx)
	fx.setup(self)

func _build_p1_ui() -> void:
	var dock = $ReelDock
	# 下一格预览：放在转轮右侧，复用 TopRow 的高度，避免 480×270 下把底部顶出画面。
	# 每列一行「列号 + 最多 3 个符号」，3 行合计 33px，仍小于 38px 的转轮高度。
	p1_preview_row = VBoxContainer.new()
	p1_preview_row.name = "P1PreviewRow"
	p1_preview_row.add_theme_constant_override("separation", 0)
	p1_preview_row.custom_minimum_size = Vector2(96, 0)
	var top_row = $ReelDock/TopRow
	top_row.add_child(p1_preview_row)
	top_row.move_child(p1_preview_row, 1)
	for reel in controller.state.REELS:
		var group := HBoxContainer.new()
		group.add_theme_constant_override("separation", 2)
		p1_preview_row.add_child(group)
		var idx_label := _label("%d" % (reel + 1), TypeScale.REEL)
		idx_label.add_theme_color_override("font_color", Palette.MUTED_DIM)
		group.add_child(idx_label)
		var arr := []
		for slot in 3:
			var l := _label("", TypeScale.REEL)
			l.visible = false
			group.add_child(l)
			arr.append(l)
		p1_preview_labels.append(arr)
	p1_preview_row.visible = false

	# 目标 + 每列停轮结果行：放在 SPIN 上方，和结算反馈（FeedbackLabel）分开。
	p1_status_row = HBoxContainer.new()
	p1_status_row.name = "P1StatusRow"
	p1_status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	p1_status_row.add_theme_constant_override("separation", 8)
	# 2026-11-17：转轮下方不再显示文字行（用户要求）。对象保留、写入逻辑照常，只是不挂到场景树。
	# dock.add_child(p1_status_row)
	p1_target_label = _label("", TypeScale.REEL)
	p1_target_label.add_theme_color_override("font_color", Palette.ACCENT_GOLD)
	# G7-D 修复：局势行可长可短，必须裁切而不是撑宽整行（960×540 / 480×270 均不越界）。
	p1_target_label.clip_text = true
	p1_target_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	p1_target_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p1_status_row.add_child(p1_target_label)
	for reel in controller.state.REELS:
		var l := _label("", TypeScale.REEL)
		l.add_theme_color_override("font_color", Palette.MUTED)
		p1_status_row.add_child(l)
		p1_stop_labels.append(l)
	_refresh_p1_ui()
	_refresh_p1_previews()


# P1：刷新目标声明与预设标签（预设切换 / 新局时调用）。
# G7-D Step 2：标准模式显示「局势 + 真实可选对策」；固定目标对照仍显示 🎯 单目标。
func _refresh_p1_ui() -> void:
	if p1_target_label == null:
		return
	var rd = controller.readability
	if rd == null:
		p1_target_label.text = ""
		return
	if not rd.is_fixed_target() and String(rd.situation) != "":
		var labels: Array = []
		for c in rd.counters:
			labels.append(String(c.get("short", c.get("label", ""))))
		var shown: Array = labels
		if labels.size() > 2:
			shown = labels.slice(0, 2)
			shown.append("…")   # 主栏最多 2 条，完整对策在 tooltip（避免 960 宽越界）
		var head := "⚖ " + String(rd.situation)
		if labels.is_empty():
			head += " · 无可主动对策"
		else:
			head += " · 对策：" + "/".join(shown)
		p1_target_label.text = head
		var tip: Array = [String(rd.situation_detail) + " · 预设 " + String(rd.preset)]
		for c in rd.counters:
			var nm := String(c.get("label", ""))
			var nt := String(c.get("note", ""))
			if nt != "":
				tip.append("· %s：%s" % [nm, nt])
		p1_target_label.tooltip_text = "\n".join(tip)
		return
	p1_target_label.text = "🎯 %s · %s" % [rd.target_label(), String(rd.target_reason)]
	p1_target_label.tooltip_text = String(rd.target_detail)


# P1：刷新每列“下一格”预览。只在旋转中、预览槽位 > 0 时显示。
func _refresh_p1_previews() -> void:
	if p1_preview_row == null:
		return
	var rd = controller.readability
	var rs = controller.reel_system
	if rd == null or int(rd.preview_slots) <= 0 or rs == null or not rs.spinning:
		p1_preview_row.visible = false
		return
	# 2026-11-12 Step 1：目盲——隐藏后续预览，当前中心格仍可见（不消耗 RNG）。
	if controller.debuffs != null and controller.debuffs.preview_hidden():
		p1_preview_row.visible = false
		return
	var slots: int = int(rd.preview_slots)
	slots = mini(slots, 3)
	p1_preview_row.visible = true
	for reel in controller.state.REELS:
		if p1_preview_labels.size() <= reel:
			continue
		var syms: Array = []
		if cell_spin_views.size() > reel and cell_spin_views[reel].size() > 0:
			syms = cell_spin_views[reel][0].next_symbols(slots)
		for slot in p1_preview_labels[reel].size():
			var l: Label = p1_preview_labels[reel][slot]
			var shown: bool = slot < syms.size() and slot < slots
			l.visible = shown
			if not shown:
				continue
			var s: SymbolData = syms[slot]
			l.text = "▸" + (String(s.name) if String(s.name) != "" else String(s.label))
			var is_target: bool = s.resource_path == rd.target_symbol_path and rd.target_symbol_path != ""
			l.add_theme_color_override("font_color", Palette.ACCENT_GOLD if is_target else Palette.MUTED)


# P1：视觉中心索引（旋转视图未激活时回落逻辑游标）。
func visual_center_index(reel: int) -> int:
	if cell_spin_views.size() > reel and cell_spin_views[reel].size() > 0:
		return int(cell_spin_views[reel][0].center_index())
	return -1


func _clear_stop_feedback() -> void:
	for l in p1_stop_labels:
		l.text = ""
		l.add_theme_color_override("font_color", Palette.MUTED)
	# Step 4：清掉停列闪光与缩放，避免跨回合残留或叠加。
	for reel in cell_stop_flashes.size():
		for row in cell_stop_flashes[reel].size():
			var tw = cell_stop_tweens[reel][row] if cell_stop_tweens.size() > reel and cell_stop_tweens[reel].size() > row else null
			if tw != null and is_instance_valid(tw):
				tw.kill()
			cell_stop_tweens[reel][row] = null
			cell_stop_flashes[reel][row].modulate.a = 0.0
			if cells.size() > reel and cells[reel].size() > row:
				cells[reel][row].scale = Vector2.ONE


func _show_stop_feedback(reel: int, nm: String, outcome: String) -> void:
	if reel < 0 or reel >= p1_stop_labels.size():
		return
	var l: Label = p1_stop_labels[reel]
	var text := ""
	var col: Color = Palette.MUTED
	match outcome:
		"target":
			text = "%d %s✓" % [reel + 1, nm]
			col = Palette.ACCENT_GOLD
		"normal":
			text = "%d %s" % [reel + 1, nm]
		"miss":
			text = "%d MISS" % (reel + 1)
			col = Palette.POP_DAMAGE
		"jam":
			text = "%d 注废" % (reel + 1)
			col = Palette.POP_DAMAGE
		"lock":
			text = "%d 锁轮" % (reel + 1)
			col = Palette.ACCENT_GOLD
		"forced":
			text = "%d 夺轮" % (reel + 1)
			col = Palette.MUTED_DIM
		_:
			text = "%d %s" % [reel + 1, nm]
	l.text = text
	l.add_theme_color_override("font_color", col)


# Step 4：停列短反馈——0.14s 内边框亮起淡出 + 格子轻微缩放回正。
# 纯表现层：不阻塞输入、不改变落点与结算；control 预设也保留（「每次操作都有确认感」）。
func _pulse_stop_cell(reel: int, outcome: String) -> void:
	if reel < 0 or reel >= cells.size() or cells[reel].is_empty():
		return
	if cell_stop_flashes.size() <= reel or cell_stop_flashes[reel].is_empty():
		return
	var cell: Control = cells[reel][0]
	var flash: Panel = cell_stop_flashes[reel][0]
	var sb := flash.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.border_color = _stop_feedback_color(outcome)
	flash.modulate.a = 1.0
	cell.pivot_offset = cell.size * 0.5
	var old = cell_stop_tweens[reel][0]
	if old != null and is_instance_valid(old):
		old.kill()
	var tw := create_tween()
	tw.tween_method(_set_cell_pop.bind(cell), 0.0, 1.0, 0.14)
	tw.parallel().tween_property(flash, "modulate:a", 0.0, 0.14)
	cell_stop_tweens[reel][0] = tw
	# 按停爆裂：整列 3 个格子同时炸一次粒子（元素色在 _refresh_cell 里已上色）
	if cell_icon_fx.size() > reel:
		@warning_ignore("shadowed_variable")
		for fx in cell_icon_fx[reel]:
			if fx is CPUParticles2D:
				# 2026-11-12 Step 0 基线：CPUParticles2D.restart() 会消耗 1 次全局 RNG，
				# 每停一列就平移整个种子局的随机流（违反「提示/动画不消耗 RNG」）。
				# one_shot 播完后 emitting 自动回落 false，直接置 true 可再次触发爆裂，
				# 且不向全局随机流取样。
				fx.emitting = true


func _set_cell_pop(t: float, cell: Control) -> void:
	if is_instance_valid(cell):
		cell.scale = Vector2.ONE * (1.0 + 0.08 * sin(t * PI))


func _stop_feedback_color(outcome: String) -> Color:
	match outcome:
		"target", "lock":
			return Palette.ACCENT_GOLD
		"miss", "jam":
			return Palette.POP_DAMAGE
		"forced":
			return Palette.MUTED_DIM
		_:
			return Palette.TITLE


# 回合级停轮摘要写到底部反馈行（随后会被战斗结算反馈覆盖，属于预期）。
func _show_spin_summary(_text: String) -> void:
	# 2026-11-17：转轮下方不再显示文字提示（用户要求），保留空实现供 readability_system 调用
	pass


func _build_loadout_screen() -> void:
	# 纯 2D 整备场景（scenes/ui/loadout_scene.tscn）：作为 hud 的兄弟节点挂到 Duel 根，
	# 以便进入整备时 hud.hide() 隐藏 Game Boy 外框 + 战斗 HUD。布局可在编辑器里直接调。
	loadout_screen = LOADOUT_SCENE.instantiate()
	get_parent().add_child(loadout_screen)
	loadout_screen.configure(controller, self)
	loadout_screen.hide_screen()


# M2：棋盘主视图与整备场景同级（hud 兄弟节点），显示时隐藏战斗 HUD，避免挤进战斗中央区域。
func _build_branch_screen() -> void:
	branch_screen = BRANCH_SCREEN.new()
	get_parent().add_child(branch_screen)
	branch_screen.configure(controller, self)
	branch_screen.hide_board(false)


func show_board_screen(board_sys) -> void:
	if branch_screen == null:
		return
	branch_screen.show_board(board_sys)


func hide_board_screen(show_hud: bool = false) -> void:
	if branch_screen != null:
		branch_screen.hide_board(show_hud)


# 卡片构造已外迁 scripts/ui/card_factory.gd（G8 第二切片）；这里保留同名薄包装，
# reward_screen / shop_screen / meta_screen / loadout_scene 与测试的调用点不变。
func _make_item_card(data: Resource, path: String, kind: String) -> Dictionary:
	return _cards.item_card(data, path, kind)


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
	# M1：普通 / 精英胜利改由三槽「战后成长」接管；BOSS 保留专属战利品屏。
	if not is_boss:
		controller.room_flow.begin_post_battle()
		return
	# L3 §6.6：BOSS 先结算收益+生成战果快照，再开战利品屏同屏展示。
	controller.room_flow.prepare_boss_summary()
	reward_screen.show_screen(true)


# M1 战后成长三槽屏（补给 / 构筑 / 成长）。
func show_post_battle(offer: Array, summary: String) -> void:
	reward_screen.show_post_battle(offer, summary)


# Step 7：同层三选一（战利品阶段）。
func show_loot_offer(view: Dictionary) -> void:
	reward_screen.show_loot_offer(view)


# Step 7：重抽后原地刷新（品质层不变）。
func refresh_loot_offer(view: Dictionary) -> void:
	reward_screen.refresh_loot_offer(view)


# Step 7：成长阶段（技艺 / 铭印；与战利品分开结算）。
func show_loot_growth(cand: Dictionary, summary: String) -> void:
	reward_screen.show_loot_growth(cand, summary)


func _make_loot_offer_card(opt: Dictionary, index: int) -> Button:
	return _cards.loot_offer_card(opt, index)


func _make_reward_card(rw: RewardData, index: int = -1, slot_label: String = "") -> Button:
	return _cards.reward_card(rw, index, slot_label)


# M1：战后成长屏的成长位卡（技艺 / 铭印 / 下一房对策）。
func _make_post_growth_card(cand: Dictionary) -> Button:
	return _cards.post_growth_card(cand)


# BOSS 战利品卡（候选为 dict，点击调 _on_boss_reward_chosen；完整说明进 tooltip，卡片只放短文案）
func _make_boss_reward_card(cand: Dictionary) -> Button:
	return _cards.boss_reward_card(cand)


# ---------------------------------------------------------------------------
# 每局结束元进度结算（当前仅铁砧点单一结果）
# ---------------------------------------------------------------------------
func _build_meta_screen() -> void:
	meta_screen = META_SCENE.instantiate()
	add_child(meta_screen)   # 必须先入树：configure 内访问 @onready 节点
	meta_screen.configure(controller, self)
	meta_screen.hide_screen()


func _show_meta_choice() -> void:
	meta_screen.show_choice()

# S5-2：整备页入口 → 生涯定向解锁与图鉴统一界面（meta_screen）
func _show_career_screen() -> void:
	meta_screen.show_career()


func _make_meta_card(opt: Dictionary) -> Button:
	return _cards.meta_card(opt)


# G6-02：生涯定向解锁卡（未拥有装备三选一；点击立即写入图鉴/拥有池）。
func _make_unlock_card(cand: Dictionary) -> Button:
	return _cards.unlock_card(cand)


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
	return _cards.shop_card(offer)


# 商店「卖出」区：四列列出已持有物品，点击回收约50%金币并释放槽位
func _make_sell_card(title_text: String, sub_text: String, disabled: bool, cb: Callable, res: Resource = null) -> Button:
	return _cards.sell_card(title_text, sub_text, disabled, cb, res)


func _build_overlay() -> void:
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	# G8：screen.gd 退役，覆盖层脚手架就地内联（仅此一处使用；布局与原先逐行一致）
	var ov_bg := ColorRect.new()
	ov_bg.color = Palette.BG_OVERLAY
	ov_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(ov_bg)
	var ov_center := CenterContainer.new()
	ov_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(ov_center)
	var ov_v := VBoxContainer.new()
	ov_v.add_theme_constant_override("separation", 18)
	ov_center.add_child(ov_v)
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
	symbol_tooltip = SYMBOL_TOOLTIP.new()   # 面板外观/两行文本/定位见 scripts/ui/symbol_tooltip.gd
	add_child(symbol_tooltip)


# 读某格的「有效元素」——即符号继承武器 element 之后的结果（controller.state.grid_elem）。
# 注意：不能读 SymbolData.element（符号原生元素）。共享 .tres（如 slash）在火剑下
# 有效元素是 fire、在铁剑下是 none，只有 grid_elem 与 _contribute 的结算口径一致。
func _cell_element(reel: int, row: int) -> String:
	if controller == null:
		return "none"
	# 读活数据（controller.grid_elem）而非只读快照：写方（reset_grid / lock_reel）都是先写 grid_elem
	# 再调 _refresh_cell，而快照要到 invalidate_state() 才更新——读快照会让元素色落后一步
	# （房间开场格子图标元素色不对，正是快照未失效导致）。
	var ge = controller.grid_elem
	if ge.size() <= reel or ge[reel].size() <= row:
		return "none"
	return ge[reel][row]


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
	var title := "%s %s" % [s.label, s.name]
	var detail := ""
	if s.kind == "buff":
		# Phase C：增益符号显示效果与持续回合，而非属性克制
		var vtxt = ("×%.1f" % s.buff_value) if s.buff_effect == "damage_mult" else ("+%d" % int(s.buff_value))
		detail = "技能 · %s %s · 持续 %d 回合" % [controller.status_system.buff_effect_name(s.buff_effect), vtxt, s.buff_turns]
	elif s.kind == "trash":
		# F-03：无效格按来源区分说明，不把武器精度不足的 MISS 写成敌方注入的废铁。
		var src := "敌方机制注入的无效格" if String(s.name) == "废铁" else "武器精度不足导致的无效格"
		detail = "%s · %s（不结算、不参与牌型）" % [String(s.name), src]
	else:
		detail = "%s · %s%s" % [_kind_name(s.kind), (ElementCounter.label(elem) if elem != "none" else "无属性"), rel_text]
	# 定位到格子上方并夹紧 HUD 边界
	symbol_tooltip.show_tip(title, detail, cells[reel][row].get_global_rect(), get_global_rect())


func _on_cell_unhover() -> void:
	if symbol_tooltip != null:
		symbol_tooltip.visible = false


# ---------------------------------------------------------------------------
# Phase 3：飘字对象池（避免每次 new + queue_free）
# ---------------------------------------------------------------------------
func _build_popup_layer() -> void:
	popup_layer = POPUP_POOL.new()   # 池与飘字动画见 scripts/ui/popup_pool.gd
	add_child(popup_layer)


# ---------------------------------------------------------------------------
# 结算扫描（2026-11-16）：三列停完后按 左→中→右 逐格亮起边框，
# 让玩家先看清「这一行是哪三格」，再进入数值结算。三连时三格一起再亮一次。
# 纯展示：只读格子节点，不读写战斗状态、不消耗 RNG。
# 样式与停轮闪光（StopFlash）保持一致：全透明底 + 2px 金边 + 同一弹缩曲线，
# 但用独立 Panel 与独立 Tween，避免和停轮闪光争用 cell_stop_tweens。
# ---------------------------------------------------------------------------
var cell_sweep_flashes: Array = []   # [reel] -> Panel
var cell_sweep_tweens: Array = []    # [reel] -> Tween

const CELL_SWEEP_STEP := 0.20        # 格与格之间的间隔（0.07 太快，看不清是哪一格）
const CELL_SWEEP_DECAY := 0.38       # 单格亮起后的衰减（下一格亮起时上一格还在淡出，形成扫过感）
const CELL_SWEEP_TRIPLE_DECAY := 0.50   # 三连收尾：三格一起再亮，衰减更慢，读作「这条线成立」


func _build_cell_sweep() -> void:
	for reel in controller.state.REELS:
		cell_sweep_flashes.append([])
		cell_sweep_tweens.append(null)
		for row in controller.state.ROWS:
			var flash := Panel.new()
			flash.name = "SweepFlash"
			flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
			flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var fsb := StyleBoxFlat.new()
			fsb.bg_color = Color(0, 0, 0, 0)
			fsb.draw_center = false
			fsb.border_color = Palette.ACCENT_GOLD
			for side in ["left", "top", "right", "bottom"]:
				fsb.set("border_width_" + side, 2)
			flash.add_theme_stylebox_override("panel", fsb)
			flash.modulate.a = 0.0
			cells[reel][row].add_child(flash)
			cell_sweep_flashes[reel].append(flash)


# 飘雪：两层速度不同的雪花，靠运动视差制造纵深（固定镜头下真视差无效，用这个替代）。
# 位于 SnowLayer(Node2D, 背景之上/立绘之下)，不遮挡玩家手动调整的立绘与阴影。
# 远雪：小、慢、暗；近雪：稍大、快、亮。都在逻辑画布 480×270 内循环。
const SNOW_TEX = preload("res://assets/fx/fx_snow.png")


func _build_snow() -> void:
	var layer := get_node_or_null("SnowLayer") as Node2D
	if layer == null:
		return
	_make_snow_stream(layer, "SnowFar", 26, 1.0, 10.0, 16.0, Color(1, 1, 1, 0.35), 15.0)
	_make_snow_stream(layer, "SnowNear", 14, 1.6, 16.0, 24.0, Color(1, 1, 1, 0.6), 25.0)


func _make_snow_stream(layer: Node2D, name: String, amount: int, scale: float,
		vel_min: float, vel_max: float, color: Color, spread_h: float) -> void:
	var p := CPUParticles2D.new()
	p.name = name
	p.texture = SNOW_TEX
	p.amount = amount
	p.lifetime = 12.0
	p.one_shot = false
	p.preprocess = 9.0            # 预模拟9秒，开局雪花就铺满画面（否则要等12秒才布满）
	p.emitting = true
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(250, 4)
	p.position = Vector2(240, -4)
	p.direction = Vector2(0.12, 1.0)          # 略向右下飘
	p.gravity = Vector2(0, 0)
	p.initial_velocity_min = vel_min
	p.initial_velocity_max = vel_max
	p.scale_amount_min = scale * 0.7
	p.scale_amount_max = scale
	p.color = color
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# CPUParticles2D 无 turbulence；横向散开靠 spread + emission_rect 宽度，
	# 纵深由两层不同速度/尺寸产生（远雪慢小、近雪快大）。
	p.spread = spread_h
	layer.add_child(p)


# 单格亮起（供 _present_turn 按格子顺序调用）
func sweep_light_cell(reel: int) -> void:
	_light_sweep_cell(reel, CELL_SWEEP_DECAY)


# 多格同时亮起（攻击格合并成一次攻击时用，视觉上区别于逐格扫）
func sweep_light_cells_together(reels: Array) -> void:
	for r in reels:
		_light_sweep_cell(int(r), CELL_SWEEP_TRIPLE_DECAY)


# 左→右逐格亮起。返回时最后一格已亮起，调用方 await 它即可控制节奏。
func play_cell_sweep() -> void:
	if cell_sweep_flashes.is_empty():
		return
	for reel in cell_sweep_flashes.size():
		_light_sweep_cell(reel, CELL_SWEEP_DECAY)
		await get_tree().create_timer(CELL_SWEEP_STEP).timeout


# 单格亮起：边框瞬间不透明 + 弹缩一下，然后按 decay 淡出。
func _light_sweep_cell(reel: int, decay: float) -> void:
	if cell_sweep_flashes.size() <= reel or cell_sweep_flashes[reel].is_empty():
		return
	if cells.size() <= reel or cells[reel].is_empty():
		return
	var cell: Control = cells[reel][0]
	var flash: Panel = cell_sweep_flashes[reel][0]
	var old = cell_sweep_tweens[reel]
	if old != null and is_instance_valid(old):
		old.kill()
	flash.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(flash, "modulate:a", 0.0, decay)
	cell_sweep_tweens[reel] = tw
	cell.pivot_offset = cell.size * 0.5
	var pop := create_tween()
	pop.tween_method(_set_cell_pop.bind(cell), 0.0, 1.0, 0.16)


# 三连 / 元素共鸣：三格一起再亮一次（衰减更慢，读作「这条线成立」）；否则静默。
func settle_cell_sweep(is_triple: bool) -> void:
	if not is_triple or cell_sweep_flashes.is_empty():
		return
	for reel in cell_sweep_flashes.size():
		_light_sweep_cell(reel, CELL_SWEEP_TRIPLE_DECAY)


# ---------------------------------------------------------------------------
# 房间 / 流程
# ---------------------------------------------------------------------------
func _clear_badges() -> void:
	for reel in controller.state.REELS:
		for row in controller.state.ROWS:
			if cell_badges.size() > reel and cell_badges[reel].size() > row:
				cell_badges[reel][row].text = ""
	# Step 5：回合结算开始时一并清掉上一回合的底部短反馈（与角标同一生命周期）。
	# 只清文本不隐藏——该行常驻占位，避免反馈出现/消失时转轮区上下跳动。
	if feedback_label != null:
		feedback_label.text = ""
		feedback_label.add_theme_color_override("font_color", Palette.TITLE)
		feedback_label.scale = Vector2.ONE
		if _feedback_tween != null and is_instance_valid(_feedback_tween):
			_feedback_tween.kill()
			_feedback_tween = null


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


# Step 5：底部单行短反馈（最高连击符号 / 克制或抵抗倍率 / 本回合总伤害）。
# 纯展示：结算数据由 CombatSystem 在 evaluate() 末尾原样传入，不参与任何数值计算。
# 不恢复大段伤害分解——完整分解仍只进 Debug.log（见 combat_system.push_dmg_line）。
func _show_turn_feedback(counts: Dictionary, total: int, triple: bool = false, elem_triple: bool = false,
		shield_gain: int = -1, heal_gain: int = -1, heal_overflow_shield: int = 0,
		armor_cleared: int = 0, counter_burst: int = 0, charge_burst: int = 0) -> void:
	if feedback_label == null:
		return
	var best_label := ""
	var best_n := 0
	for key in counts:
		var entry = counts[key]
		var s: SymbolData = entry[0]
		var c: int = entry[2]
		if s == null or s == TRASH_SYMBOL or s.kind == "trash" or c <= best_n:
			continue
		# 文字优先用符号名（火斩/匕斩），不显示 emoji——图标化后 emoji 只作资源缺失回落
		best_label = String(s.name) if String(s.name) != "" else String(s.label)
		best_n = c
	var parts: Array[String] = []
	# G7-D Step 5：护盾/治疗报「真实落地」值；满血且无溢出时不显示「恢复」，避免反馈与结算不一致。
	var has_shield := false
	var has_heal := false
	for key in counts:
		var sym: SymbolData = counts[key][0]
		if sym == null:
			continue
		if String(sym.kind) == "shield":
			has_shield = true
		elif String(sym.kind) == "heal":
			has_heal = true
	# Step 4：结果类别优先——防御 → 破甲 → 恢复 → 爆发 → 总伤害。
	# 窄屏裁切时先省略连击/克制细节，不省略「发生了什么」。
	if shield_gain > 0:
		parts.append("护盾+%d" % shield_gain)
	elif has_shield and shield_gain < 0:
		parts.append("护盾准备")   # 旧调用（无结算值）保持原文案
	if armor_cleared > 0:
		parts.append("破甲-%d" % armor_cleared)
	if heal_gain > 0:
		parts.append("恢复+%d" % heal_gain)
	elif heal_overflow_shield > 0:
		parts.append("恢复→盾+%d" % heal_overflow_shield)
	elif has_heal and heal_gain < 0:
		parts.append("恢复")       # 旧调用（无结算值）保持原文案
	if counter_burst > 0:
		parts.append("核爆-%d" % counter_burst)
	if charge_burst > 0:
		parts.append("充能爆发-%d" % charge_burst)
	if total > 0:
		parts.append("-%d" % total)
		if controller.enemy_hp > 0 and controller.enemy_hp <= int(controller.enemy_hp_max * 0.25):
			parts.append("收尾窗口")
	if best_n >= 2:
		parts.append("%s×%d" % [best_label, best_n])
	if elem_triple:
		parts.append("同元素三连")
	elif triple:
		parts.append("三连")
	if controller._eval_adv:
		parts.append("克制×%s" % ElementCounter.fmt_mult(ElementCounter.MULT_ADVANTAGE))
	elif controller._eval_dis:
		parts.append("抵抗×%s" % ElementCounter.fmt_mult(ElementCounter.MULT_RESIST))
	feedback_label.text = " / ".join(parts)
	# Step 4：结果分级——爆发/破甲/三连 > 普通命中 > 防御恢复。
	# 只改颜色与 0.12s 缩放脉冲，不加长动画、不遮下一次转轮。
	var tier_col: Color = Palette.TITLE
	var pop := 1.0
	if counter_burst > 0 or charge_burst > 0:
		tier_col = Palette.ACCENT_GOLD
		pop = 1.10
	elif triple or elem_triple:
		tier_col = Palette.ACCENT_GOLD
		pop = 1.07
	elif armor_cleared > 0:
		tier_col = Palette.ARMOR
		pop = 1.05
	elif shield_gain > 0 or heal_gain > 0 or heal_overflow_shield > 0:
		tier_col = Palette.POP_HEAL if heal_gain > 0 else Palette.POP_SHIELD
		pop = 1.03
	elif total > 0:
		pop = 1.02
	# 连击强度：2–8 连小幅递增并封顶（项目暂无音频资源，用缩放幅度做「音调」的可视替代）。
	pop += 0.006 * float(maxi(0, clampi(best_n, 0, 8) - 1))
	feedback_label.add_theme_color_override("font_color", tier_col)
	_pulse_feedback_label(pop)


# Step 4：底部反馈行的短脉冲（0.12s，纯视觉，不改变下一回合输入）。
func _pulse_feedback_label(pop: float) -> void:
	if feedback_label == null:
		return
	feedback_label.pivot_offset = feedback_label.size * 0.5
	if _feedback_tween != null and is_instance_valid(_feedback_tween):
		_feedback_tween.kill()
	feedback_label.scale = Vector2.ONE
	_feedback_tween = create_tween()
	_feedback_tween.tween_method(_set_label_pop.bind(feedback_label, pop), 0.0, 1.0, 0.12)


func _set_label_pop(t: float, label: Label, pop: float) -> void:
	if is_instance_valid(label):
		label.scale = Vector2.ONE * (1.0 + (pop - 1.0) * sin(t * PI))


# Step 4：消耗品使用后的单行结果反馈（净化 / 清净 / 破甲 / 恢复 / 强化 / 伤害）。
# 与回合结算反馈共用同一行；下一次转轮结算会自然覆盖。纯展示，不参与结算。
func _show_action_feedback(text: String) -> void:
	if feedback_label != null and text != "":
		feedback_label.text = text
		feedback_label.add_theme_color_override("font_color", Palette.TITLE)


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
		enemy_weak_label.text = "弱%s×%s" % ["·".join(wk_names), ElementCounter.fmt_mult(ElementCounter.MULT_ADVANTAGE)]
		enemy_weak_label.add_theme_color_override("font_color", ElementCounter.color(ewk[0]))
		var ers := ElementCounter.resists(eelem)
		enemy_resist_label.visible = true
		var rs_names := []
		for e in ers:
			rs_names.append(ElementCounter.label(e))
		enemy_resist_label.text = "抗%s×%s" % ["·".join(rs_names), ElementCounter.fmt_mult(ElementCounter.MULT_RESIST)]
		enemy_resist_label.add_theme_color_override("font_color", ElementCounter.color(ers[0]))


# 飘字：在 anchor 面板顶部中央弹出并上浮淡出（对象池实现见 scripts/ui/popup_pool.gd）
# slow=true 走 DoT 慢速档（上浮更慢、驻留更久），与攻击红字快弹区分。
func _popup(text: String, color: Color, anchor: Control, slow: bool = false) -> void:
	if popup_layer == null:
		return
	popup_layer.popup(text, color, anchor, slow)


# 2026-11-15 转轮凑牌 §9.1：常驻牌谱面板。
# 两个分区（武器牌谱 / 技能术式），每条显示 id、名称与组件；
# 已满足的组件正常色，缺的组件暗淡 —— 玩家随时知道「我在凑什么、还差什么」。
# entries: [{section, id, name, icon, parts: [{text, ok}], done, active}]
var _pattern_tray: Control
var _pattern_tray_label: RichTextLabel
# 2026-11-15：常驻面板暂时关闭显示。
# 实机截图显示它在像素字体下字号远超预期（12px 渲染成大字），左上角完全遮挡
# 治疗术/护符等既有信息。表现方式待定，先把显示关掉，数据层与实现保留：
# 需要重新启用时把这里改成 true 即可，调用方（combat_system._build_tray_entries）无需改动。
const PATTERN_TRAY_ENABLED := false
func update_pattern_tray(entries: Array) -> void:
	if not PATTERN_TRAY_ENABLED:
		if _pattern_tray != null and is_instance_valid(_pattern_tray):
			_pattern_tray.queue_free()
			_pattern_tray = null
			_pattern_tray_label = null
		return
	if not is_inside_tree():
		return
	if _pattern_tray == null or not is_instance_valid(_pattern_tray):
		_pattern_tray = PanelContainer.new()
		_pattern_tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.07, 0.09, 0.78)
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		_pattern_tray.add_theme_stylebox_override("panel", sb)
		_pattern_tray_label = RichTextLabel.new()
		_pattern_tray_label.bbcode_enabled = true
		_pattern_tray_label.fit_content = true
		_pattern_tray_label.scroll_active = false
		_pattern_tray_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pattern_tray_label.add_theme_font_size_override("normal_font_size", 12)
		_pattern_tray_label.custom_minimum_size = Vector2(196, 0)
		_pattern_tray.add_child(_pattern_tray_label)
		add_child(_pattern_tray)
		_pattern_tray.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_pattern_tray.position = Vector2(12, 96)
	var lines: Array[String] = []
	var cur_section := ""
	for e in entries:
		var sec := String(e.get("section", ""))
		if sec != cur_section:
			if cur_section != "":
				lines.append("")
			lines.append("[color=#8fa3b8]%s[/color]" % sec)
			cur_section = sec
		var icon := String(e.get("icon", ""))
		var head_color := "#d9e2ec"
		if bool(e.get("active", false)):
			head_color = "#d5a33d"          # 本回合生效：金色
		elif bool(e.get("done", false)):
			head_color = "#8fbf6a"          # 已凑齐但没触发（被更高优先级占用等）
		lines.append("[color=%s]%s %s %s[/color]" % [
			head_color, icon, String(e.get("id", "")), String(e.get("name", ""))])
		var parts: Array = e.get("parts", [])
		var chips: Array[String] = []
		for part in parts:
			var ok := bool(part.get("ok", false))
			var col := "#79b8d6" if ok else "#4a5563"
			chips.append("[color=%s]%s[/color]" % [col, String(part.get("text", ""))])
		if not chips.is_empty():
			lines.append("  " + " · ".join(chips))
	if lines.is_empty():
		lines.append("[color=#4a5563]（当前构筑没有可用牌谱）[/color]")
	_pattern_tray_label.text = "\n".join(lines)


# 2026-11-15 转轮凑牌 Step 6：牌谱触发横幅。
# W 定位为「中频高潮」——频率固定后，爽感只能靠那一下的分量，所以给它一个明确的视觉时刻：
# 淡入 → 停留 0.55s → 淡出，同时保留日志与飘字。headless 下 is_inside_tree() 为 false 直接跳过。
var _pattern_banner: Control
# N-04：横幅队列——多条牌谱按固定顺序串行显示，互不覆盖（旧实现用单例变量，后一条会 queue_free 前一条）。
var _pattern_banner_queue: Array = []

# 兼容旧调用：单条横幅（清空队列后显示）
func show_pattern_banner(text: String, color: Color) -> void:
	if not is_inside_tree():
		return
	_clear_pattern_banners()
	_spawn_pattern_banner(text, color, 0)

# N-04：串行横幅——第 index 条按 y 偏移错峰显示，避免与相邻横幅同帧覆盖；
# 每条自带淡入/停留/淡出，combat 侧在两条之间 await PATTERN_BANNER_HOLD。
func show_pattern_banner_seq(text: String, color, index: int) -> void:
	if not is_inside_tree():
		return
	var banner := _spawn_pattern_banner(text, color, index)
	if banner != null:
		_pattern_banner_queue.append(banner)

func _spawn_pattern_banner(text: String, color, y_offset_index: int) -> Control:
	if not is_inside_tree():
		return null
	var banner := PanelContainer.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.r, color.g, color.b, 0.92)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	banner.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(lbl)
	add_child(banner)
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	# 多条横幅纵向错峰：每条下移 34px，避免同帧互相盖住
	banner.position = Vector2(0, size.y * 0.22 + float(y_offset_index) * 34.0)
	banner.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.14)
	tw.tween_interval(0.55)
	tw.tween_property(banner, "modulate:a", 0.0, 0.30)
	tw.tween_callback(func():
		if is_instance_valid(banner):
			banner.queue_free()
		_pattern_banner_queue.erase(banner))
	# 主变量仍指向最新一条，保持旧断言/引用可用
	_pattern_banner = banner
	return banner

func _clear_pattern_banners() -> void:
	for b in _pattern_banner_queue:
		if is_instance_valid(b):
			b.queue_free()
	_pattern_banner_queue.clear()
	_pattern_banner = null


# ---------------------------------------------------------------------------
# 头顶血条（含尾部盾段）（2026-11-16，第五版）
#
# 演进：平涂 → _draw() 复刻 pixelfx 明暗 → 盾改图标（否决）→ 盾改独立蓝条（否决）
#       → v5 盾段并入同一条血条：**同一个外框**，红段是真血，蓝段接在其后。
#
# 为什么必须是同一条：独立的小蓝条看起来像第二根条，玩家要额外理解「这是盾」。
# 并进去之后它天然读作「血条被接长了」——而机制上盾本来就是先于血量被打掉的缓冲，
# 语义与表现一致，不需要图标或数字来解释。
# ---------------------------------------------------------------------------
const VITAL_W := 46.0           # 血条（红段）宽度
const VITAL_HP_H := 8.0
const VITAL_CELLS := 6
const VITAL_FLASH := 0.34
# 盾段与血条同尺：满盾（盾量 = 生命上限）延伸一段「与血段等长」的宽度。
# 血段内宽 = VITAL_W - 2 = 44px，于是 1 点盾 = 44/hp_max px，和 1 点血用同一把尺量，
# 蓝段多长就直接读作「能挡多少血」。旧实现用 24px 上限 + 4px 下限，常见盾 6~15 全被
# 压成 4px，看起来像固定长度（2026-11-16 用户反馈）。
const SHIELD_MAX_LEN := VITAL_W - 2.0


class VitalBar:
	extends Control

	const INK := Color("#0d0a14")
	const EMPTY_TOP := Color("#2a2338")
	const EMPTY_BODY := Color("#191424")
	const WHITE := Color("#ffffff")
	const PALE_HINT := Color("#ffe9a8")

	var cells := 6
	var bar_w := 46.0
	var bar_h := 8.0
	var base := Color("#e35b50")
	var shield_color := Color("#62a1c2")
	var shield_len := 0.0        # 盾段长度（像素），0 = 无盾
	var ratio := 1.0
	var prev_ratio := 1.0
	var ghost_alpha := 0.0
	var ghost_from := 0.0
	var ghost_to := 0.0
	var frame_flash := 0.0
	var spark_t := 0.0
	var spark_at := 0.0

	func _ramp(row: int, h: float, c0: Color) -> Color:
		var r := float(row) / maxf(1.0, h - 1.0)
		if r < 0.15:
			return c0.lightened(0.50)
		if r < 0.32:
			return c0.lightened(0.24)
		if r < 0.66:
			return c0
		if r < 0.90:
			return c0.darkened(0.26)
		return c0.darkened(0.46)

	func _ghost_ramp(row: int, h: float) -> Color:
		var r := float(row) / maxf(1.0, h - 1.0)
		if r < 0.15:
			return WHITE
		if r < 0.75:
			return base.lightened(0.62).lerp(PALE_HINT, 0.45)
		return base.lightened(0.15)

	func set_ghost_alpha(a: float) -> void:
		ghost_alpha = a
		queue_redraw()

	func set_frame_flash(a: float) -> void:
		frame_flash = a
		queue_redraw()

	func set_spark(v: float) -> void:
		spark_t = v
		queue_redraw()

	# r = 血量比例；sl = 盾段长度（像素）
	# 盾紧贴当前血量末端；只有「血量末端 + 盾长」超出满血内宽时才把外框撑长
	func refresh(r: float, pr: float, sl: float = 0.0) -> void:
		ratio = clampf(r, 0.0, 1.0)
		prev_ratio = clampf(pr, 0.0, 1.0)
		shield_len = maxf(0.0, sl)
		var iw_hp: float = bar_w - 2.0
		var fw: float = iw_hp * ratio
		var inner: float = maxf(iw_hp, fw + shield_len)
		size = Vector2(inner + 2.0, bar_h)
		queue_redraw()

	func _draw() -> void:
		var h := bar_h
		var total_w: float = size.x

		# 受击辉光：整条（含盾段）外围描一圈亮边
		if ghost_alpha > 0.02:
			var gc: Color = base.lightened(0.55)
			gc.a = ghost_alpha * 0.55
			draw_rect(Rect2(-1, 0, total_w + 2, h), gc, false, 1.0)

		# 一个外框包住血段与盾段 → 读作同一条血条被接长
		var frame_col: Color = INK.lerp(base.lightened(0.55), clampf(frame_flash, 0.0, 1.0))
		draw_rect(Rect2(0, 0, total_w, h), frame_col, true)

		var ix := 1.0
		var iy := 1.0
		var ih := h - 2.0
		var iw_hp: float = bar_w - 2.0
		var iw_all: float = total_w - 2.0

		# 内轨
		draw_rect(Rect2(ix, iy, iw_all, ih), EMPTY_BODY, true)
		draw_rect(Rect2(ix, iy, iw_all, 1), EMPTY_TOP, true)

		# 血段填充
		var filled_w: float = iw_hp * ratio
		if filled_w > 0.0:
			for row in int(ih):
				draw_rect(Rect2(ix, iy + row, filled_w, 1), _ramp(row, ih, base), true)

		# 盾段：紧贴当前血量末端（不在满血位置后），同一高度、同一明暗处理
		if shield_len > 0.0 and filled_w > 0.0:
			var sx: float = ix + filled_w
			for row in int(ih):
				draw_rect(Rect2(sx, iy + row, shield_len, 1), _ramp(row, ih, shield_color), true)
			# 不再画交界分隔线：颜色变化本身就是边界，画线会让盾段变成独立小方块
			# 盾段右端高光（整条血条的收口）
			draw_rect(Rect2(sx + shield_len - 1.0, iy, 1, ih), shield_color.lightened(0.6), true)
		elif shield_len > 0.0:
			# 空血（0%）也有盾：盾从内区左端起画
			var sx0: float = ix
			for row in int(ih):
				draw_rect(Rect2(sx0, iy + row, shield_len, 1), _ramp(row, ih, shield_color), true)
			draw_rect(Rect2(sx0 + shield_len - 1.0, iy, 1, ih), shield_color.lightened(0.6), true)

		# 丢失区间白闪（只作用于血段）
		if ghost_alpha > 0.01 and ghost_to > ghost_from:
			var gx: float = ix + iw_hp * ghost_from
			var gw: float = iw_hp * (ghost_to - ghost_from)
			for row in int(ih):
				var c: Color = _ghost_ramp(row, ih)
				c.a = ghost_alpha
				draw_rect(Rect2(gx, iy + row, gw, 1), c, true)

		# 格分隔线：以血段的格宽为准，**贯穿整条**（含盾段），
		# 这样血与盾是同一套节奏，不会读成两块不同性质的东西
		if cells > 1:
			var cell_w: float = iw_hp / float(cells)
			var k: int = 1
			while true:
				var dx: float = ix + round(cell_w * float(k))
				if dx >= ix + iw_all - 1.0:
					break
				draw_rect(Rect2(dx, iy, 1, ih), INK, true)
				k += 1

		# 血量边缘高光：只在「血量末端后面没有盾」时画，
		# 否则会和盾段右端高光连成一个亮边，看起来像分层
		if filled_w > 1.0 and shield_len <= 0.0:
			draw_rect(Rect2(ix + filled_w - 1.0, iy, 1, ih), base.lightened(0.6), true)

		# 火星迸射
		if spark_t > 0.01 and spark_t < 1.0:
			var sxx: float = ix + iw_hp * clampf(spark_at, 0.0, 1.0)
			for i in 4:
				var dir: float = (float(i) - 1.5) * 0.9
				var px: float = sxx + dir * 26.0 * spark_t
				var py: float = iy + ih * 0.5 - 16.0 * spark_t + 34.0 * spark_t * spark_t
				var c2: Color = WHITE if i % 2 == 0 else base.lightened(0.45)
				c2.a = 1.0 - spark_t
				draw_rect(Rect2(round(px), round(py), 1, 1), c2, true)


var player_vitals: Control
var enemy_vitals: Control
var player_hp_bar: VitalBar
var enemy_hp_bar: VitalBar
var _pv_hp_prev := 1.0
var _ev_hp_prev := 1.0


# 面板里的 HP / 盾 / 护甲文字行全部收起：数值已改为角色头顶的血条（含盾段）。
func _hide_panel_vitals() -> void:
	for row_path in [
		"Margin/Content/Middle/PlayerPanel/VBox/HpRow",
		"Margin/Content/Middle/PlayerPanel/VBox/ShieldRow",
		"Margin/Content/Middle/EnemyPanel/VBox/HpRow",
		"Margin/Content/Middle/EnemyPanel/VBox/ArmorRow",
		"GearBox/GearCards/CharmsRow",
	]:
		var row := get_node_or_null(row_path)
		if row is Control:
			(row as Control).visible = false


func _build_vitals() -> void:
	if player_sprite != null:
		var pv := _make_vitals(player_sprite, Palette.POP_DAMAGE)
		player_vitals = pv["root"]
		player_hp_bar = pv["hp"]
	if enemy_sprite != null:
		var ev := _make_vitals(enemy_sprite, Palette.POP_DAMAGE)
		enemy_vitals = ev["root"]
		enemy_hp_bar = ev["hp"]
	_refresh_vitals()


func _make_vitals(host: Control, hp_color: Color) -> Dictionary:
	var root := Control.new()
	root.name = "Vitals"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.anchor_left = 0.5
	root.anchor_right = 0.5
	root.offset_top = -(VITAL_HP_H + 4.0)
	root.offset_bottom = -4.0
	host.add_child(root)

	var hp := VitalBar.new()
	hp.cells = VITAL_CELLS
	hp.bar_w = VITAL_W
	hp.bar_h = VITAL_HP_H
	hp.base = hp_color
	hp.shield_color = Palette.ARMOR
	hp.position = Vector2(0, 0)
	hp.size = Vector2(VITAL_W, VITAL_HP_H)
	hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hp)

	return {"root": root, "hp": hp}


# 整条（血段 + 盾段）按实际宽度重新居中
func _recenter_vitals(root: Control, bar: VitalBar) -> void:
	if root == null or not is_instance_valid(root):
		return
	var total: float = VITAL_W
	if bar != null and is_instance_valid(bar):
		total = bar.size.x
	root.offset_left = -total * 0.5
	root.offset_right = total * 0.5


func _apply_hp_bar(bar: VitalBar, root: Control, new_ratio: float, prev_ratio: float, shield_len: float) -> void:
	if bar == null or not is_instance_valid(bar):
		return
	if new_ratio < prev_ratio - 0.001:
		bar.ghost_from = clampf(new_ratio, 0.0, 1.0)
		bar.ghost_to = clampf(prev_ratio, 0.0, 1.0)
		bar.set_ghost_alpha(0.95)
		bar.set_frame_flash(1.0)
		var tw := bar.create_tween()
		tw.set_parallel(true)
		tw.tween_method(bar.set_ghost_alpha, 0.95, 0.0, VITAL_FLASH)
		tw.tween_method(bar.set_frame_flash, 1.0, 0.0, 0.20)
		bar.spark_at = clampf(new_ratio, 0.0, 1.0)
		bar.set_spark(0.0)
		var sp := bar.create_tween()
		sp.tween_method(bar.set_spark, 0.0, 1.0, 0.42)
		if root != null:
			var base_y: float = root.position.y
			var jolt := root.create_tween()
			jolt.tween_property(root, "position:y", base_y + 1.0, 0.06)
			jolt.tween_property(root, "position:y", base_y, 0.10)
	bar.refresh(new_ratio, prev_ratio, shield_len)


# 盾段长度：盾量 / 生命上限 × 血段满宽（与红段同尺）；有一点盾就至少 2px 可见
func _shield_len_of(value: int, hp_max: int) -> float:
	if value <= 0:
		return 0.0
	var r: float = clampf(float(value) / float(max(1, hp_max)), 0.0, 1.0)
	return maxf(2.0, round(r * SHIELD_MAX_LEN))


func _refresh_vitals() -> void:
	var hp_max: int = max(1, controller.state.player_hp_max)
	var shown_hp: int = _hp_display_hold if _hp_display_hold >= 0 else int(controller.state.player_hp)
	var pv_r: float = float(shown_hp) / float(hp_max)
	var pv_sl: float = _shield_len_of(int(controller.state.player_shield), hp_max)
	_apply_hp_bar(player_hp_bar, player_vitals, pv_r, _pv_hp_prev, pv_sl)
	_pv_hp_prev = pv_r
	_recenter_vitals(player_vitals, player_hp_bar)

	var ev_max: int = max(1, controller.state.enemy_hp_max)
	# N-03：命中帧前读敌人幽灵值（结算前快照），命中帧释放后才跟随真实值。
	var ev_shown_hp: int = _ev_hp_display_hold if _ev_hp_display_hold >= 0 else int(controller.state.enemy_hp)
	var ev_shown_armor: int = _ev_armor_display_hold if _ev_armor_display_hold >= 0 else int(controller.state.enemy_armor)
	var ev_r: float = float(ev_shown_hp) / float(ev_max)
	var ev_sl: float = _shield_len_of(ev_shown_armor, ev_max)
	_apply_hp_bar(enemy_hp_bar, enemy_vitals, ev_r, _ev_hp_prev, ev_sl)
	_ev_hp_prev = ev_r
	_recenter_vitals(enemy_vitals, enemy_hp_bar)



func _player_sprite_anchor() -> Control:
	return player_sprite if player_sprite != null else player_panel


func _enemy_sprite_anchor() -> Control:
	return enemy_sprite if enemy_sprite != null else enemy_panel


# 敌人属性攻击的像素特效。返回调用方需要等待的秒数（0 = 该元素暂无演出素材）。
# 表现层只读元素与立绘位置，不改任何战斗数值；时序由调用方（turn_flow）负责等待。
func play_enemy_attack_fx(elem: String) -> float:
	if fx == null:
		return 0.0
	return fx.play_enemy_attack(elem)


# ---------------------------------------------------------------------------
# 2026-11-16 P0：敌人攻击的掉血表现延迟到命中帧。
# 闸口 enemy_deal_damage 数值已同步结算；这里只管表现：
# 血条/HP 数字先压在扣血前的值，命中帧一到才掉血 + 飘字 + 屏震同拍发生。
# ---------------------------------------------------------------------------

# 闸口调用。dealt = 本次实际掉血，elem = 敌人元素（决定命中帧延迟），
# hp_before = 闸口扣血前的真实 HP（显式传入，不用 player_hp+dealt 反推，避免乘区/护盾误差）。
# 多段伤害在窗口内聚合：只刷新 timer，不重复设影子值（影子值始终是第一段扣血前 HP）。
func hold_enemy_hit(dealt: int, elem: String, hp_before: int) -> void:
	if dealt <= 0:
		return
	if _hp_display_hold < 0:
		_hp_display_hold = hp_before
	_hit_pending_text += "-%d" % dealt
	_hit_release_token += 1
	var token := _hit_release_token
	# 命中帧：冰系对齐喷气命中 T_HIT(0.95s)，其余对齐前摇末 ACT_WINDUP(0.231s)。
	var delay: float = BattleFx.T_HIT if elem == "ice" else BattleAnimator.ACT_WINDUP
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if token != _hit_release_token:
			return   # 被后续段覆盖，由最后一次统一释放
		_release_enemy_hit(), CONNECT_ONE_SHOT)


# 命中帧释放：清影子值 → 血条/数字掉到真实值 → 飘字 + 屏震同拍。
func _release_enemy_hit() -> void:
	if _hp_display_hold < 0:
		return
	_hp_display_hold = -1
	_refresh_meta()
	var anchor := _player_sprite_anchor()
	if _hit_pending_text != "":
		_popup(_hit_pending_text, Palette.POP_DAMAGE, anchor)
		_hit_pending_text = ""
	# N-03：命中帧弹玩家侧分项（原始攻击 / 盾挡 / 实际损失 / 穿透），账本聚合值，不重算。
	_player_hit_breakdown_popup()
	if animator != null:
		animator.enemy_hit_shake()


# 房间重置/读档时清空影子值，避免跨房残留旧 HP 显示。
func reset_enemy_hit_hold() -> void:
	_hit_release_token += 1
	_hp_display_hold = -1
	_hit_pending_text = ""
	_ev_hp_display_hold = -1
	_ev_armor_display_hold = -1


# ---------------------------------------------------------------------------
# N-03（2026-11-21）：敌人侧「攻击前血量预览」。
# 结算层（combat_system._capture_enemy_preview）在真实扣血后顺带产出只读账本，
# 这里只做表现：命中帧前 HP/护甲显示结算前的幽灵快照，命中帧才切到真实值。
# 幽灵值取自账本 before 快照，绝不重新计算伤害。
# ---------------------------------------------------------------------------

# 结算完成后调用：把敌人 HP/护甲压到结算前的幽灵快照（命中帧前显示旧值）。
func hold_enemy_preview() -> void:
	var pv = controller.damage_preview if controller != null else null
	if pv == null or not pv.has_enemy_attack():
		return
	_ev_hp_display_hold = max(0, pv.enemy_hp_before)
	_ev_armor_display_hold = max(0, pv.enemy_armor_before)
	_refresh_meta()   # 立刻把幽灵值渲染到血条/数字（真实值已落地但暂不显示）


# 命中帧调用（玩家总伤害飘字那一刻）：清幽灵值 → 血条/数字掉到真实值 + 分项飘字。
# 多段攻击在账本里已聚合成一条总预览，这里只弹一次，不逐段扣血。
func release_enemy_preview() -> void:
	if _ev_hp_display_hold < 0 and _ev_armor_display_hold < 0:
		return
	_ev_hp_display_hold = -1
	_ev_armor_display_hold = -1
	_refresh_meta()
	var pv = controller.damage_preview if controller != null else null
	if pv == null:
		return
	# 分项聚合飘字：护甲损失 / HP 损失 / 穿透伤害（账本值，不重算）
	var parts: Array[String] = []
	if pv.enemy_armor_loss > 0:
		parts.append("甲-%d" % pv.enemy_armor_loss)
	if pv.enemy_hp_loss > 0:
		parts.append("血-%d" % pv.enemy_hp_loss)
	if pv.enemy_pierce_damage > 0:
		parts.append("穿-%d" % pv.enemy_pierce_damage)
	if not parts.is_empty():
		_popup(" ".join(parts), Palette.POP_DAMAGE, _enemy_sprite_anchor())
	# 屏震与掉血同拍（沿用玩家侧受击屏震）
	if animator != null:
		animator.enemy_hit_shake()


# 玩家侧受击命中帧（_release_enemy_hit）顺带弹分项飘字：原始攻击/盾挡/实际损失。
# 账本里已聚合多段，这里只弹一次；数值全部读账本，不重算。
func _player_hit_breakdown_popup() -> void:
	var pv = controller.damage_preview if controller != null else null
	if pv == null or not pv.has_player_attack():
		return
	var parts: Array[String] = []
	parts.append("攻%d" % pv.player_raw_attack)
	if pv.player_shield_blocked > 0:
		parts.append("盾挡%d" % pv.player_shield_blocked)
	parts.append("受%d" % pv.player_hp_loss)
	if pv.player_pierce_bypass > 0:
		parts.append("穿%d" % pv.player_pierce_bypass)
	_popup(" ".join(parts), Palette.POP_DAMAGE, _player_sprite_anchor(), true)


# 敌人立绘切换（RoomData.art 数据驱动）：旧图退场（淡出+缩小）→ 换图 → 新图入场（淡入复位）。
# tex = null 恢复默认敌人图（非 BOSS 房）。入场时序由 controller._start_room 触发。
# 尺寸按 RoomData.art_scale 倍率（基准 48×48；1.0 = 同规格，2.0 = 96×96）——只允许整数倍。
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


func _cell_style(elem: String) -> StyleBox:
	# 2026-11-17：转轮格统一用 slot_blue.png 金框（与普通武器/技能/消耗品格相同的样式，
	# 含四角 L 角装饰）。此前透明化露出底图框，导致转轮格缺四角装饰、与其他槽位不一致。
	# 冻结/干扰/锁轮警告框在 _refresh_cell 里用独立 StyleBoxFlat 覆盖，不受此处影响。
	if _cell_style_cache.has(elem):
		return _cell_style_cache[elem]
	var sb := StyleBoxTexture.new()
	sb.texture = SLOT_FRAME_TEX
	sb.set_texture_margin_all(8.0)
	_cell_style_cache[elem] = sb
	return sb


func _refresh_cell(reel: int, row: int) -> void:
	var b: Button = cells[reel][row]
	var s: SymbolData = controller.state.grid[reel][row]
	b.add_theme_font_size_override("font_size", TypeScale.REEL if s.kind == "trash" else TypeScale.SYMBOL)
	# S4：按「有效元素」着色。同一个共享符号（如 special.tres）在火剑下是火、在铁剑下是无属性，
	# 靠边框/底色一眼分辨谁吃 ×1.5；元素为 none 时回落符号自身配色。
	var elem = _cell_element(reel, row)
	# 2026-11-17：格底元素色条已移除；元素色由图标粒子(fx2.color)与文字染色(fc)表达。
	var rs = controller.reel_system
	# 2026-10-30：旋转中的未停列由 ReelSpinView 显示纵向滚动，格子自身清空文字避免重影。
	var scrolling: bool = rs != null and rs.spinning and not rs.reel_stopped[reel]
	var layer: TextureRect = cell_icon_layers[reel][row]
	if scrolling:
		b.icon = null
		b.text = ""
		layer.visible = false
	# M3-03：有图标则用图标覆盖层（文字清空）；无图回落 label。
	elif s.icon_tex != null:
		b.icon = null
		b.text = ""
		layer.texture = _cell_symbol_tex(reel, row, s)
		_cell_want_icon[reel][row] = layer.texture
		_cell_want_text[reel][row] = ""
		var fx2: CPUParticles2D = cell_icon_fx[reel][row]
		fx2.color = ElementCounter.color(elem) if elem != "none" else s.color
	else:
		b.icon = null
		_cell_want_icon[reel][row] = null
		_cell_want_text[reel][row] = s.label
	# 旋转中滚动视觉会盖住格子自身文字，这里不再写 b.text；预览统一由 P1 预览行承担。
	var fc: Color = s.color if elem == "none" else s.color.lerp(ElementCounter.color(elem), 0.55)
	# T30 冻结格（失效格）：蓝色边框框住作为 frost 提示（❄ 前缀/冰色文字不需要，边框即提示）
	var frozen: bool = controller.state.frozen_cols.has(reel)
	# 2026-08-14 UX：干扰/锁轮列标记——jam=红框（按停作废变废铁）、lock=黄框（按停保留旋转前符号）。
	# 敌人声明意图后即显示（spin 前可见），旋转中随列位持续；不再"按下去才知道被吞"
	var jammed: bool = controller.state.pending_jam_reel == reel
	var locked: bool = controller.state.pending_lock_reel == reel
	if not frozen:
		b.add_theme_color_override("font_color", fc)
		b.add_theme_color_override("font_disabled_color", fc)
		b.add_theme_color_override("font_hover_color", fc)
		b.add_theme_color_override("font_pressed_color", fc)
	# 状态警告框用纯色 StyleBoxFlat 覆盖（纹理框没有 border_color，不能 duplicate 后改色）
	var warn: Color = Color(0, 0, 0, 0)
	if frozen:
		warn = ElementCounter.color("ice")      # 冻结格：蓝框，frost 触发提示
	elif jammed:
		warn = Palette.POP_DAMAGE               # 干扰列：红框，按停即废铁
	elif locked:
		warn = Palette.ACCENT_GOLD              # 锁轮列：金框，按停保留旋转前符号
	var sb: StyleBox = _cell_style(elem)
	if warn.a > 0.0:
		var wsb := StyleBoxFlat.new()
		wsb.set_corner_radius_all(Palette.PANEL_RADIUS)
		wsb.bg_color = Palette.CELL_BG
		wsb.set_border_width_all(3)
		wsb.border_color = warn
		sb = wsb
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("disabled", sb)


func _refresh_meta() -> void:
	controller.invalidate_state()   # 语义刷新兜底：任何写方遗漏的字段变更在此重建（低频，开销可忽略）
	_refresh_gear_icons()
	var is_boss = controller._is_boss_room(controller.state.room_index)
	var essence_names := []
	for e in controller.state.room_element_mult:
		essence_names.append(ElementCounter.label(e))
	# C3 顶栏：ACT + 房间在左（金币紧随其后）；精华/房型等细节进 tooltip，不占主信息位
	var act_txt := "ACT I"
	var act_names := {1: "I", 2: "II", 3: "III"}
	var rooms: Array = controller.state.ROOMS
	if rooms.size() > 0 and controller.state.room_index >= 0 and controller.state.room_index < rooms.size():
		var a: int = int(rooms[controller.state.room_index].act)
		act_txt = "ACT %s" % act_names.get(a, str(a))
	if controller.node_mode and controller.board != null:
		# M2：棋盘进度用「第 x/路线长度 格」表达，不再显示线性「房 x/25」。
		room_label.text = controller.board.progress_text()
		var cur: Dictionary = controller.board.current_node()
		room_label.tooltip_text = "%s\n%s" % [
			String(cur.get("title", "")), String(cur.get("desc", ""))]
	else:
		room_label.text = "%s · 房 %d/%d" % [act_txt, controller.state.room_index + 1, rooms.size()]
		room_label.tooltip_text = "房间 %d/%d%s\n精华: %s" % [
			controller.state.room_index + 1, rooms.size(),
			" · ★BOSS" if is_boss else "",
			"、".join(essence_names) if not essence_names.is_empty() else "无"]
	turn_label.text = "回合 %d" % controller.state.turn_count
	gold_label.text = "%d" % controller.state.gold
	gold_label.tooltip_text = "金币"
	weapons_title.text = "武器 %d/%d" % [controller.state.selected_loadout.size(), controller._loadout_system.cat_cap("weapon")]
	# Step 5 信息层级：HP 是左栏第一重点（生命绿；≤35% 转危险红）；护盾有值才单独占一行（护盾蓝）
	var hp_now: int = _hp_display_hold if _hp_display_hold >= 0 else int(controller.state.player_hp)
	var hp_max: int = max(1, controller.state.player_hp_max)
	var hp_color: Color = Palette.POP_DAMAGE if float(hp_now) / float(hp_max) <= 0.35 else Palette.POP_HEAL
	player_hp_label.text = "%d/%d" % [hp_now, controller.state.player_hp_max]
	player_hp_label.add_theme_color_override("font_color", hp_color)
	player_hp_label.tooltip_text = "生命 %d/%d" % [hp_now, controller.state.player_hp_max]
	player_hp_icon.modulate = hp_color
	player_shield_label.text = "盾 %d" % controller.state.player_shield
	_refresh_vitals()   # 头顶血条/盾条同步刷新
	# 2026-11-19 等级已移除：玩家标题固定，成长常驻「艺N 铭N」（明细进 tooltip）
	player_title.text = "玩家"
	var growth_tags: Array[String] = []
	if not controller.growth.perk_ids.is_empty():
		growth_tags.append("艺%d" % controller.growth.perk_ids.size())
	var imp_total: int = controller.mastery.imprint_total()
	if imp_total > 0:
		growth_tags.append("铭%d" % imp_total)
	var growth_short: String = " ".join(growth_tags)
	var growth_tip: String = "%s\n%s" % [
		controller.growth.detail_text(), controller.mastery.summary_line()]
	# G7-4：机器摘要统一口径接入整备页 tooltip（§11.2 整备入口；tooltip 不影响小屏布局）
	if controller.machine_summary != null:
		var mlines: Array = controller.machine_summary.lines()
		if not mlines.is_empty():
			var mparts: Array[String] = []
			for l in mlines:
				mparts.append(String(l))
			growth_tip += "\n—— 机器摘要 ——\n" + "\n".join(mparts)
	player_level_label.text = growth_short
	player_level_label.visible = true
	player_level_label.tooltip_text = growth_tip
	player_title.tooltip_text = growth_tip
	player_buff_label.text = "技能: " + controller._buff_summary()
	# T30 玩家 frost 状态（冻结转轮列数）
	if controller.state.player_frost > 0:
		player_buff_label.text += " · ❄霜冻×%d" % controller.state.player_frost
	# 2026-08-09 酸蚀恶鬼：玩家 DoT 状态（毒层；≥ 爆炸阈值整行警示色）
	var poison: int = int(controller.state.player_status.get("poison", 0))
	# 2026-11-12 Step 3：灼烧 DoT（熔壳壁垒），与酸蚀并列展示
	var burn: int = int(controller.state.player_status.get("burn", 0))
	if poison > 0:
		player_buff_label.text += " · ☣酸蚀×%d" % poison
		if poison >= controller.state.player_dot_bomb_stacks:
			player_buff_label.add_theme_color_override("font_color", Palette.POP_DAMAGE)
		else:
			player_buff_label.remove_theme_color_override("font_color")
	elif burn > 0:
		player_buff_label.add_theme_color_override("font_color", Palette.POP_DAMAGE)
	else:
		player_buff_label.remove_theme_color_override("font_color")
	if burn > 0:
		player_buff_label.text += " · 🔥灼烧×%d" % burn
	# 2026-11-12 Step 1：玩家侧减益（虚弱/易伤/腐蚀/禁疗/目盲/缠绕/反噬…）
	var debuff_txt: String = controller.debuff_summary() if controller.debuffs != null else ""
	if debuff_txt != "":
		player_buff_label.text += " · " + debuff_txt
		player_buff_label.tooltip_text = controller.debuffs.detail_text()
	player_buff_label.visible = controller._buff_summary() != "无" or controller.state.player_frost > 0 or poison > 0 or burn > 0 or debuff_txt != ""
	enemy_name_label.text = controller.state.enemy_name
	enemy_name_label.tooltip_text = controller.state.enemy_name
	enemy_stage_name.text = controller.state.enemy_name
	enemy_stage_name.visible = is_boss
	boss_badge.visible = is_boss
	# C4-1：右栏图标化——HP / 护甲 / 充能各一组图标 + 数值；顺序 name → HP → armor → 弱/抗 → 意图 → 充能 → 状态 → 机制
	enemy_hp_label.text = "%d/%d" % [max(controller.state.enemy_hp, 0), controller.state.enemy_hp_max]
	enemy_hp_label.tooltip_text = "生命 %d/%d" % [max(controller.state.enemy_hp, 0), controller.state.enemy_hp_max]
	# HP 只在右栏显示，中央不再重复
	var ehp_now: int = max(controller.state.enemy_hp, 0)
	var ehp_max: int = max(1, controller.state.enemy_hp_max)
	var ehp_color: Color = Palette.POP_DAMAGE if float(ehp_now) / float(ehp_max) <= 0.35 else Palette.POP_HEAL
	enemy_hp_label.add_theme_color_override("font_color", ehp_color)
	# 护甲（扁平池）：有护甲才显示；破甲后剩 0 也显示（提示已破甲窗口），仅无护甲敌人隐藏
	# 护甲条已改为敌人头顶的蓝色条，面板行保持隐藏（见 _hide_panel_vitals）
	enemy_armor_label.text = "%d/%d" % [max(controller.state.enemy_armor, 0), controller.state.enemy_armor_max]
	enemy_armor_label.tooltip_text = "护甲 %d/%d" % [max(controller.state.enemy_armor, 0), controller.state.enemy_armor_max]
	enemy_status_label.text = "状态: " + ("无" if controller.state.enemy_status.is_empty() else controller.status_system.status_summary(controller.state.enemy_status))
	# C4-3 / 2026-11-20 修复：机制说明文本过长会撑高敌人面板 VBox，
	# 遮挡 TopBar 的「商店 / 下一房」按钮。面板上只保留极短的节奏窗口标签，
	# 完整机制说明移到 tooltip（悬停可查，不占布局）。
	var rhythm := ""
	if controller.current_gimmick != null:
		rhythm = String(controller.current_gimmick.rhythm_window(controller))
	var short_txt: String = "【%s】" % rhythm if rhythm != "" else ""
	enemy_mechanic_label.text = short_txt
	enemy_mechanic_label.visible = short_txt != ""
	var room_list: Array = controller.state.ROOMS
	var cur_room: RoomData = room_list[controller.state.room_index] if controller.state.room_index >= 0 and controller.state.room_index < room_list.size() else null
	var mech_txt: String = String(cur_room.mechanic_summary) if cur_room != null else ""
	enemy_mechanic_label.tooltip_text = ("【%s】\n%s" % [rhythm, mech_txt]) if mech_txt != "" else short_txt
	match rhythm:
		"爆发": enemy_mechanic_label.add_theme_color_override("font_color", Palette.POP_DAMAGE)
		"恢复": enemy_mechanic_label.add_theme_color_override("font_color", Palette.POP_HEAL)
		"蓄势": enemy_mechanic_label.add_theme_color_override("font_color", Palette.ACCENT_GOLD)
		_: enemy_mechanic_label.add_theme_color_override("font_color", Palette.MUTED)
	# T21 元素充能条：克制命中进度（满额释放元素爆发）+ 主导元素（2026-08-14：本回合命中最多的元素）
	if controller.state.charge_points > 0:
		var lead_txt := ""
		var lead_max := 0
		var lead_elem := ""
		for e in controller.state.charge_elem_counts:
			if int(controller.state.charge_elem_counts[e]) > lead_max:
				lead_max = int(controller.state.charge_elem_counts[e])
				lead_elem = e
		if lead_elem != "":
			lead_txt = " · 主导%s" % ElementCounter.label(lead_elem)
		enemy_charge_label.text = "%d/%d%s" % [controller.state.charge_points, controller.BALANCE.charge_max, lead_txt]
		# Step 5 层级：充能是进度信息，平时弱化；差 1 点即可爆发时转金色提示
		enemy_charge_label.add_theme_color_override("font_color",
			Palette.ACCENT_GOLD if controller.state.charge_points >= controller.BALANCE.charge_max - 1 else Palette.MUTED)
		enemy_charge_label.tooltip_text = "元素充能 %d/%d" % [controller.state.charge_points, controller.BALANCE.charge_max]
		enemy_charge_row.visible = true
	else:
		enemy_charge_label.text = "0/%d" % controller.BALANCE.charge_max
		enemy_charge_label.add_theme_color_override("font_color", Palette.MUTED)
		enemy_charge_label.tooltip_text = "元素充能 0/%d" % controller.BALANCE.charge_max
		enemy_charge_row.visible = true
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
	# C3：旧 RunLabel 从顶栏移除；本局加成/共鸣信息改挂左栏弱信息行 tooltip，不丢数据也不占主信息位
	var run_txt: String = "无" if parts.is_empty() else " / ".join(parts)
	player_buff_label.tooltip_text = "%s\n本局加成: %s" % [player_buff_label.text, run_txt]
	player_title.tooltip_text = "%s\n%s" % [growth_tip, player_buff_label.tooltip_text]
	enemy_intent_icon.visible = false
	var stage_intent_txt := ""
	if controller.state.enemy_intent.is_empty():
		enemy_intent_label.text = "—"
		enemy_intent_label.tooltip_text = ""
	else:
		# T20：图标/名字读 IntentData（enemy_intent.data）；攻击/重击同时显示在中央 BOSS 头顶
		var t = controller.state.enemy_intent["type"]
		var data: IntentData = controller.state.enemy_intent.get("data")
		var icon: String = data.icon if data != null and data.icon != "" else ""
		var name_txt: String = _intent_display_name(t)
		if data != null and data.display_name != "":
			name_txt = data.display_name
		match t:
			"attack", "heavy":
				enemy_intent_label.text = "%s %d" % [name_txt, controller.state.enemy_intent["value"]]
				enemy_intent_icon.visible = true
				stage_intent_txt = enemy_intent_label.text
			"jam", "lock", "chaos", "auto_stop":
				enemy_intent_label.text = "%s%s" % [icon if icon != "" else "☣", name_txt]
			"none":   enemy_intent_label.text = "—"
			_:        enemy_intent_label.text = "%s%s" % [icon if icon != "" else "", name_txt]
		# L3 §6.1：重击预警提示——本回合防御/治疗符号收益 ×1.5，引导玩家改按停目标。
		if String(t) == "heavy":
			enemy_intent_label.tooltip_text = "⚠ 重击预警：本回合防御/治疗符号收益 ×1.5（改按停目标抓盾/治疗）"
			enemy_intent_label.text += " 💊"
		else:
			enemy_intent_label.tooltip_text = "可用净化药剂解除" if String(t) in ["jam", "lock", "chaos", "auto_stop"] else ""
	# Step 5 层级：下一意图是右栏第一重点——伤害类意图用危险红，干扰类（可用净化解除）用交互金，
	# 无意图回落弱信息；字号升到正文档，避免与状态/充能同等亮度。
	var has_intent: bool = not controller.state.enemy_intent.is_empty() and String(controller.state.enemy_intent.get("type", "none")) != "none"
	var intent_color: Color = Palette.MUTED
	if has_intent:
		match String(controller.state.enemy_intent.get("type", "none")):
			"attack", "heavy": intent_color = Palette.POP_DAMAGE
			_:                  intent_color = Palette.ACCENT_GOLD
	enemy_intent_label.add_theme_color_override("font_color", intent_color)
	enemy_intent_label.add_theme_font_size_override("font_size", TypeScale.BODY)
	enemy_stage_intent.visible = is_boss and stage_intent_txt != ""
	enemy_stage_intent_label.text = stage_intent_txt


func _intent_display_name(t: String) -> String:
	# T20：IntentData.display_name 优先；未定义时回落默认名（新意图类型兜底）
	match t:
		"jam":    return "注废"
		"lock":   return "锁轮"
		"chaos":  return "乱权"
		"heavy":  return "重击"
		"attack": return "攻击"
		"auto_stop": return "夺轮"
	return t


# 2026-08-07 通用武器替换弹层（商店 / BOSS 战利品共用）：顶部显示新武器详情，下方点旧武器替换
var _replace_dialog: PanelContainer = null
var _replace_vbox: VBoxContainer = null
var _replace_scroll: ScrollContainer = null   # 2026-11-08：内容超过屏幕时可滚动，避免底部按钮被裁掉
var _replace_cb: Callable = Callable()
var _replace_cancel_cb: Callable = Callable()   # M2：棋盘武器格取消时回到棋盘（默认空 = 旧行为）
var _camp_dialog: PanelContainer = null
var _camp_vbox: VBoxContainer = null
var _camp_buy_cb: Callable = Callable()
var _camp_close_cb: Callable = Callable()
var _growth_picker = null   # 旧 M2 独立成长结算覆盖层；M1 起真实流程不再调用（保留供回滚 / 对照）

# M2-03 成长结算（技艺 + 铭印合并为一屏）：懒构建覆盖层；全部选定并确认后回调 on_confirm({key: id})
func show_growth_settlement(title: String, sections: Array, on_confirm: Callable, summary: String = "") -> void:
	if _growth_picker == null:
		_growth_picker = GROWTH_PICKER.new()
		add_child(_growth_picker)
	_growth_picker.show_sections(title, sections, on_confirm, summary)


func hide_growth_picker() -> void:
	if _growth_picker != null:
		_growth_picker.hide_picker()


func request_weapon_replace(title: String, new_weapon_info: String, on_chosen: Callable, new_path: String = "", on_cancel: Callable = Callable()) -> void:
	_replace_cb = on_chosen
	_replace_cancel_cb = on_cancel
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
		# 2026-11-08 修复：两把旧武器 + 替换预览 + 新武器详情在 480×270 下最高可到 ~300px，
		# 居中面板会上下溢出，底部「取消 / 替换」按钮被裁到屏幕外。改为限高滚动：
		# 内容不超屏时仍按内容高度（外观不变），超屏时出滚动条，所有按钮都能滚到。
		_replace_scroll = ScrollContainer.new()
		_replace_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_replace_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_replace_vbox = VBoxContainer.new()
		_replace_vbox.add_theme_constant_override("separation", 4)
		_replace_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_replace_scroll.add_child(_replace_vbox)
		dlg.add_child(_replace_scroll)
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
		# G2-01：先给「旧武器卸下」行（当前贡献 + 熟练/调律保留说明），再给带子/共鸣增减。
		# 2026-11-15：逐槽表达——每把旧武器就是这个槽的当前占用者，槽号由 _weapon_off_info 带出。
		var slot: int = controller.slot_of(path)
		var off = _label("", TypeScale.TINY)
		off.text = controller._weapon_off_info(path, slot)
		off.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		off.custom_minimum_size = Vector2(300, 0)
		off.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		off.add_theme_color_override("font_color", Palette.MUTED)
		_replace_vbox.add_child(off)
		if new_path != "":
			# 继承说明：通用锻造跟槽位，换装不变；熟练与调律留在旧武器上。
			var inherit: String = ""
			if controller.weapon_slots != null:
				inherit = String(controller.weapon_slots.describe(slot))
			var inh = _label("", TypeScale.TINY)
			inh.text = ("继承：该槽通用锻造保持不变（%s）" % inherit) if inherit != "" \
				else "继承：该槽还没有通用锻造，装入后可从这里开始投入"
			inh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			inh.custom_minimum_size = Vector2(300, 0)
			inh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			inh.add_theme_color_override("font_color", Palette.ACCENT_GOLD)
			_replace_vbox.add_child(inh)
			# 数值对照：与真实战斗同一公式（weapon_power_in_slot / weapon_hit_in_slot）
			var old_atk: int = controller.weapon_power_in_slot(path, slot)
			var new_atk: int = controller.weapon_power_in_slot(new_path, slot)
			var old_hit: int = int(round(controller.weapon_hit_in_slot(path, slot) * 100.0))
			var new_hit: int = int(round(controller.weapon_hit_in_slot(new_path, slot) * 100.0))
			var d_atk := new_atk - old_atk
			var d_hit := new_hit - old_hit
			var cmp = _label("", TypeScale.TINY)
			cmp.text = "数值：攻 %d → %d（%s%d）· 命中 %d%% → %d%%（%s%d）" % [
				old_atk, new_atk, "+" if d_atk >= 0 else "", d_atk,
				old_hit, new_hit, "+" if d_hit >= 0 else "", d_hit]
			cmp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cmp.custom_minimum_size = Vector2(300, 0)
			cmp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_replace_vbox.add_child(cmp)
			# 对已公开 BOSS 的元素倍率：只显示可准确计算的两项，不合成「胜率」。
			var boss_elem: String = controller.board_boss_element()
			var old_wd: WeaponData = load(path)
			var new_wd: WeaponData = load(new_path)
			if boss_elem != "" and old_wd != null and new_wd != null:
				var o_e := String(old_wd.element)
				var n_e := String(new_wd.element)
				var el = _label("", TypeScale.TINY)
				el.text = "对 BOSS（%s）：%s ×%.2f → %s ×%.2f" % [
					ElementCounter.label(boss_elem),
					ElementCounter.label(o_e), ElementCounter.multiplier(o_e, boss_elem),
					ElementCounter.label(n_e), ElementCounter.multiplier(n_e, boss_elem)]
				el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				el.custom_minimum_size = Vector2(300, 0)
				el.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				el.add_theme_color_override("font_color", Palette.MUTED)
				_replace_vbox.add_child(el)
		# M1-04：替换预览——真实格数增减 + 共鸣得失（口径同 build_strips，纯计算不写入局内状态）
		if new_path != "":
			var hypo: Array = controller.selected_loadout.duplicate()
			hypo.erase(path)
			hypo.append(new_path)
			var styles: Dictionary = controller._forge_styles.preview_map() if controller._forge_styles != null else {}
			var lines := ReelPreview.diff_lines(
				controller.selected_loadout, hypo,
				controller.selected_skills, controller.selected_charms,
				controller.room_element_mult, controller._reward_system.run_symbol_bonus,
				controller.deprived_level, controller.pending_chaos, int(controller.boss_trash),
				controller.mastery.tune_map(), controller.mastery.tune_map(), styles, styles)
			var dl = _label("", TypeScale.TINY)
			dl.text = "替换后：无变化" if lines.is_empty() else "替换后：" + "；".join(lines)
			dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			dl.custom_minimum_size = Vector2(300, 0)
			dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			dl.add_theme_color_override("font_color", Palette.MUTED)
			_replace_vbox.add_child(dl)
			# G2-4：构筑得失完整比较——牌谱/签名/元素覆盖的新增与失去。
			# 改造休眠（换下武器保留铸式但暂停贡献）已由上面的 _weapon_off_info 表达。
			var build_diff: String = controller.build_swap_build_diff(path, new_path)
			if build_diff != "":
				var bd = _label("", TypeScale.TINY)
				bd.text = "构筑：" + build_diff
				bd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				bd.custom_minimum_size = Vector2(300, 0)
				bd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				bd.add_theme_color_override("font_color", Palette.ACCENT_GOLD)
				_replace_vbox.add_child(bd)
		var btn = UI_BUTTON.instantiate()
		btn.text = "替换「%s」" % controller._shop_name(path, "weapon")
		btn.custom_minimum_size = Vector2(220, 34)
		btn.pressed.connect(_on_replace_chosen.bind(path))
		_replace_vbox.add_child(btn)
	var cancel = UI_BUTTON.instantiate()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(120, 30)
	cancel.pressed.connect(_on_replace_cancelled)
	_replace_vbox.add_child(cancel)
	_replace_dialog.visible = true
	_replace_dialog.modulate.a = 0.0   # 量高度期间先不显示，避免「先塌成一条再撑开」的闪动
	_fit_replace_dialog()


# 2026-11-08：替换弹层限高——内容超过 HUD 高度时压缩到可滚动高度，保证按钮不会被裁掉。
# 不超屏时保持「按内容大小居中」的旧外观；每次打开都回到顶部。
func _fit_replace_dialog() -> void:
	if _replace_scroll == null or _replace_vbox == null:
		return
	var max_h: float = size.y - 16.0 if size.y > 0.0 else 254.0
	max_h = maxf(max_h, 120.0)
	# 宽度先固定 320（此时高度为 0 也能正确折行），量一次内容自然高度，再夹到可用高度
	_replace_scroll.custom_minimum_size = Vector2(320.0, 0.0)
	await get_tree().process_frame
	if not is_instance_valid(_replace_scroll) or not is_instance_valid(_replace_vbox):
		return
	await get_tree().process_frame
	if not is_instance_valid(_replace_scroll) or not is_instance_valid(_replace_vbox):
		return
	var need: float = _replace_vbox.get_combined_minimum_size().y
	_replace_scroll.custom_minimum_size = Vector2(320.0, minf(need, max_h))
	_replace_scroll.scroll_vertical = 0
	if is_instance_valid(_replace_dialog):
		_replace_dialog.modulate.a = 1.0


func _on_replace_cancelled() -> void:
	_replace_dialog.visible = false
	var cb = _replace_cancel_cb
	_replace_cb = Callable()
	_replace_cancel_cb = Callable()
	if cb.is_valid():
		cb.call()


func _on_replace_chosen(old_path: String) -> void:
	_replace_dialog.visible = false
	var cb = _replace_cb
	_replace_cb = Callable()
	_replace_cancel_cb = Callable()
	if cb.is_valid():
		cb.call(old_path)


# G2-01 补给：休整后的一次性营地商店（最多买 1 件，离开不扣费）。
func request_camp_supply(offers: Array, on_buy: Callable, on_close: Callable) -> void:
	_camp_buy_cb = on_buy
	_camp_close_cb = on_close
	if _camp_dialog == null:
		_camp_dialog = PanelContainer.new()
		_camp_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_camp_dialog.z_index = 95
		var sb = StyleBoxFlat.new()
		sb.bg_color = Palette.BG_OVERLAY
		_camp_dialog.add_theme_stylebox_override("panel", sb)
		var center = CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var dlg = PanelContainer.new()
		var sb2 = StyleBoxFlat.new()
		sb2.bg_color = Palette.PANEL_BG
		sb2.border_color = Palette.ACCENT_GOLD
		sb2.set_border_width_all(2)
		dlg.add_theme_stylebox_override("panel", sb2)
		_camp_vbox = VBoxContainer.new()
		_camp_vbox.add_theme_constant_override("separation", 6)
		dlg.add_child(_camp_vbox)
		center.add_child(dlg)
		_camp_dialog.add_child(center)
		# 与 branch_screen 同级（都挂在 duel 根节点）：地图视图会 hud.hide()，
		# 营地面板若挂在 HUD 下会被一起隐藏，导致「看不见营地 / 到 BOSS 才突然弹出」。
		get_parent().add_child(_camp_dialog)
	for c in _camp_vbox.get_children():
		_camp_vbox.remove_child(c)
		c.queue_free()
	var title_lbl = _label("营地补给", TypeScale.OVERLAY)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_camp_vbox.add_child(title_lbl)
	var hint = _label("休整完成。可花金币购买 1 件；离开不扣费。", TypeScale.TINY)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_camp_vbox.add_child(hint)
	for offer in offers:
		var price := int(offer.get("price", 0))
		var btn = UI_BUTTON.instantiate()
		btn.text = "%s · %d 金" % [String(offer.get("name", "")), price]
		btn.custom_minimum_size = Vector2(260, 32)
		btn.disabled = bool(offer.get("sold", false)) or controller.gold < price
		btn.pressed.connect(_on_camp_offer_pressed.bind(offer))
		_camp_vbox.add_child(btn)
	var close = UI_BUTTON.instantiate()
	close.text = "离开营地"
	close.custom_minimum_size = Vector2(140, 30)
	close.pressed.connect(_on_camp_close_pressed)
	_camp_vbox.add_child(close)
	_camp_dialog.visible = true


func _on_camp_offer_pressed(offer: Dictionary) -> void:
	if _camp_buy_cb.is_valid():
		_camp_buy_cb.call(offer)


func _on_camp_close_pressed() -> void:
	hide_camp_supply()
	if _camp_close_cb.is_valid():
		_camp_close_cb.call()


func hide_camp_supply() -> void:
	if _camp_dialog != null:
		_camp_dialog.visible = false


# ---------------------------------------------------------------------------
# M-02a（§10.2）：Boss 前营地二选一。休整（回 25% HP）/ 整理（精简符号或卸技能），
# 完成后进房间歇态（可开商店 / 下一房进 Boss）。只负责展示与选择，不做任何战斗结算。
# 满血仍给整理选项；无合法整理候选时不显示假的整理按钮；提供明确「继续」入口不空屏。
# ---------------------------------------------------------------------------
var _linear_camp_dialog: PanelContainer = null
var _linear_camp_vbox: VBoxContainer = null
var _camp_rest_cb: Callable = Callable()
var _camp_trim_cb: Callable = Callable()
var _camp_continue_cb: Callable = Callable()

func request_linear_camp(can_trim: bool, rest_need: int, on_rest: Callable, on_trim: Callable, on_continue: Callable) -> void:
	_camp_rest_cb = on_rest
	_camp_trim_cb = on_trim
	_camp_continue_cb = on_continue
	if _linear_camp_dialog == null:
		_linear_camp_dialog = PanelContainer.new()
		_linear_camp_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_linear_camp_dialog.z_index = 95
		var sb = StyleBoxFlat.new()
		sb.bg_color = Palette.BG_OVERLAY
		_linear_camp_dialog.add_theme_stylebox_override("panel", sb)
		var center = CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var dlg = PanelContainer.new()
		var sb2 = StyleBoxFlat.new()
		sb2.bg_color = Palette.PANEL_BG
		sb2.border_color = Palette.ACCENT_GOLD
		sb2.set_border_width_all(2)
		dlg.add_theme_stylebox_override("panel", sb2)
		_linear_camp_vbox = VBoxContainer.new()
		_linear_camp_vbox.add_theme_constant_override("separation", 6)
		dlg.add_child(_linear_camp_vbox)
		center.add_child(dlg)
		_linear_camp_dialog.add_child(center)
		get_parent().add_child(_linear_camp_dialog)
	for c in _linear_camp_vbox.get_children():
		_linear_camp_vbox.remove_child(c)
		c.queue_free()
	var title_lbl = _label("营地", TypeScale.OVERLAY)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_linear_camp_vbox.add_child(title_lbl)
	var hint = _label("Boss 前可休整或整理（二选一），也可直接继续。", TypeScale.TINY)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_linear_camp_vbox.add_child(hint)
	# 休整：满血时显示「无需恢复」并禁用（不误导），残血可用。
	var rest_btn = UI_BUTTON.instantiate()
	rest_btn.text = "休整 · 恢复 25%% 最大 HP%s" % ("（已满血，无需恢复）" if rest_need <= 0 else "（+%d）" % rest_need)
	rest_btn.custom_minimum_size = Vector2(280, 32)
	rest_btn.disabled = rest_need <= 0
	rest_btn.pressed.connect(_on_linear_camp_rest)
	_linear_camp_vbox.add_child(rest_btn)
	# 整理：无合法候选时不提供假选项（按钮不显示），避免空选择软锁。
	if can_trim:
		var trim_btn = UI_BUTTON.instantiate()
		trim_btn.text = "整理 · 精简 1 个符号 / 卸除 1 个技能"
		trim_btn.custom_minimum_size = Vector2(280, 32)
		trim_btn.pressed.connect(_on_linear_camp_trim)
		_linear_camp_vbox.add_child(trim_btn)
	# 明确继续入口：不选也可直接进房间歇态（再进 Boss）。
	var cont_btn = UI_BUTTON.instantiate()
	cont_btn.text = "继续（进入 Boss 前整备）"
	cont_btn.custom_minimum_size = Vector2(280, 30)
	cont_btn.pressed.connect(_on_linear_camp_continue)
	_linear_camp_vbox.add_child(cont_btn)
	_linear_camp_dialog.visible = true

func hide_linear_camp() -> void:
	if _linear_camp_dialog != null:
		_linear_camp_dialog.visible = false

func _on_linear_camp_rest() -> void:
	hide_linear_camp()
	if _camp_rest_cb.is_valid():
		_camp_rest_cb.call()

func _on_linear_camp_trim() -> void:
	hide_linear_camp()
	if _camp_trim_cb.is_valid():
		_camp_trim_cb.call()

func _on_linear_camp_continue() -> void:
	hide_linear_camp()
	if _camp_continue_cb.is_valid():
		_camp_continue_cb.call()


# ============================================================================
# G7-B B3 灰盒入口：主动减带（符号精简 / 技能卸除）
# 棋盘屏按钮与线性间歇按钮共用这一个弹层；候选 / 预览 / 应用全走 StripTrimSystem，
# 这里只负责展示与确认——不重算格数、不改数值、不做退款。
# 与营地弹层同理挂在 duel 根节点：棋盘视图会 hud.hide()，挂在 HUD 下会被一起隐藏。
# ============================================================================
var _trim_dialog: PanelContainer = null
var _trim_vbox: VBoxContainer = null
var _trim_preview: Label = null
var _trim_confirm: Button = null
var _trim_pending: Dictionary = {}
# M-02a：营地整理完成后的回调（可选）；普通间歇态精简不传，行为不变。
var _trim_done_cb: Callable = Callable()


func show_trim_dialog(done_cb: Callable = Callable()) -> void:
	if controller == null or controller._trim == null:
		return
	_trim_done_cb = done_cb
	if _trim_dialog == null:
		_trim_dialog = PanelContainer.new()
		_trim_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_trim_dialog.z_index = 96   # 高于营地/替换（95），低于掌机外壳（100）
		var sb = StyleBoxFlat.new()
		sb.bg_color = Palette.BG_OVERLAY
		_trim_dialog.add_theme_stylebox_override("panel", sb)
		var center = CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var dlg = PanelContainer.new()
		var sb2 = StyleBoxFlat.new()
		sb2.bg_color = Palette.PANEL_BG
		sb2.border_color = Palette.ACCENT_GOLD
		sb2.set_border_width_all(2)
		dlg.add_theme_stylebox_override("panel", sb2)
		_trim_vbox = VBoxContainer.new()
		_trim_vbox.add_theme_constant_override("separation", 4)
		dlg.add_child(_trim_vbox)
		center.add_child(dlg)
		_trim_dialog.add_child(center)
		get_parent().add_child(_trim_dialog)
	for c in _trim_vbox.get_children():
		_trim_vbox.remove_child(c)
		c.queue_free()
	var trim = controller._trim
	var title_lbl = _label("", TypeScale.OVERLAY)
	title_lbl.text = "✂ 精简带子 · 剩余 %d 次" % trim.trims_left()
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_trim_vbox.add_child(title_lbl)
	var hint = _label("", TypeScale.TINY)
	hint.text = "符号减 1 格，或卸除 1 个技能。不可撤销；次数由「精简剪」提供（两者共享）。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(320, 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_trim_vbox.add_child(hint)
	var cands: Array = trim.candidates()
	if cands.is_empty():
		var none_lbl = _label("", TypeScale.TINY)
		none_lbl.text = "本幕没有合法候选（次数已用尽，或没有可减的符号）"
		none_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none_lbl.custom_minimum_size = Vector2(320, 0)
		none_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_trim_vbox.add_child(none_lbl)
	for cand in cands:
		var btn = UI_BUTTON.instantiate()
		btn.text = _trim_cand_text(trim, cand)
		btn.custom_minimum_size = Vector2(320, 30)
		btn.add_theme_font_size_override("font_size", 9)
		btn.pressed.connect(_on_trim_cand_pressed.bind(cand))
		_trim_vbox.add_child(btn)
	_trim_pending = {}
	_trim_preview = _label("", TypeScale.TINY)
	_trim_preview.text = "选一个候选查看真实前后"
	_trim_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_trim_preview.custom_minimum_size = Vector2(320, 0)
	_trim_preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_trim_vbox.add_child(_trim_preview)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_trim_vbox.add_child(row)
	_trim_confirm = UI_BUTTON.instantiate()
	_trim_confirm.text = "确认（不可逆）"
	_trim_confirm.custom_minimum_size = Vector2(180, 30)
	_trim_confirm.disabled = true
	_trim_confirm.pressed.connect(_on_trim_confirm_pressed)
	row.add_child(_trim_confirm)
	var close = UI_BUTTON.instantiate()
	close.text = "取消"
	close.custom_minimum_size = Vector2(90, 30)
	close.pressed.connect(_on_trim_cancel_pressed)
	row.add_child(close)
	_trim_dialog.visible = true


func _on_trim_cancel_pressed() -> void:
	hide_trim_dialog()
	# M-02a：营地整理取消 → 不推进、不结算；回调由营地侧决定（通常仅重开营地选择）。
	if _trim_done_cb.is_valid():
		var cb := _trim_done_cb
		_trim_done_cb = Callable()
		cb.call(false)


func hide_trim_dialog() -> void:
	if _trim_dialog != null:
		_trim_dialog.visible = false
	_trim_pending = {}


# 候选行：带真实前后（逻辑格 / 实际带长），与 reel_system.build_strips 同口径。
func _trim_cand_text(trim, cand: Dictionary) -> String:
	var pv: Dictionary = trim.preview(cand)
	if String(cand.get("kind", "")) == "symbol":
		return "%s %d→%d 格 · 带 %d→%d（实际 %d→%d 格）" % [
			String(cand.get("name", "")), int(pv["before_target"]), int(pv["after_target"]),
			int(pv["before_cells"]), int(pv["after_cells"]), int(pv["before_len"]), int(pv["after_len"])]
	return "%s · 带 %d→%d（实际 %d→%d 格）" % [
		String(cand.get("name", "")), int(pv["before_cells"]), int(pv["after_cells"]),
		int(pv["before_len"]), int(pv["after_len"])]


func _on_trim_cand_pressed(cand: Dictionary) -> void:
	_trim_pending = cand
	var pv: Dictionary = controller._trim.preview(cand)
	var lines: Array[String] = []
	if String(cand.get("kind", "")) == "symbol":
		lines.append("%s：%d → %d 格" % [String(cand.get("name", "")),
			int(pv["before_target"]), int(pv["after_target"])])
	else:
		lines.append("卸除 %s（该技能符号与 MISS 贡献一并消失）" % String(cand.get("name", "")))
	lines.append("逻辑带：%d → %d 格" % [int(pv["before_cells"]), int(pv["after_cells"])])
	lines.append("实际带：%d → %d 格（含最小带长平铺）" % [int(pv["before_len"]), int(pv["after_len"])])
	lines.append("伤害格：%d → %d · MISS：%d → %d" % [
		int(pv["before_damage"]), int(pv["after_damage"]),
		int(pv["before_miss"]), int(pv["after_miss"])])
	_trim_preview.text = "\n".join(lines)
	if _trim_confirm != null:
		_trim_confirm.disabled = false
		_trim_confirm.text = "确认：%s（不可逆）" % String(cand.get("name", ""))


func _on_trim_confirm_pressed() -> void:
	if _trim_pending.is_empty() or controller == null or controller._trim == null:
		return
	var msg: String = controller._trim.apply(_trim_pending)
	_trim_pending = {}
	if msg == "":
		hide_trim_dialog()
		return
	hide_trim_dialog()
	if feedback_label != null:
		feedback_label.text = msg
	# 地图模式：信息栏同步一行；地图屏自己再刷新一次（按钮状态 / 顶栏）。
	if controller.board != null and controller.node_mode:
		controller.board.feedback = msg
	if branch_screen != null and branch_screen.visible:
		branch_screen.refresh()
	_refresh_trim_entry()
	# M-02a：营地整理确认 → 结算已完成，回调推进到营地后续（只结算一次）。
	if _trim_done_cb.is_valid():
		var cb := _trim_done_cb
		_trim_done_cb = Callable()
		cb.call(true)


# 间歇态精简入口（2026-11-17：精简已改为消耗品「精简剪」授予次数）
# 没有次数时**完全不出现**——不再有「每幕 1 次」配额，也就不存在「本幕已用」这种状态。
func _refresh_trim_entry() -> void:
	if interroom_trim_btn == null:
		return
	var left := 0
	if controller != null and controller._trim != null:
		left = controller._trim.trims_left()
	interroom_trim_btn.visible = left > 0 and _interroom_on
	interroom_trim_btn.disabled = left <= 0 or not _interroom_on
	interroom_trim_btn.text = "✂ 精简 ×%d" % left


# G4-04 武器藏库：两把公开武器二选一（或跳过）；满槽的替换弹层由 controller 接续。
var _armory_dialog: PanelContainer = null
var _armory_vbox: VBoxContainer = null
var _armory_pick_cb: Callable = Callable()
var _armory_skip_cb: Callable = Callable()


func request_armory(paths: Array, on_pick: Callable, on_skip: Callable) -> void:
	_armory_pick_cb = on_pick
	_armory_skip_cb = on_skip
	if _armory_dialog == null:
		_armory_dialog = PanelContainer.new()
		_armory_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_armory_dialog.z_index = 95
		var sb = StyleBoxFlat.new()
		sb.bg_color = Palette.BG_OVERLAY
		_armory_dialog.add_theme_stylebox_override("panel", sb)
		var center = CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var dlg = PanelContainer.new()
		var sb2 = StyleBoxFlat.new()
		sb2.bg_color = Palette.PANEL_BG
		sb2.border_color = Palette.ACCENT_GOLD
		sb2.set_border_width_all(2)
		dlg.add_theme_stylebox_override("panel", sb2)
		_armory_vbox = VBoxContainer.new()
		_armory_vbox.add_theme_constant_override("separation", 6)
		dlg.add_child(_armory_vbox)
		center.add_child(dlg)
		_armory_dialog.add_child(center)
		# 与营地面板同挂 duel 根节点：棋盘隐藏 HUD 时弹层仍需可见。
		get_parent().add_child(_armory_dialog)
	for c in _armory_vbox.get_children():
		_armory_vbox.remove_child(c)
		c.queue_free()
	var title_lbl = _label("武器藏库", TypeScale.OVERLAY)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_armory_vbox.add_child(title_lbl)
	var hint = _label("二选一：选中立即入槽；武器槽已满则先替换。", TypeScale.TINY)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_armory_vbox.add_child(hint)
	for p in paths:
		var btn = UI_BUTTON.instantiate()
		btn.text = _armory_weapon_line(String(p))
		btn.custom_minimum_size = Vector2(320, 36)
		btn.tooltip_text = controller._weapon_info(String(p))
		btn.pressed.connect(_on_armory_pick_pressed.bind(String(p)))
		_armory_vbox.add_child(btn)
	var skip = UI_BUTTON.instantiate()
	skip.text = "跳过（节点已消耗）"
	skip.custom_minimum_size = Vector2(180, 30)
	skip.pressed.connect(_on_armory_skip_pressed)
	_armory_vbox.add_child(skip)
	_armory_dialog.visible = true


func _armory_weapon_line(p: String) -> String:
	var wd: WeaponData = load(p)
	if wd == null:
		return controller._shop_name(p, "weapon")
	var atk: int = int(controller.weapon_power(p))
	var owned := "（已持有 · 折算金币）" if controller.selected_loadout.has(p) else ""
	return "%s · 攻%d · %s%s" % [wd.weapon_name, atk, ElementCounter.label(wd.element), owned]


func _on_armory_pick_pressed(p: String) -> void:
	_armory_dialog.visible = false
	var cb = _armory_pick_cb
	_armory_pick_cb = Callable()
	_armory_skip_cb = Callable()
	if cb.is_valid():
		cb.call(p)


func _on_armory_skip_pressed() -> void:
	_armory_dialog.visible = false
	var cb = _armory_skip_cb
	_armory_pick_cb = Callable()
	_armory_skip_cb = Callable()
	if cb.is_valid():
		cb.call()


func _show_overlay(title: String, btn_text: String) -> void:
	overlay_label.text = title
	overlay_button.text = btn_text
	overlay.visible = true


func _hide_overlay() -> void:
	overlay.visible = false


# 战斗日志统一走编辑器控制台（Debug.log），战斗界面不再显示滚动日志框
func _log(msg: String) -> void:
	Debug.log(msg)


# 2026-08-14 玩家属性行已整体移除——变强可见性由战斗日志（伤害分解）与飘字承担。
func _refresh_gear_icons() -> void:
	panel_view.refresh_gear_icons()
	_refresh_charm_row()
	_refresh_relic_row()   # L2-F：遗物行随装备刷新


# ---------------------------------------------------------------------------
# 头顶护符行（2026-11-16）
# 护符是唯一不进转轮的装备，原先放在左栏最边缘：生效时那里一亮，视线要从角色
# 横跨到屏幕左端。挪到血条正上方后，「护符闪 → 它的盾/治疗数字」都发生在角色身上。
# 图标 12px（16px 会让头部占 38px，对比 48px 角色头重脚轻）。
# 平时低亮度剪影，生效时亮起——常驻全亮会一直抢戏。
# ---------------------------------------------------------------------------
const CHARM_ICON := 12.0          # 图标本体
const CHARM_SLOT := 14.0          # 槽位（图标 12 + 左右各 1px 边框）
const CHARM_GAP := 2.0            # 槽位间距
# 槽位底与 HUD 背景几乎同色，分隔完全靠边框；边框必须比背景亮，
# 否则图标变暗时会跟着一起消失（这正是加框要解决的问题）。
const CHARM_FRAME := Color("#6e5f57")
const CHARM_DIM := Color(0.58, 0.58, 0.64, 1.0)   # 太暗会看不清装了哪些护符，0.58 仍明显低于点亮态
const CHARM_HI := Color(1.70, 1.45, 0.85, 1.0)

var charm_row: Control
var charm_icons: Array = []   # [{path: String, node: TextureRect}]
var _charm_slot_sb: StyleBoxFlat


func _charm_slot_style() -> StyleBoxFlat:
	if _charm_slot_sb == null:
		_charm_slot_sb = StyleBoxFlat.new()
		_charm_slot_sb.bg_color = Palette.CARD_BG
		_charm_slot_sb.border_color = CHARM_FRAME
		_charm_slot_sb.set_border_width_all(1)
	return _charm_slot_sb


func _build_charm_row() -> void:
	if player_sprite == null:
		return
	charm_row = Control.new()
	charm_row.name = "CharmRow"
	charm_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	charm_row.anchor_left = 0.5
	charm_row.anchor_right = 0.5
	charm_row.visible = false
	player_sprite.add_child(charm_row)
	_refresh_charm_row()


func _refresh_charm_row() -> void:
	if charm_row == null or not is_instance_valid(charm_row):
		return
	var paths: Array = controller.state.selected_charms
	# 签名一致就不重建——_refresh_meta 调用很频繁，重建会把正在播的脉冲杀掉
	var sig := "|".join(paths)
	if String(charm_row.get_meta("sig", "")) == sig:
		return
	charm_row.set_meta("sig", sig)
	for c in charm_row.get_children():
		charm_row.remove_child(c)
		c.queue_free()
	charm_icons.clear()

	var n: int = paths.size()
	charm_row.visible = n > 0
	if n == 0:
		return
	var total: float = n * CHARM_SLOT + float(n - 1) * CHARM_GAP
	charm_row.offset_left = -total * 0.5
	charm_row.offset_right = total * 0.5
	# 血条块占 -12..-4，护符行贴在其上方 2px
	charm_row.offset_bottom = -(VITAL_HP_H + 4.0 + 2.0)
	charm_row.offset_top = charm_row.offset_bottom - CHARM_SLOT
	for i in n:
		var cpath := String(paths[i])
		var d = load(cpath)
		var tex: Texture2D = d.get("icon_tex") if d != null else null
		var slot := Panel.new()
		slot.name = "CharmSlot_%d" % i
		slot.custom_minimum_size = Vector2(CHARM_SLOT, CHARM_SLOT)
		slot.size = Vector2(CHARM_SLOT, CHARM_SLOT)
		slot.position = Vector2(float(i) * (CHARM_SLOT + CHARM_GAP), 0.0)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_theme_stylebox_override("panel", _charm_slot_style())
		charm_row.add_child(slot)

		@warning_ignore("shadowed_variable_base_class")
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.custom_minimum_size = Vector2(CHARM_ICON, CHARM_ICON)
		tr.size = Vector2(CHARM_ICON, CHARM_ICON)
		tr.position = Vector2(1, 1)   # 边框内缩 1px
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.modulate = CHARM_DIM
		slot.add_child(tr)
		charm_icons.append({"path": cpath, "node": tr})


# 护符生效脉冲：点亮头顶对应的护符图标（paths 由 ctrl.charm_breakdown 归因得出）
# L2-F：遗物与护符共用被动归因，paths 里可能含遗物 path —— 两行都脉冲。
func pulse_charm_card(paths: Array = []) -> void:
	_pulse_icon_row(charm_icons, paths)
	_pulse_icon_row(relic_icons, paths)


func _pulse_icon_row(icons: Array, paths: Array) -> void:
	for e in icons:
		if not paths.is_empty() and not paths.has(String(e["path"])):
			continue
		@warning_ignore("shadowed_variable_base_class")
		var tr: TextureRect = e["node"]
		if tr == null or not is_instance_valid(tr):
			continue
		# Godot 4：get_meta(key, null) 的 null default 等同未提供，key 不存在时会报 C++ 错误。
		# 图标首次创建时无 "tw" meta，必须先用 has_meta 守卫。
		if tr.has_meta("tw"):
			var old = tr.get_meta("tw")
			if old != null and is_instance_valid(old):
				old.kill()
		tr.modulate = CHARM_HI
		var tw := tr.create_tween()
		tw.tween_property(tr, "modulate", CHARM_DIM, 0.45)
		tr.set_meta("tw", tw)


# ---------------------------------------------------------------------------
# L2-F 头顶遗物行（2026-11-18）
# BOSS 信物入独立遗物栏 run_relics（本局拥有即生效、不占槽），与护符行同款样式，
# 贴在其下方一行。也可能触发脉冲（charm_breakdown 已含遗物 path）。
# ---------------------------------------------------------------------------
var relic_row: Control
var relic_icons: Array = []   # [{path: String, node: TextureRect}]


func _build_relic_row() -> void:
	if player_sprite == null:
		return
	relic_row = Control.new()
	relic_row.name = "RelicRow"
	relic_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	relic_row.anchor_left = 0.5
	relic_row.anchor_right = 0.5
	relic_row.visible = false
	player_sprite.add_child(relic_row)
	_refresh_relic_row()


func _refresh_relic_row() -> void:
	if relic_row == null or not is_instance_valid(relic_row):
		return
	var paths: Array = controller.run_relics if controller != null and "run_relics" in controller else []
	var sig := "|".join(paths)
	if String(relic_row.get_meta("sig", "")) == sig:
		return
	relic_row.set_meta("sig", sig)
	for c in relic_row.get_children():
		relic_row.remove_child(c)
		c.queue_free()
	relic_icons.clear()

	var n: int = paths.size()
	relic_row.visible = n > 0
	if n == 0:
		return
	var total: float = n * CHARM_SLOT + float(n - 1) * CHARM_GAP
	relic_row.offset_left = -total * 0.5
	relic_row.offset_right = total * 0.5
	# 护符行贴在血条上方（offset_bottom = -(VITAL_HP_H+4+2)），遗物行再往上 1 槽高 + 2px
	relic_row.offset_bottom = -(VITAL_HP_H + 4.0 + 2.0) - CHARM_SLOT - 2.0
	relic_row.offset_top = relic_row.offset_bottom - CHARM_SLOT
	for i in n:
		var cpath := String(paths[i])
		var d = load(cpath)
		var tex: Texture2D = d.get("icon_tex") if d != null else null
		var slot := Panel.new()
		slot.name = "RelicSlot_%d" % i
		slot.custom_minimum_size = Vector2(CHARM_SLOT, CHARM_SLOT)
		slot.size = Vector2(CHARM_SLOT, CHARM_SLOT)
		slot.position = Vector2(float(i) * (CHARM_SLOT + CHARM_GAP), 0.0)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_theme_stylebox_override("panel", _charm_slot_style())
		relic_row.add_child(slot)

		@warning_ignore("shadowed_variable_base_class")
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.custom_minimum_size = Vector2(CHARM_ICON, CHARM_ICON)
		tr.size = Vector2(CHARM_ICON, CHARM_ICON)
		tr.position = Vector2(1, 1)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.modulate = CHARM_DIM
		# 遗物边框用交互金区分护符（护符是暗铜色框）——拥有即生效的纪念品
		var rsb := StyleBoxFlat.new()
		rsb.bg_color = Palette.CARD_BG
		rsb.border_color = Palette.ACCENT_GOLD
		rsb.set_border_width_all(1)
		slot.add_theme_stylebox_override("panel", rsb)
		slot.add_child(tr)
		relic_icons.append({"path": cpath, "node": tr})


# 4 格子刷新：按 consumable_slots 顺序填，缺位留空占位文案
# - 有消耗品：显示 emoji + 名字 + charges 角标；按 game_state/in_loadout/律法锁槽 决定是否禁用
# - 空格子：显示 "—"，禁用（仅占位）
func _refresh_consumable_panel() -> void:
	panel_view.refresh_consumable_panel()


# 4 格子点击：发 consumable_used(uid) 信号让 controller 走统一扣减+结算路径
func _on_consumable_cell_pressed(cell_index: int) -> void:
	panel_view.on_consumable_cell_pressed(cell_index)


## 转轮滚动/吸附期间，ReelSpinView 会盖在格子上；此时静止层必须让位，
## 否则会出现"剑 + 火焰"两张图叠在同一格（2026-11-12 用户反馈）。
func _sync_cell_occlusion() -> void:
	for reel in cell_spin_views.size():
		var busy := false
		if cell_spin_views[reel].size() > 0:
			var sv = cell_spin_views[reel][0]
			busy = is_instance_valid(sv) and sv.visible
		for row in cell_icon_layers[reel].size():
			var layer: TextureRect = cell_icon_layers[reel][row]
			var want: Texture2D = _cell_want_icon[reel][row]
			layer.visible = (not busy) and want != null
			cells[reel][row].text = "" if busy else String(_cell_want_text[reel][row])


# 2026-11-17：底栏改为「整张美术图 + 图标绝对定位」。
# 框线全部烘焙进 assets/ui/bar_full.png，代码只负责把格子摆到图里对应的空位上。
# 下列坐标是从底栏图上逐格量出的内腔中心。
const BAR_TOP := 197.0   # 底图 bar_full.png 的屏幕 y（480×74，覆盖 y197..271）
const SLOT_CELL := 30.0

# 2026-11-17 中轴校正：以画面真正中心 x=240 为基准（原用 237，整体偏左 3px）。
# 左侧（武器/技能）保持不动；中央转轮右移 3px、右侧消耗品右移 2px、金币右移 5px。
# 注意：bar_full.png 里的槽位框线必须同步移动，否则图标与框线错位。
const WEAPON_SLOT_X := [20.0, 52.0]
const SKILL_SLOT_X := [84.0, 116.0, 148.0]
const REEL_SLOT_X := [194.0, 240.0, 286.0]
const BELT_SLOT_X := [332.0, 364.0, 396.0, 428.0]
const GOLD_SLOT_X := 460.0
const SLOT_CENTER_Y := 221.0
const REEL_CENTER_Y := 219.0


# 按给定的中心点横向摆放 container 的子节点
func _place_row(container: Node, xs: Array, cell: float, cy: float = SLOT_CENTER_Y) -> void:
	if container == null:
		return
	var i := 0
	for ch in container.get_children():
		if not (ch is Control) or not ch.visible:
			continue
		if i >= xs.size():
			break
		var c := ch as Control
		var pos := Vector2(float(xs[i]) - cell * 0.5, cy - cell * 0.5)
		if c.position != pos:
			c.position = pos
		if c.custom_minimum_size != Vector2(cell, cell):
			c.custom_minimum_size = Vector2(cell, cell)
		if c.size != Vector2(cell, cell):
			c.size = Vector2(cell, cell)
		# 图标上限 24px：48px 物品图正好减半、像素干净；30px 格子两侧各留 3px 露框。
		# 不设上限时 48px 图会整块盖住槽位框，看起来就是「图标超出框」。
		if c is Button:
			c.add_theme_constant_override("icon_max_width", 24)
		i += 1


# SPIN 按下反馈：红色横幅来自背景图，按钮本身透明，靠 1px 下沉 + 半透明黑覆盖给出触感。
func _wire_spin_feedback() -> void:
	var btn := get_node_or_null("ReelDock/SpinBar/SpinButton")
	if btn == null:
		return
	var base_y: float = btn.position.y
	btn.button_down.connect(func() -> void: btn.position.y = base_y + 1.0)
	btn.button_up.connect(func() -> void: btn.position.y = base_y)
	btn.mouse_exited.connect(func() -> void: btn.position.y = base_y)


func _layout_bottom_zones() -> void:
	# 容器本身不再参与排版，位置归零后子节点坐标即屏幕坐标
	for path in ["GearBox", "GearBox/GearCards", "GearBox/WeaponsRow",
			"GearBox/GearCards/SkillsRow", "GearBox/GearCards/CharmsRow", "ConsumablePanel",
			"ReelDock", "ReelDock/TopRow"]:
		var n := get_node_or_null(path)
		if n is Control:
			(n as Control).position = Vector2.ZERO
	# SPIN 槽：压在底栏红色横幅的空位上
	var spin_bar := get_node_or_null("ReelDock/SpinBar")
	if spin_bar != null:
		spin_bar.position = Vector2(190, 246)
		spin_bar.size = Vector2(100, 18)
	# 金币：外框 + 图标 + 数字作为整体右移 5px（中轴校正），与底图金币框中心 460 对齐。
	# 注意 GoldFrame(Panel) 场景原始 offset 是 440..470（中心455），必须在这里重定位，
	# 否则 Panel 框(455)与底图框(460)错位 5px，出现双线/暗边。
	var gf := get_node_or_null("GoldFrame")
	if gf != null:
		gf.position = Vector2(445, 206)
		gf.size = Vector2(30, 30)
	var gi := get_node_or_null("GoldIcon")
	if gi != null:
		gi.position = Vector2(449, 211)
		gi.size = Vector2(12, 12)
	var gl := get_node_or_null("GoldLabel")
	if gl != null:
		gl.position = Vector2(461, 211)
		gl.size = Vector2(12, 14)

func _layout_slot_rows() -> void:
	var grid := get_node_or_null("ReelDock/TopRow/ReelCenter/GridContainer")
	if grid is Control:
		(grid as Control).position = Vector2.ZERO
	_place_row(get_node_or_null("GearBox/WeaponsRow"), WEAPON_SLOT_X, SLOT_CELL)
	_place_row(get_node_or_null("GearBox/GearCards/SkillsRow"), SKILL_SLOT_X, SLOT_CELL)
	_place_row(get_node_or_null("ConsumablePanel"), BELT_SLOT_X, SLOT_CELL)
	_place_row(get_node_or_null("ReelDock/TopRow/ReelCenter/GridContainer"), REEL_SLOT_X, 42.0, 218.0)


func _process(_delta: float) -> void:
	if not cells.is_empty():
		_sync_cell_occlusion()
	_layout_slot_rows()
	_place_foot_shadows()


# 2026-11-17：远景层微动已去掉（用户要求）。BattleBgFar 节点与遮罩图保留但静止，画面不变。

# 脚下阴影：按立绘在世界中的脚底位置动态对齐，给角色"落地感"与前后纵深。
# 阴影层在 BattleBg 之后、Margin 之前渲染 → 位于背景之上、立绘之下。
# 幂等，可在 _process 每帧调用；立绘 scale 动画不影响 global_rect（pivot 居中），
# 但敌人 art_scale 切换会改尺寸，故每帧对齐最稳。
func _place_foot_shadows() -> void:
	_place_one_shadow(player_shadow, player_sprite, 32.0, 11.0)
	_place_one_shadow(enemy_shadow, enemy_sprite, 56.0, 16.0)


func _place_one_shadow(shadow: Control, sprite: Control, base_w: float, h: float) -> void:
	if shadow == null or sprite == null or not sprite.visible:
		if shadow != null:
			shadow.visible = false
		return
	var r: Rect2 = sprite.get_global_rect()
	# 立绘可能被动画 scale（受击放大/死亡缩小），按实际可见宽度缩放阴影，但设下限避免消失
	var scale_factor: float = clampf(absf(sprite.scale.x), 0.3, 2.0)
	var w: float = base_w * scale_factor
	var cx: float = r.position.x + r.size.x * 0.5
	var foot_y: float = r.position.y + r.size.y
	shadow.visible = sprite.modulate.a > 0.15
	shadow.position = Vector2(cx - w * 0.5, foot_y - h * 0.5)
	shadow.size = Vector2(w, h)


## 格子约 38px：符号图标 16px 太小，优先换用 /16/ → /32/ 的同名版本（1:1 不缩放）
func _cell_icon(base: Texture2D) -> Texture2D:
	if base == null:
		return null
	var p := base.resource_path
	if p == "" or not p.contains("/16/"):
		return base
	var big := p.replace("/symbols/16/", "/symbols/")   # 32px 版直接放在 symbols/ 下
	return load(big) as Texture2D if ResourceLoader.exists(big) else base


## 斩击格显示实际来源武器的完整 32px 图标。多把武器共享符号族时逐格读取 grid_src，
## 不再合并成最高攻武器，也不使用副图标角标。技能、状态和精华仍用自己的符号图标。
func _cell_symbol_tex(reel: int, row: int, s: SymbolData) -> Texture2D:
	if s == null:
		return null
	if controller == null:
		return _cell_icon(s.icon_tex)
	# 快速返回：状态 / buff / 技能 / 精华 / 金币一律用自身图标
	if String(s.kind) != "damage" and not s.resource_path.ends_with("_slash.tres"):
		return _cell_icon(s.icon_tex)
	# 来源：优先格子级 grid_src（多源按权重分格后逐格记），否则用旁路表兜底
	var wid := ""
	var gs = controller.grid_src
	if gs.size() > reel and gs[reel].size() > row:
		wid = String(gs[reel][row])
	if wid == "":
		var ge = controller.grid_elem
		var elem: String = "none"
		if ge.size() > reel and ge[reel].size() > row:
			elem = String(ge[reel][row])
		wid = String(controller._sym_src_map.get(s.resource_path + "|" + elem, ""))
	# 2026-11-16 规则：斩击永远跟随；其余伤害符号只在该武器只有它一个 damage 时才跟随
	if wid != "" and controller._symbol_follows_weapon(s, wid):
		var wtex := WeaponIcons.cell_icon_for_id(wid)
		if wtex != null:
			return wtex
	return _cell_icon(s.icon_tex)# 转轮图标描边：在图标四周外扩一圈暗色，让它"压"在奶油色底面上而不是浮着。
# 2026-11-17：底栏改为整图烘焙后，奶油格与图标缺少融合感，靠这层描边补上。
const ICON_OUTLINE_SHADER := """
shader_type canvas_item;
uniform vec4 outline_color : source_color = vec4(0.05, 0.03, 0.05, 0.85);
void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec4 c = texture(TEXTURE, UV);
	float a = 0.0;
	a = max(a, texture(TEXTURE, UV + vec2(px.x, 0.0)).a);
	a = max(a, texture(TEXTURE, UV - vec2(px.x, 0.0)).a);
	a = max(a, texture(TEXTURE, UV + vec2(0.0, px.y)).a);
	a = max(a, texture(TEXTURE, UV - vec2(0.0, px.y)).a);
	a = max(a, texture(TEXTURE, UV + px * 0.7).a);
	vec4 edge = vec4(outline_color.rgb, outline_color.a * a);
	COLOR = mix(edge, c, c.a);
}
"""
var _icon_shader: Shader = null
var _icon_material: ShaderMaterial = null


func _icon_outline_material() -> ShaderMaterial:
	if _icon_material == null:
		_icon_shader = Shader.new()
		_icon_shader.code = ICON_OUTLINE_SHADER
		_icon_material = ShaderMaterial.new()
		_icon_material.shader = _icon_shader
	return _icon_material
