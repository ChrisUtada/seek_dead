# ACT1 试玩 Demo · 制作规划与内容整理

> 状态：**2026-08-14 规划定稿（待执行）**。目标：可交付的 ACT1 完整试玩（≥1 小时游玩），供内部/朋友验证核心闭环。
> 原则：**主工程即 demo 工程**——不新建工程，用配置开关（demo_act_only）+ 内容白名单（demo_config）+ git 标签快照 + 独立导出 preset 实现（避免双代码库同步成本）。
> 关联：项目概览（现状）、装备全览（全量 92 件）、BOSS全览（ACT1 四席）、未完成任务总清单（§11.3 课程化）。

---

## 1. 目标与验收标准

> **时长依据（2026-08-14 流程时长模拟，脚本 `act1_time_sim.py` 基于真实房间/族数值 + 代码动画常量）**：
> 单轮 ACT1（8 房）纯战斗 41 回合 ≈ 3.5 分钟（人类中速）+ 非战斗开销 ≈ 5 分钟 = **单轮约 8-9 分钟**；
> 新手轮（读意图/试错/死亡重开）12-15 分钟。**1 小时 = 4-5 轮**（教学轮 → 熟悉轮 → 2-3 轮构筑/全 BOSS 收集轮），
> 时长由**多轮吸引力**撑起（4 BOSS 抽 2 + 隐秘 14% 需多轮见全、铁砧图鉴进度、13 武器构筑组合），而非单轮拉长。

| 维度 | 标准 |
|---|---|
| 时长 | **≥60 分钟** = 4-5 轮完整 ACT1（教学摸索含死亡 → 熟悉 → 2-3 轮构筑/收集）；单轮 ≈ 8-15 分钟 |
| 阻塞 | 无崩溃/卡死/数值崩坏；F6 全流程零报错（含 gimmick intents、锁轮/干扰、训练移除后节奏） |
| 循环 | 整备 → 转轮目押 → 元素克制 → 破甲/状态 → 奖励 → 商店 → BOSS 战利品 → 铁砧跨局 → 重开全闭环 |
| 内容 | 四类装备开放量 ≈ **50 件**（全量 92 的 54%），构筑面足够 4-5 轮不重复 |
| 多轮钩子 | 全 BOSS 体验（4 席抽 2 + 隐秘）· 铁砧图鉴进度 · 构筑组合探索——撑 1 小时的三个来源 |
| 教学 | ACT1 课程化生效（普通教子机制 → 精英弱化 → BOSS 合成验收） |

## 2. ACT1 敌人元素分布（内容裁剪依据，实测）

| 房型 | 元素分布 |
|---|---|
| 普通 ×12 | ice×3（寒鳞蝠/冰锋群蝠/锈盲蝠）· poison×3（毒壳壁垒/腐化史莱姆/毒孢菌）· light×2（辉光游侠/裂石像）· none×2（重锤蛮兵/窃语咒师）· fire×1（余烬傀儡）· dark×1（暗影诡匠） |
| 精英 ×4 | ice×2（寒铁精英/酸蚀傀儡）· poison×2（毒疫术士/腐殖巨蠕） |
| BOSS ×4 | ice×3（铁瓮/石像鬼/茧居）· poison×1（酸蚀恶鬼） |

**元素解硬需求**：火（克冰系 3 BOSS + 冰怪）、光（克酸蚀 + 毒怪）、冰（克余烬傀儡）；毒/暗为流派可选。

## 3. 内容裁剪清单（50 件）

### 3.1 武器：24 → **13**

| 元素 | 保留 | 剔除（理由） |
|---|---|---|
| 火 3→2 | fire_sword（rare 主）、flame_scimitar（uncommon） | flame_staff（epic——留作后续内容，demo 1 把 epic 武器足够引导收集欲？否——epic 武器剔除） |
| 冰 4→2 | frost_blade（rare）、ice_gun（rare） | ice_staff / frost_lance（同类冗余） |
| 毒 1→1 | poison_dagger | — |
| 光 5→2 | holy_sword（rare）、dawn_bow（uncommon） | dawn_blade / holy_lance / holy_mace（冗余） |
| 暗 6→2 | night_scythe（rare）、shadow_dagger（uncommon） | shadow_guillotine / sin_blade / judgment_greatsword / abyss_scythe（Act2/3 关联） |
| 无 5→4 | battle_axe（破甲核心）、iron_sword（底池）、pistol（暴击）、dagger（新手） | armor_pierce_crossbow（穿甲流留后续） |

**解 BOSS 能力**：铁瓮/石像鬼/茧居 → 火武 ×1.5；酸蚀 → 光武 ×1.5；破甲（battle_axe 三连清甲打铁瓮/石像鬼）。

### 3.2 技能：17 → **10**（覆盖全部 buff effect 类型）

| 类型 | 保留 |
|---|---|
| power | rage（+3）、focus（+6） |
| shield | calm（+8）、war_banner（+6） |
| heal / regen | recovery（三连 5×溢出转盾）、shadow_regen（+6/回合） |
| damage_mult | fire_breath（×1.3） |
| damage | flame_mark（fire 9）、magic_bolt（light 9） |
| status | ember（燃 DoT） |

剔除 7：haste、nightmare_gaze、atonement_mark、aura_of_order、nightmare_veil、atonement_light、holy_verdict——均为 Act2/3 BOSS 关联或冗余档位。

### 3.3 护符：22 → **13 普通 + 4 信物 = 17**

| effect | 保留（普通池） |
|---|---|
| damage_mult | sharp_charm（×1.1）、rage_charm（×1.5） |
| shield | guard_charm、bulwark_charm |
| room_shield | ward_charm |
| heal | regen_charm |
| interference_resist | resist_charm、mirror_charm |
| armor_pierce | pierce_charm |
| damage_bonus | rust_relic |
| element_boost | element_charm |
| status_boost | status_charm |
| dot_reduce | **poison_ward**（酸蚀对策核心） |

**BOSS 信物（4 个，全部保留）**：frost_core（铁瓮）/ stone_shard（石像鬼）/ venom_gland（酸蚀）/ rhythm_shell（茧居）——BOSS 战利品激励是 demo 核心钩子。
剔除 9：abyss_relic / scales_of_judgment / counter_shield / frost_bulwark / abyss_bulwark / soul_soothe / redemption_heart / whisper_relic / crush_seal。

### 3.4 消耗品：17 → **10**

| 类型 | 保留 |
|---|---|
| heal | heal_potion（30）、holy_grail（60） |
| assault | assault_potion（×2）、lava_burst_potion（×3） |
| reroll | reroll_scroll |
| purify | purify_potion |
| cleanse | cleanse_potion |
| 精华 | fire / ice / poison（ACT1 三元素） |

剔除 7：atonement_water / holy_burst / absolution_decree / recaster_storm / purge_water / light_essence / dark_essence。

### 3.5 合计

| 类 | 全量 | demo | 说明 |
|---|---|---|---|
| 武器 | 24 | **13** | 每元素 1-4 把，解 BOSS 全覆盖 |
| 技能 | 17 | **10** | 全部 buff 类型 ≥1 |
| 护符 | 34 | **17** | 全 effect 类型 ≥1 + 4 信物 |
| 消耗品 | 17 | **10** | ACT1 三元素精华 |
| **合计** | **92** | **50** | 54%——够玩不冗余 |

## 4. Demo 模式实现（主工程内，分钟级改动）

| 项 | 实现 | 文件 |
|---|---|---|
| 只跑 ACT1 | `DemoConfig.act_only = 1` 时 `_build_run` 用 `run_acts = 1`（`BALANCE.run_acts` 运行时替换） | duel_controller `_build_run` |
| 内容白名单 | 新增 `DemoConfig` 资源（`resources/config/demo_config.tres`）：act_only + weapon_pool / skill_pool / charm_pool / consumable_pool 四数组（50 条路径） | 新增 demo_config.gd/.tres |
| 池过滤 | 开关开启时：`seed_default_owned`（种子）、`roll_shop`（货架）、`_anvil_pool`（铁砧）、SKILL_POOL 扫描处均改为白名单子集 | meta_store / shop_system / anvil_system / duel_controller |
| 导出 preset | Godot 多 preset：demo（标题"Seek Dead · ACT1 DEMO"、独立图标/命名） | project.godot |
| 版本快照 | 验收通过 → `git tag demo-act1-v1.0` | git |

## 5. 制作流程（阶段 0-4）

### 阶段 0：全流程验收（先做，产 bug 清单）
- 内容：F6 完整跑 ACT1 数轮 + 战败重开 + 元进度
- 验证点：训练移除后节奏（奖励屏→商店零报错）· 锁轮金框不转 · 干扰红框 · 7 BOSS P2/P3 意图无 Invalid assignment · HP 跨局 100/100 · 信物三处过滤 · 灌注只命中 damage
- 产出：阻塞 bug 清单 → 修到零阻塞

### 阶段 1：Demo 模式实现
- 内容：DemoConfig 资源 + 4 处池过滤 + act_only 开关（§4）
- 验证：开关开 → 只 ACT1 房、商店/铁砧/种子只出 50 件白名单、整备可勾选面正确
- 产出：demo 模式可切换，正常模式零影响

### 阶段 2：内容落地 + 课程化复核
- 内容：白名单 50 件核对（§3 表逐件）· ACT1 6 非 BOSS 房课程化复核（普通 A 教元素 / 普通 B 异源 / 精英 mini-gimmick，总清单 §11.3 的 ACT1 部分）· 商店供给（火/光武可购、清净/净化可购）
- 验证：F6 一轮全通：BOSS 可解（火/光/破甲/清净/净化渠道畅通）、难度曲线合理（铁瓮 ante 后 ≈530 HP 击杀回合数可接受）
- 产出：内容与教学闭环

### 阶段 3：打磨（按体验影响排序）
1. 战斗反馈：飘字覆盖（克制/破甲/状态/护符/信物全链路）+ 击杀溶解动画（T9 `play_kill` 挂接）
2. 新手引导：第一局 3 屏（转轮目押 / 克制 ×1.5 / 破甲三连）——ACT1 是教学幕但缺引导文案
3. 结算可读性：伤害分解从 Debug.log 升级到战斗日志面板（可选）
- 验证：新玩家不看代码能理解"为什么这么打"

### 阶段 4：交付
1. 试玩说明（docs/ACT1试玩说明.md）：给测试者 1 页纸（见 §6 模板）
2. 导出 demo preset 构建
3. `git tag demo-act1-v1.0` + 推送（含 tag）
4. 测试者反馈收集模板：阻塞 bug / 时长 / 难度 / 最爽与最怪时刻

## 6. 试玩说明模板（随 demo 交付）

```
# Seek Dead · ACT1 试玩
版本：demo-act1-v1.0 ｜ 时长：≥60 分钟（4-5 轮）

怎么玩
- 转轮目押：空格旋转，点击/空格逐列停——停到同符号 = 连线倍率，三连必暴
- 元素克制：火克冰 / 光克毒 / 冰克火（×1.5）——敌人弱点在右侧面板
- 破甲三连：带破甲标记的武器（战斧/铁剑）三连清空护甲
- 状态：燃(DoT)/霜(减攻)/毒(DoT) 挂层即扣

BOSS 应对（ACT1 四席）
- 冰封铁瓮（固定）：叠甲+冻结 → 火武×1.5 + 破甲三连 + 清净解冻结
- 碎裂石像鬼（轮替）：反弹 → 护盾流或速杀
- 酸蚀恶鬼（轮替）：挂毒爆炸 → 光武 + 清净/蚀毒壁垒
- 茧居石雕（隐秘·14%）：开合节律 → 攒爆发打开合窗口

收集
- 铁砧：跨局抽装备（每轮结束可用）——4 个 BOSS 信物是专属收集目标
- 死亡/通关 → 整备重选，构筑自由

已知限制
- 仅 ACT1 内容开放；商店/铁砧/整备只出 demo 池 50 件
- 请反馈：阻塞 bug / 手感 / 时长 / 最爽与最怪时刻
```

## 7. 风险与预留

| 风险 | 应对 |
|---|---|
| 1 小时不够/太长 | 模拟基线：单轮 8-9 分钟（熟练）/ 12-15 分钟（新手含死亡）；若 5 轮仍不足 1 小时，补多轮钩子（全 BOSS 体验/图鉴进度/构筑组合）；若单轮 >20 分钟，调 `ante_room_step_hp` 或减课程化房数 |
| 50 件构筑面不足 | 最小补量：+2 武器（dawn_blade/holy_lance）+1 护符（counter_shield）——白名单数组即加即生效 |
| 难度失衡 | ACT1 ante ≈ ×2.66；若铁瓮击杀回合 >12 或玩家暴毙率 >50%，调 base 数值（balance_config 零代码） |
| demo 与主工程漂移 | demo 只靠配置隔离（无代码分叉）——开关关闭即完整 3 幕 |
