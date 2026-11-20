extends Node

# S2 实测 · 对子真实落点前置验证（2026-11-21）
# 只读探针：对比 CircuitSystem 可达性报告 vs CombatSystem 真实 _has_pair_damage 判定。
# 三组：晶弹对子+霜 / 铁斩对子+铁誓 / 铁斩对子+匕斩。
# 不改任何玩法代码、武器、断言；只采集并输出 JSON。
# 运行：Godot --headless --path . res://tools/s2_pair_probe.tscn -- --out=<dir>
# 输出前缀 S2PAIR|

const MATCHER := preload("res://scripts/battle/pattern_matcher.gd")

const WEAPONS := {
	"absolute_zero": "res://resources/weapon_templates/absolute_zero.tres",
	"mace": "res://resources/weapon_templates/mace.tres",
	"dueling_saber": "res://resources/weapon_templates/dueling_saber.tres",
	"ice_gun": "res://resources/weapon_templates/ice_gun.tres",
}
const SYMS := {
	"ice_crystal": "res://resources/symbols/ice_crystal.tres",
	"frost": "res://resources/symbols/frost.tres",
	"iron_slash": "res://resources/symbols/iron_slash.tres",
	"iron_wall": "res://resources/symbols/iron_wall.tres",
	"dagger_slash": "res://resources/symbols/dagger_slash.tres",
}

var _out := "user://runs/s2_pair_probe"

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("--out="):
			_out = String(arg).substr(6)
	await _run()

func _run() -> void:
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame

	var results := []
	# 三组三格落点：[damage族(2格), 第二符号(1格)]
	var cases := [
		{"name": "晶弹对子+霜", "weapon": "absolute_zero", "damage_sym": "ice_crystal", "second_sym": "frost", "second_elem": "ice"},
		{"name": "铁斩对子+铁誓", "weapon": "mace", "damage_sym": "iron_slash", "second_sym": "iron_wall", "second_elem": "none"},
		{"name": "铁斩对子+匕斩", "weapon": "dueling_saber", "damage_sym": "iron_slash", "second_sym": "dagger_slash", "second_elem": "none"},
	]
	for c in cases:
		var item := {"name": c["name"], "weapon": c["weapon"]}
		# 可达性报告：用真实构筑装备该武器
		duel.selected_loadout.clear()
		duel.selected_loadout.append(String(WEAPONS[c["weapon"]]))
		duel._confirm_loadout()
		duel._build_pool(duel.selected_loadout)
		if duel.circuit_system != null:
			var reach: Variant = duel.circuit_system.reachability_report()
			item["pair_reachable_report"] = _reach_of(reach, "circuit_pair")
			var detail: Variant = duel.circuit_system.is_reachable("circuit_pair")
			item["pair_reachable_detail"] = detail
		else:
			item["pair_reachable_report"] = "no_circuit"
		# 真实判定：构造 counts（[SymbolData, elem, count, src]）
		var dmg: SymbolData = load(String(SYMS[c["damage_sym"]]))
		var sec: SymbolData = load(String(SYMS[c["second_sym"]]))
		var dmg_elem := String(dmg.element)
		if dmg_elem == "none":
			dmg_elem = "none"
		var counts := {}
		counts[dmg.resource_path + "|" + dmg_elem] = [dmg, dmg_elem, 2, {"src": 2}]
		counts[sec.resource_path + "|" + String(c["second_elem"])] = [sec, String(c["second_elem"]), 1, {"src": 1}]
		item["counts"] = {
			"damage_key": dmg.resource_path + "|" + dmg_elem,
			"damage_kind": dmg.kind,
			"second_key": sec.resource_path + "|" + String(c["second_elem"]),
			"second_kind": sec.kind,
		}
		item["pair_actual_trigger"] = duel.combat._has_pair_damage(counts)
		results.append(item)
		var line := "S2PAIR|%s|report=%s|actual=%s" % [
			String(c["name"]), str(item.get("pair_reachable_report", "?")), str(item["pair_actual_trigger"])]
		print(line)

	var payload := {
		"generated_at": Time.get_datetime_string_from_system(),
		"note": "对子可达性(构筑层报告) vs 真实结算判定(_has_pair_damage)对比；只采集不改判定",
		"cases": results,
	}
	_write_json(_out + "/pair_probe.json", payload)
	print("S2PAIR|RESULT_OK cases=%d" % results.size())
	get_tree().quit(0)

func _reach_of(report: Dictionary, id: String) -> Variant:
	if report is Dictionary:
		# 兼容 {id: bool} 或 {reachable:{id:..}} 结构
		if report.has(id):
			return report[id]
		for k in report:
			var v = report[k]
			if v is Dictionary and v.has(id):
				return v[id]
	return "not_found"

func _write_json(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("S2PAIR: cannot write " + path)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
