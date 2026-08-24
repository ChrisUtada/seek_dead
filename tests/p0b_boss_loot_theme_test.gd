extends SceneTree

# P0-B BOSS 掉落主题一致性 + 资源名乱码哨兵 · headless 回归（2026-08-24）
# 运行：Godot_v4.7 --headless --path <项目> --script res://tests/p0b_boss_loot_theme_test.gd
# 背景：《未完成任务_总清单》T32 曾记「呓语教徒池 poison_dagger/pistol/dagger 错配」——
# 实测当前代码该错配不存在（已是 holy_sword/dawn_bow/iron_sword），本测试锁定 12 BOSS 全量主题规则防回退。

var _fails := 0
var _checks := 0


func _initialize() -> void:
	var dir := DirAccess.open("res://resources/rooms")
	var bosses: Array[RoomData] = []
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var r: RoomData = load("res://resources/rooms/" + f)
		if r == null:
			_fail("房间加载失败 %s" % f)
			continue
		# ① 全房间 name 哨兵：非空 + 无私有区字符（双重编码乱码的残留信号）
		if r.kind != "boss" or true:
			pass
		_check(r.name != "", "name 非空 %s" % f)
		_check(not _has_pua(r.name), "name 无乱码信号 %s (%s)" % [f, r.name])
		if r.kind == "boss":
			bosses.append(r)

	_check(bosses.size() == 13, "BOSS 房数量 13，实测 %d" % bosses.size())

	for b in bosses:
		var fid: String = b.resource_path.get_file()
		if b.final_boss:
			# T32 既定规则：真·最终无主题武器池（毕业战合理）
			_check(b.boss_reward_weapons.is_empty(), "真·最终无掉落池 %s" % fid)
			continue
		_check(b.boss_reward_weapons.size() >= 2, "%s 掉落池 ≥2 把，实测 %d" % [fid, b.boss_reward_weapons.size()])

		# 每个引用可加载为 WeaponData 且元素合法
		var elems: Array[String] = []
		for wp in b.boss_reward_weapons:
			_check(ResourceLoader.exists(wp), "%s 引用存在 %s" % [fid, wp])
			var w: WeaponData = load(wp)
			_check(w != null, "%s 加载为 WeaponData：%s" % [fid, wp.get_file()])
			if w != null:
				elems.append(w.element)

		# 主题规则：至少 2 把武器克制 BOSS 的（阶段）元素；none 补位不计入
		var phase_elems := [b.element]
		if b.resource_path.contains("shattered_king"):
			phase_elems = ["fire", "ice", "poison"]   # 人格裂变三阶段：火→冰→毒，一池需覆盖多阶段弱点
		var counter_count := 0
		for e in elems:
			if e == "none":
				continue
			for pe in phase_elems:
				if ElementCounter.multiplier(e, pe) == 1.5:
					counter_count += 1
					break
		_check(counter_count >= 2, "%s [%s] 克制武器 ≥2，实测 %s" % [fid, b.element, elems])

		# 信物挂接：11 常规 BOSS 均有 boss_relic_path（T32 规则）
		_check(b.boss_relic_path != "" and ResourceLoader.exists(b.boss_relic_path),
			"%s 信物存在 %s" % [fid, b.boss_relic_path])

	# ② 专项：呓语教徒（本次修复对象）——名字恢复 + 光系主题
	var cultist: RoomData = load("res://resources/rooms/whispering_cultist.tres")
	_check(cultist.name == "呓语教徒", "呓语教徒 name 已修复，实测「%s」" % cultist.name)
	var c_elems: Array[String] = []
	for wp in cultist.boss_reward_weapons:
		c_elems.append((load(wp) as WeaponData).element)
	_check(c_elems[0] == "light" and c_elems[1] == "light",
		"呓语教徒池前两把光系（dark 弱光），实测 %s" % [c_elems])

	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	quit(1 if _fails > 0 else 0)


func _has_pua(s: String) -> bool:
	for c in s:
		if ord(c) >= 0xE000 and ord(c) <= 0xF8FF:
			return true
	return false


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("PASS  ", label)
	else:
		_fails += 1
		printerr("FAIL  ", label)


func _fail(label: String) -> void:
	_checks += 1
	_fails += 1
	printerr("FAIL  ", label)