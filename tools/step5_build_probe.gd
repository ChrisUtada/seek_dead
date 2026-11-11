extends Node

# ============================================================================
# Step 5 · 多 Build 对照验证（2026-11-11）
# 依据：docs/战斗策略性_统一调优执行方案_2026-11-11.md §9 Step 5
#
# 目的：同一批样板房下，用 6 套合法 Build 各打一遍，记录逐回合局势、目标、
# 消耗品、承伤、回合数、三连/核爆/治疗与死亡点，验证「不同 Build 有不同打法、
# 没有装备是绝对门票、没有唯一操作答案」。
#
# 运行（headless 即可，不截图）：
#   Godot_v4.7-stable_win64_console.exe --headless --fixed-fps 60 --path <项目> \
#     res://tools/step5_build_probe.tscn -- --out=res://docs/baseline/2026-11-11_step5_builds
#   可选：--seeds=666,999  --builds=mono_fire,cross_fire_ice  --rooms=normal_frost,boss_urn
#
# 只读战斗状态并调用现有输入入口；不改结算公式、不写资源、不结算奖励。
# 存档隔离由外层 APPDATA 控制（探针不主动写存档）。
# ============================================================================

const OUT_DEFAULT := "res://docs/baseline/2026-11-11_step5_builds"
const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const W := "res://resources/weapon_templates/"
const C := "res://resources/consumables/"
const S := "res://resources/skills/"
const R := "res://resources/rooms/"

const SEEDS_DEFAULT := [666, 999]
const MAX_TURNS := 20

# —— 样板房（ACT1）——
const ROOMS := {
	"normal_frost": "a1_swarm_ice",       # 冰锋群蝠：首回合冻结 1 列（普通怪早期特性）
	"normal_armor": "a1_bulwark_poison",  # 毒喉壁垒：开局 20 护甲（护甲样板）
	"elite_rust": "a1_elite_brute_ice",   # 寒铁精英：首轮第 2 回合叠甲+冻结
	"boss_urn": "frozen_urn",             # 冰封铁瓮：ACT1 BOSS，蓄势→爆发→恢复
}

# —— Build 定义 ——
# aim = 每回合瞄准的符号（按 resource_path 匹配）；support = 低血时的替代目标。
# belt 为腰带 4 格；defense 类 Build 的低血目标切换到 support（护盾/治疗符号）。
const BUILDS := {
	"mono_fire": {
		"label": "同系三连（火）",
		"weapons": [W + "fire_sword.tres", W + "flame_staff.tres"],
		"skills": [],
		"belt": [C + "heal_potion.tres", C + "purify_potion.tres", C + "cleanse_potion.tres", C + "acid_solvent.tres"],
		"aim": "res://resources/symbols/fire_slash.tres",
		"support": "",
	},
	"cross_fire_ice": {
		"label": "异系组合（火+冰）",
		"weapons": [W + "fire_sword.tres", W + "ice_staff.tres"],
		"skills": [],
		"belt": [C + "heal_potion.tres", C + "purify_potion.tres", C + "cleanse_potion.tres", C + "acid_solvent.tres"],
		"aim": "res://resources/symbols/fire_slash.tres",
		"support": "",
	},
	"defense_recover": {
		"label": "防御恢复（火武+光武，护盾/治疗技能）",
		"weapons": [W + "fire_sword.tres", W + "holy_sword.tres"],
		"skills": [S + "guard.tres", S + "mend.tres"],
		"belt": [C + "heal_potion.tres", C + "purify_potion.tres", C + "cleanse_potion.tres", C + "acid_solvent.tres"],
		"aim": "res://resources/symbols/fire_slash.tres",
		"support": "res://resources/symbols/mend.tres",
	},
	"armor_pierce": {
		"label": "破甲穿透（重弩+战锤）",
		"weapons": [W + "armor_pierce_crossbow.tres", W + "war_hammer.tres"],
		"skills": [],
		"belt": [C + "acid_solvent.tres", C + "heal_potion.tres", C + "heal_potion.tres", C + "purify_potion.tres"],
		"aim": "res://resources/symbols/bolt_shot.tres",
		"support": "",
	},
	"status_dot": {
		"label": "状态持续（毒匕+枯萎长枪）",
		"weapons": [W + "poison_dagger.tres", W + "blight_spear.tres"],
		"skills": [],
		"belt": [C + "heal_potion.tres", C + "purify_potion.tres", C + "cleanse_potion.tres", C + "acid_solvent.tres"],
		"aim": "res://resources/symbols/poison.tres",
		"support": "",
	},
	"no_cleanse": {
		"label": "无净化兜底（火武，腰带无清净/净化）",
		"weapons": [W + "fire_sword.tres", W + "flame_staff.tres"],
		"skills": [],
		"belt": [C + "heal_potion.tres", C + "greater_heal_potion.tres", C + "acid_solvent.tres", C + "assault_potion.tres"],
		"aim": "res://resources/symbols/fire_slash.tres",
		"support": "",
	},
}

var OUT := OUT_DEFAULT
var SEEDS: Array = SEEDS_DEFAULT
var BUILD_KEYS: Array = BUILDS.keys()
var ROOM_KEYS: Array = ROOMS.keys()
var results: Array = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			OUT = arg.substr(6)
		elif arg.begins_with("--seeds="):
			SEEDS = _parse_ints(arg.substr(8))
		elif arg.begins_with("--builds="):
			BUILD_KEYS = arg.substr(9).split(",", false)
		elif arg.begins_with("--rooms="):
			ROOM_KEYS = arg.substr(8).split(",", false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for key in BUILD_KEYS:
		for room_key in ROOM_KEYS:
			for run_seed in SEEDS:
				var res: Dictionary = await _run_match(String(key), String(room_key), int(run_seed))
				results.append(res)
				print("BUILD_RUN|%s|%s|%d|%s|turns=%d|hp=%d/%d|enemy=%d/%d|dmg_taken=%d|burst=%d|heal=%d" % [
					key, room_key, run_seed, res["result"], res["turns"],
					res["hp_end"], res["hp_max"], res["enemy_hp_end"], res["enemy_hp_max"],
					res["damage_taken"], res["counter_burst_damage"], res["heal_total"]])
				_write_json("%s/%s__%s__%d.json" % [OUT, key, room_key, run_seed], res)
	_write_json(OUT + "/summary.json", {"runs": results,
		"builds": BUILDS, "rooms": ROOMS, "seeds": SEEDS,
		"balance": {"counter_burst_pct": DuelController.BALANCE.counter_burst_pct,
			"charge_burst_pct": DuelController.BALANCE.charge_burst_pct,
			"heal_line_mults": DuelController.BALANCE.heal_line_mults}})
	print("BUILD_PROBE|DONE|%d" % results.size())
	get_tree().quit(0)


func _run_match(build_key: String, room_key: String, run_seed: int) -> Dictionary:
	var build: Dictionary = BUILDS[build_key]
	var room: RoomData = load(R + String(ROOMS[room_key]) + ".tres")
	if room == null:
		push_error("step5_build_probe: 房间加载失败 %s" % room_key)
		get_tree().quit(1)
		return {}
	var duel: DuelController = (load(DUEL_SCENE) as PackedScene).instantiate() as DuelController
	add_child(duel)
	await _wait(0.35)
	seed(run_seed)
	duel.board_config.enabled = false
	duel.selected_loadout.assign(build["weapons"])
	duel.selected_skills.assign(build["skills"])
	duel.selected_charms.clear()
	duel.selected_consumables.assign(build["belt"])
	duel.skill_max = maxi(int(build["skills"].size()), 1)
	duel.player_hp_max = int(duel.BALANCE.player_hp_base)
	duel.player_hp = duel.player_hp_max
	# 腰带实例化（等价 LoadoutSystem.confirm_loadout 的消耗品段；不调用 full_reset，避免随机开房）
	duel.consumable_slots.clear()
	var i := 0
	for path in build["belt"]:
		var cd = load(String(path))
		if cd != null:
			duel.consumable_slots.append({"path": String(path), "item_id": String(cd.item_id),
				"charges": int(cd.charges), "uid": "b%d_%d" % [run_seed, i]})
			i += 1
	duel.ROOMS.clear()
	duel.ROOMS.append(room)
	duel.in_loadout = false
	duel.start_room_data(room, 0, 0, false)
	duel.enemy_intent = {}
	duel.reel_system._timer.stop()
	await _wait(0.15)

	var res := {
		"build": build_key, "build_label": String(build["label"]), "room": room_key,
		"room_name": String(room.name), "room_kind": String(room.kind), "seed": run_seed,
		"result": "RUNNING", "turns": 0, "turn_cap": MAX_TURNS,
		"hp_max": int(duel.player_hp_max), "hp_end": 0,
		"enemy_hp_max": int(duel.enemy_hp_max), "enemy_hp_end": 0,
		"enemy_armor_start": int(duel.enemy_armor), "enemy_armor_end": 0,
		"turn_log": [], "windows": {"蓄势": 0, "爆发": 0, "恢复": 0},
		"triple_turns": [], "counter_turns": [], "death_turn": -1,
	}
	var turn := 0
	while turn < MAX_TURNS:
		if duel.game_state != DuelController.FlowState.PLAYING:
			break
		turn += 1
		var used := _use_consumables(duel, build)
		var before := _snapshot(duel)
		var aim_used: String = await _play_turn(duel, String(build["aim"]), String(build["support"]))
		var after := _snapshot(duel)
		var rec := _turn_record(duel, turn, before, after, used)
		rec["aim"] = aim_used.get_file()
		rec["grid_end"] = after["grid"]
		(res["turn_log"] as Array).append(rec)
		if String(rec["window"]) != "":
			res["windows"][String(rec["window"])] = int(res["windows"].get(String(rec["window"]), 0)) + 1
		if bool(rec["triple"]):
			(res["triple_turns"] as Array).append(turn)
		if int(rec["counter_burst"]) > 0:
			(res["counter_turns"] as Array).append(turn)
		if int(rec["hp_end"]) <= 0:
			res["death_turn"] = turn
		await get_tree().process_frame
		if duel.game_state == DuelController.FlowState.LOST:
			res["result"] = "LOST"
			break
		if duel.game_state == DuelController.FlowState.WON:
			res["result"] = "WON"
			break
	if String(res["result"]) == "RUNNING":
		res["result"] = "LOST" if int(duel.player_hp) <= 0 else "TURN_CAP"
	res["turns"] = int(duel.turn_count)
	res["hp_end"] = int(duel.player_hp)
	res["enemy_hp_end"] = int(duel.enemy_hp)
	res["enemy_armor_end"] = int(duel.enemy_armor)
	var tele: Dictionary = duel._telemetry.summary()
	res["damage_taken"] = int(tele["damage_taken"])
	res["damage_blocked"] = int(tele["damage_blocked"])
	res["heal_total"] = int(tele["heal_total"])
	res["heal_overflow_shield"] = int(tele["heal_overflow_shield"])
	res["counter_burst_damage"] = int(tele["counter_burst_damage"])
	res["triples"] = int(tele["triples"])
	res["counter_triples"] = int(tele["counter_triples"])
	res["consumable_uses"] = (tele["consumable_uses"] as Dictionary).duplicate()
	res["telemetry"] = tele
	duel.queue_free()
	await get_tree().process_frame
	return res


func _snapshot(duel: DuelController) -> Dictionary:
	var counters: Array = []
	for c in duel.readability.counters:
		counters.append(String(c.get("short", c.get("label", ""))))
	return {
		"hp": int(duel.player_hp), "shield": int(duel.player_shield),
		"enemy_hp": int(duel.enemy_hp), "armor": int(duel.enemy_armor),
		"frost": int(duel.player_frost), "poison": int(duel.player_status.get("poison", 0)),
		"charge": int(duel.charge_points),
		"intent": String(duel.enemy_intent.get("type", "")),
		"situation": String(duel.readability.situation),
		"counters": counters,
		"grid": _grid_paths(duel),
	}


func _grid_paths(duel: DuelController) -> Array:
	var out: Array = []
	for r in duel.REELS:
		var row: Array = duel.grid[r]
		out.append(String(row[0].resource_path) if row.size() > 0 and row[0] != null else "")
	return out


func _turn_record(duel: DuelController, turn: int, before: Dictionary, after: Dictionary, used: Array) -> Dictionary:
	var window := ""
	if duel.current_gimmick != null:
		window = String(duel.current_gimmick.rhythm_window(duel))
	var tri: bool = false
	var burst := 0
	if duel.combat != null:
		tri = int(duel.combat._turn_armor_cleared) > 0
		burst = int(duel.combat._turn_counter_burst) + int(duel.combat._turn_charge_burst)
	return {
		"turn": turn, "window": window,
		"intent": String(before["intent"]),
		"situation": String(before["situation"]),
		"counters": before["counters"],
		"grid": before["grid"],
		"consumables": used,
		"hp_start": int(before["hp"]), "hp_end": int(after["hp"]),
		"shield_start": int(before["shield"]), "shield_end": int(after["shield"]),
		"enemy_hp_start": int(before["enemy_hp"]), "enemy_hp_end": int(after["enemy_hp"]),
		"armor_start": int(before["armor"]), "armor_end": int(after["armor"]),
		"frost_start": int(before["frost"]), "poison_start": int(before["poison"]),
		"charge_start": int(before["charge"]),
		"triple": tri, "counter_burst": burst,
		"damage_dealt": maxi(0, int(before["enemy_hp"]) - int(after["enemy_hp"])),
		"damage_taken": maxi(0, int(before["hp"]) - int(after["hp"])),
		"heal": maxi(0, int(after["hp"]) - int(before["hp"])),
		"feedback": String(duel.hud.feedback_label.text) if duel.hud.feedback_label != null else "",
	}


func _play_turn(duel: DuelController, aim: String, support: String) -> String:
	var target := aim
	if support != "" and int(duel.player_hp) < int(duel.player_hp_max) * 0.35:
		target = support
	duel._on_spin_pressed()
	var frames := 0
	while frames < 1500:
		frames += 1
		if duel.reel_system.spinning:
			# 按玩家习惯：任一列视觉中心是目标就按停该列，不按列序等待。
			for r in range(duel.REELS):
				if duel.reel_system.reel_stopped[r] or duel.reel_system.has_pending_stop(r):
					continue
				var strip: Array = duel.reel_system.reel_strips[r]
				var vi: int = duel.hud.visual_center_index(r)
				if vi >= 0 and vi < strip.size():
					var path := String(strip[vi][0].resource_path)
					if path == target:
						duel._on_reel_clicked(r)
			if frames > 480 or frames % 60 == 0:
				duel._on_spin_button_pressed()   # 目标长时间不出现 / 冻结或干扰列兜底
		elif not duel._busy:
			return target
		await get_tree().process_frame
	return target


# 与 Step 1–4 相同的消耗品策略：解干扰 → 解冻结/毒 → 低血治疗 → 有甲破甲。
func _use_consumables(duel: DuelController, build: Dictionary) -> Array:
	var used: Array = []
	if duel.pending_jam_reel >= 0 or duel.pending_lock_reel >= 0 or duel.pending_chaos or duel.pending_auto_stop:
		used.append(_use_effect(duel, "purify"))
	if int(duel.player_frost) > 0 or int(duel.player_status.get("poison", 0)) > 0:
		used.append(_use_effect(duel, "cleanse"))
	if int(duel.player_hp) < int(duel.player_hp_max) * 0.55:
		used.append(_use_effect(duel, "heal"))
	if int(duel.enemy_armor) > 0:
		used.append(_use_effect(duel, "armor_shred"))
	# 恢复窗口是输出窗口：有强袭药剂就留给这一回合（与 Step 3/4 的提示口径一致）。
	if duel.current_gimmick != null and String(duel.current_gimmick.rhythm_window(duel)) == "恢复":
		used.append(_use_effect(duel, "assault"))
	return used.filter(func(x): return String(x) != "")


func _use_effect(duel: DuelController, effect: String) -> String:
	for item in duel.consumable_slots:
		var data: Resource = load(String(item["path"]))
		if data != null and String(data.effect) == effect:
			var uid := String(item["uid"])
			duel.consumable_system.use(uid)
			return effect
	return ""


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "  "))


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _parse_ints(text: String) -> Array:
	var out: Array = []
	for part in text.split(",", false):
		out.append(int(part.strip_edges()))
	return out
