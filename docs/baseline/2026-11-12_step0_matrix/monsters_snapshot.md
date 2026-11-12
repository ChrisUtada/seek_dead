# 怪物清单与机制快照（2026-11-12 · Step 0 冻结）

> 由 `tools/monster_snapshot.py` 从 `resources/rooms/*.tres` 与 `resources/archetypes/*.tres` 生成，勿手改。
> 快照口径：0 值回落行为族基准；未乘 ante 缩放。完整字段见同目录 `monsters_snapshot.csv` / `.json`。

| # | 怪物 | ID | 类型 | 幕 | 元素 | 有效 HP | 有效 ATK | 有效甲 | 行为族/意图 | 现有机制脚本 | 机制摘要 |
|---:|---|---|---|---:|---|---:|---:|---:|---|---|---|
| 1 | 余烬傀儡 | `ember_golem` | normal | 1 | fire | 85 | 12 | 0 | — | — | — |
| 2 | 冰锋群蝠 | `a1_swarm_ice` | normal | 1 | ice | 55 | 10 | 0 | 群冲（{"attack": 100}） | normal_trait_gimmick | 首回合冻结1列 / 次回合自消 |
| 3 | 寒鳞蝠 | `frost_bat` | normal | 1 | ice | 80 | 10 | 0 | — | — | — |
| 4 | 暗影诡匠 | `a1_trickster_dark` | normal | 1 | dark | 95 | 14 | 0 | 诡匠（{"attack": 25, "jam": 20, "lock": 20, "chaos": 20, "auto_stop": 15}） | — | — |
| 5 | 毒壳壁垒 | `a1_bulwark_poison` | normal | 1 | poison | 170 | 12 | 0 | 壁垒（{"attack": 70, "heavy": 30}） | normal_trait_gimmick | 开局20护甲 / 破甲后不再获得 |
| 6 | 毒孢菌 | `toxin_spore` | normal | 1 | poison | 80 | 12 | 10 | — | — | — |
| 7 | 窃语咒师 | `a1_hexer_none` | normal | 1 | none | 90 | 12 | 0 | 干扰者（{"attack": 35, "jam": 25, "lock": 25, "auto_stop": 15}） | normal_trait_gimmick | 首次转轮前 / 第1列注废（仅一次） |
| 8 | 腐化史莱姆 | `corrupted_slime` | normal | 1 | poison | 90 | 13 | 12 | — | — | — |
| 9 | 裂石像 | `cracked_statue` | normal | 1 | light | 95 | 12 | 16 | — | — | — |
| 10 | 辉光游侠 | `a1_striker_light` | normal | 1 | light | 100 | 13 | 0 | 游侠（{"attack": 60, "heavy": 20, "jam": 10, "lock": 10}） | normal_trait_gimmick | 首次受击后 / 获得10护甲（一次） |
| 11 | 重锤蛮兵 | `a1_brute_none` | normal | 1 | none | 140 | 16 | 0 | 重击者（{"attack": 60, "heavy": 40}） | — | — |
| 12 | 锈盲蝠 | `rust_blind_bat` | normal | 1 | ice | 75 | 10 | 0 | — | — | — |
| 13 | 亵渎书吏 | `defiled_scribe` | normal | 2 | ice | 140 | 13 | 0 | — | — | — |
| 14 | 圣壳壁垒 | `a2_bulwark_light` | normal | 2 | light | 170 | 10 | 0 | 壁垒（{"attack": 70, "heavy": 30}） | — | — |
| 15 | 暗影信徒 | `shadow_acolyte` | normal | 2 | dark | 125 | 12 | 0 | — | — | — |
| 16 | 暗行游侠 | `a2_striker_dark` | normal | 2 | dark | 100 | 11 | 0 | 游侠（{"attack": 60, "heavy": 20, "jam": 10, "lock": 10}） | — | — |
| 17 | 暮色蛮兵 | `a2_brute_dark` | normal | 2 | dark | 140 | 14 | 0 | 重击者（{"attack": 60, "heavy": 40}） | — | — |
| 18 | 毒雾术士 | `a2_caster_poison` | normal | 2 | poison | 100 | 11 | 0 | 状态播种者（{"attack": 35, "chaos": 20, "heavy": 15, "auto_stop": 30}） | — | — |
| 19 | 炎锋群蝠 | `a2_swarm_fire` | normal | 2 | fire | 55 | 9 | 0 | 群冲（{"attack": 100}） | — | — |
| 20 | 石壳壁垒 | `a2_bulwark_none` | normal | 2 | none | 170 | 10 | 0 | 壁垒（{"attack": 70, "heavy": 30}） | — | — |
| 21 | 虚空低语者 | `void_whisperer` | normal | 2 | dark | 130 | 14 | 0 | — | — | — |
| 22 | 迷面诡匠 | `a2_trickster_none` | normal | 2 | none | 95 | 12 | 0 | 诡匠（{"attack": 25, "jam": 20, "lock": 20, "chaos": 20, "auto_stop": 15}） | — | — |
| 23 | 迷魂灯笼 | `beguiling_lantern` | normal | 2 | fire | 135 | 13 | 0 | — | — | — |
| 24 | 铁臂蛮兵 | `a2_brute_none` | normal | 2 | none | 140 | 14 | 0 | 重击者（{"attack": 60, "heavy": 40}） | — | — |
| 25 | 圣辉游侠 | `a3_striker_light` | normal | 3 | light | 100 | 11 | 0 | 游侠（{"attack": 60, "heavy": 20, "jam": 10, "lock": 10}） | — | — |
| 26 | 坍缩星核 | `collapsing_core` | normal | 3 | light | 195 | 17 | 0 | — | — | — |
| 27 | 毒针群蝠 | `a3_swarm_poison` | normal | 3 | poison | 55 | 9 | 0 | 群冲（{"attack": 100}） | — | — |
| 28 | 深渊蛮兵 | `a3_brute_none` | normal | 3 | none | 140 | 14 | 0 | 重击者（{"attack": 60, "heavy": 40}） | — | — |
| 29 | 深渊诡匠 | `a3_trickster_dark` | normal | 3 | dark | 95 | 12 | 0 | 诡匠（{"attack": 25, "jam": 20, "lock": 20, "chaos": 20, "auto_stop": 15}） | — | — |
| 30 | 湮灭使徒 | `annihilation_apostle` | normal | 3 | fire | 215 | 19 | 0 | — | — | — |
| 31 | 熔壳壁垒 | `a3_bulwark_fire` | normal | 3 | fire | 170 | 10 | 0 | 壁垒（{"attack": 70, "heavy": 30}） | — | — |
| 32 | 虚空回响 | `void_echo` | normal | 3 | dark | 205 | 18 | 0 | — | — | — |
| 33 | 裂界游魂 | `riftsoul_wanderer` | normal | 3 | poison | 220 | 20 | 0 | — | — | — |
| 34 | 辉铁蛮兵 | `a3_brute_light` | normal | 3 | light | 140 | 14 | 0 | 重击者（{"attack": 60, "heavy": 40}） | — | — |
| 35 | 霜语术士 | `a3_caster_ice` | normal | 3 | ice | 100 | 11 | 0 | 状态播种者（{"attack": 35, "chaos": 20, "heavy": 15, "auto_stop": 30}） | — | — |
| 36 | 黑曜壁垒 | `a3_bulwark_none` | normal | 3 | none | 170 | 10 | 0 | 壁垒（{"attack": 70, "heavy": 30}） | — | — |
| 37 | 寒铁精英 | `a1_elite_brute_ice` | elite | 1 | ice | 200 | 20 | 0 | 精英蛮兵（{"attack": 50, "heavy": 50}） | rust_armor_gimmick | 首轮蓄势1回合→爆发 / 之后每3回合：蓄势→爆发 / 叠甲冻结→恢复·特殊三连破甲 |
| 38 | 毒疫术士 | `a1_elite_caster_poison` | elite | 1 | poison | 160 | 17 | 0 | 精英术士（{"attack": 35, "chaos": 25, "heavy": 10, "auto_stop": 30}） | acid_bomb_gimmick | — |
| 39 | 腐殖巨蠕 | `humus_worm` | elite | 1 | poison | 145 | 13 | 0 | 毒噬者（{"attack": 30, "chaos": 30, "heavy": 10, "auto_stop": 30}） | acid_bomb_gimmick | — |
| 40 | 锈铁傀儡 | `acid_golem` | elite | 1 | ice | 155 | 16 | 22 | — | rust_armor_gimmick | — |
| 41 | 深渊咏者 | `abyssal_cantor` | elite | 2 | dark | 240 | 18 | 20 | — | whisper_lock_gimmick | — |
| 42 | 深渊咒师 | `a2_elite_hexer_dark` | elite | 2 | dark | 150 | 13 | 0 | 精英咒师（{"attack": 25, "jam": 30, "lock": 30, "auto_stop": 15}） | whisper_lock_gimmick | — |
| 43 | 炎爆群王 | `a2_elite_swarmking_fire` | elite | 2 | fire | 170 | 16 | 0 | 精英群王（{"attack": 90, "heavy": 10}） | bipolar_phase_gimmick | — |
| 44 | 邪颂祭司 | `blasphemy_priest` | elite | 2 | poison | 255 | 19 | 0 | — | acid_bomb_gimmick | — |
| 45 | 圣盾守关 | `a3_elite_warden_light` | elite | 3 | light | 180 | 14 | 18 | 精英守关（{"attack": 70, "heavy": 30}） | abyss_erosion_gimmick | — |
| 46 | 湮灭领主 | `annihilation_lord` | elite | 3 | fire | 395 | 26 | 0 | — | abyss_erosion_gimmick | — |
| 47 | 终末庄家 | `a3_elite_trickster_dark` | elite | 3 | dark | 155 | 15 | 0 | 精英诡匠（{"attack": 30, "chaos": 35, "heavy": 20, "auto_stop": 15}） | abyss_erosion_gimmick | — |
| 48 | 终焉守望 | `final_watcher` | elite | 3 | light | 370 | 24 | 28 | — | abyss_erosion_gimmick | — |
| 49 | 冰封铁瓮 | `frozen_urn` | boss | 1 | ice | 240 | 17 | 20 | — | rust_armor_gimmick | 首轮蓄势1回合→爆发 / 之后每3回合：蓄势→爆发 / 叠甲冻结1~2列→恢复·特殊三连破甲 |
| 50 | 碎裂石像鬼 | `brittle_gargoyle` | boss | 1 | ice | 198 | 25 | 8 | — | glass_cannon_gimmick | — |
| 51 | 茧居石雕 | `cocoon_sentinel` | boss | 1 | ice | 240 | 15 | 45 | — | cocoon_cycle_gimmick | — |
| 52 | 酸蚀恶鬼 | `acid_ghoul` | boss | 1 | poison | 204 | 14 | 10 | — | acid_bomb_gimmick | — |
| 53 | 呓语教徒 | `whispering_cultist` | boss | 2 | dark | 290 | 20 | 25 | — | whisper_lock_gimmick | — |
| 54 | 天平审判官 | `scale_inquisitor` | boss | 2 | light | 300 | 17 | 20 | — | compulsion_rule_gimmick | — |
| 55 | 无名虚空 | `nameless_void` | boss | 2 | dark | 320 | 18 | 20 | — | emotional_vacuum_gimmick | — |
| 56 | 躁怒元素使 | `manic_elementalist` | boss | 2 | fire | 280 | 18 | 15 | — | bipolar_phase_gimmick | — |
| 57 | 迷宫低语者 | `maze_whisperer` | boss | 2 | dark | 300 | 16 | 25 | — | whisper_lock_gimmick | — |
| 58 | 勇者的阴影 | `hero_shadow` | boss | 3 | none | 600 | 30 | 40 | — | shadow_projection_gimmick | — |
| 59 | 深渊监视者 | `abyss_watcher` | boss | 3 | light | 460 | 27 | 35 | — | abyss_erosion_gimmick | — |
| 60 | 碎裂魔王 | `shattered_king` | boss | 3 | fire | 440 | 24 | 20 | — | split_ego_gimmick | — |
| 61 | 耻辱审判官 | `grand_inquisitor` | boss | 3 | light | 450 | 26 | 25 | — | shame_counter_gimmick | — |

## 计数

| 类型 | 数量 |
|---|---:|
| 普通 | 36 |
| 精英 | 12 |
| BOSS | 13 |
| **合计** | **61** |

## 关键平衡冻结值

| 键 | 值 |
|---|---|
| `counter_burst_pct` | `0.125` |
| `heal_line_mults` | `[1.0, 2.5, 4.5]` |
| `charge_burst_pct` | `0.15` |
| `player_dmg_mult` | `1.5` |
| `crit_chance` | `0.20` |
| `ante_act_step_hp` | `1.75` |
| `ante_act_step_atk` | `1.30` |
| `ante_room_step_hp` | `1.15` |
| `ante_room_step_atk` | `1.06` |
| `run_act_layout` | `["normal", "normal", "normal", "elite", "normal", "normal", "elite", "boss"]` |
