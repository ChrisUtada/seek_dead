extends Node

# S5-3 gacha 关闭与全产点路径停测（2026-11-21）
# 验证：roll_anvil 零副作用、各房型清房不产点、局末不发点、空池明确状态、旧档历史保留、UI 无假入口。

var _fails := 0
var _checks := 0
var _duel: DuelController

func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("S5 GACHA FAIL: " + label)

func _ready() -> void:
	await get_tree().process_frame
	SaveSystem.reset_lobby_data()
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	_duel = duel
	await get_tree().process_frame
	await get_tree().process_frame
	duel.demo_config.enabled = false
	duel._confirm_loadout()
	await get_tree().process_frame

	# ① roll_anvil 零副作用（点数/RNG/收藏/保底/存档）
	var pts0: int = int(duel.meta.get("anvil_points", 0))
	var owned0: Array = (duel.meta.get("owned_weapons", []) as Array).duplicate()
	var pity0: int = int(duel.meta.get("anvil_pity", 0))
	var r: Array = duel._anvil_system.roll_anvil()
	_ok(r.is_empty(), "roll_anvil 返回空（disabled）")
	_ok(int(duel.meta.get("anvil_points", 0)) == pts0, "roll_anvil 不扣点/不加分")
	_ok(int(duel.meta.get("anvil_pity", 0)) == pity0, "roll_anvil 不改保底")
	_ok(_same(owned0, duel.meta.get("owned_weapons", []) as Array), "roll_anvil 不写收藏")

	# ② 各房型清房点数不增长
	for kind in ["normal", "elite", "boss"]:
		var room := _room_of_kind(duel, kind)
		if room == null: continue
		var a0: int = int(duel.meta.get("anvil_points", 0))
		duel._anvil_system.award_meta(room.kind == "boss")
		_ok(int(duel.meta.get("anvil_points", 0)) == a0, "%s 清房不产点" % kind)

	# ③ 局末不发点，但生涯定向仍可领取（roll_meta_choices 空 + 空状态）
	_ok(duel._reward_system.roll_meta_choices().is_empty(), "局末无铁砧点候选")
	var ms = duel.hud.meta_screen
	duel._career._directed_balance = 1
	ms.show_choice()
	await get_tree().process_frame
	_ok(ms.visible and ms.meta_grid.get_child_count() > 0, "局末优先展示生涯解锁候选")
	var before_bal: int = duel._career.available_directed()
	var before_pts: int = int(duel.meta.get("anvil_points", 0))
	var cand: String = String(duel._career.directed_candidates()[0]["path"])
	duel._career.claim_directed(cand)
	_ok(duel._career.available_directed() == before_bal - 1, "局末期生涯定向仍可领取一次")
	_ok(int(duel.meta.get("anvil_points", 0)) == before_pts, "领取过程不产点")

	# ④ BOSS 空池明确状态（不空屏、不产点）
	var boss_empty: Array = duel._reward_system.roll_boss_rewards(_boss_room(duel))
	var has_empty_card := false
	for c in boss_empty:
		if String(c.get("kind", "")) == "boss_empty": has_empty_card = true
	_ok(boss_empty.size() > 0 or has_empty_card, "BOSS 奖励候选非空或明确空状态卡")
	for c in boss_empty:
		_ok(String(c.get("kind", "")) != "boss_anvil", "BOSS 不再产出铁砧结晶卡")

	# ⑤ 旧档历史点数保留 + 重复加载不重复迁移
	SaveSystem.reset_lobby_data()
	var lb: Dictionary = SaveSystem.load_lobby_data().duplicate(true)
	lb["anvil_meta"] = {"anvil_points": 25, "career": {"unlocked": [], "bosses": []}}
	SaveSystem.save_lobby_data(lb); SaveSystem.flush_lobby_data()
	var d2: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(d2)
	await get_tree().process_frame
	_ok(int(d2.meta.get("anvil_points", 0)) == 25, "旧档历史点数保留（不回锁）")
	var bal_a: int = d2._career.available_directed()
	var d3: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(d3)
	await get_tree().process_frame
	_ok(d3._career.available_directed() == bal_a, "重复加载不重复折算")

	# ⑥ UI 无假摇奖入口
	var has_fake_entry := false
	for c in duel.hud.meta_screen.get_node("Margin/Content").get_children():
		if c is Button and String((c as Button).text).contains("摇奖"):
			has_fake_entry = true
	_ok(not has_fake_entry, "meta_screen 无临时摇奖入口")
	_ok(duel.hud.anvil_screen.roll_btn.disabled, "anvil_screen 摇动按钮禁用")
	duel.hud._show_anvil_screen()
	_ok(not duel.hud.anvil_screen.visible, "摇奖屏显示入口已屏蔽")

	print("S5 GACHA RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)

func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	for i in range(a.size()):
		if str(a[i]) != str(b[i]): return false
	return true

func _room_of_kind(duel: DuelController, kind: String) -> RoomData:
	for r in duel.ALL_ROOMS:
		if r != null and r.kind == kind: return r
	return null

func _boss_room(duel: DuelController) -> RoomData:
	return _room_of_kind(duel, "boss")
