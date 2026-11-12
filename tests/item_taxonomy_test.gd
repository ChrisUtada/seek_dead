extends Node

# ============================================================================
# 四级品质战利品 · Step 1 · 品质定义与构筑家族标签 · headless 回归
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/item_taxonomy_test.tscn
#
# 覆盖：
# ① 200 项可掉落内容全部有合法家族 / 用途 / 来源 / 幕次 / 机制摘要 / 同机制分组；
# ② 每项至少有一个真实获取来源，BOSS 信物只从对应 BOSS 掉落；
# ③ 稀有/传说物品必须有机制差异（武器：状态/特殊/三连；技能：缓冲/恢复/护盾/三连；
#    护符：代价或条件触发；消耗品：多用途或机制效果），不能只有基础数值；
# ④ 10 个首版家族都有可用的基础（common）入口；
# ⑤ BOSS 主题武器池与开局收藏的幕次/来源口径一致。
# ============================================================================

const WEAPON_DIR := "res://resources/weapon_templates"
const CHARM_DIR := "res://resources/charms"
const CONSUMABLE_DIR := "res://resources/consumables"
const SKILL_DIR := "res://resources/skills"
const ROOM_DIR := "res://resources/rooms"

const EXPECT_COUNTS := {"weapon": 90, "charm": 45, "consumable": 25, "skill": 40}

const CONDITIONAL_CHARM_EFFECTS: Array[String] = [
	"armor_pierce", "element_boost", "status_boost", "first_hit",
	"thorns", "dot_amp", "free_reroll", "charge_start", "dot_reduce",
]
const MECHANIC_CONSUMABLE_EFFECTS: Array[String] = [
	"reroll", "assault", "cleanse", "purify", "element", "armor_shred",
]

const STARTER_PATHS: Array[String] = [
	"res://resources/weapon_templates/dagger.tres",
	"res://resources/weapon_templates/fire_sword.tres",
	"res://resources/weapon_templates/battle_axe.tres",
	"res://resources/weapon_templates/ice_staff.tres",
	"res://resources/skills/haste.tres",
	"res://resources/skills/magic_bolt.tres",
	"res://resources/skills/rage.tres",
	"res://resources/skills/recovery.tres",
	"res://resources/charms/guard_charm.tres",
	"res://resources/charms/pilgrim_ward.tres",
	"res://resources/charms/regen_charm.tres",
	"res://resources/charms/resist_charm.tres",
]

var _checks := 0
var _fails := 0
var _items: Array[Dictionary] = []
var _relic_act := {}       # path -> act
var _relic_boss := {}      # path -> boss name
var _boss_weapons := {}    # path -> true


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().process_frame
	_scan_rooms()
	_scan_items()

	var by_kind := {"weapon": 0, "charm": 0, "consumable": 0, "skill": 0}
	for it in _items:
		by_kind[it["kind"]] = int(by_kind[it["kind"]]) + 1
	for kind in EXPECT_COUNTS:
		_check(int(by_kind[kind]) == int(EXPECT_COUNTS[kind]),
			"%s 数量 %d（实测 %d）" % [kind, int(EXPECT_COUNTS[kind]), int(by_kind[kind])])

	for it in _items:
		_check_item(it)

	_check_family_entries()
	_check_starter_sources()
	_check_boss_sources()

	print("---")
	print("PASSED %d / FAILED %d" % [_checks - _fails, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


# ---------------------------------------------------------------------------
# 扫描
# ---------------------------------------------------------------------------

func _scan_items() -> void:
	_scan_dir(WEAPON_DIR, "weapon")
	_scan_dir(CHARM_DIR, "charm")
	_scan_dir(CONSUMABLE_DIR, "consumable")
	_scan_dir(SKILL_DIR, "skill")


func _scan_dir(dir_path: String, kind: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_check(false, "目录可打开 " + dir_path)
		return
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var path := dir_path + "/" + f
		var res: Resource = load(path)
		_check(res != null, "资源可加载 " + path)
		if res != null:
			_items.append({"kind": kind, "path": path, "res": res})


func _scan_rooms() -> void:
	var dir := DirAccess.open(ROOM_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".tres"):
			continue
		var r: RoomData = load(ROOM_DIR + "/" + f)
		if r == null:
			continue
		if String(r.boss_relic_path) != "":
			_relic_act[String(r.boss_relic_path)] = int(r.act)
			_relic_boss[String(r.boss_relic_path)] = String(r.name)
		for wp in r.boss_reward_weapons:
			_boss_weapons[String(wp)] = true


# ---------------------------------------------------------------------------
# 单项检查
# ---------------------------------------------------------------------------

func _check_item(entry: Dictionary) -> void:
	var kind: String = entry["kind"]
	var path: String = entry["path"]
	var res: Resource = entry["res"]
	var label := path.get_file().get_basename()
	var rarity := String(res.get("rarity"))
	_check(ItemTaxonomy.is_valid_rarity(rarity), "%s 品质合法（%s）" % [label, rarity])

	var families: Array = res.get("family_tags")
	_check(not families.is_empty(), "%s 至少一个家族标签" % label)
	_check(_unique(families), "%s 家族标签无重复" % label)
	for tag in families:
		_check(ItemTaxonomy.is_valid_family(String(tag)), "%s 家族合法（%s）" % [label, String(tag)])

	var role := String(res.get("role"))
	_check(ItemTaxonomy.is_valid_role(role), "%s 用途合法（%s）" % [label, role])

	var sources: Array = res.get("source_tags")
	_check(not sources.is_empty(), "%s 至少一个合法来源" % label)
	_check(_unique(sources), "%s 来源标签无重复" % label)
	for src in sources:
		_check(ItemTaxonomy.is_valid_source(String(src)), "%s 来源合法（%s）" % [label, String(src)])

	var amin := int(res.get("act_min"))
	var amax := int(res.get("act_max"))
	_check(amin >= 1 and amin <= 3, "%s 幕次下限合法（%d）" % [label, amin])
	_check(amax >= 1 and amax <= 3, "%s 幕次上限合法（%d）" % [label, amax])
	_check(amin <= amax, "%s 幕次区间有序（%d–%d）" % [label, amin, amax])
	if rarity == "common":
		_check(amin == 1, "%s 基础品质从第 1 幕起可获取" % label)

	var summary := String(res.get("mechanism_summary"))
	_check(summary.length() >= 12, "%s 机制摘要非占位（%d 字）" % [label, summary.length()])
	_check(not summary.contains("TODO") and not summary.contains("待补"), "%s 机制摘要无占位词" % label)
	_check(_summary_has_trigger(summary), "%s 机制摘要写明触发/条件/限制" % label)

	_check(String(res.get("unique_group")) != "", "%s 有同机制分组" % label)

	var is_relic := _relic_act.has(path)
	if is_relic:
		_check(_same_sources(sources, ["boss"]), "%s BOSS 信物只从 BOSS 掉落" % label)
		_check(amin == int(_relic_act[path]) and amax == int(_relic_act[path]),
			"%s 信物幕次匹配对应 BOSS（%d）" % [label, int(_relic_act[path])])
	else:
		_check(_has_any_source(sources, ["normal", "elite", "shop", "anvil", "start"]),
			"%s 有非 BOSS 获取通道" % label)
		if kind == "weapon":
			_check(_has_any_source(sources, ["shop", "anvil"]), "%s 武器可由商店/铁砧获得" % label)
			_check(_boss_weapons.has(path) == _has_any_source(sources, ["boss"]),
				"%s BOSS 池来源标记与房间配置一致" % label)
		elif kind == "skill":
			_check(_has_any_source(sources, ["shop", "anvil"]), "%s 技能可由商店/铁砧获得" % label)
		elif kind == "charm":
			_check(_has_any_source(sources, ["elite", "shop", "anvil"]), "%s 护符有精英/商店/铁砧来源" % label)
		else:
			_check(_has_any_source(sources, ["normal", "shop"]), "%s 消耗品有战斗/商店来源" % label)

	# 高阶物品必须含机制差异，不能只有基础数值。
	if (rarity == "rare" or rarity == "epic") and not is_relic:
		match kind:
			"weapon":
				_check(_weapon_has_mechanic(res as WeaponData),
					"%s 高阶武器有状态/特殊/三连机制" % label)
			"skill":
				_check(_skill_has_mechanic(res as SkillData),
					"%s 高阶技能有缓冲/恢复/护盾/三连机制" % label)
			"charm":
				_check(_charm_has_mechanic(res as ItemData),
					"%s 高阶护符有代价或条件触发" % label)
			"consumable":
				_check(_consumable_has_mechanic(res as ItemData),
					"%s 高阶消耗品有多用途或机制效果" % label)


# ---------------------------------------------------------------------------
# 汇总检查
# ---------------------------------------------------------------------------

func _check_family_entries() -> void:
	for family in ItemTaxonomy.FAMILIES:
		var found := ""
		for it in _items:
			var res: Resource = it["res"]
			if String(res.get("rarity")) != "common":
				continue
			if (res.get("family_tags") as Array).has(family):
				found = it["path"].get_file().get_basename()
				break
		_check(found != "", "家族「%s」有基础入口（%s）" % [family, found])


func _check_starter_sources() -> void:
	for path in STARTER_PATHS:
		var res: Resource = load(path)
		_check(res != null, "开局收藏可加载 " + path)
		if res == null:
			continue
		_check((res.get("source_tags") as Array).has("start"), "%s 标记开局来源" % path.get_file())
		_check(int(res.get("act_min")) == 1, "%s 开局件第 1 幕可用" % path.get_file())


func _check_boss_sources() -> void:
	for path in _relic_act:
		var res: Resource = load(path)
		_check(res != null, "BOSS 信物可加载 " + path)
		if res != null:
			_check(String(res.get("mechanism_summary")).contains("BOSS 信物"),
				"%s 摘要标明 BOSS 信物来源" % path.get_file())
	for path in _boss_weapons:
		var res: Resource = load(path)
		if res == null:
			_check(false, "BOSS 池武器可加载 " + path)
			continue
		_check((res.get("source_tags") as Array).has("boss"), "%s BOSS 池武器标记 boss 来源" % path.get_file())
		_check(int(res.get("act_min")) == 1, "%s BOSS 池武器第 1 幕可掉落" % path.get_file())


# ---------------------------------------------------------------------------
# 机制差异
# ---------------------------------------------------------------------------

func _weapon_has_mechanic(w: WeaponData) -> bool:
	if w == null:
		return false
	if w.triple_pierce:
		return true
	for sw in w.symbols:
		if sw == null or sw.symbol == null:
			continue
		if String(sw.symbol.kind) in ["status", "special"]:
			return true
	return false


func _skill_has_mechanic(s: SkillData) -> bool:
	if s == null or s.symbol == null:
		return false
	if s.triple_pierce:
		return true
	return String(s.symbol.kind) in ["buff", "heal", "shield", "status"]


func _charm_has_mechanic(c: ItemData) -> bool:
	if c == null:
		return false
	if String(c.downside_effect) != "":
		return true
	return CONDITIONAL_CHARM_EFFECTS.has(String(c.effect))


func _consumable_has_mechanic(c: ItemData) -> bool:
	if c == null:
		return false
	if int(c.charges) >= 2:
		return true
	return MECHANIC_CONSUMABLE_EFFECTS.has(String(c.effect))


# ---------------------------------------------------------------------------
# 工具
# ---------------------------------------------------------------------------

func _summary_has_trigger(s: String) -> bool:
	for kw in ["触发", "落线", "命中", "三连", "挂", "代价", "主动使用", "被动常驻", "BOSS 信物"]:
		if s.contains(kw):
			return true
	return false


func _unique(arr: Array) -> bool:
	var seen := {}
	for v in arr:
		if seen.has(v):
			return false
		seen[v] = true
	return true


func _has_any_source(sources: Array, wanted: Array) -> bool:
	for s in wanted:
		if sources.has(s):
			return true
	return false


func _same_sources(sources: Array, wanted: Array) -> bool:
	if sources.size() != wanted.size():
		return false
	for s in wanted:
		if not sources.has(s):
			return false
	return true


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)
