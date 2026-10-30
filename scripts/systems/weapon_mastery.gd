# WeaponMastery — 武器熟练 R1–R4 与铭印（M2-02，ACT1 样板）
# 运行时经 duel_controller preload 实例化（不注册全局 class_name——headless 测试环境不刷新类缓存）。
# 职责：房间胜利时按「本房有效符号结算」给样板武器累计熟练 → R2 / R3 各欠一次铭印选择 →
# 铭印写入本局运行时状态（锋铸 +基础攻击 / 调律 +符号权重），不改共享 .tres。
# 规格见 docs/M0-02_样板范围.md §2；R4 一期只保留等级与外观。

var _ctrl  # DuelController

const SAMPLE_WEAPONS := [
	"res://resources/weapon_templates/dagger.tres",
	"res://resources/weapon_templates/fire_sword.tres",
	"res://resources/weapon_templates/battle_axe.tres",
	"res://resources/weapon_templates/ice_staff.tres",
]
const ROOM_GAIN_CAP := 3                                  # 每把每房熟练上限
const R_THRESHOLDS := {2: 3, 3: 7, 4: 12}                 # R 等级累计熟练门槛
const IMPRINT_LEVELS := [2, 3]                            # 升到这些 R 等级时欠一次铭印选择
const IMPRINT_MAX := 2                                    # 同一铭印每把最多次数
const FORGE_STEP := 2                                     # 锋铸：每次 +基础攻击

var mastery: Dictionary = {}          # 武器路径 -> 熟练累计
var imprints: Dictionary = {}         # 武器路径 -> {"forge": n, "tune": {符号路径: n}}
var owed: Array[String] = []          # 欠铭印选择的武器路径（每项 = 一次选择）
var _room_gain: Dictionary = {}       # 本房各武器已获熟练（每房上限用）
var _settled: Dictionary = {}         # 本房产生过有效结算的符号路径


func _init(ctrl) -> void:
	_ctrl = ctrl


# 新一局 / 战败回整备：熟练、铭印、欠选全部清零。
func reset_run() -> void:
	mastery.clear()
	imprints.clear()
	owed.clear()
	reset_room()


# 每房开局：清本房结算记录与熟练上限计数。
func reset_room() -> void:
	_room_gain.clear()
	_settled.clear()


# combat evaluate 的有效结算点调用（非 trash/buff/金币 的符号真正结算时）。
func note_settle(sym_path: String) -> void:
	_settled[sym_path] = true


# R 等级：1 起步，按累计熟练跨过 R2 / R3 / R4 门槛。
func r_level(path: String) -> int:
	var m: int = int(mastery.get(path, 0))
	var lv := 1
	for k in R_THRESHOLDS:
		if m >= int(R_THRESHOLDS[k]):
			lv = maxi(lv, int(k))
	return lv


# 房间胜利：样板武器（已装备且本房有有效结算）获得熟练；跨过 R2 / R3 则欠一次铭印。
func settle_room(kind: String) -> void:
	var gain_base := 1 + (1 if kind == "elite" else 0) + (1 if kind == "boss" else 0)
	for path in _ctrl.selected_loadout:
		if not SAMPLE_WEAPONS.has(path) or not _weapon_settled(path):
			continue
		var room_so_far: int = int(_room_gain.get(path, 0))
		var gain := mini(gain_base, ROOM_GAIN_CAP - room_so_far)
		if gain <= 0:
			continue
		_room_gain[path] = room_so_far + gain
		var before: int = r_level(path)
		mastery[path] = int(mastery.get(path, 0)) + gain
		var after: int = r_level(path)
		_ctrl.hud._log("⚒ 熟练 %s +%d（R%d · %d/%d）" % [display_name(path), gain, after, int(mastery[path]), _next_threshold(after)])
		for lv in IMPRINT_LEVELS:
			if lv > before and lv <= after:
				owed.append(path)
				_ctrl.hud._log("✦ %s 达 R%d：可选择一项铭印" % [display_name(path), lv])


# 欠铭印的候选（展示即定；调律仅在真实改变格数时出现，死升级不展示）。
func imprint_choices(path: String) -> Array:
	var out := []
	var wd: WeaponData = load(path)
	if wd == null:
		return out
	var im: Dictionary = _imprint_of(path)
	if int(im["forge"]) < IMPRINT_MAX:
		var base: int = int(wd.base_power) + forge_bonus(path)
		out.append({"id": "forge", "family": wd.weapon_name, "name": "锋铸",
			"desc": "基础攻击 %d → %d" % [base, base + FORGE_STEP]})
	if _tune_count(path) < IMPRINT_MAX:
		var tgt: Dictionary = tune_target(path)
		if not tgt.is_empty():
			out.append({"id": "tune", "family": wd.weapon_name, "name": "调律",
				"desc": "「%s」权重 +1：%s" % [_sym_name(tgt["sym"]), "；".join(tgt["lines"])]})
	return out


# 调律目标：本武器符号中权重最高、且 +1 能真实改变带子格数者（无则为空字典）。
# 格数口径与 build_strips 相同（ReelPreview.diff_lines），不改变实际带子则不算有效。
func tune_target(path: String) -> Dictionary:
	var wd: WeaponData = load(path)
	if wd == null:
		return {}
	var syms: Array = []
	for sw in wd.symbols:
		if sw != null and sw.symbol != null:
			syms.append([float(sw.weight), sw.symbol.resource_path])
	syms.sort_custom(func(a, b): return a[0] > b[0])
	var before_tune: Dictionary = tune_map()
	for s in syms:
		var after_tune: Dictionary = before_tune.duplicate(true)
		var row: Dictionary = after_tune.get(path, {}).duplicate()
		row[s[1]] = int(row.get(s[1], 0)) + 1
		after_tune[path] = row
		var lines: Array = ReelPreview.diff_lines(_ctrl.selected_loadout, _ctrl.selected_loadout,
			_ctrl.selected_skills, _ctrl.selected_charms, _ctrl.room_element_mult,
			_ctrl._reward_system.run_symbol_bonus, _ctrl.deprived_level, _ctrl.pending_chaos,
			int(_ctrl.boss_trash), before_tune, after_tune)
		if not lines.is_empty():
			return {"sym": s[1], "lines": lines}
	return {}


# 选定铭印：写入运行时状态并消耗一次欠选。调律在选定时固定目标符号（之后不随其他变化漂移）。
func choose(path: String, id: String) -> bool:
	var im: Dictionary = _imprint_of(path)
	if id == "forge":
		if int(im["forge"]) >= IMPRINT_MAX:
			return false
		im["forge"] = int(im["forge"]) + 1
	elif id == "tune":
		if _tune_count(path) >= IMPRINT_MAX:
			return false
		var tgt: Dictionary = tune_target(path)
		if tgt.is_empty():
			return false
		var tune: Dictionary = im["tune"]
		tune[tgt["sym"]] = int(tune.get(tgt["sym"], 0)) + 1
	else:
		return false
	imprints[path] = im
	var idx := owed.find(path)
	if idx >= 0:
		owed.remove_at(idx)
	_ctrl.hud._log("⚒ 铭印「%s」→ %s" % ["锋铸" if id == "forge" else "调律", display_name(path)])
	return true


# 锋铸累计基础攻击加成（build_pool 读取，覆盖武器 base_power）。
func forge_bonus(path: String) -> int:
	return FORGE_STEP * int(_imprint_of(path)["forge"])


# 调律：武器路径 -> {符号路径: 额外权重}（build_pool 与 ReelPreview 共用同一份口径）。
func tune_map() -> Dictionary:
	var out := {}
	for path in imprints:
		var tune: Dictionary = imprints[path]["tune"]
		if not tune.is_empty():
			out[path] = tune.duplicate()
	return out


func tune_bonus(path: String, sym_path: String) -> float:
	return float(tune_map().get(path, {}).get(sym_path, 0))


func display_name(path: String) -> String:
	var wd: WeaponData = load(path)
	return wd.weapon_name if wd != null else path


func _tune_count(path: String) -> int:
	var n := 0
	for v in _imprint_of(path)["tune"].values():
		n += int(v)
	return n


func _weapon_settled(path: String) -> bool:
	var wd: WeaponData = load(path)
	if wd == null:
		return false
	for sw in wd.symbols:
		if sw != null and sw.symbol != null and _settled.has(sw.symbol.resource_path):
			return true
	return false


func _imprint_of(path: String) -> Dictionary:
	if not imprints.has(path):
		imprints[path] = {"forge": 0, "tune": {}}
	return imprints[path]


func _sym_name(sym_path: String) -> String:
	var s: SymbolData = load(sym_path)
	return s.label if s != null and s.label != "" else sym_path


func _next_threshold(lv: int) -> int:
	return int(R_THRESHOLDS.get(lv + 1, R_THRESHOLDS[4]))
