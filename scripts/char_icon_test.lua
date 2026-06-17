-- ============================================================================
-- char_icon_test.lua — Spine 动画编辑器
--   · 左侧：骨架列表（spine_list.lua），点击切换预览不同 json
--   · 中间：预览区（深色背景 + 居中 + 选中组件骨骼高亮）
--   · 右侧：Inspector
--
--   char_icon（5 组件角色图标）= 驱动模式：
--     · PostUpdate 实时驱动每个组件骨骼（sway 随风摆 / spin 绕本体中心旋转 / static）
--     · 图层顺序在 char_icon.json 的 slots 中固化（自底向上：光翼>本体>发丝>发尾>丝带）
--     · Inspector 逐组件调：动画参数(幅度/周期/相位 或 旋转周期) + 大小/位置/翻转/透明度
--     · 「复制 JSON 到剪贴板」导出当前参数烘焙后的完整 Spine JSON
--   其它骨架 = 烘焙模式：直接播放已有动画 + 播放控制
-- ============================================================================
require "LuaScripts/Utilities/Sample"

local UI = require("urhox-libs/UI")
local Widget = require("urhox-libs/UI/Core/Widget")
local SKELETONS = require("spine_list")
local CHARDATA = require("char_icon_partsdata")
local cjson = require("cjson")

-- ---------------------------------------------------------------------------
-- 状态
-- ---------------------------------------------------------------------------
---@type table
local spineWidget = nil
local curIdx = 1
local needReinit = true

-- 驱动模式（char_icon）
local charParts = {}     -- 运行时组件（拷贝自 CHARDATA + 可调字段 + bone 引用）
local animTime = 0
local selPart = 1

-- 烘焙模式
---@type string[]
local animNames = {}
local curAnim = nil
local looping = true
local maxPlays = 1
local playCount = 0

-- 通用
local playing = true
local speed = 1.0
local showBones = true
local selSlot = nil

-- 动态 UI 容器/标签
---@type table
local compBox, paramBox, animBox = nil, nil, nil
---@type table
local playBtn, loopBtn, boneBtn, statusLabel, selLabel, skelLabel = nil, nil, nil, nil, nil, nil
---@type table
local charControls, bakedControls = nil, nil
-- 前向声明
---@type function
local buildParamBox = nil

local function isCharIcon() return SKELETONS[curIdx].name == "char_icon" end

-- ---------------------------------------------------------------------------
-- 初始化驱动组件（一次）
-- ---------------------------------------------------------------------------
local function initCharParts()
    charParts = {}
    for _, d in ipairs(CHARDATA.parts) do
        charParts[#charParts + 1] = {
            name = d.name, disp = d.disp, kind = d.kind,
            bx = d.bx, by = d.by, Vx = d.Vx, Vy = d.Vy, w = d.w, h = d.h,
            amp = d.amp, period = d.period, phase = d.phase, spinPeriod = d.spinPeriod,
            offX = d.offX or 0, offY = d.offY or 0, scale = d.scale or 1.0,
            flipX = d.flipX or false, alpha = d.alpha or 1.0,
            ---@type SpineBone
            bone = nil,
        }
    end
end

-- ---------------------------------------------------------------------------
-- 骨骼 → 屏幕换算
-- ---------------------------------------------------------------------------
local function skelToScreen(bone)
    local inst = spineWidget and spineWidget.spineInstance_
    if not inst or not bone then return nil end
    local l = spineWidget:GetAbsoluteLayout()
    local dataW, dataH = inst:GetDataWidth(), inst:GetDataHeight()
    local dataX, dataY = inst:GetDataX(), inst:GetDataY()
    if dataW <= 0 or dataH <= 0 then return nil end
    local s = math.min(l.w / dataW, l.h / dataH)
    local ox = (l.w - dataW * s) * 0.5 + (-dataX) * s
    local oy = (l.h - dataH * s) * 0.5 + (dataH + dataY) * s
    return l.x + ox + bone:GetWorldX() * s, l.y + oy + bone:GetWorldY() * (-s)
end

local BoneOverlay = Widget:Extend("BoneOverlay")
function BoneOverlay:Render(nvg)
    if not showBones or not spineWidget or not spineWidget:IsLoaded() then return end
    nvgFontFace(nvg, "sans"); nvgFontSize(nvg, 12)
    local rb = spineWidget:FindBone("root")
    local rx, ry
    if rb then rx, ry = skelToScreen(rb) end
    if rx then
        nvgBeginPath(nvg); nvgCircle(nvg, rx, ry, 5)
        nvgFillColor(nvg, nvgRGBA(255, 120, 120, 255)); nvgFill(nvg)
    end
    if selSlot then
        local slot = spineWidget:FindSlot(selSlot)
        local b = slot and slot:GetBone()
        if b then
            local sx, sy = skelToScreen(b)
            if sx then
                if rx then
                    nvgBeginPath(nvg); nvgMoveTo(nvg, rx, ry); nvgLineTo(nvg, sx, sy)
                    nvgStrokeColor(nvg, nvgRGBA(255, 210, 80, 160)); nvgStrokeWidth(nvg, 1.5); nvgStroke(nvg)
                end
                nvgBeginPath(nvg); nvgCircle(nvg, sx, sy, 8)
                nvgFillColor(nvg, nvgRGBA(255, 210, 80, 255)); nvgFill(nvg)
                nvgFillColor(nvg, nvgRGBA(255, 235, 150, 255))
                nvgText(nvg, sx + 11, sy - 4, selSlot)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- 通用控件 helper
-- ---------------------------------------------------------------------------
local function sliderRow(opts)
    local fmt = opts.fmt or "%.1f"
    local valLabel = UI.Label { text = string.format(fmt, opts.value), fontSize = 11,
        width = 52, textAlign = "right", color = { 150, 190, 255, 255 } }
    local slider = UI.Slider { min = opts.min, max = opts.max, value = opts.value,
        step = opts.step, flexGrow = 1,
        onChange = function(_, v)
            valLabel:SetText(string.format(fmt, v))
            if opts.onChange then opts.onChange(v) end
        end }
    return UI.Panel { width = "100%", flexDirection = "row", alignItems = "center", marginBottom = 6,
        children = { UI.Label { text = opts.label, fontSize = 11, width = 64, marginRight = 4 },
            slider, valLabel } }
end

local function sectionTitle(t)
    return UI.Label { text = t, fontSize = 14, color = { 255, 220, 120, 255 },
        marginTop = 12, marginBottom = 6 }
end

-- ---------------------------------------------------------------------------
-- 驱动模式：每帧把参数写到骨骼
-- ---------------------------------------------------------------------------
local function driveCharParts()
    for _, p in ipairs(charParts) do
        if p.bone then
            p.bone:SetX(p.bx + p.offX)
            p.bone:SetY(p.by + p.offY)
            p.bone:SetScaleX((p.flipX and -1 or 1) * p.scale)
            p.bone:SetScaleY(p.scale)
            local rot = 0
            if p.kind == "sway" and p.period > 0 then
                rot = p.amp * math.sin(2 * math.pi * animTime / p.period + p.phase)
            elseif p.kind == "spin" and p.spinPeriod > 0 then
                rot = -(((animTime / p.spinPeriod) * 360) % 360)  -- 顺时针
            end
            p.bone:SetRotation(rot)
            local slot = spineWidget:FindSlot(p.name)
            if slot then slot:SetColor(1, 1, 1, p.alpha) end
        end
    end
end

-- ---------------------------------------------------------------------------
-- 烘焙模式：播放控制
-- ---------------------------------------------------------------------------
local function updatePlayBtn() if playBtn then playBtn:SetText(playing and "暂停" or "播放") end end
local function updateLoopBtn() if loopBtn then loopBtn:SetText(looping and "循环: 开" or "循环: 关") end end

local function setAnim(name)
    if not spineWidget:IsLoaded() then return end
    curAnim = name; playCount = 0; playing = true
    spineWidget:SetAnimation(name, true)
    spineWidget:SetSpeed(speed)
    spineWidget:SetTimeScale(1)
    updatePlayBtn()
    if statusLabel then statusLabel:SetText("播放: " .. name) end
end

local function togglePlay()
    playing = not playing
    if isCharIcon() then
        -- 驱动模式：仅切换 animTime 推进
    else
        if playing and (not looping) and playCount >= maxPlays then
            playCount = 0
            if curAnim then spineWidget:SetAnimation(curAnim, true) end
        end
        spineWidget:SetTimeScale(playing and 1 or 0)
    end
    updatePlayBtn()
end

local function toggleLoop()
    looping = not looping; playCount = 0; playing = true
    if curAnim then spineWidget:SetAnimation(curAnim, true) end
    spineWidget:SetTimeScale(1)
    updateLoopBtn(); updatePlayBtn()
end

-- ---------------------------------------------------------------------------
-- 导出：把当前参数烘焙成完整 Spine JSON → 剪贴板
-- ---------------------------------------------------------------------------
local function r3(v) return tonumber(string.format("%.3f", v)) end

local function exportCharJson()
    local W, H = CHARDATA.W, CHARDATA.H
    local animDur = 0
    for _, p in ipairs(charParts) do
        if p.kind == "spin" and p.spinPeriod > 0 then animDur = p.spinPeriod end
    end
    if animDur <= 0 then
        for _, p in ipairs(charParts) do
            if p.kind == "sway" then animDur = math.max(animDur, p.period) end
        end
    end
    if animDur <= 0 then animDur = 2.4 end

    local bones = { { name = "root" } }
    local slots, attach, animBones = {}, {}, {}
    for _, p in ipairs(charParts) do
        local b = { name = "b_" .. p.name, parent = "root", x = r3(p.bx + p.offX), y = r3(p.by + p.offY) }
        if p.scale ~= 1 or p.flipX then
            b.scaleX = r3((p.flipX and -1 or 1) * p.scale)
            b.scaleY = r3(p.scale)
        end
        bones[#bones + 1] = b
        attach[p.name] = { [p.name] = { x = r3(p.Vx), y = r3(p.Vy), width = p.w, height = p.h } }
    end
    -- slots：charParts 已按图层顺序（自底向上）
    for _, p in ipairs(charParts) do
        local s = { name = p.name, bone = "b_" .. p.name, attachment = p.name }
        if p.alpha < 0.999 then
            s.color = string.format("ffffff%02x", math.floor(p.alpha * 255 + 0.5))
        end
        slots[#slots + 1] = s
    end
    -- 动画（rotate 烘焙，整数周期 → 无缝循环）
    for _, p in ipairs(charParts) do
        if p.kind == "sway" and p.period > 0 then
            local cycles = math.max(1, math.floor(animDur / p.period + 0.5))
            local N, kf = 24, {}
            for i = 0, N do
                local v = p.amp * math.sin(2 * math.pi * cycles * (i / N) + p.phase)
                local d = { value = r3(v) }; if i > 0 then d.time = r3(animDur * i / N) end
                kf[#kf + 1] = d
            end
            animBones["b_" .. p.name] = { rotate = kf }
        elseif p.kind == "spin" and p.spinPeriod > 0 then
            local N, kf = 48, {}
            for i = 0, N do
                local d = { value = r3(-360 * (i / N)), curve = "linear" }
                if i > 0 then d.time = r3(animDur * i / N) end
                kf[#kf + 1] = d
            end
            animBones["b_" .. p.name] = { rotate = kf }
        end
    end

    local obj = {
        skeleton = { hash = "chariconspine5", spine = "4.2.00", x = 0, y = 0,
            width = W, height = H, images = "./", audio = "" },
        bones = bones, slots = slots,
        skins = { { name = "default", attachments = attach } },
        animations = { idle = { bones = animBones } },
    }
    local ok, enc = pcall(cjson.encode, obj)
    if not ok then if statusLabel then statusLabel:SetText("导出失败") end return end
    ui:SetUseSystemClipboard(true)
    ui:SetClipboardText(enc)
    if statusLabel then statusLabel:SetText("已复制 JSON 到剪贴板，请粘贴回传") end
end

-- ---------------------------------------------------------------------------
-- Inspector：驱动模式 - 选中组件的参数
-- ---------------------------------------------------------------------------
local KINDDESC = { sway = "随风摆动（绕根部）", spin = "绕本体中心旋转", static = "静止" }

buildParamBox = function(idx)
    if not paramBox then return end
    selPart = idx
    local p = charParts[idx]
    if not p then return end
    selSlot = p.name
    if selLabel then selLabel:SetText("选中: " .. p.disp .. "  [" .. (KINDDESC[p.kind] or "") .. "]") end
    paramBox:ClearChildren()

    if p.kind == "sway" then
        paramBox:AddChild(sliderRow { label = "幅度°", min = 0, max = 20, value = p.amp,
            step = 0.5, fmt = "%.1f", onChange = function(v) p.amp = v end })
        paramBox:AddChild(sliderRow { label = "周期s", min = 0.5, max = 6, value = p.period,
            step = 0.1, fmt = "%.1f", onChange = function(v) p.period = v end })
        paramBox:AddChild(sliderRow { label = "相位", min = 0, max = 6.28, value = p.phase,
            step = 0.05, fmt = "%.2f", onChange = function(v) p.phase = v end })
    elseif p.kind == "spin" then
        paramBox:AddChild(sliderRow { label = "旋转周期s", min = 2, max = 30, value = p.spinPeriod,
            step = 0.5, fmt = "%.1f", onChange = function(v) p.spinPeriod = v end })
    else
        paramBox:AddChild(UI.Label { text = "（本组件静止，无动画参数）", fontSize = 11,
            color = { 150, 150, 170, 255 }, marginBottom = 4 })
    end

    paramBox:AddChild(sliderRow { label = "大小", min = 0.3, max = 2.5, value = p.scale,
        step = 0.05, fmt = "%.2f", onChange = function(v) p.scale = v end })
    paramBox:AddChild(sliderRow { label = "位置X", min = -300, max = 300, value = p.offX,
        step = 1, fmt = "%.0f", onChange = function(v) p.offX = v end })
    paramBox:AddChild(sliderRow { label = "位置Y", min = -300, max = 300, value = p.offY,
        step = 1, fmt = "%.0f", onChange = function(v) p.offY = v end })
    paramBox:AddChild(sliderRow { label = "透明度", min = 0, max = 1, value = p.alpha,
        step = 0.05, fmt = "%.2f", onChange = function(v) p.alpha = v end })

    local flipBtn = UI.Button { text = p.flipX and "水平翻转: 开" or "水平翻转: 关",
        variant = "secondary", width = "100%", height = 28, fontSize = 11, marginTop = 2,
        onClick = function(self)
            p.flipX = not p.flipX
            self:SetText(p.flipX and "水平翻转: 开" or "水平翻转: 关")
        end }
    local resetBtn = UI.Button { text = "重置该组件", variant = "danger", width = "100%",
        height = 28, fontSize = 11, marginTop = 4,
        onClick = function()
            local d = CHARDATA.parts[idx]
            p.amp, p.period, p.phase, p.spinPeriod = d.amp, d.period, d.phase, d.spinPeriod
            p.offX, p.offY = d.offX or 0, d.offY or 0
            p.scale, p.flipX, p.alpha = d.scale or 1.0, d.flipX or false, d.alpha or 1.0
            buildParamBox(idx)
        end }
    paramBox:AddChild(flipBtn)
    paramBox:AddChild(resetBtn)
end

local function buildCompButtons()
    if not compBox then return end
    compBox:ClearChildren()
    for i, p in ipairs(charParts) do
        compBox:AddChild(UI.Button { text = p.disp, variant = "secondary",
            height = 30, fontSize = 12, paddingHorizontal = 9, marginRight = 6, marginBottom = 6,
            onClick = function() buildParamBox(i) end })
    end
end

-- ---------------------------------------------------------------------------
-- Inspector：烘焙模式 - 动画按钮
-- ---------------------------------------------------------------------------
local function buildAnimButtons()
    if not animBox then return end
    animBox:ClearChildren()
    for _, name in ipairs(animNames) do
        animBox:AddChild(UI.Button { text = name, variant = "primary",
            height = 28, fontSize = 11, paddingHorizontal = 8, marginRight = 6, marginBottom = 6,
            onClick = function() setAnim(name) end })
    end
end

-- 切换显示哪一组控件
local function refreshInspectorMode()
    local char = isCharIcon()
    if charControls then charControls:SetStyle({ display = char and "flex" or "none" }) end
    if bakedControls then bakedControls:SetStyle({ display = char and "none" or "flex" }) end
    if loopBtn then loopBtn:SetStyle({ display = char and "none" or "flex" }) end
end

-- ---------------------------------------------------------------------------
-- 切换骨架
-- ---------------------------------------------------------------------------
local function selectSkeleton(i)
    if i == curIdx then return end
    curIdx = i
    selSlot = nil
    spineWidget:SetSrc(SKELETONS[i].src)
    needReinit = true
    if skelLabel then skelLabel:SetText("当前: " .. SKELETONS[i].name) end
end

-- ---------------------------------------------------------------------------
-- UI 构建
-- ---------------------------------------------------------------------------
local function buildLeftPanel()
    ---@type table[]
    local items = { UI.Label { text = "骨架", fontSize = 16, color = { 255, 255, 255, 255 }, marginBottom = 8 } }
    for i, sk in ipairs(SKELETONS) do
        items[#items + 1] = UI.Button { text = sk.name, variant = "secondary",
            width = "100%", height = 34, fontSize = 12, marginBottom = 6,
            onClick = function() selectSkeleton(i) end }
    end
    return UI.ScrollView { width = 180, height = "100%", backgroundColor = { 22, 23, 32, 255 },
        paddingHorizontal = 12, paddingVertical = 12, children = items }
end

local function buildInspector()
    compBox = UI.Panel { width = "100%", flexDirection = "row", flexWrap = "wrap" }
    paramBox = UI.Panel { width = "100%", flexDirection = "column" }
    animBox = UI.Panel { width = "100%", flexDirection = "row", flexWrap = "wrap" }

    playBtn = UI.Button { text = "暂停", variant = "primary", flexGrow = 1, marginRight = 6,
        onClick = togglePlay }
    loopBtn = UI.Button { text = "循环: 开", variant = "primary", flexGrow = 1, marginRight = 6,
        onClick = toggleLoop }
    boneBtn = UI.Button { text = "骨骼: 开", variant = "secondary", flexGrow = 1,
        onClick = function(self) showBones = not showBones; self:SetText(showBones and "骨骼: 开" or "骨骼: 关") end }
    statusLabel = UI.Label { text = "拖动滑块实时调整", fontSize = 11, color = { 140, 200, 140, 255 }, marginTop = 6 }
    selLabel = UI.Label { text = "未选中组件", fontSize = 12, color = { 200, 210, 255, 255 }, marginTop = 4 }

    -- 驱动模式专属控件
    charControls = UI.Panel { width = "100%", flexDirection = "column",
        children = {
            sectionTitle("组件（点击选中调参）"),
            compBox, selLabel, paramBox,
            sectionTitle("导出"),
            UI.Button { text = "复制 JSON 到剪贴板", variant = "success", width = "100%",
                onClick = exportCharJson },
        } }
    -- 烘焙模式专属控件
    bakedControls = UI.Panel { width = "100%", flexDirection = "column", display = "none",
        children = {
            sectionTitle("动画"),
            animBox,
            sliderRow { label = "播放次数", min = 1, max = 20, value = maxPlays, step = 1,
                fmt = "%.0f", onChange = function(v) maxPlays = math.floor(v) end },
        } }

    return UI.ScrollView { width = 340, height = "100%", backgroundColor = { 22, 23, 32, 255 },
        paddingHorizontal = 14, paddingVertical = 12,
        children = {
            UI.Label { text = "Inspector", fontSize = 19, color = { 255, 255, 255, 255 } },
            sectionTitle("播放控制"),
            UI.Panel { width = "100%", flexDirection = "row",
                children = { playBtn, loopBtn, boneBtn } },
            sliderRow { label = "速度", min = 0.1, max = 3, value = speed, step = 0.1, fmt = "%.1fx",
                onChange = function(v)
                    speed = v
                    if (not isCharIcon()) and spineWidget:IsLoaded() then spineWidget:SetSpeed(v) end
                end },
            statusLabel,
            bakedControls,
            charControls,
        },
    }
end

-- ---------------------------------------------------------------------------
function Start()
    SampleStart()
    UI.Init({
        theme = "default-dark",
        fonts = { { name = "sans", path = "Fonts/MiSans-Regular.ttf" } },
        scale = UI.Scale.DEFAULT,
    })
    initCharParts()

    spineWidget = UI.Spine {
        src = SKELETONS[curIdx].src, animation = "idle", loop = true, pma = false,
        objectFit = "contain", width = 720, height = 720,
    }
    spineWidget:SetCompleteListener(function(_, _)
        if isCharIcon() then return end
        playCount = playCount + 1
        if (not looping) and playCount >= maxPlays then
            spineWidget:SetTimeScale(0); playing = false; updatePlayBtn()
            if statusLabel then statusLabel:SetText(string.format("已播放 %d 次后停止", playCount)) end
        end
    end)

    local overlay = BoneOverlay { position = "absolute", top = 0, left = 0, width = "100%", height = "100%" }
    skelLabel = UI.Label { text = "当前: " .. SKELETONS[curIdx].name, fontSize = 16,
        color = { 230, 235, 255, 255 }, position = "absolute", top = 18, left = 0,
        width = "100%", textAlign = "center" }
    local preview = UI.Panel {
        flexGrow = 1, height = "100%", position = "relative",
        backgroundColor = { 16, 18, 40, 255 }, justifyContent = "center", alignItems = "center",
        children = { skelLabel, spineWidget, overlay },
    }

    UI.SetRoot(UI.Panel { width = "100%", height = "100%", flexDirection = "row",
        children = { buildLeftPanel(), preview, buildInspector() } })
    SampleInitMouseMode(MM_FREE)
    SubscribeToEvent("PostUpdate", "HandlePostUpdate")
    print("[char_icon_editor] started, skeletons=" .. #SKELETONS)
end

---@param eventType string
---@param eventData UpdateEventData
function HandlePostUpdate(eventType, eventData)
    if not spineWidget or not spineWidget:IsLoaded() then return end
    if needReinit then
        if isCharIcon() then
            spineWidget:SetToSetupPose(); spineWidget:Stop()
            for _, p in ipairs(charParts) do p.bone = spineWidget:FindBone("b_" .. p.name) end
            buildCompButtons()
            buildParamBox(selPart)
        else
            animNames = spineWidget:GetAnimationNames() or {}
            buildAnimButtons()
            local toPlay = animNames[1]
            if toPlay then setAnim(toPlay) end
        end
        refreshInspectorMode()
        needReinit = false
    end

    if isCharIcon() then
        local dt = eventData["TimeStep"]:GetFloat()
        if playing then animTime = animTime + dt * speed end
        driveCharParts()
        spineWidget:UpdateWorldTransform()
    end
end

function Stop()
    UI.Shutdown()
end
