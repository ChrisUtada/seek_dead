extends Node

# ============================================================================
# 地图巡逻诱导 · Step 5B · 成长与路线分工定向回归（2026-11-14）
# 规格：docs/地图巡逻诱导_第一版预算与分步执行计划_2026-11-14.md
#       §6 Step 5B 任务 1–5 与出口、§7「奖励 / 成长队列 / 图鉴来源」
#
# 覆盖五条出口：
#   1) 装备来源不被错误迁移；   2) 成长只结算一次；
#   3) 未选 queued 成长正确保留；4) 宝箱、商店和 BOSS 仍可获取真实装备；
#   5) 图鉴与来源记录一致。
#
# 只使用开发／AI 测试入口（MapRuntime + MapProgress），不接产品默认入口，
# 不改 board_system / board_screen / board_config，不退役任何旧测试。
# ============================================================================

const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const BUILDER := "res://scripts/board/map_board_builder.gd"
const REWARD := "res://scripts/board/map_reward.gd"
const PROGRESS := "res://scripts/board/map_progress.gd"
const RUNTIME := "res://scripts/board/map_runtime.gd"

const SEED := 20261110
const START := 57
const BATTLE_NEAR_START := 58   # 起点东邻，普通战节点

const GROWTH_KINDS := ["perk", "imprint", "fallback_shield", "fallback_gold", "fallback_power"]

var _checks := 0
var _fails := 0
var _duel: DuelController = null


func _ready() -> void:
	await _run()


func _run() -> void:
	await get_tree().process_frame
	var scene_res: PackedScene = load(DUEL_SCENE)
	if scene_res == null:
		print("MAPPROG|RESULT FAIL (duel scene missing)")
		get_tree().quit(2)
		return
	_duel = scene_res.instantiate() as DuelController
	add_child(_duel)
	await _frames(3)

	var cfg = _duel.board_config
	var dev_was: bool = bool(cfg.map_dev_override)
	cfg.map_dev_override = true
	var progress = load(PROGRESS)
	var reward = load(REWARD)
	var builder = load(BUILDER).new(_duel)
	var data: Dictionary = builder.build(1, SEED, 1)

	print("=== A 路线分工 ===")
	_test_routing(progress)
	print("=== B 普通战三选一 ===")
	_test_normal_choices(progress, data)
	print("=== C 精英收益更高 ===")
	_test_elite(progress)
	print("=== D BOSS 专属战利品 ===")
	_test_boss(progress)
	print("=== E 宝箱与商店仍给装备 ===")
	_test_gear_sources(reward, data)
	print("=== F 成长只结算一次 ===")
	_test_once_only()
	print("=== G 未选 queued 成长保留 ===")
	_test_queue_kept(progress, data)
	print("=== H 战败不发奖励 ===")
	_test_defeat()
	print("=== I 来源记录一致 ===")
	_test_source_records(progress, reward, data)

	cfg.map_dev_override = dev_was
	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	print("MAPPROG|RESULT %s (checks=%d fails=%d)" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _battle_node(cell: int) -> Dictionary:
	return {"id": "m%d" % cell, "type": "battle", "cell_id": cell, "source": "room"}


# ---------------------------------------------------------------------------
# A 路线分工
# ---------------------------------------------------------------------------

func _test_routing(progress) -> void:
	_check(progress.kind_of(_battle_node(58)) == "normal", "battle → normal")
	_check(progress.kind_of({"type": "patrol"}) == "normal", "巡逻遭遇按普通战处理")
	_check(progress.kind_of({"type": "elite"}) == "elite", "elite → elite")
	_check(progress.kind_of({"type": "boss"}) == "boss", "boss → boss")
	_check(progress.kind_of({"type": "chest"}) == "", "非战斗节点不分流")
	_check(progress.kind_of({"type": "path"}) == "", "通路不分流")

	var n: Dictionary = progress.plan(_battle_node(58))
	_check(String(n["pipeline"]) == "post_battle" and int(n["xp"]) == 1,
		"普通战走 post_battle、历练 1（%s / %d）" % [String(n["pipeline"]), int(n["xp"])])
	_check(int(n["cards"]) == 3, "普通战三选一（%d）" % int(n["cards"]))
	var e: Dictionary = progress.plan({"type": "elite"})
	_check(String(e["pipeline"]) == "post_battle" and int(e["xp"]) == 2,
		"精英走 post_battle、历练 2（%d）" % int(e["xp"]))
	_check(bool(e["elite_bonus"]), "精英标记更高收益档")
	var b: Dictionary = progress.plan({"type": "boss"})
	_check(String(b["pipeline"]) == "boss_loot" and int(b["xp"]) == 3,
		"BOSS 走 boss_loot、历练 3（%d）" % int(b["xp"]))
	_check(int(b["xp"]) > int(e["xp"]) and int(e["xp"]) > int(n["xp"]), "历练阶梯 normal < elite < boss")


# ---------------------------------------------------------------------------
# B 普通战三选一
# ---------------------------------------------------------------------------

func _test_normal_choices(progress, data: Dictionary) -> void:
	var cell := BATTLE_NEAR_START
	var node: Dictionary = data["by_id"]["m%d" % cell]
	var built: Dictionary = progress.build(node, _duel)
	var cards: Array = built["cards"]
	_check(cards.size() == 3, "普通战给出 3 张卡（%d）" % cards.size())
	var slots: Array = []
	for c in cards:
		slots.append(String(c.get("slot", "")))
	_check(slots == ["supply", "build", "growth"], "槽位为 补给 / 构筑 / 成长（%s）" % str(slots))
	var titled := 0
	for c in cards:
		if String(c.get("title", "")) != "" and String(c.get("desc", "")) != "":
			titled += 1
	_check(titled == 3, "三张卡都有标题与说明（%d）" % titled)
	var growth_kind := String(cards[2].get("kind", ""))
	_check(GROWTH_KINDS.has(growth_kind),
		"成长卡是真实成长或真实对策（%s）" % growth_kind)
	_check(int(built["xp"]) == 1, "普通战历练 1")
	_check(cards[0].get("reward") != null and cards[1].get("reward") != null,
		"补给与构筑卡都绑定真实 RewardData")


# ---------------------------------------------------------------------------
# C 精英收益更高
# ---------------------------------------------------------------------------

func _test_elite(progress) -> void:
	var rs = _duel._reward_system
	var normal_supply: Array = rs._slot_supply_pool("normal")
	var elite_supply: Array = rs._slot_supply_pool("elite")
	var normal_ids: Array = []
	var elite_ids: Array = []
	for r in normal_supply:
		normal_ids.append(String(r.id))
	for r in elite_supply:
		elite_ids.append(String(r.id))
	var elite_only := 0
	for id in elite_ids:
		if not normal_ids.has(id):
			elite_only += 1
	_check(elite_only > 0, "精英补给池含专属档（%d 项）" % elite_only)

	var normal_build: Array = rs._slot_build_pool("normal", 1)
	var elite_build: Array = rs._slot_build_pool("elite", 1)
	var elite_weapon := false
	for r in elite_build:
		if String(r.id) == "weapon":
			elite_weapon = true
	_check(elite_weapon, "精英构筑池保证可给武器")
	_check(elite_build.size() >= 1, "精英构筑池仍有真实构筑项（%d）" % elite_build.size())
	_check(progress.plan({"type": "elite"})["xp"] > progress.plan(_battle_node(58))["xp"],
		"精英历练高于普通战")


# ---------------------------------------------------------------------------
# D BOSS 专属战利品
# ---------------------------------------------------------------------------

func _test_boss(progress) -> void:
	var boss_room: RoomData = null
	for r in _duel.ALL_ROOMS:
		if r == null or String(r.kind) != "boss":
			continue
		if bool(r.final_boss):
			continue
		if r.boss_reward_weapons.size() > 0:
			boss_room = r
			break
	_check(boss_room != null, "存在带主题武器池的常规 BOSS 房")
	if boss_room == null:
		return
	var node := {"id": "m99", "type": "boss", "cell_id": 99, "source": "room", "room": boss_room}
	var built: Dictionary = progress.build(node, _duel)
	var cards: Array = built["cards"]
	_check(cards.size() > 0, "BOSS 战利品不为空（%d）" % cards.size())
	_check(cards.size() <= 3, "BOSS 战利品至多 3 张（%d）" % cards.size())
	var allowed := ["boss_weapon", "boss_relic", "boss_anvil"]
	var bad := 0
	var weapon_cards := 0
	var off_theme := 0
	for c in cards:
		var k := String(c.get("kind", ""))
		if not allowed.has(k):
			bad += 1
		if k == "boss_weapon":
			weapon_cards += 1
			if not boss_room.boss_reward_weapons.has(String(c.get("path", ""))):
				off_theme += 1
	_check(bad == 0, "BOSS 卡只来自专属类型（异常 %d）" % bad)
	_check(off_theme == 0, "BOSS 武器只来自该房主题池（越界 %d）" % off_theme)
	_check(weapon_cards > 0 or cards.size() > 0,
		"BOSS 战利品至少一张：武器 / 信物 / 铁砧兜底（武器 %d 张，合计 %d 张）" % [weapon_cards, cards.size()])
	var first_path := String(cards[0].get("path", ""))
	_check(cards[0].get("kind") == "boss_anvil" or ResourceLoader.exists(first_path),
		"BOSS 战利品路径真实存在（或铁砧兜底）")
	_check(String(built["pipeline"]) == "boss_loot", "BOSS 走 boss_loot 管线")


# ---------------------------------------------------------------------------
# E 宝箱与商店仍给装备
# ---------------------------------------------------------------------------

func _test_gear_sources(reward, data: Dictionary) -> void:
	var chest_modes: Array = []
	var shop_found := false
	for n in data["nodes"]:
		var t := String(n["type"])
		if t == "chest":
			var p: Dictionary = reward.plan(n)
			chest_modes.append(String(p["mode"]))
			_check(bool(p["free"]), "宝箱仍然免费授予")
			if String(p["mode"]) == "item" or String(p["mode"]) == "active":
				_check(ResourceLoader.exists(String(p.get("path", ""))), "宝箱物品真实存在")
		elif t == "shop":
			shop_found = true
			var p2: Dictionary = reward.plan(n)
			_check(String(p2["mode"]) == "purchase", "商店仍是付费购买")
			_check(not bool(p2["free"]), "商店不免费")
			var stock: Array = p2.get("stock", [])
			_check(stock.size() > 0, "商店货架非空（%d）" % stock.size())
			var real := 0
			for e in stock:
				if ResourceLoader.exists(String(e.get("path", ""))):
					real += 1
			_check(real == stock.size(), "商店在售物品全部真实（%d/%d）" % [real, stock.size()])
	_check(chest_modes.size() == 3, "宝箱 3 个（%d）" % chest_modes.size())
	_check(shop_found, "商店仍在")


# ---------------------------------------------------------------------------
# F 成长只结算一次
# ---------------------------------------------------------------------------

func _test_once_only() -> void:
	var rt = load(RUNTIME).create(_duel, 1, SEED, 1, false)
	var xp_before: int = int(_duel.growth.xp)
	var moved: Dictionary = rt.try_move(BATTLE_NEAR_START)
	_check(String(moved["settled"].get("kind", "")) == "battle", "进入战斗格挂起战斗")
	_check(rt.has_pending_battle(), "存在待结算战斗")
	var r1: Dictionary = rt.resolve_battle(true)
	_check(bool(r1["ok"]), "首次结算成功")
	_check(String(r1["kind"]) == "normal", "按普通战结算")
	_check(int(_duel.growth.xp) - xp_before == 1, "历练只加 1（%d）" % (int(_duel.growth.xp) - xp_before))
	var r2: Dictionary = rt.resolve_battle(true)
	_check(not bool(r2["ok"]), "二次结算被拒（%s）" % String(r2.get("reason", "")))
	_check(int(_duel.growth.xp) - xp_before == 1, "二次结算不再加历练")
	_check(rt.battles.size() == 1, "战斗结算记录 1 条（%d）" % rt.battles.size())
	_check(rt.is_consumed(BATTLE_NEAR_START), "战斗格标记已消耗")


# ---------------------------------------------------------------------------
# G 未选 queued 成长保留
# ---------------------------------------------------------------------------

func _test_queue_kept(progress, data: Dictionary) -> void:
	var g = _duel.growth
	var pending_was: int = int(g.pending_picks)
	g.pending_picks = maxi(1, pending_was)
	var kept_target: int = int(g.pending_picks)
	var node: Dictionary = data["by_id"]["m%d" % BATTLE_NEAR_START]
	var built: Dictionary = progress.build(node, _duel)
	_check(int(g.pending_picks) == kept_target,
		"生成奖励卡不消耗待选成长（%d → %d）" % [kept_target, int(g.pending_picks)])
	var queue_size: int = (_duel._post_battle.queue as Array).size()
	_check(queue_size >= 1, "待选成长进入队列（%d）" % queue_size)

	var growth_card: Dictionary = built["cards"][2]
	_check(String(growth_card.get("kind", "")) == "perk" or String(growth_card.get("kind", "")) == "imprint",
		"有待选成长时成长卡是真实成长项（%s）" % String(growth_card.get("kind", "")))

	# 只看另一张卡（不选成长）→ 成长仍在队列里。
	var again: Dictionary = _duel._post_battle.build_growth()
	_check(not again.is_empty(), "未选成长仍可再次取到")
	_check(int(g.pending_picks) == kept_target, "未选成长仍待选（%d）" % int(g.pending_picks))
	_check((_duel._post_battle.queue as Array).size() == queue_size, "队列长度不变")
	g.pending_picks = pending_was
	_duel._post_battle.queue.clear()


# ---------------------------------------------------------------------------
# H 战败不发奖励
# ---------------------------------------------------------------------------

func _test_defeat() -> void:
	var rt = load(RUNTIME).create(_duel, 1, SEED, 1, false)
	var xp_before: int = int(_duel.growth.xp)
	rt.try_move(BATTLE_NEAR_START)
	var r: Dictionary = rt.resolve_battle(false)
	_check(bool(r["ok"]), "战败也返回可结算（仅记录）")
	_check((r["reward"] as Dictionary).is_empty(), "战败不发奖励卡")
	_check((r["applied"] as Dictionary).is_empty(), "战败不结算历练")
	_check(int(_duel.growth.xp) == xp_before, "战败不加历练")
	_check(rt.is_consumed(BATTLE_NEAR_START), "战败后战斗格仍消耗")
	_check(rt.battles.has(BATTLE_NEAR_START), "战败写入战斗记录")
	_check(not bool(rt.battles[BATTLE_NEAR_START]["victory"]), "战斗记录标记为失败")


# ---------------------------------------------------------------------------
# I 来源记录一致
# ---------------------------------------------------------------------------

func _test_source_records(progress, reward, data: Dictionary) -> void:
	var mismatched := 0
	var checked := 0
	for n in data["nodes"]:
		var t := String(n["type"])
		if t == "chest" or t == "shop" or t == "rest" or t == "event" or t == "armory":
			var p: Dictionary = reward.plan(n)
			if String(p.get("mode", "")) == "":
				mismatched += 1
			var src := String(n.get("source", ""))
			if src == "":
				mismatched += 1
			checked += 1
	_check(mismatched == 0, "探索节点都有来源与结算模式（%d 个，异常 %d）" % [checked, mismatched])

	# 战斗节点分流后，记录里的 kind 必须与 plan 一致。
	var rt = load(RUNTIME).create(_duel, 1, SEED, 1, false)
	rt.try_move(BATTLE_NEAR_START)
	var r: Dictionary = rt.resolve_battle(true)
	var recorded := String(rt.battles[BATTLE_NEAR_START].get("kind", ""))
	_check(recorded == String(progress.plan(data["by_id"]["m%d" % BATTLE_NEAR_START])["kind"]),
		"战斗记录 kind 与分流计划一致（%s）" % recorded)

	# BOSS 战利品不得混入 chest 来源或地图宝箱物品。
	var boss_room: RoomData = null
	for room in _duel.ALL_ROOMS:
		if room != null and String(room.kind) == "boss" and not bool(room.final_boss) \
				and room.boss_reward_weapons.size() > 0:
			boss_room = room
			break
	if boss_room != null:
		var built: Dictionary = progress.build(
			{"id": "m98", "type": "boss", "cell_id": 98, "source": "room", "room": boss_room}, _duel)
		var leaked := 0
		for c in built["cards"]:
			if String(c.get("kind", "")) == "boss_weapon" \
					and not boss_room.boss_reward_weapons.has(String(c.get("path", ""))):
				leaked += 1
		_check(leaked == 0, "BOSS 武器不来自宝箱来源（越界 %d）" % leaked)


# ---------------------------------------------------------------------------
# 辅助
# ---------------------------------------------------------------------------

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
