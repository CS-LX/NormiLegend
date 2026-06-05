---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- SpriteEditor - 序列帧编辑器（UI面板 + NanoVG预览）
-- 支持层级索引：一级（敌人/角色），二级（具体敌人类型 / 角色1/角色2）
-- 每个实体每个动画独立的渲染倍率和裁切参数
-- ============================================================================

local UI = require("urhox-libs/UI")

local SpriteEditor = {}

-- 编辑器状态
local visible_ = false
local primaryIdx_ = 1       -- 一级索引: 1=角色, 2=敌人
local secondaryIdx_ = 1     -- 二级索引（角色下: 1=角色1, 2=角色2；敌人下: 1=蝙蝠, 2=斯缇昔娅, 3-7=古堡）
local animIdx_ = 1
local frame_ = 0
local paramIdx_ = 1

-- 一级/二级标签名
local PRIMARY_NAMES = { "角色", "敌人" }
local SECONDARY_NAMES = {
    -- 角色分支
    { "角色1", "角色2" },
    -- 敌人分支
    { "蝙蝠", "斯缇昔娅", "灰狼", "飞龙", "骷髅兵", "幽灵", "石像鬼" },
}

-- 各实体的动画定义
local ENTITY_ANIMS = {
    -- [primaryIdx][secondaryIdx] = { keys = {...}, labels = {...}, cols = N, rows = N, frames = N }
}

-- 角色动画（角色1和角色2共用动画名）
local CHAR_ANIM_KEYS = { "idle", "run", "jump", "attack", "block", "charge", "heal", "crouch", "crouch_walk", "hit" }
local CHAR_ANIM_LABELS = { "待机", "跑步", "跳跃", "攻击", "格挡", "蓄力/爆发", "治愈", "蹲下", "蹲走", "受击" }

-- 敌人动画定义
local BAT_ANIM_KEYS = { "fly", "attack", "hit" }
local BAT_ANIM_LABELS = { "飞行", "攻击", "受击" }

local STIXIA_ANIM_KEYS = { "move", "attack", "skill", "hit", "death" }
local STIXIA_ANIM_LABELS = { "移动", "攻击", "技能", "受击", "死亡" }

local CASTLE_ANIM_KEYS = { "idle", "attack", "hit", "death" }
local CASTLE_ANIM_LABELS = { "待机", "攻击", "受击", "死亡" }

-- 参数定义
local paramNames_ = { "scale", "offsetX", "offsetY", "cropW", "cropH", "cropOffX", "cropOffY" }
local paramLabels_ = { "渲染倍率", "水平偏移", "垂直偏移", "裁切宽", "裁切高", "裁切X偏移", "裁切Y偏移" }
local paramSteps_ = { 0.5, 0.02, 0.02, 0.05, 0.05, 0.02, 0.02 }
local paramMin_ = { 1.0, -1.0, -1.0, 0.1, 0.1, -0.5, -0.5 }
local paramMax_ = { 15.0, 1.0, 2.0, 1.0, 1.0, 0.5, 0.5 }
local paramDefaults_ = { 5.5, 0.0, 0.75, 1.0, 1.0, 0.0, 0.0 }

-- 外部引用（由Init传入）
local getCharAnimCropConfig_ = nil   -- function(charIdx) -> config table
local getCharAnimImages_ = nil       -- function(charIdx) -> table of images
local getNvg_ = nil
local getImgSize_ = nil              -- function() -> w, h (角色图片尺寸)
local getCurrentChar_ = nil          -- function() -> 1 or 2

-- 敌人序列帧配置（per-type per-anim）
-- enemySpriteConfig_[typeKey][animKey] = { scale, offsetX, offsetY, cropW, cropH, cropOffX, cropOffY }
local enemySpriteConfig_ = {}

-- 敌人图片获取函数
local getEnemyImages_ = nil   -- function(typeKey) -> { [animKey] = nvgImage, ... }
local getEnemyImgSize_ = nil  -- function(typeKey) -> w, h

-- 各敌人的grid配置
local ENEMY_GRID = {
    bat      = { cols = 4, rows = 1, frames = 4 },
    stixia   = { cols = 2, rows = 2, frames = 4 },
    wolf     = { cols = 4, rows = 1, frames = 4 },
    wyvern   = { cols = 4, rows = 1, frames = 4 },
    skeleton = { cols = 4, rows = 1, frames = 4 },
    ghost    = { cols = 4, rows = 1, frames = 4 },
    gargoyle = { cols = 4, rows = 1, frames = 4 },
}

-- 敌人 typeKey 映射: secondaryIdx -> typeKey
local ENEMY_TYPE_KEYS = { "bat", "stixia", "wolf", "wyvern", "skeleton", "ghost", "gargoyle" }

-- 角色相关常量
local SPRITE_COLS = 4
local SPRITE_ROWS = 3
local SPRITE_FRAMES = 12
local PLAYER_RADIUS = 0.4
local PIXELS_PER_UNIT = 60
local SCREEN_WIDTH = 1280

-- UI 引用
local editorPanel_ = nil
local lblAnimName_ = nil
local lblFrameInfo_ = nil
local lblEntityInfo_ = nil
local paramSliders_ = {}
local paramValueLabels_ = {}
local primaryBtnContainer_ = nil
local secondaryBtnContainer_ = nil
local animBtnContainer_ = nil

-- ============================================================================
-- 辅助：获取当前实体信息
-- ============================================================================

local function GetCurrentAnimKeys()
    if primaryIdx_ == 1 then
        return CHAR_ANIM_KEYS
    else
        local typeKey = ENEMY_TYPE_KEYS[secondaryIdx_]
        if typeKey == "bat" then return BAT_ANIM_KEYS
        elseif typeKey == "stixia" then return STIXIA_ANIM_KEYS
        else return CASTLE_ANIM_KEYS
        end
    end
end

local function GetCurrentAnimLabels()
    if primaryIdx_ == 1 then
        return CHAR_ANIM_LABELS
    else
        local typeKey = ENEMY_TYPE_KEYS[secondaryIdx_]
        if typeKey == "bat" then return BAT_ANIM_LABELS
        elseif typeKey == "stixia" then return STIXIA_ANIM_LABELS
        else return CASTLE_ANIM_LABELS
        end
    end
end

local function GetCurrentGrid()
    if primaryIdx_ == 1 then
        return { cols = SPRITE_COLS, rows = SPRITE_ROWS, frames = SPRITE_FRAMES }
    else
        local typeKey = ENEMY_TYPE_KEYS[secondaryIdx_]
        return ENEMY_GRID[typeKey] or { cols = 4, rows = 1, frames = 4 }
    end
end

local function GetCurrentConfig()
    if primaryIdx_ == 1 then
        -- 角色
        if getCharAnimCropConfig_ then
            local config = getCharAnimCropConfig_(secondaryIdx_)
            local key = CHAR_ANIM_KEYS[animIdx_]
            if not config[key] then
                config[key] = {
                    scale = 5.5, offsetX = 0.0, offsetY = 0.75,
                    cropW = 1.0, cropH = 1.0, cropOffX = 0.0, cropOffY = 0.0
                }
            end
            return config[key]
        end
        return { scale = 5.5, offsetX = 0.0, offsetY = 0.75, cropW = 1.0, cropH = 1.0, cropOffX = 0.0, cropOffY = 0.0 }
    else
        -- 敌人
        local typeKey = ENEMY_TYPE_KEYS[secondaryIdx_]
        local animKeys = GetCurrentAnimKeys()
        local animKey = animKeys[animIdx_]
        if not enemySpriteConfig_[typeKey] then
            enemySpriteConfig_[typeKey] = {}
        end
        if not enemySpriteConfig_[typeKey][animKey] then
            enemySpriteConfig_[typeKey][animKey] = {
                scale = 5.5, offsetX = 0.0, offsetY = 0.75,
                cropW = 1.0, cropH = 1.0, cropOffX = 0.0, cropOffY = 0.0
            }
        end
        return enemySpriteConfig_[typeKey][animKey]
    end
end

local function GetCurrentImage()
    if primaryIdx_ == 1 then
        -- 角色
        if getCharAnimImages_ then
            local imgs = getCharAnimImages_(secondaryIdx_)
            return imgs[animIdx_]
        end
        return nil
    else
        -- 敌人
        if getEnemyImages_ then
            local typeKey = ENEMY_TYPE_KEYS[secondaryIdx_]
            local imgs = getEnemyImages_(typeKey)
            local animKeys = GetCurrentAnimKeys()
            local animKey = animKeys[animIdx_]
            return imgs and imgs[animKey] or nil
        end
        return nil
    end
end

local function GetCurrentImageSize()
    if primaryIdx_ == 1 then
        if getImgSize_ then return getImgSize_() end
        return 0, 0
    else
        if getEnemyImgSize_ then
            local typeKey = ENEMY_TYPE_KEYS[secondaryIdx_]
            return getEnemyImgSize_(typeKey)
        end
        return 0, 0
    end
end

-- ============================================================================
-- 参数读写
-- ============================================================================

local function GetParamValue(pIdx)
    local cfg = GetCurrentConfig()
    if pIdx == 1 then return cfg.scale or 5.5
    elseif pIdx == 2 then return cfg.offsetX or 0.0
    elseif pIdx == 3 then return cfg.offsetY or 0.75
    elseif pIdx == 4 then return cfg.cropW or 1.0
    elseif pIdx == 5 then return cfg.cropH or 1.0
    elseif pIdx == 6 then return cfg.cropOffX or 0.0
    elseif pIdx == 7 then return cfg.cropOffY or 0.0
    end
    return 0
end

local function SetParamValue(pIdx, val)
    local cfg = GetCurrentConfig()
    val = math.max(paramMin_[pIdx], math.min(paramMax_[pIdx], val))
    if pIdx == 1 then cfg.scale = val
    elseif pIdx == 2 then cfg.offsetX = val
    elseif pIdx == 3 then cfg.offsetY = val
    elseif pIdx == 4 then cfg.cropW = val
    elseif pIdx == 5 then cfg.cropH = val
    elseif pIdx == 6 then cfg.cropOffX = val
    elseif pIdx == 7 then cfg.cropOffY = val
    end
end

-- ============================================================================
-- 刷新UI显示
-- ============================================================================

local function RefreshUI()
    if not editorPanel_ then return end
    local animKeys = GetCurrentAnimKeys()
    local animLabels = GetCurrentAnimLabels()
    local grid = GetCurrentGrid()

    -- 实体信息
    local entityName = SECONDARY_NAMES[primaryIdx_][secondaryIdx_]
    lblEntityInfo_:SetText(PRIMARY_NAMES[primaryIdx_] .. " > " .. entityName)

    -- 动画名称
    local aLabel = animLabels[animIdx_] or "?"
    local aKey = animKeys[animIdx_] or "?"
    lblAnimName_:SetText(aLabel .. " (" .. aKey .. ")")

    -- 帧信息
    lblFrameInfo_:SetText("帧: " .. frame_ .. "/" .. (grid.frames - 1))

    -- 更新所有参数滑块和数值标签
    for i = 1, #paramNames_ do
        local val = GetParamValue(i)
        local normalized = (val - paramMin_[i]) / (paramMax_[i] - paramMin_[i])
        if paramSliders_[i] then
            paramSliders_[i]:SetValue(normalized)
        end
        if paramValueLabels_[i] then
            paramValueLabels_[i]:SetText(string.format("%.2f", val))
        end
    end
end

-- 前向声明（解决互相引用）
local RefreshAnimButtons

-- 刷新二级标签按钮
local function RefreshSecondaryButtons()
    if not secondaryBtnContainer_ then return end
    secondaryBtnContainer_:RemoveAllChildren()
    local names = SECONDARY_NAMES[primaryIdx_]
    for i, name in ipairs(names) do
        local idx = i
        local isActive = (i == secondaryIdx_)
        local btn = UI.Button {
            text = name, fontSize = 9, height = 20,
            paddingLeft = 4, paddingRight = 4,
            backgroundColor = isActive and "#553355" or "#1e1e2e",
            color = isActive and "#ffcc66" or "#8888aa",
            borderRadius = 3,
            onClick = function()
                secondaryIdx_ = idx
                animIdx_ = 1
                frame_ = 0
                RefreshSecondaryButtons()
                RefreshAnimButtons()
                RefreshUI()
            end,
        }
        secondaryBtnContainer_:AddChild(btn)
    end
end

-- 刷新动画按钮
RefreshAnimButtons = function()
    if not animBtnContainer_ then return end
    animBtnContainer_:RemoveAllChildren()
    local labels = GetCurrentAnimLabels()
    for i, label in ipairs(labels) do
        local idx = i
        local btn = UI.Button {
            text = label,
            fontSize = 10, height = 22,
            paddingLeft = 4, paddingRight = 4,
            backgroundColor = (i == animIdx_) and "#335577" or "#1e1e2e",
            color = (i == animIdx_) and "#aaeeff" or "#8888aa",
            borderRadius = 3,
            onClick = function()
                animIdx_ = idx
                frame_ = 0
                RefreshAnimButtons()
                RefreshUI()
            end,
        }
        animBtnContainer_:AddChild(btn)
    end
end

-- 刷新一级标签
local function RefreshPrimaryButtons()
    if not primaryBtnContainer_ then return end
    primaryBtnContainer_:RemoveAllChildren()
    for i, name in ipairs(PRIMARY_NAMES) do
        local idx = i
        local isActive = (i == primaryIdx_)
        local btn = UI.Button {
            text = name, fontSize = 11, height = 22,
            paddingLeft = 8, paddingRight = 8,
            backgroundColor = isActive and "#662222" or "#282838",
            color = isActive and "#ffff66" or "#a0a0b4",
            borderRadius = 4,
            flexGrow = 1,
            onClick = function()
                primaryIdx_ = idx
                secondaryIdx_ = 1
                animIdx_ = 1
                frame_ = 0
                RefreshPrimaryButtons()
                RefreshSecondaryButtons()
                RefreshAnimButtons()
                RefreshUI()
            end,
        }
        primaryBtnContainer_:AddChild(btn)
    end
end

-- ============================================================================
-- 初始化
-- ============================================================================

---@param opts table 配置选项
function SpriteEditor.Init(opts)
    getCharAnimCropConfig_ = opts.getAnimCropConfig
    getCharAnimImages_ = opts.getAnimImages
    getNvg_ = opts.getNvg
    getImgSize_ = opts.getImgSize
    getCurrentChar_ = opts.getCurrentChar
    getEnemyImages_ = opts.getEnemyImages
    getEnemyImgSize_ = opts.getEnemyImgSize
    SPRITE_COLS = opts.spriteCols or 4
    SPRITE_ROWS = opts.spriteRows or 3
    SPRITE_FRAMES = opts.spriteFrames or 12
    PLAYER_RADIUS = opts.playerRadius or 0.4
    PIXELS_PER_UNIT = opts.pixelsPerUnit or 60
    SCREEN_WIDTH = opts.screenWidth or 1280

    -- 初始化敌人grid覆盖（如果有特殊配置）
    if opts.enemyGridOverrides then
        for k, v in pairs(opts.enemyGridOverrides) do
            ENEMY_GRID[k] = v
        end
    end

    SpriteEditor.CreateUI()
end

-- ============================================================================
-- 创建UI面板
-- ============================================================================

function SpriteEditor.CreateUI()
    -- 参数行构建
    local paramRows = {}
    for i = 1, #paramNames_ do
        local valLabel = UI.Label {
            text = string.format("%.2f", paramDefaults_[i]),
            fontSize = 12,
            fontColor = { 255, 255, 100, 255 },
            width = 42,
            textAlign = "right",
        }
        paramValueLabels_[i] = valLabel

        local idx = i
        local slider = UI.Slider {
            value = 0.5,
            min = 0, max = 1,
            step = 0.01,
            height = 20,
            flexGrow = 1, flexShrink = 1,
            onChange = function(self, v)
                local realVal = paramMin_[idx] + v * (paramMax_[idx] - paramMin_[idx])
                SetParamValue(idx, realVal)
                valLabel:SetText(string.format("%.2f", realVal))
            end,
        }
        paramSliders_[i] = slider

        local btnDec = UI.Button {
            text = "-", width = 24, height = 22, fontSize = 14,
            onClick = function()
                local cur = GetParamValue(idx)
                SetParamValue(idx, cur - paramSteps_[idx])
                RefreshUI()
            end,
        }
        local btnInc = UI.Button {
            text = "+", width = 24, height = 22, fontSize = 14,
            onClick = function()
                local cur = GetParamValue(idx)
                SetParamValue(idx, cur + paramSteps_[idx])
                RefreshUI()
            end,
        }

        local row = UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            width = "100%",
            gap = 4, marginBottom = 2,
            children = {
                UI.Label {
                    text = paramLabels_[i],
                    fontSize = 11,
                    fontColor = { 180, 220, 255, 220 },
                    width = 60,
                },
                btnDec, slider, btnInc, valLabel,
            }
        }
        table.insert(paramRows, row)
    end

    -- 一级标签容器
    primaryBtnContainer_ = UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "flex-start", gap = 4,
        marginBottom = 4,
    }

    -- 二级标签容器
    secondaryBtnContainer_ = UI.Panel {
        width = "100%", flexDirection = "row",
        flexWrap = "wrap",
        justifyContent = "flex-start", gap = 3,
        marginBottom = 4,
    }

    -- 动画按钮容器
    animBtnContainer_ = UI.Panel {
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 3,
        marginBottom = 6,
    }

    -- 信息标签
    lblEntityInfo_ = UI.Label {
        text = "角色 > 角色1",
        fontSize = 13,
        fontColor = { 255, 200, 100, 255 },
        marginBottom = 2,
    }
    lblAnimName_ = UI.Label {
        text = "待机 (idle)",
        fontSize = 13,
        fontColor = { 100, 255, 200, 255 },
    }
    lblFrameInfo_ = UI.Label {
        text = "帧: 0/11",
        fontSize = 12,
        fontColor = { 255, 220, 100, 255 },
    }

    editorPanel_ = UI.Panel {
        id = "spriteEditorRoot",
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 0 },
        pointerEvents = "box-none",
        children = {
            -- 右侧控制面板
            UI.Panel {
                position = "absolute",
                top = 10, right = 10,
                width = 330,
                maxHeight = "95%",
                backgroundColor = { 10, 15, 30, 230 },
                borderRadius = 8,
                borderWidth = 1,
                borderColor = { 80, 160, 220, 180 },
                padding = 10,
                overflow = "scroll",
                children = {
                    -- 标题行
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        marginBottom = 6,
                        children = {
                            UI.Label { text = "序列帧编辑器", fontSize = 16, fontColor = { 100, 220, 255, 255 } },
                            UI.Button {
                                text = "关闭(O)",
                                fontSize = 11, height = 22,
                                onClick = function() SpriteEditor.Hide() end,
                            },
                        }
                    },
                    -- 分隔线
                    UI.Panel { width = "100%", height = 1, backgroundColor = { 60, 140, 200, 120 }, marginBottom = 6 },
                    -- 一级标签
                    primaryBtnContainer_,
                    -- 二级标签
                    secondaryBtnContainer_,
                    -- 分隔线
                    UI.Panel { width = "100%", height = 1, backgroundColor = { 60, 140, 200, 80 }, marginBottom = 4 },
                    -- 实体信息
                    lblEntityInfo_,
                    -- 动画信息行
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        marginBottom = 4,
                        children = { lblAnimName_, lblFrameInfo_ }
                    },
                    -- 动画选择按钮
                    animBtnContainer_,
                    -- 帧切换
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "center",
                        alignItems = "center",
                        gap = 8, marginBottom = 6,
                        children = {
                            UI.Button {
                                text = "< 上一帧", fontSize = 11, height = 24,
                                onClick = function()
                                    local grid = GetCurrentGrid()
                                    frame_ = frame_ - 1
                                    if frame_ < 0 then frame_ = grid.frames - 1 end
                                    RefreshUI()
                                end,
                            },
                            UI.Button {
                                text = "下一帧 >", fontSize = 11, height = 24,
                                onClick = function()
                                    local grid = GetCurrentGrid()
                                    frame_ = frame_ + 1
                                    if frame_ >= grid.frames then frame_ = 0 end
                                    RefreshUI()
                                end,
                            },
                        }
                    },
                    -- 分隔线
                    UI.Panel { width = "100%", height = 1, backgroundColor = { 60, 140, 200, 80 }, marginBottom = 4 },
                    -- 参数面板标题
                    UI.Label { text = "参数调节（每动画独立）", fontSize = 12, fontColor = { 200, 200, 200, 200 }, marginBottom = 4 },
                    -- 参数滑块列表
                    table.unpack(paramRows),
                }
            },
            -- 底部复制按钮区域
            UI.Panel {
                position = "absolute",
                bottom = 50, right = 10,
                width = 330,
                backgroundColor = { 10, 15, 30, 220 },
                borderRadius = 6,
                borderWidth = 1,
                borderColor = { 80, 160, 220, 150 },
                padding = 8,
                flexDirection = "row",
                justifyContent = "center",
                gap = 10,
                children = {
                    UI.Button {
                        text = "复制当前动画(C)",
                        fontSize = 11, height = 26,
                        paddingLeft = 8, paddingRight = 8,
                        onClick = function() SpriteEditor.CopyCurrent() end,
                    },
                    UI.Button {
                        text = "复制全部配置(V)",
                        fontSize = 11, height = 26,
                        paddingLeft = 8, paddingRight = 8,
                        onClick = function() SpriteEditor.CopyAll() end,
                    },
                }
            },
        }
    }

    editorPanel_:Hide()

    -- 初始化标签内容
    RefreshPrimaryButtons()
    RefreshSecondaryButtons()
    RefreshAnimButtons()
end

-- ============================================================================
-- 显示/隐藏
-- ============================================================================

function SpriteEditor.Show()
    visible_ = true
    if editorPanel_ then
        editorPanel_:Show()
        RefreshPrimaryButtons()
        RefreshSecondaryButtons()
        RefreshAnimButtons()
        RefreshUI()
    end
end

function SpriteEditor.Hide()
    visible_ = false
    if editorPanel_ then
        editorPanel_:Hide()
    end
end

function SpriteEditor.Toggle()
    if visible_ then
        SpriteEditor.Hide()
    else
        SpriteEditor.Show()
    end
end

function SpriteEditor.IsVisible()
    return visible_
end

-- ============================================================================
-- 键盘输入处理
-- ============================================================================

function SpriteEditor.HandleInput()
    if not visible_ then return false end
    -- O键/ESC键关闭
    if input:GetKeyPress(KEY_O) or input:GetKeyPress(KEY_ESCAPE) then
        SpriteEditor.Hide()
        return true
    end
    -- Tab 切换一级标签
    if input:GetKeyPress(KEY_TAB) then
        primaryIdx_ = primaryIdx_ == 1 and 2 or 1
        secondaryIdx_ = 1
        animIdx_ = 1
        frame_ = 0
        RefreshPrimaryButtons()
        RefreshSecondaryButtons()
        RefreshAnimButtons()
        RefreshUI()
    end
    -- 1-9 切换二级标签
    local numKeys = { KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9 }
    local maxSec = #SECONDARY_NAMES[primaryIdx_]
    for i = 1, math.min(9, maxSec) do
        if input:GetKeyPress(numKeys[i]) then
            secondaryIdx_ = i
            animIdx_ = 1
            frame_ = 0
            RefreshSecondaryButtons()
            RefreshAnimButtons()
            RefreshUI()
            break
        end
    end
    -- Q/E 切换动画
    local animKeys = GetCurrentAnimKeys()
    if input:GetKeyPress(KEY_Q) then
        animIdx_ = animIdx_ - 1
        if animIdx_ < 1 then animIdx_ = #animKeys end
        frame_ = 0
        RefreshAnimButtons()
        RefreshUI()
    end
    if input:GetKeyPress(KEY_E) then
        animIdx_ = animIdx_ + 1
        if animIdx_ > #animKeys then animIdx_ = 1 end
        frame_ = 0
        RefreshAnimButtons()
        RefreshUI()
    end
    -- A/D 切换帧
    local grid = GetCurrentGrid()
    if input:GetKeyPress(KEY_A) or input:GetKeyPress(KEY_LEFT) then
        frame_ = frame_ - 1
        if frame_ < 0 then frame_ = grid.frames - 1 end
        RefreshUI()
    end
    if input:GetKeyPress(KEY_D) or input:GetKeyPress(KEY_RIGHT) then
        frame_ = frame_ + 1
        if frame_ >= grid.frames then frame_ = 0 end
        RefreshUI()
    end
    -- W/S 切换参数
    if input:GetKeyPress(KEY_W) or input:GetKeyPress(KEY_UP) then
        paramIdx_ = paramIdx_ - 1
        if paramIdx_ < 1 then paramIdx_ = #paramNames_ end
    end
    if input:GetKeyPress(KEY_S) or input:GetKeyPress(KEY_DOWN) then
        paramIdx_ = paramIdx_ + 1
        if paramIdx_ > #paramNames_ then paramIdx_ = 1 end
    end
    -- [ / ] 调整当前参数
    local step = 0
    if input:GetKeyPress(KEY_LEFTBRACKET) then step = -1 end
    if input:GetKeyPress(KEY_RIGHTBRACKET) then step = 1 end
    if step ~= 0 then
        local cur = GetParamValue(paramIdx_)
        SetParamValue(paramIdx_, cur + step * paramSteps_[paramIdx_])
        RefreshUI()
    end
    -- C 复制当前动画配置
    if input:GetKeyPress(KEY_C) then
        SpriteEditor.CopyCurrent()
    end
    -- V 复制全部配置
    if input:GetKeyPress(KEY_V) then
        SpriteEditor.CopyAll()
    end
    return true
end

-- ============================================================================
-- NanoVG 预览渲染
-- ============================================================================

function SpriteEditor.DrawPreview(width, height)
    if not visible_ then return end

    local nvg = getNvg_()
    local img = GetCurrentImage()
    local imgW, imgH = GetCurrentImageSize()
    local cfg = GetCurrentConfig()
    local grid = GetCurrentGrid()
    local cols = grid.cols
    local rows = grid.rows

    -- 左侧预览区域（半透明黑底）
    local previewW = width * 0.6
    nvgBeginPath(nvg)
    nvgRect(nvg, 0, 0, previewW, height)
    nvgFillColor(nvg, nvgRGBA(0, 0, 0, 200))
    nvgFill(nvg)

    -- 绘制整张序列帧在左上角
    local sheetDisplayW = previewW * 0.42
    local sheetDisplayH = sheetDisplayW * (imgH / math.max(imgW, 1))
    local sheetX = 15
    local sheetY = 50

    if img and img > 0 and imgW > 0 then
        local paint = nvgImagePattern(nvg, sheetX, sheetY, sheetDisplayW, sheetDisplayH, 0, img, 1.0)
        nvgBeginPath(nvg)
        nvgRect(nvg, sheetX, sheetY, sheetDisplayW, sheetDisplayH)
        nvgFillPaint(nvg, paint)
        nvgFill(nvg)

        -- 网格线
        nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, 80))
        nvgStrokeWidth(nvg, 1)
        local cellW = sheetDisplayW / cols
        local cellH = sheetDisplayH / rows
        for c = 1, cols - 1 do
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, sheetX + c * cellW, sheetY)
            nvgLineTo(nvg, sheetX + c * cellW, sheetY + sheetDisplayH)
            nvgStroke(nvg)
        end
        for r = 1, rows - 1 do
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, sheetX, sheetY + r * cellH)
            nvgLineTo(nvg, sheetX + sheetDisplayW, sheetY + r * cellH)
            nvgStroke(nvg)
        end

        -- 高亮当前帧
        local curCol = frame_ % cols
        local curRow = math.floor(frame_ / cols)
        nvgBeginPath(nvg)
        nvgRect(nvg, sheetX + curCol * cellW, sheetY + curRow * cellH, cellW, cellH)
        nvgStrokeColor(nvg, nvgRGBA(0, 255, 0, 255))
        nvgStrokeWidth(nvg, 3)
        nvgStroke(nvg)

        -- 裁切框显示
        local cropW = cfg.cropW or 1.0
        local cropH = cfg.cropH or 1.0
        local cropOffX = cfg.cropOffX or 0.0
        local cropOffY = cfg.cropOffY or 0.0
        local cropRectW = cellW * cropW
        local cropRectH = cellH * cropH
        local cropRectX = sheetX + curCol * cellW + (cellW - cropRectW) / 2 + cellW * cropOffX
        local cropRectY = sheetY + curRow * cellH + (cellH - cropRectH) / 2 + cellH * cropOffY
        nvgBeginPath(nvg)
        nvgRect(nvg, cropRectX, cropRectY, cropRectW, cropRectH)
        nvgStrokeColor(nvg, nvgRGBA(255, 255, 0, 200))
        nvgStrokeWidth(nvg, 2)
        nvgStroke(nvg)
    end

    -- 单帧预览（带参数效果）
    local previewCenterX = sheetX + (sheetDisplayW > 0 and sheetDisplayW or previewW * 0.42) + (previewW - sheetX - (sheetDisplayW > 0 and sheetDisplayW or previewW * 0.42)) * 0.5
    local previewCenterY = sheetY + (sheetDisplayH > 0 and sheetDisplayH or 200) * 0.5
    local scale = cfg.scale or 5.5
    local previewSize = PLAYER_RADIUS * scale * PIXELS_PER_UNIT * (width / SCREEN_WIDTH)

    -- 参考十字线
    nvgStrokeColor(nvg, nvgRGBA(255, 0, 0, 150))
    nvgStrokeWidth(nvg, 1)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, previewCenterX - 40, previewCenterY)
    nvgLineTo(nvg, previewCenterX + 40, previewCenterY)
    nvgStroke(nvg)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, previewCenterX, previewCenterY - 40)
    nvgLineTo(nvg, previewCenterX, previewCenterY + 40)
    nvgStroke(nvg)

    -- 单帧预览
    if img and img > 0 and imgW > 0 then
        local frameW = imgW / cols
        local frameH = imgH / rows
        local cropW = cfg.cropW or 1.0
        local cropH = cfg.cropH or 1.0
        local cropOffX = cfg.cropOffX or 0.0
        local cropOffY = cfg.cropOffY or 0.0

        local srcW = frameW * cropW
        local srcH = frameH * cropH
        local srcOffX = frameW * cropOffX
        local srcOffY = frameH * cropOffY

        local drawW = previewSize
        local drawH = previewSize * (srcH / srcW)
        local oX = cfg.offsetX or 0.0
        local oY = cfg.offsetY or 0.75
        local drawX = previewCenterX - drawW / 2 + oX * drawW
        local drawY = previewCenterY - drawH * oY

        local col = frame_ % cols
        local row = math.floor(frame_ / cols)
        local patternW = drawW * (imgW / srcW)
        local patternH = drawH * (imgH / srcH)
        local cropLeftInFrame = (frameW - srcW) / 2 + srcOffX
        local cropTopInFrame = (frameH - srcH) / 2 + srcOffY
        local patternX = drawX - (col * frameW + cropLeftInFrame) * (patternW / imgW)
        local patternY = drawY - (row * frameH + cropTopInFrame) * (patternH / imgH)

        local paint = nvgImagePattern(nvg, patternX, patternY, patternW, patternH, 0, img, 1.0)
        nvgBeginPath(nvg)
        nvgRect(nvg, drawX, drawY, drawW, drawH)
        nvgFillPaint(nvg, paint)
        nvgFill(nvg)

        -- 帧边框
        nvgBeginPath(nvg)
        nvgRect(nvg, drawX, drawY, drawW, drawH)
        nvgStrokeColor(nvg, nvgRGBA(0, 255, 255, 150))
        nvgStrokeWidth(nvg, 2)
        nvgStroke(nvg)
    end

    -- 底部操作提示
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 13)
    nvgFillColor(nvg, nvgRGBA(180, 180, 180, 200))
    nvgText(nvg, 20, height - 20, "[O]关闭  [Tab]切类型  [1-9]切子类  [Q/E]动画  [A/D]帧  [W/S]参数  [/]]调值  [C/V]复制")
end

-- ============================================================================
-- 获取UI面板
-- ============================================================================

function SpriteEditor.GetPanel()
    return editorPanel_
end

-- ============================================================================
-- 获取敌人序列帧配置（供敌人渲染模块使用）
-- ============================================================================

function SpriteEditor.GetEnemySpriteConfig()
    return enemySpriteConfig_
end

-- ============================================================================
-- 复制配置到剪贴板
-- ============================================================================

local function FormatAnimConfig(key, cfg)
    local parts = {}
    table.insert(parts, string.format('    ["%s"] = { ', key))
    table.insert(parts, string.format('cropW = %.2f, cropH = %.2f, cropOffX = %.2f, cropOffY = %.2f, ',
        cfg.cropW or 1.0, cfg.cropH or 1.0, cfg.cropOffX or 0.0, cfg.cropOffY or 0.0))
    table.insert(parts, string.format('offsetX = %.2f, offsetY = %.2f',
        cfg.offsetX or 0.0, cfg.offsetY or 0.75))
    if cfg.scale then
        table.insert(parts, string.format(', scale = %.1f', cfg.scale))
    end
    table.insert(parts, ' },')
    return table.concat(parts)
end

function SpriteEditor.CopyCurrent()
    local animKeys = GetCurrentAnimKeys()
    local key = animKeys[animIdx_]
    local cfg = GetCurrentConfig()
    local text = FormatAnimConfig(key, cfg)
    ui:SetUseSystemClipboard(true)
    ui.clipboardText = text
    local entityName = SECONDARY_NAMES[primaryIdx_][secondaryIdx_]
    print("[SpriteEditor] 已复制 " .. entityName .. " 动画配置: " .. key)
end

function SpriteEditor.CopyAll()
    local animKeys = GetCurrentAnimKeys()
    local entityName = SECONDARY_NAMES[primaryIdx_][secondaryIdx_]
    local lines = { "-- " .. entityName .. " 序列帧配置" }

    if primaryIdx_ == 1 then
        -- 角色
        local config = getCharAnimCropConfig_(secondaryIdx_)
        table.insert(lines, "animCropConfig" .. secondaryIdx_ .. "_ = {")
        for i = 1, #animKeys do
            local key = animKeys[i]
            local cfg = config[key]
            if cfg then
                table.insert(lines, FormatAnimConfig(key, cfg))
            end
        end
        table.insert(lines, "}")
    else
        -- 敌人
        local typeKey = ENEMY_TYPE_KEYS[secondaryIdx_]
        table.insert(lines, 'enemySpriteConfig_["' .. typeKey .. '"] = {')
        for i = 1, #animKeys do
            local key = animKeys[i]
            local cfg = enemySpriteConfig_[typeKey] and enemySpriteConfig_[typeKey][key]
            if cfg then
                table.insert(lines, FormatAnimConfig(key, cfg))
            end
        end
        table.insert(lines, "}")
    end

    local text = table.concat(lines, "\n")
    ui:SetUseSystemClipboard(true)
    ui.clipboardText = text
    print("[SpriteEditor] 已复制 " .. entityName .. " 全部动画配置到剪贴板")
end

-- ============================================================================
-- 获取当前编辑摘要
-- ============================================================================

function SpriteEditor.GetCurrentSummary()
    local cfg = GetCurrentConfig()
    local animKeys = GetCurrentAnimKeys()
    local entityName = SECONDARY_NAMES[primaryIdx_][secondaryIdx_]
    return string.format("[%s] anim=%s scale=%.1f oX=%.2f oY=%.2f cW=%.2f cH=%.2f cOX=%.2f cOY=%.2f",
        entityName, animKeys[animIdx_], cfg.scale or 5.5,
        cfg.offsetX or 0, cfg.offsetY or 0.75,
        cfg.cropW or 1, cfg.cropH or 1,
        cfg.cropOffX or 0, cfg.cropOffY or 0)
end

return SpriteEditor
