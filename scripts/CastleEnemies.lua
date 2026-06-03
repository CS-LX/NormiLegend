-- ============================================================================
-- CastleEnemies.lua - 古堡通用敌人系统
-- 数据驱动的多类型敌人管理（灰狼、飞龙、骷髅兵、幽灵、石像鬼）
-- ============================================================================
local CastleEnemies = {}

-- 动画状态
local ANIM_IDLE = "idle"
local ANIM_ATTACK = "attack"
local ANIM_HIT = "hit"
local ANIM_DEATH = "death"

-- 序列帧配置
local SPRITE_COLS = 4
local SPRITE_ROWS = 1

-- NanoVG 上下文
local nvg = nil

-- ============================================================================
-- 敌人类型定义
-- ============================================================================
CastleEnemies.TYPES = {
    wolf = {
        name = "灰狼",
        flying = false,
        CONFIG = {
            maxHP = 40,
            damage = 4,
            attackRange = 2.8,
            detectRange = 9.0,
            moveSpeed = 2.5,
            attackCooldown = 2.0,
            scale = 8.0,
            hitStun = 0.3,
        },
        images = {},  -- 运行时填充
    },
    wyvern = {
        name = "飞龙",
        flying = true,
        CONFIG = {
            maxHP = 55,
            damage = 5,
            attackRange = 2.8,
            detectRange = 10.0,
            moveSpeed = 3.0,
            attackCooldown = 3.0,
            scale = 7.5,
            hitStun = 0.3,
            flyAmplitude = 0.6,
            flyFrequency = 1.8,
        },
        images = {},
    },
    skeleton = {
        name = "骷髅兵",
        flying = false,
        CONFIG = {
            maxHP = 60,
            damage = 3,
            attackRange = 2.5,
            detectRange = 7.0,
            moveSpeed = 2.0,
            attackCooldown = 2.5,
            scale = 8.8,
            hitStun = 0.3,
        },
        images = {},
    },
    ghost = {
        name = "幽灵",
        flying = true,
        CONFIG = {
            maxHP = 30,
            damage = 1,
            attackRange = 2.8,
            detectRange = 8.0,
            moveSpeed = 2.5,
            attackCooldown = 2.8,
            scale = 7.0,
            hitStun = 0.3,
            flyAmplitude = 0.8,
            flyFrequency = 1.5,
        },
        images = {},
    },
    gargoyle = {
        name = "石像鬼",
        flying = true,
        CONFIG = {
            maxHP = 70,
            damage = 2,
            attackRange = 2.5,
            detectRange = 8.0,
            moveSpeed = 1.7,
            attackCooldown = 3.5,
            scale = 6.0,
            hitStun = 0.3,
            flyAmplitude = 0.4,
            flyFrequency = 2.0,
        },
        images = {},
    },
}

-- 类型顺序（用于遍历）
CastleEnemies.TYPE_ORDER = { "wolf", "wyvern", "skeleton", "ghost", "gargoyle" }

-- 活跃的敌人列表
local enemies_ = {}

-- ============================================================================
-- 初始化（加载资源）
-- ============================================================================
function CastleEnemies.Init(nvgCtx)
    nvg = nvgCtx
    local flags = NVG_IMAGE_NEAREST or 32

    local imagePaths = {
        wolf = {
            idle   = "image/wolf_idle_4f_20260601151726.png",
            attack = "image/wolf_attack_4f_20260601151711.png",
            hit    = "image/wolf_hit_4f_20260601151712.png",
            death  = "image/wolf_death_4f_20260601151716.png",
        },
        wyvern = {
            idle   = "image/wyvern_idle_4f_20260601151710.png",
            attack = "image/wyvern_attack_4f_20260601151713.png",
            hit    = "image/wyvern_hit_4f_20260601151714.png",
            death  = "image/wyvern_death_4f_20260601151715.png",
        },
        skeleton = {
            idle   = "image/skeleton_idle_4f_20260601151720.png",
            attack = "image/skeleton_attack_4f_20260601151722.png",
            hit    = "image/skeleton_hit_4f_20260601151816.png",
            death  = "image/skeleton_death_4f_20260601151819.png",
        },
        ghost = {
            idle   = "image/ghost_idle_4f_20260601151808.png",
            attack = "image/ghost_attack_4f_20260601151813.png",
            hit    = "image/ghost_hit_4f_20260601151814.png",
            death  = "image/ghost_death_4f_20260601151820.png",
        },
        gargoyle = {
            idle   = "image/gargoyle_idle_4f_20260601151811.png",
            attack = "image/gargoyle_attack_4f_20260601151830.png",
            hit    = "image/gargoyle_hit_4f_20260601151817.png",
            death  = "image/gargoyle_death_4f_20260601151815.png",
        },
    }

    for typeName, paths in pairs(imagePaths) do
        local t = CastleEnemies.TYPES[typeName]
        t.images = {
            idle   = nvgCreateImage(nvg, paths.idle, flags),
            attack = nvgCreateImage(nvg, paths.attack, flags),
            hit    = nvgCreateImage(nvg, paths.hit, flags),
            death  = nvgCreateImage(nvg, paths.death, flags),
        }
    end
    print("[CASTLE] 古堡敌人资源加载完成（5种）")
end

--- 获取指定类型的图片句柄（供序列帧编辑器使用）
function CastleEnemies.GetImages(typeName)
    local t = CastleEnemies.TYPES[typeName]
    if t then return t.images end
    return {}
end

--- 获取指定类型的图片尺寸
function CastleEnemies.GetImageSize(typeName)
    local t = CastleEnemies.TYPES[typeName]
    if t and t.images and t.images.idle and t.images.idle > 0 and nvg then
        local w, h = nvgImageSize(nvg, t.images.idle)
        return w, h
    end
    return 0, 0
end

-- ============================================================================
-- 生成敌人
-- ============================================================================
function CastleEnemies.Spawn(typeName, x, y)
    local typeData = CastleEnemies.TYPES[typeName]
    if not typeData then
        print("[CASTLE] 未知敌人类型: " .. tostring(typeName))
        return nil
    end
    local cfg = typeData.CONFIG
    local e = {
        typeName = typeName,
        x = x,
        y = y,
        hp = cfg.maxHP,
        maxHP = cfg.maxHP,
        alive = true,
        facingRight = false,
        -- 动画
        anim = ANIM_IDLE,
        animFrame = 0,
        animTimer = 0.0,
        -- AI
        state = "idle",       -- idle/chase/attack/hit/death
        stateTimer = 0.0,
        attackCooldown = 1.0,
        hitStunTimer = 0.0,
        deathTimer = 0.0,
        -- 飞行参数（飞行型）
        flyPhase = math.random() * math.pi * 2,
        baseY = y,
        -- 巡逻
        patrolTargetX = x + (math.random() > 0.5 and 3 or -3),
        patrolTimer = 0.0,
        -- 攻击判定
        attackHitFrame = false,
        -- 冰冻
        freezeTimer = 0.0,
        -- 流血
        bleedTimer = 0.0,
        bleedDPS = 0,
        bleedAccum = 0.0,
        -- 血条闪烁
        displayHP = cfg.maxHP,
        hpFlashTimer = 0.0,
    }
    table.insert(enemies_, e)
    return e
end

-- ============================================================================
-- 获取/清空
-- ============================================================================
function CastleEnemies.GetAll()
    return enemies_
end

function CastleEnemies.Clear()
    enemies_ = {}
end

-- ============================================================================
-- 更新所有敌人
-- ============================================================================
function CastleEnemies.Update(dt, playerX, playerY, camX, camY, screenW, screenH, pixelsPerUnit)
    for i = #enemies_, 1, -1 do
        local e = enemies_[i]
        if not e.alive then
            e.deathTimer = e.deathTimer + dt
            if e.deathTimer > 0.9 then
                table.remove(enemies_, i)
            else
                CastleEnemies._UpdateAnim(e, dt)
            end
        else
            -- 血条闪烁计时
            if e.hpFlashTimer > 0 then
                e.hpFlashTimer = e.hpFlashTimer - dt
                if e.hpFlashTimer <= 0 then
                    e.hpFlashTimer = 0
                    e.displayHP = e.hp
                end
            end
            CastleEnemies._UpdateAI(e, dt, playerX, playerY, camX, camY, screenW, screenH, pixelsPerUnit)
            CastleEnemies._UpdateAnim(e, dt)
        end
    end
end

-- ============================================================================
-- AI 状态机
-- ============================================================================
function CastleEnemies._UpdateAI(e, dt, playerX, playerY, camX, camY, screenW, screenH, pixelsPerUnit)
    local typeData = CastleEnemies.TYPES[e.typeName]
    local cfg = typeData.CONFIG

    -- 流血DOT
    if e.bleedTimer > 0 then
        e.bleedTimer = e.bleedTimer - dt
        e.bleedAccum = e.bleedAccum + dt
        if e.bleedAccum >= 1.0 then
            e.bleedAccum = e.bleedAccum - 1.0
            e.hp = e.hp - e.bleedDPS
            if e.hp <= 0 then
                e.hp = 0
                e.alive = false
                e.anim = ANIM_DEATH
                e.animFrame = 0
                e.deathTimer = 0
                e.state = "death"
                return
            end
        end
        if e.bleedTimer <= 0 then e.bleedTimer = 0; e.bleedDPS = 0 end
    end

    -- 冰冻
    if e.freezeTimer > 0 then
        e.freezeTimer = e.freezeTimer - dt
        if e.freezeTimer <= 0 then e.freezeTimer = 0 end
        return
    end

    -- 冷却
    if e.attackCooldown > 0 then e.attackCooldown = e.attackCooldown - dt end

    -- 受击僵直
    if e.hitStunTimer > 0 then
        e.hitStunTimer = e.hitStunTimer - dt
        return
    end

    -- 飞行浮动
    local floatOffset = 0
    if typeData.flying and cfg.flyAmplitude then
        e.flyPhase = e.flyPhase + dt * cfg.flyFrequency
        floatOffset = math.sin(e.flyPhase) * cfg.flyAmplitude
    end

    -- 屏幕范围
    local halfW = (screenW / pixelsPerUnit) / 2
    local halfH = (screenH / pixelsPerUnit) / 2
    local minX = camX - halfW + 1
    local maxX = camX + halfW - 1
    local minY = camY - halfH + 1
    local maxY = camY + halfH - 1

    local dx = playerX - e.x
    local dy = playerY - e.y
    local dist = math.sqrt(dx * dx + dy * dy)
    e.facingRight = dx > 0

    -- 状态机
    if e.state == "attack" then
        e.stateTimer = e.stateTimer + dt
        if e.stateTimer >= 0.6 then
            e.state = "idle"
            e.stateTimer = 0
            e.attackHitFrame = false
            e.anim = ANIM_IDLE
            e.animFrame = 0
            e.animTimer = 0
        end
    elseif e.state == "hit" then
        e.stateTimer = e.stateTimer + dt
        if e.stateTimer >= cfg.hitStun then
            e.state = "idle"
            e.stateTimer = 0
            e.anim = ANIM_IDLE
            e.animFrame = 0
            e.animTimer = 0
        end
    else
        -- 正常 AI
        if dist <= cfg.attackRange and e.attackCooldown <= 0 then
            e.state = "attack"
            e.stateTimer = 0
            e.attackCooldown = cfg.attackCooldown
            e.attackHitFrame = false
            e.anim = ANIM_ATTACK
            e.animFrame = 0
            e.animTimer = 0
        elseif dist <= cfg.detectRange then
            e.state = "chase"
            local dirX = dx / dist
            local dirY = dy / dist
            e.x = e.x + dirX * cfg.moveSpeed * dt
            if typeData.flying then
                e.y = e.y + dirY * cfg.moveSpeed * dt * 0.5 + floatOffset * dt
            end
            e.anim = ANIM_IDLE  -- 用idle帧表示移动
        else
            e.state = "idle"
            -- 巡逻
            e.patrolTimer = e.patrolTimer + dt
            if e.patrolTimer > 3.0 then
                e.patrolTimer = 0
                e.patrolTargetX = e.x + (math.random() * 6 - 3)
            end
            local pdx = e.patrolTargetX - e.x
            if math.abs(pdx) > 0.3 then
                local dir = pdx > 0 and 1 or -1
                e.x = e.x + dir * cfg.moveSpeed * 0.4 * dt
                e.facingRight = dir > 0
            end
            if typeData.flying then
                e.baseY = e.baseY + floatOffset * dt
                e.y = e.baseY + floatOffset * 0.5
            end
            e.anim = ANIM_IDLE
        end

        -- 屏幕范围限制
        e.x = math.max(minX, math.min(maxX, e.x))
        if typeData.flying then
            e.y = math.max(minY, math.min(maxY, e.y))
        end
    end
end

-- ============================================================================
-- 动画帧更新
-- ============================================================================
function CastleEnemies._UpdateAnim(e, dt)
    e.animTimer = e.animTimer + dt
    local fps = 6
    if e.anim == ANIM_ATTACK then fps = 8
    elseif e.anim == ANIM_HIT then fps = 10
    elseif e.anim == ANIM_DEATH then fps = 5
    end

    local interval = 1.0 / fps
    if e.animTimer >= interval then
        e.animTimer = e.animTimer - interval
        e.animFrame = e.animFrame + 1

        if e.anim == ANIM_ATTACK or e.anim == ANIM_HIT or e.anim == ANIM_DEATH then
            if e.animFrame >= 4 then e.animFrame = 3 end
        else
            e.animFrame = e.animFrame % 4
        end
    end
end

-- ============================================================================
-- 受伤
-- ============================================================================
function CastleEnemies.TakeDamage(e, damage)
    if not e.alive then return end
    local cfg = CastleEnemies.TYPES[e.typeName].CONFIG
    if e.hpFlashTimer <= 0 then
        e.displayHP = e.hp
    end
    e.hpFlashTimer = 0.6
    e.hp = e.hp - damage
    if e.hp <= 0 then
        e.hp = 0
        e.alive = false
        e.anim = ANIM_DEATH
        e.animFrame = 0
        e.animTimer = 0
        e.deathTimer = 0
        e.state = "death"
    else
        e.state = "hit"
        e.stateTimer = 0
        e.hitStunTimer = cfg.hitStun
        e.anim = ANIM_HIT
        e.animFrame = 0
        e.animTimer = 0
    end
end

-- ============================================================================
-- 检测攻击命中玩家
-- ============================================================================
function CastleEnemies.CheckAttackHits(playerX, playerY)
    local totalDmg = 0
    for _, e in ipairs(enemies_) do
        if e.alive and e.state == "attack" and not e.attackHitFrame then
            if e.animFrame >= 2 then
                local cfg = CastleEnemies.TYPES[e.typeName].CONFIG
                local dx = playerX - e.x
                local dy = playerY - e.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist <= cfg.attackRange then
                    totalDmg = totalDmg + cfg.damage
                    e.attackHitFrame = true
                end
            end
        end
    end
    return totalDmg
end

-- ============================================================================
-- 冰冻
-- ============================================================================
function CastleEnemies.ApplyFreeze(e, duration)
    if not e.alive then return end
    e.freezeTimer = duration
    if e.state == "attack" or e.state == "chase" then
        e.state = "idle"
        e.stateTimer = 0
        e.anim = ANIM_IDLE
        e.animFrame = 0
        e.animTimer = 0
    end
end

-- ============================================================================
-- 流血
-- ============================================================================
function CastleEnemies.ApplyBleed(e, duration, dps)
    if not e.alive then return end
    e.bleedTimer = duration
    e.bleedDPS = dps
    e.bleedAccum = 0.0
end

-- ============================================================================
-- 投射物命中检测
-- ============================================================================
function CastleEnemies.CheckProjectileHits(projectiles, damage)
    for pi = #projectiles, 1, -1 do
        local p = projectiles[pi]
        for _, e in ipairs(enemies_) do
            if e.alive then
                local dx = p.x - e.x
                local dy = p.y - e.y
                if math.abs(dx) < 1.0 and math.abs(dy) < 1.2 then
                    CastleEnemies.TakeDamage(e, damage)
                    table.remove(projectiles, pi)
                    break
                end
            end
        end
    end
end

-- ============================================================================
-- 冰晶群命中检测
-- ============================================================================
function CastleEnemies.CheckCrystalHits(crystalGroups, damage, freezeDuration)
    for _, group in ipairs(crystalGroups) do
        if group.spawnTime <= 0.3 and not group.castleHitApplied then
            local minX, maxX = math.huge, -math.huge
            for _, c in ipairs(group.crystals) do
                if c.x < minX then minX = c.x end
                if c.x > maxX then maxX = c.x end
            end
            minX = minX - 0.5
            maxX = maxX + 0.5
            local groundY = group.groundY

            for _, e in ipairs(enemies_) do
                if e.alive then
                    local typeData = CastleEnemies.TYPES[e.typeName]
                    local dyRange = typeData.flying and 3.0 or 2.0
                    if e.x >= minX and e.x <= maxX and math.abs(e.y - groundY) < dyRange then
                        CastleEnemies.TakeDamage(e, damage)
                        if e.alive and freezeDuration > 0 then
                            CastleEnemies.ApplyFreeze(e, freezeDuration)
                        end
                    end
                end
            end
            group.castleHitApplied = true
        end
    end
end

-- ============================================================================
-- 渲染所有敌人（不含血条）
-- ============================================================================
function CastleEnemies.Draw(width, height, camX, camY, SCREEN_W, SCREEN_H, PIXELS_PER_UNIT)
    if nvg == nil then return end
    local sx = width / SCREEN_W
    local sy = height / SCREEN_H

    for _, e in ipairs(enemies_) do
        local typeData = CastleEnemies.TYPES[e.typeName]
        local cfg = typeData.CONFIG
        local screenX = width / 2 + (e.x - camX) * PIXELS_PER_UNIT * sx
        local screenY = height / 2 - (e.y - camY) * PIXELS_PER_UNIT * sy

        -- 选择图片
        local img = typeData.images[e.anim] or typeData.images.idle

        -- 死亡渐隐
        local alpha = 1.0
        if not e.alive then
            alpha = math.max(0, 1.0 - e.deathTimer / 0.9)
        end

        -- 绘制精灵
        if img and img > 0 then
            local drawSize = 0.35 * cfg.scale * PIXELS_PER_UNIT * sx
            CastleEnemies._DrawFrame(img, e.animFrame, screenX, screenY, drawSize, not e.facingRight, alpha, typeData.flying)
        end

        -- 冰冻视觉效果（身上附着冰晶棱柱，与斯缇昔娅一致）
        if e.alive and e.freezeTimer > 0 then
            local freezeAlpha = math.min(e.freezeTimer / 0.5, 1.0)
            local drawSize = 0.35 * cfg.scale * PIXELS_PER_UNIT * sx
            local baseY = screenY - drawSize * 0.2

            local crystals = {
                { ox = -drawSize * 0.25, oy = -drawSize * 0.1, w = 7, h = 24, angle = -0.2 },
                { ox = drawSize * 0.15, oy = -drawSize * 0.25, w = 8, h = 28, angle = 0.15 },
                { ox = -drawSize * 0.05, oy = drawSize * 0.05, w = 7, h = 20, angle = 0.3 },
                { ox = drawSize * 0.3, oy = 0, w = 6, h = 16, angle = -0.25 },
                { ox = -drawSize * 0.3, oy = drawSize * 0.1, w = 5, h = 14, angle = 0.1 },
            }

            for _, cr in ipairs(crystals) do
                local cx = screenX + cr.ox
                local cy = baseY + cr.oy
                local cw = cr.w * sx
                local ch = cr.h * sx

                nvgSave(nvg)
                nvgTranslate(nvg, cx, cy)
                nvgRotate(nvg, cr.angle)

                -- 冰晶主体（半透明淡蓝色棱形）
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, 0, -ch / 2)
                nvgLineTo(nvg, cw / 2, -ch * 0.1)
                nvgLineTo(nvg, cw * 0.3, ch / 2)
                nvgLineTo(nvg, -cw * 0.3, ch / 2)
                nvgLineTo(nvg, -cw / 2, -ch * 0.1)
                nvgClosePath(nvg)
                nvgFillColor(nvg, nvgRGBA(160, 220, 255, math.floor(160 * freezeAlpha)))
                nvgFill(nvg)

                -- 冰晶高光边缘
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, 0, -ch / 2)
                nvgLineTo(nvg, cw / 2, -ch * 0.1)
                nvgLineTo(nvg, cw * 0.15, ch * 0.2)
                nvgClosePath(nvg)
                nvgFillColor(nvg, nvgRGBA(220, 240, 255, math.floor(200 * freezeAlpha)))
                nvgFill(nvg)

                -- 冰晶轮廓
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, 0, -ch / 2)
                nvgLineTo(nvg, cw / 2, -ch * 0.1)
                nvgLineTo(nvg, cw * 0.3, ch / 2)
                nvgLineTo(nvg, -cw * 0.3, ch / 2)
                nvgLineTo(nvg, -cw / 2, -ch * 0.1)
                nvgClosePath(nvg)
                nvgStrokeColor(nvg, nvgRGBA(200, 240, 255, math.floor(180 * freezeAlpha)))
                nvgStrokeWidth(nvg, 1.0 * sx)
                nvgStroke(nvg)

                nvgRestore(nvg)
            end
        end
    end
end

-- ============================================================================
-- 渲染所有血条（最上层）
-- ============================================================================
function CastleEnemies.DrawHealthBars(width, height, camX, camY, SCREEN_W, SCREEN_H, PIXELS_PER_UNIT)
    if nvg == nil then return end
    local sx = width / SCREEN_W
    local sy = height / SCREEN_H

    for _, e in ipairs(enemies_) do
        if e.alive then
            local typeData = CastleEnemies.TYPES[e.typeName]
            local cfg = typeData.CONFIG
            local screenX = width / 2 + (e.x - camX) * PIXELS_PER_UNIT * sx
            local screenY = height / 2 - (e.y - camY) * PIXELS_PER_UNIT * sy

            local barW = 40 * sx
            local barH = 4 * sy
            local drawSize = 0.35 * cfg.scale * PIXELS_PER_UNIT * sx
            local barX = screenX - barW / 2
            local barY = screenY - drawSize * 0.6

            -- 背景
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, barX, barY, barW, barH, 2)
            nvgFillColor(nvg, nvgRGBA(30, 30, 30, 200))
            nvgFill(nvg)

            -- 闪烁部分
            if e.hpFlashTimer > 0 and e.displayHP > e.hp then
                local displayRatio = e.displayHP / e.maxHP
                local flashAlpha = math.floor(180 + 75 * math.sin(e.hpFlashTimer * 18))
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, barX, barY, barW * displayRatio, barH, 2)
                nvgFillColor(nvg, nvgRGBA(255, 255, 255, flashAlpha))
                nvgFill(nvg)
            end

            -- 当前血量（红色）
            local hpRatio = e.hp / e.maxHP
            if hpRatio > 0 then
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, barX, barY, barW * hpRatio, barH, 2)
                nvgFillColor(nvg, nvgRGBA(220, 40, 40, 255))
                nvgFill(nvg)
            end

            -- 名字
            nvgFontFace(nvg, "sans")
            nvgFontSize(nvg, 9 * sx)
            nvgFillColor(nvg, nvgRGBA(255, 200, 200, 220))
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgText(nvg, screenX, barY - 1 * sy, typeData.name)
        end
    end
end

-- ============================================================================
-- 绘制序列帧
-- ============================================================================
function CastleEnemies._DrawFrame(img, frame, cx, cy, size, flipH, alpha, isFlying)
    local col = frame % SPRITE_COLS

    local actualW, actualH = nvgImageSize(nvg, img)
    local frameW = actualW / SPRITE_COLS
    local frameH = actualH / SPRITE_ROWS

    local maxDim = math.max(frameW, frameH)
    local drawW = size * (frameW / maxDim)
    local drawH = size * (frameH / maxDim)
    local drawX = cx - drawW / 2
    local drawY = isFlying and (cy - drawH / 2) or (cy - drawH * 0.7)

    nvgSave(nvg)

    if alpha < 1.0 then
        nvgGlobalAlpha(nvg, alpha)
    end

    if flipH then
        nvgTranslate(nvg, cx, 0)
        nvgScale(nvg, -1, 1)
        nvgTranslate(nvg, -cx, 0)
    end

    local patternW = drawW * (actualW / frameW)
    local patternH = drawH * (actualH / frameH)
    local patternX = drawX - col * frameW * (patternW / actualW)
    local patternY = drawY

    local paint = nvgImagePattern(nvg, patternX, patternY, patternW, patternH, 0, img, 1.0)
    nvgBeginPath(nvg)
    nvgRect(nvg, drawX, drawY, drawW, drawH)
    nvgFillPaint(nvg, paint)
    nvgFill(nvg)

    nvgRestore(nvg)
end

return CastleEnemies
