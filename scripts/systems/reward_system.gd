class_name RewardSystem
extends RefCounted

# T22：平衡常量收敛于 BalanceConfig（balance_config.tres）
const BALANCE = preload("res://resources/config/balance_config.tres")

# M4 房奖励 / 精英战前补给 / BOSS 战利品 / 局末元进度三选一——从 duel_controller.gd 抽出。
#
# 由 controller 在 _ready 处实例化并注入：RewardSystem.new(ctrl)。
# 约定（与 docs/[已完成]duel_controller拆分方案B.md 步骤4一致，延续步骤1–3 的写法）：
# - reward_choices / reward_is_boss 仍由 controller 持有（HUD 直读直写），本子系统只填充不持有；
#   本局加成层 run_symbol_bonus / run_power_bonus / run_shield_next 随本子系统走（方案B §4 状态归属表）。
# - @export 常量（META_ANVIL_BONUS / META_CHOICE_COUNT / REWARD_POOL / ELITE_REWARD_POOL 等）留
#   controller（RefCounted 无法在 Inspector 编辑），本子系统动态读 _ctrl.xxx。
# - 跨系统联动（奖励后推进房间 / 元进度生效后开新局 _full_reset / UI 刷新）留在 controller 编排层；
#   本子系统不互调其他子系统。
# - ctrl 标类型 DuelController（已加 class_name），成员访问获得编译期检查。

var _ctrl: DuelController          # DuelController 实例（类型标注，编译期检查）
var run_symbol_bonus: Dictionary = {}   # resource_path -> 额外权重（本局符号灌注，房奖励）
var run_power_bonus: int = 0            # 本局符号基础伤害加成（房奖励：攻击研磨）
var run_shield_next: int = 0            # 进入下一房时获得的护盾（房奖励：守望结界 / 精英备战）
var choice_payloads: Array[Dictionary] = []   # M1-01：与 reward_choices 按 index 对齐的预确定结果 {kind,path,title,desc}
var _acq_cache: Dictionary = {}         # path -> {w, hi}：Legacy 获取权重缓存（仅营地付费补给货架；探索已于 Step 5 迁移）
var _loot: LootPool                     # Step 3：统一来源品质池（专用 RNG，不消耗地图 RNG）
var _loot_offer: LootOffer              # Step 4：同层三选一（一次定层，重抽不重抽品质）

func _init(ctrl: DuelController) -> void:
	_ctrl = ctrl
	_loot = LootPool.new(ctrl)


# ---------------------------------------------------------------------------
# 局内清零（_full_reset 调用）
# ---------------------------------------------------------------------------

func reset_run() -> void:
	run_symbol_bonus = {}
	run_power_bonus = 0
	run_shield_next = 0
	if _loot != null:
		_loot.reset_run()   # 本局来源品质抽取的专用种子（只取一次，之后不碰地图 RNG）
	_ctrl.invalidate_state()


# ---------------------------------------------------------------------------
# 局末元进度三选一（膨胀双轨：武器 base 线性 × 护符乘数增值，持久跨局）
# ---------------------------------------------------------------------------

func roll_meta_choices() -> Array:
	# T6：武器/护符/命中率等 per-item 旋钮入口已退役（§6 铁砧纯 gacha 定案）。
	# 元进度三选一只保留「铁砧点数」兜底候选，避免给出无生效通道的假选项。
	var meta_pool := [{
		"kind": "anvil", "path": "",
		"icon": "🔨", "label": "铁砧点数 +%d" % BALANCE.meta_anvil_bonus,
		"desc": "永久铁砧点数，用于铁砧抽取装备（盘外成长）",
	}]
	return meta_pool.slice(0, BALANCE.meta_choice_count)   # 三选一：候选不足时全出


func on_meta_choice_chosen(opt: Dictionary) -> void:
	match opt["kind"]:
		"anvil":
			_ctrl.meta["anvil_points"] += BALANCE.meta_anvil_bonus
			_ctrl.hud._log("元进度：铁砧点数 +%d（共 %d）" % [BALANCE.meta_anvil_bonus, _ctrl.meta["anvil_points"]])
	_ctrl._meta_store.save_meta()   # 元进度持久落盘；开新局（_full_reset）由 controller 编排层负责


# ---------------------------------------------------------------------------
# 房奖励三选一（Roguelike 构筑）
# ---------------------------------------------------------------------------
# 胜利奖励方案（2026-08-13，见 docs/胜利奖励方案.md）：
# - 候选池 9 类（5 数值 + gold 经济 + consumable/weapon 构筑 + maxhp_heal 双效），三档稀有度加权（common 50 / uncommon 30 / rare 20，幕三 rare 升至 30）
# - 组合保证：3 张里至少 1 张恢复/防御向（def）+ 至少 1 张输出/构筑向（atk）
# - 按幕分层：幕一教学期不出 weapon（构筑武器）
const REWARD_TAG := {
	"heal": "def", "maxhp": "def", "shield": "def",
	"power": "atk", "symbol": "atk", "gold": "atk", "consumable": "atk", "weapon": "atk",
}

func roll_rewards() -> Array:
	var act: int = _ctrl.ROOMS[_ctrl.room_index].act if (_ctrl.room_index >= 0 and _ctrl.room_index < _ctrl.ROOMS.size()) else 1
	var pool: Array = build_reward_pool(act)
	var def_pool: Array = pool.filter(func(rw): return REWARD_TAG.get(rw.id, "") == "def")
	var atk_pool: Array = pool.filter(func(rw): return REWARD_TAG.get(rw.id, "") == "atk")
	var out := []
	var first: RewardData = _weighted_pick(def_pool, act)
	if first != null:
		out.append(first)
	var second: RewardData = _weighted_pick(atk_pool, act)
	if second != null:
		out.append(second)
	var rest: Array = pool.duplicate()
	rest.erase(first)
	rest.erase(second)
	var third: RewardData = _weighted_pick(rest, act)
	if third != null:
		out.append(third)
	_fill_reward_payloads(out)
	return out


# 房奖励候选池（M1-01）：幕一教学期不出构筑武器；
# 武器槽满（2 把）不再把武器卡排除——改为「展示具体武器 + 选择时走替换弹层」。
# M1-02：符号灌注若没有任何「能让转轮带格数真正变多」的候选，则不进入候选池。
func build_reward_pool(act: int) -> Array:
	var pool: Array = _ctrl.REWARD_POOL.duplicate()
	if act < 2:
		pool = pool.filter(func(rw): return rw.id != "weapon")
	if symbol_infusions().is_empty():
		pool = pool.filter(func(rw): return rw.id != "symbol")
	return pool


# 与 reward_choices 对齐的预确定结果（无 payload 的奖励返回空字典）
func payload_at(index: int) -> Dictionary:
	if index < 0 or index >= choice_payloads.size():
		return {}
	return choice_payloads[index]


func _fill_reward_payloads(choices: Array) -> void:
	choice_payloads = []
	for rw in choices:
		var pl := {}
		if rw != null:
			match rw.id:
				"weapon":
					pl = _weapon_payload()
				"symbol":
					pl = _symbol_payload()
				"consumable":
					pl = _consumable_payload()
		choice_payloads.append(pl)


# 武器奖励预确定：按当前来源品质表抽具体武器（展示前定死，确认后不再随机）
func pick_reward_weapon_path() -> String:
	var res: Dictionary = _loot.roll(_current_source(), _current_act(), {
		"category": "weapon",
		"exclude": _ctrl.selected_loadout,
	})
	return String(res.get("path", ""))


# Step 5：探索来源（宝箱 / 搜寻 / 棋盘装备格）。
# 品质只来自 chest 来源行；rng 由棋盘生成器持有（同种子可复现），
# 不消耗战斗/奖励 RNG 流，也不写 meta / 装配。
# 抽中的品质层在该类别下没有合法候选时，只在同一来源表内按原权重改抽一个「有候选」的层：
# 不跨来源、不凭空提层；整类都为空才返回 ""（节点按既有规则折算金币）。
func pick_explore_loot(category: String, act: int, rng: RandomNumberGenerator,
		exclude: Array = []) -> String:
	if rng == null:
		return ""
	var opts := {"category": category, "include_relics": false, "exclude": exclude}
	var quality := LootSourceTable.roll_quality("chest", act, rng)
	if quality == "":
		return ""
	var tier: Dictionary = _loot.tier_items("chest", act, quality, opts)
	if not bool(tier["ok"]):
		var avail := _explore_available_qualities("chest", act, opts)
		if avail.is_empty():
			return ""
		quality = _roll_quality_from(avail, rng)
		if quality == "":
			return ""
		tier = _loot.tier_items("chest", act, quality, opts)
		if not bool(tier["ok"]):
			return ""
	var items: Array = tier["items"]
	return String(items[rng.randi_range(0, items.size() - 1)])


# 探索来源中「该类别确实有候选」的品质层 → 原表权重（供空层改抽，不改变来源）。
func _explore_available_qualities(source: String, act: int, opts: Dictionary) -> Dictionary:
	var weights: Dictionary = LootSourceTable.weights_for(source, act).get("weights", {})
	var out := {}
	for q in LootSourceTable.QUALITIES:
		if int(weights.get(q, 0)) <= 0:
			continue
		var tier: Dictionary = _loot.tier_items(source, act, q, opts)
		if bool(tier["ok"]):
			out[q] = int(weights[q])
	return out


# 按给定权重抽一个品质（权重来自来源表，已剔除空层）。
func _roll_quality_from(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0
	for q in LootSourceTable.QUALITIES:
		total += int(weights.get(q, 0))
	if total <= 0:
		return ""
	var roll := rng.randf() * float(total)
	for q in LootSourceTable.QUALITIES:
		roll -= float(weights.get(q, 0))
		if roll <= 0.0:
			return q
	return LootSourceTable.QUALITIES[LootSourceTable.QUALITIES.size() - 1]


func _weapon_payload() -> Dictionary:
	var p := pick_reward_weapon_path()
	if p == "":
		return {}
	var wd: WeaponData = load(p)
	var nm: String = wd.weapon_name if wd != null else p.get_file().get_basename()
	return {
		"kind": "weapon", "path": p,
		"title": "武器 · %s" % nm,
		"desc": "加入转轮带；武器槽满则替换",
	}


# M1-02 符号灌注预确定：候选只收「灌注后转轮带格数真的变多」的 damage 符号。
# 展示时即定死具体符号 + 实际格数变化；确认后不再二次随机；无有效变化则整张卡不进候选。
func symbol_infusions() -> Array:
	var out := []
	var seen := {}
	var bonus := float(_symbol_bonus_value())
	for it in _ctrl.pool_items:
		for s in it["syms"]:
			var sym: SymbolData = s[0]
			if sym == null or sym == _ctrl.TRASH_SYMBOL or sym.kind != "damage":
				continue
			if seen.has(sym.resource_path):
				continue
			seen[sym.resource_path] = true
			var before: int = _symbol_cells(sym, 0.0)
			var after: int = _symbol_cells(sym, bonus)
			if after > before:
				out.append({"path": sym.resource_path, "sym": sym, "before": before, "after": after})
	return out


# 该符号在当前装备集合下实际占用的转轮带格数（口径与 reel_system.build_strips 一致：
# 同 (符号|有效元素) 聚合权重 → 档位 2/3/4；品质与来源数量不参与；零权重不占格）。
# Step 2：这里不再读取物品 rarity，灌注预览与真实带子对同一 Build 永远一致。
func _symbol_cells(sym: SymbolData, extra: float) -> int:
	var grouped := {}
	for it in _ctrl.pool_items:
		for s in it["syms"]:
			var csym: SymbolData = s[0]
			if csym == null or csym.resource_path != sym.resource_path:
				continue
			var w: float = maxf(0.0, float(s[1]) + _ctrl.combat.agg_symbol_weight_mod(csym) + _ctrl._synergy_system.weight_mod(csym) + extra)
			if w <= 0.0:
				continue
			var key := String(s[2])
			grouped[key] = float(grouped.get(key, 0.0)) + w
	var total := 0
	for key in grouped:
		total += ReelSystem.cells_for(float(grouped[key]))
	return total


func _symbol_bonus_value() -> int:
	var rd: RewardData = _find_reward("symbol")
	return rd.value if rd != null else 0


func _symbol_payload() -> Dictionary:
	var cands: Array = symbol_infusions()
	if cands.is_empty():
		return {}
	var pick: Dictionary = cands[randi() % cands.size()]
	var sym: SymbolData = pick["sym"]
	return {
		"kind": "symbol", "path": sym.resource_path,
		"title": "符号 · %s 权重+%d" % [sym.label, _symbol_bonus_value()],
		"desc": "转轮带 %d 格 → %d 格（本局生效）" % [int(pick["before"]), int(pick["after"])],
	}


func _consumable_payload() -> Dictionary:
	var path := pick_active_item_path()
	if path == "":
		return {}
	var cd: ItemData = load(path)
	var nm: String = cd.item_name if cd != null else path.get_file().get_basename()
	var desc := ""
	if _ctrl.consumable_slots.size() >= _ctrl.CONSUMABLE_CAP:
		desc = "腰带已满 → 折算金币 +%d" % _ctrl._sell_price("active", path)
	elif cd != null:
		desc = "入腰带：%s" % cd.description
	else:
		desc = "入腰带"
	return {"kind": "consumable", "path": path, "title": "消耗品 · %s" % nm, "desc": desc}


# 消耗品奖励预确定：按当前来源品质表抽一件 active（腰带允许同类重复，不排除已带）
func pick_active_item_path() -> String:
	var res: Dictionary = _loot.roll(_current_source(), _current_act(), {"category": "active"})
	return String(res.get("path", ""))


# 当前房间对应的来源（普通/精英/BOSS）；未知房间按普通战处理。
func _current_source() -> String:
	if _ctrl.room_index >= 0 and _ctrl.room_index < _ctrl.ROOMS.size():
		var k := String(_ctrl.ROOMS[_ctrl.room_index].kind)
		if k == "normal" or k == "elite" or k == "boss":
			return k
	return "normal"


# Step 3/5：商店货架——确定性品质阶梯 + 确定性类别序列（不走随机来源表，也不消耗地图 RNG）。
func roll_shop_ladder(act: int, opts: Dictionary = {}) -> Array:
	var merged := opts.duplicate(true)
	if not merged.has("categories"):
		merged["categories"] = LootSourceTable.shop_categories(act)
	return _loot.roll_ladder(act, LootSourceTable.shop_tiers(act), merged)


# ---------------------------------------------------------------------------
# Step 4：同层三选一（生成 / 冻结 / 重抽 / 跳过）
# ---------------------------------------------------------------------------
# 返回 {ok, reason, quality, options, skip}；options 与 skip 在 build 时冻结。
# 重抽沿用同一品质层，不重新抽品质；跳过的金币值在 build 时已写死。
func build_loot_offer(source: String, act: int, opts: Dictionary = {}, forced_quality: String = "") -> Dictionary:
	if _loot_offer == null:
		_loot_offer = LootOffer.new(_ctrl, _loot)
	return _loot_offer.build(source, act, opts, forced_quality)


func reroll_loot_offer() -> Dictionary:
	if _loot_offer == null:
		return {"ok": false, "reason": "no_offer", "quality": "", "options": [], "skip": {}}
	return _loot_offer.reroll()


func loot_offer_skip() -> Dictionary:
	if _loot_offer == null:
		return {}
	return _loot_offer.skip_result()


# 新武器写入局外收藏（图鉴/开局池）；落盘时机与商店一致（局末统一保存）
func remember_weapon(path: String) -> void:
	if path == "":
		return
	if not _ctrl.meta["owned_weapons"].has(path):
		_ctrl.meta["owned_weapons"].append(path)
		_ctrl._anvil_system.check_collection_milestones()   # M1-03：按真实收集进度结算图鉴里程碑
	_ctrl._meta_store.record_source(path, _ctrl._item_source())   # G2-01：来源记录


# G2-01：护符获得后写入图鉴/开局池；来源记录与武器同一口径。
func remember_charm(path: String) -> void:
	if path == "":
		return
	if not _ctrl.meta["owned_charms"].has(path):
		_ctrl.meta["owned_charms"].append(path)
	_ctrl._meta_store.record_source(path, _ctrl._item_source())


# Step 3：奖励卡「类型」不再按 RewardData.rarity 加权——物品品质与奖励卡类型是两层随机，
# 品质由来源表在候选池层决定；这里只负责在合法类型里等概率取一张（同层的具体物品由 payload 定）。
func _weighted_pick(pool: Array, _act: int) -> RewardData:
	if pool.is_empty():
		return null
	return pool[randi() % pool.size()]


# T6 精英房「战前补给」：2 固定（金币囤/铁砧点）+ 1 动态高品质位（rare 构筑/大数值——胜利奖励方案 2026-08-13）
func roll_elite_rewards() -> Array:
	var out := []
	for rw in _ctrl.ELITE_REWARD_POOL:
		if rw.id == "elite_gold" or rw.id == "elite_anvil":
			out.append(rw)
	var act: int = _ctrl.ROOMS[_ctrl.room_index].act if (_ctrl.room_index >= 0 and _ctrl.room_index < _ctrl.ROOMS.size()) else 1
	var high_pool: Array = []
	for rw in _ctrl.REWARD_POOL:
		# M1-01：武器槽满不再排除武器（选择时走替换）
		if rw.id in ["weapon", "consumable", "maxhp_heal"]:
			high_pool.append(rw)
	var bonus: RewardData = _weighted_pick(high_pool, act)
	if bonus != null:
		out.append(bonus)
	_fill_reward_payloads(out)
	return out


# BOSS 战利品：先按来源表（boss）确定品质，再在主题池的同品质层内无放回抽至多 3 把。
# 主题过滤保留；不再使用 acquisition_weight / boss_depth_bias（Step 3 起来源表是唯一品质概率）。
# 同层不足 3 把时按实际数量返回，空层返回明确原因（Step 4 再补同层转化）。
func roll_boss_rewards(room) -> Array:
	var cands := []
	# ① 主题新武器：房间指定池；真·最终没有掉落池 → 明确空主题；非最终未指定池 → 全部 boss 来源武器。
	var opts := {"category": "weapon", "exclude": _ctrl.selected_loadout}
	if room.final_boss:
		opts["theme"] = []
	elif room.boss_reward_weapons.size() > 0:
		opts["theme"] = room.boss_reward_weapons
	# M4-01 demo 白名单由 LootPool 统一过滤，不在这里二次裁剪
	var act: int = maxi(1, mini(3, int(room.act)))
	var picked: Dictionary = _loot.roll_n("boss", act, 3, opts)
	var picked_weapons: Array = picked.get("paths", [])
	for p in picked_weapons:
		var wd: WeaponData = load(p)
		var elem = wd.element if wd != null else "none"
		cands.append({
			"kind": "boss_weapon", "path": p,
			"icon": ElementCounter.label(elem),
			"label": (wd.weapon_name if wd != null else p.get_file().get_basename()),
			"desc": "新武器 · 进转轮带",
		})
	# ② Boss 信物：占护符槽 1/3（CHARM_CAP），护符槽满则不出
	if room.boss_relic_path != "" and _ctrl._loadout_system.sel_arr("passive").size() < _ctrl._loadout_system.cat_max("passive"):
		var rd: ItemData = load(room.boss_relic_path)
		cands.append({
			"kind": "boss_relic", "path": room.boss_relic_path,
			"icon": (rd.icon if rd != null else "🏆"),
			"label": (rd.item_name if rd != null else "Boss 信物"),
			"desc": "信物 · 占护符槽",
			"tip": (rd.description if rd != null else "专属信物 · 占护符槽"),
		})
	_loot.shuffle_in_place(cands)   # 展示顺序随机（抽取本身已定层，不消耗地图 RNG）
	# 空池保底（2026-08-14，docs/BOSS信物_设计方案.md §4）：武器槽满 2 + 护符槽满/无信物
	# → 两来源全被拦截，注入铁砧点兜底卡，战利品永不空屏
	if cands.is_empty():
		cands.append({"kind": "boss_anvil", "path": "", "icon": "🔨",
			"label": "铁砧结晶", "desc": "铁砧点数 +%d（跨局）" % BALANCE.boss_anvil_bonus,
			"tip": "敌库已空（武器/护符槽满），改赏铁砧点数"})
	var out := []
	for i in min(3, cands.size()):
		out.append(cands[i])
	return out


# ---------------------------------------------------------------------------
# M1 战后成长槽位（补给 / 构筑）
# ---------------------------------------------------------------------------
# 与旧「三张同池随机」不同：按槽位分别抽一张，且补给位永不与构筑位同 ID。
# 候选在展示前定死具体物品与真实变化（payload），确认后不再随机。

func reward_by_id(id: String) -> RewardData:
	return _find_reward(id)


func _current_act() -> int:
	if _ctrl.room_index >= 0 and _ctrl.room_index < _ctrl.ROOMS.size():
		return int(_ctrl.ROOMS[_ctrl.room_index].act)
	return 1


# 返回 [补给, 构筑] 两张 RewardData，并填充与索引对齐的 payload。
func roll_slot_rewards(kind: String) -> Array:
	var act: int = _current_act()
	var supply: Array = _slot_supply_pool(kind)
	var build: Array = _slot_build_pool(kind, act)
	var out: Array = []
	var s: RewardData = _weighted_pick(supply, act)
	var b: RewardData = _weighted_pick(build, act)
	out.append(s if s != null else _find_reward("maxhp"))
	out.append(b if b != null else _find_reward("power"))
	_fill_slot_payloads(out)
	# 消耗品无有效候选时退回最大 HP，避免出现没有具体物品的空卡。
	for i in range(out.size()):
		if String(out[i].id) == "consumable" and choice_payloads[i].is_empty():
			out[i] = _find_reward("maxhp")
			choice_payloads[i] = _slot_payload(out[i])
	return out


# 补给位：生存与资源下限。满血时不提供纯治疗（§4.4）。
func _slot_supply_pool(kind: String) -> Array:
	var ids: Array[String] = ["maxhp", "maxhp_heal", "shield", "gold", "consumable"]
	if _ctrl.player_hp < _ctrl.player_hp_max:
		ids.push_front("heal")
	if kind == "elite":
		ids.append_array(["elite_gold", "elite_anvil", "elite_ward"])
	return _rewards_by_ids(ids)


# 构筑位：武器 / 真实增格符号 / 本局伤害。power 保证槽位永不为空。
func _slot_build_pool(kind: String, act: int) -> Array:
	var ids: Array[String] = ["power"]
	if (act >= 2 or kind == "elite") and has_weapon_candidate():
		ids.push_front("weapon")
	if not symbol_infusions().is_empty():
		ids.push_front("symbol")
	return _rewards_by_ids(ids)


# 是否还有未装备武器可给（避免「新武器」卡没有具体对象）。
func has_weapon_candidate() -> bool:
	for p in _ctrl.WEAPON_POOL:
		if not _ctrl.selected_loadout.has(p):
			return true
	return false


func _rewards_by_ids(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		var rw: RewardData = _find_reward(String(id))
		if rw != null:
			out.append(rw)
	return out


func _fill_slot_payloads(choices: Array) -> void:
	choice_payloads = []
	for rw in choices:
		choice_payloads.append(_slot_payload(rw))


# 槽位卡的展示口径：具体对象 + 当前值 → 选择后值。apply_reward 只对 weapon/symbol/consumable
# 读取 payload 中的 path；其余项的 payload 只负责展示。
func _slot_payload(rw: RewardData) -> Dictionary:
	if rw == null:
		return {}
	match String(rw.id):
		"weapon":
			return _weapon_payload()
		"symbol":
			return _symbol_payload()
		"consumable":
			return _consumable_payload()
		"heal":
			var h := int(_ctrl.player_hp_max * float(rw.value) / 100.0)
			var after := mini(_ctrl.player_hp_max, _ctrl.player_hp + h)
			return {"title": "%s · +%d HP" % [rw.label, after - _ctrl.player_hp],
				"desc": "HP %d/%d → %d/%d" % [_ctrl.player_hp, _ctrl.player_hp_max, after, _ctrl.player_hp_max]}
		"maxhp":
			return {"title": "%s · +%d" % [rw.label, rw.value],
				"desc": "最大 HP %d → %d 并回满" % [_ctrl.player_hp_max, _ctrl.player_hp_max + rw.value]}
		"maxhp_heal":
			return {"title": "%s · +%d" % [rw.label, rw.value],
				"desc": "最大 HP %d → %d，并恢复 20%%" % [_ctrl.player_hp_max, _ctrl.player_hp_max + rw.value]}
		"shield", "elite_ward":
			return {"title": "%s · +%d" % [rw.label, rw.value],
				"desc": "下一房开局护盾 %d → %d" % [run_shield_next, run_shield_next + rw.value]}
		"power":
			return {"title": "%s · +%d" % [rw.label, rw.value],
				"desc": "本局符号伤害 +%d → +%d" % [run_power_bonus, run_power_bonus + rw.value]}
		"gold", "elite_gold":
			return {"title": "%s · +%d" % [rw.label, rw.value],
				"desc": "金币 %d → %d" % [_ctrl.gold, _ctrl.gold + rw.value]}
		"elite_anvil":
			var ap := int(_ctrl.meta.get("anvil_points", 0))
			return {"title": "%s · +%d" % [rw.label, rw.value],
				"desc": "铁砧点数 %d → %d（跨局）" % [ap, ap + rw.value]}
	return {"title": rw.label, "desc": rw.desc}


# 按 id 在普通/精英奖励池中查找 RewardData（数值资源化：value 字段，文案同文件防漂移）
func _find_reward(id: String) -> RewardData:
	for rw in _ctrl.REWARD_POOL:
		if rw is RewardData and rw.id == id:
			return rw
	for rw in _ctrl.ELITE_REWARD_POOL:
		if rw is RewardData and rw.id == id:
			return rw
	return null


func apply_reward(id: String, index: int = -1) -> void:
	var rd = _find_reward(id)
	if rd == null:
		_ctrl.hud._log("奖励资源缺失：%s" % id)
		return
	match id:
		"heal":
			var h = int(_ctrl.player_hp_max * float(rd.value) / 100.0)
			_ctrl.player_hp = min(_ctrl.player_hp_max, _ctrl.player_hp + h)
			_ctrl.hud._log("奖励：治疗 +%d HP" % h)
			if h > 0:
				_ctrl.hud._popup("❤+%d" % h, Palette.POP_HEAL, _ctrl.hud._player_sprite_anchor())
		"maxhp":
			_ctrl.player_hp_max += rd.value
			_ctrl.player_hp = _ctrl.player_hp_max
			_ctrl.hud._log("奖励：最大 HP +%d 并回满" % rd.value)
			_ctrl.hud._popup("❤上限+%d 回满" % rd.value, Palette.POP_HEAL, _ctrl.hud._player_sprite_anchor())
		# "purify" 净化上限奖励已删除（净化完全走消耗品）
		"symbol":
			_grant_symbol_reward(rd, index)
		"shield":
			run_shield_next += rd.value
			_ctrl.hud._log("奖励：下一房 +%d 护盾" % rd.value)
			_ctrl.hud._popup("🛡下一房+%d" % rd.value, Palette.POP_SHIELD, _ctrl.hud._player_sprite_anchor())
		"power":
			run_power_bonus += rd.value
			_ctrl.hud._log("奖励：本局符号伤害 +%d（当前 +%d）" % [rd.value, run_power_bonus])
			_ctrl.hud._popup("⚔伤害+%d" % rd.value, Palette.POP_BUFF, _ctrl.hud._player_sprite_anchor())
		# 胜利奖励方案（2026-08-13）新增：经济 / 构筑 / 双效
		"gold":
			_ctrl.gold += rd.value
			_ctrl.hud._log("奖励：金币 +%d（共 %d）" % [rd.value, _ctrl.gold])
			_ctrl.hud._popup("💰+%d" % rd.value, Palette.POP_GOLD, _ctrl.hud._player_sprite_anchor())
		"consumable":
			_grant_consumable_reward(index)
		"weapon":
			_grant_weapon_reward(index)
		"maxhp_heal":
			_ctrl.player_hp_max += rd.value
			_ctrl.player_hp = mini(_ctrl.player_hp_max, _ctrl.player_hp + int(_ctrl.player_hp_max * 0.2))
			_ctrl.hud._log("奖励：最大 HP +%d 并恢复 20%%" % rd.value)
			_ctrl.hud._popup("❤上限+%d 恢复20%%" % rd.value, Palette.POP_HEAL, _ctrl.hud._player_sprite_anchor())
		# T6 精英房「战前补给」三类选项
		"elite_gold":
			_ctrl.gold += rd.value
			_ctrl.hud._log("精英战利：金币 +%d（共 %d）" % [rd.value, _ctrl.gold])
			_ctrl.hud._popup("💰+%d" % rd.value, Palette.POP_GOLD, _ctrl.hud._player_sprite_anchor())
		"elite_anvil":
			_ctrl.meta["anvil_points"] += rd.value
			_ctrl.hud._log("精英战利：铁砧点数 +%d（共 %d）" % [rd.value, _ctrl.meta["anvil_points"]])
			_ctrl.hud._popup("🔨铁砧点+%d" % rd.value, Palette.ACCENT_GOLD, _ctrl.hud._player_sprite_anchor())
		"elite_ward":
			run_shield_next += rd.value
			_ctrl.hud._log("精英战利：下一房 +%d 护盾" % rd.value)
			_ctrl.hud._popup("🛡下一房+%d" % rd.value, Palette.POP_SHIELD, _ctrl.hud._player_sprite_anchor())
	_ctrl.invalidate_state()   # 玩家 HP/金币/构筑奖励（腰带/转轮带）
	_ctrl.hud._refresh_meta()   # 自包含刷新：任何直接调用本方法的新路径不依赖外部收尾（controller 收尾刷新降级为幂等兜底）


# 构筑奖励·武器（M1-01）：优先使用候选展示前已确定的武器；槽满时由 controller 先走替换弹层，
# 正常不会以「满槽」状态调用到这里（兜底只记日志、不塞第 3 把）。
func _grant_weapon_reward(index: int) -> void:
	var payload := payload_at(index)
	var path := String(payload.get("path", ""))
	if path == "" or _ctrl.selected_loadout.has(path):
		_pick_item_reward("weapon")   # 旧调用路径 / 候选未预选：退回随机抽取
		return
	if _ctrl.selected_loadout.size() >= _ctrl._loadout_system.cat_cap("weapon"):
		_ctrl.hud._log("武器槽已满 %d/%d：%s 需替换后才能获得" % [
			_ctrl.selected_loadout.size(), _ctrl._loadout_system.cat_cap("weapon"),
			_ctrl._shop_name(path, "weapon")])
		return
	_ctrl._loadout_system.grow_slot("weapon")
	_ctrl.selected_loadout.append(path)
	_ctrl._build_pool(_ctrl.selected_loadout)
	remember_weapon(path)
	var wd: WeaponData = load(path)
	var nm: String = wd.weapon_name if wd != null else path.get_file().get_basename()
	_ctrl.hud._log("奖励：获得武器 %s（已加入转轮带）" % nm)
	_ctrl.hud._popup("🎁 获得武器 %s" % nm, Palette.ACCENT_GOLD, _ctrl.hud._player_sprite_anchor())


# 构筑奖励·消耗品（M1-02）：展示前已定具体物品，确认后按 payload 授予；旧路径缺 payload 时才抽。
func _grant_consumable_reward(index: int) -> void:
	var path := String(payload_at(index).get("path", ""))
	if path == "":
		path = pick_active_item_path()
	if path == "":
		return
	_grant_consumable_path(path)


func _grant_consumable_path(path: String) -> void:
	var cd: Resource = load(path)
	if _ctrl.consumable_slots.size() >= _ctrl.CONSUMABLE_CAP:
		# P-审计 P2：腰带满不硬塞（超出 CONSUMABLE_CAP 的格子不可见不可用）——折算金币（卖价），保底不落空
		var refund: int = _ctrl._sell_price("active", path)
		_ctrl.gold += refund
		_ctrl.hud._log("奖励：%s 但腰带已满 → 折算金币 +%d" % [(cd.item_name if cd != null else path), refund])
		_ctrl.hud._popup("💰+%d" % refund, Palette.POP_GOLD, _ctrl.hud._player_sprite_anchor())
		return
	_ctrl._consumable_uid += 1
	_ctrl.consumable_slots.append({"path": path, "item_id": cd.item_id, "charges": cd.charges, "uid": "c%d" % _ctrl._consumable_uid})
	_ctrl.hud._log("奖励：获得消耗品 %s（入腰带）" % cd.item_name)
	_ctrl.hud._popup("🎁 获得 %s" % cd.item_name, Palette.POP_GOLD, _ctrl.hud._player_sprite_anchor())
	_ctrl.hud._refresh_consumable_panel()


# 符号灌注（M1-02）：按展示前确定的符号生效，不再二次随机；日志/飘字报真实格数变化。
func _grant_symbol_reward(rd: RewardData, index: int) -> void:
	var payload := payload_at(index)
	var spath := String(payload.get("path", ""))
	var sym: SymbolData = load(spath) if spath != "" else null
	if sym == null:
		_ctrl.hud._log("奖励：符号灌注候选缺失（未生效，不进行二次随机）")
		return
	var before: int = _symbol_cells(sym, 0.0)
	run_symbol_bonus[sym.resource_path] = run_symbol_bonus.get(sym.resource_path, 0) + rd.value
	var after: int = _symbol_cells(sym, 0.0)
	_ctrl.hud._log("奖励：%s 符号权重 +%d（转轮带 %d → %d 格）" % [sym.name, rd.value, before, after])
	_ctrl.hud._popup("✨%s %d→%d 格" % [sym.label, before, after], Palette.POP_BUFF, _ctrl.hud._player_sprite_anchor())


# 构筑奖励兜底：按当前来源品质表抽同类别一件（武器排除已装备；消耗品允许腰带重复）。
# Step 3 起不再全池均匀 / 不再读 acquisition_weight；同层为空则放弃本次授予（由上层改为其它卡）。
func _pick_item_reward(kind: String) -> void:
	# A 方案防御保底：武器槽满（上限 2）时不追加（候选层已拦截，此处双保险）
	if kind == "weapon" and _ctrl.selected_loadout.size() >= _ctrl._loadout_system.cat_cap("weapon"):
		return
	var category := "weapon" if kind == "weapon" else "active"
	var opts := {"category": category}
	if kind == "weapon":
		opts["exclude"] = _ctrl.selected_loadout
	var res: Dictionary = _loot.roll(_current_source(), _current_act(), opts)
	if not bool(res.get("ok", false)):
		return
	var path := String(res["path"])
	var cd: Resource = load(path)
	if cd == null:
		return
	if kind == "weapon":
		_ctrl._loadout_system.grow_slot("weapon")                 # 免费武器自动开槽（同 BOSS 战利品）
		_ctrl.selected_loadout.append(path)
		_ctrl._build_pool(_ctrl.selected_loadout)
		remember_weapon(path)
		_ctrl.hud._log("奖励：获得武器 %s（已加入转轮带）" % cd.weapon_name)
		_ctrl.hud._popup("🎁 获得武器 %s" % cd.weapon_name, Palette.ACCENT_GOLD, _ctrl.hud._player_sprite_anchor())
	else:
		_grant_consumable_path(path)


# BOSS 战利品结算（主题池+混合券三选一）：新武器(进池) / 武器强化券(meta升级,不进池) / Boss信物(占护符槽1/3)
func apply_boss_reward(cand: Dictionary) -> void:
	match cand.get("kind", ""):
		"boss_weapon":
			var p = cand.get("path", "")
			if p != "" and not _ctrl.selected_loadout.has(p):
				# 槽满时 controller 已路由到替换弹层；走到这里仍满槽说明调用路径异常，不硬塞第 3 把
				if _ctrl.selected_loadout.size() >= _ctrl._loadout_system.cat_cap("weapon"):
					_ctrl.hud._log("BOSS 战利品：武器槽已满，%s 未拾取" % cand.get("label", p))
				else:
					_ctrl._loadout_system.grow_slot("weapon")                 # 免费武器自动开槽（武器槽上限 2：grow_slot 封顶兜底）
					_ctrl.selected_loadout.append(p)          # 武器槽未满才出候选（A 方案 2026-08-13：上限 2 尊重「固定 2 把」规则）
					_ctrl._build_pool(_ctrl.selected_loadout)  # 重建符号池（新武器注入转轮带）
					remember_weapon(p)                        # M1-01：新武器写入局外收藏
					_ctrl.hud._log("BOSS 战利品：获得武器 %s（已加入转轮带）" % cand.get("label", p))
					_ctrl.hud._popup("⚔ 获得武器 %s" % cand.get("label", p), Palette.ACCENT_GOLD, _ctrl.hud._player_sprite_anchor())
		"boss_relic":
			var p = cand.get("path", "")
			if p != "" and not _ctrl.selected_charms.has(p):
				if _ctrl._loadout_system.sel_arr("passive").size() >= _ctrl._loadout_system.cat_max("passive"):
					_ctrl.hud._log("BOSS 战利品：护符槽已满，信物无法拾取")
					return
				_ctrl.selected_charms.append(p)            # 占护符槽 1/3（CHARM_CAP）
				# 2026-08-14 拍板（审查 §3.4）：信物跨局持久化——写入 owned_charms（收藏金字塔顶端定位），
				# 后续整备页可随时再选（BOSS 信物不进商店/铁砧/新档种子，仅 BOSS 战利品与后续重选两条路径）
				if not _ctrl.meta["owned_charms"].has(p):
					_ctrl.meta["owned_charms"].append(p)
					_ctrl._anvil_system.check_collection_milestones()   # M1-03
					_ctrl._meta_store.save_meta()
				_ctrl._meta_store.record_source(p, _ctrl._item_source())   # G2-01：来源记录
				_ctrl._apply_charms()                     # 重算护符被动（伤害乘区等随持有变化）
				_ctrl.hud._log("BOSS 战利品：获得专属信物 %s（占护符槽，已入图鉴）" % cand.get("label", p))
				_ctrl.hud._popup("🏆 获得信物 %s" % cand.get("label", p), Palette.ACCENT_GOLD, _ctrl.hud._player_sprite_anchor())
		# 空池兜底（2026-08-14）：武器/护符槽双满时的铁砧点补偿
		"boss_anvil":
			_ctrl.meta["anvil_points"] += BALANCE.boss_anvil_bonus
			_ctrl._meta_store.save_meta()   # 跨局货币立即落盘
			_ctrl.hud._log("BOSS 战利品：铁砧点数 +%d（共 %d）" % [BALANCE.boss_anvil_bonus, _ctrl.meta["anvil_points"]])
			_ctrl.hud._popup("🔨铁砧点+%d" % BALANCE.boss_anvil_bonus, Palette.ACCENT_GOLD, _ctrl.hud._player_sprite_anchor())
	_ctrl.invalidate_state()
	_ctrl.hud._refresh_meta()   # 自包含刷新（同上：新调用路径不依赖外部收尾）


# 打开奖励屏的语义入口：填充 reward_choices / reward_is_boss（HUD 从 state 快照读取）。
# 2026-08-09 由 controller._open_reward_screen 迁入（二次拆分 3/4）
func open_reward_screen(is_boss: bool) -> void:
	_ctrl.reward_is_boss = is_boss
	if is_boss:
		_ctrl.reward_choices = roll_boss_rewards(_ctrl.ROOMS[_ctrl.room_index])
	elif _ctrl.ROOMS[_ctrl.room_index].kind == "elite":
		_ctrl.reward_choices = roll_elite_rewards()
	else:
		_ctrl.reward_choices = roll_rewards()
	if _ctrl._telemetry != null:
		_ctrl._telemetry.on_reward_shown(_ctrl.reward_choices.size())   # M1-06：奖励选择率分母
	_ctrl.invalidate_state()


# 局末元进度三选一弹屏（2026-08-09 由 controller._show_meta_choice 迁入）
func show_meta_choice() -> void:
	_ctrl.hud._show_meta_choice()


# ---------------------------------------------------------------------------
# T8 掉落渠道（2026-08-24，docs/装备收集规划_200.md §12.1）：
# 普通房 12% 掉 1 消耗品；精英房保底 1 护符。BOSS 房走自身战利品不经此处。
# Step 3：两处品质都改由来源表决定（normal / elite），不再读 acquisition_weight。
# 入口：room_flow.finish_room 在铁砧点/金币入账后调用。
# ---------------------------------------------------------------------------
func apply_room_drops() -> void:
	if _ctrl.room_index < 0 or _ctrl.room_index >= _ctrl.ROOMS.size():
		return
	var kind: String = _ctrl.ROOMS[_ctrl.room_index].kind
	if kind == "elite":
		_drop_elite_charm()
	elif kind == "normal" and randf() < BALANCE.drop_consumable_chance_normal:
		var res: Dictionary = _loot.roll("normal", _current_act(), {"category": "active"})
		if bool(res.get("ok", false)):
			_grant_drop_consumable(String(res["path"]))


# 精英保底护符：来源表（elite）定品质 → 同品质层抽一个非信物护符；
# 护符槽未达天花板时免费开槽（先例：武器奖励自动开槽），已达 CHARM_CAP 天花板则折算金币（卖价），
# 保底永不落空。排除 BOSS 信物（信物仅 BOSS 战利品可获）。
# 同层为空（数据缺口/已持有过滤）时重抽品质，仍空则退回该来源的合法护符全集——保底不落空。
func _drop_elite_charm() -> void:
	var act := _current_act()
	var opts := {"category": "passive", "include_relics": false, "exclude": _ctrl.selected_charms}
	var path := ""
	for _attempt in range(6):
		var res: Dictionary = _loot.roll("elite", act, opts)
		if bool(res.get("ok", false)):
			path = String(res["path"])
			break
	if path == "":
		path = _any_legal_charm(act, opts)
	if path == "":
		return
	if sel_passive_size() >= _ctrl._loadout_system.cat_max("passive"):
		if _ctrl._loadout_system.can_grow_slot("passive"):
			_ctrl._loadout_system.grow_slot("passive")
		else:
			var refund: int = _ctrl._sell_price("passive", path)
			_ctrl.gold += refund
			var nm2: Resource = load(path)
			_ctrl.hud._log("精英掉落：%s 但护符槽已满（3/3）→ 折算金币 +%d" % [(nm2.item_name if nm2 != null else path), refund])
			_ctrl.hud._popup("💰+%d" % refund, Palette.POP_GOLD, _ctrl.hud._player_sprite_anchor())
			return
	_ctrl.selected_charms.append(path)
	remember_charm(path)   # G2-01：精英掉落护符写入图鉴/来源
	_ctrl._apply_charms()
	var cd: Resource = load(path)
	_ctrl.hud._log("精英掉落：获得护符 %s（按来源品质表，占护符槽）" % (cd.item_name if cd != null else path))
	_ctrl.hud._popup("🎁 获得护符 %s" % (cd.icon if cd != null else "🛡"), Palette.ACCENT_GOLD, _ctrl.hud._player_sprite_anchor())


# 精英掉落兜底：该来源合法护符全集里随机一个（仍走专用 RNG，不消耗地图 RNG）。
func _any_legal_charm(act: int, opts: Dictionary) -> String:
	var pool: Dictionary = _loot.candidates("elite", act, opts)
	var items: Array = pool.get("items", [])
	if items.is_empty():
		return ""
	var copy := items.duplicate()
	_loot.shuffle_in_place(copy)
	return String(copy[0])


# 普通房消耗品掉落授予：腰带满（CONSUMABLE_CAP）→ 折算金币（卖价），保底语义不落空。
func _grant_drop_consumable(path: String) -> void:
	if _ctrl.consumable_slots.size() >= _ctrl.CONSUMABLE_CAP:
		var refund: int = _ctrl._sell_price("active", path)
		_ctrl.gold += refund
		var nm: Resource = load(path)
		_ctrl.hud._log("掉落：%s 但腰带已满 → 折算金币 +%d" % [(nm.item_name if nm != null else path), refund])
		_ctrl.hud._popup("💰+%d" % refund, Palette.POP_GOLD, _ctrl.hud._player_sprite_anchor())
		return
	var cd: Resource = load(path)
	_ctrl._consumable_uid += 1
	_ctrl.consumable_slots.append({"path": path, "item_id": cd.item_id, "charges": cd.charges, "uid": "c%d" % _ctrl._consumable_uid})
	_ctrl.hud._log("掉落：获得消耗品 %s（入腰带）" % cd.item_name)
	_ctrl.hud._popup("🎁 获得 %s" % cd.item_name, Palette.POP_GOLD, _ctrl.hud._player_sprite_anchor())
	_ctrl.hud._refresh_consumable_panel()


# 共享获取权重（§11.1）：单件物品权重 = acquisition_weight[rarity]；bias ≠ 1 时乘算 rare/epic
# （§11.2 BOSS 深度偏置——只抬高稀，common/uncommon 不动；商店传 1.0）。
# 性能：权重与稀有度按路径缓存（资源静态，进程内不变），避免抽样循环里反复 load()。
func acq_weight(path: String, bias: float = 1.0) -> float:
	var e = _acq_cache.get(path)
	if e == null:
		var res: Resource = load(path)
		var r: String = String(res.get("rarity")) if res != null and res.get("rarity") != null else "common"
		e = {"w": float(BALANCE.acquisition_weight.get(r, 100)), "hi": r == "rare" or r == "epic"}
		_acq_cache[path] = e
	var w: float = float(e["w"])
	if bias != 1.0 and bool(e["hi"]):
		w *= bias
	return w


func acq_weighted_pick(paths: Array, bias: float = 1.0) -> String:
	var total := 0.0
	for p in paths:
		total += acq_weight(p, bias)
	var roll := randf() * total
	for p in paths:
		roll -= acq_weight(p, bias)
		if roll <= 0.0:
			return p
	return paths[paths.size() - 1]


# 无放回加权抽样（T7 商店货架 / BOSS 武器候选共用）。items 元素为 String 路径或含 "path" 的 Dictionary。
func acq_weighted_sample(items: Array, n: int, bias: float = 1.0) -> Array:
	var pool := items.duplicate()
	var out := []
	while out.size() < n and not pool.is_empty():
		var paths := []
		for it in pool:
			paths.append(it if it is String else it["path"])
		var chosen: String = acq_weighted_pick(paths, bias)
		for i in range(pool.size()):
			var it = pool[i]
			if (it if it is String else it["path"]) == chosen:
				out.append(it)
				pool.remove_at(i)
				break
	return out


# BOSS 信物路径全集（数据驱动：扫描全部房间的 boss_relic_path）——精英掉落排除集。
func relic_paths() -> Array:
	var out := []
	for r in _ctrl.ALL_ROOMS:
		if r.boss_relic_path != "":
			out.append(r.boss_relic_path)
	return out


func sel_passive_size() -> int:
	return _ctrl._loadout_system.sel_arr("passive").size()
