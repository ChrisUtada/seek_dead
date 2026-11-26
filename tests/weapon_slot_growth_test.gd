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
const SLOT_A := "res://resources/weapon_templates/holy_sword.tres"   # T3 阶段 1：归档件不可用于新增熟练，改正式池
const SLOT_B := "res://resources/weapon_templates/ice_gun.tres"
const SWAP_C := "res://resources/weapon_templates/fire_sword.tres"   # 火系，替换后 fire_slash 仍在带上

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

	print("=== F 替换预览与真实一致 ===")
	await _test_preview_matches_actual()

	print("=== G Step 6 数值对照 ===")
	_test_element_vs_growth()
	_test_catchup_across_levels()
	_test_budget_exhausted()
	await _test_strip_consistency()

	print("=== H S2 校准命中进入真实建池 ===")
	await _test_calibrate_miss_cells()

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


# Step 5：弹层里的「假设装入该槽」数值必须与替换完成后的真实面板逐项一致。
func _test_preview_matches_actual() -> void:
	_new_run([SLOT_A, SLOT_B])
	_duel.weapon_slots.choose(0, "forge")
	_duel.weapon_slots.choose(0, "calibrate")
	var preview_atk: int = _duel.weapon_power_in_slot(SWAP_C, 0)
	var preview_hit: float = _duel.weapon_hit_in_slot(SWAP_C, 0)
	_swap(0, SWAP_C)
	_check(_duel.weapon_power(SWAP_C) == preview_atk,
		"预览攻击 = 替换后实际（%d）" % preview_atk)
	_check(absf(_duel.weapon_hit(SWAP_C) - preview_hit) < 0.0001,
		"预览命中 = 替换后实际（%.2f）" % preview_hit)

	# 摘要必须分成「槽位锻造 / 武器专精」两段，且槽位段标注换装继承
	var info: String = _duel._weapon_info(SWAP_C, 0)
	_check(info.find("槽位锻造") >= 0, "摘要含槽位锻造段")
	_check(info.find("武器专精") >= 0, "摘要含武器专精段")
	_check(info.find("换装继承") >= 0, "槽位段标注换装继承")
	_check(info.find("锋铸×1") >= 0 and info.find("校准×1") >= 0, "槽位段列出锋铸与校准")

	# 卸下说明带槽号，且说明调律/熟练保留、贡献暂停
	var off: String = _duel._weapon_off_info(SLOT_B, 1)
	_check(off.find("武器槽 2") >= 0, "卸下说明带槽号（%s）" % off)
	_check(off.find("暂停贡献") >= 0, "卸下说明写明卸下后暂停贡献")


# 场景 1：通用成长与元素克制是两条独立的线——换克制武器后通用继承、克制仍来自倍率。
func _test_element_vs_growth() -> void:
	_new_run([SLOT_A, SLOT_B])
	_duel.weapon_slots.choose(0, "forge")
	var atk_before: int = _duel.weapon_power(SLOT_A)
	# 同槽换成火系武器：通用 +2 必须跟着槽走
	_swap(0, SWAP_C)
	_check(_duel.weapon_power(SWAP_C) == _base_power(SWAP_C) + 2,
		"克制武器继承通用锋铸（%d）" % _duel.weapon_power(SWAP_C))
	# 元素倍率独立计算，不受槽位成长影响
	# 本轮不改倍率，只断言「倍率可计算且与槽位成长互不影响」。
	var fire_vs_ice: float = ElementCounter.multiplier("fire", "ice")
	var poison_vs_ice: float = ElementCounter.multiplier("poison", "ice")
	_check(fire_vs_ice > 0.0 and poison_vs_ice > 0.0,
		"元素倍率可计算（火 ×%.2f / 毒 ×%.2f）" % [fire_vs_ice, poison_vs_ice])
	_check(atk_before == _base_power(SLOT_A) + 2, "换装前攻击只含槽位成长（%d）" % atk_before)


# 场景 3：新武器连续清房——追赶与跨级欠选都不能丢。
func _test_catchup_across_levels() -> void:
	_new_run([SLOT_A, SLOT_B])
	_duel.mastery.mastery[SLOT_B] = 8    # 另一把已到 R3，作为追赶目标
	_duel.mastery.mastery[SLOT_A] = 0
	_duel.mastery.owed.clear()
	var target: int = _duel.mastery.catchup_target(SLOT_A)
	_check(target == 8, "追赶目标是本局其他武器最高熟练（%d）" % target)
	# 连清 3 房，每房 +1
	for i in range(3):
		_duel.mastery.grant_points(SLOT_A, 1, "清房")
	_check(int(_duel.mastery.mastery.get(SLOT_A, 0)) == 3, "三房后熟练 3（%d）" % int(_duel.mastery.mastery.get(SLOT_A, 0)))
	_check(_duel.mastery.r_level(SLOT_A) == 2, "跨过 R2（R%d）" % _duel.mastery.r_level(SLOT_A))
	_check(_duel.mastery.owed.has(SLOT_A), "R2 产生一次欠选")
	# 一次跨两级：3 → 12 应同时欠 R3（不能只欠一次）
	_duel.mastery.owed.clear()
	_duel.mastery.grant_points(SLOT_A, 9, "跨级")
	_check(_duel.mastery.r_level(SLOT_A) == 4, "跨级到 R4（R%d）" % _duel.mastery.r_level(SLOT_A))
	# 3→12 只跨过 R3（R2 已经在 3 熟练时跨过），所以只欠一次
	_check(_duel.mastery.owed.size() == 1, "跨 R3 欠一次（%d）" % _duel.mastery.owed.size())


# 场景 7：满预算 Build 不再出现通用候选（不产生「选了也不变」的死卡）。
func _test_budget_exhausted() -> void:
	_new_run([SLOT_A, SLOT_B])
	_duel.weapon_slots.choose(0, "forge")
	_duel.weapon_slots.choose(0, "tyrant")
	_check(int(_duel.slot_total(0)) == 2, "槽 0 预算已满（%d）" % int(_duel.slot_total(0)))
	var ids: Array = []
	for c in _duel.mastery.imprint_choices(SLOT_A):
		ids.append(String(c.get("id", "")))
	for forbidden in ["forge", "calibrate", "tyrant"]:
		_check(not ids.has(forbidden), "预算满后不再出现 %s 候选（%s）" % [forbidden, str(ids)])
	# 另一槽仍然可以正常选
	_check(_duel.weapon_slots.can_choose(1, "forge"), "槽 1 预算未受影响")


# 场景 8：卡片与真实建带同向——预览说「有变化」时格数必须真的变，反之亦然。
func _test_strip_consistency() -> void:
	_new_run([SLOT_A, SLOT_B])
	var styles: Dictionary = _duel._forge_styles.preview_map() if _duel._forge_styles != null else {}
	var tune: Dictionary = _duel.mastery.tune_map()
	var sig_before: String = _strip_signature()
	var hypo: Array = _duel.selected_loadout.duplicate()
	hypo.remove_at(0)
	hypo.insert(0, SWAP_C)     # 同槽原位替换（不是 erase+append）
	var lines := ReelPreview.diff_lines(
		_duel.selected_loadout, hypo,
		_duel.selected_skills, _duel.selected_charms,
		_duel.room_element_mult, _duel._reward_system.run_symbol_bonus,
		_duel.deprived_level, _duel.pending_chaos, int(_duel.boss_trash),
		tune, tune, styles, styles)
	_swap(0, SWAP_C)
	var sig_after: String = _strip_signature()
	# 预览描述的是「符号分布」变化，所以对齐的也是分布签名（不是单个符号的格数）。
	_check((not lines.is_empty()) == (sig_after != sig_before),
		"预览与真实建带同向（预览 %s / 分布 %s）" % [
			"有变化" if not lines.is_empty() else "无变化",
			"变化" if sig_after != sig_before else "未变"])
	_check(_sym_cells("fire_slash") > 0, "替换后火斩仍在带上（%d 格）" % _sym_cells("fire_slash"))


# S2 命中边界裁定 a：校准铭印必须进入真实建池，面板与实际 MISS 格同口径。
func _test_calibrate_miss_cells() -> void:
	_new_run([SLOT_A, SLOT_B])
	# 面板命中 == 建池命中（统一口径的核心断言）
	var panel_hit: float = _duel.weapon_hit_in_slot(SLOT_A, 0)
	var pool_hit: float = -1.0
	for it in _duel.pool_items:
		if String(it.get("name", "")) == String(_shop_name(SLOT_A)):
			pool_hit = float(it.get("hit", -1.0))
			break
	_check(absf(panel_hit - pool_hit) < 0.0001,
		"建池命中与面板一致（面板 %.3f / 建池 %.3f）" % [panel_hit, pool_hit])
	var miss_before: int = _miss_cells()
	# 给槽位 0 加一次校准（+5% 命中），重建池
	var ok: bool = _duel.weapon_slots.choose(0, "calibrate") if _duel.weapon_slots != null else false
	_check(ok, "槽位 0 校准铭印成功")
	_duel._build_pool(_duel.selected_loadout)
	var pool_hit2: float = -1.0
	for it in _duel.pool_items:
		if String(it.get("name", "")) == String(_shop_name(SLOT_A)):
			pool_hit2 = float(it.get("hit", -1.0))
			break
	_check(pool_hit2 > pool_hit + 0.0001,
		"校准后建池命中真实上升（%.3f → %.3f）" % [pool_hit, pool_hit2])
	var miss_after: int = _miss_cells()
	_check(miss_after <= miss_before,
		"校准后 MISS 格不增加（%d → %d）" % [miss_before, miss_after])


func _shop_name(path: String) -> String:
	var wd: WeaponData = load(path)
	return wd.weapon_name if wd != null else path.get_file().get_basename()


# 统计真实转轮带上的 MISS 格数（S2 命中口径验证）。
func _miss_cells() -> int:
	var n := 0
	_duel.reel_system.build_strips()
	for strip in _duel.reel_system.reel_strips:
		for cell in strip:
			if cell[0] != null and String(cell[0].resource_path).ends_with("/miss.tres"):
				n += 1
	return n


# 转轮带符号分布签名：每种符号的总格数，排序后拼接（用于判断「带子是否真的变了」）。
func _strip_signature() -> String:
	_duel.reel_system.build_strips()
	var counts := {}
	for strip in _duel.reel_system.reel_strips:
		for cell in strip:
			var sym = cell[0]
			var key: String = "?" if sym == null else String(sym.resource_path).get_file()
			counts[key] = int(counts.get(key, 0)) + 1
	var keys: Array = counts.keys()
	keys.sort()
	var parts: Array[String] = []
	for k in keys:
		parts.append("%s=%d" % [String(k), int(counts[k])])
	return ",".join(parts)


# 统计某符号在真实转轮带上的格数（按资源文件名匹配，避免符号显示名改动导致断言失效）。
func _sym_cells(sym_file: String) -> int:
	var n := 0
	# strips 是派生数据：按当前 pool_items 重建一次，保证读到的是「此刻装备」的真实带子。
	_duel.reel_system.build_strips()
	var strips: Array = _duel.reel_system.reel_strips
	for strip in strips:
		for cell in strip:
			var sym = cell[0]
			if sym != null and String(sym.resource_path).ends_with(sym_file + ".tres"):
				n += 1
	return n


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
