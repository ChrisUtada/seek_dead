class_name ResourceScan
extends RefCounted

# Phase D 软注册表清理：用「扫描文件夹」替代手写路径数组。
# 加内容 = 在对应 resources/ 子目录放一个 .tres，无需改代码、不碰全局表。
#
# 2026-08-10 导出修复（官方最佳实践）：目录枚举从 DirAccess 改为 ResourceLoader.list_directory()。
# 依据 Godot 4.7 文档：导出构建中 DirAccess.get_files() 对 res:// 只返回 .gd/.import 文件
# （.tres 已转二进制存于 PCK，不在文件列表中）→ 运行时扫描全空 = 导出内容与编辑器完全不同。
# list_directory() 返回「导出前编辑器可见的文件名」，编辑器与导出构建行为一致，自动处理二进制映射。

# 返回 folder 下所有 .tres 的完整 res:// 路径（按文件名排序，顺序确定）。
# 用于整备池等「需要字符串路径」的消费方（HUD 仍 load(path) 渲染卡片）。
static func scan_paths(folder: String) -> Array:
	var out: Array = []
	var files := ResourceLoader.list_directory(folder)
	for f in files:
		if f.ends_with(".tres") and not f.begins_with("."):
			out.append(folder.path_join(f))
	out.sort()
	return out

# 扫描 folder 下所有 .tres，加载后仅保留 class_name == expected_class 的资源（按 resource_path 排序）。
# 用于 ROOMS / REWARD_POOL 等「直接持有 Resource 对象」的消费方。
# GDScript 的 `is` 运算符右操作数必须是字面类型，无法用运行时变量，故改用
# get_script().get_global_name() 比对自定义类名（比比对脚本路径字符串更稳健）。
static func scan_resources(folder: String, expected_class: String) -> Array:
	var out: Array = []
	var files := ResourceLoader.list_directory(folder)
	for f in files:
		if f.ends_with(".tres") and not f.begins_with("."):
			var r = load(folder.path_join(f))
			if r != null:
				var sc = r.get_script()
				if sc != null and String(sc.get_global_name()) == expected_class:
					out.append(r)
	out.sort_custom(func(a, b): return a.resource_path < b.resource_path)
	return out
