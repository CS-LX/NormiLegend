-- ============================================================================
-- 冰霜法师 - 平台跳跃游戏
-- 基于 Box2D 物理 + NanoVG 渲染 + 序列帧动画
-- ============================================================================

require "LuaScripts/Utilities/Sample"
require "urhox-libs.UI.GameHUD"
local UI = require("urhox-libs/UI")
local Enemy = require("Enemy")
local BatEnemy = require("BatEnemy")
local CastleEnemies = require("CastleEnemies")
local GMConsole = require("GMConsole")
local WorldMap = require("WorldMap")
local LevelConfig = require("LevelConfig")
local SpriteEditor = require("SpriteEditor")
local Video = require("urhox-libs/Video")

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
local HANG_GRAVITY_SCALE = 0.125  -- 滞空时重力缩放（下落减缓至1/8）

-- 地图边界常量
local MAP_HALF_WIDTH = 30.0       -- 地图半宽（地板从 -30 到 +30）

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
local ANIM_FPS_HIT = 12    -- 受击动画帧率（快速播完）

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
local HIT_STUN_DURATION = 0.1     -- 受击僵直时间（秒）

-- 蹲下动画自定义帧序列（只使用原始12帧中的特定帧）
-- enter阶段: 播放序列索引1~4 (原帧0,1,2,3)
-- loop阶段: 循环序列索引5~6
local crouchFrameMap_ = { 0, 1, 2, 3, 7, 11 }   -- 角色1: loop帧7,11
local crouchFrameMap2_ = { 0, 1, 2, 3, 10, 11 }  -- 角色2: loop帧10,11
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
local ANIM_HIT = "hit"

-- 投射物
local PROJECTILE_SPEED = 10.0
local PROJECTILE_LIFETIME = 3.0

-- ============================================================================
-- 全局变量
-- ============================================================================

-- 标题页面状态
local showTitleScreen_ = true   -- 游戏启动时显示视频标题页面
local titleVideoPlayer_ = nil   -- 标题视频播放器引用
local titleUIRoot_ = nil        -- 标题页面UI根节点
local mapBackButton_ = nil      -- 关卡选择页面左上角返回标题按钮

-- 主菜单状态
local showMainMenu_ = false     -- 主菜单（钢琴花园背景 + 右侧UI）
local mainMenuUIRoot_ = nil     -- 主菜单UI根节点

---@type Scene
local scene_ = nil
---@type Node
local cameraNode_ = nil
local physicsWorld_ = nil
local nvg_ = nil

-- 玩家相关
local playerNode_ = nil
local playerBody_ = nil
local footSensor_ = nil  -- 脚底传感器（地面检测用）
local onGround_ = false
local groundContactCount_ = 0
local facingRight_ = true
local isHanging_ = false  -- 空中滞空状态
local hangCooldown_ = 0   -- 滞空冷却计时器
local HANG_COOLDOWN_TIME = 0.5  -- 滞空冷却时间（秒）
local wingShatterTimer_ = 0  -- 光翼破碎动画计时器（>0 表示正在播放）
local WING_SHATTER_DURATION = 0.35  -- 破碎动画持续时间（秒）

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

-- 角色2吸血buff相关（蝶之加护）
local lifestealBuffTimer_ = 0.0       -- 吸血buff剩余时间
local LIFESTEAL_DURATION = 10.0       -- 吸血buff持续时间（秒）
local LIFESTEAL_RATIO = 0.5           -- 吸血比例（50%）

-- 技能图标
local iconChar1Q_ = nil
local iconChar1E_ = nil
local iconChar2Q_ = nil
local iconChar2E_ = nil

-- 潜行相关
local isCrouching_ = false

-- 受击相关
local isHit_ = false
local hitStunTimer_ = 0.0

-- 角色属性（独立HP/MP）
local charStats_ = {
    [1] = { hp = 150, maxHP = 150, mp = 80, maxMP = 80 },   -- 角色1: 冰法师
    [2] = { hp = 200, maxHP = 200, mp = 100, maxMP = 100 },  -- 角色2: 黑红角娘
}
local playerHP_ = 150        -- 当前血量（运行时指向当前角色）
local playerMaxHP_ = 150     -- 最大血量
local playerMP_ = 80         -- 当前魔力
local playerMaxMP_ = 80      -- 最大魔力
local mpRegenTimer_ = 0.0    -- 魔力回复计时器

-- 背包和技能面板
local showInventory_ = false  -- 背包面板开关
local showSkillPanel_ = false -- 技能面板开关
local skillPanelSelected_ = 1 -- 技能面板当前选中行

-- UI面板引用
local skillPanelUI_ = nil     -- 技能面板UI根节点
local inventoryPanelUI_ = nil -- 背包面板UI根节点
local escPopupUI_ = nil       -- ESC离开确认弹窗UI

-- 技能点系统（每个角色独立）
local skillPoints_ = {
    [1] = 3,  -- 角色1初始技能点
    [2] = 3,  -- 角色2初始技能点
}

-- 背包数据（空背包）
local inventoryItems_ = {}

-- 技能数据（全部0级，含升级数值预览）
local skillList_ = {
    { name = "普通攻击·冰晶术", key = "J", level = 1, maxLevel = 3, desc = "发射冰晶弹，命中造成伤害", cooldown = 0, mp = 0,
      levelData = { {dmg=3,mp=0}, {dmg=4,mp=0}, {dmg=5,mp=0} } },
    { name = "雪崩", key = "Q", level = 1, maxLevel = 3, desc = "蓄力释放冰晶群，命中敌人冰冻2秒", cooldown = 0, mp = 30,
      levelData = { {dmg=10,mp=30}, {dmg=12,mp=30}, {dmg=14,mp=30} } },
    { name = "治愈术", key = "E", level = 1, maxLevel = 3, desc = "消耗魔力回复生命值", cooldown = 3, mp = 20,
      levelData = { {heal=20,mp=20,cd=3}, {heal=25,mp=20,cd=3}, {heal=30,mp=20,cd=3} } },
    { name = "格挡", key = "右键", level = 1, maxLevel = 3, desc = "举盾格挡，减少受到的伤害", cooldown = 0, mp = 5,
      levelData = { {reduce=0.40,mpSec=5}, {reduce=0.45,mpSec=5}, {reduce=0.50,mpSec=5} } },
}

-- 角色2技能列表
local skillList2_ = {
    { name = "普通攻击·镰刀斩", key = "J", level = 1, maxLevel = 3, desc = "近战挥砍，造成伤害", cooldown = 0, mp = 0,
      levelData = { {dmg=5,mp=0}, {dmg=6,mp=0}, {dmg=7,mp=0} } },
    { name = "蝴蝶化身", key = "Q", level = 1, maxLevel = 3, desc = "化蝶突进，路径敌人流血5秒", cooldown = 0, mp = 30,
      levelData = { {dmg=10,mp=30}, {dmg=12,mp=30}, {dmg=14,mp=30} } },
    { name = "蝶之加护", key = "E", level = 1, maxLevel = 3, desc = "消耗20MP回复HP并附加10s吸血buff(50%)", cooldown = 3, mp = 20,
      levelData = { {heal=10,mp=20,cd=3,lifesteal=10}, {heal=15,mp=20,cd=3,lifesteal=10}, {heal=20,mp=20,cd=3,lifesteal=10} } },
    { name = "格挡", key = "右键", level = 1, maxLevel = 3, desc = "镰刀格挡，减少受到的伤害", cooldown = 0, mp = 5,
      levelData = { {reduce=0.40,mpSec=5}, {reduce=0.45,mpSec=5}, {reduce=0.50,mpSec=5} } },
}

-- 技能伤害/消耗常量
local PROJECTILE_DAMAGE = 3       -- 普通攻击·冰晶术命中伤害
local CHARGE_MP_COST = 30         -- 雪崩释放MP消耗
local CHARGE_DAMAGE = 10          -- 雪崩伤害
local CHARGE_FREEZE_DURATION = 2.0  -- 雪崩冰冻持续时间（秒）
local HEAL_MP_COST = 20           -- 治愈术MP消耗
local HEAL_HP_RESTORE = 20        -- 治愈术回复HP
local BLOCK_MP_PER_SEC = 5        -- 格挡每秒MP消耗

-- 角色2（黑红角娘）技能常量
local CHAR2_MELEE_DAMAGE = 5      -- 近战普攻初始伤害（每级+1）
local CHAR2_MELEE_RANGE = 2.0     -- 近战攻击判定范围（米）
local CHAR2_DASH_DAMAGE = 10      -- 蝴蝶突进伤害
local CHAR2_BLEED_DURATION = 5.0  -- 流血持续时间（秒）
local CHAR2_BLEED_DPS = 1         -- 流血每秒伤害
local CHAR2_DASH_MIN_DIST = 3.5   -- 蝴蝶突进最短距离（点按）
local CHAR2_DASH_MAX_DIST = 12.0  -- 蝴蝶突进最远距离（满蓄力）
local CHAR2_DASH_SPEED = 15.0     -- 蝴蝶突进速度（米/秒）

-- 角色2突进状态
local isDashing_ = false           -- 是否正在蝴蝶突进中
local dashTimer_ = 0.0             -- 突进已持续时间
local dashStartX_ = 0.0            -- 突进起始X
local dashDir_ = 1                 -- 突进方向
local dashTargetDist_ = 2.0        -- 本次突进目标距离（由蓄力时间决定）
local dashHitEnemies_ = {}         -- 本次突进已命中的敌人（防重复）

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
local imgHit_ = -1

-- 角色2（黑红角娘）纹理
local img2Idle_ = -1
local img2Run_ = -1
local img2Jump_ = -1
local img2Attack_ = -1
local img2Crouch_ = -1
local img2CrouchWalk_ = -1
local img2Heal_ = -1
local img2Hit_ = -1
local img2Burst_ = -1  -- Q技能爆发（蝴蝶瞬移）
local img2Block_ = -1  -- 格挡（镰刀挡胸+红色护罩）

-- 当前角色 (1=冰法师, 2=黑红角娘)
local currentCharacter_ = 1

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
local pendingMeleeHit_ = nil   -- 角色2近战延迟判定

-- 虚拟控制
local joystick_ = nil
-- UI按钮引用（通过轮询 state.pressed 检测按住状态）
---@type Widget
local btnJump_ = nil
---@type Widget
local btnAttack_ = nil
---@type Widget
local btnCharge_ = nil
---@type Widget
local btnHeal_ = nil
---@type Widget
local btnBlock_ = nil
local jumpButtonTap_ = false     -- 跳跃点按触发（单次消费）
local attackButtonTap_ = false   -- 普通攻击点按触发（单次消费）
local healButtonTap_ = false     -- E技能点按触发（单次消费）
local skillButtonPanel_ = nil    -- 右下角操作按钮面板
local skillPanelCharCache_ = nil -- 技能面板当前缓存的角色（避免重建闪烁）
local charSwitchPanel_ = nil    -- 右侧角色切换面板
local backButton_ = nil  -- 右上角返回按钮
local topButtonBar_ = nil  -- 顶部功能按钮栏
-- 触屏选关支持
local mapTouchPressed_ = false
local mapTouchX_ = 0
local mapTouchY_ = 0

-- 区域平台图片（冰原/森林）
local imgPlatformArea_ = -1
-- 区域地面图片（冰原雪地/森林落叶）
local imgGroundArea_ = -1
-- 多层视差背景（冰原）
---@type {img: integer, factor: number}[]
local parallaxLayers_ = {}

-- 调试
local debugDraw_ = false

-- 关卡内UI隐藏（按X键切换）
local hudHidden_ = false

-- 切图编辑器（状态由 SpriteEditor 模块管理，此处仅保留 editorMode_ 标志）
local editorMode_ = false

-- 每个动画的裁切配置 { cropW, cropH, cropOffX, cropOffY, offsetX, offsetY, scale }
-- 由 SpriteEditor 模块直接读写，DrawPlayer 渲染时使用
-- 角色1（冰法师）独立配置
local animCropConfig1_ = {
    [ANIM_IDLE]   = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 5.5 },
    [ANIM_RUN]    = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75 },
    [ANIM_JUMP]   = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 5.5 },
    [ANIM_ATTACK] = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 6.0 },
    [ANIM_BLOCK]  = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 7.0 },
    [ANIM_CHARGE] = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 6.0 },
    [ANIM_HEAL]   = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 5.5 },
    [ANIM_CROUCH] = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 5.5 },
    [ANIM_CROUCH_WALK] = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 5.5 },
    [ANIM_HIT]    = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 5.5 },
}
-- 角色2（黑红角娘）独立配置
local animCropConfig2_ = {
    [ANIM_IDLE]   = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 6.0 },
    [ANIM_RUN]    = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 6.5 },
    [ANIM_JUMP]   = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 6.5 },
    [ANIM_ATTACK] = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 7.0 },
    [ANIM_BLOCK]  = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 6.0 },
    [ANIM_CHARGE] = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 6.5 },
    [ANIM_HEAL]   = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 5.5 },
    [ANIM_CROUCH] = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 5.5 },
    [ANIM_CROUCH_WALK] = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 4.5 },
    [ANIM_HIT]    = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 5.5 },
}
-- 当前角色的配置引用（根据 currentCharacter_ 动态切换）
local function GetCurrentAnimCropConfig()
    if currentCharacter_ == 2 then return animCropConfig2_ end
    return animCropConfig1_
end

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

    -- 初始化UI系统（用于技能面板和背包面板）
    UI.Init({
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })
    CreateSkillPanelUI()
    CreateInventoryPanelUI()
    -- 初始化序列帧编辑器（UI形式）
    SpriteEditor.Init({
        getAnimCropConfig = function(charIdx)
            if charIdx == 2 then return animCropConfig2_ end
            return animCropConfig1_
        end,
        getAnimImages = function(charIdx)
            if charIdx == 2 then
                return { img2Idle_, img2Run_, img2Jump_, img2Attack_, img2Block_, img2Burst_, img2Heal_, img2Crouch_, img2CrouchWalk_, img2Hit_ }
            else
                return { imgIdle_, imgRun_, imgJump_, imgAttack_, imgBlock_, imgCharge_, imgHeal_, imgCrouch_, imgCrouchWalk_, imgHit_ }
            end
        end,
        getNvg = function() return nvg_ end,
        getImgSize = function() return imgWidth_, imgHeight_ end,
        getCurrentChar = function() return currentCharacter_ end,
        -- 敌人图片回调
        getEnemyImages = function(typeKey)
            if typeKey == "bat" then
                return BatEnemy.GetImages()
            elseif typeKey == "stixia" then
                return Enemy.GetImages()
            else
                -- 古堡敌人: wolf, wyvern, skeleton, ghost, gargoyle
                return CastleEnemies.GetImages(typeKey)
            end
        end,
        getEnemyImgSize = function(typeKey)
            if typeKey == "bat" then
                return BatEnemy.GetImageSize()
            elseif typeKey == "stixia" then
                return Enemy.GetImageSize()
            else
                return CastleEnemies.GetImageSize(typeKey)
            end
        end,
        -- 敌人grid特殊配置覆盖
        enemyGridOverrides = {
            stixia = { cols = 2, rows = 2, frames = 4 },
        },
        spriteCols = SPRITE_COLS,
        spriteRows = SPRITE_ROWS,
        spriteFrames = SPRITE_FRAMES,
        playerRadius = PLAYER_RADIUS,
        pixelsPerUnit = PIXELS_PER_UNIT,
        screenWidth = SCREEN_WIDTH,
    })
    -- 右上角返回按钮（关卡内显示，效果等同ESC）
    backButton_ = UI.Button {
        text = "✕", fontSize = 18,
        width = 36, height = 36,
        position = "absolute",
        top = 10, right = 10,
        backgroundColor = "rgba(0,0,0,0.5)",
        color = "#ffffff",
        borderRadius = 18,
        borderWidth = 1,
        borderColor = "rgba(255,255,255,0.3)",
        onClick = function()
            if not WorldMap.IsOnMap() and not WorldMap.IsEscPopup() then
                WorldMap.ShowEscPopup()
                ShowEscPopupUI()
            end
        end,
    }

    -- 顶部功能按钮栏（右上角：背包/技能面板/控制台）
    topButtonBar_ = UI.Panel {
        position = "absolute",
        top = 10, right = 52,
        flexDirection = "row",
        gap = 8,
        pointerEvents = "box-none",
        children = {
            UI.Button {
                text = "背包", fontSize = 12, width = 56, height = 34,
                backgroundColor = "rgba(0,0,0,0.6)", color = "#ffffff",
                borderRadius = 8, borderWidth = 1, borderColor = "rgba(255,255,255,0.3)",
                onClick = function() ToggleInventoryPanel() end,
            },
            UI.Button {
                text = "技能", fontSize = 12, width = 56, height = 34,
                backgroundColor = "rgba(0,0,0,0.6)", color = "#ffffff",
                borderRadius = 8, borderWidth = 1, borderColor = "rgba(255,255,255,0.3)",
                onClick = function() ToggleSkillPanel() end,
            },
            UI.Button {
                text = "控制台", fontSize = 11, width = 56, height = 34,
                backgroundColor = "rgba(0,0,0,0.6)", color = "#ffffff",
                borderRadius = 8, borderWidth = 1, borderColor = "rgba(255,255,255,0.3)",
                onClick = function() GMConsole.Toggle() end,
            },
            UI.Button {
                text = "序列帧", fontSize = 11, width = 56, height = 34,
                backgroundColor = "rgba(0,0,0,0.6)", color = "#ffffff",
                borderRadius = 8, borderWidth = 1, borderColor = "rgba(255,255,255,0.3)",
                onClick = function()
                    SpriteEditor.Toggle()
                    editorMode_ = SpriteEditor.IsVisible()
                end,
            },
        }
    }

    -- ESC离开确认弹窗（UI系统，支持触屏）
    escPopupUI_ = UI.Panel {
        id = "escPopupRoot",
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 150 },
        justifyContent = "center",
        alignItems = "center",
        children = {
            UI.Panel {
                width = 300,
                backgroundColor = { 30, 30, 50, 240 },
                borderRadius = 12,
                borderWidth = 2,
                borderColor = { 180, 160, 120, 200 },
                padding = 20,
                alignItems = "center",
                children = {
                    UI.Label { text = "是否离开当前区域？", fontSize = 18, fontColor = { 255, 240, 200, 255 }, marginBottom = 8 },
                    UI.Label { id = "escAreaName", text = "", fontSize = 14, fontColor = { 180, 180, 200, 200 }, marginBottom = 20 },
                    UI.Panel {
                        flexDirection = "row",
                        gap = 24,
                        children = {
                            UI.Button {
                                text = "是，离开", fontSize = 15, width = 110, height = 40,
                                backgroundColor = { 60, 160, 80, 220 }, color = "#ffffff",
                                borderRadius = 8, borderWidth = 1.5, borderColor = { 100, 220, 120, 200 },
                                onClick = function()
                                    escPopupUI_:Hide()
                                    WorldMap.CloseEscPopup()
                                    WorldMap.LeaveToMap()
                                    Enemy.Clear()
                                    BatEnemy.Clear()
                                    CastleEnemies.Clear()
                                end,
                            },
                            UI.Button {
                                text = "否，继续", fontSize = 15, width = 110, height = 40,
                                backgroundColor = { 120, 60, 60, 220 }, color = "#ffffff",
                                borderRadius = 8, borderWidth = 1.5, borderColor = { 200, 100, 100, 200 },
                                onClick = function()
                                    escPopupUI_:Hide()
                                    WorldMap.CloseEscPopup()
                                end,
                            },
                        }
                    },
                }
            }
        }
    }
    escPopupUI_:Hide()

    -- 左上角"返回标题"按钮（仅在关卡选择页面显示）
    mapBackButton_ = UI.Button {
        text = "← 返回", fontSize = 14,
        width = 72, height = 34,
        position = "absolute",
        top = 10, left = 10,
        backgroundColor = "rgba(0,0,0,0.6)",
        color = "#ffffff",
        borderRadius = 8,
        borderWidth = 1,
        borderColor = "rgba(255,255,255,0.3)",
        onClick = function()
            ShowMainMenu()
        end,
    }

    -- 右侧角色切换面板（显示非当前角色的头像，点击切换）
    charSwitchPanel_ = UI.Panel {
        id = "charSwitchPanel",
        position = "absolute",
        right = 12, top = 80,
        pointerEvents = "box-none",
        alignItems = "center",
        gap = 10,
        children = {}
    }
    RefreshCharSwitchPanel_()

    -- 建立共享根节点（所有UI面板用absolute定位覆盖全屏）
    local uiRoot = UI.Panel {
        width = "100%", height = "100%",
        pointerEvents = "box-none",
        children = { backButton_, topButtonBar_, mapBackButton_, skillButtonPanel_, charSwitchPanel_, skillPanelUI_, inventoryPanelUI_, escPopupUI_, SpriteEditor.GetPanel() }
    }
    UI.SetRoot(uiRoot)

    -- 订阅事件
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("PostUpdate", "HandlePostUpdate")
    SubscribeToEvent(nvg_, "NanoVGRender", "HandleRender")
    SubscribeToEvent("PhysicsBeginContact2D", "HandlePhysicsBeginContact")
    SubscribeToEvent("PhysicsEndContact2D", "HandlePhysicsEndContact")
    SubscribeToEvent("TouchBegin", "HandleTouchBegin")

    -- 初始化敌人系统
    Enemy.Init(nvg_)
    BatEnemy.Init(nvg_)
    CastleEnemies.Init(nvg_)

    -- 初始化大地图系统（默认显示大地图）
    WorldMap.Init(nvg_)

    -- 初始化GM控制台（增强版：分角色参数 + 技能调整 + 渲染 + 导出）
    GMConsole.Init(nvg_, {
        refillHP = function() playerHP_ = playerMaxHP_; charStats_[currentCharacter_].hp = playerHP_ end,
        refillMP = function() playerMP_ = playerMaxMP_; charStats_[currentCharacter_].mp = playerMP_ end,
        -- 角色1参数
        c1_maxHP_get = function() return charStats_[1].maxHP end,
        c1_maxHP_set = function(v) charStats_[1].maxHP = v; charStats_[1].hp = math.min(charStats_[1].hp, v); if currentCharacter_ == 1 then playerMaxHP_ = v; playerHP_ = math.min(playerHP_, v) end end,
        c1_maxMP_get = function() return charStats_[1].maxMP end,
        c1_maxMP_set = function(v) charStats_[1].maxMP = v; charStats_[1].mp = math.min(charStats_[1].mp, v); if currentCharacter_ == 1 then playerMaxMP_ = v; playerMP_ = math.min(playerMP_, v) end end,
        c1_projDmg_get = function() return PROJECTILE_DAMAGE end,
        c1_projDmg_set = function(v) PROJECTILE_DAMAGE = v end,
        c1_projSpeed_get = function() return PROJECTILE_SPEED end,
        c1_projSpeed_set = function(v) PROJECTILE_SPEED = v end,
        c1_projLife_get = function() return PROJECTILE_LIFETIME end,
        c1_projLife_set = function(v) PROJECTILE_LIFETIME = v end,
        c1_chargeDmg_get = function() return CHARGE_DAMAGE end,
        c1_chargeDmg_set = function(v) CHARGE_DAMAGE = v end,
        c1_chargeMP_get = function() return CHARGE_MP_COST end,
        c1_chargeMP_set = function(v) CHARGE_MP_COST = v end,
        c1_freezeDur_get = function() return CHARGE_FREEZE_DURATION end,
        c1_freezeDur_set = function(v) CHARGE_FREEZE_DURATION = v end,
        c1_healHP_get = function() return HEAL_HP_RESTORE end,
        c1_healHP_set = function(v) HEAL_HP_RESTORE = v end,
        c1_healMP_get = function() return HEAL_MP_COST end,
        c1_healMP_set = function(v) HEAL_MP_COST = v end,
        c1_healCD_get = function() return HEAL_COOLDOWN end,
        c1_healCD_set = function(v) HEAL_COOLDOWN = v end,
        c1_blockMP_get = function() return BLOCK_MP_PER_SEC end,
        c1_blockMP_set = function(v) BLOCK_MP_PER_SEC = v end,
        -- 角色2参数
        c2_maxHP_get = function() return charStats_[2].maxHP end,
        c2_maxHP_set = function(v) charStats_[2].maxHP = v; charStats_[2].hp = math.min(charStats_[2].hp, v); if currentCharacter_ == 2 then playerMaxHP_ = v; playerHP_ = math.min(playerHP_, v) end end,
        c2_maxMP_get = function() return charStats_[2].maxMP end,
        c2_maxMP_set = function(v) charStats_[2].maxMP = v; charStats_[2].mp = math.min(charStats_[2].mp, v); if currentCharacter_ == 2 then playerMaxMP_ = v; playerMP_ = math.min(playerMP_, v) end end,
        c2_meleeDmg_get = function() return CHAR2_MELEE_DAMAGE end,
        c2_meleeDmg_set = function(v) CHAR2_MELEE_DAMAGE = v end,
        c2_meleeRange_get = function() return CHAR2_MELEE_RANGE end,
        c2_meleeRange_set = function(v) CHAR2_MELEE_RANGE = v end,
        c2_dashDmg_get = function() return CHAR2_DASH_DAMAGE end,
        c2_dashDmg_set = function(v) CHAR2_DASH_DAMAGE = v end,
        c2_dashMP_get = function() return CHARGE_MP_COST end,
        c2_dashMP_set = function(v) CHARGE_MP_COST = v end,
        c2_dashSpeed_get = function() return CHAR2_DASH_SPEED end,
        c2_dashSpeed_set = function(v) CHAR2_DASH_SPEED = v end,
        c2_bleedDur_get = function() return CHAR2_BLEED_DURATION end,
        c2_bleedDur_set = function(v) CHAR2_BLEED_DURATION = v end,
        c2_bleedDPS_get = function() return CHAR2_BLEED_DPS end,
        c2_bleedDPS_set = function(v) CHAR2_BLEED_DPS = v end,
        c2_healHP_get = function() return 10 + (skillList2_[3].level - 1) * 5 end,
        c2_healHP_set = function(v) end,  -- 蝶之加护回复由等级决定，仅显示
        c2_healMP_get = function() return HEAL_MP_COST end,
        c2_healMP_set = function(v) HEAL_MP_COST = v end,
        c2_healCD_get = function() return HEAL_COOLDOWN end,
        c2_healCD_set = function(v) HEAL_COOLDOWN = v end,
        c2_lifestealDur_get = function() return LIFESTEAL_DURATION end,
        c2_lifestealDur_set = function(v) LIFESTEAL_DURATION = v end,
        c2_lifestealPct_get = function() return LIFESTEAL_RATIO * 100 end,
        c2_lifestealPct_set = function(v) LIFESTEAL_RATIO = v / 100 end,
        c2_blockMP_get = function() return BLOCK_MP_PER_SEC end,
        c2_blockMP_set = function(v) BLOCK_MP_PER_SEC = v end,
        -- 渲染参数
        r_pixelsPerUnit_get = function() return PIXELS_PER_UNIT end,
        r_pixelsPerUnit_set = function(v) PIXELS_PER_UNIT = v end,
        r_screenW_get = function() return SCREEN_WIDTH end,
        r_screenW_set = function(v) SCREEN_WIDTH = v end,
        r_screenH_get = function() return SCREEN_HEIGHT end,
        r_screenH_set = function(v) SCREEN_HEIGHT = v end,
        -- 序列帧配置回调（供GM控制台读写）
        getAnimCropConfig1 = function() return animCropConfig1_ end,
        getAnimCropConfig2 = function() return animCropConfig2_ end,
    })

    -- 创建GM控制台UI面板并挂载到根节点
    local gmPanel, gmExportPanel = GMConsole.CreateUI()
    if gmPanel then uiRoot:AddChild(gmPanel) end
    if gmExportPanel then uiRoot:AddChild(gmExportPanel) end

    -- ========== 标题视频页面 ==========
    -- 游戏启动时显示循环播放的视频标题页面，点击/触屏后进入关卡选择
    ShowTitleScreen()

    print("=== 冰霜法师 - 平台跳跃游戏 ===")
    print("方向键/WASD移动, 空格/K跳跃, J/鼠标左键施法, 鼠标右键/L格挡")
    print("数字键0 打开GM控制台")
end

function Stop()
    GameHUD.Shutdown()
    UI.Shutdown()
    if nvg_ ~= nil then
        nvgDelete(nvg_)
    end
end

-- ============================================================================
-- 标题视频页面
-- ============================================================================
function ShowTitleScreen()
    showTitleScreen_ = true

    -- 创建视频播放器（全屏循环播放，提前回跳 + 原生loop双保险避免黑帧）
    titleVideoPlayer_ = Video.VideoPlayer {
        src = "video/终.mp4",
        width = "100%",
        height = "100%",
        textureWidth = 1920,
        textureHeight = 1080,
        autoPlay = true,
        loop = true,   -- 原生loop兜底
        muted = false,
        objectFit = "cover",
        backgroundColor = {0, 0, 0, 255},
        onTimeUpdate = function(self, currentTime, duration)
            -- 距离结尾 0.6 秒时提前回跳（onTimeUpdate ~250ms触发一次，留足余量）
            if duration > 1 and (duration - currentTime) < 0.6 then
                self:Seek(0)
            end
        end,
    }

    -- 提示文本
    local hintLabel = UI.Label {
        id = "titleHint",
        text = "触摸屏幕开始游戏",
        fontSize = 20,
        fontColor = {255, 255, 255, 200},
        textAlign = "center",
    }

    -- 创建标题页UI根（覆盖全屏）
    -- 底层放一张静态海报图兜底，万一视频瞬间空帧不会显示黑屏
    titleUIRoot_ = UI.Panel {
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = {0, 0, 0, 255},
        children = {
            -- 静态海报兜底层（视频闪烁时显示海报而非黑屏）
            UI.Panel {
                position = "absolute",
                top = 0, left = 0,
                width = "100%", height = "100%",
                backgroundImage = "image/ice_mage_poster_20260602130332.png",
                backgroundFit = "cover",
            },
            -- 视频层（覆盖在海报上方）
            UI.Panel {
                position = "absolute",
                top = 0, left = 0,
                width = "100%", height = "100%",
                children = { titleVideoPlayer_ },
            },
            -- 点击遮罩层（透明，接收点击/触摸事件）
            UI.Panel {
                position = "absolute",
                top = 0, left = 0,
                width = "100%", height = "100%",
                justifyContent = "flex-end",
                alignItems = "center",
                paddingBottom = 60,
                onClick = function()
                    DismissTitleScreen()
                end,
                children = {
                    hintLabel,
                }
            }
        }
    }
    UI.SetRoot(titleUIRoot_)
end

function DismissTitleScreen()
    if not showTitleScreen_ then return end
    showTitleScreen_ = false

    -- 销毁视频播放器释放资源
    if titleVideoPlayer_ then
        titleVideoPlayer_:Destroy()
        titleVideoPlayer_ = nil
    end
    titleUIRoot_ = nil

    -- 进入主菜单（非直接进入关卡选择）
    ShowMainMenu()
end

-- ============================================================================
-- 主菜单界面（钢琴花园背景 + 右侧功能按钮面板）
-- ============================================================================
function ShowMainMenu()
    showMainMenu_ = true

    -- 按钮样式工厂 —— 紫藤/自然主题配色
    local function MenuBtn(opts)
        local baseColor = opts.color or "rgba(120, 80, 160, 0.55)"
        local hoverColor = opts.hoverColor or "rgba(150, 100, 190, 0.75)"
        return UI.Button {
            text = opts.text,
            fontSize = opts.fontSize or 18,
            fontColor = "#f0e8ff",
            width = opts.width or "100%",
            height = opts.height or 64,
            backgroundColor = baseColor,
            borderRadius = 12,
            borderWidth = 1,
            borderColor = "rgba(200, 170, 240, 0.6)",
            justifyContent = "center",
            alignItems = "center",
            hoverBackgroundColor = hoverColor,
            onClick = opts.onClick,
        }
    end

    -- 主菜单UI
    mainMenuUIRoot_ = UI.Panel {
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        children = {
            -- 背景图层
            UI.Panel {
                position = "absolute",
                top = 0, left = 0,
                width = "100%", height = "100%",
                backgroundImage = "image/piano_garden_bg.png",
                backgroundFit = "cover",
            },
            -- 右侧菜单面板（带半透明磨砂底色）
            UI.Panel {
                position = "absolute",
                top = 0, right = 0,
                width = "42%", height = "100%",
                paddingTop = 20, paddingBottom = 20,
                paddingLeft = 16, paddingRight = 16,
                backgroundColor = "rgba(40, 20, 60, 0.35)",
                justifyContent = "center",
                alignItems = "stretch",
                gap = 12,
                children = {
                    -- 关卡（大按钮，占顶部）
                    MenuBtn {
                        text = "关  卡",
                        fontSize = 22,
                        height = 90,
                        color = "rgba(100, 60, 150, 0.6)",
                        hoverColor = "rgba(130, 80, 180, 0.8)",
                        onClick = function()
                            EnterGameFromMenu()
                        end,
                    },
                    -- 下方两列布局
                    UI.Panel {
                        width = "100%",
                        flexGrow = 1,
                        flexDirection = "row",
                        gap = 12,
                        children = {
                            -- 左列：背包（高）
                            UI.Panel {
                                width = "45%", height = "100%",
                                children = {
                                    MenuBtn {
                                        text = "背  包",
                                        height = "100%",
                                        color = "rgba(80, 100, 140, 0.55)",
                                        hoverColor = "rgba(100, 120, 170, 0.75)",
                                        onClick = function() end,
                                    },
                                },
                            },
                            -- 右列：任务 / 商店 / 炼药+炼金+仓库
                            UI.Panel {
                                width = "55%", height = "100%",
                                gap = 10,
                                children = {
                                    MenuBtn {
                                        text = "任  务",
                                        height = 56,
                                        color = "rgba(60, 120, 100, 0.55)",
                                        hoverColor = "rgba(80, 150, 120, 0.75)",
                                        onClick = function() end,
                                    },
                                    MenuBtn {
                                        text = "商  店",
                                        height = 56,
                                        color = "rgba(140, 90, 60, 0.55)",
                                        hoverColor = "rgba(170, 110, 80, 0.75)",
                                        onClick = function() end,
                                    },
                                    -- 底部三格横排
                                    UI.Panel {
                                        width = "100%",
                                        flexGrow = 1,
                                        flexDirection = "row",
                                        gap = 8,
                                        children = {
                                            MenuBtn {
                                                text = "炼药",
                                                fontSize = 15,
                                                width = "34%",
                                                height = "100%",
                                                color = "rgba(100, 60, 120, 0.55)",
                                                hoverColor = "rgba(130, 80, 150, 0.75)",
                                                onClick = function() end,
                                            },
                                            MenuBtn {
                                                text = "炼金",
                                                fontSize = 15,
                                                width = "33%",
                                                height = "100%",
                                                color = "rgba(160, 120, 60, 0.55)",
                                                hoverColor = "rgba(190, 150, 80, 0.75)",
                                                onClick = function() end,
                                            },
                                            MenuBtn {
                                                text = "仓库",
                                                fontSize = 15,
                                                width = "33%",
                                                height = "100%",
                                                color = "rgba(60, 90, 130, 0.55)",
                                                hoverColor = "rgba(80, 110, 160, 0.75)",
                                                onClick = function() end,
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    }
    UI.SetRoot(mainMenuUIRoot_)
end

-- 从主菜单进入关卡选择（游戏主界面）
function EnterGameFromMenu()
    showMainMenu_ = false
    mainMenuUIRoot_ = nil

    -- 切换回游戏UI根
    local uiRoot = UI.Panel {
        width = "100%", height = "100%",
        pointerEvents = "box-none",
        children = { backButton_, topButtonBar_, mapBackButton_, skillButtonPanel_, charSwitchPanel_, skillPanelUI_, inventoryPanelUI_, escPopupUI_, SpriteEditor.GetPanel() }
    }
    UI.SetRoot(uiRoot)

    -- 重新挂载GM控制台面板
    local gmPanel, gmExportPanel = GMConsole.CreateUI()
    if gmPanel then uiRoot:AddChild(gmPanel) end
    if gmExportPanel then uiRoot:AddChild(gmExportPanel) end
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
    imgCrouch_ = nvgCreateImage(nvg_, "image/char1_crouch_12f_20260601.png", flags)
    imgCrouchWalk_ = nvgCreateImage(nvg_, "image/crouch_walk_12f_20260531011542.png", flags)
    imgHit_ = nvgCreateImage(nvg_, "image/hit_12f_20260531035941.png", flags)

    -- 角色2（黑红角娘）序列帧 (v2: 3行4列12帧，参考三视图+武器生成)
    img2Idle_ = nvgCreateImage(nvg_, "image/char2_idle_front_12f_20260531082747.png", flags)
    img2Run_ = nvgCreateImage(nvg_, "image/char2_run_12f_v2_20260531081912.png", flags)
    img2Jump_ = nvgCreateImage(nvg_, "image/char2_jump_12f_v2_20260531081921.png", flags)
    img2Attack_ = nvgCreateImage(nvg_, "image/char2_attack_12f_v2_20260531081918.png", flags)
    img2Crouch_ = nvgCreateImage(nvg_, "image/char2_crouch_12f_v2_20260531082008.png", flags)
    img2CrouchWalk_ = nvgCreateImage(nvg_, "image/char2_crouchwalk_12f_v2_20260531082007.png", flags)
    img2Heal_ = nvgCreateImage(nvg_, "image/char2_heal_12f_v2_20260531082018.png", flags)
    img2Hit_ = nvgCreateImage(nvg_, "image/char2_hit_12f_v2_20260531082050.png", flags)
    img2Burst_ = nvgCreateImage(nvg_, "image/char2_qburst_12f_v2_20260531082012.png", flags)
    img2Block_ = nvgCreateImage(nvg_, "image/char2_block_12f_20260531085931.png", flags)

    -- 角色头像
    imgAvatar1_ = nvgCreateImage(nvg_, "image/avatar_char1_20260602072030.png", 0)
    imgAvatar2_ = nvgCreateImage(nvg_, "image/avatar_char2_20260602072055.png", 0)

    -- 技能图标
    iconChar1Q_ = nvgCreateImage(nvg_, "image/icon_char1_q_20260601092553.png", 0)
    iconChar1E_ = nvgCreateImage(nvg_, "image/icon_char1_e_20260601092600.png", 0)
    iconChar2Q_ = nvgCreateImage(nvg_, "image/icon_char2_q_20260601092556.png", 0)
    iconChar2E_ = nvgCreateImage(nvg_, "image/icon_char2_e_20260601092552.png", 0)

    -- 背景图片（华丽古堡无平台）
    imgBackground_ = nvgCreateImage(nvg_, "image/华丽古堡背景无平台_20260531064643.png", 0)

    -- 光翼特效已改为NanoVG纯几何绘制，无需图片

    print("[LOAD] Image handles: idle=" .. tostring(imgIdle_) .. " run=" .. tostring(imgRun_) .. " jump=" .. tostring(imgJump_) .. " attack=" .. tostring(imgAttack_) .. " block=" .. tostring(imgBlock_) .. " charge=" .. tostring(imgCharge_) .. " heal=" .. tostring(imgHeal_) .. " crouch=" .. tostring(imgCrouch_) .. " hit=" .. tostring(imgHit_))

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
    groundShape:SetSize(MAP_HALF_WIDTH * 2, 1)
    groundShape.friction = 0.3
    groundShape.restitution = 0.0
    groundShape.categoryBits = 1

    table.insert(platforms_, { x = 0, y = -4.0, width = MAP_HALF_WIDTH * 2, height = 1 })

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
-- 加载区域关卡（切换区域时调用）
-- ============================================================================
function LoadArea(areaId)
    local config = LevelConfig.GetArea(areaId)
    if not config then return end

    -- 清除现有敌人
    Enemy.Clear()
    BatEnemy.Clear()
    CastleEnemies.Clear()

    -- 清除现有物理平台节点（除了玩家）
    local toRemove = {}
    for _, child in ipairs(scene_:GetChildren()) do
        if child.name == "Ground" or child.name:find("Platform", 1, true) then
            table.insert(toRemove, child)
        end
    end
    for _, node in ipairs(toRemove) do
        node:Remove()
    end
    platforms_ = {}

    -- 加载背景图片
    if config.background then
        imgBackground_ = nvgCreateImage(nvg_, config.background, 0)
    end

    -- 加载多层视差背景（冰原）
    parallaxLayers_ = {}
    if config.parallaxLayers then
        for _, layer in ipairs(config.parallaxLayers) do
            local img = nvgCreateImage(nvg_, layer.image, 0)
            if img and img > 0 then
                table.insert(parallaxLayers_, { img = img, factor = layer.factor })
            end
        end
    end

    -- 加载平台图片（如果有）
    if config.platformImage then
        imgPlatformArea_ = nvgCreateImage(nvg_, config.platformImage, NVG_IMAGE_NEAREST or 32)
    else
        imgPlatformArea_ = -1
    end

    -- 加载地面图片（如果有）
    if config.groundImage then
        imgGroundArea_ = nvgCreateImage(nvg_, config.groundImage, 0)
    else
        imgGroundArea_ = -1
    end

    -- 创建地面
    local groundNode = scene_:CreateChild("Ground")
    groundNode:SetPosition2D(0, config.groundY)
    local groundBody = groundNode:CreateComponent("RigidBody2D")
    groundBody.bodyType = BT_STATIC
    local groundShape = groundNode:CreateComponent("CollisionBox2D")
    groundShape:SetSize(config.groundWidth, 1)
    groundShape.friction = 0.3
    groundShape.restitution = 0.0
    groundShape.categoryBits = 1
    table.insert(platforms_, { x = 0, y = config.groundY, width = config.groundWidth, height = 1 })

    -- 创建浮空平台
    for _, data in ipairs(config.platforms) do
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

    -- 不再在进入关卡时自动刷新敌人（由GM控制台手动生成）

    -- 重置玩家位置
    if playerNode_ then
        playerNode_:SetPosition2D(0, 0)
        playerBody_.linearVelocity = Vector2(0, 0)
    end

    -- 进入关卡状态
    WorldMap.EnterArea(areaId)
    print("[WORLD] 进入区域: " .. (config.name or areaId))
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

    -- 脚底传感器（用于地面检测）
    footSensor_ = playerNode_:CreateComponent("CollisionCircle2D")
    footSensor_.radius = PLAYER_RADIUS * 0.7
    footSensor_.center = Vector2(0, -PLAYER_RADIUS * 0.9)
    footSensor_.trigger = true
    footSensor_.categoryBits = 4
    footSensor_.maskBits = 1
end

-- ============================================================================
-- 虚拟控制
-- ============================================================================

--- 刷新右侧角色切换面板（只显示非当前角色）
function RefreshCharSwitchPanel_()
    if not charSwitchPanel_ then return end
    charSwitchPanel_:RemoveAllChildren()

    local charList = {
        { idx = 1, name = "冰法师", avatar = "image/avatar_char1_20260602072030.png", border = { 100, 180, 255, 220 } },
        { idx = 2, name = "角娘", avatar = "image/avatar_char2_20260602072055.png", border = { 255, 100, 100, 220 } },
    }

    for _, info in ipairs(charList) do
        if info.idx ~= currentCharacter_ then
            local btn = UI.Button {
                width = 52, height = 52,
                borderRadius = 26,
                borderWidth = 2.5,
                borderColor = info.border,
                backgroundColor = { 20, 20, 30, 180 },
                backgroundImage = info.avatar,
                backgroundSize = "cover",
                onClick = function()
                    SwitchToCharacter(info.idx)
                end,
            }
            charSwitchPanel_:AddChild(btn)
        end
    end
end

--- 切换到指定角色
function SwitchToCharacter(charIdx)
    if currentCharacter_ == charIdx then return end
    -- 保存当前角色状态
    charStats_[currentCharacter_].hp = playerHP_
    charStats_[currentCharacter_].mp = playerMP_
    currentCharacter_ = charIdx
    -- 恢复目标角色状态
    playerHP_ = charStats_[charIdx].hp
    playerMaxHP_ = charStats_[charIdx].maxHP
    playerMP_ = charStats_[charIdx].mp
    playerMaxMP_ = charStats_[charIdx].maxMP
    -- 切换到角色1时清除角色2的吸血buff
    if charIdx == 1 then lifestealBuffTimer_ = 0 end
    -- 更新右侧切换面板
    RefreshCharSwitchPanel_()
    print("[CHARACTER] 切换到角色" .. charIdx)
end

function CreateGameHUD()
    GameHUD.Initialize()
    local hud = GameHUD.Create({})
    joystick_ = hud.joystick

    -- 右下角操作按钮面板（UI系统）
    -- 创建按钮（通过 state.pressed 轮询检测按住状态，onClick 检测点按）
    btnCharge_ = UI.Button {
        text = "Q", fontSize = 16, width = 60, height = 60,
        backgroundColor = "rgba(60,140,255,0.75)", color = "#ffffff",
        borderRadius = 30, borderWidth = 2, borderColor = "rgba(150,220,255,0.8)",
    }
    btnBlock_ = UI.Button {
        text = "挡", fontSize = 14, width = 60, height = 60,
        backgroundColor = "rgba(180,150,60,0.75)", color = "#ffffff",
        borderRadius = 30, borderWidth = 2, borderColor = "rgba(255,220,130,0.8)",
    }
    btnHeal_ = UI.Button {
        text = "E", fontSize = 16, width = 60, height = 60,
        backgroundColor = "rgba(60,220,120,0.75)", color = "#ffffff",
        borderRadius = 30, borderWidth = 2, borderColor = "rgba(150,255,200,0.8)",
        onClick = function() healButtonTap_ = true end,
    }
    btnAttack_ = UI.Button {
        text = "攻", fontSize = 18, width = 80, height = 80,
        backgroundColor = "rgba(220,80,60,0.8)", color = "#ffffff",
        borderRadius = 40, borderWidth = 2, borderColor = "rgba(255,150,130,0.8)",
        onClick = function() attackButtonTap_ = true end,
    }
    btnJump_ = UI.Button {
        text = "跳", fontSize = 16, width = 66, height = 66,
        backgroundColor = "rgba(143,104,213,0.8)", color = "#ffffff",
        borderRadius = 33, borderWidth = 2, borderColor = "rgba(255,255,255,0.6)",
        onClick = function() jumpButtonTap_ = true end,
    }

    skillButtonPanel_ = UI.Panel {
        position = "absolute",
        bottom = 20, right = 12,
        pointerEvents = "box-none",
        alignItems = "flex-end",
        children = {
            -- 上排：Q + 挡
            UI.Panel {
                flexDirection = "row", gap = 14, marginBottom = 10,
                pointerEvents = "box-none",
                children = { btnCharge_, btnBlock_ },
            },
            -- 中排：E + 攻
            UI.Panel {
                flexDirection = "row", gap = 14, marginBottom = 10,
                alignItems = "center",
                pointerEvents = "box-none",
                children = { btnHeal_, btnAttack_ },
            },
            -- 下排：跳
            UI.Panel {
                flexDirection = "row", justifyContent = "flex-end",
                pointerEvents = "box-none",
                children = { btnJump_ },
            },
        },
    }
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
        -- 落地时结束滞空
        if isHanging_ then
            isHanging_ = false
            playerBody_.gravityScale = 1.0
            wingShatterTimer_ = WING_SHATTER_DURATION  -- 触发破碎动画
        end
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
-- 施法 - 角色1:冰晶投射物 / 角色2:近战镰刀斩
-- ============================================================================
function CastSpell()
    if isAttacking_ then return end
    isAttacking_ = true
    attackTimer_ = 0.0
    currentAnim_ = ANIM_ATTACK
    animFrame_ = 0
    animTimer_ = 0.0

    if currentCharacter_ == 2 then
        -- 角色2：近战攻击，延迟0.5秒后判定前方敌人
        pendingMeleeHit_ = {
            delay = 0.5,
            dir = facingRight_ and 1 or -1,
        }
    else
        -- 角色1：设置延迟发射（0.1秒后生成冰晶）
        pendingProjectile_ = {
            delay = projectileDelay_,
            dir = facingRight_ and 1 or -1,
        }
    end
end

-- ============================================================================
-- 触屏事件（用于大地图选关）
-- ============================================================================
function HandleTouchBegin(eventType, eventData)
    if showTitleScreen_ or showMainMenu_ then return end
    local x = eventData["X"]:GetInt()
    local y = eventData["Y"]:GetInt()
    mapTouchPressed_ = true
    mapTouchX_ = x
    mapTouchY_ = y
end

-- ============================================================================
-- 更新逻辑
-- ============================================================================
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- ========== 标题页面/主菜单时跳过所有游戏逻辑 ==========
    if showTitleScreen_ or showMainMenu_ then return end

    -- ========== 返回按钮/顶部栏可见性 ==========
    local inLevel = not WorldMap.IsOnMap()
    local showHud = inLevel and not hudHidden_
    if backButton_ then
        backButton_:SetVisible(showHud)
    end
    if topButtonBar_ then
        topButtonBar_:SetVisible(showHud)
    end
    if skillButtonPanel_ then
        skillButtonPanel_:SetVisible(showHud)
    end
    if charSwitchPanel_ then
        charSwitchPanel_:SetVisible(showHud)
    end
    -- 地图返回按钮仅在关卡选择页面显示
    if mapBackButton_ then
        mapBackButton_:SetVisible(WorldMap.IsOnMap())
    end

    -- ========== 大地图状态处理 ==========
    if WorldMap.IsOnMap() then
        -- ESC键返回主菜单
        if input:GetKeyPress(KEY_ESCAPE) then
            ShowMainMenu()
            return
        end

        -- 大地图界面：处理鼠标/触屏点击区域
        local screenW = graphics:GetWidth()
        local screenH = graphics:GetHeight()
        local mouseX = input.mousePosition.x
        local mouseY = input.mousePosition.y
        local clicked = input:GetMouseButtonPress(MOUSEB_LEFT)

        -- 触屏支持：用TouchBegin事件标记检测新触摸
        if not clicked and mapTouchPressed_ then
            mouseX = mapTouchX_
            mouseY = mapTouchY_
            clicked = true
        end
        mapTouchPressed_ = false

        local selectedId = WorldMap.HandleMapInput(mouseX, mouseY, screenW, screenH, clicked)
        if selectedId then
            LoadArea(selectedId)
        end
        return  -- 大地图状态不更新游戏逻辑
    end

    -- ========== ESC弹窗状态处理 ==========
    if WorldMap.IsEscPopup() then
        -- ESC键也可关闭弹窗
        if input:GetKeyPress(KEY_ESCAPE) then
            if escPopupUI_ then escPopupUI_:Hide() end
            WorldMap.CloseEscPopup()
        end
        return  -- 弹窗状态不更新游戏逻辑
    end

    -- ========== 正常关卡游戏逻辑 ==========
    if playerBody_ == nil then return end

    -- 光翼破碎动画计时
    if wingShatterTimer_ > 0 then
        wingShatterTimer_ = wingShatterTimer_ - dt
    end
    -- 滞空冷却计时
    if hangCooldown_ > 0 then
        hangCooldown_ = hangCooldown_ - dt
    end

    -- GM控制台切换（数字键0）
    if input:GetKeyPress(KEY_0) then
        GMConsole.Toggle()
    end

    -- GM控制台输入优先处理
    if GMConsole.IsOpen() then
        GMConsole.HandleInput()
        -- GM控制台打开时仍更新敌人和动画（不暂停游戏）
    end

    -- ESC处理：关卡中按ESC弹出离开确认
    if input:GetKeyPress(KEY_ESCAPE) then
        if editorMode_ then
            -- 序列帧编辑器打开时，优先关闭编辑器
            SpriteEditor.Hide()
            editorMode_ = false
        elseif GMConsole.IsOpen() then
            GMConsole.Toggle()
        elseif showSkillPanel_ then
            ToggleSkillPanel()
        elseif showInventory_ then
            ToggleInventoryPanel()
        else
            -- 没有其他面板打开时，显示离开确认弹窗
            WorldMap.ShowEscPopup()
            ShowEscPopupUI()
            return
        end
    end

    -- 判定框切换（TAB键，再按隐藏）
    if input:GetKeyPress(KEY_TAB) then
        debugDraw_ = not debugDraw_
    end

    -- 背包面板切换（B键）
    if input:GetKeyPress(KEY_B) then
        ToggleInventoryPanel()
    end
    -- 技能面板切换（Z键）
    if input:GetKeyPress(KEY_Z) then
        ToggleSkillPanel()
    end

    -- 角色切换（按键1=冰法师, 按键2=黑红角娘）
    if input:GetKeyPress(KEY_1) then
        SwitchToCharacter(1)
    end
    if input:GetKeyPress(KEY_2) then
        SwitchToCharacter(2)
    end

    -- 关卡内UI隐藏切换（X键）
    if input:GetKeyPress(KEY_X) then
        hudHidden_ = not hudHidden_
        -- 立即更新joystick可见性
        if joystick_ then
            joystick_.visible = not hudHidden_
        end
    end

    -- 切图编辑器切换（O键）
    if input:GetKeyPress(KEY_O) then
        SpriteEditor.Toggle()
        editorMode_ = SpriteEditor.IsVisible()
        return  -- 防止同帧内 HandleInput 再次检测到O键导致立即关闭
    end

    -- 编辑器模式下的输入处理（委托给SpriteEditor模块）
    if editorMode_ then
        SpriteEditor.HandleInput()
        -- 同步 editorMode_ 状态（HandleInput中可能关闭了编辑器）
        editorMode_ = SpriteEditor.IsVisible()
        return  -- 编辑器模式不处理游戏逻辑
    end

    -- 受击僵直更新
    if isHit_ then
        hitStunTimer_ = hitStunTimer_ - dt
        if hitStunTimer_ <= 0 then
            isHit_ = false
            hitStunTimer_ = 0
        else
            -- 僵直期间不处理输入，只更新动画帧
            animTimer_ = animTimer_ + dt
            local frameInterval = 1.0 / ANIM_FPS_HIT
            if animTimer_ >= frameInterval then
                animTimer_ = animTimer_ - frameInterval
                animFrame_ = animFrame_ + 1
                if animFrame_ >= SPRITE_FRAMES then
                    animFrame_ = SPRITE_FRAMES - 1
                end
            end
            return
        end
    end

    -- 输入处理
    -- 检测触摸/鼠标是否在UI上，避免UI触摸同时触发游戏输入（如攻击）
    local mouseOnUI = UI.IsPointerOverUI()
    local currentVel = playerBody_.linearVelocity
    local desiredVelX = 0

    -- 虚拟摇杆输入（下拉蹲下，左右偏移45°蹲走）
    local joyCrouchHeld_ = false
    local joyCrouchMoveX_ = 0
    if joystick_ then
        local moveX, moveY = joystick_:getMovement()  -- invertY=true: 上推y>0, 下拉y<0
        if moveY < -0.4 then
            -- 下拉超过阈值 → 蹲下
            joyCrouchHeld_ = true
            -- 判断蹲走：X偏移与Y偏移比例 > tan(45°)=1 时为纯蹲（竖直下拉）
            -- X偏移与Y偏移比例在合理范围内时为蹲走
            local absX = math.abs(moveX)
            local absY = math.abs(moveY)
            if absX > 0.3 and absX / absY > 0.4 then
                -- X 分量足够大，触发蹲走
                joyCrouchMoveX_ = moveX > 0 and 1 or -1
            end
        elseif moveX < -0.1 then
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

    -- 跳跃（onClick点按触发跳跃，state.pressed保持用于滞空）
    local jumpBtnHeld = btnJump_ and btnJump_.state and btnJump_.state.pressed
    local jumpPressed = input:GetKeyPress(KEY_SPACE) or input:GetKeyPress(KEY_W) or input:GetKeyPress(KEY_UP) or input:GetKeyPress(KEY_K) or jumpButtonTap_
    jumpButtonTap_ = false  -- 消费点按
    local jumpHeld = input:GetKeyDown(KEY_SPACE) or input:GetKeyDown(KEY_W) or input:GetKeyDown(KEY_UP) or input:GetKeyDown(KEY_K) or jumpBtnHeld

    if onGround_ and jumpPressed and not isCharging_ and not chargeReleased_ and math.abs(playerBody_.linearVelocity.y) < 2.0 then
        -- 跳跃条件：在地面 + 按键 + 非蓄力/释放状态 + 竖直速度接近0（防止空中身体碰撞误判时连跳）
        onGround_ = false
        groundContactCount_ = 0
        playerBody_.linearVelocity = Vector2(desiredVelX, PLAYER_JUMP_SPEED)
        playerBody_.awake = true
        isHanging_ = false
        playerBody_.gravityScale = 1.0
    elseif not onGround_ and jumpHeld and not isHanging_ and hangCooldown_ <= 0 and playerBody_.linearVelocity.y < 0 then
        -- 空中下落期间长按跳跃键：进入滞空（上升阶段不生效，冷却中不生效）
        isHanging_ = true
        hangCooldown_ = HANG_COOLDOWN_TIME
        playerBody_.gravityScale = HANG_GRAVITY_SCALE
        -- 立即削减当前下落速度
        local vel = playerBody_.linearVelocity
        playerBody_.linearVelocity = Vector2(vel.x, vel.y * 0.3)
    end

    -- 滞空状态：松开跳跃键结束
    if isHanging_ then
        if not jumpHeld then
            isHanging_ = false
            playerBody_.gravityScale = 1.0
            wingShatterTimer_ = WING_SHATTER_DURATION  -- 触发破碎动画
        end
    end

    -- 施法（长按攻击按钮可重复触发）
    local attackBtnHeld = btnAttack_ and btnAttack_.state and btnAttack_.state.pressed
    local attackPressed = input:GetKeyPress(KEY_J) or (not mouseOnUI and input:GetMouseButtonPress(MOUSEB_LEFT)) or attackButtonTap_
    attackButtonTap_ = false  -- 消费单次点按
    -- 长按按钮/键盘时，攻击动画结束后自动重复
    if not attackPressed and (attackBtnHeld or input:GetKeyDown(KEY_J) or (not mouseOnUI and input:GetMouseButtonDown(MOUSEB_LEFT))) then
        if not isAttacking_ then
            attackPressed = true
        end
    end
    if attackPressed and not isBlocking_ and not isCharging_ and not chargeReleased_ then
        CastSpell()
    end

    -- 格挡（鼠标右键长按，松开结束）
    local blockBtnHeld = btnBlock_ and btnBlock_.state and btnBlock_.state.pressed
    local blockHeld = (not mouseOnUI and input:GetMouseButtonDown(MOUSEB_RIGHT)) or input:GetKeyDown(KEY_L) or blockBtnHeld
    if blockHeld and not isBlocking_ and not isAttacking_ and not isCharging_ and (playerMP_ > 0 or GMConsole.IsInfiniteMP()) then
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
        if not GMConsole.IsInfiniteMP() then
            playerMP_ = playerMP_ - BLOCK_MP_PER_SEC * dt
            if playerMP_ <= 0 then
                playerMP_ = 0
                isBlocking_ = false
            end
        end
    end

    -- 蓄力光波（Q键长按，最多3秒）
    local chargeBtnHeld = btnCharge_ and btnCharge_.state and btnCharge_.state.pressed
    local chargeHeld = input:GetKeyDown(KEY_Q) or chargeBtnHeld
    if not editorMode_ then
        local chargeStart = input:GetKeyPress(KEY_Q)
        if chargeBtnHeld and not isCharging_ then chargeStart = true end
        if chargeStart and not isCharging_ and not chargeReleased_ and not isAttacking_ and not isBlocking_ and not isDashing_ then
            -- 开始蓄力
            isCharging_ = true
            chargeTimer_ = 0.0
            currentAnim_ = ANIM_CHARGE
            animFrame_ = 0
            animTimer_ = 0.0
        elseif isCharging_ then
            chargeTimer_ = chargeTimer_ + dt
            -- 松开Q或达到最大时间 → 释放
            if not chargeHeld or chargeTimer_ >= CHARGE_MAX_DURATION then
                -- MP不足时取消蓄力，不释放
                if playerMP_ < CHARGE_MP_COST then
                    isCharging_ = false
                    chargeReleased_ = false
                else
                isCharging_ = false
                chargeReleased_ = true
                if not GMConsole.IsInfiniteMP() then
                    playerMP_ = playerMP_ - CHARGE_MP_COST
                end

                if currentCharacter_ == 2 then
                    -- 角色2：蝴蝶突进 —— 蓄力越长位移越远
                    local power = math.min(chargeTimer_ / CHARGE_MAX_DURATION, 1.0)
                    isDashing_ = true
                    dashTimer_ = 0.0
                    dashDir_ = facingRight_ and 1 or -1
                    dashStartX_ = playerNode_.position2D.x
                    dashTargetDist_ = CHAR2_DASH_MIN_DIST + (CHAR2_DASH_MAX_DIST - CHAR2_DASH_MIN_DIST) * power
                    dashHitEnemies_ = {}
                else
                    -- 角色1：在前方地面生成矿脉状冰晶群（索敌：优先生成在敌人脚下）
                    local pos = playerNode_.position2D
                    local dir = facingRight_ and 1 or -1
                    local power = math.min(chargeTimer_ / CHARGE_MAX_DURATION, 1.0)
                    local maxRange = ICE_CRYSTAL_MIN_DIST + (ICE_CRYSTAL_MAX_DIST - ICE_CRYSTAL_MIN_DIST) * power
                    local crystals = {}
                    local baseX = pos.x + dir * maxRange
                    local groundY = pos.y - 0.5
                    local enemies = Enemy.GetAll()
                    local closestDist = math.huge
                    for _, e in ipairs(enemies) do
                        if e.alive then
                            local dx = e.x - pos.x
                            if (dir > 0 and dx > 0 and dx <= maxRange) or (dir < 0 and dx < 0 and math.abs(dx) <= maxRange) then
                                local dist = math.abs(dx)
                                if dist >= ICE_CRYSTAL_MIN_DIST and dist < closestDist then
                                    closestDist = dist
                                    baseX = e.x
                                    groundY = e.y - 0.5
                                end
                            end
                        end
                    end
                    -- 也索引蝙蝠和古堡敌人
                    for _, b in ipairs(BatEnemy.GetAll()) do
                        if b.alive then
                            local dx = b.x - pos.x
                            if (dir > 0 and dx > 0 and dx <= maxRange) or (dir < 0 and dx < 0 and math.abs(dx) <= maxRange) then
                                local dist = math.abs(dx)
                                if dist >= ICE_CRYSTAL_MIN_DIST and dist < closestDist then
                                    closestDist = dist
                                    baseX = b.x
                                    groundY = b.y - 0.5
                                end
                            end
                        end
                    end
                    for _, c in ipairs(CastleEnemies.GetAll()) do
                        if c.alive then
                            local dx = c.x - pos.x
                            if (dir > 0 and dx > 0 and dx <= maxRange) or (dir < 0 and dx < 0 and math.abs(dx) <= maxRange) then
                                local dist = math.abs(dx)
                                if dist >= ICE_CRYSTAL_MIN_DIST and dist < closestDist then
                                    closestDist = dist
                                    baseX = c.x
                                    groundY = c.y - 0.5
                                end
                            end
                        end
                    end
                    for i = 1, ICE_CRYSTAL_COUNT do
                        local spread = (i - (ICE_CRYSTAL_COUNT + 1) / 2) * 0.6 * dir
                        local centerFactor = 1.0 - math.abs(i - (ICE_CRYSTAL_COUNT + 1) / 2) / ((ICE_CRYSTAL_COUNT + 1) / 2)
                        local h = ICE_CRYSTAL_HEIGHT * (0.4 + centerFactor * 0.6) * (0.8 + math.random() * 0.2)
                        table.insert(crystals, {
                            x = baseX + spread,
                            height = h,
                            width = 0.2 + math.random() * 0.25,
                            delay = (i - 1) * 0.05,
                            angle = (math.random() - 0.5) * 0.3,
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
                end
                -- 切换到释放帧（帧9-11）
                animFrame_ = 9
                animTimer_ = 0.0
                end  -- end else (MP足够)
            end
        end
        -- 释放动画播放完毕后恢复
        if chargeReleased_ and currentAnim_ == ANIM_CHARGE and animFrame_ >= 11 then
            chargeReleased_ = false
            -- 蝴蝶突进结束后也重置
            if isDashing_ then
                isDashing_ = false
            end
            -- 修正：释放结束时如果竖直速度接近0且在地面附近，修正着地状态
            if playerBody_ and math.abs(playerBody_.linearVelocity.y) < 1.0 and groundContactCount_ > 0 then
                onGround_ = true
            end
        end
    end

    -- 治愈技能（E键，一次性释放，有冷却）
    if not editorMode_ then
        -- 冷却计时
        if healCooldownTimer_ > 0 then
            healCooldownTimer_ = healCooldownTimer_ - dt
        end
        local healPressed = input:GetKeyPress(KEY_E) or healButtonTap_
        healButtonTap_ = false  -- 消费单次点按
        if healPressed and not isHealing_ and not isCharging_ and not chargeReleased_ and not isAttacking_ and not isBlocking_ and healCooldownTimer_ <= 0 and (playerMP_ >= HEAL_MP_COST or GMConsole.IsInfiniteMP()) then
            isHealing_ = true
            healTimer_ = 0.0
            currentAnim_ = ANIM_HEAL
            animFrame_ = 0
            animTimer_ = 0.0
            if not GMConsole.IsInfiniteMP() then
                playerMP_ = playerMP_ - HEAL_MP_COST
            end
        end
        if isHealing_ then
            healTimer_ = healTimer_ + dt
            if healTimer_ >= HEAL_DURATION then
                isHealing_ = false
                healCooldownTimer_ = HEAL_COOLDOWN
                -- 治愈完成，回复HP
                if currentCharacter_ == 2 then
                    -- 蝶之加护：回复10HP（每级+5）+ 施加10s吸血buff
                    local eLevel = skillList2_[3].level
                    local healAmount = 10 + (eLevel - 1) * 5
                    playerHP_ = math.min(playerHP_ + healAmount, playerMaxHP_)
                    lifestealBuffTimer_ = LIFESTEAL_DURATION
                else
                    playerHP_ = math.min(playerHP_ + HEAL_HP_RESTORE, playerMaxHP_)
                end
            end
        end
        -- 更新吸血buff计时器
        if lifestealBuffTimer_ > 0 then
            lifestealBuffTimer_ = lifestealBuffTimer_ - dt
            if lifestealBuffTimer_ < 0 then lifestealBuffTimer_ = 0 end
        end
    end

    -- 潜行（S键/左Shift长按/摇杆下拉，地面时可用）
    if not editorMode_ then
        local crouchHeld = input:GetKeyDown(KEY_S) or input:GetKeyDown(KEY_LSHIFT) or joyCrouchHeld_
        local wasCrouching = isCrouching_
        if crouchHeld and onGround_ and not isCharging_ and not chargeReleased_ and not isHealing_ and not isAttacking_ then
            if not wasCrouching then
                -- 刚开始蹲下，进入下蹲过渡阶段
                isCrouching_ = true
                crouchPhase_ = "enter"
                animFrame_ = 1  -- crouchFrameMap_ 索引从1开始
                animTimer_ = 0.0
            end
            -- 摇杆蹲走：下拉时左右偏移触发蹲走移动
            if joyCrouchMoveX_ ~= 0 then
                desiredVelX = joyCrouchMoveX_ * PLAYER_SPEED
                facingRight_ = joyCrouchMoveX_ > 0
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

    -- 蓄力/治愈/突进期间不能移动（突进时由dash逻辑控制位移）
    if isDashing_ then
        -- 蝴蝶突进：强制水平移动
        playerBody_.linearVelocity = Vector2(dashDir_ * CHAR2_DASH_SPEED, 0)
        desiredVelX = 0
    elseif isCharging_ or chargeReleased_ or isHealing_ then
        desiredVelX = 0
        -- 保留当前Y速度（可能刚跳跃设置了PLAYER_JUMP_SPEED，不能覆盖）
        playerBody_.linearVelocity = Vector2(0, playerBody_.linearVelocity.y)
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

    -- 玩家边界钳制：不允许走出地图边缘
    local pPos = playerNode_.position2D
    local playerBound = MAP_HALF_WIDTH - PLAYER_RADIUS
    if pPos.x < -playerBound then
        playerNode_:SetPosition2D(-playerBound, pPos.y)
        playerBody_.linearVelocity = Vector2(math.max(0, playerBody_.linearVelocity.x), playerBody_.linearVelocity.y)
    elseif pPos.x > playerBound then
        playerNode_:SetPosition2D(playerBound, pPos.y)
        playerBody_.linearVelocity = Vector2(math.min(0, playerBody_.linearVelocity.x), playerBody_.linearVelocity.y)
    end

    -- 处理延迟发射冰晶（角色1）
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

    -- 处理角色2近战判定
    if pendingMeleeHit_ then
        pendingMeleeHit_.delay = pendingMeleeHit_.delay - dt
        if pendingMeleeHit_.delay <= 0 then
            local pos = playerNode_.position2D
            local dir = pendingMeleeHit_.dir
            -- 获取当前等级伤害
            local meleeDmg = CHAR2_MELEE_DAMAGE + (skillList2_[1].level - 1)
            -- 判定前方范围内的敌人
            local enemies = Enemy.GetAll()
            for _, e in ipairs(enemies) do
                if e.alive then
                    local dx = e.x - pos.x
                    local dy = e.y - pos.y
                    -- 敌人在面朝方向且在近战范围内
                    local hit = false
                    if dir > 0 and dx > 0 and dx <= CHAR2_MELEE_RANGE and math.abs(dy) < 1.5 then
                        Enemy.TakeDamage(e, meleeDmg)
                        hit = true
                    elseif dir < 0 and dx < 0 and math.abs(dx) <= CHAR2_MELEE_RANGE and math.abs(dy) < 1.5 then
                        Enemy.TakeDamage(e, meleeDmg)
                        hit = true
                    end
                    -- 吸血buff：攻击命中时回复伤害50%的HP（向下取整）
                    if hit and lifestealBuffTimer_ > 0 then
                        local healAmt = math.floor(meleeDmg * LIFESTEAL_RATIO)
                        if healAmt > 0 then
                            playerHP_ = math.min(playerHP_ + healAmt, playerMaxHP_)
                        end
                    end
                end
            end
            -- 蝙蝠近战判定
            local bats = BatEnemy.GetAll()
            for _, b in ipairs(bats) do
                if b.alive then
                    local dx = b.x - pos.x
                    local dy = b.y - pos.y
                    local hit = false
                    if dir > 0 and dx > 0 and dx <= CHAR2_MELEE_RANGE and math.abs(dy) < 2.5 then
                        BatEnemy.TakeDamage(b, meleeDmg)
                        hit = true
                    elseif dir < 0 and dx < 0 and math.abs(dx) <= CHAR2_MELEE_RANGE and math.abs(dy) < 2.5 then
                        BatEnemy.TakeDamage(b, meleeDmg)
                        hit = true
                    end
                    if hit and lifestealBuffTimer_ > 0 then
                        local healAmt = math.floor(meleeDmg * LIFESTEAL_RATIO)
                        if healAmt > 0 then
                            playerHP_ = math.min(playerHP_ + healAmt, playerMaxHP_)
                        end
                    end
                end
            end
            -- 古堡敌人近战判定
            local castles = CastleEnemies.GetAll()
            for _, c in ipairs(castles) do
                if c.alive then
                    local dx = c.x - pos.x
                    local dy = c.y - pos.y
                    local hit = false
                    if dir > 0 and dx > 0 and dx <= CHAR2_MELEE_RANGE and math.abs(dy) < 2.5 then
                        CastleEnemies.TakeDamage(c, meleeDmg)
                        hit = true
                    elseif dir < 0 and dx < 0 and math.abs(dx) <= CHAR2_MELEE_RANGE and math.abs(dy) < 2.5 then
                        CastleEnemies.TakeDamage(c, meleeDmg)
                        hit = true
                    end
                    if hit and lifestealBuffTimer_ > 0 then
                        local healAmt = math.floor(meleeDmg * LIFESTEAL_RATIO)
                        if healAmt > 0 then
                            playerHP_ = math.min(playerHP_ + healAmt, playerMaxHP_)
                        end
                    end
                end
            end
            pendingMeleeHit_ = nil
        end
    end

    -- 更新蝴蝶突进（角色2）
    if isDashing_ then
        dashTimer_ = dashTimer_ + dt
        local pos = playerNode_.position2D
        local traveled = math.abs(pos.x - dashStartX_)
        -- 突进过程中检测路径上的敌人
        local enemies = Enemy.GetAll()
        for _, e in ipairs(enemies) do
            if e.alive and not dashHitEnemies_[tostring(e)] then
                local dx = e.x - pos.x
                local dy = e.y - pos.y
                -- 在突进方向上前方1.5米内、高度2米内的敌人
                if math.abs(dy) < 2.0 then
                    if (dashDir_ > 0 and dx >= -0.5 and dx <= 1.5) or (dashDir_ < 0 and dx <= 0.5 and dx >= -1.5) then
                        Enemy.TakeDamage(e, CHAR2_DASH_DAMAGE)
                        Enemy.ApplyBleed(e, CHAR2_BLEED_DURATION, CHAR2_BLEED_DPS)
                        dashHitEnemies_[tostring(e)] = true
                        -- 吸血buff：突进命中也触发吸血
                        if lifestealBuffTimer_ > 0 then
                            local healAmt = math.floor(CHAR2_DASH_DAMAGE * LIFESTEAL_RATIO)
                            if healAmt > 0 then
                                playerHP_ = math.min(playerHP_ + healAmt, playerMaxHP_)
                            end
                        end
                    end
                end
            end
        end
        -- 突进也检测蝙蝠
        local bats = BatEnemy.GetAll()
        for _, b in ipairs(bats) do
            if b.alive and not dashHitEnemies_["bat_" .. tostring(b)] then
                local dx = b.x - pos.x
                local dy = b.y - pos.y
                if math.abs(dy) < 3.0 then
                    if (dashDir_ > 0 and dx >= -0.5 and dx <= 1.5) or (dashDir_ < 0 and dx <= 0.5 and dx >= -1.5) then
                        BatEnemy.TakeDamage(b, CHAR2_DASH_DAMAGE)
                        BatEnemy.ApplyBleed(b, CHAR2_BLEED_DURATION, CHAR2_BLEED_DPS)
                        dashHitEnemies_["bat_" .. tostring(b)] = true
                        if lifestealBuffTimer_ > 0 then
                            local healAmt = math.floor(CHAR2_DASH_DAMAGE * LIFESTEAL_RATIO)
                            if healAmt > 0 then
                                playerHP_ = math.min(playerHP_ + healAmt, playerMaxHP_)
                            end
                        end
                    end
                end
            end
        end
        -- 突进也检测古堡敌人
        local castles = CastleEnemies.GetAll()
        for _, c in ipairs(castles) do
            if c.alive and not dashHitEnemies_["castle_" .. tostring(c)] then
                local dx = c.x - pos.x
                local dy = c.y - pos.y
                if math.abs(dy) < 3.0 then
                    if (dashDir_ > 0 and dx >= -0.5 and dx <= 1.5) or (dashDir_ < 0 and dx <= 0.5 and dx >= -1.5) then
                        CastleEnemies.TakeDamage(c, CHAR2_DASH_DAMAGE)
                        CastleEnemies.ApplyBleed(c, CHAR2_BLEED_DURATION, CHAR2_BLEED_DPS)
                        dashHitEnemies_["castle_" .. tostring(c)] = true
                        if lifestealBuffTimer_ > 0 then
                            local healAmt = math.floor(CHAR2_DASH_DAMAGE * LIFESTEAL_RATIO)
                            if healAmt > 0 then
                                playerHP_ = math.min(playerHP_ + healAmt, playerMaxHP_)
                            end
                        end
                    end
                end
            end
        end
        -- 突进结束条件：距离够了或时间超限
        if traveled >= dashTargetDist_ or dashTimer_ >= (dashTargetDist_ / CHAR2_DASH_SPEED + 0.1) then
            isDashing_ = false
            playerBody_.linearVelocity = Vector2(0, playerBody_.linearVelocity.y)
        end
    end

    -- 更新投射物
    UpdateProjectiles(dt)

    -- 更新地面冰晶
    UpdateIceCrystals(dt)

    -- 更新敌人
    local playerPos = playerNode_.position2D
    Enemy.Update(dt, playerPos.x, playerPos.y, playerHP_)

    -- 更新蝙蝠敌人
    local batCamPos = cameraNode_ and cameraNode_.worldPosition or Vector3(0, 0, -10)
    BatEnemy.Update(dt, playerPos.x, playerPos.y, batCamPos.x, batCamPos.y, SCREEN_WIDTH, SCREEN_HEIGHT, PIXELS_PER_UNIT)

    -- 更新古堡敌人
    CastleEnemies.Update(dt, playerPos.x, playerPos.y, batCamPos.x, batCamPos.y, SCREEN_WIDTH, SCREEN_HEIGHT, PIXELS_PER_UNIT)

    -- 敌人攻击命中玩家（普攻和技能分开返回）
    local normalDmg, skillDmg = Enemy.CheckAttackHits(playerPos.x, playerPos.y)
    -- 蝙蝠攻击伤害
    local batDmg = BatEnemy.CheckAttackHits(playerPos.x, playerPos.y)
    -- 古堡敌人攻击伤害
    local castleDmg = CastleEnemies.CheckAttackHits(playerPos.x, playerPos.y)
    local totalDmg = normalDmg + skillDmg + batDmg + castleDmg

    -- 无敌模式跳过伤害
    if totalDmg > 0 and GMConsole.IsInvincible() then
        totalDmg = 0
    end

    if totalDmg > 0 and isBlocking_ then
        -- 格挡减半伤害（不触发僵直）
        playerHP_ = math.max(0, playerHP_ - totalDmg * 0.5)
    elseif totalDmg > 0 then
        playerHP_ = math.max(0, playerHP_ - totalDmg)
        -- 蓄力中：普攻不打断，技能才打断
        if isCharging_ and skillDmg == 0 then
            -- 普攻命中蓄力中的玩家，只扣血不打断
        else
            -- 触发受击僵直
            isHit_ = true
            hitStunTimer_ = HIT_STUN_DURATION
            -- 中断其他动作
            isAttacking_ = false
            isCharging_ = false
            chargeReleased_ = false
            isHealing_ = false
            currentAnim_ = ANIM_HIT
            animFrame_ = 0
            animTimer_ = 0.0
        end
    end

    -- 投射物命中敌人
    Enemy.CheckProjectileHits(projectiles_, PROJECTILE_DAMAGE)
    BatEnemy.CheckProjectileHits(projectiles_, PROJECTILE_DAMAGE)
    CastleEnemies.CheckProjectileHits(projectiles_, PROJECTILE_DAMAGE)

    -- 物理调试
    if debugDraw_ and physicsWorld_ then
        physicsWorld_:DrawDebugGeometry()
    end
end

-- ============================================================================
-- 动画状态机
-- ============================================================================
function UpdateAnimation(dt, velX)
    -- 受击状态中，不切换动画（由僵直逻辑控制帧更新）
    if isHit_ then
        return
    end

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
            -- 蓄力动画：角色1: 0-2起手，3-8蓄力循环，9-11释放
            --           角色2: 0-1起手，2-4蓄力循环，5-11释放
            if isCharging_ then
                if currentCharacter_ == 2 then
                    -- 角色2蓄力中：在帧2-4之间循环（第3、4、5帧）
                    if animFrame_ > 4 then
                        animFrame_ = 2
                    end
                else
                    -- 角色1蓄力中：在帧3-8之间循环
                    if animFrame_ > 8 then
                        animFrame_ = 3
                    end
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
            -- 蹲走动画：交替播放蹲下序列帧的第7帧和第3帧（0-based: 6和2）
            animFrame_ = animFrame_ % 2
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
    -- 冰晶群命中敌人（伤害+冰冻）
    Enemy.CheckCrystalHits(iceCrystals_, CHARGE_DAMAGE, CHARGE_FREEZE_DURATION)
    BatEnemy.CheckCrystalHits(iceCrystals_, CHARGE_DAMAGE, CHARGE_FREEZE_DURATION)
    CastleEnemies.CheckCrystalHits(iceCrystals_, CHARGE_DAMAGE, CHARGE_FREEZE_DURATION)
end

-- ============================================================================
-- 相机跟随
-- ============================================================================
function HandlePostUpdate(eventType, eventData)
    if showTitleScreen_ or showMainMenu_ then return end
    if playerNode_ ~= nil and cameraNode_ ~= nil then
        local pos = playerNode_.position2D
        -- 平滑相机跟随
        local camPos = cameraNode_.position
        local targetX = pos.x
        local targetY = math.max(pos.y, 0)  -- 相机不跟随太低
        local lerpFactor = 5.0 * eventData["TimeStep"]:GetFloat()
        local newX = camPos.x + (targetX - camPos.x) * lerpFactor
        local newY = camPos.y + (targetY - camPos.y) * lerpFactor

        -- 相机边界钳制：到达地图左右边缘时固定不移动
        local camHalfView = (graphics:GetWidth() / PIXELS_PER_UNIT) * 0.5
        local camMinX = -MAP_HALF_WIDTH + camHalfView
        local camMaxX = MAP_HALF_WIDTH - camHalfView
        newX = math.max(camMinX, math.min(camMaxX, newX))

        cameraNode_:SetPosition(Vector3(newX, newY, -10))
    end
end

-- ============================================================================
-- NanoVG 渲染
-- ============================================================================
function HandleRender(eventType, eventData)
    if nvg_ == nil then return end
    -- 标题页面/主菜单时不绘制NanoVG内容
    if showTitleScreen_ or showMainMenu_ then return end

    local width = graphics:GetWidth()
    local height = graphics:GetHeight()

    nvgBeginFrame(nvg_, width, height, 1.0)

    -- ========== 大地图界面：只绘制地图 ==========
    if WorldMap.IsOnMap() then
        WorldMap.DrawMap(width, height)
        nvgEndFrame(nvg_)
        return
    end

    -- 获取相机位置
    local camPos = cameraNode_ and cameraNode_.worldPosition or Vector3(0, 0, -10)
    local camX = camPos.x
    local camY = camPos.y

    -- 绘制背景
    DrawBackground(width, height, camX)

    -- 绘制平台（白盒）
    DrawPlatforms(width, height, camX, camY)

    -- 绘制投射物
    DrawProjectiles(width, height, camX, camY)

    -- 绘制蓄力特效（在玩家后面）
    if isCharging_ then
        if currentCharacter_ == 2 then
            DrawChargeEffectChar2(width, height, camX, camY)
        else
            DrawChargeEffect(width, height, camX, camY)
        end
    end

    -- 绘制治愈特效（在玩家后面）
    if isHealing_ then
        DrawHealEffect(width, height, camX, camY)
    end

    -- 绘制敌人
    Enemy.Draw(width, height, camX, camY, SCREEN_WIDTH, SCREEN_HEIGHT, PIXELS_PER_UNIT)
    BatEnemy.Draw(width, height, camX, camY, SCREEN_WIDTH, SCREEN_HEIGHT, PIXELS_PER_UNIT)
    CastleEnemies.Draw(width, height, camX, camY, SCREEN_WIDTH, SCREEN_HEIGHT, PIXELS_PER_UNIT)

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

    -- 技能面板和背包面板已由UI系统绘制，不再使用NanoVG

    -- 敌方血条（最上层绘制，不被角色和其他物件遮挡）
    Enemy.DrawHealthBars(width, height, camX, camY, SCREEN_WIDTH, SCREEN_HEIGHT, PIXELS_PER_UNIT)
    BatEnemy.DrawHealthBars(width, height, camX, camY, SCREEN_WIDTH, SCREEN_HEIGHT, PIXELS_PER_UNIT)
    CastleEnemies.DrawHealthBars(width, height, camX, camY, SCREEN_WIDTH, SCREEN_HEIGHT, PIXELS_PER_UNIT)

    -- 绘制GM控制台
    GMConsole.Draw(width, height)

    -- 切图编辑器（NanoVG预览部分）
    if editorMode_ then
        SpriteEditor.DrawPreview(width, height)
    end

    -- ESC弹窗已迁移到UI系统，无需NanoVG绘制

    nvgEndFrame(nvg_)
end

-- ============================================================================
-- 绘制背景
-- ============================================================================
function DrawBackground(width, height, camX)
    camX = camX or 0

    -- 多层视差背景（冰原区域）
    if #parallaxLayers_ > 0 then
        for _, layer in ipairs(parallaxLayers_) do
            if layer.img and layer.img > 0 then
                -- 图片宽度=2倍屏幕宽以实现无缝滚动
                local imgW = width * 2
                local imgH = height
                -- 根据相机X偏移乘以视差因子计算水平位移（像素）
                local offsetX = -(camX * PIXELS_PER_UNIT * layer.factor)
                -- 循环平铺：让偏移量在 [-imgW, 0] 之间循环
                offsetX = offsetX % imgW
                if offsetX > 0 then offsetX = offsetX - imgW end

                -- 绘制两份以确保无缝
                local paint = nvgImagePattern(nvg_, offsetX, 0, imgW, imgH, 0, layer.img, 1.0)
                nvgBeginPath(nvg_)
                nvgRect(nvg_, 0, 0, width, height)
                nvgFillPaint(nvg_, paint)
                nvgFill(nvg_)

                -- 如果右侧有空隙则补一份
                if offsetX + imgW < width then
                    local paint2 = nvgImagePattern(nvg_, offsetX + imgW, 0, imgW, imgH, 0, layer.img, 1.0)
                    nvgBeginPath(nvg_)
                    nvgRect(nvg_, offsetX + imgW, 0, width - (offsetX + imgW), height)
                    nvgFillPaint(nvg_, paint2)
                    nvgFill(nvg_)
                end
            end
        end
    elseif imgBackground_ and imgBackground_ > 0 then
        -- 单层背景（古堡/森林等无视差的区域）
        local paint = nvgImagePattern(nvg_, 0, 0, width, height, 0, imgBackground_, 1.0)
        nvgBeginPath(nvg_)
        nvgRect(nvg_, 0, 0, width, height)
        nvgFillPaint(nvg_, paint)
        nvgFill(nvg_)
    else
        -- fallback: 纯色渐变背景
        nvgBeginPath(nvg_)
        nvgRect(nvg_, 0, 0, width, height)
        local bg = nvgLinearGradient(nvg_, 0, 0, 0, height,
            nvgRGBA(20, 30, 60, 255),
            nvgRGBA(40, 60, 120, 255))
        nvgFillPaint(nvg_, bg)
        nvgFill(nvg_)
    end
end

-- ============================================================================
-- 绘制平台（古堡石质高台风格）
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

        local isGround = (p.width >= 20)  -- 地面平台

        if isGround then
            local groundTop = screenY - h / 2
            local groundLeft = screenX - w / 2

            if imgGroundArea_ and imgGroundArea_ > 0 then
                -- 使用区域地面贴图平铺
                local tileW = 64 * sx  -- 每块贴图宽度
                local tileH = h
                local startX = groundLeft
                while startX < groundLeft + w do
                    local drawW = math.min(tileW, groundLeft + w - startX)
                    local paint = nvgImagePattern(nvg_, startX, groundTop, tileW, tileH, 0, imgGroundArea_, 1.0)
                    nvgBeginPath(nvg_)
                    nvgRect(nvg_, startX, groundTop, drawW, tileH)
                    nvgFillPaint(nvg_, paint)
                    nvgFill(nvg_)
                    startX = startX + tileW
                end
                -- 顶部边缘高光
                nvgBeginPath(nvg_)
                nvgRect(nvg_, groundLeft, groundTop, w, 2 * sy)
                nvgFillColor(nvg_, nvgRGBA(255, 255, 255, 40))
                nvgFill(nvg_)
            else
                -- 古堡地面：简洁渐变地板
                nvgBeginPath(nvg_)
                nvgRect(nvg_, groundLeft, groundTop, w, h)
                local stoneGrad = nvgLinearGradient(nvg_, 0, groundTop, 0, groundTop + h,
                    nvgRGBA(60, 40, 35, 255),
                    nvgRGBA(40, 25, 20, 255))
                nvgFillPaint(nvg_, stoneGrad)
                nvgFill(nvg_)

                -- 石砖纹理线条
                nvgStrokeColor(nvg_, nvgRGBA(30, 18, 15, 150))
                nvgStrokeWidth(nvg_, 1.0 * sx)
                local brickW = 24 * sx
                local brickH = h / 2
                for row = 0, 1 do
                    local yy = groundTop + row * brickH
                    local offsetBrick = (row % 2 == 0) and 0 or (brickW / 2)
                    local startX = groundLeft + offsetBrick
                    while startX < groundLeft + w do
                        nvgBeginPath(nvg_)
                        nvgRect(nvg_, startX, yy, brickW, brickH)
                        nvgStroke(nvg_)
                        startX = startX + brickW
                    end
                end

                -- 地毯（暗红色带金边）
                local carpetW = w * 0.6
                local carpetH = h * 0.4
                local carpetX = screenX - carpetW / 2
                local carpetY = groundTop + 2 * sy
                nvgBeginPath(nvg_)
                nvgRect(nvg_, carpetX, carpetY, carpetW, carpetH)
                local carpetGrad = nvgLinearGradient(nvg_, carpetX, carpetY, carpetX + carpetW, carpetY,
                    nvgRGBA(120, 20, 30, 200),
                    nvgRGBA(80, 15, 20, 200))
                nvgFillPaint(nvg_, carpetGrad)
                nvgFill(nvg_)
                -- 金色边框
                nvgStrokeColor(nvg_, nvgRGBA(180, 140, 60, 180))
                nvgStrokeWidth(nvg_, 1.5 * sx)
                nvgStroke(nvg_)
            end
        elseif imgPlatformArea_ and imgPlatformArea_ > 0 then
            -- 区域图片平台（冰封/藤蔓石块等）
            local platTop = screenY - h / 2
            local drawW = w * 1.15  -- 图片比碰撞框稍宽
            local drawH = h * 2.2   -- 图片比碰撞框更高（显示细节）
            local drawX = screenX - drawW / 2
            local drawY = platTop - drawH * 0.25  -- 向上偏移，让平台面对齐碰撞顶部

            local paint = nvgImagePattern(nvg_, drawX, drawY, drawW, drawH, 0, imgPlatformArea_, 1.0)
            nvgBeginPath(nvg_)
            nvgRoundedRect(nvg_, drawX, drawY, drawW, drawH, 4 * sx)
            nvgFillPaint(nvg_, paint)
            nvgFill(nvg_)
        else
            -- 空中平台：华丽巴洛克金色高台（参考古堡浮空平台素材）
            local platTop = screenY - h / 2
            local platH = h
            local left = screenX - w / 2
            local right = screenX + w / 2

            -- 平台阴影（柔和投影）
            nvgBeginPath(nvg_)
            nvgRect(nvg_, left + 4 * sx, platTop + 4 * sy, w, platH + 8 * sy)
            nvgFillColor(nvg_, nvgRGBA(0, 0, 0, 100))
            nvgFill(nvg_)

            -- === 主体：深色木质/石质基座 ===
            nvgBeginPath(nvg_)
            nvgRect(nvg_, left, platTop, w, platH)
            local bodyGrad = nvgLinearGradient(nvg_, 0, platTop, 0, platTop + platH,
                nvgRGBA(50, 35, 25, 255),
                nvgRGBA(30, 20, 15, 255))
            nvgFillPaint(nvg_, bodyGrad)
            nvgFill(nvg_)

            -- === 顶部金色平台面（略宽于主体） ===
            local topH = math.max(4 * sy, platH * 0.25)
            nvgBeginPath(nvg_)
            nvgRect(nvg_, left - 3 * sx, platTop, w + 6 * sx, topH)
            local goldTopGrad = nvgLinearGradient(nvg_, 0, platTop, 0, platTop + topH,
                nvgRGBA(210, 175, 90, 255),
                nvgRGBA(160, 120, 50, 255))
            nvgFillPaint(nvg_, goldTopGrad)
            nvgFill(nvg_)

            -- 顶面高光线
            nvgBeginPath(nvg_)
            nvgRect(nvg_, left - 3 * sx, platTop, w + 6 * sx, 1.5 * sy)
            nvgFillColor(nvg_, nvgRGBA(245, 220, 140, 200))
            nvgFill(nvg_)

            -- === 金色下沿装饰边框 ===
            local bottomBorderH = math.max(3 * sy, platH * 0.2)
            local borderY = platTop + platH - bottomBorderH
            nvgBeginPath(nvg_)
            nvgRect(nvg_, left - 2 * sx, borderY, w + 4 * sx, bottomBorderH)
            local goldBotGrad = nvgLinearGradient(nvg_, 0, borderY, 0, borderY + bottomBorderH,
                nvgRGBA(180, 140, 55, 255),
                nvgRGBA(130, 95, 35, 255))
            nvgFillPaint(nvg_, goldBotGrad)
            nvgFill(nvg_)

            -- === 中间金色浮雕纹饰 ===
            local ornamentCount = math.max(1, math.floor(w / (28 * sx)))
            local ornSpacing = w / (ornamentCount + 1)
            for i = 1, ornamentCount do
                local ox = left + ornSpacing * i
                local oy = platTop + platH * 0.5

                local ornSize = math.min(6 * sx, ornSpacing * 0.35)

                -- 中心菱形纹章
                nvgBeginPath(nvg_)
                nvgMoveTo(nvg_, ox, oy - ornSize)
                nvgLineTo(nvg_, ox + ornSize, oy)
                nvgLineTo(nvg_, ox, oy + ornSize)
                nvgLineTo(nvg_, ox - ornSize, oy)
                nvgClosePath(nvg_)
                nvgFillColor(nvg_, nvgRGBA(190, 150, 60, 200))
                nvgFill(nvg_)

                -- 菱形内部小点
                nvgBeginPath(nvg_)
                nvgCircle(nvg_, ox, oy, ornSize * 0.3)
                nvgFillColor(nvg_, nvgRGBA(220, 185, 90, 220))
                nvgFill(nvg_)

                -- 两侧卷曲装饰线
                nvgStrokeColor(nvg_, nvgRGBA(180, 140, 55, 160))
                nvgStrokeWidth(nvg_, 1.2 * sx)
                nvgBeginPath(nvg_)
                nvgMoveTo(nvg_, ox - ornSize * 1.3, oy)
                nvgQuadTo(nvg_, ox - ornSize * 2.0, oy - ornSize * 0.6,
                          ox - ornSize * 2.5, oy)
                nvgStroke(nvg_)
                nvgBeginPath(nvg_)
                nvgMoveTo(nvg_, ox + ornSize * 1.3, oy)
                nvgQuadTo(nvg_, ox + ornSize * 2.0, oy - ornSize * 0.6,
                          ox + ornSize * 2.5, oy)
                nvgStroke(nvg_)
            end

            -- === 两端金色柱头装饰 ===
            for side = -1, 1, 2 do
                local capX = (side < 0) and left or (right - 5 * sx)
                local capW = 5 * sx
                nvgBeginPath(nvg_)
                nvgRect(nvg_, capX, platTop, capW, platH)
                local capGrad = nvgLinearGradient(nvg_, capX, platTop, capX + capW, platTop,
                    nvgRGBA(170, 130, 45, 255),
                    nvgRGBA(130, 95, 35, 255))
                nvgFillPaint(nvg_, capGrad)
                nvgFill(nvg_)
                -- 端柱内侧高光
                local hlX = (side < 0) and (capX + capW - 1.5 * sx) or capX
                nvgBeginPath(nvg_)
                nvgRect(nvg_, hlX, platTop + 2 * sy, 1.5 * sx, platH - 4 * sy)
                nvgFillColor(nvg_, nvgRGBA(220, 185, 90, 120))
                nvgFill(nvg_)
            end

            -- === 底部中央垂饰（倒三角+圆球） ===
            local pendantX = screenX
            local pendantTop = platTop + platH
            local pendantW = 6 * sx
            local pendantH = 10 * sy
            nvgBeginPath(nvg_)
            nvgMoveTo(nvg_, pendantX - pendantW, pendantTop)
            nvgLineTo(nvg_, pendantX + pendantW, pendantTop)
            nvgLineTo(nvg_, pendantX, pendantTop + pendantH)
            nvgClosePath(nvg_)
            nvgFillColor(nvg_, nvgRGBA(160, 120, 45, 230))
            nvgFill(nvg_)
            nvgBeginPath(nvg_)
            nvgCircle(nvg_, pendantX, pendantTop + pendantH + 2.5 * sy, 2.5 * sx)
            nvgFillColor(nvg_, nvgRGBA(190, 150, 60, 240))
            nvgFill(nvg_)

            -- === 整体金色边框轮廓 ===
            nvgBeginPath(nvg_)
            nvgRect(nvg_, left - 3 * sx, platTop, w + 6 * sx, platH)
            nvgStrokeColor(nvg_, nvgRGBA(200, 160, 65, 180))
            nvgStrokeWidth(nvg_, 1.5 * sx)
            nvgStroke(nvg_)
        end
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

    -- ====== 4) 竖立椭圆形法阵（角色前方，水平压缩模拟竖立透视） ======
    local circleOffX = dir * 65 * sx
    local circleX = screenX + circleOffX
    local circleY = screenY - 22 * sy
    local baseRadius = 28 * sx
    local radius = baseRadius * (0.5 + progress * 0.8)
    local rotation = t * 2.5
    local alpha = math.floor(130 + progress * 125)
    local ellipseScaleX = 0.45  -- 水平压缩比例，模拟竖立椭圆

    -- 法阵外层光晕（椭圆形）
    nvgSave(nvg_)
    nvgTranslate(nvg_, circleX, circleY)
    nvgScale(nvg_, ellipseScaleX, 1.0)
    local haloGrad = nvgRadialGradient(nvg_, 0, 0, radius * 0.5, radius * 1.5,
        nvgRGBA(100, 200, 255, math.floor(alpha * 0.3)), nvgRGBA(100, 200, 255, 0))
    nvgBeginPath(nvg_)
    nvgCircle(nvg_, 0, 0, radius * 1.5)
    nvgFillPaint(nvg_, haloGrad)
    nvgFill(nvg_)
    nvgRestore(nvg_)

    nvgSave(nvg_)
    nvgTranslate(nvg_, circleX, circleY)
    nvgScale(nvg_, ellipseScaleX, 1.0)
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
    nvgRestore(nvg_)

    -- 内层反向旋转符文圈（同样椭圆压缩）
    nvgSave(nvg_)
    nvgTranslate(nvg_, circleX, circleY)
    nvgScale(nvg_, ellipseScaleX, 1.0)
    nvgRotate(nvg_, -rotation * 0.7)
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

    -- 法阵周围小光点环绕（椭圆轨道）
    local dotCount = math.floor(6 + progress * 6)
    for i = 1, dotCount do
        local da = (i / dotCount) * math.pi * 2 + t * 3
        local dd = radius * (1.3 + math.sin(t * 4 + i * 2) * 0.2)
        local dx = circleX + math.cos(da) * dd * ellipseScaleX
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

    -- ====== 11) 蓄力进度条（角色头顶上方，不被精灵遮挡） ======
    local barW = 50 * sx
    local barH = 5 * sy
    local barX = screenX - barW / 2
    local barY = screenY - 145 * sy
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
-- 绘制角色2蓄力特效（红色蝴蝶群 + 暗红光辉）
-- ============================================================================
function DrawChargeEffectChar2(width, height, camX, camY)
    if playerNode_ == nil then return end

    local pos = playerNode_.position2D
    local screenX, screenY = PhysicsToScreen(pos.x, pos.y, camX, camY)
    local sx = width / SCREEN_WIDTH
    local sy = height / SCREEN_HEIGHT
    screenX = screenX * sx
    screenY = screenY * sy

    local progress = math.min(chargeTimer_ / CHARGE_MAX_DURATION, 1.0)
    local dir = facingRight_ and 1 or -1
    local t = chargeTimer_
    local glowCenterY = screenY - 30 * sy
    local bodyRadius = 38 * sx

    -- ====== 1) 角色身体暗红光辉 ======
    local glowRadius = 40 * sx * (0.8 + progress * 0.5)
    local bodyGlowAlpha = math.floor(30 + progress * 80)
    local glowGrad = nvgRadialGradient(nvg_, screenX, glowCenterY, glowRadius * 0.2, glowRadius,
        nvgRGBA(200, 50, 80, bodyGlowAlpha), nvgRGBA(150, 20, 60, 0))
    nvgBeginPath(nvg_)
    nvgCircle(nvg_, screenX, glowCenterY, glowRadius)
    nvgFillPaint(nvg_, glowGrad)
    nvgFill(nvg_)

    -- ====== 2) 脚底暗红能量圈 ======
    local frostPulse = 1.0 + math.sin(t * 4) * 0.15
    local frostR1 = bodyRadius * (1.0 + progress * 0.6) * frostPulse
    nvgBeginPath(nvg_)
    nvgEllipse(nvg_, screenX, screenY, frostR1, frostR1 * 0.22)
    nvgStrokeColor(nvg_, nvgRGBA(200, 50, 80, math.floor((50 + progress * 120) * frostPulse)))
    nvgStrokeWidth(nvg_, 1.5 + progress * 2)
    nvgStroke(nvg_)

    -- ====== 3) 蝴蝶群环绕角色 ======
    local butterflyCount = math.floor(3 + progress * 5)
    for i = 1, butterflyCount do
        local angle = (i / butterflyCount) * math.pi * 2 + t * 1.2
        local dist = bodyRadius * (0.8 + math.sin(t * 1.8 + i * 2.1) * 0.3)
        local bx = screenX + math.cos(angle) * dist
        local by = glowCenterY + math.sin(angle) * dist * 0.5
        by = by + math.sin(t * 2.5 + i * 1.5) * 6 * sy

        local bSize = (4 + progress * 4) * sx
        local bAlpha = math.floor(160 + progress * 90)
        -- 蝴蝶翅膀拍动
        local wingFlap = math.sin(t * 8 + i * 2.5) * 0.4 + 0.6

        nvgSave(nvg_)
        nvgTranslate(nvg_, bx, by)
        nvgRotate(nvg_, math.sin(t * 1.5 + i) * 0.3)

        -- 左翅
        nvgBeginPath(nvg_)
        nvgEllipse(nvg_, -bSize * 0.5 * wingFlap, 0, bSize * 0.7 * wingFlap, bSize * 0.45)
        nvgFillColor(nvg_, nvgRGBA(220, 40, 80, bAlpha))
        nvgFill(nvg_)
        -- 右翅
        nvgBeginPath(nvg_)
        nvgEllipse(nvg_, bSize * 0.5 * wingFlap, 0, bSize * 0.7 * wingFlap, bSize * 0.45)
        nvgFillColor(nvg_, nvgRGBA(220, 40, 80, bAlpha))
        nvgFill(nvg_)
        -- 身体
        nvgBeginPath(nvg_)
        nvgEllipse(nvg_, 0, 0, bSize * 0.12, bSize * 0.35)
        nvgFillColor(nvg_, nvgRGBA(60, 0, 20, bAlpha))
        nvgFill(nvg_)
        -- 翅膀高光
        nvgBeginPath(nvg_)
        nvgEllipse(nvg_, -bSize * 0.35 * wingFlap, -bSize * 0.1, bSize * 0.2 * wingFlap, bSize * 0.15)
        nvgFillColor(nvg_, nvgRGBA(255, 120, 160, math.floor(bAlpha * 0.5)))
        nvgFill(nvg_)
        nvgBeginPath(nvg_)
        nvgEllipse(nvg_, bSize * 0.35 * wingFlap, -bSize * 0.1, bSize * 0.2 * wingFlap, bSize * 0.15)
        nvgFillColor(nvg_, nvgRGBA(255, 120, 160, math.floor(bAlpha * 0.5)))
        nvgFill(nvg_)

        nvgRestore(nvg_)
    end

    -- ====== 4) 小蝴蝶微粒散布（外层快速飞舞） ======
    local dustCount = math.floor(6 + progress * 12)
    for i = 1, dustCount do
        local angle = (i / dustCount) * math.pi * 2 + t * 2.5 + i * 0.15
        local dist2 = bodyRadius * (1.2 + progress * 0.6 + math.sin(t * 3 + i * 0.9) * 0.3)
        local px = screenX + math.cos(angle) * dist2
        local py = glowCenterY + math.sin(angle) * dist2 * 0.45
        py = py + math.sin(t * 4 + i * 1.8) * 4 * sy
        local pSize = (1.5 + math.sin(t * 6 + i * 2.1) * 0.7) * sx * (1 + progress)
        local pAlpha = math.floor((80 + progress * 140) * (0.4 + math.sin(t * 7 + i * 3) * 0.6))
        if pAlpha > 0 then
            nvgBeginPath(nvg_)
            nvgCircle(nvg_, px, py, pSize)
            nvgFillColor(nvg_, nvgRGBA(255, 80, 120, pAlpha))
            nvgFill(nvg_)
        end
    end

    -- ====== 5) 螺旋上升蝴蝶轨迹 ======
    if progress > 0.2 then
        local spiralAlpha = (progress - 0.2) / 0.8
        local segCount = math.floor(12 + progress * 16)
        for i = 1, segCount do
            local segT = (i / segCount)
            local spiralAngle = segT * math.pi * 3 + t * 2.5
            local spiralDist = bodyRadius * (0.4 + segT * 0.7)
            local spiralX = screenX + math.cos(spiralAngle) * spiralDist
            local spiralY = glowCenterY + 15 * sy - segT * 70 * sy
            local segSize = (1.5 + (1.0 - segT) * 2) * sx * spiralAlpha
            local segAlpha = math.floor((1.0 - segT * 0.7) * 180 * spiralAlpha)
            if segAlpha > 10 then
                nvgBeginPath(nvg_)
                nvgCircle(nvg_, spiralX, spiralY, segSize)
                nvgFillColor(nvg_, nvgRGBA(255, 60, 100, segAlpha))
                nvgFill(nvg_)
            end
        end
    end

    -- ====== 6) 脉冲波纹（暗红色） ======
    local pulseInterval = 0.7 - progress * 0.2
    for pi = 1, 3 do
        local pulsePhase = ((t + pi * pulseInterval) % (pulseInterval * 3)) / (pulseInterval * 3)
        local pulseRadius = bodyRadius * (0.5 + pulsePhase * 2.0)
        local pulseAlphaVal = (1.0 - pulsePhase) * progress
        if pulseAlphaVal > 0.05 then
            nvgBeginPath(nvg_)
            nvgCircle(nvg_, screenX, glowCenterY, pulseRadius)
            nvgStrokeColor(nvg_, nvgRGBA(200, 50, 80, math.floor(80 * pulseAlphaVal)))
            nvgStrokeWidth(nvg_, (1.5 - pulsePhase) * 2)
            nvgStroke(nvg_)
        end
    end

    -- ====== 7) 蓄力进度条（角色头顶上方，不被精灵遮挡，红色系） ======
    local barW = 50 * sx
    local barH = 5 * sy
    local barX = screenX - barW / 2
    local barY = screenY - 145 * sy
    nvgBeginPath(nvg_)
    nvgRoundedRect(nvg_, barX, barY, barW, barH, 2)
    nvgFillColor(nvg_, nvgRGBA(0, 0, 0, 150))
    nvgFill(nvg_)
    nvgBeginPath(nvg_)
    nvgRoundedRect(nvg_, barX + 1, barY + 1, (barW - 2) * progress, barH - 2, 1)
    local barGrad = nvgLinearGradient(nvg_, barX, barY, barX + barW * progress, barY,
        nvgRGBA(200, 40, 80, 255), nvgRGBA(255, 100, 140, 255))
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

    -- 角色2使用红色/紫色治愈特效，角色1保持绿色
    local isChar2 = (currentCharacter_ == 2)
    -- 颜色方案：角色1=绿色系，角色2=红紫色系
    local glowR, glowG, glowB = 100, 255, 150
    local glowR2, glowG2, glowB2 = 50, 200, 100
    local ringR, ringG, ringB = 80, 255, 140
    local circleR, circleG, circleB = 80, 230, 130
    local starR, starG, starB = 120, 255, 170
    local particleR, particleG, particleB = 100, 255, 160
    local runeR, runeG, runeB = 80, 240, 140
    local runeHiR, runeHiG, runeHiB = 200, 255, 220
    local spiralR, spiralG, spiralB = 120, 255, 180
    local pillarR, pillarG, pillarB = 80, 255, 140
    local flashR, flashG, flashB = 200, 255, 220

    if isChar2 then
        glowR, glowG, glowB = 200, 60, 100
        glowR2, glowG2, glowB2 = 150, 30, 80
        ringR, ringG, ringB = 220, 60, 120
        circleR, circleG, circleB = 180, 50, 140
        starR, starG, starB = 200, 80, 180
        particleR, particleG, particleB = 220, 70, 140
        runeR, runeG, runeB = 180, 50, 160
        runeHiR, runeHiG, runeHiB = 255, 180, 220
        spiralR, spiralG, spiralB = 200, 60, 180
        pillarR, pillarG, pillarB = 200, 50, 120
        flashR, flashG, flashB = 255, 180, 220
    end

    -- ====== 1) 全身柔光 ======
    local glowCenterY = screenY - 30 * sy
    local glowRadius = bodyRadius * (1.2 + progress * 0.3)
    local glowGrad = nvgRadialGradient(nvg_, screenX, glowCenterY, glowRadius * 0.1, glowRadius,
        nvgRGBA(glowR, glowG, glowB, math.floor(60 * alpha)), nvgRGBA(glowR2, glowG2, glowB2, 0))
    nvgBeginPath(nvg_)
    nvgCircle(nvg_, screenX, glowCenterY, glowRadius)
    nvgFillPaint(nvg_, glowGrad)
    nvgFill(nvg_)

    -- ====== 2) 主光环（快速扩散的圆环） ======
    local ringCount = 3
    for ri = 1, ringCount do
        local ringPhase = (progress * 3 + ri * 0.3) % 1.0
        local ringRadius = bodyRadius * (0.4 + ringPhase * 1.8)
        local ringAlpha = (1.0 - ringPhase) * alpha
        if ringAlpha > 0.02 then
            nvgBeginPath(nvg_)
            nvgCircle(nvg_, screenX, glowCenterY, ringRadius)
            nvgStrokeColor(nvg_, nvgRGBA(ringR, ringG, ringB, math.floor(180 * ringAlpha)))
            nvgStrokeWidth(nvg_, (2.5 - ringPhase * 1.5) * sx)
            nvgStroke(nvg_)
        end
    end

    -- ====== 3) 底部魔法阵（六芒星旋转） ======
    local circleRadius = bodyRadius * (0.6 + progress * 0.4)
    local rotation = t * 3.5
    nvgSave(nvg_)
    nvgTranslate(nvg_, screenX, screenY)
    nvgRotate(nvg_, rotation)
    -- 外圈
    nvgBeginPath(nvg_)
    nvgCircle(nvg_, 0, 0, circleRadius)
    nvgStrokeColor(nvg_, nvgRGBA(circleR, circleG, circleB, math.floor(160 * alpha)))
    nvgStrokeWidth(nvg_, 2 * sx)
    nvgStroke(nvg_)
    -- 六芒星
    for i = 0, 5 do
        local a1 = (i / 6) * math.pi * 2
        local a2 = ((i + 2) / 6) * math.pi * 2
        nvgBeginPath(nvg_)
        nvgMoveTo(nvg_, math.cos(a1) * circleRadius * 0.85, math.sin(a1) * circleRadius * 0.85)
        nvgLineTo(nvg_, math.cos(a2) * circleRadius * 0.85, math.sin(a2) * circleRadius * 0.85)
        nvgStrokeColor(nvg_, nvgRGBA(starR, starG, starB, math.floor(140 * alpha)))
        nvgStrokeWidth(nvg_, 1.5 * sx)
        nvgStroke(nvg_)
    end
    nvgRestore(nvg_)

    -- ====== 4) 上升光粒子（密集环绕上升） ======
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
            if i % 5 == 0 then
                nvgFillColor(nvg_, nvgRGBA(255, 255, 220, math.floor(200 * pAlpha)))
            else
                nvgFillColor(nvg_, nvgRGBA(particleR, particleG, particleB, math.floor(180 * pAlpha)))
            end
            nvgFill(nvg_)
        end
    end

    -- ====== 5) 叶片/符文环绕（菱形符文） ======
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
        nvgFillColor(nvg_, nvgRGBA(runeR, runeG, runeB, math.floor(160 * alpha)))
        nvgFill(nvg_)
        -- 中线高光
        nvgBeginPath(nvg_)
        nvgMoveTo(nvg_, 0, -rSize * 1.2)
        nvgLineTo(nvg_, 0, rSize * 1.2)
        nvgStrokeColor(nvg_, nvgRGBA(runeHiR, runeHiG, runeHiB, math.floor(180 * alpha)))
        nvgStrokeWidth(nvg_, 0.8 * sx)
        nvgStroke(nvg_)
        nvgRestore(nvg_)
    end

    -- ====== 6) 螺旋光带（双螺旋上升） ======
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
                nvgFillColor(nvg_, nvgRGBA(spiralR, spiralG, spiralB, math.floor(140 * sAlpha)))
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
            nvgRGBA(pillarR, pillarG, pillarB, math.floor(80 * pillarAlpha)),
            nvgRGBA(pillarR, pillarG, pillarB, 0))
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
        nvgStrokeColor(nvg_, nvgRGBA(flashR, flashG, flashB, math.floor(200 * flashAlpha)))
        nvgStrokeWidth(nvg_, 2 * sx)
        nvgStroke(nvg_)
        -- 垂直线
        nvgBeginPath(nvg_)
        nvgMoveTo(nvg_, screenX, glowCenterY - flashSize)
        nvgLineTo(nvg_, screenX, glowCenterY + flashSize)
        nvgStrokeColor(nvg_, nvgRGBA(flashR, flashG, flashB, math.floor(200 * flashAlpha)))
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

    -- 玩家渲染尺寸（支持每动画独立缩放）
    local animCropConfig_ = GetCurrentAnimCropConfig()
    local animScale = (animCropConfig_[currentAnim_] and animCropConfig_[currentAnim_].scale) or 5.5
    local playerDrawSize = PLAYER_RADIUS * animScale * PIXELS_PER_UNIT * sx

    -- 选择当前序列帧图片（根据角色）
    local img = imgIdle_
    if currentCharacter_ == 2 then
        -- 角色2: 黑红角娘
        img = img2Idle_
        if currentAnim_ == ANIM_RUN then
            img = img2Run_
        elseif currentAnim_ == ANIM_JUMP then
            img = img2Jump_
        elseif currentAnim_ == ANIM_ATTACK then
            img = img2Attack_
        elseif currentAnim_ == ANIM_BLOCK then
            img = img2Block_
        elseif currentAnim_ == ANIM_CHARGE then
            img = img2Burst_   -- 角色2 Q技能: 蝴蝶瞬移爆发
        elseif currentAnim_ == ANIM_HEAL then
            img = img2Heal_
        elseif currentAnim_ == ANIM_CROUCH then
            img = img2Crouch_
        elseif currentAnim_ == ANIM_CROUCH_WALK then
            img = img2CrouchWalk_
        elseif currentAnim_ == ANIM_HIT then
            img = img2Hit_
        end
    else
        -- 角色1: 冰法师
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
            img = imgCrouch_  -- 角色1蹲走复用蹲下序列帧
        elseif currentAnim_ == ANIM_HIT then
            img = imgHit_
        end
    end

    local frame = animFrame_

    -- 蹲下动画使用帧映射表：animFrame_是索引(1-based)，转为实际帧号(0-based)
    if currentAnim_ == ANIM_CROUCH then
        local map = (currentCharacter_ == 2) and crouchFrameMap2_ or crouchFrameMap_
        local idx = math.max(1, math.min(animFrame_, #map))
        frame = map[idx]
    end

    -- 角色1蹲走：交替使用蹲下序列帧的第7帧和第3帧（0-based: 6和2）
    if currentAnim_ == ANIM_CROUCH_WALK and currentCharacter_ == 1 then
        local crouchWalkFrames = { 6, 2 }  -- 0-based帧号
        frame = crouchWalkFrames[(animFrame_ % 2) + 1]
    end

    -- 光翼特效（滞空时显示 / 破碎动画）
    DrawWingsEffect(screenX, screenY, playerDrawSize)

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
-- 光翼特效绘制（滞空时显示，结束时破碎消散）
-- 简单黄色菱形几何图形，只在角色背后一侧，跟随朝向
-- ============================================================================
function DrawWingsEffect(cx, cy, playerSize)
    local showWings = isHanging_
    local showShatter = wingShatterTimer_ > 0

    if not showWings and not showShatter then return end

    nvgSave(nvg_)
    nvgGlobalAlpha(nvg_, 0.85)  -- 85%不透明度

    -- 朝向决定光翼方向：面朝右时光翼在左侧（背后），反之亦然
    local dirSign = facingRight_ and -1 or 1

    -- 光翼基准位置：角色背部肩膀处，偏向背后
    local baseX = cx + dirSign * playerSize * 0.15
    local baseY = cy - playerSize * 0.25

    -- 3片菱形羽翼的配置：{角度偏移, 长度比例, 宽度比例, 距离中心偏移}
    local feathers = {
        { angle = -30, lenScale = 0.85, widScale = 0.8, dist = 0.2 },  -- 上翼
        { angle =   5, lenScale = 1.0,  widScale = 0.85, dist = 0.25 }, -- 中翼
        { angle =  40, lenScale = 0.7,  widScale = 0.7, dist = 0.2 },  -- 下翼
    }

    local baseLen = playerSize * 0.4   -- 菱形基础长度
    local baseWid = playerSize * 0.08  -- 菱形基础宽度

    -- 角色配色：角色1黄色，角色2黑→深红渐变
    local isChar2 = (currentCharacter_ == 2)

    if showWings then
        -- 滞空中：轻微脉动 + 微浮动
        local pulse = 1.0 + math.sin(os.clock() * 6.0) * 0.06
        local floatY = math.sin(os.clock() * 3.0) * 1.0
        baseY = baseY + floatY

        for _, f in ipairs(feathers) do
            local len = baseLen * f.lenScale * pulse
            local wid = baseWid * f.widScale * pulse
            local rad = math.rad(f.angle)
            -- 菱形中心点（向背后方向展开）
            local fcx = baseX + dirSign * math.cos(rad) * playerSize * f.dist
            local fcy = baseY + math.sin(rad) * playerSize * f.dist

            -- 菱形方向沿角度展开，水平分量跟随朝向翻转
            local cosA = math.cos(rad) * dirSign
            local sinA = math.sin(rad)
            local tipX = fcx + cosA * len * 0.6
            local tipY = fcy + sinA * len * 0.6
            local tailX = fcx - cosA * len * 0.4
            local tailY = fcy - sinA * len * 0.4
            local sideX1 = fcx + (-sinA) * wid
            local sideY1 = fcy + cosA * wid * dirSign
            local sideX2 = fcx - (-sinA) * wid
            local sideY2 = fcy - cosA * wid * dirSign

            nvgBeginPath(nvg_)
            nvgMoveTo(nvg_, tipX, tipY)
            nvgLineTo(nvg_, sideX1, sideY1)
            nvgLineTo(nvg_, tailX, tailY)
            nvgLineTo(nvg_, sideX2, sideY2)
            nvgClosePath(nvg_)
            if isChar2 then
                -- 角色2：深紫黑→亮红渐变
                local grad = nvgLinearGradient(nvg_, tailX, tailY, tipX, tipY,
                    nvgRGBA(40, 5, 15, 255), nvgRGBA(220, 40, 40, 255))
                nvgFillPaint(nvg_, grad)
            else
                -- 角色1：从内到外 橘色→黄色渐变
                local grad = nvgLinearGradient(nvg_, tailX, tailY, tipX, tipY,
                    nvgRGBA(255, 140, 20, 255), nvgRGBA(255, 230, 50, 255))
                nvgFillPaint(nvg_, grad)
            end
            nvgFill(nvg_)
        end
    else
        -- 破碎动画：各片菱形向外散开 + 缩小 + 渐隐
        local progress = 1.0 - (wingShatterTimer_ / WING_SHATTER_DURATION)  -- 0→1
        local fadeAlpha = math.floor((1.0 - progress) * 255)
        local scatter = progress * playerSize * 0.6

        for _, f in ipairs(feathers) do
            local shrink = 1.0 - progress * 0.7
            local len = baseLen * f.lenScale * shrink
            local wid = baseWid * f.widScale * shrink
            local rad = math.rad(f.angle)
            local scatterX = dirSign * math.cos(rad) * scatter
            local scatterY = math.sin(rad) * scatter + progress * playerSize * 0.2
            local fcx = baseX + dirSign * math.cos(rad) * playerSize * f.dist + scatterX
            local fcy = baseY + math.sin(rad) * playerSize * f.dist + scatterY

            local cosA = math.cos(rad) * dirSign
            local sinA = math.sin(rad)
            local tipX = fcx + cosA * len * 0.6
            local tipY = fcy + sinA * len * 0.6
            local tailX = fcx - cosA * len * 0.4
            local tailY = fcy - sinA * len * 0.4
            local sideX1 = fcx + (-sinA) * wid
            local sideY1 = fcy + cosA * wid * dirSign
            local sideX2 = fcx - (-sinA) * wid
            local sideY2 = fcy - cosA * wid * dirSign

            nvgBeginPath(nvg_)
            nvgMoveTo(nvg_, tipX, tipY)
            nvgLineTo(nvg_, sideX1, sideY1)
            nvgLineTo(nvg_, tailX, tailY)
            nvgLineTo(nvg_, sideX2, sideY2)
            nvgClosePath(nvg_)
            if isChar2 then
                local grad = nvgLinearGradient(nvg_, tailX, tailY, tipX, tipY,
                    nvgRGBA(40, 5, 15, fadeAlpha), nvgRGBA(220, 40, 40, fadeAlpha))
                nvgFillPaint(nvg_, grad)
            else
                -- 角色1：从内到外 橘色→黄色渐变（带淡出）
                local grad = nvgLinearGradient(nvg_, tailX, tailY, tipX, tipY,
                    nvgRGBA(255, 140, 20, fadeAlpha), nvgRGBA(255, 230, 50, fadeAlpha))
                nvgFillPaint(nvg_, grad)
            end
            nvgFill(nvg_)
        end
    end

    nvgRestore(nvg_)
end

function DrawSpriteFrame(img, frame, cx, cy, size, flipH)
    -- 获取当前动画的裁切配置（含可能的自定义grid）
    local animCropConfig_ = GetCurrentAnimCropConfig()
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

    -- 圆形头像参数
    local avatarSize = 44 * sx
    local avatarX = 14 * sx
    local avatarY = 14 * sy
    local avatarCX = avatarX + avatarSize / 2
    local avatarCY = avatarY + avatarSize / 2
    local avatarR = avatarSize / 2

    -- 绘制圆形头像
    local avatarImg = (currentCharacter_ == 1) and imgAvatar1_ or imgAvatar2_
    if avatarImg and avatarImg > 0 then
        nvgSave(nvg_)
        nvgBeginPath(nvg_)
        nvgCircle(nvg_, avatarCX, avatarCY, avatarR)
        local imgPaint = nvgImagePattern(nvg_, avatarX, avatarY, avatarSize, avatarSize, 0, avatarImg, 1.0)
        nvgFillPaint(nvg_, imgPaint)
        nvgFill(nvg_)
        -- 头像边框
        nvgBeginPath(nvg_)
        nvgCircle(nvg_, avatarCX, avatarCY, avatarR)
        nvgStrokeColor(nvg_, nvgRGBA(220, 200, 120, 220))
        nvgStrokeWidth(nvg_, 2.5 * sx)
        nvgStroke(nvg_)
        nvgRestore(nvg_)
    end

    -- HP/MP 条在头像右侧
    local barX = avatarX + avatarSize + 8 * sx
    local barY = avatarY + 2 * sy
    local barW = 180 * sx
    local barH = 16 * sy
    local gap = 6 * sy
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

    -- ====== 技能图标（HP/MP 下方） ======
    local iconSize = 36 * sx
    local iconY = mpY + barH + 10 * sy
    local iconGap = 8 * sx
    local iconQ, iconE
    if currentCharacter_ == 2 then
        iconQ = iconChar2Q_
        iconE = iconChar2E_
    else
        iconQ = iconChar1Q_
        iconE = iconChar1E_
    end

    -- Q 技能图标
    local iconQX = barX
    if iconQ and iconQ > 0 then
        local imgPat = nvgImagePattern(nvg_, iconQX, iconY, iconSize, iconSize, 0, iconQ, 1.0)
        nvgBeginPath(nvg_)
        nvgRoundedRect(nvg_, iconQX, iconY, iconSize, iconSize, 4 * sx)
        nvgFillPaint(nvg_, imgPat)
        nvgFill(nvg_)
        -- Q技能无CD，不需要CD遮罩
    end
    -- Q 标签
    nvgFontFace(nvg_, "sans")
    nvgFontSize(nvg_, 10 * sx)
    nvgFillColor(nvg_, nvgRGBA(255, 255, 255, 200))
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgText(nvg_, iconQX + iconSize / 2, iconY + iconSize + 2 * sy, "Q")

    -- E 技能图标
    local iconEX = iconQX + iconSize + iconGap
    if iconE and iconE > 0 then
        local imgPat = nvgImagePattern(nvg_, iconEX, iconY, iconSize, iconSize, 0, iconE, 1.0)
        nvgBeginPath(nvg_)
        nvgRoundedRect(nvg_, iconEX, iconY, iconSize, iconSize, 4 * sx)
        nvgFillPaint(nvg_, imgPat)
        nvgFill(nvg_)

        -- E 技能 CD 遮罩
        if healCooldownTimer_ > 0 then
            -- 暗色遮罩
            nvgBeginPath(nvg_)
            nvgRoundedRect(nvg_, iconEX, iconY, iconSize, iconSize, 4 * sx)
            nvgFillColor(nvg_, nvgRGBA(0, 0, 0, 160))
            nvgFill(nvg_)
            -- CD 倒计时文字
            nvgFontFace(nvg_, "sans")
            nvgFontSize(nvg_, 14 * sx)
            nvgFillColor(nvg_, nvgRGBA(255, 255, 255, 240))
            nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            nvgText(nvg_, iconEX + iconSize / 2, iconY + iconSize / 2, string.format("%.1f", healCooldownTimer_))
        end
    end
    -- E 标签
    nvgFontSize(nvg_, 10 * sx)
    nvgFillColor(nvg_, nvgRGBA(255, 255, 255, 200))
    nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgText(nvg_, iconEX + iconSize / 2, iconY + iconSize + 2 * sy, "E")

    -- 图标边框
    nvgBeginPath(nvg_)
    nvgRoundedRect(nvg_, iconQX, iconY, iconSize, iconSize, 4 * sx)
    nvgStrokeColor(nvg_, nvgRGBA(180, 180, 200, 150))
    nvgStrokeWidth(nvg_, 1.5)
    nvgStroke(nvg_)
    nvgBeginPath(nvg_)
    nvgRoundedRect(nvg_, iconEX, iconY, iconSize, iconSize, 4 * sx)
    nvgStrokeColor(nvg_, nvgRGBA(180, 180, 200, 150))
    nvgStrokeWidth(nvg_, 1.5)
    nvgStroke(nvg_)

    -- 吸血buff状态指示器（角色2激活时显示）
    if currentCharacter_ == 2 and lifestealBuffTimer_ > 0 then
        local buffY = iconY + iconSize + 16 * sy
        local buffW = 80 * sx
        local buffH = 14 * sy
        -- 背景
        nvgBeginPath(nvg_)
        nvgRoundedRect(nvg_, barX, buffY, buffW, buffH, 3 * sx)
        nvgFillColor(nvg_, nvgRGBA(80, 0, 40, 180))
        nvgFill(nvg_)
        -- 进度条（剩余时间比例）
        local buffRatio = lifestealBuffTimer_ / LIFESTEAL_DURATION
        nvgBeginPath(nvg_)
        nvgRoundedRect(nvg_, barX, buffY, buffW * buffRatio, buffH, 3 * sx)
        local buffGrad = nvgLinearGradient(nvg_, barX, buffY, barX + buffW, buffY,
            nvgRGBA(220, 50, 150, 220), nvgRGBA(180, 30, 100, 220))
        nvgFillPaint(nvg_, buffGrad)
        nvgFill(nvg_)
        -- 边框
        nvgBeginPath(nvg_)
        nvgRoundedRect(nvg_, barX, buffY, buffW, buffH, 3 * sx)
        nvgStrokeColor(nvg_, nvgRGBA(255, 100, 180, 150))
        nvgStrokeWidth(nvg_, 1.0)
        nvgStroke(nvg_)
        -- 文字
        nvgFontFace(nvg_, "sans")
        nvgFontSize(nvg_, 10 * sx)
        nvgFillColor(nvg_, nvgRGBA(255, 220, 240, 255))
        nvgTextAlign(nvg_, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgText(nvg_, barX + buffW / 2, buffY + buffH / 2, string.format("吸血 %.1fs", lifestealBuffTimer_))
    end
end

-- ============================================================================
-- UI面板：技能面板（支持鼠标/触屏交互）
-- ============================================================================
function CreateSkillPanelUI()
    -- 全屏遮罩 + 居中面板（点击遮罩关闭）
    skillPanelUI_ = UI.Panel {
        id = "skillPanelRoot",
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        onClick = function() ToggleSkillPanel() end,
        children = {
            UI.Panel {
                id = "skillPanelCard",
                width = 340,
                backgroundColor = { 15, 20, 40, 240 },
                borderRadius = 10,
                borderWidth = 2,
                borderColor = { 100, 200, 160, 180 },
                padding = 10,
                onClick = function() end,  -- 阻止冒泡到遮罩
                children = {
                    -- 标题行
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        marginBottom = 6,
                        children = {
                            UI.Label { id = "skillTitle", text = "技能 - 冰法师", fontSize = 14, fontColor = { 150, 255, 200, 255 } },
                            UI.Label { id = "skillPoints", text = "技能点: 3", fontSize = 12, fontColor = { 255, 220, 80, 255 } },
                        }
                    },
                    -- 分隔线
                    UI.Panel { width = "100%", height = 1, backgroundColor = { 80, 180, 140, 120 }, marginBottom = 6 },
                    -- 技能列表容器（横向排列，一行两个）
                    UI.Panel { id = "skillListContainer", width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 5 },
                    -- 底部关闭按钮
                    UI.Panel {
                        width = "100%", marginTop = 8,
                        justifyContent = "center", alignItems = "center",
                        children = {
                            UI.Button {
                                text = "关闭(Z)",
                                fontSize = 12,
                                variant = "secondary",
                                onClick = function(self)
                                    ToggleSkillPanel()
                                end,
                            }
                        }
                    },
                }
            }
        }
    }
    skillPanelUI_:Hide()
end

--- 构建技能数据文本
function BuildSkillStatText_(curData)
    local statText = ""
    if curData.dmg then statText = statText .. "伤害:" .. curData.dmg .. " " end
    if curData.heal then statText = statText .. "回复:" .. curData.heal .. " " end
    if curData.lifesteal then statText = statText .. "吸血:" .. curData.lifesteal .. "s " end
    if curData.mp and curData.mp > 0 then statText = statText .. "MP:" .. curData.mp .. " " end
    if curData.mpSec then statText = statText .. "MP/s:" .. curData.mpSec .. " " end
    if curData.reduce then statText = statText .. "减伤:" .. math.floor(curData.reduce * 100) .. "% " end
    if curData.cd then statText = statText .. "CD:" .. curData.cd .. "s " end
    return statText
end

--- 刷新技能面板内容（切换角色或加减点后调用）
function RefreshSkillPanelUI()
    if not skillPanelUI_ then return end
    local skills = (currentCharacter_ == 1) and skillList_ or skillList2_
    local charName = (currentCharacter_ == 1) and "冰法师" or "黑红角娘"
    local points = skillPoints_[currentCharacter_]

    -- 更新标题和技能点
    skillPanelUI_:FindById("skillTitle"):SetText("技能 - " .. charName)
    skillPanelUI_:FindById("skillPoints"):SetText("技能点: " .. points)

    local container = skillPanelUI_:FindById("skillListContainer")

    -- 检查是否需要重建（角色切换时技能数量/内容变化）
    local needRebuild = (skillPanelCharCache_ ~= currentCharacter_)
    if needRebuild then
        skillPanelCharCache_ = currentCharacter_
        container:RemoveAllChildren()
    end

    -- 首次构建或角色切换时创建节点
    if needRebuild then
        for idx, skill in ipairs(skills) do
            local curData = skill.levelData[skill.level]
            local statText = BuildSkillStatText_(curData)

            local skillRow = UI.Panel {
                id = "skillRow_" .. idx,
                width = "48%",
                backgroundColor = { 30, 40, 60, 200 },
                borderRadius = 5,
                padding = 6,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        marginBottom = 2,
                        children = {
                            UI.Label { text = skill.name, fontSize = 11, fontColor = { 220, 240, 255, 255 } },
                            UI.Label { text = "[" .. skill.key .. "]", fontSize = 9, fontColor = { 255, 220, 100, 220 } },
                        }
                    },
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 4,
                        marginBottom = 2,
                        children = {
                            UI.Label { id = "skillLv_" .. idx, text = "Lv." .. skill.level .. "/" .. skill.maxLevel, fontSize = 10, fontColor = { 180, 220, 200, 220 } },
                            UI.Button {
                                id = "skillMinus_" .. idx,
                                text = "-",
                                fontSize = 10,
                                width = 33, height = 28,
                                disabled = (skill.level <= 1),
                                backgroundColor = (skill.level > 1) and { 200, 80, 80, 220 } or { 80, 60, 60, 150 },
                                textColor = { 255, 255, 255, 255 },
                                hoverBackgroundColor = { 220, 100, 100, 255 },
                                pressedBackgroundColor = { 160, 50, 50, 255 },
                                paddingHorizontal = 6,
                                paddingVertical = 2,
                                onClick = function(self)
                                    if skill.level > 1 then
                                        skill.level = skill.level - 1
                                        skillPoints_[currentCharacter_] = skillPoints_[currentCharacter_] + 1
                                        RefreshSkillPanelUI()
                                    end
                                end,
                            },
                            UI.Button {
                                id = "skillPlus_" .. idx,
                                text = "+",
                                fontSize = 10,
                                width = 33, height = 28,
                                disabled = (skill.level >= skill.maxLevel or points <= 0),
                                backgroundColor = (skill.level < skill.maxLevel and points > 0) and { 60, 180, 100, 220 } or { 60, 80, 60, 150 },
                                textColor = { 255, 255, 255, 255 },
                                hoverBackgroundColor = { 80, 200, 120, 255 },
                                pressedBackgroundColor = { 40, 140, 70, 255 },
                                paddingHorizontal = 6,
                                paddingVertical = 2,
                                onClick = function(self)
                                    if skill.level < skill.maxLevel and skillPoints_[currentCharacter_] > 0 then
                                        skill.level = skill.level + 1
                                        skillPoints_[currentCharacter_] = skillPoints_[currentCharacter_] - 1
                                        RefreshSkillPanelUI()
                                    end
                                end,
                            },
                        }
                    },
                    UI.Label { id = "skillStat_" .. idx, text = statText, fontSize = 9, fontColor = { 150, 220, 180, 200 } },
                    UI.Label { text = skill.desc, fontSize = 8, fontColor = { 160, 180, 200, 170 }, marginTop = 1 },
                }
            }
            container:AddChild(skillRow)
        end
    else
        -- 仅更新动态内容，不重建节点（避免闪烁）
        for idx, skill in ipairs(skills) do
            local curData = skill.levelData[skill.level]
            local statText = BuildSkillStatText_(curData)

            container:FindById("skillLv_" .. idx):SetText("Lv." .. skill.level .. "/" .. skill.maxLevel)
            container:FindById("skillStat_" .. idx):SetText(statText)

            local minusBtn = container:FindById("skillMinus_" .. idx)
            minusBtn:SetDisabled(skill.level <= 1)
            minusBtn:SetBackgroundColor((skill.level > 1) and { 200, 80, 80, 220 } or { 80, 60, 60, 150 })

            local plusBtn = container:FindById("skillPlus_" .. idx)
            plusBtn:SetDisabled(skill.level >= skill.maxLevel or points <= 0)
            plusBtn:SetBackgroundColor((skill.level < skill.maxLevel and points > 0) and { 60, 180, 100, 220 } or { 60, 80, 60, 150 })
        end
    end
end

--- 显示ESC离开确认弹窗（UI版）
function ShowEscPopupUI()
    if not escPopupUI_ then return end
    -- 更新当前区域名称
    local areaConfig = WorldMap.GetCurrentArea() and LevelConfig.GetArea(WorldMap.GetCurrentArea())
    local areaName = areaConfig and areaConfig.name or "未知区域"
    escPopupUI_:FindById("escAreaName"):SetText("当前区域: " .. areaName)
    escPopupUI_:Show()
end

--- 切换技能面板显示
function ToggleSkillPanel()
    showSkillPanel_ = not showSkillPanel_
    if showSkillPanel_ then
        showInventory_ = false
        if inventoryPanelUI_ then inventoryPanelUI_:Hide() end
        RefreshSkillPanelUI()
        skillPanelUI_:Show()
    else
        skillPanelUI_:Hide()
    end
end

-- ============================================================================
-- UI面板：背包面板（支持鼠标/触屏交互）
-- ============================================================================
function CreateInventoryPanelUI()
    inventoryPanelUI_ = UI.Panel {
        id = "invPanelRoot",
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        onClick = function() ToggleInventoryPanel() end,
        children = {
            UI.Panel {
                id = "invPanelCard",
                width = 380,
                backgroundColor = { 15, 20, 40, 240 },
                borderRadius = 12,
                borderWidth = 2,
                borderColor = { 100, 160, 255, 180 },
                padding = 16,
                onClick = function() end,  -- 阻止冒泡到遮罩
                children = {
                    -- 标题
                    UI.Label { text = "背包", fontSize = 20, fontColor = { 180, 220, 255, 255 }, marginBottom = 8, alignSelf = "center" },
                    -- 分隔线
                    UI.Panel { width = "100%", height = 1, backgroundColor = { 80, 120, 200, 120 }, marginBottom = 10 },
                    -- 物品容器
                    UI.Panel { id = "invItemsContainer", width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 8, justifyContent = "center", minHeight = 100 },
                    -- 底部关闭按钮
                    UI.Panel {
                        width = "100%", marginTop = 12,
                        justifyContent = "center", alignItems = "center",
                        children = {
                            UI.Button {
                                text = "关闭 (B)",
                                variant = "secondary",
                                onClick = function(self)
                                    ToggleInventoryPanel()
                                end,
                            }
                        }
                    },
                }
            }
        }
    }
    inventoryPanelUI_:Hide()
end

--- 刷新背包面板内容
function RefreshInventoryPanelUI()
    if not inventoryPanelUI_ then return end
    local container = inventoryPanelUI_:FindById("invItemsContainer")
    container:RemoveAllChildren()

    if #inventoryItems_ == 0 then
        container:AddChild(UI.Label {
            text = "背包空空如也...",
            fontSize = 14,
            fontColor = { 120, 140, 180, 180 },
            alignSelf = "center",
        })
        return
    end

    local iconSymbols = {
        potion = "药", crystal = "晶", heart = "心",
        shard = "碎", cloak = "披", rune = "符",
    }
    local iconColors = {
        potion = { 255, 100, 100, 255 },
        crystal = { 100, 180, 255, 255 },
        heart = { 200, 50, 255, 255 },
        shard = { 150, 220, 255, 255 },
        cloak = { 100, 200, 150, 255 },
        rune = { 255, 200, 80, 255 },
    }

    for _, item in ipairs(inventoryItems_) do
        local color = iconColors[item.icon] or { 200, 200, 200, 255 }
        local symbol = iconSymbols[item.icon] or "?"

        local slot = UI.Panel {
            width = 64, height = 80,
            alignItems = "center",
            justifyContent = "center",
            children = {
                -- 格子背景
                UI.Panel {
                    width = 56, height = 56,
                    backgroundColor = { 40, 50, 80, 200 },
                    borderRadius = 6,
                    borderWidth = 1,
                    borderColor = { 80, 120, 180, 150 },
                    justifyContent = "center",
                    alignItems = "center",
                    children = {
                        UI.Label { text = symbol, fontSize = 22, fontColor = color },
                        -- 数量角标
                        (item.count > 1) and UI.Label {
                            text = "x" .. item.count,
                            fontSize = 10,
                            fontColor = { 255, 255, 200, 255 },
                            position = "absolute",
                            bottom = 2, right = 4,
                        } or nil,
                    }
                },
                -- 物品名
                UI.Label { text = item.name, fontSize = 10, fontColor = { 200, 220, 255, 220 }, marginTop = 2 },
            }
        }
        container:AddChild(slot)
    end
end

--- 切换背包面板显示
function ToggleInventoryPanel()
    showInventory_ = not showInventory_
    if showInventory_ then
        showSkillPanel_ = false
        if skillPanelUI_ then skillPanelUI_:Hide() end
        RefreshInventoryPanelUI()
        inventoryPanelUI_:Show()
    else
        inventoryPanelUI_:Hide()
    end
end

-- ============================================================================
-- [已移除] 旧NanoVG面板代码已由UI系统替代（见 CreateSkillPanelUI / CreateInventoryPanelUI）
-- ============================================================================

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
-- 旧切图编辑器（已由 SpriteEditor.lua 模块替代，保留空函数避免引用错误）
-- ============================================================================
function DrawSpriteEditor(width, height)
end

--[[ 旧编辑器代码已移至 SpriteEditor.lua 模块
    -- 半透明黑底
    nvgBeginPath(nvg_)
    nvgRect(nvg_, 0, 0, width, height)
    nvgFillColor(nvg_, nvgRGBA(0, 0, 0, 200))
    nvgFill(nvg_)

    -- 获取当前动画的图片（根据当前角色，与editorAnimNames_对应）
    local animImages
    if currentCharacter_ == 2 then
        animImages = { img2Idle_, img2Run_, img2Jump_, img2Attack_, img2Block_, img2Burst_, img2Heal_, img2Crouch_, img2CrouchWalk_, img2Hit_ }
    else
        animImages = { imgIdle_, imgRun_, imgJump_, imgAttack_, imgBlock_, imgCharge_, imgHeal_, imgCrouch_, imgCrouchWalk_, imgHit_ }
    end
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
--]]

-- ============================================================================
-- UI 说明
-- ============================================================================
function CreateInstructions()
    -- 使用简单的文字说明
end
