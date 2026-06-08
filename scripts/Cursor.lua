-- ============================================================================
-- Cursor.lua - 自定义角色鼠标指针（作为 UI GlobalComponent 渲染）
-- 常态显示图1，鼠标按下时切换为图2，松开恢复图1
-- 点击时在热点处产生蓝绿色水波纹涟漪扩散特效
-- 通过 UI.RegisterGlobalComponent 注册，确保在所有 UI 内容之上渲染
-- ============================================================================

local UI = require("urhox-libs/UI")

local M = {}

local imgNormal_ = -1
local imgClick_ = -1
local inited_ = false

-- 指针显示尺寸（逻辑像素）
local CURSOR_SIZE = 100

-- 热点偏移（相对于图片左上角，单位为逻辑像素）
-- 对齐系统鼠标箭头尖端位置：箭头尖端大约在图片的 15%, 10% 处
local HOTSPOT_X = math.floor(CURSOR_SIZE * 0.15)
local HOTSPOT_Y = math.floor(CURSOR_SIZE * 0.10)

-- ============================================================================
-- 点击水波纹涟漪特效
-- ============================================================================
local MAX_RIPPLES = 5
local ripples_ = {}  -- { x, y, time, maxTime }
local RIPPLE_DURATION = 0.6  -- 涟漪持续时间（秒）
local RIPPLE_MAX_RADIUS = 40 -- 涟漪最大半径（逻辑像素）
local RIPPLE_RINGS = 2       -- 同时扩散的环数

local wasPressed_ = false    -- 上一帧鼠标状态（用于检测按下瞬间）
local lastTime_ = 0

--- 初始化自定义光标（在 UI.Init 之后调用）
function M.Init()
    -- [临时禁用] 使用系统默认光标，保留代码不删除
    input.mouseVisible = true
    print("[Cursor] Custom cursor DISABLED, using system default")
    do return end

    local nvg = UI.GetNVGContext()
    if not nvg then
        print("[Cursor] WARNING: UI NVG context not available")
        return
    end

    imgNormal_ = nvgCreateImage(nvg, "image/cursor_normal.png", 0)
    imgClick_ = nvgCreateImage(nvg, "image/cursor_click.png", 0)

    if imgNormal_ < 0 then
        print("[Cursor] WARNING: Failed to load cursor_normal.png")
    end
    if imgClick_ < 0 then
        print("[Cursor] WARNING: Failed to load cursor_click.png")
    end

    -- 使用 MM_FREE 模式隐藏系统光标，不会触发 Pointer Lock（不锁定鼠标）
    input.mouseMode = MM_FREE
    input.mouseVisible = false

    -- 注册为 UI 全局组件，确保在所有 UI 内容之上渲染
    UI.RegisterGlobalComponent("Cursor", M)
    inited_ = true
end

--- 生成一组涟漪
local function spawnRipple(x, y)
    for i = 1, RIPPLE_RINGS do
        local ripple = {
            x = x,
            y = y,
            time = 0,
            maxTime = RIPPLE_DURATION + (i - 1) * 0.12,  -- 每环稍微延迟
            delay = (i - 1) * 0.08,  -- 起始延迟
        }
        -- 环形缓冲：超出上限移除最旧的
        if #ripples_ >= MAX_RIPPLES then
            table.remove(ripples_, 1)
        end
        ripples_[#ripples_ + 1] = ripple
    end
end

--- 绘制涟漪特效
local function drawRipples(nvg, dt)
    local i = 1
    while i <= #ripples_ do
        local r = ripples_[i]
        r.time = r.time + dt

        local elapsed = r.time - r.delay
        if elapsed < 0 then
            -- 还在延迟中，不绘制
            i = i + 1
        elseif elapsed > r.maxTime then
            -- 已结束，移除
            table.remove(ripples_, i)
        else
            -- 计算进度 0~1
            local progress = elapsed / r.maxTime
            -- 缓出效果
            local eased = 1 - (1 - progress) * (1 - progress)

            local radius = RIPPLE_MAX_RADIUS * eased
            local alpha = math.floor(180 * (1 - progress))  -- 逐渐透明

            -- 蓝绿色涟漪环
            nvgBeginPath(nvg)
            nvgCircle(nvg, r.x, r.y, radius)
            nvgStrokeColor(nvg, nvgRGBA(80, 220, 210, alpha))
            nvgStrokeWidth(nvg, 2.5 * (1 - progress * 0.5))
            nvgStroke(nvg)

            -- 内部微弱填充光晕
            if progress < 0.4 then
                local fillAlpha = math.floor(40 * (1 - progress / 0.4))
                nvgBeginPath(nvg)
                nvgCircle(nvg, r.x, r.y, radius * 0.6)
                nvgFillColor(nvg, nvgRGBA(100, 240, 230, fillAlpha))
                nvgFill(nvg)
            end

            i = i + 1
        end
    end
end

--- UI GlobalComponent 渲染回调
--- 在 UI.Render 的 nvgBeginFrame/nvgEndFrame 内部调用
--- 坐标系为 UI 逻辑像素（已被 scale_ 缩放）
---@param nvg NVGContextWrapper
function M:Render(nvg)
    if not inited_ then return end
    if imgNormal_ < 0 then return end

    -- 计算 dt
    local now = time.elapsedTime
    local dt = now - lastTime_
    if dt > 0.1 then dt = 0.016 end  -- 首帧或跳帧保护
    lastTime_ = now

    -- 鼠标坐标是物理像素，需要转换为 UI 逻辑坐标
    local scale = UI.GetScale()
    local mx = input.mousePosition.x / scale
    local my = input.mousePosition.y / scale

    -- 判断是否有鼠标按键按下
    local isPressed = input:GetMouseButtonDown(MOUSEB_LEFT)
        or input:GetMouseButtonDown(MOUSEB_RIGHT)

    -- 检测按下瞬间 → 生成涟漪
    if isPressed and not wasPressed_ then
        spawnRipple(mx, my)
    end
    wasPressed_ = isPressed

    -- 绘制涟漪特效（在光标下方）
    drawRipples(nvg, dt)

    -- 绘制光标图片
    local img = (isPressed and imgClick_ >= 0) and imgClick_ or imgNormal_
    local drawX = mx - HOTSPOT_X
    local drawY = my - HOTSPOT_Y

    local paint = nvgImagePattern(nvg, drawX, drawY, CURSOR_SIZE, CURSOR_SIZE, 0, img, 1.0)
    nvgBeginPath(nvg)
    nvgRect(nvg, drawX, drawY, CURSOR_SIZE, CURSOR_SIZE)
    nvgFillPaint(nvg, paint)
    nvgFill(nvg)
end

--- 清理资源
function M.Dispose()
    if inited_ then
        local nvg = UI.GetNVGContext()
        if nvg and imgNormal_ >= 0 then
            nvgDeleteImage(nvg, imgNormal_)
            imgNormal_ = -1
        end
        if nvg and imgClick_ >= 0 then
            nvgDeleteImage(nvg, imgClick_)
            imgClick_ = -1
        end
        UI.UnregisterGlobalComponent("Cursor")
        inited_ = false
    end
end

return M
