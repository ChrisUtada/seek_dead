class_name ShopSystem
extends RefCounted

# S6–S12 商店（买入 / 卖出 / 金币升级）——从 duel_controller.gd 抽出。
#
# 由 controller 在 _ready 处实例化并注入：ShopSystem.new(ctrl)。
# 约定（与 docs/[已完成]duel_controller拆分方案B.md 步骤3一致，延续步骤1/2 的写法）：
# - 局内金币 gold / 腰带 consumable_slots / meta 仍由 controller 持有，本子系统经 _ctrl.xxx 读写；
#   本局状态 gold_upgrades / paid_price / shop_offers 随本子系统走（方案B §4 状态归属表）。
# - 金币升级定义收敛于 GoldUpgradeDef Resource（resources/config/gold_upgrades/*.tres，扫描收集，加新升级零代码）。
# - 每级增量 per_level 随定义走；结算点经 track_level(id) / track_per_level(id) 读取（T3 6 轨道 + 动态锻造）。
# - 跨系统联动（授予后刷新 UI 等）留在 controller 编排层；本子系统不互调其他子系统。
# - ctrl 标类型 DuelController（已加 class_name），成员访问获得编译期检查。
# - 3117c6d 修复保持：买入仅 kind=="weapon"/"passive" 写 owned_*，skill 跳过（防 SkillData 进 owned_weapons 崩溃）。
# - 商店经济（价格表 / 随机浮动 / 下限 / 返现比）收敛于 ShopConfig Resource（resources/config/shop_config.tres），
#   策划可直接在 Inspector 调参，不再改代码。
# - 金币升级定义收敛于 GoldUpgradeDef Resource（resources/config/gold_upgrades/*.tres，扫描收集，加新升级零代码）。
# - 每级增量 per_level 随定义走；结算点经 track_level(id) / track_per_level(id) 读取（T3 6 轨道 + 动态锻造）。

const SHOP_CONFIG = preload("res://resources/config/shop_config.tres")   # 商店经济配置（.tres，可 Inspector 编辑）
const BALANCE = preload("res://resources/config/balance_config.tres")    # T22：平衡常量（slot_init / loadout_min 等）

var _ctrl: DuelController          # DuelController 实例（类型标注，编译期检查）
var shop_offers: Array[Dictionary] = []            # 当前商店货架（随机刷新）
var reroll_used := 0               # 本房间歇期已刷新次数（_enter_interroom 清零；价格 = reroll_base + used×step，上限 reroll_max）
var paid_price: Dictionary = {}        # path/uid -> 实际购入价（卖出返还约 50%；新一局清空）
var gold_upgrades: Dictionary = {}   # 局内金币升级等级（每局清零；键 = 轨道 id：power/line/shield/hp_max）
var _upgrade_defs: Array[GoldUpgradeDef] = []          # GoldUpgradeDef 资源列表（_init 扫描收集）

func _init(ctrl: DuelController) -> void:
	_ctrl = ctrl
	_upgrade_defs.assign(ResourceScan.scan_resources("res://resources/config/gold_upgrades/", "GoldUpgradeDef"))


# ---------------------------------------------------------------------------
# 局内清零（_full_reset 调用）
# ---------------------------------------------------------------------------

func reset_run() -> void:
	paid_price = {}
	gold_upgrades = {}
	reroll_used = 0


# ---------------------------------------------------------------------------
# 购入 / 卖出 / 金币升级
# ---------------------------------------------------------------------------

# 2026-08-07 替换购买：武器槽上限 2 后的换装——旧武器回 owned 图鉴（本局卸下），新武器进槽
func on_shop_buy_replace_pressed(offer: Dictionary, old_path: String) -> void:
	if offer["sold"]:
		return
	var arr = _ctrl._loadout_system.sel_arr("weapon")
	if arr.has(offer["path"]):
		_ctrl.hud._log("已拥有 %s，无法重复购买" % offer["name"])
		return
	if not arr.has(old_path):
		return
	var buy_price: int = offer.get("price", shop_price("weapon", -1, offer["path"]))   # 2026-08-10 fix：读货架锁定报价
	if _ctrl.gold < buy_price:
		_ctrl.hud._log("金币不足（需 %d）" % buy_price)
		return
	_ctrl.gold -= buy_price
	var old_name = _ctrl._shop_name(old_path, "weapon")
	arr.erase(old_path)
	arr.append(offer["path"])
	if not _ctrl.meta["owned_weapons"].has(offer["path"]):
		_ctrl.meta["owned_weapons"].append(offer["path"])
	paid_price[offer["path"]] = buy_price
	offer["sold"] = true
	_ctrl._build_pool(_ctrl.selected_loadout)   # 换装立即重建符号池
	_ctrl.hud._log("替换：%s → %s（-%d 金，余 %d）" % [old_name, offer["name"], buy_price, _ctrl.gold])
	_ctrl.invalidate_state()


func shop_price(kind: String, owned: int = -1, item_path: String = "") -> int:
	if owned < 0:
		# 消耗品按【腰带实占数】递增价（含商店重复购买同类），而非去重勾选数
		if kind == "active":
			owned = _ctrl.consumable_slots.size()
		else:
			owned = _ctrl._loadout_system.sel_arr(kind).size()
	# 金币是「买即开槽」的节奏闸门：价格随「当前持有数」递增。
	# 售出物品会减少持有数 → 重购价格回落，换装成本自然来自买卖价差（防刷价）。
	# 加价起点对齐各类初始配额（填满初始空位仍原价，从首次扩槽起逐级加价）。
	# 步进差异：护符最大（唯一收集乘区、须最贵）；增益次之（进池挤占转轮带最凶）；
	# 武器居中；消耗品最低。数值见 ShopConfig（resources/config/shop_config.tres）。
	# T6/T21：稀有度定价阶梯——base × rarity_price_mult[物品稀有度]（epic 武器 8×5=40，一局买不起两把）
	var base = SHOP_CONFIG.base_price.get(kind, SHOP_CONFIG.fallback_base)
	var rarity := "common"
	# 消耗品按腰带 uid（如 c1）传入时非资源路径——跳过 load（回落 common），避免刷报错
	if item_path.begins_with("res://"):
		var res: Resource = load(item_path)
		if res != null and "rarity" in res:
			rarity = String(res.get("rarity"))
	base = int(round(float(base) * float(SHOP_CONFIG.rarity_price_mult.get(rarity, 1.0))))
	var price = base + randi_range(SHOP_CONFIG.jitter_min, SHOP_CONFIG.jitter_max)
	var step = SHOP_CONFIG.step_price.get(kind, SHOP_CONFIG.fallback_step)
	price += max(0, owned - int(_ctrl.SLOT_INIT.get(kind, 1)) + 1) * step
	return max(SHOP_CONFIG.price_floor, price)


func shop_name(path: String, kind: String) -> String:
	var d = load(path)
	if d == null:
		return path.get_file().get_basename()
	match kind:
		"weapon": return (d as WeaponData).weapon_name if d is WeaponData else path.get_file().get_basename()
		"skill":  return (d as SkillData).buff_name if d is SkillData else path.get_file().get_basename()
		_:        return (d as ItemData).item_name if d is ItemData else path.get_file().get_basename()


func roll_shop() -> void:
	var candidates := []
	for p in _ctrl.WEAPON_POOL:
		# 2026-08-07：武器全池售卖（图鉴模型下 owned_weapons=全量，过滤=商店空；替换购买已支持换装）
		candidates.append({"path": p, "kind": "weapon"})
	for p in _ctrl.ITEM_POOL:
		var d = load(p)
		if d is ItemData:
			if d.category == "passive" and _ctrl.selected_charms.has(p):
				continue   # 护符：本局已带不上架（避免占位拒单）；已拥有但未带可买
			candidates.append({"path": p, "kind": d.category})   # 消耗品不过滤：腰带允许同类重复占格
	for p in _ctrl.SKILL_POOL:
		if _ctrl.selected_skills.has(p):
			continue   # 本局已带技能不上架（技能唯一持有、无 owned 池）
		candidates.append({"path": p, "kind": "skill"})
	candidates.shuffle()                      # 随机刷新，防背公式
	var n = min(candidates.size(), 6)
	shop_offers = []
	for i in n:
		var c = candidates[i]
		# 2026-08-10 fix：报价在货架生成时锁定（offer["price"]）——显示与购买统一读它，
		# 否则每次调用 shop_price() 的随机 jitter 会让价格点击后跳动
		shop_offers.append({"path": c["path"], "kind": c["kind"], "name": shop_name(c["path"], c["kind"]), "price": shop_price(c["kind"], -1, c["path"]), "sold": false})
	_ctrl.invalidate_state()


# 货架刷新（2026-08-09）：Balatro 式递增价 + 每房间歇期限次（双闸门防金币无限转化）。
# 迷宫回声（信物 2026-08-14）：每房间歇期前 N 次免费（价格 0，不占付费次数；之后照常计费递增）。
# 下一房预告（规划中）与刷新互为闭环：预告给目标、刷新给执行手段。
func free_reroll_count() -> int:
	return _ctrl.charm_free_reroll if _ctrl.deprived_level < 1 else 0


func reroll_price() -> int:
	var free: int = free_reroll_count()
	if reroll_used < free:
		return 0
	return SHOP_CONFIG.reroll_base + (reroll_used - free) * SHOP_CONFIG.reroll_step


func can_reroll() -> bool:
	return reroll_used < SHOP_CONFIG.reroll_max + free_reroll_count()


func on_shop_reroll_pressed() -> void:
	if not can_reroll():
		_ctrl.hud._log("刷新已达本房上限（%d 次）" % SHOP_CONFIG.reroll_max)
		return
	var price := reroll_price()
	if _ctrl.gold < price:
		_ctrl.hud._log("金币不足（刷新需 %d）" % price)
		return
	_ctrl.gold -= price
	reroll_used += 1
	roll_shop()
	_ctrl.hud._log("🔄 刷新货架（-%d 金，余 %d；下次刷新 %d 金）" % [price, _ctrl.gold, reroll_price()])
	_ctrl.invalidate_state()


func on_shop_buy_pressed(offer: Dictionary) -> void:
	if offer["sold"]:
		return
	var kind = offer["kind"]
	var buy_price := 0
	# 消耗品：腰带实例模型（每个格子独立，允许同类重复占格，上限 CONSUMABLE_CAP）
	if kind == "active":
		if _ctrl.consumable_slots.size() >= _ctrl.CONSUMABLE_CAP:
			_ctrl.hud._log("消耗品腰带已满 %d/%d，无法购买" % [_ctrl.consumable_slots.size(), _ctrl.CONSUMABLE_CAP])
			return
		buy_price = offer.get("price", shop_price(kind, -1, offer["path"]))   # 2026-08-10 fix：读货架锁定报价
		if _ctrl.gold < buy_price:
			_ctrl.hud._log("金币不足（需 %d）" % buy_price)
			return
		_ctrl.gold -= buy_price
		var cd: Resource = load(offer["path"])
		if cd != null:
			_ctrl._consumable_uid += 1
			var uid = "c%d" % _ctrl._consumable_uid
			_ctrl.consumable_slots.append({"path": offer["path"], "item_id": cd.item_id, "charges": cd.charges, "uid": uid})
			if not _ctrl.meta["owned_consumables"].has(offer["path"]):
				_ctrl.meta["owned_consumables"].append(offer["path"])
			paid_price[uid] = buy_price
			_ctrl._refresh_consumable_panel()
			_ctrl.hud._log("购买 %s（腰带 %d/%d，-%d 金，余 %d）" % [offer["name"], _ctrl.consumable_slots.size(), _ctrl.CONSUMABLE_CAP, buy_price, _ctrl.gold])
		else:
			_ctrl.hud._log("购买失败：资源缺失 %s" % offer["name"])
		offer["sold"] = true
		_ctrl.invalidate_state()
		return
	var arr = _ctrl._loadout_system.sel_arr(kind)
	if arr.has(offer["path"]):
		_ctrl.hud._log("已拥有 %s，无法重复购买" % offer["name"])
		return
	var w = arr.size()
	var cap = _ctrl._loadout_system.cat_max(kind)            # 该类当前上限
	# 「买即开槽」（四类通用）：该类槽满时，只要还能扩（进池类无天花板 / 不进池类未触顶），
	# 本次购买即扩槽 1 格；仅在「有天花板且已触顶」时才拒绝。
	if w >= cap and not _ctrl._loadout_system.can_grow_slot(kind):
		_ctrl.hud._log("%s槽位已满 %d/%s（已达天花板），无法购买" % [_ctrl._loadout_system.cat_name(kind), w, _ctrl._loadout_system.cap_text(kind)])
		return
	buy_price = offer.get("price", shop_price(kind, -1, offer["path"]))       # 2026-08-10 fix：读货架锁定报价（原每次重算含 jitter 随机 → 点击后价格跳动）
	if _ctrl.gold < buy_price:
		_ctrl.hud._log("金币不足（需 %d）" % buy_price)
		return
	_ctrl.gold -= buy_price
	arr.append(offer["path"])
	# 技能不进拥有池（读取走 SKILL_POOL），仅武器/护符写入 owned_*
	var owned_key = ""
	if kind == "weapon":
		owned_key = "owned_weapons"
	elif kind == "passive":
		owned_key = "owned_charms"
	if owned_key != "" and not _ctrl.meta[owned_key].has(offer["path"]):
		_ctrl.meta[owned_key].append(offer["path"])
	paid_price[offer["path"]] = buy_price   # 记录实际购入价，卖出时返还约50%
	offer["sold"] = true
	if w >= cap:                        # 本次是扩槽购买 → 该类槽 +1
		_ctrl._loadout_system.grow_slot(kind)
		_ctrl.hud._log("购买 %s（%s槽 +1 → %d/%s，-%d 金，余 %d）" % [offer["name"], _ctrl._loadout_system.cat_name(kind), _ctrl._loadout_system.cat_max(kind), _ctrl._loadout_system.cap_text(kind), buy_price, _ctrl.gold])
	else:
		_ctrl.hud._log("购买 %s（-%d 金，余 %d）" % [offer["name"], buy_price, _ctrl.gold])
	_ctrl.invalidate_state()   # 金币/腰带/槽位上限已变更


func sell_price(kind: String, path: String) -> int:
	# 卖出返还按 ShopConfig.sell_refund_ratio 比例（过高会刷金；过低则换装几乎免费）。
	# 未记录购入价（如 BOSS 免费掉落）时按当前购价同比例兜底。
	var paid = int(paid_price.get(path, -1))
	if paid < 0:
		paid = shop_price(kind, -1, path)
	return max(1, int(paid * SHOP_CONFIG.sell_refund_ratio))


func on_shop_sell_pressed(path: String, kind: String) -> void:
	var sell_refund := 0
	# 消耗品：按腰带格 uid 精准定位卖出（同类重复各占一格）
	if kind == "active":
		var target = -1
		for i in range(_ctrl.consumable_slots.size()):
			if _ctrl.consumable_slots[i]["uid"] == path:
				target = i
				break
		if target < 0:
			return
		var slot = _ctrl.consumable_slots[target]
		sell_refund = sell_price(kind, slot["uid"])
		_ctrl.gold += sell_refund
		_ctrl.consumable_slots.remove_at(target)
		paid_price.erase(slot["uid"])
		_ctrl._refresh_consumable_panel()
		_ctrl.hud._log("卖出 %s（+%d 金，腰带位释放）" % [shop_name(slot["path"], kind), sell_refund])
		_ctrl.invalidate_state()
		return
	var arr = _ctrl._loadout_system.sel_arr(kind)
	if not arr.has(path):
		return
	if kind == "weapon" and arr.size() <= BALANCE.loadout_min:
		_ctrl.hud._log("至少需保留 %d 把武器，无法卖出" % BALANCE.loadout_min)
		return
	sell_refund = sell_price(kind, path)
	_ctrl.gold += sell_refund
	arr.erase(path)
	paid_price.erase(path)
	if kind == "weapon" or kind == "skill":
		_ctrl._build_pool(_ctrl.selected_loadout)       # 重建符号池（稀释转轮带）
	elif kind == "passive":
		_ctrl._apply_charms()                      # 重算护符被动（伤害乘区等随持有变化）
	_ctrl.hud._log("卖出 %s（+%d 金，槽位释放）" % [shop_name(path, kind), sell_refund])
	_ctrl.invalidate_state()


# ---------------------------------------------------------------------------
# S12/T27 训练轨道（4 条 · 每局清零 · 消耗「训练点」（仅 BOSS 掉落），金币回归纯装备职能）
# 效果经聚合层(_agg_*)与 _start_room 读取；此处仅管等级/价格(训练点)/购买。
# 轨道（training/reel 静态 4 条，定义在 resources/config/gold_upgrades/*.tres，effect + per_level 数据驱动）：
#   power 训练：锋锐 / line 连线精通 / shield 训练：壁垒 / hp_max 训练：体魄
# 收敛决策（2026-08-07）：精准由武器 hit_rate 自带、回复走内容渠道，二轨删除；
#   T27：升级从金币改为训练点（BOSS 掉落），轨道上限收窄 3、锋锐每级 +4——升级与购买彻底解耦。
# 铁律（§7.4）：玩家层无伤害乘区——power（加算）+ line（连线乘区）即上限；乘区全留给 build 层。
# ---------------------------------------------------------------------------

func track_level(id: String) -> int:
	return int(gold_upgrades.get(id, 0))


func track_per_level(id: String) -> float:
	var d = _track_def(id)
	return d.get("per_level", 0.0) if d != null else 0.0


# 统一轨道定义（静态 .tres），返回同构 Dictionary
func _track_def(id: String) -> Dictionary:
	for d in _upgrade_defs:
		if d.id == id:
			return {"id": d.id, "effect": d.effect, "per_level": d.per_level, "bind": d.bind,
				"icon": d.icon, "name": d.name, "base": d.base, "step": d.step, "max": d.max}
	return {}


# 全部轨道 id：静态 .tres
func _all_track_ids() -> Array:
	var ids := []
	for d in _upgrade_defs:
		ids.append(d.id)
	return ids


func gold_upgrade_cost(id: String) -> int:
	# T27：升级只花训练点（固定每级 1 点），不再花金币
	return BALANCE.train_per_level


func gold_upgrade_desc(id: String, lvl: int) -> String:
	var d = _track_def(id)
	if d.is_empty():
		return ""
	var per = float(d["per_level"])
	match String(d["effect"]):
		"power":   return "本局所有伤害符号基础 +%d（当前 +%d）" % [int(per), int(lvl * per)]
		"line":    return "连线倍率 +%d（2连变×%d、3连变×%d，仅匹配生效）" % [int(per), 2 + int(per), 3 + int(per)]
		"shield":  return "每房开局护盾 +%d（当前 +%d）" % [int(per), int(lvl * per)]
		"hp_max":  return "生命上限 +%d（当前 +%d，升级即回满该增量）" % [int(per), int(lvl * per)]
	return ""


func gold_upgrade_defs() -> Array:
	var out := []
	for id in _all_track_ids():
		var d = _track_def(id)
		if d.is_empty():
			continue
		var lvl = gold_upgrades.get(id, 0)
		var cost = gold_upgrade_cost(id)
		var maxed = lvl >= int(d["max"])
		out.append({
			"id": id, "icon": d["icon"], "name": d["name"],
			"desc": gold_upgrade_desc(id, lvl), "level": lvl, "max": int(d["max"]),
			"cost": cost, "maxed": maxed, "can_afford": (not maxed) and _ctrl.train_points >= cost,
		})
	return out


func on_gold_upgrade_pressed(id: String) -> void:
	var d = _track_def(id)
	if d.is_empty():
		return
	var lvl = gold_upgrades.get(id, 0)
	if lvl >= int(d["max"]):
		_ctrl.hud._log("金币升级「%s」已满级" % d["name"])
		return
	var cost = gold_upgrade_cost(id)
	if _ctrl.train_points < cost:
		_ctrl.hud._log("训练点不足（%s 需 %d 点，现有 %d）" % [d["name"], cost, _ctrl.train_points])
		return
	_ctrl.train_points -= cost
	gold_upgrades[id] = lvl + 1
	_ctrl.hud._log("训练「%s」→ Lv%d（-%d 训练点，余 %d）" % [d["name"], gold_upgrades[id], cost, _ctrl.train_points])
	_ctrl.invalidate_state()
