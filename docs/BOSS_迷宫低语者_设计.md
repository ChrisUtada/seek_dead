# BOSS · 迷宫低语者（The Maze Whisperer）设计

> 状态：**已落地（2026-08-10，Step 1-2 完成）**——whisper_lock_gimmick.gd 参数化双阶段（phase2_* 缺省 = 单阶段，呓语教徒零改动）+ maze_whisperer.tres（300/16/25 · dark · rotating · 意图 attack 35/jam 35/lock 30（jam purifiable）· 光系战利品池 T32 + whisper_relic）。F6 待验：P2 触发/锁轮加速/乱权/教徒回归。
> 关联：**T10**（BOSS 阶段化·Act2 双阶段示例：Act1 单阶段 → Act2 双阶段 → Act3 三阶段）、**T24**（gimmick_params 参数化）、**T4**（BOSS 池 6/12→7/12）、**T25**（rotating 权重 3 入 Act2 BOSS 槽 2 候选）、**T32**（BOSS 主题武器掉落规则）、**T20**（意图资源化：jam/lock 可净化）。
> 基底：现有 `whisper_lock_gimmick.gd`（呓语锁轮·单阶段）参数化升级为双阶段——`phase2_*` 缺省 = 单阶段，**呓语教徒（教学位）零改动**。

---

## 1. 定位与特色

**Act2 双阶段 BOSS（操作干扰型终局）**：Act2 BOSS 槽「2 候选选 1」的 **rotating 候选**（fixed 呓语教徒权重 6 / rotating 迷宫低语者权重 3 ≈ 33%）。**双阶段** = Act1 单阶段教学（锁轮）→ Act2 双阶段的阶段化验收：P1 教你应对干扰节奏，P2 把干扰强度拉满逼你极限操作。

```
P1 呓语不绝（HP 100% → 50%）：高频 Jam/Lock 意图 + 呓语锁轮（每 3 回合锁 1 列 + 攻击 ×1.5）
P2 疯狂呓语（HP < 50% 触发一次）：乱权加入 + 锁轮加速（每 2 回合）+ 攻击强化（×1.8）
```

**定位**：与呓语教徒（教学位）互补——教徒教"锁轮是什么、净化药剂怎么用"；低语者是**同解的验收关**：锁轮+乱权双干扰下还能稳定输出（光武克制 + 目押按停 + 净化），拖回合 = 被乱权/锁轮拖杀。

## 2. BOSS 数值表

| 项 | 值 | 说明 |
|---|---|---|
| 名称 | 迷宫低语者（The Maze Whisperer） | 游戏内显示名随 .tres 的 name |
| 元素 / 弱点 | **dark** / 弱 **light**（光武 ×1.5；毒武备选 ×1.5 + DoT，v2 元素体系） | 与呓语教徒同元素——Act2 带光武通吃两候选 |
| HP / ATK | **300 / 16**（ante 后 ≈800 / 31，ria=3） | 比教徒（290/20）血多攻低——伤害不是重点，干扰才是；P2 攻击 ×1.8 后 ≈28 与教徒持平 |
| 基础护甲 | **25** | 与教徒一致；破甲窗口压力前置到 P2 |
| 阶段 / 角色 | **双阶段**（P2 HP<50%）/ **rotating** | Act2 BOSS 槽 2 候选（fixed 6 : rotating 3） |
| 意图（P1） | **attack 35 / jam 35 / lock 30** | jam 注废（净化可抵消）、lock 锁列（目押提前按停）——干扰占比 65% |
| P2 追加 | **chaos 每回合 25%**（gimmick 驱动）+ lock 周期 3→2 + 攻击 1.5→1.8 | 乱权不占意图槽位（零核心改动，gimmick 直置 pending_chaos） |
| 玩家侧 MISS | 带子按装备 hit_rate 聚合 MISS 格（10-22%） | 全局基本功；被锁/被乱权时的白回合更致命 |

## 3. 机制（双阶段 whisper_lock，全参数化 T24）

### 3.1 P1 呓语不绝（HP 100% → 50%）
- **呓语锁轮**：每 `lock_every`（默认 3）回合 `pending_lock_reel` 锁 1 列 + 该回合攻击 ×`attack_mult`（默认 1.5）——现单阶段机制原样保留
- **意图剖面**：jam 35 / lock 30 / attack 35——干扰意图占比 65%（对比教徒的 50/25/25 更凶），jam 注废可被**净化药剂**抵消（purifiable）

### 3.2 P2 疯狂呓语（HP < 50% 触发，一次性）
`on_damaged` 检测 `ctrl.enemy_hp <= ctrl.enemy_hp_max * phase2_hp_ratio` 且未触发过 → 进入 P2：
- **锁轮加速**：周期 `lock_every` 3 → `phase2_lock_every`（默认 2）
- **攻击强化**：倍率 `attack_mult` 1.5 → `phase2_attack_mult`（默认 1.8）
- **乱权呓语**：每回合 `phase2_chaos_chance`（默认 25%）概率直置 `ctrl.pending_chaos = true`（乱权注废——零核心改动，不占意图槽位，意图预告仍显示 attack/jam/lock）
- 触发瞬间日志 + 飘字「🌀 疯狂呓语！乱权降临，锁轮加速」

### 3.3 参数化（T24 gimmick_params）
```json
{"lock_every": 3, "attack_mult": 1.5, "phase2_hp_ratio": 0.5,
 "phase2_lock_every": 2, "phase2_attack_mult": 1.8, "phase2_chaos_chance": 0.25}
```
> 缺省 = 单阶段（`phase2_hp_ratio` 缺省 0 永不触发）——**呓语教徒 .tres 零改动**，教学位不受影响。

## 4. 对策与联动（解法矩阵）

| 对策轴 | 具体 | 联动 |
|---|---|---|
| **克制·主解** | holy_sword 45/88% / dawn_bow 28/84%（光武 ×1.5）；毒武备选（毒克暗 ×1.5 + DoT） | 克制命中喂充能；DoT 在 P2 拖回合时对冲 |
| **净化·干扰** | 净化药剂（抵消 jam 注废意图） | jam 占比 35%——净化是本战正解（与教徒教学衔接） |
| **目押·锁轮** | 被锁列在锁定时段提前按停（保留好符号） | 锁轮周期 P2 变 2 回合——按停时机精度是 P2 的核心考验 |
| **重转·容错** | 重转卷轴（锁轮/乱权废回合时补救） | P2 每回合 25% 乱权——重转卷轴价值上升 |
| **爆发·窗口** | 强袭×2 / 元素充能核爆 / 三连暴击 | 破甲 25 的窗口内必须兑成击杀，P2 拖杀 |
| **穿透·备选** | pistol / ice_gun（pierce 直击 HP） | 无视护甲 25 + 锁轮干扰的稳定输出线 |
| **基础功** | MISS 按停规避 | 白回合 = 白吃锁/乱权 |

**节奏参考**：开局 jam/lock 交替平压（教徒手感）→ 前 5 回合锁轮 1-2 次、攻击 ×1.5 → **HP 过半触发 P2**：乱权 25%/回合 + 每 2 回合锁轮 + 攻击 ×1.8 → 玩家必须靠光武克制 + 净化 + 目押按停撑住输出，破甲窗口内强袭/充能击杀（拖过 8-10 回合 = 锁轮/乱权叠死）。

## 5. 内容清单

> 状态列约定同 Act1 四文档。本 BOSS **零新装备**（净化药剂（jam 对策）已存在；光武/毒武/穿透武全为现有 12 武器），符合单侧性纪律。

| 房间 | kind | 元素 | hp/atk/甲 | 角色 | 战利品 | 状态 |
|---|---|---|---|---|---|---|
| 迷宫低语者 | boss | dark | 300/16/25 | rotating | **光系主题武器池**（holy_sword / dawn_bow / iron_sword） | 【新增】 |

> 战利品遵循 **T32**（弱光 BOSS 掉光系主题武器——光武打暗系敌人/后续场景有用）；专属信物复用 `whisper_relic.tres`（与呓语教徒同系，抗扰向）；房间命名沿用课程化规范（`a2_` 前缀）。

## 6. 实现步骤（零核心代码改动：锁轮/乱权走既有 pending_lock_reel/pending_chaos，阶段切换走 on_damaged 钩子）

| 步骤 | 内容 | 改动文件 | 验证点（F6） |
|---|---|---|---|
| Step 1 · gimmick 升级 | `whisper_lock_gimmick.gd` 参数化双阶段：phase2_* 缺省 = 单阶段（教徒零改动）；on_damaged 检测 HP 阈值一次性进 P2；P2 锁轮周期/攻击倍率切换 + 每回合 chaos 概率置 pending_chaos；ICON 🌀 | `scripts/battle/gimmicks/whisper_lock_gimmick.gd` | 教徒战表现不变；低语者 HP<50% 触发 P2、锁轮 2 回合、攻击 ×1.8、乱权 25% |
| Step 2 · 房间 .tres | 迷宫低语者：300/16/25 · dark · kind=boss · act=2 · boss_role=rotating · intents(attack 35/jam 35/lock 30) · gimmick_params · 光系战利品池（T32）+ whisper_relic | `resources/rooms/` 新增 | Act2 BOSS 槽可抽到（权重 3）、意图剖面正确、P2 触发 |
| Step 3 · 文档回写 | 总清单 T4 BOSS 池 6/12→7/12；本文档状态 → 已落地 | `docs/未完成任务_总清单.md` | — |
| Step 4 · F6 验证 | 见 §7 清单 | — | 全绿 |

## 7. F6 验证清单

- [ ] 迷宫低语者以 rotating 候选进入 Act2 BOSS 槽（与教徒 2 候选抽取分布 ≈ 6:3）
- [ ] P1：每 3 回合锁 1 列 + 攻击 ×1.5；意图 jam 35 / lock 30 出现且 jam 可净化
- [ ] HP<50% 一次性触发 P2（日志/飘字），不重复触发
- [ ] P2：锁轮每 2 回合、攻击 ×1.8、乱权 ≈25%/回合（转轮注入废铁）
- [ ] 光武克制 ×1.5、毒武备选 ×1.5 + DoT；净化药剂抵消 jam
- [ ] 破甲窗口（强袭/充能核爆/穿透）内击杀；拖杀循环成立（锁+乱权叠死）
- [ ] 战利品为光系主题武器池（holy_sword / dawn_bow / iron_sword）；信物 whisper_relic 可拾取
- [ ] 呓语教徒（教学位）表现与改动前一致（单阶段回归）

## 8. 关联

- 总清单 **T10**（阶段化：Act1 单阶段 → Act2 双阶段示例）、**T24**（gimmick 参数化）、**T4**（BOSS 池 7/12）、**T25**（rotating 权重 3 / RoomData.boss_role）、**T32**（弱光 BOSS 掉光系）、**T20**（意图资源化 jam/lock purifiable）
- 结构参照：BOSS_茧居石雕_设计.md（隐秘位验收关，本 BOSS 为 **rotating 位双阶段**）
- 机制复用：锁轮（whisper_lock 现有）+ 乱权（pending_chaos 现有）——Act3 三阶段 BOSS 可直接在此基础上加第三段
