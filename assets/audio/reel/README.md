# 转轮音效素材（2026-11-23）

Kenney 免费音效包，**CC0 许可**（Creative Commons Zero，可商用、无需署名）。
下载自 kenney.nl，已随项目入库。

| 文件 | 来源包 | 原始文件 | 用途 | 时长 |
|---|---|---|---|---|
| `spin_start.ogg` | Interface Sounds | `select_001.ogg` | 启动轻咔 | 40ms |
| `tick_metal.ogg` | RPG Audio（用户本地） | `metalClick.ogg` | 每格推进金属咔，6 player 轮换 + ±3% 音高 | 450ms |
| `reel_land.ogg` | Impact Sounds | `impactSoft_medium_000.ogg` | 列落定 | 120ms |
| `win.ogg` | Interface Sounds | `confirmation_001.ogg` | 结算胜 | 290ms |
| `lose.ogg` | Impact Sounds | `impactPunch_heavy_000.ogg` | 结算负闷响 | 650ms |

## 事件映射（用户规格）

| 事件 | 代码位置 | 行为 |
|---|---|---|
| 启动 | `reel_system.gd:begin_spin()` | 播 spin_start |
| 每格推进 | `reel_system.gd:on_spin_tick()` | 三音随机轮换 + 独立 RNG ±3% 音高 |
| 按停吸附 | `reel_system.gd:_begin_absorb()` | **静默（克制）** |
| 列落定 | `reel_system.gd:_lock_at()` | 播 reel_land |
| 结算胜/负 | `turn_flow.gd`（combat.evaluate 后） | win / lose，经 `reel_system.play_result_sfx()` |

音量分层（dB）：start -6 / tick -12 / land -4 / win -3 / lose -4。
演出音高抖动走 `ReelSystem._sfx_rng` 独立实例，不碰全局 RNG（工程铁律10）。
