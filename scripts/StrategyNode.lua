-- ============================================================================
-- StrategyNode.lua - 节点化策略模式引擎
-- 职责: 节点定义、端口系统、求值、序列化/反序列化
-- 设计原则: OCP (开闭原则) - 新增节点只需在 NODE_TYPES/PORT_DEFS/INSPECTOR_FIELDS/Create/Evaluate 各加一条
-- ============================================================================
-- 节点类型 (针对2D横版动作关卡编辑器):
--   event       : 事件入口 (常驻, 不可删除)
--   value       : 常量数值
--   string      : 常量字符串
--   param       : 引用运行时参数 (playerX, playerHP, time 等)
--   compare     : 比较运算 (>, <, ==, !=, >=, <=)
--   math        : 算术运算 (+, -, *, /, min, max, abs, clamp)
--   logic       : 逻辑运算 (and, or, not)
--   concat      : 字符串拼接
--   branch      : 条件分支 (if condition then A else B)
--   sequence    : 顺序执行多个子节点
--   random      : 随机选择子节点执行 (加权)
--   delay       : 延迟后继续执行
--   repeat_n    : 重复 N 次
--   spawn       : 生成实体 (敌人/道具/特效)
--   move_obj    : 移动/旋转对象 (平台/障碍物变换)
--   set_var     : 设置变量 (修改运行时参数)
--   play_fx     : 播放效果 (音效/震屏/粒子/文字)
--   dialog      : 弹出对话框 (剧情/提示文字)
--   damage      : 造成伤害/治疗
--   win_level   : 过关/失败
-- ============================================================================

local M = {}

-- ============================================================================
-- 节点类型元数据
-- ============================================================================

M.NODE_TYPES = {
    -- === 入口 ===
    event      = { label = "事件入口",   color = {200, 50, 50},   category = "入口",   desc = "逻辑入口 (常驻)", icon = "▶" },

    -- === 数据 ===
    value      = { label = "数值",      color = {110, 160, 200}, category = "数据",   desc = "固定数值常量", icon = "#" },
    string     = { label = "字符串",    color = {180, 130, 200}, category = "数据",   desc = "固定文本常量", icon = "T" },
    param      = { label = "读取变量",  color = {200, 170, 50},  category = "数据",   desc = "读取运行时变量", icon = "$" },

    -- === 条件 ===
    compare    = { label = "比较",      color = {200, 110, 70},  category = "条件",   desc = "比较两个数值", icon = "?" },
    logic      = { label = "逻辑",      color = {170, 90, 190},  category = "条件",   desc = "逻辑与/或/非", icon = "&" },

    -- === 运算 ===
    math       = { label = "数学",      color = {70, 170, 130},  category = "运算",   desc = "数学运算", icon = "+" },
    concat     = { label = "拼接",      color = {150, 140, 200}, category = "运算",   desc = "字符串拼接", icon = ".." },

    -- === 流程控制 ===
    branch     = { label = "条件分支",  color = {210, 150, 50},  category = "流程",   desc = "if/then/else", icon = "◇" },
    sequence   = { label = "顺序执行",  color = {90, 180, 90},   category = "流程",   desc = "按顺序执行", icon = "↓" },
    random     = { label = "随机选择",  color = {180, 100, 180}, category = "流程",   desc = "加权随机", icon = "?" },
    delay      = { label = "延迟",      color = {130, 130, 180}, category = "流程",   desc = "延迟N秒后执行", icon = "⏱" },
    repeat_n   = { label = "重复",      color = {150, 180, 90},  category = "流程",   desc = "重复N次", icon = "↺" },
    break_flow = { label = "中断",      color = {180, 130, 60},  category = "流程",   desc = "中断执行，等待触发器再次触发后继续", icon = "⏸" },

    -- === 动作 (关卡核心) ===
    spawn      = { label = "生成实体",  color = {50, 170, 210},  category = "动作",   desc = "生成敌人/道具/特效", icon = "★" },
    move_obj   = { label = "移动对象",  color = {80, 200, 160},  category = "动作",   desc = "平移/旋转/透明度", icon = "→" },
    set_var    = { label = "设置变量",  color = {200, 180, 80},  category = "动作",   desc = "修改运行时参数", icon = "=" },
    play_fx    = { label = "播放效果",  color = {220, 130, 180}, category = "动作",   desc = "音效/震屏/粒子/提示", icon = "♪" },
    dialog     = { label = "弹出对话",  color = {100, 180, 220}, category = "动作",   desc = "显示剧情/提示文字", icon = "💬" },
    damage     = { label = "伤害/治疗", color = {220, 70, 70},   category = "动作",   desc = "对玩家造成伤害或治疗", icon = "♥" },
    win_level  = { label = "胜负判定",  color = {60, 200, 60},   category = "动作",   desc = "过关成功/失败", icon = "🏆" },
    camera_zoom= { label = "镜头缩放",  color = {100, 160, 220}, category = "动作",   desc = "平滑缩放相机视野", icon = "🔍" },
    modify_item= { label = "修改物品",  color = {220, 180, 50},  category = "动作",   desc = "增减玩家物品数量", icon = "📦" },
    set_ability= { label = "设置能力",  color = {140, 200, 80},  category = "动作",   desc = "启用/禁用玩家能力", icon = "⚡" },
    destroy_self={ label = "销毁自身", color = {180, 60, 60},   category = "动作",   desc = "销毁触发此策略的对象", icon = "💥" },
    teleport_player = { label = "传送玩家", color = {120, 80, 220}, category = "动作", desc = "将玩家传送到指定坐标", icon = "⚡" },
    reset_trigger   = { label = "重置触发器", color = {200, 150, 60}, category = "动作", desc = "重置目标触发器为未触发状态", icon = "↻" },

    -- === 数据(物品) ===
    read_item  = { label = "读取物品",  color = {200, 170, 50},  category = "数据",   desc = "读取玩家物品数量", icon = "🔎" },
}

-- ============================================================================
-- 端口定义
-- ============================================================================

---@alias PortType "flow"|"number"|"boolean"|"string"

M.PORT_DEFS = {
    event = {
        inputs = {},
        outputs = { { name = "▶", type = "flow", field = "outputNode" } },
    },
    value = {
        inputs = {},
        outputs = { { name = "值", type = "number" } },
    },
    string = {
        inputs = {},
        outputs = { { name = "文本", type = "string" } },
    },
    param = {
        inputs = {},
        outputs = { { name = "值", type = "number" } },
    },
    compare = {
        inputs = { { name = "A", type = "number", field = "left" }, { name = "B", type = "number", field = "right" } },
        outputs = { { name = "结果", type = "boolean" } },
    },
    math = {
        inputs = { { name = "A", type = "number", field = "left" }, { name = "B", type = "number", field = "right" } },
        outputs = { { name = "结果", type = "number" } },
    },
    logic = {
        inputs = { { name = "A", type = "boolean", field = "left" }, { name = "B", type = "boolean", field = "right" } },
        outputs = { { name = "结果", type = "boolean" } },
    },
    concat = {
        inputs = { { name = "A", type = "string", field = "left" }, { name = "B", type = "string", field = "right" } },
        outputs = { { name = "结果", type = "string" } },
    },
    branch = {
        inputs = { { name = "▶", type = "flow" }, { name = "条件", type = "boolean", field = "condition" } },
        outputs = { { name = "✓ True", type = "flow", field = "thenNode" }, { name = "✗ False", type = "flow", field = "elseNode" } },
    },
    sequence = {
        inputs = { { name = "▶", type = "flow" } },
        outputs = {},  -- 动态 children
    },
    random = {
        inputs = { { name = "▶", type = "flow" } },
        outputs = {},  -- 动态 children
    },
    delay = {
        inputs = { { name = "▶", type = "flow" }, { name = "秒数", type = "number", field = "duration" } },
        outputs = { { name = "▶", type = "flow", field = "outputNode" } },
    },
    repeat_n = {
        inputs = { { name = "▶", type = "flow" }, { name = "次数", type = "number", field = "count" } },
        outputs = { { name = "循环体", type = "flow", field = "bodyNode" }, { name = "完成后", type = "flow", field = "outputNode" } },
    },
    break_flow = {
        inputs = { { name = "▶", type = "flow" } },
        outputs = { { name = "▶", type = "flow", field = "outputNode" } },
    },
    spawn = {
        inputs = { { name = "▶", type = "flow" }, { name = "X", type = "number", field = "spawnX" }, { name = "Y", type = "number", field = "spawnY" } },
        outputs = { { name = "▶", type = "flow", field = "outputNode" } },
    },
    move_obj = {
        inputs = { { name = "▶", type = "flow" } },
        outputs = { { name = "▶", type = "flow", field = "outputNode" } },
    },
    set_var = {
        inputs = { { name = "▶", type = "flow" }, { name = "新值", type = "number", field = "newValue" } },
        outputs = { { name = "▶", type = "flow", field = "outputNode" } },
    },
    play_fx = {
        inputs = { { name = "▶", type = "flow" } },
        outputs = { { name = "▶", type = "flow", field = "outputNode" } },
    },
    dialog = {
        inputs = { { name = "▶", type = "flow" }, { name = "内容", type = "string", field = "textInput" } },
        outputs = { { name = "▶", type = "flow", field = "outputNode" } },
    },
    damage = {
        inputs = { { name = "▶", type = "flow" }, { name = "数值", type = "number", field = "amount" } },
        outputs = { { name = "▶", type = "flow", field = "outputNode" } },
    },
    win_level = {
        inputs = { { name = "▶", type = "flow" } },
        outputs = {},
    },
    camera_zoom = {
        inputs = { { name = "▶", type = "flow" }, { name = "缩放", type = "number", field = "zoomLevel" } },
        outputs = { { name = "▶", type = "flow", field = "outputNode" } },
    },
    read_item = {
        inputs = {},
        outputs = { { name = "数量", type = "number" } },
    },
    modify_item = {
        inputs = { { name = "▶", type = "flow" }, { name = "数量", type = "number", field = "itemAmount" } },
        outputs = { { name = "▶", type = "flow", field = "outputNode" } },
    },
    set_ability = {
        inputs = { { name = "▶", type = "flow" } },
        outputs = { { name = "▶", type = "flow", field = "outputNode" } },
    },
    destroy_self = {
        inputs = { { name = "▶", type = "flow" } },
        outputs = {},
    },
    teleport_player = {
        inputs = { { name = "▶", type = "flow" }, { name = "X", type = "number", field = "targetX" }, { name = "Y", type = "number", field = "targetY" } },
        outputs = { { name = "▶", type = "flow", field = "outputNode" } },
    },
    reset_trigger = {
        inputs = { { name = "▶", type = "flow" } },
        outputs = { { name = "▶", type = "flow", field = "outputNode" } },
    },
}

-- 端口颜色
M.PORT_COLORS = {
    flow    = {240, 240, 240},
    number  = {100, 200, 140},
    boolean = {220, 140, 80},
    string  = {180, 130, 220},
}

-- ============================================================================
-- 操作符/枚举选项
-- ============================================================================

M.COMPARE_OPS = {
    { id = ">",  label = ">" },
    { id = "<",  label = "<" },
    { id = "==", label = "==" },
    { id = "!=", label = "!=" },
    { id = ">=", label = ">=" },
    { id = "<=", label = "<=" },
}

M.MATH_OPS = {
    { id = "+",     label = "+" },
    { id = "-",     label = "-" },
    { id = "*",     label = "×" },
    { id = "/",     label = "÷" },
    { id = "%",     label = "%" },
    { id = "min",   label = "min" },
    { id = "max",   label = "max" },
    { id = "abs",   label = "abs" },
    { id = "clamp", label = "clamp" },
}

M.LOGIC_OPS = {
    { id = "and", label = "且" },
    { id = "or",  label = "或" },
    { id = "not", label = "非" },
}

-- 生成实体类型
M.SPAWN_TYPES = {
    { id = "enemy_melee",    label = "近战敌人" },
    { id = "enemy_ranged",   label = "远程敌人" },
    { id = "enemy_flying",   label = "飞行敌人" },
    { id = "enemy_boss",     label = "Boss" },
    { id = "item_health",    label = "生命道具" },
    { id = "item_mana",      label = "魔力道具" },
    { id = "item_coin",      label = "金币" },
    { id = "item_key",       label = "钥匙" },
    { id = "fx_explosion",   label = "爆炸特效" },
    { id = "fx_ice",         label = "冰霜特效" },
    { id = "platform_moving",label = "移动平台" },
    { id = "projectile",     label = "投射物" },
}

-- 生成朝向
M.SPAWN_DIRS = {
    { id = "left",  label = "面朝左" },
    { id = "right", label = "面朝右" },
    { id = "auto",  label = "朝向玩家" },
}

-- 效果类型
M.FX_TYPES = {
    { id = "sound",          label = "播放音效" },
    { id = "camera_shake",   label = "相机抖动" },
    { id = "screen_flash",   label = "全屏闪光" },
    { id = "floating_text",  label = "浮动文字" },
    { id = "particle",       label = "粒子效果" },
    { id = "slow_motion",    label = "慢动作" },
}

-- 移动路径类型
M.PATH_TYPES = {
    { id = "none",     label = "无（瞬移）" },
    { id = "linear",   label = "直线" },
    { id = "bezier",   label = "贝塞尔曲线" },
    { id = "circle",   label = "圆形轨迹" },
    { id = "custom",   label = "自定义路径点" },
}

-- 粒子移动方向
M.PARTICLE_DIRS = {
    { id = "up",       label = "向上" },
    { id = "down",     label = "向下" },
    { id = "left",     label = "向左" },
    { id = "right",    label = "向右" },
    { id = "explode",  label = "爆散" },
}

-- 闪光颜色预设
M.FLASH_COLORS = {
    { id = "white",  label = "白色" },
    { id = "red",    label = "红色" },
    { id = "blue",   label = "蓝色" },
    { id = "yellow", label = "黄色" },
    { id = "green",  label = "绿色" },
}

-- 对话类型（旧版兼容，新版使用组件化配置）
M.DIALOG_STYLES = {
    { id = "popup",      label = "居中弹窗" },
    { id = "banner_top", label = "顶部横幅" },
    { id = "subtitle",   label = "底部字幕" },
    { id = "bubble",     label = "气泡对话" },
}

-- 对话持续模式
M.DIALOG_DURATION_MODES = {
    { id = "timed", label = "定时关闭" },
    { id = "click", label = "点击继续" },
}

-- 移动缓动类型
M.EASE_TYPES = {
    { id = "linear",    label = "线性" },
    { id = "easeIn",    label = "加速" },
    { id = "easeOut",   label = "减速" },
    { id = "easeInOut", label = "先加后减" },
}

-- 运行时可读参数
M.RUNTIME_PARAMS = {
    { id = "playerX",       label = "玩家X" },
    { id = "playerY",       label = "玩家Y" },
    { id = "playerHP",      label = "玩家血量" },
    { id = "playerMP",      label = "玩家魔力" },
    { id = "playerSpeedX",  label = "玩家速度X" },
    { id = "playerSpeedY",  label = "玩家速度Y" },
    { id = "playerOnGround",label = "玩家着地" },
    { id = "triggerX",      label = "触发器X" },
    { id = "triggerY",      label = "触发器Y" },
    { id = "enemyCount",    label = "场景敌人数" },
    { id = "time",          label = "已用时间" },
    { id = "hitCount",      label = "被击次数" },
    { id = "killCount",     label = "击杀数" },
    { id = "custom1",       label = "自定义1" },
    { id = "custom2",       label = "自定义2" },
    { id = "custom3",       label = "自定义3" },
    { id = "altar_active",  label = "祭坛开启" },
}

-- 胜负判定类型
M.WIN_TYPES = {
    { id = "win",     label = "过关成功" },
    { id = "fail",    label = "关卡失败" },
    { id = "restart", label = "重新开始" },
}

-- 物品类型
M.ITEM_TYPES = {
    { id = "light_fragment", label = "光的碎片" },
}

-- 物品操作类型
M.ITEM_OPS = {
    { id = "add",    label = "增加" },
    { id = "remove", label = "减少" },
    { id = "set",    label = "设为" },
}

-- 玩家能力类型
M.ABILITY_TYPES = {
    { id = "hang_glide", label = "滞空滑翔" },
}

-- 触发方式（用于 reset_trigger 节点）
M.TRIGGER_METHODS = {
    { id = "keep",     label = "保持不变" },
    { id = "touch",    label = "触碰" },
    { id = "interact", label = "交互" },
    { id = "attack",   label = "攻击" },
    { id = "none",     label = "禁用(设为无)" },
}

-- ============================================================================
-- Inspector 属性定义（每种节点的可编辑属性）
-- ============================================================================

---@alias InspectorFieldType "float"|"int"|"select"|"text"|"bool"

---@class InspectorField
---@field key string 节点上的字段名
---@field label string 显示名
---@field type InspectorFieldType
---@field options? table[]|string {id, label} 选项列表或 M 上的表名 (select类型)
---@field min? number
---@field max? number
---@field step? number
---@field default? any

M.INSPECTOR_FIELDS = {
    value = {
        { key = "value", label = "数值", type = "float", min = -9999, max = 9999, step = 0.1, default = 0 },
    },
    string = {
        { key = "strValue", label = "文本内容", type = "text", default = "" },
    },
    param = {
        { key = "paramName", label = "变量名", type = "select", options = "RUNTIME_PARAMS", default = "playerX" },
    },
    compare = {
        { key = "op", label = "运算符", type = "select", options = "COMPARE_OPS", default = ">" },
    },
    math = {
        { key = "op", label = "运算符", type = "select", options = "MATH_OPS", default = "+" },
    },
    logic = {
        { key = "op", label = "运算符", type = "select", options = "LOGIC_OPS", default = "and" },
    },
    delay = {
        { key = "delaySeconds", label = "延迟(秒)", type = "float", min = 0, max = 60, step = 0.1, default = 1.0 },
    },
    repeat_n = {
        { key = "repeatCount", label = "重复次数", type = "int", min = 1, max = 100, step = 1, default = 3 },
    },
    break_flow = {},
    spawn = {
        { key = "spawnType", label = "实体类型", type = "select", options = "SPAWN_TYPES", default = "enemy_melee" },
        { key = "spawnCount", label = "数量", type = "int", min = 1, max = 20, step = 1, default = 1 },
        { key = "spawnDir", label = "朝向", type = "select", options = "SPAWN_DIRS", default = "auto" },
    },
    move_obj = {
        { key = "targetObjIdx", label = "目标物件", type = "obj_select", default = 0 },
        { key = "pathType", label = "路径类型", type = "select", options = "PATH_TYPES", default = "linear" },
        -- 瞬移模式：目标坐标
        { key = "teleportX", label = "目标X(米)", type = "float", min = -100, max = 100, step = 0.5, default = 0, showWhen = { pathType = "none" } },
        { key = "teleportY", label = "目标Y(米)", type = "float", min = -100, max = 100, step = 0.5, default = 0, showWhen = { pathType = "none" } },
        -- 路径动画模式字段（瞬移时隐藏）
        { key = "pathPoints", label = "路径编辑", type = "path_editor", default = {}, hideWhen = { pathType = "none" } },
        { key = "moveDuration", label = "单程时间(秒)", type = "float", min = 0.1, max = 60, step = 0.1, default = 1.0, hideWhen = { pathType = "none" } },
        { key = "moveEase", label = "缓动", type = "select", options = "EASE_TYPES", default = "easeOut", hideWhen = { pathType = "none" } },
        { key = "moveRoundTrip", label = "往返移动", type = "bool", default = false, hideWhen = { pathType = "none" } },
        { key = "moveLoop", label = "循环执行", type = "bool", default = false, hideWhen = { pathType = "none" } },
        { key = "moveRepeatCount", label = "执行次数", type = "int", min = 1, max = 999, step = 1, default = 1, hideWhen = { pathType = "none" } },
        { key = "rotationDeg", label = "旋转(度)", type = "float", min = -360, max = 360, step = 5, default = 0, hideWhen = { pathType = "none" } },
        { key = "flipByMoveDir", label = "朝向跟随移动方向", type = "bool", default = false, hideWhen = { pathType = "none" } },
        { key = "opacityMode", label = "透明度模式", type = "select", options = {{id="whole",label="整体"},{id="layers",label="按图层"}}, default = "whole" },
        { key = "opacityTarget", label = "目标透明度", type = "float", min = 0, max = 1, step = 0.05, default = 1.0, showWhen = { opacityMode = "whole" } },
        { key = "opacityLayerTargets", label = "图层透明度", type = "layer_opacity_list", default = {}, showWhen = { opacityMode = "layers" } },
        { key = "opacityDuration", label = "渐变时间(秒)", type = "float", min = 0, max = 60, step = 0.1, default = 0.5, hideWhen = { pathType = "none" } },
    },
    set_var = {
        { key = "varName", label = "变量名", type = "select", options = "RUNTIME_PARAMS", default = "custom1" },
        { key = "setMode", label = "方式", type = "select", options = {{id="set",label="设为"},{id="add",label="增加"},{id="mul",label="乘以"}}, default = "set" },
    },
    play_fx = {
        { key = "fxType", label = "效果类型", type = "select", options = "FX_TYPES", default = "sound" },
        -- 播放音效 子参数
        { key = "soundFile", label = "音效文件", type = "audio_select", default = "", showWhen = { fxType = "sound" } },
        { key = "soundVolume", label = "音量", type = "float", min = 0, max = 1, step = 0.05, default = 1.0, showWhen = { fxType = "sound" } },
        -- 相机抖动 子参数
        { key = "shakeDuration", label = "持续时间(秒)", type = "float", min = 0.1, max = 5, step = 0.1, default = 0.3, showWhen = { fxType = "camera_shake" } },
        { key = "shakeIntensity", label = "强度", type = "float", min = 0.1, max = 10, step = 0.1, default = 1.0, showWhen = { fxType = "camera_shake" } },
        -- 全屏闪光 子参数
        { key = "flashColor", label = "闪光颜色", type = "select", options = "FLASH_COLORS", default = "white", showWhen = { fxType = "screen_flash" } },
        { key = "flashDuration", label = "持续时间(秒)", type = "float", min = 0.05, max = 2, step = 0.05, default = 0.2, showWhen = { fxType = "screen_flash" } },
        -- 浮动文字 子参数
        { key = "floatText", label = "文字内容", type = "text", default = "", showWhen = { fxType = "floating_text" } },
        { key = "floatColor", label = "文字颜色", type = "select", options = "FLASH_COLORS", default = "white", showWhen = { fxType = "floating_text" } },
        { key = "floatSize", label = "字号", type = "int", min = 12, max = 72, step = 2, default = 24, showWhen = { fxType = "floating_text" } },
        -- 粒子效果 子参数
        { key = "particleDir", label = "粒子方向", type = "select", options = "PARTICLE_DIRS", default = "up", showWhen = { fxType = "particle" } },
        { key = "particleCount", label = "粒子数量", type = "int", min = 1, max = 100, step = 1, default = 10, showWhen = { fxType = "particle" } },
        { key = "particleSpeed", label = "粒子速度", type = "float", min = 0.1, max = 20, step = 0.1, default = 3.0, showWhen = { fxType = "particle" } },
        -- 慢动作 子参数
        { key = "slowFactor", label = "慢动作倍率", type = "float", min = 0.01, max = 1.0, step = 0.05, default = 0.3, showWhen = { fxType = "slow_motion" } },
        { key = "slowDuration", label = "持续时间(秒)", type = "float", min = 0.1, max = 10, step = 0.1, default = 1.0, showWhen = { fxType = "slow_motion" } },
    },
    dialog = {
        -- inspector 仅保留持续模式 + 编辑器入口
        { key = "dlgDurationMode", label = "持续模式", type = "select", options = "DIALOG_DURATION_MODES", default = "timed" },
        { key = "dlgDuration", label = "显示时间(秒)", type = "float", min = 0.5, max = 30, step = 0.5, default = 3.0, showWhen = { dlgDurationMode = "timed" } },
        { key = "_openEditor", label = "编辑对话内容", type = "action_button", action = "open_dialog_editor" },
    },
    damage = {
        { key = "damageAmount", label = "数值", type = "float", min = -100, max = 100, step = 1, default = 10 },
        { key = "damageIsHeal", label = "治疗模式", type = "bool", default = false },
    },
    win_level = {
        { key = "winType", label = "结果", type = "select", options = "WIN_TYPES", default = "win" },
    },
    camera_zoom = {
        { key = "zoomScale", label = "缩放倍数", type = "float", min = 0.1, max = 5.0, step = 0.1, default = 1.0 },
        { key = "zoomUsePan", label = "平移镜头到中心", type = "bool", default = false },
        { key = "zoomCenterX", label = "镜头中心X(米)", type = "float", min = 0, max = 100, step = 0.5, default = 15.0, showWhen = { zoomUsePan = true } },
        { key = "zoomCenterY", label = "镜头中心Y(米)", type = "float", min = 0, max = 100, step = 0.5, default = 8.75, showWhen = { zoomUsePan = true } },
        { key = "zoomDuration", label = "过渡时间(秒)", type = "float", min = 0, max = 10, step = 0.1, default = 0.5 },
        { key = "zoomEase", label = "缓动", type = "select", options = "EASE_TYPES", default = "easeOut" },
        { key = "zoomAutoRestore", label = "自动恢复", type = "bool", default = false },
        { key = "zoomHoldDuration", label = "持续时间(秒)", type = "float", min = 0, max = 60, step = 0.5, default = 3.0, showWhen = { zoomAutoRestore = true } },
        { key = "zoomRestoreDuration", label = "恢复过渡(秒)", type = "float", min = 0, max = 10, step = 0.1, default = 0.5, showWhen = { zoomAutoRestore = true } },
        { key = "zoomRestoreEase", label = "恢复缓动", type = "select", options = "EASE_TYPES", default = "easeOut", showWhen = { zoomAutoRestore = true } },
    },
    read_item = {
        { key = "itemName", label = "物品类型", type = "select", options = "ITEM_TYPES", default = "light_fragment" },
    },
    modify_item = {
        { key = "itemName", label = "物品类型", type = "select", options = "ITEM_TYPES", default = "light_fragment" },
        { key = "itemOp", label = "操作", type = "select", options = "ITEM_OPS", default = "add" },
    },
    set_ability = {
        { key = "abilityName", label = "能力", type = "select", options = "ABILITY_TYPES", default = "hang_glide" },
        { key = "abilityEnabled", label = "启用", type = "bool", default = true },
    },
    destroy_self = {},
    teleport_player = {
        { key = "targetX", label = "目标X", type = "float", min = 0, max = 200, step = 0.5, default = 15.0 },
        { key = "targetY", label = "目标Y", type = "float", min = 0, max = 200, step = 0.5, default = 8.0 },
    },
    reset_trigger = {
        { key = "resetTargetIdx", label = "目标触发器", type = "obj_select", default = 0 },
        { key = "resetMethod", label = "重置后触发方式", type = "select", options = "TRIGGER_METHODS", default = "keep" },
    },
}

-- ============================================================================
-- 节点创建（工厂函数）
-- ============================================================================

local nextNodeId_ = 1

-- 每种节点的默认字段（除 id/type/x/y 之外的字段）
-- 用 table 驱动代替 if/elseif 链，符合 OCP
local NODE_DEFAULTS = {
    event     = { outputNode = nil },
    value     = { value = 0.0 },
    string    = { strValue = "" },
    param     = { paramName = "playerX" },
    compare   = { op = ">", left = nil, right = nil },
    math      = { op = "+", left = nil, right = nil },
    logic     = { op = "and", left = nil, right = nil },
    concat    = { left = nil, right = nil, separator = "" },
    branch    = { condition = nil, thenNode = nil, elseNode = nil },
    sequence  = { children = {} },
    random    = { children = {}, weights = {} },
    delay     = { delaySeconds = 1.0, duration = nil, outputNode = nil },
    repeat_n  = { repeatCount = 3, count = nil, bodyNode = nil, outputNode = nil },
    break_flow = { outputNode = nil },
    spawn     = { spawnType = "enemy_melee", spawnCount = 1, spawnDir = "auto", spawnX = nil, spawnY = nil, outputNode = nil },
    move_obj  = { targetObjIdx = 0, pathType = "linear", pathPoints = {}, moveDuration = 1.0, moveEase = "easeOut", moveRoundTrip = false, moveLoop = false, moveRepeatCount = 1, rotationDeg = 0, flipByMoveDir = false, opacityMode = "whole", opacityTarget = 1.0, opacityLayerTargets = {}, opacityDuration = 0.5, teleportX = 0, teleportY = 0, outputNode = nil },
    set_var   = { varName = "custom1", setMode = "set", newValue = nil, outputNode = nil },
    play_fx   = { fxType = "sound", soundFile = "", soundVolume = 1.0, shakeDuration = 0.3, shakeIntensity = 1.0, flashColor = "white", flashDuration = 0.2, floatText = "", floatColor = "white", floatSize = 24, particleDir = "up", particleCount = 10, particleSpeed = 3.0, slowFactor = 0.3, slowDuration = 1.0, outputNode = nil },
    dialog    = { dialogText = "你好！", dlgSpeaker = "", dlgDurationMode = "click", dlgDuration = 3.0, dlgBgTexture = "", dlgBgOffsetX = -76, dlgBgOffsetY = -333, dlgBgOpacity = 0.95, dlgBgWidth = 1550, dlgBgHeight = 660, dlgPortraitTexture = "", dlgPortraitOffsetX = -500, dlgPortraitOffsetY = -300, dlgPortraitOpacity = 1.0, dlgPortraitWidth = 610, dlgPortraitHeight = 600, dlgNameOffsetX = -100, dlgNameOffsetY = -140, dlgNameOpacity = 1.0, dlgTextOffsetX = -150, dlgTextOffsetY = -209, dlgTextOpacity = 1.0, dlgNameFontSize = 16, dlgNameFontColor = {255,255,255,255}, dlgNameStrokeW = 0, dlgNameStrokeColor = {0,0,0,255}, dlgTextFontSize = 44, dlgTextFontColor = {0,0,0,255}, dlgTextStrokeW = 1.5, dlgTextStrokeColor = {0,0,0,200}, dlgTextAnim = "typewriter", dlgTextAnimSpeed = 3.0, dlgWholeTexture = "", dlgWholeOffsetX = -100, dlgWholeOffsetY = -318, dlgWholeOpacity = 1.0, dlgWholeWidth = 1600, dlgWholeHeight = 1075, textInput = nil, outputNode = nil },
    damage    = { damageAmount = 10, damageIsHeal = false, amount = nil, outputNode = nil },
    win_level = { winType = "win" },
    camera_zoom = { zoomScale = 1.0, zoomUsePan = false, zoomCenterX = 15.0, zoomCenterY = 8.75, zoomDuration = 0.5, zoomEase = "easeOut", zoomAutoRestore = false, zoomHoldDuration = 3.0, zoomRestoreDuration = 0.5, zoomRestoreEase = "easeOut", zoomLevel = nil, outputNode = nil },
    read_item   = { itemName = "light_fragment" },
    modify_item = { itemName = "light_fragment", itemOp = "add", itemAmount = nil, outputNode = nil },
    set_ability = { abilityName = "hang_glide", abilityEnabled = true, outputNode = nil },
    destroy_self= {},
    teleport_player = { targetX = 15.0, targetY = 8.0, outputNode = nil },
    reset_trigger   = { resetTargetIdx = 0, resetMethod = "keep", outputNode = nil },
}

---@param nodeType string
---@param config? table
---@return table node
function M.Create(nodeType, config)
    config = config or {}
    local node = {
        id = nextNodeId_,
        type = nodeType,
        x = config.x or 0,
        y = config.y or 0,
    }
    nextNodeId_ = nextNodeId_ + 1

    -- 从默认表复制字段（深拷贝 table 类型）
    local defaults = NODE_DEFAULTS[nodeType]
    if defaults then
        for k, v in pairs(defaults) do
            if config[k] ~= nil then
                node[k] = config[k]
            elseif type(v) == "table" then
                -- 深拷贝一层（children/weights 等数组）
                local copy = {}
                for ck, cv in pairs(v) do copy[ck] = cv end
                node[k] = copy
            else
                node[k] = v
            end
        end
    end

    return node
end

function M.ResetIdCounter(maxId)
    nextNodeId_ = (maxId or 0) + 1
end

-- ============================================================================
-- 策略树
-- ============================================================================

function M.CreateTree(config)
    config = config or {}
    local tree = {
        nodes = {},
        rootId = nil,
        params = config.params or {},
    }
    local eventNode = M.Create("event", { x = 100, y = 200 })
    tree.nodes[eventNode.id] = eventNode
    tree.rootId = eventNode.id
    return tree
end

function M.AddNode(tree, node)
    tree.nodes[node.id] = node
end

function M.RemoveNode(tree, nodeId)
    local node = tree.nodes[nodeId]
    if not node or node.type == "event" then return end
    tree.nodes[nodeId] = nil
    -- 清理所有引用（跳过"存储数值但不是节点连接"的字段）
    local skipKeys = { id = true, x = true, y = true, value = true, delaySeconds = true,
        repeatCount = true, spawnCount = true, damageAmount = true, fxIntensity = true,
        moveDuration = true, rotationDeg = true, dialogDuration = true,
        targetObjIdx = true, moveRepeatCount = true, targetX = true, targetY = true,
        itemAmount = true, zoomScale = true, zoomDuration = true,
        soundVolume = true, shakeDuration = true, shakeIntensity = true,
        flashDuration = true, floatSize = true, particleCount = true,
        particleSpeed = true, slowFactor = true, slowDuration = true,
        dlgDuration = true, dlgBgOffsetX = true, dlgBgOffsetY = true, dlgBgOpacity = true,
        dlgBgWidth = true, dlgBgHeight = true, dlgPortraitWidth = true, dlgPortraitHeight = true,
        dlgPortraitOffsetX = true, dlgPortraitOffsetY = true, dlgPortraitOpacity = true,
        dlgNameOffsetX = true, dlgNameOffsetY = true, dlgNameOpacity = true,
        dlgTextOffsetX = true, dlgTextOffsetY = true, dlgTextOpacity = true,
        dlgNameFontSize = true, dlgNameStrokeW = true, dlgTextFontSize = true, dlgTextStrokeW = true,
        dlgTextAnimSpeed = true, dlgWholeOffsetX = true, dlgWholeOffsetY = true,
        dlgWholeOpacity = true, dlgWholeWidth = true, dlgWholeHeight = true }
    for _, n in pairs(tree.nodes) do
        for k, v in pairs(n) do
            if type(v) == "number" and v == nodeId and not skipKeys[k] then
                n[k] = nil
            end
        end
        if n.children then
            for i = #n.children, 1, -1 do
                if n.children[i] == nodeId then
                    table.remove(n.children, i)
                    if n.weights then table.remove(n.weights, i) end
                end
            end
        end
    end
end

-- ============================================================================
-- 端口查询
-- ============================================================================

function M.GetOutputPorts(node)
    local def = M.PORT_DEFS[node.type]
    if not def then return {} end
    local ports = {}
    for _, p in ipairs(def.outputs) do
        table.insert(ports, p)
    end
    if node.type == "sequence" or node.type == "random" then
        for i = 1, #(node.children or {}) do
            table.insert(ports, { name = tostring(i), type = "flow", field = "children", index = i })
        end
        table.insert(ports, { name = "+", type = "flow", field = "children", index = #(node.children or {}) + 1, isAdd = true })
    end
    return ports
end

function M.GetInputPorts(node)
    local def = M.PORT_DEFS[node.type]
    if not def then return {} end
    return def.inputs
end

-- ============================================================================
-- 连接管理
-- ============================================================================

function M.Connect(tree, srcNodeId, srcPort, dstNodeId, dstPort)
    local srcNode = tree.nodes[srcNodeId]
    local dstNode = tree.nodes[dstNodeId]
    if not srcNode or not dstNode then return false end

    if srcPort.type == "flow" then
        if srcPort.field == "children" then
            local children = srcNode.children or {}
            local idx = srcPort.index or (#children + 1)
            if idx > #children then
                table.insert(children, dstNodeId)
                srcNode.children = children
                if srcNode.weights then table.insert(srcNode.weights, 1) end
            else
                children[idx] = dstNodeId
            end
        elseif srcPort.field then
            srcNode[srcPort.field] = dstNodeId
        end
        return true
    end

    if dstPort and dstPort.field then
        dstNode[dstPort.field] = srcNodeId
        return true
    end

    return false
end

function M.Disconnect(tree, nodeId, portField, portIndex)
    local node = tree.nodes[nodeId]
    if not node then return end
    if portField == "children" and portIndex then
        if node.children and node.children[portIndex] then
            table.remove(node.children, portIndex)
            if node.weights then table.remove(node.weights, portIndex) end
        end
    elseif portField then
        node[portField] = nil
    end
end

-- ============================================================================
-- 获取所有连接 (用于渲染)
-- ============================================================================

function M.GetAllConnections(tree)
    local conns = {}
    for id, node in pairs(tree.nodes) do
        local outPorts = M.GetOutputPorts(node)
        for oi, op in ipairs(outPorts) do
            if op.isAdd then goto continueOuter end
            if op.type == "flow" then
                local targetId = nil
                if op.field == "children" and op.index then
                    targetId = node.children and node.children[op.index]
                elseif op.field then
                    targetId = node[op.field]
                end
                if targetId and tree.nodes[targetId] then
                    local dstInputs = M.GetInputPorts(tree.nodes[targetId])
                    local dstIdx = 1
                    for di, dp in ipairs(dstInputs) do
                        if dp.type == "flow" then dstIdx = di; break end
                    end
                    table.insert(conns, { srcNodeId = id, srcPortIdx = oi, dstNodeId = targetId, dstPortIdx = dstIdx, portType = "flow" })
                end
            end
            ::continueOuter::
        end
        local inPorts = M.GetInputPorts(node)
        for ii, ip in ipairs(inPorts) do
            if ip.type ~= "flow" and ip.field then
                local srcId = node[ip.field]
                if srcId and tree.nodes[srcId] then
                    local srcOuts = M.GetOutputPorts(tree.nodes[srcId])
                    local srcIdx = 1
                    for si, sp in ipairs(srcOuts) do
                        if sp.type == ip.type or sp.type == "number" or sp.type == "boolean" or sp.type == "string" then
                            srcIdx = si; break
                        end
                    end
                    table.insert(conns, { srcNodeId = srcId, srcPortIdx = srcIdx, dstNodeId = id, dstPortIdx = ii, portType = ip.type })
                end
            end
        end
    end
    return conns
end

-- ============================================================================
-- 求值引擎
-- ============================================================================

function M.Evaluate(tree, nodeId, context)
    if not nodeId then return nil end
    local node = tree.nodes[nodeId]
    if not node then return nil end
    local t = node.type

    if t == "event" then
        return M.Evaluate(tree, node.outputNode, context)
    elseif t == "value" then
        return node.value
    elseif t == "string" then
        return node.strValue or ""
    elseif t == "param" then
        return (context.params or {})[node.paramName] or 0.0
    elseif t == "read_item" then
        local items = (context.params or {})._items or {}
        return items[node.itemName] or 0
    elseif t == "compare" then
        local l = tonumber(M.Evaluate(tree, node.left, context)) or 0
        local r = tonumber(M.Evaluate(tree, node.right, context)) or 0
        local op = node.op
        if     op == ">"  then return l > r
        elseif op == "<"  then return l < r
        elseif op == "==" then return math.abs(l - r) < 0.0001
        elseif op == "!=" then return math.abs(l - r) >= 0.0001
        elseif op == ">=" then return l >= r
        elseif op == "<=" then return l <= r end
        return false
    elseif t == "math" then
        local l = tonumber(M.Evaluate(tree, node.left, context)) or 0
        local r = tonumber(M.Evaluate(tree, node.right, context)) or 0
        local op = node.op
        if     op == "+" then return l + r
        elseif op == "-" then return l - r
        elseif op == "*" then return l * r
        elseif op == "/" then return r ~= 0 and (l / r) or 0
        elseif op == "%" then return r ~= 0 and (l % r) or 0
        elseif op == "min" then return math.min(l, r)
        elseif op == "max" then return math.max(l, r)
        elseif op == "abs" then return math.abs(l)
        elseif op == "clamp" then return math.max(0, math.min(l, r))
        end
        return 0
    elseif t == "logic" then
        local op = node.op
        if op == "not" then return not M.Evaluate(tree, node.left, context) end
        local l = M.Evaluate(tree, node.left, context)
        local r = M.Evaluate(tree, node.right, context)
        if op == "and" then return (l and r) and true or false
        elseif op == "or" then return (l or r) and true or false end
        return false
    elseif t == "concat" then
        local l = tostring(M.Evaluate(tree, node.left, context) or "")
        local r = tostring(M.Evaluate(tree, node.right, context) or "")
        return l .. (node.separator or "") .. r
    elseif t == "branch" then
        local cond = M.Evaluate(tree, node.condition, context)
        if cond then return M.Evaluate(tree, node.thenNode, context)
        else return M.Evaluate(tree, node.elseNode, context) end
    elseif t == "sequence" then
        local last = nil
        for _, childId in ipairs(node.children or {}) do last = M.Evaluate(tree, childId, context) end
        return last
    elseif t == "random" then
        local children = node.children or {}
        if #children == 0 then return nil end
        local weights = node.weights or {}
        local total = 0
        for i = 1, #children do total = total + (weights[i] or 1) end
        local roll = math.random() * total
        local accum = 0
        for i = 1, #children do
            accum = accum + (weights[i] or 1)
            if roll <= accum then return M.Evaluate(tree, children[i], context) end
        end
        return M.Evaluate(tree, children[#children], context)
    end

    -- 动作节点返回 action 描述
    if t == "spawn" or t == "move_obj" or t == "set_var" or t == "play_fx"
       or t == "dialog" or t == "damage" or t == "win_level"
       or t == "delay" or t == "repeat_n" or t == "teleport_player" then
        return { nodeType = t, node = node }
    end

    return nil
end

--- 执行策略树 (收集所有action)
function M.Execute(tree, runtimeParams)
    if not tree or not tree.rootId then return {} end
    local context = { params = runtimeParams or {} }
    local actions = {}
    M._collectActions(tree, tree.rootId, context, actions)
    return actions
end

function M._collectActions(tree, nodeId, context, actions)
    if not nodeId then return end
    local node = tree.nodes[nodeId]
    if not node then return end
    local t = node.type

    if t == "event" then
        M._collectActions(tree, node.outputNode, context, actions)
    elseif t == "branch" then
        local cond = M.Evaluate(tree, node.condition, context)
        if cond then M._collectActions(tree, node.thenNode, context, actions)
        else M._collectActions(tree, node.elseNode, context, actions) end
    elseif t == "sequence" then
        for _, childId in ipairs(node.children or {}) do
            M._collectActions(tree, childId, context, actions)
        end
    elseif t == "random" then
        local children = node.children or {}
        if #children == 0 then return end
        local weights = node.weights or {}
        local total = 0
        for i = 1, #children do total = total + (weights[i] or 1) end
        local roll = math.random() * total
        local accum = 0
        for i = 1, #children do
            accum = accum + (weights[i] or 1)
            if roll <= accum then M._collectActions(tree, children[i], context, actions); return end
        end
        M._collectActions(tree, children[#children], context, actions)
    elseif t == "repeat_n" then
        -- 重复节点: 将循环体展开 N 次，然后继续完成后端口
        local count = node.count or node.repeatCount or 3
        -- count 可能连接了数据节点
        if type(count) == "number" and tree.nodes[count] then
            count = tonumber(M.Evaluate(tree, count, context)) or 3
        end
        count = math.max(1, math.min(tonumber(count) or 3, 100))  -- 限制上界防死循环
        for _ = 1, count do
            if node.bodyNode then
                M._collectActions(tree, node.bodyNode, context, actions)
            end
        end
        if node.outputNode then
            M._collectActions(tree, node.outputNode, context, actions)
        end
    else
        -- 通用动作节点（OCP: 新增动作节点自动被收集，无需在此维护列表）
        -- 收集自身，对数据端口求值后存入副本
        local resolved = {}
        for k, v in pairs(node) do resolved[k] = v end
        -- 求值所有数据类型的端口输入（field 值可能是连接的节点ID）
        local ports = M.PORT_DEFS[t]
        if ports and ports.inputs then
            for _, inp in ipairs(ports.inputs) do
                if inp.type ~= "flow" and inp.field then
                    local connId = node[inp.field]
                    if connId and type(connId) == "number" and tree.nodes[connId] then
                        resolved[inp.field] = M.Evaluate(tree, connId, context)
                    end
                end
            end
        end
        table.insert(actions, { nodeType = t, node = resolved })
        if node.outputNode then
            M._collectActions(tree, node.outputNode, context, actions)
        end
    end
end

-- ============================================================================
-- 序列化 / 反序列化
-- ============================================================================

function M.Serialize(tree)
    if not tree then return nil end
    local data = { rootId = tree.rootId, params = {}, nodes = {} }
    for _, p in ipairs(tree.params or {}) do
        table.insert(data.params, { name = p.name, value = p.value, label = p.label or p.name })
    end
    for id, node in pairs(tree.nodes) do
        local sn = { id = id, type = node.type, x = node.x or 0, y = node.y or 0 }
        for k, v in pairs(node) do
            if k ~= "id" and k ~= "type" and k ~= "x" and k ~= "y" then
                sn[k] = v
            end
        end
        table.insert(data.nodes, sn)
    end
    return data
end

function M.Deserialize(data)
    if not data then return M.CreateTree() end
    local tree = { nodes = {}, rootId = data.rootId, params = {} }
    for _, p in ipairs(data.params or {}) do
        table.insert(tree.params, { name = p.name, value = p.value, label = p.label or p.name })
    end
    local maxId = 0
    for _, sn in ipairs(data.nodes or {}) do
        local node = {}
        for k, v in pairs(sn) do node[k] = v end
        if node.id > maxId then maxId = node.id end
        -- 确保必要字段
        if node.type == "sequence" and not node.children then node.children = {} end
        if node.type == "random" then
            if not node.children then node.children = {} end
            if not node.weights then node.weights = {} end
        end
        -- 兼容旧数据: gate → move_obj, teleport → move_obj
        if node.type == "gate" then
            node.type = "move_obj"
            node.targetId = node.gateTarget or ""
            node.moveDuration = 0.5
            node.moveEase = "easeOut"
            node.rotationDeg = 0
        elseif node.type == "teleport" then
            node.type = "move_obj"
            node.targetId = "player"
            node.moveDuration = 0
            node.moveEase = "linear"
            node.rotationDeg = 0
        end
        -- 兼容旧数据: move_obj 的 targetId(字符串) → targetObjIdx(索引)
        if node.type == "move_obj" and node.targetId ~= nil and node.targetObjIdx == nil then
            node.targetObjIdx = 0  -- 旧数据无法自动映射索引，需用户重新选择
            node.targetId = nil
            if not node.pathPoints then node.pathPoints = {} end
            if not node.pathType then node.pathType = "linear" end
            if not node.moveRoundTrip then node.moveRoundTrip = false end
            if not node.moveLoop then node.moveLoop = false end
            if not node.moveRepeatCount then node.moveRepeatCount = 1 end
        end
        -- 兼容旧数据: camera_zoom 补充新字段
        if node.type == "camera_zoom" and node.zoomUsePan == nil then
            node.zoomUsePan = false
            node.zoomCenterX = 15.0
            node.zoomCenterY = 8.75
        end
        -- 兼容旧数据: play_fx 补充新子参数默认值
        if node.type == "play_fx" then
            if node.soundFile == nil then node.soundFile = "" end
            if node.soundVolume == nil then node.soundVolume = 1.0 end
            if node.shakeDuration == nil then node.shakeDuration = 0.3 end
            if node.shakeIntensity == nil then node.shakeIntensity = 1.0 end
            if node.flashColor == nil then node.flashColor = "white" end
            if node.flashDuration == nil then node.flashDuration = 0.2 end
            if node.floatText == nil then node.floatText = "" end
            if node.floatColor == nil then node.floatColor = "white" end
            if node.floatSize == nil then node.floatSize = 24 end
            if node.particleDir == nil then node.particleDir = "up" end
            if node.particleCount == nil then node.particleCount = 10 end
            if node.particleSpeed == nil then node.particleSpeed = 3.0 end
            if node.slowFactor == nil then node.slowFactor = 0.3 end
            if node.slowDuration == nil then node.slowDuration = 1.0 end
        end
        tree.nodes[node.id] = node
    end
    -- 确保有 event 节点
    local hasEvent = false
    for _, n in pairs(tree.nodes) do
        if n.type == "event" then hasEvent = true; break end
    end
    if not hasEvent then
        local ev = M.Create("event", { x = 100, y = 200 })
        tree.nodes[ev.id] = ev
        tree.rootId = ev.id
        if ev.id > maxId then maxId = ev.id end
    end
    M.ResetIdCounter(maxId)
    return tree
end

return M
