-- ============================================================================
-- TitleMenu.lua
-- 标题画面、主菜单（Live2D视差）、图层编辑器、过渡系统
-- ============================================================================
local S = require("GameState")
local C = require("GameConfig")
local UI = require("urhox-libs/UI")
local Video = require("urhox-libs/Video")
local GMConsole = require("GMConsole")
local SpriteEditor = require("SpriteEditor")
local Animation = require("Animation")
local Combat = require("Combat")
local NodeCanvas = require("NodeCanvas")

local M = {}

-- ============================================================================
-- 模块内部状态
-- ============================================================================
local transition_ = { active = false, timer = 0, onComplete = nil, uiRoot = nil }
local mainMenuTime_ = 0
local layerEditorData_ = nil
local uiLayerEditorData_ = nil
local uiImageLayers_ = nil
local menuPanelOverlay_ = nil  -- 当前打开的功能面板（任务/角色）
local layerEditorVisible_ = false
local layerEditorPanel_ = nil
local layerEditorToggle_ = nil
local layerEditorExport_ = nil

-- ============================================================================
-- 关卡选择状态
-- ============================================================================
local levelSelect_ = {
    active = false,
    uiRoot = nil,
    chapterIndex = 1,   -- 当前章节索引
    editorActive = false,
    editorPanel = nil,
    editorLevelIdx = nil,  -- 正在编辑的关卡索引
}

--- 每章8关的关卡数据（白盒占位，可通过编辑器修改导出）
--- 结构: levelData_[chapterIndex][levelIndex] = { name, unlocked, stars, ... }
local levelData_ = {}
for ch = 1, 4 do
    levelData_[ch] = {}
    for lv = 1, 8 do
        levelData_[ch][lv] = {
            name = "第" .. ch .. "-" .. lv .. "关",
            unlocked = (lv == 1),  -- 默认只解锁第一关
            stars = 0,             -- 星级评价 0~3
            difficulty = 1,        -- 难度 1~5
            enemies = 3 + lv,      -- 敌人数量
            timeLimit = 60 + lv * 10,  -- 时间限制（秒）
            reward = lv * 100,     -- 通关奖励
            description = "",      -- 关卡描述
        }
    end
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

--- 显示功能面板（半透明占位）
---@param panelType "task"|"character"
function M.ShowMenuPanel(panelType)
    -- 如果已有面板打开，先关闭
    if menuPanelOverlay_ then
        M.CloseMenuPanel()
    end

    local title = panelType == "task" and "任务" or "角色"

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

local CARD_W = 320          -- 选中卡片宽度
local CARD_H = 420          -- 选中卡片高度
local CARD_SCALE_SIDE = 0.65 -- 两侧卡片缩放
local CARD_GAP = 280         -- 卡片中心间距
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
        local card = UI.Button {
            id = "chapter_card_" .. i,
            position = "absolute",
            width = CARD_W, height = CARD_H,
            backgroundColor = chap.color,
            borderRadius = 16,
            justifyContent = "center",
            alignItems = "center",
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
                    -- 点击非当前章节：切换到该章节
                    chapterSelect_.targetIndex = idx
                    chapterSelect_.animTimer = 0
                    chapterSelect_.animating = true
                else
                    -- 点击当前章节：进入关卡选择
                    M.ShowLevelSelect(idx)
                end
            end,
        }
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
end

--- 关闭章节选择界面
function M.CloseChapterSelect()
    chapterSelect_.active = false
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
-- 关卡选择页面
-- ============================================================================

--- 显示关卡选择页面
---@param chapterIdx number 章节索引 (1~4)
function M.ShowLevelSelect(chapterIdx)
    if levelSelect_.uiRoot then
        levelSelect_.uiRoot:Destroy()
    end
    levelSelect_.active = true
    levelSelect_.chapterIndex = chapterIdx
    levelSelect_.editorActive = false
    levelSelect_.editorPanel = nil
    levelSelect_.editorLevelIdx = nil

    local chapName = CHAPTER_DATA[chapterIdx] and CHAPTER_DATA[chapterIdx].name or ("第" .. chapterIdx .. "章")
    local chapColor = CHAPTER_DATA[chapterIdx] and CHAPTER_DATA[chapterIdx].color or {100, 100, 100, 255}

    -- 背景
    local bg = UI.Panel {
        position = "absolute", top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = {20, 18, 35, 250},
    }

    -- 顶部栏（标题 + 返回按钮）
    local topBar = UI.Panel {
        position = "absolute", top = 0, left = 0,
        width = "100%", height = 80,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 40, paddingRight = 40,
        pointerEvents = "box-none",
    }
    local backBtn = UI.Button {
        paddingLeft = 16, paddingRight = 16,
        paddingTop = 8, paddingBottom = 8,
        backgroundColor = {60, 60, 80, 200},
        borderRadius = 8,
        children = {
            UI.Label { text = "< 返回", fontSize = 16, fontColor = {200, 200, 220, 255} },
        },
        onClick = function()
            M.CloseLevelSelect()
        end,
    }
    local titleLabel = UI.Label {
        text = chapName .. " - 关卡选择",
        fontSize = 24,
        fontColor = {220, 220, 240, 255},
        marginLeft = 24,
    }
    topBar:AddChild(backBtn)
    topBar:AddChild(titleLabel)

    -- 关卡网格容器（2行4列，使用绝对定位+固定尺寸）
    local gridContainer = UI.Panel {
        id = "level_grid",
        position = "absolute", top = 100, left = 0, bottom = 0,
        width = "100%",
        flexDirection = "row", flexWrap = "wrap",
        justifyContent = "center", alignItems = "center",
        alignContent = "center",
        gap = 24,
        paddingLeft = 80, paddingRight = 80,
        paddingTop = 20, paddingBottom = 40,
    }

    -- 创建 8 个关卡白盒
    local levels = levelData_[chapterIdx]
    for i = 1, 8 do
        local lvData = levels[i]
        local isUnlocked = lvData.unlocked
        local boxColor = isUnlocked and {240, 240, 250, 255} or {80, 80, 100, 255}
        local textColor = isUnlocked and {30, 30, 50, 255} or {120, 120, 140, 255}
        local starText = ""
        if lvData.stars > 0 then
            for s = 1, lvData.stars do starText = starText .. "*" end
        end

        local lvIdx = i
        local levelCard = UI.Button {
            id = "level_card_" .. i,
            width = 180, height = 200,
            backgroundColor = boxColor,
            borderRadius = 12,
            borderWidth = 2,
            borderColor = isUnlocked and chapColor or {60, 60, 80, 200},
            flexDirection = "column",
            justifyContent = "center",
            alignItems = "center",
            gap = 8,
            children = {
                -- 关卡编号
                UI.Label {
                    text = tostring(i),
                    fontSize = 36,
                    fontColor = textColor,
                    pointerEvents = "none",
                },
                -- 关卡名
                UI.Label {
                    text = lvData.name,
                    fontSize = 13,
                    fontColor = textColor,
                    pointerEvents = "none",
                },
                -- 星级
                UI.Label {
                    id = "level_stars_" .. i,
                    text = starText ~= "" and starText or (isUnlocked and "未通关" or "锁定"),
                    fontSize = 12,
                    fontColor = isUnlocked and {200, 160, 50, 255} or {100, 100, 120, 255},
                    pointerEvents = "none",
                },
                -- 难度标签
                UI.Label {
                    text = "难度:" .. lvData.difficulty,
                    fontSize = 11,
                    fontColor = {150, 150, 170, 200},
                    pointerEvents = "none",
                },
            },
            onClick = function()
                if isUnlocked then
                    M.EnterLevelEditor(chapterIdx, lvIdx)
                end
            end,
        }
        gridContainer:AddChild(levelCard)
    end

    levelSelect_.uiRoot = UI.Panel {
        position = "absolute", top = 0, left = 0,
        width = "100%", height = "100%",
        children = { bg, gridContainer, topBar },
    }

    S.mainMenuUIRoot:AddChild(levelSelect_.uiRoot)
end

--- 关闭关卡选择页面
function M.CloseLevelSelect()
    levelSelect_.active = false
    levelSelect_.editorActive = false
    if levelSelect_.uiRoot then
        levelSelect_.uiRoot:Destroy()
        levelSelect_.uiRoot = nil
    end
end

--- 关卡选择页面是否打开
function M.IsLevelSelectOpen()
    return levelSelect_.active
end

-- ============================================================================
-- 关卡内编辑器（地形/平台/障碍/机关）
-- ============================================================================

-- 编辑器内部状态
local levelEditor_ = {
    active = false,
    uiRoot = nil,
    chapterIdx = 1,
    levelIdx = 1,
    currentTool = "platform",  -- platform / obstacle / trigger / executor / select / delete
    mappingMode = false,       -- 映射编辑模式
    mappingTriggerIdx = nil,   -- 当前正在映射的触发器索引
    selectedObj = nil,         -- 当前选中物件索引
    objects = {},              -- 当前关卡的物件列表
    -- 画布参数（侧视图，单位：像素）
    canvasW = 1200,
    canvasH = 700,
    gridSize = 40,             -- 网格尺寸（像素）
    -- 世界坐标映射（米）
    worldW = 30,               -- 世界宽度（米）
    worldH = 17.5,             -- 世界高度（米）
    -- 画布平移偏移（像素）
    canvasPanX = 0,
    canvasPanY = 0,
    canvasPanning = false,     -- 是否正在拖拽画布平移（已超过阈值）
    canvasPanPotential = false,-- 是否处于潜在平移状态（按下空白但未超阈值）
    canvasPanStartX = 0,       -- 拖拽起始鼠标X
    canvasPanStartY = 0,       -- 拖拽起始鼠标Y
    canvasPanStartPanX = 0,    -- 拖拽起始时的panX
    canvasPanStartPanY = 0,    -- 拖拽起始时的panY
    -- 拖拽状态
    dragging = false,
    dragObjIdx = nil,
    dragOffsetX = 0,           -- 鼠标到物件左上角的偏移(像素)
    dragOffsetY = 0,
    dragStarted = false,       -- 是否已开始拖拽（区分点击和拖拽）
    mouseDownX = 0,
    mouseDownY = 0,
    toolbarH = 50,
    margin = 8,
    -- 撤销栈
    undoStack = {},            -- 保存操作前的对象列表快照
    maxUndo = 50,              -- 最大撤销步数
    -- 预览模式
    previewActive = false,
    previewScene = nil,
    previewPlayerNode = nil,
    previewPlayerBody = nil,
    previewCameraNode = nil,
    previewFootSensor = nil,
    previewOnGround = false,
    previewGroundContacts = 0,
    previewUIRoot = nil,
    previewNodes = {},         -- 生成的地形节点列表（用于清理）
    -- 触发器/执行器提示系统（仅预览）
    previewTriggerPopups = {},  -- { {text, x, y, timer, maxTime}, ... } 浮动文字
    previewTriggeredSet = {},   -- 已触发过的触发器索引集合（防止重复触发）
    previewInteractIdx = nil,   -- 当前可交互的触发器索引（显示F键提示）
    -- 贴图系统（多图层背景）
    bgLayers = {},             -- 背景图层列表: { {path, name, opacity, x, y, w, h, depth, visible}, ... }
    selectedBgLayer = nil,     -- 当前选中的背景图层索引
    textureBrowseTarget = nil, -- "bg" 或物件索引（当前正在为哪个目标选贴图）
    -- 贴图锚点拖拽
    texDragging = false,
    texDragType = nil,         -- "scale" / "rotate"
    texDragStartX = 0,
    texDragStartY = 0,
    texDragStartW = 0,
    texDragStartH = 0,
    texDragStartAngle = 0,
    -- 背景图层锚点拖拽
    bgDragging = false,
    bgDragType = nil,          -- "move" / "tl" / "tr" / "bl" / "br" (四角)
    bgDragStartMX = 0,
    bgDragStartMY = 0,
    bgDragStartX = 0,
    bgDragStartY = 0,
    bgDragStartW = 0,
    bgDragStartH = 0,
    -- NanoVG 贴图缓存
    nvgTextures = {},          -- path -> nvg image handle
    -- 手动导入的贴图素材列表
    customTextures = {},       -- { {path=..., name=..., cat=...}, ... }
    -- 镜头范围框（世界坐标，Y-up）
    -- 默认略小于编辑器世界，确保框在画布内可见
    cameraBounds = { x = 2, y = 1, w = 26, h = 15.5 },
    cameraBoundsEnabled = true, -- 是否启用镜头范围限制（默认开启预览）
    -- 镜头范围框拖拽
    camBoundsDragging = false,
    camBoundsDragType = nil,   -- "move" / "tl" / "tr" / "bl" / "br"
    camBoundsDragStartMX = 0,
    camBoundsDragStartMY = 0,
    camBoundsDragStartX = 0,
    camBoundsDragStartY = 0,
    camBoundsDragStartW = 0,
    camBoundsDragStartH = 0,
    -- 色环/颜色选择器
    colorPickerOpen = false,   -- 颜色选择器是否打开
    colorPickerH = 0,          -- HSV: Hue (0~360)
    colorPickerS = 1.0,        -- HSV: Saturation (0~1)
    colorPickerV = 1.0,        -- HSV: Value (0~1)
    colorHistory = {},         -- 最近10个使用的颜色 {{r,g,b,a}, ...}
}

-- 贴图素材列表（手动上传管理，不再自动读取素材库）
-- 通过 M.ImportTexture(path, name, cat) 添加素材
-- cat: "bg" / "tile" / "misc"

-- 工具配置
local EDITOR_TOOLS = {
    { id = "select",    name = "选择", color = {200, 200, 200, 200} },
    { id = "platform",  name = "平台", color = {80, 180, 80, 255} },
    { id = "obstacle",  name = "障碍", color = {200, 60, 60, 255} },
    { id = "trigger",   name = "触发器", color = {220, 180, 50, 255} },
    { id = "executor",  name = "执行器", color = {50, 160, 220, 255} },
    { id = "ground",    name = "地面", color = {140, 100, 60, 255} },
    { id = "texture",   name = "贴图", color = {180, 100, 200, 255} },
    { id = "delete",    name = "删除", color = {180, 40, 40, 200} },
}

--- 进入关卡编辑器
function M.EnterLevelEditor(chapterIdx, levelIdx)
    levelEditor_.active = true
    levelEditor_.chapterIdx = chapterIdx
    levelEditor_.levelIdx = levelIdx
    levelEditor_.selectedObj = nil
    levelEditor_.currentTool = "platform"

    -- 初始化关卡物件（如果已有数据则加载）
    local key = chapterIdx .. "_" .. levelIdx
    if not levelEditor_.objects[key] then
        -- 第一章 第1-1关 地形数据
        levelEditor_.objects[key] = {
            { type = "ground", x = -0.5, y = 12.5, w = 23.0, h = 3.0, name = "地面" },
            { type = "platform", x = 5.0, y = 9.0, w = 4.0, h = 0.5, name = "平台1" },
            { type = "platform", x = 12.0, y = 7.5, w = 3.0, h = 0.5, name = "平台2" },
            { type = "platform", x = 11.0, y = 10.5, w = 3.0, h = 0.5, name = "platform5" },
        }
    end

    -- 导入默认素材（仅首次）
    if #levelEditor_.customTextures == 0 then
        M.ImportTexture("image/edited_城堡星空高清_20260604085456.png", "城堡星空", "bg")
        M.ImportTexture("image/ice_bg_far_20260602111146.png", "冰原远景", "bg")
        M.ImportTexture("image/克莱因蓝1.png", "克莱因蓝1", "bg")
        M.ImportTexture("image/城堡蓝图背景.jpg", "城堡蓝图背景", "bg")
        M.ImportTexture("image/transition_1.png", "过渡1", "tile")
        M.ImportTexture("image/transition_2.png", "过渡2", "tile")
        M.ImportTexture("image/transition_3.png", "过渡3", "tile")
    end

    M.BuildLevelEditorUI()
end

--- 导入贴图素材到编辑器（手动上传方式）
--- @param path string 图片路径（相对于 assets/，如 "image/xxx.png"）
--- @param name string 显示名称
--- @param cat string|nil 分类: "bg"/"tile"/"misc"，默认 "misc"
function M.ImportTexture(path, name, cat)
    cat = cat or "misc"
    name = name or path
    -- 避免重复导入
    for _, tex in ipairs(levelEditor_.customTextures) do
        if tex.path == path then
            print("[EDITOR] 素材已存在: " .. path)
            return
        end
    end
    table.insert(levelEditor_.customTextures, { path = path, name = name, cat = cat })
    print("[EDITOR] 导入素材: " .. name .. " (" .. path .. ") [" .. cat .. "]")
    -- 如果编辑器已打开则刷新UI
    if levelEditor_.active and levelEditor_.uiRoot then
        M.BuildLevelEditorUI()
    end
end

--- 添加背景图层
function M.AddBgLayer(path, name)
    -- 背景图层使用世界坐标(米)定位，可自由调整位置和大小
    local worldW = levelEditor_.worldW or 30
    local worldH = levelEditor_.worldH or 17.5
    local layer = {
        path = path,
        name = name or path,
        opacity = 1.0,
        x = worldW * 0.1,          -- 世界X坐标(米)
        y = worldH * 0.1,          -- 世界Y坐标(米)
        w = worldW * 0.8,          -- 宽度(米)
        h = worldH * 0.8,          -- 高度(米)
        depth = 0,                 -- 景深(0=无视差, 正值=远景慢移)
        visible = true,
    }
    table.insert(levelEditor_.bgLayers, layer)
    levelEditor_.selectedBgLayer = #levelEditor_.bgLayers
    print("[EDITOR] 添加背景图层: " .. (name or path) .. " (共" .. #levelEditor_.bgLayers .. "层)")
end

--- 删除背景图层
function M.RemoveBgLayer(idx)
    if idx and idx >= 1 and idx <= #levelEditor_.bgLayers then
        table.remove(levelEditor_.bgLayers, idx)
        if levelEditor_.selectedBgLayer == idx then
            levelEditor_.selectedBgLayer = math.max(1, idx - 1)
            if #levelEditor_.bgLayers == 0 then levelEditor_.selectedBgLayer = nil end
        elseif levelEditor_.selectedBgLayer and levelEditor_.selectedBgLayer > idx then
            levelEditor_.selectedBgLayer = levelEditor_.selectedBgLayer - 1
        end
    end
end

--- 移动背景图层顺序
function M.MoveBgLayer(idx, direction)
    local layers = levelEditor_.bgLayers
    local newIdx = idx + direction
    if newIdx < 1 or newIdx > #layers then return end
    layers[idx], layers[newIdx] = layers[newIdx], layers[idx]
    if levelEditor_.selectedBgLayer == idx then
        levelEditor_.selectedBgLayer = newIdx
    elseif levelEditor_.selectedBgLayer == newIdx then
        levelEditor_.selectedBgLayer = idx
    end
end

--- HSV转RGB (h:0~360, s:0~1, v:0~1) → (r,g,b) 0~255
function M.HSVtoRGB(h, s, v)
    h = h % 360
    local c = v * s
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = v - c
    local r, g, b = 0, 0, 0
    if h < 60 then r, g, b = c, x, 0
    elseif h < 120 then r, g, b = x, c, 0
    elseif h < 180 then r, g, b = 0, c, x
    elseif h < 240 then r, g, b = 0, x, c
    elseif h < 300 then r, g, b = x, 0, c
    else r, g, b = c, 0, x end
    return math.floor((r + m) * 255 + 0.5), math.floor((g + m) * 255 + 0.5), math.floor((b + m) * 255 + 0.5)
end

--- RGB转HSV (r,g,b: 0~255) → (h:0~360, s:0~1, v:0~1)
function M.RGBtoHSV(r, g, b)
    r, g, b = r / 255, g / 255, b / 255
    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    local d = max - min
    local h, s, v = 0, 0, max
    if max ~= 0 then s = d / max end
    if d ~= 0 then
        if max == r then h = 60 * (((g - b) / d) % 6)
        elseif max == g then h = 60 * ((b - r) / d + 2)
        else h = 60 * ((r - g) / d + 4) end
    end
    if h < 0 then h = h + 360 end
    return h, s, v
end

--- RGB转十六进制色号
function M.RGBtoHex(r, g, b)
    return string.format("#%02X%02X%02X", r, g, b)
end

--- 十六进制色号转RGB
function M.HexToRGB(hex)
    hex = hex:gsub("#", "")
    if #hex == 6 then
        local r = tonumber(hex:sub(1, 2), 16) or 0
        local g = tonumber(hex:sub(3, 4), 16) or 0
        local b = tonumber(hex:sub(5, 6), 16) or 0
        return r, g, b
    end
    return 255, 255, 255
end

--- 将颜色添加到历史记录（最多10个）
function M.AddColorToHistory(r, g, b, a)
    a = a or 255
    local history = levelEditor_.colorHistory
    -- 避免重复（相同颜色不重复添加）
    for i, c in ipairs(history) do
        if c[1] == r and c[2] == g and c[3] == b then
            table.remove(history, i)
            break
        end
    end
    table.insert(history, 1, {r, g, b, a})
    -- 最多保留10个
    while #history > 10 do
        table.remove(history)
    end
end

--- 给物件应用颜色
function M.ApplyColorToObject(objIdx, r, g, b, a)
    local objects = levelEditor_.objects[levelEditor_.chapterIdx .. "_" .. levelEditor_.levelIdx] or {}
    local obj = objects[objIdx]
    if not obj then return end
    M.PushUndoState()
    obj.color = {r, g, b, a or 255}
    M.AddColorToHistory(r, g, b, a or 255)
    M.BuildLevelEditorUI()
end

--- 为物件添加贴图图层
function M.AddObjTexLayer(objIdx, path, name)
    local objects = levelEditor_.objects[levelEditor_.chapterIdx .. "_" .. levelEditor_.levelIdx] or {}
    local obj = objects[objIdx]
    if not obj then return end
    M.PushUndoState()
    if not obj.texLayers then obj.texLayers = {} end
    -- 如果旧的单贴图存在，迁移到图层系统
    if obj.texture and #obj.texLayers == 0 then
        table.insert(obj.texLayers, {
            path = obj.texture,
            name = obj.textureName or obj.texture,
            opacity = 1.0,
            scaleW = obj.texScaleW or 1.0,
            scaleH = obj.texScaleH or 1.0,
            visible = true,
        })
        obj.texture = nil
        obj.textureName = nil
        obj.texScaleW = nil
        obj.texScaleH = nil
    end
    table.insert(obj.texLayers, {
        path = path,
        name = name or path,
        opacity = 1.0,
        scaleW = 1.0,
        scaleH = 1.0,
        visible = true,
    })
    obj.selectedTexLayer = #obj.texLayers
end

--- 移除物件贴图图层
function M.RemoveObjTexLayer(objIdx, layerIdx)
    local objects = levelEditor_.objects[levelEditor_.chapterIdx .. "_" .. levelEditor_.levelIdx] or {}
    local obj = objects[objIdx]
    if not obj or not obj.texLayers then return end
    M.PushUndoState()
    table.remove(obj.texLayers, layerIdx)
    if obj.selectedTexLayer == layerIdx then
        obj.selectedTexLayer = #obj.texLayers > 0 and math.min(layerIdx, #obj.texLayers) or nil
    elseif obj.selectedTexLayer and obj.selectedTexLayer > layerIdx then
        obj.selectedTexLayer = obj.selectedTexLayer - 1
    end
end

--- 移动物件贴图图层顺序
function M.MoveObjTexLayer(objIdx, layerIdx, direction)
    local objects = levelEditor_.objects[levelEditor_.chapterIdx .. "_" .. levelEditor_.levelIdx] or {}
    local obj = objects[objIdx]
    if not obj or not obj.texLayers then return end
    local newIdx = layerIdx + direction
    if newIdx < 1 or newIdx > #obj.texLayers then return end
    obj.texLayers[layerIdx], obj.texLayers[newIdx] = obj.texLayers[newIdx], obj.texLayers[layerIdx]
    if obj.selectedTexLayer == layerIdx then
        obj.selectedTexLayer = newIdx
    elseif obj.selectedTexLayer == newIdx then
        obj.selectedTexLayer = layerIdx
    end
end

--- 退出关卡编辑器（回到关卡选择）
function M.ExitLevelEditor()
    levelEditor_.active = false
    if levelEditor_.uiRoot then
        levelEditor_.uiRoot:Destroy()
        levelEditor_.uiRoot = nil
    end
end

--- 关卡编辑器是否打开
function M.IsLevelEditorOpen()
    return levelEditor_.active
end

--- 保存当前状态到撤销栈（在修改前调用）
function M.PushUndoState()
    local ch = levelEditor_.chapterIdx
    local lv = levelEditor_.levelIdx
    local key = ch .. "_" .. lv
    local objects = levelEditor_.objects[key] or {}
    -- 深拷贝当前对象列表（包括mappings）
    local snapshot = {}
    for i, obj in ipairs(objects) do
        local copy = { type = obj.type, x = obj.x, y = obj.y, w = obj.w, h = obj.h, name = obj.name }
        if obj.mappings then
            copy.mappings = {}
            for mi, v in ipairs(obj.mappings) do
                copy.mappings[mi] = v
            end
        end
        snapshot[i] = copy
    end
    table.insert(levelEditor_.undoStack, { key = key, objects = snapshot, selectedObj = levelEditor_.selectedObj })
    -- 限制栈大小
    if #levelEditor_.undoStack > levelEditor_.maxUndo then
        table.remove(levelEditor_.undoStack, 1)
    end
end

--- 撤销上一步操作 (Ctrl+Z)
function M.UndoLevelEditor()
    if #levelEditor_.undoStack == 0 then return end
    local state = table.remove(levelEditor_.undoStack)
    levelEditor_.objects[state.key] = state.objects
    levelEditor_.selectedObj = state.selectedObj
    M.BuildLevelEditorUI()
end

--- 关卡编辑器每帧更新（处理拖拽）
function M.UpdateLevelEditor(dt)
    if not levelEditor_.active then return end
    -- 每帧清除"刚退出预览"标志
    levelEditor_.justStoppedPreview = false
    -- 延迟清除"刚完成画布平移"标志（给 onClick 回调一帧时间读取）
    if levelEditor_.justPannedClear then
        levelEditor_.justPanned = false
        levelEditor_.justPannedClear = false
    end
    if levelEditor_.justPanned then
        levelEditor_.justPannedClear = true
    end
    -- 预览模式下编辑器不可见时跳过键盘/鼠标处理
    if levelEditor_.previewActive and levelEditor_.uiRoot and not levelEditor_.uiRoot:IsVisible() then
        return
    end

    -- NodeCanvas 打开时，优先处理其输入并跳过编辑器其他输入
    if NodeCanvas.IsActive() then
        -- 确保编辑器 UI 面板被隐藏（避免遮挡画布）
        if levelEditor_.uiRoot and levelEditor_.uiRoot:IsVisible() then
            levelEditor_.uiRoot:SetVisible(false)
        end
        NodeCanvas.HandleInput(dt)
        return
    else
        -- NodeCanvas 关闭后恢复编辑器 UI 面板显示
        if levelEditor_.uiRoot and not levelEditor_.uiRoot:IsVisible() and not levelEditor_.previewActive then
            levelEditor_.uiRoot:SetVisible(true)
        end
    end

    -- 每帧重置物件命中标记（防止背景拖拽误触发）
    levelEditor_.objHitThisFrame = false

    -- 延迟恢复滚动位置（等布局完成后）
    if levelEditor_.scrollRestoreFrames_ and levelEditor_.scrollRestoreFrames_ > 0 then
        levelEditor_.scrollRestoreFrames_ = levelEditor_.scrollRestoreFrames_ - 1
        if levelEditor_.pendingScrollY_ and levelEditor_.pendingScrollY_ > 0 then
            local pp = levelEditor_.uiRoot and levelEditor_.uiRoot:FindById("editor_props")
            if pp and pp.SetScrollDirect then
                pp:SetScrollDirect(0, levelEditor_.pendingScrollY_)
            end
        end
        if levelEditor_.scrollRestoreFrames_ <= 0 then
            levelEditor_.pendingScrollY_ = nil
            levelEditor_.scrollRestoreFrames_ = nil
        end
    end

    -- Ctrl+Z 撤销
    if input:GetKeyDown(KEY_CTRL) and input:GetKeyPress(KEY_Z) then
        M.UndoLevelEditor()
        return
    end

    -- Delete / Backspace 删除选中物件（TextField 正在编辑时不触发，优先退格）
    local focusedW = UI.GetFocus()
    local isTextEditing = focusedW and focusedW.OnTextInput and focusedW.state and focusedW.state.focused
    if (input:GetKeyPress(KEY_DELETE) or input:GetKeyPress(KEY_BACKSPACE)) and not isTextEditing then
        local key2 = levelEditor_.chapterIdx .. "_" .. levelEditor_.levelIdx
        local objs = levelEditor_.objects[key2] or {}
        if levelEditor_.selectedObj and objs[levelEditor_.selectedObj] then
            M.PushUndoState()
            local delIdx = levelEditor_.selectedObj
            table.remove(objs, delIdx)
            -- 清理映射引用
            for _, o in ipairs(objs) do
                if o.mappings then
                    for mi = #o.mappings, 1, -1 do
                        if o.mappings[mi] == delIdx then
                            table.remove(o.mappings, mi)
                        elseif o.mappings[mi] > delIdx then
                            o.mappings[mi] = o.mappings[mi] - 1
                        end
                    end
                end
            end
            levelEditor_.selectedObj = nil
            levelEditor_.mappingMode = false
            levelEditor_.mappingTriggerIdx = nil
            M.BuildLevelEditorUI()
            return
        end
    end

    -- Ctrl+C 复制选中物件
    if input:GetKeyDown(KEY_CTRL) and input:GetKeyPress(KEY_C) then
        local key2 = levelEditor_.chapterIdx .. "_" .. levelEditor_.levelIdx
        local objs = levelEditor_.objects[key2] or {}
        if levelEditor_.selectedObj and objs[levelEditor_.selectedObj] then
            M.PushUndoState()
            local src = objs[levelEditor_.selectedObj]
            local copy = { type = src.type, x = src.x + 1, y = src.y, w = src.w, h = src.h, name = src.name .. "_copy" }
            if src.mappings then
                copy.mappings = {}
            end
            -- 复制贴图属性
            if src.texture then
                copy.texture = src.texture
                copy.textureName = src.textureName
                copy.texScaleW = src.texScaleW
                copy.texScaleH = src.texScaleH
            end
            table.insert(objs, copy)
            levelEditor_.selectedObj = #objs
            M.BuildLevelEditorUI()
            return
        end
    end

    ---@type integer
    local ch = levelEditor_.chapterIdx
    ---@type integer
    local lv = levelEditor_.levelIdx
    local key = ch .. "_" .. lv
    local objects = levelEditor_.objects[key] or {}
    ---@type number
    local gridSize = levelEditor_.gridSize
    ---@type number
    local canvasOffX = levelEditor_.margin
    ---@type number
    local canvasOffY = levelEditor_.toolbarH + levelEditor_.margin
    ---@type number
    local canvasW = levelEditor_.canvasW
    ---@type number
    local canvasH = levelEditor_.canvasH

    local dpr = graphics:GetDPR()
    local mx = input.mousePosition.x / dpr
    local my = input.mousePosition.y / dpr
    local localX = mx - canvasOffX
    local localY = my - canvasOffY
    -- 内容空间坐标：减去画布平移偏移，用于 hit detection 和物件拖拽
    ---@type number
    local curPanX = levelEditor_.canvasPanX or 0
    ---@type number
    local curPanY = levelEditor_.canvasPanY or 0
    local contentX = localX - curPanX
    local contentY = localY - curPanY
    local mouseDown = input:GetMouseButtonDown(MOUSEB_LEFT)
    local mousePressed = input:GetMouseButtonPress(MOUSEB_LEFT)
    local mouseReleased = not mouseDown and (levelEditor_.dragging or levelEditor_.canvasPanning or levelEditor_.canvasPanPotential)

    -- 贴图工具：四角锚点拖拽缩放（支持多图层）
    if levelEditor_.currentTool == "texture" then
        -- 检测贴图四角锚点点击
        if mousePressed and localX >= 0 and localX < canvasW and localY >= 0 and localY < canvasH then
            local selIdx = levelEditor_.selectedObj
            if selIdx and objects[selIdx] then
                local obj = objects[selIdx]
                local px, py, pw, ph = M.WorldToCanvas(obj.x, obj.y, obj.w, obj.h)
                local handleSize = 10
                -- 优先检测多图层系统的选中层
                local tLayer = nil
                if obj.texLayers and #obj.texLayers > 0 and obj.selectedTexLayer then
                    tLayer = obj.texLayers[obj.selectedTexLayer]
                end
                if tLayer and tLayer.path and tLayer.path ~= "" then
                    local tScW = tLayer.scaleW or 1.0
                    local tScH = tLayer.scaleH or 1.0
                    local tW = pw * tScW
                    local tH = ph * tScH
                    local offL = (pw - tW) / 2
                    local offT = (ph - tH) / 2
                    -- 四角锚点坐标（左上、右上、左下、右下）
                    local corners = {
                        { x = px + offL,      y = py + offT,      type = "tl" },
                        { x = px + offL + tW, y = py + offT,      type = "tr" },
                        { x = px + offL,      y = py + offT + tH, type = "bl" },
                        { x = px + offL + tW, y = py + offT + tH, type = "br" },
                    }
                    for _, c in ipairs(corners) do
                        if math.abs(contentX - c.x) < handleSize and math.abs(contentY - c.y) < handleSize then
                            levelEditor_.texDragging = true
                            levelEditor_.texDragType = c.type
                            levelEditor_.texDragStartX = mx
                            levelEditor_.texDragStartY = my
                            levelEditor_.texDragStartW = tScW
                            levelEditor_.texDragStartH = tScH
                            levelEditor_.texDragObjPW = pw
                            levelEditor_.texDragObjPH = ph
                            M.PushUndoState()
                            break
                        end
                    end
                elseif obj.texture and obj.texture ~= "" then
                    -- 兼容旧单贴图模式（右下角缩放）
                    local tScW = obj.texScaleW or 1.0
                    local tScH = obj.texScaleH or 1.0
                    local anchorX = px + pw * tScW
                    local anchorY = py + ph * tScH
                    if math.abs(contentX - anchorX) < handleSize and math.abs(contentY - anchorY) < handleSize then
                        levelEditor_.texDragging = true
                        levelEditor_.texDragType = "scale"
                        levelEditor_.texDragStartX = mx
                        levelEditor_.texDragStartY = my
                        levelEditor_.texDragStartW = tScW
                        levelEditor_.texDragStartH = tScH
                        levelEditor_.texDragObjPW = pw
                        levelEditor_.texDragObjPH = ph
                        M.PushUndoState()
                    end
                end
            end
        end

        -- 拖拽更新（实时变化）
        if levelEditor_.texDragging and mouseDown then
            local selIdx = levelEditor_.selectedObj
            if selIdx and objects[selIdx] then
                local obj = objects[selIdx]
                local dx = mx - levelEditor_.texDragStartX
                local dy = my - levelEditor_.texDragStartY
                local pw = levelEditor_.texDragObjPW or 40
                local ph = levelEditor_.texDragObjPH or 40
                local dragType = levelEditor_.texDragType
                -- 多图层拖拽
                local tLayer = nil
                if obj.texLayers and #obj.texLayers > 0 and obj.selectedTexLayer then
                    tLayer = obj.texLayers[obj.selectedTexLayer]
                end
                if tLayer and dragType ~= "scale" then
                    -- 四角拖拽：根据角的方向计算缩放变化
                    local dw, dh = 0, 0
                    if dragType == "br" then
                        dw = dx / math.max(pw, 10)
                        dh = dy / math.max(ph, 10)
                    elseif dragType == "bl" then
                        dw = -dx / math.max(pw, 10)
                        dh = dy / math.max(ph, 10)
                    elseif dragType == "tr" then
                        dw = dx / math.max(pw, 10)
                        dh = -dy / math.max(ph, 10)
                    elseif dragType == "tl" then
                        dw = -dx / math.max(pw, 10)
                        dh = -dy / math.max(ph, 10)
                    end
                    tLayer.scaleW = math.max(0.1, levelEditor_.texDragStartW + dw)
                    tLayer.scaleH = math.max(0.1, levelEditor_.texDragStartH + dh)
                elseif dragType == "scale" then
                    -- 旧单贴图模式
                    local scaleFactorW = dx / math.max(pw, 10)
                    local scaleFactorH = dy / math.max(ph, 10)
                    obj.texScaleW = math.max(0.1, levelEditor_.texDragStartW + scaleFactorW)
                    obj.texScaleH = math.max(0.1, levelEditor_.texDragStartH + scaleFactorH)
                end
            end
        end

        -- 释放
        if levelEditor_.texDragging and not mouseDown then
            levelEditor_.texDragging = false
            levelEditor_.texDragType = nil
            levelEditor_.texDragObjPW = nil
            levelEditor_.texDragObjPH = nil
            M.BuildLevelEditorUI()
        end

        -- texture 工具下也检测物件点击（选中物件，使用内容空间坐标）
        if mousePressed and not levelEditor_.texDragging and localX >= 0 and localX < canvasW and localY >= 0 and localY < canvasH then
            local hitIdx = nil
            for i = #objects, 1, -1 do
                local obj = objects[i]
                local px, py, pw, ph = M.WorldToCanvas(obj.x, obj.y, obj.w, obj.h)
                pw = math.max(pw, 8)
                ph = math.max(ph, 8)
                if contentX >= px and contentX <= px + pw and contentY >= py and contentY <= py + ph then
                    hitIdx = i
                    break
                end
            end
            if hitIdx then
                levelEditor_.selectedObj = hitIdx
                levelEditor_.textureBrowseTarget = hitIdx
                levelEditor_.objHitThisFrame = true  -- 防止同帧触发背景拖拽
                M.BuildLevelEditorUI()
            end
        end

    end

    -- select/delete 工具预检：如果会命中物件则标记，防止同帧触发背景拖拽
    if mousePressed and not levelEditor_.objHitThisFrame
       and (levelEditor_.currentTool == "select" or levelEditor_.currentTool == "delete")
       and localX >= 0 and localX < canvasW and localY >= 0 and localY < canvasH then
        for i = #objects, 1, -1 do
            local obj = objects[i]
            local px, py, pw, ph = M.WorldToCanvas(obj.x, obj.y, obj.w, obj.h)
            pw = math.max(pw, 8)
            ph = math.max(ph, 8)
            if contentX >= px and contentX <= px + pw and contentY >= py and contentY <= py + ph then
                levelEditor_.objHitThisFrame = true
                break
            end
        end
    end

    -- 背景图层：锚点拖拽检测（四角缩放 + 拖拽移动）— 独立于工具类型
    if mousePressed and not levelEditor_.texDragging and not levelEditor_.bgDragging
       and not levelEditor_.camBoundsDragging and not levelEditor_.dragging and not levelEditor_.objHitThisFrame
       and localX >= 0 and localX < canvasW and localY >= 0 and localY < canvasH then
        local bgLayers = levelEditor_.bgLayers or {}
        local edWH = levelEditor_.worldH or 17.5
        local hitBg = false
        -- 先检测选中图层的锚点
        local selBgIdx = levelEditor_.selectedBgLayer
        if selBgIdx and bgLayers[selBgIdx] then
            local layer = bgLayers[selBgIdx]
            -- layer.y 是 Y-up 世界坐标（底边），需转为 top-down 画布坐标
            local canvasTopY = edWH - (layer.y or 0) - (layer.h or 6)
            local px, py, pw, ph = M.WorldToCanvas(layer.x or 0, canvasTopY, layer.w or 10, layer.h or 6)
            local anchorSize = 10
            local corners = {
                {px, py, "tl"},                 -- 左上
                {px + pw, py, "tr"},            -- 右上
                {px, py + ph, "bl"},            -- 左下
                {px + pw, py + ph, "br"},       -- 右下
            }
            for _, c in ipairs(corners) do
                if math.abs(contentX - c[1]) < anchorSize and math.abs(contentY - c[2]) < anchorSize then
                    levelEditor_.bgDragging = true
                    levelEditor_.bgDragType = c[3]
                    levelEditor_.bgDragStartMX = mx
                    levelEditor_.bgDragStartMY = my
                    levelEditor_.bgDragStartX = layer.x or 0
                    levelEditor_.bgDragStartY = layer.y or 0
                    levelEditor_.bgDragStartW = layer.w or 10
                    levelEditor_.bgDragStartH = layer.h or 6
                    hitBg = true
                    break
                end
            end
            -- 如果没有命中锚点，检测是否在图层区域内（拖拽移动）
            if not hitBg and contentX >= px and contentX <= px + pw and contentY >= py and contentY <= py + ph then
                levelEditor_.bgDragging = true
                levelEditor_.bgDragType = "move"
                levelEditor_.bgDragStartMX = mx
                levelEditor_.bgDragStartMY = my
                levelEditor_.bgDragStartX = layer.x or 0
                levelEditor_.bgDragStartY = layer.y or 0
                levelEditor_.bgDragStartW = layer.w or 10
                levelEditor_.bgDragStartH = layer.h or 6
                hitBg = true
            end
        end
        -- 如果没有命中选中图层，检测其他图层（点击选中，使用内容空间坐标）
        if not hitBg then
            for li = #bgLayers, 1, -1 do
                local layer = bgLayers[li]
                if layer.visible ~= false then
                    local cTopY = edWH - (layer.y or 0) - (layer.h or 6)
                    local px, py, pw, ph = M.WorldToCanvas(layer.x or 0, cTopY, layer.w or 10, layer.h or 6)
                    if contentX >= px and contentX <= px + pw and contentY >= py and contentY <= py + ph then
                        levelEditor_.selectedBgLayer = li
                        M.BuildLevelEditorUI()
                        hitBg = true
                        break
                    end
                end
            end
        end
    end

    -- ====== 镜头范围框：锚点拖拽检测 ======
    if mousePressed and levelEditor_.cameraBoundsEnabled and levelEditor_.cameraBounds
       and not levelEditor_.texDragging and not levelEditor_.bgDragging
       and not levelEditor_.camBoundsDragging and not levelEditor_.dragging
       and localX >= 0 and localX < canvasW and localY >= 0 and localY < canvasH then
        local cb = levelEditor_.cameraBounds
        local edWH = levelEditor_.worldH or 17.5
        local cbTopY = edWH - cb.y - cb.h
        local px, py, pw, ph = M.WorldToCanvas(cb.x, cbTopY, cb.w, cb.h)
        local anchorSize = 10
        local cbCorners = {
            {px, py, "tl"}, {px + pw, py, "tr"},
            {px, py + ph, "bl"}, {px + pw, py + ph, "br"},
        }
        local hitCB = false
        for _, c in ipairs(cbCorners) do
            if math.abs(contentX - c[1]) < anchorSize and math.abs(contentY - c[2]) < anchorSize then
                levelEditor_.camBoundsDragging = true
                levelEditor_.camBoundsDragType = c[3]
                levelEditor_.camBoundsDragStartMX = mx
                levelEditor_.camBoundsDragStartMY = my
                levelEditor_.camBoundsDragStartX = cb.x
                levelEditor_.camBoundsDragStartY = cb.y
                levelEditor_.camBoundsDragStartW = cb.w
                levelEditor_.camBoundsDragStartH = cb.h
                hitCB = true
                break
            end
        end
        -- 区域内拖拽移动
        if not hitCB and contentX >= px and contentX <= px + pw and contentY >= py and contentY <= py + ph then
            levelEditor_.camBoundsDragging = true
            levelEditor_.camBoundsDragType = "move"
            levelEditor_.camBoundsDragStartMX = mx
            levelEditor_.camBoundsDragStartMY = my
            levelEditor_.camBoundsDragStartX = cb.x
            levelEditor_.camBoundsDragStartY = cb.y
            levelEditor_.camBoundsDragStartW = cb.w
            levelEditor_.camBoundsDragStartH = cb.h
        end
    end

    -- 镜头范围框拖拽更新
    if levelEditor_.camBoundsDragging and mouseDown then
        local cb = levelEditor_.cameraBounds
        if cb then
            local worldW = levelEditor_.worldW or 30
            local worldH = levelEditor_.worldH or 17.5
            local dmx = (mx - levelEditor_.camBoundsDragStartMX) / canvasW * worldW
            local dmy = -(my - levelEditor_.camBoundsDragStartMY) / canvasH * worldH
            local dragType = levelEditor_.camBoundsDragType

            if dragType == "move" then
                cb.x = levelEditor_.camBoundsDragStartX + dmx
                cb.y = levelEditor_.camBoundsDragStartY + dmy
            elseif dragType == "br" then
                cb.w = math.max(2, levelEditor_.camBoundsDragStartW + dmx)
                local newH = math.max(2, levelEditor_.camBoundsDragStartH - dmy)
                cb.y = levelEditor_.camBoundsDragStartY - (newH - levelEditor_.camBoundsDragStartH)
                cb.h = newH
            elseif dragType == "bl" then
                local newW = math.max(2, levelEditor_.camBoundsDragStartW - dmx)
                cb.x = levelEditor_.camBoundsDragStartX + (levelEditor_.camBoundsDragStartW - newW)
                cb.w = newW
                local newH = math.max(2, levelEditor_.camBoundsDragStartH - dmy)
                cb.y = levelEditor_.camBoundsDragStartY - (newH - levelEditor_.camBoundsDragStartH)
                cb.h = newH
            elseif dragType == "tr" then
                cb.w = math.max(2, levelEditor_.camBoundsDragStartW + dmx)
                cb.h = math.max(2, levelEditor_.camBoundsDragStartH + dmy)
            elseif dragType == "tl" then
                local newW = math.max(2, levelEditor_.camBoundsDragStartW - dmx)
                cb.x = levelEditor_.camBoundsDragStartX + (levelEditor_.camBoundsDragStartW - newW)
                cb.w = newW
                cb.h = math.max(2, levelEditor_.camBoundsDragStartH + dmy)
            end
            -- 实时更新镜头范围框 UI 位置
            if levelEditor_.uiRoot then
                local edWH2 = levelEditor_.worldH or 17.5
                local cbTopY2 = edWH2 - cb.y - cb.h
                local cpx, cpy, cpw, cph = M.WorldToCanvas(cb.x, cbTopY2, cb.w, cb.h)
                local framePanel = levelEditor_.uiRoot:FindById("cam_bounds_frame")
                if framePanel then
                    framePanel:SetStyle({ left = cpx, top = cpy, width = math.max(cpw, 4), height = math.max(cph, 4) })
                end
            end
        end
    elseif levelEditor_.camBoundsDragging and not mouseDown then
        levelEditor_.camBoundsDragging = false
        levelEditor_.camBoundsDragType = nil
        M.BuildLevelEditorUI()
    end

    -- 背景图层拖拽更新（每帧实时跟随鼠标）
    if levelEditor_.bgDragging and mouseDown then
        local selBgIdx = levelEditor_.selectedBgLayer
        local bgLayers = levelEditor_.bgLayers or {}
        if selBgIdx and bgLayers[selBgIdx] then
            local layer = bgLayers[selBgIdx]
            -- 将鼠标位移转为世界坐标位移
            local worldW = levelEditor_.worldW or 30
            local worldH = levelEditor_.worldH or 17.5
            local dmx = (mx - levelEditor_.bgDragStartMX) / canvasW * worldW
            -- layer.y 是 Y-up 世界坐标，鼠标 my 是 top-down，所以取反
            local dmy = -(my - levelEditor_.bgDragStartMY) / canvasH * worldH
            local dragType = levelEditor_.bgDragType

            if dragType == "move" then
                layer.x = levelEditor_.bgDragStartX + dmx
                layer.y = levelEditor_.bgDragStartY + dmy
            elseif dragType == "br" then
                -- 右下角：宽度增大，底边下移（y减小）高度增大
                local newW = math.max(1, levelEditor_.bgDragStartW + dmx)
                local newH = math.max(1, levelEditor_.bgDragStartH - dmy)
                if layer.lockAspect and levelEditor_.bgDragStartW > 0.01 and levelEditor_.bgDragStartH > 0.01 then
                    local aspect = levelEditor_.bgDragStartW / levelEditor_.bgDragStartH
                    newH = newW / aspect
                end
                layer.w = newW
                layer.h = newH
                layer.y = levelEditor_.bgDragStartY - (newH - levelEditor_.bgDragStartH)
            elseif dragType == "bl" then
                -- 左下角：x随动，宽度反向，底边下移高度增大
                local newW = math.max(1, levelEditor_.bgDragStartW - dmx)
                local newH = math.max(1, levelEditor_.bgDragStartH - dmy)
                if layer.lockAspect and levelEditor_.bgDragStartW > 0.01 and levelEditor_.bgDragStartH > 0.01 then
                    local aspect = levelEditor_.bgDragStartW / levelEditor_.bgDragStartH
                    newH = newW / aspect
                end
                layer.x = levelEditor_.bgDragStartX + (levelEditor_.bgDragStartW - newW)
                layer.w = newW
                layer.h = newH
                layer.y = levelEditor_.bgDragStartY - (newH - levelEditor_.bgDragStartH)
            elseif dragType == "tr" then
                -- 右上角：宽度增大，顶边上移（底边不变）高度增大
                local newW = math.max(1, levelEditor_.bgDragStartW + dmx)
                local newH = math.max(1, levelEditor_.bgDragStartH + dmy)
                if layer.lockAspect and levelEditor_.bgDragStartW > 0.01 and levelEditor_.bgDragStartH > 0.01 then
                    local aspect = levelEditor_.bgDragStartW / levelEditor_.bgDragStartH
                    newH = newW / aspect
                end
                layer.w = newW
                layer.h = newH
            elseif dragType == "tl" then
                -- 左上角：x随动，宽度反向，顶边上移高度增大
                local newW = math.max(1, levelEditor_.bgDragStartW - dmx)
                local newH = math.max(1, levelEditor_.bgDragStartH + dmy)
                if layer.lockAspect and levelEditor_.bgDragStartW > 0.01 and levelEditor_.bgDragStartH > 0.01 then
                    local aspect = levelEditor_.bgDragStartW / levelEditor_.bgDragStartH
                    newH = newW / aspect
                end
                layer.x = levelEditor_.bgDragStartX + (levelEditor_.bgDragStartW - newW)
                layer.w = newW
                layer.h = newH
            end
        end
    end

    -- 背景图层拖拽释放
    if levelEditor_.bgDragging and not mouseDown then
        levelEditor_.bgDragging = false
        levelEditor_.bgDragType = nil
        M.BuildLevelEditorUI()
    end

    -- 映射模式：点击画布上的执行器建立映射关系
    if mousePressed and levelEditor_.mappingMode and levelEditor_.mappingTriggerIdx then
        if localX >= 0 and localX < canvasW and localY >= 0 and localY < canvasH then
            -- 检测点击到了哪个物件（使用内容空间坐标）
            for i = #objects, 1, -1 do
                local obj = objects[i]
                local px, py, pw, ph = M.WorldToCanvas(obj.x, obj.y, obj.w, obj.h)
                pw = math.max(pw, 8)
                ph = math.max(ph, 8)
                if contentX >= px and contentX <= px + pw and contentY >= py and contentY <= py + ph then
                    -- 只有执行器才能被映射
                    if obj.type == "executor" then
                        local trigger = objects[levelEditor_.mappingTriggerIdx]
                        if trigger and trigger.mappings then
                            -- 检查是否已存在此映射
                            local exists = false
                            for _, exIdx in ipairs(trigger.mappings) do
                                if exIdx == i then exists = true; break end
                            end
                            if not exists then
                                M.PushUndoState()
                                table.insert(trigger.mappings, i)
                                M.BuildLevelEditorUI()
                            end
                        end
                    end
                    break
                end
            end
            return
        end
    end

    -- 鼠标按下：检测是否点中了物件（select/delete 工具模式）
    if mousePressed and (levelEditor_.currentTool == "select" or levelEditor_.currentTool == "delete")
       and not levelEditor_.camBoundsDragging then
        -- 检查点击是否在画布范围内
        if localX >= 0 and localX < canvasW and localY >= 0 and localY < canvasH then
            -- 从后往前遍历（上层物件优先），使用内容空间坐标
            local hitIdx = nil
            for i = #objects, 1, -1 do
                local obj = objects[i]
                local px, py, pw, ph = M.WorldToCanvas(obj.x, obj.y, obj.w, obj.h)
                pw = math.max(pw, 8)
                ph = math.max(ph, 8)
                if contentX >= px and contentX <= px + pw and contentY >= py and contentY <= py + ph then
                    hitIdx = i
                    break
                end
            end
            if hitIdx then
                -- 删除工具：直接删除（先保存撤销状态）
                if levelEditor_.currentTool == "delete" then
                    M.PushUndoState()
                    table.remove(objects, hitIdx)
                    levelEditor_.selectedObj = nil
                    M.BuildLevelEditorUI()
                    return
                end
                -- 选择工具：开始拖拽
                local obj = objects[hitIdx]
                local px, py = M.WorldToCanvas(obj.x, obj.y, obj.w, obj.h)
                levelEditor_.dragging = true
                levelEditor_.dragObjIdx = hitIdx
                levelEditor_.dragOffsetX = contentX - px
                levelEditor_.dragOffsetY = contentY - py
                levelEditor_.dragStarted = false
                levelEditor_.mouseDownX = mx
                levelEditor_.mouseDownY = my
                levelEditor_.selectedObj = hitIdx
            else
                -- 点击空白处 → 进入潜在画布平移状态（等超过阈值再确认是拖拽还是点击）
                levelEditor_.canvasPanPotential = true
                levelEditor_.canvasPanStartX = mx
                levelEditor_.canvasPanStartY = my
                levelEditor_.canvasPanStartPanX = levelEditor_.canvasPanX
                levelEditor_.canvasPanStartPanY = levelEditor_.canvasPanY
            end
        end
    end

    -- 非 select/delete 模式：点击画布空白处也进入潜在平移状态
    if mousePressed and not levelEditor_.canvasPanPotential and not levelEditor_.canvasPanning
       and not levelEditor_.objHitThisFrame and not levelEditor_.texDragging and not levelEditor_.bgDragging
       and not levelEditor_.camBoundsDragging then
        local tool = levelEditor_.currentTool
        if tool ~= "select" and tool ~= "delete" then
            if localX >= 0 and localX < canvasW and localY >= 0 and localY < canvasH then
                -- 检测是否点中了已有物件（使用内容空间坐标）
                local hitObj = false
                for i = #objects, 1, -1 do
                    local obj = objects[i]
                    local px, py, pw, ph = M.WorldToCanvas(obj.x, obj.y, obj.w, obj.h)
                    pw = math.max(pw, 8)
                    ph = math.max(ph, 8)
                    if contentX >= px and contentX <= px + pw and contentY >= py and contentY <= py + ph then
                        hitObj = true
                        break
                    end
                end
                if not hitObj then
                    levelEditor_.canvasPanPotential = true
                    levelEditor_.canvasPanStartX = mx
                    levelEditor_.canvasPanStartY = my
                    levelEditor_.canvasPanStartPanX = levelEditor_.canvasPanX
                    levelEditor_.canvasPanStartPanY = levelEditor_.canvasPanY
                end
            end
        end
    end

    -- 拖拽中：更新物件位置
    if levelEditor_.dragging and mouseDown then
        local dx = math.abs(mx - levelEditor_.mouseDownX)
        local dy = math.abs(my - levelEditor_.mouseDownY)
        -- 超过 4px 阈值才开始拖拽（区分点击和拖拽）
        if not levelEditor_.dragStarted and (dx > 4 or dy > 4) then
            levelEditor_.dragStarted = true
            M.PushUndoState()  -- 拖拽开始前保存撤销状态
        end
        if levelEditor_.dragStarted and levelEditor_.dragObjIdx then
            local obj = objects[levelEditor_.dragObjIdx]
            if obj then
                -- 计算新的画布坐标（使用内容空间坐标，减去偏移）
                local newPx = contentX - levelEditor_.dragOffsetX
                local newPy = contentY - levelEditor_.dragOffsetY
                -- snap to grid
                newPx = math.floor(newPx / gridSize + 0.5) * gridSize
                newPy = math.floor(newPy / gridSize + 0.5) * gridSize
                -- 转为世界坐标
                local wx, wy = M.CanvasToWorld(newPx, newPy, 0, 0)
                obj.x = wx
                obj.y = wy
                -- 实时更新 UI 显示（通过 SetStyle 修改 top/left）
                if levelEditor_.uiRoot then
                    local objPanel = levelEditor_.uiRoot:FindById("obj_" .. levelEditor_.dragObjIdx)
                    if objPanel then
                        objPanel:SetStyle({ top = newPy, left = newPx })
                    end
                end
            end
        end
    end

    -- 画布潜在平移 → 超过阈值确认为拖拽平移
    if levelEditor_.canvasPanPotential and mouseDown and not levelEditor_.canvasPanning then
        local dx = math.abs(mx - levelEditor_.canvasPanStartX)
        local dy = math.abs(my - levelEditor_.canvasPanStartY)
        if dx > 4 or dy > 4 then
            -- 超过阈值，确认为画布平移拖拽
            levelEditor_.canvasPanPotential = false
            levelEditor_.canvasPanning = true
        end
    end

    -- 画布平移拖拽中：实时更新偏移跟随鼠标（只需移动内容容器）
    if levelEditor_.canvasPanning and mouseDown then
        local dx = mx - levelEditor_.canvasPanStartX
        local dy = my - levelEditor_.canvasPanStartY
        levelEditor_.canvasPanX = levelEditor_.canvasPanStartPanX + dx
        levelEditor_.canvasPanY = levelEditor_.canvasPanStartPanY + dy
        -- 实时移动 canvas_content 容器（网格+背景+物件一起动）
        if levelEditor_.uiRoot then
            local contentPanel = levelEditor_.uiRoot:FindById("canvas_content")
            if contentPanel then
                contentPanel:SetStyle({ left = levelEditor_.canvasPanX, top = levelEditor_.canvasPanY })
            end
        end
    end

    -- 鼠标释放：结束拖拽或确认选中
    if mouseReleased then
        -- 结束画布平移拖拽
        if levelEditor_.canvasPanning then
            levelEditor_.canvasPanning = false
            levelEditor_.canvasPanPotential = false
            levelEditor_.justPanned = true  -- 标记本次是拖拽平移，抑制点击事件
            M.BuildLevelEditorUI()  -- 重建UI确保所有元素位置与最终pan值一致
        elseif levelEditor_.canvasPanPotential then
            -- 未超过阈值 = 纯点击（非拖拽）
            levelEditor_.canvasPanPotential = false
            -- select/delete 模式：取消选中
            if levelEditor_.currentTool == "select" or levelEditor_.currentTool == "delete" then
                if levelEditor_.selectedObj then
                    levelEditor_.selectedObj = nil
                    M.BuildLevelEditorUI()
                end
            end
            -- 放置模式的点击由 canvas_click_layer onClick 处理，不需要这里额外触发
        end
        if levelEditor_.dragStarted then
            -- 物件拖拽结束，重建UI刷新属性面板
            M.BuildLevelEditorUI()
        elseif levelEditor_.dragObjIdx then
            -- 没有移动 = 纯点击选中，重建UI显示选中状态
            M.BuildLevelEditorUI()
        end
        levelEditor_.dragging = false
        levelEditor_.dragObjIdx = nil
        levelEditor_.dragStarted = false
    end

end

--- 构建关卡编辑器UI
function M.BuildLevelEditorUI()
    -- 保存右侧面板滚动位置
    local savedScrollY = 0
    if levelEditor_.uiRoot then
        local pp = levelEditor_.uiRoot:FindById("editor_props")
        if pp and pp.GetScroll then
            local _, sy = pp:GetScroll()
            savedScrollY = sy or 0
        end
        levelEditor_.uiRoot:Destroy()
    end
    levelEditor_.pendingScrollY_ = savedScrollY

    -- 动态计算画布尺寸（填满左侧区域，右侧留给属性面板）
    local dpr = graphics:GetDPR()
    local screenW = graphics:GetWidth() / dpr
    local screenH = graphics:GetHeight() / dpr
    local rightPanelW = 280
    local toolbarH = 50
    local margin = 8
    levelEditor_.canvasW = math.floor(screenW - rightPanelW - margin * 3)  -- left + gap + right边距
    levelEditor_.canvasH = math.floor(screenH - toolbarH - margin * 2)    -- toolbar + 上下边距
    -- 世界坐标范围按画布像素等比缩放（40px = 1米）
    local pixelsPerMeter = levelEditor_.gridSize  -- 40px = 1m
    levelEditor_.worldW = levelEditor_.canvasW / pixelsPerMeter
    levelEditor_.worldH = levelEditor_.canvasH / pixelsPerMeter

    local ch = levelEditor_.chapterIdx
    local lv = levelEditor_.levelIdx
    local chapName = CHAPTER_DATA[ch] and CHAPTER_DATA[ch].name or ("第" .. ch .. "章")
    local lvName = levelData_[ch][lv].name

    -- 顶部工具栏
    local toolbar = UI.Panel {
        position = "absolute", top = 0, left = 0,
        width = "100%", height = 50,
        flexDirection = "row", alignItems = "center",
        backgroundColor = {25, 22, 40, 250},
        paddingLeft = 16, paddingRight = 16, gap = 8,
    }
    -- 返回按钮
    toolbar:AddChild(UI.Button {
        paddingLeft = 12, paddingRight = 12, paddingTop = 6, paddingBottom = 6,
        backgroundColor = {60, 60, 80, 200}, borderRadius = 6,
        children = { UI.Label { text = "< 返回", fontSize = 14, fontColor = {200, 200, 220, 255} } },
        onClick = function() M.ExitLevelEditor() end,
    })
    toolbar:AddChild(UI.Label {
        text = chapName .. " " .. lvName .. " - 地形编辑器",
        fontSize = 16, fontColor = {200, 210, 240, 255}, marginLeft = 12,
    })
    -- 工具按钮
    toolbar:AddChild(UI.Panel { width = 30 }) -- spacer
    for _, tool in ipairs(EDITOR_TOOLS) do
        local tid = tool.id
        local isActive = (levelEditor_.currentTool == tid)
        toolbar:AddChild(UI.Button {
            id = "tool_" .. tid,
            paddingLeft = 10, paddingRight = 10, paddingTop = 5, paddingBottom = 5,
            backgroundColor = isActive and tool.color or {50, 50, 70, 200},
            borderRadius = 4, borderWidth = isActive and 2 or 0,
            borderColor = {255, 255, 255, 200},
            children = { UI.Label { text = tool.name, fontSize = 12, fontColor = {255, 255, 255, 255} } },
            onClick = function()
                levelEditor_.currentTool = tid
                levelEditor_.selectedObj = nil
                M.BuildLevelEditorUI()
            end,
        })
    end
    -- 导出/预览按钮
    toolbar:AddChild(UI.Panel { flexGrow = 1 }) -- push to right
    toolbar:AddChild(UI.Button {
        paddingLeft = 12, paddingRight = 12, paddingTop = 6, paddingBottom = 6,
        backgroundColor = {40, 160, 100, 220}, borderRadius = 6,
        children = { UI.Label { text = "预览", fontSize = 13, fontColor = {255, 255, 255, 255} } },
        onClick = function() M.StartPreview() end,
    })
    toolbar:AddChild(UI.Button {
        paddingLeft = 12, paddingRight = 12, paddingTop = 6, paddingBottom = 6,
        backgroundColor = {60, 100, 180, 220}, borderRadius = 6,
        children = { UI.Label { text = "导出", fontSize = 13, fontColor = {255, 255, 255, 255} } },
        onClick = function() M.ExportLevelTerrainData() end,
    })

    -- 画布区域（侧视图网格，自适应填满左侧区域）
    local canvasW = levelEditor_.canvasW
    local canvasH = levelEditor_.canvasH
    local canvas = UI.Panel {
        id = "editor_canvas",
        position = "absolute", top = toolbarH + margin, left = margin,
        width = canvasW, height = canvasH,
        backgroundColor = {10, 10, 25, 255},
        borderRadius = 4, borderWidth = 1, borderColor = {60, 60, 100, 150},
        overflow = "hidden",
    }

    -- 画布内容容器（所有网格/背景/物件都在此容器内，平移时只需偏移此容器）
    local panX = levelEditor_.canvasPanX or 0
    local panY = levelEditor_.canvasPanY or 0
    local canvasContent = UI.Panel {
        id = "canvas_content",
        position = "absolute", left = panX, top = panY,
        width = canvasW, height = canvasH,
        backgroundColor = {0, 0, 0, 0},
        pointerEvents = "none",  -- 不拦截点击，让下层 canvas_click_layer 处理
    }
    canvas:AddChild(canvasContent)

    -- 绘制网格线（用细条Panel模拟）
    local gridSize = levelEditor_.gridSize
    -- 垂直线
    for gx = 0, canvasW, gridSize do
        canvasContent:AddChild(UI.Panel {
            position = "absolute", top = 0, left = gx,
            width = 1, height = canvasH,
            backgroundColor = {40, 40, 60, 80},
            pointerEvents = "none",
        })
    end
    -- 水平线
    for gy = 0, canvasH, gridSize do
        canvasContent:AddChild(UI.Panel {
            position = "absolute", top = gy, left = 0,
            width = canvasW, height = 1,
            backgroundColor = {40, 40, 60, 80},
            pointerEvents = "none",
        })
    end

    -- ====== 背景图层贴图预览（UI层直接显示） ======
    -- 渲染顺序：列表上方（索引小）的层在视觉上层 → 逆序渲染
    local bgLayers = levelEditor_.bgLayers or {}
    local editorWorldH = levelEditor_.worldH or 17.5
    for li = #bgLayers, 1, -1 do
        local layer = bgLayers[li]
        if layer.visible ~= false and layer.path and layer.path ~= "" then
            local lx = layer.x or 0
            local ly = layer.y or 0
            local lw = layer.w or 10
            local lh = layer.h or 6
            -- layer.y 是 Y-up 世界坐标（底边），需转为 top-down 画布坐标
            local canvasTopY = editorWorldH - ly - lh
            local bpx, bpy, bpw, bph = M.WorldToCanvas(lx, canvasTopY, lw, lh)
            local isSel = (levelEditor_.selectedBgLayer == li)
            local opacity = layer.opacity or 1.0
            local alphaVal = math.floor(opacity * 255)
            canvasContent:AddChild(UI.Panel {
                position = "absolute",
                left = bpx, top = bpy,
                width = math.max(bpw, 4), height = math.max(bph, 4),
                backgroundImage = layer.path,
                backgroundFit = "fill",
                imageTint = {255, 255, 255, alphaVal},
                borderWidth = isSel and 2 or 1,
                borderColor = isSel and {200, 120, 255, 220} or {180, 100, 255, 100},
                pointerEvents = "none",
            })
        end
    end

    -- 画布点击事件（放在物件之前，这样物件按钮在上层能接收点击）
    local key = ch .. "_" .. lv
    local objects = levelEditor_.objects[key] or {}
    canvas:AddChild(UI.Button {
        id = "canvas_click_layer",
        position = "absolute", top = 0, left = 0,
        width = canvasW, height = canvasH,
        backgroundColor = {0, 0, 0, 0},
        onClick = function(self, eventData)
            -- 画布刚完成拖拽平移，抑制本次点击
            if levelEditor_.justPanned then
                levelEditor_.justPanned = false
                return
            end
            -- 正在进行画布平移拖拽中（已超过阈值），不放置
            if levelEditor_.canvasPanning then return end
            -- 映射模式下不放置物件（由 UpdateLevelEditor 处理）
            if levelEditor_.mappingMode then return end
            local tool = levelEditor_.currentTool
            -- select/delete/texture 由物件按钮自身处理点击
            if tool == "select" or tool == "delete" or tool == "texture" then
                return
            end
            -- 获取点击位置（相对于canvas，转为逻辑像素）
            local dpr = graphics:GetDPR()
            local mx = input.mousePosition.x / dpr
            local my = input.mousePosition.y / dpr
            -- 画布起点 = (margin, toolbarH + margin)
            local canvasOffX = margin
            local canvasOffY = toolbarH + margin
            local localX = mx - canvasOffX
            local localY = my - canvasOffY
            -- 转为内容空间坐标（减去画布平移偏移）
            local pnX = levelEditor_.canvasPanX or 0
            local pnY = levelEditor_.canvasPanY or 0
            local cX = localX - pnX
            local cY = localY - pnY
            -- snap to grid
            cX = math.floor(cX / gridSize) * gridSize
            cY = math.floor(cY / gridSize) * gridSize
            -- 转换为世界坐标
            local wx, wy, ww, wh = M.CanvasToWorld(cX, cY, gridSize * 3, gridSize)
            if tool == "ground" then
                ww = 6
                wh = 2
            elseif tool == "platform" then
                ww = 3
                wh = 0.5
            elseif tool == "obstacle" then
                ww = 1
                wh = 1
            elseif tool == "trigger" then
                ww = 1.5
                wh = 1.5
            elseif tool == "executor" then
                ww = 1.5
                wh = 1.5
            end
            M.PushUndoState()  -- 放置物件前保存撤销状态
            local newObj = { type = tool, x = wx, y = wy, w = ww, h = wh, name = tool .. #objects + 1 }
            -- 触发器/执行器额外初始化映射列表
            if tool == "trigger" or tool == "executor" then
                newObj.mappings = {}
            end
            table.insert(objects, newObj)
            levelEditor_.objects[key] = objects
            levelEditor_.selectedObj = #objects
            M.BuildLevelEditorUI()
        end,
    })

    -- 渲染已放置的物件（在 canvas_click_layer 之上，可接收点击）
    for idx, obj in ipairs(objects) do
        local objIdx = idx
        local px, py, pw, ph = M.WorldToCanvas(obj.x, obj.y, obj.w, obj.h)
        local objColor = M.GetObjectColor(obj.type)
        local isSelected = (levelEditor_.selectedObj == idx)

        -- 确定物件是否有贴图
        local hasTexLayers = (obj.texLayers and #obj.texLayers > 0) or obj.texture
        -- 获取第一个可见贴图路径（用于UI预览）
        local firstTexPath = nil
        local firstTexOpacity = 1.0
        if obj.texLayers and #obj.texLayers > 0 then
            for _, tl in ipairs(obj.texLayers) do
                if tl.visible ~= false and tl.path and tl.path ~= "" then
                    firstTexPath = tl.path
                    firstTexOpacity = tl.opacity or 1.0
                    break
                end
            end
        elseif obj.texture and obj.texture ~= "" then
            firstTexPath = obj.texture
        end

        -- 有贴图时隐藏占位色块（完全透明）
        local bgColor = objColor
        if firstTexPath then
            bgColor = {objColor[1], objColor[2], objColor[3], 0}
        end

        local objChildren = {}

        -- 贴图预览层（所有可见贴图图层叠加显示，使用物件颜色染色）
        -- 渲染顺序：列表上方（索引小）的层在视觉上层 → 逆序渲染（索引大的先渲染在底层）
        local tintCol = obj.color or {255, 255, 255, 255}
        if obj.texLayers and #obj.texLayers > 0 then
            for tli = #obj.texLayers, 1, -1 do
                local tLayer = obj.texLayers[tli]
                if tLayer.visible ~= false and tLayer.path and tLayer.path ~= "" then
                    local tScW = tLayer.scaleW or 1.0
                    local tScH = tLayer.scaleH or 1.0
                    local tAlpha = math.floor((tLayer.opacity or 1.0) * 255)
                    local tW = math.max(pw * tScW, 4)
                    local tH = math.max(ph * tScH, 4)
                    -- 居中偏移
                    local offL = (math.max(pw, 8) - tW) / 2
                    local offT = (math.max(ph, 8) - tH) / 2
                    table.insert(objChildren, UI.Panel {
                        position = "absolute",
                        left = offL, top = offT,
                        width = tW, height = tH,
                        backgroundImage = tLayer.path,
                        backgroundFit = "fill",
                        imageTint = {tintCol[1], tintCol[2], tintCol[3], tAlpha},
                        pointerEvents = "none",
                    })
                end
            end
        elseif obj.texture and obj.texture ~= "" then
            local tScW = obj.texScaleW or 1.0
            local tScH = obj.texScaleH or 1.0
            local tW = math.max(pw * tScW, 4)
            local tH = math.max(ph * tScH, 4)
            local offL = (math.max(pw, 8) - tW) / 2
            local offT = (math.max(ph, 8) - tH) / 2
            local singleAlpha = math.floor((tintCol[4] or 255))
            table.insert(objChildren, UI.Panel {
                position = "absolute",
                left = offL, top = offT,
                width = tW, height = tH,
                backgroundImage = obj.texture,
                backgroundFit = "fill",
                imageTint = {tintCol[1], tintCol[2], tintCol[3], singleAlpha},
                pointerEvents = "none",
            })
        end

        -- 名称标签
        table.insert(objChildren, UI.Label {
            text = obj.name or obj.type,
            fontSize = 9, fontColor = {255, 255, 255, 220},
            pointerEvents = "none",
        })

        -- 贴图层数指示器
        if hasTexLayers then
            local layerCount = obj.texLayers and #obj.texLayers or (obj.texture and 1 or 0)
            table.insert(objChildren, UI.Label {
                text = layerCount > 1 and ("T" .. layerCount) or "T",
                fontSize = 8, fontColor = {220, 160, 255, 255},
                position = "absolute", top = 1, right = 2,
                pointerEvents = "none",
            })
        end

        canvasContent:AddChild(UI.Button {
            id = "obj_" .. idx,
            position = "absolute",
            left = px, top = py,
            width = math.max(pw, 8), height = math.max(ph, 8),
            backgroundColor = bgColor,
            borderRadius = 2,
            borderWidth = isSelected and 3 or 1,
            borderColor = isSelected and {255, 255, 0, 255} or {255, 255, 255, 60},
            justifyContent = "center", alignItems = "center",
            overflow = "visible",
            children = objChildren,
            onClick = function()
                if levelEditor_.currentTool == "select" or levelEditor_.currentTool == "texture" then
                    levelEditor_.selectedObj = objIdx
                    if levelEditor_.currentTool == "texture" then
                        levelEditor_.textureBrowseTarget = objIdx
                    end
                    M.BuildLevelEditorUI()
                elseif levelEditor_.currentTool == "delete" then
                    table.remove(objects, objIdx)
                    levelEditor_.selectedObj = nil
                    M.BuildLevelEditorUI()
                end
            end,
        })
    end

    -- 贴图工具：在选中物件上绘制四角锚点指示
    if levelEditor_.currentTool == "texture" and levelEditor_.selectedObj then
        local selObj = objects[levelEditor_.selectedObj]
        if selObj then
            local px, py, pw, ph = M.WorldToCanvas(selObj.x, selObj.y, selObj.w, selObj.h)
            local handleS = 10
            -- 优先显示多图层选中层的锚点
            local tLayer = nil
            if selObj.texLayers and #selObj.texLayers > 0 and selObj.selectedTexLayer then
                tLayer = selObj.texLayers[selObj.selectedTexLayer]
            end
            if tLayer and tLayer.path and tLayer.path ~= "" then
                local tScW = tLayer.scaleW or 1.0
                local tScH = tLayer.scaleH or 1.0
                local tW = math.max(pw * tScW, 4)
                local tH = math.max(ph * tScH, 4)
                local offL = (pw - tW) / 2
                local offT = (ph - tH) / 2
                -- 贴图范围框
                canvasContent:AddChild(UI.Panel {
                    position = "absolute",
                    left = px + offL, top = py + offT,
                    width = tW, height = tH,
                    borderWidth = 1, borderColor = {200, 130, 255, 180},
                    backgroundColor = {160, 100, 220, 20},
                    borderRadius = 0,
                    pointerEvents = "none",
                })
                -- 四角锚点
                local corners = {
                    { l = px + offL - handleS/2,      t = py + offT - handleS/2 },
                    { l = px + offL + tW - handleS/2, t = py + offT - handleS/2 },
                    { l = px + offL - handleS/2,      t = py + offT + tH - handleS/2 },
                    { l = px + offL + tW - handleS/2, t = py + offT + tH - handleS/2 },
                }
                for _, c in ipairs(corners) do
                    canvasContent:AddChild(UI.Panel {
                        position = "absolute",
                        left = c.l, top = c.t,
                        width = handleS, height = handleS,
                        backgroundColor = {100, 220, 255, 255},
                        borderRadius = 2,
                        borderWidth = 1, borderColor = {255, 255, 255, 200},
                        pointerEvents = "none",
                    })
                end
            elseif selObj.texture and selObj.texture ~= "" then
                -- 兼容旧单贴图锚点
                local tScW = selObj.texScaleW or 1.0
                local tScH = selObj.texScaleH or 1.0
                canvasContent:AddChild(UI.Panel {
                    position = "absolute",
                    left = px, top = py,
                    width = math.max(pw * tScW, 4), height = math.max(ph * tScH, 4),
                    borderWidth = 1, borderColor = {200, 130, 255, 180},
                    backgroundColor = {160, 100, 220, 30},
                    borderRadius = 0,
                    pointerEvents = "none",
                })
                canvasContent:AddChild(UI.Panel {
                    position = "absolute",
                    left = px + pw * tScW - handleS/2,
                    top = py + ph * tScH - handleS/2,
                    width = handleS, height = handleS,
                    backgroundColor = {100, 220, 255, 255},
                    borderRadius = 2,
                    pointerEvents = "none",
                })
            end
        end
    end

    -- ====== 镜头范围框 UI 元素（黄色边框 + 四角锚点） ======
    if levelEditor_.cameraBoundsEnabled and levelEditor_.cameraBounds then
        local cb = levelEditor_.cameraBounds
        local edWorldH = levelEditor_.worldH or 17.5
        -- cameraBounds.y 是 Y-up 底边，转为 top-down 的 top 坐标
        local cbTopY = edWorldH - cb.y - cb.h
        local cbPx, cbPy, cbPw, cbPh = M.WorldToCanvas(cb.x, cbTopY, cb.w, cb.h)
        -- 范围框边框
        canvasContent:AddChild(UI.Panel {
            id = "cam_bounds_frame",
            position = "absolute",
            left = cbPx, top = cbPy,
            width = math.max(cbPw, 4), height = math.max(cbPh, 4),
            borderWidth = 2, borderColor = {255, 200, 50, 200},
            backgroundColor = {255, 220, 50, 10},
            borderRadius = 0,
            pointerEvents = "none",
        })
        -- 标签
        canvasContent:AddChild(UI.Panel {
            position = "absolute",
            left = cbPx, top = cbPy - 16,
            width = 70, height = 14,
            backgroundColor = {255, 200, 50, 180},
            borderRadius = 2,
            justifyContent = "center", alignItems = "center",
            pointerEvents = "none",
            children = {
                UI.Label { text = "镜头范围", fontSize = 9, fontColor = {30, 20, 0, 255} },
            },
        })
        -- 四角锚点
        local cbHandleS = 12
        local cbCorners = {
            { l = cbPx - cbHandleS/2,        t = cbPy - cbHandleS/2 },         -- 左上
            { l = cbPx + cbPw - cbHandleS/2, t = cbPy - cbHandleS/2 },         -- 右上
            { l = cbPx - cbHandleS/2,        t = cbPy + cbPh - cbHandleS/2 },  -- 左下
            { l = cbPx + cbPw - cbHandleS/2, t = cbPy + cbPh - cbHandleS/2 },  -- 右下
        }
        for _, c in ipairs(cbCorners) do
            canvasContent:AddChild(UI.Panel {
                position = "absolute",
                left = c.l, top = c.t,
                width = cbHandleS, height = cbHandleS,
                backgroundColor = {255, 200, 50, 240},
                borderRadius = 2,
                borderWidth = 1, borderColor = {255, 255, 255, 200},
                pointerEvents = "none",
            })
        end
    end

    -- 右侧属性面板
    local propsPanel = UI.Panel {
        id = "editor_props",
        position = "absolute", top = toolbarH + margin, right = margin, bottom = margin,
        width = rightPanelW,
        backgroundColor = {15, 15, 30, 240},
        borderRadius = 6, borderWidth = 1, borderColor = {60, 60, 100, 120},
        overflow = "scroll",
        flexDirection = "column",
        paddingTop = 12, paddingBottom = 12,
        paddingLeft = 10, paddingRight = 10,
        gap = 6,
    }
    M.BuildPropsPanel(propsPanel, objects)

    -- 根容器
    levelEditor_.uiRoot = UI.Panel {
        position = "absolute", top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = {12, 10, 22, 255},
        children = { canvas, toolbar, propsPanel },
    }

    -- 挂载到主菜单UI（如果关卡选择界面仍存在则在其上）
    if levelSelect_.uiRoot then
        levelSelect_.uiRoot:AddChild(levelEditor_.uiRoot)
    elseif S.mainMenuUIRoot then
        S.mainMenuUIRoot:AddChild(levelEditor_.uiRoot)
    end

    -- 延迟恢复右侧面板滚动位置（等待下一帧布局完成后执行）
    -- 立即尝试一次，同时设置延迟帧数确保下一帧再恢复一次
    if levelEditor_.pendingScrollY_ and levelEditor_.pendingScrollY_ > 0 then
        local pp = levelEditor_.uiRoot:FindById("editor_props")
        if pp and pp.SetScrollDirect then
            pp:SetScrollDirect(0, levelEditor_.pendingScrollY_)
        end
        -- 保留 pendingScrollY_，让 UpdateLevelEditor 在下一帧再恢复一次
        levelEditor_.scrollRestoreFrames_ = 2
    end

    -- 预览模式下，编辑器修改后刷新地形
    if levelEditor_.previewActive then
        M.RefreshPreviewTerrain()
    end
end

--- 构建右侧属性面板内容
function M.BuildPropsPanel(panel, objects)
    local ch = levelEditor_.chapterIdx
    local lv = levelEditor_.levelIdx
    local key = ch .. "_" .. lv

    panel:AddChild(UI.Label {
        text = "物件列表 (" .. #objects .. ")",
        fontSize = 14, fontColor = {180, 200, 255, 255}, marginBottom = 4,
    })

    -- 物件列表
    for idx, obj in ipairs(objects) do
        local objIdx = idx
        local isSelected = (levelEditor_.selectedObj == idx)
        local objColor = M.GetObjectColor(obj.type)

        local row = UI.Button {
            width = "100%", height = 28,
            flexDirection = "row", alignItems = "center", gap = 6,
            paddingLeft = 6, paddingRight = 6,
            backgroundColor = isSelected and {60, 60, 100, 200} or {30, 30, 50, 150},
            borderRadius = 4,
            onClick = function()
                levelEditor_.selectedObj = objIdx
                M.BuildLevelEditorUI()
            end,
        }
        row:AddChild(UI.Panel {
            width = 10, height = 10, borderRadius = 2,
            backgroundColor = objColor,
            pointerEvents = "none",
        })
        row:AddChild(UI.Label {
            text = obj.name .. " [" .. string.format("%.1f,%.1f", obj.x, obj.y) .. "]",
            fontSize = 11, fontColor = {200, 200, 220, 255},
            pointerEvents = "none",
        })
        panel:AddChild(row)
    end

    -- 选中物件的属性编辑
    if levelEditor_.selectedObj and objects[levelEditor_.selectedObj] then
        local obj = objects[levelEditor_.selectedObj]
        local selIdx = levelEditor_.selectedObj

        panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {80,80,120,100}, marginTop = 8, marginBottom = 4 })
        panel:AddChild(UI.Label {
            text = "编辑: " .. obj.name,
            fontSize = 13, fontColor = {255, 220, 150, 255},
        })

        -- 通用属性输入行构建函数（TextField + +/- 微调按钮）
        local function makeInputRow(label, value, onApply, step)
            step = step or 0.5
            local row = UI.Panel { flexDirection = "row", alignItems = "center", gap = 3, width = "100%", marginBottom = 2 }
            row:AddChild(UI.Label { text = label, fontSize = 11, fontColor = {150,150,180,255}, width = 20 })
            row:AddChild(UI.Button {
                text = "-", fontSize = 12, width = 20, height = 22,
                backgroundColor = {50, 50, 80, 220}, borderRadius = 3,
                justifyContent = "center", alignItems = "center",
                fontColor = {200,200,255,255},
                onClick = function()
                    M.PushUndoState()
                    onApply(value - step)
                    M.BuildLevelEditorUI()
                end,
            })
            row:AddChild(UI.TextField {
                value = string.format("%.1f", value),
                fontSize = 11, height = 22, width = 60,
                backgroundColor = {30, 30, 50, 255},
                borderRadius = 3, borderWidth = 1, borderColor = {80,80,120,200},
                fontColor = {255,255,255,255},
                paddingHorizontal = 4,
                onSubmit = function(self, text)
                    local num = tonumber(text)
                    if num then
                        M.PushUndoState()
                        onApply(num)
                        M.BuildLevelEditorUI()
                    end
                end,
                onBlur = function(self)
                    local txt = self:GetValue() or ""
                    local num = tonumber(txt)
                    if num and math.abs(num - value) > 0.001 then
                        M.PushUndoState()
                        onApply(num)
                        M.BuildLevelEditorUI()
                    end
                end,
            })
            row:AddChild(UI.Button {
                text = "+", fontSize = 12, width = 20, height = 22,
                backgroundColor = {50, 50, 80, 220}, borderRadius = 3,
                justifyContent = "center", alignItems = "center",
                fontColor = {200,200,255,255},
                onClick = function()
                    M.PushUndoState()
                    onApply(value + step)
                    M.BuildLevelEditorUI()
                end,
            })
            row:AddChild(UI.Label { text = "m", fontSize = 10, fontColor = {120,120,150,255} })
            return row
        end

        panel:AddChild(makeInputRow("X:", obj.x, function(v) obj.x = v end))
        panel:AddChild(makeInputRow("Y:", obj.y, function(v) obj.y = v end))
        panel:AddChild(makeInputRow("W:", obj.w, function(v) obj.w = math.max(0.5, v) end))
        panel:AddChild(makeInputRow("H:", obj.h, function(v) obj.h = math.max(0.5, v) end))

        -- ============ 颜色选择器 ============
        panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {80,80,120,100}, marginTop = 6, marginBottom = 4 })
        panel:AddChild(UI.Label { text = "物件颜色", fontSize = 12, fontColor = {200, 160, 255, 255} })

        local objColor = obj.color or {255, 255, 255, 255}
        local cr, cg, cb, ca = objColor[1], objColor[2], objColor[3], objColor[4] or 255

        -- 当前颜色预览 + 色号
        local colorPreviewRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, width = "100%", marginBottom = 4 }
        colorPreviewRow:AddChild(UI.Panel {
            width = 28, height = 28, borderRadius = 4,
            backgroundColor = {cr, cg, cb, ca},
            borderWidth = 1, borderColor = {180, 180, 220, 200},
        })
        colorPreviewRow:AddChild(UI.TextField {
            value = M.RGBtoHex(cr, cg, cb), fontSize = 10, width = 72, height = 22,
            backgroundColor = {30, 25, 55, 255}, fontColor = {220, 220, 255, 255},
            borderRadius = 3, paddingHorizontal = 4,
            onSubmit = function(self, txt)
                local r2, g2, b2 = M.HexToRGB(txt)
                M.ApplyColorToObject(selIdx, r2, g2, b2, ca)
            end,
            onBlur = function(self)
                local txt = self:GetValue() or ""
                if txt ~= M.RGBtoHex(cr, cg, cb) then
                    local r2, g2, b2 = M.HexToRGB(txt)
                    M.ApplyColorToObject(selIdx, r2, g2, b2, ca)
                end
            end,
        })
        -- 重置为白色按钮
        if cr ~= 255 or cg ~= 255 or cb ~= 255 then
            colorPreviewRow:AddChild(UI.Button {
                text = "重置", fontSize = 9, width = 32, height = 22,
                backgroundColor = {60, 50, 90, 220}, borderRadius = 3,
                justifyContent = "center", alignItems = "center", fontColor = {200, 200, 255, 255},
                onClick = function() M.ApplyColorToObject(selIdx, 255, 255, 255, 255) end,
            })
        end
        panel:AddChild(colorPreviewRow)

        -- RGB 输入行
        local function makeColorRow(label, value, channel)
            local row = UI.Panel { flexDirection = "row", alignItems = "center", gap = 2, width = "100%", marginBottom = 2 }
            row:AddChild(UI.Label { text = label, fontSize = 10, fontColor = {150,150,180,255}, width = 16 })
            row:AddChild(UI.Button {
                text = "-", fontSize = 11, width = 18, height = 20,
                backgroundColor = {50, 40, 80, 220}, borderRadius = 3,
                justifyContent = "center", alignItems = "center", fontColor = {200,200,255,255},
                onClick = function()
                    local nc = {cr, cg, cb, ca}
                    nc[channel] = math.max(0, nc[channel] - 15)
                    M.ApplyColorToObject(selIdx, nc[1], nc[2], nc[3], nc[4])
                end,
            })
            row:AddChild(UI.TextField {
                value = tostring(value), fontSize = 10, width = 40, height = 20,
                backgroundColor = {30, 25, 55, 255}, fontColor = {220,220,255,255},
                borderRadius = 3, paddingHorizontal = 4,
                onSubmit = function(self, txt)
                    local num = tonumber(txt)
                    if num then
                        num = math.max(0, math.min(255, math.floor(num)))
                        local nc = {cr, cg, cb, ca}
                        nc[channel] = num
                        M.ApplyColorToObject(selIdx, nc[1], nc[2], nc[3], nc[4])
                    end
                end,
                onBlur = function(self)
                    local txt = self:GetValue() or ""
                    local num = tonumber(txt)
                    if num and num ~= value then
                        num = math.max(0, math.min(255, math.floor(num)))
                        local nc = {cr, cg, cb, ca}
                        nc[channel] = num
                        M.ApplyColorToObject(selIdx, nc[1], nc[2], nc[3], nc[4])
                    end
                end,
            })
            row:AddChild(UI.Button {
                text = "+", fontSize = 11, width = 18, height = 20,
                backgroundColor = {50, 40, 80, 220}, borderRadius = 3,
                justifyContent = "center", alignItems = "center", fontColor = {200,200,255,255},
                onClick = function()
                    local nc = {cr, cg, cb, ca}
                    nc[channel] = math.min(255, nc[channel] + 15)
                    M.ApplyColorToObject(selIdx, nc[1], nc[2], nc[3], nc[4])
                end,
            })
            return row
        end
        panel:AddChild(makeColorRow("R:", cr, 1))
        panel:AddChild(makeColorRow("G:", cg, 2))
        panel:AddChild(makeColorRow("B:", cb, 3))

        -- 色环快捷色板（预设色轮 12色）
        local huePresets = {
            {255,60,60,255}, {255,140,60,255}, {255,220,60,255}, {160,255,60,255},
            {60,255,100,255}, {60,255,220,255}, {60,200,255,255}, {60,100,255,255},
            {140,60,255,255}, {220,60,255,255}, {255,60,200,255}, {255,60,120,255},
        }
        local hueRow = UI.Panel { flexDirection = "row", flexWrap = "wrap", gap = 3, width = "100%", marginTop = 4, marginBottom = 2 }
        for _, pc in ipairs(huePresets) do
            hueRow:AddChild(UI.Button {
                width = 18, height = 18, borderRadius = 9,
                backgroundColor = pc,
                borderWidth = 1, borderColor = {200,200,255,100},
                onClick = function()
                    M.ApplyColorToObject(selIdx, pc[1], pc[2], pc[3], 255)
                end,
            })
        end
        panel:AddChild(hueRow)

        -- 最近使用的颜色（10色记忆）
        if #levelEditor_.colorHistory > 0 then
            panel:AddChild(UI.Label { text = "最近使用", fontSize = 9, fontColor = {140,130,170,200}, marginTop = 2 })
            local histRow = UI.Panel { flexDirection = "row", flexWrap = "wrap", gap = 3, width = "100%", marginBottom = 2 }
            for _, hc in ipairs(levelEditor_.colorHistory) do
                histRow:AddChild(UI.Button {
                    width = 18, height = 18, borderRadius = 3,
                    backgroundColor = hc,
                    borderWidth = 1, borderColor = {180,180,220,150},
                    onClick = function()
                        M.ApplyColorToObject(selIdx, hc[1], hc[2], hc[3], hc[4] or 255)
                    end,
                })
            end
            panel:AddChild(histRow)
        end

        -- ============ 物件贴图图层 ============
        panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {80,80,120,100}, marginTop = 6, marginBottom = 4 })
        panel:AddChild(UI.Label { text = "物件贴图", fontSize = 12, fontColor = {200, 160, 255, 255} })

        -- 初始化 texLayers（兼容旧数据）
        if not obj.texLayers then obj.texLayers = {} end
        if obj.texture and #obj.texLayers == 0 then
            table.insert(obj.texLayers, {
                path = obj.texture, name = obj.textureName or obj.texture,
                opacity = 1.0, scaleW = obj.texScaleW or 1.0, scaleH = obj.texScaleH or 1.0, visible = true,
            })
            obj.texture = nil; obj.textureName = nil; obj.texScaleW = nil; obj.texScaleH = nil
        end

        -- 贴图图层列表
        if #obj.texLayers > 0 then
            for tli = 1, #obj.texLayers do
                local tLayer = obj.texLayers[tli]
                local isTSel = (obj.selectedTexLayer == tli)
                local tLayerRow = UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 2, width = "100%", marginBottom = 2,
                    backgroundColor = isTSel and {80, 60, 140, 180} or {30, 25, 55, 150},
                    borderRadius = 3, paddingLeft = 4, paddingRight = 2, paddingTop = 2, paddingBottom = 2,
                }
                -- 可见性
                local tlIdx = tli
                tLayerRow:AddChild(UI.Button {
                    text = tLayer.visible ~= false and "●" or "○", fontSize = 10, width = 16, height = 18,
                    backgroundColor = {0,0,0,0}, fontColor = tLayer.visible ~= false and {100,255,100,255} or {150,150,150,255},
                    onClick = function() M.PushUndoState(); tLayer.visible = not (tLayer.visible ~= false); M.BuildLevelEditorUI() end,
                })
                -- 名称（点击选中）
                tLayerRow:AddChild(UI.Button {
                    text = tli .. "." .. (tLayer.name or "贴图"), fontSize = 9, height = 18, flexGrow = 1,
                    backgroundColor = {0,0,0,0}, fontColor = {200,190,240,255},
                    onClick = function() obj.selectedTexLayer = tlIdx; M.BuildLevelEditorUI() end,
                })
                -- 上移
                tLayerRow:AddChild(UI.Button {
                    text = "↑", fontSize = 10, width = 16, height = 18,
                    backgroundColor = {50,40,80,180}, fontColor = {180,180,220,255}, borderRadius = 2,
                    onClick = function() M.MoveObjTexLayer(selIdx, tlIdx, -1); M.BuildLevelEditorUI() end,
                })
                -- 下移
                tLayerRow:AddChild(UI.Button {
                    text = "↓", fontSize = 10, width = 16, height = 18,
                    backgroundColor = {50,40,80,180}, fontColor = {180,180,220,255}, borderRadius = 2,
                    onClick = function() M.MoveObjTexLayer(selIdx, tlIdx, 1); M.BuildLevelEditorUI() end,
                })
                -- 删除
                tLayerRow:AddChild(UI.Button {
                    text = "×", fontSize = 11, width = 16, height = 18,
                    backgroundColor = {100,30,30,180}, fontColor = {255,180,180,255}, borderRadius = 2,
                    onClick = function() M.RemoveObjTexLayer(selIdx, tlIdx); M.BuildLevelEditorUI() end,
                })
                panel:AddChild(tLayerRow)
            end

            -- 选中贴图图层属性编辑
            local selTLayer = obj.selectedTexLayer and obj.texLayers[obj.selectedTexLayer]
            if selTLayer then
                panel:AddChild(UI.Label { text = "图层属性: " .. (selTLayer.name or ""), fontSize = 10, fontColor = {160,150,200,255}, marginTop = 4 })
                local function makeTexLayerRow(label, value, onApply, step, fmt)
                    step = step or 0.1
                    fmt = fmt or "%.2f"
                    local row = UI.Panel { flexDirection = "row", alignItems = "center", gap = 2, width = "100%", marginBottom = 2 }
                    row:AddChild(UI.Label { text = label, fontSize = 10, fontColor = {150,150,180,255}, width = 28 })
                    row:AddChild(UI.Button {
                        text = "-", fontSize = 11, width = 18, height = 20,
                        backgroundColor = {50, 40, 80, 220}, borderRadius = 3,
                        justifyContent = "center", alignItems = "center", fontColor = {200,200,255,255},
                        onClick = function() M.PushUndoState(); onApply(value - step); M.BuildLevelEditorUI() end,
                    })
                    row:AddChild(UI.TextField {
                        value = string.format(fmt, value), fontSize = 10, width = 50, height = 20,
                        backgroundColor = {30, 25, 55, 255}, fontColor = {220,220,255,255},
                        borderRadius = 3, paddingHorizontal = 4,
                        onSubmit = function(self, txt)
                            local num = tonumber(txt)
                            if num then M.PushUndoState(); onApply(num); M.BuildLevelEditorUI() end
                        end,
                        onBlur = function(self)
                            local txt = self:GetValue() or ""
                            local num = tonumber(txt)
                            if num and num ~= value then M.PushUndoState(); onApply(num); M.BuildLevelEditorUI() end
                        end,
                    })
                    row:AddChild(UI.Button {
                        text = "+", fontSize = 11, width = 18, height = 20,
                        backgroundColor = {50, 40, 80, 220}, borderRadius = 3,
                        justifyContent = "center", alignItems = "center", fontColor = {200,200,255,255},
                        onClick = function() M.PushUndoState(); onApply(value + step); M.BuildLevelEditorUI() end,
                    })
                    return row
                end
                panel:AddChild(makeTexLayerRow("透明:", selTLayer.opacity or 1.0, function(v) selTLayer.opacity = math.max(0, math.min(1, v)) end, 0.1))

                -- 固定宽高比选项
                local lockAspect = selTLayer.lockAspect or false
                local lockRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, width = "100%", marginBottom = 2 }
                lockRow:AddChild(UI.Button {
                    text = lockAspect and "☑" or "☐", fontSize = 13, width = 20, height = 20,
                    backgroundColor = {50, 40, 80, 220}, borderRadius = 3,
                    justifyContent = "center", alignItems = "center",
                    fontColor = lockAspect and {180, 255, 180, 255} or {150, 150, 180, 255},
                    onClick = function()
                        M.PushUndoState()
                        selTLayer.lockAspect = not (selTLayer.lockAspect or false)
                        M.BuildLevelEditorUI()
                    end,
                })
                lockRow:AddChild(UI.Label { text = "锁定宽高比", fontSize = 10, fontColor = {150, 150, 180, 255} })
                panel:AddChild(lockRow)

                -- 缩放宽（锁定时联动高）
                panel:AddChild(makeTexLayerRow("缩W:", selTLayer.scaleW or 1.0, function(v)
                    local oldW = selTLayer.scaleW or 1.0
                    local newW = math.max(0.1, v)
                    selTLayer.scaleW = newW
                    if selTLayer.lockAspect and oldW > 0.001 then
                        local ratio = newW / oldW
                        selTLayer.scaleH = math.max(0.1, (selTLayer.scaleH or 1.0) * ratio)
                    end
                end, 0.1))
                -- 缩放高（锁定时联动宽）
                panel:AddChild(makeTexLayerRow("缩H:", selTLayer.scaleH or 1.0, function(v)
                    local oldH = selTLayer.scaleH or 1.0
                    local newH = math.max(0.1, v)
                    selTLayer.scaleH = newH
                    if selTLayer.lockAspect and oldH > 0.001 then
                        local ratio = newH / oldH
                        selTLayer.scaleW = math.max(0.1, (selTLayer.scaleW or 1.0) * ratio)
                    end
                end, 0.1))
            end
        else
            panel:AddChild(UI.Label { text = "无贴图图层\n选择贴图工具添加", fontSize = 9, fontColor = {140,120,180,180}, marginTop = 2 })
        end

        -- 触发器/执行器：映射编辑
        if obj.type == "trigger" then
            panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {80,80,120,100}, marginTop = 6, marginBottom = 4 })

            -- ====== 触发方式 ======
            panel:AddChild(UI.Label { text = "触发方式", fontSize = 12, fontColor = {220, 180, 50, 255} })
            local triggerMethods = {"none", "touch", "interact", "attack", "other"}
            local triggerMethodNames = {none="无", touch="触碰", interact="交互", attack="攻击", other="其他"}
            local curTrigMethod = obj.triggerMethod or "none"
            local tmRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 3, width = "100%", marginBottom = 4, flexWrap = "wrap" }
            for _, tm in ipairs(triggerMethods) do
                local isCur = (curTrigMethod == tm)
                tmRow:AddChild(UI.Button {
                    text = triggerMethodNames[tm], fontSize = 10,
                    paddingLeft = 8, paddingRight = 8, paddingTop = 3, paddingBottom = 3,
                    backgroundColor = isCur and {200, 160, 30, 220} or {40, 40, 60, 200},
                    borderRadius = 3, borderWidth = isCur and 1 or 0,
                    borderColor = {255, 220, 80, 255},
                    fontColor = isCur and {255, 255, 255, 255} or {160, 160, 180, 255},
                    onClick = function()
                        M.PushUndoState()
                        obj.triggerMethod = tm
                        M.BuildLevelEditorUI()
                    end,
                })
            end
            panel:AddChild(tmRow)
            -- "其他"模式：显示自定义文本输入
            if curTrigMethod == "other" then
                local otherDesc = obj.triggerMethodDesc or ""
                panel:AddChild(UI.TextField {
                    value = otherDesc, fontSize = 10, width = "100%", height = 28,
                    backgroundColor = {30, 30, 50, 255}, fontColor = {240, 230, 160, 255},
                    borderRadius = 3, borderWidth = 1, borderColor = {180, 150, 50, 150},
                    paddingHorizontal = 6,
                    placeholder = "描述触发条件...",
                    onSubmit = function(self, txt)
                        obj.triggerMethodDesc = txt or ""
                    end,
                    onBlur = function(self)
                        obj.triggerMethodDesc = self:GetValue() or ""
                    end,
                })
            end

            panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {80,80,120,60}, marginTop = 4, marginBottom = 4 })
            local mappings = obj.mappings or {}
            panel:AddChild(UI.Label {
                text = "映射的执行器 (" .. #mappings .. ")",
                fontSize = 12, fontColor = {220, 180, 50, 255},
            })
            -- 列出已映射的执行器
            for mi, exIdx in ipairs(mappings) do
                local exObj = objects[exIdx]
                local exName = exObj and exObj.name or ("已删除#" .. exIdx)
                local mappingIdx = mi
                local mRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, width = "100%", marginBottom = 2 }
                mRow:AddChild(UI.Label {
                    text = "  -> " .. exName,
                    fontSize = 10, fontColor = {150, 200, 255, 255}, flexGrow = 1,
                })
                mRow:AddChild(UI.Button {
                    text = "x", fontSize = 9, width = 18, height = 18,
                    backgroundColor = {160, 50, 50, 200}, borderRadius = 3,
                    justifyContent = "center", alignItems = "center", fontColor = {255,255,255,255},
                    onClick = function()
                        M.PushUndoState()
                        table.remove(mappings, mappingIdx)
                        M.BuildLevelEditorUI()
                    end,
                })
                panel:AddChild(mRow)
            end
            -- 进入/退出映射编辑模式按钮
            local isMapping = levelEditor_.mappingMode and levelEditor_.mappingTriggerIdx == selIdx
            panel:AddChild(UI.Button {
                text = isMapping and "完成映射 (点击执行器添加)" or "编辑映射",
                fontSize = 11, marginTop = 4,
                width = "100%", height = 24,
                backgroundColor = isMapping and {180, 140, 30, 220} or {60, 120, 180, 220},
                borderRadius = 4, justifyContent = "center", alignItems = "center",
                fontColor = {255,255,255,255},
                onClick = function()
                    if isMapping then
                        levelEditor_.mappingMode = false
                        levelEditor_.mappingTriggerIdx = nil
                    else
                        levelEditor_.mappingMode = true
                        levelEditor_.mappingTriggerIdx = selIdx
                    end
                    M.BuildLevelEditorUI()
                end,
            })

            -- ====== 触发器策略节点 ======
            panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {80,80,120,80}, marginTop = 6, marginBottom = 4 })
            panel:AddChild(UI.Label { text = "触发策略", fontSize = 12, fontColor = {220, 180, 50, 255} })
            local StrategyEditor = require("StrategyEditor")
            panel:AddChild(StrategyEditor.Build(obj, "triggerStrategy", function() M.BuildLevelEditorUI() end, function() M.PushUndoState() end))

        elseif obj.type == "executor" then
            panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {80,80,120,100}, marginTop = 6, marginBottom = 4 })

            -- ====== 执行效果 ======
            panel:AddChild(UI.Label { text = "执行效果", fontSize = 12, fontColor = {50, 200, 120, 255} })
            local executorEffects = {"none", "other"}
            local executorEffectNames = {none="无", other="其他"}
            local curExEffect = obj.executorEffect or "none"
            local eeRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 3, width = "100%", marginBottom = 4 }
            for _, ef in ipairs(executorEffects) do
                local isCur = (curExEffect == ef)
                eeRow:AddChild(UI.Button {
                    text = executorEffectNames[ef], fontSize = 10,
                    paddingLeft = 10, paddingRight = 10, paddingTop = 3, paddingBottom = 3,
                    backgroundColor = isCur and {30, 180, 100, 220} or {40, 40, 60, 200},
                    borderRadius = 3, borderWidth = isCur and 1 or 0,
                    borderColor = {80, 255, 150, 255},
                    fontColor = isCur and {255, 255, 255, 255} or {160, 160, 180, 255},
                    onClick = function()
                        M.PushUndoState()
                        obj.executorEffect = ef
                        M.BuildLevelEditorUI()
                    end,
                })
            end
            panel:AddChild(eeRow)
            -- "其他"模式：显示自定义文本输入
            if curExEffect == "other" then
                local otherDesc = obj.executorEffectDesc or ""
                panel:AddChild(UI.TextField {
                    value = otherDesc, fontSize = 10, width = "100%", height = 28,
                    backgroundColor = {30, 30, 50, 255}, fontColor = {160, 240, 200, 255},
                    borderRadius = 3, borderWidth = 1, borderColor = {50, 180, 100, 150},
                    paddingHorizontal = 6,
                    placeholder = "描述执行效果...",
                    onSubmit = function(self, txt)
                        obj.executorEffectDesc = txt or ""
                    end,
                    onBlur = function(self)
                        obj.executorEffectDesc = self:GetValue() or ""
                    end,
                })
            end

            panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {80,80,120,100}, marginTop = 6, marginBottom = 4 })
            -- 列出关联的触发器
            local linkedTriggers = {}
            for i, o in ipairs(objects) do
                if o.type == "trigger" and o.mappings then
                    for _, exIdx in ipairs(o.mappings) do
                        if exIdx == selIdx then
                            table.insert(linkedTriggers, o.name)
                            break
                        end
                    end
                end
            end
            panel:AddChild(UI.Label {
                text = "关联触发器 (" .. #linkedTriggers .. ")",
                fontSize = 12, fontColor = {50, 160, 220, 255},
            })
            for _, tName in ipairs(linkedTriggers) do
                panel:AddChild(UI.Label {
                    text = "  <- " .. tName,
                    fontSize = 10, fontColor = {220, 200, 150, 255}, marginBottom = 2,
                })
            end
            panel:AddChild(UI.Label {
                text = "有物理碰撞",
                fontSize = 10, fontColor = {120, 180, 120, 200}, marginTop = 4,
            })

            -- ====== 执行器策略节点 ======
            panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {80,80,120,80}, marginTop = 6, marginBottom = 4 })
            panel:AddChild(UI.Label { text = "执行策略", fontSize = 12, fontColor = {50, 200, 120, 255} })
            local StrategyEditor = require("StrategyEditor")
            panel:AddChild(StrategyEditor.Build(obj, "executorStrategy", function() M.BuildLevelEditorUI() end, function() M.PushUndoState() end))
        end

        -- 删除按钮
        panel:AddChild(UI.Button {
            text = "删除此物件", fontSize = 12, marginTop = 8,
            width = "100%", height = 26,
            backgroundColor = {160, 50, 50, 220}, borderRadius = 4,
            justifyContent = "center", alignItems = "center",
            fontColor = {255,255,255,255},
            onClick = function()
                M.PushUndoState()
                table.remove(objects, selIdx)
                -- 清理映射引用
                for _, o in ipairs(objects) do
                    if o.mappings then
                        for mi = #o.mappings, 1, -1 do
                            if o.mappings[mi] == selIdx then
                                table.remove(o.mappings, mi)
                            elseif o.mappings[mi] > selIdx then
                                o.mappings[mi] = o.mappings[mi] - 1
                            end
                        end
                    end
                end
                levelEditor_.selectedObj = nil
                levelEditor_.mappingMode = false
                levelEditor_.mappingTriggerIdx = nil
                M.BuildLevelEditorUI()
            end,
        })
    end

    -- 映射模式提示
    if levelEditor_.mappingMode then
        panel:AddChild(UI.Panel {
            width = "100%", marginTop = 8, paddingTop = 6, paddingBottom = 6,
            paddingLeft = 6, paddingRight = 6,
            backgroundColor = {180, 140, 30, 40}, borderRadius = 4,
            borderWidth = 1, borderColor = {220, 180, 50, 150},
            children = {
                UI.Label {
                    text = "映射模式\n点击画布上的执行器\n建立映射关系",
                    fontSize = 10, fontColor = {220, 200, 100, 255},
                },
            },
        })
    end

    -- ====== 镜头范围框编辑 ======
    panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {200, 160, 50, 120}, marginTop = 8, marginBottom = 4 })
    do
        local cbEnabled = levelEditor_.cameraBoundsEnabled or false
        local headerRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, width = "100%", marginBottom = 4 }
        headerRow:AddChild(UI.Button {
            text = cbEnabled and "☑" or "☐", fontSize = 13, width = 20, height = 20,
            backgroundColor = {50, 50, 30, 220}, borderRadius = 3,
            justifyContent = "center", alignItems = "center",
            fontColor = cbEnabled and {255, 220, 100, 255} or {150, 150, 130, 255},
            onClick = function()
                levelEditor_.cameraBoundsEnabled = not (levelEditor_.cameraBoundsEnabled or false)
                if levelEditor_.cameraBoundsEnabled and not levelEditor_.cameraBounds then
                    -- 首次启用：初始化为略小于世界的范围（确保可见）
                    local wW = levelEditor_.worldW or 30
                    local wH = levelEditor_.worldH or 17.5
                    levelEditor_.cameraBounds = {
                        x = wW * 0.05, y = wH * 0.05,
                        w = wW * 0.9, h = wH * 0.9,
                    }
                end
                M.BuildLevelEditorUI()
            end,
        })
        headerRow:AddChild(UI.Label { text = "镜头范围框", fontSize = 12, fontColor = {220, 200, 100, 255} })
        panel:AddChild(headerRow)

        if cbEnabled and levelEditor_.cameraBounds then
            local cb = levelEditor_.cameraBounds
            local function makeCBRow(label, value, onApply, step, fmt)
                step = step or 1
                fmt = fmt or "%.1f"
                local row = UI.Panel { flexDirection = "row", alignItems = "center", gap = 2, width = "100%", marginBottom = 2 }
                row:AddChild(UI.Label { text = label, fontSize = 10, fontColor = {180, 170, 120, 255}, width = 32 })
                row:AddChild(UI.Button {
                    text = "-", fontSize = 11, width = 18, height = 20,
                    backgroundColor = {50, 50, 30, 220}, borderRadius = 3,
                    justifyContent = "center", alignItems = "center", fontColor = {220, 200, 150, 255},
                    onClick = function() onApply(value - step); M.BuildLevelEditorUI() end,
                })
                row:AddChild(UI.TextField {
                    value = string.format(fmt, value), fontSize = 10, width = 56, height = 20,
                    backgroundColor = {30, 30, 20, 255}, fontColor = {240, 230, 160, 255},
                    borderRadius = 3, paddingHorizontal = 4,
                    onSubmit = function(self, txt)
                        local num = tonumber(txt)
                        if num then onApply(num); M.BuildLevelEditorUI() end
                    end,
                    onBlur = function(self)
                        local txt = self:GetValue() or ""
                        local num = tonumber(txt)
                        if num and num ~= value then onApply(num); M.BuildLevelEditorUI() end
                    end,
                })
                row:AddChild(UI.Button {
                    text = "+", fontSize = 11, width = 18, height = 20,
                    backgroundColor = {50, 50, 30, 220}, borderRadius = 3,
                    justifyContent = "center", alignItems = "center", fontColor = {220, 200, 150, 255},
                    onClick = function() onApply(value + step); M.BuildLevelEditorUI() end,
                })
                return row
            end
            panel:AddChild(makeCBRow("X:", cb.x or 0, function(v) cb.x = v end, 1, "%.1f"))
            panel:AddChild(makeCBRow("Y:", cb.y or 0, function(v) cb.y = v end, 1, "%.1f"))
            panel:AddChild(makeCBRow("宽:", cb.w or 30, function(v) cb.w = math.max(2, v) end, 1, "%.1f"))
            panel:AddChild(makeCBRow("高:", cb.h or 17.5, function(v) cb.h = math.max(2, v) end, 1, "%.1f"))
            -- 重置按钮
            panel:AddChild(UI.Button {
                text = "重置为世界大小", fontSize = 10, width = "100%", height = 22, marginTop = 2,
                backgroundColor = {60, 60, 40, 200}, borderRadius = 3,
                justifyContent = "center", alignItems = "center",
                fontColor = {200, 190, 130, 255},
                onClick = function()
                    local wW = levelEditor_.worldW or 30
                    local wH = levelEditor_.worldH or 17.5
                    levelEditor_.cameraBounds = {
                        x = wW * 0.05, y = wH * 0.05,
                        w = wW * 0.9, h = wH * 0.9,
                    }
                    M.BuildLevelEditorUI()
                end,
            })
        end
    end

    -- 贴图工具面板
    if levelEditor_.currentTool == "texture" then
        panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {120,80,180,120}, marginTop = 8, marginBottom = 4 })
        panel:AddChild(UI.Label {
            text = "贴图素材库",
            fontSize = 13, fontColor = {200, 160, 255, 255},
        })

        -- 背景图层管理（多图层）
        panel:AddChild(UI.Button {
            text = "添加背景图层", fontSize = 11, marginTop = 4, width = "100%", height = 24,
            backgroundColor = levelEditor_.textureBrowseTarget == "bg" and {120, 80, 180, 220} or {50, 40, 80, 220},
            borderRadius = 4, justifyContent = "center", alignItems = "center",
            fontColor = {220, 200, 255, 255},
            borderWidth = levelEditor_.textureBrowseTarget == "bg" and 2 or 0,
            borderColor = {200, 160, 255, 255},
            onClick = function()
                levelEditor_.textureBrowseTarget = "bg"
                M.BuildLevelEditorUI()
            end,
        })

        -- 图层列表
        local bgLayers = levelEditor_.bgLayers
        if #bgLayers > 0 then
            panel:AddChild(UI.Label { text = "背景图层 (" .. #bgLayers .. "层)", fontSize = 11, fontColor = {180,160,220,255}, marginTop = 4 })
            for li = 1, #bgLayers do
                local layer = bgLayers[li]
                local isSel = (levelEditor_.selectedBgLayer == li)
                local layerRow = UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 2, width = "100%", marginBottom = 2,
                    backgroundColor = isSel and {80, 60, 140, 180} or {30, 25, 55, 150},
                    borderRadius = 3, paddingLeft = 4, paddingRight = 2, paddingTop = 2, paddingBottom = 2,
                }
                -- 可见性
                layerRow:AddChild(UI.Button {
                    text = layer.visible ~= false and "●" or "○", fontSize = 10, width = 16, height = 18,
                    backgroundColor = {0,0,0,0}, fontColor = layer.visible ~= false and {100,255,100,255} or {150,150,150,255},
                    onClick = function() layer.visible = not (layer.visible ~= false); M.BuildLevelEditorUI() end,
                })
                -- 名称（点击选中）
                layerRow:AddChild(UI.Button {
                    text = li .. "." .. (layer.name or "图层"), fontSize = 9, height = 18, flexGrow = 1,
                    backgroundColor = {0,0,0,0}, fontColor = {200,190,240,255},
                    onClick = function() levelEditor_.selectedBgLayer = li; M.BuildLevelEditorUI() end,
                })
                -- 上移
                layerRow:AddChild(UI.Button {
                    text = "↑", fontSize = 10, width = 16, height = 18,
                    backgroundColor = {50,40,80,180}, fontColor = {180,180,220,255}, borderRadius = 2,
                    onClick = function() M.MoveBgLayer(li, -1); M.BuildLevelEditorUI() end,
                })
                -- 下移
                layerRow:AddChild(UI.Button {
                    text = "↓", fontSize = 10, width = 16, height = 18,
                    backgroundColor = {50,40,80,180}, fontColor = {180,180,220,255}, borderRadius = 2,
                    onClick = function() M.MoveBgLayer(li, 1); M.BuildLevelEditorUI() end,
                })
                -- 删除
                layerRow:AddChild(UI.Button {
                    text = "×", fontSize = 11, width = 16, height = 18,
                    backgroundColor = {100,30,30,180}, fontColor = {255,180,180,255}, borderRadius = 2,
                    onClick = function() M.RemoveBgLayer(li); M.BuildLevelEditorUI() end,
                })
                panel:AddChild(layerRow)
            end

            -- 选中图层属性编辑
            local selLayer = levelEditor_.selectedBgLayer and bgLayers[levelEditor_.selectedBgLayer]
            if selLayer then
                panel:AddChild(UI.Label { text = "图层属性: " .. (selLayer.name or ""), fontSize = 10, fontColor = {160,150,200,255}, marginTop = 4 })
                local function makeLayerRow(label, value, onApply, step, fmt)
                    step = step or 0.1
                    fmt = fmt or "%.2f"
                    local displayVal = string.format(fmt, value):gsub("°$", "")
                    local row = UI.Panel { flexDirection = "row", alignItems = "center", gap = 2, width = "100%", marginBottom = 2 }
                    row:AddChild(UI.Label { text = label, fontSize = 10, fontColor = {150,150,180,255}, width = 32 })
                    row:AddChild(UI.Button {
                        text = "-", fontSize = 11, width = 18, height = 20,
                        backgroundColor = {50, 40, 80, 220}, borderRadius = 3,
                        justifyContent = "center", alignItems = "center", fontColor = {200,200,255,255},
                        onClick = function() onApply(value - step); M.BuildLevelEditorUI() end,
                    })
                    row:AddChild(UI.TextField {
                        value = displayVal, fontSize = 10, width = 56, height = 20,
                        backgroundColor = {30, 25, 55, 255}, fontColor = {220,220,255,255},
                        borderRadius = 3, paddingHorizontal = 4,
                        onSubmit = function(self, txt)
                            local num = tonumber(txt)
                            if num then onApply(num); M.BuildLevelEditorUI() end
                        end,
                        onBlur = function(self)
                            local txt = self:GetValue() or ""
                            local num = tonumber(txt)
                            if num and num ~= value then onApply(num); M.BuildLevelEditorUI() end
                        end,
                    })
                    row:AddChild(UI.Button {
                        text = "+", fontSize = 11, width = 18, height = 20,
                        backgroundColor = {50, 40, 80, 220}, borderRadius = 3,
                        justifyContent = "center", alignItems = "center", fontColor = {200,200,255,255},
                        onClick = function() onApply(value + step); M.BuildLevelEditorUI() end,
                    })
                    return row
                end
                panel:AddChild(makeLayerRow("X:", selLayer.x or 0, function(v) selLayer.x = v end, 1, "%.1f"))
                panel:AddChild(makeLayerRow("Y:", selLayer.y or 0, function(v) selLayer.y = v end, 1, "%.1f"))
                -- 锁定宽高比选项
                local bgLockAspect = selLayer.lockAspect or false
                local bgLockRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, width = "100%", marginBottom = 2 }
                bgLockRow:AddChild(UI.Button {
                    text = bgLockAspect and "☑" or "☐", fontSize = 13, width = 20, height = 20,
                    backgroundColor = {50, 40, 80, 220}, borderRadius = 3,
                    justifyContent = "center", alignItems = "center",
                    fontColor = bgLockAspect and {180, 255, 180, 255} or {150, 150, 180, 255},
                    onClick = function()
                        M.PushUndoState()
                        selLayer.lockAspect = not (selLayer.lockAspect or false)
                        M.BuildLevelEditorUI()
                    end,
                })
                bgLockRow:AddChild(UI.Label { text = "锁定宽高比", fontSize = 10, fontColor = {150, 150, 180, 255} })
                panel:AddChild(bgLockRow)
                panel:AddChild(makeLayerRow("宽:", selLayer.w or 10, function(v)
                    local oldW = selLayer.w or 10
                    local newW = math.max(0.5, v)
                    selLayer.w = newW
                    if selLayer.lockAspect and oldW > 0.01 then
                        local ratio = newW / oldW
                        selLayer.h = math.max(0.5, (selLayer.h or 6) * ratio)
                    end
                end, 1, "%.1f"))
                panel:AddChild(makeLayerRow("高:", selLayer.h or 6, function(v)
                    local oldH = selLayer.h or 6
                    local newH = math.max(0.5, v)
                    selLayer.h = newH
                    if selLayer.lockAspect and oldH > 0.01 then
                        local ratio = newH / oldH
                        selLayer.w = math.max(0.5, (selLayer.w or 10) * ratio)
                    end
                end, 1, "%.1f"))
                panel:AddChild(makeLayerRow("透明:", selLayer.opacity or 1.0, function(v) selLayer.opacity = math.max(0, math.min(1, v)) end, 0.1))
                panel:AddChild(makeLayerRow("景深:", selLayer.depth or 0, function(v) selLayer.depth = math.max(0, v) end, 0.1, "%.1f"))
            end
        end

        -- 如果有选中物件，可对其添加贴图图层
        if levelEditor_.selectedObj and objects[levelEditor_.selectedObj] then
            local selObj = objects[levelEditor_.selectedObj]
            local texLayerCount = selObj.texLayers and #selObj.texLayers or 0
            panel:AddChild(UI.Button {
                text = "添加贴图到物件 (" .. texLayerCount .. "层)",
                fontSize = 11, marginTop = 4, width = "100%", height = 24,
                backgroundColor = (type(levelEditor_.textureBrowseTarget) == "number") and {120, 80, 180, 220} or {50, 40, 80, 220},
                borderRadius = 4, justifyContent = "center", alignItems = "center",
                fontColor = {220, 200, 255, 255},
                borderWidth = (type(levelEditor_.textureBrowseTarget) == "number") and 2 or 0,
                borderColor = {200, 160, 255, 255},
                onClick = function()
                    levelEditor_.textureBrowseTarget = levelEditor_.selectedObj
                    M.BuildLevelEditorUI()
                end,
            })
        end

        -- 已导入素材列表（点击应用到当前目标）
        if #levelEditor_.customTextures > 0 then
            panel:AddChild(UI.Label { text = "已导入素材 (点击应用):", fontSize = 10, fontColor = {150,140,180,255}, marginTop = 6 })
            for tidx, asset in ipairs(levelEditor_.customTextures) do
                local assetPath = asset.path
                local assetName = asset.name
                local catLabel = asset.cat == "bg" and "[背景]" or (asset.cat == "tile" and "[地面]" or "[其他]")
                panel:AddChild(UI.Button {
                    text = catLabel .. " " .. assetName, fontSize = 11, width = "100%", height = 26, marginBottom = 2,
                    backgroundColor = {40, 35, 70, 200}, borderRadius = 4,
                    justifyContent = "center", alignItems = "center",
                    fontColor = {200, 180, 255, 255},
                    borderWidth = 1, borderColor = {100, 80, 160, 150},
                    onClick = function()
                        local target = levelEditor_.textureBrowseTarget
                        if target == "bg" then
                            -- 多图层模式：添加为新背景图层
                            M.AddBgLayer(assetPath, assetName)
                        elseif type(target) == "number" and objects[target] then
                            -- 多贴图图层模式：添加为新贴图图层
                            M.AddObjTexLayer(target, assetPath, assetName)
                        end
                        M.BuildLevelEditorUI()
                    end,
                })
            end
        else
            panel:AddChild(UI.Label {
                text = "暂无素材\n请将图片发给AI并说\n「导入编辑器」来添加",
                fontSize = 9, fontColor = {140, 120, 180, 180}, marginTop = 6,
            })
        end

        -- 提示
        if not levelEditor_.textureBrowseTarget then
            panel:AddChild(UI.Label {
                text = "先点击「设置背景」或\n选中物件后点击「为物件贴图」\n再从列表选择素材",
                fontSize = 9, fontColor = {140, 120, 180, 180}, marginTop = 4,
            })
        end
    end

    -- 底部说明
    panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {60,60,80,80}, marginTop = 10 })
    panel:AddChild(UI.Label {
        text = "操作: 选工具后点画布放置\n选择工具点击物件编辑\nEnter确认输入 | Del删除\nCtrl+C复制 | Ctrl+Z撤销",
        fontSize = 10, fontColor = {120, 120, 150, 200}, marginTop = 4,
    })
end

--- 世界坐标转画布像素（含平移偏移）
function M.WorldToCanvas(wx, wy, ww, wh)
    local cW = levelEditor_.canvasW or 0
    local cH = levelEditor_.canvasH or 0
    local worldW = levelEditor_.worldW or 30
    local worldH = levelEditor_.worldH or 17.5
    if worldW <= 0 then worldW = 30 end
    if worldH <= 0 then worldH = 17.5 end
    local scaleX = cW / worldW
    local scaleY = cH / worldH
    local px = wx * scaleX
    local py = wy * scaleY
    local pw = ww * scaleX
    local ph = wh * scaleY
    return px, py, pw, ph
end

--- 画布像素转世界坐标（纯缩放，pan 偏移由容器层处理）
function M.CanvasToWorld(cx, cy, cw, ch)
    local canvasW = levelEditor_.canvasW
    local canvasH = levelEditor_.canvasH
    local worldW = levelEditor_.worldW
    local worldH = levelEditor_.worldH
    local wx = cx / canvasW * worldW
    local wy = cy / canvasH * worldH
    local ww = cw / canvasW * worldW
    local wh = ch / canvasH * worldH
    return wx, wy, ww, wh
end

--- 获取物件类型对应颜色
function M.GetObjectColor(objType)
    if objType == "platform" then return {60, 160, 60, 220}
    elseif objType == "obstacle" then return {200, 50, 50, 220}
    elseif objType == "trigger" then return {220, 180, 50, 220}
    elseif objType == "executor" then return {50, 160, 220, 220}
    elseif objType == "ground" then return {130, 95, 50, 220}
    else return {100, 100, 100, 200}
    end
end

-- ============================================================================
-- 预览模式
-- ============================================================================

--- 启动预览模式（根据编辑器数据生成物理地形和玩家角色）
function M.StartPreview()
    if levelEditor_.previewActive then return end

    local ch = levelEditor_.chapterIdx
    local lv = levelEditor_.levelIdx
    local key = ch .. "_" .. lv
    local objects = levelEditor_.objects[key] or {}

    if #objects == 0 then
        print("[PREVIEW] 没有物件，无法预览")
        return
    end

    -- 隐藏编辑器UI和关卡选择UI（否则UI层覆盖NanoVG渲染）
    if levelEditor_.uiRoot then
        levelEditor_.uiRoot:SetVisible(false)
    end
    if levelSelect_.uiRoot then
        levelSelect_.uiRoot:SetVisible(false)
    end

    -- 创建预览场景
    local scene = Scene()
    scene:CreateComponent("Octree")
    scene:CreateComponent("DebugRenderer")

    local physicsWorld = scene:CreateComponent("PhysicsWorld2D")
    physicsWorld.gravity = Vector2(0, -25.0)
    physicsWorld.autoClearForces = true

    -- 正交相机（orthoSize = 游戏实际视口高度，让预览真正模拟游戏画面）
    local cameraNode = scene:CreateChild("PreviewCamera")
    local camera = cameraNode:CreateComponent("Camera")
    camera.orthographic = true
    camera.orthoSize = C.SCREEN_HEIGHT / C.PIXELS_PER_UNIT  -- 12m = 游戏实际视口高度
    cameraNode.position = Vector3(levelEditor_.worldW / 2, levelEditor_.worldH / 2, -10)

    renderer:SetViewport(0, Viewport:new(scene, camera))

    -- 生成地形物件
    local previewNodes = {}
    for _, obj in ipairs(objects) do
        local node = scene:CreateChild(obj.name or obj.type)
        -- 编辑器坐标: 左上角(0,0), Y向下; Box2D坐标: Y向上
        -- 转换: boxX = obj.x + obj.w/2, boxY = worldH - obj.y - obj.h/2
        local bx = obj.x + obj.w / 2
        local by = levelEditor_.worldH - obj.y - obj.h / 2
        node:SetPosition2D(bx, by)

        local body = node:CreateComponent("RigidBody2D")
        body.bodyType = BT_STATIC

        -- 执行器和非触发器类型有物理碰撞
        if obj.type ~= "trigger" then
            local shape = node:CreateComponent("CollisionBox2D")
            shape:SetSize(obj.w, obj.h)
            shape.friction = 0.3
            shape.restitution = 0.0
            shape.categoryBits = 1
        end

        table.insert(previewNodes, node)
    end

    -- 创建玩家角色
    local playerNode = scene:CreateChild("PreviewPlayer")
    -- 找到最高的地面/平台表面，把玩家放在其上方
    local spawnX = levelEditor_.worldW / 2
    local spawnY = levelEditor_.worldH * 0.8
    local bestTopY = -999
    for _, obj in ipairs(objects) do
        if obj.type == "ground" or obj.type == "platform" then
            -- obj.y 是编辑器坐标(Y-down)，转换到Box2D(Y-up): topSurface = worldH - obj.y
            local topSurface = levelEditor_.worldH - obj.y
            if topSurface > bestTopY then
                bestTopY = topSurface
                spawnX = obj.x + obj.w / 2
                spawnY = topSurface + 1.0
            end
        end
    end
    playerNode:SetPosition2D(spawnX, spawnY)
    print(string.format("[PREVIEW] 玩家出生: (%.1f, %.1f)", spawnX, spawnY))

    local playerBody = playerNode:CreateComponent("RigidBody2D")
    playerBody.bodyType = BT_DYNAMIC
    playerBody.fixedRotation = true
    playerBody.linearDamping = 0.0
    playerBody.gravityScale = 1.0

    -- 身体碰撞体（宽0.8 = 原半径*2，高1.6 = 原高度*2）
    local bodyShape = playerNode:CreateComponent("CollisionBox2D")
    bodyShape:SetSize(0.8, 1.6)
    bodyShape:SetCenter(0, 0.4)  -- 中心上移，底部对齐脚底
    bodyShape.density = 1.0
    bodyShape.friction = 0.0
    bodyShape.restitution = 0.0
    bodyShape.categoryBits = 2
    bodyShape.maskBits = 0xFFFF

    -- 脚底传感器
    local footSensor = playerNode:CreateComponent("CollisionCircle2D")
    footSensor.radius = 0.28
    footSensor.center = Vector2(0, -0.36)
    footSensor.trigger = true
    footSensor.categoryBits = 4
    footSensor.maskBits = 1

    -- 保存预览状态
    levelEditor_.previewActive = true
    levelEditor_.previewScene = scene
    levelEditor_.previewPlayerNode = playerNode
    levelEditor_.previewPlayerBody = playerBody
    levelEditor_.previewBodyShape = bodyShape
    levelEditor_.previewCameraNode = cameraNode
    levelEditor_.previewFootSensor = footSensor
    levelEditor_.previewOnGround = false
    levelEditor_.previewGroundContacts = 0
    levelEditor_.previewNodes = previewNodes
    levelEditor_.previewTriggerPopups = {}
    levelEditor_.previewTriggeredSet = {}
    levelEditor_.previewInteractIdx = nil

    -- 将攻击模式的触发器注册为 Targetable 可索敌目标
    local Targetable = require("Targetable")
    local attackTriggers = {}
    for i, obj in ipairs(objects) do
        if obj.type == "trigger" and obj.triggerMethod == "attack" then
            local trigCX = obj.x + obj.w / 2
            local trigCY = levelEditor_.worldH - obj.y - obj.h / 2
            table.insert(attackTriggers, {
                x = trigCX, y = trigCY,
                w = obj.w, h = obj.h,
                alive = true,
                objIdx = i,
            })
        end
    end
    levelEditor_.previewAttackTriggers = attackTriggers
    if #attackTriggers > 0 then
        Targetable.Register("previewTrigger", {
            GetAll = function() return levelEditor_.previewAttackTriggers end,
            TakeDamage = function(target, damage)
                -- 攻击命中触发器 → 标记为已触发
                if target.alive and not levelEditor_.previewTriggeredSet[target.objIdx] then
                    target.alive = false
                    levelEditor_.previewTriggeredSet[target.objIdx] = true
                    -- 浮动文字
                    table.insert(levelEditor_.previewTriggerPopups, {
                        text = "已触发", x = target.x, y = target.y + target.h / 2 + 0.5, timer = 0, maxTime = 1.5,
                    })
                    -- 联动执行器
                    local trigObj = objects[target.objIdx]
                    if trigObj and trigObj.mappings then
                        for _, exIdx in ipairs(trigObj.mappings) do
                            local exObj = objects[exIdx]
                            if exObj and exObj.type == "executor" then
                                local exEf = exObj.executorEffect or "none"
                                if exEf ~= "none" then
                                    local exCX = exObj.x + exObj.w / 2
                                    local exCY = levelEditor_.worldH - exObj.y - exObj.h / 2
                                    table.insert(levelEditor_.previewTriggerPopups, {
                                        text = "执行成功", x = exCX, y = exCY + exObj.h / 2 + 0.5, timer = 0, maxTime = 2.0,
                                    })
                                end
                            end
                        end
                    end
                end
            end,
            hitboxW = 0.8,
            hitboxH = 1.0,
            heightRange = 2.0,
        })
        print("[PREVIEW] 注册 " .. #attackTriggers .. " 个攻击模式触发器为可索敌目标")
    end

    -- 物理事件通过 main.lua 的全局 handler 路由到 M.HandlePreviewContact

    -- 创建预览UI（右上角按钮）
    levelEditor_.previewUIRoot = UI.Panel {
        position = "absolute", top = 0, left = 0,
        width = "100%", height = "100%",
        pointerEvents = "box-none",
        children = {
            -- 右上角退出按钮
            UI.Panel {
                position = "absolute", top = 10, right = 10,
                flexDirection = "row", gap = 8,
                children = {
                    UI.Button {
                        text = "退出预览", fontSize = 13,
                        paddingLeft = 12, paddingRight = 12, paddingTop = 6, paddingBottom = 6,
                        backgroundColor = {160, 50, 50, 220}, borderRadius = 6,
                        fontColor = {255,255,255,255},
                        onClick = function() M.StopPreview() end,
                    },
                },
            },
            -- 底部操作提示
            UI.Panel {
                position = "absolute", bottom = 10, left = 0, width = "100%",
                justifyContent = "center", alignItems = "center",
                pointerEvents = "none",
                children = {
                    UI.Label {
                        text = "A/D移动 | 空格跳跃 | J攻击 | L/右键格挡 | Q蓄力 | E治愈 | S蹲下 | F交互 | 1/2切换角色 | ESC退出",
                        fontSize = 11, fontColor = {200, 200, 220, 180},
                    },
                },
            },
        },
    }

    -- 预览期间切换UI根为轻量预览面板（主菜单UI层会覆盖NanoVG渲染）
    UI.SetRoot(levelEditor_.previewUIRoot)

    print("[PREVIEW] 预览启动 - " .. #objects .. " 个物件")
end

--- 停止预览模式
function M.StopPreview()
    if not levelEditor_.previewActive then return end

    -- 把编辑器UI从预览根摘出（避免被Destroy一并销毁）
    if levelEditor_.uiRoot and levelEditor_.previewUIRoot then
        levelEditor_.previewUIRoot:RemoveChild(levelEditor_.uiRoot)
    end

    -- 恢复主菜单UI根（预览时被替换了）
    if S.mainMenuUIRoot then
        UI.SetRoot(S.mainMenuUIRoot)
    end

    -- 销毁预览UI
    if levelEditor_.previewUIRoot then
        levelEditor_.previewUIRoot:Destroy()
        levelEditor_.previewUIRoot = nil
    end

    -- 销毁预览场景
    if levelEditor_.previewScene then
        levelEditor_.previewScene:Remove()
        levelEditor_.previewScene = nil
    end

    -- 恢复主场景视口
    if S.scene and S.cameraNode then
        local cam = S.cameraNode:GetComponent("Camera")
        if cam then
            renderer:SetViewport(0, Viewport:new(S.scene, cam))
        end
    end

    -- 注销预览触发器的 Targetable 注册
    local Targetable = require("Targetable")
    Targetable.Unregister("previewTrigger")
    levelEditor_.previewAttackTriggers = nil

    -- 标记"刚退出预览"，防止同帧ESC连锁退出编辑器
    levelEditor_.justStoppedPreview = true

    -- 清除预览状态
    levelEditor_.previewActive = false
    levelEditor_.previewPlayerNode = nil
    levelEditor_.previewPlayerBody = nil
    levelEditor_.previewCameraNode = nil
    levelEditor_.previewFootSensor = nil
    levelEditor_.previewOnGround = false
    levelEditor_.previewGroundContacts = 0
    levelEditor_.previewNodes = {}

    -- 重置所有动作状态（避免预览中的状态残留到主游戏）
    S.isAttacking = false
    S.isBlocking = false
    S.isCharging = false
    S.chargeReleased = false
    S.isHealing = false
    S.isCrouching = false
    S.crouchPhase = "loop"
    S.isDashing = false
    S.isHanging = false
    S.hangCooldown = 0
    S.wingShatterTimer = 0
    S.currentAnim = C.ANIM_IDLE
    S.animFrame = 0
    S.animTimer = 0.0

    -- 恢复关卡选择UI可见性
    if levelSelect_.uiRoot then
        levelSelect_.uiRoot:SetVisible(true)
    end

    -- 显示编辑器UI并挂回正确父节点
    if levelEditor_.uiRoot then
        levelEditor_.uiRoot:SetVisible(true)
        -- 编辑器UI可能还挂在已销毁的previewUIRoot上，重新挂载
        if levelSelect_.uiRoot then
            levelSelect_.uiRoot:AddChild(levelEditor_.uiRoot)
        elseif S.mainMenuUIRoot then
            S.mainMenuUIRoot:AddChild(levelEditor_.uiRoot)
        end
    else
        M.BuildLevelEditorUI()
    end

    print("[PREVIEW] 预览结束")
end

--- 预览中打开/关闭编辑器
-- ToggleEditorInPreview 已移除（预览模式不再提供编辑器入口，防止多次叠加）

--- 预览模式中刷新地形（编辑器修改后重新生成）
function M.RefreshPreviewTerrain()
    if not levelEditor_.previewActive then return end

    local scene = levelEditor_.previewScene
    if not scene then return end

    -- 销毁旧地形节点
    for _, node in ipairs(levelEditor_.previewNodes) do
        if node then node:Remove() end
    end
    levelEditor_.previewNodes = {}

    -- 重新生成地形
    local ch = levelEditor_.chapterIdx
    local lv = levelEditor_.levelIdx
    local key = ch .. "_" .. lv
    local objects = levelEditor_.objects[key] or {}

    for _, obj in ipairs(objects) do
        local node = scene:CreateChild(obj.name or obj.type)
        local bx = obj.x + obj.w / 2
        local by = levelEditor_.worldH - obj.y - obj.h / 2
        node:SetPosition2D(bx, by)

        local body = node:CreateComponent("RigidBody2D")
        body.bodyType = BT_STATIC

        if obj.type ~= "trigger" then
            local shape = node:CreateComponent("CollisionBox2D")
            shape:SetSize(obj.w, obj.h)
            shape.friction = 0.3
            shape.restitution = 0.0
            shape.categoryBits = 1
        end

        table.insert(levelEditor_.previewNodes, node)
    end
    print("[PREVIEW] 地形已刷新")
end

--- 预览模式每帧更新（角色移动和相机）
function M.UpdatePreview(dt)
    if not levelEditor_.previewActive then return end

    local playerBody = levelEditor_.previewPlayerBody
    local playerNode = levelEditor_.previewPlayerNode
    local cameraNode = levelEditor_.previewCameraNode
    if not playerBody or not playerNode or not cameraNode then return end

    -- 让 Combat 系统使用预览玩家节点（主循环被 showMainMenu 跳过）
    S.playerNode = playerNode

    -- ESC退出预览
    if input:GetKeyPress(KEY_ESCAPE) then
        M.StopPreview()
        return
    end

    -- 数字键1/2切换角色
    if input:GetKeyPress(KEY_1) then
        S.currentCharacter = 1
        S.currentAnim = C.ANIM_IDLE
        S.animFrame = 0
        S.animTimer = 0.0
    elseif input:GetKeyPress(KEY_2) then
        S.currentCharacter = 2
        S.currentAnim = C.ANIM_IDLE
        S.animFrame = 0
        S.animTimer = 0.0
    end

    -- 角色移动输入
    local moveX = 0
    local speed = 6.0
    local jumpSpeed = 13.0

    if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then
        moveX = -speed
    elseif input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then
        moveX = speed
    end

    -- 施法/格挡期间移动减半
    if S.isAttacking or S.isBlocking then
        moveX = moveX * 0.5
    end
    -- 蓄力/治愈期间禁止移动
    if S.isCharging or S.chargeReleased or S.isHealing then
        moveX = 0
    end
    -- 蹲下减速
    if S.isCrouching then
        moveX = moveX * (C.CROUCH_SPEED / C.PLAYER_SPEED)
    end

    -- 设置水平速度（突进时由突进逻辑接管）
    local vel = playerBody:GetLinearVelocity()
    if not S.isDashing then
        playerBody:SetLinearVelocity(Vector2(moveX, vel.y))
    end

    -- 跳跃
    local jumpPressed = input:GetKeyPress(KEY_SPACE) or input:GetKeyPress(KEY_W) or input:GetKeyPress(KEY_UP) or input:GetKeyPress(KEY_K)
    local jumpHeld = input:GetKeyDown(KEY_SPACE) or input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP) or input:GetKeyDown(KEY_K)
    if levelEditor_.previewOnGround and jumpPressed and not S.isCharging and not S.chargeReleased and math.abs(vel.y) < 2.0 then
        playerBody:SetLinearVelocity(Vector2(moveX, jumpSpeed))
        levelEditor_.previewOnGround = false
        levelEditor_.previewGroundContacts = 0
        S.isHanging = false
        playerBody.gravityScale = 1.0
    elseif not levelEditor_.previewOnGround and jumpHeld and not S.isHanging and S.hangCooldown <= 0 and playerBody:GetLinearVelocity().y < 0 then
        -- 空中下落期间长按跳跃键：进入滞空
        S.isHanging = true
        S.hangCooldown = C.HANG_COOLDOWN_TIME
        playerBody.gravityScale = C.HANG_GRAVITY_SCALE
        local curVel = playerBody:GetLinearVelocity()
        playerBody:SetLinearVelocity(Vector2(curVel.x, curVel.y * 0.3))
    end

    -- 滞空状态：松开跳跃键结束
    if S.isHanging then
        if not jumpHeld then
            S.isHanging = false
            playerBody.gravityScale = 1.0
            S.wingShatterTimer = C.WING_SHATTER_DURATION
        end
    end
    -- 滞空冷却
    if S.hangCooldown > 0 then
        S.hangCooldown = S.hangCooldown - dt
    end
    -- 落地时恢复重力
    if levelEditor_.previewOnGround and S.isHanging then
        S.isHanging = false
        playerBody.gravityScale = 1.0
    end

    -- 攻击（J键 / 鼠标左键）- 通过 Combat.CastSpell 触发投射物/近战
    local attackPressed = input:GetKeyPress(KEY_J) or input:GetMouseButtonPress(MOUSEB_LEFT)
    if attackPressed and not S.isBlocking and not S.isCharging and not S.chargeReleased and not S.isAttacking then
        Combat.CastSpell()
    end
    -- 攻击计时（12帧动画，完毕后恢复）
    if S.isAttacking then
        S.attackTimer = S.attackTimer + dt
        if S.attackTimer >= C.SPRITE_FRAMES / C.ANIM_FPS_ATTACK then
            S.isAttacking = false
        end
    end

    -- 格挡（鼠标右键 / L键 长按）
    local blockHeld = input:GetMouseButtonDown(MOUSEB_RIGHT) or input:GetKeyDown(KEY_L)
    if blockHeld and not S.isBlocking and not S.isAttacking and not S.isCharging then
        S.isBlocking = true
        S.currentAnim = C.ANIM_BLOCK
        S.animFrame = 0
        S.animTimer = 0.0
    elseif S.isBlocking and not blockHeld then
        S.isBlocking = false
    end

    -- 蓄力（Q键长按）
    local chargeHeld = input:GetKeyDown(KEY_Q)
    local chargeStart = input:GetKeyPress(KEY_Q)
    if chargeStart and not S.isCharging and not S.chargeReleased and not S.isAttacking and not S.isBlocking and not S.isDashing then
        S.isCharging = true
        S.chargeTimer = 0.0
        S.currentAnim = C.ANIM_CHARGE
        S.animFrame = 0
        S.animTimer = 0.0
    elseif S.isCharging then
        S.chargeTimer = S.chargeTimer + dt
        if not chargeHeld or S.chargeTimer >= C.CHARGE_MAX_DURATION then
            S.isCharging = false
            S.chargeReleased = true
            S.animFrame = 9
            S.animTimer = 0.0
            if S.currentCharacter == 2 then
                -- 角色2: 蝴蝶突进位移
                local power = math.min(S.chargeTimer / C.CHARGE_MAX_DURATION, 1.0)
                S.isDashing = true
                S.dashTimer = 0.0
                S.dashDir = S.facingRight and 1 or -1
                S.dashStartX = playerNode.position2D.x
                S.dashTargetDist = C.CHAR2_DASH_MIN_DIST + (C.CHAR2_DASH_MAX_DIST - C.CHAR2_DASH_MIN_DIST) * power
                S.dashHitEnemies = {}
            else
                -- 角色1: 蓄力释放生成冰晶群（索敌）
                Combat.SpawnIceCrystals(S.chargeTimer)
            end
        end
    end
    -- 突进位移处理 + Targetable 命中检测
    if S.isDashing then
        S.dashTimer = S.dashTimer + dt
        playerBody:SetLinearVelocity(Vector2(S.dashDir * C.CHAR2_DASH_SPEED, 0))
        -- 突进命中检测（通过 Targetable 接口）
        local Targetable = require("Targetable")
        local pos = playerNode.position2D
        Targetable.CheckDashHits(pos.x, pos.y, S.dashDir, C.CHAR2_DASH_DAMAGE, S.dashHitEnemies, C.CHAR2_BLEED_DURATION, C.CHAR2_BLEED_DPS)
        local traveled = math.abs(pos.x - S.dashStartX)
        if traveled >= S.dashTargetDist or S.dashTimer > 1.0 then
            S.isDashing = false
            playerBody:SetLinearVelocity(Vector2(0, playerBody:GetLinearVelocity().y))
        end
    end
    -- 蓄力释放动画播完后恢复
    if S.chargeReleased and S.currentAnim == C.ANIM_CHARGE and S.animFrame >= 11 then
        S.chargeReleased = false
        if S.isDashing then S.isDashing = false end
    end

    -- 治愈（E键）
    if S.healCooldownTimer > 0 then
        S.healCooldownTimer = S.healCooldownTimer - dt
    end
    local healPressed = input:GetKeyPress(KEY_E)
    if healPressed and not S.isHealing and not S.isCharging and not S.chargeReleased and not S.isAttacking and not S.isBlocking and S.healCooldownTimer <= 0 then
        S.isHealing = true
        S.healTimer = 0.0
        S.currentAnim = C.ANIM_HEAL
        S.animFrame = 0
        S.animTimer = 0.0
    end
    if S.isHealing then
        S.healTimer = S.healTimer + dt
        if S.healTimer >= C.HEAL_DURATION then
            S.isHealing = false
            S.healCooldownTimer = C.HEAL_COOLDOWN
        end
    end

    -- 蹲下（S键 / 下方向键 长按）
    local crouchHeld = input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_DOWN)
    local wasCrouching = S.isCrouching
    if crouchHeld and levelEditor_.previewOnGround and not S.isCharging and not S.chargeReleased and not S.isHealing and not S.isAttacking then
        if not wasCrouching then
            S.isCrouching = true
            S.crouchPhase = "enter"
            S.animFrame = 1
            S.animTimer = 0.0
            levelEditor_.previewForcedCrouch = false
            -- 蹲下时碰撞箱缩为 0.8×1.2, center=(0,0.2) 保持底部对齐
            local shape = levelEditor_.previewBodyShape
            if shape then
                shape:SetSize(0.8, 1.2)
                shape:SetCenter(0, 0.2)
            end
        end
    else
        if wasCrouching then
            -- 检测头顶空间是否足够站立
            -- 蹲下顶部 y=+0.8, 站立顶部 y=+1.2, 需要检测 0.4 米头顶空间
            local pos = playerNode.position2D
            local canStand = true
            local physWorld = levelEditor_.previewScene:GetComponent("PhysicsWorld2D")
            if physWorld then
                -- 从蹲下顶部向上射线检测（左中右三条）
                for _, offX in ipairs({-0.35, 0, 0.35}) do
                    local startPt = Vector2(pos.x + offX, pos.y + 0.8)
                    local endPt = Vector2(pos.x + offX, pos.y + 1.25)
                    local result = physWorld:RaycastSingle(startPt, endPt, 1)
                    if result and result.body then
                        canStand = false
                        break
                    end
                end
            end

            if canStand then
                S.isCrouching = false
                S.crouchPhase = "loop"
                S.animFrame = 0
                S.animTimer = 0.0
                levelEditor_.previewForcedCrouch = false
                -- 站立时恢复碰撞箱 0.8×1.6
                local shape = levelEditor_.previewBodyShape
                if shape then
                    shape:SetSize(0.8, 1.6)
                    shape:SetCenter(0, 0.4)
                end
            else
                -- 头顶空间不足，强制保持蹲下
                levelEditor_.previewForcedCrouch = true
            end
        end
    end

    -- 强制蹲下状态：每帧检测是否可以站起
    if levelEditor_.previewForcedCrouch and S.isCrouching and not crouchHeld then
        local pos = playerNode.position2D
        local canStand = true
        local physWorld = levelEditor_.previewScene:GetComponent("PhysicsWorld2D")
        if physWorld then
            for _, offX in ipairs({-0.35, 0, 0.35}) do
                local startPt = Vector2(pos.x + offX, pos.y + 0.8)
                local endPt = Vector2(pos.x + offX, pos.y + 1.25)
                local result = physWorld:RaycastSingle(startPt, endPt, 1)
                if result and result.body then
                    canStand = false
                    break
                end
            end
        end
        if canStand then
            S.isCrouching = false
            S.crouchPhase = "loop"
            S.animFrame = 0
            S.animTimer = 0.0
            levelEditor_.previewForcedCrouch = false
            local shape = levelEditor_.previewBodyShape
            if shape then
                shape:SetSize(0.8, 1.6)
                shape:SetCenter(0, 0.4)
            end
        end
    end

    -- 更新朝向
    if moveX > 0 then S.facingRight = true
    elseif moveX < 0 then S.facingRight = false end

    -- 同步地面状态到全局（动画状态机需要）
    S.onGround = levelEditor_.previewOnGround

    -- 驱动动画状态机
    Animation.Update(dt, moveX)

    -- ====== 预览模式 Combat 系统更新（主循环被跳过） ======
    Combat.ProcessPendingProjectile(dt)
    Combat.ProcessPendingMelee(dt)
    Combat.UpdateProjectiles(dt)
    Combat.UpdateIceCrystals(dt)
    Combat.CheckProjectileHits()

    -- ====== 触发器/执行器检测（仅预览） ======
    local pPos = playerNode.position2D
    local ch = levelEditor_.chapterIdx
    local lv = levelEditor_.levelIdx
    local tKey = ch .. "_" .. lv
    local objects = levelEditor_.objects[tKey] or {}
    local worldH = levelEditor_.worldH

    -- 浮动文字计时器更新
    local popups = levelEditor_.previewTriggerPopups
    for pi = #popups, 1, -1 do
        popups[pi].timer = popups[pi].timer + dt
        if popups[pi].timer >= popups[pi].maxTime then
            table.remove(popups, pi)
        end
    end

    -- 玩家AABB（身体碰撞体：0.8×1.6, center=(0,0.4)）
    local pHalfW = 0.4
    local pHalfH = 0.8
    local pCenterX = pPos.x
    local pCenterY = pPos.y + 0.4
    if S.isCrouching then
        pHalfH = 0.6
        pCenterY = pPos.y + 0.2
    end

    -- 触发并执行策略的本地辅助函数
    local function fireTrigger(trigIdx, obj, trigCX, trigCY, trigHH)
        levelEditor_.previewTriggeredSet[trigIdx] = true
        table.insert(popups, { text = "已触发", x = trigCX, y = trigCY + trigHH + 0.5, timer = 0, maxTime = 1.5 })

        -- 执行触发器策略 + 关联执行器
        local stratCtx = { playerX = pCenterX, playerY = pCenterY }
        local trigStratText = M._executeStrategy(obj, nil, stratCtx)
        if trigStratText then
            table.insert(popups, { text = trigStratText, x = trigCX, y = trigCY + trigHH + 1.2, timer = 0, maxTime = 2.5 })
        end

        if obj.mappings then
            for _, exIdx in ipairs(obj.mappings) do
                local exObj = objects[exIdx]
                if exObj and exObj.type == "executor" then
                    local exEf = exObj.executorEffect or "none"
                    local exCX = exObj.x + exObj.w / 2
                    local exCY = worldH - exObj.y - exObj.h / 2
                    -- 执行器策略
                    local exStratText = M._executeStrategy(obj, exObj, stratCtx)
                    if exStratText then
                        table.insert(popups, { text = exStratText, x = exCX, y = exCY + exObj.h / 2 + 1.2, timer = 0, maxTime = 2.5 })
                    end
                    if exEf ~= "none" or (exObj.executorStrategy and exObj.executorStrategy.rootId) then
                        table.insert(popups, { text = "执行成功", x = exCX, y = exCY + exObj.h / 2 + 0.5, timer = 0, maxTime = 2.0 })
                    end
                end
            end
        end
    end

    -- 检测角色与触发器的重叠
    levelEditor_.previewInteractIdx = nil
    for i, obj in ipairs(objects) do
        if obj.type == "trigger" then
            local tm = obj.triggerMethod or "none"
            if tm ~= "none" then
                -- 触发器世界坐标中心（Box2D Y-up）
                local trigCX = obj.x + obj.w / 2
                local trigCY = worldH - obj.y - obj.h / 2
                local trigHW = obj.w / 2
                local trigHH = obj.h / 2

                -- AABB 重叠检测
                local overlapX = (math.abs(pCenterX - trigCX) < (pHalfW + trigHW))
                local overlapY = (math.abs(pCenterY - trigCY) < (pHalfH + trigHH))
                local isOverlapping = overlapX and overlapY

                if isOverlapping then
                    if tm == "touch" then
                        if not levelEditor_.previewTriggeredSet[i] then
                            fireTrigger(i, obj, trigCX, trigCY, trigHH)
                        end
                    elseif tm == "interact" then
                        levelEditor_.previewInteractIdx = i
                        if input:GetKeyPress(KEY_F) and not levelEditor_.previewTriggeredSet[i] then
                            fireTrigger(i, obj, trigCX, trigCY, trigHH)
                        end
                    elseif tm == "attack" then
                        if S.isAttacking and not levelEditor_.previewTriggeredSet[i] then
                            fireTrigger(i, obj, trigCX, trigCY, trigHH)
                        end
                    elseif tm == "other" then
                        if not levelEditor_.previewTriggeredSet[i] then
                            fireTrigger(i, obj, trigCX, trigCY, trigHH)
                        end
                    end
                end
            end
        end
    end

    -- 相机跟随玩家
    local camPos = cameraNode.position
    local targetX = pPos.x
    local targetY = pPos.y
    -- 平滑跟随
    local lerpSpeed = 5.0
    local newX = camPos.x + (targetX - camPos.x) * math.min(1.0, lerpSpeed * dt)
    local newY = camPos.y + (targetY - camPos.y) * math.min(1.0, lerpSpeed * dt)

    -- 镜头范围框边界约束：相机边缘不超出范围框
    if levelEditor_.cameraBoundsEnabled and levelEditor_.cameraBounds then
        local cb = levelEditor_.cameraBounds
        local camera = cameraNode:GetComponent("Camera")
        if camera then
            local halfH = camera.orthoSize * 0.5
            local aspect = graphics:GetWidth() / graphics:GetHeight()
            local halfW = halfH * aspect
            -- 相机中心的合法范围
            local minCamX = cb.x + halfW
            local maxCamX = cb.x + cb.w - halfW
            local minCamY = cb.y + halfH
            local maxCamY = cb.y + cb.h - halfH
            -- 如果范围框比视野还小，居中
            if minCamX > maxCamX then
                newX = cb.x + cb.w / 2
            else
                newX = math.max(minCamX, math.min(maxCamX, newX))
            end
            if minCamY > maxCamY then
                newY = cb.y + cb.h / 2
            else
                newY = math.max(minCamY, math.min(maxCamY, newY))
            end
        end
    end

    cameraNode.position = Vector3(newX, newY, -10)

    -- 玩家掉出世界边界重置位置
    if pPos.y < -5 then
        playerNode:SetPosition2D(levelEditor_.worldW / 2, levelEditor_.worldH * 0.8)
        playerBody:SetLinearVelocity(Vector2(0, 0))
    end
end

--- 预览是否激活
function M.IsPreviewActive()
    return levelEditor_.previewActive
end

--- 预览刚退出（同帧标志，防止ESC连锁）
function M.JustStoppedPreview()
    return levelEditor_.justStoppedPreview == true
end

--- 预览物理碰撞处理（从main.lua的全局handler调用）
function M.HandlePreviewBeginContact(eventType, eventData)
    if not levelEditor_.previewActive then return end
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local nodeB = eventData["NodeB"]:GetPtr("Node")
    local playerNode = levelEditor_.previewPlayerNode
    if not playerNode then return end
    -- 检测脚底传感器碰撞
    if nodeA == playerNode or nodeB == playerNode then
        -- 检查是否是脚底传感器触发
        local shapeA = eventData["ShapeA"]:GetPtr("CollisionShape2D")
        local shapeB = eventData["ShapeB"]:GetPtr("CollisionShape2D")
        local footSensor = levelEditor_.previewFootSensor
        if shapeA == footSensor or shapeB == footSensor then
            levelEditor_.previewGroundContacts = levelEditor_.previewGroundContacts + 1
            levelEditor_.previewOnGround = true
        end
    end
end

function M.HandlePreviewEndContact(eventType, eventData)
    if not levelEditor_.previewActive then return end
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local nodeB = eventData["NodeB"]:GetPtr("Node")
    local playerNode = levelEditor_.previewPlayerNode
    if not playerNode then return end
    if nodeA == playerNode or nodeB == playerNode then
        local shapeA = eventData["ShapeA"]:GetPtr("CollisionShape2D")
        local shapeB = eventData["ShapeB"]:GetPtr("CollisionShape2D")
        local footSensor = levelEditor_.previewFootSensor
        if shapeA == footSensor or shapeB == footSensor then
            levelEditor_.previewGroundContacts = math.max(0, levelEditor_.previewGroundContacts - 1)
            levelEditor_.previewOnGround = (levelEditor_.previewGroundContacts > 0)
        end
    end
end

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

--- 编辑器画布贴图渲染（NanoVG，在编辑器模式下显示贴图）
function M.DrawEditorCanvasTextures(vg, physW, physH)
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
            local px, py, pw, ph = M.WorldToCanvas(lx, canvasTopY, lw, lh)
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
        local px, py, pw, ph = M.WorldToCanvas(obj.x, obj.y, obj.w, obj.h)
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
            local spx, spy, spw, sph = M.WorldToCanvas(selObj.x, selObj.y, selObj.w, selObj.h)
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
        local cbPx, cbPy, cbPw, cbPh = M.WorldToCanvas(cb.x, cbTopY, cb.w, cb.h)
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
        local vpx, vpy, vpw, vph = M.WorldToCanvas(viewLeft, viewTopY, viewW, viewH)
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

--- 预览NanoVG渲染（绘制地形和玩家可视化）
function M.DrawPreview(vg, physW, physH)
    if not levelEditor_.previewActive then return end
    local cameraNode = levelEditor_.previewCameraNode
    local playerNode = levelEditor_.previewPlayerNode
    if not cameraNode or not playerNode then return end

    local camera = cameraNode:GetComponent("Camera")
    if not camera then return end

    local camPos = cameraNode.position
    local camX, camY = camPos.x, camPos.y
    -- orthoSize 是全高度，半高度 = orthoSize * 0.5
    local halfH = camera.orthoSize * 0.5
    local aspect = physW / physH
    local halfW = halfH * aspect

    -- 世界坐标转屏幕坐标
    local function worldToScreen(wx, wy)
        local sx = (wx - camX + halfW) / (halfW * 2) * physW
        local sy = (1.0 - (wy - camY + halfH) / (halfH * 2)) * physH
        return sx, sy
    end

    -- 单位转像素比（每米对应多少像素）
    local ppu = physW / (halfW * 2)

    -- 绘制背景
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, physW, physH)
    nvgFillColor(vg, nvgRGBA(20, 25, 40, 255))
    nvgFill(vg)

    -- 绘制背景图层（使用世界坐标，支持景深视差）
    -- 渲染顺序：列表上方（索引小）的层在视觉上层 → 逆序渲染
    local bgLayers = levelEditor_.bgLayers or {}
    for li = #bgLayers, 1, -1 do
        local layer = bgLayers[li]
        if layer.visible ~= false then
            local bgImg = GetNvgTexture(vg, layer.path)
            if bgImg then
                local opacity = layer.opacity or 1.0
                local depth = layer.depth or 0
                local lx = layer.x or 0
                local ly = layer.y or 0
                local lw = layer.w or 10
                local lh = layer.h or 6
                -- 景深视差：depth越大，随相机移动越慢
                local parallax = 1.0 / (1.0 + depth)
                local offsetX = camX * (1.0 - parallax)
                local offsetY = camY * (1.0 - parallax)
                -- 世界坐标转屏幕
                local sx1, sy1 = worldToScreen(lx - offsetX, ly - offsetY + lh)
                local sx2, sy2 = worldToScreen(lx - offsetX + lw, ly - offsetY)
                local drawW = sx2 - sx1
                local drawH = sy2 - sy1
                local paint = nvgImagePattern(vg, sx1, sy1, drawW, drawH, 0, bgImg, opacity)
                nvgBeginPath(vg)
                nvgRect(vg, sx1, sy1, drawW, drawH)
                nvgFillPaint(vg, paint)
                nvgFill(vg)
            end
        end
    end

    -- 绘制地形物件
    local ch = levelEditor_.chapterIdx
    local lv = levelEditor_.levelIdx
    local key = ch .. "_" .. lv
    local objects = levelEditor_.objects[key] or {}

    for _, obj in ipairs(objects) do
        local bx = obj.x + obj.w / 2
        local by = levelEditor_.worldH - obj.y - obj.h / 2
        local sx, sy = worldToScreen(bx, by)
        local pw = obj.w * ppu
        local ph = obj.h * ppu

        -- 判断是否有可见贴图
        local hasVisibleTex = false
        if obj.texLayers and #obj.texLayers > 0 then
            for _, tl in ipairs(obj.texLayers) do
                if tl.visible ~= false and tl.path and tl.path ~= "" then
                    hasVisibleTex = true; break
                end
            end
        elseif obj.texture and obj.texture ~= "" then
            hasVisibleTex = true
        end

        -- 有贴图时不绘制占位色块（透明），无贴图时照常绘制
        if not hasVisibleTex then
            nvgBeginPath(vg)
            nvgRect(vg, sx - pw/2, sy - ph/2, pw, ph)
            if obj.type == "ground" then
                nvgFillColor(vg, nvgRGBA(80, 60, 40, 255))
            elseif obj.type == "platform" then
                nvgFillColor(vg, nvgRGBA(60, 90, 60, 255))
            elseif obj.type == "obstacle" then
                nvgFillColor(vg, nvgRGBA(140, 50, 50, 255))
            elseif obj.type == "trigger" then
                nvgFillColor(vg, nvgRGBA(60, 60, 140, 100))
            elseif obj.type == "executor" then
                nvgFillColor(vg, nvgRGBA(140, 100, 40, 200))
            else
                nvgFillColor(vg, nvgRGBA(100, 100, 100, 255))
            end
            nvgFill(vg)
        end

        -- 物件贴图（多图层，使用物件颜色染色）
        -- 渲染顺序：列表上方（索引小）的层在视觉上层 → 逆序渲染
        local prevObjCol = obj.color or {255, 255, 255, 255}
        local texLayers = obj.texLayers
        if texLayers and #texLayers > 0 then
            for tli = #texLayers, 1, -1 do
                local tLayer = texLayers[tli]
                if tLayer.visible ~= false then
                    local texImg = GetNvgTexture(vg, tLayer.path)
                    if texImg then
                        local tScW = tLayer.scaleW or 1.0
                        local tScH = tLayer.scaleH or 1.0
                        local drawW = pw * tScW
                        local drawH = ph * tScH
                        local alpha = tLayer.opacity or 1.0
                        local tintColor = nvgRGBA(prevObjCol[1], prevObjCol[2], prevObjCol[3], math.floor((prevObjCol[4] or 255) * alpha))
                        local tPaint = nvgImagePatternTinted(vg, sx - drawW/2, sy - drawH/2, drawW, drawH, 0, texImg, tintColor)
                        nvgBeginPath(vg)
                        nvgRect(vg, sx - drawW/2, sy - drawH/2, drawW, drawH)
                        nvgFillPaint(vg, tPaint)
                        nvgFill(vg)
                    end
                end
            end
        elseif obj.texture then
            local texImg = GetNvgTexture(vg, obj.texture)
            if texImg then
                local tScW = obj.texScaleW or 1.0
                local tScH = obj.texScaleH or 1.0
                local drawW = pw * tScW
                local drawH = ph * tScH
                local tintColor = nvgRGBA(prevObjCol[1], prevObjCol[2], prevObjCol[3], prevObjCol[4] or 255)
                local tPaint = nvgImagePatternTinted(vg, sx - drawW/2, sy - drawH/2, drawW, drawH, 0, texImg, tintColor)
                nvgBeginPath(vg)
                nvgRect(vg, sx - drawW/2, sy - drawH/2, drawW, drawH)
                nvgFillPaint(vg, tPaint)
                nvgFill(vg)
            end
        end

        -- 边框（仅无贴图时显示）
        if not hasVisibleTex then
            nvgStrokeColor(vg, nvgRGBA(200, 200, 200, 80))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end
    end

    -- 绘制玩家角色（完整序列帧 + 特效）
    local pPos = playerNode.position2D
    local px, py = worldToScreen(pPos.x, pPos.y)
    local playerR = 0.4 * ppu

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

    -- 动画帧与裁切配置
    local animCropConfig = S.GetCurrentAnimCropConfig()
    local animScale = (animCropConfig[S.currentAnim] and animCropConfig[S.currentAnim].scale) or 5.5
    local playerDrawSize = C.PLAYER_RADIUS * animScale * ppu

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

    -- 绘制精灵帧
    if img ~= nil and img > 0 and S.imgWidth > 0 then
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

        local drawW = playerDrawSize
        local drawH = playerDrawSize * (srcH / srcW)
        local oX = crop.offsetX or 0.0
        local oY = crop.offsetY or 0.6
        local drawX = px - drawW / 2 + oX * drawW
        local drawY = py - drawH * oY

        nvgSave(vg)
        local flipH = not S.facingRight
        if flipH then
            nvgTranslate(vg, px, 0)
            nvgScale(vg, -1, 1)
            nvgTranslate(vg, -px, 0)
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
    else
        -- fallback: 占位圆
        nvgBeginPath(vg)
        nvgCircle(vg, px, py, playerR)
        nvgFillColor(vg, nvgRGBA(100, 180, 255, 255))
        nvgFill(vg)
    end

    -- 碰撞箱可视化（绿色半透明）
    -- 身体碰撞体（蹲下0.8×0.8 center=0, 站立0.8×1.6 center=0.4）
    local boxW = 0.8 * ppu
    local boxH, boxCenterOff
    if S.isCrouching then
        boxH = 1.2 * ppu
        boxCenterOff = 0.2
    else
        boxH = 1.6 * ppu
        boxCenterOff = 0.4
    end
    local boxCenterY = py - boxCenterOff * ppu  -- 物理Y向上，屏幕Y向下取反
    nvgBeginPath(vg)
    nvgRect(vg, px - boxW/2, boxCenterY - boxH/2, boxW, boxH)
    nvgStrokeColor(vg, nvgRGBA(0, 255, 100, 180))
    nvgStrokeWidth(vg, 2)
    nvgStroke(vg)

    -- 脚底传感器（圆形 radius=0.28, center=(0, -0.36)）
    local footY = py + 0.36 * ppu  -- 屏幕Y向下，物理Y向下对应+
    nvgBeginPath(vg)
    nvgCircle(vg, px, footY, 0.28 * ppu)
    nvgStrokeColor(vg, nvgRGBA(255, 200, 0, 160))
    nvgStrokeWidth(vg, 1.5)
    nvgStroke(vg)

    -- 游戏可视范围红框（21.33m × 12m，跟随相机实际位置）
    local gameViewW = C.SCREEN_WIDTH / C.PIXELS_PER_UNIT  -- ≈21.33m
    local gameViewH = C.SCREEN_HEIGHT / C.PIXELS_PER_UNIT  -- =12m
    -- 红框使用实际相机位置（已被cameraBounds约束），始终保持在黄色范围框内
    local viewCenterX = camX
    local viewCenterY = camY
    local vLeft, vTop = worldToScreen(viewCenterX - gameViewW/2, viewCenterY + gameViewH/2)
    local vRight, vBottom = worldToScreen(viewCenterX + gameViewW/2, viewCenterY - gameViewH/2)
    local vw = vRight - vLeft
    local vh = vBottom - vTop
    nvgBeginPath(vg)
    nvgRect(vg, vLeft, vTop, vw, vh)
    nvgStrokeColor(vg, nvgRGBA(255, 50, 50, 200))
    nvgStrokeWidth(vg, 2.5)
    nvgStroke(vg)
    -- 红框角标
    local cornerLen = 12
    nvgBeginPath(vg)
    -- 左上角
    nvgMoveTo(vg, vLeft, vTop + cornerLen)
    nvgLineTo(vg, vLeft, vTop)
    nvgLineTo(vg, vLeft + cornerLen, vTop)
    -- 右上角
    nvgMoveTo(vg, vRight - cornerLen, vTop)
    nvgLineTo(vg, vRight, vTop)
    nvgLineTo(vg, vRight, vTop + cornerLen)
    -- 右下角
    nvgMoveTo(vg, vRight, vBottom - cornerLen)
    nvgLineTo(vg, vRight, vBottom)
    nvgLineTo(vg, vRight - cornerLen, vBottom)
    -- 左下角
    nvgMoveTo(vg, vLeft + cornerLen, vBottom)
    nvgLineTo(vg, vLeft, vBottom)
    nvgLineTo(vg, vLeft, vBottom - cornerLen)
    nvgStrokeColor(vg, nvgRGBA(255, 80, 80, 255))
    nvgStrokeWidth(vg, 3.5)
    nvgStroke(vg)

    -- ====== 触发器/执行器浮动文字提示 ======
    local popups = levelEditor_.previewTriggerPopups
    if popups and #popups > 0 then
        nvgFontFace(vg, "sans")
        nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
        for _, pop in ipairs(popups) do
            local sx, sy = worldToScreen(pop.x, pop.y)
            -- 淡入淡出效果
            local alpha = 255
            if pop.timer < 0.2 then
                alpha = math.floor(pop.timer / 0.2 * 255)
            elseif pop.timer > pop.maxTime - 0.4 then
                alpha = math.floor((pop.maxTime - pop.timer) / 0.4 * 255)
            end
            -- 向上飘动
            local floatY = sy - pop.timer * 20
            local isExec = (pop.text == "执行成功")
            nvgFontSize(vg, isExec and 14 or 15)
            -- 背景阴影
            nvgFillColor(vg, nvgRGBA(0, 0, 0, math.floor(alpha * 0.6)))
            nvgText(vg, sx + 1, floatY + 1, pop.text)
            -- 正文
            if isExec then
                nvgFillColor(vg, nvgRGBA(50, 230, 120, alpha))
            else
                nvgFillColor(vg, nvgRGBA(255, 220, 60, alpha))
            end
            nvgText(vg, sx, floatY, pop.text)
        end
    end

    -- 交互类型触发器：显示"按F键交互"提示
    local interIdx = levelEditor_.previewInteractIdx
    if interIdx then
        local interObj = objects[interIdx]
        if interObj and not levelEditor_.previewTriggeredSet[interIdx] then
            local trigCX = interObj.x + interObj.w / 2
            local trigCY = levelEditor_.worldH - interObj.y - interObj.h / 2
            local isx, isy = worldToScreen(trigCX, trigCY + interObj.h / 2 + 0.8)
            nvgFontFace(vg, "sans")
            nvgFontSize(vg, 14)
            nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            -- 背景矩形
            local tw = 90
            local th = 22
            nvgBeginPath(vg)
            nvgRoundedRect(vg, isx - tw/2, isy - th, tw, th, 4)
            nvgFillColor(vg, nvgRGBA(0, 0, 0, 180))
            nvgFill(vg)
            nvgStrokeColor(vg, nvgRGBA(255, 220, 80, 200))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
            -- 文字
            nvgFillColor(vg, nvgRGBA(255, 240, 100, 255))
            nvgText(vg, isx, isy - 4, "按F键交互")
        end
    end

    -- HUD: 左上角显示关卡信息
    nvgFontFace(vg, "sans")
    nvgFontSize(vg, 16)
    nvgFillColor(vg, nvgRGBA(200, 200, 220, 200))
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgText(vg, 10, 10, string.format("预览: 第%d章 第%d关", ch, lv))

    -- 着地指示
    if levelEditor_.previewOnGround then
        nvgFontSize(vg, 12)
        nvgFillColor(vg, nvgRGBA(100, 255, 100, 180))
        nvgText(vg, 10, 30, "地面")
    end

    -- 红框尺寸提示
    nvgFontSize(vg, 11)
    nvgFillColor(vg, nvgRGBA(255, 100, 100, 180))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgText(vg, (vLeft + vRight) / 2, vTop - 4, string.format("游戏视野 %.1fm×%.0fm", gameViewW, gameViewH))
end

-- ============================================================================
-- 策略树执行辅助 (预览模式)
-- ============================================================================

--- 触发器触发时执行策略树，返回弹出文字列表
--- @param trigObj table 触发器对象
--- @param executorObj table|nil 执行器对象（可选）
--- @param context table 运行时上下文 {playerX, playerY, ...}
--- @return string|nil popupText 额外弹出文本（nil则使用默认）
function M._executeStrategy(trigObj, executorObj, context)
    local SN = require("StrategyNode")
    local results = {}

    -- 1. 评估触发器策略（条件判定 + 动作）
    if trigObj.triggerStrategy and trigObj.triggerStrategy.rootId then
        local tree = trigObj.triggerStrategy
        -- 构建参数表
        local params = {}
        for _, p in ipairs(tree.params or {}) do
            params[p.name] = p.value
        end
        -- 注入运行时上下文
        if context then
            for k, v in pairs(context) do params[k] = v end
        end
        local actions = SN.Execute(tree, params)
        for _, act in ipairs(actions) do
            table.insert(results, act)
        end
    end

    -- 2. 评估执行器策略
    if executorObj and executorObj.executorStrategy and executorObj.executorStrategy.rootId then
        local tree = executorObj.executorStrategy
        local params = {}
        for _, p in ipairs(tree.params or {}) do
            params[p.name] = p.value
        end
        if context then
            for k, v in pairs(context) do params[k] = v end
        end
        local actions = SN.Execute(tree, params)
        for _, act in ipairs(actions) do
            table.insert(results, act)
        end
    end

    -- 3. 生成文本摘要
    if #results > 0 then
        local texts = {}
        local actionLabels = {}
        for _, a in ipairs(SN.ACTION_TYPES) do actionLabels[a.id] = a.label end
        for _, act in ipairs(results) do
            local label = actionLabels[act.actionType] or act.actionType
            if act.actionType == "set_param" then
                table.insert(texts, label .. ":" .. act.actionParam .. "=" .. act.actionValue)
            elseif act.actionValue ~= 0 then
                table.insert(texts, label .. "(" .. act.actionValue .. ")")
            else
                table.insert(texts, label)
            end
        end
        return table.concat(texts, " | ")
    end
    return nil
end

--- 导出关卡地形数据
function M.ExportLevelTerrainData()
    local ch = levelEditor_.chapterIdx
    local lv = levelEditor_.levelIdx
    local key = ch .. "_" .. lv
    local objects = levelEditor_.objects[key] or {}
    local chapName = CHAPTER_DATA[ch] and CHAPTER_DATA[ch].name or ("第" .. ch .. "章")
    local lvName = levelData_[ch][lv].name

    local lines = {}
    table.insert(lines, "-- " .. chapName .. " " .. lvName .. " 地形数据 --")
    table.insert(lines, "-- type: platform/obstacle/trigger/executor/ground")
    table.insert(lines, "-- x,y: 位置(米)  w,h: 尺寸(米)")
    table.insert(lines, "-- trigger.triggerMethod: none/touch/interact/attack/other")
    table.insert(lines, "-- trigger.mappings: 映射的执行器索引列表")
    table.insert(lines, "-- executor.executorEffect: none/other")
    table.insert(lines, string.format('terrain["%s"] = {', key))
    for i, obj in ipairs(objects) do
        local extra = ""
        if obj.type == "trigger" then
            -- 触发方式
            local tm = obj.triggerMethod or "none"
            extra = extra .. string.format(', triggerMethod="%s"', tm)
            if tm == "other" and obj.triggerMethodDesc and obj.triggerMethodDesc ~= "" then
                extra = extra .. string.format(', triggerMethodDesc="%s"', obj.triggerMethodDesc)
            end
            -- 映射
            if obj.mappings and #obj.mappings > 0 then
                local mStrs = {}
                for _, mIdx in ipairs(obj.mappings) do
                    table.insert(mStrs, tostring(mIdx))
                end
                extra = extra .. string.format(', mappings={%s}', table.concat(mStrs, ","))
            end
            -- 策略树
            if obj.triggerStrategy and obj.triggerStrategy.rootId then
                local SN = require("StrategyNode")
                local stratData = SN.Serialize(obj.triggerStrategy)
                local stratJson = cjson.encode(stratData)
                extra = extra .. string.format(", triggerStrategy=%q", stratJson)
            end
        elseif obj.type == "executor" then
            extra = ', hasCollision=true'
            -- 执行效果
            local ef = obj.executorEffect or "none"
            extra = extra .. string.format(', executorEffect="%s"', ef)
            if ef == "other" and obj.executorEffectDesc and obj.executorEffectDesc ~= "" then
                extra = extra .. string.format(', executorEffectDesc="%s"', obj.executorEffectDesc)
            end
            -- 策略树
            if obj.executorStrategy and obj.executorStrategy.rootId then
                local SN = require("StrategyNode")
                local stratData = SN.Serialize(obj.executorStrategy)
                local stratJson = cjson.encode(stratData)
                extra = extra .. string.format(", executorStrategy=%q", stratJson)
            end
        end
        table.insert(lines, string.format(
            '  {type="%s", x=%.1f, y=%.1f, w=%.1f, h=%.1f, name="%s"%s},',
            obj.type, obj.x, obj.y, obj.w, obj.h, obj.name or "", extra
        ))
    end
    table.insert(lines, "}")

    local exportText = table.concat(lines, "\n")
    print("[TERRAIN EXPORT] " .. chapName .. " " .. lvName)
    print(exportText)

    -- 显示导出面板
    local exportOverlay = UI.Panel {
        id = "terrain_export_overlay",
        position = "absolute", top = "8%", left = "20%",
        width = "60%",
        backgroundColor = {0, 0, 0, 245},
        borderRadius = 12, borderWidth = 1, borderColor = {100, 180, 255, 150},
        paddingTop = 20, paddingBottom = 20,
        paddingLeft = 20, paddingRight = 20,
        flexDirection = "column", gap = 12,
        children = {
            UI.Label {
                text = "地形数据导出（已打印到控制台）",
                fontSize = 15, fontColor = {180, 220, 255, 255},
            },
            UI.Panel {
                width = "100%", maxHeight = 350,
                backgroundColor = {20, 20, 40, 255},
                borderRadius = 6,
                paddingTop = 12, paddingBottom = 12,
                paddingLeft = 12, paddingRight = 12,
                overflow = "scroll",
                children = {
                    UI.Label {
                        text = exportText, fontSize = 11,
                        fontColor = {180, 255, 180, 255},
                    },
                },
            },
            UI.Panel {
                flexDirection = "row", gap = 12,
                children = {
                    UI.Button {
                        id = "export_copy_btn",
                        text = "复制文本", fontSize = 13,
                        width = 100, height = 32,
                        backgroundColor = {50, 120, 180, 220}, borderRadius = 6,
                        justifyContent = "center", alignItems = "center",
                        fontColor = {255,255,255,255},
                        onClick = function()
                            ui:SetClipboardText(exportText)
                            local btn = levelEditor_.uiRoot:FindById("export_copy_btn")
                            if btn then btn:SetText("已复制!") end
                        end,
                    },
                    UI.Button {
                        text = "关闭", fontSize = 13,
                        width = 100, height = 32,
                        backgroundColor = {100, 60, 60, 220}, borderRadius = 6,
                        justifyContent = "center", alignItems = "center",
                        fontColor = {255,255,255,255},
                        onClick = function()
                            local overlay = levelEditor_.uiRoot:FindById("terrain_export_overlay")
                            if overlay then overlay:Destroy() end
                        end,
                    },
                },
            },
        },
    }
    levelEditor_.uiRoot:AddChild(exportOverlay)
end

--- 获取关卡数据（供外部模块访问）
---@return table levelData_ 完整关卡数据
function M.GetLevelData()
    return levelData_
end

--- 设置关卡数据（从外部导入）
---@param data table 完整关卡数据
function M.SetLevelData(data)
    if data then
        levelData_ = data
    end
end

--- 获取地形编辑数据
function M.GetTerrainData()
    return levelEditor_.objects
end

return M
