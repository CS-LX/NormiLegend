-- ============================================================================
-- TitleMenu.lua
-- 标题画面、主菜单（Live2D视差）、图层编辑器、过渡系统
-- ============================================================================
local S = require("GameState")
local C = require("GameConfig")
local UI = require("urhox-libs/UI")
local Animation = require("Animation")
local Combat = require("Combat")
local NodeCanvas = require("NodeCanvas")
local EditorState = require("editor.EditorState")

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

-- 编辑器状态（已提取到 editor/EditorState.lua，此处为别名引用）
local levelEditor_ = EditorState.state
local EDITOR_TOOLS = EditorState.TOOLS

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
