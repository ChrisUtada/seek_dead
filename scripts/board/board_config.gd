# 不注册全局 class_name：headless 测试/新检出环境不会自动刷新类缓存（与 demo_config 同约定）。
extends Resource

# ============================================================================
# BoardConfig — 分岔路线图探索开关与本局规模（单一路径）
#
# 2026-11-19：14×9 开放网格已彻底删除，分岔路线图（DAG）是唯一的地图模式。
# 本资源只保留：是否进入地图模式（enabled）、本局幕数/起始幕、地图种子。
#
# 开关策略：
#   enabled = true                      —— 编辑器 / F6 手动试玩分岔地图；
#   命令行 --board / --branch            —— 不修改资源即可试玩；
#   测试内 board_config.enabled = true   —— 地图套件显式开启。
# 三者都不满足时保持线性房间（既有线性测试入口不变）。
# ============================================================================

@export var enabled: bool = false
@export var act: int = 1                    # 起始幕（三幕局固定从 ACT1 开始）
@export var acts: int = 3                   # 一局包含几幕。1 = 单幕；3 = 三幕串联
@export var boss_ria: int = 7               # BOSS 的幕内难度位置（与线性 ACT1 8 房一致）
@export var map_seed: int = 20261110        # 分岔图固定种子：同种子结构与房间绑定一致


func is_active() -> bool:
	if enabled:
		return true
	var args := OS.get_cmdline_user_args()
	if "--board" in args or "--branch" in args:
		return true
	return "--board" in OS.get_cmdline_args() or "--branch" in OS.get_cmdline_args()
