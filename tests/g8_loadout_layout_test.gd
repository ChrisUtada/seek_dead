extends Node

# G8 整备屏排版回归（2026-11-08）。
# 锁住四类曾被破坏的排版条件：
#   1. 物品卡字号 = 10（ui_button.tscn 主题曾把 font_sizes 写成 fonts，退化到默认 16）；
#   2. 物品卡文本不裁切（武器数值行 182px / 技能描述最长 591px，卡内宽仅 178px）；
#   3. 底部栏不超出 480 宽且左右留边；
#   4. 换类目后副屏列表回到顶部；悬停信息窗可生成。
# 运行：Godot_v4.7-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/g8_loadout_layout_test.tscn
# 会实例化 duel（可能写存档）：建议用隔离 APPDATA 运行（run_smoke.bat 已统一隔离）。

const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const CATS := ["weapon", "skill", "active", "passive"]
const SCREEN_W := 480.0
const SCREEN_H := 270.0

var _pass := 0
var _fail := 0


func _ready() -> void:
	await _run()


func _run() -> void:
	get_window().size = Vector2i(int(SCREEN_W), int(SCREEN_H))
	await _frames(2)

	var duel: DuelController = load(DUEL_SCENE).instantiate() as DuelController
	duel.demo_config.enabled = true
	add_child(duel)
	await _frames(8)

	var lo: LoadoutScene = duel.hud.loadout_screen
	_check(lo != null, "整备场景已创建")
	if lo == null:
		_finish()
		return
	_check(lo.ui_root.size.x <= SCREEN_W + 0.5 and lo.ui_root.size.y <= SCREEN_H + 0.5, "整备 UI 不超出逻辑分辨率")

	for cat in CATS:
		lo._open_sub(cat)
		await _frames(4)
		_check(lo.loadout_cards.size() > 0, "%s 类目有卡片" % cat)
		for i in range(lo.loadout_cards.size()):
			var btn: Button = lo.loadout_cards[i]["btn"]
			if not is_instance_valid(btn):
				continue
			var fs: int = btn.get_theme_font_size("font_size")
			if i == 0:
				_check(fs == 10, "%s 卡字号=10（实际 %d）" % [cat, fs])
			_check(btn.autowrap_mode != TextServer.AUTOWRAP_OFF, "%s 卡 %d 已开启自动换行" % [cat, i])
			_check(btn.clip_text == false, "%s 卡 %d 不裁切" % [cat, i])
			var sb: StyleBox = btn.get_theme_stylebox("normal")
			var icon_w := 0.0
			if btn.icon != null:
				icon_w = btn.icon.get_width() + btn.get_theme_constant("h_separation")
			var avail: float = btn.size.x - sb.content_margin_left - sb.content_margin_right - icon_w
			var font: Font = btn.get_theme_font("font")
			var wrapped: Vector2 = font.get_multiline_string_size(
				btn.text, HORIZONTAL_ALIGNMENT_CENTER, avail, fs)
			var need_h: float = wrapped.y + sb.content_margin_top + sb.content_margin_bottom
			_check(need_h <= btn.size.y + 0.5,
				"%s 卡 %d 高度够（need %.1f / h %.1f）" % [cat, i, need_h, btn.size.y])
			_check(wrapped.x <= avail + 0.5,
				"%s 卡 %d 宽度够（need %.1f / avail %.1f）" % [cat, i, wrapped.x, avail])
			if i == 0:
				var tip: Control = btn._make_custom_tooltip(btn.tooltip_text)
				_check(tip is RichTextLabel, "%s 卡悬停信息窗可生成" % cat)
				if tip != null:
					tip.free()

	# 换类目回顶：技能滚到底 → 切武器
	lo._open_sub("skill")
	await _frames(4)
	lo.sub_scroll.scroll_vertical = 10000
	await _frames(3)
	var scrolled: int = lo.sub_scroll.scroll_vertical
	lo._open_sub("weapon")
	await _frames(4)
	_check(scrolled > 0, "技能列表可滚动（%d）" % scrolled)
	_check(lo.sub_scroll.scroll_vertical == 0, "换类目后列表回到顶部")

	# 底部栏：不越出 480、左右留边、子项不越界
	var bar: HBoxContainer = lo.count_label.get_parent()
	_check(bar.position.x >= 5.0, "底部栏左边距 ≥5（%.1f）" % bar.position.x)
	_check(bar.position.x + bar.size.x <= SCREEN_W - 5.0, "底部栏右边距 ≥5")
	var right: float = 0.0
	for c in bar.get_children():
		var ctl := c as Control
		if ctl != null:
			right = maxf(right, ctl.position.x + ctl.size.x)
	_check(right <= bar.size.x + 0.5, "底部栏子项不越界（%.1f / %.1f）" % [right, bar.size.x])

	# Step 7：整备底栏直接进入 4×4 扫雷棋盘（与旧棋盘按钮并列）。
	var cfg = duel.board_config
	cfg.enabled = false
	cfg.layout_mode = "legacy"
	lo._refresh_board_toggle()
	_check(lo._board_btn != null and lo._grid_btn != null, "整备底栏有旧棋盘 / 扫雷两个入口")
	lo._toggle_grid_mode()
	_check(cfg.is_active() and cfg.use_grid(), "扫雷入口开启 4×4 棋盘")
	_check(String(lo._grid_btn.text).contains("扫雷✓"), "扫雷入口显示开启态")
	lo._toggle_grid_mode()
	_check(not cfg.is_active(), "再点扫雷入口回到线性")
	lo._toggle_board_mode()
	_check(cfg.is_active() and not cfg.use_grid(), "旧棋盘入口仍进入 1D3 棋盘")
	lo._toggle_board_mode()
	_check(not cfg.is_active(), "再点旧棋盘入口回到线性")

	# 三个叠层：内容不超出屏幕，且超长时可用滚动查看
	lo._preview_panel.visible = true
	lo._refresh_preview()
	await _frames(4)
	_check_overlay("转轮带预览", lo._preview_box)
	lo._preview_panel.visible = false

	lo._toggle_career()
	await _frames(4)
	_check_overlay("生涯成就", lo._career_box)
	lo._toggle_career()

	lo._toggle_forge()
	await _frames(4)
	_check_overlay("铸式", lo._forge_box)
	lo._toggle_forge()

	_finish()


func _check_overlay(what: String, box: Control) -> void:
	var scroll := box.get_parent() as ScrollContainer
	_check(scroll != null, "%s 内容在滚动容器内" % what)
	if scroll == null:
		return
	var min_size: Vector2 = box.get_combined_minimum_size()
	_check(scroll.size.x <= SCREEN_W and scroll.size.y <= SCREEN_H, "%s 不超出逻辑分辨率" % what)
	var scrollable: bool = scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED
	_check(min_size.y <= scroll.size.y + 0.5 or scrollable, "%s 内容可见（可滚动）" % what)
	_check(min_size.x <= scroll.size.x + 0.5, "%s 横向不溢出" % what)


func _finish() -> void:
	print("G8_LAYOUT|RESULT %s (%d/%d)" % ["PASS" if _fail == 0 else "FAIL", _pass, _pass + _fail])
	get_tree().quit(0 if _fail == 0 else 1)


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + what)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
