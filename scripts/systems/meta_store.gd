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


func seed_default_owned() -> void:
	# 新档/迁移：owned_* 为空时用当前全池种子填充，保证整备屏有可选范围。
	# Gungeon 化可改为只给基础子集（如 WEAPON_POOL 前 N 个）。
	# 调试开关 SMALL_OWNED：仅在 owned 为空时把拥有池压到 3 武器/4 护符（便于观察铁砧抽新）；
	#   关掉恢复正式全池。仅「空时」播种，铁砧授予的新件不会被重载后抹掉（要恢复全池请清存档）。
	if _ctrl.SMALL_OWNED:
		if meta["owned_weapons"].is_empty():
			meta["owned_weapons"] = _ctrl.WEAPON_POOL.slice(0, _ctrl.SMALL_OWNED_WEAPONS)
	if meta["owned_charms"].is_empty():
		var ps := []
		for p in _ctrl.ITEM_POOL:
			var d = load(p)
			if d is ItemData and d.category == "passive":
				if _is_boss_relic(d, p):
					continue   # BOSS 信物（epic *_relic）不种子——仅 BOSS 战利品可获（见 docs/BOSS信物_设计方案.md）
				ps.append(p)
		meta["owned_charms"] = ps.slice(0, _ctrl.SMALL_OWNED_CHARMS)
		self.save_meta()
		return
	if meta["owned_weapons"].is_empty():
		meta["owned_weapons"] = _ctrl.WEAPON_POOL.duplicate()
	if meta["owned_charms"].is_empty():
		var ps := []
		for p in _ctrl.ITEM_POOL:
			var d = load(p)
			if d is ItemData and d.category == "passive":
				if _is_boss_relic(d, p):
					continue   # BOSS 信物不种子（见上）
				ps.append(p)
		meta["owned_charms"] = ps
	if meta["owned_consumables"].is_empty():
		var cs := []
		for p in _ctrl.ITEM_POOL:
			var d = load(p)
			if d is ItemData and d.category == "active":
				cs.append(p)
		meta["owned_consumables"] = cs
	self.save_meta()


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
