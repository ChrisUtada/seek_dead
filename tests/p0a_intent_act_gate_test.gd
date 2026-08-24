extends SceneTree

# P0-A 按幕渐进意图分档 · headless 回归（2026-08-24）
# 运行：Godot_v4.7 --headless --path <项目> --script res://tests/p0a_intent_act_gate_test.gd
# 覆盖《意图配置_行为族绑定与按幕渐进_方案.md》§6 F6 清单的可自动化部分。

const ROLLS_PER_ROOM := 200

var _fails := 0
var _checks := 0


class MockCtrl:
	var deprived_level := 0
	var _interf_resist_rf := 1.0
	var enemy_atk := 10


func _initialize() -> void:
	seed(20260824)
	var sys := StatusSystem.new(MockCtrl.new())
	var rooms: Array[RoomData] = []
	var dir := DirAccess.open("res://resources/rooms")
	for f in dir.get_files():
		if f.ends_with(".tres"):
			var r: RoomData = load("res://resources/rooms/" + f)
			if r != null:
				rooms.append(r)

	# ① Act1 全部普通/精英房：恒 attack/heavy（行为族表与默认表两条路都要过闸）
	var act1 := rooms.filter(func(r): return int(r.act) == 1 and r.kind != "boss")
	_check(act1.size() >= 10, "Act1 普通/精英房样本量 (%d)" % act1.size())
	for r in act1:
		var seen := _roll_types(sys, r)
		_check(_only(seen, ["attack", "heavy"]),
			"Act1 纯教学 %s：仅 attack/heavy，实测 %s" % [r.resource_path.get_file(), seen.keys()])

	# ② Act2 普通怪：干扰入门（jam/lock/chaos 出现），夺轮绝不出现
	var act2 := rooms.filter(func(r): return int(r.act) == 2 and r.kind == "normal")
	var act2_interf := {}
	for r in act2:
		var seen2 := _roll_types(sys, r)
		_check(not seen2.has("auto_stop"), "Act2 无夺轮 %s" % r.resource_path.get_file())
		for k in ["jam", "lock", "chaos"]:
			if seen2.has(k):
				act2_interf[k] = true
	_check(act2_interf.size() >= 2, "Act2 干扰意图已入池：%s" % [act2_interf.keys()])

	# ③ Act3：干扰系/播种系怪出夺轮；重击系怪全程零干扰
	var trickster_a3: RoomData = rooms.filter(func(r): return r.resource_path.contains("a3_trickster_dark"))[0]
	var seen3 := _roll_types(sys, trickster_a3)
	_check(seen3.has("auto_stop"), "Act3 诡匠出夺轮，实测 %s" % [seen3.keys()])
	var etrick: RoomData = rooms.filter(func(r): return r.resource_path.contains("a3_elite_trickster_dark"))[0]
	_check(_roll_types(sys, etrick).has("auto_stop"), "Act3 精英诡匠出夺轮")
	var brute_rooms := rooms.filter(func(r): return r.archetype != null and r.archetype.id == "heavy_brawler")
	_check(brute_rooms.size() >= 3, "重击者样本 (%d)" % brute_rooms.size())
	for r in brute_rooms:
		var seenb := _roll_types(sys, r)
		_check(_only(seenb, ["attack", "heavy"]), "重击者零干扰 %s：实测 %s" % [r.resource_path.get_file(), seenb.keys()])

	# ④ BOSS 房不受全局分档影响：显式表原样生效（含 Act1 cocoon 的 jam 教学覆盖）
	var cocoon: RoomData = rooms.filter(func(r): return r.resource_path.contains("cocoon_sentinel"))[0]
	var cocoon_seen := _roll_types(sys, cocoon)
	_check(cocoon_seen.has("jam"), "BOSS 显式表不受限：茧居 Act1 仍出注废，实测 %s" % [cocoon_seen.keys()])
	var cultist: RoomData = rooms.filter(func(r): return r.resource_path.contains("whispering_cultist"))[0]
	var cultist_seen := _roll_types(sys, cultist)
	_check(_only(cultist_seen, ["attack", "heavy"]) and not cultist_seen.has("auto_stop"),
		"BOSS 默认表（呓语教徒空房间表）仍走 boss 表：实测 %s" % [cultist_seen.keys()])

	# ⑤ 净化折扣仍在：抗扰拉满（rf=0）→ 可净化意图权重归零，Act3 默认表只剩攻/重
	sys._ctrl._interf_resist_rf = 0.0
	var a3_default := RoomData.new()
	a3_default.act = 3
	a3_default.kind = "normal"
	var seen_rf := _roll_types(sys, a3_default)
	_check(_only(seen_rf, ["attack", "heavy"]), "抗护 rf=0 时干扰权重归零：实测 %s" % [seen_rf.keys()])

	# ⑥ 兜底：纯干扰剖面遇 Act1 过滤全空 → 回落按幕默认表不崩溃、不出干扰
	var fake_arch: EnemyArchetype = EnemyArchetype.new()
	fake_arch.intent_weights = {"jam": 40, "lock": 40}
	var fake_room := RoomData.new()
	fake_room.act = 1
	fake_room.kind = "normal"
	fake_room.archetype = fake_arch
	var seen_fb := _roll_types(sys, fake_room)
	_check(_only(seen_fb, ["attack", "heavy"]), "过滤空表回落默认表：实测 %s" % [seen_fb.keys()])

	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	quit(1 if _fails > 0 else 0)


func _roll_types(sys: StatusSystem, room: RoomData) -> Dictionary:
	var seen := {}
	for i in ROLLS_PER_ROOM:
		var it: Dictionary = sys.roll_intent(room)
		seen[it["type"]] = seen.get(it["type"], 0) + 1
	return seen


func _only(seen: Dictionary, allowed: Array) -> bool:
	for k in seen.keys():
		if not (k in allowed):
			return false
	return true


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("PASS  ", label)
	else:
		_fails += 1
		printerr("FAIL  ", label)