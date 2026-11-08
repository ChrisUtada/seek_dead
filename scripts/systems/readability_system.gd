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

const PRESETS := {
	"control":  {"base": 0.15, "min": 0.06,  "accel": 0.0010, "preview": 0, "visual": false, "buffer": false, "feedback": false},
	"readable": {"base": 0.15, "min": 0.085, "accel": 0.0007, "preview": 2, "visual": true,  "buffer": true,  "feedback": true},
	"speed":    {"base": 0.15, "min": 0.085, "accel": 0.0007, "preview": 0, "visual": false, "buffer": false, "feedback": false},
	"preview":  {"base": 0.15, "min": 0.06,  "accel": 0.0010, "preview": 2, "visual": false, "buffer": false, "feedback": false},
	"visual":   {"base": 0.15, "min": 0.06,  "accel": 0.0010, "preview": 0, "visual": true,  "buffer": false, "feedback": false},
	"buffer":   {"base": 0.15, "min": 0.06,  "accel": 0.0010, "preview": 0, "visual": true,  "buffer": true,  "feedback": false},
	"feedback": {"base": 0.15, "min": 0.06,  "accel": 0.0010, "preview": 0, "visual": false, "buffer": false, "feedback": true},
}
const CYCLE := ["control", "readable"]

var _ctrl
var preset := "control"
var base_wait := 0.15
var min_wait := 0.06
var accel := 0.0010
var preview_slots := 0
var visual_stop := false
var buffer_enabled := false
var feedback_enabled := false
var steady_hand_used := false    # G7-A S1「稳手」：本回合那一次额外缓冲是否已用掉

var target_symbol_path := ""
var target_reason := "输出窗口"
var target_detail := "优先停中主武器的高权重攻击符号。"
var _forced_target := ""

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
	if is_equal_approx(accel, 0.0010) and is_equal_approx(min_wait, 0.06):
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
	if _ctrl._telemetry != null:
		_ctrl._telemetry.on_stop(path, target_symbol_path, outcome, reason != "player")


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


# 每个真实玩家回合更新一次建议目标；只改变信息与遥测目标，不改变停轮或伤害规则。
func update_turn_target() -> void:
	if _forced_target != "":
		_set_target(_forced_target, "指定目标", "命令行指定的固定对照目标。")
		return
	var intent: Dictionary = _ctrl.enemy_intent
	var intent_type := String(intent.get("type", "none"))
	var intent_value := int(intent.get("value", 0))
	if intent_type == "heavy":
		var shield := _first_symbol_of_kind("shield")
		if shield != "":
			_set_target(shield, "重击·先护盾", "敌人预告重击 %d；优先停中护盾符号，保留其他列的输出选择。" % intent_value)
			return
		var heal := _first_symbol_of_kind("heal")
		if heal != "" and _ctrl.player_hp < _ctrl.player_hp_max:
			_set_target(heal, "重击·先恢复", "当前带内没有护盾符号；敌人预告重击 %d，可用治疗或消耗品降低风险。" % intent_value)
			return
	if _ctrl.player_hp <= int(_ctrl.player_hp_max * 0.4):
		var heal := _first_symbol_of_kind("heal")
		if heal != "":
			_set_target(heal, "低血·先恢复", "当前 HP %d/%d；优先恢复，也可根据意图继续抢攻。" % [_ctrl.player_hp, _ctrl.player_hp_max])
			return
	var recovery: bool = _ctrl.current_gimmick != null and _ctrl.current_gimmick.recovery_window(_ctrl)
	if recovery:
		if _ctrl.enemy_armor > 0:
			var special := _first_symbol_of_kind("special")
			if special != "":
				_set_target(special, "间隙·破甲", "本回合不会新增叠甲/冻结；争取三连破甲，随后集中输出。")
				return
		_set_target(_default_target(), "间隙·输出", "本回合不会新增叠甲/冻结；集中输出，避免拖入下一次加压。")
		return
	if _ctrl.enemy_armor > 0:
		var special := _first_symbol_of_kind("special")
		if special != "":
			_set_target(special, "高甲·破甲", "敌人当前护甲 %d；带内存在特殊符号，可争取三连破甲。" % int(_ctrl.enemy_armor))
			return
	var interfered: bool = _ctrl.pending_jam_reel >= 0 or _ctrl.pending_lock_reel >= 0 or _ctrl.pending_chaos or _ctrl.pending_auto_stop
	var data: IntentData = intent.get("data")
	interfered = interfered or (data != null and data.purifiable)
	if interfered:
		_set_target(_default_target(), "干扰·输出/净化", "转轮将受到干扰；可继续输出，也可按既有规则使用净化/清净消耗品。")
		return
	if _ctrl.enemy_hp > 0 and _ctrl.enemy_hp <= int(_ctrl.enemy_hp_max * 0.25):
		_set_target(_default_target(), "残血·收尾", "敌人 HP 较低；优先集中输出，减少无决策价值的残血回合。")
		return
	_set_target(_default_target(), "输出窗口", "当前没有更紧迫的防御或破甲需求；优先主武器高权重攻击符号。")


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
