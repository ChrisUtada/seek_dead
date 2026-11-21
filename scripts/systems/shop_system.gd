class_name ShopSystem
extends RefCounted

# S6–S12 商店（买入 / 卖出）——从 duel_controller.gd 抽出。
#
# 由 controller 在 _ready 处实例化并注入：ShopSystem.new(ctrl)。
# 约定（与 docs/[已完成]duel_controller拆分方案B.md 步骤3一致，延续步骤1/2 的写法）：
# - 局内金币 gold / 腰带 consumable_slots / meta 仍由 controller 持有，本子系统经 _ctrl.xxx 读写；
#   本局状态 paid_price / shop_offers 随本子系统走（方案B §4 状态归属表）。
# - 跨系统联动（授予后刷新 UI 等）留在 controller 编排层；本子系统不互调其他子系统。
# - ctrl 标类型 DuelController（已加 class_name），成员访问获得编译期检查。
# - 3117c6d 修复保持：买入仅 kind=="weapon"/"passive" 写 owned_*，skill 跳过（防 SkillData 进 owned_weapons 崩溃）。
# - 商店经济（价格表 / 随机浮动 / 下限 / 返现比）收敛于 ShopConfig Resource（resources/config/shop_config.tres），
#   策划可直接在 Inspector 调参，不再改代码。
# ⚠ 2026-08-14：训练点/四轨升级系统（GoldUpgradeDef / track_level / gold_upgrade_* / train_screen）已整体移除。

const SHOP_CONFIG = preload("res://resources/config/shop_config.tres")   # 商店经济配置（.tres，可 Inspector 编辑）
const BALANCE = preload("res://resources/config/balance_config.tres")    # T22：平衡常量（slot_init / loadout_min 等）

var _ctrl: DuelController          # DuelController 实例（类型标注，编译期检查）
var shop_offers: Array[Dictionary] = []            # 当前商店货架（随机刷新）
var reroll_used := 0               # 本房间歇期已刷新次数（_enter_interroom 清零；价格 = reroll_base + used×step，上限 reroll_max）
var paid_price: Dictionary = {}        # path/uid -> 实际购入价（卖出返还约 50%；新一局清空）

func _init(ctrl: DuelController) -> void:
	_ctrl = ctrl


# ---------------------------------------------------------------------------
# 局内清零（_full_reset 调用）
# ---------------------------------------------------------------------------

func reset_run() -> void:
	paid_price = {}
	reroll_used = 0


# ---------------------------------------------------------------------------
# 购入 / 卖出 / 金币升级
# ---------------------------------------------------------------------------

# 2026-08-07 替换购买：武器槽上限 2 后的换装——旧武器回 owned 图鉴（本局卸下），新武器进槽
# source: "shop"（默认）/ "camp"（营地补给复用同一购买路径，仅用于自动记录的来源区分）。
func on_shop_buy_replace_pressed(offer: Dictionary, old_path: String, source: String = "shop") -> void:
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
	# 唯一替换入口：原位替换，槽位通用成长不变（不能 erase+append，否则旧武器被挪到末尾）。
	var slot: int = _ctrl.selected_loadout.find(old_path)
	if slot < 0 or not _ctrl.replace_weapon_at_slot(slot, String(offer["path"])):
		_ctrl.hud._log("替换失败：目标槽位无效")
		return
	if not _ctrl.meta["owned_weapons"].has(offer["path"]):
		_ctrl.meta["owned_weapons"].append(offer["path"])
		_ctrl._career.check_collection_milestones()
	_ctrl._meta_store.record_source(offer["path"], _ctrl._item_source())   # G2-01：替换购买也记来源
	paid_price[offer["path"]] = buy_price
	offer["sold"] = true
	if _ctrl._telemetry != null:
		_ctrl._telemetry.on_weapon_swap()   # M1-06：商店换装计入替换率
	if _ctrl._journal != null:
		_journal_shop_note(offer, buy_price, source)
		_ctrl._journal.note_weapon_change(String(old_name), String(offer["name"]), "营地" if source == "camp" else "商店")
	_ctrl._build_pool(_ctrl.selected_loadout)   # 换装立即重建符号池
	_ctrl.hud._log("替换：%s → %s（-%d 金，余 %d）" % [old_name, offer["name"], buy_price, _ctrl.gold])
	_ensure_trim_offer()
	_ctrl.invalidate_state()


# B 方案：精简剪每幕常驻一格 —— 它是带子变胖的唯一解药，不能靠掉落运气。
const TRIM_ITEM_PATH := "res://resources/consumables/trim_scissors.tres"


func _ensure_trim_offer() -> void:
	for o in shop_offers:
		if String(o.get("path", "")) == TRIM_ITEM_PATH:
			return
	if shop_offers.is_empty():
		return
	var k := _shop_kind(TRIM_ITEM_PATH)
	shop_offers[shop_offers.size() - 1] = {
		"path": TRIM_ITEM_PATH, "kind": k, "name": shop_name(TRIM_ITEM_PATH, k),
		"price": shop_price(k, -1, TRIM_ITEM_PATH), "sold": false,
	}


# G5 工具：自动记录购买（source 只区分商店/营地，不改变购买逻辑）。
func _journal_shop_note(offer: Dictionary, price: int, source: String) -> void:
	if _ctrl._journal == null:
		return
	var nm := String(offer.get("name", ""))
	var kind := String(offer.get("kind", ""))
	if source == "camp":
		_ctrl._journal.note_camp(nm, kind, price)
	else:
		_ctrl._journal.note_shop(nm, kind, price)


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
	# F-09：按 run 种子 + 物品路径确定性生成 jitter，替代随机 randi_range。
	# 同局同物品始终同价；不同物品/不同局仍有变化；分布仍为 [min,max] 均匀，经济基线不变。
	# 不消耗战斗/奖励 RNG——反复打开商店或重生成货架不再改变随机流。
	var jitter_min: int = int(SHOP_CONFIG.jitter_min)
	var jitter_max: int = int(SHOP_CONFIG.jitter_max)
	var span: int = maxi(1, jitter_max - jitter_min + 1)
	var h: int = String(item_path).hash() ^ int(_ctrl.shop_run_seed)
	var jitter: int = jitter_min + posmod(h, span)
	var price = base + jitter
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
	# Step 3：货架品质不再按物品稀有度加权随机，改读来源表配套的确定性阶梯
	# （每幕 6 格：越深rare/epic越多，见 BalanceConfig.loot_shop_ladder）。
	# 保留旧过滤语义：本局已带护符/技能不上架；BOSS 信物不进商店；消耗品允许同类重复。
	var act: int = maxi(1, mini(3, int(_ctrl.current_act)))
	var exclude: Array = []
	exclude.append_array(_ctrl.selected_charms)
	exclude.append_array(_ctrl.selected_skills)
	var ladder: Array = _ctrl._reward_system.roll_shop_ladder(act, {"exclude": exclude})
	shop_offers = []
	for slot in ladder:
		if not bool(slot.get("ok", false)):
			continue
		var p := String(slot["path"])
		var kind := _shop_kind(p)
		if kind == "":
			continue
		# 2026-08-10 fix：报价在货架生成时锁定（offer["price"]）——显示与购买统一读它，
		# 否则每次调用 shop_price() 的随机 jitter 会让价格点击后跳动
		shop_offers.append({"path": p, "kind": kind, "name": shop_name(p, kind), "price": shop_price(kind, -1, p), "sold": false})
	_ctrl.invalidate_state()


# 货架条目类别（按资源类型判定，避免依赖 controller 的候选池裁剪）。
func _shop_kind(path: String) -> String:
	var d: Resource = load(path)
	if d is WeaponData:
		return "weapon"
	if d is SkillData:
		return "skill"
	if d is ItemData:
		return String(d.category)
	return ""


# 货架刷新（2026-08-09）：Balatro 式递增价 + 每房间歇期限次（双闸门防金币无限转化）。
# 迷宫回声（信物 2026-08-14）：每房间歇期前 N 次免费（价格 0，不占付费次数；之后照常计费递增）。
# 下一房预告（规划中）与刷新互为闭环：预告给目标、刷新给执行手段。
func free_reroll_count() -> int:
	return _ctrl.charm_free_reroll if _ctrl.deprived_level < 1 else 0   # 免费刷新来自信物「迷宫回声」；技艺「精打细算」已移除


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


func on_shop_buy_pressed(offer: Dictionary, source: String = "shop") -> void:
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
			if _ctrl._journal != null:
				_journal_shop_note(offer, buy_price, source)
			_ctrl._refresh_consumable_panel()
			_ctrl.hud._log("购买 %s（腰带 %d/%d，-%d 金，余 %d）" % [offer["name"], _ctrl.consumable_slots.size(), _ctrl.CONSUMABLE_CAP, buy_price, _ctrl.gold])
		else:
			_ctrl.hud._log("购买失败：资源缺失 %s" % offer["name"])
		offer["sold"] = true
		_ctrl.invalidate_state()
		return
	# F-16（2026-11-22 修正）：购买校验与卡面同源——只看本局持有（当前装备+本局仓库），
	# 局外解锁不算；直接调用购买函数也必须拒绝本局重复物品，不依赖按钮禁用。
	if _ctrl._loadout_system.is_held_this_run(kind, offer["path"]):
		_ctrl.hud._log("%s%s，无法重复购买" % [
			_ctrl._loadout_system.held_status_text(kind, offer["path"]), offer["name"]])
		return
	var arr = _ctrl._loadout_system.sel_arr(kind)
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
	# G7-C：技能也写入独立收藏池 owned_skills（整备/图鉴读取）；武器/护符照旧。
	var owned_key = ""
	if kind == "weapon":
		owned_key = "owned_weapons"
	elif kind == "passive":
		owned_key = "owned_charms"
	elif kind == "skill":
		owned_key = "owned_skills"
	if owned_key != "":
		if not _ctrl.meta[owned_key].has(offer["path"]):
			_ctrl.meta[owned_key].append(offer["path"])
			# M1-03：图鉴里程碑按真实收集进度结算（商店新件也计入，不再只在铁砧处触发）
			_ctrl._career.check_collection_milestones()
		_ctrl._meta_store.record_source(offer["path"], _ctrl._item_source())   # G2-01：来源记录
	paid_price[offer["path"]] = buy_price   # 记录实际购入价，卖出时返还约50%
	offer["sold"] = true
	if _ctrl._journal != null:
		_journal_shop_note(offer, buy_price, source)
	if w >= cap:                        # 本次是扩槽购买 → 该类槽 +1
		_ctrl._loadout_system.grow_slot(kind)
		_ctrl.hud._log("购买 %s（%s槽 +1 → %d/%s，-%d 金，余 %d）" % [offer["name"], _ctrl._loadout_system.cat_name(kind), _ctrl._loadout_system.cat_max(kind), _ctrl._loadout_system.cap_text(kind), buy_price, _ctrl.gold])
	else:
		_ctrl.hud._log("购买 %s（-%d 金，余 %d）" % [offer["name"], buy_price, _ctrl.gold])
	_ctrl.invalidate_state()   # 金币/腰带/槽位上限已变更


func sell_price(kind: String, path: String) -> int:
	# 卖出返还按 ShopConfig.sell_refund_ratio 比例（过高会刷金；过低则换装几乎免费）。
	# 无购入价（BOSS/宝箱免费掉落、腰带满折算）走固定低价，避免按购价 50% 变现白嫖。
	var paid = int(paid_price.get(path, -1))
	if paid < 0:
		return max(1, int(SHOP_CONFIG.free_item_sell_price))
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


# ⚠ 2026-08-14 训练点/四轨升级系统已整体移除（docs/训练轨道_成长频率增强_执行方案.md 弃案记录）：
# 四轨（锋锐/连线/壁垒/体魄）属 RPG 属性点框架残留，数值贡献已由奖励 9 类 + 护符 34 件 + 消耗品覆盖，
# 成长感走"装备收集 + 符号构筑"统一语言。训练房（train_screen）、gold_upgrades/*.tres、
# GoldUpgradeDef、track_level/track_per_level/gold_upgrade_defs/on_gold_upgrade_pressed 均已删。
