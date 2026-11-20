extends Node

# ============================================================================
# S0 跨局 run JSON 只读汇总器（第二阶段 S0，2026-11-20）
# 运行：Godot --headless --path . res://tools/s0_run_aggregator.tscn
# 可选命令行 user args（-- 之后）：
#   --runs=<目录>     输入 runs 目录（默认 user://runs）
#   --out=<目录>      输出目录（默认 user://runs/summary）
#   --appdata=<路径>  仅文档用途；实际路径由 Godot APPDATA 环境变量决定
#
# 设计口径（G0 追踪 §3.18）：
# - 唯一落盘真源 = run_journal 的逐局 run_*.json；本工具只读，不改任何单局文件。
# - 按 run_id（started_at + 文件名）去重；兼容 schema 版本；坏文件跳过并记录。
# - 缺失字段补默认（旧 11-08 样本缺 weapon_acquires/assist/stop_kinds 等）。
# - 输出 Markdown 策划摘要 + CSV 明细；可重复生成、可随时重建。
# 输出前缀 S0AGG|，末尾 S0AGG|RESULT。
# ============================================================================

const DEFAULT_RUNS_DIR := "user://runs"
const DEFAULT_OUT_DIR := "user://runs/summary"

var _runs_dir := DEFAULT_RUNS_DIR
var _out_dir := DEFAULT_OUT_DIR
var _warnings: Array[String] = []


func _ready() -> void:
	_parse_args()
	var ok := _run()
	print("S0AGG|RESULT %s (warnings=%d)" % ["OK" if ok else "FAIL", _warnings.size()])
	get_tree().quit(0 if ok else 1)


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var s := String(arg)
		if s.begins_with("--runs="):
			_runs_dir = s.substr(7)
		elif s.begins_with("--out="):
			_out_dir = s.substr(6)


# ---------- 主流程 ----------

func _run() -> bool:
	var files := _list_run_files(_runs_dir)
	if files.is_empty():
		print("S0AGG|no run json found in %s" % _runs_dir)
		# 空目录仍产出空汇总（可重复生成），不算失败
		return _write_outputs([], {})

	var records: Array = []
	var seen := {}
	for f in files:
		var d := _read_json(_runs_dir + "/" + f)
		if d.is_empty():
			_warnings.append("bad_json:" + f)
			continue
		var run_id := _run_id(d, f)
		if run_id.is_empty():
			_warnings.append("no_run_id:" + f)
			continue
		if seen.has(run_id):
			_warnings.append("duplicate:%s(%s)" % [run_id, f])
			continue
		seen[run_id] = true
		records.append(_normalize(d, run_id, f))
	records.sort_custom(func(a, b): return String(a["run_id"]) < String(b["run_id"]))
	return _write_outputs(records, _aggregate(records))


func _list_run_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".json") and not name.begins_with("."):
			out.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


func _run_id(d: Dictionary, file_name: String) -> String:
	var started := String(d.get("started_at", ""))
	return started if not started.is_empty() else file_name.get_basename()


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return {}
	return json.data


# 缺字段补默认：旧样本缺 weapon_acquires/assist/stop_kinds 等，统一填 0/空。
func _normalize(d: Dictionary, run_id: String, file_name: String) -> Dictionary:
	var tel: Variant = d.get("telemetry", {})
	if not (tel is Dictionary):
		tel = {}
	var loadout_end: Variant = d.get("loadout_end", [])
	if not (loadout_end is Array):
		loadout_end = []
	var weapon_changes: Variant = d.get("weapon_changes", [])
	if not (weapon_changes is Array):
		weapon_changes = []
	var result := String(d.get("result", "unknown"))
	var schema := int(d.get("schema", 0))
	var pick_rate := float(tel.get("reward_pick_rate", 0.0))
	# 版本兼容：旧 schema(<=1) 的 reward_pick_rate 是"选择次数"整数（如 7.0），非 0-1 比例。
	# 值域 >1 即判为旧格式，不纳入比例统计，并在告警中标注，避免汇总出 170% 这类失真值。
	if pick_rate > 1.0:
		_warnings.append("legacy_pick_rate:%s(%.1f)" % [run_id, pick_rate])
		pick_rate = 0.0
	return {
		"run_id": run_id,
		"file": file_name,
		"schema": schema,
		"mode": String(d.get("mode", "")),
		"result": result,
		"win": result == "clear",
		"started_at": String(d.get("started_at", "")),
		"ended_at": String(d.get("ended_at", "")),
		"duration_sec": float(d.get("duration_sec", 0.0)),
		"act": int(d.get("act", 0)),
		"nodes_total": int(d.get("nodes_total", 0)),
		"nodes_visited": int(d.get("nodes_visited", 0)),
		"loadout_start": _str_array(d.get("loadout_start", [])),
		"loadout_end": _str_array(loadout_end),
		"weapon_change_count": weapon_changes.size(),
		"turns": int(tel.get("turns", 0)),
		"triples": int(tel.get("triples", 0)),
		"spins": int(tel.get("spins", 0)),
		"avg_ttk": float(tel.get("avg_ttk", 0.0)),
		"damage_taken": int(tel.get("damage_taken", 0)),
		"weapon_swaps": int(tel.get("weapon_swaps", 0)),
		"weapon_acquires": int(tel.get("weapon_acquires", 0)),
		"weapon_swaps_draft": int(tel.get("weapon_swaps_draft", 0)),
		"rewards_shown": int(tel.get("rewards_shown", 0)),
		"reward_pick_rate": pick_rate,
		"target_hit_rate": float(tel.get("target_hit_rate", 0.0)),
		"stop_total": int(tel.get("stop_total", 0)),
		"assist_sources": _dict_keys(tel.get("assist", {})),
	}


func _str_array(v) -> Array[String]:
	var out: Array[String] = []
	if v is Array:
		for x in v:
			out.append(String(x))
	return out


func _dict_keys(v) -> Array[String]:
	var out: Array[String] = []
	if v is Dictionary:
		for k in v:
			out.append(String(k))
	out.sort()
	return out


# ---------- 聚合 ----------

func _aggregate(records: Array) -> Dictionary:
	var n := records.size()
	var wins := 0
	var duration := 0.0
	var swaps := 0
	var acquires := 0
	var swaps_draft := 0
	var rewards_shown := 0
	var pick_rate := 0.0
	var target_rate := 0.0
	var ttk := 0.0
	var weapon_use := {}       # 武器名 -> 使用局数（出现于 loadout_start/end）
	var change_total := 0
	var result_count := {}
	var assist_count := {}
	for r in records:
		if bool(r["win"]):
			wins += 1
		duration += float(r["duration_sec"])
		swaps += int(r["weapon_swaps"])
		acquires += int(r["weapon_acquires"])
		swaps_draft += int(r["weapon_swaps_draft"])
		rewards_shown += int(r["rewards_shown"])
		pick_rate += float(r["reward_pick_rate"])
		target_rate += float(r["target_hit_rate"])
		ttk += float(r["avg_ttk"])
		change_total += int(r["weapon_change_count"])
		var rc := String(r["result"])
		result_count[rc] = int(result_count.get(rc, 0)) + 1
		for w in r["loadout_start"]:
			weapon_use[w] = int(weapon_use.get(w, 0)) + 1
		for w in r["loadout_end"]:
			weapon_use[w] = int(weapon_use.get(w, 0)) + 1
		for a in r["assist_sources"]:
			assist_count[a] = int(assist_count.get(a, 0)) + 1
	var avg := func(total: float) -> float:
		return total / float(n) if n > 0 else 0.0
	return {
		"runs": n,
		"wins": wins,
		"win_rate": float(wins) / float(n) if n > 0 else 0.0,
		"avg_duration_sec": avg.call(duration),
		"avg_ttk": avg.call(ttk),
		"total_weapon_swaps": swaps,
		"total_weapon_acquires": acquires,
		"total_weapon_swaps_draft": swaps_draft,
		"avg_weapon_changes": avg.call(float(change_total)),
		"avg_rewards_shown": avg.call(float(rewards_shown)),
		"avg_reward_pick_rate": avg.call(pick_rate),
		"avg_target_hit_rate": avg.call(target_rate),
		"result_count": result_count,
		"weapon_use": weapon_use,
		"assist_count": assist_count,
	}


# ---------- 输出 ----------

func _write_outputs(records: Array, agg: Dictionary) -> bool:
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("S0AGG: 无法创建输出目录 %s (err=%d)" % [_out_dir, err])
		return false
	var md_path := _out_dir + "/summary.md"
	var csv_path := _out_dir + "/runs.csv"
	var md := _markdown(records, agg)
	var csv := _csv(records)
	if not _write_text(md_path, md) or not _write_text(csv_path, csv):
		return false
	print("S0AGG|md=%s" % ProjectSettings.globalize_path(md_path))
	print("S0AGG|csv=%s" % ProjectSettings.globalize_path(csv_path))
	return true


func _write_text(path: String, content: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("S0AGG: 无法写入 %s" % path)
		return false
	f.store_string(content)
	f.close()
	return true


func _pct(v: float) -> String:
	return "%.1f%%" % (v * 100.0)


func _markdown(records: Array, agg: Dictionary) -> String:
	var s := "# S0 跨局数据汇总（自动生成的 Markdown 摘要）\n\n"
	s += "> 数据源：run_journal 逐局 JSON（唯一真源）；本文件由只读工具生成，可随时重建。\n"
	s += "> 生成时间：%s；样本数：%d\n\n" % [Time.get_datetime_string_from_system(), int(agg.get("runs", 0))]
	s += "## 核心指标\n\n"
	s += "| 指标 | 值 |\n|---|---|\n"
	s += "| 通关率 | %s（%d/%d） |\n" % [_pct(float(agg.get("win_rate", 0.0))), int(agg.get("wins", 0)), int(agg.get("runs", 0))]
	s += "| 平均单局时长 | %.1f 秒 |\n" % float(agg.get("avg_duration_sec", 0.0))
	s += "| 平均清房 TTK | %.1f 秒 |\n" % float(agg.get("avg_ttk", 0.0))
	s += "| 平均奖励选择率 | %s |\n" % _pct(float(agg.get("avg_reward_pick_rate", 0.0)))
	s += "| 平均目标停中率 | %s |\n" % _pct(float(agg.get("avg_target_hit_rate", 0.0)))
	s += "| 武器获取 / 换装（本局仓库）合计 | %d / %d |\n" % [
		int(agg.get("total_weapon_acquires", 0)), int(agg.get("total_weapon_swaps_draft", 0))]
	s += "| 武器替换（奖励/BOSS/商店）合计 | %d |\n" % int(agg.get("total_weapon_swaps", 0))
	s += "| 平均换武次数/局 | %.2f |\n" % float(agg.get("avg_weapon_changes", 0.0))
	s += "\n## 结果分布\n\n"
	var rc: Dictionary = agg.get("result_count", {})
	for k in rc:
		s += "- %s：%d 局\n" % [String(k), int(rc[k])]
	s += "\n## 武器使用（出现于开局或结算配装，局数）\n\n"
	var wu: Dictionary = agg.get("weapon_use", {})
	var keys := wu.keys()
	keys.sort_custom(func(a, b): return int(wu[a]) > int(wu[b]))
	for k in keys:
		s += "- %s：%d\n" % [String(k), int(wu[k])]
	if not _warnings.is_empty():
		s += "\n## 数据质量告警\n\n"
		for w in _warnings:
			s += "- %s\n" % w
	s += "\n## 单局明细\n\n"
	s += "| run_id | 结果 | 时长s | 换武 | 获取 | 奖励选择率 | 停中率 |\n|---|---|---:|---:|---:|---:|---:|\n"
	for r in records:
		s += "| %s | %s | %.1f | %d | %d | %s | %s |\n" % [
			String(r["run_id"]), String(r["result"]), float(r["duration_sec"]),
			int(r["weapon_swaps"]), int(r["weapon_acquires"]),
			_pct(float(r["reward_pick_rate"])), _pct(float(r["target_hit_rate"]))]
	return s


func _csv(records: Array) -> String:
	var cols := ["run_id", "file", "schema", "mode", "result", "started_at", "ended_at",
		"duration_sec", "act", "nodes_total", "nodes_visited", "weapon_change_count",
		"turns", "triples", "spins", "avg_ttk", "damage_taken", "weapon_swaps",
		"weapon_acquires", "weapon_swaps_draft", "rewards_shown", "reward_pick_rate",
		"target_hit_rate", "stop_total", "loadout_start", "loadout_end", "assist_sources"]
	var lines: Array[String] = [",".join(cols)]
	for r in records:
		var row: Array[String] = []
		for c in cols:
			row.append(_csv_cell(r.get(c)))
		lines.append(",".join(row))
	return "\n".join(lines) + "\n"


func _csv_cell(v) -> String:
	if v == null:
		return ""
	if v is Array:
		var parts: Array[String] = []
		for x in v:
			parts.append(str(x).replace(";", "/"))
		return "\"" + ";".join(parts) + "\""
	var s := str(v)
	if s.find(",") >= 0 or s.find("\"") >= 0 or s.find("\n") >= 0:
		return "\"" + s.replace("\"", "\"\"") + "\""
	return s
