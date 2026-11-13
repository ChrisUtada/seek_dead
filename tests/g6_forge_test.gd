extends Node

# ============================================================================
# G6-05 横向铸式 · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/g6_forge_test.tscn
#
# 覆盖：
# ① 只有 4 把代表武器支持铸式；每把最多一个；
# ② 解锁条件：历史熟练 R2；未解锁不能选择；
# ③ 选择写入 anvil_meta.forge_styles，跨实例保留，非法路径/id 自动清理；
# ④ 4 个变体的优势与代价同时存在（攻/命中/权重/破甲连数/状态层数）；
# ⑤ build_pool 应用真实修正（攻/命中/符号权重/破甲阈值/状态加成）；
# ⑥ ReelPreview 能预览真实带子格数差异（4 个变体均非空）；
# ⑦ 整备屏铸式面板可打开、可切换、标准形态可恢复。
# 测试结束还原 meta（不污染玩家真实存档）。
# ============================================================================

const FIRE := "res://resources/weapon_templates/fire_sword.tres"
const DAGGER := "res://resources/weapon_templates/dagger.tres"
const AXE := "res://resources/weapon_templates/battle_axe.tres"
const ICE := "res://resources/weapon_templates/ice_staff.tres"
const CINDER := "res://resources/weapon_templates/cinder_saber.tres"
const FIRE_SLASH := "res://resources/symbols/fire_slash.tres"
const DAGGER_SLASH := "res://resources/symbols/dagger_slash.tres"
const AXE_SLASH := "res://resources/symbols/axe_slash.tres"
const ICE_CRYSTAL := "res://resources/symbols/ice_crystal.tres"

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
	# 从干净选择开始：玩家存档里可能已有铸式选择，本套按空选择验证解锁/选择/清理。
	duel.meta["forge_styles"] = {}
	duel._forge_styles = preload("res://scripts/systems/forge_style_system.gd").new(duel)

	_test_defaults(duel)
	_test_unlock_and_select(duel)
	_test_persist_and_sanitize(duel)
	_test_modifiers(duel)
	_test_build_pool(duel)
	_test_strip_diffs(duel)
	_test_ui(duel)

	duel.meta.clear()
	for k in meta_backup:
		duel.meta[k] = meta_backup[k]
	duel._meta_store.save_meta()

	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _boot() -> DuelController:
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel: DuelController = scene_res.instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
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


func _fs(duel: DuelController):
	return duel._forge_styles


func _unlock_all(duel: DuelController) -> void:
	duel.meta["codex"] = {}
	for p in [FIRE, DAGGER, AXE, ICE]:
		duel.meta["codex"][p] = {"uses": 1, "best_rank": 2, "best_mastery": 3, "forge": 0, "tune": {}}
	duel._codex = preload("res://scripts/systems/codex_system.gd").new(duel)


func _select(duel: DuelController, path: String, id: String) -> void:
	_fs(duel).set_style(path, id)


func _test_defaults(duel: DuelController) -> void:
	var fs = _fs(duel)
	_check(duel.meta.has("forge_styles") and duel.meta["forge_styles"] is Dictionary, "控制器默认含 forge_styles 键")
	_check(fs.is_supported(FIRE) and fs.is_supported(DAGGER) and fs.is_supported(AXE) and fs.is_supported(ICE), "首批支持火焰剑/匕首/战斧/霜晶法杖")
	_check(not fs.is_supported(CINDER), "未扩展到其它武器")
	duel.meta["codex"] = {}
	duel._codex = preload("res://scripts/systems/codex_system.gd").new(duel)
	_check(not fs.unlocked(FIRE), "历史熟练不足时变体锁定")
	_check(fs.current_rank(FIRE) == 1, "无记录按 R1 展示")
	_check(fs.unlock_text(FIRE).contains("R2"), "锁定提示写明 R2 条件")
	_check(not fs.set_style(FIRE, "lie_ren"), "未解锁时拒绝选择变体")
	_check(fs.selected_id(FIRE) == "", "未解锁时仍为标准形态")


func _test_unlock_and_select(duel: DuelController) -> void:
	_unlock_all(duel)
	var fs = _fs(duel)
	_check(fs.unlocked(FIRE) and fs.unlocked(DAGGER) and fs.unlocked(AXE) and fs.unlocked(ICE), "历史熟练 R2 解锁全部 4 个变体")
	_check(fs.set_style(FIRE, "lie_ren"), "解锁后可选择烈刃")
	_check(fs.selected_id(FIRE) == "lie_ren", "选择写入 meta")
	_check(String(fs.selected_def(FIRE).get("name", "")) == "烈刃", "selected_def 返回烈刃")
	_check(not fs.set_style(FIRE, "not_a_style"), "非法变体 id 被拒绝")
	_check(not fs.set_style(AXE, "lie_ren"), "变体 id 不能跨武器错配")
	_check(not fs.set_style(CINDER, "anything"), "不支持的武器拒绝选择")
	_check(fs.set_style(FIRE, ""), "可切回标准形态")
	_check(fs.selected_id(FIRE) == "" and fs.power_bonus(FIRE) == 0, "标准形态无修正")
	_check(fs.set_style(FIRE, "lie_ren"), "再次选择烈刃")


func _test_persist_and_sanitize(duel: DuelController) -> void:
	var fs = _fs(duel)
	_select(duel, DAGGER, "wen_shou")
	var again = preload("res://scripts/systems/forge_style_system.gd").new(duel)
	_check(again.selected_id(FIRE) == "lie_ren" and again.selected_id(DAGGER) == "wen_shou", "选择跨 ForgeStyleSystem 实例保留")
	duel.meta["forge_styles"]["res://resources/weapon_templates/nope.tres"] = "lie_ren"
	duel.meta["forge_styles"][ICE] = "bogus"
	var cleaned = preload("res://scripts/systems/forge_style_system.gd").new(duel)
	_check(not duel.meta["forge_styles"].has("res://resources/weapon_templates/nope.tres"), "非法武器路径被清理")
	_check(not duel.meta["forge_styles"].has(ICE), "非法变体 id 被清理")
	_check(cleaned.selected_id(FIRE) == "lie_ren" and cleaned.selected_id(DAGGER) == "wen_shou", "合法选择不被清理")


func _test_modifiers(duel: DuelController) -> void:
	_unlock_all(duel)
	var fs = _fs(duel)
	_select(duel, FIRE, "lie_ren")
	_select(duel, DAGGER, "wen_shou")
	_select(duel, AXE, "po_cheng")
	_select(duel, ICE, "shuang_ming")
	_check(fs.power_bonus(FIRE) == 2 and is_equal_approx(fs.hit_delta(FIRE), -0.05), "烈刃：攻 +2 / 命中 -5%")
	_check(fs.power_bonus(DAGGER) == -2 and is_equal_approx(fs.hit_delta(DAGGER), 0.08), "稳手：攻 -2 / 命中 +8%")
	_check(is_equal_approx(fs.weight_delta(AXE, AXE_SLASH), -2.0) and fs.pierce_at(AXE) == 2, "破城：斧斩权重 -2 / 破甲 2 连")
	_check(is_equal_approx(fs.weight_delta(ICE, ICE_CRYSTAL), -1.0) and fs.power_bonus(ICE) == -2, "霜鸣：冰霜晶弹权重 -1 / 攻 -2")
	_check(fs.status_bonus(ICE) == 1, "霜鸣：每次状态 +1 层")
	_check(fs.pierce_at(DAGGER) == 3, "未选破城的武器保持 3 连破甲")
	_check(fs.stat_line(AXE).contains("破甲 3连→2连"), "破城属性行写明破甲连数变化")
	_check(fs.stat_line(ICE).contains("状态 +1层/次"), "霜鸣属性行写明状态层数变化")


func _test_build_pool(duel: DuelController) -> void:
	var fs = _fs(duel)
	_select(duel, FIRE, "lie_ren")
	_select(duel, DAGGER, "wen_shou")
	_select(duel, AXE, "po_cheng")
	_select(duel, ICE, "shuang_ming")

	duel.selected_loadout.clear()
	duel.selected_loadout.append(FIRE)
	duel.selected_loadout.append(ICE)
	duel._build_pool(duel.selected_loadout)
	_check(is_equal_approx(float(duel._weapon_power_map.get(FIRE_SLASH, 0.0)), 20.0), "烈刃入池：火焰剑攻击 18→20")
	var fire_item := _item_named(duel, "火焰剑")
	_check(fire_item != null and is_equal_approx(float(fire_item.get("hit", 0.0)), 0.83), "烈刃入池：命中 88%→83%")
	_check(is_equal_approx(float(duel._weapon_power_map.get(ICE_CRYSTAL, 0.0)), 12.0), "霜鸣入池：霜晶法杖攻击 14→12")
	_check(int(duel._item_status_bonus.get(ICE_CRYSTAL, 0)) == 1, "霜鸣入池：冰霜晶弹带 +1 状态层")
	_check(_weight_of(duel, ICE_CRYSTAL) == 3.0, "霜鸣入池：冰霜晶弹权重 4→3")

	duel.selected_loadout.clear()
	duel.selected_loadout.append(DAGGER)
	duel._build_pool(duel.selected_loadout)
	var dagger_item := _item_named(duel, "匕首")
	_check(is_equal_approx(float(duel._weapon_power_map.get(DAGGER_SLASH, 0.0)), 6.0), "稳手入池：匕首攻击 8→6")
	_check(dagger_item != null and is_equal_approx(float(dagger_item.get("hit", 0.0)), 0.94), "稳手入池：命中 86%→94%")

	duel.selected_loadout.clear()
	duel.selected_loadout.append(AXE)
	duel._build_pool(duel.selected_loadout)
	_check(_weight_of(duel, AXE_SLASH) == 3.0, "破城入池：斧斩权重 5→3")
	_check(int(duel._item_pierce_at.get(AXE_SLASH, 3)) == 2, "破城入池：斧斩破甲阈值 3→2")
	_check(int(duel._item_pierce_map.get(AXE_SLASH, false)) != 0, "破城保留破甲机制")


func _test_strip_diffs(duel: DuelController) -> void:
	var fs = _fs(duel)
	var d_fire: Array = _diff([FIRE, ICE], FIRE, fs.style_def(FIRE))
	var d_dagger: Array = _diff([DAGGER, AXE], DAGGER, fs.style_def(DAGGER))
	var d_axe: Array = _diff([AXE], AXE, fs.style_def(AXE))
	var d_ice: Array = _diff([ICE], ICE, fs.style_def(ICE))
	_check(not d_fire.is_empty() and _joined(d_fire).contains("MISS"), "烈刃真实带子差异：MISS 格变化")
	_check(not d_dagger.is_empty() and _joined(d_dagger).contains("MISS"), "稳手真实带子差异：MISS 格变化")
	_check(not d_axe.is_empty() and _joined(d_axe).contains("4→3"), "破城真实带子差异：斧斩 4→3 格")
	_check(not d_ice.is_empty() and _joined(d_ice).contains("4→3"), "霜鸣真实带子差异：冰霜晶弹 4→3 格")
	# 方向：标准 → 铸式。稳手是 MISS 减少（负数），烈刃是 MISS 增加（正数）。
	_check(_joined(d_dagger).contains("-1格"), "稳手预览方向：MISS 减少")
	_check(_joined(d_fire).contains("+1格"), "烈刃预览方向：MISS 增加")
	# 未装备时不伪造带子差异。
	_check(fs.strip_diff(CINDER).is_empty(), "不支持的武器没有铸式带子差异")


func _test_ui(duel: DuelController) -> void:
	_unlock_all(duel)
	duel.meta["owned_weapons"] = [FIRE, DAGGER, AXE, ICE]
	var scene = duel.hud.loadout_screen
	_check(scene != null, "整备屏存在")
	_check(scene._forge_btn != null and scene._forge_panel != null, "整备屏构建铸式按钮与面板")
	scene._toggle_forge()
	_check(scene._forge_panel.visible, "铸式面板可打开")
	var before: int = int(scene._forge_box.get_child_count())
	_check(before >= 12, "铸式面板列出 4 把武器的优势/代价/属性/带子")
	scene._on_forge_choose(FIRE, "lie_ren")
	_check(duel.meta["forge_styles"].get(FIRE, "") == "lie_ren", "面板选择写入存档")
	scene._on_forge_choose(FIRE, "")
	_check(not duel.meta["forge_styles"].has(FIRE), "面板可切回标准形态")
	scene._toggle_forge()
	_check(not scene._forge_panel.visible, "铸式面板可关闭")
	_check(_widget_text(scene._forge_box).contains("标准形态"), "面板文案含标准形态按钮")


func _diff(loadout: Array, path: String, def: Dictionary) -> Array:
	return ReelPreview.diff_lines(loadout, loadout, [], [], [], {}, 0, false, 0, {}, {}, {}, {path: def})


func _item_named(duel: DuelController, name: String) -> Dictionary:
	for it in duel.pool_items:
		if String(it.get("name", "")) == name:
			return it
	return {}


func _weight_of(duel: DuelController, sym_path: String) -> float:
	for it in duel.pool_items:
		for s in it.get("syms", []):
			if String(s[0].resource_path) == sym_path:
				return float(s[1])
	return -1.0


func _joined(items: Array) -> String:
	var out := ""
	for l in items:
		out += String(l) + "\n"
	return out


func _widget_text(node: Node) -> String:
	var out := ""
	if node is Label:
		out += String((node as Label).text) + "\n"
	elif node is Button:
		out += String((node as Button).text) + "\n"
	for c in node.get_children():
		out += _widget_text(c)
	return out
