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
            effects = node.dlgBgEffects or {},
        },
        portrait = {
            texturePath = node.dlgPortraitTexture or "",
            offsetX = node.dlgPortraitOffsetX or 0,
            offsetY = node.dlgPortraitOffsetY or 0,
            opacity = node.dlgPortraitOpacity or 1.0,
            effects = node.dlgPortraitEffects or {},
        },
        nameplate = {
            texturePath = node.dlgNameTexture or "",
            offsetX = node.dlgNameOffsetX or 0,
            offsetY = node.dlgNameOffsetY or 0,
            opacity = node.dlgNameOpacity or 1.0,
            effects = node.dlgNameEffects or {},
        },
        textbox = {
            texturePath = node.dlgTextTexture or "",
            offsetX = node.dlgTextOffsetX or 0,
            offsetY = node.dlgTextOffsetY or 0,
            opacity = node.dlgTextOpacity or 1.0,
            effects = node.dlgTextEffects or {},
        },
        durationMode = node.dlgDurationMode or "timed",
        duration = node.dlgDuration or 3.0,
        nameplateText = node.dlgSpeaker or "",
        dialogText = node.dialogText or "",
    }
end

return M
