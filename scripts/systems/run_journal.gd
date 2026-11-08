extends RefCounted

# G5 工具：局内自动记录（2026-11-08）
#
# 目的：替代手填记录表的客观部分——边玩边记，局末生成 JSON + 预填 TXT。
# 边界：
# - 只读状态，不写存档（lobby_data）、不改数值/奖励/掉落/RNG、不弹任何界面。
# - 仅导出包（自定义特性 act1_demo）或命令行带 --runlog 时落盘；测试/编辑器默认只在内存累计。
# - 主观项（手感、选路理由等）按项目约定不记录：有问题由作者直接口头反馈。
#
# 产物目录：user://runs/（Windows: %APPDATA%\Godot\app_userdata\Seek Dead Prototype\runs）
#   run_YYYY-MM-DDTHH-MM-SS.json  结构化数据（供汇总脚本）
#   run_YYYY-MM-DDTHH-MM-SS.txt   预填的记录表（客观项已填）

const SCHEMA := 1
const OUT_DIR := "user://runs"
const SPECIAL_TYPES := ["treasure", "shrine", "armory"]
const RUN_SUMMARY := preload("res://scripts/systems/run_summary.gd")
const KIND_LABEL := {"normal": "普通", "elite": "精英", "boss": "BOSS"}

var _ctrl
var _active := false
var _finished := false
var _data: Dictionary = {}
var _started_ms := 0
var _board_shown_ms := -1
var _first_pick_open := false
var _pending_battle: Dictionary = {}
var _json_path := ""
var _txt_path := ""


func _init(ctrl) -> void:
	_ctrl = ctrl


func is_active() -> bool:
	return _active


func reset() -> void:
	_active = false
	_finished = false
	_data = {}
	_started_ms = 0
	_board_shown_ms = -1
	_first_pick_open = false
	_pending_battle = {}
	_json_path = ""
	_txt_path = ""


# 新一局开始（full_reset 完成棋盘生成 / 线性房间构建后调用）。
func start_run() -> void:
	reset()
	_active = true
	_started_ms = Time.get_ticks_msec()
	var size := DisplayServer.window_get_size()
	var mode := "board" if _is_board() else "linear"
	_data = {
		"schema": SCHEMA,
		"mode": mode,
		"started_at": Time.get_datetime_string_from_system(),
		"act": int(_ctrl.current_act),
		"acts": [],
		"resolution": "%dx%d" % [size.x, size.y],
		"loadout_start": _loadout_names(),
		"route": [],
		"battles": [],
		"growth": [],
		"weapon_changes": [],
		"shop": [],
		"camp": [],
		"consumables": [],
		"special": [],
		"first_pick": {},
	}
	if _is_board():
		var b = _ctrl.board
		_data["board"] = {
			"shape": String(b.shape_id),
			"template": String(b.template_id),
			"nodes": b.node_count(),
			"cells": b.route_length(),
		}
		# G7-A S4：按幕分段——第一幕先记一条，幕间由 note_act_start 续上。
		_data["acts"].append(_act_entry(b.summary()))
		# 起点也计入路线（与 board.visited_count() 口径一致：起点在生成时即已消耗）
		_data["route"].append({"id": String(b.current_id), "type": "start", "depth": 0, "act": int(b.act)})
	_stamp_paths()
	_flush()


# 棋盘首次展示：10 秒找落点的计时起点（只在每局第一次展示时启动）。
func note_board_shown() -> void:
	if not _active or _board_shown_ms >= 0:
		return
	_board_shown_ms = Time.get_ticks_msec()
	_first_pick_open = true


# 一次落点选择（玩家点击，不含唯一去路的自动前进）。
func note_first_pick(node_id: String) -> void:
	if not _first_pick_open or _board_shown_ms < 0:
		return
	_first_pick_open = false
	_data["first_pick"] = {
		"seconds": snappedf(float(Time.get_ticks_msec() - _board_shown_ms) / 1000.0, 0.1),
		"node": node_id,
	}


# 幕间推进（G7-A S4）：收口上一幕的 BOSS 名，开始记录新一幕的棋盘参数。
func note_act_start(act: int, summary: Dictionary = {}, prev: Dictionary = {}) -> void:
	if not _active:
		return
	if not prev.is_empty() and not _data["acts"].is_empty():
		var last: Dictionary = _data["acts"][-1]
		last["boss"] = String(prev.get("boss", ""))
	_data["act"] = int(act)
	_data["acts"].append(_act_entry(summary))
	_flush()


func _act_entry(summary: Dictionary) -> Dictionary:
	return {
		"act": int(summary.get("act", _ctrl.current_act)),
		"shape": String(summary.get("shape", "")),
		"template": String(summary.get("template", "")),
		"boss": String(summary.get("boss", "")),
		"nodes": int(summary.get("nodes", 0)),
		"cells": int(summary.get("cells", 0)),
	}


# 进入一个棋盘节点（路线记录；战斗节点的确认框不改变路线）。
func note_node(node: Dictionary) -> void:
	if not _active or node.is_empty():
		return
	var t := String(node.get("type", ""))
	var act: int = int(_ctrl.board.act) if _is_board() else int(_ctrl.current_act)
	_data["route"].append({"id": String(node.get("id", "")), "type": t,
		"depth": int(node.get("depth", 0)), "act": act})
	if t in SPECIAL_TYPES:
		_data["special"].append({"type": t, "node": String(node.get("id", "")), "outcome": ""})


# 战斗开始：记录房型/敌人与当前 HP；同一场重复调用以最后一次为准。
func note_battle_start(room: RoomData) -> void:
	if not _active or room == null:
		return
	_finalize_pending("win")   # 防御：上一场若未收到结算，不丢记录
	_pending_battle = {
		"seq": _data["battles"].size() + 1,
		"act": int(_ctrl.current_act),
		"kind": String(room.kind),
		"room": String(room.name),
		"element": String(room.element),
		"enemy_hp": int(_ctrl.enemy_hp_max),
		"enemy_atk": int(_ctrl.enemy_atk),
		"player_hp_start": int(_ctrl.player_hp),
		"turns": 0,
		"result": "",
	}
	if String(room.kind) == "boss":
		_data["final_boss"] = "%s（%s）" % [room.name, ElementCounter.label(room.element)]


# 战斗结束（胜利）。战败由 finish() 统一收口当前待结算战斗。
func note_battle_end(result: String = "win") -> void:
	_finalize_pending(result)


func note_growth(id: String, label: String) -> void:
	if not _active:
		return
	_data["growth"].append({"id": id, "name": label})


func note_weapon_change(from_name: String, to_name: String, source: String) -> void:
	if not _active:
		return
	_data["weapon_changes"].append({"from": from_name, "to": to_name, "source": source})


func note_shop(name: String, kind: String, price: int) -> void:
	if not _active:
		return
	_data["shop"].append({"name": name, "kind": kind, "price": price})


func note_camp(name: String, kind: String, price: int) -> void:
	if not _active:
		return
	_data["camp"].append({"name": name, "kind": kind, "price": price})


func note_consumable(name: String) -> void:
	if not _active:
		return
	_data["consumables"].append({"name": name})


# 特殊格结果（宝箱开出什么 / 神龛效果 / 藏库选择或跳过）。
func note_special(kind: String, outcome: String) -> void:
	if not _active:
		return
	for s in _data["special"]:
		if String(s.get("type", "")) == kind and String(s.get("outcome", "")) == "":
			s["outcome"] = outcome
			return
	_data["special"].append({"type": kind, "node": "", "outcome": outcome})


# 局末收口：通关（最终 BOSS）或战败都会走到这里（room_flow.log_telemetry）。
func finish() -> void:
	if not _active or _finished:
		return
	_finished = true
	var lost: bool = _ctrl.game_state == _ctrl.FlowState.LOST
	if lost:
		_finalize_pending("loss")
		var room: RoomData = _ctrl.current_room
		_data["death"] = {
			"node": String(_ctrl.board.current_id) if _is_board() and _ctrl.board != null else "",
			"room": String(room.name) if room != null else String(_ctrl.enemy_name),
			"kind": String(room.kind) if room != null else "",
			"hp": int(_ctrl.player_hp),
		}
	_data["result"] = "defeat" if lost else "clear"
	_data["ended_at"] = Time.get_datetime_string_from_system()
	_data["duration_sec"] = snappedf(float(Time.get_ticks_msec() - _started_ms) / 1000.0, 0.1)
	_data["loadout_end"] = _loadout_names()
	_data["battles_count"] = _data["battles"].size()
	# G7-A S4：三幕局的「总节点」= 各幕节点数之和（route 已跨幕累计）。
	var nodes_total := 0
	if _is_board() and _ctrl.board != null:
		for a in _data.get("acts", []):
			nodes_total += int(a.get("nodes", 0))
		if nodes_total <= 0:
			nodes_total = _ctrl.board.node_count()
	else:
		nodes_total = _ctrl.ROOMS.size()
	_data["nodes_total"] = nodes_total
	_data["nodes_visited"] = _data["route"].size() if _is_board() else _data["battles"].size()
	if _ctrl._telemetry != null:
		_data["telemetry"] = _ctrl._telemetry.summary()
	_write_files()
	if _file_logging():
		var abs_txt := ProjectSettings.globalize_path(_txt_path)
		print("RUNLOG|" + abs_txt)
		_ctrl.hud._log("📝 本局记录已写入：%s" % abs_txt)


func _finalize_pending(result: String) -> void:
	if _pending_battle.is_empty():
		return
	_pending_battle["result"] = result
	_pending_battle["turns"] = int(_ctrl.turn_count)
	_pending_battle["player_hp_end"] = int(_ctrl.player_hp)
	_data["battles"].append(_pending_battle)
	_pending_battle = {}
	_flush()


func _is_board() -> bool:
	return bool(_ctrl.node_mode) and _ctrl.board != null and bool(_ctrl.board.generated)


func _loadout_names() -> Array:
	var out: Array = []
	for p in _ctrl.selected_loadout:
		var wd: WeaponData = load(p)
		out.append(String(wd.weapon_name) if wd != null else String(p).get_file().get_basename())
	return out


func _file_logging() -> bool:
	return OS.has_feature("act1_demo") or OS.get_cmdline_user_args().has("--runlog")


func _stamp_paths() -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	if _is_board():
		stamp += "_" + String(_ctrl.board.shape_id)
	_json_path = "%s/run_%s.json" % [OUT_DIR, stamp]
	_txt_path = "%s/run_%s.txt" % [OUT_DIR, stamp]
	var n := 1
	while FileAccess.file_exists(_json_path):
		_json_path = "%s/run_%s_%d.json" % [OUT_DIR, stamp, n]
		_txt_path = "%s/run_%s_%d.txt" % [OUT_DIR, stamp, n]
		n += 1


func _flush() -> void:
	if not _active or _json_path == "" or not _file_logging():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f := FileAccess.open(_json_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_data, "\t"))
		f.close()


func _write_files() -> void:
	if not _file_logging():
		return
	_flush()
	var f := FileAccess.open(_txt_path, FileAccess.WRITE)
	if f != null:
		f.store_string(_record_text())
		f.close()


# 预填记录表：字段对齐 docs/G5_复测_执行清单与记录表_2026-11-08.md §3.1，
# 但只填客观项；主观问卷按约定由作者需要时口头反馈，不在此生成。
func _record_text() -> String:
	var lines: Array[String] = []
	lines.append("Seek Dead · ACT1 自动记录（局末生成，客观项自动填写）")
	lines.append("=========================================================")
	lines.append("开始：%s    结束：%s    时长：%.1f 分钟" % [
		String(_data.get("started_at", "")), String(_data.get("ended_at", "")),
		float(_data.get("duration_sec", 0.0)) / 60.0])
	lines.append("模式：%s    分辨率：%s    场次文件：%s" % [
		"棋盘" if String(_data.get("mode", "")) == "board" else "线性",
		String(_data.get("resolution", "")), _json_path.get_file()])
	lines.append("幕：%s" % _acts_text())
	lines.append("")
	lines.append("一、本局概况")
	lines.append("------------")
	if _is_board():
		var b: Dictionary = _data.get("board", {})
		var shape := String(b.get("shape", ""))
		var tpl := String(b.get("template", ""))
		lines.append("骨架：%s（%s / %d 节点 / %d 格）" % [
			String(RUN_SUMMARY.SHAPE_LABEL.get(shape, shape)), shape, int(b.get("nodes", 0)), int(b.get("cells", 0))])
		lines.append("模板：%s（%s）" % [String(RUN_SUMMARY.TEMPLATE_LABEL.get(tpl, tpl)), tpl])
	lines.append("最终 BOSS：%s" % String(_data.get("final_boss", "无")))
	lines.append("特殊格：%s" % _special_text())
	lines.append("战斗场次：%d" % int(_data.get("battles_count", 0)))
	lines.append("到达节点 / 总节点：%d / %d" % [int(_data.get("nodes_visited", 0)), int(_data.get("nodes_total", 0))])
	lines.append("结果：%s" % ("完整通关" if String(_data.get("result", "")) == "clear" else "战败"))
	var death: Dictionary = _data.get("death", {})
	if not death.is_empty():
		lines.append("死亡点：%s%s（HP %d）" % [String(death.get("room", "")), (" · " + String(death.get("node", "")) if String(death.get("node", "")) != "" else ""), int(death.get("hp", 0))])
	lines.append("")
	lines.append("二、路线（按顺序）")
	lines.append("------------------")
	var route: Array = _data.get("route", [])
	if route.is_empty():
		lines.append("线性模式：无棋盘路线")
	else:
		var last_act := -1
		for n in route:
			var a := int(n.get("act", 1))
			if a != last_act:
				lines.append(" [%s]" % Palette.act_name(a))
				last_act = a
			lines.append("  %s  %s  depth=%d" % [String(n.get("id", "")), String(n.get("type", "")), int(n.get("depth", 0))])
	lines.append("")
	lines.append("三、战斗")
	lines.append("--------")
	for b in _data.get("battles", []):
		lines.append("  #%d %s %s %s（%s） 结果=%s 回合=%d HP %d→%d" % [
			int(b.get("seq", 0)), Palette.act_name(int(b.get("act", 1))),
			String(KIND_LABEL.get(String(b.get("kind", "")), String(b.get("kind", "")))), String(b.get("room", "")),
			ElementCounter.label(String(b.get("element", "none"))), String(b.get("result", "")),
			int(b.get("turns", 0)), int(b.get("player_hp_start", 0)), int(b.get("player_hp_end", 0))])
	lines.append("")
	lines.append("四、成长与装备")
	lines.append("--------------")
	lines.append("成长选择：%s" % _join_names(_data.get("growth", [])))
	lines.append("武器组合：%s → %s" % [", ".join(_data.get("loadout_start", [])), ", ".join(_data.get("loadout_end", []))])
	lines.append("换武器（%d 次）：%s" % [_data.get("weapon_changes", []).size(), _weapon_change_text()])
	lines.append("商店购买：%s" % _shop_text(_data.get("shop", [])))
	lines.append("营地购买：%s" % _shop_text(_data.get("camp", [])))
	lines.append("消耗品使用：%s" % _join_names(_data.get("consumables", [])))
	lines.append("")
	lines.append("五、数据（来自现有遥测）")
	lines.append("------------------------")
	var t: Dictionary = _data.get("telemetry", {})
	lines.append("回合数：%d    三连：%d（%.0f%%）" % [int(t.get("turns", 0)), int(t.get("triples", 0)), float(t.get("triple_rate", 0.0)) * 100.0])
	lines.append("承伤：%d    格挡：%d    敌人出手：%d" % [int(t.get("damage_taken", 0)), int(t.get("damage_blocked", 0)), int(t.get("enemy_attacks", 0))])
	lines.append("平均 TTK：%.1f 秒    旋转：%d 次（均 %.2f 秒）" % [float(t.get("avg_ttk", 0.0)), int(t.get("spins", 0)), float(t.get("avg_spin", 0.0))])
	lines.append("目标停中：%d/%d（%.0f%%）    强制停轮：%d    缓冲：%d" % [
		int(t.get("target_hits", 0)), int(t.get("stop_total", 0)), float(t.get("target_hit_rate", 0.0)) * 100.0,
		int(t.get("forced_stops", 0)), int(t.get("buffer_queues", 0))])
	lines.append("")
	lines.append("六、10 秒找落点（首次点击）")
	lines.append("---------------------------")
	var fp: Dictionary = _data.get("first_pick", {})
	if fp.is_empty():
		lines.append("未记录（本局没有手动点击落点）")
	else:
		lines.append("用时：%.1f 秒    指向节点：%s" % [float(fp.get("seconds", 0.0)), String(fp.get("node", ""))])
	lines.append("")
	lines.append("注：主观项（手感、选路理由、是否想再玩）按约定不由本表记录。")
	return "\n".join(lines) + "\n"


# G7-A S4：幕概览（单幕时也明确写出来，避免与三幕记录混淆）。
func _acts_text() -> String:
	var arr: Array = _data.get("acts", [])
	if arr.is_empty():
		return "ACT I（单幕）"
	var out: Array[String] = []
	for a in arr:
		var bits: Array[String] = [Palette.act_name(int(a.get("act", 1)))]
		var shape := String(a.get("shape", ""))
		if shape != "":
			bits.append(String(RUN_SUMMARY.SHAPE_LABEL.get(shape, shape)))
		out.append(" ".join(bits))
	if out.size() <= 1:
		return "%s（单幕）" % out[0]
	return "%s（%d 幕）" % [" → ".join(out), out.size()]


func _special_text() -> String:
	var arr: Array = _data.get("special", [])
	if arr.is_empty():
		return "无"
	var out: Array[String] = []
	for s in arr:
		var o := String(s.get("outcome", ""))
		out.append("%s%s" % [_special_label(String(s.get("type", ""))), ("：" + o) if o != "" else ""])
	return " / ".join(out)


func _special_label(t: String) -> String:
	match t:
		"treasure": return "宝箱"
		"shrine": return "神龛"
		"armory": return "武器藏库"
	return t


func _join_names(arr: Array) -> String:
	if arr.is_empty():
		return "无"
	var out: Array[String] = []
	for it in arr:
		out.append(String(it.get("name", "")))
	return " / ".join(out)


func _shop_text(arr: Array) -> String:
	if arr.is_empty():
		return "无"
	var out: Array[String] = []
	for it in arr:
		out.append("%s(%d金)" % [String(it.get("name", "")), int(it.get("price", 0))])
	return " / ".join(out)


func _weapon_change_text() -> String:
	var arr: Array = _data.get("weapon_changes", [])
	if arr.is_empty():
		return "无"
	var out: Array[String] = []
	for it in arr:
		var f := String(it.get("from", ""))
		var t := String(it.get("to", ""))
		out.append(("%s → %s" % [f, t]) if f != "" else t)
	return " / ".join(out)
