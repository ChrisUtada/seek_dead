# 怪物与 BOSS 美术进度清单

> 盘点时间：2026-11-10 10:35
> 最近更新：2026-11-11（辉铁蛮兵、深渊蛮兵、熔壳壁垒、黑曜壁垒、霜语术士接入；玩家立绘重绘为 E1 并覆盖 `hero_48.png`）
> 数据源：`docs/怪物与BOSS全览_当前版本.md`、`resources/rooms/*.tres`、`assets/characters/` 实际文件
> 判定标准：**立绘为 96×96 且已接入 `.tres`** 才算完成（2026-11-10 起小怪也统一 96）。 11-09 09:19 那批 6–12 色的 48×48 图是旧占位，不计。

## 总进度

| 类别 | 总数 | 已完成 | 进度 |
|---|---:|---:|---:|
| BOSS | 13 | 5 | 38% |
| 精英 | 12 | 1 | 8% |
| 普通 | 36 | 29 | 81% |
| **怪物合计** | **61** | **35** | **57%** |
| 玩家 | 1 | 1 | 100% |

**ACT1 普通 12/12、ACT2 普通 12/12 已全部完成**；ACT1 BOSS 4/4 全完成，ACT2 BOSS 0/5、ACT3 BOSS 1/4；ACT3 普通 5/12（辉铁蛮兵、深渊蛮兵、熔壳壁垒、黑曜壁垒、霜语术士）。精英已开工 1/12（锈铁傀儡）。

---

## 1. 已完成 ✅

| 状态 | 名称 | ID | 类别 | 立绘文件 | 规格 |
|---|---|---|---|---|---|
| ✅ | 骑士（玩家） | `knight_v1` | 玩家 | `hero_48.png` | 48×48 / 36 色（盾在身前 · 举剑朝右 · 双腿张开 · 盾面不规则裂缝；2026-11-11 重绘，旧 v1 备份在 `.workbuddy/art_trials/player_v3/old_v1_48.png`） |
| ✅ | 冰封铁瓮 | `frozen_urn` | ACT1 BOSS · fixed | `boss_96.png` | 96×96 / 2303 色 |
| ✅ | 碎裂石像鬼 | `brittle_gargoyle` | ACT1 BOSS · rotating | `idle_01.png` | 96×96 / 3416 色（含亮冰蓝裂痕、轮廓清边） |
| ✅ | 酸蚀恶鬼 | `acid_ghoul` | ACT1 BOSS · rotating | `idle_01.png` | 96×96 / 48 色 |
| ✅ | 茧居石雕 | `cocoon_sentinel` | ACT1 BOSS · hidden | `closed.png` + `open.png` | 双态各 96×96 / 25·38 色 |
| ✅ | 耻辱审判官 | `grand_inquisitor` | ACT3 BOSS · hidden | `boss_96.png` | 96×96 / 1439 色 |
| ✅ | 余烬傀儡 | `ember_golem` | ACT1 普通 | `idle_01.png` | 96×96 / 63 色 |
| ✅ | 重锤蛮兵 | `a1_brute_none` | ACT1 普通 | `idle_01.png` | 96×96 / 72 色 |
| ✅ | 毒壳壁垒 | `a1_bulwark_poison` | ACT1 普通 | `idle_01.png` | 96×96 / 59 色 |
| ✅ | 窃语咒师 | `a1_hexer_none` | ACT1 普通 | `idle_01.png` | 96×96 / 72 色 |
| ✅ | 辉光游侠 | `a1_striker_light` | ACT1 普通 | `idle_01.png` | 96×96 / 106 色 |
| ✅ | 冰锋群蝠 | `a1_swarm_ice` | ACT1 普通 | `idle_01.png` | 96×96 / 88 色（主蝠脸部返工 + 暗点合并） |
| ✅ | 暗影诡匠 | `a1_trickster_dark` | ACT1 普通 | `idle_01.png` | 96×96 / 90 色 |
| ✅ | 腐化史莱姆 | `corrupted_slime` | ACT1 普通 | `idle_01.png` | 96×96 / 85 色 |
| ✅ | 寒鳞蝠 | `frost_bat` | ACT1 普通 | `idle_01.png` | 96×96 / 56 色（冰锋群蝠族色·瘦高） |
| ✅ | 锈盲蝠 | `rust_blind_bat` | ACT1 普通 | `idle_01.png` | 96×96 / 56 色（冰锋群蝠族色·扁宽破损） |
| ✅ | 裂石像 | `cracked_statue` | ACT1 普通 | `idle_01.png` | 96×96 / 71 色（巨石面·无手脚·锯齿巨口·纯石质） |
| ✅ | 毒孢菌 | `toxin_spore` | ACT1 普通 | `idle_01.png` | 96×96 / 103 色（巨口齿列·流脓版） |
| ✅ | 暮色蛮兵 | `a2_brute_dark` | ACT2 普通 | `idle_01.png` | 96×96 / 32 色（双角盔·拖地砍刀·去噪） |
| ✅ | 铁臂蛮兵 | `a2_brute_none` | ACT2 普通 | `idle_01.png` | 96×96 / 27 色（巨铁活塞臂·瘦小另一臂·亮钢骷髅头） |
| ✅ | 圣壳壁垒 | `a2_bulwark_light` | ACT2 普通 | `idle_01.png` | 96×96 / 37 色（哥特拱圣龛·象牙石板+旧金·中央圣光缝） |
| ✅ | 石壳壁垒 | `a2_bulwark_none` | ACT2 普通 | `idle_01.png` | 96×96 / 43 色（前倾断裂城垛·巨大黑色裂口·铁钉断链） |
| ✅ | 毒雾术士 | `a2_caster_poison` | ACT2 普通 | `idle_01.png` | 96×96 / 28 色（宽兜帽·骨鸟嘴面罩·提香炉·贴地毒雾） |
| ✅ | 暗行游侠 | `a2_striker_dark` | ACT2 普通 | `idle_01.png` | 96×96 / 28 色（低伏潜行·单手弩·破布拖影·紫眼缝） |
| ✅ | 炎锋群蝠 | `a2_swarm_fire` | ACT2 普通 | `idle_01.png` | 96×96 / 27 色（焦黑双蝠·骨翼条·翼脉余火） |
| ✅ | 迷面诡匠 | `a2_trickster_none` | ACT2 普通 | `idle_01.png` | 96×96 / 21 色（三张骨白面具叠加·无腿漂浮破袍·提线十指·焦褐配色） |
| ✅ | 迷魂灯笼 | `beguiling_lantern` | ACT2 普通 | `idle_01.png` | 96×96 / 21 色（悬吊铁笼·右侧压凹·内壁暖反光·火焰竖瞳·笼底骨指与枯爪） |
| ✅ | 亵渎书吏 | `defiled_scribe` | ACT2 普通 | `idle_01.png` | 96×96 / 39 色（伏案弓背·无五官脸布满墨迹+单只黑洞·骨手按书·冰羽笔·摊开破书带霜） |
| ✅ | 暗影信徒 | `shadow_acolyte` | ACT2 普通 | `idle_01.png` | 96×96 / 18 色（影沼升起半身·长条骷髅面·竖缝眼+三道缝嘴·双手合捧·后端翻兜帽） |
| ✅ | 虚空低语者 | `void_whisperer` | ACT2 普通 | `idle_01.png` | 96×96 / 21 色（兜帽长衫人形·兜帽内纯黑虚空无脸·灰蓝配色·双臂垂侧·下摆撕裂垂地·无烟尘） |
| ✅ | 辉铁蛮兵 | `a3_brute_light` | ACT3 普通 | `idle_01.png` | 96×96 / 4670 色（亮银+暖金全封闭盔·横向亮目缝无五官·双手竖握发光巨剑；AI 原图纯缩放，未量化清理） |
| ✅ | 深渊蛮兵 | `a3_brute_none` | ACT3 普通 | `idle_01.png` | 96×96 / 4074 色（石板灰铁全封闭盔·胸甲与面甲岩浆裂缝·亮黄核心→橙→暗红；AI 原图纯缩放 + 紫色像素定向 HSV 换色，未量化清理；旧 48 占位备份在 `.workbuddy/art_trials/shen_yuan/old_placeholder_48.png`） |
| ✅ | 熔壳壁垒 | `a3_bulwark_fire` | ACT3 普通 | `idle_01.png` | 96×96 / 4490 色（低伏玄武岩拱壳·宽橙金岩浆裂缝·中央熔炉亮口·四只短粗石爪；非人形壳主体，正面居中；AI 原图纯抠底缩放，未量化清理；旧 48 占位备份在 `.workbuddy/art_trials/rong_ke/old_placeholder_48.png`） |
| ✅ | 黑曜壁垒 | `a3_bulwark_none` | ACT3 普通 | `idle_01.png` | 96×96 / 3421 色（竖向不对称黑曜石尖晶簇·冰青/银蓝镜面高光棱面+紫边·**无脚**；与熔壳壁垒「横向+暖橙」形成竖/横、冷/暖对比；由 1024 RGBA 母版按 y=705 语义切掉石足并清 92 个孤立碎点，主体逐点零改动，未量化清理；旧 48 占位备份在 `.workbuddy/art_trials/hei_yao/old_placeholder_48.png`） |
| ✅ | 霜语术士 | `a3_caster_ice` | ACT3 普通 | `idle_01.png` | 96×96 / 2213 色（冰晶棱面兜帽长袍·兜帽内霜雾+青色亮瞳·双手托悬浮亮青冰符·袍摆碎成冰棱且**无脚**；纯冷色冰青/银白/深靛蓝，meanL 152；与同族 5 只靠「非布袍+无书无香炉」区分；AI 原图纯抠底缩放，未量化清理；旧 48 占位备份在 `.workbuddy/art_trials/shuang_yu/old_placeholder_48.png`） |

## 1b. 已完成 ✅ — 精英（1）

| 状态 | 名称 | ID | 幕 | 元素 | 专属机制 | 立绘 |
|---|---|---|---|---|---|---|
| ✅ | 锈铁傀儡 | `acid_golem` | 1 | 冰 | 熔铸护甲 | 96×96 / 24 色（低伏拱背兽态·双臂完整撑地等长·背脊铁刺·仰头盯人·胸下垂熔渣铁链） |

---

## 2. 待做 ⬜ — 普通怪物（7）

### ACT1 普通（0）— ✅ 全部完成 12/12

| 状态 | 名称 | ID | 元素 | 备注 |
|---|---|---|---|---|

### ACT2 普通（0）— ✅ 全部完成 12/12

| 状态 | 名称 | ID | 元素 | 备注 |
|---|---|---|---|---|

### ACT3 普通（7）

| 状态 | 名称 | ID | 元素 | 备注 |
|---|---|---|---|---|
| ⬜ | 圣辉游侠 | `a3_striker_light` | 光 | 模板房 |
| ⬜ | 毒针群蝠 | `a3_swarm_poison` | 毒 | 模板房 |
| ⬜ | 深渊诡匠 | `a3_trickster_dark` | 暗 | 模板房 |
| ⬜ | 湮灭使徒 | `annihilation_apostle` | 火 | 具名怪 |
| ⬜ | 坍缩星核 | `collapsing_core` | 光 | 具名怪 |
| ⬜ | 裂界游魂 | `riftsoul_wanderer` | 毒 | 具名怪 |
| ⬜ | 虚空回响 | `void_echo` | 暗 | 具名怪 |

---

## 3. 待做 ⬜ — 精英（11）

| 状态 | 名称 | ID | 幕 | 元素 | 专属机制 |
|---|---|---|---|---|---|
| ⬜ | 寒铁精英 | `a1_elite_brute_ice` | 1 | 冰 | 熔铸护甲 |
| ⬜ | 毒疫术士 | `a1_elite_caster_poison` | 1 | 毒 | 酸蚀挂毒 |
| ⬜ | 腐殖巨蠕 | `humus_worm` | 1 | 毒 | 酸蚀挂毒 |
| ⬜ | 深渊咒师 | `a2_elite_hexer_dark` | 2 | 暗 | 呓语锁轮 |
| ⬜ | 炎爆群王 | `a2_elite_swarmking_fire` | 2 | 火 | 躁抑交替 |
| ⬜ | 深渊咏者 | `abyssal_cantor` | 2 | 暗 | 呓语锁轮 |
| ⬜ | 邪颂祭司 | `blasphemy_priest` | 2 | 毒 | 酸蚀挂毒 |
| ⬜ | 终焉诡匠 | `a3_elite_trickster_dark` | 3 | 暗 | 深渊侵蚀·lite |
| ⬜ | 圣盾守关 | `a3_elite_warden_light` | 3 | 光 | 深渊侵蚀·lite |
| ⬜ | 湮灭领主 | `annihilation_lord` | 3 | 火 | 深渊侵蚀·lite |
| ⬜ | 终焉守望 | `final_watcher` | 3 | 光 | 深渊侵蚀·lite |

---

## 4. 待做 ⬜ — BOSS（8）

| 状态 | 名称 | ID | 幕 | 角色 | 元素 | 核心机制 |
|---|---|---|---|---|---|---|
| ⬜ | 呓语教徒 | `whispering_cultist` | 2 | fixed | 暗 | 呓语锁轮 |
| ⬜ | 迷宫低语者 | `maze_whisperer` | 2 | rotating | 暗 | 呓语锁轮·双阶段 |
| ⬜ | 躁怒元素使 | `manic_elementalist` | 2 | rotating | 火 | 躁抑交替 |
| ⬜ | 天平审判官 | `scale_inquisitor` | 2 | rotating | 光 | 律法强迫 |
| ⬜ | 无名虚空 | `nameless_void` | 2 | hidden | 暗 | 情感剥离 |
| ⬜ | 深渊监视者 | `abyss_watcher` | 3 | fixed | 光 | 深渊侵蚀·三阶段 |
| ⬜ | 碎裂魔王 | `shattered_king` | 3 | rotating | 火→冰→毒 | 人格裂变 |
| ⬜ | 勇者的阴影 | `hero_shadow` | 3 | **final** | 无 | 万象投影 / 三阶段终局 |

---

## 5. 备注

- **占位图复用**：旧 48×48 中有 4 组共用同一张图 —— 毒疫术士 / 毒雾术士 / 邪颂祭司；冰锋群蝠 / 寒鳞蝠；炎锋群蝠 / 炎爆群王（暗影信徒与虚空低语者原本也共用，两只现已各自单独绘制）。做美术时会自然拆开，不需要额外处理数据。
- **尺寸约定（2026-11-10 变更）**：**全部 61 个房间统一 `art_scale=2.0`、立绘 96×96**。原 48 个小怪的 1.0/48 已批量改为 2.0/96；**尚未重绘的 26 只仍用 48 贴图，会按 2 倍放大显示（偏马赛克）**，重绘后自然恢复清晰。贴图物理尺寸必须与 `48 × art_scale` 一致，否则 TextureRect 的 minimum size 会撑大父容器。
- **文件命名不统一**：`frozen_urn` / `grand_inquisitor` 用 `boss_96.png`，其余用 `idle_01.png`；`cocoon_sentinel` 用 `closed.png` / `open.png` 双态。盘点时不能只看 `idle_01.png`。
- **建议推进顺序**：ACT1 剩余 3 个精英 → ACT2（5 BOSS + 4 精英）→ ACT3（3 BOSS + 4 精英 + 7 普通）。理由是 ACT1 BOSS 与普通怪已全部完成，补齐精英即可让 ACT1 视觉闭环。
- 本文只记美术进度，数值 / 机制 / 战利品以 `docs/怪物与BOSS全览_当前版本.md` 为准。
