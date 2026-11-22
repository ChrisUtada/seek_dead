extends Node

# T1.9 第 3 步：只读探针，验证建带/落点链是否保留废铁来源的资源身份。
# 不修改任何生产代码，只检查 reel_strips 中废铁格 resource_path 是否保真。
# 结论用于决定第三档「仅敌人注废」能否用 resource_path 作为真实来源标记。

var _checks := 0
var _fails := 0

func _ready() -> void:
	await _run()
	print("T19ID|RESULT %s (checks=%d fails=%d)" % ["PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)

func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("T19ID|FAIL|" + label)

func _boot() -> DuelController:
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	return duel

func _run() -> void:
	var duel := await _boot()
	if duel == null:
		push_error("boot failed")
		get_tree().quit(2)
		return
	duel.selected_consumables.clear()
	duel.selected_charms.clear()
	duel.selected_skills.clear()
	duel._confirm_loadout()
	await get_tree().process_frame

	var miss_path := "res://resources/symbols/miss.tres"
	var trash_path := "res://resources/symbols/trash.tres"
	var rs := duel.reel_system
	rs.build_strips()

	# 统计带子中三类废铁身份：miss.tres / trash.tres / 其它（含被复制丢失路径的）
	var miss_cnt := 0
	var trash_cnt := 0
	var other_trash_cnt := 0
	var total := 0
	for strip in rs.reel_strips:
		for cell in strip:
			total += 1
			var sym = cell[0] if cell is Array else cell
			if sym == null:
				continue
			var p := String(sym.resource_path)
			var k := String(sym.kind)
			if k == "trash":
				if p == miss_path:
					miss_cnt += 1
				elif p == trash_path:
					trash_cnt += 1
				else:
					other_trash_cnt += 1

	_ok(total > 0, "reel_strips 非空")
	# 关键：identity 判据按 resource_path，不依赖对象引用相等。
	# miss/trash 都来自 preload 常量，build_strips 用 duplicate(true) 复制的是数组，
	# 资源对象本身不复制，因此 resource_path 必然保真。
	var all_trash := miss_cnt + trash_cnt + other_trash_cnt
	_ok(other_trash_cnt == 0, "所有废铁格保留可识别 resource_path (other=%d)" % other_trash_cnt)
	_ok(miss_cnt > 0, "精度 MISS 格存在且身份=miss.tres (n=%d)" % miss_cnt)
	print("T19ID|INFO total=%d miss=%d trash=%d other=%d" % [total, miss_cnt, trash_cnt, other_trash_cnt])

	# 验证对象引用层面是否也保真（判定资源是否被复制）。不作为判据，仅记录。
	var miss_obj = load(miss_path)
	var trash_obj = load(trash_path)
	var ref_miss := 0
	var ref_trash := 0
	for strip in rs.reel_strips:
		for cell in strip:
			var sym = cell[0] if cell is Array else cell
			if sym == null:
				continue
			if sym == miss_obj:
				ref_miss += 1
			if sym == trash_obj:
				ref_trash += 1
	print("T19ID|INFO ref_miss=%d ref_trash=%d" % [ref_miss, ref_trash])

	# 补测：构造敌人机制注入废铁（BOSS trash + 混乱），验证两种来源在同一带子里身份严格分离。
	duel.boss_trash = 3
	duel.pending_chaos = true
	rs.build_strips()
	var m2 := 0
	var t2 := 0
	var o2 := 0
	for strip in rs.reel_strips:
		for cell in strip:
			var sym = cell[0] if cell is Array else cell
			if sym == null or String(sym.kind) != "trash":
				continue
			var p := String(sym.resource_path)
			if p == miss_path:
				m2 += 1
			elif p == trash_path:
				t2 += 1
			else:
				o2 += 1
	_ok(o2 == 0, "混合场景：所有废铁保留可识别路径 (other=%d)" % o2)
	_ok(m2 > 0, "混合场景：精度 MISS 身份保真 (n=%d)" % m2)
	_ok(t2 > 0, "混合场景：敌人注入废铁 trash.tres 身份保真 (n=%d)" % t2)
	_ok(m2 > 0 and t2 > 0 and o2 == 0, "两种来源严格分离且无第三类模糊身份")
	print("T19ID|INFO mixed miss=%d trash=%d other=%d" % [m2, t2, o2])

	duel.queue_free()
	await get_tree().process_frame
