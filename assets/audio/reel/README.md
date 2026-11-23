# 转轮音效素材（2026-11-23）

素材来自 Kenney（kenney.nl）与 Mixkit（mixkit.co），均为**CC0 / 免费商用无需署名**。
已随项目入库。

| 文件 | 来源包 | 原始文件 | 用途 | 时长 |
|---|---|---|---|---|
| `spin_start.ogg` | RPG Audio（用户本地） | `chop.ogg` | 启动音 | 240ms |
| `tick_metal.ogg` | RPG Audio（用户本地） | `metalClick.ogg` | 每格推进金属咔，6 player 轮换 + ±3% 音高 | 450ms |
| `reel_land.ogg` | RPG Audio（用户本地） | `metalLatch.ogg` | 列落定 | 260ms |
| `win.ogg` | Interface Sounds | `confirmation_001.ogg` | 结算胜 | 290ms |
| `lose.ogg` | Impact Sounds | `impactPunch_heavy_000.ogg` | 结算负闷响 | 650ms |
| `coin_flash.ogg` | RPG Audio（用户本地） | `handleCoins.ogg` | 金币图标闪烁 | 850ms |
| `sym_attack.wav` | Mixkit（CC0） | 1487 Dagger woosh | 攻击符号（damage/special/status）— 清脆匕首破风 | 280ms |

heal / buff / shield / trash(MISS) 符号**静默**——由图标亮起 + 飘字表达，不占用声音频道。

## 事件映射（用户规格）

| 事件 | 代码位置 | 行为 |
|---|---|---|
| 启动 | `reel_system.gd:begin_spin()` | 播 spin_start |
| 每格推进 | `reel_system.gd:on_spin_tick()` | 三音随机轮换 + 独立 RNG ±3% 音高 |
| 按停吸附 | `reel_system.gd:_begin_absorb()` | **静默（克制）** |
| 列落定 | `reel_system.gd:_lock_at()` | 播 reel_land |
| 结算胜/负 | `turn_flow.gd`（combat.evaluate 后） | win / lose，经 `reel_system.play_result_sfx()` |
| 金币图标闪烁 | `combat_system.gd` 逐格读格（金币格） | coin_flash，2 player 轮换，经 `play_coin_sfx()` |
| 符号格闪烁 | `combat_system.gd` 逐格读格（非金币格）+ 攻击齐亮分支 | 仅 damage/special/status→攻击音；heal/buff/shield/trash→静默；经 `play_symbol_sfx()` |

音量分层（dB）：start -6 / tick -12 / land -4 / win -3 / lose -4 / coin -6 / sym -8。
演出音高抖动走 `ReelSystem._sfx_rng` 独立实例，不碰全局 RNG（工程铁律10）。

## 设计原则（2026-11-23 拍板）

符号格闪烁**仅攻击符号发声**，其余（heal/buff/shield/trash）全部静默。
依据经典 slot 音频预算原则：
- "Every animation doesn't need a dramatic noise. When everything sounds important, nothing really does."
- "Frequently repeated sounds generally shouldn't dominate the mix."
- "Feedback should be synchronized" —— heal/buff 音与游戏节奏、战斗打击感都对不上，硬配反而别扭。

这类高频良性符号由视觉接管（图标亮起 + 飘字已充分表达），声音预算只留给低频次、有打击感的时刻：
转轮机械音 + 攻击符号 + 金币 + 胜负。这是最经典也最省心的做法。
演进史：5 元素细分 → 5 kind 独立音 → 2 类短音 → 3 类短音 → **仅攻击音（当前）**，
逐步删减到经典的最小集合。
战斗场景的命中/伤害/状态生效演出目前无音效（battle_animator 无音源），若要补应另建，
与符号格闪烁音属不同时间点，不必混在一起。
