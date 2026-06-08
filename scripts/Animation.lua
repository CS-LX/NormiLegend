-- ============================================================================
-- Animation.lua - 动画状态机
-- 管理角色动画帧更新、状态切换、帧率控制
-- ============================================================================

local C = require("GameConfig")
local S = require("GameState")

local M = {}

-- 蹲下动画自定义帧序列
local crouchFrameMap1 = { 0, 1, 2, 3, 7, 11 }   -- 角色1: loop帧7,11
local crouchFrameMap2 = { 0, 1, 2, 3, 10, 11 }   -- 角色2: loop帧10,11

--- 获取当前角色的蹲下帧映射
function M.GetCrouchFrameMap()
    if S.currentCharacter == 2 then return crouchFrameMap2 end
    return crouchFrameMap1
end

--- 更新动画状态机
---@param dt number 帧时间
---@param velX number 水平速度（用于判断跑步/待机）
function M.Update(dt, velX)
    -- 受击状态中，不切换动画（由僵直逻辑控制帧更新）
    if S.isHit then
        return
    end

    -- 攻击动画优先
    if S.isAttacking then
        S.attackTimer = S.attackTimer + dt
        local attackDuration = C.SPRITE_FRAMES / C.ANIM_FPS_ATTACK
        if S.attackTimer >= attackDuration then
            S.isAttacking = false
            S.attackTimer = 0.0
        end
    end

    -- 确定当前动画（记录切换前的状态）
    local prevAnim = S.currentAnim
    if S.isHealing then
        S.currentAnim = C.ANIM_HEAL
    elseif S.isCharging or S.chargeReleased then
        S.currentAnim = C.ANIM_CHARGE
    elseif S.isBlocking then
        S.currentAnim = C.ANIM_BLOCK
    elseif not S.isAttacking then
        if not S.onGround then
            S.currentAnim = C.ANIM_JUMP
        elseif S.isCrouching then
            -- 蹲下时区分蹲走和蹲下
            if math.abs(velX) > 0.1 and S.crouchPhase == "loop" then
                S.currentAnim = C.ANIM_CROUCH_WALK
            else
                S.currentAnim = C.ANIM_CROUCH
            end
        elseif math.abs(velX) > 0.1 then
            S.currentAnim = C.ANIM_RUN
        else
            S.currentAnim = C.ANIM_IDLE
        end
    end

    -- 动画切换时重置帧
    if S.currentAnim ~= prevAnim then
        if S.currentAnim == C.ANIM_CROUCH then
            -- 进入蹲下时，如果已在loop阶段就从loop开始
            if S.crouchPhase == "loop" then
                S.animFrame = C.CROUCH_LOOP_START
            else
                S.animFrame = 1
            end
            S.animTimer = 0.0
        elseif S.currentAnim == C.ANIM_CROUCH_WALK then
            -- 进入蹲走时从0开始
            S.animFrame = 0
            S.animTimer = 0.0
        elseif prevAnim == C.ANIM_CROUCH or prevAnim == C.ANIM_CROUCH_WALK then
            -- 从蹲下/蹲走切到其他动画时重置
            S.animFrame = 0
            S.animTimer = 0.0
        else
            S.animFrame = 0
            S.animTimer = 0.0
        end
    end

    -- 根据动画类型选择帧率
    local fps = C.ANIM_FPS
    if S.currentAnim == C.ANIM_RUN then
        fps = C.ANIM_FPS_RUN
    elseif S.currentAnim == C.ANIM_ATTACK then
        fps = C.ANIM_FPS_ATTACK
    elseif S.currentAnim == C.ANIM_BLOCK then
        fps = C.ANIM_FPS_BLOCK
    elseif S.currentAnim == C.ANIM_CHARGE then
        fps = C.ANIM_FPS_CHARGE
    elseif S.currentAnim == C.ANIM_HEAL then
        fps = 10  -- 治愈动画帧率
    elseif S.currentAnim == C.ANIM_CROUCH then
        fps = C.ANIM_FPS_CROUCH
    elseif S.currentAnim == C.ANIM_CROUCH_WALK then
        fps = C.ANIM_FPS_CROUCH
    end

    -- 更新动画帧
    S.animTimer = S.animTimer + dt
    local frameInterval = 1.0 / fps
    if S.animTimer >= frameInterval then
        S.animTimer = S.animTimer - frameInterval
        S.animFrame = S.animFrame + 1

        if S.currentAnim == C.ANIM_ATTACK then
            -- 攻击动画不循环
            if S.animFrame >= C.SPRITE_FRAMES then
                S.animFrame = C.SPRITE_FRAMES - 1
            end
        elseif S.currentAnim == C.ANIM_BLOCK then
            -- 格挡动画：0-2起手，3-9结界持续循环，10-11收杖
            if S.isBlocking then
                if S.animFrame > 9 then
                    S.animFrame = 3
                end
            else
                if S.animFrame >= C.SPRITE_FRAMES then
                    S.animFrame = C.SPRITE_FRAMES - 1
                end
            end
        elseif S.currentAnim == C.ANIM_CHARGE then
            -- 蓄力动画：角色1: 0-2起手，3-8蓄力循环，9-11释放
            --           角色2: 0-1起手，2-4蓄力循环，5-11释放
            if S.isCharging then
                if S.currentCharacter == 2 then
                    if S.animFrame > 4 then
                        S.animFrame = 2
                    end
                else
                    if S.animFrame > 8 then
                        S.animFrame = 3
                    end
                end
            elseif S.chargeReleased then
                if S.animFrame >= C.SPRITE_FRAMES then
                    S.animFrame = C.SPRITE_FRAMES - 1
                end
            else
                if S.animFrame >= C.SPRITE_FRAMES then
                    S.animFrame = C.SPRITE_FRAMES - 1
                end
            end
        elseif S.currentAnim == C.ANIM_HEAL then
            -- 治愈动画：单次播放，到末帧停住
            if S.animFrame >= C.SPRITE_FRAMES then
                S.animFrame = C.SPRITE_FRAMES - 1
            end
        elseif S.currentAnim == C.ANIM_CROUCH then
            -- 蹲下动画使用 crouchFrameMap_ 索引
            if S.crouchPhase == "enter" then
                if S.animFrame > C.CROUCH_ENTER_END then
                    S.animFrame = C.CROUCH_LOOP_START
                    S.crouchPhase = "loop"
                end
            elseif S.crouchPhase == "loop" then
                if S.animFrame > C.CROUCH_LOOP_END then
                    S.animFrame = C.CROUCH_LOOP_START
                end
            end
        elseif S.currentAnim == C.ANIM_CROUCH_WALK then
            -- 蹲走动画：交替播放
            S.animFrame = S.animFrame % 2
        else
            -- 其他动画循环
            S.animFrame = S.animFrame % C.SPRITE_FRAMES
        end
    end
end

return M
