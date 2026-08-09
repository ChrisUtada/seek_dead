extends Control
class_name ShopScreen

# shop_screen — 商店（购入 / 卖出 / 升级三页签）覆盖层（P3b-2 抽独立场景）
# 静态骨架由 shop_screen.tscn 提供；本脚本负责显隐 / 填数据 / 切页签 / 发信号。
# 卡片构造复用 HUD 的 _make_shop_card / _make_sell_card / _make_upgrade_card。

var controller
var hud: BattleHud
const DRAWER_W := 420          # 抽屉宽度（右侧 docked）
var _open := false             # 抽屉是否处于展开态（供外部 toggle 判断）
var _pending_offer: Dictionary = {}   # 待替换购买的武器货品（2026-08-07）

@onready var bg = $Bg
@onready var title_label = $Margin/Content/TitleLabel
@onready var gold_label = $Margin/Content/GoldLabel
@onready var buy_panel = $Margin/Content/BuyPanel
@onready var sell_panel = $Margin/Content/SellPanel
@onready var shop_grid = $Margin/Content/BuyPanel/ShopGrid
@onready var weapon_list = $Margin/Content/SellPanel/SellBox/WeaponList
@onready var skill_list = $Margin/Content/SellPanel/SellBox/SkillList
@onready var charm_list = $Margin/Content/SellPanel/SellBox/CharmList
@onready var consum_list = $Margin/Content/SellPanel/SellBox/ConsumList
@onready var shop_tab_buy_btn = $Margin/Content/TabBar/BuyTab
@onready var shop_tab_sell_btn = $Margin/Content/TabBar/SellTab
@onready var leave_btn = $Margin/Content/Bot/LeaveBtn

func configure(ctrl, h: BattleHud) -> void:
	controller = ctrl
	hud = h
	bg.color = Palette.BG_REWARD
	title_label.text = "🛒 商店"
	# 两页签（T28：升级页已迁出为 BOSS 战后的训练房）
	shop_tab_buy_btn.connect("pressed", show_tab.bind("buy"))
	shop_tab_sell_btn.connect("pressed", show_tab.bind("sell"))
	leave_btn.connect("pressed", hud.shop_leave_requested.emit)
	hud.shop_card_pressed.connect(_on_shop_card_pressed)
	show_tab("buy")


# 商店卡片点击：武器且已带满 2 把 → 弹替换面板（换装，battle_hud 通用弹层）；否则正常购买
func _on_shop_card_pressed(offer: Dictionary) -> void:
	if offer.get("kind", "") == "weapon" and controller._loadout_system.sel_arr("weapon").size() >= 2:
		_pending_offer = offer
		var info := ""
		var res: Resource = load(offer.get("path", ""))
		if res != null and "rarity" in res and "base_power" in res:
			var elem_txt := ElementCounter.label(String(res.get("element") if "element" in res else "none"))
			var hit_pct: int = int(float(res.get("hit_rate") if "hit_rate" in res else 1.0) * 100)
			info = "新武器：%s · %s · 攻%d · 命中%d%% · %s" % [offer.get("name", "?"), String(res.get("rarity")), int(res.get("base_power")), hit_pct, elem_txt]
		else:
			info = "新武器：%s" % offer.get("name", "?")
		hud.request_weapon_replace("替换武器", info, func(old_path: String):
			hud.buy_replace_requested.emit(_pending_offer, old_path))
	else:
		hud.buy_requested.emit(offer)

func show_screen() -> void:
	# 货架由 controller 在进入房间歇态时生成一次（_enter_interroom → _roll_shop），
	# 本屏只渲染——反复开关商店不刷新货架（防「买完再开刷货架」）
	refresh()
	visible = true
	_open = true
	# 从右缘滑入：收起态 offset_left=0（零宽），展开到 -DRAWER_W
	offset_left = 0.0
	var tw = create_tween()
	tw.tween_property(self, "offset_left", -DRAWER_W, 0.22).set_ease(Tween.EASE_OUT)


func is_shown() -> bool:
	return _open


func refresh() -> void:
	gold_label.text = "金币: %d" % controller.state.gold
	for c in shop_grid.get_children():
		shop_grid.remove_child(c)
		c.queue_free()
	for offer in controller.state.shop_offers:
		shop_grid.add_child(hud._make_shop_card(offer))
	_refresh_shop_sell()

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
	var owned = controller._loadout_system.sel_arr(kind)
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
	var active = Palette.ACCENT_GOLD
	var idle = Palette.MUTED
	if shop_tab_buy_btn != null:
		shop_tab_buy_btn.add_theme_color_override("font_color", active if tab == "buy" else idle)
	if shop_tab_sell_btn != null:
		shop_tab_sell_btn.add_theme_color_override("font_color", active if tab == "sell" else idle)

func hide_screen() -> void:
	if not visible:
		return
	_open = false
	# 滑回右缘后隐藏
	var tw = create_tween()
	tw.tween_property(self, "offset_left", 0.0, 0.18).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): visible = false)
