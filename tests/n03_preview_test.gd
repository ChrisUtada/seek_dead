extends Node

# N-03（2026-11-21）：双方攻击前血量预览——必测用例。
#
# 核心验收：账本（结算层顺带产出的只读分解值）必须与最终真实结算一致，且预览不改变结算。
# 覆盖：有盾 / 部分格挡 / 全格挡 / 护甲 / 穿透 / 超杀 / 多段攻击。
#
# 手法：直接调用结算闸口（enemy_deal_damage / apply_enemy_damage / _capture_enemy_preview），
# 断言账本分解值 == 结算前后真实 HP/护甲差，且账本自身不产生任何额外扣血。
# APPDATA 由 run_smoke.bat 隔离；本脚本首尾各自 reset_lobby_data，单独裸跑也不污染真实档。

var _fails := 0
var _checks := 0
var _duel: DuelController

func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("N03 FAIL: " + label)

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

	_test_no_shield()
	_test_partial_block()
	_test_full_block()
	_test_armor()
	_test_pierce()
	_test_enemy_pierce_bypass()
	_test_overkill()
	_test_multi_segment()
	_test_preview_does_not_change_settlement()

	_finish()

# 基线：玩家 HP=1000、盾=0；敌人 HP=1000、护甲=0；账本清零。
func _fresh() -> void:
	_duel.player_hp = 1000
	_duel.player_hp_max = 1000
	_duel.player_shield = 0
	_duel.enemy_hp = 1000
	_duel.enemy_hp_max = 1000
	_duel.enemy_armor = 0
	_duel.enemy_armor_max = 1000
	_duel.boss_atk_mult = 1.0
	_duel._pattern_enemy_atk_mult = 1.0
	if _duel.debuffs != null:
		_duel.debuffs.reset()
	_duel.damage_preview.reset(_duel.turn_count)
	# combat 内部 _turn_* 累加器只在 evaluate 的 _reset_turn_state 清零；测试直接调闸口需手动重置，
	# 否则上一用例的穿透/护甲累加值会残留，污染 _capture_enemy_preview 的分解口径。
	_duel.combat._reset_turn_state()

# 无盾：原始攻击=100，盾挡=0，HP损失=100。账本三段与真实扣血一致。
func _test_no_shield() -> void:
	_fresh()
	var hp_before: int = int(_duel.player_hp)
	_duel.combat.enemy_deal_damage(100, "attack")
	var pv = _duel.damage_preview
	_ok(pv.player_raw_attack == 100, "无盾：原始攻击=100（实测 %d）" % pv.player_raw_attack)
	_ok(pv.player_shield_blocked == 0, "无盾：盾挡=0")
	_ok(pv.player_hp_loss == 100, "无盾：HP损失=100（实测 %d）" % pv.player_hp_loss)
	_ok(hp_before - pv.player_hp_loss == int(_duel.player_hp), "无盾：预览 HP 与最终一致")
	_ok(pv.player_hp_before == hp_before, "无盾：幽灵值基准=出手前 HP")

# 有盾、部分格挡：盾=40，原始=100 → 盾挡=40，HP损失=60。
func _test_partial_block() -> void:
	_fresh()
	_duel.player_shield = 40
	var hp_before: int = int(_duel.player_hp)
	_duel.combat.enemy_deal_damage(100, "attack")
	var pv = _duel.damage_preview
	_ok(pv.player_raw_attack == 100, "部分格挡：原始攻击=100")
	_ok(pv.player_shield_blocked == 40, "部分格挡：盾挡=40（实测 %d）" % pv.player_shield_blocked)
	_ok(pv.player_hp_loss == 60, "部分格挡：HP损失=60（实测 %d）" % pv.player_hp_loss)
	_ok(hp_before - pv.player_total_hp_loss() == int(_duel.player_hp), "部分格挡：预览总损失与最终一致")
	_ok(int(_duel.player_shield) == 0, "部分格挡：盾已扣完")

# 全格挡：盾=200 ≥ 原始=100 → HP损失=0，盾扣 100。
func _test_full_block() -> void:
	_fresh()
	_duel.player_shield = 200
	_duel.combat.enemy_deal_damage(100, "attack")
	var pv = _duel.damage_preview
	_ok(pv.player_shield_blocked == 100, "全格挡：盾挡=100")
	_ok(pv.player_hp_loss == 0, "全格挡：HP损失=0")
	_ok(int(_duel.player_shield) == 100, "全格挡：盾剩 100")
	_ok(int(_duel.player_hp) == 1000, "全格挡：HP 不变")

# 护甲：敌人护甲=50，非穿透伤害=100 → 甲损失=50，HP损失=50。
func _test_armor() -> void:
	_fresh()
	_duel.enemy_armor = 50
	var hp_before: int = int(_duel.enemy_hp)
	var armor_before: int = int(_duel.enemy_armor)
	_duel.combat.apply_enemy_damage(100, false)
	_duel.combat._capture_enemy_preview(hp_before, armor_before)
	var pv = _duel.damage_preview
	_ok(pv.enemy_armor_loss == 50, "护甲：甲损失=50（实测 %d）" % pv.enemy_armor_loss)
	_ok(pv.enemy_hp_loss == 50, "护甲：HP损失=50（实测 %d）" % pv.enemy_hp_loss)
	_ok(pv.enemy_pierce_damage == 0, "护甲：穿透=0")
	_ok(pv.enemy_armor_before - pv.enemy_armor_loss == int(_duel.enemy_armor), "护甲：预览护甲与结算一致")
	_ok(hp_before - pv.enemy_total_hp_loss() == int(_duel.enemy_hp), "护甲：预览 HP 与结算一致")

# 穿透：敌人护甲=100，穿透伤害=60 → 甲损失=0，穿透=60，HP损失=60。
func _test_pierce() -> void:
	_fresh()
	_duel.enemy_armor = 100
	var hp_before: int = int(_duel.enemy_hp)
	var armor_before: int = int(_duel.enemy_armor)
	_duel.combat.apply_enemy_damage(60, true)
	_duel.combat._capture_enemy_preview(hp_before, armor_before)
	var pv = _duel.damage_preview
	_ok(pv.enemy_armor_loss == 0, "穿透：甲损失=0（护甲未被吃）")
	_ok(pv.enemy_pierce_damage == 60, "穿透：穿透伤害=60（实测 %d）" % pv.enemy_pierce_damage)
	_ok(pv.enemy_hp_loss == 0, "穿透：非穿透 HP 损失=0")
	_ok(int(_duel.enemy_armor) == 100, "穿透：护甲保持 100")
	_ok(hp_before - 60 == int(_duel.enemy_hp), "穿透：HP 直扣 60")

# 敌人护盾穿透旁路（圣辉游侠）：pierce_pct 直扣 HP，绕过闸口也必须入账。
func _test_enemy_pierce_bypass() -> void:
	_fresh()
	_duel.player_shield = 500
	_duel.enemy_attack_pierce_pct = 0.5
	# 现行设计：pierce_pct 额外直扣 HP（50），且 raw 全额(100)仍走闸口被盾挡（50 盾→挡 50 盾）。
	# 这里盾=500，闸口 eff=100 被全挡，HP 仅受旁路 50 直扣；账本两段分别记，不重算。
	var hp_before: int = int(_duel.player_hp)
	_duel.enemy_system._do_attack({"type": "attack", "value": 100})
	var pv = _duel.damage_preview
	_ok(pv.player_pierce_bypass == 50, "护盾穿透旁路：直扣=50（实测 %d）" % pv.player_pierce_bypass)
	_ok(pv.player_shield_blocked == 100, "护盾穿透旁路：闸口盾挡=100（raw 全额，实测 %d）" % pv.player_shield_blocked)
	_ok(pv.player_hp_loss == 0, "护盾穿透旁路：闸口 HP 损失=0")
	_ok(hp_before - pv.player_total_hp_loss() == int(_duel.player_hp), "护盾穿透旁路：预览总损失与最终一致")

# 超杀：一击伤害远超敌人 HP → 预览 HP 损失 = 实际掉血（不超发），与结算一致。
func _test_overkill() -> void:
	_fresh()
	_duel.enemy_hp = 30
	var hp_before: int = 30
	var armor_before: int = 0
	_duel.combat.apply_enemy_damage(9999, false)
	_duel.combat._capture_enemy_preview(hp_before, armor_before)
	var pv = _duel.damage_preview
	# 账本用 max(0, before-after) 记「实际可见损失」，超杀时只记到当前 HP 为止（30），
	# 不会把超发的 9999 计入预览——这正是「预览 = 可见结算，不超发」的要求。
	_ok(pv.enemy_hp_loss == 30, "超杀：账本只记可见损失 30（实测 %d）" % pv.enemy_hp_loss)
	_ok(int(_duel.enemy_hp) <= 0, "超杀：敌人 HP 已归零或以下")
	_ok(pv.enemy_hp_before - pv.enemy_total_hp_loss() == 0, "超杀：HUD 预览显示值 0（不超发）")

# 多段攻击：主攻击(100) + 追加(100)，盾 50 → 原始=200，盾挡=100，HP=100，只聚合一次。
func _test_multi_segment() -> void:
	_fresh()
	_duel.player_shield = 50
	var hp_before: int = int(_duel.player_hp)
	_duel.combat.enemy_deal_damage(100, "attack")   # 盾挡 50，HP 损失 50
	_duel.combat.enemy_deal_damage(100, "attack")   # 盾已空，HP 损失 100
	var pv = _duel.damage_preview
	_ok(pv.player_segment_count == 2, "多段：段数=2（实测 %d）" % pv.player_segment_count)
	_ok(pv.player_raw_attack == 200, "多段：原始攻击聚合=200（实测 %d）" % pv.player_raw_attack)
	_ok(pv.player_shield_blocked == 50, "多段：盾挡聚合=50（实测 %d）" % pv.player_shield_blocked)
	_ok(pv.player_hp_loss == 150, "多段：HP 损失聚合=150（实测 %d）" % pv.player_hp_loss)
	_ok(hp_before - pv.player_total_hp_loss() == int(_duel.player_hp), "多段：预览总损失与最终一致")
	_ok(pv.player_hp_before == hp_before, "多段：幽灵值只记第一段前 HP（不逐段重复）")

# 核心验收：预览的 hold/release 只改 HUD 显示值，绝不改真实 HP/护甲/盾。
func _test_preview_does_not_change_settlement() -> void:
	_fresh()
	_duel.enemy_armor = 50
	var hp_before: int = int(_duel.enemy_hp)
	var armor_before: int = int(_duel.enemy_armor)
	_duel.combat.apply_enemy_damage(80, false)
	_duel.combat._capture_enemy_preview(hp_before, armor_before)
	var hp_after_settle: int = int(_duel.enemy_hp)
	var armor_after_settle: int = int(_duel.enemy_armor)
	# hold：压幽灵值，但真实数值不动
	_duel.hud.hold_enemy_preview()
	_ok(int(_duel.enemy_hp) == hp_after_settle, "hold 后真实敌人 HP 不变")
	_ok(int(_duel.enemy_armor) == armor_after_settle, "hold 后真实敌人护甲不变")
	_ok(_duel.hud._ev_hp_display_hold == hp_before, "hold 只设幽灵显示值=结算前 HP")
	# release：切回真实值，真实数值仍不动
	_duel.hud.release_enemy_preview()
	_ok(int(_duel.enemy_hp) == hp_after_settle, "release 后真实敌人 HP 不变")
	_ok(_duel.hud._ev_hp_display_hold == -1, "release 清幽灵值（-1）")
	_ok(_duel.hud._ev_armor_display_hold == -1, "release 清幽灵护甲值（-1）")

func _finish() -> void:
	print("N03 RESULT: %d checks, %d fails" % [_checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)
