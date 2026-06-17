-- ============================================================================
-- dialog/DialogEditor.lua - 对话框可视化编辑器
-- 内嵌于节点编辑器，弹出面板式 WYSIWYG 编辑
-- ============================================================================

local UI = require("urhox-libs/UI")
local EditorState = require("editor.EditorState")

local M = {}

-- 编辑器状态
M.active = false
M.tree = nil
M.nodeId = nil
M.onClose = nil
M.selectedComp = "background"
M._snapshot = nil
M._uiRoot = nil
M._dragging = false
M._dragStartMX = 0
M._dragStartMY = 0
M._dragStartOffX = 0
M._dragStartOffY = 0

-- 组件定义
local COMPONENTS = {
    { key = "background", label = "底图",   prefix = "dlgBg",       hasTex = true,  hasText = false, hasSize = true,  texCat = "dlg_bg" },
    { key = "portrait",   label = "立绘",   prefix = "dlgPortrait", hasTex = true,  hasText = false, hasSize = true,  texCat = "dlg_portrait" },
    { key = "nameplate",  label = "名牌",   prefix = "dlgName",     hasTex = false, hasText = true,  hasSize = false, texCat = "dlg_bg", textKey = "dlgSpeaker", fontPrefix = "dlgName" },
    { key = "textbox",    label = "文本",   prefix = "dlgText",     hasTex = false, hasText = true,  hasSize = false, texCat = "dlg_bg", textKey = "dialogText", fontPrefix = "dlgText", hasAnim = true },
    { key = "whole",      label = "整体",   prefix = "dlgWhole",    hasTex = true,  hasText = false, hasSize = true,  texCat = "dlg_whole" },
}

-- 文本动画类型
local TEXT_ANIMS = {
    { id = "none",       label = "无" },
    { id = "typewriter", label = "打字机" },
    { id = "fade_in",    label = "浮现" },
    { id = "slide_up",   label = "上滑" },
}

-- 颜色预设
local COLOR_PRESETS = {
    {255,255,255,255}, {0,0,0,255}, {255,220,100,255},
    {100,200,255,255}, {255,100,100,255}, {100,255,150,255},
    {200,150,255,255}, {255,180,80,255}, {180,180,180,255},
    {50,50,50,255}, {255,200,200,255}, {200,255,200,255},
}

--- 深拷贝节点数据（用于取消回滚）
local function deepCopyNode(node)
    local copy = {}
    for k, v in pairs(node) do
        if type(v) == "table" then
            local t = {}
            for i, vv in ipairs(v) do t[i] = vv end
            for kk, vv in pairs(v) do if type(kk) ~= "number" then t[kk] = vv end end
            copy[k] = t
        else
            copy[k] = v
        end
    end
    return copy
end

--- 打开对话编辑器
function M.Open(tree, nodeId, onClose)
    M.active = true
    M.tree = tree
    M.nodeId = nodeId
    M.onClose = onClose
    M.selectedComp = "background"
    -- 快照用于取消
    M._snapshot = deepCopyNode(tree.nodes[nodeId])
    M._buildUI()
end

--- 关闭编辑器
function M.Close(confirm)
    if not confirm and M._snapshot and M.tree and M.nodeId then
        -- 取消：回滚
        M.tree.nodes[M.nodeId] = M._snapshot
    end
    local cb = M.onClose
    M.active = false
    M._snapshot = nil
    M.tree = nil
    M.nodeId = nil
    M.onClose = nil
    -- 移除 UI 覆盖层
    if M._uiRoot and M._uiParent then
        M._uiParent:RemoveChild(M._uiRoot)
    end
    M._uiRoot = nil
    M._uiParent = nil
    -- 回调放最后
    if cb then cb() end
end

--- 获取当前编辑节点
function M._getNode()
    if not M.tree or not M.nodeId then return nil end
    return M.tree.nodes[M.nodeId]
end

--- 获取当前选中组件定义
function M._getCompDef()
    for _, c in ipairs(COMPONENTS) do
        if c.key == M.selectedComp then return c end
    end
    return COMPONENTS[1]
end

--- 构建/重建 UI
function M._buildUI()
    local node = M._getNode()
    if not node then M.Close(false); return end

    local dpr = graphics:GetDPR()
    local screenW = graphics:GetWidth() / dpr
    local screenH = graphics:GetHeight() / dpr
    local sidebarW = 250

    -- 全屏面板（左侧透明以显示 NanoVG 预览，右侧不透明属性栏）
    M._uiRoot = UI.Panel {
        id = "dlg_editor_overlay",
        position = "absolute", left = 0, top = 0, width = screenW, height = screenH,
        backgroundColor = {0, 0, 0, 0},  -- 整体透明，NanoVG 预览可透出
        flexDirection = "row",
        children = {
            -- 左侧：透明占位（NanoVG 直接绘制在此下方）
            UI.Panel {
                id = "dlg_editor_preview_area",
                flexGrow = 1, height = "100%",
                backgroundColor = {0, 0, 0, 0},  -- 完全透明
            },
            -- 右侧：属性面板（不透明）
            UI.Panel {
                width = sidebarW, height = "100%",
                flexDirection = "column",
                backgroundColor = {22, 22, 38, 250},
                borderLeftWidth = 1, borderColor = {60, 70, 120, 150},
                children = {
                    -- 标题栏
                    M._buildHeader(sidebarW),
                    -- 组件Tab + 属性
                    M._buildCompTabs(sidebarW),
                    M._buildProperties(sidebarW, screenH - 32 - 34 - 40),
                    -- 底栏
                    M._buildFooter(sidebarW),
                },
            },
        },
    }

    local root = UI.GetRoot()
    if root then
        root:AddChild(M._uiRoot)
        M._uiParent = root
    end
end

--- 标题栏
function M._buildHeader(w)
    return UI.Panel {
        width = w, height = 32, flexDirection = "row", alignItems = "center",
        backgroundColor = {30, 35, 55, 255},
        paddingLeft = 12, paddingRight = 8, gap = 8,
        children = {
            UI.Label { text = "对话编辑器", fontSize = 13, fontColor = {200, 200, 255, 255}, flexGrow = 1 },
        },
    }
end

--- 底栏（确认/取消）
function M._buildFooter(w)
    return UI.Panel {
        width = w, height = 36, flexDirection = "row", alignItems = "center",
        justifyContent = "flex-end",
        backgroundColor = {30, 35, 55, 255},
        paddingRight = 12, gap = 8,
        children = {
            UI.Button {
                text = "取消", fontSize = 11, paddingHorizontal = 16, height = 26,
                backgroundColor = {80, 50, 50, 220}, borderRadius = 4,
                fontColor = {255, 180, 180, 255},
                onClick = function() M.Close(false) end,
            },
            UI.Button {
                text = "确认", fontSize = 11, paddingHorizontal = 16, height = 26,
                backgroundColor = {50, 100, 50, 220}, borderRadius = 4,
                fontColor = {180, 255, 180, 255},
                onClick = function() M.Close(true) end,
            },
        },
    }
end



--- 组件切换 Tab（两行三列）
function M._buildCompTabs(w)
    local tabs = {}
    for _, comp in ipairs(COMPONENTS) do
        local isActive = (M.selectedComp == comp.key)
        table.insert(tabs, UI.Button {
            text = comp.label, fontSize = 10,
            width = math.floor((w - 24) / 3), height = 24,
            backgroundColor = isActive and {60, 80, 150, 230} or {40, 40, 60, 180},
            borderRadius = 3,
            fontColor = isActive and {255, 240, 150, 255} or {160, 160, 180, 200},
            justifyContent = "center", alignItems = "center",
            onClick = function() M.selectedComp = comp.key; M._buildUI() end,
        })
    end
    return UI.Panel {
        width = w, flexDirection = "row", flexWrap = "wrap", alignItems = "center",
        gap = 3, paddingHorizontal = 6, paddingVertical = 4,
        backgroundColor = {25, 25, 40, 255},
        borderBottomWidth = 1, borderColor = {60, 60, 100, 100},
        children = tabs,
    }
end

--- 属性面板
function M._buildProperties(w, h)
    local node = M._getNode()
    if not node then return UI.Panel { width = w, height = h } end
    local comp = M._getCompDef()
    local prefix = comp.prefix
    local children = {}

    -- 贴图选择
    if comp.hasTex then
        local texKey = prefix .. "Texture"
        local currentPath = node[texKey] or ""
        local shortName = currentPath ~= "" and (currentPath:match("[^/]+$") or currentPath) or "（无）"
        table.insert(children, UI.Label { text = "贴图", fontSize = 9, fontColor = {120, 150, 200, 200}, marginTop = 4 })
        table.insert(children, M._makeTexSelector(texKey, comp.texCat, shortName))
        -- 宽高（底图和立绘支持，0=原始尺寸）
        if comp.hasSize then
            table.insert(children, M._makeNumRow("宽", prefix .. "Width", 10, "%.0f", 0, 2000))
            table.insert(children, M._makeNumRow("高", prefix .. "Height", 10, "%.0f", 0, 2000))
        end
        -- 偏移
        table.insert(children, M._makeNumRow("偏X", prefix .. "OffsetX", 1))
        table.insert(children, M._makeNumRow("偏Y", prefix .. "OffsetY", 1))
        -- 透明度
        table.insert(children, M._makeNumRow("透明", prefix .. "Opacity", 0.05, "%.2f", 0, 1))
    end

    -- 文本内容 + 样式（名牌/文本组件）
    if comp.hasText then
        table.insert(children, UI.Panel { width = "100%", height = 1, backgroundColor = {80,80,120,80}, marginTop = 6, marginBottom = 4 })
        table.insert(children, UI.Label { text = "文本内容", fontSize = 9, fontColor = {120, 200, 150, 200} })
        -- 文本输入
        local textKey = comp.textKey
        table.insert(children, UI.TextField {
            value = node[textKey] or "", fontSize = 11,
            width = "100%", height = 28, marginBottom = 4,
            backgroundColor = {35, 35, 55, 255}, fontColor = {220, 220, 255, 255},
            borderRadius = 3, paddingHorizontal = 6,
            placeholder = "输入文本...",
            onSubmit = function(self, txt) node[textKey] = txt; M._buildUI() end,
            onBlur = function(self) node[textKey] = self:GetValue() or ""; M._buildUI() end,
        })
        -- 偏移
        table.insert(children, M._makeNumRow("偏X", prefix .. "OffsetX", 1))
        table.insert(children, M._makeNumRow("偏Y", prefix .. "OffsetY", 1))
        -- 字号
        local fp = comp.fontPrefix
        table.insert(children, M._makeNumRow("字号", fp .. "FontSize", 1, "%.0f", 8, 48))
        -- 文字颜色（预设 + 色号输入）
        table.insert(children, UI.Label { text = "文字颜色", fontSize = 9, fontColor = {120, 150, 200, 200}, marginTop = 2 })
        table.insert(children, M._makeColorPicker(fp .. "FontColor"))
        -- 描边宽
        table.insert(children, M._makeNumRow("描边宽", fp .. "StrokeW", 0.5, "%.1f", 0, 8))
        -- 描边颜色
        table.insert(children, UI.Label { text = "描边颜色", fontSize = 9, fontColor = {120, 150, 200, 200}, marginTop = 2 })
        table.insert(children, M._makeColorPicker(fp .. "StrokeColor"))
        -- 文本动画效果
        if comp.hasAnim then
            table.insert(children, UI.Panel { width = "100%", height = 1, backgroundColor = {80,80,120,80}, marginTop = 6, marginBottom = 4 })
            table.insert(children, UI.Label { text = "文本动画", fontSize = 9, fontColor = {120, 180, 200, 200} })
            table.insert(children, M._makeAnimSelector("dlgTextAnim"))
            table.insert(children, M._makeNumRow("动画速度", "dlgTextAnimSpeed", 0.5, "%.1f", 0.5, 10))
        end
    end

    return UI.Panel {
        width = w, flexGrow = 1, flexDirection = "column",
        paddingHorizontal = 8, paddingVertical = 4,
        overflow = "scroll",
        children = children,
    }
end

--- 数值调整行（竖向：标签在上，控件在下）
function M._makeNumRow(label, key, step, fmt, minVal, maxVal)
    step = step or 1
    fmt = fmt or "%.1f"
    local node = M._getNode()
    local val = node[key] or 0
    return UI.Panel {
        flexDirection = "column", width = "100%", marginBottom = 4,
        children = {
            UI.Label { text = label, fontSize = 9, fontColor = {140, 140, 170, 220}, marginBottom = 2 },
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4, width = "100%",
                children = {
                    UI.Button {
                        text = "-", fontSize = 11, width = 28, height = 24,
                        backgroundColor = {50, 45, 75, 220}, borderRadius = 3,
                        fontColor = {200, 200, 255, 255}, justifyContent = "center", alignItems = "center",
                        onClick = function()
                            local v = (node[key] or 0) - step
                            if minVal then v = math.max(minVal, v) end
                            node[key] = v; M._buildUI()
                        end,
                    },
                    UI.TextField {
                        value = string.format(fmt, val), fontSize = 10, flexGrow = 1, height = 24,
                        backgroundColor = {30, 28, 50, 255}, fontColor = {220, 220, 255, 255},
                        borderRadius = 3, paddingHorizontal = 6,
                        onSubmit = function(self, txt)
                            local n = tonumber(txt)
                            if n then
                                if minVal then n = math.max(minVal, n) end
                                if maxVal then n = math.min(maxVal, n) end
                                node[key] = n; M._buildUI()
                            end
                        end,
                    },
                    UI.Button {
                        text = "+", fontSize = 11, width = 28, height = 24,
                        backgroundColor = {50, 45, 75, 220}, borderRadius = 3,
                        fontColor = {200, 200, 255, 255}, justifyContent = "center", alignItems = "center",
                        onClick = function()
                            local v = (node[key] or 0) + step
                            if maxVal then v = math.min(maxVal, v) end
                            node[key] = v; M._buildUI()
                        end,
                    },
                },
            },
        },
    }
end

--- 贴图选择器（从素材库拉取）
function M._makeTexSelector(key, catFilter, currentName)
    local node = M._getNode()
    local texList = EditorState.state.customTextures or {}
    local filtered = {}
    for _, ta in ipairs(texList) do
        if ta.cat == catFilter then table.insert(filtered, ta) end
    end

    local optChildren = {}
    -- "无" 选项
    local noneActive = (node[key] or "") == ""
    table.insert(optChildren, UI.Button {
        text = "（无）", fontSize = 9, height = 20, width = "100%",
        backgroundColor = noneActive and {60, 80, 140, 200} or {40, 40, 55, 180},
        borderRadius = 2, fontColor = noneActive and {255, 240, 150, 255} or {180, 180, 200, 200},
        paddingLeft = 6,
        onClick = function() node[key] = ""; M._buildUI() end,
    })
    for _, ta in ipairs(filtered) do
        local isActive = (ta.path == (node[key] or ""))
        table.insert(optChildren, UI.Button {
            text = ta.name or ta.path:match("[^/]+$") or ta.path,
            fontSize = 9, height = 20, width = "100%",
            backgroundColor = isActive and {60, 80, 140, 200} or {40, 40, 55, 180},
            borderRadius = 2, fontColor = isActive and {255, 240, 150, 255} or {180, 200, 210, 200},
            paddingLeft = 6,
            onClick = function() node[key] = ta.path; M._buildUI() end,
        })
    end

    return UI.Panel {
        width = "100%", flexDirection = "column", gap = 1,
        maxHeight = 90, overflow = "scroll",
        backgroundColor = {30, 30, 45, 200}, borderRadius = 3,
        paddingVertical = 2, paddingHorizontal = 2, marginBottom = 4,
        children = optChildren,
    }
end

--- 颜色选择器（预设色块 + 色号输入）
function M._makeColorPicker(key)
    local node = M._getNode()
    local color = node[key]
    if type(color) ~= "table" then color = {255, 255, 255, 255}; node[key] = color end

    -- 预设色块
    local presetBtns = {}
    for _, c in ipairs(COLOR_PRESETS) do
        local isActive = (c[1] == color[1] and c[2] == color[2] and c[3] == color[3])
        table.insert(presetBtns, UI.Button {
            text = "", width = 18, height = 18,
            backgroundColor = {c[1], c[2], c[3], c[4] or 255},
            borderRadius = 3,
            borderWidth = isActive and 2 or 0,
            borderColor = {255, 255, 255, 200},
            onClick = function()
                node[key] = {c[1], c[2], c[3], c[4] or 255}
                M._buildUI()
            end,
        })
    end

    -- 色号输入（#RRGGBB 格式）
    local hexStr = string.format("#%02X%02X%02X", color[1], color[2], color[3])

    return UI.Panel {
        flexDirection = "column", gap = 3, width = "100%", marginBottom = 4,
        children = {
            -- 预设色块行
            UI.Panel {
                flexDirection = "row", flexWrap = "wrap", gap = 3, width = "100%",
                children = presetBtns,
            },
            -- 色号输入行
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4, width = "100%",
                children = {
                    -- 当前颜色预览
                    UI.Panel {
                        width = 22, height = 22,
                        backgroundColor = {color[1], color[2], color[3], color[4] or 255},
                        borderRadius = 3, borderWidth = 1, borderColor = {100, 100, 140, 200},
                    },
                    -- 色号输入框
                    UI.TextField {
                        value = hexStr, fontSize = 10, flexGrow = 1, height = 22,
                        backgroundColor = {30, 28, 50, 255}, fontColor = {220, 220, 255, 255},
                        borderRadius = 3, paddingHorizontal = 4,
                        placeholder = "#FFFFFF",
                        onSubmit = function(self, txt)
                            local hex = txt:match("#?(%x%x%x%x%x%x)")
                            if hex then
                                local r = tonumber(hex:sub(1,2), 16)
                                local g = tonumber(hex:sub(3,4), 16)
                                local b = tonumber(hex:sub(5,6), 16)
                                node[key] = {r, g, b, color[4] or 255}
                                M._buildUI()
                            end
                        end,
                    },
                },
            },
        },
    }
end

--- 文本动画选择器
function M._makeAnimSelector(key)
    local node = M._getNode()
    local currentAnim = node[key] or "none"
    local animBtns = {}
    for _, anim in ipairs(TEXT_ANIMS) do
        local isActive = (anim.id == currentAnim)
        table.insert(animBtns, UI.Button {
            text = anim.label, fontSize = 9,
            paddingHorizontal = 8, height = 22,
            backgroundColor = isActive and {60, 100, 140, 220} or {40, 40, 55, 180},
            borderRadius = 3,
            fontColor = isActive and {255, 240, 150, 255} or {180, 180, 200, 200},
            onClick = function() node[key] = anim.id; M._buildUI() end,
        })
    end
    return UI.Panel {
        flexDirection = "row", flexWrap = "wrap", gap = 3, width = "100%", marginBottom = 4,
        children = animBtns,
    }
end

--- 处理输入（鼠标拖动图层位置）
function M.HandleInput()
    if not M.active then return end
    local node = M._getNode()
    if not node then return end
    local comp = M._getCompDef()
    local prefix = comp.prefix

    local dpr = graphics:GetDPR()
    local mx = input.mousePosition.x / dpr
    local my = input.mousePosition.y / dpr
    -- 预览区范围（左侧，不含右侧栏）
    local screenW = graphics:GetWidth() / dpr
    local sidebarW = 250
    local inPreview = mx < (screenW - sidebarW)

    if input:GetMouseButtonPress(MOUSEB_LEFT) and inPreview then
        -- 开始拖动当前选中组件
        M._dragging = true
        M._dragStartMX = mx
        M._dragStartMY = my
        M._dragStartOffX = node[prefix .. "OffsetX"] or 0
        M._dragStartOffY = node[prefix .. "OffsetY"] or 0
    end

    if M._dragging then
        if input:GetMouseButtonDown(MOUSEB_LEFT) then
            -- 计算拖动偏移（屏幕像素转换为模拟屏幕坐标）
            local previewW = (screenW - sidebarW) * dpr
            local previewH = graphics:GetHeight()
            local simW, simH = 1920, 1080
            local scale = math.min(previewW * 0.92 / simW, previewH * 0.88 / simH)
            local dx = (mx - M._dragStartMX) * dpr / scale
            local dy = (my - M._dragStartMY) * dpr / scale
            node[prefix .. "OffsetX"] = M._dragStartOffX + dx
            node[prefix .. "OffsetY"] = M._dragStartOffY + dy
        else
            -- 松开鼠标结束拖动
            M._dragging = false
            M._buildUI()  -- 更新属性面板显示
        end
    end
end

--- NanoVG 实时预览绘制（由 NodeCanvas 的 NanoVGRender 调用）
---@param vg userdata
---@param physW number 物理像素宽（NanoVG坐标系）
---@param physH number 物理像素高（NanoVG坐标系）
function M.DrawPreview(vg, physW, physH)
    if not M.active then return end
    local node = M._getNode()
    if not node then return end

    -- 全屏布局：左侧预览区 = 物理宽 - 右侧栏宽度(按DPR缩放)
    local dpr = graphics:GetDPR()
    local sidebarW = 250 * dpr
    local previewW = physW - sidebarW
    local previewH = physH

    if previewW <= 0 or previewH <= 0 then return end

    -- 模拟 16:9 游戏屏幕（与实际游戏分辨率一致）
    local simW, simH = 1920, 1080
    local scale = math.min(previewW * 0.92 / simW, previewH * 0.88 / simH)
    local drawW, drawH = simW * scale, simH * scale
    local ox = (previewW - drawW) / 2
    local oy = (previewH - drawH) / 2  -- 垂直居中

    nvgSave(vg)

    -- 预览区全覆盖背景（NanoVG 层，确保可见）
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, previewW, previewH)
    nvgFillColor(vg, nvgRGBA(18, 20, 32, 255))
    nvgFill(vg)

    -- 模拟游戏画面框
    nvgBeginPath(vg)
    nvgRect(vg, ox, oy, drawW, drawH)
    nvgFillColor(vg, nvgRGBA(30, 45, 65, 255))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(50, 70, 110, 200))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 绘制对话框组件（不裁切，对话框可超出模拟画面框）
    nvgTranslate(vg, ox, oy)
    nvgScale(vg, scale, scale)

    local DialogRenderer = require("dialog.DialogRenderer")
    DialogRenderer.DrawFromNode(vg, simW, simH, node)

    nvgRestore(vg)
end

return M
