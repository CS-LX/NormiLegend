-- ============================================================================
-- 冰霜法师 - 平台跳跃游戏
-- 基于 Box2D 物理 + NanoVG 渲染 + 序列帧动画
-- ============================================================================

require "LuaScripts/Utilities/Sample"
require "urhox-libs.UI.GameHUD"
local UI = require("urhox-libs/UI")

-- ============================================================================
-- 游戏常量
-- ============================================================================
local SCREEN_WIDTH = 1280
local SCREEN_HEIGHT = 720

-- 物理常量
local GRAVITY = 25.0
local PLAYER_SPEED = 6.0
local PLAYER_JUMP_SPEED = 13.0
local PLAYER_RADIUS = 0.4

-- 渲染常量
local PIXELS_PER_UNIT = 60

-- 序列帧配置 (4列3行网格, 共12帧)
local SPRITE_COLS = 4
local SPRITE_ROWS = 3
local SPRITE_FRAMES = 12
local ANIM_FPS = 8  -- 默认动画帧率（待机/跳跃）
local ANIM_FPS_RUN = 20  -- 跑步动画帧率（双脚频繁交替）
local ANIM_FPS_ATTACK = 12  -- 攻击动画帧率
local ANIM_FPS_BLOCK = 8  -- 格挡动画帧率
local ANIM_FPS_CHARGE = 6  -- 蓄力动画帧率

-- 蓄力冰晶常量
local CHARGE_MAX_DURATION = 3.0   -- 最长蓄力时间（秒）
local ICE_CRYSTAL_MIN_DIST = 2.0  -- 最短攻击距离（米，蓄力最短时）
local ICE_CRYSTAL_MAX_DIST = 10.0 -- 最远攻击距离（米，蓄力满时）
local ICE_CRYSTAL_LIFETIME = 2.5  -- 冰晶持续时间（秒）
local ICE_CRYSTAL_COUNT = 7       -- 冰晶柱数量
local ICE_CRYSTAL_HEIGHT = 2.5    -- 冰晶柱固定高度（米）

-- 治愈技能常量
local HEAL_DURATION = 1.2         -- 治愈动画持续时间（秒）
local HEAL_COOLDOWN = 3.0         -- 治愈冷却时间（秒）

-- 潜行常量
local CROUCH_SPEED = 2.5          -- 潜行移动速度（减速）
local ANIM_FPS_CROUCH = 8         -- 潜行动画帧率

-- 蹲下动画自定义帧序列（只使用原始12帧中的特定帧）
-- enter阶段: 播放序列索引1~4 (原帧0,1,2,3)
-- loop阶段: 循环序列索引5~6 (原帧7,11 两帧交替)
local crouchFrameMap_ = { 0, 1, 2, 3, 7, 11 }
local CROUCH_ENTER_END = 4    -- enter阶段结束索引（含）
local CROUCH_LOOP_START = 5   -- loop阶段开始索引
local CROUCH_LOOP_END = 6     -- loop阶段结束索引

-- 动画状态
local ANIM_IDLE = "idle"
local ANIM_RUN = "run"
local ANIM_JUMP = "jump"
local ANIM_ATTACK = "attack"
local ANIM_BLOCK = "block"
local ANIM_CHARGE = "charge"
local ANIM_HEAL = "heal"
local ANIM_CROUCH = "crouch"
local ANIM_CROUCH_WALK = "crouch_walk"

-- 投射物
local PROJECTILE_SPEED = 10.0
local PROJECTILE_LIFETIME = 3.0

-- ============================================================================
-- 全局变量
-- ============================================================================
---@type Scene
local scene_ = nil
---@type Node
local cameraNode_ = nil
local physicsWorld_ = nil
local nvg_ = nil

-- 玩家相关
local playerNode_ = nil
local playerBody_ = nil
local onGround_ = false
local groundContactCount_ = 0
local facingRight_ = true

-- 动画相关
local currentAnim_ = ANIM_IDLE
local animFrame_ = 0
local animTimer_ = 0.0
local attackTimer_ = 0.0
local isAttacking_ = false
local isBlocking_ = false
local blockTimer_ = 0.0

-- 蓄力光波相关
local isCharging_ = false
local chargeTimer_ = 0.0
local chargeReleased_ = false  -- 蓄力释放中（播放释放帧）
local iceCrystals_ = {}        -- 活跃的地面冰晶群

-- 治愈技能相关
local isHealing_ = false
local healTimer_ = 0.0
local healCooldownTimer_ = 0.0  -- 冷却计时器

-- 潜行相关
local isCrouching_ = false

-- 角色属性
local playerHP_ = 100        -- 当前血量
local playerMaxHP_ = 100     -- 最大血量
local playerMP_ = 80         -- 当前魔力
local playerMaxMP_ = 80      -- 最大魔力
local mpRegenTimer_ = 0.0    -- 魔力回复计时器

-- 背包和技能面板
local showInventory_ = false  -- 背包面板开关
local showSkillPanel_ = false -- 技能面板开关

-- 背包数据（空背包）
local inventoryItems_ = {}

-- 技能数据（全部0级，含升级数值预览）
local skillList_ = {
    { name = "冰晶投射", key = "J", level = 0, maxLevel = 5, desc = "发射冰晶弹，命中造成伤害", cooldown = 0, mp = 0,
      levelData = { {dmg=5,mp=0}, {dmg=7,mp=0}, {dmg=10,mp=0}, {dmg=14,mp=0}, {dmg=18,mp=0} } },
    { name = "冰霜蓄力", key = "Q", level = 0, maxLevel = 5, desc = "蓄力后释放冰晶群，蓄力越久范围越大", cooldown = 0, mp = 30,
      levelData = { {dmg=20,mp=30}, {dmg=28,mp=28}, {dmg=36,mp=26}, {dmg=45,mp=24}, {dmg=55,mp=22} } },
    { name = "治愈术", key = "E", level = 0, maxLevel = 3, desc = "消耗魔力回复生命值", cooldown = 3, mp = 20,
      levelData = { {heal=20,mp=20,cd=3}, {heal=35,mp=18,cd=2.5}, {heal=50,mp=16,cd=2} } },
    { name = "格挡", key = "右键", level = 0, maxLevel = 3, desc = "举盾格挡，减少受到的伤害", cooldown = 0, mp = 15,
      levelData = { {reduce=0.5,mpSec=15}, {reduce=0.6,mpSec=12}, {reduce=0.7,mpSec=10} } },
    { name = "潜行", key = "S/Shift", level = 0, maxLevel = 3, desc = "蹲下缓慢移动，降低被发现概率", cooldown = 0, mp = 0,
      levelData = { {speed=2.5}, {speed=3.2}, {speed=4.0} } },
}

-- 技能伤害/消耗常量
local PROJECTILE_DAMAGE = 5       -- 冰晶投射命中伤害
local CHARGE_MP_COST = 30         -- 蓄力释放MP消耗
local CHARGE_DAMAGE = 20          -- 蓄力冰晶伤害
local HEAL_MP_COST = 20           -- 治愈术MP消耗
local HEAL_HP_RESTORE = 20        -- 治愈术回复HP
local BLOCK_MP_PER_SEC = 5        -- 格挡每秒MP消耗

-- 纹理（NanoVG image）
local imgIdle_ = -1
local imgRun_ = -1
local imgJump_ = -1
local imgAttack_ = -1
local imgBlock_ = -1
local imgCharge_ = -1
local imgHeal_ = -1
local imgCrouch_ = -1
local imgCrouchWalk_ = -1

-- 蹲下动画阶段: "enter"(下蹲中), "loop"(蹲住), "exit"(起身中)
local crouchPhase_ = "loop"
local imgWidth_ = 1029
local imgHeight_ = 768

-- 平台列表
local platforms_ = {}

-- 投射物列表
local projectiles_ = {}

-- 延迟发射冰晶
local pendingProjectile_ = nil
local projectileDelay_ = 0.15  -- 延迟0.15秒生成冰晶

-- 虚拟控制
local joystick_ = nil
local jumpButton_ = nil
local attackButton_ = nil

-- 调试
local debugDraw_ = false

-- 切图编辑器
local editorMode_ = false
local editorAnimIdx_ = 1  -- 当前查看的动画索引 (1=idle,2=run,3=jump,4=attack,5=block)
local editorFrame_ = 0    -- 当前查看的帧
local editorOffsetX_ = 0.0  -- 水平偏移（比例）
local editorOffsetY_ = 0.6  -- 垂直偏移比例（0.6=脚底对齐）
local editorScale_ = 5.5    -- 渲染缩放倍率
local editorCropW_ = 1.0    -- 裁切宽度比例（0.1~1.0，1.0=整格）
local editorCropH_ = 1.0    -- 裁切高度比例（0.1~1.0，1.0=整格）
local editorCropOffX_ = 0.0 -- 裁切区域水平偏移（-0.5~0.5）
local editorCropOffY_ = 0.0 -- 裁切区域垂直偏移（-0.5~0.5）
local editorParam_ = 1      -- 当前调整的参数 (1=offsetX,2=offsetY,3=scale,4=cropW,5=cropH,6=cropOffX,7=cropOffY)
local editorAnimNames_ = { "idle", "run", "jump", "attack", "block", "charge", "heal", "crouch", "crouch_walk" }
local editorParamNames_ = { "offsetX", "offsetY", "scale", "cropW", "cropH", "cropOffX", "cropOffY" }

-- ============================================================================
-- 工具函数
-- ============================================================================
local function PhysicsToScreen(physX, physY, camX, camY)
    local screenX = SCREEN_WIDTH / 2 + (physX - camX) * PIXELS_PER_UNIT
    local screenY = SCREEN_HEIGHT / 2 - (physY - camY) * PIXELS_PER_UNIT
    return screenX, screenY
end

-- ============================================================================
-- 主函数
-- ============================================================================
function Start()
    SampleStart()

    -- 创建 NanoVG 上下文
    nvg_ = nvgCreate(1)
    if nvg_ == nil then
        print("ERROR: 无法创建NanoVG上下文")
        return
    end

    -- 创建字体
    nvgCreateFont(nvg_, "sans", "Fonts/MiSans-Regular.ttf")

    -- 创建场景
    CreateScene()

    -- 创建世界
    CreateWorld()

    -- 创建玩家
    CreatePlayer()

    -- 加载序列帧纹理（在场景创建后加载，确保资源系统就绪）
    LoadSpriteSheets()

    -- 创建虚拟控制
    CreateGameHUD()

    -- 订阅事件
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("PostUpdate", "HandlePostUpdate")
    SubscribeToEvent(nvg_, "NanoVGRender", "HandleRender")
    SubscribeToEvent("PhysicsBeginContact2D", "HandlePhysicsBeginContact")
    SubscribeToEvent("PhysicsEndContact2D", "HandlePhysicsEndContact")

    print("=== 冰霜法师 - 平台跳跃游戏 ===")
    print("方向键/WASD移动, 空格跳跃, J/鼠标左键施法, 鼠标右键格挡")
end

function Stop()
    GameHUD.Shutdown()
    UI.Shutdown()
    if nvg_ ~= nil then
        nvgDelete(nvg_)
    end
end

-- ============================================================================
-- 加载序列帧
-- ============================================================================
function LoadSpriteSheets()
    local flags = NVG_IMAGE_NEAREST or 32

    -- 加载所有动画序列帧（12帧，基于原始三视图参考生成）
    imgIdle_ = nvgCreateImage(nvg_, "image/idle_12f_v2_20260530134219.png", flags)
    imgRun_ = nvgCreateImage(nvg_, "image/run_12f_v2_20260530134223.png", flags)
    imgJump_ = nvgCreateImage(nvg_, "image/jump_12f_v3_20260530140014.png", flags)
    imgAttack_ = nvgCreateImage(nvg_, "image/attack_12f_v2_20260530134230.png", flags)
    imgBlock_ = nvgCreateImage(nvg_, "image/block_12f_v2_20260530143345.png", flags)
    imgCharge_ = nvgCreateImage(nvg_, "image/ice_charge_side_12f_20260530180952.png", flags)
    imgHeal_ = nvgCreateImage(nvg_, "image/edited_heal_skill_12f_transparent_20260531002130.png", flags)
    imgCrouch_ = nvgCreateImage(nvg_, "image/crouch_sneak_12f_v2_20260531005607.png", flags)
    imgCrouchWalk_ = nvgCreateImage(nvg_, "image/crouch_walk_12f_20260531011542.png", flags)

    print("[LOAD] Image handles: idle=" .. tostring(imgIdle_) .. " run=" .. tostring(imgRun_) .. " jump=" .. tostring(imgJump_) .. " attack=" .. tostring(imgAttack_) .. " block=" .. tostring(imgBlock_) .. " charge=" .. tostring(imgCharge_) .. " heal=" .. tostring(imgHeal_) .. " crouch=" .. tostring(imgCrouch_))

    -- 用 nvgImageSize 获取实际图片尺寸
    local testImg = imgIdle_
    if testImg == nil or testImg <= 0 then testImg = imgRun_ end
    if testImg ~= nil and testImg > 0 then
        local w, h = nvgImageSize(nvg_, testImg)
        imgWidth_ = w
        imgHeight_ = h
        print("[LOAD] 序列帧加载成功, 实际尺寸: " .. w .. "x" .. h)
    else
        print("[LOAD] 序列帧加载失败! 将使用占位符圆形渲染角色")
        imgWidth_ = 0
        imgHeight_ = 0
    end
end

-- ============================================================================
-- 场景创建
-- ============================================================================
function CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("DebugRenderer")

    physicsWorld_ = scene_:CreateComponent("PhysicsWorld2D")
    physicsWorld_.gravity = Vector2(0, -GRAVITY)
    physicsWorld_.autoClearForces = true

    -- 正交相机
    cameraNode_ = scene_:CreateChild("Camera")
    local camera = cameraNode_:CreateComponent("Camera")
    camera.orthographic = true
    camera.orthoSize = SCREEN_HEIGHT / 2
    cameraNode_.position = Vector3(0, 0, -10)

    renderer:SetViewport(0, Viewport:new(scene_, camera))
end

-- ============================================================================
-- 创建世界 (白盒占位平台)
-- ============================================================================
function CreateWorld()
    -- 地面
    local groundNode = scene_:CreateChild("Ground")
    groundNode:SetPosition2D(0, -4.0)
    local groundBody = groundNode:CreateComponent("RigidBody2D")
    groundBody.bodyType = BT_STATIC
    local groundShape = groundNode:CreateComponent("CollisionBox2D")
    groundShape:SetSize(40, 1)
    groundShape.friction = 0.3
    groundShape.restitution = 0.0
    groundShape.categoryBits = 1

    table.insert(platforms_, { x = 0, y = -4.0, width = 40, height = 1 })

    -- 平台数据
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
        local platformNode = scene_:CreateChild("Platform")
        platformNode:SetPosition2D(data.x, data.y)
        local platformBody = platformNode:CreateComponent("RigidBody2D")
        platformBody.bodyType = BT_STATIC
        local platformShape = platformNode:CreateComponent("CollisionBox2D")
        platformShape:SetSize(data.width, data.height)
        platformShape.friction = 0.3
        platformShape.restitution = 0.0
        platformShape.categoryBits = 1

        table.insert(platforms_, data)
    end
end

-- ============================================================================
-- 创建玩家
-- ============================================================================
function CreatePlayer()
    playerNode_ = scene_:CreateChild("Player")
    playerNode_:SetPosition2D(0, 0)

    playerBody_ = playerNode_:CreateComponent("RigidBody2D")
    playerBody_.bodyType = BT_DYNAMIC
    playerBody_.fixedRotation = true
    playerBody_.linearDamping = 0.0
    playerBody_.gravityScale = 1.0

    -- 身体碰撞体（圆形，不卡墙）
    local bodyShape = playerNode_:CreateComponent("CollisionCircle2D")
    bodyShape.radius = PLAYER_RADIUS
    bodyShape.density = 1.0
    bodyShape.friction = 0.0
    bodyShape.restitution = 0.0
    bodyShape.categoryBits = 2
    bodyShape.maskBits = 0xFFFF

    -- 脚底传感器
    local footSensor = playerNode_:CreateComponent("CollisionCircle2D")
    footSensor.radius = PLAYER_RADIUS * 0.7
    footSensor.center = Vector2(0, -PLAYER_RADIUS * 0.9)
    footSensor.trigger = true
    footSensor.categoryBits = 4
    footSensor.maskBits = 1
end

-- ============================================================================
-- 虚拟控制
-- ============================================================================
function CreateGameHUD()
    GameHUD.Initialize()
    local hud = GameHUD.Create({
        enableJump = true,
        enableShoot = true,
        shootLabel = "施法",
    })
    joystick_ = hud.joystick
    jumpButton_ = hud.jumpButton
    attackButton_ = hud.shootButton
end

-- ============================================================================
-- 碰撞处理
-- ============================================================================
local function GetOtherNode(nodeA, nodeB)
    if playerNode_ == nil then return nil end
    if nodeA == playerNode_ then return nodeB
    elseif nodeB == playerNode_ then return nodeA end
    return nil
end

local function IsGroundOrPlatform(node)
    if node == nil then return false end
    return node.name == "Ground" or node.name:find("Platform", 1, true) ~= nil
end

function HandlePhysicsBeginContact(eventType, eventData)
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local nodeB = eventData["NodeB"]:GetPtr("Node")
    local hitNode = GetOtherNode(nodeA, nodeB)
    if IsGroundOrPlatform(hitNode) then
        groundContactCount_ = groundContactCount_ + 1
        onGround_ = true
    end
end

function HandlePhysicsEndContact(eventType, eventData)
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local nodeB = eventData["NodeB"]:GetPtr("Node")
    local hitNode = GetOtherNode(nodeA, nodeB)
    if IsGroundOrPlatform(hitNode) then
        groundContactCount_ = groundContactCount_ - 1
        if groundContactCount_ <= 0 then
            groundContactCount_ = 0
            onGround_ = false
        end
    end
end

-- ============================================================================
-- 施法 - 创建冰晶投射物
-- ============================================================================
function CastSpell()
    if isAttacking_ then return end
    isAttacking_ = true
    attackTimer_ = 0.0
    currentAnim_ = ANIM_ATTACK
    animFrame_ = 0
    animTimer_ = 0.0

    -- 设置延迟发射（0.1秒后生成冰晶）
    pendingProjectile_ = {
        delay = projectileDelay_,
        dir = facingRight_ and 1 or -1,
    }
end

-- ============================================================================
-- 更新逻辑
-- ============================================================================
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    if playerBody_ == nil then return end

    -- 判定框切换（TAB键，再按隐藏）
    if input:GetKeyPress(KEY_TAB) then
        debugDraw_ = not debugDraw_
    end

    -- 背包面板切换（B键）
    if input:GetKeyPress(KEY_B) then
        showInventory_ = not showInventory_
        if showInventory_ then showSkillPanel_ = false end  -- 互斥
    end
    -- 技能面板切换（Z键）
    if input:GetKeyPress(KEY_Z) then
        showSkillPanel_ = not showSkillPanel_
        if showSkillPanel_ then showInventory_ = false end  -- 互斥
    end

    -- 切图编辑器切换
    if input:GetKeyPress(KEY_1) then
        editorMode_ = not editorMode_
        if editorMode_ then
            print("[EDITOR] 切图编辑器已开启")
            print("[EDITOR] Q/E切换动画, 左/右切换帧, 上/下调offsetY, SHIFT+左/右调offsetX, +/-调scale")
        end
    end

    -- 编辑器模式下的输入处理
    if editorMode_ then
        -- Q/E 切换动画
        if input:GetKeyPress(KEY_Q) then
            editorAnimIdx_ = editorAnimIdx_ - 1
            if editorAnimIdx_ < 1 then editorAnimIdx_ = #editorAnimNames_ end
            editorFrame_ = 0
        end
        if input:GetKeyPress(KEY_E) then
            editorAnimIdx_ = editorAnimIdx_ + 1
            if editorAnimIdx_ > #editorAnimNames_ then editorAnimIdx_ = 1 end
            editorFrame_ = 0
        end
        -- A/D 切换帧
        if input:GetKeyPress(KEY_A) or input:GetKeyPress(KEY_LEFT) then
            editorFrame_ = editorFrame_ - 1
            if editorFrame_ < 0 then editorFrame_ = SPRITE_FRAMES - 1 end
        end
        if input:GetKeyPress(KEY_D) or input:GetKeyPress(KEY_RIGHT) then
            editorFrame_ = editorFrame_ + 1
            if editorFrame_ >= SPRITE_FRAMES then editorFrame_ = 0 end
        end
        -- W/S 切换当前调整的参数
        if input:GetKeyPress(KEY_W) or input:GetKeyPress(KEY_UP) then
            editorParam_ = editorParam_ - 1
            if editorParam_ < 1 then editorParam_ = #editorParamNames_ end
        end
        if input:GetKeyPress(KEY_S) or input:GetKeyPress(KEY_DOWN) then
            editorParam_ = editorParam_ + 1
            if editorParam_ > #editorParamNames_ then editorParam_ = 1 end
        end
        -- [ / ] 调整当前参数值
        local step = 0
        if input:GetKeyPress(KEY_LEFTBRACKET) then step = -1 end
        if input:GetKeyPress(KEY_RIGHTBRACKET) then step = 1 end
        if step ~= 0 then
            if editorParam_ == 1 then
                editorOffsetX_ = editorOffsetX_ + step * 0.02
            elseif editorParam_ == 2 then
                editorOffsetY_ = editorOffsetY_ + step * 0.02
            elseif editorParam_ == 3 then
                editorScale_ = math.max(1.0, editorScale_ + step * 0.5)
            elseif editorParam_ == 4 then
                editorCropW_ = math.max(0.1, math.min(1.0, editorCropW_ + step * 0.05))
            elseif editorParam_ == 5 then
                editorCropH_ = math.max(0.1, math.min(1.0, editorCropH_ + step * 0.05))
            elseif editorParam_ == 6 then
                editorCropOffX_ = math.max(-0.5, math.min(0.5, editorCropOffX_ + step * 0.02))
            elseif editorParam_ == 7 then
                editorCropOffY_ = math.max(-0.5, math.min(0.5, editorCropOffY_ + step * 0.02))
            end
        end
        return  -- 编辑器模式不处理游戏逻辑
    end

    -- 输入处理
    local currentVel = playerBody_.linearVelocity
    local desiredVelX = 0

    -- 虚拟摇杆输入
    if joystick_ then
        local moveX, _ = joystick_:getMovement()
        if moveX < -0.1 then
            desiredVelX = -PLAYER_SPEED
            facingRight_ = false
        elseif moveX > 0.1 then
            desiredVelX = PLAYER_SPEED
            facingRight_ = true
        end
    end

    -- 键盘输入（补充，确保跳跃中也能改变朝向）
    if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then
        desiredVelX = -PLAYER_SPEED
        facingRight_ = false
    elseif input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then
        desiredVelX = PLAYER_SPEED
        facingRight_ = true
    end

    -- 施法/格挡期间可以移动但速度减半
    if isAttacking_ or isBlocking_ then
        desiredVelX = desiredVelX * 0.5
    end

    playerBody_.linearVelocity = Vector2(desiredVelX, currentVel.y)

    -- 跳跃
    local jumpPressed = input:GetKeyPress(KEY_SPACE) or input:GetKeyPress(KEY_W) or input:GetKeyPress(KEY_UP)
    if jumpButton_ and jumpButton_.isPressed then
        jumpPressed = true
    end

    if onGround_ and jumpPressed then
        playerBody_.linearVelocity = Vector2(desiredVelX, PLAYER_JUMP_SPEED)
        playerBody_.awake = true
    end

    -- 施法
    local attackPressed = input:GetKeyPress(KEY_J) or input:GetMouseButtonPress(MOUSEB_LEFT)
    if attackButton_ and attackButton_.isPressed then
        attackPressed = true
    end
    if attackPressed and not isBlocking_ and not isCharging_ and not chargeReleased_ then
        CastSpell()
    end

    -- 格挡（鼠标右键长按，松开结束）
    local blockHeld = input:GetMouseButtonDown(MOUSEB_RIGHT)
    if blockHeld and not isBlocking_ and not isAttacking_ and not isCharging_ and playerMP_ > 0 then
        -- 开始格挡（需要有MP）
        isBlocking_ = true
        currentAnim_ = ANIM_BLOCK
        animFrame_ = 0
        animTimer_ = 0.0
    elseif isBlocking_ and not blockHeld then
        -- 松开右键，结束格挡
        isBlocking_ = false
    end
    -- 格挡期间持续消耗MP，不足时自动停止
    if isBlocking_ then
        playerMP_ = playerMP_ - BLOCK_MP_PER_SEC * dt
        if playerMP_ <= 0 then
            playerMP_ = 0
            isBlocking_ = false
        end
    end

    -- 蓄力光波（Q键长按，最多3秒）
    local chargeHeld = input:GetKeyDown(KEY_Q)
    if not editorMode_ then
        if input:GetKeyPress(KEY_Q) and not isCharging_ and not chargeReleased_ and not isAttacking_ and not isBlocking_ then
            -- 开始蓄力
            isCharging_ = true
            chargeTimer_ = 0.0
            currentAnim_ = ANIM_CHARGE
            animFrame_ = 0
            animTimer_ = 0.0
        elseif isCharging_ then
            chargeTimer_ = chargeTimer_ + dt
            -- 松开Q或达到最大时间 → 释放冰晶
            if not chargeHeld or chargeTimer_ >= CHARGE_MAX_DURATION then
                -- MP不足时取消蓄力，不释放
                if playerMP_ < CHARGE_MP_COST then
                    isCharging_ = false
                    chargeReleased_ = false
                else
                isCharging_ = false
                chargeReleased_ = true
                playerMP_ = playerMP_ - CHARGE_MP_COST
                -- 在前方地面生成矿脉状冰晶群（蓄力越久距离越远）
                local pos = playerNode_.position2D
                local dir = facingRight_ and 1 or -1
                local power = math.min(chargeTimer_ / CHARGE_MAX_DURATION, 1.0)  -- 0~1蓄力比例
                local distance = ICE_CRYSTAL_MIN_DIST + (ICE_CRYSTAL_MAX_DIST - ICE_CRYSTAL_MIN_DIST) * power
                local crystals = {}
                local baseX = pos.x + dir * distance
                local groundY = pos.y - 0.5  -- 地面高度估算（角色脚底偏下）
                for i = 1, ICE_CRYSTAL_COUNT do
                    local spread = (i - (ICE_CRYSTAL_COUNT + 1) / 2) * 0.6 * dir
                    -- 固定高度，中间最高两侧递减
                    local centerFactor = 1.0 - math.abs(i - (ICE_CRYSTAL_COUNT + 1) / 2) / ((ICE_CRYSTAL_COUNT + 1) / 2)
                    local h = ICE_CRYSTAL_HEIGHT * (0.4 + centerFactor * 0.6) * (0.8 + math.random() * 0.2)
                    table.insert(crystals, {
                        x = baseX + spread,
                        height = h,
                        width = 0.2 + math.random() * 0.25,
                        delay = (i - 1) * 0.05,  -- 依次爆出的延迟
                        angle = (math.random() - 0.5) * 0.3,  -- 轻微倾斜角
                    })
                end
                table.insert(iceCrystals_, {
                    crystals = crystals,
                    groundY = groundY,
                    life = ICE_CRYSTAL_LIFETIME,
                    maxLife = ICE_CRYSTAL_LIFETIME,
                    power = power,
                    spawnTime = 0,
                    dir = dir,
                })
                -- 切换到释放帧（帧9-11）
                animFrame_ = 9
                animTimer_ = 0.0
                end  -- end else (MP足够)
            end
        end
        -- 释放动画播放完毕后恢复
        if chargeReleased_ and currentAnim_ == ANIM_CHARGE and animFrame_ >= 11 then
            chargeReleased_ = false
        end
    end

    -- 治愈技能（E键，一次性释放，有冷却）
    if not editorMode_ then
        -- 冷却计时
        if healCooldownTimer_ > 0 then
            healCooldownTimer_ = healCooldownTimer_ - dt
        end
        if input:GetKeyPress(KEY_E) and not isHealing_ and not isCharging_ and not chargeReleased_ and not isAttacking_ and not isBlocking_ and healCooldownTimer_ <= 0 and playerMP_ >= HEAL_MP_COST then
            isHealing_ = true
            healTimer_ = 0.0
            currentAnim_ = ANIM_HEAL
            animFrame_ = 0
            animTimer_ = 0.0
            playerMP_ = playerMP_ - HEAL_MP_COST
        end
        if isHealing_ then
            healTimer_ = healTimer_ + dt
            if healTimer_ >= HEAL_DURATION then
                isHealing_ = false
                healCooldownTimer_ = HEAL_COOLDOWN
                -- 治愈完成，回复HP
                playerHP_ = math.min(playerHP_ + HEAL_HP_RESTORE, playerMaxHP_)
            end
        end
    end

    -- 潜行（S键或左Shift长按，地面时可用）
    if not editorMode_ then
        local crouchHeld = input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_LSHIFT)
        local wasCrouching = isCrouching_
        if crouchHeld and onGround_ and not isCharging_ and not chargeReleased_ and not isHealing_ and not isAttacking_ then
            if not wasCrouching then
                -- 刚开始蹲下，进入下蹲过渡阶段
                isCrouching_ = true
                crouchPhase_ = "enter"
                animFrame_ = 1  -- crouchFrameMap_ 索引从1开始
                animTimer_ = 0.0
            end
        else
            if wasCrouching then
                -- 松开键，立即结束蹲下
                isCrouching_ = false
                crouchPhase_ = "loop"
                animFrame_ = 0
                animTimer_ = 0.0
            end
        end
    end

    -- 蓄力/治愈期间不能移动
    if isCharging_ or chargeReleased_ or isHealing_ then
        desiredVelX = 0
        playerBody_.linearVelocity = Vector2(0, currentVel.y)
    elseif isCrouching_ then
        -- 潜行时减速
        desiredVelX = desiredVelX * (CROUCH_SPEED / PLAYER_SPEED)
        playerBody_.linearVelocity = Vector2(desiredVelX, currentVel.y)
    end

    -- 魔力自然回复（每2秒回复1点）
    mpRegenTimer_ = mpRegenTimer_ + dt
    if mpRegenTimer_ >= 2.0 then
        mpRegenTimer_ = mpRegenTimer_ - 2.0
        if playerMP_ < playerMaxMP_ then
            playerMP_ = math.min(playerMP_ + 1, playerMaxMP_)
        end
    end

    -- 更新动画状态
    UpdateAnimation(dt, desiredVelX)

    -- 处理延迟发射冰晶
    if pendingProjectile_ then
        pendingProjectile_.delay = pendingProjectile_.delay - dt
        if pendingProjectile_.delay <= 0 then
            local pos = playerNode_.position2D
            local dir = pendingProjectile_.dir
            local spawnX = pos.x + dir * 0.8
            local spawnY = pos.y + 0.2
            table.insert(projectiles_, {
                x = spawnX,
                y = spawnY,
                vx = dir * PROJECTILE_SPEED,
                vy = 0,
                life = PROJECTILE_LIFETIME,
                size = 0.3,
            })
            pendingProjectile_ = nil
        end
    end

    -- 更新投射物
    UpdateProjectiles(dt)

    -- 更新地面冰晶
    UpdateIceCrystals(dt)

    -- 物理调试
    if debugDraw_ and physicsWorld_ then
        physicsWorld_:DrawDebugGeometry()
    end
end

-- ============================================================================
-- 动画状态机
-- ============================================================================
function UpdateAnimation(dt, velX)
    -- 攻击动画优先
    if isAttacking_ then
        attackTimer_ = attackTimer_ + dt
        local attackDuration = SPRITE_FRAMES / ANIM_FPS_ATTACK
        if attackTimer_ >= attackDuration then
            isAttacking_ = false
            attackTimer_ = 0.0
        end
    end

    -- 确定当前动画（记录切换前的状态）
    local prevAnim = currentAnim_
    if isHealing_ then
        currentAnim_ = ANIM_HEAL
    elseif isCharging_ or chargeReleased_ then
        currentAnim_ = ANIM_CHARGE
    elseif isBlocking_ then
        currentAnim_ = ANIM_BLOCK
    elseif not isAttacking_ then
        if not onGround_ then
            currentAnim_ = ANIM_JUMP
        elseif isCrouching_ then
            -- 蹲下时区分蹲走和蹲下
            if math.abs(velX) > 0.1 and crouchPhase_ == "loop" then
                currentAnim_ = ANIM_CROUCH_WALK
            else
                currentAnim_ = ANIM_CROUCH
            end
        elseif math.abs(velX) > 0.1 then
            currentAnim_ = ANIM_RUN
        else
            currentAnim_ = ANIM_IDLE
        end
    end

    -- 动画切换时重置帧
    if currentAnim_ ~= prevAnim then
        if currentAnim_ == ANIM_CROUCH then
            -- 进入蹲下时，如果已在loop阶段就从loop开始
            if crouchPhase_ == "loop" then
                animFrame_ = CROUCH_LOOP_START
            else
                animFrame_ = 1
            end
            animTimer_ = 0.0
        elseif currentAnim_ == ANIM_CROUCH_WALK then
            -- 进入蹲走时从0开始
            animFrame_ = 0
            animTimer_ = 0.0
        elseif prevAnim == ANIM_CROUCH or prevAnim == ANIM_CROUCH_WALK then
            -- 从蹲下/蹲走切到其他动画时重置
            animFrame_ = 0
            animTimer_ = 0.0
        else
            animFrame_ = 0
            animTimer_ = 0.0
        end
    end

    -- 根据动画类型选择帧率
    local fps = ANIM_FPS
    if currentAnim_ == ANIM_RUN then
        fps = ANIM_FPS_RUN
    elseif currentAnim_ == ANIM_ATTACK then
        fps = ANIM_FPS_ATTACK
    elseif currentAnim_ == ANIM_BLOCK then
        fps = ANIM_FPS_BLOCK
    elseif currentAnim_ == ANIM_CHARGE then
        fps = ANIM_FPS_CHARGE
    elseif currentAnim_ == ANIM_HEAL then
        fps = 10  -- 治愈动画帧率（干净利落）
    elseif currentAnim_ == ANIM_CROUCH then
        fps = ANIM_FPS_CROUCH
    elseif currentAnim_ == ANIM_CROUCH_WALK then
        fps = ANIM_FPS_CROUCH
    end

    -- 更新动画帧
    animTimer_ = animTimer_ + dt
    local frameInterval = 1.0 / fps
    if animTimer_ >= frameInterval then
        animTimer_ = animTimer_ - frameInterval
        animFrame_ = animFrame_ + 1

        if currentAnim_ == ANIM_ATTACK then
            -- 攻击动画不循环
            if animFrame_ >= SPRITE_FRAMES then
                animFrame_ = SPRITE_FRAMES - 1
            end
        elseif currentAnim_ == ANIM_BLOCK then
            -- 格挡动画：0-2起手，3-9结界持续循环，10-11收杖
            if isBlocking_ then
                -- 持续格挡时在3-9帧之间循环
                if animFrame_ > 9 then
                    animFrame_ = 3
                end
            else
                -- 松开后播放收杖动画（10-11）
                if animFrame_ >= SPRITE_FRAMES then
                    animFrame_ = SPRITE_FRAMES - 1
                end
            end
        elseif currentAnim_ == ANIM_CHARGE then
            -- 蓄力动画：0-2起手，3-8蓄力循环，9-11释放
            if isCharging_ then
                -- 蓄力中：在帧3-8之间循环
                if animFrame_ > 8 then
                    animFrame_ = 3
                end
            elseif chargeReleased_ then
                -- 释放中：播放9-11，到11停住
                if animFrame_ >= SPRITE_FRAMES then
                    animFrame_ = SPRITE_FRAMES - 1
                end
            else
                -- 结束
                if animFrame_ >= SPRITE_FRAMES then
                    animFrame_ = SPRITE_FRAMES - 1
                end
            end
        elseif currentAnim_ == ANIM_HEAL then
            -- 治愈动画：单次播放，到末帧停住
            if animFrame_ >= SPRITE_FRAMES then
                animFrame_ = SPRITE_FRAMES - 1
            end
        elseif currentAnim_ == ANIM_CROUCH then
            -- 蹲下动画使用 crouchFrameMap_ 索引（1-based）
            -- enter阶段: 索引1~4 (原帧0,1,2,3), 到4后进入loop
            -- loop阶段: 索引5~6 (原帧7,9) 循环
            if crouchPhase_ == "enter" then
                if animFrame_ > CROUCH_ENTER_END then
                    animFrame_ = CROUCH_LOOP_START
                    crouchPhase_ = "loop"
                end
            elseif crouchPhase_ == "loop" then
                if animFrame_ > CROUCH_LOOP_END then
                    animFrame_ = CROUCH_LOOP_START
                end
            end
        elseif currentAnim_ == ANIM_CROUCH_WALK then
            -- 蹲走动画：全16帧循环
            animFrame_ = animFrame_ % 16
        else
            -- 其他动画循环
            animFrame_ = animFrame_ % SPRITE_FRAMES
        end
    end
end

-- ============================================================================
-- 更新投射物
-- ============================================================================
function UpdateProjectiles(dt)
    local i = 1
    while i <= #projectiles_ do
        local p = projectiles_[i]
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(projectiles_, i)
        else
            i = i + 1
        end
    end
end

-- ============================================================================
-- 更新地面冰晶
-- ============================================================================
function UpdateIceCrystals(dt)
    local i = 1
    while i <= #iceCrystals_ do
        local g = iceCrystals_[i]
        g.life = g.life - dt
        g.spawnTime = g.spawnTime + dt
        if g.life <= 0 then
            table.remove(iceCrystals_, i)
        else
            i = i + 1
        end
    end
end

-- ============================================================================
-- 相机跟随
-- ============================================================================
function HandlePostUpdate(eventType, eventData)
    if playerNode_ ~= nil and cameraNode_ ~= nil then
        local pos = playerNode_.position2D
        -- 平滑相机跟随
        local camPos = cameraNode_.position
        local targetX = pos.x
        local targetY = math.max(pos.y, 0)  -- 相机不跟随太低
        local lerpFactor = 5.0 * eventData["TimeStep"]:GetFloat()
        local newX = camPos.x + (targetX - camPos.x) * lerpFactor
        local newY = camPos.y + (targetY - camPos.y) * lerpFactor
        cameraNode_:SetPosition(Vector3(newX, newY, -10))
    end
end

-- ============================================================================
-- NanoVG 渲染
-- ============================================================================
function HandleRender(eventType, eventData)
    if nvg_ == nil then return end

    local width = graphics:GetWidth()
    local height = graphics:GetHeight()

    nvgBeginFrame(nvg_, width, height, 1.0)

    -- 获取相机位置
    local camPos = cameraNode_ and cameraNode_.worldPosition or Vector3(0, 0, -10)
    local camX = camPos.x
    local camY = camPos.y

    -- 绘制背景
    DrawBackground(width, height)

    -- 绘制平台（白盒）
    DrawPlatforms(width, height, camX, camY)

    -- 绘制投射物
    DrawProjectiles(width, height, camX, camY)

    -- 绘制蓄力法阵特效（在玩家后面）
    if isCharging_ then
        DrawChargeEffect(width, height, camX, camY)
    end

    -- 绘制治愈特效（在玩家后面）
    if isHealing_ then
        DrawHealEffect(width, height, camX, camY)
    end

    -- 绘制玩家
    DrawPlayer(width, height, camX, camY)

    -- 绘制地面冰晶
    DrawIceCrystals(width, height, camX, camY)

    -- 绘制 HP/MP 血条和魔力条（左上角，始终显示）
    if not editorMode_ then
        DrawHPMPBars(width, height)
    end

    -- 绘制调试信息
    if not editorMode_ and debugDraw_ then
        DrawDebugInfo(width, height)
    end

    -- 绘制背包面板
    if showInventory_ then
        DrawInventoryPanel(width, height)
    end

    -- 绘制技能面板
    if showSkillPanel_ then
        DrawSkillPanel(width, height)
    end

    -- 切图编辑器
    if editorMode_ then
        DrawSpriteEditor(width, height)
    end

    nvgEndFrame(nvg_)
end

-- ============================================================================
-- 绘制背景
-- ============================================================================
function DrawBackground(width, height)
    nvgBeginPath(nvg_)
    nvgRect(nvg_, 0, 0, width, height)
    local bg = nvgLinearGradient(nvg_, 0, 0, 0, height,
        nvgRGBA(20, 30, 60, 255),
        nvgRGBA(40, 60, 120, 255))
    nvgFillPaint(nvg_, bg)
    nvgFill(nvg_)

    -- 星星装饰
    nvgFillColor(nvg_, nvgRGBA(255, 255, 255, 100))
    math.randomseed(42)
    for i = 1, 50 do
        local sx = math.random() * width
        local sy = math.random() * height * 0.7
        local sr = 1 + math.random() * 2
        nvgBeginPath(nvg_)
        nvgCircle(nvg_, sx, sy, sr)
        nvgFill(nvg_)
    end
end

-- ============================================================================
-- 绘制平台（白盒占位）
-- ============================================================================
function DrawPlatforms(width, height, camX, camY)
    local sx = width / SCREEN_WIDTH
    local sy = height / SCREEN_HEIGHT
    for _, p in ipairs(platforms_) do
        local screenX, screenY = PhysicsToScreen(p.x, p.y, camX, camY)
        local w = p.width * PIXELS_PER_UNIT
        local h = p.height * PIXELS_PER_UNIT

        -- 转换为屏幕坐标
        screenX = screenX * sx
        screenY = screenY * sy
        w = w * sx
        h = h * sy

        -- 平台阴影
        nvgBeginPath(nvg_)
        nvgRoundedRect(nvg_, screenX - w/2 + 2, screenY - h/2 + 2, w, h, 4)
        nvgFillColor(nvg_, nvgRGBA(0, 0, 0, 60))
        nvgFill(nvg_)

        -- 白盒平台
        nvgBeginPath(nvg_)
        nvgRoundedRect(nvg_, screenX - w/2, screenY - h/2, w, h, 4)
        local grad = nvgLinearGradient(nvg_,
            screenX - w/2, screenY - h/2,
            screenX - w/2, screenY + h/2,
            nvgRGBA(220, 230, 240, 255),
            nvgRGBA(180, 190, 210, 255))
        nvgFillPaint(nvg_, grad)
        nvgFill(nvg_)

        -- 边框
        nvgStrokeColor(nvg_, nvgRGBA(150, 160, 180, 200))
        nvgStrokeWidth(nvg_, 1.5)
        nvgStroke(nvg_)
    end
end

-- ============================================================================
-- 绘制投射物（冰晶 - 水平飞行，不旋转，周围雾气）
-- ============================================================================
function DrawProjectiles(width, height, camX, camY)
    local sx = width / SCREEN_WIDTH
    local sy = height / SCREEN_HEIGHT

    for _, p in ipairs(projectiles_) do
        local screenX, screenY = PhysicsToScreen(p.x, p.y, camX, camY)
        screenX = screenX * sx
        screenY = screenY * sy
        local size = p.size * PIXELS_PER_UNIT * sx

        -- 周围环绕的雾气（多层半透明圆）
        local fogPhase = (PROJECTILE_LIFETIME - p.life) * 4.0
        for i = 1, 4 do
            local angle = fogPhase + i * 1.57  -- 等间距分布
            local fogDist = size * (0.8 + math.sin(fogPhase + i) * 0.3)
            local fogX = screenX + math.cos(angle) * fogDist
            local fogY = screenY + math.sin(angle) * fogDist * 0.5  -- 扁平化
            local fogR = size * (0.4 + math.sin(fogPhase * 0.7 + i * 2) * 0.15)
            nvgBeginPath(nvg_)
            nvgCircle(nvg_, fogX, fogY, fogR)
            nvgFillColor(nvg_, nvgRGBA(180, 220, 255, 50 + math.floor(math.sin(fogPhase + i) * 20)))
            nvgFill(nvg_)
        end

        -- 冰晶外发光
        nvgBeginPath(nvg_)
        nvgCircle(nvg_, screenX, screenY, size * 1.8)
        nvgFillColor(nvg_, nvgRGBA(100, 180, 255, 30))
        nvgFill(nvg_)

        -- 冰晶主体菱形（水平固定方向，不旋转）
        nvgBeginPath(nvg_)
        nvgMoveTo(nvg_, screenX - size, screenY)
        nvgLineTo(nvg_, screenX, screenY - size * 0.6)
        nvgLineTo(nvg_, screenX + size, screenY)
        nvgLineTo(nvg_, screenX, screenY + size * 0.6)
        nvgClosePath(nvg_)
        local iceGrad = nvgLinearGradient(nvg_,
            screenX - size, screenY,
            screenX + size, screenY,
            nvgRGBA(200, 235, 255, 255),
            nvgRGBA(100, 180, 255, 220))
        nvgFillPaint(nvg_, iceGrad)
        nvgFill(nvg_)

        -- 冰晶边框高光
        nvgStrokeColor(nvg_, nvgRGBA(220, 245, 255, 200))
        nvgStrokeWidth(nvg_, 1.2)
        nvgStroke(nvg_)

        -- 冰晶中心亮点
        nvgBeginPath(nvg_)
        nvgCircle(nvg_, screenX, screenY, size * 0.2)
        nvgFillColor(nvg_, nvgRGBA(255, 255, 255, 200))
        nvgFill(nvg_)
    end
end

-- ============================================================================
-- 绘制蓄力法阵特效（超华丽粒子+旋转魔法阵+冰晶环绕）
-- ============================================================================
function DrawChargeEffect(width, height, camX, camY)
    if playerNode_ == nil then return end

    local pos = playerNode_.position2D
    local screenX, screenY = PhysicsToScreen(pos.x, pos.y, camX, camY)
    local sx = width / SCREEN_WIDTH
    local sy = height / SCREEN_HEIGHT
    screenX = screenX * sx
    screenY = screenY * sy

    -- 蓄力进度（0~1）
    local progress = math.min(chargeTimer_ / CHARGE_MAX_DURATION, 1.0)
    local dir = facingRight_ and 1 or -1
    local t = chargeTimer_

    -- ====== 1) 角色身体光辉（全身发光底层） ======
    local glowRadius = 40 * sx * (0.8 + progress * 0.5)
    local glowCenterY = screenY - 30 * sy
    local bodyGlowAlpha = math.floor(30 + progress * 80)
    local glowGrad = nvgRadialGradient(nvg_, screenX, glowCenterY, glowRadius * 0.2, glowRadius,
        nvgRGBA(150, 220, 255, bodyGlowAlpha), nvgRGBA(100, 180, 255, 0))
    nvgBeginPath(nvg_)
    nvgCircle(nvg_, screenX, glowCenterY, glowRadius)
    nvgFillPaint(nvg_, glowGrad)
    nvgFill(nvg_)

    -- ====== 2) 脚底冰霜扩散圈（双层呼吸动画） ======
    local bodyRadius = 38 * sx
    local frostPulse = 1.0 + math.sin(t * 4) * 0.15
    -- 外圈
    local frostR1 = bodyRadius * (1.0 + progress * 0.6) * frostPulse
    nvgBeginPath(nvg_)
    nvgEllipse(nvg_, screenX, screenY, frostR1, frostR1 * 0.22)
    nvgStrokeColor(nvg_, nvgRGBA(120, 200, 255, math.floor((50 + progress * 120) * frostPulse)))
    nvgStrokeWidth(nvg_, 1.5 + progress * 2)
    nvgStroke(nvg_)
    -- 内圈（反向呼吸）
    local frostR2 = bodyRadius * (0.6 + progress * 0.3) * (2.0 - frostPulse)
    nvgBeginPath(nvg_)
    nvgEllipse(nvg_, screenX, screenY, frostR2, frostR2 * 0.22)
    nvgStrokeColor(nvg_, nvgRGBA(180, 235, 255, math.floor(40 + progress * 80)))
    nvgStrokeWidth(nvg_, 1.0 + progress)
    nvgStroke(nvg_)
    -- 脚底冰霜填充（半透明冰面）
    if progress > 0.3 then
        local iceAlpha = math.floor((progress - 0.3) / 0.7 * 60)
        nvgBeginPath(nvg_)
        nvgEllipse(nvg_, screenX, screenY, frostR1 * 0.8, frostR1 * 0.18)
        nvgFillColor(nvg_, nvgRGBA(180, 230, 255, iceAlpha))
        nvgFill(nvg_)
    end

    -- ====== 3) 角色周围浮动冰晶（大中小三层） ======
    -- 大冰晶（缓慢旋转，靠近身体）
    local bigCount = math.floor(2 + progress * 3)
    for i = 1, bigCount do
        local angle = (i / bigCount) * math.pi * 2 + t * 0.6
        local dist = bodyRadius * (0.9 + math.sin(t * 1.5 + i * 2.3) * 0.2)
        local cx = screenX + math.cos(angle) * dist
        local cy = glowCenterY + math.sin(angle) * dist * 0.5
        cy = cy + math.sin(t * 2 + i * 1.7) * 8 * sy

        local cSize = (5 + progress * 5) * sx
        local cAlpha = math.floor(160 + progress * 90)

        nvgSave(nvg_)
        nvgTranslate(nvg_, cx, cy)
        nvgRotate(nvg_, t * 1.5 + i * 1.2)
        -- 冰晶主体（六边形）
        nvgBeginPath(nvg_)
        for vi = 0, 5 do
            local va = (vi / 6) * math.pi * 2
            local vr = cSize * (vi % 2 == 0 and 1.0 or 0.6)
            if vi == 0 then
                nvgMoveTo(nvg_, math.cos(va) * vr, math.sin(va) * vr)
            else
                nvgLineTo(nvg_, math.cos(va) * vr, math.sin(va) * vr)
            end
        end
        nvgClosePath(nvg_)
        nvgFillColor(nvg_, nvgRGBA(160, 225, 255, cAlpha))
        nvgFill(nvg_)
        nvgStrokeColor(nvg_, nvgRGBA(220, 245, 255, cAlpha))
        nvgStrokeWidth(nvg_, 1.0)
        nvgStroke(nvg_)
        -- 内部高光
        nvgBeginPath(nvg_)
        nvgMoveTo(nvg_, -cSize * 0.2, -cSize * 0.5)
        nvgLineTo(nvg_, cSize * 0.1, -cSize * 0.1)
        nvgLineTo(nvg_, -cSize * 0.1, cSize * 0.2)
        nvgClosePath(nvg_)
        nvgFillColor(nvg_, nvgRGBA(255, 255, 255, math.floor(cAlpha * 0.4)))
        nvgFill(nvg_)
        nvgRestore(nvg_)
    end

    -- 中冰晶（快速旋转，中层轨道）
    local midCount = math.floor(4 + progress * 6)
    for i = 1, midCount do
        local angle = (i / midCount) * math.pi * 2 + t * (1.2 + i * 0.1)
        local dist = bodyRadius * (1.2 + math.sin(t * 2.5 + i * 1.1) * 0.3)
        local cx = screenX + math.cos(angle) * dist
        local cy = glowCenterY + math.sin(angle) * dist * 0.55
        cy = cy + math.sin(t * 3.5 + i * 2.5) * 5 * sy

        local cSize = (2.5 + progress * 3) * sx
        local cAlpha = math.floor((120 + progress * 130) * (0.6 + math.sin(t * 4 + i * 1.8) * 0.4))

        nvgSave(nvg_)
        nvgTranslate(nvg_, cx, cy)
        nvgRotate(nvg_, t * 2.5 + i * 0.9)
        -- 菱形
        nvgBeginPath(nvg_)
        nvgMoveTo(nvg_, 0, -cSize * 1.3)
        nvgLineTo(nvg_, cSize * 0.45, 0)
        nvgLineTo(nvg_, 0, cSize * 1.3)
        nvgLineTo(nvg_, -cSize * 0.45, 0)
        nvgClosePath(nvg_)
        nvgFillColor(nvg_, nvgRGBA(180, 235, 255, cAlpha))
        nvgFill(nvg_)
        nvgRestore(nvg_)
    end

    -- 小微粒（快速散布，外层轨道，闪烁）
    local dustCount = math.floor(8 + progress * 16)
    for i = 1, dustCount do
        local angle = (i / dustCount) * math.pi * 2 + t * (2.0 + i * 0.05)
        local dist = bodyRadius * (1.0 + progress * 0.8 + math.sin(t * 3 + i * 0.9) * 0.4)
        local px = screenX + math.cos(angle) * dist
        local py = glowCenterY + math.sin(angle) * dist * 0.45
        py = py + math.sin(t * 5 + i * 1.3) * 4 * sy
        local pSize = (1 + math.sin(t * 6 + i * 2.1) * 0.5) * sx * (1 + progress)
        local pAlpha = math.floor((80 + progress * 140) * (0.3 + math.sin(t * 7 + i * 3.1) * 0.7))
        if pAlpha > 0 then
            nvgBeginPath(nvg_)
            nvgCircle(nvg_, px, py, pSize)
            nvgFillColor(nvg_, nvgRGBA(200, 240, 255, pAlpha))
            nvgFill(nvg_)
        end
    end

    -- ====== 4) 法阵（角色前方，双层旋转） ======
    local circleOffX = dir * 65 * sx
    local circleX = screenX + circleOffX
    local circleY = screenY - 22 * sy
    local baseRadius = 28 * sx
    local radius = baseRadius * (0.5 + progress * 0.8)
    local rotation = t * 2.5
    local alpha = math.floor(130 + progress * 125)

    -- 法阵外层光晕
    local haloGrad = nvgRadialGradient(nvg_, circleX, circleY, radius * 0.5, radius * 1.5,
        nvgRGBA(100, 200, 255, math.floor(alpha * 0.3)), nvgRGBA(100, 200, 255, 0))
    nvgBeginPath(nvg_)
    nvgCircle(nvg_, circleX, circleY, radius * 1.5)
    nvgFillPaint(nvg_, haloGrad)
    nvgFill(nvg_)

    nvgSave(nvg_)
    nvgTranslate(nvg_, circleX, circleY)
    nvgRotate(nvg_, rotation)

    -- 外圈
    nvgBeginPath(nvg_)
    nvgCircle(nvg_, 0, 0, radius * 1.2)
    nvgStrokeColor(nvg_, nvgRGBA(100, 200, 255, alpha))
    nvgStrokeWidth(nvg_, 2 + progress * 2.5)
    nvgStroke(nvg_)

    -- 中圈
    nvgBeginPath(nvg_)
    nvgCircle(nvg_, 0, 0, radius * 0.85)
    nvgStrokeColor(nvg_, nvgRGBA(150, 230, 255, alpha))
    nvgStrokeWidth(nvg_, 1.5 + progress)
    nvgStroke(nvg_)

    -- 六芒星
    for i = 0, 5 do
        local angle1 = (i / 6) * math.pi * 2
        local angle2 = ((i + 2) / 6) * math.pi * 2
        local x1 = math.cos(angle1) * radius
        local y1 = math.sin(angle1) * radius
        local x2 = math.cos(angle2) * radius
        local y2 = math.sin(angle2) * radius
        nvgBeginPath(nvg_)
        nvgMoveTo(nvg_, x1, y1)
        nvgLineTo(nvg_, x2, y2)
        nvgStrokeColor(nvg_, nvgRGBA(180, 240, 255, alpha))
        nvgStrokeWidth(nvg_, 1.5 + progress * 1.5)
        nvgStroke(nvg_)
    end

    -- 内层反向旋转符文圈
    nvgRestore(nvg_)
    nvgSave(nvg_)
    nvgTranslate(nvg_, circleX, circleY)
    nvgRotate(nvg_, -rotation * 0.7)  -- 反向旋转
    local innerR = radius * 0.55
    -- 三角形符文
    for i = 0, 2 do
        local a1 = (i / 3) * math.pi * 2
        local a2 = ((i + 1) / 3) * math.pi * 2
        nvgBeginPath(nvg_)
        nvgMoveTo(nvg_, math.cos(a1) * innerR, math.sin(a1) * innerR)
        nvgLineTo(nvg_, math.cos(a2) * innerR, math.sin(a2) * innerR)
        nvgStrokeColor(nvg_, nvgRGBA(200, 245, 255, math.floor(alpha * 0.7)))
        nvgStrokeWidth(nvg_, 1.0 + progress)
        nvgStroke(nvg_)
    end
    -- 中心光点（脉冲）
    local pulseSize = radius * 0.12 * (1 + math.sin(t * 10) * 0.4)
    nvgBeginPath(nvg_)
    nvgCircle(nvg_, 0, 0, pulseSize)
    nvgFillColor(nvg_, nvgRGBA(240, 255, 255, 220 + math.floor(progress * 35)))
    nvgFill(nvg_)
    nvgRestore(nvg_)

    -- 法阵周围小光点环绕
    local dotCount = math.floor(6 + progress * 6)
    for i = 1, dotCount do
        local da = (i / dotCount) * math.pi * 2 + t * 3
        local dd = radius * (1.3 + math.sin(t * 4 + i * 2) * 0.2)
        local dx = circleX + math.cos(da) * dd
        local dy = circleY + math.sin(da) * dd
        local ds = (1.5 + math.sin(t * 8 + i * 3) * 0.8) * sx
        nvgBeginPath(nvg_)
        nvgCircle(nvg_, dx, dy, ds)
        nvgFillColor(nvg_, nvgRGBA(220, 250, 255, math.floor(150 * (0.5 + math.sin(t * 6 + i) * 0.5))))
        nvgFill(nvg_)
    end

    -- ====== 5) 螺旋冰晶轨迹（环绕角色的双螺旋上升光带） ======
    if progress > 0.2 then
        local spiralAlpha = (progress - 0.2) / 0.8
        local spiralCount = 2  -- 双螺旋
        for s = 1, spiralCount do
            local spiralOffset = (s - 1) * math.pi  -- 180度相位差
            local segCount = math.floor(15 + progress * 20)
            for i = 1, segCount do
                local segT = (i / segCount)
                local spiralAngle = segT * math.pi * 4 + t * 3.0 + spiralOffset
                local spiralDist = bodyRadius * (0.5 + segT * 0.8)
                local spiralX = screenX + math.cos(spiralAngle) * spiralDist
                local spiralY = glowCenterY + 20 * sy - segT * 80 * sy
                local segSize = (1.5 + (1.0 - segT) * 2.5) * sx * spiralAlpha
                local segAlpha = math.floor((1.0 - segT * 0.6) * 200 * spiralAlpha)
                if segAlpha > 10 then
                    nvgBeginPath(nvg_)
                    nvgCircle(nvg_, spiralX, spiralY, segSize)
                    if s == 1 then
                        nvgFillColor(nvg_, nvgRGBA(140, 210, 255, segAlpha))
                    else
                        nvgFillColor(nvg_, nvgRGBA(200, 240, 255, math.floor(segAlpha * 0.7)))
                    end
                    nvgFill(nvg_)
                end
            end
        end
    end

    -- ====== 6) 能量收束线（从四周汇聚向法阵，带弧度） ======
    if progress > 0.4 then
        local lineAlpha = math.floor((progress - 0.4) / 0.6 * 200)
        local lineCount = math.floor(8 + progress * 8)
        for i = 1, lineCount do
            local startAngle = (i / lineCount) * math.pi * 2 + t * 0.6 + i * 0.3
            local startDist = bodyRadius * (2.5 + math.sin(t * 2 + i) * 0.5)
            local lx1 = screenX + math.cos(startAngle) * startDist
            local ly1 = glowCenterY + math.sin(startAngle) * startDist * 0.4
            local lx2 = circleX + math.cos(t * 3 + i) * 5 * sx
            local ly2 = circleY + math.sin(t * 3 + i) * 5 * sy
            -- 中间控制点（弧线）
            local mx = (lx1 + lx2) * 0.5 + math.sin(t * 4 + i * 1.5) * 15 * sx
            local my = (ly1 + ly2) * 0.5 - 10 * sy
            local lFade = 0.5 + math.sin(t * 5 + i * 2.2) * 0.5
            nvgBeginPath(nvg_)
            nvgMoveTo(nvg_, lx1, ly1)
            nvgQuadTo(nvg_, mx, my, lx2, ly2)
            nvgStrokeColor(nvg_, nvgRGBA(160, 230, 255, math.floor(lineAlpha * lFade)))
            nvgStrokeWidth(nvg_, 1.0 + progress * 1.5)
            nvgStroke(nvg_)
            -- 线条末端亮点
            nvgBeginPath(nvg_)
            nvgCircle(nvg_, lx1, ly1, (1.5 + math.sin(t * 8 + i) * 0.5) * sx)
            nvgFillColor(nvg_, nvgRGBA(220, 250, 255, math.floor(lineAlpha * lFade * 0.8)))
            nvgFill(nvg_)
        end
    end

    -- ====== 7) 闪电能量弧（角色与法阵之间的电弧） ======
    if progress > 0.5 then
        local arcAlpha = (progress - 0.5) / 0.5
        local arcCount = math.floor(2 + progress * 3)
        for a = 1, arcCount do
            local arcPhase = t * 12 + a * 3.7
            -- 只在特定相位闪烁
            if math.sin(arcPhase) > 0.3 then
                local segments = 5 + math.floor(progress * 3)
                nvgBeginPath(nvg_)
                local ax1 = screenX + dir * 15 * sx
                local ay1 = glowCenterY
                nvgMoveTo(nvg_, ax1, ay1)
                for si = 1, segments do
                    local segProg = si / segments
                    local baseAX = ax1 + (circleX - ax1) * segProg
                    local baseAY = ay1 + (circleY - ay1) * segProg
                    local jitterX = (math.random() - 0.5) * 12 * sx * (1 - segProg)
                    local jitterY = (math.random() - 0.5) * 10 * sy * (1 - segProg)
                    nvgLineTo(nvg_, baseAX + jitterX, baseAY + jitterY)
                end
                nvgStrokeColor(nvg_, nvgRGBA(180, 240, 255, math.floor(200 * arcAlpha * (0.5 + math.sin(arcPhase) * 0.5))))
                nvgStrokeWidth(nvg_, 1.0 + progress)
                nvgStroke(nvg_)
            end
        end
    end

    -- ====== 8) 地面冰霜蔓延（从角色脚下向前方扩展冰冻地面） ======
    if progress > 0.3 then
        local frostExtent = (progress - 0.3) / 0.7
        local frostLength = frostExtent * math.abs(circleOffX) * 1.2
        local frostStartX = screenX + dir * bodyRadius * 0.3
        local frostEndX = frostStartX + dir * frostLength
        -- 冰霜地面半透明填充
        nvgBeginPath(nvg_)
        nvgMoveTo(nvg_, frostStartX, screenY)
        nvgLineTo(nvg_, frostEndX, screenY)
        nvgLineTo(nvg_, frostEndX, screenY + 4 * sy)
        nvgLineTo(nvg_, frostStartX, screenY + 4 * sy)
        nvgClosePath(nvg_)
        local frostGrad = nvgLinearGradient(nvg_, frostStartX, screenY, frostEndX, screenY,
            nvgRGBA(120, 200, 255, math.floor(100 * frostExtent)),
            nvgRGBA(120, 200, 255, 0))
        nvgFillPaint(nvg_, frostGrad)
        nvgFill(nvg_)
        -- 冰霜边缘闪烁微粒
        local frostParticles = math.floor(3 + frostExtent * 8)
        for fi = 1, frostParticles do
            local fp = fi / frostParticles
            local fpx = frostStartX + (frostEndX - frostStartX) * fp
            local fpy = screenY + (math.random() - 0.5) * 6 * sy
            local fpFlicker = math.sin(t * 10 + fi * 2.3)
            if fpFlicker > 0.2 then
                local fpSize = (1.0 + fpFlicker) * sx
                nvgBeginPath(nvg_)
                nvgCircle(nvg_, fpx, fpy, fpSize)
                nvgFillColor(nvg_, nvgRGBA(200, 240, 255, math.floor(120 * frostExtent * fpFlicker)))
                nvgFill(nvg_)
            end
        end
    end

    -- ====== 9) 上升冰雾（角色头顶飘散的寒气微粒，增强版） ======
    local mistCount = math.floor(8 + progress * 15)
    for i = 1, mistCount do
        local phase = t * 1.5 + i * 1.1
        local mx = screenX + math.sin(phase * 2.3) * bodyRadius * 0.8
        local myBase = glowCenterY - 20 * sy
        local my = myBase - (phase % 2.5) / 2.5 * 60 * sy
        local mAlpha = (1.0 - (phase % 2.5) / 2.5) * (0.3 + progress * 0.7)
        local mSize = (2 + math.sin(phase) * 1.5) * sx * (1 + progress * 0.6)
        if mAlpha > 0.05 then
            nvgBeginPath(nvg_)
            nvgCircle(nvg_, mx, my, mSize)
            nvgFillColor(nvg_, nvgRGBA(200, 240, 255, math.floor(90 * mAlpha)))
            nvgFill(nvg_)
        end
    end

    -- ====== 10) 脉冲波纹（周期性从角色中心向外扩散的圆环） ======
    local pulseInterval = 0.6 - progress * 0.2  -- 蓄力越满频率越高
    local pulseCount = 3
    for pi = 1, pulseCount do
        local pulsePhase = ((t + pi * pulseInterval) % (pulseInterval * pulseCount)) / (pulseInterval * pulseCount)
        local pulseRadius = bodyRadius * (0.5 + pulsePhase * 2.5)
        local pulseAlphaVal = (1.0 - pulsePhase) * progress
        if pulseAlphaVal > 0.05 then
            nvgBeginPath(nvg_)
            nvgCircle(nvg_, screenX, glowCenterY, pulseRadius)
            nvgStrokeColor(nvg_, nvgRGBA(150, 220, 255, math.floor(100 * pulseAlphaVal)))
            nvgStrokeWidth(nvg_, (1.5 - pulsePhase) * 2)
            nvgStroke(nvg_)
        end
    end

    -- ====== 11) 蓄力进度条（角色头顶） ======
    local barW = 50 * sx
    local barH = 5 * sy
    local barX = screenX - barW / 2
    local barY = screenY - 70 * sy
    -- 背景
    nvgBeginPath(nvg_)
    nvgRoundedRect(nvg_, barX, barY, barW, barH, 2)
    nvgFillColor(nvg_, nvgRGBA(0, 0, 0, 150))
    nvgFill(nvg_)
    -- 填充
    nvgBeginPath(nvg_)
    nvgRoundedRect(nvg_, barX + 1, barY + 1, (barW - 2) * progress, barH - 2, 1)
    local barGrad = nvgLinearGradient(nvg_, barX, barY, barX + barW * progress, barY,
        nvgRGBA(100, 200, 255, 255), nvgRGBA(200, 240, 255, 255))
    nvgFillPaint(nvg_, barGrad)
    nvgFill(nvg_)
end

-- ============================================================================
-- 绘制治愈特效（绿色光环 + 粒子）
-- ============================================================================
function DrawHealEffect(width, height, camX, camY)
    if playerNode_ == nil then return end

    local pos = playerNode_.position2D
    local screenX, screenY = PhysicsToScreen(pos.x, pos.y, camX, camY)
    local sx = width / SCREEN_WIDTH
    local sy = height / SCREEN_HEIGHT
    screenX = screenX * sx
    screenY = screenY * sy

    local progress = math.min(healTimer_ / HEAL_DURATION, 1.0)
    local t = healTimer_
    local bodyRadius = 40 * sx

    -- 光环出现/消失阶段
    local fadeIn = math.min(progress / 0.2, 1.0)   -- 前20%淡入
    local fadeOut = math.min((1.0 - progress) / 0.2, 1.0) -- 后20%淡出
    local alpha = fadeIn * fadeOut

    -- ====== 1) 全身绿色柔光 ======
    local glowCenterY = screenY - 30 * sy
    local glowRadius = bodyRadius * (1.2 + progress * 0.3)
    local glowGrad = nvgRadialGradient(nvg_, screenX, glowCenterY, glowRadius * 0.1, glowRadius,
        nvgRGBA(100, 255, 150, math.floor(60 * alpha)), nvgRGBA(50, 200, 100, 0))
    nvgBeginPath(nvg_)
    nvgCircle(nvg_, screenX, glowCenterY, glowRadius)
    nvgFillPaint(nvg_, glowGrad)
    nvgFill(nvg_)

    -- ====== 2) 主光环（快速扩散的绿色圆环） ======
    local ringCount = 3
    for ri = 1, ringCount do
        local ringPhase = (progress * 3 + ri * 0.3) % 1.0
        local ringRadius = bodyRadius * (0.4 + ringPhase * 1.8)
        local ringAlpha = (1.0 - ringPhase) * alpha
        if ringAlpha > 0.02 then
            nvgBeginPath(nvg_)
            nvgCircle(nvg_, screenX, glowCenterY, ringRadius)
            nvgStrokeColor(nvg_, nvgRGBA(80, 255, 140, math.floor(180 * ringAlpha)))
            nvgStrokeWidth(nvg_, (2.5 - ringPhase * 1.5) * sx)
            nvgStroke(nvg_)
        end
    end

    -- ====== 3) 底部魔法阵（绿色六芒星旋转） ======
    local circleRadius = bodyRadius * (0.6 + progress * 0.4)
    local rotation = t * 3.5
    nvgSave(nvg_)
    nvgTranslate(nvg_, screenX, screenY)
    nvgRotate(nvg_, rotation)
    -- 外圈
    nvgBeginPath(nvg_)
    nvgCircle(nvg_, 0, 0, circleRadius)
    nvgStrokeColor(nvg_, nvgRGBA(80, 230, 130, math.floor(160 * alpha)))
    nvgStrokeWidth(nvg_, 2 * sx)
    nvgStroke(nvg_)
    -- 六芒星
    for i = 0, 5 do
        local a1 = (i / 6) * math.pi * 2
        local a2 = ((i + 2) / 6) * math.pi * 2
        nvgBeginPath(nvg_)
        nvgMoveTo(nvg_, math.cos(a1) * circleRadius * 0.85, math.sin(a1) * circleRadius * 0.85)
        nvgLineTo(nvg_, math.cos(a2) * circleRadius * 0.85, math.sin(a2) * circleRadius * 0.85)
        nvgStrokeColor(nvg_, nvgRGBA(120, 255, 170, math.floor(140 * alpha)))
        nvgStrokeWidth(nvg_, 1.5 * sx)
        nvgStroke(nvg_)
    end
    nvgRestore(nvg_)

    -- ====== 4) 上升绿色光粒子（密集环绕上升） ======
    local particleCount = math.floor(15 + progress * 20)
    for i = 1, particleCount do
        local phase = t * 2.0 + i * 0.8
        local angle = (i / particleCount) * math.pi * 2 + t * 1.5
        local dist = bodyRadius * (0.3 + math.sin(phase * 0.7) * 0.4)
        local px = screenX + math.cos(angle) * dist
        local riseHeight = ((phase * 0.8) % 1.5) / 1.5
        local py = screenY - riseHeight * 80 * sy
        local pAlpha = (1.0 - riseHeight) * alpha
        local pSize = (1.5 + math.sin(phase * 3) * 0.8) * sx

        if pAlpha > 0.05 then
            nvgBeginPath(nvg_)
            nvgCircle(nvg_, px, py, pSize)
            -- 绿色为主，少量白色高亮
            if i % 5 == 0 then
                nvgFillColor(nvg_, nvgRGBA(255, 255, 220, math.floor(200 * pAlpha)))
            else
                nvgFillColor(nvg_, nvgRGBA(100, 255, 160, math.floor(180 * pAlpha)))
            end
            nvgFill(nvg_)
        end
    end

    -- ====== 5) 叶片/符文环绕（菱形绿色符文） ======
    local runeCount = math.floor(4 + progress * 4)
    for i = 1, runeCount do
        local runeAngle = (i / runeCount) * math.pi * 2 + t * 2.2
        local runeDist = bodyRadius * (0.8 + math.sin(t * 1.8 + i * 1.5) * 0.2)
        local rx = screenX + math.cos(runeAngle) * runeDist
        local ry = glowCenterY + math.sin(runeAngle) * runeDist * 0.45
        ry = ry + math.sin(t * 3 + i * 2) * 6 * sy
        local rSize = (4 + math.sin(t * 2.5 + i) * 1.5) * sx * alpha

        nvgSave(nvg_)
        nvgTranslate(nvg_, rx, ry)
        nvgRotate(nvg_, t * 3 + i * 1.3)
        -- 菱形叶片
        nvgBeginPath(nvg_)
        nvgMoveTo(nvg_, 0, -rSize * 1.5)
        nvgLineTo(nvg_, rSize * 0.5, 0)
        nvgLineTo(nvg_, 0, rSize * 1.5)
        nvgLineTo(nvg_, -rSize * 0.5, 0)
        nvgClosePath(nvg_)
        nvgFillColor(nvg_, nvgRGBA(80, 240, 140, math.floor(160 * alpha)))
        nvgFill(nvg_)
        -- 中线高光
        nvgBeginPath(nvg_)
        nvgMoveTo(nvg_, 0, -rSize * 1.2)
        nvgLineTo(nvg_, 0, rSize * 1.2)
        nvgStrokeColor(nvg_, nvgRGBA(200, 255, 220, math.floor(180 * alpha)))
        nvgStrokeWidth(nvg_, 0.8 * sx)
        nvgStroke(nvg_)
        nvgRestore(nvg_)
    end

    -- ====== 6) 螺旋光带（双螺旋绿色上升） ======
    local spiralSegs = math.floor(12 + progress * 10)
    for s = 1, 2 do
        local spiralOff = (s - 1) * math.pi
        for i = 1, spiralSegs do
            local segT = i / spiralSegs
            local sAngle = segT * math.pi * 3 + t * 2.5 + spiralOff
            local sDist = bodyRadius * (0.4 + segT * 0.3)
            local spx = screenX + math.cos(sAngle) * sDist
            local spy = screenY - segT * 70 * sy
            local sSize = (2.0 + (1.0 - segT) * 2.0) * sx * alpha
            local sAlpha = (1.0 - segT * 0.5) * alpha
            if sAlpha > 0.05 then
                nvgBeginPath(nvg_)
                nvgCircle(nvg_, spx, spy, sSize)
                nvgFillColor(nvg_, nvgRGBA(120, 255, 180, math.floor(140 * sAlpha)))
                nvgFill(nvg_)
            end
        end
    end

    -- ====== 7) 脚底治愈光柱（从底部向上的光柱效果） ======
    if progress > 0.15 then
        local pillarAlpha = alpha * math.min((progress - 0.15) / 0.2, 1.0)
        local pillarH = 90 * sy * pillarAlpha
        local pillarW = 18 * sx
        local pillarGrad = nvgLinearGradient(nvg_, screenX, screenY, screenX, screenY - pillarH,
            nvgRGBA(80, 255, 140, math.floor(80 * pillarAlpha)),
            nvgRGBA(80, 255, 140, 0))
        nvgBeginPath(nvg_)
        nvgMoveTo(nvg_, screenX - pillarW, screenY)
        nvgLineTo(nvg_, screenX + pillarW, screenY)
        nvgLineTo(nvg_, screenX + pillarW * 0.3, screenY - pillarH)
        nvgLineTo(nvg_, screenX - pillarW * 0.3, screenY - pillarH)
        nvgClosePath(nvg_)
        nvgFillPaint(nvg_, pillarGrad)
        nvgFill(nvg_)
    end

    -- ====== 8) 十字闪光（高潮时刻的十字星光） ======
    if progress > 0.3 and progress < 0.8 then
        local flashAlpha = math.sin((progress - 0.3) / 0.5 * math.pi) * alpha
        local flashSize = 30 * sx * flashAlpha
        -- 水平线
        nvgBeginPath(nvg_)
        nvgMoveTo(nvg_, screenX - flashSize, glowCenterY)
        nvgLineTo(nvg_, screenX + flashSize, glowCenterY)
        nvgStrokeColor(nvg_, nvgRGBA(200, 255, 220, math.floor(200 * flashAlpha)))
        nvgStrokeWidth(nvg_, 2 * sx)
        nvgStroke(nvg_)
        -- 垂直线
        nvgBeginPath(nvg_)
        nvgMoveTo(nvg_, screenX, glowCenterY - flashSize)
        nvgLineTo(nvg_, screenX, glowCenterY + flashSize)
        nvgStrokeColor(nvg_, nvgRGBA(200, 255, 220, math.floor(200 * flashAlpha)))
        nvgStrokeWidth(nvg_, 2 * sx)
        nvgStroke(nvg_)
        -- 中心亮点
        nvgBeginPath(nvg_)
        nvgCircle(nvg_, screenX, glowCenterY, 4 * sx * flashAlpha)
        nvgFillColor(nvg_, nvgRGBA(255, 255, 255, math.floor(240 * flashAlpha)))
        nvgFill(nvg_)
    end
end

-- ============================================================================
-- 绘制地面矿脉状冰晶群（华丽爆发特效）
-- ============================================================================
function DrawIceCrystals(width, height, camX, camY)
    local sx = width / SCREEN_WIDTH
    local sy = height / SCREEN_HEIGHT
    local ppu = PIXELS_PER_UNIT

    for _, group in ipairs(iceCrystals_) do
        local t = group.spawnTime
        local fadeOut = math.min(group.life / 0.5, 1.0)  -- 最后0.5秒淡出

        -- 地面裂缝光芒（先于冰晶出现）
        local crackAlpha = math.min(t / 0.15, 1.0) * fadeOut
        if crackAlpha > 0 then
            local groundScreenX, groundScreenY = PhysicsToScreen(
                group.crystals[math.ceil(#group.crystals / 2)].x,
                group.groundY, camX, camY)
            groundScreenX = groundScreenX * sx
            groundScreenY = groundScreenY * sy

            -- 地面裂缝发光线
            local crackLen = (#group.crystals * 0.6) * ppu * sx
            nvgBeginPath(nvg_)
            nvgMoveTo(nvg_, groundScreenX - crackLen * 0.5, groundScreenY)
            nvgLineTo(nvg_, groundScreenX + crackLen * 0.5, groundScreenY)
            nvgStrokeColor(nvg_, nvgRGBA(150, 220, 255, math.floor(180 * crackAlpha * fadeOut)))
            nvgStrokeWidth(nvg_, 2 + group.power * 2)
            nvgStroke(nvg_)

            -- 裂缝扩散光晕
            nvgBeginPath(nvg_)
            nvgEllipse(nvg_, groundScreenX, groundScreenY, crackLen * 0.55, 8 * sy)
            nvgFillColor(nvg_, nvgRGBA(100, 200, 255, math.floor(60 * crackAlpha * fadeOut)))
            nvgFill(nvg_)
        end

        -- 逐个绘制冰晶柱
        for idx, c in ipairs(group.crystals) do
            local elapsed = t - c.delay
            if elapsed > 0 then
                -- 冰晶破土动画：快速升起
                local riseT = math.min(elapsed / 0.3, 1.0)
                -- 弹性缓动
                local eased = riseT < 1.0 and (1.0 - math.cos(riseT * math.pi * 0.5)) or 1.0
                if riseT >= 0.8 then
                    -- 轻微回弹
                    local bounceT = (riseT - 0.8) / 0.2
                    eased = 1.0 + math.sin(bounceT * math.pi) * 0.05
                end

                local currentH = c.height * eased * fadeOut
                local currentW = c.width * (0.8 + riseT * 0.2)

                local baseScreenX, baseScreenY = PhysicsToScreen(c.x, group.groundY, camX, camY)
                baseScreenX = baseScreenX * sx
                baseScreenY = baseScreenY * sy

                local crystalH = currentH * ppu * sy
                local crystalW = currentW * ppu * sx

                nvgSave(nvg_)
                nvgTranslate(nvg_, baseScreenX, baseScreenY)
                nvgRotate(nvg_, c.angle)

                -- 冰晶柱体（多边形，尖顶宽底）
                local topW = crystalW * 0.15
                local midW = crystalW * 0.7
                local botW = crystalW * 1.0

                -- 外层发光
                local glowAlpha = math.floor(50 * fadeOut * group.power)
                nvgBeginPath(nvg_)
                nvgMoveTo(nvg_, 0, -crystalH)
                nvgLineTo(nvg_, midW * 0.8, -crystalH * 0.4)
                nvgLineTo(nvg_, botW * 0.7, 0)
                nvgLineTo(nvg_, -botW * 0.7, 0)
                nvgLineTo(nvg_, -midW * 0.8, -crystalH * 0.4)
                nvgClosePath(nvg_)
                nvgFillColor(nvg_, nvgRGBA(100, 180, 255, glowAlpha))
                nvgFill(nvg_)

                -- 主体冰晶（渐变：底部深蓝 → 顶部亮白）
                nvgBeginPath(nvg_)
                nvgMoveTo(nvg_, 0, -crystalH)
                nvgLineTo(nvg_, topW, -crystalH * 0.85)
                nvgLineTo(nvg_, midW * 0.6, -crystalH * 0.45)
                nvgLineTo(nvg_, botW * 0.5, 0)
                nvgLineTo(nvg_, -botW * 0.5, 0)
                nvgLineTo(nvg_, -midW * 0.6, -crystalH * 0.45)
                nvgLineTo(nvg_, -topW, -crystalH * 0.85)
                nvgClosePath(nvg_)
                local crystGrad = nvgLinearGradient(nvg_, 0, 0, 0, -crystalH,
                    nvgRGBA(40, 100, 180, math.floor(220 * fadeOut)),
                    nvgRGBA(200, 240, 255, math.floor(250 * fadeOut)))
                nvgFillPaint(nvg_, crystGrad)
                nvgFill(nvg_)

                -- 内部高光面（半透明白色，模拟折射）
                nvgBeginPath(nvg_)
                nvgMoveTo(nvg_, -topW * 0.3, -crystalH * 0.9)
                nvgLineTo(nvg_, midW * 0.2, -crystalH * 0.5)
                nvgLineTo(nvg_, botW * 0.15, -crystalH * 0.1)
                nvgLineTo(nvg_, -midW * 0.1, -crystalH * 0.4)
                nvgClosePath(nvg_)
                nvgFillColor(nvg_, nvgRGBA(255, 255, 255, math.floor(80 * fadeOut)))
                nvgFill(nvg_)

                -- 冰晶边缘轮廓
                nvgBeginPath(nvg_)
                nvgMoveTo(nvg_, 0, -crystalH)
                nvgLineTo(nvg_, midW * 0.6, -crystalH * 0.45)
                nvgLineTo(nvg_, botW * 0.5, 0)
                nvgMoveTo(nvg_, 0, -crystalH)
                nvgLineTo(nvg_, -midW * 0.6, -crystalH * 0.45)
                nvgLineTo(nvg_, -botW * 0.5, 0)
                nvgStrokeColor(nvg_, nvgRGBA(180, 230, 255, math.floor(150 * fadeOut)))
                nvgStrokeWidth(nvg_, 1.0)
                nvgStroke(nvg_)

                nvgRestore(nvg_)

                -- 破土粒子（出现瞬间）
                if elapsed < 0.5 then
                    local particleAlpha = (1.0 - elapsed / 0.5) * fadeOut
                    local particleCount = 3 + math.floor(group.power * 3)
                    for pi = 1, particleCount do
                        local pAngle = (pi / particleCount) * math.pi + math.random() * 0.5
                        local pDist = elapsed * ppu * sx * (2 + math.random() * 2)
                        local px = baseScreenX + math.cos(pAngle) * pDist
                        local py = baseScreenY - math.sin(pAngle) * pDist * 0.6
                        local pSize = (1.5 + math.random() * 2) * sx
                        nvgBeginPath(nvg_)
                        -- 小碎冰菱形
                        nvgMoveTo(nvg_, px - pSize, py)
                        nvgLineTo(nvg_, px, py - pSize * 0.7)
                        nvgLineTo(nvg_, px + pSize, py)
                        nvgLineTo(nvg_, px, py + pSize * 0.7)
                        nvgClosePath(nvg_)
                        nvgFillColor(nvg_, nvgRGBA(180, 235, 255, math.floor(180 * particleAlpha)))
                        nvgFill(nvg_)
                    end
                end

                -- 顶部寒气散发（持续的微粒上升）
                if riseT >= 1.0 and fadeOut > 0.3 then
                    local mistCount = 2 + math.floor(group.power * 2)
                    for mi = 1, mistCount do
                        local mPhase = t * 2 + mi * 1.7 + idx * 0.5
                        local mY = baseScreenY - crystalH - (mPhase % 1.0) * 20 * sy
                        local mX = baseScreenX + math.sin(mPhase * 3) * crystalW * 0.8
                        local mAlpha = (1.0 - (mPhase % 1.0)) * fadeOut * 0.6
                        local mSize = (1 + math.sin(mPhase) * 0.5) * sx * 2
                        nvgBeginPath(nvg_)
                        nvgCircle(nvg_, mX, mY, mSize)
                        nvgFillColor(nvg_, nvgRGBA(200, 240, 255, math.floor(100 * mAlpha)))
                        nvgFill(nvg_)
                    end
                end
            end
        end

        -- 地面冰霜扩散环（整体效果）
        if t < 0.8 then
            local ringProgress = t / 0.8
            local centerX = group.crystals[math.ceil(#group.crystals / 2)].x
            local ringScreenX, ringScreenY = PhysicsToScreen(centerX, group.groundY, camX, camY)
            ringScreenX = ringScreenX * sx
            ringScreenY = ringScreenY * sy
            local ringRadius = ringProgress * (#group.crystals * 0.5) * ppu * sx
            local ringAlpha = (1.0 - ringProgress) * fadeOut

            nvgBeginPath(nvg_)
            nvgEllipse(nvg_, ringScreenX, ringScreenY, ringRadius, ringRadius * 0.25)
            nvgStrokeColor(nvg_, nvgRGBA(150, 220, 255, math.floor(150 * ringAlpha)))
            nvgStrokeWidth(nvg_, 2 + group.power * 2)
            nvgStroke(nvg_)
        end
    end
end

-- ============================================================================
-- 绘制玩家（序列帧动画）
-- ============================================================================
function DrawPlayer(width, height, camX, camY)
    if playerNode_ == nil then
        print("[DEBUG] DrawPlayer: playerNode_ is nil!")
        return
    end

    local pos = playerNode_.position2D
    local screenX, screenY = PhysicsToScreen(pos.x, pos.y, camX, camY)

    -- 缩放到实际屏幕尺寸
    local sx = width / SCREEN_WIDTH
    local sy = height / SCREEN_HEIGHT
    screenX = screenX * sx
    screenY = screenY * sy

    -- 玩家渲染尺寸
    local playerDrawSize = PLAYER_RADIUS * 5.5 * PIXELS_PER_UNIT * sx

    -- 选择当前序列帧图片
    local img = imgIdle_
    if currentAnim_ == ANIM_RUN then
        img = imgRun_
    elseif currentAnim_ == ANIM_JUMP then
        img = imgJump_
    elseif currentAnim_ == ANIM_ATTACK then
        img = imgAttack_
    elseif currentAnim_ == ANIM_BLOCK then
        img = imgBlock_
    elseif currentAnim_ == ANIM_CHARGE then
        img = imgCharge_
    elseif currentAnim_ == ANIM_HEAL then
        img = imgHeal_
    elseif currentAnim_ == ANIM_CROUCH then
        img = imgCrouch_
    elseif currentAnim_ == ANIM_CROUCH_WALK then
        img = imgCrouchWalk_
    end

    local frame = animFrame_

    -- 蹲下动画使用帧映射表：animFrame_是索引(1-based)，转为实际帧号(0-based)
    if currentAnim_ == ANIM_CROUCH then
        local idx = math.max(1, math.min(animFrame_, #crouchFrameMap_))
        frame = crouchFrameMap_[idx]
    end

    -- 如果图片加载成功，使用序列帧
    if img ~= nil and img > 0 and imgWidth_ > 0 then
        DrawSpriteFrame(img, frame, screenX, screenY, playerDrawSize, not facingRight_)
    else
        -- fallback: 绘制占位圆形（确保始终可见）
        nvgBeginPath(nvg_)
        nvgCircle(nvg_, screenX, screenY, playerDrawSize / 2)
        nvgFillColor(nvg_, nvgRGBA(100, 180, 255, 255))
        nvgFill(nvg_)

        -- 绘制方向指示
        nvgBeginPath(nvg_)
        local dirX = facingRight_ and (playerDrawSize * 0.4) or (-playerDrawSize * 0.4)
        nvgCircle(nvg_, screenX + dirX, screenY, playerDrawSize * 0.15)
        nvgFillColor(nvg_, nvgRGBA(255, 255, 255, 255))
        nvgFill(nvg_)
    end
end

-- ============================================================================
-- 绘制序列帧中的单帧
-- 4列3行网格, frame 从0开始
-- ============================================================================
-- 每个动画的裁切配置 { cropW, cropH, cropOffX, cropOffY, offsetX, offsetY }
-- offsetX/offsetY 控制绘制位置偏移（与编辑器中的 offset 参数对应）
local animCropConfig_ = {
    [ANIM_IDLE]   = { cropW = 1.0, cropH = 1.0, cropOffX = 0.0, cropOffY = 0.0, offsetX = 0.0, offsetY = 0.6 },
    [ANIM_RUN]    = { cropW = 1.0, cropH = 1.0, cropOffX = 0.0, cropOffY = 0.0, offsetX = 0.0, offsetY = 0.6 },
    [ANIM_JUMP]   = { cropW = 1.0, cropH = 1.0, cropOffX = 0.0, cropOffY = 0.0, offsetX = 0.0, offsetY = 0.6 },
    [ANIM_ATTACK] = { cropW = 1.0, cropH = 1.0, cropOffX = 0.0, cropOffY = 0.0, offsetX = 0.0, offsetY = 0.6 },
    [ANIM_BLOCK]  = { cropW = 1.0, cropH = 1.0, cropOffX = 0.0, cropOffY = 0.0, offsetX = 0.0, offsetY = 0.6 },
    [ANIM_CHARGE] = { cropW = 1.0, cropH = 1.0, cropOffX = 0.0, cropOffY = 0.0, offsetX = 0.0, offsetY = 0.6 },
    [ANIM_HEAL]   = { cropW = 1.0, cropH = 1.0, cropOffX = 0.0, cropOffY = 0.0, offsetX = 0.0, offsetY = 0.6 },
    [ANIM_CROUCH] = { cropW = 1.0, cropH = 1.0, cropOffX = 0.0, cropOffY = 0.0, offsetX = 0.0, offsetY = 0.6 },
    [ANIM_CROUCH_WALK] = { cropW = 1.0, cropH = 1.0, cropOffX = 0.0, cropOffY = 0.0, offsetX = 0.0, offsetY = 0.6, cols = 4, rows = 4 },
}

function DrawSpriteFrame(img, frame, cx, cy, size, flipH)
    -- 获取当前动画的裁切配置（含可能的自定义grid）
    local crop = animCropConfig_[currentAnim_] or { cropW = 1.0, cropH = 1.0, cropOffX = 0.0, cropOffY = 0.0, offsetX = 0.0, offsetY = 0.6 }
    local cols = crop.cols or SPRITE_COLS
    local rows = crop.rows or SPRITE_ROWS

    local col = frame % cols
    local row = math.floor(frame / cols)

    -- 获取图片实际尺寸（蹲走图片可能和其他图片尺寸不同）
    local actualW, actualH = nvgImageSize(nvg_, img)

    -- 每帧的像素尺寸
    local frameW = actualW / cols
    local frameH = actualH / rows

    local srcW = frameW * crop.cropW
    local srcH = frameH * crop.cropH
    local srcOffX = frameW * crop.cropOffX
    local srcOffY = frameH * crop.cropOffY

    -- 绘制区域 - 保持裁切后的宽高比
    local drawW = size
    local drawH = size * (srcH / srcW)
    local oX = crop.offsetX or 0.0
    local oY = crop.offsetY or 0.6
    local drawX = cx - drawW / 2 + oX * drawW
    local drawY = cy - drawH * oY

    nvgSave(nvg_)

    -- 水平翻转
    if flipH then
        nvgTranslate(nvg_, cx, 0)
        nvgScale(nvg_, -1, 1)
        nvgTranslate(nvg_, -cx, 0)
    end

    -- 计算 pattern 参数（将裁切区域映射到绘制区域）
    local patternW = drawW * (actualW / srcW)
    local patternH = drawH * (actualH / srcH)
    local cropLeftInFrame = (frameW - srcW) / 2 + srcOffX
    local cropTopInFrame = (frameH - srcH) / 2 + srcOffY
    local patternX = drawX - (col * frameW + cropLeftInFrame) * (patternW / actualW)
    local patternY = drawY - (row * frameH + cropTopInFrame) * (patternH / actualH)

    local paint = nvgImagePattern(nvg_, patternX, patternY, patternW, patternH, 0, img, 1.0)

    nvgBeginPath(nvg_)
    nvgRect(nvg_, drawX, drawY, drawW, drawH)
    nvgFillPaint(nvg_, paint)
    nvgFill(nvg_)

    nvgRestore(nvg_)
end

-- ============================================================================
-- 绘制 HP/MP 血条和魔力条（左上角）
-- ============================================================================
function DrawHPMPBars(width, height)
    local sx = width / SCREEN_WIDTH
    local sy = height / SCREEN_HEIGHT
    local barX = 16 * sx
    local barY = 16 * sy
    local barW = 200 * sx
    local barH = 18 * sy
    local gap = 8 * sy
    local cornerR = 4 * sx

    -- HP 条背景
    nvgBeginPath(nvg_)
    nvgRoundedRect(nvg_, barX, barY, barW, barH, cornerR)
    nvgFillColor(nvg_, nvgRGBA(30, 30, 30, 200))
    nvgFill(nvg_)

    -- HP 条填充
    local hpRatio = playerHP_ / playerMaxHP_
    if hpRatio > 0 then
        nvgBeginPath(nvg_)
        nvgRoundedRect(nvg_, barX, barY, barW * hpRatio, barH, cornerR)
        local hpGrad = nvgLinearGradient(nvg_, barX, barY, barX, barY + barH,
            nvgRGBA(220, 50, 50, 255), nvgRGBA(160, 20, 20, 255))
        nvgFillPaint(nvg_, hpGrad)
        nvgFill(nvg_)
    end

    -- HP 条边框
    nvgBeginPath(nvg_)
    nvgRoundedRect(nvg_, barX, barY, barW, barH, cornerR)
    nvgStrokeColor(nvg_, nvgRGBA(200, 200, 200, 150))
    nvgStrokeWidth(nvg_, 1.5)
    nvgStroke(nvg_)

    -- HP 文字
    nvgFontFace(nvg_, "sans")
    nvgFontSize(nvg_, 13 * sx)
    nvgFillColor(nvg_, nvgRGBA(255, 255, 255, 240))
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(nvg_, barX + barW / 2, barY + barH / 2, string.format("HP %d/%d", math.floor(playerHP_), math.floor(playerMaxHP_)))

    -- HP 图标（小红心）
    nvgFontSize(nvg_, 16 * sx)
    nvgTextAlign(nvg_, NVG_ALIGN_RIGHT + NVG_ALIGN_MIDDLE)
    nvgFillColor(nvg_, nvgRGBA(255, 80, 80, 255))

    -- MP 条
    local mpY = barY + barH + gap

    -- MP 条背景
    nvgBeginPath(nvg_)
    nvgRoundedRect(nvg_, barX, mpY, barW, barH, cornerR)
    nvgFillColor(nvg_, nvgRGBA(30, 30, 30, 200))
    nvgFill(nvg_)

    -- MP 条填充
    local mpRatio = playerMP_ / playerMaxMP_
    if mpRatio > 0 then
        nvgBeginPath(nvg_)
        nvgRoundedRect(nvg_, barX, mpY, barW * mpRatio, barH, cornerR)
        local mpGrad = nvgLinearGradient(nvg_, barX, mpY, barX, mpY + barH,
            nvgRGBA(60, 130, 255, 255), nvgRGBA(30, 80, 200, 255))
        nvgFillPaint(nvg_, mpGrad)
        nvgFill(nvg_)
    end

    -- MP 条边框
    nvgBeginPath(nvg_)
    nvgRoundedRect(nvg_, barX, mpY, barW, barH, cornerR)
    nvgStrokeColor(nvg_, nvgRGBA(200, 200, 200, 150))
    nvgStrokeWidth(nvg_, 1.5)
    nvgStroke(nvg_)

    -- MP 文字
    nvgFontSize(nvg_, 13 * sx)
    nvgFillColor(nvg_, nvgRGBA(255, 255, 255, 240))
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgText(nvg_, barX + barW / 2, mpY + barH / 2, string.format("MP %d/%d", math.floor(playerMP_), math.floor(playerMaxMP_)))
end

-- ============================================================================
-- 绘制背包面板
-- ============================================================================
function DrawInventoryPanel(width, height)
    local sx = width / SCREEN_WIDTH
    local sy = height / SCREEN_HEIGHT

    -- 面板尺寸和位置（屏幕中央）
    local panelW = 420 * sx
    local panelH = 360 * sy
    local panelX = (width - panelW) / 2
    local panelY = (height - panelH) / 2

    -- 半透明背景
    nvgBeginPath(nvg_)
    nvgRoundedRect(nvg_, panelX, panelY, panelW, panelH, 12 * sx)
    nvgFillColor(nvg_, nvgRGBA(15, 20, 40, 230))
    nvgFill(nvg_)

    -- 边框
    nvgBeginPath(nvg_)
    nvgRoundedRect(nvg_, panelX, panelY, panelW, panelH, 12 * sx)
    nvgStrokeColor(nvg_, nvgRGBA(100, 160, 255, 180))
    nvgStrokeWidth(nvg_, 2)
    nvgStroke(nvg_)

    -- 标题
    nvgFontFace(nvg_, "sans")
    nvgFontSize(nvg_, 20 * sx)
    nvgFillColor(nvg_, nvgRGBA(180, 220, 255, 255))
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgText(nvg_, panelX + panelW / 2, panelY + 12 * sy, "背包 [B]")

    -- 分隔线
    nvgBeginPath(nvg_)
    nvgMoveTo(nvg_, panelX + 16 * sx, panelY + 42 * sy)
    nvgLineTo(nvg_, panelX + panelW - 16 * sx, panelY + 42 * sy)
    nvgStrokeColor(nvg_, nvgRGBA(80, 120, 200, 120))
    nvgStrokeWidth(nvg_, 1)
    nvgStroke(nvg_)

    -- 物品网格
    local gridX = panelX + 20 * sx
    local gridY = panelY + 54 * sy
    local cellSize = 56 * sx
    local cellGap = 8 * sx
    local cols = 5

    -- 空背包提示
    if #inventoryItems_ == 0 then
        nvgFontFace(nvg_, "sans")
        nvgFontSize(nvg_, 16 * sx)
        nvgFillColor(nvg_, nvgRGBA(120, 140, 180, 180))
        nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(nvg_, panelX + panelW / 2, panelY + panelH / 2, "背包空空如也...")
    end

    for idx, item in ipairs(inventoryItems_) do
        local col = (idx - 1) % cols
        local row = math.floor((idx - 1) / cols)
        local cx = gridX + col * (cellSize + cellGap)
        local cy = gridY + row * (cellSize + cellGap + 20 * sy)

        -- 格子背景
        nvgBeginPath(nvg_)
        nvgRoundedRect(nvg_, cx, cy, cellSize, cellSize, 6 * sx)
        nvgFillColor(nvg_, nvgRGBA(40, 50, 80, 200))
        nvgFill(nvg_)
        nvgStrokeColor(nvg_, nvgRGBA(80, 120, 180, 150))
        nvgStrokeWidth(nvg_, 1)
        nvgStroke(nvg_)

        -- 图标（用首字母+颜色区分）
        local iconColors = {
            potion = nvgRGBA(255, 100, 100, 255),
            crystal = nvgRGBA(100, 180, 255, 255),
            heart = nvgRGBA(200, 50, 255, 255),
            shard = nvgRGBA(150, 220, 255, 255),
            cloak = nvgRGBA(100, 200, 150, 255),
            rune = nvgRGBA(255, 200, 80, 255),
        }
        local iconSymbols = {
            potion = "药",
            crystal = "晶",
            heart = "心",
            shard = "碎",
            cloak = "披",
            rune = "符",
        }
        local color = iconColors[item.icon] or nvgRGBA(200, 200, 200, 255)
        nvgFontFace(nvg_, "sans")
        nvgFontSize(nvg_, 22 * sx)
        nvgFillColor(nvg_, color)
        nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(nvg_, cx + cellSize / 2, cy + cellSize / 2, iconSymbols[item.icon] or "?")

        -- 数量角标
        if item.count > 1 then
            nvgFontSize(nvg_, 11 * sx)
            nvgFillColor(nvg_, nvgRGBA(255, 255, 200, 255))
            nvgTextAlign(nvg_, NVG_ALIGN_RIGHT + NVG_ALIGN_BOTTOM)
            nvgText(nvg_, cx + cellSize - 3 * sx, cy + cellSize - 2 * sy, "x" .. item.count)
        end

        -- 物品名称
        nvgFontSize(nvg_, 11 * sx)
        nvgFillColor(nvg_, nvgRGBA(200, 220, 255, 220))
        nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgText(nvg_, cx + cellSize / 2, cy + cellSize + 2 * sy, item.name)
    end

    -- 底部提示
    nvgFontSize(nvg_, 12 * sx)
    nvgFillColor(nvg_, nvgRGBA(150, 170, 200, 180))
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgText(nvg_, panelX + panelW / 2, panelY + panelH - 10 * sy, "按 B 关闭")
end

-- ============================================================================
-- 绘制技能面板
-- ============================================================================
function DrawSkillPanel(width, height)
    local sx = width / SCREEN_WIDTH
    local sy = height / SCREEN_HEIGHT

    -- 面板尺寸和位置（屏幕中央）
    local panelW = 460 * sx
    local panelH = 400 * sy
    local panelX = (width - panelW) / 2
    local panelY = (height - panelH) / 2

    -- 半透明背景
    nvgBeginPath(nvg_)
    nvgRoundedRect(nvg_, panelX, panelY, panelW, panelH, 12 * sx)
    nvgFillColor(nvg_, nvgRGBA(15, 20, 40, 230))
    nvgFill(nvg_)

    -- 边框
    nvgBeginPath(nvg_)
    nvgRoundedRect(nvg_, panelX, panelY, panelW, panelH, 12 * sx)
    nvgStrokeColor(nvg_, nvgRGBA(100, 200, 160, 180))
    nvgStrokeWidth(nvg_, 2)
    nvgStroke(nvg_)

    -- 标题
    nvgFontFace(nvg_, "sans")
    nvgFontSize(nvg_, 20 * sx)
    nvgFillColor(nvg_, nvgRGBA(150, 255, 200, 255))
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgText(nvg_, panelX + panelW / 2, panelY + 12 * sy, "技能 [Z]")

    -- 分隔线
    nvgBeginPath(nvg_)
    nvgMoveTo(nvg_, panelX + 16 * sx, panelY + 42 * sy)
    nvgLineTo(nvg_, panelX + panelW - 16 * sx, panelY + 42 * sy)
    nvgStrokeColor(nvg_, nvgRGBA(80, 180, 140, 120))
    nvgStrokeWidth(nvg_, 1)
    nvgStroke(nvg_)

    -- 鼠标位置
    local mx = input.mousePosition.x
    local my = input.mousePosition.y
    local hoveredSkillIdx = -1

    -- 技能列表
    local listX = panelX + 20 * sx
    local listY = panelY + 54 * sy
    local rowH = 62 * sy

    for idx, skill in ipairs(skillList_) do
        local ry = listY + (idx - 1) * rowH
        local rowW = panelW - 40 * sx
        local rowInnerH = rowH - 6 * sy

        -- 检测鼠标悬停
        local isHovered = (mx >= listX and mx <= listX + rowW and my >= ry and my <= ry + rowInnerH)
        if isHovered then
            hoveredSkillIdx = idx
        end

        -- 技能行背景（悬停高亮）
        nvgBeginPath(nvg_)
        nvgRoundedRect(nvg_, listX, ry, rowW, rowInnerH, 6 * sx)
        if isHovered then
            nvgFillColor(nvg_, nvgRGBA(40, 60, 90, 220))
        else
            nvgFillColor(nvg_, nvgRGBA(30, 40, 60, 180))
        end
        nvgFill(nvg_)

        -- 技能名称
        nvgFontFace(nvg_, "sans")
        nvgFontSize(nvg_, 15 * sx)
        nvgFillColor(nvg_, nvgRGBA(220, 240, 255, 255))
        nvgTextAlign(nvg_, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgText(nvg_, listX + 10 * sx, ry + 6 * sy, skill.name)

        -- 快捷键
        nvgFontSize(nvg_, 12 * sx)
        nvgFillColor(nvg_, nvgRGBA(255, 220, 100, 220))
        nvgTextAlign(nvg_, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        nvgText(nvg_, listX + rowW - 10 * sx, ry + 6 * sy, "[" .. skill.key .. "]")

        -- 等级条
        local lvBarX = listX + 10 * sx
        local lvBarY = ry + 26 * sy
        local lvBarW = 100 * sx
        local lvBarH = 8 * sy
        nvgBeginPath(nvg_)
        nvgRoundedRect(nvg_, lvBarX, lvBarY, lvBarW, lvBarH, 3)
        nvgFillColor(nvg_, nvgRGBA(40, 40, 60, 200))
        nvgFill(nvg_)
        -- 等级填充
        local lvRatio = skill.level / skill.maxLevel
        nvgBeginPath(nvg_)
        nvgRoundedRect(nvg_, lvBarX, lvBarY, lvBarW * lvRatio, lvBarH, 3)
        nvgFillColor(nvg_, nvgRGBA(80, 200, 160, 255))
        nvgFill(nvg_)
        -- 等级文字
        nvgFontSize(nvg_, 10 * sx)
        nvgFillColor(nvg_, nvgRGBA(180, 220, 200, 200))
        nvgTextAlign(nvg_, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        nvgText(nvg_, lvBarX + lvBarW + 8 * sx, lvBarY + lvBarH / 2,
            "Lv." .. skill.level .. "/" .. skill.maxLevel)

        -- 升级数值预览（显示下一级数据）
        if skill.level < skill.maxLevel and skill.levelData then
            local nextLv = skill.level + 1
            local data = skill.levelData[nextLv]
            local previewText = "下一级: "
            if data.dmg then previewText = previewText .. "伤害" .. data.dmg .. " " end
            if data.heal then previewText = previewText .. "回复" .. data.heal .. " " end
            if data.mp and data.mp > 0 then previewText = previewText .. "MP" .. data.mp .. " " end
            if data.mpSec then previewText = previewText .. "MP/s " .. data.mpSec .. " " end
            if data.reduce then previewText = previewText .. "减伤" .. math.floor(data.reduce * 100) .. "% " end
            if data.speed then previewText = previewText .. "速度" .. data.speed .. " " end
            if data.cd then previewText = previewText .. "CD " .. data.cd .. "s" end
            nvgFontSize(nvg_, 10 * sx)
            nvgFillColor(nvg_, nvgRGBA(100, 220, 255, 200))
            nvgTextAlign(nvg_, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgText(nvg_, listX + 10 * sx, ry + 38 * sy, previewText)
        elseif skill.level >= skill.maxLevel then
            nvgFontSize(nvg_, 10 * sx)
            nvgFillColor(nvg_, nvgRGBA(255, 200, 80, 200))
            nvgTextAlign(nvg_, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
            nvgText(nvg_, listX + 10 * sx, ry + 38 * sy, "已满级")
        end

        -- 当前等级数据
        if skill.level > 0 and skill.levelData then
            local curData = skill.levelData[skill.level]
            local curText = ""
            if curData.dmg then curText = curText .. "伤害:" .. curData.dmg .. " " end
            if curData.heal then curText = curText .. "回复:" .. curData.heal .. " " end
            if curData.reduce then curText = curText .. "减伤:" .. math.floor(curData.reduce * 100) .. "% " end
            nvgFontSize(nvg_, 10 * sx)
            nvgFillColor(nvg_, nvgRGBA(180, 200, 160, 180))
            nvgTextAlign(nvg_, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
            nvgText(nvg_, listX + rowW - 10 * sx, ry + 38 * sy, curText)
        end
    end

    -- 悬停浮窗（显示技能详细描述）
    if hoveredSkillIdx > 0 then
        local skill = skillList_[hoveredSkillIdx]
        local tipW = 220 * sx
        local tipH = 60 * sy
        local tipX = mx + 12 * sx
        local tipY = my + 12 * sy
        -- 防止溢出屏幕右侧
        if tipX + tipW > width then tipX = mx - tipW - 8 * sx end
        if tipY + tipH > height then tipY = my - tipH - 8 * sy end

        -- 浮窗背景
        nvgBeginPath(nvg_)
        nvgRoundedRect(nvg_, tipX, tipY, tipW, tipH, 6 * sx)
        nvgFillColor(nvg_, nvgRGBA(10, 15, 30, 240))
        nvgFill(nvg_)
        nvgBeginPath(nvg_)
        nvgRoundedRect(nvg_, tipX, tipY, tipW, tipH, 6 * sx)
        nvgStrokeColor(nvg_, nvgRGBA(120, 200, 255, 180))
        nvgStrokeWidth(nvg_, 1)
        nvgStroke(nvg_)

        -- 技能名
        nvgFontFace(nvg_, "sans")
        nvgFontSize(nvg_, 13 * sx)
        nvgFillColor(nvg_, nvgRGBA(200, 240, 255, 255))
        nvgTextAlign(nvg_, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgText(nvg_, tipX + 8 * sx, tipY + 8 * sy, skill.name .. " [" .. skill.key .. "]")

        -- 技能描述
        nvgFontSize(nvg_, 11 * sx)
        nvgFillColor(nvg_, nvgRGBA(180, 200, 220, 220))
        nvgText(nvg_, tipX + 8 * sx, tipY + 26 * sy, skill.desc)

        -- MP消耗
        if skill.mp > 0 then
            nvgFontSize(nvg_, 10 * sx)
            nvgFillColor(nvg_, nvgRGBA(100, 160, 255, 200))
            nvgText(nvg_, tipX + 8 * sx, tipY + 42 * sy, "消耗: " .. skill.mp .. " MP")
        else
            nvgFontSize(nvg_, 10 * sx)
            nvgFillColor(nvg_, nvgRGBA(100, 200, 100, 200))
            nvgText(nvg_, tipX + 8 * sx, tipY + 42 * sy, "无消耗")
        end
    end

    -- 底部提示
    nvgFontSize(nvg_, 12 * sx)
    nvgFillColor(nvg_, nvgRGBA(150, 200, 180, 180))
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgText(nvg_, panelX + panelW / 2, panelY + panelH - 10 * sy, "按 Z 关闭 | 悬停查看详情")
end

-- ============================================================================
-- 调试信息
-- ============================================================================
function DrawDebugInfo(width, height)
    nvgFontFace(nvg_, "sans")
    nvgFontSize(nvg_, 14)
    nvgFillColor(nvg_, nvgRGBA(255, 255, 0, 255))

    local y = 16
    local lineH = 16

    local posStr = "nil"
    local screenStr = "nil"
    if playerNode_ then
        local pos = playerNode_.position2D
        posStr = string.format("%.1f, %.1f", pos.x, pos.y)

        local camPos = cameraNode_ and cameraNode_.worldPosition or Vector3(0, 0, -10)
        local sx, sy = PhysicsToScreen(pos.x, pos.y, camPos.x, camPos.y)
        sx = sx * (width / SCREEN_WIDTH)
        sy = sy * (height / SCREEN_HEIGHT)
        screenStr = string.format("%.0f, %.0f", sx, sy)
    end

    local texts = {
        "Idle=" .. tostring(imgIdle_) .. " Run=" .. tostring(imgRun_) .. " W=" .. tostring(imgWidth_),
        "Pos=" .. posStr .. " Scr=" .. screenStr,
        "Anim=" .. currentAnim_ .. " F=" .. animFrame_ .. " Gnd=" .. tostring(onGround_),
    }
    for _, t in ipairs(texts) do
        nvgText(nvg_, 10, y, t)
        y = y + lineH
    end

    -- 在屏幕中心画一个红色十字标记，确认渲染管线正常
    nvgBeginPath(nvg_)
    nvgCircle(nvg_, width / 2, height / 2, 5)
    nvgFillColor(nvg_, nvgRGBA(255, 0, 0, 200))
    nvgFill(nvg_)
end

-- ============================================================================
-- 切图编辑器
-- ============================================================================
function DrawSpriteEditor(width, height)
    -- 半透明黑底
    nvgBeginPath(nvg_)
    nvgRect(nvg_, 0, 0, width, height)
    nvgFillColor(nvg_, nvgRGBA(0, 0, 0, 200))
    nvgFill(nvg_)

    -- 获取当前动画的图片
    local animImages = { imgIdle_, imgRun_, imgJump_, imgAttack_, imgBlock_, imgCharge_, imgHeal_, imgCrouch_, imgCrouchWalk_ }
    local img = animImages[editorAnimIdx_]
    local animName = editorAnimNames_[editorAnimIdx_]

    -- 左侧：显示整张序列帧 + 网格线
    local sheetDisplayW = width * 0.45
    local sheetDisplayH = sheetDisplayW * (imgHeight_ / imgWidth_)
    local sheetX = 20
    local sheetY = 60

    if img and img > 0 and imgWidth_ > 0 then
        -- 绘制整张序列帧
        local paint = nvgImagePattern(nvg_, sheetX, sheetY, sheetDisplayW, sheetDisplayH, 0, img, 1.0)
        nvgBeginPath(nvg_)
        nvgRect(nvg_, sheetX, sheetY, sheetDisplayW, sheetDisplayH)
        nvgFillPaint(nvg_, paint)
        nvgFill(nvg_)

        -- 绘制网格线
        nvgStrokeColor(nvg_, nvgRGBA(255, 255, 255, 80))
        nvgStrokeWidth(nvg_, 1)
        local cellW = sheetDisplayW / SPRITE_COLS
        local cellH = sheetDisplayH / SPRITE_ROWS
        for c = 1, SPRITE_COLS - 1 do
            nvgBeginPath(nvg_)
            nvgMoveTo(nvg_, sheetX + c * cellW, sheetY)
            nvgLineTo(nvg_, sheetX + c * cellW, sheetY + sheetDisplayH)
            nvgStroke(nvg_)
        end
        for r = 1, SPRITE_ROWS - 1 do
            nvgBeginPath(nvg_)
            nvgMoveTo(nvg_, sheetX, sheetY + r * cellH)
            nvgLineTo(nvg_, sheetX + sheetDisplayW, sheetY + r * cellH)
            nvgStroke(nvg_)
        end

        -- 高亮当前帧
        local curCol = editorFrame_ % SPRITE_COLS
        local curRow = math.floor(editorFrame_ / SPRITE_COLS)
        nvgBeginPath(nvg_)
        nvgRect(nvg_, sheetX + curCol * cellW, sheetY + curRow * cellH, cellW, cellH)
        nvgStrokeColor(nvg_, nvgRGBA(0, 255, 0, 255))
        nvgStrokeWidth(nvg_, 3)
        nvgStroke(nvg_)
    end

    -- 右侧：单帧预览（使用当前 offset/scale/crop 参数）
    local previewCenterX = width * 0.75
    local previewCenterY = height * 0.4
    local previewSize = PLAYER_RADIUS * editorScale_ * PIXELS_PER_UNIT * (width / SCREEN_WIDTH)

    -- 绘制参考十字线（标记物理中心点）
    nvgStrokeColor(nvg_, nvgRGBA(255, 0, 0, 150))
    nvgStrokeWidth(nvg_, 1)
    nvgBeginPath(nvg_)
    nvgMoveTo(nvg_, previewCenterX - 50, previewCenterY)
    nvgLineTo(nvg_, previewCenterX + 50, previewCenterY)
    nvgStroke(nvg_)
    nvgBeginPath(nvg_)
    nvgMoveTo(nvg_, previewCenterX, previewCenterY - 50)
    nvgLineTo(nvg_, previewCenterX, previewCenterY + 50)
    nvgStroke(nvg_)

    -- 绘制当前帧预览（带裁切参数）
    if img and img > 0 and imgWidth_ > 0 then
        local frameW = imgWidth_ / SPRITE_COLS
        local frameH = imgHeight_ / SPRITE_ROWS

        -- 裁切后的源区域（像素）
        local srcW = frameW * editorCropW_
        local srcH = frameH * editorCropH_
        local srcOffX = frameW * editorCropOffX_
        local srcOffY = frameH * editorCropOffY_

        -- 绘制尺寸（保持裁切后的宽高比）
        local drawW = previewSize
        local drawH = previewSize * (srcH / srcW)
        local drawX = previewCenterX - drawW / 2 + editorOffsetX_ * drawW
        local drawY = previewCenterY - drawH * editorOffsetY_

        -- 计算 pattern：将裁切区域映射到绘制区域
        local col = editorFrame_ % SPRITE_COLS
        local row = math.floor(editorFrame_ / SPRITE_COLS)

        -- pattern 尺寸 = 整张图缩放到裁切后每帧占 drawW x drawH
        local patternW = drawW * (imgWidth_ / srcW)
        local patternH = drawH * (imgHeight_ / srcH)
        -- pattern 起点 = drawX 减去当前帧裁切区域左上角在整图中的偏移
        local cropLeftInFrame = (frameW - srcW) / 2 + srcOffX
        local cropTopInFrame = (frameH - srcH) / 2 + srcOffY
        local patternX = drawX - (col * frameW + cropLeftInFrame) * (patternW / imgWidth_)
        local patternY = drawY - (row * frameH + cropTopInFrame) * (patternH / imgHeight_)

        local paint = nvgImagePattern(nvg_, patternX, patternY, patternW, patternH, 0, img, 1.0)
        nvgBeginPath(nvg_)
        nvgRect(nvg_, drawX, drawY, drawW, drawH)
        nvgFillPaint(nvg_, paint)
        nvgFill(nvg_)

        -- 帧边框
        nvgBeginPath(nvg_)
        nvgRect(nvg_, drawX, drawY, drawW, drawH)
        nvgStrokeColor(nvg_, nvgRGBA(0, 255, 255, 150))
        nvgStrokeWidth(nvg_, 2)
        nvgStroke(nvg_)
    end

    -- 在序列帧上也显示裁切框
    if img and img > 0 and imgWidth_ > 0 then
        local cellW = sheetDisplayW / SPRITE_COLS
        local cellH = sheetDisplayH / SPRITE_ROWS
        local curCol = editorFrame_ % SPRITE_COLS
        local curRow = math.floor(editorFrame_ / SPRITE_COLS)

        local cropRectW = cellW * editorCropW_
        local cropRectH = cellH * editorCropH_
        local cropRectX = sheetX + curCol * cellW + (cellW - cropRectW) / 2 + cellW * editorCropOffX_
        local cropRectY = sheetY + curRow * cellH + (cellH - cropRectH) / 2 + cellH * editorCropOffY_

        nvgBeginPath(nvg_)
        nvgRect(nvg_, cropRectX, cropRectY, cropRectW, cropRectH)
        nvgStrokeColor(nvg_, nvgRGBA(255, 255, 0, 200))
        nvgStrokeWidth(nvg_, 2)
        nvgStroke(nvg_)
    end

    -- 数据面板
    nvgFontFace(nvg_, "sans")
    nvgFontSize(nvg_, 16)

    local dataX = width * 0.55
    local dataY = height * 0.7
    local lineH = 22

    nvgFillColor(nvg_, nvgRGBA(0, 255, 0, 255))
    nvgText(nvg_, dataX, dataY, "=== 切图数据 (发给AI调整) ===")
    dataY = dataY + lineH

    -- 参数列表，当前选中的高亮
    local paramValues = {
        string.format("offsetX: %.2f", editorOffsetX_),
        string.format("offsetY: %.2f", editorOffsetY_),
        string.format("scale: %.1f", editorScale_),
        string.format("cropW: %.2f", editorCropW_),
        string.format("cropH: %.2f", editorCropH_),
        string.format("cropOffX: %.2f", editorCropOffX_),
        string.format("cropOffY: %.2f", editorCropOffY_),
    }
    for i, text in ipairs(paramValues) do
        if i == editorParam_ then
            nvgFillColor(nvg_, nvgRGBA(255, 100, 100, 255))
            nvgText(nvg_, dataX, dataY, "▶ " .. text)
        else
            nvgFillColor(nvg_, nvgRGBA(255, 255, 100, 255))
            nvgText(nvg_, dataX, dataY, "  " .. text)
        end
        dataY = dataY + lineH
    end

    dataY = dataY + 4
    nvgFillColor(nvg_, nvgRGBA(180, 220, 255, 255))
    nvgText(nvg_, dataX, dataY, string.format("动画: %s  帧: %d/%d  网格: %dx%d  图: %dx%d",
        animName, editorFrame_, SPRITE_FRAMES - 1, SPRITE_COLS, SPRITE_ROWS, imgWidth_, imgHeight_))

    -- 操作提示
    nvgFontSize(nvg_, 14)
    nvgFillColor(nvg_, nvgRGBA(180, 180, 180, 255))
    local helpY = 30
    nvgText(nvg_, 20, helpY, "[1]退出  [Q/E]切换动画  [A/D]切换帧  [W/S]选参数  [ [ / ] ]调值(红色项)")
end

-- ============================================================================
-- UI 说明
-- ============================================================================
function CreateInstructions()
    -- 使用简单的文字说明
end
