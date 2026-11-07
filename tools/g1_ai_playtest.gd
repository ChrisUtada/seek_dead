extends Node

# G1 AI-assisted playtest. Uses the production DuelController and real action entry points.
# It records observations, not human opinions or human reaction performance.

const OUT_ROOT := "res://docs/baseline/2026-11-06_g1_ai"
const DUEL_SCENE := "res://scenes/duel/duel.tscn"

var _duel: DuelController
var _suite := "linear"
var _out_dir := ""
var _shots := {}
var _stop_audit: Array = []
var _pending_visual := {}
var _stop_seen := 0
var _resume := false
var _only: Array = []
var _out_override := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--g1-suite="):
			_suite = String(arg).trim_prefix("--g1-suite=")
		if String(arg) == "--g1-resume":
			_resume = true
		if String(arg).begins_with("--g1-only="):
			_only = Array(String(arg).trim_prefix("--g1-only=").split(",", false))
		if String(arg).begins_with("--g1-out="):
			_out_override = String(arg).trim_prefix("--g1-out=")
	_out_dir = "%s/%s" % [OUT_ROOT, _out_override if _out_override != "" else _suite]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	get_window().size = Vector2i(960, 540)
	_duel = load(DUEL_SCENE).instantiate() as DuelController
	_duel.demo_config.enabled = true
	add_child(_duel)
	await _wait(0.4)
	var specs: Array = []
	match _suite:
		"linear":
			for i in 3: specs.append({"label": "R%d" % (i+1), "seed": 1101+i, "board": false, "preset": "control"})
		"board":
			for i in 4: specs.append({"label": "B%d" % (i+1), "seed": 2201+i, "board": true, "preset": "control"})
		"ab":
			for i in 6: specs.append({"label": "C%d" % (i+1), "seed": 3301+i, "board": false, "preset": "control"})
			for i in 6: specs.append({"label": "V%d" % (i+1), "seed": 4401+i, "board": false, "preset": "readable"})
		"audit":
			specs.append({"label": "C1", "seed": 3301, "board": false, "preset": "control"})
			specs.append({"label": "V1", "seed": 4401, "board": false, "preset": "readable"})
		"single":
			specs.append({"label": "F1", "seed": 5501, "board": false, "preset": "control"})
		_:
			push_error("Unknown G1 suite: " + _suite)
			get_tree().quit(2)
			return
	if not _only.is_empty():
		specs = specs.filter(func(s): return String(s["label"]) in _only)
	var results: Array = []
	for spec in specs:
		var label := String(spec["label"])
		var existing := "%s/%s.json" % [_out_dir, label]
		if _resume and FileAccess.file_exists(existing):
			var loaded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(existing))
			results.append(loaded)
			print("G1_RESUME|%s|%s" % [label, loaded.get("terminal", "")])
			continue
		var result: Dictionary = await _run_one(spec)
		results.append(result)
		_write_json("%s/%s.json" % [_out_dir, label], result)
		print("G1_RUN|%s|%s|%.1fs|boss=%s|rooms=%d" % [label, result["terminal"], result["seconds"], result["boss"], (result["rooms"] as Array).size()])
	var summary := {"suite": _suite, "tester": "AI-assisted production-flow driver", "runs": results, "stop_audit": _stop_audit}
	_write_json("%s/summary.json" % _out_dir, summary)
	print("G1_SUITE|DONE|%s|runs=%d|stop_audit=%d" % [_suite, results.size(), _stop_audit.size()])
	get_tree().quit()


func _run_one(spec: Dictionary) -> Dictionary:
	seed(int(spec["seed"]))
	_duel.board_config.enabled = bool(spec["board"])
	_duel.readability.apply_preset(String(spec["preset"]))
	_duel._confirm_loadout()
	await _wait(0.25)
	var started := Time.get_ticks_msec()
	var result := {
		"label": spec["label"], "seed": spec["seed"], "mode": "board" if spec["board"] else "linear",
		"preset": spec["preset"], "start_time": Time.get_datetime_string_from_system(),
		"terminal": "RUNNING", "seconds": 0.0, "boss": "", "rooms": [], "selections": [],
		"m1": {"single_screen": true, "offers": [], "deferred_id": "", "deferred_kept": false, "deferred_seen_next": false},
		"board": {"rolls": [], "path": [], "fork_a": "", "fork_b": "", "items": [], "confirmations": [], "boss_map": [], "continue_seen": false, "fork_descs": []},
		"shots": [], "errors": [],
	}
	if _duel.selected_loadout.size() < 2:
		result["errors"].append("默认配装少于双武器")
		result["terminal"] = "LOADOUT_ERROR"
		return result
	if bool(spec["board"]):
		if not _duel.node_mode or _duel.board.node_count() != 25:
			result["errors"].append("棋盘版本/节点数不符合 25 节点要求")
			result["terminal"] = "VERSION_ERROR"
			return result
		for id in _duel.board.boss_ids:
			var bn: Dictionary = _duel.board.node_by_id(id)
			var br: RoomData = bn.get("room")
			result["board"]["boss_map"].append("%s=%s(%s)" % [id, br.name, ElementCounter.label(br.element)])
		for id in ["n6", "n9", "n12"]:
			result["board"]["fork_descs"].append(String(_duel.board.node_by_id(id).get("desc", "")))
	else:
		if _duel.node_mode or _duel.ROOMS.size() != 8:
			result["errors"].append("线性版本/房间数不符合 8 房要求")
			result["terminal"] = "VERSION_ERROR"
			return result
	await _shot(result, "start")

	var current_battle := {}
	var battle_key := ""
	var deferred_id := ""
	var deferred_pending := false
	var last_node := ""
	var frames := 0
	while frames < 50000:
		frames += 1
		if _duel.hud._replace_dialog != null and _duel.hud._replace_dialog.visible:
			await _shot(result, "replace")
			var post_battle: bool = bool(_duel.room_flow.post_battle_active)
			_duel.hud._on_replace_cancelled()
			if post_battle:
				# 满双武器时战后「构筑」位会给武器卡；取消替换会回到同一三槽屏，
				# 再点同一张卡会无限弹层。改选补给/成长，仍失败则放弃本次成长。
				_pick_post_battle(["supply", "growth"], result)
				result["m1"]["replace_cancelled"] = int(result["m1"].get("replace_cancelled", 0)) + 1
			await get_tree().process_frame
			continue
		if _duel.hud._camp_dialog != null and _duel.hud._camp_dialog.visible:
			_duel._camp_leave()
			await get_tree().process_frame
			continue
		if _duel.hud.meta_screen.visible:
			result["terminal"] = "WON_GAME"
			await _shot(result, "end")
			_duel._on_meta_choice_chosen({"kind": "anvil", "path": "", "icon": "", "label": "", "desc": ""})
			break
		if _duel.game_state == DuelController.FlowState.LOST:
			result["terminal"] = "LOST"
			_end_battle(result, current_battle)
			await _shot(result, "end")
			_duel._on_overlay_button_pressed()
			break
		if _duel.in_interroom:
			_duel._on_next_room_pressed()
			await get_tree().process_frame
			continue
		if _duel.game_state == DuelController.FlowState.WON:
			_end_battle(result, current_battle)
			if _duel.room_flow.post_battle_active:
				var offer: Array = _duel.room_flow.post_offer()
				var titles: Array = []
				var slots: Array = []
				for c in offer:
					titles.append(String(c.get("title", "")))
					slots.append(String(c.get("slot", "")))
				(result["m1"]["offers"] as Array).append({"room": _duel.room_index+1, "titles": titles, "slots": slots})
				if slots != ["supply", "build", "growth"]:
					result["m1"]["single_screen"] = false
				await _shot(result, "growth")
				var growth: Dictionary = _duel.room_flow.post_battle_growth_candidate()
				if not growth.is_empty():
					var gid := String(growth.get("growth_id", ""))
					if deferred_id == "":
						deferred_id = gid
						_pick_post_battle(["supply", "build"], result)
						deferred_pending = not _duel._post_battle.queue.is_empty()
						result["m1"]["deferred_kept"] = deferred_pending
					else:
						if deferred_pending and gid == deferred_id:
							result["m1"]["deferred_seen_next"] = true
						_pick_post_battle(["growth", "supply", "build"], result)
					result["selections"].append("成长:" + String(growth.get("title", "")))
				else:
					var prefer: Array = ["supply"] if _duel.player_hp < _duel.player_hp_max/2 else ["build", "supply"]
					_pick_post_battle(prefer, result)
				await get_tree().process_frame
				continue
			# BOSS keeps its dedicated loot screen; skip only after recording that it is not a three-slot screen.
			if _duel.reward_is_boss:
				await _shot(result, "boss_loot")
			_duel._on_reward_skip_pressed()
			await get_tree().process_frame
			continue
		if _duel.hud.shop_screen_is_open():
			await _shot(result, "shop")
			_duel._on_shop_leave_pressed()
			await get_tree().process_frame
			continue
		if _duel.hud.board_screen.visible:
			var board = _duel.board
			var scr = _duel.hud.board_screen
			if board.dice > 0 and scr._advance_btn.text.contains("继续"):
				result["board"]["continue_seen"] = true
			if board.current_id != last_node:
				last_node = board.current_id
				var cur: Dictionary = board.current_node()
				(result["board"]["path"] as Array).append(last_node + ":" + String(cur.get("title", cur.get("type", ""))))
				if String(cur.get("type", "")) in ["weapon", "charm"]:
					(result["board"]["items"] as Array).append(String(cur.get("title", "")))
			if not scr._pending_node.is_empty():
				var pending: Dictionary = scr._pending_node
				var r: RoomData = pending.get("room")
				var txt := "%s|%s|%s" % [scr._confirm_enemy.text, scr._confirm_stats.text, scr._confirm_btn.text]
				(result["board"]["confirmations"] as Array).append(txt)
				await _shot(result, "confirm_" + String(pending.get("id", "")))
				scr._on_confirm_battle()
				await get_tree().process_frame
				continue
			if board.dice == 0:
				if not scr._moving and not scr._stepping:
					scr._on_advance()
					if board.last_roll > 0:
						(result["board"]["rolls"] as Array).append(board.last_roll)
			else:
				var legal: Array = board.legal_targets()
				if legal.size() > 1:
					var pick := _choose_branch(String(spec["label"]), legal)
					var pid := String(pick["id"])
					if pid in ["n7", "n10"]:
						result["board"]["fork_a"] = "上路" if pid == "n7" else "下路"
					if pid in ["n13", "n15", "n17", "n19"]:
						result["board"]["fork_b"] = pid
					scr._on_node_pressed(pid)
				else:
					scr._on_advance()
			await get_tree().process_frame
			continue
		if _duel.game_state == DuelController.FlowState.PLAYING and not _duel.in_loadout:
			var key := "%s:%d:%s" % [_duel.board.current_id if _duel.node_mode else "linear", _duel.room_index, _duel.enemy_name]
			if key != battle_key:
				battle_key = key
				current_battle = {"key": key, "name": _duel.enemy_name, "kind": _duel.current_room.kind,
					"turns": 0, "hp_start": _duel.player_hp, "hp_end": _duel.player_hp,
					"hp_max": _duel.player_hp_max, "near_death": false, "finished": false}
				if _duel.current_room.kind == "boss":
					result["boss"] = _duel.enemy_name
					await _shot(result, "boss")
			_auto_consume()
			var turn_result: String = await _play_turn()
			current_battle["hp_end"] = _duel.player_hp
			current_battle["near_death"] = bool(current_battle["near_death"]) or _duel.player_hp <= int(_duel.player_hp_max*0.25)
			if turn_result != "OK":
				result["errors"].append(turn_result)
				result["terminal"] = turn_result
				break
		else:
			await get_tree().process_frame
	if result["terminal"] == "RUNNING":
		result["terminal"] = "FRAME_TIMEOUT"
	result["seconds"] = float(Time.get_ticks_msec()-started)/1000.0
	result["end_time"] = Time.get_datetime_string_from_system()
	result["growth"] = {"summary": _duel.growth.summary_line(), "mastery": _duel.mastery.summary_line(),
		"level": _duel.growth.level, "perks": _duel.growth.perk_ids.duplicate()}
	result["telemetry"] = _duel._telemetry.summary()
	return result


func _pick_post_battle(prefer: Array, result: Dictionary) -> bool:
	var picked: bool = _duel.room_flow.auto_pick_post_battle(prefer)
	if not picked:
		# 空候选 / 失效候选不允许让驱动空转：走真实「放弃本次成长」入口收尾。
		_duel._on_reward_skip_pressed()
		result["m1"]["auto_pick_failed"] = int(result["m1"].get("auto_pick_failed", 0)) + 1
	return picked


func _end_battle(result: Dictionary, battle: Dictionary) -> void:
	if battle.is_empty() or bool(battle.get("finished", false)):
		return
	battle["finished"] = true
	battle["turns"] = _duel.turn_count
	battle["hp_end"] = _duel.player_hp
	(result["rooms"] as Array).append(battle)


func _choose_branch(label: String, legal: Array) -> Dictionary:
	var preferences: Array = []
	match label:
		"B1": preferences = ["n7", "n13", "n17"]
		"B2": preferences = ["n10", "n15", "n19"]
		"B3": preferences = ["n7", "n15", "n19"]
		"B4": preferences = ["n10", "n13", "n17"]
		_: preferences = ["n7", "n13", "n17"]
	for id in preferences:
		for n in legal:
			if String(n["id"]) == id:
				return n
	return legal[0]


func _play_turn() -> String:
	_duel._on_spin_pressed()
	_pending_visual.clear()
	_stop_seen = 0
	var frames := 0
	while frames < 1200:
		frames += 1
		if frames % 240 == 0:
			print("G1_WAIT|enemy=%s|frame=%d|spin=%s|busy=%s|stopped=%s|target=%s" % [_duel.enemy_name, frames, str(_duel.reel_system.spinning), str(_duel._busy), str(_duel.reel_system.reel_stopped), _duel.readability.target_symbol_path])
		_collect_stops()
		if _duel.reel_system.spinning:
			var reel := _next_reel()
			if reel >= 0:
				var strip: Array = _duel.reel_system.reel_strips[reel]
				var vi: int = _duel.hud.visual_center_index(reel)
				var path := ""
				if vi >= 0 and vi < strip.size():
					path = String(strip[vi][0].resource_path)
				var target: String = _duel.readability.target_symbol_path
				if path == target or frames > 900:
					_pending_visual[reel] = path
					_duel._on_reel_clicked(reel)
					_collect_stops()
		elif not _duel._busy:
			_collect_stops()
			return "OK"
		await get_tree().process_frame
	return "TURN_TIMEOUT"


func _next_reel() -> int:
	for r in range(_duel.reel_system.reel_stopped.size()):
		if not _duel.reel_system.reel_stopped[r] and not _duel.reel_system.has_pending_stop(r):
			return r
	return -1


func _collect_stops() -> void:
	var records: Array = _duel.readability.stop_results
	while _stop_seen < records.size():
		var rec: Dictionary = records[_stop_seen]
		_stop_seen += 1
		if String(rec.get("reason", "")) != "player":
			continue
		var preset_count := 0
		for old in _stop_audit:
			if String(old.get("preset", "")) == _duel.readability.preset:
				preset_count += 1
		var audit_limit := 10 if _suite == "single" else 5
		if preset_count < audit_limit:
			var visual := String(_pending_visual.get(int(rec["reel"]), ""))
			_stop_audit.append({"reel": int(rec["reel"])+1, "visual": visual, "visual_name": _symbol_name(visual),
				"actual": String(rec.get("path", "")), "actual_name": String(rec.get("name", "")),
				"same": visual == String(rec.get("path", "")), "preset": _duel.readability.preset})


func _symbol_name(path: String) -> String:
	if path == "": return ""
	var sym = load(path)
	return String(sym.name) if sym != null else path.get_file().get_basename()


func _auto_consume() -> void:
	if _duel.player_hp < _duel.player_hp_max*4/10 and _use_effect("heal"):
		return
	if _duel.pending_jam_reel >= 0 or _duel.pending_lock_reel >= 0 or _duel.pending_chaos or _duel.pending_auto_stop:
		_use_effect("purify")


func _use_effect(effect: String) -> bool:
	for item in _duel.consumable_slots:
		var data: Resource = load(item["path"])
		if data != null and data.effect == effect:
			_duel.consumable_system.use(item["uid"])
			return true
	return false


func _shot(result: Dictionary, name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var key := "%s/%s" % [result["label"], name]
	if _shots.has(key): return
	_shots[key] = true
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s_%s.png" % [_out_dir, result["label"], name]
	var err := image.save_png(path)
	(result["shots"] as Array).append(path + " err=" + str(err))


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "  "))


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
