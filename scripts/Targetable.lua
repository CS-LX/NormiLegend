-- ============================================================================
-- Targetable.lua - 可被索敌接口（统一目标注册表）
-- 职责: 所有可被玩家攻击命中的目标统一注册、查询、命中判定
-- ============================================================================
-- 使用方式:
--   1. 注册目标提供者: Targetable.Register("enemy", provider)
--   2. 战斗系统调用: Targetable.CheckProjectileHits / FindClosest / CheckMeleeHits
--   3. 不再需要时注销: Targetable.Unregister("enemy")
--
-- Provider 接口:
--   必须:
--     .GetAll()            -> { {x, y, alive, [w, h]} , ... }
--     .TakeDamage(target, damage)
--   可选:
--     .ApplyBleed(target, duration, dps)
--     .ApplyFreeze(target, duration)
--     .CheckProjectileHits(projectiles, damage)  -- 自定义投射物碰撞逻辑
--     .CheckCrystalHits(crystalGroups, damage, freezeDuration)
--     .heightRange         -> number (垂直检测范围，默认1.5)
--     .hitboxW             -> number (命中判定宽度，默认0.8)
--     .hitboxH             -> number (命中判定高度，默认1.0)
-- ============================================================================

local Targetable = {}

---@type table<string, table>
local providers_ = {}

--- 注册一个可被索敌的目标提供者
---@param name string 唯一标识名
---@param provider table 需要实现 GetAll() 和 TakeDamage(t, dmg)
function Targetable.Register(name, provider)
    providers_[name] = provider
end

--- 注销目标提供者
---@param name string
function Targetable.Unregister(name)
    providers_[name] = nil
end

--- 获取所有注册的提供者
---@return table<string, table>
function Targetable.GetProviders()
    return providers_
end

--- 清空所有注册
function Targetable.Clear()
    providers_ = {}
end

-- ============================================================================
-- 投射物命中检测（遍历所有 Provider）
-- ============================================================================

--- 检测投射物命中所有已注册目标
---@param projectiles table[] 投射物列表
---@param damage number 伤害值
function Targetable.CheckProjectileHits(projectiles, damage)
    for _, prov in pairs(providers_) do
        if prov.CheckProjectileHits then
            -- 使用 Provider 自定义的命中逻辑
            prov.CheckProjectileHits(projectiles, damage)
        else
            -- 默认命中逻辑（支持目标自带 w/h 覆盖 provider 级别 hitbox）
            local defHitW = prov.hitboxW or 0.8
            local defHitH = prov.hitboxH or 1.0
            for pi = #projectiles, 1, -1 do
                local p = projectiles[pi]
                for _, e in ipairs(prov.GetAll()) do
                    if e.alive then
                        local hitW = (e.w and e.w / 2) or defHitW
                        local hitH = (e.h and e.h / 2) or defHitH
                        local dx = math.abs(p.x - e.x)
                        local dy = math.abs(p.y - e.y)
                        if dx < hitW and dy < hitH then
                            prov.TakeDamage(e, damage)
                            table.remove(projectiles, pi)
                            break
                        end
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- 冰晶群命中检测
-- ============================================================================

--- 检测冰晶群命中所有已注册目标
---@param crystalGroups table[] 冰晶群列表
---@param damage number 伤害值
---@param freezeDuration number 冰冻持续时间
function Targetable.CheckCrystalHits(crystalGroups, damage, freezeDuration)
    for _, prov in pairs(providers_) do
        if prov.CheckCrystalHits then
            prov.CheckCrystalHits(crystalGroups, damage, freezeDuration)
        else
            -- 默认冰晶群命中逻辑（半径检测）
            for _, group in ipairs(crystalGroups) do
                if group.spawnTime and group.spawnTime > 0.1 then
                    for _, e in ipairs(prov.GetAll()) do
                        if e.alive then
                            local dx = math.abs(e.x - group.x)
                            local dy = math.abs(e.y - group.groundY)
                            if dx < (group.radius + 0.5) and dy < 2.0 then
                                prov.TakeDamage(e, damage)
                                if prov.ApplyFreeze then
                                    prov.ApplyFreeze(e, freezeDuration)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ============================================================================
-- 索敌：查找最近目标（蓄力就近索敌）
-- ============================================================================

--- 查找指定方向范围内最近的目标
---@param posX number 起点X
---@param posY number 起点Y
---@param dir number 方向(1=右, -1=左)
---@param minDist number 最小距离
---@param maxDist number 最大距离
---@return table|nil {x, y, target, provider} 或 nil
function Targetable.FindClosest(posX, posY, dir, minDist, maxDist)
    local closest = nil
    local closestDist = math.huge
    for _, prov in pairs(providers_) do
        for _, e in ipairs(prov.GetAll()) do
            if e.alive then
                local dx = e.x - posX
                if (dir > 0 and dx > 0 and dx <= maxDist) or (dir < 0 and dx < 0 and math.abs(dx) <= maxDist) then
                    local dist = math.abs(dx)
                    if dist >= minDist and dist < closestDist then
                        closestDist = dist
                        closest = { x = e.x, y = e.y, target = e, provider = prov }
                    end
                end
            end
        end
    end
    return closest
end

-- ============================================================================
-- 近战命中检测
-- ============================================================================

--- 检测近战攻击命中所有已注册目标
---@param posX number 玩家X
---@param posY number 玩家Y
---@param dir number 方向(1=右, -1=左)
---@param range number 攻击距离
---@param damage number 伤害值
---@return number hitCount 命中数量
function Targetable.CheckMeleeHits(posX, posY, dir, range, damage)
    local hitCount = 0
    for _, prov in pairs(providers_) do
        local heightRange = prov.heightRange or 1.5
        for _, e in ipairs(prov.GetAll()) do
            if e.alive then
                local dx = e.x - posX
                local dy = e.y - posY
                local hit = false
                if dir > 0 and dx > 0 and dx <= range and math.abs(dy) < heightRange then
                    hit = true
                elseif dir < 0 and dx < 0 and math.abs(dx) <= range and math.abs(dy) < heightRange then
                    hit = true
                end
                if hit then
                    prov.TakeDamage(e, damage)
                    hitCount = hitCount + 1
                end
            end
        end
    end
    return hitCount
end

-- ============================================================================
-- 突进命中检测
-- ============================================================================

--- 检测突进路径上的目标
---@param posX number 玩家X
---@param posY number 玩家Y
---@param dashDir number 突进方向(1/-1)
---@param damage number 伤害值
---@param dashHitSet table 已命中集合（防止重复命中）
---@param bleedDur number|nil 流血持续时间
---@param bleedDps number|nil 流血每秒伤害
---@return number hitCount 本次新命中数量
function Targetable.CheckDashHits(posX, posY, dashDir, damage, dashHitSet, bleedDur, bleedDps)
    local hitCount = 0
    for name, prov in pairs(providers_) do
        local heightRange = prov.heightRange or 2.0
        for _, e in ipairs(prov.GetAll()) do
            local key = name .. tostring(e)
            if e.alive and not dashHitSet[key] then
                local dx = e.x - posX
                local dy = e.y - posY
                if math.abs(dy) < heightRange then
                    if (dashDir > 0 and dx >= -0.5 and dx <= 1.5) or (dashDir < 0 and dx <= 0.5 and dx >= -1.5) then
                        prov.TakeDamage(e, damage)
                        if bleedDur and bleedDps and prov.ApplyBleed then
                            prov.ApplyBleed(e, bleedDur, bleedDps)
                        end
                        dashHitSet[key] = true
                        hitCount = hitCount + 1
                    end
                end
            end
        end
    end
    return hitCount
end

return Targetable
