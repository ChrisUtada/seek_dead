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

	# ① S5-2：定向解锁 UI 已归一到 meta_screen，anvil_screen 降级为纯摇奖兼容层
	var anvil = duel.hud.anvil_screen
	_ok(anvil != null, "anvil_screen 仍存在（兼容摇奖）")
	_ok(anvil.get_node_or_null("Margin/Content/DirectedBox") == null, "anvil_screen 不再有独立定向 UI")
	var ms = duel.hud.meta_screen
	_ok(ms != null and ms.codex_panel != null, "meta_screen 承载图鉴组件")
	duel._career.earn_directed("test")
	ms.show_career()
	await get_tree().process_frame
	var btns: Array = []
	for c in ms.meta_grid.get_children():
		if c is Button: btns.append(c)
	_ok(btns.size() > 0, "meta_screen 有额度时候选按钮出现（%d）" % btns.size())
	var before: int = duel._career.available_directed()
	if btns.size() > 0:
		btns[0].pressed.emit()
		await get_tree().process_frame
		_ok(duel._career.available_directed() == before - 1, "点 meta_screen 按钮消耗额度一次")
		_ok(duel._anvil_system.available_directed_unlocks() == duel._career.available_directed(), "旧 API 与新账本同余额")

	# ③ G7-4：整备页 tooltip 含机器摘要
	duel.hud._refresh_meta()
	var tip: String = String(duel.hud.player_level_label.tooltip_text)
	_ok(tip.contains("机器摘要"), "整备 tooltip 含机器摘要（%s...）" % tip.substr(0, 40))

	print("G7 UI INTEGRATION RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
