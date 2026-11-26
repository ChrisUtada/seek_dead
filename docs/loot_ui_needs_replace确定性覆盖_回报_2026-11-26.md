# loot_ui needs_replace 覆盖改为确定性两向断言 · 回报（2026-11-26）

> 性质：测试门禁加固（仅 `tests/loot_ui_test.gd`，零生产代码改动）。
> 提交：`73c13f3 test(loot-ui): needs_replace 覆盖改为确定性两向断言`
> 验收：10 次隔离复跑 10/10 PASS，两条新断言各 10/10 命中；`run_smoke` → `SMOKE|RESULT PASS (checks=2062 fails=0)` / `[smoke] RESULT: ALL GREEN`。

## 1. 背景

上一轮把"满槽武器候选标 needs_replace"补成了覆盖，但它依赖成长 Draft 抽样是否抽到 `weapon_*` 候选
（10 次里约 2 次抽到），属于抽样覆盖而非门禁。本轮改为直接调用
`RewardPresentation.definition_to_option(def, ctrl)`（`reward_presentation.gd:36`，public static；
`:58-62` 就地判定 `weapon_effect` + 槽位满 → `needs_replace=true`），用同一个武器 def
跑满槽/空槽两种配装，两向断言互为反证。

## 2. 改动（`_test_replace_flow`，满槽夹具之后）

保留原夹具与 `满槽夹具：配装填满真武器` 断言，其后追加：

```gdscript
# 确定性覆盖（不依赖 Draft 抽样）：同一个武器 def，满槽必须标 needs_replace，空槽必须不标。
# 两向断言互为反证——常量实现无法同时满足。
var wpath := ""
for p in _duel.WEAPON_POOL:
    var s := String(p)
    if s.get_file().contains("_relic"):
        continue
    var d2: Resource = load(s)
    if d2 is WeaponData:
        wpath = s
        break
_check(wpath != "", "确定性覆盖：找到可用武器路径（%s）" % wpath)
var def_w := RewardDefinition.new()
def_w.id = "test_needs_replace"
def_w.name = "测试换装标记"
def_w.rarity = "common"
def_w.effects = [{"effect_id": "weapon_swap", "params": {"weapon_path": wpath}}]
var slot_before := _duel.selected_loadout.size()
var opt_full: Dictionary = RewardPresentation.definition_to_option(def_w, _duel)
_check(slot_before >= cap and bool(opt_full.get("needs_replace", false)),
    "满槽（%d/%d）时武器卡必须标 needs_replace" % [slot_before, cap])
_duel.selected_loadout.resize(cap - 1)
var opt_spare: Dictionary = RewardPresentation.definition_to_option(def_w, _duel)
_check(not bool(opt_spare.get("needs_replace", false)),
    "空槽（%d/%d）时武器卡不得标 needs_replace" % [_duel.selected_loadout.size(), cap])
_duel.selected_loadout.resize(slot_before)   # 复原，别影响后续断言/清理
```

原有 Draft 抽样循环与 `info` 跳过行原样保留，降级为额外集成覆盖（命中与否不影响门禁结论）。

## 3. 验证证据

### 3.1 首跑（`--import` 后）

```text
PASS  确定性覆盖：找到可用武器路径（res://resources/weapon_templates/absolute_zero.tres）
PASS  满槽（2/2）时武器卡必须标 needs_replace
PASS  空槽（1/2）时武器卡不得标 needs_replace
LOOTUI|RESULT PASS (checks=94 fails=0)
```

### 3.2 10 次隔离复跑

| run | RESULT | checks | 满槽（2/2） | 空槽（1/2） |
|---|---|---|---|---|
| 1 | PASS | 93 | PASS | PASS |
| 2 | PASS | 93 | PASS | PASS |
| 3 | PASS | 94 | PASS | PASS |
| 4 | PASS | 94 | PASS | PASS |
| 5 | PASS | 93 | PASS | PASS |
| 6 | PASS | 93 | PASS | PASS |
| 7 | PASS | 94 | PASS | PASS |
| 8 | PASS | 95 | PASS | PASS |
| 9 | PASS | 93 | PASS | PASS |
| 10 | PASS | 93 | PASS | PASS |

- 两条新断言命中率 **10/10 + 10/10**，满足门禁要求。
- checks 分布 93×6 / 94×3 / 95×1，与上一轮 90/91/92 一一对应（+3），
  增量全部来自本轮 3 条固定断言；没有引入新的抽样波动。

### 3.3 全量 smoke

```text
SMOKE|RESULT PASS (checks=2062 fails=0)
[smoke] RESULT: ALL GREEN
```

## 4. 断言数量变化（如实）

| 项 | 变化 |
|---|---|
| 新增（固定） | `确定性覆盖：找到可用武器路径` |
| 新增（固定） | `满槽（%d/%d）时武器卡必须标 needs_replace` |
| 新增（固定） | `空槽（%d/%d）时武器卡不得标 needs_replace` |
| 保留 | 上一轮的 `满槽夹具：配装填满真武器`、Draft 抽样循环与全部既有断言 |

净新增 3 条固定断言；未放宽/删除任何已有断言。

## 5. 提交

```text
73c13f3 test(loot-ui): needs_replace 覆盖改为确定性两向断言
 tests/loot_ui_test.gd | 26 ++++++++++++++++++++++++++
 1 file changed, 26 insertions(+)
```

约束遵守：未改 `reward_presentation.gd` 或任何生产代码；未动
`_test_weapon_reward_changes_loadout`；未 checkout/reset/stash；未 push。

## 6. 工作区备注

`docs/Seek_Dead_统一设计基线与总体进度_2026-11-22.md` 在 `git status` 里显示为已修改，
`git diff` 无内容差异（仅 LF→CRLF 行尾提示），属行尾规范化标记，非内容改动；
本轮提交未包含它。
