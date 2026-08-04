extends Control
class_name ShopScreen

# shop_screen — 商店（购入 / 卖出 / 升级三页签）覆盖层（P3b-2 抽独立场景）
# 静态骨架由 shop_screen.tscn 提供；本脚本负责显隐 / 填数据 / 切页签 / 发信号。
# 卡片构造复用 HUD 的 _make_shop_card / _make_sell_card / _make_upgrade_card。

var controller
var hud: BattleHud
const UI_BUTTON = preload("res://scenes/ui/ui_button.tscn")

@onready var bg = $Bg
@onready var title_label = $Margin/Content/TitleLabel
@onready var gold_label = $Margin/Content/GoldLabel
@onready var sub_label = $Margin/Content/SubLabel
@onready var tab_bar = $Margin/Content/TabBar
@onready var buy_panel = $Margin/Content/Scroll/Inner/BuyPanel
@onready var sell_panel = $Margin/Content/Scroll/Inner/SellPanel
@onready var up_panel = $Margin/Content/Scroll/Inner/UpPanel
@onready var shop_grid = $Margin/Content/Scroll/Inner/BuyPanel/ShopGrid
@onready var weapon_list = $Margin/Content/Scroll/Inner/SellPanel/SellBox/WeaponList
@onready var skill_list = $Margin/Content/Scroll/Inner/SellPanel/SellBox/SkillList
@onready var charm_list = $Margin/Content/Scroll/Inner/SellPanel/SellBox/CharmList
@onready var consum_list = $Margin/Content/Scroll/Inner/SellPanel/SellBox/ConsumList
@onready var up_grid = $Margin/Content/Scroll/Inner/UpPanel/UpGrid
@onready var bot = $Margin/Content/Bot

var shop_tab_buy_btn
var shop_tab_sell_btn
var shop_tab_up_btn

func configure(ctrl, h: BattleHud) -> void:
	controller = ctrl
	hud = h
	bg.color = Palette.BG_REWARD
	title_label.text = "🛒 商店 · 用金币投资战力"
	title_label.add_theme_font_size_override("font_size", TypeScale.OVERLAY)
	sub_label.text = "金币投资战力 · 购入带装备 / 卖出回收 / 升级深化乘区（每局清零）"
	sub_label.add_theme_font_size_override("font_size", TypeScale.META)
	gold_label.add_theme_color_override("font_color", Palette.ACCENT_GOLD)
	# 三页签
	shop_tab_buy_btn = _tab_btn("📥 购入", "buy")
	tab_bar.add_child(shop_tab_buy_btn)
	shop_tab_sell_btn = _tab_btn("📤 卖出", "sell")
	tab_bar.add_child(shop_tab_sell_btn)
	shop_tab_up_btn = _tab_btn("⬆ 升级", "up")
	tab_bar.add_child(shop_tab_up_btn)
	# 离开
	var sp = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot.add_child(sp)
	var leave_btn = UI_BUTTON.instantiate()
	leave_btn.text = "离开商店 ▶"
	leave_btn.custom_minimum_size = Vector2(140, 40)
	leave_btn.connect("pressed", controller._on_shop_leave_pressed)
	bot.add_child(leave_btn)
	show_tab("buy")

func _tab_btn(text: String, tab: String) -> Button:
	var b = UI_BUTTON.instantiate()
	b.text = text
	b.custom_minimum_size = Vector2(110, 34)
	b.add_theme_font_size_override("font_size", TypeScale.META)
	b.connect("pressed", show_tab.bind(tab))
	return b

func show_screen() -> void:
	controller._roll_shop()
	refresh()
	visible = true

func refresh() -> void:
	gold_label.text = "金币: %d" % controller.state.gold
	for c in shop_grid.get_children():
		shop_grid.remove_child(c)
		c.queue_free()
	for offer in controller.state.shop_offers:
		shop_grid.add_child(hud._make_shop_card(offer))
	_refresh_shop_sell()
	_refresh_shop_up()

func _refresh_shop_sell() -> void:
	_sell_fill(weapon_list, "weapon")
	_sell_fill(skill_list, "skill")
	_sell_fill(charm_list, "passive")
	_sell_fill(consum_list, "active")

func _sell_fill(list: VBoxContainer, kind: String) -> void:
	for c in list.get_children():
		if c is Label:        # 保留列标题
			continue
		list.remove_child(c)
		c.queue_free()
	if kind == "active":
		for slot in controller.state.consumable_slots:
			var name = hud._source_tag(kind) + controller._shop_name(slot["path"], kind)
			var refund = controller._sell_price(kind, slot["uid"])
			var sub = "卖出 +%d 金" % refund
			list.add_child(hud._make_sell_card(name, sub, false, hud.sell_requested.emit.bind(slot["uid"], kind)))
		return
	var owned = controller._sel_arr(kind)
	for path in owned:
		var name = hud._source_tag(kind) + controller._shop_name(path, kind)
		var refund = controller._sell_price(kind, path)
		var last = (kind == "weapon" and owned.size() <= controller.state.LOADOUT_MIN)
		var sub: String
		if last:
			sub = "最后一把 · 不可卖"
		else:
			sub = "卖出 +%d 金" % refund
		list.add_child(hud._make_sell_card(name, sub, last, hud.sell_requested.emit.bind(path, kind)))

func show_tab(tab: String) -> void:
	if buy_panel == null:
		return
	buy_panel.visible = (tab == "buy")
	sell_panel.visible = (tab == "sell")
	up_panel.visible = (tab == "up")
	var active = Palette.ACCENT_GOLD
	var idle = Palette.MUTED
	if shop_tab_buy_btn != null:
		shop_tab_buy_btn.add_theme_color_override("font_color", active if tab == "buy" else idle)
	if shop_tab_sell_btn != null:
		shop_tab_sell_btn.add_theme_color_override("font_color", active if tab == "sell" else idle)
	if shop_tab_up_btn != null:
		shop_tab_up_btn.add_theme_color_override("font_color", active if tab == "up" else idle)
	if tab == "up":
		_refresh_shop_up()

func _refresh_shop_up() -> void:
	if up_grid == null:
		return
	for c in up_grid.get_children():
		up_grid.remove_child(c)
		c.queue_free()
	for u in controller._gold_upgrade_defs():
		up_grid.add_child(hud._make_upgrade_card(u))

func hide_screen() -> void:
	visible = false
