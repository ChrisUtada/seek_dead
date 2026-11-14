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
const REWARD := "res://scripts/board/map_reward.gd"
const RUNTIME := "res://scripts/board/map_runtime.gd"
const MAP_GRID := preload("res://scripts/board/map_grid.gd")
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
	print("=== E 冻结的奖励内容（chest / armory / shop / rest / event） ===")
	_test_frozen_content(data, types)
	print("=== F 结算语义分离与无落空奖励 ===")
	_test_settle_semantics(data)
	print("=== G 一次性结算 / 回访 / 撤回 / 查看 ===")
	_test_once_only(duel, data)

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


# Step 5A 任务 2：宝箱 / 藏库 / 商店 / 事件的奖励内容必须当场冻结，不留空字段。
func _test_frozen_content(data: Dictionary, _types) -> void:
	var chest_gold := 0
	var chest_item := 0
	var shop_nodes := 0
	var rest_nodes := 0
	var bad_gold := 0
	var bad_shop := 0
	var bad_rest := 0
	var stock_size := 0
	for n in data["nodes"]:
		match String(n["type"]):
			"chest":
				var kind := String(n.get("treasure_kind", ""))
				if kind == "gold":
					chest_gold += 1
					if int(n.get("gold_amount", 0)) <= 0:
						bad_gold += 1
				else:
					chest_item += 1
					if int(n.get("gold_amount", 0)) != 0:
						bad_gold += 1
			"shop":
				shop_nodes += 1
				var seen: Dictionary = {}
				for entry in n.get("shop_stock", []):
					var p := String(entry.get("path", ""))
					stock_size += 1
					if p == "" or seen.has(p):
						bad_shop += 1
					seen[p] = true
			"rest":
				rest_nodes += 1
				if float(n.get("rest_heal_pct", 0.0)) <= 0.0:
					bad_rest += 1
	_check(chest_gold + chest_item == 3, "宝箱 3 项都冻结了内容（金币 %d / 物品 %d）" % [chest_gold, chest_item])
	_check(bad_gold == 0, "金币宝箱冻结 gold_amount、物品宝箱不带金额（异常 %d）" % bad_gold)
	_check(shop_nodes == 1, "商店 1 个（%d）" % shop_nodes)
	_check(stock_size > 0, "商店货架冻结且非空（%d 件）" % stock_size)
	_check(bad_shop == 0, "商店货架无空条目、无重复（异常 %d）" % bad_shop)
	_check(rest_nodes == 2, "休整 2 个（%d）" % rest_nodes)
	_check(bad_rest == 0, "休整冻结回血比例（异常 %d）" % bad_rest)


# Step 5A 任务 3：chest 与 shop 结算语义必须不同，且不允许出现落空奖励。
func _test_settle_semantics(data: Dictionary) -> void:
	var reward = load(REWARD)
	var modes: Dictionary = {}
	var blank_text := 0
	for n in data["nodes"]:
		var t := String(n["type"])
		if t == "path" or t == "start":
			continue
		var p: Dictionary = reward.plan(n)
		modes[t] = String(p.get("mode", ""))
		if String(reward.describe(p)) == "":
			blank_text += 1
	_check(blank_text == 0, "所有内容节点都有非空结算文案（缺失 %d）" % blank_text)
	# 逐类型语义（同一类型取首个节点判定，其余由 validate 全量扫描）。
	_check(String(modes.get("chest", "")) in ["item", "active", "gold"],
		"chest 为免费授予 item/active/gold（%s）" % String(modes.get("chest", "")))
	_check(String(modes.get("armory", "")) == "choose_one", "armory 为 2 选 1（%s）" % String(modes.get("armory", "")))
	_check(String(modes.get("shop", "")) == "purchase", "shop 为付费购买（%s）" % String(modes.get("shop", "")))
	_check(String(modes.get("rest", "")) == "heal", "rest 为回血（%s）" % String(modes.get("rest", "")))
	_check(String(modes.get("event", "")) == "shrine", "event 走独立配置（%s）" % String(modes.get("event", "")))
	_check(String(modes.get("battle", "")) == "battle", "battle 为战斗结算")
	_check(String(modes.get("shop", "")) != String(modes.get("chest", "")),
		"shop 与 chest 结算模式不同，未为兼容旧测试统一")
	for n in data["nodes"]:
		if String(n["type"]) != "shop":
			continue
		var p: Dictionary = reward.plan(n)
		_check(not bool(p.get("free", true)), "商店不能免费赠予")
		_check(String(p.get("pricing", "")) == "shop", "商店使用现有商店计价")
	var errs: Array = reward.validate(data)
	_check(errs.is_empty(), "奖励合法性校验无错误（%s）" % str(errs.slice(0, 3)))

	# 三类反例必须被拒：商店伪装宝箱 / 空货架 / 空类型。
	var shop_node: Dictionary = {}
	for n in data["nodes"]:
		if String(n["type"]) == "shop":
			shop_node = n
	var fake: Dictionary = shop_node.duplicate(true)
	fake["item_path"] = "res://resources/weapon_templates/acid_flask.tres"
	_check(not reward.validate({"nodes": [fake]}).is_empty(), "商店携带赠予字段时报伪来源")
	var empty_stock: Dictionary = shop_node.duplicate(true)
	empty_stock["shop_stock"] = []
	_check(not reward.validate({"nodes": [empty_stock]}).is_empty(), "商店货架为空时报落空奖励")
	var blank: Dictionary = {"id": "x", "type": "", "source": ""}
	_check(not reward.validate({"nodes": [blank]}).is_empty(), "空类型节点被拒")
	var wrong_source: Dictionary = {"id": "y", "type": "chest", "source": "shop",
		"treasure_kind": "gold", "gold_amount": 15}
	_check(not reward.validate({"nodes": [wrong_source]}).is_empty(), "错误来源被拒")


# Step 5A 出口：查看 / 回访 / 撤回都不重抽、不重复获得。
func _test_once_only(duel: DuelController, data: Dictionary) -> void:
	var rt = load(RUNTIME).create(duel, 1, SEED, 3, false)
	var chest_cell := -1
	var armory_cell := -1
	for n in data["nodes"]:
		var t := String(n["type"])
		if t == "chest" and chest_cell < 0:
			chest_cell = int(n["cell_id"])
		elif t == "armory" and armory_cell < 0:
			armory_cell = int(n["cell_id"])
	_check(chest_cell >= 0 and armory_cell >= 0, "地图上存在宝箱与藏库")

	var preview: Dictionary = rt.grant_preview(chest_cell)
	_check(String(preview.get("mode", "")) != "", "结算预览给出模式")
	var sig_before: String = rt.signature()
	rt.grant_preview(chest_cell)
	rt.view(chest_cell)
	rt.view(armory_cell)
	_check(rt.signature() == sig_before, "预览与查看不改变状态")

	var log_before: int = _grants_for(rt, chest_cell)
	_check(_walk(rt, chest_cell), "可沿合法路径走到宝箱")
	_check(_grants_for(rt, chest_cell) == log_before + 1,
		"首次结算该宝箱记 1 条流水（%d → %d）" % [log_before, _grants_for(rt, chest_cell)])
	var g: Dictionary = _grant_at(rt, chest_cell)
	_check(String(g.get("mode", "")) == String(preview.get("mode", "")), "实际结算模式与预览一致")
	_check(bool(g.get("free", false)), "宝箱结算免费")

	var away: Array = MAP_GRID.neighbors(rt.grid, chest_cell)
	if not away.is_empty():
		rt.try_move(int(away[0]))
	var after_first: int = _grants_for(rt, chest_cell)
	_walk(rt, chest_cell)
	_check(_grants_for(rt, chest_cell) == after_first, "回访不新增结算流水")
	_check(rt.is_consumed(chest_cell), "宝箱仍标记已消耗")

	_check(_walk(rt, armory_cell), "可沿合法路径走到藏库")
	_check(not rt.pending_choice.is_empty(), "藏库结算挂起 2 选 1")
	var options: Array = rt.pending_choice.get("options", [])
	_check(options.size() == 2, "藏库给出 2 个选项（%d）" % options.size())
	var bad_pick: Dictionary = rt.choose_armory(armory_cell, 5)
	_check(not bool(bad_pick["ok"]), "越界选择被拒绝")
	var before_choice: int = rt.grants.size()
	var pick: Dictionary = rt.choose_armory(armory_cell, 0)
	_check(bool(pick["ok"]), "合法选择成功")
	_check(String(pick["path"]) == String(options[0]), "发放的是所选那把武器")
	_check(rt.pending_choice.is_empty(), "选择后挂起状态清空")
	_check(rt.grants.size() == before_choice + 1, "选择只记 1 条流水")
	_check(not bool(rt.choose_armory(armory_cell, 1)["ok"]), "同一藏库不能重复领取")

	var turn_before: int = rt.turn
	var consumed_before: int = rt.consumed.size()
	var w: Dictionary = rt.withdraw()
	_check(bool(w["ok"]), "撤回整备返回成功")
	_check(not bool(w["granted"]), "撤回不发放未结算奖励")
	_check(rt.turn == turn_before, "撤回不推进回合")
	_check(rt.consumed.size() == consumed_before, "撤回不回收已结算内容")
	_check(rt.pending_battle.is_empty(), "撤回清空待战节点")


func _grants_for(rt, cell: int) -> int:
	var n := 0
	for g in rt.grants:
		if int(g.get("cell", -1)) != cell:
			continue
		var mode := String(g.get("mode", ""))
		if mode == "chosen" or mode == "declined":
			continue
		n += 1
	return n


func _grant_at(rt, cell: int) -> Dictionary:
	for g in rt.grants:
		if int(g.get("cell", -1)) == cell:
			return g
	return {}


func _walk(rt, target: int) -> bool:
	var path: Array = MAP_GRID.reachable(rt.grid, rt.player_cell, target)
	if path.is_empty():
		return false
	for i in range(1, path.size()):
		var r: Dictionary = rt.try_move(int(path[i]))
		if not bool(r["ok"]):
			return false
		if String(r["settled"].get("kind", "")) == "battle":
			rt.take_pending_battle()
	return rt.player_cell == target


func _signature(data: Dictionary) -> String:
	var parts: Array[String] = []
	for n in data["nodes"]:
		var r: RoomData = n.get("room")
		parts.append("%s:%s:%s:%s:%s:%s:%s:%s:%s:%s" % [
			String(n["id"]), String(n["type"]), str(n.get("variant", -1)),
			r.resource_path if r != null else "",
			String(n.get("treasure_kind", "")), String(n.get("item_path", "")),
			str(n.get("armory_paths", [])), str(n.get("shop_stock", [])),
			str(n.get("rest_heal_pct", "")), str(n.get("gold_amount", ""))])
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
