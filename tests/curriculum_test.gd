extends Node

# ============================================================================
# 课程化规范回归（2026-08-24，模型见 项目概览 §5.2 / 总清单「❓ 课程化复核」）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/curriculum_test.tscn
#
# 断言：
# ① 精英房全覆盖 mini 机制（gimmick_script + 非空 gimmick_params），且脚本 ∈ 本幕家族白名单；
# ② mini 参数弱于 BOSS 默认（抽查 rust/whisper/abyss 三家族关键键）；
# ③ 普通房不挂机制（普通 A/B 靠元素与行为族教学）；
# ④ BOSS 房 13 个 gimmick 不受影响。
# ============================================================================

const ELITE_FAMILY := {
	1: ["rust_armor_gimmick", "acid_bomb_gimmick"],
	2: ["whisper_lock_gimmick", "bipolar_phase_gimmick", "acid_bomb_gimmick"],
	3: ["abyss_erosion_gimmick"],
}

var _fails := 0
var _checks := 0


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame

	var elites := 0
	var bosses := 0
	for r in duel.ALL_ROOMS:
		var fid: String = r.resource_path.get_file()
		if r.kind == "elite":
			elites += 1
			_check(r.gimmick_script != null, "精英挂 mini 机制 %s" % fid)
			if r.gimmick_script == null:
				continue
			_check(not r.gimmick_params.is_empty(), "精英 params 非空 %s" % fid)
			var script_name: String = r.gimmick_script.resource_path.get_file().get_basename()
			_check(script_name in ELITE_FAMILY[int(r.act)],
				"精英机制 ∈ 幕%d 家族 %s（实测 %s）" % [int(r.act), fid, script_name])
			_check_mini_weakness(r, script_name)
		elif r.kind == "boss":
			bosses += 1
			_check(r.gimmick_script != null, "BOSS 挂机制 %s" % fid)
		else:
			_check(r.gimmick_script == null, "普通房无机制 %s" % fid)
	_check(elites == 12, "精英总数 12（%d）" % elites)
	_check(bosses == 13, "BOSS 总数 13（%d）" % bosses)

	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check_mini_weakness(r: RoomData, script_name: String) -> void:
	var p: Dictionary = r.gimmick_params
	match script_name:
		"rust_armor_gimmick":
			_check(int(p.get("interval", 2)) >= 3 and int(p.get("max_stacks", 3)) <= 2,
				"rust mini 弱于默认（interval≥3, stacks≤2）%s" % r.name)
		"acid_bomb_gimmick":
			_check(int(p.get("bomb_stacks", 10)) >= 10 and int(p.get("bomb_dmg", 30)) <= 30,
				"acid mini 弱于默认（阈值更高/伤害更低）%s" % r.name)
		"whisper_lock_gimmick":
			_check(int(p.get("lock_every", 3)) >= 4 and float(p.get("phase2_hp_ratio", 0.5)) == 0.0,
				"whisper mini 单阶段且低频 %s" % r.name)
		"bipolar_phase_gimmick":
			_check(float(p.get("manic_atk_mult", 2.0)) < 2.0 and float(p.get("manic_self_damage_pct", 0.05)) < 0.05,
				"bipolar mini 弱于默认 %s" % r.name)
		"abyss_erosion_gimmick":
			_check(float(p.get("base_ratio", 0.10)) <= 0.06 and float(p.get("phase3_hp_ratio", 0.33)) == 0.0,
				"abyss mini 稀释减半且单阶段 %s" % r.name)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("PASS  ", label)
	else:
		_fails += 1
		printerr("FAIL  ", label)