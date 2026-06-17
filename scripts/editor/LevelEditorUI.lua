-- ============================================================================
-- LevelEditorUI.lua  —  关卡编辑器 UI 构建（从 TitleMenu.lua 提取）
-- 职责: BuildLevelEditorUI / BuildPropsPanel
-- ============================================================================
local S = require("GameState")
local UI = require("urhox-libs/UI")
local EditorState = require("editor.EditorState")
local MenuFlow = require("menu.MenuFlow")

local M = {}

-- 延迟引用 TitleMenu（避免循环依赖）
local TitleMenu_
local function getTitleMenu()
    if not TitleMenu_ then TitleMenu_ = require("TitleMenu") end
    return TitleMenu_
end

-- 状态别名
local levelEditor_ = EditorState.state
local CHAPTER_DATA = MenuFlow.CHAPTER_DATA
local EDITOR_TOOLS = EditorState.TOOLS

-- ============================================================================
-- UI 构建
-- ============================================================================
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
    local lvName = MenuFlow.levelData_[ch][lv].name

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
        onClick = function() getTitleMenu().ExitLevelEditor() end,
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
                -- 离开 prefab 工具时清理放置状态
                if tid ~= "prefab" then
                    levelEditor_.prefabMode = nil
                    levelEditor_.prefabData = nil
                end
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
        onClick = function() getTitleMenu().StartPreview() end,
    })
    toolbar:AddChild(UI.Button {
        paddingLeft = 12, paddingRight = 12, paddingTop = 6, paddingBottom = 6,
        backgroundColor = {60, 100, 180, 220}, borderRadius = 6,
        children = { UI.Label { text = "导出", fontSize = 13, fontColor = {255, 255, 255, 255} } },
        onClick = function() getTitleMenu().ExportLevelTerrainData() end,
    })
    toolbar:AddChild(UI.Button {
        paddingLeft = 12, paddingRight = 12, paddingTop = 6, paddingBottom = 6,
        backgroundColor = {140, 90, 40, 220}, borderRadius = 6,
        children = { UI.Label { text = "导入", fontSize = 13, fontColor = {255, 255, 255, 255} } },
        onClick = function() getTitleMenu().ImportLevelData() end,
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
    local zoom = levelEditor_.canvasZoom or 1.0
    local contentW = math.ceil(canvasW * zoom)
    local contentH = math.ceil(canvasH * zoom)
    local canvasContent = UI.Panel {
        id = "canvas_content",
        position = "absolute", left = panX, top = panY,
        width = contentW, height = contentH,
        backgroundColor = {0, 0, 0, 0},
        pointerEvents = "box-none",  -- 容器自身不拦截点击，但子元素（物件按钮）可被点击
    }

    -- 绘制网格线（用细条Panel模拟）
    local gridSize = levelEditor_.gridSize * zoom
    -- 垂直线
    for gx = 0, contentW, gridSize do
        canvasContent:AddChild(UI.Panel {
            position = "absolute", top = 0, left = gx,
            width = 1, height = contentH,
            backgroundColor = {40, 40, 60, 80},
            pointerEvents = "none",
        })
    end
    -- 水平线
    for gy = 0, contentH, gridSize do
        canvasContent:AddChild(UI.Panel {
            position = "absolute", top = gy, left = 0,
            width = contentW, height = 1,
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
            local bpx, bpy, bpw, bph = getTitleMenu().WorldToCanvas(lx, canvasTopY, lw, lh)
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

    -- 画布点击事件（z-index 低于 canvasContent，物件按钮优先接收点击）
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
            -- select/delete/texture/prefab 由物件按钮自身处理点击或特殊逻辑
            if tool == "select" or tool == "delete" or tool == "texture" then
                return
            end
            -- 预制体放置模式
            if tool == "prefab" then
                if levelEditor_.prefabMode == "place" and levelEditor_.prefabData then
                    local Prefab = require("editor.Prefab")
                    local dpr = graphics:GetDPR()
                    local mx = input.mousePosition.x / dpr
                    local my = input.mousePosition.y / dpr
                    local canvasOffX = margin
                    local canvasOffY = toolbarH + margin
                    local localX = mx - canvasOffX
                    local localY = my - canvasOffY
                    local pnX = levelEditor_.canvasPanX or 0
                    local pnY = levelEditor_.canvasPanY or 0
                    local cX = localX - pnX
                    local cY = localY - pnY
                    cX = math.floor(cX / gridSize) * gridSize
                    cY = math.floor(cY / gridSize) * gridSize
                    local wx, wy = getTitleMenu().CanvasToWorld(cX, cY, gridSize, gridSize)
                    getTitleMenu().PushUndoState()
                    local newIndices = Prefab.InstantiateObjects(levelEditor_.prefabData, wx, wy, objects)
                    levelEditor_.objects[key] = objects
                    levelEditor_.selectedObj = newIndices[1]
                    print("[Prefab] 放置预制体 '" .. (levelEditor_.prefabData.name or "?") .. "' 共 " .. #newIndices .. " 个对象")
                    M.BuildLevelEditorUI()
                end
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
            local wx, wy, ww, wh = getTitleMenu().CanvasToWorld(cX, cY, gridSize * 3, gridSize)
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
            getTitleMenu().PushUndoState()  -- 放置物件前保存撤销状态
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

    -- canvasContent 在 canvas_click_layer 之上，物件按钮可被 hit-test 命中
    canvas:AddChild(canvasContent)

    -- 鼠标世界坐标显示标签（绝对定位在画布左下角）
    canvas:AddChild(UI.Label {
        id = "canvas_mouse_coord",
        position = "absolute", bottom = 4, left = 6,
        fontSize = 11, fontColor = {160, 200, 240, 200},
        text = "",
        pointerEvents = "none",
    })

    -- 渲染已放置的物件（在 canvas_click_layer 之上，可接收点击）
    for idx, obj in ipairs(objects) do
        local objIdx = idx
        local px, py, pw, ph = getTitleMenu().WorldToCanvas(obj.x, obj.y, obj.w, obj.h)
        local objColor = getTitleMenu().GetObjectColor(obj.type)
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

        -- 圆形碰撞时外观为圆形
        local objBorderRadius = 2
        local objDisplayW = math.max(pw, 8)
        local objDisplayH = math.max(ph, 8)
        if obj.collisionShape == "circle" then
            objBorderRadius = math.max(objDisplayW, objDisplayH) / 2
        end

        canvasContent:AddChild(UI.Button {
            id = "obj_" .. idx,
            position = "absolute",
            left = px, top = py,
            width = objDisplayW, height = objDisplayH,
            backgroundColor = bgColor,
            borderRadius = objBorderRadius,
            borderWidth = isSelected and 3 or 1,
            borderColor = isSelected and {255, 255, 0, 255} or {255, 255, 255, 60},
            justifyContent = "center", alignItems = "center",
            overflow = "visible",
            children = objChildren,
            onClick = function()
                -- 画布刚完成拖拽平移或正在平移中，抑制本次点击
                if levelEditor_.justPanned or levelEditor_.canvasPanning then return end
                if levelEditor_.currentTool == "select" or levelEditor_.currentTool == "texture" or levelEditor_.currentTool == "prefab" then
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
            local px, py, pw, ph = getTitleMenu().WorldToCanvas(selObj.x, selObj.y, selObj.w, selObj.h)
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
    -- 渲染在最底层（在背景图层之后、物件之前），仅选中时显示锚点
    if levelEditor_.cameraBoundsEnabled and levelEditor_.cameraBounds then
        local cb = levelEditor_.cameraBounds
        local edWorldH = levelEditor_.worldH or 17.5
        -- cameraBounds.y 是 Y-up 底边，转为 top-down 的 top 坐标
        local cbTopY = edWorldH - cb.y - cb.h
        local cbPx, cbPy, cbPw, cbPh = getTitleMenu().WorldToCanvas(cb.x, cbTopY, cb.w, cb.h)
        local isCamSel = levelEditor_.camBoundsSelected
        -- 范围框边框（未选中时淡化显示）
        canvasContent:AddChild(UI.Panel {
            id = "cam_bounds_frame",
            position = "absolute",
            left = cbPx, top = cbPy,
            width = math.max(cbPw, 4), height = math.max(cbPh, 4),
            borderWidth = isCamSel and 2 or 1,
            borderColor = isCamSel and {255, 200, 50, 220} or {255, 200, 50, 100},
            backgroundColor = {255, 220, 50, isCamSel and 12 or 5},
            borderRadius = 0,
            pointerEvents = "none",
        })
        -- 标签
        canvasContent:AddChild(UI.Panel {
            position = "absolute",
            left = cbPx, top = cbPy - 16,
            width = 70, height = 14,
            backgroundColor = {255, 200, 50, isCamSel and 180 or 80},
            borderRadius = 2,
            justifyContent = "center", alignItems = "center",
            pointerEvents = "none",
            children = {
                UI.Label { text = "镜头范围", fontSize = 9, fontColor = {30, 20, 0, 255} },
            },
        })
        -- 四角锚点（仅选中时显示）
        if isCamSel then
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

    -- 挂载到父UI
    if levelEditor_.openedFromGame then
        -- 从游戏中打开时，挂到 editorGameRoot（重建UI时也需要重新挂载）
        if levelEditor_.editorGameRoot then
            levelEditor_.editorGameRoot:AddChild(levelEditor_.uiRoot)
        end
    else
        local levelSelect_ = getTitleMenu().levelSelect_
        if levelSelect_.uiRoot then
            levelSelect_.uiRoot:AddChild(levelEditor_.uiRoot)
        elseif S.mainMenuUIRoot then
            S.mainMenuUIRoot:AddChild(levelEditor_.uiRoot)
        end
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
        getTitleMenu().RefreshPreviewTerrain()
    end
end

--- 构建右侧属性面板内容
function M.BuildPropsPanel(panel, objects)
    local ch = levelEditor_.chapterIdx
    local lv = levelEditor_.levelIdx
    local key = ch .. "_" .. lv

    -- 物件列表（可收放）
    local objListHeader = UI.Button {
        width = "100%", height = 24,
        flexDirection = "row", alignItems = "center", gap = 4,
        paddingLeft = 4, paddingRight = 4,
        backgroundColor = {40, 40, 70, 180},
        borderRadius = 4, marginBottom = 4,
        onClick = function()
            levelEditor_.objListExpanded = not levelEditor_.objListExpanded
            M.BuildLevelEditorUI()
        end,
    }
    objListHeader:AddChild(UI.Label {
        text = levelEditor_.objListExpanded and "▼" or "▶",
        fontSize = 11, fontColor = {150, 150, 200, 255}, pointerEvents = "none",
    })
    objListHeader:AddChild(UI.Label {
        text = "物件列表 (" .. #objects .. ")",
        fontSize = 14, fontColor = {180, 200, 255, 255}, pointerEvents = "none",
    })
    panel:AddChild(objListHeader)

    if levelEditor_.objListExpanded then
        for idx, obj in ipairs(objects) do
            local objIdx = idx
            local isSelected = (levelEditor_.selectedObj == idx)
            local objColor = getTitleMenu().GetObjectColor(obj.type)

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
                text = obj.name .. " [" .. string.format("%.1f,%.1f", obj.x + obj.w / 2, (levelEditor_.worldH or 17.5) - obj.y - obj.h / 2) .. "]",
                fontSize = 11, fontColor = {200, 200, 220, 255},
                pointerEvents = "none",
            })
            panel:AddChild(row)
        end
    end

    -- 选中物件的属性编辑
    if levelEditor_.selectedObj and objects[levelEditor_.selectedObj] then
        local obj = objects[levelEditor_.selectedObj]
        local selIdx = levelEditor_.selectedObj

        panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {80,80,120,100}, marginTop = 8, marginBottom = 4 })
        -- 物件名称（可编辑重命名）
        local nameRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, width = "100%", marginBottom = 2 }
        nameRow:AddChild(UI.Label {
            text = "名称:", fontSize = 11, fontColor = {150, 150, 180, 255}, width = 30,
        })
        nameRow:AddChild(UI.TextField {
            value = obj.name,
            fontSize = 12, height = 24, flexGrow = 1,
            backgroundColor = {30, 30, 50, 255},
            borderRadius = 3, borderWidth = 1, borderColor = {120, 100, 60, 200},
            fontColor = {255, 220, 150, 255},
            paddingHorizontal = 4,
            onSubmit = function(self, text)
                if text and #text > 0 and text ~= obj.name then
                    getTitleMenu().PushUndoState()
                    obj.name = text
                    M.BuildLevelEditorUI()
                end
            end,
            onBlur = function(self)
                local text = self:GetValue() or ""
                if #text > 0 and text ~= obj.name then
                    getTitleMenu().PushUndoState()
                    obj.name = text
                    M.BuildLevelEditorUI()
                end
            end,
        })
        panel:AddChild(nameRow)

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
                    getTitleMenu().PushUndoState()
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
                        getTitleMenu().PushUndoState()
                        onApply(num)
                        M.BuildLevelEditorUI()
                    end
                end,
                onBlur = function(self)
                    local txt = self:GetValue() or ""
                    local num = tonumber(txt)
                    if num and math.abs(num - value) > 0.001 then
                        getTitleMenu().PushUndoState()
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
                    getTitleMenu().PushUndoState()
                    onApply(value + step)
                    M.BuildLevelEditorUI()
                end,
            })
            row:AddChild(UI.Label { text = "m", fontSize = 10, fontColor = {120,120,150,255} })
            return row
        end

        -- 显示游戏坐标（中心点，Y-up）
        local worldH = levelEditor_.worldH or 17.5
        local displayX = obj.x + obj.w / 2
        local displayY = worldH - obj.y - obj.h / 2
        panel:AddChild(makeInputRow("X:", displayX, function(v) obj.x = v - obj.w / 2 end))
        panel:AddChild(makeInputRow("Y:", displayY, function(v) obj.y = worldH - v - obj.h / 2 end))
        if obj.collisionShape == "circle" then
            -- 圆形碰撞：只显示半径输入
            local radius = obj.circleRadius or (math.min(obj.w, obj.h) / 2)
            panel:AddChild(makeInputRow("半径:", radius, function(v)
                local r = math.max(0.25, v)
                obj.circleRadius = r
                -- 同步宽高为直径，保持一致
                obj.w = r * 2
                obj.h = r * 2
            end, 0.25))
        else
            panel:AddChild(makeInputRow("W:", obj.w, function(v) obj.w = math.max(0.5, v) end))
            panel:AddChild(makeInputRow("H:", obj.h, function(v) obj.h = math.max(0.5, v) end))
        end
        panel:AddChild(makeInputRow("R°:", obj.rotation or 0, function(v) obj.rotation = v % 360 end, 5))

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
            value = getTitleMenu().RGBtoHex(cr, cg, cb), fontSize = 10, width = 72, height = 22,
            backgroundColor = {30, 25, 55, 255}, fontColor = {220, 220, 255, 255},
            borderRadius = 3, paddingHorizontal = 4,
            onSubmit = function(self, txt)
                local r2, g2, b2 = getTitleMenu().HexToRGB(txt)
                getTitleMenu().ApplyColorToObject(selIdx, r2, g2, b2, ca)
            end,
            onBlur = function(self)
                local txt = self:GetValue() or ""
                if txt ~= getTitleMenu().RGBtoHex(cr, cg, cb) then
                    local r2, g2, b2 = getTitleMenu().HexToRGB(txt)
                    getTitleMenu().ApplyColorToObject(selIdx, r2, g2, b2, ca)
                end
            end,
        })
        -- 重置为白色按钮
        if cr ~= 255 or cg ~= 255 or cb ~= 255 then
            colorPreviewRow:AddChild(UI.Button {
                text = "重置", fontSize = 9, width = 32, height = 22,
                backgroundColor = {60, 50, 90, 220}, borderRadius = 3,
                justifyContent = "center", alignItems = "center", fontColor = {200, 200, 255, 255},
                onClick = function() getTitleMenu().ApplyColorToObject(selIdx, 255, 255, 255, 255) end,
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
                    getTitleMenu().ApplyColorToObject(selIdx, nc[1], nc[2], nc[3], nc[4])
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
                        getTitleMenu().ApplyColorToObject(selIdx, nc[1], nc[2], nc[3], nc[4])
                    end
                end,
                onBlur = function(self)
                    local txt = self:GetValue() or ""
                    local num = tonumber(txt)
                    if num and num ~= value then
                        num = math.max(0, math.min(255, math.floor(num)))
                        local nc = {cr, cg, cb, ca}
                        nc[channel] = num
                        getTitleMenu().ApplyColorToObject(selIdx, nc[1], nc[2], nc[3], nc[4])
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
                    getTitleMenu().ApplyColorToObject(selIdx, nc[1], nc[2], nc[3], nc[4])
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
                    getTitleMenu().ApplyColorToObject(selIdx, pc[1], pc[2], pc[3], 255)
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
                        getTitleMenu().ApplyColorToObject(selIdx, hc[1], hc[2], hc[3], hc[4] or 255)
                    end,
                })
            end
            panel:AddChild(histRow)
        end

        -- ============ 物件贴图图层 ============
        panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {80,80,120,100}, marginTop = 6, marginBottom = 4 })

        -- 初始化 texLayers（兼容旧数据）
        if not obj.texLayers then obj.texLayers = {} end
        if obj.texture and #obj.texLayers == 0 then
            table.insert(obj.texLayers, {
                path = obj.texture, name = obj.textureName or obj.texture,
                opacity = 1.0, scaleW = obj.texScaleW or 1.0, scaleH = obj.texScaleH or 1.0, visible = true,
            })
            obj.texture = nil; obj.textureName = nil; obj.texScaleW = nil; obj.texScaleH = nil
        end

        -- 贴图图层列表（可折叠）
        local objTexExpanded = levelEditor_.objTexLayersExpanded ~= false
        local texLayerTitle = "物件贴图 (" .. #obj.texLayers .. "层)"
        panel:AddChild(UI.Button {
            text = (objTexExpanded and "▼ " or "▶ ") .. texLayerTitle,
            fontSize = 11, width = "100%", height = 22, marginBottom = 2,
            backgroundColor = {50, 45, 80, 180}, borderRadius = 3,
            justifyContent = "center", alignItems = "center",
            fontColor = {200, 160, 255, 255},
            borderWidth = 1, borderColor = {80, 70, 120, 120},
            onClick = function()
                levelEditor_.objTexLayersExpanded = not objTexExpanded
                M.BuildLevelEditorUI()
            end,
        })

        if objTexExpanded and #obj.texLayers > 0 then
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
                    onClick = function() getTitleMenu().PushUndoState(); tLayer.visible = not (tLayer.visible ~= false); M.BuildLevelEditorUI() end,
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
                    onClick = function() getTitleMenu().MoveObjTexLayer(selIdx, tlIdx, -1); M.BuildLevelEditorUI() end,
                })
                -- 下移
                tLayerRow:AddChild(UI.Button {
                    text = "↓", fontSize = 10, width = 16, height = 18,
                    backgroundColor = {50,40,80,180}, fontColor = {180,180,220,255}, borderRadius = 2,
                    onClick = function() getTitleMenu().MoveObjTexLayer(selIdx, tlIdx, 1); M.BuildLevelEditorUI() end,
                })
                -- 删除
                tLayerRow:AddChild(UI.Button {
                    text = "×", fontSize = 11, width = 16, height = 18,
                    backgroundColor = {100,30,30,180}, fontColor = {255,180,180,255}, borderRadius = 2,
                    onClick = function() getTitleMenu().RemoveObjTexLayer(selIdx, tlIdx); M.BuildLevelEditorUI() end,
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
                        onClick = function() getTitleMenu().PushUndoState(); onApply(value - step); M.BuildLevelEditorUI() end,
                    })
                    row:AddChild(UI.TextField {
                        value = string.format(fmt, value), fontSize = 10, width = 50, height = 20,
                        backgroundColor = {30, 25, 55, 255}, fontColor = {220,220,255,255},
                        borderRadius = 3, paddingHorizontal = 4,
                        onSubmit = function(self, txt)
                            local num = tonumber(txt)
                            if num then getTitleMenu().PushUndoState(); onApply(num); M.BuildLevelEditorUI() end
                        end,
                        onBlur = function(self)
                            local txt = self:GetValue() or ""
                            local num = tonumber(txt)
                            if num and num ~= value then getTitleMenu().PushUndoState(); onApply(num); M.BuildLevelEditorUI() end
                        end,
                    })
                    row:AddChild(UI.Button {
                        text = "+", fontSize = 11, width = 18, height = 20,
                        backgroundColor = {50, 40, 80, 220}, borderRadius = 3,
                        justifyContent = "center", alignItems = "center", fontColor = {200,200,255,255},
                        onClick = function() getTitleMenu().PushUndoState(); onApply(value + step); M.BuildLevelEditorUI() end,
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
                        getTitleMenu().PushUndoState()
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
                -- 贴图旋转（度数）
                panel:AddChild(makeTexLayerRow("旋转:", selTLayer.rotation or 0, function(v)
                    selTLayer.rotation = v % 360
                end, 15, "%.0f°"))
                -- 位置偏移X（物件尺寸百分比）
                panel:AddChild(makeTexLayerRow("偏X:", selTLayer.offsetX or 0, function(v)
                    selTLayer.offsetX = v
                end, 0.05, "%.2f"))
                -- 位置偏移Y（物件尺寸百分比）
                panel:AddChild(makeTexLayerRow("偏Y:", selTLayer.offsetY or 0, function(v)
                    selTLayer.offsetY = v
                end, 0.05, "%.2f"))

                -- ====== 贴图图层动态效果 ======
                panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {80,120,180,80}, marginTop = 4, marginBottom = 3 })
                panel:AddChild(UI.Label { text = "图层动态效果", fontSize = 10, fontColor = {80, 180, 255, 220} })
                if not selTLayer.effects then selTLayer.effects = {} end
                local TLEffectRegistry = require("effects.EffectRegistry")
                if #selTLayer.effects > 0 then
                    for tlei = 1, #selTLayer.effects do
                        local tlEff = selTLayer.effects[tlei]
                        local tlEffDef = TLEffectRegistry.Get(tlEff.id)
                        local tlEffName = tlEffDef and tlEffDef.name or tlEff.id
                        local tlEffRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 3, width = "100%", marginBottom = 2 }
                        tlEffRow:AddChild(UI.Label { text = tlEffName, fontSize = 9, fontColor = {160, 210, 255, 220}, flexGrow = 1 })
                        if tlEffDef and tlEffDef.params_schema and #tlEffDef.params_schema > 0 then
                            tlEffRow:AddChild(UI.Button {
                                text = "参数", fontSize = 8,
                                paddingLeft = 5, paddingRight = 5, paddingTop = 1, paddingBottom = 1,
                                backgroundColor = {50, 70, 110, 200}, borderRadius = 2,
                                fontColor = {160, 200, 255, 220},
                                onClick = function()
                                    tlEff._expanded = not tlEff._expanded
                                    M.BuildLevelEditorUI()
                                end,
                            })
                        end
                        tlEffRow:AddChild(UI.Button {
                            text = "×", fontSize = 10,
                            paddingLeft = 4, paddingRight = 4, paddingTop = 1, paddingBottom = 1,
                            backgroundColor = {130, 40, 40, 200}, borderRadius = 2,
                            fontColor = {255, 180, 180, 255},
                            onClick = function()
                                getTitleMenu().PushUndoState()
                                table.remove(selTLayer.effects, tlei)
                                M.BuildLevelEditorUI()
                            end,
                        })
                        panel:AddChild(tlEffRow)
                        -- 参数展开编辑
                        if tlEff._expanded and tlEffDef and tlEffDef.params_schema then
                            if not tlEff.params then tlEff.params = {} end
                            for _, schema in ipairs(tlEffDef.params_schema) do
                                local pKey = schema.key
                                local pVal = tlEff.params[pKey]
                                if pVal == nil then pVal = schema.default end
                                local pRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 3, width = "100%", marginBottom = 1, paddingLeft = 8 }
                                pRow:AddChild(UI.Label { text = schema.label or pKey, fontSize = 8, fontColor = {130, 160, 200, 180}, width = 55 })
                                if schema.type == "texture" then
                                    local currentPath = tostring(pVal)
                                    local shortName = currentPath ~= "" and currentPath:match("[^/]+$") or "(无)"
                                    local isOpen = tlEff._texPickerOpen
                                    pRow:AddChild(UI.Button {
                                        text = (isOpen and "▼" or "▶") .. " " .. shortName, fontSize = 8, flexGrow = 1, height = 18,
                                        backgroundColor = {40, 50, 80, 255}, borderRadius = 2,
                                        borderWidth = 1, borderColor = isOpen and {100, 160, 255, 200} or {80, 120, 200, 180},
                                        fontColor = {180, 210, 255, 255}, paddingLeft = 4,
                                        onClick = function()
                                            tlEff._texPickerOpen = not tlEff._texPickerOpen
                                            M.BuildLevelEditorUI()
                                        end,
                                    })
                                    panel:AddChild(pRow)
                                    if isOpen then
                                        local texList = levelEditor_.customTextures or {}
                                        if schema.cat_filter or (pKey == "path" and tlEff.id == "spritesheet") then
                                            local filtered = {}
                                            local filterCat = schema.cat_filter or "seq"
                                            for _, ta in ipairs(texList) do
                                                local c = ta.cat or "other"
                                                if c == filterCat or c == "sequence" then table.insert(filtered, ta) end
                                            end
                                            texList = filtered
                                        end
                                        local pickerPanel = UI.Panel {
                                            width = "100%", paddingLeft = 12, marginBottom = 3,
                                            maxHeight = 120, overflow = "scroll",
                                            backgroundColor = {25, 30, 42, 200}, borderRadius = 2,
                                            paddingVertical = 2, paddingRight = 3,
                                            borderWidth = 1, borderColor = {60, 80, 120, 150},
                                        }
                                        pickerPanel:AddChild(UI.Button {
                                            text = "✕ 清空", fontSize = 7, width = "100%", height = 16,
                                            paddingLeft = 5, backgroundColor = {80, 40, 40, 200}, borderRadius = 2,
                                            fontColor = {255, 180, 180, 255}, marginBottom = 2,
                                            onClick = function()
                                                getTitleMenu().PushUndoState()
                                                tlEff.params[pKey] = ""
                                                tlEff._texPickerOpen = false
                                                M.BuildLevelEditorUI()
                                            end,
                                        })
                                        for _, texAsset in ipairs(texList) do
                                            local texPath = texAsset.path or ""
                                            local texName = texAsset.name or texPath:match("[^/]+$") or texPath
                                            local isCurrent = (texPath == currentPath)
                                            pickerPanel:AddChild(UI.Button {
                                                text = (isCurrent and "● " or "  ") .. texName, fontSize = 7,
                                                width = "100%", height = 16, paddingLeft = 5,
                                                backgroundColor = isCurrent and {50, 80, 140, 255} or {30, 40, 60, 180},
                                                borderRadius = 2, fontColor = isCurrent and {255, 255, 255, 255} or {160, 190, 220, 220},
                                                onClick = function()
                                                    getTitleMenu().PushUndoState()
                                                    tlEff.params[pKey] = texPath
                                                    tlEff._texPickerOpen = false
                                                    M.BuildLevelEditorUI()
                                                end,
                                            })
                                        end
                                        if #texList == 0 then
                                            pickerPanel:AddChild(UI.Label { text = "无可用贴图", fontSize = 7, fontColor = {120, 120, 140, 180} })
                                        end
                                        panel:AddChild(pickerPanel)
                                    end
                                elseif schema.type == "bool" then
                                    local boolVal = (tonumber(pVal) or 0) ~= 0
                                    pRow:AddChild(UI.Button {
                                        text = boolVal and "ON" or "OFF", fontSize = 8, width = 36, height = 18,
                                        backgroundColor = boolVal and {40, 120, 80, 255} or {80, 40, 40, 255},
                                        borderRadius = 9, fontColor = {255, 255, 255, 255},
                                        onClick = function()
                                            getTitleMenu().PushUndoState()
                                            tlEff.params[pKey] = boolVal and 0 or 1
                                            M.BuildLevelEditorUI()
                                        end,
                                    })
                                    panel:AddChild(pRow)
                                else
                                    pRow:AddChild(UI.TextField {
                                        value = tostring(pVal), fontSize = 8, width = 50, height = 18,
                                        backgroundColor = {30, 35, 55, 255}, fontColor = {190, 210, 255, 255},
                                        borderRadius = 2, paddingHorizontal = 3,
                                        onSubmit = function(self, txt)
                                            getTitleMenu().PushUndoState()
                                            local numVal = tonumber(txt)
                                            if numVal then
                                                if schema.min then numVal = math.max(schema.min, numVal) end
                                                if schema.max then numVal = math.min(schema.max, numVal) end
                                                tlEff.params[pKey] = numVal
                                            end
                                            M.BuildLevelEditorUI()
                                        end,
                                        onBlur = function(self)
                                            local txt = self:GetValue()
                                            local numVal = tonumber(txt)
                                            if numVal then
                                                if schema.min then numVal = math.max(schema.min, numVal) end
                                                if schema.max then numVal = math.min(schema.max, numVal) end
                                                tlEff.params[pKey] = numVal
                                            end
                                        end,
                                    })
                                    if schema.min and schema.max then
                                        pRow:AddChild(UI.Label { text = string.format("[%.1f~%.1f]", schema.min, schema.max), fontSize = 7, fontColor = {90, 110, 140, 130} })
                                    end
                                    panel:AddChild(pRow)
                                end
                            end
                        end
                    end
                else
                    panel:AddChild(UI.Label { text = "无动态效果", fontSize = 8, fontColor = {90, 130, 170, 130}, marginBottom = 1 })
                end
                -- 添加图层效果按钮行
                local tlAllEffIds = TLEffectRegistry.GetIds()
                local tlAddRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 3, width = "100%", marginTop = 2, flexWrap = "wrap" }
                for _, effId in ipairs(tlAllEffIds) do
                    local effDef = TLEffectRegistry.Get(effId)
                    tlAddRow:AddChild(UI.Button {
                        text = "+" .. (effDef and effDef.name or effId), fontSize = 8,
                        paddingLeft = 5, paddingRight = 5, paddingTop = 2, paddingBottom = 2,
                        backgroundColor = {35, 60, 100, 200}, borderRadius = 2,
                        fontColor = {120, 190, 255, 220},
                        onClick = function()
                            getTitleMenu().PushUndoState()
                            local params = {}
                            if effDef and effDef.params_schema then
                                for _, schema in ipairs(effDef.params_schema) do
                                    params[schema.key] = schema.default
                                end
                            end
                            table.insert(selTLayer.effects, { id = effId, params = params })
                            M.BuildLevelEditorUI()
                        end,
                    })
                end
                panel:AddChild(tlAddRow)
            end
        elseif objTexExpanded then
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
                        getTitleMenu().PushUndoState()
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
                        getTitleMenu().PushUndoState()
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

            -- ====== 碰撞体积 ======
            panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {80,80,120,60}, marginTop = 4, marginBottom = 4 })
            local trigHasCol = obj.hasCollision or false
            local colRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 6, width = "100%", marginBottom = 4 }
            colRow:AddChild(UI.Label { text = "物理碰撞", fontSize = 11, fontColor = {180, 180, 200, 255} })
            colRow:AddChild(UI.Button {
                text = trigHasCol and "有碰撞" or "无碰撞", fontSize = 10,
                paddingLeft = 10, paddingRight = 10, paddingTop = 3, paddingBottom = 3,
                backgroundColor = trigHasCol and {120, 180, 120, 220} or {80, 60, 60, 200},
                borderRadius = 3, fontColor = {255, 255, 255, 255},
                onClick = function()
                    getTitleMenu().PushUndoState()
                    obj.hasCollision = not trigHasCol
                    M.BuildLevelEditorUI()
                end,
            })
            panel:AddChild(colRow)

            -- ====== 触发器策略节点 ======
            panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {80,80,120,80}, marginTop = 6, marginBottom = 4 })
            panel:AddChild(UI.Label { text = "触发策略", fontSize = 12, fontColor = {220, 180, 50, 255} })
            local StrategyEditor = require("StrategyEditor")
            panel:AddChild(StrategyEditor.Build(obj, "triggerStrategy", function() M.BuildLevelEditorUI() end, function() getTitleMenu().PushUndoState() end))

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
                        getTitleMenu().PushUndoState()
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
            -- 碰撞体积开关（执行器默认有碰撞）
            local exHasCol = obj.hasCollision
            if exHasCol == nil then exHasCol = true end
            local exColRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 6, width = "100%", marginTop = 4 }
            exColRow:AddChild(UI.Label { text = "物理碰撞", fontSize = 11, fontColor = {180, 180, 200, 255} })
            exColRow:AddChild(UI.Button {
                text = exHasCol and "有碰撞" or "无碰撞", fontSize = 10,
                paddingLeft = 10, paddingRight = 10, paddingTop = 3, paddingBottom = 3,
                backgroundColor = exHasCol and {120, 180, 120, 220} or {80, 60, 60, 200},
                borderRadius = 3, fontColor = {255, 255, 255, 255},
                onClick = function()
                    getTitleMenu().PushUndoState()
                    if obj.hasCollision == nil then
                        obj.hasCollision = false
                    else
                        obj.hasCollision = not obj.hasCollision
                    end
                    M.BuildLevelEditorUI()
                end,
            })
            panel:AddChild(exColRow)

            -- ====== 执行器策略节点 ======
            panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {80,80,120,80}, marginTop = 6, marginBottom = 4 })
            panel:AddChild(UI.Label { text = "执行策略", fontSize = 12, fontColor = {50, 200, 120, 255} })
            local StrategyEditor = require("StrategyEditor")
            panel:AddChild(StrategyEditor.Build(obj, "executorStrategy", function() M.BuildLevelEditorUI() end, function() getTitleMenu().PushUndoState() end))
        end

        -- ============ 碰撞形状 & 摩擦力 ============
        panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {100,80,160,80}, marginTop = 6, marginBottom = 4 })
        panel:AddChild(UI.Label { text = "碰撞属性", fontSize = 12, fontColor = {180, 140, 255, 255} })

        -- 碰撞形状选择
        local COLLISION_SHAPE_OPTIONS = { "box", "circle" }
        local COLLISION_SHAPE_LABELS = { box = "矩形", circle = "圆形" }
        local curShape = obj.collisionShape or "box"
        local shapeRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 6, width = "100%", marginBottom = 4 }
        shapeRow:AddChild(UI.Label { text = "形状", fontSize = 11, fontColor = {160, 160, 200, 255} })
        for _, shapeKey in ipairs(COLLISION_SHAPE_OPTIONS) do
            local isActive = (curShape == shapeKey)
            shapeRow:AddChild(UI.Button {
                text = COLLISION_SHAPE_LABELS[shapeKey], fontSize = 9,
                paddingLeft = 6, paddingRight = 6, paddingTop = 2, paddingBottom = 2,
                backgroundColor = isActive and {120, 100, 200, 230} or {60, 60, 80, 180},
                borderRadius = 3, fontColor = isActive and {255, 255, 255, 255} or {160, 160, 180, 200},
                onClick = function()
                    getTitleMenu().PushUndoState()
                    obj.collisionShape = shapeKey
                    -- 切换到圆形时，同步半径和宽高
                    if shapeKey == "circle" then
                        local r = obj.circleRadius or (math.min(obj.w, obj.h) / 2)
                        obj.circleRadius = r
                        obj.w = r * 2
                        obj.h = r * 2
                    end
                    M.BuildLevelEditorUI()
                end,
            })
        end
        panel:AddChild(shapeRow)

        -- 摩擦力设置
        local frictionRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 6, width = "100%", marginBottom = 4 }
        frictionRow:AddChild(UI.Label { text = "摩擦力", fontSize = 11, fontColor = {160, 160, 200, 255} })
        frictionRow:AddChild(UI.Slider {
            value = (obj.friction or 0.3) * 100,
            min = 0, max = 100, step = 5,
            width = 100, height = 16,
            onChange = function(self, v)
                obj.friction = v / 100
            end,
            onRelease = function()
                getTitleMenu().PushUndoState()
            end,
        })
        frictionRow:AddChild(UI.Label {
            text = string.format("%.2f", obj.friction or 0.3),
            fontSize = 10, fontColor = {200, 200, 220, 200},
        })
        panel:AddChild(frictionRow)

        -- ============ 动态效果配置 ============
        panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {80,120,180,100}, marginTop = 6, marginBottom = 4 })
        panel:AddChild(UI.Label { text = "动态效果", fontSize = 12, fontColor = {80, 180, 255, 255} })

        -- 已配置的效果列表
        if not obj.effects then obj.effects = {} end
        local EffectRegistry = require("effects.EffectRegistry")
        if #obj.effects > 0 then
            for ei = 1, #obj.effects do
                local eff = obj.effects[ei]
                local effDef = EffectRegistry.Get(eff.id)
                local effName = effDef and effDef.name or eff.id
                local effRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, width = "100%", marginBottom = 3 }
                effRow:AddChild(UI.Label { text = effName, fontSize = 10, fontColor = {180, 220, 255, 255}, flexGrow = 1 })
                -- 参数编辑按钮
                if effDef and effDef.params_schema and #effDef.params_schema > 0 then
                    effRow:AddChild(UI.Button {
                        text = "参数", fontSize = 9,
                        paddingLeft = 6, paddingRight = 6, paddingTop = 2, paddingBottom = 2,
                        backgroundColor = {60, 80, 120, 200}, borderRadius = 3,
                        fontColor = {180, 220, 255, 255},
                        onClick = function()
                            -- 切换展开/收起
                            eff._expanded = not eff._expanded
                            M.BuildLevelEditorUI()
                        end,
                    })
                end
                -- 删除效果按钮
                effRow:AddChild(UI.Button {
                    text = "×", fontSize = 11,
                    paddingLeft = 5, paddingRight = 5, paddingTop = 1, paddingBottom = 1,
                    backgroundColor = {140, 50, 50, 200}, borderRadius = 3,
                    fontColor = {255, 200, 200, 255},
                    onClick = function()
                        getTitleMenu().PushUndoState()
                        table.remove(obj.effects, ei)
                        M.BuildLevelEditorUI()
                    end,
                })
                panel:AddChild(effRow)

                -- 展开参数编辑
                if eff._expanded and effDef and effDef.params_schema then
                    if not eff.params then eff.params = {} end
                    for _, schema in ipairs(effDef.params_schema) do
                        local pKey = schema.key
                        local pVal = eff.params[pKey]
                        if pVal == nil then pVal = schema.default end
                        local paramRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, width = "100%", marginBottom = 2, paddingLeft = 8 }
                        paramRow:AddChild(UI.Label { text = schema.label or pKey, fontSize = 9, fontColor = {150, 180, 220, 200}, width = 60 })

                        if schema.type == "texture" then
                            -- 贴图选择器：从 customTextures 列表中选择（可收放）
                            local currentPath = tostring(pVal)
                            local shortName = currentPath ~= "" and currentPath:match("[^/]+$") or "(无)"
                            local isOpen = eff._texPickerOpen
                            local toggleIcon = isOpen and "▼" or "▶"
                            paramRow:AddChild(UI.Button {
                                text = toggleIcon .. " " .. shortName, fontSize = 8, flexGrow = 1, height = 20,
                                backgroundColor = {40, 50, 80, 255}, borderRadius = 2,
                                borderWidth = 1, borderColor = isOpen and {100, 160, 255, 200} or {80, 120, 200, 180},
                                fontColor = {180, 210, 255, 255}, paddingLeft = 4,
                                onClick = function()
                                    -- 展开/收起贴图选择列表
                                    eff._texPickerOpen = not eff._texPickerOpen
                                    M.BuildLevelEditorUI()
                                end,
                            })
                            panel:AddChild(paramRow)
                            -- 贴图选择列表（展开时显示，限高可滚动）
                            if isOpen then
                                local texList = levelEditor_.customTextures or {}
                                -- 序列帧图片选择器只显示 seq 分类的图片
                                if schema.type == "texture" and (schema.cat_filter or (pKey == "path" and eff.id == "spritesheet")) then
                                    local filtered = {}
                                    local filterCat = schema.cat_filter or "seq"
                                    for _, ta in ipairs(texList) do
                                        local c = ta.cat or "other"
                                        if c == filterCat or c == "sequence" then
                                            table.insert(filtered, ta)
                                        end
                                    end
                                    texList = filtered
                                end
                                local pickerPanel = UI.Panel {
                                    width = "100%", paddingLeft = 12, marginBottom = 4,
                                    maxHeight = 150, overflow = "scroll",
                                    backgroundColor = {25, 30, 42, 200}, borderRadius = 3,
                                    paddingVertical = 3, paddingRight = 4,
                                    borderWidth = 1, borderColor = {60, 80, 120, 150},
                                }
                                -- 清空选项
                                pickerPanel:AddChild(UI.Button {
                                    text = "✕ 清空选择", fontSize = 8,
                                    width = "100%", height = 18,
                                    paddingLeft = 6, paddingTop = 2, paddingBottom = 2,
                                    backgroundColor = {80, 40, 40, 200}, borderRadius = 2,
                                    fontColor = {255, 180, 180, 255}, marginBottom = 3,
                                    onClick = function()
                                        getTitleMenu().PushUndoState()
                                        eff.params[pKey] = ""
                                        eff._texPickerOpen = false
                                        M.BuildLevelEditorUI()
                                    end,
                                })
                                -- customTextures 元素结构: { path=..., name=..., cat=... }
                                for _, texAsset in ipairs(texList) do
                                    local texPath = texAsset.path or ""
                                    local texName = texAsset.name or texPath:match("[^/]+$") or texPath
                                    local isCurrent = (texPath == currentPath)
                                    pickerPanel:AddChild(UI.Button {
                                        text = (isCurrent and "● " or "  ") .. texName, fontSize = 8,
                                        width = "100%", height = 18,
                                        paddingLeft = 6, paddingTop = 1, paddingBottom = 1,
                                        backgroundColor = isCurrent and {50, 80, 140, 255} or {30, 40, 60, 180},
                                        borderRadius = 2,
                                        fontColor = isCurrent and {255, 255, 255, 255} or {160, 190, 220, 220},
                                        onClick = function()
                                            getTitleMenu().PushUndoState()
                                            eff.params[pKey] = texPath
                                            eff._texPickerOpen = false
                                            M.BuildLevelEditorUI()
                                        end,
                                    })
                                end
                                if #texList == 0 then
                                    pickerPanel:AddChild(UI.Label { text = "无可用贴图（请先在贴图工具中导入）", fontSize = 8, fontColor = {120, 120, 140, 180} })
                                end
                                -- 收起按钮（列表底部）
                                pickerPanel:AddChild(UI.Button {
                                    text = "▲ 收起", fontSize = 8,
                                    width = "100%", height = 16, marginTop = 3,
                                    backgroundColor = {50, 60, 80, 200}, borderRadius = 2,
                                    fontColor = {140, 170, 220, 200}, justifyContent = "center", alignItems = "center",
                                    onClick = function()
                                        eff._texPickerOpen = false
                                        M.BuildLevelEditorUI()
                                    end,
                                })
                                panel:AddChild(pickerPanel)
                            end
                        elseif schema.type == "bool" then
                            -- 布尔开关
                            local boolVal = (tonumber(pVal) or 0) ~= 0
                            paramRow:AddChild(UI.Button {
                                text = boolVal and "ON" or "OFF", fontSize = 9, width = 40, height = 20,
                                backgroundColor = boolVal and {40, 120, 80, 255} or {80, 40, 40, 255},
                                borderRadius = 10, borderWidth = 1,
                                borderColor = boolVal and {80, 200, 140, 200} or {160, 80, 80, 200},
                                fontColor = {255, 255, 255, 255},
                                onClick = function()
                                    getTitleMenu().PushUndoState()
                                    eff.params[pKey] = boolVal and 0 or 1
                                    M.BuildLevelEditorUI()
                                end,
                            })
                            panel:AddChild(paramRow)
                        else
                            -- 默认数值输入
                            paramRow:AddChild(UI.TextField {
                                value = tostring(pVal), fontSize = 9, width = 60, height = 20,
                                backgroundColor = {30, 40, 60, 255}, fontColor = {200, 220, 255, 255},
                                borderRadius = 2, borderWidth = 1, borderColor = {60, 100, 160, 150},
                                paddingHorizontal = 4,
                                onSubmit = function(self, txt)
                                    getTitleMenu().PushUndoState()
                                    local numVal = tonumber(txt)
                                    if numVal then
                                        if schema.min then numVal = math.max(schema.min, numVal) end
                                        if schema.max then numVal = math.min(schema.max, numVal) end
                                        eff.params[pKey] = numVal
                                    end
                                    M.BuildLevelEditorUI()
                                end,
                                onBlur = function(self)
                                    local txt = self:GetValue()
                                    local numVal = tonumber(txt)
                                    if numVal then
                                        if schema.min then numVal = math.max(schema.min, numVal) end
                                        if schema.max then numVal = math.min(schema.max, numVal) end
                                        eff.params[pKey] = numVal
                                    end
                                end,
                            })
                            if schema.min and schema.max then
                                paramRow:AddChild(UI.Label { text = string.format("[%.1f~%.1f]", schema.min, schema.max), fontSize = 8, fontColor = {100, 130, 160, 150} })
                            end
                            panel:AddChild(paramRow)
                        end
                    end
                end
            end
        else
            panel:AddChild(UI.Label { text = "无动态效果", fontSize = 9, fontColor = {100, 140, 180, 150}, marginBottom = 2 })
        end

        -- 添加效果下拉按钮
        local allEffectIds = EffectRegistry.GetIds()
        local addEffRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, width = "100%", marginTop = 3, flexWrap = "wrap" }
        for _, effId in ipairs(allEffectIds) do
            local effDef = EffectRegistry.Get(effId)
            addEffRow:AddChild(UI.Button {
                text = "+" .. (effDef and effDef.name or effId), fontSize = 9,
                paddingLeft = 6, paddingRight = 6, paddingTop = 3, paddingBottom = 3,
                backgroundColor = {40, 70, 110, 200}, borderRadius = 3,
                fontColor = {140, 200, 255, 255},
                onClick = function()
                    getTitleMenu().PushUndoState()
                    -- 初始化 params 为默认值
                    local params = {}
                    if effDef and effDef.params_schema then
                        for _, schema in ipairs(effDef.params_schema) do
                            params[schema.key] = schema.default
                        end
                    end
                    table.insert(obj.effects, { id = effId, params = params })
                    M.BuildLevelEditorUI()
                end,
            })
        end
        panel:AddChild(addEffRow)

        -- 删除按钮
        panel:AddChild(UI.Button {
            text = "删除此物件", fontSize = 12, marginTop = 8,
            width = "100%", height = 26,
            backgroundColor = {160, 50, 50, 220}, borderRadius = 4,
            justifyContent = "center", alignItems = "center",
            fontColor = {255,255,255,255},
            onClick = function()
                getTitleMenu().PushUndoState()
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
        -- 选中编辑按钮
        local isCamSel = levelEditor_.camBoundsSelected
        headerRow:AddChild(UI.Button {
            text = isCamSel and "🔓选中" or "🔒未选", fontSize = 10, height = 18,
            paddingHorizontal = 4,
            backgroundColor = isCamSel and {120, 100, 30, 220} or {50, 50, 40, 180},
            borderRadius = 3, justifyContent = "center", alignItems = "center",
            fontColor = isCamSel and {255, 240, 100, 255} or {150, 140, 100, 200},
            borderWidth = isCamSel and 1 or 0, borderColor = {255, 220, 80, 180},
            onClick = function()
                levelEditor_.camBoundsSelected = not levelEditor_.camBoundsSelected
                -- 选中镜头框时取消其他选中
                if levelEditor_.camBoundsSelected then
                    levelEditor_.selectedObj = nil
                    levelEditor_.selectedBgLayer = nil
                end
                M.BuildLevelEditorUI()
            end,
        })
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
            if isCamSel then
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
            else
                panel:AddChild(UI.Label { text = "点击「选中」按钮后可编辑", fontSize = 9, fontColor = {160, 150, 100, 150}, marginTop = 2 })
            end
        end
    end

    -- 角色渲染倍率调节
    do
        panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {80,160,120,120}, marginTop = 8, marginBottom = 4 })
        local scaleVal = levelEditor_.playerRenderScale or 1.0
        local scaleRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 2, width = "100%", marginBottom = 2 }
        scaleRow:AddChild(UI.Label { text = "角色倍率:", fontSize = 10, fontColor = {140, 220, 180, 255}, width = 58 })
        scaleRow:AddChild(UI.Button {
            text = "-", fontSize = 11, width = 18, height = 20,
            backgroundColor = {30, 60, 40, 220}, borderRadius = 3,
            justifyContent = "center", alignItems = "center", fontColor = {180, 255, 200, 255},
            onClick = function()
                levelEditor_.playerRenderScale = math.max(0.1, (levelEditor_.playerRenderScale or 1.0) - 0.05)
                M.BuildLevelEditorUI()
            end,
        })
        scaleRow:AddChild(UI.TextField {
            value = string.format("%.2f", scaleVal), fontSize = 10, width = 50, height = 20,
            backgroundColor = {20, 40, 30, 255}, fontColor = {200, 255, 220, 255},
            borderRadius = 3, paddingHorizontal = 4,
            onSubmit = function(self, txt)
                local num = tonumber(txt)
                if num then levelEditor_.playerRenderScale = math.max(0.1, num); M.BuildLevelEditorUI() end
            end,
            onBlur = function(self)
                local txt = self:GetValue() or ""
                local num = tonumber(txt)
                if num and math.abs(num - scaleVal) > 0.001 then
                    levelEditor_.playerRenderScale = math.max(0.1, num); M.BuildLevelEditorUI()
                end
            end,
        })
        scaleRow:AddChild(UI.Button {
            text = "+", fontSize = 11, width = 18, height = 20,
            backgroundColor = {30, 60, 40, 220}, borderRadius = 3,
            justifyContent = "center", alignItems = "center", fontColor = {180, 255, 200, 255},
            onClick = function()
                levelEditor_.playerRenderScale = (levelEditor_.playerRenderScale or 1.0) + 0.05
                M.BuildLevelEditorUI()
            end,
        })
        panel:AddChild(scaleRow)
    end

    -- 角色垂直偏移调节（offsetY）
    do
        local oyVal = levelEditor_.playerOffsetY or 0.0
        local oyRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 2, width = "100%", marginBottom = 2 }
        oyRow:AddChild(UI.Label { text = "垂直偏移:", fontSize = 10, fontColor = {140, 220, 180, 255}, width = 58 })
        oyRow:AddChild(UI.Button {
            text = "-", fontSize = 11, width = 18, height = 20,
            backgroundColor = {30, 60, 40, 220}, borderRadius = 3,
            justifyContent = "center", alignItems = "center", fontColor = {180, 255, 200, 255},
            onClick = function()
                levelEditor_.playerOffsetY = (levelEditor_.playerOffsetY or 0.0) - 0.02
                M.BuildLevelEditorUI()
            end,
        })
        oyRow:AddChild(UI.TextField {
            value = string.format("%.2f", oyVal), fontSize = 10, width = 50, height = 20,
            backgroundColor = {20, 40, 30, 255}, fontColor = {200, 255, 220, 255},
            borderRadius = 3, paddingHorizontal = 4,
            onSubmit = function(self, txt)
                local num = tonumber(txt)
                if num then levelEditor_.playerOffsetY = num; M.BuildLevelEditorUI() end
            end,
            onBlur = function(self)
                local txt = self:GetValue() or ""
                local num = tonumber(txt)
                if num and math.abs(num - oyVal) > 0.001 then
                    levelEditor_.playerOffsetY = num; M.BuildLevelEditorUI()
                end
            end,
        })
        oyRow:AddChild(UI.Button {
            text = "+", fontSize = 11, width = 18, height = 20,
            backgroundColor = {30, 60, 40, 220}, borderRadius = 3,
            justifyContent = "center", alignItems = "center", fontColor = {180, 255, 200, 255},
            onClick = function()
                levelEditor_.playerOffsetY = (levelEditor_.playerOffsetY or 0.0) + 0.02
                M.BuildLevelEditorUI()
            end,
        })
        panel:AddChild(oyRow)
    end

    -- 玩家初始位置设置
    do
        local hasStart = (levelEditor_.playerStartX ~= nil and levelEditor_.playerStartY ~= nil)
        local startRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 2, width = "100%", marginBottom = 2 }
        startRow:AddChild(UI.Label { text = "出生点:", fontSize = 10, fontColor = {140, 220, 180, 255}, width = 58 })
        if hasStart then
            -- 显示游戏坐标（Y-up）
            local wH = levelEditor_.worldH or 17.5
            local displayStartY = wH - levelEditor_.playerStartY
            startRow:AddChild(UI.TextField {
                value = string.format("%.1f", levelEditor_.playerStartX), fontSize = 10, width = 38, height = 20,
                backgroundColor = {20, 40, 30, 255}, fontColor = {200, 255, 220, 255},
                borderRadius = 3, paddingHorizontal = 2,
                onSubmit = function(self, txt)
                    local num = tonumber(txt)
                    if num then
                        getTitleMenu().PushUndoState()
                        levelEditor_.playerStartX = num
                        M.BuildLevelEditorUI()
                    end
                end,
                onBlur = function(self)
                    local txt = self:GetValue() or ""
                    local num = tonumber(txt)
                    if num and math.abs(num - (levelEditor_.playerStartX or 0)) > 0.01 then
                        getTitleMenu().PushUndoState()
                        levelEditor_.playerStartX = num
                        M.BuildLevelEditorUI()
                    end
                end,
            })
            startRow:AddChild(UI.Label { text = ",", fontSize = 10, fontColor = {140, 220, 180, 255} })
            startRow:AddChild(UI.TextField {
                value = string.format("%.1f", displayStartY), fontSize = 10, width = 38, height = 20,
                backgroundColor = {20, 40, 30, 255}, fontColor = {200, 255, 220, 255},
                borderRadius = 3, paddingHorizontal = 2,
                onSubmit = function(self, txt)
                    local num = tonumber(txt)
                    if num then
                        getTitleMenu().PushUndoState()
                        levelEditor_.playerStartY = wH - num
                        M.BuildLevelEditorUI()
                    end
                end,
                onBlur = function(self)
                    local txt = self:GetValue() or ""
                    local num = tonumber(txt)
                    if num and math.abs(num - displayStartY) > 0.01 then
                        getTitleMenu().PushUndoState()
                        levelEditor_.playerStartY = wH - num
                        M.BuildLevelEditorUI()
                    end
                end,
            })
            startRow:AddChild(UI.Button {
                text = "清除", fontSize = 9, width = 30, height = 20,
                backgroundColor = {80, 30, 30, 220}, borderRadius = 3,
                justifyContent = "center", alignItems = "center", fontColor = {255, 180, 180, 255},
                onClick = function()
                    getTitleMenu().PushUndoState()
                    levelEditor_.playerStartX = nil
                    levelEditor_.playerStartY = nil
                    M.BuildLevelEditorUI()
                end,
            })
        else
            startRow:AddChild(UI.Label { text = "自动", fontSize = 10, fontColor = {180, 180, 180, 200}, width = 30 })
            startRow:AddChild(UI.Button {
                text = "设置", fontSize = 9, width = 30, height = 20,
                backgroundColor = {30, 60, 40, 220}, borderRadius = 3,
                justifyContent = "center", alignItems = "center", fontColor = {180, 255, 200, 255},
                onClick = function()
                    getTitleMenu().PushUndoState()
                    -- 默认放在世界中心
                    levelEditor_.playerStartX = levelEditor_.worldW / 2
                    levelEditor_.playerStartY = levelEditor_.worldH / 2
                    M.BuildLevelEditorUI()
                end,
            })
        end
        panel:AddChild(startRow)
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
            local bgExpanded = levelEditor_.bgLayersExpanded ~= false
            panel:AddChild(UI.Button {
                text = (bgExpanded and "▼ " or "▶ ") .. "背景图层 (" .. #bgLayers .. "层)",
                fontSize = 11, width = "100%", height = 22, marginTop = 4, marginBottom = 2,
                backgroundColor = {50, 45, 80, 180}, borderRadius = 3,
                justifyContent = "center", alignItems = "center",
                fontColor = {180, 160, 220, 255},
                borderWidth = 1, borderColor = {80, 70, 120, 120},
                onClick = function()
                    levelEditor_.bgLayersExpanded = not bgExpanded
                    M.BuildLevelEditorUI()
                end,
            })
            if not bgExpanded then goto bg_layers_end end
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
                -- 锁定
                layerRow:AddChild(UI.Button {
                    text = layer.locked and "🔒" or "🔓", fontSize = 9, width = 18, height = 18,
                    backgroundColor = {0,0,0,0}, fontColor = layer.locked and {255,180,80,255} or {120,120,140,200},
                    onClick = function() layer.locked = not layer.locked; M.BuildLevelEditorUI() end,
                })
                -- 名称（点击选中）
                layerRow:AddChild(UI.Button {
                    text = li .. "." .. (layer.name or "图层"), fontSize = 9, height = 18, flexGrow = 1,
                    backgroundColor = {0,0,0,0},
                    fontColor = layer.locked and {140,130,170,180} or {200,190,240,255},
                    onClick = function()
                        levelEditor_.selectedBgLayer = li
                        levelEditor_.camBoundsSelected = false
                        M.BuildLevelEditorUI()
                    end,
                })
                -- 上移
                layerRow:AddChild(UI.Button {
                    text = "↑", fontSize = 10, width = 16, height = 18,
                    backgroundColor = {50,40,80,180}, fontColor = {180,180,220,255}, borderRadius = 2,
                    onClick = function() getTitleMenu().MoveBgLayer(li, -1); M.BuildLevelEditorUI() end,
                })
                -- 下移
                layerRow:AddChild(UI.Button {
                    text = "↓", fontSize = 10, width = 16, height = 18,
                    backgroundColor = {50,40,80,180}, fontColor = {180,180,220,255}, borderRadius = 2,
                    onClick = function() getTitleMenu().MoveBgLayer(li, 1); M.BuildLevelEditorUI() end,
                })
                -- 删除
                layerRow:AddChild(UI.Button {
                    text = "×", fontSize = 11, width = 16, height = 18,
                    backgroundColor = {100,30,30,180}, fontColor = {255,180,180,255}, borderRadius = 2,
                    onClick = function() getTitleMenu().RemoveBgLayer(li); M.BuildLevelEditorUI() end,
                })
                panel:AddChild(layerRow)
            end

            -- 选中图层属性编辑
            local selLayer = levelEditor_.selectedBgLayer and bgLayers[levelEditor_.selectedBgLayer]
            if selLayer then
                local layerLocked = selLayer.locked or false
                local lockLabel = layerLocked and " [已锁定]" or ""
                panel:AddChild(UI.Label { text = "图层属性: " .. (selLayer.name or "") .. lockLabel, fontSize = 10, fontColor = layerLocked and {200,150,100,200} or {160,150,200,255}, marginTop = 4 })
                if layerLocked then
                    panel:AddChild(UI.Label { text = "图层已锁定，解锁后可编辑", fontSize = 9, fontColor = {180,140,80,150}, marginTop = 2 })
                end
                if not layerLocked then
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
                        onClick = function() getTitleMenu().PushUndoState(); onApply(value - step); M.BuildLevelEditorUI() end,
                    })
                    row:AddChild(UI.TextField {
                        value = displayVal, fontSize = 10, width = 56, height = 20,
                        backgroundColor = {30, 25, 55, 255}, fontColor = {220,220,255,255},
                        borderRadius = 3, paddingHorizontal = 4,
                        onSubmit = function(self, txt)
                            local num = tonumber(txt)
                            if num then getTitleMenu().PushUndoState(); onApply(num); M.BuildLevelEditorUI() end
                        end,
                        onBlur = function(self)
                            local txt = self:GetValue() or ""
                            local num = tonumber(txt)
                            if num and num ~= value then getTitleMenu().PushUndoState(); onApply(num); M.BuildLevelEditorUI() end
                        end,
                    })
                    row:AddChild(UI.Button {
                        text = "+", fontSize = 11, width = 18, height = 20,
                        backgroundColor = {50, 40, 80, 220}, borderRadius = 3,
                        justifyContent = "center", alignItems = "center", fontColor = {200,200,255,255},
                        onClick = function() getTitleMenu().PushUndoState(); onApply(value + step); M.BuildLevelEditorUI() end,
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
                        getTitleMenu().PushUndoState()
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
                panel:AddChild(makeLayerRow("景深:", selLayer.depth or 0, function(v) selLayer.depth = math.max(-0.9, v) end, 0.02, "%.2f"))

                -- ====== 背景图层动态效果 ======
                panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {80,120,180,80}, marginTop = 4, marginBottom = 3 })
                panel:AddChild(UI.Label { text = "动态效果", fontSize = 10, fontColor = {80, 180, 255, 220} })
                if not selLayer.effects then selLayer.effects = {} end
                local BgEffectRegistry = require("effects.EffectRegistry")
                if #selLayer.effects > 0 then
                    for bei = 1, #selLayer.effects do
                        local bEff = selLayer.effects[bei]
                        local bEffDef = BgEffectRegistry.Get(bEff.id)
                        local bEffName = bEffDef and bEffDef.name or bEff.id
                        local bEffRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 3, width = "100%", marginBottom = 2 }
                        bEffRow:AddChild(UI.Label { text = bEffName, fontSize = 9, fontColor = {160, 210, 255, 220}, flexGrow = 1 })
                        if bEffDef and bEffDef.params_schema and #bEffDef.params_schema > 0 then
                            bEffRow:AddChild(UI.Button {
                                text = "参数", fontSize = 8,
                                paddingLeft = 5, paddingRight = 5, paddingTop = 1, paddingBottom = 1,
                                backgroundColor = {50, 70, 110, 200}, borderRadius = 2,
                                fontColor = {160, 200, 255, 220},
                                onClick = function()
                                    bEff._expanded = not bEff._expanded
                                    M.BuildLevelEditorUI()
                                end,
                            })
                        end
                        bEffRow:AddChild(UI.Button {
                            text = "×", fontSize = 10,
                            paddingLeft = 4, paddingRight = 4, paddingTop = 1, paddingBottom = 1,
                            backgroundColor = {130, 40, 40, 200}, borderRadius = 2,
                            fontColor = {255, 180, 180, 255},
                            onClick = function()
                                getTitleMenu().PushUndoState()
                                table.remove(selLayer.effects, bei)
                                M.BuildLevelEditorUI()
                            end,
                        })
                        panel:AddChild(bEffRow)
                        -- 参数展开编辑
                        if bEff._expanded and bEffDef and bEffDef.params_schema then
                            if not bEff.params then bEff.params = {} end
                            for _, schema in ipairs(bEffDef.params_schema) do
                                local pKey = schema.key
                                local pVal = bEff.params[pKey]
                                if pVal == nil then pVal = schema.default end
                                local pRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 3, width = "100%", marginBottom = 1, paddingLeft = 8 }
                                pRow:AddChild(UI.Label { text = schema.label or pKey, fontSize = 8, fontColor = {130, 160, 200, 180}, width = 55 })
                                pRow:AddChild(UI.TextField {
                                    value = tostring(pVal), fontSize = 8, width = 50, height = 18,
                                    backgroundColor = {30, 35, 55, 255}, fontColor = {190, 210, 255, 255},
                                    borderRadius = 2, paddingHorizontal = 3,
                                    onSubmit = function(self, txt)
                                        getTitleMenu().PushUndoState()
                                        local numVal = tonumber(txt)
                                        if numVal then
                                            if schema.min then numVal = math.max(schema.min, numVal) end
                                            if schema.max then numVal = math.min(schema.max, numVal) end
                                            bEff.params[pKey] = numVal
                                        end
                                        M.BuildLevelEditorUI()
                                    end,
                                    onBlur = function(self)
                                        local txt = self:GetValue()
                                        local numVal = tonumber(txt)
                                        if numVal then
                                            if schema.min then numVal = math.max(schema.min, numVal) end
                                            if schema.max then numVal = math.min(schema.max, numVal) end
                                            bEff.params[pKey] = numVal
                                        end
                                    end,
                                })
                                if schema.min and schema.max then
                                    pRow:AddChild(UI.Label { text = string.format("[%.1f~%.1f]", schema.min, schema.max), fontSize = 7, fontColor = {90, 110, 140, 130} })
                                end
                                panel:AddChild(pRow)
                            end
                        end
                    end
                else
                    panel:AddChild(UI.Label { text = "无动态效果", fontSize = 8, fontColor = {90, 130, 170, 130}, marginBottom = 1 })
                end
                -- 添加效果按钮行
                local bgAllEffIds = BgEffectRegistry.GetIds()
                local bgAddRow = UI.Panel { flexDirection = "row", alignItems = "center", gap = 3, width = "100%", marginTop = 2, flexWrap = "wrap" }
                for _, effId in ipairs(bgAllEffIds) do
                    local effDef = BgEffectRegistry.Get(effId)
                    bgAddRow:AddChild(UI.Button {
                        text = "+" .. (effDef and effDef.name or effId), fontSize = 8,
                        paddingLeft = 5, paddingRight = 5, paddingTop = 2, paddingBottom = 2,
                        backgroundColor = {35, 60, 100, 200}, borderRadius = 2,
                        fontColor = {120, 190, 255, 220},
                        onClick = function()
                            getTitleMenu().PushUndoState()
                            local params = {}
                            if effDef and effDef.params_schema then
                                for _, schema in ipairs(effDef.params_schema) do
                                    params[schema.key] = schema.default
                                end
                            end
                            table.insert(selLayer.effects, { id = effId, params = params })
                            M.BuildLevelEditorUI()
                        end,
                    })
                end
                panel:AddChild(bgAddRow)

                end -- if not layerLocked
            end
            ::bg_layers_end::
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

        -- 已导入素材列表（按分类展开显示）
        if #levelEditor_.customTextures > 0 then
            panel:AddChild(UI.Label { text = "已导入素材 (点击应用):", fontSize = 10, fontColor = {150,140,180,255}, marginTop = 6 })
            -- 按分类分组
            local catGroups = { bg = {}, tile = {}, seq = {}, interact = {}, solid = {}, sign = {}, dlg_portrait = {}, dlg_bg = {}, dlg_whole = {}, other = {} }
            for tidx, asset in ipairs(levelEditor_.customTextures) do
                local cat = asset.cat or "other"
                if cat == "sequence" or cat == "seq" then cat = "seq" end
                if not catGroups[cat] then cat = "other" end
                table.insert(catGroups[cat], { idx = tidx, asset = asset })
            end
            local catOrder = {
                { key = "bg", label = "背景", color = {100, 180, 100, 255} },
                { key = "tile", label = "物件/地面", color = {180, 140, 80, 255} },
                { key = "sign", label = "标志", color = {220, 180, 60, 255} },
                { key = "dlg_portrait", label = "对话框/立绘", color = {140, 180, 255, 255} },
                { key = "dlg_bg", label = "对话框/底图", color = {180, 140, 220, 255} },
                { key = "dlg_whole", label = "对话框/整体", color = {160, 200, 180, 255} },
                { key = "seq", label = "序列帧", color = {100, 160, 220, 255} },
                { key = "interact", label = "交互", color = {220, 120, 180, 255} },
                { key = "solid", label = "纯色", color = {200, 200, 200, 255} },
                { key = "other", label = "其他", color = {160, 140, 180, 255} },
            }
            for _, catInfo in ipairs(catOrder) do
                local items = catGroups[catInfo.key]
                if #items > 0 then
                    local expanded = levelEditor_.texCatExpanded[catInfo.key] ~= false
                    -- 分类标题行（可折叠）
                    panel:AddChild(UI.Button {
                        text = (expanded and "▼ " or "▶ ") .. catInfo.label .. " (" .. #items .. ")",
                        fontSize = 10, width = "100%", height = 22, marginTop = 4, marginBottom = 2,
                        backgroundColor = {50, 45, 80, 180}, borderRadius = 3,
                        justifyContent = "center", alignItems = "center",
                        fontColor = catInfo.color,
                        borderWidth = 1, borderColor = {80, 70, 120, 120},
                        onClick = function()
                            levelEditor_.texCatExpanded[catInfo.key] = not expanded
                            M.BuildLevelEditorUI()
                        end,
                    })
                    -- 展开时显示素材
                    if expanded then
                        for _, item in ipairs(items) do
                            local assetPath = item.asset.path
                            local assetName = item.asset.name
                            local assetIdx = item.idx
                            panel:AddChild(UI.Panel {
                                width = "100%", height = 26, marginBottom = 1,
                                flexDirection = "row", alignItems = "center",
                                backgroundColor = {40, 35, 70, 200}, borderRadius = 3,
                                borderWidth = 1, borderColor = {80, 65, 130, 120},
                                children = {
                                    -- 素材名称按钮（点击应用）
                                    UI.Button {
                                        text = "  " .. assetName, fontSize = 11,
                                        flexGrow = 1, height = "100%",
                                        backgroundColor = {0, 0, 0, 0}, borderRadius = 0,
                                        paddingLeft = 8,
                                        fontColor = {200, 180, 255, 255},
                                        onClick = function()
                                            local target = levelEditor_.textureBrowseTarget
                                            if target == "bg" then
                                                getTitleMenu().AddBgLayer(assetPath, assetName)
                                            elseif type(target) == "number" and objects[target] then
                                                getTitleMenu().AddObjTexLayer(target, assetPath, assetName)
                                            end
                                            M.BuildLevelEditorUI()
                                        end,
                                    },
                                    -- 删除按钮
                                    UI.Button {
                                        text = "×", fontSize = 14, width = 24, height = "100%",
                                        backgroundColor = {0, 0, 0, 0}, borderRadius = 0,
                                        fontColor = {200, 100, 100, 200},
                                        justifyContent = "center", alignItems = "center",
                                        onClick = function()
                                            -- 从列表中移除该素材
                                            table.remove(levelEditor_.customTextures, assetIdx)
                                            print("[Editor] 已删除素材: " .. assetName)
                                            M.BuildLevelEditorUI()
                                        end,
                                    },
                                },
                            })
                        end
                    end
                end
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

    -- ================================================================
    -- 预制体系统 UI
    -- ================================================================

    -- 「保存为预制体」按钮 —— 选中对象时显示
    if levelEditor_.selectedObj and objects[levelEditor_.selectedObj] then
        panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {60,80,80,100}, marginTop = 8 })
        panel:AddChild(UI.Button {
            width = "100%", paddingTop = 8, paddingBottom = 8,
            backgroundColor = {40, 150, 130, 220}, borderRadius = 6,
            justifyContent = "center", alignItems = "center",
            children = { UI.Label { text = "保存为预制体", fontSize = 12, fontColor = {255,255,255,255} } },
            onClick = function()
                -- 收集选中对象（当前仅单选，用数组包裹）
                local indices = { levelEditor_.selectedObj }
                -- 如果有多选，合并
                if levelEditor_.multiSelectActive and next(levelEditor_.multiSelect) then
                    indices = {}
                    for idx, _ in pairs(levelEditor_.multiSelect) do
                        indices[#indices + 1] = idx
                    end
                    table.sort(indices)
                end
                -- 弹出命名输入
                levelEditor_.prefabSaveIndices = indices
                levelEditor_.prefabSaveNaming = true
                levelEditor_.prefabSaveName = "prefab_" .. os.time()
                M.BuildLevelEditorUI()
            end,
        })
    end

    -- 预制体命名弹窗（保存流程）
    if levelEditor_.prefabSaveNaming then
        panel:AddChild(UI.Panel {
            width = "100%", marginTop = 6, padding = 8,
            backgroundColor = {30, 50, 50, 220}, borderRadius = 6,
            borderWidth = 1, borderColor = {80, 200, 180, 150},
            flexDirection = "column", gap = 6,
            children = {
                UI.Label { text = "预制体名称:", fontSize = 11, fontColor = {180, 220, 200, 255} },
                UI.TextField {
                    id = "prefab_name_input",
                    width = "100%", height = 28, fontSize = 12,
                    text = levelEditor_.prefabSaveName or "",
                    onChange = function(self, text)
                        levelEditor_.prefabSaveName = text
                    end,
                },
                UI.Panel {
                    flexDirection = "row", gap = 6,
                    children = {
                        UI.Button {
                            paddingLeft = 12, paddingRight = 12, paddingTop = 5, paddingBottom = 5,
                            backgroundColor = {40, 160, 130, 230}, borderRadius = 4,
                            children = { UI.Label { text = "确认保存", fontSize = 11, fontColor = {255,255,255,255} } },
                            onClick = function()
                                local Prefab = require("editor.Prefab")
                                local name = levelEditor_.prefabSaveName or "unnamed"
                                local indices = levelEditor_.prefabSaveIndices or {}
                                local ok, err = Prefab.SavePrefab(name, objects, indices)
                                if ok then
                                    print("[Prefab] 保存成功: " .. name)
                                else
                                    print("[Prefab] 保存失败: " .. tostring(err))
                                end
                                levelEditor_.prefabSaveNaming = false
                                levelEditor_.prefabSaveIndices = nil
                                M.BuildLevelEditorUI()
                            end,
                        },
                        UI.Button {
                            paddingLeft = 12, paddingRight = 12, paddingTop = 5, paddingBottom = 5,
                            backgroundColor = {80, 60, 60, 200}, borderRadius = 4,
                            children = { UI.Label { text = "取消", fontSize = 11, fontColor = {200,200,200,255} } },
                            onClick = function()
                                levelEditor_.prefabSaveNaming = false
                                levelEditor_.prefabSaveIndices = nil
                                M.BuildLevelEditorUI()
                            end,
                        },
                    },
                },
            },
        })
    end

    -- 预制体库面板（prefab 工具激活时展示）
    if levelEditor_.currentTool == "prefab" then
        panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {60,80,80,100}, marginTop = 10 })
        panel:AddChild(UI.Label {
            text = "预制体库", fontSize = 14, fontColor = {100, 220, 200, 255}, marginBottom = 4,
        })

        local Prefab = require("editor.Prefab")
        local prefabList = Prefab.ListPrefabs()

        if #prefabList == 0 then
            panel:AddChild(UI.Label {
                text = "暂无预制体\n选中对象后点击「保存为预制体」",
                fontSize = 10, fontColor = {140, 160, 160, 180}, marginTop = 4,
            })
        else
            for pi, pInfo in ipairs(prefabList) do
                local isActive = (levelEditor_.prefabMode == "place" and levelEditor_.prefabData and levelEditor_.prefabData.name == pInfo.name)
                panel:AddChild(UI.Panel {
                    width = "100%", height = 32, marginBottom = 2,
                    flexDirection = "row", alignItems = "center",
                    backgroundColor = isActive and {60, 140, 120, 200} or {30, 50, 50, 180},
                    borderRadius = 4,
                    borderWidth = isActive and 2 or 0,
                    borderColor = {100, 255, 200, 200},
                    children = {
                        -- 预制体名称按钮（点击选中放置）
                        UI.Button {
                            flexGrow = 1, height = "100%",
                            flexDirection = "row", alignItems = "center", gap = 6,
                            paddingLeft = 8,
                            backgroundColor = {0, 0, 0, 0}, borderRadius = 0,
                            onClick = function()
                                local data, err = Prefab.LoadPrefab(pInfo.filePath)
                                if data then
                                    levelEditor_.prefabMode = "place"
                                    levelEditor_.prefabData = data
                                    levelEditor_.selectedObj = nil
                                    print("[Prefab] 选中预制体: " .. pInfo.name .. " (点击画布放置)")
                                else
                                    print("[Prefab] 加载失败: " .. tostring(err))
                                end
                                M.BuildLevelEditorUI()
                            end,
                            children = {
                                UI.Panel {
                                    width = 10, height = 10, borderRadius = 2,
                                    backgroundColor = {100, 200, 180, 255},
                                    pointerEvents = "none",
                                },
                                UI.Label {
                                    text = pInfo.name .. " (" .. pInfo.objectCount .. ")",
                                    fontSize = 11, fontColor = {200, 240, 220, 255},
                                    pointerEvents = "none",
                                },
                            },
                        },
                        -- 删除按钮
                        UI.Button {
                            text = "×", fontSize = 14, width = 28, height = "100%",
                            backgroundColor = {0, 0, 0, 0}, borderRadius = 0,
                            fontColor = {200, 100, 100, 200},
                            justifyContent = "center", alignItems = "center",
                            onClick = function()
                                Prefab.DeletePrefab(pInfo.filePath)
                                print("[Prefab] 已删除预制体: " .. pInfo.name)
                                -- 如果正在放置被删除的预制体，取消放置模式
                                if levelEditor_.prefabData and levelEditor_.prefabData.name == pInfo.name then
                                    levelEditor_.prefabMode = nil
                                    levelEditor_.prefabData = nil
                                end
                                M.BuildLevelEditorUI()
                            end,
                        },
                    },
                })
            end
        end

        -- 取消放置模式按钮
        if levelEditor_.prefabMode == "place" then
            panel:AddChild(UI.Button {
                width = "100%", paddingTop = 6, paddingBottom = 6, marginTop = 6,
                backgroundColor = {120, 60, 60, 200}, borderRadius = 4,
                justifyContent = "center", alignItems = "center",
                children = { UI.Label { text = "取消放置", fontSize = 11, fontColor = {255, 200, 200, 255} } },
                onClick = function()
                    levelEditor_.prefabMode = nil
                    levelEditor_.prefabData = nil
                    M.BuildLevelEditorUI()
                end,
            })
        end

        -- 提示
        panel:AddChild(UI.Label {
            text = "提示: 选中预制体后\n点击画布即可放置",
            fontSize = 9, fontColor = {120, 160, 150, 180}, marginTop = 6,
        })
    end

    -- 底部说明
    panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {60,60,80,80}, marginTop = 10 })
    panel:AddChild(UI.Label {
        text = "操作: 选工具后点画布放置\n选择工具点击物件编辑\nEnter确认输入 | Del删除\nCtrl+C复制 | Ctrl+Z撤销",
        fontSize = 10, fontColor = {120, 120, 150, 200}, marginTop = 4,
    })
end

return M
