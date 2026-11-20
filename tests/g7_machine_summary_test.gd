extends Node

# ============================================================================
# G7-4 统一机器摘要测试（2026-11-20）
# 方案 §11.2：六类信息统一快照 + §2.2 可归因；服务整备/换装/战后/局末同一口径。
# ============================================================================

var _fails := 0
var _checks := 0


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("G7-4 FAIL: " + label)


func _ready() -> void:
	await get_tree().process_frame
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame
	var ms = duel.machine_summary
	_ok(ms != null, "MachineSummary 已注入")

	# ① 六类快照结构完整
	var s: Dictionary = ms.snapshot()
	for key in ["weapons", "symbols", "patterns", "circuits", "controls", "survival"]:
		_ok(s.has(key), "快照含 %s" % key)

	# ② 武器与仓库
	var w: Dictionary = s["weapons"]
	_ok((w["equipped"] as Array).size() == 2, "当前两把武器")
	_ok((w["equipped_names"] as Array).size() == 2, "武器名可读")

	# ③ 符号格数占比来源
	var sym: Dictionary = s["symbols"]
	_ok(int(sym["total_cells"]) > 0, "带长 >0（%d）" % int(sym["total_cells"]))
	_ok((sym["rows"] as Array).size() > 0, "符号行非空")
	var row0: Dictionary = sym["rows"][0]
	_ok(row0.has("name") and row0.has("cells") and row0.has("pct") and row0.has("sources"),
		"符号行含名称/格数/占比/来源")

	# ④ 回路（装备 + 报告）
	var cir: Dictionary = s["circuits"]
	_ok(cir.has("equipped") and cir.has("report"), "回路快照含装备与报告")

	# ⑤ 操控与生存
	var ctl: Dictionary = s["controls"]
	_ok(ctl.has("preset"), "操控快照含预设")
	var sv: Dictionary = s["survival"]
	_ok(sv.has("hp") and sv.has("gold"), "生存快照含 HP/金币")

	# ⑥ lines() 六类可读摘要
	var lines: Array = ms.lines()
	_ok(lines.size() == 6, "lines 输出 6 行（%d）" % lines.size())

	# ⑦ 可归因：回路触发/未触发解释 + 赔付口径
	duel._build_pool(duel.selected_loadout)
	duel.circuit_system.acquire("circuit_triple_echo")
	duel.circuit_system.equip("circuit_triple_echo")
	var attrs: Array = ms.attribution_lines()
	_ok(attrs.size() > 0, "可归因行非空（%d）" % attrs.size())
	var joined := ""
	for l in attrs:
		joined += String(l) + "\n"
	_ok(joined.contains("回路未触发") or joined.contains("回路触发"), "可归因含回路解释")
	_ok(joined.contains("赔付口径") or joined.contains("赔付表"), "可归因指向统一赔付表")

	print("G7-4 MACHINE SUMMARY RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
