extends Node

# ============================================================================
# 战斗 UI 重构 · 截图采集工具（Step 0–5 + 纠偏 C0–C6，2026-10-31）
# 运行：Godot_v4.7-stable_win64_console.exe --path <项目> res://tools/ui_capture_step0.tscn
#     必须窗口模式（不要 --headless）——headless 无帧缓冲，截图为空。
# 产物：docs/baseline/2026-10-31_ui/<步骤目录>/{01..18}_*.png + capture_data.txt
#      （OUT_DIR 每次指向当前步骤目录；12–16 为 Step 3/4 加入的演出、奖励图标、角标取证；
#       17/18 为 Step 5 的底部短反馈与信息层级取证）
# 原则：只读现有界面；不修改战斗逻辑；商店货架/奖励候选/元进度候选均为截图临时生成，
#      不购买、不结算、不写存档（万一写入，用 lobby_data 备份还原）。
# 采集面：整备 / 普通房 / BOSS 房（固定替换为样板 BOSS 冰封铁瓮）/ 商店 / 奖励 / 铁砧 /
#      结算 / 转轮滚动中，并覆盖 960×540、1440×810、1920×1080（2×/3×/4× 整数放大）。
# ============================================================================

const OUT_DIR := "res://docs/baseline/2026-10-31_ui/correct2"
const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const SAMPLE_BOSS := "res://resources/rooms/frozen_urn.tres"   # 任务书指定样板 BOSS
# 纠偏 C0/C6：普通房固定为同一只怪，保证纠偏前后截图是同一房间、同一数值
const SAMPLE_NORMAL := "res://resources/rooms/a1_striker_light.tres"

var _duel: DuelController
var _lines: Array[String] = []
var _boss_idx := -1


func _ready() -> void:
	await _run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_lines.append("# Seek Dead · 战斗 UI 重构 Step 0 基线")
	_lines.append("# 采集时间：%s" % Time.get_datetime_string_from_system())
	_lines.append("# 颜色基准：palette.gd / theme/battle_theme.tres 当前值")
	_lines.append("")
	await get_tree().process_frame

	var scene: PackedScene = load(DUEL_SCENE)
	if scene == null:
		push_error("无法加载 duel.tscn")
		get_tree().quit(2)
		return
	_duel = scene.instantiate() as DuelController
	add_child(_duel)
	await _wait_frames(8)
	await _wait(0.3)

	# 纠偏：固定普通房（仅内存替换，不写资源/存档）。注意：_confirm_loadout 会重建 ROOMS，
	# 因此必须在开战之后再替换并重新进入，否则截到的是随机普通房，无法与纠偏前同房对比。
	var normal_sample: RoomData = load(SAMPLE_NORMAL)

	_set_window(Vector2i(960, 540))
	await _wait(0.3)

	# ---- 960×540 ----
	_dump_layout("整备（启动时软默认）")
	await _shot("01_loadout_960")

	_duel._confirm_loadout()
	await _wait(0.9)
	if normal_sample != null and _duel.ROOMS.size() > 0:
		_duel.ROOMS[0] = normal_sample
		_duel._start_room(0)
		await _wait(0.9)
	_dump_battle("普通房 · 刚入场")
	await _shot("02_battle_960")

	# C6：480×270 原生逻辑截图（1:1，不放大）
	_set_window(Vector2i(480, 270))
	await _wait(0.4)
	await _shot("02b_battle_480")
	_set_window(Vector2i(960, 540))
	await _wait(0.4)

	# 样板 BOSS：把本局某个 BOSS 席位替换为固定样板（仅内存，不写资源/存档），
	# 保证改造前后截图是同一只 BOSS、同一幕数。
	_boss_idx = _boss_index()
	if _boss_idx >= 0:
		var sample: RoomData = load(SAMPLE_BOSS)
		if sample != null:
			_duel.ROOMS[_boss_idx] = sample
		_duel._start_room(_boss_idx)
		await _wait(1.1)
		_dump_battle("BOSS 房（样板冰封铁瓮，直跳 idx=%d）" % _boss_idx)
		await _shot("03_boss_960")
		_set_window(Vector2i(480, 270))
		await _wait(0.4)
		await _shot("03b_boss_480")
		_set_window(Vector2i(960, 540))
		await _wait(0.4)

		# Step 3 演出验证：真实调用 BattleAnimator（攻击帧序列 + 暖白受击闪），非摆拍。
		# t≈0.08s：受击闪接近峰值；t≈0.21s：玩家第 4 帧（命中帧）。
		_duel.hud.animator.play_attack("player", "enemy")
		await _wait(0.08)
		await _shot("12_attack_flash_960")
		await _wait(0.13)
		await _shot("13_attack_impact_960")
		await _wait(0.4)

	# 回到普通房，给后续覆盖层一个稳定底图
	_duel._start_room(0)
	await _wait(0.8)

	_duel._shop_system.roll_shop()
	_duel.hud._show_shop_screen()
	await _wait(0.55)
	await _shot("04_shop_960")
	_duel.hud.hide_shop_screen()
	await _wait(0.2)

	_duel.hud._show_reward_screen(false)
	await _wait(0.45)
	await _shot("05_reward_960")
	# Step 4 取证：奖励卡主图。正常 roll 未必同时抽到生命/护盾/金币，
	# 这里用生产构建器 _make_reward_card 重建固定三张（真实 RewardData，非伪造控件）。
	var rgrid = _duel.hud.reward_screen.reward_grid
	for c in rgrid.get_children():
		rgrid.remove_child(c)
		c.queue_free()
	for rid in ["heal", "shield", "gold"]:
		var rw: RewardData = load("res://resources/rewards/%s.tres" % rid)
		if rw != null:
			rgrid.add_child(_duel.hud._make_reward_card(rw, -1))
	await _wait(0.3)
	await _shot("14_reward_icons_960")
	_duel.hud.hide_reward_screen()
	await _wait(0.2)

	_duel.hud._show_anvil_screen()
	await _wait(0.45)
	await _shot("06_anvil_960")
	_duel.hud.hide_anvil_screen()
	await _wait(0.2)

	_duel.hud._show_meta_choice()
	await _wait(0.45)
	await _shot("07_meta_960")
	_duel.hud.hide_meta_screen()
	await _wait(0.2)

	# ---- 1440×810 ----
	_set_window(Vector2i(1440, 810))
	await _wait(0.5)
	_duel._start_room(0)
	await _wait(0.9)
	await _shot("09_battle_1440")
	if _boss_idx >= 0:
		_duel._start_room(_boss_idx)
		await _wait(1.0)
		await _shot("10_boss_1440")

	# ---- 1920×1080 ----
	_set_window(Vector2i(1920, 1080))
	await _wait(0.5)
	_duel._start_room(0)
	await _wait(0.9)
	await _shot("11_battle_1920")

	# ---- 转轮滚动中（放最后：真实 SPIN 不会自动停，需强制收尾，会触发敌回合）----
	# 用高血量样板 BOSS 承载旋转/角标/反馈取证：普通房 100 HP 容易被击杀后无法继续真实旋转。
	_set_window(Vector2i(960, 540))
	await _wait(0.4)
	if _boss_idx >= 0:
		_duel.player_hp = _duel.player_hp_max
		_duel.player_shield = 0
		_duel._start_room(_boss_idx)
		await _wait(0.9)
	_duel._on_spin_button_pressed()
	await _wait(0.18)
	await _shot("08_spin_960")
	_lines.append("旋转中：spinning=%s stopped=%s" % [
		str(_duel.reel_system.spinning), str(_duel.reel_system.reel_stopped)])
	await _wait(1.2)
	await _shot("08b_spin_960")
	# 逐列按停（与玩家操作同一条路径：每列 lock 后立即刷新格子，第三列触发结算）
	for i in 3:
		_duel.reel_system.stop_next_reel()
		await _wait(0.45)
	# Step 4 取证：结算后的静止状态（图标 + 匹配角标同时在场）
	await _wait(1.2)
	await _shot("15_after_spin_960")

	# 角标取证：真实旋转直到出现匹配角标（最多 6 次；无角标则重置房间重试）。
	for attempt in 6:
		if _duel.game_state == _duel.FlowState.WON:
			_duel.hud.hide_reward_screen()
			await _wait(0.15)
		if _any_badge() != "":
			break
		if attempt > 0 and _boss_idx >= 0:
			_duel.player_hp = _duel.player_hp_max
			_duel._start_room(_boss_idx)
			await _wait(0.8)
		_duel._on_spin_button_pressed()
		await _wait(0.5)
		for i in 3:
			_duel.reel_system.stop_next_reel()
			await _wait(0.4)
		await _wait(1.0)
	var badge_text := _any_badge()
	_lines.append("匹配角标：%s" % ("无" if badge_text == "" else badge_text))
	if badge_text != "":
		await _shot("16_badges_960")
	else:
		# 未取到角标：删除旧截图，避免目录里留下与本次运行不一致的陈旧证据
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/16_badges_960.png" % OUT_DIR))

	# ---- Step 5 取证：底部短反馈（最近一次真实结算，非摆拍）----
	# 继续真实旋转直到结算产生反馈（最多 3 次）。若击杀，仅隐藏奖励覆盖层取画面，不选奖励、不结算。
	for attempt in 6:
		if _duel.game_state == _duel.FlowState.WON:
			_duel.hud.hide_reward_screen()
			await _wait(0.15)
		if str(_duel.hud.feedback_label.text) != "":
			break
		if attempt > 0 and _boss_idx >= 0:
			_duel.player_hp = _duel.player_hp_max
			_duel._start_room(_boss_idx)
			await _wait(0.8)
		_duel._on_spin_button_pressed()
		await _wait(0.5)
		for i in 3:
			_duel.reel_system.stop_next_reel()
			await _wait(0.4)
		await _wait(0.9)
	var fb_txt: String = str(_duel.hud.feedback_label.text)
	_lines.append("底部反馈：%s" % ("（空）" if fb_txt == "" else fb_txt))
	if fb_txt != "":
		await _shot("17_feedback_960")
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/17_feedback_960.png" % OUT_DIR))

	# ---- Step 5 取证：克制分支（冰封铁瓮弱火；火斩落线即出现「克制×1.5」）----
	if _boss_idx >= 0:
		_duel.player_hp = _duel.player_hp_max
		_duel.player_shield = 0
		_duel._start_room(_boss_idx)
		await _wait(0.9)
		for attempt in 5:
			if str(_duel.hud.feedback_label.text).contains("克制"):
				break
			_duel._on_spin_button_pressed()
			await _wait(0.5)
			for i in 3:
				_duel.reel_system.stop_next_reel()
				await _wait(0.4)
			await _wait(0.9)
			_duel.player_hp = _duel.player_hp_max   # 仅保证取证过程不被击倒；不改任何结算公式
		_lines.append("克制反馈：%s" % str(_duel.hud.feedback_label.text))
		await _shot("19_counter_feedback_960")

	# ---- Step 5 取证：信息层级（低 HP 危险红 / 护盾独立行 / 充能临界金）。
	# 直接写运行态仅为取色，不做结算、不写存档；之后不再截图其他界面。
	_duel.player_hp = max(1, int(_duel.player_hp_max * 0.15))
	_duel.player_shield = 8
	_duel.charge_points = _duel.BALANCE.charge_max - 1
	_duel.hud._refresh_meta()
	await _wait(0.25)
	_lines.append("层级实测：HP 色=%s；护盾行 visible=%s；充能色=%s；意图色=%s" % [
		str(_duel.hud.player_hp_label.get_theme_color("font_color")),
		str(_duel.hud.player_shield_row.visible),
		str(_duel.hud.enemy_charge_label.get_theme_color("font_color")),
		str(_duel.hud.enemy_intent_label.get_theme_color("font_color"))])
	await _shot("18_priority_960")

	# 最严布局工况：护盾行 + 下一房浮层同时显示；浮层不得增加 Content 高度
	_duel.hud.set_interroom_enabled(true)
	await _wait(0.25)
	_dump_battle("间歇浮层 + 护盾行动态布局")
	await _shot("20_interroom_layout_960")
	_duel.hud.set_interroom_enabled(false)

	_write_log()
	print("CAPTURE|DONE")
	get_tree().quit(0)


# ---------------------------------------------------------------------------
# 数据记录
# ---------------------------------------------------------------------------
func _dump_layout(label: String) -> void:
	_lines.append("## %s" % label)
	var vp := get_viewport().get_visible_rect().size
	_lines.append("视口逻辑尺寸 = %d×%d；窗口 = %d×%d" % [
		int(vp.x), int(vp.y), get_window().size.x, get_window().size.y])
	_lines.append("")


func _dump_battle(label: String) -> void:
	var h := _duel.hud
	_lines.append("## %s" % label)
	_lines.append("左栏宽 = %d；右栏宽 = %d" % [
		int(h.player_panel.size.x), int(h.enemy_panel.size.x)])
	_lines.append("转轮格最小尺寸 = %s；实际 = %s" % [
		str(h.cells[0][0].custom_minimum_size), str(h.cells[0][0].size)])
	_lines.append("玩家立绘 = %s（最小尺寸 %s；实际 %s；scale %s）" % [
		h.player_sprite.texture.resource_path if h.player_sprite.texture else "null",
		str(h.player_sprite.custom_minimum_size), str(h.player_sprite.size), str(h.player_sprite.scale)])
	_lines.append("敌人立绘 = %s（最小尺寸 %s；实际 %s；scale %s）" % [
		h.enemy_sprite.texture.resource_path if h.enemy_sprite.texture else "null",
		str(h.enemy_sprite.custom_minimum_size), str(h.enemy_sprite.size), str(h.enemy_sprite.scale)])
	_lines.append("ENEMY_SPRITE_SIZE = %s；当前房 art_scale = %s" % [
		str(h.ENEMY_SPRITE_SIZE), str(_duel.ROOMS[_duel.room_index].art_scale)])
	_lines.append("HP 显示位置：玩家=左栏 / 敌人=右栏；中央重复项已移除")
	_lines.append("右栏 HP/护甲/充能行 visible：%s / %s / %s；机制摘要=%s" % [
		str(h.enemy_hp_label.get_parent().visible),
		str(h.enemy_armor_row.visible),
		str(h.enemy_charge_row.visible),
		str(h.enemy_mechanic_label.text)])
	# C4-3 交叉核对：摘要必须与真实 gimmick_params 一致（不靠肉眼）
	var cur_room: RoomData = _duel.ROOMS[_duel.room_index]
	if cur_room.gimmick_params.has("interval"):
		var iv: int = int(cur_room.gimmick_params["interval"])
		var ps: int = int(cur_room.gimmick_params.get("per_stack", 0))
		var ms: int = int(cur_room.gimmick_params.get("max_stacks", 0))
		var mtxt: String = String(cur_room.mechanic_summary)
		_lines.append("机制一致性：interval=%d 在摘要=%s；per_stack=%d 在摘要=%s；max_stacks=%d 在摘要=%s" % [
			iv, str(mtxt.contains(str(iv))), ps, str(mtxt.contains(str(ps))), ms, str(mtxt.contains(str(ms)))])
	_lines.append("左栏宽 = %d；武器卡数 = %d；技能卡数 = %d；护符卡数 = %d；消耗品格实际 = %s" % [
		int(h.player_panel.size.x), h.weapons_row.get_child_count(),
		h.skills_row.get_child_count(), h.charms_row.get_child_count(),
		str(h.consumable_cells[0].size)])
	_lines.append("卡片实际尺寸：武器0=%s 技能=%s 护符=%s" % [
		str(h.weapons_row.get_child(0).size) if h.weapons_row.get_child_count() > 0 else "无",
		str(h.skills_row.get_child(0).size) if h.skills_row.get_child_count() > 0 else "无",
		str(h.charms_row.get_child(0).size) if h.charms_row.get_child_count() > 0 else "无"])
	_lines.append("布局高度：Content 最小=%s 实际=%s；MainRow=%s；NextRoom 父节点=%s" % [
		str(h.get_node("Margin/Content").get_combined_minimum_size().y),
		str(h.get_node("Margin/Content").size.y),
		str(h.get_node("Margin/Content/MainRow").size.y),
		str(h.next_room_bar.get_parent().name)])
	_lines.append("顶栏：%s | 金币 %s | %s；RunLabel 仍存在=%s" % [
		str(h.room_label.text), str(h.gold_label.text), str(h.turn_label.text),
		str(h.get_node_or_null("Margin/Content/InfoBar/RunLabel") != null)])
	_lines.append("左栏弱信息 tooltip：%s" % str(h.player_buff_label.tooltip_text))
	_lines.append("中央舞台可用宽 = %d；高度 = %d" % [
		int(h.get_node("Margin/Content/MainRow/CenterStage").size.x),
		int(h.get_node("Margin/Content/MainRow/CenterStage").size.y)])
	var rs = _duel.reel_system
	_lines.append("转轮状态：spinning=%s stopped=%s" % [str(rs.spinning), str(rs.reel_stopped)])
	# Step 4：元素色条（图标模式替代文字染色）实测
	var strip_info := []
	for reel in range(_duel.hud.cell_elem_strips.size()):
		var st: ColorRect = _duel.hud.cell_elem_strips[reel][0]
		var el: String = _duel.state.grid_elem[reel][0] if _duel.state.grid_elem.size() > reel else "?"
		strip_info.append("%s elem=%s visible=%s color=%s" % [
			str(_duel.hud.cells[reel][0].icon), el, str(st.visible), str(st.color)])
	_lines.append("元素条：" + " | ".join(strip_info))
	_lines.append("")


func _boss_index() -> int:
	for i in range(_duel.ROOMS.size()):
		if _duel.ROOMS[i].kind == "boss":
			return i
	return -1


# 当前位置上第一个非空匹配角标（"×N"），没有则返回空串
func _any_badge() -> String:
	for reel in range(_duel.hud.cell_badges.size()):
		for row in range(_duel.hud.cell_badges[reel].size()):
			var t := str(_duel.hud.cell_badges[reel][row].text)
			if t != "":
				return t
	return ""


# ---------------------------------------------------------------------------
# 截图与写盘
# ---------------------------------------------------------------------------
func _set_window(target: Vector2i) -> void:
	get_window().size = target


func _shot(name: String) -> void:
	# 截图前收起转轮悬停提示：鼠标恰好停在格子上时，tooltip 会盖住立绘/右侧信息
	if _duel != null and _duel.hud != null and _duel.hud.symbol_tooltip != null:
		_duel.hud.symbol_tooltip.visible = false
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := img.save_png(path)
	_lines.append("截图：%s.png  %dx%d  err=%d" % [name, img.get_width(), img.get_height(), err])


func _write_log() -> void:
	var f := FileAccess.open("%s/capture_data.txt" % OUT_DIR, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _wait_frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
