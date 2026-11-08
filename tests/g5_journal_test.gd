extends Node

# G5 工具回归：局内自动记录（run_journal）——只在 --runlog 下写文件。
# 运行：Godot_v4.7-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/g5_journal_test.tscn -- --runlog
# 产物：user://runs/（建议配合隔离 APPDATA 运行，避免污染真实存档目录）

const DUEL_SCENE := "res://scenes/duel/duel.tscn"

var _pass := 0
var _fail := 0


func _ready() -> void:
	await _run()


func _run() -> void:
	var duel: DuelController = load(DUEL_SCENE).instantiate() as DuelController
	duel.demo_config.enabled = true
	duel.board_config.enabled = true   # 本用例断言棋盘字段，固定走棋盘局
	add_child(duel)
	await _frames(6)
	duel._confirm_loadout()
	await _frames(6)

	_check(duel._journal != null, "journal 已实例化")
	if duel._journal != null:
		_check(duel._journal.is_active(), "start_run 已激活记录")
		duel._journal.note_board_shown()
		duel._journal.note_first_pick("n1")
		duel._journal.note_node({"id": "n1", "type": "normal", "depth": 1})
		var room: RoomData = load("res://resources/rooms/acid_ghoul.tres")
		duel.enemy_hp_max = 123
		duel.enemy_atk = 7
		duel._journal.note_battle_start(room)
		duel.turn_count = 4
		duel._journal.note_battle_end("win")
		duel._journal.note_growth("insight", "洞察")
		duel._journal.note_weapon_change("火焰剑", "匕首", "测试")
		duel._journal.note_shop("治疗药水", "active", 5)
		duel._journal.note_camp("圣盾护符", "passive", 9)
		duel._journal.note_consumable("治疗药水")
		duel._journal.note_special("treasure", "测试宝箱")
		# 成长位的铭印与「下一房对策」也要进记录（此前只有技艺会记）
		var wp := String(duel.selected_loadout[0])
		var ok_imp: bool = duel._post_battle.apply_choice(
			{"kind": "imprint", "entry": {"path": wp, "id": "forge"}, "entry_index": -1})
		_check(ok_imp, "铭印选择成功")
		_check(duel._post_battle.apply_choice({"kind": "fallback_gold", "gold": 7, "entry_index": -1}),
			"兜底金币选择成功")
		var gnames: Array = []
		for g in duel._journal._data.get("growth", []):
			gnames.append(String(g.get("name", "")))
		_check(gnames.has("铭印：锋铸 ×%s" % duel.mastery.display_name(wp)), "铭印已写入记录")
		_check(gnames.has("成长位：金币 +7"), "兜底选择已写入记录")
		# duration_sec 按 0.1 秒取整：headless 跑得比真实时间快，先等足真实 150ms，
		# 否则这一局可能被取整成 0.0 秒（曾导致「时长已记录」偶发失败）。
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 150:
			await get_tree().process_frame
		duel._journal.finish()

		var dir := ProjectSettings.globalize_path("user://runs")
		_check(DirAccess.dir_exists_absolute(dir), "runs 目录存在")
		var files := _list_files(dir)
		var json_files: Array[String] = []
		var txt_files: Array[String] = []
		for f in files:
			if f.ends_with(".json"):
				json_files.append(f)
			elif f.ends_with(".txt"):
				txt_files.append(f)
		_check(json_files.size() > 0, "已生成 JSON")
		_check(txt_files.size() > 0, "已生成预填记录表")

		if json_files.size() > 0:
			var js := _read(json_files[0])
			var d = JSON.parse_string(js)
			_check(d is Dictionary, "JSON 可解析")
			if d is Dictionary:
				_check(String(d.get("mode", "")) == "board", "mode=board")
				_check(String(d.get("result", "")) == "clear", "result=clear")
				_check(int(d.get("battles_count", 0)) == 1, "战斗计数=1")
				_check(float(d.get("duration_sec", 0.0)) > 0.0, "时长已记录")
				var fp: Dictionary = d.get("first_pick", {})
				_check(String(fp.get("node", "")) == "n1", "首次落点已记录")
		if txt_files.size() > 0:
			var txt := _read(txt_files[0])
			for k in ["骨架", "模板", "10 秒找落点", "用时", "自动记录"]:
				_check(txt.contains(k), "记录表包含「%s」" % k)
			_check(txt.contains("主观项"), "记录表声明不含主观项")

	print("G5_JOURNAL|RESULT %s (%d/%d)" % ["PASS" if _fail == 0 else "FAIL", _pass, _pass + _fail])
	get_tree().quit(0 if _fail == 0 else 1)


func _list_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	da.list_dir_begin()
	var n := da.get_next()
	while n != "":
		if not da.current_is_dir():
			out.append(dir.path_join(n))
		n = da.get_next()
	da.list_dir_end()
	out.sort()
	return out


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + what)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
