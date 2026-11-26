extends Node

# ============================================================================
# T3-1：状态迁移管道「惰性生效」验收（2026-11-26；对应基线 §5 T3-1）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/w01_status_migration_inert_test.tscn
#
# 本测试证明「管道装了但没启用」：
#   5.1 未迁移武器（fire_sword，status_migrated=false）的 burn 符号仍照常入池、照常进带；
#   5.2 同一配置下 _phase_migrated_status 不给敌人加任何状态（enemy_status 前后不变）；
#   5.3 默认值守卫：fire_sword 的 status_migrated == false 且 status_chance == 0.0。
# 任何一条失败都意味着「零行为变化」被破坏——这里不校验新功能，只校验未启用时的惰性。
# ============================================================================

const FIRE_SWORD := "res://resources/weapon_templates/fire_sword.tres"

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
	_duel.reel_system._timer.stop()

	# 固定配装：只装 fire_sword（未迁移，带 burn 符号），并重建池 + 带子。
	_duel.selected_loadout.assign([FIRE_SWORD])
	_duel.selected_skills.clear()
	_duel._build_pool(_duel.selected_loadout)
	_duel.reel_system.build_strips()

	_test_burn_symbol_still_in_pool()
	_test_no_status_without_migration()
	_test_defaults_are_inert()

	print("W01INERT|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


# 5.1：未迁移武器的状态符号不得被过滤——池（flatten_pool 结果）与带子两处都要有 burn.tres。
func _test_burn_symbol_still_in_pool() -> void:
	var pool_has := false
	for it in _duel.pool:
		var s = it[0]
		if s != null and String(s.resource_path).ends_with("burn.tres"):
			pool_has = true
			break
	var strip_has := false
	for strip in _duel.reel_system.reel_strips:
		for e in strip:
			if e != null and e.size() > 0 and String((e[0] as SymbolData).resource_path).ends_with("burn.tres"):
				strip_has = true
				break
		if strip_has:
			break
	_check(pool_has and strip_has,
		"未迁移武器：burn 符号仍在池/带中（pool=%s strip=%s）" % [pool_has, strip_has])


# 5.2：未迁移武器即使有伤害入账，也不得触发任何状态——enemy_status 前后必须完全相同。
func _test_no_status_without_migration() -> void:
	var wid := String(load(FIRE_SWORD).resource_path).get_file().get_basename()
	var wd: WeaponData = _duel.weapon_data_by_id(wid)
	var before := str(_duel.enemy_status)
	# 直接驱动阶段函数：模拟 fire_sword 本回合造成过伤害（source_dmg 键 = 武器 id）。
	_duel.combat._phase_migrated_status({"source_dmg": {wid: 100.0}})
	var after := str(_duel.enemy_status)
	_check(wd != null and before == after,
		"未迁移武器不挂状态：weapon_data_by_id=%s enemy_status %s → %s" % [str(wd != null), before, after])


# 5.3：默认值守卫——资源不写这 4 个字段时必须是惰性默认，且其它武器同样如此。
func _test_defaults_are_inert() -> void:
	var wd: WeaponData = load(FIRE_SWORD)
	_check(wd.status_migrated == false and wd.status_chance == 0.0,
		"fire_sword 默认惰性：status_migrated=%s status_chance=%.2f" % [str(wd.status_migrated), wd.status_chance])
