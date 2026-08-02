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
const GOLD_SYMBOL = preload("res://resources/symbols/gold.tres")
const GOLD_POOL_WEIGHT := 3.0      # 金币符号在转轮池中的权重（远低于伤害符号，防稀释 DPS）
const GOLD_PER_COIN := 1           # 每枚落在连线上的金币符号产出的金币数
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

# 携带约束（Phase G 收紧）：按「进池 / 不进池」两把尺子分开管，而不是按总数一刀切。
#   · 进池类（武器 / 增益）：符号会挤进同一条转轮带 → 带多了稀释克制乘区、稀释 special
#     三连、拉长带子让「按停到目标符号」变难。故上限压得很死：武器 1–2、增益 0–1。
#   · 不进池类：消耗品只影响界面负担，尺度可宽松；护符虽不进池，但是「唯一收集乘区」，
#     须严格限量（见下「护符硬上限」注），不可照搬消耗品的宽松尺度。
#   · TOTAL_MAX 是真正的取舍闸门：分类上限之和 = 2+1+2+3 = 8 > 5，逼玩家「想带的比能带的多」。
# 注：护符为「唯一收集乘区」，硬上限 3、不成长。未来混合护符（正负并存）的负面即其平衡刹车，
#     故无需「护符槽成长」通道（旧 Phase G 的 1→4 成长计划已废弃）。
const LOADOUT_MIN := 1
const LOADOUT_MAX := 2
const CONSUMABLE_MIN := 0
const CONSUMABLE_MAX := 2
const CHARM_MIN := 0
const CHARM_MAX := 3
const BUFF_MIN := 0
const BUFF_MAX := 1
const TOTAL_MAX := 5

const REELS = 3
const ROWS = 1

# 房间难度曲线（ante）：敌方 HP/ATK 随房间序号 n 指数缩放（1+α)^n。
# 玩家膨胀（武器升级/护符）需敌方同步变肉，否则中期秒怪、游戏结束。初值待真机调参。
const ANTE_ALPHA_HP := 0.15
const ANTE_ALPHA_ATK := 0.10

# M4 房奖励池（每清一房随机 3 选 1；Boss 房走同池但标为「残余物」）。
# Phase D 资源化：改为扫描 resources/rewards/*.tres（RewardData），见 _ready 内填充。
var REWARD_POOL: Array = []

# 房间序列（肉鸽逐房推进）。
# jam=注废意图概率, lock=锁轮意图概率, chaos=乱权意图概率, heavy=重击意图概率, 其余=普攻。
# Phase D 资源化：改为扫描 resources/rooms/*.tres（RoomData），见 _ready 内填充。
var ROOMS: Array = []

# grid[reel][row] = SymbolData 引用
var grid = []
# grid_elem[reel][row] = 该格符号的「有效元素」（武器元素继承后的实际元素，用于逐符号克制结算）
var grid_elem = []

# 合并后的加权符号池：元素为 [SymbolData, weight, element]（element = 有效元素）
var pool: Array = []
var loadout_names: Array = []
var _busy: bool = false                 # 旋转序列进行中，防重入
var _eval_adv := false                  # _evaluate 阶段2：本回合是否触发过「克制」
var _eval_dis := false                  # _evaluate 阶段2：本回合是否触发过「抵抗」

# —— 实体转轮带（方案 A）：权重 = 带子上该符号的格子数，落点由停止时机决定 ——
var reel_strips: Array = []            # [reel] -> Array[ [SymbolData, element] ]
var reel_cursor: Array = []            # [reel] -> 当前带子索引（旋转时递增，取模长度）
var reel_stopped: Array = []           # [reel] -> 该列是否已停
var _locked_prev_sym: Array = []       # [reel] -> 锁轮保留的上一轮符号
var _locked_prev_elem: Array = []      # [reel] -> 锁轮保留的上一轮有效元素
var _spinning := false                 # 旋转进行中（供输入分支判断）
var _spin_timer: Timer                 # 旋转节拍器（每跳推进一格 + 加速）
var _spin_ticks := 0                   # 已跳次数（用于加速上限）
const _SPIN_BASE_WAIT := 0.09          # 起始每跳间隔（秒）
const _SPIN_MIN_WAIT := 0.035          # 最快每跳间隔（越转越快，到此封顶后恒速）
const _STRIP_MIN_CELLS := 30           # 转轮带最小格数（整份平铺补足，不改变符号占比）
# 注：不设自动停止上限——转轮何时停完全由玩家决定，不操作就一直转。
signal spin_finished                   # 全部转轮停下后发出，_on_spin_pressed 等待它

# 整备（M3–M6）：玩家自由勾选武器 / 消耗品 / 护符三分类
var in_loadout := false
var selected_loadout: Array = []          # 玩家勾选的武器路径
var selected_consumables: Array = []      # 玩家勾选的消耗品路径
var selected_charms: Array = []           # 玩家勾选的护符路径
var selected_buffs: Array = []            # 玩家勾选的主动增益路径（Phase C）

const STATUS_NAMES := {"burn": "燃", "frost": "霜", "poison": "毒"}

# Phase C 主动增益运行时：SymbolData -> 剩余回合数（本房内有效，进房清空）
var player_buffs: Dictionary = {}

# 消耗品运行时（战斗中主动使用）
var consumable_charges: Dictionary = {}   # item_id -> 剩余次数（整备确认时按持有初始化一次；用掉即消耗，仅靠商店补给）
var consumable_panel                      # 战斗 UI 底部消耗品按钮行
var consumable_buttons: Array = []        # {id, data, btn}
var assault_next_spin: int = 1            # 强袭药剂：下次转轮伤害倍率（1=正常）

# 玩家状态
var player_hp = 100
var player_hp_max = 100
var gold = 4                           # S6：局内金币（每局清零，见 §11）
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
var charm_shield_trickle: int = 0      # 守备护符：每回合护盾涓流（整局生效，见 §8）
var charm_interf_resist: int = 0       # 抗扰护符：本局敌人干扰概率降低（等效抗扰等级）
var charm_purify_bonus: int = 0        # 丰沛护符：净化上限 +N
var charm_damage_mult: float = 1.0      # Phase G v2.0：护符全局乘区（joker），默认 ×1.0

# 流程状态
var game_state = "playing"             # playing | won | lost | cleared
var turn_count = 1

# M4 本局（Run）加成层
var run_symbol_bonus: Dictionary = {}  # resource_path -> 额外权重（奖励：符号灌注）
var run_power_bonus: int = 0           # 本局符号基础伤害加成（奖励：锋锐打磨）
var run_shield_next: int = 0           # 进入下一房时获得的护盾（奖励：守望结界）
var reward_choices: Array = []         # 当前展示的 3 个奖励
var reward_is_boss: bool = false       # 当前奖励是否来自 Boss 房（选完开新局）
var shop_offers: Array = []            # S7：当前商店货架（随机刷新）

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
	hud._build_shop_screen()      # S7：商店覆盖层
	hud._show_loadout_screen()
	# 方案 A：旋转节拍器（转轮带滚动 + 加速 + 停止时机判定）
	_spin_timer = Timer.new()
	_spin_timer.one_shot = false
	_spin_timer.connect("timeout", _on_spin_tick)
	add_child(_spin_timer)
func _build_pool(loadout: Array) -> void:
	pool = []
	loadout_names = []
	# 合并键 = resource_path + "|" + 有效元素。
	# 关键：slash.tres 等符号被多把武器共享（同 resource_path），但火武器/无属性武器继承出的
	# 有效元素不同，必须按「符号+有效元素」双键分离，否则元素会冲突（Phase G v2.0 武器元素化）。
	var merged := {}   # key -> [SymbolData, 总权重, 有效元素]（跨武器累加）
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
			var eff: String = _eff_element(sw.symbol, wd)
			var mkey: String = sp + "|" + eff
			if not merged.has(mkey):
				merged[mkey] = [sw.symbol, 0.0, eff]
			merged[mkey][1] += float(sw.weight)
		# M5 铁砧：武器升级 → 主符号（权重最高者）额外加成（按「符号+有效元素」定位，避免共享符号冲突）
		var bonus = meta["weapon_upgrades"].get(path, 0)
		if bonus > 0 and not wd.reel.is_empty():
			var dom_sym: SymbolData = null
			var domw = -1.0
			for sw in wd.reel:
				if sw == null or sw.symbol == null:
					continue
				var w = float(sw.weight)
				if w > domw:
					domw = w
					dom_sym = sw.symbol
			if dom_sym != null:
				var deff: String = _eff_element(dom_sym, wd)
				var dkey: String = dom_sym.resource_path + "|" + deff
				if not merged.has(dkey):
					merged[dkey] = [dom_sym, 0.0, deff]
				merged[dkey][1] += float(bonus)
	# Phase C：所携带的主动增益，其符号同样注入转轮池（与武器符号同池竞争）
	for path in selected_buffs:
		var bd: BuffData = load(path)
		if bd == null or bd.symbol == null:
			continue
		var bp: String = bd.symbol.resource_path
		var beff: String = bd.symbol.element if bd.symbol.element != "none" else "none"
		var bkey: String = bp + "|" + beff
		if not merged.has(bkey):
			merged[bkey] = [bd.symbol, 0.0, beff]
		merged[bkey][1] += float(bd.weight)
	for key in merged.keys():
		pool.append(merged[key])
	# F-0 属性聚合层：符号权重修正（本局符号灌注 + Phase F 词缀），run_symbol_bonus 以 resource_path 为键
	for spath in run_symbol_bonus.keys():
		var found = false
		for p in pool:
			if p[0].resource_path == spath:
				p[1] += _agg_symbol_weight_mod(p[0])
				found = true
				break
		if not found:
			pool.append([load(spath), _agg_symbol_weight_mod(load(spath)), "none"])
	# 金币符号：常驻转轮资源（如废铁），落在线上的金币转化为金币（S6 经济引擎）
	pool.append([GOLD_SYMBOL, GOLD_POOL_WEIGHT, "none"])
	# 符号图例（每符号名称/类型/元素 + 敌人属性）
	if hud.legend_container != null:
		hud._refresh_legend()


# 计算某符号的「有效元素」（Phase G v2.0 武器元素化）：
# - special 符号：优先用武器 reel_element（特殊符号属性），否则用符号自身 element
# - 其余符号：自身 element 非 none 用之，否则继承武器 element（火武器 → 伤害符号带火）
func _eff_element(sym: SymbolData, wd: WeaponData) -> String:
	if sym.kind == "special":
		return wd.reel_element if wd.reel_element != "none" else sym.element
	return sym.element if sym.element != "none" else wd.element


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
		chaotic.append([p[0], w, p[2]])
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
	# 消耗品：整备确认时按当前持有一次性初始化次数（每房/每局不再回满，靠商店补给）
	consumable_charges = {}
	for path in selected_consumables:
		var cd: Resource = load(path)
		if cd != null:
			consumable_charges[cd.item_id] = cd.charges
	hud._hide_loadout_screen()
	_full_reset()


# 结算护符被动（整局生效）与净化上限（净化药剂 + 丰沛护符）
func _apply_charms() -> void:
	charm_power_bonus = 0
	charm_room_shield = 0
	charm_interf_resist = 0
	charm_purify_bonus = 0
	charm_damage_mult = 1.0
	charm_shield_trickle = 0
	for path in selected_charms:
		var cd: Resource = load(path)
		if cd == null:
			continue
		match cd.effect:
			"damage_bonus":         charm_power_bonus += cd.value
			"room_shield":          charm_room_shield += cd.value
			"interference_resist":  charm_interf_resist += cd.value
			"purify_bonus":         charm_purify_bonus += cd.value
			"shield":               charm_shield_trickle += cd.value   # 守备护符：每回合护盾涓流
			"damage_mult":          charm_damage_mult *= cd.mult_value
		# 混合护符的负面效果（未来卡用）：与正面同枚举、加成型数值取反、乘区型乘 downside_mult
		if cd.downside_effect != "":
			match cd.downside_effect:
				"damage_bonus":         charm_power_bonus -= cd.downside_value
				"room_shield":          charm_room_shield -= cd.downside_value
				"interference_resist":  charm_interf_resist -= cd.downside_value
				"purify_bonus":         charm_purify_bonus -= cd.downside_value
				"shield":               charm_shield_trickle -= cd.downside_value
				"damage_mult":          charm_damage_mult *= cd.downside_mult
	var pm = 0
	for path in selected_consumables:
		var cd: Resource = load(path)
		if cd != null and cd.effect == "purify":
			pm += cd.value
	purify_max_base = pm + charm_purify_bonus
	var charm_log = "护符已装配：伤害+%d / 开局护盾+%d / 每回合护盾+%d / 抗扰+%d / 净化+%d" % [charm_power_bonus, charm_room_shield, charm_shield_trickle, charm_interf_resist, charm_purify_bonus]
	if charm_damage_mult != 1.0:
		charm_log += " / 伤害×%s" % ElementCounter.fmt_mult(charm_damage_mult)
	hud._log(charm_log)


func _on_reload_loadout_pressed() -> void:
	hud._show_loadout_screen()


# ---------------------------------------------------------------------------
# M4 房奖励三选一界面（Roguelike 构筑）
# ---------------------------------------------------------------------------
func _on_reward_chosen(id: String) -> void:
	hud.reward_screen.visible = false
	_apply_reward(id)
	_award_meta(reward_is_boss)    # M5：房间通关发放铁砧点数
	_award_gold(reward_is_boss)    # S6+S8：清房金币 + 利息
	if reward_is_boss:
		_full_reset()              # 通关后开新一局（金币随局清零）
	else:
		hud._show_shop_screen()    # S7：房间之间进入商店
	hud._refresh_meta()


func _on_reward_skip_pressed() -> void:
	hud.reward_screen.visible = false
	_award_meta(reward_is_boss)    # M5：房间通关发放铁砧点数（即使跳过奖励）
	_award_gold(reward_is_boss)    # S6+S8：清房金币 + 利息
	if reward_is_boss:
		_full_reset()
	else:
		hud._show_shop_screen()    # S7：房间之间进入商店
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


# ---------------------------------------------------------------------------
# S6–S8 局内经济：金币 / 商店 / 利息
# ---------------------------------------------------------------------------
func _award_gold(is_boss: bool) -> void:
	var base = 10 if is_boss else 5
	var interest = mini(int(gold / 5), 5)     # S8：每 5 金 +1，上限 +5
	var total = base + interest
	gold += total
	hud._log("金币 +%d（清房 %d + 利息 %d，共 %d）" % [total, base, interest, gold])

func _shop_price(kind: String) -> int:
	var base = {"weapon": 8, "passive": 10, "active": 5, "buff": 6}.get(kind, 6)
	return max(3, base + randi_range(-1, 2))

func _shop_name(path: String, kind: String) -> String:
	var d = load(path)
	if d == null:
		return path.get_file().get_basename()
	match kind:
		"weapon": return (d as WeaponData).weapon_name if d is WeaponData else path.get_file().get_basename()
		"buff":   return (d as BuffData).buff_name if d is BuffData else path.get_file().get_basename()
		_:        return (d as ItemData).item_name if d is ItemData else path.get_file().get_basename()
	return path.get_file().get_basename()

func _roll_shop() -> void:
	var candidates := []
	for p in WEAPON_POOL:
		candidates.append({"path": p, "kind": "weapon"})
	for p in ITEM_POOL:
		var d = load(p)
		if d is ItemData:
			candidates.append({"path": p, "kind": d.category})
	for p in BUFF_POOL:
		candidates.append({"path": p, "kind": "buff"})
	candidates.shuffle()                      # 随机刷新，防背公式
	var n = min(candidates.size(), 6)
	shop_offers = []
	for i in n:
		var c = candidates[i]
		shop_offers.append({"path": c["path"], "kind": c["kind"], "price": _shop_price(c["kind"]), "name": _shop_name(c["path"], c["kind"]), "sold": false})

func _on_shop_buy_pressed(offer: Dictionary) -> void:
	if offer["sold"]:
		return
	var arr = _sel_arr(offer["kind"])
	if arr.has(offer["path"]):
		hud._log("已拥有 %s，无法重复购买" % offer["name"])
		return
	var cap = _cat_max(offer["kind"])
	if arr.size() >= cap:
		hud._log("%s槽位已满，无法购买" % _cat_name(offer["kind"]))
		return
	if gold < offer["price"]:
		hud._log("金币不足（需 %d）" % offer["price"])
		return
	gold -= offer["price"]
	arr.append(offer["path"])
	offer["sold"] = true
	if offer["kind"] == "active":   # 消耗品：立即写入可用次数，使新购物品当即可用
		var cd: Resource = load(offer["path"])
		if cd != null:
			consumable_charges[cd.item_id] = cd.charges
			_rebuild_consumable_panel()
	hud._log("购买 %s（-%d 金，余 %d）" % [offer["name"], offer["price"], gold])
	hud._refresh_shop()
	hud._refresh_meta()

func _on_shop_leave_pressed() -> void:
	hud.shop_screen.visible = false
	_start_room(room_index + 1)

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
	gold = 4                                 # S6：新一局金币清零（每局清零，见 §11）
	# M4：开新一局，重置本局加成层
	run_symbol_bonus = {}
	run_power_bonus = 0
	run_shield_next = 0
	_build_pool(selected_loadout)
	_start_room(0)


func _start_room(idx: int) -> void:
	_apply_charms()                         # S7：每次开房重算护符被动（含商店购入的护符）
	_build_pool(selected_loadout)           # S7：重建符号池（含商店购入的武器）
	room_index = idx
	var r: RoomData = ROOMS[idx]
	enemy_name = r.name
	# ante 难度曲线：RoomData.hp/atk 视为基础值，按房间序号 idx 缩放（(1+α)^idx）
	var hp_scale = pow(1.0 + ANTE_ALPHA_HP, idx)
	var atk_scale = pow(1.0 + ANTE_ALPHA_ATK, idx)
	enemy_hp_max = int(round(float(r.hp) * hp_scale))
	enemy_hp = enemy_hp_max
	enemy_atk = int(round(float(r.atk) * atk_scale))
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
	# 消耗品次数不再每房回满：已在整备确认时一次性初始化，用掉即消耗，仅靠商店补给
	game_state = "playing"                # 必须在重建消耗品按钮前置为 playing，否则房间过渡瞬间按钮被误判为禁用
	_rebuild_consumable_panel()
	turn_count = 1
	enemy_intent = {}
	hud._hide_overlay()
	_build_strips()
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
	# 阶段 0：旋转（实体转轮带滚动，玩家按停止键锁定落点；不立即结算）
	_begin_spin()
	await spin_finished
	await get_tree().create_timer(0.25).timeout
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


# ---------------------------------------------------------------------------
# 方案 A：实体转轮带 + 停止时机（SPIN 与重转卷轴共用）
# 权重 = 带子上该符号的格子数；落点由玩家按停时机决定，而非后台加权随机。
# ---------------------------------------------------------------------------

# 开始一次旋转：构建转轮带、随机起点、启动节拍器。结果在 spin_finished 后结算。
func _begin_spin() -> void:
	var chaos = pending_chaos
	if chaos:
		_apply_chaos_pool()
	_build_strips()
	if chaos:
		_restore_pool()
	reel_cursor = []
	reel_stopped = []
	_locked_prev_sym = []
	_locked_prev_elem = []
	for r in REELS:
		var len = reel_strips[r].size() if reel_strips.size() > r and not reel_strips[r].is_empty() else 1
		reel_cursor.append(randi() % len)
		reel_stopped.append(false)
		# 锁轮列：保留旋转前该列的符号与有效元素
		_locked_prev_sym.append(grid[r][0] if grid.size() > r and grid[r].size() > 0 else TRASH_SYMBOL)
		_locked_prev_elem.append(grid_elem[r][0] if grid_elem.size() > r and grid_elem[r].size() > 0 else "none")
		# 旋转期间允许点击该列以停止
		if hud.cells.size() > r and hud.cells[r].size() > 0:
			hud.cells[r][0].disabled = false
	_spinning = true
	_spin_ticks = 0
	hud._clear_damage_breakdown()   # S2：新一轮开始，先清掉上一回合的分解
	_spin_timer.wait_time = _SPIN_BASE_WAIT
	_spin_timer.start()
	hud._log("转轮旋转中——按【空格】逐列停止，或点击某一列单独停下（不停就一直转）")


# 由合并符号池构建每列转轮带：权重 → 带子上该符号的格子数。每列拿到一份洗牌副本（同构成、异顺序）。
func _build_strips() -> void:
	reel_strips = []
	if pool.is_empty():
		for r in REELS:
			reel_strips.append([[TRASH_SYMBOL, "none"]])
		return
	var base := []
	for p in pool:
		var w = int(round(p[1]))
		if w < 1:
			w = 1
		for _i in w:
			base.append([p[0], p[2]])
	if base.is_empty():
		base = [[TRASH_SYMBOL, "none"]]
	# 最小带长保护：武器砍到 1–2 把后带子可能只有 10 格左右，最高速下每秒循环近 3 圈，
	# 玩家能看出重复、观感发晕。整份平铺到 _STRIP_MIN_CELLS 以上——只拉长周期，
	# 各符号占比（即命中概率）完全不变。
	if base.size() < _STRIP_MIN_CELLS:
		var unit = base.duplicate(true)
		while base.size() < _STRIP_MIN_CELLS:
			base.append_array(unit.duplicate(true))
	for r in REELS:
		var copy = base.duplicate(true)
		for i in range(copy.size() - 1, 0, -1):
			var j = randi() % (i + 1)
			var tmp = copy[i]
			copy[i] = copy[j]
			copy[j] = tmp
		reel_strips.append(copy)


# 节拍器回调：推进仍在旋转的转轮并逐步加速。没有自动停止——只有玩家按停才会锁定。
func _on_spin_tick() -> void:
	if not _spinning:
		return
	_spin_ticks += 1
	var any_moving := false
	for r in REELS:
		if not reel_stopped[r]:
			var len = reel_strips[r].size() if reel_strips.size() > r and not reel_strips[r].is_empty() else 1
			reel_cursor[r] = (reel_cursor[r] + 1) % len
			_write_reel_cell(r)
			any_moving = true
	if not any_moving:
		_finish_spin()
		return
	var w = max(_SPIN_MIN_WAIT, _SPIN_BASE_WAIT - _spin_ticks * 0.0015)
	_spin_timer.wait_time = w


# 把当前带子位置的符号写入展示格（旋转中每跳调用，复用既有 _refresh_cell）。
func _write_reel_cell(r: int) -> void:
	var strip = reel_strips[r] if reel_strips.size() > r else null
	if strip == null or strip.is_empty():
		grid[r][0] = TRASH_SYMBOL
		grid_elem[r][0] = "none"
	else:
		var idx = reel_cursor[r] % strip.size()
		grid[r][0] = strip[idx][0]
		grid_elem[r][0] = strip[idx][1]
	hud._refresh_cell(r, 0)


# 锁定某列：pos<0 表示锁定在当前带子位置（按停时机）。注废/锁轮列覆盖结果。
func _lock_reel(r: int, pos: int) -> void:
	if r < 0 or r >= REELS or reel_stopped[r]:
		return
	if r == pending_jam_reel:
		grid[r][0] = TRASH_SYMBOL
		grid_elem[r][0] = "none"
		pending_jam_reel = -1
	elif r == pending_lock_reel:
		grid[r][0] = _locked_prev_sym[r]
		grid_elem[r][0] = _locked_prev_elem[r]
		pending_lock_reel = -1
	else:
		var strip = reel_strips[r]
		var idx = (pos if pos >= 0 else reel_cursor[r]) % strip.size()
		grid[r][0] = strip[idx][0]
		grid_elem[r][0] = strip[idx][1]
	reel_stopped[r] = true
	hud._refresh_cell(r, 0)
	if hud.cells.size() > r and hud.cells[r].size() > 0:
		hud.cells[r][0].disabled = true
	var all := true
	for rr in REELS:
		if not reel_stopped[rr]:
			all = false
			break
	if all:
		_finish_spin()


# 停止下一列（空格）：依次锁定尚未停下的列，时机由玩家掌握。
func _stop_next_reel() -> void:
	for r in REELS:
		if not reel_stopped[r]:
			_lock_reel(r, -1)
			return


# 全部转轮停下：停止节拍器、复位交互态、发信号让结算继续。
func _finish_spin() -> void:
	if not _spinning:
		return
	_spinning = false
	_spin_timer.stop()
	for r in REELS:
		if hud.cells.size() > r and hud.cells[r].size() > 0:
			hud.cells[r][0].disabled = true
	pending_jam_reel = -1
	pending_lock_reel = -1
	pending_chaos = false
	emit_signal("spin_finished")


# SPIN 按钮：旋转中=停止下一列，否则开始旋转。
func _on_spin_button_pressed() -> void:
	if _spinning:
		_stop_next_reel()
	else:
		_on_spin_pressed()


# 点击某列直接锁定该列（旋转中有效）。
func _on_reel_clicked(r: int) -> void:
	if not _spinning or reel_stopped[r]:
		return
	_lock_reel(r, -1)


# 重转卷轴：免费重转一次（不触发敌人回合）
func _free_spin() -> void:
	if _busy:
		return
	_busy = true
	_begin_spin()
	await spin_finished
	await get_tree().create_timer(0.25).timeout
	await _evaluate()
	_busy = false
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
	# 敌人 debuff 减益（元素驱动）：frost/poison = 敌人减攻。本函数是对敌人伤害的唯一闸口，
	# 且 _enemy_turn 在玩家结算之后，故当回合挂的 debuff 当回合生效。
	var atk_down = 1.0 - min(0.5, enemy_status.get("frost", 0) * 0.2 + enemy_status.get("poison", 0) * 0.2)
	var eff = int(round(float(raw) * atk_down))
	if atk_down < 1.0:
		hud._log("敌人被削弱：攻击×%s" % ElementCounter.fmt_mult(atk_down))
	var blocked = min(player_shield, eff)
	player_shield -= blocked
	var dealt = max(0, eff - blocked)
	player_hp -= dealt
	if dealt > 0:
		hud._popup("-%d" % dealt, Palette.POP_DAMAGE, hud._player_panel_anchor())
	hud._log("敌人攻击 %d（盾挡 %d，受 %d）" % [eff, blocked, dealt])


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
	if consumable_charges.get(id, 0) <= 0:
		consumable_charges.erase(id)
		for i in range(selected_consumables.size()):
			var d = load(selected_consumables[i])
			if d != null and d.item_id == id:
				selected_consumables.remove_at(i)
				break
		_rebuild_consumable_panel()
		hud._log("「%s」已用尽，移出持有（可于商店补给）" % id)
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
	hud._clear_damage_breakdown()
	grid_elem = []
	for reel in REELS:
		grid_elem.append([])
		for row in ROWS:
			grid_elem[reel].append("none")
			grid[reel][row] = TRASH_SYMBOL
			if fill_random and reel_strips.size() > reel and not reel_strips[reel].is_empty():
				var idx = randi() % reel_strips[reel].size()
				grid[reel][row] = reel_strips[reel][idx][0]
				grid_elem[reel][row] = reel_strips[reel][idx][1]
			hud._refresh_cell(reel, row)


func _contribute(sym: SymbolData, mult: int, acc: Dictionary, elem: String) -> void:
	var bonus = _agg_power_flat()             # F-0 聚合层：本局加成 + 护符 + 狂怒增益 + (Phase F 词缀)
	var flat = sym.base + bonus
	# 逐符号元素克制倍率（Phase G v2.0：通用元素乘区，奖罚并存·温和）
	var em = ElementCounter.multiplier(elem, enemy_element)
	if em > 1.0:
		_eval_adv = true
	elif em < 1.0:
		_eval_dis = true
	match sym.kind:
		"damage":
			var dv = flat * mult * em
			acc["dmg"] += dv
			_push_dmg_line(acc, sym, elem, flat, bonus, mult, em, dv, false)
		"shield":  acc["shield"]  += sym.base * mult
		"heal":    acc["heal"]    += sym.base * mult
		"status":  acc["status_stacks"][sym.status_type] = acc["status_stacks"].get(sym.status_type, 0) + mult
		"special":
			# special 降级：1 同即生效（base×c），3 同额外追加一次 base；均吃元素倍率
			var sv = flat * mult * em
			var crit = mult >= 3
			if crit:
				sv += flat * em
			acc["special"] += sv
			_push_dmg_line(acc, sym, elem, flat, bonus, mult, em, sv, crit)
		_: pass


# S2：伤害分解行（§5.2 标为 P0——"爽感的一半来自看懂这一下为什么这么大"；
# 同时是 ante 调参（ANTE_ALPHA_HP/ATK）的唯一 debug 依据）。
# 逐符号记录「基础 × 连线 × 克制 = 小计」，回合级乘区（护符/增益/强袭）在 _evaluate 汇总。
func _push_dmg_line(acc: Dictionary, sym: SymbolData, elem: String, flat, bonus, mult: int, em: float, v: float, crit: bool) -> void:
	if not acc.has("lines"):
		return
	var parts := []
	if bonus > 0:
		parts.append("基础%d(=%d+%d)" % [int(flat), int(sym.base), int(bonus)])
	else:
		parts.append("基础%d" % int(flat))
	if mult > 1:
		parts.append("连线%d" % mult)
	# S-结算核查：带元素的符号永远显式写出克制关系（含中性×1.0），让"抗性数值"不再隐形
	if elem != "none":
		if em > 1.0:
			parts.append("克制×%s" % ElementCounter.fmt_mult(em))
		elif em < 1.0:
			parts.append("抗性×%s" % ElementCounter.fmt_mult(em))
		else:
			parts.append("中性×1.0")
	var etxt = "" if elem == "none" else "·" + ElementCounter.label(elem)
	var line = "   %s %s%s  %s = %d" % [sym.label, sym.name, etxt, " × ".join(parts), int(round(v))]
	if crit:
		line += "（含三连追加 +%d）" % int(round(flat * em))
	acc["lines"].append(line)


# 结算：分两阶段（先防御/增益/状态，后攻击），接单向属性克制与强袭药剂。
func _evaluate() -> void:
	hud._clear_badges()
	var acc = { "dmg": 0, "shield": 0, "heal": 0, "status_stacks": {}, "special": 0, "lines": [] }
	_eval_adv = false
	_eval_dis = false

	# 按「符号 + 有效元素」计数（解决共享符号跨武器元素冲突；HUD 角标据此展示）
	var counts = {}
	for p in PAYLINES[0]:
		var sym: SymbolData = grid[p[0]][p[1]]
		var elem: String = grid_elem[p[0]][p[1]]
		var key: String = sym.resource_path + "|" + elem
		if not counts.has(key):
			counts[key] = [sym, elem, 0]
		counts[key][2] += 1
	# Phase C：先结算 buff 符号（本回合即生效，命中当回合就吃到增益）
	for key in counts:
		var s: SymbolData = counts[key][0]
		if s == TRASH_SYMBOL or s.kind != "buff":
			continue
		_grant_buff(s, counts[key][2])
	# 金币符号（常驻）：落在线上的金币直接转化为金币资源，不造成任何伤害
	for key in counts:
		var s: SymbolData = counts[key][0]
		if s == GOLD_SYMBOL:
			var g = GOLD_PER_COIN * counts[key][2]
			if g > 0:
				gold += g
				hud._log("💰 金币 +%d" % g)
				hud._popup("💰+%d" % g, Palette.POP_GOLD, hud._player_panel_anchor())
	# 再结算常规符号（此时 _contribute 读到的已是含新增益的加成，并按各自有效元素吃克制）
	for key in counts:
		var s: SymbolData = counts[key][0]
		var elem: String = counts[key][1]
		var c: int = counts[key][2]
		if s == TRASH_SYMBOL or s.kind == "buff" or s == GOLD_SYMBOL:
			continue
		if s.kind == "special" and c < 1:
			continue
		_contribute(s, c, acc, elem)

	# 匹配角标（×N，N>=2）
	hud._update_match_badges(counts)

	# —— 阶段 1：防御 / 增益 / 状态先落地 ——
	# Phase C：铁壁(shield)/回春(regen) 按回合生效，并入本回合护盾与治疗（F-0 聚合层）
	acc["shield"] += int(_agg_shield())
	acc["heal"] += int(_agg_regen())
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

	# —— 阶段 2：攻击结算（逐符号克制已在 _contribute 计入；此处只乘护符/强袭）——
	# Phase C：迅捷(damage_mult) 对本回合总伤害做乘算（F-0 聚合层，含护符乘区）
	var buff_mult = _agg_damage_mult()
	var assault = assault_next_spin
	var subtotal = acc["dmg"] + acc["special"]
	var total = int(subtotal * assault * buff_mult)
	assault_next_spin = 1
	# S2：输出伤害分解——逐符号明细 + 回合级乘区汇总（走中栏独立面板，不进战斗日志）
	if acc["lines"].is_empty():
		hud._clear_damage_breakdown()
	else:
		var blk := ["🔍 伤害分解"]
		blk.append_array(acc["lines"])
		var tail := []
		var cm = charm_damage_mult
		var bm = _buff_damage_mult()
		if cm != 1.0:
			tail.append("护符×%s" % ElementCounter.fmt_mult(cm))
		if bm != 1.0:
			tail.append("增益×%s" % ElementCounter.fmt_mult(bm))
		if assault != 1:
			tail.append("强袭×%s" % ElementCounter.fmt_mult(float(assault)))
		if tail.is_empty():
			blk.append("   合计 = %d" % total)
		else:
			blk.append("   小计 %d × %s = %d" % [int(round(subtotal)), " × ".join(tail), total])
		hud._show_damage_breakdown("\n".join(blk))
	if total > 0:
		enemy_hp -= total
		var elem_tag := ""
		if _eval_adv:
			elem_tag += " [克制]"
		if _eval_dis:
			elem_tag += " [抵抗]"
		if buff_mult != 1.0:
			elem_tag += "⚡"
		hud._popup("-%d%s" % [total, elem_tag], Palette.POP_DAMAGE, hud._enemy_panel_anchor())
		hud._log("连线造成 %d 伤害%s" % [total, elem_tag])
	await get_tree().create_timer(0.55).timeout
	# Phase C：回合末递减增益剩余回合
	_tick_buffs()


# ---------------------------------------------------------------------------
# 属性聚合层 (F-0) — 所有「修正轴」的统一查询入口
# ---------------------------------------------------------------------------
# 背景：M4 本局加成(run_*)、M6 护符(charm_*)、Phase C 增益(_buff_*) 各自独立地
# 散落在 _contribute / _evaluate / _build_pool 中，每加一类修正就要在三四处各插一刀。
# 本层把「加法标量 / 乘法标量 / 符号权重」三类轴统一成一组 _agg_* 查询，
# 调用方只认聚合层、不认具体来源。
#
# 新增一条修正轴（如 Phase F 词缀）只需在对应 _agg_* 末尾加一行求和，战斗结算零改动。
# 当前各 _affix_* 为占位（返回中性值），接入后改为遍历 player_affixes。
#
# 注意：本层只聚合「每符号 / 每回合」类修正。房开局护盾（守望护符 charm_room_shield
# / 守望结界 run_shield_next）与抗扰 / 净化上限等是「房间级」修正，仍在各自原位处理，
# 不进入此层。铁砧转轮升级(meta.weapon_upgrades)是「武器级」权重，在 _build_pool 内处理。
# ---------------------------------------------------------------------------
var player_affixes: Array = []   # Phase F 接入点：整备确认时填入武器实例词缀；当前空

# —— 加法型标量轴（多个来源直接相加）——
func _agg_power_flat() -> float:
	return float(run_power_bonus) + float(charm_power_bonus) + _buff_power() + _affix_power()

func _agg_shield() -> float:
	return _buff_shield() + _affix_shield() + float(charm_shield_trickle)


func _agg_regen() -> float:
	return _buff_regen() + _affix_regen()

# —— 乘法型轴（各乘区独立相乘，基值 1.0）——
func _agg_damage_mult() -> float:
	# 护符全局乘区（joker）× 增益乘区（Phase C）× 词缀乘区（占位）
	return charm_damage_mult * _buff_damage_mult() * _affix_damage_mult()

# —— 符号权重轴（本局符号灌注 + 全局词缀；武器级权重见 _build_pool）——
func _agg_symbol_weight_mod(sym: SymbolData) -> float:
	return float(run_symbol_bonus.get(sym.resource_path, 0.0)) + _affix_symbol_weight(sym)

# —— Phase F 词缀占位（当前返回中性值，接入后改为遍历 player_affixes 求和）——
func _affix_power() -> float:                     return 0.0
func _affix_shield() -> float:                    return 0.0
func _affix_regen() -> float:                     return 0.0
func _affix_damage_mult() -> float:               return 1.0
func _affix_symbol_weight(sym: SymbolData) -> float: return 0.0

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
		parts.append("%s+%d" % [STATUS_NAMES.get(st, st), stacks[st]])
	return "/".join(parts)


# ---------------------------------------------------------------------------
# 表现刷新
# ---------------------------------------------------------------------------
func _input(event) -> void:
	if in_loadout:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		if _spinning:
			_stop_next_reel()
		else:
			_on_spin_pressed()
