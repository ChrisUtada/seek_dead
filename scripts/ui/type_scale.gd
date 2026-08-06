# type_scale.gd — 老虎机对决字号阶梯
#
# Phase 0（UI 重构）：把散落的魔法字号集中为语义化常量。
# Phase 3（响应式）：viewport 从 640×360 升级到 1280×720 后，
#   全阶梯同步放大 ~35-50%，保证可读性。
# 复古掌机 P2：viewport 降至 480×270，全阶梯按 ~原值/2.4 重标定。
# P2b：默认字体换 VonwaonBitmap-12px（12px 位图字体），全阶梯下限锁 11 避免 <11 缩小糊化。
# P2c（E 项修复）：发现 VonwaonBitmap-12px 不含 CJK、且 allow_system_fallback=true
#   导致中文回退到系统矢量字体 → "字体没变化"假象。改用 zpix.ttf（含 CJK，12px 像素字）
#   作 default_font，关 antialiasing/hinting/system_fallback；并全阶梯再降一档（11→9 区间），
#   让 9-10px 像素感更明显（zpix 像素字体在 9-10px 中文仍可读，1px=2 像素清晰点阵）。
class_name TypeScale
extends RefCounted

const REEL     := 13  # 转轮格子符号 / 全屏覆盖大字
const OVERLAY  := 10  # 飘字 / 覆盖层标题
const TITLE    := 11  # 界面主标题（Seek Dead · 老虎机对决）
const LEAD     := 10  # 子界面标题（整备 · 选择携带物品 / 列头）
const SUBTITLE := 10  # 主操作按钮（SPIN）
const BODY     := 10  # 正文标签（玩家/敌人 / 铁砧标题）
const MEDIUM   := 9   # 数值行（HP、确认/返回按钮）
const META     := 9   # 信息栏（房间/回合/护盾/副按钮/卡片名）
const TINY     := 9   # 弱信息（本局加成/日志/描述/图例/tooltip）
const CAPTION  := 8   # 极弱说明（副标题下一行的小字/升级花费）
