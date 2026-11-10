extends Node

# ============================================================================
# 扫雷棋盘 Step 7 · 受控随机模板（2026-11-11）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/grid_templates_test.tscn
#
# 覆盖（Step 7 出口）：
# ① 少量人工验证模板（3 套），类型构成一致；
# ② 每套：起点安全、BOSS 可达、精英/装备可见、至少一件武器距起点 ≤2；
# ③ 威胁密度可比：无数字 4 的格子，数字总和落在窄带内；
# ④ 至少一条起点→BOSS 路线全程数字 ≤2（可推理，不依赖强制 50/50）；
# ⑤ 同 seed 内容完全一致；不同 seed 轮换模板并产生不同装备路线；
# ⑥ 不存在明显最优模板：战斗预算、威胁密度、装备距离均在允许带内。
# ============================================================================

const SEEDS := [20261110, 20261111, 20261112]
const COUNT_EXPECT := {
	"start": 1, "normal": 6, "elite": 1, "boss": 1,
	"weapon": 2, "charm": 1, "shop": 2, "rest": 2,
}

var _checks := 0
var _fails := 0


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	var duel: DuelController = await _boot()
	if duel == null:
		print("RESULT FAIL (boot)")
		get_tree().quit(2)
		return
	_test_template_count(duel)
	_test_each_template(duel)
	_test_seed_rotation(duel)
	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _boot() -> DuelController:
	var scene: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.board_config.enabled = false
	duel._confirm_loadout()
	await get_tree().process_frame
	return duel


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _grid(duel: DuelController):
	return load("res://scripts/board/board_grid.gd").new(duel)


func _test_template_count(duel: DuelController) -> void:
	var grid = _grid(duel)
	_check(grid.TEMPLATES.size() == 3, "Step 7 使用少量人工模板（3 套，实际 %d）" % grid.TEMPLATES.size())
	_check(int(grid.DEFAULT_TEMPLATE_INDEX) == 1, "默认模板索引为 1")
	_check(grid.template_index_for(20261110) == 1, "默认 seed 20261110 落在默认模板")


func _test_each_template(duel: DuelController) -> void:
	var grid = _grid(duel)
	for idx in range(grid.TEMPLATES.size()):
		var data: Dictionary = grid.generate(1, 20261110, idx)
		var by_id: Dictionary = data["by_id"]
		_check(int(data.get("template_index", -1)) == idx, "模板 %d 可强制生成" % idx)
		_check(by_id[String(data["start_id"])]["type"] == "start" and by_id[String(data["boss_id"])]["type"] == "boss",
			"模板 %d 起点左上 / BOSS 右下" % idx)
		_check((grid.validate(data) as Array).is_empty(),
			"模板 %d 棋盘校验通过（%s）" % [idx, str(grid.validate(data))])

		var tally := {}
		for n in data["nodes"]:
			var t := String(n["type"])
			tally[t] = int(tally.get(t, 0)) + 1
		var counts_ok := true
		for t in COUNT_EXPECT:
			if int(tally.get(t, 0)) != int(COUNT_EXPECT[t]):
				counts_ok = false
		_check(counts_ok, "模板 %d 类型构成与默认版一致（%s）" % [idx, str(tally)])
		var battles: int = int(tally.get("normal", 0)) + int(tally.get("elite", 0)) + int(tally.get("boss", 0))
		_check(battles == 8, "模板 %d 战斗预算 8（普6+精1+王1）" % idx)

		var start: Dictionary = by_id[String(data["start_id"])]
		var safe_first := false
		for nx in start["next"]:
			if not _is_battle(by_id[String(nx)]):
				safe_first = true
		_check(safe_first, "模板 %d 起点有非战斗首选格（安全 / 低风险）" % idx)

		var visible_ok := true
		var near_weapon := false
		for n in data["nodes"]:
			var t := String(n["type"])
			if t in ["elite", "boss", "weapon", "charm", "shop", "rest"] and not bool(n["visible"]):
				visible_ok = false
			if t == "weapon" and int(n["distance"]) <= 2:
				near_weapon = true
		_check(visible_ok, "模板 %d 精英 / BOSS / 装备 / 补给开局可见" % idx)
		_check(near_weapon, "模板 %d 至少一件武器距起点 ≤2（首轮探索动机）" % idx)

		var nums := _numbers(data)
		var total := 0
		var max_n := 0
		for id in nums:
			total += int(nums[id])
			max_n = maxi(max_n, int(nums[id]))
		_check(max_n <= 3, "模板 %d 无数字 4 的格子（最大 %d）" % [idx, max_n])
		_check(total >= 16 and total <= 23, "模板 %d 威胁密度落在可比带内（总和 %d）" % [idx, total])
		_check(_low_threat_route(data, nums), "模板 %d 存在全程数字 ≤2 的起点→BOSS 路线" % idx)

		# 装备价值：两件武器 + 护符均在公开格上，且不是同一路线的重复目标。
		var weapon_ids: Array = data.get("weapon_ids", [])
		_check(weapon_ids.size() == 2, "模板 %d 两件武器目标" % idx)
		var charm: Dictionary = by_id[String(data["charm_id"])]
		_check(String(charm.get("item_path", "")) != "", "模板 %d 护符有冻结候选" % idx)


func _test_seed_rotation(duel: DuelController) -> void:
	var grid = _grid(duel)
	var indices := {}
	var sigs := {}
	for s in SEEDS:
		var data: Dictionary = grid.generate(1, int(s))
		var idx := int(data["template_index"])
		indices[idx] = true
		sigs[s] = _signature(data)
	_check(indices.size() == 3, "三个相邻 seed 覆盖 3 套模板（%s）" % str(indices.keys()))

	var a: Dictionary = grid.generate(1, 20261110)
	var b: Dictionary = grid.generate(1, 20261110)
	_check(_signature(a) == _signature(b), "同 seed 内容完全一致（敌人 / 装备 / 位置）")
	_check(int(a["template_index"]) == 1, "默认 seed 使用默认模板")

	var c: Dictionary = grid.generate(1, 20261111)
	_check(int(a["template_index"]) != int(c["template_index"]), "不同 seed 轮换模板")
	_check(_signature(a) != _signature(c), "不同 seed 产生不同装备路线")

	# 手动指定模板仍可复现，用于测试 / 采集。
	var m1: Dictionary = grid.generate(1, 777, 2)
	var m2: Dictionary = grid.generate(1, 777, 2)
	_check(int(m1["template_index"]) == 2 and _signature(m1) == _signature(m2),
		"template_override 可复现指定模板")


# ---------------------------------------------------------------------------

func _is_battle(n: Dictionary) -> bool:
	return String(n.get("type", "")) in ["normal", "elite", "boss"]


# 按当前棋盘类型计算「四方向相邻普通怪数量」（与 BoardSystem.number_of 同口径）。
func _numbers(data: Dictionary) -> Dictionary:
	var by_id: Dictionary = data["by_id"]
	var out := {}
	for id in by_id:
		var c := 0
		for nx in by_id[id]["next"]:
			if String(by_id[String(nx)]["type"]) == "normal":
				c += 1
		out[id] = c
	return out


# 存在一条起点→BOSS 的路径，路径上每一格的数字都 ≤2（信息可推理，不被 3+ 威胁围死）。
func _low_threat_route(data: Dictionary, nums: Dictionary) -> bool:
	var by_id: Dictionary = data["by_id"]
	var start := String(data["start_id"])
	var boss := String(data["boss_id"])
	var seen := {start: true}
	var q: Array = [start]
	while not q.is_empty():
		var id := String(q.pop_front())
		if id == boss:
			return true
		if int(nums.get(id, 9)) > 2:
			continue
		for nx in by_id[id]["next"]:
			var key := String(nx)
			if seen.has(key):
				continue
			seen[key] = true
			q.append(key)
	return false


func _signature(data: Dictionary) -> String:
	var by_id: Dictionary = data["by_id"]
	var keys: Array = by_id.keys()
	keys.sort()
	var parts: Array[String] = []
	for id in keys:
		var n: Dictionary = by_id[id]
		var room: RoomData = n.get("room")
		var room_path := String(room.resource_path) if room != null else ""
		parts.append("%s:%s:%s:%s" % [id, String(n["type"]), room_path, String(n.get("item_path", ""))])
	return "|".join(parts)
