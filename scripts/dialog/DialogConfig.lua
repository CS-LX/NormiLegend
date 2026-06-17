-- ============================================================================
-- dialog/DialogConfig.lua - 对话框数据模型
-- 纯数据结构，不含行为逻辑
-- ============================================================================

local M = {}

--- 从策略节点数据构造标准对话框配置
---@param node table 节点原始字段
---@return table config
function M.FromNode(node)
    return {
        background = {
            texturePath = node.dlgBgTexture or "",
            offsetX = node.dlgBgOffsetX or 0,
            offsetY = node.dlgBgOffsetY or 0,
            opacity = node.dlgBgOpacity or 1.0,
            width = node.dlgBgWidth or 0,
            height = node.dlgBgHeight or 0,
            effects = node.dlgBgEffects or {},
        },
        portrait = {
            texturePath = node.dlgPortraitTexture or "",
            offsetX = node.dlgPortraitOffsetX or 0,
            offsetY = node.dlgPortraitOffsetY or 0,
            opacity = node.dlgPortraitOpacity or 1.0,
            width = node.dlgPortraitWidth or 0,
            height = node.dlgPortraitHeight or 0,
            effects = node.dlgPortraitEffects or {},
        },
        nameplate = {
            texturePath = node.dlgNameTexture or "",
            offsetX = node.dlgNameOffsetX or 0,
            offsetY = node.dlgNameOffsetY or 0,
            opacity = node.dlgNameOpacity or 1.0,
            fontSize = node.dlgNameFontSize or 16,
            fontColor = node.dlgNameFontColor or {255,255,255,255},
            strokeWidth = node.dlgNameStrokeW or 0,
            strokeColor = node.dlgNameStrokeColor or {0,0,0,255},
            effects = node.dlgNameEffects or {},
        },
        textbox = {
            texturePath = node.dlgTextTexture or "",
            offsetX = node.dlgTextOffsetX or -150,
            offsetY = node.dlgTextOffsetY or -209,
            opacity = node.dlgTextOpacity or 1.0,
            fontSize = node.dlgTextFontSize or 44,
            fontColor = node.dlgTextFontColor or {0,0,0,255},
            strokeWidth = node.dlgTextStrokeW or 1.5,
            strokeColor = node.dlgTextStrokeColor or {0,0,0,200},
            textAnim = node.dlgTextAnim or "typewriter",
            textAnimSpeed = node.dlgTextAnimSpeed or 3.0,
            effects = node.dlgTextEffects or {},
        },
        whole = {
            texturePath = node.dlgWholeTexture or "",
            offsetX = node.dlgWholeOffsetX or -100,
            offsetY = node.dlgWholeOffsetY or -318,
            opacity = node.dlgWholeOpacity or 1.0,
            width = node.dlgWholeWidth or 1600,
            height = node.dlgWholeHeight or 1075,
        },
        durationMode = node.dlgDurationMode or "timed",
        duration = node.dlgDuration or 3.0,
        nameplateText = node.dlgSpeaker or "",
        dialogText = node.dialogText or "",
    }
end

return M
