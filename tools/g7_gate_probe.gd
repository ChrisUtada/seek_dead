extends Node

const OUT_DEFAULT := "res://.workbuddy/full_run"
const SEEDS_DEFAULT := [111, 333, 555, 777, 999, 1234]
const STRATEGIES_DEFAULT := ["tactical"]
const STOP_MODELS := ["random", "normal", "skilled", "perfect"]  # 方案 §14.1 四档操作模型
var OUT := OUT_DEFAULT
var SEEDS: Array = SEEDS_DEFAULT
var STRATEGIES: Array = STRATEGIES_DEFAULT
var HIT_RATES: Dictionary = {}   # 普通/熟练档目标停中率：必须真人测量后显式传入，禁止内定
var TIME_SCALE := 40.0

# G7 门禁：可归因成长档位（方案 §4.1 四档：无成长/锋铸/调律/混合成长）。
# 在 boot 后直接注入 mastery 状态（而非 bot 战斗中自由领取），确保组间差异可归因。
var GROWTH_MODE := "mixed"
const GROWTH_MODES := ["no_growth", "forge", "tune", "mixed"]

# G7-2 换装曲线：在指定房间胜利后把第一把武器换成 --swap-weapon 指定的武器，
# 验证「无旧成长」换装后输出是否仍达标（方案 §13.4 换装曲线前置）。
var SWAP_WEAPON := ""       # 空=不换装
var SWAP_AT_ROOM := 8       # 默认 ACT2 第一房（room index 8）
const WEAPON_PATHS := [
	"res://resources/weapon_templates/fire_sword.tres",
	"res://resources/weapon_templates/ice_staff.tres",
]
const FORGE_PER_WEAPON := 2   # 锋铸档：每把武器 2 次锋铸（FORGE_STEP=2 → +4 基础攻击）
const TUNE_PER_WEAPON := 2    # 调律档：每把武器 2 次调律（+2 权重）
var duel: DuelController
var initial_save: Dictionary = {}
var results: Array = []
var mech_stats: Dictionary = {}   # 机制使用率：一局内各机制触发/出现计数

func _bump(key: String, n: int = 1) -> void:
	mech_stats[key] = int(mech_stats.get(key, 0)) + n


func _ready() -> void:
	# 2026-11-11 Step 1：命令行可指定输出目录 / 种子 / 策略，避免每轮改探针：
	#   -- --out=res://docs/baseline/xxx --seeds=111,333 --strategies=aim_only,tactical
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			OUT = arg.substr(6)
		elif arg.begins_with("--seeds="):
			SEEDS = _parse_ints(arg.substr(8))
		elif arg.begins_with("--strategies="):
			STRATEGIES = arg.substr(13).split(",", false)
		elif arg.begins_with("--hit-rates="):
			# --hit-rates=normal:0.5,skilled:0.8；缺失该档键则拒绝运行该档（不内定真人值）
			HIT_RATES = _parse_hit_rates(arg.substr(12))
		elif arg.begins_with("--speed="):
			TIME_SCALE = float(arg.substr(8))
		elif arg.begins_with("--growth-mode="):
			GROWTH_MODE = arg.substr(14)
			if not GROWTH_MODES.has(GROWTH_MODE):
				push_error("G7 gate: 非法成长档位 %s（可选 %s）" % [GROWTH_MODE, str(GROWTH_MODES)])
				get_tree().quit(2)
				return
		elif arg.begins_with("--swap-weapon="):
			SWAP_WEAPON = arg.substr(14)
		elif arg.begins_with("--swap-at-room="):
			SWAP_AT_ROOM = int(arg.substr(15))
	# 普通/熟练档必须显式给停中率，否则拒绝运行，避免用编造值冒充真人近似
	for s in STRATEGIES:
		if (s == "normal" or s == "skilled") and not HIT_RATES.has(s):
			push_error("G0-3b: 策略 %s 缺少真人实测停中率（--hit-rates=%s:0.xx），拒绝运行" % [s, s])
			get_tree().quit(2)
			return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	Engine.time_scale = TIME_SCALE   # 加速全部timer/动画演出（await create_timer 受此影响）
	initial_save = SaveSystem.load_lobby_data().duplicate(true)
	duel = load("res://scenes/duel/duel.tscn").instantiate() as DuelController
	duel.demo_config.enabled = false   # 关闭demo限制，跑完整三幕
	duel.demo_config.act_only = false
	add_child(duel)
	await _wait(0.35)
	for strategy in STRATEGIES:
		for run_seed in SEEDS:
			var result: Dictionary = await _run_one(strategy, run_seed)
			results.append(result)
			_write_json("%s/%s_%d.json" % [OUT, strategy, run_seed], result)
			print("STRATEGY_RUN|%s|%d|%s|rooms=%d|turns=%d|damage=%d|boss=%s" % [strategy, run_seed, result["terminal"], result["rooms"].size(), result["turns"], result["damage_taken"], result["boss"]])
	_write_json(OUT + "/summary.json", {"runs": results,
		"operation_models": {
			"random": "新手/随机：整带均匀随机停，不瞄准（测下限）",
			"normal": "普通目标命中：按 --hit-rates=normal:p 概率命中，失手停相邻格（p 须真人实测）",
			"skilled": "熟练目标命中：按 --hit-rates=skilled:p 概率命中，失手停相邻格（p 须真人实测）",
			"perfect": "完美目押：100% 命中目标，只测上限",
			"tactical": "历史兼容档：完美目押 + 自动喝药（基线 A 口径）",
			"hit_rates_used": HIT_RATES,
			"note": "normal/skilled 无真人实测则拒绝运行；本轮只跑 random + perfect"
		},
		"method": "same seed/loadout/rewards; readable only; G0-3b 四档仅隔离停中能力，统一不自动喝药",
		"balance": {"counter_burst_pct": DuelController.BALANCE.counter_burst_pct, "heal_line_mults": DuelController.BALANCE.heal_line_mults}})
	print("STRATEGY_PROBE|DONE|%d" % results.size())
	get_tree().quit()


# G7 门禁成长注入：组间差异只来自这里，确保可归因。
# - no_growth：mastery.enabled=false，无熟练无铭印
# - forge：每把武器 FORGE_PER_WEAPON 次锋铸
# - tune：每把武器 TUNE_PER_WEAPON 次调律（目标取该武器最高权重 damage 符号）
# - mixed：锋铸+调律都有
func _apply_growth_mode() -> void:
	var m = duel.mastery
	if m == null:
		return
	m.enabled = (GROWTH_MODE != "no_growth")
	if GROWTH_MODE == "no_growth":
		m.imprints.clear()
		return
	# growth 系统：四档都不给额外技艺 growth（把成长收敛到 mastery 轴，便于归因）
	duel.growth.enabled = false
	# 用实际选中配装（_confirm_loadout 后确定），而非硬编码路径——否则注入到未装备武器上无效。
	var slot := 0
	for wp in duel.selected_loadout:
		var forge_n := 0
		var tune_map := {}
		if GROWTH_MODE == "forge" or GROWTH_MODE == "mixed":
			forge_n = FORGE_PER_WEAPON
			# 🔴 关键修正：forge 实际由 weapon_slots 结算（mastery.forge_bonus → weapon_slots.forge_bonus），
			# 写 mastery.imprints["forge"] 无效。必须走 weapon_slots.choose(slot, "forge")。
			if duel.weapon_slots != null and duel.weapon_slots.valid_slot(slot):
				for k in range(FORGE_PER_WEAPON):
					duel.weapon_slots.choose(slot, "forge")
		if GROWTH_MODE == "tune" or GROWTH_MODE == "mixed":
			var wd: WeaponData = load(wp) as WeaponData
			var best_path := ""
			var best_w := -1.0
			if wd != null:
				for sw in wd.symbols:
					if sw == null or sw.symbol == null or String(sw.symbol.kind) != "damage":
						continue
					if sw.weight > best_w:
						best_w = sw.weight
						best_path = String(sw.symbol.resource_path)
			if best_path != "":
				tune_map[best_path] = TUNE_PER_WEAPON
		m.imprints[wp] = {"forge": forge_n, "tune": tune_map, "calibrate": 0, "tyrant": 0}
		slot += 1
	# forge（base_power）与 tune（weight）都在 build_pool 时读取 → 注入后必须重建带子。
	duel._build_pool(duel.selected_loadout)


func _run_one(strategy: String, run_seed: int) -> Dictionary:
	seed(run_seed)
	mech_stats = {}
	if strategy == "dot":
		# DoT 流派验证：强制装备两把自带 DoT 符号的武器（火+光）
		duel.selected_loadout.assign([
			"res://resources/weapon_templates/fire_sword.tres",
			"res://resources/weapon_templates/holy_sword.tres",
		])
	duel.readability.apply_preset("readable")
	duel._confirm_loadout()
	# G7 门禁：按档位注入旧成长状态（可归因——组间差异只来自成长注入）。
	_apply_growth_mode()
	await _wait(0.15)
	var slots_snapshot: Array = []
	if duel.weapon_slots != null:
		slots_snapshot = duel.weapon_slots.snapshot()
	var result := {"strategy": strategy, "seed": run_seed, "growth_mode": GROWTH_MODE,
		"growth_applied": str(duel.mastery.imprints), "mastery_enabled": duel.mastery.enabled,
		"weapon_slots_snapshot": slots_snapshot, "tune_map": str(duel.mastery.tune_map()),
		"terminal": "RUNNING", "rooms": [], "boss": "", "errors": []}
	var current := {}
	var last_key := ""
	var frames := 0
	while frames < 40000:
		frames += 1
		if duel.hud._replace_dialog != null and duel.hud._replace_dialog.visible:
			# 满双武器时选择武器奖励会弹替换层。此前探针一律取消，导致同一奖励被反复选中而卡死
			# （第 7 房精英后的「阻塞」即此路径）。按真实玩家行为替换第一把武器后继续。
			if not duel.selected_loadout.is_empty():
				duel.hud._on_replace_chosen(String(duel.selected_loadout[0]))
			else:
				duel.hud._on_replace_cancelled()
			await get_tree().process_frame
			continue
		if duel.hud.meta_screen.visible:
			result["terminal"] = "WON_GAME"
			duel._on_meta_choice_chosen({"kind": "anvil", "path": ""})
			break
		if duel.game_state == DuelController.FlowState.LOST:
			result["terminal"] = "LOST"
			_end_room(result, current)
			duel._on_overlay_button_pressed()
			break
		if duel.in_interroom:
			duel._on_next_room_pressed()
			await get_tree().process_frame
			continue
		if duel.game_state == DuelController.FlowState.WON:
			_end_room(result, current)
			# G7-2 换装曲线：到达指定房间后，把第一把武器换成目标武器并重建带子。
			if SWAP_WEAPON != "" and duel.room_index == SWAP_AT_ROOM \
				and not bool(result.get("swapped", false)) and ResourceLoader.load(SWAP_WEAPON) != null:
				var old0: String = duel.selected_loadout[0] if duel.selected_loadout.size() > 0 else ""
				if not duel.selected_loadout.has(SWAP_WEAPON):
					duel.selected_loadout[0] = SWAP_WEAPON
					duel._build_pool(duel.selected_loadout)
					result["swapped"] = true
					result["swap_from"] = old0
					result["swap_to"] = SWAP_WEAPON
					result["swap_at_room"] = SWAP_AT_ROOM
			var is_boss_offer := false
			for c in duel.reward_choices:
				if String(c.get("kind", "")).begins_with("boss_"):
					is_boss_offer = true
					break
			if is_boss_offer:
				# BOSS 战利品：优先领遗物（否则跳过会导致遗物/信物/图鉴全 0，机制使用率失真）
				var pick = duel.reward_choices[0]
				for c in duel.reward_choices:
					if String(c.get("kind", "")) == "boss_relic":
						pick = c
						break
				duel._on_boss_reward_chosen(pick)
			elif duel.room_flow.post_battle_active:
				if duel.room_flow.post_battle_has_growth():
					duel.room_flow.auto_pick_post_battle(["growth"])
				else:
					duel.room_flow.auto_pick_post_battle(["build", "supply"])
			else:
				duel._on_reward_skip_pressed()
			await get_tree().process_frame
			continue
		if duel.hud.shop_screen_is_open():
			duel._on_shop_leave_pressed()
			await get_tree().process_frame
			continue
		if duel.game_state == DuelController.FlowState.PLAYING and not duel.in_loadout:
			var key := "%d:%s" % [duel.room_index, duel.enemy_name]
			if key != last_key:
				last_key = key
				var room_trait := ""
				var room_summary := ""
				if duel.current_room != null:
					room_trait = String(duel.current_room.gimmick_params.get("trait", ""))
					room_summary = String(duel.current_room.mechanic_summary)
				current = {"name": duel.enemy_name, "kind": duel.current_room.kind, "hp_start": duel.player_hp,
					"enemy_hp_start": duel.enemy_hp, "turns": 0, "hp_end": duel.player_hp, "finished": false,
					"trait": room_trait, "mechanic_summary": room_summary,
					"armor_start": int(duel.enemy_armor), "armor_max_start": int(duel.enemy_armor_max),
					"frost_start": int(duel.player_frost), "jam_start": int(duel.pending_jam_reel),
					"turn_log": []}
				if duel.current_room.kind == "boss": result["boss"] = duel.enemy_name
			# G0-3b 四操作模型对照：只隔离「停中能力」变量，四档统一不自动喝药。
			# 旧 tactical 策略保留自动喝药以兼容历史基线；perfect/random/normal/skilled 均不喝。
			if strategy == "tactical": _use_consumables()
			var error: String = await _play_turn(strategy, current, run_seed)
			if error != "OK":
				result["errors"].append(error)
				result["terminal"] = error
				break
		else:
			await get_tree().process_frame
	if result["terminal"] == "RUNNING": result["terminal"] = "FRAME_TIMEOUT"
	var telemetry: Dictionary = duel._telemetry.summary()
	result["turns"] = telemetry["turns"]
	result["triples"] = telemetry["triples"]
	result["damage_taken"] = telemetry["damage_taken"]
	result["damage_blocked"] = telemetry["damage_blocked"]
	result["enemy_attacks"] = telemetry["enemy_attacks"]
	result["target_hits"] = telemetry["target_hits"]
	result["stop_total"] = telemetry["stop_total"]
	result["target_hit_rate"] = telemetry["target_hit_rate"]
	result["buffer_queues"] = telemetry["buffer_queues"]
	result["weapon_swaps"] = telemetry["weapon_swaps"]
	result["counter_triples"] = telemetry["counter_triples"]
	result["counter_burst_damage"] = telemetry["counter_burst_damage"]
	result["heal_total"] = telemetry["heal_total"]
	result["heal_overflow_shield"] = telemetry["heal_overflow_shield"]
	result["consumable_uses"] = telemetry["consumable_uses"]
	result["growth"] = {"summary": duel.growth.summary_line(), "mastery": duel.mastery.summary_line()}
	# 遗物/收集品统计
	result["relics_run"] = int(duel.run_relics.size())
	result["charms_owned"] = int(duel.selected_charms.size())
	if duel._codex != null:
		var c = duel._codex
		result["codex"] = {
			"weapon": "%d/%d" % [c.owned_count("weapon"), c.total_count("weapon")],
			"skill": "%d/%d" % [c.owned_count("skill"), c.total_count("skill")],
			"charm": "%d/%d" % [c.owned_count("charm"), c.total_count("charm")],
		}
	mech_stats["relics_owned_max"] = int(duel.run_relics.size())
	result["mech"] = mech_stats
	return result


func _end_room(result: Dictionary, current: Dictionary) -> void:
	if current.is_empty() or bool(current.get("finished", false)): return
	current["finished"] = true
	current["turns"] = duel.turn_count
	current["hp_end"] = duel.player_hp
	current["armor_end"] = int(duel.enemy_armor)
	# 普通怪特性是否在离房前已经触发（shell 在入场即生效，不置 _done，由 armor_max_start 判定）
	# 用 get("_done") 防御：精英/BOSS gimmick 不一定有该字段。
	current["trait_done"] = (duel.current_gimmick.get("_done") == true) if duel.current_gimmick != null else false
	# Step 3：把逐回合窗口压成摘要，便于直接统计「爆发/恢复是否真的出现」。
	var burst_turns: Array = []
	var recovery_turns: Array = []
	for t in (current.get("turn_log", []) as Array):
		var window := String(t.get("window", ""))
		if window == "爆发": burst_turns.append(int(t.get("turn", 0)))
		elif window == "恢复": recovery_turns.append(int(t.get("turn", 0)))
	current["burst_turns"] = burst_turns
	current["recovery_turns"] = recovery_turns
	current["rhythm_seen"] = not burst_turns.is_empty() and not recovery_turns.is_empty()
	(result["rooms"] as Array).append(current)


func _play_turn(strategy: String, current: Dictionary, run_seed: int) -> String:
	# 完美玩家模拟：不依赖视觉目押（高 time_scale 会让目押失真），直接把转轮光标
	# 设到目标符号 index 后 lock_reel(use_visual=false)，100% 精确命中目标 Build 符号。
	# 这样测出的是「最优操作下的通关能力/难度曲线」，而非 AI 的目押水平。
	var turn_rec := {"turn": int(duel.turn_count), "window": "",
		"armor": int(duel.enemy_armor), "frost": int(duel.player_frost),
		"enemy_hp": int(duel.enemy_hp), "hp": int(duel.player_hp)}
	if duel.current_gimmick != null:
		turn_rec["window"] = String(duel.current_gimmick.rhythm_window(duel))
	duel._on_spin_pressed()
	var frames := 0
	var target: String = duel.readability.target_symbol_path
	while frames < 600:
		frames += 1
		if duel.reel_system.spinning:
			# G0-3b 修复：缠绕机制要求按指定方向逐列停，不能像旧探针那样一帧内遍历所有列
			# （顺序不对的列会被 lock_reel 拒绝且不再重试 → 该回合永不结束 → TURN_TIMEOUT）。
			# 每帧只停「当前允许停的一列」：缠绕时服从 entangle_next()，否则取第一个未忙列。
			var r: int = -1
			if duel.debuffs != null and duel.debuffs.entangle_active():
				r = duel.debuffs.entangle_next(duel.reel_system)
			else:
				r = _next_reel()
			if r >= 0 and not duel.reel_system.reel_stopped[r] and not duel.reel_system.is_absorbing(r):
				var strip: Array = duel.reel_system.reel_strips[r]
				if not strip.is_empty():
					# 找目标符号在本列的 index；dot 策略优先 DoT 状态符号
					var idx := -1
					if strategy == "dot":
						for i in range(strip.size()):
							var sym0: Resource = strip[i][0]
							var kv = sym0.get("kind") if sym0 != null else null
							if kv != null and String(kv) == "status":
								idx = i
								break
					if idx < 0:
						for i in range(strip.size()):
							if String(strip[i][0].resource_path) == target:
								idx = i
								break
					var target_idx := idx   # 目标格；perfect 用它，其余档据此计算「是否命中」
					idx = _pick_stop_index(strategy, idx, target_idx, strip.size(), run_seed, r)
					duel.reel_system.reel_cursor[r] = idx
					duel.reel_system.lock_reel(r, false, "player")
		elif not duel._busy:
			_finish_turn(current, turn_rec)
			return "OK"
		await get_tree().process_frame
	_finish_turn(current, turn_rec)
	return "TURN_TIMEOUT"


func _finish_turn(current: Dictionary, turn_rec: Dictionary) -> void:
	turn_rec["armor_end"] = int(duel.enemy_armor)
	turn_rec["frost_end"] = int(duel.player_frost)
	turn_rec["enemy_hp_end"] = int(duel.enemy_hp)
	turn_rec["hp_end"] = int(duel.player_hp)
	# 机制使用率采样：本回合敌人身上的 DoT 状态 + 上一意图类型 + 遗物数
	for st in duel.enemy_status.keys():
		_bump("dot_" + String(st))
	var li: Dictionary = duel.last_enemy_intent
	if not li.is_empty():
		_bump("intent_" + String(li.get("type", "none")))
	_bump("relics_owned_max", 0)   # 占位，结束时会用实际值覆盖
	(current["turn_log"] as Array).append(turn_rec)


func _next_reel() -> int:
	for r in range(duel.reel_system.reel_stopped.size()):
		if not duel.reel_system.reel_stopped[r] and not duel.reel_system.has_pending_stop(r):
			return r
	return -1


func _det_rand(seed_val: int) -> float:
	# 确定性伪随机 [0,1)，不消耗全局 RNG，保证同种子各操作模型可复现对照。
	var x: int = seed_val & 0x7FFFFFFF
	x = (x * 1103515245 + 12345) & 0x7FFFFFFF
	x = (x ^ (x >> 13)) & 0x7FFFFFFF
	x = (x * 1274126177) & 0x7FFFFFFF
	return float(x) / 2147483648.0


func _pick_stop_index(strategy: String, found_idx: int, target_idx: int, strip_size: int, run_seed: int, r: int) -> int:
	if strip_size <= 0:
		return 0
	# perfect / tactical / dot：保持原行为，命中目标（找不到目标则第 0 格）
	if strategy == "perfect" or strategy == "tactical" or strategy == "dot":
		return found_idx if found_idx >= 0 else 0
	var base: int = run_seed + duel.room_index * 100003 + int(duel.turn_count) * 1009 + r * 37
	# random / 新手：不瞄准，整条带均匀随机（测下限）
	if strategy == "random":
		return int(_det_rand(base) * strip_size) % strip_size
	# normal / skilled：按给定停中率命中目标；失手停在相邻格（真人「差一点」近似）
	if strategy == "normal" or strategy == "skilled":
		var p: float = float(HIT_RATES.get(strategy, 0.0))
		if target_idx >= 0 and _det_rand(base) < p:
			return target_idx
		if target_idx >= 0 and strip_size > 1:
			var off: int = 1 if _det_rand(base + 7) < 0.5 else -1
			return (target_idx + off + strip_size) % strip_size
		return int(_det_rand(base + 13) * strip_size) % strip_size
	return found_idx if found_idx >= 0 else 0


func _use_consumables() -> void:
	if duel.player_hp < int(duel.player_hp_max * 0.45) and _use_effect("heal"):
		return
	if duel.pending_jam_reel >= 0 or duel.pending_lock_reel >= 0 or duel.pending_chaos or duel.pending_auto_stop:
		_use_effect("purify")


func _use_effect(effect: String) -> bool:
	for item in duel.consumable_slots:
		var data: Resource = load(item["path"])
		if data != null and data.effect == effect:
			duel.consumable_system.use(item["uid"])
			return true
	return false


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(data, "  "))


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _parse_ints(text: String) -> Array:
	var out: Array = []
	for part in text.split(",", false):
		out.append(int(part.strip_edges()))
	return out


func _parse_hit_rates(text: String) -> Dictionary:
	# 形如 normal:0.5,skilled:0.8；键必须是操作模型名，值为 [0,1] 停中率
	var out: Dictionary = {}
	for part in text.split(",", false):
		var kv := part.split(":", false)
		if kv.size() == 2:
			out[String(kv[0]).strip_edges()] = clampf(float(kv[1].strip_edges()), 0.0, 1.0)
	return out
