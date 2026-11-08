# palette.gd — 老虎机对决统一调色板
#
# Phase 0（UI 重构）：把散落在 duel_controller.gd 中的魔法颜色字面量集中管理。
# 2026-10-31 Step 1（战斗 UI 重构样板）：按 docs/战斗UI重构_执行方案与AI任务书.md §5.1 换色板。
#   暗紫褐底 + 暖白细线框 + 灰白玩家 / 红色敌人 + 交互金。
#   灰度纪律：红色只用于敌人/伤害/危险，金色只用于可操作/奖励/匹配。
#   颜色值即 sRGB 8bit（实测 Color(0.12,0.09,0.12) 渲染为 #1F171F，Color("#hex") 同语义）。
# 后续如需调整主题色，只改这里即可全局生效。
class_name Palette
extends RefCounted

# ---- 屏幕背景（ColorRect）----
# Step 5 结论：各子界面保留各自略深的底色（同一暗紫褐家族的明度差），不强行统一为 BG_MAIN——
# 底图同色会失去「战斗 / 整备 / 奖励」的场所切换感；差异仅明度，不引入新色相。
const BG_MAIN    := Color("#160d13")   # 主对决界面：暗紫褐底
const BG_LOADOUT := Color("#100a10")   # 整备界面
const BG_REWARD  := Color("#0d0b12")   # 奖励界面
const BG_ANVIL   := Color("#120e0a")   # 铁砧界面
const BG_OVERLAY := Color(0, 0, 0, 0.72)  # 结算/覆盖层遮罩

# ---- 每幕环境主题（G7-A S3 / D3：三幕共用骨架，只换配色，不新增美术）----
# map = 棋盘地图底；grid = 石砖网格；node = 普通节点线框；bg = 顶层/底栏底色。
const ACT_THEME := {
	1: {"name": "ACT I", "bg": Color("#160d13"), "map": Color("#1a1016"),
		"grid": Color("#1e1319"), "node": Color("#3a2b31")},
	2: {"name": "ACT II", "bg": Color("#0d1315"), "map": Color("#101a1c"),
		"grid": Color("#142022"), "node": Color("#2b3a3a")},
	3: {"name": "ACT III", "bg": Color("#160d10"), "map": Color("#1a1013"),
		"grid": Color("#201317"), "node": Color("#3a2b30")},
}


static func act_theme(act: int) -> Dictionary:
	return ACT_THEME.get(clampi(act, 1, 3), ACT_THEME[1])


static func act_name(act: int) -> String:
	return String(act_theme(act)["name"])

# ---- 硬边化（复古掌机 P2：圆角归零 + 边框加粗）----
const PANEL_RADIUS := 0     # 所有面板/卡片圆角 → 0（硬边）
const BORDER_WIDTH := 1     # 普通线框 1px（2026-10-31 Step 1：2 → 1；选中/SPIN/危险仍用 2~3px）

# ---- 面板样式（StyleBoxFlat）----
const PANEL_BG        := Color("#1d1219")  # 侧栏/卡片/按钮底（实色，避免叠色偏）
const PANEL_BORDER    := Color("#a99d89")  # 次级线框：面板、转轮格
const FRAME_MAIN      := Color("#e2d7bd")  # 主线框/关键文字（外框、重点线，Step 2 用于一级外框）
const DEEP_LINE       := Color("#3a222b")  # 内部隔断、角色暗部、悬停底
const PANEL_BG_ALT    := Color("#1d1219")  # 图例面板底（与主面板同底，靠线框区分）
const CARD_BG         := Color("#1d1219")  # 装备卡面板底
const CELL_BG         := Color("#1d1219")  # 转轮格子底
const TOOLTIP_BG      := Color("#1d1219")  # 悬停提示面板底（实色）

# ---- 文本/标题色 ----
const TITLE      := Color("#e2d7bd")  # 主文字/标题
const PLAYER     := Color("#b9b8b0")  # 玩家灰白
const ENEMY      := Color("#e35b50")  # 敌人红
const ENEMY_DARK := Color("#8c3438")  # 敌人暗部、危险框
const MUTED      := Color("#a99d89")  # 次级文本
const MUTED_DIM  := Color("#6e5f57")  # 弱信息
const ACCENT_GOLD := Color("#d5a33d")  # 交互金：SPIN/匹配/奖励

# ---- 飘字（_popup）颜色 ----
const POP_SHIELD := Color("#62a1c2")  # 护盾
const POP_HEAL   := Color("#a4bc4d")  # 治疗
const POP_STATUS := Color(1.00, 0.60, 0.30)  # 状态（语义例外：新色板无橙，保留以区分伤害/增益）
const POP_DAMAGE := Color("#e35b50")  # 伤害
const POP_BUFF   := Color(0.85, 0.65, 1.00)  # 主动增益（Step 5 结论：保留紫色作语义例外——增益必须与伤害红/治疗绿/护盾蓝三轴都不同，且不占用交互金）
const POP_GOLD   := Color("#d5a33d")  # 金币（转轮经济引擎）
const ARMOR      := Color("#62a1c2")  # 护盾/护甲蓝

# ---- 装备卡选中/常态样式 ----
const CARD_SEL_BG      := Color("#1d1219")  # 选中底（靠线框区分，不叠色）
const CARD_SEL_BORDER  := Color("#a4bc4d")  # 选中边框（生命绿）
const CARD_NORM_BG     := Color("#1d1219")  # 常态底
const CARD_NORM_BORDER := Color("#6e5f57")  # 常态边框（弱线）

# ---- 稀有度色（tooltip/卡片：common 灰 / uncommon 绿 / rare 蓝 / epic 紫）----
const RARITY_COMMON   := Color("#a99d89")
const RARITY_UNCOMMON := Color("#a4bc4d")
const RARITY_RARE     := Color("#62a1c2")
const RARITY_EPIC     := Color(0.85, 0.65, 1.00)  # 语义例外：史诗紫（与增益飘字同色，稀有度轴不与战斗语义冲突）
