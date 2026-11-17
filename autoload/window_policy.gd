extends Node

# 窗口策略（2026-11-17）
#
# 取舍：**永不出现黑边**，宁可非整数缩放时画面轻微不均匀。
#   - 逻辑画布 480×270，2× = 960×540；
#   - 窗口最大锁在 960×540，玩家拉不大，也就不存在"拉伸变糊"；
#   - 允许缩小（最小 480×270，见 project.godot 的 min_width/min_height）；
#   - 不用 stretch/scale_mode="integer" —— 那会在非整数尺寸留黑边，已移除。
#
# 为什么不用项目设置：Godot 4 的 display/window/size 只提供 min_width/min_height，
# 没有 max 项，必须走 DisplayServer API。

const MAX_W := 960   # 480 × 2
const MAX_H := 540   # 270 × 2


func _ready() -> void:
	DisplayServer.window_set_max_size(Vector2i(MAX_W, MAX_H))
