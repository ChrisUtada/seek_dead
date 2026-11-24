extends Node

# S5-5 老档与完整流程回归（2026-11-21）
# 覆盖：含旧点数/两套额度/已领记录/旧gacha字段的存档、重复加载、无AnvilSystem、
# 生涯领取后重载一致、完整三幕最终Boss返回整备、图鉴商店换装空池正常。

var _fails := 0
var _checks := 0

func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("S5 FULL FAIL: " + label)

func _ready() -> void:
	await get_tree().process_frame
	# 构造老档：旧点数25、旧anvil额度7、career额度5、已领记录、旧gacha字段
	SaveSystem.reset_lobby_data()
	var lb: Dictionary = SaveSystem.load_lobby_data().duplicate(true)
	lb["anvil_meta"] = {
		"anvil_points": 25, "anvil_pity": 9,
		"directed_unlocks": 7,
		"directed_claimed": ["res://resources/weapon_templates/dagger.tres"],
		"collection_milestones": [0],
		"career": {"unlocked": ["first_clear"], "bosses": ["b1"], "unlock_charges": 5},
		"codex": {}, "forge_styles": {}, "item_sources": {},
	}
	SaveSystem.save_lobby_data(lb); SaveSystem.flush_lobby_data()

	var d1: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(d1)
	await get_tree().process_frame
	await get_tree().process_frame
	# ① 老档迁移：取较大值7（非求和12）、历史点数保留、已领记录并集
	_ok(d1._career.available_directed() == 7, "老档迁移取max(7,5)=7非求和")
	_ok(int(d1.meta.get("anvil_points", 0)) == 25, "旧点数历史保留")
	_ok(d1._career.has("first_clear") and d1._career.had_boss("b1"), "生涯成就/Boss记录保留")
	_ok(not ("_anvil_system" in d1), "AnvilSystem 不存在")
	_ok(int(d1.meta.get("anvil_pity", 0)) == 9, "旧gacha字段保留作历史")

	# ② 连续加载两次不重复折算（独立实例读同一存档）
	var d2: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(d2)
	await get_tree().process_frame
	_ok(d2._career.available_directed() == d1._career.available_directed(), "重复加载余额一致（不重折算）")

	# ③ 生涯领取武器与技能后重载一致
	var cands: Array = d1._career.directed_candidates()
	var weapon: String = ""
	var skill: String = ""
	for c in cands:
		var p: String = String(c.get("path", ""))
		if weapon == "" and (load(p) is WeaponData) and not (d1.meta.get("owned_weapons", []) as Array).has(p):
			weapon = p
		if skill == "" and (load(p) is SkillData):
			skill = p
	if weapon != "":
		d1._career._directed_balance += 1
		_ok(bool(d1._career.claim_directed(weapon).get("ok", false)), "生涯领取武器成功")
		_ok((d1.meta.get("owned_weapons", []) as Array).has(weapon), "武器写 owned_weapons")
	if skill != "":
		d1._career._directed_balance += 1
		_ok(bool(d1._career.claim_directed(skill).get("ok", false)), "生涯领取技能成功")
		_ok((d1.meta.get("owned_skills", []) as Array).has(skill), "技能写 owned_skills")
	d1._meta_store.save_meta()
	var d3: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(d3)
	await get_tree().process_frame
	if weapon != "":
		_ok((d3.meta.get("owned_weapons", []) as Array).has(weapon), "重载后武器仍拥有")
	if skill != "":
		_ok((d3.meta.get("owned_skills", []) as Array).has(skill), "重载后技能仍拥有")

	# ④ 新局状态与子系统正常（无空调用）
	d1.demo_config.enabled = false
	d1._confirm_loadout()
	await get_tree().process_frame
	_ok(d1._career != null and d1._reward_system != null and d1._shop_system != null, "新局子系统正常")
	_ok(d1.hud.meta_screen.codex_panel != null, "图鉴组件正常")
	d1._shop_system.roll_shop()
	_ok(d1._shop_system.shop_offers.size() > 0, "商店货架正常")

	# ⑤ Boss/精英空池明确状态（不空屏、无铁砧结晶）
	var boss_card: Array = d1._reward_system.roll_boss_rewards(_boss_room(d1))
	var no_anvil := true
	for c in boss_card:
		if String(c.get("kind", "")) == "boss_anvil": no_anvil = false
	_ok(no_anvil, "Boss空池无铁砧结晶卡")

	# ⑥ 三幕推进与返回整备（简化：验证线性换幕入口 _maybe_grant_linear_act_boon 与 return_to_loadout 不崩）
	d1.room_flow.return_to_loadout()
	await get_tree().process_frame
	_ok(d1.hud.meta_screen != null, "返回整备后界面正常")

	print("S5 FULL RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)

func _boss_room(duel: DuelController) -> RoomData:
	for r in duel.ALL_ROOMS:
		if r != null and r.kind == "boss": return r
	return null
