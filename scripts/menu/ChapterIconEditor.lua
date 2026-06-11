-- ============================================================================
-- 章节图标图层编辑器
-- 管理章节卡片的多图层合成显示及编辑
-- ============================================================================
local UI = require("urhox-libs/UI")
local cjson = require("cjson")

local M = {}

-- ============================================================================
-- 章节图标图层数据
-- 每个章节可以有多个图层，按 z-order 从下到上排列
-- ============================================================================

---@class ChapterIconLayer
---@field name string 图层名称
---@field path string 图片资源路径（相对于 assets/）
---@field x number 偏移X（相对于卡片左上角，像素）
---@field y number 偏移Y（相对于卡片左上角，像素）
---@field w number 图层宽度（像素）
---@field h number 图层高度（像素）
---@field visible boolean 是否可见

-- 各章节的图层配置（索引 = 章节号）
-- 卡片尺寸: 320 x 420
local CARD_W = 320
local CARD_H = 420

---@type table<number, ChapterIconLayer[]>
local chapterIconLayers_ = {
    -- 第一章（序章）图层：从下到上
    [1] = {
        { name = "门后月亮", path = "image/序章图标/门后月亮.png", x = -35, y = -40, w = 290, h = 290, visible = true },
        { name = "门",       path = "image/序章图标/门.png",       x = 60,  y = 20,  w = 210, h = 399, visible = true },
        { name = "人物剪影", path = "image/序章图标/人物剪影.png", x = 190, y = 180, w = 140, h = 257, visible = true },
        { name = "左下飞鸟", path = "image/序章图标/左下飞鸟.png", x = -35, y = 240, w = 180, h = 180, visible = true },
        { name = "右上飞鸟", path = "image/序章图标/右上飞鸟.png", x = 200, y = 20,  w = 130, h = 130, visible = true },
        { name = "艺术字",   path = "image/序章图标/艺术字.png",   x = -70, y = -75, w = 180, h = 383, visible = true },
    },
}

-- 编辑器状态
local editorState_ = {
    visible = false,
    chapterIdx = 1,     -- 当前编辑的章节索引
    panel = nil,        -- 编辑面板 UI
    toggleBtn = nil,    -- 切换按钮
    cardContainer = nil, -- 章节卡片容器引用（用于实时更新）
}

-- 动画状态
local animState_ = {
    elapsed = 0,          -- 累计时间
    hovered = false,      -- 是否悬停
    hoverScale = 1.0,     -- 当前悬停缩放值
    hoverTarget = 1.0,    -- 悬停目标缩放值
    cardScale = 1.0,      -- 卡片在轮播中的缩放比例
    layerRefs = {},       -- 图层 UI 引用（用于动画更新）
    containerRef = nil,   -- 图层容器引用
}

-- ============================================================================
-- 公共接口
-- ============================================================================

--- 获取章节图标图层数据
---@param chapterIdx number
---@return ChapterIconLayer[]|nil
function M.GetLayers(chapterIdx)
    return chapterIconLayers_[chapterIdx]
end

--- 构建章节卡片内容（替换纯色卡片为图层合成）
--- 返回一个包含所有图层的 Panel，可作为卡片的 children
---@param chapterIdx number
---@param cardW number 卡片宽度
---@param cardH number 卡片高度
---@return table|nil layerContainer UI 面板（绝对定位，覆盖整个卡片）
function M.BuildCardLayers(chapterIdx, cardW, cardH)
    local layers = chapterIconLayers_[chapterIdx]
    if not layers then return nil end

    local container = UI.Panel {
        id = "chapter_icon_layers_" .. chapterIdx,
        position = "absolute", top = 0, left = 0,
        width = cardW, height = cardH,
        pointerEvents = "none",
    }

    -- 清空图层引用（仅章节1需要动画）
    if chapterIdx == 1 then
        animState_.layerRefs = {}
        animState_.containerRef = container
    end

    for i, layer in ipairs(layers) do
        if layer.visible then
            local layerPanel = UI.Panel {
                id = "ch_icon_layer_" .. chapterIdx .. "_" .. i,
                position = "absolute",
                left = layer.x, top = layer.y,
                width = layer.w, height = layer.h,
                backgroundImage = layer.path,
                backgroundFit = "contain",
                pointerEvents = "none",
            }
            container:AddChild(layerPanel)

            -- 保存章节1图层引用用于呼吸动画
            if chapterIdx == 1 then
                table.insert(animState_.layerRefs, {
                    panel = layerPanel,
                    phase = (i - 1) * 0.8,  -- 每层不同相位，产生波浪感
                    baseX = layer.x,
                    baseY = layer.y,
                    baseW = layer.w,
                    baseH = layer.h,
                })
            end
        end
    end

    return container
end

--- 重建指定章节卡片的图层显示（编辑时实时刷新）
---@param chapterIdx number
---@param card table 卡片 UI 对象
function M.RefreshCardLayers(chapterIdx, card)
    if not card then return end
    -- 移除旧的图层容器
    local oldContainer = card:FindById("chapter_icon_layers_" .. chapterIdx)
    if oldContainer then oldContainer:Destroy() end

    -- 重建
    local layers = chapterIconLayers_[chapterIdx]
    if not layers then return end

    local container = M.BuildCardLayers(chapterIdx, CARD_W, CARD_H)
    if container then
        card:AddChild(container)
    end
end

-- ============================================================================
-- 图层编辑器 UI
-- ============================================================================

--- 初始化编辑器（在章节选择界面打开时调用）
---@param parentRoot table 主 UI 根节点
---@param cards table[] 章节卡片引用数组
function M.Init(parentRoot, cards)
    editorState_.parentRoot = parentRoot
    editorState_.cards = cards
    M.BuildEditorUI()
end

--- 销毁编辑器（在章节选择关闭时调用）
function M.Destroy()
    if editorState_.panel then
        editorState_.panel:Destroy()
        editorState_.panel = nil
    end
    if editorState_.toggleBtn then
        editorState_.toggleBtn:Destroy()
        editorState_.toggleBtn = nil
    end
    editorState_.visible = false
    editorState_.parentRoot = nil
    editorState_.cards = nil
end

--- 构建编辑器 UI
function M.BuildEditorUI()
    if not editorState_.parentRoot then return end

    -- 切换按钮
    editorState_.toggleBtn = UI.Button {
        position = "absolute", bottom = 16, right = 16,
        text = "图标编辑", fontSize = 12,
        fontColor = {255, 255, 255, 220},
        backgroundColor = {0, 0, 0, 180},
        borderRadius = 4,
        paddingLeft = 8, paddingRight = 8,
        paddingTop = 4, paddingBottom = 4,
        onClick = function()
            editorState_.visible = not editorState_.visible
            M.RefreshEditorPanel()
        end,
    }
    editorState_.parentRoot:AddChild(editorState_.toggleBtn)

    -- 编辑面板
    editorState_.panel = UI.Panel {
        id = "chapterIconEditorPanel",
        position = "absolute", bottom = 50, right = 16,
        width = 380, maxHeight = "80%",
        backgroundColor = {0, 0, 0, 210},
        borderRadius = 8,
        paddingTop = 10, paddingBottom = 10,
        paddingLeft = 10, paddingRight = 10,
        flexDirection = "column", gap = 4,
        overflow = "scroll",
        display = "none",
    }
    editorState_.parentRoot:AddChild(editorState_.panel)
end

--- 刷新编辑面板内容
function M.RefreshEditorPanel()
    if not editorState_.panel then return end
    editorState_.panel:ClearChildren()

    if not editorState_.visible then
        editorState_.panel:SetStyle({ display = "none" })
        return
    end
    editorState_.panel:SetStyle({ display = "flex" })

    local chIdx = editorState_.chapterIdx
    local layers = chapterIconLayers_[chIdx]

    -- 标题 + 章节切换（始终显示，即使无图层数据也能切换章节）
    local headerRow = UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 8, width = "100%", marginBottom = 6,
    }
    headerRow:AddChild(UI.Label {
        text = "章节" .. chIdx .. " 图标图层", fontSize = 14,
        fontColor = {150, 200, 255, 255},
    })
    -- 切换章节按钮
    headerRow:AddChild(UI.Button {
        text = "<", fontSize = 12, width = 22, height = 22,
        backgroundColor = (chIdx > 1) and {80, 80, 120, 200} or {60, 60, 60, 100}, borderRadius = 3,
        justifyContent = "center", alignItems = "center",
        fontColor = (chIdx > 1) and {255,255,255,255} or {100,100,100,255},
        onClick = function()
            if editorState_.chapterIdx > 1 then
                editorState_.chapterIdx = editorState_.chapterIdx - 1
                M.RefreshEditorPanel()
            end
        end,
    })
    headerRow:AddChild(UI.Button {
        text = ">", fontSize = 12, width = 22, height = 22,
        backgroundColor = (chIdx < 4) and {80, 80, 120, 200} or {60, 60, 60, 100}, borderRadius = 3,
        justifyContent = "center", alignItems = "center",
        fontColor = (chIdx < 4) and {255,255,255,255} or {100,100,100,255},
        onClick = function()
            if editorState_.chapterIdx < 4 then
                editorState_.chapterIdx = editorState_.chapterIdx + 1
                M.RefreshEditorPanel()
            end
        end,
    })
    editorState_.panel:AddChild(headerRow)

    if not layers then
        editorState_.panel:AddChild(UI.Label {
            text = "该章节无图标图层数据", fontSize = 13,
            fontColor = {200, 200, 200, 180}, marginTop = 8,
        })
        return
    end

    -- 图层列表（从上到下 = 从最顶层到最底层显示）
    editorState_.panel:AddChild(UI.Label {
        text = "图层（从上到下）", fontSize = 11,
        fontColor = {180, 180, 200, 200}, marginBottom = 2,
    })

    for i = #layers, 1, -1 do
        editorState_.panel:AddChild(M.CreateLayerRow(chIdx, i, layers[i]))
    end

    -- 导出按钮
    editorState_.panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {100,100,100,80}, marginTop = 6, marginBottom = 4 })
    editorState_.panel:AddChild(UI.Button {
        text = "导出图层数据", fontSize = 12,
        width = "100%", height = 28,
        backgroundColor = {60, 100, 180, 220}, borderRadius = 4,
        justifyContent = "center", alignItems = "center",
        fontColor = {255,255,255,255},
        onClick = function() M.ExportData() end,
    })
end

--- 创建单个图层编辑行
---@param chIdx number 章节索引
---@param layerIdx number 图层索引
---@param layer ChapterIconLayer 图层数据
function M.CreateLayerRow(chIdx, layerIdx, layer)
    local layers = chapterIconLayers_[chIdx]
    local totalLayers = #layers

    -- 外层容器：垂直排列两行
    local container = UI.Panel {
        flexDirection = "column", width = "100%",
        paddingTop = 3, paddingBottom = 3, paddingLeft = 4, paddingRight = 4,
        backgroundColor = (layerIdx % 2 == 0) and {40,40,60,100} or {0,0,0,0},
        borderRadius = 3, gap = 3,
    }

    -- 第一行：可见性 + 名称 + 上移下移
    local row1 = UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 6, width = "100%",
    }
    row1:AddChild(UI.Button {
        text = layer.visible and "●" or "○", fontSize = 10, width = 20, height = 20,
        backgroundColor = layer.visible and {60,160,60,200} or {100,60,60,200}, borderRadius = 3,
        justifyContent = "center", alignItems = "center",
        fontColor = {255,255,255,255},
        onClick = function()
            layers[layerIdx].visible = not layers[layerIdx].visible
            M.ApplyLayerChange(chIdx)
            M.RefreshEditorPanel()
        end,
    })
    row1:AddChild(UI.Label { text = layer.name, fontSize = 11, fontColor = {255,220,180,255}, flexGrow = 1 })
    row1:AddChild(UI.Button {
        text = "▲", fontSize = 9, width = 22, height = 20,
        backgroundColor = (layerIdx < totalLayers) and {120,80,150,200} or {60,60,60,100}, borderRadius = 3,
        justifyContent = "center", alignItems = "center",
        fontColor = (layerIdx < totalLayers) and {255,255,255,255} or {100,100,100,255},
        onClick = function()
            if layerIdx < totalLayers then M.MoveLayer(chIdx, layerIdx, 1) end
        end,
    })
    row1:AddChild(UI.Button {
        text = "▼", fontSize = 9, width = 22, height = 20,
        backgroundColor = (layerIdx > 1) and {120,80,150,200} or {60,60,60,100}, borderRadius = 3,
        justifyContent = "center", alignItems = "center",
        fontColor = (layerIdx > 1) and {255,255,255,255} or {100,100,100,255},
        onClick = function()
            if layerIdx > 1 then M.MoveLayer(chIdx, layerIdx, -1) end
        end,
    })
    container:AddChild(row1)

    -- 第二行：X / Y / S 控制
    local row2 = UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 4, width = "100%",
        paddingLeft = 26,  -- 缩进对齐名称
    }

    -- X 控制组
    row2:AddChild(UI.Label { text = "X", fontSize = 9, fontColor = {100,200,100,255}, width = 12 })
    row2:AddChild(UI.Button {
        text = "-", fontSize = 11, width = 20, height = 18,
        backgroundColor = {80,120,80,200}, borderRadius = 3,
        justifyContent = "center", alignItems = "center", fontColor = {255,255,255,255},
        onClick = function()
            layers[layerIdx].x = layers[layerIdx].x - 5
            M.ApplyLayerChange(chIdx)
            M.RefreshEditorPanel()
        end,
    })
    row2:AddChild(UI.Label { text = tostring(math.floor(layer.x)), fontSize = 9, fontColor = {255,255,255,255}, width = 30, textAlign = "center" })
    row2:AddChild(UI.Button {
        text = "+", fontSize = 11, width = 20, height = 18,
        backgroundColor = {80,120,80,200}, borderRadius = 3,
        justifyContent = "center", alignItems = "center", fontColor = {255,255,255,255},
        onClick = function()
            layers[layerIdx].x = layers[layerIdx].x + 5
            M.ApplyLayerChange(chIdx)
            M.RefreshEditorPanel()
        end,
    })

    -- 间隔
    row2:AddChild(UI.Panel { width = 6 })

    -- Y 控制组
    row2:AddChild(UI.Label { text = "Y", fontSize = 9, fontColor = {100,100,220,255}, width = 12 })
    row2:AddChild(UI.Button {
        text = "-", fontSize = 11, width = 20, height = 18,
        backgroundColor = {80,80,120,200}, borderRadius = 3,
        justifyContent = "center", alignItems = "center", fontColor = {255,255,255,255},
        onClick = function()
            layers[layerIdx].y = layers[layerIdx].y - 5
            M.ApplyLayerChange(chIdx)
            M.RefreshEditorPanel()
        end,
    })
    row2:AddChild(UI.Label { text = tostring(math.floor(layer.y)), fontSize = 9, fontColor = {255,255,255,255}, width = 30, textAlign = "center" })
    row2:AddChild(UI.Button {
        text = "+", fontSize = 11, width = 20, height = 18,
        backgroundColor = {80,80,120,200}, borderRadius = 3,
        justifyContent = "center", alignItems = "center", fontColor = {255,255,255,255},
        onClick = function()
            layers[layerIdx].y = layers[layerIdx].y + 5
            M.ApplyLayerChange(chIdx)
            M.RefreshEditorPanel()
        end,
    })

    -- 间隔
    row2:AddChild(UI.Panel { width = 6 })

    -- S 缩放控制组
    row2:AddChild(UI.Label { text = "S", fontSize = 9, fontColor = {200,180,80,255}, width = 12 })
    row2:AddChild(UI.Button {
        text = "-", fontSize = 11, width = 20, height = 18,
        backgroundColor = {120,100,60,200}, borderRadius = 3,
        justifyContent = "center", alignItems = "center", fontColor = {255,255,255,255},
        onClick = function()
            local l = layers[layerIdx]
            local ratio = l.h / l.w
            l.w = math.max(10, l.w - 10)
            l.h = math.floor(l.w * ratio + 0.5)
            M.ApplyLayerChange(chIdx)
            M.RefreshEditorPanel()
        end,
    })
    row2:AddChild(UI.Label { text = tostring(math.floor(layer.w)), fontSize = 9, fontColor = {255,255,255,255}, width = 30, textAlign = "center" })
    row2:AddChild(UI.Button {
        text = "+", fontSize = 11, width = 20, height = 18,
        backgroundColor = {120,100,60,200}, borderRadius = 3,
        justifyContent = "center", alignItems = "center", fontColor = {255,255,255,255},
        onClick = function()
            local l = layers[layerIdx]
            local ratio = l.h / l.w
            l.w = l.w + 10
            l.h = math.floor(l.w * ratio + 0.5)
            M.ApplyLayerChange(chIdx)
            M.RefreshEditorPanel()
        end,
    })

    container:AddChild(row2)
    return container
end

--- 移动图层顺序
---@param chIdx number 章节索引
---@param layerIdx number 当前图层索引
---@param direction number 1=上移（数组中向后）, -1=下移（数组中向前）
function M.MoveLayer(chIdx, layerIdx, direction)
    local layers = chapterIconLayers_[chIdx]
    if not layers then return end
    local target = layerIdx + direction
    if target < 1 or target > #layers then return end

    layers[layerIdx], layers[target] = layers[target], layers[layerIdx]
    M.ApplyLayerChange(chIdx)
    M.RefreshEditorPanel()
end

--- 应用图层变更到卡片显示
---@param chIdx number
function M.ApplyLayerChange(chIdx)
    if not editorState_.cards then return end
    local card = editorState_.cards[chIdx]
    if card then
        M.RefreshCardLayers(chIdx, card)
    end
end

--- 导出图层数据（打印到控制台 + 写入文件）
function M.ExportData()
    local chIdx = editorState_.chapterIdx
    local layers = chapterIconLayers_[chIdx]
    if not layers then
        print("[CHAPTER ICON] 无图层数据，跳过导出")
        return
    end

    print("[CHAPTER ICON] 开始导出章节 " .. chIdx .. " 的图层数据...")

    local exportData = {}
    for i, layer in ipairs(layers) do
        table.insert(exportData, {
            name = layer.name,
            path = layer.path,
            x = layer.x, y = layer.y,
            w = layer.w, h = layer.h,
            visible = layer.visible,
        })
    end

    local jsonStr = cjson.encode({ chapterIdx = chIdx, layers = exportData })

    -- 控制台输出（始终打印，方便调试）
    print("===== CHAPTER_ICON_DATA_BEGIN =====")
    print(jsonStr)
    print("===== CHAPTER_ICON_DATA_END =====")

    -- 写入文件（确保目录存在）
    local dirPath = fileSystem:GetUserDocumentsDir() .. "levels"
    if not fileSystem:DirExists(dirPath) then
        fileSystem:CreateDir(dirPath)
        print("[CHAPTER ICON] 创建目录: " .. dirPath)
    end
    local filePath = dirPath .. "/chapter_icon_" .. chIdx .. ".json"
    local file = File(filePath, FILE_WRITE)
    if file and file:IsOpen() then
        file:WriteString(jsonStr)
        file:Close()
        print("[CHAPTER ICON] 导出成功: " .. filePath)
    else
        -- 尝试相对路径写入
        local relPath = "levels/chapter_icon_" .. chIdx .. ".json"
        print("[CHAPTER ICON] 绝对路径写入失败，尝试相对路径: " .. relPath)
        if not fileSystem:DirExists("levels") then
            fileSystem:CreateDir("levels")
        end
        local file2 = File(relPath, FILE_WRITE)
        if file2 and file2:IsOpen() then
            file2:WriteString(jsonStr)
            file2:Close()
            print("[CHAPTER ICON] 导出成功(相对路径): " .. relPath)
        else
            print("[CHAPTER ICON] 导出失败！无法写入文件")
        end
    end
end

--- 尝试从 JSON 加载章节图标配置
---@param chIdx number
function M.LoadFromFile(chIdx)
    local filePath = "levels/chapter_icon_" .. chIdx .. ".json"
    if not cache:Exists(filePath) then return false end

    local file = cache:GetFile(filePath)
    if not file or not file:IsOpen() then return false end

    local jsonStr = file:ReadString()
    file:Close()

    local ok, data = pcall(cjson.decode, jsonStr)
    if not ok or type(data) ~= "table" or not data.layers then return false end

    chapterIconLayers_[chIdx] = {}
    for _, layer in ipairs(data.layers) do
        table.insert(chapterIconLayers_[chIdx], {
            name = layer.name or "未命名",
            path = layer.path or "",
            x = layer.x or 0,
            y = layer.y or 0,
            w = layer.w or 100,
            h = layer.h or 100,
            visible = layer.visible ~= false,
        })
    end
    print("[CHAPTER ICON] 从文件加载: " .. filePath .. " (" .. #chapterIconLayers_[chIdx] .. " layers)")
    return true
end

-- ============================================================================
-- 呼吸动画 & 悬停效果
-- ============================================================================

--- 设置悬停状态（由 MenuFlow 调用）
---@param hovered boolean
function M.SetHovered(hovered)
    animState_.hovered = hovered
    animState_.hoverTarget = hovered and 1.08 or 1.0
end

--- 设置卡片在轮播中的缩放（由 MenuFlow.LayoutChapterCards 调用）
---@param scale number
function M.SetCardScale(scale)
    animState_.cardScale = scale
end

--- 每帧更新动画（由 MenuFlow.UpdateChapterSelect 调用）
---@param dt number
function M.Update(dt)
    if #animState_.layerRefs == 0 then return end

    animState_.elapsed = animState_.elapsed + dt

    -- 悬停缩放平滑插值
    local speed = 6.0  -- 插值速度
    animState_.hoverScale = animState_.hoverScale + (animState_.hoverTarget - animState_.hoverScale) * math.min(dt * speed, 1.0)

    local hoverS = animState_.hoverScale

    local cardS = animState_.cardScale

    -- 更新每个图层的动画
    for _, ref in ipairs(animState_.layerRefs) do
        -- 呼吸效果：仅上下浮动（无缩放）
        local breathTime = animState_.elapsed + ref.phase
        local breathOffY = math.sin(breathTime * 0.9) * 2.0 * cardS  -- 浮动也随卡片缩小

        -- 综合缩放 = 卡片轮播缩放 * 悬停缩放
        local totalScale = cardS * hoverS

        local newW = ref.baseW * totalScale
        local newH = ref.baseH * totalScale
        local newX = ref.baseX * cardS
        local newY = ref.baseY * cardS

        -- 悬停偏移（以图层中心为锚点放大）
        local hoverOffX = ref.baseW * cardS * (1.0 - hoverS) * 0.5
        local hoverOffY = ref.baseH * cardS * (1.0 - hoverS) * 0.5

        ref.panel:SetStyle({
            left = newX + hoverOffX,
            top = newY + hoverOffY + breathOffY,
            width = newW,
            height = newH,
        })
    end
end

return M
