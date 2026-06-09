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

    -- === 动作 (关卡核心) ===
    spawn      = { label = "生成实体",  color = {50, 170, 210},  category = "动作",   desc = "生成敌人/道具/特效", icon = "★" },
    move_obj   = { label = "移动对象",  color = {80, 200, 160},  category = "动作",   desc = "平移/旋转对象", icon = "→" },
    set_var    = { label = "设置变量",  color = {200, 180, 80},  category = "动作",   desc = "修改运行时参数", icon = "=" },
    play_fx    = { label = "播放效果",  color = {220, 130, 180}, category = "动作",   desc = "音效/震屏/粒子/提示", icon = "♪" },
    dialog     = { label = "弹出对话",  color = {100, 180, 220}, category = "动作",   desc = "显示剧情/提示文字", icon = "💬" },
    damage     = { label = "伤害/治疗", color = {220, 70, 70},   category = "动作",   desc = "对玩家造成伤害或治疗", icon = "♥" },
    win_level  = { label = "胜负判定",  color = {60, 200, 60},   category = "动作",   desc = "过关成功/失败", icon = "🏆" },
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
    spawn = {
        inputs = { { name = "▶", type = "flow" }, { name = "X", type = "number", field = "spawnX" }, { name = "Y", type = "number", field = "spawnY" } },
        outputs = { { name = "▶", type = "flow", field = "outputNode" } },
    },
    move_obj = {
        inputs = { { name = "▶", type = "flow" }, { name = "X偏移", type = "number", field = "offsetX" }, { name = "Y偏移", type = "number", field = "offsetY" } },
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

-- 对话类型
M.DIALOG_STYLES = {
    { id = "popup",      label = "居中弹窗" },
    { id = "banner_top", label = "顶部横幅" },
    { id = "subtitle",   label = "底部字幕" },
    { id = "bubble",     label = "气泡对话" },
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
}

-- 胜负判定类型
M.WIN_TYPES = {
    { id = "win",     label = "过关成功" },
    { id = "fail",    label = "关卡失败" },
    { id = "restart", label = "重新开始" },
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
    spawn = {
        { key = "spawnType", label = "实体类型", type = "select", options = "SPAWN_TYPES", default = "enemy_melee" },
        { key = "spawnCount", label = "数量", type = "int", min = 1, max = 20, step = 1, default = 1 },
        { key = "spawnDir", label = "朝向", type = "select", options = "SPAWN_DIRS", default = "auto" },
    },
    move_obj = {
        { key = "targetId", label = "目标ID", type = "text", default = "" },
        { key = "moveDuration", label = "持续(秒)", type = "float", min = 0.1, max = 30, step = 0.1, default = 1.0 },
        { key = "moveEase", label = "缓动", type = "select", options = "EASE_TYPES", default = "easeOut" },
        { key = "rotationDeg", label = "旋转(度)", type = "float", min = -360, max = 360, step = 5, default = 0 },
    },
    set_var = {
        { key = "varName", label = "变量名", type = "select", options = "RUNTIME_PARAMS", default = "custom1" },
        { key = "setMode", label = "方式", type = "select", options = {{id="set",label="设为"},{id="add",label="增加"},{id="mul",label="乘以"}}, default = "set" },
    },
    play_fx = {
        { key = "fxType", label = "效果类型", type = "select", options = "FX_TYPES", default = "sound" },
        { key = "fxParam", label = "参数", type = "text", default = "" },
        { key = "fxIntensity", label = "强度", type = "float", min = 0, max = 10, step = 0.1, default = 1.0 },
    },
    dialog = {
        { key = "dialogText", label = "对话内容", type = "text", default = "你好！" },
        { key = "dialogStyle", label = "样式", type = "select", options = "DIALOG_STYLES", default = "popup" },
        { key = "dialogDuration", label = "显示时间(秒)", type = "float", min = 0.5, max = 30, step = 0.5, default = 3.0 },
        { key = "dialogSpeaker", label = "说话人", type = "text", default = "" },
    },
    damage = {
        { key = "damageAmount", label = "数值", type = "float", min = -100, max = 100, step = 1, default = 10 },
        { key = "damageIsHeal", label = "治疗模式", type = "bool", default = false },
    },
    win_level = {
        { key = "winType", label = "结果", type = "select", options = "WIN_TYPES", default = "win" },
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
    spawn     = { spawnType = "enemy_melee", spawnCount = 1, spawnDir = "auto", spawnX = nil, spawnY = nil, outputNode = nil },
    move_obj  = { targetId = "", moveDuration = 1.0, moveEase = "easeOut", rotationDeg = 0, offsetX = nil, offsetY = nil, outputNode = nil },
    set_var   = { varName = "custom1", setMode = "set", newValue = nil, outputNode = nil },
    play_fx   = { fxType = "sound", fxParam = "", fxIntensity = 1.0, outputNode = nil },
    dialog    = { dialogText = "你好！", dialogStyle = "popup", dialogDuration = 3.0, dialogSpeaker = "", textInput = nil, outputNode = nil },
    damage    = { damageAmount = 10, damageIsHeal = false, amount = nil, outputNode = nil },
    win_level = { winType = "win" },
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
    -- 清理所有引用
    local skipKeys = { id = true, x = true, y = true, value = true, delaySeconds = true,
        repeatCount = true, spawnCount = true, damageAmount = true, fxIntensity = true,
        moveDuration = true, rotationDeg = true, dialogDuration = true }
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
       or t == "delay" or t == "repeat_n" then
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
    elseif t == "delay" or t == "repeat_n" or t == "spawn" or t == "move_obj"
        or t == "set_var" or t == "play_fx" or t == "dialog"
        or t == "damage" or t == "win_level" then
        -- 动作节点: 收集自身，然后继续
        table.insert(actions, { nodeType = t, node = node })
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
