-- ============================================================================
-- GameConfig.lua - 游戏常量定义
-- 所有不变的配置集中管理，各模块通过 require("GameConfig") 引用
-- ============================================================================

local C = {}

-- 渲染/视口
C.SCREEN_WIDTH = 1280
C.SCREEN_HEIGHT = 720
C.PIXELS_PER_UNIT = 60

-- 物理
C.GRAVITY = 25.0
C.PLAYER_SPEED = 6.0
C.PLAYER_JUMP_SPEED = 13.0
C.PLAYER_RADIUS = 0.4
C.HANG_GRAVITY_SCALE = 0.125
C.MAP_HALF_WIDTH = 30.0

-- 跳跃手感优化（Celeste 风格）
C.COYOTE_TIME = 0.1          -- 土狼时间（离开地面后仍可跳跃的宽限期）
C.JUMP_BUFFER_TIME = 0.1     -- 跳跃缓冲（落地前按键的有效窗口）
C.VAR_JUMP_TIME = 0.2        -- 可变跳跃持续时间（此窗口内松手截断上升）
C.JUMP_CUT_MULT = 0.75       -- 松手时保留75%上升速度（最短跳≈2m）
C.JUMP_CUT_GRAVITY = 1.0     -- 截断后正常重力（不额外加速下落）

-- 序列帧
C.SPRITE_COLS = 4
C.SPRITE_ROWS = 3
C.SPRITE_FRAMES = 12

-- 动画帧率
C.ANIM_FPS = 8
C.ANIM_FPS_RUN = 20
C.ANIM_FPS_ATTACK = 12
C.ANIM_FPS_BLOCK = 8
C.ANIM_FPS_CHARGE = 6
C.ANIM_FPS_HIT = 12

-- 动画状态名
C.ANIM_IDLE = "idle"
C.ANIM_RUN = "run"
C.ANIM_JUMP = "jump"
C.ANIM_ATTACK = "attack"
C.ANIM_BLOCK = "block"
C.ANIM_CHARGE = "charge"
C.ANIM_HEAL = "heal"
C.ANIM_CROUCH = "crouch"
C.ANIM_CROUCH_WALK = "crouch_walk"
C.ANIM_HIT = "hit"

-- 蓄力冰晶
C.CHARGE_MAX_DURATION = 3.0
C.ICE_CRYSTAL_MIN_DIST = 2.0
C.ICE_CRYSTAL_MAX_DIST = 10.0
C.ICE_CRYSTAL_LIFETIME = 2.5
C.ICE_CRYSTAL_COUNT = 7
C.ICE_CRYSTAL_HEIGHT = 2.5

-- 治愈技能
C.HEAL_DURATION = 1.2
C.HEAL_COOLDOWN = 3.0

-- 潜行
C.CROUCH_SPEED = 2.5
C.ANIM_FPS_CROUCH = 8
C.HIT_STUN_DURATION = 0.1

-- 蹲下帧映射
C.CROUCH_FRAME_MAP_1 = { 0, 1, 2, 3, 7, 11 }   -- 角色1
C.CROUCH_FRAME_MAP_2 = { 0, 1, 2, 3, 10, 11 }   -- 角色2
C.CROUCH_ENTER_END = 4
C.CROUCH_LOOP_START = 5
C.CROUCH_LOOP_END = 6

-- 滞空
C.HANG_COOLDOWN_TIME = 0.5
C.WING_SHATTER_DURATION = 0.35

-- 投射物
C.PROJECTILE_SPEED = 10.0
C.PROJECTILE_LIFETIME = 3.0

-- 技能伤害/消耗（可在GM控制台中运行时修改）
C.PROJECTILE_DAMAGE = 3
C.CHARGE_MP_COST = 30
C.CHARGE_DAMAGE = 10
C.CHARGE_FREEZE_DURATION = 2.0
C.HEAL_MP_COST = 20
C.HEAL_HP_RESTORE = 20
C.BLOCK_MP_PER_SEC = 5

-- 角色2技能常量
C.CHAR2_MELEE_DAMAGE = 5
C.CHAR2_MELEE_RANGE = 2.0
C.CHAR2_DASH_DAMAGE = 10
C.CHAR2_BLEED_DURATION = 5.0
C.CHAR2_BLEED_DPS = 1
C.CHAR2_DASH_MIN_DIST = 3.5
C.CHAR2_DASH_MAX_DIST = 12.0
C.CHAR2_DASH_SPEED = 15.0

-- 吸血buff
C.LIFESTEAL_DURATION = 10.0
C.LIFESTEAL_RATIO = 0.5

-- ============================================================================
-- 角色策略（CharacterStrategy）
-- 每种策略定义：默认角色、是否允许切换、可用角色列表
-- ============================================================================
C.CharacterStrategy = {
    -- 正常关卡：固定角色3（蓝白），禁止切换
    normal = {
        defaultChar = 3,
        allowSwitch = false,
        availableChars = { 3 },
    },
    -- 番外篇：默认角色1（冰法师），允许切换全部角色
    sideStory = {
        defaultChar = 1,
        allowSwitch = true,
        availableChars = { 1, 2, 3 },
    },
}

return C
