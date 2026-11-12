extends Node

# ============================================================================
# 课程化规范回归（2026-08-24，模型见 项目概览 §5.2 / 总清单「❓ 课程化复核」）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/curriculum_test.tscn
#
# 断言：
# ① 精英房全覆盖 mini 机制（gimmick_script + 非空 gimmick_params），且脚本 ∈ 本幕家族白名单；
# ② mini 参数弱于 BOSS 默认（抽查 rust/whisper/abyss 三家族关键键）；
# ③ 普通房最多挂 1 个早期特性（仅 normal_trait_gimmick，且 trait / 摘要非空）——Step 3 扩到三幕各 12 只；
# ④ BOSS 房 13 个 gimmick 不受影响。
# ============================================================================

const ELITE_FAMILY := {
	1: ["rust_armor_gimmick", "acid_bomb_gimmick"],
	2: ["whisper_lock_gimmick", "bipolar_phase_gimmick", "acid_bomb_gimmick"],
	3: ["abyss_erosion_gimmick", "sleight_gimmick", "shield_warden_gimmick",
		"annihilation_lord_gimmick", "final_watcher_gimmick"],
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
	var normal_traits := 0
	var normal_by_act := {1: 0, 2: 0, 3: 0}
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
			_check_elite_step4(r, script_name)
		elif r.kind == "boss":
			bosses += 1
			_check(r.gimmick_script != null, "BOSS 挂机制 %s" % fid)
		elif r.gimmick_script != null:
			# Step 4：普通怪允许且只允许一个早期特性样板；不得套用精英 / BOSS 多机制脚本。
			normal_traits += 1
			normal_by_act[int(r.act)] = int(normal_by_act.get(int(r.act), 0)) + 1
			var sn: String = r.gimmick_script.resource_path.get_file().get_basename()
			_check(sn == "normal_trait_gimmick", "普通房只挂早期特性脚本 %s（实测 %s）" % [fid, sn])
			_check(String(r.gimmick_params.get("trait", "")) != "", "普通特性 trait 非空 %s" % fid)
			_check(String(r.mechanic_summary) != "", "普通特性有可见摘要 %s" % fid)
	_check(elites == 12, "精英总数 12（%d）" % elites)
	_check(bosses == 13, "BOSS 总数 13（%d）" % bosses)
	_check(normal_traits == 36, "普通怪早期特性覆盖 36 只（%d）" % normal_traits)
	for a in [1, 2, 3]:
		_check(int(normal_by_act[a]) == 12, "ACT%d 普通怪特性 = 12（%d）" % [a, int(normal_by_act[a])])

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


func _check_elite_step4(r: RoomData, script_name: String) -> void:
	var p: Dictionary = r.gimmick_params
	_check(String(r.mechanic_summary) != "", "精英有可见机制摘要 %s" % r.name)
	match String(r.name):
		"寒铁精英":
			_check(bool(p.get("freeze_clears_on_break", false)),
				"D1：寒铁冻结随破甲解除 %s" % r.name)
		"毒疫术士":
			_check(int(p.get("pause_after_bomb_turns", 1)) == 2,
				"D2：毒疫爆炸后停毒 2 回合 %s" % r.name)
		"锈铁傀儡":
			_check(bool(p.get("apply_corrode", false)), "锈铁附加腐蚀 %s" % r.name)
		"腐殖巨蠕":
			_check(int(p.get("strip_every", 0)) == 4, "腐殖巨蠕周期剥增益 %s" % r.name)
		"深渊咒师":
			_check(bool(p.get("jam_on_lock", false)), "D4：深渊咒师锁列附注废 %s" % r.name)
		"炎爆群王":
			_check(int(p.get("self_damage_every", 1)) == 3, "D3：炎爆 P1 每 3 回合自损 %s" % r.name)
		"深渊咏者":
			_check(bool(p.get("same_col", false)) and bool(p.get("triple_counter", false)),
				"深渊咏者锁定同列 + 三连反制 %s" % r.name)
		"邪颂祭司":
			_check(int(p.get("self_damage_every", 0)) == 4 and float(p.get("self_damage_pct", 0.0)) > 0.0,
				"邪颂祭司自损换毒 %s" % r.name)
		_:
			_check(script_name != "abyss_erosion_gimmick", "精英不复用深渊侵蚀 %s" % r.name)


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("PASS  ", label)
	else:
		_fails += 1
		printerr("FAIL  ", label)