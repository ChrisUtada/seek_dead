extends Node

# ============================================================================
# 地图巡逻诱导 · Step 0.5 · 新节点类型、真实来源映射与冻结定向回归（2026-11-14）
# 规格：docs/地图巡逻诱导_第一版预算与分步执行计划_2026-11-14.md §6 Step 0.5 任务 2/3/4、自动出口、§7
#
# 覆盖：8 种注册表类型无空类型；chest / armory / shop / rest / event 来源映射真实；
#       treasure_kind / armory_paths 固定且来自 chest 探索来源；同 seed 完全冻结；
#       节点不携带运行时消耗状态（撤回／回访由上层一次性结算）。
#
# 旧 loot_explore_test 不删除、不跳过、不改；本套只验证新地图数据层。
# ============================================================================

const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const BUILDER := "res://scripts/board/map_board_builder.gd"
const TYPES := "res://scripts/board/map_node_types.gd"
const SEED := 20261110

var _checks := 0
var _fails := 0


func _ready() -> void:
	await _run()


func _run() -> void:
	await get_tree().process_frame
	var scene_res: PackedScene = load(DUEL_SCENE)
	if scene_res == null:
		print("MAPLOOT|RESULT FAIL (duel scene missing)")
		get_tree().quit(2)
		return
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await _frames(3)
	var builder = load(BUILDER).new(duel)
	var types = load(TYPES)
	var data: Dictionary = builder.build(1, SEED, 3)

	print("=== A 节点类型注册表 ===")
	_test_registry(data, types)
	print("=== B 真实来源映射 ===")
	_test_sources(data, types)
	print("=== C 探索字段合法 ===")
	_test_explore_fields(data)
	print("=== D 冻结与一次性结算口径 ===")
	_test_freeze(builder, data)

	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	print("MAPLOOT|RESULT %s (checks=%d fails=%d)" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _test_registry(data: Dictionary, types) -> void:
	var counts: Dictionary = {}
	var unregistered := 0
	var missing_legacy := 0
	for n in data["nodes"]:
		var t := String(n["type"])
		counts[t] = int(counts.get(t, 0)) + 1
		if t != types.PATH and t != types.START and not types.is_registered(t):
			unregistered += 1
		if types.is_registered(t) and String(n.get("legacy_type", "")) == "":
			missing_legacy += 1
	_check(unregistered == 0, "所有内容节点都在注册表内（越界 %d）" % unregistered)
	_check(missing_legacy == 0, "每个注册类型都有 legacy_type 结算映射（缺 %d）" % missing_legacy)
	_check(int(counts.get("battle", 0)) == 12, "battle 12（%d）" % int(counts.get("battle", 0)))
	_check(int(counts.get("elite", 0)) == 3, "elite 3（%d）" % int(counts.get("elite", 0)))
	_check(int(counts.get("boss", 0)) == 1, "boss 1（%d）" % int(counts.get("boss", 0)))
	_check(int(counts.get("chest", 0)) == 3, "chest 3（%d）" % int(counts.get("chest", 0)))
	_check(int(counts.get("armory", 0)) == 1, "armory 1（%d）" % int(counts.get("armory", 0)))
	_check(int(counts.get("shop", 0)) == 1, "shop 1（%d）" % int(counts.get("shop", 0)))
	_check(int(counts.get("rest", 0)) == 2, "rest 2（%d）" % int(counts.get("rest", 0)))
	_check(int(counts.get("event", 0)) == 4, "event 4（%d）" % int(counts.get("event", 0)))
	_check(int(counts.get("start", 0)) == 1, "start 1（%d）" % int(counts.get("start", 0)))
	_check(int(counts.get(types.PATH, 0)) == 33, "通路 33（%d）" % int(counts.get(types.PATH, 0)))
	for key in types.TYPES.keys():
		_check(int(counts.get(key, 0)) > 0, "注册表类型 %s 在地图上真实出现" % key)


func _test_sources(data: Dictionary, types) -> void:
	var wrong_source := 0
	var shop_item := 0
	var rest_item := 0
	var event_item := 0
	for n in data["nodes"]:
		var t := String(n["type"])
		if not types.is_registered(t):
			continue
		if String(n.get("source", "")) != types.source_of(t):
			wrong_source += 1
		match t:
			"shop":
				if String(n.get("item_path", "")) != "" or (n.get("armory_paths", []) as Array).size() > 0:
					shop_item += 1
			"rest":
				if String(n.get("item_path", "")) != "" or (n.get("armory_paths", []) as Array).size() > 0:
					rest_item += 1
			"event":
				if String(n.get("item_path", "")) != "" or (n.get("armory_paths", []) as Array).size() > 0:
					event_item += 1
	_check(wrong_source == 0, "source 字段与注册表一致（异常 %d）" % wrong_source)
	_check(shop_item == 0, "shop 不伪装成宝箱、不生成装备（异常 %d）" % shop_item)
	_check(rest_item == 0, "rest 不生成装备（异常 %d）" % rest_item)
	_check(event_item == 0, "event 走独立配置、不生成装备（异常 %d）" % event_item)
	_check(types.source_of("chest") == "chest", "chest 来源固定为 chest")
	_check(types.source_of("armory") == "armory", "armory 来源固定为 armory")
	_check(types.source_of("shop") != "chest", "shop 来源不等于 chest")


func _test_explore_fields(data: Dictionary) -> void:
	var bad_kind := 0
	var bad_path := 0
	var relic_leak := 0
	var seen_chest := 0
	var seen_armory := 0
	var bad_armory := 0
	var bad_event := 0
	for n in data["nodes"]:
		var t := String(n["type"])
		if t == "chest":
			seen_chest += 1
			var kind := String(n.get("treasure_kind", ""))
			if not (kind in ["weapon", "charm", "active", "gold"]):
				bad_kind += 1
			var p := String(n.get("item_path", ""))
			if kind != "gold":
				if p == "" or not ResourceLoader.exists(p):
					bad_path += 1
				if p.get_file().contains("_relic"):
					relic_leak += 1
		elif t == "armory":
			seen_armory += 1
			var paths: Array = n.get("armory_paths", [])
			if paths.size() < 2 or String(paths[0]) == String(paths[1]):
				bad_armory += 1
			for p in paths:
				var sp := String(p)
				if not ResourceLoader.exists(sp) or sp.get_file().contains("_relic"):
					bad_armory += 1
		elif t == "event":
			var k := String(n.get("shrine_kind", ""))
			if not (k in ["heal", "maxhp", "ward"]) or int(n.get("shrine_value", 0)) <= 0:
				bad_event += 1
	_check(bad_kind == 0, "treasure_kind 只取真实类别（异常 %d）" % bad_kind)
	_check(bad_path == 0, "chest 的 item_path 是存在的真实资源（异常 %d）" % bad_path)
	_check(relic_leak == 0, "chest 不冻结 BOSS 信物（泄漏 %d）" % relic_leak)
	_check(seen_chest > 0 and seen_armory > 0,
		"样本覆盖宝箱与武器藏库（chest %d / armory %d）" % [seen_chest, seen_armory])
	_check(bad_armory == 0, "armory_paths 是两把互不重复的真实武器（异常 %d）" % bad_armory)
	_check(bad_event == 0, "event 使用独立 shrine 配置（异常 %d）" % bad_event)


func _test_freeze(builder, data: Dictionary) -> void:
	_check(_signature(data) == _signature(builder.build(1, SEED, 3)),
		"同 (seed, act, total_acts) 探索字段完全冻结")
	_check(_signature(data) != _signature(builder.build(1, 20261111, 3)),
		"不同 seed 可区分（探索内容随 seed 变化）")
	var layout_a := _layout_signature(data)
	var layout_b := _layout_signature(builder.build(1, 20261111, 3))
	_check(layout_a == layout_b, "地形与节点类型布局不随 seed 变")
	var runtime_leak := 0
	for n in data["nodes"]:
		if n.has("consumed") or n.has("defeated"):
			runtime_leak += 1
	_check(runtime_leak == 0, "节点不写运行时消耗状态，撤回／回访由上层一次性结算（泄漏 %d）" % runtime_leak)
	_check(bool(data["by_id"][data["boss_id"]]["frozen"]), "内容生成时冻结标记在位")


func _signature(data: Dictionary) -> String:
	var parts: Array[String] = []
	for n in data["nodes"]:
		var r: RoomData = n.get("room")
		parts.append("%s:%s:%s:%s:%s:%s:%s" % [
			String(n["id"]), String(n["type"]), str(n.get("variant", -1)),
			r.resource_path if r != null else "",
			String(n.get("treasure_kind", "")), String(n.get("item_path", "")),
			str(n.get("armory_paths", []))])
	return "|".join(parts)


func _layout_signature(data: Dictionary) -> String:
	var parts: Array[String] = []
	for n in data["nodes"]:
		parts.append("%s:%s" % [String(n["id"]), String(n["type"])])
	return "|".join(parts)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if ok:
		print("PASS  " + what)
	else:
		_fails += 1
		print("FAIL  " + what)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
