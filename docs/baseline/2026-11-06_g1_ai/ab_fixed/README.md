# 目押 A/B 修复后证据（2026-11-06）

> 对应：`docs/G1_人工验收_执行清单与记录表_2026-11-06_AI回填.md` §4、§5
> 用途：替换 `../ab/` 中 V4/V5 阻塞的旧数据；**仍不是真人验收**。

## 1. 为什么重跑

旧 `../ab/` 在 readable V4 第 7 房胜利后停止推进。复核截图 `../ab/V4_replace.png` 显示：
战后三槽的「构筑」位给了 `武器 · 铁剑`，玩家已满双武器，因此弹出「胜利奖励：替换武器」。
旧驱动在顶层无条件取消该弹层，取消后回到同一三槽屏，又反复点同一张武器卡，形成**驱动层循环**，
不是游戏软锁。旧报告把它记为 `POST_BATTLE_STALL`，现已更正。

驱动修复（`tools/g1_ai_playtest.gd`）：

- 取消替换后，若 `post_battle_active`，改选补给 / 成长；
- 仍无法选择时，走真实「放弃本次成长」入口收尾；
- 普通三槽自动选择失败也有同样兜底，避免任何空候选让驱动空转。

## 2. 结果

| 组 | 局数 | 通关 | 主动按停 | 目标停中 | 三连 | 缓冲 |
|---|---:|---:|---:|---:|---:|---:|
| control | 6 | 0 | 311 | 35（11.3%） | 1 | 0 |
| readable | 6 | 6 | 176 | 176（100.0%） | 58 | 160 |

- control 6 局最远 4–7 房，均在 BOSS 前失败；readable 6 局均 8 房通关。
- readable V4/V5/V6 各出现 1 次 `replace_cancelled`，`auto_pick_failed=0`。
- 10 次停轮核对见 `../audit_fixed/`：control 5/5 视觉中心≠结算，readable 5/5 一致。
  control 的错位与 `lock_reel` 在 `visual_stop/buffer` 关闭时回落到逻辑游标一致；
  AI 零延迟会放大该差异，真人结果仍需 G1-04 复核。

## 3. 文件来源

| 文件 | 来源 |
|---|---|
| `C1..C6.json`、`V1..V2.json` | `driver.log` 全量套件（C1–C6、V1–V2；外层 300s 包装超时在 V2 后终止，不是游戏问题） |
| `V3.json` | `driver_v3.log` 定向重跑 |
| `V4..V6.json` | `rerun_logs/driver_v4.log`、`driver_v56.log` 定向重跑 |
| `summary.json` | 由 12 个单局 JSON 合并；`stop_audit` 取自 `../audit_fixed/summary.json` |

所有单局均为 headless、相同 seed（C1–C6 = 3301–3306，V1–V6 = 4401–4406）、相同预设。

## 4. 复现

```powershell
D:\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe `
  --path . --headless res://tools/g1_ai_playtest.tscn -- `
  --g1-suite=ab --g1-only=V4,V5,V6 --g1-out=ab_fixed_rerun
```

- `--g1-only` / `--g1-out` 为本次新增的驱动参数；默认行为不变。
- 跑测会写 `lobby_data.json`；跑前备份、跑后还原并核对 SHA-256。
