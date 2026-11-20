extends Node

# ============================================================================
# G7-1 铸式解锁改行为条件测试（2026-11-20）
# 方案 §10.1 / G7-1：解锁从"历史 R2"改为"行为条件（累计出场 N 局）"，保留老存档解锁。
# ============================================================================

var _fails := 0
var _checks := 0
const FIRE := "res://resources/weapon_templates/fire_sword.tres"


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		push_error("G7-1 FAIL: " + label)


func _ready() -> void:
	await get_tree().process_frame
	var duel: DuelController = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	var fs = duel._forge_styles

	# ① 新行为条件：累计出场 3 局解锁
	duel.meta["codex"] = {}
	duel._codex = preload("res://scripts/systems/codex_system.gd").new(duel)
	_ok(not fs.unlocked(FIRE), "初始未解锁")
	for i in range(3):
		duel._codex.note_style_use(FIRE)
	_ok(duel._codex.style_uses_of(FIRE) == 3, "出场次数累计正确（3）")
	_ok(fs.unlocked(FIRE), "累计出场 3 局后解锁")

	# ② 图鉴文案不再显示 R 等级门槛
	var txt: String = fs.unlock_text(FIRE)
	_ok(fs.unlocked(FIRE) and txt == "已解锁", "解锁后文案（%s）" % txt)
	duel.meta["codex"] = {}
	duel._codex = preload("res://scripts/systems/codex_system.gd").new(duel)
	txt = fs.unlock_text(FIRE)
	_ok(not txt.contains("R"), "锁定时文案无 R 等级（%s）" % txt)
	_ok(txt.contains("出场"), "锁定时文案含行为条件（%s）" % txt)

	# ③ 老存档兼容：历史 R2 保留解锁（不回锁）
	duel.meta["codex"] = {FIRE: {"best_rank": 2, "best_mastery": 7, "style_uses": 0}}
	duel._codex = preload("res://scripts/systems/codex_system.gd").new(duel)
	_ok(fs.unlocked(FIRE), "老存档 R2 保留解锁（不回锁）")

	# ④ 已解锁的铸式选择保留
	_ok(fs.set_style(FIRE, "lie_ren"), "老存档解锁后可设置铸式")
	_ok(String(fs.selected_id(FIRE)) == "lie_ren", "铸式选择保留")

	# ⑤ 不支持的武器仍拒绝
	_ok(not fs.unlocked("res://resources/weapon_templates/nope.tres"), "不支持武器不解锁")

	print("G7-1 FORGE UNLOCK RESULT: %d checks, %d fails" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
