# 不注册全局 class_name：headless 测试/新检出环境不会自动刷新类缓存（与 demo_config 同约定）。
extends Resource

# ============================================================================
# BoardConfig — 棋盘探索开关与本局规模（单一路径）
# 规格：docs/地图巡逻诱导_第一版预算与分步执行计划_2026-11-14.md
#       §6 Step 0 作者决定（14×9 替换两套旧模型）+ Step 2 任务 6（单路径收敛）
#
# 2026-11-14 收敛：14×9 地图替换 1D3 节点骨架与 4×4 扫雷灰盒，工程内只保留一种地图。
# 本文件已删除：layout_mode / use_grid() / grid_seed / dice_sides / battle_node_count /
# shape_id / special_id / template_id / map14x9_enabled / map_dev_override。
# 旧模型专属脚本 board_generator.gd / board_grid.gd 同步退役。
#
# 开关策略（保证线性回归可控）：
#   enabled = true                      —— 编辑器 / F6 手动试玩棋盘；
#   命令行 --board（user args）          —— 不修改资源即可试玩棋盘；
#   测试内 board_config.enabled = true   —— 棋盘套件显式开启。
# 三者都不满足时保持线性房间，既有线性测试入口不变。
# ============================================================================

@export var enabled: bool = false
@export var act: int = 1                    # 起始幕（三幕局固定从 ACT1 开始）
# G7-A S4：一局包含几幕。1 = 单幕；3 = 三幕串联。
@export var acts: int = 3
@export var boss_ria: int = 7               # BOSS 的幕内难度位置（与线性 ACT1 8 房一致）
# 14×9 地图固定种子：同种子地形、内容、陷阱、巡逻与房间绑定完全一致。
@export var map_seed: int = 20261110


func is_active() -> bool:
	if enabled:
		return true
	var args := OS.get_cmdline_user_args()
	if "--board" in args:
		return true
	return "--board" in OS.get_cmdline_args()
