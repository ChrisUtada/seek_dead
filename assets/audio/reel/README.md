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
| `sym_shield.wav` | Mixkit（CC0） | 2765 Sword strikes armor | 护盾符号（shield）— 剑击金属盔甲（物理） | 220ms |
| `sym_support.wav` | Mixkit（CC0） | 255 Fantasy game sweep notification | 增益符号（heal/buff）— 奇幻魔法 | 280ms |

## 事件映射（用户规格）

| 事件 | 代码位置 | 行为 |
|---|---|---|
| 启动 | `reel_system.gd:begin_spin()` | 播 spin_start |
| 每格推进 | `reel_system.gd:on_spin_tick()` | 三音随机轮换 + 独立 RNG ±3% 音高 |
| 按停吸附 | `reel_system.gd:_begin_absorb()` | **静默（克制）** |
| 列落定 | `reel_system.gd:_lock_at()` | 播 reel_land |
| 结算胜/负 | `turn_flow.gd`（combat.evaluate 后） | win / lose，经 `reel_system.play_result_sfx()` |
| 金币图标闪烁 | `combat_system.gd` 逐格读格（金币格） | coin_flash，2 player 轮换，经 `play_coin_sfx()` |
| 符号格闪烁 | `combat_system.gd` 逐格读格（非金币格）+ 攻击齐亮分支 | 按 kind 分 3 类短音：damage/special/status→攻击音，shield→护盾音，heal/buff→增益音；trash/MISS→静默；经 `play_symbol_sfx()` |

音量分层（dB）：start -6 / tick -12 / land -4 / win -3 / lose -4 / coin -6 / sym -8。
演出音高抖动走 `ReelSystem._sfx_rng` 独立实例，不碰全局 RNG（工程铁律10）。

## 设计原则（2026-11-23 拍板）

符号格闪烁收敛为 **3 类短音**（攻击 / 护盾 / 魔法增益），不按元素或具体符号细分。
依据行业原则（Dolce & Forte「Design for the thousandth spin」）：高频音必须短、不张扬、
留 headroom。逐格间隔只有 420ms，长音（heal 900ms / status 850ms）会重叠成噪音，
故全部收到 ≤280ms，与攻击音同长同方式，天然有间隔。
护盾单独保留物理金属音（用户拍板：盾是金属实体，不是魔法）；heal/buff 用短促奇幻魔法音。
MISS/trash 静默——失败不庆祝，静音是有效的对比工具。
演进史：5 元素细分 → 5 kind 独立音 → 2 类短音 → 3 类短音（当前），逐步收敛到经典做法。
战斗场景的命中/伤害/状态生效演出目前无音效（battle_animator 无音源），若要补应另建，
与符号格闪烁音属不同时间点，不必混在一起。
