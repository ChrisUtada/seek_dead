# tools/art_pipeline · 美术后处理管道（M0-03）

可复现的候选图后处理与验收工具，替代原先散落在个人目录的后处理脚本。

## 依赖

- Python 3.10+（本机 3.14.6）
- Pillow（本机 12.3.0）

```bash
python -m pip install pillow
```

## 目录

```text
tools/art_pipeline/
├── pipeline.py                # 唯一入口：palette / normalize / check / sheet
├── palette.json               # 主色板 v3（32 色）+ 每类色数上限
└── prompt_cards/
    ├── m0_golden.json         # M0-02 锁定的 5 项黄金样板描述卡
    └── backend_compare.json   # 后端对比 12 题（4 武器图标 / 4 敌人 / 4 BOSS）
```

原始 AI 图不入库：放在仓库根的 `raw/art/<批次>/`（已加入 `.gitignore`），只提交归一后的成品与 contact sheet。

## 命令

```bash
# 1) 色板预览
python tools/art_pipeline/pipeline.py palette --out docs/M0-03/palette_v3.png

# 2) 候选图 -> 入库图（去背景 / 量化 / 整数归一 / 锚点）
python tools/art_pipeline/pipeline.py normalize raw/art/hero_01.png \
    assets/characters/player/idle_01.png --mode sprite48

# 3) 规格检查（逐文件 PASS/FAIL，可输出 JSON）
python tools/art_pipeline/pipeline.py check assets/characters/player/*.png \
    --mode sprite48 --json docs/M0-03/check_report.json

# 4) 同批 contact sheet（1x 可辨 / 3x 细节 / 纯黑剪影）
python tools/art_pipeline/pipeline.py sheet --out docs/M0-03/sheet_act1.png \
    --scale 3 --silhouette --items assets/characters/player/idle_01.png assets/enemies/frost_bat.png
```

### 模式预设

| mode | 画布 | 色数上限 | 锚点 |
|---|---|---|---|
| `sprite48` | 48×48 | 12 | bottom |
| `boss96` | 96×96 | 16 | bottom |
| `icon24` | 24×24 | 8 | center |
| `icon16` | 16×16 | 6 | center |

可用 `--canvas 64x64 --max-colors 10 --anchor center` 覆盖。

### normalize 行为

1. `--bg auto` 取四角众数色抠背景（AI 直出常见纯色底）；已有 alpha 则沿用。
2. alpha 硬化为 0/255，消除抗锯齿半透明边。
3. 裁到包围盒后按**整数倍**放大；源图大于画布时最近邻缩小并告警（应回生成端出小尺寸）。
4. 最近色量化到 `palette.json` 的 32 色主色板。
5. 按锚点贴入画布（角色脚底贴底，图标居中）。
6. 立刻跑一次 check，FAIL 时返回码 1。

### check 判定

- FAIL：尺寸不等于目标；无可见像素；色数超上限；板外色 > 5%；16/24 图标主体占比 < 25%。
- WARN：模式非 RGBA；板外色 ≤ 5%；透明像素过少；角色脚底离底 > 1px；水平中心偏移 > 1px。

## 后端对比流程（M0-03）

1. 用 `prompt_cards/backend_compare.json` 的 12 题，在两个后端各出 2–3 候选。
2. 每个后端的候选都过同一套 `normalize`（参数按卡上的 canvas / kind）。
3. 用 `sheet --silhouette` 生成各自的 contact sheet。
4. 按 `docs/M0-03_后端对比测试.md` 的评分表盲评，选主后端 + 备用后端。

评分记录写在 `docs/M0-03_后端对比测试.md`；生成记录（后端、模型版本、种子、prompt、参考图批次、后处理版本）写在每个批次的 `raw/art/<批次>/manifest.json`，不入库但需本地保留。

## 规范来源

- `docs/M0-03_美术规范.md`：画布、色板、线宽、间距、字体、命名与验收阈值。
- `docs/M0-03_资产映射.md`：现有资产盘点、回落路径、视觉 ID → 房间/资源映射。
