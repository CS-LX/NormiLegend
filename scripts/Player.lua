-- ============================================================================
-- Player.lua - 玩家系统
-- 职责: 角色切换、HUD创建、碰撞回调、输入处理（移动/跳跃/格挡/蓄力/治愈/潜行）
-- ============================================================================

local C = require("GameConfig")
local S = require("GameState")
local Combat = require("Combat")
local GMConsole = require("GMConsole")
local SpriteEditor = require("SpriteEditor")
local Enemy = require("Enemy")
local BatEnemy = require("BatEnemy")
local CastleEnemies = require("CastleEnemies")

require "urhox-libs.UI.GameHUD"
local UI = require("urhox-libs/UI")

local M = {}

-- ============================================================================
-- 角色切换
-- ============================================================================

--- 刷新右侧角色切换面板（只显示非当前角色）
function M.RefreshCharSwitchPanel()
    if not S.charSwitchPanel then return end
    S.charSwitchPanel:RemoveAllChildren()

    local charList = {
        { idx = 1, name = "冰法师", avatar = "image/avatar_char1_20260602072030.png", border = { 100, 180, 255, 220 } },
        { idx = 2, name = "角娘", avatar = "image/avatar_char2_20260602072055.png", border = { 255, 100, 100, 220 } },
    }

    for _, info in ipairs(charList) do
        if info.idx ~= S.currentCharacter then
            local btn = UI.Button {
                width = 52, height = 52,
                borderRadius = 26,
                borderWidth = 2.5,
                borderColor = info.border,
                backgroundColor = { 20, 20, 30, 180 },
                backgroundImage = info.avatar,
                backgroundSize = "cover",
                onClick = function()
                    M.SwitchToCharacter(info.idx)
                end,
            }
            S.charSwitchPanel:AddChild(btn)
        end
    end
end

--- 切换到指定角色
---@param charIdx number 1=冰法师, 2=黑红角娘
function M.SwitchToCharacter(charIdx)
    if S.currentCharacter == charIdx then return end
    -- 保存当前角色状态
    S.charStats[S.currentCharacter].hp = S.playerHP
    S.charStats[S.currentCharacter].mp = S.playerMP
    S.currentCharacter = charIdx
    -- 恢复目标角色状态
    S.playerHP = S.charStats[charIdx].hp
    S.playerMaxHP = S.charStats[charIdx].maxHP
    S.playerMP = S.charStats[charIdx].mp
    S.playerMaxMP = S.charStats[charIdx].maxMP
    -- 切换到角色1时清除角色2的吸血buff
    if charIdx == 1 then S.lifestealBuffTimer = 0 end
    -- 更新右侧切换面板
    M.RefreshCharSwitchPanel()
    print("[CHARACTER] 切换到角色" .. charIdx)
end

-- ============================================================================
-- HUD 创建
-- ============================================================================

--- 创建游戏 HUD（摇杆 + 技能按钮面板）
function M.CreateGameHUD()
    GameHUD.Initialize()
    local hud = GameHUD.Create({})
    S.joystick = hud.joystick

    -- 右下角操作按钮面板
    S.btnCharge = UI.Button {
        text = "Q", fontSize = 16, width = 60, height = 60,
        backgroundColor = "rgba(60,140,255,0.75)", color = "#ffffff",
        borderRadius = 30, borderWidth = 2, borderColor = "rgba(150,220,255,0.8)",
    }
    S.btnBlock = UI.Button {
        text = "挡", fontSize = 14, width = 60, height = 60,
        backgroundColor = "rgba(180,150,60,0.75)", color = "#ffffff",
        borderRadius = 30, borderWidth = 2, borderColor = "rgba(255,220,130,0.8)",
    }
    S.btnHeal = UI.Button {
        text = "E", fontSize = 16, width = 60, height = 60,
        backgroundColor = "rgba(60,220,120,0.75)", color = "#ffffff",
        borderRadius = 30, borderWidth = 2, borderColor = "rgba(150,255,200,0.8)",
        onClick = function() S.healButtonTap = true end,
    }
    S.btnAttack = UI.Button {
        text = "攻", fontSize = 18, width = 80, height = 80,
        backgroundColor = "rgba(220,80,60,0.8)", color = "#ffffff",
        borderRadius = 40, borderWidth = 2, borderColor = "rgba(255,150,130,0.8)",
        onClick = function() S.attackButtonTap = true end,
    }
    S.btnJump = UI.Button {
        text = "跳", fontSize = 16, width = 66, height = 66,
        backgroundColor = "rgba(143,104,213,0.8)", color = "#ffffff",
        borderRadius = 33, borderWidth = 2, borderColor = "rgba(255,255,255,0.6)",
        onClick = function() S.jumpButtonTap = true end,
    }

    S.skillButtonPanel = UI.Panel {
        position = "absolute",
        bottom = 20, right = 12,
        pointerEvents = "box-none",
        alignItems = "flex-end",
        children = {
            UI.Panel {
                flexDirection = "row", gap = 14, marginBottom = 10,
                pointerEvents = "box-none",
                children = { S.btnCharge, S.btnBlock },
            },
            UI.Panel {
                flexDirection = "row", gap = 14, marginBottom = 10,
                alignItems = "center",
                pointerEvents = "box-none",
                children = { S.btnHeal, S.btnAttack },
            },
            UI.Panel {
                flexDirection = "row", justifyContent = "flex-end",
                pointerEvents = "box-none",
                children = { S.btnJump },
            },
        },
    }
end

-- ============================================================================
-- 碰撞回调
-- ============================================================================

local function GetOtherNode(nodeA, nodeB)
    if S.playerNode == nil then return nil end
    if nodeA == S.playerNode then return nodeB
    elseif nodeB == S.playerNode then return nodeA end
    return nil
end

local function IsGroundOrPlatform(node)
    if node == nil then return false end
    return node.name == "Ground" or node.name:find("Platform", 1, true) ~= nil
end

--- 物理开始接触回调
function M.HandlePhysicsBeginContact(eventType, eventData)
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local nodeB = eventData["NodeB"]:GetPtr("Node")
    local hitNode = GetOtherNode(nodeA, nodeB)
    if IsGroundOrPlatform(hitNode) then
        S.groundContactCount = S.groundContactCount + 1
        S.onGround = true
        -- 落地时结束滞空
        if S.isHanging and S.playerBody then
            S.isHanging = false
            S.playerBody.gravityScale = 1.0
            S.wingShatterTimer = C.WING_SHATTER_DURATION
        end
    end
end

--- 物理结束接触回调
function M.HandlePhysicsEndContact(eventType, eventData)
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local nodeB = eventData["NodeB"]:GetPtr("Node")
    local hitNode = GetOtherNode(nodeA, nodeB)
    if IsGroundOrPlatform(hitNode) then
        S.groundContactCount = S.groundContactCount - 1
        if S.groundContactCount <= 0 then
            S.groundContactCount = 0
            S.onGround = false
        end
    end
end

-- ============================================================================
-- 帧更新 - 输入与物理状态
-- ============================================================================

--- 每帧更新玩家输入与状态（在关卡内调用）
---@param dt number
function M.Update(dt)
    if S.playerBody == nil then return end

    -- 光翼破碎动画计时
    if S.wingShatterTimer > 0 then
        S.wingShatterTimer = S.wingShatterTimer - dt
    end
    -- 滞空冷却计时
    if S.hangCooldown > 0 then
        S.hangCooldown = S.hangCooldown - dt
    end

    -- 受击僵直更新
    if S.isHit then
        S.hitStunTimer = S.hitStunTimer - dt
        if S.hitStunTimer <= 0 then
            S.isHit = false
            S.hitStunTimer = 0
        else
            -- 僵直期间不处理输入，只更新动画帧
            S.animTimer = S.animTimer + dt
            local frameInterval = 1.0 / C.ANIM_FPS_HIT
            if S.animTimer >= frameInterval then
                S.animTimer = S.animTimer - frameInterval
                S.animFrame = S.animFrame + 1
                if S.animFrame >= C.SPRITE_FRAMES then
                    S.animFrame = C.SPRITE_FRAMES - 1
                end
            end
            return
        end
    end

    -- 数字键切换角色（1=冰法师, 2=黑红角娘）
    if not S.editorMode then
        if input:GetKeyPress(KEY_1) then M.SwitchToCharacter(1) end
        if input:GetKeyPress(KEY_2) then M.SwitchToCharacter(2) end
    end

    -- 输入处理
    local mouseOnUI = UI.IsPointerOverUI()
    local currentVel = S.playerBody.linearVelocity
    local desiredVelX = 0

    -- 虚拟摇杆输入
    local joyCrouchHeld = false
    local joyCrouchMoveX = 0
    if S.joystick then
        local moveX, moveY = S.joystick:getMovement()
        if moveY < -0.4 then
            joyCrouchHeld = true
            local absX = math.abs(moveX)
            local absY = math.abs(moveY)
            if absX > 0.3 and absX / absY > 0.4 then
                joyCrouchMoveX = moveX > 0 and 1 or -1
            end
        elseif moveX < -0.1 then
            desiredVelX = -C.PLAYER_SPEED
            S.facingRight = false
        elseif moveX > 0.1 then
            desiredVelX = C.PLAYER_SPEED
            S.facingRight = true
        end
    end

    -- 键盘输入
    if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then
        desiredVelX = -C.PLAYER_SPEED
        S.facingRight = false
    elseif input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then
        desiredVelX = C.PLAYER_SPEED
        S.facingRight = true
    end

    -- 施法/格挡期间可以移动但速度减半
    if S.isAttacking or S.isBlocking then
        desiredVelX = desiredVelX * 0.5
    end

    S.playerBody.linearVelocity = Vector2(desiredVelX, currentVel.y)

    -- 跳跃
    local jumpBtnHeld = S.btnJump and S.btnJump.state and S.btnJump.state.pressed
    local jumpPressed = input:GetKeyPress(KEY_SPACE) or input:GetKeyPress(KEY_W) or input:GetKeyPress(KEY_UP) or input:GetKeyPress(KEY_K) or S.jumpButtonTap
    S.jumpButtonTap = false
    local jumpHeld = input:GetKeyDown(KEY_SPACE) or input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP) or input:GetKeyDown(KEY_K) or jumpBtnHeld

    if S.onGround and jumpPressed and not S.isCharging and not S.chargeReleased and math.abs(S.playerBody.linearVelocity.y) < 2.0 then
        S.onGround = false
        S.groundContactCount = 0
        S.playerBody.linearVelocity = Vector2(desiredVelX, C.PLAYER_JUMP_SPEED)
        S.playerBody.awake = true
        S.isHanging = false
        S.playerBody.gravityScale = 1.0
    elseif not S.onGround and jumpHeld and not S.isHanging and S.hangCooldown <= 0 and S.playerBody.linearVelocity.y < 0 then
        -- 空中下落期间长按跳跃键：进入滞空
        S.isHanging = true
        S.hangCooldown = C.HANG_COOLDOWN_TIME
        S.playerBody.gravityScale = C.HANG_GRAVITY_SCALE
        local vel = S.playerBody.linearVelocity
        S.playerBody.linearVelocity = Vector2(vel.x, vel.y * 0.3)
    end

    -- 滞空状态：松开跳跃键结束
    if S.isHanging then
        if not jumpHeld then
            S.isHanging = false
            S.playerBody.gravityScale = 1.0
            S.wingShatterTimer = C.WING_SHATTER_DURATION
        end
    end

    -- 施法（攻击）
    local attackBtnHeld = S.btnAttack and S.btnAttack.state and S.btnAttack.state.pressed
    local attackPressed = input:GetKeyPress(KEY_J) or (not mouseOnUI and input:GetMouseButtonPress(MOUSEB_LEFT)) or S.attackButtonTap
    S.attackButtonTap = false
    if not attackPressed and (attackBtnHeld or input:GetKeyDown(KEY_J) or (not mouseOnUI and input:GetMouseButtonDown(MOUSEB_LEFT))) then
        if not S.isAttacking then
            attackPressed = true
        end
    end
    if attackPressed and not S.isBlocking and not S.isCharging and not S.chargeReleased then
        Combat.CastSpell()
    end

    -- 格挡（鼠标右键长按）
    local blockBtnHeld = S.btnBlock and S.btnBlock.state and S.btnBlock.state.pressed
    local blockHeld = (not mouseOnUI and input:GetMouseButtonDown(MOUSEB_RIGHT)) or input:GetKeyDown(KEY_L) or blockBtnHeld
    if blockHeld and not S.isBlocking and not S.isAttacking and not S.isCharging and (S.playerMP > 0 or GMConsole.IsInfiniteMP()) then
        S.isBlocking = true
        S.currentAnim = C.ANIM_BLOCK
        S.animFrame = 0
        S.animTimer = 0.0
    elseif S.isBlocking and not blockHeld then
        S.isBlocking = false
    end
    -- 格挡消耗MP
    if S.isBlocking then
        if not GMConsole.IsInfiniteMP() then
            S.playerMP = S.playerMP - C.BLOCK_MP_PER_SEC * dt
            if S.playerMP <= 0 then
                S.playerMP = 0
                S.isBlocking = false
            end
        end
    end

    -- 蓄力（Q键长按）
    local chargeBtnHeld = S.btnCharge and S.btnCharge.state and S.btnCharge.state.pressed
    local chargeHeld = input:GetKeyDown(KEY_Q) or chargeBtnHeld
    if not S.editorMode then
        local chargeStart = input:GetKeyPress(KEY_Q)
        if chargeBtnHeld and not S.isCharging then chargeStart = true end
        if chargeStart and not S.isCharging and not S.chargeReleased and not S.isAttacking and not S.isBlocking and not S.isDashing then
            S.isCharging = true
            S.chargeTimer = 0.0
            S.currentAnim = C.ANIM_CHARGE
            S.animFrame = 0
            S.animTimer = 0.0
        elseif S.isCharging then
            S.chargeTimer = S.chargeTimer + dt
            if not chargeHeld or S.chargeTimer >= C.CHARGE_MAX_DURATION then
                -- MP不足时取消
                if S.playerMP < C.CHARGE_MP_COST then
                    S.isCharging = false
                    S.chargeReleased = false
                else
                    S.isCharging = false
                    S.chargeReleased = true
                    if not GMConsole.IsInfiniteMP() then
                        S.playerMP = S.playerMP - C.CHARGE_MP_COST
                    end

                    if S.currentCharacter == 2 then
                        -- 角色2：蝴蝶突进
                        local power = math.min(S.chargeTimer / C.CHARGE_MAX_DURATION, 1.0)
                        S.isDashing = true
                        S.dashTimer = 0.0
                        S.dashDir = S.facingRight and 1 or -1
                        S.dashStartX = S.playerNode.position2D.x
                        S.dashTargetDist = C.CHAR2_DASH_MIN_DIST + (C.CHAR2_DASH_MAX_DIST - C.CHAR2_DASH_MIN_DIST) * power
                        S.dashHitEnemies = {}
                    else
                        -- 角色1：生成冰晶群
                        Combat.SpawnIceCrystals(S.chargeTimer)
                    end
                    -- 切换到释放帧
                    S.animFrame = 9
                    S.animTimer = 0.0
                end
            end
        end
        -- 释放动画播放完毕后恢复
        if S.chargeReleased and S.currentAnim == C.ANIM_CHARGE and S.animFrame >= 11 then
            S.chargeReleased = false
            if S.isDashing then S.isDashing = false end
            if S.playerBody and math.abs(S.playerBody.linearVelocity.y) < 1.0 and S.groundContactCount > 0 then
                S.onGround = true
            end
        end
    end

    -- 治愈技能（E键）
    if not S.editorMode then
        if S.healCooldownTimer > 0 then
            S.healCooldownTimer = S.healCooldownTimer - dt
        end
        local healPressed = input:GetKeyPress(KEY_E) or S.healButtonTap
        S.healButtonTap = false
        if healPressed and not S.isHealing and not S.isCharging and not S.chargeReleased and not S.isAttacking and not S.isBlocking and S.healCooldownTimer <= 0 and (S.playerMP >= C.HEAL_MP_COST or GMConsole.IsInfiniteMP()) then
            S.isHealing = true
            S.healTimer = 0.0
            S.currentAnim = C.ANIM_HEAL
            S.animFrame = 0
            S.animTimer = 0.0
            if not GMConsole.IsInfiniteMP() then
                S.playerMP = S.playerMP - C.HEAL_MP_COST
            end
        end
        if S.isHealing then
            S.healTimer = S.healTimer + dt
            if S.healTimer >= C.HEAL_DURATION then
                S.isHealing = false
                S.healCooldownTimer = C.HEAL_COOLDOWN
                if S.currentCharacter == 2 then
                    local eLevel = S.skillList2[3].level
                    local healAmount = 10 + (eLevel - 1) * 5
                    S.playerHP = math.min(S.playerHP + healAmount, S.playerMaxHP)
                    S.lifestealBuffTimer = C.LIFESTEAL_DURATION
                else
                    S.playerHP = math.min(S.playerHP + C.HEAL_HP_RESTORE, S.playerMaxHP)
                end
            end
        end
        -- 吸血buff计时
        if S.lifestealBuffTimer > 0 then
            S.lifestealBuffTimer = S.lifestealBuffTimer - dt
            if S.lifestealBuffTimer < 0 then S.lifestealBuffTimer = 0 end
        end
    end

    -- 潜行
    if not S.editorMode then
        local crouchHeld = input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_LSHIFT) or joyCrouchHeld
        local wasCrouching = S.isCrouching
        if crouchHeld and S.onGround and not S.isCharging and not S.chargeReleased and not S.isHealing and not S.isAttacking then
            if not wasCrouching then
                S.isCrouching = true
                S.crouchPhase = "enter"
                S.animFrame = 1
                S.animTimer = 0.0
            end
            if joyCrouchMoveX ~= 0 then
                desiredVelX = joyCrouchMoveX * C.PLAYER_SPEED
                S.facingRight = joyCrouchMoveX > 0
            end
        else
            if wasCrouching then
                S.isCrouching = false
                S.crouchPhase = "loop"
                S.animFrame = 0
                S.animTimer = 0.0
            end
        end
    end

    -- 蓄力/治愈/突进期间限制移动
    if S.isDashing then
        S.playerBody.linearVelocity = Vector2(S.dashDir * C.CHAR2_DASH_SPEED, 0)
        desiredVelX = 0
    elseif S.isCharging or S.chargeReleased or S.isHealing then
        desiredVelX = 0
        S.playerBody.linearVelocity = Vector2(0, S.playerBody.linearVelocity.y)
    elseif S.isCrouching then
        desiredVelX = desiredVelX * (C.CROUCH_SPEED / C.PLAYER_SPEED)
        S.playerBody.linearVelocity = Vector2(desiredVelX, currentVel.y)
    end

    -- 魔力自然回复
    S.mpRegenTimer = S.mpRegenTimer + dt
    if S.mpRegenTimer >= 2.0 then
        S.mpRegenTimer = S.mpRegenTimer - 2.0
        if S.playerMP < S.playerMaxMP then
            S.playerMP = math.min(S.playerMP + 1, S.playerMaxMP)
        end
    end

    -- 玩家边界钳制
    local pPos = S.playerNode.position2D
    local playerBound = C.MAP_HALF_WIDTH - C.PLAYER_RADIUS
    if pPos.x < -playerBound then
        S.playerNode:SetPosition2D(-playerBound, pPos.y)
        S.playerBody.linearVelocity = Vector2(math.max(0, S.playerBody.linearVelocity.x), S.playerBody.linearVelocity.y)
    elseif pPos.x > playerBound then
        S.playerNode:SetPosition2D(playerBound, pPos.y)
        S.playerBody.linearVelocity = Vector2(math.min(0, S.playerBody.linearVelocity.x), S.playerBody.linearVelocity.y)
    end

    return desiredVelX
end

-- ============================================================================
-- 相机跟随（PostUpdate）
-- ============================================================================

--- 平滑相机跟随玩家
---@param dt number
function M.UpdateCamera(dt)
    if S.playerNode == nil or S.cameraNode == nil then return end

    local Renderer = require("Renderer")

    local pos = S.playerNode.position2D
    local camPos = S.cameraNode.position
    local targetX = pos.x
    local targetY = math.max(pos.y, 0)
    local lerpFactor = 5.0 * dt
    local newX = camPos.x + (targetX - camPos.x) * lerpFactor
    local newY = camPos.y + (targetY - camPos.y) * lerpFactor

    -- 相机边界钳制
    local _, _, lbW, _ = Renderer.CalcLetterbox(graphics:GetWidth(), graphics:GetHeight())
    local camHalfView = (lbW / C.PIXELS_PER_UNIT) * 0.5
    local camMinX = -C.MAP_HALF_WIDTH + camHalfView
    local camMaxX = C.MAP_HALF_WIDTH - camHalfView
    newX = math.max(camMinX, math.min(camMaxX, newX))

    S.cameraNode:SetPosition(Vector3(newX, newY, -10))
end

return M
