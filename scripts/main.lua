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
local GameConfig = require("GameConfig")
local GameState = require("GameState")
local Renderer = require("Renderer")
local GameUI = require("GameUI")

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
local mainMenuUIRoot_ = nil     -- 主菜单UI根节点（.videoPlayer 存储视频引用）

-- 过场状态（使用全局表避免 local 数量上限）
transition_ = { active = false, timer = 0, onComplete = nil, uiRoot = nil }

---@type Scene
local scene_ = nil
---@type Node
local cameraNode_ = nil
local physicsWorld_ = nil
local nvg_ = nil

-- 玩家相关
local playerNode_ = nil
---@type RigidBody2D
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

    -- 创建字体（香萃等粗宋）
    nvgCreateFont(nvg_, "sans", "Fonts/XiangcuiDengcusong.ttf")

    -- 自定义鼠标指针将在 UI.Init 之后初始化（见下方）

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
            { family = "sans", weights = { normal = "Fonts/XiangcuiDengcusong.ttf" } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 初始化自定义鼠标指针（必须在 UI.Init 之后，使用 UI 的 NVG 上下文）
    require("Cursor").Init()

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
            ShowTransition(function() ShowMainMenu() end)
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
-- 过场画面（界面切换时显示随机图片，持续2秒）
-- ============================================================================
function ShowTransition(onComplete)
    -- 过场系统已禁用，直接执行回调
    if onComplete then onComplete() end
    do return end

    -- 以下为保留代码（禁用状态）
    local images = {
        "image/transition_1.png",
        "image/transition_2.png",
        "image/transition_3.png",
    }
    local chosen = images[math.random(1, 3)]

    transition_.active = true
    transition_.timer = 2.0
    transition_.onComplete = onComplete

    transition_.uiRoot = UI.Panel {
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundImage = chosen,
        backgroundFit = "cover",
    }
    UI.SetRoot(transition_.uiRoot)
end

function UpdateTransition(dt)
    if not transition_.active then return end
    transition_.timer = transition_.timer - dt
    if transition_.timer <= 0 then
        transition_.active = false
        transition_.uiRoot = nil
        local cb = transition_.onComplete
        transition_.onComplete = nil
        if cb then cb() end
    end
end

-- ============================================================================
-- 标题视频页面
-- ============================================================================
function ShowTitleScreen()
    showTitleScreen_ = true

    -- 创建视频播放器（全屏循环播放，透明背景让底层尾帧透出）
    titleVideoPlayer_ = Video.VideoPlayer {
        src = "video/终.mp4",
        width = "100%",
        height = "100%",
        textureWidth = 1920,
        textureHeight = 1080,
        autoPlay = true,
        loop = true,
        muted = false,
        objectFit = "cover",
        backgroundColor = {0, 0, 0, 0},
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
    titleUIRoot_ = UI.Panel {
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = {0, 0, 0, 255},
        children = {
            -- 视频尾帧静态图底层（循环间隙透出尾帧而非黑屏）
            UI.Panel {
                position = "absolute",
                top = 0, left = 0,
                width = "100%", height = "100%",
                backgroundImage = "image/title_last_frame.png",
                backgroundFit = "cover",
            },
            -- 视频层（覆盖在尾帧上方）
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

    -- 过场后进入主菜单
    ShowTransition(function()
        ShowMainMenu()
    end)
end

-- ============================================================================
-- 图层位置编辑器（调试用）
-- ============================================================================
function BuildLayerEditor()
    if layerEditorPanel_ then
        layerEditorPanel_:Destroy()
        layerEditorPanel_ = nil
    end

    -- 切换按钮（始终可见）
    local toggleBtn = UI.Button {
        position = "absolute", bottom = 16, left = 16,
        text = "图层编辑", fontSize = 12,
        fontColor = {255, 255, 255, 220},
        backgroundColor = {0, 0, 0, 180},
        borderRadius = 4,
        paddingLeft = 8, paddingRight = 8,
        paddingTop = 4, paddingBottom = 4,
        onClick = function()
            layerEditorVisible_ = not layerEditorVisible_
            RefreshLayerEditor()
        end,
    }
    mainMenuUIRoot_:AddChild(toggleBtn)
    layerEditorToggle_ = toggleBtn

    -- 编辑面板
    layerEditorPanel_ = UI.Panel {
        id = "layerEditorPanel",
        position = "absolute", bottom = 50, left = 16,
        width = 320, maxHeight = "80%",
        backgroundColor = {0, 0, 0, 200},
        borderRadius = 8,
        paddingTop = 10, paddingBottom = 10,
        paddingLeft = 10, paddingRight = 10,
        flexDirection = "column", gap = 6,
        display = "none",
    }
    mainMenuUIRoot_:AddChild(layerEditorPanel_)
    RefreshLayerEditor()
end

function RefreshLayerEditor()
    if not layerEditorPanel_ then return end
    -- 清空旧内容
    layerEditorPanel_:ClearChildren()

    if not layerEditorVisible_ then
        layerEditorPanel_:SetStyle({ display = "none" })
        return
    end
    layerEditorPanel_:SetStyle({ display = "flex" })

    -- 标题
    layerEditorPanel_:AddChild(UI.Label {
        text = "图层位置编辑器", fontSize = 14,
        fontColor = {255, 255, 255, 255},
        marginBottom = 4,
    })

    -- 为每个图层创建控制行
    for i, layer in ipairs(layerEditorData_) do
        local row = UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 4,
            width = "100%",
        }
        -- 图层名
        row:AddChild(UI.Label {
            text = layer.name, fontSize = 11,
            fontColor = {200, 200, 255, 255},
            width = 55,
        })
        -- top 标签
        row:AddChild(UI.Label { text = "T:", fontSize = 10, fontColor = {180,180,180,255}, width = 14 })
        -- top -
        row:AddChild(UI.Button {
            text = "-", fontSize = 12, width = 22, height = 22,
            backgroundColor = {80, 80, 120, 200}, borderRadius = 3,
            justifyContent = "center", alignItems = "center",
            fontColor = {255,255,255,255},
            onClick = function()
                layerEditorData_[i].top = layerEditorData_[i].top - 0.5
                ApplyLayerEditorPos(i)
                RefreshLayerEditorValues()
            end,
        })
        -- top 值显示
        row:AddChild(UI.Label {
            id = "le_top_" .. i, text = tostring(layer.top), fontSize = 11,
            fontColor = {255,255,255,255}, width = 30, textAlign = "center",
        })
        -- top +
        row:AddChild(UI.Button {
            text = "+", fontSize = 12, width = 22, height = 22,
            backgroundColor = {80, 80, 120, 200}, borderRadius = 3,
            justifyContent = "center", alignItems = "center",
            fontColor = {255,255,255,255},
            onClick = function()
                layerEditorData_[i].top = layerEditorData_[i].top + 0.5
                ApplyLayerEditorPos(i)
                RefreshLayerEditorValues()
            end,
        })
        -- left 标签
        row:AddChild(UI.Label { text = "L:", fontSize = 10, fontColor = {180,180,180,255}, width = 14 })
        -- left -
        row:AddChild(UI.Button {
            text = "-", fontSize = 12, width = 22, height = 22,
            backgroundColor = {80, 120, 80, 200}, borderRadius = 3,
            justifyContent = "center", alignItems = "center",
            fontColor = {255,255,255,255},
            onClick = function()
                layerEditorData_[i].left = layerEditorData_[i].left - 0.5
                ApplyLayerEditorPos(i)
                RefreshLayerEditorValues()
            end,
        })
        -- left 值显示
        row:AddChild(UI.Label {
            id = "le_left_" .. i, text = tostring(layer.left), fontSize = 11,
            fontColor = {255,255,255,255}, width = 30, textAlign = "center",
        })
        -- left +
        row:AddChild(UI.Button {
            text = "+", fontSize = 12, width = 22, height = 22,
            backgroundColor = {80, 120, 80, 200}, borderRadius = 3,
            justifyContent = "center", alignItems = "center",
            fontColor = {255,255,255,255},
            onClick = function()
                layerEditorData_[i].left = layerEditorData_[i].left + 0.5
                ApplyLayerEditorPos(i)
                RefreshLayerEditorValues()
            end,
        })
        layerEditorPanel_:AddChild(row)
    end

    -- 导出按钮
    layerEditorPanel_:AddChild(UI.Button {
        text = "导出数据", fontSize = 12, marginTop = 8,
        width = "100%", height = 28,
        backgroundColor = {60, 100, 180, 220}, borderRadius = 4,
        justifyContent = "center", alignItems = "center",
        fontColor = {255,255,255,255},
        onClick = function() ShowLayerEditorExport() end,
    })
end

function RefreshLayerEditorValues()
    if not layerEditorPanel_ then return end
    for i, layer in ipairs(layerEditorData_) do
        local topLabel = layerEditorPanel_:FindById("le_top_" .. i)
        local leftLabel = layerEditorPanel_:FindById("le_left_" .. i)
        if topLabel then topLabel:SetText(tostring(layer.top)) end
        if leftLabel then leftLabel:SetText(tostring(layer.left)) end
    end
end

function ApplyLayerEditorPos(idx)
    if not mainMenuUIRoot_ then return end
    local layer = layerEditorData_[idx]
    local widget = mainMenuUIRoot_:FindById(layer.id)
    if widget then
        widget:SetStyle({
            top = tostring(layer.top) .. "%",
            left = tostring(layer.left) .. "%",
        })
    end
end

function ShowLayerEditorExport()
    -- 生成可复制的数据文本
    local lines = { "-- 图层位置数据 --" }
    for _, layer in ipairs(layerEditorData_) do
        table.insert(lines, layer.name .. ": top=" .. tostring(layer.top) .. "%, left=" .. tostring(layer.left) .. "%")
    end
    local exportText = table.concat(lines, "\n")

    -- 弹出显示
    if layerEditorExport_ then
        layerEditorExport_:Destroy()
    end
    layerEditorExport_ = UI.Panel {
        position = "absolute", top = "10%", left = "20%",
        width = "60%",
        backgroundColor = {0, 0, 0, 230},
        borderRadius = 10, borderWidth = 1, borderColor = {100, 140, 255, 150},
        paddingTop = 16, paddingBottom = 16,
        paddingLeft = 16, paddingRight = 16,
        flexDirection = "column", gap = 8,
        children = {
            UI.Label {
                text = "复制以下数据发给AI：", fontSize = 13,
                fontColor = {180, 200, 255, 255},
            },
            UI.Panel {
                width = "100%",
                backgroundColor = {30, 30, 50, 255},
                borderRadius = 6,
                paddingTop = 10, paddingBottom = 10,
                paddingLeft = 10, paddingRight = 10,
                children = {
                    UI.Label {
                        text = exportText, fontSize = 11,
                        fontColor = {200, 255, 200, 255},
                    },
                },
            },
            UI.Button {
                text = "关闭", fontSize = 12,
                width = 80, height = 28,
                backgroundColor = {100, 50, 50, 200}, borderRadius = 4,
                justifyContent = "center", alignItems = "center",
                fontColor = {255,255,255,255},
                onClick = function()
                    if layerEditorExport_ then
                        layerEditorExport_:Destroy()
                        layerEditorExport_ = nil
                    end
                end,
            },
        },
    }
    mainMenuUIRoot_:AddChild(layerEditorExport_)
end

-- ============================================================================
-- 主菜单界面（钢琴花园背景 + 右侧功能按钮面板）
-- ============================================================================
function ShowMainMenu()
    showMainMenu_ = true
    mainMenuTime_ = 0

    -- 克莱因蓝半透明色
    local KB = {0, 47, 167, 160}
    local KB_LIGHT = {0, 47, 167, 120}
    local KB_BORDER = {100, 140, 255, 100}

    -- Live2D 图层（从下到上）：背景 → 人物 → 帘子 → 风铃 → 紫藤花 → 钢琴
    -- 所有图层整体向左上偏移，防止右侧/底部露黑边
    local layerBg = UI.Panel {
        id = "l2d_bg",
        position = "absolute", top = "0%", left = "0%",
        width = "104%", height = "104%",
        backgroundImage = "image/主界面背景图/背景.png",
        backgroundFit = "cover",
        pointerEvents = "none",
    }
    local layerChar = UI.Panel {
        id = "l2d_char",
        position = "absolute", top = "0%", left = "-0.5%",
        width = "104%", height = "104%",
        backgroundImage = "image/主界面背景图/人物1.png",
        backgroundFit = "cover",
        pointerEvents = "none",
    }
    local layerCurtain = UI.Panel {
        id = "l2d_curtain",
        position = "absolute", top = "0%", left = "-3%",
        width = "104%", height = "104%",
        backgroundImage = "image/主界面背景图/帘子.png",
        backgroundFit = "cover",
        pointerEvents = "none",
    }
    local layerChime = UI.Panel {
        id = "l2d_chime",
        position = "absolute", top = "0%", left = "-3%",
        width = "104%", height = "104%",
        backgroundImage = "image/主界面背景图/风铃.png",
        backgroundFit = "cover",
        pointerEvents = "none",
    }
    local layerWisteria = UI.Panel {
        id = "l2d_wisteria",
        position = "absolute", top = "0%", left = "-0.5%",
        width = "104%", height = "104%",
        backgroundImage = "image/主界面背景图/紫藤花.png",
        backgroundFit = "cover",
        pointerEvents = "none",
    }
    local layerPiano = UI.Panel {
        id = "l2d_piano",
        position = "absolute", top = "-3%", left = "-3%",
        width = "104%", height = "104%",
        backgroundImage = "image/主界面背景图/钢琴.png",
        backgroundFit = "cover",
        pointerEvents = "none",
    }

    -- 花瓣粒子容器（最前层，钢琴之上、UI之下）
    local petalContainer = UI.Panel {
        id = "l2d_petals",
        position = "absolute", top = 0, left = 0,
        width = "100%", height = "100%",
        pointerEvents = "none",
    }
    -- 创建6个紫色花瓣
    for i = 1, 6 do
        petalContainer:AddChild(UI.Panel {
            id = "petal_" .. i,
            position = "absolute",
            width = 5, height = 5,
            borderRadius = 3,
            backgroundColor = {180, 140, 220, math.random(120, 200)},
            top = tostring(math.random(0, 80)) .. "%",
            left = tostring(math.random(-10, 100)) .. "%",
            pointerEvents = "none",
        })
    end

    -- 右侧功能面板（景深效果目标）
    local menuPanel = UI.Panel {
        id = "mainMenuPanel",
        position = "absolute",
        top = 30, right = 30,
        width = "30%", height = "90%",
        flexDirection = "column",
        gap = 8,
        children = {
            UI.Button {
                width = "100%", height = "30%",
                text = "关卡", fontSize = 22,
                fontColor = {255, 255, 255, 230},
                backgroundColor = KB, borderRadius = 10,
                borderWidth = 1, borderColor = KB_BORDER,
                justifyContent = "center", alignItems = "center",
                rotate = -2,
                onClick = function() EnterGameFromMenu() end,
            },
            UI.Button {
                width = "100%", flexGrow = 1,
                text = "角色", fontSize = 18,
                fontColor = {255, 255, 255, 230},
                backgroundColor = KB, borderRadius = 10,
                borderWidth = 1, borderColor = KB_BORDER,
                justifyContent = "center", alignItems = "center",
                rotate = -2, onClick = function() end,
            },
            UI.Button {
                width = "100%", flexGrow = 1,
                text = "商店", fontSize = 18,
                fontColor = {255, 255, 255, 230},
                backgroundColor = KB, borderRadius = 10,
                borderWidth = 1, borderColor = KB_BORDER,
                justifyContent = "center", alignItems = "center",
                rotate = -2, onClick = function() end,
            },
            UI.Button {
                width = "100%", flexGrow = 1,
                text = "任务", fontSize = 18,
                fontColor = {255, 255, 255, 230},
                backgroundColor = KB, borderRadius = 10,
                borderWidth = 1, borderColor = KB_BORDER,
                justifyContent = "center", alignItems = "center",
                rotate = -2, onClick = function() end,
            },
            UI.Panel {
                width = "100%", flexGrow = 1,
                flexDirection = "row", gap = 8, rotate = -2,
                children = {
                    UI.Button {
                        flexGrow = 1, height = "100%",
                        text = "炼金", fontSize = 16,
                        fontColor = {255, 255, 255, 230},
                        backgroundColor = KB, borderRadius = 10,
                        borderWidth = 1, borderColor = KB_BORDER,
                        justifyContent = "center", alignItems = "center",
                        onClick = function() end,
                    },
                    UI.Button {
                        flexGrow = 1, height = "100%",
                        text = "仓库", fontSize = 16,
                        fontColor = {255, 255, 255, 230},
                        backgroundColor = KB, borderRadius = 10,
                        borderWidth = 1, borderColor = KB_BORDER,
                        justifyContent = "center", alignItems = "center",
                        onClick = function() end,
                    },
                },
            },
        },
    }

    -- 主菜单UI（图层堆叠）
    mainMenuUIRoot_ = UI.Panel {
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        overflow = "hidden",
        children = {
            layerBg,
            layerChar,
            layerCurtain,
            layerChime,
            layerWisteria,
            layerPiano,
            petalContainer,
            menuPanel,
            -- 左上角返回标题按钮
            UI.Button {
                position = "absolute",
                top = 16, left = 16,
                text = "< 返回", fontSize = 14,
                fontColor = {255, 255, 255, 220},
                backgroundColor = {0, 0, 0, 120},
                borderRadius = 6,
                paddingLeft = 12, paddingRight = 12,
                paddingTop = 6, paddingBottom = 6,
                onClick = function()
                    showMainMenu_ = false
                    mainMenuUIRoot_ = nil
                    ShowTransition(function() ShowTitleScreen() end)
                end,
            },
        },
    }
    UI.SetRoot(mainMenuUIRoot_)
    -- 存储引用供动画使用
    mainMenuUIRoot_.menuPanel = menuPanel
    mainMenuUIRoot_.layerBg = layerBg
    mainMenuUIRoot_.layerChar = layerChar
    mainMenuUIRoot_.layerCurtain = layerCurtain
    mainMenuUIRoot_.layerChime = layerChime
    mainMenuUIRoot_.layerWisteria = layerWisteria
    mainMenuUIRoot_.layerPiano = layerPiano
    mainMenuUIRoot_.petalContainer = petalContainer

    -- ===== 图层位置编辑器 =====
    ---@type {name:string, id:string, top:number, left:number}[]
    layerEditorData_ = {
        { name = "背景",    id = "l2d_bg",        top = 0.0, left = 0.0 },
        { name = "人物",    id = "l2d_char",      top = 0.0, left = -0.5 },
        { name = "帘子",    id = "l2d_curtain",   top = 0.0, left = -3.0 },
        { name = "风铃",    id = "l2d_chime",     top = 0.0, left = -3.0 },
        { name = "紫藤花",  id = "l2d_wisteria",  top = 0.0, left = -0.5 },
        { name = "钢琴",    id = "l2d_piano",     top = -3.0, left = -3.0 },
    }
    layerEditorVisible_ = false
    BuildLayerEditor()
end

-- 从主菜单进入关卡选择（游戏主界面）
function EnterGameFromMenu()
    showMainMenu_ = false
    mainMenuUIRoot_ = nil

    -- 过场后切换到游戏界面
    ShowTransition(function()
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
    end)
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

    -- ========== 过场计时器 ==========
    UpdateTransition(dt)

    -- ========== 主菜单 Live2D 动画系统 ==========
    if showMainMenu_ and mainMenuUIRoot_ and mainMenuUIRoot_.menuPanel then
        mainMenuTime_ = (mainMenuTime_ or 0) + dt
        local t = mainMenuTime_

        -- 鼠标视差（各层不同深度）
        local screenW = graphics:GetWidth()
        local screenH = graphics:GetHeight()
        local mx = input.mousePosition.x
        local my = input.mousePosition.y
        local nx = (mx - screenW * 0.5) / (screenW * 0.5)
        local ny = (my - screenH * 0.5) / (screenH * 0.5)

        -- 从编辑器数据读取 base 位置（允许实时调整）
        local edBg   = layerEditorData_ and layerEditorData_[1] or { top = -3.0, left = -3.0 }
        local edChar  = layerEditorData_ and layerEditorData_[2] or { top = -2.0, left = -5.0 }
        local edCurt  = layerEditorData_ and layerEditorData_[3] or { top = -3.0, left = -3.0 }
        local edChime = layerEditorData_ and layerEditorData_[4] or { top = -3.0, left = -3.0 }
        local edWist  = layerEditorData_ and layerEditorData_[5] or { top = -3.0, left = -3.0 }
        local edPiano = layerEditorData_ and layerEditorData_[6] or { top = -3.0, left = -3.0 }

        -- 背景层：增大纵向视差
        local bgOx = -nx * 2
        local bgOy = -ny * 4
        mainMenuUIRoot_.layerBg:SetStyle({
            top = tostring(edBg.top + bgOy * 0.1) .. "%",
            left = tostring(edBg.left + bgOx * 0.1) .. "%",
        })

        -- 人物层：呼吸+微晃头（视差减小）
        local charBreath = math.sin(t * 1.2) * 0.15
        local charHeadSway = math.sin(t * 0.4) * 0.2
        local charParX = -nx * 1.5
        local charParY = -ny * 1
        mainMenuUIRoot_.layerChar:SetStyle({
            top = tostring(edChar.top + charBreath * 0.15 + charParY * 0.04) .. "%",
            left = tostring(edChar.left + charHeadSway * 0.1 + charParX * 0.04) .. "%",
        })

        -- 帘子层：轻微摆动（视差减小）
        local curtainSway = math.sin(t * 0.8) * 0.4 + math.sin(t * 1.3) * 0.2
        local curtainParX = -nx * 2
        local curtainParY = -ny * 1
        mainMenuUIRoot_.layerCurtain:SetStyle({
            top = tostring(edCurt.top + math.sin(t * 0.6) * 0.2 + curtainParY * 0.04) .. "%",
            left = tostring(edCurt.left + curtainSway * 0.25 + curtainParX * 0.04) .. "%",
        })

        -- 风铃层：随风摆动（视差增大，摆动幅度增大）
        local chimeSway = math.sin(t * 1.5) * 1.5 + math.sin(t * 2.3) * 0.8 + math.sin(t * 3.1) * 0.4
        local chimeParX = -nx * 10
        local chimeParY = -ny * 6
        mainMenuUIRoot_.layerChime:SetStyle({
            top = tostring(edChime.top + math.abs(math.sin(t * 1.5)) * 0.6 + chimeParY * 0.12) .. "%",
            left = tostring(edChime.left + chimeSway * 0.5 + chimeParX * 0.12) .. "%",
        })

        -- 紫藤花层：缓慢摆动，幅度加大（多频叠加，自然感）
        local wistSway = math.sin(t * 0.5) * 1.2 + math.sin(t * 0.8) * 0.7 + math.sin(t * 1.2) * 0.3
        local wistParX = -nx * 7
        local wistParY = -ny * 3.5
        mainMenuUIRoot_.layerWisteria:SetStyle({
            top = tostring(edWist.top + math.sin(t * 0.3) * 0.4 + wistParY * 0.1) .. "%",
            left = tostring(edWist.left + wistSway * 0.4 + wistParX * 0.1) .. "%",
        })

        -- 钢琴层：前景（视差减小）
        local pianoParX = -nx * 1.5
        local pianoParY = -ny * 1
        mainMenuUIRoot_.layerPiano:SetStyle({
            top = tostring(edPiano.top + pianoParY * 0.03) .. "%",
            left = tostring(edPiano.left + pianoParX * 0.03) .. "%",
        })

        -- 按钮面板视差
        local panelOx = -nx * 18
        local panelOy = -ny * 4
        mainMenuUIRoot_.menuPanel:SetStyle({
            right = 30 - panelOx,
            top = 30 + panelOy,
        })

        -- 花瓣粒子动画（6个花瓣，向右下飘落）
        if mainMenuUIRoot_.petalContainer then
            for i = 1, 6 do
                local petal = mainMenuUIRoot_.petalContainer:FindById("petal_" .. i)
                if petal then
                    -- 每个花瓣有不同速度和起始相位
                    local speed = 0.8 + (i * 0.3)
                    local phase = i * 1.2
                    -- 水平：向右飘（风向右）
                    local px = ((t * speed * 8 + phase * 30) % 130) - 15
                    -- 垂直：缓慢下落 + 轻微波动
                    local py = ((t * speed * 3 + phase * 20) % 110) - 5
                    local wave = math.sin(t * 2 + phase) * 3
                    petal:SetStyle({
                        left = tostring(px) .. "%",
                        top = tostring(py + wave * 0.5) .. "%",
                        opacity = (py > 90) and 0 or 1,
                    })
                end
            end
        end
    end

    -- ========== 标题页面/主菜单/过场时跳过所有游戏逻辑 ==========
    if showTitleScreen_ or showMainMenu_ or transition_.active then return end

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
            ShowTransition(function() ShowMainMenu() end)
            return
        end

        -- 大地图界面：处理鼠标/触屏点击区域（适配 16:9 letterbox）
        local lbOx, lbOy, lbW, lbH = Renderer.CalcLetterbox(graphics:GetWidth(), graphics:GetHeight())
        local mouseX = input.mousePosition.x - lbOx
        local mouseY = input.mousePosition.y - lbOy
        local clicked = input:GetMouseButtonPress(MOUSEB_LEFT)

        -- 触屏支持：用TouchBegin事件标记检测新触摸
        if not clicked and mapTouchPressed_ then
            mouseX = mapTouchX_ - lbOx
            mouseY = mapTouchY_ - lbOy
            clicked = true
        end
        mapTouchPressed_ = false

        local selectedId = WorldMap.HandleMapInput(mouseX, mouseY, lbW, lbH, clicked)
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
                        x = baseX,
                        groundY = groundY,
                        radius = ((ICE_CRYSTAL_COUNT - 1) / 2) * 0.6,
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

        -- 相机边界钳制：到达地图左右边缘时固定不移动（使用16:9安全区域宽度）
        local _, _, lbW, _ = Renderer.CalcLetterbox(graphics:GetWidth(), graphics:GetHeight())
        local camHalfView = (lbW / PIXELS_PER_UNIT) * 0.5
        local camMinX = -MAP_HALF_WIDTH + camHalfView
        local camMaxX = MAP_HALF_WIDTH - camHalfView
        newX = math.max(camMinX, math.min(camMaxX, newX))

        cameraNode_:SetPosition(Vector3(newX, newY, -10))
    end
end

-- ============================================================================
-- NanoVG 渲染（委托给 Renderer 模块）
-- ============================================================================

--- 将 main.lua 局部变量同步到 GameState 共享表（供 Renderer/GameUI 模块读取）
local function SyncToSharedState()
    local S = GameState
    S.nvg = nvg_
    S.playerNode = playerNode_
    S.cameraNode = cameraNode_
    S.showTitleScreen = showTitleScreen_
    S.showMainMenu = showMainMenu_
    S.isCharging = isCharging_
    S.chargeTimer = chargeTimer_
    S.chargeReleased = chargeReleased_
    S.isHealing = isHealing_
    S.healTimer = healTimer_
    S.currentCharacter = currentCharacter_
    S.currentAnim = currentAnim_
    S.animFrame = animFrame_
    S.facingRight = facingRight_
    S.onGround = onGround_
    S.isHanging = isHanging_
    S.wingShatterTimer = wingShatterTimer_
    S.iceCrystals = iceCrystals_
    S.platforms = platforms_
    S.projectiles = projectiles_
    S.parallaxLayers = parallaxLayers_
    S.imgBackground = imgBackground_
    S.imgPlatformArea = imgPlatformArea_
    S.imgGroundArea = imgGroundArea_
    S.imgIdle = imgIdle_
    S.imgRun = imgRun_
    S.imgJump = imgJump_
    S.imgAttack = imgAttack_
    S.imgBlock = imgBlock_
    S.imgCharge = imgCharge_
    S.imgHeal = imgHeal_
    S.imgCrouch = imgCrouch_
    S.imgCrouchWalk = imgCrouchWalk_
    S.imgHit = imgHit_
    S.img2Idle = img2Idle_
    S.img2Run = img2Run_
    S.img2Jump = img2Jump_
    S.img2Attack = img2Attack_
    S.img2Block = img2Block_
    S.img2Burst = img2Burst_
    S.img2Heal = img2Heal_
    S.img2Crouch = img2Crouch_
    S.img2CrouchWalk = img2CrouchWalk_
    S.img2Hit = img2Hit_
    S.imgAvatar1 = imgAvatar1_
    S.imgAvatar2 = imgAvatar2_
    S.iconChar1Q = iconChar1Q_
    S.iconChar1E = iconChar1E_
    S.iconChar2Q = iconChar2Q_
    S.iconChar2E = iconChar2E_
    S.imgWidth = imgWidth_
    S.imgHeight = imgHeight_
    S.playerHP = playerHP_
    S.playerMaxHP = playerMaxHP_
    S.playerMP = playerMP_
    S.playerMaxMP = playerMaxMP_
    S.lifestealBuffTimer = lifestealBuffTimer_
    S.debugDraw = debugDraw_
    S.editorMode = editorMode_
    S.showSkillPanel = showSkillPanel_
    S.showInventory = showInventory_
    S.skillPanelUI = skillPanelUI_
    S.inventoryPanelUI = inventoryPanelUI_
    S.escPopupUI = escPopupUI_
    S.skillPoints = skillPoints_
    S.skillList = skillList_
    S.skillList2 = skillList2_
    S.inventoryItems = inventoryItems_
    S.skillPanelCharCache = skillPanelCharCache_
end

function HandleRender(eventType, eventData)
    if nvg_ == nil then return end
    SyncToSharedState()
    Renderer.HandleRender(eventType, eventData)
end


-- ============================================================================
-- 渲染函数代理（实际实现在 Renderer.lua）
-- 保留全局函数名以兼容其他模块的调用
-- ============================================================================
function PhysicsToScreen(physX, physY, camX, camY)
    return Renderer.PhysicsToScreen(physX, physY, camX, camY)
end

function DrawBackground(width, height, camX)
    Renderer.DrawBackground(width, height, camX)
end

function DrawPlatforms(width, height, camX, camY)
    Renderer.DrawPlatforms(width, height, camX, camY)
end

function DrawProjectiles(width, height, camX, camY)
    Renderer.DrawProjectiles(width, height, camX, camY)
end

function DrawChargeEffect(width, height, camX, camY)
    Renderer.DrawChargeEffect(width, height, camX, camY)
end

function DrawChargeEffectChar2(width, height, camX, camY)
    Renderer.DrawChargeEffectChar2(width, height, camX, camY)
end

function DrawHealEffect(width, height, camX, camY)
    Renderer.DrawHealEffect(width, height, camX, camY)
end

function DrawIceCrystals(width, height, camX, camY)
    Renderer.DrawIceCrystals(width, height, camX, camY)
end

function DrawPlayer(width, height, camX, camY)
    Renderer.DrawPlayer(width, height, camX, camY)
end

function DrawWingsEffect(cx, cy, playerSize)
    Renderer.DrawWingsEffect(cx, cy, playerSize)
end

function DrawSpriteFrame(img, frame, cx, cy, size, flipH)
    Renderer.DrawSpriteFrame(img, frame, cx, cy, size, flipH)
end

function DrawHPMPBars(width, height)
    Renderer.DrawHPMPBars(width, height)
end

function DrawDebugInfo(width, height)
    Renderer.DrawDebugInfo(width, height)
end

function DrawSpriteEditor(width, height)
    -- 已由 SpriteEditor.lua 模块替代
end

-- ============================================================================
-- UI 面板代理（实际实现在 GameUI.lua）
-- ============================================================================
function CreateSkillPanelUI()
    GameUI.CreateSkillPanelUI()
    skillPanelUI_ = GameState.skillPanelUI
end

function BuildSkillStatText_(curData)
    return GameUI.BuildSkillStatText(curData)
end

function RefreshSkillPanelUI()
    SyncToSharedState()
    GameUI.RefreshSkillPanelUI()
    -- 同步回变更
    skillPanelCharCache_ = GameState.skillPanelCharCache
end

function ShowEscPopupUI()
    SyncToSharedState()
    GameUI.ShowEscPopupUI()
end

function ToggleSkillPanel()
    SyncToSharedState()
    GameUI.ToggleSkillPanel()
    -- 同步回变更
    showSkillPanel_ = GameState.showSkillPanel
    showInventory_ = GameState.showInventory
end

function CreateInventoryPanelUI()
    GameUI.CreateInventoryPanelUI()
    inventoryPanelUI_ = GameState.inventoryPanelUI
end

function RefreshInventoryPanelUI()
    SyncToSharedState()
    GameUI.RefreshInventoryPanelUI()
end

function ToggleInventoryPanel()
    SyncToSharedState()
    GameUI.ToggleInventoryPanel()
    -- 同步回变更
    showInventory_ = GameState.showInventory
    showSkillPanel_ = GameState.showSkillPanel
end

-- ============================================================================
-- UI 说明
-- ============================================================================
function CreateInstructions()
    -- 使用简单的文字说明
end
