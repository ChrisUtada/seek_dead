extends Node

# M-02b 第2步：章节头 UI 屏验收（暂不插入正式流程）。
# 验证：一屏两层内容、只用 ChapterInfo 数据、机制文案=mechanic_summary、
# 点击/按键关闭、每幕一次幂等、不发奖/不改构筑/不消耗 RNG、可快速跳过。
# 隔离 APPDATA 运行。

const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const INTRO_SCENE := "res://scenes/ui/chapter_intro.tscn"
const ChapterInfo = preload("res://scripts/systems/chapter_info.gd")

var _checks := 0
var _fails := 0
var _duel = null
var _intro = null

func _ready() -> void:
	await _run()
	print("M02BUI|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("M02BUI|FAIL|" + msg)

func _run() -> void:
	var scene: PackedScene = load(DUEL_SCENE)
	_duel = scene.instantiate()
	add_child(_duel)
	for i in 2:
		await get_tree().process_frame
	_duel.demo_config.enabled = false
	_duel.demo_config.act_only = false
	_duel._confirm_loadout()   # 构建本局 ROOMS
	for i in 2:
		await get_tree().process_frame
	var rooms: Array = _duel.ROOMS
	var d1: Dictionary = ChapterInfo.for_run(rooms, 1)

	# 状态基线（验收不改状态/不发奖/不耗 RNG）
	var gold0 := int(_duel.gold)
	var hp0 := int(_duel.player_hp)
	var loadout0 := str(_duel.selected_loadout)
	var charms0 := str(_duel.selected_charms)
	var perk0 := str(_duel.growth.perk_ids)
	var rng0 := int(_duel._reward_system._loot.seed_value())

	# 实例化 UI
	var isc: PackedScene = load(INTRO_SCENE)
	_intro = isc.instantiate()
	add_child(_intro)
	await get_tree().process_frame
	_check(not _intro.visible, "章节头初始隐藏")

	var shown: bool = _intro.show_for_run(d1)
	_check(shown, "首次 show_for_run(ACT1) 显示")
	_check(_intro.visible, "章节头显示后可见")

	# 内容两层：章节层 + Boss 层
	var chapter_text := String(_intro.chapter_label.text)
	_check(chapter_text == "— ACT I · 章节 —", "章节层幕名精确为 ACT I（实测 %s）" % chapter_text)
	_check(String(_intro.ambience_label.text) != "", "章节层含氛围描述")
	_check(String(_intro.flow_label.text).contains("→"), "章节层含本幕流程摘要")

	# Boss 层文本：名称/元素/弱抗/机制（从 boss_info 聚合）
	var boss_text := ""
	if _intro.boss_info != null:
		for c in _intro.boss_info.get_children():
			if c is Label:
				boss_text += String(c.text) + "\n"
	_check(boss_text.contains(String(d1["boss_name"])), "Boss 层含名称")
	_check(boss_text.contains(String(d1["boss_element_label"])), "Boss 层含元素")
	_check(boss_text.contains("核心机制"), "Boss 层含核心机制标题")
	var mech := String(d1["mechanic_summary"])
	_check(boss_text.contains(mech.substr(0, mini(8, mech.length()))), "Boss 层机制文案来自 mechanic_summary")
	# 不含答案性措辞
	for w in ["推荐", "建议", "应该带", "准备方向", "带什么", "攻略"]:
		_check(not boss_text.contains(w), "UI 文案无答案性措辞：%s" % w)

	# 一屏布局：Dialog 在屏内、按钮可见
	var dlg = _intro.get_node("Center/Dialog")
	_check(dlg != null, "存在 Dialog 面板")
	_check(_intro.continue_btn != null and _intro.continue_btn.visible, "继续按钮可见")

	# 点击关闭 + 信号
	var emitted: Array = []
	_intro.continue_requested.connect(func(a): emitted.append(a))
	_intro.continue_btn.pressed.emit()
	_check(not _intro.visible, "点击继续后关闭")
	_check(emitted.size() == 1 and int(emitted[0]) == 1, "关闭发一次 continue_requested(act=1)")

	# 每幕一次幂等：再次 show_for_run 同幕应返回 false
	var again: bool = _intro.show_for_run(d1)
	_check(not again, "同幕重复 show_for_run 被幂等守卫视掉")
	# 换一幕可显示
	var d2: Dictionary = ChapterInfo.for_run(rooms, 2)
	_check(_intro.show_for_run(d2), "换幕 ACT2 可显示")
	_check(String(_intro.chapter_label.text) == "— ACT II · 章节 —", "ACT2 幕名精确（实测 %s）" % String(_intro.chapter_label.text))
	_intro.hide()

	# 空机制文案：界面不显示"核心机制"（防回归）
	var d_empty: Dictionary = ChapterInfo.for_run(rooms, 3).duplicate(true)
	d_empty["mechanic_summary"] = ""
	_check(_intro.show_for_run(d_empty), "空机制数据可显示（ACT3）")
	var empty_boss_text := ""
	if _intro.boss_info != null:
		for c in _intro.boss_info.get_children():
			if c is Label:
				empty_boss_text += String(c.text) + "\n"
	_check(not empty_boss_text.contains("核心机制"), "空机制时不显示核心机制标题")
	_intro.hide()

	# 按键快速跳过：任意键关闭
	_intro.reset_shown()
	_intro.show_for_run(d1)
	_check(_intro.visible, "reset 后可再次显示（测试用）")
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = KEY_SPACE
	_intro._unhandled_input(ev)
	_check(not _intro.visible, "按键快速跳过关闭")

	# 不发奖/不改状态/不耗 RNG
	_check(int(_duel.gold) == gold0, "章节头不改金币")
	_check(int(_duel.player_hp) == hp0, "章节头不改 HP")
	_check(str(_duel.selected_loadout) == loadout0 and str(_duel.selected_charms) == charms0, "章节头不改构筑")
	_check(str(_duel.growth.perk_ids) == perk0, "章节头不改技艺/成长")
	_check(int(_duel._reward_system._loot.seed_value()) == rng0, "章节头不消耗战利品 RNG")

	_intro.queue_free()
	_duel.queue_free()
	await get_tree().process_frame
