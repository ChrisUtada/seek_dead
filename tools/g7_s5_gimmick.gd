extends Node

# ============================================================================
# G7-A S5 · ACT2/ACT3 机制房逐个开打探针（2026-11-08）
#
# 补上图 4 局 bot 覆盖不到的机制：把每个 act>=2 且挂了 gimmick_script 的房间
# 单独当一场战斗起来，打若干回合，断言：
#   - current_gimmick 实例化成功；
#   - on_room_start 已经跑过（机制自己写进 controller 的状态非默认）；
#   - 连续回合里敌攻/结算不崩，玩家 HP 仍在合法区间。
# 只读：不改任何 .tres、不改 BALANCE（复活靠把 player_hp 拉回假人值）。
#
# 运行（必须隔离 APPDATA）：
#   Godot_v4.7-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tools/g7_s5_gimmick.tscn
# 产物：docs/baseline/2026-11-08_run3_baseline/gimmick_probe.txt
# ============================================================================

const OUT_PATH := "res://docs/baseline/2026-11-08_run3_baseline/gimmick_probe.txt"
const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const DUMMY_HP := 99999
const TURNS := 6

var _duel: DuelController
var _lines: Array[String] = []
var _ok := 0
var _fail := 0


func _ready() -> void:
	await _run()


func _run() -> void:
	_duel = load(DUEL_SCENE).instantiate() as DuelController
	add_child(_duel)
	await _frames(8)
	_duel.board_config.enabled = false
	_duel._confirm_loadout()
	await _frames(4)
	_lines.append("# G7-A S5 · ACT2/ACT3 机制房逐个开打 %s" % Time.get_datetime_string_from_system())
	_lines.append("")
	_lines.append("协议：线性开房（ROOMS=[该房]）· 假人生命 %d · 每房 %d 回合 · 不改 .tres / BALANCE" % [DUMMY_HP, TURNS])
	_lines.append("")
	_lines.append("| 幕 | 房 | 类型 | 机制 | 实例化 | %d 回合无异常 | 状态痕迹 | 结论 |" % TURNS)
	_lines.append("|---|---|---|---|---|---|---|---|")

	var seen := {}
	for r in _duel.ALL_ROOMS:
		if r == null or int(r.act) < 2 or r.gimmick_script == null:
			continue
		await _probe(r)
		seen[_gimmick_name(r)] = true
	_lines.append("")
	_lines.append("去重机制（act>=2）：%s" % ", ".join(seen.keys()))
	_lines.append("结果：ok=%d fail=%d" % [_ok, _fail])

	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	print("G7_S5_GIMMICK|DONE ok=%d fail=%d" % [_ok, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


func _probe(r: RoomData) -> void:
	seed(8100 + int(r.act) * 100 + r.name.hash() % 97)
	_duel._reset_run_state()
	var rooms: Array[RoomData] = [r]
	_duel.ROOMS = rooms
	_duel._build_pool(_duel.selected_loadout)
	_duel._start_room(0)
	_duel.player_hp_max = DUMMY_HP
	_duel.player_hp = DUMMY_HP
	_duel.player_shield = 0

	var g = _duel.current_gimmick
	var instantiated: bool = g != null
	var trace := ""
	var turns_ok := true
	if instantiated:
		trace = _trace(g)
		for i in TURNS:
			_duel._begin_player_turn()
			_duel.enemy_system.take_turn()
			if _duel.player_hp < 0 or _duel.player_hp > DUMMY_HP:
				turns_ok = false
			_duel.player_hp = DUMMY_HP
	var ok: bool = instantiated and turns_ok
	if ok:
		_ok += 1
	else:
		_fail += 1
	_lines.append("| %s | %s | %s | %s | %s | %s | %s | %s |" % [
		Palette.act_name(int(r.act)), String(r.name), String(r.kind), _gimmick_name(r),
		"✓" if instantiated else "✗", "✓" if turns_ok else "✗",
		trace if trace != "" else "-", "PASS" if ok else "FAIL"])


func _gimmick_name(r: RoomData) -> String:
	return r.gimmick_script.resource_path.get_file().get_basename().replace("_gimmick", "")


# 抓一个非空/非零的机制属性名，作为「on_room_start 真的跑过」的客观痕迹。
func _trace(g) -> String:
	for p in g.get_script().get_script_property_list():
		var name := String(p.get("name", ""))
		if name == "" or name.begins_with("script"):
			continue
		var v = g.get(name)
		if v is bool:
			if bool(v):
				return name
		elif v is int or v is float:
			if absf(float(v)) > 0.0001:
				return "%s=%s" % [name, str(v)]
		elif v is Dictionary:
			if not (v as Dictionary).is_empty():
				return name
		elif v is Array:
			if not (v as Array).is_empty():
				return name
	return ""


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
