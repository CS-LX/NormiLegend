-- ============================================================================
-- WorldMap.lua - 大地图选择界面 + ESC离开弹窗
-- 通过NanoVG渲染大地图，点击区域进入对应关卡
-- 关卡内按ESC弹出确认弹窗，确认后返回大地图
-- ============================================================================

local LevelConfig = require("LevelConfig")

local WorldMap = {}

-- 状态枚举
WorldMap.STATE_MAP = "map"         -- 大地图选择界面
WorldMap.STATE_LEVEL = "level"     -- 关卡游戏中
WorldMap.STATE_ESC_POPUP = "esc"   -- ESC弹窗确认中

-- 当前状态
local state_ = WorldMap.STATE_MAP
local currentArea_ = nil           -- 当前所在区域ID
local selectedArea_ = nil          -- 鼠标悬浮的区域

-- NanoVG上下文引用
local nvg_ = nil

-- 大地图图片
local imgWorldMap_ = -1

-- 区域点击热区（屏幕坐标比例，相对于大地图图片）
-- 这些坐标对应生成的世界地图上三个区域的大致位置
local areaHotspots_ = {
    {
        id = LevelConfig.AREA_CASTLE,
        name = "华丽古堡",
        -- 古堡在地图中央偏右上
        cx = 0.5, cy = 0.35,
        radius = 0.12,
        color = { 180, 140, 60 },  -- 金色
    },
    {
        id = LevelConfig.AREA_ICE,
        name = "极寒冰原",
        -- 冰原在地图左侧
        cx = 0.2, cy = 0.5,
        radius = 0.12,
        color = { 100, 200, 255 },  -- 冰蓝色
    },
    {
        id = LevelConfig.AREA_FOREST,
        name = "幽暗森林",
        -- 森林在地图右侧
        cx = 0.8, cy = 0.55,
        radius = 0.12,
        color = { 80, 180, 80 },  -- 绿色
    },
}

-- ESC弹窗按钮热区
local escBtnYes_ = { x = 0, y = 0, w = 0, h = 0 }
local escBtnNo_ = { x = 0, y = 0, w = 0, h = 0 }

--- 初始化大地图模块
---@param nvgCtx userdata NanoVG上下文
function WorldMap.Init(nvgCtx)
    nvg_ = nvgCtx
    imgWorldMap_ = nvgCreateImage(nvg_, "image/world_map_20260601153957.png", 0)
    state_ = WorldMap.STATE_MAP
    currentArea_ = nil
end

--- 获取当前状态
---@return string
function WorldMap.GetState()
    return state_
end

--- 获取当前区域ID
---@return string|nil
function WorldMap.GetCurrentArea()
    return currentArea_
end

--- 是否在大地图界面（不在关卡中）
---@return boolean
function WorldMap.IsOnMap()
    return state_ == WorldMap.STATE_MAP
end

--- 是否显示ESC弹窗
---@return boolean
function WorldMap.IsEscPopup()
    return state_ == WorldMap.STATE_ESC_POPUP
end

--- 是否在关卡中（正常游玩状态）
---@return boolean
function WorldMap.IsInLevel()
    return state_ == WorldMap.STATE_LEVEL
end

--- 进入指定区域
---@param areaId string
function WorldMap.EnterArea(areaId)
    currentArea_ = areaId
    state_ = WorldMap.STATE_LEVEL
end

--- 显示ESC确认弹窗
function WorldMap.ShowEscPopup()
    if state_ == WorldMap.STATE_LEVEL then
        state_ = WorldMap.STATE_ESC_POPUP
    end
end

--- 关闭ESC弹窗（取消离开）
function WorldMap.CloseEscPopup()
    if state_ == WorldMap.STATE_ESC_POPUP then
        state_ = WorldMap.STATE_LEVEL
    end
end

--- 确认离开当前区域，返回大地图
function WorldMap.LeaveToMap()
    state_ = WorldMap.STATE_MAP
    currentArea_ = nil
end

--- 处理大地图点击输入
---@param mouseX number 鼠标屏幕X
---@param mouseY number 鼠标屏幕Y
---@param screenW number 屏幕宽
---@param screenH number 屏幕高
---@param clicked boolean 是否有点击
---@return string|nil 如果点击了某区域返回其ID，否则nil
function WorldMap.HandleMapInput(mouseX, mouseY, screenW, screenH, clicked)
    selectedArea_ = nil

    for _, spot in ipairs(areaHotspots_) do
        local spotX = spot.cx * screenW
        local spotY = spot.cy * screenH
        local spotR = spot.radius * math.min(screenW, screenH)

        local dx = mouseX - spotX
        local dy = mouseY - spotY
        if dx * dx + dy * dy <= spotR * spotR then
            selectedArea_ = spot.id
            if clicked then
                return spot.id
            end
        end
    end
    return nil
end

--- 处理ESC弹窗点击
---@param mouseX number
---@param mouseY number
---@param clicked boolean
---@return string|nil "yes"=确认离开, "no"=取消, nil=未点击按钮
function WorldMap.HandleEscInput(mouseX, mouseY, clicked)
    if not clicked then return nil end

    -- 检查"是"按钮
    if mouseX >= escBtnYes_.x and mouseX <= escBtnYes_.x + escBtnYes_.w
        and mouseY >= escBtnYes_.y and mouseY <= escBtnYes_.y + escBtnYes_.h then
        return "yes"
    end
    -- 检查"否"按钮
    if mouseX >= escBtnNo_.x and mouseX <= escBtnNo_.x + escBtnNo_.w
        and mouseY >= escBtnNo_.y and mouseY <= escBtnNo_.y + escBtnNo_.h then
        return "no"
    end
    return nil
end

--- 绘制大地图界面
---@param width number 屏幕宽
---@param height number 屏幕高
function WorldMap.DrawMap(width, height)
    if nvg_ == nil then return end

    -- 绘制大地图背景图
    if imgWorldMap_ and imgWorldMap_ > 0 then
        local paint = nvgImagePattern(nvg_, 0, 0, width, height, 0, imgWorldMap_, 1.0)
        nvgBeginPath(nvg_)
        nvgRect(nvg_, 0, 0, width, height)
        nvgFillPaint(nvg_, paint)
        nvgFill(nvg_)
    else
        -- fallback
        nvgBeginPath(nvg_)
        nvgRect(nvg_, 0, 0, width, height)
        nvgFillColor(nvg_, nvgRGBA(30, 40, 60, 255))
        nvgFill(nvg_)
    end

    -- 半透明遮罩让文字更清晰
    nvgBeginPath(nvg_)
    nvgRect(nvg_, 0, 0, width, height)
    nvgFillColor(nvg_, nvgRGBA(0, 0, 0, 40))
    nvgFill(nvg_)

    -- 标题
    nvgFontFace(nvg_, "sans")
    nvgFontSize(nvg_, 36)
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(nvg_, nvgRGBA(255, 240, 200, 255))
    nvgText(nvg_, width / 2, 20, "选择探索区域")

    -- 绘制区域热区（发光圆圈 + 名称标签）
    for _, spot in ipairs(areaHotspots_) do
        local spotX = spot.cx * width
        local spotY = spot.cy * height
        local spotR = spot.radius * math.min(width, height)
        local r, g, b = spot.color[1], spot.color[2], spot.color[3]

        local isSelected = (selectedArea_ == spot.id)
        local alpha = isSelected and 200 or 120
        local ringWidth = isSelected and 4 or 2.5

        -- 外发光
        local glowGrad = nvgRadialGradient(nvg_, spotX, spotY, spotR * 0.6, spotR * 1.2,
            nvgRGBA(r, g, b, math.floor(alpha * 0.4)), nvgRGBA(r, g, b, 0))
        nvgBeginPath(nvg_)
        nvgCircle(nvg_, spotX, spotY, spotR * 1.2)
        nvgFillPaint(nvg_, glowGrad)
        nvgFill(nvg_)

        -- 圆圈边框
        nvgBeginPath(nvg_)
        nvgCircle(nvg_, spotX, spotY, spotR)
        nvgStrokeColor(nvg_, nvgRGBA(r, g, b, alpha))
        nvgStrokeWidth(nvg_, ringWidth)
        nvgStroke(nvg_)

        -- 内部半透明填充
        nvgBeginPath(nvg_)
        nvgCircle(nvg_, spotX, spotY, spotR * 0.9)
        nvgFillColor(nvg_, nvgRGBA(r, g, b, isSelected and 60 or 30))
        nvgFill(nvg_)

        -- 区域名称
        nvgFontSize(nvg_, isSelected and 22 or 18)
        nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(nvg_, nvgRGBA(255, 255, 255, isSelected and 255 or 200))
        nvgText(nvg_, spotX, spotY, spot.name)

        -- 悬浮时提示"点击进入"
        if isSelected then
            nvgFontSize(nvg_, 14)
            nvgFillColor(nvg_, nvgRGBA(255, 255, 200, 200))
            nvgText(nvg_, spotX, spotY + spotR + 16, "点击进入")
        end
    end

    -- 底部操作提示
    nvgFontSize(nvg_, 16)
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(nvg_, nvgRGBA(200, 200, 200, 180))
    nvgText(nvg_, width / 2, height - 20, "点击区域进入关卡 | 关卡内按ESC可返回大地图")
end

--- 绘制ESC确认弹窗（覆盖在游戏画面上）
---@param width number
---@param height number
function WorldMap.DrawEscPopup(width, height)
    if nvg_ == nil then return end

    -- 半透明黑色遮罩
    nvgBeginPath(nvg_)
    nvgRect(nvg_, 0, 0, width, height)
    nvgFillColor(nvg_, nvgRGBA(0, 0, 0, 150))
    nvgFill(nvg_)

    -- 弹窗面板
    local panelW = 360
    local panelH = 180
    local panelX = (width - panelW) / 2
    local panelY = (height - panelH) / 2

    -- 面板背景
    nvgBeginPath(nvg_)
    nvgRoundedRect(nvg_, panelX, panelY, panelW, panelH, 12)
    nvgFillColor(nvg_, nvgRGBA(30, 30, 50, 240))
    nvgFill(nvg_)
    -- 面板边框
    nvgStrokeColor(nvg_, nvgRGBA(180, 160, 120, 200))
    nvgStrokeWidth(nvg_, 2)
    nvgStroke(nvg_)

    -- 标题
    nvgFontFace(nvg_, "sans")
    nvgFontSize(nvg_, 22)
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(nvg_, nvgRGBA(255, 240, 200, 255))
    nvgText(nvg_, width / 2, panelY + 25, "是否离开当前区域？")

    -- 副标题（当前区域名称）
    local areaConfig = currentArea_ and LevelConfig.GetArea(currentArea_)
    local areaName = areaConfig and areaConfig.name or "未知区域"
    nvgFontSize(nvg_, 16)
    nvgFillColor(nvg_, nvgRGBA(180, 180, 200, 200))
    nvgText(nvg_, width / 2, panelY + 55, "当前区域: " .. areaName)

    -- 按钮尺寸
    local btnW = 120
    local btnH = 42
    local btnY = panelY + panelH - 65
    local gap = 30
    local btnYesX = width / 2 - btnW - gap / 2
    local btnNoX = width / 2 + gap / 2

    -- "是"按钮
    nvgBeginPath(nvg_)
    nvgRoundedRect(nvg_, btnYesX, btnY, btnW, btnH, 8)
    nvgFillColor(nvg_, nvgRGBA(60, 160, 80, 220))
    nvgFill(nvg_)
    nvgStrokeColor(nvg_, nvgRGBA(100, 220, 120, 200))
    nvgStrokeWidth(nvg_, 1.5)
    nvgStroke(nvg_)

    nvgFontSize(nvg_, 18)
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg_, nvgRGBA(255, 255, 255, 255))
    nvgText(nvg_, btnYesX + btnW / 2, btnY + btnH / 2, "是，离开")

    -- "否"按钮
    nvgBeginPath(nvg_)
    nvgRoundedRect(nvg_, btnNoX, btnY, btnW, btnH, 8)
    nvgFillColor(nvg_, nvgRGBA(120, 60, 60, 220))
    nvgFill(nvg_)
    nvgStrokeColor(nvg_, nvgRGBA(200, 100, 100, 200))
    nvgStrokeWidth(nvg_, 1.5)
    nvgStroke(nvg_)

    nvgFillColor(nvg_, nvgRGBA(255, 255, 255, 255))
    nvgText(nvg_, btnNoX + btnW / 2, btnY + btnH / 2, "否，继续")

    -- 更新按钮热区供输入检测
    escBtnYes_.x = btnYesX
    escBtnYes_.y = btnY
    escBtnYes_.w = btnW
    escBtnYes_.h = btnH
    escBtnNo_.x = btnNoX
    escBtnNo_.y = btnY
    escBtnNo_.w = btnW
    escBtnNo_.h = btnH
end

return WorldMap
