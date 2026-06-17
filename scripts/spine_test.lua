-- ============================================================================
-- spine_test.lua
-- 法杖多组件 Spine 动画编辑器（参数实时可调）
--   组成：光翼(呼吸) + 三碎片(从菱形中心顺时针弧线展开) + 法杖本体(静止, 最上层)
--   · PostUpdate 按参数实时驱动骨骼，调滑块即时生效
--   · 可调参数：周期 / 光翼呼吸 / 展开幅度 / 弧线弯曲 / 停留 / 错开
--   · 骨骼叠加层：骨骼点 / 父子连线 / 选中高亮；播放暂停；导出 JSON
-- ============================================================================
require "LuaScripts/Utilities/Sample"

local UI = require("urhox-libs/UI")
local Widget = require("urhox-libs/UI/Core/Widget")
local cjson = require("cjson")
local DATA = require("staff_partsdata")

-- ----------------------------------------------------------------------------
local parts = {}
local fragCount = 0
for _, d in ipairs(DATA.parts) do
    local p = { name = d.name, disp = d.disp, kind = d.kind,
        bx = d.bx, by = d.by, w = d.w, h = d.h,
        Vx = d.Vx, Vy = d.Vy, R = d.R, ang = d.ang,
        fragIndex = 0,
        ---@type SpineBone
        bone = nil }
    if d.kind == "frag" then p.fragIndex = fragCount; fragCount = fragCount + 1 end
    parts[#parts + 1] = p
end

-- 可调参数（初值取自生成默认）
local P = {
    period     = 1.4,   -- 周期 1.4s（编辑器默认值）
    wingBob    = DATA.defaults.wingBob,
    deployScale = DATA.defaults.deployScale,
    sweep      = DATA.defaults.sweep,
    holdR      = DATA.defaults.holdR,
    stagger    = DATA.defaults.stagger,
    deployDur  = DATA.defaults.deployDur,
}

local selected = 1
local playing = true
local showBones = true
local animTime = 0
local initialized = false

---@type table
local spineWidget = nil
---@type SpineBone
local rootBone = nil
---@type table
local selLabel, bindLabel, statusLabel, playBtn, boneBtn = nil, nil, nil, nil, nil

local KINDDESC = {
    static = "法杖本体（静止·最上层）",
    wing = "光翼（上下呼吸起伏）",
    frag = "碎片（菱形中心→弧线展开）",
}

-- ----------------------------------------------------------------------------
-- 动画曲线
-- ----------------------------------------------------------------------------
local function easeOut(x) return 1 - (1 - x) ^ 3 end
local function easeIn(x) return x ^ 3 end

local function fragP(k, s)
    local t0 = P.stagger * k
    local t1 = math.min(t0 + P.deployDur, P.holdR - 0.02)
    if s < t0 then return 0.0 end
    if s < t1 then return easeOut((s - t0) / (t1 - t0)) end
    if s < P.holdR then return 1.0 end
    return 1.0 - easeIn((s - P.holdR) / (1.0 - P.holdR))
end

local function fragOff(part, p)
    local rad = p * part.R * P.deployScale
    local th = part.ang + P.sweep * (1 - p)
    return rad * math.cos(th) - part.Vx, rad * math.sin(th) - part.Vy
end

-- ----------------------------------------------------------------------------
-- 骨骼叠加可视化
-- ----------------------------------------------------------------------------
local BoneOverlay = Widget:Extend("BoneOverlay")

local function skelToScreen(skx, sky)
    local inst = spineWidget and spineWidget.spineInstance_
    if not inst then return nil end
    local l = spineWidget:GetAbsoluteLayout()
    local dataW, dataH = inst:GetDataWidth(), inst:GetDataHeight()
    local dataX, dataY = inst:GetDataX(), inst:GetDataY()
    if dataW <= 0 or dataH <= 0 then return nil end
    local s = math.min(l.w / dataW, l.h / dataH)
    local originX = (l.w - dataW * s) * 0.5 + (-dataX) * s
    local originY = (l.h - dataH * s) * 0.5 + (dataH + dataY) * s
    return l.x + originX + skx * s, l.y + originY + sky * (-s)
end

local function fillC(nvg, r, g, b, a) nvgFillColor(nvg, nvgRGBA(r, g, b, a)) end
local function strokeC(nvg, r, g, b, a) nvgStrokeColor(nvg, nvgRGBA(r, g, b, a)) end

function BoneOverlay:Render(nvg)
    if not showBones or not spineWidget or not spineWidget:IsLoaded() then return end
    local rx, ry
    if rootBone then rx, ry = skelToScreen(rootBone:GetWorldX(), rootBone:GetWorldY()) end
    nvgFontFace(nvg, "sans"); nvgFontSize(nvg, 12)
    for _, p in ipairs(parts) do
        if p.bone then
            local sx, sy = skelToScreen(p.bone:GetWorldX(), p.bone:GetWorldY())
            if sx then
                if rx then
                    nvgBeginPath(nvg); nvgMoveTo(nvg, rx, ry); nvgLineTo(nvg, sx, sy)
                    strokeC(nvg, 90, 160, 255, 90); nvgStrokeWidth(nvg, 1.5); nvgStroke(nvg)
                end
                local sel = (parts[selected] == p)
                local rad = sel and 8 or 5
                nvgBeginPath(nvg); nvgCircle(nvg, sx, sy, rad)
                if sel then fillC(nvg, 255, 210, 80, 255) else fillC(nvg, 80, 200, 255, 220) end
                nvgFill(nvg)
                if sel then
                    nvgBeginPath(nvg); nvgCircle(nvg, sx, sy, rad + 3)
                    strokeC(nvg, 255, 210, 80, 220); nvgStrokeWidth(nvg, 2); nvgStroke(nvg)
                    fillC(nvg, 255, 235, 130, 255); nvgText(nvg, sx + 10, sy - 4, p.disp)
                end
            end
        end
    end
    if rx then
        nvgBeginPath(nvg); nvgCircle(nvg, rx, ry, 6); fillC(nvg, 255, 120, 120, 255); nvgFill(nvg)
    end
end

-- ----------------------------------------------------------------------------
local function refreshSelection()
    local p = parts[selected]
    if not p then return end
    if selLabel then selLabel:SetText("选中: " .. p.disp .. "  (b_" .. p.name .. ")") end
    if bindLabel then bindLabel:SetText(KINDDESC[p.kind] or "") end
end
local function selectPart(i) selected = i; refreshSelection() end

-- ----------------------------------------------------------------------------
-- 导出（重建烘焙 JSON）
-- ----------------------------------------------------------------------------
local function r3(v) return tonumber(string.format("%.3f", v)) end
local function exportJson()
    local T, N = P.period, 24
    local bones = { { name = "root" } }
    local slots, attach, animBones = {}, {}, {}
    for _, p in ipairs(parts) do
        bones[#bones + 1] = { name = "b_" .. p.name, parent = "root", x = p.bx, y = p.by }
        slots[#slots + 1] = { name = p.name, bone = "b_" .. p.name, attachment = p.name }
        attach[p.name] = { [p.name] = { x = r3(p.Vx), y = r3(p.Vy), width = p.w, height = p.h } }
    end
    for _, p in ipairs(parts) do
        if p.kind == "frag" then
            local kf = {}
            for i = 0, N do
                local s = i / N
                local ox, oy = fragOff(p, fragP(p.fragIndex, s))
                local d = { x = r3(ox), y = r3(oy) }; if i > 0 then d.time = r3(s * T) end
                kf[#kf + 1] = d
            end
            animBones["b_" .. p.name] = { translate = kf }
        elseif p.kind == "wing" then
            local kf = {}
            for i = 0, N do
                local s = i / N
                local d = { y = r3(P.wingBob * math.sin(2 * math.pi * s)) }
                if i > 0 then d.time = r3(s * T) end
                kf[#kf + 1] = d
            end
            animBones["b_" .. p.name] = { translate = kf }
        end
    end
    local obj = {
        skeleton = { hash = "staff1", spine = "4.2.00", x = DATA.bounds.x, y = DATA.bounds.y,
            width = DATA.bounds.w, height = DATA.bounds.h, images = "./", audio = "" },
        bones = bones, slots = slots,
        skins = { { name = "default", attachments = attach } },
        animations = { deploy = { bones = animBones } },
    }
    local ok, enc = pcall(cjson.encode, obj)
    if not ok then if statusLabel then statusLabel:SetText("导出失败") end return end
    -- 复制 JSON 到系统剪贴板，由用户通过对话回传
    ui:SetUseSystemClipboard(true)
    ui:SetClipboardText(enc)
    if statusLabel then statusLabel:SetText("已复制 JSON 到剪贴板，请粘贴回传") end
end

-- ----------------------------------------------------------------------------
local function sliderRow(opts)
    local fmt = opts.fmt or "%.2f"
    local valLabel = UI.Label { text = string.format(fmt, opts.value), fontSize = 12,
        width = 56, textAlign = "right", color = { 150, 190, 255, 255 } }
    local slider = UI.Slider { min = opts.min, max = opts.max, value = opts.value,
        step = opts.step, flexGrow = 1,
        onChange = function(_, v)
            valLabel:SetText(string.format(fmt, v))
            if opts.onChange then opts.onChange(v) end
        end }
    return UI.Panel { width = "100%", flexDirection = "row", alignItems = "center",
        marginBottom = 8,
        children = { UI.Label { text = opts.label, fontSize = 12, width = 76, marginRight = 4 },
            slider, valLabel } }
end
local function sectionTitle(t)
    return UI.Label { text = t, fontSize = 14, color = { 255, 220, 120, 255 },
        marginTop = 12, marginBottom = 6 }
end

-- ----------------------------------------------------------------------------
local function buildEditor()
    spineWidget = UI.Spine {
        src = "Spines/staff_parts.json", animation = "deploy", loop = true, pma = false,
        objectFit = "contain", width = 700, height = 700,
    }
    local overlay = BoneOverlay { position = "absolute", top = 0, left = 0,
        width = "100%", height = "100%" }
    local previewPanel = UI.Panel {
        flexGrow = 1, height = "100%", position = "relative",
        backgroundColor = { 18, 20, 44, 255 },
        justifyContent = "center", alignItems = "center",
        children = { spineWidget, overlay },
    }

    local btns = {}
    for i, p in ipairs(parts) do
        btns[i] = UI.Button { text = p.disp, variant = "secondary",
            height = 30, fontSize = 12, paddingHorizontal = 9, marginRight = 6, marginBottom = 6,
            onClick = function() selectPart(i) end }
    end
    local picker = UI.Panel { width = "100%", flexDirection = "row", flexWrap = "wrap",
        children = btns }

    selLabel = UI.Label { text = "", fontSize = 13, color = { 255, 255, 255, 255 }, marginTop = 4 }
    bindLabel = UI.Label { text = "", fontSize = 12, color = { 150, 200, 255, 255 }, marginBottom = 4 }

    playBtn = UI.Button { text = "暂停", variant = "primary", flexGrow = 1, marginRight = 8,
        onClick = function()
            playing = not playing
            playBtn:SetText(playing and "暂停" or "播放")
        end }
    boneBtn = UI.Button { text = "骨骼: 开", variant = "primary", flexGrow = 1,
        onClick = function()
            showBones = not showBones
            boneBtn:SetText(showBones and "骨骼: 开" or "骨骼: 关")
        end }
    statusLabel = UI.Label { text = "拖动滑块实时调整", fontSize = 11,
        color = { 140, 200, 140, 255 }, marginTop = 6 }

    local controls = UI.ScrollView {
        width = 360, height = "100%", backgroundColor = { 22, 23, 32, 255 },
        paddingHorizontal = 14, paddingVertical = 12,
        children = {
            UI.Label { text = "法杖 Spine 编辑器", fontSize = 19,
                color = { 255, 255, 255, 255 }, marginBottom = 4 },

            sectionTitle("组件 (" .. #parts .. ")"),
            picker, selLabel, bindLabel,

            sectionTitle("动画参数（实时）"),
            sliderRow { label = "周期", min = 1, max = 6, value = P.period, step = 0.1,
                fmt = "%.1fs", onChange = function(v) P.period = v end },
            sliderRow { label = "光翼呼吸", min = 0, max = 60, value = P.wingBob, step = 1,
                fmt = "%.0f", onChange = function(v) P.wingBob = v end },
            sliderRow { label = "展开幅度", min = 0.3, max = 1.6, value = P.deployScale, step = 0.05,
                fmt = "%.2fx", onChange = function(v) P.deployScale = v end },
            sliderRow { label = "弧线弯曲", min = -1.5, max = 1.5, value = P.sweep, step = 0.05,
                fmt = "%.2f", onChange = function(v) P.sweep = v end },
            sliderRow { label = "停留比例", min = 0.2, max = 0.9, value = P.holdR, step = 0.02,
                fmt = "%.2f", onChange = function(v) P.holdR = v end },
            sliderRow { label = "错开量", min = 0, max = 0.3, value = P.stagger, step = 0.01,
                fmt = "%.2f", onChange = function(v) P.stagger = v end },

            sectionTitle("控制"),
            UI.Panel { width = "100%", flexDirection = "row", marginBottom = 8,
                children = { playBtn, boneBtn } },
            UI.Button { text = "复制 JSON 到剪贴板", variant = "success", width = "100%", marginBottom = 8,
                onClick = exportJson },
            statusLabel,
        },
    }

    return UI.Panel { width = "100%", height = "100%", flexDirection = "row",
        children = { previewPanel, controls } }
end

-- ----------------------------------------------------------------------------
---@param eventType string
---@param eventData UpdateEventData
function HandlePostUpdate(eventType, eventData)
    if not spineWidget or not spineWidget:IsLoaded() then return end
    if not initialized then
        spineWidget:SetToSetupPose(); spineWidget:Stop()
        rootBone = spineWidget:FindBone("root")
        for _, p in ipairs(parts) do p.bone = spineWidget:FindBone("b_" .. p.name) end
        initialized = true
        refreshSelection()
    end

    local dt = eventData["TimeStep"]:GetFloat()
    if playing then animTime = (animTime + dt) % P.period end
    local s = animTime / P.period

    for _, p in ipairs(parts) do
        if p.bone then
            if p.kind == "frag" then
                local ox, oy = fragOff(p, fragP(p.fragIndex, s))
                p.bone:SetX(p.bx + ox); p.bone:SetY(p.by + oy)
            elseif p.kind == "wing" then
                p.bone:SetX(p.bx)
                p.bone:SetY(p.by + P.wingBob * math.sin(2 * math.pi * s))
            else
                p.bone:SetX(p.bx); p.bone:SetY(p.by)
            end
        end
    end
    spineWidget:UpdateWorldTransform()
end

function Start()
    SampleStart()
    UI.Init({
        theme = "default-dark",
        fonts = { { name = "sans", path = "Fonts/MiSans-Regular.ttf" } },
        scale = UI.Scale.DEFAULT,
    })
    UI.SetRoot(buildEditor())
    SampleInitMouseMode(MM_FREE)
    SubscribeToEvent("PostUpdate", "HandlePostUpdate")
    print("[staff_editor] started, parts=" .. #parts)
end

function Stop()
    UI.Shutdown()
end
