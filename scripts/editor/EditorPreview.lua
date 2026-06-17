-- ============================================================================
-- editor/EditorPreview.lua
-- 预览/仿真系统（从 TitleMenu.lua 提取，语义不变）
-- ============================================================================
local S = require("GameState")
local C = require("GameConfig")
local UI = require("urhox-libs/UI")
local Animation = require("Animation")
local Combat = require("Combat")
local EditorState = require("editor.EditorState")
require("effects.builtin")  -- 注册内置效果
local EffectRegistry = require("effects.EffectRegistry")
local DialogManager = require("dialog.DialogManager")

local P = {}
local levelEditor_ = EditorState.state

-- ============================================================================
-- 缓动函数 & 路径求值工具
-- ============================================================================

local EASE_FNS = {
    linear    = function(t) return t end,
    easeIn    = function(t) return t * t end,
    easeOut   = function(t) return 1 - (1 - t) * (1 - t) end,
    easeInOut = function(t)
        if t < 0.5 then return 2 * t * t
        else return 1 - 2 * (1 - t) * (1 - t) end
    end,
}

--- 根据路径类型和 pathPoints 创建求值函数 f(t) -> worldX, worldY
--- pathPoints 中的 x/y 是绝对世界目标坐标（Y-up），不是偏移量
--- @param pathType string
--- @param pathPoints table
--- @param originX number 物件初始世界坐标 X
--- @param originY number 物件初始世界坐标 Y
--- @return function evaluator(t:0-1) -> x, y
local function createPathEvaluator(pathType, pathPoints, originX, originY)
    if pathType == "none" then
        -- 瞬移：直接返回目标位置
        local pt = pathPoints[1] or { x = originX, y = originY }
        local endX = pt.x or originX
        local endY = pt.y or originY
        return function(_) return endX, endY end
    elseif pathType == "linear" then
        -- pathPoints[1] = {x=目标X, y=目标Y}
        local pt = pathPoints[1] or { x = originX, y = originY }
        local endX = pt.x or originX
        local endY = pt.y or originY
        return function(t)
            return originX + (endX - originX) * t, originY + (endY - originY) * t
        end
    elseif pathType == "bezier" then
        -- pathPoints[1] = {x, y, cx, cy} (目标坐标 + 控制点坐标，均为绝对坐标)
        local pt = pathPoints[1] or { x = originX, y = originY, cx = originX, cy = originY }
        local endX = pt.x or originX
        local endY = pt.y or originY
        local ctrlX = pt.cx or originX
        local ctrlY = pt.cy or originY
        return function(t)
            -- 二次贝塞尔: B(t) = (1-t)^2*P0 + 2(1-t)t*P1 + t^2*P2
            local u = 1 - t
            local x = u * u * originX + 2 * u * t * ctrlX + t * t * endX
            local y = u * u * originY + 2 * u * t * ctrlY + t * t * endY
            return x, y
        end
    elseif pathType == "circle" then
        -- pathPoints[1] = {radius, startAngle(deg), endAngle(deg)} (圆弧保持相对方式)
        local pt = pathPoints[1] or { radius = 2, startAngle = 0, endAngle = 360 }
        local r = pt.radius or 2
        local sa = math.rad(pt.startAngle or 0)
        local ea = math.rad(pt.endAngle or 360)
        return function(t)
            local angle = sa + (ea - sa) * t
            return originX + math.cos(angle) * r, originY + math.sin(angle) * r
        end
    elseif pathType == "custom" then
        -- pathPoints = 多个途经点，绝对世界坐标
        if #pathPoints == 0 then
            return function(_) return originX, originY end
        end
        -- 构建世界坐标列表（含起始点）
        local pts = { { x = originX, y = originY } }
        for _, p in ipairs(pathPoints) do
            table.insert(pts, { x = p.x or originX, y = p.y or originY })
        end
        -- 计算各段长度
        local segLens = {}
        local totalLen = 0
        for i = 2, #pts do
            local dx = pts[i].x - pts[i-1].x
            local dy = pts[i].y - pts[i-1].y
            local len = math.sqrt(dx * dx + dy * dy)
            segLens[i-1] = len
            totalLen = totalLen + len
        end
        if totalLen == 0 then
            return function(_) return originX, originY end
        end
        return function(t)
            local dist = t * totalLen
            local accum = 0
            for i = 1, #segLens do
                if accum + segLens[i] >= dist then
                    local segT = (dist - accum) / segLens[i]
                    local ax, ay = pts[i].x, pts[i].y
                    local bx, by = pts[i+1].x, pts[i+1].y
                    return ax + (bx - ax) * segT, ay + (by - ay) * segT
                end
                accum = accum + segLens[i]
            end
            return pts[#pts].x, pts[#pts].y
        end
    end
    -- fallback
    return function(_) return originX, originY end
end

--- 粒子方向映射
local PARTICLE_DIR_MAP = {
    up    = { x = 0, y = 1 },
    down  = { x = 0, y = -1 },
    left  = { x = -1, y = 0 },
    right = { x = 1, y = 0 },
    radial= { x = 0, y = 0 },  -- 特殊：随机方向
}

--- 颜色名称映射
local FLASH_COLOR_MAP = {
    white  = { 255, 255, 255 },
    red    = { 255, 60, 60 },
    blue   = { 80, 140, 255 },
    green  = { 60, 255, 100 },
    yellow = { 255, 240, 60 },
}

-- ============================================================================
-- 碰撞形状工厂（OCP: 新增形状只需在此 table 加一行）
-- ============================================================================

local SHAPE_CREATORS = {
    box = function(node, obj)
        local shape = node:CreateComponent("CollisionBox2D")
        shape:SetSize(obj.w, obj.h)
        return shape
    end,

    circle = function(node, obj)
        local shape = node:CreateComponent("CollisionCircle2D")
        shape.radius = obj.circleRadius or (math.min(obj.w, obj.h) / 2)
        return shape
    end,

}

--- 根据 obj.collisionShape 创建碰撞体（替换硬编码 CollisionBox2D）
--- @param node any Urho2D node
--- @param obj table 物件数据
--- @return any|nil shape component
local function createCollisionShape(node, obj)
    local shapeType = obj.collisionShape or "box"
    local creator = SHAPE_CREATORS[shapeType]
    if not creator then
        print("[WARN] 未知碰撞形状: " .. tostring(shapeType) .. ", fallback to box")
        creator = SHAPE_CREATORS.box
    end
    local shape = creator(node, obj)
    if shape then
        shape.friction = obj.friction or 0.3
        shape.restitution = obj.restitution or 0.0
        shape.categoryBits = 1
    end
    return shape
end

-- ============================================================================
-- 滞空滑翔策略接口
-- 通过替换 P.hangGlideStrategy 可自定义触发条件
-- ============================================================================

--- 滞空滑翔是否启用（X键切换，默认禁用）
P.hangGlideEnabled = false

--- 滞空触发条件策略函数
--- @param ctx table {onGround, jumpHeld, isHanging, hangCooldown, velY, jumpWasCut}
--- @return boolean 是否允许进入滞空
P.hangGlideStrategy = function(ctx)
    -- 碎片数==3时才允许滞空滑翔
    local fragments = (levelEditor_.previewItems or {})["light_fragment"] or 0
    return P.hangGlideEnabled
        and fragments >= 3
        and not ctx.onGround
        and ctx.jumpHeld
        and not ctx.isHanging
        and ctx.hangCooldown <= 0
        and ctx.velY < 0
        and not ctx.jumpWasCut
end

-- 延迟引用 TitleMenu（避免循环依赖）
---@type table
local TitleMenu_
local function getTitleMenu()
    if not TitleMenu_ then TitleMenu_ = require("TitleMenu") end
    return TitleMenu_
end

--- 获取/缓存NanoVG贴图句柄（从 TitleMenu 复制，纯工具函数）
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

function P.StartPreview()
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
    if getTitleMenu().levelSelect_.uiRoot then
        getTitleMenu().levelSelect_.uiRoot:SetVisible(false)
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
        -- 应用旋转（编辑器角度为顺时针度数，Box2D 需要逆时针弧度 → 取反）
        if obj.rotation and obj.rotation ~= 0 then
            node.rotation2D = -obj.rotation
        end

        local body = node:CreateComponent("RigidBody2D")
        body.bodyType = BT_STATIC

        -- 根据 hasCollision 字段决定是否创建碰撞体（触发器默认无，执行器默认有）
        local wantCollision = obj.hasCollision
        if wantCollision == nil then
            wantCollision = (obj.type ~= "trigger")
        end
        if wantCollision then
            createCollisionShape(node, obj)
        end

        table.insert(previewNodes, node)
    end

    -- 创建玩家角色
    local playerNode = scene:CreateChild("PreviewPlayer")
    -- 确定玩家出生位置
    local spawnX = levelEditor_.worldW / 2
    local spawnY = levelEditor_.worldH * 0.8
    if levelEditor_.playerStartX and levelEditor_.playerStartY then
        -- 使用手动设置的初始位置（编辑器坐标Y-down → Box2D坐标Y-up）
        spawnX = levelEditor_.playerStartX
        spawnY = levelEditor_.worldH - levelEditor_.playerStartY
    else
        -- 自动：找到最高的地面/平台表面，把玩家放在其上方
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

    -- 同步编辑器参数到游戏状态
    S.playerOffsetY = levelEditor_.playerOffsetY or 0.0

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
    levelEditor_.previewItems = {}          -- 物品背包 { [itemName] = count }
    levelEditor_.previewVars = {}           -- 运行时变量存储 { [varName] = number } (set_var写入, param读取)
    levelEditor_.previewDestroyedSet = {}   -- 被 destroy_self 销毁的对象索引集合

    -- 动作节点运行时状态
    levelEditor_.previewDelayedQueues = {}  -- 延迟执行队列 { {actions, startIdx, timer, context, trigObjIdx} }
    levelEditor_.previewBreakContinuations = {} -- 中断续集 { [trigObjIdx] = {actions, startIdx, context} }
    levelEditor_.previewBreakReenterSet = {}    -- break_flow 要求玩家先离开再重入才可触发 { [trigIdx] = true }
    levelEditor_.previewMotions = {}        -- 移动对象任务队列
    levelEditor_.previewCameraFx = {}       -- 相机效果队列（抖动等）
    levelEditor_.previewCameraZoom = nil    -- 当前镜头缩放/平移任务
    levelEditor_.previewScreenFlash = nil   -- 全屏闪光 {color, duration, elapsed}
    levelEditor_.previewParticles = {}      -- 活跃粒子列表
    levelEditor_.previewSlowMotion = nil    -- 慢动作 {factor, duration, elapsed}
    levelEditor_.previewBaseOrthoSize = C.SCREEN_HEIGHT / C.PIXELS_PER_UNIT  -- 默认视野高度

    -- 重置对话框状态
    DialogManager.Reset()

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

    -- 创建预览UI（16:9 安全区域容器 + 右上角按钮）
    levelEditor_.previewUIRoot = UI.Panel {
        width = "100%", height = "100%",
        justifyContent = "center", alignItems = "center",
        pointerEvents = "box-none",
        children = {
            UI.Panel {
                width = 1920, height = 1080,
                pointerEvents = "box-none",
                overflow = "hidden",
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
                                onClick = function() P.StopPreview() end,
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
            },
        },
    }

    -- 预览期间切换UI根为轻量预览面板（主菜单UI层会覆盖NanoVG渲染）
    UI.SetRoot(levelEditor_.previewUIRoot)

    print("[PREVIEW] 预览启动 - " .. #objects .. " 个物件")
end

--- 停止预览模式
function P.StopPreview()
    if not levelEditor_.previewActive then return end

    -- 重置对话框
    DialogManager.Reset()

    -- 把编辑器UI从预览根摘出（避免被Destroy一并销毁）
    if levelEditor_.uiRoot and levelEditor_.previewUIRoot then
        levelEditor_.previewUIRoot:RemoveChild(levelEditor_.uiRoot)
    end

    -- 恢复UI根（预览时被替换了）
    if levelEditor_.openedFromGame and levelEditor_.editorGameRoot then
        UI.SetRoot(levelEditor_.editorGameRoot)
    elseif S.mainMenuUIRoot then
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

    -- 清除动作节点运行时状态
    levelEditor_.previewMotions = {}
    levelEditor_.previewObjFlipH = {}
    levelEditor_.previewObjOpacity = {}
    levelEditor_.previewObjLayerOpacity = {}
    levelEditor_.previewCameraFx = {}
    levelEditor_.previewCameraZoom = nil
    levelEditor_.previewScreenFlash = nil
    levelEditor_.previewParticles = {}
    levelEditor_.previewSlowMotion = nil

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
    S.hangCooldown = C.HANG_COOLDOWN_TIME
    S.wingShatterTimer = 0
    S.coyoteTimer = 0
    S.jumpBufferTimer = 0
    S.varJumpTimer = 0
    S.jumpWasCut = false
    S.activeJump = false
    S.currentAnim = C.ANIM_IDLE
    S.animFrame = 0
    S.animTimer = 0.0

    -- 恢复关卡选择UI可见性
    if getTitleMenu().levelSelect_.uiRoot then
        getTitleMenu().levelSelect_.uiRoot:SetVisible(true)
    end

    -- 直接游玩模式：不需要恢复编辑器UI，直接回到关卡选择
    if levelEditor_.playedDirectly then
        levelEditor_.playedDirectly = false
        print("[PREVIEW] 直接游玩结束，返回关卡选择")
    else
        -- 显示编辑器UI并挂回正确父节点
        if levelEditor_.uiRoot then
            levelEditor_.uiRoot:SetVisible(true)
            -- 编辑器UI可能还挂在已销毁的previewUIRoot上，重新挂载
            if levelEditor_.openedFromGame and levelEditor_.editorGameRoot then
                levelEditor_.editorGameRoot:AddChild(levelEditor_.uiRoot)
            elseif getTitleMenu().levelSelect_.uiRoot then
                getTitleMenu().levelSelect_.uiRoot:AddChild(levelEditor_.uiRoot)
            elseif S.mainMenuUIRoot then
                S.mainMenuUIRoot:AddChild(levelEditor_.uiRoot)
            end
        else
            getTitleMenu().BuildLevelEditorUI()
        end
        print("[PREVIEW] 预览结束")
    end
end

--- 预览中打开/关闭编辑器
-- ToggleEditorInPreview 已移除（预览模式不再提供编辑器入口，防止多次叠加）

--- 预览模式中刷新地形（编辑器修改后重新生成）
function P.RefreshPreviewTerrain()
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
        if obj.rotation and obj.rotation ~= 0 then
            node.rotation2D = -obj.rotation
        end

        local body = node:CreateComponent("RigidBody2D")
        body.bodyType = BT_STATIC

        local wantCollision = obj.hasCollision
        if wantCollision == nil then
            wantCollision = (obj.type ~= "trigger")
        end
        if wantCollision then
            createCollisionShape(node, obj)
        end

        table.insert(levelEditor_.previewNodes, node)
    end
    print("[PREVIEW] 地形已刷新")
end

--- 预览模式每帧更新（角色移动和相机）
function P.UpdatePreview(dt)
    if not levelEditor_.previewActive then return end

    -- 对话框计时更新（在物理/逻辑之前，使用真实dt）
    DialogManager.Update(dt)

    local playerBody = levelEditor_.previewPlayerBody
    local playerNode = levelEditor_.previewPlayerNode
    local cameraNode = levelEditor_.previewCameraNode
    if not playerBody or not playerNode or not cameraNode then return end

    -- 让 Combat 系统使用预览玩家节点（主循环被 showMainMenu 跳过）
    S.playerNode = playerNode

    -- 慢动作：缩放 dt
    if levelEditor_.previewSlowMotion then
        local sm = levelEditor_.previewSlowMotion
        sm.elapsed = (sm.elapsed or 0) + dt  -- 用真实dt计时
        if sm.elapsed >= sm.duration then
            levelEditor_.previewSlowMotion = nil
        else
            dt = dt * sm.factor
        end
    end

    -- 延迟动作队列更新
    P._updateDelayedQueues(dt)
    -- 运动动画更新
    P._updateMotions(dt)
    -- 粒子更新
    P._updateParticles(dt)

    -- ESC退出预览
    if input:GetKeyPress(KEY_ESCAPE) then
        P.StopPreview()
        return
    end

    -- Tab 切换碰撞箱可视化
    if input:GetKeyPress(KEY_TAB) then
        levelEditor_.previewShowColliders = not levelEditor_.previewShowColliders
    end

    -- H 切换坐标显示
    if input:GetKeyPress(KEY_H) then
        levelEditor_.previewShowCoords = not levelEditor_.previewShowCoords
    end

    -- 数字键1/2/3切换角色（受策略限制）
    if S.currentCharStrategy and S.currentCharStrategy.allowSwitch then
        local availableChars = S.currentCharStrategy.availableChars or {}
        local function isAvailable(ch)
            for _, v in ipairs(availableChars) do if v == ch then return true end end
            return false
        end
        if input:GetKeyPress(KEY_1) and isAvailable(1) then
            S.currentCharacter = 1
            S.currentAnim = C.ANIM_IDLE
            S.animFrame = 0
            S.animTimer = 0.0
        elseif input:GetKeyPress(KEY_2) and isAvailable(2) then
            S.currentCharacter = 2
            S.currentAnim = C.ANIM_IDLE
            S.animFrame = 0
            S.animTimer = 0.0
        elseif input:GetKeyPress(KEY_3) and isAvailable(3) then
            S.currentCharacter = 3
            S.currentAnim = C.ANIM_IDLE
            S.animFrame = 0
            S.animTimer = 0.0
        end
    end

    -- 角色移动输入
    local moveX = 0
    local speed = C.PLAYER_SPEED
    local jumpSpeed = C.PLAYER_JUMP_SPEED

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

    -- [Celeste优化1] 土狼时间（离开地面后仍可跳跃的宽限期）
    if levelEditor_.previewOnGround then
        S.coyoteTimer = C.COYOTE_TIME
    else
        S.coyoteTimer = math.max(0, S.coyoteTimer - dt)
    end

    -- 跳跃输入
    local jumpPressed = input:GetKeyPress(KEY_SPACE) or input:GetKeyPress(KEY_W) or input:GetKeyPress(KEY_UP) or input:GetKeyPress(KEY_K)
    local jumpHeld = input:GetKeyDown(KEY_SPACE) or input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP) or input:GetKeyDown(KEY_K)

    -- [Celeste优化2] 跳跃缓冲（落地前按键的有效窗口）
    if jumpPressed then
        S.jumpBufferTimer = C.JUMP_BUFFER_TIME
    else
        S.jumpBufferTimer = math.max(0, S.jumpBufferTimer - dt)
    end

    -- 跳跃条件：地面或土狼时间内 + 按键或缓冲有效
    local canJump = levelEditor_.previewOnGround or S.coyoteTimer > 0
    local wantsJump = jumpPressed or S.jumpBufferTimer > 0

    -- X键切换滞空滑翔功能
    if input:GetKeyPress(KEY_X) then
        P.hangGlideEnabled = not P.hangGlideEnabled
    end

    if canJump and wantsJump and not S.isCharging and not S.chargeReleased and math.abs(vel.y) < 2.0 then
        playerBody:SetLinearVelocity(Vector2(moveX, jumpSpeed))
        levelEditor_.previewOnGround = false
        levelEditor_.previewGroundContacts = 0
        S.coyoteTimer = 0              -- 消耗土狼时间，防止二段跳
        S.jumpBufferTimer = 0          -- 消耗跳跃缓冲
        S.activeJump = true
        S.jumpWasCut = false           -- 新跳跃重置截断标记
        S.varJumpTimer = C.VAR_JUMP_TIME  -- [Celeste优化3] 启动可变跳跃窗口
        S.hangCooldown = C.HANG_COOLDOWN_TIME  -- 防止同一次跳跃下落阶段自动触发滞空
        S.isHanging = false
        playerBody.gravityScale = 1.0
    elseif P.hangGlideStrategy({
        onGround = levelEditor_.previewOnGround,
        jumpHeld = jumpHeld,
        isHanging = S.isHanging,
        hangCooldown = S.hangCooldown,
        velY = playerBody:GetLinearVelocity().y,
        jumpWasCut = S.jumpWasCut,
    }) then
        -- 空中下落期间长按跳跃键：进入滞空
        S.isHanging = true
        S.hangCooldown = C.HANG_COOLDOWN_TIME
        playerBody.gravityScale = C.HANG_GRAVITY_SCALE
        local curVel = playerBody:GetLinearVelocity()
        playerBody:SetLinearVelocity(Vector2(curVel.x, curVel.y * 0.3))
    end

    -- [Celeste优化3] 可变跳跃高度：窗口内松手截断上升
    if S.varJumpTimer > 0 then
        S.varJumpTimer = S.varJumpTimer - dt
        if not jumpHeld then
            local curVel = playerBody:GetLinearVelocity()
            if curVel.y > 0 then
                playerBody:SetLinearVelocity(Vector2(curVel.x, curVel.y * C.JUMP_CUT_MULT))
            end
            S.varJumpTimer = 0
            S.jumpWasCut = true
            playerBody.gravityScale = C.JUMP_CUT_GRAVITY
        end
    end

    -- 落地时重置跳跃截断状态
    if S.jumpWasCut and levelEditor_.previewOnGround then
        S.jumpWasCut = false
        playerBody.gravityScale = 1.0
    end

    -- 滞空状态：松开跳跃键结束
    if S.isHanging then
        if not jumpHeld then
            S.isHanging = false
            playerBody.gravityScale = 1.0
            S.wingShatterTimer = C.WING_SHATTER_DURATION
        end
    end
    -- 光翼破碎动画计时
    if S.wingShatterTimer > 0 then
        S.wingShatterTimer = S.wingShatterTimer - dt
    end
    -- 滞空冷却
    if S.hangCooldown > 0 then
        S.hangCooldown = S.hangCooldown - dt
    end
    -- 落地时恢复重力
    if levelEditor_.previewOnGround and S.isHanging then
        S.isHanging = false
        playerBody.gravityScale = 1.0
        S.wingShatterTimer = C.WING_SHATTER_DURATION
    end

    -- 对话框点击拦截（优先于攻击等其他输入）
    local clickConsumed = false
    if input:GetMouseButtonPress(MOUSEB_LEFT) and DialogManager.HandleClick() then
        -- 点击被对话框消费，本帧不再触发攻击（防止关闭对话的那一击同帧放招）
        clickConsumed = true
    end

    -- 攻击（J键 / 鼠标左键）- 通过 Combat.CastSpell 触发投射物/近战
    -- 角色3没有攻击动作，跳过
    local attackPressed = input:GetKeyPress(KEY_J) or (input:GetMouseButtonPress(MOUSEB_LEFT) and not DialogManager.IsBlocking() and not clickConsumed)
    if S.currentCharacter ~= 3 and attackPressed and not S.isBlocking and not S.isCharging and not S.chargeReleased and not S.isAttacking then
        Combat.CastSpell()
    end
    -- 攻击计时（12帧动画，完毕后恢复）
    if S.isAttacking then
        S.attackTimer = S.attackTimer + dt
        if S.attackTimer >= C.SPRITE_FRAMES / C.ANIM_FPS_ATTACK then
            S.isAttacking = false
        end
    end

    -- 格挡（鼠标右键 / L键 长按）- 角色3无格挡
    local blockHeld = input:GetMouseButtonDown(MOUSEB_RIGHT) or input:GetKeyDown(KEY_L)
    if S.currentCharacter ~= 3 then
        if blockHeld and not S.isBlocking and not S.isAttacking and not S.isCharging then
            S.isBlocking = true
            S.currentAnim = C.ANIM_BLOCK
            S.animFrame = 0
            S.animTimer = 0.0
        elseif S.isBlocking and not blockHeld then
            S.isBlocking = false
        end
    end

    -- 蓄力（Q键长按）- 角色3无蓄力
    local chargeHeld = input:GetKeyDown(KEY_Q)
    local chargeStart = input:GetKeyPress(KEY_Q)
    if S.currentCharacter ~= 3 and chargeStart and not S.isCharging and not S.chargeReleased and not S.isAttacking and not S.isBlocking and not S.isDashing then
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

    -- 治愈（E键）- 角色3无治愈
    if S.healCooldownTimer > 0 then
        S.healCooldownTimer = S.healCooldownTimer - dt
    end
    local healPressed = input:GetKeyPress(KEY_E)
    if S.currentCharacter ~= 3 and healPressed and not S.isHealing and not S.isCharging and not S.chargeReleased and not S.isAttacking and not S.isBlocking and S.healCooldownTimer <= 0 then
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

    -- 蹲下（S键 / 下方向键 长按）- 角色3无蹲下
    local crouchHeld = input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_DOWN)
    local wasCrouching = S.isCrouching
    if S.currentCharacter ~= 3 and crouchHeld and levelEditor_.previewOnGround and not S.isCharging and not S.chargeReleased and not S.isHealing and not S.isAttacking then
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

        -- 检查是否存在 break_flow 续集：优先恢复续集执行而非重新执行整个策略
        local continuation = levelEditor_.previewBreakContinuations and levelEditor_.previewBreakContinuations[trigIdx]
        if continuation then
            levelEditor_.previewBreakContinuations[trigIdx] = nil
            print("[PREVIEW] fireTrigger: 恢复 break_flow 续集 (trigIdx=" .. trigIdx .. ")")
            P._executeActionSublist(continuation.actions, continuation.startIdx, continuation.context)
            return
        end

        -- 执行触发器策略 + 关联执行器
        -- 构建完整运行时上下文（对齐 RUNTIME_PARAMS 定义）
        local playerBody = levelEditor_.previewPlayerNode and levelEditor_.previewPlayerNode:GetComponent("RigidBody2D")
        local playerVel = playerBody and playerBody:GetLinearVelocity() or Vector2(0, 0)
        local stratCtx = {
            playerX = pCenterX,
            playerY = pCenterY,
            playerSpeedX = playerVel.x,
            playerSpeedY = playerVel.y,
            playerOnGround = levelEditor_.previewOnGround and 1 or 0,
            triggerX = trigCX,
            triggerY = trigCY,
            _trigObjIdx = trigIdx,
        }
        -- 注入持久化变量（set_var 写入的值，供 param 节点读取）
        local vars = levelEditor_.previewVars or {}
        for k, v in pairs(vars) do
            stratCtx[k] = v
        end
        local trigStratText = P._executeStrategy(obj, nil, stratCtx)
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
                    -- 仅执行执行器自身的策略（不重复执行触发器策略）
                    local exStratText = P._executeExecutorOnly(exObj, stratCtx)
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
    local destroyedSet = levelEditor_.previewDestroyedSet or {}
    for i, obj in ipairs(objects) do
        if destroyedSet[i] then goto continue_trig end
        if obj.type == "trigger" then
            local tm = obj.triggerMethod or "none"
            if tm ~= "none" then
                -- 触发器世界坐标中心（优先从 previewNode 获取实时位置，move_obj 会修改节点位置）
                local trigCX, trigCY
                local pNode = levelEditor_.previewNodes and levelEditor_.previewNodes[i]
                if pNode then
                    local pos = pNode:GetPosition2D()
                    trigCX = pos.x
                    trigCY = pos.y
                else
                    trigCX = obj.x + obj.w / 2
                    trigCY = worldH - obj.y - obj.h / 2
                end
                local trigHW = obj.w / 2
                local trigHH = obj.h / 2

                -- AABB 重叠检测
                local overlapX = (math.abs(pCenterX - trigCX) < (pHalfW + trigHW))
                local overlapY = (math.abs(pCenterY - trigCY) < (pHalfH + trigHH))
                local isOverlapping = overlapX and overlapY

                -- break_flow 重入机制：玩家离开触发器区域后清除重入标记（仅约束被动触发 touch/other）
                local reenterSet = levelEditor_.previewBreakReenterSet
                if not isOverlapping and reenterSet and reenterSet[i] then
                    reenterSet[i] = nil
                end

                -- 主动触发（interact/attack）不受重入限制，玩家按键即表示"再次触发"
                local needReenter = reenterSet and reenterSet[i]
                local isPassive = (tm == "touch" or tm == "other")


                if isOverlapping and not (needReenter and isPassive) then
                    if tm == "touch" then
                        if not levelEditor_.previewTriggeredSet[i] then
                            fireTrigger(i, obj, trigCX, trigCY, trigHH)
                        end
                    elseif tm == "interact" then
                        levelEditor_.previewInteractIdx = i
                        if input:GetKeyPress(KEY_F) and not levelEditor_.previewTriggeredSet[i] then
                            -- 主动触发时清除重入标记
                            if reenterSet then reenterSet[i] = nil end
                            fireTrigger(i, obj, trigCX, trigCY, trigHH)
                        end
                    elseif tm == "attack" then
                        if S.isAttacking and not levelEditor_.previewTriggeredSet[i] then
                            if reenterSet then reenterSet[i] = nil end
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
        ::continue_trig::
    end

    -- 相机跟随玩家
    local camPos = cameraNode.position
    local targetX = pPos.x
    local targetY = pPos.y

    -- 镜头缩放/平移更新（可能覆盖跟随目标）
    local camera = cameraNode:GetComponent("Camera")
    if camera then
        local zoomOverrideX, zoomOverrideY = P._updateCameraZoom(dt, cameraNode, camera, targetX, targetY)
        if zoomOverrideX then
            targetX, targetY = zoomOverrideX, zoomOverrideY
        end
    end

    -- 平滑跟随
    local lerpSpeed = 5.0
    local newX = camPos.x + (targetX - camPos.x) * math.min(1.0, lerpSpeed * dt)
    local newY = camPos.y + (targetY - camPos.y) * math.min(1.0, lerpSpeed * dt)

    -- 镜头范围框边界约束：相机边缘不超出范围框
    if levelEditor_.cameraBoundsEnabled and levelEditor_.cameraBounds then
        local cb = levelEditor_.cameraBounds
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

    -- 镜头抖动偏移
    local shakeOX, shakeOY = P._updateCameraFx(dt)
    cameraNode.position = Vector3(newX + shakeOX, newY + shakeOY, -10)

    -- 玩家掉出世界边界重置位置
    if pPos.y < -5 then
        playerNode:SetPosition2D(levelEditor_.worldW / 2, levelEditor_.worldH * 0.8)
        playerBody:SetLinearVelocity(Vector2(0, 0))
    end
end

--- 预览是否激活
function P.IsPreviewActive()
    return levelEditor_.previewActive
end

--- 预览刚退出（同帧标志，防止ESC连锁）
function P.JustStoppedPreview()
    return levelEditor_.justStoppedPreview == true
end

--- 预览物理碰撞处理（从main.lua的全局handler调用）
function P.HandlePreviewBeginContact(eventType, eventData)
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
            S.activeJump = false
            -- 落地时结束滞空
            if S.isHanging and levelEditor_.previewPlayerBody then
                S.isHanging = false
                levelEditor_.previewPlayerBody.gravityScale = 1.0
                S.wingShatterTimer = C.WING_SHATTER_DURATION
            end
            -- 落地时重置跳跃截断状态
            if S.jumpWasCut and levelEditor_.previewPlayerBody then
                S.jumpWasCut = false
                levelEditor_.previewPlayerBody.gravityScale = 1.0
            end
        end
    end
end

function P.HandlePreviewEndContact(eventType, eventData)
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

-- ============================================================================
-- 光翼特效（滞空滑翔 + 破碎动画）
-- ============================================================================
function P.DrawWingsEffect(vg, cx, cy, playerSize)
    local showWings = S.isHanging
    local showShatter = S.wingShatterTimer > 0

    if not showWings and not showShatter then return end

    nvgSave(vg)
    nvgGlobalAlpha(vg, 0.85)

    local dirSign = S.facingRight and -1 or 1
    local baseX = cx + dirSign * playerSize * 0.15
    local baseY = cy - playerSize * 0.25

    local feathers = {
        { angle = -30, lenScale = 0.85, widScale = 0.8, dist = 0.2 },
        { angle =   5, lenScale = 1.0,  widScale = 0.85, dist = 0.25 },
        { angle =  40, lenScale = 0.7,  widScale = 0.7, dist = 0.2 },
    }

    local baseLen = playerSize * 0.4
    local baseWid = playerSize * 0.08
    local isChar2 = (S.currentCharacter == 2)

    if showWings then
        local pulse = 1.0 + math.sin(os.clock() * 6.0) * 0.06
        local floatY = math.sin(os.clock() * 3.0) * 1.0
        baseY = baseY + floatY

        for _, f in ipairs(feathers) do
            local len = baseLen * f.lenScale * pulse
            local wid = baseWid * f.widScale * pulse
            local rad = math.rad(f.angle)
            local fcx = baseX + dirSign * math.cos(rad) * playerSize * f.dist
            local fcy = baseY + math.sin(rad) * playerSize * f.dist

            local cosA = math.cos(rad) * dirSign
            local sinA = math.sin(rad)
            local tipX = fcx + cosA * len * 0.6
            local tipY = fcy + sinA * len * 0.6
            local tailX = fcx - cosA * len * 0.4
            local tailY = fcy - sinA * len * 0.4
            local sideX1 = fcx + (-sinA) * wid
            local sideY1 = fcy + cosA * wid * dirSign
            local sideX2 = fcx - (-sinA) * wid
            local sideY2 = fcy - cosA * wid * dirSign

            nvgBeginPath(vg)
            nvgMoveTo(vg, tipX, tipY)
            nvgLineTo(vg, sideX1, sideY1)
            nvgLineTo(vg, tailX, tailY)
            nvgLineTo(vg, sideX2, sideY2)
            nvgClosePath(vg)
            if isChar2 then
                local grad = nvgLinearGradient(vg, tailX, tailY, tipX, tipY,
                    nvgRGBA(40, 5, 15, 255), nvgRGBA(220, 40, 40, 255))
                nvgFillPaint(vg, grad)
            else
                local grad = nvgLinearGradient(vg, tailX, tailY, tipX, tipY,
                    nvgRGBA(255, 140, 20, 255), nvgRGBA(255, 230, 50, 255))
                nvgFillPaint(vg, grad)
            end
            nvgFill(vg)
        end
    else
        -- 破碎动画
        local progress = 1.0 - (S.wingShatterTimer / C.WING_SHATTER_DURATION)
        local fadeAlpha = math.floor((1.0 - progress) * 255)
        local scatter = progress * playerSize * 0.6

        for _, f in ipairs(feathers) do
            local shrink = 1.0 - progress * 0.7
            local len = baseLen * f.lenScale * shrink
            local wid = baseWid * f.widScale * shrink
            local rad = math.rad(f.angle)
            local scatterX = dirSign * math.cos(rad) * scatter
            local scatterY = math.sin(rad) * scatter + progress * playerSize * 0.2
            local fcx = baseX + dirSign * math.cos(rad) * playerSize * f.dist + scatterX
            local fcy = baseY + math.sin(rad) * playerSize * f.dist + scatterY

            local cosA = math.cos(rad) * dirSign
            local sinA = math.sin(rad)
            local tipX = fcx + cosA * len * 0.6
            local tipY = fcy + sinA * len * 0.6
            local tailX = fcx - cosA * len * 0.4
            local tailY = fcy - sinA * len * 0.4
            local sideX1 = fcx + (-sinA) * wid
            local sideY1 = fcy + cosA * wid * dirSign
            local sideX2 = fcx - (-sinA) * wid
            local sideY2 = fcy - cosA * wid * dirSign

            nvgBeginPath(vg)
            nvgMoveTo(vg, tipX, tipY)
            nvgLineTo(vg, sideX1, sideY1)
            nvgLineTo(vg, tailX, tailY)
            nvgLineTo(vg, sideX2, sideY2)
            nvgClosePath(vg)
            if isChar2 then
                local grad = nvgLinearGradient(vg, tailX, tailY, tipX, tipY,
                    nvgRGBA(40, 5, 15, fadeAlpha), nvgRGBA(220, 40, 40, fadeAlpha))
                nvgFillPaint(vg, grad)
            else
                local grad = nvgLinearGradient(vg, tailX, tailY, tipX, tipY,
                    nvgRGBA(255, 140, 20, fadeAlpha), nvgRGBA(255, 230, 50, fadeAlpha))
                nvgFillPaint(vg, grad)
            end
            nvgFill(vg)
        end
    end

    nvgRestore(vg)
end

function P.DrawPreview(vg, physW, physH)
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

    -- 绘制背景图层（使用世界坐标，支持景深视差 + 动态效果）
    -- 渲染顺序：列表上方（索引小）的层在视觉上层 → 逆序渲染
    local bgLayers = levelEditor_.bgLayers or {}
    local effectTime = time.elapsedTime
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

                -- 应用动态效果
                local edx, edy, eScale, eAngle, eAlpha = 0, 0, 1, 0, 1
                if layer.effects and #layer.effects > 0 then
                    edx, edy, eScale, eAngle, eAlpha = EffectRegistry.Apply(layer.effects, effectTime)
                end
                local finalOpacity = opacity * eAlpha

                -- 景深视差：depth越大，随相机移动越慢（仅作用于X轴）
                local parallax = 1.0 / (1.0 + depth)
                local offsetX = camX * (1.0 - parallax)
                -- 世界坐标转屏幕（Y轴不受景深影响）+ 效果位移
                local sx1, sy1 = worldToScreen(lx - offsetX + edx, ly + lh + edy)
                local sx2, sy2 = worldToScreen(lx - offsetX + lw + edx, ly + edy)
                local drawW = (sx2 - sx1) * eScale
                local drawH = (sy2 - sy1) * eScale
                -- 缩放以中心为基准
                local cx = (sx1 + sx2) / 2
                local cy = (sy1 + sy2) / 2
                local finalX = cx - drawW / 2
                local finalY = cy - drawH / 2

                -- 旋转处理
                local hasAngle = (eAngle ~= 0)
                if hasAngle then
                    nvgSave(vg)
                    nvgTranslate(vg, cx, cy)
                    nvgRotate(vg, eAngle)
                    nvgTranslate(vg, -cx, -cy)
                end

                local paint = nvgImagePattern(vg, finalX, finalY, drawW, drawH, 0, bgImg, finalOpacity)
                nvgBeginPath(vg)
                nvgRect(vg, finalX, finalY, drawW, drawH)
                nvgFillPaint(vg, paint)
                nvgFill(vg)

                if hasAngle then
                    nvgRestore(vg)
                end
            end
        end
    end

    -- 绘制地形物件
    local ch = levelEditor_.chapterIdx
    local lv = levelEditor_.levelIdx
    local key = ch .. "_" .. lv
    local objects = levelEditor_.objects[key] or {}

    local effectTime = time.elapsedTime
    local destroyedSetDraw = levelEditor_.previewDestroyedSet or {}
    local previewNodesForDraw = levelEditor_.previewNodes or {}
    for i_obj, obj in ipairs(objects) do
        if destroyedSetDraw[i_obj] then goto continue_draw end
        -- 应用动态效果
        local edx, edy, eScale, eAngle, eAlpha, renderCtx = EffectRegistry.Apply(obj.effects, effectTime)
        -- move_obj 透明度覆盖
        if levelEditor_.previewObjOpacity and levelEditor_.previewObjOpacity[i_obj] then
            eAlpha = eAlpha * levelEditor_.previewObjOpacity[i_obj]
        end
        -- 优先从 previewNodes 获取实时位置（move_obj 会修改节点位置）
        local bx, by
        local pNode = previewNodesForDraw[i_obj]
        if pNode then
            local pos = pNode:GetPosition2D()
            bx = pos.x + edx
            by = pos.y + edy
        else
            bx = (obj.x + edx) + obj.w / 2
            by = levelEditor_.worldH - (obj.y + edy) - obj.h / 2
        end
        local sx, sy = worldToScreen(bx, by)
        local pw = obj.w * ppu * eScale
        local ph = obj.h * ppu * eScale

        -- 判断是否有可见贴图
        local hasVisibleTex = false
        if renderCtx and renderCtx.type == "spritesheet" and renderCtx.path ~= "" then
            hasVisibleTex = true
        elseif obj.texLayers and #obj.texLayers > 0 then
            for _, tl in ipairs(obj.texLayers) do
                if tl.visible ~= false and tl.path and tl.path ~= "" then
                    hasVisibleTex = true; break
                end
            end
        elseif obj.texture and obj.texture ~= "" then
            hasVisibleTex = true
        end

        -- 物件贴图（多图层，使用物件颜色染色）
        -- 渲染顺序：列表上方（索引小）的层在视觉上层 → 逆序渲染
        local prevObjCol = obj.color or {255, 255, 255, 255}
        local texLayers = obj.texLayers

        -- 如果有旋转（静态rotation + 动态效果eAngle + 运行时旋转），保存变换状态并绕物件中心旋转
        local objRotRad = (obj.rotation or 0) * math.pi / 180
        -- move_obj 运行时旋转：previewNode.rotation2D 是 Box2D 角度（= -editorDeg），需取反还原为编辑器角度
        if pNode then
            objRotRad = -pNode.rotation2D * math.pi / 180
        end
        local totalAngle = eAngle + objRotRad
        local hasRotation = (totalAngle ~= 0)
        if hasRotation then
            nvgSave(vg)
            nvgTranslate(vg, sx, sy)
            nvgRotate(vg, totalAngle)
            nvgTranslate(vg, -sx, -sy)
        end

        -- 朝向翻转（move_obj flipByMoveDir 功能）
        local objFlipH = levelEditor_.previewObjFlipH and levelEditor_.previewObjFlipH[i_obj]
        if objFlipH then
            nvgSave(vg)
            nvgTranslate(vg, sx, 0)
            nvgScale(vg, -1, 1)
            nvgTranslate(vg, -sx, 0)
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

        -- 序列帧效果渲染（renderCtx 优先级最高）
        if renderCtx and renderCtx.type == "spritesheet" and renderCtx.path ~= "" then
            local ssImg = GetNvgTexture(vg, renderCtx.path)
            if ssImg then
                local cols = renderCtx.cols or 1
                local rows = renderCtx.rows or 1
                local frameIdx = renderCtx.frameIndex or 0
                local col = frameIdx % cols
                local row = math.floor(frameIdx / cols)
                -- 整张图铺满 cols*pw × rows*ph，偏移使当前帧对齐绘制区域
                local sheetW = pw * cols
                local sheetH = ph * rows
                local offX = (sx - pw / 2) - col * pw
                local offY = (sy - ph / 2) - row * ph
                local alpha = eAlpha
                local objCol = prevObjCol
                local tintColor = nvgRGBA(objCol[1], objCol[2], objCol[3], math.floor((objCol[4] or 255) * alpha))
                local paint = nvgImagePatternTinted(vg, offX, offY, sheetW, sheetH, 0, ssImg, tintColor)
                nvgBeginPath(vg)
                nvgRect(vg, sx - pw / 2, sy - ph / 2, pw, ph)
                nvgFillPaint(vg, paint)
                nvgFill(vg)
            end
        elseif texLayers and #texLayers > 0 then
            for tli = #texLayers, 1, -1 do
                local tLayer = texLayers[tli]
                if tLayer.visible ~= false then
                    local texImg = GetNvgTexture(vg, tLayer.path)
                    if texImg then
                        local tScW = tLayer.scaleW or 1.0
                        local tScH = tLayer.scaleH or 1.0
                        -- 图层独立动态效果
                        local lEdx, lEdy, lEsc, lEang, lEalp = 0, 0, 1.0, 0, 1.0
                        if tLayer.effects and #tLayer.effects > 0 then
                            lEdx, lEdy, lEsc, lEang, lEalp = EffectRegistry.Apply(tLayer.effects, effectTime)
                        end
                        local drawW = pw * tScW * lEsc
                        local drawH = ph * tScH * lEsc
                        -- 位置偏移（像素单位，基于物件尺寸百分比，X右正 Y上正）+ 图层效果偏移
                        local offX = (tLayer.offsetX or 0) * pw + lEdx * pw
                        local offY = (tLayer.offsetY or 0) * ph + lEdy * ph
                        local layerCX = sx + offX
                        local layerCY = sy - offY
                        -- 图层透明度：优先使用按图层的运行时覆盖
                        local layerAlpha = tLayer.opacity or 1.0
                        if levelEditor_.previewObjLayerOpacity and levelEditor_.previewObjLayerOpacity[i_obj] then
                            local rtAlpha = levelEditor_.previewObjLayerOpacity[i_obj][tli]
                            if rtAlpha then layerAlpha = rtAlpha end
                        end
                        local alpha = layerAlpha * eAlpha * lEalp
                        local tintColor = nvgRGBA(prevObjCol[1], prevObjCol[2], prevObjCol[3], math.floor((prevObjCol[4] or 255) * alpha))
                        -- 贴图独立旋转（静态 + 效果角度）
                        local tRot = (tLayer.rotation or 0) * math.pi / 180 + lEang
                        if tRot ~= 0 then
                            nvgSave(vg)
                            nvgTranslate(vg, layerCX, layerCY)
                            nvgRotate(vg, tRot)
                            nvgTranslate(vg, -layerCX, -layerCY)
                        end
                        local tPaint = nvgImagePatternTinted(vg, layerCX - drawW/2, layerCY - drawH/2, drawW, drawH, 0, texImg, tintColor)
                        nvgBeginPath(vg)
                        nvgRect(vg, layerCX - drawW/2, layerCY - drawH/2, drawW, drawH)
                        nvgFillPaint(vg, tPaint)
                        nvgFill(vg)
                        if tRot ~= 0 then
                            nvgRestore(vg)
                        end
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
                local baseAlpha = (prevObjCol[4] or 255) * eAlpha
                local tintColor = nvgRGBA(prevObjCol[1], prevObjCol[2], prevObjCol[3], math.floor(baseAlpha))
                local tPaint = nvgImagePatternTinted(vg, sx - drawW/2, sy - drawH/2, drawW, drawH, 0, texImg, tintColor)
                nvgBeginPath(vg)
                nvgRect(vg, sx - drawW/2, sy - drawH/2, drawW, drawH)
                nvgFillPaint(vg, tPaint)
                nvgFill(vg)
            end
        end

        if objFlipH then
            nvgRestore(vg)
        end
        if hasRotation then
            nvgRestore(vg)
        end

        -- 边框（仅无贴图时显示）
        if not hasVisibleTex then
            nvgStrokeColor(vg, nvgRGBA(200, 200, 200, 80))
            nvgStrokeWidth(vg, 1)
            nvgStroke(vg)
        end
        ::continue_draw::
    end

    -- 绘制玩家角色（完整序列帧 + 特效）
    local pPos = playerNode.position2D
    local px, py = worldToScreen(pPos.x, pPos.y)
    local playerR = 0.4 * ppu

    -- 选择当前序列帧图片
    local img = S.imgIdle
    if S.currentCharacter == 3 then
        img = S.img3Idle
        if S.currentAnim == C.ANIM_RUN then img = S.img3Run
        elseif S.currentAnim == C.ANIM_JUMP then img = S.img3Jump
        elseif S.currentAnim == C.ANIM_ATTACK then img = S.img3Attack
        elseif S.currentAnim == C.ANIM_BLOCK then img = S.img3Block
        elseif S.currentAnim == C.ANIM_CHARGE then img = S.img3Charge
        elseif S.currentAnim == C.ANIM_HEAL then img = S.img3Heal
        elseif S.currentAnim == C.ANIM_CROUCH then img = S.img3Crouch
        elseif S.currentAnim == C.ANIM_CROUCH_WALK then img = S.img3CrouchWalk
        elseif S.currentAnim == C.ANIM_HIT then img = S.img3Hit
        end
    elseif S.currentCharacter == 2 then
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
    local renderScale = levelEditor_.playerRenderScale or 1.0
    local playerDrawSize = C.PLAYER_RADIUS * animScale * renderScale * ppu

    local frame = S.animFrame
    -- 蹲下帧映射（角色3暂无蹲下动画，跳过）
    if S.currentAnim == C.ANIM_CROUCH and S.currentCharacter ~= 3 then
        local map = (S.currentCharacter == 2) and C.CROUCH_FRAME_MAP_2 or C.CROUCH_FRAME_MAP_1
        local idx = math.max(1, math.min(S.animFrame, #map))
        frame = map[idx]
    end
    -- 角色1蹲走帧
    if S.currentAnim == C.ANIM_CROUCH_WALK and S.currentCharacter == 1 then
        local crouchWalkFrames = { 6, 2 }
        frame = crouchWalkFrames[(S.animFrame % 2) + 1]
    end

    -- 光翼特效（滞空/破碎动画）
    P.DrawWingsEffect(vg, px, py, playerDrawSize)

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
        local oY = (crop.offsetY or 0.6) + (levelEditor_.playerOffsetY or 0.0)
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

    -- 绘制光的碎片（图片特效，左/正面/右 顺序排列）
    local fragmentCount = (levelEditor_.previewItems or {})["light_fragment"] or 0
    if fragmentCount > 0 then
        local fragTime = time.elapsedTime
        local fragImg = GetNvgTexture(vg, "image/光之碎片持有特效.png")
        -- 排列位置：1=左, 2=正面(中间), 3=右侧
        local fragPositions = {}
        if fragmentCount >= 1 then
            fragPositions[1] = { dx = -1.2, dy = 0.8 }   -- 左侧
        end
        if fragmentCount >= 2 then
            fragPositions[2] = { dx = 0.0, dy = 1.2 }    -- 正面（头顶上方）
        end
        if fragmentCount >= 3 then
            fragPositions[3] = { dx = 1.2, dy = 0.8 }    -- 右侧
        end
        for fi, fp in ipairs(fragPositions) do
            -- 浮动动画：每个碎片相位不同
            local phase = fragTime * 2.5 + fi * 2.09
            local floatY = math.sin(phase) * 0.15
            local floatX = math.cos(phase * 0.7) * 0.05
            -- 脉冲缩放动画
            local pulse = 1.0 + math.sin(fragTime * 3.0 + fi * 1.5) * 0.08
            local fsx, fsy = worldToScreen(pPos.x + fp.dx + floatX, pPos.y + fp.dy + floatY)
            local fragSize = 0.7 * ppu * pulse
            nvgSave(vg)
            if fragImg then
                -- 用图片纹理绘制
                local paint = nvgImagePattern(vg, fsx - fragSize/2, fsy - fragSize/2, fragSize, fragSize, 0, fragImg, 1.0)
                nvgBeginPath(vg)
                nvgRect(vg, fsx - fragSize/2, fsy - fragSize/2, fragSize, fragSize)
                nvgFillPaint(vg, paint)
                nvgFill(vg)
            else
                -- fallback: 程序化四角星
                local ds = fragSize * 0.5
                nvgBeginPath(vg)
                nvgMoveTo(vg, fsx, fsy - ds)          -- 上
                nvgLineTo(vg, fsx + ds * 0.3, fsy - ds * 0.3)
                nvgLineTo(vg, fsx + ds, fsy)          -- 右
                nvgLineTo(vg, fsx + ds * 0.3, fsy + ds * 0.3)
                nvgLineTo(vg, fsx, fsy + ds)          -- 下
                nvgLineTo(vg, fsx - ds * 0.3, fsy + ds * 0.3)
                nvgLineTo(vg, fsx - ds, fsy)          -- 左
                nvgLineTo(vg, fsx - ds * 0.3, fsy - ds * 0.3)
                nvgClosePath(vg)
                local gradPaint = nvgLinearGradient(vg, fsx, fsy - ds, fsx, fsy + ds,
                    nvgRGBA(255, 180, 50, 230), nvgRGBA(255, 120, 20, 230))
                nvgFillPaint(vg, gradPaint)
                nvgFill(vg)
            end
            nvgRestore(vg)
        end
    end

    -- 碰撞箱可视化（Tab 键切换显示）
    if levelEditor_.previewShowColliders then
        -- 玩家身体碰撞体（蹲下0.8×1.2 center=0.2, 站立0.8×1.6 center=0.4）
        local boxW = 0.8 * ppu
        local boxH, boxCenterOff
        if S.isCrouching then
            boxH = 1.2 * ppu
            boxCenterOff = 0.2
        else
            boxH = 1.6 * ppu
            boxCenterOff = 0.4
        end
        local boxCenterY = py - boxCenterOff * ppu
        nvgBeginPath(vg)
        nvgRect(vg, px - boxW/2, boxCenterY - boxH/2, boxW, boxH)
        nvgStrokeColor(vg, nvgRGBA(0, 255, 100, 220))
        nvgStrokeWidth(vg, 3)
        nvgStroke(vg)

        -- 脚底传感器（圆形 radius=0.28, center=(0, -0.36)）
        local footY = py + 0.36 * ppu
        nvgBeginPath(vg)
        nvgCircle(vg, px, footY, 0.28 * ppu)
        nvgStrokeColor(vg, nvgRGBA(255, 200, 0, 200))
        nvgStrokeWidth(vg, 2.5)
        nvgStroke(vg)

        -- 物件碰撞箱（遍历所有有物理碰撞的物件）
        for _, obj in ipairs(objects) do
            if obj.type ~= "trigger" then
                local obx = obj.x + obj.w / 2
                local oby = levelEditor_.worldH - obj.y - obj.h / 2
                local osx, osy = worldToScreen(obx, oby)
                local opw = obj.w * ppu
                local oph = obj.h * ppu
                nvgBeginPath(vg)
                nvgRect(vg, osx - opw/2, osy - oph/2, opw, oph)
                nvgStrokeColor(vg, nvgRGBA(0, 200, 80, 180))
                nvgStrokeWidth(vg, 3)
                nvgStroke(vg)
            end
        end
    end



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

    -- 左上角：角色当前坐标（H键切换）
    if levelEditor_.previewShowCoords ~= false then
        local coordY = levelEditor_.previewOnGround and 46 or 30
        nvgFontSize(vg, 18)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 230))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        local cpx = pPos.x
        local cpy = pPos.y
        nvgText(vg, 10, coordY, string.format("坐标: (%.2f, %.2f)", cpx, cpy))
    end



    -- 右下角：滞空滑翔状态 + 碎片数
    do
        local fragments = (levelEditor_.previewItems or {})["light_fragment"] or 0
        local canGlide = P.hangGlideEnabled and fragments >= 3
        local label = canGlide and "滑翔: ON" or "滑翔: OFF"
        if P.hangGlideEnabled and fragments < 3 then
            label = string.format("碎片: %d/3", fragments)
        end
        local bgAlpha = 180
        local textR, textG, textB = 100, 220, 255
        if not canGlide then
            textR, textG, textB = 180, 180, 180
        end
        if P.hangGlideEnabled and fragments < 3 then
            textR, textG, textB = 255, 200, 50  -- 橙黄色提示收集中
        end
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, 14)
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
        -- 背景圆角矩形
        local tw = 90
        local th = 24
        local rx = physW - 10
        local ry = physH - 10
        nvgBeginPath(vg)
        nvgRoundedRect(vg, rx - tw, ry - th, tw, th, 6)
        nvgFillColor(vg, nvgRGBA(0, 0, 0, bgAlpha))
        nvgFill(vg)
        -- 文字
        nvgFillColor(vg, nvgRGBA(textR, textG, textB, 240))
        nvgText(vg, rx - 8, ry - 5, label)
        -- 快捷键提示
        nvgFontSize(vg, 10)
        nvgFillColor(vg, nvgRGBA(180, 180, 180, 160))
        nvgTextAlign(vg, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
        nvgText(vg, rx - 8, ry - th - 2, "[X] 切换")
    end

    -- 绘制粒子效果
    local particles = levelEditor_.previewParticles or {}
    if #particles > 0 then
        for _, p in ipairs(particles) do
            local sx, sy = worldToScreen(p.x, p.y)
            local lifeRatio = p.life / (p.maxLife or 1.0)
            local alpha = math.max(0, math.min(255, math.floor(lifeRatio * 255)))
            local radius = (p.size or 0.1) * ppu
            nvgBeginPath(vg)
            nvgCircle(vg, sx, sy, math.max(2, radius))
            nvgFillColor(vg, nvgRGBA(255, 200, 60, alpha))
            nvgFill(vg)
        end
    end

    -- 屏幕闪光叠加层
    local flash = levelEditor_.previewScreenFlash
    if flash then
        flash.elapsed = (flash.elapsed or 0) + (time.timeStep or 0.016)
        local progress = flash.elapsed / flash.duration
        if progress >= 1.0 then
            levelEditor_.previewScreenFlash = nil
        else
            local flashAlpha = math.floor((1.0 - progress) * 180)
            local fc = FLASH_COLOR_MAP[flash.color] or FLASH_COLOR_MAP.white
            nvgBeginPath(vg)
            nvgRect(vg, 0, 0, physW, physH)
            nvgFillColor(vg, nvgRGBA(fc[1], fc[2], fc[3], flashAlpha))
            nvgFill(vg)
        end
    end

    -- 对话框渲染已迁移至 DialogView（urhox-libs/UI overlay，自动渲染于最上层）
end

-- ============================================================================
-- 动作节点运行时更新
-- ============================================================================

--- 每帧更新移动对象任务
--- 执行动作列表（从 startIdx 开始），遇到 delay 节点时打包剩余动作到延迟队列
--- @param actions table 完整动作列表
--- @param startIdx number 起始索引（1-based）
--- @param context table|nil 运行时上下文
function P._executeActionSublist(actions, startIdx, context)
    local items = levelEditor_.previewItems or {}
    local trigObjIdx = context and context._trigObjIdx

    for i = startIdx, #actions do
        local act = actions[i]
        local node = act.node or {}

        -- 遇到 dialog 节点：显示对话框 + 阻塞后续动作，对话关闭后恢复执行
        if act.nodeType == "dialog" then
            local remainActions = actions
            local nextIdx = i + 1
            local ctx = context
            DialogManager.Show(node, function()
                -- 对话框关闭回调：恢复执行后续节点
                if nextIdx <= #remainActions then
                    P._executeActionSublist(remainActions, nextIdx, ctx)
                end
            end)
            break  -- 中断当前循环，等对话关闭后回调恢复
        end

        -- 遇到 delay 节点：将后续动作压入延迟队列，中断当前循环
        if act.nodeType == "delay" then
            local delaySec = tonumber(node.delaySeconds) or 1.0
            if i < #actions then
                table.insert(levelEditor_.previewDelayedQueues, {
                    actions = actions,
                    startIdx = i + 1,
                    timer = delaySec,
                    context = context,
                })
            end
            break
        end

        -- 遇到 break_flow 节点：将后续动作存入续集表，重置触发器，中断当前循环
        if act.nodeType == "break_flow" then
            if trigObjIdx and i < #actions then
                levelEditor_.previewBreakContinuations[trigObjIdx] = {
                    actions = actions,
                    startIdx = i + 1,
                    context = context,
                }
                -- 重新激活触发器，使其可以再次被触发以恢复执行
                if levelEditor_.previewTriggeredSet then
                    levelEditor_.previewTriggeredSet[trigObjIdx] = nil
                end
                -- 标记需要玩家先离开触发器区域再重新进入才可触发（避免 touch 模式下立刻重触发）
                levelEditor_.previewBreakReenterSet[trigObjIdx] = true
                print("[PREVIEW] break_flow: 中断执行, trigIdx=" .. trigObjIdx .. ", continuation startIdx=" .. (i+1))
            end
            break
        end

        -- 正常执行动作副作用
        if act.nodeType == "modify_item" then
            local name = node.itemName or "light_fragment"
            local op = node.itemOp or "add"
            local amount = node.itemAmount or 1
            if type(amount) ~= "number" then amount = tonumber(amount) or 1 end
            local cur = items[name] or 0
            if op == "add" then
                items[name] = cur + amount
            elseif op == "remove" then
                items[name] = math.max(0, cur - amount)
            elseif op == "set" then
                items[name] = amount
            end
            if name == "light_fragment" then
                items[name] = math.min(3, math.max(0, items[name]))
            end
        elseif act.nodeType == "set_ability" then
            local ability = node.abilityName or "hang_glide"
            local enabled = node.abilityEnabled
            if enabled == nil then enabled = true end
            if ability == "hang_glide" then
                P.hangGlideEnabled = enabled
            end
        elseif act.nodeType == "destroy_self" then
            if trigObjIdx then
                levelEditor_.previewDestroyedSet[trigObjIdx] = true
            end
        elseif act.nodeType == "move_obj" then
            local targetIdx = tonumber(node.targetObjIdx) or 0
            -- targetObjIdx==0 表示"自身"（触发器物件）
            if targetIdx == 0 and trigObjIdx and trigObjIdx >= 1 then
                targetIdx = trigObjIdx
            end
            if targetIdx >= 1 then
                local targetNode = levelEditor_.previewNodes[targetIdx]
                if targetNode then
                    local pos = targetNode:GetPosition2D()
                    local pathPoints = node.pathPoints or {}
                    if #pathPoints == 0 then
                        pathPoints = { { x = 2, y = 0 } }
                    end

                    -- "无"路径类型：瞬移到目标位置，不做动画
                    local pathType = node.pathType or "linear"
                    if pathType == "none" then
                        local destX = node.teleportX or pos.x
                        local destY = node.teleportY or pos.y
                        -- 切换为运动学体以允许设置位置
                        local body = targetNode:GetComponent("RigidBody2D")
                        local wasStatic = false
                        if body and body.bodyType == BT_STATIC then
                            body.bodyType = BT_KINEMATIC
                            wasStatic = true
                        end
                        targetNode:SetPosition2D(destX, destY)
                        if body then body:SetAwake(true) end
                        if wasStatic and body then body.bodyType = BT_STATIC end
                        -- 瞬移也处理透明度（立即到达目标值）
                        local opacityMode = node.opacityMode or "whole"
                        local opacityTarget = node.opacityTarget
                        if opacityMode == "layers" then
                            local layerTargets = node.opacityLayerTargets or {}
                            if #layerTargets > 0 or next(layerTargets) then
                                if not levelEditor_.previewObjLayerOpacity then levelEditor_.previewObjLayerOpacity = {} end
                                if not levelEditor_.previewObjLayerOpacity[targetIdx] then levelEditor_.previewObjLayerOpacity[targetIdx] = {} end
                                for li, tgt in pairs(layerTargets) do
                                    local liNum = tonumber(li) or li
                                    levelEditor_.previewObjLayerOpacity[targetIdx][liNum] = tgt
                                end
                            end
                        else
                            if opacityTarget ~= nil then
                                if not levelEditor_.previewObjOpacity then levelEditor_.previewObjOpacity = {} end
                                levelEditor_.previewObjOpacity[targetIdx] = opacityTarget
                            end
                        end
                        goto move_obj_done
                    end

                    local easeName = node.moveEase or "easeOut"
                    -- 透明度动画：记录起始透明度
                    local opacityMode = node.opacityMode or "whole"
                    local opacityTarget = node.opacityTarget
                    local opacityDuration = node.opacityDuration or 0.5
                    local hasOpacity = false
                    local currentOpacity = 1.0
                    local layerOpacityFrom = nil
                    local layerOpacityTargets = nil

                    if opacityMode == "layers" then
                        -- 按图层模式
                        local layerTargets = node.opacityLayerTargets or {}
                        if #layerTargets > 0 or next(layerTargets) then
                            hasOpacity = true
                            if not levelEditor_.previewObjLayerOpacity then levelEditor_.previewObjLayerOpacity = {} end
                            if not levelEditor_.previewObjLayerOpacity[targetIdx] then levelEditor_.previewObjLayerOpacity[targetIdx] = {} end
                            layerOpacityFrom = {}
                            layerOpacityTargets = {}
                            for li, tgt in pairs(layerTargets) do
                                local liNum = tonumber(li) or li
                                layerOpacityFrom[liNum] = levelEditor_.previewObjLayerOpacity[targetIdx][liNum] or 1.0
                                layerOpacityTargets[liNum] = tgt
                            end
                        end
                    else
                        -- 整体模式（向后兼容）
                        hasOpacity = (opacityTarget ~= nil and opacityTarget ~= 1.0) or (opacityDuration > 0 and opacityTarget ~= nil)
                        if hasOpacity then
                            if not levelEditor_.previewObjOpacity then levelEditor_.previewObjOpacity = {} end
                            currentOpacity = levelEditor_.previewObjOpacity[targetIdx] or 1.0
                        end
                    end

                    table.insert(levelEditor_.previewMotions, {
                        node = targetNode,
                        objIdx = targetIdx,
                        pathEvaluator = createPathEvaluator(
                            node.pathType or "linear",
                            pathPoints,
                            pos.x, pos.y
                        ),
                        easeFn = EASE_FNS[easeName] or EASE_FNS.easeOut,
                        duration = node.moveDuration or 1.0,
                        roundTrip = node.moveRoundTrip or false,
                        loop = node.moveLoop or false,
                        repeatTotal = node.moveRepeatCount or 1,
                        rotationDeg = node.rotationDeg or 0,
                        flipByMoveDir = node.flipByMoveDir or false,
                        -- 透明度动画
                        opacityMode = opacityMode,
                        opacityFrom = currentOpacity,
                        opacityTarget = opacityTarget or 1.0,
                        opacityDuration = opacityDuration,
                        opacityElapsed = 0,
                        hasOpacity = hasOpacity,
                        -- 按图层透明度
                        layerOpacityFrom = layerOpacityFrom,
                        layerOpacityTargets = layerOpacityTargets,
                        elapsed = 0,
                        phase = "forward",
                        repeatDone = 0,
                        finished = false,
                        originX = pos.x,
                        originY = pos.y,
                        prevX = pos.x,
                        originRotation = targetNode.rotation2D or 0,
                    })
                    ::move_obj_done::
                end
            end
        elseif act.nodeType == "play_fx" then
            P._executeFx(node.fxType or "sound", node, context)
        elseif act.nodeType == "camera_zoom" then
            local camera = levelEditor_.previewCameraNode and levelEditor_.previewCameraNode:GetComponent("Camera")
            if camera then
                local baseSize = levelEditor_.previewBaseOrthoSize or camera.orthoSize
                local toSize = baseSize / (node.zoomScale or 1.0)
                local easeName = node.zoomEase or "easeOut"
                local camPos = levelEditor_.previewCameraNode.position
                levelEditor_.previewCameraZoom = {
                    phase = "zoom_in",  -- 状态机阶段: zoom_in → holding → restore → done
                    fromOrthoSize = camera.orthoSize,
                    toOrthoSize = toSize,
                    duration = node.zoomDuration or 0.5,
                    easeFn = EASE_FNS[easeName] or EASE_FNS.easeOut,
                    elapsed = 0,
                    usePan = node.zoomUsePan or false,
                    fromCenterX = camPos.x,
                    fromCenterY = camPos.y,
                    toCenterX = node.zoomCenterX or 15.0,
                    toCenterY = node.zoomCenterY or 8.75,
                    finished = false,
                    -- 自动恢复相关
                    autoRestore = node.zoomAutoRestore or false,
                    holdDuration = node.zoomHoldDuration or 3.0,
                    holdElapsed = 0,
                    restoreDuration = node.zoomRestoreDuration or 0.5,
                    restoreEaseFn = EASE_FNS[node.zoomRestoreEase or "easeOut"] or EASE_FNS.easeOut,
                    restoreElapsed = 0,
                    -- 恢复目标（zoom_in 完成后填充）
                    restoreFromOrthoSize = nil,
                    restoreToOrthoSize = camera.orthoSize,
                    restoreFromCenterX = nil,
                    restoreFromCenterY = nil,
                    restoreToCenterX = camPos.x,
                    restoreToCenterY = camPos.y,
                }
            end
        elseif act.nodeType == "teleport_player" then
            local tx = tonumber(node.targetX) or 15.0
            local ty = tonumber(node.targetY) or 8.0
            -- targetX/Y 直接使用游戏坐标（Y-up），与 camera_zoom 一致
            local playerNode = levelEditor_.previewPlayerNode
            if playerNode then
                playerNode:SetPosition2D(tx, ty)
                local body = playerNode:GetComponent("RigidBody2D")
                if body then
                    body:SetLinearVelocity(Vector2(0, 0))
                    body:SetAwake(true)
                end
                print("[PREVIEW] teleport_player: 传送到 (" .. tx .. ", " .. ty .. ")")
            end

        elseif act.nodeType == "reset_trigger" then
            local targetIdx = node.resetTargetIdx or 0
            -- targetIdx==0 表示"自身"（触发此策略的触发器）
            if targetIdx == 0 and trigObjIdx and trigObjIdx >= 1 then
                targetIdx = trigObjIdx
            end
            if targetIdx > 0 then
                local objects = levelEditor_.objects[levelEditor_.chapterIdx .. "_" .. levelEditor_.levelIdx] or {}
                local targetObj = objects[targetIdx]
                if targetObj and targetObj.type == "trigger" then
                    -- 重置已触发标志（正确的表是 previewTriggeredSet）
                    if levelEditor_.previewTriggeredSet then
                        levelEditor_.previewTriggeredSet[targetIdx] = nil
                    end
                    -- 同时清除 break_flow 续集和重入标记（重置意味着下次触发应从头执行）
                    if levelEditor_.previewBreakContinuations then
                        levelEditor_.previewBreakContinuations[targetIdx] = nil
                    end
                    if levelEditor_.previewBreakReenterSet then
                        levelEditor_.previewBreakReenterSet[targetIdx] = nil
                    end
                    -- 可选修改触发方式
                    local method = node.resetMethod or "keep"
                    if method ~= "keep" then
                        targetObj.triggerMethod = method
                    end
                    print("[PREVIEW] reset_trigger: 已重置触发器 #" .. targetIdx .. " (方式=" .. method .. ")")
                end
            end

        elseif act.nodeType == "set_var" then
            -- 设置运行时变量（持久化到 previewVars，供 param 节点读取）
            local vars = levelEditor_.previewVars or {}
            local varName = node.varName or "custom1"
            local mode = node.setMode or "set"
            local newVal = tonumber(node.newValue) or 0
            local oldVal = vars[varName] or 0
            if mode == "set" then
                vars[varName] = newVal
            elseif mode == "add" then
                vars[varName] = oldVal + newVal
            elseif mode == "mul" then
                vars[varName] = oldVal * newVal
            end
            levelEditor_.previewVars = vars
            print("[PREVIEW] set_var: " .. varName .. " " .. mode .. " " .. tostring(newVal) .. " => " .. tostring(vars[varName]))
        end
    end
    levelEditor_.previewItems = items
end

--- 每帧更新延迟动作队列（倒计时 → 到期时执行）
function P._updateDelayedQueues(dt)
    local queues = levelEditor_.previewDelayedQueues
    if not queues or #queues == 0 then return end

    -- 从末尾遍历以便安全移除
    for i = #queues, 1, -1 do
        local q = queues[i]
        q.timer = q.timer - dt
        if q.timer <= 0 then
            table.remove(queues, i)
            -- 执行到期的动作（可能递归产生新的延迟条目）
            P._executeActionSublist(q.actions, q.startIdx, q.context)
        end
    end
end

function P._updateMotions(dt)
    local motions = levelEditor_.previewMotions
    if not motions then return end
    for i = #motions, 1, -1 do
        local m = motions[i]
        if m.finished then
            -- 运动结束，恢复刚体类型
            if m._wasStatic and m.node then
                local body = m.node:GetComponent("RigidBody2D")
                if body then body.bodyType = BT_STATIC end
            end
            table.remove(motions, i)
            goto continue_motion
        end

        m.elapsed = m.elapsed + dt
        local t = math.min(1.0, m.elapsed / m.duration)
        local easedT = m.easeFn(t)

        -- 方向处理
        local pathT = (m.phase == "backward") and (1.0 - easedT) or easedT
        local wx, wy = m.pathEvaluator(pathT)

        -- 设置节点位置（kinematic body 才能通过代码移动）
        if m.node then
            local body = m.node:GetComponent("RigidBody2D")
            if body and body.bodyType == BT_STATIC then
                body.bodyType = BT_KINEMATIC  -- 临时切为运动学体
                m._wasStatic = true
            end
            m.node:SetPosition2D(wx, wy)
            if body then body:SetAwake(true) end
        end

        -- 朝向跟随移动方向：X正向不翻转，X负向翻转贴图
        if m.flipByMoveDir and m.objIdx then
            local dx = wx - m.prevX
            if math.abs(dx) > 0.001 then
                if not levelEditor_.previewObjFlipH then levelEditor_.previewObjFlipH = {} end
                levelEditor_.previewObjFlipH[m.objIdx] = (dx < 0)
            end
            m.prevX = wx
        end

        -- 旋转叠加（基于单程进度线性增长）
        if m.rotationDeg ~= 0 and m.node then
            local rotProgress = easedT
            m.node.rotation2D = m.originRotation - (m.rotationDeg * rotProgress)
        end

        -- 透明度动画（独立计时，不受路径/旋转阶段影响）
        if m.hasOpacity and m.objIdx then
            m.opacityElapsed = m.opacityElapsed + dt
            local ot = 1.0
            if m.opacityDuration > 0 then
                ot = math.min(1.0, m.opacityElapsed / m.opacityDuration)
            end
            if m.opacityMode == "layers" and m.layerOpacityFrom and m.layerOpacityTargets then
                -- 按图层独立透明度
                if not levelEditor_.previewObjLayerOpacity then levelEditor_.previewObjLayerOpacity = {} end
                if not levelEditor_.previewObjLayerOpacity[m.objIdx] then levelEditor_.previewObjLayerOpacity[m.objIdx] = {} end
                for li, fromVal in pairs(m.layerOpacityFrom) do
                    local toVal = m.layerOpacityTargets[li] or 1.0
                    levelEditor_.previewObjLayerOpacity[m.objIdx][li] = fromVal + (toVal - fromVal) * ot
                end
            else
                -- 整体透明度（向后兼容）
                local newAlpha = m.opacityFrom + (m.opacityTarget - m.opacityFrom) * ot
                if not levelEditor_.previewObjOpacity then levelEditor_.previewObjOpacity = {} end
                levelEditor_.previewObjOpacity[m.objIdx] = newAlpha
            end
        end

        -- 阶段切换
        if t >= 1.0 then
            if m.roundTrip and m.phase == "forward" then
                m.phase = "backward"
                m.elapsed = 0
            else
                m.repeatDone = m.repeatDone + 1
                if m.loop or m.repeatDone < m.repeatTotal then
                    m.phase = "forward"
                    m.elapsed = 0
                else
                    m.finished = true
                end
            end
        end
        ::continue_motion::
    end
end

--- 每帧更新镜头缩放/平移
--- @param dt number
--- @param cameraNode userdata
--- @param camera userdata
--- @param normalX number 正常跟随目标X
--- @param normalY number 正常跟随目标Y
--- @return number, number 最终相机目标坐标
function P._updateCameraZoom(dt, cameraNode, camera, normalX, normalY)
    local zoom = levelEditor_.previewCameraZoom
    if not zoom then return normalX, normalY end

    local phase = zoom.phase or "zoom_in"
    local targetX, targetY = normalX, normalY

    if phase == "zoom_in" then
        -- 阶段1: 缩放/平移到目标
        zoom.elapsed = zoom.elapsed + dt
        local t = math.min(1.0, zoom.elapsed / math.max(0.001, zoom.duration))
        local et = zoom.easeFn(t)

        camera.orthoSize = zoom.fromOrthoSize + (zoom.toOrthoSize - zoom.fromOrthoSize) * et

        if zoom.usePan then
            targetX = zoom.fromCenterX + (zoom.toCenterX - zoom.fromCenterX) * et
            targetY = zoom.fromCenterY + (zoom.toCenterY - zoom.fromCenterY) * et
        end

        if t >= 1.0 then
            if zoom.autoRestore then
                -- 进入 holding 阶段
                zoom.phase = "holding"
                zoom.holdElapsed = 0
                -- 记录恢复起点（当前到达的位置）
                zoom.restoreFromOrthoSize = camera.orthoSize
                if zoom.usePan then
                    zoom.restoreFromCenterX = zoom.toCenterX
                    zoom.restoreFromCenterY = zoom.toCenterY
                end
            else
                zoom.phase = "done"
                zoom.finished = true
            end
        end

    elseif phase == "holding" then
        -- 阶段2: 持续保持缩放状态
        zoom.holdElapsed = zoom.holdElapsed + dt
        camera.orthoSize = zoom.toOrthoSize
        if zoom.usePan then
            targetX = zoom.toCenterX
            targetY = zoom.toCenterY
        end

        if zoom.holdElapsed >= zoom.holdDuration then
            -- 进入 restore 阶段
            zoom.phase = "restore"
            zoom.restoreElapsed = 0
        end

    elseif phase == "restore" then
        -- 阶段3: 恢复到原始缩放/位置
        zoom.restoreElapsed = zoom.restoreElapsed + dt
        local t = math.min(1.0, zoom.restoreElapsed / math.max(0.001, zoom.restoreDuration))
        local et = zoom.restoreEaseFn(t)

        camera.orthoSize = zoom.restoreFromOrthoSize + (zoom.restoreToOrthoSize - zoom.restoreFromOrthoSize) * et

        if zoom.usePan then
            targetX = (zoom.restoreFromCenterX or zoom.toCenterX) + (zoom.restoreToCenterX - (zoom.restoreFromCenterX or zoom.toCenterX)) * et
            targetY = (zoom.restoreFromCenterY or zoom.toCenterY) + (zoom.restoreToCenterY - (zoom.restoreFromCenterY or zoom.toCenterY)) * et
        end

        if t >= 1.0 then
            zoom.phase = "done"
            zoom.finished = true
            -- 恢复完毕，清除 zoom 对象让相机回归正常跟随
            levelEditor_.previewCameraZoom = nil
        end

    else -- "done"
        -- 无自动恢复时保持最终状态
        camera.orthoSize = zoom.toOrthoSize
        if zoom.usePan then
            targetX = zoom.toCenterX
            targetY = zoom.toCenterY
        end
    end

    return targetX, targetY
end

--- 每帧更新相机效果（抖动等），返回偏移量
--- @param dt number
--- @return number offsetX, number offsetY
function P._updateCameraFx(dt)
    local fxList = levelEditor_.previewCameraFx
    if not fxList then return 0, 0 end
    local offsetX, offsetY = 0, 0
    for i = #fxList, 1, -1 do
        local fx = fxList[i]
        if fx.type == "shake" then
            fx.elapsed = fx.elapsed + dt
            if fx.elapsed >= fx.duration then
                table.remove(fxList, i)
            else
                local amp = fx.intensity * (1.0 - fx.elapsed / fx.duration)
                offsetX = offsetX + (math.random() * 2 - 1) * amp
                offsetY = offsetY + (math.random() * 2 - 1) * amp
            end
        end
    end
    return offsetX, offsetY
end

--- 每帧更新粒子
function P._updateParticles(dt)
    local particles = levelEditor_.previewParticles
    if not particles then return end
    for i = #particles, 1, -1 do
        local p = particles[i]
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(particles, i)
        else
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            -- 重力影响
            p.vy = p.vy - 3.0 * dt
        end
    end
end

-- ============================================================================
-- play_fx 效果分发系统
-- ============================================================================

--- 播放音效
function P._fxSound(node, context)
    local file = node.soundFile or ""
    if file == "" then return end
    local sound = cache:GetResource("Sound", file)
    if not sound then
        print("[play_fx] 音效资源未找到: " .. file)
        return
    end
    sound.looped = false
    local scene = levelEditor_.previewScene
    if not scene then return end
    local sourceNode = scene:CreateChild("SfxSource")
    local source = sourceNode:CreateComponent("SoundSource")
    source.soundType = "Effect"
    source:Play(sound)
    source.gain = node.soundVolume or 1.0
    -- 播放完后自动清理（简单方案：延迟销毁节点）
    -- 由于 Sound 播放是引擎管理的，这里标记延迟清理
    if not levelEditor_.previewSfxNodes then levelEditor_.previewSfxNodes = {} end
    table.insert(levelEditor_.previewSfxNodes, { node = sourceNode, timer = 10.0 })
end

--- 相机抖动
function P._fxCameraShake(node, _)
    local fxList = levelEditor_.previewCameraFx
    if not fxList then return end
    table.insert(fxList, {
        type = "shake",
        duration = node.shakeDuration or 0.3,
        intensity = (node.shakeIntensity or 1.0) * 0.1,  -- 转换为米单位偏移
        elapsed = 0.0,
    })
end

--- 全屏闪光
function P._fxScreenFlash(node, _)
    levelEditor_.previewScreenFlash = {
        color = node.flashColor or "white",
        duration = node.flashDuration or 0.2,
        elapsed = 0.0,
    }
end

--- 浮动文字
function P._fxFloatingText(node, context)
    local popups = levelEditor_.previewTriggerPopups
    if not popups then return end
    local text = node.floatText or ""
    if text == "" then return end
    local px = context and context.playerX or (levelEditor_.worldW / 2)
    local py = context and context.playerY or (levelEditor_.worldH / 2)
    table.insert(popups, {
        text = text,
        x = px,
        y = py + 2.0,
        timer = 0,
        maxTime = 2.5,
        color = node.floatColor or "white",
        fontSize = node.floatSize or 24,
    })
end

--- 粒子效果
function P._fxParticle(node, context)
    local particles = levelEditor_.previewParticles
    if not particles then return end
    local px = context and context.playerX or (levelEditor_.worldW / 2)
    local py = context and context.playerY or (levelEditor_.worldH / 2)
    local dirKey = node.particleDir or "up"
    local dirVec = PARTICLE_DIR_MAP[dirKey] or PARTICLE_DIR_MAP.up
    local count = node.particleCount or 10
    local speed = node.particleSpeed or 3.0
    for _ = 1, count do
        local vx, vy
        if dirKey == "radial" then
            local angle = math.random() * math.pi * 2
            vx = math.cos(angle) * speed * (0.5 + math.random() * 0.5)
            vy = math.sin(angle) * speed * (0.5 + math.random() * 0.5)
        else
            vx = dirVec.x * speed * (0.7 + math.random() * 0.6) + (math.random() - 0.5) * speed * 0.3
            vy = dirVec.y * speed * (0.7 + math.random() * 0.6) + (math.random() - 0.5) * speed * 0.3
        end
        table.insert(particles, {
            x = px + (math.random() - 0.5) * 0.5,
            y = py + (math.random() - 0.5) * 0.5,
            vx = vx,
            vy = vy,
            life = 0.8 + math.random() * 0.6,
            maxLife = 0.8 + math.random() * 0.6,
            size = 0.1 + math.random() * 0.1,
        })
    end
end

--- 慢动作
function P._fxSlowMotion(node, _)
    levelEditor_.previewSlowMotion = {
        factor = node.slowFactor or 0.3,
        duration = node.slowDuration or 1.0,
        elapsed = 0.0,
    }
end

--- 效果分发表（可扩展）
P._fxHandlers = {
    sound         = P._fxSound,
    camera_shake  = P._fxCameraShake,
    screen_flash  = P._fxScreenFlash,
    floating_text = P._fxFloatingText,
    particle      = P._fxParticle,
    slow_motion   = P._fxSlowMotion,
}

--- 执行 play_fx 节点
function P._executeFx(fxType, node, context)
    local handler = P._fxHandlers[fxType]
    if handler then
        handler(node, context)
    else
        print("[play_fx] 未实现的效果类型: " .. tostring(fxType))
    end
end

-- ============================================================================
-- 策略树执行辅助 (预览模式)
-- ============================================================================

--- 仅执行执行器自身的策略树（不重复执行触发器策略）
--- @param executorObj table 执行器对象
--- @param context table 运行时上下文
--- @return string|nil popupText
function P._executeExecutorOnly(executorObj, context)
    if not executorObj or not executorObj.executorStrategy or not executorObj.executorStrategy.rootId then
        return nil
    end
    local SN = require("StrategyNode")
    local items = levelEditor_.previewItems or {}
    local tree = executorObj.executorStrategy
    local params = {}
    for _, p in ipairs(tree.params or {}) do
        params[p.name] = p.value
    end
    if context then
        for k, v in pairs(context) do params[k] = v end
    end
    params._items = items
    local actions = SN.Execute(tree, params)

    -- 执行实际运行时副作用（支持 delay 节点异步延迟）
    P._executeActionSublist(actions, 1, context)

    -- 生成文本摘要
    if #actions > 0 then
        local texts = {}
        for _, act in ipairs(actions) do
            local node = act.node or {}
            local ntDef = SN.NODE_TYPES[act.nodeType]
            local label = ntDef and ntDef.label or act.nodeType
            if act.nodeType == "teleport_player" then
                table.insert(texts, label .. "(" .. tostring(node.targetX or 15) .. "," .. tostring(node.targetY or 8) .. ")")
            else
                table.insert(texts, label)
            end
        end
        return table.concat(texts, " | ")
    end
    return nil
end

--- 触发器触发时执行策略树，返回弹出文字列表
--- @param trigObj table 触发器对象
--- @param executorObj table|nil 执行器对象（可选）
--- @param context table 运行时上下文 {playerX, playerY, ...}
--- @return string|nil popupText 额外弹出文本（nil则使用默认）
function P._executeStrategy(trigObj, executorObj, context)
    local SN = require("StrategyNode")
    local results = {}

    -- 注入物品背包到 _items，供 read_item 节点读取
    local items = levelEditor_.previewItems or {}

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
        params._items = items
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
        params._items = items
        local actions = SN.Execute(tree, params)
        for _, act in ipairs(actions) do
            table.insert(results, act)
        end
    end

    -- 2.5 执行实际运行时副作用（支持 delay 节点异步延迟）
    P._executeActionSublist(results, 1, context)

    -- 3. 生成文本摘要
    if #results > 0 then
        local texts = {}
        for _, act in ipairs(results) do
            local ntDef = SN.NODE_TYPES[act.nodeType]
            local label = ntDef and ntDef.label or act.nodeType
            local node = act.node or {}
            if act.nodeType == "set_var" then
                table.insert(texts, label .. ":" .. (node.varName or "?") .. "=" .. tostring(node.newValue or 0))
            elseif act.nodeType == "spawn" then
                table.insert(texts, label .. "(" .. (node.spawnType or "?") .. " x" .. (node.spawnCount or 1) .. ")")
            elseif act.nodeType == "damage" then
                local prefix = node.damageIsHeal and "+" or "-"
                table.insert(texts, label .. "(" .. prefix .. tostring(node.damageAmount or 10) .. "HP)")
            elseif act.nodeType == "delay" then
                table.insert(texts, label .. "(" .. tostring(node.delaySeconds or 1) .. "s)")
            elseif act.nodeType == "repeat_n" then
                table.insert(texts, label .. "(" .. tostring(node.repeatCount or 3) .. "x)")
            elseif act.nodeType == "dialog" then
                local txt = node.dialogText or ""
                if #txt > 8 then txt = txt:sub(1, 8) .. "…" end
                table.insert(texts, label .. '("' .. txt .. '")')
            elseif act.nodeType == "move_obj" then
                table.insert(texts, label .. "(" .. (node.targetId or "?") .. " " .. (node.moveDuration or 1) .. "s)")
            elseif act.nodeType == "camera_zoom" then
                table.insert(texts, label .. "(" .. tostring(node.zoomScale or 1.0) .. "x " .. tostring(node.zoomDuration or 0.5) .. "s)")
            elseif act.nodeType == "modify_item" then
                local opLabel = node.itemOp or "add"
                for _, o in ipairs(SN.ITEM_OPS) do if o.id == node.itemOp then opLabel = o.label; break end end
                local itemLabel = node.itemName or "?"
                for _, it in ipairs(SN.ITEM_TYPES) do if it.id == node.itemName then itemLabel = it.label; break end end
                table.insert(texts, label .. "(" .. opLabel .. " " .. itemLabel .. ")")
            elseif act.nodeType == "set_ability" then
                local abilLabel = node.abilityName or "?"
                for _, a in ipairs(SN.ABILITY_TYPES) do if a.id == node.abilityName then abilLabel = a.label; break end end
                table.insert(texts, label .. "(" .. (node.abilityEnabled and "启用" or "禁用") .. " " .. abilLabel .. ")")
            elseif act.nodeType == "destroy_self" then
                table.insert(texts, label)
            elseif act.nodeType == "teleport_player" then
                table.insert(texts, label .. "(" .. tostring(node.targetX or 15) .. "," .. tostring(node.targetY or 8) .. ")")
            elseif act.nodeType == "reset_trigger" then
                local mLabel = node.resetMethod or "keep"
                for _, m in ipairs(SN.TRIGGER_METHODS) do if m.id == node.resetMethod then mLabel = m.label; break end end
                table.insert(texts, label .. "(#" .. tostring(node.resetTargetIdx or 0) .. " " .. mLabel .. ")")
            else
                table.insert(texts, label)
            end
        end
        return table.concat(texts, " | ")
    end
    return nil
end

--- 导出关卡地形数据

return P
