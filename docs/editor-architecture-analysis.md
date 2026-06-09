# 编辑器模块架构分析

> 分析日期: 2026-06-09
> 目标: 识别高耦合、语义偏离、YAGNI 问题

---

## 1. 概览数据

| 文件 | 行数 | 占比 |
|------|------|------|
| TitleMenu.lua | 5,911 | 35.4% |
| Renderer.lua | 1,355 | 8.1% |
| NodeCanvas.lua | 1,170 | 7.0% |
| SpriteEditor.lua | 1,001 | 6.0% |
| 其余 15 个文件 | 7,259 | 43.5% |
| **合计** | **16,696** | 100% |

`TitleMenu.lua` 单文件占全项目超过三分之一代码量。

---

## 2. God File: TitleMenu.lua

### 2.1 职责混杂（6 个不相关关注点）

| 行范围 | 实际职责 | 函数数 |
|--------|---------|--------|
| 66-859 | 主菜单流程 (转场、章节选择、面板切换) | 19 |
| 1000-1340 | 图层编辑器 (背景图层管理) | 10 |
| 1340-1487 | 关卡选择面板 | 3 |
| 1613-4113 | 关卡编辑器核心 (物件增删改、工具、属性面板) | 30 |
| 4119-4960 | 预览/物理仿真系统 (Box2D 场景、相机跟随、碰撞) | 10 |
| 4960-5702 | NanoVG 渲染 (画布贴图、预览绘制) | 2 (极长函数) |
| 5703-5911 | 策略执行 + 数据 I/O | 4 |

**结论**: 一个名为 "TitleMenu" 的文件中，80% 的代码与菜单无关，属于典型 God File 反模式。

### 2.2 God Object: `levelEditor_`

`levelEditor_` 表包含 **40+ 字段**，在文件中被引用 **564 次**。字段混合了完全不相关的状态域:

| 状态域 | 字段示例 |
|--------|---------|
| 身份标识 | `active`, `chapterIdx`, `levelIdx` |
| 世界几何 | `worldW`, `worldH`, `gridSize`, `objects` |
| 选择/工具 | `currentTool`, `selectedObj`, `mappingMode` |
| 画布视口 | `canvasPanX/Y`, `canvasPanning`, `canvasPanStartX/Y` |
| 拖拽状态 | `dragging`, `dragObjIdx`, `dragOffsetX/Y`, `dragStarted` |
| 背景图层 | `bgLayers`, `selectedBgLayer`, `bgDragging`, `bgDragType` |
| 贴图拖拽 | `texDragging`, `texDragType`, `texDragStartX/Y` |
| 镜头范围 | `cameraBounds`, `cameraBoundsEnabled`, `camBoundsDragging` |
| 预览/仿真 | `previewActive`, `previewScene`, `previewPlayerNode`, `previewOnGround` |
| 颜色选择器 | `colorPickerOpen`, `colorPickerH/S/V`, `colorHistory` |
| NanoVG 缓存 | `nvgTextures` |
| 撤销系统 | `undoStack`, `maxUndo` |

**问题**: 任何函数都能读写任何字段，无法做局部推理，修改一处可能波及全局。

---

## 3. 语义偏离 (Semantic Drift)

### 3.1 文件名 vs 实际内容

| 文件名 | 期望含义 | 实际内容 | 偏离程度 |
|--------|---------|---------|---------|
| **TitleMenu.lua** | 标题菜单逻辑 | 菜单 + 图层编辑器 + 关卡编辑器 + 预览系统 + 渲染 | 严重 |
| **Renderer.lua** | 通用渲染管线 | 关卡编辑器画布的 NanoVG 渲染 + 调用 TitleMenu 的绘制函数 | 中度 |

### 3.2 函数名 vs 实际行为

- `M.UpdateLevelEditor(dt)` (line 1905): 单函数 734 行，处理输入事件解析、拖拽状态机、画布平移、物件创建、贴图操作、镜头范围编辑——远超 "update" 的语义。
- `M.BuildLevelEditorUI()` (line 2639): 单函数 527 行，构建整个编辑器侧边栏 UI 树。
- `M._executeStrategy()` (line 5703): 策略/行为树执行器嵌入在 "TitleMenu" 模块中。

### 3.3 模块名与导入关系矛盾

```
main.lua
  └─ require("TitleMenu")     -- 期望: 菜单逻辑
  └─ require("Renderer")      -- 期望: 独立渲染器

Renderer.lua
  └─ require("TitleMenu")     -- 反向依赖! 渲染器依赖菜单模块
```

**渲染器不应该依赖 UI 层**——这是典型的依赖倒置。正确方向应该是 `TitleMenu → Renderer`，而非反过来。

---

## 4. YAGNI 问题 (You Aren't Gonna Need It)

### 4.1 过度设计

| 功能 | 行数估计 | YAGNI 原因 |
|------|---------|-----------|
| HSV 色环选择器 | ~100 行 | 编辑器物件只用了固定颜色分类，完整色环选择器使用率极低 |
| 颜色历史记录系统 | ~30 行 | 同上，`colorHistory` 保存最近 10 色但场景中仅用于物件高亮 |
| 贴图图层系统 (多图层、排序、锚点拖拽) | ~200 行 | 当前关卡实际只使用单色方块，贴图功能处于半成品状态 |
| 策略执行器 `_executeStrategy` | ~60 行 | 嵌入编辑器模块中的运行时逻辑，应独立为运行时模块 |
| 50 步撤销栈 + 深拷贝快照 | ~40 行 | 合理功能，但序列化整个 objects 表的方式对大型关卡有性能风险 |

### 4.2 未使用/死代码倾向

- `mappingMode` / `mappingTriggerIdx`: 触发器映射编辑模式，代码复杂度高但使用频率未知
- `texDragging` / `texDragType` / 相关 6 个字段: 贴图锚点旋转/缩放的完整状态机，但贴图功能本身未完成

---

## 5. 耦合分析

### 5.1 模块依赖图

```
main.lua (19 imports)
    │
    ├── TitleMenu.lua ◄──── Renderer.lua (反向依赖!)
    │       │
    │       ├── 内含: 菜单流程
    │       ├── 内含: 图层编辑器
    │       ├── 内含: 关卡编辑器
    │       ├── 内含: 预览系统
    │       └── 内含: NanoVG 渲染
    │
    ├── NodeCanvas.lua (1,170 行 - 节点画布)
    ├── SpriteEditor.lua (1,001 行 - 精灵编辑)
    ├── StrategyNode.lua (799 行 - 策略节点)
    └── ... (其余模块)
```

### 5.2 耦合热点

1. **`levelEditor_` 的 564 次引用** — 所有编辑器功能通过共享可变状态通信，无接口隔离
2. **Renderer → TitleMenu 反向依赖** — 渲染器直接调用 `TitleMenu.DrawEditorCanvasTextures()` 和 `TitleMenu.DrawPreview()`
3. **main.lua 19 个 import** — 扇入过高，本应由分层架构分摊

### 5.3 变更影响分析

修改以下任何一项，都可能需要在 TitleMenu.lua 内多处改动:

| 修改目标 | 影响范围 |
|---------|---------|
| 添加新的编辑器工具 | UpdateLevelEditor + BuildLevelEditorUI + BuildPropsPanel + DrawEditorCanvasTextures |
| 修改画布坐标系 | WorldToCanvas + CanvasToWorld + 所有拖拽逻辑 + 预览渲染 |
| 修改预览相机 | StartPreview + UpdatePreview + DrawPreview + cameraBounds 相关 |

理想状态下每次修改只应涉及 1-2 个文件，当前架构下通常涉及 3-5 处。

---

## 6. 建议拆分方案

### 目标结构

```
scripts/
├── main.lua                    # 入口协调器 (精简为 <200 行)
├── GameConfig.lua              # 保持不变
├── GameState.lua               # 保持不变
│
├── menu/
│   ├── MenuFlow.lua            # 转场 + 主菜单 + 章节选择 (~800 行)
│   └── LevelSelect.lua         # 关卡选择面板 (~200 行)
│
├── editor/
│   ├── EditorState.lua         # levelEditor_ 状态定义 + 访问接口 (~150 行)
│   ├── LevelEditor.lua         # 核心逻辑: 物件 CRUD、工具切换 (~800 行)
│   ├── LevelEditorUI.lua       # BuildLevelEditorUI + BuildPropsPanel (~600 行)
│   ├── LevelEditorInput.lua    # UpdateLevelEditor 中的输入/拖拽逻辑 (~500 行)
│   ├── LayerEditor.lua         # 背景图层管理 (~350 行)
│   ├── ColorPicker.lua         # HSV 色环 + 颜色历史 (~150 行)
│   └── EditorPreview.lua       # StartPreview + UpdatePreview + 碰撞 (~800 行)
│
├── renderer/
│   ├── EditorCanvasRenderer.lua  # DrawEditorCanvasTextures (~330 行)
│   └── PreviewRenderer.lua       # DrawPreview (~400 行)
│
└── ... (其余游戏模块保持不变)
```

### 拆分优先级

| 优先级 | 拆分动作 | 收益 |
|--------|---------|------|
| P0 | 将菜单流程 (66-859) 从 TitleMenu 独立 | 消除最严重的语义偏离 |
| P0 | 将预览系统 (4119-4960) 独立 | 解除 Renderer 反向依赖 |
| P1 | 将编辑器输入处理从 UpdateLevelEditor 独立 | 734 行函数拆为可测试单元 |
| P1 | 将 NanoVG 渲染 (4960-5702) 移入 Renderer 侧 | 统一渲染职责 |
| P2 | 将 levelEditor_ 替换为 EditorState 模块 | 限制字段访问范围 |
| P2 | 将颜色选择器独立 | 消除 YAGNI，可按需加载 |

---

## 7. 总结

| 维度 | 评分 | 说明 |
|------|------|------|
| **耦合度** | 高 | God Object + 反向依赖 + 共享可变状态 |
| **语义偏离** | 严重 | "TitleMenu" 实际是整个编辑器系统 |
| **YAGNI** | 中度 | 色环、贴图图层系统为过度设计 |
| **可维护性** | 低 | 单函数 734 行、单文件 5911 行、修改波及面广 |
| **是否"屎山"** | 是 (早期) | 功能可运行但架构债务在快速积累，再增加 2-3 个功能将进入不可维护阶段 |

**核心问题一句话**: TitleMenu.lua 是一个挂着菜单名字的编辑器全家桶，所有状态塞在一个 40 字段的 table 里，任何改动都可能引发连锁反应。
