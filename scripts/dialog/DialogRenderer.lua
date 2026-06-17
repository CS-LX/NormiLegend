-- ============================================================================
-- dialog/DialogRenderer.lua - 对话框渲染器
-- 职责：纯 NanoVG 绘制，不含逻辑控制
-- 在 DrawPreview 末尾调用，绘制在 HUD 层之上
-- ============================================================================

local DialogManager = require("dialog.DialogManager")
local EffectRegistry = require("effects.EffectRegistry")

local M = {}

-- 缓存的 NanoVG 贴图句柄
local texCache = {}

--- 获取/缓存贴图句柄
local function getTexture(vg, path)
    if not path or path == "" then return nil end
    if texCache[path] then return texCache[path] end
    local handle = nvgCreateImage(vg, path, 0)
    if handle and handle > 0 then
        texCache[path] = handle
        return handle
    end
    return nil
end

--- 绘制当前活跃对话框
---@param vg userdata    NanoVG 上下文
---@param screenW number 渲染区域宽（像素）
---@param screenH number 渲染区域高（像素）
function M.Draw(vg, screenW, screenH)
    local active = DialogManager.active
    if not active then return end
    local cfg = active.config
    local t = active.elapsed

    -- 对话框锚点：屏幕底部居中
    local baseX = screenW / 2
    local baseY = screenH

    nvgSave(vg)

    -- 绘制顺序：底图 → 立绘 → 整体 → 名牌 → 文本（文本层最后，防止被遮挡）
    M._drawComponent(vg, cfg.background, baseX, baseY, t, screenW, screenH, nil)
    M._drawComponent(vg, cfg.portrait,   baseX, baseY, t, screenW, screenH, nil)
    M._drawComponent(vg, cfg.whole,      baseX, baseY, t, screenW, screenH, nil)
    M._drawComponent(vg, cfg.nameplate,  baseX, baseY, t, screenW, screenH, cfg.nameplateText)
    M._drawComponent(vg, cfg.textbox,    baseX, baseY, t, screenW, screenH, cfg.dialogText)

    -- click 模式提示（闪烁）
    if cfg.durationMode == "click" then
        local blink = math.sin(t * 4) * 0.3 + 0.7
        nvgFontSize(vg, 14)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, math.floor(blink * 180)))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        nvgText(vg, baseX, baseY - 8, "[ 点击继续 ]")
    end

    nvgRestore(vg)
end

--- 绘制单个组件
---@param vg userdata
---@param comp table       组件配置 {texturePath, offsetX, offsetY, opacity, effects}
---@param baseX number     基准X（屏幕中心）
---@param baseY number     基准Y（屏幕底部）
---@param t number         对话已显示时间（秒）
---@param screenW number
---@param screenH number
---@param textContent string|nil  文本内容（名牌/对话用）
function M._drawComponent(vg, comp, baseX, baseY, t, screenW, screenH, textContent)
    if not comp then return end
    local hasTexture = comp.texturePath and comp.texturePath ~= ""
    local hasText = textContent and textContent ~= ""
    if not hasTexture and not hasText then return end

    -- 应用动态效果
    local dx, dy, scale, angle, alpha = 0, 0, 1, 0, 1.0
    if comp.effects and #comp.effects > 0 then
        dx, dy, scale, angle, alpha = EffectRegistry.Apply(comp.effects, t)
    end
    alpha = alpha * (comp.opacity or 1.0)
    if alpha <= 0 then return end

    local cx = baseX + (comp.offsetX or 0) + dx
    local cy = baseY + (comp.offsetY or 0) + dy

    nvgSave(vg)
    nvgTranslate(vg, cx, cy)
    if angle ~= 0 then nvgRotate(vg, angle) end
    if scale ~= 1 then nvgScale(vg, scale, scale) end
    nvgGlobalAlpha(vg, alpha)

    -- 绘制贴图（支持自定义宽高，0表示使用原始尺寸）
    if hasTexture then
        local img = getTexture(vg, comp.texturePath)
        if img then
            local imgW, imgH = nvgImageSize(vg, img)
            if imgW > 0 and imgH > 0 then
                local drawW = (comp.width and comp.width > 0) and comp.width or imgW
                local drawH = (comp.height and comp.height > 0) and comp.height or imgH
                local paint = nvgImagePattern(vg, -drawW / 2, -drawH / 2, drawW, drawH, 0, img, 1.0)
                nvgBeginPath(vg)
                nvgRect(vg, -drawW / 2, -drawH / 2, drawW, drawH)
                nvgFillPaint(vg, paint)
                nvgFill(vg)
            end
        end
    end

    -- 绘制文本（支持样式：字号、颜色、描边 + 动画）
    if hasText then
        local fontSize = comp.fontSize or 18
        local fontColor = comp.fontColor or {255, 255, 255, 255}
        local strokeW = comp.strokeWidth or 0
        local strokeColor = comp.strokeColor or {0, 0, 0, 255}
        local animType = comp.textAnim or "none"
        local animSpeed = comp.textAnimSpeed or 3.0

        -- 应用文本动画
        local displayText = textContent --[[@as string]]
        local textAlpha = 1.0
        local textOffY = 0

        if animType == "typewriter" then
            -- 打字机：按时间逐字显示
            local charsToShow = math.floor(t * animSpeed)
            -- UTF-8 安全截取
            local shown = 0
            local byteIdx = 1
            while shown < charsToShow and byteIdx <= #textContent do
                local b = string.byte(textContent, byteIdx) or 0
                if b < 0x80 then byteIdx = byteIdx + 1
                elseif b < 0xE0 then byteIdx = byteIdx + 2
                elseif b < 0xF0 then byteIdx = byteIdx + 3
                else byteIdx = byteIdx + 4 end
                shown = shown + 1
            end
            displayText = (textContent or ""):sub(1, byteIdx - 1)
        elseif animType == "fade_in" then
            -- 浮现：透明度从0到1
            local progress = math.min(1.0, t * animSpeed * 0.5)
            textAlpha = progress
        elseif animType == "slide_up" then
            -- 上滑：从下方滑入 + 渐显
            local progress = math.min(1.0, t * animSpeed * 0.5)
            textAlpha = progress
            textOffY = (1.0 - progress) * 30
        end

        if #displayText == 0 then
            -- 动画还没开始显示任何字符
        else
            nvgSave(vg)
            nvgTranslate(vg, 0, textOffY)
            nvgFontSize(vg, fontSize)
            nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

            local finalAlpha = textAlpha * alpha
            -- 描边
            if strokeW > 0 then
                nvgFontBlur(vg, strokeW)
                nvgFillColor(vg, nvgRGBA(strokeColor[1], strokeColor[2], strokeColor[3], math.floor((strokeColor[4] or 255) * finalAlpha)))
                nvgText(vg, 0, 0, displayText)
                nvgFontBlur(vg, 0)
            end
            -- 填充
            nvgFillColor(vg, nvgRGBA(fontColor[1], fontColor[2], fontColor[3], math.floor((fontColor[4] or 255) * finalAlpha)))
            nvgText(vg, 0, 0, displayText)
            nvgRestore(vg)
        end
    end

    nvgRestore(vg)
end

--- 从节点数据直接绘制对话框（编辑器预览用）
---@param vg userdata
---@param screenW number
---@param screenH number
---@param node table 策略节点原始数据
function M.DrawFromNode(vg, screenW, screenH, node)
    if not node then return end

    local baseX = screenW / 2
    local baseY = screenH
    local t = time.elapsedTime

    nvgSave(vg)

    -- 底图
    M._drawComponent(vg, {
        texturePath = node.dlgBgTexture or "",
        offsetX = node.dlgBgOffsetX or -76,
        offsetY = node.dlgBgOffsetY or -333,
        opacity = node.dlgBgOpacity or 0.95,
        width = node.dlgBgWidth or 1550,
        height = node.dlgBgHeight or 660,
    }, baseX, baseY, t, screenW, screenH, nil)

    -- 立绘
    M._drawComponent(vg, {
        texturePath = node.dlgPortraitTexture or "",
        offsetX = node.dlgPortraitOffsetX or -500,
        offsetY = node.dlgPortraitOffsetY or -300,
        opacity = node.dlgPortraitOpacity or 1.0,
        width = node.dlgPortraitWidth or 610,
        height = node.dlgPortraitHeight or 600,
    }, baseX, baseY, t, screenW, screenH, nil)

    -- 整体贴图（在名牌/文本之前，防止遮挡文字）
    M._drawComponent(vg, {
        texturePath = node.dlgWholeTexture or "",
        offsetX = node.dlgWholeOffsetX or -100,
        offsetY = node.dlgWholeOffsetY or -318,
        opacity = node.dlgWholeOpacity or 1.0,
        width = node.dlgWholeWidth or 1600,
        height = node.dlgWholeHeight or 1075,
    }, baseX, baseY, t, screenW, screenH, nil)

    -- 名牌（最后渲染，不被遮挡）
    M._drawComponent(vg, {
        texturePath = node.dlgNameTexture or "",
        offsetX = node.dlgNameOffsetX or -100,
        offsetY = node.dlgNameOffsetY or -140,
        opacity = node.dlgNameOpacity or 1.0,
        fontSize = node.dlgNameFontSize or 16,
        fontColor = node.dlgNameFontColor or {255,255,255,255},
        strokeWidth = node.dlgNameStrokeW or 0,
        strokeColor = node.dlgNameStrokeColor or {0,0,0,255},
    }, baseX, baseY, t, screenW, screenH, node.dlgSpeaker or "")

    -- 文本框（最后渲染，不被遮挡）
    M._drawComponent(vg, {
        texturePath = node.dlgTextTexture or "",
        offsetX = node.dlgTextOffsetX or -150,
        offsetY = node.dlgTextOffsetY or -209,
        opacity = node.dlgTextOpacity or 1.0,
        fontSize = node.dlgTextFontSize or 44,
        fontColor = node.dlgTextFontColor or {0,0,0,255},
        strokeWidth = node.dlgTextStrokeW or 1.5,
        strokeColor = node.dlgTextStrokeColor or {0,0,0,200},
        textAnim = node.dlgTextAnim or "none",
        textAnimSpeed = node.dlgTextAnimSpeed or 3.0,
    }, baseX, baseY, t, screenW, screenH, node.dialogText or "")

    nvgRestore(vg)
end

--- 重置贴图缓存（场景切换时调用）
function M.ResetCache()
    texCache = {}
end

return M
