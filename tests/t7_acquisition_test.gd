extends Node

# ============================================================================
# T7 获取轴 · headless 回归（场景入口，工程约束同 smoke_root）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t7_acquisition_test.tscn
#
# Step 3 起本套件验证「来源品质表 + 统一候选池」的接入，不再验证旧的
# acquisition_weight 加权与 boss_depth_bias：
# ① 商店：货架品质多重集 == loot_shop_ladder[act]（确定性阶梯，可用固定种子复现）；
#    已带护符/技能不上架、BOSS 信物永不上架；
# ② BOSS：主题过滤保留；品质只由 boss 来源行决定，act1 与 act3 分布一致（无深度偏置）；
#    真·最终空主题 → 铁砧兜底。
# ============================================================================

const SHOP_ROLLS := 100
const BOSS_ROLLS := 4000

var _fails := 0
var _checks := 0


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	var duel: DuelController = await _boot()
	if duel == null:
		print("RESULT FAIL (boot)")
		get_tree().quit(2)
		return

	_part_a_shop_ladder(duel)
	_part_b_boss_source(duel)

	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _boot() -> DuelController:
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	return duel


func _rarity_of(path: String) -> String:
	var res: Resource = load(path)
	return String(res.get("rarity")) if res != null and res.get("rarity") != null else "common"


func _is_relic(path: String) -> bool:
	return path.get_file().contains("_relic")


func _quality_counts(paths: Array) -> Dictionary:
	var out := {"common": 0, "uncommon": 0, "rare": 0, "epic": 0}
	for p in paths:
		var r := _rarity_of(String(p))
		out[r] = int(out.get(r, 0)) + 1
	return out


func _same_counts(a: Dictionary, b: Dictionary) -> bool:
	for q in LootSourceTable.QUALITIES:
		if int(a.get(q, 0)) != int(b.get(q, 0)):
			return false
	return true


# ① 商店确定性阶梯
func _part_a_shop_ladder(duel: DuelController) -> void:
	seed(9001)
	duel._reset_run_state()
	var rooms: Array[RoomData] = [duel.ALL_ROOMS[0]]
	duel.ROOMS = rooms
	duel._start_room(0)
	var relic_violations := 0
	var selected_violations := 0
	for act in [1, 2, 3]:
		duel.current_act = act
		var ladder: Array = LootSourceTable.shop_tiers(act)
		_check(ladder.size() == 6, "act%d 商店阶梯为 6 格" % act)
		var want := {"common": 0, "uncommon": 0, "rare": 0, "epic": 0}
		for q in ladder:
			want[String(q)] = int(want.get(String(q), 0)) + 1
		var mismatches := 0
		var size_bad := 0
		for i in SHOP_ROLLS:
			duel._shop_system.roll_shop()
			var paths: Array = []
			for o in duel._shop_system.shop_offers:
				paths.append(String(o["path"]))
				if _is_relic(String(o["path"])):
					relic_violations += 1
				if duel.selected_charms.has(String(o["path"])) or duel.selected_skills.has(String(o["path"])):
					selected_violations += 1
			if duel._shop_system.shop_offers.size() != 6:
				size_bad += 1
			if not _same_counts(_quality_counts(paths), want):
				mismatches += 1
		_check(mismatches == 0, "act%d 货架品质构成 == 阶梯（%d 轮偏差 %d）" % [act, SHOP_ROLLS, mismatches])
		_check(size_bad == 0, "act%d 货架恒为 6 格（异常 %d 轮）" % [act, size_bad])
	_check(relic_violations == 0, "商店永不上架 BOSS 信物（违规 %d）" % relic_violations)
	_check(selected_violations == 0, "已带护符/技能不上架（违规 %d）" % selected_violations)

	# 固定专用种子 → 货架路径序列可复现（质量阶梯本身确定，只验证抽取可复现）
	duel.current_act = 2
	duel._reward_system._loot.reset_run(4242)
	duel._shop_system.roll_shop()
	var first: Array = []
	for o in duel._shop_system.shop_offers:
		first.append(String(o["path"]))
	duel._reward_system._loot.reset_run(4242)
	duel._shop_system.roll_shop()
	var second: Array = []
	for o in duel._shop_system.shop_offers:
		second.append(String(o["path"]))
	_check(first == second, "固定种子下商店货架可复现")


# ② BOSS 来源表：主题过滤 + 品质分布 + 无深度偏置 + 最终 BOSS 兜底
func _part_b_boss_source(duel: DuelController) -> void:
	seed(9002)
	duel._reset_run_state()
	duel.selected_loadout.clear()
	var theme := [
		"res://resources/weapon_templates/iron_sword.tres",      # common
		"res://resources/weapon_templates/abyss_scythe.tres",    # uncommon
		"res://resources/weapon_templates/dawn_blade.tres",      # uncommon
		"res://resources/weapon_templates/holy_sword.tres",      # uncommon
		"res://resources/weapon_templates/fire_sword.tres",      # rare
		"res://resources/weapon_templates/ice_gun.tres",         # rare
		"res://resources/weapon_templates/flame_staff.tres",     # epic
	]
	var weights: Dictionary = LootSourceTable.weights_for("boss", 1)["weights"]
	var table_total := 0
	for q in LootSourceTable.QUALITIES:
		table_total += int(weights.get(q, 0))
	_check(table_total == 100, "boss 来源行权重合计 100（实测 %d）" % table_total)
	var shares := {}
	for act in [1, 3]:
		var tally := {"common": 0, "uncommon": 0, "rare": 0, "epic": 0}
		var outside := 0
		for i in BOSS_ROLLS:
			var res: Dictionary = duel._reward_system._loot.roll_n("boss", act, 3, {
				"category": "weapon", "theme": theme})
			for p in res.get("paths", []):
				if not theme.has(String(p)):
					outside += 1
			if bool(res.get("ok", false)):
				var q := String(res["quality"])
				tally[q] = int(tally.get(q, 0)) + 1
		_check(outside == 0, "act%d BOSS 候选全部来自主题池（越界 %d）" % [act, outside])
		var total := 0
		for q in tally:
			total += int(tally[q])
		for q in LootSourceTable.QUALITIES:
			var exp: float = float(weights.get(q, 0)) / 100.0
			var obs: float = float(tally.get(q, 0)) / maxf(1.0, float(total))
			_check(absf(obs - exp) <= 0.025,
				"act%d boss %s 占比 %.3f ≈ 表 %.3f" % [act, q, obs, exp])
		shares[act] = tally

	# 无深度偏置：同一主题池 act1 与 act3 的品质频数应高度一致（表不随幕变化）
	for q in LootSourceTable.QUALITIES:
		var a: float = float(shares[1].get(q, 0))
		var b: float = float(shares[3].get(q, 0))
		_check(absf(a - b) <= float(BOSS_ROLLS) * 0.03,
			"boss %s 不受幕次偏置（act1 %.0f vs act3 %.0f）" % [q, a, b])

	# 真·最终 BOSS：空主题 → 无武器候选，注入铁砧兜底卡
	var fin: RoomData = null
	for r in duel.ALL_ROOMS:
		if r.final_boss:
			fin = r
			break
	if fin == null:
		_fail("缺少 final_boss 房间")
		return
	fin.boss_relic_path = ""
	duel.selected_charms.clear()
	var cands: Array = duel._reward_system.roll_boss_rewards(fin)
	_check(cands.size() == 1 and String(cands[0].get("kind", "")) == "boss_anvil",
		"真·最终 BOSS 空主题 → 铁砧兜底卡")


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("PASS  ", label)
	else:
		_fails += 1
		printerr("FAIL  ", label)


func _fail(label: String) -> void:
	_checks += 1
	_fails += 1
	printerr("FAIL  ", label)
