-- ============================================================================
-- NodeCanvas.lua - Blender/Unity 风格可视化节点编辑器
-- 使用 NanoVG 渲染, 支持拖拽节点、连接端口、平移缩放
-- Inspector 面板使用 UI 组件（支持 TextBox 编辑）
-- ============================================================================

local S = require("GameState")
local SN = require("StrategyNode")

local M = {}

-- ============================================================================
-- 状态
-- ============================================================================

local state = {
    active = false,
    tree = nil,
    fieldName = "",
    obj = nil,
    onClose = nil,

    -- 视口
    panX = 0,
    panY = 0,
    zoom = 1.0,

    -- 交互
    draggingNode = nil,
    dragOffsetX = 0,
    dragOffsetY = 0,
    panning = false,
    panStartX = 0,
    panStartY = 0,
    panStartPanX = 0,
    panStartPanY = 0,

    -- 连线
    connecting = false,
    connSrcNodeId = nil,
    connSrcPortIdx = nil,
    connSrcIsOutput = true,
    connMouseX = 0,
    connMouseY = 0,

    -- 选中
    selectedNode = nil,

    -- 右键菜单
    contextMenu = false,
    contextX = 0,
    contextY = 0,
    menuWorldX = 0,
    menuWorldY = 0,
    menuSelectedCat = 1,  -- 当前选中的分类tab索引

    -- Inspector (UI 组件)
    inspectorRoot = nil,
    inspectorNodeId = nil,  -- 当前 inspector 正在展示的节点 id

    -- Dropdown (节点类型快捷创建)
    dropdownVisible = false,
}

-- ============================================================================
-- 视觉常量
-- ============================================================================

local NODE_W         = 170
local NODE_HEADER_H  = 30
local NODE_PORT_H    = 24
local NODE_PADDING   = 10
local PORT_RADIUS    = 5.5
local GRID_SIZE      = 50
local INSPECTOR_W    = 280

-- 颜色调色板
local COL_BG         = {22, 22, 28, 252}
local COL_GRID       = {50, 50, 60}
local COL_NODE_BODY  = {38, 38, 46, 245}
local COL_NODE_BORDER= {60, 60, 70, 200}
local COL_SEL_BORDER = {255, 200, 60, 240}
local COL_SHADOW     = {0, 0, 0, 60}
local COL_TOOLBAR    = {30, 30, 38, 245}
local COL_MENU_BG    = {42, 42, 52, 248}
local COL_MENU_HOVER = {70, 70, 95, 200}
local COL_TEXT       = {220, 220, 230, 240}
local COL_TEXT_DIM   = {160, 160, 175, 200}
local COL_TEXT_HINT  = {120, 120, 140, 160}

-- ============================================================================
-- 公共接口
-- ============================================================================

function M.IsActive()
    return state.active
end

function M.JustClosed()
    return state.justClosed == true
end

function M.ClearJustClosed()
    state.justClosed = false
end

function M.Open(obj, fieldName, onClose)
    state.active = true
    state.obj = obj
    state.fieldName = fieldName
    state.onClose = onClose

    if obj[fieldName] and obj[fieldName].rootId then
        state.tree = obj[fieldName]
    else
        state.tree = SN.CreateTree()
        obj[fieldName] = state.tree
    end

    local evNode = state.tree.nodes[state.tree.rootId]
    if evNode then
        state.panX = -evNode.x + 350
        state.panY = -evNode.y + 250
    end

    state.selectedNode = nil
    state.contextMenu = false
    state.connecting = false
    state.dropdownVisible = false

    M._setEditorUIVisible(false)
    M._destroyInspector()
end

function M.Close()
    M._destroyInspector()
    M._setEditorUIVisible(true)
    if state.onClose then state.onClose() end
    state.active = false
    state.tree = nil
    state.obj = nil
    state.contextMenu = false
    state.connecting = false
    state.dropdownVisible = false
end

function M._setEditorUIVisible(visible)
    local UI = require("urhox-libs/UI")
    if not visible then
        -- 保存当前编辑器 UI root 并替换为节点画布专用 root（空透明容器）
        state.prevUIRoot = UI.GetRoot()
        state.canvasUIRoot = UI.Panel {
            width = "100%", height = "100%",
            pointerEvents = "box-none",
        }
        UI.SetRoot(state.canvasUIRoot, false)
    else
        -- 恢复编辑器 UI root
        if state.prevUIRoot then
            UI.SetRoot(state.prevUIRoot, false)
        end
        state.prevUIRoot = nil
        state.canvasUIRoot = nil
    end
end

-- ============================================================================
-- Inspector UI 组件（实际可编辑面板）
-- ============================================================================

function M._destroyInspector()
    if state.inspectorRoot then
        state.inspectorRoot:Destroy()
        state.inspectorRoot = nil
    end
    state.inspectorNodeId = nil
end

function M._buildInspector(nodeId)
    -- 如果已经在展示该节点则不重建
    if state.inspectorNodeId == nodeId and state.inspectorRoot then return end
    M._destroyInspector()

    local node = state.tree and state.tree.nodes[nodeId]
    if not node then return end

    local UI = require("urhox-libs/UI")
    local meta = SN.NODE_TYPES[node.type] or { label = "?", color = {128,128,128}, desc = "" }
    local fields = SN.INSPECTOR_FIELDS[node.type]

    local physW = graphics:GetWidth()
    local dpr = graphics:GetDPR()
    local logW = physW / dpr

    local children = {}

    -- 标题行
    table.insert(children, UI.Label {
        text = (meta.icon or "") .. " " .. meta.label,
        fontSize = 14, fontColor = {meta.color[1], meta.color[2], meta.color[3], 255},
        marginBottom = 2,
    })
    table.insert(children, UI.Label {
        text = meta.desc or "", fontSize = 10, fontColor = {140, 140, 160, 200}, marginBottom = 8,
    })

    -- 分割线
    table.insert(children, UI.Panel { width = "100%", height = 1, backgroundColor = {80, 80, 100, 100}, marginBottom = 8 })

    if not fields or #fields == 0 then
        table.insert(children, UI.Label { text = "该节点无可编辑属性", fontSize = 11, fontColor = {120,120,140,180} })
    else
        for _, field in ipairs(fields) do
            -- showWhen 条件过滤：字段仅在节点某个属性匹配时显示
            if field.showWhen then
                local visible = true
                for condKey, condVal in pairs(field.showWhen) do
                    if node[condKey] ~= condVal then visible = false; break end
                end
                if not visible then goto continueField end
            end
            -- hideWhen 条件过滤：字段在节点某个属性匹配时隐藏
            if field.hideWhen then
                for condKey, condVal in pairs(field.hideWhen) do
                    if node[condKey] == condVal then goto continueField end
                end
            end

            -- 字段标签
            table.insert(children, UI.Label {
                text = field.label, fontSize = 10, fontColor = {180, 180, 200, 220}, marginBottom = 2,
            })

            -- 字段编辑器
            local editor = M._createFieldEditor(node, field)
            if editor then
                table.insert(children, editor)
            end

            -- 间距
            table.insert(children, UI.Panel { width = "100%", height = 6 })
            ::continueField::
        end
    end

    -- 删除节点按钮（非 event）
    if node.type ~= "event" then
        table.insert(children, UI.Panel { width = "100%", height = 1, backgroundColor = {80, 50, 50, 100}, marginTop = 10, marginBottom = 6 })
        table.insert(children, UI.Button {
            text = "删除节点", fontSize = 11, width = "100%", height = 28,
            backgroundColor = {120, 40, 40, 220}, borderRadius = 4,
            fontColor = {255, 200, 200, 255}, justifyContent = "center", alignItems = "center",
            onClick = function()
                SN.RemoveNode(state.tree, nodeId)
                state.selectedNode = nil
                M._destroyInspector()
            end,
        })
    end

    -- 创建面板容器
    local panelWidth = INSPECTOR_W / dpr
    state.inspectorRoot = UI.Panel {
        position = "absolute",
        top = 40 / dpr,
        right = 0,
        width = panelWidth,
        height = "100%",
        backgroundColor = {32, 32, 40, 235},
        borderLeftWidth = 1,
        borderColor = {70, 70, 85, 200},
        paddingTop = 12,
        paddingBottom = 60,
        paddingLeft = 12,
        paddingRight = 12,
        flexDirection = "column",
        overflow = "scroll",
        children = children,
    }

    -- 挂载到节点画布专用 UI root
    local canvasRoot = state.canvasUIRoot
    if canvasRoot then
        canvasRoot:AddChild(state.inspectorRoot)
    end
    state.inspectorNodeId = nodeId
end

--- 创建单个字段的编辑器组件
function M._createFieldEditor(node, field)
    local UI = require("urhox-libs/UI")
    local nodeRef = node  -- 闭包引用

    if field.type == "float" or field.type == "int" then
        local currentVal = node[field.key]
        if currentVal == nil then currentVal = field.default or 0 end
        if field.type == "int" then currentVal = math.floor(currentVal + 0.5) end

        return UI.Panel {
            flexDirection = "row", alignItems = "center", width = "100%", gap = 4,
            children = {
                -- 减按钮
                UI.Button {
                    text = "−", fontSize = 14, width = 28, height = 28,
                    backgroundColor = {60, 60, 80, 220}, borderRadius = 4,
                    fontColor = {150, 200, 255, 255}, justifyContent = "center", alignItems = "center",
                    onClick = function()
                        local step = field.step or 1
                        local val = (nodeRef[field.key] or field.default or 0) - step
                        val = math.max(field.min or -9999, val)
                        if field.type == "int" then val = math.floor(val + 0.5) end
                        nodeRef[field.key] = val
                        -- 刷新 inspector
                        state.inspectorNodeId = nil
                        M._buildInspector(nodeRef.id)
                    end,
                },
                -- 文本输入框
                UI.TextField {
                    value = field.type == "int" and tostring(math.floor(currentVal + 0.5)) or string.format("%.1f", currentVal),
                    fontSize = 11, height = 28, flexGrow = 1,
                    backgroundColor = {45, 45, 60, 255}, fontColor = {220, 230, 255, 255},
                    borderRadius = 4, borderWidth = 1, borderColor = {80, 80, 100, 150},
                    paddingHorizontal = 6, textAlign = "center",
                    onSubmit = function(self, txt)
                        local val = tonumber(txt)
                        if val then
                            val = math.max(field.min or -9999, math.min(field.max or 9999, val))
                            if field.type == "int" then val = math.floor(val + 0.5) end
                            nodeRef[field.key] = val
                            state.inspectorNodeId = nil
                            M._buildInspector(nodeRef.id)
                        end
                    end,
                },
                -- 加按钮
                UI.Button {
                    text = "+", fontSize = 14, width = 28, height = 28,
                    backgroundColor = {60, 60, 80, 220}, borderRadius = 4,
                    fontColor = {150, 200, 255, 255}, justifyContent = "center", alignItems = "center",
                    onClick = function()
                        local step = field.step or 1
                        local val = (nodeRef[field.key] or field.default or 0) + step
                        val = math.min(field.max or 9999, val)
                        if field.type == "int" then val = math.floor(val + 0.5) end
                        nodeRef[field.key] = val
                        state.inspectorNodeId = nil
                        M._buildInspector(nodeRef.id)
                    end,
                },
            },
        }

    elseif field.type == "text" then
        local currentVal = node[field.key]
        if currentVal == nil then currentVal = field.default or "" end
        return UI.TextField {
            value = tostring(currentVal),
            fontSize = 11, height = 28, width = "100%",
            backgroundColor = {45, 45, 60, 255}, fontColor = {220, 220, 240, 255},
            borderRadius = 4, borderWidth = 1, borderColor = {80, 80, 100, 150},
            paddingHorizontal = 8,
            placeholder = field.label,
            onSubmit = function(self, txt)
                nodeRef[field.key] = txt or ""
            end,
        }

    elseif field.type == "select" then
        local options = field.options
        if type(options) == "string" then options = SN[options] end
        if not options then return nil end

        local currentVal = node[field.key]
        if currentVal == nil then currentVal = field.default end

        -- 构建选项列表
        local optChildren = {}
        for _, opt in ipairs(options) do
            local isActive = (opt.id == currentVal)
            table.insert(optChildren, UI.Button {
                text = opt.label,
                fontSize = 10, height = 24, width = "100%",
                backgroundColor = isActive and {80, 100, 160, 220} or {50, 50, 65, 180},
                borderRadius = 3,
                fontColor = isActive and {255, 240, 150, 255} or {200, 200, 210, 220},
                paddingLeft = 8, justifyContent = "center",
                onClick = function()
                    nodeRef[field.key] = opt.id
                    state.inspectorNodeId = nil
                    M._buildInspector(nodeRef.id)
                end,
            })
        end

        return UI.Panel {
            width = "100%", flexDirection = "column", gap = 2,
            maxHeight = 130, overflow = "scroll",
            children = optChildren,
        }

    elseif field.type == "bool" then
        local currentVal = node[field.key]
        if currentVal == nil then currentVal = field.default or false end
        return UI.Button {
            text = currentVal and "✓ 是" or "✗ 否",
            fontSize = 11, height = 28, width = "100%",
            backgroundColor = currentVal and {50, 100, 50, 220} or {80, 50, 50, 220},
            borderRadius = 4,
            fontColor = currentVal and {150, 255, 150, 255} or {255, 150, 150, 255},
            justifyContent = "center", alignItems = "center",
            onClick = function()
                nodeRef[field.key] = not nodeRef[field.key]
                state.inspectorNodeId = nil
                M._buildInspector(nodeRef.id)
            end,
        }

    elseif field.type == "obj_select" then
        -- 物件列表选择器：从当前关卡的物件列表中选择目标
        local EditorState = require("editor.EditorState")
        local edState = EditorState.state
        local chKey = edState.chapterIdx .. "_" .. edState.levelIdx
        local objects = edState.objects[chKey] or {}
        local currentIdx = node[field.key] or 0

        local optChildren = {}
        -- "无" 选项
        table.insert(optChildren, UI.Button {
            text = "（无）",
            fontSize = 10, height = 22, width = "100%",
            backgroundColor = (currentIdx == 0) and {80, 100, 160, 220} or {50, 50, 65, 180},
            borderRadius = 3,
            fontColor = (currentIdx == 0) and {255, 240, 150, 255} or {200, 200, 210, 220},
            paddingLeft = 6, justifyContent = "center",
            onClick = function()
                nodeRef[field.key] = 0
                state.inspectorNodeId = nil
                M._buildInspector(nodeRef.id)
            end,
        })
        -- 物件列表
        for i, obj in ipairs(objects) do
            local objLabel = string.format("%d. %s", i, obj.name or obj.type or "物件")
            local isActive = (i == currentIdx)
            table.insert(optChildren, UI.Button {
                text = objLabel,
                fontSize = 10, height = 22, width = "100%",
                backgroundColor = isActive and {80, 100, 160, 220} or {50, 50, 65, 180},
                borderRadius = 3,
                fontColor = isActive and {255, 240, 150, 255} or {180, 200, 210, 220},
                paddingLeft = 6, justifyContent = "center",
                onClick = function()
                    nodeRef[field.key] = i
                    state.inspectorNodeId = nil
                    M._buildInspector(nodeRef.id)
                end,
            })
        end

        return UI.Panel {
            width = "100%", flexDirection = "column", gap = 2,
            maxHeight = 150, overflow = "scroll",
            backgroundColor = {38, 38, 50, 200}, borderRadius = 4,
            paddingVertical = 4, paddingHorizontal = 2,
            children = optChildren,
        }

    elseif field.type == "path_editor" then
        -- 路径点编辑器：根据 pathType 动态显示不同的参数
        local points = node[field.key]
        if type(points) ~= "table" then points = {}; node[field.key] = points end
        local pathType = node.pathType or "linear"

        local pointChildren = {}

        -- 辅助：创建带标签的输入字段
        local function makeField(labelText, value, onApply, width)
            return UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 2, flexGrow = width and 0 or 1,
                width = width,
                children = {
                    UI.Label { text = labelText, fontSize = 9, fontColor = {140,170,200,200}, width = 18 },
                    UI.TextField {
                        value = string.format("%.1f", value or 0),
                        fontSize = 10, height = 22, flexGrow = 1,
                        backgroundColor = {45, 45, 60, 255}, fontColor = {200, 230, 255, 255},
                        borderRadius = 3, paddingHorizontal = 4, textAlign = "center",
                        onSubmit = function(self, txt)
                            local v = tonumber(txt)
                            if v then onApply(v) end
                        end,
                    },
                },
            }
        end

        -- Y-up 坐标提示（与游戏世界坐标一致：Y+ = 向上）
        local yUpHint = UI.Label { text = "绝对世界坐标 (Y+ = 向上)", fontSize = 9, fontColor = {120,180,140,180}, marginBottom = 4 }

        if pathType == "linear" then
            -- 直线：1个终点 {x, y} — 绝对世界坐标
            if #points == 0 then table.insert(points, { x = 10, y = 5 }) end
            local pt = points[1]
            table.insert(pointChildren, yUpHint)
            table.insert(pointChildren, UI.Label { text = "目标坐标", fontSize = 10, fontColor = {160,200,160,220}, marginBottom = 2 })
            table.insert(pointChildren, UI.Panel {
                flexDirection = "row", alignItems = "center", width = "100%", gap = 4,
                children = {
                    makeField("X", pt.x, function(v) pt.x = v end),
                    makeField("Y", pt.y, function(v) pt.y = v end),
                },
            })

        elseif pathType == "bezier" then
            -- 贝塞尔：1个点 {x, y, cx, cy} — 均为绝对世界坐标
            if #points == 0 then table.insert(points, { x = 10, y = 5, cx = 5, cy = 8 }) end
            local pt = points[1]
            if pt.cx == nil then pt.cx = (pt.x or 0) / 2 end
            if pt.cy == nil then pt.cy = (pt.y or 0) + 2 end
            table.insert(pointChildren, yUpHint)
            table.insert(pointChildren, UI.Label { text = "目标坐标", fontSize = 10, fontColor = {160,200,160,220}, marginBottom = 2 })
            table.insert(pointChildren, UI.Panel {
                flexDirection = "row", alignItems = "center", width = "100%", gap = 4,
                children = {
                    makeField("X", pt.x, function(v) pt.x = v end),
                    makeField("Y", pt.y, function(v) pt.y = v end),
                },
            })
            table.insert(pointChildren, UI.Label { text = "控制点坐标", fontSize = 10, fontColor = {200,180,140,220}, marginTop = 4, marginBottom = 2 })
            table.insert(pointChildren, UI.Panel {
                flexDirection = "row", alignItems = "center", width = "100%", gap = 4,
                children = {
                    makeField("cX", pt.cx, function(v) pt.cx = v end),
                    makeField("cY", pt.cy, function(v) pt.cy = v end),
                },
            })

        elseif pathType == "circle" then
            -- 圆形轨迹：1个点 {radius, startAngle, endAngle}
            if #points == 0 then table.insert(points, { radius = 2, startAngle = 0, endAngle = 360 }) end
            local pt = points[1]
            if pt.radius == nil then pt.radius = 2 end
            if pt.startAngle == nil then pt.startAngle = 0 end
            if pt.endAngle == nil then pt.endAngle = 360 end
            table.insert(pointChildren, UI.Label { text = "圆弧参数", fontSize = 10, fontColor = {160,200,160,220}, marginBottom = 2 })
            table.insert(pointChildren, UI.Panel {
                flexDirection = "row", alignItems = "center", width = "100%", gap = 4,
                children = {
                    makeField("R", pt.radius, function(v) pt.radius = math.max(0.1, v) end),
                },
            })
            table.insert(pointChildren, UI.Panel {
                flexDirection = "row", alignItems = "center", width = "100%", gap = 4, marginTop = 4,
                children = {
                    makeField("起", pt.startAngle, function(v) pt.startAngle = v end),
                    makeField("止", pt.endAngle, function(v) pt.endAngle = v end),
                },
            })
            table.insert(pointChildren, UI.Label { text = "角度(°) 0=右 逆时针", fontSize = 9, fontColor = {120,130,150,180}, marginTop = 2 })

        elseif pathType == "custom" then
            -- 自定义路径：多个途经点 {x, y} — 绝对世界坐标
            table.insert(pointChildren, UI.Label { text = "途经点(绝对坐标)", fontSize = 10, fontColor = {160,200,160,220}, marginBottom = 2 })
            table.insert(pointChildren, yUpHint)
            for i, pt in ipairs(points) do
                table.insert(pointChildren, UI.Panel {
                    flexDirection = "row", alignItems = "center", width = "100%", gap = 2, height = 26,
                    children = {
                        UI.Label { text = string.format("#%d", i), fontSize = 9, fontColor = {140,160,180,200}, width = 22 },
                        UI.TextField {
                            value = string.format("%.1f", pt.x or 0),
                            fontSize = 10, height = 22, flexGrow = 1,
                            backgroundColor = {45, 45, 60, 255}, fontColor = {200, 230, 255, 255},
                            borderRadius = 3, paddingHorizontal = 4, textAlign = "center",
                            onSubmit = function(self, txt)
                                local v = tonumber(txt)
                                if v then points[i].x = v end
                            end,
                        },
                        UI.TextField {
                            value = string.format("%.1f", pt.y or 0),
                            fontSize = 10, height = 22, flexGrow = 1,
                            backgroundColor = {45, 45, 60, 255}, fontColor = {200, 230, 255, 255},
                            borderRadius = 3, paddingHorizontal = 4, textAlign = "center",
                            onSubmit = function(self, txt)
                                local v = tonumber(txt)
                                if v then points[i].y = v end
                            end,
                        },
                        UI.Button {
                            text = "×", fontSize = 12, width = 22, height = 22,
                            backgroundColor = {100, 40, 40, 200}, borderRadius = 3,
                            fontColor = {255, 180, 180, 255}, justifyContent = "center", alignItems = "center",
                            onClick = function()
                                table.remove(points, i)
                                state.inspectorNodeId = nil
                                M._buildInspector(nodeRef.id)
                            end,
                        },
                    },
                })
            end
            -- 添加点按钮
            table.insert(pointChildren, UI.Button {
                text = "+ 添加路径点", fontSize = 10, height = 24, width = "100%",
                backgroundColor = {50, 80, 60, 220}, borderRadius = 3,
                fontColor = {150, 255, 180, 255}, justifyContent = "center", alignItems = "center",
                marginTop = 2,
                onClick = function()
                    local lastPt = points[#points]
                    local nx = lastPt and (lastPt.x + 2) or 10
                    local ny = lastPt and lastPt.y or 5
                    table.insert(points, { x = nx, y = ny })
                    state.inspectorNodeId = nil
                    M._buildInspector(nodeRef.id)
                end,
            })
        end

        return UI.Panel {
            width = "100%", flexDirection = "column", gap = 2,
            maxHeight = 200, overflow = "scroll",
            backgroundColor = {35, 38, 48, 200}, borderRadius = 4,
            paddingVertical = 4, paddingHorizontal = 4,
            children = pointChildren,
        }

    elseif field.type == "audio_select" then
        -- 音效文件选择器：显示已导入的音效列表
        local EditorState = require("editor.EditorState")
        local edState = EditorState.state
        local audioList = edState.importedAudio or {}
        local currentFile = node[field.key] or ""

        local optChildren = {}
        -- "无" 选项
        table.insert(optChildren, UI.Button {
            text = currentFile == "" and "▸ 未选择音效" or "▸ " .. currentFile,
            fontSize = 10, height = 24, width = "100%",
            backgroundColor = {45, 50, 65, 220}, borderRadius = 3,
            fontColor = currentFile == "" and {150, 150, 170, 200} or {180, 220, 255, 255},
            paddingLeft = 6, justifyContent = "center",
            onClick = function()
                -- 点击已选项时清空选择
                if currentFile ~= "" then
                    nodeRef[field.key] = ""
                    state.inspectorNodeId = nil
                    M._buildInspector(nodeRef.id)
                end
            end,
        })

        if #audioList > 0 then
            for i, audio in ipairs(audioList) do
                local audioName = audio.name or audio.path or ("音效" .. i)
                local isActive = (currentFile == (audio.path or audio.name or ""))
                table.insert(optChildren, UI.Button {
                    text = audioName,
                    fontSize = 10, height = 22, width = "100%",
                    backgroundColor = isActive and {60, 90, 140, 220} or {50, 50, 65, 180},
                    borderRadius = 3,
                    fontColor = isActive and {255, 240, 150, 255} or {180, 200, 220, 220},
                    paddingLeft = 8, justifyContent = "center",
                    onClick = function()
                        nodeRef[field.key] = audio.path or audio.name or ""
                        state.inspectorNodeId = nil
                        M._buildInspector(nodeRef.id)
                    end,
                })
            end
        else
            table.insert(optChildren, UI.Label {
                text = "暂无音效，请上传", fontSize = 9, fontColor = {120, 120, 140, 160},
                paddingLeft = 6, marginTop = 2,
            })
        end

        return UI.Panel {
            width = "100%", flexDirection = "column", gap = 2,
            maxHeight = 130, overflow = "scroll",
            backgroundColor = {38, 38, 50, 200}, borderRadius = 4,
            paddingVertical = 4, paddingHorizontal = 2,
            children = optChildren,
        }

    elseif field.type == "layer_opacity_list" then
        -- 图层透明度列表编辑器：根据目标物件的 texLayers 动态生成
        local EditorState = require("editor.EditorState")
        local edState = EditorState.state
        local chKey = edState.chapterIdx .. "_" .. edState.levelIdx
        local objects = edState.objects[chKey] or {}
        local targetIdx = node.targetObjIdx or 0
        local targetObj = objects[targetIdx]

        local layerTargets = node[field.key]
        if type(layerTargets) ~= "table" then layerTargets = {}; node[field.key] = layerTargets end

        local layerChildren = {}

        if not targetObj or not targetObj.texLayers or #targetObj.texLayers == 0 then
            table.insert(layerChildren, UI.Label {
                text = "目标物件无贴图图层", fontSize = 9, fontColor = {140, 120, 120, 180},
            })
        else
            for li, tl in ipairs(targetObj.texLayers) do
                local curVal = layerTargets[li]
                if curVal == nil then curVal = 1.0 end
                local layerName = tl.name or ("图层" .. li)
                -- 截短名称
                if #layerName > 8 then layerName = layerName:sub(1, 8) .. ".." end
                table.insert(layerChildren, UI.Panel {
                    flexDirection = "row", alignItems = "center", width = "100%", gap = 2,
                    children = {
                        UI.Label { text = li .. "." .. layerName, fontSize = 9, fontColor = {160, 180, 200, 200}, width = 60 },
                        UI.Button {
                            text = "−", fontSize = 12, width = 22, height = 22,
                            backgroundColor = {60, 60, 80, 220}, borderRadius = 3,
                            fontColor = {150, 200, 255, 255}, justifyContent = "center", alignItems = "center",
                            onClick = function()
                                local val = (layerTargets[li] or 1.0) - 0.1
                                layerTargets[li] = math.max(0, val)
                                state.inspectorNodeId = nil
                                M._buildInspector(nodeRef.id)
                            end,
                        },
                        UI.TextField {
                            value = string.format("%.2f", curVal),
                            fontSize = 10, height = 22, flexGrow = 1,
                            backgroundColor = {45, 45, 60, 255}, fontColor = {200, 230, 255, 255},
                            borderRadius = 3, paddingHorizontal = 3, textAlign = "center",
                            onSubmit = function(self, txt)
                                local v = tonumber(txt)
                                if v then
                                    layerTargets[li] = math.max(0, math.min(1, v))
                                    state.inspectorNodeId = nil
                                    M._buildInspector(nodeRef.id)
                                end
                            end,
                        },
                        UI.Button {
                            text = "+", fontSize = 12, width = 22, height = 22,
                            backgroundColor = {60, 60, 80, 220}, borderRadius = 3,
                            fontColor = {150, 200, 255, 255}, justifyContent = "center", alignItems = "center",
                            onClick = function()
                                local val = (layerTargets[li] or 1.0) + 0.1
                                layerTargets[li] = math.min(1, val)
                                state.inspectorNodeId = nil
                                M._buildInspector(nodeRef.id)
                            end,
                        },
                    },
                })
            end
        end

        return UI.Panel {
            width = "100%", flexDirection = "column", gap = 3,
            backgroundColor = {38, 38, 50, 200}, borderRadius = 4,
            paddingVertical = 4, paddingHorizontal = 4,
            children = layerChildren,
        }
    end

    return nil
end

-- ============================================================================
-- 坐标转换
-- ============================================================================

local function screenToWorld(sx, sy)
    return (sx - state.panX) / state.zoom, (sy - state.panY) / state.zoom
end

local function worldToScreen(wx, wy)
    return wx * state.zoom + state.panX, wy * state.zoom + state.panY
end

-- ============================================================================
-- 节点尺寸计算
-- ============================================================================

local function getNodeContentLines(node)
    if node.type == "value" or node.type == "string" or node.type == "param"
       or node.type == "compare" or node.type == "math" or node.type == "logic"
       or node.type == "concat" then
        return 1
    end
    if node.type == "spawn" or node.type == "play_fx" or node.type == "dialog"
       or node.type == "delay" or node.type == "repeat_n" or node.type == "win_level"
       or node.type == "set_var" or node.type == "damage" or node.type == "camera_zoom"
       or node.type == "read_item" or node.type == "modify_item"
       or node.type == "set_ability" or node.type == "destroy_self" then
        return 1
    end
    return 0
end

local function getNodeHeight(node)
    local inPorts = SN.GetInputPorts(node)
    local outPorts = SN.GetOutputPorts(node)
    local portCount = math.max(#inPorts, #outPorts)
    local extraLines = getNodeContentLines(node)
    return NODE_HEADER_H + math.max(portCount, 1) * NODE_PORT_H + extraLines * NODE_PORT_H + NODE_PADDING
end

-- ============================================================================
-- 端口位置计算 (世界坐标)
-- ============================================================================

local function getInputPortPos(node, portIdx)
    local x = node.x
    local y = node.y + NODE_HEADER_H + (portIdx - 0.5) * NODE_PORT_H
    return x, y
end

local function getOutputPortPos(node, portIdx)
    local y = node.y + NODE_HEADER_H + (portIdx - 0.5) * NODE_PORT_H
    local x = node.x + NODE_W
    return x, y
end

-- ============================================================================
-- 命中检测
-- ============================================================================

local function hitTestNode(wx, wy)
    for id, node in pairs(state.tree.nodes) do
        local nh = getNodeHeight(node)
        if wx >= node.x and wx <= node.x + NODE_W and wy >= node.y and wy <= node.y + nh then
            return id
        end
    end
    return nil
end

local function hitTestPort(wx, wy)
    local hitR = (PORT_RADIUS + 5)
    for id, node in pairs(state.tree.nodes) do
        local inPorts = SN.GetInputPorts(node)
        for pi = 1, #inPorts do
            local px, py = getInputPortPos(node, pi)
            local dx, dy = wx - px, wy - py
            if dx * dx + dy * dy <= hitR * hitR then
                return id, pi, false
            end
        end
        local outPorts = SN.GetOutputPorts(node)
        for pi = 1, #outPorts do
            local px, py = getOutputPortPos(node, pi)
            local dx, dy = wx - px, wy - py
            if dx * dx + dy * dy <= hitR * hitR then
                return id, pi, true
            end
        end
    end
    return nil
end

-- ============================================================================
-- 输入处理
-- ============================================================================

function M.HandleInput(dt)
    if not state.active then return end

    state.justClosed = false

    -- ESC 关闭
    if input:GetKeyPress(KEY_ESCAPE) then
        if state.contextMenu then
            state.contextMenu = false
        else
            state.justClosed = true
            M.Close()
        end
        return
    end

    local mx = input.mousePosition.x
    local my = input.mousePosition.y
    local wx, wy = screenToWorld(mx, my)

    -- Inspector 区域检测 (右侧 UI 面板)
    local physW = graphics:GetWidth()
    local inInspector = state.selectedNode and state.inspectorRoot and mx > (physW - INSPECTOR_W)

    -- 滚轮缩放
    local wheel = input.mouseMoveWheel
    if wheel ~= 0 and not inInspector then
        local oldZoom = state.zoom
        local factor = 1.0005
        local newZoom = state.zoom * (factor ^ wheel)
        state.zoom = math.max(0.2, math.min(4.0, newZoom))
        local ratio = state.zoom / oldZoom
        state.panX = mx - (mx - state.panX) * ratio
        state.panY = my - (my - state.panY) * ratio
    end

    -- Delete 删除选中节点（inspector 区域内或输入框聚焦时不触发）
    if input:GetKeyPress(KEY_DELETE) or input:GetKeyPress(KEY_BACKSPACE) then
        local focused = UI.GetFocus and UI.GetFocus()
        local isTextEditing = focused and focused.OnTextInput and focused.state and focused.state.focused
        if not isTextEditing and not inInspector then
            if state.selectedNode and state.tree.nodes[state.selectedNode] then
                local node = state.tree.nodes[state.selectedNode]
                if node.type ~= "event" then
                    SN.RemoveNode(state.tree, state.selectedNode)
                    state.selectedNode = nil
                    M._destroyInspector()
                end
            end
        end
    end

    -- 右键菜单
    if input:GetMouseButtonPress(MOUSEB_RIGHT) then
        if state.connecting then
            state.connecting = false
        elseif not inInspector then
            state.contextMenu = true
            state.contextX = mx
            state.contextY = my
            state.menuWorldX = wx
            state.menuWorldY = wy
        end
        return
    end

    -- 左键按下
    if input:GetMouseButtonPress(MOUSEB_LEFT) then
        -- Inspector 面板内点击由 UI 组件处理，不再干预
        if inInspector then
            return
        end

        -- 上下文菜单点击
        if state.contextMenu then
            local handled, keepOpen = M._handleContextMenuClick(mx, my)
            if not keepOpen then
                state.contextMenu = false
            end
            if handled then return end
        end

        -- 端口命中
        local portNodeId, portIdx, isOutput = hitTestPort(wx, wy)
        if portNodeId then
            state.connecting = true
            state.connSrcNodeId = portNodeId
            state.connSrcPortIdx = portIdx
            state.connSrcIsOutput = isOutput
            state.connMouseX = mx
            state.connMouseY = my
            return
        end

        -- 节点命中
        local hitId = hitTestNode(wx, wy)
        if hitId then
            state.selectedNode = hitId
            state.draggingNode = hitId
            local node = state.tree.nodes[hitId]
            state.dragOffsetX = wx - node.x
            state.dragOffsetY = wy - node.y
            M._buildInspector(hitId)
        else
            state.selectedNode = nil
            M._destroyInspector()
            state.panning = true
            state.panStartX = mx
            state.panStartY = my
            state.panStartPanX = state.panX
            state.panStartPanY = state.panY
        end
    end

    -- 中键平移
    if input:GetMouseButtonPress(MOUSEB_MIDDLE) then
        state.panning = true
        state.panStartX = mx
        state.panStartY = my
        state.panStartPanX = state.panX
        state.panStartPanY = state.panY
    end

    -- 拖拽中
    if input:GetMouseButtonDown(MOUSEB_LEFT) or input:GetMouseButtonDown(MOUSEB_MIDDLE) then
        if state.draggingNode then
            local node = state.tree.nodes[state.draggingNode]
            if node then
                node.x = wx - state.dragOffsetX
                node.y = wy - state.dragOffsetY
            end
        elseif state.panning then
            state.panX = state.panStartPanX + (mx - state.panStartX)
            state.panY = state.panStartPanY + (my - state.panStartY)
        elseif state.connecting then
            state.connMouseX = mx
            state.connMouseY = my
        end
    end

    -- 释放
    if not input:GetMouseButtonDown(MOUSEB_LEFT) and not input:GetMouseButtonDown(MOUSEB_MIDDLE) then
        if state.connecting then
            local portNodeId2, portIdx2, isOutput2 = hitTestPort(wx, wy)
            if portNodeId2 and portNodeId2 ~= state.connSrcNodeId and isOutput2 ~= state.connSrcIsOutput then
                M._makeConnection(state.connSrcNodeId, state.connSrcPortIdx, state.connSrcIsOutput,
                                  portNodeId2, portIdx2, isOutput2)
            end
            state.connecting = false
        end
        state.draggingNode = nil
        state.panning = false
    end
end

-- ============================================================================
-- 建立连接
-- ============================================================================

function M._makeConnection(nodeA, portA, isOutputA, nodeB, portB, isOutputB)
    local srcNodeId, srcPortIdx, dstNodeId, dstPortIdx
    if isOutputA then
        srcNodeId, srcPortIdx = nodeA, portA
        dstNodeId, dstPortIdx = nodeB, portB
    else
        srcNodeId, srcPortIdx = nodeB, portB
        dstNodeId, dstPortIdx = nodeA, portA
    end

    local srcNode = state.tree.nodes[srcNodeId]
    local dstNode = state.tree.nodes[dstNodeId]
    if not srcNode or not dstNode then return end

    local srcPorts = SN.GetOutputPorts(srcNode)
    local dstPorts = SN.GetInputPorts(dstNode)
    local srcPort = srcPorts[srcPortIdx]
    local dstPort = dstPorts[dstPortIdx]
    if not srcPort or not dstPort then return end

    -- 类型兼容性
    if srcPort.type == "flow" and dstPort.type ~= "flow" then return end
    if srcPort.type ~= "flow" and dstPort.type == "flow" then return end

    SN.Connect(state.tree, srcNodeId, srcPort, dstNodeId, dstPort)
end

-- ============================================================================
-- 右键菜单 - 分类（自动从 NODE_TYPES 生成，新增节点自动出现）
-- ============================================================================

-- 分类显示顺序（不在此列表中的分类追加到末尾）
local MENU_CAT_ORDER = { "数据", "条件", "运算", "流程", "动作" }
-- 不显示在菜单中的分类（入口节点由系统自动创建）
local MENU_CAT_EXCLUDE = { ["入口"] = true }

local MENU_CATEGORIES  -- 延迟构建，首次打开菜单时生成

local function _buildMenuCategories()
    if MENU_CATEGORIES then return end
    -- 按 category 聚合所有节点类型
    local catMap = {}  -- category_name -> { nodeType1, nodeType2, ... }
    for nodeType, def in pairs(SN.NODE_TYPES) do
        local cat = def.category
        if cat and not MENU_CAT_EXCLUDE[cat] then
            if not catMap[cat] then catMap[cat] = {} end
            catMap[cat][#catMap[cat] + 1] = nodeType
        end
    end
    -- 按预定义顺序构建
    MENU_CATEGORIES = {}
    local added = {}
    for _, name in ipairs(MENU_CAT_ORDER) do
        if catMap[name] then
            MENU_CATEGORIES[#MENU_CATEGORIES + 1] = { name = name, types = catMap[name] }
            added[name] = true
        end
    end
    -- 追加未在预定义顺序中的新分类
    for name, types in pairs(catMap) do
        if not added[name] then
            MENU_CATEGORIES[#MENU_CATEGORIES + 1] = { name = name, types = types }
        end
    end
end

local MENU_ITEM_H = 38
local MENU_TAB_H = 32
local MENU_W = 240
local MENU_TAB_PAD = 8  -- tab 区域上下内边距

local function getMenuActualWidth()
    _buildMenuCategories()
    local tabsTotalW = MENU_TAB_PAD
    for _, cat in ipairs(MENU_CATEGORIES) do
        tabsTotalW = tabsTotalW + #cat.name * 14 + 16 + 4
    end
    tabsTotalW = tabsTotalW + MENU_TAB_PAD
    return math.max(MENU_W, tabsTotalW)
end

local function getMenuTotalHeight()
    _buildMenuCategories()
    local catIdx = state.menuSelectedCat or 1
    local cat = MENU_CATEGORIES[catIdx]
    local itemCount = cat and #cat.types or 0
    -- tab行 + items
    return MENU_TAB_PAD + MENU_TAB_H + MENU_TAB_PAD + itemCount * MENU_ITEM_H + MENU_TAB_PAD
end

function M._handleContextMenuClick(mx, my)
    _buildMenuCategories()
    local menuX = state.contextX
    local menuY = state.contextY

    -- 检查 tab 区域点击
    local tabY = menuY + MENU_TAB_PAD
    if my >= tabY and my <= tabY + MENU_TAB_H then
        local tabX = menuX + MENU_TAB_PAD
        for i, cat in ipairs(MENU_CATEGORIES) do
            local tabW = #cat.name * 14 + 16
            if mx >= tabX and mx <= tabX + tabW then
                state.menuSelectedCat = i
                return true, true  -- handled=true, keepOpen=true
            end
            tabX = tabX + tabW + 4
        end
    end

    -- 检查 item 区域点击
    local itemStartY = menuY + MENU_TAB_PAD + MENU_TAB_H + MENU_TAB_PAD
    local catIdx = state.menuSelectedCat or 1
    local cat = MENU_CATEGORIES[catIdx]
    local menuW = getMenuActualWidth()
    if cat then
        for idx, nodeType in ipairs(cat.types) do
            local itemY = itemStartY + (idx - 1) * MENU_ITEM_H
            if mx >= menuX and mx <= menuX + menuW and my >= itemY and my <= itemY + MENU_ITEM_H then
                local newNode = SN.Create(nodeType, { x = state.menuWorldX, y = state.menuWorldY })
                SN.AddNode(state.tree, newNode)
                state.selectedNode = newNode.id
                M._buildInspector(newNode.id)
                return true
            end
        end
    end
    return false
end

-- ============================================================================
-- NanoVG 渲染入口
-- ============================================================================

function M.Draw(vg, physW, physH)
    if not state.active or not state.tree then return end

    -- 深色背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, physW, physH)
    nvgFillColor(vg, nvgRGBA(COL_BG[1], COL_BG[2], COL_BG[3], COL_BG[4]))
    nvgFill(vg)

    -- 网格
    M._drawGrid(vg, physW, physH)

    -- 连线
    M._drawConnections(vg)

    -- 正在连线
    if state.connecting then
        M._drawConnectingLine(vg)
    end

    -- 节点
    for id, node in pairs(state.tree.nodes) do
        M._drawNode(vg, node, id == state.selectedNode)
    end

    -- 右键菜单 (最上层 NanoVG)
    if state.contextMenu then
        M._drawContextMenu(vg)
    end

    -- 顶部工具栏
    M._drawToolbar(vg, physW)

    -- 底部提示
    M._drawHints(vg, physW, physH)
end

-- ============================================================================
-- 绘制: 网格
-- ============================================================================

function M._drawGrid(vg, physW, physH)
    local gridSize = GRID_SIZE * state.zoom
    if gridSize < 8 then return end

    local alpha = math.min(35, math.floor(gridSize * 0.6))
    local startX = state.panX % gridSize
    local startY = state.panY % gridSize

    nvgBeginPath(vg)
    nvgStrokeColor(vg, nvgRGBA(COL_GRID[1], COL_GRID[2], COL_GRID[3], alpha))
    nvgStrokeWidth(vg, 0.8)

    local x = startX
    while x < physW do
        nvgMoveTo(vg, x, 0)
        nvgLineTo(vg, x, physH)
        x = x + gridSize
    end
    local y = startY
    while y < physH do
        nvgMoveTo(vg, 0, y)
        nvgLineTo(vg, physW, y)
        y = y + gridSize
    end
    nvgStroke(vg)

    -- 粗网格
    local bigGrid = gridSize * 5
    if bigGrid > 40 then
        local bigAlpha = math.min(50, math.floor(bigGrid * 0.3))
        local bsx = state.panX % bigGrid
        local bsy = state.panY % bigGrid
        nvgBeginPath(vg)
        nvgStrokeColor(vg, nvgRGBA(COL_GRID[1], COL_GRID[2], COL_GRID[3], bigAlpha))
        nvgStrokeWidth(vg, 1.2)
        x = bsx
        while x < physW do
            nvgMoveTo(vg, x, 0)
            nvgLineTo(vg, x, physH)
            x = x + bigGrid
        end
        y = bsy
        while y < physH do
            nvgMoveTo(vg, 0, y)
            nvgLineTo(vg, physW, y)
            y = y + bigGrid
        end
        nvgStroke(vg)
    end
end

-- ============================================================================
-- 绘制: 节点
-- ============================================================================

function M._drawNode(vg, node, isSelected)
    local sx, sy = worldToScreen(node.x, node.y)
    local sw = NODE_W * state.zoom
    local nh = getNodeHeight(node)
    local sh = nh * state.zoom
    local rr = 8 * state.zoom

    local meta = SN.NODE_TYPES[node.type] or { label = "?", color = {128, 128, 128}, icon = "?" }
    local r, g, b = meta.color[1], meta.color[2], meta.color[3]

    -- 阴影
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sx + 2 * state.zoom, sy + 3 * state.zoom, sw, sh, rr)
    nvgFillColor(vg, nvgRGBA(COL_SHADOW[1], COL_SHADOW[2], COL_SHADOW[3], COL_SHADOW[4]))
    nvgFill(vg)

    -- 主体
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sx, sy, sw, sh, rr)
    nvgFillColor(vg, nvgRGBA(COL_NODE_BODY[1], COL_NODE_BODY[2], COL_NODE_BODY[3], COL_NODE_BODY[4]))
    nvgFill(vg)

    -- 边框
    if isSelected then
        nvgStrokeColor(vg, nvgRGBA(COL_SEL_BORDER[1], COL_SEL_BORDER[2], COL_SEL_BORDER[3], COL_SEL_BORDER[4]))
        nvgStrokeWidth(vg, 2.5 * state.zoom)
    else
        nvgStrokeColor(vg, nvgRGBA(COL_NODE_BORDER[1], COL_NODE_BORDER[2], COL_NODE_BORDER[3], COL_NODE_BORDER[4]))
        nvgStrokeWidth(vg, 1.0 * state.zoom)
    end
    nvgStroke(vg)

    -- 头部渐变
    local headerH = NODE_HEADER_H * state.zoom
    nvgSave(vg)
    nvgIntersectScissor(vg, sx, sy, sw, headerH)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sx, sy, sw, sh, rr)
    local headerPaint = nvgLinearGradient(vg, sx, sy, sx, sy + headerH,
        nvgRGBA(r, g, b, 200), nvgRGBA(math.floor(r * 0.7), math.floor(g * 0.7), math.floor(b * 0.7), 200))
    nvgFillPaint(vg, headerPaint)
    nvgFill(vg)
    nvgRestore(vg)

    -- 头部分隔线
    nvgBeginPath(vg)
    nvgMoveTo(vg, sx, sy + headerH)
    nvgLineTo(vg, sx + sw, sy + headerH)
    nvgStrokeColor(vg, nvgRGBA(0, 0, 0, 60))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 头部文字
    nvgFontFace(vg, "sans")
    local iconSize = 14 * state.zoom
    local titleSize = 12 * state.zoom
    nvgFontSize(vg, iconSize)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 220))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local iconX = sx + 8 * state.zoom
    local headerCenterY = sy + headerH / 2
    nvgText(vg, iconX, headerCenterY, meta.icon or "")

    nvgFontSize(vg, titleSize)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
    nvgText(vg, iconX + iconSize + 4 * state.zoom, headerCenterY, meta.label)

    -- 摘要行
    local extraLines = getNodeContentLines(node)
    if extraLines > 0 then
        local inPorts = SN.GetInputPorts(node)
        local outPorts = SN.GetOutputPorts(node)
        local portCount = math.max(#inPorts, #outPorts)
        local summaryY = sy + headerH + portCount * NODE_PORT_H * state.zoom + 4 * state.zoom
        nvgFontSize(vg, 10 * state.zoom)
        nvgFillColor(vg, nvgRGBA(COL_TEXT_DIM[1], COL_TEXT_DIM[2], COL_TEXT_DIM[3], COL_TEXT_DIM[4]))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        local summary = M._getNodeSummary(node)
        if summary then
            nvgText(vg, sx + sw / 2, summaryY, summary)
        end
    end

    -- 输入端口
    local inPorts = SN.GetInputPorts(node)
    for pi, port in ipairs(inPorts) do
        local px, py = getInputPortPos(node, pi)
        local spx, spy = worldToScreen(px, py)
        M._drawPort(vg, spx, spy, port, false)
    end

    -- 输出端口
    local outPorts = SN.GetOutputPorts(node)
    for pi, port in ipairs(outPorts) do
        if port.isAdd then
            local px, py = getOutputPortPos(node, pi)
            local spx, spy = worldToScreen(px, py)
            nvgFontSize(vg, 12 * state.zoom)
            nvgFillColor(vg, nvgRGBA(150, 150, 160, 180))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgText(vg, spx, spy, "+")
        else
            local px, py = getOutputPortPos(node, pi)
            local spx, spy = worldToScreen(px, py)
            M._drawPort(vg, spx, spy, port, true)
        end
    end
end

function M._drawPort(vg, spx, spy, port, isOutput)
    local pr = PORT_RADIUS * state.zoom
    local pc = SN.PORT_COLORS[port.type] or {180, 180, 180}

    if port.type == "flow" then
        local s = pr * 1.2
        nvgBeginPath(vg)
        if isOutput then
            nvgMoveTo(vg, spx - s * 0.5, spy - s)
            nvgLineTo(vg, spx + s, spy)
            nvgLineTo(vg, spx - s * 0.5, spy + s)
        else
            nvgMoveTo(vg, spx + s * 0.5, spy - s)
            nvgLineTo(vg, spx - s, spy)
            nvgLineTo(vg, spx + s * 0.5, spy + s)
        end
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(pc[1], pc[2], pc[3], 220))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(20, 20, 25, 180))
        nvgStrokeWidth(vg, 1.0 * state.zoom)
        nvgStroke(vg)
    else
        nvgBeginPath(vg)
        nvgCircle(vg, spx, spy, pr)
        nvgFillColor(vg, nvgRGBA(pc[1], pc[2], pc[3], 220))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(20, 20, 25, 180))
        nvgStrokeWidth(vg, 1.2 * state.zoom)
        nvgStroke(vg)
    end

    -- 端口名
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10 * state.zoom)
    nvgFillColor(vg, nvgRGBA(COL_TEXT_DIM[1], COL_TEXT_DIM[2], COL_TEXT_DIM[3], COL_TEXT_DIM[4]))
    if isOutput then
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
        nvgText(vg, spx - (PORT_RADIUS + 5) * state.zoom, spy, port.name)
    else
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgText(vg, spx + (PORT_RADIUS + 5) * state.zoom, spy, port.name)
    end
end

function M._getNodeSummary(node)
    local t = node.type
    if t == "value" then return tostring(node.value or 0) end
    if t == "string" then
        local s = node.strValue or ""
        if #s > 12 then s = s:sub(1, 12) .. "…" end
        return '"' .. s .. '"'
    end
    if t == "param" then
        for _, p in ipairs(SN.RUNTIME_PARAMS) do
            if p.id == node.paramName then return "$" .. p.label end
        end
        return "$" .. (node.paramName or "?")
    end
    if t == "compare" then return node.op or ">" end
    if t == "math" then
        for _, o in ipairs(SN.MATH_OPS) do if o.id == node.op then return o.label end end
        return node.op or "+"
    end
    if t == "logic" then
        for _, o in ipairs(SN.LOGIC_OPS) do if o.id == node.op then return o.label end end
        return node.op or "and"
    end
    if t == "concat" then return "A .. B" end
    if t == "spawn" then
        for _, s in ipairs(SN.SPAWN_TYPES) do if s.id == node.spawnType then return s.label end end
        return node.spawnType or ""
    end
    if t == "play_fx" then
        for _, f in ipairs(SN.FX_TYPES) do if f.id == node.fxType then return f.label end end
        return node.fxType or ""
    end
    if t == "dialog" then
        local s = node.dialogText or ""
        if #s > 10 then s = s:sub(1, 10) .. "…" end
        return s
    end
    if t == "delay" then return string.format("%.1f秒", node.delaySeconds or 1) end
    if t == "repeat_n" then return string.format("%d次", node.repeatCount or 3) end
    if t == "win_level" then
        for _, w in ipairs(SN.WIN_TYPES) do if w.id == node.winType then return w.label end end
        return node.winType or ""
    end
    if t == "set_var" then
        for _, p in ipairs(SN.RUNTIME_PARAMS) do
            if p.id == node.varName then return p.label end
        end
        return node.varName or ""
    end
    if t == "damage" then
        local prefix = node.damageIsHeal and "+" or "-"
        return prefix .. tostring(node.damageAmount or 10) .. " HP"
    end
    if t == "move_obj" then
        local idx = node.targetObjIdx or 0
        if idx == 0 then return "未选择" end
        local EditorState = require("editor.EditorState")
        local edState = EditorState.state
        local chKey = edState.chapterIdx .. "_" .. edState.levelIdx
        local objects = edState.objects[chKey] or {}
        local obj = objects[idx]
        if obj then
            local name = obj.name or obj.type or "物件"
            if #name > 8 then name = name:sub(1, 8) .. "…" end
            return name
        end
        return "#" .. idx
    end
    if t == "camera_zoom" then
        local s = tostring(node.zoomScale or 1.0) .. "x"
        if node.zoomUsePan then
            s = s .. string.format(" →(%.0f,%.0f)", node.zoomCenterX or 15, node.zoomCenterY or 8.75)
        end
        return s
    end
    if t == "read_item" then
        for _, it in ipairs(SN.ITEM_TYPES) do if it.id == node.itemName then return "$" .. it.label end end
        return "$" .. (node.itemName or "?")
    end
    if t == "modify_item" then
        local opLabel = node.itemOp or "add"
        for _, o in ipairs(SN.ITEM_OPS) do if o.id == node.itemOp then opLabel = o.label; break end end
        local itemLabel = node.itemName or "?"
        for _, it in ipairs(SN.ITEM_TYPES) do if it.id == node.itemName then itemLabel = it.label; break end end
        return opLabel .. " " .. itemLabel
    end
    if t == "set_ability" then
        local abilLabel = node.abilityName or "?"
        for _, a in ipairs(SN.ABILITY_TYPES) do if a.id == node.abilityName then abilLabel = a.label; break end end
        return (node.abilityEnabled and "启用" or "禁用") .. " " .. abilLabel
    end
    if t == "destroy_self" then
        return "销毁自身"
    end
    return nil
end

-- ============================================================================
-- 绘制: 连线
-- ============================================================================

function M._drawConnections(vg)
    local conns = SN.GetAllConnections(state.tree)
    for _, conn in ipairs(conns) do
        local srcNode = state.tree.nodes[conn.srcNodeId]
        local dstNode = state.tree.nodes[conn.dstNodeId]
        if srcNode and dstNode then
            local sx, sy = getOutputPortPos(srcNode, conn.srcPortIdx)
            local dx, dy = getInputPortPos(dstNode, conn.dstPortIdx)
            sx, sy = worldToScreen(sx, sy)
            dx, dy = worldToScreen(dx, dy)
            M._drawBezier(vg, sx, sy, dx, dy, conn.portType)
        end
    end
end

function M._drawBezier(vg, x1, y1, x2, y2, portType)
    local pc = SN.PORT_COLORS[portType] or {180, 180, 180}
    local dist = math.abs(x2 - x1) * 0.4 + 30 * state.zoom
    dist = math.max(dist, 40 * state.zoom)

    nvgBeginPath(vg)
    nvgMoveTo(vg, x1, y1)
    nvgBezierTo(vg, x1 + dist, y1, x2 - dist, y2, x2, y2)
    nvgStrokeColor(vg, nvgRGBA(pc[1], pc[2], pc[3], 160))
    nvgStrokeWidth(vg, 2.2 * state.zoom)
    nvgStroke(vg)
end

function M._drawConnectingLine(vg)
    local srcNode = state.tree.nodes[state.connSrcNodeId]
    if not srcNode then return end

    local px, py
    if state.connSrcIsOutput then
        px, py = getOutputPortPos(srcNode, state.connSrcPortIdx)
    else
        px, py = getInputPortPos(srcNode, state.connSrcPortIdx)
    end
    px, py = worldToScreen(px, py)

    local mx, my = state.connMouseX, state.connMouseY
    if state.connSrcIsOutput then
        M._drawBezier(vg, px, py, mx, my, "flow")
    else
        M._drawBezier(vg, mx, my, px, py, "flow")
    end
end

-- ============================================================================
-- 绘制: 右键菜单
-- ============================================================================

function M._drawContextMenu(vg)
    local mx, my = state.contextX, state.contextY
    local totalH = getMenuTotalHeight()
    local menuW = getMenuActualWidth()

    -- 阴影
    nvgBeginPath(vg)
    nvgRoundedRect(vg, mx + 2, my + 2, menuW, totalH, 8)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 100))
    nvgFill(vg)

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, mx, my, menuW, totalH, 8)
    nvgFillColor(vg, nvgRGBA(COL_MENU_BG[1], COL_MENU_BG[2], COL_MENU_BG[3], COL_MENU_BG[4]))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(70, 70, 85, 200))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    local curMx = input.mousePosition.x
    local curMy = input.mousePosition.y

    nvgFontFace(vg, "sans")

    -- 绘制分类 tab 横向排列
    local tabX = mx + MENU_TAB_PAD
    local tabY = my + MENU_TAB_PAD
    local catIdx = state.menuSelectedCat or 1

    for i, cat in ipairs(MENU_CATEGORIES) do
        local tabW = #cat.name * 14 + 16
        local isActive = (i == catIdx)
        local isHovered = curMx >= tabX and curMx <= tabX + tabW and curMy >= tabY and curMy <= tabY + MENU_TAB_H

        -- tab 背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, tabX, tabY, tabW, MENU_TAB_H, 5)
        if isActive then
            nvgFillColor(vg, nvgRGBA(80, 100, 160, 220))
        elseif isHovered then
            nvgFillColor(vg, nvgRGBA(60, 60, 90, 180))
        else
            nvgFillColor(vg, nvgRGBA(40, 40, 60, 150))
        end
        nvgFill(vg)

        -- tab 文字
        nvgFontSize(vg, 13)
        nvgFillColor(vg, isActive and nvgRGBA(255, 255, 255, 240) or nvgRGBA(180, 180, 200, 200))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(vg, tabX + tabW / 2, tabY + MENU_TAB_H / 2, cat.name)

        tabX = tabX + tabW + 4
    end

    -- 分割线
    local sepY = my + MENU_TAB_PAD + MENU_TAB_H + 4
    nvgBeginPath(vg)
    nvgMoveTo(vg, mx + 8, sepY)
    nvgLineTo(vg, mx + menuW - 8, sepY)
    nvgStrokeColor(vg, nvgRGBA(80, 80, 110, 150))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 绘制当前分类的节点列表
    local itemStartY = my + MENU_TAB_PAD + MENU_TAB_H + MENU_TAB_PAD
    local cat = MENU_CATEGORIES[catIdx]
    if cat then
        for idx, nodeType in ipairs(cat.types) do
            local itemY = itemStartY + (idx - 1) * MENU_ITEM_H
            local hovered = curMx >= mx and curMx <= mx + menuW and curMy >= itemY and curMy <= itemY + MENU_ITEM_H

            if hovered then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, mx + 4, itemY + 2, menuW - 8, MENU_ITEM_H - 4, 5)
                nvgFillColor(vg, nvgRGBA(COL_MENU_HOVER[1], COL_MENU_HOVER[2], COL_MENU_HOVER[3], COL_MENU_HOVER[4]))
                nvgFill(vg)
            end

            local nodeMeta = SN.NODE_TYPES[nodeType] or { label = "?", color = {128,128,128}, icon = "?" }
            -- 色点
            nvgBeginPath(vg)
            nvgCircle(vg, mx + 22, itemY + MENU_ITEM_H / 2, 6)
            nvgFillColor(vg, nvgRGBA(nodeMeta.color[1], nodeMeta.color[2], nodeMeta.color[3], 220))
            nvgFill(vg)
            -- 文字
            nvgFontSize(vg, 15)
            nvgFillColor(vg, nvgRGBA(COL_TEXT[1], COL_TEXT[2], COL_TEXT[3], COL_TEXT[4]))
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgText(vg, mx + 38, itemY + MENU_ITEM_H / 2, nodeMeta.label)
        end
    end
end

-- ============================================================================
-- 绘制: 顶部工具栏
-- ============================================================================

function M._drawToolbar(vg, physW)
    local barH = 40

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, physW, barH)
    nvgFillColor(vg, nvgRGBA(COL_TOOLBAR[1], COL_TOOLBAR[2], COL_TOOLBAR[3], COL_TOOLBAR[4]))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, barH)
    nvgLineTo(vg, physW, barH)
    nvgStrokeColor(vg, nvgRGBA(70, 70, 85, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 15)
    nvgFillColor(vg, nvgRGBA(240, 200, 60, 240))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local title = "策略节点编辑器"
    if state.fieldName == "triggerStrategy" then
        title = "触发策略 - 节点编辑器"
    elseif state.fieldName == "executorStrategy" then
        title = "执行策略 - 节点编辑器"
    end
    nvgText(vg, 14, barH / 2, title)

    -- 缩放
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(COL_TEXT_DIM[1], COL_TEXT_DIM[2], COL_TEXT_DIM[3], COL_TEXT_DIM[4]))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(vg, physW / 2, barH / 2, string.format("%.0f%%", state.zoom * 100))

    -- 节点数
    local nodeCount = 0
    if state.tree then
        for _ in pairs(state.tree.nodes) do nodeCount = nodeCount + 1 end
    end
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(COL_TEXT_HINT[1], COL_TEXT_HINT[2], COL_TEXT_HINT[3], COL_TEXT_HINT[4]))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(vg, physW / 2, barH / 2 + 14, nodeCount .. " nodes")

    -- 关闭提示
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(200, 200, 210, 200))
    nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgText(vg, physW - 14, barH / 2, "[ESC] 关闭")
end

-- ============================================================================
-- 绘制: 底部提示
-- ============================================================================

function M._drawHints(vg, physW, physH)
    local hintY = physH - 24
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10)
    nvgFillColor(vg, nvgRGBA(COL_TEXT_HINT[1], COL_TEXT_HINT[2], COL_TEXT_HINT[3], COL_TEXT_HINT[4]))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgText(vg, 14, hintY, "右键:添加节点 | 拖拽端口:连线 | 中键/空白拖拽:平移 | 滚轮:缩放 | Del:删除")
end

return M
