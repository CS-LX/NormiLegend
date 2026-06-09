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

local P = {}
local levelEditor_ = EditorState.state

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
    }

    -- 预览期间切换UI根为轻量预览面板（主菜单UI层会覆盖NanoVG渲染）
    UI.SetRoot(levelEditor_.previewUIRoot)

    print("[PREVIEW] 预览启动 - " .. #objects .. " 个物件")
end

--- 停止预览模式
function P.StopPreview()
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
    if getTitleMenu().levelSelect_.uiRoot then
        getTitleMenu().levelSelect_.uiRoot:SetVisible(true)
    end

    -- 显示编辑器UI并挂回正确父节点
    if levelEditor_.uiRoot then
        levelEditor_.uiRoot:SetVisible(true)
        -- 编辑器UI可能还挂在已销毁的previewUIRoot上，重新挂载
        if getTitleMenu().levelSelect_.uiRoot then
            getTitleMenu().levelSelect_.uiRoot:AddChild(levelEditor_.uiRoot)
        elseif S.mainMenuUIRoot then
            S.mainMenuUIRoot:AddChild(levelEditor_.uiRoot)
        end
    else
        getTitleMenu().BuildLevelEditorUI()
    end

    print("[PREVIEW] 预览结束")
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
function P.UpdatePreview(dt)
    if not levelEditor_.previewActive then return end

    local playerBody = levelEditor_.previewPlayerBody
    local playerNode = levelEditor_.previewPlayerNode
    local cameraNode = levelEditor_.previewCameraNode
    if not playerBody or not playerNode or not cameraNode then return end

    -- 让 Combat 系统使用预览玩家节点（主循环被 showMainMenu 跳过）
    S.playerNode = playerNode

    -- ESC退出预览
    if input:GetKeyPress(KEY_ESCAPE) then
        P.StopPreview()
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
                    -- 执行器策略
                    local exStratText = P._executeStrategy(obj, exObj, stratCtx)
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
function P._executeStrategy(trigObj, executorObj, context)
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

return P
