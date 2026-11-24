class_name CombatSystem
extends RefCounted

# combat_system — 战斗结算系统（2026-08-09 从 duel_controller 拆分）
#
# 职责：单回合结算（evaluate 编排四阶段：_phase_symbols / _phase_defense / _phase_counter / _phase_attack）、
# 符号贡献（_contribute：伤害/护盾/治疗/状态/特殊）、伤害分解行、敌人攻防、
# 三连破甲/核爆、元素充能爆发、增益/状态 tick、属性聚合层（_agg_*）。
#
# 状态共享：全部战斗状态（grid / enemy_* / player_* / charge_points / player_buffs / 护符）
# 仍由 DuelController 持有，本系统经 _ctrl 读写（与 shop_system 同一模式）；
# BOSS 机制钩子（current_gimmick.on_special_triple / on_damaged）回调传 _ctrl。
#
# 唯一 async 入口：evaluate()（内部 await 间隔，供飘字/动画演出）。

const PATTERN_MATCHER = preload("res://scripts/battle/pattern_matcher.gd")
const PATTERN_EFFECTS = preload("res://scripts/battle/pattern_effects.gd")

# 飘字节奏（2026-11-16）：同一回合内金币/护盾/治疗/状态会在不同阶段各自弹字，
# 原先它们在同一帧出生，即使有堆叠偏移也像一次性刷屏。这里在「连续第二条及以后」的
# 弹字前插入短间隔，让玩家能逐个读到。单条飘字不加延迟，空转回合不受影响。
const POPUP_BEAT := 0.36
# 护符图标闪起后、对应数值弹出前的停顿（实现「闪一下 → 数值出现」的顺序）
const CHARM_FLASH_HOLD := 0.30
# 三格扫描结束到开始出数值之间的停顿
const SWEEP_TO_NUMBERS_HOLD := 0.25

var _ctrl  # DuelController

# L3 §6.1 意图系统：敌人蓄力重击(heavy)时，本回合防御/治疗符号收益倍率。
# 在 evaluate 开头按 enemy_intent 计算一次，contribute 的 shield/heal 分支读取；只作用于符号，
# 不动护符/铁壁/回春等聚合来源——聚焦"看意图改按停目标"的决策。
const HEAVY_INTENT_DEFENSE_MULT := 1.5
var _intent_defense_mult: float = 1.0

# 本回合是否已经弹过「收益类」飘字（金币/护盾/治疗/状态）。
# 用于给第二条及以后的飘字插入 POPUP_BEAT 间隔；伤害飘字不参与（它在攻击阶段、
# 且必须紧跟扣血，延迟反而会加剧「血条先变、数字后到」）。
var _popup_fired_this_turn: bool = false
# 护符本回合是否已经脉冲过（一回合最多闪一次，避免刷屏）
var _charm_pulsed_this_turn: bool = false
# 本回合待播报的护符（结算阶段只记账，播报阶段才闪）
var _pending_defense_charms: Array = []
var _pending_damage_charms: Array = []
# 播报节奏
const CELL_PRESENT_STEP := 0.42      # 逐格播报：每格亮起 + 出数后的停留（所有回合统一）
const HEAL_SFX_HOLD := 1.55           # 治愈音(1.5s)播完所需的停留，避免与下一格重叠
const ATTACK_FLASH_HOLD := 0.36     # 攻击格齐亮后、总伤害数字出现前的停顿
const TURN_TAIL_HOLD := 0.85        # 播报结束到敌方回合之间的留白
# N-04（2026-11-21）：牌谱提示时序——只在牌谱实际触发时增加短停顿，普通 SPIN 零额外等待。
const PATTERN_BANNER_HOLD := 0.34   # 牌谱名称短提示：先看清牌型，再看到伤害数字
const PATTERN_CONTRIB_HOLD := 0.30  # 符号/牌谱追加贡献 → 总伤害之间的短停顿


# 收益类飘字：本回合第一条立刻弹，之后每条前插一个短间隔。
func _popup_gain(text: String, color: Color, anchor: Control) -> void:
	if _popup_fired_this_turn:
		await _ctrl.get_tree().create_timer(POPUP_BEAT).timeout
	_popup_fired_this_turn = true
	_ctrl.hud._popup(text, color, anchor)

# Step 4（2026-11-11）：本回合结果反馈的分类累计。只供 HUD 文案，不参与结算。
# 破甲量 = 特殊三连/充能爆发真正清掉的护甲；核爆/充能爆发 = 对应的穿透伤害。
var _turn_armor_cleared := 0
var _turn_counter_burst := 0
var _turn_charge_burst := 0

# N-03（2026-11-21）：敌人侧伤害分解账本（本回合累计，结算时顺带记，UI 只读不重算）。
# apply_enemy_damage 是敌人 HP/护甲的唯一变更点，分解值在这里记，保证「预览 = 结算」。
# 整段清甲（on_counter / release_element_burst 的 enemy_armor=0）已由 _turn_armor_cleared 记，
# 这里的 _turn_enemy_armor_consumed 只记非穿透伤害真正吃掉的护甲，两者相加 = 敌人护甲总损失。
var _turn_enemy_armor_consumed := 0
var _turn_enemy_pierce_damage := 0
var _turn_enemy_hp_direct := 0


func _init(ctrl) -> void:
	_ctrl = ctrl


# 单符号贡献：按 kind 路由到伤害/护盾/治疗/状态/特殊。acc 为回合累计字典（见 evaluate）。
func contribute(sym: SymbolData, raw: int, acc: Dictionary, elem: String, source_id: String = "", family_raw: int = -1, family_charge: bool = true) -> void:
	# raw = 当前来源的格数；family_raw = 同符号族总格数。混合来源各自结算，三连倍率只按符号族触发一次。
	var mult = raw
	var combo_raw: int = raw if family_raw < 0 else family_raw
	var sk: String = ReelSystem.source_key(sym.resource_path, source_id)
	var item_power: float = _ctrl._weapon_power_map.get(sk, _ctrl._weapon_power_map.get(sym.resource_path, 0.0))
	var flat: float = item_power + agg_power_flat() if item_power > 0.0 else sym.base + agg_power_flat()
	# bonus = 非 sym.base 部分（攻击力差值 + 元进度聚合），供 push_dmg_line 分解展示（恒等式 flat = sym.base + bonus）
	var bonus: float = flat - sym.base
	# 逐符号元素克制倍率（Phase G v2.0：通用元素乘区，奖罚并存·温和；共鸣可对该元素加成）
	# T2 元素优势护符：克制时额外加法加成（×1.5 → ×1.5+boost），抵抗/中性不生效（鼓励带对元素）
	# 2026-08-09：治疗/护盾/状态符号豁免元素乘区——不造成伤害，克制/抗性/充能/核爆一律不参与
	var em: float = 1.0
	if sym.kind == "damage" or sym.kind == "special":
		em = ElementCounter.multiplier(elem, _ctrl.enemy_element) * _ctrl._synergy_system.element_boost(elem)
		if em > 1.0 and _ctrl.deprived_level < 1 and _ctrl.charm_element_boost > 0.0:   # 无名虚空：元素加成护符剥离
			em += _ctrl.charm_element_boost
		if em > 1.0:
			_ctrl._eval_adv = true
			if family_charge:
				_ctrl._charge_elem_counts[elem] = int(_ctrl._charge_elem_counts.get(elem, 0)) + 1
				if combo_raw >= 2:
					_ctrl.charge_points += 1
					acc["counter_triple"] = true
		elif em < 1.0:
			_ctrl._eval_dis = true
	# 同源三连使用武器自己的专精倍率；同族混合三连固定为1.5倍；同元素共鸣不再自动必暴。
	var crit_rate: float = DuelController.BALANCE.crit_chance + _ctrl._item_crit_chance_map.get(sk, _ctrl._item_crit_chance_map.get(sym.resource_path, 0.0))
	var crit_mult_val := 1.0
	if raw >= 3:
		crit_mult_val = _ctrl._item_crit_map.get(sk, _ctrl._item_crit_map.get(sym.resource_path, 1.0)) + _ctrl._synergy_system.crit_bonus(sym)
	elif combo_raw >= 3:
		crit_mult_val = 1.5
	elif randf() < crit_rate:
		crit_mult_val = _ctrl._item_crit_map.get(sk, _ctrl._item_crit_map.get(sym.resource_path, 1.0)) + _ctrl._synergy_system.crit_bonus(sym)
	var source_triple: bool = raw >= 3 and source_id != ""
	var archetype: int = int(_ctrl._source_archetype_map.get(source_id, WeaponData.Archetype.MEDIUM))
	var weapon_type: int = int(_ctrl._source_weapon_type_map.get(source_id, WeaponData.WeaponType.MELEE))
	var magic_triple: bool = source_triple and archetype == WeaponData.Archetype.MAGIC
	if magic_triple:
		_ctrl.charge_points += 1
	# T2 破甲护符：非穿透符号按概率直击 HP（穿透护甲；无名虚空剥夺时概率归零）——damage/special 共用
	var pierce_p: float = _ctrl.charm_pierce_chance if _ctrl.deprived_level < 1 else 0.0
	match sym.kind:
		"damage":
			var dv = flat * mult * em
			if crit_mult_val > 1.0:
				dv *= crit_mult_val
			if source_triple and archetype == WeaponData.Archetype.LIGHT:
				dv *= 1.5
			if not _ctrl._turn_hit_used and _ctrl.charm_first_hit > 1.0 and _ctrl.deprived_level < 1:
				dv *= _ctrl.charm_first_hit
				_ctrl._turn_hit_used = true
			if combo_raw >= 3:
				acc["triple"] = true
			_note_damage_elem(elem)
			var e_key: String = elem if elem != "" else "none"
			var s_key: String = source_id if source_id != "" else sym.resource_path
			acc["dmg_by_elem"][e_key] = float(acc["dmg_by_elem"].get(e_key, 0.0)) + dv
			acc["source_dmg"][s_key] = float(acc["source_dmg"].get(s_key, 0.0)) + dv
			if sym.pierce_armor or randf() < pierce_p:
				acc["pierce"] += dv
			elif source_triple and weapon_type == WeaponData.WeaponType.RANGED:
				acc["pierce"] += dv * 0.35
				acc["dmg"] += dv * 0.65
				acc["dmg_bucket_by_elem"][e_key] = float(acc["dmg_bucket_by_elem"].get(e_key, 0.0)) + dv * 0.65
			else:
				acc["dmg"] += dv
				acc["dmg_bucket_by_elem"][e_key] = float(acc["dmg_bucket_by_elem"].get(e_key, 0.0)) + dv
			push_dmg_line(acc, sym, elem, flat, bonus, mult, em, dv, crit_mult_val)
		# 2026-08-07 重构：shield/heal 不吃武器攻击力/克制/元进度——只 = 符号 base × 连线 × 暴击（治疗/护盾符号保持小值，来自技能/房奖励）
		"shield":
			var sh: float = sym.base * mult * crit_mult_val * _intent_defense_mult
			acc["shield"] += sh
			# 按来源记账（表现层按格分配用；同一来源的格子公式相同，均分是精确的）
			var sh_key: String = source_id if source_id != "" else sym.resource_path
			acc["source_shield"][sh_key] = float(acc["source_shield"].get(sh_key, 0.0)) + sh
		# 治疗倍率由 BalanceConfig.heal_line_mults 配置，当前三连为 4.5 倍；
		# 2026-11-11 Step 1：倍率表移入配置，三连倍率可独立复测
		# 不吃暴击/连线精通/克制——治疗规则简单可预期；3连标记 heal_triple 供溢出转护盾
		"heal":
			var hv: float = sym.base * float(DuelController.BALANCE.heal_line_mults[mini(raw - 1, 2)]) * _intent_defense_mult
			acc["heal"] += hv
			var hl_key: String = source_id if source_id != "" else sym.resource_path
			acc["source_heal"][hl_key] = float(acc["source_heal"].get(hl_key, 0.0)) + hv
			if combo_raw >= 3:
				acc["heal_triple"] = true
		"status":  acc["status_stacks"][sym.status_type] = acc["status_stacks"].get(sym.status_type, 0) + mult * crit_mult_val + (int(_ctrl.charm_dot_amp) if _ctrl.deprived_level < 1 else 0) + int(_ctrl._item_status_bonus.get(sk, 0) if source_id != "" else _ctrl._item_status_bonus.get(sym.resource_path, 0)) + (1 if magic_triple else 0)
		"special":
			var sv = flat * mult * em
			if crit_mult_val > 1.0:
				sv *= crit_mult_val
			if source_triple and archetype == WeaponData.Archetype.LIGHT:
				sv *= 1.5
			if not _ctrl._turn_hit_used and _ctrl.charm_first_hit > 1.0 and _ctrl.deprived_level < 1:
				sv *= _ctrl.charm_first_hit
				_ctrl._turn_hit_used = true
			if combo_raw >= 3:
				acc["triple"] = true
			_note_damage_elem(elem)
			var e_key2: String = elem if elem != "" else "none"
			var s_key2: String = source_id if source_id != "" else sym.resource_path
			acc["dmg_by_elem"][e_key2] = float(acc["dmg_by_elem"].get(e_key2, 0.0)) + sv
			acc["source_dmg"][s_key2] = float(acc["source_dmg"].get(s_key2, 0.0)) + sv
			if sym.pierce_armor or randf() < pierce_p:
				acc["pierce"] += sv
			elif source_triple and weapon_type == WeaponData.WeaponType.RANGED:
				acc["pierce"] += sv * 0.35
				acc["special"] += sv * 0.65
				acc["dmg_bucket_by_elem"][e_key2] = float(acc["dmg_bucket_by_elem"].get(e_key2, 0.0)) + sv * 0.65
			else:
				acc["special"] += sv
				acc["dmg_bucket_by_elem"][e_key2] = float(acc["dmg_bucket_by_elem"].get(e_key2, 0.0)) + sv
			push_dmg_line(acc, sym, elem, flat, bonus, mult, em, sv, crit_mult_val)
		_: pass


# 2026-11-12 Step 2：记录本回合造成伤害的元素（去重），供「每回合首次受到某元素伤害」类普通特性读取。
func _note_damage_elem(elem: String) -> void:
	if elem == "none" or _ctrl.turn_damage_elems.has(elem):
		return
	_ctrl.turn_damage_elems.append(elem)


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


# T4 A3 测试接缝：是否需要在逐段回放之外再弹总伤害大数字。
# 0 段（纯破甲/空转）没有逐段飘字，需要补总伤害；>=2 段已有逐段飘字；
# 恰好 1 段时回放已弹过，不再叠总伤害。
func _should_show_total_popup(event_count: int) -> bool:
	return event_count != 1


# 结算：分四阶段（符号计数 → 防御/增益/状态 → 反制 → 攻击），接单向属性克制与强袭药剂。
# 2026-08-07：重转机制移除，单次结算（chain_mult 参数退役）
# 2026-11-08（G8）：原单函数按阶段拆分；执行顺序、RNG 调用与 await 时序与拆分前逐行一致。
func evaluate() -> void:
	_ctrl.turn_resolved = true   # 2026-11-12 Step 3：转轮已结束，此后施加的 debuff 从下一回合起计时
	# L3 §6.1：敌人蓄力重击时，本回合防御/治疗符号收益提升（看意图改按停目标）。
	_intent_defense_mult = HEAVY_INTENT_DEFENSE_MULT if String(_ctrl.enemy_intent.get("type", "")) == "heavy" else 1.0
	var acc := _new_acc()
	_reset_turn_state()
	# N-04：每次结算从干净跳过标志起步（演出中按回车置位，只作用本回合）。
	_ctrl.presentation_skip = false
	# N-03：每次结算都从干净账本起步（含 free_spin 重转），避免上一回合的分解值残留。
	if _ctrl.damage_preview != null:
		_ctrl.damage_preview.reset(_ctrl.turn_count)
	# N-03：记录玩家整段结算链出手前的敌人真实 HP/护甲快照（含破甲/核爆/爆发/血锁）。
	# 账本的唯一产出点在 _capture_enemy_preview —— 用 before/after 真实差，保证「预览 = 结算」。
	var enemy_hp_before: int = int(_ctrl.enemy_hp)
	var enemy_armor_before: int = int(_ctrl.enemy_armor)
	# T4：伤害表现账本从本回合真实起始 HP 开局（不与 damage_preview 混用，二者职责不同）。
	_ctrl.damage_ledger.begin(int(_ctrl.turn_count), enemy_hp_before)
	# 2026-11-16 顺序优化：结算与表现彻底分离。
	# 先跑完全部结算（不产生任何飘字/等待），再交给 _present_turn 按「读格 → 攻击齐亮」回放。
	# 三连/连线倍率依赖整行，必须先算完才知道每格的分量，所以只能「先算后放」。
	var counts := _phase_symbols(acc)
	_phase_defense(acc)
	_phase_counter(counts, acc)
	_apply_patterns(acc)
	_apply_circuits(acc, counts)   # G4-3/G4-6：本局回路（牌谱后、攻击前，读本回合已收集事件）
	_phase_attack(counts, acc)
	# N-03：玩家结算链全部结束（含 hp_floor 血锁收口）后，写入敌人侧分解账本。
	_capture_enemy_preview(enemy_hp_before, enemy_armor_before)
	# N-03：结算值已落地，但命中帧前先压幽灵快照（显示旧 HP/护甲），命中帧才切真实值。
	_ctrl.hud.hold_enemy_preview()
	await _present_turn(acc, counts)


# G7-D Step 5：shield_gain / heal_gain / heal_overflow_shield 只供底部反馈报「真实落地」数值，
# 不参与结算；结算仍读 shield / heal 原字段。
func _new_acc() -> Dictionary:
	return { "dmg": 0, "shield": 0, "heal": 0, "status_stacks": {}, "special": 0, "lines": [], "pierce": 0.0, "counter_triple": false, "triple": false, "heal_triple": false, "element_resonance": false,
		"shield_gain": 0, "heal_gain": 0, "heal_overflow_shield": 0,
		# 2026-11-15 转轮凑牌 Step 2：按元素拆分的结构化累计，供牌谱效果运算。
		# dmg_by_elem      = 该元素本轮造成的总伤害（含穿透），用于「某元素伤害 +X%」
		# dmg_bucket_by_elem = 其中真正进了 acc["dmg"] 的部分，用于「某元素伤害转穿透」
		"dmg_by_elem": {}, "dmg_bucket_by_elem": {}, "source_dmg": {},
		# 2026-11-16 顺序优化：按来源记账，供「按格子从左到右」逐格播报。
		# 只用于表现分配，不参与任何结算；聚合字段（shield/heal/dmg）仍是唯一口径。
		"source_heal": {}, "source_shield": {},
		"gold_gain": 0, "total_damage": 0, "elem_tag": "",
		"charm_shield": 0, "charm_heal": 0,
		# 无格子归属的飘字（增益授予 / 元素爆发）：结算时入队，播报时按阵营统一发出，
		# 避免它们在"读格"之前就弹出来打乱顺序。
		"pending_player_pops": [], "pending_enemy_pops": [], "pending_banners": [] }


# N-03：玩家结算链全部跑完后，用「结算前快照 vs 结算后真实值」写入敌人侧只读账本。
# 分解口径：
#   护甲损失 = 结算前护甲 - 结算后护甲（涵盖非穿透吃甲 + 整段清甲，不重算）
#   HP 损失  = 结算前 HP - 结算后 HP - 穿透伤害（非穿透溢出部分）
#   穿透伤害 = apply_enemy_damage 顺带记的 pierce 累加（直击 HP，不吃甲）
# 三项均为真实结算差，UI 只读展示；血锁（hp_floor）已包含在 after 里，故预览永远与最终一致。
func _capture_enemy_preview(hp_before: int, armor_before: int) -> void:
	var pv = _ctrl.damage_preview
	if pv == null:
		return
	var armor_after: int = max(0, int(_ctrl.enemy_armor))
	var hp_after: int = max(0, int(_ctrl.enemy_hp))
	var armor_loss: int = max(0, armor_before - armor_after)
	var hp_lost_total: int = max(0, hp_before - hp_after)
	var pierce: int = _turn_enemy_pierce_damage
	var hp_loss_normal: int = max(0, hp_lost_total - pierce)
	pv.enemy_hp_before = hp_before
	pv.enemy_armor_before = armor_before
	pv.enemy_armor_loss = armor_loss
	pv.enemy_hp_loss = hp_loss_normal
	pv.enemy_pierce_damage = pierce

func _reset_turn_state() -> void:
	_popup_fired_this_turn = false
	_pending_defense_charms = []
	_pending_damage_charms = []
	_charm_pulsed_this_turn = false
	_ctrl._eval_adv = false
	_ctrl._eval_dis = false
	_ctrl._turn_hit_used = false   # 碎片王冠（信物）：每回合首击标记重置
	_ctrl._charge_elem_counts = {}   # 主导元素统计每回合重置
	_ctrl.turn_damage_elems.clear()  # 2026-11-12 Step 2：本回合伤害元素记录（余烬傀儡等读取）
	_turn_armor_cleared = 0
	_turn_counter_burst = 0
	_turn_charge_burst = 0
	_turn_enemy_armor_consumed = 0
	_turn_enemy_pierce_damage = 0
	_turn_enemy_hp_direct = 0
	if _ctrl != null:
		_ctrl._pattern_enemy_atk_mult = 1.0   # W02 的敌方攻击乘区每回合重置


# —— 阶段 1：符号计数与贡献（含增益/金币符号）——
func _phase_symbols(acc: Dictionary) -> Dictionary:
	_ctrl.hud._clear_badges()

	# 符号族统计连线总数，第四项按来源记录格数；来源不拆散同族三连。
	# T30：冻结列（失效格）不参与计数——不匹配、不结算、无攻击
	var counts = {}
	for p in _ctrl.PAYLINES[0]:
		if p[0] in _ctrl.frozen_cols:
			continue
		var sym: SymbolData = _ctrl.grid[p[0]][p[1]]
		var elem: String = _ctrl.grid_elem[p[0]][p[1]]
		var src := ""
		if _ctrl.grid_src.size() > p[0] and _ctrl.grid_src[p[0]].size() > p[1]:
			src = String(_ctrl.grid_src[p[0]][p[1]])
		var key: String = sym.resource_path + "|" + elem
		if not counts.has(key):
			counts[key] = [sym, elem, 0, {}]
		counts[key][2] += 1
		counts[key][3][src] = int(counts[key][3].get(src, 0)) + 1
	# 同元素3格 = 元素共鸣：每回合一次充能，并强化本回合已有状态，不替代同源/同族三连。
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
		acc["element_resonance"] = true
		_ctrl.charge_points += 1
		_ctrl.hud._log("✦ 元素共鸣：同元素3格，充能+1；本回合状态+1")
	# Phase C：先结算 buff 符号（本回合即生效，命中当回合就吃到增益）
	for key in counts:
		var s: SymbolData = counts[key][0]
		if s.kind != "buff":   # trash/MISS(同为 kind=trash) 一律跳过
			continue
		grant_buff(s, counts[key][2], acc)
	# 金币符号（常驻）：落在线上的金币直接转化为金币资源，不造成任何伤害
	for key in counts:
		var s: SymbolData = counts[key][0]
		if s == DuelController.GOLD_SYMBOL:
			var g = DuelController.BALANCE.gold_per_coin * counts[key][2]
			if g > 0:
				_ctrl.gold += g
				_ctrl.hud._log("💰 金币 +%d" % g)
				# 只记账，飘字留给 _present_turn 按格子顺序播报
				acc["gold_gain"] = int(acc.get("gold_gain", 0)) + g
	# 每个来源分别结算自身格数，同族总数只负责连线、三连和充能判定。
	for key in counts:
		var s: SymbolData = counts[key][0]
		var elem: String = counts[key][1]
		var c: int = counts[key][2]
		if s.kind == "trash" or s.kind == "buff" or s == DuelController.GOLD_SYMBOL:
			continue
		if s.kind == "special" and c < 1:
			continue
		var first_source := true
		for src in counts[key][3]:
			var source_count: int = int(counts[key][3][src])
			_ctrl.mastery.note_settle(s.resource_path, String(src))
			contribute(s, source_count, acc, elem, String(src), c, first_source)
			first_source = false

	# 匹配角标（×N，N>=2）
	_ctrl.hud._update_match_badges(counts)
	# 2026-11-12 Step 1：反噬判定——连续使用上一回合出现过的符号时记小额代价（每回合最多一次）。
	# 只读本回合停轮结果，不消耗 RNG；未挂反噬时仅更新「上一回合符号」记录。
	if _ctrl.debuffs != null:
		var turn_syms: Array[String] = []
		for key in counts:
			var s: SymbolData = counts[key][0]
			if s.kind == "trash" or s == DuelController.GOLD_SYMBOL:
				continue
			var p: String = s.resource_path
			if not turn_syms.has(p):
				turn_syms.append(p)
		_ctrl.debuffs.note_turn_symbols(_ctrl, turn_syms)
	return counts


# 转轮凑牌：三轨判定（2026-11-15 Step 2）。
#   weapon_public（G01–G03）+ weapon_attack（W）只读武器牌；
#   skill_support（T）恰好一张技能牌 + 两张武器牌。
# 每轨独立，各自每回合最多一条；所有效果写进累计器，不重算符号。
func _apply_patterns(acc: Dictionary) -> void:
	if _ctrl == null or _ctrl._pattern_system == null:
		return
	var all_cards: Array = PATTERN_MATCHER.cards_from_grid(_ctrl)
	var weapon_cards: Array = []
	var skill_cards: Array = []
	for c in all_cards:
		if not bool(c.get("valid", true)):
			continue
		var k := String(c.get("source_kind", "resource"))
		if k == "weapon":
			weapon_cards.append(c)
		elif k == "skill":
			skill_cards.append(c)

	# —— 武器轨 ——
	var m: Dictionary = PATTERN_MATCHER.match(weapon_cards)
	acc["pattern_match"] = m
	var ids: Array = []
	for p in m["patterns"]:
		ids.append(String(p.get("id", "")))
	var loadout: Array = _ctrl.selected_loadout.duplicate()
	var unlocked_weapon: Array = _ctrl._pattern_system.unlocked_patterns(loadout, _ctrl._pattern_tag_of)
	acc["patterns_universal"] = _ctrl._pattern_system.resolve_universal(ids, unlocked_weapon)
	var w_pool: Array = _pick_track(unlocked_weapon, "weapon_attack")
	var w_hits: Array = PATTERN_MATCHER.match_rules(weapon_cards, w_pool)
	var w_pick = _ctrl._pattern_system.resolve_equipment(w_hits, w_pool)
	if w_pick != null:
		# 签名：修改所属基础牌谱的效果参数；须三选一习得 + 携带专属武器(key_paths) + 牌型满足才生效（2026-11-19 恢复签名语义）
		var all_equip: Array = loadout.duplicate()
		all_equip.append_array(_ctrl.selected_charms)
		all_equip.append_array(_ctrl.run_relics)   # L2-E：遗物也参与签名牌谱解锁判定（拥有即生效）
		# 2026-11-19：签名全解锁，不再传 learned；带专属武器+牌型即自动生效
		var sig = _ctrl._pattern_system.find_signature(String(w_pick.id), all_equip, weapon_cards)
		acc["pattern_weapon"] = String(w_pick.id)
		acc["pattern_equipment"] = String(w_pick.id)   # 兼容既有断言与展示
		acc["pattern_signature"] = String(sig.id) if sig != null else ""
		if _ctrl.hud != null:
			var sig_txt := ""
			if sig != null:
				sig_txt = "·%s" % String(sig.name)
			_ctrl.hud._log("🗂 武器牌谱 %s %s%s" % [
				String(w_pick.id), String(w_pick.name), sig_txt])
			# 中频高潮：频率固定后靠这一下撑分量，签名用金色区分
			var icon := String(sig.icon) if sig != null else String(w_pick.icon)
			var banner_color := Palette.POP_DAMAGE if sig == null else Palette.POP_GOLD
			# 入队，播报最开始统一放出（避免在"读格"之前抢跑）
			acc["pending_banners"].append({"text": "%s %s %s%s" % [
				icon, String(w_pick.id), String(w_pick.name), sig_txt], "color": banner_color})
		PATTERN_EFFECTS.apply(acc, sig if sig != null else w_pick, {"ctrl": _ctrl})

	# —— 技能轨：恰好 1 技能 + 2 武器 ——
	if skill_cards.size() == 1 and weapon_cards.size() == 2:
		var skill_load: Array = _ctrl.selected_skills.duplicate()
		var unlocked_skill: Array = _ctrl._pattern_system.unlocked_patterns(skill_load, _ctrl._pattern_tag_of)
		var t_pool: Array = _pick_track(unlocked_skill, "skill_support")
		if not t_pool.is_empty():
			var t_hits: Array = PATTERN_MATCHER.match_rules(all_cards, t_pool)
			var t_pick = _ctrl._pattern_system.resolve_equipment(t_hits, t_pool)
			# T03 满血时不激活，避免出现「治疗 +25% 但没得治」的无效候选
			if t_pick != null and String(t_pick.effect_id) == "recovery_support" \
					and int(_ctrl.player_hp) >= int(_ctrl.player_hp_max):
				t_pick = null
			if t_pick != null:
				acc["pattern_skill"] = String(t_pick.id)
				if _ctrl.hud != null:
					_ctrl.hud._log("🗂 技能术式 %s %s" % [String(t_pick.id), String(t_pick.name)])
					var t_color: Color = Palette.POP_SHIELD
					if String(t_pick.effect_id) == "recovery_support":
						t_color = Palette.POP_HEAL
					elif String(t_pick.effect_id) == "power_support":
						t_color = Palette.POP_BUFF
					acc["pending_banners"].append({"text": "%s %s %s" % [
						String(t_pick.icon), String(t_pick.id), String(t_pick.name)], "color": t_color})
				PATTERN_EFFECTS.apply(acc, t_pick, {"ctrl": _ctrl})

	# 常驻面板：本回合可用牌谱与组件状态（§9.1 两分区）
	if _ctrl.hud != null:
		_ctrl.hud.update_pattern_tray(_build_tray_entries(all_cards, weapon_cards, unlocked_weapon, acc))

	# 牌谱新增的状态层在这里落地（_phase_defense 已经跑过，不能复用 status_stacks）
	for st in acc.get("pattern_status", {}).keys():
		var n := int(acc["pattern_status"][st])
		if n > 0:
			_ctrl.add_enemy_status(st, n)


# G4-3：本局回路结算。读本回合已收集的原始事件（三连/状态/破甲），按回路声明赔付。
# 位置在牌谱之后、攻击之前（G4-1 契约插入点）。回路只响应原始事件，不响应自己的追加结果
# ——应用赔付时用 begin_resolve/end_resolve 防递归。
func _apply_circuits(acc: Dictionary, counts: Dictionary) -> void:
	var c = _ctrl.circuit_system
	if c == null:
		return
	c.reset_spin()   # 每 SPIN 重置回路的每SPIN上限计数
	# 原始事件→回路触发事件（与 CircuitSystem.DEFINITIONS 的 event 字段对应）
	if acc.get("triple", false) or acc.get("counter_triple", false) or acc.get("heal_triple", false):
		_apply_circuit_fired(c.try_trigger("triple"), acc, "triple")
	if not acc.get("status_stacks", {}).is_empty():
		_apply_circuit_fired(c.try_trigger("status_applied"), acc, "status_applied")
	if acc.get("armor_broken", false):
		_apply_circuit_fired(c.try_trigger("armor_break"), acc, "armor_break")
	# G4-6 新增三事件（覆盖牌型/元素/资源三类组合条件）
	if _has_pair_damage(counts) and not acc.get("triple", false) and not acc.get("counter_triple", false):
		_apply_circuit_fired(c.try_trigger("pair"), acc, "pair")
	if _has_three_colors(counts):
		_apply_circuit_fired(c.try_trigger("tri_color"), acc, "tri_color")
	if float(acc.get("dmg", 0.0)) > 0.0 and float(acc.get("shield", 0.0)) > 0.0:
		_apply_circuit_fired(c.try_trigger("damage_and_shield"), acc, "damage_and_shield")


# 恰好一对同族伤害（某 damage 符号族恰 2 格，且存在另一不同的有效符号族；不与三连共存）。
func _has_pair_damage(counts: Dictionary) -> bool:
	var pair_family := ""
	for key in counts:
		var d: Array = counts[key]
		if String(d[0].kind) != "damage" or int(d[2]) != 2:
			continue
		pair_family = String(key)
		break
	if pair_family.is_empty():
		return false
	for key in counts:
		var d: Array = counts[key]
		if String(key) != pair_family and int(d[2]) >= 1:
			return true
	return false


# 三列三种不同有效元素（方案 §12.2 异色协奏；ROELS=3）。
func _has_three_colors(counts: Dictionary) -> bool:
	var elems := {}
	var total := 0
	for key in counts:
		var d: Array = counts[key]
		var e: String = String(d[1])
		if e == "none":
			continue
		elems[e] = true
		total += int(d[2])
	return elems.size() >= 3 and total >= 3


func _apply_circuit_fired(ids: Array, acc: Dictionary, event: String) -> void:
	if ids.is_empty() or _ctrl.circuit_system == null:
		return
	var c = _ctrl.circuit_system
	c.begin_resolve()
	for id in ids:
		var def: Dictionary = c.definition(id)
		var payout: String = String(def.get("payout", ""))
		match payout:
			"bonus_damage":
				acc["dmg"] = float(acc.get("dmg", 0.0)) + CIRCUIT_BONUS_DAMAGE
				acc["lines"].append("🔁 %s 回响 +%d 伤害" % [String(def.get("name", "回路")), CIRCUIT_BONUS_DAMAGE])
			"extra_stack":
				var stacks: Dictionary = acc.get("status_stacks", {})
				for st in stacks.keys():
					stacks[st] = int(stacks[st]) + CIRCUIT_EXTRA_STACK
				acc["lines"].append("🔁 %s 状态反应 +%d 层" % [String(def.get("name", "回路")), CIRCUIT_EXTRA_STACK])
			"pierce_damage":
				acc["pierce"] = float(acc.get("pierce", 0.0)) + CIRCUIT_PIERCE_DAMAGE
				acc["lines"].append("🔁 %s 余波 +%d 穿透" % [String(def.get("name", "回路")), CIRCUIT_PIERCE_DAMAGE])
			"pair_bonus":
				# 对子效能 +35%（这里以本回合 dmg 为基准，简化为固定比例加成）
				var pair_add: float = float(acc.get("dmg", 0.0)) * CIRCUIT_PAIR_RATIO
				acc["dmg"] = float(acc.get("dmg", 0.0)) + pair_add
				acc["lines"].append("🔁 %s 对子 +%d%% 效能" % [String(def.get("name", "回路")), int(CIRCUIT_PAIR_RATIO * 100.0)])
			"tri_color_pierce":
				var tri_add: float = float(acc.get("dmg", 0.0)) * CIRCUIT_TRI_COLOR_RATIO
				acc["pierce"] = float(acc.get("pierce", 0.0)) + tri_add
				acc["lines"].append("🔁 %s 异色 +%d%% 穿透" % [String(def.get("name", "回路")), int(CIRCUIT_TRI_COLOR_RATIO * 100.0)])
			"damage_shield_pierce":
				var ds_add: float = float(acc.get("shield", 0.0)) * CIRCUIT_DAMAGE_SHIELD_RATIO
				acc["pierce"] = float(acc.get("pierce", 0.0)) + ds_add
				acc["lines"].append("🔁 %s 攻守 +%d%% 护盾穿透" % [String(def.get("name", "回路")), int(CIRCUIT_DAMAGE_SHIELD_RATIO * 100.0)])
	c.end_resolve()
	if _ctrl.hud != null:
		_ctrl.hud._log("🔁 回路触发：%s（%s）" % [str(ids), event])


const CIRCUIT_BONUS_DAMAGE := 5.0
const CIRCUIT_EXTRA_STACK := 1
const CIRCUIT_PIERCE_DAMAGE := 4.0
const CIRCUIT_PAIR_RATIO := 0.35        # 对子赔付：对子部分 +35% 效能（方案 §12.2）
const CIRCUIT_TRI_COLOR_RATIO := 0.20   # 异色协奏：本次伤害 +20% 穿透
const CIRCUIT_DAMAGE_SHIELD_RATIO := 0.30  # 攻守转换：护盾入账 +30% 穿透


# 常驻面板的数据：武器牌谱最多 2 条（避免面板过长），技能术式只显示与当前技能匹配的那条。
func _build_tray_entries(all_cards: Array, weapon_cards: Array, unlocked_weapon: Array, acc: Dictionary) -> Array:
	var out: Array = []
	var shown := 0
	for p in unlocked_weapon:
		if String(p.track) != "weapon_attack":
			continue
		if shown >= 2:
			break
		out.append(_tray_entry(p, weapon_cards, acc, "武器牌谱"))
		shown += 1
	var skill_load: Array = _ctrl.selected_skills.duplicate()
	if not skill_load.is_empty():
		var unlocked_skill: Array = _ctrl._pattern_system.unlocked_patterns(skill_load, _ctrl._pattern_tag_of)
		for p in unlocked_skill:
			if String(p.track) != "skill_support":
				continue
			var entry := _tray_entry(p, all_cards, acc, "技能术式")
			# 技能牌不在手牌时也显示，但组件会标成「未满足」，玩家能看出「差一张技能牌」
			out.append(entry)
			break
	return out


func _tray_entry(p, cards: Array, acc: Dictionary, section: String) -> Dictionary:
	var d: Dictionary = PATTERN_MATCHER.diagnose(cards, p.match_rule)
	var conds: Array = (p.match_rule as Dictionary).get("all", [])
	var parts: Array = []
	for i in range(conds.size()):
		parts.append({
			"text": PATTERN_MATCHER.describe_condition(conds[i]),
			"ok": (d["satisfied"] as Array).has(i),
		})
	var pid := String(p.id)
	var active := String(acc.get("pattern_weapon", "")) == pid or String(acc.get("pattern_skill", "")) == pid
	return {
		"section": section, "id": pid, "name": String(p.name), "icon": String(p.icon),
		"parts": parts, "done": bool(d["done"]), "active": active,
	}


func _pick_track(patterns: Array, track: String) -> Array:
	var out: Array = []
	for p in patterns:
		if String(p.track) == track:
			out.append(p)
	return out


# —— 阶段 2：防御 / 增益 / 状态先落地 ——
func _phase_defense(acc: Dictionary) -> void:
	# Phase C：铁壁(shield)/回春(regen) 按回合生效，并入本回合护盾与治疗（F-0 聚合层）
	acc["shield"] += int(agg_shield())
	acc["heal"] += int(agg_regen())
	# 护符分量（守备/回春涓流）：聚合值里已包含，这里单独记出来供播报时「护符闪 → 它的数」
	acc["charm_shield"] = int(_ctrl.charm_shield_trickle) if _ctrl.deprived_level < 1 else 0
	acc["charm_heal"] = int(_ctrl.charm_heal_trickle) if _ctrl.deprived_level < 1 else 0
	# 2026-11-12 Step 1：腐蚀 / 禁疗在「全部来源聚合之后、落地之前」统一折算，
	# 覆盖符号、铁壁/回春等所有护盾/治疗来源，避免只砍符号的漏算。
	if _ctrl.debuffs != null:
		var shield_mult: float = _ctrl.debuffs.shield_mult()
		if shield_mult != 1.0 and acc["shield"] > 0:
			acc["shield"] = int(round(float(acc["shield"]) * shield_mult))
			_ctrl.hud._log("🧪 腐蚀：本回合护盾收益 ×%s" % ElementCounter.fmt_mult(shield_mult))
		var heal_mult: float = _ctrl.debuffs.heal_mult()
		if heal_mult != 1.0 and acc["heal"] > 0:
			acc["heal"] = int(round(float(acc["heal"]) * heal_mult))
			_ctrl.hud._log("🚫 禁疗：本回合治疗收益 ×%s" % ElementCounter.fmt_mult(heal_mult))
	if acc.get("element_resonance", false):
		for st in acc["status_stacks"].keys():
			acc["status_stacks"][st] += 1
	for st in acc["status_stacks"].keys():
		_ctrl.add_enemy_status(st, int(acc["status_stacks"][st]))
	if not _charm_pulsed_this_turn and _ctrl.deprived_level < 1:
		var defense_charms: Array = _ctrl.charm_paths_for_signal("defense")
		if not defense_charms.is_empty():
			_charm_pulsed_this_turn = true
			_pending_defense_charms = defense_charms
	if acc["shield"] > 0:
		_ctrl.player_shield += acc["shield"]
		acc["shield_gain"] = int(acc["shield"])
		_ctrl.hud._log("获得 %d 护盾" % acc["shield"])
	if acc["heal"] > 0:
		var missing: int = _ctrl.player_hp_max - _ctrl.player_hp
		var hp_gain: int = mini(int(acc["heal"]), missing)
		# 2026-11-23：治疗显示锁——先锁住旧血值，HP 数据照常落地，
		# 但血条保持旧值，直到 heal 格演出帧释放（与治愈音同帧）。音画/数据同步。
		if hp_gain > 0:
			_ctrl.hud.hold_heal_display(int(_ctrl.player_hp))
		_ctrl.player_hp += hp_gain
		acc["heal_gain"] = hp_gain
		var overflow_shield := 0
		if hp_gain > 0:
			_ctrl.hud._log("回复 %d HP" % hp_gain)
		# 2026-08-07 方案 A：治疗三连溢出转护盾（满血不浪费，三连独有奖励）
		# 三拍板②（2026-08-24）：单次溢出转盾 ≤ maxHP × heal_overflow_shield_cap_pct（20%）——
		# 防单次爆炸性囤盾；全面衰减机制挂 F6 盾流实测后再议
		if acc.get("heal_triple", false) and int(acc["heal"]) > missing:
			var shield_gain: int = int(acc["heal"]) - missing
			var overflow_cap: int = int(_ctrl.player_hp_max * DuelController.BALANCE.heal_overflow_shield_cap_pct)
			shield_gain = mini(shield_gain, overflow_cap)
			_ctrl.player_shield += shield_gain
			overflow_shield = shield_gain
			acc["heal_overflow_shield"] = shield_gain
			_ctrl.hud._log("治疗三连溢出转护盾 +%d（上限 %d）" % [shield_gain, overflow_cap])
		if _ctrl._telemetry != null:
			_ctrl._telemetry.on_heal(hp_gain, overflow_shield)   # Step 1 复测：治疗/转盾只统计，不改结算
	if not acc["status_stacks"].is_empty():
		_ctrl.hud._log("敌人获得状态: " + _ctrl.status_system.status_summary(acc["status_stacks"]))
	# 状态飘字、血条刷新与收尾等待全部移到 _present_turn（敌方侧结算统一在攻击齐亮之后播报）


# —— 阶段 3：反制（三连钩子 / 破甲 / 核爆）——
func _phase_counter(counts: Dictionary, acc: Dictionary) -> void:
	# S10 T5 钩子点 + 破甲/核爆（2026-08-07 通用化：任意同符号三连触发；破甲仅限带破甲机制的武器/技能）。
	# current_gimmick 仅在 BOSS 房由 T2 的 BossGimmick 子类赋值；非 BOSS 房为 null，显式判空跳过（避免 ?. 在某些 4.x 不兼容）。
	if acc.get("triple", false):
		_ctrl.hud._log("⚡ 三连触发")
		if _ctrl.current_gimmick != null:
			_ctrl.current_gimmick.on_special_triple(_ctrl)   # BOSS 自定义钩子（三连感知，语义泛化）

	# 破甲：带破甲机制（triple_pierce）的连携 → 清甲；克制三连 → 核爆（清甲 + 按比例穿透）
	# G6-05 破城铸式把该武器的破甲所需连数降到 2（其它来源仍为 3）。
	var triple_pierce: bool = false
	var pierce_need := 3
	for key in counts:
		var sp: String = counts[key][0].resource_path
		for src in counts[key][3]:
			var source_id := String(src)
			var sk: String = ReelSystem.source_key(sp, source_id)
			var need := int(_ctrl._item_pierce_at.get(sk, 3) if source_id != "" else _ctrl._item_pierce_at.get(sp, 3))
			var has_pierce: bool = bool(_ctrl._item_pierce_map.get(sk, false) if source_id != "" else _ctrl._item_pierce_map.get(sp, false))
			var source_count := int(counts[key][3][src])
			var heavy_triple: bool = source_count >= 3 and int(_ctrl._source_archetype_map.get(source_id, -1)) == WeaponData.Archetype.HEAVY
			if (has_pierce and source_count >= need) or heavy_triple:
				triple_pierce = true
				pierce_need = mini(pierce_need, need)
				break
		if triple_pierce:
			break
	if acc.get("counter_triple", false):
		on_counter("element", 3, acc)
	elif triple_pierce:
		on_counter("special", pierce_need, acc)


# —— 阶段 4：攻击结算与回合收口 ——
func _phase_attack(counts: Dictionary, acc: Dictionary) -> void:
	# —— 攻击结算（先破甲后掉血；穿透符号直接扣 HP）——
	# Phase C：迅捷(damage_mult) 对本回合总伤害做乘算（F-0 聚合层，含护符乘区）
	var buff_mult = agg_damage_mult()
	# 攻击侧同理：只有「提供伤害类效果」的护符才闪。
	if not _charm_pulsed_this_turn and _ctrl.deprived_level < 1:
		var damage_charms: Array = _ctrl.charm_paths_for_signal("damage")
		if not damage_charms.is_empty():
			_charm_pulsed_this_turn = true
			_pending_damage_charms = damage_charms
	# 2026-11-12 Step 1：虚弱对「连线+穿透」总伤害乘算；核爆/充能爆发按 maxHP 比例，不受虚弱影响。
	var debuff_mult: float = _ctrl.debuffs.damage_mult() if _ctrl.debuffs != null else 1.0
	# 迷面诡匠「镜面夺盾」的无盾兜底：下回合伤害打折，用掉即清（一次性）
	var mirror_mult: float = float(_ctrl.mirror_dmg_mult)
	_ctrl.mirror_dmg_mult = 1.0
	var assault = _ctrl.assault_next_spin
	var normal_subtotal = acc["dmg"] + acc["special"]
	var pierce_subtotal = acc.get("pierce", 0.0)
	var normal_total = int(normal_subtotal * assault * buff_mult * DuelController.BALANCE.player_dmg_mult * debuff_mult * mirror_mult)
	var pierce_total = int(pierce_subtotal * assault * buff_mult * DuelController.BALANCE.player_dmg_mult * debuff_mult * mirror_mult)
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
		if debuff_mult != 1.0:
			tail.append("虚弱×%s" % ElementCounter.fmt_mult(debuff_mult))
		if DuelController.BALANCE.player_dmg_mult != 1.0:
			tail.append("全局×%s" % ElementCounter.fmt_mult(DuelController.BALANCE.player_dmg_mult))
		if pierce_total > 0:
			tail.append("穿透直击")
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
		# 只记账，飘字与攻击动画留到 _present_turn 的「攻击齐亮」步骤
		acc["total_damage"] = total
		acc["elem_tag"] = elem_tag
		_ctrl.hud._log("连线造成 %d 伤害%s（护甲剩 %d）" % [total, elem_tag, int(_ctrl.enemy_armor)])
	# Step 5：底部单行短反馈（连击/克制/总伤害）。纯展示：读本回合结算结果，不改数值、不加时序等待。
	# G7-D Step 5：护盾/治疗只报真实入账值（满血无回血时不显示「恢复」）。
	# Step 4：破甲/核爆/充能爆发在充能爆发结算之后再统一上报（见下方 apply_enemy_hp_floor 后）。
	# T21 元素充能：克制命中满额 → 释放元素爆发（穿透核爆 + 清甲，覆盖流爆发赛道）
	if _ctrl.charge_points >= DuelController.BALANCE.charge_max:
		_ctrl.charge_points = 0
		release_element_burst(acc)
	_ctrl.apply_enemy_hp_floor()   # P-审计 P1：爆发/穿透等一切扣血后统一收口（血锁防旁路）
	# 底部短反馈 / 血条刷新 / 前摇动画全部移到 _present_turn，按「读格 → 攻击齐亮」的顺序播报
	# 天平审判官：玩家转轮结算完成通知（空转/MISS 回合也触发，规则判定读 ctrl.grid 停轮结果）
	if _ctrl.current_gimmick != null:
		_ctrl.current_gimmick.on_turn_resolved(_ctrl)
	# Phase C：回合末递减增益剩余回合
	tick_buffs()
	# 2026-11-12 Step 1：减益计时在「玩家实际经历完本回合」后结算（施放当回合不扣）。
	if _ctrl.debuffs != null:
		_ctrl.debuffs.tick_turn_end(_ctrl)
	if _ctrl._telemetry != null:
		_ctrl._telemetry.on_turn(bool(acc.get("triple", false)))   # M1-06：回合与三连率
	_ctrl.invalidate_state()   # 伤害/护盾/充能/状态与 gimmick 钩子写入（on_special_triple/on_damaged/on_turn_resolved）统一在此覆盖


# ---------------------------------------------------------------------------
# 回合播报（2026-11-16）：结算与表现分离——先全部算完，再按「读格 → 攻击齐亮」回放。
# 纯展示：只读 acc / grid，不写战斗状态、不改数值、不消耗 RNG。
# 分组依据是「接收方」而不是「效果类型」：
#   玩家侧收益（治疗/护盾/金币/增益）→ 按格子左到右逐个亮起并出数
#   敌人侧结算（攻击/状态）          → 所有攻击格一起亮，只出一次总伤害
# ---------------------------------------------------------------------------

func _cell_kind(reel: int) -> String:
	if reel < 0 or reel >= _ctrl.grid.size() or _ctrl.grid[reel].is_empty():
		return ""
	var sym = _ctrl.grid[reel][0]
	return String(sym.kind) if sym != null else ""


func _cell_source(reel: int) -> String:
	if reel < 0 or reel >= _ctrl.grid_src.size() or _ctrl.grid_src[reel].is_empty():
		return ""
	return String(_ctrl.grid_src[reel][0])


func _cell_is_gold(reel: int) -> bool:
	if reel < 0 or reel >= _ctrl.grid.size() or _ctrl.grid[reel].is_empty():
		return false
	return _ctrl.grid[reel][0] == DuelController.GOLD_SYMBOL


# 玩家侧收益格：按格读出数；其余（攻击/状态/MISS）归入「攻击齐亮」
func _cell_is_player_gain(reel: int) -> bool:
	if _cell_is_gold(reel):
		return true
	var k := _cell_kind(reel)
	# 2026-11-23：status（施加状态层）属增益，应与 heal/shield/buff 一起逐格闪烁，
	# 不能归入 attack_reels 走「攻击齐亮」——否则会和攻击符号同时闪且播错音。
	return k == "heal" or k == "shield" or k == "buff" or k == "status"


func _reels_of_source(src: String) -> Array:
	var out: Array = []
	for reel in DuelController.REELS:
		if _cell_source(reel) == src:
			out.append(reel)
	return out


# 把某来源的总量均分到它的各格，余数给最后一格 → 各格之和必然等于总量（不会出现对不上）
func _alloc_by_reels(total: float, reels: Array) -> Dictionary:
	var out := {}
	var n: int = reels.size()
	if n <= 0:
		return out
	var rounded: int = int(round(total))
	var per: int = int(floor(float(rounded) / float(n)))
	for i in n:
		out[int(reels[i])] = per if i < n - 1 else rounded - per * (n - 1)
	return out


# 该格的收益文本（治疗/护盾/金币）；无收益返回空字典
func _gain_text_of_reel(reel: int, acc: Dictionary) -> Dictionary:
	if _cell_is_gold(reel):
		return {"text": "💰+%d" % int(DuelController.BALANCE.gold_per_coin), "color": Palette.POP_GOLD}
	var src := _cell_source(reel)
	var k := _cell_kind(reel)
	var reels := _reels_of_source(src)
	if k == "heal":
		# 治疗有满血上限：按「真实入账 / 总治疗」缩放，保证各格数字之和 == 血条实际回血量
		var scale := 0.0
		if float(acc["heal"]) > 0.0:
			scale = float(int(acc.get("heal_gain", 0))) / float(acc["heal"])
		var v: int = int(_alloc_by_reels(float(acc["source_heal"].get(src, 0.0)) * scale, reels).get(reel, 0))
		if v > 0:
			return {"text": "❤+%d" % v, "color": Palette.POP_HEAL}
	elif k == "shield":
		var v2: int = int(_alloc_by_reels(float(acc["source_shield"].get(src, 0.0)), reels).get(reel, 0))
		if v2 > 0:
			return {"text": "🛡+%d" % v2, "color": Palette.POP_SHIELD}
	return {}


# N-04：演出等待统一走这里——快速跳过只把「等待时长」压到 0，不改任何结算/数值/RNG。
# 跳过标志由 duel_controller.presentation_skip 提供（按键触发，演出中按一次即生效到本回合结束）。
func _present_wait(tree: SceneTree, seconds: float) -> void:
	if seconds <= 0.0:
		return
	if _ctrl.presentation_skip:
		# 压到最小一帧，保证 await 链仍推进（不原地卡死），但不产生可感知等待。
		await tree.process_frame
		return
	await tree.create_timer(seconds).timeout

# N-04：牌谱追加贡献的只读展示文案。数据来自结算时 pattern_effects 写入 acc["lines"] 的行，
# 这里只是筛选/拼接，不重算数值、不改 acc。无牌谱贡献行时返回空串（该步跳过、零额外等待）。
func _pattern_contrib_text(acc: Dictionary) -> String:
	var lines: Array = acc.get("lines", [])
	var parts: Array[String] = []
	for l in lines:
		var s := String(l).strip_edges()
		# pattern_effects 的贡献行统一带「✦」或「牌谱」前缀；伤害分解行是「🔍 伤害分解」不算。
		if s.begins_with("✦") or s.contains("牌谱「") or s.contains("共鸣") or s.contains("连携") \
				or s.contains("处刑") or s.contains("磨砺") or s.contains("术式") or s.contains("圣辉") \
				or s.contains("二重") or s.contains("爆发连携"):
			parts.append(s)
	if parts.is_empty():
		return ""
	return "✦ " + " / ".join(parts)

# N-04：牌谱横幅串行显示——按入队顺序逐条展示，每条之间留短间隔，避免单例横幅互相覆盖。
# 普通 SPIN（banners 为空）不进入此函数，零额外等待。
func _present_banners(tree: SceneTree, banners: Array) -> void:
	for i in banners.size():
		var b: Dictionary = banners[i]
		_ctrl.hud.show_pattern_banner_seq(String(b.get("text", "")), b.get("color", Palette.POP_DAMAGE), i)
		if i < banners.size() - 1:
			await _present_wait(tree, PATTERN_BANNER_HOLD)


func _present_turn(acc: Dictionary, counts: Dictionary) -> void:
	var tree: SceneTree = _ctrl.get_tree()

	# 2026-11-23：逐格间隔统一 0.42s（用户拍板——多符号回合也回到原始节奏，不再动态拉长）。
	const PRESENT_STEP := CELL_PRESENT_STEP

	# ⓪ 牌型横幅结算时已入队；按「合并表现」口径推迟到 ④，与挥砍、伤害数字同帧出现，
	# 让牌型身份读作「这一次攻击的名号」，而不是先弹横幅、再单独来一次攻击。
	var banners: Array = acc.get("pending_banners", [])

	# ① 护符（玩家侧）先闪 → 报它的分量（守备/回春涓流不由任何格子提供，必须早于读格）
	if not _pending_defense_charms.is_empty():
		_ctrl.hud.pulse_charm_card(_pending_defense_charms)
		await _present_wait(tree, CHARM_FLASH_HOLD)
		var cs: int = int(acc.get("charm_shield", 0))
		var ch: int = int(acc.get("charm_heal", 0))
		if cs > 0:
			_ctrl.hud._popup("🛡+%d" % cs, Palette.POP_SHIELD, _ctrl.hud._player_sprite_anchor())
		if ch > 0:
			_ctrl.hud._popup("❤+%d" % ch, Palette.POP_HEAL, _ctrl.hud._player_sprite_anchor())
		if cs > 0 or ch > 0:
			_ctrl.hud._refresh_meta()
			await _present_wait(tree, POPUP_BEAT)

	# ② 读格：左 → 右，逐个亮起并出数；攻击格跳过（留给 ④）
	var attack_reels: Array = []
	var trash_reels: Array = []   # MISS/废铁：收集起来，等其它格子都闪完后单独错时闪（见 ④b）
	for reel in DuelController.REELS:
		if not _cell_is_player_gain(reel):
			# 2026-11-23：MISS/废铁(trash)是负面结果，不与攻击/增益同时闪。
			# 此处只收集，不立即闪——真正的闪烁放在 ④b，错开时间避免视觉重叠。
			if _cell_kind(reel) == "trash":
				trash_reels.append(reel)
			else:
				attack_reels.append(reel)
			continue
		_ctrl.hud.sweep_light_cell(reel)
		if _cell_is_gold(reel):
			_ctrl.reel_system.play_coin_sfx()   # 金币图标闪烁：RPG Audio handleCoins
		elif _cell_kind(reel) != "heal":
			# 2026-11-23：heal 格闪时不播音——治愈音只在血条真增长时播（见下方）。
			_ctrl.reel_system.play_symbol_sfx(_cell_kind(reel))
		var g := _gain_text_of_reel(reel, acc)
		if not g.is_empty():
			_ctrl.hud._popup(String(g["text"]), g["color"], _ctrl.hud._player_sprite_anchor())
			_ctrl.hud._refresh_meta()   # 血条在这一帧增长
		# 2026-11-23：heal 格演出时总是播治愈音——满血摇到治疗格也要有反馈，
		# 否则"像没发生作用"。血条释放仍只在真涨时(内部无锁会跳过)，音画各自正确。
		var is_heal: bool = _cell_kind(reel) == "heal"
		if is_heal:
			_ctrl.hud.release_heal_display()   # 血条真涨才有效，满血无锁直接跳过
			_ctrl.reel_system.play_heal_sfx()
		# 治愈音(1.0s)比逐格间隔长，播完再进下一格，避免与上一段治愈音重叠。
		var step: float = maxf(PRESENT_STEP, HEAL_SFX_HOLD) if is_heal else PRESENT_STEP
		await _present_wait(tree, step)

	# ②b 无格子归属的玩家侧飘字（增益授予）——放在读格之后，避免抢在转轮前面
	for pp in acc["pending_player_pops"]:
		_ctrl.hud._popup(String(pp["text"]), pp["color"], _ctrl.hud._player_sprite_anchor())
	if not (acc["pending_player_pops"] as Array).is_empty():
		_ctrl.hud._refresh_meta()
		await _present_wait(tree, POPUP_BEAT)

	# ③ 护符（伤害侧）
	if not _pending_damage_charms.is_empty():
		_ctrl.hud.pulse_charm_card(_pending_damage_charms)
		await _present_wait(tree, CHARM_FLASH_HOLD)

	# ④ N-04 牌谱提示时序（只在牌谱实际触发时增加短停顿，普通 SPIN 零额外等待）：
	#    最后一列停稳（turn_flow 已 await spin_finished）
	#      → 牌谱名称短提示（横幅，逐条串行不覆盖）
	#      → 符号与牌谱追加贡献
	#      → 总伤害
	var total: int = int(acc.get("total_damage", 0))
	var has_banners: bool = not banners.is_empty()
	if not attack_reels.is_empty():
		_ctrl.hud.sweep_light_cells_together(attack_reels)
		# 齐亮音效只在真攻击（damage/special）时播一次，代表本批攻击（避免同帧叠音）。
		# status（燃烧/中毒）虽在 attack_reels 里一起亮，但不算真攻击，不发音。
		var has_real_attack: bool = false
		for rr in attack_reels:
			var kk := _cell_kind(int(rr))
			if kk == "damage" or kk == "special":
				has_real_attack = true
				break
		if has_real_attack:
			_ctrl.reel_system.play_symbol_sfx("damage")
		await _present_wait(tree, ATTACK_FLASH_HOLD)
	# ④a MISS/废铁(trash)错时单独闪：等收益格逐格闪完、攻击格齐亮淡出后才闪，
	# 时间上与其它格子完全分离，避免看起来"跟攻击/增益一起亮"。无音效。
	if not trash_reels.is_empty():
		await _present_wait(tree, POPUP_BEAT)
		for rr in trash_reels:
			_ctrl.hud.sweep_light_cell(int(rr))
	# —— 牌谱名称短提示（先看清牌型）——
	if has_banners:
		await _present_banners(tree, banners)
		await _present_wait(tree, PATTERN_BANNER_HOLD)
	# —— 符号与牌谱追加贡献（把「大数字从哪来」先讲清楚）——
	if has_banners:
		var contrib: String = _pattern_contrib_text(acc)
		if contrib != "":
			_ctrl.hud._popup(contrib, Palette.POP_BUFF, _ctrl.hud._enemy_sprite_anchor())
			await _present_wait(tree, PATTERN_CONTRIB_HOLD)
	# —— 总伤害（最后才看到大数字）——
	if total > 0:
		if _ctrl.hud.animator != null:
			# 仅玩家武器攻击播斩击粒子；敌人掉血闸口的 play_enemy_attack 不播（with_slash 默认 false）
			_ctrl.hud.animator.play_attack("player", "enemy", true)
		# N-03：命中帧一到才把敌人幽灵值切成真实值 + 弹分项飘字（护甲/HP/穿透）。
		_ctrl.hud.release_enemy_preview()
		# T4：命中帧后按账本顺序逐段回放（只读事件，不改结算值）。只 drain 一次，
		# 事件数 0 段（纯破甲/空转）补总伤害大数字；>=2 段已有逐段飘字；恰好 1 段回放已弹过，不叠第二条。
		var dmg_events: Array = _ctrl.damage_ledger.drain()
		await _ctrl.hud.play_damage_events(dmg_events, _ctrl.enemy_hp_max, _ctrl.presentation_skip)
		if _should_show_total_popup(dmg_events.size()):
			_ctrl.hud._popup("-%d%s" % [total, String(acc.get("elem_tag", ""))], Palette.POP_DAMAGE, _ctrl.hud._enemy_sprite_anchor())
		_ctrl.hud._refresh_meta()
		await _present_wait(tree, PRESENT_STEP)
	elif has_banners:
		# 纯增益/防御牌谱（本回合无攻击伤害）：横幅 + 贡献已播，留一个短收尾
		await _present_wait(tree, POPUP_BEAT)
	# ④b 敌人侧后续飘字（元素爆发 / 克制核爆）——跟在总伤害之后
	for ep in acc["pending_enemy_pops"]:
		_ctrl.hud._popup(String(ep["text"]), ep["color"], _ctrl.hud._enemy_sprite_anchor())
	if not (acc["pending_enemy_pops"] as Array).is_empty():
		await _present_wait(tree, POPUP_BEAT)
	if not (acc["status_stacks"] as Dictionary).is_empty():
		_ctrl.hud._popup(_ctrl.status_system.status_summary(acc["status_stacks"]), Palette.POP_STATUS, _ctrl.hud._enemy_sprite_anchor())

	# N-03 兜底：若本回合有破甲但无伤害（total=0，上面 total>0 分支未释放），
	# 或纯增益/空转导致幽灵值残留，统一在此释放，保证任何路径都不跨帧残留幽灵值。
	_ctrl.hud.release_enemy_preview()
	# T4 兜底：破甲无伤害 / 空转路径也要把账本取空，避免残留到下个表现阶段。
	await _ctrl.hud.play_damage_events(_ctrl.damage_ledger.drain(), _ctrl.enemy_hp_max, _ctrl.presentation_skip)
	# 治疗锁兜底：本回合治疗若全来自 regen/护符（无 heal 符号格），锁不会在逐格演出中释放，
	# 在此统一释放，保证血条不跨回合残留旧值。
	_ctrl.hud.release_heal_display()
	# ⑤ 收尾：底部短反馈 → 留出阅读时间
	_ctrl.hud._show_turn_feedback(counts, total, bool(acc.get("triple", false)), _ctrl._elem_triple,
		int(acc.get("shield_gain", 0)), int(acc.get("heal_gain", 0)), int(acc.get("heal_overflow_shield", 0)),
		_turn_armor_cleared, _turn_counter_burst, _turn_charge_burst)
	await _present_wait(tree, TURN_TAIL_HOLD)



# ---------------------------------------------------------------------------
# 属性聚合层 (F-0) — 所有「修正轴」的统一查询入口
# ---------------------------------------------------------------------------
# 本层把「加法标量 / 乘法标量 / 符号权重」三类轴统一成一组 agg_* 查询，
# 调用方只认聚合层、不认具体来源。新增修正轴只需在对应 agg_* 末尾加一行求和。
# 注意：本层只聚合「每符号 / 每回合」类修正；房开局护盾等「房间级」修正仍在原位处理。
# P0：以下结算聚合已抽到 BattleMath（参数化纯函数），此处仅剩薄包装。
# ---------------------------------------------------------------------------

func agg_power_flat() -> float:
	var charm_pb: int = _ctrl.charm_power_bonus if _ctrl.deprived_level < 1 else 0   # 无名虚空：护符剥夺
	return BattleMath.agg_power_flat(_ctrl._reward_system.run_power_bonus, charm_pb, _ctrl.player_buffs)

func agg_shield() -> float:
	var charm_st: int = _ctrl.charm_shield_trickle if _ctrl.deprived_level < 1 else 0   # 无名虚空：护符剥夺
	return BattleMath.agg_shield(_ctrl.player_buffs, charm_st)

func agg_regen() -> float:
	var charm_ht: int = _ctrl.charm_heal_trickle if _ctrl.deprived_level < 1 else 0   # 无名虚空：护符剥夺
	return BattleMath.agg_regen(_ctrl.player_buffs, charm_ht)

func agg_damage_mult() -> float:
	var charm_dm: float = _ctrl.charm_damage_mult if _ctrl.deprived_level < 1 else 1.0   # 无名虚空：护符乘区剥离
	return BattleMath.agg_damage_mult(charm_dm, _ctrl.player_buffs)

# —— 符号权重轴（本局符号灌注；武器级权重见 _build_pool）——
func agg_symbol_weight_mod(sym: SymbolData) -> float:
	return BattleMath.agg_symbol_weight_mod(_ctrl._reward_system.run_symbol_bonus, sym)


# ---------------------------------------------------------------------------
# Phase C 主动增益：符号自描述（sym.buff_effect / buff_value / buff_turns），零查表
# player_buffs: SymbolData -> 剩余回合数
# ---------------------------------------------------------------------------
func grant_buff(sym: SymbolData, mult: int, acc: Dictionary = {}) -> void:
	var add = max(1, sym.buff_turns) * mult
	_ctrl.player_buffs[sym] = int(_ctrl.player_buffs.get(sym, 0)) + add
	# 入队，由 _present_turn 在读格之后统一发出（避免早于转轮读格）
	if not acc.is_empty():
		acc["pending_player_pops"].append({"text": "%s+%d" % [sym.label, add], "color": Palette.POP_BUFF})
	else:
		_ctrl.hud._popup("%s+%d" % [sym.label, add], Palette.POP_BUFF, _ctrl.hud._player_sprite_anchor())
	_ctrl.hud._log("技能：%s %s（剩余 %d 回合）" % [sym.label, sym.name, _ctrl.player_buffs[sym]])


# 乘法型增益（多个同时生效则连乘）
func buff_damage_mult() -> float:
	return BattleMath.buff_damage_mult(_ctrl.player_buffs)


# T30：按当前 frost 层数随机挑选冻结列（spin 前冰封，每轮重选，frost 持续期间不可瞄准）。
# 不封废铁：跳过当前显示为 trash 的列（冻结废铁格 = 浪费），全为废铁时回落随机。
# 2026-08-09 单侧性纪律：玩家侧冻结状态 = frozen StatusDef（frost 已回归纯敌人侧减攻）。
func pick_frozen_cols() -> Array[int]:
	var n: int = mini(_ctrl.player_frost, int(_ctrl.status_system.status_def("frozen").max_cols))
	if n <= 0:
		return []
	var candidates: Array[int] = []
	for r in DuelController.REELS:
		var sym: SymbolData = _ctrl.grid[r][0] if _ctrl.grid.size() > r and _ctrl.grid[r].size() > 0 else null
		if sym != null and sym.kind != "trash":   # 冻结不封废铁/MISS
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


# P2：玩家侧 DoT 飘字按来源标签取元素色（与敌人侧 StatusDef.element 上色口径一致）。
# 反弹无对应元素，保留状态橙；未识别的 DoT 标签退回状态橙，避免误上成攻击红。
func _dot_pop_color(tag: String) -> Color:
	if tag.contains("灼烧") or tag.contains("🔥"):
		return ElementCounter.color("fire")
	if tag.contains("毒") or tag.contains("酸蚀") or tag.contains("悲伤") or tag.contains("☣"):
		return ElementCounter.color("poison")
	return Palette.POP_STATUS


# 敌人攻击玩家（debuff 减益由元素驱动：frost/poison = 敌人减攻）。本函数是对玩家伤害的唯一闸口。
# reason: attack = 敌人真实出手（播前冲+红闪+屏震）；dot / reflect = 持续伤害或反弹，
# 只走同一结算闸口（护盾/飘字/日志/反弹），不播攻击演出——否则玩家掉血就误读成「敌人又打了一次」。
# src_tag: 来源标签（如 "☣ 中毒" / "🔥 灼烧"），由调用方传入，用于 DoT/反弹飘字与日志的具体分类；留空则用 reason 默认文案。
func enemy_deal_damage(raw: int, reason: String = "attack", src_tag: String = "") -> void:
	var atk_down = 1.0 - min(0.5, _ctrl.enemy_status.get("frost", 0) * 0.2 + _ctrl.enemy_status.get("poison", 0) * 0.2)
	# 2026-11-12 Step 1：易伤在敌人→玩家唯一伤害闸口折算（+25%）。
	var taken_mult: float = _ctrl.debuffs.taken_mult() if _ctrl.debuffs != null else 1.0
	var pattern_mult: float = float(_ctrl._pattern_enemy_atk_mult)
	var eff = int(round(float(raw) * atk_down * _ctrl.boss_atk_mult * taken_mult * pattern_mult))
	if pattern_mult < 1.0:
		_ctrl.hud._log("❄ 霜封：敌人攻击 ×%s" % ElementCounter.fmt_mult(pattern_mult))
	if taken_mult != 1.0:
		_ctrl.hud._log("🩸 易伤：承伤 ×%s" % ElementCounter.fmt_mult(taken_mult))
	if _ctrl.boss_atk_mult != 1.0:
		_ctrl.hud._log("🔒 呓语强化：敌人攻击 ×%s" % ElementCounter.fmt_mult(_ctrl.boss_atk_mult))
	if atk_down < 1.0:
		_ctrl.hud._log("敌人被削弱：攻击×%s" % ElementCounter.fmt_mult(atk_down))
	var blocked = min(_ctrl.player_shield, eff)
	_ctrl.player_shield -= blocked
	var dealt = max(0, eff - blocked)
	var hp_before_hit := int(_ctrl.player_hp)   # P0：扣血前 HP，供 HUD 显示影子值（不反推，避免乘区误差）
	_ctrl.player_hp -= dealt
	# N-03：闸口分解值顺带记入只读账本（eff=原始攻击/blocked=盾挡/dealt=HP损失）。
	# 只记 reason=="attack"——DoT/反弹是即时伤害、无「攻击前预览」，不入账避免污染。
	# 多段攻击（主攻击+追加）均走 attack，由 add_player_segment 聚合，hp_before 只在第一段记录。
	if reason == "attack" and _ctrl.damage_preview != null:
		_ctrl.damage_preview.add_player_segment(hp_before_hit, eff, blocked, dealt)
	if _ctrl._telemetry != null:
		_ctrl._telemetry.on_player_hit(eff, blocked, dealt)   # M1-06：意图出手/承伤/格挡
	if dealt > 0:
		# 2026-11-16 P0：敌人真实出手时，数值同步结算，但掉血表现（血条/飘字/屏震）
		# 延后到命中帧才释放——先看到前摇动作，命中瞬间才掉血，消除「突然掉血」。
		# 冰系用 T_HIT 对齐喷气命中帧，其余用前摇末 ACT_WINDUP。
		if reason == "attack":
			if _ctrl.hud.animator != null:
				_ctrl.hud.animator.play_enemy_attack()   # t=0 前摇动作（前冲+玩家红闪）
			_ctrl.hud.hold_enemy_hit(dealt, String(_ctrl.enemy_element), hp_before_hit)   # 命中帧才掉血+飘字+屏震
		else:
			# P0/P1/P2：DoT/反弹用元素色 + 来源标签 + 慢速档，与敌人攻击红字快弹分离（不播攻击动作，避免误读「敌人又打一次」）
			var tag: String = src_tag if src_tag != "" else ("↩ 反弹" if reason == "reflect" else "☣ 持续")
			_ctrl.hud._popup("%s -%d" % [tag, dealt], _dot_pop_color(tag), _ctrl.hud._player_sprite_anchor(), true)
	# P1：日志按来源分类——原来所有 reason 都写「敌人攻击」，DoT/反弹也被误记成敌人出手
	var log_tag: String = src_tag if src_tag != "" else ("敌人攻击" if reason == "attack" else ("↩ 反弹" if reason == "reflect" else "☣ 状态侵蚀"))
	_ctrl.hud._log("%s %d（盾挡 %d，受 %d）" % [log_tag, eff, blocked, dealt])
	# 石屑之心（信物）：反弹 thorns×原始攻击 给敌人（穿透护甲直击 HP；被剥夺时失效）
	var thorns: float = _ctrl.charm_thorns if _ctrl.deprived_level < 1 else 0.0
	if thorns > 0.0 and dealt > 0:
		var thorns_dmg := int(round(float(eff) * thorns))
		if thorns_dmg > 0:
			apply_enemy_damage(thorns_dmg, true)
			_ctrl.hud._log("🪨 石屑反弹：%d 伤害" % thorns_dmg)


# 对敌人造成伤害（先破甲后掉血）：非穿透先扣护甲、溢出进 HP；穿透直接扣 HP。返回实际造成的总值。
# N-03：在本唯一变更点顺带记分解值（只读账本），UI/测试不再重算——这是「预览 = 结算」的保证。
func apply_enemy_damage(amount: float, pierce: bool) -> float:
	var dmg = max(0, int(round(amount)))
	if dmg <= 0:
		return 0.0
	if pierce:
		var hp_before: int = int(_ctrl.enemy_hp)
		_ctrl.enemy_hp -= dmg
		# T4：穿透段——before 为加之前真实 HP，after 为扣除后真实 HP（账本不重算）。
		_ctrl.damage_ledger.record("pierce", dmg, hp_before, int(_ctrl.enemy_hp), "", "none", "apply_enemy_damage")
		_turn_enemy_pierce_damage += dmg   # 穿透伤害（直击 HP，不吃护甲）
		_turn_enemy_hp_direct += dmg
		return float(dmg)
	var to_armor = min(_ctrl.enemy_armor, float(dmg))
	_ctrl.enemy_armor -= to_armor
	_turn_enemy_armor_consumed += int(to_armor)   # 非穿透伤害真正吃掉的护甲
	var to_hp = dmg - to_armor
	var hp_before: int = int(_ctrl.enemy_hp)
	_ctrl.enemy_hp -= to_hp
	# T4：破甲后真正进 HP 的部分才记账（amount=to_hp，不是总伤害），保证飘字与血条一致。
	if to_hp > 0:
		_ctrl.damage_ledger.record("hit", int(to_hp), hp_before, int(_ctrl.enemy_hp), "", "none", "apply_enemy_damage")
	_turn_enemy_hp_direct += int(to_hp)
	return float(dmg)


# 反制即爆发（Plan C）：
# · "special" = 通用破甲：清空敌人护甲，开启「伤害直击 HP」的爆发窗口（所有敌人通用破绽）。
# · "element" = 进阶核爆：同族符号的克制连线，除破甲外再追加一次直接打血（穿透）的核爆伤害。
func on_counter(kind: String, pierce_need: int = 3, acc: Dictionary = {}) -> void:
	if _ctrl.enemy_armor > 0:
		var cleared := int(_ctrl.enemy_armor)
		_turn_armor_cleared += cleared   # Step 4：结果反馈报真实破甲量
		var tag := "special %s破甲" % ("三连" if pierce_need >= 3 else "二连")
		_ctrl.hud._log("💥 %s！护甲清零（%d）" % [tag if kind == "special" else "克制同族连线", cleared])
		_ctrl.enemy_armor = 0
		if not acc.is_empty():
			acc["armor_broken"] = true   # G4-3：供回路"破甲余波"事件监听（原始事件，非回路追加）
		if _ctrl._career != null:
			_ctrl._career.note_armor_break()   # G6-01：仅记录 BOSS 房破甲（不改结算）
		_ctrl.notify_armor_break()   # 2026-11-12 Step 1：腐蚀解除 + gimmick「首次破甲」触发
	if kind == "element":
		var burst = int(_ctrl.enemy_hp_max * DuelController.BALANCE.counter_burst_pct)
		if burst > 0:
			_turn_counter_burst += burst   # Step 4：核爆与连线伤害分开报
			apply_enemy_damage(burst, true)
			if _ctrl._telemetry != null:
				_ctrl._telemetry.on_counter_burst(burst)
			if not acc.is_empty():
				acc["pending_enemy_pops"].append({"text": "💥克制核爆!-%d" % burst, "color": Palette.POP_DAMAGE})
			else:
				_ctrl.hud._popup("💥克制核爆!-%d" % burst, Palette.POP_DAMAGE, _ctrl.hud._enemy_sprite_anchor())
			_ctrl.hud._log("⚡ 克制同族连线触发核爆：%d 伤害（穿透护甲）" % burst)
	if _ctrl.hud.animator != null:
		_ctrl.hud.animator.play_counter(kind)


# 敌人 DoT 状态结算（灼烧/毒/霜冻…，含元素克制与状态护符乘区；衰减由 StatusDef.decay 定义）
# 2026-11-16 DoT 相位：结算时先把「本回合新挂、尚未到期」的 pending 层从 enemy_status 摘出，
# 只用可结算层算伤害与衰减，结算后再放回。这样结算中/敌人回合挂的层从下一回合起才跳伤害，
# 与玩家 debuff 的 turn_resolved 规则对称；而减攻/牌谱即时结算/HUD 全程读的是完整 enemy_status。
func tick_status() -> int:
	var restored: Dictionary = {}   # st -> 摘出的 pending 层数（结算后放回）
	for st in _ctrl.enemy_status_pending.keys():
		var hold: int = int(_ctrl.enemy_status_pending[st])
		if hold > 0 and _ctrl.enemy_status.has(st):
			var cur: int = int(_ctrl.enemy_status[st])
			var taken: int = mini(hold, cur)
			restored[st] = taken
			_ctrl.enemy_status[st] = cur - taken
			if _ctrl.enemy_status[st] <= 0:
				_ctrl.enemy_status.erase(st)
	var dot = 0
	# P0：按状态类型分别记标签+伤害，供分类飘字；总扣血仍是各行之和，数值口径完全不变。
	var dot_pops: Array = []
	for st in _ctrl.enemy_status.keys():
		var base = _ctrl.status_system.status_base(st)
		var mult = ElementCounter.multiplier(_ctrl.status_system.status_element(st), _ctrl.enemy_element)
		# T2 状态护符：DoT 伤害乘倍率（状态叠加轴投资；无名虚空剥夺时 ×1.0）；T23：衰减率由 StatusDef.decay 定义
		# 2026-09-29：原全局 status_dmg_mult=3.0 已等值折入 StatusDef.base（burn 12 / poison 9），base 即实跳伤害
		var status_boost: float = _ctrl.charm_status_boost if _ctrl.deprived_level < 1 else 1.0
		var sd: StatusDef = _ctrl.status_system.status_def(st)
		var stacks: int = int(_ctrl.enemy_status[st])
		var one: int = int(round(stacks * base * mult * status_boost))
		dot += one
		var tag: String = ("%s %s" % [sd.icon, sd.name]) if sd != null else "☣ 状态"
		var elem: String = sd.element if sd != null else "none"
		if one > 0:
			dot_pops.append([tag, one, elem])
		# L3 §6.2：层数阈值爆发——伤害型状态(base>0)叠到阈值时一次性爆发并消耗层数。
		# 只对 DoT 生效（frost base=0 是减攻控制，不参与）。爆发吃同一克制倍率，独立于本回合普通 tick。
		# L3 §6.3 遗物联动：毒腺囊(dot_amp)每层降阈值1（下限4，更快爆发）；锋锐/霜核(damage_bonus)
		# 给爆发加 flat（power_bonus×2）；虚空回响(status_boost)已乘进爆发公式，天然强化。
		var effective_threshold: int = maxi(4, int(DuelController.BALANCE.dot_burst_threshold) - int(_ctrl.charm_dot_amp))
		if base > 0.0 and stacks >= effective_threshold:
			var burst_flat: int = int(_ctrl.charm_power_bonus) * 2 if _ctrl.deprived_level < 1 else 0
			var burst: int = int(round(stacks * base * mult * status_boost * DuelController.BALANCE.dot_burst_mult)) + burst_flat
			dot += burst
			dot_pops.append([("💥 %s 爆发" % (sd.name if sd != null else st)), burst, elem])
			_ctrl.hud._log("💥 %s 爆发！%d 层 → %d 伤害" % [sd.name if sd != null else st, stacks, burst])
			stacks = max(0, stacks - int(DuelController.BALANCE.dot_burst_consume))
		# 衰减（爆发消耗已计入 stacks）
		stacks = max(0, stacks - (sd.decay if sd != null else 1))
		_ctrl.enemy_status[st] = stacks
		if stacks <= 0:
			_ctrl.enemy_status.erase(st)
	# 放回未到期层：它们本回合不跳伤害、不衰减，从下一回合起进入结算
	for st in restored.keys():
		_ctrl.enemy_status[st] = int(_ctrl.enemy_status.get(st, 0)) + int(restored[st])
	if dot > 0:
		# T4：按 dot_pops 顺序逐条扣血并逐条记账（原先一次性 enemy_hp -= dot）。
		# 总数 dot 不变、_career.note_status_damage(dot) 仍用总数；允许中途为负，UI 端 clamp。
		var hp_now: int = int(_ctrl.enemy_hp)
		for pop in dot_pops:
			var one: int = int(pop[1])
			if one <= 0:
				continue
			var pop_tag: String = String(pop[0])
			var pop_elem: String = String(pop[2])
			var before: int = hp_now
			hp_now -= one
			_ctrl.enemy_hp = hp_now
			var kind: String = "dot_burst" if pop_tag.contains("爆发") else "dot"
			_ctrl.damage_ledger.record(kind, one, before, hp_now, pop_tag, pop_elem, "tick_status")
		if _ctrl._career != null:
			_ctrl._career.note_status_damage(dot)   # G6-01：仅记录 BOSS 房状态伤害（不改结算）
		# T4 表现去重：DoT 标签/元素已随事件进账本，飘字统一由 play_damage_events 按 tag 弹出，
		# 这里不再 _popup，避免同一段被弹两次。
		_ctrl.hud._log("状态结算 %d 伤害（灼烧/毒·含克制）" % dot)
	return dot


# T21 元素充能爆发（覆盖流赛道）：克制命中满 charge_max 次后自动释放——
# 清甲 + 穿透核爆（无视护甲直击 HP），与三连破甲/核爆互补（分散积累 vs 单次高概率）。
# 2026-08-14 主导元素：按本回合克制命中最多的元素，追加一次元素附伤（吃克制 ×1.5/×0.85）——
# 「元素身份感」回归（爆发记住你主要用哪个元素），池子不拆、HUD 不变、混合构筑不惩罚。
func release_element_burst(acc: Dictionary = {}) -> void:
	var burst := int(_ctrl.enemy_hp_max * DuelController.BALANCE.charge_burst_pct)
	if _ctrl.enemy_armor > 0:
		_turn_armor_cleared += int(_ctrl.enemy_armor)   # Step 4：结果反馈报真实破甲量
		_ctrl.enemy_armor = 0
		_ctrl.hud._log("⚡ 元素充能爆发：护甲清零！")
		_ctrl.notify_armor_break()   # 2026-11-12 Step 1：破甲路径统一（腐蚀解除 / 首次破甲触发）
	if burst > 0:
		_turn_charge_burst += burst   # Step 4：充能爆发与连线伤害分开报
		apply_enemy_damage(burst, true)
		acc["pending_enemy_pops"].append({"text": "⚡元素爆发!-%d" % burst, "color": Palette.POP_DAMAGE})
		_ctrl.hud._log("⚡ 元素充能爆发：%d 穿透伤害（直击 HP，无视护甲）" % burst)
	var lead := ""
	var lead_max := 0
	for e in _ctrl._charge_elem_counts:
		if int(_ctrl._charge_elem_counts[e]) > lead_max:
			lead_max = int(_ctrl._charge_elem_counts[e])
			lead = e
	if lead != "" and lead != "none":
		var em: float = ElementCounter.multiplier(lead, _ctrl.enemy_element)
		var extra := int(round(float(DuelController.BALANCE.charge_extra_base) * em))
		if extra > 0:
			_turn_charge_burst += extra
			apply_enemy_damage(float(extra), false)
			acc["pending_enemy_pops"].append({"text": "%s爆发!-%d" % [ElementCounter.label(lead), extra], "color": ElementCounter.color(lead)})
			_ctrl.hud._log("⚡ %s系爆发附伤：%d（×%s）" % [ElementCounter.label(lead), extra, ElementCounter.fmt_mult(em)])
	if _ctrl.hud.animator != null:
		_ctrl.hud.animator.play_counter("element")
