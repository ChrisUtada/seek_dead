extends SceneTree

# P1-A 冒烟基建 · L1 内容与数学 lint（纯静态层，最快、完全确定）
# 运行：Godot --headless --fixed-fps 60 --path <项目> --script res://tests/smoke_lint.gd
# 覆盖：资源全量可加载、目录规模下限、克制矩阵、意图分档表、BalanceConfig 关键字段、BattleMath 纯函数。
# ⚠ 本脚本必须可在 --script 模式编译：禁止引用 DuelController（其依赖链含 SaveSystem autoload，
# 在 --script 模式下不注册会导致编译失败）——BalanceConfig 直接 load 资源。

var _fails := 0
var _checks := 0


func _initialize() -> void:
	seed(1)
	_check_dirs()
	_check_elements()
	_check_intents()
	_check_balance()
	_check_battle_math()
	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	quit(1 if _fails > 0 else 0)


func _check_dirs() -> void:
	var minimums := {
		"res://resources/weapon_templates": 24,
		"res://resources/charms": 34,
		"res://resources/skills": 17,
		"res://resources/consumables": 21,
		"res://resources/rooms": 61,
		"res://resources/archetypes": 15,
		"res://resources/intents": 6,
		"res://resources/statuses": 4,
		"res://resources/symbols": 40,
		"res://resources/rewards": 1,
		"res://resources/synergies": 3,
	}
	for dir_path in minimums.keys():
		var n := _count_tres(dir_path)
		_check(n >= int(minimums[dir_path]), "%s ≥%d，实测 %d" % [dir_path, int(minimums[dir_path]), n])
	# 全量可加载 + 字段合法性
	var rooms := 0
	for fp in _all_tres("res://resources"):
		var res: Resource = load(fp)
		if res == null:
			_fail("加载失败 %s" % fp)
			continue
		if res is RoomData:
			rooms += 1
			var r: RoomData = res
			_check(r.kind in ["normal", "elite", "boss"], "kind 合法 %s" % fp)
			_check(r.act >= 1 and r.act <= 3, "act 合法 %s" % fp)
			_check(ElementCounter.is_valid_element(r.element), "element 合法 %s" % fp)
			_check(r.name != "", "name 非空 %s" % fp)
			for it in r.intents:
				_check(it != null and StatusSystem.INTENT_DEFS.has(it.id), "房间意图 id 已定义 %s (%s)" % [fp, it.id if it != null else "?"])
			if r.archetype != null:
				_check(r.archetype.id != "", "行为族引用有效 %s" % fp)
	_check(rooms >= 61, "RoomData 总数 ≥61，实测 %d" % rooms)


func _count_tres(dir_path: String) -> int:
	var n := 0
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return 0
	for f in dir.get_files():
		if f.ends_with(".tres"):
			n += 1
	return n


func _all_tres(root: String) -> Array[String]:
	var out: Array[String] = []
	var stack: Array[String] = [root]
	while not stack.is_empty():
		var dpath: String = stack.pop_back()
		var dir := DirAccess.open(dpath)
		if dir == null:
			continue
		for f in dir.get_files():
			if f.ends_with(".tres"):
				out.append(dpath + "/" + f)
		for dn in dir.get_directories():
			stack.append(dpath + "/" + dn)
	return out


func _check_elements() -> void:
	# 克制矩阵快照（互克对 + 毒链，v2 定稿）
	var expect := {
		["fire", "ice"]: 1.5, ["ice", "fire"]: 1.5,
		["light", "dark"]: 1.5, ["dark", "light"]: 1.5,
		["fire", "poison"]: 1.5, ["poison", "dark"]: 1.5,
		["ice", "poison"]: 1.0, ["poison", "fire"]: 0.85,
		["poison", "light"]: 0.85, ["dark", "poison"]: 0.85,
		["fire", "fire"]: 0.85, ["none", "fire"]: 1.0, ["fire", "none"]: 1.0,
	}
	for k in expect.keys():
		var m: float = ElementCounter.multiplier(k[0], k[1])
		_check(abs(m - float(expect[k])) < 0.001, "克制 %s→%s = %s" % [k[0], k[1], expect[k]])
	_check(ElementCounter.weakness("dark").size() == 2, "暗系弱点数（光+毒）")
	_check(ElementCounter.weakness("none").is_empty(), "无属性无弱点")


func _check_intents() -> void:
	var defs: Dictionary = StatusSystem.INTENT_DEFS
	for id in ["attack", "heavy", "jam", "lock", "chaos", "auto_stop"]:
		_check(defs.has(id), "意图已定义 %s" % id)
	var purif: Dictionary = StatusSystem.INTENT_UNLOCK_ACT
	for k in purif.keys():
		_check(defs.has(k), "解锁表键均已定义 %s" % k)
	for act in StatusSystem.ACT_INTENT_WEIGHTS.keys():
		for kind in StatusSystem.ACT_INTENT_WEIGHTS[act].keys():
			var tbl: Dictionary = StatusSystem.ACT_INTENT_WEIGHTS[act][kind]
			var total := 0
			for k in tbl:
				total += int(tbl[k])
			_check(total > 0, "分档表正权重 act%d/%s" % [int(act), kind])
			for k in tbl.keys():
				_check(defs.has(k), "分档表意图已定义 act%d/%s/%s" % [int(act), kind, k])
	# Act1 分档不含任何需 Act2+ 解锁的意图
	for kind in StatusSystem.ACT_INTENT_WEIGHTS[1].keys():
		var tbl1: Dictionary = StatusSystem.ACT_INTENT_WEIGHTS[1][kind]
		for k in tbl1.keys():
			_check(int(purif.get(k, 1)) <= 1, "Act1 分档仅含解锁幕≤1 的意图（实测含 %s）" % k)


func _check_balance() -> void:
	var b: Resource = load("res://resources/config/balance_config.tres")
	for field in ["player_hp_base", "crit_chance", "charge_max", "ante_act_step_hp", "ante_act_step_atk", "ante_room_step_hp", "ante_room_step_atk", "player_dmg_mult", "gold_per_coin"]:
		var v = b.get(field)
		_check(v != null and float(v) > 0.0, "BalanceConfig.%s > 0（=%s）" % [field, v])
	_check(float(b.crit_chance) < 1.0, "crit_chance < 1")
	_check(float(b.ante_act_step_hp) >= 1.0 and float(b.ante_act_step_atk) >= 1.0, "ante 幕间台阶 ≥1（递增曲线）")
	# 三拍板键值（2026-08-24）
	for kv in [["anvil_award_normal", 0], ["anvil_award_elite", 3], ["anvil_award_boss", 5], ["anvil_award_final", 8]]:
		_check(int(b.get(kv[0])) == int(kv[1]), "BalanceConfig.%s == %s" % [kv[0], kv[1]])
	var hoc: float = float(b.heal_overflow_shield_cap_pct)
	_check(hoc > 0.0 and hoc <= 1.0, "heal_overflow_shield_cap_pct ∈ (0,1]（=%s）" % hoc)


func _check_battle_math() -> void:
	_check(abs(BattleMath.buff_damage_mult({}) - 1.0) < 0.001, "空增益乘区 = 1.0")
	_check(abs(BattleMath.agg_power_flat(2, 3, {}) - 5.0) < 0.001, "加法聚合 2+3=5")
	_check(abs(BattleMath.agg_damage_mult(1.5, {}) - 1.5) < 0.001, "乘法聚合空增益透传")


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