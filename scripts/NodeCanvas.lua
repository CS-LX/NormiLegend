-- ============================================================================
-- NodeCanvas.lua - Blender/Unity 风格可视化节点编辑器
-- 使用 NanoVG 渲染, 支持拖拽节点、连接端口、平移缩放、Inspector 面板
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

    -- Inspector
    inspectorScrollY = 0,
    editingField = nil,  -- {nodeId, key} 当前正在编辑的字段
    editBuffer = "",
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
local INSPECTOR_W    = 340

-- 颜色调色板
local COL_BG         = {22, 22, 28, 252}
local COL_GRID       = {50, 50, 60}
local COL_NODE_BODY  = {38, 38, 46, 245}
local COL_NODE_BORDER= {60, 60, 70, 200}
local COL_SEL_BORDER = {255, 200, 60, 240}
local COL_SHADOW     = {0, 0, 0, 60}
local COL_TOOLBAR    = {30, 30, 38, 245}
local COL_INSP_BG    = {32, 32, 40, 240}
local COL_INSP_FIELD = {50, 50, 60, 220}
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

--- 本帧是否刚通过 ESC 关闭（用于阻止外层 ESC 连锁触发）
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
    state.editingField = nil
    state.inspectorScrollY = 0

    M._setEditorUIVisible(false)
end

function M.Close()
    M._setEditorUIVisible(true)
    if state.onClose then state.onClose() end
    state.active = false
    state.tree = nil
    state.obj = nil
    state.contextMenu = false
    state.connecting = false
    state.editingField = nil
end

function M._setEditorUIVisible(visible)
    local UI = require("urhox-libs/UI")
    local root = UI.GetRoot()
    if root and root.SetVisible then
        root:SetVisible(visible)
    end
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
    -- 额外显示行（节点参数摘要）
    if node.type == "value" or node.type == "param" or node.type == "compare"
       or node.type == "math" or node.type == "logic" then
        return 1
    end
    if node.type == "spawn" or node.type == "play_fx" or node.type == "gate"
       or node.type == "delay" or node.type == "repeat_n" or node.type == "win_level"
       or node.type == "set_var" or node.type == "damage" then
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

    -- 每帧开头清除"刚关闭"标志
    state.justClosed = false

    -- ESC 关闭节点画布，返回编辑器界面
    if input:GetKeyPress(KEY_ESCAPE) then
        state.justClosed = true
        M.Close()
        return
    end

    local mx = input.mousePosition.x
    local my = input.mousePosition.y
    local wx, wy = screenToWorld(mx, my)

    -- Inspector 区域检测 (右侧面板内不进行画布操作)
    local physW = graphics:GetWidth()
    local inInspector = state.selectedNode and mx > (physW - INSPECTOR_W)

    -- 滚轮缩放 (指数缩放，平滑)
    local wheel = input.mouseMoveWheel
    if wheel ~= 0 and not inInspector then
        local oldZoom = state.zoom
        -- 指数缩放: 极缓速率，每格滚轮变化约 0.05%
        local factor = 1.0005
        local newZoom = state.zoom * (factor ^ wheel)
        state.zoom = math.max(0.2, math.min(4.0, newZoom))
        -- 以鼠标位置为中心缩放
        local ratio = state.zoom / oldZoom
        state.panX = mx - (mx - state.panX) * ratio
        state.panY = my - (my - state.panY) * ratio
    end

    -- Inspector 滚轮
    if wheel ~= 0 and inInspector then
        state.inspectorScrollY = state.inspectorScrollY - wheel * 20
        state.inspectorScrollY = math.max(0, state.inspectorScrollY)
    end

    -- ESC 关闭
    if input:GetKeyPress(KEY_ESCAPE) then
        if state.editingField then
            state.editingField = nil
        elseif state.contextMenu then
            state.contextMenu = false
        else
            M.Close()
        end
        return
    end

    -- Delete 删除选中节点
    if input:GetKeyPress(KEY_DELETE) or input:GetKeyPress(KEY_BACKSPACE) then
        if not state.editingField and state.selectedNode and state.tree.nodes[state.selectedNode] then
            local node = state.tree.nodes[state.selectedNode]
            if node.type ~= "event" then
                SN.RemoveNode(state.tree, state.selectedNode)
                state.selectedNode = nil
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
        -- Inspector 面板内的点击
        if inInspector then
            M._handleInspectorClick(mx, my)
            return
        end

        -- 上下文菜单点击
        if state.contextMenu then
            local handled = M._handleContextMenuClick(mx, my)
            state.contextMenu = false
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
            state.inspectorScrollY = 0
            local node = state.tree.nodes[hitId]
            state.dragOffsetX = wx - node.x
            state.dragOffsetY = wy - node.y
            state.editingField = nil
        else
            state.selectedNode = nil
            state.editingField = nil
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
-- Inspector 面板点击处理
-- ============================================================================

function M._handleInspectorClick(mx, my)
    if not state.selectedNode then return end
    local node = state.tree.nodes[state.selectedNode]
    if not node then return end

    local fields = SN.INSPECTOR_FIELDS[node.type]
    if not fields then return end

    local physW = graphics:GetWidth()
    local panelX = physW - INSPECTOR_W
    local panelY = 40
    local startY = panelY + 84 - state.inspectorScrollY

    for i, field in ipairs(fields) do
        local fy = startY + (i - 1) * 88 + 32
        local fieldX = panelX + 18
        local fieldW = INSPECTOR_W - 36
        local fieldH = 44

        if mx >= fieldX and mx <= fieldX + fieldW and my >= fy and my <= fy + fieldH then
            if field.type == "select" then
                -- 循环切换选项
                local options = field.options
                if type(options) == "string" then options = SN[options] end
                if options then
                    local current = node[field.key]
                    local nextIdx = 1
                    for oi, opt in ipairs(options) do
                        if opt.id == current then nextIdx = oi + 1; break end
                    end
                    if nextIdx > #options then nextIdx = 1 end
                    node[field.key] = options[nextIdx].id
                end
            elseif field.type == "bool" then
                node[field.key] = not node[field.key]
            elseif field.type == "float" or field.type == "int" then
                -- 左半部分减，右半部分加
                local step = field.step or 1
                local mid = fieldX + fieldW / 2
                if mx < mid then
                    node[field.key] = math.max(field.min or -9999, (node[field.key] or field.default or 0) - step)
                else
                    node[field.key] = math.min(field.max or 9999, (node[field.key] or field.default or 0) + step)
                end
                if field.type == "int" then node[field.key] = math.floor(node[field.key] + 0.5) end
            end
            return
        end
    end
end

-- ============================================================================
-- 右键菜单 - 分类
-- ============================================================================

local MENU_CATEGORIES = {
    { name = "数据",   types = { "value", "param" } },
    { name = "条件",   types = { "compare", "logic" } },
    { name = "运算",   types = { "math" } },
    { name = "流程",   types = { "branch", "sequence", "random", "delay", "repeat_n" } },
    { name = "动作",   types = { "spawn", "move_obj", "set_var", "play_fx", "gate", "teleport", "damage", "win_level" } },
}

local MENU_ITEM_H = 48
local MENU_HEADER_H = 38
local MENU_W = 260

local function getMenuTotalHeight()
    local h = 8
    for _, cat in ipairs(MENU_CATEGORIES) do
        h = h + MENU_HEADER_H
        h = h + #cat.types * MENU_ITEM_H
    end
    return h + 8
end

function M._handleContextMenuClick(mx, my)
    local menuX = state.contextX
    local menuY = state.contextY
    local curY = menuY + 8

    for _, cat in ipairs(MENU_CATEGORIES) do
        curY = curY + MENU_HEADER_H
        for _, nodeType in ipairs(cat.types) do
            if mx >= menuX and mx <= menuX + MENU_W and my >= curY and my <= curY + MENU_ITEM_H then
                local newNode = SN.Create(nodeType, { x = state.menuWorldX, y = state.menuWorldY })
                SN.AddNode(state.tree, newNode)
                state.selectedNode = newNode.id
                return true
            end
            curY = curY + MENU_ITEM_H
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

    -- Inspector 面板 (在节点上层)
    if state.selectedNode and state.tree.nodes[state.selectedNode] then
        M._drawInspector(vg, physW, physH)
    end

    -- 右键菜单 (最上层)
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

    -- 粗网格 (5格一组)
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
-- 绘制: 节点 (美化版)
-- ============================================================================

function M._drawNode(vg, node, isSelected)
    local sx, sy = worldToScreen(node.x, node.y)
    local sw = NODE_W * state.zoom
    local nh = getNodeHeight(node)
    local sh = nh * state.zoom
    local rr = 8 * state.zoom  -- 圆角半径

    local meta = SN.NODE_TYPES[node.type] or { label = "?", color = {128, 128, 128}, icon = "?" }
    local r, g, b = meta.color[1], meta.color[2], meta.color[3]

    -- 阴影 (柔和)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sx + 2 * state.zoom, sy + 3 * state.zoom, sw, sh, rr)
    nvgFillColor(vg, nvgRGBA(COL_SHADOW[1], COL_SHADOW[2], COL_SHADOW[3], COL_SHADOW[4]))
    nvgFill(vg)

    -- 主体 (深色)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sx, sy, sw, sh, rr)
    nvgFillColor(vg, nvgRGBA(COL_NODE_BODY[1], COL_NODE_BODY[2], COL_NODE_BODY[3], COL_NODE_BODY[4]))
    nvgFill(vg)

    -- 选中/普通边框
    if isSelected then
        nvgStrokeColor(vg, nvgRGBA(COL_SEL_BORDER[1], COL_SEL_BORDER[2], COL_SEL_BORDER[3], COL_SEL_BORDER[4]))
        nvgStrokeWidth(vg, 2.5 * state.zoom)
    else
        nvgStrokeColor(vg, nvgRGBA(COL_NODE_BORDER[1], COL_NODE_BORDER[2], COL_NODE_BORDER[3], COL_NODE_BORDER[4]))
        nvgStrokeWidth(vg, 1.0 * state.zoom)
    end
    nvgStroke(vg)

    -- 头部 (圆角矩形上半部分)
    local headerH = NODE_HEADER_H * state.zoom
    nvgSave(vg)
    nvgIntersectScissor(vg, sx, sy, sw, headerH)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, sx, sy, sw, sh, rr)
    -- 渐变头部
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

    -- 头部图标 + 标题
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
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgText(vg, iconX + iconSize + 4 * state.zoom, headerCenterY, meta.label)

    -- 节点参数摘要 (在端口下方显示一行关键参数)
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
            -- "+" 按钮端口
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

--- 绘制单个端口（美化版）
function M._drawPort(vg, spx, spy, port, isOutput)
    local pr = PORT_RADIUS * state.zoom
    local pc = SN.PORT_COLORS[port.type] or {180, 180, 180}

    if port.type == "flow" then
        -- Flow 端口: 三角形/菱形
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
        -- 数据端口: 圆形
        nvgBeginPath(vg)
        nvgCircle(vg, spx, spy, pr)
        nvgFillColor(vg, nvgRGBA(pc[1], pc[2], pc[3], 220))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(20, 20, 25, 180))
        nvgStrokeWidth(vg, 1.2 * state.zoom)
        nvgStroke(vg)
    end

    -- 端口名称
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

--- 获取节点参数摘要文字
function M._getNodeSummary(node)
    local t = node.type
    if t == "value" then return tostring(node.value or 0) end
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
    if t == "spawn" then
        for _, s in ipairs(SN.SPAWN_TYPES) do if s.id == node.spawnType then return s.label end end
        return node.spawnType or ""
    end
    if t == "play_fx" then
        for _, f in ipairs(SN.FX_TYPES) do if f.id == node.fxType then return f.label end end
        return node.fxType or ""
    end
    if t == "gate" then
        for _, g in ipairs(SN.GATE_ACTIONS) do if g.id == node.gateAction then return g.label end end
        return node.gateAction or ""
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
    return nil
end

-- ============================================================================
-- 绘制: 连线 (贝塞尔曲线)
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

-- ============================================================================
-- 绘制: 正在拖拽的连线
-- ============================================================================

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
-- 绘制: Inspector 面板
-- ============================================================================

function M._drawInspector(vg, physW, physH)
    local node = state.tree.nodes[state.selectedNode]
    if not node then return end

    local panelX = physW - INSPECTOR_W
    local panelY = 40
    local panelH = physH - 80

    -- 面板背景
    nvgBeginPath(vg)
    nvgRect(vg, panelX, panelY, INSPECTOR_W, panelH)
    nvgFillColor(vg, nvgRGBA(COL_INSP_BG[1], COL_INSP_BG[2], COL_INSP_BG[3], COL_INSP_BG[4]))
    nvgFill(vg)
    -- 左边框线
    nvgBeginPath(vg)
    nvgMoveTo(vg, panelX, panelY)
    nvgLineTo(vg, panelX, panelY + panelH)
    nvgStrokeColor(vg, nvgRGBA(70, 70, 85, 200))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 节点类型标题
    local meta = SN.NODE_TYPES[node.type] or { label = "?", color = {128,128,128}, icon = "?" }
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 30)
    nvgFillColor(vg, nvgRGBA(meta.color[1], meta.color[2], meta.color[3], 240))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgText(vg, panelX + 18, panelY + 12, (meta.icon or "") .. " " .. meta.label)

    -- 描述
    nvgFontSize(vg, 20)
    nvgFillColor(vg, nvgRGBA(COL_TEXT_HINT[1], COL_TEXT_HINT[2], COL_TEXT_HINT[3], COL_TEXT_HINT[4]))
    nvgText(vg, panelX + 18, panelY + 48, meta.desc or "")

    -- Inspector 字段
    local fields = SN.INSPECTOR_FIELDS[node.type]
    if not fields then
        nvgFontSize(vg, 22)
        nvgFillColor(vg, nvgRGBA(COL_TEXT_DIM[1], COL_TEXT_DIM[2], COL_TEXT_DIM[3], COL_TEXT_DIM[4]))
        nvgText(vg, panelX + 18, panelY + 80, "该节点无可编辑属性")
        return
    end

    -- 裁剪区域
    nvgSave(vg)
    nvgScissor(vg, panelX, panelY + 78, INSPECTOR_W, panelH - 84)

    local startY = panelY + 84 - state.inspectorScrollY
    local fieldSpacing = 88  -- 每个字段总高度
    for i, field in ipairs(fields) do
        local fy = startY + (i - 1) * fieldSpacing

        -- 字段标签
        nvgFontSize(vg, 21)
        nvgFillColor(vg, nvgRGBA(COL_TEXT_DIM[1], COL_TEXT_DIM[2], COL_TEXT_DIM[3], COL_TEXT_DIM[4]))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgText(vg, panelX + 18, fy, field.label)

        -- 字段值区域
        local valY = fy + 32
        local valX = panelX + 18
        local valW = INSPECTOR_W - 36
        local valH = 44

        -- 背景框
        nvgBeginPath(vg)
        nvgRoundedRect(vg, valX, valY, valW, valH, 6)
        nvgFillColor(vg, nvgRGBA(COL_INSP_FIELD[1], COL_INSP_FIELD[2], COL_INSP_FIELD[3], COL_INSP_FIELD[4]))
        nvgFill(vg)
        nvgStrokeColor(vg, nvgRGBA(70, 70, 85, 150))
        nvgStrokeWidth(vg, 1)
        nvgStroke(vg)

        -- 值显示
        local displayVal = M._getFieldDisplayValue(node, field)
        nvgFontSize(vg, 22)
        nvgFillColor(vg, nvgRGBA(COL_TEXT[1], COL_TEXT[2], COL_TEXT[3], COL_TEXT[4]))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(vg, valX + valW / 2, valY + valH / 2, displayVal)

        -- 数值类型显示 +/- 提示
        if field.type == "float" or field.type == "int" then
            nvgFontSize(vg, 26)
            nvgFillColor(vg, nvgRGBA(120, 180, 255, 180))
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgText(vg, valX + 12, valY + valH / 2, "−")
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgText(vg, valX + valW - 12, valY + valH / 2, "+")
        end

        -- select 类型右侧箭头
        if field.type == "select" then
            nvgFontSize(vg, 20)
            nvgFillColor(vg, nvgRGBA(120, 180, 255, 180))
            nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
            nvgText(vg, valX + valW - 10, valY + valH / 2, "▸")
        end
    end

    nvgRestore(vg)
end

--- 获取字段显示值
function M._getFieldDisplayValue(node, field)
    local val = node[field.key]
    if val == nil then val = field.default end

    if field.type == "select" then
        local options = field.options
        if type(options) == "string" then options = SN[options] end
        if options then
            for _, opt in ipairs(options) do
                if opt.id == val then return opt.label end
            end
        end
        return tostring(val or "")
    elseif field.type == "bool" then
        return val and "✓ 是" or "✗ 否"
    elseif field.type == "float" then
        return string.format("%.1f", val or 0)
    elseif field.type == "int" then
        return tostring(math.floor((val or 0) + 0.5))
    elseif field.type == "text" then
        return tostring(val or "")
    end
    return tostring(val or "")
end

-- ============================================================================
-- 绘制: 右键菜单 (分类版)
-- ============================================================================

function M._drawContextMenu(vg)
    local mx, my = state.contextX, state.contextY
    local totalH = getMenuTotalHeight()

    -- 阴影
    nvgBeginPath(vg)
    nvgRoundedRect(vg, mx + 2, my + 2, MENU_W, totalH, 8)
    nvgFillColor(vg, nvgRGBA(0, 0, 0, 100))
    nvgFill(vg)

    -- 背景
    nvgBeginPath(vg)
    nvgRoundedRect(vg, mx, my, MENU_W, totalH, 8)
    nvgFillColor(vg, nvgRGBA(COL_MENU_BG[1], COL_MENU_BG[2], COL_MENU_BG[3], COL_MENU_BG[4]))
    nvgFill(vg)
    nvgStrokeColor(vg, nvgRGBA(70, 70, 85, 200))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    local curMx = input.mousePosition.x
    local curMy = input.mousePosition.y
    local curY = my + 8

    nvgFontFace(vg, "sans")

    for _, cat in ipairs(MENU_CATEGORIES) do
        -- 分类标题
        nvgFontSize(vg, 18)
        nvgFillColor(vg, nvgRGBA(COL_TEXT_HINT[1], COL_TEXT_HINT[2], COL_TEXT_HINT[3], COL_TEXT_HINT[4]))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgText(vg, mx + 14, curY + MENU_HEADER_H / 2, "— " .. cat.name .. " —")
        curY = curY + MENU_HEADER_H

        for _, nodeType in ipairs(cat.types) do
            local hovered = curMx >= mx and curMx <= mx + MENU_W and curMy >= curY and curMy <= curY + MENU_ITEM_H
            if hovered then
                nvgBeginPath(vg)
                nvgRoundedRect(vg, mx + 4, curY + 2, MENU_W - 8, MENU_ITEM_H - 4, 5)
                nvgFillColor(vg, nvgRGBA(COL_MENU_HOVER[1], COL_MENU_HOVER[2], COL_MENU_HOVER[3], COL_MENU_HOVER[4]))
                nvgFill(vg)
            end

            local nodeMeta = SN.NODE_TYPES[nodeType] or { label = "?", color = {128,128,128}, icon = "?" }
            -- 色点
            nvgBeginPath(vg)
            nvgCircle(vg, mx + 22, curY + MENU_ITEM_H / 2, 7)
            nvgFillColor(vg, nvgRGBA(nodeMeta.color[1], nodeMeta.color[2], nodeMeta.color[3], 220))
            nvgFill(vg)
            -- 文字
            nvgFontSize(vg, 22)
            nvgFillColor(vg, nvgRGBA(COL_TEXT[1], COL_TEXT[2], COL_TEXT[3], COL_TEXT[4]))
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            nvgText(vg, mx + 40, curY + MENU_ITEM_H / 2, nodeMeta.label)

            curY = curY + MENU_ITEM_H
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
    -- 底部描边
    nvgBeginPath(vg)
    nvgMoveTo(vg, 0, barH)
    nvgLineTo(vg, physW, barH)
    nvgStrokeColor(vg, nvgRGBA(70, 70, 85, 180))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)

    -- 标题
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

    -- 缩放信息
    nvgFontSize(vg, 12)
    nvgFillColor(vg, nvgRGBA(COL_TEXT_DIM[1], COL_TEXT_DIM[2], COL_TEXT_DIM[3], COL_TEXT_DIM[4]))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(vg, physW / 2, barH / 2, string.format("%.0f%%", state.zoom * 100))

    -- 关闭按钮
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
