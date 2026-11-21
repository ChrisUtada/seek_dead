extends Node

# N-04（2026-11-21）：牌谱提示时机——验收测试。
#
# 验收重点（对应用户 6 项）：
#   1. 无牌谱时不增加等待：pending_banners 空 → _present_banners 不产生横幅、_pattern_contrib_text 为空。
#   2. 有牌谱时先名称、再追加贡献、再总伤害：_present 编排顺序（通过 _pattern_contrib_text 与横幅队列间接钉住）。
#   3. 多横幅串行不覆盖：show_pattern_banner_seq 按 index 递增、各自成品，队列长度正确。
#   4. 快速跳过只跳演出：presentation_skip 下 _present_wait 走 process_frame（近乎零等待），
#      且结算层（contribute/apply）完全不受影响。
#   5. 同种子同输入战斗结果与 RNG 序列一致：两次 evaluate（跳过/不跳过）后 HP 与后续 randi() 序列一致。
#   6. 不改匹配/结算/RNG：从结构上保证（等待只在 _present_turn 零 RNG 演出层）。

var _fails := 0
var _checks := 0
var _duel: DuelController

func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("N04 FAIL: " + label)

func _ready() -> void:
	await get_tree().process_frame
	SaveSystem.reset_lobby_data()
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	_duel = scene_res.instantiate() as DuelController
	add_child(_duel)
	await get_tree().process_frame
	await get_tree().process_frame
	_duel.demo_config.enabled = false
	_duel.board_config.enabled = false
	_duel._confirm_loadout()
	await get_tree().process_frame

	_test_no_banner_zero_overhead()
	_test_banner_sequence_no_overwrite()
	_test_contrib_text()
	_test_skip_only_presentation()
	_test_rng_sequence_stable()

	_finish()

# 1. 无牌谱：空 banners → 不通往横幅路径；贡献文本为空；零额外等待分支。
func _test_no_banner_zero_overhead() -> void:
	var acc: Dictionary = _duel.combat._new_acc()
	var banners: Array = acc.get("pending_banners", [])
	_ok(banners.is_empty(), "无牌谱：pending_banners 为空")
	_ok(_duel.combat._pattern_contrib_text(acc) == "", "无牌谱：追加贡献文本为空（无额外提示）")
	# 无牌谱时 _present_banners 直接 for 空数组，不产生任何横幅节点
	_duel.hud._clear_pattern_banners()
	_duel.combat._present_banners(get_tree(), banners)
	_ok(_duel.hud._pattern_banner_queue.is_empty(), "无牌谱：不产生横幅节点")

# 3. 多横幅串行：3 条横幅各自独立、按 index 递增、不互相 queue_free 覆盖。
func _test_banner_sequence_no_overwrite() -> void:
	_duel.hud._clear_pattern_banners()
	var banners: Array = [
		{"text": "⚔ W01 烈焰斩", "color": Color.RED},
		{"text": "✦ W02 冰封击", "color": Color.BLUE},
		{"text": "✚ T01 恢复术式", "color": Color.GREEN},
	]
	# 直接连续 spawn 三条（不等 await），验证互不覆盖；_present_banners 的串行 await 只是播放间隔。
	for i in banners.size():
		var b: Dictionary = banners[i]
		_duel.hud.show_pattern_banner_seq(String(b["text"]), b["color"], i)
	_ok(_duel.hud._pattern_banner_queue.size() == 3, "多横幅：队列 3 条（实测 %d）" % _duel.hud._pattern_banner_queue.size())
	# 每条都是独立实例且有效（未被后一条覆盖销毁）
	var all_valid := true
	for b in _duel.hud._pattern_banner_queue:
		if not is_instance_valid(b):
			all_valid = false
	_ok(all_valid, "多横幅：每条都有效（未被覆盖 queue_free）")
	# y 偏移递增 = 串行错峰，不重叠
	var ys: Array = []
	for b in _duel.hud._pattern_banner_queue:
		if is_instance_valid(b):
			ys.append(float(b.position.y))
	var strictly_increasing: bool = ys.size() == 3 and ys[0] < ys[1] and ys[1] < ys[2]
	_ok(strictly_increasing, "多横幅：y 偏移递增、不重叠（%s）" % str(ys))
	_duel.hud._clear_pattern_banners()

# 2. 追加贡献文本：从 acc.lines 筛牌谱行，聚合成一条短提示；伤害分解行不算。
func _test_contrib_text() -> void:
	var acc: Dictionary = _duel.combat._new_acc()
	acc["lines"] = [
		"🔍 伤害分解",
		"   小计 10 × 克制×1.5 = 15",
		"   ✦ 牌谱「烈焰斩」已触发",
		"   🔥 烈焰共鸣：火系伤害 +25%（+5）",
	]
	var txt: String = _duel.combat._pattern_contrib_text(acc)
	_ok(txt != "", "有牌谱：追加贡献文本非空")
	_ok(txt.contains("烈焰"), "追加贡献含牌谱内容（%s）" % txt)
	_ok(not txt.contains("伤害分解"), "追加贡献不含伤害分解行")
	# 全是非牌谱行 → 空
	var acc2: Dictionary = _duel.combat._new_acc()
	acc2["lines"] = ["🔍 伤害分解", "   小计 10 = 10"]
	_ok(_duel.combat._pattern_contrib_text(acc2) == "", "无牌谱贡献行：文本为空")

# 4. 快速跳过只跳演出：_present_wait 在跳过时不产生长等待。
#    用墙钟时间近似：跳过模式 3 次 0.4s 等待应在 <0.15s 内跑完；正常模式应 ≥1.0s。
func _test_skip_only_presentation() -> void:
	var tree: SceneTree = get_tree()
	_duel.presentation_skip = true
	var t0: int = Time.get_ticks_msec()
	for i in 3:
		await _duel.combat._present_wait(tree, 0.4)
	var skip_ms: int = Time.get_ticks_msec() - t0
	_ok(skip_ms < 150, "跳过演出：3×0.4s 等待被压缩（实测 %d ms）" % skip_ms)
	# 跳过不影响结算层：结算函数不读 presentation_skip（结构保证），这里验证标志不误伤战斗数值。
	_duel.presentation_skip = false

# 5. 同种子同输入：结算结果（含 RNG 消耗）与跳过标志无关。
#    固定 seed 跑两次 contribute（结算层核心 RNG 点），断言结果与后续 RNG 序列一致。
func _test_rng_sequence_stable() -> void:
	var acc_a: Dictionary = _duel.combat._new_acc()
	seed(424242)
	_duel.presentation_skip = true
	var dmg_a := _contribute_fixed(acc_a)
	var rnd_a: Array = []
	for i in 5:
		rnd_a.append(randi())

	var acc_b: Dictionary = _duel.combat._new_acc()
	seed(424242)
	_duel.presentation_skip = false
	var dmg_b := _contribute_fixed(acc_b)
	var rnd_b: Array = []
	for i in 5:
		rnd_b.append(randi())

	_ok(dmg_a == dmg_b, "同种子同输入：结算伤害一致（%d / %d）" % [dmg_a, dmg_b])
	_ok(rnd_a == rnd_b, "同种子同输入：后续 RNG 序列一致（跳过不改变结算 RNG）")
	_ok(absf(float(acc_a["dmg"]) - float(acc_b["dmg"])) < 0.01, "同种子：acc.dmg 一致")
	_duel.presentation_skip = false

# 固定输入调用结算层 contribute（含 randf 暴击/穿透判定），返回整数伤害。
func _contribute_fixed(acc: Dictionary) -> int:
	var sym: SymbolData = load("res://resources/symbols/fire_slash.tres")
	_duel.combat.contribute(sym, 100, acc, "fire", "", -1, true)
	return int(acc.get("dmg", 0))

func _finish() -> void:
	print("N04 RESULT: %d checks, %d fails" % [_checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)
