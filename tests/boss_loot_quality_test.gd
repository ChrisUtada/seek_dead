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

# T3 阶段 1 遗留收口（2026-11-27）：主题可用品质集合的显式期望表。
#
# 口径：「主题可用品质」= candidates() 在归档过滤后真实存在的品质，再与 boss 来源表
# 权重大于 0 的品质（uncommon/rare/epic）取交集。boss 来源表 common=0，故 common
# 不进入本表（铁剑只作为主题池的排除/覆盖项存在，永远不会被 BOSS 抽出）。
#
# 这张表是硬编码的人工期望，不得用实际结果反推：今后任何主题池退化（例如正式池
# 某档最后一件被归档、或主题映射被改动），必须显式修改本表才可能重新变绿，
# 不允许测试自证。键 = resources/rooms 下的文件名（去掉 .tres）。
#
# 当前缺口（2026-11-27 逐条核对）：9 个 BOSS 的 uncommon 档全部是已归档武器
# （abyss_scythe / cinder_cleaver / sin_blade / frozen_spear / holy_mace /
# radiant_saber / shadow_guillotine），过滤后该档为空，只剩 rare+epic；
# 主题三档齐全的只有 acid_ghoul（dawn_bow）/ maze_whisperer / whispering_cultist。
const BOSS_QUALITY_SETS := {
	"abyss_watcher": ["rare", "epic"],       # abyss_scythe(uncommon) 已归档；eclipse(epic)/night_scythe(rare)
	"acid_ghoul": ["uncommon", "rare", "epic"],      # dawn_bow(uncommon) 仍在池
	"brittle_gargoyle": ["rare", "epic"],    # cinder_cleaver(uncommon) 已归档
	"cocoon_sentinel": ["rare", "epic"],     # cinder_cleaver(uncommon) 已归档
	"frozen_urn": ["rare", "epic"],          # cinder_cleaver(uncommon) 已归档
	"grand_inquisitor": ["rare", "epic"],    # sin_blade(uncommon) 已归档
	"manic_elementalist": ["rare", "epic"],  # frozen_spear(uncommon) 已归档
	"maze_whisperer": ["uncommon", "rare", "epic"],  # dawn_bow(uncommon) 仍在池
	"nameless_void": ["rare", "epic"],       # holy_mace / radiant_saber(uncommon) 均已归档
	"scale_inquisitor": ["rare", "epic"],    # shadow_guillotine(uncommon) 已归档
	"shattered_king": ["rare", "epic"],      # frozen_spear(uncommon) 已归档
	"whispering_cultist": ["uncommon", "rare", "epic"],  # dawn_bow(uncommon) 仍在池
}

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

	print("=== H Step 4 全品质覆盖后的实际分布 ===")
	_test_distribution()

	print("=== I 主题可用品质集合（显式期望表） ===")
	_test_theme_quality_sets()

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


# Step 4 完成标准：每个 BOSS 的抽样分布 = boss 来源表权重在「该主题当前仍可掉落品质」上的
# 重新归一化（与 LootPool.roll_n 的空层回退同口径）。
# T3 阶段 1 归档后，部分 BOSS 主题池不再包含 uncommon 档，实际分布相应归一化为 rare/epic
# 两档（不再是固定 10/60/30）；主题仍含三档时仍应等于 10/60/30。
func _test_distribution() -> void:
	var rooms: Array = _boss_rooms()
	var bad: Array[String] = []
	for r in rooms:
		var opts := {"category": "weapon", "theme": r.boss_reward_weapons}
		var want_by_q := _expected_shares(r)
		var counts := {"common": 0, "uncommon": 0, "rare": 0, "epic": 0}
		var total := 0
		for i in range(10000):
			var res: Dictionary = _pool.roll_n("boss", int(r.act), 1, opts)
			if bool(res.get("ok", false)):
				var q := String(res.get("quality", ""))
				counts[q] = int(counts.get(q, 0)) + 1
				total += 1
		var line := "%s: " % String(r.name)
		var ok_all := true
		for q in ["uncommon", "rare", "epic"]:
			var pct: float = 100.0 * float(counts[q]) / maxf(1.0, float(total))
			var want: float = float(want_by_q.get(q, 0.0))
			line += "%s %.1f%%(期望%.1f) " % [q, pct, want]
			if absf(pct - want) > 2.0:
				ok_all = false
		if int(counts["common"]) != 0:
			ok_all = false
			line += "common %d(应为0) " % int(counts["common"])
		print("  [分布] " + line)
		if not ok_all:
			bad.append(String(r.name))
	_check(bad.is_empty(), "12 个 BOSS 的分布与来源表（按可用品质归一化）一致（不符：%s）" % str(bad))


# 该 BOSS 主题池在归档过滤后仍可掉落的品质 → 来源表权重归一化百分比。
func _expected_shares(room) -> Dictionary:
	var out := {"common": 0.0, "uncommon": 0.0, "rare": 0.0, "epic": 0.0}
	var opts := {"category": "weapon", "theme": room.boss_reward_weapons}
	var pool: Dictionary = _pool.candidates("boss", int(room.act), opts)
	var present := {}
	for p in (pool.get("items", []) as Array):
		var rarity := String(_pool._entry(String(p)).get("rarity", ""))
		if rarity != "":
			present[rarity] = true
	var weights: Dictionary = SOURCE_TABLE.weights_for("boss", int(room.act)).get("weights", {})
	var total := 0
	for q in ["uncommon", "rare", "epic"]:
		if present.has(q):
			total += int(weights.get(q, 0))
	if total <= 0:
		return out
	for q in ["uncommon", "rare", "epic"]:
		if present.has(q):
			out[q] = 100.0 * float(weights.get(q, 0)) / float(total)
	return out


# 主题可用品质集合：candidates() 归档过滤后真实存在 ∩ boss 来源表权重 > 0 的品质。
func _theme_quality_set(room) -> Array:
	var opts := {"category": "weapon", "theme": room.boss_reward_weapons}
	var pool: Dictionary = _pool.candidates("boss", int(room.act), opts)
	var present := {}
	for p in (pool.get("items", []) as Array):
		var q := String(_pool._entry(String(p)).get("rarity", ""))
		if q != "":
			present[q] = true
	var out: Array = []
	for q in ["uncommon", "rare", "epic"]:
		if present.has(q):
			out.append(q)
	return out


# I：12 个 BOSS 的主题可用品质集合必须与 BOSS_QUALITY_SETS 完全相等。
# 单条聚合断言：期望表缺项、多出项、集合不一致都算不符。
func _test_theme_quality_sets() -> void:
	var rooms: Array = _boss_rooms()
	var seen := {}
	var bad: Array[String] = []
	for r in rooms:
		var key := String(r.resource_path).get_file().get_basename()
		seen[key] = true
		if not BOSS_QUALITY_SETS.has(key):
			bad.append("%s(期望表未登记)" % key)
			continue
		var want: Array = BOSS_QUALITY_SETS[key]
		var got: Array = _theme_quality_set(r)
		print("  [品质集合] %-18s 期望=%s 实测=%s" % [String(r.name), str(want), str(got)])
		if got != want:
			bad.append("%s 实测%s≠期望%s" % [key, str(got), str(want)])
	for key in BOSS_QUALITY_SETS.keys():
		if not seen.has(String(key)):
			bad.append("%s(期望表多出，无对应 BOSS)" % String(key))
	_check(bad.is_empty(), "12 个 BOSS 主题可用品质集合与显式期望表完全相等（不符：%s）" % str(bad))


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
