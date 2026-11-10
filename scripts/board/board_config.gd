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
@export var act: int = 1                    # 起始幕（三幕局固定从 ACT1 开始）
# G7-A S4：一局包含几幕。1 = 单幕（ACT1 行为不变，可回退）；3 = 三幕串联。
# 2026-11-08 作者拍板：默认 3（真人单幕一局约 4 分钟，判定「太短、太简单」）。回退 = 改回 1。
@export var acts: int = 3
@export var dice_sides: int = 3             # 1D3
@export var boss_ria: int = 7               # BOSS 的幕内难度位置（与线性 ACT1 8 房一致）
@export var battle_node_count: int = 8      # 单局路径 5 普通 + 2 精英 + 1 BOSS
# G4-02 骨架：空 = 每局随机（standard 25 / long_tail 29 / long_share 26 节点）；
# 测试与调试可填 "standard" / "long_tail" / "long_share" 固定形状。
@export var shape_id: String = ""
# G4-04 特殊格：空 = 每局随机（宝箱 / 神龛 / 武器藏库）；测试与调试可填对应 id。
@export var special_id: String = ""
# G4-01 分支价值模板：空 = 每局随机（standard / mirror / elite_first / elite_upper / elite_lower）；
# 测试与调试可填模板 id 固定类型分配（不影响骨架、深度与边）。
@export var template_id: String = ""
# 2026-11-10 扫雷棋盘 Step 2：棋盘布局模型。
#   "legacy" = 现有 1D3 / 25–29 节点骨架（默认，旧测试与试玩包不变）；
#   "grid4x4" = 固定 4×4 扫雷内容灰盒（Step 1/2）。
@export var layout_mode: String = "legacy"
# 4×4 内容冻结种子；同种子房间 / 武器 / 护符完全一致。
@export var grid_seed: int = 20261110


# 是否使用 4×4 扫雷网格。layout_mode 优先；命令行 --grid 可临时覆盖（需配合 --board）。
func use_grid() -> bool:
	if layout_mode == "grid4x4":
		return true
	var args := OS.get_cmdline_user_args()
	if "--grid" in args:
		return true
	return "--grid" in OS.get_cmdline_args()


func is_active() -> bool:
	if enabled:
		return true
	var args := OS.get_cmdline_user_args()
	if "--board" in args:
		return true
	return "--board" in OS.get_cmdline_args()
