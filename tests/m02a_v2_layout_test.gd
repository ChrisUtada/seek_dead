extends Node

# 新版 M-02a 步骤 2：房间序列与特殊房类型 · 专项回归。
# 覆盖 §2 固定 8 房：普通→普通→宝箱/事件→精英→普通→精英→营地→Boss。
# 特殊房无敌人/无 gimmick；同 shop_run_seed 下类型可复现。

var _fails := 0
var _checks := 0
var _duel: DuelController

func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("M02A V2 FAIL: " + label)

func _ready() -> void:
	await get_tree().process_frame
	SaveSystem.reset_lobby_data()
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	_duel = scene_res.instantiate() as DuelController
	add_child(_duel)
	await get_tree().process_frame
	await get_tree().process_frame
	_duel.demo_config.enabled = false
	# 固定 seed 保证可复现断言稳定
	_duel.shop_run_seed = 1234567
	_duel._confirm_loadout()
	await get_tree().process_frame

	_test_layout()
	_test_special_nodes()
	_test_reproducible()
	_test_frozen_content()
	_test_event_no_repeat()

	_finish()

const EXPECT_KINDS: Array = ["normal", "normal", "SPECIAL", "elite", "normal", "elite", "camp", "boss"]

func _test_layout() -> void:
	var rooms: Array = _duel.ROOMS
	_ok(rooms.size() == 25, "总房数 = 3×8 + 真·最终（实测 %d）" % rooms.size())
	for act in range(1, 4):
		var base: int = (act - 1) * 8
		var got: Array = []
		for i in 8:
			var k: String = String((rooms[base + i] as RoomData).kind)
			if k == "chest" or k == "event":
				k = "SPECIAL"
			got.append(k)
		_ok(got == EXPECT_KINDS, "幕 %d 新版固定顺序（实测 %s）" % [act, str(got)])
		# 第 3 房必须是宝箱或事件之一
		var k3: String = String((rooms[base + 2] as RoomData).kind)
		_ok(k3 == "chest" or k3 == "event", "幕 %d 第 3 房为宝箱/事件（实测 %s）" % [act, k3])

func _test_special_nodes() -> void:
	for act in range(1, 4):
		var sp: RoomData = _duel.ROOMS[(act - 1) * 8 + 2]
		_ok(int(sp.hp) == 0 and int(sp.atk) == 0 and int(sp.armor) == 0, "幕 %d 特殊房无战斗数值" % act)
		_ok(sp.archetype == null and sp.gimmick_script == null, "幕 %d 特殊房无 archetype/gimmick" % act)
		_ok(sp.intents.is_empty(), "幕 %d 特殊房无意图表" % act)
		_ok(sp.name == "宝箱" or sp.name == "事件", "幕 %d 特殊房名=%s" % [act, sp.name])

# 同 seed 两次 build_run 的特殊房类型序列必须一致（可复现）。
func _test_reproducible() -> void:
	var seq_a: Array = []
	for r in _duel._build_run():
		var k: String = String((r as RoomData).kind)
		if k == "chest" or k == "event":
			seq_a.append(k)
	var seq_b: Array = []
	for r in _duel._build_run():
		var k: String = String((r as RoomData).kind)
		if k == "chest" or k == "event":
			seq_b.append(k)
	_ok(seq_a == seq_b, "同 seed 特殊房类型序列可复现（%s vs %s）" % [str(seq_a), str(seq_b)])
	_ok(seq_a.size() == 3, "三幕各一个特殊房（实测 %d）" % seq_a.size())

# 步骤 3：特殊房内容生成时冻结，同 seed 可复现；进入前只显示类型（name）。
func _test_frozen_content() -> void:
	var run: Array = _duel._build_run()
	for i in run.size():
		var r: RoomData = run[i]
		if r.kind == "chest":
			var p: Dictionary = r.gimmick_params
			_ok(String(p.get("special_kind", "")) == "chest", "宝箱冻结 special_kind=chest")
			var has_item: bool = String(p.get("item_path", "")) != ""
			var has_gold: bool = bool(p.get("fallback", false)) and int(p.get("fallback_gold", 0)) > 0
			_ok(has_item or has_gold, "宝箱冻结具体物品或金币兜底（%s）" % str(p))
		elif r.kind == "event":
			var p: Dictionary = r.gimmick_params
			_ok(String(p.get("special_kind", "")) == "event", "事件冻结 special_kind=event")
			var opts: Array = p.get("options", [])
			_ok(not opts.is_empty() or bool(p.get("empty", false)), "事件冻结二选一选项或明确空状态（%s）" % str(p))
			for o in opts:
				var od: Dictionary = o
				_ok(od.has("label"), "事件选项含展示文案")

# §5：同一事件一局内不重复。
func _test_event_no_repeat() -> void:
	var ids: Array = []
	for r in _duel._build_run():
		var k: String = String((r as RoomData).kind)
		if k == "event":
			var eid: String = String((r as RoomData).gimmick_params.get("id", ""))
			if eid != "" and eid != "none":
				_ok(not ids.has(eid), "事件 id 一局内不重复（%s）" % eid)
				ids.append(eid)

func _finish() -> void:
	print("M02AV2 RESULT: %d checks, %d fails" % [_checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)
