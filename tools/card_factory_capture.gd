extends Node

# ============================================================================
# 卡片重构取证（G8 第二切片，2026-11-08）
# 卡片构造外迁到 scripts/ui/card_factory.gd 后，逐屏截图确认外观未变：
#   整备物品卡 / 商店货架卡 + 卖出卡 / 房奖励卡 / 局末元进度卡 / 战后成长卡
# 运行（必须窗口模式，headless 无帧缓冲）：
#   Godot_v4.7-stable_win64_console.exe --path . res://tools/card_factory_capture.tscn
# 产物：docs/baseline/2026-11-08_cards/{n}_{name}.png + capture_data.txt
# 会实例化 duel（可能写存档）：跑前把 APPDATA 指到临时目录。
# ============================================================================

const OUT_DIR := "res://docs/baseline/2026-11-08_cards"
const DUEL_SCENE := "res://scenes/duel/duel.tscn"

var _duel: DuelController
var _lines: Array[String] = []


func _ready() -> void:
	await _run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_lines.append("# 卡片重构取证 %s" % Time.get_datetime_string_from_system())
	get_window().size = Vector2i(960, 540)
	await _wait_frames(6)
	await _wait(0.35)

	_duel = load(DUEL_SCENE).instantiate() as DuelController
	_duel.demo_config.enabled = true
	add_child(_duel)
	await _wait_frames(6)
	await _wait(0.35)

	# 1) 整备屏物品卡（_make_item_card）
	await _shot("01_loadout_items")

	_duel._confirm_loadout()
	await _wait(0.9)
	_duel._start_room(0)
	await _wait(0.8)

	# 2) 商店货架卡（_make_shop_card）+ 卖出卡（_make_sell_card）
	_duel._shop_system.roll_shop()
	_duel.hud._show_shop_screen()
	await _wait(0.55)
	await _shot("02_shop_cards")
	_duel.hud.hide_shop_screen()
	await _wait(0.2)

	# 3) 房奖励卡（_make_reward_card）
	_duel.hud._show_reward_screen(false)
	await _wait(0.45)
	await _shot("03_reward_cards")
	var rgrid = _duel.hud.reward_screen.reward_grid
	for c in rgrid.get_children():
		rgrid.remove_child(c)
		c.queue_free()
	for rid in ["heal", "shield", "gold"]:
		var rw: RewardData = load("res://resources/rewards/%s.tres" % rid)
		if rw != null:
			rgrid.add_child(_duel.hud._make_reward_card(rw, -1))
	await _wait(0.3)
	await _shot("04_reward_cards_fixed")

	# 4) 战后成长卡（_make_post_growth_card）：控件渲染检查，内容为固定样例
	for c in rgrid.get_children():
		rgrid.remove_child(c)
		c.queue_free()
	rgrid.add_child(_duel.hud._make_post_growth_card({
		"icon": "✦", "slot_label": "成长", "title": "坚韧",
		"desc": "[体魄] 生命上限 +6", "tooltip": "坚韧（体魄）\n生命上限 +6"}))
	await _wait(0.3)
	await _shot("05_post_growth_card")
	_duel.hud.hide_reward_screen()
	await _wait(0.2)

	# 5) 局末元进度卡（_make_meta_card）
	_duel.hud._show_meta_choice()
	await _wait(0.45)
	await _shot("06_meta_cards")
	_duel.hud.hide_meta_screen()
	await _wait(0.2)

	# 6) 生涯解锁卡（_make_unlock_card）：控件渲染检查，内容为固定样例
	if _duel.hud.meta_screen != null:
		_duel.hud._show_meta_choice()
		await _wait(0.3)
		var grid = _duel.hud.meta_screen.meta_grid
		for c in grid.get_children():
			grid.remove_child(c)
			c.queue_free()
		grid.add_child(_duel.hud._make_unlock_card({
			"icon": "🗡️", "name": "霜鸣短刃", "desc": "未拥有 · 命中 92%",
			"tip": "霜鸣短刃\n冰 · 攻 12"}))
		await _wait(0.3)
		await _shot("07_unlock_card")
		_duel.hud.hide_meta_screen()

	var f := FileAccess.open("%s/capture_data.txt" % OUT_DIR, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	print("CARD_CAPTURE|DONE shots=%d" % _lines.size())
	_duel.queue_free()
	await _wait_frames(4)
	get_tree().quit(0)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("%s/%s.png" % [OUT_DIR, name])
	_lines.append("%s  %dx%d  err=%d" % [name, img.get_width(), img.get_height(), err])


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _wait_frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
