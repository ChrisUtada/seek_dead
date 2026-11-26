# 四级品质战利品 · Step 4 · 同层三选一与冻结 payload（2026-11-13）

> 依据：`docs/四级品质战利品与大奖池_分步执行计划_2026-11-12.md` §2.3、§4.2、§4.3、Step 4
> 范围：实现「一次定层 → 同层候选 → 恰好三项 → 展示前冻结」的生成器，并支持重抽与跳过；
> 本步不替换现有战后三槽 UI，来源接入与界面收口分别在 Step 5 / Step 7。

---

## 1. 完成范围

| 改动 | 位置 | 结果 |
|---|---|---|
| 新增同层三选一生成器 | `scripts/systems/loot_offer.gd` | 一次定层、同层 3 项、用途覆盖、转化补齐、冻结 payload |
| 候选池补同层接口 | `scripts/systems/loot_pool.gd` | `roll_quality` / `tier_items` / `pick_n` / `entry_of` |
| 奖励系统入口 | `scripts/systems/reward_system.gd` | `build_loot_offer` / `reroll_loot_offer` / `loot_offer_skip` |
| 同层转化数值配置化 | `BalanceConfig.loot_conversion_gold / loot_conversion_power / loot_skip_gold` | 策划可在 Inspector 调表 |
| 新增第 43 套回归 | `tests/loot_offer_test.gd` | 34 项断言 |

---

## 2. 生成规则

```text
来源 + 幕次
→ 抽一次品质（LootSourceTable，专用 RNG）
→ 取该品质层全部合法候选（source_tags / act / 类别 / 主题 / 排除）
→ 去重路径、尽量去重 unique_group
→ 取至多 3 项；不足 3 项用同层转化补齐
→ 保证至少两种决策用途
→ 冻结物品、授予方式、转化数值、跳过收益
```

**用途口径**：普通物品用 `role`；同为 `damage` 时按 `family_tags` 细分（火焰 / 冰霜 / 暗影…），
避免三把同族武器被当成三种选择。转化项用途固定为 `resource`（金币）或 `damage`（强化）。

**同层补齐**（不跨品质）：

| 品质 | 金币转化 | 伤害强化 | 跳过金币 |
|---|---:|---:|---:|
| common | 6 | +1 | 4 |
| uncommon | 10 | +2 | 7 |
| rare | 18 | +3 | 12 |
| epic | 30 | +4 | 20 |

转化使用现有通道：金币走 `gold`，强化走 `run_power_bonus`，不新增货币。

---

## 3. 冻结内容

| 字段 | 冻结值 |
|---|---|
| `quality` | 本组品质层；重抽不改变 |
| `options[].path` | 具体物品路径 |
| `options[].grant` | `item`（正常授予）或 `gold`（重复/满槽转金币） |
| `options[].gold` | 重复/溢出的金币数值 |
| `options[].needs_replace` | 武器槽满时新武器必须走替换流程 |
| `options[].title/desc/tooltip` | 展示文案（含真实机制摘要） |
| `skip` | 跳过时的同层固定金币与文案 |

重复判定只看**本局状态**：已装备武器 / 已带护符 / 腰带满 / 护符槽触顶。
图鉴已解锁但本局未装备的物品仍是正常候选（§4.3）。

重抽（`reroll`）只重新抽同层候选并优先避开上一组路径，品质层与跳过收益保持不变。

---

## 4. 出口自检

| 出口项 | 状态 | 证据 |
|---|---|---|
| 每组奖励均为同层且恰好三个有效选项 | ✅ | 第 43 套：normal/elite/boss × act1–3 共 360 组，全部 3 项、同品质 |
| 不出现同路径重复 | ✅ | 360 组路径重复 0 |
| 不出现空名称 / 空效果 | ✅ | 每项标题、描述非空；每项 `grant` 或转化值 > 0 |
| 至少覆盖两种用途 | ✅ | 用途键去重 ≥2；同层分组充足时 unique_group 不重复 |
| 满槽 / 空主题池有合法出口 | ✅ | 腰带满、护符槽触顶全部转金币；空主题池补 3 项同层转化 |
| 全收集不剔除本局候选 | ✅ | 图鉴已解锁未装备 → 仍为物品候选 |
| 重抽不改变品质 | ✅ | 30 次重抽品质与物品 rarity 均不变 |
| 跳过的转化与展示一致 | ✅ | `skip` 在 build 时冻结，重抽不变；展示值 = 配置值 |
| 生成不消耗地图 RNG | ✅ | 200 次生成前后全局 `randi()` 相同 |

---

## 5. 全量回归

| 项 | 结果 |
|---|---|
| 套件数 | 43 |
| 全量结果 | ✅ **43 / 43 ALL GREEN**（`[smoke] RESULT: ALL GREEN`，退出码 0） |
| 第 4 套 | `SMOKE|RESULT PASS (checks=2567 fails=0)` |
| 第 43 套 | `LOOTOFFER|RESULT PASS (checks=34 fails=0)` |
| 日志 | `docs/baseline/2026-11-13_loot_step4/smoke.out.log` |

---

## 6. 复现

```text
run_smoke.bat
Godot_v4.7-stable_win64_console.exe --headless --fixed-fps 60 --path . res://tests/loot_offer_test.tscn
```

---

## 7. 已知影响与下一步

- 本步只实现生成器，**现有战后三槽屏仍是旧流程**；同层三选一尚未替换玩家可见奖励界面。
- Step 5 负责把普通 / 精英 / BOSS / 探索来源接到 `build_loot_offer`，并实现确认后的发奖结算（进槽 / 替换 / 腰带 / 金币 / 强化）。
- Step 7 负责奖励界面的重抽、跳过、替换与转化状态展示。
- 转化数值（金币 / 强化 / 跳过）是模拟起点，Step 8 大样本再调；本步不改任何战斗数值。
- 「满血」出口在本步不触发：战利品候选是物品（武器 / 护符 / 消耗品），不生成纯治疗奖励卡；
  纯治疗卡的满血过滤仍由旧奖励路径负责，Step 7 收口时统一。
- Step 6 已把「本局已装备武器的重复候选」从同层金币改为同层熟练转化；本文件 §3/§4 中
  「重复装备 → 金币」的描述是 Step 4 时点行为，以 Step 6 说明为准。
