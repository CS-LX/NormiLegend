-- ============================================================================
-- GameState.lua - 共享可变状态
-- 所有模块通过 require("GameState") 引用同一个表实例
-- 字段命名保持与原 local 变量一致（去掉尾部下划线）
-- ============================================================================

local C = require("GameConfig")

local S = {}

-- 页面/菜单状态
S.showTitleScreen = true
S.showMainMenu = false
S.titleVideoPlayer = nil
S.titleUIRoot = nil
S.mainMenuUIRoot = nil
S.enteredGameFromChapterSelect = false  -- 从章节选择进入游戏世界（番外篇），ESC返回章节选择

-- 引擎对象
S.scene = nil          ---@type Scene
S.cameraNode = nil     ---@type Node
S.physicsWorld = nil
S.nvg = nil

-- 玩家物理
S.playerNode = nil     ---@type Node
S.playerBody = nil     ---@type RigidBody2D
S.footSensor = nil
S.onGround = false
S.groundContactCount = 0
S.facingRight = true
S.isHanging = false
S.hangCooldown = 0
S.wingShatterTimer = 0

-- 动画
S.currentAnim = C.ANIM_IDLE
S.animFrame = 0
S.animTimer = 0.0
S.attackTimer = 0.0
S.isAttacking = false
S.isBlocking = false
S.blockTimer = 0.0

-- 蓄力
S.isCharging = false
S.chargeTimer = 0.0
S.chargeReleased = false
S.iceCrystals = {}

-- 治愈
S.isHealing = false
S.healTimer = 0.0
S.healCooldownTimer = 0.0

-- 吸血buff
S.lifestealBuffTimer = 0.0

-- 潜行
S.isCrouching = false
S.crouchPhase = "loop"

-- 受击
S.isHit = false
S.hitStunTimer = 0.0

-- 角色属性
S.charStats = {
    [1] = { hp = 150, maxHP = 150, mp = 80, maxMP = 80 },
    [2] = { hp = 200, maxHP = 200, mp = 100, maxMP = 100 },
}
S.playerHP = 150
S.playerMaxHP = 150
S.playerMP = 80
S.playerMaxMP = 80
S.mpRegenTimer = 0.0

-- 当前角色 (1=冰法师, 2=黑红角娘)
S.currentCharacter = 1

-- 技能/背包面板
S.showInventory = false
S.showSkillPanel = false
S.skillPanelSelected = 1
S.skillPanelUI = nil
S.inventoryPanelUI = nil
S.escPopupUI = nil
S.skillPanelCharCache = nil

-- 技能点
S.skillPoints = { [1] = 3, [2] = 3 }

-- 背包
S.inventoryItems = {}

-- 技能数据
S.skillList = {
    { name = "普通攻击·冰晶术", key = "J", level = 1, maxLevel = 3, desc = "发射冰晶弹，命中造成伤害", cooldown = 0, mp = 0,
      levelData = { {dmg=3,mp=0}, {dmg=4,mp=0}, {dmg=5,mp=0} } },
    { name = "雪崩", key = "Q", level = 1, maxLevel = 3, desc = "蓄力释放冰晶群，命中敌人冰冻2秒", cooldown = 0, mp = 30,
      levelData = { {dmg=10,mp=30}, {dmg=12,mp=30}, {dmg=14,mp=30} } },
    { name = "治愈术", key = "E", level = 1, maxLevel = 3, desc = "消耗魔力回复生命值", cooldown = 3, mp = 20,
      levelData = { {heal=20,mp=20,cd=3}, {heal=25,mp=20,cd=3}, {heal=30,mp=20,cd=3} } },
    { name = "格挡", key = "右键", level = 1, maxLevel = 3, desc = "举盾格挡，减少受到的伤害", cooldown = 0, mp = 5,
      levelData = { {reduce=0.40,mpSec=5}, {reduce=0.45,mpSec=5}, {reduce=0.50,mpSec=5} } },
}

S.skillList2 = {
    { name = "普通攻击·镰刀斩", key = "J", level = 1, maxLevel = 3, desc = "近战挥砍，造成伤害", cooldown = 0, mp = 0,
      levelData = { {dmg=5,mp=0}, {dmg=6,mp=0}, {dmg=7,mp=0} } },
    { name = "蝴蝶化身", key = "Q", level = 1, maxLevel = 3, desc = "化蝶突进，路径敌人流血5秒", cooldown = 0, mp = 30,
      levelData = { {dmg=10,mp=30}, {dmg=12,mp=30}, {dmg=14,mp=30} } },
    { name = "蝶之加护", key = "E", level = 1, maxLevel = 3, desc = "消耗20MP回复HP并附加10s吸血buff(50%)", cooldown = 3, mp = 20,
      levelData = { {heal=10,mp=20,cd=3,lifesteal=10}, {heal=15,mp=20,cd=3,lifesteal=10}, {heal=20,mp=20,cd=3,lifesteal=10} } },
    { name = "格挡", key = "右键", level = 1, maxLevel = 3, desc = "镰刀格挡，减少受到的伤害", cooldown = 0, mp = 5,
      levelData = { {reduce=0.40,mpSec=5}, {reduce=0.45,mpSec=5}, {reduce=0.50,mpSec=5} } },
}

-- 注意: 技能数值直接存放在 GameConfig (C.*) 上，GM控制台直接修改 C.*
-- Combat.lua 等模块通过 require("GameConfig") 读取，不再在此处建副本

-- 角色2突进
S.isDashing = false
S.dashTimer = 0.0
S.dashStartX = 0.0
S.dashDir = 1
S.dashTargetDist = 2.0
S.dashHitEnemies = {}

-- NanoVG 纹理句柄
S.imgIdle = -1
S.imgRun = -1
S.imgJump = -1
S.imgAttack = -1
S.imgBlock = -1
S.imgCharge = -1
S.imgHeal = -1
S.imgCrouch = -1
S.imgCrouchWalk = -1
S.imgHit = -1
-- 角色2纹理
S.img2Idle = -1
S.img2Run = -1
S.img2Jump = -1
S.img2Attack = -1
S.img2Crouch = -1
S.img2CrouchWalk = -1
S.img2Heal = -1
S.img2Hit = -1
S.img2Burst = -1
S.img2Block = -1
-- 头像
S.imgAvatar1 = nil
S.imgAvatar2 = nil
-- 技能图标
S.iconChar1Q = nil
S.iconChar1E = nil
S.iconChar2Q = nil
S.iconChar2E = nil
-- 背景
S.imgBackground = -1
-- 区域平台/地面图片
S.imgPlatformArea = -1
S.imgGroundArea = -1
-- 视差背景
S.parallaxLayers = {}

-- 图片尺寸
S.imgWidth = 1029
S.imgHeight = 768

-- 平台/投射物
S.platforms = {}
S.projectiles = {}

-- 延迟发射
S.pendingProjectile = nil
S.projectileDelay = 0.15
S.pendingMeleeHit = nil

-- 虚拟控制
S.joystick = nil
S.btnJump = nil
S.btnAttack = nil
S.btnCharge = nil
S.btnHeal = nil
S.btnBlock = nil
S.jumpButtonTap = false
S.attackButtonTap = false
S.healButtonTap = false
S.skillButtonPanel = nil
S.charSwitchPanel = nil
S.backButton = nil
S.topButtonBar = nil
S.mapBackButton = nil
-- 触屏选关
S.mapTouchPressed = false
S.mapTouchX = 0
S.mapTouchY = 0

-- 调试/编辑
S.debugDraw = false
S.hudHidden = false
S.editorMode = false

-- 动画裁切配置
S.animCropConfig1 = {
    [C.ANIM_IDLE]        = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 5.5 },
    [C.ANIM_RUN]         = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75 },
    [C.ANIM_JUMP]        = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 5.5 },
    [C.ANIM_ATTACK]      = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 6.0 },
    [C.ANIM_BLOCK]       = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 7.0 },
    [C.ANIM_CHARGE]      = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 6.0 },
    [C.ANIM_HEAL]        = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 5.5 },
    [C.ANIM_CROUCH]      = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 5.5 },
    [C.ANIM_CROUCH_WALK] = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 5.5 },
    [C.ANIM_HIT]         = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 5.5 },
}
S.animCropConfig2 = {
    [C.ANIM_IDLE]        = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 6.0 },
    [C.ANIM_RUN]         = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 6.5 },
    [C.ANIM_JUMP]        = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 6.5 },
    [C.ANIM_ATTACK]      = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 7.0 },
    [C.ANIM_BLOCK]       = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 6.0 },
    [C.ANIM_CHARGE]      = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 6.5 },
    [C.ANIM_HEAL]        = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 5.5 },
    [C.ANIM_CROUCH]      = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 5.5 },
    [C.ANIM_CROUCH_WALK] = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 4.5 },
    [C.ANIM_HIT]         = { cropW = 1.00, cropH = 1.00, cropOffX = 0.00, cropOffY = 0.00, offsetX = 0.00, offsetY = 0.75, scale = 5.5 },
}

--- 获取当前角色的动画裁切配置
function S.GetCurrentAnimCropConfig()
    if S.currentCharacter == 2 then return S.animCropConfig2 end
    return S.animCropConfig1
end

return S
