# 对话框模块 UI 组件化重设计

> 目标：把对话框运行时表现从 raw NanoVG 改为 urhox-libs/UI 组件，确保显示在屏幕最上层，
> 保留全部已有功能。
>
> 决策：编辑器预览方案 A（保留 NanoVG 画布内预览）；点击关闭路线 A（box-none + 现有轮询 + 防双触发）。

---

## 1. 现状与根因

混合渲染架构：

| 层 | 渲染方式 | 触发点 |
|----|---------|--------|
| 游戏世界 | raw NanoVG 整帧 | `Renderer.HandleRender`（NanoVGRender 事件） |
| HUD/菜单/编辑器 | urhox-libs/UI 组件 | `UI.Init` + `UI.SetRoot`（渲染在游戏世界之上） |
| 对话框（旧） | raw NanoVG | `EditorPreview.DrawPreview` 末尾（`DialogRenderer.Draw`） |

根因：旧对话框画在游戏世界 NanoVG 流程内，被 UI 层 HUD 遮挡 → 不在最上层。
有利条件：`UI.Init` 已用 `DESIGN_RESOLUTION(1920,1080)`，与对话框偏移坐标系一致，迁移无需换算。

---

## 2. 模块分层（保持现有 OCP）

```
DialogConfig  (数据模型)          ← 不变
DialogManager (生命周期/互斥/阻塞)  ← 增加挂载/更新/卸载 View
DialogRenderer(NanoVG)            ← 运行时停用；仅保留给编辑器画布内预览(DrawFromNode)
DialogView   (UI 组件) ★新增      ← 运行时表现层
```

---

## 3. 关键技术映射

| 功能 | UI 实现 |
|------|---------|
| 图片组件（底图/立绘/整体） | `UI.Panel{ backgroundImage, backgroundFit="fill", width, height, opacity }` |
| 文本组件（名牌/文本框） | `UI.Label{ text, fontSize, fontColor, textStroke, textAlign="left", verticalAlign="middle" }` |
| 描边 | `Label.textStroke = { width, color }`（原生支持） |
| 层级置顶 | 全屏 overlay `UI.Panel{ position="fixed", zIndex=9000, pointerEvents="box-none" }`，AddChild 到 `UI.GetRoot()` |
| 文本动画 | 每帧 `Update` 手动驱动（与旧逻辑一致）：typewriter 逐字 `SetText`，fade_in/slide_up 调 `SetStyle{opacity,translateY}` |
| effects | 每帧 `EffectRegistry.Apply(comp.effects, t)` → `SetStyle{translateX,translateY,scale,rotate=math.deg(angle),opacity}` |
| 显隐 | `RemoveChild` + `Destroy` |

### 坐标转换（设计分辨率 1920×1080）

旧 NanoVG 锚点：图片以 `(960+offsetX, 1080+offsetY)` 为中心。UI 用左上角：

```
图片 panel: left = 960 + offsetX - drawW/2,  top = 1080 + offsetY - drawH/2
文本 label: left = 960 + offsetX,            top = 1080 + offsetY - boxH/2
            （textAlign=left + verticalAlign=middle，等价旧 LEFT+MIDDLE）
```

### 单位注意

- UI `rotate` 单位为**度**；`EffectRegistry.Apply` 的 angle 是**弧度** → `rotate = math.deg(angle)`。
- effects 字段默认未配置（Apply 返回 0/1，no-op），但实现保留以备扩展。

---

## 4. 编辑器预览（方案 A）

- 运行时（游戏中）对话框：走 `DialogView`（UI 组件，置顶）。
- 编辑器内预览：保留 `DialogRenderer.DrawFromNode`（NanoVG，画布内局部缩放预览不变）。
- 两套视图共享同一份 `DialogConfig` 数据，无重复逻辑。UI 组件无法嵌入画布局部缩放区域，故编辑器预览不迁移。

---

## 5. 点击关闭（路线 A + 防双触发）

旧逻辑用引擎底层轮询 `input:GetMouseButtonPress(MOUSEB_LEFT)`，左键兼作攻击键，靠 `IsBlocking()` 互斥。

overlay 用 `pointerEvents="box-none"` 让点击穿透，**保留现有轮询逻辑**。

防双触发：`HandleClick()` 内部 `Dismiss` 会立即把 `active=nil`，同帧 `IsBlocking()` 变 false，
导致"关闭对话的那一击同时触发攻击"。用本帧标志位根治：

```lua
local clickConsumed = false
if input:GetMouseButtonPress(MOUSEB_LEFT) and DialogManager.HandleClick() then
    clickConsumed = true
end
local attackPressed = input:GetKeyPress(KEY_J)
    or (input:GetMouseButtonPress(MOUSEB_LEFT) and not DialogManager.IsBlocking() and not clickConsumed)
```

---

## 6. 第八节 · 实装清单（含输入细节）

| 文件 | 改动 |
|------|------|
| `dialog/DialogView.lua` | **新增**：`Show(config)` 构建 overlay + 控件引用；`Update(dt,config,elapsed)` 文本动画 + effects + 提示闪烁；`Hide()` 卸载销毁 |
| `dialog/DialogManager.lua` | `Show` 增 `DialogView.Show(config)`；`Update` 增 `DialogView.Update(dt, a.config, a.elapsed)`；`Dismiss`/`Reset` 增 `DialogView.Hide()` |
| `editor/EditorPreview.lua` | 删除运行时 `DialogRenderer.Draw`（2102）；点击处理加 `clickConsumed` 标志（849/856）防双触发 |
| `dialog/DialogConfig.lua` | 不变 |
| `dialog/DialogRenderer.lua` | 运行时停用；保留 `DrawFromNode` 供编辑器预览 |

### 风险点

1. **rotate 单位**：UI 用度，effects 用弧度，已用 `math.deg` 处理。
2. **点击双触发**：已用 `clickConsumed` 标志根治（第 5 节）。
3. **字体表现**：UI 注册 `XiangcuiDengcusong.ttf`（family="sans"），与旧 NanoVG 默认字体可能略有视觉差异，需预览确认。
4. **文本换行**：旧 NanoVG 单行不换行，UI Label 用 `whiteSpace="nowrap"` 保持一致；若需换行另行调整。
5. **图片原始尺寸**：`ImageCache.GetSize` 依赖渲染期上下文，构建期不可靠 → 图片组件一律用显式宽高（默认值均有）。

---

*状态：实装中*
