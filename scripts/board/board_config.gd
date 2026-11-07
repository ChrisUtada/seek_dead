# 不注册全局 class_name：headless 测试/新检出环境不会自动刷新类缓存（与 demo_config 同约定）。
extends Resource

# ============================================================================
# BoardConfig — ACT1 棋盘灰盒开关与生成约束（M2）
# 规格：docs/棋盘探索_战后成长与局外生涯_制作执行方案.md §5、§7、§11 M2
#
# 开关策略（保证 15 套线性回归零行为变化）：
#   enabled = true                      —— 编辑器 / F6 手动试玩棋盘；
#   命令行 --board（user args）          —— 不修改资源即可试玩棋盘；
#   测试内 board_config.enabled = true   —— 棋盘套件显式开启。
# 三者都不满足时保持线性房间，既有测试入口不变。
# ============================================================================

@export var enabled: bool = false
@export var act: int = 1                    # M2 只做 ACT1 棋盘
@export var dice_sides: int = 3             # 1D3
@export var boss_ria: int = 7               # BOSS 的幕内难度位置（与线性 ACT1 8 房一致）
@export var battle_node_count: int = 8      # 单局路径 5 普通 + 2 精英 + 1 BOSS
# G4-02 骨架：空 = 每局随机（standard 25 节点 / long_tail 29 节点）；
# 测试与调试可填 "standard" / "long_tail" 固定形状。
@export var shape_id: String = ""
# G4-04 特殊格：空 = 每局随机（宝箱 / 神龛 / 武器藏库）；测试与调试可填对应 id。
@export var special_id: String = ""


func is_active() -> bool:
	if enabled:
		return true
	var args := OS.get_cmdline_user_args()
	if "--board" in args:
		return true
	return "--board" in OS.get_cmdline_args()
