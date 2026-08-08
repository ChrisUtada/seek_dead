class_name CombatSystem
extends RefCounted

# combat_system — 战斗结算系统（2026-08-09 从 duel_controller 拆分）
#
# 职责：单回合结算（_evaluate：符号计数 → 分阶段落地 → 攻击结算）、
# 符号贡献（_contribute：伤害/护盾/治疗/状态/特殊）、伤害分解行、敌人攻防、
# 三连破甲/核爆、元素充能爆发、增益/状态 tick、属性聚合层（_agg_*）。
#
# 状态共享：全部战斗状态（grid / enemy_* / player_* / charge_points / player_buffs / 护符）
# 仍由 DuelController 持有，本系统经 _ctrl 读写（与 shop_system 同一模式）；
# BOSS 机制钩子（current_gimmick.on_special_triple / on_damaged）回调传 _ctrl。
#
# 唯一 async 入口：evaluate()（内部 await 间隔，供飘字/动画演出）。

var _ctrl  # DuelController


func _init(ctrl) -> void:
	_ctrl = ctrl


# 单符号贡献：按 kind 路由到伤害/护盾/治疗/状态/特殊。acc 为回合累计字典（见 evaluate）。
func contribute(sym: SymbolData, raw: int, acc: Dictionary, elem: String) -> void:
	# 连线精通(S12)：仅当实落 ≥2（确为连线匹配）时才叠加倍率，单符号必结算不受影响
	var line_bonus: int = int(_ctrl._shop_system.track_level("line") * _ctrl._shop_system.track_per_level("line"))
	var mult = raw + (line_bonus if raw >= 2 else 0)
	# 2026-08-07 武器系统重构（T12）：伤害只由武器攻击力决定——flat = item_power + 元进度加成，
	# 符号 sym.base 不再参与缩放（BASE_POWER_REF 退役）；非武器符号（异常路径）兜底 sym.base。
	var item_power: float = _ctrl._weapon_power_map.get(sym.resource_path, 0.0)
	var flat: float = item_power + agg_power_flat() if item_power > 0.0 else sym.base + agg_power_flat()
	# bonus = 非 sym.base 部分（攻击力差值 + 元进度聚合），供 push_dmg_line 分解展示（恒等式 flat = sym.base + bonus）
	var bonus: float = flat - sym.base
	# 逐符号元素克制倍率（Phase G v2.0：通用元素乘区，奖罚并存·温和；共鸣可对该元素加成）
	# T2 元素优势护符：克制时额外加法加成（×1.5 → ×1.5+boost），抵抗/中性不生效（鼓励带对元素）
	# 2026-08-09：治疗/护盾/状态符号豁免元素乘区——不造成伤害，克制/抗性/充能/核爆一律不参与
	var em: float = 1.0
	if sym.kind == "damage" or sym.kind == "special":
		em = ElementCounter.multiplier(elem, _ctrl.enemy_element) * _ctrl._synergy_system.element_boost(elem)
		if em > 1.0 and _ctrl.charm_element_boost > 0.0:
			em += _ctrl.charm_element_boost
		if em > 1.0:
			_ctrl._eval_adv = true
			_ctrl.charge_points += 1              # T21 元素充能：每次克制命中 +1（仅伤害类符号）
			# 反制即爆发（Plan C）：克制元素连线/三连标记，供 evaluate 触发核爆
			# 2026-08-07 同元素三连：同元素 3 格（可不同符号）也触发核爆
			if raw >= 2 or _ctrl._elem_triple:
				acc["counter_triple"] = true
		elif em < 1.0:
			_ctrl._eval_dis = true
	# 方案 B：三连必暴（crit_mult，现状保留）；非三连每符号实例按 BALANCE.crit_chance + 物品 crit_chance 独立暴击——
	# 单带靠三连大暴，多带靠每列小暴；高 base 武器低暴击（代价轴，2026-08-07）。
	# 2026-08-07 同元素三连：同元素 3 格（可不同符号）同样必暴（匹配判定宽容化，参考 Slots & Skulls）。
	# 共鸣 crit_bonus 在暴击触发时叠加到 crit_mult（激活集由 _synergy_system 缓存）。
	var crit_rate: float = DuelController.BALANCE.crit_chance + _ctrl._item_crit_chance_map.get(sym.resource_path, 0.0)
	var crit_mult_val: float = (_ctrl._item_crit_map.get(sym.resource_path, 1.0) + _ctrl._synergy_system.crit_bonus(sym)) if raw >= 3 or _ctrl._elem_triple or randf() < crit_rate else 1.0
	match sym.kind:
		"damage":
			var dv = flat * mult * em
			if crit_mult_val > 1.0:
				dv *= crit_mult_val
			# 2026-08-07 三连通用化：任意同符号 3 连 → 必暴（triple 标记供 gimmick/破甲判定）；
			# 破甲 = 仅带破甲机制（triple_pierce）的武器/技能三连触发（evaluate 里判 _item_pierce_map）
			if raw >= 3:
				acc["triple"] = true
			# T2 破甲护符：非穿透符号按概率直击 HP（穿透护甲）
			if sym.pierce_armor or randf() < _ctrl.charm_pierce_chance:
				acc["pierce"] += dv     # 穿透护甲：直接扣 HP
			else:
				acc["dmg"] += dv
			push_dmg_line(acc, sym, elem, flat, bonus, mult, em, dv, crit_mult_val)
		# 2026-08-07 重构：shield/heal 不吃武器攻击力/克制/元进度——只 = 符号 base × 连线 × 暴击（治疗/护盾符号保持小值，来自技能/房奖励）
		"shield":  acc["shield"]  += sym.base * mult * crit_mult_val
		# 2026-08-07 治疗术倍率表（方案 A）：1连×1.0 / 2连×2.5 / 3连×5.0；
		# 不吃暴击/连线精通/克制——治疗规则简单可预期；3连标记 heal_triple 供溢出转护盾
		"heal":
			acc["heal"] += sym.base * [1.0, 2.5, 5.0][mini(raw - 1, 2)]
			if raw >= 3:
				acc["heal_triple"] = true
		"status":  acc["status_stacks"][sym.status_type] = acc["status_stacks"].get(sym.status_type, 0) + mult * crit_mult_val
		"special":
			# special（火焰法杖等专属高伤符号，2026-08-07 起与 damage 同源；三连同样必暴/连锁/破甲机制）
			var sv = flat * mult * em
			if crit_mult_val > 1.0:
				sv *= crit_mult_val
			if raw >= 3:
				acc["triple"] = true
			if sym.pierce_armor or randf() < _ctrl.charm_pierce_chance:
				acc["pierce"] += sv
			else:
				acc["special"] += sv
			push_dmg_line(acc, sym, elem, flat, bonus, mult, em, sv, crit_mult_val)
		_: pass


# S2：伤害分解行（§5.2 标为 P0——"爽感的一半来自看懂这一下为什么这么大"；
# 同时是 ante 调参（BALANCE.ante_act_step_hp/ATK、BALANCE.ante_room_step_hp/ATK）的唯一 debug 依据）。
# 逐符号记录「基础 × 连线 × 克制 = 小计」，回合级乘区（护符/增益/强袭）在 evaluate 汇总。
func push_dmg_line(acc: Dictionary, sym: SymbolData, elem: String, flat, bonus, mult: int, em: float, v: float, crit_mult_val: float = 1.0) -> void:
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
	if crit_mult_val > 1.0:
		line += "（⚡暴击 ×%s）" % ElementCounter.fmt_mult(crit_mult_val)
	acc["lines"].append(line)


# 结算：分两阶段（先防御/增益/状态，后攻击），接单向属性克制与强袭药剂。
# 2026-08-07：重转机制移除，单次结算（chain_mult 参数退役）
func evaluate() -> void:
	_ctrl.hud._clear_badges()
	var acc = { "dmg": 0, "shield": 0, "heal": 0, "status_stacks": {}, "special": 0, "lines": [], "pierce": 0.0, "counter_triple": false, "triple": false, "heal_triple": false }
	_ctrl._eval_adv = false
	_ctrl._eval_dis = false

	# 按「符号 + 有效元素」计数（解决共享符号跨武器元素冲突；HUD 角标据此展示）
	# T30：冻结列（失效格）不参与计数——不匹配、不结算、无攻击
	var counts = {}
	for p in _ctrl.PAYLINES[0]:
		if p[0] in _ctrl.frozen_cols:
			continue
		var sym: SymbolData = _ctrl.grid[p[0]][p[1]]
		var elem: String = _ctrl.grid_elem[p[0]][p[1]]
		var key: String = sym.resource_path + "|" + elem
		if not counts.has(key):
			counts[key] = [sym, elem, 0]
		counts[key][2] += 1
	# 2026-08-07 同元素三连：统计每「有效元素」总出现数（跨符号聚合，仅非 none）——3 列同元素即必暴/核爆
	_ctrl._elem_triple = false
	var elem_total := {}
	for key in counts:
		var e: String = counts[key][1]
		if e != "none":
			elem_total[e] = elem_total.get(e, 0) + counts[key][2]
	for e in elem_total:
		if elem_total[e] >= 3:
			_ctrl._elem_triple = true
			break
	if _ctrl._elem_triple:
		_ctrl.hud._log("⚡ 元素三连！同元素 3 格（必暴）")
	# Phase C：先结算 buff 符号（本回合即生效，命中当回合就吃到增益）
	for key in counts:
		var s: SymbolData = counts[key][0]
		if s == DuelController.TRASH_SYMBOL or s.kind != "buff":
			continue
		grant_buff(s, counts[key][2])
	# 金币符号（常驻）：落在线上的金币直接转化为金币资源，不造成任何伤害
	for key in counts:
		var s: SymbolData = counts[key][0]
		if s == DuelController.GOLD_SYMBOL:
			var g = DuelController.BALANCE.gold_per_coin * counts[key][2]
			if g > 0:
				_ctrl.gold += g
				_ctrl.hud._log("💰 金币 +%d" % g)
				_ctrl.hud._popup("💰+%d" % g, Palette.POP_GOLD, _ctrl.hud._player_sprite_anchor())
	# 再结算常规符号（此时 contribute 读到的已是含新增益的加成，并按各自有效元素吃克制）
	for key in counts:
		var s: SymbolData = counts[key][0]
		var elem: String = counts[key][1]
		var c: int = counts[key][2]
		if s == DuelController.TRASH_SYMBOL or s.kind == "buff" or s == DuelController.GOLD_SYMBOL:
			continue
		if s.kind == "special" and c < 1:
			continue
		contribute(s, c, acc, elem)

	# 匹配角标（×N，N>=2）
	_ctrl.hud._update_match_badges(counts)

	# —— 阶段 1：防御 / 增益 / 状态先落地 ——
	# Phase C：铁壁(shield)/回春(regen) 按回合生效，并入本回合护盾与治疗（F-0 聚合层）
	acc["shield"] += int(agg_shield())
	acc["heal"] += int(agg_regen())
	for st in acc["status_stacks"].keys():
		_ctrl.enemy_status[st] = _ctrl.enemy_status.get(st, 0) + acc["status_stacks"][st]
	if acc["shield"] > 0:
		_ctrl.player_shield += acc["shield"]
		_ctrl.hud._popup("🛡+%d" % acc["shield"], Palette.POP_SHIELD, _ctrl.hud._player_sprite_anchor())
		_ctrl.hud._log("获得 %d 护盾" % acc["shield"])
	if acc["heal"] > 0:
		var missing: int = _ctrl.player_hp_max - _ctrl.player_hp
		var hp_gain: int = mini(int(acc["heal"]), missing)
		_ctrl.player_hp += hp_gain
		if hp_gain > 0:
			_ctrl.hud._popup("❤+%d" % hp_gain, Palette.POP_HEAL, _ctrl.hud._player_sprite_anchor())
			_ctrl.hud._log("回复 %d HP" % hp_gain)
		# 2026-08-07 方案 A：治疗三连溢出转护盾（满血不浪费，三连独有奖励）
		if acc.get("heal_triple", false) and int(acc["heal"]) > missing:
			var shield_gain: int = int(acc["heal"]) - missing
			_ctrl.player_shield += shield_gain
			_ctrl.hud._popup("🛡+%d" % shield_gain, Palette.POP_SHIELD, _ctrl.hud._player_sprite_anchor())
			_ctrl.hud._log("治疗三连溢出转护盾 +%d" % shield_gain)
	if not acc["status_stacks"].is_empty():
		_ctrl.hud._log("敌人获得状态: " + _ctrl._status_summary(acc["status_stacks"]))
		_ctrl.hud._popup(_ctrl._status_summary(acc["status_stacks"]), Palette.POP_STATUS, _ctrl.hud._enemy_sprite_anchor())

	_ctrl.hud._refresh_meta()
	await _ctrl.get_tree().create_timer(0.25).timeout

	# S10 T5 钩子点 + 破甲/核爆（2026-08-07 通用化：任意同符号三连触发；破甲仅限带破甲机制的武器/技能）。
	# current_gimmick 仅在 BOSS 房由 T2 的 BossGimmick 子类赋值；非 BOSS 房为 null，显式判空跳过（避免 ?. 在某些 4.x 不兼容）。
	if acc.get("triple", false):
		_ctrl.hud._log("⚡ 三连触发")
		if _ctrl.current_gimmick != null:
			_ctrl.current_gimmick.on_special_triple(_ctrl)   # BOSS 自定义钩子（三连感知，语义泛化）

	# 破甲：带破甲机制（triple_pierce）的三连 → 清甲；克制三连 → 核爆（清甲 + 20% max HP）
	var triple_pierce: bool = false
	for key in counts:
		if _ctrl._item_pierce_map.has(counts[key][0].resource_path) and counts[key][2] >= 3:
			triple_pierce = true
			break
	if acc.get("counter_triple", false):
		on_counter("element")
	elif triple_pierce:
		on_counter("special")

	# —— 阶段 2：攻击结算（先破甲后掉血；穿透符号直接扣 HP）——
	# Phase C：迅捷(damage_mult) 对本回合总伤害做乘算（F-0 聚合层，含护符乘区）
	var buff_mult = agg_damage_mult()
	var assault = _ctrl.assault_next_spin
	var normal_subtotal = acc["dmg"] + acc["special"]
	var pierce_subtotal = acc.get("pierce", 0.0)
	var normal_total = int(normal_subtotal * assault * buff_mult * DuelController.BALANCE.player_dmg_mult)
	var pierce_total = int(pierce_subtotal * assault * buff_mult * DuelController.BALANCE.player_dmg_mult)
	_ctrl.assault_next_spin = 1
	var total = normal_total + pierce_total
	# S2：伤害分解只进调试日志（Debug.log），屏幕仅保留总伤害飘字（见下方 _popup）
	if not acc["lines"].is_empty():
		var blk := ["🔍 伤害分解"]
		blk.append_array(acc["lines"])
		var tail := []
		var cm = _ctrl.charm_damage_mult
		var bm = buff_damage_mult()
		if cm != 1.0:
			tail.append("护符×%s" % ElementCounter.fmt_mult(cm))
		if bm != 1.0:
			tail.append("增益×%s" % ElementCounter.fmt_mult(bm))
		if assault != 1:
			tail.append("强袭×%s" % ElementCounter.fmt_mult(float(assault)))
		if pierce_total > 0:
			tail.append("穿透×直接HP")
		if tail.is_empty():
			blk.append("   合计 = %d" % total)
		else:
			blk.append("   小计 %d × %s = %d" % [int(round(normal_subtotal + pierce_subtotal)), " × ".join(tail), total])
		Debug.log("\n".join(blk))
	# 先破甲后掉血：非穿透先扣护甲溢出进 HP；穿透直接扣 HP
	if normal_total > 0:
		apply_enemy_damage(normal_total, false)
	if pierce_total > 0:
		apply_enemy_damage(pierce_total, true)
	if total > 0:
		if _ctrl.current_gimmick != null:
			_ctrl.current_gimmick.on_damaged(_ctrl, total)
		var elem_tag := ""
		if _ctrl._eval_adv:
			elem_tag += " [克制]"
		if _ctrl._eval_dis:
			elem_tag += " [抵抗]"
		if buff_mult != 1.0:
			elem_tag += "⚡"
		_ctrl.hud._popup("-%d%s" % [total, elem_tag], Palette.POP_DAMAGE, _ctrl.hud._enemy_sprite_anchor())
		_ctrl.hud._log("连线造成 %d 伤害%s（护甲剩 %d）" % [total, elem_tag, int(_ctrl.enemy_armor)])
		if _ctrl.hud.animator != null:
			_ctrl.hud.animator.play_attack("player", "enemy")
	# T21 元素充能：克制命中满额 → 释放元素爆发（穿透核爆 + 清甲，覆盖流爆发赛道）
	if _ctrl.charge_points >= DuelController.BALANCE.charge_max:
		_ctrl.charge_points = 0
		release_element_burst()
	_ctrl.hud._refresh_meta()   # 伤害落地后立即刷新：HP/护甲即时变化（破甲窗口需即时可见）
	await _ctrl.get_tree().create_timer(0.35).timeout
	# Phase C：回合末递减增益剩余回合
	tick_buffs()


# ---------------------------------------------------------------------------
# 属性聚合层 (F-0) — 所有「修正轴」的统一查询入口
# ---------------------------------------------------------------------------
# 本层把「加法标量 / 乘法标量 / 符号权重」三类轴统一成一组 agg_* 查询，
# 调用方只认聚合层、不认具体来源。新增修正轴只需在对应 agg_* 末尾加一行求和。
# 注意：本层只聚合「每符号 / 每回合」类修正；房开局护盾等「房间级」修正仍在原位处理。
# P0：以下结算聚合已抽到 BattleMath（参数化纯函数），此处仅剩薄包装。
# ---------------------------------------------------------------------------

func agg_power_flat() -> float:
	return BattleMath.agg_power_flat(_ctrl._reward_system.run_power_bonus, _ctrl.charm_power_bonus, _ctrl.player_buffs,
		float(_ctrl._shop_system.track_level("power")) * _ctrl._shop_system.track_per_level("power"))

func agg_shield() -> float:
	return BattleMath.agg_shield(_ctrl.player_buffs, _ctrl.charm_shield_trickle)

func agg_regen() -> float:
	return BattleMath.agg_regen(_ctrl.player_buffs, _ctrl.charm_heal_trickle)

func agg_damage_mult() -> float:
	return BattleMath.agg_damage_mult(_ctrl.charm_damage_mult, _ctrl.player_buffs)

# —— 符号权重轴（本局符号灌注；武器级权重见 _build_pool）——
func agg_symbol_weight_mod(sym: SymbolData) -> float:
	return BattleMath.agg_symbol_weight_mod(_ctrl._reward_system.run_symbol_bonus, sym)


# ---------------------------------------------------------------------------
# Phase C 主动增益：符号自描述（sym.buff_effect / buff_value / buff_turns），零查表
# player_buffs: SymbolData -> 剩余回合数
# ---------------------------------------------------------------------------
func grant_buff(sym: SymbolData, mult: int) -> void:
	var add = max(1, sym.buff_turns) * mult
	_ctrl.player_buffs[sym] = int(_ctrl.player_buffs.get(sym, 0)) + add
	_ctrl.hud._popup("%s+%d" % [sym.label, add], Palette.POP_BUFF, _ctrl.hud._player_sprite_anchor())
	_ctrl.hud._log("技能：%s %s（剩余 %d 回合）" % [sym.label, sym.name, _ctrl.player_buffs[sym]])


# 乘法型增益（多个同时生效则连乘）
func buff_damage_mult() -> float:
	return BattleMath.buff_damage_mult(_ctrl.player_buffs)


# T30：按当前 frost 层数随机挑选冻结列（spin 前冰封，每轮重选，frost 持续期间不可瞄准）。
# 不封废铁：跳过当前显示为 trash 的列（冻结废铁格 = 浪费），全为废铁时回落随机。
func pick_frozen_cols() -> Array[int]:
	var n: int = mini(_ctrl.player_frost, int(_ctrl._status_def("frost").max_cols))
	if n <= 0:
		return []
	var candidates: Array[int] = []
	for r in DuelController.REELS:
		var sym: SymbolData = _ctrl.grid[r][0] if _ctrl.grid.size() > r and _ctrl.grid[r].size() > 0 else null
		if sym != null and sym != DuelController.TRASH_SYMBOL:
			candidates.append(r)
	if candidates.size() < n:
		for r in DuelController.REELS:
			if not candidates.has(r):
				candidates.append(r)
	candidates.shuffle()
	var cols: Array[int] = []
	for i in n:
		cols.append(candidates[i])
	return cols


func tick_buffs() -> void:
	var expired: Array = []
	for sym in _ctrl.player_buffs.keys():
		_ctrl.player_buffs[sym] = int(_ctrl.player_buffs[sym]) - 1
		if _ctrl.player_buffs[sym] <= 0:
			expired.append(sym)
	for sym in expired:
		_ctrl.player_buffs.erase(sym)
		_ctrl.hud._log("增益结束：%s %s" % [sym.label, sym.name])


# 敌人攻击玩家（debuff 减益由元素驱动：frost/poison = 敌人减攻）。本函数是对玩家伤害的唯一闸口。
func enemy_deal_damage(raw: int) -> void:
	var atk_down = 1.0 - min(0.5, _ctrl.enemy_status.get("frost", 0) * 0.2 + _ctrl.enemy_status.get("poison", 0) * 0.2)
	var eff = int(round(float(raw) * atk_down * _ctrl.boss_atk_mult))
	if _ctrl.boss_atk_mult != 1.0:
		_ctrl.hud._log("🔒 呓语强化：敌人攻击 ×%s" % ElementCounter.fmt_mult(_ctrl.boss_atk_mult))
	if atk_down < 1.0:
		_ctrl.hud._log("敌人被削弱：攻击×%s" % ElementCounter.fmt_mult(atk_down))
	var blocked = min(_ctrl.player_shield, eff)
	_ctrl.player_shield -= blocked
	var dealt = max(0, eff - blocked)
	_ctrl.player_hp -= dealt
	if dealt > 0:
		_ctrl.hud._popup("-%d" % dealt, Palette.POP_DAMAGE, _ctrl.hud._player_sprite_anchor())
		if _ctrl.hud.animator != null:
			_ctrl.hud.animator.play_enemy_attack()
	_ctrl.hud._log("敌人攻击 %d（盾挡 %d，受 %d）" % [eff, blocked, dealt])


# 对敌人造成伤害（先破甲后掉血）：非穿透先扣护甲、溢出进 HP；穿透直接扣 HP。返回实际造成的总值。
func apply_enemy_damage(amount: float, pierce: bool) -> float:
	var dmg = max(0, int(round(amount)))
	if dmg <= 0:
		return 0.0
	if pierce:
		_ctrl.enemy_hp -= dmg
		return float(dmg)
	var to_armor = min(_ctrl.enemy_armor, float(dmg))
	_ctrl.enemy_armor -= to_armor
	var to_hp = dmg - to_armor
	_ctrl.enemy_hp -= to_hp
	return float(dmg)


# 反制即爆发（Plan C）：
# · "special" = 通用破甲：清空敌人护甲，开启「伤害直击 HP」的爆发窗口（所有敌人通用破绽）。
# · "element" = 进阶核爆：克制元素三连，除破甲外再追加一次直接打血（穿透）的核爆伤害。
func on_counter(kind: String) -> void:
	if _ctrl.enemy_armor > 0:
		_ctrl.hud._log("💥 %s破甲！护甲清零（%d）" % ["special 三连" if kind == "special" else "克制元素三连", int(_ctrl.enemy_armor)])
		_ctrl.enemy_armor = 0
	if kind == "element":
		var burst = int(_ctrl.enemy_hp_max * 0.20)
		if burst > 0:
			apply_enemy_damage(burst, true)
			_ctrl.hud._popup("💥克制核爆!-%d" % burst, Palette.POP_DAMAGE, _ctrl.hud._enemy_sprite_anchor())
			_ctrl.hud._log("⚡ 克制元素三连触发核爆：%d 伤害（穿透护甲）" % burst)
	if _ctrl.hud.animator != null:
		_ctrl.hud.animator.play_counter(kind)


# 敌人 DoT 状态结算（灼烧/毒/霜冻…，含元素克制与状态护符乘区；衰减由 StatusDef.decay 定义）
func tick_status() -> void:
	var dot = 0
	for st in _ctrl.enemy_status.keys():
		var base = _ctrl._status_base(st)
		var mult = ElementCounter.multiplier(_ctrl._status_element(st), _ctrl.enemy_element)
		# T2 状态护符：DoT 伤害乘倍率（状态叠加轴投资）；T23：衰减率由 StatusDef.decay 定义
		dot += int(round(_ctrl.enemy_status[st] * base * mult * DuelController.BALANCE.status_dmg_mult * _ctrl.charm_status_boost))
		var sd: StatusDef = _ctrl._status_def(st)
		_ctrl.enemy_status[st] = max(0, _ctrl.enemy_status[st] - (sd.decay if sd != null else 1))
		if _ctrl.enemy_status[st] <= 0:
			_ctrl.enemy_status.erase(st)
	if dot > 0:
		_ctrl.enemy_hp -= dot
		_ctrl.hud._log("状态结算 %d 伤害（灼烧/毒·含克制）" % dot)


# T21 元素充能爆发（覆盖流赛道）：克制命中满 charge_max 次后自动释放——
# 清甲 + 穿透核爆（无视护甲直击 HP），与三连破甲/核爆互补（分散积累 vs 单次高概率）。
func release_element_burst() -> void:
	var burst := int(_ctrl.enemy_hp_max * DuelController.BALANCE.charge_burst_pct)
	if _ctrl.enemy_armor > 0:
		_ctrl.enemy_armor = 0
		_ctrl.hud._log("⚡ 元素充能爆发：护甲清零！")
	if burst > 0:
		apply_enemy_damage(burst, true)
		_ctrl.hud._popup("⚡元素爆发!-%d" % burst, Palette.POP_DAMAGE, _ctrl.hud._enemy_sprite_anchor())
		_ctrl.hud._log("⚡ 元素充能爆发：%d 穿透伤害（直击 HP，无视护甲）" % burst)
	if _ctrl.hud.animator != null:
		_ctrl.hud.animator.play_counter("element")
