extends Node

# ============================================================================
# M3-03 数据绑定原则 · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/m3_binding_test.tscn
#
# 覆盖：
# ① 武器 / 技能共用基类暴露通用 icon_tex / art；符号与可携带物品同样可绑定图标
# ② 转轮格：符号有 icon_tex 时渲染图标并清空文字；无图回落 label
# ③ 整备列表：装备有 icon_tex 时按钮显示图标；无图不干预原有文本
# ④ 卡片：ItemCard.set_art 有图显示、无图隐藏
# ⑤ 武器与符号不因绑定美术而获得角色动画字段（无 anim_class / character 绑定）
# ============================================================================

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

	_test_fields()
	_test_reel_cell(duel)
	_test_list_button(duel)
	_test_card_art()

	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _boot() -> DuelController:
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
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


func _tex() -> Texture2D:
	var t := PlaceholderTexture2D.new()
	t.size = Vector2(16, 16)
	return t


func _test_fields() -> void:
	var wd := WeaponData.new()
	var sd := SkillData.new()
	var sym := SymbolData.new()
	var it := ItemData.new()
	_check(wd.get("icon_tex") != null or "icon_tex" in wd, "WeaponData 暴露 icon_tex")
	_check(sd.get("icon_tex") != null or "icon_tex" in sd, "SkillData 继承 icon_tex")
	_check("icon_tex" in sym, "SymbolData 暴露 icon_tex")
	_check("icon_tex" in it, "ItemData 暴露 icon_tex")
	_check(sym.icon_tex == null, "图标缺省为空（回落旧呈现）")
	_check(not ("anim_class" in sym) and not ("character" in sym), "符号不绑定 character / anim_class")


func _test_reel_cell(duel: DuelController) -> void:
	var sym := SymbolData.new()
	sym.label = "▲"
	sym.kind = "damage"
	duel.grid[0][0] = sym
	duel.grid_elem[0][0] = "none"
	duel.invalidate_state()
	duel.hud._refresh_cell(0, 0)
	var cell: Button = duel.hud.cells[0][0]
	_check(cell.icon == null and cell.text == "▲", "无图标：转轮格回落 label")
	var t := _tex()
	sym.icon_tex = t
	duel.invalidate_state()
	duel.hud._refresh_cell(0, 0)
	_check(cell.icon == t and cell.text == "", "有图标：转轮格显示图标并清空文字")
	duel.grid[0][0] = DuelController.TRASH_SYMBOL
	duel.invalidate_state()
	duel.hud._refresh_cell(0, 0)


func _test_list_button(duel: DuelController) -> void:
	var wd := WeaponData.new()
	wd.weapon_name = "测试武器"
	var t := _tex()
	wd.icon_tex = t
	var card: Dictionary = duel.hud._make_item_card(wd, "res://resources/weapon_templates/fire_sword.tres", "weapon")
	var btn: Button = card["btn"]
	_check(btn.icon == t, "整备列表：装备图标绑定到按钮")
	wd.icon_tex = null
	var card2: Dictionary = duel.hud._make_item_card(wd, "res://resources/weapon_templates/fire_sword.tres", "weapon")
	_check(card2["btn"].icon == null, "整备列表：无图标不设置图标")


func _test_card_art() -> void:
	var card: ItemCard = (load("res://scenes/ui/item_card.tscn") as PackedScene).instantiate()
	var icon_rect: TextureRect = card.get_node("Center/VBox/IconRect")
	card.set_art(_tex())
	_check(icon_rect.visible and icon_rect.texture != null, "卡片：有图显示主图")
	card.set_art(null)
	_check(not icon_rect.visible, "卡片：无图隐藏主图")
	card.queue_free()
