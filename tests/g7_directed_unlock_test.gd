extends Node

# ============================================================================
# G7-3 铁砧定向解锁测试（2026-11-20）
# 方案 §10.1：条件解锁+定向选择替代随机摇奖；老档点数每10点折算1次，已解锁不回锁。
# ============================================================================

var _fails := 0
var _checks := 0


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("G7-3 FAIL: " + label)


func _ready() -> void:
	await get_tree().process_frame
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	var an = duel._anvil_system

	# ① 记录基线额度（环境可能已有老档折算额度）
	var base: int = an.available_directed_unlocks()

	# ② 条件达成授予额度（验证增量）
	an.earn_directed_unlock("boss")
	an.earn_directed_unlock("career")
	_ok(an.available_directed_unlocks() == base + 2, "条件达成授予 2 次额度（%d→%d）" % [base, an.available_directed_unlocks()])

	# ③ 定向候选列出未拥有内容
	var cands: Array = an.directed_candidates()
	_ok(cands.size() > 0, "定向候选非空（%d）" % cands.size())
	var target: String = String(cands[0]["path"])
	_ok(not an._anvil_is_owned(target), "候选目标当前未拥有")

	# ④ 定向选择：花 1 额度解锁指定目标（不随机）
	var before: int = an.available_directed_unlocks()
	var res: Dictionary = an.claim_directed_unlock(target)
	_ok(bool(res["ok"]), "定向解锁成功（%s）" % String(res["reason"]))
	_ok(an.available_directed_unlocks() == before - 1, "额度消耗 1 次")
	_ok(an._anvil_is_owned(target), "目标已进收藏")
	_ok(duel.meta["directed_claimed"].has(target), "记录已定向解锁目标")

	# ⑤ 重复/非法/无额度拒绝
	var dup: Dictionary = an.claim_directed_unlock(target)
	_ok(not bool(dup["ok"]) and String(dup["reason"]) == "already_owned", "重复解锁被拒")
	var bad: Dictionary = an.claim_directed_unlock("res://nope.tres")
	_ok(not bool(bad["ok"]), "非法路径被拒")
	# 直接清零额度测无额度拒绝
	duel.meta["directed_unlocks"] = 0
	var noq: Dictionary = an.claim_directed_unlock(String(cands[1]["path"]))
	_ok(not bool(noq["ok"]) and String(noq["reason"]) == "no_unlock_available", "无额度被拒")

	# ⑥ 老存档不回锁：已有收藏不因改造丢失
	_ok(an._anvil_is_owned(target), "已解锁内容保留（不回锁）")

	print("G7-3 DIRECTED UNLOCK RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
