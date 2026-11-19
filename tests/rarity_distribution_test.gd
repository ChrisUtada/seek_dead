extends Node

# ============================================================================
# 稀有度分布回归测试（2026-11-19）
# 用户实测反馈：三选一里进阶/稀有卡比普通卡多。
# 根因：所有卡 base_weight=1.0、rarity 不参与抽取，卡池构成（rare5/uncommon4/common3）
#       直接决定出现率 → common 仅 15%、uncommon 64%（与 V1.1 70/25/5 颠倒）。
# 修复：CategoryResolver.RARITY_DRAW_MULT 让 rarity 参与类别内抽取；
#       基础成长卡标 common、稀有构筑卡（元素共鸣）保持 rare。
#
# 覆盖：
# ① 400 组 Draft（1200 卡）中 common ≥ 55%（普通卡占多数）
# ② uncommon < common（进阶不反超）
# ③ rare ≤ 10%（稀有最少）
# ④ 类别分布无严重失衡（最多类别 < 55%）
# ============================================================================

var _fails := 0
var _checks := 0


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("RARITY FAIL: " + label)


func _ready() -> void:
	await get_tree().process_frame
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame
	var rs = duel._reward_system
	var snap = RunStateAnalyzer.capture(duel)

	var counts := {}
	var cats := {}
	var total := 0
	for i in range(400):
		var d = rs._draft_composer.compose(snap, 3, false, rs._draft_extra(), false)
		for r in (d.rewards as Array):
			var q: String = String(r.rarity)
			counts[q] = int(counts.get(q, 0)) + 1
			var c: String = String(r.effective_category())
			cats[c] = int(cats.get(c, 0)) + 1
			total += 1

	var common: int = int(counts.get("common", 0))
	var uncommon: int = int(counts.get("uncommon", 0))
	var rare: int = int(counts.get("rare", 0))
	var cp: float = 100.0 * float(common) / float(total)
	var up: float = 100.0 * float(uncommon) / float(total)
	var rp: float = 100.0 * float(rare) / float(total)

	_ok(cp >= 55.0, "common >=55%% (got %.1f%%)" % cp)
	_ok(uncommon <= common, "uncommon <= common (%.1f%% <= %.1f%%)" % [up, cp])
	_ok(rp <= 10.0, "rare <=10%% (got %.1f%%)" % rp)

	var max_cat := 0
	for c in cats:
		max_cat = maxi(max_cat, int(cats[c]))
	_ok(float(max_cat) / float(total) <= 0.55, "no category >55%% (max %.1f%%)" % (100.0 * float(max_cat) / float(total)))

	print("RARITY TEST RESULT: %d checks, %d fails; common=%.1f%% uncommon=%.1f%% rare=%.1f%%" % [
		_checks, _fails, cp, up, rp])
	get_tree().quit(1 if _fails > 0 else 0)
