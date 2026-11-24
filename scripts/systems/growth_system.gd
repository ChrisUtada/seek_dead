# GrowthSystem — 角色历练与技艺（M2-01 建立，G7-A S1 扩至三幕）
# 运行时经 duel_controller preload 实例化（不注册全局 class_name——headless 测试环境不刷新类缓存）。
# 职责：技艺三选一（概率注入战后奖励池）+ 幕间锻魂。2026-11-19 移除等级/经验/升级。
# 技艺效果在各自落点读取本系统的查询接口（守势 / 精打细算 / 落点吸附 / 宽判窗口 / 废铁豁免），
# 只有「坚韧」「备用药剂」「回春」「积蓄」在落点即时结算。整局状态经 reset_run 清零（新一局 / 战败回整备）。
# 规格见 docs/移除玩家等级_替代方案_2026-11-19.md（等级已移除，技艺改概率注入三选一）；
# 随机技艺池 8；旧技艺「精打细算」仅作存档兼容，不再进入随机候选。

var _ctrl  # DuelController

const FAMILIES := {"survive": "生存", "plan": "运筹"}
# P0-2（2026-11-03）：给每个家族一句「打法方向」，选择前能预判自己走哪条线。
const FAMILY_HINT := {"survive": "更耐打", "plan": "更多资源", "aim": "更易停中"}
const FAMILY_ORDER := ["survive", "plan", "aim"]
const PERKS := [
	{"id": "tough", "family": "survive", "name": "坚韧", "desc": "最大 HP +10，并立即恢复 10 HP"},
	{"id": "guard", "family": "survive", "name": "守势", "desc": "每房开局获得 8 护盾"},
	{"id": "reserve", "family": "plan", "name": "备用药剂", "desc": "获得时，腰带上所有消耗品各 +1 次使用次数"},
	# G7-A S1（2026-11-08 拍板）：每家族 +1，池 6→9，支撑 Lv.6 的第三次选择。
	{"id": "regen", "family": "survive", "name": "回春", "desc": "每次房间胜利恢复 4 HP（BOSS 房 8 HP）"},
	{"id": "hoard", "family": "plan", "name": "积蓄", "desc": "每次房间胜利获得 2 金（BOSS 房 5 金）"},
	# 2026-11-19 P1.1③：原 3 项目押技艺（snap/wide/mercy）迁出至 reel_control 类别，消除双入口。
	# 补 3 项生存/运筹型，池深保持 8（roll_choices 需 ≥3 未拥有候选，5 项会后期抽干）。
	{"id": "surge", "family": "survive", "name": "蓄能", "desc": "每房开局额外获得 5 点护盾"},
	{"id": "reclaim", "family": "plan", "name": "回收", "desc": "每次房间胜利额外获得 2 金币"},
	{"id": "spare", "family": "plan", "name": "余裕", "desc": "满血时每次房间胜利额外获得 3 金币"},
]
# 回春 / 积蓄的数值（只在这里改，测试与文档都引用这两组常量）。
const REGEN_HP := 4
const REGEN_HP_BOSS := 8
const HOARD_GOLD := 2
const HOARD_GOLD_BOSS := 5
# 操控能力唯一由 reel_control 奖励授予（技艺侧已迁出）。
const MERCY_PER_TURN := 1       # 废铁转化：每回合最多触发次数（废铁→+金）
# 落点吸附已移除（盲目前后N格是干扰、无正面收益）；改为每房1次废铁改判 trash_reroll（在 ReadabilitySystem）
# 宽判窗口已移除，改为缓速操控 slow_ramp（在 ReelSystem._accel() 读 reel_controls）
# 2026-11-19 P1.1③ 新增三项生存/运筹型技艺（补 aim 空位，池深保持 8）。
const SURGE_SHIELD := 5         # 蓄能：每房开局额外护盾
const RECLAIM_GOLD := 2         # 回收：每房胜利额外金币
const SPARE_GOLD := 3           # 余裕：满血时每房胜利额外金币
const GUARD_SHIELD := 8
# 幕间锻魂——进入 ACT II / ACT III 时自动发放一次。
# T1.7 收口：仅保留本局符号伤害 +8（C1 方案）。原 +20 最大 HP 与同步回血已移除——
# 36 种子 A/B 证明：+8 伤害通过缩短击杀时间提供更有效生存余量，额外 HP 属冗余支撑。
# 只改本局运行时状态，不改敌人 / ante / 存档；ACT I 不发放。
const ACT_BOON_POWER := 8

var enabled: bool = true         # 探针开关（M2-04 对照组）：false 时房间胜利不发历练
var perk_ids: Array[String] = []
# S4-1：仅本局有效的幕间锻魂幂等账本。以 act 号为键，同幕重复调用直接返回；
# 不入局外存档，新一局由 reset_run() 清空。Journal 不另建账本，以本集合为唯一守卫。
var granted_acts: Dictionary = {}



func _init(ctrl) -> void:
	_ctrl = ctrl


# 新一局 / 战败回整备：历练与技艺清零（最大 HP 由 LoadoutSystem.reset_run_state 回基础值）。
func reset_run() -> void:
	perk_ids.clear()
	granted_acts.clear()   # S4-1：新一局清空，按新生命周期可重新发放


func has_perk(id: String) -> bool:
	return perk_ids.has(id)


# P0-2：本局技艺的方向摘要（按固定顺序聚合家族），供 HUD tooltip / 成长结算页头展示。
func summary_line() -> String:
	if perk_ids.is_empty():
		return "技艺：无"
	var counts := {}
	for pid in perk_ids:
		var fam := _family_of(pid)
		if fam != "":
			counts[fam] = int(counts.get(fam, 0)) + 1
	var parts: Array[String] = []
	for fid in FAMILY_ORDER:
		var n: int = int(counts.get(fid, 0))
		if n > 0:
			parts.append("%s×%d" % [FAMILIES[fid], n])
	return "技艺 " + "·".join(parts)


# P0-2：完整明细（tooltip 用）：每项技艺带家族与效果。
func detail_text() -> String:
	if perk_ids.is_empty():
		return "技艺：无"
	var lines: Array[String] = ["技艺："]
	for pid in perk_ids:
		lines.append("· %s（%s）%s" % [perk_name(pid), perk_family(pid), perk_desc(pid)])
	return "\n".join(lines)


# G7-A S1（2026-11-08 拍板）：房间胜利后的技艺结算（回春 / 积蓄）。
# 与 reward_system.note_skill_pity_room 同一处调用（room_flow._settle_victory），只读本局状态；
# 不发经验、不改房间数值、不碰掉落与 RNG。
func apply_victory_perks(kind: String) -> void:
	if not enabled:
		return
	var is_boss: bool = kind == "boss"
	if has_perk("regen"):
		var amount: int = REGEN_HP_BOSS if is_boss else REGEN_HP
		var before: int = _ctrl.player_hp
		_ctrl.player_hp = mini(_ctrl.player_hp_max, before + amount)
		var healed: int = _ctrl.player_hp - before
		if _ctrl._telemetry != null:
			_ctrl._telemetry.on_heal(healed, 0, "regen")   # T1.8 分来源观测
		if healed > 0 and _ctrl.hud != null:
			_ctrl.hud._log("🌿 回春：HP %d/%d → %d/%d（+%d）" % [
				before, _ctrl.player_hp_max, _ctrl.player_hp, _ctrl.player_hp_max, healed])
			_ctrl.hud._popup("❤+%d" % healed, Palette.POP_HEAL, _ctrl.hud._player_sprite_anchor())
		_ctrl.invalidate_state()
		# T0-4：真实治疗入口必须主动刷新 HUD（标签/血条），否则 invalidate_state 只失效缓存不重绘。
		# _refresh_meta 内部已含 invalidate_state，并让 _refresh_vitals 按真实 HP 处理影子遮蔽。
		if _ctrl.hud != null:
			_ctrl.hud._refresh_meta()
	if has_perk("hoard"):
		var gold: int = HOARD_GOLD_BOSS if is_boss else HOARD_GOLD
		_ctrl.gold += gold
		if _ctrl.hud != null:
			_ctrl.hud._log("📦 积蓄：金币 +%d（共 %d）" % [gold, _ctrl.gold])
			_ctrl.hud._popup("💰+%d" % gold, Palette.POP_GOLD, _ctrl.hud._player_sprite_anchor())
			_ctrl.hud._refresh_meta()
		_ctrl.invalidate_state()
	# P1.1③：回收（每房+金）/ 余裕（满血时每房+金）
	if has_perk("reclaim"):
		_ctrl.gold += RECLAIM_GOLD
		if _ctrl.hud != null:
			_ctrl.hud._log("♻️ 回收：金币 +%d（共 %d）" % [RECLAIM_GOLD, _ctrl.gold])
		_ctrl.invalidate_state()
	if has_perk("spare") and int(_ctrl.player_hp) >= int(_ctrl.player_hp_max):
		_ctrl.gold += SPARE_GOLD
		if _ctrl.hud != null:
			_ctrl.hud._log("🎒 余裕（满血）：金币 +%d（共 %d）" % [SPARE_GOLD, _ctrl.gold])
		_ctrl.invalidate_state()


# G7-A S5 后续（2026-11-09）：幕间锻魂。线性换幕由 DuelController._maybe_grant_linear_act_boon()
# 在进入下一幕首个房间时调用一次；仅 act >= 2 生效，因此 ACT I 开局与单幕局行为不变。
# 复用 reward_system.run_power_bonus（与「攻击研磨」同一本局加成层），不新增状态字段。
func grant_act_boon(act: int) -> void:
	if not enabled or act < 2:
		return
	# S4-1：同幕幂等守卫——已发过直接返回，不重复加数值、不重复记 Journal。
	if granted_acts.has(act):
		return
	granted_acts[act] = true
	var power_before: int = int(_ctrl._reward_system.run_power_bonus)
	# T1.7 收口：仅 +8 本局符号伤害；不再改最大 HP / 当前 HP。
	_ctrl._reward_system.run_power_bonus += ACT_BOON_POWER
	if _ctrl.hud != null:
		_ctrl.hud._log("◆ 幕间锻魂：本局符号伤害 +%d（%d → %d）" % [
			ACT_BOON_POWER, power_before, _ctrl._reward_system.run_power_bonus])
		_ctrl.hud._popup("锻魂 +%d" % ACT_BOON_POWER, Palette.ACCENT_GOLD, _ctrl.hud.player_hp_label)
	if _ctrl._journal != null:
		_ctrl._journal.note_act_boon(act, ACT_BOON_POWER, 0)   # hp 记 0：C1 后不再发 HP
	_ctrl.invalidate_state()
	# HUD 刷新入口保留（T0-4）：虽不再改 HP，仍主动重绘标签/血条，
	# 确保受击影子期不遮蔽真实 HP——「刷新不得因收口而失效」。
	if _ctrl.hud != null:
		_ctrl.hud._refresh_meta()


# 三选一候选：按家族打乱后各取一个未拥有技艺（候选覆盖不同家族，不出现同义卡）。
# 展示即定完整效果——效果为常量，选择后不再随机。
func roll_choices() -> Array:
	var families: Array = FAMILIES.keys()
	families.shuffle()
	var picks: Array = []
	for fam in families:
		if picks.size() >= 3:
			break
		var cands := _unowned_in(fam)
		if cands.is_empty():
			continue
		cands.shuffle()
		picks.append(cands[0])
	if picks.size() < 3:   # 家族不足时从剩余未拥有技艺补齐
		var rest := _unowned_in("")
		rest.shuffle()
		for p in rest:
			if picks.size() >= 3:
				break
			if not picks.has(p):
				picks.append(p)
	return picks.map(func(p): return _choice_view(p))


# 候选展示口径：描述 + 展示时的当前→升级后数值（确认前预览）。
# P0-2：每张卡都带「方向」与可量化前后值，玩家不必靠猜测判断强弱。
func _choice_view(p: Dictionary) -> Dictionary:
	var desc: String = p["desc"]
	match String(p["id"]):
		"tough":
			var hp: int = _ctrl.player_hp_max
			desc += "（最大 HP %d → %d，立即回 10）" % [hp, hp + 10]
		"guard":
			var shield_now: int = int(_ctrl.charm_room_shield) + int(_ctrl._reward_system.run_shield_next)
			desc += "（每房开局护盾 %d → %d）" % [shield_now, shield_now + GUARD_SHIELD]
		"reserve":
			var charges_now := 0
			for slot in _ctrl.consumable_slots:
				charges_now += int(slot["charges"])
			var slot_n: int = _ctrl.consumable_slots.size()
			desc += "（腰带 %d 格合计次数 %d → %d）" % [slot_n, charges_now, charges_now + slot_n]
		"surge":
			desc += "（每房开局护盾 +%d）" % SURGE_SHIELD
		"reclaim":
			desc += "（每房胜利金币 +%d）" % RECLAIM_GOLD
		"spare":
			desc += "（满血时每房胜利金币 +%d）" % SPARE_GOLD
		"regen":
			desc += "（房胜利 HP +%d → BOSS 房 +%d）" % [REGEN_HP, REGEN_HP_BOSS]
		"hoard":
			desc += "（房胜利 金 +%d → BOSS 房 +%d）" % [HOARD_GOLD, HOARD_GOLD_BOSS]
	return {"id": p["id"], "family": FAMILIES[p["family"]],
		"hint": String(FAMILY_HINT.get(p["family"], "")), "name": p["name"], "desc": desc}


func _family_of(id: String) -> String:
	for p in PERKS:
		if p["id"] == id:
			return String(p["family"])
	return ""


func _unowned_in(family: String) -> Array:
	var out: Array = []
	for p in PERKS:
		if family != "" and p["family"] != family:
			continue
		if perk_ids.has(p["id"]):
			continue
		out.append(p)
	return out


# 战利品直接授予一项未拥有技艺。
func grant_perk(id: String) -> bool:
	if perk_ids.has(id) or perk_name(id) == "":
		return false
	return pick(id)


# 选定技艺：瞬时效果在此结算。非法选择返回 false。
# 2026-11-19：技艺改由三选一常驻/概率注入，选中即授予，不再需要 pending_picks 门控。
func pick(id: String) -> bool:
	if perk_ids.has(id) or perk_name(id) == "":
		return false
	perk_ids.append(id)
	match id:
		"tough":
			var hp_before_tough: int = _ctrl.player_hp
			_ctrl.player_hp_max += 10
			_ctrl.player_hp = mini(_ctrl.player_hp_max, _ctrl.player_hp + 10)
			if _ctrl._telemetry != null:
				_ctrl._telemetry.on_heal(_ctrl.player_hp - hp_before_tough, 0, "regen")   # T1.8 观测
		"reserve":
			for slot in _ctrl.consumable_slots:
				slot["charges"] += 1
	if _ctrl._journal != null:
		_ctrl._journal.note_growth(id, perk_name(id))   # G5 工具：自动记录成长选择
	_ctrl.hud._log("✦ 习得技艺「%s」：%s" % [perk_name(id), perk_desc(id)])
	# T0-4：坚韧改了最大 HP/当前 HP，必须让 BattleState 快照失效并主动重绘 HUD。
	# 只对改 HP 的瞬时技艺刷新，避免影响「备用药剂」等不改血条的技艺路径。
	if id == "tough":
		_ctrl.invalidate_state()
		if _ctrl.hud != null:
			_ctrl.hud._refresh_meta()
	return true


func perk_name(id: String) -> String:
	for p in PERKS:
		if p["id"] == id:
			return p["name"]
	return ""


func perk_desc(id: String) -> String:
	for p in PERKS:
		if p["id"] == id:
			return p["desc"]
	return ""


func perk_family(id: String) -> String:
	for p in PERKS:
		if p["id"] == id:
			return FAMILIES[p["family"]]
	return ""


# —— 落点查询（守势 / 蓄能 / 操控）——

# 守势 + 蓄能：每房开局护盾（RoomFlow / _start_room 叠加到 player_shield）
func room_shield() -> int:
	var shield: int = 0
	if has_perk("guard"):
		shield += GUARD_SHIELD
	if has_perk("surge"):
		shield += SURGE_SHIELD
	return shield


# P1.1③：操控能力唯一由 reel_control 奖励授予（技艺侧已迁出，消除双入口）。
func _has_control(id: String) -> bool:
	return _ctrl != null and _ctrl.reel_controls.has(id)


# 废铁转化：每回合可用次数（0 = 未拥有）
func mercy_per_turn() -> int:
	return MERCY_PER_TURN if _has_control("mercy") else 0
