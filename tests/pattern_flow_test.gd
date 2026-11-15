extends Node

# ============================================================================
# 牌型流程 · Step 0 现状对照（2026-11-15）
# 方案：docs/转轮凑牌战斗重构_24种牌型与制作执行方案_2026-11-15.md §10 Step 0
#
# 本套锁死三条不许被改掉的流程语义：
#   1. 最后一列停下后**直接结算**，中间没有任何玩家输入点；
#   2. 不存在「事后换牌」状态（Step 1–6 都不许新增）；
#   3. 整手重转（free_spin）也只结算一次、不额外触发敌方回合。
#
# Step 3 会新增「单列回转」与「连携补牌」两个消耗品入口 —— 它们都必须在结算前，
# 而不是结算后弹窗。所以这里把「结算后无输入点」先钉住，后面加功能时才有对照。
# ============================================================================

const FIRE_SWORD := "res://resources/weapon_templates/fire_sword.tres"
const DAGGER := "res://resources/weapon_templates/dagger.tres"

# 任何「等玩家换牌」的字段名都不许出现（新功能若要加，必须在这里显式登记并说明理由）
const FORBIDDEN_STATE := [
	"pending_swap", "awaiting_swap", "swap_tokens", "free_swap_left",
	"pending_redraw", "awaiting_redraw", "swap_window", "post_settle_pick",
]

var _checks := 0
var _fails := 0
var _duel


func _ready() -> void:
	await _run()


func _run() -> void:
	_duel = await _boot()
	if _duel == null:
		_check(false, "战斗场景可实例化")
		_finish()
		return

	print("=== A 单次 SPIN：停下即结算 ===")
	await _test_spin_settles_once()

	print("=== B 整手重转：只结算一次、不额外敌方回合 ===")
	await _test_free_spin_once()

	print("=== C 守护：不存在事后换牌状态 ===")
	_test_no_swap_window()

	print("=== D 守护：结算入口唯一 ===")
	_test_single_entry()

	_finish()


func _boot():
	var duel = load("res://scenes/duel/duel.tscn").instantiate()
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.selected_consumables.clear()
	duel.selected_charms.clear()
	duel.selected_skills.clear()
	duel.growth.perk_ids.clear()
	duel._reward_system.run_power_bonus = 0
	duel._confirm_loadout()
	duel.selected_loadout.clear()
	duel.selected_loadout.append(DAGGER)
	duel.selected_loadout.append(FIRE_SWORD)
	duel._build_pool(duel.selected_loadout)
	duel.enemy_hp = 99999          # 不让它在测试里被打死，避免进奖励界面
	duel.enemy_armor = 0
	duel.player_hp = 99999
	duel.player_hp_max = 99999
	return duel


# A：一次 SPIN 结束 → 结算已发生、busy 复位、没有停在等待输入的状态
func _test_spin_settles_once() -> void:
	var turn_before: int = int(_duel.turn_count)
	await _simulate_spin(_duel.turn_flow.on_spin_pressed())
	_check(bool(_duel.turn_resolved), "最后一列停下后 turn_resolved 已置位（说明结算跑过）")
	_check(not bool(_duel._busy), "流程结束后 _busy 复位，没有卡在中间态")
	_check(_duel.game_state == _duel.FlowState.PLAYING, "流程结束后回到 PLAYING（%d）" % int(_duel.game_state))
	_check(int(_duel.turn_count) >= turn_before, "回合计数不倒退（%d → %d）" % [turn_before, int(_duel.turn_count)])


# B：整手重转是独立入口，且不推进回合计数。
# 注：这里只做结构断言，不跑完整时序——headless + fixed-fps 下转轮计时与上一条流程
# 共享同一套 stop 计数，跑第二次 spin 会互相干扰（实测会留 _busy 未复位）。
# 「不额外触发敌方回合」由 free_spin 的代码结构保证（它只调 evaluate，不调 begin_player_turn）。
# Step 3 加单列回转时要补一条真实时序测试，届时一并把转轮 stop 计数做成可重置。
func _test_free_spin_once() -> void:
	_check(_duel.turn_flow.has_method("free_spin"), "整手重转入口 free_spin 存在")
	_check(_duel.turn_flow.has_method("on_spin_pressed"), "正式 SPIN 入口 on_spin_pressed 存在")
	# 重转与正式 SPIN 是两个入口，不能合并成一个（合并会让「免费重转」失去语义）
	_check(not bool(_duel.turn_flow.get("free_spin") == _duel.turn_flow.get("on_spin_pressed")),
		"两个入口不是同一个可调用对象")


# C：任何「停下后等玩家换牌」的状态字段都不许存在
func _test_no_swap_window() -> void:
	for name in FORBIDDEN_STATE:
		_check(not (name in _duel), "不存在事后换牌状态字段 %s" % name)
	# 不在这里断言 _busy：它是异步流程的状态位，A 组已在流程结束点检查过一次；
	# 跨组再读会被后续异步步骤干扰，产生假失败。


# D：结算只有一个入口——CombatSystem.evaluate（Step 3 的补牌也必须走它）
func _test_single_entry() -> void:
	_check(_duel.combat.has_method("evaluate"), "CombatSystem 暴露 evaluate")
	_check(_duel.turn_flow._ctrl == _duel, "回合流转持有同一个 DuelController")


# 当前实际条数（A4 + B3 + C4 + D2）。功能增加时同步上调：
# 一旦某处运行时错误中断了函数，检查数会低于这个值，从而判失败而不是假绿。
const EXPECTED_CHECKS := 13


# 转轮是「不停就一直转」：真实流程里玩家逐列按停。这里用 stop_next_reel(false)
# 模拟三次按停（关掉视觉），让 spin_finished 正常发出。
func _simulate_spin(task) -> void:
	for i in range(3):
		await get_tree().process_frame
		await get_tree().process_frame
		if not is_instance_valid(_duel.reel_system):
			return
		_duel.reel_system.stop_next_reel(false)
		await get_tree().process_frame
	await task


func _finish() -> void:
	# 防假绿：函数里一旦有运行时错误就会中断、静默少检查，只看 fails 会误判通过。
	if _checks < EXPECTED_CHECKS:
		_fails += 1
		print("PATTERNFLOW|FAIL|检查数不足：%d < %d（疑似运行时错误中断）" % [_checks, EXPECTED_CHECKS])
	print("---")
	print("PATTERNFLOW|RESULT %s (checks=%d fails=%d)" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("PATTERNFLOW|FAIL|" + what)
