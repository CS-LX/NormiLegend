-- ============================================================================
-- MenuFlow.lua
-- 菜单流程系统：过场、标题页、主菜单（Live2D视差）、功能面板、章节选择、图层编辑器
-- 从 TitleMenu.lua 提取，保持语义不变
-- ============================================================================
local S = require("GameState")
local UI = require("urhox-libs/UI")
local Video = require("urhox-libs/Video")
local GMConsole = require("GMConsole")
local SpriteEditor = require("SpriteEditor")
local ChapterIconEditor = require("menu.ChapterIconEditor")

local M = {}

-- 延迟引用 TitleMenu（避免循环依赖）
local TitleMenu_
local function getTitleMenu()
    if not TitleMenu_ then TitleMenu_ = require("TitleMenu") end
    return TitleMenu_
end

-- ============================================================================
-- 模块内部状态
-- ============================================================================
local transition_ = { active = false, timer = 0, onComplete = nil, uiRoot = nil }
local mainMenuTime_ = 0
local layerEditorData_ = nil
local uiLayerEditorData_ = nil
local uiImageLayers_ = nil
local menuPanelOverlay_ = nil
local layerEditorVisible_ = false
local layerEditorPanel_ = nil
local layerEditorToggle_ = nil
local layerEditorExport_ = nil

-- 角色面板图层编辑器状态
local charPanelLayers_ = nil       -- 角色面板图层定义数组
local charPanelContainer_ = nil    -- 角色面板图层容器
local charLayerEditorVisible_ = false
local charLayerEditorPanel_ = nil
local charLayerEditorToggle_ = nil
local charPanelTime_ = 0           -- 角色面板动画时间

-- ============================================================================
-- 关卡数据（共享给 TitleMenu 中的 LevelSelect/LevelEditor）
-- ============================================================================
local levelData_ = {}
for ch = 1, 4 do
    levelData_[ch] = {}
    for lv = 1, 8 do
        levelData_[ch][lv] = {
            name = "第" .. ch .. "-" .. lv .. "关",
            unlocked = (lv == 1),
            stars = 0,
            difficulty = 1,
            enemies = 3 + lv,
            timeLimit = 60 + lv * 10,
            reward = lv * 100,
            description = "",
        }
    end
end
M.levelData_ = levelData_

--- 替换关卡数据（外部导入时调用）
function M.SetLevelData(data)
    levelData_ = data
    M.levelData_ = data
end

-- ============================================================================
-- 过场系统
-- ============================================================================
--- 过场切换（直接执行回调，无遮罩）
function M.ShowTransition(onComplete)
    if onComplete then onComplete() end
end

function M.UpdateTransition(dt)
    if not transition_.active then return end

    transition_.timer = transition_.timer + dt

    if transition_.phase == "title_fadeout" then
        -- 标题页视频淡出（0.8秒）
        local fadeTime = 0.8
        local alpha = 1.0 - (transition_.timer / fadeTime)
        if alpha <= 0 then
            -- 淡出完成，销毁标题页和视频播放器
            if S.titleVideoPlayer then
                S.titleVideoPlayer:Destroy()
                S.titleVideoPlayer = nil
            end
            if S.titleUIRoot then
                S.titleUIRoot:Destroy()
                S.titleUIRoot = nil
            end
            transition_.active = false
            transition_.phase = nil
        else
            if S.titleUIRoot then
                S.titleUIRoot:SetStyle({ opacity = alpha })
            end
        end
    end
end

function M.IsTransitionActive()
    return transition_.active
end

-- ============================================================================
-- 标题视频页面
-- ============================================================================
function M.ShowTitleScreen()
    S.showTitleScreen = true

    -- 创建视频播放器（全屏循环播放，透明背景让底层尾帧透出）
    S.titleVideoPlayer = Video.VideoPlayer {
        src = "video/终.mp4",
        width = "100%",
        height = "100%",
        textureWidth = 1920,
        textureHeight = 1080,
        autoPlay = true,
        loop = true,
        muted = false,
        objectFit = "cover",
        backgroundColor = {0, 0, 0, 0},
    }

    -- 提示文本
    local hintLabel = UI.Label {
        id = "titleHint",
        text = "触摸屏幕开始游戏",
        fontSize = 20,
        fontColor = {255, 255, 255, 200},
        textAlign = "center",
    }

    -- 创建标题页UI根（覆盖全屏）
    S.titleUIRoot = UI.Panel {
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = {0, 0, 0, 255},
        children = {
            -- 视频尾帧静态图底层（循环间隙透出尾帧而非黑屏）
            UI.Panel {
                position = "absolute",
                top = 0, left = 0,
                width = "100%", height = "100%",
                backgroundImage = "image/title_last_frame.png",
                backgroundFit = "cover",
            },
            -- 视频层（覆盖在尾帧上方）
            UI.Panel {
                position = "absolute",
                top = 0, left = 0,
                width = "100%", height = "100%",
                children = { S.titleVideoPlayer },
            },
            -- 点击遮罩层（透明，接收点击/触摸事件）
            UI.Panel {
                position = "absolute",
                top = 0, left = 0,
                width = "100%", height = "100%",
                justifyContent = "flex-end",
                alignItems = "center",
                paddingBottom = 60,
                onClick = function()
                    M.DismissTitleScreen()
                end,
                children = {
                    hintLabel,
                }
            }
        }
    }
    UI.SetRoot(S.titleUIRoot)
end

function M.DismissTitleScreen()
    if not S.showTitleScreen then return end
    S.showTitleScreen = false

    -- 先加载主菜单（会调用 UI.SetRoot 替换掉标题页）
    M.ShowMainMenu()

    -- 将标题页叠加到主菜单上方作为淡出遮罩
    if S.titleUIRoot and S.mainMenuUIRoot then
        S.mainMenuUIRoot:AddChild(S.titleUIRoot)
    end

    -- 启动淡出动画
    transition_.active = true
    transition_.phase = "title_fadeout"
    transition_.timer = 0
end

-- ============================================================================
-- 主菜单界面（钢琴花园背景 + 右侧功能按钮面板）
-- ============================================================================
function M.ShowMainMenu()
    S.showMainMenu = true
    mainMenuTime_ = 0

    -- 克莱因蓝半透明色
    local KB = {0, 47, 167, 160}
    local KB_LIGHT = {0, 47, 167, 120}
    local KB_BORDER = {100, 140, 255, 100}

    -- Live2D 图层（从下到上）：背景 → 人物 → 帘子 → 风铃 → 紫藤花 → 钢琴
    -- 使用像素定位避免百分比字符串导致的加载闪烁
    -- 基准：1920×1080 设计分辨率，104% = 1997×1123，偏移按比例换算
    local BG_W = 1997
    local BG_H = 1123
    local layerBg = UI.Panel {
        id = "l2d_bg",
        position = "absolute", top = 0, left = 0,
        width = BG_W, height = BG_H,
        backgroundImage = "image/主界面背景图/背景.png",
        backgroundFit = "cover",
        pointerEvents = "none",
    }
    local layerChar = UI.Panel {
        id = "l2d_char",
        position = "absolute", top = 0, left = -10,
        width = BG_W, height = BG_H,
        backgroundImage = "image/主界面背景图/人物1.png",
        backgroundFit = "cover",
        pointerEvents = "none",
    }
    local layerCurtain = UI.Panel {
        id = "l2d_curtain",
        position = "absolute", top = 0, left = -58,
        width = BG_W, height = BG_H,
        backgroundImage = "image/主界面背景图/帘子.png",
        backgroundFit = "cover",
        pointerEvents = "none",
    }
    local layerChime = UI.Panel {
        id = "l2d_chime",
        position = "absolute", top = 0, left = -58,
        width = BG_W, height = BG_H,
        backgroundImage = "image/主界面背景图/风铃.png",
        backgroundFit = "cover",
        pointerEvents = "none",
    }
    local layerWisteria = UI.Panel {
        id = "l2d_wisteria",
        position = "absolute", top = 0, left = -10,
        width = BG_W, height = BG_H,
        backgroundImage = "image/主界面背景图/紫藤花.png",
        backgroundFit = "cover",
        pointerEvents = "none",
    }
    local layerPiano = UI.Panel {
        id = "l2d_piano",
        position = "absolute", top = -32, left = -58,
        width = BG_W, height = BG_H,
        backgroundImage = "image/主界面背景图/钢琴.png",
        backgroundFit = "cover",
        pointerEvents = "none",
    }

    -- 花瓣粒子容器（最前层，钢琴之上、UI之下）
    local petalContainer = UI.Panel {
        id = "l2d_petals",
        position = "absolute", top = 0, left = 0,
        width = "100%", height = "100%",
        pointerEvents = "none",
    }
    -- 创建6个紫色花瓣
    for i = 1, 6 do
        petalContainer:AddChild(UI.Panel {
            id = "petal_" .. i,
            position = "absolute",
            width = 5, height = 5,
            borderRadius = 3,
            backgroundColor = {180, 140, 220, math.random(120, 200)},
            top = tostring(math.random(0, 80)) .. "%",
            left = tostring(math.random(-10, 100)) .. "%",
            pointerEvents = "none",
        })
    end

    -- ===== 主界面UI图片图层（按z-order从下到上） =====
    -- 图层顺序: 背景 → 图标 → 高亮 → 角色蓝框 → 文字 → 总体高亮
    -- UI容器（承载所有UI图片，覆盖在背景图层之上）
    local uiLayerContainer = UI.Panel {
        id = "ui_layer_container",
        position = "absolute", top = 0, left = 0,
        width = "100%", height = "100%",
        pointerEvents = "none",
    }

    -- 定义UI图片数据（按图层从下到上排列）
    -- 每项: { name=显示名, id=唯一id, file=图片路径, w=原始宽, h=原始高, top=初始top(px), left=初始left(px) }
    ---@type {name:string, id:string, file:string, w:number, h:number, top:number, left:number}[]
    uiImageLayers_ = {
        -- 第1层: 背景
        { name = "任务背景",   id = "ui_任务背景",   file = "image/主界面ui/任务背景.png",   w = 433, h = 656, top = 95, left = 1040 },
        { name = "探索背景",   id = "ui_探索背景",   file = "image/主界面ui/探索背景.png",   w = 234, h = 747, top = 100, left = 1610 },
        { name = "角色背景",   id = "ui_角色背景",   file = "image/主界面ui/角色背景.png",   w = 180, h = 643, top = 110, left = 1405 },
        -- 第2层: 图标
        { name = "任务图标",   id = "ui_任务图标",   file = "image/主界面ui/任务图标.png",   w = 171, h = 623, top = 110, left = 1205 },
        { name = "探索图标",   id = "ui_探索图标",   file = "image/主界面ui/探索图标.png",   w = 280, h = 466, top = 380, left = 1600 },
        { name = "角色图标",   id = "ui_角色图标",   file = "image/主界面ui/角色图标.png",   w = 245, h = 221, top = 115, left = 1375 },
        -- 第3层: 高亮（探索高亮、角色高亮）
        { name = "探索高亮",   id = "ui_探索高亮",   file = "image/主界面ui/探索高亮.png",   w = 263, h = 388, top = 460, left = 1600 },
        { name = "角色高亮",   id = "ui_角色高亮",   file = "image/主界面ui/角色高亮.png",   w = 210, h = 564, top = 115, left = 1380 },
        -- 第4层: 角色蓝框（角色高亮上层，角色文字下层）
        { name = "角色蓝框",   id = "ui_角色蓝框",   file = "image/主界面ui/角色蓝框.png",   w = 104, h = 123, top = 260, left = 1530 },
        -- 第5层: 总体高亮（文字下层）
        { name = "总体高亮",   id = "ui_总体高亮",   file = "image/主界面ui/总体高亮.png",   w = 1840, h = 1035, top = 10, left = 75 },
        -- 第6层: 文字（最顶层）
        { name = "任务文字",   id = "ui_任务文字",   file = "image/主界面ui/任务文字.png",   w = 176, h = 388, top = 145, left = 1165 },
        { name = "探索文字",   id = "ui_探索文字",   file = "image/主界面ui/探索文字.png",   w = 284, h = 337, top = 60, left = 1625 },
        { name = "角色文字",   id = "ui_角色文字",   file = "image/主界面ui/角色文字.png",   w = 422, h = 377, top = 265, left = 1185 },
    }

    -- 创建所有UI图片图层
    for _, layer in ipairs(uiImageLayers_) do
        local isTextLayer = layer.id:find("文字") ~= nil
        local panel = UI.Panel {
            id = layer.id,
            position = "absolute",
            top = layer.top, left = layer.left,
            width = layer.w, height = layer.h,
            backgroundImage = layer.file,
            backgroundFit = "contain",
            pointerEvents = "none",
            transition = isTextLayer and "all 0.25s easeOut" or nil,
        }
        uiLayerContainer:AddChild(panel)
    end

    -- 右侧三个功能区域的点击热区（任务/角色/探索）
    local menuPanel = UI.Panel {
        id = "mainMenuPanel",
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        pointerEvents = "box-none",
        children = {
            -- 任务热区（左侧卡片）
            UI.Button {
                id = "hotspot_task",
                position = "absolute", top = 127, left = 1161,
                width = 202, height = 594,
                backgroundColor = {0,0,0,0},
                onClick = function() M.ShowMenuPanel("task") end,
                onPointerEnter = function()
                    local w = uiLayerContainer:FindById("ui_任务文字")
                    if w then w:SetStyle({ scale = 1.08 }) end
                end,
                onPointerLeave = function()
                    local w = uiLayerContainer:FindById("ui_任务文字")
                    if w then w:SetStyle({ scale = 1.0 }) end
                end,
            },
            -- 角色热区（中间卡片）
            UI.Button {
                id = "hotspot_char",
                position = "absolute", top = 107, left = 1411,
                width = 184, height = 643,
                backgroundColor = {0,0,0,0},
                onClick = function() M.ShowMenuPanel("character") end,
                onPointerEnter = function()
                    local w = uiLayerContainer:FindById("ui_角色文字")
                    if w then w:SetStyle({ scale = 1.08 }) end
                end,
                onPointerLeave = function()
                    local w = uiLayerContainer:FindById("ui_角色文字")
                    if w then w:SetStyle({ scale = 1.0 }) end
                end,
            },
            -- 探索热区（右侧卡片）
            UI.Button {
                id = "hotspot_explore",
                position = "absolute", top = 100, left = 1623,
                width = 202, height = 710,
                backgroundColor = {0,0,0,0},
                onClick = function() M.EnterGameFromMenu() end,
                onPointerEnter = function()
                    local w = uiLayerContainer:FindById("ui_探索文字")
                    if w then w:SetStyle({ scale = 1.08 }) end
                end,
                onPointerLeave = function()
                    local w = uiLayerContainer:FindById("ui_探索文字")
                    if w then w:SetStyle({ scale = 1.0 }) end
                end,
            },
        },
    }

    -- 主菜单UI（图层堆叠）
    S.mainMenuUIRoot = UI.Panel {
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        overflow = "hidden",
        children = {
            layerBg,
            layerChar,
            layerCurtain,
            layerChime,
            layerWisteria,
            layerPiano,
            petalContainer,
            uiLayerContainer,
            menuPanel,
            -- 左上角返回标题按钮
            UI.Button {
                position = "absolute",
                top = 16, left = 16,
                text = "< 返回", fontSize = 14,
                fontColor = {255, 255, 255, 220},
                backgroundColor = {0, 0, 0, 120},
                borderRadius = 6,
                paddingLeft = 12, paddingRight = 12,
                paddingTop = 6, paddingBottom = 6,
                onClick = function()
                    S.showMainMenu = false
                    S.mainMenuUIRoot = nil
                    M.ShowTransition(function() M.ShowTitleScreen() end)
                end,
            },
        },
    }
    UI.SetRoot(S.mainMenuUIRoot)
    -- 存储引用供动画使用
    S.mainMenuUIRoot.menuPanel = menuPanel
    S.mainMenuUIRoot.layerBg = layerBg
    S.mainMenuUIRoot.layerChar = layerChar
    S.mainMenuUIRoot.layerCurtain = layerCurtain
    S.mainMenuUIRoot.layerChime = layerChime
    S.mainMenuUIRoot.layerWisteria = layerWisteria
    S.mainMenuUIRoot.layerPiano = layerPiano
    S.mainMenuUIRoot.petalContainer = petalContainer
    S.mainMenuUIRoot.uiLayerContainer = uiLayerContainer

    -- ===== 图层位置编辑器 =====
    -- Live2D背景图层数据（像素单位，与面板初始化一致，避免百分比字符串闪烁）
    ---@type {name:string, id:string, top:number, left:number, unit:string}[]
    layerEditorData_ = {
        { name = "背景",    id = "l2d_bg",        top = 0, left = 0, unit = "px" },
        { name = "人物",    id = "l2d_char",      top = 0, left = -10, unit = "px" },
        { name = "帘子",    id = "l2d_curtain",   top = 0, left = -58, unit = "px" },
        { name = "风铃",    id = "l2d_chime",     top = 0, left = -58, unit = "px" },
        { name = "紫藤花",  id = "l2d_wisteria",  top = 0, left = -10, unit = "px" },
        { name = "钢琴",    id = "l2d_piano",     top = -32, left = -58, unit = "px" },
    }
    -- UI图片图层数据（像素单位，支持上下移动图层顺序）
    ---@type {name:string, id:string, top:number, left:number, unit:string}[]
    uiLayerEditorData_ = {}
    for _, layer in ipairs(uiImageLayers_) do
        table.insert(uiLayerEditorData_, { name = layer.name, id = layer.id, top = layer.top, left = layer.left, unit = "px" })
    end

    layerEditorVisible_ = false
    M.BuildLayerEditor()
end

-- ============================================================================
-- 主菜单功能面板（任务/角色）
-- ============================================================================

--- 显示功能面板
---@param panelType "task"|"character"
function M.ShowMenuPanel(panelType)
    if menuPanelOverlay_ then
        M.CloseMenuPanel()
    end

    if panelType == "character" then
        M.ShowCharacterPanel()
        return
    end

    -- 任务面板仍为占位
    local title = "任务"
    menuPanelOverlay_ = UI.Panel {
        id = "menu_panel_overlay",
        position = "absolute", top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = {0, 0, 0, 120},
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Panel {
                width = 800, height = 500,
                backgroundColor = {20, 30, 60, 200},
                borderRadius = 16,
                justifyContent = "center", alignItems = "center",
                children = {
                    UI.Label {
                        text = title .. "（开发中）",
                        fontSize = 28, fontColor = {255, 255, 255, 220},
                    },
                    UI.Label {
                        text = "按 ESC 关闭",
                        fontSize = 16, fontColor = {180, 180, 200, 180},
                        marginTop = 20,
                    },
                },
            },
        },
        onClick = function()
            M.CloseMenuPanel()
        end,
    }
    S.mainMenuUIRoot:AddChild(menuPanelOverlay_)
end

--- 关闭当前功能面板
function M.CloseMenuPanel()
    if menuPanelOverlay_ then
        menuPanelOverlay_:Destroy()
        menuPanelOverlay_ = nil
    end
    -- 关闭角色面板图层编辑器
    if charLayerEditorPanel_ then
        charLayerEditorPanel_:Destroy()
        charLayerEditorPanel_ = nil
    end
    if charLayerEditorToggle_ then
        charLayerEditorToggle_:Destroy()
        charLayerEditorToggle_ = nil
    end
    charPanelContainer_ = nil
    charLayerEditorVisible_ = false
end

--- 主菜单面板是否打开
function M.IsMenuPanelOpen()
    return menuPanelOverlay_ ~= nil
end

-- ============================================================================
-- 章节选择界面（横屏轮播）
-- ============================================================================
local chapterSelect_ = {
    active = false,
    uiRoot = nil,
    currentIndex = 1,       -- 当前选中章节（1~4）
    targetIndex = 1,        -- 目标章节（动画过渡用）
    animTimer = 0,          -- 动画计时器
    animating = false,      -- 是否正在过渡动画中
    cards = {},             -- 章节卡片引用
    dragStartX = nil,       -- 拖拽起始X
}

local CHAPTER_DATA = {
    { name = "第一章", color = {80, 130, 200, 255} },
    { name = "第二章", color = {130, 80, 180, 255} },
    { name = "第三章", color = {180, 100, 80, 255} },
    { name = "第四章", color = {80, 160, 120, 255} },
}
M.CHAPTER_DATA = CHAPTER_DATA

local CARD_W = 320          -- 选中卡片宽度
local CARD_H = 420          -- 选中卡片高度
local CARD_SCALE_SIDE = 0.65 -- 两侧卡片缩放
local CARD_GAP = 560         -- 卡片中心间距（扩大两倍）
local ANIM_DURATION = 0.3    -- 切换动画时长（秒）

--- 显示章节选择界面
function M.ShowChapterSelect()
    if chapterSelect_.uiRoot then
        chapterSelect_.uiRoot:Destroy()
    end
    chapterSelect_.active = true
    chapterSelect_.currentIndex = 1
    chapterSelect_.targetIndex = 1
    chapterSelect_.animTimer = 0
    chapterSelect_.animating = false
    chapterSelect_.cards = {}

    -- 背景（半透明深色渐变）
    local bg = UI.Panel {
        position = "absolute", top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = {15, 12, 30, 240},
    }

    -- 标题
    local title = UI.Label {
        text = "选择章节",
        fontSize = 28,
        fontColor = {220, 220, 240, 255},
        position = "absolute", top = 40, left = 0,
        width = "100%", textAlign = "center",
    }

    -- 章节卡片容器（居中）
    local cardContainer = UI.Panel {
        id = "chapter_card_container",
        position = "absolute", top = 0, left = 0,
        width = "100%", height = "100%",
        pointerEvents = "box-none",
    }

    -- 创建4张章节卡片（可点击切换）
    for i, chap in ipairs(CHAPTER_DATA) do
        local idx = i
        -- 尝试加载章节图标图层配置
        ChapterIconEditor.LoadFromFile(idx)
        local hasIconLayers = ChapterIconEditor.GetLayers(idx) ~= nil

        local card
        if hasIconLayers then
            -- 有图层的章节：使用 Panel（无悬停高亮），不裁剪溢出
            card = UI.Panel {
                id = "chapter_card_" .. i,
                position = "absolute",
                width = CARD_W, height = CARD_H,
                backgroundColor = {20, 18, 35, 255},
                borderRadius = 16,
                justifyContent = "center",
                alignItems = "center",
            }

            -- 图层容器（允许溢出显示）
            local layerContainer = ChapterIconEditor.BuildCardLayers(idx, CARD_W, CARD_H)
            if layerContainer then
                card:AddChild(layerContainer)
            end

            -- 章节名（底部）
            card:AddChild(UI.Label {
                text = chap.name,
                fontSize = 16,
                fontColor = {255, 255, 255, 180},
                textAlign = "center",
                pointerEvents = "none",
                position = "absolute",
                bottom = 12, left = 0, width = "100%",
            })

            -- 透明点击按钮（无悬停高亮，但检测 hover 用于动画）
            card:AddChild(UI.Panel {
                id = "chapter_click_" .. i,
                position = "absolute", top = 0, left = 0,
                width = "100%", height = "100%",
                borderRadius = 16,
                pointerEvents = "auto",
                onClick = function()
                    if chapterSelect_.animating then return end
                    if idx ~= chapterSelect_.currentIndex then
                        chapterSelect_.targetIndex = idx
                        chapterSelect_.animTimer = 0
                        chapterSelect_.animating = true
                    else
                        getTitleMenu().ShowLevelSelect(idx)
                    end
                end,
                onPointerEnter = function()
                    if idx == 1 then
                        ChapterIconEditor.SetHovered(true)
                    end
                end,
                onPointerLeave = function()
                    if idx == 1 then
                        ChapterIconEditor.SetHovered(false)
                    end
                end,
            })
        else
            -- 无图层的章节：使用普通 Button
            card = UI.Button {
                id = "chapter_card_" .. i,
                position = "absolute",
                width = CARD_W, height = CARD_H,
                backgroundColor = chap.color,
                borderRadius = 16,
                justifyContent = "center",
                alignItems = "center",
                overflow = "hidden",
                children = {
                    UI.Label {
                        text = chap.name,
                        fontSize = 36,
                        fontColor = {255, 255, 255, 255},
                        textAlign = "center",
                        pointerEvents = "none",
                    },
                },
                onClick = function()
                    if chapterSelect_.animating then return end
                    if idx ~= chapterSelect_.currentIndex then
                        chapterSelect_.targetIndex = idx
                        chapterSelect_.animTimer = 0
                        chapterSelect_.animating = true
                    else
                        getTitleMenu().ShowLevelSelect(idx)
                    end
                end,
            }
        end

        cardContainer:AddChild(card)
        chapterSelect_.cards[i] = card
    end

    -- 番外篇按钮（右上角）
    local extraBtn = UI.Button {
        position = "absolute", top = 36, right = 40,
        paddingLeft = 20, paddingRight = 20,
        paddingTop = 10, paddingBottom = 10,
        backgroundColor = {100, 80, 160, 200},
        borderRadius = 8,
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Label { text = "番外篇", fontSize = 16, fontColor = {255, 255, 255, 255} },
        },
        onClick = function()
            M.CloseChapterSelect()
            M.EnterGameWorld()
        end,
    }

    -- 返回按钮（左上角）
    local backBtn = UI.Button {
        position = "absolute", top = 36, left = 40,
        paddingLeft = 16, paddingRight = 16,
        paddingTop = 10, paddingBottom = 10,
        backgroundColor = {60, 60, 80, 200},
        borderRadius = 8,
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Label { text = "< 返回", fontSize = 16, fontColor = {200, 200, 220, 255} },
        },
        onClick = function()
            M.CloseChapterSelect()
        end,
    }

    -- 左右箭头提示
    local arrowLeft = UI.Button {
        id = "chapter_arrow_left",
        position = "absolute", top = "45%", left = 40,
        width = 48, height = 48,
        backgroundColor = {255, 255, 255, 40},
        borderRadius = 24,
        justifyContent = "center", alignItems = "center",
        children = { UI.Label { text = "<", fontSize = 24, fontColor = {255, 255, 255, 200} } },
        onClick = function() M.ChapterNavigate(-1) end,
    }
    local arrowRight = UI.Button {
        id = "chapter_arrow_right",
        position = "absolute", top = "45%", right = 40,
        width = 48, height = 48,
        backgroundColor = {255, 255, 255, 40},
        borderRadius = 24,
        justifyContent = "center", alignItems = "center",
        children = { UI.Label { text = ">", fontSize = 24, fontColor = {255, 255, 255, 200} } },
        onClick = function() M.ChapterNavigate(1) end,
    }

    -- 底部指示点
    local dotsContainer = UI.Panel {
        id = "chapter_dots",
        position = "absolute", bottom = 60, left = 0,
        width = "100%", height = 20,
        flexDirection = "row",
        justifyContent = "center", alignItems = "center",
        gap = 12, pointerEvents = "none",
    }
    for i = 1, #CHAPTER_DATA do
        dotsContainer:AddChild(UI.Panel {
            id = "chapter_dot_" .. i,
            width = 10, height = 10,
            borderRadius = 5,
            backgroundColor = (i == 1) and {255, 255, 255, 255} or {255, 255, 255, 80},
        })
    end

    chapterSelect_.uiRoot = UI.Panel {
        position = "absolute", top = 0, left = 0,
        width = "100%", height = "100%",
        children = { bg, cardContainer, title, extraBtn, backBtn, arrowLeft, arrowRight, dotsContainer },
    }

    -- 初始布局卡片
    M.LayoutChapterCards(1.0)

    S.mainMenuUIRoot:AddChild(chapterSelect_.uiRoot)

    -- 初始化章节图标编辑器
    ChapterIconEditor.Init(chapterSelect_.uiRoot, chapterSelect_.cards)
end

--- 关闭章节选择界面
function M.CloseChapterSelect()
    chapterSelect_.active = false
    ChapterIconEditor.Destroy()
    if chapterSelect_.uiRoot then
        chapterSelect_.uiRoot:Destroy()
        chapterSelect_.uiRoot = nil
    end
    chapterSelect_.cards = {}
end

--- 章节选择是否打开
function M.IsChapterSelectOpen()
    return chapterSelect_.active
end

--- 导航到目标章节（direction: -1=左, 1=右）
function M.ChapterNavigate(direction)
    if chapterSelect_.animating then return end
    local newIdx = chapterSelect_.currentIndex + direction
    if newIdx < 1 or newIdx > #CHAPTER_DATA then return end
    chapterSelect_.targetIndex = newIdx
    chapterSelect_.animTimer = 0
    chapterSelect_.animating = true
end

--- 布局章节卡片（progress: 0~1 动画进度，基于 currentIndex 到 targetIndex）
function M.LayoutChapterCards(progress)
    local screenW = 1920
    local screenH = 1080
    local centerX = screenW / 2
    local centerY = screenH / 2

    -- 插值当前位置
    local fromIdx = chapterSelect_.currentIndex
    local toIdx = chapterSelect_.targetIndex
    local activePos = fromIdx + (toIdx - fromIdx) * progress

    for i, card in ipairs(chapterSelect_.cards) do
        -- 相对于当前活跃位置的偏移
        local offset = i - activePos
        -- 位置
        local cx = centerX + offset * CARD_GAP
        -- 缩放：居中=1.0，偏移越远越小
        local scaleFactor = 1.0 - math.min(math.abs(offset), 2) * (1.0 - CARD_SCALE_SIDE)
        scaleFactor = math.max(scaleFactor, CARD_SCALE_SIDE * 0.6)
        -- 透明度：居中=1.0，远处渐隐
        local alpha = 1.0 - math.min(math.abs(offset), 2) * 0.35
        alpha = math.max(alpha, 0.3)

        local cardW = CARD_W * scaleFactor
        local cardH = CARD_H * scaleFactor
        local cardLeft = cx - cardW / 2
        local cardTop = centerY - cardH / 2

        card:SetStyle({
            left = cardLeft,
            top = cardTop,
            width = cardW,
            height = cardH,
            opacity = alpha,
        })

        -- 章节1图层容器跟随卡片缩放
        if i == 1 then
            ChapterIconEditor.SetCardScale(scaleFactor)
        end
    end

    -- 更新指示点
    if chapterSelect_.uiRoot then
        local nearestIdx = math.floor(activePos + 0.5)
        for i = 1, #CHAPTER_DATA do
            local dot = chapterSelect_.uiRoot:FindById("chapter_dot_" .. i)
            if dot then
                dot:SetStyle({
                    backgroundColor = (i == nearestIdx) and {255, 255, 255, 255} or {255, 255, 255, 80},
                    width = (i == nearestIdx) and 12 or 10,
                    height = (i == nearestIdx) and 12 or 10,
                    borderRadius = (i == nearestIdx) and 6 or 5,
                })
            end
        end
    end
end

--- 章节选择动画更新（每帧调用）
function M.UpdateChapterSelect(dt)
    if not chapterSelect_.active then return end

    -- 更新章节图标图层动画（呼吸 + 悬停）
    ChapterIconEditor.Update(dt)

    -- 处理滑动手势
    if input:GetMouseButtonDown(MOUSEB_LEFT) then
        if chapterSelect_.dragStartX == nil then
            chapterSelect_.dragStartX = input.mousePosition.x
        end
    elseif chapterSelect_.dragStartX then
        -- 松手时判断滑动方向
        local dx = input.mousePosition.x - chapterSelect_.dragStartX
        chapterSelect_.dragStartX = nil
        if not chapterSelect_.animating then
            if dx < -80 then
                M.ChapterNavigate(1)   -- 向左滑 = 下一章
            elseif dx > 80 then
                M.ChapterNavigate(-1)  -- 向右滑 = 上一章
            end
        end
    end

    -- 切换动画
    if chapterSelect_.animating then
        chapterSelect_.animTimer = chapterSelect_.animTimer + dt
        local progress = math.min(chapterSelect_.animTimer / ANIM_DURATION, 1.0)
        -- easeOut 缓动
        local eased = 1.0 - (1.0 - progress) * (1.0 - progress)
        M.LayoutChapterCards(eased)
        if progress >= 1.0 then
            chapterSelect_.animating = false
            chapterSelect_.currentIndex = chapterSelect_.targetIndex
        end
    end
end

-- ============================================================================
-- 从主菜单进入关卡选择（游戏主界面）
-- ============================================================================
--- 点击探索 → 显示章节选择
function M.EnterGameFromMenu()
    M.ShowChapterSelect()
end

--- 从章节选择进入游戏世界（番外篇 / 地图页面）
function M.EnterGameWorld()
    S.showMainMenu = false
    S.mainMenuUIRoot = nil
    S.enteredGameFromChapterSelect = true  -- 标记来源，ESC返回章节选择

    -- 过场后切换到游戏界面
    M.ShowTransition(function()
        local uiRoot = UI.Panel {
            width = "100%", height = "100%",
            pointerEvents = "box-none",
            children = { S.backButton, S.topButtonBar, S.mapBackButton, S.skillButtonPanel, S.charSwitchPanel, S.skillPanelUI, S.inventoryPanelUI, S.escPopupUI, SpriteEditor.GetPanel() }
        }
        UI.SetRoot(uiRoot)

        -- 重新挂载GM控制台面板
        local gmPanel, gmExportPanel = GMConsole.CreateUI()
        if gmPanel then uiRoot:AddChild(gmPanel) end
        if gmExportPanel then uiRoot:AddChild(gmExportPanel) end
    end)
end

--- 从游戏世界返回章节选择（番外篇退出用）
function M.ReturnToChapterSelect()
    S.enteredGameFromChapterSelect = false
    M.ShowTransition(function()
        M.ShowMainMenu()
        M.ShowChapterSelect()
    end)
end

-- ============================================================================
-- Live2D 视差动画更新（每帧调用）
-- ============================================================================
function M.UpdateMainMenuAnimation(dt)
    if not S.showMainMenu then return end

    -- 子面板打开时：只运行角色面板视差，跳过主界面背景视差
    if menuPanelOverlay_ then
        M.UpdateCharPanelParallax(dt)
        return
    end

    if not S.mainMenuUIRoot or not S.mainMenuUIRoot.menuPanel then return end

    mainMenuTime_ = mainMenuTime_ + dt
    local t = mainMenuTime_

    -- 鼠标视差（各层不同深度）
    local screenW = graphics:GetWidth()
    local screenH = graphics:GetHeight()
    local mx = input.mousePosition.x
    local my = input.mousePosition.y
    local nx = (mx - screenW * 0.5) / (screenW * 0.5)
    local ny = (my - screenH * 0.5) / (screenH * 0.5)

    -- 从编辑器数据读取 base 位置（像素单位，允许实时调整）
    local edBg   = layerEditorData_ and layerEditorData_[1] or { top = 0, left = 0 }
    local edChar  = layerEditorData_ and layerEditorData_[2] or { top = 0, left = -10 }
    local edCurt  = layerEditorData_ and layerEditorData_[3] or { top = 0, left = -58 }
    local edChime = layerEditorData_ and layerEditorData_[4] or { top = 0, left = -58 }
    local edWist  = layerEditorData_ and layerEditorData_[5] or { top = 0, left = -10 }
    local edPiano = layerEditorData_ and layerEditorData_[6] or { top = -32, left = -58 }

    -- 百分比→像素换算系数（基于1920×1080设计分辨率）
    local PX = 19.2   -- 1% 水平 = 19.2px
    local PY = 10.8   -- 1% 垂直 = 10.8px

    -- 背景层视差（减弱）
    local bgOx = -nx * 1
    local bgOy = -ny * 1.5
    S.mainMenuUIRoot.layerBg:SetStyle({
        top = edBg.top + bgOy * 0.06 * PY,
        left = edBg.left + bgOx * 0.06 * PX,
    })

    -- 人物层：呼吸+微晃头（视差减弱）
    local charBreath = math.sin(t * 1.2) * 0.15
    local charHeadSway = math.sin(t * 0.4) * 0.2
    local charParX = -nx * 0.8
    local charParY = -ny * 0.4
    S.mainMenuUIRoot.layerChar:SetStyle({
        top = edChar.top + (charBreath * 0.15 + charParY * 0.02) * PY,
        left = edChar.left + (charHeadSway * 0.1 + charParX * 0.02) * PX,
    })

    -- 帘子层：轻微摆动（视差减弱）
    local curtainSway = math.sin(t * 0.8) * 0.4 + math.sin(t * 1.3) * 0.2
    local curtainParX = -nx * 1
    local curtainParY = -ny * 0.4
    S.mainMenuUIRoot.layerCurtain:SetStyle({
        top = edCurt.top + (math.sin(t * 0.6) * 0.2 + curtainParY * 0.02) * PY,
        left = edCurt.left + (curtainSway * 0.25 + curtainParX * 0.02) * PX,
    })

    -- 风铃层：随风摆动（纵向视差增强）
    local chimeSway = math.sin(t * 1.5) * 1.5 + math.sin(t * 2.3) * 0.8 + math.sin(t * 3.1) * 0.4
    local chimeParX = -nx * 5
    local chimeParY = -ny * 8
    S.mainMenuUIRoot.layerChime:SetStyle({
        top = edChime.top + (math.abs(math.sin(t * 1.5)) * 0.6 + chimeParY * 0.12) * PY,
        left = edChime.left + (chimeSway * 0.5 + chimeParX * 0.06) * PX,
    })

    -- 紫藤花层：缓慢摆动（纵向视差增强）
    local wistSway = math.sin(t * 0.5) * 1.2 + math.sin(t * 0.8) * 0.7 + math.sin(t * 1.2) * 0.3
    local wistParX = -nx * 3
    local wistParY = -ny * 5
    S.mainMenuUIRoot.layerWisteria:SetStyle({
        top = edWist.top + (math.sin(t * 0.3) * 0.4 + wistParY * 0.1) * PY,
        left = edWist.left + (wistSway * 0.4 + wistParX * 0.05) * PX,
    })

    -- 钢琴层：前景（视差减弱）
    local pianoParX = -nx * 0.8
    local pianoParY = -ny * 0.3
    S.mainMenuUIRoot.layerPiano:SetStyle({
        top = edPiano.top + pianoParY * 0.02 * PY,
        left = edPiano.left + pianoParX * 0.02 * PX,
    })



    -- 花瓣粒子动画（6个花瓣，向右下飘落）
    if S.mainMenuUIRoot.petalContainer then
        for i = 1, 6 do
            local petal = S.mainMenuUIRoot.petalContainer:FindById("petal_" .. i)
            if petal then
                -- 每个花瓣有不同速度和起始相位
                local speed = 0.8 + (i * 0.3)
                local phase = i * 1.2
                -- 水平：向右飘（风向右）
                local px = ((t * speed * 8 + phase * 30) % 130) - 15
                -- 垂直：缓慢下落 + 轻微波动
                local py = ((t * speed * 3 + phase * 20) % 110) - 5
                local wave = math.sin(t * 2 + phase) * 3
                petal:SetStyle({
                    left = tostring(px) .. "%",
                    top = tostring(py + wave * 0.5) .. "%",
                    opacity = (py > 90) and 0 or 1,
                })
            end
        end
    end

    -- UI图片图层视差 + 呼吸浮动（不同层深度不同，越靠上层视差越大）
    if S.mainMenuUIRoot.uiLayerContainer and uiImageLayers_ and uiLayerEditorData_ then
        local layerCount = #uiImageLayers_
        for idx, layer in ipairs(uiImageLayers_) do
            local widget = S.mainMenuUIRoot.uiLayerContainer:FindById(layer.id)
            if widget then
                -- 深度因子：底层(idx=1)=0.2, 顶层(idx=max)=1.0
                -- 总体高亮与背景层一致（固定最小深度）
                local depth
                if layer.id == "ui_总体高亮" then
                    depth = 0.2
                else
                    depth = 0.2 + 0.8 * ((idx - 1) / math.max(layerCount - 1, 1))
                end
                local parX = -nx * 28 * depth   -- 水平视差（底层~6px, 顶层~28px）
                local parY = -ny * 2 * depth    -- 垂直轻微

                -- 呼吸浮动：每层有不同相位，轻微上下浮动（振幅3~6px）
                local breathPhase = idx * 0.7
                local breathAmp = 3 + depth * 3  -- 底层~3px, 顶层~6px
                local breathOffset = math.sin(t * 0.8 + breathPhase) * breathAmp

                local ed = uiLayerEditorData_[idx]
                local baseTop = ed and ed.top or layer.top
                local baseLeft = ed and ed.left or layer.left
                widget:SetStyle({
                    top = baseTop + parY + breathOffset,
                    left = baseLeft + parX,
                })
            end
        end
    end
end

-- ============================================================================
-- 图层位置编辑器（调试用）- 支持背景图层 + UI图片图层 + 图层上下移动
-- ============================================================================
function M.BuildLayerEditor()
    if layerEditorPanel_ then
        layerEditorPanel_:Destroy()
        layerEditorPanel_ = nil
    end

    -- 切换按钮（始终可见）
    local toggleBtn = UI.Button {
        position = "absolute", bottom = 16, left = 16,
        text = "图层编辑", fontSize = 12,
        fontColor = {255, 255, 255, 220},
        backgroundColor = {0, 0, 0, 180},
        borderRadius = 4,
        paddingLeft = 8, paddingRight = 8,
        paddingTop = 4, paddingBottom = 4,
        onClick = function()
            layerEditorVisible_ = not layerEditorVisible_
            M.RefreshLayerEditor()
        end,
    }
    S.mainMenuUIRoot:AddChild(toggleBtn)
    layerEditorToggle_ = toggleBtn

    -- 编辑面板（滚动区域）
    layerEditorPanel_ = UI.Panel {
        id = "layerEditorPanel",
        position = "absolute", bottom = 50, left = 16,
        width = 360, maxHeight = "85%",
        backgroundColor = {0, 0, 0, 210},
        borderRadius = 8,
        paddingTop = 10, paddingBottom = 10,
        paddingLeft = 10, paddingRight = 10,
        flexDirection = "column", gap = 4,
        overflow = "scroll",
        display = "none",
    }
    S.mainMenuUIRoot:AddChild(layerEditorPanel_)
    M.RefreshLayerEditor()
end

function M.RefreshLayerEditor()
    if not layerEditorPanel_ then return end
    layerEditorPanel_:ClearChildren()

    if not layerEditorVisible_ then
        layerEditorPanel_:SetStyle({ display = "none" })
        return
    end
    layerEditorPanel_:SetStyle({ display = "flex" })

    -- ===== 背景图层区域 =====
    layerEditorPanel_:AddChild(UI.Label {
        text = "◆ 背景图层（视差）", fontSize = 13,
        fontColor = {150, 200, 255, 255}, marginBottom = 2,
    })
    for i, layer in ipairs(layerEditorData_) do
        layerEditorPanel_:AddChild(M.CreateBgLayerRow(i, layer))
    end

    -- ===== UI图片图层区域 =====
    layerEditorPanel_:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {100,100,100,100}, marginTop = 6, marginBottom = 6 })
    layerEditorPanel_:AddChild(UI.Label {
        text = "◆ UI图片图层（从下到上）", fontSize = 13,
        fontColor = {255, 200, 150, 255}, marginBottom = 2,
    })
    for i, layer in ipairs(uiLayerEditorData_) do
        layerEditorPanel_:AddChild(M.CreateUILayerRow(i, layer))
    end

    -- 导出按钮
    layerEditorPanel_:AddChild(UI.Button {
        text = "导出数据", fontSize = 12, marginTop = 8,
        width = "100%", height = 28,
        backgroundColor = {60, 100, 180, 220}, borderRadius = 4,
        justifyContent = "center", alignItems = "center",
        fontColor = {255,255,255,255},
        onClick = function() M.ShowLayerEditorExport() end,
    })
end

--- 创建背景图层编辑行（像素单位）
function M.CreateBgLayerRow(i, layer)
    local row = UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 3, width = "100%",
    }
    row:AddChild(UI.Label { text = layer.name, fontSize = 11, fontColor = {200,200,255,255}, width = 50 })
    row:AddChild(UI.Label { text = "T:", fontSize = 10, fontColor = {150,150,150,255}, width = 13 })
    row:AddChild(UI.Button {
        text = "-", fontSize = 11, width = 20, height = 20,
        backgroundColor = {80,80,120,200}, borderRadius = 3,
        justifyContent = "center", alignItems = "center", fontColor = {255,255,255,255},
        onClick = function()
            layerEditorData_[i].top = layerEditorData_[i].top - 5
            M.ApplyBgLayerPos(i)
            M.RefreshLayerEditor()
        end,
    })
    row:AddChild(UI.Label { id = "bg_top_" .. i, text = tostring(math.floor(layer.top)), fontSize = 10, fontColor = {255,255,255,255}, width = 28, textAlign = "center" })
    row:AddChild(UI.Button {
        text = "+", fontSize = 11, width = 20, height = 20,
        backgroundColor = {80,80,120,200}, borderRadius = 3,
        justifyContent = "center", alignItems = "center", fontColor = {255,255,255,255},
        onClick = function()
            layerEditorData_[i].top = layerEditorData_[i].top + 5
            M.ApplyBgLayerPos(i)
            M.RefreshLayerEditor()
        end,
    })
    row:AddChild(UI.Label { text = "L:", fontSize = 10, fontColor = {150,150,150,255}, width = 13 })
    row:AddChild(UI.Button {
        text = "-", fontSize = 11, width = 20, height = 20,
        backgroundColor = {80,120,80,200}, borderRadius = 3,
        justifyContent = "center", alignItems = "center", fontColor = {255,255,255,255},
        onClick = function()
            layerEditorData_[i].left = layerEditorData_[i].left - 5
            M.ApplyBgLayerPos(i)
            M.RefreshLayerEditor()
        end,
    })
    row:AddChild(UI.Label { id = "bg_left_" .. i, text = tostring(math.floor(layer.left)), fontSize = 10, fontColor = {255,255,255,255}, width = 28, textAlign = "center" })
    row:AddChild(UI.Button {
        text = "+", fontSize = 11, width = 20, height = 20,
        backgroundColor = {80,120,80,200}, borderRadius = 3,
        justifyContent = "center", alignItems = "center", fontColor = {255,255,255,255},
        onClick = function()
            layerEditorData_[i].left = layerEditorData_[i].left + 5
            M.ApplyBgLayerPos(i)
            M.RefreshLayerEditor()
        end,
    })
    return row
end

--- 创建UI图片图层编辑行（像素单位 + 图层上下移动）
function M.CreateUILayerRow(i, layer)
    local row = UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 2, width = "100%",
    }
    -- 图层名称
    row:AddChild(UI.Label { text = layer.name, fontSize = 10, fontColor = {255,220,180,255}, width = 52 })
    -- top 控制
    row:AddChild(UI.Label { text = "T:", fontSize = 9, fontColor = {150,150,150,255}, width = 12 })
    row:AddChild(UI.Button {
        text = "-", fontSize = 11, width = 18, height = 18,
        backgroundColor = {80,80,120,200}, borderRadius = 2,
        justifyContent = "center", alignItems = "center", fontColor = {255,255,255,255},
        onClick = function()
            uiLayerEditorData_[i].top = uiLayerEditorData_[i].top - 5
            M.ApplyUILayerPos(i)
            M.RefreshLayerEditor()
        end,
    })
    row:AddChild(UI.Label { text = tostring(math.floor(layer.top)), fontSize = 9, fontColor = {255,255,255,255}, width = 28, textAlign = "center" })
    row:AddChild(UI.Button {
        text = "+", fontSize = 11, width = 18, height = 18,
        backgroundColor = {80,80,120,200}, borderRadius = 2,
        justifyContent = "center", alignItems = "center", fontColor = {255,255,255,255},
        onClick = function()
            uiLayerEditorData_[i].top = uiLayerEditorData_[i].top + 5
            M.ApplyUILayerPos(i)
            M.RefreshLayerEditor()
        end,
    })
    -- left 控制
    row:AddChild(UI.Label { text = "L:", fontSize = 9, fontColor = {150,150,150,255}, width = 12 })
    row:AddChild(UI.Button {
        text = "-", fontSize = 11, width = 18, height = 18,
        backgroundColor = {80,120,80,200}, borderRadius = 2,
        justifyContent = "center", alignItems = "center", fontColor = {255,255,255,255},
        onClick = function()
            uiLayerEditorData_[i].left = uiLayerEditorData_[i].left - 5
            M.ApplyUILayerPos(i)
            M.RefreshLayerEditor()
        end,
    })
    row:AddChild(UI.Label { text = tostring(math.floor(layer.left)), fontSize = 9, fontColor = {255,255,255,255}, width = 28, textAlign = "center" })
    row:AddChild(UI.Button {
        text = "+", fontSize = 11, width = 18, height = 18,
        backgroundColor = {80,120,80,200}, borderRadius = 2,
        justifyContent = "center", alignItems = "center", fontColor = {255,255,255,255},
        onClick = function()
            uiLayerEditorData_[i].left = uiLayerEditorData_[i].left + 5
            M.ApplyUILayerPos(i)
            M.RefreshLayerEditor()
        end,
    })
    -- 图层上移按钮
    row:AddChild(UI.Button {
        text = "▲", fontSize = 9, width = 20, height = 18,
        backgroundColor = (i > 1) and {120,80,150,200} or {60,60,60,100}, borderRadius = 2,
        justifyContent = "center", alignItems = "center",
        fontColor = (i > 1) and {255,255,255,255} or {100,100,100,255},
        onClick = function()
            if i > 1 then M.MoveUILayer(i, -1) end
        end,
    })
    -- 图层下移按钮
    row:AddChild(UI.Button {
        text = "▼", fontSize = 9, width = 20, height = 18,
        backgroundColor = (i < #uiLayerEditorData_) and {120,80,150,200} or {60,60,60,100}, borderRadius = 2,
        justifyContent = "center", alignItems = "center",
        fontColor = (i < #uiLayerEditorData_) and {255,255,255,255} or {100,100,100,255},
        onClick = function()
            if i < #uiLayerEditorData_ then M.MoveUILayer(i, 1) end
        end,
    })
    return row
end

--- 应用背景图层位置（像素）
function M.ApplyBgLayerPos(idx)
    if not S.mainMenuUIRoot then return end
    local layer = layerEditorData_[idx]
    local widget = S.mainMenuUIRoot:FindById(layer.id)
    if widget then
        widget:SetStyle({
            top = layer.top,
            left = layer.left,
        })
    end
end

--- 应用UI图片图层位置（像素）
function M.ApplyUILayerPos(idx)
    if not S.mainMenuUIRoot or not S.mainMenuUIRoot.uiLayerContainer then return end
    local layer = uiLayerEditorData_[idx]
    local widget = S.mainMenuUIRoot.uiLayerContainer:FindById(layer.id)
    if widget then
        widget:SetStyle({ top = layer.top, left = layer.left })
    end
end

--- 移动UI图片图层顺序（direction: -1=上移, 1=下移）
function M.MoveUILayer(idx, direction)
    local target = idx + direction
    if target < 1 or target > #uiLayerEditorData_ then return end

    -- 交换编辑器数据
    uiLayerEditorData_[idx], uiLayerEditorData_[target] = uiLayerEditorData_[target], uiLayerEditorData_[idx]
    -- 同步uiImageLayers_数据
    uiImageLayers_[idx], uiImageLayers_[target] = uiImageLayers_[target], uiImageLayers_[idx]

    -- 重建UI图层容器的子元素顺序
    M.RebuildUILayerContainer()
    -- 刷新编辑器面板
    M.RefreshLayerEditor()
end

--- 重建UI图层容器（按uiImageLayers_顺序重新添加子元素）
function M.RebuildUILayerContainer()
    if not S.mainMenuUIRoot or not S.mainMenuUIRoot.uiLayerContainer then return end
    local container = S.mainMenuUIRoot.uiLayerContainer
    container:ClearChildren()

    for _, layer in ipairs(uiImageLayers_) do
        local panel = UI.Panel {
            id = layer.id,
            position = "absolute",
            top = layer.top, left = layer.left,
            width = layer.w, height = layer.h,
            backgroundImage = layer.file,
            backgroundFit = "contain",
            pointerEvents = "none",
        }
        container:AddChild(panel)
    end
    -- 同步编辑器数据中的位置到新面板
    for i, ed in ipairs(uiLayerEditorData_) do
        local widget = container:FindById(ed.id)
        if widget then
            widget:SetStyle({ top = ed.top, left = ed.left })
        end
    end
end

function M.ShowLayerEditorExport()
    local lines = { "-- 背景图层位置 --" }
    for _, layer in ipairs(layerEditorData_) do
        table.insert(lines, layer.name .. ": top=" .. tostring(math.floor(layer.top)) .. "px, left=" .. tostring(math.floor(layer.left)) .. "px")
    end
    table.insert(lines, "")
    table.insert(lines, "-- UI图片图层（从下到上）--")
    for i, layer in ipairs(uiLayerEditorData_) do
        table.insert(lines, i .. ". " .. layer.name .. ": top=" .. tostring(math.floor(layer.top)) .. "px, left=" .. tostring(math.floor(layer.left)) .. "px")
    end
    local exportText = table.concat(lines, "\n")

    if layerEditorExport_ then
        layerEditorExport_:Destroy()
    end
    layerEditorExport_ = UI.Panel {
        position = "absolute", top = "10%", left = "20%",
        width = "60%",
        backgroundColor = {0, 0, 0, 230},
        borderRadius = 10, borderWidth = 1, borderColor = {100, 140, 255, 150},
        paddingTop = 16, paddingBottom = 16,
        paddingLeft = 16, paddingRight = 16,
        flexDirection = "column", gap = 8,
        children = {
            UI.Label {
                text = "复制以下数据发给AI：", fontSize = 13,
                fontColor = {180, 200, 255, 255},
            },
            UI.Panel {
                width = "100%",
                backgroundColor = {30, 30, 50, 255},
                borderRadius = 6,
                paddingTop = 10, paddingBottom = 10,
                paddingLeft = 10, paddingRight = 10,
                children = {
                    UI.Label {
                        text = exportText, fontSize = 11,
                        fontColor = {200, 255, 200, 255},
                    },
                },
            },
            UI.Button {
                text = "关闭", fontSize = 12,
                width = 80, height = 28,
                backgroundColor = {100, 50, 50, 200}, borderRadius = 4,
                justifyContent = "center", alignItems = "center",
                fontColor = {255,255,255,255},
                onClick = function()
                    if layerEditorExport_ then
                        layerEditorExport_:Destroy()
                        layerEditorExport_ = nil
                    end
                end,
            },
        },
    }
    S.mainMenuUIRoot:AddChild(layerEditorExport_)
end

-- ============================================================================
-- 角色面板图层系统 + 图层编辑器
-- ============================================================================

--- 初始化角色面板图层定义（视觉从下到上：底图→背景→...→占位文本）
local function initCharPanelLayers()
    -- 渲染顺序：数组第1个在最底层，最后一个在最顶层
    charPanelLayers_ = {
        { name = "底图(参考)", id = "cp_底图",         file = "image/角色1面板ui/底图.png",         top = 0, left = 0, opacity = 0.5, isRef = true, hidden = true },
        { name = "背景",       id = "cp_背景",         file = "image/角色1面板ui/背景.png",         top = 0, left = 0, opacity = 1.0 },
        { name = "加粗边框",   id = "cp_加粗边框",     file = "image/角色1面板ui/加粗边框.png",     top = 0, left = 0, opacity = 1.0 },
        { name = "圆形头像线稿", id = "cp_圆形头像线稿", file = "image/角色1面板ui/圆形头像线稿.png", top = 0, left = 0, opacity = 1.0 },
        { name = "半透明文本框", id = "cp_半透明文本框", file = "image/角色1面板ui/半透明文本框.png", top = 0, left = 0, opacity = 1.0 },
        { name = "走姿小人",   id = "cp_走姿小人",     file = "image/角色1面板ui/走姿小人.png",     top = 0, left = 0, opacity = 1.0 },
        { name = "角色头像",   id = "cp_角色头像",     file = "image/角色1面板ui/角色头像+左下花.png", top = 0, left = 0, opacity = 1.0 },
        { name = "头像框飞鸟", id = "cp_头像框飞鸟",   file = "image/角色1面板ui/头像框飞鸟.png",   top = 0, left = 0, opacity = 1.0 },
        { name = "头像框花",   id = "cp_头像框花",     file = "image/角色1面板ui/头像框花.png",     top = 0, left = 0, opacity = 1.0 },
        { name = "边框飞鸟",   id = "cp_边框飞鸟",     file = "image/角色1面板ui/边框飞鸟.png",     top = 0, left = 0, opacity = 1.0 },
        { name = "占位文本",   id = "cp_占位文本",     file = "image/角色1面板ui/占位文本.png",     top = 0, left = 0, opacity = 1.0 },
    }
end

--- 打开角色面板（显示图层 + 编辑器）
function M.ShowCharacterPanel()
    if not charPanelLayers_ then
        initCharPanelLayers()
    end

    -- 全屏遮罩 + 图层容器
    charPanelContainer_ = UI.Panel {
        id = "cp_layer_container",
        position = "absolute", top = 0, left = 0,
        width = 1840, height = 1035,
    }

    menuPanelOverlay_ = UI.Panel {
        id = "menu_panel_overlay",
        position = "absolute", top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = {0, 0, 0, 0},
        justifyContent = "center", alignItems = "center",
        children = { charPanelContainer_ },
    }
    S.mainMenuUIRoot:AddChild(menuPanelOverlay_)

    -- 按顺序添加图层
    M.RebuildCharPanelLayers()

    -- 构建角色面板图层编辑器
    M.BuildCharLayerEditor()
end

--- 重建角色面板图层渲染顺序
function M.RebuildCharPanelLayers()
    if not charPanelContainer_ then return end
    charPanelContainer_:ClearChildren()

    for _, layer in ipairs(charPanelLayers_) do
        if not layer.hidden then
            local panel = UI.Panel {
                id = layer.id,
                position = "absolute",
                top = layer.top, left = layer.left,
                width = 1840, height = 1035,
                backgroundImage = layer.file,
                backgroundFit = "contain",
                pointerEvents = "none",
                opacity = layer.opacity or 1.0,
            }
            charPanelContainer_:AddChild(panel)
        end
    end
end

--- 应用角色面板某图层的位置
function M.ApplyCharLayerPos(idx)
    if not charPanelContainer_ then return end
    local layer = charPanelLayers_[idx]
    local widget = charPanelContainer_:FindById(layer.id)
    if widget then
        widget:SetStyle({ top = layer.top, left = layer.left })
    end
end

--- 构建角色面板图层编辑器
function M.BuildCharLayerEditor()
    -- 切换按钮
    charLayerEditorToggle_ = UI.Button {
        position = "absolute", bottom = 16, right = 16,
        text = "角色图层编辑", fontSize = 12,
        fontColor = {255, 255, 255, 220},
        backgroundColor = {80, 40, 120, 200},
        borderRadius = 4,
        paddingLeft = 8, paddingRight = 8,
        paddingTop = 4, paddingBottom = 4,
        onClick = function()
            charLayerEditorVisible_ = not charLayerEditorVisible_
            M.RefreshCharLayerEditor()
        end,
    }
    S.mainMenuUIRoot:AddChild(charLayerEditorToggle_)

    -- 编辑面板
    charLayerEditorPanel_ = UI.Panel {
        id = "charLayerEditorPanel",
        position = "absolute", bottom = 50, right = 16,
        width = 380, maxHeight = "85%",
        backgroundColor = {0, 0, 0, 220},
        borderRadius = 8,
        paddingTop = 10, paddingBottom = 10,
        paddingLeft = 10, paddingRight = 10,
        flexDirection = "column", gap = 4,
        overflow = "scroll",
        display = "none",
    }
    S.mainMenuUIRoot:AddChild(charLayerEditorPanel_)

    -- 默认展开编辑器
    charLayerEditorVisible_ = true
    M.RefreshCharLayerEditor()
end

--- 刷新角色面板图层编辑器内容
function M.RefreshCharLayerEditor()
    if not charLayerEditorPanel_ then return end
    charLayerEditorPanel_:ClearChildren()

    if not charLayerEditorVisible_ then
        charLayerEditorPanel_:SetStyle({ display = "none" })
        return
    end
    charLayerEditorPanel_:SetStyle({ display = "flex" })

    -- 标题行
    charLayerEditorPanel_:AddChild(UI.Panel {
        flexDirection = "row", alignItems = "center", justifyContent = "space-between", width = "100%",
        children = {
            UI.Label {
                text = "◆ 角色面板图层（从下到上）", fontSize = 13,
                fontColor = {200, 150, 255, 255},
            },
            UI.Button {
                text = "✕ 关闭面板", fontSize = 11,
                paddingLeft = 8, paddingRight = 8, paddingTop = 3, paddingBottom = 3,
                backgroundColor = {150, 50, 50, 200}, borderRadius = 4,
                fontColor = {255, 255, 255, 255},
                onClick = function() M.CloseMenuPanel() end,
            },
        },
    })

    -- 图层行
    for i, layer in ipairs(charPanelLayers_) do
        charLayerEditorPanel_:AddChild(M.CreateCharLayerRow(i, layer))
    end

    -- 导出按钮
    charLayerEditorPanel_:AddChild(UI.Button {
        text = "导出位置数据", fontSize = 12, marginTop = 8,
        width = "100%", height = 28,
        backgroundColor = {80, 60, 160, 220}, borderRadius = 4,
        justifyContent = "center", alignItems = "center",
        fontColor = {255, 255, 255, 255},
        onClick = function() M.ShowCharLayerExport() end,
    })
end

--- 创建角色面板图层编辑行
function M.CreateCharLayerRow(i, layer)
    local isRef = layer.isRef or false
    local nameColor = isRef and {255, 180, 100, 200} or {220, 200, 255, 255}

    local row = UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 2, width = "100%",
        backgroundColor = isRef and {60, 40, 20, 100} or {0, 0, 0, 0},
        paddingTop = 2, paddingBottom = 2, paddingLeft = 4, paddingRight = 2,
        borderRadius = 3,
    }

    -- 图层名称
    row:AddChild(UI.Label { text = layer.name, fontSize = 10, fontColor = nameColor, width = 62 })

    -- top 控制
    row:AddChild(UI.Label { text = "T:", fontSize = 9, fontColor = {150, 150, 150, 255}, width = 12 })
    row:AddChild(UI.Button {
        text = "-", fontSize = 11, width = 18, height = 18,
        backgroundColor = {80, 80, 120, 200}, borderRadius = 2,
        justifyContent = "center", alignItems = "center", fontColor = {255, 255, 255, 255},
        onClick = function()
            charPanelLayers_[i].top = charPanelLayers_[i].top - 5
            M.ApplyCharLayerPos(i)
            M.RefreshCharLayerEditor()
        end,
    })
    row:AddChild(UI.Label { text = tostring(math.floor(layer.top)), fontSize = 9, fontColor = {255, 255, 255, 255}, width = 30, textAlign = "center" })
    row:AddChild(UI.Button {
        text = "+", fontSize = 11, width = 18, height = 18,
        backgroundColor = {80, 80, 120, 200}, borderRadius = 2,
        justifyContent = "center", alignItems = "center", fontColor = {255, 255, 255, 255},
        onClick = function()
            charPanelLayers_[i].top = charPanelLayers_[i].top + 5
            M.ApplyCharLayerPos(i)
            M.RefreshCharLayerEditor()
        end,
    })

    -- left 控制
    row:AddChild(UI.Label { text = "L:", fontSize = 9, fontColor = {150, 150, 150, 255}, width = 12 })
    row:AddChild(UI.Button {
        text = "-", fontSize = 11, width = 18, height = 18,
        backgroundColor = {80, 120, 80, 200}, borderRadius = 2,
        justifyContent = "center", alignItems = "center", fontColor = {255, 255, 255, 255},
        onClick = function()
            charPanelLayers_[i].left = charPanelLayers_[i].left - 5
            M.ApplyCharLayerPos(i)
            M.RefreshCharLayerEditor()
        end,
    })
    row:AddChild(UI.Label { text = tostring(math.floor(layer.left)), fontSize = 9, fontColor = {255, 255, 255, 255}, width = 30, textAlign = "center" })
    row:AddChild(UI.Button {
        text = "+", fontSize = 11, width = 18, height = 18,
        backgroundColor = {80, 120, 80, 200}, borderRadius = 2,
        justifyContent = "center", alignItems = "center", fontColor = {255, 255, 255, 255},
        onClick = function()
            charPanelLayers_[i].left = charPanelLayers_[i].left + 5
            M.ApplyCharLayerPos(i)
            M.RefreshCharLayerEditor()
        end,
    })

    -- 图层上移
    row:AddChild(UI.Button {
        text = "▲", fontSize = 9, width = 20, height = 18,
        backgroundColor = (i > 1) and {120, 80, 150, 200} or {60, 60, 60, 100}, borderRadius = 2,
        justifyContent = "center", alignItems = "center",
        fontColor = (i > 1) and {255, 255, 255, 255} or {100, 100, 100, 255},
        onClick = function()
            if i > 1 then M.MoveCharLayer(i, -1) end
        end,
    })
    -- 图层下移
    row:AddChild(UI.Button {
        text = "▼", fontSize = 9, width = 20, height = 18,
        backgroundColor = (i < #charPanelLayers_) and {120, 80, 150, 200} or {60, 60, 60, 100}, borderRadius = 2,
        justifyContent = "center", alignItems = "center",
        fontColor = (i < #charPanelLayers_) and {255, 255, 255, 255} or {100, 100, 100, 255},
        onClick = function()
            if i < #charPanelLayers_ then M.MoveCharLayer(i, 1) end
        end,
    })

    return row
end

--- 移动角色面板图层顺序
function M.MoveCharLayer(idx, direction)
    local target = idx + direction
    if target < 1 or target > #charPanelLayers_ then return end
    charPanelLayers_[idx], charPanelLayers_[target] = charPanelLayers_[target], charPanelLayers_[idx]
    M.RebuildCharPanelLayers()
    M.RefreshCharLayerEditor()
end

--- 角色面板视差动画更新（每帧调用）
function M.UpdateCharPanelParallax(dt)
    if not charPanelContainer_ or not charPanelLayers_ then return end

    charPanelTime_ = charPanelTime_ + dt
    local t = charPanelTime_

    -- 鼠标归一化坐标 (-1 ~ 1)
    local screenW = graphics:GetWidth()
    local screenH = graphics:GetHeight()
    local mx = input.mousePosition.x
    local my = input.mousePosition.y
    local nx = (mx - screenW * 0.5) / (screenW * 0.5)
    local ny = (my - screenH * 0.5) / (screenH * 0.5)

    local layerCount = #charPanelLayers_
    local visibleIdx = 0

    for idx, layer in ipairs(charPanelLayers_) do
        if not layer.hidden then
            visibleIdx = visibleIdx + 1
            local widget = charPanelContainer_:FindById(layer.id)
            if widget then
                -- 静态层：不做视差和呼吸
                local isStatic = (layer.id == "cp_背景" or layer.id == "cp_占位文本"
                    or layer.id == "cp_加粗边框" or layer.id == "cp_圆形头像线稿"
                    or layer.id == "cp_半透明文本框")

                if isStatic then
                    widget:SetStyle({
                        top = layer.top,
                        left = layer.left,
                    })
                else
                    -- 深度因子：底层=0.1, 顶层=1.0（越靠上视差越强）
                    local depth = 0.1 + 0.9 * ((visibleIdx - 1) / math.max(layerCount - 2, 1))

                    -- 水平视差（底层~3px, 顶层~25px）
                    local parX = -nx * 25 * depth
                    -- 垂直视差（底层~1px, 顶层~8px）
                    local parY = -ny * 8 * depth

                    -- 呼吸浮动：每层不同相位
                    local breathPhase = idx * 0.8
                    local breathAmp = 2 + depth * 4  -- 底层~2px, 顶层~6px
                    -- 特定图层呼吸幅度加大
                    if layer.id == "cp_头像框飞鸟" then
                        breathAmp = 16
                    elseif layer.id == "cp_走姿小人" then
                        breathAmp = 12
                    end
                    local breathOffset = math.sin(t * 0.7 + breathPhase) * breathAmp

                    widget:SetStyle({
                        top = layer.top + parY + breathOffset,
                        left = layer.left + parX,
                    })
                end
            end
        end
    end
end

--- 导出角色面板图层位置数据
function M.ShowCharLayerExport()
    local lines = { "-- 角色面板图层位置（从下到上）--" }
    for i, layer in ipairs(charPanelLayers_) do
        local tag = layer.isRef and " [参考]" or ""
        table.insert(lines, i .. ". " .. layer.name .. tag .. ": top=" .. tostring(math.floor(layer.top)) .. ", left=" .. tostring(math.floor(layer.left)))
    end
    local exportText = table.concat(lines, "\n")
    print("[CharPanel] 导出数据:\n" .. exportText)

    -- 弹窗展示
    local exportPanel = UI.Panel {
        position = "absolute", top = "10%", left = "20%",
        width = "60%",
        backgroundColor = {0, 0, 0, 230},
        borderRadius = 10, borderWidth = 1, borderColor = {120, 80, 200, 150},
        paddingTop = 16, paddingBottom = 16,
        paddingLeft = 16, paddingRight = 16,
        flexDirection = "column", gap = 8,
        children = {
            UI.Label { text = "角色面板图层位置数据", fontSize = 16, fontColor = {200, 160, 255, 255} },
            UI.Label { text = exportText, fontSize = 11, fontColor = {200, 200, 200, 255} },
            UI.Button {
                text = "关闭", fontSize = 13,
                width = 80, height = 30,
                backgroundColor = {100, 50, 50, 200}, borderRadius = 4,
                justifyContent = "center", alignItems = "center",
                fontColor = {255, 255, 255, 255},
                onClick = function()
                    exportPanel:Destroy()
                end,
            },
        },
    }
    S.mainMenuUIRoot:AddChild(exportPanel)
end

return M
