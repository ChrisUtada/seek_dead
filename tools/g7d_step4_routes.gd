extends Node

# ============================================================================
# G7-D Step 4 · 多打法路线验证夹具（2026-11-09）
#
# 目的：按计划 Step 4 的五条路线跑**完整战斗**（寒铁精英 / 冰封铁瓮），
#   记录每回合局势、实际停轮目标、消耗品、承伤、回合数、死亡点与残血收尾长度。
#   本夹具是「按提示对策停轮」的理想化全信息 bot：只出方向，不产出平衡结论，
#   不代填真人数据，也不关闭真人出口。
#
# 五条路线：
#   ① 同系三连/爆发：双火武器 + 强袭药剂，优先停伤害符号（三连）
#   ② 异系覆盖/充能：火 + 冰，优先停伤害符号（克制/充能）
#   ③ 护盾/恢复：火剑 + 铁剑 + 守备/神盾/包扎/复苏 + 守备/回春护符 + 治疗药剂
#   ④ 破甲/穿透：火剑 + 破甲弩 + 破甲酸液，优先特殊三连/穿透
#   ⑤ 无净化兜底：双火武器、无消耗品，只用带内符号处理
#
# 运行（必须隔离 APPDATA）：
#   set APPDATA=%TEMP%\seek_dead_probe_appdata
#   Godot_v4.7-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tools/g7d_step4_routes.tscn
#   可选：-- --seeds=3 --seed=9601
#   Step 5 残血尾段：-- --rooms=all --step=5 --out=res://docs/baseline/2026-11-09_g7d_step5
# 产物：docs/baseline/2026-11-09_g7d_step4/report.txt + turns.csv（--out 可改目录）
# ============================================================================

const OUT_DIR := "res://docs/baseline/2026-11-09_g7d_step4"
const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const BASE_SEED := 9601
const SEEDS := 3
const MAX_TURNS := 80
const MAX_WAIT := 16          # 等目标上限（拍）；超过强制停，记为 forced
const ELITE_RIA := 4          # 寒铁精英在 ACT1 的典型房内序号
const BOSS_RIA := 7           # 冰封铁瓮在 ACT1 的典型房内序号（幕末）
const NORMAL_RIA := 2         # 普通房取 ACT1 第 3 个房位（中段，非开场秒杀）
const NORMAL_ROOMS := [
	"res://resources/rooms/a1_brute_none.tres",
	"res://resources/rooms/a1_bulwark_poison.tres",
	"res://resources/rooms/a1_hexer_none.tres",
]

var _duel: DuelController
var _seeds := SEEDS
var _seed0 := BASE_SEED
var _out_dir := OUT_DIR
var _step := 4
var _include_normal := false
var _rows: Array[Dictionary] = []
var _turn_rows: Array[Dictionary] = []
var _lines: Array[String] = []
var _selfcheck_fail := 0


func _ready() -> void:
	await _run()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--seeds="):
			_seeds = maxi(1, int(s.get_slice("=", 1)))
		elif s.begins_with("--seed="):
			_seed0 = int(s.get_slice("=", 1))
		elif s.begins_with("--step="):
			_step = maxi(4, int(s.get_slice("=", 1)))
		elif s.begins_with("--out="):
			_out_dir = s.get_slice("=", 1)
		elif s == "--rooms=all":
			_include_normal = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))

	_duel = load(DUEL_SCENE).instantiate() as DuelController
	add_child(_duel)
	await _frames(8)
	_duel.board_config.enabled = false
	await _frames(2)
	Engine.time_scale = 8.0   # 夹具加速：回合演出计时器按 8× 走，不改变结算逻辑
	print("G7D_STEP4|boot ok")

	var rooms := _sample_rooms()
	if rooms.is_empty():
		print("G7D_STEP4|FAIL 找不到样板房间")
		get_tree().quit(2)
		return

	for room in rooms:
		for route in _routes():
			for i in range(_seeds):
				await _run_battle(route, room, _seed0 + i)

	_write_report()
	var fails := _selfcheck_fail
	print("G7D_STEP4|DONE rows=%d turns=%d selfcheck_fail=%d" % [_rows.size(), _turn_rows.size(), fails])
	get_tree().quit(0 if fails == 0 else 1)


# ---------------------------------------------------------------------------
# 路线与样板
# ---------------------------------------------------------------------------

func _routes() -> Array:
	return [
		{"id": "same_element", "label": "① 同系三连/爆发",
			"weapons": ["fire_sword", "flame_staff"], "skills": [], "charms": [],
			"consumables": ["assault_potion"],
			"prefer": ["symbol_damage"], "mixed": false},
		{"id": "coverage", "label": "② 异系覆盖/充能",
			"weapons": ["fire_sword", "ice_staff"], "skills": [], "charms": [],
			"consumables": ["fire_essence"],
			"prefer": ["symbol_damage"], "mixed": false},
		{"id": "defense", "label": "③ 护盾/恢复",
			"weapons": ["fire_sword", "iron_sword"],
			"skills": ["guard", "aegis", "mend", "renewal"],
			"charms": ["guard_charm", "regen_charm"],
			"consumables": ["heal_potion"],
			"prefer": ["symbol_shield", "symbol_heal", "symbol_damage"], "mixed": false},
		{"id": "armor", "label": "④ 破甲/穿透",
			"weapons": ["fire_sword", "armor_pierce_crossbow"], "skills": [], "charms": [],
			"consumables": ["acid_solvent"],
			"prefer": ["symbol_pierce", "symbol_damage"], "mixed": false},
		{"id": "no_cleanse", "label": "⑤ 无净化兜底",
			"weapons": ["fire_sword", "flame_staff"], "skills": [], "charms": [],
			"consumables": [],
			"prefer": ["symbol_damage"], "mixed": false},
	]


func _sample_rooms() -> Array:
	var out: Array = []
	var wanted: Array = ["寒铁精英", "冰封铁瓮"]
	for r in _duel.ALL_ROOMS:
		if r == null:
			continue
		if String(r.name) in wanted:
			out.append(r)
	if _include_normal:
		for p in NORMAL_ROOMS:
			for r in _duel.ALL_ROOMS:
				if r != null and r.resource_path == String(p):
					out.append(r)
					break
	out.sort_custom(func(a, b):
		var ra := int(DuelController.ROOM_KIND_RANK.get(String(a.kind), 0))
		var rb := int(DuelController.ROOM_KIND_RANK.get(String(b.kind), 0))
		if ra != rb:
			return ra < rb
		return String(a.name) < String(b.name))
	return out


func _weapon_path(id: String) -> String:
	for p in _duel.WEAPON_POOL:
		if p.ends_with(id + ".tres"):
			return String(p)
	return "res://resources/weapon_templates/%s.tres" % id


# ---------------------------------------------------------------------------
# 一场完整战斗
# ---------------------------------------------------------------------------

func _run_battle(route: Dictionary, room: RoomData, s: int) -> void:
	seed(s)
	_duel.selected_loadout.assign(_paths(route["weapons"], "weapon"))
	_duel.selected_skills.assign(_paths(route["skills"], "skill"))
	_duel.selected_charms.assign(_paths(route["charms"], "charm"))
	_duel.selected_consumables.assign(_paths(route["consumables"], "consumable"))
	_duel._confirm_loadout()
	await _frames(4)
	print("G7D_STEP4|route=%s room=%s seed=%d prepared" % [String(route["id"]), String(room.name), s])
	_duel.ROOMS.clear()
	_duel.ROOMS.append(room)
	var ria := NORMAL_RIA
	match String(room.kind):
		"elite":
			ria = ELITE_RIA
		"boss":
			ria = BOSS_RIA
	_duel.start_room_data(room, 0, ria, false)
	await _frames(2)

	var row := {
		"route": String(route["id"]), "label": String(route["label"]),
		"room": String(room.name), "kind": String(room.kind), "seed": s,
		"result": "TIMEOUT", "turns": 0, "taken": 0, "blocked": 0,
		"hp_end": int(_duel.player_hp), "hp_max": int(_duel.player_hp_max),
		"forced": 0, "counter_turns": 0, "situations": {},
		"consumables": {}, "tail_turns": -1, "tail_taken": 0, "tail_started": -1,
		"tail_counter_turns": 0, "tail_dmg": 0,
	}
	var guard := 0
	while guard < MAX_TURNS:
		guard += 1
		if _duel.game_state == DuelController.FlowState.WON:
			row["result"] = "WIN"
			break
		if _duel.game_state == DuelController.FlowState.LOST:
			row["result"] = "LOST"
			break
		if _duel.game_state != DuelController.FlowState.PLAYING:
			await get_tree().process_frame
			continue

		var rd = _duel.readability
		var situation := String(rd.situation)
		row["situations"][situation] = int(row["situations"].get(situation, 0)) + 1
		if rd.counters.size() > 0:
			row["counter_turns"] = int(row["counter_turns"]) + 1
		var target := ""
		var allowed: Array = []
		if bool(route.get("mixed", false)):
			allowed = _allowed_kinds(route)
		else:
			target = _pick_target(route)
		var rec: Dictionary = await _play_turn(target, route)
		rec["route"] = String(route["id"])
		rec["room"] = String(room.name)
		rec["seed"] = s
		rec["turn"] = int(row["turns"]) + 1
		rec["situation"] = situation
		rec["target"] = target if target != "" else "mixed:" + "/".join(allowed)
		rec["target_in_band"] = _in_band(target) if target != "" else true
		rec["counter_count"] = rd.counters.size()
		_turn_rows.append(rec)

		row["turns"] = int(row["turns"]) + 1
		row["taken"] = int(row["taken"]) + int(rec["taken"])
		row["blocked"] = int(row["blocked"]) + int(rec["blocked"])
		row["forced"] = int(row["forced"]) + int(rec["forced"])
		for k in rec["consumables"]:
			row["consumables"][k] = int(row["consumables"].get(k, 0)) + int(rec["consumables"][k])
		# 尾部定义：从「敌人已 ≤25% 且仍存活」的下一回合开始计数（跨线那一回合不算尾部，
		# 因为玩家在该回合开始时仍在打满血段）。避免把一击斩杀记成 1 回合尾部。
		if int(row["tail_started"]) >= 0:
			row["tail_taken"] = int(row["tail_taken"]) + int(rec["taken"])
			row["tail_dmg"] = int(row["tail_dmg"]) + int(rec["enemy_dmg"])
			if int(rec["counter_count"]) > 0:
				row["tail_counter_turns"] = int(row["tail_counter_turns"]) + 1
		if int(row["tail_started"]) < 0 and int(_duel.enemy_hp) > 0 \
			and int(_duel.enemy_hp) <= int(_duel.enemy_hp_max * 0.25):
			row["tail_started"] = int(row["turns"]) + 1

	if String(row["result"]) == "WIN" and int(row["tail_started"]) >= 0 and int(row["tail_started"]) <= int(row["turns"]):
		row["tail_turns"] = int(row["turns"]) - int(row["tail_started"]) + 1
	row["hp_end"] = int(_duel.player_hp)
	_rows.append(row)
	print("G7D_STEP4|route=%s room=%s seed=%d result=%s turns=%d taken=%d" % [
		String(route["id"]), String(room.name), s, String(row["result"]), int(row["turns"]), int(row["taken"])])
	_duel.game_state = DuelController.FlowState.PLAYING
	_duel.hud.hide_meta_screen()


func _paths(ids: Array, kind: String) -> Array[String]:
	var out: Array[String] = []
	for id in ids:
		var k := String(id)
		match kind:
			"weapon":
				out.append(_weapon_path(k))
			"skill":
				out.append("res://resources/skills/%s.tres" % k)
			"charm":
				out.append("res://resources/charms/%s.tres" % k)
			"consumable":
				out.append("res://resources/consumables/%s.tres" % k)
			_:
				out.append(k)
	return out


# 每回合按路线身份选一个「要凑三连」的符号：防御路线重击时凑护盾/治疗，
# 破甲路线有甲时凑特殊/穿透，其余路线凑伤害（异系路线优先克制元素）。
func _pick_target(route: Dictionary) -> String:
	var rd = _duel.readability
	var sit := String(rd.situation)
	var id := String(route["id"])
	if id == "defense" and (sit.begins_with("重击") or sit.begins_with("低血")):
		var p := _counter_path(["symbol_shield", "symbol_heal"], "")
		if p != "":
			return p
	if id == "armor" and int(_duel.enemy_armor) > 0:
		var p2 := _counter_path(["symbol_special", "symbol_pierce"], "")
		if p2 != "":
			return p2
	var elem := ""
	if id == "coverage":
		elem = _counter_element(String(_duel.enemy_element))
	var p3 := _counter_path(["symbol_pierce", "symbol_damage"], elem)
	if p3 != "":
		return p3
	if rd.target_symbol_path != "" and _in_band(String(rd.target_symbol_path)):
		return String(rd.target_symbol_path)
	for strip in _duel.reel_system.reel_strips:
		for entry in strip:
			var sym: SymbolData = entry[0]
			if sym != null and String(sym.kind) == "damage":
				return String(sym.resource_path)
	return ""


func _counter_path(kinds: Array, elem: String) -> String:
	var rd = _duel.readability
	for want_elem in ([true, false] if elem != "" else [false]):
		for kind in kinds:
			for c in rd.counters:
				if String(c.get("kind", "")) != String(kind):
					continue
				var p := String(c.get("path", ""))
				if p == "" or not _in_band(p):
					continue
				if bool(want_elem):
					var sym = load(p)
					if sym == null or String(sym.element) != elem:
						continue
				return p
	return ""


func _counter_element(def: String) -> String:
	for e in ["fire", "ice", "poison", "light", "dark"]:
		if ElementCounter.multiplier(e, def) > 1.0:
			return e
	return ""


func _allowed_kinds(route: Dictionary) -> Array:
	var sit := String(_duel.readability.situation)
	match String(route["id"]):
		"coverage":
			return ["damage"]
		"defense":
			if sit.begins_with("重击") or sit.begins_with("低血"):
				return ["shield", "heal", "damage"]
			return ["damage", "heal"]
		"armor":
			if int(_duel.enemy_armor) > 0:
				return ["special", "damage"]
			return ["damage"]
		_:
			return ["damage"]


func _in_band(path: String) -> bool:
	for strip in _duel.reel_system.reel_strips:
		for entry in strip:
			var sym: SymbolData = entry[0]
			if sym != null and String(sym.resource_path) == path:
				return true
	return false


func _play_turn(target: String, route: Dictionary) -> Dictionary:
	var t = _duel._telemetry
	var taken0 := int(t.damage_taken)
	var blocked0 := int(t.damage_blocked)
	var uses0: Dictionary = t.consumable_uses.duplicate()
	var enemy_hp0 := int(_duel.enemy_hp)
	var player_hp0 := int(_duel.player_hp)
	_maybe_use_consumables(route)

	_duel._on_spin_pressed()
	var seen := {}
	var waited := {0: 0, 1: 0, 2: 0}
	var ours := {}
	var forced := 0
	var guard := 0
	while guard < 4000:
		guard += 1
		if not _duel._busy:
			break
		if _duel.reel_system.spinning:
			for r in DuelController.REELS:
				if _duel.reel_system.reel_stopped[r] or ours.has(r):
					continue
				if _is_mech_col(r):
					continue
				var strip: Array = _duel.reel_system.reel_strips[r]
				if strip.is_empty():
					continue
				var cur: int = int(_duel.reel_system.reel_cursor[r]) % strip.size()
				if int(seen.get(r, -1)) != cur:
					seen[r] = cur
					waited[r] = int(waited.get(r, 0)) + 1
				var sym: SymbolData = strip[cur][0]
				var want := sym != null and String(sym.resource_path) == target
				if want:
					_duel.reel_system.lock_reel(r, false, "player")
					ours[r] = true
				elif int(waited[r]) >= MAX_WAIT:
					_duel.reel_system.lock_reel(r, false, "player")
					ours[r] = true
					forced += 1
		await get_tree().process_frame

	var uses_delta := {}
	for k in t.consumable_uses:
		var d := int(t.consumable_uses[k]) - int(uses0.get(k, 0))
		if d > 0:
			uses_delta[k] = d
	return {
		"taken": int(t.damage_taken) - taken0,
		"blocked": int(t.damage_blocked) - blocked0,
		"enemy_dmg": enemy_hp0 - int(_duel.enemy_hp),
		"player_hp": int(_duel.player_hp),
		"player_hp0": player_hp0,
		"enemy_hp": int(_duel.enemy_hp),
		"forced": forced,
		"consumables": uses_delta,
	}


func _is_mech_col(r: int) -> bool:
	if _duel.frozen_cols.has(r):
		return true
	if int(_duel.pending_jam_reel) == r or int(_duel.pending_lock_reel) == r:
		return true
	return false


# 消耗品策略：只使用路线自带的物品；没有对应物品就跳过。
func _maybe_use_consumables(route: Dictionary) -> void:
	if _duel._busy or _duel.game_state != DuelController.FlowState.PLAYING:
		return
	var allowed: Array = _paths(route["consumables"], "consumable")
	if _duel.player_hp <= int(_duel.player_hp_max * 0.5):
		_use_effect(allowed, "heal")
	if int(_duel.enemy_armor) > 0:
		_use_effect(allowed, "armor_shred")
	if int(_duel.pending_jam_reel) >= 0 or int(_duel.pending_lock_reel) >= 0 or bool(_duel.pending_chaos):
		_use_effect(allowed, "purify")
	if int(_duel.player_frost) > 0 or int(_duel.player_status.get("poison", 0)) > 0:
		_use_effect(allowed, "cleanse")
	if int(_duel.enemy_hp) <= int(_duel.enemy_hp_max * 0.5):
		_use_effect(allowed, "assault")
	var elem := String(_duel.enemy_element)
	if elem != "" and elem != "none":
		_use_effect(allowed, "element")


func _use_effect(allowed: Array, effect: String) -> void:
	for slot in _duel.consumable_slots:
		if int(slot.get("charges", 0)) <= 0:
			continue
		if not allowed.has(String(slot.get("path", ""))):
			continue
		var d = load(String(slot.get("path", "")))
		if d is ItemData and String(d.effect) == effect:
			_duel.consumable_system.use(String(slot["uid"]))
			return


# ---------------------------------------------------------------------------
# 报告
# ---------------------------------------------------------------------------

func _write_report() -> void:
	_lines.clear()
	var tail_note := " · 含普通房残血尾段" if _include_normal else ""
	_lines.append("# G7-D Step %d · 多打法路线验证（夹具读数，不是平衡结论）%s · %s" % [_step, tail_note, Time.get_datetime_string_from_system()])
	_lines.append("")
	_lines.append("> **本表只验证「不同路线能否凭不同打法处理样板」。** bot 按标准提示里的真实对策停轮，")
	_lines.append("> 是理想化全信息停轮；绝对胜负/承伤不能当真人读数，真人数据必须分开读。")
	_lines.append("")
	var sample_txt := "样板「寒铁精英」(ACT1 elite, ria=%d) 与「冰封铁瓮」(ACT1 boss, ria=%d)" % [ELITE_RIA, BOSS_RIA]
	if _include_normal:
		sample_txt += " + 普通房 3 个（ACT1 normal, ria=%d）" % NORMAL_RIA
	_lines.append("协议：headless --fixed-fps 60 · 真实平衡（未改 BALANCE / 任何 .tres） · 玩家真实生命（测存活） ·")
	_lines.append("      %s · 每路线 %d 种子 · 停轮上限 %d 拍 · 回合上限 %d"
		% [sample_txt, _seeds, MAX_WAIT, MAX_TURNS])
	_lines.append("种子：%d..%d" % [_seed0, _seed0 + _seeds - 1])
	_lines.append("")

	_lines.append("## 1. 路线 × 样板汇总")
	_lines.append("")
	_lines.append("| 路线 | 样板 | 种子 | 胜/负/超时 | 回合/场 | 承伤/场 | 格挡/场 | 残血收尾回合 | 残血承伤 | 强制停 | 有对策回合 | 消耗品 |")
	_lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
	for r in _rows:
		_lines.append("| %s | %s | %d | %s | %d | %d | %d | %s | %d | %d | %d | %s |" % [
			String(r["label"]), String(r["room"]), int(r["seed"]),
			String(r["result"]), int(r["turns"]), int(r["taken"]), int(r["blocked"]),
			"-" if int(r["tail_turns"]) < 0 else str(int(r["tail_turns"])),
			int(r["tail_taken"]), int(r["forced"]), int(r["counter_turns"]),
			_consumables_text(r["consumables"])])
	_lines.append("")

	_lines.append("## 2. 按路线聚合（全部样板合计）")
	_lines.append("")
	_lines.append("| 路线 | 场数 | 胜率 | 平均回合 | 平均承伤 | 平均格挡 | 平均残血收尾 | 主要局势 |")
	_lines.append("|---|---|---|---|---|---|---|---|")
	for route in _routes():
		var rs: Array = []
		for r in _rows:
			if String(r["route"]) == String(route["id"]):
				rs.append(r)
		if rs.is_empty():
			continue
		var wins := 0
		var turns := 0
		var taken := 0
		var blocked := 0
		var tail := 0
		var tail_n := 0
		var sits := {}
		for r in rs:
			if String(r["result"]) == "WIN":
				wins += 1
			turns += int(r["turns"])
			taken += int(r["taken"])
			blocked += int(r["blocked"])
			if int(r["tail_turns"]) >= 0:
				tail += int(r["tail_turns"])
				tail_n += 1
			for k in r["situations"]:
				sits[k] = int(sits.get(k, 0)) + int(r["situations"][k])
		_lines.append("| %s | %d | %.0f%% | %.1f | %.1f | %.1f | %s | %s |" % [
			String(route["label"]), rs.size(), 100.0 * float(wins) / float(rs.size()),
			float(turns) / float(rs.size()), float(taken) / float(rs.size()),
			float(blocked) / float(rs.size()),
			"-" if tail_n == 0 else "%.1f" % (float(tail) / float(tail_n)),
			_situations_text(sits)])
	_lines.append("")

	_lines.append("## 3. 残血尾部（敌人 HP ≤25% 起算）")
	_lines.append("")
	_lines.append("| 房型 | 场数 | 有尾部场数 | 尾部总回合 | 尾部有对策回合 | 最长尾部 | 尾部承伤合计 | 尾部伤害合计 |")
	_lines.append("|---|---|---|---|---|---|---|---|")
	for kind in ["normal", "elite", "boss"]:
		var ks: Array = []
		for r in _rows:
			if String(r["kind"]) == String(kind):
				ks.append(r)
		if ks.is_empty():
			continue
		var battles := ks.size()
		var with_tail := 0
		var tail_total := 0
		var tail_counter := 0
		var tail_max := 0
		var tail_taken := 0
		var tail_dmg := 0
		for r in ks:
			var tt := int(r["tail_turns"])
			if tt >= 0:
				with_tail += 1
				tail_total += tt
				tail_max = maxi(tail_max, tt)
			tail_counter += int(r["tail_counter_turns"])
			tail_taken += int(r["tail_taken"])
			tail_dmg += int(r["tail_dmg"])
		_lines.append("| %s | %d | %d | %d | %d | %d | %d | %d |" % [
			_kind_name(String(kind)), battles, with_tail, tail_total, tail_counter, tail_max, tail_taken, tail_dmg])
	_lines.append("")

	_lines.append("## 4. 夹具自检")
	_lines.append("")
	_lines.append("| 检查 | 结果 |")
	_lines.append("|---|---|")
	_add_check("每路线都至少出现一次真实对策", _all_routes_have_counters())
	_add_check("所有目标符号都来自当前带内", _all_targets_in_band())
	_add_check("无净化路线没有使用净化/清净", _no_cleanse_route_clean())
	_add_check("破甲路线在护甲样板中至少使用一次破甲/穿透", _armor_route_used_break())
	_add_check("防御路线至少出现一次护盾/恢复对策", _defense_route_saw_defense())
	_add_check("残血尾段每回合都有真实对策", _tail_turns_have_counters())
	_add_check("残血尾段最长 ≤ 6 回合", _tail_max_turns() <= 6)
	_lines.append("")

	_lines.append("## 5. 怎么读 / 不能怎么读")
	_lines.append("")
	_lines.append("- **能读**：五条路线是否都能走通、每回合标准提示是否给出可执行对策、普通/精英/BOSS 残血尾段长度与对策覆盖、消耗品是否被真实使用。")
	_lines.append("- **不能读**：胜负率与绝对承伤当真人难度；bot 看得见逻辑游标且零反应延迟。")
	_lines.append("- **不能读**：某件装备是否「绝对门票」——需要真人局与选择率；本表只能说明 bot 路线下没有出现单点依赖。")
	_lines.append("")

	var f := FileAccess.open(_out_dir + "/report.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()
	_write_turns_csv()


func _write_turns_csv() -> void:
	var f := FileAccess.open(_out_dir + "/turns.csv", FileAccess.WRITE)
	if f == null:
		return
	f.store_string("route,room,seed,turn,situation,target,counter_count,enemy_dmg,taken,blocked,player_hp,enemy_hp,forced,consumables\n")
	for r in _turn_rows:
		f.store_string("%s,%s,%d,%d,%s,%s,%d,%d,%d,%d,%d,%d,%d,%s\n" % [
			String(r["route"]), String(r["room"]), int(r["seed"]), int(r["turn"]),
			String(r["situation"]).replace(",", " "), String(r["target"]),
			int(r["counter_count"]), int(r["enemy_dmg"]), int(r["taken"]), int(r["blocked"]),
			int(r["player_hp"]), int(r["enemy_hp"]), int(r["forced"]),
			_consumables_text(r["consumables"]).replace(",", " ")])
	f.close()


func _consumables_text(d: Dictionary) -> String:
	if d.is_empty():
		return "-"
	var parts: Array = []
	for k in d:
		parts.append("%s×%d" % [k, int(d[k])])
	return ", ".join(parts)


func _situations_text(d: Dictionary) -> String:
	var parts: Array = []
	for k in d:
		parts.append("%s×%d" % [k, int(d[k])])
	return " · ".join(parts)


func _all_routes_have_counters() -> bool:
	for route in _routes():
		var ok := false
		for r in _rows:
			if String(r["route"]) == String(route["id"]) and int(r["counter_turns"]) > 0:
				ok = true
				break
		if not ok:
			return false
	return true


func _all_targets_in_band() -> bool:
	for r in _turn_rows:
		if not bool(r.get("target_in_band", false)):
			return false
	return true


func _no_cleanse_route_clean() -> bool:
	for r in _rows:
		if String(r["route"]) != "no_cleanse":
			continue
		if int(r["consumables"].get("purify", 0)) > 0 or int(r["consumables"].get("cleanse", 0)) > 0:
			return false
	return true


func _armor_route_used_break() -> bool:
	for r in _rows:
		if String(r["route"]) != "armor" or String(r["room"]) != "寒铁精英":
			continue
		if int(r["consumables"].get("armor_shred", 0)) > 0:
			return true
		for t in _turn_rows:
			if String(t["route"]) == "armor" and String(t["room"]) == "寒铁精英":
				if String(t["target"]).contains("special") or String(t["target"]).contains("flame_special") \
					or String(t["target"]).contains("bolt_shot"):
					return true
	return false


func _defense_route_saw_defense() -> bool:
	for t in _turn_rows:
		if String(t["route"]) != "defense":
			continue
		var tg := String(t["target"])
		if tg.contains("shield") or tg.contains("heal") or tg.contains("/guard.") \
			or tg.contains("/aegis.") or tg.contains("/mend.") or tg.contains("/renewal."):
			return true
	return false


func _kind_name(kind: String) -> String:
	match kind:
		"normal":
			return "普通"
		"elite":
			return "精英"
		"boss":
			return "BOSS"
	return kind


func _tail_turns_have_counters() -> bool:
	for r in _rows:
		if int(r["tail_turns"]) > 0 and int(r["tail_counter_turns"]) < int(r["tail_turns"]):
			return false
	return true


func _tail_max_turns() -> int:
	var m := 0
	for r in _rows:
		m = maxi(m, int(r["tail_turns"]))
	return m


func _add_check(name: String, ok: bool) -> void:
	if not ok:
		_selfcheck_fail += 1
	_lines.append("| %s | %s |" % [name, "✓" if ok else "✗"])


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
