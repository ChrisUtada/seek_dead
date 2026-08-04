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
	title_label.text = "★ 通关一局！选择一项元进度升级（持久生效）"
	title_label.add_theme_font_size_override("font_size", TypeScale.OVERLAY)
	title_label.add_theme_color_override("font_color", Palette.TITLE)
	sub_label.text = "武器基础伤害 / 命中率 线性成长 × 护符伤害乘区增值——下一局起爆炸"
	sub_label.add_theme_font_size_override("font_size", TypeScale.META)
	sub_label.add_theme_color_override("font_color", Palette.MUTED)

func show_choice() -> void:
	for c in meta_grid.get_children():
		meta_grid.remove_child(c)
		c.queue_free()
	var choices = controller._roll_meta_choices()
	for opt in choices:
		meta_grid.add_child(hud._make_meta_card(opt))
	visible = true

func hide_screen() -> void:
	visible = false
