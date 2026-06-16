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

    -- 绘制顺序：底图 → 立绘 → 名牌 → 文本（从后往前）
    M._drawComponent(vg, cfg.background, baseX, baseY, t, screenW, screenH, nil)
    M._drawComponent(vg, cfg.portrait,   baseX, baseY, t, screenW, screenH, nil)
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

    -- 绘制贴图
    if hasTexture then
        local img = getTexture(vg, comp.texturePath)
        if img then
            local imgW, imgH = nvgImageSize(vg, img)
            if imgW > 0 and imgH > 0 then
                -- 以组件中心锚点绘制原始尺寸图片
                local paint = nvgImagePattern(vg, -imgW / 2, -imgH / 2, imgW, imgH, 0, img, 1.0)
                nvgBeginPath(vg)
                nvgRect(vg, -imgW / 2, -imgH / 2, imgW, imgH)
                nvgFillPaint(vg, paint)
                nvgFill(vg)
            end
        end
    end

    -- 绘制文本
    if hasText then
        nvgFontSize(vg, 18)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(vg, 0, 0, textContent)
    end

    nvgRestore(vg)
end

--- 重置贴图缓存（场景切换时调用）
function M.ResetCache()
    texCache = {}
end

return M
