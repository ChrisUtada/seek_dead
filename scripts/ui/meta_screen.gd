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
	_clear_grid()
	# G6-02：有定向解锁机会时先展示「未拥有装备三选一」，选完再进入原有元进度结算。
	if controller._career != null and controller._career.has_unlock_charge():
		var cands: Array = controller._career.roll_unlock_candidates(3)
		if not cands.is_empty():
			_show_unlock(cands)
			visible = true
			return
	_show_meta()


func _clear_grid() -> void:
	for c in meta_grid.get_children():
		meta_grid.remove_child(c)
		c.queue_free()


func _show_unlock(cands: Array) -> void:
	title_label.text = "★ 生涯解锁 · 未拥有装备三选一"
	sub_label.text = "选择一件，直接写入图鉴与开局拥有池。\n本次机会来自生涯成就，不是额外货币。"
	for cand in cands:
		meta_grid.add_child(hud._make_unlock_card(cand))


func _show_meta() -> void:
	var choices = controller._reward_system.roll_meta_choices()
	# M1-05：单结果直接以「本局获得」呈现；未来 GAME+ 多候选上线时自动回到选择语义。
	# 2026-10-31（P0.5）：ACT1 试玩包把「一局结束」写成试玩收束口径——本局结算后回整备，
	# 告诉试玩者接下来能做什么（铁砧 / 图鉴 / 换配装）以及怎么反馈。
	if controller.demo_active():
		title_label.text = "★ ACT1 试玩结束"
		sub_label.text = "感谢试玩！本局获得已结算并跨局保留。\n确认后回整备：可用铁砧点数、看图鉴、换配装再开一局。"
	elif choices.size() <= 1:
		title_label.text = "★ 一局结束 · 本局获得"
		sub_label.text = "以下奖励已直接结算（跨局保留）"
	else:
		title_label.text = "★ 一局结束 · 选择一项元进度"
		sub_label.text = "以下选项持久生效，下一局起可用。"
	# G6-01：局末给出生涯反馈；G6-03：路线 / 成长 / 新收藏 / 下一局建议（均为只读摘要）。
	if controller._career != null:
		var new_ids: Array = controller._career.take_new_unlocks()
		if not new_ids.is_empty():
			var names: Array[String] = []
			for id in new_ids:
				names.append(controller._career.title_of(String(id)))
			sub_label.text += "\n🏅 本局生涯：" + "、".join(names)
	if controller._run_summary != null:
		for line in controller._run_summary.lines():
			sub_label.text += "\n" + String(line)
	for opt in choices:
		meta_grid.add_child(hud._make_meta_card(opt))
	visible = true

func hide_screen() -> void:
	visible = false
