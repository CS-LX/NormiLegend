-- ============================================================================
-- dialog/DialogManager.lua - 对话框管理器（单例）
-- 职责：互斥控制 + 阻塞节点流 + 计时/点击关闭
-- 保证屏幕上同时只存在一个对话框
-- ============================================================================

local DialogConfig = require("dialog.DialogConfig")
local DialogView = require("dialog.DialogView")

local M = {}

--- 当前活跃对话（nil = 无对话显示）
---@type table|nil
-- { config: DialogNodeConfig, elapsed: number, startTime: number, onDismiss: function|nil }
M.active = nil

--- 显示对话框（替换已有，保证唯一性）
---@param nodeData table  节点原始数据
---@param onDismiss function|nil  关闭时回调（恢复节点流）
function M.Show(nodeData, onDismiss)
    -- 强制关闭前一个（互斥保证）
    if M.active and M.active.onDismiss then
        M.active.onDismiss()
    end
    local config = DialogConfig.FromNode(nodeData)
    M.active = {
        config = config,
        elapsed = 0,
        onDismiss = onDismiss,
    }
    -- 构建并挂载 UI 视图（最上层 overlay）
    DialogView.Show(config)
    print("[DIALOG] Show: " .. (config.nameplateText or "") .. " - " .. (config.dialogText or ""))
end

--- 每帧更新（计时关闭）
---@param dt number
function M.Update(dt)
    if not M.active then return end
    local a = M.active
    a.elapsed = a.elapsed + dt
    -- 驱动 UI 视图（文本动画 / effects / 提示闪烁）
    DialogView.Update(dt, a.config, a.elapsed)
    if a.config.durationMode == "timed" then
        if a.elapsed >= a.config.duration then
            M.Dismiss()
        end
    end
    -- "click" 模式不自动关闭，等 HandleClick
end

--- 处理鼠标点击（任何模式均可点击关闭）
---@return boolean consumed 是否消费了点击事件
function M.HandleClick()
    if not M.active then return false end
    M.Dismiss()
    return true  -- 消费了点击事件
end

--- 关闭当前对话框，触发回调恢复节点流
function M.Dismiss()
    if not M.active then return end
    local cb = M.active.onDismiss
    M.active = nil
    DialogView.Hide()  -- 卸载并销毁 UI 视图
    print("[DIALOG] Dismiss")
    if cb then cb() end
end

--- 是否正在显示对话框（用于判断阻塞）
---@return boolean
function M.IsBlocking()
    return M.active ~= nil
end

--- 重置（预览开始/结束时调用）
function M.Reset()
    M.active = nil
    DialogView.Hide()  -- 确保 UI 视图被清理
end

return M
