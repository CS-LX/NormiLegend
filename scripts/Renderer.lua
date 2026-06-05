-- ============================================================================
-- Renderer.lua - 所有 NanoVG 渲染函数
-- 负责背景、平台、投射物、特效、玩家、HP/MP条、调试信息的绘制
-- ============================================================================

local C = require("GameConfig")
local S = require("GameState")
local WorldMap = require("WorldMap")
local Enemy = require("Enemy")
local BatEnemy = require("BatEnemy")
local CastleEnemies = require("CastleEnemies")
local LevelConfig = require("LevelConfig")

local M = {}

-- ============================================================================
-- 坐标转换工具
-- ============================================================================
function M.PhysicsToScreen(physX, physY, camX, camY)
    local screenX = C.SCREEN_WIDTH / 2 + (physX - camX) * C.PIXELS_PER_UNIT
    local screenY = C.SCREEN_HEIGHT / 2 - (physY - camY) * C.PIXELS_PER_UNIT
    return screenX, screenY
end

-- ============================================================================
-- 16:9 Letterbox 计算（SHOW_ALL 策略）
-- 返回: offsetX, offsetY, viewW, viewH（安全区域在物理屏幕中的位置和尺寸）
-- ============================================================================
local TARGET_ASPECT = 16 / 9

function M.CalcLetterbox(physW, physH)
    local screenAspect = physW / physH
    local viewW, viewH, offsetX, offsetY
    if screenAspect > TARGET_ASPECT then
        -- 屏幕更宽 → 左右黑边（pillarbox）
        viewH = physH
        viewW = physH * TARGET_ASPECT
        offsetX = (physW - viewW) / 2
        offsetY = 0
    else
        -- 屏幕更高 → 上下黑边（letterbox）
        viewW = physW
        viewH = physW / TARGET_ASPECT
        offsetX = 0
        offsetY = (physH - viewH) / 2
    end
    return offsetX, offsetY, viewW, viewH
end

-- ============================================================================
-- 主渲染入口（NanoVGRender 事件调用）
-- ============================================================================
function M.HandleRender(eventType, eventData)
    if S.nvg == nil then return end

    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()

    nvgBeginFrame(S.nvg, physW, physH, 1.0)

    -- 标题视频页面 / 主菜单 → 不渲染游戏画面（UI 自行处理）
    if S.showTitleScreen or S.showMainMenu then
        nvgEndFrame(S.nvg)
        return
    end

    -- 计算 16:9 安全区域
    local ox, oy, viewW, viewH = M.CalcLetterbox(physW, physH)

    -- 绘制黑色背景（清除非安全区域）
    nvgBeginPath(S.nvg)
    nvgRect(S.nvg, 0, 0, physW, physH)
    nvgFillColor(S.nvg, nvgRGBA(0, 0, 0, 255))
    nvgFill(S.nvg)

    -- 将后续所有绘制限制在 16:9 安全区域内
    nvgSave(S.nvg)
    nvgTranslate(S.nvg, ox, oy)
    -- 传递给子函数的 width/height 就是安全区域尺寸
    local width = viewW
    local height = viewH

    -- 在世界地图 → 委托给世界地图渲染
    if WorldMap.IsOnMap() then
        WorldMap.DrawMap(width, height)
        nvgRestore(S.nvg)
        nvgEndFrame(S.nvg)
        return
    end

    -- 获取相机位置
    local camPos = S.cameraNode and S.cameraNode.worldPosition or Vector3(0, 0, -10)
    local camX, camY = camPos.x, camPos.y

    -- 绘制顺序：背景 → 平台 → 投射物 → 特效 → 敌人 → 玩家 → HUD
    M.DrawBackground(width, height, camX, camY)
    M.DrawPlatforms(width, height, camX, camY)
    M.DrawProjectiles(width, height, camX, camY)

    -- 蓄力特效（在玩家后面）
    if S.isCharging then
        if S.currentCharacter == 2 then
            M.DrawChargeEffectChar2(width, height, camX, camY)
        else
            M.DrawChargeEffect(width, height, camX, camY)
        end
    end

    -- 治愈特效（在玩家后面）
    if S.isHealing then
        M.DrawHealEffect(width, height, camX, camY)
    end

    -- 敌人渲染
    Enemy.Draw(width, height, camX, camY, C.SCREEN_WIDTH, C.SCREEN_HEIGHT, C.PIXELS_PER_UNIT)
    BatEnemy.Draw(width, height, camX, camY, C.SCREEN_WIDTH, C.SCREEN_HEIGHT, C.PIXELS_PER_UNIT)
    CastleEnemies.Draw(width, height, camX, camY, C.SCREEN_WIDTH, C.SCREEN_HEIGHT, C.PIXELS_PER_UNIT)

    -- 玩家
    M.DrawPlayer(width, height, camX, camY)

    -- 地面冰晶
    M.DrawIceCrystals(width, height, camX, camY)

    -- HP/MP 血条
    if not S.editorMode then
        M.DrawHPMPBars(width, height)
    end

    -- 调试信息
    if not S.editorMode and S.debugDraw then
        M.DrawDebugInfo(width, height)
    end

    -- 敌方血条（最上层）
    Enemy.DrawHealthBars(width, height, camX, camY, C.SCREEN_WIDTH, C.SCREEN_HEIGHT, C.PIXELS_PER_UNIT)
    BatEnemy.DrawHealthBars(width, height, camX, camY, C.SCREEN_WIDTH, C.SCREEN_HEIGHT, C.PIXELS_PER_UNIT)
    CastleEnemies.DrawHealthBars(width, height, camX, camY, C.SCREEN_WIDTH, C.SCREEN_HEIGHT, C.PIXELS_PER_UNIT)

    -- GM控制台
    local GMConsole = require("GMConsole")
    GMConsole.Draw(width, height)

    -- 切图编辑器
    if S.editorMode then
        local SpriteEditor = require("SpriteEditor")
        SpriteEditor.DrawPreview(width, height)
    end

    nvgRestore(S.nvg)
    nvgEndFrame(S.nvg)
end

-- ============================================================================
-- 背景绘制（多层视差 / 单图 / 渐变）
-- ============================================================================
function M.DrawBackground(width, height, camX, camY)
    local vg = S.nvg

    -- 多层视差背景
    if #S.parallaxLayers > 0 then
        for _, layer in ipairs(S.parallaxLayers) do
            if layer.img and layer.img > 0 then
                local offsetX = -camX * layer.factor * C.PIXELS_PER_UNIT * (width / C.SCREEN_WIDTH)
                local imgW, imgH = nvgImageSize(vg, layer.img)
                local scaleH = height / imgH
                local drawW = imgW * scaleH
                -- 平铺填充
                local startX = (offsetX % drawW) - drawW
                for x = startX, width, drawW do
                    local paint = nvgImagePattern(vg, x, 0, drawW, height, 0, layer.img, 1.0)
                    nvgBeginPath(vg)
                    nvgRect(vg, x, 0, drawW, height)
                    nvgFillPaint(vg, paint)
                    nvgFill(vg)
                end
            end
        end
        return
    end

    -- 单图背景
    if S.imgBackground and S.imgBackground > 0 then
        local paint = nvgImagePattern(vg, 0, 0, width, height, 0, S.imgBackground, 1.0)
        nvgBeginPath(vg)
        nvgRect(vg, 0, 0, width, height)
        nvgFillPaint(vg, paint)
        nvgFill(vg)
        return
    end

    -- 渐变兜底
    local grad = nvgLinearGradient(vg, 0, 0, 0, height,
        nvgRGBA(20, 30, 60, 255), nvgRGBA(50, 70, 120, 255))
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, width, height)
    nvgFillPaint(vg, grad)
    nvgFill(vg)
end

-- ============================================================================
-- 平台绘制
-- ============================================================================
function M.DrawPlatforms(width, height, camX, camY)
    local vg = S.nvg
    local sx = width / C.SCREEN_WIDTH
    local sy = height / C.SCREEN_HEIGHT

    -- 地面
    local groundScreenX, groundScreenY = M.PhysicsToScreen(0, -0.25, camX, camY)
    groundScreenX = groundScreenX * sx
    groundScreenY = groundScreenY * sy
    local groundW = C.MAP_HALF_WIDTH * 2 * C.PIXELS_PER_UNIT * sx
    local groundH = 0.5 * C.PIXELS_PER_UNIT * sy

    if S.imgGroundArea and S.imgGroundArea > 0 then
        -- 用区域地面纹理平铺
        local imgW, imgH = nvgImageSize(vg, S.imgGroundArea)
        local tileH = groundH * 1.2
        local tileW = tileH * (imgW / imgH)
        local startX = groundScreenX - groundW / 2
        for x = startX, startX + groundW, tileW do
            local paint = nvgImagePattern(vg, x, groundScreenY - tileH / 2, tileW, tileH, 0, S.imgGroundArea, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, x, groundScreenY - tileH / 2, tileW, tileH)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
        end
    else
        -- 石砖+地毯风格地面
        nvgBeginPath(vg)
        nvgRect(vg, groundScreenX - groundW / 2, groundScreenY - groundH / 2, groundW, groundH)
        local groundGrad = nvgLinearGradient(vg, 0, groundScreenY - groundH / 2, 0, groundScreenY + groundH / 2,
            nvgRGBA(80, 70, 60, 255), nvgRGBA(50, 45, 40, 255))
        nvgFillPaint(vg, groundGrad)
        nvgFill(vg)

        -- 顶部红色地毯条纹
        nvgBeginPath(vg)
        nvgRect(vg, groundScreenX - groundW / 2, groundScreenY - groundH / 2, groundW, groundH * 0.2)
        nvgFillColor(vg, nvgRGBA(140, 30, 30, 200))
        nvgFill(vg)
    end

    -- 浮空平台
    for _, p in ipairs(S.platforms) do
        local px, py = M.PhysicsToScreen(p.x, p.y, camX, camY)
        px = px * sx
        py = py * sy
        local pw = p.width * C.PIXELS_PER_UNIT * sx
        local ph = p.height * C.PIXELS_PER_UNIT * sy

        if S.imgPlatformArea and S.imgPlatformArea > 0 then
            -- 平台图片
            local paint = nvgImagePattern(vg, px - pw / 2, py - ph / 2, pw, ph, 0, S.imgPlatformArea, 1.0)
            nvgBeginPath(vg)
            nvgRect(vg, px - pw / 2, py - ph / 2, pw, ph)
            nvgFillPaint(vg, paint)
            nvgFill(vg)
        else
            -- 巴洛克金色风格平台
            nvgBeginPath(vg)
            nvgRoundedRect(vg, px - pw / 2, py - ph / 2, pw, ph, 4 * sx)
            local platGrad = nvgLinearGradient(vg, 0, py - ph / 2, 0, py + ph / 2,
                nvgRGBA(120, 100, 50, 255), nvgRGBA(80, 65, 35, 255))
            nvgFillPaint(vg, platGrad)
            nvgFill(vg)

            -- 金色边框
            nvgBeginPath(vg)
            nvgRoundedRect(vg, px - pw / 2, py - ph / 2, pw, ph, 4 * sx)
            nvgStrokeColor(vg, nvgRGBA(200, 170, 80, 200))
            nvgStrokeWidth(vg, 2 * sx)
            nvgStroke(vg)
        end
    end
end

-- ============================================================================
-- 投射物绘制
-- ============================================================================
function M.DrawProjectiles(width, height, camX, camY)
    local vg = S.nvg
    local sx = width / C.SCREEN_WIDTH
    local sy = height / C.SCREEN_HEIGHT

    for _, proj in ipairs(S.projectiles) do
        local px, py = M.PhysicsToScreen(proj.x, proj.y, camX, camY)
        px = px * sx
        py = py * sy
        local size = 8 * sx

        -- 冰晶弹 + 雾粒子
        nvgBeginPath(vg)
        nvgCircle(vg, px, py, size)
        nvgFillColor(vg, nvgRGBA(150, 220, 255, 220))
        nvgFill(vg)

        -- 外发光
        nvgBeginPath(vg)
        nvgCircle(vg, px, py, size * 1.8)
        nvgFillColor(vg, nvgRGBA(100, 180, 255, 60))
        nvgFill(vg)
    end
end

-- ============================================================================
-- 冰法师蓄力特效（11层视觉效果）
-- ============================================================================
function M.DrawChargeEffect(width, height, camX, camY)
    if S.playerNode == nil then return end
    local vg = S.nvg
    local pos = S.playerNode.position2D
    local screenX, screenY = M.PhysicsToScreen(pos.x, pos.y, camX, camY)
    local sx = width / C.SCREEN_WIDTH
    local sy = height / C.SCREEN_HEIGHT
    screenX = screenX * sx
    screenY = screenY * sy

    local progress = math.min(S.chargeTimer / C.CHARGE_MAX_DURATION, 1.0)
    local t = os.clock()
    local baseRadius = 40 * sx

    -- 1. 身体发光
    local glowAlpha = math.floor(80 + progress * 100)
    local glowR = baseRadius * (1.0 + progress * 0.5)
    nvgBeginPath(vg)
    nvgCircle(vg, screenX, screenY, glowR)
    local glowGrad = nvgRadialGradient(vg, screenX, screenY, glowR * 0.2, glowR,
        nvgRGBA(150, 220, 255, glowAlpha), nvgRGBA(80, 150, 255, 0))
    nvgFillPaint(vg, glowGrad)
    nvgFill(vg)

    -- 2. 霜环（旋转）
    local ringCount = 2 + math.floor(progress * 2)
    for i = 1, ringCount do
        local ringR = baseRadius * (0.8 + i * 0.3) * (0.8 + progress * 0.4)
        local rot = t * (1.5 + i * 0.5)
        nvgSave(vg)
        nvgTranslate(vg, screenX, screenY)
        nvgRotate(vg, rot)
        nvgBeginPath(vg)
        nvgEllipse(vg, 0, 0, ringR, ringR * 0.3)
        nvgStrokeColor(vg, nvgRGBA(180, 230, 255, math.floor(120 - i * 20)))
        nvgStrokeWidth(vg, (2 + progress) * sx)
        nvgStroke(vg)
        nvgRestore(vg)
    end

    -- 3. 浮游冰晶碎片
    local crystalCount = math.floor(4 + progress * 8)
    for i = 1, crystalCount do
        local angle = (i / crystalCount) * math.pi * 2 + t * 1.2
        local dist = baseRadius * (0.6 + progress * 0.8) + math.sin(t * 3 + i) * 5 * sx
        local cx = screenX + math.cos(angle) * dist
        local cy = screenY + math.sin(angle) * dist * 0.6
        local csize = (3 + progress * 4) * sx

        nvgSave(vg)
        nvgTranslate(vg, cx, cy)
        nvgRotate(vg, angle + t)
        nvgBeginPath(vg)
        nvgMoveTo(vg, 0, -csize)
        nvgLineTo(vg, csize * 0.5, 0)
        nvgLineTo(vg, 0, csize)
        nvgLineTo(vg, -csize * 0.5, 0)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(200, 240, 255, math.floor(150 + progress * 80)))
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- 4. 魔法阵
    if progress > 0.3 then
        local circleAlpha = math.floor((progress - 0.3) / 0.7 * 180)
        local circleR = baseRadius * 1.5 * progress
        nvgSave(vg)
        nvgTranslate(vg, screenX, screenY)
        nvgRotate(vg, -t * 0.8)
        nvgBeginPath(vg)
        nvgCircle(vg, 0, 0, circleR)
        nvgStrokeColor(vg, nvgRGBA(100, 200, 255, circleAlpha))
        nvgStrokeWidth(vg, 1.5 * sx)
        nvgStroke(vg)
        -- 六芒星
        for k = 0, 5 do
            local a = k * math.pi / 3
            nvgBeginPath(vg)
            nvgMoveTo(vg, math.cos(a) * circleR, math.sin(a) * circleR)
            nvgLineTo(vg, math.cos(a + math.pi * 2 / 3) * circleR, math.sin(a + math.pi * 2 / 3) * circleR)
            nvgStrokeColor(vg, nvgRGBA(120, 200, 255, math.floor(circleAlpha * 0.7)))
            nvgStrokeWidth(vg, 1 * sx)
            nvgStroke(vg)
        end
        nvgRestore(vg)
    end

    -- 5. 螺旋轨迹
    if progress > 0.2 then
        local trailAlpha = math.floor((progress - 0.2) / 0.8 * 200)
        nvgBeginPath(vg)
        local trailPoints = 20
        for i = 0, trailPoints do
            local frac = i / trailPoints
            local angle = frac * math.pi * 4 + t * 2
            local r = baseRadius * (0.3 + frac * progress)
            local tx = screenX + math.cos(angle) * r
            local ty = screenY + math.sin(angle) * r * 0.5
            if i == 0 then nvgMoveTo(vg, tx, ty) else nvgLineTo(vg, tx, ty) end
        end
        nvgStrokeColor(vg, nvgRGBA(150, 220, 255, trailAlpha))
        nvgStrokeWidth(vg, (1 + progress * 2) * sx)
        nvgStroke(vg)
    end

    -- 6. 汇聚线条
    if progress > 0.5 then
        local lineAlpha = math.floor((progress - 0.5) / 0.5 * 200)
        local lineCount = 8
        for i = 1, lineCount do
            local angle = (i / lineCount) * math.pi * 2 + t * 0.5
            local outerR = baseRadius * 2.5
            local innerR = baseRadius * 0.3
            nvgBeginPath(vg)
            nvgMoveTo(vg, screenX + math.cos(angle) * outerR, screenY + math.sin(angle) * outerR * 0.6)
            nvgLineTo(vg, screenX + math.cos(angle) * innerR, screenY + math.sin(angle) * innerR * 0.6)
            nvgStrokeColor(vg, nvgRGBA(180, 230, 255, lineAlpha))
            nvgStrokeWidth(vg, (1 + progress) * sx)
            nvgStroke(vg)
        end
    end

    -- 7. 闪电弧
    if progress > 0.6 then
        local arcAlpha = math.floor((progress - 0.6) / 0.4 * 220)
        local arcCount = math.floor(2 + progress * 3)
        for i = 1, arcCount do
            local startAngle = (i / arcCount) * math.pi * 2 + t * 3
            local ar = baseRadius * (0.8 + progress * 0.5)
            nvgBeginPath(vg)
            local px1 = screenX + math.cos(startAngle) * ar
            local py1 = screenY + math.sin(startAngle) * ar * 0.5
            nvgMoveTo(vg, px1, py1)
            local segs = 4
            for s = 1, segs do
                local frac2 = s / segs
                local midAngle = startAngle + frac2 * 0.8
                local mr = ar * (1 - frac2 * 0.7)
                local jitter = (math.random() - 0.5) * 10 * sx
                nvgLineTo(vg, screenX + math.cos(midAngle) * mr + jitter, screenY + math.sin(midAngle) * mr * 0.5 + jitter)
            end
            nvgStrokeColor(vg, nvgRGBA(200, 240, 255, arcAlpha))
            nvgStrokeWidth(vg, (1.5 + progress) * sx)
            nvgStroke(vg)
        end
    end

    -- 8. 地面霜花
    local frostY = screenY + baseRadius * 0.5
    local frostW = baseRadius * (1 + progress * 2)
    nvgBeginPath(vg)
    nvgRect(vg, screenX - frostW, frostY, frostW * 2, 4 * sy)
    nvgFillColor(vg, nvgRGBA(200, 240, 255, math.floor(60 + progress * 80)))
    nvgFill(vg)

    -- 9. 上升雾气
    local mistCount = math.floor(3 + progress * 5)
    for i = 1, mistCount do
        local mx = screenX + (math.random() - 0.5) * frostW * 2
        local myBase = frostY
        local rise = (t * 30 + i * 50) % (baseRadius * 2)
        local my = myBase - rise
        local mistAlpha = math.floor((1 - rise / (baseRadius * 2)) * 80 * progress)
        nvgBeginPath(vg)
        nvgCircle(vg, mx, my, (3 + progress * 3) * sx)
        nvgFillColor(vg, nvgRGBA(180, 220, 255, mistAlpha))
        nvgFill(vg)
    end

    -- 10. 脉冲波
    if progress > 0.4 then
        local pulsePhase = (t * 2) % 1.0
        local pulseR = baseRadius * (0.5 + pulsePhase * 2) * progress
        local pulseAlpha = math.floor((1 - pulsePhase) * 150 * (progress - 0.4) / 0.6)
        nvgBeginPath(vg)
        nvgCircle(vg, screenX, screenY, pulseR)
        nvgStrokeColor(vg, nvgRGBA(150, 220, 255, pulseAlpha))
        nvgStrokeWidth(vg, (2 + progress * 2) * sx)
        nvgStroke(vg)
    end

    -- 11. 进度条（底部）
    local barW = 60 * sx
    local barH = 6 * sy
    local barX = screenX - barW / 2
    local barY = screenY + baseRadius * 1.2
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 3 * sx)
    nvgFillColor(vg, nvgRGBA(20, 30, 50, 180))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW * progress, barH, 3 * sx)
    local barGrad = nvgLinearGradient(vg, barX, barY, barX + barW, barY,
        nvgRGBA(100, 180, 255, 255), nvgRGBA(200, 240, 255, 255))
    nvgFillPaint(vg, barGrad)
    nvgFill(vg)
end

-- ============================================================================
-- 角色2蓄力特效（红蝶爆发，7层效果）
-- ============================================================================
function M.DrawChargeEffectChar2(width, height, camX, camY)
    if S.playerNode == nil then return end
    local vg = S.nvg
    local pos = S.playerNode.position2D
    local screenX, screenY = M.PhysicsToScreen(pos.x, pos.y, camX, camY)
    local sx = width / C.SCREEN_WIDTH
    local sy = height / C.SCREEN_HEIGHT
    screenX = screenX * sx
    screenY = screenY * sy

    local progress = math.min(S.chargeTimer / C.CHARGE_MAX_DURATION, 1.0)
    local t = os.clock()
    local baseRadius = 40 * sx

    -- 1. 身体发光（暗红）
    local glowAlpha = math.floor(60 + progress * 120)
    local glowR = baseRadius * (1.0 + progress * 0.6)
    nvgBeginPath(vg)
    nvgCircle(vg, screenX, screenY, glowR)
    local glowGrad = nvgRadialGradient(vg, screenX, screenY, glowR * 0.2, glowR,
        nvgRGBA(200, 50, 80, glowAlpha), nvgRGBA(100, 20, 40, 0))
    nvgFillPaint(vg, glowGrad)
    nvgFill(vg)

    -- 2. 能量环
    local ringR = baseRadius * (0.8 + progress * 0.6)
    nvgBeginPath(vg)
    nvgCircle(vg, screenX, screenY, ringR)
    nvgStrokeColor(vg, nvgRGBA(255, 80, 120, math.floor(100 + progress * 100)))
    nvgStrokeWidth(vg, (2 + progress * 2) * sx)
    nvgStroke(vg)

    -- 3. 飞舞蝴蝶
    local butterflyCount = math.floor(3 + progress * 5)
    for i = 1, butterflyCount do
        local angle = (i / butterflyCount) * math.pi * 2 + t * 1.5
        local dist = baseRadius * (0.5 + progress * 0.8) + math.sin(t * 2 + i * 1.7) * 8 * sx
        local bx = screenX + math.cos(angle) * dist
        local by = screenY + math.sin(angle) * dist * 0.6 + math.sin(t * 4 + i) * 3 * sy
        local bsize = (4 + progress * 3) * sx

        -- 简单蝴蝶形状（两个翅膀三角）
        nvgSave(vg)
        nvgTranslate(vg, bx, by)
        nvgRotate(vg, math.sin(t * 8 + i) * 0.3)
        nvgBeginPath(vg)
        nvgMoveTo(vg, 0, 0)
        nvgLineTo(vg, -bsize, -bsize * 0.7)
        nvgLineTo(vg, -bsize * 0.3, 0)
        nvgLineTo(vg, -bsize, bsize * 0.7)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(220, 40, 80, math.floor(150 + progress * 80)))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, 0, 0)
        nvgLineTo(vg, bsize, -bsize * 0.7)
        nvgLineTo(vg, bsize * 0.3, 0)
        nvgLineTo(vg, bsize, bsize * 0.7)
        nvgClosePath(vg)
        nvgFillColor(vg, nvgRGBA(180, 30, 60, math.floor(150 + progress * 80)))
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- 4. 粒子散射
    local particleCount = math.floor(6 + progress * 10)
    for i = 1, particleCount do
        local angle2 = (i / particleCount) * math.pi * 2 + t * 2
        local pdist = baseRadius * progress + math.sin(t * 5 + i) * 5 * sx
        local ppx = screenX + math.cos(angle2) * pdist
        local ppy = screenY + math.sin(angle2) * pdist * 0.5
        nvgBeginPath(vg)
        nvgCircle(vg, ppx, ppy, (1.5 + progress * 2) * sx)
        nvgFillColor(vg, nvgRGBA(255, 100, 150, math.floor(100 + progress * 100)))
        nvgFill(vg)
    end

    -- 5. 螺旋
    if progress > 0.3 then
        nvgBeginPath(vg)
        local spiralPts = 16
        for i = 0, spiralPts do
            local frac = i / spiralPts
            local sa = frac * math.pi * 3 + t * 2.5
            local sr = baseRadius * (0.2 + frac * progress)
            local spx = screenX + math.cos(sa) * sr
            local spy = screenY + math.sin(sa) * sr * 0.5
            if i == 0 then nvgMoveTo(vg, spx, spy) else nvgLineTo(vg, spx, spy) end
        end
        nvgStrokeColor(vg, nvgRGBA(255, 80, 120, math.floor((progress - 0.3) / 0.7 * 180)))
        nvgStrokeWidth(vg, (1.5 + progress) * sx)
        nvgStroke(vg)
    end

    -- 6. 脉冲
    if progress > 0.4 then
        local pulsePhase = (t * 2.5) % 1.0
        local pulseR2 = baseRadius * (0.3 + pulsePhase * 1.5) * progress
        local pulseAlpha = math.floor((1 - pulsePhase) * 150 * (progress - 0.4) / 0.6)
        nvgBeginPath(vg)
        nvgCircle(vg, screenX, screenY, pulseR2)
        nvgStrokeColor(vg, nvgRGBA(255, 60, 100, pulseAlpha))
        nvgStrokeWidth(vg, (2 + progress * 2) * sx)
        nvgStroke(vg)
    end

    -- 7. 进度条
    local barW = 60 * sx
    local barH = 6 * sy
    local barX = screenX - barW / 2
    local barY = screenY + baseRadius * 1.2
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, 3 * sx)
    nvgFillColor(vg, nvgRGBA(30, 10, 20, 180))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW * progress, barH, 3 * sx)
    local barGrad = nvgLinearGradient(vg, barX, barY, barX + barW, barY,
        nvgRGBA(200, 40, 80, 255), nvgRGBA(255, 100, 150, 255))
    nvgFillPaint(vg, barGrad)
    nvgFill(vg)
end

-- ============================================================================
-- 治愈特效
-- ============================================================================
function M.DrawHealEffect(width, height, camX, camY)
    if S.playerNode == nil then return end
    local vg = S.nvg
    local pos = S.playerNode.position2D
    local screenX, screenY = M.PhysicsToScreen(pos.x, pos.y, camX, camY)
    local sx = width / C.SCREEN_WIDTH
    local sy = height / C.SCREEN_HEIGHT
    screenX = screenX * sx
    screenY = screenY * sy

    local progress = S.healTimer / C.HEAL_DURATION
    local t = os.clock()
    local baseRadius = 45 * sx

    -- 双色方案：角色1绿色系，角色2红紫系
    local isChar2 = (S.currentCharacter == 2)
    local r1, g1, b1 = 80, 255, 150   -- 主色
    local r2, g2, b2 = 50, 200, 100   -- 辅色
    if isChar2 then
        r1, g1, b1 = 255, 80, 150
        r2, g2, b2 = 200, 50, 120
    end

    -- 1. 身体发光
    local glowAlpha = math.floor(60 + progress * 100)
    local glowR = baseRadius * (0.8 + progress * 0.5)
    nvgBeginPath(vg)
    nvgCircle(vg, screenX, screenY, glowR)
    local glowGrad = nvgRadialGradient(vg, screenX, screenY, glowR * 0.1, glowR,
        nvgRGBA(r1, g1, b1, glowAlpha), nvgRGBA(r2, g2, b2, 0))
    nvgFillPaint(vg, glowGrad)
    nvgFill(vg)

    -- 2. 扩展圆环
    local ringCount = 2
    for i = 1, ringCount do
        local phase = (t * 1.5 + i * 0.5) % 1.0
        local ringR = baseRadius * (0.5 + phase * 1.2)
        local ringAlpha = math.floor((1 - phase) * 150 * progress)
        nvgBeginPath(vg)
        nvgCircle(vg, screenX, screenY, ringR)
        nvgStrokeColor(vg, nvgRGBA(r1, g1, b1, ringAlpha))
        nvgStrokeWidth(vg, (2 + progress) * sx)
        nvgStroke(vg)
    end

    -- 3. 魔法阵
    local circleR = baseRadius * 1.2 * progress
    nvgSave(vg)
    nvgTranslate(vg, screenX, screenY)
    nvgRotate(vg, t * 0.6)
    nvgBeginPath(vg)
    nvgCircle(vg, 0, 0, circleR)
    nvgStrokeColor(vg, nvgRGBA(r1, g1, b1, math.floor(100 * progress)))
    nvgStrokeWidth(vg, 1.5 * sx)
    nvgStroke(vg)
    nvgRestore(vg)

    -- 4. 上升粒子
    local particleCount = math.floor(5 + progress * 8)
    for i = 1, particleCount do
        local angle = (i / particleCount) * math.pi * 2
        local rise = ((t * 40 + i * 30) % 80) * sy
        local dist2 = baseRadius * 0.3 + math.sin(t + i) * 10 * sx
        local ppx = screenX + math.cos(angle) * dist2
        local ppy = screenY - rise
        local pAlpha = math.floor((1 - rise / (80 * sy)) * 180 * progress)
        nvgBeginPath(vg)
        nvgCircle(vg, ppx, ppy, (2 + progress * 2) * sx)
        nvgFillColor(vg, nvgRGBA(r1, g1, b1, pAlpha))
        nvgFill(vg)
    end

    -- 5. 符文/叶片
    local runeCount = 4
    for i = 1, runeCount do
        local ra = (i / runeCount) * math.pi * 2 + t * 0.8
        local rd = baseRadius * 0.7
        local rx = screenX + math.cos(ra) * rd
        local ry = screenY + math.sin(ra) * rd * 0.5
        local rsize = (5 + progress * 3) * sx

        nvgSave(vg)
        nvgTranslate(vg, rx, ry)
        nvgRotate(vg, ra + t)
        nvgBeginPath(vg)
        nvgMoveTo(vg, 0, -rsize)
        nvgQuadTo(vg, rsize * 0.8, 0, 0, rsize)
        nvgQuadTo(vg, -rsize * 0.8, 0, 0, -rsize)
        nvgFillColor(vg, nvgRGBA(r1, g1, b1, math.floor(120 * progress)))
        nvgFill(vg)
        nvgRestore(vg)
    end

    -- 6. 螺旋光带
    if progress > 0.3 then
        nvgBeginPath(vg)
        local pts = 20
        for i = 0, pts do
            local frac = i / pts
            local sa = frac * math.pi * 3 + t * 2
            local sr = baseRadius * frac * progress
            local spx = screenX + math.cos(sa) * sr
            local spy = screenY + math.sin(sa) * sr * 0.4
            if i == 0 then nvgMoveTo(vg, spx, spy) else nvgLineTo(vg, spx, spy) end
        end
        nvgStrokeColor(vg, nvgRGBA(r1, g1, b1, math.floor((progress - 0.3) / 0.7 * 150)))
        nvgStrokeWidth(vg, (1.5 + progress * 2) * sx)
        nvgStroke(vg)
    end

    -- 7. 治愈光柱
    if progress > 0.5 then
        local pillarAlpha = math.floor((progress - 0.5) / 0.5 * 120)
        local pillarW = 20 * sx * progress
        local pillarH = baseRadius * 2
        nvgBeginPath(vg)
        nvgRect(vg, screenX - pillarW / 2, screenY - pillarH, pillarW, pillarH)
        local pillarGrad = nvgLinearGradient(vg, screenX, screenY - pillarH, screenX, screenY,
            nvgRGBA(r1, g1, b1, 0), nvgRGBA(r1, g1, b1, pillarAlpha))
        nvgFillPaint(vg, pillarGrad)
        nvgFill(vg)
    end

    -- 8. 十字闪光
    if progress > 0.7 then
        local flashAlpha = math.floor((progress - 0.7) / 0.3 * 200)
        local flashSize = baseRadius * 0.3 * ((progress - 0.7) / 0.3)
        nvgBeginPath(vg)
        nvgRect(vg, screenX - flashSize, screenY - 1 * sy, flashSize * 2, 2 * sy)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, flashAlpha))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRect(vg, screenX - 1 * sx, screenY - flashSize, 2 * sx, flashSize * 2)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, flashAlpha))
        nvgFill(vg)
    end
end

-- ============================================================================
-- 地面冰晶群
-- ============================================================================
function M.DrawIceCrystals(width, height, camX, camY)
    local vg = S.nvg
    local sx = width / C.SCREEN_WIDTH
    local sy = height / C.SCREEN_HEIGHT
    local t = os.clock()

    for _, group in ipairs(S.iceCrystals) do
        local lifeRatio = 1 - (group.life / group.maxLife)
        local fadeAlpha = lifeRatio > 0.7 and math.floor((1 - (lifeRatio - 0.7) / 0.3) * 255) or 255

        -- 地面裂痕
        local crackScreenX, crackScreenY = M.PhysicsToScreen(group.x, group.groundY, camX, camY)
        crackScreenX = crackScreenX * sx
        crackScreenY = crackScreenY * sy
        local crackW = group.radius * 2 * C.PIXELS_PER_UNIT * sx
        nvgBeginPath(vg)
        nvgRect(vg, crackScreenX - crackW / 2, crackScreenY - 2 * sy, crackW, 4 * sy)
        nvgFillColor(vg, nvgRGBA(100, 180, 255, math.floor(fadeAlpha * 0.5)))
        nvgFill(vg)

        -- 冰晶柱
        for _, crystal in ipairs(group.crystals) do
            local crystalScreenX, crystalScreenY = M.PhysicsToScreen(crystal.x, group.groundY, camX, camY)
            crystalScreenX = crystalScreenX * sx
            crystalScreenY = crystalScreenY * sy
            local h = crystal.height * C.PIXELS_PER_UNIT * sy
            local w = h * 0.25

            -- 主体（三角柱形）
            nvgBeginPath(vg)
            nvgMoveTo(vg, crystalScreenX, crystalScreenY - h)
            nvgLineTo(vg, crystalScreenX + w / 2, crystalScreenY)
            nvgLineTo(vg, crystalScreenX - w / 2, crystalScreenY)
            nvgClosePath(vg)
            local crystGrad = nvgLinearGradient(vg, crystalScreenX, crystalScreenY - h, crystalScreenX, crystalScreenY,
                nvgRGBA(200, 240, 255, fadeAlpha), nvgRGBA(100, 180, 255, math.floor(fadeAlpha * 0.7)))
            nvgFillPaint(vg, crystGrad)
            nvgFill(vg)

            -- 高光
            nvgBeginPath(vg)
            nvgMoveTo(vg, crystalScreenX - w * 0.1, crystalScreenY - h * 0.7)
            nvgLineTo(vg, crystalScreenX - w * 0.05, crystalScreenY - h * 0.3)
            nvgStrokeColor(vg, nvgRGBA(255, 255, 255, math.floor(fadeAlpha * 0.6)))
            nvgStrokeWidth(vg, 1.5 * sx)
            nvgStroke(vg)
        end

        -- 爆裂粒子
        if lifeRatio < 0.3 then
            local burstAlpha = math.floor((1 - lifeRatio / 0.3) * 200)
            local burstCount = 6
            for i = 1, burstCount do
                local angle = (i / burstCount) * math.pi * 2 + group.x
                local dist = group.radius * C.PIXELS_PER_UNIT * sx * (lifeRatio / 0.3)
                local bpx = crackScreenX + math.cos(angle) * dist
                local bpy = crackScreenY + math.sin(angle) * dist * 0.3
                nvgBeginPath(vg)
                nvgCircle(vg, bpx, bpy, (2 + lifeRatio * 3) * sx)
                nvgFillColor(vg, nvgRGBA(180, 230, 255, burstAlpha))
                nvgFill(vg)
            end
        end

        -- 霜雾
        local mistAlpha = math.floor(fadeAlpha * 0.3)
        nvgBeginPath(vg)
        nvgEllipse(vg, crackScreenX, crackScreenY, crackW * 0.6, 8 * sy)
        nvgFillColor(vg, nvgRGBA(150, 220, 255, mistAlpha))
        nvgFill(vg)

        -- 能量环
        local ringPhase = (t * 1.5 + group.x) % 1.0
        local ringR = group.radius * C.PIXELS_PER_UNIT * sx * (0.5 + ringPhase * 0.5)
        local ringAlpha = math.floor((1 - ringPhase) * fadeAlpha * 0.5)
        nvgBeginPath(vg)
        nvgEllipse(vg, crackScreenX, crackScreenY, ringR, ringR * 0.3)
        nvgStrokeColor(vg, nvgRGBA(150, 220, 255, ringAlpha))
        nvgStrokeWidth(vg, 2 + group.power * 2)
        nvgStroke(vg)
    end
end

-- ============================================================================
-- 绘制玩家（序列帧动画）
-- ============================================================================
function M.DrawPlayer(width, height, camX, camY)
    if S.playerNode == nil then return end
    local vg = S.nvg

    local pos = S.playerNode.position2D
    local screenX, screenY = M.PhysicsToScreen(pos.x, pos.y, camX, camY)

    local sx = width / C.SCREEN_WIDTH
    local sy = height / C.SCREEN_HEIGHT
    screenX = screenX * sx
    screenY = screenY * sy

    -- 玩家渲染尺寸
    local animCropConfig = S.GetCurrentAnimCropConfig()
    local animScale = (animCropConfig[S.currentAnim] and animCropConfig[S.currentAnim].scale) or 5.5
    local playerDrawSize = C.PLAYER_RADIUS * animScale * C.PIXELS_PER_UNIT * sx

    -- 选择当前序列帧图片
    local img = S.imgIdle
    if S.currentCharacter == 2 then
        img = S.img2Idle
        if S.currentAnim == C.ANIM_RUN then img = S.img2Run
        elseif S.currentAnim == C.ANIM_JUMP then img = S.img2Jump
        elseif S.currentAnim == C.ANIM_ATTACK then img = S.img2Attack
        elseif S.currentAnim == C.ANIM_BLOCK then img = S.img2Block
        elseif S.currentAnim == C.ANIM_CHARGE then img = S.img2Burst
        elseif S.currentAnim == C.ANIM_HEAL then img = S.img2Heal
        elseif S.currentAnim == C.ANIM_CROUCH then img = S.img2Crouch
        elseif S.currentAnim == C.ANIM_CROUCH_WALK then img = S.img2CrouchWalk
        elseif S.currentAnim == C.ANIM_HIT then img = S.img2Hit
        end
    else
        if S.currentAnim == C.ANIM_RUN then img = S.imgRun
        elseif S.currentAnim == C.ANIM_JUMP then img = S.imgJump
        elseif S.currentAnim == C.ANIM_ATTACK then img = S.imgAttack
        elseif S.currentAnim == C.ANIM_BLOCK then img = S.imgBlock
        elseif S.currentAnim == C.ANIM_CHARGE then img = S.imgCharge
        elseif S.currentAnim == C.ANIM_HEAL then img = S.imgHeal
        elseif S.currentAnim == C.ANIM_CROUCH then img = S.imgCrouch
        elseif S.currentAnim == C.ANIM_CROUCH_WALK then img = S.imgCrouch
        elseif S.currentAnim == C.ANIM_HIT then img = S.imgHit
        end
    end

    local frame = S.animFrame

    -- 蹲下帧映射
    if S.currentAnim == C.ANIM_CROUCH then
        local map = (S.currentCharacter == 2) and C.CROUCH_FRAME_MAP_2 or C.CROUCH_FRAME_MAP_1
        local idx = math.max(1, math.min(S.animFrame, #map))
        frame = map[idx]
    end

    -- 角色1蹲走帧
    if S.currentAnim == C.ANIM_CROUCH_WALK and S.currentCharacter == 1 then
        local crouchWalkFrames = { 6, 2 }
        frame = crouchWalkFrames[(S.animFrame % 2) + 1]
    end

    -- 光翼特效
    M.DrawWingsEffect(screenX, screenY, playerDrawSize)

    -- 序列帧绘制
    if img ~= nil and img > 0 and S.imgWidth > 0 then
        M.DrawSpriteFrame(img, frame, screenX, screenY, playerDrawSize, not S.facingRight)
    else
        -- fallback 占位圆
        nvgBeginPath(vg)
        nvgCircle(vg, screenX, screenY, playerDrawSize / 2)
        nvgFillColor(vg, nvgRGBA(100, 180, 255, 255))
        nvgFill(vg)

        nvgBeginPath(vg)
        local dirX = S.facingRight and (playerDrawSize * 0.4) or (-playerDrawSize * 0.4)
        nvgCircle(vg, screenX + dirX, screenY, playerDrawSize * 0.15)
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgFill(vg)
    end
end

-- ============================================================================
-- 光翼特效
-- ============================================================================
function M.DrawWingsEffect(cx, cy, playerSize)
    local showWings = S.isHanging
    local showShatter = S.wingShatterTimer > 0

    if not showWings and not showShatter then return end
    local vg = S.nvg

    nvgSave(vg)
    nvgGlobalAlpha(vg, 0.85)

    local dirSign = S.facingRight and -1 or 1
    local baseX = cx + dirSign * playerSize * 0.15
    local baseY = cy - playerSize * 0.25

    local feathers = {
        { angle = -30, lenScale = 0.85, widScale = 0.8, dist = 0.2 },
        { angle =   5, lenScale = 1.0,  widScale = 0.85, dist = 0.25 },
        { angle =  40, lenScale = 0.7,  widScale = 0.7, dist = 0.2 },
    }

    local baseLen = playerSize * 0.4
    local baseWid = playerSize * 0.08
    local isChar2 = (S.currentCharacter == 2)

    if showWings then
        local pulse = 1.0 + math.sin(os.clock() * 6.0) * 0.06
        local floatY = math.sin(os.clock() * 3.0) * 1.0
        baseY = baseY + floatY

        for _, f in ipairs(feathers) do
            local len = baseLen * f.lenScale * pulse
            local wid = baseWid * f.widScale * pulse
            local rad = math.rad(f.angle)
            local fcx = baseX + dirSign * math.cos(rad) * playerSize * f.dist
            local fcy = baseY + math.sin(rad) * playerSize * f.dist

            local cosA = math.cos(rad) * dirSign
            local sinA = math.sin(rad)
            local tipX = fcx + cosA * len * 0.6
            local tipY = fcy + sinA * len * 0.6
            local tailX = fcx - cosA * len * 0.4
            local tailY = fcy - sinA * len * 0.4
            local sideX1 = fcx + (-sinA) * wid
            local sideY1 = fcy + cosA * wid * dirSign
            local sideX2 = fcx - (-sinA) * wid
            local sideY2 = fcy - cosA * wid * dirSign

            nvgBeginPath(vg)
            nvgMoveTo(vg, tipX, tipY)
            nvgLineTo(vg, sideX1, sideY1)
            nvgLineTo(vg, tailX, tailY)
            nvgLineTo(vg, sideX2, sideY2)
            nvgClosePath(vg)
            if isChar2 then
                local grad = nvgLinearGradient(vg, tailX, tailY, tipX, tipY,
                    nvgRGBA(40, 5, 15, 255), nvgRGBA(220, 40, 40, 255))
                nvgFillPaint(vg, grad)
            else
                local grad = nvgLinearGradient(vg, tailX, tailY, tipX, tipY,
                    nvgRGBA(255, 140, 20, 255), nvgRGBA(255, 230, 50, 255))
                nvgFillPaint(vg, grad)
            end
            nvgFill(vg)
        end
    else
        -- 破碎动画
        local progress = 1.0 - (S.wingShatterTimer / C.WING_SHATTER_DURATION)
        local fadeAlpha = math.floor((1.0 - progress) * 255)
        local scatter = progress * playerSize * 0.6

        for _, f in ipairs(feathers) do
            local shrink = 1.0 - progress * 0.7
            local len = baseLen * f.lenScale * shrink
            local wid = baseWid * f.widScale * shrink
            local rad = math.rad(f.angle)
            local scatterX = dirSign * math.cos(rad) * scatter
            local scatterY = math.sin(rad) * scatter + progress * playerSize * 0.2
            local fcx = baseX + dirSign * math.cos(rad) * playerSize * f.dist + scatterX
            local fcy = baseY + math.sin(rad) * playerSize * f.dist + scatterY

            local cosA = math.cos(rad) * dirSign
            local sinA = math.sin(rad)
            local tipX = fcx + cosA * len * 0.6
            local tipY = fcy + sinA * len * 0.6
            local tailX = fcx - cosA * len * 0.4
            local tailY = fcy - sinA * len * 0.4
            local sideX1 = fcx + (-sinA) * wid
            local sideY1 = fcy + cosA * wid * dirSign
            local sideX2 = fcx - (-sinA) * wid
            local sideY2 = fcy - cosA * wid * dirSign

            nvgBeginPath(vg)
            nvgMoveTo(vg, tipX, tipY)
            nvgLineTo(vg, sideX1, sideY1)
            nvgLineTo(vg, tailX, tailY)
            nvgLineTo(vg, sideX2, sideY2)
            nvgClosePath(vg)
            if isChar2 then
                local grad = nvgLinearGradient(vg, tailX, tailY, tipX, tipY,
                    nvgRGBA(40, 5, 15, fadeAlpha), nvgRGBA(220, 40, 40, fadeAlpha))
                nvgFillPaint(vg, grad)
            else
                local grad = nvgLinearGradient(vg, tailX, tailY, tipX, tipY,
                    nvgRGBA(255, 140, 20, fadeAlpha), nvgRGBA(255, 230, 50, fadeAlpha))
                nvgFillPaint(vg, grad)
            end
            nvgFill(vg)
        end
    end

    nvgRestore(vg)
end

-- ============================================================================
-- 序列帧绘制
-- ============================================================================
function M.DrawSpriteFrame(img, frame, cx, cy, size, flipH)
    local vg = S.nvg
    local animCropConfig = S.GetCurrentAnimCropConfig()
    local crop = animCropConfig[S.currentAnim] or { cropW = 1.0, cropH = 1.0, cropOffX = 0.0, cropOffY = 0.0, offsetX = 0.0, offsetY = 0.6 }
    local cols = crop.cols or C.SPRITE_COLS
    local rows = crop.rows or C.SPRITE_ROWS

    local col = frame % cols
    local row = math.floor(frame / cols)

    local actualW, actualH = nvgImageSize(vg, img)

    local frameW = actualW / cols
    local frameH = actualH / rows

    local srcW = frameW * crop.cropW
    local srcH = frameH * crop.cropH
    local srcOffX = frameW * crop.cropOffX
    local srcOffY = frameH * crop.cropOffY

    local drawW = size
    local drawH = size * (srcH / srcW)
    local oX = crop.offsetX or 0.0
    local oY = crop.offsetY or 0.6
    local drawX = cx - drawW / 2 + oX * drawW
    local drawY = cy - drawH * oY

    nvgSave(vg)

    if flipH then
        nvgTranslate(vg, cx, 0)
        nvgScale(vg, -1, 1)
        nvgTranslate(vg, -cx, 0)
    end

    local patternW = drawW * (actualW / srcW)
    local patternH = drawH * (actualH / srcH)
    local cropLeftInFrame = (frameW - srcW) / 2 + srcOffX
    local cropTopInFrame = (frameH - srcH) / 2 + srcOffY
    local patternX = drawX - (col * frameW + cropLeftInFrame) * (patternW / actualW)
    local patternY = drawY - (row * frameH + cropTopInFrame) * (patternH / actualH)

    local paint = nvgImagePattern(vg, patternX, patternY, patternW, patternH, 0, img, 1.0)

    nvgBeginPath(vg)
    nvgRect(vg, drawX, drawY, drawW, drawH)
    nvgFillPaint(vg, paint)
    nvgFill(vg)

    nvgRestore(vg)
end

-- ============================================================================
-- HP/MP 血条
-- ============================================================================
function M.DrawHPMPBars(width, height)
    local vg = S.nvg
    local sx = width / C.SCREEN_WIDTH
    local sy = height / C.SCREEN_HEIGHT

    -- 圆形头像
    local avatarSize = 44 * sx
    local avatarX = 14 * sx
    local avatarY = 14 * sy
    local avatarCX = avatarX + avatarSize / 2
    local avatarCY = avatarY + avatarSize / 2
    local avatarR = avatarSize / 2

    local avatarImg = (S.currentCharacter == 1) and S.imgAvatar1 or S.imgAvatar2
    if avatarImg and avatarImg > 0 then
        nvgSave(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, avatarCX, avatarCY, avatarR)
        local imgPaint = nvgImagePattern(vg, avatarX, avatarY, avatarSize, avatarSize, 0, avatarImg, 1.0)
        nvgFillPaint(vg, imgPaint)
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, avatarCX, avatarCY, avatarR)
        nvgStrokeColor(vg, nvgRGBA(220, 200, 120, 220))
        nvgStrokeWidth(vg, 2.5 * sx)
        nvgStroke(vg)
        nvgRestore(vg)
    end

    -- HP/MP 条
    local barX = avatarX + avatarSize + 8 * sx
    local barY = avatarY + 2 * sy
    local barW = 180 * sx
    local barH = 16 * sy
    local gap = 6 * sy
    local cornerR = 4 * sx

    -- HP 条
    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, cornerR)
    nvgFillColor(vg, nvgRGBA(30, 30, 30, 200))
    nvgFill(vg)

    local hpRatio = S.playerHP / S.playerMaxHP
    if hpRatio > 0 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, barY, barW * hpRatio, barH, cornerR)
        local hpGrad = nvgLinearGradient(vg, barX, barY, barX, barY + barH,
            nvgRGBA(220, 50, 50, 255), nvgRGBA(160, 20, 20, 255))
        nvgFillPaint(vg, hpGrad)
        nvgFill(vg)
    end

    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, barY, barW, barH, cornerR)
    nvgStrokeColor(vg, nvgRGBA(200, 200, 200, 150))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 13 * sx)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(vg, barX + barW / 2, barY + barH / 2, string.format("HP %d/%d", math.floor(S.playerHP), math.floor(S.playerMaxHP)))

    -- MP 条
    local mpY = barY + barH + gap

    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, mpY, barW, barH, cornerR)
    nvgFillColor(vg, nvgRGBA(30, 30, 30, 200))
    nvgFill(vg)

    local mpRatio = S.playerMP / S.playerMaxMP
    if mpRatio > 0 then
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, mpY, barW * mpRatio, barH, cornerR)
        local mpGrad = nvgLinearGradient(vg, barX, mpY, barX, mpY + barH,
            nvgRGBA(60, 130, 255, 255), nvgRGBA(30, 80, 200, 255))
        nvgFillPaint(vg, mpGrad)
        nvgFill(vg)
    end

    nvgBeginPath(vg)
    nvgRoundedRect(vg, barX, mpY, barW, barH, cornerR)
    nvgStrokeColor(vg, nvgRGBA(200, 200, 200, 150))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    nvgFontSize(vg, 13 * sx)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(vg, barX + barW / 2, mpY + barH / 2, string.format("MP %d/%d", math.floor(S.playerMP), math.floor(S.playerMaxMP)))

    -- 技能图标
    local iconSize = 36 * sx
    local iconY = mpY + barH + 10 * sy
    local iconGap = 8 * sx
    local iconQ, iconE
    if S.currentCharacter == 2 then
        iconQ = S.iconChar2Q
        iconE = S.iconChar2E
    else
        iconQ = S.iconChar1Q
        iconE = S.iconChar1E
    end

    -- Q 技能图标
    local iconQX = barX
    if iconQ and iconQ > 0 then
        local imgPat = nvgImagePattern(vg, iconQX, iconY, iconSize, iconSize, 0, iconQ, 1.0)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, iconQX, iconY, iconSize, iconSize, 4 * sx)
        nvgFillPaint(vg, imgPat)
        nvgFill(vg)
    end
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 10 * sx)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgText(vg, iconQX + iconSize / 2, iconY + iconSize + 2 * sy, "Q")

    -- E 技能图标
    local iconEX = iconQX + iconSize + iconGap
    if iconE and iconE > 0 then
        local imgPat = nvgImagePattern(vg, iconEX, iconY, iconSize, iconSize, 0, iconE, 1.0)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, iconEX, iconY, iconSize, iconSize, 4 * sx)
        nvgFillPaint(vg, imgPat)
        nvgFill(vg)

        -- CD遮罩
        if S.healCooldownTimer > 0 then
            nvgBeginPath(vg)
            nvgRoundedRect(vg, iconEX, iconY, iconSize, iconSize, 4 * sx)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 160))
            nvgFill(vg)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 14 * sx)
            nvgFillColor(vg, nvgRGBA(255, 255, 255, 240))
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgText(vg, iconEX + iconSize / 2, iconY + iconSize / 2, string.format("%.1f", S.healCooldownTimer))
        end
    end
    nvgFontSize(vg, 10 * sx)
    nvgFillColor(vg, nvgRGBA(255, 255, 255, 200))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgText(vg, iconEX + iconSize / 2, iconY + iconSize + 2 * sy, "E")

    -- 图标边框
    nvgBeginPath(vg)
    nvgRoundedRect(vg, iconQX, iconY, iconSize, iconSize, 4 * sx)
    nvgStrokeColor(vg, nvgRGBA(180, 180, 200, 150))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, iconEX, iconY, iconSize, iconSize, 4 * sx)
    nvgStrokeColor(vg, nvgRGBA(180, 180, 200, 150))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 吸血buff指示器
    if S.currentCharacter == 2 and S.lifestealBuffTimer > 0 then
        local buffY = iconY + iconSize + 16 * sy
        local buffW = 80 * sx
        local buffH = 14 * sy
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, buffY, buffW, buffH, 3 * sx)
        nvgFillColor(vg, nvgRGBA(80, 0, 40, 180))
        nvgFill(vg)
        local buffRatio = S.lifestealBuffTimer / S.LIFESTEAL_DURATION
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, buffY, buffW * buffRatio, buffH, 3 * sx)
        local buffGrad = nvgLinearGradient(vg, barX, buffY, barX + buffW, buffY,
            nvgRGBA(220, 50, 150, 220), nvgRGBA(180, 30, 100, 220))
        nvgFillPaint(vg, buffGrad)
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, barX, buffY, buffW, buffH, 3 * sx)
        nvgStrokeColor(vg, nvgRGBA(255, 100, 180, 150))
        nvgStrokeWidth(vg, 1.0)
        nvgStroke(vg)
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 10 * sx)
        nvgFillColor(vg, nvgRGBA(255, 220, 240, 255))
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(vg, barX + buffW / 2, buffY + buffH / 2, string.format("吸血 %.1fs", S.lifestealBuffTimer))
    end
end

-- ============================================================================
-- 调试信息
-- ============================================================================
function M.DrawDebugInfo(width, height)
    local vg = S.nvg
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 14)
    nvgFillColor(vg, nvgRGBA(255, 255, 0, 255))

    local y = 16
    local lineH = 16

    local posStr = "nil"
    local screenStr = "nil"
    if S.playerNode then
        local pos = S.playerNode.position2D
        posStr = string.format("%.1f, %.1f", pos.x, pos.y)
        local camPos = S.cameraNode and S.cameraNode.worldPosition or Vector3(0, 0, -10)
        local ssx, ssy = M.PhysicsToScreen(pos.x, pos.y, camPos.x, camPos.y)
        ssx = ssx * (width / C.SCREEN_WIDTH)
        ssy = ssy * (height / C.SCREEN_HEIGHT)
        screenStr = string.format("%.0f, %.0f", ssx, ssy)
    end

    local texts = {
        "Idle=" .. tostring(S.imgIdle) .. " Run=" .. tostring(S.imgRun) .. " W=" .. tostring(S.imgWidth),
        "Pos=" .. posStr .. " Scr=" .. screenStr,
        "Anim=" .. S.currentAnim .. " F=" .. S.animFrame .. " Gnd=" .. tostring(S.onGround),
    }
    for _, t2 in ipairs(texts) do
        nvgText(vg, 10, y, t2)
        y = y + lineH
    end

    nvgBeginPath(vg)
    nvgCircle(vg, width / 2, height / 2, 5)
    nvgFillColor(vg, nvgRGBA(255, 0, 0, 200))
    nvgFill(vg)
end

return M
