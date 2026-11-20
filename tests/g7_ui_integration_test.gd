extends Node

# ============================================================================
# G7-3/4 UI 接入验证（2026-11-20）
# G7-3：anvil_screen 定向解锁区块（额度/候选/领取按钮）
# G7-4：整备页 tooltip 含统一机器摘要
# ============================================================================

var _fails := 0
var _checks := 0


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("G7 UI FAIL: " + label)


func _ready() -> void:
	await get_tree().process_frame
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame

	# ① G7-3：anvil_screen 定向解锁区块已动态构建
	var anvil = duel.hud.anvil_screen
	_ok(anvil != null, "anvil_screen 存在")
	anvil.show_screen()
	await get_tree().process_frame
	var box: Node = anvil.get_node_or_null("Margin/Content/DirectedBox")
	_ok(box != null, "DirectedBox 已动态创建")
	if box != null:
		# 动态节点的实际名字：第一个 Label / 第二个 VBox
		var labels: Array = []
		for c in box.get_children():
			if c is Label:
				labels.append(c)
		_ok(labels.size() >= 1, "额度标签存在")
		if labels.size() > 0:
			_ok(String(labels[0].text).contains("定向额度"), "额度文案正确（%s）" % String(labels[0].text))

	# ② 有额度时候选按钮可领取
	duel._anvil_system.earn_directed_unlock("test")
	anvil.refresh()
	await get_tree().process_frame
	var list: Node = box.get_child(1) if box.get_child_count() > 1 else null
	var btns: Array = []
	if list != null:
		for c in list.get_children():
			if c is Button:
				btns.append(c)
	_ok(btns.size() > 0, "有额度时候选按钮出现（%d）" % btns.size())
	if btns.size() > 0:
		var before: int = duel._anvil_system.available_directed_unlocks()
		btns[0].pressed.emit()
		_ok(duel._anvil_system.available_directed_unlocks() == before - 1, "点按钮消耗额度")

	# ③ G7-4：整备页 tooltip 含机器摘要
	duel.hud._refresh_meta()
	var tip: String = String(duel.hud.player_level_label.tooltip_text)
	_ok(tip.contains("机器摘要"), "整备 tooltip 含机器摘要（%s...）" % tip.substr(0, 40))

	print("G7 UI INTEGRATION RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
