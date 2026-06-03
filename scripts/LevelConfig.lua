-- ============================================================================
-- LevelConfig.lua - 关卡区域配置
-- 定义三个区域（古堡、冰原、森林）的背景、平台布局、敌人配置
-- ============================================================================

local LevelConfig = {}

-- 区域枚举
LevelConfig.AREA_CASTLE = "castle"
LevelConfig.AREA_ICE = "ice"
LevelConfig.AREA_FOREST = "forest"

-- 各区域配置
LevelConfig.areas = {
    -- ====== 古堡区域（原始关卡） ======
    [LevelConfig.AREA_CASTLE] = {
        name = "华丽古堡",
        background = "image/bg_castle_cartoon_20260601173316.png",
        platformImage = nil,  -- 古堡使用程序化绘制平台
        platformStyle = "baroque",  -- 巴洛克金色高台
        groundY = -4.0,
        groundWidth = 60,  -- MAP_HALF_WIDTH * 2
        platforms = {
            { x = -6, y = -1.5, width = 3, height = 0.5 },
            { x = -2, y = 0.5, width = 2.5, height = 0.5 },
            { x = 2, y = 2.0, width = 3, height = 0.5 },
            { x = 6, y = 0.5, width = 2.5, height = 0.5 },
            { x = 10, y = 2.5, width = 3, height = 0.5 },
            { x = -4, y = 3.0, width = 2, height = 0.5 },
            { x = 14, y = 1.0, width = 2.5, height = 0.5 },
            { x = 18, y = 3.0, width = 3, height = 0.5 },
        },
        enemies = {
            { type = "wolf", x = 12, y = -3.0 },
            { type = "wyvern", x = 15, y = 2.0 },
            { type = "skeleton", x = 18, y = -3.0 },
            { type = "ghost", x = 20, y = 1.5 },
            { type = "gargoyle", x = 22, y = 3.0 },
        },
        basicEnemies = {
            { x = 5, y = -3.0 },
            { x = 10, y = -3.0 },
        },
        batEnemies = {
            { x = 3, y = 2.0 },
            { x = 8, y = 3.0 },
        },
    },

    -- ====== 冰原区域 ======
    [LevelConfig.AREA_ICE] = {
        name = "极寒冰原",
        background = "image/ice_bg_far_20260602111146.png",
        -- 多层视差背景（远→近，parallaxFactor越大滚动越快）
        parallaxLayers = {
            { image = "image/ice_bg_far_20260602111146.png",  factor = 0.1 },  -- 远景雪山（几乎不动）
            { image = "image/ice_bg_mid_20260602111140.png",  factor = 0.4 },  -- 中景雪屋灌木
            { image = "image/ice_bg_near_20260602111135.png", factor = 0.7 },  -- 近景路灯路牌
        },
        platformImage = "image/platform_ice_20260601153959.png",
        groundImage = "image/ground_snow_20260601173313.png",
        platformStyle = "image",  -- 使用图片渲染平台
        groundY = -4.0,
        groundWidth = 60,
        platforms = {
            { x = -5, y = -1.0, width = 3.5, height = 0.6 },
            { x = -1, y = 1.0, width = 2.5, height = 0.6 },
            { x = 4, y = 2.5, width = 3, height = 0.6 },
            { x = 8, y = 0.5, width = 2.5, height = 0.6 },
            { x = 12, y = 3.0, width = 3, height = 0.6 },
            { x = -3, y = 3.5, width = 2, height = 0.6 },
            { x = 16, y = 1.5, width = 3, height = 0.6 },
            { x = 20, y = 3.5, width = 2.5, height = 0.6 },
        },
        enemies = {
            { type = "wolf", x = 10, y = -3.0 },
            { type = "wolf", x = 16, y = -3.0 },
            { type = "ghost", x = 5, y = 2.0 },
            { type = "ghost", x = 20, y = 2.5 },
        },
        basicEnemies = {
            { x = 6, y = -3.0 },
            { x = 14, y = -3.0 },
        },
        batEnemies = {
            { x = 4, y = 3.0 },
            { x = 12, y = 4.0 },
        },
    },

    -- ====== 森林区域 ======
    [LevelConfig.AREA_FOREST] = {
        name = "幽暗森林",
        background = "image/bg_forest_20260601154001.png",
        platformImage = "image/platform_vine_stone_20260601154000.png",
        groundImage = "image/ground_leaves_20260601173313.png",
        platformStyle = "image",  -- 使用图片渲染平台
        groundY = -4.0,
        groundWidth = 60,
        platforms = {
            { x = -7, y = -1.0, width = 3, height = 0.6 },
            { x = -3, y = 1.5, width = 2.5, height = 0.6 },
            { x = 1, y = 3.0, width = 2, height = 0.6 },
            { x = 5, y = 1.0, width = 3, height = 0.6 },
            { x = 9, y = 2.5, width = 2.5, height = 0.6 },
            { x = 13, y = 0.5, width = 3, height = 0.6 },
            { x = 17, y = 2.0, width = 2.5, height = 0.6 },
            { x = 21, y = 3.5, width = 3, height = 0.6 },
        },
        enemies = {
            { type = "skeleton", x = 8, y = -3.0 },
            { type = "skeleton", x = 14, y = -3.0 },
            { type = "wyvern", x = 10, y = 3.0 },
            { type = "gargoyle", x = 18, y = 3.5 },
        },
        basicEnemies = {
            { x = 4, y = -3.0 },
            { x = 12, y = -3.0 },
            { x = 20, y = -3.0 },
        },
        batEnemies = {
            { x = 6, y = 2.5 },
            { x = 15, y = 3.5 },
        },
    },
}

--- 获取指定区域的配置
---@param areaId string
---@return table|nil
function LevelConfig.GetArea(areaId)
    return LevelConfig.areas[areaId]
end

--- 获取所有区域ID列表
---@return string[]
function LevelConfig.GetAreaIds()
    return { LevelConfig.AREA_CASTLE, LevelConfig.AREA_ICE, LevelConfig.AREA_FOREST }
end

return LevelConfig
