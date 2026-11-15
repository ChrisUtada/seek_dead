extends Node

# 双武器槽通用成长（2026-11-15）
# 方案：docs/武器成长与BOSS换装解耦_执行方案_2026-11-15.md
#
# 核心契约：通用数值（锋铸 / 校准 / 暴虐）跟随**槽位**，换装立即继承且只生效一份；
# 熟练与调律跟随**具体武器**，换来换去不复制、不丢失。
#
# Step 0 时这些断言在旧实现上应当失败（旧实现把通用铭印挂在武器路径上）。
# 运行：Godot --headless --fixed-fps 60 --path . res://tests/weapon_slot_growth_test.tscn

const DUEL_SCENE := "res://scenes/duel/duel.tscn"
const SLOT_A := "res://resources/weapon_templates/cinder_cleaver.tres"   # arch1 锋铸/调律
const SLOT_B := "res://resources/weapon_templates/blight_spear.tres"     # arch1 锋铸/调律
const SWAP_C := "res://resources/weapon_templates/cinder_hatchet.tres"   # arch1 锋铸/调律

var _pass := 0
var _fail := 0
var _duel


func _ready() -> void:
	await _run()


func _run() -> void:
	_duel = load(DUEL_SCENE).instantiate()
	add_child(_duel)
	await _frames(4)
	_check(_duel != null and _duel.mastery != null, "运行时有武器熟练系统")
	if _duel == null or _duel.mastery == null:
		_finish()
		return
	_equip([SLOT_A, SLOT_B])
	await _frames(2)

	print("=== A 双槽独立 ===")
	_test_two_slots()

	print("=== B 换装继承通用成长 ===")
	await _test_inherit_on_swap()

	print("=== C 预算与复制防护 ===")
	await _test_budget()

	print("=== D 调律仍属武器 ===")
	await _test_tune_stays_on_weapon()

	print("=== E 共享资源不被修改 ===")
	_test_resource_immutable()

	_finish()


# 新一局：清本局槽位成长再配装（槽位预算整局不重置，所以每组开头要显式开新局）。
func _new_run(paths: Array) -> void:
	if _duel.weapon_slots != null:
		_duel.weapon_slots.reset_run()
	_equip(paths)


func _equip(paths: Array) -> void:
	_duel.selected_loadout.clear()
	for p in paths:
		_duel.selected_loadout.append(String(p))
	_duel._build_pool(_duel.selected_loadout)
	_duel.invalidate_state()


# 用真实替换入口（Step 2 要落地的唯一入口）；旧实现里等价于 erase+append。
func _swap(slot: int, new_path: String) -> bool:
	if _duel.has_method("replace_weapon_at_slot"):
		return bool(_duel.replace_weapon_at_slot(slot, new_path))
	var old_path: String = String(_duel.selected_loadout[slot])
	_duel.selected_loadout.erase(old_path)
	_duel.selected_loadout.append(new_path)
	_duel._build_pool(_duel.selected_loadout)
	_duel.invalidate_state()
	return true


func _base_power(path: String) -> int:
	var wd: WeaponData = load(path)
	return int(wd.base_power) if wd != null else -1


func _test_two_slots() -> void:
	_new_run([SLOT_A, SLOT_B])
	_check(_duel.selected_loadout.size() == 2, "装了双武器（%d）" % _duel.selected_loadout.size())
	_check(int(_duel.slot_total(0)) == 0 and int(_duel.slot_total(1)) == 0,
		"新一局两槽通用成长均为 0（%d / %d）" % [int(_duel.slot_total(0)), int(_duel.slot_total(1))])

	var before_a: int = _duel.weapon_power(SLOT_A)
	var before_b: int = _duel.weapon_power(SLOT_B)
	_check(before_a == _base_power(SLOT_A), "初始攻击等于基础值（%d）" % before_a)

	# 槽 0 锋铸：只影响槽 0
	_duel.mastery.choose(SLOT_A, "forge")
	_check(int(_duel.slot_forge(0)) == 1, "槽 0 锋铸次数 1（%d）" % int(_duel.slot_forge(0)))
	_check(_duel.weapon_power(SLOT_A) == before_a + 2,
		"槽 0 武器攻击 +2（%d → %d）" % [before_a, _duel.weapon_power(SLOT_A)])
	_check(_duel.weapon_power(SLOT_B) == before_b,
		"槽 1 武器攻击不受影响（%d）" % _duel.weapon_power(SLOT_B))


func _test_inherit_on_swap() -> void:
	_new_run([SLOT_A, SLOT_B])
	_duel.mastery.choose(SLOT_A, "forge")
	_duel.mastery.choose(SLOT_A, "forge")
	var old_power: int = _duel.weapon_power(SLOT_A)
	_check(old_power == _base_power(SLOT_A) + 4, "槽 0 两次锋铸 = +4（%d）" % old_power)

	var ok := _swap(0, SWAP_C)
	_check(ok, "替换入口接受合法新武器")
	_check(String(_duel.selected_loadout[0]) == SWAP_C, "槽 0 已换成新武器")
	_check(String(_duel.selected_loadout[1]) == SLOT_B,
		"槽 1 未被移动（%s）" % String(_duel.selected_loadout[1]))

	var new_power: int = _duel.weapon_power(SWAP_C)
	_check(new_power == _base_power(SWAP_C) + 4,
		"新武器继承槽 0 锋铸（%d = %d + 4）" % [new_power, _base_power(SWAP_C)])

	# 卸下的旧武器不再贡献：它的数值不再进入任何槽
	_check(_duel.weapon_power(SLOT_B) == _base_power(SLOT_B), "槽 1 仍无锋铸")


func _test_budget() -> void:
	_new_run([SLOT_A, SLOT_B])
	# 槽 0 通用预算 2 次（锋铸 + 校准）
	_check(_duel.mastery.choose(SLOT_A, "forge"), "第 1 次通用铭印成功")
	_check(_duel.mastery.choose(SLOT_A, "calibrate"), "第 2 次通用铭印成功")
	_check(int(_duel.slot_total(0)) == 2, "槽 0 已用满 2 次（%d）" % int(_duel.slot_total(0)))
	_check(not _duel.mastery.choose(SLOT_A, "tyrant"), "预算满后第 3 次被拒")
	_check(not _duel.mastery.choose(SLOT_A, "forge"), "预算满后同项追加被拒")
	_check(int(_duel.slot_total(0)) == 2, "被拒后预算不变（%d）" % int(_duel.slot_total(0)))

	# 换装不刷新预算
	_swap(0, SWAP_C)
	_check(int(_duel.slot_total(0)) == 2, "换装后预算仍是 2（%d）" % int(_duel.slot_total(0)))
	_check(not _duel.mastery.choose(SWAP_C, "forge"), "换装不能刷新预算")

	# 卸下再装回也不能刷新
	_swap(0, SLOT_A)
	_check(int(_duel.slot_total(0)) == 2, "装回原武器后预算仍是 2（%d）" % int(_duel.slot_total(0)))
	_check(not _duel.mastery.choose(SLOT_A, "forge"), "卸下装回不能刷新预算")


func _test_tune_stays_on_weapon() -> void:
	_new_run([SLOT_A, SLOT_B])
	var tgt: Dictionary = _duel.mastery.tune_target(SLOT_A)
	if tgt.is_empty():
		_check(true, "（本武器无合法调律目标，跳过调律归属断言）")
	else:
		_check(_duel.mastery.choose(SLOT_A, "tune", String(tgt["sym"])), "调律写入旧武器")
		var tune_before: Dictionary = _duel.mastery.tune_map()
		_check(tune_before.has(SLOT_A), "旧武器有调律记录")
		_swap(0, SWAP_C)
		var tune_after: Dictionary = _duel.mastery.tune_map()
		_check(tune_after.has(SLOT_A), "卸下后旧武器调律仍保留")
		_check(not tune_after.has(SWAP_C), "新武器不继承调律")
		_check(int(_duel.slot_total(0)) == 0, "调律不占通用数值预算（%d）" % int(_duel.slot_total(0)))


func _test_resource_immutable() -> void:
	var wd: WeaponData = load(SLOT_A)
	var base_before: int = int(wd.base_power)
	var hit_before: float = float(wd.hit_rate)
	_new_run([SLOT_A, SLOT_B])
	_duel.mastery.choose(SLOT_A, "forge")
	_duel.mastery.choose(SLOT_A, "calibrate")
	_duel.weapon_power(SLOT_A)
	_duel.weapon_hit(SLOT_A)
	var wd2: WeaponData = load(SLOT_A)
	_check(int(wd2.base_power) == base_before, "共享资源 base_power 未被改写（%d）" % int(wd2.base_power))
	_check(absf(float(wd2.hit_rate) - hit_before) < 0.0001,
		"共享资源 hit_rate 未被改写（%.2f）" % float(wd2.hit_rate))


func _finish() -> void:
	print("SLOTGROWTH|RESULT %s (checks=%d fails=%d)" % [
		"PASS" if _fail == 0 else "FAIL", _pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


func _check(ok: bool, what: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("FAIL  " + what)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
