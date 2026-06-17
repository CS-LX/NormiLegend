-- ============================================================================
-- dialog/DialogView.lua - 对话框视图层（UI 组件实现）
-- 职责：用 urhox-libs/UI 组件渲染对话框，挂到 UI 根的最上层 overlay
-- 由 DialogManager 驱动（Show/Update/Hide），不含生命周期/互斥逻辑
-- 设计分辨率固定 1920×1080（与 UI.Init 一致），坐标直接用设计像素
-- ============================================================================

local UI = require("urhox-libs/UI")
local EffectRegistry = require("effects.EffectRegistry")

local M = {}

-- 设计分辨率（与 main.lua 的 UI.Init(DESIGN_RESOLUTION(1920,1080)) 一致）
local DW, DH = 1920, 1080

--- 当前挂载的全屏 overlay 根（nil = 未显示）
---@type table|nil
M._overlay = nil

--- 控件引用与状态
---@type table|nil
-- { panels = {background=,portrait=,whole=,nameplate=,textbox=}, nameLabel=, textLabel=, hintLabel=, lastText= }
M._refs = nil

-- ----------------------------------------------------------------------------
-- 构建辅助
-- ----------------------------------------------------------------------------

--- 构建图片组件 Panel（中心锚点 → 左上角定位）
---@param comp table|nil
---@return table|nil widget
local function buildImagePanel(comp)
    if not comp then return nil end
    local path = comp.texturePath
    if not path or path == "" then return nil end
    local w = (comp.width and comp.width > 0) and comp.width or 0
    local h = (comp.height and comp.height > 0) and comp.height or 0
    if w <= 0 or h <= 0 then return nil end  -- 构建期无法可靠取原始尺寸，要求显式宽高

    local cx = DW / 2 + (comp.offsetX or 0)
    local cy = DH + (comp.offsetY or 0)
    return UI.Panel {
        position = "absolute",
        left = cx - w / 2,
        top = cy - h / 2,
        width = w,
        height = h,
        backgroundImage = path,
        backgroundFit = "fill",
        opacity = comp.opacity or 1.0,
        pointerEvents = "none",
    }
end

--- 构建文本组件 Label（左对齐 + 垂直居中，等价旧 NanoVG LEFT+MIDDLE）
---@param comp table|nil
---@param content string|nil
---@return table|nil widget
local function buildTextLabel(comp, content)
    if not comp then return nil end
    if not content or content == "" then return nil end

    local cx = DW / 2 + (comp.offsetX or 0)
    local cy = DH + (comp.offsetY or 0)
    local fs = comp.fontSize or 18
    local boxH = fs * 1.6

    local props = {
        position = "absolute",
        left = cx,
        top = cy - boxH / 2,
        width = 1700,           -- 足够宽的单行盒子（与旧 NanoVG 不换行行为一致）
        height = boxH,
        text = content,
        fontSize = fs,
        fontColor = comp.fontColor or { 255, 255, 255, 255 },
        textAlign = "left",
        verticalAlign = "middle",
        whiteSpace = "nowrap",
        pointerEvents = "none",
    }
    if comp.strokeWidth and comp.strokeWidth > 0 then
        props.textStroke = { width = comp.strokeWidth, color = comp.strokeColor or { 0, 0, 0, 255 } }
    end
    return UI.Label(props)
end

-- ----------------------------------------------------------------------------
-- 公开接口
-- ----------------------------------------------------------------------------

--- 显示对话框：构建 overlay 并挂到 UI 根最上层
---@param config table  DialogConfig.FromNode 的产物
function M.Show(config)
    M.Hide()  -- 互斥：先清理旧的

    local children = {}
    local refs = { panels = {} }

    -- 绘制顺序：底图 → 立绘 → 整体 → 名牌(图+字) → 文本(图+字)（文本层最后，防遮挡）
    local order = { "background", "portrait", "whole", "nameplate", "textbox" }
    for _, key in ipairs(order) do
        local p = buildImagePanel(config[key])
        if p then
            children[#children + 1] = p
            refs.panels[key] = p
        end
    end

    -- 名牌文字
    local nameLabel = buildTextLabel(config.nameplate, config.nameplateText)
    if nameLabel then
        children[#children + 1] = nameLabel
        refs.nameLabel = nameLabel
    end

    -- 文本框文字（支持打字机/淡入/上滑动画，初始按动画起始态构建）
    local textLabel = buildTextLabel(config.textbox, config.dialogText)
    if textLabel then
        children[#children + 1] = textLabel
        refs.textLabel = textLabel
        refs.lastText = config.dialogText or ""
    end

    -- click 模式提示
    if config.durationMode == "click" then
        local hint = UI.Label {
            position = "absolute",
            left = 0, bottom = 8,
            width = "100%", height = 24,
            text = "[ 点击继续 ]",
            fontSize = 14,
            fontColor = { 255, 255, 255, 180 },
            textAlign = "center",
            pointerEvents = "none",
        }
        children[#children + 1] = hint
        refs.hintLabel = hint
    end

    -- 全屏 overlay：fixed + 高 zIndex 置顶；box-none 让点击穿透（沿用游戏侧轮询关闭）
    local overlay = UI.Panel {
        position = "fixed",
        top = 0, left = 0,
        width = "100%", height = "100%",
        zIndex = 9000,
        pointerEvents = "box-none",
        children = children,
    }

    local root = UI.GetRoot()
    if root then root:AddChild(overlay) end
    M._overlay = overlay
    M._refs = refs
end

--- UTF-8 安全截取前 n 个字符
---@param s string
---@param n number
---@return string
local function utf8Sub(s, n)
    local shown, byteIdx = 0, 1
    local len = #s
    while shown < n and byteIdx <= len do
        local b = string.byte(s, byteIdx) or 0
        if b < 0x80 then byteIdx = byteIdx + 1
        elseif b < 0xE0 then byteIdx = byteIdx + 2
        elseif b < 0xF0 then byteIdx = byteIdx + 3
        else byteIdx = byteIdx + 4 end
        shown = shown + 1
    end
    return s:sub(1, byteIdx - 1)
end

--- 每帧更新：文本动画 + effects 动态变换 + 提示闪烁
---@param dt number
---@param config table
---@param elapsed number  对话已显示时间（秒）
function M.Update(dt, config, elapsed)
    local refs = M._refs
    if not refs then return end
    local t = elapsed

    -- effects 仅在配置了效果时每帧应用（默认空则 no-op，避免无谓 SetStyle）
    local function applyImageEffects(panel, comp)
        if not panel or not comp then return end
        if not comp.effects or #comp.effects == 0 then return end
        local dx, dy, sc, ang, al = EffectRegistry.Apply(comp.effects, t)
        panel:SetStyle({
            translateX = dx, translateY = dy,
            scale = sc, rotate = math.deg(ang),
            opacity = (comp.opacity or 1.0) * al,
        })
    end
    applyImageEffects(refs.panels.background, config.background)
    applyImageEffects(refs.panels.portrait, config.portrait)
    applyImageEffects(refs.panels.whole, config.whole)
    applyImageEffects(refs.panels.nameplate, config.nameplate)
    applyImageEffects(refs.panels.textbox, config.textbox)

    -- 名牌文字 effects
    if refs.nameLabel and config.nameplate.effects and #config.nameplate.effects > 0 then
        local dx, dy, _, _, al = EffectRegistry.Apply(config.nameplate.effects, t)
        refs.nameLabel:SetStyle({ translateX = dx, translateY = dy, opacity = al })
    end

    -- 文本框文字：动画（typewriter / fade_in / slide_up）+ effects
    if refs.textLabel then
        local comp = config.textbox
        local full = config.dialogText or ""
        local animType = comp.textAnim or "none"
        local animSpeed = comp.textAnimSpeed or 3.0

        local displayText = full
        local textAlpha = 1.0
        local textOffY = 0

        if animType == "typewriter" then
            local charsToShow = math.floor(t * animSpeed)
            displayText = utf8Sub(full, charsToShow)
        elseif animType == "fade_in" then
            textAlpha = math.min(1.0, t * animSpeed * 0.5)
        elseif animType == "slide_up" then
            local prog = math.min(1.0, t * animSpeed * 0.5)
            textAlpha = prog
            textOffY = (1.0 - prog) * 30
        end

        -- 仅在文字变化时 SetText（打字机增量更新）
        if displayText ~= refs.lastText then
            refs.textLabel:SetText(displayText)
            refs.lastText = displayText
        end

        -- effects 叠加到动画偏移/透明度
        local edx, edy, eAlpha = 0, 0, 1.0
        if comp.effects and #comp.effects > 0 then
            local dx, dy, _, _, al = EffectRegistry.Apply(comp.effects, t)
            edx, edy, eAlpha = dx, dy, al
        end
        refs.textLabel:SetStyle({
            translateX = edx,
            translateY = edy + textOffY,
            opacity = textAlpha * eAlpha,
        })
    end

    -- click 提示闪烁
    if refs.hintLabel then
        local blink = math.sin(t * 4) * 0.3 + 0.7
        refs.hintLabel:SetStyle({ opacity = blink })
    end
end

--- 隐藏并销毁对话框 overlay
function M.Hide()
    if M._overlay then
        local root = UI.GetRoot()
        if root then root:RemoveChild(M._overlay) end
        M._overlay:Destroy()
        M._overlay = nil
    end
    M._refs = nil
end

return M
