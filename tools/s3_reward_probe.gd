extends Node

# S3-3 真实对局奖励采集探针（2026-11-21）
# 用真实 reward_system 流程（build_loot_offer / settle_loot_offer / reroll / skip）产生
# 真实 run_journal run JSON（--runlog），供 S0 汇总器读真实分布。不用 fixture 推新权重。
# 六身份武器通过局内授予构造，run JSON 标注 "probe_note=测试配装"，不伪装自然新档掉落。
# 运行：Godot --headless --path . res://tools/s3_reward_probe.tscn -- --out=<runs目录> --profiles=<json> --seeds=111,333

var OUT := "user://runs"
var SEEDS := [111, 333, 555]
var profiles: Array = []

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var s := String(arg)
		if s.begins_with("--out="): OUT = s.substr(6)
		elif s.begins_with("--seeds="):
			SEEDS = []
			for p in s.substr(8).split(",", false): SEEDS.append(int(String(p).strip_edges()))
		elif s.begins_with("--profiles="): profiles = _load_profiles(s.substr(11))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for prof in profiles:
		for run_seed in SEEDS:
			await _run_one(prof, int(run_seed))
	print("S3REWARD|RESULT_OK profiles=%d seeds=%d" % [profiles.size(), SEEDS.size()])
	get_tree().quit(0)

func _load_profiles(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return []
	var j := JSON.new()
	if j.parse(f.get_as_text()) != OK: return []
	var d: Variant = j.data
	if d is Dictionary: return d.get("profiles", [])
	return []

func _run_one(prof: Dictionary, run_seed: int) -> void:
	seed(run_seed)
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.demo_config.enabled = false
	duel.demo_config.act_only = false
	duel.selected_loadout.clear()
	for p in prof.get("loadout", []): duel.selected_loadout.append(String(p))
	duel._confirm_loadout()
	await get_tree().process_frame
	# 标注测试配装（六身份武器局内授予，非自然新档掉落）
	if duel._journal._data is Dictionary:
		duel._journal._data["probe_note"] = "S3-3测试配装:" + String(prof.get("name", ""))
		duel._journal._data["probe_test_loadout"] = (duel.selected_loadout.duplicate() if duel.selected_loadout is Array else [])

	var rs = duel._reward_system
	var rooms: int = int(prof.get("rooms", 20))
	var strategy: String = String(prof.get("strategy", "mixed"))
	var displayed := 0
	var picked := 0
	var skipped := 0
	var rerolled := 0
	for i in range(rooms):
		# 模拟房间/幕推进，让事件的 room/act 有真实梯度
		duel.room_index = i
		duel.current_act = 1 + i / 8
		duel.gold = 100   # 保证重抽可支付
		duel.player_hp = duel.player_hp_max
		var view: Dictionary = rs.build_loot_offer("normal", duel.current_act, {"growth_only": true})
		if not bool(view.get("ok", false)):
			rs.settle_loot_skip()
			continue
		displayed += 1
		# 策略：展示分布用 skip；选择价值用 pick；mixed 覆盖重抽/跳过/选择
		var act: String = strategy
		if strategy == "mixed":
			act = ["skip", "pick", "reroll_pick", "reroll_skip"][i % 4]
		if act == "reroll_pick" or act == "reroll_skip":
			var rv: Dictionary = rs.reroll_loot_offer()
			if bool(rv.get("ok", false)):
				rerolled += 1
				displayed += 1   # 重抽新组合也是一次展示
				view = rv
		if act == "skip" or act == "reroll_skip":
			rs.settle_loot_skip()
			skipped += 1
		else:
			var opts: Array = view.get("options", [])
			var idx: int = _pick_index(opts, prof, duel)
			var settled: Dictionary = rs.settle_loot_offer(idx)
			if bool(settled.get("ok", false)): picked += 1
			else: rs.settle_loot_skip(); skipped += 1
	# 局末真实落盘（--runlog 由命令行启用）
	duel._journal.finish()
	# 统计摘要写到控制台；真实数据以 run JSON 为准
	print("S3REWARD|%s|%d|displayed=%d|picked=%d|skipped=%d|rerolled=%d|events=%d" % [
		String(prof.get("name", "")), run_seed, displayed, picked, skipped, rerolled,
		duel._telemetry.draft_events_all.size()])
	duel.queue_free()
	await get_tree().process_frame

func _pick_index(opts: Array, prof: Dictionary, duel: DuelController) -> int:
	if opts.is_empty(): return 0
	var pref: String = String(prof.get("prefer", ""))
	# 构筑策略 bot：优先选偏好类别/回路，否则第0张
	for i in range(opts.size()):
		var o: Variant = opts[i]
		var cat := ""
		var oid := ""
		if o is Dictionary:
			cat = String(o.get("category", ""))
			oid = String(o.get("id", ""))
		if pref != "" and (cat == pref or oid.begins_with(pref)): return i
	return 0
