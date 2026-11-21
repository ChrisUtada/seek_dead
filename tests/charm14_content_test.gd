extends Node

# #14 护符补齐内容验证（2026-11-21）
# 验证新增两件机制护符(荆棘胸甲 thorns / 蚀纹符 dot_amp)的可获取性、装配、图鉴。

var _fails := 0
var _checks := 0
const THORN := "res://resources/charms/thorn_plate.tres"
const VENOM := "res://resources/charms/venom_lattice.tres"

func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("CHARM14 FAIL: " + label)

func _ready() -> void:
	await get_tree().process_frame
	SaveSystem.reset_lobby_data()
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.demo_config.enabled = false
	duel._confirm_loadout()
	await get_tree().process_frame

	# ① 资源可加载 + 字段正确
	for entry in [[THORN, "thorns", "defense"], [VENOM, "dot_amp", "damage"]]:
		var p: String = entry[0]
		var res = load(p)
		_ok(res != null, "护符资源可加载：%s" % p.get_file())
		if res != null:
			_ok(String(res.effect) == String(entry[1]), "%s effect 正确" % p.get_file())
			_ok(String(res.role) == String(entry[2]), "%s role 正确" % p.get_file())
			_ok(String(res.rarity) == "uncommon", "%s 稀有度 uncommon" % p.get_file())
			_ok(String(res.downside_effect) != "", "%s 有代价" % p.get_file())

	# ② 图鉴池包含（ITEM_POOL）
	_ok(duel.ITEM_POOL.has(THORN) and duel.ITEM_POOL.has(VENOM), "两件护符在图鉴池 ITEM_POOL")
	var entries: Array = duel._codex.list_entries("passive")
	var paths: Array = []
	for e in entries: paths.append(String(e.get("path", "")))
	_ok(paths.has(THORN) and paths.has(VENOM), "图鉴可列出两件护符")
	_ok(duel._codex.detail_lines(THORN).size() > 0, "图鉴详情可读")

	# ③ LootPool 各来源候选（按 source_tags: elite/shop/chest）
	var loot = duel._reward_system._loot
	for source in ["elite", "shop", "chest"]:
		var pool: Dictionary = loot.candidates(source, 1, {"category": "passive"})
		var items: Array = pool.get("items", [])
		_ok(items.has(THORN) and items.has(VENOM), "来源 %s 候选含两件护符" % source)
	# 普通/boss 不含（source_tags 未列）
	var npool: Dictionary = loot.candidates("normal", 1, {"category": "passive"})
	_ok(not (npool.get("items", []) as Array).has(THORN), "普通来源不含新护符（符合 source_tags）")

	# ④ 商店 ladder：uncommon passive 槽是否可买到
	var shop_hits := 0
	for i in range(80):
		duel._shop_system.roll_shop()
		for off in duel._shop_system.shop_offers:
			var op: String = String(off.get("path", ""))
			if op == THORN or op == VENOM: shop_hits += 1
	_ok(shop_hits > 0, "商店 ladder 可产出新护符（80 次命中 %d）" % shop_hits)

	# ⑤ 生涯定向候选包含
	var cands: Array = duel._career.directed_candidates()
	var cpaths: Array = []
	for c in cands: cpaths.append(String(c.get("path", "")))
	_ok(cpaths.has(THORN) and cpaths.has(VENOM), "生涯定向候选含两件新护符")

	# ⑥ 装配后机制生效
	duel.meta["owned_charms"] = [THORN, VENOM]
	duel.selected_charms = [THORN, VENOM]
	duel._apply_charms()
	_ok(duel.charm_thorns >= 0.15 - 0.001, "荆棘胸甲反弹倍率生效（%.2f）" % duel.charm_thorns)
	_ok(duel.charm_dot_amp >= 1, "蚀纹符挂层 +1 生效（%d）" % duel.charm_dot_amp)

	print("CHARM14 RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
