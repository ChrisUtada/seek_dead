extends Node

# C-01（2026-11-22）：治疗血量必须显示在血条/HP 标签上。
# 回归根因：N-03 的玩家幽灵影子 _hp_display_hold 在敌人攻击命中帧前显示扣血前值，
# 若此时发生治疗，旧逻辑一律读影子值 → 治疗后的真实 HP 被遮蔽，血条/标签卡住不涨。
# 修复：幽灵值只在真实 HP 未超过影子（扣血未到命中帧）时显示；治疗使真实 HP 高于影子时跟随真实值。

var _fails := 0
var _checks := 0
var _duel: DuelController

func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("C01 FAIL: " + label)

func _ready() -> void:
	await get_tree().process_frame
	SaveSystem.reset_lobby_data()
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	_duel = scene_res.instantiate() as DuelController
	add_child(_duel)
	await get_tree().process_frame
	await get_tree().process_frame
	_duel.demo_config.enabled = false
	_duel._confirm_loadout()
	await get_tree().process_frame

	_test_plain_heal()
	_test_heal_during_enemy_hit_shadow()
	_test_shadow_still_masks_before_hit()
	_test_heal_display_hold()

	_finish()

func _refresh() -> void:
	_duel.invalidate_state()
	_duel.hud._refresh_meta()

# 无影子值：普通治疗反映到标签与血条。
func _test_plain_heal() -> void:
	_duel.hud.reset_enemy_hit_hold()
	_duel.player_hp = 30
	_duel.player_hp_max = 100
	_refresh()
	_ok(_duel.hud.player_hp_label.text == "30/100", "治疗前标签=30/100（实测 %s）" % _duel.hud.player_hp_label.text)
	_ok(absf(_duel.hud.player_hp_bar.ratio - 0.3) < 0.01, "治疗前血条=0.3（实测 %.3f）" % _duel.hud.player_hp_bar.ratio)
	_duel.player_hp = 70
	_refresh()
	_ok(_duel.hud.player_hp_label.text == "70/100", "治疗后标签=70/100（实测 %s）" % _duel.hud.player_hp_label.text)
	_ok(absf(_duel.hud.player_hp_bar.ratio - 0.7) < 0.01, "治疗后血条=0.7（实测 %.3f）" % _duel.hud.player_hp_bar.ratio)

# 核心回归：敌人攻击影子值未释放时治疗，血条/标签必须跟随真实 HP（不被影子遮蔽）。
func _test_heal_during_enemy_hit_shadow() -> void:
	_duel.hud.reset_enemy_hit_hold()
	_duel.hud.hold_enemy_hit(10, "fire", 40)   # 影子值=40（扣血前真实 HP）
	_ok(_duel.hud._hp_display_hold == 40, "前置：影子值=40")
	_duel.player_hp = 30
	_refresh()
	_ok(_duel.hud.player_hp_label.text == "40/100", "影子生效期显示扣血前值 40（实测 %s）" % _duel.hud.player_hp_label.text)
	# 治疗到 70（高于影子 40）：必须显示真实 70，而非卡在影子 40
	_duel.player_hp = 70
	_refresh()
	_ok(_duel.hud.player_hp_label.text == "70/100", "影子期治疗：标签跟随真实 70（实测 %s）" % _duel.hud.player_hp_label.text)
	_ok(absf(_duel.hud.player_hp_bar.ratio - 0.7) < 0.01, "影子期治疗：血条跟随真实 0.7（实测 %.3f）" % _duel.hud.player_hp_bar.ratio)

# 延迟表现契约：真实 HP 仍低于影子时，继续显示影子（命中帧才掉血），不被缺陷修复破坏。
func _test_shadow_still_masks_before_hit() -> void:
	_duel.hud.reset_enemy_hit_hold()
	_duel.hud.hold_enemy_hit(10, "fire", 40)
	_duel.player_hp = 30
	_refresh()
	_ok(_duel.hud.player_hp_label.text == "40/100", "扣血未到命中帧：仍显示影子 40（实测 %s）" % _duel.hud.player_hp_label.text)
	_ok(absf(_duel.hud.player_hp_bar.ratio - 0.4) < 0.01, "扣血未到命中帧：血条仍 0.4（实测 %.3f）" % _duel.hud.player_hp_bar.ratio)

# 2026-11-23：治疗显示锁——结算落地 HP 后血条保持旧值，直到演出帧释放才涨（与治愈音同步）。
func _test_heal_display_hold() -> void:
	_duel.hud.reset_enemy_hit_hold()
	_duel.player_hp = 30
	_duel.player_hp_max = 100
	_refresh()
	# 模拟结算：锁住旧血值 30，然后 HP 数据涨到 70
	_duel.hud.hold_heal_display(30)
	_duel.player_hp = 70
	_refresh()
	_ok(_duel.hud.player_hp_label.text == "30/100", "治疗锁生效期：标签仍显示旧值 30（实测 %s）" % _duel.hud.player_hp_label.text)
	_ok(absf(_duel.hud.player_hp_bar.ratio - 0.3) < 0.01, "治疗锁生效期：血条仍 0.3（实测 %.3f）" % _duel.hud.player_hp_bar.ratio)
	# 演出帧释放：血条涨到真实 70（与治愈音同帧）
	_duel.hud.release_heal_display()
	_refresh()
	_ok(_duel.hud.player_hp_label.text == "70/100", "治疗锁释放后：标签=70/100（实测 %s）" % _duel.hud.player_hp_label.text)
	_ok(absf(_duel.hud.player_hp_bar.ratio - 0.7) < 0.01, "治疗锁释放后：ratio=0.7（实测 %.3f）" % _duel.hud.player_hp_bar.ratio)
	# 增长动画：ratio 已=0.7，但 display_ratio 从旧值0.3开始渐变（动画期间 < ratio）
	_ok(_duel.hud.player_hp_bar.display_ratio < 0.7,
		"治疗增长动画：display_ratio 从旧值渐变（实测 %.3f < 0.7）" % _duel.hud.player_hp_bar.display_ratio)
	_ok(_duel.hud.player_hp_bar.grow_tween != null, "治疗增长 tween 存在")


func _finish() -> void:
	print("C01 RESULT: %d checks, %d fails" % [_checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)
