# palette.gd — 老虎机对决统一调色板
#
# Phase 0（UI 重构）：把散落在 duel_controller.gd 中的魔法颜色字面量集中管理。
# 颜色值与原硬编码完全一致，仅做集中，不改任何视觉表现。
# 后续如需调整主题色，只改这里即可全局生效。
class_name Palette
extends RefCounted

# ---- 屏幕背景（ColorRect）----
const BG_MAIN    := Color(0.09, 0.09, 0.13, 1)      # 主对决界面
const BG_LOADOUT := Color(0.06, 0.06, 0.10, 0.98)   # 整备界面
const BG_REWARD  := Color(0.05, 0.07, 0.12, 0.98)   # 奖励界面
const BG_ANVIL   := Color(0.10, 0.08, 0.05, 0.98)   # 铁砧界面
const BG_OVERLAY := Color(0, 0, 0, 0.72)            # 结算/覆盖层遮罩

# ---- 面板样式（StyleBoxFlat）----
const PANEL_BG        := Color(0.11, 0.11, 0.16, 0.75)  # 侧栏面板底（已收入 battle_theme.tres）
const PANEL_BORDER    := Color(0.22, 0.22, 0.30, 1)     # 面板边框（多条共用）
const PANEL_BG_ALT    := Color(0.09, 0.09, 0.13, 0.85)  # 图例面板底（差异化，保留 override）
const CARD_BG         := Color(0.10, 0.10, 0.15, 0.80)  # 装备卡面板底
const CELL_BG         := Color(0.18, 0.18, 0.24, 1)     # 转轮格子底
const TOOLTIP_BG      := Color(0.07, 0.07, 0.11, 0.96)  # 悬停提示面板底（Phase 3 tooltip）

# ---- 文本/标题色 ----
const TITLE      := Color(0.90, 0.85, 0.70, 1)  # 标题金
const PLAYER     := Color(0.60, 0.85, 0.95, 1)  # 玩家强调
const ENEMY      := Color(0.95, 0.55, 0.55, 1)  # 敌人强调
const MUTED      := Color(0.70, 0.70, 0.75, 1)  # 次级文本
const MUTED_DIM  := Color(0.65, 0.65, 0.75, 1)  # 更弱文本
const ACCENT_GOLD := Color(1.0, 0.85, 0.30, 1)  # 角标/强调金

# ---- 飘字（_popup）颜色 ----
const POP_SHIELD := Color(0.55, 0.70, 0.95)  # 护盾
const POP_HEAL   := Color(0.50, 0.95, 0.60)  # 治疗
const POP_STATUS := Color(1.00, 0.60, 0.30)  # 状态
const POP_DAMAGE := Color(1.00, 0.50, 0.40)  # 伤害
const POP_BUFF   := Color(0.85, 0.65, 1.00)  # 主动增益（Phase C）
const POP_GOLD   := Color(1.00, 0.80, 0.15)  # 金币（转轮经济引擎）

# ---- 装备卡选中/常态样式 ----
const CARD_SEL_BG      := Color(0.20, 0.32, 0.22, 1)  # 选中底
const CARD_SEL_BORDER  := Color(0.45, 0.85, 0.50, 1)  # 选中边框
const CARD_NORM_BG     := Color(0.16, 0.16, 0.22, 1)  # 常态底
const CARD_NORM_BORDER := Color(0.30, 0.30, 0.38, 1)  # 常态边框
