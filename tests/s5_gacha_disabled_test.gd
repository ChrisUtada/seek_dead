extends Node

# S5-4 gacha 物理清理后验证（2026-11-21）
# AnvilSystem/gacha UI 已删除；本测试验证：无产点、存档历史可读、无假入口、生涯路径正常。

var _fails := 0
var _checks := 0

func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("S5 CLEANUP FAIL: " + label)

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

	# ① AnvilSystem 已移除
	_ok(not ("_anvil_system" in duel), "duel 无 _anvil_system 字段")
	_ok(not duel.hud.has_method("_show_anvil_screen"), "battle_hud 无摇奖屏入口")

	# ② 局末不发点 + 无假摇奖入口
	_ok(duel._reward_system.roll_meta_choices().is_empty(), "局末无铁砧点候选")
	var ms = duel.hud.meta_screen
	var has_fake_entry := false
	for c in ms.get_node("Margin/Content").get_children():
		if c is Button and String((c as Button).text).contains("摇奖"):
			has_fake_entry = true
	_ok(not has_fake_entry, "meta_screen 无临时摇奖入口")

	# ③ 清房不再产点
	var a0: int = int(duel.meta.get("anvil_points", 0))
	duel._meta_store.award_gold(false)
	_ok(int(duel.meta.get("anvil_points", 0)) == a0, "清房金币结算不附带铁砧点")

	# ④ 旧档历史点数保留 + 重复加载不重复迁移
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

	# ⑤ 生涯 claim / 收藏基座 / 图鉴 / Boss空池仍正常
	_ok(d2._career.directed_candidates().size() > 0, "生涯候选可用")
	_ok(d2._career.collection_pool().size() > 0, "收藏基座已迁 career 且可用")
	var boss_card: Array = d2._reward_system.roll_boss_rewards(_boss_room(d2))
	var no_anvil_card := true
	for c in boss_card:
		if String(c.get("kind", "")) == "boss_anvil": no_anvil_card = false
	_ok(no_anvil_card, "Boss 战利无铁砧结晶卡")
	_ok(d2.hud.meta_screen.codex_panel != null, "图鉴独立组件可用")

	print("S5 CLEANUP RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)

func _boss_room(duel: DuelController) -> RoomData:
	for r in duel.ALL_ROOMS:
		if r != null and r.kind == "boss": return r
	return null
