# BOSS · 碎裂石像鬼（The Brittle Gargoyle）设计

> 状态：**✅ 已落地（2026-08-09，Step 1-4 完成）**——`glass_cannon_gimmick.gd`（石屑反弹：min(5, 总伤×15%)，走 `enemy_deal_damage` 唯一闸口 → 护盾可挡、击杀一击不反弹；`gimmick_params` 参数化）+ `brittle_gargoyle.tres`（165/22/8 · ice · kind=boss · act=1 · boss_role=rotating · intents attack 40/heavy 60 · 火系战利品池）。**零核心代码改动**（`on_damaged` 钩子与伤害闸口均为既有）。F6 已验：4 选 1 抽取分布 60 局铁瓮 40 : 石像鬼 20（权重 6:3 吻合）、反弹数值/上限/击杀豁免单测通过、房间字段加载正确；实机手感与火克制/MISS/通关链待 F6 复核。
> 关联：T10（BOSS 阶段化·Act1 单阶段轮替示例）、T24（gimmick_params 新规落地）、T4（BOSS 池 3/12→4/12）、T25（rotating 权重 3 入 4 选 1）、**T32（BOSS 主题武器掉落规则——本 BOSS 战利品遵循）**。

---

## 1. 定位与特色

**轮替 BOSS（重玩性内容）**：与固定首领铁瓮（教学位）错位——它是 Act1 BOSS 槽「4 候选选 1」的轮替候选（`boss_role=rotating`，权重 3），出场时替代铁瓮，提供差异化节奏。

```
① 高攻窗口：ATK 22（铁瓮 1.47 倍）+ heavy 偏置意图 → 蓄力重击威胁大
② 石屑反弹：受击反馈自噬伤害 → 输出节奏有代价
③ 脆甲：护甲 8 → 快速打穿，抢杀可行
```

## 2. BOSS 数值表

| 项 | 值 | 说明 |
|---|---|---|
| 名称 | 碎裂石像鬼（The Brittle Gargoyle） | 游戏内显示名随 .tres 的 name |
| 元素 / 弱点 | ice / 弱 **fire** | 与铁瓮一致（玩家火符号 ×1.5） |
| HP / ATK | **165 / 22**（ante 后 ≈439 / 43，ria=7） | 比铁瓮（175/15）脆而凶；数值待 F6 复核 |
| 基础护甲 | **8** | 远低于铁瓮 20——「一触即碎」 |
| 阶段 / 角色 | 单阶段 / **rotating** | Act1 BOSS 槽 4 选 1 候选（权重 3） |
| 意图 | **attack 40 / heavy 60**（覆盖默认 60/40） | 蓄力预告为主，护盾/治疗有节奏（heavy=×2.0） |
| 玩家侧 MISS | 带子按装备 hit_rate 聚合 MISS 格（10-22%） | 全局基本功 |

## 3. 机制

### 3.1 石屑反弹（glass_cannon · 核心）
- `on_damaged` 钩子每轮结算后触发：**反弹 = min(上限, 本轮总伤害 × 15%)**，参数化 `gimmick_params = {"reflect_ratio": 0.15, "reflect_cap": 5}`
- 走 `combat.enemy_deal_damage` 唯一闸口：**护盾可挡**（守备/铁壁同扛重击 + 反弹）、飘字/受击动画/日志自动
- **击杀一击不反弹**（enemy_hp ≤ 0 不结算）——抢杀即规避反弹
- 不分伤害类型（普通/穿透/三连/核爆/充能全按本轮总伤害）；无状态挂载（与 frost/trash/MISS 区分）

### 3.2 高攻窗口（意图剖面）
- `RoomData.intents` 覆盖 boss 默认表：attack 40 / heavy 60（heavy = ×2.0，IntentData.value_mult）
- 蓄力预告可读：heavy 回合前架盾/治疗，或抢在重击前击杀

### 3.3 脆甲
- 甲 8（ante 缩放）：非穿透伤害 1-2 轮打穿，穿透符号直接无视
- 破甲/穿透对策在本 BOSS 价值低于铁瓮——差异化逼换打法

## 4. 对策与联动（解法矩阵）

| 对策轴 | 具体 | 联动 |
|---|---|---|
| **护盾流·主解** | 守备（4/回合）/ 铁壁（8/回合）/ 守望（12/房） | 同时挡重击与反弹，双克制 |
| **抢杀·爆发** | 强袭×2 / 元素充能核爆 / 三连暴击 / 重转凑三连 | 击杀一击无反弹 = 爆发直接兑收益 |
| **武器·克制** | fire_sword 45/88% / flame_staff 40/86%（×1.5） | 克制命中喂充能，双轴并行 |
| **武器·穿透** | pistol / ice_gun（pierce 符号） | 无视低甲直击 |
| **消耗品** | 治疗（反弹容错）/ 强袭 / 重转 | 腰带取舍：治疗/爆发压力位 |
| **技能** | rage（增伤）/ recovery（容错） | 共用池 |
| **基础功** | MISS 按停规避 | 停歪 = 该列无效 + 白挨反弹 |

**节奏参考**：attack 平压 → 2-3 回合 heavy 蓄力（架盾窗口）→ 玩家火力全开（反弹压力上升）→ 低血阶段拼抢杀（最后一击无反弹）。

## 5. 内容清单

> 状态列约定同铁瓮文档（原/调整/【新增】/规划）。本 BOSS **零新装备**（武器 12 / 技能 5 / 护符 13 / 消耗品 4 全「原」共用，不重复列表）。

| 房间 | kind | 元素 | hp/atk/甲 | 角色 | 战利品 | 状态 |
|---|---|---|---|---|---|---|
| 碎裂石像鬼 | boss | ice | 165/22/8 | rotating | 火系主题武器池（fire_sword / flame_staff / 通用） | 【新增】 |

> 调整说明：入 Act1 BOSS 槽 4 选 1 候选（rotating 权重 3，fixed 6）；专属信物暂不挂（随 T4/T7 内容扩充）；**战利品遵循 T32（BOSS 主题武器掉落规则）：弱火 BOSS 掉火系主题武器**。

## 6. 实现步骤（零核心代码改动：`on_damaged` 钩子与 `enemy_deal_damage` 闸口均已存在）

| 步骤 | 内容 | 改动文件 | 验证点（F6） |
|---|---|---|---|
| Step 1 · gimmick 脚本 | `glass_cannon_gimmick.gd`：on_room_start 开场日志；on_damaged 反弹 = min(cap, ratio×dmg) 走 `ctrl.combat.enemy_deal_damage`；enemy_hp ≤ 0 不反弹；读 gimmick_params（空则回落默认 0.15/5，行为同 T24 新规） | `scripts/battle/gimmicks/glass_cannon_gimmick.gd` | 受击后「石屑反弹 -X」、护盾可挡、击杀一击不反弹 |
| Step 2 · 房间 .tres | 石像鬼房：165/22/8 · ice · kind=boss · act=1 · boss_role=rotating · intents(attack 40 / heavy 60) · gimmick_params(0.15/5) · boss_reward_weapons（火系主题池，T32） | `resources/rooms/` 新增 | 4 选 1 可抽到（rotating 权重 3）、heavy 偏置生效 |
| Step 3 · 文档回写 | 总清单 T4 BOSS 池 3/12→4/12 | `docs/未完成任务_总清单.md` | — |
| Step 4 · F6 验证 | 见 §7 清单 | — | 全绿 |

## 7. F6 验证清单

- [x] 石像鬼以 rotating 候选进入 Act1 BOSS 槽（60 局抽取分布 20/60 ≈ 33%，与权重 6:3 吻合）
- [x] 意图 heavy 偏置（attack 40/heavy 60）数据层加载正确（HUD 预告显示待实机确认）
- [x] 反弹 = min(5, 总伤×15%)（单测：20 伤→3、40 伤→5 封顶）；走 enemy_deal_damage 闸口 → 护盾可挡
- [x] 击杀一击不反弹（enemy_hp ≤ 0 单测通过）
- [ ] 强袭/充能/三连抢杀可行（实机手感待验）
- [ ] 火克制 ×1.5/×1.7、MISS 规避正常（同全局，实机待验）
- [ ] 通关 → 训练点 +1 → 训练房 → 商店/下一房（实机待验）
- [x] BOSS 战利品为火系主题武器池（fire_sword / flame_staff / iron_sword，T32 规则）

## 8. 关联

- 总清单 **T10**（BOSS 阶段化总纲·Act1 单阶段轮替示例）、**T24**（gimmick 参数化新规）、**T4**（BOSS 池 3/12→4/12，目标 12）、**T25**（`run_boss_weights` rotating 3 / `RoomData.boss_role`）、**T32**（BOSS 主题武器掉落规则）
- 结构参照：BOSS_冰封铁瓮_设计.md（固定首领·教学位）；本 BOSS 为非教学位轮替内容
