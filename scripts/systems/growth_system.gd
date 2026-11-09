# GrowthSystem — 角色历练与技艺（M2-01 建立，G7-A S1 扩至三幕）
# 运行时经 duel_controller preload 实例化（不注册全局 class_name——headless 测试环境不刷新类缓存）。
# 职责：房间胜利发放历练经验 → 升级（最大 HP +5 并恢复）→ 在 Lv.2 / Lv.4 / Lv.6 各给一次技艺三选一。
# 技艺效果在各自落点读取本系统的查询接口（守势 / 精打细算 / 稳定节奏 / 洞察 / 稳手），
# 只有「坚韧」「备用药剂」「回春」「积蓄」在落点即时结算。整局状态经 reset_run 清零（新一局 / 战败回整备）。
# 规格见 docs/M0-02_样板范围.md §1（ACT1 样板：Lv.4 / 2 技艺）；
# 2026-11-08 按 `docs/G7-A_切片拆分与验收清单_2026-11-08.md` S1 拍板扩至 Lv.6 / 3 技艺 / 池 9。

var _ctrl  # DuelController

const ROOM_XP := {"normal": 1, "elite": 2, "boss": 3}   # 历练经验：只在房间胜利时发放
const LEVEL_XP := {2: 3, 3: 7, 4: 12, 5: 20, 6: 30}     # 累计经验门槛（G7-A S1：扩至 Lv.6；
                                                        # 5/6 按三幕 36 经验推算，Lv.5 落在第二幕中段、Lv.6 落在第三幕）
const LEVEL_MAX := 6                                     # G7-A S1：ACT1 样板 4 → 三幕 6
const HP_PER_LEVEL := 5                                  # 每级最大 HP +5 并恢复同量
const PERK_LEVELS := [2, 4, 6]                           # 升到这些等级时获得一次技艺选择（G7-A S1：+Lv.6）
const FAMILIES := {"survive": "生存", "plan": "运筹", "aim": "目押"}
# P0-2（2026-11-03）：给每个家族一句「打法方向」，选择前能预判自己走哪条线。
const FAMILY_HINT := {"survive": "更耐打", "plan": "更多资源", "aim": "更易停中"}
const FAMILY_ORDER := ["survive", "plan", "aim"]
const PERKS := [
	{"id": "tough", "family": "survive", "name": "坚韧", "desc": "最大 HP +10，并立即恢复 10 HP"},
	{"id": "guard", "family": "survive", "name": "守势", "desc": "每房开局获得 8 护盾"},
	{"id": "frugal", "family": "plan", "name": "精打细算", "desc": "每个房间间歇首次商店刷新免费"},
	{"id": "reserve", "family": "plan", "name": "备用药剂", "desc": "获得时，腰带上所有消耗品各 +1 次使用次数"},
	{"id": "steady", "family": "aim", "name": "稳定节奏", "desc": "每房前 2 回合转轮基础间隔 0.15→0.17s，加速曲线不变"},
	{"id": "insight", "family": "aim", "name": "洞察", "desc": "旋转时，每列显示下一格符号"},
	# G7-A S1（2026-11-08 拍板）：每家族 +1，池 6→9，支撑 Lv.6 的第三次选择。
	{"id": "regen", "family": "survive", "name": "回春", "desc": "每次房间胜利恢复 4 HP（BOSS 房 8 HP）"},
	{"id": "hoard", "family": "plan", "name": "积蓄", "desc": "每次房间胜利获得 2 金（BOSS 房 5 金）"},
	{"id": "steady_hand", "family": "aim", "name": "稳手", "desc": "每回合首次按停可多缓冲一拍，等视觉中心到下一格"},
]
# 回春 / 积蓄的数值（只在这里改，测试与文档都引用这两组常量）。
const REGEN_HP := 4
const REGEN_HP_BOSS := 8
const HOARD_GOLD := 2
const HOARD_GOLD_BOSS := 5
const STEADY_WAIT := 0.17        # 稳定节奏：每房前 2 回合的基础每跳间隔
const STEADY_TURNS := 2
const GUARD_SHIELD := 8
# G7-A S5 后续（2026-11-09）：幕间锻魂——进入 ACT II / ACT III 时自动发放一次。
# 只改本局运行时状态（本局符号伤害 + 最大 HP），不改敌人 / ante / 存档；ACT I 不发放。
const ACT_BOON_POWER := 8
const ACT_BOON_HP := 20

var enabled: bool = true         # 探针开关（M2-04 对照组）：false 时房间胜利不发历练
var boon_enabled: bool = true    # 探针开关（S5 复测 A/B）：false 时不发幕间锻魂
var xp: int = 0
var level: int = 1
var perk_ids: Array[String] = []
var pending_picks: int = 0       # 尚未选择的技艺次数


func _init(ctrl) -> void:
	_ctrl = ctrl


# 新一局 / 战败回整备：历练与技艺清零（最大 HP 由 LoadoutSystem.reset_run_state 回基础值）。
func reset_run() -> void:
	xp = 0
	level = 1
	perk_ids.clear()
	pending_picks = 0


func has_perk(id: String) -> bool:
	return perk_ids.has(id)


# 玩家区文案：等级 + 距下一级的历练进度（满级后显示累计）。
func progress_text() -> String:
	if level >= LEVEL_MAX:
		return "Lv.%d · %d（满）" % [level, xp]
	return "Lv.%d · %d/%d" % [level, xp, int(LEVEL_XP[level + 1])]


# 左栏常驻小字：只有历练进度（等级已在玩家标题），满级后显示累计。
func progress_short() -> String:
	if level >= LEVEL_MAX:
		return "%d 满" % xp
	return "%d/%d" % [xp, int(LEVEL_XP[level + 1])]


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


# 房间胜利：累计经验并逐级升级。返回待选技艺次数（>0 时 RoomFlow 先弹三选一再进间歇）。
func grant_room_xp(kind: String) -> int:
	if not enabled:
		return pending_picks
	xp += int(ROOM_XP.get(kind, 0))
	while level < LEVEL_MAX and xp >= int(LEVEL_XP[level + 1]):
		level += 1
		var hp_before: int = _ctrl.player_hp_max
		_ctrl.player_hp_max += HP_PER_LEVEL
		_ctrl.player_hp = mini(_ctrl.player_hp_max, _ctrl.player_hp + HP_PER_LEVEL)
		# P0-2：升级必须有可见结果（前 → 后数值 + 飘字），否则只有日志里的 +5 无法形成变强感。
		_ctrl.hud._log("🎓 历练 Lv.%d：最大 HP %d → %d（立即恢复 %d）" % [level, hp_before, _ctrl.player_hp_max, HP_PER_LEVEL])
		_ctrl.hud._popup("Lv.%d" % level, Palette.ACCENT_GOLD, _ctrl.hud.player_hp_label)
		if PERK_LEVELS.has(level):
			pending_picks += 1
			_ctrl.hud._log("  ◆ 获得 1 次技艺选择")
	return pending_picks


# G7-A S1（2026-11-08 拍板）：房间胜利后的技艺结算（回春 / 积蓄）。
# 与 grant_room_xp 同一处调用（room_flow._settle_victory），只读本局状态；
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
		if healed > 0 and _ctrl.hud != null:
			_ctrl.hud._log("🌿 回春：HP %d/%d → %d/%d（+%d）" % [
				before, _ctrl.player_hp_max, _ctrl.player_hp, _ctrl.player_hp_max, healed])
			_ctrl.hud._popup("❤+%d" % healed, Palette.POP_HEAL, _ctrl.hud._player_sprite_anchor())
		_ctrl.invalidate_state()
	if has_perk("hoard"):
		var gold: int = HOARD_GOLD_BOSS if is_boss else HOARD_GOLD
		_ctrl.gold += gold
		if _ctrl.hud != null:
			_ctrl.hud._log("📦 积蓄：金币 +%d（共 %d）" % [gold, _ctrl.gold])
			_ctrl.hud._popup("💰+%d" % gold, Palette.POP_GOLD, _ctrl.hud._player_sprite_anchor())
			_ctrl.hud._refresh_meta()
		_ctrl.invalidate_state()


# G7-A S5 后续（2026-11-09）：幕间锻魂。advance_act() 在换幕成功后调用一次；
# 仅 act >= 2 生效，因此 ACT I 开局与单幕局（advance_act 永不被调用）行为不变。
# 复用 reward_system.run_power_bonus（与「攻击研磨」同一本局加成层），不新增状态字段。
func grant_act_boon(act: int) -> void:
	if not enabled or not boon_enabled or act < 2:
		return
	var hp_before: int = _ctrl.player_hp
	var hp_max_before: int = _ctrl.player_hp_max
	var power_before: int = int(_ctrl._reward_system.run_power_bonus)
	_ctrl._reward_system.run_power_bonus += ACT_BOON_POWER
	_ctrl.player_hp_max += ACT_BOON_HP
	_ctrl.player_hp = mini(_ctrl.player_hp_max, hp_before + ACT_BOON_HP)
	var healed: int = _ctrl.player_hp - hp_before
	if _ctrl.hud != null:
		_ctrl.hud._log("◆ 幕间锻魂：本局符号伤害 +%d（%d → %d） · 最大 HP %d → %d（HP +%d）" % [
			ACT_BOON_POWER, power_before, _ctrl._reward_system.run_power_bonus,
			hp_max_before, _ctrl.player_hp_max, healed])
		_ctrl.hud._popup("锻魂 +%d" % ACT_BOON_POWER, Palette.ACCENT_GOLD, _ctrl.hud.player_hp_label)
	if _ctrl._journal != null:
		_ctrl._journal.note_act_boon(act, ACT_BOON_POWER, ACT_BOON_HP)
	_ctrl.invalidate_state()


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
		"frugal":
			var free_now: int = _ctrl._shop_system.free_reroll_count()
			desc += "（每房间歇免费刷新 %d → %d 次）" % [free_now, free_now + 1]
		"reserve":
			var charges_now := 0
			for slot in _ctrl.consumable_slots:
				charges_now += int(slot["charges"])
			var slot_n: int = _ctrl.consumable_slots.size()
			desc += "（腰带 %d 格合计次数 %d → %d）" % [slot_n, charges_now, charges_now + slot_n]
		"steady":
			desc += "（前 2 回合间隔 0.15 → 0.17s）"
		"insight":
			desc += "（提前 1 格可见）"
		"regen":
			desc += "（房胜利 HP +%d → BOSS 房 +%d）" % [REGEN_HP, REGEN_HP_BOSS]
		"hoard":
			desc += "（房胜利 金 +%d → BOSS 房 +%d）" % [HOARD_GOLD, HOARD_GOLD_BOSS]
		"steady_hand":
			desc += "（每回合 1 次，提前 1 拍锁定）"
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


# 选定技艺：扣减待选次数，瞬时效果在此结算。非法选择返回 false。
func pick(id: String) -> bool:
	if pending_picks <= 0 or perk_ids.has(id) or perk_name(id) == "":
		return false
	perk_ids.append(id)
	pending_picks -= 1
	match id:
		"tough":
			_ctrl.player_hp_max += 10
			_ctrl.player_hp = mini(_ctrl.player_hp_max, _ctrl.player_hp + 10)
		"reserve":
			for slot in _ctrl.consumable_slots:
				slot["charges"] += 1
	if _ctrl._journal != null:
		_ctrl._journal.note_growth(id, perk_name(id))   # G5 工具：自动记录成长选择
	_ctrl.hud._log("✦ 习得技艺「%s」：%s" % [perk_name(id), perk_desc(id)])
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


# —— 落点查询（守势 / 精打细算 / 稳定节奏 / 洞察）——

# 守势：每房开局护盾（RoomFlow / _start_room 叠加到 player_shield）
func room_shield() -> int:
	return GUARD_SHIELD if has_perk("guard") else 0


# 精打细算：每房间歇免费刷新次数（叠加在护符免费刷新之上）
func free_reroll_bonus() -> int:
	return 1 if has_perk("frugal") else 0


# 稳定节奏：每跳基础间隔。仅前 STEADY_TURNS 回合放慢，之后回落到 base。
func spin_wait_base(base: float) -> float:
	if has_perk("steady") and _ctrl.turn_count <= STEADY_TURNS:
		return maxf(base, STEADY_WAIT)
	return base
