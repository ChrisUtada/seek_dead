extends Node

# M-02b F7：for_run 的 helper 契约（不是 D1 的调用方回归保护）。
# 本测试自己把 duel.ROOMS 传给 for_run()，验证"给定本局 run_rooms 时 Boss 取数正确"
# 这一 helper 契约；调用方是否真的传 ROOMS（而非 ALL_ROOMS）由
# m02b_chapter_flow_test ① 的"章节头 Boss 名=本局 ACT2 Boss"断言覆盖。
# 连续 boot 3 次（每局不同固定种子），对 act 1/2/3 断言 boss 与 ROOMS 中该幕常规 Boss 同一对象。
# 隔离 APPDATA 运行。

const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const ChapterInfo = preload("res://scripts/systems/chapter_info.gd")

var _checks := 0
var _fails := 0

func _ready() -> void:
	await _run()
	print("M02BMATCH|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("M02BMATCH|FAIL|" + msg)

func _run() -> void:
	var seeds: Array[int] = [111, 222, 333]
	for i in range(seeds.size()):
		seed(seeds[i])
		var scene: PackedScene = load(DUEL_SCENE)
		var duel = scene.instantiate()
		add_child(duel)
		for f in 2:
			await get_tree().process_frame
		duel.demo_config.enabled = false
		duel.demo_config.act_only = false
		duel.board_config.enabled = false
		duel.shop_run_seed = 1000 + i   # 工单：每局不同固定 shop_run_seed
		duel._confirm_loadout()
		for f in 2:
			await get_tree().process_frame
		var rooms: Array = duel.ROOMS
		_check(not rooms.is_empty(), "第%d局 ROOMS 已构建（%d 房）" % [i + 1, rooms.size()])
		for act in [1, 2, 3]:
			var run_boss: RoomData = null
			for r in rooms:
				if r is RoomData and int(r.act) == act and String(r.kind) == "boss" and not bool(r.final_boss):
					run_boss = r
					break
			var d: Dictionary = ChapterInfo.for_run(rooms, act)
			_check(run_boss != null, "第%d局 ACT%d 本局有常规 Boss" % [i + 1, act])
			_check(not d.is_empty() and d["boss"] == run_boss,
				"第%d局 ACT%d 章节头 Boss 等于本局 Boss（%s）" % [i + 1, act, String(d.get("boss_name", "?"))])
		duel.queue_free()
		await get_tree().process_frame
