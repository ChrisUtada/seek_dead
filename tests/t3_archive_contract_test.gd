extends Node

# ============================================================================
# T3 阶段 1 归档契约测试（2026-11-27）
# 运行：Godot --headless --fixed-fps 60 --path <项目> res://tests/t3_archive_contract_test.tscn
# 覆盖：
#   A-1 90 把武器扫描：archived==false 恰好 30 把、==true 恰好 60 把，且 30 把 ID 与 C1 一致
#   A-2 六个状态技能 archived==true（blight/chill/ember/holy_sear/ignite/shadow_curse）
#   A-3 starter 集合 == battle_axe / iron_sword / fire_sword / ice_staff；
#       iron_sword 带 start 标签、dagger 不带
#   A-4 demo 白名单 10 条 ⊆ 正式 30 把，且 starter 在池内
#   A-5 获取路径采样 500 次（普通/精英/Boss/宝箱/商店）不含归档武器
#   A-6 商店阶梯采样 100 次不含归档武器
#   A-7 新获取/换装候选跳过归档武器（meta / 本局仓库注入归档样本）
#   A-8 战斗建池不过滤归档：已装备归档武器仍产出其符号（老档兼容）
#   A-9 携带归档技能时符号池不含其状态符号
#   A-10 图鉴详情标注「已归档」，不隐藏
#   A-11 归档武器不新增熟练成长（已有熟练仍可展示）
# ============================================================================

const EMBER_SWORD := "res://resources/weapon_templates/ember_sword.tres"
const FIRE_SWORD := "res://resources/weapon_templates/fire_sword.tres"
const DAGGER := "res://resources/weapon_templates/dagger.tres"
const IRON_SWORD := "res://resources/weapon_templates/iron_sword.tres"
const BATTLE_AXE := "res://resources/weapon_templates/battle_axe.tres"
const ICE_STAFF := "res://resources/weapon_templates/ice_staff.tres"
const EMBER_SKILL := "res://resources/skills/ember.tres"
const EMBER_SYM := "res://resources/symbols/ember.tres"
const STATUS_SKILLS := [
	"res://resources/skills/blight.tres", "res://resources/skills/chill.tres",
	"res://resources/skills/ember.tres", "res://resources/skills/holy_sear.tres",
	"res://resources/skills/ignite.tres", "res://resources/skills/shadow_curse.tres",
]
const STARTER := [BATTLE_AXE, IRON_SWORD, FIRE_SWORD, ICE_STAFF]
# C1 冻结表「保留」列（30 把，按 ID 字典序无关；此处按文件 basename 比较）。
const KEEP := [
	"absolute_zero", "abyss_staff", "acolyte_blade", "armor_pierce_crossbow", "battle_axe",
	"cinder_saber", "dawn_bow", "dawn_staff", "eclipse_blade", "executioner_axe",
	"fire_sword", "flame_staff", "flintlock", "frost_dagger", "glacier_greatsword",
	"gloom_saber", "holy_sword", "ice_gun", "ice_staff", "inferno_axe",
	"iron_sword", "mace", "miasma_staff", "night_scythe", "plague_reaper",
	"poison_dagger", "shadow_dagger", "sunforged_blade", "venom_queen", "venom_sickle",
]

var _fails := 0
var _checks := 0
var _duel: DuelController


func _ready() -> void:
	await get_tree().process_frame
	SaveSystem.reset_lobby_data()
	_duel = (load("res://scenes/duel/duel.tscn") as PackedScene).instantiate() as DuelController
	add_child(_duel)
	await get_tree().process_frame
	await get_tree().process_frame
	_duel.demo_config.enabled = false
	_duel._confirm_loadout()
	_duel.reel_system._timer.stop()

	_test_a1_weapon_counts()
	_test_a2_status_skills()
	_test_a3_starter()
	_test_a4_demo_whitelist()
	_test_a5_acquisition_sampling()
	_test_a6_shop_sampling()
	_test_a7_acquire_defs()
	_test_a8_battle_pool_compat()
	_test_a9_archived_skill_pool()
	_test_a10_codex_label()
	_test_a11_mastery()

	print("T3ARCHIVE|RESULT %s (checks=%d fails=%d)" % [
		"PASS" if _fails == 0 else "FAIL", _checks, _fails])
	SaveSystem.reset_lobby_data()
	get_tree().quit(1 if _fails > 0 else 0)


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("PASS  " + msg)
	else:
		_fails += 1
		print("FAIL  " + msg)


func _archived(res: Resource) -> bool:
	if res == null:
		return false
	return res.get("archived") == true


func _scan_weapons() -> Array[String]:
	var out: Array[String] = []
	for p in ResourceScan.scan_paths("res://resources/weapon_templates/"):
		out.append(String(p))
	out.sort()
	return out


func _test_a1_weapon_counts() -> void:
	var paths := _scan_weapons()
	var keep: Array[String] = []
	var arch: Array[String] = []
	for p in paths:
		if _archived(load(p)):
			arch.append(p)
		else:
			keep.append(p)
	_check(paths.size() == 90, "A-1 武器资源总数 90（实测 %d）" % paths.size())
	_check(keep.size() == 30, "A-1 archived==false 恰好 30 把（实测 %d）" % keep.size())
	_check(arch.size() == 60, "A-1 archived==true 恰好 60 把（实测 %d）" % arch.size())
	var keep_ids: Array[String] = []
	for p in keep:
		keep_ids.append(p.get_file().get_basename())
	keep_ids.sort()
	var expect := KEEP.duplicate()
	expect.sort()
	_check(keep_ids == expect, "A-1 保留 30 把 ID 与 C1 完全一致（差异 %s）" % _diff(keep_ids, expect))
	var arch_ids := {}
	for p in arch:
		arch_ids[p.get_file().get_basename()] = true
	for k in KEEP:
		if arch_ids.has(k):
			_check(false, "A-1 保留武器不应归档：%s" % k)
			return
	_check(true, "A-1 60 把归档与 30 把保留互不重叠")


func _diff(a: Array, b: Array) -> String:
	var only_a: Array = []
	for x in a:
		if not b.has(x):
			only_a.append(x)
	var only_b: Array = []
	for x in b:
		if not a.has(x):
			only_b.append(x)
	return "多 %s / 缺 %s" % [str(only_a), str(only_b)]


func _test_a2_status_skills() -> void:
	var bad: Array[String] = []
	for p in STATUS_SKILLS:
		var sd = load(String(p))
		if sd == null or not _archived(sd):
			bad.append(String(p).get_file())
	_check(bad.is_empty(), "A-2 六个状态技能 archived=true（未归档 %s）" % str(bad))


func _test_a3_starter() -> void:
	var starters: Array = _duel._meta_store._starter_weapons()
	var got: Array[String] = []
	for p in starters:
		got.append(String(p))
	got.sort()
	var want := STARTER.duplicate()
	want.sort()
	_check(got == want, "A-3 starter 集合 = 战斧/铁剑/火焰剑/霜晶法杖（实测 %s）" % str(got))
	var dagger: WeaponData = load(DAGGER)
	var iron: WeaponData = load(IRON_SWORD)
	_check(dagger != null and not (dagger.source_tags as Array).has("start"),
		"A-3 dagger 不再带 start 标签（%s）" % str(dagger.source_tags if dagger != null else []))
	_check(iron != null and (iron.source_tags as Array).has("start"),
		"A-3 iron_sword 带 start 标签（%s）" % str(iron.source_tags if iron != null else []))


func _test_a4_demo_whitelist() -> void:
	var cfg = _duel.demo_config
	var pool: Array = cfg.weapon_pool
	_check(pool.size() == 10, "A-4 demo 武器白名单 10 条（实测 %d）" % pool.size())
	var keep_ids := {}
	for k in KEEP:
		keep_ids[String(k)] = true
	var bad: Array[String] = []
	for p in pool:
		var id := String(p).get_file().get_basename()
		if not keep_ids.has(id):
			bad.append(id)
	_check(bad.is_empty(), "A-4 demo 白名单 ⊆ 正式 30 把（越界 %s）" % str(bad))
	for p in STARTER:
		_check(pool.has(String(p)), "A-4 starter 在白名单内：%s" % String(p).get_file())


# 500 次获取采样：普通/精英/Boss/宝箱/商店 × 三幕。
# 归档集合按 C1 冻结表判定（扫描结果 - 保留 30 把），不依赖资源是否已写入 archived，
# 这样改前（未归档）也会命中归档样本并报红。
func _test_a5_acquisition_sampling() -> void:
	var arch_ids := _expected_archive_ids()
	var sources := ["normal", "elite", "boss", "chest", "shop"]
	var hits: Array[String] = []
	var rounds := 500
	for i in rounds:
		var src: String = String(sources[i % sources.size()])
		var act: int = 1 + (i % 3)
		var res: Dictionary = _duel._reward_system._loot.roll(src, act, {"category": "weapon"})
		var p := String(res.get("path", ""))
		if p != "" and arch_ids.has(p) and not hits.has(p.get_file().get_basename()):
			hits.append(p.get_file().get_basename())
	_check(hits.is_empty(), "A-5 获取路径采样 %d 次无归档武器（命中 %s）" % [rounds, str(hits)])


# 商店阶梯 100 次采样（roll_shop_ladder 内部走同一候选池）。
func _test_a6_shop_sampling() -> void:
	var arch_ids := _expected_archive_ids()
	var hits: Array[String] = []
	for i in 100:
		var act: int = 1 + (i % 3)
		var slots: Array = _duel._reward_system.roll_shop_ladder(act, {})
		for s in slots:
			var p := String((s as Dictionary).get("path", ""))
			if p != "" and arch_ids.has(p) and not hits.has(p.get_file().get_basename()):
				hits.append(p.get_file().get_basename())
	_check(hits.is_empty(), "A-6 商店阶梯采样 100 次无归档武器（命中 %s）" % str(hits))


func _expected_archive_ids() -> Dictionary:
	var keep := {}
	for k in KEEP:
		keep[String(k)] = true
	var out := {}
	for p in _scan_weapons():
		var id := p.get_file().get_basename()
		if not keep.has(id):
			out[p] = true
	return out


# 旧档拥有归档武器时，新获取/换装候选必须跳过。
func _test_a7_acquire_defs() -> void:
	var old_owned: Array = _duel.meta.get("owned_weapons", []).duplicate()
	var old_inv: Array = _duel.run_weapon_inventory.duplicate()
	var old_loadout: Array = _duel.selected_loadout.duplicate()
	_duel.meta["owned_weapons"] = [EMBER_SWORD]
	_duel.selected_loadout.assign([FIRE_SWORD])
	_duel.run_weapon_inventory.clear()
	var defs: Array = _duel._reward_system._make_weapon_acquire_defs()
	_check(defs.is_empty(), "A-7 局外收藏含归档武器时 acquire 候选为空（实测 %d）" % defs.size())
	var defs2: Array = _duel._reward_system._make_weapon_defs()
	_check(defs2.is_empty(), "A-7 旧换装路径同样跳过归档武器（实测 %d）" % defs2.size())
	_duel.run_weapon_inventory.append(EMBER_SWORD)
	var defs3: Array = _duel._reward_system._make_weapon_swap_defs()
	_check(defs3.is_empty(), "A-7 本局仓库换装跳过归档武器（实测 %d）" % defs3.size())
	_duel.meta["owned_weapons"] = old_owned
	_duel.run_weapon_inventory.assign(old_inv)
	_duel.selected_loadout.assign(old_loadout)


# 老档兼容：已装备归档武器仍参与战斗建池。
func _test_a8_battle_pool_compat() -> void:
	var old_loadout: Array = _duel.selected_loadout.duplicate()
	var old_skills: Array = _duel.selected_skills.duplicate()
	_duel.selected_loadout.assign([EMBER_SWORD, FIRE_SWORD])
	_duel.selected_skills.clear()
	_duel._build_pool(_duel.selected_loadout)
	var has_ember := false
	for it in _duel.pool_items:
		for s in (it as Dictionary)["syms"]:
			if s.size() > 3 and String(s[3]) == "ember_sword":
				has_ember = true
	_check(has_ember, "A-8 战斗建池仍含已装备归档武器的符号（老档兼容）")
	_duel.reel_system.build_strips()
	var strips: Array = _duel.reel_system.reel_strips
	_check(strips.size() == 3, "A-8 已装备归档武器可正常生成三条转轮带（实测 %d）" % strips.size())
	_duel.selected_loadout.assign(old_loadout)
	_duel.selected_skills.assign(old_skills)
	_duel._build_pool(_duel.selected_loadout)


# 归档技能：符号池不得含其状态符号。
func _test_a9_archived_skill_pool() -> void:
	var old_loadout: Array = _duel.selected_loadout.duplicate()
	var old_skills: Array = _duel.selected_skills.duplicate()
	_duel.selected_skills.assign([EMBER_SKILL])
	_duel._build_pool(_duel.selected_loadout)
	var found := false
	for it in _duel.pool_items:
		for s in (it as Dictionary)["syms"]:
			var sym = s[0]
			if sym != null and String(sym.resource_path) == EMBER_SYM:
				found = true
	_check(not found, "A-9 携带归档技能时符号池不含该技能符号（ember）")
	_duel.reel_system.build_strips()
	var strip_has := false
	for row in _duel.reel_system.reel_strips:
		for c in (row as Array):
			var sym = (c as Array)[0] if c is Array and (c as Array).size() > 0 else null
			if sym != null and String(sym.resource_path) == EMBER_SYM:
				strip_has = true
	_check(not strip_has, "A-9 归档技能符号不进入转轮带")
	_duel.selected_loadout.assign(old_loadout)
	_duel.selected_skills.assign(old_skills)
	_duel._build_pool(_duel.selected_loadout)


# 图鉴：归档武器/技能标注「已归档」，仍返回详情（不隐藏）。
func _test_a10_codex_label() -> void:
	var weapon_lines: Array[String] = _duel._codex.detail_lines(EMBER_SWORD)
	var weapon_joined := "\n".join(weapon_lines)
	_check(weapon_joined.contains("已归档"), "A-10 归档武器图鉴标注「已归档」（%s）" % weapon_joined.replace("\n", " / "))
	_check(not weapon_lines.is_empty(), "A-10 归档武器图鉴不隐藏详情（%d 行）" % weapon_lines.size())
	var skill_lines: Array[String] = _duel._codex.detail_lines(EMBER_SKILL)
	var skill_joined := "\n".join(skill_lines)
	_check(skill_joined.contains("已归档"), "A-10 归档技能图鉴标注「已归档」（%s）" % skill_joined.replace("\n", " / "))
	_check(not skill_lines.is_empty(), "A-10 归档技能图鉴不隐藏详情（%d 行）" % skill_lines.size())


# 归档武器不再增长熟练；已有熟练仍可读。
func _test_a11_mastery() -> void:
	var before: int = int(_duel.mastery.mastery.get(EMBER_SWORD, 0))
	var gained: int = _duel.mastery.grant_points(EMBER_SWORD, 5, "契约测试")
	var after: int = int(_duel.mastery.mastery.get(EMBER_SWORD, 0))
	_check(gained == 0 and after == before,
		"A-11 归档武器不新增熟练（返回 %d，%d → %d）" % [gained, before, after])
	_duel.mastery.mastery[EMBER_SWORD] = 7
	_check(int(_duel.mastery.mastery.get(EMBER_SWORD, 0)) == 7,
		"A-11 已有熟练仍可展示（=7）")
	_duel.mastery.mastery.erase(EMBER_SWORD)
