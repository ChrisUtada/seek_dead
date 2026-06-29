# 项目指令

## 启动新任务时

在开始任何修改或新功能之前，先执行以下步骤：

1. 使用 `glob` 工具扫描 `docs/*.md`，获取所有文档文件列表
2. 使用 `read` 工具依次读取所有文档文件，了解当前项目的：
   - 整体架构和设计方向
   - 各系统完成状态（已实现 / 待办 / Blocked）
   - 技术决策和约束（碰撞层、分辨率、Autoload 等）
   - 编码惯例和命名规则
3. 读取完成后，在回答中简要总结当前项目的进展状态，再开始实际工作

## 编码约定

- 全部使用 GDScript，不引入 C#
- 2D 俯视角动作 RPG，设计分辨率 640×360，stretch/mode=canvas_items，窗口 1280×720
- 像素图用 `texture_filter = NEAREST`
- `class_name` 注册的类通过 `preload` 在文件顶部显式引用
- 不写注释，除非有特别复杂的逻辑需要说明
- 使用组件化架构（StateComponent / MovementComponent / WeaponComponent 等）
- 数据驱动优先：使用 Resource（.tres）配置，而非硬编码数值
- 碰撞层：1=Player, 2=Enemy, 3=Environment, 4=Pickup, 5=Hazard, 6=Hurtbox, 7=Hitbox
- 状态机使用 `enum` + `match` 单类实现，带 `_enter_*` 和 `_exit_*` 生命周期
- `monitoring`/`monitorable` 修改必须用 `set_deferred`

## 设计准则

- **最少改动原则**：优先修改现有文件，不新建文件除非无法避免
- **保持一致性**：新代码的风格、命名、架构模式与现有代码一致
- **防御性编程**：引用节点时使用 `get_node_or_null()` 或 `is_instance_valid()` 校验
- **解耦**：系统间通过信号（Signal）通信，避免直接依赖
- **不引入外部依赖**：不使用插件或第三方库，除非项目已使用

## 工作流程

- **每步必验**：每完成一个功能模块或一个改动后，必须进行调试验证再提交。验证方式包括但不限于：
  - F8 调试命令（装备系统相关）
  - 控制台 `print` 输出关键状态变化
  - 游戏内实测观察行为
  - 检查日志确认无报错
- 未经验证的代码不得提交，除非用户明确要求跳过。
