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
	var defaults := {"anvil_points": 0, "owned_weapons": [], "owned_charms": [], "owned_consumables": [], "anvil_pity": 0, "collection_milestones": []}
	var lb = SaveSystem.load_lobby_data()
	if lb.has(_ctrl.ANVIL_SAVE_KEY) and lb[_ctrl.ANVIL_SAVE_KEY] is Dictionary:
		var parsed: Dictionary = lb[_ctrl.ANVIL_SAVE_KEY]
		for k in defaults.keys():
			if parsed.has(k):
				meta[k] = parsed[k]
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

func seed_default_owned() -> void:
	# 迁移口径：只「补足」基础子集，从不删除已有收藏——老存档的全池收藏原样保留（不回收已获得内容）。
	_ensure_owned("owned_weapons", _starter_weapons())
	_ensure_owned("owned_charms", _starter_charms())
	_ensure_owned("owned_consumables", _all_active_items())
	self.save_meta()


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


# 初始护符：非 BOSS 信物的 passive 中优先 common（保证新档有基础防御向构筑），按路径稳定排序取前 N。
func _starter_charms() -> Array:
	var pool := []
	for p in _ctrl.ITEM_POOL:
		var d = load(p)
		if d is ItemData and d.category == "passive" and not _is_boss_relic(d, p):
			pool.append(p)
	pool.sort()
	var common := pool.filter(func(p): return String(load(p).get("rarity")) == "common")
	var out: Array = common.slice(0, STARTER_CHARM_COUNT)
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
	for key in ["owned_weapons", "owned_charms", "owned_consumables"]:
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
			if ok:
				cleaned.append(p)
		meta[key] = cleaned
	self.save_meta()


func award_gold(is_boss: bool) -> void:
	var base = 10 if is_boss else 5
	var interest = mini(int(_ctrl.gold / 5.0), 5)     # S8：每 5 金 +1，上限 +5
	var total = base + interest
	_ctrl.gold += total
	_ctrl.hud._log("金币 +%d（清房 %d + 利息 %d，共 %d）" % [total, base, interest, _ctrl.gold])
	_ctrl.hud._popup("💰+%d" % total, Palette.POP_GOLD, _ctrl.hud._player_sprite_anchor())
	_ctrl.invalidate_state()
	_ctrl.hud._refresh_meta()   # 自包含刷新：直接调用本方法的新路径不依赖外部收尾
