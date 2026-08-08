extends Control
class_name TrainScreen

# train_screen — T28 训练房：BOSS 战利品三选一后、进下一房前，当场分配训练点（升级轨道唯一货币）。
# 静态骨架由 train_screen.tscn 提供；本脚本负责显隐 / 填数据 / 发继续信号。
# 卡片构造复用 HUD 的 _make_upgrade_card（与商店同源，信号单一）。

var controller          # DuelController
var hud: BattleHud

@onready var bg = $Bg
@onready var title_label = $Center/Dialog/Margin/Content/TitleLabel
@onready var sub_label = $Center/Dialog/Margin/Content/SubLabel
@onready var train_grid = $Center/Dialog/Margin/Content/TrainGrid
@onready var continue_btn = $Center/Dialog/Margin/Content/Bot/ContinueBtn

func configure(ctrl, h: BattleHud) -> void:
	controller = ctrl
	hud = h
	bg.color = Palette.BG_REWARD
	title_label.text = "⚔ 训练房"
	continue_btn.connect("pressed", hud.train_continue_requested.emit)

func show_screen() -> void:
	sub_label.text = "击败 BOSS 获得训练点——每级消耗 1 点（当前 %d 点）" % controller.train_points
	for c in train_grid.get_children():
		train_grid.remove_child(c)
		c.queue_free()
	for u in controller._gold_upgrade_defs():
		train_grid.add_child(hud._make_upgrade_card(u))
	visible = true

func hide_screen() -> void:
	visible = false
