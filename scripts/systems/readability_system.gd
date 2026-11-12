extends RefCounted

# ============================================================================
# P1 · 目押可读性原型（docs/转轮目押_成长与减带优化_执行方案.md §5）
#
# 只做“看得清、停得准、反馈可解释”，不改任何伤害/掉落/数值。
# 预设（命令行 --p1-preset=<name>，或战斗内 F8 在 control / readable 间切换）：
#   control  = 当前规则（对照）
#   readable = 慢化最快阶段 + 下一格预览 + 视觉落点对齐 + 最多一拍缓冲 + 命中反馈
#   speed    = 只慢化最快阶段
#   preview  = 只增加下一格预览
#   visual   = 只把落点对齐到视觉中心
#   buffer   = 视觉中心 + 最多一拍缓冲
#   feedback = 只加目标/普通/MISS 命中反馈
#
# “视觉落点对齐”：玩家按停时，取视觉上最接近中心的那一格，而不是上一逻辑拍的格子。
# “缓冲”：若最近中心是下一格且尚未到达，则等到下一逻辑拍再锁定（最多 1 拍）；
#          它不自动选目标，也不跨越多格。
# ============================================================================

# 2026-11-12 转轮手感 Step 3：5 格/秒起转，0.32s 后进入巡航，高速封顶，加速段约 1.5s。
# 2026-11-12 二次调整：符号图标从 16px 升到 32px，滚动槽间距 19→30px，
# 同样的「格/秒」下视觉像素速度会快 58%（171→270 px/s）。为了让观感回到改动前，
# 把整条速度曲线按 19/30 = 0.633 等比缩放（含上限与加速），保持 1.5s 到顶的时间不变。
# 代价：转轮逻辑节拍变慢，旋转总时长约 ×1.58。
const CRUISE_CPS := 5.7           # 原 9.0；视觉 ≈ 30px × 5.7 = 171 px/s
const MAX_CPS := 7.6              # 原 12.0
const READABLE_MAX_CPS := 7.0     # 原 11.0
const CONTROL_ACCEL := 0.0051     # 原 0.0020：节拍变慢后需按比例加大，才能仍在 ~1.5s 到顶
const READABLE_ACCEL := 0.0038    # 原 0.0014

const PRESETS := {
	"control":  {"base": 1.0 / CRUISE_CPS, "min": 1.0 / MAX_CPS, "accel": CONTROL_ACCEL, "preview": 0, "visual": false, "buffer": false, "feedback": false},
	"readable": {"base": 1.0 / CRUISE_CPS, "min": 1.0 / READABLE_MAX_CPS, "accel": READABLE_ACCEL, "preview": 2, "visual": true,  "buffer": true,  "feedback": true},
	"speed":    {"base": 1.0 / CRUISE_CPS, "min": 1.0 / READABLE_MAX_CPS, "accel": READABLE_ACCEL, "preview": 0, "visual": false, "buffer": false, "feedback": false},
	"preview":  {"base": 1.0 / CRUISE_CPS, "min": 1.0 / MAX_CPS, "accel": CONTROL_ACCEL, "preview": 2, "visual": false, "buffer": false, "feedback": false},
	"visual":   {"base": 1.0 / CRUISE_CPS, "min": 1.0 / MAX_CPS, "accel": CONTROL_ACCEL, "preview": 0, "visual": true,  "buffer": false, "feedback": false},
	"buffer":   {"base": 1.0 / CRUISE_CPS, "min": 1.0 / MAX_CPS, "accel": CONTROL_ACCEL, "preview": 0, "visual": true,  "buffer": true,  "feedback": false},
	"feedback": {"base": 1.0 / CRUISE_CPS, "min": 1.0 / MAX_CPS, "accel": CONTROL_ACCEL, "preview": 0, "visual": false, "buffer": false, "feedback": true},
}
const CYCLE := ["control", "readable"]

var _ctrl
var preset := "control"
var base_wait := 1.0 / CRUISE_CPS
var min_wait := 1.0 / MAX_CPS
var accel := CONTROL_ACCEL
var preview_slots := 0
var visual_stop := false
var buffer_enabled := false
var feedback_enabled := false
var steady_hand_used := false    # G7-A S1「稳手」：本回合那一次额外缓冲是否已用掉

var target_symbol_path := ""
var target_reason := "输出窗口"
var target_detail := "优先停中主武器的高权重攻击符号。"
var _forced_target := ""

# G7-D Step 1–2：标准提示改为「局势 + 真实可选对策」。
# target_* 仍保留给固定目标对照与遥测口径；situation/counters 只做信息展示，不替玩家按停。
var situation := ""
var situation_detail := ""
var counters: Array = []   # [{label, kind, path, note}]，path 为空表示兜底选项

# 本回合 / 本局统计（只读遥测，不参与结算）
var stop_results: Array = []      # [{reel, path, name, outcome, reason}]
var player_stops := 0
var target_hits := 0
var forced_stops := 0
var buffer_queues := 0


func _init(ctrl) -> void:
	_ctrl = ctrl
	var cli_preset := "control"
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--p1-preset="):
			cli_preset = s.trim_prefix("--p1-preset=")
		elif s.begins_with("--p1-target="):
			_forced_target = s.trim_prefix("--p1-target=")
	_apply(cli_preset, false)


func apply_preset(name: String) -> void:
	_apply(name, true)


func cycle_preset() -> void:
	var idx := CYCLE.find(preset)
	var nxt: String = CYCLE[(idx + 1) % CYCLE.size()] if idx >= 0 else CYCLE[0]
	apply_preset(nxt)


func _apply(name: String, notify: bool) -> void:
	var key: String = name if PRESETS.has(name) else "control"
	var p: Dictionary = PRESETS[key]
	preset = key
	base_wait = float(p["base"])
	min_wait = float(p["min"])
	accel = float(p["accel"])
	preview_slots = int(p["preview"])
	visual_stop = bool(p["visual"])
	buffer_enabled = bool(p["buffer"])
	feedback_enabled = bool(p["feedback"])
	if notify:
		if _ctrl.hud != null and _ctrl.hud.has_method("_refresh_p1_ui"):
			_ctrl.hud._refresh_p1_ui()
		if _ctrl.hud != null:
			_ctrl.hud._log("🎛 P1 预设：%s（速度 %s / 预览 %d / 视觉落点 %s / 缓冲 %s / 反馈 %s）" % [
				preset, _speed_text(), preview_slots,
				"开" if visual_stop else "关", "开" if buffer_enabled else "关", "开" if feedback_enabled else "关"])


func _speed_text() -> String:
	if is_equal_approx(accel, CONTROL_ACCEL) and is_equal_approx(min_wait, 1.0 / MAX_CPS):
		return "当前"
	return "慢化"


# 新一局：清统计、按当前配装重选目标。CLI 指定目标时优先保留。
func reset_run() -> void:
	stop_results.clear()
	player_stops = 0
	target_hits = 0
	forced_stops = 0
	buffer_queues = 0
	steady_hand_used = false
	situation = ""
	situation_detail = ""
	counters = []
	target_symbol_path = _forced_target if _forced_target != "" else _default_target()
	if _ctrl._telemetry != null:
		_ctrl._telemetry.target_symbol = target_symbol_path


func begin_spin() -> void:
	stop_results.clear()
	steady_hand_used = false   # 稳手按回合刷新
	if _ctrl.hud != null and _ctrl.hud.has_method("_clear_stop_feedback"):
		_ctrl.hud._clear_stop_feedback()


# G7-A S1「稳手」：每回合一次额外的一拍缓冲，与 P1 预设的 buffer_enabled 独立。
# 只影响玩家按停的落点解析，不改速度、预览格数或任何伤害。
func steady_hand_ready() -> bool:
	if steady_hand_used or _ctrl == null or _ctrl.growth == null:
		return false
	return _ctrl.growth.has_perk("steady_hand")


func consume_steady_hand() -> void:
	steady_hand_used = true


func finish_spin() -> void:
	if feedback_enabled and _ctrl.hud != null and _ctrl.hud.has_method("_show_spin_summary"):
		_ctrl.hud._show_spin_summary(turn_summary())


func on_buffer_queued() -> void:
	buffer_queues += 1
	if _ctrl._telemetry != null:
		_ctrl._telemetry.on_buffer_queued()


# reason: player / forced / jam / lock
func on_stop(reel: int, sym, reason: String) -> void:
	var path := ""
	var nm := ""
	var kind := ""
	if sym != null and sym is Resource:
		path = String(sym.resource_path)
		nm = String(sym.name) if String(sym.name) != "" else String(sym.label)
		kind = String(sym.kind)
	var outcome := "normal"
	if reason == "jam":
		outcome = "jam"
	elif reason == "lock":
		outcome = "lock"
	elif reason == "forced":
		outcome = "forced"
	elif sym == null or kind == "trash":
		outcome = "miss"
	elif path == target_symbol_path and target_symbol_path != "":
		outcome = "target"
	var rec := {"reel": reel, "path": path, "name": nm, "outcome": outcome, "reason": reason}
	stop_results.append(rec)
	if reason == "player":
		player_stops += 1
		if outcome == "target":
			target_hits += 1
	if reason == "forced":
		forced_stops += 1
	if _ctrl.hud != null and _ctrl.hud.has_method("_show_stop_feedback") and feedback_enabled:
		_ctrl.hud._show_stop_feedback(reel, nm, outcome)
	# Step 4：停列短确认（边框 + 轻微缩放）对 control 预设也生效——它只做视觉确认，
	# 不加文本、不改落点、不占输入；预设差异仍留给 preview/visual/buffer/feedback。
	if _ctrl.hud != null and _ctrl.hud.has_method("_pulse_stop_cell"):
		_ctrl.hud._pulse_stop_cell(reel, outcome)
	if _ctrl._telemetry != null:
		_ctrl._telemetry.on_stop(path, target_symbol_path, outcome, reason != "player", kind)


func turn_summary() -> String:
	if stop_results.is_empty():
		return ""
	var n_target := 0
	var n_normal := 0
	var n_miss := 0
	var n_forced := 0
	for r in stop_results:
		match String(r["outcome"]):
			"target": n_target += 1
			"normal": n_normal += 1
			"miss", "jam": n_miss += 1
			"lock", "forced": n_forced += 1
	var parts: Array[String] = []
	parts.append("目标 %d/%d" % [n_target, player_stops])
	if n_normal > 0:
		parts.append("普通 %d" % n_normal)
	if n_miss > 0:
		parts.append("MISS %d" % n_miss)
	if n_forced > 0:
		parts.append("机制 %d" % n_forced)
	return "本回合：" + " · ".join(parts)


func target_label() -> String:
	if target_symbol_path == "":
		return "—"
	var s = load(target_symbol_path)
	if s != null and s is Resource:
		var n := String(s.name)
		return n if n != "" else String(s.label)
	return target_symbol_path.get_file().get_basename()


func target_hit_rate() -> float:
	return float(target_hits) / float(player_stops) if player_stops > 0 else 0.0


# 默认目标：主武器（配装顺序第一把）中权重最高的 damage 符号。
# 与 P0 基线口径一致；P1 A/B 固定使用该目标。
func _default_target() -> String:
	if _ctrl.selected_loadout.is_empty():
		return ""
	var best_path := ""
	var best_w := -1.0
	for wp in _ctrl.selected_loadout:
		var wd = load(wp)
		if wd == null or wd.symbols == null:
			continue
		for sw in wd.symbols:
			if sw == null or sw.symbol == null:
				continue
			if String(sw.symbol.kind) == "damage" and float(sw.weight) > best_w:
				best_w = float(sw.weight)
				best_path = String(sw.symbol.resource_path)
		if best_path != "":
			break   # 只看主武器
	return best_path


# 每个真实玩家回合更新一次：目标（固定对照/遥测口径）+ 局势与真实对策（标准提示）。
# 标准提示只解释局势、列出当前带内确实可用的对策；不指定唯一答案，不替玩家按停。
func update_turn_target() -> void:
	if _forced_target != "":
		_set_target(_forced_target, "指定目标", "命令行指定的固定对照目标。")
		_set_situation("固定对照", "命令行指定目标 %s；仅用于 A/B 对照，不参与标准提示。" % target_label(),
			[{"label": target_label(), "kind": "forced", "path": _forced_target, "note": "固定对照目标"}])
		_refresh_ui()
		return
	var intent: Dictionary = _ctrl.enemy_intent
	var intent_type := String(intent.get("type", "none"))
	var intent_value := int(intent.get("value", 0))
	# Step 5：机制声明的节奏窗口（蓄势 / 爆发 / 恢复）；普通战与无 Rhythm 的机制为空。
	var rhythm := ""
	if _ctrl.current_gimmick != null:
		rhythm = String(_ctrl.current_gimmick.rhythm_window(_ctrl))
	if intent_type == "heavy":
		var shield := _first_symbol_of_kind("shield")
		var heal := _first_symbol_of_kind("heal")
		if shield != "":
			_set_target(shield, "重击·先护盾", "敌人预告重击 %d；优先停中护盾符号，保留其他列的输出选择。" % intent_value)
		elif heal != "" and _ctrl.player_hp < _ctrl.player_hp_max:
			_set_target(heal, "重击·先恢复", "当前带内没有护盾符号；敌人预告重击 %d，可用治疗或消耗品降低风险。" % intent_value)
		else:
			_set_target(_default_target(), "重击·抢攻/承伤", "敌人预告重击 %d；没有防御符号时可直接承伤或抢攻，不跟随建议不算错误。" % intent_value)
		_set_situation("重击 %d" % intent_value,
			"敌人预告重击 %d。下列对策按当前带内真实资源列出；直接承伤也是可计算的选项。" % intent_value,
			_heavy_counters(intent_value))
		_refresh_ui()
		return
	if _ctrl.player_hp <= int(_ctrl.player_hp_max * 0.4):
		var heal := _first_symbol_of_kind("heal")
		if heal != "":
			_set_target(heal, "低血·先恢复", "当前 HP %d/%d；优先恢复，也可根据意图继续抢攻。" % [_ctrl.player_hp, _ctrl.player_hp_max])
		else:
			_set_target(_default_target(), "低血·抢攻/恢复", "当前 HP %d/%d；带内没有治疗符号，可用消耗品或抢攻。" % [_ctrl.player_hp, _ctrl.player_hp_max])
		_set_situation("低血 %d/%d" % [_ctrl.player_hp, _ctrl.player_hp_max],
			"当前 HP %d/%d。恢复与抢攻都是可选方向。" % [_ctrl.player_hp, _ctrl.player_hp_max],
			_low_hp_counters())
		_refresh_ui()
		return
	var recovery: bool = rhythm == "恢复" or (_ctrl.current_gimmick != null and _ctrl.current_gimmick.recovery_window(_ctrl))
	if recovery:
		# Step 5：恢复窗口文案由机制声明，避免非熔铸类 BOSS 误显示「熔铸间隙」。
		var rec_title := "间隙"
		var rec_detail := "本回合敌人不追加新的加压或干扰；可治疗、净化、破甲或集中输出。"
		if _ctrl.current_gimmick != null:
			var t := String(_ctrl.current_gimmick.recovery_title(_ctrl))
			var d := String(_ctrl.current_gimmick.recovery_detail(_ctrl))
			if t != "":
				rec_title = t
			if d != "":
				rec_detail = d
		if _ctrl.enemy_armor > 0:
			var special := _first_symbol_of_kind("special")
			if special != "":
				_set_target(special, "间隙·破甲", rec_detail)
			else:
				_set_target(_default_target(), "间隙·输出", rec_detail)
		else:
			_set_target(_default_target(), "间隙·输出", rec_detail)
		_set_situation(rec_title, rec_detail, _recovery_counters())
		_refresh_ui()
		return
	# Step 5：爆发窗口 = 敌人刚叠甲/冻结的当回合；恢复窗口已在上方优先处理。
	if rhythm == "爆发":
		var burst_special := _first_symbol_of_kind("special")
		_set_target(burst_special if burst_special != "" else _default_target(),
			"爆发·破甲/承伤", "敌人完成蓄势：护甲与冻结已生效；可三连破甲、穿透直击、清净解冻或直接承伤。")
		_set_situation("爆发 · 护甲 %d/%d" % [int(_ctrl.enemy_armor), int(_ctrl.enemy_armor_max)],
			"敌人刚完成蓄势：护甲/冻结已生效。破甲、解冻、硬吃与继续输出都是可计算的选择。",
			_burst_counters())
		_refresh_ui()
		return
	# Step 5：蓄势窗口 = 下一次叠甲/冻结前的准备回合；提前破甲和留资源同样成立。
	if rhythm == "蓄势":
		var prep_special := _first_symbol_of_kind("special")
		_set_target(prep_special if prep_special != "" else _default_target(),
			"蓄势·准备", "下一次叠甲/冻结还没到；可提前破甲、攒强化，或保留资源给爆发后的恢复窗口。")
		_set_situation("蓄势 · 下回合爆发",
			"敌人正在蓄势，下一次爆发（叠甲/冻结）即将到来。提前破甲、保持输出、攒资源或直接留到恢复窗口都成立。",
			_windup_counters())
		_refresh_ui()
		return
	if _ctrl.enemy_armor > 0:
		var special := _first_symbol_of_kind("special")
		if special != "":
			_set_target(special, "高甲·破甲", "敌人当前护甲 %d；带内存在特殊符号，可争取三连破甲。" % int(_ctrl.enemy_armor))
		else:
			_set_target(_default_target(), "高甲·穿透/输出", "敌人当前护甲 %d；带内没有特殊符号，可用穿透符号或消耗品破甲。" % int(_ctrl.enemy_armor))
		_set_situation("高甲 %d/%d" % [int(_ctrl.enemy_armor), int(_ctrl.enemy_armor_max)],
			"敌人当前护甲 %d/%d。特殊三连可清空护甲，穿透符号直接扣 HP。" % [int(_ctrl.enemy_armor), int(_ctrl.enemy_armor_max)],
			_armor_counters())
		_refresh_ui()
		return
	var interfered: bool = _ctrl.pending_jam_reel >= 0 or _ctrl.pending_lock_reel >= 0 or _ctrl.pending_chaos or _ctrl.pending_auto_stop
	var data: IntentData = intent.get("data")
	interfered = interfered or (data != null and data.purifiable)
	var status_key := ""
	if _ctrl.player_frost > 0:
		status_key = "frozen"
	elif int(_ctrl.player_status.get("poison", 0)) > 0:
		status_key = "poison"
	interfered = interfered or status_key != ""
	if interfered:
		var itype := String(intent.get("type", "none"))
		if itype == "none" or itype == "":
			if _ctrl.pending_jam_reel >= 0:
				itype = "jam"
			elif _ctrl.pending_lock_reel >= 0:
				itype = "lock"
			elif _ctrl.pending_chaos:
				itype = "chaos"
			elif _ctrl.pending_auto_stop:
				itype = "auto_stop"
		var sit := "干扰"
		if status_key == "frozen":
			sit = "干扰 寒霜"
		elif status_key == "poison":
			sit = "干扰 酸蚀"
		else:
			sit = "干扰 %s" % _intent_name(itype)
		_set_target(_default_target(), "干扰·输出/净化", "转轮将受到干扰；可继续输出，也可按既有规则使用净化/清净消耗品。")
		_set_situation(sit,
			"%s；可净化、清净或照常停轮，不使用消耗品不会导致必败。" % sit,
			_interference_counters(data, itype))
		_refresh_ui()
		return
	if _ctrl.enemy_hp > 0 and _ctrl.enemy_hp <= int(_ctrl.enemy_hp_max * 0.25):
		_set_target(_default_target(), "残血·收尾", "敌人 HP 较低；优先集中输出，减少无决策价值的残血回合。")
		_set_situation("残血 %d/%d" % [int(_ctrl.enemy_hp), int(_ctrl.enemy_hp_max)],
			"敌人 HP 较低；可抢攻收尾，也可保留消耗品给下一战。",
			_finishing_counters())
		_refresh_ui()
		return
	_set_target(_default_target(), "输出窗口", "当前没有更紧迫的防御或破甲需求；优先主武器高权重攻击符号。")
	_set_situation("输出窗口", "当前没有更紧迫的防御或破甲需求；可按主武器输出，或保留消耗品。", _output_counters())
	_refresh_ui()


func is_fixed_target() -> bool:
	return _forced_target != ""


# ---- Step 1：真实对策查询（只读当前带/腰带/局势，不生成虚假建议） ----

func _heavy_counters(value: int) -> Array:
	var out: Array = []
	_push_counter(out, _symbol_counter("shield", "护盾符号", "可停中"))
	if _ctrl.player_hp < _ctrl.player_hp_max:
		_push_counter(out, _symbol_counter("heal", "治疗符号", "可停中"))
	_push_counter(out, _consumable_counter("heal", "治疗药剂", "立即回复"))
	out.append({"label": "硬吃 %d" % value, "short": "硬吃 %d" % value, "kind": "fallback", "path": "",
		"note": "不投入资源，预计承受 %d 伤害；护甲与格挡会降低实际承伤。" % value})
	return out


func _low_hp_counters() -> Array:
	var out: Array = []
	_push_counter(out, _symbol_counter("heal", "治疗符号", "可停中"))
	_push_counter(out, _consumable_counter("heal", "治疗药剂", "立即回复"))
	_push_counter(out, _symbol_counter("shield", "护盾符号", "可停中"))
	out.append({"label": "抢攻", "short": "抢攻", "kind": "fallback", "path": "",
		"note": "若判断能先击杀，可放弃恢复继续输出。"})
	return out


func _recovery_counters() -> Array:
	var out: Array = []
	if _ctrl.enemy_armor > 0:
		_push_counter(out, _symbol_counter("special", "破甲（特殊三连）", "三连清空护甲"))
		_push_counter(out, _pierce_counter())
		_push_counter(out, _consumable_counter("armor_shred", "破甲酸液", "立即清除护甲"))
	_push_counter(out, _symbol_counter("damage", "输出符号", "集中输出"))
	_push_counter(out, _consumable_counter("assault", "强化药剂", "下一次转轮伤害提升"))
	_push_counter(out, _consumable_counter("attack", "攻击药剂", "立即伤害"))
	return out


# Step 5：爆发当回合的真实对策（破甲 / 直击 / 解冻 / 承伤 / 强化），不指定唯一答案。
func _burst_counters() -> Array:
	var out: Array = []
	_push_counter(out, _symbol_counter("special", "破甲（特殊三连）", "三连清空护甲"))
	_push_counter(out, _pierce_counter())
	_push_counter(out, _consumable_counter("armor_shred", "破甲酸液", "立即清除护甲"))
	if _ctrl.player_frost > 0:
		_push_counter(out, _consumable_counter("cleanse", "清净药剂", "当回合解除冻结"))
	_push_counter(out, _symbol_counter("damage", "承压输出", "冻结/护甲下仍可正常停轮"))
	_push_counter(out, _consumable_counter("assault", "强化药剂", "下一次转轮伤害提升"))
	out.append({"label": "直接承伤", "short": "承伤", "kind": "fallback", "path": "",
		"note": "不投入资源，按当前护甲/冻结继续输出；冻结会在下一回合自消。"})
	return out


# Step 5：蓄势回合的真实对策（提前破甲 / 保持输出 / 攒资源 / 留到恢复窗口）。
func _windup_counters() -> Array:
	var out: Array = []
	if _ctrl.enemy_armor > 0:
		_push_counter(out, _symbol_counter("special", "提前破甲（特殊三连）", "三连清空护甲"))
		_push_counter(out, _pierce_counter())
		_push_counter(out, _consumable_counter("armor_shred", "破甲酸液", "立即清除护甲"))
	_push_counter(out, _symbol_counter("damage", "保持输出", "蓄势回合同样是输出窗口"))
	_push_counter(out, _consumable_counter("assault", "强化药剂", "把下一次转轮留给恢复窗口"))
	_push_counter(out, _consumable_counter("attack", "攻击药剂", "立即伤害"))
	out.append({"label": "保留资源", "short": "留资源", "kind": "fallback", "path": "",
		"note": "不投入消耗品也可以；把资源留给爆发后的恢复窗口同样成立。"})
	return out


func _armor_counters() -> Array:
	var out: Array = []
	_push_counter(out, _symbol_counter("special", "破甲（特殊三连）", "三连清空护甲"))
	_push_counter(out, _pierce_counter())
	_push_counter(out, _consumable_counter("armor_shred", "破甲酸液", "立即清除护甲"))
	_push_counter(out, _symbol_counter("damage", "输出符号", "先磨甲再打血"))
	if out.is_empty():
		out.append({"label": "普通攻击磨甲", "short": "磨甲", "kind": "fallback", "path": "",
			"note": "没有特殊/穿透/破甲消耗品；只能按普通伤害逐点磨掉护甲。"})
	return out


func _interference_counters(data: IntentData, itype: String) -> Array:
	var out: Array = []
	var purifiable: bool = (data != null and data.purifiable) or itype in ["jam", "lock", "chaos"]
	if purifiable:
		_push_counter(out, _consumable_counter("purify", "净化药剂", "抵消敌人干扰意图"))
	if _ctrl.player_frost > 0 or int(_ctrl.player_status.get("poison", 0)) > 0:
		_push_counter(out, _consumable_counter("cleanse", "清净药剂", "解除冻结/毒层"))
	_push_counter(out, _symbol_counter("damage", "照常输出", "干扰下仍可正常停轮输出"))
	out.append({"label": "照常停轮", "short": "照常", "kind": "fallback", "path": "",
		"note": "不使用消耗品，按正常节奏停轮；干扰不会导致必败。"})
	return out


func _finishing_counters() -> Array:
	var out: Array = []
	_push_counter(out, _symbol_counter("damage", "输出符号", "集中收尾"))
	_push_counter(out, _consumable_counter("attack", "攻击药剂", "立即伤害"))
	_push_counter(out, _consumable_counter("assault", "强化药剂", "下一次转轮伤害提升"))
	return out


func _output_counters() -> Array:
	var out: Array = []
	_push_counter(out, _symbol_counter("damage", "输出符号", "主武器高权重攻击符号"))
	_push_counter(out, _consumable_counter("assault", "强化药剂", "下一次转轮伤害提升"))
	return out


func _symbol_counter(kind: String, label: String, note: String) -> Dictionary:
	var paths := _symbol_paths_of_kind(kind)
	if paths.is_empty():
		return {}
	return {"label": label, "short": _symbol_short(kind), "kind": "symbol_" + kind, "path": paths[0],
		"note": "%s：%s" % [note, "、".join(_symbol_names(paths))]}


func _pierce_counter() -> Dictionary:
	var paths := _pierce_paths()
	if paths.is_empty():
		return {}
	return {"label": "穿透符号", "short": "穿透", "kind": "symbol_pierce", "path": paths[0],
		"note": "穿透护甲直接扣 HP：%s" % "、".join(_symbol_names(paths))}


func _consumable_counter(effect: String, label: String, note: String) -> Dictionary:
	for slot in _ctrl.consumable_slots:
		if int(slot.get("charges", 0)) <= 0:
			continue
		var d = load(String(slot.get("path", "")))
		if d is ItemData and String(d.effect) == effect:
			return {"label": label, "short": _consumable_short(effect), "kind": "consumable_" + effect, "path": String(slot["path"]),
				"note": "%s（%s）" % [note, String(d.item_name)]}
	return {}


# Step 4：主栏只放短标签，完整名称与说明仍在 tooltip；避免 480 逻辑宽度下只显示半条对策。
func _symbol_short(kind: String) -> String:
	return {"shield": "护盾", "heal": "治疗", "special": "特殊三连", "damage": "输出", "buff": "增益"}.get(kind, kind)


func _consumable_short(effect: String) -> String:
	return {"heal": "治疗药", "armor_shred": "酸液", "cleanse": "清净", "purify": "净化",
		"assault": "强化", "attack": "攻击药", "reroll": "重转", "element": "精华"}.get(effect, effect)


func _push_counter(out: Array, counter: Dictionary) -> void:
	if not counter.is_empty():
		out.append(counter)


func _symbol_paths_of_kind(kind: String) -> Array:
	var out: Array = []
	if _ctrl.reel_system == null:
		return out
	for strip in _ctrl.reel_system.reel_strips:
		for entry in strip:
			var sym: SymbolData = entry[0]
			if sym == null or String(sym.kind) != kind:
				continue
			var p := String(sym.resource_path)
			if p != "" and not out.has(p):
				out.append(p)
	return out


func _pierce_paths() -> Array:
	var out: Array = []
	if _ctrl.reel_system == null:
		return out
	for strip in _ctrl.reel_system.reel_strips:
		for entry in strip:
			var sym: SymbolData = entry[0]
			if sym == null or not sym.pierce_armor:
				continue
			var p := String(sym.resource_path)
			if p != "" and not out.has(p):
				out.append(p)
	return out


func _symbol_names(paths: Array) -> Array:
	var names: Array = []
	for p in paths:
		var s = load(String(p))
		if s != null and s is Resource:
			var n := String(s.name)
			names.append(n if n != "" else String(s.label))
	return names


func _intent_name(t: String) -> String:
	if t == "auto_stop":
		return "夺轮"
	if _ctrl.has_method("_intent_name"):
		return String(_ctrl._intent_name(t))
	return {"jam": "注废", "lock": "锁轮", "chaos": "乱权", "heavy": "重击"}.get(t, "干扰")


func _set_situation(text: String, detail: String, arr: Array) -> void:
	situation = text
	situation_detail = detail
	counters = arr


func _refresh_ui() -> void:
	if _ctrl.hud != null and _ctrl.hud.has_method("_refresh_p1_ui"):
		_ctrl.hud._refresh_p1_ui()


func _first_symbol_of_kind(kind: String) -> String:
	if _ctrl.reel_system == null:
		return ""
	for strip in _ctrl.reel_system.reel_strips:
		for entry in strip:
			var sym: SymbolData = entry[0]
			if sym != null and String(sym.kind) == kind:
				return String(sym.resource_path)
	return ""


func _set_target(path: String, reason: String, detail: String) -> void:
	target_symbol_path = path
	target_reason = reason
	target_detail = detail
	if _ctrl._telemetry != null:
		_ctrl._telemetry.target_symbol = path
	if _ctrl.hud != null and _ctrl.hud.has_method("_refresh_p1_ui"):
		_ctrl.hud._refresh_p1_ui()
