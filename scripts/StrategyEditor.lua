-- ============================================================================
-- StrategyEditor.lua - 策略节点编辑器入口按钮
-- 职责: 在属性面板中提供"打开节点编辑器"按钮，点击后打开 NodeCanvas
-- ============================================================================

local SN = require("StrategyNode")
local UI = require("urhox-libs/UI")
local NodeCanvas = require("NodeCanvas")

local M = {}

-- ============================================================================
-- 主入口：构建策略编辑器 UI（仅一个打开按钮 + 参数区）
-- ============================================================================

---@param obj table 触发器/执行器对象
---@param fieldName string "triggerStrategy" / "executorStrategy"
---@param rebuildFn function 重建UI的回调
---@param pushUndoFn function 推送Undo的回调
---@return table panel UI.Panel
function M.Build(obj, fieldName, rebuildFn, pushUndoFn)
    -- 确保对象有策略树
    if not obj[fieldName] then
        obj[fieldName] = SN.CreateTree()
    end
    local tree = obj[fieldName]

    local panel = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 4,
    }

    -- ====== 参数定义区 ======
    panel:AddChild(M._buildParamsSection(tree, rebuildFn, pushUndoFn))

    -- ====== 打开节点编辑器按钮 ======
    panel:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = {80, 80, 120, 80}, marginTop = 4, marginBottom = 4 })

    local nodeCount = 0
    for _ in pairs(tree.nodes) do nodeCount = nodeCount + 1 end

    panel:AddChild(UI.Button {
        text = "打开节点编辑器 (" .. nodeCount .. " 个节点)",
        fontSize = 12, width = "100%", height = 32,
        backgroundColor = {60, 80, 140, 230}, borderRadius = 5,
        borderWidth = 1, borderColor = {100, 140, 220, 200},
        justifyContent = "center", alignItems = "center",
        fontColor = {240, 230, 180, 255},
        onClick = function()
            pushUndoFn()
            NodeCanvas.Open(obj, fieldName, function()
                -- 关闭时重建属性面板以刷新节点数
                rebuildFn()
            end)
        end,
    })

    panel:AddChild(UI.Label {
        text = "右键添加节点 | 拖拽端口连线 | ESC关闭",
        fontSize = 9, fontColor = {120, 120, 150, 180}, marginTop = 2,
    })

    return panel
end

-- ============================================================================
-- 参数定义区
-- ============================================================================

function M._buildParamsSection(tree, rebuildFn, pushUndoFn)
    local section = UI.Panel { width = "100%", flexDirection = "column", gap = 3 }

    section:AddChild(UI.Label { text = "自定义参数", fontSize = 11, fontColor = {220, 200, 100, 255} })

    for pi, param in ipairs(tree.params) do
        local paramIdx = pi
        local row = UI.Panel { flexDirection = "row", alignItems = "center", gap = 4, width = "100%", marginBottom = 2 }

        -- 参数名
        row:AddChild(UI.TextField {
            value = param.label or param.name,
            fontSize = 9, width = 60, height = 22,
            backgroundColor = {30, 30, 50, 255}, fontColor = {220, 200, 100, 255},
            borderRadius = 3, borderWidth = 1, borderColor = {180, 150, 50, 100},
            paddingHorizontal = 4,
            onSubmit = function(self, txt)
                pushUndoFn()
                tree.params[paramIdx].label = txt or tree.params[paramIdx].name
                tree.params[paramIdx].name = (txt or tree.params[paramIdx].name):gsub("%s+", "_"):lower()
                rebuildFn()
            end,
        })

        -- 参数默认值
        row:AddChild(UI.Label { text = "=", fontSize = 10, fontColor = {150, 150, 170, 200} })
        row:AddChild(UI.TextField {
            value = tostring(param.value),
            fontSize = 9, width = 50, height = 22,
            backgroundColor = {30, 30, 50, 255}, fontColor = {180, 220, 255, 255},
            borderRadius = 3, borderWidth = 1, borderColor = {80, 120, 180, 100},
            paddingHorizontal = 4,
            onSubmit = function(self, txt)
                pushUndoFn()
                tree.params[paramIdx].value = tonumber(txt) or 0
                rebuildFn()
            end,
        })

        -- 删除参数
        row:AddChild(UI.Button {
            text = "x", fontSize = 9, width = 18, height = 18,
            backgroundColor = {140, 50, 50, 200}, borderRadius = 3,
            justifyContent = "center", alignItems = "center", fontColor = {255, 255, 255, 255},
            onClick = function()
                pushUndoFn()
                table.remove(tree.params, paramIdx)
                rebuildFn()
            end,
        })

        section:AddChild(row)
    end

    -- 添加参数按钮
    section:AddChild(UI.Button {
        text = "+ 参数", fontSize = 9, height = 20,
        paddingLeft = 8, paddingRight = 8,
        backgroundColor = {60, 80, 60, 200}, borderRadius = 3,
        fontColor = {180, 220, 180, 255},
        onClick = function()
            pushUndoFn()
            local idx = #tree.params + 1
            table.insert(tree.params, {
                name = "param" .. idx,
                value = 0,
                label = "参数" .. idx,
            })
            rebuildFn()
        end,
    })

    return section
end

--- 重置编辑器状态
function M.Reset()
    -- NodeCanvas handles its own state
end

return M
