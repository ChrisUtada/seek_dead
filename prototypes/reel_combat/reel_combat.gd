extends Control
# ============================================================================
# M2 原型 — 老虎机回合制战斗（完整单敌对决闭环）
# 相对 M1 的增量：
#   · 真实敌人意图：每回合预告(attack/heavy/jam)，玩家 SPIN 后敌人执行该意图
#   · 胜负状态机 + 房间推进（ROOMS 数组，逐房升级，通关/失败可重开）
#   · DoT 细化（灼烧/毒跨回合持续、回合末衰减、HUD 显示层数）
#   · 干扰反制接入（M3 的轻量切片）：敌人 jam 注入废铁占据一列，
#     玩家用「净化」次数抵消（每房回满，M3 将由消耗品承接）
# 仍：1 行 3 格、符号池来自 WeaponData.reel_symbols、单符号必结算+匹配倍率、无锁定。
# 按 F6 运行试玩。
#
# M3 增量（整备选物 UI）：
#   · 开局先进入整备覆盖层，从 WEAPON_POOL 自由勾选 1–5 把武器
#   · 带哪把武器 = 转轮里有什么符号（卡片实时预览符号池）
#   · 战斗中可「重新整备」返回选配；确认后按所选武器重建符号池
#   · 消耗品 / 护符分类在 UI 框架中预留（M3 后续接入实际数据）
# M3 干扰系统增量（本版）：
#   · 敌人干扰分支扩展为 注废(jam) / 锁轮(lock) / 乱权(chaos) 三类（攻击 attack / 重击 heavy 不变）
#   · 净化接成消耗品：整备携带「净化药剂 ×N」决定净化上限，每房回满到携带量
#   · 意图 HUD 含干扰图标与「可净化」提示；净化可清除任意一类干扰意图
# M4 增量（房间 + Roguelike 构筑）：
#   · 跑通一局（Run）：HP 跨房保留；每清一房弹出「房奖励」三选一界面（Roguelike 构筑）
#   · 本局加成层：符号权重加成(run_symbol_bonus) / 符号伤害加成(run_power_bonus) / 下一房护盾(run_shield_next)
#   · 奖励池 REWARD_POOL：治疗 / 最大HP / 净化上限 / 符号灌注 / 守望结界 / 锋锐打磨
#   · Boss 房（最后一房）击败 → 通关 → 领取残余物奖励 → 开新一局
# ============================================================================

const ReelSymbol = preload("res://scripts/battle/reel_symbol.gd")

# 可选物品池（整备界面从这里自由勾选，真实 .tres 数据）。
const WEAPON_POOL := [
	"res://resources/weapon_templates/iron_sword.tres",
	"res://resources/weapon_templates/pistol.tres",
	"res://resources/weapon_templates/fire_sword.tres",
	"res://resources/weapon_templates/flame_staff.tres",
	"res://resources/weapon_templates/ice_gun.tres",
	"res://resources/weapon_templates/battle_axe.tres",
	"res://resources/weapon_templates/dagger.tres",
	"res://resources/weapon_templates/poison_dagger.tres",
]
const CONSUMABLE_POOL := [
	"res://resources/consumables/purify_potion.tres",
	"res://resources/consumables/heal_potion.tres",
	"res://resources/consumables/assault_potion.tres",
	"res://resources/consumables/reroll_scroll.tres",
]
const CHARM_POOL := [
	"res://resources/charms/sharp_charm.tres",
	"res://resources/charms/ward_charm.tres",
	"res://resources/charms/resist_charm.tres",
	"res://resources/charms/purify_charm.tres",
]

# 携带约束（与策划案 v0.4 定稿一致）：武器硬下限≥1；分类容量上限；总槽≈6。
const LOADOUT_MIN := 1
const LOADOUT_MAX := 5
const CONSUMABLE_MIN := 0
const CONSUMABLE_MAX := 3
const CHARM_MIN := 0
const CHARM_MAX := 2
const TOTAL_MAX := 6

const REELS = 3
const ROWS = 1

# M4 房奖励池（每清一房随机 3 选 1；Boss 房走同池但标为「残余物」）
const REWARD_POOL := [
	{"id": "heal",   "icon": "✚", "label": "治疗药剂", "desc": "恢复 35% 最大 HP"},
	{"id": "maxhp",  "icon": "♥", "label": "强韧之心", "desc": "最大 HP +20 并回满"},
	{"id": "purify", "icon": "⛨", "label": "净化符文", "desc": "净化上限 +1（每房回满）"},
	{"id": "symbol", "icon": "✶", "label": "符号灌注", "desc": "随机优势符号权重 +3"},
	{"id": "shield", "icon": "🛡", "label": "守望结界", "desc": "下一房开局 +15 护盾"},
	{"id": "power",  "icon": "⚔", "label": "锋锐打磨", "desc": "本局符号伤害 +1"},
]
# 净化上限由 M6 物品（净化药剂 + 丰沛护符）与房奖励共同决定，见 purify_max_base

# 房间序列（肉鸽逐房推进）。
# jam=注废意图概率, lock=锁轮意图概率, chaos=乱权意图概率, heavy=重击意图概率, 其余=普攻。
const ROOMS := [
	{"name": "腐化史莱姆", "hp": 90,  "atk": 11, "jam": 0.15, "lock": 0.10, "chaos": 0.10, "heavy": 0.15},
	{"name": "锈蚀傀儡",   "hp": 130, "atk": 14, "jam": 0.20, "lock": 0.15, "chaos": 0.15, "heavy": 0.20},
	{"name": "呓语教徒",   "hp": 165, "atk": 16, "jam": 0.25, "lock": 0.20, "chaos": 0.20, "heavy": 0.20},
	{"name": "深渊监视者", "hp": 220, "atk": 20, "jam": 0.30, "lock": 0.25, "chaos": 0.25, "heavy": 0.30},
]

# grid[reel][row] = 符号 id (ReelSymbol.Id)
var grid = []
var cells = []   # 展示用 Button 引用 [reel][row]

# 合并后的加权符号池：元素为 [symbol_id, weight]
var pool: Array = []
var loadout_names: Array = []

# 整备（M3–M6）：玩家自由勾选武器 / 消耗品 / 护符三分类
var in_loadout := false
var selected_loadout: Array = []          # 玩家勾选的武器路径
var selected_consumables: Array = []      # 玩家勾选的消耗品路径
var selected_charms: Array = []           # 玩家勾选的护符路径
var loadout_screen
var loadout_grid
var loadout_cards := []                   # 卡片元数据列表 {path, btn, selected, category}
var loadout_count_label
var loadout_confirm_btn
var loadout_anvil_label                # M5：整备屏显示铁砧点数

# 消耗品运行时（战斗中主动使用）
var consumable_charges: Dictionary = {}   # item_id -> 剩余次数（每房回满）
var consumable_panel                      # 战斗 UI 底部消耗品按钮行
var consumable_buttons: Array = []        # {id, data, btn}
var assault_next_spin: int = 1            # 强袭药剂：下次转轮伤害倍率（1=正常）

# 玩家状态
var player_hp = 100
var player_hp_max = 100
var player_shield = 0

# 敌人 / 房间状态
var room_index = 0
var enemy_name = "敌人"
var enemy_hp = 120
var enemy_hp_max = 120
var enemy_atk = 14
var enemy_jam = 0.2
var enemy_lock = 0.1
var enemy_chaos = 0.1
var enemy_heavy = 0.2
var enemy_status: Dictionary = {}      # status_type(str) -> 叠加层数(int)
var enemy_intent: Dictionary = {}      # 当前敌人意图（SPIN 后执行），空字典表示已执行/未定
var pending_jam_reel = -1              # 敌人注废 → 下一轮强制废铁列索引（-1 无）
var pending_lock_reel = -1             # 敌人锁轮 → 下一轮该列固定为当前符号（-1 无）
var pending_chaos = false              # 敌人乱权 → 下一轮权重削弱优势符号
var _pool_backup: Array = []           # chaos 临时池备份（spin 后还原）
# 净化上限 = 携带「净化药剂」数值 + 丰沛护符加成 + 房奖励增量；每房回满到该值
var purify_max_base = 0
var purify_charges = 0

# M6 护符被动（整局生效，_apply_charms 在 _confirm_loadout 结算）
var charm_power_bonus: int = 0         # 锋锐护符：本局所有伤害符号 +N
var charm_room_shield: int = 0         # 守望护符：每房开局护盾 +N
var charm_interf_resist: int = 0       # 抗扰护符：本局敌人干扰概率降低（等效抗扰等级）
var charm_purify_bonus: int = 0        # 丰沛护符：净化上限 +N

# 流程状态
var game_state = "playing"             # playing | won | lost | cleared
var turn_count = 1

# M4 本局（Run）加成层
var run_symbol_bonus: Dictionary = {}  # symbol_id -> 额外权重（奖励：符号灌注）
var run_power_bonus: int = 0           # 本局符号基础伤害加成（奖励：锋锐打磨）
var run_shield_next: int = 0           # 进入下一房时获得的护盾（奖励：守望结界）
var reward_screen                       # 奖励三选一覆盖层
var reward_title_label
var reward_grid
var reward_skip_btn
var reward_choices: Array = []         # 当前展示的 3 个奖励
var reward_is_boss: bool = false       # 当前奖励是否来自 Boss 房（选完开新局）

# M5 元进度（铁砧锻造 + 存档持久化，跨局保留）
# weapon_upgrades: weapon_path -> int（该武器主符号额外权重，转轮升级）
# interference_resist: int（抗干扰等级，降低敌人干扰概率）
var meta: Dictionary = {"anvil_points": 0, "weapon_upgrades": {}, "interference_resist": 0}
const SAVE_PATH := "user://reel_combat_save.json"
var anvil_screen
var anvil_title_label
var anvil_points_label
var anvil_grid
var anvil_back_btn

# 仅 1 行 3 格。特殊符号需 3 同才触发；普通符号单颗即结算，出现 n 次 ×n。
var PAYLINES = [
	[[0,0],[1,0],[2,0]],
]

# UI 引用
var grid_container
var log_label
var log_scroll
var player_hp_label
var player_shield_label
var enemy_name_label
var enemy_hp_label
var enemy_intent_label
var enemy_status_label
var loadout_label
var room_label
var turn_label
var run_label
var purify_label
var overlay
var overlay_label
var overlay_button

var logs: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_meta()                     # M5：载入铁砧元进度
	_build_ui()
	_build_loadout_screen()
	_build_reward_screen()
	_build_anvil_screen()
	_show_loadout_screen()


# ---------------------------------------------------------------------------
# 符号池：合并已装备武器的 reel_symbols
# ---------------------------------------------------------------------------
func _build_pool(loadout: Array) -> void:
	pool = []
	loadout_names = []
	var merged := {}   # symbol_id -> 总权重（跨武器累加）
	for path in loadout:
		var wd: Resource = load(path)
		if wd == null:
			_log("⚠ 找不到武器: " + path)
			continue
		loadout_names.append(wd.weapon_name)
		if typeof(wd.get("reel_symbols")) != TYPE_DICTIONARY:
			continue
		for key in wd.reel_symbols.keys():
			var sid := int(key)
			merged[sid] = merged.get(sid, 0.0) + float(wd.reel_symbols[key])
		# M5 铁砧：武器升级 → 主符号（权重最高者）额外加成
		var bonus = meta["weapon_upgrades"].get(path, 0)
		if bonus > 0 and not wd.reel_symbols.is_empty():
			var dom = -1
			var domw = -1.0
			for key in wd.reel_symbols.keys():
				var w = float(wd.reel_symbols[key])
				if w > domw:
					domw = w
					dom = int(key)
			if dom >= 0:
				merged[dom] = merged.get(dom, 0.0) + float(bonus)
	for sid in merged.keys():
		pool.append([sid, merged[sid]])
	# M4 本局符号权重加成（符号灌注奖励叠加）
	for sid in run_symbol_bonus.keys():
		var found = false
		for p in pool:
			if p[0] == sid:
				p[1] += float(run_symbol_bonus[sid])
				found = true
				break
		if not found:
			pool.append([sid, float(run_symbol_bonus[sid])])


func _weighted_random_sym() -> int:
	if pool.is_empty():
		return ReelSymbol.Id.TRASH
	var total := 0.0
	for p in pool:
		total += p[1]
	var r := randf() * total
	for p in pool:
		r -= p[1]
		if r < 0:
			return p[0]
	return pool[0][0]


# 乱权：临时扭曲权重池（削弱最高权重符号、增强废铁），spin 后由 _restore_pool 还原
func _apply_chaos_pool() -> void:
	_pool_backup = pool.duplicate(true)
	var max_w = 0.0
	for p in pool:
		max_w = max(max_w, p[1])
	var chaotic := []
	for p in pool:
		var w = p[1]
		if p[0] == ReelSymbol.Id.TRASH:
			w *= 2.0
		elif w >= max_w * 0.99:
			w *= 0.35
		chaotic.append([p[0], w])
	pool = chaotic


func _restore_pool() -> void:
	if not _pool_backup.is_empty():
		pool = _pool_backup
		_pool_backup = []


# ---------------------------------------------------------------------------
# UI 构建（全代码）
# ---------------------------------------------------------------------------
func _label(text: String, size: int = 16) -> Label:
	var l = Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	return l


func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.09, 0.09, 0.13, 1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	vbox.add_child(_label("M4 原型 · 老虎机回合制战斗（Roguelike 房奖励）", 16))
	loadout_label = _label("已装备: —", 11)
	vbox.add_child(loadout_label)

	# 房间 / 回合
	var rt = HBoxContainer.new()
	room_label = _label("房间: 1/1", 11)
	turn_label = _label("回合: 1", 11)
	rt.add_child(room_label)
	var rt_sp = Control.new()
	rt_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_child(rt_sp)
	rt.add_child(turn_label)
	vbox.add_child(rt)

	# M4 本局加成概览
	run_label = _label("本局加成: —", 10)
	vbox.add_child(run_label)

	# 顶部：玩家面板 + 敌人面板
	var top = HBoxContainer.new()
	vbox.add_child(top)
	var ppanel = VBoxContainer.new()
	ppanel.add_theme_constant_override("separation", 2)
	top.add_child(ppanel)
	player_hp_label = _label("玩家 HP: 100/100", 13)
	player_shield_label = _label("护盾: 0", 11)
	ppanel.add_child(player_hp_label)
	ppanel.add_child(player_shield_label)

	var espacer = Control.new()
	espacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(espacer)

	var epanel = VBoxContainer.new()
	epanel.add_theme_constant_override("separation", 2)
	top.add_child(epanel)
	enemy_name_label = _label("敌人", 13)
	enemy_hp_label = _label("HP: 0/0", 11)
	enemy_intent_label = _label("意图: —", 11)
	enemy_status_label = _label("状态: 无", 10)
	epanel.add_child(enemy_name_label)
	epanel.add_child(enemy_hp_label)
	epanel.add_child(enemy_intent_label)
	epanel.add_child(enemy_status_label)

	# 中部：转轮
	var mid = HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(mid)
	var center = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(center)
	grid_container = GridContainer.new()
	grid_container.columns = REELS
	grid_container.add_theme_constant_override("h_separation", 8)
	grid_container.add_theme_constant_override("v_separation", 8)
	center.add_child(grid_container)

	for reel in REELS:
		cells.append([])
		grid.append([])
		for row in ROWS:
			var b = Button.new()
			b.custom_minimum_size = Vector2(64, 64)
			b.add_theme_font_size_override("font_size", 18)
			b.disabled = true   # 原型无锁定，格子仅作展示
			grid_container.add_child(b)
			cells[reel].append(b)
			grid[reel].append(ReelSymbol.Id.TRASH)

	# 日志（固定高度的可滚动容器，避免长日志把底部按钮挤出视口）
	log_scroll = ScrollContainer.new()
	log_scroll.custom_minimum_size = Vector2(0, 64)
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(log_scroll)
	log_label = Label.new()
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.add_theme_font_size_override("font_size", 11)
	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	log_scroll.add_child(log_label)

	# 消耗品按钮行（战斗中主动使用，由整备携带的物品动态生成）
	consumable_panel = HBoxContainer.new()
	consumable_panel.add_theme_constant_override("separation", 6)
	vbox.add_child(consumable_panel)

	# 底部：SPIN / 净化 / 重新整备 / 重置
	var bot = HBoxContainer.new()
	bot.add_theme_constant_override("separation", 6)
	vbox.add_child(bot)
	var spin = Button.new()
	spin.text = "SPIN (空格)"
	spin.custom_minimum_size = Vector2(110, 32)
	spin.add_theme_font_size_override("font_size", 12)
	spin.connect("pressed", _on_spin_pressed)
	bot.add_child(spin)
	var purify = Button.new()
	purify.text = "净化"
	purify.custom_minimum_size = Vector2(80, 32)
	purify.add_theme_font_size_override("font_size", 11)
	purify.connect("pressed", _on_purify_pressed)
	bot.add_child(purify)
	purify_label = _label("净化: 2", 10)
	bot.add_child(purify_label)
	var re_eq = Button.new()
	re_eq.text = "整备"
	re_eq.custom_minimum_size = Vector2(72, 32)
	re_eq.add_theme_font_size_override("font_size", 11)
	re_eq.connect("pressed", _on_reload_loadout_pressed)
	bot.add_child(re_eq)
	var reset = Button.new()
	reset.text = "重置"
	reset.custom_minimum_size = Vector2(72, 32)
	reset.add_theme_font_size_override("font_size", 11)
	reset.connect("pressed", _full_reset)
	bot.add_child(reset)

	_build_overlay()


# ---------------------------------------------------------------------------
# 整备界面（M3–M6）：武器 / 消耗品 / 护符 三分类自由勾选
# ---------------------------------------------------------------------------
func _build_loadout_screen() -> void:
	loadout_screen = Control.new()
	loadout_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loadout_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg = ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.10, 0.98)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loadout_screen.add_child(bg)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	loadout_screen.add_child(margin)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	margin.add_child(v)
	v.add_child(_label("⚙ 整备 · 选择携带物品", 15))
	v.add_child(_label("武器 %d–%d 把 · 消耗品 0–%d · 护符 0–%d · 总槽 %d" % [LOADOUT_MIN, LOADOUT_MAX, CONSUMABLE_MAX, CHARM_MAX, TOTAL_MAX], 10))
	v.add_child(_label("武器=转轮符号池 · 消耗品=战斗中主动用 · 护符=整局被动", 9))

	# 三分类卡片区（同一可滚动容器内分三段）
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)

	loadout_grid = VBoxContainer.new()
	loadout_grid.add_theme_constant_override("separation", 6)
	scroll.add_child(loadout_grid)

	loadout_cards = []
	_add_loadout_section(loadout_grid, "武器", WEAPON_POOL, "weapon")
	_add_loadout_section(loadout_grid, "消耗品", CONSUMABLE_POOL, "consumable")
	_add_loadout_section(loadout_grid, "护符", CHARM_POOL, "charm")

	# M5 铁砧入口：点数 + 打开锻造界面
	var anvil_row = HBoxContainer.new()
	anvil_row.add_theme_constant_override("separation", 6)
	v.add_child(anvil_row)
	loadout_anvil_label = _label("铁砧点数: 0", 10)
	anvil_row.add_child(loadout_anvil_label)
	var af = Control.new()
	af.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	anvil_row.add_child(af)
	var anvil_btn = Button.new()
	anvil_btn.text = "🔨 铁砧"
	anvil_btn.custom_minimum_size = Vector2(90, 26)
	anvil_btn.add_theme_font_size_override("font_size", 10)
	anvil_btn.connect("pressed", _show_anvil_screen)
	anvil_row.add_child(anvil_btn)

	# 底部：计数 + 确认（始终可见）
	var bot = HBoxContainer.new()
	bot.add_theme_constant_override("separation", 8)
	v.add_child(bot)
	loadout_count_label = _label("已选 0/6", 11)
	bot.add_child(loadout_count_label)
	var sp = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot.add_child(sp)
	loadout_confirm_btn = Button.new()
	loadout_confirm_btn.text = "确认开战 ▶"
	loadout_confirm_btn.custom_minimum_size = Vector2(110, 30)
	loadout_confirm_btn.add_theme_font_size_override("font_size", 12)
	loadout_confirm_btn.connect("pressed", _confirm_loadout)
	bot.add_child(loadout_confirm_btn)

	add_child(loadout_screen)
	loadout_screen.visible = false


func _add_loadout_section(parent: Control, title: String, pool: Array, category: String) -> void:
	parent.add_child(_label("▶ %s" % title, 12))
	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(grid)
	for path in pool:
		var data: Resource = load(path)
		var card = _make_item_card(data, path, category)
		grid.add_child(card["btn"])
		loadout_cards.append(card)


func _make_item_card(data: Resource, path: String, category: String) -> Dictionary:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(96, 56)
	btn.text = ""
	var cc = CenterContainer.new()
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.add_child(cc)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	cc.add_child(vb)
	var name := ""
	var detail := ""
	if category == "weapon":
		name = data.weapon_name if (data != null) else path.get_file().get_basename()
		if data != null and typeof(data.get("reel_symbols")) == TYPE_DICTIONARY:
			var parts := []
			for key in data.reel_symbols.keys():
				var sid := int(key)
				var d = ReelSymbol.get_symbol(sid)
				parts.append("%s%s×%d" % [d["label"], d["name"], int(data.reel_symbols[key])])
			detail = " ".join(parts)
	else:
		name = data.item_name if (data != null) else path.get_file().get_basename()
		if data != null:
			detail = "%s %s" % [data.icon, data.description]
	vb.add_child(_label(name, 11))
	var dl = _label(detail, 9)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(dl)
	var card := {"path": path, "btn": btn, "selected": false, "category": category}
	btn.connect("pressed", _on_card_toggled.bind(card))
	return card


# 卡片点击：三分类通用 toggle（受分类上限与总槽约束）
func _on_card_toggled(card: Dictionary) -> void:
	var cat = card["category"]
	var arr = _sel_arr(cat)
	if card["selected"]:
		card["selected"] = false
		arr.erase(card["path"])
	else:
		if arr.size() >= _cat_max(cat):
			_log("%s已达上限 %d" % [_cat_name(cat), _cat_max(cat)])
			return
		if _total_selected() >= TOTAL_MAX:
			_log("总槽已达上限 %d" % TOTAL_MAX)
			return
		card["selected"] = true
		arr.append(card["path"])
	_update_loadout_cards_visual()
	_update_loadout_count()


func _sel_arr(cat: String) -> Array:
	match cat:
		"weapon":     return selected_loadout
		"consumable": return selected_consumables
		"charm":      return selected_charms
	return []


func _cat_max(cat: String) -> int:
	match cat:
		"weapon":     return LOADOUT_MAX
		"consumable": return CONSUMABLE_MAX
		"charm":      return CHARM_MAX
	return 99


func _cat_name(cat: String) -> String:
	match cat:
		"weapon":     return "武器"
		"consumable": return "消耗品"
		"charm":      return "护符"
	return cat


func _total_selected() -> int:
	return selected_loadout.size() + selected_consumables.size() + selected_charms.size()


func _update_loadout_cards_visual() -> void:
	var wfull = selected_loadout.size() >= LOADOUT_MAX
	var cfull = selected_consumables.size() >= CONSUMABLE_MAX
	var hfull = selected_charms.size() >= CHARM_MAX
	var tfull = _total_selected() >= TOTAL_MAX
	for card in loadout_cards:
		var sb = StyleBoxFlat.new()
		if card["selected"]:
			sb.bg_color = Color(0.20, 0.32, 0.22, 1)
			sb.border_color = Color(0.45, 0.85, 0.50, 1)
			sb.set_border_width_all(2)
			card["btn"].disabled = false
		else:
			sb.bg_color = Color(0.16, 0.16, 0.22, 1)
			sb.border_color = Color(0.30, 0.30, 0.38, 1)
			sb.set_border_width_all(1)
			var cf = (card["category"] == "weapon" and wfull) or (card["category"] == "consumable" and cfull) or (card["category"] == "charm" and hfull)
			card["btn"].disabled = (cf or tfull)
		card["btn"].add_theme_stylebox_override("normal", sb)
		card["btn"].add_theme_stylebox_override("hover", sb)
		card["btn"].add_theme_stylebox_override("pressed", sb)
		card["btn"].add_theme_stylebox_override("disabled", sb)


func _update_loadout_count() -> void:
	var t = _total_selected()
	loadout_count_label.text = "武器 %d · 消耗 %d · 护符 %d · 总 %d/%d" % [selected_loadout.size(), selected_consumables.size(), selected_charms.size(), t, TOTAL_MAX]
	var ok = selected_loadout.size() >= LOADOUT_MIN and t <= TOTAL_MAX
	loadout_confirm_btn.disabled = not ok
	loadout_confirm_btn.text = ("确认开战 ▶" if ok else "至少选 %d 把武器 ▶" % LOADOUT_MIN)


func _show_loadout_screen() -> void:
	in_loadout = true
	_update_loadout_cards_visual()
	_update_loadout_count()
	_update_loadout_anvil()
	loadout_screen.visible = true


func _update_loadout_anvil() -> void:
	if loadout_anvil_label != null:
		loadout_anvil_label.text = "铁砧点数: %d" % meta["anvil_points"]


func _hide_loadout_screen() -> void:
	in_loadout = false
	loadout_screen.visible = false


func _confirm_loadout() -> void:
	if selected_loadout.size() < LOADOUT_MIN:
		return
	_apply_charms()                       # 结算护符被动 + 净化上限
	_hide_loadout_screen()
	_full_reset()


# 结算护符被动（整局生效）与净化上限（净化药剂 + 丰沛护符）
func _apply_charms() -> void:
	charm_power_bonus = 0
	charm_room_shield = 0
	charm_interf_resist = 0
	charm_purify_bonus = 0
	for path in selected_charms:
		var cd: Resource = load(path)
		if cd == null:
			continue
		match cd.effect:
			"damage_bonus":         charm_power_bonus += cd.value
			"room_shield":          charm_room_shield += cd.value
			"interference_resist":  charm_interf_resist += cd.value
			"purify_bonus":         charm_purify_bonus += cd.value
	var pm = 0
	for path in selected_consumables:
		var cd: Resource = load(path)
		if cd != null and cd.effect == "purify":
			pm += cd.value
	purify_max_base = pm + charm_purify_bonus
	_log("护符已装配：伤害+%d / 护盾+%d / 抗扰+%d / 净化+%d" % [charm_power_bonus, charm_room_shield, charm_interf_resist, charm_purify_bonus])


func _on_reload_loadout_pressed() -> void:
	_show_loadout_screen()


# ---------------------------------------------------------------------------
# M4 房奖励三选一界面（Roguelike 构筑）
# ---------------------------------------------------------------------------
func _build_reward_screen() -> void:
	reward_screen = Control.new()
	reward_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reward_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.12, 0.98)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reward_screen.add_child(bg)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	reward_screen.add_child(margin)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	margin.add_child(v)
	reward_title_label = _label("", 18)
	v.add_child(reward_title_label)
	v.add_child(_label("选择一项奖励带入后续房间（Roguelike 构筑，跳过则不取）", 11))

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
	reward_skip_btn = Button.new()
	reward_skip_btn.text = "跳过 ▶"
	reward_skip_btn.custom_minimum_size = Vector2(110, 30)
	reward_skip_btn.connect("pressed", _on_reward_skip_pressed)
	bot.add_child(reward_skip_btn)

	add_child(reward_screen)
	reward_screen.visible = false


func _show_reward_screen(is_boss: bool) -> void:
	reward_is_boss = is_boss
	reward_choices = _roll_rewards()
	# 清理旧卡片
	for c in reward_grid.get_children():
		reward_grid.remove_child(c)
		c.queue_free()
	reward_title_label.text = ("★ 通关！选择一项残余物奖励" if is_boss else "胜利！选择一项房奖励")
	for rw in reward_choices:
		reward_grid.add_child(_make_reward_card(rw))
	reward_screen.visible = true


func _make_reward_card(rw: Dictionary) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(96, 64)
	btn.text = ""
	var cc = CenterContainer.new()
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.add_child(cc)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	cc.add_child(vb)
	vb.add_child(_label("%s %s" % [rw["icon"], rw["label"]], 13))
	var dl = _label(rw["desc"], 10)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(dl)
	btn.connect("pressed", _on_reward_chosen.bind(rw["id"]))
	return btn


func _on_reward_chosen(id: String) -> void:
	reward_screen.visible = false
	_apply_reward(id)
	_award_meta(reward_is_boss)    # M5：房间通关发放铁砧点数
	if reward_is_boss:
		_full_reset()              # 通关后开新一局
	else:
		_start_room(room_index + 1)
	_refresh_meta()


func _on_reward_skip_pressed() -> void:
	reward_screen.visible = false
	_award_meta(reward_is_boss)    # M5：房间通关发放铁砧点数（即使跳过奖励）
	if reward_is_boss:
		_full_reset()
	else:
		_start_room(room_index + 1)
	_refresh_meta()


func _roll_rewards() -> Array:
	var copy = REWARD_POOL.duplicate(true)
	var out := []
	for i in 3:
		if copy.is_empty():
			break
		var idx = randi() % copy.size()
		out.append(copy[idx])
		copy.remove_at(idx)
	return out


func _apply_reward(id: String) -> void:
	match id:
		"heal":
			var h = int(player_hp_max * 0.35)
			player_hp = min(player_hp_max, player_hp + h)
			_log("奖励：治疗 +%d HP" % h)
		"maxhp":
			player_hp_max += 20
			player_hp = player_hp_max
			_log("奖励：最大 HP +20 并回满")
		"purify":
			purify_max_base += 1
			_log("奖励：净化上限 +1（当前 %d）" % purify_max_base)
		"symbol":
			var cand := []
			for p in pool:
				if p[0] != ReelSymbol.Id.TRASH:
					cand.append(p[0])
			if cand.is_empty():
				cand = [ReelSymbol.Id.SLASH]
			var sid = cand[randi() % cand.size()]
			run_symbol_bonus[sid] = run_symbol_bonus.get(sid, 0) + 3
			_log("奖励：%s 符号权重 +3" % ReelSymbol.get_symbol(sid)["name"])
		"shield":
			run_shield_next += 15
			_log("奖励：下一房 +15 护盾")
		"power":
			run_power_bonus += 1
			_log("奖励：本局符号伤害 +1（当前 +%d）" % run_power_bonus)


# ---------------------------------------------------------------------------
# M5 元进度（铁砧锻造 + 存档持久化）
# ---------------------------------------------------------------------------
func _load_meta() -> void:
	var defaults := {"anvil_points": 0, "weapon_upgrades": {}, "interference_resist": 0}
	if FileAccess.file_exists(SAVE_PATH):
		var f = FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f:
			var txt = f.get_as_text()
			f.close()
			var parsed = JSON.parse_string(txt)
			if parsed is Dictionary:
				for k in defaults.keys():
					if parsed.has(k):
						meta[k] = parsed[k]
	_log("铁砧元进度已载入：点数 %d，武器升级 %d，抗干扰 Lv%d" % \
		[meta["anvil_points"], meta["weapon_upgrades"].size(), meta["interference_resist"]])


func _save_meta() -> void:
	var f = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(meta))
		f.close()


# 房间通关（含 Boss）发放铁砧点数并持久化；is_boss 给额外奖励
func _award_meta(is_boss: bool) -> void:
	var pts = 8 + (25 if is_boss else 0)
	meta["anvil_points"] += pts
	_save_meta()
	_log("铁砧点数 +%d（共 %d）" % [pts, meta["anvil_points"]])


func _build_anvil_screen() -> void:
	anvil_screen = Control.new()
	anvil_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anvil_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg = ColorRect.new()
	bg.color = Color(0.10, 0.08, 0.05, 0.98)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anvil_screen.add_child(bg)

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	anvil_screen.add_child(margin)

	var v = VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	margin.add_child(v)
	anvil_title_label = _label("🔨 铁砧锻造 · 元进度", 16)
	v.add_child(anvil_title_label)
	anvil_points_label = _label("铁砧点数: 0", 11)
	v.add_child(anvil_points_label)
	v.add_child(_label("消耗点数永久强化转轮 / 抗干扰（跨局保留）", 9))

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
	anvil_back_btn = Button.new()
	anvil_back_btn.text = "返回整备"
	anvil_back_btn.custom_minimum_size = Vector2(110, 30)
	anvil_back_btn.add_theme_font_size_override("font_size", 12)
	anvil_back_btn.connect("pressed", _on_anvil_back_pressed)
	bot.add_child(anvil_back_btn)

	add_child(anvil_screen)
	anvil_screen.visible = false


func _show_anvil_screen() -> void:
	_refresh_anvil()
	anvil_screen.visible = true


func _refresh_anvil() -> void:
	anvil_points_label.text = "铁砧点数: %d" % meta["anvil_points"]
	# 清理旧卡片
	for c in anvil_grid.get_children():
		anvil_grid.remove_child(c)
		c.queue_free()
	# 武器转轮升级
	for path in WEAPON_POOL:
		var wd: Resource = load(path)
		var wname = wd.weapon_name if (wd != null) else path.get_file().get_basename()
		var lvl = meta["weapon_upgrades"].get(path, 0)
		var cost = (lvl + 1) * 10
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(96, 56)
		btn.text = ""
		var cc = CenterContainer.new()
		cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.add_child(cc)
		var vb = VBoxContainer.new()
		vb.add_theme_constant_override("separation", 1)
		cc.add_child(vb)
		vb.add_child(_label(wname, 11))
		vb.add_child(_label("转轮 Lv%d" % lvl, 9))
		vb.add_child(_label("升级 %d 点" % cost, 9))
		btn.connect("pressed", _on_anvil_weapon_pressed.bind(path))
		anvil_grid.add_child(btn)
	# 抗干扰
	var rl = meta["interference_resist"]
	var rcost = (rl + 1) * 15
	var rbtn = Button.new()
	rbtn.custom_minimum_size = Vector2(96, 56)
	rbtn.text = ""
	var rcc = CenterContainer.new()
	rcc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rcc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rbtn.add_child(rcc)
	var rvb = VBoxContainer.new()
	rvb.add_theme_constant_override("separation", 1)
	rcc.add_child(rvb)
	rvb.add_child(_label("锤炼意志", 11))
	rvb.add_child(_label("抗干扰 Lv%d/5" % rl, 9))
	if rl >= 5:
		rvb.add_child(_label("已满级", 9))
	else:
		rvb.add_child(_label("升级 %d 点" % rcost, 9))
	rbtn.connect("pressed", _on_anvil_resist_pressed)
	anvil_grid.add_child(rbtn)


func _on_anvil_weapon_pressed(path: String) -> void:
	var lvl = meta["weapon_upgrades"].get(path, 0)
	var cost = (lvl + 1) * 10
	if meta["anvil_points"] < cost:
		_log("铁砧点数不足（%s 需 %d）" % [path.get_file().get_basename(), cost])
		return
	meta["anvil_points"] -= cost
	meta["weapon_upgrades"][path] = lvl + 1
	_save_meta()
	_refresh_anvil()
	_log("铁砧：%s 转轮升级 Lv%d" % [path.get_file().get_basename(), lvl + 1])


func _on_anvil_resist_pressed() -> void:
	var rl = meta["interference_resist"]
	if rl >= 5:
		_log("抗干扰已满级")
		return
	var cost = (rl + 1) * 15
	if meta["anvil_points"] < cost:
		_log("铁砧点数不足（抗干扰需 %d）" % cost)
		return
	meta["anvil_points"] -= cost
	meta["interference_resist"] = rl + 1
	_save_meta()
	_refresh_anvil()
	_log("铁砧：抗干扰 Lv%d（敌人干扰概率降低）" % (rl + 1))


func _on_anvil_back_pressed() -> void:
	anvil_screen.visible = false
	_update_loadout_anvil()


func _build_overlay() -> void:
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var ov_bg = ColorRect.new()
	ov_bg.color = Color(0, 0, 0, 0.72)
	ov_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(ov_bg)
	var ov_c = CenterContainer.new()
	ov_c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(ov_c)
	var ov_v = VBoxContainer.new()
	ov_v.add_theme_constant_override("separation", 18)
	ov_c.add_child(ov_v)
	overlay_label = _label("", 30)
	ov_v.add_child(overlay_label)
	overlay_button = Button.new()
	overlay_button.custom_minimum_size = Vector2(220, 50)
	overlay_button.connect("pressed", _on_overlay_button_pressed)
	ov_v.add_child(overlay_button)
	add_child(overlay)
	overlay.visible = false


# ---------------------------------------------------------------------------
# 房间 / 流程
# ---------------------------------------------------------------------------
func _full_reset() -> void:
	player_hp = player_hp_max
	# M4：开新一局，重置本局加成层
	run_symbol_bonus = {}
	run_power_bonus = 0
	run_shield_next = 0
	_build_pool(selected_loadout)
	_start_room(0)


func _start_room(idx: int) -> void:
	room_index = idx
	var r: Dictionary = ROOMS[idx]
	enemy_name = r["name"]
	enemy_hp_max = r["hp"]
	enemy_hp = enemy_hp_max
	enemy_atk = r["atk"]
	enemy_jam = r["jam"]
	enemy_lock = r["lock"]
	enemy_chaos = r["chaos"]
	enemy_heavy = r["heavy"]
	# M5+M6 抗干扰：铁砧 + 抗扰护符 共同降低敌人干扰概率（每级 -12%，最低保留 25%）
	var total_resist = meta["interference_resist"] + charm_interf_resist
	if total_resist > 0:
		var rf = max(0.25, 1.0 - total_resist * 0.12)
		enemy_jam *= rf
		enemy_lock *= rf
		enemy_chaos *= rf
	enemy_status = {}
	player_shield = 0
	player_shield += run_shield_next      # M4：上一房奖励的结界在本房开局生效
	player_shield += charm_room_shield    # M6：守望护符每房开局护盾
	run_shield_next = 0
	pending_jam_reel = -1
	pending_lock_reel = -1
	pending_chaos = false
	purify_charges = purify_max_base      # 净化上限（净化药剂 + 丰沛护符 + 房奖励）
	# M6：消耗品每房回满次数
	consumable_charges = {}
	for path in selected_consumables:
		var cd: Resource = load(path)
		if cd != null:
			consumable_charges[cd.item_id] = cd.charges
	_rebuild_consumable_panel()
	game_state = "playing"
	turn_count = 1
	enemy_intent = {}
	_hide_overlay()
	_reset_grid(true)
	_begin_player_turn()
	_refresh_meta()
	_log("▶ 进入房间 %d/%d：%s（HP %d，攻击 %d）" % [idx + 1, ROOMS.size(), enemy_name, enemy_hp_max, enemy_atk])


func _begin_player_turn() -> void:
	if game_state != "playing":
		return
	var rnd = randf()
	if rnd < enemy_jam:
		enemy_intent = {"type": "jam", "value": 0}
	elif rnd < enemy_jam + enemy_lock:
		enemy_intent = {"type": "lock", "value": 0}
	elif rnd < enemy_jam + enemy_lock + enemy_chaos:
		enemy_intent = {"type": "chaos", "value": 0}
	elif rnd < enemy_jam + enemy_lock + enemy_chaos + enemy_heavy:
		enemy_intent = {"type": "heavy", "value": enemy_atk * 2}
	else:
		enemy_intent = {"type": "attack", "value": enemy_atk}


func _on_spin_pressed() -> void:
	if in_loadout:
		return
	if game_state != "playing":
		return
	turn_count += 1
	_do_spin_core()
	if enemy_hp <= 0:
		_log("★ 击败 %s！" % enemy_name)
		game_state = "won"
		var is_boss = (room_index + 1 >= ROOMS.size())
		var title = ("★ 通关！\n%s 被击败" % enemy_name) if is_boss else ("★ 胜利！\n%s 被击败" % enemy_name)
		_show_overlay(title, "领取奖励 ▶")
		_refresh_meta()
		return

	_enemy_turn()

	if player_hp <= 0:
		_log("✖ 你被 %s 击倒。" % enemy_name)
		game_state = "lost"
		_show_overlay("✖ 失败\n你倒在了 %s 面前" % enemy_name, "重试本房 ↺")
		_refresh_meta()
		return

	_begin_player_turn()
	_refresh_meta()


# 旋转 + 结算核心（SPIN 与重转卷轴共用）
func _do_spin_core() -> void:
	var chaos_this_spin = pending_chaos
	if chaos_this_spin:
		_apply_chaos_pool()
	for reel in REELS:
		for row in ROWS:
			var sym: int
			if reel == pending_jam_reel:
				sym = ReelSymbol.Id.TRASH
			elif reel == pending_lock_reel:
				sym = grid[reel][row]
			else:
				sym = _weighted_random_sym()
			grid[reel][row] = sym
			_refresh_cell(reel, row)
	pending_jam_reel = -1
	pending_lock_reel = -1
	pending_chaos = false
	if chaos_this_spin:
		_restore_pool()
	_evaluate()


# 重转卷轴：免费重转一次（不触发敌人回合）
func _free_spin() -> void:
	_do_spin_core()
	if enemy_hp <= 0:
		_log("★ 重转触发击败 %s！" % enemy_name)
		game_state = "won"
		var is_boss = (room_index + 1 >= ROOMS.size())
		var title = ("★ 通关！\n%s 被击败" % enemy_name) if is_boss else ("★ 胜利！\n%s 被击败" % enemy_name)
		_show_overlay(title, "领取奖励 ▶")
	_refresh_meta()


func _enemy_turn() -> void:
	var it: Dictionary = enemy_intent
	match it.get("type", "attack"):
		"attack", "heavy":
			_enemy_deal_damage(it.get("value", enemy_atk))
		"jam":
			pending_jam_reel = randi() % REELS
			_log("敌人注废 → 下一轮第 %d 列被废铁占据" % (pending_jam_reel + 1))
		"lock":
			pending_lock_reel = randi() % REELS
			_log("敌人锁轮 → 下一轮第 %d 列固定不变" % (pending_lock_reel + 1))
		"chaos":
			pending_chaos = true
			_log("敌人乱权 → 下一轮权重被打乱（优势符号被削弱）")
		"none":
			_log("敌人意图落空（已被净化）")
	enemy_intent = {}
	_tick_status()


func _enemy_deal_damage(raw: int) -> void:
	var blocked = min(player_shield, raw)
	player_shield -= blocked
	var dealt = raw - blocked
	player_hp -= dealt
	_log("敌人攻击 %d（盾挡 %d，受 %d）" % [raw, blocked, dealt])


func _tick_status() -> void:
	var dot = 0
	for st in enemy_status.keys():
		var base = _status_base(st)
		dot += enemy_status[st] * base
		enemy_status[st] = max(0, enemy_status[st] - 1)
		if enemy_status[st] <= 0:
			enemy_status.erase(st)
	if dot > 0:
		enemy_hp -= dot
		_log("状态结算 %d 伤害（灼烧/毒）" % dot)


func _on_purify_pressed() -> void:
	if in_loadout:
		return
	if game_state != "playing":
		return
	if enemy_intent.is_empty():
		_log("当前敌人无意图，无需净化")
		return
	if enemy_intent.get("type") not in ["jam", "lock", "chaos"]:
		_log("当前意图不可净化（攻击/重击）")
		return
	if purify_charges <= 0:
		_log("净化次数已用尽（整备携带的净化药剂不足）")
		return
	purify_charges -= 1
	var t = enemy_intent.get("type")
	enemy_intent = {"type": "none", "value": 0}
	_log("净化成功：抵消了敌人的%s" % _intent_name(t))
	_refresh_meta()


func _intent_name(t: String) -> String:
	match t:
		"jam":   return "注废"
		"lock":  return "锁轮"
		"chaos": return "乱权"
		"heavy": return "重击"
		"attack": return "攻击"
		_:      return t


# ---------------------------------------------------------------------------
# M6 消耗品：战斗中主动使用
# ---------------------------------------------------------------------------
# 根据整备携带的消耗品，重建战斗 UI 底部按钮行（每房调用一次）
func _rebuild_consumable_panel() -> void:
	for c in consumable_panel.get_children():
		consumable_panel.remove_child(c)
		c.queue_free()
	consumable_buttons = []
	if selected_consumables.is_empty():
		return
	for path in selected_consumables:
		var cd: Resource = load(path)
		if cd == null:
			continue
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(86, 30)
		btn.add_theme_font_size_override("font_size", 10)
		btn.connect("pressed", _on_consumable_pressed.bind(cd.item_id))
		consumable_panel.add_child(btn)
		consumable_buttons.append({"id": cd.item_id, "data": cd, "btn": btn})
	_refresh_consumable_panel()


func _refresh_consumable_panel() -> void:
	for m in consumable_buttons:
		var left = consumable_charges.get(m["id"], 0)
		m["btn"].text = "%s%s(%d)" % [m["data"].icon, m["data"].item_name, left]
		m["btn"].disabled = (left <= 0 or game_state != "playing" or in_loadout)


func _on_consumable_pressed(id: String) -> void:
	if in_loadout or game_state != "playing":
		return
	if consumable_charges.get(id, 0) <= 0:
		_log("「%s」已用尽" % id)
		return
	var data: Resource = null
	for m in consumable_buttons:
		if m["id"] == id:
			data = m["data"]
			break
	if data == null:
		return
	consumable_charges[id] -= 1
	match data.effect:
		"purify":
			if enemy_intent.get("type") in ["jam", "lock", "chaos"]:
				enemy_intent = {"type": "none", "value": 0}
				_log("净化药剂：抵消了敌人的干扰意图")
			purify_charges += data.value
			_log("净化药剂：恢复 %d 点净化次数（现 %d）" % [data.value, purify_charges])
		"heal":
			player_hp = min(player_hp_max, player_hp + data.value)
			_log("治疗药剂：回复 %d HP（现 %d）" % [data.value, player_hp])
		"assault":
			assault_next_spin = data.value
			_log("强袭药剂：下一次转轮伤害 ×%d" % data.value)
		"reroll":
			_log("重转卷轴：免费重转！")
			_free_spin()
	_refresh_consumable_panel()
	_refresh_meta()


func _on_overlay_button_pressed() -> void:
	match game_state:
		"won":    _show_reward_screen(room_index + 1 >= ROOMS.size())   # M4：胜利→房奖励三选一
		"lost":   _retry_room()
		"cleared": _full_reset()


func _retry_room() -> void:
	player_hp = player_hp_max
	_start_room(room_index)


# ---------------------------------------------------------------------------
# 结算（方案 A：单符号必结算 + 匹配倍率）
# ---------------------------------------------------------------------------
func _reset_grid(fill_random: bool) -> void:
	for reel in REELS:
		for row in ROWS:
			grid[reel][row] = ReelSymbol.Id.TRASH
			if fill_random:
				grid[reel][row] = _weighted_random_sym()
			_refresh_cell(reel, row)


func _contribute(sym_id: int, mult: int, acc: Dictionary) -> void:
	var d = ReelSymbol.get_symbol(sym_id)
	var flat = d["base"] + run_power_bonus + charm_power_bonus   # M6：锋锐护符加成
	match d["kind"]:
		"damage":  acc["dmg"]     += flat * mult
		"shield":  acc["shield"]  += d["base"] * mult
		"heal":    acc["heal"]    += d["base"] * mult
		"status":  acc["status_stacks"][d["status"]] = acc["status_stacks"].get(d["status"], 0) + mult
		"special": acc["special"] += flat * mult
		_: pass


func _evaluate() -> void:
	var acc = { "dmg": 0, "shield": 0, "heal": 0, "status_stacks": {}, "special": 0 }

	var row_syms: Array = []
	for p in PAYLINES[0]:
		row_syms.append(grid[p[0]][p[1]])
	var counts = {}
	for s in row_syms:
		counts[s] = counts.get(s, 0) + 1
	for s in counts:
		if s == ReelSymbol.Id.TRASH:
			continue
		var c = counts[s]
		var d = ReelSymbol.get_symbol(s)
		if d["kind"] == "special" and c < 3:
			continue
		_contribute(s, c, acc)

	for st in acc["status_stacks"].keys():
		enemy_status[st] = enemy_status.get(st, 0) + acc["status_stacks"][st]

	var total_dmg = (acc["dmg"] + acc["special"]) * assault_next_spin   # M6：强袭药剂翻倍
	assault_next_spin = 1
	if total_dmg > 0:
		enemy_hp -= total_dmg
		_log("连线造成 %d 伤害" % total_dmg)
	if acc["shield"] > 0:
		player_shield += acc["shield"]
		_log("获得 %d 护盾" % acc["shield"])
	if acc["heal"] > 0:
		player_hp = min(player_hp_max, player_hp + acc["heal"])
		_log("回复 %d HP" % acc["heal"])
	if not acc["status_stacks"].is_empty():
		_log("敌人获得状态: " + _status_summary(acc["status_stacks"]))


func _status_base(type_str: String) -> float:
	for id in ReelSymbol.CATALOG.keys():
		var d = ReelSymbol.CATALOG[id]
		if d.has("status") and d["status"] == type_str:
			return d["base"]
	return 0.0


func _status_summary(stacks: Dictionary) -> String:
	var parts: Array = []
	for st in stacks.keys():
		parts.append("%s+%d" % [st, stacks[st]])
	return "/".join(parts)


# ---------------------------------------------------------------------------
# 表现刷新
# ---------------------------------------------------------------------------
func _refresh_cell(reel: int, row: int) -> void:
	var b: Button = cells[reel][row]
	var s: int = grid[reel][row]
	var d = ReelSymbol.get_symbol(s)
	b.text = d["label"]
	b.add_theme_color_override("font_color", d["color"])
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.18, 0.24, 1)
	b.add_theme_stylebox_override("normal", sb)


func _refresh_meta() -> void:
	loadout_label.text = "已装备: " + ("/".join(loadout_names) if not loadout_names.is_empty() else "—")
	room_label.text = "房间: %d/%d" % [room_index + 1, ROOMS.size()]
	turn_label.text = "回合: %d" % turn_count
	player_hp_label.text = "玩家 HP: %d/%d" % [player_hp, player_hp_max]
	player_shield_label.text = "护盾: %d" % player_shield
	enemy_name_label.text = enemy_name
	enemy_hp_label.text = "HP: %d/%d" % [max(enemy_hp, 0), enemy_hp_max]
	enemy_status_label.text = "状态: " + ("无" if enemy_status.is_empty() else _status_summary(enemy_status))
	purify_label.text = "净化: %d/%d" % [purify_charges, purify_max_base]
	# M4+M6 本局加成概览
	var parts := []
	if run_power_bonus + charm_power_bonus > 0:
		parts.append("伤害+%d" % (run_power_bonus + charm_power_bonus))
	if purify_max_base > 0:
		parts.append("净化上限%d" % purify_max_base)
	if charm_room_shield > 0:
		parts.append("护盾+%d" % charm_room_shield)
	if charm_interf_resist > 0:
		parts.append("抗扰+%d" % charm_interf_resist)
	if not run_symbol_bonus.is_empty():
		var sp := []
		for sid in run_symbol_bonus.keys():
			sp.append("%s+%d" % [ReelSymbol.get_symbol(sid)["name"], run_symbol_bonus[sid]])
		parts.append("符号:" + "/".join(sp))
	if run_shield_next > 0:
		parts.append("下房盾+%d" % run_shield_next)
	run_label.text = "本局加成: " + ("无" if parts.is_empty() else " / ".join(parts))
	if enemy_intent.is_empty():
		enemy_intent_label.text = "意图: —"
	else:
		var t = enemy_intent["type"]
		match t:
			"attack": enemy_intent_label.text = "意图: ⚔ 攻击 %d" % enemy_intent["value"]
			"heavy":  enemy_intent_label.text = "意图: 💥 重击 %d" % enemy_intent["value"]
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
	logs.push_front(msg)
	if logs.size() > 10:
		logs.pop_back()
	if log_label != null:
		log_label.text = "\n".join(logs)


func _input(event) -> void:
	if in_loadout:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_on_spin_pressed()
