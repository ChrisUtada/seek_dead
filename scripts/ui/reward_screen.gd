extends Control
class_name RewardScreen

# reward_screen — 房奖励三选一 / BOSS 战利品三选一覆盖层（P3b-2 抽独立场景）
# 静态骨架由 reward_screen.tscn 提供；本脚本负责显隐 / 填数据 / 跳过信号。
# 卡片构造复用 HUD 的 _make_reward_card / _make_boss_reward_card。

var controller
var hud: BattleHud
const UI_BUTTON = preload("res://scenes/ui/ui_button.tscn")

@onready var dimmer = $Dimmer
@onready var title_label = $Center/Dialog/Margin/Content/TitleLabel
@onready var sub_label = $Center/Dialog/Margin/Content/SubLabel
@onready var reward_grid = $Center/Dialog/Margin/Content/Scroll/RewardGrid
@onready var bot = $Center/Dialog/Margin/Content/Bot

func configure(ctrl, h: BattleHud) -> void:
	controller = ctrl
	hud = h
	dimmer.color = Palette.BG_OVERLAY
	sub_label.text = "选择一项奖励带入后续房间（Roguelike 构筑，跳过则不取）"
	var sp = Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot.add_child(sp)
	var skip_btn = UI_BUTTON.instantiate()
	skip_btn.text = "跳过 ▶"
	skip_btn.custom_minimum_size = Vector2(120, 40)
	skip_btn.pressed.connect(hud.reward_skip_requested.emit)
	bot.add_child(skip_btn)

func show_screen(is_boss: bool) -> void:
	# 奖励候选与 reward_is_boss 由 controller._open_reward_screen 填充（UI 不再直写 controller 字段），
	# 本屏只从只读快照 state 读取渲染数据。
	controller._open_reward_screen(is_boss)
	for c in reward_grid.get_children():
		reward_grid.remove_child(c)
		c.queue_free()
	var choices = controller.state.reward_choices
	var kind = controller.state.ROOMS[controller.state.room_index].kind
	if is_boss:
		title_label.text = "★ BOSS 战利品！选择一项（主题武器 / 强化券 / 信物）"
		for rw in choices:
			reward_grid.add_child(hud._make_boss_reward_card(rw))
	elif kind == "elite":
		title_label.text = "⚔ 精英房 · 战前补给（选择一项备战）"
		for rw in choices:
			reward_grid.add_child(hud._make_reward_card(rw))
	else:
		title_label.text = "胜利！选择一项房奖励"
		for rw in choices:
			reward_grid.add_child(hud._make_reward_card(rw))
	visible = true

func hide_screen() -> void:
	visible = false
