extends Control
# ============================================================================
# 官方对决控制器（DuelController）
# 由原型 prototypes/reel_combat/reel_combat.gd 迁移而来（M0–M6 完整闭环）。
# 符号数据层：scripts/battle/symbol_data.gd（SymbolData 资源）、WeaponData.reel、
#   8 把武器 .tres、ItemData（合并原 ConsumableData/CharmData）+ 8 个 .tres。
# 与原型唯一差异：铁砧元进度存档由 user://reel_combat_save.json 改为
#   SaveSystem.lobby_data["anvil_meta"]（与项目统一 JSON 存档）。
# 全代码 UI（Control 树），可直接作为 duel.tscn 脚本运行（F6）或由 RoomManager 进入。
#
# 原原型注释（功能增量说明）：
# ----------------------------------------------------------------------------
# M2 原型 — 老虎机回合制战斗（完整单敌对决闭环）
# 相对 M1 的增量：
#   · 真实敌人意图：每回合预告(attack/heavy/jam)，玩家 SPIN 后敌人执行该意图
#   · 胜负状态机 + 房间推进（ROOMS 数组，逐房升级，通关/失败可重开）
#   · DoT 细化（灼烧/毒跨回合持续、回合末衰减、HUD 显示层数）
#   · 干扰反制接入（M3 的轻量切片）：敌人 jam 注入废铁占据一列，
#     玩家用「净化」次数抵消（每房回满，M3 将由消耗品承接）
# 仍：1 行 3 格、符号池来自 WeaponData.reel、单符号必结算+匹配倍率、无锁定。
# 按 F6 运行试玩。
#
# M3 增量（整备选物 UI）：
#   · 开局先进入整备覆盖层，从 WEAPON_POOL 自由勾选 1–5 把武器
#   · 带哪把武器 = 转轮里有什么符号（卡片实时预览符号池）
#   · 战斗中可「重新整备」返回选配；确认后按所选武器重建符号池
#   · 消耗品 / 护符分类在 UI 框架中预留（M3 后续接入实际数据）
# M3 干扰系统增量（本版）：
#   · 敌人干扰分支扩展为 注废(jam) / 锁轮(lock) / 乱权(chaos) 三类（攻击 attack / 重击 heavy 不变）
#   · 净化接成消耗品：整备携带「净化药剂 ×N」决定净化上限，每房回满到携带量
#   · 意图 HUD 含干扰图标与「可净化」提示；净化可清除任意一类干扰意图
# M4 增量（房间 + Roguelike 构筑）：
#   · 跑通一局（Run）：HP 跨房保留；每清一房弹出「房奖励」三选一界面（Roguelike 构筑）
#   · 本局加成层：符号权重加成(run_symbol_bonus) / 符号伤害加成(run_power_bonus) / 下一房护盾(run_shield_next)
#   · 奖励池 REWARD_POOL：治疗 / 最大HP / 净化上限 / 符号灌注 / 守望结界 / 锋锐打磨
#   · Boss 房（最后一房）击败 → 通关 → 领取残余物奖励 → 开新一局
# ============================================================================

const TRASH_SYMBOL = preload("res://resources/symbols/trash.tres")
const ElementCounter = preload("res://scripts/battle/element_counter.gd")
# Phase D 软注册表清理：文件夹自动扫描工具（替代手写路径数组）
const ResourceScan = preload("res://scripts/utils/resource_scan.gd")

# Phase 1 组件化：UI 复用场景与脚手架
const UI_BUTTON = preload("res://scenes/ui/ui_button.tscn")

# 可选物品池（整备界面从这里自由勾选，真实 .tres 数据）。
# Phase D 软注册表清理：改为文件夹自动扫描，新增内容只需在对应 resources/ 子目录放 .tres，
# 不再手写路径数组（见 _ready 内的 ResourceScan 填充）。默认空，待 _ready 填充。
var WEAPON_POOL: Array = []
var ITEM_POOL: Array = []
# Phase C 主动增益：携带后其符号进入转轮，连线命中施加限时增益
var BUFF_POOL: Array = []

# 携带约束（与策划案 v0.4 定稿一致）：武器硬下限≥1；分类容量上限；总槽≈8（Phase C 起含增益）。
const LOADOUT_MIN := 1
const LOADOUT_MAX := 5
const CONSUMABLE_MIN := 0
const CONSUMABLE_MAX := 3
const CHARM_MIN := 0
const CHARM_MAX := 2
const BUFF_MIN := 0
const BUFF_MAX := 2
const TOTAL_MAX := 8

const REELS = 3
const ROWS = 1

# M4 房奖励池（每清一房随机 3 选 1；Boss 房走同池但标为「残余物」）。
# Phase D 资源化：改为扫描 resources/rewards/*.tres（RewardData），见 _ready 内填充。
var REWARD_POOL: Array = []

# 房间序列（肉鸽逐房推进）。
# jam=注废意图概率, lock=锁轮意图概率, chaos=乱权意图概率, heavy=重击意图概率, 其余=普攻。
# Phase D 资源化：改为扫描 resources/rooms/*.tres（RoomData），见 _ready 内填充。
var ROOMS: Array = []

# grid[reel][row] = SymbolData 引用
var grid = []

# 合并后的加权符号池：元素为 [SymbolData, weight]
var pool: Array = []
var loadout_names: Array = []
var _special_element: String = "none"   # 当前池内特殊符号的属性元素（取自武器 reel_element）
var _busy: bool = false                 # 旋转序列进行中，防重入

# 整备（M3–M6）：玩家自由勾选武器 / 消耗品 / 护符三分类
var in_loadout := false
var selected_loadout: Array = []          # 玩家勾选的武器路径
var selected_consumables: Array = []      # 玩家勾选的消耗品路径
var selected_charms: Array = []           # 玩家勾选的护符路径
var selected_buffs: Array = []            # 玩家勾选的主动增益路径（Phase C）

# Phase C 主动增益运行时：SymbolData -> 剩余回合数（本房内有效，进房清空）
var player_buffs: Dictionary = {}

# 消耗品运行时（战斗中主动使用）
var consumable_charges: Dictionary = {}   # item_id -> 剩余次数（每房回满）
var consumable_panel                      # 战斗 UI 底部消耗品按钮行
var consumable_buttons: Array = []        # {id, data, btn}
var assault_next_spin: int = 1            # 强袭药剂：下次转轮伤害倍率（1=正常）

# 玩家状态
var player_hp = 100
var player_hp_max = 100
var player_shield = 0

# 敌人 / 房间状态
var room_index = 0
var enemy_name = "敌人"
var enemy_hp = 120
var enemy_hp_max = 120
var enemy_atk = 14
var enemy_jam = 0.2
var enemy_lock = 0.1
var enemy_chaos = 0.1
var enemy_heavy = 0.2
var enemy_status: Dictionary = {}      # status_type(str) -> 叠加层数(int)
var enemy_intent: Dictionary = {}      # 当前敌人意图（SPIN 后执行），空字典表示已执行/未定
var enemy_element: String = "none"     # 敌人属性元素（用于单向克制：玩家符号元素 → 敌人元素）
var pending_jam_reel = -1              # 敌人注废 → 下一轮强制废铁列索引（-1 无）
var pending_lock_reel = -1             # 敌人锁轮 → 下一轮该列固定为当前符号（-1 无）
var pending_chaos = false              # 敌人乱权 → 下一轮权重削弱优势符号
var _pool_backup: Array = []           # chaos 临时池备份（spin 后还原）
# 净化上限 = 携带「净化药剂」数值 + 丰沛护符加成 + 房奖励增量；每房回满到该值
var purify_max_base = 0
var purify_charges = 0

# M6 护符被动（整局生效，_apply_charms 在 _confirm_loadout 结算）
var charm_power_bonus: int = 0         # 锋锐护符：本局所有伤害符号 +N
var charm_room_shield: int = 0         # 守望护符：每房开局护盾 +N
var charm_interf_resist: int = 0       # 抗扰护符：本局敌人干扰概率降低（等效抗扰等级）
var charm_purify_bonus: int = 0        # 丰沛护符：净化上限 +N

# 流程状态
var game_state = "playing"             # playing | won | lost | cleared
var turn_count = 1

# M4 本局（Run）加成层
var run_symbol_bonus: Dictionary = {}  # resource_path -> 额外权重（奖励：符号灌注）
var run_power_bonus: int = 0           # 本局符号基础伤害加成（奖励：锋锐打磨）
var run_shield_next: int = 0           # 进入下一房时获得的护盾（奖励：守望结界）
var reward_choices: Array = []         # 当前展示的 3 个奖励
var reward_is_boss: bool = false       # 当前奖励是否来自 Boss 房（选完开新局）

# M5 元进度（铁砧锻造 + 存档持久化，跨局保留）
# weapon_upgrades: weapon_path -> int（该武器主符号额外权重，转轮升级）
# interference_resist: int（抗干扰等级，降低敌人干扰概率）
var meta: Dictionary = {"anvil_points": 0, "weapon_upgrades": {}, "interference_resist": 0}
const ANVIL_SAVE_KEY := "anvil_meta"   # 铁砧元进度存于 SaveSystem.lobby_data

# 仅 1 行 3 格。特殊符号需 3 同才触发；普通符号单颗即结算，出现 n 次 ×n。
var PAYLINES = [
	[[0,0],[1,0],[2,0]],
]

# UI 引用

# 符号图例（每符号名称/类型/元素 + 敌人属性提示）

var logs: Array = []



const BATTLE_HUD = preload("res://scenes/ui/battle_hud.tscn")
var hud: BattleHud

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Phase D：文件夹自动扫描内容池（替代手写路径数组）。必须在构建整备界面之前完成。
	WEAPON_POOL = ResourceScan.scan_paths("res://resources/weapon_templates/")
	ITEM_POOL = ResourceScan.scan_paths("res://resources/items/")
	BUFF_POOL = ResourceScan.scan_paths("res://resources/buffs/")
	ROOMS = ResourceScan.scan_resources("res://resources/rooms/", "RoomData")
	REWARD_POOL = ResourceScan.scan_resources("res://resources/rewards/", "RewardData")
	hud = BATTLE_HUD.instantiate()
	add_child(hud)
	hud.controller = self
	_load_meta()
	hud._build_ui()
	hud._build_loadout_screen()
	hud._build_reward_screen()
	hud._build_anvil_screen()
	hud._show_loadout_screen()
func _build_pool(loadout: Array) -> void:
	pool = []
	loadout_names = []
	_special_element = "none"
	var merged := {}   # resource_path -> [SymbolData, 总权重]（跨武器累加）
	for path in loadout:
		var wd: WeaponData = load(path)
		if wd == null:
			hud._log("⚠ 找不到武器: " + path)
			continue
		loadout_names.append(wd.weapon_name)
		if wd.reel == null or wd.reel.is_empty():
			continue
		for sw in wd.reel:
			if sw == null or sw.symbol == null:
				continue
			var sp: String = sw.symbol.resource_path
			if not merged.has(sp):
				merged[sp] = [sw.symbol, 0.0]
			merged[sp][1] += float(sw.weight)
			# 记录特殊符号的属性元素（用于单向克制）
			if sw.symbol.kind == "special" and wd.reel_element != "none":
				_special_element = wd.reel_element
		# M5 铁砧：武器升级 → 主符号（权重最高者）额外加成
		var bonus = meta["weapon_upgrades"].get(path, 0)
		if bonus > 0 and not wd.reel.is_empty():
			var dom_path = ""
			var domw = -1.0
			for sw in wd.reel:
				if sw == null or sw.symbol == null:
					continue
				var w = float(sw.weight)
				if w > domw:
					domw = w
					dom_path = sw.symbol.resource_path
			if dom_path != "":
				if not merged.has(dom_path):
					merged[dom_path] = [load(dom_path), 0.0]
				merged[dom_path][1] += float(bonus)
	# Phase C：所携带的主动增益，其符号同样注入转轮池（与武器符号同池竞争）
	for path in selected_buffs:
		var bd: BuffData = load(path)
		if bd == null or bd.symbol == null:
			continue
		var bp: String = bd.symbol.resource_path
		if not merged.has(bp):
			merged[bp] = [bd.symbol, 0.0]
		merged[bp][1] += float(bd.weight)
	for sp in merged.keys():
		pool.append([merged[sp][0], merged[sp][1]])
	# M4 本局符号权重加成（符号灌注奖励叠加）— run_symbol_bonus 以 resource_path 为键
	for spath in run_symbol_bonus.keys():
		var found = false
		for p in pool:
			if p[0].resource_path == spath:
				p[1] += float(run_symbol_bonus[spath])
				found = true
				break
		if not found:
			pool.append([load(spath), float(run_symbol_bonus[spath])])
	# 符号图例（每符号名称/类型/元素 + 敌人属性）
	if hud.legend_container != null:
		hud._refresh_legend()


func _weighted_random_sym() -> SymbolData:
	if pool.is_empty():
		return TRASH_SYMBOL
	var total := 0.0
	for p in pool:
		total += p[1]
	var r := randf() * total
	for p in pool:
		r -= p[1]
		if r < 0:
			return p[0]
	return pool[0][0]


# 乱权：临时扭曲权重池（削弱最高权重符号、增强废铁），spin 后由 _restore_pool 还原
func _apply_chaos_pool() -> void:
	_pool_backup = pool.duplicate(true)
	var max_w = 0.0
	for p in pool:
		max_w = max(max_w, p[1])
	var chaotic := []
	for p in pool:
		var w = p[1]
		if p[0] == TRASH_SYMBOL:
			w *= 2.0
		elif w >= max_w * 0.99:
			w *= 0.35
		chaotic.append([p[0], w])
	pool = chaotic


func _restore_pool() -> void:
	if not _pool_backup.is_empty():
		pool = _pool_backup
		_pool_backup = []


# ---------------------------------------------------------------------------
# UI 构建（全代码）
# ---------------------------------------------------------------------------
func _on_card_toggled(card: Dictionary) -> void:
	var cat = card.kind
	var arr = _sel_arr(cat)
	if card["selected"]:
		card["selected"] = false
		arr.erase(card["path"])
	else:
		if arr.size() >= _cat_max(cat):
			hud._log("%s已达上限 %d" % [_cat_name(cat), _cat_max(cat)])
			return
		if _total_selected() >= TOTAL_MAX:
			hud._log("总槽已达上限 %d" % TOTAL_MAX)
			return
		card["selected"] = true
		arr.append(card["path"])
	hud._update_loadout_cards_visual()
	hud._update_loadout_count()


func _sel_arr(cat: String) -> Array:
	match cat:
		"weapon":  return selected_loadout
		"active":  return selected_consumables
		"passive": return selected_charms
		"buff":    return selected_buffs
	return []


func _cat_max(cat: String) -> int:
	match cat:
		"weapon":  return LOADOUT_MAX
		"active":  return CONSUMABLE_MAX
		"passive": return CHARM_MAX
		"buff":    return BUFF_MAX
		"item":    return CONSUMABLE_MAX + CHARM_MAX
	return 99


func _cat_name(cat: String) -> String:
	match cat:
		"weapon":  return "武器"
		"active":  return "消耗品"
		"passive": return "护符"
		"buff":    return "增益"
		"item":    return "物品"
	return cat


func _total_selected() -> int:
	return selected_loadout.size() + selected_consumables.size() + selected_charms.size() + selected_buffs.size()


func _confirm_loadout() -> void:
	if selected_loadout.size() < LOADOUT_MIN:
		return
	_apply_charms()                       # 结算护符被动 + 净化上限
	hud._hide_loadout_screen()
	_full_reset()


# 结算护符被动（整局生效）与净化上限（净化药剂 + 丰沛护符）
func _apply_charms() -> void:
	charm_power_bonus = 0
	charm_room_shield = 0
	charm_interf_resist = 0
	charm_purify_bonus = 0
	for path in selected_charms:
		var cd: Resource = load(path)
		if cd == null:
			continue
		match cd.effect:
			"damage_bonus":         charm_power_bonus += cd.value
			"room_shield":          charm_room_shield += cd.value
			"interference_resist":  charm_interf_resist += cd.value
			"purify_bonus":         charm_purify_bonus += cd.value
	var pm = 0
	for path in selected_consumables:
		var cd: Resource = load(path)
		if cd != null and cd.effect == "purify":
			pm += cd.value
	purify_max_base = pm + charm_purify_bonus
	hud._log("护符已装配：伤害+%d / 护盾+%d / 抗扰+%d / 净化+%d" % [charm_power_bonus, charm_room_shield, charm_interf_resist, charm_purify_bonus])


func _on_reload_loadout_pressed() -> void:
	hud._show_loadout_screen()


# ---------------------------------------------------------------------------
# M4 房奖励三选一界面（Roguelike 构筑）
# ---------------------------------------------------------------------------
func _on_reward_chosen(id: String) -> void:
	hud.reward_screen.visible = false
	_apply_reward(id)
	_award_meta(reward_is_boss)    # M5：房间通关发放铁砧点数
	if reward_is_boss:
		_full_reset()              # 通关后开新一局
	else:
		_start_room(room_index + 1)
	hud._refresh_meta()


func _on_reward_skip_pressed() -> void:
	hud.reward_screen.visible = false
	_award_meta(reward_is_boss)    # M5：房间通关发放铁砧点数（即使跳过奖励）
	if reward_is_boss:
		_full_reset()
	else:
		_start_room(room_index + 1)
	hud._refresh_meta()


func _roll_rewards() -> Array:
	# REWARD_POOL 现为 RewardData 资源数组；元素只读不修改，用浅拷贝即可（避免深拷贝复制资源）。
	var copy = REWARD_POOL.duplicate()
	var out := []
	for i in 3:
		if copy.is_empty():
			break
		var idx = randi() % copy.size()
		out.append(copy[idx])
		copy.remove_at(idx)
	return out


func _apply_reward(id: String) -> void:
	match id:
		"heal":
			var h = int(player_hp_max * 0.35)
			player_hp = min(player_hp_max, player_hp + h)
			hud._log("奖励：治疗 +%d HP" % h)
		"maxhp":
			player_hp_max += 20
			player_hp = player_hp_max
			hud._log("奖励：最大 HP +20 并回满")
		"purify":
			purify_max_base += 1
			hud._log("奖励：净化上限 +1（当前 %d）" % purify_max_base)
		"symbol":
			var cand := []
			for p in pool:
				if p[0] != TRASH_SYMBOL:
					cand.append(p[0])
			if cand.is_empty():
				cand = [TRASH_SYMBOL]
			var sym: SymbolData = cand[randi() % cand.size()]
			run_symbol_bonus[sym.resource_path] = run_symbol_bonus.get(sym.resource_path, 0) + 3
			hud._log("奖励：%s 符号权重 +3" % sym.name)
		"shield":
			run_shield_next += 15
			hud._log("奖励：下一房 +15 护盾")
		"power":
			run_power_bonus += 1
			hud._log("奖励：本局符号伤害 +1（当前 +%d）" % run_power_bonus)


# ---------------------------------------------------------------------------
# M5 元进度（铁砧锻造 + 存档持久化）
# ---------------------------------------------------------------------------
func _load_meta() -> void:
	var defaults := {"anvil_points": 0, "weapon_upgrades": {}, "interference_resist": 0}
	var lb = SaveSystem.load_lobby_data()
	if lb.has(ANVIL_SAVE_KEY) and lb[ANVIL_SAVE_KEY] is Dictionary:
		var parsed: Dictionary = lb[ANVIL_SAVE_KEY]
		for k in defaults.keys():
			if parsed.has(k):
				meta[k] = parsed[k]
	hud._log("铁砧元进度已载入：点数 %d，武器升级 %d，抗干扰 Lv%d" % \
		[meta["anvil_points"], meta["weapon_upgrades"].size(), meta["interference_resist"]])


func _save_meta() -> void:
	var lb = SaveSystem.load_lobby_data()
	if lb is Dictionary:
		lb[ANVIL_SAVE_KEY] = meta
	else:
		lb = {ANVIL_SAVE_KEY: meta}
	SaveSystem.save_lobby_data(lb)
	SaveSystem.flush_lobby_data()   # 关键节点立即落盘，避免丢失


# 房间通关（含 Boss）发放铁砧点数并持久化；is_boss 给额外奖励
func _award_meta(is_boss: bool) -> void:
	var pts = 8 + (25 if is_boss else 0)
	meta["anvil_points"] += pts
	_save_meta()
	hud._log("铁砧点数 +%d（共 %d）" % [pts, meta["anvil_points"]])


func _on_anvil_weapon_pressed(path: String) -> void:
	var lvl = meta["weapon_upgrades"].get(path, 0)
	var cost = (lvl + 1) * 10
	if meta["anvil_points"] < cost:
		hud._log("铁砧点数不足（%s 需 %d）" % [path.get_file().get_basename(), cost])
		return
	meta["anvil_points"] -= cost
	meta["weapon_upgrades"][path] = lvl + 1
	_save_meta()
	hud._refresh_anvil()
	hud._log("铁砧：%s 转轮升级 Lv%d" % [path.get_file().get_basename(), lvl + 1])


func _on_anvil_resist_pressed() -> void:
	var rl = meta["interference_resist"]
	if rl >= 5:
		hud._log("抗干扰已满级")
		return
	var cost = (rl + 1) * 15
	if meta["anvil_points"] < cost:
		hud._log("铁砧点数不足（抗干扰需 %d）" % cost)
		return
	meta["anvil_points"] -= cost
	meta["interference_resist"] = rl + 1
	_save_meta()
	hud._refresh_anvil()
	hud._log("铁砧：抗干扰 Lv%d（敌人干扰概率降低）" % (rl + 1))


func _on_anvil_back_pressed() -> void:
	hud.anvil_screen.visible = false
	hud._update_loadout_anvil()


func _full_reset() -> void:
	player_hp = player_hp_max
	# M4：开新一局，重置本局加成层
	run_symbol_bonus = {}
	run_power_bonus = 0
	run_shield_next = 0
	_build_pool(selected_loadout)
	_start_room(0)


func _start_room(idx: int) -> void:
	room_index = idx
	var r: RoomData = ROOMS[idx]
	enemy_name = r.name
	enemy_hp_max = r.hp
	enemy_hp = enemy_hp_max
	enemy_atk = r.atk
	enemy_jam = r.jam
	enemy_lock = r.lock
	enemy_chaos = r.chaos
	enemy_heavy = r.heavy
	enemy_element = r.element if r.element != "" else "none"   # 单向克制：敌人属性（仅供玩家符号克制判定）
	# M5+M6 抗干扰：铁砧 + 抗扰护符 共同降低敌人干扰概率（每级 -12%，最低保留 25%）
	var total_resist = meta["interference_resist"] + charm_interf_resist
	if total_resist > 0:
		var rf = max(0.25, 1.0 - total_resist * 0.12)
		enemy_jam *= rf
		enemy_lock *= rf
		enemy_chaos *= rf
	enemy_status = {}
	player_buffs = {}                     # Phase C：主动增益不跨房保留
	player_shield = 0
	player_shield += run_shield_next      # M4：上一房奖励的结界在本房开局生效
	player_shield += charm_room_shield    # M6：守望护符每房开局护盾
	run_shield_next = 0
	pending_jam_reel = -1
	pending_lock_reel = -1
	pending_chaos = false
	purify_charges = purify_max_base      # 净化上限（净化药剂 + 丰沛护符 + 房奖励）
	# M6：消耗品每房回满次数
	consumable_charges = {}
	for path in selected_consumables:
		var cd: Resource = load(path)
		if cd != null:
			consumable_charges[cd.item_id] = cd.charges
	game_state = "playing"                # 必须在重建消耗品按钮前置为 playing，否则房间过渡瞬间按钮被误判为禁用
	_rebuild_consumable_panel()
	turn_count = 1
	enemy_intent = {}
	hud._hide_overlay()
	_reset_grid(true)
	_begin_player_turn()
	_refresh_consumable_panel()           # 双重保险：同步按钮禁用状态与当前战斗状态
	hud._refresh_meta()
	hud._refresh_legend()
	hud._log("▶ 进入房间 %d/%d：%s（HP %d，攻击 %d）" % [idx + 1, ROOMS.size(), enemy_name, enemy_hp_max, enemy_atk])


func _begin_player_turn() -> void:
	if game_state != "playing":
		return
	var rnd = randf()
	if rnd < enemy_jam:
		enemy_intent = {"type": "jam", "value": 0}
	elif rnd < enemy_jam + enemy_lock:
		enemy_intent = {"type": "lock", "value": 0}
	elif rnd < enemy_jam + enemy_lock + enemy_chaos:
		enemy_intent = {"type": "chaos", "value": 0}
	elif rnd < enemy_jam + enemy_lock + enemy_chaos + enemy_heavy:
		enemy_intent = {"type": "heavy", "value": enemy_atk * 2}
	else:
		enemy_intent = {"type": "attack", "value": enemy_atk}


func _on_spin_pressed() -> void:
	if in_loadout or game_state != "playing" or _busy:
		return
	_busy = true
	turn_count += 1
	# 阶段 0：旋转（刷新转轮，暂不结算）
	_do_spin_core()
	await get_tree().create_timer(0.45).timeout
	# 阶段 1+2：结算（先防御/增益/状态，后攻击；含飘字）
	await _evaluate()
	if enemy_hp <= 0:
		hud._log("★ 击败 %s！" % enemy_name)
		game_state = "won"
		var is_boss = (room_index + 1 >= ROOMS.size())
		var title = ("★ 通关！\n%s 被击败" % enemy_name) if is_boss else ("★ 胜利！\n%s 被击败" % enemy_name)
		hud._show_overlay(title, "领取奖励 ▶")
		hud._refresh_meta()
		_busy = false
		return

	# 阶段 3：敌人行动（先让玩家看清敌人刚掉的血）
	await get_tree().create_timer(0.35).timeout
	_enemy_turn()
	hud._refresh_meta()
	await get_tree().create_timer(0.55).timeout
	if enemy_hp <= 0:
		# 敌人可能在自身回合被状态 DoT 结算致死
		hud._log("★ 击败 %s！（状态结算）" % enemy_name)
		game_state = "won"
		var is_boss = (room_index + 1 >= ROOMS.size())
		var title = ("★ 通关！\n%s 被击败" % enemy_name) if is_boss else ("★ 胜利！\n%s 被击败" % enemy_name)
		hud._show_overlay(title, "领取奖励 ▶")
		_busy = false
		return
	if player_hp <= 0:
		hud._log("✖ 你被 %s 击倒。" % enemy_name)
		game_state = "lost"
		hud._show_overlay("✖ 失败\n你倒在了 %s 面前" % enemy_name, "重试本房 ↺")
		hud._refresh_meta()
		_busy = false
		return

	await get_tree().create_timer(0.30).timeout
	# 阶段 4：预告下一回合意图
	_begin_player_turn()
	hud._refresh_meta()
	_busy = false


# 旋转 + 结算核心（SPIN 与重转卷轴共用）
func _do_spin_core() -> void:
	var chaos_this_spin = pending_chaos
	if chaos_this_spin:
		_apply_chaos_pool()
	for reel in REELS:
		for row in ROWS:
			var sym: SymbolData
			if reel == pending_jam_reel:
				sym = TRASH_SYMBOL
			elif reel == pending_lock_reel:
				sym = grid[reel][row]
			else:
				sym = _weighted_random_sym()
			grid[reel][row] = sym
			hud._refresh_cell(reel, row)
	pending_jam_reel = -1
	pending_lock_reel = -1
	pending_chaos = false
	if chaos_this_spin:
		_restore_pool()


# 重转卷轴：免费重转一次（不触发敌人回合）
func _free_spin() -> void:
	if _busy:
		return
	_busy = true
	_do_spin_core()
	await _evaluate()
	if enemy_hp <= 0:
		hud._log("★ 重转触发击败 %s！" % enemy_name)
		game_state = "won"
		var is_boss = (room_index + 1 >= ROOMS.size())
		var title = ("★ 通关！\n%s 被击败" % enemy_name) if is_boss else ("★ 胜利！\n%s 被击败" % enemy_name)
		hud._show_overlay(title, "领取奖励 ▶")
	hud._refresh_meta()
	_busy = false


func _enemy_turn() -> void:
	var it: Dictionary = enemy_intent
	match it.get("type", "attack"):
		"attack", "heavy":
			_enemy_deal_damage(it.get("value", enemy_atk))
		"jam":
			pending_jam_reel = randi() % REELS
			hud._log("敌人注废 → 下一轮第 %d 列被废铁占据" % (pending_jam_reel + 1))
		"lock":
			pending_lock_reel = randi() % REELS
			hud._log("敌人锁轮 → 下一轮第 %d 列固定不变" % (pending_lock_reel + 1))
		"chaos":
			pending_chaos = true
			hud._log("敌人乱权 → 下一轮权重被打乱（优势符号被削弱）")
		"none":
			hud._log("敌人意图落空（已被净化）")
	enemy_intent = {}
	_tick_status()


func _enemy_deal_damage(raw: int) -> void:
	var blocked = min(player_shield, raw)
	player_shield -= blocked
	var dealt = raw - blocked
	player_hp -= dealt
	if dealt > 0:
		hud._popup("-%d" % dealt, Palette.POP_DAMAGE, hud._player_panel_anchor())
	hud._log("敌人攻击 %d（盾挡 %d，受 %d）" % [raw, blocked, dealt])


func _tick_status() -> void:
	var dot = 0
	for st in enemy_status.keys():
		var base = _status_base(st)
		var mult = ElementCounter.multiplier(_status_element(st), enemy_element)
		dot += int(round(enemy_status[st] * base * mult))
		enemy_status[st] = max(0, enemy_status[st] - 1)
		if enemy_status[st] <= 0:
			enemy_status.erase(st)
	if dot > 0:
		enemy_hp -= dot
		hud._log("状态结算 %d 伤害（灼烧/毒·含克制）" % dot)


func _on_purify_pressed() -> void:
	if in_loadout or _busy:
		return
	if game_state != "playing":
		return
	if enemy_intent.is_empty():
		hud._log("当前敌人无意图，无需净化")
		return
	if enemy_intent.get("type") not in ["jam", "lock", "chaos"]:
		hud._log("当前意图不可净化（攻击/重击）")
		return
	if purify_charges <= 0:
		hud._log("净化次数已用尽（整备携带的净化药剂不足）")
		return
	purify_charges -= 1
	var t = enemy_intent.get("type")
	enemy_intent = {"type": "none", "value": 0}
	hud._log("净化成功：抵消了敌人的%s" % _intent_name(t))
	hud._refresh_meta()


func _intent_name(t: String) -> String:
	match t:
		"jam":   return "注废"
		"lock":  return "锁轮"
		"chaos": return "乱权"
		"heavy": return "重击"
		"attack": return "攻击"
		_:      return t


# ---------------------------------------------------------------------------
# M6 消耗品：战斗中主动使用
# ---------------------------------------------------------------------------
# 根据整备携带的消耗品，重建战斗 UI 底部按钮行（每房调用一次）
func _rebuild_consumable_panel() -> void:
	for c in consumable_panel.get_children():
		consumable_panel.remove_child(c)
		c.queue_free()
	consumable_buttons = []
	if selected_consumables.is_empty():
		return
	for path in selected_consumables:
		var cd: Resource = load(path)
		if cd == null:
			continue
		var btn = UI_BUTTON.instantiate()
		btn.custom_minimum_size = Vector2(86, 30)
		btn.add_theme_font_size_override("font_size", TypeScale.TINY)
		btn.connect("pressed", _on_consumable_pressed.bind(cd.item_id))
		consumable_panel.add_child(btn)
		consumable_buttons.append({"id": cd.item_id, "data": cd, "btn": btn})
	_refresh_consumable_panel()


func _refresh_consumable_panel() -> void:
	for m in consumable_buttons:
		var left = consumable_charges.get(m["id"], 0)
		m["btn"].text = "%s%s(%d)" % [m["data"].icon, m["data"].item_name, left]
		m["btn"].disabled = (left <= 0 or game_state != "playing" or in_loadout)


func _on_consumable_pressed(id: String) -> void:
	if in_loadout or game_state != "playing" or _busy:
		return
	if consumable_charges.get(id, 0) <= 0:
		hud._log("「%s」已用尽" % id)
		return
	var data: Resource = null
	for m in consumable_buttons:
		if m["id"] == id:
			data = m["data"]
			break
	if data == null:
		return
	consumable_charges[id] -= 1
	match data.effect:
		"purify":
			if enemy_intent.get("type") in ["jam", "lock", "chaos"]:
				enemy_intent = {"type": "none", "value": 0}
				hud._log("净化药剂：抵消了敌人的干扰意图")
			purify_charges += data.value
			hud._log("净化药剂：恢复 %d 点净化次数（现 %d）" % [data.value, purify_charges])
		"heal":
			player_hp = min(player_hp_max, player_hp + data.value)
			hud._log("治疗药剂：回复 %d HP（现 %d）" % [data.value, player_hp])
		"assault":
			assault_next_spin = data.value
			hud._log("强袭药剂：下一次转轮伤害 ×%d" % data.value)
		"reroll":
			hud._log("重转卷轴：免费重转！")
			await _free_spin()
	_refresh_consumable_panel()
	hud._refresh_meta()


func _on_overlay_button_pressed() -> void:
	match game_state:
		"won":    hud._show_reward_screen(room_index + 1 >= ROOMS.size())   # M4：胜利→房奖励三选一
		"lost":   _retry_room()
		"cleared": _full_reset()


func _retry_room() -> void:
	player_hp = player_hp_max
	_start_room(room_index)


# ---------------------------------------------------------------------------
# 结算（方案 A：单符号必结算 + 匹配倍率）
# ---------------------------------------------------------------------------
func _reset_grid(fill_random: bool) -> void:
	hud._clear_badges()
	for reel in REELS:
		for row in ROWS:
			grid[reel][row] = TRASH_SYMBOL
			if fill_random:
				grid[reel][row] = _weighted_random_sym()
			hud._refresh_cell(reel, row)


func _contribute(sym: SymbolData, mult: int, acc: Dictionary) -> void:
	var flat = sym.base + run_power_bonus + charm_power_bonus + _buff_power()   # M6 锋锐护符 + Phase C 狂怒增益
	match sym.kind:
		"damage":  acc["dmg"]     += flat * mult
		"shield":  acc["shield"]  += sym.base * mult
		"heal":    acc["heal"]    += sym.base * mult
		"status":  acc["status_stacks"][sym.status_type] = acc["status_stacks"].get(sym.status_type, 0) + mult
		"special":
			# special 降级：1 同即生效（base×c），3 同额外追加一次 base
			var v = flat * mult
			if mult >= 3:
				v += flat
			acc["special"] += v
		_: pass


# 结算：分两阶段（先防御/增益/状态，后攻击），接单向属性克制与强袭药剂。
func _evaluate() -> void:
	hud._clear_badges()
	var acc = { "dmg": 0, "shield": 0, "heal": 0, "status_stacks": {}, "special": 0 }

	var row_syms: Array = []
	for p in PAYLINES[0]:
		row_syms.append(grid[p[0]][p[1]])
	var counts = {}
	for s in row_syms:
		counts[s] = counts.get(s, 0) + 1
	# Phase C：先结算 buff 符号（本回合即生效，命中当回合就吃到增益）
	for s in counts:
		if s == TRASH_SYMBOL or s.kind != "buff":
			continue
		_grant_buff(s, counts[s])
	# 再结算常规符号（此时 _contribute 读到的已是含新增益的加成）
	for s in counts:
		if s == TRASH_SYMBOL or s.kind == "buff":
			continue
		var c = counts[s]
		if s.kind == "special" and c < 1:
			continue
		_contribute(s, c, acc)

	# 匹配角标（×N，N>=2）
	hud._update_match_badges(counts)

	# —— 阶段 1：防御 / 增益 / 状态先落地 ——
	# Phase C：铁壁(shield)/回春(regen) 按回合生效，并入本回合护盾与治疗
	acc["shield"] += int(_buff_shield())
	acc["heal"] += int(_buff_regen())
	for st in acc["status_stacks"].keys():
		enemy_status[st] = enemy_status.get(st, 0) + acc["status_stacks"][st]
	if acc["shield"] > 0:
		player_shield += acc["shield"]
		hud._popup("🛡+%d" % acc["shield"], Palette.POP_SHIELD, hud._player_panel_anchor())
		hud._log("获得 %d 护盾" % acc["shield"])
	if acc["heal"] > 0:
		player_hp = min(player_hp_max, player_hp + acc["heal"])
		hud._popup("❤+%d" % acc["heal"], Palette.POP_HEAL, hud._player_panel_anchor())
		hud._log("回复 %d HP" % acc["heal"])
	if not acc["status_stacks"].is_empty():
		hud._log("敌人获得状态: " + _status_summary(acc["status_stacks"]))
		hud._popup(_status_summary(acc["status_stacks"]), Palette.POP_STATUS, hud._enemy_panel_anchor())

	hud._refresh_meta()
	await get_tree().create_timer(0.45).timeout

	# —— 阶段 2：攻击结算（单向克制 + 强袭药剂）——
	var sp_mult = ElementCounter.multiplier(_special_element, enemy_element)
	# Phase C：迅捷(damage_mult) 对本回合总伤害做乘算
	var buff_mult = _buff_damage_mult()
	var total = int((acc["dmg"] + acc["special"] * sp_mult) * assault_next_spin * buff_mult)
	assault_next_spin = 1
	if total > 0:
		enemy_hp -= total
		var elem_tag := ""
		if acc["special"] > 0 and sp_mult != 1.0:
			elem_tag = ElementCounter.tag(_special_element, enemy_element)
		if buff_mult != 1.0:
			elem_tag += "⚡"
		hud._popup("-%d%s" % [total, elem_tag], Palette.POP_DAMAGE, hud._enemy_panel_anchor())
		hud._log("连线造成 %d 伤害%s" % [total, elem_tag])
	await get_tree().create_timer(0.55).timeout
	# Phase C：回合末递减增益剩余回合
	_tick_buffs()


# ---------------------------------------------------------------------------
# Phase C 主动增益：符号自描述（sym.buff_effect / buff_value / buff_turns），零查表
# player_buffs: SymbolData -> 剩余回合数
# ---------------------------------------------------------------------------
func _grant_buff(sym: SymbolData, mult: int) -> void:
	var add = max(1, sym.buff_turns) * mult
	player_buffs[sym] = int(player_buffs.get(sym, 0)) + add
	hud._popup("%s+%d" % [sym.label, add], Palette.POP_BUFF, hud._player_panel_anchor())
	hud._log("增益：%s %s（剩余 %d 回合）" % [sym.label, sym.name, player_buffs[sym]])


# 按效果类型聚合当前生效的增益值（加法型）
func _buff_sum(effect: String) -> float:
	var v = 0.0
	for sym in player_buffs.keys():
		if sym.buff_effect == effect:
			v += sym.buff_value
	return v


func _buff_power() -> float:
	return _buff_sum("power")


func _buff_shield() -> float:
	return _buff_sum("shield")


func _buff_regen() -> float:
	return _buff_sum("regen")


# 乘法型增益（多个同时生效则连乘）
func _buff_damage_mult() -> float:
	var m = 1.0
	for sym in player_buffs.keys():
		if sym.buff_effect == "damage_mult":
			m *= sym.buff_value
	return m


func _tick_buffs() -> void:
	var expired: Array = []
	for sym in player_buffs.keys():
		player_buffs[sym] = int(player_buffs[sym]) - 1
		if player_buffs[sym] <= 0:
			expired.append(sym)
	for sym in expired:
		player_buffs.erase(sym)
		hud._log("增益结束：%s %s" % [sym.label, sym.name])


func _buff_summary() -> String:
	if player_buffs.is_empty():
		return "无"
	var parts: Array = []
	for sym in player_buffs.keys():
		parts.append("%s%d" % [sym.label, int(player_buffs[sym])])
	return " ".join(parts)


func _buff_effect_name(effect: String) -> String:
	match effect:
		"power":       return "伤害符号加成"
		"shield":      return "每回合护盾"
		"regen":       return "每回合回血"
		"damage_mult": return "总伤害倍率"
		_:             return effect


func _status_base(type_str: String) -> float:
	for p in pool:
		var d: SymbolData = p[0]
		if d.kind == "status" and d.status_type == type_str:
			return d.base
	return 0.0


# 状态类型对应的属性元素（用于 DoT 单向克制）
func _status_element(st: String) -> String:
	for p in pool:
		var d: SymbolData = p[0]
		if d.kind == "status" and d.status_type == st:
			return d.element
	return "none"


func _status_summary(stacks: Dictionary) -> String:
	var parts: Array = []
	for st in stacks.keys():
		parts.append("%s+%d" % [st, stacks[st]])
	return "/".join(parts)


# ---------------------------------------------------------------------------
# 表现刷新
# ---------------------------------------------------------------------------
func _input(event) -> void:
	if in_loadout:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_on_spin_pressed()
