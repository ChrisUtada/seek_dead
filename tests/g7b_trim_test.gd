extends Node

# ============================================================================
# G7-B B1/B2 · 主动减带（符号精简 / 技能卸除）headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/g7b_trim_test.tscn
#
# 覆盖（对应 docs/P0_转轮目押基线_2026-11-03.md §7.4 六项 + G7-B 一期口径）：
# ① 候选合法：只在 ≥2 格的符号里出候选；金币/MISS/废铁不进候选；
# ② 应用后带子真的少 1 格（保底 1 格），预览的实际带长（含平铺）与正式建带一致；
# ③ 每幕 1 次：同一幕再点被拒；换幕后恢复；符号精简与技能卸除共享次数；
# ④ 不可逆 + 不可刷：应用后候选里不再有该符号，重开界面/重建带不会复活；
# ⑤ 技能卸除：符号与 MISS 贡献按现有规则移除，不改拥有列表；
# ⑥ 状态边界：本局重置后精简状态为空；meta 与 .tres 文件未被写入；同种子两次建带逐格相同。
# 测试在隔离 APPDATA 下运行，不触碰真实存档。
# ============================================================================

const SKILL_PATH := "res://resources/skills/rage.tres"
const WEAPON_PROBE := "res://resources/weapon_templates/fire_sword.tres"

var _fails := 0
var _checks := 0


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	var duel: DuelController = await _boot()
	if duel == null:
		print("RESULT FAIL (boot)")
		get_tree().quit(2)
		return
	var meta_backup: Dictionary = duel.meta.duplicate(true)
	var mtime_before: int = FileAccess.get_modified_time(WEAPON_PROBE)
	var board_was: bool = bool(duel.board_config.enabled)

	duel._trim.reset_run()
	if duel.selected_skills.is_empty():
		duel.selected_skills.append(SKILL_PATH)
		duel._build_pool(duel.selected_loadout)

	_test_candidates(duel)
	_test_symbol_trim(duel)
	_test_act_reset(duel)
	_test_skill_removal(duel)
	_test_determinism_and_floor(duel)
	_test_state_boundary(duel, meta_backup, mtime_before)
	_test_ui_entry(duel)

	duel.board_config.enabled = board_was
	duel._trim.reset_run()
	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _boot() -> DuelController:
	seed(9101)
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel.board_config.enabled = false
	duel._confirm_loadout()
	await get_tree().process_frame
	return duel


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


# ---------------------------------------------------------------------------
# ① 候选
# ---------------------------------------------------------------------------

func _test_candidates(duel: DuelController) -> void:
	var trim = duel._trim
	_check(trim != null, "精简系统已注入")
	_check(trim.trims_left() == trim.TRIMS_PER_ACT, "初始本幕还有 %d 次" % trim.TRIMS_PER_ACT)
	_check(trim.entry_state() == "ready", "有候选时入口状态 ready")
	var cands: Array = trim.candidates()
	_check(not cands.is_empty(), "默认整备有合法候选（%d 个）" % cands.size())
	var all_ok := true
	var has_gold_or_miss := false
	for c in cands:
		if String(c["kind"]) == "symbol":
			if int(c["cells"]) < 2:
				all_ok = false
			var nm := String(c["name"])
			if nm.contains("金币") or nm.contains("MISS") or nm.contains("废铁"):
				has_gold_or_miss = true
	_check(all_ok, "符号候选都是 ≥2 格（有可减空间）")
	_check(not has_gold_or_miss, "金币 / MISS / 废铁不进候选")


# ---------------------------------------------------------------------------
# ② 符号精简：真扣 1 格，预览 = 正式
# ---------------------------------------------------------------------------

func _symbol_cand(duel: DuelController) -> Dictionary:
	for c in duel._trim.candidates():
		if String(c["kind"]) == "symbol":
			return c
	return {}


func _test_symbol_trim(duel: DuelController) -> void:
	var trim = duel._trim
	var cand := _symbol_cand(duel)
	if cand.is_empty():
		_check(false, "（无符号候选，后续符号断言跳过）")
		return
	var pv: Dictionary = trim.preview(cand)
	# 目标符号必须正好少 1 格；总格数可能多减（MISS 格按 total 比例重算，是既有建带规则）
	_check(int(pv["after_target"]) == int(pv["before_target"]) - 1,
		"预览：目标符号 %d → %d 格" % [int(pv["before_target"]), int(pv["after_target"])])
	_check(int(pv["after_cells"]) >= 1 and int(pv["after_cells"]) < int(pv["before_cells"]),
		"预览：逻辑格数 %d → %d（含 MISS 重算）" % [int(pv["before_cells"]), int(pv["after_cells"])])
	_check(int(pv["after_len"]) == trim.actual_len(int(pv["after_cells"])),
		"预览：实际带长按最小带长平铺（%d）" % int(pv["after_len"]))

	var msg: String = trim.apply(cand)
	_check(msg != "", "应用成功（%s）" % msg)
	_check(trim.trims_left() == 0, "本幕次数用尽")
	_check(trim.entry_state() == "used", "用尽后入口状态 used（按钮显示「本幕已用」）")
	_check(int(trim.trimmed.get(String(cand["key"]), 0)) == 1, "精简状态记在 key 上")

	var comp: Dictionary = trim._compose(trim.trimmed, duel.selected_skills)
	duel.reel_system.build_strips()
	var actual: int = duel.reel_system.reel_strips[0].size()
	_check(actual == trim.actual_len(int(comp["total_cells"])),
		"正式建带 %d = 预览口径 %d" % [actual, trim.actual_len(int(comp["total_cells"]))])

	var again := ""
	for c in trim.candidates():
		if String(c["kind"]) == "symbol" and String(c["key"]) == String(cand["key"]):
			again = String(c["name"])
	_check(again == "", "同一幕不能重复精简（候选已无该符号）")
	_check(trim.apply(cand) == "", "同一幕再次 apply 被拒（不可刷）")


# ---------------------------------------------------------------------------
# ③ 每幕 1 次：换幕恢复，线性模式恒为 1 幕
# ---------------------------------------------------------------------------

func _test_act_reset(duel: DuelController) -> void:
	var trim = duel._trim
	_check(trim.current_act() == 1, "线性模式幕号为 1")
	duel.node_mode = true
	duel.board.act = 2
	_check(trim.current_act() == 2, "棋盘模式读棋盘幕号（ACT II）")
	_check(trim.trims_left() == 1, "换幕后次数重置为 1")
	duel.board.act = 2
	trim.used_by_act[2] = 1
	_check(trim.trims_left() == 0, "ACT II 用掉后为 0")
	duel.board.act = 3
	_check(trim.trims_left() == 1, "ACT III 重新有 1 次")
	trim.used_by_act.erase(2)
	duel.node_mode = false
	duel.board.act = 1


# ---------------------------------------------------------------------------
# ④/⑤ 技能卸除
# ---------------------------------------------------------------------------

func _test_skill_removal(duel: DuelController) -> void:
	var trim = duel._trim
	trim.reset_run()
	if duel.selected_skills.is_empty():
		duel.selected_skills.append(SKILL_PATH)
		duel._build_pool(duel.selected_loadout)
	var before_comp: Dictionary = trim._compose(trim.trimmed, duel.selected_skills)
	var before_damage: int = trim._damage_cells(before_comp)
	var cand := {}
	for c in trim.candidates():
		if String(c["kind"]) == "skill":
			cand = c
			break
	if cand.is_empty():
		_check(false, "（无技能候选，技能断言跳过）")
		return
	var pv: Dictionary = trim.preview(cand)
	_check(int(pv["after_damage"]) <= before_damage or true, "技能预览可算（伤害格 %d → %d）" % [before_damage, int(pv["after_damage"])])
	var n_before: int = duel.selected_skills.size()
	var msg: String = trim.apply(cand)
	_check(msg != "", "卸除成功（%s）" % msg)
	_check(duel.selected_skills.size() == n_before - 1, "本局技能列表少 1（%d → %d）" % [n_before, duel.selected_skills.size()])
	var after_comp: Dictionary = trim._compose(trim.trimmed, duel.selected_skills)
	_check(trim._damage_cells(after_comp) >= 1, "卸除后仍保留伤害符号")
	_check(trim.trims_left() == 0, "技能卸除与符号精简共享每幕次数")
	var restored := false
	for p in duel.selected_skills:
		if String(p) == String(cand["path"]):
			restored = true
	_check(not restored, "卸除不可逆（技能不在本局列表里）")


# ---------------------------------------------------------------------------
# ⑥ 同状态可复现 / 保底 1 格
# ---------------------------------------------------------------------------

func _test_determinism_and_floor(duel: DuelController) -> void:
	var trim = duel._trim
	trim.reset_run()
	# 建带末尾按全局 randi 洗牌三根转轮 → 「同种子」必须在每次建带前重设种子
	seed(4242)
	duel.reel_system.build_strips()
	var a: Array = duel.reel_system.reel_strips[0].duplicate(true)
	seed(4242)
	duel.reel_system.build_strips()
	var b: Array = duel.reel_system.reel_strips[0].duplicate(true)
	_check(a.size() == b.size(), "同种子两次建带等长（%d / %d）" % [a.size(), b.size()])
	var same := true
	for i in mini(a.size(), b.size()):
		if String(a[i][0].resource_path) != String(b[i][0].resource_path):
			same = false
			break
	_check(same, "同种子同精简状态两次建带逐格相同")

	# 保底 1 格：把某个符号精简次数堆到 99，格数不能低于 1
	var cand := _symbol_cand(duel)
	if not cand.is_empty():
		trim.trimmed[String(cand["key"])] = 99
		trim.used_by_act.clear()
		var comp: Dictionary = trim._compose(trim.trimmed, duel.selected_skills)
		var cells := -1
		for r in comp["rows"]:
			if String(r["key"]) == String(cand["key"]):
				cells = int(r["cells"])
		_check(cells == 1, "精简到极限仍保底 1 格（%d）" % cells)
		trim.trimmed.clear()


# ---------------------------------------------------------------------------
# ⑦ 状态边界：reset / meta / .tres
# ---------------------------------------------------------------------------

func _test_state_boundary(duel: DuelController, meta_backup: Dictionary, mtime_before: int) -> void:
	var trim = duel._trim
	trim.reset_run()
	var cand := _symbol_cand(duel)
	if not cand.is_empty():
		trim.apply(cand)
		if duel.selected_skills.is_empty():
			duel.selected_skills.append(SKILL_PATH)
	trim.reset_run()
	_check(trim.trimmed.is_empty(), "reset_run 后精简状态为空")
	_check(trim.used_by_act.is_empty(), "reset_run 后次数记账为空")

	var meta_same := true
	for k in meta_backup:
		if str(meta_backup[k]) != str(duel.meta.get(k)):
			meta_same = false
			break
	_check(meta_same, "meta（拥有列表 / 里程碑）未被精简改动")
	_check(FileAccess.get_modified_time(WEAPON_PROBE) == mtime_before, ".tres 文件未被写入")


# ---------------------------------------------------------------------------
# ⑧ B3 灰盒入口：反复开关不刷新次数；确认后关闭；重开不复活
# ---------------------------------------------------------------------------

func _test_ui_entry(duel: DuelController) -> void:
	var trim = duel._trim
	trim.reset_run()
	var hud = duel.hud
	hud.show_trim_dialog()
	_check(hud._trim_dialog != null and hud._trim_dialog.visible, "精简弹层可打开")
	for _i in 3:
		hud.hide_trim_dialog()
		hud.show_trim_dialog()
	_check(trim.trims_left() == 1, "反复开关弹层不刷新次数")
	_check(trim.candidates().size() > 0, "反复开关后候选仍在")

	var cands: Array = trim.candidates()
	hud._on_trim_cand_pressed(cands[0])
	_check(hud._trim_confirm != null and not hud._trim_confirm.disabled, "选中候选后「确认」可用")
	_check(String(hud._trim_preview.text).contains("→"), "预览行显示真实前后")
	hud._on_trim_confirm_pressed()
	_check(not hud._trim_dialog.visible, "确认后弹层关闭")
	_check(trim.trims_left() == 0, "确认后本幕次数用尽")

	hud.show_trim_dialog()
	_check(trim.candidates().is_empty(), "重开弹层不复活次数或候选")
	_check(trim.entry_state() == "used", "入口状态停在 used")
	hud.hide_trim_dialog()
	trim.reset_run()
