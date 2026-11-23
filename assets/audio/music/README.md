# 战斗 BGM

## duel_bgm.ogg（Battle Theme A）

- **来源**：OpenGameArt — [Battle Theme A](https://opengameart.org/content/battle-theme-a)
- **作者**：（见原页面）
- **许可**：**CC0 1.0 / Public Domain** —— 免署名、可商用、可用于游戏，无使用限制。
- **文件**：`duel_bgm.ogg`（完整曲 1:36，44.1kHz 立体声 Vorbis q5，从原 MP3 转码）
- **用途**：对决战斗 BGM，进入战斗房（`_start_room`）时淡入并循环播放。

## 许可核实（2026-11-23）

用户要求"务必免费可商用"，逐个核实过来源许可：

| 来源 | 游戏商用 | 结论 |
|---|---|---|
| **Mixkit 音乐** | ❌ 明确禁止 | 官方 Stock Music Free License 原文："Not Allowed: ... **Video Games**" —— 不能用！ |
| Mixkit 音效(SFX) | ✅ 允许 | `assets/audio/reel/` 现有符号音属此类，可继续用 |
| **OpenGameArt（本曲）** | ✅ CC0 | 已核实页面 License(s) 标签为 CC0，免署名可商用 |

⚠️ 关键：Mixkit 的**音乐**和**音效**是两套许可。音乐禁止游戏用途，
不要从 Mixkit 拿 BGM；本曲来自 OpenGameArt CC0。

## 接入架构

- `scripts/battle/bgm_system.gd`（BgmSystem，RefCounted）：单曲循环 + 淡入淡出 + 静音开关。
- `duel_controller.gd`：`_ready` 创建注入；`start_room_data`（营地/宝箱/事件房已提前分流）
  进入战斗房时 `bgm_system.start()` 淡入。
- 音量：BGM 目标 **-18dB**，低于 SFX（-3~-8dB），符合经典混音"音乐不盖过音效"原则。
- 循环：ogg 的 `loop=true`（ogg 无 mp3 编码延迟，循环接缝较干净）。
