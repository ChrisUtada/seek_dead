extends Node

# ============================================================================
# G8 导出后资源扫描（方案 §16.2-12 / 工程铁律9）
# 关键：必须用 ResourceLoader.list_directory，禁 DirAccess.get_files（导出后只返回 .gd/.import，扫出空）
# 运行（扫描导出包）：
#   Godot_v4.7-stable_win64.exe --headless --main-pack "Seek Dead Prototype.pck" res://tools/export_resource_scan.tscn
# 运行（编辑器基线对照）：
#   Godot_v4.7-stable_win64.exe --headless --path . res://tools/export_resource_scan.tscn
# 输出前缀 RES_SCAN|，末尾 RES_SCAN|RESULT。
# ============================================================================

const DIRS := [
	"res://resources/weapon_templates/",
	"res://resources/symbols/",
	"res://resources/charms/",
	"res://resources/skills/",
	"res://resources/rooms/",
	"res://resources/patterns/",
	"res://resources/rewards/",
]

# 编辑器基线（2026-11-20 统计；导出包不得低于此值）
const BASELINE := {
	"res://resources/weapon_templates/": 90,
	"res://resources/symbols/": 80,
	"res://resources/charms/": 43,
	"res://resources/skills/": 42,
	"res://resources/rooms/": 61,
	"res://resources/patterns/": 21,
	"res://resources/rewards/": 9,
}

var _fails := 0


func _ready() -> void:
	await get_tree().process_frame
	# 判断模式：导出包里 .gd 源码被编译，路径不存在；编辑器里有源码
	var has_source := ResourceLoader.exists("res://scripts/battle/duel_controller.gd")
	print("RES_SCAN|MODE|%s|source_script=%s" % ["export" if not has_source else "editor", str(has_source)])
	var total := 0
	for d in DIRS:
		var files := ResourceLoader.list_directory(d)
		var tres_count := 0
		for f in files:
			if String(f).ends_with(".tres"):
				tres_count += 1
		total += tres_count
		var base: int = int(BASELINE.get(d, 0))
		var ok: bool = tres_count >= base
		if not ok:
			_fails += 1
		print("RES_SCAN|%s|%d(基线%d)|%s" % [d, tres_count, base, "OK" if ok else "FAIL"])
	# 抽查关键单个资源可读
	var probes := [
		"res://resources/weapon_templates/fire_sword.tres",
		"res://resources/rooms/frozen_urn.tres",
		"res://resources/symbols/fire_slash.tres",
	]
	for p in probes:
		var exists := ResourceLoader.exists(p) and load(p) != null
		if not exists:
			_fails += 1
		print("RES_SCAN|PROBE|%s|%s" % [p, "OK" if exists else "FAIL"])
	print("RES_SCAN|RESULT|total=%d|fails=%d" % [total, _fails])
	get_tree().quit(1 if _fails > 0 else 0)
