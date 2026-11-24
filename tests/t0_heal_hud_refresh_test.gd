extends Node

# ============================================================================
# T0-4 专项：真实治疗入口与 HUD 刷新（docs/Seek_Dead_T0_当前缺陷返工与执行指令_2026-11-22.md §5）
#
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t0_heal_hud_refresh_test.tscn
# 隔离：必须由外部覆盖 APPDATA 到临时目录后再运行，绝不触碰真实存档。
#
# 三个真实入口（不手动设置 player_hp、不手动调 _refresh_meta）：
#   - growth.apply_victory_perks("normal"/"boss") 的回春；
#   - growth.grant_act_boon(act) 的锻魂 HP / 最大 HP；
#   - growth.pick("tough") 的最大 HP 与当前 HP。
#
# 目标：真实 HP/最大 HP 正确；BattleState 快照更新；HP 标签与血条读取新值；
#       不被旧受击影子遮蔽；满血与溢出转盾按现有规则。
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


func _reset(hp: int, hp_max: int) -> void:
	_duel.hud.reset_enemy_hit_hold()
	_duel.player_hp = hp
	_duel.player_hp_max = hp_max
	_duel.invalidate_state()
	_duel.hud._refresh_meta()


# 断言标签/血条/快照与真实 HP 一致（治疗刷新是否生效的唯一判据）
func _assert_hud(label: String, expect_hp: int, expect_max: int) -> void:
	_check(_duel.hud.player_hp_label.text == "%d/%d" % [expect_hp, expect_max],
		"%s HP 标签=%d/%d（实测 %s）" % [label, expect_hp, expect_max, _duel.hud.player_hp_label.text])
	var expect_ratio: float = float(expect_hp) / float(max(1, expect_max))
	_check(absf(_duel.hud.player_hp_bar.ratio - expect_ratio) < 0.01,
		"%s 血条比例=%.3f（实测 %.3f）" % [label, expect_ratio, _duel.hud.player_hp_bar.ratio])
	_check(int(_duel.state.player_hp) == expect_hp and int(_duel.state.player_hp_max) == expect_max,
		"%s BattleState 快照=%d/%d" % [label, expect_hp, expect_max])


func _run() -> void:
	_test_regen()
	_test_regen_full_hp()
	_test_regen_during_shadow()
	_test_act_boon()
	_test_act_boon_shadow()
	_test_tough()
	_test_tough_shadow()


# 回春：普通房 +4，真实入口 apply_victory_perks("normal")
func _test_regen() -> void:
	_duel.growth.reset_run()
	_duel.growth.grant_perk("regen")
	_reset(30, 100)
	_duel.growth.apply_victory_perks("normal")
	_check(int(_duel.player_hp) == 34, "回春 真实 HP=34（实测 %d）" % int(_duel.player_hp))
	_assert_hud("回春", 34, 100)

# 回春满血：不溢出，HP 不变、标签仍满
func _test_regen_full_hp() -> void:
	_duel.growth.reset_run()
	_duel.growth.grant_perk("regen")
	_reset(100, 100)
	_duel.growth.apply_victory_perks("normal")
	_check(int(_duel.player_hp) == 100, "回春满血 HP 不变（实测 %d）" % int(_duel.player_hp))
	_assert_hud("回春满血", 100, 100)

# 回春 + 受击影子未释放：真实 HP 高于影子，必须跟随真实值不被遮蔽
func _test_regen_during_shadow() -> void:
	_duel.growth.reset_run()
	_duel.growth.grant_perk("regen")
	_duel.hud.reset_enemy_hit_hold()
	_duel.player_hp = 30
	_duel.player_hp_max = 100
	_duel.hud.hold_enemy_hit(10, "fire", 32)   # 影子=32（低于治疗后的 34）
	_duel.invalidate_state()
	_duel.hud._refresh_meta()
	_duel.growth.apply_victory_perks("normal")
	_check(int(_duel.player_hp) == 34, "回春影子期 真实 HP=34（实测 %d）" % int(_duel.player_hp))
	_assert_hud("回春影子期", 34, 100)

# T1.7 收口：幕间锻魂只发 +8 符号伤害，不改最大 HP/当前 HP。
# HUD 刷新不得因此失效——验证锻魂后 HP 标签/血条仍显示真实值（未被旧值遮蔽）。
func _test_act_boon() -> void:
	_duel.growth.reset_run()
	_reset(50, 100)
	var power0: int = int(_duel._reward_system.run_power_bonus)
	_duel.growth.grant_act_boon(2)
	_check(int(_duel.player_hp_max) == 100, "锻魂 最大 HP 不变=100（实测 %d）" % int(_duel.player_hp_max))
	_check(int(_duel.player_hp) == 50, "锻魂 当前 HP 不变=50（实测 %d）" % int(_duel.player_hp))
	_check(int(_duel._reward_system.run_power_bonus) == power0 + 8, "锻魂 符号伤害 +8")
	_assert_hud("锻魂", 50, 100)

# 锻魂 + 影子未释放：锻魂不改 HP，HUD 应继续显示真实 HP（不被幽灵值遮蔽）
func _test_act_boon_shadow() -> void:
	_duel.growth.reset_run()
	_duel.hud.reset_enemy_hit_hold()
	_duel.player_hp = 50
	_duel.player_hp_max = 100
	# 影子=45（低于当前真实 HP=50）：锻魂触发 _refresh_meta 后，HUD 应显示真实 HP 50，
	# 不被旧影子遮蔽——验证「HUD 刷新入口不因锻魂收口而失效」。
	_duel.hud.hold_enemy_hit(10, "fire", 45)
	_duel.invalidate_state()
	_duel.hud._refresh_meta()
	_duel.growth.grant_act_boon(3)
	_check(int(_duel.player_hp) == 50, "锻魂影子期 当前 HP 不变=50（实测 %d）" % int(_duel.player_hp))
	_assert_hud("锻魂影子期", 50, 100)

# 坚韧：最大 HP +10、当前 HP +10，真实入口 pick("tough")
func _test_tough() -> void:
	_duel.growth.reset_run()
	_reset(40, 100)
	var ok: bool = _duel.growth.pick("tough")
	_check(ok, "坚韧 pick 成功")
	_check(int(_duel.player_hp_max) == 110, "坚韧 最大 HP=110（实测 %d）" % int(_duel.player_hp_max))
	_check(int(_duel.player_hp) == 50, "坚韧 当前 HP=50（实测 %d）" % int(_duel.player_hp))
	_assert_hud("坚韧", 50, 110)

# 坚韧 + 影子未释放
func _test_tough_shadow() -> void:
	_duel.growth.reset_run()
	_duel.hud.reset_enemy_hit_hold()
	_duel.player_hp = 40
	_duel.player_hp_max = 100
	_duel.hud.hold_enemy_hit(10, "fire", 45)   # 影子=45（低于治疗后的 50）
	_duel.invalidate_state()
	_duel.hud._refresh_meta()
	_duel.growth.pick("tough")
	_check(int(_duel.player_hp) == 50, "坚韧影子期 当前 HP=50（实测 %d）" % int(_duel.player_hp))
	_assert_hud("坚韧影子期", 50, 110)


func _finish() -> void:
	print("---")
	print("T0-4 RESULT: %d checks, %d fails" % [_checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)
