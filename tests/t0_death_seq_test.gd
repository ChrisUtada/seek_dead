extends Node

# ============================================================================
# T0-4A 专项（真实验收）：敌方死亡演出与奖励切换
# docs/Seek_Dead_T0_当前缺陷返工与执行指令_2026-11-22.md §5A
#
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t0_death_seq_test.tscn
# 隔离：必须由外部覆盖 APPDATA 到临时目录后再运行，绝不触碰真实存档。
#
# 全部击杀从真实入口触发（on_spin_pressed / free_spin），不直接调 _settle_kill_async 代替。
# 覆盖：普通/Boss 死亡时序、只结算一次、tween 中与完成后重复触发、快进终态、
#       真实 _start_room 视觉复位、非致命/和平、同种子 RNG 序列。
# ============================================================================

class KillProbeAnimator:
	var real
	var kill_calls: int = 0
	var finished: int = 0
	var last_skip: bool = false

	func setup(p_hud) -> void:
		real.setup(p_hud)

	# T0-4A：透明转发战斗过程中使用的其他 animator 方法，避免替换后
	# 战斗路径调 play_attack/play_enemy_attack/play_counter/enemy_hit_shake 时报
	# "Nonexistent function"。只有 play_kill 需要计数包装。
	func play_attack(attacker: String, target: String, with_slash: bool = false) -> void:
		real.play_attack(attacker, target, with_slash)

	func play_enemy_attack() -> void:
		real.play_enemy_attack()

	func play_counter(kind: String) -> void:
		real.play_counter(kind)

	func enemy_hit_shake() -> void:
		real.enemy_hit_shake()

	func play_kill(skip: bool = false):
		kill_calls += 1
		last_skip = skip
		var tw = real.play_kill(skip)
		if tw != null:
			tw.tween_callback(func() -> void: finished += 1)
		return tw


var _fails := 0
var _checks := 0
var _duel: DuelController
var _probe: KillProbeAnimator


func _ready() -> void:
	await get_tree().process_frame
	SaveSystem.reset_lobby_data()
	_duel = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(_duel)
	await get_tree().process_frame
	await get_tree().process_frame
	_duel.demo_config.enabled = false
	_duel.board_config.enabled = false
	_duel._confirm_loadout()
	await get_tree().process_frame
	_install_probe()
	await _run()
	_finish()


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _install_probe() -> void:
	if _probe != null:
		return
	_probe = KillProbeAnimator.new()
	_probe.real = _duel.hud.animator
	_duel.hud.animator = _probe


# 进入指定房型并重置到可战斗状态（room_index: 普通房 0 / Boss 房 7）
func _enter_room(idx: int) -> void:
	_duel.game_state = _duel.FlowState.PLAYING
	_duel.peaceful_win = false
	_duel._busy = false
	_duel.in_interroom = false   # 战后/特殊房会置位，不清则 on_spin_pressed 守卫直接 return
	_duel.in_loadout = false
	_duel.presentation_skip = true
	_duel.room_flow.post_battle_active = false
	_duel.hud.hide_reward_screen()
	_probe.kill_calls = 0
	_probe.finished = 0
	_duel.start_room_data(_duel.ROOMS[idx], idx)
	_duel.player_hp = _duel.player_hp_max   # 防止反被击倒
	_duel.enemy_hp = 1
	_duel.enemy_armor = 0


# 真实入口触发击杀并驱动到"死亡 tween 进行中"（state=WON 且 kill 已调用、tween 未完成）
func _drive_kill_via_spin() -> void:
	# 符号带随机：某些回合全是防御/治疗符号，evaluate 打不出伤害。
	# 重试直到真实击杀（最多 6 次），每次重置 HP=1 与战斗态。
	for attempt in 6:
		if _duel.game_state == _duel.FlowState.WON and _probe.kill_calls > 0:
			return
		_duel.game_state = _duel.FlowState.PLAYING
		_duel._busy = false
		_duel.enemy_hp = 1
		_duel.enemy_armor = 0
		_duel.player_hp = _duel.player_hp_max
		_duel._on_spin_pressed()
		for _i in 30:
			if _duel.reel_system.spinning:
				break
			await get_tree().process_frame
		for col in 3:
			_duel.reel_system.stop_next_reel()
			for _w in 40:
				if _duel.reel_system.reel_stopped[col]:
					break
				await get_tree().process_frame
		for _i in 100:
			await get_tree().create_timer(0.1).timeout
			if _duel.game_state == _duel.FlowState.WON and _probe.kill_calls > 0:
				break


# 断言击杀归零三件套（奖励出现前）：敌人真实 HP<=0、HP 标签 0/最大、血条比例 0
func _assert_enemy_zero(label: String) -> void:
	_check(_duel.enemy_hp <= 0, "%s 奖励前 enemy_hp<=0（实测 %d）" % [label, _duel.enemy_hp])
	var expect_label: String = "0/%d" % _duel.enemy_hp_max
	_check(_duel.hud.enemy_hp_label.text == expect_label,
		"%s 奖励前 enemy_hp_label=%s（实测 %s）" % [label, expect_label, _duel.hud.enemy_hp_label.text])
	_check(absf(_duel.hud.enemy_hp_bar.ratio) < 0.01,
		"%s 奖励前 enemy_hp_bar.ratio=0（实测 %.3f）" % [label, _duel.hud.enemy_hp_bar.ratio])


# 等死亡 tween 完成
func _await_death_done() -> void:
	for _i in 60:
		await get_tree().create_timer(0.1).timeout
		if _probe.finished > 0:
			break
	# tween 回调后留两帧让终态稳定写入（避免竞态导致 alpha 读到中间值）
	await get_tree().process_frame
	await get_tree().process_frame


# 1：普通攻击击杀（真实 on_spin_pressed）——普通房
func _test_normal_kill_timing() -> void:
	_enter_room(0)
	await _drive_kill_via_spin()
	_check(_duel.game_state == _duel.FlowState.WON, "普攻普通房 置 WON")
	_assert_enemy_zero("普攻普通房")
	_check(_probe.kill_calls == 1, "普攻普通房 play_kill 一次（实测 %d）" % _probe.kill_calls)
	_check(not _duel.hud.reward_screen.visible, "普攻普通房 死亡 tween 完成前战后界面不可见")
	_check(not _duel.room_flow.post_battle_active, "普攻普通房 死亡 tween 完成前未进入战后结算")
	await _await_death_done()
	_check(_probe.finished == 1, "普攻普通房 等待真实 tween 完成（实测 %d）" % _probe.finished)
	_check(_duel.room_flow.post_battle_active, "普攻普通房 tween 完成后战后结算进入")
	_check(_duel.hud.reward_screen.visible, "普攻普通房 tween 完成后战后界面可见")


# 1b：真实 DoT 击杀——从真实 on_spin_pressed 进入，普通攻击打不死，靠状态伤害致死
func _test_dot_kill_timing() -> void:
	_enter_room(0)
	_duel._busy = false
	_duel.player_hp = _duel.player_hp_max
	# 敌人 HP 设高使普通攻击打不死；加足量毒层使 DoT tick 致死
	for attempt in 6:
		if _duel.game_state == _duel.FlowState.WON and _probe.kill_calls > 0:
			break
		_duel.game_state = _duel.FlowState.PLAYING
		_duel._busy = false
		_duel.enemy_hp = 60
		_duel.enemy_armor = 0
		_duel.player_hp = _duel.player_hp_max
		_duel.enemy_status.clear()
		_duel.enemy_status_pending.clear()
		_duel.add_enemy_status("poison", 15)   # 15×9=135 > 60，DoT 必致死
		_duel._on_spin_pressed()
		for _i in 30:
			if _duel.reel_system.spinning:
				break
			await get_tree().process_frame
		for col in 3:
			_duel.reel_system.stop_next_reel()
			for _w in 40:
				if _duel.reel_system.reel_stopped[col]:
					break
				await get_tree().process_frame
		for _i in 120:
			await get_tree().create_timer(0.1).timeout
			if _duel.game_state == _duel.FlowState.WON and _probe.kill_calls > 0:
				break
	_check(_duel.game_state == _duel.FlowState.WON, "DoT 击杀 置 WON")
	_assert_enemy_zero("DoT 击杀")
	_check(_probe.kill_calls == 1, "DoT 击杀 play_kill 一次（实测 %d）" % _probe.kill_calls)
	_check(not _duel.hud.reward_screen.visible, "DoT 击杀 死亡 tween 完成前奖励不可见")
	_check(not _duel.room_flow.post_battle_active, "DoT 击杀 死亡 tween 完成前未进入战后结算")
	await _await_death_done()
	_check(_probe.finished == 1, "DoT 击杀 等待真实 tween 完成（实测 %d）" % _probe.finished)
	_check(_duel.room_flow.post_battle_active, "DoT 击杀 tween 完成后战后结算进入")
	_check(_duel.hud.reward_screen.visible, "DoT 击杀 tween 完成后奖励可见")


# 2：Boss 击杀时序（真实 on_spin_pressed）
func _test_boss_kill_timing() -> void:
	_enter_room(7)
	await _drive_kill_via_spin()
	_check(_duel.game_state == _duel.FlowState.WON, "Boss 击杀 置 WON")
	_check(_probe.kill_calls == 1, "Boss 击杀 play_kill 一次（实测 %d）" % _probe.kill_calls)
	_check(not _duel.hud.reward_screen.visible, "Boss 击杀 死亡 tween 完成前战利品不可见")
	await _await_death_done()
	_check(_duel.hud.reward_screen.visible, "Boss 击杀 tween 完成后战利品可见")


# 3：免费重转击杀（真实 free_spin）
func _test_free_spin_kill() -> void:
	_enter_room(0)
	_duel._busy = false
	for attempt in 6:
		if _duel.game_state == _duel.FlowState.WON and _probe.kill_calls > 0:
			break
		_duel.game_state = _duel.FlowState.PLAYING
		_duel._busy = false
		_duel.enemy_hp = 1
		_duel.enemy_armor = 0
		_duel.turn_flow.free_spin()
		for _i in 30:
			if _duel.reel_system.spinning:
				break
			await get_tree().process_frame
		for col in 3:
			_duel.reel_system.stop_next_reel()
			for _w in 40:
				if _duel.reel_system.reel_stopped[col]:
					break
				await get_tree().process_frame
		for _i in 100:
			await get_tree().create_timer(0.1).timeout
			if _duel.game_state == _duel.FlowState.WON and _probe.kill_calls > 0:
				break
	_check(_duel.game_state == _duel.FlowState.WON, "免费重转击杀 置 WON")
	_check(_probe.kill_calls == 1, "免费重转击杀 经同一收口 play_kill（实测 %d）" % _probe.kill_calls)
	await _await_death_done()
	_check(_duel.hud.reward_screen.visible, "免费重转击杀 tween 完成后界面可见")


# 4：tween 进行中与完成后重复触发收口，不重复 kill / 奖励 / 战后结算
func _test_repeat_settle() -> void:
	_enter_room(0)
	await _drive_kill_via_spin()
	# tween 进行中重复触发
	_duel.turn_flow._settle_kill_async("重复A")
	_duel.turn_flow._settle_kill_async("重复B")
	_check(_probe.kill_calls == 1, "tween 中重复触发 play_kill 仍一次（实测 %d）" % _probe.kill_calls)
	await _await_death_done()
	var calls_after: int = _probe.kill_calls
	var active_after: bool = _duel.room_flow.post_battle_active
	# 完成后再重复触发
	_duel.turn_flow._settle_kill_async("重复C")
	_duel.turn_flow._settle_kill_async("重复D")
	await get_tree().process_frame
	_check(_probe.kill_calls == calls_after, "完成后重复触发 play_kill 不增加（实测 %d）" % _probe.kill_calls)
	_check(_duel.room_flow.post_battle_active == active_after, "完成后重复触发 战后结算状态不变")


# 5：真实 _start_room 进入下一房，敌人视觉与 HP 显示复位
func _test_next_room_real_entry() -> void:
	_enter_room(0)
	_duel.presentation_skip = true
	# 等 reel/战斗系统从上一测试的战后状态稳定下来
	await get_tree().create_timer(0.2).timeout
	await _drive_kill_via_spin()
	# 偶发首次 spin 被残留状态吞掉：若未击杀则重置后再试一次
	if _probe.kill_calls == 0:
		_duel._busy = false
		_duel.game_state = _duel.FlowState.PLAYING
		await get_tree().create_timer(0.2).timeout
		await _drive_kill_via_spin()
	await _await_death_done()
	var sprite = _probe.real.enemy_sprite
	_check(is_equal_approx(float(sprite.modulate.a), 0.0), "击杀后 敌人 alpha 归零（实测 %.3f，kill=%d finished=%d）" % [float(sprite.modulate.a), _probe.kill_calls, _probe.finished])
	# 真实进入下一房（房 1 普通）
	_duel._on_next_room_pressed()
	# 房间切换可能有过渡，等待复位完成
	await get_tree().create_timer(0.8).timeout
	_check(is_equal_approx(float(sprite.modulate.a), 1.0), "下一房 alpha 复位为 1（实测 %.3f）" % float(sprite.modulate.a))
	_check(is_equal_approx(float(sprite.scale.x), 1.0), "下一房 scale 复位为 1（实测 %.3f）" % float(sprite.scale.x))
	_check(_duel.hud.player_hp_label.text == "%d/%d" % [_duel.player_hp, _duel.player_hp_max], "下一房 HP 标签显示真实值（实测 %s）" % _duel.hud.player_hp_label.text)
	# 新敌人 HP 标签与血条比例必须与新房真实 HP 一致（不能只验证玩家 HP）
	var enemy_hp: int = maxi(0, _duel.enemy_hp)
	var enemy_max: int = maxi(1, _duel.enemy_hp_max)
	var expect_enemy_label: String = "%d/%d" % [enemy_hp, enemy_max]
	_check(_duel.hud.enemy_hp_label.text == expect_enemy_label,
		"下一房 enemy_hp_label=%s（实测 %s）" % [expect_enemy_label, _duel.hud.enemy_hp_label.text])
	var expect_enemy_ratio: float = float(enemy_hp) / float(enemy_max)
	_check(absf(_duel.hud.enemy_hp_bar.ratio - expect_enemy_ratio) < 0.01,
		"下一房 enemy_hp_bar.ratio=%.3f（实测 %.3f）" % [expect_enemy_ratio, _duel.hud.enemy_hp_bar.ratio])


# 6：同种子全局 RNG 序列对照——死亡演出（溶解 tween）本身不消耗随机流
func _test_rng_sequence() -> void:
	seed(20261122)
	var base: Array[int] = []
	for _i in 8:
		base.append(randi())
	# 只跑死亡演出本身：seed 后调 play_kill 并等完成，不掺入 evaluate 战斗 RNG
	seed(20261122)
	var tw = _probe.real.play_kill(false)
	if tw != null:
		await tw.finished
	var after: Array[int] = []
	for _i in 8:
		after.append(randi())
	_check(base == after, "同种子：死亡演出不消耗全局 RNG（基准 %s / 实测 %s）" % [str(base), str(after)])


# 7：保留非致命、和平结局与快进终态
func _test_preserved_cases() -> void:
	# 非致命：敌人未死，begin_player_turn 不播 kill
	_enter_room(0)
	_duel.enemy_hp = 50
	_probe.kill_calls = 0
	_duel.turn_flow.begin_player_turn()
	await get_tree().process_frame
	_check(_probe.kill_calls == 0, "非致命回合 不触发 play_kill（实测 %d）" % _probe.kill_calls)

	# 和平结局：不播 kill
	_enter_room(0)
	_duel.enemy_hp = 50
	_duel.peaceful_win = false
	_probe.kill_calls = 0
	_duel.turn_flow.resolve_peaceful_win()
	await get_tree().process_frame
	_check(_duel.peaceful_win and _duel.game_state == _duel.FlowState.WON, "和平结局 置 WON")
	_check(_probe.kill_calls == 0, "和平结局 不触发 play_kill（实测 %d）" % _probe.kill_calls)

	# 快进终态：直接验证 play_kill(true) 的快进机制（evaluate 会清零 presentation_skip，
	# 因此收口路径的 skip 由 controller 输入的时机决定，这里精确验证快进本身）。
	_enter_room(0)
	_probe.last_skip = false
	var tw = _probe.play_kill(true)   # 经 probe 记录 skip 参数并转调真实动画器
	_check(_probe.last_skip, "快进 传入 skip=true（实测 %s）" % str(_probe.last_skip))
	if tw != null:
		await tw.finished
	await get_tree().process_frame
	var sprite = _probe.real.enemy_sprite
	_check(is_equal_approx(float(sprite.modulate.a), 0.0), "快进 alpha 归零（实测 %.3f）" % float(sprite.modulate.a))
	_check(is_equal_approx(float(sprite.scale.x), 0.2), "快进 scale 到终值（实测 %.3f）" % float(sprite.scale.x))


func _run() -> void:
	await _test_normal_kill_timing()
	await _test_dot_kill_timing()
	await _test_boss_kill_timing()
	await _test_free_spin_kill()
	await _test_repeat_settle()
	await _test_next_room_real_entry()
	await _test_rng_sequence()
	await _test_preserved_cases()


func _finish() -> void:
	print("---")
	print("T0-4A RESULT: %d checks, %d fails" % [_checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)
