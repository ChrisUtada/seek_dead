extends Control
class_name RewardScreen

# reward_screen — 战后成长三槽 / 同层三选一 / BOSS 战利品 / 旧奖励屏覆盖层（P3b-2 抽独立场景）
# 静态骨架由 reward_screen.tscn 提供；本脚本负责显隐 / 填数据 / 跳过信号。
# 卡片构造复用 HUD 的 _make_reward_card / _make_post_growth_card / _make_boss_reward_card / _make_loot_offer_card。
#
# 模式（_mode）：
#   ""        旧奖励屏 / BOSS 战利品（show_screen）
#   "post"    M1 战后成长三槽（show_post_battle，保留给旧调用点与测试）
#   "loot"    Step 7 同层三选一（战利品阶段）
#   "growth"  Step 7 成长阶段（技艺 / 铭印，与战利品分开结算）
#
# 键盘 / 取消：ESC 在 loot 阶段不结算任何东西（避免「取消 = 白拿金币」）；
# 在 growth 阶段等价于「保留到下次战斗」；其余模式忽略。所有结算入口都幂等（见 RewardSystem.settle_*）。

var controller
var hud: BattleHud
const UI_BUTTON = preload("res://scenes/ui/ui_button.tscn")

@onready var dimmer = $Dimmer
@onready var title_label = $Center/Dialog/Margin/Content/TitleLabel
@onready var sub_label = $Center/Dialog/Margin/Content/SubLabel
@onready var reward_grid = $Center/Dialog/Margin/Content/Scroll/RewardGrid
@onready var bot = $Center/Dialog/Margin/Content/Bot

var _skip_btn: Button = null
var _reroll_btn: Button = null
var _mode := ""

func configure(ctrl, h: BattleHud) -> void:
	controller = ctrl
	hud = h
	dimmer.color = Palette.BG_OVERLAY
	sub_label.text = "选择一项（跳过则不取）"
	sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var sp = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot.add_child(sp)
	_reroll_btn = UI_BUTTON.instantiate()
	_reroll_btn.text = "重抽"
	_reroll_btn.custom_minimum_size = Vector2(76, 30)
	_reroll_btn.visible = false
	_reroll_btn.pressed.connect(func() -> void: hud.loot_offer_reroll_requested.emit())
	bot.add_child(_reroll_btn)
	_skip_btn = UI_BUTTON.instantiate()
	_skip_btn.text = "跳过 ▶"
	_skip_btn.custom_minimum_size = Vector2(96, 30)
	_skip_btn.pressed.connect(_on_skip_pressed)
	bot.add_child(_skip_btn)


# 跳过按钮按当前模式分发：战利品 = 免费且零收益；成长 = 保留到下次；其余 = 旧跳过。
func _on_skip_pressed() -> void:
	match _mode:
		"loot":
			hud.loot_offer_skip_requested.emit()
		"growth":
			hud.post_battle_defer_requested.emit()
		_:
			hud.reward_skip_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	# 战利品阶段：ESC 只吞掉输入，不结算、不关闭（必须明确选择或跳过）。
	# 成长阶段：等价于「保留到下次战斗」——不发放任何东西，安全。
	if _mode == "growth":
		hud.post_battle_defer_requested.emit()
	get_viewport().set_input_as_handled()


# BOSS 战利品 / 旧奖励屏（直接调用路径）。普通 / 精英胜利由 show_post_battle 接管。
func show_screen(is_boss: bool) -> void:
	# 奖励候选与 reward_is_boss 由 controller._open_reward_screen 填充（UI 不再直写 controller 字段），
	# 本屏只从只读快照 state 读取渲染数据。
	controller._reward_system.open_reward_screen(is_boss)
	_clear_grid()
	_mode = ""
	reward_grid.columns = 3
	if _reroll_btn != null:
		_reroll_btn.visible = false
	var choices = controller.state.reward_choices
	var kind = controller.state.ROOMS[controller.state.room_index].kind
	sub_label.text = "选择一项（跳过则不取）"
	if _skip_btn != null:
		_skip_btn.text = "跳过 ▶"
	if is_boss:
		title_label.text = "★ BOSS 战利品"
		for rw in choices:
			reward_grid.add_child(hud._make_boss_reward_card(rw))
	elif kind == "elite":
		title_label.text = "⚔ 精英 · 战前补给"
		for i in range(choices.size()):
			reward_grid.add_child(hud._make_reward_card(choices[i], i))
	else:
		title_label.text = "胜利！选一项奖励"
		for i in range(choices.size()):
			reward_grid.add_child(hud._make_reward_card(choices[i], i))
	visible = true


# M1 战后成长三槽：标题固定，页头保留历练 / 技艺 / 铭印摘要，三张卡带槽位标签。
func show_post_battle(offer: Array, summary: String) -> void:
	_clear_grid()
	_mode = "post"
	reward_grid.columns = 3
	if _reroll_btn != null:
		_reroll_btn.visible = false
	title_label.text = "战后成长 · 选择一项"
	sub_label.text = summary
	if _skip_btn != null:
		_skip_btn.text = "放弃本次成长"
	for cand in offer:
		if String(cand.get("kind", "")) == "reward":
			reward_grid.add_child(hud._make_reward_card(cand["reward"], int(cand["index"]),
				String(cand.get("slot_label", ""))))
		else:
			reward_grid.add_child(hud._make_post_growth_card(cand))
	visible = true


# ---------------------------------------------------------------------------
# Step 7：同层三选一
# ---------------------------------------------------------------------------

# 战利品阶段：标题写明来源与品质；三项同层，卡面不出现品质高下提示。
func show_loot_offer(view: Dictionary) -> void:
	_mode = "loot"
	reward_grid.columns = 3
	var growth := bool(view.get("growth_only", false))
	title_label.text = "%s · %s%s" % [
		String(view.get("source_label", "战利品")), String(view.get("quality_name", "")),
		"成长" if growth else "战利品"]
	sub_label.text = "成长三选一：强化当前 Build；装备主要来自探索、商店与BOSS" if growth \
		else "同层三选一：三项品质相同，按用途与当前 Build 选择"
	_refresh_loot_actions(view)
	_fill_loot_options(view)
	visible = true


# 重抽：只换同层候选，品质不变；按钮展示下一次费用，金币不足时禁用。
func refresh_loot_offer(view: Dictionary) -> void:
	if _mode != "loot":
		return
	_refresh_loot_actions(view)
	_fill_loot_options(view)


func _refresh_loot_actions(view: Dictionary) -> void:
	if _reroll_btn != null:
		var cost := int(view.get("reroll_cost", 5))
		_reroll_btn.visible = true
		_reroll_btn.text = "重抽 · %d金" % cost
		_reroll_btn.disabled = controller.gold < cost
		_reroll_btn.tooltip_text = "支付 %d 金币，更换同层候选；不会提高品质" % cost
	if _skip_btn != null:
		_skip_btn.text = "跳过 · 免费"


func _fill_loot_options(view: Dictionary) -> void:
	_clear_grid()
	var opts: Array = view.get("options", [])
	for i in range(opts.size()):
		reward_grid.add_child(hud._make_loot_offer_card(opts[i], i))


# 成长阶段：只有真实触发（技艺 / 铭印）时才展示；没有则不进入本阶段。
func show_loot_growth(cand: Dictionary, summary: String) -> void:
	_mode = "growth"
	_clear_grid()
	reward_grid.columns = 1
	var kind := String(cand.get("kind", ""))
	title_label.text = "成长 · %s" % ("技艺" if kind == "perk" else "铭印")
	sub_label.text = summary
	if _reroll_btn != null:
		_reroll_btn.visible = false
	if _skip_btn != null:
		_skip_btn.text = "保留到下次战斗"
	reward_grid.add_child(hud._make_post_growth_card(cand))
	visible = true


func hide_screen() -> void:
	visible = false
	_mode = ""


func _clear_grid() -> void:
	for c in reward_grid.get_children():
		reward_grid.remove_child(c)
		c.queue_free()
