-- ============================================================================
-- TitleMenu.lua
-- 关卡选择 + 关卡编辑器核心控制器（CRUD/Undo/Update）
-- 菜单/过场/章节/图层编辑 → menu/MenuFlow.lua
-- 编辑器UI构建 → editor/LevelEditorUI.lua
-- 预览系统 → editor/EditorPreview.lua
-- 画布渲染 → editor/EditorRenderer.lua
-- 全局状态 → editor/EditorState.lua
-- ============================================================================
local S = require("GameState")
local C = require("GameConfig")
local UI = require("urhox-libs/UI")
local NodeCanvas = require("NodeCanvas")
local EditorState = require("editor.EditorState")
local ChapterBg = require("menu.ChapterBg")

local M = {}
local MenuFlow = require("menu.MenuFlow")

-- 关卡数据别名（MenuFlow 持有实际数据）
local levelData_ = MenuFlow.levelData_
local CHAPTER_DATA = MenuFlow.CHAPTER_DATA

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

-- ============================================================================
-- 菜单/过场/章节/图层编辑（已提取到 menu/MenuFlow.lua）
-- ============================================================================
M.ShowTransition = MenuFlow.ShowTransition
M.UpdateTransition = MenuFlow.UpdateTransition
M.IsTransitionActive = MenuFlow.IsTransitionActive
M.ShowTitleScreen = MenuFlow.ShowTitleScreen
M.DismissTitleScreen = MenuFlow.DismissTitleScreen
M.ShowMainMenu = MenuFlow.ShowMainMenu
M.ShowMenuPanel = MenuFlow.ShowMenuPanel
M.CloseMenuPanel = MenuFlow.CloseMenuPanel
M.IsMenuPanelOpen = MenuFlow.IsMenuPanelOpen
M.ShowChapterSelect = MenuFlow.ShowChapterSelect
M.CloseChapterSelect = MenuFlow.CloseChapterSelect
M.IsChapterSelectOpen = MenuFlow.IsChapterSelectOpen
M.ChapterNavigate = MenuFlow.ChapterNavigate
M.LayoutChapterCards = MenuFlow.LayoutChapterCards
M.UpdateChapterSelect = MenuFlow.UpdateChapterSelect
M.EnterGameFromMenu = MenuFlow.EnterGameFromMenu
M.EnterGameWorld = MenuFlow.EnterGameWorld
M.ReturnToChapterSelect = MenuFlow.ReturnToChapterSelect
M.UpdateMainMenuAnimation = MenuFlow.UpdateMainMenuAnimation
M.BuildLayerEditor = MenuFlow.BuildLayerEditor
M.RefreshLayerEditor = MenuFlow.RefreshLayerEditor
M.CreateBgLayerRow = MenuFlow.CreateBgLayerRow
M.CreateUILayerRow = MenuFlow.CreateUILayerRow
M.ApplyBgLayerPos = MenuFlow.ApplyBgLayerPos
M.ApplyUILayerPos = MenuFlow.ApplyUILayerPos
M.MoveUILayer = MenuFlow.MoveUILayer
M.RebuildUILayerContainer = MenuFlow.RebuildUILayerContainer
M.ShowLayerEditorExport = MenuFlow.ShowLayerEditorExport
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

    -- 背景：赛博宗教风格动态转场
    local bg = ChapterBg.Create()

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
        -- 编辑按钮（右上角小按钮）
        local editBtn = isUnlocked and UI.Button {
            position = "absolute", top = 6, right = 6,
            width = 32, height = 22,
            backgroundColor = {80, 120, 200, 220},
            borderRadius = 4,
            justifyContent = "center", alignItems = "center",
            zIndex = 10,
            children = {
                UI.Label { text = "编辑", fontSize = 9, fontColor = {255, 255, 255, 255}, pointerEvents = "none" },
            },
            onClick = function()
                M.EnterLevelEditor(chapterIdx, lvIdx)
            end,
        } or nil

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
                    M.PlayLevel(chapterIdx, lvIdx)
                end
            end,
        }
        -- 将编辑按钮叠加到卡片上
        if editBtn then levelCard:AddChild(editBtn) end
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
    ChapterBg.Destroy()
    if levelSelect_.uiRoot then
        levelSelect_.uiRoot:Destroy()
        levelSelect_.uiRoot = nil
    end
end

--- 关卡选择背景动画更新（每帧调用）
function M.UpdateLevelSelect(dt)
    if not levelSelect_.active then return end
    ChapterBg.Update(dt)
end

--- 关卡选择页面是否打开
function M.IsLevelSelectOpen()
    return levelSelect_.active
end

-- ============================================================================
-- 关卡内编辑器（地形/平台/障碍/机关）
-- ============================================================================

-- 编辑器状态（已提取到 editor/EditorState.lua，此处为别名引用）
local levelEditor_ = EditorState.state
local EDITOR_TOOLS = EditorState.TOOLS

--- 直接进入关卡游玩（跳过编辑器，直接启动预览/游戏）
function M.PlayLevel(chapterIdx, levelIdx)
    -- 设置关卡索引
    levelEditor_.chapterIdx = chapterIdx
    levelEditor_.levelIdx = levelIdx
    levelEditor_.playedDirectly = true

    -- 加载关卡数据（优先 JSON 文件，最后默认数据）
    local key = chapterIdx .. "_" .. levelIdx
    local jsonPath = "levels/" .. key .. ".json"
    -- 始终尝试从 JSON 加载最新数据（覆盖内存缓存）
    local loaded = M.ImportLevelData(jsonPath)
    if not loaded and not levelEditor_.objects[key] then
        levelEditor_.objects[key] = {
            { type = "ground", x = -0.5, y = 12.5, w = 23.0, h = 3.0, name = "地面" },
            { type = "platform", x = 5.0, y = 9.0, w = 4.0, h = 0.5, name = "平台1" },
            { type = "platform", x = 12.0, y = 7.5, w = 3.0, h = 0.5, name = "平台2" },
            { type = "platform", x = 11.0, y = 10.5, w = 3.0, h = 0.5, name = "platform5" },
        }
    end

    -- 隐藏关卡选择UI
    if levelSelect_.uiRoot then
        levelSelect_.uiRoot:SetVisible(false)
    end

    -- 直接启动预览（不进入编辑器）
    local EditorPreview = require("editor.EditorPreview")
    EditorPreview.StartPreview()
    print("[PLAY] 直接进入关卡: ch=" .. chapterIdx .. " lv=" .. levelIdx)
end

--- 进入关卡编辑器
function M.EnterLevelEditor(chapterIdx, levelIdx)
    levelEditor_.active = true
    levelEditor_.chapterIdx = chapterIdx
    levelEditor_.levelIdx = levelIdx
    levelEditor_.selectedObj = nil
    levelEditor_.currentTool = "platform"

    -- 初始化关卡物件（优先从 JSON 导入，其次用内存缓存，最后用默认数据）
    local key = chapterIdx .. "_" .. levelIdx
    local jsonPath = "levels/" .. key .. ".json"
    -- 始终尝试从 JSON 加载（覆盖内存缓存，确保数据最新）
    local loaded = M.ImportLevelData(jsonPath)
    if not loaded and not levelEditor_.objects[key] then
        -- 默认地形数据
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
    end
    -- 序列帧素材（放在 if 外面，确保已有数据也能补充；ImportTexture 内部去重）
    M.ImportTexture("image/小鸟序列帧精灵图.png", "小鸟序列帧精灵图", "seq")
    -- 修正已有记录的分类（可能之前导入为其他分类）
    for _, tex in ipairs(levelEditor_.customTextures) do
        if tex.path == "image/小鸟序列帧精灵图.png" and tex.cat ~= "seq" then
            tex.cat = "seq"
        end
    end
    -- 光之祭坛素材（前缀"交互-" → interact 分类）
    M.ImportTexture("image/光之祭坛/交互-祭坛底座.png", "祭坛底座", "interact")
    M.ImportTexture("image/光之祭坛/交互-祭坛核心.png", "祭坛核心", "interact")
    M.ImportTexture("image/光之祭坛/交互-祭坛碎片.png", "祭坛碎片", "interact")
    M.ImportTexture("image/光之祭坛/交互-祭坛核心完整.png", "祭坛核心完整", "interact")
    -- 地图素材文件夹（按前缀自动分类：背景→bg, 平台→tile）
    -- 放在 if 外面，确保已有关卡数据也能补充新素材（ImportTexture 内部已去重）
    local mapAssets = {
        -- 平台素材
        "平台-秋叶",
        "平台-花",
        "平台-蓝白",
        "平台-镂空平台",
        "平台-镂空平台浅",
        "平台-镂空平台深",
        -- 背景素材
        "背景-斜线淡绿",
        "背景-时隙废墟-上",
        "背景-时隙废墟-中",
        "背景-时隙废墟-近",
        "背景-时隙废墟-远",
        "背景-时隙废墟-阴",
        "背景-楼梯",
        "背景-正弦飞鸟",
        "背景-破碎时空",
        "背景-神像-无花",
        "背景-神像-有花",
        "背景-空境花园-中",
        "背景-空境花园-近",
        "背景-空境花园-远",
        "背景-花",
        "背景-解密1-近",
        "背景-解密1-远",
    }
    for _, name in ipairs(mapAssets) do
        ---@type string
        local cat = "other"
        ---@type string
        local displayName = name
        if name:find("^平台%-") then
            cat = "tile"
            displayName = name:sub(#"平台-" + 1)  -- 去掉"平台-"前缀
        elseif name:find("^背景%-") then
            cat = "bg"
            displayName = name:sub(#"背景-" + 1)  -- 去掉"背景-"前缀
        end
        M.ImportTexture("image/地图素材/" .. name .. ".png", displayName, cat)
    end
    -- 标志素材
    local signAssets = { "标志-蓝白分割线", "标志-蓝金分割线", "标志-金分割线", "标志-金蓝分割线", "标志-（竖）金色花纹" }
    for _, name in ipairs(signAssets) do
        local displayName = name:sub(#"标志-" + 1)
        M.ImportTexture("image/地图素材/标志/" .. name .. ".png", displayName, "sign")
    end
    -- 对话框素材：立绘
    local portraitDir = "image/对话框/诺米立绘/"
    local portraitFiles = { "诺米-傲娇", "诺米-哭", "诺米-嫌弃", "诺米-尴尬", "诺米-张嘴", "诺米-微笑", "诺米-普通", "诺米-生气", "诺米-疑惑", "诺米-自豪", "诺米-闭眼笑", "诺米-震惊" }
    for _, name in ipairs(portraitFiles) do
        M.ImportTexture(portraitDir .. name .. ".png", name, "dlg_portrait")
    end
    -- 对话框素材：底图
    M.ImportTexture("image/对话框/底图/诺米对话框-窄.png", "诺米对话框-窄", "dlg_bg")
    M.ImportTexture("image/对话框/底图/诺米对话框-宽.png", "诺米对话框-宽", "dlg_bg")
    -- 对话框素材：整体
    local dlgWholeFiles = { "诺米-常态", "诺米-张嘴", "诺米-疑惑", "诺米-震惊" }
    for _, name in ipairs(dlgWholeFiles) do
        M.ImportTexture("image/对话框/整体/" .. name .. ".png", name, "dlg_whole")
    end
    -- 纯色素材
    M.ImportTexture("image/白色.png", "白色", "solid")
    M.ImportTexture("image/透明.png", "透明", "solid")

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
    -- 退出前自动保存当前编辑状态到文件（防止重新进入时读取旧数据）
    M.ExportLevelTerrainData(true)

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

--- 从游戏中打开关卡编辑器（加载当前关卡地形数据）
--- @param chapterIdx number|nil 章节索引（默认1）
--- @param levelIdx number|nil 关卡索引（默认1）
function M.OpenEditorFromGame(chapterIdx, levelIdx)
    chapterIdx = chapterIdx or 1
    levelIdx = levelIdx or 1

    -- 保存之前的UI根节点
    levelEditor_.prevGameUIRoot = UI.GetRoot()
    levelEditor_.openedFromGame = true

    -- 设置编辑器模式标志（阻止游戏输入处理）
    S.editorMode = true

    -- 先创建编辑器容器根节点（16:9 安全区域 + BuildLevelEditorUI 会将 uiRoot 挂载到此）
    local editorGameRoot = UI.Panel {
        width = "100%", height = "100%",
        justifyContent = "center", alignItems = "center",
        pointerEvents = "box-none",
        children = {
            UI.Panel {
                width = 1920, height = 1080,
                pointerEvents = "box-none",
                overflow = "hidden",
                children = {
                    UI.Button {
                        text = "返回游戏", fontSize = 12,
                        position = "absolute", bottom = 16, right = 16,
                        zIndex = 100,
                        width = 80, height = 34,
                        backgroundColor = {180, 60, 60, 220},
                        color = "#ffffff",
                        borderRadius = 8,
                        borderWidth = 1, borderColor = {255, 100, 100, 180},
                        onClick = function()
                            M.CloseEditorToGame()
                        end,
                    },
                },
            },
        },
    }
    levelEditor_.editorGameRoot = editorGameRoot
    UI.SetRoot(editorGameRoot)

    -- 进入编辑器（BuildLevelEditorUI 会把 uiRoot 挂到 editorGameRoot）
    M.EnterLevelEditor(chapterIdx, levelIdx)

    print("[EDITOR] 从游戏中打开编辑器: ch=" .. chapterIdx .. " lv=" .. levelIdx)
end

--- 从编辑器返回游戏
function M.CloseEditorToGame()
    if not levelEditor_.openedFromGame then return end

    -- 先导出当前状态到文件（静默模式，不弹UI）
    M.ExportLevelTerrainData(true)

    -- 退出编辑器
    levelEditor_.active = false
    if levelEditor_.editorGameRoot then
        levelEditor_.editorGameRoot:Destroy()
        levelEditor_.editorGameRoot = nil
    end
    levelEditor_.uiRoot = nil

    -- 恢复游戏UI
    if levelEditor_.prevGameUIRoot then
        UI.SetRoot(levelEditor_.prevGameUIRoot)
        levelEditor_.prevGameUIRoot = nil
    end

    -- 恢复游戏模式
    S.editorMode = false
    levelEditor_.openedFromGame = false

    print("[EDITOR] 返回游戏")
end

--- 保存当前状态到撤销栈（在修改前调用）
function M.PushUndoState()
    local ch = levelEditor_.chapterIdx
    local lv = levelEditor_.levelIdx
    local key = ch .. "_" .. lv
    local objects = levelEditor_.objects[key] or {}
    -- 深拷贝当前对象列表（完整复制所有属性，包括贴图/效果/触发器/执行器）
    local snapshot = {}
    for i, obj in ipairs(objects) do
        local copy = { type = obj.type, x = obj.x, y = obj.y, w = obj.w, h = obj.h, name = obj.name }
        -- 颜色
        if obj.color then
            copy.color = { obj.color[1], obj.color[2], obj.color[3], obj.color[4] }
        end
        -- 旧式单贴图（兼容）
        if obj.texture then
            copy.texture = obj.texture
            copy.textureName = obj.textureName
            copy.texScaleW = obj.texScaleW
            copy.texScaleH = obj.texScaleH
        end
        -- 多贴图图层（深拷贝）
        if obj.texLayers and #obj.texLayers > 0 then
            copy.texLayers = {}
            for _, layer in ipairs(obj.texLayers) do
                local layerCopy = {
                    path = layer.path,
                    name = layer.name,
                    opacity = layer.opacity,
                    scaleW = layer.scaleW,
                    scaleH = layer.scaleH,
                    visible = layer.visible,
                    lockAspect = layer.lockAspect,
                    rotation = layer.rotation,
                    offsetX = layer.offsetX,
                    offsetY = layer.offsetY,
                }
                -- 图层独立动态效果（深拷贝）
                if layer.effects and #layer.effects > 0 then
                    layerCopy.effects = {}
                    for _, eff in ipairs(layer.effects) do
                        local paramsCopy = {}
                        if eff.params then
                            for k, v in pairs(eff.params) do paramsCopy[k] = v end
                        end
                        table.insert(layerCopy.effects, { id = eff.id, params = paramsCopy })
                    end
                end
                table.insert(copy.texLayers, layerCopy)
            end
            copy.selectedTexLayer = obj.selectedTexLayer
        end
        -- 动态效果（深拷贝）
        if obj.effects and #obj.effects > 0 then
            copy.effects = {}
            for _, eff in ipairs(obj.effects) do
                local paramsCopy = {}
                if eff.params then
                    for k, v in pairs(eff.params) do paramsCopy[k] = v end
                end
                table.insert(copy.effects, { id = eff.id, params = paramsCopy })
            end
        end
        -- mappings
        if obj.mappings then
            copy.mappings = {}
            for mi, v in ipairs(obj.mappings) do
                copy.mappings[mi] = v
            end
        end
        -- 触发器专有
        if obj.type == "trigger" then
            copy.triggerMethod = obj.triggerMethod
            copy.triggerMethodDesc = obj.triggerMethodDesc
            if obj.triggerStrategy then
                local SN = require("StrategyNode")
                copy.triggerStrategy = SN.Deserialize(SN.Serialize(obj.triggerStrategy))
            end
        end
        -- 执行器专有
        if obj.type == "executor" then
            copy.executorEffect = obj.executorEffect
            copy.executorEffectDesc = obj.executorEffectDesc
            copy.hasCollision = obj.hasCollision
            if obj.executorStrategy then
                local SN = require("StrategyNode")
                copy.executorStrategy = SN.Deserialize(SN.Serialize(obj.executorStrategy))
            end
        end
        snapshot[i] = copy
    end
    -- 深拷贝背景图层列表
    local bgSnapshot = {}
    if levelEditor_.bgLayers then
        for _, bg in ipairs(levelEditor_.bgLayers) do
            local bgCopy = {
                path = bg.path, name = bg.name, opacity = bg.opacity,
                x = bg.x, y = bg.y, w = bg.w, h = bg.h,
                depth = bg.depth, visible = bg.visible, lockAspect = bg.lockAspect,
                locked = bg.locked,
            }
            -- 背景图层动态效果
            if bg.effects and #bg.effects > 0 then
                bgCopy.effects = {}
                for _, eff in ipairs(bg.effects) do
                    local p = {}
                    if eff.params then for k, v in pairs(eff.params) do p[k] = v end end
                    table.insert(bgCopy.effects, { id = eff.id, params = p })
                end
            end
            table.insert(bgSnapshot, bgCopy)
        end
    end

    table.insert(levelEditor_.undoStack, {
        key = key, objects = snapshot, selectedObj = levelEditor_.selectedObj,
        bgLayers = bgSnapshot, selectedBgLayer = levelEditor_.selectedBgLayer,
        playerStartX = levelEditor_.playerStartX,
        playerStartY = levelEditor_.playerStartY,
    })
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
    -- 恢复背景图层
    if state.bgLayers then
        levelEditor_.bgLayers = state.bgLayers
        levelEditor_.selectedBgLayer = state.selectedBgLayer
    end
    -- 恢复玩家初始位置
    levelEditor_.playerStartX = state.playerStartX
    levelEditor_.playerStartY = state.playerStartY
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

    -- 导出面板打开时跳过画布交互（避免点击按钮同帧触发 BuildLevelEditorUI 销毁面板）
    if levelEditor_.uiRoot and levelEditor_.uiRoot:FindById("terrain_export_overlay") then
        return
    end

    -- WASD 键盘平移画布（TextField 聚焦时不触发）
    local focusedWidget = UI.GetFocus()
    local isTextInput = focusedWidget and focusedWidget.OnTextInput and focusedWidget.state and focusedWidget.state.focused
    if not isTextInput then
        local panSpeed = 300 * dt  -- 像素/秒
        local panChanged = false
        if input:GetKeyDown(KEY_W) then
            levelEditor_.canvasPanY = (levelEditor_.canvasPanY or 0) + panSpeed
            panChanged = true
        end
        if input:GetKeyDown(KEY_S) then
            levelEditor_.canvasPanY = (levelEditor_.canvasPanY or 0) - panSpeed
            panChanged = true
        end
        if input:GetKeyDown(KEY_A) then
            levelEditor_.canvasPanX = (levelEditor_.canvasPanX or 0) + panSpeed
            panChanged = true
        end
        if input:GetKeyDown(KEY_D) then
            levelEditor_.canvasPanX = (levelEditor_.canvasPanX or 0) - panSpeed
            panChanged = true
        end
        if panChanged and levelEditor_.uiRoot then
            local contentPanel = levelEditor_.uiRoot:FindById("canvas_content")
            if contentPanel then
                contentPanel:SetStyle({ left = levelEditor_.canvasPanX, top = levelEditor_.canvasPanY })
            end
        end
    end

    -- 鼠标滚轮缩放画布（无文本聚焦 + 鼠标不在inspector面板上）
    local dprZ = graphics:GetDPR()
    local mouseXLogical = input.mousePosition.x / dprZ
    local screenWLogical = graphics:GetWidth() / dprZ
    local rightPanelW = 280
    local marginZ = levelEditor_.margin or 8
    local mouseOverInspector = mouseXLogical > (screenWLogical - rightPanelW - marginZ)
    if not isTextInput and not mouseOverInspector then
        local wheel = input.mouseMoveWheel
        if wheel ~= 0 then
            local oldZoom = levelEditor_.canvasZoom or 1.0
            local newZoom = oldZoom * (1.0005 ^ wheel)
            newZoom = math.max(0.3, math.min(3.0, newZoom))
            -- 以鼠标位置为中心缩放（调整 pan 使鼠标指向的世界点不变）
            local dpr2 = graphics:GetDPR()
            local mxz = input.mousePosition.x / dpr2
            local myz = input.mousePosition.y / dpr2
            local canvasOffXz = levelEditor_.margin or 8
            local canvasOffYz = (levelEditor_.toolbarH or 50) + (levelEditor_.margin or 8)
            local localMX = mxz - canvasOffXz
            local localMY = myz - canvasOffYz
            local ratio = newZoom / oldZoom
            local panX = levelEditor_.canvasPanX or 0
            local panY = levelEditor_.canvasPanY or 0
            levelEditor_.canvasPanX = localMX - (localMX - panX) * ratio
            levelEditor_.canvasPanY = localMY - (localMY - panY) * ratio
            levelEditor_.canvasZoom = newZoom
            -- 实时重建 UI（网格线、背景图层等跟随缩放更新）
            M.BuildLevelEditorUI()
        end
    end

    -- 每帧更新鼠标世界坐标显示
    if levelEditor_.uiRoot then
        local coordLabel = levelEditor_.uiRoot:FindById("canvas_mouse_coord")
        if coordLabel then
            local dpr = graphics:GetDPR()
            local mx = input.mousePosition.x / dpr
            local my = input.mousePosition.y / dpr
            local margin = 8
            local toolbarH = 50
            local panX = levelEditor_.canvasPanX or 0
            local panY = levelEditor_.canvasPanY or 0
            local canvasMouseX = mx - margin - panX
            local canvasMouseY = my - (toolbarH + margin) - panY
            local zoom = levelEditor_.canvasZoom or 1.0
            local gridSize = (levelEditor_.gridSize or 40) * zoom
            local worldH = levelEditor_.worldH or 17.5
            local wx = canvasMouseX / gridSize
            local wy = worldH - (canvasMouseY / gridSize)
            coordLabel:SetText(string.format("世界坐标: (%.2f, %.2f)", wx, wy))
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

    -- Ctrl+C 复制选中物件（深拷贝所有属性）
    if input:GetKeyDown(KEY_CTRL) and input:GetKeyPress(KEY_C) then
        local key2 = levelEditor_.chapterIdx .. "_" .. levelEditor_.levelIdx
        local objs = levelEditor_.objects[key2] or {}
        if levelEditor_.selectedObj and objs[levelEditor_.selectedObj] then
            M.PushUndoState()
            local src = objs[levelEditor_.selectedObj]
            local copy = { type = src.type, x = src.x + 1, y = src.y, w = src.w, h = src.h, name = (src.name or "") .. "_copy" }
            -- 颜色
            if src.color then
                copy.color = { src.color[1], src.color[2], src.color[3], src.color[4] }
            end
            -- 旧式单贴图（兼容）
            if src.texture then
                copy.texture = src.texture
                copy.textureName = src.textureName
                copy.texScaleW = src.texScaleW
                copy.texScaleH = src.texScaleH
            end
            -- 多贴图图层（深拷贝）
            if src.texLayers and #src.texLayers > 0 then
                copy.texLayers = {}
                for _, layer in ipairs(src.texLayers) do
                    table.insert(copy.texLayers, {
                        path = layer.path,
                        name = layer.name,
                        opacity = layer.opacity,
                        scaleW = layer.scaleW,
                        scaleH = layer.scaleH,
                        visible = layer.visible,
                        lockAspect = layer.lockAspect,
                    })
                end
                copy.selectedTexLayer = src.selectedTexLayer
            end
            -- 动态效果（深拷贝）
            if src.effects and #src.effects > 0 then
                copy.effects = {}
                for _, eff in ipairs(src.effects) do
                    -- 深拷贝 params 表
                    local paramsCopy = {}
                    if eff.params then
                        for k, v in pairs(eff.params) do paramsCopy[k] = v end
                    end
                    table.insert(copy.effects, { id = eff.id, params = paramsCopy })
                end
            end
            -- 触发器专有
            if src.type == "trigger" then
                copy.triggerMethod = src.triggerMethod
                copy.triggerMethodDesc = src.triggerMethodDesc
                if src.mappings then copy.mappings = {} end
                -- 深拷贝策略节点树
                if src.triggerStrategy and src.triggerStrategy.rootId then
                    local SN = require("StrategyNode")
                    copy.triggerStrategy = SN.Deserialize(SN.Serialize(src.triggerStrategy))
                end
            end
            -- 执行器专有
            if src.type == "executor" then
                copy.executorEffect = src.executorEffect
                copy.executorEffectDesc = src.executorEffectDesc
                copy.hasCollision = src.hasCollision
                -- 深拷贝策略节点树
                if src.executorStrategy and src.executorStrategy.rootId then
                    local SN = require("StrategyNode")
                    copy.executorStrategy = SN.Deserialize(SN.Serialize(src.executorStrategy))
                end
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
    local gridSize = levelEditor_.gridSize * (levelEditor_.canvasZoom or 1.0)
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
                    -- 未命中四角锚点 → 检测贴图内部区域拖拽移动（修改 offsetX/offsetY）
                    if not levelEditor_.texDragging then
                        local offX = (tLayer.offsetX or 0) * pw
                        local offY = (tLayer.offsetY or 0) * ph
                        local layerCX = px + pw / 2 + offX - tW / 2
                        local layerCY = py + ph / 2 - offY - tH / 2
                        if contentX >= layerCX and contentX <= layerCX + tW
                           and contentY >= layerCY and contentY <= layerCY + tH then
                            levelEditor_.texDragging = true
                            levelEditor_.texDragType = "move"
                            levelEditor_.texDragStartX = mx
                            levelEditor_.texDragStartY = my
                            levelEditor_.texDragStartOffX = tLayer.offsetX or 0
                            levelEditor_.texDragStartOffY = tLayer.offsetY or 0
                            levelEditor_.texDragObjPW = pw
                            levelEditor_.texDragObjPH = ph
                            M.PushUndoState()
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
                if tLayer and dragType == "move" then
                    -- 中心拖拽：更新 offsetX/offsetY（物件尺寸百分比，X右正 Y上正）
                    tLayer.offsetX = levelEditor_.texDragStartOffX + dx / math.max(pw, 10)
                    tLayer.offsetY = levelEditor_.texDragStartOffY - dy / math.max(ph, 10)
                elseif tLayer and dragType ~= "scale" then
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
                levelEditor_.camBoundsSelected = false
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
        if selBgIdx and bgLayers[selBgIdx] and not bgLayers[selBgIdx].locked then
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
       and levelEditor_.camBoundsSelected
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
                levelEditor_.camBoundsSelected = false
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

-- 编辑器 UI 构建（已提取到 editor/LevelEditorUI.lua）
local LevelEditorUI = require("editor.LevelEditorUI")
M.BuildLevelEditorUI = LevelEditorUI.BuildLevelEditorUI
M.BuildPropsPanel = LevelEditorUI.BuildPropsPanel

--- 世界坐标转画布像素（含平移偏移）
-- 坐标转换（转发到 EditorState）
M.WorldToCanvas = EditorState.WorldToCanvas
M.CanvasToWorld = EditorState.CanvasToWorld
M.GetObjectColor = EditorState.GetObjectColor

-- ============================================================================
-- 预览模式（已提取到 editor/EditorPreview.lua）
-- ============================================================================
local EditorPreview = require("editor.EditorPreview")
M.StartPreview = EditorPreview.StartPreview
M.StopPreview = EditorPreview.StopPreview
M.RefreshPreviewTerrain = EditorPreview.RefreshPreviewTerrain
M.UpdatePreview = EditorPreview.UpdatePreview
M.IsPreviewActive = EditorPreview.IsPreviewActive
M.JustStoppedPreview = EditorPreview.JustStoppedPreview
M.HandlePreviewBeginContact = EditorPreview.HandlePreviewBeginContact
M.HandlePreviewEndContact = EditorPreview.HandlePreviewEndContact

-- 编辑器画布渲染（已提取到 editor/EditorRenderer.lua）
local EditorRenderer = require("editor.EditorRenderer")
M.DrawEditorCanvasTextures = EditorRenderer.DrawEditorCanvasTextures


-- DrawPreview + _executeStrategy（已提取到 editor/EditorPreview.lua）
M.DrawPreview = EditorPreview.DrawPreview
M._executeStrategy = EditorPreview._executeStrategy
--- 导出关卡完整数据（JSON 格式，写入文件 + UI 反馈）
function M.ExportLevelTerrainData(silent)
    local ch = levelEditor_.chapterIdx
    local lv = levelEditor_.levelIdx
    local key = ch .. "_" .. lv
    local objects = levelEditor_.objects[key] or {}
    local chapName = CHAPTER_DATA[ch] and CHAPTER_DATA[ch].name or ("第" .. ch .. "章")
    local chapterLevels = MenuFlow.levelData_ and MenuFlow.levelData_[ch]
    local lvName = (chapterLevels and chapterLevels[lv] and chapterLevels[lv].name) or ("关卡" .. lv)

    -- 序列化单个物件
    local function serializeObject(obj)
        local o = {
            type = obj.type,
            x = obj.x,
            y = obj.y,
            w = obj.w,
            h = obj.h,
            name = obj.name or "",
        }
        -- 旋转角度（非零时才保存）
        if obj.rotation and obj.rotation ~= 0 then
            o.rotation = obj.rotation
        end
        -- 颜色
        if obj.color then
            o.color = obj.color  -- {r, g, b, a}
        end
        -- 贴图层
        if obj.texLayers and #obj.texLayers > 0 then
            o.texLayers = {}
            for _, layer in ipairs(obj.texLayers) do
                local layerData = {
                    path = layer.path,
                    name = layer.name,
                    opacity = layer.opacity,
                    scaleW = layer.scaleW,
                    scaleH = layer.scaleH,
                    rotation = layer.rotation or 0,
                    visible = layer.visible,
                    lockAspect = layer.lockAspect or false,
                    offsetX = layer.offsetX or 0,
                    offsetY = layer.offsetY or 0,
                }
                -- 图层独立动态效果
                if layer.effects and #layer.effects > 0 then
                    layerData.effects = {}
                    for _, eff in ipairs(layer.effects) do
                        local p = {}
                        if eff.params then for k, v in pairs(eff.params) do p[k] = v end end
                        table.insert(layerData.effects, { id = eff.id, params = p })
                    end
                end
                table.insert(o.texLayers, layerData)
            end
        end
        -- 触发器专有字段
        if obj.type == "trigger" then
            o.triggerMethod = obj.triggerMethod or "none"
            if o.triggerMethod == "other" and obj.triggerMethodDesc and obj.triggerMethodDesc ~= "" then
                o.triggerMethodDesc = obj.triggerMethodDesc
            end
            if obj.mappings and #obj.mappings > 0 then
                o.mappings = obj.mappings
            end
            if obj.triggerStrategy and obj.triggerStrategy.rootId then
                local SN = require("StrategyNode")
                o.triggerStrategy = SN.Serialize(obj.triggerStrategy)
            end
        end
        -- 执行器专有字段
        if obj.type == "executor" then
            o.hasCollision = true
            o.executorEffect = obj.executorEffect or "none"
            if o.executorEffect == "other" and obj.executorEffectDesc and obj.executorEffectDesc ~= "" then
                o.executorEffectDesc = obj.executorEffectDesc
            end
            if obj.executorStrategy and obj.executorStrategy.rootId then
                local SN = require("StrategyNode")
                o.executorStrategy = SN.Serialize(obj.executorStrategy)
            end
        end
        -- 动态效果（通用，所有物件类型均可配置）
        if obj.effects and #obj.effects > 0 then
            o.effects = {}
            for _, eff in ipairs(obj.effects) do
                table.insert(o.effects, { id = eff.id, params = eff.params })
            end
        end
        return o
    end

    -- 序列化物件列表
    local serializedObjects = {}
    for _, obj in ipairs(objects) do
        table.insert(serializedObjects, serializeObject(obj))
    end

    -- 序列化背景图层
    local serializedBgLayers = {}
    if levelEditor_.bgLayers then
        for _, bg in ipairs(levelEditor_.bgLayers) do
            local bgEntry = {
                path = bg.path,
                name = bg.name,
                opacity = bg.opacity,
                x = bg.x,
                y = bg.y,
                w = bg.w,
                h = bg.h,
                depth = bg.depth,
                visible = bg.visible,
                lockAspect = bg.lockAspect or false,
            }
            -- 序列化动态效果
            if bg.effects and #bg.effects > 0 then
                bgEntry.effects = {}
                for _, eff in ipairs(bg.effects) do
                    local p = {}
                    if eff.params then for k, v in pairs(eff.params) do p[k] = v end end
                    table.insert(bgEntry.effects, { id = eff.id, params = p })
                end
            end
            table.insert(serializedBgLayers, bgEntry)
        end
    end

    -- 序列化自定义贴图素材
    local serializedCustomTextures = {}
    if levelEditor_.customTextures then
        for _, tex in ipairs(levelEditor_.customTextures) do
            table.insert(serializedCustomTextures, {
                path = tex.path,
                name = tex.name,
                cat = tex.cat,
            })
        end
    end

    -- 序列化关卡元数据（行为规则）
    local levelMeta = nil
    local chapterLevelData = MenuFlow.levelData_ and MenuFlow.levelData_[ch]
    if chapterLevelData and chapterLevelData[lv] then
        local ld = chapterLevelData[lv]
        levelMeta = {
            name = ld.name,
            difficulty = ld.difficulty,
            enemies = ld.enemies,
            timeLimit = ld.timeLimit,
            reward = ld.reward,
            description = ld.description or "",
        }
    end

    -- 组装完整导出数据
    local exportData = {
        version = 1,
        chapter = ch,
        level = lv,
        key = key,
        chapterName = chapName,
        levelName = lvName,
        -- 关卡行为元数据
        levelMeta = levelMeta,
        -- 世界尺寸参数
        worldW = levelEditor_.worldW,
        worldH = levelEditor_.worldH,
        -- 镜头范围
        cameraBounds = {
            enabled = levelEditor_.cameraBoundsEnabled,
            x = levelEditor_.cameraBounds.x,
            y = levelEditor_.cameraBounds.y,
            w = levelEditor_.cameraBounds.w,
            h = levelEditor_.cameraBounds.h,
        },
        -- 角色渲染倍率
        playerRenderScale = levelEditor_.playerRenderScale or 1.0,
        -- 角色垂直偏移
        playerOffsetY = levelEditor_.playerOffsetY or 0.0,
        -- 玩家初始位置（nil时不写入，预览时自动计算）
        playerStartX = levelEditor_.playerStartX,
        playerStartY = levelEditor_.playerStartY,
        -- 地形物件
        objects = serializedObjects,
        -- 背景图层
        bgLayers = serializedBgLayers,
        -- 自定义贴图素材库
        customTextures = serializedCustomTextures,
    }

    -- 编码为 JSON
    local exportJson = cjson.encode(exportData)

    -- 写入文件（游戏虚拟FS，用于游戏内持久化）
    fileSystem:CreateDir("levels")
    local filePath = "levels/" .. key .. ".json"
    local file = File(filePath, FILE_WRITE)
    local writeOk = false
    if file:IsOpen() then
        file:WriteString(exportJson)
        file:Close()
        writeOk = true
        print("[LEVEL EXPORT] 已写入文件: " .. filePath)
    else
        print("[LEVEL EXPORT] 写入文件失败: " .. filePath)
    end

    -- 同步保存预制体库数据
    do
        local Prefab = require("editor.Prefab")
        local prefabList = Prefab.ListPrefabs()
        if #prefabList > 0 then
            local allPrefabs = {}
            for _, pInfo in ipairs(prefabList) do
                local data = Prefab.LoadPrefab(pInfo.filePath)
                if data then
                    allPrefabs[#allPrefabs + 1] = data
                end
            end
            if #allPrefabs > 0 then
                local prefabJson = cjson.encode({ version = 1, prefabs = allPrefabs })
                fileSystem:CreateDir("levels")
                local pfPath = "levels/prefabs_library.json"
                local pfFile = File(pfPath, FILE_WRITE)
                if pfFile:IsOpen() then
                    pfFile:WriteString(prefabJson)
                    pfFile:Close()
                    print("[LEVEL EXPORT] 预制体库已同步保存: " .. pfPath .. " (" .. #allPrefabs .. " 个)")
                end
            end
        end
    end

    -- 打印到控制台（带明确标记，便于AI检索）
    print("===LEVEL_EXPORT_START===")
    print(exportJson)
    print("===LEVEL_EXPORT_END===")

    -- 静默模式时不显示UI（从 CloseEditorToGame 调用时使用）
    if silent then return end

    -- 显示导出面板
    local statusText = writeOk
        and ("已导出到 " .. filePath)
        or "导出失败（文件写入错误）"
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
                text = "关卡数据导出（JSON）",
                fontSize = 15, fontColor = {180, 220, 255, 255},
            },
            UI.Label {
                text = statusText,
                fontSize = 12, fontColor = writeOk and {120, 255, 120, 255} or {255, 120, 120, 255},
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
                        text = exportJson, fontSize = 11,
                        fontColor = {180, 255, 180, 255},
                    },
                },
            },
            UI.Panel {
                flexDirection = "row", gap = 12,
                children = {
                    UI.Button {
                        id = "export_copy_btn",
                        text = "复制JSON", fontSize = 13,
                        width = 100, height = 32,
                        backgroundColor = {50, 120, 180, 220}, borderRadius = 6,
                        justifyContent = "center", alignItems = "center",
                        fontColor = {255,255,255,255},
                        onClick = function()
                            ui.useSystemClipboard = true
                            ui.clipboardText = exportJson
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

--- 从 JSON 文件导入关卡完整数据，还原编辑器状态
--- @param filePath string|nil 文件路径（默认 "levels/{ch}_{lv}.json"）
--- @return boolean success 是否成功
function M.ImportLevelData(filePath)
    local ch = levelEditor_.chapterIdx
    local lv = levelEditor_.levelIdx
    local key = ch .. "_" .. lv
    filePath = filePath or ("levels/" .. key .. ".json")

    -- 优先从可写沙箱目录读取（ExportLevelTerrainData 写入的位置）
    -- 这样用户编辑保存后再次进入能读到最新数据，不会被 assets/ 中的旧文件覆盖
    local jsonStr = nil
    if fileSystem:FileExists(filePath) then
        local sandboxFile = File(filePath, FILE_READ)
        if sandboxFile and sandboxFile:IsOpen() then
            jsonStr = sandboxFile:ReadString()
            sandboxFile:Close()
            print("[LEVEL IMPORT] 从沙箱读取: " .. filePath)
        end
    end
    if not jsonStr then
        -- Fallback: 从资源缓存读取（assets/ 打包资源）
        if not cache:Exists(filePath) then
            return false
        end
        local cacheFile = cache:GetFile(filePath)
        if not cacheFile or not cacheFile:IsOpen() then
            return false
        end
        jsonStr = cacheFile:ReadString()
        cacheFile:Close()
        print("[LEVEL IMPORT] 从资源缓存读取: " .. filePath)
    end

    -- 解析 JSON
    local ok, data = pcall(cjson.decode, jsonStr)
    if not ok or type(data) ~= "table" then
        print("[LEVEL IMPORT] JSON 解析失败: " .. filePath)
        return false
    end

    print("[LEVEL IMPORT] 开始导入 " .. filePath .. " (version=" .. tostring(data.version) .. ")")

    -- 还原世界尺寸
    if data.worldW then levelEditor_.worldW = data.worldW end
    if data.worldH then levelEditor_.worldH = data.worldH end

    -- 还原镜头范围
    if data.cameraBounds then
        levelEditor_.cameraBoundsEnabled = data.cameraBounds.enabled ~= false
        levelEditor_.cameraBounds.x = data.cameraBounds.x or 2
        levelEditor_.cameraBounds.y = data.cameraBounds.y or 1
        levelEditor_.cameraBounds.w = data.cameraBounds.w or 26
        levelEditor_.cameraBounds.h = data.cameraBounds.h or 15.5
    end

    -- 还原角色渲染倍率
    if data.playerRenderScale then
        levelEditor_.playerRenderScale = data.playerRenderScale
    end

    -- 还原角色垂直偏移
    if data.playerOffsetY then
        levelEditor_.playerOffsetY = data.playerOffsetY
    end

    -- 还原玩家初始位置
    levelEditor_.playerStartX = data.playerStartX  -- nil表示自动
    levelEditor_.playerStartY = data.playerStartY

    -- 还原物件列表
    if data.objects then
        local objects = {}
        for _, o in ipairs(data.objects) do
            local obj = {
                type = o.type or "platform",
                x = o.x or 0,
                y = o.y or 0,
                w = o.w or 1,
                h = o.h or 1,
                name = o.name or "",
            }
            -- 旋转角度
            if o.rotation and o.rotation ~= 0 then
                obj.rotation = o.rotation
            end
            -- 颜色
            if o.color then
                obj.color = o.color
            end
            -- 贴图层
            if o.texLayers and #o.texLayers > 0 then
                obj.texLayers = {}
                for _, tl in ipairs(o.texLayers) do
                    local layerObj = {
                        path = tl.path,
                        name = tl.name,
                        opacity = tl.opacity or 1.0,
                        scaleW = tl.scaleW or 1.0,
                        scaleH = tl.scaleH or 1.0,
                        rotation = tl.rotation or 0,
                        visible = tl.visible ~= false,
                        lockAspect = tl.lockAspect or false,
                        offsetX = tl.offsetX or 0,
                        offsetY = tl.offsetY or 0,
                    }
                    -- 图层独立动态效果
                    if tl.effects and #tl.effects > 0 then
                        layerObj.effects = {}
                        for _, eff in ipairs(tl.effects) do
                            table.insert(layerObj.effects, { id = eff.id, params = eff.params or {} })
                        end
                    end
                    table.insert(obj.texLayers, layerObj)
                end
            end
            -- 触发器字段
            if obj.type == "trigger" then
                obj.triggerMethod = o.triggerMethod or "none"
                obj.triggerMethodDesc = o.triggerMethodDesc or ""
                obj.mappings = o.mappings or {}
                if o.triggerStrategy then
                    local SN = require("StrategyNode")
                    obj.triggerStrategy = SN.Deserialize(o.triggerStrategy)
                end
            end
            -- 执行器字段
            if obj.type == "executor" then
                obj.executorEffect = o.executorEffect or "none"
                obj.executorEffectDesc = o.executorEffectDesc or ""
                if o.executorStrategy then
                    local SN = require("StrategyNode")
                    obj.executorStrategy = SN.Deserialize(o.executorStrategy)
                end
            end
            -- 动态效果（通用）
            if o.effects and #o.effects > 0 then
                obj.effects = {}
                for _, eff in ipairs(o.effects) do
                    table.insert(obj.effects, { id = eff.id, params = eff.params or {} })
                end
            end
            table.insert(objects, obj)
        end
        levelEditor_.objects[key] = objects
    end

    -- 还原背景图层
    if data.bgLayers then
        levelEditor_.bgLayers = {}
        for _, bg in ipairs(data.bgLayers) do
            local entry = {
                path = bg.path,
                name = bg.name,
                opacity = bg.opacity or 1.0,
                x = bg.x or 0,
                y = bg.y or 0,
                w = bg.w or 10,
                h = bg.h or 10,
                depth = bg.depth or 0,
                visible = bg.visible ~= false,
                lockAspect = bg.lockAspect or false,
                locked = true,  -- 重新进入编辑器时默认锁定，防止误操作
            }
            -- 还原动态效果
            if bg.effects and #bg.effects > 0 then
                entry.effects = {}
                for _, eff in ipairs(bg.effects) do
                    local p = {}
                    if eff.params then for k, v in pairs(eff.params) do p[k] = v end end
                    table.insert(entry.effects, { id = eff.id, params = p })
                end
            end
            table.insert(levelEditor_.bgLayers, entry)
        end
        levelEditor_.selectedBgLayer = nil
    end

    -- 还原自定义贴图素材库
    if data.customTextures then
        levelEditor_.customTextures = {}
        for _, tex in ipairs(data.customTextures) do
            table.insert(levelEditor_.customTextures, {
                path = tex.path,
                name = tex.name,
                cat = tex.cat or "misc",
            })
        end
    end

    -- 还原关卡元数据
    if data.levelMeta then
        local chapterLevels = MenuFlow.levelData_ and MenuFlow.levelData_[ch]
        if chapterLevels and chapterLevels[lv] then
            local ld = chapterLevels[lv]
            if data.levelMeta.name then ld.name = data.levelMeta.name end
            if data.levelMeta.difficulty then ld.difficulty = data.levelMeta.difficulty end
            if data.levelMeta.enemies then ld.enemies = data.levelMeta.enemies end
            if data.levelMeta.timeLimit then ld.timeLimit = data.levelMeta.timeLimit end
            if data.levelMeta.reward then ld.reward = data.levelMeta.reward end
            if data.levelMeta.description then ld.description = data.levelMeta.description end
        end
    end

    -- 还原预制体库数据（从 prefabs_library.json 恢复到虚拟FS）
    do
        local Prefab = require("editor.Prefab")
        local pfPath = "levels/prefabs_library.json"
        local pfJson = nil
        if fileSystem:FileExists(pfPath) then
            local pfFile = File(pfPath, FILE_READ)
            if pfFile and pfFile:IsOpen() then
                pfJson = pfFile:ReadString()
                pfFile:Close()
            end
        end
        if not pfJson and cache:Exists(pfPath) then
            local pfFile = cache:GetFile(pfPath)
            if pfFile and pfFile:IsOpen() then
                pfJson = pfFile:ReadString()
                pfFile:Close()
            end
        end
        if pfJson then
            local pOk, pData = pcall(cjson.decode, pfJson)
            if pOk and pData and pData.prefabs then
                fileSystem:CreateDir(Prefab.PREFAB_DIR)
                local count = 0
                for _, prefabData in ipairs(pData.prefabs) do
                    local name = prefabData.name or ("prefab_" .. count)
                    local pfFilePath = Prefab.PREFAB_DIR .. "/" .. name .. ".prefab.json"
                    local wf = File(pfFilePath, FILE_WRITE)
                    if wf:IsOpen() then
                        wf:WriteString(cjson.encode(prefabData))
                        wf:Close()
                        count = count + 1
                    end
                end
                if count > 0 then
                    print("[LEVEL IMPORT] 预制体库已恢复: " .. count .. " 个")
                end
            end
        end
    end

    -- 重置 UI 瞬态
    levelEditor_.selectedObj = nil
    levelEditor_.selectedBgLayer = nil

    -- 刷新编辑器 UI
    if levelEditor_.active and levelEditor_.uiRoot then
        M.BuildLevelEditorUI()
    end

    print("[LEVEL IMPORT] 导入完成: " .. key .. " (" .. #(levelEditor_.objects[key] or {}) .. " objects, "
        .. #(levelEditor_.bgLayers or {}) .. " bgLayers)")
    return true
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
        MenuFlow.SetLevelData(data)
    end
end

--- 获取地形编辑数据
function M.GetTerrainData()
    return levelEditor_.objects
end

-- 暴露内部状态给已提取的子模块（避免循环依赖）
M.levelSelect_ = levelSelect_

return M
