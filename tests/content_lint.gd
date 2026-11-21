extends SceneTree

# S6 内容静态校验（统一入口 · 补 smoke_lint / item_taxonomy_test 盲区）
# 运行：Godot --headless --fixed-fps 60 --path <项目> --script res://tests/content_lint.gd
# 分工：
#   smoke_lint        — L1 数量下限 / 武器元素-状态 / ItemData effect / 数学快照
#   item_taxonomy_test — L2 role/family_tags/source_tags/act/mechanism_summary 语义（场景模式）
#   content_lint(本)  — 图标路径、Symbol/Weapon/Skill/Reward 枚举、relic 命名、文案落点、anvil 来源存量
# ⚠ --script 模式禁止引用 DuelController（依赖 SaveSystem autoload）。

const DIRS := [
	"res://resources/weapon_templates/",
	"res://resources/charms/",
	"res://resources/skills/",
	"res://resources/consumables/",
	"res://resources/symbols/",
	"res://resources/rooms/",
	"res://resources/rewards/",
	"res://resources/patterns/",
]

const SYMBOL_KINDS := ["damage", "shield", "heal", "status", "special", "buff", "trash", "gold"]
const ELEMENTS := ["fire", "ice", "poison", "light", "dark", "none"]
const BUFF_EFFECTS := ["", "power", "shield", "regen", "damage_mult"]
# StatusSystem.STATUS_DEFS 的键（状态 id，非元素）
const STATUS_TYPES := ["", "burn", "frost", "poison", "frozen", "holy_burn", "shadow_blight"]
const RARITIES := ["common", "uncommon", "rare", "epic", "relic"]
const SOURCES := ["normal", "elite", "boss", "chest", "event", "shop", "anvil", "start"]
const ROLES := ["damage", "defense", "recovery", "control", "resource", "utility", "conversion"]

var _fails := 0
var _checks := 0
var _warnings := 0


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fails += 1
		print("FAIL  " + label)


func _warn(cond: bool, label: String) -> void:
	if not cond:
		_warnings += 1
		print("WARN  " + label)


func _initialize() -> void:
	seed(1)
	var all: Array[String] = []
	for d in DIRS:
		all.append_array(_all_tres(d))
	_check_icon_paths(all)
	_check_enums(all)
	_check_relic_naming(all)
	_check_text_hooks(all)
	_check_anvil_sources(all)
	print("CONTENT_LINT|RESULT checks=%d fails=%d warnings=%d" % [_checks, _fails, _warnings])
	quit(1 if _fails > 0 else 0)


func _all_tres(root: String) -> Array[String]:
	var out: Array[String] = []
	var stack: Array[String] = [root]
	while not stack.is_empty():
		var dpath: String = stack.pop_back()
		var dir := DirAccess.open(dpath)
		if dir == null:
			continue
		for f in dir.get_files():
			if f.ends_with(".tres"):
				out.append(dpath + "/" + f)
		for dn in dir.get_directories():
			stack.append(dpath + "/" + dn)
	return out


# ① 图标/资源路径：解析 .tres 的 ext_resource path，全部应存在
func _check_icon_paths(all: Array[String]) -> void:
	var checked := 0
	for fp in all:
		var f := FileAccess.open(fp, FileAccess.READ)
		if f == null:
			continue
		var text := f.get_as_text()
		f.close()
		var lines := text.split("\n")
		for line in lines:
			if not line.begins_with("[ext_resource"):
				continue
			var p := _extract_path(line)
			if p != "" and (p.begins_with("res://assets/") or p.begins_with("res://resources/")):
				_ok(ResourceLoader.exists(p), "资源路径存在 %s (在 %s)" % [p, fp.get_file()])
				checked += 1
	print("CONTENT_LINT|ICONS checked=%d" % checked)


func _extract_path(line: String) -> String:
	var i := line.find("path=\"")
	if i < 0:
		return ""
	var rest := line.substr(i + 6)
	var j := rest.find("\"")
	if j < 0:
		return ""
	return rest.substr(0, j)


# ② 枚举与必填字段（按脚本类型判断）
func _check_enums(all: Array[String]) -> void:
	for fp in all:
		var res = load(fp)
		if res == null:
			continue
		var resname: String = fp.get_file()
		if res is SymbolData:
			_ok(SYMBOL_KINDS.has(String(res.kind)), "SymbolData.kind 合法 %s (%s)" % [res.kind, resname])
			_ok(ELEMENTS.has(String(res.element)), "SymbolData.element 合法 %s (%s)" % [res.element, resname])
			_ok(STATUS_TYPES.has(String(res.status_type)),
				"SymbolData.status_type 合法 %s (%s)" % [res.status_type, resname])
			_ok(BUFF_EFFECTS.has(String(res.buff_effect)), "SymbolData.buff_effect 合法 %s (%s)" % [res.buff_effect, resname])
		elif res is WeaponData:
			_ok(int(res.archetype) >= 0 and int(res.archetype) <= 3, "WeaponData.archetype 合法 (%s)" % resname)
			_ok(int(res.weapon_type) >= 0 and int(res.weapon_type) <= 1, "WeaponData.weapon_type 合法 (%s)" % resname)
			_ok(ELEMENTS.has(String(res.reel_element)), "WeaponData.reel_element 合法 %s (%s)" % [res.reel_element, resname])
			_ok(ELEMENTS.has(String(res.element)), "WeaponData.element 合法 %s (%s)" % [res.element, resname])
			_ok(String(res.role) == "" or ROLES.has(String(res.role)), "WeaponData.role 合法 %s (%s)" % [res.role, resname])
		elif res is SkillData:
			_ok(res.symbol != null, "SkillData.symbol 非空 (%s)" % resname)
			_ok(float(res.weight) > 0.0, "SkillData.weight > 0 (%s)" % resname)
		elif res is RewardData:
			_ok(String(res.id) != "" and String(res.label) != "", "RewardData id/label 非空 (%s)" % resname)
			_ok(["common", "uncommon", "rare"].has(String(res.rarity)), "RewardData.rarity 合法 %s (%s)" % [res.rarity, resname])


# ③ relic 命名一致性：rarity=relic 的路径应含 _relic（loot_pool 靠文件名判信物）
func _check_relic_naming(all: Array[String]) -> void:
	for fp in all:
		var res = load(fp)
		if res == null or not ("rarity" in res):
			continue
		if String(res.rarity) == "relic":
			_ok(fp.contains("_relic"), "relic 文件名含 _relic (%s)" % fp.get_file())


# ④ 文案承诺无代码落点检测（报告性，不判失败）
func _check_text_hooks(all: Array[String]) -> void:
	var no_hook := 0
	for fp in all:
		var f := FileAccess.open(fp, FileAccess.READ)
		if f == null: continue
		var text := f.get_as_text()
		f.close()
		# "连锁放大" 无 combat hook；"处决线" 无字段（当前若出现应提示）
		if text.contains("连锁放大") or text.contains("处决线"):
			no_hook += 1
			_warn(false, "文案可能无代码落点 %s（连锁放大/处决线）" % fp.get_file())
	print("CONTENT_LINT|TEXT_NO_HOOK count=%d" % no_hook)


# ⑤ anvil 来源存量（S5 删除铁砧后无生产路径，历史标签待清理；报告不判失败）
func _check_anvil_sources(all: Array[String]) -> void:
	var with_anvil := 0
	var anvil_only := 0
	for fp in all:
		var f := FileAccess.open(fp, FileAccess.READ)
		if f == null: continue
		var text := f.get_as_text()
		f.close()
		if not text.contains("source_tags = Array[String]([") or not text.contains("\"anvil\""):
			continue
		with_anvil += 1
		# 提取 source_tags 行判断是否唯一 anvil
		for line in text.split("\n"):
			if line.begins_with("source_tags") and line.contains("\"anvil\""):
				var others := line.replace("\"anvil\"", "")
				if not (others.contains("\"normal\"") or others.contains("\"elite\"") or
					others.contains("\"boss\"") or others.contains("\"shop\"") or
					others.contains("\"chest\"") or others.contains("\"start\"") or others.contains("\"event\"")):
					anvil_only += 1
	_ok(anvil_only == 0, "无资源以 anvil 为唯一来源（%d）" % anvil_only)
	print("CONTENT_LINT|ANVIL_TAGS legacy=%d anvil_only=%d (S5后无生产路径,待清理)" % [with_anvil, anvil_only])
