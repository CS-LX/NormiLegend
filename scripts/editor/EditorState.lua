-- ============================================================================
-- editor/EditorState.lua
-- 编辑器全局状态 + 工具常量 + 坐标转换
-- 从 TitleMenu.lua 提取，保持语义不变
-- ============================================================================
local M = {}

-- ============================================================================
-- 编辑器状态（原 levelEditor_ God Object）
-- ============================================================================
M.state = {
    active = false,
    uiRoot = nil,
    chapterIdx = 1,
    levelIdx = 1,
    currentTool = "platform",  -- platform / obstacle / trigger / executor / select / delete
    mappingMode = false,       -- 映射编辑模式
    mappingTriggerIdx = nil,   -- 当前正在映射的触发器索引
    selectedObj = nil,         -- 当前选中物件索引
    objects = {},              -- 当前关卡的物件列表
    -- 画布参数（侧视图，单位：像素）
    canvasW = 1200,
    canvasH = 700,
    gridSize = 40,             -- 网格尺寸（像素）
    -- 世界坐标映射（米）
    worldW = 30,               -- 世界宽度（米）
    worldH = 17.5,             -- 世界高度（米）
    -- 画布平移偏移（像素）
    canvasPanX = 0,
    canvasPanY = 0,
    canvasPanning = false,     -- 是否正在拖拽画布平移（已超过阈值）
    canvasPanPotential = false,-- 是否处于潜在平移状态（按下空白但未超阈值）
    canvasPanStartX = 0,       -- 拖拽起始鼠标X
    canvasPanStartY = 0,       -- 拖拽起始鼠标Y
    canvasPanStartPanX = 0,    -- 拖拽起始时的panX
    canvasPanStartPanY = 0,    -- 拖拽起始时的panY
    -- 拖拽状态
    dragging = false,
    dragObjIdx = nil,
    dragOffsetX = 0,           -- 鼠标到物件左上角的偏移(像素)
    dragOffsetY = 0,
    dragStarted = false,       -- 是否已开始拖拽（区分点击和拖拽）
    mouseDownX = 0,
    mouseDownY = 0,
    toolbarH = 50,
    margin = 8,
    -- 撤销栈
    undoStack = {},            -- 保存操作前的对象列表快照
    maxUndo = 50,              -- 最大撤销步数
    -- 预览模式
    previewActive = false,
    previewScene = nil,
    previewPlayerNode = nil,
    previewPlayerBody = nil,
    previewCameraNode = nil,
    previewFootSensor = nil,
    previewOnGround = false,
    previewGroundContacts = 0,
    previewUIRoot = nil,
    previewNodes = {},         -- 生成的地形节点列表（用于清理）
    -- 触发器/执行器提示系统（仅预览）
    previewTriggerPopups = {},  -- { {text, x, y, timer, maxTime}, ... } 浮动文字
    previewTriggeredSet = {},   -- 已触发过的触发器索引集合（防止重复触发）
    previewInteractIdx = nil,   -- 当前可交互的触发器索引（显示F键提示）
    -- 贴图系统（多图层背景）
    bgLayers = {},             -- 背景图层列表: { {path, name, opacity, x, y, w, h, depth, visible}, ... }
    selectedBgLayer = nil,     -- 当前选中的背景图层索引
    textureBrowseTarget = nil, -- "bg" 或物件索引（当前正在为哪个目标选贴图）
    -- 贴图锚点拖拽
    texDragging = false,
    texDragType = nil,         -- "scale" / "rotate"
    texDragStartX = 0,
    texDragStartY = 0,
    texDragStartW = 0,
    texDragStartH = 0,
    texDragStartAngle = 0,
    -- 背景图层锚点拖拽
    bgDragging = false,
    bgDragType = nil,          -- "move" / "tl" / "tr" / "bl" / "br" (四角)
    bgDragStartMX = 0,
    bgDragStartMY = 0,
    bgDragStartX = 0,
    bgDragStartY = 0,
    bgDragStartW = 0,
    bgDragStartH = 0,
    -- NanoVG 贴图缓存
    nvgTextures = {},          -- path -> nvg image handle
    -- 手动导入的贴图素材列表
    customTextures = {},       -- { {path=..., name=..., cat=...}, ... }
    -- 镜头范围框（世界坐标，Y-up）
    -- 默认略小于编辑器世界，确保框在画布内可见
    cameraBounds = { x = 2, y = 1, w = 26, h = 15.5 },
    cameraBoundsEnabled = true, -- 是否启用镜头范围限制（默认开启预览）
    -- 镜头范围框拖拽
    camBoundsDragging = false,
    camBoundsDragType = nil,   -- "move" / "tl" / "tr" / "bl" / "br"
    camBoundsDragStartMX = 0,
    camBoundsDragStartMY = 0,
    camBoundsDragStartX = 0,
    camBoundsDragStartY = 0,
    camBoundsDragStartW = 0,
    camBoundsDragStartH = 0,
    -- 色环/颜色选择器
    colorPickerOpen = false,   -- 颜色选择器是否打开
    colorPickerH = 0,          -- HSV: Hue (0~360)
    colorPickerS = 1.0,        -- HSV: Saturation (0~1)
    colorPickerV = 1.0,        -- HSV: Value (0~1)
    colorHistory = {},         -- 最近10个使用的颜色 {{r,g,b,a}, ...}
}

-- ============================================================================
-- 工具配置常量
-- ============================================================================
M.TOOLS = {
    { id = "select",    name = "选择", color = {200, 200, 200, 200} },
    { id = "platform",  name = "平台", color = {80, 180, 80, 255} },
    { id = "obstacle",  name = "障碍", color = {200, 60, 60, 255} },
    { id = "trigger",   name = "触发器", color = {220, 180, 50, 255} },
    { id = "executor",  name = "执行器", color = {50, 160, 220, 255} },
    { id = "ground",    name = "地面", color = {140, 100, 60, 255} },
    { id = "texture",   name = "贴图", color = {180, 100, 200, 255} },
    { id = "delete",    name = "删除", color = {180, 40, 40, 200} },
}

-- ============================================================================
-- 坐标转换
-- ============================================================================

--- 世界坐标转画布像素（纯缩放，pan 偏移由容器层处理）
function M.WorldToCanvas(wx, wy, ww, wh)
    local cW = M.state.canvasW or 0
    local cH = M.state.canvasH or 0
    local worldW = M.state.worldW or 30
    local worldH = M.state.worldH or 17.5
    if worldW <= 0 then worldW = 30 end
    if worldH <= 0 then worldH = 17.5 end
    local scaleX = cW / worldW
    local scaleY = cH / worldH
    local px = wx * scaleX
    local py = wy * scaleY
    local pw = ww * scaleX
    local ph = wh * scaleY
    return px, py, pw, ph
end

--- 画布像素转世界坐标（纯缩放，pan 偏移由容器层处理）
function M.CanvasToWorld(cx, cy, cw, ch)
    local canvasW = M.state.canvasW
    local canvasH = M.state.canvasH
    local worldW = M.state.worldW
    local worldH = M.state.worldH
    local wx = cx / canvasW * worldW
    local wy = cy / canvasH * worldH
    local ww = cw / canvasW * worldW
    local wh = ch / canvasH * worldH
    return wx, wy, ww, wh
end

--- 获取物件类型对应颜色
function M.GetObjectColor(objType)
    if objType == "platform" then return {60, 160, 60, 220}
    elseif objType == "obstacle" then return {200, 50, 50, 220}
    elseif objType == "trigger" then return {220, 180, 50, 220}
    elseif objType == "executor" then return {50, 160, 220, 220}
    elseif objType == "ground" then return {130, 95, 50, 220}
    else return {100, 100, 100, 200}
    end
end

return M
