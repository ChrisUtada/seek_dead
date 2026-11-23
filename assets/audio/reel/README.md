# 转轮音效素材（2026-11-23）

Kenney 免费音效包，**CC0 许可**（Creative Commons Zero，可商用、无需署名）。
下载自 kenney.nl，已随项目入库。

| 文件 | 来源包 | 原始文件 | 用途 | 时长 |
|---|---|---|---|---|
| `spin_start.ogg` | RPG Audio（用户本地） | `chop.ogg` | 启动音 | 240ms |
| `tick_metal.ogg` | RPG Audio（用户本地） | `metalClick.ogg` | 每格推进金属咔，6 player 轮换 + ±3% 音高 | 450ms |
| `reel_land.ogg` | RPG Audio（用户本地） | `metalLatch.ogg` | 列落定 | 260ms |
| `win.ogg` | Interface Sounds | `confirmation_001.ogg` | 结算胜 | 290ms |
| `lose.ogg` | Impact Sounds | `impactPunch_heavy_000.ogg` | 结算负闷响 | 650ms |
| `coin_flash.ogg` | RPG Audio（用户本地） | `handleCoins.ogg` | 金币图标闪烁 | 850ms |
| `sym_attack.ogg` | RPG Audio（Kenney） | `drawKnife1.ogg` | 攻击符号格闪烁（damage/special）— 拔剑声 | 400ms |
| `sym_boost.ogg` | Interface Sounds（Kenney） | `pluck_001.ogg` | 增益符号格闪烁（shield/heal/buff/status） | 100ms |

## 事件映射（用户规格）

| 事件 | 代码位置 | 行为 |
|---|---|---|
| 启动 | `reel_system.gd:begin_spin()` | 播 spin_start |
| 每格推进 | `reel_system.gd:on_spin_tick()` | 三音随机轮换 + 独立 RNG ±3% 音高 |
| 按停吸附 | `reel_system.gd:_begin_absorb()` | **静默（克制）** |
| 列落定 | `reel_system.gd:_lock_at()` | 播 reel_land |
| 结算胜/负 | `turn_flow.gd`（combat.evaluate 后） | win / lose，经 `reel_system.play_result_sfx()` |
| 金币图标闪烁 | `combat_system.gd` 逐格读格（金币格） | coin_flash，2 player 轮换，经 `play_coin_sfx()` |
| 符号格闪烁 | `combat_system.gd` 逐格读格（非金币格） | 按符号 kind：damage/special→攻击音，shield/heal/buff/status→增益音，trash/MISS→静默；经 `play_symbol_sfx()` |

音量分层（dB）：start -6 / tick -12 / land -4 / win -3 / lose -4 / coin -6 / sym -8。
演出音高抖动走 `ReelSystem._sfx_rng` 独立实例，不碰全局 RNG（工程铁律10）。

## 设计原则（2026-11-23 拍板）

符号格闪烁按 **kind 分两类**，不按 5 元素细分。依据行业经典做法 Audio Hierarchy：
声音表达「这格是干嘛的」（攻击 vs 增益 vs 废牌），元素交给战斗场景的命中演出表达。
这样跨元素统一、语义清晰，也避免 5 种魔法音在 10,000 次 spin 下的听觉疲劳。
MISS/trash 静默——失败不庆祝（行业伦理规范），静音是有效的对比工具。
曾试过按 5 元素细分（Mixkit 魔法音），已否决并回退。
