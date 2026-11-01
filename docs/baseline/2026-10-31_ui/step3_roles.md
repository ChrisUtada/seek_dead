# 战斗 UI 重构 · Step 3 样板角色风格化（2026-10-31）

> 依据：`docs/战斗UI重构_执行方案与AI任务书.md` §6 Step 3
> 范围：只做「灰白玩家 + 红色 BOSS」两个样板，**不覆盖任何原始素材**，不改战斗数值/动画时序/房间机制
> 截图：`docs/baseline/2026-10-31_ui/step3/`（同工具、同流程，可与 `before/`、`after/`、`step2/` 对照）

---

## 1. 任务书条目对照

| 任务书 Step 3 条目 | 处理 |
|---|---|
| ① 玩家立绘另存灰白版，不覆盖原图 | 输入改用实机素材 `assets/characters/viking/`（见 §0 核对备注 ③，非 `knight1.png`），输出新目录 `assets/characters/viking_ash/`；`viking/` 原图零改动（`git status` 无记录） |
| ② `bossbf.png` 另存红色版，不覆盖原图 | 输出 `assets/bossbf_ember.png`；`assets/bossbf.png` 零改动 |
| ③ 少量色阶、保留透明背景与 48×48 | 亮度分档重映射到 **6 阶色板**；尺寸 48×48、alpha 通道原样保留（半透明边缘不清除、不填实） |
| ④ 灰白版接入战斗 HUD | `battle_hud.tscn` 默认贴图 + `battle_animator.gd` 站立/攻击帧列表全部指向 `viking_ash/` |
| ⑤ 红色 BOSS 经 `RoomData.art` 接入冰封铁瓮 | `resources/rooms/frozen_urn.tres` 的 `art` 指向 `bossbf_ember.png`（数据驱动，无代码分支） |
| ⑥ 体量差优先整数倍率并验证舞台空间 | `art_scale` 2.0 → **2.25**：64×2.25 = **144 = 48×3（整数 3×）**；原 128 = 2.667× 为非整数倍率。实测舞台 286×235，144 不压转轮与右栏 |
| ⑦ 红色敌人受击改暖白闪/反相 | 现网 `battle_animator.gd:88` 已是暖白 `Color(1.75,1.70,1.55)`（M3-02 改过），本步实测确认在红 BOSS 上可见，无需改动 |

## 2. 改动 / 新增清单

| 文件 | 类型 | 说明 |
|---|---|---|
| `tools/art_pipeline/stylize_sample.py` | 新增 | 可复现的风格化脚本：亮度分档 → 6 阶色，只读原图、只写新文件 |
| `assets/characters/viking_ash/idle_01..04.png` | 新增 | 灰白玩家站立 4 帧（48×48） |
| `assets/characters/viking_ash/attack_01..05.png` | 新增 | 灰白玩家攻击 5 帧（48×48） |
| `assets/bossbf_ember.png` | 新增 | 红色 BOSS（48×48） |
| `scripts/ui/battle_animator.gd` | 修改 | 9 条 `preload` 路径 `viking/` → `viking_ash/`；**帧数、帧长、命中帧索引、缓动均未改** |
| `scenes/ui/battle_hud.tscn` | 修改 | `4_knight` ext_resource 指向 `viking_ash/idle_01.png`（节点/尺寸不变） |
| `resources/rooms/frozen_urn.tres` | 修改 | `art` → `bossbf_ember.png` 并移除失效 uid；`art_scale` 2.0 → 2.25 |

未改：`combat_system.gd`、`balance_config.tres`、任何成长/奖励/铁砧/房间数据；`ENEMY_SPRITE_SIZE`、舞台/栏宽/转轮尺寸；原始 `viking/` 与 `bossbf.png`。

## 3. 色阶设计

按**感知亮度**（`0.299R + 0.587G + 0.114B`）分档重映射，保留原图明暗结构、丢弃原始色相。档位上限按实测亮度分布校准，避免暗部糊成一块：

| 阶 | 玩家 ASH 上限 → 色 | BOSS EMBER 上限 → 色 |
|---|---|---|
| 1 | 0.10 → `#242221` | 0.08 → `#3A1216` |
| 2 | 0.22 → `#454240` | 0.20 → `#5E1A1F` |
| 3 | 0.36 → `#6D6965` | 0.34 → `#7E262C` |
| 4 | 0.52 → `#9A9690` | 0.50 → `#9E3438`（敌人暗红 `#8C3438` 附近） |
| 5 | 0.70 → `#C8C4BD` | 0.68 → `#C0474A` |
| 6 | 1.01 → `#EFEBE2` | 1.01 → `#E35B50`（任务书敌人红） |

色数：玩家 `idle_01` 13 色 → **5 色**（其它帧相近）；BOSS 435 色 → **6 色**。
透明度核对：9 张玩家帧 + BOSS 的 alpha 通道与原图**逐像素一致**（脚本比对 `alpha_same=True`），尺寸均为 48×48。
重生成：`python tools/art_pipeline/stylize_sample.py`（确定性输出，无随机）。

## 4. 实测数据

| 项 | Step 2 | Step 3 | 说明 |
|---|---|---|---|
| 玩家立绘 | `viking/idle_0x.png` 96×96（2×） | `viking_ash/idle_0x.png` 96×96（2×） | 尺寸不变，仅配色 |
| BOSS 立绘 | `bossbf.png` **128×128**（2.667×，非整数） | `bossbf_ember.png` **144×144**（**3×** 整数） | 与玩家 2× 形成 1.5× 体量差 |
| 中央舞台 | 286×235 | 286×235 | 未变；BOSS 显示框 144×144（逻辑 y 50–194），转轮框顶 y=198 → 框底间隙 4px；实际像素下沿 y≈178.5，像素间隙 ≈19.5px |
| 左/右栏 | 88 / 88 | 88 / 88 | 未变 |
| BOSS 遮挡意图/右栏 | — | 无 | `10_boss_1440.png` 目视通过 |

## 5. 演出验证（真实调用，非摆拍）

采集工具在 BOSS 房直接调用 `hud.animator.play_attack("player","enemy")`，按真实 tween 时序抓两帧：

- `12_attack_flash_960.png`（t≈0.08s）：玩家攻击帧中段 + BOSS 受击**暖白闪**（`modulate ×1.75/1.70/1.55`）。红主体被提亮到偏粉，剪影与面部结构仍可辨——红闪方案在红 BOSS 上会糊成一片，暖白方案成立。
- `13_attack_impact_960.png`（t≈0.21s）：玩家命中帧（`attack_04`，索引 3）+ 闪色回落中；玩家立绘轮廓在灰白配色下仍清晰。

## 6. 验收

- 480×270：`02_battle_960.png`（普通房）、`03_boss_960.png`（BOSS 房）无重叠/裁切；灰白玩家与红色 BOSS 剪影可辨。
- 整数放大：`09_battle_1440.png`、`10_boss_1440.png`、`11_battle_1920.png` 边缘均为整数像素，无插值毛边（BOSS 48→144→×3 屏 = 9× 整数链）。
- 覆盖层（商店/奖励/铁砧/结算/整备）不受立绘改动影响：`01,04,05,06,07` 与 Step 2 一致。
- 转轮滚动中（`08_spin_960.png`）符号、角标、元素色不变。

## 7. 回归结果

`run_smoke.bat`：**13/13 ALL GREEN，exit 0**（Step 3 实跑）

| 套件 | 结果 |
|---|---|
| 1/13 L0 intent act-gating | PASSED 42 / FAILED 0 |
| 2/13 L0 boss loot theme | PASSED 234 / FAILED 0 |
| 3/13 L1 content math lint | PASSED 393 / FAILED 0 |
| 4/13 L2+L3 full-run smoke | PASS（checks=3863, fails=0） |
| 5/13 T8 drop channels | PASSED 20 / FAILED 0 |
| 6/13 T7 acquisition weighting | PASSED 10 / FAILED 0 |
| 7/13 curriculum | PASSED 99 / FAILED 0 |
| 8/13 charge gating | PASSED 8 / FAILED 0 |
| 9/13 M1 reward suite | PASSED 51 / FAILED 0 |
| 10/13 M2 growth | PASSED 51 / FAILED 0 |
| 11/13 M2 weapon mastery | PASSED 41 / FAILED 0 |
| 12/13 M3 binding | PASSED 12 / FAILED 0 |
| 13/13 M4 demo config | PASSED 48 / FAILED 0 |

合计 4872 条断言，0 失败，与 Step 0/1/2 逐套一致。
副作用同前：整局 smoke 改写 `anvil_points`（6899 → 7320），已备份并还原为 6899（文件哈希与备份一致）。

## 8. 已知遗留

- **普通敌人立绘未风格化**：`assets/enemy.png`（默认敌人，64×64 显示）仍是旧的暖橙厚涂，与本步的灰白/红配色并置时偏亮。按任务书 Step 3 范围只做样板角色，普通敌人留待 Step 4 图标/后续敌人批次。
- 玩家立绘仅覆盖 `idle ×4 + attack ×5`；`viking/` 其余 11 帧（hurt/dead 等）当前无调用方，未生成副本。
- 色阶为亮度线性分档，未按元素/材质分区（例如盾牌与皮肤同档），如需更细的角色辨识可在后续按掩码分区。
- BOSS 144 高使显示框下沿贴近转轮框顶（逻辑间隙 4px，像素间隙 ≈19.5px），如后续转轮格再放大需重估 `art_scale`。
