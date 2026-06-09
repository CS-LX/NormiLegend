# 编辑器代码重构策划案

> 根本原则: **不修改编辑器语义** — 所有阶段均为纯提取式重构，行为与重构前完全一致。
>
> 基于: `docs/editor-architecture-analysis.md`

---

## 重构策略

采用 **Extract Module** 模式:
1. 从 `TitleMenu.lua` 中整块提取函数和状态到新模块
2. 新模块 export 相同接口
3. `TitleMenu.lua` 通过 `require` 引入新模块，对外 API 保持不变（转发调用）
4. 外部调用方（main.lua、Renderer.lua）**零修改**或**最小修改**

每个阶段独立可回滚，每个阶段结束产出可运行版本。

---

## 阶段一: 提取编辑器状态 (EditorState.lua)

**目标**: 将 God Object `levelEditor_` 提取为独立模块，统一管理编辑器状态。

**操作**:
1. 创建 `scripts/editor/EditorState.lua`
2. 将 `levelEditor_` 表定义（line 1496-1595）完整迁移
3. 将相关工具常量 `EDITOR_TOOLS`（line 1599-1610）迁移
4. 将辅助函数迁移: `WorldToCanvas`, `CanvasToWorld`, `GetObjectColor`
5. `TitleMenu.lua` 改为 `local EditorState = require("editor.EditorState")`，用 `EditorState.state` 替换 `levelEditor_`

**变更文件**:
- 新增: `scripts/editor/EditorState.lua`
- 修改: `scripts/TitleMenu.lua`（替换 `levelEditor_` 引用为 `EditorState.state`）

**冒烟测试**:
- [ ] 构建通过（无 LSP Error）
- [ ] 进入主菜单 → 正常显示
- [ ] 进入关卡编辑器 → 画布渲染正常、网格可见
- [ ] 选择工具 → 创建平台/地面 → 拖拽物件 → 正常
- [ ] 进入预览 → 角色可跳跃、镜头跟随正常
- [ ] 退出编辑器 → 回到菜单正常

---

## 阶段二: 提取预览系统 (EditorPreview.lua)

**目标**: 将预览/仿真系统整块提取，解除 Renderer 对 TitleMenu 的隐式依赖。

**操作**:
1. 创建 `scripts/editor/EditorPreview.lua`
2. 迁移函数:
   - `StartPreview` (line 4119-4339)
   - `StopPreview` (line 4340-4431)
   - `RefreshPreviewTerrain` (line 4432-4472)
   - `UpdatePreview` (line 4473-4912)
   - `IsPreviewActive` (line 4913)
   - `JustStoppedPreview` (line 4918)
   - `HandlePreviewBeginContact` (line 4923)
   - `HandlePreviewEndContact` (line 4942)
   - `DrawPreview` (line 5290-5702)
3. 新模块 import `EditorState` 获取状态
4. `TitleMenu.lua` 中保留转发:
   ```lua
   local EditorPreview = require("editor.EditorPreview")
   M.StartPreview = EditorPreview.StartPreview
   M.IsPreviewActive = EditorPreview.IsPreviewActive
   -- ... 其余同理
   ```

**变更文件**:
- 新增: `scripts/editor/EditorPreview.lua`
- 修改: `scripts/TitleMenu.lua`（删除预览代码，添加转发）

**冒烟测试**:
- [ ] 构建通过
- [ ] 编辑器中点击"预览"按钮 → 正常进入预览
- [ ] 预览中角色移动 → 相机跟随 → 在镜头范围内
- [ ] 预览中碰撞检测正常（角色站在平台上不穿透）
- [ ] 预览中触发器触发弹出文本
- [ ] 点击"停止"→ 退出预览回到编辑器
- [ ] 再次进入预览 → 无残留状态

---

## 阶段三: 提取编辑器渲染 (EditorRenderer.lua)

**目标**: 将 NanoVG 画布绘制逻辑集中到独立渲染模块，消除 Renderer → TitleMenu 反向依赖。

**操作**:
1. 创建 `scripts/editor/EditorRenderer.lua`
2. 迁移:
   - `GetNvgTexture` local function (line 4960-4972)
   - `DrawEditorCanvasTextures` (line 4974-5289)
3. 新模块 import `EditorState`、`NodeCanvas`
4. `TitleMenu.lua` 保留转发
5. **关键**: `Renderer.lua` 中的 `TitleMenu.DrawEditorCanvasTextures` 和 `TitleMenu.DrawPreview` 调用改为直接调用新模块（或保持调用 TitleMenu 转发——此阶段选择后者以最小化变更）

**变更文件**:
- 新增: `scripts/editor/EditorRenderer.lua`
- 修改: `scripts/TitleMenu.lua`（删除渲染代码，添加转发）

**冒烟测试**:
- [ ] 构建通过
- [ ] 编辑器画布正常渲染（网格线、物件方块、贴图图层）
- [ ] 背景图层显示正确（透明度、层次）
- [ ] 选中物件高亮正常
- [ ] 镜头范围黄色框显示正常
- [ ] 画布缩放/平移后渲染位置正确

---

## 阶段四: 提取菜单流程 (MenuFlow.lua)

**目标**: 将菜单/转场/章节选择逻辑独立，让文件名回归语义。

**操作**:
1. 创建 `scripts/menu/MenuFlow.lua`
2. 迁移函数 (line 66-859):
   - 过场系统: `ShowTransition`, `UpdateTransition`, `IsTransitionActive`
   - 标题: `ShowTitleScreen`, `DismissTitleScreen`
   - 主菜单: `ShowMainMenu`, `ShowMenuPanel`, `CloseMenuPanel`, `IsMenuPanelOpen`
   - 章节选择: `ShowChapterSelect`, `CloseChapterSelect`, `IsChapterSelectOpen`, `ChapterNavigate`, `LayoutChapterCards`, `UpdateChapterSelect`
   - 导航: `EnterGameFromMenu`, `EnterGameWorld`, `ReturnToChapterSelect`
   - 动画: `UpdateMainMenuAnimation`
3. 迁移相关状态: `transition_`, `mainMenuTime_`, `menuPanelOverlay_`
4. `TitleMenu.lua` 保留转发（对 main.lua 零影响）

**变更文件**:
- 新增: `scripts/menu/MenuFlow.lua`
- 修改: `scripts/TitleMenu.lua`（删除菜单代码，添加转发）

**冒烟测试**:
- [ ] 构建通过
- [ ] 启动游戏 → 标题画面正常显示
- [ ] 点击进入 → 主菜单显示、按钮可点击
- [ ] 打开功能面板（任务/角色）→ 正常弹出和关闭
- [ ] 进入章节选择 → 卡片渲染正常、左右导航正常
- [ ] 选择章节进入关卡选择 → 正常
- [ ] ESC 逐级返回 → 各层级正确退出

---

## 阶段五: 提取编辑器 UI 构建 (LevelEditorUI.lua)

**目标**: 将 UI 树构建逻辑独立（最大的两个函数: BuildLevelEditorUI 527行 + BuildPropsPanel 908行）。

**操作**:
1. 创建 `scripts/editor/LevelEditorUI.lua`
2. 迁移:
   - `BuildLevelEditorUI` (line 2639-3165)
   - `BuildPropsPanel` (line 3166-4073)
3. 这两个函数大量引用 `levelEditor_` → 通过 `EditorState.state` 访问
4. 回调函数中调用的编辑器核心方法（如 PushUndoState）→ 通过 `require("TitleMenu")` 或参数注入

**变更文件**:
- 新增: `scripts/editor/LevelEditorUI.lua`
- 修改: `scripts/TitleMenu.lua`（删除 UI 构建代码，添加转发）

**冒烟测试**:
- [ ] 构建通过
- [ ] 进入编辑器 → 左侧工具栏渲染正常
- [ ] 选择物件 → 右侧属性面板显示正确
- [ ] 修改物件属性（位置、尺寸、名称）→ 即时生效
- [ ] 切换工具 → 面板切换正常
- [ ] 贴图工具面板 → 图层操作正常

---

## 阶段六: 清理转发层 + 重命名

**目标**: 最终清理，让 `TitleMenu.lua` 回归为薄代理或直接重命名。

**操作**:
1. 将 `TitleMenu.lua` 剩余代码（关卡选择面板、编辑器核心逻辑、图层编辑器）迁移到:
   - `scripts/menu/LevelSelect.lua` — 关卡选择 (line 1340-1487)
   - `scripts/editor/LayerEditor.lua` — 图层管理 (line 1000-1339)
   - `scripts/editor/LevelEditorCore.lua` — 核心 CRUD + 输入处理 (剩余)
2. `TitleMenu.lua` 最终变为纯转发模块（~50 行），仅做 require 和 re-export
3. 更新 `main.lua` 和 `Renderer.lua` 直接 require 对应子模块（消除转发层）
4. 可选: 将 `TitleMenu.lua` 重命名为 `EditorFacade.lua`

**变更文件**:
- 新增: `scripts/menu/LevelSelect.lua`, `scripts/editor/LayerEditor.lua`, `scripts/editor/LevelEditorCore.lua`
- 修改: `scripts/TitleMenu.lua`（精简为转发）
- 修改: `scripts/main.lua`, `scripts/Renderer.lua`（可选，直接引用子模块）

**冒烟测试**:
- [ ] 完整流程测试: 标题 → 菜单 → 章节 → 关卡选择 → 编辑器 → 预览 → 退出 → 菜单
- [ ] 图层编辑器打开/关闭/编辑/导出正常
- [ ] 编辑器所有工具正常（选择、平台、障碍、触发器、执行器、地面、贴图、删除）
- [ ] 撤销功能正常
- [ ] 保存/加载关卡数据正常

---

## 最终目录结构

```
scripts/
├── main.lua                     # 入口 (不变或微调 import)
├── GameConfig.lua               # 不变
├── GameState.lua                # 不变
├── Renderer.lua                 # 不变 (或改为直接调用 editor/ 模块)
│
├── TitleMenu.lua                # 精简为转发层 (~50 行)
│
├── menu/
│   ├── MenuFlow.lua             # 转场 + 标题 + 主菜单 + 章节选择
│   └── LevelSelect.lua          # 关卡选择面板
│
├── editor/
│   ├── EditorState.lua          # 状态定义 + 工具常量 + 坐标转换
│   ├── LevelEditorCore.lua      # 编辑器核心 (物件CRUD + 输入处理)
│   ├── LevelEditorUI.lua        # UI 树构建
│   ├── EditorPreview.lua        # 预览/仿真系统
│   ├── EditorRenderer.lua       # NanoVG 画布渲染
│   └── LayerEditor.lua          # 图层管理
│
└── ... (其余模块不变)
```

---

## 风险控制

| 风险 | 应对 |
|------|------|
| 循环依赖 (A require B, B require A) | 每阶段提取后立即检测: `grep -r "require.*TitleMenu" scripts/editor/` 必须为空 |
| local function 不可跨模块 | `GetNvgTexture` 等 local 函数随所属模块迁移 |
| 状态共享竞态 | EditorState 为单例模块，require 返回同一实例 |
| 转发层遗忘 | 每阶段用 grep 验证外部调用方不受影响 |

---

## 执行节奏

| 阶段 | 预估改动行数 | 风险等级 |
|------|-------------|---------|
| 一 (EditorState) | ~200 行移动 + ~564 处引用替换 | 中（全局替换多） |
| 二 (Preview) | ~1600 行移动 | 低（边界清晰） |
| 三 (Renderer) | ~350 行移动 | 低 |
| 四 (MenuFlow) | ~800 行移动 | 低（独立性最高） |
| 五 (EditorUI) | ~1400 行移动 | 中（回调依赖） |
| 六 (清理) | ~1500 行移动 | 中 |

建议每阶段结束后 commit 一次，便于回滚。
