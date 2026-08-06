# type_scale.gd — 老虎机对决字号阶梯
#
# Phase 0（UI 重构）：把散落的魔法字号集中为语义化常量。
# Phase 3（响应式）：viewport 从 640×360 升级到 1280×720 后，
#   全阶梯同步放大 ~35-50%，保证可读性。
# 复古掌机 P2：viewport 降至 480×270，全阶梯按 ~原值/2.4 重标定；
#   并因 UI 含中文（整备/武器/技能…），下限抬到 ≥11px 保证 CJK 像素字可读。
# P2b：默认字体换 VonwaonBitmap-12px（12px 位图字体），其最佳渲染尺寸 ≈12px，
#   故全阶梯下限锁 11（仅略缩，仍清晰），避免 <11 缩小糊化。
#   调整全局字号只需改这里。
class_name TypeScale
extends RefCounted

const REEL     := 16  # 转轮格子符号 / 全屏覆盖大字
const OVERLAY  := 12  # 飘字 / 覆盖层标题
const TITLE    := 13  # 界面主标题（Seek Dead · 老虎机对决）
const LEAD     := 12  # 子界面标题（整备 · 选择携带物品 / 列头）
const SUBTITLE := 12  # 主操作按钮（SPIN）
const BODY     := 12  # 正文标签（玩家/敌人 / 铁砧标题）
const MEDIUM   := 11  # 数值行（HP、确认/返回按钮）
const META     := 11  # 信息栏（房间/回合/护盾/副按钮/卡片名）
const TINY     := 11  # 弱信息（本局加成/日志/描述/图例/tooltip）
const CAPTION  := 11  # 极弱说明（副标题下一行的小字/升级花费）
