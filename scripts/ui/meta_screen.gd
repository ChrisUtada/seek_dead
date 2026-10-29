extends Control
class_name MetaScreen

# meta_screen — 每局结束元进度三选一覆盖层（P3b-2 抽独立场景）
# 静态骨架由 meta_screen.tscn 提供；本脚本负责显隐 / 填数据 / 发信号。
# 卡片构造复用 HUD 的 _make_meta_card（保持信号接线单一来源）。

var controller          # DuelController
var hud: BattleHud      # 用于调用共享卡片构造器与信号转发

@onready var bg = $Bg
@onready var title_label = $Margin/Content/TitleLabel
@onready var sub_label = $Margin/Content/SubLabel
@onready var meta_grid = $Margin/Content/Center/MetaGrid

func configure(ctrl, h: BattleHud) -> void:
	controller = ctrl
	hud = h
	bg.color = Palette.BG_REWARD
	# M1-05：当前元进度只有「铁砧点数」一个真实结果——不再伪装成三选一，也不承诺线性成长。
	title_label.text = "★ 一局结束 · 元进度结算"
	sub_label.text = "铁砧点数用于铁砧抽取装备（跨局保留）；更多元进度候选待 GAME+ 上线后恢复。"

func show_choice() -> void:
	for c in meta_grid.get_children():
		meta_grid.remove_child(c)
		c.queue_free()
	var choices = controller._reward_system.roll_meta_choices()
	# M1-05：单结果直接以「本局获得」呈现；未来 GAME+ 多候选上线时自动回到选择语义。
	if choices.size() <= 1:
		title_label.text = "★ 一局结束 · 本局获得"
		sub_label.text = "以下奖励已直接结算（跨局保留）"
	else:
		title_label.text = "★ 一局结束 · 选择一项元进度"
		sub_label.text = "以下选项持久生效，下一局起可用。"
	for opt in choices:
		meta_grid.add_child(hud._make_meta_card(opt))
	visible = true

func hide_screen() -> void:
	visible = false
