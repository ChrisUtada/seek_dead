# GrowthSystem — 角色历练与技艺（M2-01，ACT1 样板）
# 运行时经 duel_controller preload 实例化（不注册全局 class_name——headless 测试环境不刷新类缓存）。
# 职责：房间胜利发放历练经验 → 升级（最大 HP +5 并恢复）→ 在 Lv.2 / Lv.4 各给一次技艺三选一。
# 技艺效果在各自落点读取本系统的查询接口（守势 / 精打细算 / 稳定节奏 / 洞察），
# 只有「坚韧」「备用药剂」两项在获得瞬间结算。整局状态经 reset_run 清零（新一局 / 战败回整备）。
# 规格见 docs/M0-02_样板范围.md §1；ACT1 样板上限 Lv.4 / 2 个技艺，Lv.5+ 归 M5。

var _ctrl  # DuelController

const ROOM_XP := {"normal": 1, "elite": 2, "boss": 3}   # 历练经验：只在房间胜利时发放
const LEVEL_XP := {2: 3, 3: 7, 4: 12}                    # 累计经验门槛
const LEVEL_MAX := 4                                     # ACT1 样板上限
const HP_PER_LEVEL := 5                                  # 每级最大 HP +5 并恢复同量
const PERK_LEVELS := [2, 4]                              # 升到这些等级时获得一次技艺选择
const FAMILIES := {"survive": "生存", "plan": "运筹", "aim": "目押"}
const PERKS := [
	{"id": "tough", "family": "survive", "name": "坚韧", "desc": "最大 HP +10，并立即恢复 10 HP"},
	{"id": "guard", "family": "survive", "name": "守势", "desc": "每房开局获得 8 护盾"},
	{"id": "frugal", "family": "plan", "name": "精打细算", "desc": "每个房间间歇首次商店刷新免费"},
	{"id": "reserve", "family": "plan", "name": "备用药剂", "desc": "获得时，腰带上所有消耗品各 +1 次使用次数"},
	{"id": "steady", "family": "aim", "name": "稳定节奏", "desc": "每房前 2 回合转轮基础间隔 0.15→0.17s，加速曲线不变"},
	{"id": "insight", "family": "aim", "name": "洞察", "desc": "旋转时，每列显示下一格符号"},
]
const STEADY_WAIT := 0.17        # 稳定节奏：每房前 2 回合的基础每跳间隔
const STEADY_TURNS := 2
const GUARD_SHIELD := 8

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


# 房间胜利：累计经验并逐级升级。返回待选技艺次数（>0 时 RoomFlow 先弹三选一再进间歇）。
func grant_room_xp(kind: String) -> int:
	xp += int(ROOM_XP.get(kind, 0))
	while level < LEVEL_MAX and xp >= int(LEVEL_XP[level + 1]):
		level += 1
		_ctrl.player_hp_max += HP_PER_LEVEL
		_ctrl.player_hp = mini(_ctrl.player_hp_max, _ctrl.player_hp + HP_PER_LEVEL)
		_ctrl.hud._log("🎓 历练 Lv.%d：最大 HP +%d 并恢复 %d" % [level, HP_PER_LEVEL, HP_PER_LEVEL])
		if PERK_LEVELS.has(level):
			pending_picks += 1
	return pending_picks


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
	return picks.map(func(p): return {"id": p["id"], "family": FAMILIES[p["family"]], "name": p["name"], "desc": p["desc"]})


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
