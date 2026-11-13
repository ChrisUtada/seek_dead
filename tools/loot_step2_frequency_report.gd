extends SceneTree

# ============================================================================
# 四级品质战利品 · Step 2 · 品质/频率解耦前后对照（只读数据，不启动战斗）
#
# 运行：
#   Godot_v4.7-stable_win64_console.exe --headless --path . \
#     --script res://tools/loot_step2_frequency_report.gd
#
# 口径：
#   - 旧规则：非 damage 的 rare/epic 符号，单源（该符号只有这一件装备携带）封顶 2 格；
#   - 新规则：格数只看聚合权重（<2 → 2 格，[2,4) → 3 格，≥4 → 4 格）；
#   - 本表按「单件装备单独携带该符号」列出受旧封顶影响的行；
#     多件装备共享同一符号时旧规则本来就不封顶，不在此表内。
#
# 产物只写到 stdout，由调用方重定向到 docs/baseline/...；不写存档、不改资源。
# ============================================================================

const DIRS := ["res://resources/weapon_templates", "res://resources/skills"]


func _initialize() -> void:
	var rows: Array = []
	var scanned := 0
	var non_damage := 0
	for dir in DIRS:
		for f in _tres_files(String(dir)):
			var res: Resource = load(f)
			if res == null:
				continue
			scanned += 1
			var rarity := String(res.get("rarity")) if res.get("rarity") != null else "common"
			for e in _symbol_entries(res):
				var sym: Resource = e[0]
				var weight := float(e[1])
				if sym == null or weight <= 0.0:
					continue
				var kind := String(sym.get("kind"))
				if kind == "damage":
					continue
				non_damage += 1
				var new_cells := _cells(weight)
				var old_cells := new_cells
				if (rarity == "rare" or rarity == "epic") and new_cells > 2:
					old_cells = 2
				if old_cells == new_cells:
					continue
				rows.append({
					"item": String(res.get("weapon_name")) if res.get("weapon_name") != null else String(res.get("buff_name")),
					"path": f,
					"rarity": rarity,
					"kind": kind,
					"symbol": String(sym.get("name")),
					"weight": weight,
					"old": old_cells,
					"new": new_cells,
				})
	rows.sort_custom(func(a, b):
		if int(a["new"]) != int(b["new"]):
			return int(a["new"]) > int(b["new"])
		if float(a["weight"]) != float(b["weight"]):
			return float(a["weight"]) > float(b["weight"])
		return String(a["item"]) < String(b["item"]))

	print("# Step 2 品质/频率解耦 · 受旧「rare/epic 非伤害符号封顶 2 格」影响的行")
	print("")
	print("- 扫描资源：%d 件（武器 %d / 技能 %d）" % [scanned, _count(DIRS[0]), _count(DIRS[1])])
	print("- 非伤害符号条目：%d" % non_damage)
	print("- 受影响（旧封顶移除后格数增加）：%d 行" % rows.size())
	print("")
	print("| 物品 | 品质 | 符号 | 类型 | 权重 | 旧格数 | 新格数 | Δ |")
	print("|---|---|---|---|---:|---:|---:|---:|")
	for r in rows:
		print("| %s | %s | %s | %s | %.1f | %d | %d | %+d |" % [
			r["item"], r["rarity"], r["symbol"], r["kind"], r["weight"],
			r["old"], r["new"], int(r["new"]) - int(r["old"])])
	print("")
	# 按符号聚合，便于看“哪些符号整体变频繁”
	var by_sym := {}
	for r in rows:
		var k := String(r["symbol"]) + "|" + String(r["kind"])
		if not by_sym.has(k):
			by_sym[k] = {"symbol": r["symbol"], "kind": r["kind"], "items": 0, "max_delta": 0}
		by_sym[k]["items"] = int(by_sym[k]["items"]) + 1
		by_sym[k]["max_delta"] = maxi(int(by_sym[k]["max_delta"]), int(r["new"]) - int(r["old"]))
	print("## 按符号聚合")
	print("")
	print("| 符号 | 类型 | 受影响物品数 | 最大 Δ格 |")
	print("|---|---|---:|---:|")
	var keys: Array = by_sym.keys()
	keys.sort_custom(func(a, b): return int(by_sym[a]["max_delta"]) > int(by_sym[b]["max_delta"]))
	for k in keys:
		var g: Dictionary = by_sym[k]
		print("| %s | %s | %d | +%d |" % [g["symbol"], g["kind"], g["items"], g["max_delta"]])
	quit(0)


func _tres_files(dir_path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not d.current_is_dir() and n.ends_with(".tres"):
			out.append(dir_path + "/" + n)
		n = d.get_next()
	d.list_dir_end()
	return out


func _count(dir_path: String) -> int:
	return _tres_files(dir_path).size()


# 武器：symbols 数组（SymbolWeight → symbol/weight）；技能：单体 symbol/weight。
func _symbol_entries(res: Resource) -> Array:
	var out: Array = []
	var arr: Variant = res.get("symbols")
	if arr is Array:
		for sw in arr:
			if sw != null and sw.get("symbol") != null:
				out.append([sw.get("symbol"), sw.get("weight")])
		return out
	if res.get("symbol") != null:
		out.append([res.get("symbol"), res.get("weight")])
	return out


func _cells(w: float) -> int:
	if w >= 4.0:
		return 4
	if w >= 2.0:
		return 3
	return 2
