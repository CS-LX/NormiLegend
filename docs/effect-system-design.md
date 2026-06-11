# 物件动态效果系统设计方案

> **设计原则**: OCP（对修改关闭，对扩展开放）
> **日期**: 2026-06-11

---

## 架构总览

```
┌────────────────────────────────────────────────────────────┐
│  现有物件数据 (obj)                                         │
│  { type, x, y, w, h, texLayers, color, ... }               │
│                                     ▼ 新增字段              │
│  effects = {                                               │
│    { id = "float",   params = {amp=0.3, speed=2.0} },      │
│    { id = "pulse",   params = {min=0.8, max=1.1, speed=3} },│
│    { id = "rotate",  params = {speed=45} },                │
│  }                                                         │
└────────────────────────────────────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────────┐
│  EffectRegistry (不修改，只注册扩展)        │
│                                          │
│  Registry["float"]  = { apply(obj, t) }  │  ← 每个效果是独立模块
│  Registry["pulse"]  = { apply(obj, t) }  │
│  Registry["rotate"] = { apply(obj, t) }  │
│  Registry["shake"]  = { apply(obj, t) }  │  ← 新增效果只需注册
│  ...                                     │
└──────────────────────────────────────────┘
```

---

## 文件结构

```
scripts/
├── effects/
│   ├── EffectRegistry.lua   # 核心注册中心（稳定，不修改）
│   └── builtin.lua          # 内置效果集（可追加）
├── editor/
│   └── LevelEditorUI.lua    # 编辑器 UI（仅一次性接入）
└── Renderer.lua             # 渲染层（仅一次性接入）
```

---

## 核心模块设计

### 1. EffectRegistry.lua — 注册中心

**职责**: 维护效果注册表，提供统一的 Apply 接口

**接口**:
- `Register(id, def)` — 注册一个效果类型
- `GetAll()` — 获取所有已注册效果（编辑器 UI 用）
- `Get(id)` — 获取单个效果定义
- `Apply(effects, t)` — 对物件应用所有效果，返回渲染变换参数

**返回值约定**:
```lua
-- Apply 返回 5 个值，叠加到物件的渲染参数上
dx,     -- X 方向偏移（米），累加
dy,     -- Y 方向偏移（米），累加
scale,  -- 缩放因子，连乘
angle,  -- 旋转角度（度），累加
alpha   -- 透明度因子，连乘
```

### 2. 效果定义结构

每个效果注册时提供:

```lua
{
    name = "浮动",                    -- 显示名称（编辑器用）
    params_schema = {                 -- 参数 schema（编辑器自动生成 UI）
        { key = "amp",   label = "振幅(米)", default = 0.3, min = 0.05, max = 2.0 },
        { key = "speed", label = "速度",     default = 2.0, min = 0.1,  max = 10.0 },
    },
    apply = function(t, params)       -- 纯函数，无副作用
        return dx, dy, scale, angle, alpha
    end,
}
```

### 3. 物件数据扩展

```lua
-- 物件数据结构（已有字段不改，仅追加 effects）
obj = {
    type = "platform",
    x = 5, y = 2, w = 3, h = 0.6,
    texLayers = {...},
    color = {255, 255, 255, 255},
    -- ▼ 新增 ▼
    effects = {
        { id = "float", params = { amp = 0.3, speed = 2.0 } },
        { id = "pulse", params = { min = 0.9, max = 1.1, speed = 3.0 } },
    },
}
```

---

## 内置效果清单

| ID | 名称 | 参数 | 效果描述 |
|----|------|------|---------|
| `float` | 浮动 | amp, speed | 上下正弦悬浮 |
| `pulse` | 脉冲 | min, max, speed | 周期性缩放 |
| `rotate` | 旋转 | speed | 匀速旋转 |
| `blink` | 闪烁 | min, speed | 透明度周期变化 |
| `shake` | 摇晃 | amp, speed | 水平抖动 |

---

## 渲染层接入

在渲染物件时插入效果计算:

```lua
local EffectRegistry = require("effects.EffectRegistry")

-- 渲染每个物件：
local dx, dy, scale, angle, alpha = EffectRegistry.Apply(obj.effects, gameTime)
local finalX = obj.x + dx
local finalY = obj.y + dy
-- 用 nvgSave/nvgTranslate/nvgRotate/nvgScale 实现变换
```

---

## 编辑器 UI 接入

在物件属性面板中追加效果配置区:

```
┌─────────────────────────────────────────┐
│ ✨ 动态效果                    [+ 添加] │
│  ┌───────────────────────────────────┐  │
│  │ 🔹 浮动               [×删除]    │  │
│  │    振幅: [0.3]  速度: [2.0]      │  │
│  ├───────────────────────────────────┤  │
│  │ 🔹 脉冲               [×删除]    │  │
│  │    最小: [0.9]  最大: [1.1]      │  │
│  │    速度: [3.0]                   │  │
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

编辑器从 `EffectRegistry.GetAll()` 动态获取可用效果列表和参数 schema，自动生成 UI — **新增效果时编辑器 UI 无需改动**。

---

## OCP 合规性分析

| 场景 | 是否需改已有代码 | 操作 |
|------|:---:|------|
| **新增一种效果** | 否 | 新建 .lua 文件，调用 `Registry.Register(...)` |
| **给物件添加效果** | 否 | 编辑器 UI 自动从 Registry 读取列表 |
| **调整效果参数** | 否 | 编辑器 UI 根据 params_schema 自动生成输入控件 |
| **组合多种效果** | 否 | obj.effects 数组可叠加任意数量效果 |
| **删除某种效果** | 否 | 删除对应的注册文件即可 |

**修改关闭**: EffectRegistry.lua（核心引擎）、渲染接入点、编辑器 UI 模板
**扩展开放**: 任何 `Register()` 调用都是扩展点

---

## 扩展示例：自定义效果

```lua
-- scripts/effects/waterwave.lua（新文件，不改任何已有代码）
local Registry = require("effects.EffectRegistry")

Registry.Register("waterwave", {
    name = "水波纹",
    params_schema = {
        { key = "amp",   label = "波幅",     default = 0.2 },
        { key = "freqX", label = "横波频率", default = 3.0 },
        { key = "freqY", label = "纵波频率", default = 2.0 },
    },
    apply = function(t, p)
        local dx = math.sin(t * p.freqX) * p.amp * 0.5
        local dy = math.cos(t * p.freqY) * p.amp
        return dx, dy, nil, nil, nil
    end,
})
```

---

*最后更新: 2026-06-11*
