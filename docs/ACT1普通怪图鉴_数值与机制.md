# ACT1 普通怪图鉴：数值与机制

> 数据来源：`resources/rooms/*.tres`（`act=1` 且 `kind=normal`）、`resources/archetypes/*.tres`、`scripts/battle/gimmicks/normal_trait_gimmick.gd`、`scripts/battle/run_setup.gd`、`scripts/systems/balance_config.gd`（`resources/config/balance_config.tres`）、`resources/intents/*.tres`。
> 核对日期：2026-11-17。

---

## 一、总体规则

### 1.1 候选池与出场

- ACT1 普通怪**候选池共 12 只**。每局 ACT1 从池中随机抽 **5 只**上场（`balance_config.tres` 的 `run_act_layout = [normal×5, elite×2, boss×1]`），打乱后逐个取用，所以同一局不会重复遇到同一只。
- 图鉴列的是全部 12 只候选；一局只会见到其中 5 只。
- 12 只每只**只配 1 个特性**（`gimmick_params.trait`），不叠加；触发点固定在「入场 / 首次转轮前 / 首次受击 / 首次破甲 / 周期 / HP 阈值」。

### 1.2 数值构成

实际进战斗的数值按以下规则计算（`duel_controller.gd:1098-1111`）：

```
HP   = round(基础HP × hp_scale)
ATK  = round(基础ATK × atk_scale)
护甲 = round(基础护甲 × hp_scale)   // 基础护甲为 0 则无护甲
```

- **基础值**：房间资源 `hp/atk/armor` 字段；若为 0，则取行为族（archetype）的 `hp_base/atk_base/armor_base`。
- **ante 缩放**（`run_setup.gd:86`，用 `balance_config.tres` 实际值）：
  - `hp_scale = 1.75^(act-1) × 1.15^ria`
  - `atk_scale = 1.30^(act-1) × 1.06^ria`
  - ACT1 的 `act-1 = 0`，故 **ACT1：`hp_scale = 1.15^ria`，`atk_scale = 1.06^ria`**
  - `ria` = 本房之前与本房同幕的房间数（幕内序号，0 起）。ACT1 房间顺序为 5 normal → 2 elite → boss，所以普通怪的 `ria` 通常为 0~4。
- 因此下表中的 ATK/HP 是**基础值（ria=0 时的近似值）**，实际随出场顺序递增（第 5 只约为 HP ×1.75、ATK ×1.26）。

### 1.3 元素与意图

- **元素**：单向克制——玩家符号元素 → 敌人元素。下列元素即敌人的被克制属性。
- **意图权重**：有行为族的 6 只用各自 `intent_weights`；无行为族的 6 只用 ACT1 normal 默认表 `attack 75 / heavy 25`（`status_system.gd:ACT_INTENT_WEIGHTS`）。
- **意图效果**（`resources/intents/*.tres`）：
  - `attack 攻击`：造成 ATK ×1.0 伤害
  - `heavy 重击`：造成 ATK ×2.0 伤害
  - `jam 注废`：注废一列（可净化）
  - `lock 锁轮`：锁定一列符号（可净化）
  - `chaos 乱权`：转轮注入 20% 废铁（可净化）
  - `auto_stop 夺轮`：下轮自动停轮 + 注入 1 列废铁（可净化）

---

## 二、12 只普通怪总表

下表中「基础 HP/ATK/护甲」为 ante 缩放前的值。带 `*` 的行为族数值由 archetype 提供（房间字段 hp=0）。

| #   | 名称    | 元素  | 行为族               | 基础HP | 基础ATK | 基础护甲      | 特性                                | 意图权重来源                                                 |
| --- | ----- | --- | ----------------- | ---- | ----- | --------- | --------------------------------- | ------------------------------------------------------ |
| 1   | 重锤蛮兵  | 无   | 重击者 heavy_brawler | 140* | 16    | 0         | `charge` 入场蓄力，下一次行动改重击            | attack 60 / heavy 40                                   |
| 2   | 毒壳壁垒  | 毒   | 壁垒 bulwark        | 170* | 12    | 0 + 特性补20 | `shell` 入场 +20 护甲，破甲后不再补          | attack 70 / heavy 30                                   |
| 3   | 窃语咒师  | 无   | 干扰者 jammer        | 90*  | 12    | 0         | `jam_open` 首次转轮前第 1 列注废（一次）       | attack 35 / jam 25 / lock 25 / auto_stop 15            |
| 4   | 辉光游侠  | 光   | 游侠 striker        | 100* | 13    | 0 + 特性补10 | `first_hit_ward` 首次受击后 +10 护甲（一次） | attack 60 / heavy 20 / jam 10 / lock 10                |
| 5   | 冰锋群蝠  | 冰   | 群冲 swarmer        | 55*  | 10    | 0         | `frost_open` 首回合冻结 1 列，次回合自消      | attack 100                                             |
| 6   | 暗影诡匠  | 暗   | 诡匠 trickster      | 95*  | 14    | 0         | `lock_open` 首次转轮前锁定 1 列符号         | attack 25 / jam 20 / lock 20 / chaos 20 / auto_stop 15 |
| 7   | 裂石像   | 光   | 无                 | 95   | 12    | 16        | `break_skip` 首次破甲后下一次行动失效         | ACT1 默认 attack 75 / heavy 25                           |
| 8   | 锈盲蝠   | 冰   | 无                 | 75   | 10    | 0         | `rust_jam` 首次受击后下一轮注废 1 列（一次）     | ACT1 默认                                                |
| 9   | 腐化史莱姆 | 毒   | 无                 | 90   | 13    | 12        | `poison_hit` 首次受击使玩家中毒 1 层（一次）    | ACT1 默认                                                |
| 10  | 余烬傀儡  | 火   | 无                 | 85   | 12    | 0         | `ember_heal` 每回合首次受火伤回复 6 HP      | ACT1 默认                                                |
| 11  | 寒鳞蝠   | 冰   | 无                 | 80   | 10    | 0         | `frost_hit` 每次受击自身 +1 层霜（减攻）      | ACT1 默认                                                |
| 12  | 毒孢菌   | 毒   | 无                 | 80   | 12    | 10        | `spore` HP 首次 <50% 时使玩家中毒 2 层（一次） | ACT1 默认                                                |

> 说明：护甲栏「0 + 特性补N」表示该怪房间本身无护甲，护甲由特性的 `on_room_start` 追加（`shell`/`first_hit_ward`），且追加后再乘 `hp_scale`。

---

## 三、特性机制详解

全部来自 `normal_trait_gimmick.gd`。设计纪律：每只 1 个特性；不加锁血 / 强制复活 / 阶段变化 / 固定伤害上限；只改本房临时状态，不随玩家 Build 动态调值；提示与计时确定性，不消耗 RNG。

| 特性 | 怪物 | 触发点 | 实际效果 |
|---|---|---|---|
| `charge` | 重锤蛮兵 | 入场 | 下一次行动改为重击（ATK ×2），之后恢复普通攻击 |
| `shell` | 毒壳壁垒 | 入场 | `enemy_armor` 与 `enemy_armor_max` 各 +20（参数 `armor=20`），破甲后不再补充 |
| `jam_open` | 窃语咒师 | 首次转轮前 | 第 1 列（参数 `column=0`，0 起）注废，仅一次 |
| `first_hit_ward` | 辉光游侠 | 首次受击后 | 获得 10 护甲（参数 `ward=10`），仅一次，**不挡当次伤害** |
| `frost_open` | 冰锋群蝠 | 首回合 | 冻结 1 列，次回合自消；清净药剂可当回合解除 |
| `lock_open` | 暗影诡匠 | 首次转轮前 | 锁定 1 列当前符号，仅一次 |
| `break_skip` | 裂石像 | 首次破甲 | 下一次行动失效（给出集中输出窗口） |
| `rust_jam` | 锈盲蝠 | 首次受击 | 下一轮注废 1 列，仅一次，净化可解 |
| `poison_hit` | 腐化史莱姆 | 首次受击 | 玩家中毒 1 层（参数 `stacks=1`），仅一次，清净可解 |
| `ember_heal` | 余烬傀儡 | 每回合首次受火伤 | 回复 6 HP（参数 `heal=6`）；换元素或集中爆发可绕过 |
| `frost_hit` | 寒鳞蝠 | 每次受击 | 自身 +1 层霜（敌人霜 = 减攻），可连续小攻击削弱 |
| `spore` | 毒孢菌 | HP 首次 <50% | 玩家中毒 2 层（参数 `hp=0.5, stacks=2`），仅一次 |

**玩家侧 DoT 结算**（`poison_hit` / `spore` 施加的中毒）：在玩家回合开始结算，每层按 `poison_base` 点（默认 2）、每回合 -1 层，走 `enemy_deal_damage` 唯一闸口（护盾可挡、飘字/动画自动），清净药剂可清零。

---

## 四、行为族基准数值对照

6 只带 archetype 的怪，房间 `hp=0` 时取下列基准（`atk` 房间有写死值则覆盖基准）：

| 行为族 | display_name | hp_base | atk_base | armor_base | intent_weights |
|---|---|---|---|---|---|
| heavy_brawler | 重击者 | 140 | 14 | 0 | attack 60 / heavy 40 |
| bulwark | 壁垒 | 170 | 10 | 0 | attack 70 / heavy 30 |
| jammer | 干扰者 | 90 | 10 | 0 | attack 35 / jam 25 / lock 25 / auto_stop 15 |
| striker | 游侠 | 100 | 11 | 0 | attack 60 / heavy 20 / jam 10 / lock 10 |
| swarmer | 群冲 | 55 | 9 | 0 | attack 100 |
| trickster | 诡匠 | 95 | 12 | 0 | attack 25 / jam 20 / lock 20 / chaos 20 / auto_stop 15 |

> 注意：房间字段的 `atk` 均大于行为族 `atk_base`，实际以房间值为准（例如重锤蛮兵房间 atk=16，覆盖基准 14）。

---

## 五、数据一致性备注

- `mechanic_summary`（房间资源里的展示摘要）**只影响 UI 显示，不参与结算**；`room_data.gd` 注明其内容必须与 `gimmick_params` 保持一致。本表机制一栏以 `gimmick_params` + 脚本实现为准，与摘要一致。
- 意图权重表有优先级：`RoomData.intents`（显式表）> 行为族 `intent_weights` > `ACT_INTENT_WEIGHTS` 按幕默认表。ACT1 的 12 只均未填 `RoomData.intents`，故按各自行为族或默认表。
- 若后续调整 `balance_config.tres` 的 `ante_*` 系数，第二章的「基础值」不变，但实际战斗数值会按 1.2 节公式变化。
