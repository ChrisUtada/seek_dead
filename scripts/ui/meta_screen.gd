extends Control
class_name MetaScreen

# S5-4：返回整备信号（原 anvil_back_requested 归一到 meta_screen）
signal back_to_loadout_requested

# meta_screen — 元进度 / 生涯定向解锁 / 图鉴 的统一覆盖层（S5-2 入口归一）
# 静态骨架由 meta_screen.tscn 提供；本脚本负责显隐 / 填数据 / 发信号。
# S5-2：定向候选/余额/claim/技能全部读 CareerSystem；图鉴用独立 CodexPanel（不依赖摇奖节点）。

var controller          # DuelController
var hud: BattleHud      # 用于调用共享卡片构造器与信号转发
var codex_panel: CodexPanel = null
var _back_btn: Button = null     # 整备模式返回
# S5-5：确定性候选队列分页——全量候选都可翻页看到，不必先领掉前面若干件。
var _page := 0
var _pager: HBoxContainer = null
var _page_label: Label = null
var _all_cands: Array = []

@onready var bg = $Bg
@onready var title_label = $Margin/Content/TitleLabel
@onready var sub_label = $Margin/Content/SubLabel
@onready var meta_grid = $Margin/Content/Center/MetaGrid

var _claiming := false   # S5-2：连续点击防护（claim 期间不再接受第二次）

func configure(ctrl, h: BattleHud) -> void:
	controller = ctrl
	hud = h
	bg.color = Palette.BG_REWARD
	# S5-2：图鉴组件挂到 Content（不是 roll_btn 父节点），自带按钮，读 controller._codex
	codex_panel = CodexPanel.new()
	codex_panel.name = "CodexPanel"
	add_child(codex_panel)
	codex_panel.configure(ctrl, $Margin/Content)
	$Margin/Content.move_child(codex_panel.get_button(), 0)  # 图鉴按钮置顶
	# S5-3：临时摇奖兼容入口已移除（不再显示"可继续摇奖"假入口）
	_back_btn = Button.new()
	_back_btn.text = "← 返回整备"
	_back_btn.add_theme_font_size_override("font_size", 9)
	_back_btn.pressed.connect(func(): back_to_loadout_requested.emit())
	$Margin/Content.add_child(_back_btn)
	# S5-5：分页控件（上一页/页码/下一页），翻页不消耗额度
	_pager = HBoxContainer.new()
	_pager.add_theme_constant_override("separation", 6)
	var prev := Button.new()
	prev.text = "◀ 上一页"
	prev.add_theme_font_size_override("font_size", 9)
	prev.pressed.connect(_prev_page)
	_page_label = Label.new()
	_page_label.add_theme_font_size_override("font_size", 9)
	var next := Button.new()
	next.text = "下一页 ▶"
	next.add_theme_font_size_override("font_size", 9)
	next.pressed.connect(_next_page)
	_pager.add_child(prev)
	_pager.add_child(_page_label)
	_pager.add_child(next)
	$Margin/Content.add_child(_pager)
	_pager.visible = false
	title_label.text = "★ 一局结束 · 元进度结算"
	# S5-3：铁砧点数已停用，不再显示点数相关文案
	sub_label.text = "本局已结算；定向解锁与图鉴可继续在生涯界面查看。"

# 局末入口：有定向余额先展示生涯三选一，否则进入元进度结算。
func show_choice() -> void:
	_clear_grid()
	_claiming = false
	_page = 0
	if _back_btn != null: _back_btn.visible = false
	if controller._career != null and controller._career.available_directed() > 0:
		var cands: Array = controller._career.directed_candidates()
		if not cands.is_empty():
			_show_unlock(cands)
			visible = true
			return
	_show_meta()

# S5-2 整备页入口：生涯 / 图鉴 / 定向解锁（不进入元进度结算语义）。
func show_career() -> void:
	_clear_grid()
	_claiming = false
	if _back_btn != null: _back_btn.visible = true
	title_label.text = "★ 生涯 · 定向解锁与图鉴"
	var bal: int = controller._career.available_directed() if controller._career != null else 0
	if bal <= 0:
		sub_label.text = "当前没有定向解锁机会。\n可通过生涯成就、武器里程碑或收藏里程碑获得。"
		visible = true
		return
	var cands: Array = controller._career.directed_candidates()
	if cands.is_empty():
		sub_label.text = "当前余额 %d 次，但全部候选已拥有（空池）。" % bal
		if _pager != null: _pager.visible = false
		visible = true
		return
	_page = 0
	_show_unlock(cands)
	sub_label.text = "余额 %d 次 · 可翻页浏览全部候选，选择一件写入拥有池（含技艺）。" % bal
	visible = true

func _clear_grid() -> void:
	for c in meta_grid.get_children():
		meta_grid.remove_child(c)
		c.queue_free()

func _show_unlock(cands: Array) -> void:
	# S5-5：保存全量候选，按页展示；翻页不消耗额度，任何目标都可直接翻到。
	_all_cands = cands
	title_label.text = "★ 生涯解锁 · 未拥有装备（可翻页）"
	if sub_label.text.is_empty() or not sub_label.text.contains("余额"):
		sub_label.text = "选择一件，直接写入图鉴与开局拥有池。\n可翻页浏览全部候选，不限前三项。"
	_show_page()

func _show_page() -> void:
	_clear_grid()
	if _all_cands.is_empty():
		if _pager != null: _pager.visible = false
		return
	var pages: int = ceili(float(_all_cands.size()) / 3.0)
	_page = clampi(_page, 0, pages - 1)
	var start: int = _page * 3
	var end: int = mini(start + 3, _all_cands.size())
	for i in range(start, end):
		meta_grid.add_child(hud._make_unlock_card(_all_cands[i]))
	if _pager != null:
		_pager.visible = pages > 1
		if _page_label != null:
			_page_label.text = "第 %d/%d 页 · 共 %d 件" % [_page + 1, pages, _all_cands.size()]

func _prev_page() -> void:
	_page -= 1
	_show_page()

func _next_page() -> void:
	_page += 1
	_show_page()

func _show_meta() -> void:
	var choices = controller._reward_system.roll_meta_choices()
	if controller.demo_active():
		title_label.text = "★ ACT1 试玩结束"
		sub_label.text = "感谢试玩！本局获得已结算并跨局保留。\n确认后回整备：看生涯图鉴、换配装再开一局。"
	elif choices.size() <= 1:
		title_label.text = "★ 一局结束 · 本局获得"
		sub_label.text = "以下奖励已直接结算（跨局保留）"
	else:
		title_label.text = "★ 一局结束 · 选择一项元进度"
		sub_label.text = "以下选项持久生效，下一局起可用。"
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
	if choices.is_empty():
		# S5-3：局末不再有铁砧点候选，给出明确空状态，不空屏
		sub_label.text += "\n本局元进度已结算完毕，无需额外选择。"
	else:
		for opt in choices:
			meta_grid.add_child(hud._make_meta_card(opt))
	visible = true

# S5-2：claim 成功后由 controller 回调，统一刷新（不重复扣额）。
func on_claim_resolved(success: bool) -> void:
	_claiming = false
	if success:
		# 刷新当前视图；局末模式继续走 show_choice，整备生涯模式走 show_career
		if title_label.text.contains("生涯 · 定向"):
			show_career()
		else:
			show_choice()

func is_claiming() -> bool:
	return _claiming

func begin_claim() -> bool:
	if _claiming: return false
	_claiming = true
	return true

func show_codex() -> void:
	if codex_panel != null:
		codex_panel.open()

func hide_codex() -> void:
	if codex_panel != null:
		codex_panel.close()

func hide_screen() -> void:
	_claiming = false
	hide_codex()
	visible = false
