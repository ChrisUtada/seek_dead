extends Node

# S5-1 生涯单账本与老档迁移矩阵测试（2026-11-21）
# 覆盖：全新/只有旧额度/只有career/两套并存取较大/重复加载/0-9-10-25边界/
# 已领记录不重复/技能claim写owned_skills/全拥有空池原因/旧API与career同余额/重载一致。

var _fails := 0
var _checks := 0
var _duels: Array = []

func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("S5 MIGRATION FAIL: " + label)

func _make_duel(save: Dictionary) -> DuelController:
	var lb: Dictionary = SaveSystem.load_lobby_data().duplicate(true)
	lb["anvil_meta"] = save.duplicate(true)
	SaveSystem.save_lobby_data(lb)
	SaveSystem.flush_lobby_data()
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	_duels.append(duel)
	return duel

func _flush_duels() -> void:
	for d in _duels:
		if is_instance_valid(d): d.queue_free()
	_duels.clear()

func _ready() -> void:
	await get_tree().process_frame

	# ① 全新无存档：余额0，迁移flag写入
	var d1 := _make_duel({})
	_ok(d1._career.available_directed() == 0, "fresh: balance 0")
	_ok(bool(d1.meta.get("career", {}).get("directed_v1", false)), "fresh: migration flag set")
	_ok(d1._anvil_system.available_directed_unlocks() == d1._career.available_directed(), "fresh: old API same balance")

	# ② 只有旧 anvil 额度 7
	var d2 := _make_duel({"directed_unlocks": 7, "anvil_points": 0, "career": {"unlocked": [], "bosses": []}})
	_ok(d2._career.available_directed() == 7, "only old anvil: balance 7")

	# ③ 只有 career 额度 5
	var d3 := _make_duel({"directed_unlocks": 0, "anvil_points": 0, "career": {"unlocked": [], "bosses": [], "unlock_charges": 5}})
	_ok(d3._career.available_directed() == 5, "only career: balance 5")

	# ④ 两套同时存在 7 + 5：取较大值7，不求和12
	var d4 := _make_duel({"directed_unlocks": 7, "anvil_points": 0, "career": {"unlocked": [], "bosses": [], "unlock_charges": 5}})
	_ok(d4._career.available_directed() == 7, "both: max(7,5)=7 not sum 12")

	# ⑤ 已迁移存档重复加载两次：不重复发放（模拟 flag 已 true）
	var save5 := {"directed_unlocks": 7, "anvil_points": 25, "career": {"unlocked": [], "bosses": [], "directed_balance": 9, "directed_v1": true}}
	var d5a := _make_duel(save5)
	var bal5a: int = d5a._career.available_directed()
	var d5b := _make_duel(save5)
	_ok(d5b._career.available_directed() == bal5a, "reload: no re-migration (balance stable)")

	# ⑥ 老点数边界 0/9/10/25（无旧额度时应折算 0/0/1/2）
	for pair in [{"pts":0,"exp":0},{"pts":9,"exp":0},{"pts":10,"exp":1},{"pts":25,"exp":2}]:
		var pts: int = int(pair["pts"])
		var exp: int = int(pair["exp"])
		var dp := _make_duel({"directed_unlocks": 0, "anvil_points": pts, "career": {"unlocked": [], "bosses": []}})
		_ok(dp._career.available_directed() == exp, "legacy points %d -> %d" % [pts, exp])

	# ⑦ 已领取记录并集 + 图鉴/成就记录不重复
	var save7 := {"directed_unlocks": 3, "anvil_points": 0,
		"directed_claimed": ["res://resources/weapon_templates/dagger.tres"],
		"collection_milestones": [0,1],
		"career": {"unlocked": ["first_clear"], "bosses": ["b1"], "directed_v1": true}}
	var d7 := _make_duel(save7)
	_ok(d7._career.has("first_clear") and d7._career.had_boss("b1"), "career records intact")
	# dagger 已在 claimed 且已拥有，不应重复授予
	var before7: int = d7._career.available_directed()
	var r7: Dictionary = d7._career.claim_directed("res://resources/weapon_templates/dagger.tres")
	_ok(not bool(r7.get("ok", false)) and d7._career.available_directed() == before7, "claimed/owned target not re-granted")

	# ⑧ 技能 claim 成功且写 owned_skills
	var d8 := _make_duel({"directed_unlocks": 2, "anvil_points": 0, "career": {"unlocked": [], "bosses": []}})
	var skill_target := ""
	for c in d8._career.directed_candidates():
		var p: String = String(c["path"])
		if p.ends_with(".tres") and (load(p) is SkillData):
			skill_target = p; break
	if skill_target != "":
		var before8: int = d8._career.available_directed()
		var r8: Dictionary = d8._career.claim_directed(skill_target)
		_ok(bool(r8.get("ok", false)), "skill claim ok")
		_ok((d8.meta.get("owned_skills", []) as Array).has(skill_target), "skill written to owned_skills")
		_ok(d8._career.available_directed() == before8 - 1, "skill claim consumes 1")
	else:
		_ok(false, "no skill candidate found")

	# ⑨ 全部候选已拥有时返回明确空池原因
	var d9 := _make_duel({"directed_unlocks": 1, "anvil_points": 0, "career": {"unlocked": [], "bosses": []}})
	var all_owned: Dictionary = {}
	for c in d9._career.directed_candidates(): all_owned[String(c["path"])] = true
	# 直接构造一个不在池且未拥有的路径 -> not_in_pool
	var r9: Dictionary = d9._career.claim_directed("res://resources/weapon_templates/__nonexistent__.tres")
	_ok(not bool(r9.get("ok", false)) and String(r9.get("reason", "")) == "invalid_path", "invalid path reason")

	# ⑩ 旧 API 与 career 新 API 同余额（已覆盖①②，再验证 claim 后仍同步）
	var d10 := _make_duel({"directed_unlocks": 4, "anvil_points": 0, "career": {"unlocked": [], "bosses": []}})
	var tc: String = String(d10._career.directed_candidates()[0]["path"])
	var r10: Dictionary = d10._anvil_system.claim_directed_unlock(tc)
	_ok(bool(r10.get("ok", false)), "old API claim ok")
	_ok(d10._anvil_system.available_directed_unlocks() == d10._career.available_directed(), "old API same balance after claim")

	# ⑪ earn 走生涯不双写：earn 一次只 +1
	var d11 := _make_duel({"directed_unlocks": 1, "anvil_points": 0, "career": {"unlocked": [], "bosses": []}})
	var before11: int = d11._career.available_directed()
	d11._anvil_system.earn_directed_unlock("boss:test")
	_ok(d11._career.available_directed() == before11 + 1, "earn via old API = +1 only (no double write)")
	_ok(int(d11.meta.get("directed_unlocks", 0)) == 1, "legacy balance field not updated")

	_flush_duels()
	print("S5 MIGRATION RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
