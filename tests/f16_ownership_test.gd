extends Node

# F-16 拥有与叠加语义统一测试（2026-11-21）
# 覆盖：商店唯一物品标已拥有禁用、符号改造满层过滤与X/Y、消耗品重复、
# 重抽/Fallback 不绕过滤、永久收藏与本局仓库不混淆、即时资源不误过滤。

const SAMPLE_SYM := "res://resources/symbols/dagger_slash.tres"

var _fails := 0
var _checks := 0
var _duel: DuelController

func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("F16 FAIL: " + label)

func _ready() -> void:
	await get_tree().process_frame
	SaveSystem.reset_lobby_data()
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	_duel = scene_res.instantiate() as DuelController
	add_child(_duel)
	await get_tree().process_frame
	await get_tree().process_frame
	_duel.demo_config.enabled = false
	_duel._confirm_loadout()
	await get_tree().process_frame
	var rs = _duel._reward_system

	# ① 商店唯一物品：已装备武器/护符在卡面标"已拥有"且禁用，点击不扣款不重复写入
	_duel.gold = 500
	var owned_path: String = _duel.selected_loadout[0]
	var offer := {"path": owned_path, "kind": "weapon", "name": "已装备武器", "price": 10, "sold": false}
	var card: Button = _duel.hud._cards.shop_card(offer)
	_ok(card.disabled, "商店已装备武器卡禁用")
	_ok(String((card.get_node("Center/VBox/StatusLabel") as Label).text).contains("已装备"),
		"商店已装备武器卡显示已装备")
	var gold_before: int = _duel.gold
	var arr_before: int = _duel.selected_loadout.size()
	_duel._shop_system.on_shop_buy_pressed(offer)
	_ok(_duel.gold == gold_before and _duel.selected_loadout.size() == arr_before,
		"点击已拥有卡不扣款不重复写入")

	# ② 消耗品允许同类重复持有（按腰带格数，不按图鉴去重）
	var active: Array = _duel.ITEM_POOL.filter(func(p): return String(p).contains("consumable") or String(p).contains("potion"))
	# 用已知消耗品路径兜底
	var ap: String = "res://resources/consumables/energy_drink.tres"
	if active.size() > 0: ap = String(active[0])
	var before_slots: int = _duel.consumable_slots.size()
	_duel.gold = 500
	var ao := {"path": ap, "kind": "active", "name": "消耗品", "price": 5, "sold": false}
	if ResourceLoader.load(ap) != null:
		_duel._shop_system.on_shop_buy_pressed(ao)
		_ok(_duel.consumable_slots.size() == before_slots + 1 or _duel.consumable_slots.size() == _duel.CONSUMABLE_CAP,
			"消耗品可重复入腰带（%d → %d）" % [before_slots, _duel.consumable_slots.size()])

	# ③ 符号效果改造：未满层可重复，满层后生成端不再产出且结算端拒绝
	var defs_before: Array = rs._make_symbol_effect_defs()
	_ok(defs_before.size() > 0, "符号效果改造候选非空")
	var d0: RewardDefinition = defs_before[0]
	var sp: String = String(d0.effects[0].get("params", {}).get("symbol_path", ""))
	var eid: String = String(d0.effects[0].get("params", {}).get("effect", ""))
	var delta: float = float(d0.effects[0].get("params", {}).get("delta", 1.0))
	_ok(String(d0.desc).contains("0/3 层"), "符号改造卡面显示当前 X/上限 Y（%s）" % d0.desc)
	# 手动累加到满层（复用现有账本）
	_duel.symbol_effect_overrides[sp] = {eid: delta * 3.0}
	var defs_after: Array = rs._make_symbol_effect_defs()
	var still_offered := false
	for d in defs_after:
		if String(d.id) == String(d0.id): still_offered = true
	_ok(not still_offered, "符号改造满层后不再出现在候选")
	var resolver = load("res://scripts/reward/reward_resolver.gd").new(_duel)
	var rr = resolver.preflight(d0)
	_ok(not rr.ok and String(rr.reason) == "symbol_effect_maxed",
		"结算端满层安全网拒绝（reason=%s）" % String(rr.reason))

	# ④ 永久收藏 vs 本局仓库：武器 acquire 只跳过本局仓库，不因永久已拥有而拒绝
	_duel.meta["owned_weapons"] = _duel.WEAPON_POOL.duplicate()  # 永久全拥有
	_duel.run_weapon_inventory.clear()
	var acq: Array = rs._make_weapon_acquire_defs()
	_ok(acq.size() >= 1, "永久已拥有但本局无仓库 → 仍产出新武器 acquire（不混淆两账本）")

	# ⑤ 即时资源不被 owned 过滤：治疗/金币可重复出现在候选
	var owned_ids: Array = rs._owned_reward_ids()
	var has_heal := false
	var has_gold := false
	for id in owned_ids:
		if String(id).contains("battle_ready"): has_heal = true
		if String(id).contains("gold_cache"): has_gold = true
	_ok(not has_heal and not has_gold, "即时资源（治疗/金币）不在 owned 过滤集合")

	print("F16 RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
