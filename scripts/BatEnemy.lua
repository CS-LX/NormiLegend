-- ============================================================================
-- BatEnemy.lua - 蝙蝠敌人系统模块
-- 飞行型敌人：在屏幕范围内飞行移动，接近玩家时攻击
-- ============================================================================
local BatEnemy = {}

-- 动画状态
BatEnemy.ANIM_FLY = "fly"
BatEnemy.ANIM_ATTACK = "attack"
BatEnemy.ANIM_HIT = "hit"

-- 默认参数（可通过GM控制台修改）
BatEnemy.CONFIG = {
    maxHP = 30,
    damage = 2,            -- 攻击伤害
    attackRange = 2.5,     -- 攻击距离（米）
    detectRange = 8.0,     -- 检测距离（米）
    moveSpeed = 3.5,       -- 飞行速度
    attackCooldown = 4.0,  -- 攻击冷却
    scale = 5.0,           -- 渲染缩放
    flyAmplitude = 0.5,    -- 飞行上下浮动幅度
    flyFrequency = 2.0,    -- 飞行浮动频率
}

-- 序列帧配置：4帧单行
local BAT_SPRITE_COLS = 4
local BAT_SPRITE_ROWS = 1
local BAT_ANIM_FPS = 6

-- 图片句柄
local imgFly_ = -1
local imgAttack_ = -1
local imgHit_ = -1

-- 活跃的蝙蝠列表
local bats_ = {}

-- NanoVG 上下文引用
local nvg = nil

-- ============================================================================
-- 初始化（加载资源）
-- ============================================================================
function BatEnemy.Init(nvgCtx)
    nvg = nvgCtx
    local flags = NVG_IMAGE_NEAREST or 32
    imgFly_    = nvgCreateImage(nvg, "image/bat_fly_4f_20260601145654.png", flags)
    imgAttack_ = nvgCreateImage(nvg, "image/bat_attack_4f_20260601145643.png", flags)
    imgHit_    = nvgCreateImage(nvg, "image/bat_hit_4f_20260601150607.png", flags)
    print("[BAT] 蝙蝠资源加载完成")
end

--- 获取图片句柄（供序列帧编辑器使用）
function BatEnemy.GetImages()
    return {
        fly = imgFly_,
        attack = imgAttack_,
        hit = imgHit_,
    }
end

--- 获取图片尺寸
function BatEnemy.GetImageSize()
    if imgFly_ and imgFly_ > 0 and nvg then
        local w, h = nvgImageSize(nvg, imgFly_)
        return w, h
    end
    return 0, 0
end

-- ============================================================================
-- 生成蝙蝠
-- ============================================================================
function BatEnemy.Spawn(x, y)
    local b = {
        x = x,
        y = y,
        hp = BatEnemy.CONFIG.maxHP,
        maxHP = BatEnemy.CONFIG.maxHP,
        alive = true,
        facingRight = false,
        -- 动画
        anim = BatEnemy.ANIM_FLY,
        animFrame = 0,
        animTimer = 0.0,
        -- AI
        state = "fly",       -- fly/chase/attack/hit/death
        stateTimer = 0.0,
        attackCooldown = 1.0,
        hitStunTimer = 0.0,
        deathTimer = 0.0,
        -- 飞行参数
        flyPhase = math.random() * math.pi * 2,  -- 随机初始相位
        baseY = y,           -- 基准飞行高度
        -- 巡逻目标
        patrolTargetX = x + (math.random() > 0.5 and 3 or -3),
        patrolTimer = 0.0,
        -- 攻击判定
        attackHitFrame = false,
        -- 冰冻状态
        freezeTimer = 0.0,
        -- 流血状态
        bleedTimer = 0.0,
        bleedDPS = 0,
        bleedAccum = 0.0,
        -- 血条闪烁
        displayHP = BatEnemy.CONFIG.maxHP,  -- 显示用HP（延迟下降）
        hpFlashTimer = 0.0,                -- 闪烁计时器
    }
    table.insert(bats_, b)
    return b
end

-- ============================================================================
-- 获取蝙蝠列表
-- ============================================================================
function BatEnemy.GetAll()
    return bats_
end

-- ============================================================================
-- 清空所有蝙蝠
-- ============================================================================
function BatEnemy.Clear()
    bats_ = {}
end

-- ============================================================================
-- 更新所有蝙蝠
-- ============================================================================
function BatEnemy.Update(dt, playerX, playerY, camX, camY, screenW, screenH, pixelsPerUnit)
    for i = #bats_, 1, -1 do
        local b = bats_[i]
        if not b.alive then
            b.deathTimer = b.deathTimer + dt
            if b.deathTimer > 0.8 then
                table.remove(bats_, i)
            else
                BatEnemy._UpdateAnim(b, dt)
            end
        else
            -- 更新血条闪烁计时
            if b.hpFlashTimer > 0 then
                b.hpFlashTimer = b.hpFlashTimer - dt
                if b.hpFlashTimer <= 0 then
                    b.hpFlashTimer = 0
                    b.displayHP = b.hp
                end
            end
            BatEnemy._UpdateAI(b, dt, playerX, playerY, camX, camY, screenW, screenH, pixelsPerUnit)
            BatEnemy._UpdateAnim(b, dt)
        end
    end
end

-- ============================================================================
-- AI 状态机
-- ============================================================================
function BatEnemy._UpdateAI(b, dt, playerX, playerY, camX, camY, screenW, screenH, pixelsPerUnit)
    -- 流血DOT
    if b.bleedTimer > 0 then
        b.bleedTimer = b.bleedTimer - dt
        b.bleedAccum = b.bleedAccum + dt
        if b.bleedAccum >= 1.0 then
            b.bleedAccum = b.bleedAccum - 1.0
            b.hp = b.hp - b.bleedDPS
            if b.hp <= 0 then
                b.hp = 0
                b.alive = false
                b.anim = BatEnemy.ANIM_FLY
                b.animFrame = 0
                b.deathTimer = 0
                b.state = "death"
                return
            end
        end
        if b.bleedTimer <= 0 then
            b.bleedTimer = 0
            b.bleedDPS = 0
        end
    end

    -- 冰冻状态
    if b.freezeTimer > 0 then
        b.freezeTimer = b.freezeTimer - dt
        if b.freezeTimer <= 0 then b.freezeTimer = 0 end
        return
    end

    -- 冷却递减
    if b.attackCooldown > 0 then b.attackCooldown = b.attackCooldown - dt end

    -- 受击硬直
    if b.hitStunTimer > 0 then
        b.hitStunTimer = b.hitStunTimer - dt
        return
    end

    -- 飞行浮动（始终更新）
    b.flyPhase = b.flyPhase + dt * BatEnemy.CONFIG.flyFrequency
    local floatOffset = math.sin(b.flyPhase) * BatEnemy.CONFIG.flyAmplitude

    -- 屏幕范围限制（世界坐标）
    local halfW = (screenW / pixelsPerUnit) / 2
    local halfH = (screenH / pixelsPerUnit) / 2
    local minX = camX - halfW + 1
    local maxX = camX + halfW - 1
    local minY = camY - halfH + 1
    local maxY = camY + halfH - 1

    local dx = playerX - b.x
    local dy = playerY - b.y
    local dist = math.sqrt(dx * dx + dy * dy)
    b.facingRight = dx > 0

    -- 状态机
    if b.state == "attack" then
        b.stateTimer = b.stateTimer + dt
        if b.stateTimer >= 0.6 then
            b.state = "fly"
            b.stateTimer = 0
            b.attackHitFrame = false
            b.anim = BatEnemy.ANIM_FLY
            b.animFrame = 0
            b.animTimer = 0
        end
    elseif b.state == "hit" then
        b.stateTimer = b.stateTimer + dt
        if b.stateTimer >= 0.3 then
            b.state = "fly"
            b.stateTimer = 0
            b.anim = BatEnemy.ANIM_FLY
            b.animFrame = 0
            b.animTimer = 0
        end
    else
        -- 飞行/追击逻辑
        if dist <= BatEnemy.CONFIG.attackRange and b.attackCooldown <= 0 then
            -- 攻击
            b.state = "attack"
            b.stateTimer = 0
            b.attackCooldown = BatEnemy.CONFIG.attackCooldown
            b.attackHitFrame = false
            b.anim = BatEnemy.ANIM_ATTACK
            b.animFrame = 0
            b.animTimer = 0
        elseif dist <= BatEnemy.CONFIG.detectRange then
            -- 追击玩家
            b.state = "chase"
            local dirX = dx / dist
            local dirY = dy / dist
            b.x = b.x + dirX * BatEnemy.CONFIG.moveSpeed * dt
            b.y = b.y + dirY * BatEnemy.CONFIG.moveSpeed * dt * 0.6 + floatOffset * dt
            b.anim = BatEnemy.ANIM_FLY
        else
            -- 巡逻飞行
            b.state = "fly"
            b.patrolTimer = b.patrolTimer + dt
            if b.patrolTimer > 3.0 then
                b.patrolTimer = 0
                b.patrolTargetX = b.x + (math.random() * 6 - 3)
            end
            local pdx = b.patrolTargetX - b.x
            if math.abs(pdx) > 0.3 then
                local dir = pdx > 0 and 1 or -1
                b.x = b.x + dir * BatEnemy.CONFIG.moveSpeed * 0.5 * dt
                b.facingRight = dir > 0
            end
            b.baseY = b.baseY + floatOffset * dt
            b.y = b.baseY + floatOffset * 0.5
            b.anim = BatEnemy.ANIM_FLY
        end

        -- 限制在屏幕范围内
        b.x = math.max(minX, math.min(maxX, b.x))
        b.y = math.max(minY, math.min(maxY, b.y))
    end
end

-- ============================================================================
-- 动画帧更新
-- ============================================================================
function BatEnemy._UpdateAnim(b, dt)
    b.animTimer = b.animTimer + dt
    local fps = BAT_ANIM_FPS
    if b.anim == BatEnemy.ANIM_ATTACK then
        fps = 8
    elseif b.anim == BatEnemy.ANIM_HIT then
        fps = 10
    end

    local interval = 1.0 / fps
    if b.animTimer >= interval then
        b.animTimer = b.animTimer - interval
        b.animFrame = b.animFrame + 1

        if b.anim == BatEnemy.ANIM_ATTACK then
            if b.animFrame >= 4 then b.animFrame = 3 end  -- 停最后帧
        elseif b.anim == BatEnemy.ANIM_HIT then
            if b.animFrame >= 4 then b.animFrame = 3 end  -- 停最后帧
        else
            b.animFrame = b.animFrame % 4  -- 循环
        end
    end
end

-- ============================================================================
-- 蝙蝠受伤
-- ============================================================================
function BatEnemy.TakeDamage(b, damage)
    if not b.alive then return end
    -- 记录扣血前的显示HP用于闪烁
    if b.hpFlashTimer <= 0 then
        b.displayHP = b.hp
    end
    b.hpFlashTimer = 0.6  -- 闪烁持续0.6秒
    b.hp = b.hp - damage
    if b.hp <= 0 then
        b.hp = 0
        b.alive = false
        b.anim = BatEnemy.ANIM_FLY
        b.animFrame = 0
        b.deathTimer = 0
        b.state = "death"
    else
        b.state = "hit"
        b.stateTimer = 0
        b.hitStunTimer = 0.3
        b.anim = BatEnemy.ANIM_HIT
        b.animFrame = 0
        b.animTimer = 0
    end
end

-- ============================================================================
-- 检测蝙蝠攻击是否命中玩家
-- ============================================================================
function BatEnemy.CheckAttackHits(playerX, playerY)
    local totalDmg = 0
    for _, b in ipairs(bats_) do
        if b.alive and b.state == "attack" and not b.attackHitFrame then
            if b.animFrame >= 2 then
                local dx = playerX - b.x
                local dy = playerY - b.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist <= BatEnemy.CONFIG.attackRange then
                    totalDmg = totalDmg + BatEnemy.CONFIG.damage
                    b.attackHitFrame = true
                end
            end
        end
    end
    return totalDmg
end

-- ============================================================================
-- 冰冻蝙蝠
-- ============================================================================
function BatEnemy.ApplyFreeze(b, duration)
    if not b.alive then return end
    b.freezeTimer = duration
    if b.state == "attack" or b.state == "chase" then
        b.state = "fly"
        b.stateTimer = 0
        b.anim = BatEnemy.ANIM_FLY
        b.animFrame = 0
        b.animTimer = 0
    end
end

-- ============================================================================
-- 施加流血
-- ============================================================================
function BatEnemy.ApplyBleed(b, duration, dps)
    if not b.alive then return end
    b.bleedTimer = duration
    b.bleedDPS = dps
    b.bleedAccum = 0.0
end

-- ============================================================================
-- 检测投射物命中蝙蝠
-- ============================================================================
function BatEnemy.CheckProjectileHits(projectiles, damage)
    for pi = #projectiles, 1, -1 do
        local p = projectiles[pi]
        for _, b in ipairs(bats_) do
            if b.alive then
                local dx = p.x - b.x
                local dy = p.y - b.y
                if math.abs(dx) < 1.0 and math.abs(dy) < 1.0 then
                    BatEnemy.TakeDamage(b, damage)
                    table.remove(projectiles, pi)
                    break
                end
            end
        end
    end
end

-- ============================================================================
-- 检测冰晶群命中蝙蝠
-- ============================================================================
function BatEnemy.CheckCrystalHits(crystalGroups, damage, freezeDuration)
    for _, group in ipairs(crystalGroups) do
        if group.spawnTime <= 0.3 and not group.batHitApplied then
            local minX, maxX = math.huge, -math.huge
            for _, c in ipairs(group.crystals) do
                if c.x < minX then minX = c.x end
                if c.x > maxX then maxX = c.x end
            end
            minX = minX - 0.5
            maxX = maxX + 0.5
            local groundY = group.groundY

            for _, b in ipairs(bats_) do
                if b.alive then
                    if b.x >= minX and b.x <= maxX and math.abs(b.y - groundY) < 3.0 then
                        BatEnemy.TakeDamage(b, damage)
                        if b.alive and freezeDuration > 0 then
                            BatEnemy.ApplyFreeze(b, freezeDuration)
                        end
                    end
                end
            end
            group.batHitApplied = true
        end
    end
end

-- ============================================================================
-- 渲染所有蝙蝠
-- ============================================================================
function BatEnemy.Draw(width, height, camX, camY, SCREEN_W, SCREEN_H, PIXELS_PER_UNIT)
    if nvg == nil then return end
    local sx = width / SCREEN_W
    local sy = height / SCREEN_H

    for _, b in ipairs(bats_) do
        local screenX = width / 2 + (b.x - camX) * PIXELS_PER_UNIT * sx
        local screenY = height / 2 - (b.y - camY) * PIXELS_PER_UNIT * sy

        -- 选择图片
        local img = imgFly_
        if b.anim == BatEnemy.ANIM_ATTACK then
            img = imgAttack_
        elseif b.anim == BatEnemy.ANIM_HIT then
            img = imgHit_
        end

        -- 死亡时渐隐
        local alpha = 1.0
        if not b.alive then
            alpha = math.max(0, 1.0 - b.deathTimer / 0.8)
        end

        -- 绘制精灵
        if img and img > 0 then
            local drawSize = 0.35 * BatEnemy.CONFIG.scale * PIXELS_PER_UNIT * sx
            BatEnemy._DrawFrame(img, b.animFrame, screenX, screenY, drawSize, not b.facingRight, alpha)
        else
            -- fallback
            nvgBeginPath(nvg)
            nvgCircle(nvg, screenX, screenY, 12 * sx)
            nvgFillColor(nvg, nvgRGBA(80, 40, 80, math.floor(255 * alpha)))
            nvgFill(nvg)
        end

        -- 冰冻视觉效果（身上附着冰晶棱柱，与斯缇昔娅一致）
        if b.alive and b.freezeTimer > 0 then
            local freezeAlpha = math.min(b.freezeTimer / 0.5, 1.0)
            local drawSize = 0.35 * BatEnemy.CONFIG.scale * PIXELS_PER_UNIT * sx
            local baseY = screenY - drawSize * 0.2

            local crystals = {
                { ox = -drawSize * 0.2, oy = -drawSize * 0.1, w = 6, h = 20, angle = -0.2 },
                { ox = drawSize * 0.15, oy = -drawSize * 0.2, w = 7, h = 22, angle = 0.15 },
                { ox = -drawSize * 0.05, oy = drawSize * 0.05, w = 6, h = 16, angle = 0.3 },
                { ox = drawSize * 0.25, oy = 0, w = 5, h = 14, angle = -0.25 },
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

        -- 血条在 DrawHealthBars 中统一绘制（最上层）
    end
end

-- ============================================================================
-- 绘制蝙蝠序列帧（12帧单行）
-- ============================================================================
function BatEnemy._DrawFrame(img, frame, cx, cy, size, flipH, alpha)
    local cols = BAT_SPRITE_COLS
    local rows = BAT_SPRITE_ROWS
    local col = frame % cols
    local row = 0

    local actualW, actualH = nvgImageSize(nvg, img)
    local frameW = actualW / cols
    local frameH = actualH / rows

    local maxDim = math.max(frameW, frameH)
    local drawW = size * (frameW / maxDim)
    local drawH = size * (frameH / maxDim)
    local drawX = cx - drawW / 2
    local drawY = cy - drawH / 2  -- 蝙蝠中心对齐

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
    local patternY = drawY - row * frameH * (patternH / actualH)

    local paint = nvgImagePattern(nvg, patternX, patternY, patternW, patternH, 0, img, 1.0)
    nvgBeginPath(nvg)
    nvgRect(nvg, drawX, drawY, drawW, drawH)
    nvgFillPaint(nvg, paint)
    nvgFill(nvg)

    nvgRestore(nvg)
end

-- ============================================================================
-- 渲染所有蝙蝠血条（独立调用，确保在最上层）
-- ============================================================================
function BatEnemy.DrawHealthBars(width, height, camX, camY, SCREEN_W, SCREEN_H, PIXELS_PER_UNIT)
    if nvg == nil then return end
    local sx = width / SCREEN_W
    local sy = height / SCREEN_H

    for _, b in ipairs(bats_) do
        if b.alive then
            local screenX = width / 2 + (b.x - camX) * PIXELS_PER_UNIT * sx
            local screenY = height / 2 - (b.y - camY) * PIXELS_PER_UNIT * sy

            local barW = 35 * sx
            local barH = 4 * sy
            local drawSize = 0.35 * BatEnemy.CONFIG.scale * PIXELS_PER_UNIT * sx
            local barX = screenX - barW / 2
            local barY = screenY - drawSize * 0.6

            -- 背景
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, barX, barY, barW, barH, 2)
            nvgFillColor(nvg, nvgRGBA(30, 30, 30, 200))
            nvgFill(nvg)

            -- 闪烁部分（扣血延迟显示）
            if b.hpFlashTimer > 0 and b.displayHP > b.hp then
                local displayRatio = b.displayHP / b.maxHP
                local flashAlpha = math.floor(180 + 75 * math.sin(b.hpFlashTimer * 18))
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, barX, barY, barW * displayRatio, barH, 2)
                nvgFillColor(nvg, nvgRGBA(255, 255, 255, flashAlpha))
                nvgFill(nvg)
            end

            -- 当前血量（红色）
            local hpRatio = b.hp / b.maxHP
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
            nvgText(nvg, screenX, barY - 1 * sy, "蝙蝠")
        end
    end
end

return BatEnemy
