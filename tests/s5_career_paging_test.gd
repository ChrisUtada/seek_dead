extends Node

# S5-5 生涯候选分页与双式军刀可达性测试（2026-11-21）
# 验证：全量候选可翻页浏览、目标内容（含双式军刀）无需先领前序即可看到、翻页不扣额度。

const SABER := "res://resources/weapon_templates/dueling_saber.tres"

var _fails := 0
var _checks := 0

func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("S5 PAGING FAIL: " + label)

func _ready() -> void:
	await get_tree().process_frame
	SaveSystem.reset_lobby_data()
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.demo_config.enabled = false
	duel._confirm_loadout()
	await get_tree().process_frame

	var ms = duel.hud.meta_screen
	duel._career._directed_balance = 1
	ms.show_career()
	await get_tree().process_frame

	var cands: Array = duel._career.directed_candidates()
	_ok(cands.size() > 3, "候选全量 > 3（%d）" % cands.size())
	_ok(ms.meta_grid.get_child_count() == 3, "第一页显示 3 张卡")
	var saber_idx: int = -1
	for i in range(cands.size()):
		if String(cands[i].get("path", "")) == SABER: saber_idx = i; break
	_ok(saber_idx >= 0, "双式军刀在生涯候选池中（位置 %d）" % saber_idx)

	# 逐页前进直到看到 saber 所在页；翻页不扣额度
	var target_page: int = saber_idx / 3
	var bal_before: int = duel._career.available_directed()
	var page_ok := true
	for p in range(target_page + 1):
		if p > 0:
			ms._next_page()
			await get_tree().process_frame
		var expected_count: int = mini(3, cands.size() - p * 3)
		if ms.meta_grid.get_child_count() != expected_count:
			page_ok = false
	_ok(page_ok, "翻到第 %d 页可显示该页候选（含双式军刀）" % (target_page + 1))
	_ok(ms._page == target_page, "页码到达目标页（%d）" % target_page)
	_ok(duel._career.available_directed() == bal_before, "翻页不扣额度")

	# 直接领取该页的 saber（验证写入 owned_weapons 且下局可选配）
	duel._career._directed_balance += 1
	var r: Dictionary = duel._career.claim_directed(SABER)
	_ok(bool(r.get("ok", false)), "生涯领取双式军刀成功")
	_ok((duel.meta.get("owned_weapons", []) as Array).has(SABER), "写入 owned_weapons")

	print("S5 PAGING RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
