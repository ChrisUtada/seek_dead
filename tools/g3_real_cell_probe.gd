extends Node

# ============================================================================
# G3-1 原型探针：档位模型 vs 一格一权重模型（2026-11-20）
#
# 目的（权威方案 §5.2 / G3-1）：制作"一格一权重"原型并与当前档位模型对照，
# 回答两个问题：① 整数化会不会让总带长/占比大幅波动？② 档位模型的"改造触顶"是否真实存在？
#
# 🔴 只读探针：不修改任何正式代码、不写存档。两种模型都是本地纯函数计算。
# 运行：Godot --headless --fixed-fps 60 --path . res://tools/g3_real_cell_probe.tscn
# 产物：res://.workbuddy/g3_real_cell_probe/baseline.json + 控制台摘要
# ============================================================================

const OUT_DIR := "res://.workbuddy/g3_real_cell_probe"

# 当前正式模型（与 ReelSystem.cells_for 完全一致）
static func tier_cells(w: float) -> int:
	if w >= 4.0:
		return 4
	if w >= 2.0:
		return 3
	return 2

# G3 真实格数原型：整数权重直接 = 格数，每符号上限 MAX_CELLS。
# 取整权重：符号资源里的 float 权重（多为 1.0/2.0/3.0）直接 round。
const MAX_CELLS := 8
static func real_cells(w: float, bonus: int = 0) -> int:
	return clampi(int(round(maxf(0.0, w))) + bonus, 0, MAX_CELLS)


func _ready() -> void:
	await get_tree().process_frame
	var scene_res: PackedScene = load("res://scenes/duel/duel.tscn")
	var duel = scene_res.instantiate()
	add_child(duel)
	await get_tree().process_frame
	await get_tree().process_frame
	duel._confirm_loadout()
	await get_tree().process_frame

	var agg := _aggregate(duel.pool_items)
	var rows: Array = []
	var tier_total := 0
	var real_total := 0
	for k in agg:
		var d: Dictionary = agg[k]
		var w: float = float(d["w"])
		var tc: int = tier_cells(w)
		var rc: int = real_cells(w)
		tier_total += tc
		real_total += rc
		rows.append({
			"key": k, "name": String(d["sym"].name), "w": w,
			"tier_cells": tc, "real_cells": rc,
		})
	rows.sort_custom(func(a, b): return float(a["w"]) > float(b["w"]))

	# 改造触顶对照：对权重最低的符号连续灌注（模拟 +1 权重/次），看多少格后触顶
	var probe_key: String = String(rows[rows.size() - 1]["key"]) if not rows.is_empty() else ""
	var probe_w: float = float(rows[rows.size() - 1]["w"]) if not rows.is_empty() else 0.0
	var tier_seq: Array = []
	var real_seq: Array = []
	for i in range(8):
		tier_seq.append(tier_cells(probe_w + float(i)))
		real_seq.append(real_cells(probe_w, i))

	var summary := {
		"baseline": "3f1a366", "date": "2026-11-20",
		"tier_total_cells": tier_total, "real_total_cells": real_total,
		"tier_to_real_ratio": (float(real_total) / float(tier_total)) if tier_total > 0 else 0.0,
		"symbols": rows,
		"pour_probe": {
			"symbol": probe_key, "base_w": probe_w,
			"tier_cells_per_pour": tier_seq, "real_cells_per_pour": real_seq,
			"tier_saturates_at_pour": _first_plateau(tier_seq),
			"real_saturates_at_pour": _first_plateau(real_seq),
		},
	}
	_write_json(summary)
	_print_summary(summary)
	get_tree().quit(0)


# 按 (sym_path|elem) 聚合权重，与 ReelSystem.build_strips 口径一致
func _aggregate(items: Array) -> Dictionary:
	var agg := {}
	for it in items:
		if not (it is Dictionary):
			continue
		for s in it.get("syms", []):
			if not (s is Array) or s.is_empty():
				continue
			var sym = s[0]
			if sym == null:
				continue
			var w: float = maxf(0.0, float(s[1]))
			if w <= 0.0:
				continue
			var key: String = String(sym.resource_path) + "|" + String(s[2])
			if not agg.has(key):
				agg[key] = {"sym": sym, "elem": s[2], "w": 0.0}
			agg[key]["w"] += w
	return agg


func _first_plateau(seq: Array) -> int:
	if seq.size() < 2:
		return -1
	for i in range(1, seq.size()):
		if int(seq[i]) == int(seq[i - 1]):
			return i - 1
	return -1


func _write_json(data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT_DIR + "/baseline.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "  "))
		f.close()


func _print_summary(s: Dictionary) -> void:
	print("=== G3-1 档位 vs 真实格数 ===")
	print("总格数: 档位=%d 真实=%d (比值 %.2f)" % [
		int(s["tier_total_cells"]), int(s["real_total_cells"]), float(s["tier_to_real_ratio"])])
	print("符号权重TOP:")
	for r in (s["symbols"] as Array).slice(0, 6):
		var d: Dictionary = r
		print("  %-18s w=%.1f 档位=%d 真实=%d" % [
			String(d["name"]).substr(0, 18), float(d["w"]), int(d["tier_cells"]), int(d["real_cells"])])
	var pp: Dictionary = s["pour_probe"]
	print("灌注序列(%s w=%.1f):" % [String(pp["symbol"]).get_file().get_basename(), float(pp["base_w"])])
	print("  档位: %s → 饱和于第%s次" % [str(pp["tier_cells_per_pour"]), str(pp["tier_saturates_at_pour"])])
	print("  真实: %s → 饱和于第%s次" % [str(pp["real_cells_per_pour"]), str(pp["real_saturates_at_pour"])])
	print("PROBE G3-1 DONE")
