extends Node

# ============================================================================
# M0-01 基线采集工具（2026-10-29）
# 运行：Godot_v4.7-stable_win64_console.exe --path <项目> res://tools/baseline_capture.tscn
#     必须窗口模式（不要 --headless）——headless 无帧缓冲，截图为空。
# 产物：docs/baseline/2026-10-29/{01..06}_*.png + baseline_data.txt
# 原则：只读现有界面与数据，不改战斗逻辑、不删旧素材、不消耗额外随机流程
#      （商店货架 / 奖励候选 / 元进度候选均为截图临时生成，不写存档）。
# ============================================================================

const OUT_DIR := "res://docs/baseline/2026-10-29"
const DUEL_SCENE := "res://scenes/duel/duel.tscn"

var _duel: DuelController
var _lines: Array[String] = []


func _ready() -> void:
	await _run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_lines.append("# Seek Dead · M0-01 当前基线数据")
	_lines.append("# 采集时间：%s" % Time.get_datetime_string_from_system())
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

	# 01 整备：启动即整备屏（软默认配装）
	_dump_loadout("整备（启动时软默认）")
	await _shot("01_loadout")

	# 02 战斗：确认开战 → 首房
	_duel._confirm_loadout()
	await _wait(0.9)
	_dump_run()
	await _shot("02_battle")

	# 03 商店：临时滚货架（不购买、不清房）
	_duel._shop_system.roll_shop()
	_duel.hud._show_shop_screen()
	await _wait(0.55)
	await _shot("03_shop")
	_duel.hud.hide_shop_screen()
	await _wait(0.2)

	# 04 奖励：普通房三选一候选（临时生成）
	_duel.hud._show_reward_screen(false)
	await _wait(0.45)
	await _shot("04_reward")
	_duel.hud.hide_reward_screen()
	await _wait(0.2)

	# 05 铁砧
	_duel.hud._show_anvil_screen()
	await _wait(0.45)
	await _shot("05_anvil")
	_duel.hud.hide_anvil_screen()
	await _wait(0.2)

	# 06 元进度/结算
	_duel.hud._show_meta_choice()
	await _wait(0.45)
	await _shot("06_meta")
	_duel.hud.hide_meta_screen()

	_write_log()
	print("BASELINE|DONE")
	get_tree().quit(0)


# ---------------------------------------------------------------------------
# 数据记录
# ---------------------------------------------------------------------------
func _dump_loadout(label: String) -> void:
	_lines.append("## %s" % label)
	_lines.append("武器：%s" % _names(_duel.selected_loadout, "weapon_name"))
	_lines.append("技能：%s" % _names(_duel.selected_skills, "skill_name"))
	_lines.append("护符：%s" % _names(_duel.selected_charms, "item_name"))
	_lines.append("消耗品：%s" % _names(_duel.selected_consumables, "item_name"))
	_lines.append("金币=%d  HP=%d/%d" % [_duel.gold, _duel.player_hp, _duel.player_hp_max])
	_lines.append("")


func _dump_run() -> void:
	_lines.append("## 本局构建（确认开战后）")
	_lines.append("ACT1 配装（实际入池）：%s" % _names(_duel.selected_loadout, "weapon_name"))
	_lines.append("")
	_lines.append("### 房间顺序（_build_run 产物）")
	for i in range(_duel.ROOMS.size()):
		var r: RoomData = _duel.ROOMS[i]
		_lines.append("R%02d act%d %-6s %-10s elem=%-6s hp=%-4d atk=%-3d armor=%-2d boss_role=%-8s final=%s" % [
			i + 1, r.act, r.kind, r.name, r.element, r.hp, r.atk, r.armor, r.boss_role, str(r.final_boss)])
	_lines.append("")
	_lines.append("### ACT1 符号带（默认双武器构建后）")
	for r in range(_duel.reel_system.reel_strips.size()):
		var strip: Array = _duel.reel_system.reel_strips[r]
		var counts := {}
		for pair in strip:
			var sym: SymbolData = pair[0]
			var key := "%s(%s/%s) -> %s" % [sym.label, sym.kind, sym.element, pair[1]]
			counts[key] = int(counts.get(key, 0)) + 1
		var keys: Array = counts.keys()
		keys.sort()
		var parts: Array[String] = []
		for k in keys:
			parts.append("%s×%d" % [k, counts[k]])
		_lines.append("转轮 %d（%d 格）：%s" % [r + 1, strip.size(), "，".join(parts)])
	_lines.append("")
	_lines.append("### 奖励池")
	_dump_rewards("普通房 REWARD_POOL", _duel.REWARD_POOL)
	_dump_rewards("精英 ELITE_REWARD_POOL", _duel.ELITE_REWARD_POOL)
	_lines.append("")
	_lines.append("### BOSS 候选（按幕）")
	for r in _duel.ALL_ROOMS:
		if r.kind == "boss" or r.final_boss:
			_lines.append("act%d %-10s role=%-8s final=%s element=%s" % [
				r.act, r.name, r.boss_role, str(r.final_boss), r.element])
	_lines.append("")
	_lines.append("### 关键平衡值（balance_config 实值）")
	for k in ["player_dmg_mult", "player_hp_base", "ante_act_step_atk", "ante_room_step_atk",
			"ante_act_step_hp", "ante_room_step_hp", "charge_max", "loadout_min", "anvil_roll_cost"]:
		_lines.append("%s = %s" % [k, str(_duel.BALANCE.get(k))])
	_lines.append("")


func _dump_rewards(title: String, pool: Array) -> void:
	_lines.append("%s（%d）：" % [title, pool.size()])
	for rw in pool:
		_lines.append("  %s %s rarity=%s value=%d" % [rw.id, rw.label, rw.rarity, rw.value])


func _names(paths: Array, field: String) -> String:
	if paths.is_empty():
		return "（空）"
	var out: Array[String] = []
	for p in paths:
		var res: Resource = load(p)
		var n := String(res.get(field)) if res != null and res.get(field) != null else String(p)
		out.append("%s [%s]" % [n, String(p).get_file()])
	return "，".join(out)


# ---------------------------------------------------------------------------
# 截图与写盘
# ---------------------------------------------------------------------------
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var err := img.save_png(path)
	_lines.append("截图：%s.png  %dx%d  err=%d" % [name, img.get_width(), img.get_height(), err])


func _write_log() -> void:
	var f := FileAccess.open("%s/baseline_data.txt" % OUT_DIR, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _wait_frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
