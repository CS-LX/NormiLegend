-- ============================================================================
-- Level.lua - 场景与关卡管理
-- 职责: 场景创建、物理世界、平台布局、区域加载、精灵纹理加载、玩家实体创建
-- ============================================================================

local C = require("GameConfig")
local S = require("GameState")
local LevelConfig = require("LevelConfig")
local Enemy = require("Enemy")
local BatEnemy = require("BatEnemy")
local CastleEnemies = require("CastleEnemies")
local WorldMap = require("WorldMap")

local M = {}

-- ============================================================================
-- 精灵纹理加载
-- ============================================================================

--- 加载所有角色序列帧、头像、技能图标、背景等 NanoVG 纹理
function M.LoadSpriteSheets()
    local vg = S.nvg
    local flags = NVG_IMAGE_NEAREST or 32

    -- 角色1 动画序列帧（12帧，3行4列）
    S.imgIdle = nvgCreateImage(vg, "image/idle_12f_v2_20260530134219.png", flags)
    S.imgRun = nvgCreateImage(vg, "image/run_12f_v2_20260530134223.png", flags)
    S.imgJump = nvgCreateImage(vg, "image/jump_12f_v3_20260530140014.png", flags)
    S.imgAttack = nvgCreateImage(vg, "image/attack_12f_v2_20260530134230.png", flags)
    S.imgBlock = nvgCreateImage(vg, "image/block_12f_v2_20260530143345.png", flags)
    S.imgCharge = nvgCreateImage(vg, "image/ice_charge_side_12f_20260530180952.png", flags)
    S.imgHeal = nvgCreateImage(vg, "image/edited_heal_skill_12f_transparent_20260531002130.png", flags)
    S.imgCrouch = nvgCreateImage(vg, "image/char1_crouch_12f_20260601.png", flags)
    S.imgCrouchWalk = nvgCreateImage(vg, "image/crouch_walk_12f_20260531011542.png", flags)
    S.imgHit = nvgCreateImage(vg, "image/hit_12f_20260531035941.png", flags)

    -- 角色2（黑红角娘）序列帧
    S.img2Idle = nvgCreateImage(vg, "image/char2_idle_front_12f_20260531082747.png", flags)
    S.img2Run = nvgCreateImage(vg, "image/char2_run_12f_v2_20260531081912.png", flags)
    S.img2Jump = nvgCreateImage(vg, "image/char2_jump_12f_v2_20260531081921.png", flags)
    S.img2Attack = nvgCreateImage(vg, "image/char2_attack_12f_v2_20260531081918.png", flags)
    S.img2Crouch = nvgCreateImage(vg, "image/char2_crouch_12f_v2_20260531082008.png", flags)
    S.img2CrouchWalk = nvgCreateImage(vg, "image/char2_crouchwalk_12f_v2_20260531082007.png", flags)
    S.img2Heal = nvgCreateImage(vg, "image/char2_heal_12f_v2_20260531082018.png", flags)
    S.img2Hit = nvgCreateImage(vg, "image/char2_hit_12f_v2_20260531082050.png", flags)
    S.img2Burst = nvgCreateImage(vg, "image/char2_qburst_12f_v2_20260531082012.png", flags)
    S.img2Block = nvgCreateImage(vg, "image/char2_block_12f_20260531085931.png", flags)

    -- 角色3（蓝白角色）序列帧
    S.img3Idle = nvgCreateImage(vg, "image/char3_idle_12f.png", flags)
    S.img3Run = nvgCreateImage(vg, "image/char3_run_12f.png", flags)
    S.img3Jump = nvgCreateImage(vg, "image/char3_jump_12f.png", flags)
    -- 角色3其他动画预留（暂用idle替代）
    S.img3Attack = S.img3Idle
    S.img3Block = S.img3Idle
    S.img3Charge = S.img3Idle
    S.img3Heal = S.img3Idle
    S.img3Crouch = S.img3Idle
    S.img3CrouchWalk = S.img3Idle
    S.img3Hit = S.img3Idle

    -- 角色头像
    S.imgAvatar1 = nvgCreateImage(vg, "image/avatar_char1_20260602072030.png", 0)
    S.imgAvatar2 = nvgCreateImage(vg, "image/avatar_char2_20260602072055.png", 0)

    -- 技能图标
    S.iconChar1Q = nvgCreateImage(vg, "image/icon_char1_q_20260601092553.png", 0)
    S.iconChar1E = nvgCreateImage(vg, "image/icon_char1_e_20260601092600.png", 0)
    S.iconChar2Q = nvgCreateImage(vg, "image/icon_char2_q_20260601092556.png", 0)
    S.iconChar2E = nvgCreateImage(vg, "image/icon_char2_e_20260601092552.png", 0)

    -- 背景图片
    S.imgBackground = nvgCreateImage(vg, "image/华丽古堡背景无平台_20260531064643.png", 0)

    print("[LOAD] Image handles: idle=" .. tostring(S.imgIdle) .. " run=" .. tostring(S.imgRun) ..
          " jump=" .. tostring(S.imgJump) .. " attack=" .. tostring(S.imgAttack) ..
          " block=" .. tostring(S.imgBlock) .. " charge=" .. tostring(S.imgCharge) ..
          " heal=" .. tostring(S.imgHeal) .. " crouch=" .. tostring(S.imgCrouch) ..
          " hit=" .. tostring(S.imgHit))

    -- 获取实际图片尺寸
    local testImg = S.imgIdle
    if testImg == nil or testImg <= 0 then testImg = S.imgRun end
    if testImg ~= nil and testImg > 0 then
        local w, h = nvgImageSize(vg, testImg)
        S.imgWidth = w
        S.imgHeight = h
        print("[LOAD] 序列帧加载成功, 实际尺寸: " .. w .. "x" .. h)
    else
        print("[LOAD] 序列帧加载失败! 将使用占位符圆形渲染角色")
        S.imgWidth = 0
        S.imgHeight = 0
    end
end

-- ============================================================================
-- 场景创建
-- ============================================================================

--- 创建 Box2D 物理场景 + 正交相机
function M.CreateScene()
    S.scene = Scene()
    S.scene:CreateComponent("Octree")
    S.scene:CreateComponent("DebugRenderer")

    S.physicsWorld = S.scene:CreateComponent("PhysicsWorld2D")
    S.physicsWorld.gravity = Vector2(0, -C.GRAVITY)
    S.physicsWorld.autoClearForces = true

    -- 正交相机
    S.cameraNode = S.scene:CreateChild("Camera")
    local camera = S.cameraNode:CreateComponent("Camera")
    camera.orthographic = true
    camera.orthoSize = C.SCREEN_HEIGHT / 2
    S.cameraNode.position = Vector3(0, 0, -10)

    renderer:SetViewport(0, Viewport:new(S.scene, camera))
end

-- ============================================================================
-- 创建默认世界（白盒占位平台）
-- ============================================================================

--- 创建默认关卡的地面和浮空平台
function M.CreateWorld()
    -- 地面
    local groundNode = S.scene:CreateChild("Ground")
    groundNode:SetPosition2D(0, -4.0)
    local groundBody = groundNode:CreateComponent("RigidBody2D")
    groundBody.bodyType = BT_STATIC
    local groundShape = groundNode:CreateComponent("CollisionBox2D")
    groundShape:SetSize(C.MAP_HALF_WIDTH * 2, 1)
    groundShape.friction = 0.3
    groundShape.restitution = 0.0
    groundShape.categoryBits = 1

    table.insert(S.platforms, { x = 0, y = -4.0, width = C.MAP_HALF_WIDTH * 2, height = 1 })

    -- 浮空平台数据
    local platformData = {
        { x = -6, y = -1.5, width = 3, height = 0.5 },
        { x = -2, y = 0.5, width = 2.5, height = 0.5 },
        { x = 2, y = 2.0, width = 3, height = 0.5 },
        { x = 6, y = 0.5, width = 2.5, height = 0.5 },
        { x = 10, y = 2.5, width = 3, height = 0.5 },
        { x = -4, y = 3.0, width = 2, height = 0.5 },
        { x = 14, y = 1.0, width = 2.5, height = 0.5 },
        { x = 18, y = 3.0, width = 3, height = 0.5 },
    }

    for _, data in ipairs(platformData) do
        local platformNode = S.scene:CreateChild("Platform")
        platformNode:SetPosition2D(data.x, data.y)
        local platformBody = platformNode:CreateComponent("RigidBody2D")
        platformBody.bodyType = BT_STATIC
        local platformShape = platformNode:CreateComponent("CollisionBox2D")
        platformShape:SetSize(data.width, data.height)
        platformShape.friction = 0.3
        platformShape.restitution = 0.0
        platformShape.categoryBits = 1

        table.insert(S.platforms, data)
    end
end

-- ============================================================================
-- 加载区域关卡
-- ============================================================================

--- 切换到指定区域关卡
---@param areaId string 区域ID
function M.LoadArea(areaId)
    local config = LevelConfig.GetArea(areaId)
    if not config then return end

    -- 清除现有敌人
    Enemy.Clear()
    BatEnemy.Clear()
    CastleEnemies.Clear()

    -- 清除现有物理平台节点（除了玩家）
    local toRemove = {}
    for _, child in ipairs(S.scene:GetChildren()) do
        if child.name == "Ground" or child.name:find("Platform", 1, true) then
            table.insert(toRemove, child)
        end
    end
    for _, node in ipairs(toRemove) do
        node:Remove()
    end
    S.platforms = {}

    local vg = S.nvg

    -- 加载背景图片
    if config.background then
        S.imgBackground = nvgCreateImage(vg, config.background, 0)
    end

    -- 加载多层视差背景（冰原）
    S.parallaxLayers = {}
    if config.parallaxLayers then
        for _, layer in ipairs(config.parallaxLayers) do
            local img = nvgCreateImage(vg, layer.image, 0)
            if img and img > 0 then
                table.insert(S.parallaxLayers, { img = img, factor = layer.factor })
            end
        end
    end

    -- 加载平台图片（如果有）
    if config.platformImage then
        S.imgPlatformArea = nvgCreateImage(vg, config.platformImage, NVG_IMAGE_NEAREST or 32)
    else
        S.imgPlatformArea = -1
    end

    -- 加载地面图片（如果有）
    if config.groundImage then
        S.imgGroundArea = nvgCreateImage(vg, config.groundImage, 0)
    else
        S.imgGroundArea = -1
    end

    -- 创建地面
    local groundNode = S.scene:CreateChild("Ground")
    groundNode:SetPosition2D(0, config.groundY)
    local groundBody = groundNode:CreateComponent("RigidBody2D")
    groundBody.bodyType = BT_STATIC
    local groundShape = groundNode:CreateComponent("CollisionBox2D")
    groundShape:SetSize(config.groundWidth, 1)
    groundShape.friction = 0.3
    groundShape.restitution = 0.0
    groundShape.categoryBits = 1
    table.insert(S.platforms, { x = 0, y = config.groundY, width = config.groundWidth, height = 1 })

    -- 创建浮空平台
    for _, data in ipairs(config.platforms) do
        local platformNode = S.scene:CreateChild("Platform")
        platformNode:SetPosition2D(data.x, data.y)
        local platformBody = platformNode:CreateComponent("RigidBody2D")
        platformBody.bodyType = BT_STATIC
        local platformShape = platformNode:CreateComponent("CollisionBox2D")
        platformShape:SetSize(data.width, data.height)
        platformShape.friction = 0.3
        platformShape.restitution = 0.0
        platformShape.categoryBits = 1
        table.insert(S.platforms, data)
    end

    -- 重置玩家位置与物理状态
    if S.playerNode and S.playerBody then
        S.playerNode:SetPosition2D(0, 0)
        S.playerBody.linearVelocity = Vector2(0, 0)
        S.playerBody.awake = true  -- 强制唤醒刚体，防止睡眠状态导致重力不生效
        S.playerBody.gravityScale = 1.0  -- 确保重力正常
    end
    -- 重置地面检测与滞空状态（旧碰撞体已删除，接触数据失效）
    S.groundContactCount = 0
    S.onGround = false
    S.isHanging = false
    S.hangCooldown = 0

    -- 进入关卡状态
    WorldMap.EnterArea(areaId)
    print("[WORLD] 进入区域: " .. (config.name or areaId))
end

-- ============================================================================
-- 创建玩家实体
-- ============================================================================

--- 创建玩家物理实体（圆形碰撞体 + 脚底传感器）
function M.CreatePlayer()
    S.playerNode = S.scene:CreateChild("Player")
    S.playerNode:SetPosition2D(0, 0)

    S.playerBody = S.playerNode:CreateComponent("RigidBody2D")
    S.playerBody.bodyType = BT_DYNAMIC
    S.playerBody.fixedRotation = true
    S.playerBody.linearDamping = 0.0
    S.playerBody.gravityScale = 1.0

    -- 身体碰撞体（圆形，不卡墙）
    local bodyShape = S.playerNode:CreateComponent("CollisionCircle2D")
    bodyShape.radius = C.PLAYER_RADIUS
    bodyShape.density = 1.0
    bodyShape.friction = 0.0
    bodyShape.restitution = 0.0
    bodyShape.categoryBits = 2
    bodyShape.maskBits = 0xFFFF

    -- 脚底传感器（用于地面检测）
    S.footSensor = S.playerNode:CreateComponent("CollisionCircle2D")
    S.footSensor.radius = C.PLAYER_RADIUS * 0.7
    S.footSensor.center = Vector2(0, -C.PLAYER_RADIUS * 0.9)
    S.footSensor.trigger = true
    S.footSensor.categoryBits = 4
    S.footSensor.maskBits = 1
end

return M
