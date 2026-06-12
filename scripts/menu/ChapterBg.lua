-- ============================================================================
-- ChapterBg.lua
-- 关卡选择背景动画：赛博宗教风格 Glitch Block Reveal 过渡
-- 基于参考视频逐帧还原：蓝图状态 → 故障块揭示 → 金色状态 → 循环
-- ============================================================================
local UI = require("urhox-libs/UI")

local M = {}

-- 动画状态
local state_ = {
    active = false,
    time = 0,
    phase = "blueprint",  -- "blueprint" | "glitch_to_gold" | "gold" | "glitch_to_bp"
    phaseTime = 0,
    layerGold = nil,
    layerBlueprint = nil,
    glitchBlocks = {},
    glitchContainer = nil,
    container = nil,
}

-- 配置 (基于视频分析)
local CFG = {
    -- 蓝图静态展示时长
    blueprintDuration = 6.0,
    -- 故障过渡时长
    glitchDuration = 0.45,
    -- 金色静态展示时长
    goldDuration = 6.0,
    -- 故障块数量（过渡时出现的白色矩形）
    glitchBlockCount = 12,
    -- 故障块最小/最大尺寸（百分比）
    blockMinW = 8, blockMaxW = 25,
    blockMinH = 4, blockMaxH = 15,
}

-- 故障块随机化参数
local glitchBlockData_ = {}

local function randomizeGlitchBlocks()
    glitchBlockData_ = {}
    for i = 1, CFG.glitchBlockCount do
        -- 色块类型随机分配（用于 gold→blueprint 方向的蓝色块比例）
        local colorType = math.random(1, 10)
        glitchBlockData_[i] = {
            x = math.random(0, 75),        -- left %
            y = math.random(0, 80),        -- top %
            w = math.random(CFG.blockMinW, CFG.blockMaxW),
            h = math.random(CFG.blockMinH, CFG.blockMaxH),
            -- 每个块出现/消失的时间偏移（产生阶梯状涌现效果）
            onset = math.random(0, 60) / 100,  -- 0~0.6 归一化
            -- 色块类型：用于两个方向的不同着色
            -- 1-5: 主色块, 6-8: 辅色块, 9-10: 边缘/黑色块
            colorType = colorType,
        }
    end
end

-- ============================================================================
-- 公共接口
-- ============================================================================

function M.Create()
    state_.time = 0
    state_.phase = "blueprint"
    state_.phaseTime = 0
    state_.active = true

    randomizeGlitchBlocks()

    -- 底层：金色赛博宗教
    state_.layerGold = UI.Panel {
        position = "absolute", top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundImage = "image/chapter_bg_gold.png",
        backgroundFit = "cover",
        pointerEvents = "none",
        opacity = 0,
    }

    -- 上层：蓝图
    state_.layerBlueprint = UI.Panel {
        position = "absolute", top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundImage = "image/chapter_bg_blueprint.png",
        backgroundFit = "cover",
        pointerEvents = "none",
        opacity = 1.0,
    }

    -- 故障块层
    state_.glitchContainer = UI.Panel {
        position = "absolute", top = 0, left = 0,
        width = "100%", height = "100%",
        pointerEvents = "none",
        overflow = "hidden",
    }
    state_.glitchBlocks = {}
    for i = 1, CFG.glitchBlockCount do
        local block = UI.Panel {
            position = "absolute",
            left = "0%", top = "0%",
            width = "10%", height = "5%",
            backgroundColor = {255, 255, 255, 0},  -- 初始全透明
            pointerEvents = "none",
        }
        state_.glitchContainer:AddChild(block)
        state_.glitchBlocks[i] = block
    end

    -- 总容器
    state_.container = UI.Panel {
        position = "absolute", top = 0, left = 0,
        width = "100%", height = "100%",
        pointerEvents = "none",
        children = {
            state_.layerGold,
            state_.layerBlueprint,
            state_.glitchContainer,
        },
    }

    return state_.container
end

--- 每帧更新
function M.Update(dt)
    if not state_.active then return end
    state_.time = state_.time + dt
    state_.phaseTime = state_.phaseTime + dt

    local phase = state_.phase

    if phase == "blueprint" then
        -- 蓝图静态展示
        if state_.phaseTime >= CFG.blueprintDuration then
            state_.phase = "glitch_to_gold"
            state_.phaseTime = 0
            randomizeGlitchBlocks()
        end

    elseif phase == "glitch_to_gold" then
        -- 故障过渡：蓝图 → 金色
        local progress = math.min(state_.phaseTime / CFG.glitchDuration, 1.0)

        -- 蓝图淡出 / 金色淡入（快速切换，非线性）
        local imgProgress = progress * progress  -- ease-in
        if state_.layerBlueprint then
            state_.layerBlueprint:SetStyle({ opacity = 1.0 - imgProgress })
        end
        if state_.layerGold then
            state_.layerGold:SetStyle({ opacity = imgProgress })
        end

        -- 故障块出现
        updateGlitchBlocks(progress, true)

        if progress >= 1.0 then
            state_.phase = "gold"
            state_.phaseTime = 0
            hideAllGlitchBlocks()
        end

    elseif phase == "gold" then
        -- 金色静态展示
        if state_.phaseTime >= CFG.goldDuration then
            state_.phase = "glitch_to_bp"
            state_.phaseTime = 0
            randomizeGlitchBlocks()
        end

    elseif phase == "glitch_to_bp" then
        -- 故障过渡：金色 → 蓝图
        local progress = math.min(state_.phaseTime / CFG.glitchDuration, 1.0)

        local imgProgress = progress * progress
        if state_.layerGold then
            state_.layerGold:SetStyle({ opacity = 1.0 - imgProgress })
        end
        if state_.layerBlueprint then
            state_.layerBlueprint:SetStyle({ opacity = imgProgress })
        end

        -- 故障块出现
        updateGlitchBlocks(progress, false)

        if progress >= 1.0 then
            state_.phase = "blueprint"
            state_.phaseTime = 0
            hideAllGlitchBlocks()
        end
    end
end

--- 获取色块颜色（基于视频逐帧分析）
--- Blueprint→Gold: 主要白色块 + 少量黑色边缘条
--- Gold→Blueprint: 主要蓝色/蓝紫色块 + 白色块 + 黑色边缘条
--- @param colorType number 1-10 色块类型
--- @param toGold boolean 是否向金色方向
--- @return number r
--- @return number g
--- @return number b
local function getBlockColor(colorType, toGold)
    if toGold then
        -- Blueprint → Gold 方向：以白色为主，少量黑色边缘
        if colorType <= 8 then
            -- 80% 白色块
            return 255, 255, 255
        else
            -- 20% 黑色/深色边缘条
            return 15, 15, 20
        end
    else
        -- Gold → Blueprint 方向：以蓝色为主，混合白色和黑色
        if colorType <= 5 then
            -- 50% 蓝色/蓝紫色块（匹配蓝图配色）
            -- 稍有随机偏移增加层次感
            local rOff = math.random(-10, 10)
            return 90 + rOff, 120 + rOff, 230 + math.random(-15, 0)
        elseif colorType <= 8 then
            -- 30% 白色块
            return 255, 255, 255
        else
            -- 20% 黑色边缘条
            return 10, 10, 15
        end
    end
end

--- 更新故障块的显示
--- @param progress number 0~1 过渡进度
--- @param toGold boolean 是否是向金色方向的过渡
function updateGlitchBlocks(progress, toGold)
    for i, block in ipairs(state_.glitchBlocks) do
        local data = glitchBlockData_[i]
        if not data then goto continue end

        -- 每个块有自己的出现时间窗口
        local blockStart = data.onset * 0.5        -- 块开始出现的进度点
        local blockEnd = blockStart + 0.5          -- 块结束的进度点
        local blockAlpha = 0

        if progress >= blockStart and progress <= blockEnd then
            -- 块在窗口内：从出现到消失的钟形曲线
            local localP = (progress - blockStart) / (blockEnd - blockStart)
            -- 钟形：先增后减
            blockAlpha = math.sin(localP * math.pi)
            -- 添加随机闪烁
            if math.random(1, 3) == 1 then
                blockAlpha = blockAlpha * math.random(60, 100) / 100
            end
        end

        local alpha = math.floor(blockAlpha * 230)
        local r, g, b = getBlockColor(data.colorType, toGold)

        block:SetStyle({
            left = data.x .. "%",
            top = data.y .. "%",
            width = data.w .. "%",
            height = data.h .. "%",
            backgroundColor = {r, g, b, alpha},
        })

        ::continue::
    end
end

--- 隐藏所有故障块
function hideAllGlitchBlocks()
    for i, block in ipairs(state_.glitchBlocks) do
        block:SetStyle({
            backgroundColor = {255, 255, 255, 0},
        })
    end
end

--- 销毁
function M.Destroy()
    state_.active = false
    state_.layerGold = nil
    state_.layerBlueprint = nil
    state_.glitchBlocks = {}
    state_.glitchContainer = nil
    state_.container = nil
    glitchBlockData_ = {}
end

return M
