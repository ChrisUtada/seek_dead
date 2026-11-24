extends Node

# ============================================================================
# T0-1 专项：营地二选一「本次整理机会」回收（docs/Seek_Dead_T0_当前缺陷返工与执行指令_2026-11-22.md §2）
#
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t0_camp_trim_reclaim_test.tscn
# 隔离：必须由外部覆盖 APPDATA 到临时目录后再运行，绝不触碰真实存档。
#
# 必测场景（文档 §2）：
#   1. 休整后，本次整理次数为 0。
#   2. 直接继续后，本次整理次数为 0。
#   3. 打开整理再取消，然后休整/继续，本次机会为 0。
#   4. 实际整理成功只消耗一次，重复回调不重复扣减。
#   5. 满血休整不软锁。
#   6. 已有其他来源整理次数时，不会误删玩家原有资源。
#
# 补充验收（2026-11-22 用户指令）：
#   7. 无合法候选且无可卸技能：不提供假整理选项，休整/继续均不软锁，
#      回收后次数正确，并覆盖已有其他来源次数。
#   8. 成功整理后重复调用一次 _linear_camp_trim_done(true)：不重复扣次、不重复结算。
#   9. 至少通过真实 HUD 方法分别走一次取消链与确认链（非仅直接调控制器回调 / _trim.apply）。
# ============================================================================

var _fails := 0
var _checks := 0
var _duel: DuelController


func _ready() -> void:
	await get_tree().process_frame
	SaveSystem.reset_lobby_data()
	_duel = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(_duel)
	await get_tree().process_frame
	await get_tree().process_frame
	_duel.demo_config.enabled = false
	_duel._confirm_loadout()
	await get_tree().process_frame
	_run()
	_finish()


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


# 进营地：ROOMS[6] = 幕1第7房营地。do_reset 控制是否先清空精简记账。
func _enter_camp(hp: int, do_reset: bool = true) -> void:
	if do_reset:
		_duel._trim.reset_run()
	_duel.room_index = 5
	_duel.player_hp = hp
	_duel.player_hp_max = 100
	_duel._linear_camp_done = false
	_duel._linear_camp_idx = -1
	_duel.start_room_data(_duel.ROOMS[6], 6)


func _run() -> void:
	_test_rest_reclaim()
	_test_continue_reclaim()
	_test_cancel_then_rest()
	_test_cancel_then_continue()
	_test_trim_consume_once()
	_test_full_hp_no_softlock()
	_test_keep_other_source()
	_test_hud_cancel_chain()
	_test_hud_confirm_chain_and_repeat()
	_test_no_candidates_no_softlock()


# 场景1：休整后本次机会回收为 0
func _test_rest_reclaim() -> void:
	_enter_camp(50)
	_check(_duel._trim.trims_left() == 1, "S1 进营地授予本次 1 次（实测 %d）" % _duel._trim.trims_left())
	_duel._linear_camp_rest()
	_check(_duel._trim.trims_left() == 0, "S1 休整后本次机会为 0（实测 %d）" % _duel._trim.trims_left())
	_check(_duel._linear_camp_done, "S1 休整置结算守卫")


# 场景2：直接继续后本次机会回收为 0
func _test_continue_reclaim() -> void:
	_enter_camp(50)
	_duel._linear_camp_continue()
	_check(_duel._trim.trims_left() == 0, "S2 直接继续后本次机会为 0（实测 %d）" % _duel._trim.trims_left())


# 场景3a：打开整理再取消，然后休整 → 机会为 0
func _test_cancel_then_rest() -> void:
	_enter_camp(50)
	_duel._linear_camp_trim_done(false)   # 模拟取消：不推进、不消耗
	_check(_duel._trim.trims_left() == 1, "S3a 取消整理不消耗机会（实测 %d）" % _duel._trim.trims_left())
	_check(not _duel._linear_camp_done, "S3a 取消后未结算")
	_duel._linear_camp_rest()
	_check(_duel._trim.trims_left() == 0, "S3a 取消后休整，本次机会为 0（实测 %d）" % _duel._trim.trims_left())


# 场景3b：打开整理再取消，然后直接继续 → 机会为 0
func _test_cancel_then_continue() -> void:
	_enter_camp(50)
	_duel._linear_camp_trim_done(false)
	_duel._linear_camp_continue()
	_check(_duel._trim.trims_left() == 0, "S3b 取消后继续，本次机会为 0（实测 %d）" % _duel._trim.trims_left())


# 场景4：实际整理只消耗一次；重复回调不重复扣减（控制器链对照）
func _test_trim_consume_once() -> void:
	_enter_camp(50)
	var cands: Array = _duel._trim.candidates()
	_check(not cands.is_empty(), "S4 有合法整理候选")
	if cands.is_empty():
		return
	var cand: Dictionary = cands[0]
	var before: int = _duel._trim.trims_left()
	var msg: String = _duel._trim.apply(cand)
	_check(msg != "", "S4 整理真实生效（%s）" % msg)
	_check(_duel._trim.trims_left() == before - 1, "S4 整理只消耗 1 次（实测 %d）" % _duel._trim.trims_left())
	_duel._linear_camp_trim_done(true)
	_check(_duel._linear_camp_done, "S4 整理后结算守卫置位")
	_check(_duel._trim.trims_left() == before - 1, "S4 整理结算不额外回收（实测 %d）" % _duel._trim.trims_left())
	_duel._linear_camp_rest()   # 重复回调：守卫应挡住，不重复扣减/回收
	_duel._linear_camp_continue()
	_check(_duel._trim.trims_left() == before - 1, "S4 重复回调不重复扣减（实测 %d）" % _duel._trim.trims_left())


# 场景5：满血休整不软锁，机会仍回收
func _test_full_hp_no_softlock() -> void:
	_enter_camp(100)
	_duel._linear_camp_rest()
	_check(int(_duel.player_hp) == 100, "S5 满血休整不增血（实测 %d）" % int(_duel.player_hp))
	_check(_duel._linear_camp_done, "S5 满血休整置结算（不软锁）")
	_check(_duel._trim.trims_left() == 0, "S5 满血休整后机会为 0（实测 %d）" % _duel._trim.trims_left())


# 场景6：玩家已有其他来源次数时，只回收本次机会，不误删原有资源
func _test_keep_other_source() -> void:
	_duel._trim.reset_run()
	_duel._trim.grant(2)                  # 模拟玩家已有 2 次（精简剪来源，非本次营地）
	_enter_camp(50, false)                # 进营地再授予本次 1 次（不 reset）
	_check(_duel._trim.trims_left() == 3, "S6 已有2次+营地1次=3（实测 %d）" % _duel._trim.trims_left())
	_duel._linear_camp_rest()
	_check(_duel._trim.trims_left() == 2, "S6 休整只回收本次1次，保留原有2次（实测 %d）" % _duel._trim.trims_left())


# 补充9a：真实 HUD 取消链 —— 营地「整理」按钮 → 精简弹层「取消」→ 重开营地
# 全程走 HUD 的真实按钮回调，不直接调控制器回调、不直接 _trim.apply。
func _test_hud_cancel_chain() -> void:
	_enter_camp(50)
	var hud = _duel.hud
	_check(hud._linear_camp_dialog != null and hud._linear_camp_dialog.visible, "HUD取消 营地弹层可见")
	hud._on_linear_camp_trim()             # 真实：点营地「整理」按钮 → show_trim_dialog(_linear_camp_trim_done)
	_check(hud._trim_dialog != null and hud._trim_dialog.visible, "HUD取消 精简弹层已打开")
	_check(_duel._trim.trims_left() == 1, "HUD取消 打开弹层不消耗次数（实测 %d）" % _duel._trim.trims_left())
	hud._on_trim_cancel_pressed()          # 真实：点精简弹层「取消」→ done(false) → 重开营地
	_check(not hud._trim_dialog.visible, "HUD取消 精简弹层关闭")
	_check(hud._linear_camp_dialog.visible, "HUD取消 回到营地二选一（未推进）")
	_check(not _duel._linear_camp_done, "HUD取消 未结算")
	_check(_duel._trim.trims_left() == 1, "HUD取消 次数未消耗（实测 %d）" % _duel._trim.trims_left())
	# 取消后走真实 HUD「休整」收口，验证回收
	hud._on_linear_camp_rest()
	_check(_duel._linear_camp_done, "HUD取消后休整 结算置位（不软锁）")
	_check(_duel._trim.trims_left() == 0, "HUD取消后休整 本次机会回收为 0（实测 %d）" % _duel._trim.trims_left())


# 补充9b + 8：真实 HUD 确认链 —— 营地「整理」→ 选候选 →「确认」→ 成功结算
# 随后重复调用一次 _linear_camp_trim_done(true)，验证不重复扣次、不重复结算。
func _test_hud_confirm_chain_and_repeat() -> void:
	_enter_camp(50)
	var hud = _duel.hud
	var before: int = _duel._trim.trims_left()
	var used_before: int = _duel._trim.used
	var cands: Array = _duel._trim.candidates()
	_check(not cands.is_empty(), "HUD确认 有合法整理候选")
	if cands.is_empty():
		return
	hud._on_linear_camp_trim()             # 真实：点营地「整理」
	hud._on_trim_cand_pressed(cands[0])    # 真实：点候选查看预览
	_check(hud._trim_confirm != null and not hud._trim_confirm.disabled, "HUD确认 选中候选后确认按钮可用")
	hud._on_trim_confirm_pressed()         # 真实：点「确认」→ apply → done(true) → settle
	_check(not hud._trim_dialog.visible, "HUD确认 弹层关闭")
	_check(_duel._linear_camp_done, "HUD确认 结算守卫置位")
	_check(_duel._trim.trims_left() == before - 1, "HUD确认 只消耗 1 次（实测 %d）" % _duel._trim.trims_left())
	_check(_duel._trim.used == used_before + 1, "HUD确认 used 只 +1（实测 %d→%d）" % [used_before, _duel._trim.used])
	var hp_once: int = int(_duel.player_hp)
	var left_once: int = _duel._trim.trims_left()
	var used_once: int = _duel._trim.used
	# 补充8：成功后重复调用一次
	_duel._linear_camp_trim_done(true)
	_check(_duel._trim.trims_left() == left_once, "HUD确认后重复 trim_done(true) 不重复扣次（实测 %d）" % _duel._trim.trims_left())
	_check(_duel._trim.used == used_once, "HUD确认后重复 trim_done(true) used 不变（实测 %d）" % _duel._trim.used)
	_check(int(_duel.player_hp) == hp_once, "HUD确认后重复 trim_done(true) 不重复结算（HP 实测 %d）" % int(_duel.player_hp))


# 补充7：无合法候选且无可卸技能
# 构造：临时清空 selected_loadout 与 selected_skills，使 candidates() 为空。
# 验证：不提供假整理选项、休整/继续均不软锁、回收后次数正确、覆盖已有其他来源次数。
func _test_no_candidates_no_softlock() -> void:
	var saved_loadout: Array = _duel.selected_loadout.duplicate()
	var saved_skills: Array = _duel.selected_skills.duplicate()
	_duel.selected_loadout = []
	_duel.selected_skills = []

	# 7a：无其他来源 —— 本次机会不得残留，休整/继续不软锁
	_enter_camp(50)
	_check(_duel._trim.candidates().is_empty(), "S7a 无合法候选且无可卸技能（candidates 为空）")
	_check(_duel._trim.trims_left() == 0, "S7a 无候选时本次机会已回收（实测 %d）" % _duel._trim.trims_left())
	var hud = _duel.hud
	var has_fake_trim_btn := false
	for c in hud._linear_camp_vbox.get_children():
		if c is Button and String(c.text).contains("整理 · 精简"):
			has_fake_trim_btn = true
	_check(not has_fake_trim_btn, "S7a 不提供假整理按钮")
	_check(hud._linear_camp_dialog.visible, "S7a 营地弹层可见（不空屏）")
	hud._on_linear_camp_rest()
	_check(_duel._linear_camp_done, "S7a 无候选休整不软锁（结算置位）")
	_check(_duel._trim.trims_left() == 0, "S7a 无候选休整后次数为 0（实测 %d）" % _duel._trim.trims_left())

	# 7b：继续路径不软锁
	_enter_camp(50)
	hud._on_linear_camp_continue()
	_check(_duel._linear_camp_done, "S7b 无候选继续不软锁（结算置位）")
	_check(_duel._trim.trims_left() == 0, "S7b 无候选继续后次数为 0（实测 %d）" % _duel._trim.trims_left())

	# 7c：已有其他来源 2 次 —— 无候选不误删原有次数
	_duel._trim.reset_run()
	_duel._trim.grant(2)
	_enter_camp(50, false)
	_check(_duel._trim.trims_left() == 2, "S7c 已有2次+无候选不授予，仍为2（实测 %d）" % _duel._trim.trims_left())
	hud._on_linear_camp_rest()
	_check(_duel._trim.trims_left() == 2, "S7c 无候选休整不误删原有2次（实测 %d）" % _duel._trim.trims_left())

	# 恢复装备，避免污染后续（本测试为最后一项，仍保持整洁）
	_duel.selected_loadout = saved_loadout
	_duel.selected_skills = saved_skills
	_duel._trim.reset_run()


func _finish() -> void:
	print("---")
	print("T0-1 RESULT: %d checks, %d fails" % [_checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)
