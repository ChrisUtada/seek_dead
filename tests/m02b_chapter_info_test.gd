extends Node

# M-02b 第1步：章节头数据契约测试（只读 helper，不改战斗状态）。
# 验证：
# ① ACT1/2/3 都返回正确的常规 Boss 数据（名称/立绘/元素/弱抗/mechanic_summary）；
# ② 机制文案唯一源 = RoomData.mechanic_summary，不从 gimmick 动态生成；
# ③ 不含推荐武器/准备方向；
# ④ 不消耗 RNG、不改变战斗状态（纯函数，前后 duel 状态一致）；
# ⑤ 真·最终 Boss 不错误复用普通幕章节头。
# 隔离 APPDATA 运行。

const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const ChapterInfo = preload("res://scripts/systems/chapter_info.gd")
const EC = preload("res://scripts/battle/element_counter.gd")

var _checks := 0
var _fails := 0

func _ready() -> void:
	await _run()
	print("M02BINFO|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)

func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("M02BINFO|FAIL|" + msg)

func _run() -> void:
	var scene: PackedScene = load(DUEL_SCENE)
	var duel = scene.instantiate()
	add_child(duel)
	for i in 2:
		await get_tree().process_frame
	duel.demo_config.enabled = false
	duel.demo_config.act_only = false
	duel.board_config.enabled = false
	duel._confirm_loadout()   # 构建本局 ROOMS（F6：数据源必须是本局 ROOMS）
	for i in 2:
		await get_tree().process_frame
	var rooms: Array = duel.ROOMS
	_check(not rooms.is_empty(), "本局 ROOMS 已构建（%d 房）" % rooms.size())

	# ① ACT1/2/3 都有常规 Boss，数据正确
	for act in [1, 2, 3]:
		var d: Dictionary = ChapterInfo.for_run(rooms, act)
		_check(not d.is_empty(), "ACT%d 返回章节数据" % act)
		if d.is_empty():
			continue
		var boss: RoomData = d["boss"]
		_check(int(boss.act) == act, "ACT%d Boss 属于本幕" % act)
		_check(String(boss.kind) == "boss" and not bool(boss.final_boss), "ACT%d Boss 是常规 Boss（非真最终）" % act)
		_check(String(d["boss_name"]) == String(boss.name), "ACT%d Boss 名称取自 RoomData" % act)
		_check(String(d["mechanic_summary"]) == String(boss.mechanic_summary), "ACT%d 机制文案=RoomData.mechanic_summary" % act)
		var elem: String = String(d["boss_element"])
		var expect_weak: Array[String] = EC.weakness(elem)
		var expect_resist: Array[String] = EC.resists(elem)
		_check((d["weakness"] as Array).size() == expect_weak.size(), "ACT%d 弱点数量与元素表一致" % act)
		_check((d["resistance"] as Array).size() == expect_resist.size(), "ACT%d 抗性数量与元素表一致" % act)
		# F6 新断言：Boss 等于本局 ROOMS 中该幕 Boss、flow=8 房、幕名对齐
		var run_boss: RoomData = null
		for r in rooms:
			if r is RoomData and int(r.act) == act and String(r.kind) == "boss" and not bool(r.final_boss):
				run_boss = r
				break
		_check(run_boss != null and d["boss"] == run_boss, "ACT%d 章节头 Boss 等于本局 Boss" % act)
		_check((d["flow"] as Array).size() == 8, "ACT%d 流程 8 房（实测 %d）" % [act, (d["flow"] as Array).size()])
		_check(String(d["chapter_name"]) == ["ACT I", "ACT II", "ACT III"][act - 1], "ACT%d 幕名对齐" % act)
		print("M02BINFO|ACT%d boss=%s elem=%s weak=%s resist=%s" % [
			act, d["boss_name"], d["boss_element_label"], str(d["weakness"]), str(d["resistance"])])

	# ② 机制文案唯一源：不含 gimmick 脚本方法名/阶段标签的硬编码（只来自 mechanic_summary）
	var d1: Dictionary = ChapterInfo.for_run(rooms, 1)
	var summary: String = String(d1.get("mechanic_summary", ""))
	_check(summary != "" and not summary.contains("func "), "机制文案为 RoomData 原文，非脚本生成")
	# 与 boss 的 mechanic_summary 严格一致（即便为空也一致）
	var boss1: RoomData = d1["boss"]
	_check(summary == String(boss1.mechanic_summary), "机制文案严格等于 boss.mechanic_summary（唯一源）")

	# ③ 不含推荐/准备方向：数据键与文案里不应出现这些答案性词
	var forbidden := ["推荐", "建议", "应该带", "准备方向", "带什么", "攻略"]
	var blob: String = str(d1)
	for w in forbidden:
		_check(not blob.contains(w), "不含答案性措辞：%s" % w)

	# ④ 纯函数：调用前后 duel 状态不变、无 RNG 消费（helper 不接触 duel，仅 rooms）
	var hp0 := int(duel.player_hp)
	var gold0 := int(duel.gold)
	var rng_seed0 := int(duel._reward_system._loot.seed_value())
	for act in [1, 2, 3]:
		ChapterInfo.for_run(rooms, act)
		ChapterInfo.has_chapter_boss(rooms, act)
	_check(int(duel.player_hp) == hp0 and int(duel.gold) == gold0, "调用 helper 不改变 HP/金币")
	_check(int(duel._reward_system._loot.seed_value()) == rng_seed0, "调用 helper 不消耗战利品 RNG")

	# ⑤ 真·最终 Boss 不复用普通幕章节头
	var final_room: RoomData = null
	for r in rooms:
		if r is RoomData and bool(r.final_boss):
			final_room = r
			break
	if final_room != null:
		# 构造一个只含真最终 Boss 的 rooms 数组；任何幕都不应因它返回章节数据
		var only_final: Array = [final_room]
		var any := false
		for act in [1, 2, 3]:
			if not ChapterInfo.for_run(only_final, act).is_empty():
				any = true
		_check(not any, "真·最终 Boss 不产生任何普通幕章节头数据")
		_check(String(final_room.name) == "勇者的阴影", "真·最终 Boss 识别正确（%s）" % String(final_room.name))

	duel.queue_free()
	await get_tree().process_frame
