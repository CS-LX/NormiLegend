-- ============================================================================
-- Combat.lua - 战斗系统
-- 职责: 施法、投射物、冰晶群、近战判定、蝴蝶突进、受击处理
-- ============================================================================

local C = require("GameConfig")
local S = require("GameState")
local Enemy = require("Enemy")
local BatEnemy = require("BatEnemy")
local CastleEnemies = require("CastleEnemies")
local GMConsole = require("GMConsole")
local Targetable = require("Targetable")

local M = {}

-- ============================================================================
-- 注册敌人为可索敌目标（游戏开始时调用）
-- ============================================================================

--- 注册所有敌人模块到 Targetable 系统
function M.RegisterEnemyProviders()
    Targetable.Register("enemy", {
        GetAll = Enemy.GetAll,
        TakeDamage = Enemy.TakeDamage,
        ApplyBleed = Enemy.ApplyBleed,
        ApplyFreeze = Enemy.ApplyFreeze,
        CheckProjectileHits = Enemy.CheckProjectileHits,
        CheckCrystalHits = Enemy.CheckCrystalHits,
        heightRange = 1.5,
        hitboxW = 0.8,
        hitboxH = 1.0,
    })
    Targetable.Register("batEnemy", {
        GetAll = BatEnemy.GetAll,
        TakeDamage = BatEnemy.TakeDamage,
        ApplyBleed = BatEnemy.ApplyBleed,
        ApplyFreeze = BatEnemy.ApplyFreeze,
        CheckProjectileHits = BatEnemy.CheckProjectileHits,
        CheckCrystalHits = BatEnemy.CheckCrystalHits,
        heightRange = 2.5,
        hitboxW = 0.8,
        hitboxH = 1.5,
    })
    Targetable.Register("castleEnemy", {
        GetAll = CastleEnemies.GetAll,
        TakeDamage = CastleEnemies.TakeDamage,
        ApplyBleed = CastleEnemies.ApplyBleed,
        ApplyFreeze = CastleEnemies.ApplyFreeze,
        CheckProjectileHits = CastleEnemies.CheckProjectileHits,
        CheckCrystalHits = CastleEnemies.CheckCrystalHits,
        heightRange = 2.5,
        hitboxW = 0.8,
        hitboxH = 1.5,
    })
    print("[COMBAT] 敌人已注册到 Targetable 系统")
end

--- 注销所有敌人（关卡切换时调用）
function M.UnregisterEnemyProviders()
    Targetable.Unregister("enemy")
    Targetable.Unregister("batEnemy")
    Targetable.Unregister("castleEnemy")
end

-- ============================================================================
-- 施法 - 角色1:冰晶投射物 / 角色2:近战镰刀斩
-- ============================================================================

--- 发动攻击（角色1发射冰晶，角色2近战斩击）
function M.CastSpell()
    if S.isAttacking then return end
    S.isAttacking = true
    S.attackTimer = 0.0
    S.currentAnim = C.ANIM_ATTACK
    S.animFrame = 0
    S.animTimer = 0.0

    if S.currentCharacter == 2 then
        -- 角色2：近战攻击，延迟0.5秒后判定前方敌人
        S.pendingMeleeHit = {
            delay = 0.5,
            dir = S.facingRight and 1 or -1,
        }
    else
        -- 角色1：设置延迟发射（0.15秒后生成冰晶）
        S.pendingProjectile = {
            delay = S.projectileDelay,
            dir = S.facingRight and 1 or -1,
        }
    end
end

-- ============================================================================
-- 延迟投射物发射
-- ============================================================================

--- 处理延迟投射物（角色1冰晶弹）
---@param dt number
function M.ProcessPendingProjectile(dt)
    if not S.pendingProjectile then return end
    S.pendingProjectile.delay = S.pendingProjectile.delay - dt
    if S.pendingProjectile.delay <= 0 then
        local pos = S.playerNode.position2D
        local dir = S.pendingProjectile.dir
        local spawnX = pos.x + dir * 0.8
        local spawnY = pos.y + 0.2
        table.insert(S.projectiles, {
            x = spawnX,
            y = spawnY,
            vx = dir * C.PROJECTILE_SPEED,
            vy = 0,
            life = C.PROJECTILE_LIFETIME,
            size = 0.3,
        })
        S.pendingProjectile = nil
    end
end

-- ============================================================================
-- 角色2 近战判定
-- ============================================================================

--- 处理角色2延迟近战判定
---@param dt number
function M.ProcessPendingMelee(dt)
    if not S.pendingMeleeHit then return end
    S.pendingMeleeHit.delay = S.pendingMeleeHit.delay - dt
    if S.pendingMeleeHit.delay > 0 then return end

    local pos = S.playerNode.position2D
    local dir = S.pendingMeleeHit.dir
    -- 获取当前等级伤害
    local meleeDmg = C.CHAR2_MELEE_DAMAGE + (S.skillList2[1].level - 1)

    -- 通过 Targetable 接口进行近战命中判定
    local hitCount = Targetable.CheckMeleeHits(pos.x, pos.y, dir, C.CHAR2_MELEE_RANGE, meleeDmg)

    -- 吸血buff
    if hitCount > 0 and S.lifestealBuffTimer > 0 then
        local healAmt = math.floor(meleeDmg * C.LIFESTEAL_RATIO) * hitCount
        if healAmt > 0 then
            S.playerHP = math.min(S.playerHP + healAmt, S.playerMaxHP)
        end
    end

    S.pendingMeleeHit = nil
end

-- ============================================================================
-- 蝴蝶突进（角色2 Q技能）
-- ============================================================================

--- 更新蝴蝶突进状态
---@param dt number
function M.UpdateDash(dt)
    if not S.isDashing then return end

    S.dashTimer = S.dashTimer + dt
    local pos = S.playerNode.position2D
    local traveled = math.abs(pos.x - S.dashStartX)

    -- 通过 Targetable 接口进行突进伤害判定
    local dashHits = Targetable.CheckDashHits(pos.x, pos.y, S.dashDir, C.CHAR2_DASH_DAMAGE, S.dashHitEnemies, C.CHAR2_BLEED_DURATION, C.CHAR2_BLEED_DPS)

    -- 吸血buff
    if dashHits > 0 and S.lifestealBuffTimer > 0 then
        local healAmt = math.floor(C.CHAR2_DASH_DAMAGE * C.LIFESTEAL_RATIO) * dashHits
        if healAmt > 0 then
            S.playerHP = math.min(S.playerHP + healAmt, S.playerMaxHP)
        end
    end

    -- 突进结束条件：距离够了或时间超限
    if traveled >= S.dashTargetDist or S.dashTimer >= (S.dashTargetDist / C.CHAR2_DASH_SPEED + 0.1) then
        S.isDashing = false
        if S.playerBody then
            S.playerBody.linearVelocity = Vector2(0, S.playerBody.linearVelocity.y)
        end
    end
end

-- ============================================================================
-- 投射物更新
-- ============================================================================

--- 更新所有飞行中的投射物
---@param dt number
function M.UpdateProjectiles(dt)
    local i = 1
    while i <= #S.projectiles do
        local p = S.projectiles[i]
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(S.projectiles, i)
        else
            i = i + 1
        end
    end
end

-- ============================================================================
-- 冰晶群更新
-- ============================================================================

--- 更新地面冰晶群（生命周期 + 伤害判定）
---@param dt number
function M.UpdateIceCrystals(dt)
    local i = 1
    while i <= #S.iceCrystals do
        local g = S.iceCrystals[i]
        g.life = g.life - dt
        g.spawnTime = g.spawnTime + dt
        if g.life <= 0 then
            table.remove(S.iceCrystals, i)
        else
            i = i + 1
        end
    end
    -- 冰晶群命中敌人（伤害+冰冻，通过 Targetable 接口）
    Targetable.CheckCrystalHits(S.iceCrystals, C.CHARGE_DAMAGE, C.CHARGE_FREEZE_DURATION)
end

-- ============================================================================
-- 投射物命中检测
-- ============================================================================

--- 检测投射物是否命中敌人（通过 Targetable 接口）
function M.CheckProjectileHits()
    Targetable.CheckProjectileHits(S.projectiles, C.PROJECTILE_DAMAGE)
end

-- ============================================================================
-- 受击处理
-- ============================================================================

--- 处理玩家受到的总伤害
---@param normalDmg number 普通攻击伤害
---@param skillDmg number 技能攻击伤害
---@param batDmg number 蝙蝠攻击伤害
---@param castleDmg number 古堡敌人攻击伤害
function M.ProcessDamage(normalDmg, skillDmg, batDmg, castleDmg)
    local totalDmg = normalDmg + skillDmg + batDmg + castleDmg

    -- 无敌模式跳过伤害
    if totalDmg > 0 and GMConsole.IsInvincible() then
        totalDmg = 0
    end

    if totalDmg > 0 and S.isBlocking then
        -- 格挡减半伤害（不触发僵直）
        S.playerHP = math.max(0, S.playerHP - totalDmg * 0.5)
    elseif totalDmg > 0 then
        S.playerHP = math.max(0, S.playerHP - totalDmg)
        -- 蓄力中：普攻不打断，技能才打断
        if S.isCharging and skillDmg == 0 then
            -- 普攻命中蓄力中的玩家，只扣血不打断
        else
            -- 触发受击僵直
            S.isHit = true
            S.hitStunTimer = C.HIT_STUN_DURATION
            -- 中断其他动作
            S.isAttacking = false
            S.isCharging = false
            S.chargeReleased = false
            S.isHealing = false
            S.currentAnim = C.ANIM_HIT
            S.animFrame = 0
            S.animTimer = 0.0
        end
    end
end

-- ============================================================================
-- 蓄力释放：生成冰晶群（角色1）
-- ============================================================================

--- 角色1蓄力释放时生成冰晶群
---@param chargeTimer number 蓄力时长
function M.SpawnIceCrystals(chargeTimer)
    local pos = S.playerNode.position2D
    local dir = S.facingRight and 1 or -1
    local power = math.min(chargeTimer / C.CHARGE_MAX_DURATION, 1.0)
    local maxRange = C.ICE_CRYSTAL_MIN_DIST + (C.ICE_CRYSTAL_MAX_DIST - C.ICE_CRYSTAL_MIN_DIST) * power
    local baseX = pos.x + dir * maxRange
    local groundY = pos.y - 0.5

    -- 索敌：通过 Targetable 接口查找最近目标，优先生成在目标脚下
    local closest = Targetable.FindClosest(pos.x, pos.y, dir, C.ICE_CRYSTAL_MIN_DIST, maxRange)
    if closest then
        baseX = closest.x
        groundY = closest.y - 0.5
    end

    -- 生成冰晶群
    local crystals = {}
    for i = 1, C.ICE_CRYSTAL_COUNT do
        local spread = (i - (C.ICE_CRYSTAL_COUNT + 1) / 2) * 0.6 * dir
        local centerFactor = 1.0 - math.abs(i - (C.ICE_CRYSTAL_COUNT + 1) / 2) / ((C.ICE_CRYSTAL_COUNT + 1) / 2)
        local h = C.ICE_CRYSTAL_HEIGHT * (0.4 + centerFactor * 0.6) * (0.8 + math.random() * 0.2)
        table.insert(crystals, {
            x = baseX + spread,
            height = h,
            width = 0.2 + math.random() * 0.25,
            delay = (i - 1) * 0.05,
            angle = (math.random() - 0.5) * 0.3,
        })
    end

    table.insert(S.iceCrystals, {
        crystals = crystals,
        x = baseX,
        groundY = groundY,
        radius = ((C.ICE_CRYSTAL_COUNT - 1) / 2) * 0.6,
        life = C.ICE_CRYSTAL_LIFETIME,
        maxLife = C.ICE_CRYSTAL_LIFETIME,
        power = power,
        spawnTime = 0,
        dir = dir,
    })
end

return M
