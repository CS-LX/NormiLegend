-- ============================================================================
-- Enemy.lua - 敌人系统模块（斯缇昔娅）
-- 包含：敌人数据、AI行为、动画状态机、渲染
-- ============================================================================
local Enemy = {}

-- 敌人动画状态
Enemy.ANIM_MOVE = "move"
Enemy.ANIM_ATTACK = "attack"
Enemy.ANIM_SKILL = "skill"
Enemy.ANIM_HIT = "hit"
Enemy.ANIM_DEATH = "death"
Enemy.ANIM_IDLE = "idle"

-- 默认参数（可通过GM控制台修改）
Enemy.CONFIG = {
    maxHP = 80,
    damage = 3,            -- 普通攻击伤害
    skillDamage = 9,       -- 技能伤害
    attackRange = 2.8,     -- 攻击距离（米）
    skillRange = 3.5,      -- 技能距离（米）
    detectRange = 8.0,     -- 检测距离（米）
    moveSpeed = 2.5,       -- 移动速度
    attackCooldown = 2.0,  -- 攻击冷却
    skillCooldown = 10.0,  -- 技能冷却
    scale = 6.0,           -- 渲染缩放
}

-- 序列帧配置（默认2列2行，受击为4列1行）
local ENEMY_SPRITE_COLS = 2
local ENEMY_SPRITE_ROWS = 2
local ENEMY_ANIM_FPS = 6

-- 每动画独立grid配置（nil则使用默认）
local ENEMY_ANIM_GRID = {
    [Enemy.ANIM_HIT] = { cols = 4, rows = 1, scale = 2.0 },
}

-- 图片句柄
local imgMove_ = -1
local imgAttack_ = -1
local imgSkill_ = -1
local imgHit_ = -1
local imgDeath_ = -1

-- 活跃的敌人列表
local enemies_ = {}

-- NanoVG 上下文引用
local nvg = nil

-- ============================================================================
-- 初始化（加载资源）
-- ============================================================================
function Enemy.Init(nvgCtx)
    nvg = nvgCtx
    local flags = NVG_IMAGE_NEAREST or 32
    imgMove_   = nvgCreateImage(nvg, "image/enemy_stixia_move_20260531033903.png", flags)
    imgAttack_ = nvgCreateImage(nvg, "image/enemy_stixia_attack_20260531033900.png", flags)
    imgSkill_  = nvgCreateImage(nvg, "image/enemy_stixia_skill_20260531033859.png", flags)
    imgHit_    = nvgCreateImage(nvg, "image/enemy_stixia_hit_20260531033902.png", flags)
    imgDeath_  = nvgCreateImage(nvg, "image/enemy_stixia_death_20260531033901.png", flags)
    print("[ENEMY] 斯缇昔娅资源加载完成")
end

--- 获取图片句柄（供序列帧编辑器使用）
function Enemy.GetImages()
    return {
        move = imgMove_,
        attack = imgAttack_,
        skill = imgSkill_,
        hit = imgHit_,
        death = imgDeath_,
    }
end

--- 获取图片尺寸
function Enemy.GetImageSize()
    if imgMove_ and imgMove_ > 0 and nvg then
        local w, h = nvgImageSize(nvg, imgMove_)
        return w, h
    end
    return 0, 0
end

-- ============================================================================
-- 生成敌人
-- ============================================================================
function Enemy.Spawn(x, y)
    local e = {
        x = x,
        y = y,
        hp = Enemy.CONFIG.maxHP,
        maxHP = Enemy.CONFIG.maxHP,
        alive = true,
        facingRight = false,  -- 默认面向左（面向玩家）
        -- 动画
        anim = Enemy.ANIM_IDLE,
        animFrame = 0,
        animTimer = 0.0,
        -- AI
        state = "idle",       -- idle/chase/attack/skill/hit/death
        stateTimer = 0.0,
        attackCooldown = 0.0,
        skillCooldown = 3.0,  -- 开局稍延后释放技能
        hitStunTimer = 0.0,
        deathTimer = 0.0,
        -- 冰冻状态
        freezeTimer = 0.0,
        -- 流血状态（DOT）
        bleedTimer = 0.0,
        bleedDPS = 0,
        bleedAccum = 0.0,  -- 累积伤害计时
        -- 攻击判定
        attackHitFrame = false,  -- 本次攻击是否已造成伤害
        -- 血条闪烁
        displayHP = Enemy.CONFIG.maxHP,  -- 显示用HP（延迟下降）
        hpFlashTimer = 0.0,              -- 闪烁计时器
    }
    table.insert(enemies_, e)
    return e
end

-- ============================================================================
-- 获取敌人列表
-- ============================================================================
function Enemy.GetAll()
    return enemies_
end

-- ============================================================================
-- 清空所有敌人
-- ============================================================================
function Enemy.Clear()
    enemies_ = {}
end

-- ============================================================================
-- 更新所有敌人
-- ============================================================================
function Enemy.Update(dt, playerX, playerY, playerHP)
    for i = #enemies_, 1, -1 do
        local e = enemies_[i]
        if not e.alive then
            e.deathTimer = e.deathTimer + dt
            -- 死亡动画播完后移除
            if e.deathTimer > 1.0 then
                table.remove(enemies_, i)
            else
                -- 更新死亡动画帧
                Enemy._UpdateAnim(e, dt)
            end
        else
            -- 更新血条闪烁计时
            if e.hpFlashTimer > 0 then
                e.hpFlashTimer = e.hpFlashTimer - dt
                if e.hpFlashTimer <= 0 then
                    e.hpFlashTimer = 0
                    e.displayHP = e.hp
                end
            end
            Enemy._UpdateAI(e, dt, playerX, playerY)
            Enemy._UpdateAnim(e, dt)
        end
    end
end

-- ============================================================================
-- AI 状态机
-- ============================================================================
function Enemy._UpdateAI(e, dt, playerX, playerY)
    -- 流血DOT：每秒造成伤害（独立于冰冻/其他状态）
    if e.bleedTimer > 0 then
        e.bleedTimer = e.bleedTimer - dt
        e.bleedAccum = e.bleedAccum + dt
        if e.bleedAccum >= 1.0 then
            e.bleedAccum = e.bleedAccum - 1.0
            e.hp = e.hp - e.bleedDPS
            if e.hp <= 0 then
                e.hp = 0
                e.alive = false
                e.anim = Enemy.ANIM_DEATH
                e.animFrame = 0
                e.animTimer = 0
                e.deathTimer = 0
                e.state = "death"
                return
            end
        end
        if e.bleedTimer <= 0 then
            e.bleedTimer = 0
            e.bleedDPS = 0
        end
    end

    -- 冰冻状态：无法移动和攻击
    if e.freezeTimer > 0 then
        e.freezeTimer = e.freezeTimer - dt
        if e.freezeTimer <= 0 then
            e.freezeTimer = 0
        end
        return  -- 冰冻期间跳过所有AI逻辑
    end

    -- 冷却递减
    if e.attackCooldown > 0 then e.attackCooldown = e.attackCooldown - dt end
    if e.skillCooldown > 0 then e.skillCooldown = e.skillCooldown - dt end

    -- 受击硬直
    if e.hitStunTimer > 0 then
        e.hitStunTimer = e.hitStunTimer - dt
        return
    end

    local dx = playerX - e.x
    local dist = math.abs(dx)
    e.facingRight = dx > 0

    -- 状态机
    if e.state == "attack" or e.state == "skill" then
        -- 等攻击/技能动画播放完毕
        e.stateTimer = e.stateTimer + dt
        local duration = (e.state == "skill") and 0.7 or 0.5
        if e.stateTimer >= duration then
            e.state = "idle"
            e.stateTimer = 0
            e.attackHitFrame = false
        end
    elseif e.state == "hit" then
        e.stateTimer = e.stateTimer + dt
        if e.stateTimer >= 0.25 then
            e.state = "idle"
            e.stateTimer = 0
        end
    else
        -- 正常AI逻辑
        if dist <= Enemy.CONFIG.attackRange and e.attackCooldown <= 0 then
            -- 进入攻击
            e.state = "attack"
            e.stateTimer = 0
            e.attackCooldown = Enemy.CONFIG.attackCooldown
            e.attackHitFrame = false
            e.anim = Enemy.ANIM_ATTACK
            e.animFrame = 0
            e.animTimer = 0
        elseif dist <= Enemy.CONFIG.skillRange and e.skillCooldown <= 0 then
            -- 释放技能
            e.state = "skill"
            e.stateTimer = 0
            e.skillCooldown = Enemy.CONFIG.skillCooldown
            e.attackHitFrame = false
            e.anim = Enemy.ANIM_SKILL
            e.animFrame = 0
            e.animTimer = 0
        elseif dist <= Enemy.CONFIG.detectRange and dist > Enemy.CONFIG.attackRange then
            -- 追击
            e.state = "chase"
            local dir = dx > 0 and 1 or -1
            e.x = e.x + dir * Enemy.CONFIG.moveSpeed * dt
            e.anim = Enemy.ANIM_MOVE
        else
            -- 待机
            e.state = "idle"
            e.anim = Enemy.ANIM_MOVE  -- idle用移动帧第0帧
        end
    end
end

-- ============================================================================
-- 动画帧更新
-- ============================================================================
function Enemy._UpdateAnim(e, dt)
    e.animTimer = e.animTimer + dt
    local fps = ENEMY_ANIM_FPS
    if e.anim == Enemy.ANIM_ATTACK or e.anim == Enemy.ANIM_SKILL then
        fps = 8
    elseif e.anim == Enemy.ANIM_HIT then
        fps = 6
    elseif e.anim == Enemy.ANIM_DEATH then
        fps = 4
    end

    local interval = 1.0 / fps
    if e.animTimer >= interval then
        e.animTimer = e.animTimer - interval
        e.animFrame = e.animFrame + 1

        if e.anim == Enemy.ANIM_DEATH then
            if e.animFrame >= 4 then e.animFrame = 3 end  -- 停在最后一帧
        elseif e.anim == Enemy.ANIM_HIT then
            if e.animFrame >= 4 then e.animFrame = 3 end
        elseif e.anim == Enemy.ANIM_ATTACK or e.anim == Enemy.ANIM_SKILL then
            if e.animFrame >= 4 then e.animFrame = 3 end
        else
            e.animFrame = e.animFrame % 4  -- 循环
        end
    end
end

-- ============================================================================
-- 敌人受伤
-- ============================================================================
function Enemy.TakeDamage(e, damage)
    if not e.alive then return end
    -- 记录扣血前的显示HP用于闪烁
    if e.hpFlashTimer <= 0 then
        e.displayHP = e.hp
    end
    e.hpFlashTimer = 0.6  -- 闪烁持续0.6秒
    e.hp = e.hp - damage
    if e.hp <= 0 then
        e.hp = 0
        e.alive = false
        e.anim = Enemy.ANIM_DEATH
        e.animFrame = 0
        e.animTimer = 0
        e.deathTimer = 0
        e.state = "death"
    else
        -- 受击硬直
        e.state = "hit"
        e.stateTimer = 0
        e.hitStunTimer = 0.15
        e.anim = Enemy.ANIM_HIT
        e.animFrame = 0
        e.animTimer = 0
    end
end

-- ============================================================================
-- 检测敌人攻击是否命中玩家（返回伤害值，0表示未命中）
-- ============================================================================
function Enemy.CheckAttackHits(playerX, playerY)
    local normalDmg = 0
    local skillDmg = 0
    local attackHeightRange = 2.0  -- 攻击高度限制（上下各2米内才能命中）
    for _, e in ipairs(enemies_) do
        if e.alive and (e.state == "attack" or e.state == "skill") and not e.attackHitFrame then
            -- 在攻击动画的第2帧判定命中
            if e.animFrame >= 2 then
                local dx = playerX - e.x
                local dy = playerY - e.y
                local dist = math.abs(dx)
                local range = (e.state == "skill") and Enemy.CONFIG.skillRange or Enemy.CONFIG.attackRange
                if dist <= range and math.abs(dy) <= attackHeightRange then
                    if e.state == "skill" then
                        skillDmg = skillDmg + Enemy.CONFIG.skillDamage
                    else
                        normalDmg = normalDmg + Enemy.CONFIG.damage
                    end
                    e.attackHitFrame = true
                end
            end
        end
    end
    return normalDmg, skillDmg
end

-- ============================================================================
-- 冰冻敌人（雪崩效果）
-- ============================================================================
function Enemy.ApplyFreeze(e, duration)
    if not e.alive then return end
    e.freezeTimer = duration
    -- 冰冻时中断当前攻击/技能
    if e.state == "attack" or e.state == "skill" or e.state == "chase" then
        e.state = "idle"
        e.stateTimer = 0
        e.anim = Enemy.ANIM_MOVE  -- idle用移动帧第0帧
        e.animFrame = 0
        e.animTimer = 0
    end
end

-- ============================================================================
-- 施加流血效果（DOT）
-- ============================================================================
function Enemy.ApplyBleed(e, duration, dps)
    if not e.alive then return end
    e.bleedTimer = duration
    e.bleedDPS = dps
    e.bleedAccum = 0.0
end

-- ============================================================================
-- 检测冰晶群命中敌人（雪崩AOE）
-- ============================================================================
function Enemy.CheckCrystalHits(crystalGroups, damage, freezeDuration)
    for _, group in ipairs(crystalGroups) do
        -- 只在冰晶刚生成的前0.3秒判定命中（避免重复伤害）
        if group.spawnTime <= 0.3 and not group.hitApplied then
            -- 计算冰晶群的X范围
            local minX, maxX = math.huge, -math.huge
            for _, c in ipairs(group.crystals) do
                if c.x < minX then minX = c.x end
                if c.x > maxX then maxX = c.x end
            end
            -- 稍微扩大判定范围
            minX = minX - 0.5
            maxX = maxX + 0.5
            local groundY = group.groundY

            for _, e in ipairs(enemies_) do
                if e.alive then
                    -- 敌人在冰晶X范围内且Y坐标接近地面
                    if e.x >= minX and e.x <= maxX and math.abs(e.y - groundY) < 2.0 then
                        Enemy.TakeDamage(e, damage)
                        -- 存活则施加冰冻
                        if e.alive and freezeDuration > 0 then
                            Enemy.ApplyFreeze(e, freezeDuration)
                        end
                    end
                end
            end
            group.hitApplied = true  -- 标记已判定，避免重复
        end
    end
end

-- ============================================================================
-- 检测投射物命中敌人
-- ============================================================================
function Enemy.CheckProjectileHits(projectiles, damage)
    for pi = #projectiles, 1, -1 do
        local p = projectiles[pi]
        for _, e in ipairs(enemies_) do
            if e.alive then
                local dx = p.x - e.x
                local dy = p.y - e.y
                if math.abs(dx) < 0.8 and math.abs(dy) < 1.0 then
                    Enemy.TakeDamage(e, damage)
                    table.remove(projectiles, pi)
                    break
                end
            end
        end
    end
end

-- ============================================================================
-- 渲染所有敌人
-- ============================================================================
function Enemy.Draw(width, height, camX, camY, SCREEN_W, SCREEN_H, PIXELS_PER_UNIT)
    if nvg == nil then return end
    local sx = width / SCREEN_W
    local sy = height / SCREEN_H

    for _, e in ipairs(enemies_) do
        local screenX = width / 2 + (e.x - camX) * PIXELS_PER_UNIT * sx
        local screenY = height / 2 - (e.y - camY) * PIXELS_PER_UNIT * sy

        -- 选择图片
        local img = imgMove_
        if e.anim == Enemy.ANIM_ATTACK then
            img = imgAttack_
        elseif e.anim == Enemy.ANIM_SKILL then
            img = imgSkill_
        elseif e.anim == Enemy.ANIM_HIT then
            img = imgHit_
        elseif e.anim == Enemy.ANIM_DEATH then
            img = imgDeath_
        end

        -- 绘制精灵
        if img and img > 0 then
            local drawSize = 0.4 * Enemy.CONFIG.scale * PIXELS_PER_UNIT * sx
            Enemy._DrawFrame(img, e.animFrame, screenX, screenY, drawSize, not e.facingRight, e.anim)
        else
            -- fallback 圆形
            nvgBeginPath(nvg)
            nvgCircle(nvg, screenX, screenY, 20 * sx)
            nvgFillColor(nvg, nvgRGBA(200, 50, 50, 255))
            nvgFill(nvg)
        end

        -- 冰冻视觉效果（身上附着大块冰晶）
        if e.alive and e.freezeTimer > 0 then
            local freezeAlpha = math.min(e.freezeTimer / 0.5, 1.0)  -- 渐隐因子
            local drawSize = 0.4 * Enemy.CONFIG.scale * PIXELS_PER_UNIT * sx
            local baseY = screenY - drawSize * 0.4  -- 身体中心

            -- 绘制多块大冰晶棱柱
            local crystals = {
                { ox = -drawSize * 0.25, oy = -drawSize * 0.1, w = 8, h = 28, angle = -0.2 },
                { ox = drawSize * 0.15,  oy = -drawSize * 0.25, w = 10, h = 32, angle = 0.15 },
                { ox = -drawSize * 0.05, oy = drawSize * 0.05,  w = 9, h = 24, angle = 0.3 },
                { ox = drawSize * 0.3,   oy = drawSize * 0.0,   w = 7, h = 20, angle = -0.25 },
                { ox = -drawSize * 0.35, oy = drawSize * 0.1,   w = 6, h = 18, angle = 0.1 },
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

        -- 流血视觉效果（红色滴血粒子）
        if e.alive and e.bleedTimer > 0 then
            local bleedAlpha = math.min(e.bleedTimer / 1.0, 1.0)
            local drawSize = 0.4 * Enemy.CONFIG.scale * PIXELS_PER_UNIT * sx
            local t = 5.0 - e.bleedTimer  -- 已经流血的时间
            for i = 1, 4 do
                local phase = t * 2.0 + i * 1.5
                local dropX = screenX + math.sin(phase) * drawSize * 0.3
                local dropY = screenY - drawSize * 0.3 + ((phase * 0.5) % 1.0) * drawSize * 0.6
                local dropAlpha = (1.0 - ((phase * 0.5) % 1.0)) * bleedAlpha
                if dropAlpha > 0.05 then
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, dropX, dropY, 2.5 * sx)
                    nvgFillColor(nvg, nvgRGBA(220, 30, 30, math.floor(200 * dropAlpha)))
                    nvgFill(nvg)
                end
            end
        end

        -- 血条在 DrawHealthBars 中统一绘制（最上层）
    end
end

-- ============================================================================
-- 绘制敌人序列帧（支持每动画独立grid）
-- ============================================================================
function Enemy._DrawFrame(img, frame, cx, cy, size, flipH, animName)
    local grid = ENEMY_ANIM_GRID[animName]
    local cols = grid and grid.cols or ENEMY_SPRITE_COLS
    local rows = grid and grid.rows or ENEMY_SPRITE_ROWS
    local col = frame % cols
    local row = math.floor(frame / cols)

    local actualW, actualH = nvgImageSize(nvg, img)
    local frameW = actualW / cols
    local frameH = actualH / rows

    -- 绘制区域（按最大维度归一化，保持不同grid动画视觉大小一致）
    local gridScale = grid and grid.scale or 1.0
    local maxDim = math.max(frameW, frameH)
    local drawW = size * (frameW / maxDim) * gridScale
    local drawH = size * (frameH / maxDim) * gridScale
    local drawX = cx - drawW / 2
    local drawY = cy - drawH * 0.7  -- 脚底偏移

    nvgSave(nvg)

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
-- 渲染所有敌人血条（独立调用，确保在最上层）
-- ============================================================================
function Enemy.DrawHealthBars(width, height, camX, camY, SCREEN_W, SCREEN_H, PIXELS_PER_UNIT)
    if nvg == nil then return end
    local sx = width / SCREEN_W
    local sy = height / SCREEN_H

    for _, e in ipairs(enemies_) do
        if e.alive then
            local screenX = width / 2 + (e.x - camX) * PIXELS_PER_UNIT * sx
            local screenY = height / 2 - (e.y - camY) * PIXELS_PER_UNIT * sy

            local barW = 50 * sx
            local barH = 5 * sy
            local barX = screenX - barW / 2
            local barY = screenY - 0.4 * Enemy.CONFIG.scale * PIXELS_PER_UNIT * sx * 0.7

            -- 背景
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, barX, barY, barW, barH, 2)
            nvgFillColor(nvg, nvgRGBA(30, 30, 30, 200))
            nvgFill(nvg)

            -- 闪烁部分（扣血延迟显示）
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
            nvgFontSize(nvg, 11 * sx)
            nvgFillColor(nvg, nvgRGBA(255, 200, 200, 220))
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            nvgText(nvg, screenX, barY - 2 * sy, "斯缇昔娅")
        end
    end
end

return Enemy
