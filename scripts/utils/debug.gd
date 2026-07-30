class_name Debug
extends RefCounted

## 统一调试日志工具。
##
## 用本工具替代散落在各处的裸 print()，解决两个问题：
##   1. 生产日志污染——release 导出构建自动静默所有 Debug.log 输出；
##   2. 调用点分散——统一一处开关，便于后续按需开启/分级。
##
## 开关策略：debug 构建（编辑器运行、调试导出）自动开启；
##          release 构建（正式导出）自动关闭，无需手动维护常量。
##
## 用法：
##   Debug.log("[效果执行] 治疗 +%.1f" % amount)   # 普通调试日志
##   Debug.warn("属性缺失")                         # 警告（始终 push_warning）
##   Debug.error("未实现效果")                       # 错误（始终 push_error）

static var enabled: bool = OS.is_debug_build()


## 普通调试日志。仅在 debug 构建打印，release 构建自动跳过。
static func log(msg: String) -> void:
	if enabled:
		print(msg)


## 警告。始终通过 push_warning 输出（不受 debug 开关影响）。
static func warn(msg: String) -> void:
	push_warning(msg)


## 错误。始终通过 push_error 输出（不受 debug 开关影响），
## 用于"不应发生 / 未实现"等真正需要暴露的缺陷。
static func error(msg: String) -> void:
	push_error(msg)
