# type_scale.gd — 老虎机对决字号阶梯
#
# Phase 0（UI 重构）：把散落的魔法字号集中为语义化常量。
# Phase 3（响应式）：viewport 从 640×360 升级到 1280×720 后，
#   全阶梯同步放大 ~35-50%，保证可读性。
#   调整全局字号只需改这里。
class_name TypeScale
extends RefCounted

const REEL     := 36  # 转轮格子符号 / 全屏覆盖大字
const OVERLAY  := 24  # 飘字 / 覆盖层标题
const TITLE    := 22  # 界面主标题（Seek Dead · 老虎机对决）
const LEAD     := 20  # 子界面标题（整备 · 选择携带物品 / 列头）
const SUBTITLE := 18  # 主操作按钮（SPIN）
const BODY     := 17  # 正文标签（玩家/敌人 / 铁砧标题）
const MEDIUM   := 16  # 数值行（HP、确认/返回按钮）
const META     := 14  # 信息栏（房间/回合/护盾/副按钮/卡片名）
const TINY     := 13  # 弱信息（本局加成/日志/描述/图例/tooltip）
const CAPTION  := 12  # 极弱说明（副标题下一行的小字/升级花费）
