-- ============================================================================
-- editor/EditorRenderer.lua
-- 编辑器画布NanoVG渲染（从 TitleMenu.lua 提取，语义不变）
-- ============================================================================
local C = require("GameConfig")
local EditorState = require("editor.EditorState")
local NodeCanvas = require("NodeCanvas")

local R = {}
local levelEditor_ = EditorState.state

--- 获取/缓存NanoVG贴图句柄
local function GetNvgTexture(vg, path)
    if not path or path == "" then return nil end
    if levelEditor_.nvgTextures[path] then
        return levelEditor_.nvgTextures[path]
    end
    local handle = nvgCreateImage(vg, path, 0)
    if handle and handle > 0 then
        levelEditor_.nvgTextures[path] = handle
        return handle
    end
    return nil
end

function R.DrawEditorCanvasTextures(vg, physW, physH)
    if not levelEditor_.active then return end
    if levelEditor_.previewActive then return end

    -- NodeCanvas 打开时，全屏覆盖渲染节点编辑器
    if NodeCanvas.IsActive() then
        NodeCanvas.Draw(vg, physW, physH)
        return
    end

    local dpr = graphics:GetDPR()
    local toolbarH = 50
    local margin = 8
    local canvasW = levelEditor_.canvasW or 0
    local canvasH = levelEditor_.canvasH or 0
    if canvasW <= 0 or canvasH <= 0 then return end

    -- 画布在屏幕上的物理像素起点
    local canvasX = margin * dpr
    local canvasY = (toolbarH + margin) * dpr
    local canvasPhysW = canvasW * dpr
    local canvasPhysH = canvasH * dpr

    -- 画布平移偏移（物理像素）
    local panOffX = (levelEditor_.canvasPanX or 0) * dpr
    local panOffY = (levelEditor_.canvasPanY or 0) * dpr

    -- 裁剪到画布区域（用 nvgScissor 而非 nvgIntersectScissor）
    nvgSave(vg)
    nvgScissor(vg, canvasX, canvasY, canvasPhysW, canvasPhysH)
    -- 将 canvasX/canvasY 加上平移偏移，后续所有绘制自动跟随画布平移
    canvasX = canvasX + panOffX
    canvasY = canvasY + panOffY

    -- 获取当前关卡物件
    ---@type integer
    local ch = levelEditor_.chapterIdx
    ---@type integer
    local lv = levelEditor_.levelIdx
    local key = ch .. "_" .. lv
    local objects = levelEditor_.objects[key] or {}
    local gridSize = levelEditor_.gridSize or 40  -- 40px/m

    -- 渲染背景图层（使用世界坐标定位）
    -- 渲染顺序：列表上方（索引小）的层在视觉上层 → 逆序渲染
    local bgLayers = levelEditor_.bgLayers or {}
    local edWorldH = levelEditor_.worldH or 17.5
    for li = #bgLayers, 1, -1 do
        local layer = bgLayers[li]
        if layer.visible ~= false then
            local bgImg = GetNvgTexture(vg, layer.path)
            -- 使用世界坐标转画布坐标（layer.y 是 Y-up 底边，需转 top-down）
            local lx = layer.x or 0
            local ly = layer.y or 0
            local lw = layer.w or 10
            local lh = layer.h or 6
            local canvasTopY = edWorldH - ly - lh
            local px, py, pw, ph = EditorState.WorldToCanvas(lx, canvasTopY, lw, lh)
            local sx = canvasX + px * dpr
            local sy = canvasY + py * dpr
            local sw = pw * dpr
            local sh = ph * dpr
            local alpha = layer.opacity or 1.0

            if bgImg then
                local paint = nvgImagePattern(vg, sx, sy, sw, sh, 0, bgImg, alpha)
                nvgBeginPath(vg)
                nvgRect(vg, sx, sy, sw, sh)
                nvgFillPaint(vg, paint)
                nvgFill(vg)
            end

            -- 紫色预览框
            local isSel = (levelEditor_.selectedBgLayer == li)
            local borderAlpha = isSel and 220 or 140
            nvgBeginPath(vg)
            nvgRect(vg, sx, sy, sw, sh)
            nvgStrokeColor(vg, nvgRGBA(180, 100, 255, borderAlpha))
            nvgStrokeWidth(vg, (isSel and 2.0 or 1.5) * dpr)
            nvgStroke(vg)

            -- 四角锚点（仅选中时显示）
            if isSel then
                local anchorR = 5 * dpr
                local corners = {
                    {sx, sy},                  -- 左上
                    {sx + sw, sy},             -- 右上
                    {sx, sy + sh},             -- 左下
                    {sx + sw, sy + sh},        -- 右下
                }
                for _, c in ipairs(corners) do
                    nvgBeginPath(vg)
                    nvgCircle(vg, c[1], c[2], anchorR)
                    nvgFillColor(vg, nvgRGBA(200, 120, 255, 240))
                    nvgFill(vg)
                    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 200))
                    nvgStrokeWidth(vg, 1.0 * dpr)
                    nvgStroke(vg)
                end
            end

            -- 右下角名称标签
            local bgName = layer.name or ""
            if bgName ~= "" then
                nvgFontSize(vg, 10 * dpr)
                nvgFontFace(vg, "sans")
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                nvgFillColor(vg, nvgRGBA(200, 140, 255, 220))
                nvgText(vg, sx + sw - 3 * dpr, sy + sh - 2 * dpr, bgName)
            end
        end
    end

    -- 渲染物件贴图图层 + 颜色染色 + 位置标识框
    for _, obj in ipairs(objects) do
        local px, py, pw, ph = EditorState.WorldToCanvas(obj.x, obj.y, obj.w, obj.h)
        local sx = canvasX + px * dpr
        local sy = canvasY + py * dpr
        local sw = pw * dpr
        local sh = ph * dpr
        local cx = sx + sw / 2
        local cy = sy + sh / 2

        -- 多贴图图层渲染（使用物件颜色染色）
        -- 渲染顺序：列表上方（索引小）的层在视觉上层 → 逆序渲染
        local objCol = obj.color or {255, 255, 255, 255}
        local texLayers = obj.texLayers
        if texLayers and #texLayers > 0 then
            for tli = #texLayers, 1, -1 do
                local tLayer = texLayers[tli]
                if tLayer.visible ~= false then
                    local texImg = GetNvgTexture(vg, tLayer.path)
                    local tScW = tLayer.scaleW or 1.0
                    local tScH = tLayer.scaleH or 1.0
                    local drawW = sw * tScW
                    local drawH = sh * tScH
                    local alpha = tLayer.opacity or 1.0

                    if texImg then
                        local tintColor = nvgRGBA(objCol[1], objCol[2], objCol[3], math.floor((objCol[4] or 255) * alpha))
                        local paint = nvgImagePatternTinted(vg, cx - drawW/2, cy - drawH/2, drawW, drawH, 0, texImg, tintColor)
                        nvgBeginPath(vg)
                        nvgRect(vg, cx - drawW/2, cy - drawH/2, drawW, drawH)
                        nvgFillPaint(vg, paint)
                        nvgFill(vg)
                    end
                end
            end
            -- 绘制位置标识框（最外层以最大尺寸为基准）
            nvgBeginPath(vg)
            nvgRect(vg, sx, sy, sw, sh)
            nvgStrokeColor(vg, nvgRGBA(255, 200, 50, 180))
            nvgStrokeWidth(vg, 1.5 * dpr)
            nvgStroke(vg)
            -- 右下角名称标签
            local firstName = texLayers[1] and texLayers[1].name or obj.name or ""
            if firstName ~= "" then
                nvgFontSize(vg, 10 * dpr)
                nvgFontFace(vg, "sans")
                nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
                nvgFillColor(vg, nvgRGBA(255, 220, 100, 220))
                nvgText(vg, sx + sw - 3 * dpr, sy + sh - 2 * dpr, firstName)
            end
        elseif obj.texture then
            -- 兼容旧的单贴图数据（未迁移）
            local texImg = GetNvgTexture(vg, obj.texture)
            local tScW = obj.texScaleW or 1.0
            local tScH = obj.texScaleH or 1.0
            local drawW = sw * tScW
            local drawH = sh * tScH

            if texImg then
                local tintColor = nvgRGBA(objCol[1], objCol[2], objCol[3], math.floor((objCol[4] or 255) * 0.9))
                local paint = nvgImagePatternTinted(vg, cx - drawW/2, cy - drawH/2, drawW, drawH, 0, texImg, tintColor)
                nvgBeginPath(vg)
                nvgRect(vg, cx - drawW/2, cy - drawH/2, drawW, drawH)
                nvgFillPaint(vg, paint)
                nvgFill(vg)
            end
            nvgBeginPath(vg)
            nvgRect(vg, cx - drawW/2, cy - drawH/2, drawW, drawH)
            nvgStrokeColor(vg, nvgRGBA(255, 200, 50, 180))
            nvgStrokeWidth(vg, 1.5 * dpr)
            nvgStroke(vg)
        end
    end

    -- 贴图工具：绘制选中物件的贴图图层四角锚点
    if levelEditor_.currentTool == "texture" and levelEditor_.selectedObj then
        local selObj = objects[levelEditor_.selectedObj]
        if selObj then
            local spx, spy, spw, sph = EditorState.WorldToCanvas(selObj.x, selObj.y, selObj.w, selObj.h)
            local ssx = canvasX + spx * dpr
            local ssy = canvasY + spy * dpr
            local ssw = spw * dpr
            local ssh = sph * dpr
            -- 多图层选中层锚点
            local tLayer = nil
            if selObj.texLayers and #selObj.texLayers > 0 and selObj.selectedTexLayer then
                tLayer = selObj.texLayers[selObj.selectedTexLayer]
            end
            if tLayer and tLayer.path and tLayer.path ~= "" then
                local tScW = tLayer.scaleW or 1.0
                local tScH = tLayer.scaleH or 1.0
                local tW = ssw * tScW
                local tH = ssh * tScH
                local tOffL = (ssw - tW) / 2
                local tOffT = (ssh - tH) / 2
                local tx = ssx + tOffL
                local ty = ssy + tOffT
                -- 贴图范围框
                nvgBeginPath(vg)
                nvgRect(vg, tx, ty, tW, tH)
                nvgStrokeColor(vg, nvgRGBA(200, 130, 255, 200))
                nvgStrokeWidth(vg, 1.5 * dpr)
                nvgStroke(vg)
                -- 四角锚点
                local anchorR = 5 * dpr
                local tCorners = {
                    {tx, ty}, {tx + tW, ty},
                    {tx, ty + tH}, {tx + tW, ty + tH},
                }
                for _, c in ipairs(tCorners) do
                    nvgBeginPath(vg)
                    nvgCircle(vg, c[1], c[2], anchorR)
                    nvgFillColor(vg, nvgRGBA(100, 220, 255, 240))
                    nvgFill(vg)
                    nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 220))
                    nvgStrokeWidth(vg, 1.0 * dpr)
                    nvgStroke(vg)
                end
            end
        end
    end

    -- ====== 镜头范围框绘制（黄色虚线矩形） ======
    if levelEditor_.cameraBoundsEnabled and levelEditor_.cameraBounds then
        local cb = levelEditor_.cameraBounds
        local edWorldH = levelEditor_.worldH or 17.5
        -- cameraBounds.y 是 Y-up 底边，转为 top-down
        local cbTopY = edWorldH - cb.y - cb.h
        local cbPx, cbPy, cbPw, cbPh = EditorState.WorldToCanvas(cb.x, cbTopY, cb.w, cb.h)
        local cbSx = canvasX + cbPx * dpr
        local cbSy = canvasY + cbPy * dpr
        local cbSw = cbPw * dpr
        local cbSh = cbPh * dpr

        -- 黄色边框
        nvgBeginPath(vg)
        nvgRect(vg, cbSx, cbSy, cbSw, cbSh)
        nvgStrokeColor(vg, nvgRGBA(255, 200, 50, 200))
        nvgStrokeWidth(vg, 2.0 * dpr)
        nvgStroke(vg)

        -- 半透明填充标识
        nvgBeginPath(vg)
        nvgRect(vg, cbSx, cbSy, cbSw, cbSh)
        nvgFillColor(vg, nvgRGBA(255, 220, 50, 15))
        nvgFill(vg)

        -- 四角锚点
        local cbAnchorR = 5 * dpr
        local cbCorners = {
            {cbSx, cbSy}, {cbSx + cbSw, cbSy},
            {cbSx, cbSy + cbSh}, {cbSx + cbSw, cbSy + cbSh},
        }
        for _, c in ipairs(cbCorners) do
            nvgBeginPath(vg)
            nvgCircle(vg, c[1], c[2], cbAnchorR)
            nvgFillColor(vg, nvgRGBA(255, 200, 50, 240))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, 200))
            nvgStrokeWidth(vg, 1.0 * dpr)
            nvgStroke(vg)
        end

        -- 左上角标签
        nvgFontSize(vg, 10 * dpr)
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(255, 220, 80, 220))
        nvgText(vg, cbSx + 3 * dpr, cbSy - 2 * dpr, "镜头范围")

        -- ====== 单屏视野参考框（青色虚线，居中显示） ======
        -- 游戏实际一屏大小：SCREEN_WIDTH/PIXELS_PER_UNIT × SCREEN_HEIGHT/PIXELS_PER_UNIT
        local viewW = C.SCREEN_WIDTH / C.PIXELS_PER_UNIT   -- ≈21.33
        local viewH = C.SCREEN_HEIGHT / C.PIXELS_PER_UNIT  -- =12
        -- 居中于镜头范围框中心
        local viewCenterX = cb.x + cb.w / 2
        local viewCenterY = cb.y + cb.h / 2
        local viewLeft = viewCenterX - viewW / 2
        local viewBottom = viewCenterY - viewH / 2
        local viewTopY = edWorldH - viewBottom - viewH
        local vpx, vpy, vpw, vph = EditorState.WorldToCanvas(viewLeft, viewTopY, viewW, viewH)
        local vsx = canvasX + vpx * dpr
        local vsy = canvasY + vpy * dpr
        local vsw = vpw * dpr
        local vsh = vph * dpr
        -- 青色边框
        nvgBeginPath(vg)
        nvgRect(vg, vsx, vsy, vsw, vsh)
        nvgStrokeColor(vg, nvgRGBA(80, 220, 255, 180))
        nvgStrokeWidth(vg, 1.5 * dpr)
        nvgStroke(vg)
        -- 右上角标签
        nvgFontSize(vg, 9 * dpr)
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
        nvgFillColor(vg, nvgRGBA(80, 220, 255, 200))
        nvgText(vg, vsx + vsw - 2 * dpr, vsy - 2 * dpr, "单屏视野")
    end

    nvgRestore(vg) -- 恢复裁剪
end

return R
