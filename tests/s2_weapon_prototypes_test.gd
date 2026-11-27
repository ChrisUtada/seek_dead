extends Node

const MACE := "res://resources/weapon_templates/mace.tres"
const DUSK_HATCHET := "res://resources/weapon_templates/dusk_hatchet.tres"
const DUELING_SABER := "res://resources/weapon_templates/dueling_saber.tres"
const FIRE_SWORD := "res://resources/weapon_templates/fire_sword.tres"
const ABSOLUTE_ZERO := "res://resources/weapon_templates/absolute_zero.tres"
const ICE_GUN := "res://resources/weapon_templates/ice_gun.tres"
const ECLIPSE_BLADE := "res://resources/weapon_templates/eclipse_blade.tres"
const IRON_SLASH := "res://resources/symbols/iron_slash.tres"
const IRON_WALL := "res://resources/symbols/iron_wall.tres"
const SHADOW_SLASH := "res://resources/symbols/shadow_slash.tres"
const DAWN_LIGHT := "res://resources/symbols/dawn_light.tres"
const DAGGER_SLASH := "res://resources/symbols/dagger_slash.tres"

var _fails := 0
var _checks := 0


func _ready() -> void:
	await _run()


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("S2 PROTOTYPE FAIL: " + label)


func _run() -> void:
	_ok(ResourceScan.scan_paths("res://resources/weapon_templates/").size() == 90,
		"试点不增加武器总数")
	_test_definition(MACE, "坚壁钉锤", "defense", "weapon_none_guard_line", IRON_SLASH, IRON_WALL)
	_test_definition(DUSK_HATCHET, "暮光手斧", "damage", "weapon_twilight_coverage_line", SHADOW_SLASH, DAWN_LIGHT)
	_test_definition(DUELING_SABER, "双式军刀", "damage", "weapon_none_pair_line", IRON_SLASH, DAGGER_SLASH)
	_test_existing_flagships()

	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame

	_test_defense_pool(duel)
	_test_coverage_pool(duel)
	_test_pair_pool(duel)

	print("S2 PROTOTYPES RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _test_definition(path: String, weapon_name: String, role: String, group: String,
		first_symbol: String, second_symbol: String) -> void:
	var wd: WeaponData = load(path)
	_ok(wd != null, "资源可加载：" + path)
	if wd == null:
		return
	_ok(wd.weapon_name == weapon_name, "%s 名称与身份一致" % weapon_name)
	_ok(wd.role == role, "%s role=%s" % [weapon_name, role])
	_ok(wd.unique_group == group, "%s 使用独立机制组" % weapon_name)
	_ok(wd.symbols.size() == 2, "%s 不再使用单符号 A 级重复结构" % weapon_name)
	var weights := _weights(wd)
	_ok(is_equal_approx(float(weights.get(first_symbol, 0.0)), 3.0), "%s 主符号一为 3 格权重" % weapon_name)
	_ok(is_equal_approx(float(weights.get(second_symbol, 0.0)), 3.0), "%s 主符号二为 3 格权重" % weapon_name)


func _weights(wd: WeaponData) -> Dictionary:
	var out := {}
	for sw in wd.symbols:
		if sw != null and sw.symbol != null:
			out[sw.symbol.resource_path] = float(sw.weight)
	return out


func _test_existing_flagships() -> void:
	var absolute_zero: WeaponData = load(ABSOLUTE_ZERO)
	var ice_gun: WeaponData = load(ICE_GUN)
	var eclipse_blade: WeaponData = load(ECLIPSE_BLADE)
	_ok(is_equal_approx(float(_weights(absolute_zero).get("res://resources/symbols/ice_crystal.tres", 0.0)), 5.0),
		"集中旗舰绝对零度保留 5 格主伤害符号")
	_ok(is_equal_approx(float(_weights(ice_gun).get("res://resources/symbols/glacier_spear.tres", 0.0)), 5.0),
		"状态旗舰冰霜枪保留 5 格主伤害符号（霜棘）")
	_ok(eclipse_blade.triple_pierce, "破甲旗舰蚀日之刃保留三连破甲")


func _set_loadout(duel: DuelController, paths: Array) -> void:
	duel.selected_loadout.assign(paths)
	duel.selected_skills.clear()
	duel._build_pool(duel.selected_loadout)


func _pool_facts(duel: DuelController) -> Dictionary:
	var kinds := {}
	var elements := {}
	var damage_families := {}
	for item in duel.pool_items:
		for entry in item.get("syms", []):
			if not (entry is Array) or entry.size() < 3 or entry[0] == null:
				continue
			var sym: SymbolData = entry[0]
			kinds[String(sym.kind)] = true
			if sym.kind == "damage":
				elements[String(entry[2])] = true
				damage_families[String(sym.resource_path)] = true
	return {"kinds": kinds, "elements": elements, "damage_families": damage_families}


func _preview_rows(paths: Array) -> Dictionary:
	var comp: Dictionary = ReelPreview.compose(paths, [], [], [], {}, 0, false, 0, {}, {}, {})
	var out := {}
	for row in comp["rows"]:
		out[String(row["path"])] = row
	return out


func _test_defense_pool(duel: DuelController) -> void:
	_set_loadout(duel, [MACE])
	var facts: Dictionary = _pool_facts(duel)
	_ok(facts["kinds"].has("damage") and facts["kinds"].has("shield"),
		"坚壁钉锤真实建池同时含伤害与护盾")
	var reach: Dictionary = duel.circuit_system.is_reachable("circuit_damage_shield")
	_ok(bool(reach.get("ok", false)), "坚壁钉锤单独使攻守转换可达")
	var rows: Dictionary = _preview_rows([MACE])
	_ok(rows.has(IRON_SLASH) and String(rows[IRON_SLASH]["kind"]) == "damage",
		"防御预览保留铁斩伤害")
	_ok(rows.has(IRON_WALL) and String(rows[IRON_WALL]["kind"]) == "shield" and int(rows[IRON_WALL]["cells"]) == 3,
		"防御预览显示铁誓 3 格护盾")


func _test_coverage_pool(duel: DuelController) -> void:
	_set_loadout(duel, [DUSK_HATCHET])
	var facts: Dictionary = _pool_facts(duel)
	_ok(facts["elements"].has("dark") and facts["elements"].has("light"),
		"暮光手斧真实建池保留暗/光双元素")
	_ok(not facts["elements"].has("none"), "跨元素符号不被武器底色改写为无元素")
	var rows: Dictionary = _preview_rows([DUSK_HATCHET])
	_ok(rows.has(SHADOW_SLASH) and String(rows[SHADOW_SLASH]["elem"]) == "dark",
		"跨元素预览保留暗斩元素")
	_ok(rows.has(DAWN_LIGHT) and String(rows[DAWN_LIGHT]["elem"]) == "light",
		"跨元素预览保留晨曦元素")
	_set_loadout(duel, [DUSK_HATCHET, FIRE_SWORD])
	var reach: Dictionary = duel.circuit_system.is_reachable("circuit_tri_color")
	_ok(bool(reach.get("ok", false)), "暮光手斧与火系武器组合后异色协奏可达")


func _test_pair_pool(duel: DuelController) -> void:
	_set_loadout(duel, [DUELING_SABER])
	var facts: Dictionary = _pool_facts(duel)
	_ok(facts["damage_families"].size() == 2, "双式军刀真实建池含两个伤害族")
	var reach: Dictionary = duel.circuit_system.is_reachable("circuit_pair")
	_ok(bool(reach.get("ok", false)), "双式军刀单独使对子赔付可达")
	var rows: Dictionary = _preview_rows([DUELING_SABER])
	_ok(rows.has(IRON_SLASH) and rows.has(DAGGER_SLASH)
		and int(rows[IRON_SLASH]["cells"]) == 3 and int(rows[DAGGER_SLASH]["cells"]) == 3,
		"对子预览显示两个等权 3 格伤害族")
	var counts := {
		"iron|none": [load(IRON_SLASH), "none", 2],
		"dagger|none": [load(DAGGER_SLASH), "none", 1],
	}
	_ok(duel.combat._has_pair_damage(counts), "双式军刀结构可形成真实对子事件")
