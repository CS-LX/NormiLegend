-- ============================================================================
-- GameUI.lua - 技能面板 / 背包面板 / ESC弹窗 UI
-- 提取自 main.lua 的 UI 面板相关函数
-- ============================================================================

local S = require("GameState")
local WorldMap = require("WorldMap")
local LevelConfig = require("LevelConfig")

local UI = require("urhox-libs/UI")

local M = {}

-- ============================================================================
-- 辅助：构建技能数据文本
-- ============================================================================
function M.BuildSkillStatText(curData)
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

-- ============================================================================
-- 技能面板
-- ============================================================================
function M.CreateSkillPanelUI()
    S.skillPanelUI = UI.Panel {
        id = "skillPanelRoot",
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        onClick = function() M.ToggleSkillPanel() end,
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
                                    M.ToggleSkillPanel()
                                end,
                            }
                        }
                    },
                }
            }
        }
    }
    S.skillPanelUI:Hide()
end

--- 刷新技能面板内容（切换角色或加减点后调用）
function M.RefreshSkillPanelUI()
    if not S.skillPanelUI then return end
    local skills = (S.currentCharacter == 1) and S.skillList or S.skillList2
    local charName = (S.currentCharacter == 1) and "冰法师" or "黑红角娘"
    local points = S.skillPoints[S.currentCharacter]

    -- 更新标题和技能点
    S.skillPanelUI:FindById("skillTitle"):SetText("技能 - " .. charName)
    S.skillPanelUI:FindById("skillPoints"):SetText("技能点: " .. points)

    local container = S.skillPanelUI:FindById("skillListContainer")

    -- 检查是否需要重建（角色切换时技能数量/内容变化）
    local needRebuild = (S.skillPanelCharCache ~= S.currentCharacter)
    if needRebuild then
        S.skillPanelCharCache = S.currentCharacter
        container:RemoveAllChildren()
    end

    -- 首次构建或角色切换时创建节点
    if needRebuild then
        for idx, skill in ipairs(skills) do
            local curData = skill.levelData[skill.level]
            local statText = M.BuildSkillStatText(curData)

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
                                        S.skillPoints[S.currentCharacter] = S.skillPoints[S.currentCharacter] + 1
                                        M.RefreshSkillPanelUI()
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
                                    if skill.level < skill.maxLevel and S.skillPoints[S.currentCharacter] > 0 then
                                        skill.level = skill.level + 1
                                        S.skillPoints[S.currentCharacter] = S.skillPoints[S.currentCharacter] - 1
                                        M.RefreshSkillPanelUI()
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
            local statText = M.BuildSkillStatText(curData)

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

--- 切换技能面板显示
function M.ToggleSkillPanel()
    S.showSkillPanel = not S.showSkillPanel
    if S.showSkillPanel then
        S.showInventory = false
        if S.inventoryPanelUI then S.inventoryPanelUI:Hide() end
        M.RefreshSkillPanelUI()
        S.skillPanelUI:Show()
    else
        S.skillPanelUI:Hide()
    end
end

-- ============================================================================
-- 背包面板
-- ============================================================================
function M.CreateInventoryPanelUI()
    S.inventoryPanelUI = UI.Panel {
        id = "invPanelRoot",
        position = "absolute",
        top = 0, left = 0,
        width = "100%", height = "100%",
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        onClick = function() M.ToggleInventoryPanel() end,
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
                                    M.ToggleInventoryPanel()
                                end,
                            }
                        }
                    },
                }
            }
        }
    }
    S.inventoryPanelUI:Hide()
end

--- 刷新背包面板内容
function M.RefreshInventoryPanelUI()
    if not S.inventoryPanelUI then return end
    local container = S.inventoryPanelUI:FindById("invItemsContainer")
    container:RemoveAllChildren()

    if #S.inventoryItems == 0 then
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

    for _, item in ipairs(S.inventoryItems) do
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
function M.ToggleInventoryPanel()
    S.showInventory = not S.showInventory
    if S.showInventory then
        S.showSkillPanel = false
        if S.skillPanelUI then S.skillPanelUI:Hide() end
        M.RefreshInventoryPanelUI()
        S.inventoryPanelUI:Show()
    else
        S.inventoryPanelUI:Hide()
    end
end

-- ============================================================================
-- ESC 离开确认弹窗
-- ============================================================================
function M.ShowEscPopupUI()
    if not S.escPopupUI then return end
    -- 更新当前区域名称
    local areaConfig = WorldMap.GetCurrentArea() and LevelConfig.GetArea(WorldMap.GetCurrentArea())
    local areaName = areaConfig and areaConfig.name or "未知区域"
    S.escPopupUI:FindById("escAreaName"):SetText("当前区域: " .. areaName)
    S.escPopupUI:Show()
end

return M
