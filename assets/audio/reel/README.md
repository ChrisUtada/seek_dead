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
| `sym_attack.wav` | Mixkit（CC0） | 1487 Dagger woosh | 真攻击符号（damage/special）— 清脆匕首破风 | 280ms |
| `sym_heal.wav` | Mixkit（CC0） | 2830 Video game magic potion | 治疗符号（heal）— 魔法药剂（截取 0-1.0s，血条增长帧播） | 1.0s |

符号音按反馈比例分三级（经典 Audio Hierarchy / Feedback scale with outcome）：
- damage/special → 攻击音（Dagger woosh，-8dB）
- buff / heal 格子闪时 → Dagger woosh 压低到 **-20dB** 的轻确认音（高频但不张扬）
- heal 血条真增长时 → 另有专用治愈音 **sym_heal.wav（1.0s 魔法药剂）**（见下）
- status/shield/trash → 静默，交给视觉

演出间隔：常规 0.42s；本回合符号 ≥3 时拉长到 0.6s（Readability：每格闪光+飘字呈现完整）。
治愈音播完再进下一格：heal 格触发治愈音时，该格停留拉到 1.05s（>1.0s 音长），避免相邻治愈音重叠。
（快速跳过时 `_present_wait` 仍会把等待压到最小一帧。）

治疗链路（2026-11-23 修正）：
- **格子闪时**：静默（用户不要操作确认音）
- **血条增长帧**：专用治愈音 sym_heal(1.0s)，仅 `heal_gain>0`（血条真涨）时播——"音随结果走"
🔴 关键：播放条件**只看 heal_gain>0，不依赖收益文本 g**。
原因：regen 持续回复会抬高 heal_gain（血条真涨），但不计入 source_heal，
导致治疗格的 g 可能为空——若按 g 判断就会"血条涨了却没声"。满血(heal_gain=0)则不播。

🔴 血条增长时机（2026-11-23 修正）：治疗 HP 在结算阶段(_phase_defense)就落地，
但血条此前在 hold_enemy_preview/_refresh_meta 提前涨——"一按停就涨了"，与治愈音错位。
解法（借鉴 N-03 敌人幽灵值）：结算时 hud.hold_heal_display(旧血值) 锁住显示，
HP 数据照常落地；heal 格演出帧 hud.release_heal_display() 释放 → 血条涨与治愈音同帧。
兜底：无 heal 符号格的治疗（纯 regen/护符）在演出末尾统一释放，避免跨回合残留锁。
经典依据（Questbe）："sound, animation, and game state should remain synchronized"。
护符治疗（① 段）暂不配音，仅转轮治疗格链路有此同步音。
MISS/废铁(trash)会**错时单独闪烁**——等其它格子闪完、攻击齐亮淡出后才闪（④a 段），
时间上完全分离，不跟攻击/增益一起亮。它是负面结果，语义上不该像攻击，且无音效。

## 事件映射（用户规格）

| 事件 | 代码位置 | 行为 |
|---|---|---|
| 启动 | `reel_system.gd:begin_spin()` | 播 spin_start |
| 每格推进 | `reel_system.gd:on_spin_tick()` | 三音随机轮换 + 独立 RNG ±3% 音高 |
| 按停吸附 | `reel_system.gd:_begin_absorb()` | **静默（克制）** |
| 列落定 | `reel_system.gd:_lock_at()` | 播 reel_land |
| 结算胜/负 | `turn_flow.gd`（combat.evaluate 后） | win / lose，经 `reel_system.play_result_sfx()` |
| 金币图标闪烁 | `combat_system.gd` 逐格读格（金币格） | coin_flash，2 player 轮换，经 `play_coin_sfx()` |
| 符号格闪烁 | `combat_system.gd` 逐格读格（非金币格）+ 攻击齐亮分支 | damage/special→重音(-8dB)；buff格闪→轻确认音(-20dB)；heal格闪→静默,血条涨→专用治愈音(1.0s,仅heal_gain>0)；status/shield→静默；trash/MISS→错时单独轻闪+静默(④a)；齐亮仅在含真攻击时发音；逐格间隔多符号时 0.42→0.6s |

音量分层（dB）：start -6 / tick -12 / land -4 / win -3 / lose -4 / coin -6 / sym -8。
演出音高抖动走 `ReelSystem._sfx_rng` 独立实例，不碰全局 RNG（工程铁律10）。

## 设计原则（2026-11-23 拍板）

符号音按 **Feedback scale with outcome** 分三级，而非简单"有/无"：
攻击重音(-8dB) / 增益轻音(-20dB，同素材) / 其余静默。
依据经典原则（iGaming Times）：
- "Feedback should scale with outcome" —— 反馈要跟结果匹配
- "The elements played most often should be the least assertive" —— 高频音最不张扬（压音量，不是静默）
- "Sound should reinforce information conveyed visually" —— 声音强化视觉，不是替代

演出节奏与音效密度是**两个独立维度**（用户 2026-11-23 提点）：
- Readability："Sequencing rather than simultaneity" + "Pacing that scales with significance"
  → 多符号回合逐格间隔 0.42→0.6s，让每格呈现完整
- 音效密度：同素材不同强度，攻重增轻，解决"错乱感"而非靠全静默

演进史：5 元素细分 → 5 kind 独立音 → 2 类短音 → 3 类短音 → 仅攻击音 → **三级反馈+动态间隔（当前）**，
在"可读性"与"不疲劳"之间收敛到经典平衡。
战斗场景的命中/伤害/状态生效演出目前无音效（battle_animator 无音源），若要补应另建，
与符号格闪烁音属不同时间点，不必混在一起。
