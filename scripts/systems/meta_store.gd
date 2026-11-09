class_name MetaStore
extends RefCounted

# M5 元进度（铁砧锻造 + 存档持久化）——从 duel_controller.gd 抽出的纯 IO 子系统。
#
# 由 controller 在 _ready 处实例化并注入：MetaStore.new(ctrl, ctrl.meta)。
# 约定（与 docs/[已完成]duel_controller拆分方案B.md 步骤1一致）：
# - meta 是 controller.meta 字典的引用，本子系统直接改其键后经 save_meta() 落盘；
#   不持有 meta 所有权（避免"只读快照不可写回"类 bug）。
# - 跨系统联动（授予后刷新 UI 等）留在 controller 编排层，本子系统不互调其他子系统。
# - ctrl 标类型 DuelController（已加 class_name），成员访问获得编译期检查。

var _ctrl: DuelController          # DuelController 实例（类型标注，编译期检查）
var meta: Dictionary = {}   # controller.meta 引用（注入，直接改键后 save_meta 落盘）

func _init(ctrl: DuelController, m: Dictionary) -> void:
	_ctrl = ctrl
	meta = m


# ---------------------------------------------------------------------------
# 存档读写 + 拥有池种子/自愈 + 金币授予
# ---------------------------------------------------------------------------

func load_meta() -> void:
	var defaults := {"anvil_points": 0, "owned_weapons": [], "owned_charms": [], "owned_consumables": [], "owned_skills": [], "anvil_pity": 0, "collection_milestones": [], "item_sources": {}, "career": {"unlocked": [], "bosses": []}, "codex": {}, "forge_styles": {}}
	var lb = SaveSystem.load_lobby_data()
	var had_save := false
	var parsed: Dictionary = {}
	if lb.has(_ctrl.ANVIL_SAVE_KEY) and lb[_ctrl.ANVIL_SAVE_KEY] is Dictionary:
		had_save = true
		parsed = lb[_ctrl.ANVIL_SAVE_KEY]
		for k in defaults.keys():
			if parsed.has(k):
				meta[k] = parsed[k]
	# G7-C 迁移：老档（有存档但无 owned_skills）只授予 G7-C 之前已有的 17 件技能，
	# 不把新增的 23 件直接送掉；也不回收老档已能用的内容。
	# 用固定清单而非目录扫描，避免以后新增技能被老档迁移一次性送完。
	if had_save and not parsed.has("owned_skills"):
		meta["owned_skills"] = _existing_paths(LEGACY_SKILLS)
	_ctrl.hud._log("铁砧元进度已载入：点数 %d" % meta["anvil_points"])


func save_meta() -> void:
	var lb = SaveSystem.load_lobby_data()
	if lb is Dictionary:
		lb[_ctrl.ANVIL_SAVE_KEY] = meta
	else:
		lb = {_ctrl.ANVIL_SAVE_KEY: meta}
	SaveSystem.save_lobby_data(lb)
	SaveSystem.flush_lobby_data()   # 关键节点立即落盘，避免丢失


# M1-03 新档初始收藏（M0-02 已确认）：4 把初始武器 + 4 个基础护符 + 全部基础消耗品。
# 目的：新档保留真实未解锁内容，铁砧/图鉴有成长空间（旧行为播种全池 → 图鉴一步到 76%，里程碑集中补发）。
const STARTER_WEAPONS: Array[String] = [
	"res://resources/weapon_templates/dagger.tres",
	"res://resources/weapon_templates/fire_sword.tres",
	"res://resources/weapon_templates/battle_axe.tres",
	"res://resources/weapon_templates/ice_staff.tres",
]
const STARTER_CHARM_COUNT := 4
# M6-C4：新档护符只给「纯增益的防御向 common」——混合/诅咒护符带 downside，不能作为开局默认。
const STARTER_CHARM_DEFENSE_EFFECTS: Array[String] = ["shield", "room_shield", "heal", "interference_resist"]
# G7-C：新档只给 4 个基础技能（原技能池最早的 4 件），其余技能靠铁砧/商店收集。
const STARTER_SKILLS: Array[String] = [
	"res://resources/skills/haste.tres",
	"res://resources/skills/magic_bolt.tres",
	"res://resources/skills/rage.tres",
	"res://resources/skills/recovery.tres",
]
# G7-C 之前的 17 件技能：老档迁移只授予这些，不把 G7-C 新增的 23 件直接送掉。
const LEGACY_SKILLS: Array[String] = [
	"res://resources/skills/atonement_light.tres",
	"res://resources/skills/atonement_mark.tres",
	"res://resources/skills/aura_of_order.tres",
	"res://resources/skills/calm.tres",
	"res://resources/skills/ember.tres",
	"res://resources/skills/fire_breath.tres",
	"res://resources/skills/flame_mark.tres",
	"res://resources/skills/focus.tres",
	"res://resources/skills/haste.tres",
	"res://resources/skills/holy_verdict.tres",
	"res://resources/skills/magic_bolt.tres",
	"res://resources/skills/nightmare_gaze.tres",
	"res://resources/skills/nightmare_veil.tres",
	"res://resources/skills/rage.tres",
	"res://resources/skills/recovery.tres",
	"res://resources/skills/shadow_regen.tres",
	"res://resources/skills/war_banner.tres",
]

func seed_default_owned() -> void:
	# 迁移口径：只「补足」基础子集，从不删除已有收藏——老存档的全池收藏原样保留（不回收已获得内容）。
	_ensure_owned("owned_weapons", _starter_weapons())
	_ensure_owned("owned_charms", _starter_charms())
	_ensure_owned("owned_consumables", _all_active_items())
	_ensure_owned("owned_skills", _starter_skills())
	self.save_meta()


func _starter_skills() -> Array:
	return _existing_paths(STARTER_SKILLS)


func _existing_paths(paths: Array) -> Array:
	var out := []
	for p in paths:
		if ResourceLoader.exists(String(p)):
			out.append(String(p))
	return out


func _ensure_owned(key: String, paths: Array) -> void:
	if not meta.has(key):
		meta[key] = []
	for p in paths:
		if not meta[key].has(p):
			meta[key].append(p)


func _starter_weapons() -> Array:
	var out := []
	for p in STARTER_WEAPONS:
		if ResourceLoader.exists(p):
			out.append(p)
	return out


# 初始护符（M6-C4 修订）：非 BOSS 信物、无负面、common 且属于防御向家族，按路径稳定排序取前 N。
# 目的：新档拿到一套「纯增益基础防御」，而不是排序靠前的混合/诅咒护符。
# 不足 N 时依次回退：无负面 common → 全池（仍排除信物）。
func _starter_charms() -> Array:
	var pool := []
	for p in _ctrl.ITEM_POOL:
		var d = load(p)
		if d is ItemData and d.category == "passive" and not _is_boss_relic(d, p):
			pool.append(p)
	pool.sort()
	var defense := pool.filter(func(p):
		var d = load(p)
		var pure_common: bool = String(d.get("rarity")) == "common" and String(d.get("downside_effect")) == ""
		return pure_common and STARTER_CHARM_DEFENSE_EFFECTS.has(String(d.get("effect"))))
	var out: Array = defense.slice(0, STARTER_CHARM_COUNT)
	if out.size() < STARTER_CHARM_COUNT:
		for p in pool:
			if out.size() >= STARTER_CHARM_COUNT:
				break
			var d = load(p)
			if not out.has(p) and String(d.get("rarity")) == "common" and String(d.get("downside_effect")) == "":
				out.append(p)
	if out.size() < STARTER_CHARM_COUNT:
		for p in pool:
			if out.size() >= STARTER_CHARM_COUNT:
				break
			if not out.has(p):
				out.append(p)
	return out


func _all_active_items() -> Array:
	var out := []
	for p in _ctrl.ITEM_POOL:
		var d = load(p)
		if d is ItemData and d.category == "active":
			out.append(p)
	return out


# BOSS 信物判定（2026-08-14）：epic 稀有度 + *_relic 文件名的 passive——
# 12 个 BOSS 信物仅 BOSS 战利品可获（docs/BOSS信物_设计方案.md），不进种子/商店/铁砧池。
# 旧 3 信物（rust/whisper/abyss_relic，rare/common/uncommon）与非信物 epic（crush_seal/status_charm）不受影响。
static func _is_boss_relic(d: Resource, p: String) -> bool:
	return d.get("rarity") == "epic" and p.get_file().contains("_relic")


func sanitize_owned() -> void:
	# 自愈：历史上技能曾被误写入 owned_weapons（shop 的 owned_key 推导 bug）。
	# 清洗各 owned_* 中不属于本类的路径，避免 load 出 SkillData 后整备屏按 weapon 读 weapon_name 崩溃。
	for key in ["owned_weapons", "owned_charms", "owned_consumables", "owned_skills"]:
		if not meta.has(key):
			continue
		var cleaned := []
		for p in meta[key]:
			var d = load(p)
			var ok := false
			if key == "owned_weapons":
				ok = (d is WeaponData)
			elif key == "owned_charms":
				ok = (d is ItemData and d.category == "passive")
			elif key == "owned_consumables":
				ok = (d is ItemData and d.category == "active")
			elif key == "owned_skills":
				ok = (d is SkillData)
			if ok:
				cleaned.append(p)
		meta[key] = cleaned
	self.save_meta()


# G2-01：装备来源记录。只记最少可核对的信息，同一来源只留一条，按件数封顶防止存档膨胀。
const SOURCE_MAX := 5


func record_source(path: String, entry: Dictionary) -> void:
	if path == "" or entry.is_empty():
		return
	if not meta.has("item_sources") or not (meta["item_sources"] is Dictionary):
		meta["item_sources"] = {}
	var all: Dictionary = meta["item_sources"]
	var arr: Array = all.get(path, [])
	if arr.has(entry):
		return
	arr.append(entry.duplicate(true))
	while arr.size() > SOURCE_MAX:
		arr.pop_front()
	all[path] = arr
	meta["item_sources"] = all


func award_gold(is_boss: bool) -> void:
	var base = 10 if is_boss else 5
	var interest = mini(int(_ctrl.gold / 5.0), 5)     # S8：每 5 金 +1，上限 +5
	var total = base + interest
	_ctrl.gold += total
	_ctrl.hud._log("金币 +%d（清房 %d + 利息 %d，共 %d）" % [total, base, interest, _ctrl.gold])
	_ctrl.hud._popup("💰+%d" % total, Palette.POP_GOLD, _ctrl.hud._player_sprite_anchor())
	_ctrl.invalidate_state()
	_ctrl.hud._refresh_meta()   # 自包含刷新：直接调用本方法的新路径不依赖外部收尾
