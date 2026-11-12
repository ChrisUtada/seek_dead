extends RefCounted

# ============================================================================
# Step 1（2026-11-12）· 玩家侧共用 debuff 模块
# 规格：docs/全怪物个性机制设计与制作计划_2026-11-12.md §10 Step 1
#
# 职责：统一「玩家侧负面状态」的施加 / 计时 / 解除 / 数值查询。
# - 怪物侧只调用 ctrl.apply_debuff("weak", 1)，不直接改玩家字段；
# - 结算层（combat/enemy/consumable）只读 *_mult() 查询，不认具体怪物；
# - 净化 vs 清净职责分离：
#     净化（purify / kind = interference）→ 目盲、缠绕（转轮操作干扰）
#     清净（cleanse  / kind = status）      → 虚弱、易伤、腐蚀、禁疗、反噬
# - 吸能 / 剥增益为一次性效果（kind = instant），不进入计时表。
#
# 纪律：
# - 不消耗全局 RNG（提示、文案、计时全为确定性）；
# - 持续时间按「玩家实际经历多少个转轮」计算：转轮前施加当回合生效；结算中/敌人回合施加从下一回合起算；
# - 任何减益都有解除路径（自动到期 / 破甲 / 净化 / 清净），不永久封死资源。
# ============================================================================

const DEFS := {
	"weak": {
		"name": "虚弱", "icon": "💢", "kind": "status", "turns": 1,
		"desc": "攻击收益 -20%", "counter": "换功能符号 / 清净药剂",
	},
	"vulnerable": {
		"name": "易伤", "icon": "🩸", "kind": "status", "turns": 2,
		"desc": "承伤 +25%", "counter": "防御 / 抢斩杀 / 清净药剂",
	},
	"corrode": {
		"name": "腐蚀", "icon": "🧪", "kind": "status", "turns": 99,
		"desc": "护盾收益 -25%（破甲或清净解除）", "counter": "破甲 / 恢复 / 清净药剂",
	},
	"drain": {
		"name": "吸能", "icon": "🔋", "kind": "instant",
		"desc": "充能 -2（不低于 0）", "counter": "提前爆发 / 重新积累",
	},
	"heal_block": {
		"name": "禁疗", "icon": "🚫", "kind": "status", "turns": 1,
		"desc": "治疗收益 -50%（不完全禁止）", "counter": "护盾 / 抢攻 / 清净药剂",
	},
	"blind": {
		"name": "目盲", "icon": "🌫", "kind": "interference", "turns": 2,
		"desc": "隐藏后续预览，当前中心符号仍可见", "counter": "看当前格 / 净化药剂",
	},
	"entangle": {
		"name": "缠绕", "icon": "🪢", "kind": "interference", "turns": 1,
		"desc": "本回合需按指定方向逐列停止", "counter": "按顺序操作 / 净化药剂",
	},
	"backlash": {
		"name": "反噬", "icon": "⚡", "kind": "status", "turns": 1,
		"desc": "连续使用同一符号时受小额代价", "counter": "换符号 / 清净药剂",
	},
	"strip": {
		"name": "剥增益", "icon": "🪓", "kind": "instant",
		"desc": "移除一个当前增益", "counter": "提前使用 / 重新获得 / 抢攻",
	},
}

const WEAK_DAMAGE_MULT := 0.8       # 虚弱：玩家攻击收益 -20%
const VULNERABLE_TAKEN_MULT := 1.25 # 易伤：玩家承伤 +25%
const CORRODE_SHIELD_MULT := 0.75   # 腐蚀：护盾收益 -25%
const HEAL_BLOCK_MULT := 0.5        # 禁疗：治疗收益 -50%
const DRAIN_AMOUNT := 2             # 吸能：充能 -2
const BACKLASH_HP_PCT := 0.02       # 反噬：连续同符号代价 = 2% maxHP（至少 1，且不致死）
const LONG_TURNS := 99              # 展示为「直到解除」的持续型（腐蚀）

# 结构：id -> { "turns": int, "stacks": int, "applied_turn": int, "order": String }
var active: Dictionary = {}
var _seen: Dictionary = {}          # 本房已做过首次提示的 id
var _prev_syms: Array[String] = []  # 上一回合结算到的符号（反噬判定）
var _last_cost_turn := -1           # 反噬每回合最多一次


# 新房间 / 新一局：清空计时与提示记忆。
func reset() -> void:
	active.clear()
	_seen.clear()
	_prev_syms.clear()
	_last_cost_turn = -1


# —— 施加 ——
# turns < 0 用定义默认值；extra 目前支持 {"order": "ltr"|"rtl"}（缠绕方向）。
# 返回是否成功施加（未知 id 返回 false，只记一条警告，不崩溃）。
func apply(ctrl, id: String, turns: int = -1, stacks: int = 1, extra: Dictionary = {}) -> bool:
	if not DEFS.has(id):
		if ctrl != null and ctrl.hud != null:
			ctrl.hud._log("⚠ 未知减益：%s（忽略）" % id)
		return false
	var d: Dictionary = DEFS[id]
	if String(d.get("kind", "status")) == "instant":
		_apply_instant(ctrl, id)
		_prompt(ctrl, id, d, {}, true)
		_after(ctrl)
		return true
	var t: int = int(d.get("turns", 1)) if turns < 0 else maxi(1, turns)
	var rec: Dictionary = active.get(id, {})
	var before_spin: bool = true if ctrl == null else not bool(ctrl.turn_resolved)
	if rec.is_empty():
		rec = {
			"turns": t,
			"stacks": clampi(stacks, 1, 3),
			"applied_turn": int(ctrl.turn_count) if ctrl != null else 0,
			"before_spin": before_spin,
			"order": String(extra.get("order", "ltr")),
		}
		active[id] = rec
	else:
		# 叠加：时长取较长者（不做无限延长），层数 +1（上限 3）；刷新施放回合避免当回合被 tick
		rec["turns"] = maxi(int(rec["turns"]), t)
		rec["stacks"] = clampi(int(rec["stacks"]) + stacks, 1, 3)
		rec["applied_turn"] = int(ctrl.turn_count) if ctrl != null else 0
		rec["before_spin"] = before_spin
		if extra.has("order"):
			rec["order"] = String(extra.get("order", "ltr"))
	_prompt(ctrl, id, d, rec, active.get(id, {}).get("stacks", 1) > 1)
	_after(ctrl)
	return true


# —— 回合末计时 ——
# 计时按「玩家实际经历过的转轮」计算：
#   转轮前施加（入场 / 回合开始钩子）→ 本回合就吃一次，回合末 -1；
#   结算中 / 敌人回合施加（三连钩子、受击、破甲）→ 从下一回合开始算，回合末不扣。
func tick_turn_end(ctrl) -> void:
	if active.is_empty():
		return
	var expired: Array[String] = []
	for id in active.keys():
		var rec: Dictionary = active[id]
		if ctrl != null:
			var applied: int = int(rec.get("applied_turn", 0))
			if applied >= int(ctrl.turn_count):
				# 同一回合：只有转轮前施加的才算「已经用过一回合」
				if applied > int(ctrl.turn_count) or not bool(rec.get("before_spin", true)):
					continue
		rec["turns"] = int(rec.get("turns", 0)) - 1
		if int(rec["turns"]) <= 0:
			expired.append(id)
	for id in expired:
		active.erase(id)
		if ctrl != null and ctrl.hud != null:
			ctrl.hud._log("%s %s 结束" % [icon(id), name_of(id)])
	if not expired.is_empty():
		_after(ctrl)


# —— 查询 ——
func has(id: String) -> bool:
	return active.has(id)

func turns_left(id: String) -> int:
	return int(active.get(id, {}).get("turns", 0))

func name_of(id: String) -> String:
	return String(DEFS.get(id, {}).get("name", id))

func icon(id: String) -> String:
	return String(DEFS.get(id, {}).get("icon", "✳"))

func damage_mult() -> float:
	return WEAK_DAMAGE_MULT if active.has("weak") else 1.0

func taken_mult() -> float:
	return VULNERABLE_TAKEN_MULT if active.has("vulnerable") else 1.0

func shield_mult() -> float:
	return CORRODE_SHIELD_MULT if active.has("corrode") else 1.0

func heal_mult() -> float:
	return HEAL_BLOCK_MULT if active.has("heal_block") else 1.0

func preview_hidden() -> bool:
	return active.has("blind")

func entangle_active() -> bool:
	return active.has("entangle")

func entangle_order() -> String:
	return String(active.get("entangle", {}).get("order", "ltr"))

# 缠绕：本回合下一个「必须按顺序按停」的列；-1 = 不限制（已全部停住 / 无缠绕）。
# 跳过冻结列、锁轮列（begin_spin 中已 reel_stopped）与吸附中的列，避免要求玩家停无法操作的列。
func entangle_next(rs) -> int:
	if not active.has("entangle") or rs == null:
		return -1
	var ltr: bool = String(active["entangle"].get("order", "ltr")) == "ltr"
	var seq := [0, 1, 2] if ltr else [2, 1, 0]
	for r in seq:
		if r < rs.reel_stopped.size() and not bool(rs.reel_stopped[r]) and not rs.is_absorbing(r):
			return int(r)
	return -1

# HUD 状态行：💢虚弱1 · 🩸易伤2（长久型不显示数字）
func summary() -> String:
	var parts: Array[String] = []
	for id in DEFS.keys():
		if not active.has(id):
			continue
		var t: int = turns_left(id)
		parts.append("%s%s%s" % [icon(id), name_of(id), "" if t >= LONG_TURNS else str(t)])
	return " · ".join(parts)

# 状态行 tooltip：逐条「图标 名称：效果（剩余 N 回合）｜应对：…」
func detail_text() -> String:
	var lines: Array[String] = []
	for id in DEFS.keys():
		if not active.has(id):
			continue
		var d: Dictionary = DEFS[id]
		var t: int = turns_left(id)
		var left := "直到解除" if t >= LONG_TURNS else ("剩余 %d 回合" % t)
		lines.append("%s %s：%s（%s）\n   应对：%s" % [
			d.get("icon", "✳"), d.get("name", id), d.get("desc", ""), left, d.get("counter", "")])
	return "\n".join(lines)


# —— 解除 ——
# 清净：只解 status 类，返回被解除的显示名（供消耗品反馈）。
func clear_status(ctrl) -> Array[String]:
	return _clear_kind(ctrl, "status")

# 净化：只解 interference 类（转轮操作干扰），返回被解除的显示名。
func clear_interference(ctrl) -> Array[String]:
	return _clear_kind(ctrl, "interference")

# 破甲解除：腐蚀随玩家破甲来源结束。
func clear_on_armor_break(ctrl) -> Array[String]:
	var out: Array[String] = []
	for id in active.keys():
		if id != "corrode":
			continue
		out.append(name_of(id))
		active.erase(id)
	if not out.is_empty():
		if ctrl != null and ctrl.hud != null:
			ctrl.hud._log("🧪 破甲：腐蚀解除")
		_after(ctrl)
	return out

func _clear_kind(ctrl, kind: String) -> Array[String]:
	var out: Array[String] = []
	for id in active.keys():
		if String(DEFS[id].get("kind", "status")) != kind:
			continue
		out.append(name_of(id))
		active.erase(id)
	if not out.is_empty():
		_after(ctrl)
	return out


# —— 反噬：每回合结算符号时调用一次 ——
# 连续使用上一回合出现过的符号 → 小额代价（盾→HP，HP 不低于 1，不致死）；
# 换了符号 → 反噬立即结束（与计划「换符号即结束」一致）。
func note_turn_symbols(ctrl, syms: Array) -> void:
	if active.has("backlash") and ctrl != null and int(ctrl.turn_count) != _last_cost_turn:
		var repeat := false
		for p in syms:
			if _prev_syms.has(String(p)):
				repeat = true
				break
		if repeat:
			_apply_backlash_cost(ctrl)
		else:
			active.erase("backlash")
			if ctrl.hud != null:
				ctrl.hud._log("⚡ 反噬结束：你换了符号")
			_after(ctrl)
	_prev_syms.clear()
	for p in syms:
		_prev_syms.append(String(p))


# —— 内部 ——
func _apply_backlash_cost(ctrl) -> void:
	_last_cost_turn = int(ctrl.turn_count)
	var cost: int = maxi(1, int(round(float(ctrl.player_hp_max) * BACKLASH_HP_PCT)))
	var blocked: int = mini(int(ctrl.player_shield), cost)
	ctrl.player_shield -= blocked
	var dealt: int = cost - blocked
	if dealt > 0:
		ctrl.player_hp = maxi(1, int(ctrl.player_hp) - dealt)   # 反噬不致死：避免减益直接封死本局
	if ctrl.hud != null:
		ctrl.hud._popup("⚡反噬 -%d" % dealt, Palette.POP_DAMAGE, ctrl.hud._player_sprite_anchor())
		ctrl.hud._log("⚡ 反噬：连续同符号，代价 %d（盾挡 %d，实受 %d）" % [cost, blocked, dealt])


func _apply_instant(ctrl, id: String) -> void:
	if ctrl == null:
		return
	match id:
		"drain":
			var before: int = int(ctrl.charge_points)
			ctrl.charge_points = maxi(0, before - DRAIN_AMOUNT)
			if ctrl.hud != null:
				ctrl.hud._log("🔋 吸能：充能 %d → %d" % [before, int(ctrl.charge_points)])
		"strip":
			_strip_one_buff(ctrl)


func _strip_one_buff(ctrl) -> bool:
	var keys: Array = ctrl.player_buffs.keys()
	if keys.is_empty():
		if ctrl.hud != null:
			ctrl.hud._log("🪓 剥增益：当前没有可移除的增益")
		return false
	# 确定性选择：剩余回合最少者优先（同值按名称），不掷随机
	keys.sort_custom(func(a, b):
		var ta: int = int(ctrl.player_buffs[a])
		var tb: int = int(ctrl.player_buffs[b])
		if ta != tb:
			return ta < tb
		return String(a.label) < String(b.label))
	var sym = keys[0]
	var left: int = int(ctrl.player_buffs[sym])
	ctrl.player_buffs.erase(sym)
	if ctrl.hud != null:
		ctrl.hud._log("🪓 剥增益：移除「%s %s」（原剩余 %d 回合）" % [sym.label, sym.name, left])
		ctrl.hud._show_action_feedback("剥增益：%s" % String(sym.name))
	return true


func _prompt(ctrl, id: String, d: Dictionary, rec: Dictionary, stacked: bool) -> void:
	if ctrl == null or ctrl.hud == null:
		return
	var nm := String(d.get("name", id))
	var ic := String(d.get("icon", "✳"))
	if not _seen.has(id):
		_seen[id] = true
		var left := ""
		if not rec.is_empty():
			var t: int = int(rec.get("turns", 0))
			left = "（%s）" % ("直到解除" if t >= LONG_TURNS else ("%d 回合" % t))
		ctrl.hud._log("%s %s：%s%s｜应对：%s" % [ic, nm, d.get("desc", ""), left, d.get("counter", "")])
		return
	if stacked and not rec.is_empty():
		ctrl.hud._log("%s %s 叠加（剩余 %d 回合）" % [ic, nm, int(rec.get("turns", 0))])
	else:
		ctrl.hud._log("%s %s 仍在生效" % [ic, nm])


func _after(ctrl) -> void:
	if ctrl == null:
		return
	if ctrl.has_method("invalidate_state"):
		ctrl.invalidate_state()
	if ctrl.hud != null:
		ctrl.hud._refresh_meta()
