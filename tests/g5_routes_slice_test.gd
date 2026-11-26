extends Node

# ============================================================================
# G5-4 六路线 ACT1 垂直切片验证（2026-11-20）
# 方案 §12.4 六条引擎路线。每条路线至少要有：核心来源 + 强化方式 + 可触发机制。
# 🔴 本测试验证"结构性可玩"（核心回路可达 + 事件可触发 + 有弱点记录），
#    不是平衡结论；真人路线体验待 F6。
# ============================================================================

var _fails := 0
var _checks := 0


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("G5-4 FAIL: " + label)


func _ready() -> void:
	await get_tree().process_frame
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame
	var c = duel.circuit_system

	# 六路线 → 核心回路（G4 已实装的对应规则）
	var routes := {
		"同系三连": "circuit_triple_echo",
		"对子稳定": "circuit_pair",
		"异色覆盖": "circuit_tri_color",
		"DoT反应": "circuit_status_react",
		"破甲穿透": "circuit_armor_break",
		"防御运筹": "circuit_damage_shield",
	}
	duel._build_pool(duel.selected_loadout)

	# ① 每条路线的核心回路都有定义
	for route in routes:
		var cid: String = String(routes[route])
		_ok(CircuitSystem.DEFINITIONS.has(cid), "%s 核心回路有定义（%s）" % [route, cid])

	# ② 默认配装下各路线核心回路的可达性（客观记录，不要求全可达——弱点即代价）
	var report: Dictionary = c.reachability_report()
	var reachable_routes := 0
	for route in routes:
		var cid: String = String(routes[route])
		var r: Dictionary = report["circuits"][cid]
		if bool(r["reachable"]):
			reachable_routes += 1
		print("路线切片 %-10s 核心回路 %-24s 可达=%s 原因=%s" % [
			route, cid, str(r["reachable"]), String(r["reason"])])
	_ok(reachable_routes >= 3, "默认配装至少 3 条路线核心可达（%d/6）" % reachable_routes)

	# ③ 每条路线的核心回路都能真实触发并落地（用 CircuitSystem + payout 直接验）
	for route in routes:
		var cid: String = String(routes[route])
		c.reset_run()
		_ok(c.acquire(cid), "%s 核心回路可 acquire" % route)
		_ok(c.equip(cid).ok, "%s 核心回路可装备（单槽验证）" % route)
		var ev: String = String(CircuitSystem.DEFINITIONS[cid]["event"])
		var fired: Array = c.try_trigger(ev)
		_ok(fired.size() == 1 and String(fired[0]) == cid, "%s 核心事件可触发（%s）" % [route, ev])

	# ④ 路线弱点记录（方案要求"每条有真实弱点"）——结构性弱点是可达性不保证。
	# T3 阶段 1：starter 由 dagger 改为 iron_sword（铁斩带破甲），破甲路线在默认配装下变为可达；
	# 异色覆盖仍缺稳定三色来源，作为默认配装的真实弱点记录。
	var tri: Dictionary = report["circuits"]["circuit_tri_color"]
	_ok(not bool(tri["reachable"]), "异色覆盖有明确弱点：默认配装不可达，需专门三色配装")

	print("G5-4 ROUTES SLICE RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
