extends Node

# S5-2 入口归一与图鉴解耦流程测试（2026-11-21）
# 验证：meta_screen 唯一定向入口、图鉴独立、余额单次扣减、空状态、连续点击防护。

var _fails := 0
var _checks := 0

func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("S5 ENTRY FAIL: " + label)

func _ready() -> void:
	await get_tree().process_frame
	# 干净存档
	SaveSystem.reset_lobby_data()
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.demo_config.enabled = false
	duel._confirm_loadout()
	await get_tree().process_frame

	var ms = duel.hud.meta_screen
	_ok(ms != null and ms.codex_panel != null, "meta_screen 承载图鉴组件")

	# ① 余额 0 空状态
	duel._career._directed_balance = 0
	ms.show_career()
	await get_tree().process_frame
	_ok(ms.visible and ms.meta_grid.get_child_count() == 0, "余额0：空状态无候选卡")
	_ok(ms.sub_label.text.contains("没有定向解锁机会"), "余额0：明确文案")

	# ② 整备入口 → 候选 → 领取一次 → owned 更新 → 余额只减一次 → UI 刷新
	duel._career._directed_balance = 2
	duel._career._directed_claimed.clear()
	ms.show_career()
	await get_tree().process_frame
	var cards: Array = []
	for c in ms.meta_grid.get_children():
		if c is Button: cards.append(c)
	_ok(cards.size() == 3, "有余额显示3张候选卡（%d）" % cards.size())
	if cards.is_empty():
		_flush(); return
	var target: String = ""
	# 从 career 候选确定目标（与 meta_screen 同源）
	var cands: Array = duel._career.directed_candidates()
	_ok(cands.size() > 0, "候选池非空")
	if cands.is_empty():
		_flush(); return
	target = String(cands[0]["path"])
	var owned_key: String = _owned_key(duel, target)
	var before_owned: int = (duel.meta.get(owned_key, []) as Array).size()
	var before_bal: int = duel._career.available_directed()
	cards[0].pressed.emit()
	await get_tree().process_frame
	_ok(duel._career.available_directed() == before_bal - 1, "领取一次只扣1额度")
	_ok((duel.meta.get(owned_key, []) as Array).size() == before_owned + 1, "owned_%s 更新" % owned_key)
	_ok(duel._career.available_directed() == duel._career.available_directed(), "旧API与新账本同余额")

	# ③ 重新打开仍一致
	ms.hide_screen()
	ms.show_career()
	await get_tree().process_frame
	_ok(duel._career.available_directed() == before_bal - 1, "重新打开余额一致")

	# ④ 连续点击只成功一次（用 begin_claim 门禁）
	duel._career._directed_balance = 1
	ms.show_career()
	await get_tree().process_frame
	var gate_ok: bool = ms.begin_claim()
	_ok(gate_ok, "首次 begin_claim 成功")
	_ok(not ms.begin_claim(), "claim 中重复点击被门禁拒绝")
	ms.on_claim_resolved(false)   # 模拟一次失败释放门禁

	# ⑤ 技能领取写 owned_skills
	var skill := ""
	for c in duel._career.directed_candidates():
		var p: String = String(c["path"])
		if load(p) is SkillData:
			skill = p; break
	if skill != "":
		duel._career._directed_balance = 1
		ms.show_career()
		await get_tree().process_frame
		var r: Dictionary = duel._career.claim_directed(skill)
		_ok(bool(r.get("ok", false)), "技能 claim 成功")
		_ok((duel.meta.get("owned_skills", []) as Array).has(skill), "技能写入 owned_skills")
	else:
		_ok(false, "未找到技能候选")

	# ⑥ 全候选已拥有 → 空池提示
	duel._career._directed_balance = 1
	for c in duel._career.directed_candidates():
		var p: String = String(c["path"])
		var k: String = _owned_key(duel, p)
		var arr: Array = duel.meta.get(k, [])
		if not arr.has(p): arr.append(p)
		duel.meta[k] = arr
	ms.show_career()
	await get_tree().process_frame
	_ok(ms.sub_label.text.contains("空池"), "全拥有时空池提示")

	# ⑦ 图鉴独立打开/返回，不访问已失效摇奖节点
	ms.show_career()
	await get_tree().process_frame
	ms.show_codex()
	await get_tree().process_frame
	_ok(ms.codex_panel.is_open(), "图鉴独立打开（摇奖屏不可见）")
	ms.hide_codex()
	await get_tree().process_frame
	_ok(not ms.codex_panel.is_open(), "图鉴返回关闭")
	_ok(ms.visible, "图鉴返回后 meta_screen 仍在")

	# ⑧ 返回不扣额度
	var bal_before_back: int = duel._career.available_directed()
	ms.hide_screen()
	_ok(duel._career.available_directed() == bal_before_back, "返回/关闭不扣额度")

	_flush()

func _owned_key(duel: DuelController, path: String) -> String:
	var res = load(path)
	if res is WeaponData: return "owned_weapons"
	if res is SkillData: return "owned_skills"
	if res is ItemData:
		if res.category == "passive": return "owned_charms"
		if res.category == "active": return "owned_consumables"
	return "owned_weapons"

func _flush() -> void:
	print("S5 ENTRY RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
