extends Node

# ============================================================================
# T3 阶段 2 · 武器去状态符号契约（2026-11-27）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t3_no_status_weapon_contract_test.tscn
#
# 阶段 2 裁决：状态符号（燃烧/霜冻/中毒/圣灼/暗蚀）不再由武器进入轮池；
# 武器的状态改为「命中后按概率触发」（status_migrated / status_family / status_chance / status_stacks）。
#
# 判定「未迁移」：武器 .tres 满足全部三条 ——
#   1) archived != true（在正式池，不是软封存老武器）
#   2) status_migrated != true（还没走迁移管道）
#   3) symbols 里引用了 kind == "status" 的符号（仍带状态符号位）
#
# 白名单是硬编码的人工期望，不得用实际结果反推：每迁完一把必须显式删除对应 id，
# 否则测试保持红。多一条、少一条都算不符。清零 = 「状态符号全量离池」完成。
# ============================================================================

const WEAPON_DIR := "res://resources/weapon_templates"

# 当前仍未迁移的正式池武器（15 把，与对照表一致）。每批迁移完成后显式删除对应 id。
const PENDING_MIGRATED_WEAPONS := [
	"acolyte_blade",
	"cinder_saber",
	"dawn_bow",
	"eclipse_blade",
	"fire_sword",
	"frost_dagger",
	"gloom_saber",
	"holy_sword",
	"inferno_axe",
	"miasma_staff",
	"night_scythe",
	"plague_reaper",
	"shadow_dagger",
	"venom_queen",
	"venom_sickle",
]

var _checks := 0
var _fails := 0


func _ready() -> void:
	await get_tree().process_frame
	_run()
	print("T3NOWEAPON|RESULT %s (checks=%d fails=%d)" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _run() -> void:
	var weapons := _load_weapons()
	_check(weapons.size() > 0, "扫描到武器资源（%d）" % weapons.size())
	_check(not PENDING_MIGRATED_WEAPONS.is_empty(),
		"白名单非空（%d 条）" % PENDING_MIGRATED_WEAPONS.size())

	var actual: Array[String] = []
	for w in weapons:
		if _is_unmigrated_with_status(w):
			actual.append(_weapon_id(w))
	actual.sort()

	var want: Array[String] = []
	for id in PENDING_MIGRATED_WEAPONS:
		want.append(String(id))
	want.sort()

	var extra: Array[String] = []
	for id in actual:
		if not want.has(id):
			extra.append(id)
	var stale: Array[String] = []
	for id in want:
		if not actual.has(id):
			stale.append(id)
	_check(actual == want,
		"未迁移且带状态符号的武器集合 == 白名单（多出 %s / 缺 %s / 实测 %s）" % [
			str(extra), str(stale), str(actual)])


func _load_weapons() -> Array:
	var out: Array = []
	var dir := DirAccess.open(WEAPON_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var w = load(WEAPON_DIR + "/" + f)
		if w != null:
			out.append(w)
	return out


func _weapon_id(w) -> String:
	return String(w.resource_path).get_file().get_basename()


func _is_unmigrated_with_status(w) -> bool:
	if bool(w.get("archived")):
		return false
	if bool(w.get("status_migrated")):
		return false
	for entry in w.symbols:
		if entry == null:
			continue
		var sym = entry.symbol
		if sym != null and String(sym.kind) == "status":
			return true
	return false


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)
