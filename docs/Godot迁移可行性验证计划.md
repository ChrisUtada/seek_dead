# 《Seek Dead》Godot迁移可行性验证计划

| 版本 | 日期 | 变更说明 |
|------|------|----------|
| v1.0 | 2026-06-22 | 初始版本 |
| v2.0 | 2026-06-22 | 修正GDScript API，利用Godot原生特性，规范格式 |

---

## 一、验证目标

### 1.1 核心目标

- 验证使用 **GDScript** 在 Godot 4.x 中实现《Seek Dead》核心游戏机制的可行性
- 评估 Godot 4.x 2D性能表现
- 验证关键系统（战斗、AI、UI）在 Godot 中的实现效果
- 确认第三方依赖的替代方案是否可行

### 1.2 验证范围

| 验证模块 | 验证内容 | 优先级 |
|---------|---------|--------|
| 核心架构 | Autoload单例、Signals事件系统、Resource资源管理 | P0 |
| 战斗系统 | 角色控制、武器攻击、伤害计算、状态效果 | P0 |
| AI系统 | 行为树、寻路、基础AI行为 | P1 |
| UI系统 | HUD界面、菜单系统、动画过渡 | P1 |
| 物理系统 | 碰撞检测、角色移动、刚体交互 | P0 |
| 渲染系统 | 2D渲染、动画播放、特效系统 | P1 |
| 数据系统 | JSON配置加载、存档系统 | P1 |

---

## 二、技术选型

### 2.1 开发语言：GDScript 4.x

**选择理由：**

- Godot原生语言，性能最优
- 语法简洁，开发效率高
- 与Godot节点系统深度集成
- 动态类型，便于快速原型开发
- 无需编译，热重载支持完善

### 2.2 项目结构

```
SeekDeadPrototype/
├── project.godot
├── autoload/
│   ├── game_manager.gd
│   ├── event_manager.gd
│   └── resource_manager.gd
├── scripts/
│   ├── battle/
│   ├── ai/
│   ├── ui/
│   └── utils/
├── scenes/
│   ├── battle/
│   ├── ui/
│   └── test/
├── resources/
└── assets/
```

### 2.3 核心技术方案

#### 2.3.1 Autoload 单例

Godot 的 Autoload 本身就是单例模式，无需手动实现 `instance` 判断。在 `project.godot` 中配置即可：

```ini
; project.godot
[autoload]
GameManager="*res://autoload/game_manager.gd"
EventManager="*res://autoload/event_manager.gd"
ResourceManager="*res://autoload/resource_manager.gd"
```

```gdscript
# autoload/game_manager.gd
extends Node

var player_data: Dictionary = {}
var current_level: int = 1

func _ready():
    process_mode = Node.PROCESS_MODE_ALWAYS
    print("GameManager initialized")
```

#### 2.3.2 事件系统

Godot 内置 Signals 机制已足够，无需额外封装。直接使用节点信号：

```gdscript
# autoload/event_manager.gd
extends Node

# 直接声明信号
signal damage_dealt(attacker, defender, amount)
signal player_died(player)
signal skill_used(skill_data)
signal scene_changed(scene_name)

# 使用示例
func _ready():
    damage_dealt.connect(_on_damage_dealt)

func _on_damage_dealt(attacker, defender, amount):
    print("Damage: %s -> %s = %f" % [attacker.name, defender.name, amount])
```

#### 2.3.3 资源管理

使用 Godot 的 FileAccess 和 JSON 进行配置加载：

```gdscript
# autoload/resource_manager.gd
extends Node

var config_cache: Dictionary = {}

func load_json(path: String) -> Variant:
    if path in config_cache:
        return config_cache[path]

    var file = FileAccess.open(path, FileAccess.READ)
    if not file:
        push_error("无法加载配置文件: %s" % path)
        return null

    var text = file.get_as_text()
    var json = JSON.new()
    var error = json.parse(text)

    if error != OK:
        push_error("JSON解析错误: %s" % json.get_error_message())
        return null

    config_cache[path] = json.data
    return json.data
```

---

## 三、验证步骤

### 3.1 阶段一：基础框架验证（1周）

#### 任务清单

| 任务 | 描述 | 完成标准 |
|------|------|----------|
| 项目初始化 | 创建Godot项目，配置Autoload | 项目可正常运行 |
| 事件系统 | 测试Signals机制 | 支持信号订阅和触发 |
| 资源管理 | 实现JSON配置加载 | 支持配置加载和缓存 |
| 输入系统 | 配置InputMap | 支持键鼠和控制器 |

#### 测试用例

**测试1：Autoload单例**

```gdscript
# test/autoload_test.gd
extends SceneTree

func _init():
    var gm1 = GameManager
    var gm2 = GameManager
    assert(gm1 == gm2, "单例模式失败")
    print("Autoload单例测试通过")
```

**测试2：Signals事件系统**

```gdscript
# test/signal_test.gd
extends Node

var received_message: String = ""

func _ready():
    EventManager.damage_dealt.connect(_on_damage)
    EventManager.damage_dealt.emit(self, self, 100.0)

func _on_damage(attacker, defender, amount):
    assert(amount == 100.0, "信号参数错误")
    print("Signals事件系统测试通过")
```

**测试3：JSON配置加载**

```gdscript
# test/json_test.gd
extends SceneTree

func _init():
    var test_data = {"name": "test", "value": 42}
    var json_string = JSON.stringify(test_data)

    var file = FileAccess.open("user://test_config.json", FileAccess.WRITE)
    file.store_string(json_string)
    file.close()

    var loaded = ResourceManager.load_json("user://test_config.json")
    assert(loaded["name"] == "test", "配置加载失败")
    assert(loaded["value"] == 42, "配置值错误")
    print("JSON配置加载测试通过")
```

### 3.2 阶段二：战斗系统验证（2周）

#### 任务清单

| 任务 | 描述 | 完成标准 |
|------|------|----------|
| 角色控制 | 实现玩家移动、旋转、跳跃 | 流畅的角色控制 |
| 武器系统 | 实现近战和远程攻击 | 攻击动作和伤害计算 |
| 伤害系统 | 实现伤害类型和伤害计算 | 支持8种伤害类型 |
| 状态系统 | 实现HP、能量、体力管理 | 状态条显示和更新 |
| 碰撞系统 | 实现攻击碰撞和伤害判定 | 准确的碰撞检测 |

#### 核心代码示例

**角色控制器：**

```gdscript
# scripts/battle/player_controller.gd
extends CharacterBody2D

@export var speed: float = 200.0
@export var jump_force: float = -400.0
@export var gravity: float = 980.0

func _physics_process(delta: float):
    if not is_on_floor():
        velocity.y += gravity * delta

    var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")

    if input_dir.length() > 0.1:
        velocity.x = input_dir.x * speed
        velocity.y = input_dir.y * speed
    else:
        velocity.x = move_toward(velocity.x, 0, speed)
        velocity.y = move_toward(velocity.y, 0, speed)

    if is_on_floor() and Input.is_action_just_pressed("jump"):
        velocity.y = jump_force

    move_and_slide()
```

**伤害系统：**

```gdscript
# scripts/battle/damage_system.gd
class_name DamageSystem
extends RefCounted

enum DamageType {
    PUNCTURE,
    SLASH,
    SMASH,
    FIRE,
    LIGHTNING,
    ICE,
    POISON,
    WIND
}

func calculate_damage(attacker: Node2D, defender: Node2D, damage_type: DamageType, base_damage: float) -> float:
    var final_damage = base_damage

    var defense_ratio = _get_defense_ratio(defender, damage_type)
    final_damage *= (1.0 - defense_ratio)

    var attack_bonus = _get_attack_bonus(attacker, damage_type)
    final_damage *= (1.0 + attack_bonus)

    return final_damage

func _get_defense_ratio(target: Node2D, damage_type: DamageType) -> float:
    var defense_params = target.get("defense_params") if target.has_method("get") else {}
    if defense_params.is_empty():
        return 0.0
    var ratio_key = _damage_type_to_key(damage_type)
    return defense_params.get(ratio_key, 0.0)

func _get_attack_bonus(attacker: Node2D, damage_type: DamageType) -> float:
    var attack_params = attacker.get("attack_params") if attacker.has_method("get") else {}
    if attack_params.is_empty():
        return 0.0
    var bonus_key = _damage_type_to_key(damage_type)
    return attack_params.get(bonus_key, 0.0)

func _damage_type_to_key(damage_type: DamageType) -> String:
    match damage_type:
        DamageType.PUNCTURE: return "puncture_ratio"
        DamageType.SLASH: return "slash_ratio"
        DamageType.SMASH: return "smash_ratio"
        DamageType.FIRE: return "fire_ratio"
        DamageType.LIGHTNING: return "lightning_ratio"
        DamageType.ICE: return "ice_ratio"
        DamageType.POISON: return "poison_ratio"
        DamageType.WIND: return "wind_ratio"
        _: return "default_ratio"
```

#### 测试用例

**测试1：伤害计算**

```gdscript
# test/damage_test.gd
extends Node

func _ready():
    var ds = DamageSystem.new()

    var attacker = Node2D.new()
    attacker.set("attack_params", {"fire_power": 0.5})

    var defender = Node2D.new()
    defender.set("defense_params", {"fire_ratio": 0.2})

    var damage = ds.calculate_damage(attacker, defender, DamageSystem.DamageType.FIRE, 100.0)

    # 预期伤害: 100 * (1 - 0.2) * (1 + 0.5) = 120
    assert(abs(damage - 120.0) < 0.1, "伤害计算错误: %f" % damage)
    print("伤害系统测试通过")
    quit()
```

### 3.3 阶段三：AI系统验证（1周）

#### 任务清单

| 任务 | 描述 | 完成标准 |
|------|------|----------|
| 行为树框架 | 实现行为树节点基类 | 支持选择器、序列、条件节点 |
| 寻路系统 | 使用NavigationAgent2D | 实现A*寻路 |
| 基础AI | 实现搜索、跟随、攻击行为 | AI能追踪并攻击玩家 |
| Boss AI | 实现多阶段Boss行为 | 支持阶段切换 |

#### 核心代码示例

**行为树框架：**

```gdscript
# scripts/ai/behavior_tree.gd
class_name BehaviorTree
extends RefCounted

enum NodeStatus {
    SUCCESS,
    FAILURE,
    RUNNING
}

class BehaviorNode:
    var status: NodeStatus = NodeStatus.FAILURE

    func tick(delta: float) -> NodeStatus:
        return status

class SelectorNode extends BehaviorNode:
    var children: Array[BehaviorNode] = []

    func tick(delta: float) -> NodeStatus:
        for child in children:
            var child_status = child.tick(delta)
            if child_status == NodeStatus.SUCCESS or child_status == NodeStatus.RUNNING:
                return child_status
        return NodeStatus.FAILURE

class SequenceNode extends BehaviorNode:
    var children: Array[BehaviorNode] = []

    func tick(delta: float) -> NodeStatus:
        for child in children:
            var child_status = child.tick(delta)
            if child_status == NodeStatus.FAILURE or child_status == NodeStatus.RUNNING:
                return child_status
        return NodeStatus.SUCCESS
```

**AI控制器：**

```gdscript
# scripts/ai/ai_controller.gd
extends CharacterBody2D

@export var detection_range: float = 200.0
@export var attack_range: float = 40.0
@export var speed: float = 100.0

var target: Node2D = null
var behavior_tree: BehaviorTree.BehaviorNode = null
var navigation_agent: NavigationAgent2D = null

func _ready():
    navigation_agent = get_node("NavigationAgent2D")
    _setup_behavior_tree()

func _setup_behavior_tree():
    var root = BehaviorTree.SequenceNode.new()

    var detect_player = DetectPlayerNode.new()
    detect_player.ai = self

    var move_to_player = MoveToPlayerNode.new()
    move_to_player.ai = self

    var attack_player = AttackPlayerNode.new()
    attack_player.ai = self

    root.children = [detect_player, move_to_player, attack_player]
    behavior_tree = root

func _physics_process(delta: float):
    if behavior_tree:
        behavior_tree.tick(delta)

func find_player() -> Node2D:
    var players = get_tree().get_nodes_in_group("players")
    for player in players:
        var distance = global_position.distance_to(player.global_position)
        if distance <= detection_range:
            return player
    return null
```

#### 测试用例

**测试1：行为树执行**

```gdscript
# test/behavior_tree_test.gd
extends Node

func _ready():
    var selector = BehaviorTree.SelectorNode.new()
    var sequence = BehaviorTree.SequenceNode.new()

    var success_node = SuccessNode.new()
    sequence.children = [success_node, success_node]
    selector.children = [sequence]

    var status = selector.tick(0.1)
    assert(status == BehaviorTree.NodeStatus.SUCCESS, "行为树测试失败")
    print("行为树测试通过")
    quit()
```

### 3.4 阶段四：UI系统验证（1周）

#### 任务清单

| 任务 | 描述 | 完成标准 |
|------|------|----------|
| UI管理器 | 使用CanvasLayer实现UI层级管理 | 支持界面显示和隐藏 |
| HUD界面 | 实现战斗HUD | 显示HP、能量、弹药 |
| 菜单系统 | 实现主菜单和暂停菜单 | 支持菜单切换 |
| 动画系统 | 使用AnimationPlayer | 平滑的界面切换 |

#### 核心代码示例

**UI管理器：**

```gdscript
# scripts/ui/ui_manager.gd
extends CanvasLayer

var current_screen: Control = null
var screens: Dictionary = {}

func register_screen(screen_name: String, screen: Control):
    screens[screen_name] = screen
    screen.visible = false

func show_screen(screen_name: String):
    if current_screen:
        current_screen.visible = false

    if screen_name in screens:
        current_screen = screens[screen_name]
        current_screen.visible = true

func hide_screen(screen_name: String):
    if screen_name in screens:
        screens[screen_name].visible = false
        if current_screen == screens[screen_name]:
            current_screen = null
```

**战斗HUD：**

```gdscript
# scripts/ui/battle_hud.gd
extends Control

@onready var hp_bar: ProgressBar = $HPBar
@onready var energy_bar: ProgressBar = $EnergyBar
@onready var stamina_bar: ProgressBar = $StaminaBar
@onready var ammo_text: Label = $AmmoText

func update_hp(current: float, max_value: float):
    hp_bar.value = (current / max_value) * 100.0

func update_energy(current: float, max_value: float):
    energy_bar.value = (current / max_value) * 100.0

func update_stamina(current: float, max_value: float):
    stamina_bar.value = (current / max_value) * 100.0

func update_ammo(current: int, total: int):
    ammo_text.text = "%d/%d" % [current, total]
```

#### 测试用例

**测试1：UI切换**

```gdscript
# test/ui_test.gd
extends Node

func _ready():
    var ui_manager = UIManager

    var screen1 = Control.new()
    screen1.name = "Screen1"
    ui_manager.register_screen("Screen1", screen1)

    var screen2 = Control.new()
    screen2.name = "Screen2"
    ui_manager.register_screen("Screen2", screen2)

    ui_manager.show_screen("Screen1")
    assert(screen1.visible == true, "界面显示失败")
    assert(screen2.visible == false, "界面隐藏失败")

    ui_manager.show_screen("Screen2")
    assert(screen1.visible == false, "界面切换失败")
    assert(screen2.visible == true, "界面切换失败")

    print("UI系统测试通过")
    quit()
```

### 3.5 阶段五：数据系统验证（0.5周）

#### 任务清单

| 任务 | 描述 | 完成标准 |
|------|------|----------|
| 配置加载 | 实现JSON配置加载 | 支持游戏数据配置 |
| 存档系统 | 实现存档和读档 | 支持玩家进度保存 |

#### 核心代码示例

**存档系统：**

```gdscript
# scripts/utils/save_system.gd
extends Node

const SAVE_DIR = "user://saves/"
const SAVE_FILE = "save.json"

func save_game(data: Dictionary):
    DirAccess.make_dir_recursive_absolute(SAVE_DIR)

    var file = FileAccess.open(SAVE_DIR + SAVE_FILE, FileAccess.WRITE)
    if file:
        var json_string = JSON.stringify(data, "\t")
        file.store_string(json_string)
        file.close()
        print("存档成功")
    else:
        push_error("存档失败")

func load_game() -> Dictionary:
    var file = FileAccess.open(SAVE_DIR + SAVE_FILE, FileAccess.READ)
    if file:
        var content = file.get_as_text()
        var json = JSON.new()
        var error = json.parse(content)
        if error == OK:
            return json.data
    return {}
```

---

## 四、性能测试方案

### 4.1 测试环境

| 项目 | 规格 |
|------|------|
| 操作系统 | Windows 10/11 |
| CPU | Intel i7 / AMD Ryzen 7 |
| GPU | NVIDIA RTX 3070 / AMD RX 6800 |
| 内存 | 16GB DDR4 |
| Godot版本 | 4.3.x stable |

### 4.2 性能指标

| 指标 | 目标值 | 测量方法 |
|------|--------|----------|
| 帧率 | ≥60 FPS | Godot Profiler |
| CPU占用 | ≤30% | Godot Profiler |
| 内存占用 | ≤2GB | 操作系统监控 |
| 加载时间 | ≤3秒 | 手动计时 |

### 4.3 测试场景

| 场景 | 条件 | 持续时间 | 测量指标 |
|------|------|----------|----------|
| 战斗性能 | 10个敌人同时战斗 | 60秒 | 帧率、CPU占用 |
| AI性能 | 20个AI同时寻路 | 30秒 | 帧率、寻路响应时间 |
| UI性能 | 频繁切换UI界面(100次) | - | 界面切换延迟 |

---

## 五、验证标准

### 5.1 通过标准

| 模块 | 通过条件 |
|------|----------|
| 核心架构 | Autoload和Signals系统正常工作 |
| 战斗系统 | 角色控制流畅，伤害计算准确 |
| AI系统 | AI能正确追踪并攻击玩家 |
| UI系统 | 界面显示正常，切换流畅 |
| 物理系统 | 碰撞检测准确，角色移动流畅 |
| 性能指标 | 帧率≥60 FPS，CPU占用≤30% |

### 5.2 未通过标准

| 模块 | 未通过条件 |
|------|----------|
| 核心架构 | Autoload或Signals无法正常工作 |
| 战斗系统 | 无法实现核心战斗机制 |
| AI系统 | AI行为不符合预期 |
| UI系统 | UI显示异常或无法交互 |
| 性能指标 | 帧率持续低于30 FPS |

### 5.3 改进方向

如果验证过程中发现问题：

1. 分析问题原因
2. 寻找替代方案
3. 调整技术方案
4. 重新测试验证

---

## 六、时间规划

### 6.1 总体时间：4-5周

| 阶段 | 时间 | 主要任务 | 交付物 |
|------|------|----------|--------|
| 阶段一 | 第1周 | 基础框架验证 | 可运行的基础框架 |
| 阶段二 | 第2-3周 | 战斗系统验证 | 战斗原型Demo |
| 阶段三 | 第4周 | AI系统验证 | AI原型Demo |
| 阶段四 | 第4周 | UI系统验证 | UI原型Demo |
| 阶段五 | 第5周 | 数据系统验证+性能测试 | 完整验证报告 |

### 6.2 里程碑

| 里程碑 | 时间 | 完成标准 |
|--------|------|----------|
| M1 | 第1周 | 基础框架完成，测试通过 |
| M2 | 第3周 | 战斗系统完成，可进行战斗 |
| M3 | 第4周 | AI系统完成，可与AI战斗 |
| M4 | 第5周 | 完整验证完成，提交报告 |

---

## 七、资源需求

### 7.1 人力资源

- **游戏程序员**: 1-2人
- **技术美术**: 0.5人（仅用于测试资源）

### 7.2 硬件资源

- 开发电脑：高配置PC
- 测试设备：多种配置的PC

### 7.3 软件资源

- Godot 4.3.x stable
- Git版本控制
- 项目管理工具（Trello）

---

## 八、风险评估

### 8.1 主要风险

| 风险 | 概率 | 影响 | 应对措施 |
|------|------|------|----------|
| GDScript性能不足 | 中 | 高 | 提前进行性能测试 |
| 物理系统差异 | 中 | 中 | 调整物理参数 |
| 渲染效果差异 | 低 | 中 | 使用Godot着色器优化 |
| 学习曲线陡峭 | 低 | 低 | GDScript语法简洁，上手快 |

### 8.2 风险应对策略

1. **性能风险**: 建立性能基准测试，及时优化关键路径
2. **技术风险**: 制定技术选型标准，备选方案准备
3. **进度风险**: 制定详细计划，设置关键里程碑

---

## 九、验证报告模板

### 9.1 报告结构

```
1. 验证概述
   - 验证目标
   - 验证范围
   - 验证环境

2. 验证结果
   - 各模块验证结果
   - 性能测试结果
   - 问题汇总

3. 可行性评估
   - 技术可行性
   - 性能可行性
   - 时间可行性

4. 建议
   - 迁移建议
   - 改进建议
   - 后续步骤
```

### 9.2 结论标准

| 结论 | 条件 |
|------|------|
| 强烈推荐迁移 | 所有模块验证通过，性能达标 |
| 推荐迁移 | 核心模块通过，存在少量问题可解决 |
| 谨慎考虑 | 部分模块存在问题，需要额外工作 |
| 不推荐迁移 | 核心模块无法通过，性能不达标 |

---

## 十、附录

### 10.1 GDScript常用API参考

```gdscript
# 变量声明
var name: String = "value"
var count: int = 0
var speed: float = 5.0
var is_active: bool = true

# 函数定义
func function_name(param: String) -> int:
    return 0

# 信号
signal my_signal(param)
emit_signal("my_signal", value)
my_signal.connect(callable)

# 异步
func _ready():
    await get_tree().create_timer(1.0).timeout
    print("1秒后执行")

# JSON操作
var data = {"key": "value"}
var json_string = JSON.stringify(data)
var json = JSON.new()
json.parse(json_string)
var parsed = json.data

# 文件操作
var file = FileAccess.open(path, FileAccess.READ)
var content = file.get_as_text()
file.close()

# 节点操作
var node = get_node("Path/To/Node")
var node = $Path/To/Node
add_child(child_node)
node.queue_free()

# 场景加载
var scene = load("res://path/to/scene.tscn")
var instance = scene.instantiate()
```

### 10.2 参考资源

| 资源 | 链接 |
|------|------|
| Godot官方文档 | https://docs.godotengine.org/ |
| GDScript语法参考 | https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/index.html |
| Godot社区论坛 | https://godotengine.org/qa/ |
| GitHub示例项目 | https://github.com/godotengine/godot-demo-projects |

---

**文档版本**: v2.0
**创建日期**: 2026-06-22
**验证周期**: 4-5周
**目标语言**: GDScript 4.x
