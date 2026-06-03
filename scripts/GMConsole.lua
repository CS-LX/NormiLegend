-- ============================================================================
-- GMConsole.lua - GM控制台模块 (UI组件版)
-- 按数字键0打开/关闭，支持分角色编辑、技能参数调整、数据导出
-- 使用 urhox-libs/UI 组件实现，支持鼠标/触屏点击交互
-- ============================================================================
local UI = require("urhox-libs/UI")
local Enemy = require("Enemy")
local BatEnemy = require("BatEnemy")
local CastleEnemies = require("CastleEnemies")

local GMConsole = {}

-- 状态
local isOpen_ = false
local currentCategory_ = 1   -- 一级标签: 1=敌人, 2=角色, 3=渲染
local currentSubTab_ = 1     -- 二级标签索引（在当前一级标签下的子标签）

-- 无敌模式
local isInvincible_ = false
-- 无限MP模式
local isInfiniteMP_ = false

-- 主回调引用
local callbacks_ = nil

-- UI引用
local gmPanelUI_ = nil         -- GM面板根节点
local exportPanelUI_ = nil     -- 导出面板根节点
local itemsContainer_ = nil    -- 参数列表容器
local categoryButtons_ = {}    -- 一级标签按钮引用
local subTabButtons_ = {}      -- 二级标签按钮引用
local subTabContainer_ = nil   -- 二级标签容器
local statusLabel_ = nil       -- 状态栏标签
local exportTextLabel_ = nil   -- 导出文本标签

-- 一级标签
local categoryNames_ = { "敌人", "角色", "渲染" }

-- 二级标签配置（每个一级标签下的子标签）
local subTabConfig_ = {
    -- 敌人分支
    { "蝙蝠", "斯缇昔娅", "灰狼", "飞龙", "骷髅兵", "幽灵", "石像鬼" },
    -- 角色分支
    { "角色1", "角色2" },
    -- 渲染分支（无二级标签，直接显示参数）
    { "渲染" },
}

-- 蝙蝠参数编辑项
local batItems_ = {
    { label = "血量",       key = "maxHP",          min = 5,   max = 200, step = 5,   source = "bat" },
    { label = "攻击伤害",   key = "damage",         min = 1,   max = 50,  step = 1,   source = "bat" },
    { label = "攻击距离",   key = "attackRange",    min = 0.5, max = 8,   step = 0.5, source = "bat" },
    { label = "检测距离",   key = "detectRange",    min = 2.0, max = 20,  step = 1.0, source = "bat" },
    { label = "飞行速度",   key = "moveSpeed",      min = 0.5, max = 10,  step = 0.5, source = "bat" },
    { label = "攻击CD",     key = "attackCooldown", min = 0.5, max = 8.0, step = 0.5, source = "bat" },
    { label = "浮动幅度",   key = "flyAmplitude",   min = 0.1, max = 2.0, step = 0.1, source = "bat" },
    { label = "浮动频率",   key = "flyFrequency",   min = 0.5, max = 5.0, step = 0.5, source = "bat" },
    { label = "渲染缩放",   key = "scale",          min = 1.0, max = 8,   step = 0.5, source = "bat" },
}

-- 斯缇昔娅参数编辑项
local enemyItems_ = {
    { label = "血量",       key = "maxHP",          min = 10,  max = 500, step = 10 },
    { label = "普攻伤害",   key = "damage",         min = 1,   max = 100, step = 1 },
    { label = "技能伤害",   key = "skillDamage",    min = 1,   max = 200, step = 2 },
    { label = "攻击距离",   key = "attackRange",    min = 0.5, max = 10,  step = 0.5 },
    { label = "技能距离",   key = "skillRange",     min = 1.0, max = 15,  step = 0.5 },
    { label = "检测距离",   key = "detectRange",    min = 2.0, max = 20,  step = 1.0 },
    { label = "移动速度",   key = "moveSpeed",      min = 0.5, max = 10,  step = 0.5 },
    { label = "攻击CD",     key = "attackCooldown", min = 0.2, max = 5.0, step = 0.1 },
    { label = "技能CD",     key = "skillCooldown",  min = 1.0, max = 15,  step = 0.5 },
    { label = "渲染缩放",   key = "scale",          min = 2.0, max = 10,  step = 0.5 },
}

-- 角色1参数编辑项
local char1Items_ = {
    { label = "最大HP",         cbKey = "c1_maxHP",       min = 10,  max = 500, step = 10 },
    { label = "最大MP",         cbKey = "c1_maxMP",       min = 10,  max = 500, step = 10 },
    { label = "冰晶术伤害",     cbKey = "c1_projDmg",     min = 1,   max = 100, step = 1 },
    { label = "冰晶术速度",     cbKey = "c1_projSpeed",   min = 1,   max = 30,  step = 1 },
    { label = "冰晶术射程",     cbKey = "c1_projLife",    min = 0.5, max = 10,  step = 0.5 },
    { label = "雪崩伤害",       cbKey = "c1_chargeDmg",   min = 1,   max = 200, step = 2 },
    { label = "雪崩MP消耗",     cbKey = "c1_chargeMP",    min = 5,   max = 100, step = 5 },
    { label = "雪崩冰冻时长",   cbKey = "c1_freezeDur",   min = 0.5, max = 10,  step = 0.5 },
    { label = "治愈回复HP",     cbKey = "c1_healHP",      min = 5,   max = 200, step = 5 },
    { label = "治愈MP消耗",     cbKey = "c1_healMP",      min = 5,   max = 100, step = 5 },
    { label = "治愈CD",         cbKey = "c1_healCD",      min = 0.5, max = 15,  step = 0.5 },
    { label = "格挡MP/秒",      cbKey = "c1_blockMP",     min = 1,   max = 30,  step = 1 },
}

-- 角色2参数编辑项
local char2Items_ = {
    { label = "最大HP",         cbKey = "c2_maxHP",       min = 10,  max = 500, step = 10 },
    { label = "最大MP",         cbKey = "c2_maxMP",       min = 10,  max = 500, step = 10 },
    { label = "镰刀斩伤害",     cbKey = "c2_meleeDmg",    min = 1,   max = 100, step = 1 },
    { label = "镰刀斩范围",     cbKey = "c2_meleeRange",  min = 0.5, max = 10,  step = 0.5 },
    { label = "蝴蝶突进伤害",   cbKey = "c2_dashDmg",     min = 1,   max = 200, step = 2 },
    { label = "突进MP消耗",     cbKey = "c2_dashMP",      min = 5,   max = 100, step = 5 },
    { label = "突进速度",       cbKey = "c2_dashSpeed",   min = 5,   max = 30,  step = 1 },
    { label = "流血时长",       cbKey = "c2_bleedDur",    min = 1,   max = 15,  step = 0.5 },
    { label = "流血DPS",        cbKey = "c2_bleedDPS",    min = 1,   max = 20,  step = 1 },
    { label = "蝶之加护回复HP", cbKey = "c2_healHP",      min = 5,   max = 200, step = 5 },
    { label = "蝶之加护MP消耗", cbKey = "c2_healMP",      min = 5,   max = 100, step = 5 },
    { label = "蝶之加护CD",     cbKey = "c2_healCD",      min = 0.5, max = 15,  step = 0.5 },
    { label = "吸血持续时间",   cbKey = "c2_lifestealDur",min = 1,   max = 30,  step = 1 },
    { label = "吸血比例%",      cbKey = "c2_lifestealPct",min = 10,  max = 100, step = 5 },
    { label = "格挡MP/秒",      cbKey = "c2_blockMP",     min = 1,   max = 30,  step = 1 },
}

-- 渲染参数编辑项
local renderItems_ = {
    { label = "像素/米(缩放)", cbKey = "r_pixelsPerUnit", min = 20, max = 150, step = 5 },
    { label = "设计宽度",      cbKey = "r_screenW",       min = 640, max = 2560, step = 64 },
    { label = "设计高度",      cbKey = "r_screenH",       min = 360, max = 1440, step = 36 },
}

-- 古堡敌人参数编辑项（数据驱动：从 CastleEnemies.TYPES 生成）
local TYPE_ORDER = { "wolf", "wyvern", "skeleton", "ghost", "gargoyle" }
local castleItems_ = {}
for _, typeName in ipairs(TYPE_ORDER) do
    local items = {
        { label = "血量",     key = "maxHP",          min = 10,  max = 300, step = 5,   castleType = typeName },
        { label = "攻击伤害", key = "damage",         min = 1,   max = 50,  step = 1,   castleType = typeName },
        { label = "攻击距离", key = "attackRange",    min = 0.5, max = 8,   step = 0.5, castleType = typeName },
        { label = "检测距离", key = "detectRange",    min = 2.0, max = 20,  step = 1.0, castleType = typeName },
        { label = "移动速度", key = "moveSpeed",      min = 0.5, max = 10,  step = 0.5, castleType = typeName },
        { label = "攻击CD",   key = "attackCooldown", min = 0.5, max = 8.0, step = 0.5, castleType = typeName },
        { label = "渲染缩放", key = "scale",          min = 2.0, max = 10,  step = 0.5, castleType = typeName },
    }
    -- 飞行敌人额外参数
    if CastleEnemies.TYPES[typeName].flying then
        table.insert(items, { label = "浮动幅度", key = "flyAmplitude", min = 0.1, max = 2.0, step = 0.1, castleType = typeName })
        table.insert(items, { label = "浮动频率", key = "flyFrequency", min = 0.5, max = 5.0, step = 0.5, castleType = typeName })
    end
    castleItems_[typeName] = items
end

-- ============================================================================
-- 获取当前 tab 的编辑项列表
-- ============================================================================
local function GetCurrentItems()
    if currentCategory_ == 1 then
        -- 敌人分支
        if currentSubTab_ == 1 then return batItems_
        elseif currentSubTab_ == 2 then return enemyItems_
        elseif currentSubTab_ == 3 then return castleItems_["wolf"]
        elseif currentSubTab_ == 4 then return castleItems_["wyvern"]
        elseif currentSubTab_ == 5 then return castleItems_["skeleton"]
        elseif currentSubTab_ == 6 then return castleItems_["ghost"]
        elseif currentSubTab_ == 7 then return castleItems_["gargoyle"]
        end
    elseif currentCategory_ == 2 then
        -- 角色分支
        if currentSubTab_ == 1 then return char1Items_
        elseif currentSubTab_ == 2 then return char2Items_
        end
    elseif currentCategory_ == 3 then
        -- 渲染分支
        return renderItems_
    end
    return {}
end

-- ============================================================================
-- 获取参数当前值
-- ============================================================================
local function GetItemValue(item)
    if currentCategory_ == 1 and currentSubTab_ == 1 then
        -- 蝙蝠
        return BatEnemy.CONFIG[item.key] or 0
    elseif currentCategory_ == 1 and currentSubTab_ == 2 then
        -- 斯缇昔娅
        return Enemy.CONFIG[item.key] or 0
    elseif item.castleType then
        -- 古堡敌人
        return CastleEnemies.TYPES[item.castleType].CONFIG[item.key] or 0
    else
        local getKey = item.cbKey .. "_get"
        if callbacks_ and callbacks_[getKey] then
            return callbacks_[getKey]()
        end
    end
    return 0
end

-- ============================================================================
-- 设置参数值
-- ============================================================================
local function SetItemValue(item, val)
    val = math.max(item.min, math.min(item.max, val))
    val = math.floor(val * 100 + 0.5) / 100
    if currentCategory_ == 1 and currentSubTab_ == 1 then
        -- 蝙蝠
        BatEnemy.CONFIG[item.key] = val
    elseif currentCategory_ == 1 and currentSubTab_ == 2 then
        -- 斯缇昔娅
        Enemy.CONFIG[item.key] = val
    elseif item.castleType then
        -- 古堡敌人
        CastleEnemies.TYPES[item.castleType].CONFIG[item.key] = val
    else
        local setKey = item.cbKey .. "_set"
        if callbacks_ and callbacks_[setKey] then
            callbacks_[setKey](val)
        end
    end
end

-- ============================================================================
-- 格式化数值
-- ============================================================================
local function FormatValue(val)
    if val == math.floor(val) then
        return tostring(math.floor(val))
    else
        return string.format("%.1f", val)
    end
end

-- ============================================================================
-- 生成导出文本
-- ============================================================================
local function GenerateExportText()
    local lines = {}
    table.insert(lines, "=== GM控制台数据导出 ===")
    table.insert(lines, "")
    table.insert(lines, "[敌人-蝙蝠]")
    for _, item in ipairs(batItems_) do
        local val = BatEnemy.CONFIG[item.key]
        table.insert(lines, string.format("  %s = %s", item.label, tostring(val)))
    end
    table.insert(lines, "")
    table.insert(lines, "[敌人-斯缇昔娅]")
    for _, item in ipairs(enemyItems_) do
        local val = Enemy.CONFIG[item.key]
        table.insert(lines, string.format("  %s = %s", item.label, tostring(val)))
    end
    table.insert(lines, "")
    -- 古堡敌人
    local castleNames = { wolf = "灰狼", wyvern = "飞龙", skeleton = "骷髅兵", ghost = "幽灵", gargoyle = "石像鬼" }
    for _, typeName in ipairs(TYPE_ORDER) do
        table.insert(lines, "[敌人-" .. castleNames[typeName] .. "]")
        for _, item in ipairs(castleItems_[typeName]) do
            local val = CastleEnemies.TYPES[typeName].CONFIG[item.key]
            table.insert(lines, string.format("  %s = %s", item.label, tostring(val)))
        end
        table.insert(lines, "")
    end
    table.insert(lines, "[角色1 - 冰法师]")
    for _, item in ipairs(char1Items_) do
        if callbacks_ and callbacks_[item.cbKey .. "_get"] then
            local val = callbacks_[item.cbKey .. "_get"]()
            table.insert(lines, string.format("  %s = %s", item.label, tostring(val)))
        end
    end
    table.insert(lines, "")
    table.insert(lines, "[角色2 - 黑红角娘]")
    for _, item in ipairs(char2Items_) do
        if callbacks_ and callbacks_[item.cbKey .. "_get"] then
            local val = callbacks_[item.cbKey .. "_get"]()
            table.insert(lines, string.format("  %s = %s", item.label, tostring(val)))
        end
    end
    table.insert(lines, "")
    table.insert(lines, "[渲染参数]")
    for _, item in ipairs(renderItems_) do
        if callbacks_ and callbacks_[item.cbKey .. "_get"] then
            local val = callbacks_[item.cbKey .. "_get"]()
            table.insert(lines, string.format("  %s = %s", item.label, tostring(val)))
        end
    end
    table.insert(lines, "")
    table.insert(lines, "请将以上数据发给AI助手，说「请按这些数值更新游戏默认参数」即可。")
    return table.concat(lines, "\n")
end

-- ============================================================================
-- 敌人生成配置（每个敌人子标签对应的生成方式）
-- ============================================================================
local enemySpawnConfig_ = {
    -- subTab index -> { label, spawn function }
    [1] = { label = "蝙蝠",     spawn = function() BatEnemy.Spawn(math.random(2, 20), math.random(1, 4) * 1.0) end },
    [2] = { label = "斯缇昔娅", spawn = function() Enemy.Spawn(math.random(3, 18), -3.0) end },
    [3] = { label = "灰狼",     spawn = function() CastleEnemies.Spawn("wolf", math.random(10, 25), -3.0) end },
    [4] = { label = "飞龙",     spawn = function() CastleEnemies.Spawn("wyvern", math.random(10, 25), math.random(1, 3) * 1.0) end },
    [5] = { label = "骷髅兵",   spawn = function() CastleEnemies.Spawn("skeleton", math.random(10, 25), -3.0) end },
    [6] = { label = "幽灵",     spawn = function() CastleEnemies.Spawn("ghost", math.random(10, 25), math.random(1, 3) * 0.5 + 0.5) end },
    [7] = { label = "石像鬼",   spawn = function() CastleEnemies.Spawn("gargoyle", math.random(10, 25), math.random(2, 4) * 1.0) end },
}

-- ============================================================================
-- 刷新参数列表UI
-- ============================================================================
local function RefreshItemsUI()
    if not itemsContainer_ then return end
    itemsContainer_:RemoveAllChildren()

    -- 敌人分支：在参数列表顶部添加"生成"按钮
    if currentCategory_ == 1 then
        local spawnCfg = enemySpawnConfig_[currentSubTab_]
        if spawnCfg then
            local spawnRow = UI.Panel {
                width = "100%", height = 26,
                flexDirection = "row", alignItems = "center",
                justifyContent = "center", gap = 6,
                marginBottom = 4,
                children = {
                    UI.Button {
                        text = "生成 " .. spawnCfg.label, fontSize = 10, height = 22,
                        paddingLeft = 10, paddingRight = 10,
                        backgroundColor = "#335544", color = "#88ffaa", borderRadius = 4,
                        onClick = function()
                            spawnCfg.spawn()
                            print("[GM] 生成了一个" .. spawnCfg.label)
                        end,
                    },
                }
            }
            itemsContainer_:AddChild(spawnRow)
        end
    end

    local items = GetCurrentItems()
    for _, item in ipairs(items) do
        local val = GetItemValue(item)
        local row = UI.Panel {
            width = "100%", height = 22,
            flexDirection = "row", alignItems = "center",
            paddingLeft = 4, paddingRight = 4,
            children = {
                UI.Label {
                    text = item.label,
                    fontSize = 10, color = "#ccdde8",
                    width = 95, flexShrink = 0,
                },
                UI.Button {
                    text = "-", width = 20, height = 18, fontSize = 11,
                    backgroundColor = "#553333", color = "#ffaaaa", borderRadius = 3,
                    onClick = function()
                        local cur = GetItemValue(item)
                        SetItemValue(item, cur - item.step)
                        RefreshItemsUI()
                    end,
                },
                UI.Label {
                    text = FormatValue(val),
                    fontSize = 10, color = "#aaffaa",
                    width = 42, textAlign = "center", flexShrink = 0,
                },
                UI.Button {
                    text = "+", width = 20, height = 18, fontSize = 11,
                    backgroundColor = "#335533", color = "#aaffaa", borderRadius = 3,
                    onClick = function()
                        local cur = GetItemValue(item)
                        SetItemValue(item, cur + item.step)
                        RefreshItemsUI()
                    end,
                },
            }
        }
        itemsContainer_:AddChild(row)
    end
end

-- ============================================================================
-- 刷新二级标签UI
-- ============================================================================
local function RefreshSubTabs()
    if not subTabContainer_ then return end
    subTabContainer_:RemoveAllChildren()
    subTabButtons_ = {}

    local subTabs = subTabConfig_[currentCategory_]
    if not subTabs or #subTabs <= 1 then
        -- 渲染等只有一个子标签时不显示二级标签行
        RefreshItemsUI()
        return
    end

    for i, name in ipairs(subTabs) do
        local btn = UI.Button {
            text = name, fontSize = 9, height = 17,
            paddingLeft = 3, paddingRight = 3,
            backgroundColor = (i == currentSubTab_) and "#553355" or "#1e1e2e",
            color = (i == currentSubTab_) and "#ffcc66" or "#8888aa",
            borderRadius = 3,
            onClick = function()
                currentSubTab_ = i
                RefreshSubTabs()
            end,
        }
        subTabButtons_[i] = btn
        subTabContainer_:AddChild(btn)
    end
    RefreshItemsUI()
end

-- ============================================================================
-- 刷新一级标签高亮 + 二级标签
-- ============================================================================
local function RefreshTabs()
    for i, btn in ipairs(categoryButtons_) do
        if i == currentCategory_ then
            btn:SetStyle({ backgroundColor = "#662222", color = "#ffff66" })
        else
            btn:SetStyle({ backgroundColor = "#282838", color = "#a0a0b4" })
        end
    end
    RefreshSubTabs()
end

-- ============================================================================
-- 刷新状态栏
-- ============================================================================
local function RefreshStatus()
    if not statusLabel_ then return end
    local parts = {}
    table.insert(parts, isInvincible_ and "无敌:ON" or "无敌:OFF")
    table.insert(parts, isInfiniteMP_ and "无限MP:ON" or "无限MP:OFF")
    statusLabel_:SetText(table.concat(parts, " | "))
    if isInvincible_ or isInfiniteMP_ then
        statusLabel_:SetStyle({ color = "#ff6666" })
    else
        statusLabel_:SetStyle({ color = "#888899" })
    end
end

-- ============================================================================
-- 创建GM面板UI
-- ============================================================================
local function CreateGMPanelUI()
    -- 一级标签按钮
    categoryButtons_ = {}
    local categoryChildren = {}
    for i, name in ipairs(categoryNames_) do
        local btn = UI.Button {
            text = name, fontSize = 10, height = 20,
            paddingLeft = 6, paddingRight = 6,
            backgroundColor = (i == currentCategory_) and "#662222" or "#282838",
            color = (i == currentCategory_) and "#ffff66" or "#a0a0b4",
            borderRadius = 3,
            flexGrow = 1,
            onClick = function()
                currentCategory_ = i
                currentSubTab_ = 1
                RefreshTabs()
            end,
        }
        categoryButtons_[i] = btn
        categoryChildren[i] = btn
    end

    -- 二级标签容器（动态刷新内容）
    subTabContainer_ = UI.Panel {
        width = "100%", flexDirection = "row",
        flexWrap = "wrap",
        justifyContent = "flex-start", gap = 2,
        marginBottom = 3,
    }

    -- 参数列表容器
    itemsContainer_ = UI.Panel {
        width = "100%", flexGrow = 1, flexShrink = 1,
        overflow = "scroll",
    }

    -- 状态栏
    statusLabel_ = UI.Label {
        text = "无敌:OFF | 无限MP:OFF",
        fontSize = 9, color = "#888899",
        width = "100%", textAlign = "center",
        marginTop = 2,
    }

    -- 功能按钮行
    local actionRow = UI.Panel {
        width = "100%", flexDirection = "row", flexWrap = "wrap",
        justifyContent = "center", gap = 3,
        marginTop = 3,
        children = {
            UI.Button {
                text = "清空敌人", fontSize = 9, height = 20,
                paddingLeft = 5, paddingRight = 5,
                backgroundColor = "#442222", color = "#ff7777", borderRadius = 3,
                onClick = function()
                    Enemy.Clear()
                    BatEnemy.Clear()
                    CastleEnemies.Clear()
                    print("[GM] 已清空所有敌人")
                end,
            },
            UI.Button {
                text = "重生敌人", fontSize = 9, height = 20,
                paddingLeft = 5, paddingRight = 5,
                backgroundColor = "#443322", color = "#ffcc88", borderRadius = 3,
                onClick = function()
                    Enemy.Clear()
                    Enemy.Spawn(5, -3.0)
                    Enemy.Spawn(10, -3.0)
                    BatEnemy.Clear()
                    BatEnemy.Spawn(3, 2.0)
                    BatEnemy.Spawn(8, 3.0)
                    CastleEnemies.Clear()
                    CastleEnemies.Spawn("wolf", 12, -3.0)
                    CastleEnemies.Spawn("wyvern", 15, 2.0)
                    CastleEnemies.Spawn("skeleton", 18, -3.0)
                    CastleEnemies.Spawn("ghost", 20, 1.5)
                    CastleEnemies.Spawn("gargoyle", 22, 3.0)
                    print("[GM] 敌人已重生（全部）")
                end,
            },
            UI.Button {
                text = "无敌", fontSize = 9, height = 20,
                paddingLeft = 5, paddingRight = 5,
                backgroundColor = "#442222", color = "#ffaaaa", borderRadius = 3,
                onClick = function()
                    isInvincible_ = not isInvincible_
                    print("[GM] 无敌模式: " .. (isInvincible_ and "开启" or "关闭"))
                    RefreshStatus()
                end,
            },
            UI.Button {
                text = "无限MP", fontSize = 9, height = 20,
                paddingLeft = 5, paddingRight = 5,
                backgroundColor = "#222244", color = "#aabbff", borderRadius = 3,
                onClick = function()
                    isInfiniteMP_ = not isInfiniteMP_
                    print("[GM] 无限MP: " .. (isInfiniteMP_ and "开启" or "关闭"))
                    if isInfiniteMP_ and callbacks_ and callbacks_.refillMP then
                        callbacks_.refillMP()
                    end
                    RefreshStatus()
                end,
            },
            UI.Button {
                text = "回满", fontSize = 9, height = 20,
                paddingLeft = 5, paddingRight = 5,
                backgroundColor = "#224422", color = "#aaffaa", borderRadius = 3,
                onClick = function()
                    if callbacks_ and callbacks_.refillHP then callbacks_.refillHP() end
                    if callbacks_ and callbacks_.refillMP then callbacks_.refillMP() end
                    print("[GM] HP/MP 已回满")
                end,
            },
            UI.Button {
                text = "导出", fontSize = 9, height = 20,
                paddingLeft = 5, paddingRight = 5,
                backgroundColor = "#223344", color = "#88ccff", borderRadius = 3,
                onClick = function()
                    local exportText = GenerateExportText()
                    if exportTextLabel_ then
                        exportTextLabel_:SetText(exportText)
                    end
                    if exportPanelUI_ then
                        exportPanelUI_:Show()
                    end
                end,
            },
        }
    }

    -- 主面板（全屏透明遮罩 + 侧边面板）
    gmPanelUI_ = UI.Panel {
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        pointerEvents = "auto",
        onClick = function() GMConsole.Toggle() end,  -- 点击空白关闭
        children = {
            UI.Panel {
                position = "absolute",
                right = 8, top = 8,
                width = 220, height = 450,
                backgroundColor = "#0a0a14ee",
                borderRadius = 6,
                borderWidth = 1, borderColor = "#ff5050cc",
                padding = 6,
                flexDirection = "column",
                onClick = function() end,  -- 阻止冒泡到遮罩
                children = {
                    -- 标题
                    UI.Label {
                        text = "GM 控制台 [0]",
                        fontSize = 11, color = "#ff6666", fontWeight = "bold",
                        width = "100%", textAlign = "center",
                        marginBottom = 4,
                    },
                    -- 一级标签行
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        justifyContent = "flex-start", gap = 3,
                        marginBottom = 3,
                        children = categoryChildren,
                    },
                    -- 二级标签行（动态刷新）
                    subTabContainer_,
                    -- 参数列表
                    itemsContainer_,
                    -- 状态栏
                    statusLabel_,
                    -- 功能按钮
                    actionRow,
                    -- 关闭按钮
                    UI.Button {
                        text = "关闭", fontSize = 9, height = 18,
                        width = "100%", marginTop = 3,
                        backgroundColor = "#333", color = "#aaa", borderRadius = 3,
                        onClick = function()
                            GMConsole.Toggle()
                        end,
                    },
                }
            }
        }
    }
    gmPanelUI_:Hide()

    -- 导出面板（居中覆盖）
    exportTextLabel_ = UI.Label {
        text = "",
        fontSize = 9, color = "#dde6f0",
        width = "100%", flexShrink = 1,
    }

    exportPanelUI_ = UI.Panel {
        position = "absolute",
        left = "15%", top = "10%",
        width = "70%", height = "80%",
        backgroundColor = "#0f0f1eee",
        borderRadius = 8,
        borderWidth = 1, borderColor = "#66c8ffcc",
        padding = 10,
        flexDirection = "column",
        children = {
            UI.Label {
                text = "数据导出 - 复制文本发给AI助手",
                fontSize = 12, color = "#66c8ff",
                width = "100%", textAlign = "center",
                marginBottom = 6,
            },
            UI.Panel {
                width = "100%", flexGrow = 1, flexShrink = 1,
                overflow = "scroll",
                children = { exportTextLabel_ },
            },
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "center", gap = 8,
                marginTop = 6,
                children = {
                    UI.Button {
                        text = "复制到剪贴板", fontSize = 10, height = 24,
                        paddingLeft = 12, paddingRight = 12,
                        backgroundColor = "#3c78dc", color = "#fff", borderRadius = 4,
                        onClick = function()
                            local exportText = GenerateExportText()
                            ui.clipboardText = exportText
                            ui.useSystemClipboard = true
                            print("[GM] 数据已复制到剪贴板")
                        end,
                    },
                    UI.Button {
                        text = "关闭", fontSize = 10, height = 24,
                        paddingLeft = 12, paddingRight = 12,
                        backgroundColor = "#444", color = "#ccc", borderRadius = 4,
                        onClick = function()
                            if exportPanelUI_ then
                                exportPanelUI_:Hide()
                            end
                        end,
                    },
                }
            },
        }
    }
    exportPanelUI_:Hide()

    -- 初始刷新（刷新二级标签 + 参数列表）
    RefreshSubTabs()
end

-- ============================================================================
-- 公共接口
-- ============================================================================
function GMConsole.Init(nvgCtx, callbacks)
    callbacks_ = callbacks
    -- nvgCtx 保留兼容参数，不再使用
end

function GMConsole.Toggle()
    isOpen_ = not isOpen_
    if gmPanelUI_ then
        if isOpen_ then
            RefreshItemsUI()
            RefreshStatus()
            gmPanelUI_:Show()
        else
            gmPanelUI_:Hide()
            if exportPanelUI_ then exportPanelUI_:Hide() end
        end
    end
end

function GMConsole.IsOpen()
    return isOpen_
end

function GMConsole.IsInvincible()
    return isInvincible_
end

function GMConsole.IsInfiniteMP()
    return isInfiniteMP_
end

--- 创建UI并返回面板节点列表（供外部挂载到 UI root）
function GMConsole.CreateUI()
    CreateGMPanelUI()
    return gmPanelUI_, exportPanelUI_
end

--- 输入处理（保留键盘快捷键支持）
function GMConsole.HandleInput()
    if not isOpen_ then return false end

    -- 导出面板显示中
    if exportPanelUI_ and exportPanelUI_:IsVisible() then
        if input:GetKeyPress(KEY_ESCAPE) or input:GetKeyPress(KEY_RETURN) then
            exportPanelUI_:Hide()
        end
        if input:GetKeyPress(KEY_C) then
            local exportText = GenerateExportText()
            ui.clipboardText = exportText
            ui.useSystemClipboard = true
            print("[GM] 数据已复制到剪贴板")
        end
        return true
    end

    -- 快捷键
    if input:GetKeyPress(KEY_X) then
        Enemy.Clear()
        BatEnemy.Clear()
        CastleEnemies.Clear()
        print("[GM] 已清空所有敌人")
    end
    if input:GetKeyPress(KEY_R) then
        Enemy.Clear()
        Enemy.Spawn(5, -3.0)
        Enemy.Spawn(10, -3.0)
        BatEnemy.Clear()
        BatEnemy.Spawn(3, 2.0)
        BatEnemy.Spawn(8, 3.0)
        CastleEnemies.Clear()
        CastleEnemies.Spawn("wolf", 12, -3.0)
        CastleEnemies.Spawn("wyvern", 15, 2.0)
        CastleEnemies.Spawn("skeleton", 18, -3.0)
        CastleEnemies.Spawn("ghost", 20, 1.5)
        CastleEnemies.Spawn("gargoyle", 22, 3.0)
        print("[GM] 敌人已重生（全部）")
    end
    if input:GetKeyPress(KEY_G) then
        isInvincible_ = not isInvincible_
        print("[GM] 无敌模式: " .. (isInvincible_ and "开启" or "关闭"))
        RefreshStatus()
    end
    if input:GetKeyPress(KEY_M) then
        isInfiniteMP_ = not isInfiniteMP_
        print("[GM] 无限MP: " .. (isInfiniteMP_ and "开启" or "关闭"))
        if isInfiniteMP_ and callbacks_ and callbacks_.refillMP then callbacks_.refillMP() end
        RefreshStatus()
    end
    if input:GetKeyPress(KEY_H) then
        if callbacks_ and callbacks_.refillHP then callbacks_.refillHP() end
        if callbacks_ and callbacks_.refillMP then callbacks_.refillMP() end
        print("[GM] HP/MP 已回满")
    end
    if input:GetKeyPress(KEY_P) then
        local exportText = GenerateExportText()
        if exportTextLabel_ then exportTextLabel_:SetText(exportText) end
        if exportPanelUI_ then exportPanelUI_:Show() end
    end

    return true
end

--- 绘制（已废弃，保留空函数兼容）
function GMConsole.Draw(width, height)
    -- UI版本不再需要NanoVG绘制
end

return GMConsole
