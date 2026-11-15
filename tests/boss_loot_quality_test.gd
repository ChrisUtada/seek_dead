extends Node

# BOSS 武器品质空层回退 · P0 回归（2026-11-15）
# 方案：docs/稀有度与掉落概率修正_完整执行计划_2026-11-15.md §5 Step 1
#
# 缺陷：`LootPool.roll_n()` 抽到「主题池里没有的品质层」时直接返回 empty_tier，
# 而 `roll()` 早就做了「只在实际存在且权重 > 0 的品质里重新归一化」的回退。
# 结果是 BOSS 主题池缺某一档时，整组主题武器一起消失（brittle_gargoyle 等 10%~90%）。
#
# 本套在修复前 A / D 必须失败。运行：
#   Godot --headless --fixed-fps 60 --path . res://tests/boss_loot_quality_test.tscn

const LOOT_POOL := preload("res://scripts/systems/loot_pool.gd")
const SOURCE_TABLE := preload("res://scripts/systems/loot_source_table.gd")

const SEED := 20261115
const ACT := 1
const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const ROOM_DIR := "res://resources/rooms"

var _pass := 0
var _fail := 0
var _pool
var _duel


func _ready() -> void:
	await _run()


func _run() -> void:
	await get_tree().process_frame
	_pool = LOOT_POOL.new(null)
	_pool.reset_run(SEED)
	var by_q: Dictionary = _boss_weapons_by_quality()
	_check(by_q.has("uncommon") and by_q.has("rare"),
		"12 BOSS 主题池能取到进阶与稀有样本（%s）" % str(by_q.keys()))
	if not (by_q.has("uncommon") and by_q.has("rare")):
		_finish()
		return

	print("=== A 不完整主题池不能吞掉整组武器 ===")
	_test_no_swallow(by_q)

	print("=== B 同组同品质与无放回 ===")
	_test_same_quality(by_q)

	print("=== C 强制品质不回退 ===")
	_test_forced_quality(by_q)

	print("=== D 排除已装备后仍能回退 ===")
	_test_exclude_fallback(by_q)

	print("=== E 整个池为空才允许无武器 ===")
	_test_empty_pool(by_q)

	print("=== F Step 0 审计：非最终 BOSS 的品质覆盖 ===")
	_audit_bosses()

	print("=== G Step 3 真实 BOSS 奖励入口 ===")
	await _test_real_entry()

	_finish()


# BOSS 来源 + weapon 类别下，按品质各取一件。
func _boss_weapons_by_quality() -> Dictionary:
	var all: Dictionary = _pool.candidates("boss", ACT, {"category": "weapon"})
	var out := {}
	for p in all.get("items", []):
		var e: Dictionary = _pool._entry(String(p))
		var q := String(e.get("rarity", "common"))
		if not out.has(q):
			out[q] = String(p)
	return out


# A：主题池只有进阶 + 基础，BOSS 权重里基础为 0 —— 旧实现抽到稀有/传说就整组消失。
func _test_no_swallow(by_q: Dictionary) -> void:
	var theme: Array = [String(by_q["uncommon"])]
	if by_q.has("common"):
		theme.append(String(by_q["common"]))
	var bad := 0
	var bad_reason := ""
	var wrong_q := 0
	for i in range(80):
		var r: Dictionary = _pool.roll_n("boss", ACT, 3, {"category": "weapon", "theme": theme})
		if not bool(r.get("ok", false)):
			bad += 1
			bad_reason = String(r.get("reason", ""))
			continue
		if String(r.get("quality", "")) != "uncommon":
			wrong_q += 1
	_check(bad == 0, "80 次抽取都返回武器（失败 %d 次，最后原因 %s）" % [bad, bad_reason])
	_check(wrong_q == 0, "合法品质只有进阶，实际品质不得串档（%d 次）" % wrong_q)


# B：同组同品质、路径不重复；同层不足时 short_tier 而不是跨层补满。
func _test_same_quality(by_q: Dictionary) -> void:
	var theme: Array = [String(by_q["uncommon"]), String(by_q["rare"])]
	var mismatched := 0
	var dup := 0
	for i in range(40):
		var r: Dictionary = _pool.roll_n("boss", ACT, 3, {"category": "weapon", "theme": theme})
		if not bool(r.get("ok", false)):
			continue
		var q := String(r.get("quality", ""))
		var seen := {}
		for p in r.get("paths", []):
			var e: Dictionary = _pool._entry(String(p))
			seen[String(p)] = true
			if String(e.get("rarity", "")) != q:
				mismatched += 1
		if seen.size() != (r.get("paths", []) as Array).size():
			dup += 1
	_check(mismatched == 0, "同组武器 rarity 都等于 quality（%d 处不符）" % mismatched)
	_check(dup == 0, "同组路径不重复（%d 组重复）" % dup)

	# 同层只有 1 件却要 3 件：允许 short_tier，不得跨层凑数
	var single: Array = [String(by_q["uncommon"])]
	var r2: Dictionary = _pool.roll_n("boss", ACT, 3, {"category": "weapon", "theme": single})
	_check(bool(r2.get("ok", false)), "单件主题池仍能出武器")
	if bool(r2.get("ok", false)):
		_check((r2.get("paths", []) as Array).size() == 1, "同层不足 3 件只给 1 件（%d）" % (r2.get("paths", []) as Array).size())
		_check(String(r2.get("reason", "")) == "short_tier", "不足数标 short_tier（%s）" % String(r2.get("reason", "")))


# C：forced_quality 指定空层必须原样失败，防止测试接口被回退逻辑破坏。
func _test_forced_quality(by_q: Dictionary) -> void:
	var theme: Array = [String(by_q["uncommon"])]
	var r: Dictionary = _pool.roll_n("boss", ACT, 3, {"category": "weapon", "theme": theme}, "rare")
	_check(not bool(r.get("ok", false)) and String(r.get("reason", "")) == "empty_tier",
		"强制稀有但池里没有稀有 → empty_tier（%s）" % String(r.get("reason", "")))
	var r2: Dictionary = _pool.roll_n("boss", ACT, 3, {"category": "weapon", "theme": theme}, "uncommon")
	_check(bool(r2.get("ok", false)) and String(r2.get("quality", "")) == "uncommon",
		"强制进阶且池里有 → 正常返回")


# D：某品质只有一件，被排除后必须改抽其他合法品质，而不是整组为空。
func _test_exclude_fallback(by_q: Dictionary) -> void:
	var only_uncommon: String = String(by_q["uncommon"])
	var a_rare: String = String(by_q["rare"])
	var theme: Array = [only_uncommon, a_rare]
	var bad := 0
	var not_rare := 0
	for i in range(60):
		var r: Dictionary = _pool.roll_n("boss", ACT, 3,
			{"category": "weapon", "theme": theme, "exclude": [only_uncommon]})
		if not bool(r.get("ok", false)):
			bad += 1
			continue
		if String(r.get("quality", "")) != "rare":
			not_rare += 1
	_check(bad == 0, "排除唯一进阶件后仍每次出武器（失败 %d 次）" % bad)
	_check(not_rare == 0, "此时合法品质只剩稀有（串档 %d 次）" % not_rare)


# E：整个池为空才允许没有武器，且必须给出明确原因。
func _test_empty_pool(by_q: Dictionary) -> void:
	var r: Dictionary = _pool.roll_n("boss", ACT, 3, {"category": "weapon", "theme": []})
	_check(not bool(r.get("ok", false)), "空主题池返回失败")
	_check(String(r.get("reason", "")) != "", "空主题池给出明确原因（%s）" % String(r.get("reason", "")))
	var all: Dictionary = _pool.candidates("boss", ACT, {"category": "weapon"})
	var r2: Dictionary = _pool.roll_n("boss", ACT, 3,
		{"category": "weapon", "exclude": (all.get("items", []) as Array).duplicate()})
	_check(not bool(r2.get("ok", false)), "全部候选被排除时返回失败")


# 非最终 BOSS 且配置了主题武器池的房间（真·最终 BOSS 刻意空池，单独排除）。
func _boss_rooms() -> Array:
	var out: Array = []
	var dir := DirAccess.open(ROOM_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var r = load(ROOM_DIR + "/" + f)
		if r == null or not (r is RoomData):
			continue
		if bool(r.final_boss):
			continue
		if (r.boss_reward_weapons as Array).is_empty():
			continue
		out.append(r)
	return out


# Step 0：逐个 BOSS 输出「主题池覆盖哪些品质 / 修复后哪些层可用」。
# 审计数据全部来自资源与来源表，不硬编码 BOSS 名称或品质。
func _audit_bosses() -> void:
	var rooms: Array = _boss_rooms()
	_check(rooms.size() == 12, "非最终 BOSS 且有主题池的房间 12 个（%d）" % rooms.size())
	var weights: Dictionary = SOURCE_TABLE.weights_for("boss", 1).get("weights", {})
	for r in rooms:
		var cover := {}
		for p in r.boss_reward_weapons:
			var e: Dictionary = _pool._entry(String(p))
			var q := String(e.get("rarity", "common"))
			cover[q] = int(cover.get(q, 0)) + 1
		var usable: Array = []
		var missing: Array = []
		for q in SOURCE_TABLE.QUALITIES:
			if int(weights.get(q, 0)) <= 0:
				continue
			if cover.has(q):
				usable.append(q)
			else:
				missing.append(q)
		print("  [审计] %-18s act%d 覆盖=%s 可用=%s 缺失=%s" % [
			String(r.name), int(r.act), str(cover.keys()), str(usable), str(missing)])
		_check(usable.size() >= 1, "%s 至少有一个可用品质层（可用 %s）" % [String(r.name), str(usable)])
		# 这一行就是修复前的缺陷：缺档的 BOSS 在旧实现里会整组消失。
		if not missing.is_empty():
			print("         ↑ 旧实现缺 %s，会整组消失；修复后回退到 %s" % [str(missing), str(usable)])


# Step 3：不走纯池，直接走 RewardSystem.roll_boss_rewards(room)。
func _test_real_entry() -> void:
	_duel = load(DUEL_SCENE).instantiate()
	add_child(_duel)
	for i in range(4):
		await get_tree().process_frame
	var rs = _duel._reward_system
	var rooms: Array = _boss_rooms()
	_check(rs != null and not rooms.is_empty(), "奖励系统可用且取到 BOSS 房间（%d）" % rooms.size())
	if rs == null or rooms.is_empty():
		return
	var total_missing := 0
	var total_bad_q := 0
	var total_dup := 0
	for r in rooms:
		var missing := 0
		var bad_q := 0
		var dup := 0
		for i in range(20):
			var cands: Array = rs.roll_boss_rewards(r)
			var ws: Array = []
			for c in cands:
				if String(c.get("kind", "")) == "boss_weapon":
					ws.append(c)
			if ws.is_empty():
				missing += 1
				continue
			var q := String(ws[0].get("quality", ""))
			var seen := {}
			for c in ws:
				if String(c.get("quality", "")) != q:
					bad_q += 1
				var p := String(c.get("path", ""))
				if seen.has(p):
					dup += 1
				seen[p] = true
		total_missing += missing
		total_bad_q += bad_q
		total_dup += dup
		_check(missing == 0, "%s：20 次真实奖励都有主题武器（缺 %d 次）" % [String(r.name), missing])
	_check(total_bad_q == 0, "同组主题武器品质一致（%d 处不符）" % total_bad_q)
	_check(total_dup == 0, "同组主题武器不重复（%d 处重复）" % total_dup)
	_check(total_missing == 0, "12 个 BOSS × 20 次都没有空武器（缺 %d 次）" % total_missing)


func _finish() -> void:
	print("BOSSQUALITY|RESULT %s (checks=%d fails=%d)" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + what)
